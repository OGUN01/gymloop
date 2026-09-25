-- ATT-003/009-014 visible contract tests. All probes roll back (ADR-030).
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(39);

select has_enum('public', 'checkin_gate_mode', 'mode is a canonical Postgres enum');
select enum_has_labels('public', 'checkin_gate_mode', array['printed_poster', 'rotating_screen']::name[], 'only approved gate modes exist');
select col_is_null('public', 'qr_sessions', 'expires_at', 'poster sessions can be non-expiring');
select col_not_null('public', 'qr_sessions', 'gate_mode', 'QR sessions distinguish poster from rotating');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='qr_sessions' and indexdef like '%UNIQUE%' and indexdef like '%tenant_id, branch_id%' and indexdef like '%printed_poster%' and indexdef like '%revoked_at IS NULL%'), 'unique partial index admits only one live poster per branch');

insert into auth.users(id) values
  ('66000000-0000-4000-8000-000000000901'),('66000000-0000-4000-8000-000000000902'),
  ('66000000-0000-4000-8000-000000000903'),('66000000-0000-4000-8000-000000000904'),
  ('66000000-0000-4000-8000-000000000905');
insert into public.organizations(id,name,gym_code,timezone) values
  ('66000000-0000-4000-8000-000000000001','Poster Gym A','PST66A','Asia/Kolkata'),
  ('66000000-0000-4000-8000-000000000002','Poster Gym B','PST66B','Asia/Kolkata');
insert into public.organization_settings(tenant_id, checkin_dedupe_seconds) values
  ('66000000-0000-4000-8000-000000000001',0),('66000000-0000-4000-8000-000000000002',0);
insert into public.branches(id,tenant_id,name,is_default,timezone) values
  ('66000000-0000-4000-8000-000000000011','66000000-0000-4000-8000-000000000001','A Main',true,'Asia/Kolkata'),
  ('66000000-0000-4000-8000-000000000012','66000000-0000-4000-8000-000000000001','A Other',false,'Etc/GMT+12'),
  ('66000000-0000-4000-8000-000000000013','66000000-0000-4000-8000-000000000002','B Main',true,'Asia/Kolkata');
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name) values
  ('66000000-0000-4000-8000-000000000021','66000000-0000-4000-8000-000000000901','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000011','gym_owner','A Owner'),
  ('66000000-0000-4000-8000-000000000022','66000000-0000-4000-8000-000000000902','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000011','gym_manager','A Manager'),
  ('66000000-0000-4000-8000-000000000023','66000000-0000-4000-8000-000000000903','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000011','front_desk','A Desk'),
  ('66000000-0000-4000-8000-000000000024','66000000-0000-4000-8000-000000000904','66000000-0000-4000-8000-000000000002','66000000-0000-4000-8000-000000000013','gym_owner','B Owner');
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone) values
  ('66000000-0000-4000-8000-000000000031','66000000-0000-4000-8000-000000000905','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000011','A Member','+916600000031'),
  ('66000000-0000-4000-8000-000000000032',null,'66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000012','Other Branch','+916600000032');
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values ('66000000-0000-4000-8000-000000000041','66000000-0000-4000-8000-000000000001','Monthly',30,200000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) values
  ('66000000-0000-4000-8000-000000000051','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000031','66000000-0000-4000-8000-000000000041','active',(now() at time zone 'Asia/Kolkata')::date-1,(now() at time zone 'Asia/Kolkata')::date+30,200000),
  ('66000000-0000-4000-8000-000000000052','66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000032','66000000-0000-4000-8000-000000000041','active',(now() at time zone 'Asia/Kolkata')::date-1,(now() at time zone 'Asia/Kolkata')::date+30,200000);
select is((select checkin_gate_mode::text from public.organization_settings where tenant_id='66000000-0000-4000-8000-000000000001'), 'printed_poster'::text, 'new gym starts in printed-poster mode');
select is((select checkin_gate_mode::text from public.organization_settings where tenant_id='66000000-0000-4000-8000-000000000002'), 'printed_poster'::text, 'second new gym defaults independently');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='attendance' and indexdef like '%tenant_id, member_id, checked_in_at%'), 'once-per-day lookup uses existing tenant/member/time index');
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"66000000-0000-4000-8000-000000000001","staff_id":"66000000-0000-4000-8000-000000000021"}',true);
set local role authenticated;
select is(public.replace_checkin_poster('66000000-0000-4000-8000-000000000011','66000000-0000-4000-8000-000000000061',repeat('a',64)), '66000000-0000-4000-8000-000000000061'::uuid, 'owner issues first poster atomically');
select is((select count(*) from public.qr_sessions where tenant_id='66000000-0000-4000-8000-000000000001' and branch_id='66000000-0000-4000-8000-000000000011' and gate_mode='printed_poster' and revoked_at is null), 1::bigint, 'one active poster in branch');
select is((select expires_at from public.qr_sessions where id='66000000-0000-4000-8000-000000000061'), null::timestamptz, 'poster does not expire');
select throws_ok($$select public.replace_checkin_poster('66000000-0000-4000-8000-000000000013','66000000-0000-4000-8000-000000000062',repeat('b',64))$$,'42501',null,'foreign branch replacement is denied');
select throws_ok($$insert into public.qr_sessions(tenant_id,branch_id,token_hash,gate_mode) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000012',repeat('c',64),'printed_poster')$$,'42501',null,'direct poster insert cannot evade audited command');
select throws_ok($$update public.organization_settings set checkin_gate_mode='rotating_screen' where tenant_id='66000000-0000-4000-8000-000000000001'$$,'42501',null,'direct mode write cannot skip atomic poster revocation/audit');
select is((select count(*) from public.qr_sessions where tenant_id='66000000-0000-4000-8000-000000000002'),0::bigint,'owner cannot see any session in another gym');
select throws_ok($$insert into public.qr_sessions(tenant_id,branch_id,token_hash,gate_mode) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000011',repeat('d',64),'printed_poster')$$,'42501',null,'direct insert cannot make a second active poster');
select is(public.replace_checkin_poster('66000000-0000-4000-8000-000000000011','66000000-0000-4000-8000-000000000063',repeat('e',64)), '66000000-0000-4000-8000-000000000063'::uuid, 'replacement creates one new session');
select ok((select revoked_at is not null from public.qr_sessions where id='66000000-0000-4000-8000-000000000061'), 'replacement immediately revokes old hash');
select is((select actor_user_id from public.audit_log where tenant_id='66000000-0000-4000-8000-000000000001' and action='checkin_poster.replaced' and record_id='66000000-0000-4000-8000-000000000063'), '66000000-0000-4000-8000-000000000901'::uuid, 'replacement is audited under authenticated owner');
select throws_ok($$insert into public.attendance(tenant_id,member_id,branch_id,source,qr_session_id) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000031','66000000-0000-4000-8000-000000000011','qr','66000000-0000-4000-8000-000000000061')$$,'GL012',null,'old poster is refused after replacement');
select throws_ok($$insert into public.attendance(tenant_id,member_id,branch_id,source,qr_session_id) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000032','66000000-0000-4000-8000-000000000012','qr','66000000-0000-4000-8000-000000000063')$$,'GL071',null,'same-gym wrong-branch scan is refused');
select is((select count(*) from public.qr_sessions where tenant_id='66000000-0000-4000-8000-000000000002'), 0::bigint, 'foreign-branch probes leave B gym unchanged');

-- Member RPC reaches the same BEFORE INSERT trigger as the direct staff path.
set local role postgres;
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"member","tenant_id":"66000000-0000-4000-8000-000000000001","member_id":"66000000-0000-4000-8000-000000000031"}',true);
set local role authenticated;
select is((select count(*) from public.member_mobile_check_in(repeat('e',64),'66000000-0000-4000-8000-000000000071',null)),1::bigint,'member RPC accepts live poster with empty hours');
select is((select replay from public.member_mobile_check_in(repeat('e',64),'66000000-0000-4000-8000-000000000071',null)),true,'same event id remains idempotent');
select throws_ok($$select * from public.member_mobile_check_in(repeat('e',64),null,null)$$,'GL073',null,'second poster scan today is refused with zero dedupe seconds');
select throws_ok($$select * from public.member_mobile_check_in(repeat('a',64),null,now()-interval '1 hour')$$,'GL012',null,'offline replay cannot revive a replaced poster');
set local role postgres;
select is((select count(*) from public.attendance where tenant_id='66000000-0000-4000-8000-000000000001' and member_id='66000000-0000-4000-8000-000000000031'),1::bigint,'refused scans and replays add no attendance');

select ok(app.poster_open_at('{"fri":["22:00-02:00"]}'::jsonb,'2026-09-18 23:30:00+00'::timestamptz,'UTC'),'overnight interval starts Friday');
select ok(app.poster_open_at('{"fri":["22:00-02:00"]}'::jsonb,'2026-09-19 01:30:00+00'::timestamptz,'UTC'),'overnight interval continues Saturday morning');
select ok(not app.poster_open_at('{"fri":["22:00-02:00"]}'::jsonb,'2026-09-19 02:00:00+00'::timestamptz,'UTC'),'overnight closing instant excluded');
select ok(app.poster_open_at('{}'::jsonb,now(),'Asia/Kolkata'),'empty hours permit every time');
select ok(not app.poster_open_at('{"mon":[]}'::jsonb,now(),'Asia/Kolkata'),'nonempty hours missing current day close gate');
update public.organization_settings set opening_hours='{"sun":[],"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[]}'::jsonb where tenant_id='66000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"66000000-0000-4000-8000-000000000001","staff_id":"66000000-0000-4000-8000-000000000022"}',true);
set local role authenticated;
select throws_ok($$insert into public.attendance(tenant_id,member_id,branch_id,source,qr_session_id) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000031','66000000-0000-4000-8000-000000000011','qr','66000000-0000-4000-8000-000000000063')$$,'GL072',null,'direct insert refused when poster hours closed');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"66000000-0000-4000-8000-000000000001","staff_id":"66000000-0000-4000-8000-000000000023"}',true);
set local role authenticated;
select throws_ok($$select public.set_checkin_gate_mode('rotating_screen')$$,'42501',null,'front desk cannot change gym mode');
select throws_ok($$select public.replace_checkin_poster('66000000-0000-4000-8000-000000000011',gen_random_uuid(),repeat('9',64))$$,'42501',null,'front desk cannot replace poster');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"66000000-0000-4000-8000-000000000001","staff_id":"66000000-0000-4000-8000-000000000022"}',true);
set local role authenticated;
select is(public.set_checkin_gate_mode('rotating_screen')::text,'rotating_screen'::text,'manager may switch mode');
select ok((select revoked_at is not null from public.qr_sessions where id='66000000-0000-4000-8000-000000000063'),'switching modes revokes poster atomically');
select throws_ok($$insert into public.attendance(tenant_id,member_id,branch_id,source,qr_session_id) values ('66000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000031','66000000-0000-4000-8000-000000000011','qr','66000000-0000-4000-8000-000000000063')$$,'GL012',null,'old poster refused after switching mode');
select is((select actor_user_id from public.audit_log where action='checkin_gate.mode_changed' and tenant_id='66000000-0000-4000-8000-000000000001' order by occurred_at desc limit 1), '66000000-0000-4000-8000-000000000902'::uuid,'mode change audit names manager');
select * from finish();
rollback;
