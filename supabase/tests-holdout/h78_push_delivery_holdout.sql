-- h78 NTF push-delivery holdout (independent adversarial author; no implementation consulted).
-- Frozen contract: proposal NTF-001..016, transport + pre-configuration amendments,
-- wave-c delivery declarations and serial freeze declarations. The unconfigured provider is
-- the default CI state; configured-path dispatch classification is live-acceptance evidence.
begin;
set local role postgres;
set local search_path = extensions, public;
set local timezone = 'UTC';
select set_config('request.jwt.claims','',true);
select plan(103);

-- ---------------------------------------------------------------- fixtures (owner context, RLS not applying)
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('78900000-0000-4000-8000-000000000001','Holdout Push A','HPA789','active','Asia/Kolkata','INR'),
 ('78900000-0000-4000-8000-000000000002','Holdout Push B','HPB789','active','Asia/Kolkata','INR');
insert into auth.users(id) values
 ('78900000-0000-4000-8000-000000000901'),
 ('78900000-0000-4000-8000-000000000902'),
 ('78900000-0000-4000-8000-000000000903'),
 ('78900000-0000-4000-8000-000000000904'),
 ('78900000-0000-4000-8000-000000000905'),
 ('78900000-0000-4000-8000-000000000906'),
 ('78900000-0000-4000-8000-000000000911'),
 ('78900000-0000-4000-8000-000000000912'),
 ('78900000-0000-4000-8000-000000000921');
insert into public.branches(id,tenant_id,name,is_default) values
 ('78900000-0000-4000-8000-000000000101','78900000-0000-4000-8000-000000000001','Holdout Branch A',true),
 ('78900000-0000-4000-8000-000000000102','78900000-0000-4000-8000-000000000002','Holdout Branch B',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,user_id,date_of_birth) values
 ('78900000-0000-4000-8000-000000000701','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Member A','+917890000001','active','78900000-0000-4000-8000-000000000901',null),
 ('78900000-0000-4000-8000-000000000702','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Member B','+917890000002','active','78900000-0000-4000-8000-000000000902',null),
 ('78900000-0000-4000-8000-000000000703','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Blocked','+917890000003','blocked','78900000-0000-4000-8000-000000000903',null),
 ('78900000-0000-4000-8000-000000000704','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Minor','+917890000004','active','78900000-0000-4000-8000-000000000904','2015-01-01'),
 ('78900000-0000-4000-8000-000000000705','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Dual','+917890000005','active','78900000-0000-4000-8000-000000000905',null),
 ('78900000-0000-4000-8000-000000000706','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000101','Holdout Expired','+917890000006','expired','78900000-0000-4000-8000-000000000906',null),
 ('78900000-0000-4000-8000-000000000721','78900000-0000-4000-8000-000000000002','78900000-0000-4000-8000-000000000102','Holdout Member D','+917890000021','active','78900000-0000-4000-8000-000000000921',null);
insert into public.staff(id,tenant_id,user_id,role,full_name) values
 ('78900000-0000-4000-8000-000000000611','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000911','gym_owner','Holdout Owner'),
 ('78900000-0000-4000-8000-000000000612','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000912','trainer','Holdout Trainer'),
 ('78900000-0000-4000-8000-000000000615','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000905','trainer','Holdout Dual Staff');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at) values
 ('78900000-0000-4000-8000-000000000501','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000701','service',true,'v1','holdout',now()),
 ('78900000-0000-4000-8000-000000000502','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000702','service',true,'v1','holdout',now());
insert into public.announcements(id,tenant_id,kind,audience,status,current_version,created_by_staff_id,published_at) values
 ('78900000-0000-4000-8000-000000000401','78900000-0000-4000-8000-000000000001','transactional','all_members','published',1,'78900000-0000-4000-8000-000000000611',now());
insert into public.notifications(id,tenant_id,member_id,channel,category,status,dedupe_key,payload,scheduled_for) values
 ('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000701','push','motivation','scheduled','holdout:h78-push-1','{}'::jsonb,now()),
 ('78900000-0000-4000-8000-000000000302','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000701','in_app','motivation','scheduled','holdout:h78-inapp-1','{}'::jsonb,now());
create temp table h78_wallet0(ledger_rows bigint,wallet_row jsonb) on commit drop;
insert into h78_wallet0
 select (select count(*) from public.messaging_wallet_ledger where tenant_id='78900000-0000-4000-8000-000000000001'),
        (select to_jsonb(w) from public.messaging_wallets w where w.tenant_id='78900000-0000-4000-8000-000000000001' limit 1);
create temp table h78_audit0(n bigint) on commit drop;
insert into h78_audit0 select count(*) from public.audit_log;
create temp table h78_out(label text primary key, result jsonb);
grant all on h78_out to authenticated;

-- outcome capture helpers: error SQLSTATE inside jsonb, never thrown past the call
create function pg_temp.h78_reg(p_installation uuid,p_token text,p_platform text) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := public.register_member_push_device(p_installation,p_token,p_platform);
  return r;
exception when others then
  return jsonb_build_object('error',SQLSTATE);
end;
$f$;
create function pg_temp.h78_unset(p_installation uuid) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := public.unregister_member_push_device(p_installation);
  return r;
exception when others then
  return jsonb_build_object('error',SQLSTATE);
end;
$f$;
create function pg_temp.h78_ack(p_notification uuid,p_device uuid,p_revision bigint,p_event text) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := public.acknowledge_member_push(p_notification,p_device,p_revision,p_event);
  return r;
exception when others then
  return jsonb_build_object('error',SQLSTATE);
end;
$f$;
create function pg_temp.h78_pref(p_category public.message_category,p_enabled boolean) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := public.set_member_push_preference(p_category,p_enabled);
  return r;
exception when others then
  return jsonb_build_object('error',SQLSTATE);
end;
$f$;
create function pg_temp.h78_read() returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := public.read_member_push_settings();
  return r;
exception when others then
  return jsonb_build_object('error',SQLSTATE);
end;
$f$;
create function pg_temp.h78_sql(p_stmt text) returns text language plpgsql as $f$
begin
  execute p_stmt;
  return 'ok';
exception when others then
  return 'err:'||SQLSTATE;
end;
$f$;

-- ---------------------------------------------------------------- A. shape (22)
select has_table('public','member_devices','H78 member_devices survives the amendment');
select has_column('public','member_devices','registered_user_id','H78 device binding user recorded');
select has_column('public','member_devices','installation_id','H78 device installation id');
select has_column('public','member_devices','token_revision','H78 device token revision');
select has_column('public','member_devices','invalidated_at','H78 device invalidation timestamp');
select has_column('public','member_devices','invalidated_reason','H78 device invalidation reason');
select col_is_unique('public','member_devices',array['tenant_id','member_id','installation_id'],'H78 one device row per installation');
select col_is_unique('public','member_devices',array['tenant_id','push_token'],'H78 existing tenant/token uniqueness retained');
select fk_ok('public','member_devices',array['tenant_id','member_id'],'public','members',array['tenant_id','id'],'H78 composite tenant/member device FK');
select has_table('public','member_notification_preferences','H78 preferences table exists');
select has_column('public','member_notification_preferences','category','H78 preference category is the DB vocabulary');
select has_column('public','member_notification_preferences','enabled','H78 preference enabled flag');
select col_is_unique('public','member_notification_preferences',array['tenant_id','member_id','category'],'H78 one preference per category');
select has_table('public','notification_push_campaigns','H78 campaigns table exists');
select col_is_unique('public','notification_push_campaigns',array['tenant_id','announcement_id','version_no'],'H78 one campaign per announcement version');
select col_is_unique('public','notification_push_campaigns',array['tenant_id','request_key'],'H78 campaign request key unique per tenant');
select fk_ok('public','notification_push_campaigns',array['tenant_id','announcement_id'],'public','announcements',array['tenant_id','id'],'H78 campaign announcement composite FK');
select has_table('public','notification_push_attempts','H78 attempts table exists');
select col_is_unique('public','notification_push_attempts',array['tenant_id','notification_id','device_id'],'H78 one durable attempt per notification/device');
select fk_ok('public','notification_push_attempts',array['tenant_id','member_id'],'public','members',array['tenant_id','id'],'H78 attempt composite tenant/member FK');
select enum_has_labels('public','notification_status',array['scheduled','sent','delivered','failed','clicked','converted','opted_out'],'H78 canonical status vocabulary unchanged');
select enum_has_labels('public','message_category',array['renewal','payment','fulfilment','promotion','motivation','class_update','announcement'],'H78 canonical category vocabulary unchanged');

-- ---------------------------------------------------------------- B. grants (25)
select is(has_table_privilege('authenticated','public.member_devices','INSERT'),false,'H78 authenticated cannot insert devices directly');
select is(has_table_privilege('authenticated','public.member_devices','UPDATE'),false,'H78 authenticated cannot update devices directly');
select is(has_table_privilege('authenticated','public.member_devices','DELETE'),false,'H78 authenticated cannot delete devices directly');
select is(has_column_privilege('authenticated','public.member_devices','push_token','SELECT'),false,'H78 token column unreadable by members');
select is(has_table_privilege('anon','public.member_devices','INSERT'),false,'H78 anon cannot insert devices');
select is(has_column_privilege('anon','public.member_devices','push_token','SELECT'),false,'H78 token column unreadable by anon');
select is(has_table_privilege('authenticated','public.member_notification_preferences','INSERT'),false,'H78 preference writes go through the command only');
select is(has_table_privilege('authenticated','public.member_notification_preferences','UPDATE'),false,'H78 preference rows are not directly editable');
select is(has_table_privilege('authenticated','public.notification_push_attempts','SELECT'),false,'H78 attempts unreadable by authenticated');
select is(has_table_privilege('authenticated','public.notification_push_attempts','INSERT'),false,'H78 attempts not directly writable by authenticated');
select is(has_table_privilege('anon','public.notification_push_attempts','SELECT'),false,'H78 attempts unreadable by anon');
select is(has_table_privilege('service_role','public.notification_push_attempts','INSERT'),false,'H78 no direct service DML on attempts');
select is(has_table_privilege('service_role','public.notification_push_attempts','DELETE'),false,'H78 attempts are not deletable even by service role');
select is(has_table_privilege('authenticated','public.notification_push_campaigns','INSERT'),false,'H78 campaigns created only through reviewed commands');
select is(has_function_privilege('service_role','public.reserve_push_attempts(integer)','EXECUTE'),true,'H78 transport facade granted to service role');
select is(has_function_privilege('anon','public.reserve_push_attempts(integer)','EXECUTE'),false,'H78 transport facade denied to anon');
select is(has_function_privilege('authenticated','public.reserve_push_attempts(integer)','EXECUTE'),false,'H78 transport facade denied to authenticated');
select is(has_function_privilege('authenticated','public.authorize_push_attempt(uuid,uuid)','EXECUTE'),false,'H78 authorization facade denied to authenticated');
select is(has_function_privilege('authenticated','public.register_member_push_device(uuid,text,text)','EXECUTE'),true,'H78 device registration granted to members');
select is(has_function_privilege('anon','public.register_member_push_device(uuid,text,text)','EXECUTE'),false,'H78 device registration denied to anon');
select is(has_function_privilege('authenticated','public.read_member_push_settings()','EXECUTE'),true,'H78 settings read granted to members');
select is(has_function_privilege('anon','public.read_member_push_settings()','EXECUTE'),false,'H78 settings read denied to anon');
select is(has_function_privilege('authenticated','public.acknowledge_member_push(uuid,uuid,bigint,text)','EXECUTE'),true,'H78 acknowledgement granted to members');
select is(has_function_privilege('anon','public.acknowledge_member_push(uuid,uuid,bigint,text)','EXECUTE'),false,'H78 acknowledgement denied to anon');
select is(has_function_privilege('authenticated','app.run_push_events(uuid)','EXECUTE'),false,'H78 scheduler driver has no ordinary grant');

-- ---------------------------------------------------------------- C. member RPC attacks (34)
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);
set local role authenticated;
insert into h78_out values ('reg1',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a01','789token-first','android'));
select is((select result->>'tokenRevision' from h78_out where label='reg1'),'1','H78 first registration starts at revision one');
select is((select result->>'active' from h78_out where label='reg1'),'true','H78 registration is active');
insert into h78_out values ('replay',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a01','789token-first','android'));
select is((select result from h78_out where label='replay'),(select result from h78_out where label='reg1'),'H78 same installation/token is an inert replay');
insert into h78_out values ('rotate',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a01','789token-second','android'));
select is((select result->>'tokenRevision' from h78_out where label='rotate'),'2','H78 rotation increments the revision');
select ok(not exists(select 1 from public.member_devices where tenant_id='78900000-0000-4000-8000-000000000001' and member_id='78900000-0000-4000-8000-000000000701' and push_token='789token-first' and is_active),'H78 old revision is not an active send target after rotation');
insert into h78_out values ('ios',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a02','789token-ios','ios'));
select ok((select result ? 'error' from h78_out where label='ios'),'H78 non-Android platform refused');
insert into h78_out values ('blank',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a03','','android'));
select ok((select result ? 'error' from h78_out where label='blank'),'H78 blank token refused');
insert into h78_out values ('huge',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a04',repeat('x',4097),'android'));
select ok((select result ? 'error' from h78_out where label='huge'),'H78 oversized token refused');
insert into h78_out values ('steal',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a05','789token-second','android'));
select ok((select result ? 'error' from h78_out where label='steal'),'H78 cross-member token collision refused generically');
select ok(exists(select 1 from public.member_devices where tenant_id='78900000-0000-4000-8000-000000000001' and member_id='78900000-0000-4000-8000-000000000701' and push_token='789token-second' and is_active),'H78 collision does not move the token to the attacker');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000903','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000703')::text,true);
insert into h78_out values ('blocked',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a06','789token-blocked','android'));
select ok((select result ? 'error' from h78_out where label='blocked'),'H78 blocked member cannot register');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000906','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000706')::text,true);
insert into h78_out values ('expired',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a07','789token-expired','android'));
select ok((select result ? 'error' from h78_out where label='expired'),'H78 expired member cannot register');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000904','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000704')::text,true);
insert into h78_out values ('minor',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a08','789token-minor','android'));
select ok((select result ? 'error' from h78_out where label='minor'),'H78 known minor without a complete guardian record cannot register');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000905','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000705')::text,true);
insert into h78_out values ('dual',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a09','789token-dual','android'));
select ok((select result ? 'error' from h78_out where label='dual'),'H78 a user also bound to a staff row has no member device identity');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701','impersonation_session_id','78900000-0000-4000-8000-000000000801')::text,true);
insert into h78_out values ('impersonated',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a10','789token-impersonated','android'));
select ok((select result ? 'error' from h78_out where label='impersonated'),'H78 impersonation cannot mutate member devices');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000911','role','authenticated','app_role','super_admin','tenant_id','78900000-0000-4000-8000-000000000001')::text,true);
insert into h78_out values ('platform',pg_temp.h78_read());
select ok((select result ? 'error' from h78_out where label='platform'),'H78 platform support has no member settings read');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000912','role','authenticated','app_role','trainer','tenant_id','78900000-0000-4000-8000-000000000001')::text,true);
insert into h78_out values ('trainer',pg_temp.h78_reg('78900000-0000-4000-8000-000000000a11','789token-trainer','android'));
select ok((select result ? 'error' from h78_out where label='trainer'),'H78 trainer identity cannot register a member device');
select set_config('request.jwt.claims','',true);
insert into h78_out values ('anonctx',pg_temp.h78_read());
select ok((select result ? 'error' from h78_out where label='anonctx'),'H78 missing claims fail closed');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);
insert into h78_out values ('unset-own',pg_temp.h78_unset('78900000-0000-4000-8000-000000000b99'));
select is((select result->>'disabled' from h78_out where label='unset-own'),'true','H78 unregistering an absent own installation is inert');
insert into h78_out values ('unset-foreign',pg_temp.h78_unset('78900000-0000-4000-8000-000000000b98'));
select is((select result from h78_out where label='unset-foreign'),(select result from h78_out where label='unset-own'),'H78 foreign and absent device ids are indistinguishable');
insert into h78_out values ('settings',pg_temp.h78_read());
select is((select result->'devices' from h78_out where label='settings'),'[]'::jsonb,'H78 no fabricated devices in settings');
select ok(NOT exists(select 1 from jsonb_array_elements((select result->'devices' from h78_out where label='settings')) d where d ?| array['token','pushToken','contact','guardianContact','email']),'H78 device metadata carries no token or contact');
insert into h78_out values ('pref1',pg_temp.h78_pref('promotion',false));
select is((select result from h78_out where label='pref1'),jsonb_build_object('category','promotion','enabled',false),'H78 preference change returns the exact pair');
insert into h78_out values ('pref-replay',pg_temp.h78_pref('promotion',false));
select is((select result from h78_out where label='pref-replay'),(select result from h78_out where label='pref1'),'H78 identical preference replay is inert');
create temp table h78_audit1(n bigint) on commit drop;
insert into h78_audit1 select count(*) from public.audit_log;
select is((select n from h78_audit1),(select n from h78_audit0),'H78 inert replays append no audit rows');
select is((select count(*) from public.consents where tenant_id='78900000-0000-4000-8000-000000000001'),2::bigint,'H78 preference command never mutates consents');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000902','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000702')::text,true);
select is((select count(*) from public.member_notification_preferences where member_id='78900000-0000-4000-8000-000000000701'),0::bigint,'H78 another member reads zero preference rows');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000911','role','authenticated','app_role','gym_owner','tenant_id','78900000-0000-4000-8000-000000000001')::text,true);
select is((select count(*) from public.member_notification_preferences),0::bigint,'H78 staff reads zero preference rows');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);
insert into h78_out values ('ack-event',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000a01',2,'read'));
select ok((select result ? 'error' from h78_out where label='ack-event'),'H78 acknowledgement event outside received/opened refused');
insert into h78_out values ('ack-foreign',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000b01',2,'received'));
select ok((select result ? 'error' from h78_out where label='ack-foreign'),'H78 foreign device acknowledgement refused');
insert into h78_out values ('ack-unknown',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000b02',2,'received'));
select is((select result from h78_out where label='ack-unknown'),(select result from h78_out where label='ack-foreign'),'H78 foreign and unknown devices refuse identically');
insert into h78_out values ('ack-stale',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000a01',999,'received'));
select ok((select result ? 'error' from h78_out where label='ack-stale'),'H78 stale token revision cannot acknowledge');
insert into h78_out values ('ack-noattempt',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000a01',2,'received'));
select ok((select result ? 'error' from h78_out where label='ack-noattempt'),'H78 receipt evidence requires a matching accepted attempt');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000902','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000702')::text,true);
insert into h78_out values ('ack-other-member',pg_temp.h78_ack('78900000-0000-4000-8000-000000000301','78900000-0000-4000-8000-000000000a01',2,'received'));
select ok((select result ? 'error' from h78_out where label='ack-other-member'),'H78 another member cannot acknowledge someone else push');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);

-- ---------------------------------------------------------------- D. transport facades and fail-closed configuration (8)
select set_config('request.jwt.claims','',true);
reset role;
set local role postgres;
set local role service_role;
select throws_ok('select public.reserve_push_attempts(0)','22023',null,'H78 zero batch is out of range');
select throws_ok('select public.reserve_push_attempts(101)','22023',null,'H78 oversized batch is out of range');
select is((select public.reserve_push_attempts(10) ->> 'configuration'),'provider_unconfigured','H78 unconfigured provider reserves nothing');
select throws_ok('select public.authorize_push_attempt(''78900000-0000-4000-8000-000000000c01'',''78900000-0000-4000-8000-000000000c02'')','P0002',null,'H78 unknown attempt/reservation pair is invisible');
select throws_ok('select public.finish_push_attempt(''78900000-0000-4000-8000-000000000c01'',''78900000-0000-4000-8000-000000000c02'',null,null,true)','P0002',null,'H78 finishing an unknown attempt is invisible');
reset role;
set local role postgres;
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000911','role','authenticated','app_role','gym_owner','tenant_id','78900000-0000-4000-8000-000000000001')::text,true);
set local role authenticated;
select throws_ok('select app.run_push_events(''78900000-0000-4000-8000-000000000001'')','42501',null,'H78 owner context cannot run the scheduler driver');
reset role;
set local role postgres;
select set_config('request.jwt.claims','',true);
select lives_ok('select app.run_push_events(''78900000-0000-4000-8000-000000000001'')','H78 trusted scheduler context may run the bounded driver');
set local role service_role;
select is((select public.reserve_push_attempts(10) ->> 'configuration'),'provider_unconfigured','H78 zero eligible sources still reserve nothing while unconfigured');
reset role;
set local role postgres;

-- ---------------------------------------------------------------- E. notification graph and evidence (4)
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);
set local role authenticated;
select throws_ok('insert into public.notifications(tenant_id,member_id,channel,category,status,dedupe_key,scheduled_for) values (''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000701'',''push'',''motivation'',''scheduled'',''holdout:h78-forged'',now())','42501',null,'H78 members cannot create notifications directly');
reset role;
set local role postgres;
select set_config('request.jwt.claims','',true);
select is(pg_temp.h78_sql('update public.notifications set status=''sent'', sent_at=now() where id=''78900000-0000-4000-8000-000000000301''') <> 'ok',true,'H78 push dispatch edge requires the durable attempt evidence');
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000911','role','authenticated','app_role','gym_owner','tenant_id','78900000-0000-4000-8000-000000000001')::text,true);
set local role authenticated;
select public.send_notification('78900000-0000-4000-8000-000000000302');
reset role;
set local role postgres;
select set_config('request.jwt.claims',json_build_object('sub','78900000-0000-4000-8000-000000000901','role','authenticated','app_role','member','tenant_id','78900000-0000-4000-8000-000000000001','member_id','78900000-0000-4000-8000-000000000701')::text,true);
set local role authenticated;
select is((select public.acknowledge_notification('78900000-0000-4000-8000-000000000302') ->> 'status'),'delivered','H78 own in_app acknowledgement survives the amendments unchanged');
select is(pg_temp.h78_sql('select public.acknowledge_notification(''78900000-0000-4000-8000-000000000301'')') <> 'ok',true,'H78 in_app acknowledgement never touches a push row');
reset role;
set local role postgres;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- F. campaigns, dedupe, zero charge, consent (10)
insert into public.notification_push_campaigns(id,tenant_id,announcement_id,version_no,request_key,created_by_staff_id) values
 ('78900000-0000-4000-8000-000000000201','78900000-0000-4000-8000-000000000001','78900000-0000-4000-8000-000000000401',1,'78900000-0000-4000-8000-000000000202','78900000-0000-4000-8000-000000000611');
select throws_ok('insert into public.notification_push_campaigns(id,tenant_id,announcement_id,version_no,request_key,created_by_staff_id) values (''78900000-0000-4000-8000-000000000203'',''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000401'',1,''78900000-0000-4000-8000-000000000204'',''78900000-0000-4000-8000-000000000611'')','23505',null,'H78 one reviewed campaign per announcement version');
select throws_ok('insert into public.notification_push_campaigns(id,tenant_id,announcement_id,version_no,request_key,created_by_staff_id) values (''78900000-0000-4000-8000-000000000205'',''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000401'',2,''78900000-0000-4000-8000-000000000202'',''78900000-0000-4000-8000-000000000611'')','23505',null,'H78 campaign request key is unique per tenant');
select throws_ok('insert into public.member_devices(tenant_id,member_id,platform,push_token) values (''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000721'',''android'',''789token-cross'')','23503',null,'H78 device row cannot pair tenant A with another tenant member');
select pg_temp.h78_sql('insert into public.member_devices(tenant_id,member_id,platform,push_token) values (''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000701'',''android'',''789token-legacy'')');
select ok(not exists(select 1 from public.member_devices where registered_user_id is null and is_active),'H78 legacy provenance-null devices are inactive until self-registration');
update public.consents set granted=false where id='78900000-0000-4000-8000-000000000501';
set local role service_role;
select is((select public.reserve_push_attempts(10) ->> 'configuration'),'provider_unconfigured','H78 withdrawn consent before authorization yields zero provider work');
reset role;
set local role postgres;
select set_config('request.jwt.claims','',true);
select throws_ok('select app.accept_paid_notification(''78900000-0000-4000-8000-000000000301'',''push'',100,''78900000-0000-4000-8000-000000000001'')','GL069',null,'H78 paid-provider stub stays denied');
select throws_ok('select app.accept_paid_notification(''78900000-0000-4000-8000-000000000301'',''push'',0,''78900000-0000-4000-8000-000000000001'')','GL069',null,'H78 paid-provider stub denies every cost argument');
select is((select ledger_rows from h78_wallet0),(select count(*) from public.messaging_wallet_ledger where tenant_id='78900000-0000-4000-8000-000000000001'),'H78 push path moves no wallet ledger rows');
select is((select wallet_row from h78_wallet0),(select to_jsonb(w) from public.messaging_wallets w where w.tenant_id='78900000-0000-4000-8000-000000000001' limit 1),'H78 push path changes no wallet balance');
select is(pg_temp.h78_sql('insert into public.notification_push_attempts(tenant_id,member_id,notification_id,device_id,token_revision,reservation_id) values (''78900000-0000-4000-8000-000000000001'',''78900000-0000-4000-8000-000000000701'',''78900000-0000-4000-8000-000000000301'',''78900000-0000-4000-8000-000000000a01'',2,''78900000-0000-4000-8000-000000000d01'')') <> 'ok',true,'H78 even the owner role cannot fabricate attempt evidence by direct insert');

rollback;
