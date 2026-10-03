-- Independent visible repair contract; frozen spec 84810a9. No production read.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(75); -- 45 assertion statements + 22 window/policy + 5 date + 3 target matrix expansions
create function pg_temp.gid(n integer) returns uuid language sql immutable as $$select ('20200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
-- Probe subtransactions undo even an unexpected successful write.
create function pg_temp.err(q text) returns text language plpgsql as $$declare d text; begin begin execute q; raise exception using errcode='Z2020'; exception when others then if sqlstate='Z2020' then return 'SUCCESS'; end if; get stacked diagnostics d=PG_EXCEPTION_DETAIL; return sqlstate||':'||coalesce(d,''); end; end$$;
grant execute on function pg_temp.gid(integer),pg_temp.err(text) to authenticated;
select has_function('app','pt_availability_grid',array['text','text','date','date','jsonb','integer'],'declared private grid signature');
select ok((select not prosecdef and provolatile='s' and proretset and pg_get_userbyid(proowner)='postgres' and proconfig @> array['search_path=""'] and proargnames=array['p_gym_timezone','p_trainer_timezone','p_from','p_to','p_windows','p_session_minutes','starts_at','ends_at'] from pg_proc where oid=to_regprocedure('app.pt_availability_grid(text,text,date,date,jsonb,integer)')),'stable invoker exact input/output names and empty path');
select ok((select not has_function_privilege('anon',oid,'EXECUTE') and not has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('service_role',oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(proacl,acldefault('f',proowner))) a where a.grantee=0 and privilege_type='EXECUTE') from pg_proc where oid=to_regprocedure('app.pt_availability_grid(text,text,date,date,jsonb,integer)')),'no session or PUBLIC execute grant');
-- Fixed UTC lists are independently derived from real timezone transition facts.
select results_eq($q$select starts_at,ends_at from app.pt_availability_grid('America/New_York','America/New_York','2024-03-10','2024-03-10','[{"weekday":0,"startMinute":60,"endMinute":240}]',30)$q$,$q$values ('2024-03-10 06:00Z'::timestamptz,'2024-03-10 06:30Z'::timestamptz),('2024-03-10 06:30Z'::timestamptz,'2024-03-10 07:00Z'::timestamptz),('2024-03-10 07:00Z'::timestamptz,'2024-03-10 07:30Z'::timestamptz),('2024-03-10 07:30Z'::timestamptz,'2024-03-10 08:00Z'::timestamptz)$q$,'New York gap contributes no normalized or duplicated starts; ends are elapsed');
select results_eq($q$select starts_at from app.pt_availability_grid('America/New_York','America/New_York','2024-11-03','2024-11-03','[{"weekday":0,"startMinute":60,"endMinute":180}]',30)$q$,$q$values ('2024-11-03 05:00Z'::timestamptz),('2024-11-03 05:30Z'::timestamptz),('2024-11-03 06:00Z'::timestamptz),('2024-11-03 06:30Z'::timestamptz),('2024-11-03 07:00Z'::timestamptz),('2024-11-03 07:30Z'::timestamptz)$q$,'New York repeated hour exposes both distinct absolute occurrences in order');
select results_eq($q$select starts_at from app.pt_availability_grid('Australia/Lord_Howe','Australia/Lord_Howe','2024-10-06','2024-10-06','[{"weekday":0,"startMinute":90,"endMinute":210}]',15)$q$,$q$values ('2024-10-05 15:00Z'::timestamptz),('2024-10-05 15:15Z'::timestamptz),('2024-10-05 15:30Z'::timestamptz),('2024-10-05 15:45Z'::timestamptz),('2024-10-05 16:00Z'::timestamptz),('2024-10-05 16:15Z'::timestamptz)$q$,'Lord Howe half-hour spring gap omits exactly its nonexistent quarter-hours');
select results_eq($q$select starts_at from app.pt_availability_grid('Australia/Lord_Howe','Australia/Lord_Howe','2024-04-07','2024-04-07','[{"weekday":0,"startMinute":90,"endMinute":150}]',15)$q$,$q$values ('2024-04-06 14:30Z'::timestamptz),('2024-04-06 14:45Z'::timestamptz),('2024-04-06 15:00Z'::timestamptz),('2024-04-06 15:15Z'::timestamptz),('2024-04-06 15:30Z'::timestamptz),('2024-04-06 15:45Z'::timestamptz)$q$,'Lord Howe half-hour fall repeat is complete and distinct');
select results_eq($q$select starts_at from app.pt_availability_grid('Pacific/Kiritimati','Pacific/Honolulu','2024-01-02','2024-01-02','[{"weekday":1,"startMinute":600,"endMinute":720}]',60)$q$,$q$values ('2024-01-01 20:00Z'::timestamptz),('2024-01-01 21:00Z'::timestamptz)$q$,'gym Tuesday includes trainer Monday across the date line');
select results_eq($q$select starts_at from app.pt_availability_grid('Pacific/Honolulu','Pacific/Kiritimati','2024-01-01','2024-01-01','[{"weekday":2,"startMinute":600,"endMinute":720}]',60)$q$,$q$values ('2024-01-01 20:00Z'::timestamptz),('2024-01-01 21:00Z'::timestamptz)$q$,'gym Monday includes trainer Tuesday across the date line');
select results_eq($q$select starts_at from app.pt_availability_grid('UTC','UTC','2024-01-01','2024-01-01','[{"weekday":1,"startMinute":1420,"endMinute":1440}]',15)$q$,$q$values ('2024-01-01 23:40Z'::timestamptz)$q$,'grid is anchored to window start, not midnight, and requires whole duration');
select is_empty($q$select * from app.pt_availability_grid('UTC','UTC','2024-01-01','2024-01-14','[]',60)$q$,'empty windows accepted at inclusive 14-day boundary');
select is((select count(*)::integer from app.pt_availability_grid('UTC','UTC','2024-01-01','2024-01-14',(select jsonb_agg(jsonb_build_object('weekday',n,'startMinute',0,'endMinute',1440)) from generate_series(0,6)n),15)),1344,'helper never applies public reader 400-row truncation');
select results_eq($q$select starts_at from app.pt_availability_grid('UTC','UTC','2024-01-01','2024-01-01','[{"weekday":1,"startMinute":60,"endMinute":120},{"weekday":1,"startMinute":120,"endMinute":180}]',60)$q$,$q$values ('2024-01-01 01:00Z'::timestamptz),('2024-01-01 02:00Z'::timestamptz)$q$,'touching windows allowed without duplicate boundary candidate');
-- Validation matrix: no coercion and no silently dropped malformed windows.
select throws_ok(format('select * from app.pt_availability_grid(%L,%L,%L::date,%L::date,%L::jsonb,%s)',gym,trainer,'2024-01-01','2024-01-01',windows,minutes),'22023',null,label)
from (values
('No/Such_Zone','UTC','[]','60','unknown gym timezone'),
('UTC','No/Such_Zone','[]','60','unknown trainer timezone'),
(null,'UTC','[]','60','null gym timezone'),
('UTC',null,'[]','60','null trainer timezone'),
('UTC','UTC',null,'60','null windows'),
('UTC','UTC','{}','60','object instead of window array'),
('UTC','UTC','[null]','60','null element'),
('UTC','UTC','[1]','60','numeric element'),
('UTC','UTC','[{"weekday":1,"startMinute":"60","endMinute":120}]','60','numeric string'),
('UTC','UTC','[{"weekday":1,"startMinute":true,"endMinute":120}]','60','boolean minute'),
('UTC','UTC','[{"weekday":1,"startMinute":60.5,"endMinute":120}]','60','fractional minute'),
('UTC','UTC','[{"weekday":1,"startMinute":60,"endMinute":120,"extra":0}]','60','unknown key'),
('UTC','UTC','[{"weekday":1,"start_minute":60,"end_minute":120}]','60','snake-case aliases'),
('UTC','UTC','[{"weekday":1,"startMinute":60}]','60','missing end'),
('UTC','UTC','[{"weekday":7,"startMinute":60,"endMinute":120}]','60','weekday outside range'),
('UTC','UTC','[{"weekday":1,"startMinute":-1,"endMinute":120}]','60','negative start'),
('UTC','UTC','[{"weekday":1,"startMinute":60,"endMinute":1441}]','60','end after midnight boundary'),
('UTC','UTC','[{"weekday":1,"startMinute":60,"endMinute":60}]','60','empty window'),
('UTC','UTC','[{"weekday":1,"startMinute":60,"endMinute":180},{"weekday":1,"startMinute":120,"endMinute":240}]','60','overlapping windows'),
('UTC','UTC','[]','14','below minimum duration'),
('UTC','UTC','[]','181','above maximum duration'),
('UTC','UTC','[]','16','duration not divisible by five'),
('UTC','UTC','[]','NULL','null duration'))v(gym,trainer,windows,minutes,label);
select throws_ok($q$select * from app.pt_availability_grid('UTC','UTC','2024-01-01','2024-01-01',(select jsonb_agg(jsonb_build_object('weekday',0,'startMinute',n*20,'endMinute',n*20+15)) from generate_series(0,28)n),15)$q$,'22023',null,'29 individually nonoverlapping windows refused');
select is(pg_temp.err(format('select * from app.pt_availability_grid(''UTC'',''UTC'',%L::date,%L::date,''[]'',60)',f,t)),'22023:range_invalid',label)
from (values(null,'2024-01-01','null first day'),('2024-01-01',null,'null last day'),('2024-01-02','2024-01-01','inverted range'),('2024-01-01','2024-01-15','15 inclusive days'),('-infinity','2024-01-01','negative infinity'),('2024-01-01','infinity','positive infinity'))v(f,t,label);
select lives_ok($q$select * from app.pt_availability_grid('UTC','UTC','2500-01-01','2500-01-01','[]',180)$q$,'finite far-future date is not rejected by arbitrary calendar-year bound');
select throws_ok($q$select * from app.pt_availability_grid('UTC','UTC','5874897-12-31','5874897-12-31',(select jsonb_agg(jsonb_build_object('weekday',n,'startMinute',0,'endMinute',1440)) from generate_series(0,6)n),60)$q$,'22023',null,'unsupported finite date arithmetic refuses explicitly rather than overflowing');
-- Real actor setup uses permitted visible-domain fixtures. No guard replacement.
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
(pg_temp.gid(1),'Grid repair visible','GR202A','active','Pacific/Kiritimati','INR'),
(pg_temp.gid(2),'Grid repair foreign','GR202B','active','UTC','INR');
insert into public.organization_settings(tenant_id) values(pg_temp.gid(1)),(pg_temp.gid(2));
insert into public.branches(id,tenant_id,name,is_default,timezone) values
(pg_temp.gid(11),pg_temp.gid(1),'Date-line trainer',true,'Pacific/Honolulu'),(pg_temp.gid(12),pg_temp.gid(2),'Foreign',true,'UTC');
insert into auth.users(id) values(pg_temp.gid(901)),(pg_temp.gid(902)),(pg_temp.gid(903));
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active,qualification) values
(pg_temp.gid(21),pg_temp.gid(1),pg_temp.gid(901),pg_temp.gid(11),'gym_owner','Owner',true,null),
(pg_temp.gid(24),pg_temp.gid(1),pg_temp.gid(902),pg_temp.gid(11),'trainer','Live Trainer',true,'Credential'),
(pg_temp.gid(25),pg_temp.gid(1),null,pg_temp.gid(11),'trainer','Inactive Trainer',true,'Credential'),
(pg_temp.gid(26),pg_temp.gid(2),null,pg_temp.gid(12),'trainer','Foreign Trainer',true,'Credential');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status) values
(pg_temp.gid(31),pg_temp.gid(1),pg_temp.gid(903),pg_temp.gid(11),'Own Member','+912020000031','active'),
(pg_temp.gid(32),pg_temp.gid(1),null,pg_temp.gid(11),'Other Member','+912020000032','active');
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.gid(41),pg_temp.gid(1),'Live membership',120,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) values
(pg_temp.gid(51),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(41),'active',app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60,10000);
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,session_count,trainer_staff_id,trainer_qualification,cancellation_terms,is_active) values
(pg_temp.gid(101),pg_temp.gid(1),'pt_package','Grid programme','Disclosed',0,'INR',60,8,pg_temp.gid(24),'Credential','Terms',true);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on) values
(pg_temp.gid(201),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(202),pg_temp.gid(1),pg_temp.gid(32),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(203),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'completed',1,0,0,'INR',pg_temp.gid(24),8,8,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60);
update public.staff set is_active=false where id=pg_temp.gid(25);
insert into public.trainer_availability(tenant_id,staff_id,weekday,start_minute,end_minute) select pg_temp.gid(1),pg_temp.gid(24),n,0,1440 from generate_series(0,6)n;
create temp table requested_days as select app.gym_today(pg_temp.gid(1))+2 as d;
create temp table expected_live as select g.starts_at,g.ends_at,'Pacific/Honolulu'::text as timezone from requested_days d cross join lateral app.pt_availability_grid('Pacific/Kiritimati','Pacific/Honolulu',d.d,d.d,(select jsonb_agg(jsonb_build_object('weekday',weekday,'startMinute',start_minute,'endMinute',end_minute)) from public.trainer_availability where staff_id=pg_temp.gid(24)),60)g where app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),g.starts_at)='open';
create temp table actual_live(starts_at timestamptz,ends_at timestamptz,timezone text);
grant select on requested_days,expected_live to authenticated;
grant select,insert,delete on actual_live to authenticated;
select is((select count(*)::integer from expected_live),24,'live fixture has 24 offered starts wholly inside requested gym day');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
insert into actual_live select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days));
select results_eq($q$select * from actual_live$q$,$q$select * from expected_live order by starts_at$q$,'real own-member reader consumes same current grid and slot predicate across different local dates');
select is_empty($q$select * from actual_live where (starts_at at time zone 'Pacific/Kiritimati')::date<>(select d from requested_days)$q$,'every public start belongs to requested gym date');
select is((select count(*)::integer from actual_live where (starts_at at time zone 'Pacific/Honolulu')::date=(select d-1 from requested_days)),24,'public reader includes trainer previous-day windows');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(202),(select d from requested_days),(select d from requested_days))$q$,'other member pack stays invisible');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(999),(select d from requested_days),(select d from requested_days))$q$,'unknown pack same invisible result');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(203),(select d from requested_days),(select d from requested_days))$q$,'can_book false completed pack returns no offers');
select is(pg_temp.err($q$select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d+14 from requested_days))$q$),'22023:range_invalid','reader range refusal preserved');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- Live filtering: removed time off restores rows, active time off removes them.
insert into public.trainer_time_off(id,tenant_id,staff_id,starts_on,ends_on,created_by_staff_id) select pg_temp.gid(301),pg_temp.gid(1),pg_temp.gid(24),d-1,d-1,pg_temp.gid(21) from requested_days;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days))$q$,'reader applies live trainer-day time off after enumeration');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.trainer_time_off set removed_at=statement_timestamp(),removed_by_staff_id=pg_temp.gid(21) where id=pg_temp.gid(301);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days))),24,'reader restores current offers after soft removal');
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(901),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.gid(1),'staff_id',pg_temp.gid(21))::text,true);
create temp table refusal_before as select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id=pg_temp.gid(1)),'sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.pt_sessions s where tenant_id=pg_temp.gid(1)),'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id=pg_temp.gid(1)),'notices',(select jsonb_agg(to_jsonb(n) order by id) from public.notifications n where tenant_id=pg_temp.gid(1))) v;
set local role authenticated;
select is(pg_temp.err(format('select * from public.reassign_pt_packs(%L::uuid,%L::uuid,array[%L::uuid],''Valid reason'')',pg_temp.gid(n),pg_temp.gid(n),pg_temp.gid(201))),'GL055:trainer_unavailable',label)
from (values(999,'missing equal target eligibility precedes same trainer'),(26,'foreign equal target eligibility precedes same trainer'),(25,'inactive equal target eligibility precedes same trainer'),(21,'nontrainer equal target eligibility precedes same trainer'))v(n,label);
select is(pg_temp.err($q$select * from public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(24),array[pg_temp.gid(201)],'Valid reason')$q$),'22023:same_trainer','eligible equal target reaches same-trainer refusal');
select is(pg_temp.err($q$select * from public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(25),array[pg_temp.gid(201)],'Valid reason')$q$),'GL055:trainer_unavailable','different inactive target refuses too');
set local role postgres;
select results_eq($q$select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id=pg_temp.gid(1)),'sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.pt_sessions s where tenant_id=pg_temp.gid(1)),'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id=pg_temp.gid(1)),'notices',(select jsonb_agg(to_jsonb(n) order by id) from public.notifications n where tenant_id=pg_temp.gid(1)))$q$,$q$select v from refusal_before$q$,'all target/equality refusals preserve every order, session, audit and notice');
-- Sold upper validity clamps a live pack without extending its terms.
select set_config('request.jwt.claims','',true);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on)
select pg_temp.gid(204),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-2,d from requested_days;
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on) values
(pg_temp.gid(205),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,null,null),
(pg_temp.gid(206),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-10,app.gym_today(pg_temp.gid(1))-1);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
select ok(exists(select 1 from public.read_member_pt_slots(pg_temp.gid(204),(select d from requested_days),(select d+1 from requested_days))),'live pack still offers eligible starts on original expiry day');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(204),(select d from requested_days),(select d+1 from requested_days)) where starts_at<((select d-4 from requested_days)::timestamp at time zone 'Pacific/Kiritimati') or ends_at>((select d+1 from requested_days)::timestamp at time zone 'Pacific/Kiritimati') or (starts_at at time zone 'Pacific/Kiritimati')::date>(select d from requested_days)$q$,'whole returned slot stays inside sold start and expiry boundaries');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(205),(select d from requested_days),(select d from requested_days))$q$,'null validity never fabricates eligible pack slots');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(206),(select d from requested_days),(select d from requested_days))$q$,'expired active pack remains unbookable');
set local role postgres;
-- A real booking establishes taken filtering without overriding slot state/guards.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
select lives_ok($q$select * from public.book_pt_session(pg_temp.gid(201),pg_temp.gid(401),(select min(starts_at) from actual_live))$q$,'returned live own-pack slot can be booked under inherited current-day guard');
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days))),23,'reader removes real taken slot using current slot predicate');
select is_empty($q$select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days)) where starts_at=(select min(starts_at) from actual_live)$q$,'booked absolute start absent from subsequent offers');
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into public.staff(id,tenant_id,branch_id,role,full_name,is_active,qualification) values(pg_temp.gid(27),pg_temp.gid(1),pg_temp.gid(11),'trainer','Eligible target',true,'Credential');
create temp table atomic_before as select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id=pg_temp.gid(1)),'sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.pt_sessions s where tenant_id=pg_temp.gid(1)),'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id=pg_temp.gid(1)),'notices',(select jsonb_agg(to_jsonb(n) order by id) from public.notifications n where tenant_id=pg_temp.gid(1))) v;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(901),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.gid(1),'staff_id',pg_temp.gid(21))::text,true);
set local role authenticated;
select throws_ok($q$select * from public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(27),array[pg_temp.gid(201),pg_temp.gid(203)],'Valid reason')$q$,'GL055',null,'mixed active/completed batch refuses rather than reassigning first pack');
set local role postgres;
select results_eq($q$select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id=pg_temp.gid(1)),'sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.pt_sessions s where tenant_id=pg_temp.gid(1)),'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id=pg_temp.gid(1)),'notices',(select jsonb_agg(to_jsonb(n) order by id) from public.notifications n where tenant_id=pg_temp.gid(1)))$q$,$q$select v from atomic_before$q$,'atomic batch refusal preserves scheduled booking, sold terms and every side effect');
set local role authenticated;
select lives_ok($q$select public.set_pt_policy(24,true,15)$q$,'owner changes duration through authorized policy command');
set local role postgres;
create temp table expected_capped as select g.starts_at,g.ends_at,'Pacific/Honolulu'::text timezone from requested_days d cross join lateral app.pt_availability_grid('Pacific/Kiritimati','Pacific/Honolulu',d.d,d.d+13,(select jsonb_agg(jsonb_build_object('weekday',weekday,'startMinute',start_minute,'endMinute',end_minute)) from public.trainer_availability where staff_id=pg_temp.gid(24)),15)g where app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),g.starts_at)='open' order by g.starts_at limit 400;
grant select on expected_capped to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.gid(903),'role','authenticated','app_role','member','tenant_id',pg_temp.gid(1),'member_id',pg_temp.gid(31))::text,true);
set local role authenticated;
select results_eq($q$select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d+13 from requested_days))$q$,$q$select * from expected_capped order by starts_at$q$,'public 400 cap follows current taken filtering and absolute ordering');
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d+13 from requested_days))),400,'public cap remains exactly 400 on abundant live offers');
select set_config('request.jwt.claims','{}',true);
select throws_ok($q$select * from public.read_member_pt_slots(pg_temp.gid(201),(select d from requested_days),(select d from requested_days))$q$,'42501',null,'reader still rejects incomplete identity before returning offers');
set local role postgres;
select * from finish();
rollback;





