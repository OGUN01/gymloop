-- h06_attendance — HOLDOUT pgTAP suite for the `attendance` cluster.
--
-- Written blind from openspec/changes/0001-data-model/specs/attendance/spec.md
-- and docs/domain-rules.md (ATT-003, ATT-005..008, DQA-003, INT-001, STK-002),
-- never from the migration. Tables under test: qr_sessions, attendance,
-- attendance_corrections, organization_holidays.
--
-- ADR-030: the whole file is one transaction and ends in ROLLBACK — the suite
-- runs against the shared Cloud project. No anonymous PL/pgSQL block appears
-- here: check-pgtap-rollback.mjs strips comments, splits on the semicolon and
-- uppercases, so a block's closing END would read as a bare END statement.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(67);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner: `postgres` holds BYPASSRLS, so RLS does not
-- apply here. Two gyms, each with a branch, a staff member, a member, a QR
-- session, a visit, a correction and a holiday.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('aa000006-0000-4000-8000-000000000001', 'Holdout Attendance Gym A', 'HAT06A'),
       ('aa000006-0000-4000-8000-000000000002', 'Holdout Attendance Gym B', 'HAT06B');

insert into public.branches (id, tenant_id, name)
values ('aa000006-0000-4000-8000-000000000011', 'aa000006-0000-4000-8000-000000000001', 'H06 Main A'),
       ('aa000006-0000-4000-8000-000000000012', 'aa000006-0000-4000-8000-000000000002', 'H06 Main B');

insert into public.staff (id, tenant_id, branch_id, role, full_name)
values ('aa000006-0000-4000-8000-000000000021', 'aa000006-0000-4000-8000-000000000001',
        'aa000006-0000-4000-8000-000000000011', 'front_desk', 'H06 Desk A'),
       ('aa000006-0000-4000-8000-000000000022', 'aa000006-0000-4000-8000-000000000002',
        'aa000006-0000-4000-8000-000000000012', 'front_desk', 'H06 Desk B');

insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('aa000006-0000-4000-8000-000000000031', 'aa000006-0000-4000-8000-000000000001',
        'aa000006-0000-4000-8000-000000000011', 'H06 Member A', '+919600060001'),
       ('aa000006-0000-4000-8000-000000000032', 'aa000006-0000-4000-8000-000000000002',
        'aa000006-0000-4000-8000-000000000012', 'H06 Member B', '+919600060002');

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at)
values ('aa000006-0000-4000-8000-000000000041', 'aa000006-0000-4000-8000-000000000001',
        'aa000006-0000-4000-8000-000000000011', 'h06-token-hash-a',
        timestamptz '2026-03-01 06:00+05:30', timestamptz '2026-03-01 06:05+05:30'),
       ('aa000006-0000-4000-8000-000000000042', 'aa000006-0000-4000-8000-000000000002',
        'aa000006-0000-4000-8000-000000000012', 'h06-token-hash-b',
        timestamptz '2026-03-01 06:00+05:30', timestamptz '2026-03-01 06:05+05:30');

insert into public.attendance (id, tenant_id, branch_id, member_id, checked_in_at, source)
values ('aa000006-0000-4000-8000-000000000051', 'aa000006-0000-4000-8000-000000000001',
        'aa000006-0000-4000-8000-000000000011', 'aa000006-0000-4000-8000-000000000031',
        timestamptz '2026-03-01 06:01+05:30', 'qr'),
       ('aa000006-0000-4000-8000-000000000052', 'aa000006-0000-4000-8000-000000000002',
        'aa000006-0000-4000-8000-000000000012', 'aa000006-0000-4000-8000-000000000032',
        timestamptz '2026-03-01 06:01+05:30', 'qr');

insert into public.attendance_corrections (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
values ('aa000006-0000-4000-8000-000000000061', 'aa000006-0000-4000-8000-000000000001',
        'aa000006-0000-4000-8000-000000000051', 'aa000006-0000-4000-8000-000000000021',
        'h06 wrong member scanned', '{}'::jsonb, '{}'::jsonb),
       ('aa000006-0000-4000-8000-000000000062', 'aa000006-0000-4000-8000-000000000002',
        'aa000006-0000-4000-8000-000000000052', 'aa000006-0000-4000-8000-000000000022',
        'h06 wrong member scanned', '{}'::jsonb, '{}'::jsonb);

insert into public.organization_holidays (id, tenant_id, holiday_on, name)
values ('aa000006-0000-4000-8000-000000000071', 'aa000006-0000-4000-8000-000000000001',
        date '2026-01-26', 'H06 Republic Day A'),
       ('aa000006-0000-4000-8000-000000000072', 'aa000006-0000-4000-8000-000000000002',
        date '2026-08-15', 'H06 Independence Day B');

-- ---------------------------------------------------------------------------
-- No claim at all: the GUC has never been set in this transaction. Every table
-- must return zero rows, and must do so silently — a policy that raised would
-- let a caller tell "wrong tenant" apart from "nothing here".
-- ---------------------------------------------------------------------------

set local role authenticated;

select is((select count(*)::int from public.qr_sessions), 0,
  'RLS: with no jwt claims set at all, qr_sessions returns zero rows without raising');
select is((select count(*)::int from public.attendance), 0,
  'RLS: with no jwt claims set at all, attendance returns zero rows without raising');
select is((select count(*)::int from public.attendance_corrections), 0,
  'RLS: with no jwt claims set at all, attendance_corrections returns zero rows without raising');
select is((select count(*)::int from public.organization_holidays), 0,
  'RLS: with no jwt claims set at all, organization_holidays returns zero rows without raising');

set local role postgres;

-- The empty-string claim is the second shape of a missing claim.

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is((select count(*)::int from public.attendance), 0,
  'RLS: an empty-string jwt claims setting yields zero attendance rows, not an error');
select is((select count(*)::int from public.qr_sessions), 0,
  'RLS: an empty-string jwt claims setting yields zero qr_sessions rows, not an error');

set local role postgres;

-- ---------------------------------------------------------------------------
-- Act as a signed-in gym_owner of Gym A.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000006-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- Positive controls first: a table with RLS enabled and no policy at all would
-- pass every isolation assertion below while being useless.

select is((select count(*)::int from public.qr_sessions
           where id = 'aa000006-0000-4000-8000-000000000041'), 1,
  'RLS: gym A reads its own qr_sessions row');
select is((select count(*)::int from public.attendance
           where id = 'aa000006-0000-4000-8000-000000000051'), 1,
  'RLS: gym A reads its own attendance row');
select is((select count(*)::int from public.attendance_corrections
           where id = 'aa000006-0000-4000-8000-000000000061'), 1,
  'RLS: gym A reads its own attendance_corrections row');
select is((select count(*)::int from public.organization_holidays
           where id = 'aa000006-0000-4000-8000-000000000071'), 1,
  'RLS: gym A reads its own organization_holidays row');

-- qr_sessions: read, update, insert-as-B, delete.

select is((select count(*)::int from public.qr_sessions
           where id = 'aa000006-0000-4000-8000-000000000042'), 0,
  'RLS: gym A cannot read gym B''s qr_sessions row');

with u as (
  update public.qr_sessions set revoked_at = now()
   where id = 'aa000006-0000-4000-8000-000000000042'
  returning 1
)
select is((select count(*)::int from u), 0,
  'RLS: gym A''s update of gym B''s qr_sessions row by pk touches no rows');

select throws_ok(
  $$insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
    values ('aa000006-0000-4000-8000-000000000002', 'aa000006-0000-4000-8000-000000000012',
            'h06-token-hash-x1', timestamptz '2026-03-02 06:00+05:30', timestamptz '2026-03-02 06:05+05:30')$$,
  '42501', null,
  'RLS: gym A cannot insert a qr_sessions row labelled with gym B''s tenant');

select throws_ok(
  $$delete from public.qr_sessions where id = 'aa000006-0000-4000-8000-000000000042'$$,
  '42501', null,
  'RLS/INT-001: gym A''s delete of gym B''s qr_sessions row is refused');

-- attendance: read, update, insert-as-B, delete.

select is((select count(*)::int from public.attendance
           where id = 'aa000006-0000-4000-8000-000000000052'), 0,
  'RLS: gym A cannot read gym B''s attendance row');

with u as (
  update public.attendance set checked_out_at = timestamptz '2026-03-01 07:00+05:30'
   where id = 'aa000006-0000-4000-8000-000000000052'
  returning 1
)
select is((select count(*)::int from u), 0,
  'RLS: gym A''s update of gym B''s attendance row by pk touches no rows');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000006-0000-4000-8000-000000000002', 'aa000006-0000-4000-8000-000000000012',
            'aa000006-0000-4000-8000-000000000032', timestamptz '2026-03-02 06:01+05:30', 'qr')$$,
  '42501', null,
  'RLS: gym A cannot insert an attendance row labelled with gym B''s tenant');

select throws_ok(
  $$delete from public.attendance where id = 'aa000006-0000-4000-8000-000000000052'$$,
  '42501', null,
  'RLS/INT-001: gym A''s delete of gym B''s attendance row is refused');

-- attendance_corrections: read, insert-as-B, delete. It is append-only, so an
-- update is refused for want of privilege rather than filtered — asserted below
-- against gym A's own row, where privilege is the only thing that can refuse it.

select is((select count(*)::int from public.attendance_corrections
           where id = 'aa000006-0000-4000-8000-000000000062'), 0,
  'RLS: gym A cannot read gym B''s attendance_corrections row');

select throws_ok(
  $$insert into public.attendance_corrections (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
    values ('aa000006-0000-4000-8000-000000000002', 'aa000006-0000-4000-8000-000000000052',
            'aa000006-0000-4000-8000-000000000022', 'h06 cross tenant', '{}'::jsonb, '{}'::jsonb)$$,
  '42501', null,
  'RLS: gym A cannot insert an attendance_corrections row labelled with gym B''s tenant');

select throws_ok(
  $$delete from public.attendance_corrections where id = 'aa000006-0000-4000-8000-000000000062'$$,
  '42501', null,
  'RLS/INT-001: gym A''s delete of gym B''s attendance_corrections row is refused');

-- organization_holidays: read, update, insert-as-B, delete.

select is((select count(*)::int from public.organization_holidays
           where id = 'aa000006-0000-4000-8000-000000000072'), 0,
  'RLS: gym A cannot read gym B''s organization_holidays row');

with u as (
  update public.organization_holidays set name = 'h06 renamed by gym A'
   where id = 'aa000006-0000-4000-8000-000000000072'
  returning 1
)
select is((select count(*)::int from u), 0,
  'RLS: gym A''s update of gym B''s organization_holidays row by pk touches no rows');

select throws_ok(
  $$insert into public.organization_holidays (tenant_id, holiday_on, name)
    values ('aa000006-0000-4000-8000-000000000002', date '2026-12-25', 'h06 cross tenant')$$,
  '42501', null,
  'RLS: gym A cannot insert an organization_holidays row labelled with gym B''s tenant');

select throws_ok(
  $$delete from public.organization_holidays where id = 'aa000006-0000-4000-8000-000000000072'$$,
  '42501', null,
  'RLS: gym A''s delete of gym B''s organization_holidays row is refused');

-- ---------------------------------------------------------------------------
-- ATT-005 / ATT-006 — an assisted front-desk check-in names the staff member
-- and carries a non-empty reason, and the pair is symmetric.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assisted_by_staff_id)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:00+05:30',
            'front_desk', 'aa000006-0000-4000-8000-000000000021')$$,
  '23514', null,
  'ATT-005/006: a front_desk check-in with no assist_reason is rejected');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assisted_by_staff_id, assist_reason)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:01+05:30',
            'front_desk', 'aa000006-0000-4000-8000-000000000021', '')$$,
  '23514', null,
  'ATT-006: a front_desk check-in with an empty-string assist_reason is rejected');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assist_reason)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:02+05:30',
            'front_desk', 'h06 member forgot phone')$$,
  '23514', null,
  'ATT-005: a front_desk check-in with a reason but no acting staff member is rejected');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:03+05:30', 'qr')$$,
  'ATT-005/006: a qr check-in needs neither an acting staff member nor a reason');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assisted_by_staff_id)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:04+05:30',
            'qr', 'aa000006-0000-4000-8000-000000000021')$$,
  '23514', null,
  'ATT-005/006: an acting staff member recorded with no reason is rejected on any source');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assist_reason)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:05+05:30',
            'qr', 'h06 turnstile jammed')$$,
  '23514', null,
  'ATT-005/006: a reason recorded with no acting staff member is rejected on any source');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, assisted_by_staff_id, assist_reason)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-03 06:06+05:30',
            'front_desk', 'aa000006-0000-4000-8000-000000000021', 'h06 member forgot phone')$$,
  'ATT-005/006: a front_desk check-in naming both the staff member and a reason is accepted');

-- ---------------------------------------------------------------------------
-- ATT-007 — the offline audit stamp is both timestamps or neither, and a
-- device-generated event id replays exactly once per organisation.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, offline_recorded_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-04 06:00+05:30',
            'qr', timestamptz '2026-03-04 05:55+05:30')$$,
  '23514', null,
  'ATT-007: an offline timestamp with no replay time is rejected');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, replayed_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-04 06:01+05:30',
            'qr', timestamptz '2026-03-04 08:00+05:30')$$,
  '23514', null,
  'ATT-007: a replay time with no offline timestamp is rejected');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, offline_recorded_at, replayed_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-04 06:02+05:30',
            'qr', timestamptz '2026-03-04 05:55+05:30', timestamptz '2026-03-04 08:00+05:30')$$,
  'ATT-007: a replayed row carrying both the offline timestamp and the replay time is accepted');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, client_event_id)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-05 06:00+05:30',
            'qr', 'aa000006-0000-4000-8000-000000000081')$$,
  'ATT-007: the first replay of a queued check-in is accepted');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, client_event_id)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-05 06:00+05:30',
            'qr', 'aa000006-0000-4000-8000-000000000081')$$,
  '23505', null,
  'ATT-007: the same client_event_id replayed twice in one organisation is rejected');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-06 06:00+05:30', 'qr')$$,
  'ATT-007: a live check-in with no client_event_id is accepted');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-06 06:00+05:30', 'qr')$$,
  'ATT-007: a second live check-in with no client_event_id is accepted, so the uniqueness is partial');

-- ---------------------------------------------------------------------------
-- ATT-008 — check-out is optional and never precedes check-in.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, checked_out_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-07 07:00+05:30',
            timestamptz '2026-03-07 06:00+05:30', 'qr')$$,
  '23514', null,
  'ATT-008: a check-out earlier than its check-in is rejected');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, checked_out_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-07 07:01+05:30',
            null, 'qr')$$,
  'ATT-008: a visit with no check-out is valid and blocks nothing');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, checked_out_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-000000000031', timestamptz '2026-03-07 07:02+05:30',
            timestamptz '2026-03-07 07:02+05:30', 'qr')$$,
  'ATT-008: a check-out equal to its check-in is accepted (the bound is inclusive)');

-- A visit is scoped to a member of the gym: an unknown member id is refused.

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'aa000006-0000-4000-8000-0000000000ff', timestamptz '2026-03-08 06:00+05:30', 'qr')$$,
  '23503', null,
  'A visit referencing a member id that does not exist is rejected');

-- ---------------------------------------------------------------------------
-- DQA-003 / INT-001 — a visit is corrected, never removed or edited.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance_corrections (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000051',
            'aa000006-0000-4000-8000-000000000021', '', '{}'::jsonb, '{}'::jsonb)$$,
  '23514', null,
  'DQA-003: a correction with an empty reason is rejected');

select lives_ok(
  $$insert into public.attendance_corrections (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000051',
            'aa000006-0000-4000-8000-000000000021', 'h06 checked in at the wrong branch',
            '{}'::jsonb, '{}'::jsonb)$$,
  'DQA-003: a correction carrying a non-empty reason and the acting staff member is accepted');

select throws_ok(
  $$update public.attendance_corrections set reason = 'h06 edited'
     where id = 'aa000006-0000-4000-8000-000000000061'$$,
  '42501', null,
  'INT-001: a signed-in caller cannot edit a correction in their own tenant');

select throws_ok(
  $$delete from public.attendance where id = 'aa000006-0000-4000-8000-000000000051'$$,
  '42501', null,
  'INT-001: a signed-in caller cannot delete a visit in their own tenant');

-- ---------------------------------------------------------------------------
-- ATT-003 — a QR session expires, and only its hash is stored.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'h06-token-hash-a2', timestamptz '2026-03-09 06:00+05:30', timestamptz '2026-03-09 05:00+05:30')$$,
  '23514', null,
  'ATT-003: a QR session whose expiry precedes its issue time is rejected');

select throws_ok(
  $$insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'h06-token-hash-a3', timestamptz '2026-03-09 06:00+05:30', timestamptz '2026-03-09 06:00+05:30')$$,
  '23514', null,
  'ATT-003: a QR session that expires at its issue time is rejected — the expiry must be later');

select throws_ok(
  $$insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
    values ('aa000006-0000-4000-8000-000000000001', 'aa000006-0000-4000-8000-000000000011',
            'h06-token-hash-a', timestamptz '2026-03-09 06:00+05:30', timestamptz '2026-03-09 06:05+05:30')$$,
  '23505', null,
  'ATT-003: a second QR session reusing an existing token hash is rejected');

-- ---------------------------------------------------------------------------
-- The holiday calendar has one entry per date per gym (STK-002 needs it
-- unambiguous).
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.organization_holidays (tenant_id, holiday_on, name)
    values ('aa000006-0000-4000-8000-000000000001', date '2026-01-26', 'h06 duplicate')$$,
  '23505', null,
  'STK-002: a second holiday for the same gym and date is rejected');

set local role postgres;

-- ---------------------------------------------------------------------------
-- Gym B: the same device event id and the same holiday date belong to another
-- gym's rows, so they are accepted there.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000006-0000-4000-8000-000000000002',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, checked_in_at, source, client_event_id)
    values ('aa000006-0000-4000-8000-000000000002', 'aa000006-0000-4000-8000-000000000012',
            'aa000006-0000-4000-8000-000000000032', timestamptz '2026-03-05 06:00+05:30',
            'qr', 'aa000006-0000-4000-8000-000000000081')$$,
  'ATT-007: the same client_event_id at a different gym is accepted — replay is scoped per organisation');

select lives_ok(
  $$insert into public.organization_holidays (tenant_id, holiday_on, name)
    values ('aa000006-0000-4000-8000-000000000002', date '2026-01-26', 'h06 Republic Day B')$$,
  'STK-002: two gyms may hold a holiday on the same date');

set local role postgres;

-- ---------------------------------------------------------------------------
-- The platform branch: super_admin and platform_support cross tenants, and the
-- gym_owner assertions above show a gym role does not.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'aa000006-0000-4000-8000-000000000001',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is((select count(*)::int from public.attendance
           where id = 'aa000006-0000-4000-8000-000000000052'), 1,
  'RLS: super_admin reads gym B''s attendance row while claiming gym A');
select is((select count(*)::int from public.qr_sessions
           where id = 'aa000006-0000-4000-8000-000000000042'), 1,
  'RLS: super_admin reads gym B''s qr_sessions row while claiming gym A');
select is((select count(*)::int from public.attendance_corrections
           where id = 'aa000006-0000-4000-8000-000000000062'), 1,
  'RLS: super_admin reads gym B''s attendance_corrections row while claiming gym A');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', null::text,
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select is((select count(*)::int from public.organization_holidays
           where id = 'aa000006-0000-4000-8000-000000000072'), 1,
  'RLS: platform_support with no tenant claim still reads gym B''s organization_holidays row');
select is((select count(*)::int from public.attendance
           where id = 'aa000006-0000-4000-8000-000000000052'), 1,
  'RLS: platform_support with no tenant claim still reads gym B''s attendance row');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- Shape and privilege, asserted as the owner so the result does not depend on
-- which role the session happens to be in.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
    values ('aa000006-0000-4000-8000-000000000002', 'aa000006-0000-4000-8000-000000000012',
            'h06-token-hash-a', timestamptz '2026-03-10 06:00+05:30', timestamptz '2026-03-10 06:05+05:30')$$,
  '23505', null,
  'ATT-003: a token hash is unique across the whole table, not merely within a gym');

select hasnt_column('public', 'qr_sessions', 'token',
  'ATT-003: qr_sessions has no column holding the raw token');
select hasnt_column('public', 'qr_sessions', 'raw_token',
  'ATT-003: qr_sessions has no raw_token column either');
select has_column('public', 'qr_sessions', 'token_hash',
  'ATT-003: qr_sessions stores the token as a hash');

select ok(not has_table_privilege('authenticated', 'public.attendance', 'DELETE'),
  'INT-001: authenticated holds no DELETE on attendance');
select ok(not has_table_privilege('authenticated', 'public.attendance_corrections', 'DELETE'),
  'INT-001: authenticated holds no DELETE on attendance_corrections');
select ok(not has_table_privilege('authenticated', 'public.qr_sessions', 'DELETE'),
  'INT-001: authenticated holds no DELETE on qr_sessions');
select ok(not has_table_privilege('authenticated', 'public.organization_holidays', 'DELETE'),
  'INT-001: authenticated holds no DELETE on organization_holidays');
select ok(not has_table_privilege('authenticated', 'public.attendance_corrections', 'UPDATE'),
  'INT-001: attendance_corrections is append-only — authenticated holds no UPDATE');

select * from finish();

rollback;
