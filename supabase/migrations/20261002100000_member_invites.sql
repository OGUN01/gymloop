-- Member invites and self-linking (INV-001..INV-024). Forward-only; CI alone applies it (ADR-030).
-- Contract: openspec/changes/member-invites/proposal.md, including "Contract amendments v1.1".
-- Decisions: ADR-176 (self-linking replaces operator binding as the everyday path), ADR-052 (composite
-- tenant keys), ADR-040 (check names), ADR-037 (privileges are separate from RLS).
--
-- The design in one paragraph. A member's `members.user_id` used to be written only by the operator tool
-- (service role, no JWT subject). This file adds the invite that lets a member bind themselves: staff issue
-- an invite and hand over a link; the member signs in with Google and calls redeem_member_invite, which is
-- the ONLY session-reachable path that writes members.user_id (a trigger refuses every other one). The raw
-- token never reaches Postgres: the web handler stores and compares only its lowercase-hex SHA-256. Redeem
-- binds only when the invite is live, the member and gym are still bindable, the caller's Auth user is a
-- verified Google sign-in whose email equals the member's CURRENT email, and that Auth user is bound
-- nowhere else (D1: one account is exactly one member, ever). Redeem refusals are returned ROWS, never
-- exceptions, so the refusal audit row (which is also the throttle evidence) commits.
--
-- Statement order is docs/data-model.md's: enum, table, constraints, indexes, RLS, policies, privileges,
-- triggers, functions, then each function's privileges. Every number the contract fixes (48 hours,
-- 100 per gym-hour, 5 per member-day, 10 refusals per 15 minutes) is written once, as a named constant
-- inside the one function that applies it; MEMBER_INVITE_LIMITS in packages/shared mirrors them.

-- ---------------------------------------------------------------------------
-- 1. The status vocabulary (ADR-021: a canonical status is a Postgres enum)
-- ---------------------------------------------------------------------------

create type public.member_invite_status as enum ('pending', 'redeemed', 'revoked', 'superseded');

-- ---------------------------------------------------------------------------
-- 2. The table. Tenant path: direct (`tenant_id`). It holds ids, a hash and timestamps and no personal
--    data (INV-024). expires_at has no default: the issuing command always writes it, so a 48 hour
--    expiry cannot be bypassed by an insert that forgets it.
-- ---------------------------------------------------------------------------

create table public.member_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null,
  -- Lowercase hex SHA-256 of the token. Globally unique below: a token carries no tenant.
  token_hash text not null,
  status public.member_invite_status not null default 'pending',
  issued_by_staff_id uuid not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  closed_by_staff_id uuid,
  -- Kept for the audit trail; an Auth user deletion must not delete the invite (INV-024).
  redeemed_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint member_invites_token_hash_format_chk check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint member_invites_expiry_chk check (expires_at > issued_at),
  -- pending <=> not closed; only a redeemed invite may name a redeeming user (and may not, once that
  -- Auth user is deleted).
  constraint member_invites_closed_state_chk check (
    ((status = 'pending') = (closed_at is null))
    and (status = 'redeemed' or redeemed_user_id is null)
  ),

  -- A token carries no tenant, so the lookup by hash cannot lead with one: a deliberate non-tenant-leading
  -- unique, the fourth after gym_code, qr_sessions_token_hash_key and the impersonation open-session key
  -- (04_contract_meta names it). It is a secret's hash, so one gym can never claim a slot another needs.
  constraint member_invites_token_hash_key unique (token_hash),

  -- ADR-052: every reference to a tenant-scoped parent re-checks the tenant.
  constraint member_invites_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id),
  constraint member_invites_issued_by_staff_id_fkey
    foreign key (tenant_id, issued_by_staff_id) references public.staff (tenant_id, id),
  constraint member_invites_closed_by_staff_id_fkey
    foreign key (tenant_id, closed_by_staff_id) references public.staff (tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- 3. Indexes
-- ---------------------------------------------------------------------------

-- At most one pending invite per member, enforced under concurrent issues (INV-003).
create unique index member_invites_one_pending_key
  on public.member_invites (tenant_id, member_id) where status = 'pending';

-- Newest-invite lookup and the per-member daily issue throttle.
create index member_invites_tenant_id_member_id_issued_at_idx
  on public.member_invites (tenant_id, member_id, issued_at desc);
-- The per-gym hourly issue throttle.
create index member_invites_tenant_id_issued_at_idx
  on public.member_invites (tenant_id, issued_at);
-- Foreign-key indexes (index rule 2).
create index member_invites_tenant_id_issued_by_staff_id_idx
  on public.member_invites (tenant_id, issued_by_staff_id);
create index member_invites_tenant_id_closed_by_staff_id_idx
  on public.member_invites (tenant_id, closed_by_staff_id);
create index member_invites_redeemed_user_id_idx
  on public.member_invites (redeemed_user_id);

-- The redeem throttle counts one Auth user's recent refusals; only refusal rows are in this index.
create index audit_log_actor_user_id_occurred_at_member_invite_idx
  on public.audit_log (actor_user_id, occurred_at) where action = 'member_invite.redeem_refused';

-- INV-028: bounded member history, without broadening audit-log access.
create index audit_log_member_invite_history_idx
  on public.audit_log (tenant_id, record_type, record_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- 4. Row-level security. Read-only for the front office of the gym; every write goes through the
--    commands below. No write policy exists because authenticated holds no write grant.
-- ---------------------------------------------------------------------------

alter table public.member_invites enable row level security;

create policy member_invites_platform_select on public.member_invites
  for select to authenticated
  using ((select app.is_platform()));

create policy member_invites_tenant_select on public.member_invites
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));

revoke all on public.member_invites from anon, authenticated;
grant select on public.member_invites to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Table triggers. The standard stamp, and the support-preview guard (NAV-003) even though no session
--    can write the table: the contract names it so the table follows the same shape as its siblings.
-- ---------------------------------------------------------------------------

create trigger member_invites_touch_updated_at
  before update on public.member_invites
  for each row execute function app.touch_updated_at();

create trigger member_invites_preview_read_only
  before insert or update or delete on public.member_invites
  for each row execute function app.enforce_preview_read_only();

-- ---------------------------------------------------------------------------
-- 6. The binding guard (INV-013). Before this file, any front-office role could write members.user_id
--    directly with no audit. It is now writable only by: a postgres-owned definer command (redeem,
--    unlink), a migration or seed (also postgres), and the operator provisioning tool (service_role with
--    NO JWT subject). `current_user` is the invoking role for a trigger function, so a session role
--    (authenticated, anon, or service_role carrying a subject) is refused, owner included. The guard adds
--    no cross-table check on purpose: existing identity fixtures legitimately bind one user in several
--    tables; the one-account rule lives in redeem (ADR-176).
-- ---------------------------------------------------------------------------

create function app.enforce_member_auth_binding()
returns trigger language plpgsql security invoker set search_path = '' as $fn$
begin
  if current_user = 'postgres' or (current_user = 'service_role' and auth.uid() is null) then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.user_id is not null then
      raise exception 'Member identity binding is changed by its audited commands' using errcode = 'GL074',
        detail = 'member_binding_command_required';
    end if;
  elsif new.user_id is distinct from old.user_id then
    raise exception 'Member identity binding is changed by its audited commands' using errcode = 'GL074',
      detail = 'member_binding_command_required';
  end if;
  return new;
end
$fn$;

create trigger members_auth_binding_invariant
  before insert or update of user_id on public.members
  for each row execute function app.enforce_member_auth_binding();

-- ---------------------------------------------------------------------------
-- 7. The audit helper. audit_log is written only by an app security-definer function (INT-003); this one
--    admits exactly the seven invite actions, so a bug elsewhere cannot forge another family's row
--    through it. Nobody but the owner can execute it. It receives no token and no hash by contract.
-- ---------------------------------------------------------------------------

create function app.member_invite_audit(
  p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text,
  p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text
) returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  -- A null action must fail here, not on audit_log's not-null: `null not in (...)` is not true.
  if p_action is null or p_action not in (
    'member_invite.issued', 'member_invite.superseded', 'member_invite.revoked',
    'member_invite.redeemed', 'member_invite.redeem_refused', 'member.linked', 'member.unlinked'
  ) then
    raise exception 'Unsupported invite audit action' using errcode = '22023';
  end if;
  insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, reason)
    values (p_tenant_id, p_actor, p_role, p_action, p_record_type, p_record_id, p_before, p_after, p_reason);
end
$fn$;

-- ---------------------------------------------------------------------------
-- 8. The staff actor helper (mirrors app.checkin_gate_actor). A real, current staff member of the claimed
--    gym, in one of the named roles: no member id, no impersonation id, and the staff row must be active
--    and agree with the claims on tenant, id, user and role. Anything else is 42501, so a forged or
--    stale claim, a platform user and a support preview are all refused alike. Invoker: it needs no
--    elevation of its own, its callers are the definers below (and staff invites reuse it).
-- ---------------------------------------------------------------------------

create function app.member_invite_actor(p_roles text[])
returns table (tenant_id uuid, staff_id uuid, user_id uuid, role public.app_role)
language plpgsql stable security invoker set search_path = '' as $fn$
begin
  if auth.uid() is null or app.current_tenant_id() is null
     or app.current_staff_id() is null or app.current_member_id() is not null
     or app.current_impersonation_id() is not null
     or not coalesce(app.current_app_role() = any (p_roles), false) then
    raise exception 'Gym staff required' using errcode = '42501';
  end if;
  return query
    select s.tenant_id, s.id, s.user_id, s.role
      from public.staff s
     where s.tenant_id = app.current_tenant_id() and s.id = app.current_staff_id()
       and s.user_id = auth.uid() and s.role::text = app.current_app_role() and s.is_active;
  if not found then
    raise exception 'Active gym staff required' using errcode = '42501';
  end if;
exception when invalid_text_representation then
  -- A malformed uuid claim is a forged claim.
  raise exception 'Valid gym staff identity required' using errcode = '42501';
end
$fn$;

-- ---------------------------------------------------------------------------
-- 9. issue_member_invite. Front office only. The raw token never arrives: the handler hashes it first.
--    Check order (amendments v1.1): 42501 (role, tenant, unknown id) -> 22023 -> GL075 -> GL077 ->
--    GL076 -> GL078. Lock order: member row, then invite row (redeem takes the same order after its
--    per-account advisory lock), so a resend can never deadlock a redeem. A refusal rolls back
--    everything, so a refused resend leaves the pending invite alone and writes no audit row.
-- ---------------------------------------------------------------------------

create function public.issue_member_invite(p_member_id uuid, p_token_hash text)
returns table (invite_id uuid, expires_at timestamptz, superseded_invite_id uuid)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in MEMBER_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_ttl constant interval := interval '48 hours';
  c_tenant_issues_per_hour constant integer := 100;
  c_member_issues_per_day constant integer := 5;
  v_actor record;
  v_member public.members%rowtype;
  v_eligible boolean;
  v_now timestamptz := statement_timestamp();
  v_old_id uuid;
  v_new_id uuid;
  v_expires timestamptz;
  v_count integer;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  if p_member_id is null then
    raise exception 'Member required' using errcode = '22023';
  end if;
  -- Serialize the gym's quota before any target-row lock: distinct members share this limit.
  perform pg_advisory_xact_lock(hashtextextended('member-invite-issue:' || v_actor.tenant_id::text, 0));
  -- Scoped to the actor's gym, so another gym's member and an unknown id are the same 42501.
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = p_member_id for no key update;
  if not found then
    raise exception 'Member unavailable to this gym' using errcode = '42501';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;

  select (o.status = 'active'::public.organization_status
          or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
    into v_eligible from public.organizations o where o.id = v_actor.tenant_id;
  if v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null or not coalesce(v_eligible, false) then
    raise exception 'Member cannot be invited' using errcode = 'GL075', detail = 'member_not_invitable';
  end if;
  if v_member.user_id is not null then
    raise exception 'Member is already linked' using errcode = 'GL077', detail = 'member_already_linked';
  end if;
  -- PROV-002: one @, non-empty local part, dotted domain, no whitespace (after trimming).
  if v_member.email is null
     or btrim(v_member.email, E' \t\r\n') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Member email required' using errcode = 'GL076', detail = 'member_email_required';
  end if;

  -- Rolling windows counted from issued_at, over every status, so a revoked or superseded invite still
  -- counts: the limit bounds what staff can send, not what is currently live.
  select count(*) into v_count from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.issued_at > v_now - interval '1 hour';
  if v_count >= c_tenant_issues_per_hour then
    raise exception 'Too many invites from this gym' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;
  select count(*) into v_count from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.member_id = v_member.id and i.issued_at > v_now - interval '24 hours';
  if v_count >= c_member_issues_per_day then
    raise exception 'Too many invites for this member' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;

  -- Resend: close the live invite first (the one-pending index needs the slot), even if it has expired.
  select i.id into v_old_id from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.member_id = v_member.id and i.status = 'pending' for update;
  if v_old_id is not null then
    update public.member_invites i set status = 'superseded', closed_at = v_now where i.id = v_old_id;
  end if;

  v_expires := v_now + c_ttl;
  insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, issued_at, expires_at)
    values (v_actor.tenant_id, v_member.id, p_token_hash, v_actor.staff_id, v_now, v_expires)
    returning member_invites.id into v_new_id;

  if v_old_id is not null then
    perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member_invite.superseded',
      'member_invite', v_old_id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'superseded', 'replaced_by', v_new_id), null);
  end if;
  perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member_invite.issued',
    'member_invite', v_new_id, null,
    jsonb_build_object('member_id', v_member.id, 'expires_at', v_expires, 'superseded_invite_id', v_old_id), null);

  return query select v_new_id, v_expires, v_old_id;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 10. revoke_member_invite. Front office only. Works on any `pending` invite, including one past its
--     expiry (expiry is derived, status is what GL079 tests). An invite of another gym and an unknown id
--     are the same 42501. Member row before invite row, as everywhere.
-- ---------------------------------------------------------------------------

create function public.revoke_member_invite(p_invite_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor record;
  v_invite public.member_invites%rowtype;
  v_now timestamptz := statement_timestamp();
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  if p_invite_id is null then
    raise exception 'Invite required' using errcode = '22023';
  end if;
  select i.* into v_invite from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.id = p_invite_id;
  if not found then
    raise exception 'Invite unavailable to this gym' using errcode = '42501';
  end if;
  perform 1 from public.members m
   where m.tenant_id = v_invite.tenant_id and m.id = v_invite.member_id for no key update;
  -- Re-read under the lock: a redeem or resend that held it may have closed the invite meanwhile.
  select i.* into v_invite from public.member_invites i where i.id = p_invite_id for update;
  if v_invite.status <> 'pending'::public.member_invite_status then
    raise exception 'Invite is not pending' using errcode = 'GL079', detail = 'invite_not_pending';
  end if;
  update public.member_invites i
     set status = 'revoked', closed_at = v_now, closed_by_staff_id = v_actor.staff_id
   where i.id = v_invite.id;
  perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member_invite.revoked',
    'member_invite', v_invite.id, jsonb_build_object('status', 'pending'),
    jsonb_build_object('status', 'revoked'), null);
  return v_invite.id;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 11. peek_member_invite. The only read a signed-out visitor gets: the gym's name for a token that is
--     pending, unexpired, for an invitable member of an eligible gym; zero rows for every other cause,
--     with no column but the name. Executable by anon (the only anon-executable definer this adds), so
--     it takes a hash only, never writes, and a malformed hash is the sole error.
-- ---------------------------------------------------------------------------

create function public.peek_member_invite(p_token_hash text)
returns table (gym_name text)
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;
  return query
    select o.name::text
      from public.member_invites i
      join public.members m on m.tenant_id = i.tenant_id and m.id = i.member_id
      join public.organizations o on o.id = i.tenant_id
     where i.token_hash = p_token_hash
       and i.status = 'pending'::public.member_invite_status
       and i.expires_at > statement_timestamp()
       and m.status not in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       and m.erased_at is null
       and m.user_id is null
       and m.email is not null
       and btrim(m.email, E' \t\r\n') ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       and (o.status = 'active'::public.organization_status
            or (o.status = 'trial'::public.organization_status and o.trial_ends_at > statement_timestamp()));
end
$fn$;

-- ---------------------------------------------------------------------------
-- 12. redeem_member_invite (INV-007..INV-011). The identity-critical command.
--     * Caller must be an Auth user (42501 otherwise) and not an impersonation token (42501).
--     * Order of work: per-account advisory lock -> throttle -> token lookup -> member row lock -> invite
--       row lock (re-read) -> replay -> live-invite and member/gym state (a) -> verified Google
--       identity (b) -> email equality (c) -> account bound nowhere else (d) -> bind.
--     * The advisory key is the contract's, shared with staff invites so one account cannot be linked as
--       member and as staff at the same time.
--     * Every refusal is a returned row, audited as member_invite.redeem_refused (that row IS the
--       throttle evidence, so it must commit). All causes about the invite or the member collapse to
--       `invite_unavailable`, so the answer is no oracle on who or what exists. rate_limited writes
--       nothing and is decided before the token is looked at. Malformed input is an exception and is
--       not a refusal, so it does not feed the throttle.
-- ---------------------------------------------------------------------------

create function public.redeem_member_invite(p_token_hash text)
returns table (outcome text, gym_name text)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in MEMBER_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_failure_limit constant integer := 10;
  c_failure_window constant interval := interval '15 minutes';
  v_uid uuid;
  v_now timestamptz := statement_timestamp();
  v_recent integer;
  v_found boolean;
  v_invite public.member_invites%rowtype;
  v_member public.members%rowtype;
  v_gym_name text;
  v_gym_eligible boolean;
  v_confirmed boolean;
  v_has_google boolean;
  v_has_password boolean;
  v_provisioned boolean;
  v_outcome text;
begin
  begin
    v_uid := auth.uid();
    if v_uid is null or app.current_impersonation_id() is not null then
      raise exception 'Signed-in account required' using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    -- A malformed uuid claim is a forged claim.
    raise exception 'Signed-in account required' using errcode = '42501';
  end;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;

  -- Two concurrent redemptions by one account (or a member and a staff link) queue here, so at most one
  -- binding can ever be made for that account.
  perform pg_advisory_xact_lock(hashtextextended('identity-bind:' || v_uid::text, 0));

  select count(*) into v_recent from public.audit_log a
   where a.actor_user_id = v_uid and a.action = 'member_invite.redeem_refused'
     and a.occurred_at > v_now - c_failure_window;
  if v_recent >= c_failure_limit then
    return query select 'rate_limited'::text, null::text;
    return;
  end if;

  select i.* into v_invite from public.member_invites i where i.token_hash = p_token_hash;
  v_found := found;
  if v_found then
    select m.* into v_member from public.members m
     where m.tenant_id = v_invite.tenant_id and m.id = v_invite.member_id for no key update;
    -- Re-read under the lock; everything below decides on this version of the row.
    select i.* into v_invite from public.member_invites i where i.id = v_invite.id for update;
  end if;

  <<decide>>
  begin
    if not v_found then
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    select o.name::text,
           (o.status = 'active'::public.organization_status
            or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
      into v_gym_name, v_gym_eligible
      from public.organizations o where o.id = v_invite.tenant_id;

    -- Replay (INV-009): only the recorded redeemer, and only while the member is still bound to them.
    -- No write, and no member-status check: they are already in.
    if v_invite.status = 'redeemed'::public.member_invite_status then
      if v_invite.redeemed_user_id = v_uid and v_member.user_id = v_uid then
        return query select 'already_linked_here'::text, v_gym_name;
        return;
      end if;
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    -- (a) The invite is live and the member and gym are still bindable. A member row that already has
    -- a user_id, even this caller's, is unavailable: it cannot be bound twice.
    if v_invite.status <> 'pending'::public.member_invite_status
       or v_invite.expires_at <= v_now
       or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       or v_member.erased_at is not null
       or v_member.user_id is not null
       or not coalesce(v_gym_eligible, false) then
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    -- (b) A verified Google sign-in (PROV-006a): confirmed email, a google identity, and either
    -- operator-provisioned or no password (email-provider) identity beside it. A self-registered
    -- password account that merely added Google later is not verified.
    select u.email_confirmed_at is not null,
           exists (select 1 from auth.identities gi where gi.user_id = u.id and gi.provider = 'google'),
           exists (select 1 from auth.identities ei where ei.user_id = u.id and ei.provider = 'email'),
           coalesce(u.raw_app_meta_data ->> 'gymloop_provisioned', '') = 'true'
      into v_confirmed, v_has_google, v_has_password, v_provisioned
      from auth.users u where u.id = v_uid;
    if not coalesce(v_confirmed, false) or not coalesce(v_has_google, false)
       or not (coalesce(v_provisioned, false) or not coalesce(v_has_password, false)) then
      v_outcome := 'identity_unverified';
      exit decide;
    end if;

    -- (c) The Google identity's own email, never auth.users.email, equals the member's CURRENT email.
    -- Exact after trimming and lower-casing (no dot or plus normalisation). A blank address on either
    -- side becomes null and null never equals null, so it never matches.
    if not exists (
      select 1 from auth.identities gi
       where gi.user_id = v_uid and gi.provider = 'google'
         and nullif(lower(btrim(gi.identity_data ->> 'email', E' \t\r\n')), '')
           = nullif(lower(btrim(v_member.email, E' \t\r\n')), '')
    ) then
      v_outcome := 'email_mismatch';
      exit decide;
    end if;

    -- (d) D1: this Auth user is bound to nothing, in any gym, as member, staff or platform user,
    -- active or not. The target member's own user_id is null (checked in (a)), so any hit is another row.
    if exists (select 1 from public.members bm where bm.user_id = v_uid)
       or exists (select 1 from public.staff bs where bs.user_id = v_uid)
       or exists (select 1 from public.platform_users bp where bp.user_id = v_uid) then
      v_outcome := 'account_already_linked';
      exit decide;
    end if;

    -- Bind. The guard trigger admits this write because the function runs as its postgres owner.
    update public.members m set user_id = v_uid where m.tenant_id = v_member.tenant_id and m.id = v_member.id;
    update public.member_invites i
       set status = 'redeemed', redeemed_user_id = v_uid, closed_at = v_now
     where i.id = v_invite.id;
    perform app.member_invite_audit(v_invite.tenant_id, v_uid, 'member'::public.app_role, 'member_invite.redeemed',
      'member_invite', v_invite.id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'redeemed', 'member_id', v_member.id), null);
    perform app.member_invite_audit(v_invite.tenant_id, v_uid, 'member'::public.app_role, 'member.linked',
      'member', v_member.id, jsonb_build_object('user_linked', false),
      jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', v_invite.id), null);
    return query select 'linked'::text, v_gym_name;
    return;
  end;

  -- A refusal. The tenant and record are known only when the token resolved to an invite row; the
  -- audit row carries the outcome and nothing about the member (and, by construction, no token or hash).
  perform app.member_invite_audit(case when v_found then v_invite.tenant_id end, v_uid, null::public.app_role,
    'member_invite.redeem_refused', 'member_invite', case when v_found then v_invite.id end, null,
    jsonb_build_object('outcome', v_outcome), null);
  return query select v_outcome, null::text;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 13. unlink_member_identity (INV-014). Owner or manager only. Check order: role -> member visible
--     (42501) -> reason (22023) -> bound (GL080), so a role that may not unlink learns nothing about
--     whether the member is linked. Deleting the former user's sessions bounds how long their token can
--     keep reading to the 15 minute jwt expiry. A pending invite is deliberately left alone.
-- ---------------------------------------------------------------------------

create function public.unlink_member_identity(p_member_id uuid, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor record;
  v_member public.members%rowtype;
  v_reason text;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager']);
  if p_member_id is null then
    raise exception 'Member required' using errcode = '22023';
  end if;
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = p_member_id for no key update;
  if not found then
    raise exception 'Member unavailable to this gym' using errcode = '42501';
  end if;
  v_reason := btrim(p_reason, E' \t\r\n');
  if v_reason is null or char_length(v_reason) not between 3 and 200 then
    raise exception 'A reason of 3 to 200 characters is required' using errcode = '22023';
  end if;
  if v_member.user_id is null then
    raise exception 'Member is not linked' using errcode = 'GL080', detail = 'member_not_linked';
  end if;
  update public.members m set user_id = null where m.tenant_id = v_member.tenant_id and m.id = v_member.id;
  delete from auth.sessions s where s.user_id = v_member.user_id;
  perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member.unlinked',
    'member', v_member.id, jsonb_build_object('user_linked', true),
    jsonb_build_object('user_linked', false), v_reason);
end
$fn$;

-- ---------------------------------------------------------------------------
-- 14. read_member_app_access (INV-015). The console's one read of a member's app-access state, front
--     office only (support preview is refused: the console shows the panel read-only then). Precedence:
--     linked, then unavailable, then the NEWEST invite (a closed newest invite counts as none; an older
--     pending one is never consulted), else not_invited. Expiry is derived from expires_at, never stored.
-- ---------------------------------------------------------------------------

create function public.read_member_app_access(p_member_id uuid)
returns table (state text, invite_id uuid, issued_at timestamptz, expires_at timestamptz, linked_at timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  v_actor record;
  v_member public.members%rowtype;
  v_invite public.member_invites%rowtype;
  v_found boolean;
  v_linked_at timestamptz;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  if p_member_id is null then
    raise exception 'Member required' using errcode = '22023';
  end if;
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = p_member_id;
  if not found then
    raise exception 'Member unavailable to this gym' using errcode = '42501';
  end if;

  if v_member.user_id is not null then
    -- Null for a member the operator tool bound: that path writes no audit row (ADR-176).
    select max(a.occurred_at) into v_linked_at from public.audit_log a
     where a.tenant_id = v_member.tenant_id and a.action = 'member.linked'
       and a.record_type = 'member' and a.record_id = v_member.id;
    return query select 'linked'::text, null::uuid, null::timestamptz, null::timestamptz, v_linked_at;
    return;
  end if;
  if v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null then
    return query select 'unavailable'::text, null::uuid, null::timestamptz, null::timestamptz, null::timestamptz;
    return;
  end if;

  select i.* into v_invite from public.member_invites i
   where i.tenant_id = v_member.tenant_id and i.member_id = v_member.id
   order by i.issued_at desc, i.id desc limit 1;
  v_found := found;
  if v_found and v_invite.status = 'pending'::public.member_invite_status then
    return query select
      case when v_invite.expires_at > statement_timestamp() then 'invite_pending' else 'invite_expired' end,
      v_invite.id, v_invite.issued_at, v_invite.expires_at, null::timestamptz;
    return;
  end if;
  return query select 'not_invited'::text, null::uuid, null::timestamptz, null::timestamptz, null::timestamptz;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 15. Ownership and privileges. Every definer is owned by postgres (BYPASSRLS, and the identity the
--     binding guard trusts). Revoke from every role first, then grant the narrow set: authenticated only,
--     plus anon for peek; the audit helper, the actor helper and the guard are executable by nobody
--     beyond the owner (a trigger function is checked at CREATE TRIGGER, not on each firing).
-- ---------------------------------------------------------------------------

create function public.read_member_invite_history(p_member_id uuid)
returns table (event_id uuid, occurred_at timestamptz, action text, actor_name text)
language plpgsql stable security definer set search_path = '' as $fn$
declare
  c_history_limit constant integer := 50;
  v_actor record;
  v_member public.members%rowtype;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  if p_member_id is null then
    raise exception 'Member required' using errcode = '22023';
  end if;
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = p_member_id;
  if not found then
    raise exception 'Member unavailable to this gym' using errcode = '42501';
  end if;

  return query
    select a.id, a.occurred_at, a.action,
           case
             when a.actor_role = 'member'::public.app_role then
               case when a.actor_user_id = v_member.user_id
                          and a.action in ('member_invite.redeemed', 'member.linked')
                    then v_member.full_name end
             else (select s.full_name from public.staff s
                    where s.tenant_id = v_actor.tenant_id and s.user_id = a.actor_user_id)
           end::text
      from public.audit_log a
     where a.tenant_id = v_actor.tenant_id
       and (
         (a.record_type = 'member_invite'
          and a.action in ('member_invite.issued', 'member_invite.superseded',
                           'member_invite.revoked', 'member_invite.redeemed')
          and exists (select 1 from public.member_invites i
                       where i.tenant_id = v_actor.tenant_id and i.member_id = v_member.id
                         and i.id = a.record_id))
         or (a.record_type = 'member' and a.record_id = v_member.id
             and a.action in ('member.linked', 'member.unlinked'))
       )
     order by a.occurred_at desc, a.id desc
     limit c_history_limit;
end
$fn$;

alter function app.member_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text) owner to postgres;
alter function public.read_member_invite_history(uuid) owner to postgres;
alter function public.issue_member_invite(uuid, text) owner to postgres;
alter function public.revoke_member_invite(uuid) owner to postgres;
alter function public.redeem_member_invite(text) owner to postgres;
alter function public.peek_member_invite(text) owner to postgres;
alter function public.unlink_member_identity(uuid, text) owner to postgres;
alter function public.read_member_app_access(uuid) owner to postgres;

revoke all on function app.member_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function app.member_invite_actor(text[]) from public, anon, authenticated, service_role;
revoke all on function app.enforce_member_auth_binding() from public, anon, authenticated, service_role;

revoke all on function public.issue_member_invite(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.revoke_member_invite(uuid) from public, anon, authenticated, service_role;
revoke all on function public.redeem_member_invite(text) from public, anon, authenticated, service_role;
revoke all on function public.peek_member_invite(text) from public, anon, authenticated, service_role;
revoke all on function public.unlink_member_identity(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.read_member_app_access(uuid) from public, anon, authenticated, service_role;
revoke all on function public.read_member_invite_history(uuid) from public, anon, authenticated, service_role;

grant execute on function public.issue_member_invite(uuid, text) to authenticated;
grant execute on function public.revoke_member_invite(uuid) to authenticated;
grant execute on function public.redeem_member_invite(text) to authenticated;
grant execute on function public.peek_member_invite(text) to anon, authenticated;
grant execute on function public.unlink_member_identity(uuid, text) to authenticated;
grant execute on function public.read_member_app_access(uuid) to authenticated;
grant execute on function public.read_member_invite_history(uuid) to authenticated;
