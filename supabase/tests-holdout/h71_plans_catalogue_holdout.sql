-- Independent PLC holdout, frozen contract only. No implementation or visible suites read.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(29);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$
select ('71900000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid $$;
create function pg_temp.claims(n integer default 1) returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(200+n),'role','authenticated','tenant_id',pg_temp.u(case when n=5 then 2 else 1 end),'staff_id',pg_temp.u(200+n),'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk' when 4 then 'trainer' when 5 then 'gym_owner' else 'gym_owner' end)::text $$;
create function pg_temp.run(q text,c text default pg_temp.claims(),r text default 'authenticated') returns jsonb language plpgsql as $$
declare v jsonb;d text;begin
perform set_config('request.jwt.claims',coalesce(c,''),true);execute format('set local role %I',r);
begin execute q into v;exception when others then get stacked diagnostics d=pg_exception_detail;v:=jsonb_build_object('error',sqlstate,'detail',d);end;
set local role postgres;perform set_config('request.jwt.claims','',true);return coalesce(v,'null'::jsonb);end $$;
insert into public.organizations(id,name,gym_code,status,timezone,currency)values
(pg_temp.u(1),'PLC owner A','H71PLA','active','Asia/Kolkata','INR'),(pg_temp.u(2),'PLC owner B','H71PLB','active','Asia/Kolkata','INR');
insert into public.organization_settings(tenant_id)values(pg_temp.u(1)),(pg_temp.u(2));
insert into public.branches(id,tenant_id,name,is_default)values(pg_temp.u(11),pg_temp.u(1),'A',true),(pg_temp.u(12),pg_temp.u(2),'B',true);
insert into auth.users(id)select pg_temp.u(n)from generate_series(201,209)n;
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active)values
(pg_temp.u(201),pg_temp.u(201),pg_temp.u(1),pg_temp.u(11),'gym_owner','Owner A',true),
(pg_temp.u(202),pg_temp.u(202),pg_temp.u(1),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(203),pg_temp.u(203),pg_temp.u(1),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(204),pg_temp.u(204),pg_temp.u(1),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(205),pg_temp.u(205),pg_temp.u(2),pg_temp.u(12),'gym_owner','Owner B',true),
(pg_temp.u(206),pg_temp.u(206),pg_temp.u(1),pg_temp.u(11),'gym_owner','Inactive',false);
insert into public.platform_users(user_id,role,full_name,email,is_active)values
(pg_temp.u(207),'super_admin','Super','super@h70.test',true),(pg_temp.u(208),'platform_support','Support','support@h70.test',true);
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone)values(pg_temp.u(100),pg_temp.u(209),pg_temp.u(1),pg_temp.u(11),'Member','+919709000100');

insert into auth.users(id)values(pg_temp.u(210));
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone)values(pg_temp.u(101),pg_temp.u(210),pg_temp.u(2),pg_temp.u(12),'PLC other member','+919719000101');
create function pg_temp.member_claims(n integer default 1)returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(case n when 1 then 209 else 210 end),'role','authenticated','tenant_id',pg_temp.u(n),'app_role','member','member_id',pg_temp.u(case n when 1 then 100 else 101 end))::text $$;
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency,is_active,sort_order)values
(pg_temp.u(300),pg_temp.u(1),'PLC active first',30,9007199254740993,'INR',true,1),
(pg_temp.u(301),pg_temp.u(1),'PLC active second',90,20000,'INR',true,2),
(pg_temp.u(302),pg_temp.u(1),'PLC retired held',60,10000,'INR',false,3),
(pg_temp.u(303),pg_temp.u(2),'PLC other active',30,8000,'INR',true,1),
(pg_temp.u(304),pg_temp.u(2),'PLC other retired',30,7000,'INR',false,2);
-- ADR-098 membership fixture bypass: unrelated period-grant guards are not under test.
set local session_replication_role=replica;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,discount_paise,currency,periods_granted,duration_days)values
(pg_temp.u(400),pg_temp.u(1),pg_temp.u(100),pg_temp.u(302),'active',current_date-20,current_date+40,10000,0,'INR',1,60);
set local session_replication_role=origin;
select is(pg_temp.run('select to_jsonb(array_agg(id order by sort_order))from public.plans',pg_temp.member_claims()),to_jsonb(array[pg_temp.u(300),pg_temp.u(301)]),'PLC-001 unfiltered member select only own active');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans where id=pg_temp.u(302)',pg_temp.member_claims()),'0'::jsonb,'PLC-001 inactive primary-key lookup absent');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans where not is_active',pg_temp.member_claims()),'0'::jsonb,'PLC-001 inactive filter/count absent');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans where tenant_id=pg_temp.u(2)',pg_temp.member_claims()),'0'::jsonb,'PLC-001 foreign plans active/inactive invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans where tenant_id=pg_temp.u(1)',pg_temp.member_claims(2)),'0'::jsonb,'PLC-001 isolation opposite direction');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.member_claims(2)),'1'::jsonb,'PLC-001 other member owns one active plan');
select is(pg_temp.run('select to_jsonb(count(*))from public.memberships where id=pg_temp.u(400)',pg_temp.member_claims()),'1'::jsonb,'PLC-004 inactive plan keeps own membership readable');
select is(pg_temp.run('select to_jsonb(p.name)from public.memberships m left join public.plans p on p.id=m.plan_id where m.id=pg_temp.u(400)',pg_temp.member_claims()),'null'::jsonb,'PLC-004 inactive held plan embed absent');
select is(pg_temp.run('select to_jsonb(price_paise::text)from public.plans where id=pg_temp.u(300)',pg_temp.member_claims()),'"9007199254740993"'::jsonb,'PLC money exact decimal text retained by member read');
select is(pg_temp.run($q$update public.plans set is_active=false where id=pg_temp.u(301)returning to_jsonb(id)$q$)->>'error',null::text,'PLC-002 existing owner write retained');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.member_claims()),'1'::jsonb,'PLC-001 deactivate immediately visible');
select is(pg_temp.run($q$update public.plans set is_active=true where id=pg_temp.u(301)returning to_jsonb(id)$q$)->>'error',null::text,'PLC-002 owner reactivation retained');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.member_claims()),'2'::jsonb,'PLC-001 reactivation visible same transaction');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans','{}'),'0'::jsonb,'PLC-002 missing claims no exposure');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',(pg_temp.member_claims()::jsonb-'app_role')::text),'0'::jsonb,'PLC-002 tenant without role no exposure');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',(pg_temp.member_claims()::jsonb-'member_id')::text),'0'::jsonb,'PLC-002 member role without id no exposure');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',(pg_temp.member_claims()::jsonb||jsonb_build_object('app_role','trainer'))::text),'0'::jsonb,'PLC-002 role-mismatched member claim no exposure');
select is(pg_temp.run($q$insert into public.plans(tenant_id,name,duration_days,price_paise,currency)values(pg_temp.u(1),'forged',30,100,'INR')returning to_jsonb(id)$q$,pg_temp.member_claims())->>'error','42501','PLC-002 member insert still refused');
select is(pg_temp.run($q$with changed as(update public.plans set name='forged'where id=pg_temp.u(300)returning id)select to_jsonb(count(*))from changed$q$,pg_temp.member_claims()),'0'::jsonb,'PLC-002 member update still affects zero rows');
select ok(not has_table_privilege('authenticated','public.plans','DELETE')and not has_table_privilege('authenticated','public.plans','TRUNCATE'),'PLC-002 existing delete/truncate grant boundary');
select is((select count(*)from pg_policy where polrelid='public.plans'::regclass),5::bigint,'PLC-003 still exactly five policies');
select ok((select polcmd='r'and polroles=array[(select oid from pg_roles where rolname='authenticated')]from pg_policy where polrelid='public.plans'::regclass and polname='plans_member_select'),'PLC-003 original policy name command and role');
select ok(exists(select 1 from pg_indexes where schemaname='public'and tablename='plans'and indexname='plans_tenant_id_is_active_idx'),'PLC-003 existing tenant-active index retained');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.claims(1)),'3'::jsonb,'PLC-002 staff role 1 keeps active and inactive own plans');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.claims(2)),'3'::jsonb,'PLC-002 staff role 2 keeps active and inactive own plans');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.claims(3)),'3'::jsonb,'PLC-002 staff role 3 keeps active and inactive own plans');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',pg_temp.claims(4)),'3'::jsonb,'PLC-002 staff role 4 keeps active and inactive own plans');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text),'5'::jsonb,'PLC-002 super_admin unchanged cross-gym read');
select is(pg_temp.run('select to_jsonb(count(*))from public.plans',jsonb_build_object('sub',pg_temp.u(208),'role','authenticated','app_role','platform_support')::text),'5'::jsonb,'PLC-002 platform_support unchanged cross-gym read');
select * from finish();
rollback;
