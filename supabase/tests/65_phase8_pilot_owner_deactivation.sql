-- PILOT-008: only the named non-preview super-admin command may retire a
-- linked active owner. Every fixture is transaction-local and rolls back.
begin;

select plan(30);

set local role postgres;
set local search_path = extensions, public;

select has_function('public', 'deactivate_gym_owner', array['uuid', 'uuid', 'uuid', 'uuid']::name[],
  'PILOT-008: exact four-UUID owner-deactivation command exists');
select ok(not has_function_privilege('anon', 'public.deactivate_gym_owner(uuid,uuid,uuid,uuid)', 'execute'),
  'PILOT-008: anonymous callers have no owner-deactivation execution grant');
select ok(not has_function_privilege('service_role', 'public.deactivate_gym_owner(uuid,uuid,uuid,uuid)', 'execute'),
  'PILOT-008: service-role callers have no owner-deactivation execution grant');

insert into auth.users(id, email) values
  ('65000000-0000-4000-8000-000000000901', 'pilot65-admin@gymloop.test'),
  ('65000000-0000-4000-8000-000000000902', 'pilot65-owner@gymloop.test'),
  ('65000000-0000-4000-8000-000000000903', 'pilot65-support@gymloop.test');

insert into public.platform_users(user_id, role, full_name, email, is_active) values
  ('65000000-0000-4000-8000-000000000901', 'super_admin', 'Pilot 65 Admin', 'pilot65-admin@gymloop.test', true),
  ('65000000-0000-4000-8000-000000000903', 'platform_support', 'Pilot 65 Support', 'pilot65-support@gymloop.test', true);

select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}', true);
set local role authenticated;

create temporary table pilot65_onboarded(name text primary key, result jsonb not null) on commit drop;
insert into pilot65_onboarded(name, result) values
  ('qa', public.onboard_gym(
    '65000000-0000-4000-8000-000000000001', 'Pilot 65 QA Gym', 'Asia/Kolkata', 'INR',
    'premium_studio'::public.gym_preset, 'Pilot 65 QA Main', 'Pilot 65 Owner', 'pilot65-owner@gymloop.test')),
  ('foreign', public.onboard_gym(
    '65000000-0000-4000-8000-000000000002', 'Pilot 65 Foreign Gym', 'Asia/Kolkata', 'INR',
    'premium_studio'::public.gym_preset, 'Pilot 65 Foreign Main', 'Pilot 65 Foreign Owner', 'pilot65-foreign@gymloop.test'));

create temporary table pilot65_link as
select public.link_gym_owner(
  (select result #>> '{organization,tenantId}' from pilot65_onboarded where name = 'qa')::uuid,
  (select (result ->> 'ownerStaffId')::uuid from pilot65_onboarded where name = 'qa'),
  null, 'pilot65-owner@gymloop.test', '65000000-0000-4000-8000-000000000010') as result;

select is((select result ->> 'userId' from pilot65_link), '65000000-0000-4000-8000-000000000902',
  'PILOT-008: fixture links the exact target Auth user before retirement');
select ok((select is_active and user_id = '65000000-0000-4000-8000-000000000902'::uuid
  from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)),
  'PILOT-008: fixture target is one active linked gym owner');

set local role postgres;
insert into auth.sessions(id, user_id) values
  ('65000000-0000-4000-8000-000000000920', '65000000-0000-4000-8000-000000000902');
set local role authenticated;

select set_config('request.jwt.claims', (select jsonb_build_object(
  'sub', result ->> 'userId', 'role', 'authenticated', 'app_role', 'gym_owner',
  'tenant_id', result ->> 'tenantId', 'staff_id', result ->> 'ownerStaffId')::text from pilot65_link), true);
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000020')$$,
  '42501', null, 'PILOT-008: a linked gym owner cannot retire an owner');

select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"platform_support"}', true);
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000021')$$,
  '42501', null, 'PILOT-008: platform support cannot retire an owner');

select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin","impersonation_session_id":"65000000-0000-4000-8000-000000000930"}', true);
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000022')$$,
  '42501', null, 'PILOT-008: preview super-admin cannot retire an owner');

select set_config('request.jwt.claims',
  '{"sub":"65000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}', true);
select throws_ok($$update public.staff set is_active = false
  where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)$$,
  'GL049', null, 'PILOT-008: direct authenticated staff retirement is refused');
select ok((select is_active from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)),
  'PILOT-008: direct-update refusal leaves the linked owner active');
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000901', '65000000-0000-4000-8000-000000000023')$$,
  null, null, 'PILOT-008: a stale expected user is refused before retirement');
select ok((select is_active from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)),
  'PILOT-008: stale expected-user refusal leaves the owner active');
select is((select count(*) from public.audit_log where request_key = '65000000-0000-4000-8000-000000000023'::uuid), 0::bigint,
  'PILOT-008: stale expected-user refusal writes no audit event');

create temporary table pilot65_deactivation as
select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000030') as result;

select is((select count(*) from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)
  and tenant_id = (select (result ->> 'tenantId')::uuid from pilot65_link) and is_active = false), 1::bigint,
  'PILOT-008: command retires exactly the requested linked owner row');
select is((select user_id::text from public.staff where id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)),
  '65000000-0000-4000-8000-000000000902', 'PILOT-008: command preserves the exact linked user association');
select is((select count(*) from public.staff where tenant_id = (select (result ->> 'tenantId')::uuid from pilot65_link)
  and id <> (select (result ->> 'ownerStaffId')::uuid from pilot65_link) and is_active = false), 0::bigint,
  'PILOT-008: command does not retire another QA staff row');
select is((select count(*) from public.staff where tenant_id = (select result #>> '{organization,tenantId}' from pilot65_onboarded where name = 'foreign')::uuid
  and is_active = false), 0::bigint, 'PILOT-008: command does not retire foreign-gym staff');
select is((select count(*) from auth.sessions where user_id = '65000000-0000-4000-8000-000000000902'), 0::bigint,
  'PILOT-008: owner retirement revokes every target Auth session');
select is((select count(*) from public.audit_log where tenant_id = (select (result ->> 'tenantId')::uuid from pilot65_link)
  and action = 'staff.owner_deactivated' and record_id = (select (result ->> 'ownerStaffId')::uuid from pilot65_link)
  and request_key = '65000000-0000-4000-8000-000000000030'::uuid
  and before ->> 'is_active' = 'true' and after ->> 'is_active' = 'false'), 1::bigint,
  'PILOT-008: owner retirement appends one keyed before/after audit event');

select is(public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000030'),
  (select result from pilot65_deactivation), 'PILOT-008: exact retirement replay returns its original result');
select is((select count(*) from public.audit_log where request_key = '65000000-0000-4000-8000-000000000030'::uuid), 1::bigint,
  'PILOT-008: exact retirement replay adds no audit event');
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000901', '65000000-0000-4000-8000-000000000030')$$,
  'GL068', null, 'PILOT-008: changed expected user under a used key is an idempotency conflict');
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000031')$$,
  null, null, 'PILOT-008: inactive first-use is stale state');

select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  (select (result ->> 'ownerStaffId')::uuid from pilot65_onboarded where name = 'foreign'),
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000040')$$,
  null, null, 'PILOT-008: foreign owner staff is not found under the QA tenant');
select is((select count(*) from public.audit_log where request_key = '65000000-0000-4000-8000-000000000040'::uuid), 0::bigint,
  'PILOT-008: foreign-owner refusal writes no audit event');
select throws_ok($$select public.deactivate_gym_owner(
  (select (result ->> 'tenantId')::uuid from pilot65_link),
  '65000000-0000-4000-8000-000000000999',
  '65000000-0000-4000-8000-000000000902', '65000000-0000-4000-8000-000000000041')$$,
  null, null, 'PILOT-008: unknown owner staff is not found');
select is((select count(*) from public.audit_log where request_key = '65000000-0000-4000-8000-000000000041'::uuid), 0::bigint,
  'PILOT-008: unknown-owner refusal writes no audit event');

set local role postgres;
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '65000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '65000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,app_role}'), null::text, 'PILOT-008: retired owner receives no fresh role claim');
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '65000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '65000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,tenant_id}'), null::text, 'PILOT-008: retired owner receives no fresh tenant claim');
select is((app.custom_access_token_hook(jsonb_build_object(
  'user_id', '65000000-0000-4000-8000-000000000902',
  'claims', jsonb_build_object('sub', '65000000-0000-4000-8000-000000000902', 'role', 'authenticated')))
  #>> '{claims,staff_id}'), null::text, 'PILOT-008: retired owner receives no fresh staff claim');

select * from finish();
rollback;
