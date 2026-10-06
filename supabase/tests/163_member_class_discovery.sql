-- NAVC-004/005/013/014/015 visible suite, authored from the frozen contract.
-- No feature implementation, proposed migration, or holdout suite was read.
-- Historical backfill qualification requires pre-migration deployment evidence;
-- this post-migration suite proves default Off and that later changes never infer On.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(115);

-- Reuse the established visible CLS fixture harness with a separate UUID prefix.
create function pg_temp.u(n integer) returns uuid language sql immutable as
$$ select ('16300000-0000-4000-8000-' || lpad(to_hex(n),12,'0'))::uuid $$;
create function pg_temp.claim(who integer, gym integer default 1, extra jsonb default '{}'::jsonb)
returns void language plpgsql as $$
declare r text; j jsonb;
begin
  r := case who when 21 then 'gym_owner' when 22 then 'gym_manager'
    when 23 then 'front_desk' when 24 then 'trainer' when 25 then 'gym_owner'
    when 26 then 'gym_manager' when 27 then 'gym_owner'
    when 28 then 'super_admin' when 29 then 'platform_support' else 'member' end;
  j := jsonb_build_object('sub',pg_temp.u(who+900),'role','authenticated',
    'app_role',r,'tenant_id',pg_temp.u(gym));
  if who between 21 and 27 then j := j || jsonb_build_object('staff_id',pg_temp.u(who));
  elsif who >= 101 then j := j || jsonb_build_object('member_id',pg_temp.u(who)); end if;
  perform set_config('request.jwt.claims',(j || extra)::text,true);
end $$;
create function pg_temp.run(q text) returns text language plpgsql as $$
begin execute q; return 'OK'; exception when others then return sqlstate; end $$;
create table pg_temp.saved(k text primary key, v jsonb);
grant all on pg_temp.saved to authenticated;
create function pg_temp.capture(p_key text,p_query text) returns text language plpgsql as $$
declare v_result jsonb;
begin
  execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from (' || p_query || ') x' into v_result;
  insert into pg_temp.saved values(p_key,v_result) on conflict(k) do update set v=excluded.v;
  return 'OK'; exception when others then return sqlstate;
end $$;
create function pg_temp.val(p_key text) returns jsonb language sql stable as
$$ select v from pg_temp.saved where k=p_key $$;
create function pg_temp.id(p_key text,p_field text) returns uuid language sql stable as
$$ select (v->0->>p_field)::uuid from pg_temp.saved where k=p_key $$;
create function pg_temp.class_state() returns jsonb language sql stable as $$
select jsonb_build_object(
  'services',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.services x where tenant_id=pg_temp.u(1)),
  'rules',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.class_rules x where tenant_id=pg_temp.u(1)),
  'sessions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.class_sessions x where tenant_id=pg_temp.u(1)),
  'bookings',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.class_bookings x where tenant_id=pg_temp.u(1)),
  'messages',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.notifications x where tenant_id=pg_temp.u(1)))
$$;

select has_column('public','organization_settings','member_classes_enabled','NAVC-004: saved visibility exists');
select col_type_is('public','organization_settings','member_classes_enabled','boolean','NAVC-004: boolean setting');
select col_not_null('public','organization_settings','member_classes_enabled','NAVC-004: setting never null');
select col_default_is('public','organization_settings','member_classes_enabled','false','NAVC-015: default Off');
select has_function('public','read_member_class_visibility',array[]::text[],'NAVC-004: no tenant argument in visibility read');
select has_function('public','set_member_classes_enabled',array['boolean'],'NAVC-004: boolean-only command');
select has_function('public','read_member_upcoming_class_bookings',array[]::text[],'NAVC-013: no member, tenant or date argument');
select is((select count(*)::integer from pg_proc where pronamespace='public'::regnamespace and proname in('read_member_class_visibility','set_member_classes_enabled','read_member_upcoming_class_bookings')),3,'NAVC-004/013: no overloaded caller-scope entry point');
select ok((select bool_and(prosecdef and proowner='postgres'::regrole and proconfig @> array['search_path=""']) from pg_proc where oid in(to_regprocedure('public.read_member_class_visibility()'),to_regprocedure('public.set_member_classes_enabled(boolean)'),to_regprocedure('public.read_member_upcoming_class_bookings()'))),'NAVC-004/013: postgres-owned definers with empty search path');
select ok((select bool_and(has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('anon',oid,'EXECUTE') and not has_function_privilege('service_role',oid,'EXECUTE')) from pg_proc where oid in(to_regprocedure('public.read_member_class_visibility()'),to_regprocedure('public.set_member_classes_enabled(boolean)'),to_regprocedure('public.read_member_upcoming_class_bookings()'))),'NAVC-004/013: execution limited to authenticated audience');
select is((select proargnames from pg_proc where oid=to_regprocedure('public.read_member_class_visibility()')),array['enabled']::text[],'NAVC-004: visibility exposes only enabled');
select is((select proallargtypes from pg_proc where oid=to_regprocedure('public.read_member_class_visibility()')),array['boolean'::regtype::oid],'NAVC-004: enabled is a real boolean');
select is((select proargnames from pg_proc where oid=to_regprocedure('public.set_member_classes_enabled(boolean)')),array['p_enabled','enabled','changed']::text[],'NAVC-004: exact command result names');
select is((select proallargtypes from pg_proc where oid=to_regprocedure('public.set_member_classes_enabled(boolean)')),array['boolean'::regtype::oid,'boolean'::regtype::oid,'boolean'::regtype::oid],'NAVC-004: exact command result types');
select is((select proargnames from pg_proc where oid=to_regprocedure('public.read_member_upcoming_class_bookings()')),(select proargnames[3:array_length(proargnames,1)] from pg_proc where oid=to_regprocedure('public.read_member_class_schedule(date,date)')),'NAVC-013: own reader preserves complete safe schedule column names');
select is((select proallargtypes from pg_proc where oid=to_regprocedure('public.read_member_upcoming_class_bookings()')),(select proallargtypes[3:array_length(proallargtypes,1)] from pg_proc where oid=to_regprocedure('public.read_member_class_schedule(date,date)')),'NAVC-013: own reader preserves complete safe schedule column types');

insert into auth.users(id,email) select pg_temp.u(n+900),'navc163-'||n||'@example.test'
from generate_series(21,29)n union all
select pg_temp.u(n+900),'navc163-'||n||'@example.test' from generate_series(101,111)n;
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 (pg_temp.u(928),'super_admin','NAVC Root','navc-root163@example.test',true),
 (pg_temp.u(929),'platform_support','NAVC Support','navc-support163@example.test',true);
-- Infrastructure fixtures follow canonical platform configuration guards.
do $fixture$ declare previous_claims text := current_setting('request.jwt.claims',true); begin
 perform pg_temp.claim(28,1,jsonb_build_object('tenant_id',null));
 insert into public.organizations(id,name,gym_code,status,timezone) values
 (pg_temp.u(1),'NAVC A','NV163A','active','Pacific/Kiritimati'),
 (pg_temp.u(2),'NAVC B','NV163B','active','Asia/Kolkata'),
 (pg_temp.u(3),'NAVC Missing','NV163C','active','Asia/Kolkata');
 insert into public.branches(id,tenant_id,name,is_default,timezone) values
 (pg_temp.u(11),pg_temp.u(1),'East home',true,'Pacific/Kiritimati'),
 (pg_temp.u(12),pg_temp.u(1),'West commitment',false,'Etc/GMT+12'),
 (pg_temp.u(15),pg_temp.u(1),'Changed home',false,'Asia/Kolkata'),
 (pg_temp.u(13),pg_temp.u(2),'Other tenant',true,'Asia/Kolkata'),
 (pg_temp.u(14),pg_temp.u(3),'Missing settings',true,'Asia/Kolkata');
 insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
 (pg_temp.u(21),pg_temp.u(1),pg_temp.u(11),pg_temp.u(921),'gym_owner','Owner',true),
 (pg_temp.u(22),pg_temp.u(1),pg_temp.u(11),pg_temp.u(922),'gym_manager','Manager',true),
 (pg_temp.u(23),pg_temp.u(1),pg_temp.u(11),pg_temp.u(923),'front_desk','Desk',true),
 (pg_temp.u(24),pg_temp.u(1),pg_temp.u(11),pg_temp.u(924),'trainer','Teacher',true),
 (pg_temp.u(25),pg_temp.u(1),pg_temp.u(11),pg_temp.u(925),'gym_owner','Revoked owner',false),
 (pg_temp.u(26),pg_temp.u(1),pg_temp.u(11),pg_temp.u(926),'gym_manager','Revoked manager',false),
 (pg_temp.u(27),pg_temp.u(2),pg_temp.u(13),pg_temp.u(927),'gym_owner','Foreign owner',true);
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
exception when others then
 perform set_config('request.jwt.claims',coalesce(previous_claims,''),true); raise;
end $fixture$;
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status,erased_at)
select pg_temp.u(n),pg_temp.u(case when n=110 then 2 when n=111 then 3 else 1 end),
 pg_temp.u(case when n=110 then 13 when n=111 then 14 else 11 end),
 case when n=105 then null else pg_temp.u(n+900) end,
 'Private NAVC member '||n,'+91630000'||lpad(n::text,4,'0'),
 case when n=103 then 'blocked'::public.member_status else 'active'::public.member_status end,
 case when n=104 then statement_timestamp() else null end
from generate_series(101,111)n;
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 (pg_temp.u(41),pg_temp.u(1),'NAVC plan',60,10000),
 (pg_temp.u(42),pg_temp.u(2),'NAVC plan',60,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
select pg_temp.u(n+1000),pg_temp.u(case when n=110 then 2 else 1 end),pg_temp.u(n),
 pg_temp.u(case when n=110 then 42 else 41 end),'active',current_date-2,current_date+60,10000
from generate_series(101,110)n;
insert into public.organization_settings(tenant_id) values(pg_temp.u(1)),(pg_temp.u(2)) on conflict do nothing;
delete from public.organization_settings where tenant_id=pg_temp.u(3);
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(1)),false,'NAVC-015: a newly created tenant starts Off');
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(2)),false,'NAVC-015: separate new tenant also starts Off');

set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.capture('owner-on',$$select * from public.set_member_classes_enabled(true)$$),'OK','NAVC-004: canonical owner enables Classes');
select is(pg_temp.val('owner-on'),'[{"enabled":true,"changed":true}]'::jsonb,'NAVC-004: exact changed owner result');
select is(pg_temp.capture('owner-retry',$$select * from public.set_member_classes_enabled(true)$$),'OK','NAVC-004: same-value retry succeeds');
select is(pg_temp.val('owner-retry'),'[{"enabled":true,"changed":false}]'::jsonb,'NAVC-004: retry explicitly unchanged');
set local role postgres;
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.class_visibility_changed'),1,'NAVC-004: one successful audit for first change and retry');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.class_visibility_changed' and record_type='organization_settings' and record_id=pg_temp.u(1) and actor_user_id=pg_temp.u(921) and actor_role='gym_owner' and before='{"member_classes_enabled":false}'::jsonb and after='{"member_classes_enabled":true}'::jsonb),'NAVC-004: exact owner audit before/after and attribution');
set local role authenticated;
select pg_temp.claim(22);
select is(pg_temp.capture('manager-off',$$select * from public.set_member_classes_enabled(false)$$),'OK','NAVC-004: canonical manager disables Classes');
select is(pg_temp.val('manager-off'),'[{"enabled":false,"changed":true}]'::jsonb,'NAVC-004: exact changed manager result');
set local role postgres;
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.class_visibility_changed' and actor_user_id=pg_temp.u(922) and actor_role='gym_manager' and before='{"member_classes_enabled":true}'::jsonb and after='{"member_classes_enabled":false}'::jsonb),'NAVC-004: manager audit is attributed to real caller');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.u(2) and action='organization.class_visibility_changed'),0,'NAVC-004: saves never audit other tenant');

set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(null)$$),'22023','NAVC-004: null is invalid, never Off');
select is(pg_temp.run($$update public.organization_settings set member_classes_enabled=true where tenant_id=pg_temp.u(1)$$),'42501','NAVC-004: canonical owner cannot bypass audited command directly');
select pg_temp.claim(22);
select is(pg_temp.run($$update public.organization_settings set member_classes_enabled=true,class_cancel_window_hours=0 where tenant_id=pg_temp.u(1)$$),'42501','NAVC-004: mixed direct update cannot bypass guard');
select is(pg_temp.run($$update public.organization_settings set class_cancel_window_hours=3,class_allow_cross_branch=true where tenant_id=pg_temp.u(1)$$),'OK','NAVC-004: existing ordinary settings update remains permitted');
select is((select class_cancel_window_hours from public.organization_settings where tenant_id=pg_temp.u(1)),3,'NAVC-004: ordinary cancellation-window change persisted');
select is((select class_allow_cross_branch from public.organization_settings where tenant_id=pg_temp.u(1)),true,'NAVC-004: ordinary cross-branch change persisted');
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(1)),false,'NAVC-004: ordinary settings update retains visibility');
select pg_temp.claim(21);
select is((select count(*)::integer from public.organization_settings where tenant_id=pg_temp.u(1)),1,'NAVC-004: staff settings read is preserved');
select pg_temp.claim(28,1,jsonb_build_object('tenant_id',null));
select is((select count(*)::integer from public.organization_settings where tenant_id in(pg_temp.u(1),pg_temp.u(2))),2,'NAVC-004: platform settings reads remain preserved');
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: platform has no mutation authority');
select pg_temp.claim(29,1,jsonb_build_object('tenant_id',null));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: platform support has no mutation authority');
select pg_temp.claim(23);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: front desk refused');
select pg_temp.claim(24);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: trainer refused');
select pg_temp.claim(25);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: revoked owner refused');
select pg_temp.claim(26);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: revoked manager refused');
select pg_temp.claim(27,1);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: foreign tenant staff claim refused');
select pg_temp.claim(21,1,jsonb_build_object('sub',pg_temp.u(922)));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: mismatched user and staff refused');
select pg_temp.claim(21,1,jsonb_build_object('staff_id',pg_temp.u(22)));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: mismatched staff identity refused');
select pg_temp.claim(21,1,jsonb_build_object('app_role','gym_manager'));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: claimed role must match canonical staff row');
select pg_temp.claim(21,1,jsonb_build_object('impersonation_session_id',pg_temp.u(999)));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: impersonation cannot mutate');
select pg_temp.claim(21,1,jsonb_build_object('staff_id',null));
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: incomplete actor refused');
select pg_temp.claim(101);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'42501','NAVC-004: member refused');
select is(pg_temp.run($$select * from public.set_member_classes_enabled(null)$$),'42501','NAVC-004: audience checked before invalid null');
set local role postgres;
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.class_visibility_changed'),2,'NAVC-004: all refused writes produce no successful change audit');
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(1)),false,'NAVC-004: refused writes leave settings unchanged');

set local role authenticated;
select pg_temp.claim(27,2);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'OK','NAVC-004: other tenant owner updates only its own setting');
select pg_temp.claim(101);
select is(pg_temp.capture('member-a',$$select * from public.read_member_class_visibility()$$),'OK','NAVC-004: canonical member reads visibility');
select is(pg_temp.val('member-a'),'[{"enabled":false}]'::jsonb,'NAVC-004: member sees only own tenant boolean');
select is((select count(*)::integer from public.organization_settings where tenant_id=pg_temp.u(1)),0,'NAVC-004: member still cannot read entire private settings row');
select pg_temp.claim(110,2);
select is(pg_temp.capture('member-b',$$select * from public.read_member_class_visibility()$$),'OK','NAVC-004: other tenant member uses own projection');
select is(pg_temp.val('member-b'),'[{"enabled":true}]'::jsonb,'NAVC-004: tenant values are isolated');
select pg_temp.claim(101,2);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: forged foreign member tenant refused');
select pg_temp.claim(101,1,jsonb_build_object('member_id',pg_temp.u(102)));
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: another member ID cannot be read under caller subject');
select pg_temp.claim(101,1,jsonb_build_object('impersonation_session_id',pg_temp.u(999)));
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: impersonated member projection refused');
select pg_temp.claim(21);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: owner cannot use member projection');
select pg_temp.claim(103);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: blocked member projection refused');
select pg_temp.claim(104);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: erased member projection refused');
select pg_temp.claim(105);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'42501','NAVC-004: unlinked member projection refused');
select pg_temp.claim(111,3);
select is(pg_temp.run($$select * from public.read_member_class_visibility()$$),'22023','NAVC-004: missing settings fail rather than manufacture Off');
set local role postgres;
delete from public.organization_settings where tenant_id=pg_temp.u(2);
set local role authenticated;
select pg_temp.claim(27,2);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(false)$$),'22023','NAVC-004: missing settings command fails');
set local role postgres;
insert into public.organization_settings(tenant_id) values(pg_temp.u(2));

-- A real booked West session while home is East. Cross-branch browsing is later
-- switched Off, and then home itself changes. Own commitments are independent.
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.capture('service',$$select public.create_service('Mixed activity',null,60,20,0) as id$$),'OK','NAVC-001: existing catalogue command reused');
select is(pg_temp.capture('rule',$$select * from public.create_class_rules(pg_temp.id('service','id'),pg_temp.u(12),array[extract(dow from (statement_timestamp() at time zone 'Etc/GMT+12')::date+4)::smallint],time '10:00',60,20,null,(statement_timestamp() at time zone 'Etc/GMT+12')::date+4,null)$$),'OK','NAVC-001: existing mixed-activity rule command reused');
select is(pg_temp.capture('session',$$select public.create_class_session(pg_temp.id('service','id'),pg_temp.u(12),((statement_timestamp()+interval '3 days') at time zone 'Etc/GMT+12')::date,time '18:00',60,20,null) as id$$),'OK','NAVC-001: existing session command reused');
select pg_temp.claim(101);
select is(pg_temp.capture('booking',$$select * from public.book_class_session(pg_temp.id('session','id'))$$),'OK','NAVC-005: Off does not change new-booking authorization');
set local role postgres;
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(1)),false,'NAVC-015: adding active service and booked session does not rerun backfill');
select set_config('request.jwt.claims','',true);
-- COM lifecycle fixtures enter scheduled/classified/deduplicated with no event
-- evidence (phase6-comms-contract.md section 4; visible 33_comms_commands.sql).
insert into public.notifications(id,tenant_id,member_id,channel,category,status,dedupe_key,scheduled_for,sent_at,delivered_at,payload)
 values(pg_temp.u(701),pg_temp.u(1),pg_temp.u(101),'in_app','class_update','scheduled','navc163-retained:'||pg_temp.u(701),statement_timestamp(),null,null,jsonb_build_object('body','A retained class message','kind','class_update'));
insert into pg_temp.saved values('class-state',pg_temp.class_state());
set local role authenticated;
select pg_temp.claim(21);
select is(pg_temp.run($$select * from public.set_member_classes_enabled(true)$$),'OK','NAVC-005: enable with a real commitment');
select is(pg_temp.run($$select * from public.set_member_classes_enabled(false)$$),'OK','NAVC-005: switch Off with a real commitment');
set local role postgres;
select is(pg_temp.class_state(),pg_temp.val('class-state'),'NAVC-005: visibility changes preserve services, rules, sessions, bookings and messages');
set local role authenticated;
select pg_temp.claim(22);
update public.organization_settings set class_allow_cross_branch=false,class_cancel_window_hours=2 where tenant_id=pg_temp.u(1);
select pg_temp.claim(101);
select is((select count(*)::integer from public.read_member_class_schedule(current_date-1,current_date+10) where session_id=pg_temp.id('session','id')),0,'NAVC-013: browsable catalogue still obeys branch restriction');
select is(pg_temp.capture('own-west',$$select * from public.read_member_upcoming_class_bookings()$$),'OK','NAVC-013: own commitment survives cross-branch restriction');
select is(pg_temp.val('own-west')->0->>'my_booking_id',pg_temp.id('booking','booking_id')::text,'NAVC-013: exact own booking retained');
select is(pg_temp.val('own-west')->0->>'my_booking_status','booked','NAVC-013: booked status retained');
select is(pg_temp.val('own-west')->0->>'availability','booked','NAVC-013: own booking never offered as an open seat');
select is(pg_temp.val('own-west')->0->>'timezone','Etc/GMT+12','NAVC-014: session retains its branch timezone');
select is((pg_temp.val('own-west')->0->>'can_cancel')::boolean,true,'NAVC-013: ordinary cancellation permission retained');
select is((pg_temp.val('own-west')->0->>'cancel_by')::timestamptz,(select starts_at-interval '2 hours' from public.read_member_upcoming_class_bookings()),'NAVC-013: current authoritative cancellation deadline');
select is(pg_temp.run($$select * from public.book_class_session(pg_temp.id('session','id'))$$),'GL094','NAVC-013: own read does not grant branch booking eligibility');
set local role postgres;
update public.members set branch_id=pg_temp.u(15) where id=pg_temp.u(101);
set local role authenticated;
select pg_temp.claim(101);
select is((select count(*)::integer from public.read_member_upcoming_class_bookings()),1,'NAVC-013: changing home branch retains own commitment');
select is(pg_temp.run($$select * from public.cancel_class_booking(pg_temp.id('booking','booking_id'))$$),'OK','NAVC-005/013: own cancellation continues while discovery is Off');
set local role postgres;
update public.members set branch_id=pg_temp.u(11) where id=pg_temp.u(101);
select set_config('request.jwt.claims','',true);

-- Absolute-time fixtures: ordered tie IDs, in-progress and western local
-- yesterday, ended, upper-exclusive horizon, three cancelled states, no booking,
-- another member and another tenant. No trigger or clock is disabled/replaced.
insert into public.services(id,tenant_id,name,default_duration_minutes,default_capacity,is_active) values
 (pg_temp.u(201),pg_temp.u(1),'Inactive Yoga',60,20,false),
 (pg_temp.u(202),pg_temp.u(2),'Foreign Dance',60,20,true),
 (pg_temp.u(203),pg_temp.u(1),'Inactive Dance',60,20,false);
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,status,cancelled_at,cancel_reason,cancelled_by_staff_id)
select pg_temp.u(n),pg_temp.u(case when n=312 then 2 else 1 end),
 pg_temp.u(case when n=312 then 202 when n=309 then 203 else 201 end),pg_temp.u(case when n=312 then 13 else 12 end),
 (t.s at time zone case when n=312 then 'Asia/Kolkata' else 'Etc/GMT+12' end)::date,
 t.s,t.e,20,case when n=307 then 'cancelled'::public.class_session_status else 'scheduled'::public.class_session_status end,
 case when n=307 then statement_timestamp() end,case when n=307 then 'Fixture cancelled session' end,
 case when n=307 then pg_temp.u(21) end
from generate_series(301,312)n cross join lateral (
 select case when n=301 then statement_timestamp()-interval '30 minutes'
             when n=302 then statement_timestamp()+interval '5 minutes'
             when n=303 then statement_timestamp()-interval '1 hour'
             when n=304 then statement_timestamp()+interval '28 days'
             when n in(308,309) then statement_timestamp()+interval '2 days'
             else statement_timestamp()+interval '1 day'+(n-305)*interval '1 hour' end s,
        case when n=301 then statement_timestamp()+interval '30 minutes'
             when n=302 then statement_timestamp()+interval '65 minutes'
             when n=303 then statement_timestamp()-interval '1 microsecond'
             when n=304 then statement_timestamp()+interval '28 days 1 hour'
             when n in(308,309) then statement_timestamp()+interval '2 days 1 hour'
             else statement_timestamp()+interval '1 day 1 hour'+(n-305)*interval '1 hour' end e) t;
insert into public.class_bookings(id,tenant_id,session_id,member_id,status,cancelled_at,cancel_reason)
select pg_temp.u(n+100),pg_temp.u(case when n=312 then 2 else 1 end),pg_temp.u(n),
 pg_temp.u(case when n=311 then 102 when n=312 then 110 else 101 end),
 case when n=305 then 'cancelled_by_member'::public.booking_status when n=306 then 'cancelled_by_gym'::public.booking_status when n=307 then 'session_cancelled'::public.booking_status else 'booked'::public.booking_status end,
 case when n in(305,306,307) then statement_timestamp() end,
 case when n=306 then 'Fixture desk cancellation' end
from generate_series(301,312)n where n<>310;
set local role authenticated;
select pg_temp.claim(101);
select is(pg_temp.capture('absolute',$$select * from public.read_member_upcoming_class_bookings()$$),'OK','NAVC-013/014: absolute own reader works for inactive inaccessible service');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(301)::text),'NAVC-014: in-progress commitment included');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(302)::text and (r->>'session_date')::date < (statement_timestamp() at time zone 'Pacific/Kiritimati')::date),'NAVC-014: future western-local yesterday remains included');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(303)::text),'NAVC-014: ended commitment excluded');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id' in(pg_temp.u(310)::text,pg_temp.u(311)::text,pg_temp.u(312)::text)),'NAVC-013: no unbooked, other-member or foreign-tenant rows');
select ok((select bool_and(r->>'my_booking_id' is not null and r->>'my_booking_status' is not null) from jsonb_array_elements(pg_temp.val('absolute'))r),'NAVC-013: every returned row has an own booking identity and state');
select ok((select bool_and(r->>'availability'<>'open' and (r->>'can_cancel')::boolean=false) from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id' in(pg_temp.u(305)::text,pg_temp.u(306)::text,pg_temp.u(307)::text)),'NAVC-013: cancelled booking states never become open purchase opportunities');
select is((select r->>'my_booking_status' from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(305)::text),'cancelled_by_member','NAVC-013: member cancellation state retained');
select is((select r->>'my_booking_status' from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(306)::text),'cancelled_by_gym','NAVC-013: gym cancellation state retained');
select is((select r->>'session_status' from jsonb_array_elements(pg_temp.val('absolute'))r where r->>'session_id'=pg_temp.u(307)::text),'cancelled','NAVC-013: cancelled session remains truthful');
select ok((select bool_and(previous is null or (previous->>'starts_at')::timestamptz < (r->>'starts_at')::timestamptz or ((previous->>'starts_at')::timestamptz=(r->>'starts_at')::timestamptz and (previous->>'session_id')::uuid < (r->>'session_id')::uuid)) from (select r,lag(r) over(order by ord)previous from jsonb_array_elements(pg_temp.val('absolute'))with ordinality x(r,ord))o),'NAVC-013: order is absolute start and session identity, including ties');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('absolute'))r cross join lateral jsonb_object_keys(r)k where k in('member_id','user_id','tenant_id','trainer_staff_id','member_phone','member_name')),'NAVC-013: safe projection contains no private member or staff identity');

-- CLS-026 (approved openspec/changes/classes/proposal.md) fixes every class
-- "now" to statement_timestamp(); v2 preserves that existing class contract.
-- Align fixtures and the read in one outer statement to prove strict exclusion
-- and inclusion without changing the clock or installing a test-only reader.
set local role postgres;
select is(pg_temp.run($probe$do $b$ begin
 update public.class_sessions set starts_at=statement_timestamp()+interval '28 days',ends_at=statement_timestamp()+interval '28 days 1 hour',session_date=((statement_timestamp()+interval '28 days') at time zone 'Etc/GMT+12')::date where id=pg_temp.u(304);
 update public.class_sessions set starts_at=statement_timestamp()-interval '1 hour',ends_at=statement_timestamp(),session_date=((statement_timestamp()-interval '1 hour') at time zone 'Etc/GMT+12')::date where id=pg_temp.u(303);
 set local role authenticated;
 perform pg_temp.capture('boundary','select * from public.read_member_upcoming_class_bookings()');
 end $b$;$probe$),'OK','NAVC-014: capture exact upper and end boundaries in one statement');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('boundary'))r where r->>'session_id'=pg_temp.u(304)::text),'NAVC-014: start exactly at 28-day horizon excluded');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('boundary'))r where r->>'session_id'=pg_temp.u(303)::text),'NAVC-014: end exactly at captured clock excluded');
set local role postgres;
select is(pg_temp.run($probe$do $b$ begin
 update public.class_sessions set starts_at=statement_timestamp()+interval '28 days'-interval '1 microsecond',ends_at=statement_timestamp()+interval '28 days 1 hour',session_date=((statement_timestamp()+interval '28 days'-interval '1 microsecond') at time zone 'Etc/GMT+12')::date where id=pg_temp.u(304);
 update public.class_sessions set starts_at=statement_timestamp()-interval '1 hour',ends_at=statement_timestamp()+interval '1 microsecond',session_date=((statement_timestamp()-interval '1 hour') at time zone 'Etc/GMT+12')::date where id=pg_temp.u(303);
 set local role authenticated;
 perform pg_temp.capture('inside','select * from public.read_member_upcoming_class_bookings()');
 end $b$;$probe$),'OK','NAVC-014: capture just-inside horizon and end boundaries');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.val('inside'))r where r->>'session_id'=pg_temp.u(304)::text),'NAVC-014: start one microsecond inside horizon included');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.val('inside'))r where r->>'session_id'=pg_temp.u(303)::text),'NAVC-014: end one microsecond after captured clock included');
set local role authenticated;
select pg_temp.claim(102);
select is((select count(*)::integer from public.read_member_upcoming_class_bookings()),1,'NAVC-013: second member receives only its own commitment');
select pg_temp.claim(106);
select is((select count(*)::integer from public.read_member_upcoming_class_bookings()),0,'NAVC-013: valid member without bookings receives empty success');
select pg_temp.claim(101,2);
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: foreign tenant claim refused before returning rows');
select pg_temp.claim(101,1,jsonb_build_object('member_id',pg_temp.u(102)));
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: spoofed other-member identity refused');
select pg_temp.claim(21);
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: owner cannot use member commitment reader');
select pg_temp.claim(101,1,jsonb_build_object('impersonation_session_id',pg_temp.u(999)));
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: preview has no own-booking projection authority');
select pg_temp.claim(103);
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: blocked member cannot read commitments');
select pg_temp.claim(104);
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: erased member cannot read commitments');
select pg_temp.claim(105);
select is(pg_temp.run($$select * from public.read_member_upcoming_class_bookings()$$),'42501','NAVC-013: unlinked member cannot read commitments');
set local role postgres;
select is((select member_classes_enabled from public.organization_settings where tenant_id=pg_temp.u(1)),false,'NAVC-015: later commitments and independent reads never override saved Off');
select * from finish();
rollback;
