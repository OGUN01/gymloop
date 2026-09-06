-- 06_attendance_checkin.sql — cluster: attendance
--
-- The attendance row itself: the assisted front-desk fallback (ATT-005,
-- ATT-006), exactly-once offline replay and its audit stamp (ATT-007), the
-- optional check-out (ATT-008), referential integrity, and the missing DELETE
-- privilege (INT-001).
--
-- Written from openspec/changes/0001-data-model/specs/attendance/spec.md before
-- the migration existed. ADR-030: one transaction, always rolled back.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(26);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as postgres (owner, bypasses RLS — no `force row level
-- security` on this project).
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001', 'Gym A', 'TSTA01'),
  ('b0000000-0000-4000-8000-000000000001', 'Gym B', 'TSTB01');

insert into public.branches (id, tenant_id, name) values
  ('a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'A Main'),
  ('b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'B Main');

insert into public.staff (id, tenant_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'front_desk', 'A Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Member', '+919900000001'),
  ('b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'B Member', '+919900000002');

select has_table('public', 'attendance', 'attendance exists');

select col_type_is('public', 'attendance', 'source', 'attendance_source',
  'attendance.source is the attendance_source enum');

select col_is_null('public', 'attendance', 'checked_out_at',
  'ATT-008 — check-out is optional');

-- ---------------------------------------------------------------------------
-- ATT-005 / ATT-006 — "An assisted check-in names the staff member and the reason"
-- ---------------------------------------------------------------------------

select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr')
$$, 'ATT-005/006, scenario "A QR check-in needs neither"');

select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'front_desk')
$$, '23514'::char(5), null,
  'ATT-006, scenario "A front-desk check-in with no reason"');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'front_desk',
          'a0000000-0000-4000-8000-000000000003', '')
$$, '23514'::char(5), null,
  'ATT-006, scenario "A front-desk check-in with an empty reason"');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assist_reason)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'front_desk', 'phone battery dead')
$$, '23514'::char(5), null,
  'ATT-005, scenario "A front-desk check-in with no acting staff member"');

select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id, assist_reason)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'front_desk',
          'a0000000-0000-4000-8000-000000000003', 'phone battery dead')
$$, 'ATT-005/006 — a front-desk check-in with both the staff member and a reason');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assist_reason)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr', 'turnstile jammed')
$$, '23514'::char(5), null,
  'ATT-005/006 — a reason without an acting staff member');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, assisted_by_staff_id)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          'a0000000-0000-4000-8000-000000000003')
$$, '23514'::char(5), null,
  'ATT-005/006 — an acting staff member without a reason');

-- ---------------------------------------------------------------------------
-- ATT-007 — "A queued offline check-in replays exactly once"
-- ---------------------------------------------------------------------------

select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, client_event_id)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          'e0000000-0000-4000-8000-00000000000e')
$$, 'ATT-007 — the first replay of a queued check-in is recorded');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, client_event_id)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          'e0000000-0000-4000-8000-00000000000e')
$$, '23505'::char(5), null,
  'ATT-007, scenario "The same queued check-in replayed twice"');

select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, client_event_id)
  values ('b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000002',
          'b0000000-0000-4000-8000-000000000004', 'qr',
          'e0000000-0000-4000-8000-00000000000e')
$$, 'ATT-007 — the device event id is unique per organisation, not globally');

select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr'),
         ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr')
$$, 'ATT-007, scenario "Two live check-ins with no device event id"');

-- ---------------------------------------------------------------------------
-- ATT-007's audit stamp — "An offline replay records both timestamps or neither"
-- ---------------------------------------------------------------------------

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, replayed_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr', '2026-09-06T12:00:00Z')
$$, '23514'::char(5), null,
  'ATT-007, scenario "A replay time with no offline time"');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, offline_recorded_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr', '2026-09-06T11:00:00Z')
$$, '23514'::char(5), null,
  'ATT-007, scenario "An offline time with no replay time"');

select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, offline_recorded_at, replayed_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          '2026-09-06T11:00:00Z', '2026-09-06T12:00:00Z')
$$, 'ATT-007 — both halves of the audit stamp together are accepted');

-- ---------------------------------------------------------------------------
-- ATT-008 — "Check-out is optional and never precedes check-in"
-- ---------------------------------------------------------------------------

select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, checked_in_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr', '2026-09-06T07:00:00Z')
$$, 'ATT-008, scenario "A visit with no check-out"');

select lives_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, checked_in_at, checked_out_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          '2026-09-06T07:00:00Z', '2026-09-06T07:00:00Z')
$$, 'ATT-008 — a check-out at the instant of check-in is accepted');

select throws_ok($$
  insert into public.attendance
    (tenant_id, branch_id, member_id, source, checked_in_at, checked_out_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr',
          '2026-09-06T07:00:00Z', '2026-09-06T06:59:00Z')
$$, '23514'::char(5), null,
  'ATT-008, scenario "A check-out before the check-in"');

-- ---------------------------------------------------------------------------
-- "A visit is scoped to a branch and a member of the same gym"
-- ---------------------------------------------------------------------------

select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'c0000000-0000-4000-8000-00000000dead', 'qr')
$$, '23503'::char(5), null,
  'Scenario "A visit by a member who does not exist"');

select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'c0000000-0000-4000-8000-00000000dead',
          'a0000000-0000-4000-8000-000000000004', 'qr')
$$, '23503'::char(5), null,
  'A visit at a branch that does not exist is rejected');

-- ---------------------------------------------------------------------------
-- INT-001 — "A visit is corrected, never removed"
-- ---------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.attendance', 'INSERT'),
  'attendance is insertable by authenticated');

select ok(has_table_privilege('authenticated', 'public.attendance', 'UPDATE'),
  'attendance is updatable by authenticated');

select ok(not has_table_privilege('authenticated', 'public.attendance', 'DELETE'),
  'INT-001 — authenticated holds no DELETE on attendance');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select throws_ok($$
  delete from public.attendance
  where tenant_id = 'a0000000-0000-4000-8000-000000000001'
$$, '42501'::char(5), null,
  'INT-001, scenario "Deleting a visit" — refused for want of privilege in the caller''s own tenant');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
