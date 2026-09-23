-- HARD-004 assisted front-desk response-time repair. Written from the frozen
-- OpenSpec contract before the RPC migration and route implementation.
-- All fixture writes, successful visits and failed probes roll back.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(17);

insert into public.organizations(id, name, gym_code) values
  ('37000000-0000-4000-8000-000000000001', 'RPC Gym A', 'RPC37A'),
  ('37000000-0000-4000-8000-000000000002', 'RPC Gym B', 'RPC37B');
insert into public.organization_settings(tenant_id, checkin_dedupe_seconds) values
  ('37000000-0000-4000-8000-000000000001', 3600),
  ('37000000-0000-4000-8000-000000000002', 3600);
insert into public.branches(id, tenant_id, name, is_default) values
  ('37000000-0000-4000-8000-000000000011', '37000000-0000-4000-8000-000000000001', 'A Desk', true),
  ('37000000-0000-4000-8000-000000000012', '37000000-0000-4000-8000-000000000002', 'B Desk', true);
insert into public.staff(id, tenant_id, branch_id, role, full_name) values
  ('37000000-0000-4000-8000-000000000021', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000011', 'front_desk', 'A Front Desk'),
  ('37000000-0000-4000-8000-000000000022', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000011', 'trainer', 'A Trainer'),
  ('37000000-0000-4000-8000-000000000023', '37000000-0000-4000-8000-000000000002', '37000000-0000-4000-8000-000000000012', 'front_desk', 'B Front Desk');
insert into public.members(id, tenant_id, branch_id, full_name, phone) values
  ('37000000-0000-4000-8000-000000000031', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000011', 'Asha Rao', '+913700000031'),
  ('37000000-0000-4000-8000-000000000032', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000011', 'A New', '+913700000032'),
  ('37000000-0000-4000-8000-000000000034', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000011', 'A Trainer Probe', '+913700000034'),
  ('37000000-0000-4000-8000-000000000033', '37000000-0000-4000-8000-000000000002', '37000000-0000-4000-8000-000000000012', 'B Foreign', '+913700000033');
insert into public.plans(id, tenant_id, name, duration_days, price_paise) values
  ('37000000-0000-4000-8000-000000000041', '37000000-0000-4000-8000-000000000001', 'A Month', 30, 200000),
  ('37000000-0000-4000-8000-000000000042', '37000000-0000-4000-8000-000000000002', 'B Month', 30, 200000);
insert into public.memberships(id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('37000000-0000-4000-8000-000000000051', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000031', '37000000-0000-4000-8000-000000000041', 'active', (now() at time zone 'Asia/Kolkata')::date - 1, (now() at time zone 'Asia/Kolkata')::date + 30, 200000),
  ('37000000-0000-4000-8000-000000000052', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000032', '37000000-0000-4000-8000-000000000041', 'active', (now() at time zone 'Asia/Kolkata')::date - 1, (now() at time zone 'Asia/Kolkata')::date + 30, 200000),
  ('37000000-0000-4000-8000-000000000054', '37000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000034', '37000000-0000-4000-8000-000000000041', 'active', (now() at time zone 'Asia/Kolkata')::date - 1, (now() at time zone 'Asia/Kolkata')::date + 30, 200000),
  ('37000000-0000-4000-8000-000000000053', '37000000-0000-4000-8000-000000000002', '37000000-0000-4000-8000-000000000033', '37000000-0000-4000-8000-000000000042', 'active', (now() at time zone 'Asia/Kolkata')::date - 1, (now() at time zone 'Asia/Kolkata')::date + 30, 200000);

-- Exact signature, no tenant/branch/actor input, invoker authority and grant.
select ok(to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)') is not null,
  'the RPC exposes exactly member, reason and optional event ID arguments');
select results_eq(
  $$select p.pronargs, p.provolatile::text, p.prosecdef, p.proretset
      from pg_proc p where p.oid = to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)')$$,
  $$values (3::smallint, 'v'::text, false, true)$$,
  'the command is a volatile SECURITY INVOKER set-returning function');
select results_eq(
  $$select ro, has_function_privilege(ro, 'public.record_staff_front_desk_check_in(uuid,text,uuid)', 'execute')
      from (values ('anon'), ('authenticated'), ('service_role')) v(ro) order by ro$$,
  $$values ('anon'::text, false), ('authenticated'::text, true), ('service_role'::text, false)$$,
  'only authenticated has the RPC execute grant');

create temp table rpc_result(label text, id uuid, checked_in_at timestamptz, source text, member_name text);
grant select, insert on rpc_result to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"37000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"37000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"37000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

insert into rpc_result
select 'first', r.id, r.checked_in_at, r.source::text, r.member_name
from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000031', 'Phone left at home', '37000000-0000-4000-8000-000000000701') r;
select results_eq(
  $$select source, member_name, id is not null, checked_in_at is not null from rpc_result where label = 'first'$$,
  $$values ('front_desk'::text, 'Asha Rao'::text, true, true)$$,
  'one successful command returns the current front-desk response facts');
select results_eq(
  $$select a.id = r.id, a.checked_in_at = r.checked_in_at, a.tenant_id, a.branch_id,
           a.member_id, a.assisted_by_staff_id, a.assist_reason, a.source::text
      from public.attendance a join rpc_result r on r.id = a.id where r.label = 'first'$$,
  $$values (true, true, '37000000-0000-4000-8000-000000000001'::uuid,
            '37000000-0000-4000-8000-000000000011'::uuid,
            '37000000-0000-4000-8000-000000000031'::uuid,
            '37000000-0000-4000-8000-000000000021'::uuid,
            'Phone left at home'::text, 'front_desk'::text)$$,
  'the command writes the visible member and database-enforced tenant, branch and actor');
select is((select count(*)::int from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000033', 'Cross-gym attempt', null)), 0,
  'a foreign member is invisible under caller RLS and returns no row');
select is((select count(*)::int from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000099', 'Unknown member', null)), 0,
  'an unknown member returns the same zero-row shape');
select is((select count(*)::int from public.attendance where tenant_id = '37000000-0000-4000-8000-000000000002'), 0,
  'foreign and unknown member probes write no gym-B attendance');
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000032', '   ', null)$$,
  null::char(5), null, 'a whitespace-only assisted reason is refused');
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000032', null, null)$$,
  null::char(5), null, 'a missing assisted reason is refused');
select is((select count(*)::int from public.attendance where member_id = '37000000-0000-4000-8000-000000000032'), 0,
  'invalid reasons leave the member without attendance');
insert into rpc_result
select 'second', r.id, r.checked_in_at, r.source::text, r.member_name
from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000032', 'Assisted at desk', null) r;
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000032', 'Again inside window', null)$$,
  'GL014', null, 'the existing duplicate window still refuses a second visit');
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000031', 'Same event retry',
  '37000000-0000-4000-8000-000000000701')$$,
  '23505', null, 'the reused client event ID reaches the unique replay boundary');
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000032', 'Event used by another member',
  '37000000-0000-4000-8000-000000000701')$$,
  '23505', null, 'one event ID cannot be reused for a different member');
select results_eq(
  $$select member_id, client_event_id, assisted_by_staff_id from public.attendance
      where tenant_id = '37000000-0000-4000-8000-000000000001' order by member_id$$,
  $$values ('37000000-0000-4000-8000-000000000031'::uuid,
            '37000000-0000-4000-8000-000000000701'::uuid,
            '37000000-0000-4000-8000-000000000021'::uuid),
           ('37000000-0000-4000-8000-000000000032'::uuid,
            null::uuid, '37000000-0000-4000-8000-000000000021'::uuid)$$,
  'all refusals preserve exactly the two legitimate, actor-attributed visits');

set local role postgres;
select set_config('request.jwt.claims',
  '{"sub":"37000000-0000-4000-8000-000000000902","role":"authenticated","tenant_id":"37000000-0000-4000-8000-000000000001","app_role":"trainer","staff_id":"37000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;
select throws_ok($$select * from public.record_staff_front_desk_check_in(
  '37000000-0000-4000-8000-000000000034', 'Trainer cannot mark attendance', null)$$,
  '42501', null, 'an unsupported trainer role cannot write through the RPC');
set local role postgres;
select set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.attendance where tenant_id = '37000000-0000-4000-8000-000000000001'), 2,
  'trainer refusal adds no attendance');

select * from finish();
rollback;
