-- PILOT-001: five synthetic gyms, one shared database, one rollback-only rehearsal.
-- The fixtures are deliberately deterministic so the postflight can identify
-- them by id without retaining any state from this transaction.
begin;

select plan(40);

set local role postgres;

insert into public.organizations (id, name, gym_code)
select format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('Pilot Gym %s', n),
       format('P%s', lpad(n::text, 5, '0'))
from generate_series(1, 5) as s(n);

insert into public.branches (id, tenant_id, name, is_default)
select format('10000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('Pilot Gym %s Main Branch', n),
       true
from generate_series(1, 5) as s(n);

insert into public.staff (id, tenant_id, branch_id, role, full_name)
select format('20000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('10000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       'gym_owner'::public.app_role,
       format('Pilot Owner %s', n)
from generate_series(1, 5) as s(n);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select md5(format('pilot-member-%s-%s', gym_no, member_no))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(gym_no::text, 12, '0'))::uuid,
       format('10000000-0000-4000-8000-%s', lpad(gym_no::text, 12, '0'))::uuid,
       format('Pilot Member %s-%s', gym_no, member_no),
       format('+919900%s', lpad(((gym_no * 100) + member_no)::text, 6, '0'))
from generate_series(1, 5) as gyms(gym_no)
cross join generate_series(1, 50) as members(member_no);

set local role authenticated;

-- Each owner sees exactly its own organization and fifty members. The
-- tenant-id and known foreign UUID assertions cover both row and id leaks.
set local request.jwt.claims = '{"tenant_id":"00000000-0000-4000-8000-000000000001","app_role":"gym_owner"}';
select is((select count(*) from public.members), 50::bigint, 'gym 1 owner sees exactly 50 members');
select is((select count(*) from public.organizations), 1::bigint, 'gym 1 owner sees exactly one organization');
select is((select count(*) from public.members where tenant_id <> '00000000-0000-4000-8000-000000000001'::uuid), 0::bigint, 'gym 1 owner sees no foreign member rows');
select is((select count(*) from public.members where id = md5('pilot-member-2-1')::uuid), 0::bigint, 'gym 1 owner sees no foreign member id');
select is((select count(*) from public.organizations where id = '00000000-0000-4000-8000-000000000002'::uuid), 0::bigint, 'gym 1 owner sees no foreign organization id');
with changed as (update public.members set full_name = 'MUST NOT CHANGE' where id = md5('pilot-member-2-1')::uuid returning id)
select is((select count(*) from changed), 0::bigint, 'gym 1 cross-tenant update affects zero rows');
select throws_ok($$delete from public.members where id = md5('pilot-member-2-1')::uuid$$, '42501', null, 'gym 1 cross-tenant delete is refused');
set local role postgres;
select is((select full_name from public.members where id = md5('pilot-member-2-1')::uuid), 'Pilot Member 2-1', 'gym 1 foreign row is unchanged');
set local role authenticated;

set local request.jwt.claims = '{"tenant_id":"00000000-0000-4000-8000-000000000002","app_role":"gym_owner"}';
select is((select count(*) from public.members), 50::bigint, 'gym 2 owner sees exactly 50 members');
select is((select count(*) from public.organizations), 1::bigint, 'gym 2 owner sees exactly one organization');
select is((select count(*) from public.members where tenant_id <> '00000000-0000-4000-8000-000000000002'::uuid), 0::bigint, 'gym 2 owner sees no foreign member rows');
select is((select count(*) from public.members where id = md5('pilot-member-3-1')::uuid), 0::bigint, 'gym 2 owner sees no foreign member id');
select is((select count(*) from public.organizations where id = '00000000-0000-4000-8000-000000000003'::uuid), 0::bigint, 'gym 2 owner sees no foreign organization id');
with changed as (update public.members set full_name = 'MUST NOT CHANGE' where id = md5('pilot-member-3-1')::uuid returning id)
select is((select count(*) from changed), 0::bigint, 'gym 2 cross-tenant update affects zero rows');
select throws_ok($$delete from public.members where id = md5('pilot-member-3-1')::uuid$$, '42501', null, 'gym 2 cross-tenant delete is refused');
set local role postgres;
select is((select full_name from public.members where id = md5('pilot-member-3-1')::uuid), 'Pilot Member 3-1', 'gym 2 foreign row is unchanged');
set local role authenticated;

set local request.jwt.claims = '{"tenant_id":"00000000-0000-4000-8000-000000000003","app_role":"gym_owner"}';
select is((select count(*) from public.members), 50::bigint, 'gym 3 owner sees exactly 50 members');
select is((select count(*) from public.organizations), 1::bigint, 'gym 3 owner sees exactly one organization');
select is((select count(*) from public.members where tenant_id <> '00000000-0000-4000-8000-000000000003'::uuid), 0::bigint, 'gym 3 owner sees no foreign member rows');
select is((select count(*) from public.members where id = md5('pilot-member-4-1')::uuid), 0::bigint, 'gym 3 owner sees no foreign member id');
select is((select count(*) from public.organizations where id = '00000000-0000-4000-8000-000000000004'::uuid), 0::bigint, 'gym 3 owner sees no foreign organization id');
with changed as (update public.members set full_name = 'MUST NOT CHANGE' where id = md5('pilot-member-4-1')::uuid returning id)
select is((select count(*) from changed), 0::bigint, 'gym 3 cross-tenant update affects zero rows');
select throws_ok($$delete from public.members where id = md5('pilot-member-4-1')::uuid$$, '42501', null, 'gym 3 cross-tenant delete is refused');
set local role postgres;
select is((select full_name from public.members where id = md5('pilot-member-4-1')::uuid), 'Pilot Member 4-1', 'gym 3 foreign row is unchanged');
set local role authenticated;

set local request.jwt.claims = '{"tenant_id":"00000000-0000-4000-8000-000000000004","app_role":"gym_owner"}';
select is((select count(*) from public.members), 50::bigint, 'gym 4 owner sees exactly 50 members');
select is((select count(*) from public.organizations), 1::bigint, 'gym 4 owner sees exactly one organization');
select is((select count(*) from public.members where tenant_id <> '00000000-0000-4000-8000-000000000004'::uuid), 0::bigint, 'gym 4 owner sees no foreign member rows');
select is((select count(*) from public.members where id = md5('pilot-member-5-1')::uuid), 0::bigint, 'gym 4 owner sees no foreign member id');
select is((select count(*) from public.organizations where id = '00000000-0000-4000-8000-000000000005'::uuid), 0::bigint, 'gym 4 owner sees no foreign organization id');
with changed as (update public.members set full_name = 'MUST NOT CHANGE' where id = md5('pilot-member-5-1')::uuid returning id)
select is((select count(*) from changed), 0::bigint, 'gym 4 cross-tenant update affects zero rows');
select throws_ok($$delete from public.members where id = md5('pilot-member-5-1')::uuid$$, '42501', null, 'gym 4 cross-tenant delete is refused');
set local role postgres;
select is((select full_name from public.members where id = md5('pilot-member-5-1')::uuid), 'Pilot Member 5-1', 'gym 4 foreign row is unchanged');
set local role authenticated;

set local request.jwt.claims = '{"tenant_id":"00000000-0000-4000-8000-000000000005","app_role":"gym_owner"}';
select is((select count(*) from public.members), 50::bigint, 'gym 5 owner sees exactly 50 members');
select is((select count(*) from public.organizations), 1::bigint, 'gym 5 owner sees exactly one organization');
select is((select count(*) from public.members where tenant_id <> '00000000-0000-4000-8000-000000000005'::uuid), 0::bigint, 'gym 5 owner sees no foreign member rows');
select is((select count(*) from public.members where id = md5('pilot-member-1-1')::uuid), 0::bigint, 'gym 5 owner sees no foreign member id');
select is((select count(*) from public.organizations where id = '00000000-0000-4000-8000-000000000001'::uuid), 0::bigint, 'gym 5 owner sees no foreign organization id');
with changed as (update public.members set full_name = 'MUST NOT CHANGE' where id = md5('pilot-member-1-1')::uuid returning id)
select is((select count(*) from changed), 0::bigint, 'gym 5 cross-tenant update affects zero rows');
select throws_ok($$delete from public.members where id = md5('pilot-member-1-1')::uuid$$, '42501', null, 'gym 5 cross-tenant delete is refused');
set local role postgres;
select is((select full_name from public.members where id = md5('pilot-member-1-1')::uuid), 'Pilot Member 1-1', 'gym 5 foreign row is unchanged');

select * from finish();
rollback;
