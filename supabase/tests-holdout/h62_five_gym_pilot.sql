-- PILOT-001 independent five-gym rehearsal. Fixtures are synthetic and rolled back.
begin;

set local role postgres;

select plan(29);

create temp table pilot_h62_fixture (
  tenant_id uuid primary key,
  branch_id uuid not null,
  owner_id uuid not null,
  foreign_member_id uuid not null,
  gym_code text not null
) on commit drop;

insert into pilot_h62_fixture (tenant_id, branch_id, owner_id, foreign_member_id, gym_code)
values
  ('62000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000101', '62000000-0000-4000-8000-000000000201', '62000000-0000-4000-8000-000000000301', 'P62A01'),
  ('62000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000102', '62000000-0000-4000-8000-000000000202', '62000000-0000-4000-8000-000000000302', 'P62A02'),
  ('62000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000103', '62000000-0000-4000-8000-000000000203', '62000000-0000-4000-8000-000000000303', 'P62A03'),
  ('62000000-0000-4000-8000-000000000004', '62000000-0000-4000-8000-000000000104', '62000000-0000-4000-8000-000000000204', '62000000-0000-4000-8000-000000000304', 'P62A04'),
  ('62000000-0000-4000-8000-000000000005', '62000000-0000-4000-8000-000000000105', '62000000-0000-4000-8000-000000000205', '62000000-0000-4000-8000-000000000305', 'P62A05');

insert into public.organizations (id, name, gym_code)
select tenant_id, 'PILOT H62 Gym ' || right(gym_code, 2), gym_code
from pilot_h62_fixture;

insert into public.branches (id, tenant_id, name, is_default)
select branch_id, tenant_id, 'PILOT H62 Branch ' || right(gym_code, 2), true
from pilot_h62_fixture;

insert into public.staff (id, tenant_id, branch_id, role, full_name)
select owner_id, tenant_id, branch_id, 'gym_owner', 'PILOT H62 Owner ' || right(gym_code, 2)
from pilot_h62_fixture;

insert into public.members (id, tenant_id, branch_id, member_code, full_name, phone)
select
  case when n = 1 then f.foreign_member_id else gen_random_uuid() end,
  f.tenant_id,
  f.branch_id,
  f.gym_code || lpad(n::text, 3, '0'),
  'PILOT H62 Member ' || right(f.gym_code, 2) || '-' || lpad(n::text, 3, '0'),
  '+917620' || right(f.gym_code, 2) || lpad(n::text, 4, '0')
from pilot_h62_fixture f
cross join generate_series(1, 50) as n;

select is(
  (select count(*) from public.members where member_code like 'P62A%'),
  250::bigint,
  'synthetic member fixture has five groups of fifty'
);

select is(
  (select count(*) from public.staff where full_name like 'PILOT H62 Owner %'),
  5::bigint,
  'synthetic fixture has five distinct owners'
);

-- Owner 1
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000001', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000201')::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint, 'owner one sees one organization');
select is((select count(*) from public.members), 50::bigint, 'owner one sees fifty members');
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000302'), 0::bigint, 'owner one cannot read owner two member by id');
with changed as (update public.members set notes = 'H62 altered' where id = '62000000-0000-4000-8000-000000000302' returning id)
select is((select count(*) from changed), 0::bigint, 'owner one cannot update owner two member');
set local role postgres;
select is((select coalesce(notes, '') from public.members where id = '62000000-0000-4000-8000-000000000302'), ''::text, 'owner two member remains unchanged after owner one update');

-- Owner 2
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000002', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000202')::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint, 'owner two sees one organization');
select is((select count(*) from public.members), 50::bigint, 'owner two sees fifty members');
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000303'), 0::bigint, 'owner two cannot read owner three member by id');
with changed as (update public.members set notes = 'H62 altered' where id = '62000000-0000-4000-8000-000000000303' returning id)
select is((select count(*) from changed), 0::bigint, 'owner two cannot update owner three member');
set local role postgres;
select is((select coalesce(notes, '') from public.members where id = '62000000-0000-4000-8000-000000000303'), ''::text, 'owner three member remains unchanged after owner two update');

-- Owner 3
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000003', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000203')::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint, 'owner three sees one organization');
select is((select count(*) from public.members), 50::bigint, 'owner three sees fifty members');
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000304'), 0::bigint, 'owner three cannot read owner four member by id');
with changed as (update public.members set notes = 'H62 altered' where id = '62000000-0000-4000-8000-000000000304' returning id)
select is((select count(*) from changed), 0::bigint, 'owner three cannot update owner four member');
set local role postgres;
select is((select coalesce(notes, '') from public.members where id = '62000000-0000-4000-8000-000000000304'), ''::text, 'owner four member remains unchanged after owner three update');

-- Owner 4
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000004', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000204')::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint, 'owner four sees one organization');
select is((select count(*) from public.members), 50::bigint, 'owner four sees fifty members');
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000305'), 0::bigint, 'owner four cannot read owner five member by id');
with changed as (update public.members set notes = 'H62 altered' where id = '62000000-0000-4000-8000-000000000305' returning id)
select is((select count(*) from changed), 0::bigint, 'owner four cannot update owner five member');
set local role postgres;
select is((select coalesce(notes, '') from public.members where id = '62000000-0000-4000-8000-000000000305'), ''::text, 'owner five member remains unchanged after owner four update');

-- Owner 5
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000005', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000205')::text, true);
set local role authenticated;
select is((select count(*) from public.organizations), 1::bigint, 'owner five sees one organization');
select is((select count(*) from public.members), 50::bigint, 'owner five sees fifty members');
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000301'), 0::bigint, 'owner five cannot read owner one member by id');
with changed as (update public.members set notes = 'H62 altered' where id = '62000000-0000-4000-8000-000000000301' returning id)
select is((select count(*) from changed), 0::bigint, 'owner five cannot update owner one member');
set local role postgres;
select is((select coalesce(notes, '') from public.members where id = '62000000-0000-4000-8000-000000000301'), ''::text, 'owner one member remains unchanged after owner five update');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '62000000-0000-4000-8000-000000000001', 'app_role', 'gym_owner', 'staff_id', '62000000-0000-4000-8000-000000000201')::text, true);
set local role authenticated;
select throws_ok(
  $$delete from public.members where id = '62000000-0000-4000-8000-000000000302'$$,
  '42501', null,
  'owner one cannot delete owner two member'
);
set local role postgres;
select is((select count(*) from public.members where id = '62000000-0000-4000-8000-000000000302'), 1::bigint, 'owner two member remains after foreign delete attempt');

select * from finish();
rollback;
