-- 08_retention_rls — retention cluster, cross-tenant leak matrix for
-- no_show_cases and follow_ups (gate 7).
-- Written from openspec/changes/0001-data-model/specs/retention/spec.md and
-- docs/data-model.md "### Row-Level Security" / "### Privileges" /
-- "### How a pgTAP test assumes a role", before any DDL existed.
-- Requirement ids: NSH-003, NSH-005, NSH-007, INT-001.
--
-- The asymmetry this file is built around: an RLS policy does not raise on
-- select/update/delete, it filters — so the assertion is zero rows / row
-- unchanged. A failing `with check` on insert does raise 42501, and so does a
-- statement refused for want of privilege.
-- ADR-030: wrapped BEGIN … ROLLBACK.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(29);

-- ---------------------------------------------------------------------------
-- Fixtures for two gyms, inserted as the owner: RLS does not apply to the table
-- owner because the contract forbids `force row level security`.
-- Gym codes RTNR0A / RTNR0B are unique to this file.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'Retention Gym A', 'RTNR0A'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'Retention Gym B', 'RTNR0B');

insert into public.branches (id, tenant_id, name) values
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'A Main'),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'B Main');

insert into public.staff (id, tenant_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'front_desk', 'A Front Desk'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'front_desk', 'B Front Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000010'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'A Member One', '+919100000010'),
  ('a0000000-0000-4000-8000-000000000011'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 'A Member Two', '+919100000011'),
  ('b0000000-0000-4000-8000-000000000010'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'b0000000-0000-4000-8000-000000000002'::uuid, 'B Member One', '+919200000010'),
  ('b0000000-0000-4000-8000-000000000011'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'b0000000-0000-4000-8000-000000000002'::uuid, 'B Member Two', '+919200000011');

-- Gym A's case is `closed`, so the spec's "Deleting a resolved case" scenario has
-- a resolved case to aim at. Gym B's is `open`, so a leaked update would show.
insert into public.no_show_cases (id, tenant_id, member_id, status, absent_days_at_open, threshold_days) values
  ('a0000000-0000-4000-8000-000000000020'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000010'::uuid, 'closed', 10, 7),
  ('b0000000-0000-4000-8000-000000000020'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'b0000000-0000-4000-8000-000000000010'::uuid, 'open',   10, 7);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes) values
  ('a0000000-0000-4000-8000-000000000030'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000020'::uuid, 'a0000000-0000-4000-8000-000000000003'::uuid, 'call',     'will_return', 'A: called'),
  ('b0000000-0000-4000-8000-000000000030'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'b0000000-0000-4000-8000-000000000020'::uuid, 'b0000000-0000-4000-8000-000000000003'::uuid, 'whatsapp', 'no_response', 'B: messaged');

-- ---------------------------------------------------------------------------
-- 1-14  Act as a signed-in owner of Gym A.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select results_eq(
  'select id from public.no_show_cases order by id',
  array['a0000000-0000-4000-8000-000000000020'::uuid],
  'NSH-003: gym A selects only its own no_show_cases');

select results_eq(
  'select id from public.follow_ups order by id',
  array['a0000000-0000-4000-8000-000000000030'::uuid],
  'NSH-007: gym A selects only its own follow_ups');

-- An RLS policy filters an update, it does not raise: the statement succeeds
-- and touches nothing.
with attempted as (
  update public.no_show_cases
     set status = 'returned'
   where id = 'b0000000-0000-4000-8000-000000000020'::uuid
  returning 1
)
select is(
  (select count(*) from attempted),
  0::bigint,
  'NSH-003: gym A updating gym B''s case by primary key affects zero rows');

-- follow_ups is append-only, so an update is refused for want of privilege
-- before RLS is ever consulted — cross-tenant and own-tenant alike.
select throws_ok(
  $q$update public.follow_ups set outcome = 'unhappy'
      where id = 'b0000000-0000-4000-8000-000000000030'::uuid$q$,
  '42501', null,
  'NSH-007: gym A updating gym B''s follow-up is refused for want of privilege');

select throws_ok(
  $q$update public.follow_ups set outcome = 'unhappy'
      where id = 'a0000000-0000-4000-8000-000000000030'::uuid$q$,
  '42501', null,
  'NSH-007: updating a follow-up in the caller''s own tenant is refused for want of privilege');

select throws_ok(
  $q$delete from public.no_show_cases
      where id = 'a0000000-0000-4000-8000-000000000020'::uuid$q$,
  '42501', null,
  'NSH-005/INT-001: deleting a closed case in the caller''s own tenant is refused for want of privilege');

select throws_ok(
  $q$delete from public.follow_ups
      where id = 'a0000000-0000-4000-8000-000000000030'::uuid$q$,
  '42501', null,
  'NSH-007/INT-001: deleting a follow-up in the caller''s own tenant is refused for want of privilege');

select throws_ok(
  $q$delete from public.no_show_cases
      where id = 'b0000000-0000-4000-8000-000000000020'::uuid$q$,
  '42501', null,
  'INT-001: gym A cannot delete gym B''s case — no DELETE is granted at all');

select throws_ok(
  $q$delete from public.follow_ups
      where id = 'b0000000-0000-4000-8000-000000000030'::uuid$q$,
  '42501', null,
  'INT-001: gym A cannot delete gym B''s follow-up — no DELETE is granted at all');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
     values ('b0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000011'::uuid, 10, 7)$q$,
  '42501', null,
  'NSH-003: gym A inserting a case carrying gym B''s tenant_id violates the with check');

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
     values ('b0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000020'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'no_response')$q$,
  '42501', null,
  'NSH-007: gym A inserting a follow-up carrying gym B''s tenant_id violates the with check');

-- Positive controls: the policies must permit the caller's own tenant, or every
-- negative assertion above would pass against a table that denies everything.
select lives_ok(
  $q$insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
     values ('a0000000-0000-4000-8000-000000000021'::uuid,
             'a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000010'::uuid, 10, 7)$q$,
  'NSH-003: gym A may open a case in its own tenant');

select lives_ok(
  $q$insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
     values ('a0000000-0000-4000-8000-000000000031'::uuid,
             'a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000020'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid, 'in_person', 'timing_issue')$q$,
  'NSH-007: gym A may append to the contact log in its own tenant');

-- Honest behaviour, not the behaviour one might hope for: a foreign key does not
-- enforce tenancy, and the policy's `with check` inspects tenant_id only. A case
-- carrying gym A's tenant_id but pointing at gym B's member is ACCEPTED by the
-- schema. The application layer closes this; the schema does not. (Finding.)
select lives_ok(
  $q$insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days)
     values ('a0000000-0000-4000-8000-000000000022'::uuid,
             'a0000000-0000-4000-8000-000000000001'::uuid,
             'b0000000-0000-4000-8000-000000000011'::uuid, 10, 7)$q$,
  'NSH-003: a case whose member_id belongs to another gym is accepted — FKs do not enforce tenancy');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 15-16  Act as the platform: rows from both gyms are visible.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select results_eq(
  'select distinct tenant_id from public.no_show_cases order by 1',
  array['a0000000-0000-4000-8000-000000000001'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid],
  'NSH-003: super_admin sees no_show_cases from both gyms');

select results_eq(
  'select distinct tenant_id from public.follow_ups order by 1',
  array['a0000000-0000-4000-8000-000000000001'::uuid,
        'b0000000-0000-4000-8000-000000000001'::uuid],
  'NSH-007: super_admin sees follow_ups from both gyms');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 17-21  No JWT claims at all. app.current_tenant_id() is null, so the tenant
--        predicate is null rather than true and both policies OR to false:
--        zero rows, silently. A policy that raised would let a caller tell
--        "nothing here" apart from "wrong tenant".
-- ---------------------------------------------------------------------------

set local role authenticated;

select lives_ok(
  'select id from public.no_show_cases',
  'NSH-003: a claimless caller selecting no_show_cases does not raise');

select is(
  (select count(*) from public.no_show_cases),
  0::bigint,
  'NSH-003: a claimless caller sees zero no_show_cases');

select is(
  (select count(*) from public.follow_ups),
  0::bigint,
  'NSH-007: a claimless caller sees zero follow_ups');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000011'::uuid, 10, 7)$q$,
  '42501', null,
  'NSH-003: a claimless caller cannot insert a no-show case');

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000020'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'no_response')$q$,
  '42501', null,
  'NSH-007: a claimless caller cannot append to the contact log');

set local role postgres;

-- ---------------------------------------------------------------------------
-- 22-26  An empty-string tenant_id claim. The inner nullif in
--        app.current_tenant_id() turns it into null before the uuid cast, so it
--        behaves exactly like no claims — it must not become a uuid cast error
--        and must not match a row.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select lives_ok(
  'select id from public.no_show_cases',
  'NSH-003: an empty-string tenant_id claim does not raise on select');

select is(
  (select count(*) from public.no_show_cases),
  0::bigint,
  'NSH-003: an empty-string tenant_id claim sees zero no_show_cases');

select is(
  (select count(*) from public.follow_ups),
  0::bigint,
  'NSH-007: an empty-string tenant_id claim sees zero follow_ups');

select throws_ok(
  $q$insert into public.no_show_cases (tenant_id, member_id, absent_days_at_open, threshold_days)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000011'::uuid, 10, 7)$q$,
  '42501', null,
  'NSH-003: an empty-string tenant_id claim cannot insert a no-show case');

select throws_ok(
  $q$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000020'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid, 'call', 'no_response')$q$,
  '42501', null,
  'NSH-007: an empty-string tenant_id claim cannot append to the contact log');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 27-29  Back as the owner, which sees everything: gym B's rows survived every
--        attempt above untouched. Filtering only counts if the row is still there.
-- ---------------------------------------------------------------------------

select is(
  (select status::text from public.no_show_cases
    where id = 'b0000000-0000-4000-8000-000000000020'::uuid),
  'open',
  'NSH-003: gym B''s case is still open — gym A''s update reached nothing');

select is(
  (select count(*) from public.no_show_cases
    where id = 'b0000000-0000-4000-8000-000000000020'::uuid),
  1::bigint,
  'INT-001: gym B''s case is still present after gym A''s delete attempt');

select is(
  (select count(*) from public.follow_ups
    where id = 'b0000000-0000-4000-8000-000000000030'::uuid),
  1::bigint,
  'INT-001: gym B''s follow-up is still present after gym A''s delete attempt');

select * from finish();

rollback;
