-- Staff invites and self-linking (STI-001..STI-018). Forward-only; CI alone applies it (ADR-030), after
-- 20261002100000_member_invites.sql, whose app.member_invite_actor this file reuses.
-- Contract: openspec/changes/staff-invites/proposal.md, including "Contract amendments v1.1", which inherits
-- openspec/changes/member-invites/proposal.md and its amendments. Decisions: ADR-176 (INV + STI batch),
-- ADR-052 (composite tenant keys), ADR-040 (check names), ADR-037 (privileges are separate from RLS).
--
-- The design in one paragraph. A gym owner creates a staff row and hands the person an invite; the person
-- signs in with Google and calls redeem_staff_invite, which sets staff.user_id and nothing else (the role is
-- the owner's choice and lives on the row). staff.user_id was writable only by the platform (GL049, owner
-- links) and by the operator tool; this file adds exactly two more admitted writes, a link and an unlink of
-- a NON-owner row, and only for a postgres-owned definer command that names the write in a transaction-local
-- setting (app.staff_binding_command). A session cannot use the setting: the trigger also demands
-- current_user = 'postgres', which no session role is. The existing staff_auth_binding_session_revoke trigger
-- deletes the user's auth.sessions on any user_id change, so a link or unlink ends the person's session and
-- they sign in once more. Owners are never linked or unlinked here: only /platform links gym owners.
-- Redeem refusals are returned ROWS (never exceptions) so the refusal audit row, which is also the
-- throttle evidence, commits. The raw token never reaches Postgres; only its lowercase-hex SHA-256 does.
--
-- Statement order is docs/data-model.md's: enum, table, constraints, indexes, RLS, policies, privileges,
-- triggers, functions, then each function's privileges. Every number the contract fixes (48 hours,
-- 30 per gym-hour, 5 per staff-row-day, 10 refusals per 15 minutes) is written once, as a named constant
-- inside the one function that applies it; STAFF_INVITE_LIMITS in packages/shared mirrors them.

-- ---------------------------------------------------------------------------
-- 1. The status vocabulary (ADR-021: a canonical status is a Postgres enum)
-- ---------------------------------------------------------------------------

create type public.staff_invite_status as enum ('pending', 'redeemed', 'revoked', 'superseded');

-- ---------------------------------------------------------------------------
-- 2. The table. Tenant path: direct (`tenant_id`). It holds ids, a hash and timestamps and no personal
--    data (STI-017). expires_at has no default: the issuing commands always write it, so a 48 hour
--    expiry cannot be bypassed by an insert that forgets it.
-- ---------------------------------------------------------------------------

create table public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  staff_id uuid not null,
  -- Lowercase hex SHA-256 of the token. Globally unique below: a token carries no tenant.
  token_hash text not null,
  status public.staff_invite_status not null default 'pending',
  issued_by_staff_id uuid not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  closed_by_staff_id uuid,
  -- Kept for the audit trail; an Auth user deletion must not delete the invite (STI-017).
  redeemed_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint staff_invites_token_hash_format_chk check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint staff_invites_expiry_chk check (expires_at > issued_at),
  -- pending <=> not closed; only a redeemed invite may name a redeeming user (and may not, once that
  -- Auth user is deleted).
  constraint staff_invites_closed_state_chk check (
    ((status = 'pending') = (closed_at is null))
    and (status = 'redeemed' or redeemed_user_id is null)
  ),

  -- A token carries no tenant, so the lookup by hash cannot lead with one: a deliberate non-tenant-leading
  -- unique (a secret's hash, so one gym can never claim a slot another needs; 04_contract_meta names it).
  constraint staff_invites_token_hash_key unique (token_hash),

  -- ADR-052: every reference to a tenant-scoped parent re-checks the tenant.
  constraint staff_invites_staff_id_fkey
    foreign key (tenant_id, staff_id) references public.staff (tenant_id, id),
  constraint staff_invites_issued_by_staff_id_fkey
    foreign key (tenant_id, issued_by_staff_id) references public.staff (tenant_id, id),
  constraint staff_invites_closed_by_staff_id_fkey
    foreign key (tenant_id, closed_by_staff_id) references public.staff (tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- 3. Indexes
-- ---------------------------------------------------------------------------

-- At most one pending invite per staff row, enforced under concurrent issues (STI-002).
create unique index staff_invites_one_pending_key
  on public.staff_invites (tenant_id, staff_id) where status = 'pending';

-- Newest-invite lookup and the per-row daily issue throttle.
create index staff_invites_tenant_id_staff_id_issued_at_idx
  on public.staff_invites (tenant_id, staff_id, issued_at desc);
-- The per-gym hourly issue throttle.
create index staff_invites_tenant_id_issued_at_idx
  on public.staff_invites (tenant_id, issued_at);
-- Foreign-key indexes (index rule 2).
create index staff_invites_tenant_id_issued_by_staff_id_idx
  on public.staff_invites (tenant_id, issued_by_staff_id);
create index staff_invites_tenant_id_closed_by_staff_id_idx
  on public.staff_invites (tenant_id, closed_by_staff_id);
create index staff_invites_redeemed_user_id_idx
  on public.staff_invites (redeemed_user_id);

-- The redeem throttle counts one Auth user's recent refusals; only refusal rows are in this index.
create index audit_log_actor_user_id_occurred_at_staff_invite_idx
  on public.audit_log (actor_user_id, occurred_at) where action = 'staff_invite.redeem_refused';

-- ---------------------------------------------------------------------------
-- 4. Row-level security. Read-only for the gym owner of the gym (and platform roles, per the
--    04_contract_meta pair rule); every write goes through the commands below. No write policy exists
--    because authenticated holds no write grant.
-- ---------------------------------------------------------------------------

alter table public.staff_invites enable row level security;

create policy staff_invites_platform_select on public.staff_invites
  for select to authenticated
  using ((select app.is_platform()));

create policy staff_invites_tenant_select on public.staff_invites
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'gym_owner');

revoke all on public.staff_invites from anon, authenticated;
grant select on public.staff_invites to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Table triggers. The standard stamp, and the support-preview guard (NAV-003) even though no session
--    can write the table, so the table follows the same shape as its siblings.
-- ---------------------------------------------------------------------------

create trigger staff_invites_touch_updated_at
  before update on public.staff_invites
  for each row execute function app.touch_updated_at();

create trigger staff_invites_preview_read_only
  before insert or update or delete on public.staff_invites
  for each row execute function app.enforce_preview_read_only();

-- ---------------------------------------------------------------------------
-- 6. The binding guard (STI-006, GL049). `create or replace` of the existing function with ONE addition:
--    an early return for exactly two command-keyed shapes. Everything else in the body is the Phase 6
--    definition (20260915100011) unchanged, so owner linking by /platform, deactivate_gym_owner, the
--    operator tool and every denied shape behave exactly as before.
--
--    An admitted write must satisfy ALL of:
--      * current_user = 'postgres' (a definer command, never a session role),
--      * the transaction-local setting app.staff_binding_command equals the command for THIS row and user,
--      * the row is a manager, front desk or trainer (an owner row is never admitted), before and after,
--      * the statement changes no column but user_id (and the trigger-maintained updated_at),
--      * link: user_id null -> not null, row active before and after; unlink: user_id not null -> null.
--    A statement that fails any term falls through to the old logic: a session gets GL049, a postgres-run
--    definer with a JWT subject that is not a platform admin is refused by the platform check, and a caller
--    without a JWT subject keeps its trust.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_staff_auth_binding()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  v_protected boolean;
  v_trusted boolean := false;
  v_command text;
begin
  if tg_op = 'INSERT' then
    v_protected := new.user_id is not null;
  else
    if new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id then
      raise exception 'Invalid platform input'
        using errcode = '22023', detail = 'invalid_platform_input';
    end if;

    -- The two staff-invite shapes (STI-006). Absent or empty setting: nothing is admitted here.
    v_command := nullif(current_setting('app.staff_binding_command', true), '');
    if v_command is not null
       and current_user = 'postgres'
       and old.role in ('gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role)
       and new.role in ('gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role)
       and (to_jsonb(new) - 'user_id' - 'updated_at') = (to_jsonb(old) - 'user_id' - 'updated_at')
       and (
         (old.user_id is null and new.user_id is not null
          and old.is_active and new.is_active
          and v_command = 'link:' || new.user_id::text)
         or
         (old.user_id is not null and new.user_id is null
          and v_command = 'unlink:' || old.user_id::text)
       ) then
      return new;
    end if;

    v_protected := new.user_id is distinct from old.user_id
      or (
        old.user_id is not null
        and (new.role = 'gym_owner'::public.app_role)
          is distinct from (old.role = 'gym_owner'::public.app_role)
      );
  end if;

  if v_protected then
    if current_user = 'postgres' then
      if auth.uid() is not null then
        perform app.require_platform_super_admin();
      end if;
      v_trusted := true;
    elsif current_user = 'service_role' and auth.uid() is null then
      v_trusted := true;
    end if;

    if not v_trusted then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and auth.uid() is not null
     and new.user_id is distinct from old.user_id then
    if old.role <> 'gym_owner'::public.app_role
       or new.role <> 'gym_owner'::public.app_role
       or not old.is_active
       or not new.is_active
       or new.user_id is null
       or not exists (select 1 from auth.users u where u.id = new.user_id)
       or exists (
         select 1 from public.platform_users pu where pu.user_id = new.user_id
       )
       or exists (
         select 1
           from public.staff s
          where s.tenant_id = new.tenant_id
            and s.user_id = new.user_id
            and s.id <> new.id
       ) then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;
  return new;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 7. The audit helper. audit_log is written only by an app security-definer function (INT-003); this one
--    admits exactly the eight staff-invite actions, so a bug elsewhere cannot forge another family's row
--    through it. Nobody but the owner can execute it. It receives no token and no hash by contract.
-- ---------------------------------------------------------------------------

create function app.staff_invite_audit(
  p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text,
  p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text
) returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  -- A null action must fail here, not on audit_log's not-null: `null not in (...)` is not true.
  if p_action is null or p_action not in (
    'staff.invited', 'staff_invite.issued', 'staff_invite.superseded', 'staff_invite.revoked',
    'staff_invite.redeemed', 'staff_invite.redeem_refused', 'staff.linked', 'staff.unlinked'
  ) then
    raise exception 'Unsupported staff invite audit action' using errcode = '22023';
  end if;
  insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, reason)
    values (p_tenant_id, p_actor, p_role, p_action, p_record_type, p_record_id, p_before, p_after, p_reason);
end
$fn$;

-- ---------------------------------------------------------------------------
-- 8. invite_staff_member (STI-001). Gym owner only (app.member_invite_actor, from the INV migration).
--    Creates the staff row and its first invite in one transaction; any refusal, including a reused hash
--    failing at the invite insert, rolls the staff row back with it.
--    Check order (amendments v1.1): 42501 (actor, foreign/unknown branch) -> 22023 -> GL082 -> GL075 ->
--    GL076 -> GL081 -> GL078. The new row is created active and unlinked; the invitee never chooses a role.
-- ---------------------------------------------------------------------------

create function public.invite_staff_member(
  p_full_name text, p_email text, p_phone text, p_role public.app_role, p_branch_id uuid, p_token_hash text
) returns table (staff_id uuid, invite_id uuid, expires_at timestamptz)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in STAFF_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_ttl constant interval := interval '48 hours';
  c_tenant_issues_per_hour constant integer := 30;
  v_actor record;
  v_eligible boolean;
  v_now timestamptz := statement_timestamp();
  v_name text := btrim(p_full_name, E' \t\r\n');
  v_phone text := nullif(btrim(p_phone, E' \t\r\n'), '');
  v_email text := btrim(p_email, E' \t\r\n');
  v_staff_id uuid;
  v_invite_id uuid;
  v_expires timestamptz;
  v_count integer;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  -- Scoped to the owner's gym, so another gym's branch and an unknown id are the same 42501.
  if p_branch_id is not null and not exists (
    select 1 from public.branches b where b.tenant_id = v_actor.tenant_id and b.id = p_branch_id
  ) then
    raise exception 'Branch unavailable to this gym' using errcode = '42501';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;
  if v_name is null or v_name = '' then
    raise exception 'A name is required' using errcode = '22023';
  end if;
  if v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'A phone number in E.164 form is required' using errcode = '22023';
  end if;

  -- Only the three roles an owner may hand out; a null role is not one of them.
  if p_role is null or p_role not in (
    'gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role
  ) then
    raise exception 'Role is not invitable' using errcode = 'GL082', detail = 'staff_role_not_invitable';
  end if;

  select (o.status = 'active'::public.organization_status
          or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
    into v_eligible from public.organizations o where o.id = v_actor.tenant_id;
  if not coalesce(v_eligible, false) then
    raise exception 'Gym cannot invite staff' using errcode = 'GL075', detail = 'staff_not_invitable';
  end if;

  -- PROV-002: one @, non-empty local part, dotted domain, no whitespace (after trimming).
  if v_email is null or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Staff email required' using errcode = 'GL076', detail = 'staff_email_required';
  end if;

  -- Create and resend share the gym quota; always take this lock before email or target-row locks.
  perform pg_advisory_xact_lock(hashtextextended('staff-invite-issue:' || v_actor.tenant_id::text, 0));

  -- One address, one staff row per gym (any row, active or not). The lock closes the window between the
  -- check and the insert for two concurrent invites of the same address.
  perform pg_advisory_xact_lock(
    hashtextextended('staff-invite-email:' || v_actor.tenant_id::text || ':' || lower(v_email), 0));
  if exists (
    select 1 from public.staff s
     where s.tenant_id = v_actor.tenant_id and lower(btrim(s.email, E' \t\r\n')) = lower(v_email)
  ) then
    raise exception 'Staff email already used in this gym' using errcode = 'GL081', detail = 'staff_email_taken';
  end if;

  -- The new row has no invite history, so only the gym-hour window can bite here.
  select count(*) into v_count from public.staff_invites i
   where i.tenant_id = v_actor.tenant_id and i.issued_at > v_now - interval '1 hour';
  if v_count >= c_tenant_issues_per_hour then
    raise exception 'Too many invites from this gym' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;

  insert into public.staff (tenant_id, user_id, branch_id, role, full_name, phone, email, is_active)
    values (v_actor.tenant_id, null, p_branch_id, p_role, v_name, v_phone, v_email, true)
    returning staff.id into v_staff_id;

  v_expires := v_now + c_ttl;
  insert into public.staff_invites (tenant_id, staff_id, token_hash, issued_by_staff_id, issued_at, expires_at)
    values (v_actor.tenant_id, v_staff_id, p_token_hash, v_actor.staff_id, v_now, v_expires)
    returning staff_invites.id into v_invite_id;

  perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff.invited',
    'staff', v_staff_id, null, jsonb_build_object('role', p_role, 'branch_id', p_branch_id), null);
  perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff_invite.issued',
    'staff_invite', v_invite_id, null,
    jsonb_build_object('staff_id', v_staff_id, 'expires_at', v_expires, 'superseded_invite_id', null), null);

  return query select v_staff_id, v_invite_id, v_expires;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 9. issue_staff_invite (STI-002, STI-003). Gym owner only. The raw token never arrives: the handler
--    hashes it first. Check order (amendments v1.1): 42501 (actor, unknown/foreign id) -> 22023 -> GL075
--    (inactive, owner role or gym not eligible) -> GL077 -> GL076 -> GL078. Lock order: staff row, then
--    invite row (redeem takes the same order after its per-account advisory lock), so a resend can never
--    deadlock a redeem. A refusal rolls back everything, so a refused resend leaves the pending invite
--    alone and writes no audit row.
-- ---------------------------------------------------------------------------

create function public.issue_staff_invite(p_staff_id uuid, p_token_hash text)
returns table (invite_id uuid, expires_at timestamptz, superseded_invite_id uuid)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in STAFF_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_ttl constant interval := interval '48 hours';
  c_tenant_issues_per_hour constant integer := 30;
  c_staff_issues_per_day constant integer := 5;
  v_actor record;
  v_staff public.staff%rowtype;
  v_eligible boolean;
  v_now timestamptz := statement_timestamp();
  v_old_id uuid;
  v_new_id uuid;
  v_expires timestamptz;
  v_count integer;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  if p_staff_id is null then
    raise exception 'Staff row required' using errcode = '22023';
  end if;
  -- The same quota lock as create, taken before the staff row so all issue paths agree on order.
  perform pg_advisory_xact_lock(hashtextextended('staff-invite-issue:' || v_actor.tenant_id::text, 0));
  -- Scoped to the owner's gym, so another gym's row and an unknown id are the same 42501.
  select s.* into v_staff from public.staff s
   where s.tenant_id = v_actor.tenant_id and s.id = p_staff_id for no key update;
  if not found then
    raise exception 'Staff row unavailable to this gym' using errcode = '42501';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;

  select (o.status = 'active'::public.organization_status
          or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
    into v_eligible from public.organizations o where o.id = v_actor.tenant_id;
  if not v_staff.is_active
     or v_staff.role not in ('gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role)
     or not coalesce(v_eligible, false) then
    raise exception 'Staff row cannot be invited' using errcode = 'GL075', detail = 'staff_not_invitable';
  end if;
  if v_staff.user_id is not null then
    raise exception 'Staff row is already linked' using errcode = 'GL077', detail = 'staff_already_linked';
  end if;
  -- PROV-002: one @, non-empty local part, dotted domain, no whitespace (after trimming).
  if v_staff.email is null
     or btrim(v_staff.email, E' \t\r\n') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Staff email required' using errcode = 'GL076', detail = 'staff_email_required';
  end if;

  -- Rolling windows counted from issued_at, over every status, so a revoked or superseded invite still
  -- counts: the limit bounds what the owner can send, not what is currently live.
  select count(*) into v_count from public.staff_invites i
   where i.tenant_id = v_actor.tenant_id and i.issued_at > v_now - interval '1 hour';
  if v_count >= c_tenant_issues_per_hour then
    raise exception 'Too many invites from this gym' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;
  select count(*) into v_count from public.staff_invites i
   where i.tenant_id = v_actor.tenant_id and i.staff_id = v_staff.id and i.issued_at > v_now - interval '24 hours';
  if v_count >= c_staff_issues_per_day then
    raise exception 'Too many invites for this staff row' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;

  -- Resend: close the live invite first (the one-pending index needs the slot), even if it has expired.
  select i.id into v_old_id from public.staff_invites i
   where i.tenant_id = v_actor.tenant_id and i.staff_id = v_staff.id and i.status = 'pending' for update;
  if v_old_id is not null then
    update public.staff_invites i set status = 'superseded', closed_at = v_now where i.id = v_old_id;
  end if;

  v_expires := v_now + c_ttl;
  insert into public.staff_invites (tenant_id, staff_id, token_hash, issued_by_staff_id, issued_at, expires_at)
    values (v_actor.tenant_id, v_staff.id, p_token_hash, v_actor.staff_id, v_now, v_expires)
    returning staff_invites.id into v_new_id;

  if v_old_id is not null then
    perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff_invite.superseded',
      'staff_invite', v_old_id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'superseded', 'replaced_by', v_new_id), null);
  end if;
  perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff_invite.issued',
    'staff_invite', v_new_id, null,
    jsonb_build_object('staff_id', v_staff.id, 'expires_at', v_expires, 'superseded_invite_id', v_old_id), null);

  return query select v_new_id, v_expires, v_old_id;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 10. revoke_staff_invite (STI-002). Gym owner only. Works on any `pending` invite, including one past
--     its expiry (expiry is derived, status is what GL079 tests). An invite of another gym and an unknown
--     id are the same 42501. Staff row before invite row, as everywhere.
-- ---------------------------------------------------------------------------

create function public.revoke_staff_invite(p_invite_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor record;
  v_invite public.staff_invites%rowtype;
  v_now timestamptz := statement_timestamp();
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  if p_invite_id is null then
    raise exception 'Invite required' using errcode = '22023';
  end if;
  select i.* into v_invite from public.staff_invites i
   where i.tenant_id = v_actor.tenant_id and i.id = p_invite_id;
  if not found then
    raise exception 'Invite unavailable to this gym' using errcode = '42501';
  end if;
  perform 1 from public.staff s
   where s.tenant_id = v_invite.tenant_id and s.id = v_invite.staff_id for no key update;
  -- Re-read under the lock: a redeem or resend that held it may have closed the invite meanwhile.
  select i.* into v_invite from public.staff_invites i where i.id = p_invite_id for update;
  if v_invite.status <> 'pending'::public.staff_invite_status then
    raise exception 'Invite is not pending' using errcode = 'GL079', detail = 'invite_not_pending';
  end if;
  update public.staff_invites i
     set status = 'revoked', closed_at = v_now, closed_by_staff_id = v_actor.staff_id
   where i.id = v_invite.id;
  perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff_invite.revoked',
    'staff_invite', v_invite.id, jsonb_build_object('status', 'pending'),
    jsonb_build_object('status', 'revoked'), null);
  return v_invite.id;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 11. peek_staff_invite (STI-007). The only read a signed-out visitor gets: the gym's name and the role on
--     the row for a token that is pending, unexpired, for an active unlinked manager/front-desk/trainer row
--     with a plausible address, issued by a gym owner who is still active, in an eligible gym; zero rows for
--     every other cause. Executable by anon, so it takes a hash only, never writes, and a malformed hash is
--     its sole error.
-- ---------------------------------------------------------------------------

create function public.peek_staff_invite(p_token_hash text)
returns table (gym_name text, staff_role public.app_role)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;
  return query
    select o.name::text, s.role
      from public.staff_invites i
      join public.staff s on s.tenant_id = i.tenant_id and s.id = i.staff_id
      join public.staff iss on iss.tenant_id = i.tenant_id and iss.id = i.issued_by_staff_id
      join public.organizations o on o.id = i.tenant_id
     where i.token_hash = p_token_hash
       and i.status = 'pending'::public.staff_invite_status
       and i.expires_at > statement_timestamp()
       and s.is_active
       and s.role in ('gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role)
       and s.user_id is null
       and s.email is not null
       and btrim(s.email, E' \t\r\n') ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       and iss.role = 'gym_owner'::public.app_role
       and iss.is_active
       and (o.status = 'active'::public.organization_status
            or (o.status = 'trial'::public.organization_status and o.trial_ends_at > statement_timestamp()));
end
$fn$;

-- ---------------------------------------------------------------------------
-- 12. redeem_staff_invite (STI-004, STI-005, STI-006). The identity-critical command; INV-007 with staff
--     for member.
--     * Caller must be an Auth user (42501 otherwise) and not an impersonation token (42501).
--     * Order of work: per-account advisory lock (the INV key, so one account cannot be linked as member
--       and as staff at once) -> shared throttle -> token lookup -> staff row lock -> invite row lock
--       (re-read) -> replay -> live-invite and row/gym/issuer state (a) -> verified Google identity (b)
--       -> email equality (c) -> account bound nowhere else (d) -> bind.
--     * (a) also requires the issuing staff row to still be an active gym_owner of the tenant: an invite
--       outlives neither its issuer's deactivation nor demotion.
--     * The link is the ONLY thing written to the staff row: role, branch, name and email stay the
--       owner's. The binding is admitted by the GL049 guard through app.staff_binding_command, set
--       immediately before the update and cleared right after.
--     * Every refusal is a returned row, audited as staff_invite.redeem_refused (that row IS throttle
--       evidence, so it must commit). All causes about the invite or the row collapse to
--       `invite_unavailable`, so the answer is no oracle on who or what exists. rate_limited writes nothing
--       and is decided before the token is looked at. Malformed input is an exception and not a refusal,
--       so it does not feed the throttle.
-- ---------------------------------------------------------------------------

create function public.redeem_staff_invite(p_token_hash text)
returns table (outcome text, gym_name text, staff_role public.app_role)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in STAFF_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_failure_limit constant integer := 10;
  c_failure_window constant interval := interval '15 minutes';
  v_uid uuid;
  v_now timestamptz := statement_timestamp();
  v_recent integer;
  v_found boolean;
  v_invite public.staff_invites%rowtype;
  v_staff public.staff%rowtype;
  v_gym_name text;
  v_gym_eligible boolean;
  v_issuer_ok boolean;
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
  -- binding can ever be made for that account. Taken before any row lock.
  perform pg_advisory_xact_lock(hashtextextended('identity-bind:' || v_uid::text, 0));

  -- The refusal budget is shared by both families: alternating member and staff tokens does not double it.
  -- Each family has its own partial index, so the two counts are taken separately.
  select (select count(*) from public.audit_log a
           where a.actor_user_id = v_uid and a.action = 'member_invite.redeem_refused'
             and a.occurred_at > v_now - c_failure_window)
       + (select count(*) from public.audit_log a
           where a.actor_user_id = v_uid and a.action = 'staff_invite.redeem_refused'
             and a.occurred_at > v_now - c_failure_window)
    into v_recent;
  if v_recent >= c_failure_limit then
    return query select 'rate_limited'::text, null::text, null::public.app_role;
    return;
  end if;

  select i.* into v_invite from public.staff_invites i where i.token_hash = p_token_hash;
  v_found := found;
  if v_found then
    select s.* into v_staff from public.staff s
     where s.tenant_id = v_invite.tenant_id and s.id = v_invite.staff_id for no key update;
    -- Re-read under the lock; everything below decides on this version of the row.
    select i.* into v_invite from public.staff_invites i where i.id = v_invite.id for update;
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

    -- Replay: only the recorded redeemer, and only while the row is still bound to them. No write, and no
    -- row-state check: they are already in. After an unlink the same token is simply unavailable.
    if v_invite.status = 'redeemed'::public.staff_invite_status then
      if v_invite.redeemed_user_id = v_uid and v_staff.user_id = v_uid then
        return query select 'already_linked_here'::text, v_gym_name, v_staff.role;
        return;
      end if;
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    -- The issuer is read at redemption, not at issue: demoting or deactivating the owner who sent an
    -- invite voids it.
    select exists (
      select 1 from public.staff iss
       where iss.tenant_id = v_invite.tenant_id and iss.id = v_invite.issued_by_staff_id
         and iss.role = 'gym_owner'::public.app_role and iss.is_active
    ) into v_issuer_ok;

    -- (a) The invite is live and the row, gym and issuer are still bindable. A row that already has a
    -- user_id, even this caller's, is unavailable: it cannot be bound twice. An owner row is never
    -- bindable here.
    if v_invite.status <> 'pending'::public.staff_invite_status
       or v_invite.expires_at <= v_now
       or not v_staff.is_active
       or v_staff.role not in ('gym_manager'::public.app_role, 'front_desk'::public.app_role, 'trainer'::public.app_role)
       or v_staff.user_id is not null
       or not coalesce(v_gym_eligible, false)
       or not coalesce(v_issuer_ok, false) then
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

    -- (c) The Google identity's own email, never auth.users.email, equals the row's CURRENT email.
    -- Exact after trimming and lower-casing (no dot or plus normalisation). A blank address on either
    -- side becomes null and null never equals null, so it never matches.
    if not exists (
      select 1 from auth.identities gi
       where gi.user_id = v_uid and gi.provider = 'google'
         and nullif(lower(btrim(gi.identity_data ->> 'email', E' \t\r\n')), '')
           = nullif(lower(btrim(v_staff.email, E' \t\r\n')), '')
    ) then
      v_outcome := 'email_mismatch';
      exit decide;
    end if;

    -- (d) D1: this Auth user is bound to nothing, in any gym, as member, staff or platform user,
    -- active or not. The target row's own user_id is null (checked in (a)), so any hit is another row.
    if exists (select 1 from public.members bm where bm.user_id = v_uid)
       or exists (select 1 from public.staff bs where bs.user_id = v_uid)
       or exists (select 1 from public.platform_users bp where bp.user_id = v_uid) then
      v_outcome := 'account_already_linked';
      exit decide;
    end if;

    -- Bind. The GL049 guard admits exactly this write: we run as postgres, the setting names this link,
    -- and nothing but user_id changes. The setting is cleared the moment the write is done.
    perform set_config('app.staff_binding_command', 'link:' || v_uid::text, true);
    update public.staff s set user_id = v_uid where s.tenant_id = v_staff.tenant_id and s.id = v_staff.id;
    perform set_config('app.staff_binding_command', '', true);
    update public.staff_invites i
       set status = 'redeemed', redeemed_user_id = v_uid, closed_at = v_now
     where i.id = v_invite.id;
    perform app.staff_invite_audit(v_invite.tenant_id, v_uid, v_staff.role, 'staff_invite.redeemed',
      'staff_invite', v_invite.id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'redeemed', 'staff_id', v_staff.id), null);
    perform app.staff_invite_audit(v_invite.tenant_id, v_uid, v_staff.role, 'staff.linked',
      'staff', v_staff.id, jsonb_build_object('user_linked', false),
      jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', v_invite.id, 'role', v_staff.role), null);
    return query select 'linked'::text, v_gym_name, v_staff.role;
    return;
  end;

  -- A refusal. The tenant and record are known only when the token resolved to an invite row; the
  -- audit row carries the outcome and nothing about the person (and, by construction, no token or hash).
  perform app.staff_invite_audit(case when v_found then v_invite.tenant_id end, v_uid, null::public.app_role,
    'staff_invite.redeem_refused', 'staff_invite', case when v_found then v_invite.id end, null,
    jsonb_build_object('outcome', v_outcome), null);
  return query select v_outcome, null::text, null::public.app_role;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 13. unlink_staff_identity (STI-008). Gym owner only (unlike INV, a manager may not unlink). Check order:
--     role -> staff row visible, and not an owner row (42501: only the platform path touches owner rows,
--     the caller's own included) -> reason (22023) -> bound (GL080), so a caller that may not unlink
--     learns nothing about whether the row is linked. The existing staff_auth_binding_session_revoke
--     trigger deletes the former user's sessions, bounding how long their token can keep reading to the
--     15 minute jwt expiry. A pending invite is deliberately left alone.
-- ---------------------------------------------------------------------------

create function public.unlink_staff_identity(p_staff_id uuid, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor record;
  v_staff public.staff%rowtype;
  v_reason text;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  if p_staff_id is null then
    raise exception 'Staff row required' using errcode = '22023';
  end if;
  select s.* into v_staff from public.staff s
   where s.tenant_id = v_actor.tenant_id and s.id = p_staff_id for no key update;
  if not found or v_staff.role = 'gym_owner'::public.app_role then
    raise exception 'Staff row unavailable to this command' using errcode = '42501';
  end if;
  v_reason := btrim(p_reason, E' \t\r\n');
  if v_reason is null or char_length(v_reason) not between 3 and 200 then
    raise exception 'A reason of 3 to 200 characters is required' using errcode = '22023';
  end if;
  if v_staff.user_id is null then
    raise exception 'Staff row is not linked' using errcode = 'GL080', detail = 'staff_not_linked';
  end if;
  perform set_config('app.staff_binding_command', 'unlink:' || v_staff.user_id::text, true);
  update public.staff s set user_id = null where s.tenant_id = v_staff.tenant_id and s.id = v_staff.id;
  perform set_config('app.staff_binding_command', '', true);
  perform app.staff_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'staff.unlinked',
    'staff', v_staff.id, jsonb_build_object('user_linked', true),
    jsonb_build_object('user_linked', false), v_reason);
end
$fn$;

-- ---------------------------------------------------------------------------
-- 14. read_staff_app_access (STI-009). The console's one read of a staff row's app-access state, gym
--     owner only (a support preview is refused: the console shows the panel read-only then). Precedence:
--     linked (any non-null user_id, including a platform-linked owner row), then unavailable (inactive row
--     or owner role), then the NEWEST invite (a closed newest invite counts as none; an older pending one
--     is never consulted), else not_invited. Expiry is derived from expires_at, never stored.
-- ---------------------------------------------------------------------------

create function public.read_staff_app_access(p_staff_id uuid)
returns table (state text, invite_id uuid, issued_at timestamptz, expires_at timestamptz, linked_at timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  v_actor record;
  v_staff public.staff%rowtype;
  v_invite public.staff_invites%rowtype;
  v_found boolean;
  v_linked_at timestamptz;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  if p_staff_id is null then
    raise exception 'Staff row required' using errcode = '22023';
  end if;
  select s.* into v_staff from public.staff s
   where s.tenant_id = v_actor.tenant_id and s.id = p_staff_id;
  if not found then
    raise exception 'Staff row unavailable to this gym' using errcode = '42501';
  end if;

  if v_staff.user_id is not null then
    -- Null for a row the operator tool or the platform bound: those paths write no staff.linked row.
    select max(a.occurred_at) into v_linked_at from public.audit_log a
     where a.tenant_id = v_staff.tenant_id and a.action = 'staff.linked'
       and a.record_type = 'staff' and a.record_id = v_staff.id;
    return query select 'linked'::text, null::uuid, null::timestamptz, null::timestamptz, v_linked_at;
    return;
  end if;
  if not v_staff.is_active or v_staff.role = 'gym_owner'::public.app_role then
    return query select 'unavailable'::text, null::uuid, null::timestamptz, null::timestamptz, null::timestamptz;
    return;
  end if;

  select i.* into v_invite from public.staff_invites i
   where i.tenant_id = v_staff.tenant_id and i.staff_id = v_staff.id
   order by i.issued_at desc, i.id desc limit 1;
  v_found := found;
  if v_found and v_invite.status = 'pending'::public.staff_invite_status then
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
--     plus anon for peek; the audit helper is executable by nobody beyond the owner. The amended guard
--     function keeps the owner and privileges it already has (create or replace preserves them).
-- ---------------------------------------------------------------------------

alter function app.staff_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text) owner to postgres;
alter function public.invite_staff_member(text, text, text, public.app_role, uuid, text) owner to postgres;
alter function public.issue_staff_invite(uuid, text) owner to postgres;
alter function public.revoke_staff_invite(uuid) owner to postgres;
alter function public.redeem_staff_invite(text) owner to postgres;
alter function public.peek_staff_invite(text) owner to postgres;
alter function public.unlink_staff_identity(uuid, text) owner to postgres;
alter function public.read_staff_app_access(uuid) owner to postgres;

revoke all on function app.staff_invite_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb, text)
  from public, anon, authenticated, service_role;

revoke all on function public.invite_staff_member(text, text, text, public.app_role, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.issue_staff_invite(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.revoke_staff_invite(uuid) from public, anon, authenticated, service_role;
revoke all on function public.redeem_staff_invite(text) from public, anon, authenticated, service_role;
revoke all on function public.peek_staff_invite(text) from public, anon, authenticated, service_role;
revoke all on function public.unlink_staff_identity(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.read_staff_app_access(uuid) from public, anon, authenticated, service_role;

grant execute on function public.invite_staff_member(text, text, text, public.app_role, uuid, text) to authenticated;
grant execute on function public.issue_staff_invite(uuid, text) to authenticated;
grant execute on function public.revoke_staff_invite(uuid) to authenticated;
grant execute on function public.redeem_staff_invite(text) to authenticated;
grant execute on function public.peek_staff_invite(text) to anon, authenticated;
grant execute on function public.unlink_staff_identity(uuid, text) to authenticated;
grant execute on function public.read_staff_app_access(uuid) to authenticated;
