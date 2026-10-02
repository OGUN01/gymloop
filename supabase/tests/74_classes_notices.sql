-- CLS focused visible notices, independently authored from frozen CLS-010/011/027.
-- Self-contained fixture; no implementation or holdout read. Committed 083000 is mandatory.
-- No local 55P04 exemption; every fixture and fault-injection trigger rolls back.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(42);

create function pg_temp.u(n integer) returns uuid language sql immutable as
$$ select ('74000000-0000-4000-8000-' || lpad(to_hex(n),12,'0'))::uuid $$;
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

select enum_has_labels('public','message_category',array['renewal','payment','fulfilment','promotion','motivation','class_update','announcement']::name[],'Prelude: committed notice categories in exact order');
-- Established infrastructure fixtures; everything is rolled back and prefix-scoped.
insert into auth.users(id,email) select pg_temp.u(n+900),'cls74-'||n||'@example.test'
from generate_series(21,29) n union all
select pg_temp.u(n+900),'cls74-'||n||'@example.test' from generate_series(101,110) n;
insert into public.organizations(id,name,gym_code,status,timezone) values
 (pg_temp.u(1),'CLS A','CLS74A','active','Asia/Kolkata'),
 (pg_temp.u(2),'CLS B','CLS74B','active','Pacific/Kiritimati');
insert into public.branches(id,tenant_id,name,is_default,timezone) values
 (pg_temp.u(11),pg_temp.u(1),'Main',true,'Asia/Kolkata'),
 (pg_temp.u(12),pg_temp.u(1),'West',false,'Etc/GMT+12'),
 (pg_temp.u(13),pg_temp.u(2),'East',true,'Pacific/Kiritimati');
insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
 (pg_temp.u(21),pg_temp.u(1),pg_temp.u(11),pg_temp.u(921),'gym_owner','Owner',true),
 (pg_temp.u(22),pg_temp.u(1),pg_temp.u(11),pg_temp.u(922),'gym_manager','Manager',true),
 (pg_temp.u(23),pg_temp.u(1),pg_temp.u(11),pg_temp.u(923),'front_desk','Desk',true),
 (pg_temp.u(24),pg_temp.u(1),pg_temp.u(11),pg_temp.u(924),'trainer','Lead',true),
 (pg_temp.u(25),pg_temp.u(1),pg_temp.u(11),pg_temp.u(925),'trainer','Other Lead',true),
 (pg_temp.u(26),pg_temp.u(1),pg_temp.u(11),pg_temp.u(926),'front_desk','Inactive',false),
 (pg_temp.u(27),pg_temp.u(2),pg_temp.u(13),pg_temp.u(927),'gym_owner','B Owner',true);
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 (pg_temp.u(928),'super_admin','Root','root74@example.test',true),
 (pg_temp.u(929),'platform_support','Support','support74@example.test',true);
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
insert into pg_temp.saved select 'attendance_before',coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') from public.attendance a where tenant_id in(pg_temp.u(1),pg_temp.u(2));
insert into pg_temp.saved select 'noshow_before',coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') from public.no_show_cases a where tenant_id in(pg_temp.u(1),pg_temp.u(2));

insert into public.services(id,tenant_id,name,default_duration_minutes,default_capacity) values(pg_temp.u(200),pg_temp.u(1),'Zumba',60,2);
insert into pg_temp.saved values('service',jsonb_build_object('id',pg_temp.u(200)));
-- Explicitly withdrawn service and marketing consent never gates transactional in-app notices.
insert into public.consents(tenant_id,member_id,purpose,granted,version,source) select pg_temp.u(1),pg_temp.u(n),purpose,false,'CLS74-visible','visible-fixture' from unnest(array[101,107])n cross join unnest(array['service'::public.consent_purpose,'marketing'::public.consent_purpose])purpose;
-- Cancellation transaction, direct sent notices, ineligible withholding, no-app count.
set local role postgres;
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,trainer_staff_id)
 values(pg_temp.u(901),pg_temp.u(1),pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp() at time zone 'Asia/Kolkata')::date+4,((statement_timestamp() at time zone 'Asia/Kolkata')::date+4+time '18:00') at time zone 'Asia/Kolkata',((statement_timestamp() at time zone 'Asia/Kolkata')::date+4+time '19:00') at time zone 'Asia/Kolkata',7,pg_temp.u(24));
insert into public.class_bookings(id,tenant_id,session_id,member_id) select pg_temp.u(n+10000),pg_temp.u(1),pg_temp.u(901),pg_temp.u(n) from unnest(array[101,107,108,105,109]) n;
insert into public.class_bookings(tenant_id,session_id,member_id,status,marked_at) values(pg_temp.u(1),pg_temp.u(901),pg_temp.u(102),'attended',statement_timestamp()),(pg_temp.u(1),pg_temp.u(901),pg_temp.u(104),'no_show',statement_timestamp());
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.capture('cancelresult',$$select * from public.cancel_class_session(pg_temp.u(901),'  Instructor unwell  ')$$),'OK','CLS-010: cancel session transaction');
select is((select v from pg_temp.saved where k='cancelresult'),jsonb_build_object('bookings_cancelled',5,'notices_written',2,'notices_withheld',3,'members_without_app',1),'CLS-010/011: exact cancellation and notice counts');
select is(pg_temp.run($$select public.cancel_class_session(pg_temp.u(901),'Instructor unwell')$$),'GL111','CLS-010: repeat cancellation refuses rather than repeats notices');
set local role postgres;
select is((select count(*)::integer from public.class_bookings where session_id=pg_temp.u(901) and status='session_cancelled' and cancelled_at is not null),5,'CLS-010: booked rows move to terminal session_cancelled');
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(901) and category='class_update' and channel='in_app' and status='sent'),2,'CLS-011: direct same-transaction sent notices without service consent');
select ok(not exists(select 1 from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(901) and member_id in(pg_temp.u(108),pg_temp.u(105),pg_temp.u(109))),'CLS-011: blocked, erased and cancelled account notices withheld');
select ok(exists(select 1 from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(901) and member_id=pg_temp.u(107)),'CLS-011: no-app member still receives notice row');
select ok(not exists(select 1 from public.notifications n join public.class_sessions s on s.id=n.related_id where n.tenant_id=pg_temp.u(1) and n.related_id=pg_temp.u(901) and (n.template_key<>'class_session_cancelled' or n.related_type<>'class_session' or n.dedupe_key<>'class-cancelled:'||s.id||':'||n.member_id or n.payload-'kind'<>jsonb_build_object('body','Zumba on '||to_char(s.starts_at at time zone 'Asia/Kolkata','FMDD Mon YYYY "at" FMHH12:MI am')||' has been cancelled. Reason: Instructor unwell','sessionId',s.id,'reason','Instructor unwell') or not(n.payload?'kind'))),'CLS-011: exact dedupe/template/local body/payload; kind key required, value unspecified by contract');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and record_id=pg_temp.u(901) and action='class_session.cancelled' and before=jsonb_build_object('status','scheduled') and after=jsonb_build_object('status','cancelled','bookings_cancelled',5,'notices_written',2,'notices_withheld',3) and reason='Instructor unwell' and actor_role='gym_owner' and actor_user_id=pg_temp.u(921)),'CLS-027: exact session cancel audit');
select is((select count(*)::integer from public.class_bookings where session_id=pg_temp.u(901) and status in('attended','no_show') and marked_at is not null),2,'CLS-010: cancellation preserves attended and no-show evidence');
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(901) and member_id in(pg_temp.u(102),pg_temp.u(104))),0,'CLS-011: marked attendees and no-shows receive no cancellation notice');
select is(pg_temp.run($$update public.class_sessions set status='scheduled',cancelled_at=null,cancel_reason=null,cancelled_by_staff_id=null where id=pg_temp.u(901)$$),'GL111','CLS-010: no resurrection under postgres');

-- Failure while writing a notice must roll the whole cancellation back.
set local role postgres;
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity)
 values(pg_temp.u(902),pg_temp.u(1),pg_temp.id('service','id'),pg_temp.u(11),current_date+5,statement_timestamp()+interval '5 days',statement_timestamp()+interval '5 days 1 hour',2);
insert into public.class_bookings(id,tenant_id,session_id,member_id) values(pg_temp.u(19002),pg_temp.u(1),pg_temp.u(902),pg_temp.u(101));
create function pg_temp.notice_fault() returns trigger language plpgsql as $$begin
 if new.related_id=pg_temp.u(902) then raise exception 'visible notice write fault' using errcode='Z7402'; end if;
 return new; end $$;
create trigger cls74_notice_fault before insert on public.notifications for each row execute function pg_temp.notice_fault();
select pg_temp.claim(21);
set local role authenticated;
select is(pg_temp.run($$select public.cancel_class_session(pg_temp.u(902),'Instructor unwell')$$),'Z7402','CLS-010: notice storage failure propagated');
set local role postgres;
drop trigger cls74_notice_fault on public.notifications;
select is((select status::text from public.class_sessions where id=pg_temp.u(902)),'scheduled','CLS-010: notice failure restores session state');
select is((select status::text from public.class_bookings where id=pg_temp.u(19002)),'booked','CLS-010: notice failure restores booking state');
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(902)),0,'CLS-010: notice failure leaves no notification');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.u(1) and action='class_session.cancelled' and record_id=pg_temp.u(902)),0,'CLS-010: notice failure leaves no cancel audit');
insert into public.notifications(tenant_id,member_id,channel,category,template_key,related_type,related_id,dedupe_key,payload)
 values(pg_temp.u(1),pg_temp.u(101),'in_app','class_update','class_session_cancelled','class_session',pg_temp.u(902),'class-cancelled:'||pg_temp.u(902)||':'||pg_temp.u(101),jsonb_build_object('body','Already written','kind','cancelled','sessionId',pg_temp.u(902),'reason','Instructor unwell'));
update public.notifications set status='sent' where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(902);
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.capture('dedupcancel',$$select * from public.cancel_class_session(pg_temp.u(902),'Instructor unwell')$$),'OK','CLS-011: pre-existing dedupe notice allows cancellation');
select is((select(v->>'notices_written')::integer from pg_temp.saved where k='dedupcancel'),1,'CLS-011: duplicate counted as written');
set local role postgres;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(902)),1,'CLS-011: dedupe leaves exactly one row');

set local role postgres;
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,trainer_staff_id)
 values(pg_temp.u(903),pg_temp.u(1),pg_temp.id('service','id'),pg_temp.u(11),(statement_timestamp()+interval '6 days' at time zone 'Asia/Kolkata')::date,statement_timestamp()+interval '6 days',statement_timestamp()+interval '6 days 1 hour',2,pg_temp.u(24));
insert into public.class_bookings(tenant_id,session_id,member_id) select pg_temp.u(1),pg_temp.u(903),pg_temp.u(n) from unnest(array[101,102])n;
-- Trainer changes notify held booked members, a real no-op writes nothing.
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select public.update_class_session(pg_temp.u(903),(select session_date from public.class_sessions where id=pg_temp.u(903)),(select(starts_at at time zone 'Asia/Kolkata')::time from public.class_sessions where id=pg_temp.u(903)),60,1,pg_temp.u(25))$$),'OK','CLS-009/011: trainer change keeps seats and notifies');
set local role postgres;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(903) and template_key='class_trainer_changed' and category='class_update' and channel='in_app' and status='sent'),2,'CLS-011: two booked recipients get sent trainer-change notices');
select ok(not exists(select 1 from public.notifications n join public.class_sessions s on s.id=n.related_id where n.tenant_id=pg_temp.u(1) and n.related_id=pg_temp.u(903) and (n.payload->>'trainerName' is distinct from 'Other Lead' or n.payload->>'body' is distinct from 'Zumba on '||to_char(s.starts_at at time zone 'Asia/Kolkata','FMDD Mon YYYY "at" FMHH12:MI am')||' will now be led by Other Lead' or n.dedupe_key is null or n.dedupe_key not like 'class-trainer:'||s.id||':'||n.member_id||':'||pg_temp.u(25)||':%' or n.payload->>'sessionId' is distinct from s.id::text)),'CLS-011: trainer notice text, recipient, new trainer and command epoch key');
insert into pg_temp.saved select 'trainernotices',to_jsonb(count(*)) from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(903);
select ok(not exists(select 1 from public.notifications n where n.tenant_id=pg_temp.u(1) and n.related_id=pg_temp.u(903) and n.dedupe_key is distinct from 'class-trainer:'||n.related_id||':'||n.member_id||':'||pg_temp.u(25)||':'||(extract(epoch from n.scheduled_for)*1000000)::bigint::text),'CLS-011: trainer dedupe suffix is exact microseconds of the stored command clock');
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select public.update_class_session(pg_temp.u(903),(select session_date from public.class_sessions where id=pg_temp.u(903)),(select(starts_at at time zone 'Asia/Kolkata')::time from public.class_sessions where id=pg_temp.u(903)),60,1,pg_temp.u(25))$$),'OK','CLS-009: identical session edit accepted');
set local role postgres;
select is((select to_jsonb(count(*)) from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.u(903)),(select v from pg_temp.saved where k='trainernotices'),'CLS-009: identical trainer edit writes no notice');
set local role postgres;
-- Rule propagation is a second notice source; each real trainer change gets a new key.
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.capture('noticerule',$$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(11),array[extract(dow from (statement_timestamp() at time zone 'Asia/Kolkata')::date+1)::smallint],time '17:00',60,2,pg_temp.u(24),(statement_timestamp() at time zone 'Asia/Kolkata')::date+1,null)$$),'OK','CLS-011: independent rule-notice fixture');
set local role postgres;
insert into pg_temp.saved select 'noticeocc',jsonb_build_object('id',id) from public.class_sessions where rule_id=pg_temp.id('noticerule','rule_id') order by starts_at limit 1;
insert into public.class_bookings(tenant_id,session_id,member_id) select pg_temp.u(1),pg_temp.id('noticeocc','id'),pg_temp.u(n) from unnest(array[101,102])n;
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select public.update_class_rule(pg_temp.id('noticerule','rule_id'),60,2,pg_temp.u(25),null,true)$$),'OK','CLS-011: rule trainer change notifies booked occurrence');
set local role postgres;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.id('noticeocc','id') and template_key='class_trainer_changed' and status='sent'),2,'CLS-011: propagated trainer sends two transactional rows');
select ok(not exists(select 1 from public.notifications n join public.class_sessions s on s.id=n.related_id where n.tenant_id=pg_temp.u(1) and s.rule_id=pg_temp.id('noticerule','rule_id') and n.related_id<>pg_temp.id('noticeocc','id')),'CLS-011: unbooked generated occurrences receive no notices');
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select public.update_class_rule(pg_temp.id('noticerule','rule_id'),60,2,pg_temp.u(25),null,true)$$),'OK','CLS-011: same trainer rule edit accepted');
set local role postgres;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.id('noticeocc','id')),2,'CLS-011: same trainer emits nothing');
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select public.update_class_rule(pg_temp.id('noticerule','rule_id'),60,2,pg_temp.u(24),null,true)$$),'OK','CLS-011: returning to previous trainer remains a real change');
set local role postgres;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.id('noticeocc','id')),4,'CLS-011: another real trainer change sends another pair');
select is((select count(distinct dedupe_key)::integer from public.notifications where tenant_id=pg_temp.u(1) and related_id=pg_temp.id('noticeocc','id')),4,'CLS-011: trainer command clock/new-trainer keys remain distinct');
insert into pg_temp.saved select 'refusalnotices',to_jsonb(count(*)) from public.notifications where tenant_id=pg_temp.u(1);
select pg_temp.claim(23);
set local role authenticated;
select is(pg_temp.run($$select public.cancel_class_session(pg_temp.id('noticeocc','id'),'Instructor unwell')$$),'42501','CLS-010/011: desk cannot cancel session or send notices');
set local role postgres;
select is((select to_jsonb(count(*)) from public.notifications where tenant_id=pg_temp.u(1)),(select v from pg_temp.saved where k='refusalnotices'),'CLS-011: role refusal sends nothing');
select is((select status::text from public.class_sessions where id=pg_temp.id('noticeocc','id')),'scheduled','CLS-010: role refusal preserves session');
select ok(not exists(select 1 from public.notifications where tenant_id=pg_temp.u(1) and category='class_update' and (not(payload?'kind') or jsonb_typeof(payload->'kind')<>'string')),'CLS-011: kind is a present string without inventing its vocabulary');
select is((select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') from public.attendance a where tenant_id in(pg_temp.u(1),pg_temp.u(2))),(select v from pg_temp.saved where k='attendance_before'),'CLS-019: notice and cancellation commands leave attendance unchanged');
select is((select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') from public.no_show_cases a where tenant_id in(pg_temp.u(1),pg_temp.u(2))),(select v from pg_temp.saved where k='noshow_before'),'CLS-019: notice and cancellation commands leave no-show facts unchanged');
select * from finish();
rollback;
