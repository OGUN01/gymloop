-- Independent SLF-003 identity regression, derived from the frozen member-self-service proposal.
-- No source, migration, or holdout was read. All fixtures roll back.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(22);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('81900000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text,s integer,a integer,m integer default null) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(s),'member_id',case when m is not null then pg_temp.u(m) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer),pg_temp.probe(text) to authenticated;
insert into auth.users(id) select pg_temp.u(n) from generate_series(901,906) n;
insert into public.organizations(id,name,gym_code,status,timezone) values(pg_temp.u(1),'SLF identity','SLF819','active','Asia/Kolkata');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.u(11),pg_temp.u(1),'Identity',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
(pg_temp.u(21),pg_temp.u(1),pg_temp.u(901),pg_temp.u(11),'gym_owner','Owner',true),
(pg_temp.u(22),pg_temp.u(1),pg_temp.u(902),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(23),pg_temp.u(1),pg_temp.u(903),pg_temp.u(11),'front_desk','Desk',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status)
select pg_temp.u(100+n),pg_temp.u(1),pg_temp.u(11),pg_temp.u(903+n),'Identity member '||n,'+91819000010'||n,'active' from generate_series(1,3) n;
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.u(201),pg_temp.u(1),'Identity plan',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
select pg_temp.u(300+n),pg_temp.u(1),pg_temp.u(100+n),pg_temp.u(201),'active',app.gym_today(pg_temp.u(1))-1,app.gym_today(pg_temp.u(1))+30,10000 from generate_series(1,3) n;
insert into public.organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year) values(pg_temp.u(1),'gym_manager',30) on conflict(tenant_id) do update set pause_approver_role=excluded.pause_approver_role,max_freeze_days_per_year=excluded.max_freeze_days_per_year;
insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason)
select pg_temp.u(400+n),pg_temp.u(1),pg_temp.u(100+n),pg_temp.u(300+n),pg_temp.u(903+n),pg_temp.u(500+n),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Identity fixture' from generate_series(1,3) n;
create temporary table proof(k text primary key,v jsonb);
insert into proof values('before',jsonb_build_object('requests',(select jsonb_agg(to_jsonb(r) order by id) from public.member_freeze_requests r where tenant_id=pg_temp.u(1)),'commands',(select jsonb_agg(to_jsonb(r) order by id) from public.member_freeze_commands r where tenant_id=pg_temp.u(1)),'pauses',(select jsonb_agg(to_jsonb(r) order by id) from public.membership_pauses r where tenant_id=pg_temp.u(1)),'memberships',(select jsonb_agg(to_jsonb(r) order by id) from public.memberships r where tenant_id=pg_temp.u(1)),'audit',(select jsonb_agg(to_jsonb(r) order by id) from public.audit_log r where tenant_id=pg_temp.u(1))));
set local role authenticated;
select pg_temp.claim('gym_owner',23,903);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'42501','SLF-003: current database role differs from claimed owner refuses public.read_staff_freeze_requests before target/domain');
select is(pg_temp.probe('select public.read_member_freeze_request(pg_temp.u(401))'),'42501','SLF-003: current database role differs from claimed owner refuses public.read_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.adopt_member_freeze_request(pg_temp.u(401),1,pg_temp.u(601))'),'42501','SLF-003: current database role differs from claimed owner refuses public.adopt_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.approve_member_freeze_request(pg_temp.u(401),1,pg_temp.u(602))'),'42501','SLF-003: current database role differs from claimed owner refuses public.approve_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.reject_member_freeze_request(pg_temp.u(401),1,''Identity refusal'',pg_temp.u(603))'),'42501','SLF-003: current database role differs from claimed owner refuses public.reject_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.expire_member_freeze_request(pg_temp.u(401),1,pg_temp.u(604))'),'42501','SLF-003: current database role differs from claimed owner refuses public.expire_member_freeze_request before target/domain');
select pg_temp.claim('front_desk',23,903,101);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.read_staff_freeze_requests before target/domain');
select is(pg_temp.probe('select public.read_member_freeze_request(pg_temp.u(401))'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.read_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.adopt_member_freeze_request(pg_temp.u(401),1,pg_temp.u(601))'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.adopt_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.approve_member_freeze_request(pg_temp.u(401),1,pg_temp.u(602))'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.approve_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.reject_member_freeze_request(pg_temp.u(401),1,''Identity refusal'',pg_temp.u(603))'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.reject_member_freeze_request before target/domain');
select is(pg_temp.probe('select public.expire_member_freeze_request(pg_temp.u(401),1,pg_temp.u(604))'),'42501','SLF-003: staff claim contradictorily carries member_id refuses public.expire_member_freeze_request before target/domain');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is(jsonb_build_object('requests',(select jsonb_agg(to_jsonb(r) order by id) from public.member_freeze_requests r where tenant_id=pg_temp.u(1)),'commands',(select jsonb_agg(to_jsonb(r) order by id) from public.member_freeze_commands r where tenant_id=pg_temp.u(1)),'pauses',(select jsonb_agg(to_jsonb(r) order by id) from public.membership_pauses r where tenant_id=pg_temp.u(1)),'memberships',(select jsonb_agg(to_jsonb(r) order by id) from public.memberships r where tenant_id=pg_temp.u(1)),'audit',(select jsonb_agg(to_jsonb(r) order by id) from public.audit_log r where tenant_id=pg_temp.u(1))),(select v from proof where k='before'),'SLF-003: identity refusals leave request, command, pause, membership and audit rows unchanged');
set local role authenticated;
select pg_temp.claim('gym_owner',21,901);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'OK','SLF-003: real gym_owner with complete claims reads queue');
select is(pg_temp.probe('select public.adopt_member_freeze_request(pg_temp.u(401),1,pg_temp.u(611))'),'OK','SLF-003: real gym_owner with complete claims adopts');
select pg_temp.claim('gym_manager',22,902);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'OK','SLF-003: real gym_manager with complete claims reads queue');
select is(pg_temp.probe('select public.adopt_member_freeze_request(pg_temp.u(402),1,pg_temp.u(612))'),'OK','SLF-003: real gym_manager with complete claims adopts');
select pg_temp.claim('front_desk',23,903);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'OK','SLF-003: real front_desk with complete claims reads queue');
select is(pg_temp.probe('select public.adopt_member_freeze_request(pg_temp.u(403),1,pg_temp.u(613))'),'OK','SLF-003: real front_desk with complete claims adopts');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select adopted_by_staff_id from public.member_freeze_requests where id=pg_temp.u(401)),pg_temp.u(21),'SLF-003: permitted adoption records real staff 21');
select is((select adopted_by_staff_id from public.member_freeze_requests where id=pg_temp.u(402)),pg_temp.u(22),'SLF-003: permitted adoption records real staff 22');
select is((select adopted_by_staff_id from public.member_freeze_requests where id=pg_temp.u(403)),pg_temp.u(23),'SLF-003: permitted adoption records real staff 23');
select * from finish();
rollback;
