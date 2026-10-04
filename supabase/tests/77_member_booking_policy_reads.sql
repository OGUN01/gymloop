-- PT/CLS read-contract diagnostic: retain every non-AccessShare relation lock, with catalog names.
-- Independent visible SQL contract: approved member-policy reads only.
-- No migration, implementation, holdout or critic material was read.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(65);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('77000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(m integer default 101,t integer default 1,extra jsonb default '{}') returns void language plpgsql as $$begin perform set_config('request.jwt.claims',(jsonb_build_object('sub',pg_temp.u(m+900),'role','authenticated','app_role','member','tenant_id',pg_temp.u(t),'member_id',pg_temp.u(m))||extra)::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.reject(c jsonb) returns text language plpgsql as $$declare old text:=current_setting('request.jwt.claims',true); answer text; begin perform pg_temp.claim(101,1,c); answer:=pg_temp.probe('select * from public.read_member_pt_policy()'); perform set_config('request.jwt.claims',old,true); return answer; exception when others then perform set_config('request.jwt.claims',old,true); raise; end$$;
create temporary table proof(k text primary key,v jsonb);
grant all on proof to authenticated;
insert into auth.users(id,email) select pg_temp.u(n+900),'policy77-'||n||'@example.test' from (values(28),(21),(101),(102),(103),(104),(105),(106)) x(n);
insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.u(928),'super_admin','Policy root','policy77-root@example.test',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
insert into public.organizations(id,name,gym_code,status,timezone) values(pg_temp.u(1),'Policy A','POL77A','active','Asia/Kolkata'),(pg_temp.u(2),'Policy B','POL77B','active','UTC');
insert into public.branches(id,tenant_id,name,is_default,timezone) values(pg_temp.u(11),pg_temp.u(1),'Main',true,'Asia/Kolkata'),(pg_temp.u(12),pg_temp.u(2),'Foreign',true,'UTC');
insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values(pg_temp.u(21),pg_temp.u(1),pg_temp.u(11),pg_temp.u(921),'gym_owner','Policy owner',true);
select set_config('request.jwt.claims','',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status,erased_at)
select pg_temp.u(n),pg_temp.u(case when n=106 then 2 else 1 end),pg_temp.u(case when n=106 then 12 else 11 end),pg_temp.u(n+900),'Policy member '||n,'+91770000'||lpad(n::text,4,'0'),case when n=103 then 'blocked'::public.member_status when n=104 then 'cancelled'::public.member_status else 'active'::public.member_status end,case when n=105 then statement_timestamp() else null end from generate_series(101,106)n;
insert into public.organization_settings(tenant_id,class_cancel_window_hours) values(pg_temp.u(1),7),(pg_temp.u(2),13) on conflict(tenant_id) do update set class_cancel_window_hours=excluded.class_cancel_window_hours;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(921),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(21))::text,true);
select public.set_pt_policy(37,true,60);
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.u(41),pg_temp.u(1),'Policy membership',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) values(pg_temp.u(51),pg_temp.u(1),pg_temp.u(101),pg_temp.u(41),'active',current_date-2,current_date+30,10000),(pg_temp.u(52),pg_temp.u(1),pg_temp.u(102),pg_temp.u(41),'pending',current_date-2,current_date+30,10000);
insert into public.services(id,tenant_id,name,default_duration_minutes,default_capacity) values(pg_temp.u(61),pg_temp.u(1),'Policy class',60,2);
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity)
select pg_temp.u(n),pg_temp.u(1),pg_temp.u(61),pg_temp.u(11),((statement_timestamp()+case when n=204 then interval '-1 hour' else interval '3 days'+(n-201)*interval '2 hours' end) at time zone 'Asia/Kolkata')::date,statement_timestamp()+case when n=204 then interval '-1 hour' else interval '3 days'+(n-201)*interval '2 hours' end,statement_timestamp()+case when n=204 then interval '-1 hour' else interval '3 days'+(n-201)*interval '2 hours' end+interval '60 minutes',case when n=203 then 1 else 2 end from generate_series(201,206)n;
insert into public.class_bookings(id,tenant_id,session_id,member_id,status,cancelled_at) values(pg_temp.u(301),pg_temp.u(1),pg_temp.u(202),pg_temp.u(101),'booked',null),(pg_temp.u(302),pg_temp.u(1),pg_temp.u(203),pg_temp.u(102),'booked',null),(pg_temp.u(303),pg_temp.u(1),pg_temp.u(206),pg_temp.u(101),'session_cancelled',statement_timestamp());
update public.class_sessions set status='cancelled',cancelled_at=statement_timestamp(),cancel_reason='Fixture cancelled',cancelled_by_staff_id=pg_temp.u(21) where id=pg_temp.u(206);
insert into proof select 'starts',jsonb_object_agg(id,starts_at) from public.class_sessions where tenant_id=pg_temp.u(1);
select ok(exists(select 1 from pg_proc where oid=to_regprocedure('public.read_member_pt_policy()') and prosecdef and provolatile='s' and pg_get_userbyid(proowner)='postgres' and proconfig @> array['search_path=""']),'PT: stable postgres definer with empty path');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='read_member_pt_policy'),1,'PT: one selector-free signature');
select is((select array_agg(a.n order by a.ord) from pg_proc p cross join lateral unnest(p.proargnames,p.proargmodes) with ordinality a(n,m,ord) where p.oid=to_regprocedure('public.read_member_pt_policy()') and a.m='t'),array['cancel_window_hours','late_cancel_consumes_session']::text[],'PT: exact two names');
select is((select array_agg(a.t::regtype::text order by a.ord) from pg_proc p cross join lateral unnest(p.proallargtypes,p.proargmodes) with ordinality a(t,m,ord) where p.oid=to_regprocedure('public.read_member_pt_policy()') and a.m='t'),array['integer','boolean']::text[],'PT: exact two types');
select ok(exists(select 1 from pg_proc p where oid=to_regprocedure('public.read_member_pt_policy()') and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'PT: authenticated-only execute including PUBLIC revocation');
select ok(not has_function_privilege('authenticated','app.pt_member_actor()','EXECUTE'),'PT: validator stays private');
insert into proof select 'read_before',jsonb_build_object(
 'settings',(select jsonb_agg(to_jsonb(x) order by tenant_id) from public.organization_settings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))),
 'classes',(select jsonb_agg(to_jsonb(x) order by id) from public.class_bookings x where tenant_id=pg_temp.u(1)),
 'audits',(select count(*) from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2))),
 'notices',(select count(*) from public.notifications where tenant_id in(pg_temp.u(1),pg_temp.u(2))));
insert into proof select 'locks_before',coalesce(jsonb_agg(jsonb_build_object('relation',relation,'schema',(select n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.oid=relation),'name',(select c.relname from pg_class c where c.oid=relation),'mode',mode,'type',locktype) order by relation,mode,locktype),'[]') from pg_locks where pid=pg_backend_pid() and mode<>'AccessShareLock' and relation is not null;
set local role authenticated;
select pg_temp.claim();
select is((select jsonb_agg(to_jsonb(x)) from public.read_member_pt_policy()x),'[{"cancel_window_hours":37,"late_cancel_consumes_session":true}]'::jsonb,'PT: current exact same-tenant policy');
select is_empty('select * from public.organization_settings','PT: no direct settings read');
select is(pg_temp.probe('select app.pt_member_actor()'),'42501','PT: no validator execution');
select is_empty('select 1 from pg_locks where pid=pg_backend_pid() and locktype=''advisory''','PT: no advisory lock');
select is(current_setting('request.jwt.claims')::jsonb,jsonb_build_object('sub',pg_temp.u(1001),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101)),'PT: claims unchanged');
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),'open','CLS: open fixture is visible');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),(select (v->>pg_temp.u(201)::text)::timestamptz-interval '7 hours' from proof where k='starts'),'CLS: open exact deadline boundary');
select is((select can_cancel from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),false,'CLS: open unbooked cannot cancel');
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(202)),'booked','CLS: booked fixture is visible');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(202)),(select (v->>pg_temp.u(202)::text)::timestamptz-interval '7 hours' from proof where k='starts'),'CLS: booked exact deadline boundary');
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(203)),'full','CLS: full fixture is visible');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(203)),null::timestamptz,'CLS: full exact deadline boundary');
select is((select can_cancel from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(203)),false,'CLS: full unbooked cannot cancel');
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(204)),'closed','CLS: closed fixture is visible');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(204)),null::timestamptz,'CLS: closed exact deadline boundary');
select is((select can_cancel from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(204)),false,'CLS: closed unbooked cannot cancel');
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(206)),'cancelled','CLS: cancelled fixture is visible');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(206)),null::timestamptz,'CLS: cancelled exact deadline boundary');
select is((select can_cancel from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(206)),false,'CLS: cancelled unbooked cannot cancel');
select pg_temp.claim(102);
select is((select availability from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),'membership_not_live','CLS: pending membership fixture');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),null::timestamptz,'CLS: nonlive membership has no deadline');
select pg_temp.claim();
select is(pg_temp.reject(jsonb_build_object('tenant_id',pg_temp.u(2))),'42501','PT: cross-tenant refused');
select is(pg_temp.reject(jsonb_build_object('tenant_id',pg_temp.u(999))),'42501','PT: unknown tenant refused');
select is(pg_temp.reject(jsonb_build_object('member_id',pg_temp.u(102))),'42501','PT: other member refused');
select is(pg_temp.reject(jsonb_build_object('member_id',pg_temp.u(999))),'42501','PT: unknown member refused');
select is(pg_temp.reject(jsonb_build_object('sub',pg_temp.u(1002))),'42501','PT: spoof subject refused');
select is(pg_temp.reject(jsonb_build_object('staff_id',pg_temp.u(21))),'42501','PT: mixed staff refused');
select is(pg_temp.reject(jsonb_build_object('impersonation_session_id',pg_temp.u(999))),'42501','PT: impersonation refused');
select is(pg_temp.reject(jsonb_build_object('member_id',null)),'42501','PT: missing member_id refused');
select is(pg_temp.reject(jsonb_build_object('member_id','invalid')),'42501','PT: malformed member_id refused');
select is(pg_temp.reject(jsonb_build_object('tenant_id',null)),'42501','PT: missing tenant_id refused');
select is(pg_temp.reject(jsonb_build_object('tenant_id','invalid')),'42501','PT: malformed tenant_id refused');
select is(pg_temp.reject(jsonb_build_object('sub',null)),'42501','PT: missing sub refused');
select is(pg_temp.reject(jsonb_build_object('sub','invalid')),'42501','PT: malformed sub refused');
select is(pg_temp.reject(jsonb_build_object('app_role',null)),'42501','PT: missing app_role refused');
select is(pg_temp.reject(jsonb_build_object('app_role','invalid')),'42501','PT: malformed app_role refused');
select is(pg_temp.reject(jsonb_build_object('app_role','gym_owner')),'42501','PT: gym_owner refused');
select is(pg_temp.reject(jsonb_build_object('app_role','gym_manager')),'42501','PT: gym_manager refused');
select is(pg_temp.reject(jsonb_build_object('app_role','front_desk')),'42501','PT: front_desk refused');
select is(pg_temp.reject(jsonb_build_object('app_role','trainer')),'42501','PT: trainer refused');
select is(pg_temp.reject(jsonb_build_object('app_role','super_admin')),'42501','PT: super_admin refused');
select is(pg_temp.reject(jsonb_build_object('app_role','platform_support')),'42501','PT: platform_support refused');
select pg_temp.claim(103);
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: blocked member refused');
select pg_temp.claim(104);
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: cancelled member refused');
select pg_temp.claim(105);
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: erased member refused');
select pg_temp.claim(106,2);
select is((select jsonb_agg(to_jsonb(x)) from public.read_member_pt_policy()x),'[{"cancel_window_hours":24,"late_cancel_consumes_session":true}]'::jsonb,'PT: different real tenant receives its own policy');
set local role postgres;
select is(jsonb_build_object(
 'settings',(select jsonb_agg(to_jsonb(x) order by tenant_id) from public.organization_settings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))),
 'classes',(select jsonb_agg(to_jsonb(x) order by id) from public.class_bookings x where tenant_id=pg_temp.u(1)),
 'audits',(select count(*) from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2))),
 'notices',(select count(*) from public.notifications where tenant_id in(pg_temp.u(1),pg_temp.u(2)))),
 (select v from proof where k='read_before'),'Reads/refusals preserve settings, bookings, audit and notifications');
select is((select coalesce(jsonb_agg(jsonb_build_object('relation',relation,'schema',(select n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.oid=relation),'name',(select c.relname from pg_class c where c.oid=relation),'mode',mode,'type',locktype) order by relation,mode,locktype),'[]') from pg_locks where pid=pg_backend_pid() and mode<>'AccessShareLock' and relation is not null),(select v from proof where k='locks_before'),'Reads/refusals add no write or row relation locks');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
-- Active -> trial is deliberately not a legal commercial transition. This
-- isolated actor-read fixture needs that historical state; restore the exact
-- commercial invariant before invoking any read under test.
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set status='trial',trial_ends_at=statement_timestamp()+interval '1 day' where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim();
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'OK','PT: live trial eligible');
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set trial_ends_at=statement_timestamp()-interval '1 day' where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim();
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: expired trial refused');
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set trial_ends_at=null where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim();
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: undated trial refused');
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set status='active',trial_ends_at=null where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set status='suspended' where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim();
select is(pg_temp.probe('select * from public.read_member_pt_policy()'),'42501','PT: suspended gym refused');
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set status='active' where id=pg_temp.u(1);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim(102);
select is((select can_cancel from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),false,'CLS: nonlive unbooked cannot cancel');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organization_settings set class_cancel_window_hours=11 where tenant_id=pg_temp.u(1);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(921),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(21))::text,true);
select public.set_pt_policy(0,false,60);
select pg_temp.claim();
select is((select jsonb_agg(to_jsonb(x)) from public.read_member_pt_policy()x),'[{"cancel_window_hours":0,"late_cancel_consumes_session":false}]'::jsonb,'PT: changed current policy, zero/false retained');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),(select (v->>pg_temp.u(201)::text)::timestamptz-interval '11 hours' from proof where k='starts'),'CLS: changed policy reevaluates open deadline');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(202)),(select (v->>pg_temp.u(202)::text)::timestamptz-interval '11 hours' from proof where k='starts'),'CLS: changed policy reevaluates booked deadline');
set local role postgres;
select set_config('request.jwt.claims','',true);
delete from public.organization_settings where tenant_id=pg_temp.u(1);
set local role authenticated;
select pg_temp.claim();
select is_empty('select * from public.read_member_pt_policy()','PT: missing settings is empty');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(201)),(select (v->>pg_temp.u(201)::text)::timestamptz-interval '2 hours' from proof where k='starts'),'CLS: existing missing-setting default for open');
select is((select cancel_by from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.u(202)),(select (v->>pg_temp.u(202)::text)::timestamptz-interval '2 hours' from proof where k='starts'),'CLS: existing missing-setting default for booked');
select * from finish();
rollback;
