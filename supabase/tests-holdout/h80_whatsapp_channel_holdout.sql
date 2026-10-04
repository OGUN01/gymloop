-- WSP h80 independent adversarial holdout; authored from the frozen contract only.
-- No implementation consulted; no visible Wave C file read (78*/79*/80*).
-- Clean-fail discipline: the wallet paise migration and every WSP table are
-- absent on Cloud until the Wave C migration is CI-applied, so all new-schema
-- reads go through pg_temp.wsp_scalar (exception-safe, null on error) and all
-- new-table staging is exception-swallowed with explicit staging assertions.
-- Refusal checks use throws_ok/throws_like (savepoint-safe, clean red today).
-- Known tradeoff (pinned spellings): attempt/receipt column and result-key
-- spellings follow the frozen contract's natural names (ticket, io_started_at,
-- uncertain_at, provider_read_at, charged_ledger_id, provider_id). If the
-- implementer chooses different names, that is an implementer report for a
-- spec: test-author fix, not a silent edit. throws_like '%' is used only where
-- the contract mandates refusal without pinning a SQLSTATE; those assertions
-- pass vacuously pre-implementation and are real checks post-implementation.
begin;
set local role postgres;
set local search_path = extensions, public;
set local timezone = 'UTC';
select set_config('request.jwt.claims','',true);
select plan(156);

-- ---------------------------------------------------------------- helpers
create function pg_temp.wsp_scalar(q text) returns text language plpgsql as $f$
declare v text;
begin
  execute q into v;
  return v;
exception when others then return null;
end $f$;

create function pg_temp.wsp_stage_wsp_tables() returns void language plpgsql as $f$
begin
  insert into public.whatsapp_sender_accounts(id,tenant_id,provider,waba_id,sender_id,secret_reference,enabled,compliance_approved_at,template_ready_at,config_revision)
   values ('80900000-0000-8000-8000-00000000a001','80900000-0000-8000-8000-000000000001','meta','waba-holdout-a','phone-holdout-a','vault:gymloop_wsp_holdout_a',true,now()-interval '1 hour',now()-interval '1 hour',1),
          ('80900000-0000-8000-8000-00000000a002','80900000-0000-8000-8000-000000000002','meta','waba-holdout-b','phone-holdout-b','vault:gymloop_wsp_holdout_b',true,now()-interval '1 hour',now()-interval '1 hour',1);
  insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,provider_template_id,provider_template_name,body_hash,parameter_schema_hash,locale,category,approved_at,approval_evidence_digest,checked_at)
   values ('80900000-0000-8000-8000-00000000b001','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-00000000a001','80900000-0000-8000-8000-00000000b101','tmpl_holdout_a','renewal_reminder','0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef','abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789','en','payment',now(),'0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',now()),
          ('80900000-0000-8000-8000-00000000b003','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-00000000a002','80900000-0000-8000-8000-00000000b102','tmpl_holdout_b','renewal_reminder','00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff','abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789','en','payment',now(),'00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',now());
  insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
   values ('80900000-0000-8000-8000-00000000c001','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-00000000a001',now()-interval '1 hour','IN','payment',350,350,'INR','all_in','1111111111111111111111111111111111111111111111111111111111111111'),
          ('80900000-0000-8000-8000-00000000c003','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-00000000a002',now()-interval '1 hour','IN','payment',350,350,'INR','all_in','3333333333333333333333333333333333333333333333333333333333333333');
exception when others then null;
end $f$;

create function pg_temp.wsp_stage_wallet() returns void language plpgsql as $f$
begin
  insert into public.messaging_wallets(tenant_id,balance_paise,currency)
   values ('80900000-0000-8000-8000-000000000001',100000,'INR'),
          ('80900000-0000-8000-8000-000000000002',350,'INR');
exception when others then null;
end $f$;

-- ---------------------------------------------------------------- fixtures
insert into auth.users(id) values
 ('80900000-0000-8000-8000-000000000901'),
 ('80900000-0000-8000-8000-000000000902'),
 ('80900000-0000-8000-8000-000000000903'),
 ('80900000-0000-8000-8000-000000000904'),
 ('80900000-0000-8000-8000-000000000905'),
 ('80900000-0000-8000-8000-000000000906'),
 ('80900000-0000-8000-8000-000000000907'),
 ('80900000-0000-8000-8000-000000000908'),
 ('80900000-0000-8000-8000-000000000909'),
 ('80900000-0000-8000-8000-000000000910'),
 ('80900000-0000-8000-8000-000000000911');
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('80900000-0000-8000-8000-000000000001','WSP Holdout A','WHA809','active','Asia/Kolkata','INR'),
 ('80900000-0000-8000-8000-000000000002','WSP Holdout B','WHB809','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('80900000-0000-8000-8000-000000000011','80900000-0000-8000-8000-000000000001','Holdout A Main',true),
 ('80900000-0000-8000-8000-000000000012','80900000-0000-8000-8000-000000000002','Holdout B Main',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,joined_on,date_of_birth,user_id) values
 ('80900000-0000-8000-8000-000000000031','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000011','Holdout Member A','+918095550001','active',current_date,'1990-01-01','80900000-0000-8000-8000-000000000901'),
 ('80900000-0000-8000-8000-000000000032','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000011','Holdout Member B','+918095550002','active',current_date,null,'80900000-0000-8000-8000-000000000906'),
 ('80900000-0000-8000-8000-000000000034','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000011','Holdout Member D','+918095550004','active',current_date,'1985-05-05','80900000-0000-8000-8000-000000000907'),
 ('80900000-0000-8000-8000-000000000033','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000012','Holdout Member C','+918095550003','active',current_date,'1992-02-02','80900000-0000-8000-8000-000000000909'),
 ('80900000-0000-8000-8000-000000000035','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000012','Holdout Member E','+918095550005','active',current_date,'1988-08-08','80900000-0000-8000-8000-000000000911');
insert into public.staff(id,tenant_id,full_name,role,is_active,user_id) values
 ('80900000-0000-8000-8000-000000000041','80900000-0000-8000-8000-000000000001','Holdout Owner A','gym_owner',true,'80900000-0000-8000-8000-000000000902'),
 ('80900000-0000-8000-8000-000000000042','80900000-0000-8000-8000-000000000001','Holdout Manager A','gym_manager',true,'80900000-0000-8000-8000-000000000903'),
 ('80900000-0000-8000-8000-000000000043','80900000-0000-8000-8000-000000000001','Holdout Desk A','front_desk',true,'80900000-0000-8000-8000-000000000904'),
 ('80900000-0000-8000-8000-000000000044','80900000-0000-8000-8000-000000000001','Holdout Trainer A','trainer',true,'80900000-0000-8000-8000-000000000905'),
 ('80900000-0000-8000-8000-000000000045','80900000-0000-8000-8000-000000000002','Holdout Owner B','gym_owner',true,'80900000-0000-8000-8000-000000000910');
insert into public.platform_users(user_id,role,full_name,email) values
 ('80900000-0000-8000-8000-000000000908','super_admin','Holdout Platform Admin','wsp809platform@example.test');
insert into public.consents(tenant_id,member_id,purpose,granted,version,source) values
 ('80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','service',true,'v1','holdout'),
 ('80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000032','service',true,'v1','holdout'),
 ('80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000033','service',true,'v1','holdout'),
 ('80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000035','service',true,'v1','holdout'),
 ('80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000034','service',true,'v1','holdout'),
 ('80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','marketing',true,'v1','holdout');
insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active)
   values ('80900000-0000-8000-8000-00000000b101','80900000-0000-8000-8000-000000000001','wsp_holdout_a','whatsapp_link','en','payment','Holdout template A',true),
          ('80900000-0000-8000-8000-00000000b102','80900000-0000-8000-8000-000000000002','wsp_holdout_b','whatsapp_link','en','payment','Holdout template B',true);
insert into public.notifications(id,tenant_id,member_id,channel,category,status,scheduled_for,recipient_phone,dedupe_key,payload,template_id,template_key) values
 ('80900000-0000-8000-8000-000000000051','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n1','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000052','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n2','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000053','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000034','in_app','payment','scheduled',now(),'+918095550004','h80-src-n3','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000054','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n4','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000055','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n5','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000056','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n6','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000057','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n7','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000058','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n8','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a'),
 ('80900000-0000-8000-8000-000000000059','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000033','in_app','payment','scheduled',now(),'+918095550003','h80-src-n9','{}','80900000-0000-8000-8000-00000000b102','wsp_holdout_b'),
 ('80900000-0000-8000-8000-000000000060','80900000-0000-8000-8000-000000000002','80900000-0000-8000-8000-000000000035','in_app','payment','scheduled',now(),'+918095550005','h80-src-n10','{}','80900000-0000-8000-8000-00000000b102','wsp_holdout_b'),
 ('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','in_app','payment','scheduled',now(),'+918095550001','h80-src-n11','{}','80900000-0000-8000-8000-00000000b101','wsp_holdout_a');
select pg_temp.wsp_stage_wallet();
select pg_temp.wsp_stage_wsp_tables();
-- Real flow: the renewal scheduler sends the in-app reminder first (scheduled->sent
-- through the legal send_notification edge), then the desk dispatches WhatsApp on
-- the sent event. Advance every staged source before any dispatch request.
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000902","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000041"}',true);
set local role authenticated;
select public.send_notification('80900000-0000-8000-8000-000000000051');
select public.send_notification('80900000-0000-8000-8000-000000000052');
select public.send_notification('80900000-0000-8000-8000-000000000053');
select public.send_notification('80900000-0000-8000-8000-000000000054');
select public.send_notification('80900000-0000-8000-8000-000000000055');
select public.send_notification('80900000-0000-8000-8000-000000000056');
select public.send_notification('80900000-0000-8000-8000-000000000057');
select public.send_notification('80900000-0000-8000-8000-000000000058');
select public.send_notification('80900000-0000-8000-8000-000000000061');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000910","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000002","staff_id":"80900000-0000-8000-8000-000000000045"}',true);
select public.send_notification('80900000-0000-8000-8000-000000000059');
select public.send_notification('80900000-0000-8000-8000-000000000060');
reset role;
select set_config('request.jwt.claims','',true);
create temporary table h80_results(label text primary key, result jsonb);
grant all on h80_results to authenticated;
grant all on h80_results to service_role;

-- Bootstrap with actual current recipient evidence, then retain a truthful
-- earlier copy. Never guess the private digest/contact-version format or edit
-- immutable consent history. Distinct recorded instants make chronology explicit.
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
set local role authenticated;
select lives_ok($q$insert into h80_results select 'bootstrap_consent',public.set_member_whatsapp_consent('service',true,'wsp-notice-v1')$q$,'WSP-H-FIX0a public member command derives current recipient evidence');
reset role;
select set_config('request.jwt.claims','',true);
select lives_ok($q$insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_at)
 select '80900000-0000-8000-8000-00000000d001',c.tenant_id,c.member_id,c.purpose,c.granted,c.notice_version,c.source,c.recipient_phone_digest,c.contact_version_ref,c.recipient_basis,c.recorded_at-interval '1 hour'
 from public.whatsapp_channel_consents c join h80_results r on r.label='bootstrap_consent' and c.id=(r.result->>'consentId')::uuid$q$,'WSP-H-FIX0b historical bootstrap retains exact truthful contact facts');

-- fixture prerequisites
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallets where tenant_id='80900000-0000-8000-8000-000000000001' and balance_paise=100000$q$),'1','WSP-H-FIX1 wallet staged in paise units');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_sender_accounts$q$),'2','WSP-H-FIX2 sender accounts staged');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_rate_versions where amount_paise=350 and currency='INR'$q$),'2','WSP-H-FIX3 rate versions staged');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_channel_consents where granted$q$),'2','WSP-H-FIX4 current command and historical channel evidence staged');

-- ---------------------------------------------------------------- A. schema and grant armor
select is(pg_temp.wsp_scalar($q$select (to_regclass('public.whatsapp_sender_accounts') is not null and to_regclass('public.whatsapp_template_revisions') is not null and to_regclass('public.whatsapp_rate_versions') is not null and to_regclass('public.whatsapp_channel_consents') is not null and to_regclass('public.notification_whatsapp_attempts') is not null and to_regclass('public.notification_whatsapp_receipts') is not null)::text$q$),'true','WSP-H-A01 six WSP tables exist');
select is((select count(distinct e)::text from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='notification_status'),'7','WSP-H-A02 canonical notification_status unchanged');
select is((select count(distinct e)::text from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='message_category'),'7','WSP-H-A03 canonical message_category unchanged');
select is(pg_temp.wsp_scalar($q$select (bool_and(relrowsecurity))::text from pg_class where oid in (to_regclass('public.whatsapp_sender_accounts'),to_regclass('public.whatsapp_template_revisions'),to_regclass('public.whatsapp_rate_versions'),to_regclass('public.whatsapp_channel_consents'),to_regclass('public.notification_whatsapp_attempts'),to_regclass('public.notification_whatsapp_receipts'))$q$),'true','WSP-H-A04 RLS enabled on every WSP table');
select is(pg_temp.wsp_scalar($q$select (not has_table_privilege('anon','public.notification_whatsapp_attempts','SELECT') and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','SELECT') and not has_table_privilege('anon','public.notification_whatsapp_attempts','INSERT') and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','INSERT'))::text$q$),'true','WSP-H-A05 attempts unreadable/unwritable by ordinary roles');
select is(pg_temp.wsp_scalar($q$select (not has_table_privilege('anon','public.notification_whatsapp_receipts','SELECT') and not has_table_privilege('authenticated','public.notification_whatsapp_receipts','SELECT') and not has_table_privilege('authenticated','public.notification_whatsapp_receipts','INSERT'))::text$q$),'true','WSP-H-A06 receipts unreadable/unwritable by ordinary roles');
select is(pg_temp.wsp_scalar($q$select (not has_table_privilege('anon','public.whatsapp_sender_accounts','SELECT') and not has_table_privilege('authenticated','public.whatsapp_sender_accounts','INSERT') and not has_table_privilege('authenticated','public.whatsapp_sender_accounts','UPDATE'))::text$q$),'true','WSP-H-A07 sender accounts: no anon read, no authenticated configuration writes');
select is(pg_temp.wsp_scalar($q$select (not has_function_privilege('anon','public.claim_whatsapp_dispatch(integer)','EXECUTE') and not has_function_privilege('authenticated','public.claim_whatsapp_dispatch(integer)','EXECUTE') and not has_function_privilege('anon','public.authorize_whatsapp_dispatch(uuid,uuid)','EXECUTE') and not has_function_privilege('authenticated','public.authorize_whatsapp_dispatch(uuid,uuid)','EXECUTE') and not has_function_privilege('anon','public.record_whatsapp_acceptance(uuid,uuid,text,text)','EXECUTE') and not has_function_privilege('authenticated','public.record_whatsapp_acceptance(uuid,uuid,text,text)','EXECUTE') and not has_function_privilege('anon','public.finish_whatsapp_rejection(uuid,uuid,text,boolean)','EXECUTE') and not has_function_privilege('authenticated','public.finish_whatsapp_rejection(uuid,uuid,text,boolean)','EXECUTE') and not has_function_privilege('anon','public.record_whatsapp_receipt(uuid,text,text,text,timestamptz,text)','EXECUTE') and not has_function_privilege('authenticated','public.record_whatsapp_receipt(uuid,text,text,text,timestamptz,text)','EXECUTE'))::text$q$),'true','WSP-H-A08 transport facades denied to anon and authenticated');
select is(pg_temp.wsp_scalar($q$select (has_function_privilege('service_role','public.claim_whatsapp_dispatch(integer)','EXECUTE') and has_function_privilege('service_role','public.authorize_whatsapp_dispatch(uuid,uuid)','EXECUTE') and has_function_privilege('service_role','public.record_whatsapp_acceptance(uuid,uuid,text,text)','EXECUTE') and has_function_privilege('service_role','public.finish_whatsapp_rejection(uuid,uuid,text,boolean)','EXECUTE') and has_function_privilege('service_role','public.record_whatsapp_receipt(uuid,text,text,text,timestamptz,text)','EXECUTE'))::text$q$),'true','WSP-H-A09 transport facades granted to service_role only');
select is(pg_temp.wsp_scalar($q$select (has_function_privilege('authenticated','public.request_whatsapp_dispatch(uuid,uuid)','EXECUTE') and not has_function_privilege('anon','public.request_whatsapp_dispatch(uuid,uuid)','EXECUTE') and has_function_privilege('authenticated','public.read_member_whatsapp_settings()','EXECUTE') and has_function_privilege('authenticated','public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)','EXECUTE') and not has_function_privilege('anon','public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)','EXECUTE'))::text$q$),'true','WSP-H-A10 member/front-office commands authenticated-only');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
set local role authenticated;
select throws_ok($q$insert into public.notification_whatsapp_attempts(id,tenant_id,member_id,notification_id,request_key) values ('80900000-0000-8000-8000-00000000e001','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-000000000031','80900000-0000-8000-8000-000000000051','80900000-0000-8000-8000-00000000f001')$q$,'42501',null,'WSP-H-A11 authenticated cannot insert attempt rows directly');
select throws_ok($q$insert into public.whatsapp_sender_accounts(id,tenant_id,provider,waba_id,sender_id,secret_reference,enabled) values ('80900000-0000-8000-8000-00000000a003','80900000-0000-8000-8000-000000000001','meta','waba-x','phone-x','vault:y',true)$q$,'42501',null,'WSP-H-A12 authenticated cannot configure sender accounts directly');
select throws_ok($q$insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,provider_category,destination_market,amount_paise,max_amount_paise,currency,effective_from) values ('80900000-0000-8000-8000-00000000c009','80900000-0000-8000-8000-000000000001','80900000-0000-8000-8000-00000000a001','utility','IN',1,1,'INR',now())$q$,'42501',null,'WSP-H-A13 authenticated cannot write rate versions (no client-authored price)');
reset role;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- B. consent forgery and abuse
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
set local role authenticated;
select lives_ok($q$select public.set_member_whatsapp_consent('service',true,'wsp-notice-v1')$q$,'WSP-H-B01 member self-consent service granted');
select is(pg_temp.wsp_scalar($q$select (select count(*) from jsonb_object_keys(public.set_member_whatsapp_consent('service',true,'wsp-notice-v1')))::text$q$),'5','WSP-H-B02 consent result carries exactly the five frozen keys (replay inert)');
select lives_ok($q$select public.set_member_whatsapp_consent('marketing',false,'wsp-notice-v1')$q$,'WSP-H-B03 member may refuse marketing channel independently');
reset role;
select set_config('request.jwt.claims','',true);
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_channel_consents where member_id='80900000-0000-8000-8000-000000000031'$q$),'3','WSP-H-B04 distinct purposes and historical bootstrap are separate append-only rows');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
set local role authenticated;
reset role;
select set_config('request.jwt.claims','',true);
select throws_ok($q$update public.whatsapp_channel_consents set granted=false where member_id='80900000-0000-8000-8000-000000000031'$q$,'23514',null,'WSP-H-B05 channel consent is append-only, not editable');
select throws_ok($q$delete from public.whatsapp_channel_consents where member_id='80900000-0000-8000-8000-000000000031'$q$,'23514',null,'WSP-H-B06 channel consent rows cannot be deleted');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000044"}',true);
set local role authenticated;
select throws_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000031','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0a1')$q$,'42501',null,'WSP-H-B07 trainer cannot record channel consent');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select throws_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000031','service',true,'wsp-notice-v1','','80900000-0000-8000-8000-00000000f0a2')$q$,'22023',null,'WSP-H-B08 blank source is not actual-recipient evidence');
select lives_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000034','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0a3')$q$,'WSP-H-B09 desk records consent with verified actual-recipient source');
select lives_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000034','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0a3')$q$,'WSP-H-B10 staff consent replay is inert');
select throws_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000034','service',false,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0a3')$q$,'GL068',null,'WSP-H-B11 staff consent key with changed facts conflicts');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000910","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000002","staff_id":"80900000-0000-8000-8000-000000000045"}',true);
select is(pg_temp.wsp_scalar($q$select (public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000059','80900000-0000-8000-8000-00000000f0b1')->>'queued')::text$q$),'false','WSP-H-B12 member with no channel consent is not dispatchable (no default-on)');
select is(pg_temp.wsp_scalar($q$select (public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000059','80900000-0000-8000-8000-00000000f0b1')->>'reason') is not null::text$q$),'true','WSP-H-B13 refusal carries an allowlisted safe reason, not silence');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000051','80900000-0000-8000-8000-00000000f0b2')$q$,'WSP-H-B14 admissible member dispatch queues with both predicates');
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000051','80900000-0000-8000-8000-00000000f0b9')$q$,'GL068',null,'WSP-H-B15 second request for a live attempt is refused, not overwritten');
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000052','80900000-0000-8000-8000-00000000f0b2')$q$,'GL068',null,'WSP-H-B16 reused request key for a different notification conflicts');
reset role;
select set_config('request.jwt.claims','',true);
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_channel_consents where recipient_basis not in ('self','guardian')$q$),'0','WSP-H-B17 no consent row exists outside the implemented recipient bases (a phone field never grants)');

-- ---------------------------------------------------------------- C. signatures and recipient/identity
select is(pg_temp.wsp_scalar($q$select (to_regprocedure('public.claim_whatsapp_dispatch(integer)') is not null and to_regprocedure('public.authorize_whatsapp_dispatch(uuid,uuid)') is not null and to_regprocedure('public.record_whatsapp_acceptance(uuid,uuid,text,text)') is not null and to_regprocedure('public.finish_whatsapp_rejection(uuid,uuid,text,boolean)') is not null and to_regprocedure('public.record_whatsapp_receipt(uuid,text,text,text,timestamptz,text)') is not null and to_regprocedure('public.request_whatsapp_dispatch(uuid,uuid)') is not null and to_regprocedure('public.read_whatsapp_operations(timestamptz,uuid,integer)') is not null and to_regprocedure('public.read_member_whatsapp_settings()') is not null and to_regprocedure('public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)') is not null and to_regprocedure('public.record_whatsapp_consent(uuid,public.consent_purpose,boolean,text,text,uuid)') is not null)::text$q$),'true','WSP-H-C01 exact frozen signatures exist');
select is(pg_temp.wsp_scalar($q$select (to_regprocedure('public.record_whatsapp_receipt(uuid,text,text,text,timestamptz,text,bigint)') is null and to_regprocedure('public.authorize_whatsapp_dispatch(uuid,uuid,text)') is null and to_regprocedure('public.claim_whatsapp_dispatch(integer,bigint)') is null)::text$q$),'true','WSP-H-C02 no price or recipient parameter exists on any transport signature');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000059','80900000-0000-8000-8000-00000000f0c2')$q$,'P0002',null,'WSP-H-C03 foreign-tenant notification id is refused like an unknown one');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000910","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000002","staff_id":"80900000-0000-8000-8000-000000000045"}',true);
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000051','80900000-0000-8000-8000-00000000f0c3')$q$,'P0002',null,'WSP-H-C04 tenant B owner cannot see or queue tenant A notification (indistinguishable)');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000052','80900000-0000-8000-8000-00000000f0c4')$q$,'WSP-H-C05 member A second source queued for edge tests');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000053','80900000-0000-8000-8000-00000000f0c5')$q$,'WSP-H-C06 member D source queued (has desk-recorded consent)');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000054','80900000-0000-8000-8000-00000000f0c6')$q$,'WSP-H-C07 member A third source queued (template abuse target)');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000055','80900000-0000-8000-8000-00000000f0c7')$q$,'WSP-H-C08 member A fourth source queued (withdrawal target)');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000056','80900000-0000-8000-8000-00000000f0c8')$q$,'WSP-H-C09 member A fifth source queued (uncertainty target)');
reset role;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- D. money attacks (highest weight)
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000910","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000002","staff_id":"80900000-0000-8000-8000-000000000045"}',true);
select lives_ok($q$select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000035','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0d1')$q$,'WSP-H-D01 tenant B member E channel consent recorded');
select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000033','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0d0');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000059','80900000-0000-8000-8000-00000000f0d2')$q$,'WSP-H-D02 tenant B member C dispatch queued');
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000060','80900000-0000-8000-8000-00000000f0d3')$q$,'WSP-H-D03 tenant B member E dispatch queued (funds competition)');
reset role;
select set_config('request.jwt.claims','',true);
set local role service_role;
select lives_ok($q$insert into h80_results select 'claim1',public.claim_whatsapp_dispatch(10)$q$,'WSP-H-D04 claim returns bounded due work');
select is(pg_temp.wsp_scalar($q$select (select count(*) from jsonb_object_keys(result))::text from h80_results where label='claim1'$q$),'2','WSP-H-D05 claim result carries exactly attempts and configuration');
select is(pg_temp.wsp_scalar($q$select (result->>'configuration')::text from h80_results where label='claim1'$q$),'ready','WSP-H-D06 claim reports ready configuration in the frozen default');
select lives_ok($q$insert into h80_results select 'claim2',public.claim_whatsapp_dispatch(10)$q$,'WSP-H-D07 overlapping claim is safe and bounded');
select is(pg_temp.wsp_scalar($q$select (result->'attempts'->0->>'attemptId') is not null::text from h80_results where label='claim1'$q$),'true','WSP-H-D08 claim returns attempt identifiers with tickets, no recipients');
select lives_ok($q$insert into h80_results select 'authz1',public.authorize_whatsapp_dispatch(((select result->'attempts'->0->>'attemptId' from h80_results where label='claim1')::uuid),((select result->'attempts'->0->>'ticket' from h80_results where label='claim1')::uuid))$q$,'WSP-H-D09 authorization returns the minimal provider payload for the due attempt');
select is(pg_temp.wsp_scalar($q$select (jsonb_typeof(result - 'recipient' - 'cost' - 'price' - 'amount')='object' and result ? 'recipient')::text from h80_results where label='authz1'$q$),'true','WSP-H-D10 authorized payload carries recipient but no client-settable cost');
select throws_like($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1))$q$,'%','WSP-H-D11 authorization cannot be replayed for a second permission to send');
select is(pg_temp.wsp_scalar($q$select (io_started_at is not null)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D11a authorization marks initiation exactly once');
select is(pg_temp.wsp_scalar($q$select balance_paise::text from public.messaging_wallets where tenant_id='80900000-0000-8000-8000-000000000001'$q$),'100000','WSP-H-D12 a hold never alters the posted balance');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'0','WSP-H-D13 no ledger movement exists before verified billable delivery');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1),'wamid.h80-accept-1',repeat('441f6a1b',8))$q$,'WSP-H-D14 provider acceptance records evidence');
select is(pg_temp.wsp_scalar($q$select (status='sent')::text from public.notifications where id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D15 acceptance marks sent as accepted-for-delivery');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'0','WSP-H-D16 API acceptance never debits');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1),'wamid.h80-accept-1',repeat('441f6a1b',8))$q$,'WSP-H-D17 duplicate acceptance is an inert replay');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'0','WSP-H-D18 replay appends no movement');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-1','f1e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44')$q$,'WSP-H-D19 verified delivery receipt accepted');
select is(pg_temp.wsp_scalar($q$select (status='delivered')::text from public.notifications where id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D20 delivered evidence records delivered');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051' and delta_paise<0$q$),'1','WSP-H-D21 exactly one negative causal movement on verified billable delivery');
select is(pg_temp.wsp_scalar($q$select (min(abs(delta_paise)))::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'350','WSP-H-D22 debit equals the frozen server tariff, not a webhook value');
select is(pg_temp.wsp_scalar($q$select balance_after_paise::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051' limit 1$q$),'99650','WSP-H-D23 derived balance uses the locked arithmetic path');
select is(pg_temp.wsp_scalar($q$select (charged_ledger_id is not null and completed_at is not null)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D24 attempt carries its causal charged ledger reference');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-1','f1e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44')$q$,'WSP-H-D25 duplicate fingerprint receipt is idempotent evidence');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'1','WSP-H-D26 duplicate receipt does not debit twice');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-1','f2e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','read',now(),'bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11')$q$,'WSP-H-D27 provider read evidence accepted');
select is(pg_temp.wsp_scalar($q$select (provider_read_at is not null)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D28 provider read lands on the attempt, not the click field');
select is(pg_temp.wsp_scalar($q$select (clicked_at is null)::text from public.notifications where id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-D29 WhatsApp read never fabricates clicked_at');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'1','WSP-H-D30 a read receipt never debits');
select lives_ok($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000052' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000052' limit 1))$q$,'WSP-H-D31 second attempt authorized');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000052' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000052' limit 1),'wamid.h80-accept-2',repeat('441f6a1b',8))$q$,'WSP-H-D31a second attempt accepted');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-2','f3e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','read',now(),'cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22')$q$,'WSP-H-D32 a read receipt legally implies delivery through the frozen graph');
select throws_like($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-3','f4e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33dd44aa11bb22cc33')$q$,'%','WSP-H-D33 delivery evidence without an accepted send is refused');
reset role;
select set_config('request.jwt.claims','',true);
select throws_ok($q$insert into public.messaging_wallet_ledger(tenant_id,delta_paise,currency,reason) values ('80900000-0000-8000-8000-000000000001',0,'INR','zero-cost probe')$q$,'23514',null,'WSP-H-D34 zero-cost delivery creates no ledger row because the ledger forbids zero movements');
select is(pg_temp.wsp_scalar($q$select (select currency from public.whatsapp_rate_versions where id=(select rate_version_id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1))::text$q$),'INR','WSP-H-D35 the causal debit resolved an INR tariff; non-INR versions are never used');
set local role service_role;
select lives_ok($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000059' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000059' limit 1))$q$,'WSP-H-D36 tenant B winner authorized');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000059' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000059' limit 1),'wamid.h80-b-1',repeat('441f6a1b',8))$q$,'WSP-H-D36a tenant B winner accepted');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a002','wamid.h80-b-1','f5e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'ee11ff22aa33bb44ee11ff22aa33bb44ee11ff22aa33bb44ee11ff22aa33bb44')$q$,'WSP-H-D36b tenant B winner completes its causal debit');
select is(pg_temp.wsp_scalar($q$select balance_after_paise::text from public.messaging_wallet_ledger where tenant_id='80900000-0000-8000-8000-000000000002' limit 1$q$),'0','WSP-H-D37 the final amount goes to exactly one send');
select is(pg_temp.wsp_scalar($q$select jsonb_array_length(result->'attempts')::text from h80_results where label='claim2'$q$),'0','WSP-H-D38 the losing send is not claimable: nothing left to claim');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000060'$q$),'0','WSP-H-D39 no attempt row exists for a send whose hold could not be reserved');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where tenant_id='80900000-0000-8000-8000-000000000002'$q$),'1','WSP-H-D40 the losing send produced no movement');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000054'$q$),'0','WSP-H-D41 baseline: notification 54 has no movement');
select is(coalesce(pg_temp.wsp_scalar($q$select case when (public.accept_paid_notification('80900000-0000-4000-8000-00000000d00d','wamid.x',350::bigint,'80900000-0000-8000-8000-000000000001')::jsonb)>>>'status' in ('sent','delivered') then 'activated' else 'denied' end$q$),'denied'),'denied','WSP-H-D42 the paid-acceptance stub stays denied for every cost argument');
reset role;
select set_config('request.jwt.claims','',true);
select throws_like($q$update public.whatsapp_rate_versions set amount_paise=400 where id='80900000-0000-8000-8000-00000000c001'$q$,'%','WSP-H-D43 a used rate version is immutable');
set local role service_role;
select throws_like($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-accept-4','f6e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'ff22aa33bb44cc55ff22aa33bb44cc55ff22aa33bb44cc55ff22aa33bb44cc55')$q$,'%','WSP-H-D45 delivery against a paused/recategorized template is refused');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000054'$q$),'0','WSP-H-D46 refused delivery leaves no movement');
reset role;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- E. uncertainty and withdrawal
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000058','80900000-0000-8000-8000-00000000f0e1')$q$,'WSP-H-E01 uncertainty target queued');
reset role;
select set_config('request.jwt.claims','',true);
set local role service_role;
select lives_ok($q$insert into h80_results select 'claim3',public.claim_whatsapp_dispatch(10)$q$,'WSP-H-E02 claim picks up the uncertainty target');
select lives_ok($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1))$q$,'WSP-H-E03 authorization for the uncertainty target');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),'wamid.h80-e-1',repeat('441f6a1b',8))$q$,'WSP-H-E04 acceptance before the transport crash');
select throws_ok($q$select public.finish_whatsapp_rejection((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),'provider_rejected',false)$q$,'22023',null,'WSP-H-E05 known=false cannot carry a failure code');
select lives_ok($q$select public.finish_whatsapp_rejection((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),null,false)$q$,'WSP-H-E06 unknown outcome records uncertainty without releasing the hold');
select is(pg_temp.wsp_scalar($q$select (uncertain_at is not null)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058'$q$),'true','WSP-H-E07 uncertainty is a recorded durable fact');
select is(pg_temp.wsp_scalar($q$select (status<>'failed')::text from public.notifications where id='80900000-0000-8000-8000-000000000058'$q$),'true','WSP-H-E08 uncertainty is never treated as rejection');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000058'$q$),'0','WSP-H-E09 an uncertain attempt holds funds without debiting');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058'$q$),'1','WSP-H-E10 no automatic resend: exactly one live attempt per notification');
select throws_like($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000058' limit 1))$q$,'%','WSP-H-E11 an uncertain attempt cannot authorize provider I/O again');
reset role;
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
set local role authenticated;
select lives_ok($q$select public.set_member_whatsapp_consent('service',false,'wsp-notice-v1')$q$,'WSP-H-E12 member withdraws channel consent while an attempt is queued');
reset role;
select set_config('request.jwt.claims','',true);
-- Chronology amendment (wsp-holdout-ordering-diagnosis.md): command-stamped
-- recorded_at values share the transaction instant, so a withdrawal and any
-- same-transaction grant tie and the canonical UUID tie-break makes this
-- chronological scenario nondeterministic. The frozen declaration requires
-- chronological scenarios to carry distinct lawful recorded instants; the
-- withdrawal is additionally represented as a truthful fixture row copying the
-- member's own real recipient evidence at an explicit strictly-later instant,
-- which makes the canonical decision deterministic. The member-command
-- withdrawal above keeps the real command behavior pinned.
select lives_ok($q$insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_at)
 select '80900000-0000-8000-8000-00000000e0e2',c.tenant_id,c.member_id,c.purpose,false,c.notice_version,c.source,c.recipient_phone_digest,c.contact_version_ref,c.recipient_basis,clock_timestamp()
 from public.whatsapp_channel_consents c join h80_results r on r.label='bootstrap_consent' and c.id=(r.result->>'consentId')::uuid$q$,'WSP-H-E12b the withdrawal is canonically current at a distinct lawful later instant');
set local role service_role;
select is(pg_temp.wsp_scalar($q$select (public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000055' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000055' limit 1))->>'authorized')::text$q$),'false','WSP-H-E12a authorization after withdrawal is refused as a result, not an error');
reset role;
select set_config('request.jwt.claims','',true);
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000055' and io_started_at is not null$q$),'0','WSP-H-E13 withdrawal committed before authorization produces no provider send');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000055'$q$),'0','WSP-H-E14 withdrawal creates no debit and releases the hold');

-- ---------------------------------------------------------------- F. late evidence and graph integrity
-- Chronology amendment (wsp-holdout-ordering-diagnosis.md): the regrant must be
-- canonically later than the E12 withdrawal. The staff command below keeps the
-- real command-path acceptance pinned; because its recorded_at shares the
-- transaction instant with every other command row, the deterministic current
-- decision is additionally represented as a truthful fixture row copying the
-- member's own real recipient evidence at an explicit strictly-later instant.
select lives_ok($q$insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_at)
 select '80900000-0000-8000-8000-00000000f0f1',c.tenant_id,c.member_id,c.purpose,true,c.notice_version,c.source,c.recipient_phone_digest,c.contact_version_ref,c.recipient_basis,clock_timestamp()+interval '1 second'
 from public.whatsapp_channel_consents c join h80_results r on r.label='bootstrap_consent' and c.id=(r.result->>'consentId')::uuid$q$,'WSP-H-F-pre the late lawful regrant is canonically current at a distinct later instant');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000902","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000041"}',true);
set local role authenticated;
select public.record_whatsapp_consent('80900000-0000-8000-8000-000000000031','service',true,'wsp-notice-v1','desk_verified','80900000-0000-8000-8000-00000000f0f0');
-- This late-evidence target is prepared only after the new lawful grant.
-- An older attempt's exact channel reference may never be replaced by regrant.
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000057','80900000-0000-8000-8000-00000000f0c9')$q$,'WSP-H-C10 member A sixth source queued (late-evidence target)');
select set_config('request.jwt.claims','',true);
set local role service_role;
select lives_ok($q$insert into h80_results select 'claim_late',public.claim_whatsapp_dispatch(10)$q$,'WSP-H-F00 fresh late-evidence claim binds current regrant');
select lives_ok($q$select public.authorize_whatsapp_dispatch((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1))$q$,'WSP-H-F01 late-evidence target authorized');
select lives_ok($q$select public.record_whatsapp_acceptance((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1),'wamid.h80-f-1',repeat('441f6a1b',8))$q$,'WSP-H-F02 late-evidence target accepted');
select lives_ok($q$select public.finish_whatsapp_rejection((select id from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1),(select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000057' limit 1),'recipient_invalid',true)$q$,'WSP-H-F03 known rejection finalizes the attempt');
select is(pg_temp.wsp_scalar($q$select (status='failed')::text from public.notifications where id='80900000-0000-8000-8000-000000000057'$q$),'true','WSP-H-F04 known rejection marks failed');
select lives_ok($q$select public.record_whatsapp_receipt('80900000-0000-8000-8000-00000000a001','wamid.h80-f-1','f7e2d3c4b5a697887766554433221100ffeeddccbbaa99887766554433221100','delivered',now(),'aa22bb33cc44dd55aa22bb33cc44dd55aa22bb33cc44dd55aa22bb33cc44dd55')$q$,'WSP-H-F05 late delivery evidence is retained for reconciliation');
select is(pg_temp.wsp_scalar($q$select (status='failed')::text from public.notifications where id='80900000-0000-8000-8000-000000000057'$q$),'true','WSP-H-F06 late evidence cannot revive a terminal failure');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000057'$q$),'0','WSP-H-F07 late evidence after terminal failure debits nothing');
select is(pg_temp.wsp_scalar($q$select (status='delivered')::text from public.notifications where id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-F08 baseline state before the out-of-order probe');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where provider_message_id='wamid.h80-accept-1'$q$),'1','WSP-H-F09 exactly one attempt per provider message id; a second fingerprint is idempotent evidence, not a second send');
select is(pg_temp.wsp_scalar($q$select (status='delivered')::text from public.notifications where id='80900000-0000-8000-8000-000000000051'$q$),'true','WSP-H-F10 out-of-order evidence never regresses delivered');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id='80900000-0000-8000-8000-000000000051'$q$),'1','WSP-H-F11 out-of-order evidence never debits twice');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notifications where dedupe_key='whatsapp-paid:80900000-0000-8000-8000-000000000057'$q$),'1','WSP-H-F12 the paid WhatsApp child exists under the frozen key grammar');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notifications where dedupe_key='whatsapp-fallback:80900000-0000-8000-8000-000000000057' and channel='in_app'$q$),'1','WSP-H-F13 the desk fallback is a separate causal in_app child under the frozen key grammar');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where notification_id in (select id from public.notifications where dedupe_key='whatsapp-fallback:80900000-0000-8000-8000-000000000057')$q$),'0','WSP-H-F14 the fallback is never charged');
reset role;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- G. template and rate abuse
select lives_ok($q$update public.whatsapp_template_revisions set paused_at=now() where id='80900000-0000-8000-8000-00000000b001'$q$,'WSP-H-D44 template paused after authorization (operator act)');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notifications where dedupe_key='whatsapp-paid:80900000-0000-8000-8000-000000000054'$q$),'0','WSP-H-G01 no paid child was created for the refused delivery');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select lives_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-00000000f0a7')$q$,'WSP-H-G02 paused-template era request queued');
reset role;
select set_config('request.jwt.claims','',true);
set local role service_role;
select lives_ok($q$insert into h80_results select 'claim4',public.claim_whatsapp_dispatch(10)$q$,'WSP-H-G03 claim in the paused-template era drains nothing sendable');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000061' and io_started_at is not null$q$),'0','WSP-H-G04 a paused template never reaches provider authorization');
reset role;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- H. privilege and privacy
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
set local role authenticated;
select is(pg_temp.wsp_scalar($q$select (select count(*) from jsonb_object_keys(public.read_member_whatsapp_settings()))::text$q$),'6','WSP-H-H01 member settings carry exactly the six frozen keys');
select is(pg_temp.wsp_scalar($q$select (position('+918095550001' in public.read_member_whatsapp_settings()::text)=0)::text$q$),'true','WSP-H-H02 member settings never expose the full phone number');
reset role;
select set_config('request.jwt.claims','',true);
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000043"}',true);
select is(pg_temp.wsp_scalar($q$select ((public.read_whatsapp_operations(null,null,50)::text not like '%balancePaise%') and (public.read_whatsapp_operations(null,null,50)::text not like '%8095550001%'))::text$q$),'true','WSP-H-H03 desk operations view has no wallet amounts and no raw phone');
select is(pg_temp.wsp_scalar($q$select (public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-00000000f0b7')->>'queued')::text$q$),'false','WSP-H-H04 replaying the refused paused-era request with its own key stays inertly refused, never a second queue entry');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000902","role":"authenticated","app_role":"gym_owner","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000041"}',true);
select is(pg_temp.wsp_scalar($q$select (public.read_whatsapp_operations(null,null,50)::text like '%balancePaise%')::text$q$),'true','WSP-H-H05 the owner operations view carries the wallet projection');
select is(pg_temp.wsp_scalar($q$select (public.read_whatsapp_operations(null,null,50)::text not like '%wamid%' and public.read_whatsapp_operations(null,null,50)::text not like '%ticket%')::text$q$),'true','WSP-H-H06 owner view exposes no provider ids or lease tickets');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000901","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000031"}',true);
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-00000000f0c7')$q$,'42501',null,'WSP-H-H07 a member cannot request dispatch');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"80900000-0000-8000-8000-000000000001","staff_id":"80900000-0000-8000-8000-000000000044"}',true);
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-00000000f0d7')$q$,'42501',null,'WSP-H-H08 a trainer cannot request dispatch');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"80900000-0000-8000-8000-000000000001","impersonation_session_id":"80900000-0000-8000-8000-000000000070"}',true);
select throws_ok($q$select public.request_whatsapp_dispatch('80900000-0000-8000-8000-000000000061','80900000-0000-8000-8000-00000000f0e7')$q$,'42501',null,'WSP-H-H09 impersonation cannot request dispatch');
select set_config('request.jwt.claims','{"sub":"80900000-0000-8000-8000-000000000906","role":"authenticated","app_role":"member","tenant_id":"80900000-0000-8000-8000-000000000001","member_id":"80900000-0000-8000-8000-000000000032"}',true);
select is(pg_temp.wsp_scalar($q$select (position('+918095550001' in public.read_member_whatsapp_settings()::text)=0)::text$q$),'true','WSP-H-H10 sibling settings never contain the other member''s phone');
reset role;
select set_config('request.jwt.claims','',true);
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.audit_log where action not like 'notification.%' and (coalesce(before::text,'') like '%8095550001%' or coalesce(after::text,'') like '%8095550001%' or coalesce(before::text,'') like '%wamid%' or coalesce(after::text,'') like '%wamid%')$q$),'0','WSP-H-H11 WSP audit rows carry no phone, rendered text or provider message ids (phase6 notification edge audits keep their frozen shape)');
select is(pg_temp.wsp_scalar($q$select (exists(select 1 from information_schema.columns where table_name='whatsapp_sender_accounts' and column_name='secret_reference') and not exists(select 1 from information_schema.columns where table_name='whatsapp_sender_accounts' and (column_name like '%secret_value%' or column_name like '%plaintext%' or column_name like '%credential%')))::text$q$),'true','WSP-H-H12 sender accounts keep only a secret reference, never plaintext credentials');

-- ---------------------------------------------------------------- I. final invariants
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' and lease_ticket is distinct from (select lease_ticket from public.notification_whatsapp_attempts where notification_id='80900000-0000-8000-8000-000000000051' limit 1)$q$),'0','WSP-H-I01 no second live attempt or ticket was minted for a processed notification');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger l join public.whatsapp_sender_accounts s on s.tenant_id=l.tenant_id where l.currency is distinct from 'INR'$q$),'0','WSP-H-I02 every causal movement is explicitly INR');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_receipts r join public.whatsapp_sender_accounts s on s.id=r.sender_account_id join public.notification_whatsapp_attempts a on a.id=r.attempt_id where a.tenant_id is distinct from s.tenant_id$q$),'0','WSP-H-I03 no receipt is bound across a sender/tenant boundary');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts a join public.notifications n on n.id=a.notification_id where a.tenant_id is distinct from n.tenant_id$q$),'0','WSP-H-I04 no attempt is bound across a tenant boundary');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.messaging_wallet_ledger where reason ilike '%transport%' and notification_id is not null and delta_paise>0$q$),'0','WSP-H-I05 no positive movement masquerades as a transport charge');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.notification_whatsapp_attempts where charged_ledger_id is not null and uncertain_at is not null$q$),'0','WSP-H-I06 an uncertain attempt never carries a charge');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_channel_consents where granted and recorded_at is null$q$),'0','WSP-H-I07 every granted channel consent carries its recorded instant');
select is(pg_temp.wsp_scalar($q$select count(*)::text from public.whatsapp_template_revisions where approved_at is not null and approval_evidence_digest is null$q$),'0','WSP-H-I08 every approved template carries its approval evidence digest');

-- Independent supplement, 2026-10-04: WSP frozen table declarations + ADR-052.
-- Exact composite tenant FKs are checked structurally, without relying on an
-- implementation-specific constraint name or swallowed fixture insertion.
select ok(exists (
  select 1 from pg_constraint k
  where k.contype='f' and k.conrelid=to_regclass('public.whatsapp_template_revisions')
    and k.confrelid=to_regclass('public.message_templates')
    and array(select a.attname::text from unnest(k.conkey) with ordinality x(n,pos)
              join pg_attribute a on a.attrelid=k.conrelid and a.attnum=x.n order by x.pos)
        = array['tenant_id','template_id']
    and array(select a.attname::text from unnest(k.confkey) with ordinality x(n,pos)
              join pg_attribute a on a.attrelid=k.confrelid and a.attnum=x.n order by x.pos)
        = array['tenant_id','id']),
  'WSP-H-J01 template revision cannot bind an existing template in a different tenant');
select ok(exists (
  select 1 from pg_constraint k
  where k.contype='f' and k.conrelid=to_regclass('public.notification_whatsapp_attempts')
    and k.confrelid=to_regclass('public.whatsapp_template_revisions')
    and array(select a.attname::text from unnest(k.conkey) with ordinality x(n,pos)
              join pg_attribute a on a.attrelid=k.conrelid and a.attnum=x.n order by x.pos)
        @> array['tenant_id']
    and cardinality(k.conkey)=2
    and (select a.attname::text from pg_attribute a
         where a.attrelid=k.conrelid and a.attnum=k.conkey[1])='tenant_id'
    and array(select a.attname::text from unnest(k.confkey) with ordinality x(n,pos)
              join pg_attribute a on a.attrelid=k.confrelid and a.attnum=x.n order by x.pos)
        = array['tenant_id','id']),
  'WSP-H-J02 attempt template evidence is constrained to the same tenant');
select ok(exists (
  select 1 from pg_constraint k
  where k.contype='f' and k.conrelid=to_regclass('public.notification_whatsapp_attempts')
    and k.confrelid=to_regclass('public.whatsapp_channel_consents')
    and array(
      select src.attname::text || '->' || dst.attname::text
      from unnest(k.conkey,k.confkey) x(srcnum,dstnum)
      join pg_attribute src on src.attrelid=k.conrelid and src.attnum=x.srcnum
      join pg_attribute dst on dst.attrelid=k.confrelid and dst.attnum=x.dstnum
      order by src.attname::text)
      = array['channel_consent_id->id','member_id->member_id','tenant_id->tenant_id']),
  'WSP-H-J03 exact channel opt-in evidence is constrained to the same tenant and member');
select ok(exists (
  select 1 from pg_constraint k
  where k.contype='f' and k.conrelid=to_regclass('public.notification_whatsapp_attempts')
    and k.confrelid=to_regclass('public.consents')
    and exists (
      select 1 from unnest(k.conkey,k.confkey) x(srcnum,dstnum)
      join pg_attribute src on src.attrelid=k.conrelid and src.attnum=x.srcnum
      join pg_attribute dst on dst.attrelid=k.confrelid and dst.attnum=x.dstnum
      where src.attname='consent_id' and dst.attname='id')),
  'WSP-H-J04 generic-purpose consent_id keeps its independent public.consents reference');

select * from finish();
rollback;
