-- h16_checkin_holdout — HOLDOUT pgTAP suite for Phase 3's check-in capability.
--
-- Written blind from openspec/changes/phase-3-core-domain/specs/check-in/spec.md
-- and openspec/specs/authorization/spec.md. The author of this file has not read
-- supabase/tests/**, any Phase 3 migration, or anything under apps/web/.
--
-- What this file can and cannot prove is stated plainly, because an assertion
-- that looks like it proves exactly-once and does not is worse than a gap:
--
--   * It proves everything the DATABASE is the arbiter of — the composite tenant
--     keys (ADR-052), the row-security gates, the live-membership vocabulary,
--     the per-gym window value, and the shape of qr_sessions.
--   * It cannot open two connections: ADR-030 wraps every file in one
--     transaction. So the concurrency requirement is approached from the
--     MECHANISM side — a de-duplication that a second concurrent session can
--     defeat is one the database does not enforce, and the database is the only
--     party both sessions share. Assertions 26-29 test for a guard that exists
--     in the database; they do not run two sessions.
--
-- ADR-050: the project permanently holds a seeded demo gym. Nothing here counts
-- or lists a whole table — every count is scoped to this file's own fixtures.
--
-- ADR-030: one transaction, ending in ROLLBACK.

begin;

-- ADR-046: CI's session may be a NOINHERIT login role; the owner role, which
-- holds BYPASSRLS, is assumed explicitly rather than inherited.
set local role postgres;

select plan(43);

-- ---------------------------------------------------------------------------
-- Fixtures. Two gyms whose de-duplication windows are DIFFERENT and NEITHER of
-- which is the column default — an implementation that hardcodes a constant is
-- wrong for both, not merely for one.
--
-- Gym A's window is 45 seconds. Gym B's is 600.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('aa000016-0000-4000-8000-000000000001', 'Holdout Check-in Gym A', 'HCI16A'),
       ('aa000016-0000-4000-8000-000000000002', 'Holdout Check-in Gym B', 'HCI16B');

insert into public.organization_settings (tenant_id, checkin_dedupe_seconds)
values ('aa000016-0000-4000-8000-000000000001', 45),
       ('aa000016-0000-4000-8000-000000000002', 600);

insert into public.branches (id, tenant_id, name)
values ('aa000016-0000-4000-8000-000000000011', 'aa000016-0000-4000-8000-000000000001', 'H16 Main A'),
       ('aa000016-0000-4000-8000-000000000012', 'aa000016-0000-4000-8000-000000000002', 'H16 Main B');

insert into public.staff (id, tenant_id, branch_id, role, full_name)
values ('aa000016-0000-4000-8000-000000000021', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'front_desk', 'H16 Desk A'),
       ('aa000016-0000-4000-8000-000000000022', 'aa000016-0000-4000-8000-000000000002',
        'aa000016-0000-4000-8000-000000000012', 'front_desk', 'H16 Desk B'),
       ('aa000016-0000-4000-8000-000000000023', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'trainer', 'H16 Trainer A');

insert into public.plans (id, tenant_id, name, duration_days, price_paise)
values ('aa000016-0000-4000-8000-000000000025', 'aa000016-0000-4000-8000-000000000001',
        'H16 Plan A', 30, 100000),
       ('aa000016-0000-4000-8000-000000000026', 'aa000016-0000-4000-8000-000000000002',
        'H16 Plan B', 30, 100000);

-- Members of gym A, one per membership situation the spec discriminates.
--   ...0031 holds a live (active) membership
--   ...0033 holds only lapsed ones — one expired, one cancelled
--   ...0034 holds only a pending one
--   ...0036 is the client-event-id member
--   ...0037 is the assisted-reason member
--   ...0038 is the no-check-out member
-- Gym B's member is ...0032.
insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('aa000016-0000-4000-8000-000000000031', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Live Member A', '+919600160001'),
       ('aa000016-0000-4000-8000-000000000032', 'aa000016-0000-4000-8000-000000000002',
        'aa000016-0000-4000-8000-000000000012', 'H16 Live Member B', '+919600160002'),
       ('aa000016-0000-4000-8000-000000000033', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Lapsed Member A', '+919600160003'),
       ('aa000016-0000-4000-8000-000000000034', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Pending Member A', '+919600160004'),
       ('aa000016-0000-4000-8000-000000000036', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Event Member A', '+919600160006'),
       ('aa000016-0000-4000-8000-000000000037', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Assisted Member A', '+919600160007'),
       ('aa000016-0000-4000-8000-000000000038', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 No Checkout Member A', '+919600160008');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
values ('aa000016-0000-4000-8000-000000000041', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000031', 'aa000016-0000-4000-8000-000000000025',
        'active', date '2026-03-01', date '2026-12-31', 100000),
       ('aa000016-0000-4000-8000-000000000042', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000033', 'aa000016-0000-4000-8000-000000000025',
        'expired', date '2025-01-01', date '2025-12-31', 100000),
       ('aa000016-0000-4000-8000-000000000043', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000033', 'aa000016-0000-4000-8000-000000000025',
        'cancelled', date '2024-01-01', date '2024-12-31', 100000),
       ('aa000016-0000-4000-8000-000000000045', 'aa000016-0000-4000-8000-000000000002',
        'aa000016-0000-4000-8000-000000000032', 'aa000016-0000-4000-8000-000000000026',
        'active', date '2026-03-01', date '2026-12-31', 100000),
       ('aa000016-0000-4000-8000-000000000046', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000036', 'aa000016-0000-4000-8000-000000000025',
        'active', date '2026-03-01', date '2026-12-31', 100000),
       -- ATT-008's member is live: that requirement is about the check-OUT
       -- being optional, so the check-IN must not be refused for some other
       -- reason or the assertion silently tests ATT-001 instead.
       ('aa000016-0000-4000-8000-000000000047', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000038', 'aa000016-0000-4000-8000-000000000025',
        'active', date '2026-03-01', date '2026-12-31', 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise)
values ('aa000016-0000-4000-8000-000000000044', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000034', 'aa000016-0000-4000-8000-000000000025',
        'pending', 100000);

-- QR sessions: live, expired and revoked in gym A; live in gym B. The times are
-- relative to now() so "expired" and "live" are true when the suite runs, not
-- true only on the day the file was written.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at)
values ('aa000016-0000-4000-8000-000000000051', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'h16-token-hash-a-live',
        now() - interval '1 minute', now() + interval '1 hour', null),
       ('aa000016-0000-4000-8000-000000000052', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'h16-token-hash-a-expired',
        now() - interval '2 hours', now() - interval '1 hour', null),
       ('aa000016-0000-4000-8000-000000000053', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'h16-token-hash-a-revoked',
        now() - interval '1 minute', now() + interval '1 hour', now() - interval '30 seconds'),
       ('aa000016-0000-4000-8000-000000000054', 'aa000016-0000-4000-8000-000000000002',
        'aa000016-0000-4000-8000-000000000012', 'h16-token-hash-b-live',
        now() - interval '1 minute', now() + interval '1 hour', null);

-- The visit each de-duplication window is measured from.
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id,
                               checked_in_at, source, qr_session_id)
values ('aa000016-0000-4000-8000-000000000061', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'aa000016-0000-4000-8000-000000000031',
        'aa000016-0000-4000-8000-000000000041',
        timestamptz '2026-04-01 06:00:00+05:30', 'qr',
        'aa000016-0000-4000-8000-000000000051'),
       ('aa000016-0000-4000-8000-000000000062', 'aa000016-0000-4000-8000-000000000002',
        'aa000016-0000-4000-8000-000000000012', 'aa000016-0000-4000-8000-000000000032',
        'aa000016-0000-4000-8000-000000000045',
        timestamptz '2026-04-01 06:00:00+05:30', 'qr',
        'aa000016-0000-4000-8000-000000000054');


-- ---------------------------------------------------------------------------
-- ATT-003 — the token is never stored, only its hash.
--
-- The column list is asserted whole rather than by naming the columns a token
-- might hide in. A future migration that adds `token`, `code`, `qr_payload` or
-- `secret` fails here; a list of hasnt_column() calls only fails for the names
-- somebody thought of.
-- ---------------------------------------------------------------------------

select columns_are('public', 'qr_sessions',
  ARRAY['id', 'tenant_id', 'branch_id', 'token_hash', 'issued_at', 'expires_at',
        'revoked_at', 'created_by_staff_id', 'created_at'],
  'ATT-003: qr_sessions holds a hash and nothing else that could be presented as a token');

select col_not_null('public', 'qr_sessions', 'expires_at',
  'ATT-003: every QR session carries an expiry, so a screenshot stops working');

select col_is_null('public', 'qr_sessions', 'revoked_at',
  'ATT-001: revocation is representable — a live session is one that has not been revoked, not merely one that has not expired');


-- ---------------------------------------------------------------------------
-- ATT-004 — the de-duplication window is the gym's own, read per gym.
-- ---------------------------------------------------------------------------

select col_not_null('public', 'organization_settings', 'checkin_dedupe_seconds',
  'ATT-004: every gym has a de-duplication window — there is no null to fall back to a constant for');

select col_is_pk('public', 'organization_settings', 'tenant_id',
  'ATT-004: the window is keyed by gym — one row per tenant, so it is read per gym');

select results_eq(
  $$select checkin_dedupe_seconds from public.organization_settings
     where tenant_id in ('aa000016-0000-4000-8000-000000000001',
                         'aa000016-0000-4000-8000-000000000002')
     order by checkin_dedupe_seconds$$,
  $$values (45), (600)$$,
  'ATT-004: two gyms hold two different windows');

select is(
  (select count(*)::int from public.organization_settings s
    where s.tenant_id in ('aa000016-0000-4000-8000-000000000001',
                          'aa000016-0000-4000-8000-000000000002')
      and s.checkin_dedupe_seconds = (
        select substring(c.column_default from '^\d+')::int from information_schema.columns c
         where c.table_schema = 'public' and c.table_name = 'organization_settings'
           and c.column_name = 'checkin_dedupe_seconds')),
  0,
  'ATT-004: neither fixture gym sits on the column default, so a hardcoded constant is wrong for both');


-- ---------------------------------------------------------------------------
-- The live-membership vocabulary. ATT-001 asks for a membership in `active` or
-- `frozen` — not for one that merely exists. The database already carries the
-- distinction as a partial unique key over the live statuses; these assertions
-- pin which statuses that is, behaviourally, without naming the index.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.memberships
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and member_id = 'aa000016-0000-4000-8000-000000000033'),
  2,
  'ATT-001: the lapsed member does hold memberships — "a membership exists" is true of them');

select is(
  (select count(*)::int from public.memberships
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and member_id = 'aa000016-0000-4000-8000-000000000033'
      and status in ('active', 'frozen')),
  0,
  'ATT-001: and none of them is live — the two questions have different answers for this member');

select throws_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000031',
            'aa000016-0000-4000-8000-000000000025', 'active',
            date '2026-06-01', date '2026-06-30', 100000)$$,
  '23505', null,
  'ATT-001: `active` is a live status — a second one for the same member collides');

select throws_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000031',
            'aa000016-0000-4000-8000-000000000025', 'frozen',
            date '2026-06-01', date '2026-06-30', 100000)$$,
  '23505', null,
  'ATT-001: `frozen` is a live status too — it collides with the active one, so a frozen member may check in');

select lives_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000033',
            'aa000016-0000-4000-8000-000000000025', 'expired',
            date '2023-01-01', date '2023-12-31', 100000)$$,
  'ATT-001: `expired` is not a live status — a second expired membership does not collide');

select lives_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000033',
            'aa000016-0000-4000-8000-000000000025', 'cancelled',
            date '2022-01-01', date '2022-12-31', 100000)$$,
  'ATT-001: `cancelled` is not a live status either');

select lives_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, status, price_paise)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000034',
            'aa000016-0000-4000-8000-000000000025', 'pending', 100000)$$,
  'ATT-001: `pending` is not a live status — a member who has paid for nothing yet is not live');


-- ---------------------------------------------------------------------------
-- Exactly-once, from the mechanism side.
--
-- This transaction cannot open a second connection, so it cannot stage a real
-- race. What it can do is ask whether the guarantee lives anywhere two
-- concurrent sessions would both meet. A de-duplication that is a read followed
-- by a write leaves nothing here to find.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.attendance'::regclass
       and c.contype in ('u', 'x')
       and pg_get_constraintdef(c.oid) like '%member_id%'
  )
  or exists (
    select 1 from pg_index x
     where x.indrelid = 'public.attendance'::regclass
       and x.indisunique
       and pg_get_indexdef(x.indexrelid) like '%member_id%'
  )
  or exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and p.prosrc ~* 'checkin_dedupe_seconds'
       and p.prosrc ~* '(advisory|for update|serializable)'
  ),
  'Exactly-once: the same-member guarantee is enforced in the database — a unique or exclusion key over the member, or a function that takes a lock before it writes. A read-then-write in the caller satisfies none of these, and two concurrent callers defeat it.');


-- ---------------------------------------------------------------------------
-- Act as the front desk of gym A. This is the session a check-in actually runs
-- in: `attendance` write gate is front office, `qr_sessions` read gate is front
-- office, `organization_settings` read gate is staff.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', 'aa000016-0000-4000-8000-000000000021')::text,
  true
);
set local role authenticated;

select is(
  (select checkin_dedupe_seconds from public.organization_settings
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'),
  45,
  'ATT-004: the front desk reads its own gym''s window, and it is that gym''s value');

select is_empty(
  $$select 1 from public.organization_settings
     where tenant_id = 'aa000016-0000-4000-8000-000000000002'$$,
  'ATT-004: and cannot read the other gym''s window, so one gym''s value can never stand in for another''s');

-- ATT-001/ATT-002. Of the four fixture sessions, exactly one is presentable to
-- this session: the expired one and the revoked one are excluded by the
-- predicate, and the other gym's live one is excluded by row security before
-- any predicate runs.
select results_eq(
  $$select id from public.qr_sessions
     where id in ('aa000016-0000-4000-8000-000000000051',
                  'aa000016-0000-4000-8000-000000000052',
                  'aa000016-0000-4000-8000-000000000053',
                  'aa000016-0000-4000-8000-000000000054')
       and expires_at > now()
       and revoked_at is null
     order by id$$,
  $$values ('aa000016-0000-4000-8000-000000000051'::uuid)$$,
  'ATT-001/002: expired, revoked and other-gym sessions are all excluded — only the live session of this gym remains');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000033', timestamptz '2026-04-07 06:00:00+05:30',
            'qr', 'aa000016-0000-4000-8000-000000000054')$$,
  null::char(5), null::text,
  'ATT-001: a visit citing another gym''s QR session is refused by the database itself — by a guard or by the key, whichever reaches it first, and not merely by the endpoint''s own check');

-- The same client event id, submitted twice. The second submission carries a
-- LATER check-in time, so "the original is intact" is a claim with teeth.
select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id,
                                   checked_in_at, source, qr_session_id, client_event_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000036', 'aa000016-0000-4000-8000-000000000046',
            timestamptz '2026-04-03 06:00:00+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000051',
            'aa000016-0000-4000-8000-0000000000e1')$$,
  'Exactly-once: the first submission of a client event is recorded');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id,
                                   checked_in_at, source, qr_session_id, client_event_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000036', 'aa000016-0000-4000-8000-000000000046',
            timestamptz '2026-04-03 06:00:07+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000051',
            'aa000016-0000-4000-8000-0000000000e1')
    on conflict do nothing$$,
  'Exactly-once: the second submission of the same client event is a no-op the database absorbs, not an error the caller must be told about');

select is(
  (select count(*)::int from public.attendance
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and client_event_id = 'aa000016-0000-4000-8000-0000000000e1'),
  1,
  'Exactly-once: one client event, one attendance row');

select is(
  (select checked_in_at from public.attendance
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and client_event_id = 'aa000016-0000-4000-8000-0000000000e1'),
  timestamptz '2026-04-03 06:00:00+05:30',
  'Exactly-once: the surviving row is the first submission — the re-submission changed nothing');

-- ATT-004, the window itself. Gym A's window is 45 seconds. Every column here
-- is valid and every key resolves, so the only thing that can refuse this
-- insert is a de-duplication guard.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id,
                                   checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000031', 'aa000016-0000-4000-8000-000000000041',
            timestamptz '2026-04-01 06:00:30+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'ATT-004: a second scan thirty seconds later, inside this gym''s forty-five second window, is refused');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id,
                                   checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000031', 'aa000016-0000-4000-8000-000000000041',
            timestamptz '2026-04-01 06:05:00+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000051')$$,
  'ATT-004: a scan five minutes later, the window having elapsed, is recorded');

-- ATT-005/006. The Phase 1 constraint refuses the empty string. A reason made
-- of whitespace is the same absence wearing a costume.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000037', timestamptz '2026-04-04 06:00:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000021', '   ')$$,
  '23514', null,
  'ATT-006: an assisted check-in whose reason is three spaces is rejected — whitespace is not a reason');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000037', timestamptz '2026-04-04 06:10:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000021', E'\t\n ')$$,
  '23514', null,
  'ATT-006: nor is a tab and a newline');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000037', timestamptz '2026-04-04 07:00:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000021',
            'h16 member left their phone in the car')$$,
  'ATT-005/006: the front desk records an assisted check-in naming itself and a real reason');

-- The same statement, naming a COLLEAGUE OF THE SAME GYM (trainer ...0023).
-- Nothing about the tenant is wrong, so ADR-052's key has no objection and this
-- isolates the rule itself: ATT-005 exists to make "who marked this member
-- present" attributable, and an attribution the writer chooses is not one. The
-- HTTP schema has no field for this column, which makes the endpoint honest and
-- the table not — and the table is the boundary.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000037', timestamptz '2026-04-04 08:00:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000023',
            'h16 attributing an assist to a colleague')$$,
  null::char(5), null::text,
  'ATT-005: an assisted check-in cannot be attributed to a colleague of the same gym — the acting staff member is whoever holds the session, and a value the caller supplies is not evidence of that');

-- A check-in never crosses a tenant. Each of these labels the row with the
-- CALLER'S OWN tenant, so row security admits it — what refuses it is the key
-- re-checking the tenant of the thing being named (ADR-052).
--
-- The member and membership cases pin 23503, because the composite key is the
-- only thing that can refuse them and naming the mechanism is what makes those
-- assertions evidence for ADR-052. The assisted-staff case below does NOT pin a
-- code, and the reason is in the comment on it.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000032', timestamptz '2026-04-02 06:00:00+05:30', 'qr')$$,
  '23503', null,
  'A check-in naming another gym''s member is refused even though the row carries the caller''s own tenant');

-- This row breaks TWO rules at once, and the spec states an outcome for each
-- rather than a mechanism. Staff ...0022 belongs to gym B, so ADR-052's
-- composite key refuses it; and ...0022 is not the acting staff member either —
-- this session is ...0021 — which the assisted-check-in requirement now refuses
-- in its own right ("the acting staff member is whoever holds the session, and
-- a value supplied by the caller is not evidence of that"). Whichever rule
-- reaches it first is an implementation detail this file has no business
-- pinning: naming 23503 here would turn a correct fix into a red test, because
-- a guard that refuses a supplied colleague necessarily runs before the key
-- ever sees the value. The claim the assertion makes — that this is refused —
-- is unchanged and is the part that matters.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000033', timestamptz '2026-04-02 06:01:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000022', 'h16 cross-tenant staff')$$,
  null::char(5), null::text,
  'An assisted check-in naming another gym''s staff member is refused — by the tenant key or by the rule that the acting staff member is not the caller''s to choose, and the write must not land either way');

-- The cross-tenant half, with the acting staff member taken out of the
-- question. This session's own claim names gym B's front desk while carrying
-- gym A's tenant, so `assisted_by_staff_id` is the session's OWN staff id and
-- no colleague is being named — the new assisted-check-in rule has nothing to
-- object to, and only the tenant boundary is left to refuse the write.
--
-- Without this, the coverage the assertion above used to carry for ADR-052 on
-- `assisted_by_staff_id` disappears the moment a colleague rule is added. Still
-- unpinned: a rule requiring the acting staff row to exist in the acting gym
-- would also refuse this, and would be a correct rule to have.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', 'aa000016-0000-4000-8000-000000000022')::text,
  true
);

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000033', timestamptz '2026-04-02 06:04:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000022',
            'h16 acting staff belongs to the other gym')$$,
  null::char(5), null::text,
  'An assisted check-in whose acting staff member belongs to another gym is refused although the caller names nobody but itself — a well-formed claim is not evidence that the staff row it names is this gym''s');

-- Back to gym A's own front desk for the remaining assertions.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', 'aa000016-0000-4000-8000-000000000021')::text,
  true
);

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000034', 'aa000016-0000-4000-8000-000000000045',
            timestamptz '2026-04-02 06:02:00+05:30', 'qr')$$,
  '23503', null,
  'A check-in citing another gym''s membership is refused');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000016-0000-4000-8000-000000000002', 'aa000016-0000-4000-8000-000000000012',
            'aa000016-0000-4000-8000-000000000032', timestamptz '2026-04-02 06:03:00+05:30', 'qr')$$,
  '42501', null,
  'The tenant of a check-in is the claim''s, not the caller''s to supply — a row labelled with the other gym is refused by row security');

-- ATT-008. A visit with no check-out is an ordinary visit.
select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000038', timestamptz '2026-04-06 06:00:00+05:30',
            'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  'ATT-008: a check-in with no check-out is recorded');

select is(
  (select count(*)::int from public.attendance
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and member_id = 'aa000016-0000-4000-8000-000000000038'
      and checked_out_at is null),
  1,
  'ATT-008: and it counts as a visit — nothing depends on the check-out being there');


-- ---------------------------------------------------------------------------
-- Act as a member of gym A. A member session is the one holding the phone that
-- scans, so what it can reach decides whether the QR gate and the window can be
-- enforced client-side at all. They cannot.
-- ---------------------------------------------------------------------------

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'member',
                    'member_id', 'aa000016-0000-4000-8000-000000000031')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select 1 from public.organization_settings
     where tenant_id = 'aa000016-0000-4000-8000-000000000001'$$,
  'ATT-004: a member session cannot read the window, so the de-duplication cannot be a client-side decision');

select is_empty(
  $$select 1 from public.qr_sessions
     where id = 'aa000016-0000-4000-8000-000000000051'$$,
  'ATT-001: a member session cannot read even the live QR session of its own gym, so the scan is validated server-side or not at all');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000031', timestamptz '2026-04-08 06:00:00+05:30', 'qr')$$,
  '42501', null,
  'A member cannot write their own attendance — the QR check-in goes through the server, which is where the gates are');


-- ---------------------------------------------------------------------------
-- Act as a trainer of gym A. The matrix gives `attendance` a write gate of
-- front office and above, and `qr_sessions` a read gate of front office.
-- ---------------------------------------------------------------------------

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'trainer',
                    'staff_id', 'aa000016-0000-4000-8000-000000000023')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select 1 from public.qr_sessions
     where id = 'aa000016-0000-4000-8000-000000000051'$$,
  'ATT-001: a trainer cannot read the gym''s QR sessions');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source,
                                   assisted_by_staff_id, assist_reason)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'aa000016-0000-4000-8000-000000000033', timestamptz '2026-04-05 06:00:00+05:30',
            'front_desk', 'aa000016-0000-4000-8000-000000000023', 'h16 trainer assisted')$$,
  '42501', null,
  'ATT-005: a trainer''s assisted check-in is refused — the write gate is front office and above');


-- ---------------------------------------------------------------------------
-- Act as the front desk of gym B, whose window is 600 seconds. The same five
-- minute gap that was long enough for gym A is inside gym B's window. An
-- implementation carrying one number gets exactly one of these two right.
-- ---------------------------------------------------------------------------

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', 'aa000016-0000-4000-8000-000000000022')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id,
                                   checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000002', 'aa000016-0000-4000-8000-000000000012',
            'aa000016-0000-4000-8000-000000000032', 'aa000016-0000-4000-8000-000000000045',
            timestamptz '2026-04-01 06:05:00+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000054')$$,
  null::char(5), null::text,
  'ATT-004: the same five minute gap is refused at gym B, whose window is ten minutes — each gym''s de-duplication uses its own value');


-- ---------------------------------------------------------------------------
-- Closing check, as the owner: nothing this file attempted left a gym A member
-- in gym B or a gym B member in gym A.
-- ---------------------------------------------------------------------------

set local role postgres;

select is(
  (select count(*)::int from public.attendance a
     join public.members m on m.id = a.member_id
    where a.tenant_id in ('aa000016-0000-4000-8000-000000000001',
                          'aa000016-0000-4000-8000-000000000002')
      and m.tenant_id <> a.tenant_id),
  0,
  'No attendance row in either fixture gym belongs to a member of the other');

select * from finish();

rollback;
