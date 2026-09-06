-- 06_attendance_rls.sql — cluster: attendance
--
-- The cross-tenant matrix for all four tables this cluster owns: select,
-- insert, update and delete as Gym A against Gym B; the platform branch
-- (`super_admin`) seeing both; and the no-claim caller, which sees zero rows
-- without raising and cannot insert (docs/security.md; docs/data-model.md,
-- "Row-Level Security"; ADR-032, ADR-033, ADR-037).
--
-- Written from openspec/changes/0001-data-model/specs/attendance/spec.md before
-- the migration existed. ADR-030: one transaction, always rolled back.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(39);

-- ---------------------------------------------------------------------------
-- Fixtures for two gyms, inserted as postgres (owner, bypasses RLS — the
-- contract forbids `force row level security`).
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001', 'Gym A', 'TSTA01'),
  ('b0000000-0000-4000-8000-000000000001', 'Gym B', 'TSTB01');

insert into public.branches (id, tenant_id, name) values
  ('a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'A Main'),
  ('b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'B Main');

insert into public.staff (id, tenant_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'front_desk', 'A Desk'),
  ('b0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000001', 'front_desk', 'B Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Member', '+919900000001'),
  ('b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'B Member', '+919900000002');

insert into public.attendance (id, tenant_id, branch_id, member_id, source) values
  ('a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000004', 'qr'),
  ('b0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000004', 'qr');

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at) values
  ('a0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'rls-hash-a',
   '2026-09-06T10:00:00Z', '2026-09-06T10:15:00Z'),
  ('b0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'rls-hash-b',
   '2026-09-06T10:00:00Z', '2026-09-06T10:15:00Z');

insert into public.attendance_corrections
  (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after) values
  ('a0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000003',
   'gym A reason', '{}'::jsonb, '{}'::jsonb),
  ('b0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000003',
   'gym B reason', '{}'::jsonb, '{}'::jsonb);

insert into public.organization_holidays (id, tenant_id, holiday_on, name) values
  ('a0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001',
   date '2026-01-26', 'Republic Day A'),
  ('b0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-000000000001',
   date '2026-01-26', 'Republic Day B');

-- ---------------------------------------------------------------------------
-- Gym A's owner. Everything below is the leak matrix required by gate 7
-- (docs/security.md) and .claude/skills/rls-policy/SKILL.md.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select is_empty($$
  select id from public.attendance where id = 'b0000000-0000-4000-8000-000000000005'
$$, 'RLS select — Gym A cannot read Gym B''s attendance');

select is_empty($$
  select id from public.qr_sessions where id = 'b0000000-0000-4000-8000-000000000006'
$$, 'RLS select — Gym A cannot read Gym B''s qr_sessions');

select is_empty($$
  select id from public.attendance_corrections where id = 'b0000000-0000-4000-8000-000000000007'
$$, 'RLS select — Gym A cannot read Gym B''s attendance_corrections');

select is_empty($$
  select id from public.organization_holidays where id = 'b0000000-0000-4000-8000-000000000008'
$$, 'RLS select — Gym A cannot read Gym B''s organization_holidays');

select is(
  (select count(*) from public.attendance where id = 'a0000000-0000-4000-8000-000000000005'),
  1::bigint, 'RLS select — Gym A reads its own attendance');

select is(
  (select count(*) from public.qr_sessions where id = 'a0000000-0000-4000-8000-000000000006'),
  1::bigint, 'RLS select — Gym A reads its own qr_sessions');

select is(
  (select count(*) from public.attendance_corrections where id = 'a0000000-0000-4000-8000-000000000007'),
  1::bigint, 'RLS select — Gym A reads its own attendance_corrections');

select is(
  (select count(*) from public.organization_holidays where id = 'a0000000-0000-4000-8000-000000000008'),
  1::bigint, 'RLS select — Gym A reads its own organization_holidays');

select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000002',
          'b0000000-0000-4000-8000-000000000004', 'qr')
$$, '42501'::char(5), null,
  'RLS insert — Gym A cannot write an attendance row into Gym B');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000002', 'rls-hash-leak',
          '2026-09-06T10:00:00Z', '2026-09-06T10:15:00Z')
$$, '42501'::char(5), null,
  'RLS insert — Gym A cannot write a qr_sessions row into Gym B');

select throws_ok($$
  insert into public.attendance_corrections
    (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
  values ('b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000005',
          'b0000000-0000-4000-8000-000000000003',
          'leaked', '{}'::jsonb, '{}'::jsonb)
$$, '42501'::char(5), null,
  'RLS insert — Gym A cannot write an attendance_corrections row into Gym B');

select throws_ok($$
  insert into public.organization_holidays (tenant_id, holiday_on, name)
  values ('b0000000-0000-4000-8000-000000000001', date '2026-08-15', 'leaked')
$$, '42501'::char(5), null,
  'RLS insert — Gym A cannot write an organization_holidays row into Gym B');

-- An update filtered by RLS does not raise; it matches no rows. The rows are
-- re-read as postgres below to prove nothing moved.
select lives_ok($$
  update public.attendance set checked_out_at = now()
  where id = 'b0000000-0000-4000-8000-000000000005'
$$, 'RLS update — Gym A''s update of a Gym B attendance row matches nothing rather than raising');

select lives_ok($$
  update public.qr_sessions set revoked_at = now()
  where id = 'b0000000-0000-4000-8000-000000000006'
$$, 'RLS update — Gym A''s update of a Gym B qr_sessions row matches nothing rather than raising');

select lives_ok($$
  update public.organization_holidays set name = 'leaked'
  where id = 'b0000000-0000-4000-8000-000000000008'
$$, 'RLS update — Gym A''s update of a Gym B organization_holidays row matches nothing rather than raising');

select throws_ok($$
  update public.attendance_corrections set reason = 'leaked'
  where id = 'b0000000-0000-4000-8000-000000000007'
$$, '42501'::char(5), null,
  'INT-001 — update on attendance_corrections is refused for want of privilege, cross-tenant or not');

select throws_ok($$
  delete from public.attendance where id = 'b0000000-0000-4000-8000-000000000005'
$$, '42501'::char(5), null,
  'ADR-037 — no DELETE on attendance for authenticated, cross-tenant or not');

select throws_ok($$
  delete from public.qr_sessions where id = 'b0000000-0000-4000-8000-000000000006'
$$, '42501'::char(5), null,
  'ADR-037 — no DELETE on qr_sessions for authenticated, cross-tenant or not');

select throws_ok($$
  delete from public.attendance_corrections where id = 'b0000000-0000-4000-8000-000000000007'
$$, '42501'::char(5), null,
  'ADR-037 — no DELETE on attendance_corrections for authenticated, cross-tenant or not');

select throws_ok($$
  delete from public.organization_holidays where id = 'b0000000-0000-4000-8000-000000000008'
$$, '42501'::char(5), null,
  'ADR-037 — no DELETE on organization_holidays for authenticated, cross-tenant or not');

set local role postgres;

select is(
  (select checked_out_at from public.attendance where id = 'b0000000-0000-4000-8000-000000000005'),
  null::timestamptz, 'RLS update — Gym B''s attendance row is untouched');

select is(
  (select revoked_at from public.qr_sessions where id = 'b0000000-0000-4000-8000-000000000006'),
  null::timestamptz, 'RLS update — Gym B''s qr_sessions row is untouched');

select is(
  (select name from public.organization_holidays where id = 'b0000000-0000-4000-8000-000000000008'),
  'Republic Day B'::text, 'RLS update — Gym B''s organization_holidays row is untouched');

select is(
  (select reason from public.attendance_corrections where id = 'b0000000-0000-4000-8000-000000000007'),
  'gym B reason'::text, 'RLS update — Gym B''s attendance_corrections row is untouched');

-- ---------------------------------------------------------------------------
-- The platform branch: `super_admin` crosses tenants by policy, not by
-- disabling RLS (docs/security.md; ADR-033). No tenant_id claim at all.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true);
set local role authenticated;

select is(
  (select count(*) from public.attendance
    where id in ('a0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000005')),
  2::bigint, 'RLS select — super_admin sees both gyms'' attendance');

select is(
  (select count(*) from public.qr_sessions
    where id in ('a0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000006')),
  2::bigint, 'RLS select — super_admin sees both gyms'' qr_sessions');

select is(
  (select count(*) from public.attendance_corrections
    where id in ('a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000007')),
  2::bigint, 'RLS select — super_admin sees both gyms'' attendance_corrections');

select is(
  (select count(*) from public.organization_holidays
    where id in ('a0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-000000000008')),
  2::bigint, 'RLS select — super_admin sees both gyms'' organization_holidays');

-- ---------------------------------------------------------------------------
-- The no-claim caller: zero rows and no insert, without raising on the
-- accessor itself (ADR-032).
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role authenticated;

select ok(app.current_tenant_id() is null,
  'ADR-032 — an empty claims string yields a null tenant id rather than raising');

select is_empty($$
  select id from public.attendance
   where id in ('a0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000005')
$$, 'RLS select — a caller with no claim sees no attendance');

select is_empty($$
  select id from public.qr_sessions
   where id in ('a0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000006')
$$, 'RLS select — a caller with no claim sees no qr_sessions');

select is_empty($$
  select id from public.attendance_corrections
   where id in ('a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000007')
$$, 'RLS select — a caller with no claim sees no attendance_corrections');

select is_empty($$
  select id from public.organization_holidays
   where id in ('a0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-000000000008')
$$, 'RLS select — a caller with no claim sees no organization_holidays');

select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002',
          'a0000000-0000-4000-8000-000000000004', 'qr')
$$, '42501'::char(5), null,
  'RLS insert — a caller with no claim cannot write attendance');

select throws_ok($$
  insert into public.qr_sessions (tenant_id, branch_id, token_hash, issued_at, expires_at)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000002', 'rls-hash-noclaim',
          '2026-09-06T10:00:00Z', '2026-09-06T10:15:00Z')
$$, '42501'::char(5), null,
  'RLS insert — a caller with no claim cannot write qr_sessions');

select throws_ok($$
  insert into public.attendance_corrections
    (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
  values ('a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000005',
          'a0000000-0000-4000-8000-000000000003',
          'no claim', '{}'::jsonb, '{}'::jsonb)
$$, '42501'::char(5), null,
  'RLS insert — a caller with no claim cannot write attendance_corrections');

select throws_ok($$
  insert into public.organization_holidays (tenant_id, holiday_on, name)
  values ('a0000000-0000-4000-8000-000000000001', date '2026-08-15', 'no claim')
$$, '42501'::char(5), null,
  'RLS insert — a caller with no claim cannot write organization_holidays');

-- Claims present, tenant_id key absent — the hook-less token of ADR-032.
set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select ok(app.current_tenant_id() is null,
  'ADR-032 — a claims object with no tenant_id key yields a null tenant id rather than raising');

select is_empty($$
  select id from public.attendance
   where id in ('a0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000005')
$$, 'RLS select — a hook-less token sees no attendance');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
