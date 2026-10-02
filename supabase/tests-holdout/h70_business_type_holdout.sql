-- Independent BIZ holdout, frozen contract only. No implementation or visible suites read.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(71);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$
select ('70900000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid $$;
create function pg_temp.claims(n integer default 1) returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(200+n),'role','authenticated','tenant_id',pg_temp.u(case when n=5 then 2 else 1 end),'staff_id',pg_temp.u(200+n),'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk' when 4 then 'trainer' when 5 then 'gym_owner' else 'gym_owner' end)::text $$;
create function pg_temp.run(q text,c text default pg_temp.claims(),r text default 'authenticated') returns jsonb language plpgsql as $$
declare v jsonb;d text;begin
perform set_config('request.jwt.claims',coalesce(c,''),true);execute format('set local role %I',r);
begin execute q into v;exception when others then get stacked diagnostics d=pg_exception_detail;v:=jsonb_build_object('error',sqlstate,'detail',d);end;
set local role postgres;perform set_config('request.jwt.claims','',true);return coalesce(v,'null'::jsonb);end $$;
insert into public.organizations(id,name,gym_code,status,timezone,currency)values
(pg_temp.u(1),'BIZ owner A','H70BZA','active','Asia/Kolkata','INR'),(pg_temp.u(2),'BIZ owner B','H70BZB','active','Asia/Kolkata','INR');
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
create temp table h70_before as select id,to_jsonb(o)-'business_type'-'updated_at' facts from public.organizations o where id in(pg_temp.u(1),pg_temp.u(2));
create temp table h70_settings as select tenant_id,to_jsonb(o) facts from public.organization_settings o where tenant_id in(pg_temp.u(1),pg_temp.u(2));
select enum_has_labels('public','business_type',array['gym','dance','yoga','martial_arts','studio']::name[],'BIZ-001 canonical enum order');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'gym','BIZ-001 default gym');
select ok((select attnotnull from pg_attribute where attrelid='public.organizations'::regclass and attname='business_type'),'BIZ-001 not nullable');
select is(pg_temp.run('select to_jsonb(g)from public.set_business_type(''dance'')g')->>'previous_business_type','gym','BIZ-003 first return previous value');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'dance','BIZ-003 command changes own tenant');
select is((select business_type::text from public.organizations where id=pg_temp.u(2)),'gym','BIZ-007 foreign tenant unchanged');
select is(pg_temp.run('select to_jsonb(g)from public.set_business_type(''dance'')g')->>'changed','false','BIZ-003 replay no-op');
select is((select count(*)from public.audit_log where tenant_id=pg_temp.u(1)and action='organization.business_type_changed'),1::bigint,'BIZ-008 exact one owner audit');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1)and record_id=pg_temp.u(1)and record_type='organization'and action='organization.business_type_changed'and actor_user_id=pg_temp.u(201)and actor_role='gym_owner'and reason is null and before='{"business_type":"gym"}'::jsonb and after='{"business_type":"dance"}'::jsonb),'BIZ-008 exact owner attribution and projection');
select is(pg_temp.run('select to_jsonb(g)from public.set_business_type(null)g')->>'error','22023','BIZ-004 null type');
select is(pg_temp.run('select to_jsonb(g)from public.set_business_type(''yoga'')g',pg_temp.claims(5))->>'previous_business_type','gym','BIZ-007 second owner changes own tenant');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'dance','BIZ-007 isolation opposite direction');
select is(pg_temp.run('select to_jsonb(business_type)from public.organizations where id=pg_temp.u(1)'),'"dance"'::jsonb,'BIZ-002 own staff reads');
select is(pg_temp.run('select to_jsonb(business_type)from public.organizations where id=pg_temp.u(2)'),'null'::jsonb,'BIZ-002 foreign staff invisible');
select ok(pg_temp.run('select to_jsonb(count(*))from public.organizations','','anon')='0'::jsonb or pg_temp.run('select to_jsonb(count(*))from public.organizations','','anon')->>'error'='42501','BIZ-002 anonymous no organization exposure');
create temp table h70_mark as select count(*)n from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2));
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,pg_temp.claims(2))->>'error','42501','BIZ-004 manager refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,pg_temp.claims(3))->>'error','42501','BIZ-004 desk refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,pg_temp.claims(4))->>'error','42501','BIZ-004 trainer refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,pg_temp.claims(6))->>'error','42501','BIZ-004 inactive refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(209)))::text)->>'error','42501','BIZ-004 wrong subject refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('app_role','gym_manager'))::text)->>'error','42501','BIZ-004 wrong role refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','BIZ-004 wrong tenant refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb-'staff_id')::text)->>'error','42501','BIZ-004 missing staff refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('member_id',pg_temp.u(100)))::text)->>'error','42501','BIZ-004 member id contamination refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(900)))::text)->>'error','42501','BIZ-004 preview refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,jsonb_build_object('sub',pg_temp.u(209),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(100))::text)->>'error','42501','BIZ-004 member refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','BIZ-004 super refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,jsonb_build_object('sub',pg_temp.u(208),'role','authenticated','app_role','platform_support')::text)->>'error','42501','BIZ-004 support refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,'','anon')->>'error','42501','BIZ-004 anon RPC grant refused');
select is(pg_temp.run($q$select to_jsonb(g)from public.set_business_type('studio')g$q$,'','service_role')->>'error','42501','BIZ-004 service_role RPC grant refused');
select is((select count(*)from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2))),(select n from h70_mark),'BIZ-008 refusals write no audit');
select is(pg_temp.run($q$update public.organizations set business_type='studio'where id=pg_temp.u(1)returning to_jsonb(id)$q$,pg_temp.claims(1))->>'error','42501','BIZ-006 direct role 1 cannot change type');
select is(pg_temp.run($q$with changed as(update public.organizations set business_type='studio'where id=pg_temp.u(1)returning id)select to_jsonb(count(*))from changed$q$,pg_temp.claims(2)),'0'::jsonb,'BIZ-006 manager write-hidden row affects zero rows');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'dance','BIZ-006 manager write-hidden row leaves type unchanged');
select is(pg_temp.run($q$with changed as(update public.organizations set business_type='studio'where id=pg_temp.u(1)returning id)select to_jsonb(count(*))from changed$q$,pg_temp.claims(3)),'0'::jsonb,'BIZ-006 front desk write-hidden row affects zero rows');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'dance','BIZ-006 front desk write-hidden row leaves type unchanged');
select is(pg_temp.run($q$with changed as(update public.organizations set business_type='studio'where id=pg_temp.u(1)returning id)select to_jsonb(count(*))from changed$q$,pg_temp.claims(4)),'0'::jsonb,'BIZ-006 trainer write-hidden row affects zero rows');
select is((select business_type::text from public.organizations where id=pg_temp.u(1)),'dance','BIZ-006 trainer write-hidden row leaves type unchanged');
select is(pg_temp.run($q$update public.organizations set business_type='studio'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'detail','business_type_command_required','BIZ-006 exact command-required detail');
select is(pg_temp.run($q$update public.organizations set status='suspended'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error','GL049','BIZ-006 direct commercial status retains guard');
select is(pg_temp.run($q$update public.organizations set trial_ends_at=clock_timestamp()+interval '1 day'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error','GL049','BIZ-006 direct commercial trial_ends_at retains guard');
select is(pg_temp.run($q$update public.organizations set activated_at=clock_timestamp()where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error','GL049','BIZ-006 direct commercial activated_at retains guard');
select ok(not exists(select 1 from public.organizations o join h70_before b using(id)where (to_jsonb(o)-'business_type'-'updated_at')<>b.facts),'BIZ-007 all other organization facts preserved');
select is(pg_temp.run($q$update public.organizations set name='BIZ renamed'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error',null::text,'BIZ-006 owner rename still allowed');
select is(pg_temp.run($q$update public.organizations set timezone='Asia/Calcutta'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error',null::text,'BIZ-006 owner timezone still allowed');
select is(pg_temp.run($q$update public.organizations set business_type='studio',status='suspended'where id=pg_temp.u(1)returning to_jsonb(id)$q$,pg_temp.claims(),'postgres')->>'error','42501','BIZ-006 definer owner cannot smuggle mixed commercial shape');
select is(pg_temp.run($q$update public.organizations set business_type='studio'where id=pg_temp.u(2)returning to_jsonb(id)$q$,'','service_role')->>'error',null::text,'BIZ-006 subjectless service writer retained');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'businessType','martial_arts','BIZ-005 platform changed target');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'businessType','martial_arts','BIZ-005 replay before stale check');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','studio',pg_temp.u(701))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','GL068','BIZ-005 key conflict refusal');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','studio',pg_temp.u(702))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','40001','BIZ-005 stale refusal');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(999),'gym','studio',pg_temp.u(703))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','P0002','BIZ-005 missing refusal');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),null,'studio',pg_temp.u(704))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','22023','BIZ-005 null refusal');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,pg_temp.claims(2))->>'error','42501','BIZ-005 platform command manager refused');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,pg_temp.claims(3))->>'error','42501','BIZ-005 platform command desk refused');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,pg_temp.claims(4))->>'error','42501','BIZ-005 platform command trainer refused');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,pg_temp.claims(6))->>'error','42501','BIZ-005 platform command inactive refused');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(209)))::text)->>'error','42501','BIZ-005 platform command wrong subject refused');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'dance','martial_arts',pg_temp.u(701))$q$,jsonb_build_object('sub',pg_temp.u(208),'role','authenticated','app_role','platform_support')::text)->>'error','42501','BIZ-005 platform command support refused');
select ok(not has_function_privilege('anon','public.set_business_type(public.business_type)','EXECUTE')and not has_function_privilege('service_role','public.set_business_type(public.business_type)','EXECUTE'),'BIZ-004 owner command grants');
select ok(not has_function_privilege('anon','public.set_gym_business_type(uuid,public.business_type,public.business_type,uuid)','EXECUTE')and not has_function_privilege('service_role','public.set_gym_business_type(uuid,public.business_type,public.business_type,uuid)','EXECUTE'),'BIZ-005 platform command grants');
select ok(not has_function_privilege('authenticated','app.business_type_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb)','EXECUTE'),'BIZ-008 audit helper private');
select is(pg_temp.run($q$select to_jsonb(app.business_type_audit(pg_temp.u(1),null,null,'invalid','organization',pg_temp.u(1),null,null))$q$,'','postgres')->>'error','22023','BIZ-008 audit allowlist');
select ok((select bool_and(p.prosecdef and p.provolatile='v' and 'search_path=""'=any(p.proconfig) and pg_get_userbyid(p.proowner)='postgres')from pg_proc p where p.oid in('public.set_business_type(public.business_type)'::regprocedure,'public.set_gym_business_type(uuid,public.business_type,public.business_type,uuid)'::regprocedure)),'BIZ-003/005 definer posture empty path');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid()and relation='public.organizations'::regclass and mode='RowShareLock'and granted),'BIZ-003 row-lock relation metadata retained; actual concurrent sessions are separate proof');
select ok(not exists(select 1 from public.organization_settings o join h70_settings b using(tenant_id)where to_jsonb(o)<>b.facts),'BIZ-007 type changes never mutate settings or preset');
select is(pg_temp.run($q$update public.organizations set tier='pro'where id=pg_temp.u(1)returning to_jsonb(id)$q$)->>'error','GL049','BIZ-006 direct tier guard unchanged');

select is(pg_temp.run($q$update public.organizations set business_type='studio'where id=pg_temp.u(1)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','BIZ-006 direct authenticated super-admin still needs audited command');
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'martial_arts','studio',pg_temp.u(705))$q$,(jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin','impersonation_session_id',pg_temp.u(900)))::text)->>'error','42501','BIZ-005 platform preview cannot change type');
create temp table h70_platform_mark as select count(*)n from public.audit_log where tenant_id=pg_temp.u(1)and action='organization.business_type_changed';
select is(pg_temp.run($q$select public.set_gym_business_type(pg_temp.u(1),'martial_arts','martial_arts',pg_temp.u(706))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'businessType','martial_arts','BIZ-005 no-op platform result');
select is((select count(*)from public.audit_log where tenant_id=pg_temp.u(1)and action='organization.business_type_changed'),(select n from h70_platform_mark),'BIZ-008 platform no-op emits no business-type audit');

select * from finish();
rollback;
