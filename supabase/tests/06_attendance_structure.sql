-- 06_attendance_structure.sql — cluster: attendance
--
-- Shape of the attendance_source enum, qr_sessions (ATT-003),
-- organization_holidays (STK-002) and attendance_corrections (INT-001, DQA-003).
-- The attendance table's own constraints are in 06_attendance_checkin.sql;
-- the cross-tenant matrix is in 06_attendance_rls.sql.
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
-- Fixtures. Inserted as postgres, which owns every table the migrations create
-- and bypasses RLS because the contract forbids `force row level security`
-- (docs/data-model.md, "Row-Level Security").
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
   'a0000000-0000-4000-8000-000000000002', 'A Member', '+919900000001');

insert into public.attendance (id, tenant_id, branch_id, member_id, source) values
  ('a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000004', 'qr');

-- ---------------------------------------------------------------------------
-- The enum this cluster owns. The label order is part of the contract because
-- it is what `supabase gen types` emits (docs/data-model.md, "Enums").
-- ---------------------------------------------------------------------------

select has_enum('public', 'attendance_source',
  'attendance_source exists in public');

select enum_has_labels('public', 'attendance_source',
  array['qr', 'front_desk']::name[],
  'attendance_source carries the contract labels, in the contract order');

-- ---------------------------------------------------------------------------
-- ATT-003 — "A QR session expires and only its hash is stored"
-- ---------------------------------------------------------------------------

select has_table('public', 'qr_sessions', 'qr_sessions exists');

select has_column('public', 'qr_sessions', 'token_hash',
  'ATT-003 — qr_sessions stores token_hash');

select hasnt_column('public', 'qr_sessions', 'token',
  'ATT-003 — qr_sessions has no plaintext token column');

select col_not_null('public', 'qr_sessions', 'expires_at',
  'ATT-003 — every QR session carries an expiry');

select lives_ok($$
  insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('a0000000-0000-4000-8000-000000000006',
          'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'hash-a-1',
          '2026-09-06T10:00:00Z',
          '2026-09-06T10:15:00Z')
$$, 'ATT-003 — a session whose expiry is after its issue time is accepted');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'hash-a-equal',
          '2026-09-06T10:00:00Z',
          '2026-09-06T10:00:00Z')
$$, '23514'::char(5), null,
  'ATT-003, scenario "A session that expires before it is issued" — expiry equal to issue time');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'hash-a-past',
          '2026-09-06T10:00:00Z',
          '2026-09-06T09:59:00Z')
$$, '23514'::char(5), null,
  'ATT-003, scenario "A session that expires before it is issued" — expiry before issue time');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'hash-a-1',
          '2026-09-06T11:00:00Z',
          '2026-09-06T11:15:00Z')
$$, '23505'::char(5), null,
  'ATT-003, scenario "A reused token hash" — same hash again in the same gym');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000002',
          'hash-a-1',
          '2026-09-06T11:00:00Z',
          '2026-09-06T11:15:00Z')
$$, '23505'::char(5), null,
  'ATT-003, scenario "A reused token hash" — the hash is unique globally, not per gym');

-- ---------------------------------------------------------------------------
-- STK-002 — "The gym's holiday calendar has one entry per date"
-- ---------------------------------------------------------------------------

select has_table('public', 'organization_holidays', 'organization_holidays exists');

select lives_ok($$
  insert into public.organization_holidays (id, tenant_id, holiday_on, name)
  values ('a0000000-0000-4000-8000-000000000008',
          'a0000000-0000-4000-8000-000000000001',
          date '2026-01-26', 'Republic Day A')
$$, 'STK-002 — a gym records a holiday');

select throws_ok($$
  insert into public.organization_holidays (tenant_id, holiday_on, name)
  values ('a0000000-0000-4000-8000-000000000001', date '2026-01-26', 'Republic Day again')
$$, '23505'::char(5), null,
  'STK-002, scenario "The same holiday twice" — one entry per organisation per date');

select lives_ok($$
  insert into public.organization_holidays (tenant_id, holiday_on, name)
  values ('b0000000-0000-4000-8000-000000000001', date '2026-01-26', 'Republic Day B')
$$, 'STK-002 — the uniqueness is per organisation, so another gym may hold the same date');

-- ---------------------------------------------------------------------------
-- INT-001 / DQA-003 — "A visit is corrected, never removed"
-- ---------------------------------------------------------------------------

select has_table('public', 'attendance_corrections', 'attendance_corrections exists');

select col_not_null('public', 'attendance_corrections', 'reason',
  'DQA-003 — a correction always carries a reason');

select col_not_null('public', 'attendance_corrections', 'corrected_by_staff_id',
  'DQA-003 — a correction always names the acting staff member');

select lives_ok($$
  insert into public.attendance_corrections
    (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
  values ('a0000000-0000-4000-8000-000000000007',
          'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000005',
          'a0000000-0000-4000-8000-000000000003',
          'wrong member scanned', '{}'::jsonb, '{}'::jsonb)
$$, 'DQA-003 — a correction with a reason and a staff member is accepted');

select throws_ok($$
  insert into public.attendance_corrections
    (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000005',
          'a0000000-0000-4000-8000-000000000003',
          '', '{}'::jsonb, '{}'::jsonb)
$$, '23514'::char(5), null,
  'DQA-003, scenario "A correction with no reason" — an empty-string reason');

select ok(has_table_privilege('authenticated', 'public.attendance_corrections', 'SELECT'),
  'INT-001 — append-only still means readable');

select ok(has_table_privilege('authenticated', 'public.attendance_corrections', 'INSERT'),
  'INT-001 — append-only still means insertable');

select ok(not has_table_privilege('authenticated', 'public.attendance_corrections', 'UPDATE'),
  'INT-001 — authenticated holds no UPDATE on attendance_corrections');

select ok(not has_table_privilege('authenticated', 'public.attendance_corrections', 'DELETE'),
  'INT-001 — authenticated holds no DELETE on attendance_corrections');

-- The privilege refusal, exercised in the caller's own tenant so the refusal is
-- unambiguously a want of privilege and not RLS filtering.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select throws_ok($$
  update public.attendance_corrections set reason = 'edited'
  where id = 'a0000000-0000-4000-8000-000000000007'
$$, '42501'::char(5), null,
  'INT-001, scenario "Editing a correction" — refused for want of privilege');

select throws_ok($$
  delete from public.attendance_corrections
  where id = 'a0000000-0000-4000-8000-000000000007'
$$, '42501'::char(5), null,
  'INT-001 — deleting a correction is refused for want of privilege');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
