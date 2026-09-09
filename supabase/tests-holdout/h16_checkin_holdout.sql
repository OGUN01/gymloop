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

select plan(66);

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
       ('aa000016-0000-4000-8000-000000000012', 'aa000016-0000-4000-8000-000000000002', 'H16 Main B'),
       -- A second branch in gym A, solely so the generic column sweep below has
       -- a valid alternate branch_id to probe with instead of a random uuid.
       ('aa000016-0000-4000-8000-000000000013', 'aa000016-0000-4000-8000-000000000001', 'H16 Second Branch A');

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
        'aa000016-0000-4000-8000-000000000011', 'H16 No Checkout Member A', '+919600160008'),
       -- Dedicated to the checked_out_at attack-surface probes further down
       -- (row 072), kept separate from ...0038 so those probes setting and
       -- re-setting checked_out_at do not add a second row to the count
       -- ATT-008 already scoped to ...0038's own visits.
       ('aa000016-0000-4000-8000-000000000039', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16 Checkout Probe Member A', '+919600160009');

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
        'active', date '2026-03-01', date '2026-12-31', 100000),
       -- ...039's own membership: its attendance row (072) is a QR check-in,
       -- and app.enforce_check_in() requires a live membership for that
       -- source even on a trusted-context fixture insert.
       ('aa000016-0000-4000-8000-000000000048', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000039', 'aa000016-0000-4000-8000-000000000025',
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

-- Three dedicated rows for the "written once" assertions further down, kept
-- separate from every row another assertion already depends on so neither the
-- generic sweep nor the open-column probes disturb an earlier count — and kept
-- separate from EACH OTHER too: the generic sweep probes id last, and if id is
-- not frozen, every later attack aimed at the same row by its original id
-- would silently match nothing once the sweep has already renumbered it,
-- making that later attack prove nothing at all.
--   ...070 — an assisted (front_desk) row with every optional column
--            populated, so the sweep alone has something in every column to
--            change. Nothing else in this file targets it afterward.
--   ...071 — a second assisted (front_desk) row, for the combined-write
--            attacks (forging offline provenance, erasing the assisted pair)
--            that must land on a row the sweep has not touched.
--   ...072 — a plain QR row with no check-out yet, for the checked_out_at
--            attack-surface probes (check-out-before-check-in, repeated
--            check-out).
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id,
                               checked_in_at, source, assisted_by_staff_id, assist_reason)
values ('aa000016-0000-4000-8000-000000000070', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'aa000016-0000-4000-8000-000000000037',
        'aa000016-0000-4000-8000-000000000041',
        timestamptz '2026-04-05 09:00:00+05:30', 'front_desk',
        'aa000016-0000-4000-8000-000000000021', 'h16 sweep fixture, original reason'),
       ('aa000016-0000-4000-8000-000000000071', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'aa000016-0000-4000-8000-000000000037',
        'aa000016-0000-4000-8000-000000000041',
        timestamptz '2026-04-05 09:30:00+05:30', 'front_desk',
        'aa000016-0000-4000-8000-000000000021', 'h16 combined-write fixture, original reason');

insert into public.attendance (id, tenant_id, branch_id, member_id, checked_in_at, source, qr_session_id)
values ('aa000016-0000-4000-8000-000000000072', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'aa000016-0000-4000-8000-000000000039',
        timestamptz '2026-04-05 10:00:00+05:30', 'qr',
        'aa000016-0000-4000-8000-000000000051');


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
-- ---------------------------------------------------------------------------
-- THE GENERIC COLUMN SWEEP — "every column except checked_out_at", asserted as
-- a shape rather than transcribed as the nine (now known to be wrong) names
-- the first version of this rule listed. pg_temp.frozen_probe() enumerates
-- information_schema.columns itself, so id, created_at, offline_recorded_at
-- and replayed_at — ADR-070's own four misses — are covered along with
-- anything nobody has named yet. Each FK column is perturbed with a real
-- alternate row rather than a random uuid, so a refusal is attributable to the
-- freeze rule and not to an incidental foreign-key violation.
--
-- offline_recorded_at and replayed_at are excluded from the loop: Phase 1's
-- own attendance_offline_stamp_pair_chk refuses setting either one alone
-- regardless of any freeze rule, which would make a single-column probe of
-- either one prove nothing about THIS rule. That combined attack is tested
-- separately, right below, by setting both together in one statement — which
-- satisfies the pair check and leaves only the freeze rule able to refuse it.
-- ---------------------------------------------------------------------------

-- pg_temp.attempt(): run a write, return 'ok' or the SQLSTATE, never abort.
-- Security invoker. Used below only where the write is meant to be REFUSED
-- and the assertion that follows checks row state rather than an error —
-- exactly ADR-069's shape, so its result is always consumed by an assertion
-- or discarded through `perform` inside a do block, never a bare top-level
-- `select`.
create function pg_temp.attempt(sql text) returns text
language plpgsql as $fn$
begin
  execute sql;
  return 'ok';
exception when others then
  return sqlstate;
end;
$fn$;

create function pg_temp.frozen_probe(
  p_table text, p_row_id uuid, p_excluded text[], p_fk_overrides jsonb default '{}'::jsonb
) returns text[] language plpgsql as $fn$
declare
  before_row jsonb;
  after_row jsonb;
  col record;
  new_val text;
  leaked text[] := '{}';
  id_survived boolean;
begin
  execute format('select to_jsonb(t) from public.%I t where id = %L', p_table, p_row_id)
    into before_row;

  -- id is tested LAST and separately (below), never inside this loop: if id
  -- itself is not frozen and leaks first, every later UPDATE in this loop is
  -- still keyed `where id = p_row_id` against a row that has already moved,
  -- so it would silently match zero rows and every remaining column would
  -- misreport as leaked too. Testing id last, by existence rather than by
  -- value-diff, keeps the per-column results below trustworthy regardless of
  -- what id does.
  for col in
    select c.column_name, c.data_type
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = p_table
       and c.column_name <> all(p_excluded)
       and c.column_name <> 'id'
     order by c.ordinal_position
  loop
    if p_fk_overrides ? col.column_name then
      new_val := quote_literal(p_fk_overrides ->> col.column_name);
    elsif col.column_name = 'source' then
      new_val := quote_literal(case when before_row ->> 'source' = 'front_desk' then 'qr' else 'front_desk' end);
    elsif col.data_type = 'uuid' then
      new_val := 'gen_random_uuid()';
    elsif col.data_type = 'date' then
      new_val := quote_literal(((before_row ->> col.column_name)::date + 1)::text);
    elsif col.data_type = 'timestamp with time zone' then
      if before_row ->> col.column_name is null then
        new_val := 'now()';
      else
        new_val := quote_literal(((before_row ->> col.column_name)::timestamptz + interval '1 second')::text);
      end if;
    elsif col.data_type = 'text' then
      new_val := quote_literal(coalesce(before_row ->> col.column_name, '') || '_frozen_probe');
    elsif col.data_type = 'boolean' then
      new_val := (not coalesce((before_row ->> col.column_name)::boolean, false))::text;
    elsif col.data_type in ('integer', 'smallint', 'bigint', 'numeric') then
      new_val := (coalesce((before_row ->> col.column_name)::numeric, 0) + 1)::text;
    else
      leaked := leaked || (col.column_name || ' [UNPROBED TYPE ' || col.data_type || ']');
      continue;
    end if;

    begin
      execute format('update public.%I set %I = %s where id = %L',
        p_table, col.column_name, new_val, p_row_id);
    exception when others then
      null;
    end;
  end loop;

  execute format('select to_jsonb(t) from public.%I t where id = %L', p_table, p_row_id)
    into after_row;

  for col in
    select c.column_name
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = p_table
       and c.column_name <> all(p_excluded)
       and c.column_name <> 'id'
  loop
    if (before_row ->> col.column_name) is distinct from (after_row ->> col.column_name) then
      leaked := leaked || col.column_name;
    end if;
  end loop;

  -- id, last, by existence under the original value rather than by comparing
  -- values (there is nothing left to compare it to once it might have moved).
  if 'id' <> all(p_excluded) then
    begin
      execute format('update public.%I set id = gen_random_uuid() where id = %L', p_table, p_row_id);
    exception when others then
      null;
    end;

    execute format('select exists(select 1 from public.%I where id = %L)', p_table, p_row_id)
      into id_survived;

    if not id_survived then
      leaked := leaked || 'id'::text;
    end if;
  end if;

  return leaked;
end;
$fn$;

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
  pg_temp.frozen_probe('attendance', 'aa000016-0000-4000-8000-000000000070'::uuid,
    array['tenant_id', 'checked_out_at', 'offline_recorded_at', 'replayed_at'],
    jsonb_build_object('branch_id', 'aa000016-0000-4000-8000-000000000013',
                        'member_id', 'aa000016-0000-4000-8000-000000000036',
                        'membership_id', 'aa000016-0000-4000-8000-000000000046',
                        'assisted_by_staff_id', 'aa000016-0000-4000-8000-000000000023',
                        'qr_session_id', 'aa000016-0000-4000-8000-000000000051')),
  '{}'::text[],
  'A recorded visit freezes every column but checked_out_at — swept from the catalogue rather than a hand-typed list, so id, created_at and any column nobody has named yet are covered too, not just the nine the first version of this rule listed');

-- The combined attack the pair check alone cannot answer: stamp BOTH offline
-- columns together on a visit that was recorded live. Satisfies
-- attendance_offline_stamp_pair_chk, so only the freeze rule stands between a
-- front-office session and forged offline provenance on this row.
do $do$ begin perform pg_temp.attempt($$
  update public.attendance
     set offline_recorded_at = now(), replayed_at = now()
   where id = 'aa000016-0000-4000-8000-000000000071'$$); end $do$;

-- Erasing the assisted pair, as the spec's own scenario states it: flip
-- source to 'qr' and null BOTH assist columns in the same statement. Nulling
-- just one alone is already refused by the Phase 1 pair check regardless of
-- this rule, so the meaningful attack is the combined write, which satisfies
-- every Phase 1 check and leaves only the freeze rule to answer.
do $do$ begin perform pg_temp.attempt($$
  update public.attendance
     set source = 'qr', assisted_by_staff_id = null, assist_reason = null
   where id = 'aa000016-0000-4000-8000-000000000071'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select offline_recorded_at is null and replayed_at is null
     from public.attendance
    where id = 'aa000016-0000-4000-8000-000000000071'),
  'Offline provenance cannot be forged onto a visit recorded live, even by setting both paired columns together in one statement that satisfies Phase 1''s own pair check');

select ok(
  (select source = 'front_desk' and assisted_by_staff_id is not null and assist_reason is not null
     from public.attendance
    where id = 'aa000016-0000-4000-8000-000000000071'),
  'The assisted pair cannot be erased by flipping source to qr and nulling both columns together — ATT-005 exists so that marking somebody else present is attributable, and an attributable record that can be un-attributed in one statement is not one');

-- ---------------------------------------------------------------------------
-- THE ONE OPEN COLUMN AS AN ATTACK SURFACE. checked_out_at is deliberately
-- left writable; the question is what a caller can do with only that.
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

-- A check-out before the check-in. Not a defence this rule is responsible
-- for — attendance_checked_out_at_after_checked_in_at_chk already refuses it
-- — but the open column is exactly where that pre-existing guard has to keep
-- working once every other column is frozen.
select throws_ok(
  $$update public.attendance
       set checked_out_at = timestamptz '2026-04-05 09:59:00+05:30'
     where id = 'aa000016-0000-4000-8000-000000000072'$$,
  '23514', null,
  'A check-out before the check-in is still refused through the one open column, by Phase 1''s own ordering check');

select lives_ok(
  $$update public.attendance
       set checked_out_at = timestamptz '2026-04-05 10:30:00+05:30'
     where id = 'aa000016-0000-4000-8000-000000000072'$$,
  'A valid check-out, at or after the check-in time, succeeds through the one column the rule leaves open');

-- A SECOND check-out on the same visit, overwriting the first. Nothing in the
-- spec's text restricts checked_out_at once it has already been set once — it
-- is simply the column the freeze rule does not apply to — so this is asserted
-- as succeeding under the literal rule. If a gym''s product sense says a visit
-- should only be checked out once, that is a rule this spec does not yet
-- state, and this assertion is where that gap would be found.
select lives_ok(
  $$update public.attendance
       set checked_out_at = timestamptz '2026-04-05 11:00:00+05:30'
     where id = 'aa000016-0000-4000-8000-000000000072'$$,
  'A second check-out on the same visit, overwriting the first, is not refused by anything this spec states — checked_out_at is unconditionally open, not open-once');

-- ===========================================================================
-- ADDENDUM -- "live" now means dates too, not only status.
--
-- The spec was rewritten (2026-09-09): a membership is live only when its
-- status is `active`/`frozen` AND the gym's own today falls within
-- [starts_on, ends_on]. Nothing in this product ever writes `expired`, so the
-- status-only rule admitted a membership that ended in March, forever.
--
-- Written blind and independently of the visible suite's extension of the
-- same requirement -- this is a second, separately-reasoned reading, not a
-- transcription. Namespace 'cafe1600-...', used nowhere else in this repo's
-- test suites. Every boundary date below is read from the GYM'S OWN today,
-- captured once into a temp table via `(now() at time zone o.timezone)::date`
-- -- no literal date and no `current_date` appears anywhere in this addendum.
--
-- An open question this file does NOT settle: whether "the gym's own today"
-- means the day the row is INSERTED (what every assertion below tests) or
-- the day named by `checked_in_at` (relevant to an offline-recorded visit
-- synced after the gym's midnight, which carries its own
-- offline_recorded_at/replayed_at columns for exactly this reason). The
-- spec's own wording ties liveness to "today", not to the visit's own
-- timestamp, so insert-time is the more literal reading and is what every
-- fixture below exercises -- but a replayed offline check-in for a visit that
-- was live on the day it actually happened, synced the next day, is a case
-- this file cannot distinguish from a plain insert and does not attempt to.
-- Flagged for the human, not resolved here.
-- ===========================================================================

set local role postgres;

-- A schema fact discovered empirically against the live database (queried
-- directly, never via a migration file): `memberships_dated_unless_pending_chk`
-- requires BOTH starts_on and ends_on whenever status <> 'pending'. That makes
-- the spec's own "open-ended membership" scenario (an active membership with
-- no ends_on) -- and its unstated mirror, an active membership with no
-- starts_on -- states the schema refuses to store at all, not merely states
-- the check-in gate happens to never see. Pinned here so a future migration
-- that relaxes the constraint doesn't silently reopen either hole.
select ok(
  exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.memberships'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ~ 'pending'
       and pg_get_constraintdef(c.oid) ~ 'starts_on'
       and pg_get_constraintdef(c.oid) ~ 'ends_on'
  ),
  'A check constraint on memberships requires BOTH starts_on and ends_on for any non-pending status, so a live (active/frozen) membership with a null starts_on or a null ends_on cannot exist in this schema at all -- the spec''s open-ended-membership scenario, and its unstated null-starts_on mirror, describe a state that is unreachable at the row level, not merely one the check-in gate has never needed to refuse'
);

-- Two gyms at the extreme ends of the clock, 24 hours apart at every instant
-- (same technique as h18/h21): the server (UTC) and these two gyms are on
-- different calendar dates for most of any given day, and the two gyms are
-- on different calendar dates from EACH OTHER for most of any given day too.
insert into public.organizations (id, name, gym_code, timezone)
values ('cafe1600-0000-4000-8000-000000000001', 'Holdout Live-Membership Gym P (GMT-12)', 'H16CFP', 'Etc/GMT-12'),
       ('cafe1600-0000-4000-8000-000000000002', 'Holdout Live-Membership Gym M (GMT+12)', 'H16CFM', 'Etc/GMT+12');

insert into public.organization_settings (tenant_id, checkin_dedupe_seconds)
values ('cafe1600-0000-4000-8000-000000000001', 60),
       ('cafe1600-0000-4000-8000-000000000002', 60);

insert into public.branches (id, tenant_id, name)
values ('cafe1600-0000-4000-8000-000000000011', 'cafe1600-0000-4000-8000-000000000001', 'H16C Main P'),
       ('cafe1600-0000-4000-8000-000000000012', 'cafe1600-0000-4000-8000-000000000002', 'H16C Main M');

insert into public.staff (id, tenant_id, branch_id, role, full_name)
values ('cafe1600-0000-4000-8000-000000000021', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000011', 'front_desk', 'H16C Desk P'),
       ('cafe1600-0000-4000-8000-000000000022', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000012', 'front_desk', 'H16C Desk M');

insert into public.plans (id, tenant_id, name, duration_days, price_paise)
values ('cafe1600-0000-4000-8000-000000000025', 'cafe1600-0000-4000-8000-000000000001', 'H16C Plan P', 30, 100000),
       ('cafe1600-0000-4000-8000-000000000026', 'cafe1600-0000-4000-8000-000000000002', 'H16C Plan M', 30, 100000);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at)
values ('cafe1600-0000-4000-8000-000000000051', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000011', 'h16c-token-hash-p-live',
        now() - interval '1 minute', now() + interval '1 hour', null),
       ('cafe1600-0000-4000-8000-000000000052', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000012', 'h16c-token-hash-m-live',
        now() - interval '1 minute', now() + interval '1 hour', null);

-- The gym's own today, for gym A (the original fixture gym, timezone default
-- Asia/Kolkata) and both extreme-timezone gyms -- read once, used everywhere
-- below instead of any literal date or current_date.
create temp table h16c_today as
select o.id as tenant_id, (now() at time zone o.timezone)::date as today
  from public.organizations o
 where o.id in ('aa000016-0000-4000-8000-000000000001',
                'cafe1600-0000-4000-8000-000000000001',
                'cafe1600-0000-4000-8000-000000000002');

-- Members of gym A, one per interaction this addendum targets:
--   ...101 -- frozen status, dates genuinely live (frozen is live, but only
--            when the dates say so too). Gains a SECOND, long-lapsed
--            membership (...206) in the closing section, where it is CREATED
--            rather than declared here -- see the note there for why it
--            cannot be created until this one has been cancelled.
--   ...102 -- frozen status, dates lapsed long ago (ADR-075's exact case,
--            restated for `frozen` instead of `active`)
--   ...103 -- TWO memberships: one long-cancelled with lapsed dates, one
--            active with live dates -- the lapsed row must not blind the gate
--            to the live one
--   ...104 -- active, starts_on is the gym's own today (the boundary the
--            visible spec's "next Monday" scenario does not reach: today
--            itself, not merely some day in the future)
--   ...106 -- frozen status, live dates, AND a currently-approved pause
--            covering today -- a table this rule has no business consulting
insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('cafe1600-0000-4000-8000-000000000101', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16C Frozen Live A', '+919600170101'),
       ('cafe1600-0000-4000-8000-000000000102', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16C Frozen Lapsed A', '+919600170102'),
       ('cafe1600-0000-4000-8000-000000000103', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16C Two Memberships A', '+919600170103'),
       ('cafe1600-0000-4000-8000-000000000104', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16C Starts Today A', '+919600170104'),
       ('cafe1600-0000-4000-8000-000000000106', 'aa000016-0000-4000-8000-000000000001',
        'aa000016-0000-4000-8000-000000000011', 'H16C Pause Frozen A', '+919600170106');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
values ('cafe1600-0000-4000-8000-000000000201', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000101', 'aa000016-0000-4000-8000-000000000025',
        'frozen', date '2020-01-01', date '2030-01-01', 100000),
       ('cafe1600-0000-4000-8000-000000000202', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000102', 'aa000016-0000-4000-8000-000000000025',
        'frozen', date '2015-01-01', date '2016-12-31', 100000),
       ('cafe1600-0000-4000-8000-000000000203', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000103', 'aa000016-0000-4000-8000-000000000025',
        'cancelled', date '2018-01-01', date '2018-12-31', 100000),
       ('cafe1600-0000-4000-8000-000000000204', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000103', 'aa000016-0000-4000-8000-000000000025',
        'active', date '2020-01-01', date '2030-01-01', 100000),
       ('cafe1600-0000-4000-8000-000000000205', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000104', 'aa000016-0000-4000-8000-000000000025',
        'active',
        (select today from h16c_today where tenant_id = 'aa000016-0000-4000-8000-000000000001'),
        date '2030-01-01', 100000),
       ('cafe1600-0000-4000-8000-000000000207', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000106', 'aa000016-0000-4000-8000-000000000025',
        'frozen', date '2020-01-01', date '2030-01-01', 100000);

-- ...101's second membership (...206) is NOT declared here. It has to be
-- `active` -- a live status -- with dates already behind today, and while
-- ...201 is still `frozen` the partial unique key over the live statuses
-- (pinned by the assertions far above) refuses a second live membership for
-- the same member. So it is created in the closing section, after ...201 has
-- been cancelled, as an assertion in its own right.

-- An approved pause on ...207, covering today. Nothing in the rewritten
-- requirement mentions membership_pauses at all -- it is checked here purely
-- to prove the gate does not silently grow an extra, unstated condition from
-- a neighbouring table.
insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, approved_by_staff_id, approved_at)
values ('cafe1600-0000-4000-8000-000000000061', 'aa000016-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000207',
        (select today - 5 from h16c_today where tenant_id = 'aa000016-0000-4000-8000-000000000001'),
        (select today + 5 from h16c_today where tenant_id = 'aa000016-0000-4000-8000-000000000001'),
        'h16 holdout addendum: approved pause covering today', 'aa000016-0000-4000-8000-000000000021', now());

-- Gym P (Etc/GMT-12): ...111 sits on the boundary in ITS OWN day, ...112
-- lapsed yesterday in ITS OWN day, ...113 starts tomorrow in ITS OWN day --
-- the sharpest possible version of "not started yet", one day off instead of
-- "next Monday".
insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('cafe1600-0000-4000-8000-000000000111', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000011', 'H16C TZP Boundary', '+919600170111'),
       ('cafe1600-0000-4000-8000-000000000112', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000011', 'H16C TZP Lapsed', '+919600170112'),
       ('cafe1600-0000-4000-8000-000000000113', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000011', 'H16C TZP Starts Tomorrow', '+919600170113');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
values ('cafe1600-0000-4000-8000-000000000211', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000111', 'cafe1600-0000-4000-8000-000000000025',
        'active', date '2020-01-01',
        (select today from h16c_today where tenant_id = 'cafe1600-0000-4000-8000-000000000001'), 100000),
       ('cafe1600-0000-4000-8000-000000000212', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000112', 'cafe1600-0000-4000-8000-000000000025',
        'active', date '2020-01-01',
        (select today - 1 from h16c_today where tenant_id = 'cafe1600-0000-4000-8000-000000000001'), 100000),
       ('cafe1600-0000-4000-8000-000000000213', 'cafe1600-0000-4000-8000-000000000001',
        'cafe1600-0000-4000-8000-000000000113', 'cafe1600-0000-4000-8000-000000000025',
        'active',
        (select today + 1 from h16c_today where tenant_id = 'cafe1600-0000-4000-8000-000000000001'),
        date '2030-01-01', 100000);

-- Gym M (Etc/GMT+12), 24 hours from gym P at every instant.
insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('cafe1600-0000-4000-8000-000000000121', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000012', 'H16C TZM Boundary', '+919600170121'),
       ('cafe1600-0000-4000-8000-000000000122', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000012', 'H16C TZM Lapsed', '+919600170122');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
values ('cafe1600-0000-4000-8000-000000000221', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000121', 'cafe1600-0000-4000-8000-000000000026',
        'active', date '2020-01-01',
        (select today from h16c_today where tenant_id = 'cafe1600-0000-4000-8000-000000000002'), 100000),
       ('cafe1600-0000-4000-8000-000000000222', 'cafe1600-0000-4000-8000-000000000002',
        'cafe1600-0000-4000-8000-000000000122', 'cafe1600-0000-4000-8000-000000000026',
        'active', date '2020-01-01',
        (select today - 1 from h16c_today where tenant_id = 'cafe1600-0000-4000-8000-000000000002'), 100000);

-- Act as gym A's own front desk again for the addendum's gym-A assertions.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000016-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', 'aa000016-0000-4000-8000-000000000021')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000101', 'cafe1600-0000-4000-8000-000000000201',
            timestamptz '2026-05-10 06:00:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  'A frozen membership whose dates are genuinely live is live -- frozen is not a status that alone excuses the dates from being checked');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000102', 'cafe1600-0000-4000-8000-000000000202',
            timestamptz '2026-05-10 06:00:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'A frozen membership whose dates lapsed a decade ago is refused -- ADR-075''s fix restated for `frozen`, not just `active`, since the old bug was in the vocabulary check, which never distinguished the two');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000103', timestamptz '2026-05-10 06:10:00+05:30', 'qr',
            'aa000016-0000-4000-8000-000000000051')$$,
  'A member holding one long-cancelled, date-lapsed membership AND one active, date-live membership is admitted -- the lapsed row''s presence does not blind the gate to the live one. membership_id is left unsupplied deliberately: the gate is evaluated against the MEMBER''s entitlement, not against whichever specific membership row a caller happens to cite');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000104', 'cafe1600-0000-4000-8000-000000000205',
            timestamptz '2026-05-10 06:20:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  'A membership whose starts_on IS the gym''s own today is live -- the open boundary the visible spec''s "starts next Monday" scenario never reaches: today itself, not merely some day still in the future. An implementation using `>` where the rule needs `>=` fails exactly this case and no other');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000106', 'cafe1600-0000-4000-8000-000000000207',
            timestamptz '2026-05-10 06:40:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  'A frozen membership with live dates is not additionally refused for having a currently-approved pause covering today -- the rewritten requirement names only status and dates, and does not gain an unstated third condition by way of membership_pauses');

-- The second statement (ADR-070): the gate is a `before insert` trigger and
-- nothing about `memberships` is frozen by it. What may be done to the CITED
-- membership is `memberships`' own business under `memberships`' own rules,
-- not this gate's -- but the recorded visit must not move with it, and a fresh
-- insert made after the member's entitlement has changed must be judged on the
-- entitlement as it stands then, not on the one the previous insert saw.
--
-- READ THIS BEFORE COLLAPSING THE FOUR STATEMENTS BELOW BACK INTO ONE.
-- Until Phase 5 this section lapsed the membership the obvious way --
-- `update memberships set ends_on = today - 1` -- and that statement is now
-- refused from every session (`GL045`, ADR-093: a membership's dates are what
-- its payments bought, and they move only inside the rule that grants a
-- period). So the fixture reaches the same STATE through writes the money
-- rules still permit: `status` is frozen by nothing, and the member is moved
-- off their live membership and onto an already-lapsed one -- which is what
-- the old date edit amounted to from this gate's point of view anyway, since
-- the gate reads the MEMBER's entitlement and not the row a caller cites.
-- Putting the date edit back turns this section red on a `memberships` rule
-- and proves nothing whatever about the check-in gate.
set local role postgres;

-- The one line the deleted date edit earns on its way out. It is not an
-- assertion about what `memberships` allows -- it is about WHOSE rule refuses:
-- the code raised here is the money rule's, and the surviving form of "this
-- gate has no say over `memberships`" is that the refusal is not its.
select throws_ok(
  $$update public.memberships set ends_on = (select today - 1 from h16c_today
     where tenant_id = 'aa000016-0000-4000-8000-000000000001')
   where id = 'cafe1600-0000-4000-8000-000000000201'$$,
  'GL045', null::text,
  'Editing a membership''s own ends_on into the past is refused -- but by a rule living on `memberships` that names itself GL045, not by this gate, whose own refusals carry a different code entirely. The check-in gate still has no say over `memberships`; something else acquired one, and that is the only reason this line is a throws_ok and not the lives_ok it used to be');

select lives_ok(
  $$update public.memberships set status = 'cancelled'
   where id = 'cafe1600-0000-4000-8000-000000000201'$$,
  'Cancelling the very membership an earlier visit cited is an ordinary write this gate has no say over -- its rules live on `attendance`, not on `memberships`, and it neither refuses the write nor reaches back into the visit that cited the row');

select is(
  (select row(checked_in_at, membership_id)::text from public.attendance
    where tenant_id = 'aa000016-0000-4000-8000-000000000001'
      and member_id = 'cafe1600-0000-4000-8000-000000000101'),
  row(timestamptz '2026-05-10 06:00:00+05:30', 'cafe1600-0000-4000-8000-000000000201'::uuid)::text,
  'The visit recorded while the membership was live is untouched by the later change -- a membership ceasing to be live after the fact does not retroactively rewrite or void the attendance row that cited it while it was');

-- ...101's second membership, CREATED here in the state it is needed in.
--
-- READ THIS BEFORE TURNING IT BACK INTO AN UPDATE. Until 2026-09-13 this line
-- reached the same state by reviving a retirement: ...206 was declared
-- `expired` up in the fixture block and this statement was
-- `update memberships set status = 'active' where id = ...206`. That route is
-- refused from every session as of `GL047`: `expired` and `cancelled` are
-- terminal and nothing comes back out of them, which is the whole point of
-- the rule -- a critic had walked a retired membership back to life from an
-- ordinary front-desk session in exactly that one statement. Putting the
-- update back turns this line red on a `memberships` rule, the same way the
-- `ends_on` edit two assertions up did, and proves nothing about this gate.
--
-- Creation is the door that stays open, deliberately (OPEN-029): no rule
-- judges the status a membership is BORN in, and `supabase/seed.sql` builds
-- its own lapsed fixtures this way. The alternatives were weighed and lost.
-- `app.grant_periods()` only ever moves `ends_on` FORWARD, so the granting
-- rule cannot manufacture a past end date at all. A direct `ends_on` edit is
-- `GL045`, which the assertion two lines up already pins. And a SECOND MEMBER
-- would reach the same status/date combination while throwing away the
-- property the NEXT assertion actually rests on -- that this is the SAME
-- member whose earlier visit still stands, judged fresh on the entitlement as
-- it stands now. The member is load-bearing; the route was not.
--
-- It also has to come after ...201's cancellation rather than before it:
-- `active` is a live status, and a second live membership for one member is
-- refused by the partial unique key the assertions far above pin.
select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status,
                                    starts_on, ends_on, price_paise)
    values ('cafe1600-0000-4000-8000-000000000206', 'aa000016-0000-4000-8000-000000000001',
            'cafe1600-0000-4000-8000-000000000101', 'aa000016-0000-4000-8000-000000000025',
            'active', date '2020-01-01',
            (select today - 1 from h16c_today
              where tenant_id = 'aa000016-0000-4000-8000-000000000001'),
            100000)$$,
  'And the member is moved ONTO a long-lapsed membership -- one created with a LIVE status and dates that ended yesterday in the gym''s own day, since nothing judges the status a membership is born in (OPEN-029) even though GL047 now forbids reaching that status from a retirement. This reconstructs exactly the state the old `ends_on` edit produced, and the revival that replaced it produced (one live-STATUS membership whose dates are behind today), by the only route the rules still permit -- and if creation is ever governed too, this line goes red first and says so');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000101', 'cafe1600-0000-4000-8000-000000000206',
            timestamptz '2026-05-10 09:00:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'A member CAN be moved onto a lapsed membership between two check-ins -- liveness is re-evaluated fresh on this new insert, against the entitlement as it stands NOW, and this second visit is refused even though the first, hours earlier by the same member, still stands. Nothing was carried over from the first insert, and the refusal is the DATE half specifically: the membership cited here holds a live status');

-- The trusted-context question, decided from the spec: nothing in ATT-001
-- carves out an exception for who is asking. This file's own top-of-file
-- fixture inserts already run under `postgres`, and its own comment on row
-- ...072 records that app.enforce_check_in() fired even there. Restated here
-- for the DATE half of the rule specifically, with no request.jwt.claims set
-- at all -- the shape of a trusted backend job, not a front-desk session.
reset role;
set local role postgres;

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('aa000016-0000-4000-8000-000000000001', 'aa000016-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000102', 'cafe1600-0000-4000-8000-000000000202',
            timestamptz '2026-05-10 10:00:00+05:30', 'qr', 'aa000016-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'The live-membership gate is not merely a front-office-session courtesy: a trusted-context insert with no JWT claims at all, run as the owner role, is refused for the same date-lapsed membership -- the guard is a property of inserting into attendance, not of the session that does it');

-- The timezone itself. Gym P (Etc/GMT-12) and gym M (Etc/GMT+12) are 24 hours
-- apart at every instant, and both differ from the server's own UTC date for
-- most of any given day. Each is evaluated in ITS OWN day, read from
-- organizations.timezone, never from current_date.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'cafe1600-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', 'cafe1600-0000-4000-8000-000000000021')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('cafe1600-0000-4000-8000-000000000001', 'cafe1600-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000111', 'cafe1600-0000-4000-8000-000000000211',
            now(), 'qr', 'cafe1600-0000-4000-8000-000000000051')$$,
  'Gym P (Etc/GMT-12): a membership ending on gym P''s OWN today is live -- evaluated in a day that is not the server''s UTC date for most of the clock');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('cafe1600-0000-4000-8000-000000000001', 'cafe1600-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000112', 'cafe1600-0000-4000-8000-000000000212',
            now(), 'qr', 'cafe1600-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'Gym P: a membership that ended yesterday IN GYM P''S OWN DAY is refused -- an implementation reading the server''s UTC date instead gets this wrong on whichever side of local midnight the server currently sits');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('cafe1600-0000-4000-8000-000000000001', 'cafe1600-0000-4000-8000-000000000011',
            'cafe1600-0000-4000-8000-000000000113', 'cafe1600-0000-4000-8000-000000000213',
            now(), 'qr', 'cafe1600-0000-4000-8000-000000000051')$$,
  null::char(5), null::text,
  'Gym P: a membership starting tomorrow IN GYM P''S OWN DAY is refused -- the sharpest version of "not started yet", one day off rather than a whole week');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'cafe1600-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', 'cafe1600-0000-4000-8000-000000000022')::text,
  true
);

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('cafe1600-0000-4000-8000-000000000002', 'cafe1600-0000-4000-8000-000000000012',
            'cafe1600-0000-4000-8000-000000000121', 'cafe1600-0000-4000-8000-000000000221',
            now(), 'qr', 'cafe1600-0000-4000-8000-000000000052')$$,
  'Gym M (Etc/GMT+12, 24 hours from gym P at every instant): a membership ending on gym M''s OWN today is live -- proving the day used is THIS gym''s, not gym P''s, not the server''s');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('cafe1600-0000-4000-8000-000000000002', 'cafe1600-0000-4000-8000-000000000012',
            'cafe1600-0000-4000-8000-000000000122', 'cafe1600-0000-4000-8000-000000000222',
            now(), 'qr', 'cafe1600-0000-4000-8000-000000000052')$$,
  null::char(5), null::text,
  'Gym M: a membership that ended yesterday in gym M''s own day is refused, on gym M''s own clock, independent of gym P''s');

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
