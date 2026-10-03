-- member_freeze_requests — SLF-001..018 (Wave D, frozen 2026-10-03)
--
-- Member-originated freeze requests that ride the existing desk pause as their
-- only commercial effect. Frozen authority:
-- openspec/changes/member-self-service/proposal.md (FROZEN 2026-10-03), with
-- the owner-resolved allowance semantics of SLF-012 (calendar year of the
-- requested interval's start day, member-scoped across memberships, each
-- interval counted whole in its start year, gym `max_freeze_days_per_year`
-- only, only approved non-rejected pauses count, rejection consumes nothing)
-- and the OPEN-016 allowance-enforcement gap recorded as a documented residual
-- (D-SLF-2): the database-enforced budget the desk route lacks is NOT built
-- here; SLF's own serialization and the checks below are the SLF-side guard.
--
-- Refusal vocabulary (no new GL number — the frozen proposal reuses the shared
-- classes): 42501 actor/authorization, 22023 value/shape, 23514 invariant,
-- 23505 uniqueness, GL066 state/stale/overlap/bound/terminal/expiry, GL067
-- allowance insufficiency, GL068 idempotency-key conflict, P0002 invisible
-- target.
--
-- Shape notes:
--   * Both tables enable RLS and carry ZERO privileges for anon and
--     authenticated (SLF-014): application access is only through the nine
--     public RPCs. The request policies below are defense in depth for the
--     standard platform read branch and the two application predicates; with
--     no SELECT grant they are unreachable directly, exactly as the contract
--     says ("application reads use the revalidating safe RPCs").
--   * The five narrow definers are `request_member_freeze`,
--     `cancel_member_freeze_request` and the three reads; the four desk
--     commands are invoker wrappers whose request-table work happens in two
--     private definer helpers (`app.slf_freeze_prepare` / `app.slf_freeze_finish`)
--     while the source `membership_pauses` write happens IN THE WRAPPER, under
--     the caller's own RLS and the unchanged `app.enforce_pause_decision`
--     trigger — the frozen "source INSERT through unchanged RLS/guards".
--   * The additive source invariant (`app.enforce_freeze_source_consistency`)
--     is a definer trigger on `membership_pauses` so it binds EVERY writer,
--     trusted ones included: a pause linked to a freeze request may not drift
--     from the request's frozen scope, and may not be decided while its linked
--     request is closed (cancelled/expired). An ordinary desk pause links to
--     nothing and is untouched. Lock order needs no extra rule for direct
--     source writers: they never acquire this feature's advisory lock, so no
--     cycle can form between them and the RPC path.
--   * `membership_pauses` gains `unique (tenant_id, id)` — the ADR-052 pattern —
--     because the frozen composite FK to it needs a referenceable key.

create type public.member_freeze_request_status as enum (
  'requested', 'desk_submitted', 'approved', 'rejected', 'cancelled', 'expired'
);

-- ---------------------------------------------------------------------------
-- 0. Referenceable key for the composite source FK (ADR-052 pattern).
-- ---------------------------------------------------------------------------

alter table public.membership_pauses
  add constraint membership_pauses_tenant_id_id_key unique (tenant_id, id);

-- ---------------------------------------------------------------------------
-- 1. member_freeze_requests
-- ---------------------------------------------------------------------------

create table public.member_freeze_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null,
  membership_id uuid not null,
  requested_by_user_id uuid not null references auth.users (id),
  request_key uuid not null,
  starts_on date not null,
  ends_on date not null,
  reason text not null
    constraint member_freeze_requests_reason_chk
      check (reason <> '' and char_length(btrim(reason)) >= 1
             and char_length(reason) <= 2000),
  status public.member_freeze_request_status not null default 'requested',
  revision bigint not null default 1
    constraint member_freeze_requests_revision_chk check (revision >= 1),
  source_pause_id uuid,
  adopted_by_staff_id uuid,
  adopted_at timestamptz,
  decided_by_staff_id uuid,
  decided_at timestamptz,
  decision_reason text
    constraint member_freeze_requests_decision_reason_chk
      check (decision_reason is null or (char_length(btrim(decision_reason)) >= 3
             and char_length(decision_reason) <= 200)),
  cancelled_by_user_id uuid references auth.users (id),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint member_freeze_requests_dates_chk
    check (ends_on >= starts_on),

  -- The adoption pair exists exactly when a source pause exists.
  constraint member_freeze_requests_source_adopted_pair_chk
    check ((source_pause_id is null) = (adopted_by_staff_id is null)
           and (source_pause_id is null) = (adopted_at is null)),

  -- An approval grants an actual pause; a rejection needs its recorded reason.
  constraint member_freeze_requests_approved_requires_source_chk
    check (status <> 'approved' or source_pause_id is not null),
  constraint member_freeze_requests_approved_requires_decision_chk
    check (status <> 'approved'
           or (decided_by_staff_id is not null and decided_at is not null)),
  constraint member_freeze_requests_rejected_requires_decision_chk
    check (status <> 'rejected'
           or (decided_by_staff_id is not null and decided_at is not null
               and decision_reason is not null)),

  -- A cancellation is the original member's act; terminal states are closed;
  -- open states are not.
  constraint member_freeze_requests_cancelled_requires_canceller_chk
    check (status <> 'cancelled' or cancelled_by_user_id is not null),
  constraint member_freeze_requests_terminal_closed_chk
    check ((status in ('approved','rejected','cancelled','expired'))
           = (closed_at is not null)),

  -- A `requested` row carries none of the later facts; a `desk_submitted` row
  -- carries its source link.
  constraint member_freeze_requests_requested_clean_chk
    check (status <> 'requested'
           or (source_pause_id is null and decided_by_staff_id is null
               and decided_at is null and cancelled_by_user_id is null)),
  constraint member_freeze_requests_desk_submitted_linked_chk
    check (status <> 'desk_submitted' or source_pause_id is not null),

  -- The decision pair is one fact.
  constraint member_freeze_requests_decision_pair_chk
    check ((decided_by_staff_id is null) = (decided_at is null)),

  -- Composite tenant FKs (ADR-052): members, memberships, the source pause and
  -- the two staff references.
  constraint member_freeze_requests_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id),
  constraint member_freeze_requests_tenant_id_membership_id_fkey
    foreign key (tenant_id, membership_id)
    references public.memberships (tenant_id, id),
  constraint member_freeze_requests_tenant_id_source_pause_id_fkey
    foreign key (tenant_id, source_pause_id)
    references public.membership_pauses (tenant_id, id),
  constraint member_freeze_requests_tenant_id_adopted_by_staff_id_fkey
    foreign key (tenant_id, adopted_by_staff_id) references public.staff (tenant_id, id),
  constraint member_freeze_requests_tenant_id_decided_by_staff_id_fkey
    foreign key (tenant_id, decided_by_staff_id) references public.staff (tenant_id, id),

  constraint member_freeze_requests_tenant_id_request_key_key
    unique (tenant_id, request_key),
  constraint member_freeze_requests_tenant_id_id_key unique (tenant_id, id)
);

-- A source pause binds at most one request, and only when linked.
create unique index member_freeze_requests_tenant_source_pause_key
  on public.member_freeze_requests (tenant_id, source_pause_id)
  where source_pause_id is not null;

create index member_freeze_requests_tenant_member_created_idx
  on public.member_freeze_requests (tenant_id, member_id, created_at desc, id desc);
create index member_freeze_requests_tenant_membership_span_idx
  on public.member_freeze_requests (tenant_id, membership_id, starts_on, ends_on);
create index member_freeze_requests_tenant_status_created_idx
  on public.member_freeze_requests (tenant_id, status, created_at desc, id desc);
create index member_freeze_requests_tenant_subject_idx
  on public.member_freeze_requests (tenant_id, requested_by_user_id);
create index member_freeze_requests_tenant_adopter_idx
  on public.member_freeze_requests (tenant_id, adopted_by_staff_id);
create index member_freeze_requests_tenant_decider_idx
  on public.member_freeze_requests (tenant_id, decided_by_staff_id);
-- Row lookup for the additive source invariant (per-row, must be index-driven).
create index member_freeze_requests_source_pause_idx
  on public.member_freeze_requests (source_pause_id)
  where source_pause_id is not null;

-- ---------------------------------------------------------------------------
-- 2. member_freeze_commands — the durable replay evidence.
-- ---------------------------------------------------------------------------

create table public.member_freeze_commands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  request_id uuid not null,
  actor_user_id uuid not null references auth.users (id),
  command_key uuid not null,
  action text not null
    constraint member_freeze_commands_action_chk
      check (action in ('create','adopt','approve','reject','cancel','expire')),
  facts jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),

  constraint member_freeze_commands_tenant_id_request_id_fkey
    foreign key (tenant_id, request_id)
    references public.member_freeze_requests (tenant_id, id),

  constraint member_freeze_commands_tenant_id_command_key_key
    unique (tenant_id, command_key)
);

create index member_freeze_commands_tenant_request_idx
  on public.member_freeze_commands (tenant_id, request_id);
create index member_freeze_commands_tenant_actor_idx
  on public.member_freeze_commands (tenant_id, actor_user_id);

-- ---------------------------------------------------------------------------
-- 3. Row invariants — frozen fields, the status map, revision monotonicity,
--    and no deletes. Every writer, trusted ones included.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_member_freeze_request_row()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'member freeze requests are immutable evidence and cannot be deleted'
      using errcode = '23514';
  end if;

  -- Always-frozen identity/scope facts (SLF-014).
  if new.id          is distinct from old.id
     or new.tenant_id           is distinct from old.tenant_id
     or new.member_id           is distinct from old.member_id
     or new.membership_id       is distinct from old.membership_id
     or new.requested_by_user_id is distinct from old.requested_by_user_id
     or new.request_key         is distinct from old.request_key
     or new.starts_on           is distinct from old.starts_on
     or new.ends_on             is distinct from old.ends_on
     or new.reason              is distinct from old.reason
     or new.created_at          is distinct from old.created_at then
    raise exception 'member freeze request refused: the request identity, scope and reason are frozen'
      using errcode = '23514';
  end if;

  -- Source/adoption facts freeze on first assignment.
  if old.source_pause_id is not null
     and (new.source_pause_id is distinct from old.source_pause_id
          or new.adopted_by_staff_id is distinct from old.adopted_by_staff_id
          or new.adopted_at is distinct from old.adopted_at) then
    raise exception 'member freeze request refused: the source pause and adoption facts are frozen once linked'
      using errcode = '23514';
  end if;

  -- Decision facts freeze on first assignment.
  if old.decided_at is not null
     and (new.decided_by_staff_id is distinct from old.decided_by_staff_id
          or new.decided_at is distinct from old.decided_at
          or new.decision_reason is distinct from old.decision_reason) then
    raise exception 'member freeze request refused: the decision facts are frozen once recorded'
      using errcode = '23514';
  end if;

  if old.cancelled_by_user_id is not null
     and new.cancelled_by_user_id is distinct from old.cancelled_by_user_id then
    raise exception 'member freeze request refused: the cancelling subject is frozen once recorded'
      using errcode = '23514';
  end if;

  if old.closed_at is not null
     and new.closed_at is distinct from old.closed_at then
    raise exception 'member freeze request refused: the closure stamp is frozen once recorded'
      using errcode = '23514';
  end if;

  -- The status map: requested -> desk_submitted | rejected | cancelled | expired;
  -- desk_submitted -> approved | rejected | cancelled | expired; terminal is
  -- final (SLF-005/008/009/010).
  if old.status = 'requested'
     and new.status not in ('requested','desk_submitted','rejected','cancelled','expired') then
    raise exception 'member freeze request refused: a requested request may only be adopted, rejected, cancelled or expired'
      using errcode = '23514';
  end if;
  if old.status = 'desk_submitted'
     and new.status not in ('desk_submitted','approved','rejected','cancelled','expired') then
    raise exception 'member freeze request refused: a desk_submitted request may only be approved, rejected, cancelled or expired'
      using errcode = '23514';
  end if;
  if old.status in ('approved','rejected','cancelled','expired')
     and new.status is distinct from old.status then
    raise exception 'member freeze request refused: a decided request is terminal'
      using errcode = '23514';
  end if;

  -- Revision moves exactly once per material transition (SLF-014).
  if (new.status is distinct from old.status)
     or (new.source_pause_id is distinct from old.source_pause_id)
     or (new.adopted_by_staff_id is distinct from old.adopted_by_staff_id)
     or (new.adopted_at is distinct from old.adopted_at)
     or (new.decided_by_staff_id is distinct from old.decided_by_staff_id)
     or (new.decided_at is distinct from old.decided_at)
     or (new.decision_reason is distinct from old.decision_reason)
     or (new.cancelled_by_user_id is distinct from old.cancelled_by_user_id)
     or (new.closed_at is distinct from old.closed_at) then
    if new.revision is distinct from old.revision + 1 then
      raise exception 'member freeze request refused: a material transition moves the revision exactly once'
        using errcode = '23514';
    end if;
  elsif new.revision is distinct from old.revision then
    raise exception 'member freeze request refused: the revision only moves with a material transition'
      using errcode = '23514';
  end if;

  return new;
end;
$fn$;

create trigger member_freeze_requests_enforce_row
  before update on public.member_freeze_requests
  for each row execute function app.enforce_member_freeze_request_row();

create trigger member_freeze_requests_touch_updated_at
  before update on public.member_freeze_requests
  for each row execute function app.touch_updated_at();

create trigger member_freeze_requests_no_delete
  before delete on public.member_freeze_requests
  for each row execute function app.enforce_member_freeze_request_row();

-- The replay ledger is append-only evidence for every writer (SLF-013/014).
create or replace function app.enforce_member_freeze_command_immutable()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'member freeze commands are durable replay evidence and cannot be deleted'
      using errcode = '23514';
  end if;
  raise exception 'member freeze commands are immutable for every writer'
    using errcode = '23514';
end;
$fn$;

create trigger member_freeze_commands_enforce_immutable
  before update or delete on public.member_freeze_commands
  for each row
execute function app.enforce_member_freeze_command_immutable();

-- ---------------------------------------------------------------------------
-- 4. The additive source invariant on `membership_pauses` (SLF-014). Definer so
--    it binds trusted writers too; it reads nothing else and touches nothing.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_freeze_source_consistency()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_request public.member_freeze_requests;
begin
  select r.* into v_request
    from public.member_freeze_requests r
   where r.source_pause_id = new.id
   limit 1;

  if v_request.id is null then
    return new;  -- an ordinary desk pause: none of this applies
  end if;

  -- Exact link/scope agreement: the linked pause may never drift from the
  -- request's frozen dates or membership.
  if new.membership_id is distinct from v_request.membership_id
     or new.starts_on is distinct from v_request.starts_on
     or new.ends_on is distinct from v_request.ends_on then
    raise exception 'membership pause refused: this pause is linked to a member freeze request and may not leave the requested scope'
      using errcode = '23514';
  end if;

  -- No deciding a linked closed/ineffective request.
  if (new.approved_at is not null or new.rejected_at is not null)
     and v_request.status in ('cancelled','expired') then
    raise exception 'membership pause refused: its linked member freeze request is closed, so the pause decision is refused'
      using errcode = '23514';
  end if;

  return new;
end;
$fn$;

create trigger membership_pauses_freeze_source_consistency
  after insert or update on public.membership_pauses
  for each row execute function app.enforce_freeze_source_consistency();

-- ---------------------------------------------------------------------------
-- 5. RLS, privileges and policies.
-- ---------------------------------------------------------------------------

alter table public.member_freeze_requests enable row level security;
alter table public.member_freeze_commands enable row level security;

revoke all on public.member_freeze_requests, public.member_freeze_commands
  from public, anon, authenticated;

-- Defense in depth: unreachable while the revoke above stands, but the
-- predicates state who WOULD see what, and the platform read branch is the
-- standard shape.
create policy member_freeze_requests_member_select
  on public.member_freeze_requests for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and member_id = (select app.current_member_id()));

create policy member_freeze_requests_tenant_select
  on public.member_freeze_requests for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.is_front_office()));

create policy member_freeze_requests_platform_select
  on public.member_freeze_requests for select to authenticated
  using ((select app.is_platform()));

-- member_freeze_commands carries no policy at all: no application surface
-- exists (SLF-014).

-- ---------------------------------------------------------------------------
-- 6. Private helpers (schema `app`, not exposed through the Data API).
-- ---------------------------------------------------------------------------

-- Validates the original member actor and returns the member id. Mirrors
-- app.announcement_member_actor: claims first, then the live row.
create or replace function app.slf_member_actor()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_member public.members;
begin
  if auth.uid() is null
     or app.current_tenant_id() is null
     or app.current_app_role() is distinct from 'member'
     or app.current_member_id() is null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'Member freeze authority unavailable' using errcode = '42501';
  end if;

  select * into v_member
    from public.members m
   where m.tenant_id = app.current_tenant_id()
     and m.id = app.current_member_id();

  if v_member.id is null
     or v_member.user_id is distinct from auth.uid()
     or v_member.erased_at is not null
     or v_member.status in ('blocked','cancelled') then
    raise exception 'Member freeze authority unavailable' using errcode = '42501';
  end if;

  if not exists (select 1 from public.organizations o
                  where o.id = v_member.tenant_id and o.status = 'active') then
    raise exception 'Member freeze authority unavailable' using errcode = '42501';
  end if;

  return v_member.id;
end
$fn$;

-- Validates the original front-office staff actor and returns the staff id.
create or replace function app.slf_front_office_staff()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_staff public.staff;
begin
  if auth.uid() is null
     or app.current_tenant_id() is null
     or not coalesce(app.is_front_office(), false)
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Freeze desk authority unavailable' using errcode = '42501';
  end if;

  select * into v_staff
    from public.staff s
   where s.tenant_id = app.current_tenant_id()
     and s.id = app.current_staff_id();

  if v_staff.id is null
     or not v_staff.is_active
     or v_staff.user_id is distinct from auth.uid() then
    raise exception 'Freeze desk authority unavailable' using errcode = '42501';
  end if;

  return v_staff.id;
end
$fn$;

-- Whether an open request is ALREADY ineffective (SLF-010): its own start day
-- has elapsed, or the member or the target membership has become unavailable.
-- Shared verbatim by the expire gate (which requires it), the adopt/approve
-- gates (which refuse it — effective expiration applies at guards even if
-- closure is not materialized) and the effective-open/overlap predicates in
-- creation (an ineffective open row reserves nothing). Reads stay non-writing.
create or replace function app.slf_freeze_ineffective(
  p_request public.member_freeze_requests, p_today date
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $fn$
  select p_request.starts_on < p_today
     or exists (
       select 1
         from public.members m
        where m.tenant_id = p_request.tenant_id
          and m.id = p_request.member_id
          and (m.erased_at is not null or m.status in ('blocked','cancelled'))
     )
     or not exists (
       select 1
         from public.memberships m2
        where m2.tenant_id = p_request.tenant_id
          and m2.id = p_request.membership_id
          and m2.member_id = p_request.member_id
          and m2.status in ('active','frozen')
          and (m2.ends_on is null or m2.ends_on >= p_today)
     )
$fn$;

-- The SLF serialization lock: one resource per tenant+member.
create or replace function app.slf_freeze_lock(p_tenant_id uuid, p_member_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select pg_catalog.pg_advisory_xact_lock(
    ('x' || substr(pg_catalog.md5(p_tenant_id::text || ':' || p_member_id::text), 1, 16))::bit(64)::bigint)
$fn$;

-- Append one audit event. Called only from postgres-owned code.
create or replace function app.slf_freeze_audit(
  p_tenant_id uuid, p_actor uuid, p_role text, p_action text,
  p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if p_action not in ('member_freeze.requested','member_freeze.adopted',
                      'member_freeze.approved','member_freeze.rejected',
                      'member_freeze.cancelled','member_freeze.expired') then
    raise exception 'Unsupported member freeze audit action' using errcode = '22023';
  end if;

  insert into public.audit_log
    (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, reason)
  values
    (p_tenant_id, p_actor, p_role::public.app_role, p_action,
     'member_freeze_request', p_record_id, p_before, p_after, p_reason);
end
$fn$;

-- ---------------------------------------------------------------------------
-- 7. The four invoker wrappers share one prepare/finish pair.
-- ---------------------------------------------------------------------------

-- Prepares a desk command: actor revalidation, target load and tenancy,
-- the serialization lock, the replay ledger check, then the state/revision
-- (and, for approval, overlap and allowance) validation. Performs no writes.
create or replace function app.slf_freeze_prepare(
  p_action text, p_request_id uuid, p_expected_revision bigint,
  p_command_key uuid, p_facts jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff_id   uuid;
  v_request    public.member_freeze_requests;
  v_command    public.member_freeze_commands;
  v_today      date;
  v_settings   public.organization_settings;
  v_used_days  integer;
  v_proposed   integer;
begin
  if p_action not in ('adopt','approve','reject','expire') then
    raise exception 'Unsupported member freeze command' using errcode = '22023';
  end if;

  -- Revalidate the original caller (a direct authenticated call to this helper
  -- grants nothing extra: it writes nothing and reads only what the staff
  -- queue read already exposes).
  v_staff_id := app.slf_front_office_staff();

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id;

  if v_request.id is null then
    raise exception 'Member freeze request unavailable' using errcode = 'P0002';
  end if;
  if v_request.tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Freeze desk authority unavailable' using errcode = '42501';
  end if;

  perform app.slf_freeze_lock(v_request.tenant_id, v_request.member_id);

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id
   for update;

  -- Replay ledger: an exact same-actor, same-facts retry returns the original
  -- result read-only; anything else under the key conflicts (SLF-013).
  select * into v_command
    from public.member_freeze_commands c
   where c.tenant_id = v_request.tenant_id
     and c.command_key = p_command_key;

  if v_command.id is not null then
    if v_command.action = p_action
       and v_command.actor_user_id = auth.uid()
       and v_command.facts = p_facts then
      return jsonb_build_object('replayed', true, 'result', v_command.result);
    end if;
    raise exception 'Member freeze command key conflict' using errcode = 'GL068';
  end if;

  -- Stale revision refuses before any effect (SLF-013).
  if p_expected_revision is distinct from v_request.revision then
    raise exception 'Member freeze request stale'
      using errcode = 'GL066',
      detail = format('expected revision %s, current revision %s',
                           p_expected_revision, v_request.revision);
  end if;

  -- State gates per action.
  if p_action = 'adopt' and v_request.status <> 'requested' then
    raise exception 'Member freeze request state refuses adoption' using errcode = 'GL066';
  end if;
  if p_action = 'approve' and v_request.status <> 'desk_submitted' then
    raise exception 'Member freeze request state refuses approval' using errcode = 'GL066';
  end if;
  if p_action in ('reject','expire')
     and v_request.status not in ('requested','desk_submitted') then
    raise exception 'Member freeze request is not open' using errcode = 'GL066';
  end if;

  v_today := app.gym_today(v_request.tenant_id);

  -- Expiry exists to close an ALREADY ineffective open request (SLF-010). A
  -- future-dated request on a live member and target is refused.
  if p_action = 'expire'
     and not app.slf_freeze_ineffective(v_request, v_today) then
    raise exception 'Member freeze request is not yet ineffective; only an ineffective open request can be expired'
      using errcode = 'GL066';
  end if;

  -- Effective expiration applies at the adoption and approval guards too, even
  -- when closure has not been materialized: an elapsed-start or
  -- member/target-unavailable request is refused (GL066) without shifting its
  -- requested dates and without materializing closure on the desk path.
  if p_action in ('adopt','approve')
     and app.slf_freeze_ineffective(v_request, v_today) then
    raise exception 'Member freeze request is effectively expired and can no longer be adopted or approved'
      using errcode = 'GL066';
  end if;

  -- Overlap recheck under serialization, excluding this request's own linked
  -- pause (SLF-005). Applies to adopt (before the source is created) and to
  -- approve (an intervening desk pause may have appeared).
  if p_action in ('adopt','approve') then
    if exists (
      select 1
        from public.member_freeze_requests r2
       where r2.tenant_id = v_request.tenant_id
         and r2.member_id = v_request.member_id
         and r2.id <> v_request.id
         and r2.status in ('requested','desk_submitted')
         and r2.ends_on >= v_today
         and r2.starts_on <= v_request.ends_on
         and v_request.starts_on <= r2.ends_on
    ) or exists (
      select 1
        from public.membership_pauses p
        join public.memberships m on m.id = p.membership_id
       where m.tenant_id = v_request.tenant_id
         and m.member_id = v_request.member_id
         and p.rejected_at is null
         and p.id is distinct from v_request.source_pause_id
         and p.starts_on <= v_request.ends_on
         and v_request.starts_on <= p.ends_on
    ) then
      raise exception 'Member freeze request overlaps an effective pause or request'
        using errcode = 'GL066';
    end if;
  end if;

  -- The frozen annual allowance recheck happens at final approval only
  -- (SLF-012): calendar year of the requested start day, member-scoped across
  -- memberships, each interval whole in its start year, gym setting only.
  -- Creation and adoption never reach this branch.
  if p_action = 'approve' then
    select * into v_settings
      from public.organization_settings s
     where s.tenant_id = v_request.tenant_id;

    if v_settings.tenant_id is null or v_settings.max_freeze_days_per_year is null then
      raise exception 'Freeze allowance unavailable for this gym' using errcode = 'GL066';
    end if;

    select coalesce(sum(p.ends_on - p.starts_on + 1), 0)
      into v_used_days
      from public.membership_pauses p
      join public.memberships m on m.id = p.membership_id
     where m.tenant_id = v_request.tenant_id
       and m.member_id = v_request.member_id
       and p.approved_at is not null
       and date_part('year', p.starts_on) = date_part('year', v_request.starts_on);

    v_proposed := v_request.ends_on - v_request.starts_on + 1;

    if v_used_days + v_proposed > v_settings.max_freeze_days_per_year then
      raise exception 'Freeze allowance exhausted for this year'
        using errcode = 'GL067',
        detail = format('used %s days, proposed %s days, allowance %s',
                             v_used_days, v_proposed,
                             v_settings.max_freeze_days_per_year);
    end if;
  end if;

  return jsonb_build_object(
    'replayed', false,
    'request', jsonb_build_object(
      'id', v_request.id,
      'tenant_id', v_request.tenant_id,
      'member_id', v_request.member_id,
      'membership_id', v_request.membership_id,
      'starts_on', v_request.starts_on,
      'ends_on', v_request.ends_on,
      'reason', v_request.reason,
      'status', v_request.status::text,
      'revision', v_request.revision::text,
      'source_pause_id', v_request.source_pause_id,
      'adopted_by_staff_id', v_request.adopted_by_staff_id
    )
  );
end
$fn$;

-- Applies the request transition, appends the replay-ledger row and the audit
-- event, all under the lock the same transaction already holds. Revalidates
-- the actor and the exact current source-row outcome so a direct call grants
-- nothing extra.
create or replace function app.slf_freeze_finish(
  p_action text, p_request_id uuid, p_command_key uuid,
  p_source_pause_id uuid, p_decision_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff_id  uuid;
  v_member_id uuid;
  v_request   public.member_freeze_requests;
  v_pause     public.membership_pauses;
  v_before    jsonb;
  v_result    jsonb;
  v_effective text;
  v_today     date;
begin
  if p_action not in ('adopt','approve','reject','expire') then
    raise exception 'Unsupported member freeze command' using errcode = '22023';
  end if;

  v_staff_id := app.slf_front_office_staff();

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id
   for update;

  if v_request.id is null
     or v_request.tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Member freeze request unavailable' using errcode = 'P0002';
  end if;

  v_member_id := v_request.member_id;
  v_before := pg_catalog.to_jsonb(v_request);

  if p_action = 'adopt' then
    if v_request.status <> 'requested' then
      raise exception 'Member freeze request state refuses adoption' using errcode = 'GL066';
    end if;
    -- The wrapper created the source pause in the caller's own context; this
    -- helper only links the pause the caller just made.
    select * into v_pause
      from public.membership_pauses p
     where p.id = p_source_pause_id;
    if v_pause.id is null
       or v_pause.tenant_id is distinct from v_request.tenant_id
       or v_pause.membership_id is distinct from v_request.membership_id
       or v_pause.starts_on is distinct from v_request.starts_on
       or v_pause.ends_on is distinct from v_request.ends_on
       or v_pause.requested_by_staff_id is distinct from v_staff_id
       or v_pause.approved_at is not null
       or v_pause.rejected_at is not null then
      raise exception 'Member freeze adoption source mismatch' using errcode = '23514';
    end if;

    update public.member_freeze_requests r
       set status = 'desk_submitted',
           source_pause_id = v_pause.id,
           adopted_by_staff_id = v_staff_id,
           adopted_at = pg_catalog.now(),
           revision = r.revision + 1
     where r.id = v_request.id
     returning * into v_request;

    v_result := jsonb_build_object(
      'request_id', v_request.id, 'status', v_request.status::text,
      'revision', v_request.revision::text, 'source_pause_id', v_pause.id,
      'replayed', false);

    insert into public.member_freeze_commands
      (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
    values
      (gen_random_uuid(), v_request.tenant_id, v_request.id, auth.uid(),
       p_command_key, 'adopt',
       jsonb_build_object('request_id', v_request.id),
       v_result);

    perform app.slf_freeze_audit(
      v_request.tenant_id, auth.uid(), app.current_app_role(),
      'member_freeze.adopted', v_request.id,
      v_before - 'updated_at', pg_catalog.to_jsonb(v_request) - 'updated_at', null);

  elsif p_action = 'approve' then
    if v_request.status <> 'desk_submitted' then
      raise exception 'Member freeze request state refuses approval' using errcode = 'GL066';
    end if;
    select * into v_pause
      from public.membership_pauses p
     where p.id = v_request.source_pause_id;
    if v_pause.id is null
       or v_pause.approved_at is null
       or v_pause.approved_by_staff_id is distinct from v_staff_id
       or v_pause.rejected_at is not null then
      raise exception 'Member freeze approval source mismatch' using errcode = '23514';
    end if;

    update public.member_freeze_requests r
       set status = 'approved',
           decided_by_staff_id = v_staff_id,
           decided_at = pg_catalog.now(),
           closed_at = pg_catalog.now(),
           revision = r.revision + 1
     where r.id = v_request.id
     returning * into v_request;

    v_today := app.gym_today(v_request.tenant_id);
    v_effective := case
      when v_today > v_pause.ends_on then 'completed'
      when v_today < v_pause.starts_on then 'scheduled'
      else 'paused'
    end;

    v_result := jsonb_build_object(
      'request_id', v_request.id, 'status', v_request.status::text,
      'revision', v_request.revision::text, 'source_pause_id', v_pause.id,
      'effective_state', v_effective, 'replayed', false);

    insert into public.member_freeze_commands
      (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
    values
      (gen_random_uuid(), v_request.tenant_id, v_request.id, auth.uid(),
       p_command_key, 'approve',
       jsonb_build_object('request_id', v_request.id),
       v_result);

    perform app.slf_freeze_audit(
      v_request.tenant_id, auth.uid(), app.current_app_role(),
      'member_freeze.approved', v_request.id,
      v_before - 'updated_at', pg_catalog.to_jsonb(v_request) - 'updated_at', null);

  elsif p_action = 'reject' then
    if v_request.status not in ('requested','desk_submitted') then
      raise exception 'Member freeze request is not open' using errcode = 'GL066';
    end if;
    if v_request.source_pause_id is not null then
      select * into v_pause
        from public.membership_pauses p
       where p.id = v_request.source_pause_id;
      if v_pause.id is null
         or v_pause.rejected_at is null
         or v_pause.approved_at is not null then
        raise exception 'Member freeze rejection source mismatch' using errcode = '23514';
      end if;
    end if;

    update public.member_freeze_requests r
       set status = 'rejected',
           decided_by_staff_id = v_staff_id,
           decided_at = pg_catalog.now(),
           decision_reason = p_decision_reason,
           closed_at = pg_catalog.now(),
           revision = r.revision + 1
     where r.id = v_request.id
     returning * into v_request;

    v_result := jsonb_build_object(
      'request_id', v_request.id, 'status', v_request.status::text,
      'revision', v_request.revision::text, 'replayed', false);

    insert into public.member_freeze_commands
      (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
    values
      (gen_random_uuid(), v_request.tenant_id, v_request.id, auth.uid(),
       p_command_key, 'reject',
       jsonb_build_object('request_id', v_request.id, 'reason', p_decision_reason),
       v_result);

    perform app.slf_freeze_audit(
      v_request.tenant_id, auth.uid(), app.current_app_role(),
      'member_freeze.rejected', v_request.id,
      v_before - 'updated_at', pg_catalog.to_jsonb(v_request) - 'updated_at',
      p_decision_reason);

  else  -- expire
    if v_request.status not in ('requested','desk_submitted') then
      raise exception 'Member freeze request is not open' using errcode = 'GL066';
    end if;

    update public.member_freeze_requests r
       set status = 'expired',
           closed_at = pg_catalog.now(),
           revision = r.revision + 1
     where r.id = v_request.id
     returning * into v_request;

    v_result := jsonb_build_object(
      'request_id', v_request.id, 'status', v_request.status::text,
      'revision', v_request.revision::text, 'replayed', false);

    insert into public.member_freeze_commands
      (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
    values
      (gen_random_uuid(), v_request.tenant_id, v_request.id, auth.uid(),
       p_command_key, 'expire',
       jsonb_build_object('request_id', v_request.id),
       v_result);

    perform app.slf_freeze_audit(
      v_request.tenant_id, auth.uid(), app.current_app_role(),
      'member_freeze.expired', v_request.id,
      v_before - 'updated_at', pg_catalog.to_jsonb(v_request) - 'updated_at', null);
  end if;

  return v_result;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 8. The nine public RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.request_member_freeze(
  p_membership_id uuid, p_starts_on date, p_ends_on date,
  p_reason text, p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member_id  uuid;
  v_membership public.memberships;
  v_request    public.member_freeze_requests;
  v_command    public.member_freeze_commands;
  v_today      date;
  v_before     jsonb;
  v_result     jsonb;
  v_facts      jsonb;
  v_reason     text;
begin
  -- Authorization first (SLF-003), then the replay ledger, then eligibility.
  v_member_id := app.slf_member_actor();

  select * into v_membership
    from public.memberships m
   where m.id = p_membership_id;

  if v_membership.id is null
     or v_membership.tenant_id is distinct from app.current_tenant_id()
     or v_membership.member_id is distinct from v_member_id then
    raise exception 'Membership unavailable for freeze requests' using errcode = '42501';
  end if;

  perform app.slf_freeze_lock(v_membership.tenant_id, v_member_id);

  v_reason := btrim(coalesce(p_reason, ''));
  v_facts := jsonb_build_object(
    'membership_id', p_membership_id,
    'starts_on', p_starts_on, 'ends_on', p_ends_on, 'reason', v_reason);

  select * into v_command
    from public.member_freeze_commands c
   where c.tenant_id = v_membership.tenant_id
     and c.command_key = p_request_key;

  if v_command.id is not null then
    if v_command.action = 'create'
       and v_command.actor_user_id = auth.uid()
       and v_command.facts = v_facts then
      return jsonb_set(v_command.result, '{replayed}', 'true'::jsonb, true);
    end if;
    raise exception 'Member freeze command key conflict' using errcode = 'GL068';
  end if;

  -- Value/shape validation (22023).
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'Member freeze interval invalid' using errcode = '22023';
  end if;
  if v_reason = '' or char_length(v_reason) > 2000 then
    raise exception 'Member freeze reason invalid' using errcode = '22023';
  end if;
  if p_request_key is null then
    raise exception 'Member freeze request key required' using errcode = '22023';
  end if;

  v_today := app.gym_today(v_membership.tenant_id);

  -- SLF-004: eligible member, own currently dated active/frozen membership,
  -- interval wholly inside the span, start no earlier than gym-local today.
  -- SLF-002: a pending membership disables freeze creation.
  if v_membership.status not in ('active','frozen') then
    raise exception 'Membership does not permit freeze requests' using errcode = '22023';
  end if;
  if v_membership.starts_on > v_today
     or (v_membership.ends_on is not null and v_membership.ends_on < v_today) then
    raise exception 'Membership is not currently dated' using errcode = '22023';
  end if;
  if p_starts_on < v_today then
    raise exception 'Member freeze cannot start in the past' using errcode = '22023';
  end if;
  if p_starts_on < v_membership.starts_on
     or (v_membership.ends_on is not null and p_ends_on > v_membership.ends_on) then
    raise exception 'Member freeze interval leaves the membership span' using errcode = '22023';
  end if;

  -- SLF-only closure materialization: an elapsed, unadopted open request of
  -- this member closes atomically here, with one expiry event, so a stale
  -- row cannot block a fresh eligible request (SLF-010).
  with closed as (
    update public.member_freeze_requests r
       set status = 'expired',
           closed_at = pg_catalog.now(),
           revision = r.revision + 1
     where r.tenant_id = v_membership.tenant_id
       and r.member_id = v_member_id
       and r.status = 'requested'
       and r.starts_on < v_today
     returning r.*
  )
  insert into public.audit_log
    (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, reason)
  select c.tenant_id, auth.uid(), app.current_app_role(),
         'member_freeze.expired', 'member_freeze_request', c.id,
         null, pg_catalog.to_jsonb(c) - 'updated_at', null
  from closed c;

  -- One EFFECTIVE open request per member (SLF_LIMITS): elapsed-start or
  -- member/target-unavailable rows reserve nothing even while still open --
  -- exclusion only; the closure CTE above stays requested-only.
  if exists (
    select 1
      from public.member_freeze_requests r
     where r.tenant_id = v_membership.tenant_id
       and r.member_id = v_member_id
       and r.status in ('requested','desk_submitted')
       and not app.slf_freeze_ineffective(r, v_today)
  ) then
    raise exception 'Member already has an open freeze request' using errcode = 'GL066';
  end if;

  -- Inclusive overlap against EFFECTIVE open requests and undecided/approved
  -- source pauses of this member (SLF-005); adjacent intervals share no date.
  if exists (
    select 1
      from public.member_freeze_requests r
     where r.tenant_id = v_membership.tenant_id
       and r.member_id = v_member_id
       and r.status in ('requested','desk_submitted')
       and not app.slf_freeze_ineffective(r, v_today)
       and r.starts_on <= p_ends_on
       and p_starts_on <= r.ends_on
  ) or exists (
    select 1
      from public.membership_pauses p
      join public.memberships m on m.id = p.membership_id
     where m.tenant_id = v_membership.tenant_id
       and m.member_id = v_member_id
       and p.rejected_at is null
       and p.starts_on <= p_ends_on
       and p_starts_on <= p.ends_on
  ) then
    raise exception 'Member freeze request overlaps an effective pause or request'
      using errcode = 'GL066';
  end if;

  insert into public.member_freeze_requests
    (tenant_id, member_id, membership_id, requested_by_user_id,
     request_key, starts_on, ends_on, reason)
  values
    (v_membership.tenant_id, v_member_id, v_membership.id, auth.uid(),
     p_request_key, p_starts_on, p_ends_on, v_reason)
  returning * into v_request;

  v_result := jsonb_build_object(
    'request_id', v_request.id, 'status', v_request.status::text,
    'revision', v_request.revision::text, 'replayed', false);

  insert into public.member_freeze_commands
    (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
  values
    (gen_random_uuid(), v_membership.tenant_id, v_request.id, auth.uid(),
     p_request_key, 'create', v_facts, v_result);

  perform app.slf_freeze_audit(
    v_membership.tenant_id, auth.uid(), app.current_app_role(),
    'member_freeze.requested', v_request.id,
    null, pg_catalog.to_jsonb(v_request) - 'updated_at', null);

  return v_result;
end
$fn$;

create or replace function public.cancel_member_freeze_request(
  p_request_id uuid, p_command_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member_id uuid;
  v_request   public.member_freeze_requests;
  v_command   public.member_freeze_commands;
  v_before    jsonb;
  v_result    jsonb;
  v_facts     jsonb;
begin
  v_member_id := app.slf_member_actor();

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id;

  if v_request.id is null then
    raise exception 'Member freeze request unavailable' using errcode = 'P0002';
  end if;
  if v_request.tenant_id is distinct from app.current_tenant_id()
     or v_request.member_id is distinct from v_member_id
     or v_request.requested_by_user_id is distinct from auth.uid() then
    raise exception 'Member freeze authority unavailable' using errcode = '42501';
  end if;

  perform app.slf_freeze_lock(v_request.tenant_id, v_request.member_id);

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id
   for update;

  v_facts := jsonb_build_object('request_id', p_request_id);

  select * into v_command
    from public.member_freeze_commands c
   where c.tenant_id = v_request.tenant_id
     and c.command_key = p_command_key;

  if v_command.id is not null then
    if v_command.action = 'cancel'
       and v_command.actor_user_id = auth.uid()
       and v_command.facts = v_facts then
      return jsonb_set(v_command.result, '{replayed}', 'true'::jsonb, true);
    end if;
    raise exception 'Member freeze command key conflict' using errcode = 'GL068';
  end if;

  if v_request.status not in ('requested','desk_submitted') then
    raise exception 'Member freeze request is not open' using errcode = 'GL066';
  end if;

  v_before := pg_catalog.to_jsonb(v_request);

  update public.member_freeze_requests r
     set status = 'cancelled',
         cancelled_by_user_id = auth.uid(),
         closed_at = pg_catalog.now(),
         revision = r.revision + 1
   where r.id = v_request.id
   returning * into v_request;

  v_result := jsonb_build_object(
    'request_id', v_request.id, 'status', v_request.status::text,
    'revision', v_request.revision::text, 'replayed', false);

  insert into public.member_freeze_commands
    (id, tenant_id, request_id, actor_user_id, command_key, action, facts, result)
  values
    (gen_random_uuid(), v_request.tenant_id, v_request.id, auth.uid(),
     p_command_key, 'cancel', v_facts, v_result);

  perform app.slf_freeze_audit(
    v_request.tenant_id, auth.uid(), app.current_app_role(),
    'member_freeze.cancelled', v_request.id,
    v_before - 'updated_at', pg_catalog.to_jsonb(v_request) - 'updated_at', null);

  return v_result;
end
$fn$;

-- The four desk commands: invoker wrappers. Actor validation and the source
-- `membership_pauses` write happen HERE, in the caller's own RLS/trigger
-- context; everything on the request tables happens in the definer helpers.
create or replace function public.adopt_member_freeze_request(
  p_request_id uuid, p_expected_revision bigint, p_command_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff_id uuid;
  v_prep     jsonb;
  v_req      jsonb;
  v_pause_id uuid;
begin
  v_staff_id := app.slf_front_office_staff();

  v_prep := app.slf_freeze_prepare('adopt', p_request_id, p_expected_revision,
                                   p_command_key,
                                   jsonb_build_object('request_id', p_request_id));
  if v_prep @> '{"replayed": true}'::jsonb then
    return v_prep -> 'result';
  end if;

  v_req := v_prep -> 'request';

  insert into public.membership_pauses
    (tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values
    ((v_req ->> 'tenant_id')::uuid, (v_req ->> 'membership_id')::uuid,
     (v_req ->> 'starts_on')::date, (v_req ->> 'ends_on')::date,
     v_req ->> 'reason', app.current_staff_id())
  returning id into v_pause_id;

  return app.slf_freeze_finish('adopt', p_request_id, p_command_key,
                               v_pause_id, null);
end
$fn$;

create or replace function public.approve_member_freeze_request(
  p_request_id uuid, p_expected_revision bigint, p_command_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff_id   uuid;
  v_prep       jsonb;
  v_req        jsonb;
  v_adopter    uuid;
  v_required   public.app_role;
  v_actor_role public.app_role;
  v_updated    integer;
begin
  v_staff_id := app.slf_front_office_staff();

  v_prep := app.slf_freeze_prepare('approve', p_request_id, p_expected_revision,
                                   p_command_key,
                                   jsonb_build_object('request_id', p_request_id));
  if v_prep @> '{"replayed": true}'::jsonb then
    return v_prep -> 'result';
  end if;

  v_req := v_prep -> 'request';
  v_adopter := (v_req ->> 'adopted_by_staff_id')::uuid;

  -- The desk sponsor's two-person boundary, checked here so the refusals are
  -- actor failures (42501) and so they follow the allowance recheck the
  -- prepare already ran (SLF-006/007, SLF-012).
  if v_adopter is not distinct from v_staff_id then
    raise exception 'Freeze approval refused: the adopting staff member cannot approve their own sponsorship'
      using errcode = '42501';
  end if;

  select s.pause_approver_role into v_required
    from public.organization_settings s
   where s.tenant_id = app.current_tenant_id();

  if v_required is not null then
    select st.role into v_actor_role
      from public.staff st
     where st.id = v_staff_id
       and st.tenant_id = app.current_tenant_id();

    if v_actor_role is distinct from v_required then
      raise exception 'Freeze approval refused: this gym requires % to approve a freeze, and the acting staff member is %',
        v_required, coalesce(v_actor_role::text, 'not a member of this gym')
        using errcode = '42501';
    end if;
  end if;

  update public.membership_pauses p
     set approved_by_staff_id = app.current_staff_id(),
         approved_at = pg_catalog.now()
   where p.id = (v_req ->> 'source_pause_id')::uuid
     and p.approved_at is null
     and p.rejected_at is null;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'Member freeze approval source mismatch' using errcode = '23514';
  end if;

  return app.slf_freeze_finish('approve', p_request_id, p_command_key, null, null);
end
$fn$;

create or replace function public.reject_member_freeze_request(
  p_request_id uuid, p_expected_revision bigint, p_reason text,
  p_command_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff_id uuid;
  v_prep     jsonb;
  v_req      jsonb;
  v_reason   text;
  v_updated  integer;
begin
  v_staff_id := app.slf_front_office_staff();

  v_reason := btrim(coalesce(p_reason, ''));
  if char_length(v_reason) < 3 or char_length(v_reason) > 200 then
    raise exception 'Member freeze rejection reason invalid' using errcode = '22023';
  end if;

  v_prep := app.slf_freeze_prepare('reject', p_request_id, p_expected_revision,
                                   p_command_key,
                                   jsonb_build_object('request_id', p_request_id,
                                                      'reason', v_reason));
  if v_prep @> '{"replayed": true}'::jsonb then
    return v_prep -> 'result';
  end if;

  v_req := v_prep -> 'request';

  -- A linked pending source pause is rejected by the real staff caller; a
  -- requested request has nothing to reject at the source.
  if (v_req ->> 'source_pause_id') is not null then
    update public.membership_pauses p
       set rejected_at = pg_catalog.now()
     where p.id = (v_req ->> 'source_pause_id')::uuid
       and p.approved_at is null
       and p.rejected_at is null;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      raise exception 'Member freeze rejection source mismatch' using errcode = '23514';
    end if;
  end if;

  return app.slf_freeze_finish('reject', p_request_id, p_command_key, null, v_reason);
end
$fn$;

create or replace function public.expire_member_freeze_request(
  p_request_id uuid, p_expected_revision bigint, p_command_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff_id uuid;
  v_prep     jsonb;
begin
  v_staff_id := app.slf_front_office_staff();

  v_prep := app.slf_freeze_prepare('expire', p_request_id, p_expected_revision,
                                   p_command_key,
                                   jsonb_build_object('request_id', p_request_id));
  if v_prep @> '{"replayed": true}'::jsonb then
    return v_prep -> 'result';
  end if;

  return app.slf_freeze_finish('expire', p_request_id, p_command_key, null, null);
end
$fn$;

-- The three safe reads (SLF-001/002): revalidating definer readers; members
-- see their own requests, real same-tenant front office sees the queue, and
-- the projection never carries staff/Auth ids on the member path.
create or replace function public.read_member_freeze_request(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_member_id uuid;
  v_request   public.member_freeze_requests;
begin
  v_member_id := app.slf_member_actor();

  select * into v_request
    from public.member_freeze_requests r
   where r.id = p_request_id;

  if v_request.id is null
     or v_request.tenant_id is distinct from app.current_tenant_id()
     or v_request.member_id is distinct from v_member_id then
    raise exception 'Member freeze request unavailable' using errcode = 'P0002';
  end if;

  return app.slf_freeze_detail(v_request, false);
end
$fn$;

create or replace function public.read_member_freeze_requests(
  p_limit integer, p_after_created_at timestamptz, p_after_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_member_id uuid;
  v_limit     integer;
  v_result    jsonb;
begin
  v_member_id := app.slf_member_actor();
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  select coalesce(
           jsonb_agg(app.slf_freeze_detail(r, false) order by r.created_at desc, r.id desc),
           '[]'::jsonb)
    into v_result
    from (
      select r.*
        from public.member_freeze_requests r
       where r.tenant_id = app.current_tenant_id()
         and r.member_id = v_member_id
         and (p_after_created_at is null
              or r.created_at < p_after_created_at
              or (r.created_at = p_after_created_at
                  and (p_after_id is null or r.id < p_after_id)))
       order by r.created_at desc, r.id desc
       limit v_limit
    ) r;

  return v_result;
end
$fn$;

create or replace function public.read_staff_freeze_requests(
  p_limit integer, p_after_created_at timestamptz, p_after_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_staff_id uuid;
  v_limit    integer;
  v_result   jsonb;
begin
  v_staff_id := app.slf_front_office_staff();
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  select coalesce(
           jsonb_agg(app.slf_freeze_detail(r, true) order by r.created_at desc, r.id desc),
           '[]'::jsonb)
    into v_result
    from (
      select r.*
        from public.member_freeze_requests r
       where r.tenant_id = app.current_tenant_id()
         and (p_after_created_at is null
              or r.created_at < p_after_created_at
              or (r.created_at = p_after_created_at
                  and (p_after_id is null or r.id < p_after_id)))
       order by r.created_at desc, r.id desc
       limit v_limit
    ) r;

  return v_result;
end
$fn$;

-- The safe detail projection (SLF-001/018): request id, membership id, dates
-- and reason, persisted and effective state, revision, times, decision reason,
-- source pause id and truthful action availability. `p_include_staff` is true
-- only on the staff queue read.
create or replace function app.slf_freeze_detail(
  p_request public.member_freeze_requests, p_include_staff boolean
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_today    date;
  v_pause    public.membership_pauses;
  v_effective text;
begin
  v_today := app.gym_today(p_request.tenant_id);

  if p_request.source_pause_id is not null then
    select * into v_pause
      from public.membership_pauses p
     where p.id = p_request.source_pause_id;
  end if;

  if p_request.status = 'approved' and v_pause.id is not null then
    v_effective := case
      when v_today > v_pause.ends_on then 'completed'
      when v_today < v_pause.starts_on then 'scheduled'
      else 'paused'
    end;
  elsif p_request.status = 'requested' then
    -- An open row whose start day has elapsed or whose member/target is
    -- unavailable discloses its effectively-expired condition at reads
    -- (SLF-010; reads never materialize it).
    v_effective := case when app.slf_freeze_ineffective(p_request, v_today)
                        then 'expired' else 'awaiting_desk' end;
  elsif p_request.status = 'desk_submitted' then
    v_effective := case when app.slf_freeze_ineffective(p_request, v_today)
                        then 'expired' else 'awaiting_approval' end;
  else
    v_effective := p_request.status::text;
  end if;

  return jsonb_build_object(
    'id', p_request.id,
    'membership_id', p_request.membership_id,
    'starts_on', p_request.starts_on,
    'ends_on', p_request.ends_on,
    'reason', p_request.reason,
    'status', p_request.status::text,
    'effective_state', v_effective,
    'revision', p_request.revision::text,
    'created_at', p_request.created_at,
    'adopted_at', p_request.adopted_at,
    'decided_at', p_request.decided_at,
    'decision_reason', p_request.decision_reason,
    'closed_at', p_request.closed_at,
    'source_pause_id', p_request.source_pause_id,
    'can_cancel', p_request.status in ('requested','desk_submitted'),
    'requested_by_staff_id',
      case when p_include_staff then p_request.adopted_by_staff_id end,
    'decided_by_staff_id',
      case when p_include_staff then p_request.decided_by_staff_id end
  );
end
$fn$;

-- ---------------------------------------------------------------------------
-- 9. EXECUTE grants: authenticated only, on the nine public RPCs and on the
--    two helpers the invoker wrappers must call. Everything else is revoked
--    from public, anon, authenticated and service_role.
-- ---------------------------------------------------------------------------

revoke all on function public.request_member_freeze(uuid,date,date,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.request_member_freeze(uuid,date,date,text,uuid) to authenticated;

revoke all on function public.cancel_member_freeze_request(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.cancel_member_freeze_request(uuid,uuid) to authenticated;

revoke all on function public.adopt_member_freeze_request(uuid,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.adopt_member_freeze_request(uuid,bigint,uuid) to authenticated;

revoke all on function public.approve_member_freeze_request(uuid,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.approve_member_freeze_request(uuid,bigint,uuid) to authenticated;

revoke all on function public.reject_member_freeze_request(uuid,bigint,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.reject_member_freeze_request(uuid,bigint,text,uuid) to authenticated;

revoke all on function public.expire_member_freeze_request(uuid,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.expire_member_freeze_request(uuid,bigint,uuid) to authenticated;

revoke all on function public.read_member_freeze_request(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_member_freeze_request(uuid) to authenticated;

revoke all on function public.read_member_freeze_requests(integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_member_freeze_requests(integer,timestamptz,uuid) to authenticated;

revoke all on function public.read_staff_freeze_requests(integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_staff_freeze_requests(integer,timestamptz,uuid) to authenticated;

revoke all on function app.slf_freeze_prepare(text,uuid,bigint,uuid,jsonb) from public,anon,service_role;
grant execute on function app.slf_freeze_prepare(text,uuid,bigint,uuid,jsonb) to authenticated;

revoke all on function app.slf_freeze_finish(text,uuid,uuid,uuid,text) from public,anon,service_role;
grant execute on function app.slf_freeze_finish(text,uuid,uuid,uuid,text) to authenticated;

revoke all on function app.slf_freeze_audit(uuid,uuid,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated,service_role;
-- The staff validator is a pure check the invoker wrappers run as the calling
-- role; a direct call returns only the caller's own staff id and grants
-- nothing extra.
revoke all on function app.slf_front_office_staff() from public,anon,service_role;
grant execute on function app.slf_front_office_staff() to authenticated;
revoke all on function app.slf_freeze_lock(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function app.slf_freeze_detail(public.member_freeze_requests,boolean) from public,anon,authenticated,service_role;
revoke all on function app.slf_freeze_ineffective(public.member_freeze_requests,date) from public,anon,authenticated,service_role;
revoke all on function app.slf_member_actor() from public,anon,authenticated,service_role;
revoke all on function app.slf_front_office_staff() from public,anon,authenticated,service_role;
revoke all on function app.enforce_member_freeze_request_row() from public,anon,authenticated,service_role;
revoke all on function app.enforce_freeze_source_consistency() from public,anon,authenticated,service_role;
