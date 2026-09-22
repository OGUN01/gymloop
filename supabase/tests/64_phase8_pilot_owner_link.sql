-- PILOT-007: the controlled second-owner fixture is a database-command
-- rehearsal only. It never creates a browser session and always rolls back.
begin;

select plan(23);

set local role postgres;
set local search_path = extensions, public;

insert into auth.users(id, email) values
  ('64000000-0000-4000-8000-000000000901', 'pilot64-platform@gymloop.test'),
  ('64000000-0000-4000-8000-000000000902', 'pilot64-owner@gymloop.test');

insert into public.platform_users(user_id, role, full_name, email, is_active) values
  ('64000000-0000-4000-8000-000000000901', 'super_admin', 'Pilot 64 Platform',
   'pilot64-platform@gymloop.test', true);

select set_config('request.jwt.claims',
  '{"sub":"64000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',
  true);
set local role authenticated;

create temporary table pilot64_result(
  name text primary key,
  result jsonb not null
) on commit drop;

insert into pilot64_result(name, result) values
  ('qa', public.onboard_gym(
    '64000000-0000-4000-8000-000000000001', 'Pilot 64 QA Gym', 'Asia/Kolkata', 'INR',
    'premium_studio'::public.gym_preset, 'Pilot 64 QA Main', 'Pilot 64 QA Owner',
    'pilot64-owner@gymloop.test')),
  ('foreign', public.onboard_gym(
    '64000000-0000-4000-8000-000000000002', 'Pilot 64 Foreign Gym', 'Asia/Kolkata', 'INR',
    'premium_studio'::public.gym_preset, 'Pilot 64 Foreign Main', 'Pilot 64 Foreign Owner',
    'pilot64-foreign@gymloop.test'));

select is((select result #>> '{organization,tenantId}' from pilot64_result where name = 'qa'),
  '64000000-0000-4000-8000-000000000001',
  'PILOT-007: QA onboarding derives the requested tenant identity');
select ok((select user_id is null and is_active and role = 'gym_owner'::public.app_role
  from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot64_result where name = 'qa')),
  'PILOT-007: the QA owner profile is active and unlinked before owner link');
set local role postgres;
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '64000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '64000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,app_role}'), null::text,
  'PILOT-007: the separately created Auth user has no Gymloop role before link');
set local role authenticated;

create temporary table pilot64_link as
select public.link_gym_owner(
  (select result #>> '{organization,tenantId}' from pilot64_result where name = 'qa')::uuid,
  (select (result ->> 'ownerStaffId')::uuid from pilot64_result where name = 'qa'),
  null,
  'pilot64-owner@gymloop.test',
  '64000000-0000-4000-8000-000000000010') as result;

select ok((select result ?& array['tenantId', 'ownerStaffId', 'userId', 'ownerAccessPending']
  and result ->> 'ownerAccessPending' = 'false' from pilot64_link),
  'PILOT-007: first owner link returns the exact non-pending result envelope');
select is((select result ->> 'tenantId' from pilot64_link),
  (select result #>> '{organization,tenantId}' from pilot64_result where name = 'qa'),
  'PILOT-007: owner link returns the requested QA tenant id');
select is((select result ->> 'ownerStaffId' from pilot64_link),
  (select result ->> 'ownerStaffId' from pilot64_result where name = 'qa'),
  'PILOT-007: owner link returns the designated unlinked owner staff id');
select is((select result ->> 'userId' from pilot64_link),
  '64000000-0000-4000-8000-000000000902',
  'PILOT-007: owner link binds only the separately created Auth user');
select is((select user_id::text from public.staff
  where id = (select (result ->> 'ownerStaffId')::uuid from pilot64_link)),
  '64000000-0000-4000-8000-000000000902',
  'PILOT-007: the linked staff row stores the target Auth user id');
select is((select count(*) from public.audit_log
  where tenant_id = (select (result ->> 'tenantId')::uuid from pilot64_link)
    and action = 'staff.owner_linked'
    and record_id = (select (result ->> 'ownerStaffId')::uuid from pilot64_link)
    and request_key = '64000000-0000-4000-8000-000000000010'::uuid),
  1::bigint, 'PILOT-007: the first owner link records one keyed owner-link audit event');

select is(public.link_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot64_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot64_link),
  null,
  'pilot64-owner@gymloop.test',
  '64000000-0000-4000-8000-000000000010'),
  (select result from pilot64_link),
  'PILOT-007: exact link replay returns its original result');
select is((select count(*) from public.audit_log
  where request_key = '64000000-0000-4000-8000-000000000010'::uuid),
  1::bigint, 'PILOT-007: exact owner-link replay appends no audit event');
select throws_ok($$select public.link_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot64_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot64_link),
  '64000000-0000-4000-8000-000000000902',
  'different-pilot64-owner@gymloop.test',
  '64000000-0000-4000-8000-000000000010')$$,
  'GL068', null, 'PILOT-007: a changed owner-link replay is refused');

set local role postgres;
create temporary table pilot64_fresh_hook as
select app.custom_access_token_hook(jsonb_build_object(
  'user_id', '64000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '64000000-0000-4000-8000-000000000902', 'role', 'authenticated'))) as result;
select is((select result #>> '{claims,app_role}' from pilot64_fresh_hook), 'gym_owner',
  'PILOT-007: fresh hook claims name the linked gym-owner role');
select is((select result #>> '{claims,tenant_id}' from pilot64_fresh_hook), (select result ->> 'tenantId' from pilot64_link),
  'PILOT-007: fresh hook claims name the linked QA tenant');
select is((select result #>> '{claims,staff_id}' from pilot64_fresh_hook), (select result ->> 'ownerStaffId' from pilot64_link),
  'PILOT-007: fresh hook claims name the linked owner staff id');

select set_config('request.jwt.claims', (select result -> 'claims' from pilot64_fresh_hook)::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint,
  'PILOT-007: hook-issued owner claims see one organization through RLS');
select is((select count(*) from public.organizations
  where id = (select (result #>> '{organization,tenantId}')::uuid from pilot64_result where name = 'foreign')),
  0::bigint, 'PILOT-007: hook-issued owner claims cannot read the foreign gym by id');
with changed as (
  update public.organizations set name = 'PILOT 64 FOREIGN MUST NOT CHANGE'
  where id = (select (result #>> '{organization,tenantId}')::uuid from pilot64_result where name = 'foreign')
  returning id
)
select is((select count(*) from changed), 0::bigint,
  'PILOT-007: hook-issued owner claims cannot mutate the foreign gym');

select set_config('request.jwt.claims',
  '{"sub":"64000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}', true);
select throws_ok($$update public.staff set is_active = false
  where id = (select (result ->> 'ownerStaffId')::uuid from pilot64_link)$$,
  'GL049', null, 'PILOT-007: direct authenticated staff retirement is refused');
select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot64_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot64_link),
  '64000000-0000-4000-8000-000000000902',
  '64000000-0000-4000-8000-000000000011');

set local role postgres;
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '64000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '64000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,app_role}'), null::text,
  'PILOT-007: deactivated test owner receives no fresh Gymloop role claim');
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '64000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '64000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,tenant_id}'), null::text,
  'PILOT-007: deactivated test owner receives no fresh Gymloop tenant claim');
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '64000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '64000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,staff_id}'), null::text,
  'PILOT-007: deactivated test owner receives no fresh Gymloop staff claim');

set local role authenticated;
select is((select name from public.organizations
  where id = (select (result #>> '{organization,tenantId}')::uuid from pilot64_result where name = 'foreign')),
  'Pilot 64 Foreign Gym', 'PILOT-007: the denied foreign mutation leaves its row unchanged');

select * from finish();
rollback;
