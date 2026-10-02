-- Independent visible boundary author; public contract and visible fixture patterns only.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(42);

create function pg_temp.u(n integer) returns uuid language sql immutable as
$$ select ('74100000-0000-4000-8000-' || lpad(to_hex(n),12,'0'))::uuid $$;
create function pg_temp.claim(who integer, gym integer default 1, extra jsonb default '{}'::jsonb)
returns void language plpgsql as $$
declare r text; j jsonb;
begin
  r := case who when 21 then 'gym_owner' when 22 then 'gym_manager'
    when 23 then 'front_desk' when 24 then 'trainer' when 25 then 'trainer'
    when 26 then 'front_desk' when 27 then 'gym_owner'
    when 28 then 'super_admin' when 29 then 'platform_support' else 'member' end;
  j := jsonb_build_object('sub',pg_temp.u(who+900),'role','authenticated',
    'app_role',r,'tenant_id',pg_temp.u(gym));
  if who between 21 and 27 then j := j || jsonb_build_object('staff_id',pg_temp.u(who));
  elsif who >= 101 then j := j || jsonb_build_object('member_id',pg_temp.u(who)); end if;
  perform set_config('request.jwt.claims',(j || extra)::text,true);
end $$;
-- Exceptions are captured in a subtransaction: a refusal cannot leave writes behind.
create function pg_temp.run(q text) returns text language plpgsql as $$
begin execute q; return 'OK'; exception when others then return sqlstate; end $$;
create table pg_temp.saved(k text primary key, v jsonb);
grant all on pg_temp.saved to authenticated;
create function pg_temp.capture(p_key text,p_query text) returns text language plpgsql as $$
declare v_result jsonb;
begin execute 'select to_jsonb(x) from (' || p_query || ') x' into v_result;
  insert into pg_temp.saved values(p_key,v_result) on conflict(k) do update set v=excluded.v;
  return 'OK'; exception when others then return sqlstate; end $$;
create function pg_temp.id(p_key text,p_field text) returns uuid language sql stable as
$$ select (v->>p_field)::uuid from pg_temp.saved where saved.k=p_key $$;

insert into auth.users(id,email) select pg_temp.u(n+900),'clb74-'||n||'@example.test'
from generate_series(21,29) n union all
select pg_temp.u(n+900),'clb74-'||n||'@example.test' from generate_series(101,110) n;
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 (pg_temp.u(928),'super_admin','Root','root74@example.test',true),
 (pg_temp.u(929),'platform_support','Support','support74@example.test',true);
-- Legitimate configuration fixture: active platform identity, normal commercial guard.
do $fixture$ declare previous_claims text := current_setting('request.jwt.claims',true); begin
 perform pg_temp.claim(28,1,jsonb_build_object('tenant_id',null));
 insert into public.organizations(id,name,gym_code,status,timezone) values
 (pg_temp.u(1),'CLS A','CLB74A','active','Asia/Kolkata'),
 (pg_temp.u(2),'CLS B','CLB74B','active','Pacific/Kiritimati');
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
exception when others then
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
 raise;
end $fixture$;
insert into public.branches(id,tenant_id,name,is_default,timezone) values
 (pg_temp.u(11),pg_temp.u(1),'Main',true,'Asia/Kolkata'),
 (pg_temp.u(12),pg_temp.u(1),'West',false,'Etc/GMT+12'),
 (pg_temp.u(13),pg_temp.u(2),'East',true,'Pacific/Kiritimati');
-- Bound staff configuration uses the canonical active platform identity.
do $staff_fixture$ declare previous_claims text := current_setting('request.jwt.claims',true); begin
 perform pg_temp.claim(28,1,jsonb_build_object('tenant_id',null));
 insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
 (pg_temp.u(21),pg_temp.u(1),pg_temp.u(11),pg_temp.u(921),'gym_owner','Owner',true),
 (pg_temp.u(22),pg_temp.u(1),pg_temp.u(11),pg_temp.u(922),'gym_manager','Manager',true),
 (pg_temp.u(23),pg_temp.u(1),pg_temp.u(11),pg_temp.u(923),'front_desk','Desk',true),
 (pg_temp.u(24),pg_temp.u(1),pg_temp.u(11),pg_temp.u(924),'trainer','Lead',true),
 (pg_temp.u(25),pg_temp.u(1),pg_temp.u(11),pg_temp.u(925),'trainer','Other Lead',true),
 (pg_temp.u(26),pg_temp.u(1),pg_temp.u(11),pg_temp.u(926),'front_desk','Inactive',false),
 (pg_temp.u(27),pg_temp.u(2),pg_temp.u(13),pg_temp.u(927),'gym_owner','B Owner',true);
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
exception when others then
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
 raise;
end $staff_fixture$;
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status,erased_at)
select pg_temp.u(n),pg_temp.u(case when n=110 then 2 else 1 end),
 pg_temp.u(case when n=110 then 13 when n=106 then 12 else 11 end),
 case when n=107 then null else pg_temp.u(n+900) end,
 'Secret CLS member '||n,'+91740000'||lpad(n::text,4,'0'),
 case when n=108 then 'blocked'::public.member_status when n=109 then 'cancelled'::public.member_status else 'active'::public.member_status end,
 case when n=105 then statement_timestamp() else null end
from generate_series(101,110) n;
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 (pg_temp.u(41),pg_temp.u(1),'CLS plan',30,10000),(pg_temp.u(42),pg_temp.u(2),'CLS plan',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
select pg_temp.u(n+1000),pg_temp.u(case when n=110 then 2 else 1 end),pg_temp.u(n),
 pg_temp.u(case when n=110 then 42 else 41 end),
 case when n=102 then 'frozen'::public.membership_status when n=103 then 'pending'::public.membership_status else 'active'::public.membership_status end,
 current_date-1,current_date+30,10000
from generate_series(101,110) n;
insert into public.organization_settings(tenant_id) values(pg_temp.u(1)),(pg_temp.u(2)) on conflict do nothing;
-- Start boundaries use real branch-local future days inside the production horizon.
set local role authenticated;
select pg_temp.claim(21);
insert into pg_temp.saved select 'service',jsonb_build_object('id',public.create_service('Boundary',null,60,4,0));
select is(pg_temp.capture('midnight',$$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '00:00:00',60,4,null) as id$$),'OK','CLS boundary: exact midnight accepted');
select is(pg_temp.capture('last',$$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+4,time '23:59:59.999999',60,4,null) as id$$),'OK','CLS boundary: last representable instant before 24 accepted');
select is(pg_temp.capture('rulezero',$$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+5)::smallint],time '00:00:00',60,4,null,(statement_timestamp() at time zone 'Asia/Kolkata')::date+5,null)$$),'OK','CLS boundary: weekly midnight accepted');
select is(pg_temp.capture('rulelast',$$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(12),array[extract(dow from (statement_timestamp() at time zone 'Etc/GMT+12')::date+5)::smallint],time '23:59:59.999999',60,4,null,(statement_timestamp() at time zone 'Etc/GMT+12')::date+5,null)$$),'OK','CLS boundary: weekly last wall instant accepted in western branch');
set local role postgres;
create function pg_temp.boundary_state() returns jsonb language sql stable as $$
select jsonb_build_object('rules',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from public.class_rules r where tenant_id=pg_temp.u(1)),
'sessions',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from public.class_sessions r where tenant_id=pg_temp.u(1)),
'audit',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from public.audit_log r where tenant_id=pg_temp.u(1))) $$;
insert into pg_temp.saved values('before',pg_temp.boundary_state());
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($q$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+3)::smallint],time '24:00',60,4,null,(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,null)$q$),'22023','CLS boundary: actor 21 rule 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'22023','CLS boundary: actor 21 oneoff 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.update_class_session(pg_temp.id('midnight','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'22023','CLS boundary: actor 21 edit 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
set local role authenticated;
select pg_temp.claim(22);
select is(pg_temp.run($q$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+3)::smallint],time '24:00',60,4,null,(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,null)$q$),'22023','CLS boundary: actor 22 rule 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'22023','CLS boundary: actor 22 oneoff 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.update_class_session(pg_temp.id('midnight','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'22023','CLS boundary: actor 22 edit 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
set local role authenticated;
select pg_temp.claim(23);
select is(pg_temp.run($q$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+3)::smallint],time '24:00',60,4,null,(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,null)$q$),'42501','CLS boundary: actor 23 rule 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'42501','CLS boundary: actor 23 oneoff 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.update_class_session(pg_temp.id('midnight','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'42501','CLS boundary: actor 23 edit 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
set local role authenticated;
select pg_temp.claim(101);
select is(pg_temp.run($q$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+3)::smallint],time '24:00',60,4,null,(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,null)$q$),'42501','CLS boundary: actor 101 rule 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'42501','CLS boundary: actor 101 oneoff 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select is(pg_temp.run($q$select public.update_class_session(pg_temp.id('midnight','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+3,time '24:00',60,4,null)$q$),'42501','CLS boundary: actor 101 edit 24:00 refusal after authorization');
set local role postgres;
select is(pg_temp.boundary_state(),(select v from pg_temp.saved where k='before'),'CLS boundary: refused command leaves sessions rules and audit unchanged');
set local role authenticated;
select pg_temp.claim(21);
select lives_ok($q$select public.update_class_session(pg_temp.id('midnight','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+6,time '00:00',60,4,null)$q$,'CLS boundary: one-off edit to exact midnight accepted');
select lives_ok($q$select public.update_class_session(pg_temp.id('last','id'),(statement_timestamp() at time zone 'Asia/Kolkata')::date+7,time '23:59:59.999999',60,4,null)$q$,'CLS boundary: one-off edit before 24 accepted');
set local role postgres;
insert into pg_temp.saved select 'occurrence',jsonb_build_object('id',id,'row',to_jsonb(s)) from public.class_sessions s where rule_id=pg_temp.id('rulezero','rule_id') order by session_date limit 1;
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($q$select public.update_class_session(pg_temp.id('occurrence','id'),((select v->'row'->>'session_date' from pg_temp.saved where k='occurrence')::date)+1,time '00:00',60,4,null)$q$),'22023','CLS boundary: explicit rule occurrence cannot move to another date');
set local role postgres;
select is((select to_jsonb(s) from public.class_sessions s where id=pg_temp.id('occurrence','id')),(select v->'row' from pg_temp.saved where k='occurrence'),'CLS boundary: refused occurrence edit preserves complete identity');
select ok((select bool_and(session_date=(starts_at at time zone app.class_branch_timezone(tenant_id,branch_id))::date) from public.class_sessions where tenant_id=pg_temp.u(1)),'CLS boundary: all accepted starts store resolved branch-local day');
select ok((select (ends_at at time zone 'Asia/Kolkata')::date=session_date+1 from public.class_sessions where id=pg_temp.id('last','id')),'CLS boundary: crossing midnight at end retains start day');
select ok((select bool_and(s.session_date=(s.starts_at at time zone app.class_branch_timezone(s.tenant_id,s.branch_id))::date and extract(dow from s.session_date)=r.weekday) from public.class_sessions s join public.class_rules r on r.id=s.rule_id where s.tenant_id=pg_temp.u(1)),'CLS boundary: generated occurrence dates retain rule weekday');
select is(app.generate_class_sessions(pg_temp.u(1),null,null),0,'CLS boundary: ordinary generator replay retains occurrence identities');
select is(app.class_local_instant('America/New_York',date '2026-03-08',time '02:30'),timestamptz '2026-03-08 07:30+00','CLS boundary: ordinary DST gap resolution preserved');
select is(app.class_local_instant('America/New_York',date '2026-11-01',time '01:30'),timestamptz '2026-11-01 06:30+00','CLS boundary: ordinary DST fold resolution preserved');
-- Apia skipped 2011-12-30 is outside the actual rolling 28-day horizon. No clock
-- injection is in the public contract. This resolver check is NOT generator-skip proof.
select is((app.class_local_instant('Pacific/Apia',date '2011-12-30',time '12:00') at time zone 'Pacific/Apia')::date,date '2011-12-31','CLS boundary: skipped civil date actually resolves to another local day');
-- Malformed imported wall-time data is permitted by the frozen table CHECK list.
-- No constraints/triggers or clock are altered: genuine generator owns the skip.
insert into public.class_rules(id,tenant_id,service_id,branch_id,weekday,start_time,duration_minutes,capacity,valid_from,valid_until)
select pg_temp.u(501),pg_temp.u(1),pg_temp.id('service','id'),pg_temp.u(11),extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+2)::smallint,time '24:00',60,4,(statement_timestamp() at time zone 'Asia/Kolkata')::date+2,(statement_timestamp() at time zone 'Asia/Kolkata')::date+2;
select is(pg_temp.capture('skip',$q$select app.generate_class_sessions(pg_temp.u(1),pg_temp.u(501),null) as created$q$),'OK','CLS boundary: genuine generator does not raise on imported 24:00 occurrence');
select is((select (v->>'created')::integer from pg_temp.saved where k='skip'),0,'CLS boundary: generator creates zero shifted occurrences');
select is((select count(*)::integer from public.class_sessions where rule_id=pg_temp.u(501)),0,'CLS boundary: no next-day session stored under earlier rule date');
select * from finish();
rollback;
