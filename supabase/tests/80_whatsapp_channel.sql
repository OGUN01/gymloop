-- Harness provenance: catalog readers are STABLE; count(*) pgTAP operands agree as bigint.
-- WSP-001..011 independent visible contract. No cross-session concurrency claimed.
-- Column spellings for the six new WSP tables are the author's pinned natural
-- spellings from the frozen shapes; if the implementer chooses different
-- names, that is an implementer report to the orchestrator, not a test edit.
-- The suite is RED today for three expected reasons: WSP tables absent, WSP
-- functions absent, and the wallet paise columns absent (migration
-- 20261004085000 is committed but not yet applied on Cloud). Every guarded
-- block reports a clean false instead of aborting, so the whole plan runs.
-- Wall-clock ticket expiry and true cross-connection races are left to the
-- holdout/orchestrator rounds (no clock seam in SQL).
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(144);
create function pg_temp.aid(n integer) returns uuid language sql immutable as $f$select ('80100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$f$;
create function pg_temp.claim(r text default 'gym_owner',s integer default 21,m integer default null,u integer default 901,t integer default 1,p boolean default false) returns void language plpgsql as $f$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.aid(u),'role','authenticated','app_role',r,'tenant_id',pg_temp.aid(t),'staff_id',case when s is not null then pg_temp.aid(s) end,'member_id',case when m is not null then pg_temp.aid(m) end,'impersonation_session_id',case when p then pg_temp.aid(999) end))::text,true); end$f$;
create function pg_temp.refusal(q text) returns text language plpgsql as $f$declare detail text; begin begin execute q; raise exception using errcode='Z8000'; exception when others then if sqlstate='Z8000' then return 'SUCCESS'; end if; get stacked diagnostics detail=PG_EXCEPTION_DETAIL; return sqlstate||case when detail<>'' then ':'||detail else '' end; end; end$f$;
create function pg_temp.tbl(q text) returns boolean language sql stable as $f$select to_regclass(q) is not null$f$;
create function pg_temp.hasfn(q text) returns boolean language sql stable as $f$select to_regprocedure(q) is not null$f$;
create function pg_temp.col(tbl text,col text) returns boolean language sql stable as $f$select exists(select 1 from pg_attribute where attrelid=to_regclass(tbl) and attname=col and not attisdropped)$f$;
create function pg_temp.nuniq(tbl text) returns integer language sql stable as $f$select count(*)::integer from pg_indexes where schemaname='public' and tablename=tbl and indexdef ~* 'unique'$f$;
create function pg_temp.nfk(tbl text) returns integer language sql stable as $f$select count(*)::integer from pg_constraint where conrelid=to_regclass(tbl) and contype='f'$f$;
create function pg_temp.shortid(u uuid) returns text language sql immutable as $f$select right(u::text,3)$f$;
create temp table wsp_ids(k text primary key,id uuid not null);
create temp table wsp_txt(k text primary key,v text not null);
grant all on wsp_ids to authenticated,service_role;
grant all on wsp_txt to authenticated,service_role;
grant execute on function pg_temp.aid(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.refusal(text),pg_temp.tbl(text),pg_temp.hasfn(text),pg_temp.col(text,text),pg_temp.nuniq(text),pg_temp.nfk(text) to authenticated,anon,service_role;

-- Chronological historical bootstrap: verify through the public command, then
-- append a distinct truthful decision at a later actual recording instant.
-- Existing immutable consent rows are never edited; tied instants belong only
-- to the independent ordering regression.
create function pg_temp.chronological_channel_decision(m uuid,p public.consent_purpose,g boolean,v text,s text,k uuid) returns jsonb language plpgsql security invoker as $f$
declare r jsonb; actor_claim text; stamp timestamptz;
begin
 r:=public.record_whatsapp_consent(m,p,g,v,s,k);
 actor_claim:=current_setting('request.jwt.claims',true);
 stamp:=clock_timestamp();
 insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at,created_at)
 select gen_random_uuid(),cc.tenant_id,cc.member_id,cc.purpose,g,v,s,cc.recipient_phone_digest,cc.contact_version_ref,cc.recipient_basis,(actor_claim::jsonb->>'staff_id')::uuid,stamp,stamp
 from public.whatsapp_channel_consents cc where cc.tenant_id=(actor_claim::jsonb->>'tenant_id')::uuid and cc.member_id=m and cc.purpose=p order by cc.recorded_at desc,cc.id desc limit 1;
 return r;
end$f$;
-- ---------------------------------------------------------------------------
-- Fixtures (trusted scheduler context)
-- ---------------------------------------------------------------------------
insert into public.organizations(id,name,gym_code,status) values(pg_temp.aid(1),'WSP A','WSP80A','active'),(pg_temp.aid(2),'WSP B','WSP80B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.aid(11),pg_temp.aid(1),'A',true),(pg_temp.aid(12),pg_temp.aid(2),'B',true);
insert into auth.users(id) select pg_temp.aid(n) from generate_series(901,918) n;
insert into public.platform_users(user_id,email,full_name,role,is_active)
values(pg_temp.aid(917),'wsp-super@example.test','WSP SUPER','super_admin',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.aid(21),pg_temp.aid(1),pg_temp.aid(901),pg_temp.aid(11),'gym_owner','Owner'),
(pg_temp.aid(22),pg_temp.aid(1),pg_temp.aid(902),pg_temp.aid(11),'gym_manager','Manager'),
(pg_temp.aid(23),pg_temp.aid(1),pg_temp.aid(903),pg_temp.aid(11),'front_desk','Desk'),
(pg_temp.aid(24),pg_temp.aid(1),pg_temp.aid(904),pg_temp.aid(11),'trainer','Trainer'),
(pg_temp.aid(25),pg_temp.aid(2),pg_temp.aid(905),pg_temp.aid(12),'gym_owner','Other');
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,date_of_birth,status,erased_at,guardian_name,guardian_relation,guardian_phone,guardian_email) values
(pg_temp.aid(101),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(906),'PRIVATE_MEMBER_101','+917500000101','1990-01-01','active',null,null,null,null,null),
(pg_temp.aid(102),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(907),'PRIVATE_MEMBER_102','+917500000102','1990-01-01','paused',null,null,null,null,null),
(pg_temp.aid(104),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(909),'PRIVATE_MEMBER_104','+917500000104','1990-01-01','blocked',null,null,null,null,null),
(pg_temp.aid(106),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(911),'PRIVATE_MEMBER_106','+917500000106','1990-01-01','active',now(),null,null,null,null),
(pg_temp.aid(107),pg_temp.aid(2),pg_temp.aid(12),pg_temp.aid(912),'PRIVATE_FOREIGN_MEMBER','+917500000107','1990-01-01','active',null,null,null,null,null),
(pg_temp.aid(108),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(910),'PRIVATE_MINOR_108','+917500000108','2016-06-15','active',null,'GUARDIAN_108','father','+917500001081','guardian108@example.test'),
(pg_temp.aid(109),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(913),'PRIVATE_MEMBER_109','+917500000109','1990-01-01','active',null,null,null,null,null),
(pg_temp.aid(110),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(914),'PRIVATE_MEMBER_110','+917500000110','1990-01-01','active',null,null,null,null,null),
(pg_temp.aid(111),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(915),'PRIVATE_MEMBER_111','+917500000111','1990-01-01','active',null,null,null,null,null),
(pg_temp.aid(112),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(916),'PRIVATE_MEMBER_112','+917500000112','1990-01-01','active',null,null,null,null,null);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.aid(201),pg_temp.aid(1),'WSP plan',30,100000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,currency) values
(pg_temp.aid(301),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR'),
(pg_temp.aid(302),pg_temp.aid(1),pg_temp.aid(102),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR'),
(pg_temp.aid(303),pg_temp.aid(1),pg_temp.aid(109),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR'),
(pg_temp.aid(304),pg_temp.aid(1),pg_temp.aid(110),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR'),
(pg_temp.aid(305),pg_temp.aid(1),pg_temp.aid(111),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR'),
(pg_temp.aid(306),pg_temp.aid(1),pg_temp.aid(112),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1)),100000,'INR');
insert into public.organization_settings(tenant_id,renewal_reminder_days_from_expiry) values(pg_temp.aid(1),array[0::smallint]);
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at) values
(pg_temp.aid(401),pg_temp.aid(1),pg_temp.aid(101),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(402),pg_temp.aid(1),pg_temp.aid(102),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(403),pg_temp.aid(1),pg_temp.aid(101),'marketing',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(404),pg_temp.aid(1),pg_temp.aid(109),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(405),pg_temp.aid(1),pg_temp.aid(110),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(406),pg_temp.aid(1),pg_temp.aid(111),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(407),pg_temp.aid(1),pg_temp.aid(112),'service',true,'v1','signup',now()-interval '1 day');
insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active)
values(pg_temp.aid(451),pg_temp.aid(1),'wsp_renewal_notice','whatsapp_link','en','renewal','Membership renewal reminder for {{1}}',true);

-- The trusted scheduler creates the in-app renewal source rows the WSP tests
-- dispatch from (expiry_day window: ends today, service consent, dues).
set local role service_role;
select set_config('request.jwt.claims','',true);
create temp table wsp_run as select app.run_renewal_reminders(pg_temp.aid(1)) as r;
set local role postgres;
insert into wsp_ids(k,id)
select 'src_'||pg_temp.shortid(n.member_id), n.id
from public.notifications n
join public.members m on m.id=n.member_id and m.tenant_id=n.tenant_id
where n.tenant_id=pg_temp.aid(1) and n.category='renewal'
  and n.channel='in_app' and n.template_key='renewal_reminder'
  and n.status='sent' and n.related_type='membership';
select set_config('request.jwt.claims','',true);

-- Strict opt-in: members the tests dispatch need a currently-granted
-- WhatsApp channel consent (WSP-002 as amended by the serial decision).
create function pg_temp.visible_tap_block_1() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.tbl('public.whatsapp_channel_consents') then
    return next ok(false,'WSP: channel-consent fixture block red (schema absent)'); return; end if;
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  perform public.record_whatsapp_consent(pg_temp.aid(101),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1461));
  perform public.record_whatsapp_consent(pg_temp.aid(102),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1462));
  perform public.record_whatsapp_consent(pg_temp.aid(109),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1463));
  perform public.record_whatsapp_consent(pg_temp.aid(110),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1464));
  perform public.record_whatsapp_consent(pg_temp.aid(111),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1465));
  perform public.record_whatsapp_consent(pg_temp.aid(112),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1466));
  perform set_config('request.jwt.claims','',true);
end $b$;
select * from pg_temp.visible_tap_block_1();

-- ---------------------------------------------------------------------------
-- S1: canonical enums unchanged
-- ---------------------------------------------------------------------------
select enum_has_labels('public','notification_channel',array['push','whatsapp_link','in_app','sms','email']::name[],'WSP: canonical notification_channel unchanged');
select enum_has_labels('public','notification_status',array['scheduled','sent','delivered','failed','clicked','converted','opted_out']::name[],'WSP: canonical notification_status unchanged');
select enum_has_labels('public','message_category',array['renewal','payment','fulfilment','promotion','motivation','class_update','announcement']::name[],'WSP: canonical message_category unchanged');

-- ---------------------------------------------------------------------------
-- S2: WSP table shapes, grants, RLS, uniques (clean red while absent)
-- ---------------------------------------------------------------------------
select ok(CASE WHEN to_regclass('public.whatsapp_sender_accounts') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.whatsapp_sender_accounts'))
  and not has_table_privilege('authenticated','public.whatsapp_sender_accounts','SELECT')
  and not has_table_privilege('authenticated','public.whatsapp_sender_accounts','INSERT')
  and not has_table_privilege('anon','public.whatsapp_sender_accounts','SELECT')
  and not has_table_privilege('anon','public.whatsapp_sender_accounts','INSERT')
END,'WSP: sender accounts RLS, no authenticated/anon access (owner reads via RPC)');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.whatsapp_sender_accounts') and attnum>0 and not attisdropped order by attnum$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('provider' collate "default"),('waba_id' collate "default"),('sender_id' collate "default"),('secret_reference' collate "default"),('enabled' collate "default"),('compliance_approved_at' collate "default"),('template_ready_at' collate "default"),('config_revision' collate "default"),('created_at' collate "default"),('updated_at' collate "default")) as e$q$,'WSP: exact sender accounts columns');
select ok(CASE WHEN to_regclass('public.whatsapp_sender_accounts') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.whatsapp_sender_accounts')) >= 1 END,'WSP: sender accounts has tenant policy');
select ok(CASE WHEN to_regclass('public.whatsapp_sender_accounts') IS NULL THEN false ELSE pg_temp.nuniq('whatsapp_sender_accounts') >= 1 END,'WSP: sender accounts tenant/sender uniqueness');

select ok(CASE WHEN to_regclass('public.whatsapp_template_revisions') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.whatsapp_template_revisions'))
  and has_table_privilege('authenticated','public.whatsapp_template_revisions','SELECT')
  and not has_table_privilege('authenticated','public.whatsapp_template_revisions','INSERT')
  and not has_table_privilege('authenticated','public.whatsapp_template_revisions','UPDATE')
  and not has_table_privilege('authenticated','public.whatsapp_template_revisions','DELETE')
  and not has_table_privilege('anon','public.whatsapp_template_revisions','SELECT')
END,'WSP: template revisions front-office safe SELECT, no DML');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.whatsapp_template_revisions') and attnum>0 and not attisdropped order by attnum$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('sender_account_id' collate "default"),('template_id' collate "default"),('body_hash' collate "default"),('parameter_schema_hash' collate "default"),('provider_template_name' collate "default"),('provider_template_id' collate "default"),('locale' collate "default"),('category' collate "default"),('approved_at' collate "default"),('paused_at' collate "default"),('disabled_at' collate "default"),('approval_evidence_digest' collate "default"),('checked_at' collate "default"),('created_at' collate "default"),('updated_at' collate "default")) as e$q$,'WSP: exact template revisions columns');
select ok(CASE WHEN to_regclass('public.whatsapp_template_revisions') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.whatsapp_template_revisions')) >= 1 END,'WSP: template revisions has tenant policy');
select ok(CASE WHEN to_regclass('public.whatsapp_template_revisions') IS NULL THEN false ELSE pg_temp.nfk('whatsapp_template_revisions') >= 2 END,'WSP: template revisions composite tenant FKs to sender/template');

select ok(CASE WHEN to_regclass('public.whatsapp_rate_versions') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.whatsapp_rate_versions'))
  and not has_table_privilege('authenticated','public.whatsapp_rate_versions','SELECT')
  and not has_table_privilege('authenticated','public.whatsapp_rate_versions','INSERT')
  and not has_table_privilege('anon','public.whatsapp_rate_versions','SELECT')
END,'WSP: rate versions owner-RPC-only reads, no client writes');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.whatsapp_rate_versions') and attnum>0 and not attisdropped order by attnum$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('sender_account_id' collate "default"),('effective_from' collate "default"),('effective_to' collate "default"),('destination_market' collate "default"),('provider_category' collate "default"),('amount_paise' collate "default"),('max_amount_paise' collate "default"),('currency' collate "default"),('rounding_revision' collate "default"),('evidence_digest' collate "default"),('created_at' collate "default")) as e$q$,'WSP: exact rate versions columns');
select ok(CASE WHEN to_regclass('public.whatsapp_rate_versions') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.whatsapp_rate_versions')) >= 1 END,'WSP: rate versions has tenant policy');
select ok(CASE WHEN to_regclass('public.whatsapp_rate_versions') IS NULL THEN false ELSE pg_temp.nfk('whatsapp_rate_versions') >= 1 END,'WSP: rate versions composite tenant/account FK');

select ok(CASE WHEN to_regclass('public.whatsapp_channel_consents') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.whatsapp_channel_consents'))
  and has_table_privilege('authenticated','public.whatsapp_channel_consents','SELECT')
  and not has_table_privilege('authenticated','public.whatsapp_channel_consents','INSERT')
  and not has_table_privilege('authenticated','public.whatsapp_channel_consents','UPDATE')
  and not has_table_privilege('authenticated','public.whatsapp_channel_consents','DELETE')
  and not has_table_privilege('anon','public.whatsapp_channel_consents','SELECT')
END,'WSP: channel consents own-member SELECT via RLS, no DML');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.whatsapp_channel_consents') and attnum>0 and not attisdropped order by attnum$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('member_id' collate "default"),('purpose' collate "default"),('granted' collate "default"),('notice_version' collate "default"),('source' collate "default"),('recipient_phone_digest' collate "default"),('contact_version_ref' collate "default"),('recipient_basis' collate "default"),('recorded_by_staff_id' collate "default"),('recorded_at' collate "default"),('created_at' collate "default")) as e$q$,'WSP: exact channel consents columns (digest, never raw phone)');
select ok(CASE WHEN to_regclass('public.whatsapp_channel_consents') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.whatsapp_channel_consents')) >= 1 END,'WSP: channel consents has tenant/member policy');
select ok(CASE WHEN to_regclass('public.whatsapp_channel_consents') IS NULL THEN false ELSE pg_temp.nfk('whatsapp_channel_consents') >= 1 END,'WSP: channel consents composite tenant/member FK');

select ok(CASE WHEN to_regclass('public.notification_whatsapp_attempts') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.notification_whatsapp_attempts'))
  and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','SELECT')
  and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','INSERT')
  and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','UPDATE')
  and not has_table_privilege('authenticated','public.notification_whatsapp_attempts','DELETE')
  and not has_table_privilege('anon','public.notification_whatsapp_attempts','SELECT')
  and not has_table_privilege('service_role','public.notification_whatsapp_attempts','INSERT')
  and not has_table_privilege('service_role','public.notification_whatsapp_attempts','UPDATE')
  and not has_table_privilege('service_role','public.notification_whatsapp_attempts','DELETE')
END,'WSP: attempts no authenticated/anon grants and no direct service DML (facades only)');
-- retained-schema-inventory-declaration.md (2026-10-04): append the generated
-- alias; retain all original attempt columns. Runtime amendment 2026-10-04:
-- the declaration pins the column SET (all 28 names, no recipient phone
-- column) and states ordinal order is not contract behavior, so the set is
-- compared order-insensitively; a genuinely missing/extra column still fails
-- this assertion, so the contract strength is unchanged.
select set_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.notification_whatsapp_attempts') and attnum>0 and not attisdropped$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('member_id' collate "default"),('notification_id' collate "default"),('sender_account_id' collate "default"),('template_revision_id' collate "default"),('rate_version_id' collate "default"),('consent_id' collate "default"),('request_key' collate "default"),('lease_ticket' collate "default"),('lease_expires_at' collate "default"),('recipient_contact_revision' collate "default"),('hold_max_paise' collate "default"),('hold_currency' collate "default"),('authorized_at' collate "default"),('io_started_at' collate "default"),('accepted_at' collate "default"),('completed_at' collate "default"),('uncertain_at' collate "default"),('provider_message_id' collate "default"),('failure_code' collate "default"),('released_at' collate "default"),('charged_ledger_id' collate "default"),('provider_read_at' collate "default"),('created_at' collate "default"),('updated_at' collate "default"),('currency' collate "default"),('channel_consent_id' collate "default")) as e$q$,'WSP: exact attempts columns (no recipient phone column)');
select ok(CASE WHEN to_regclass('public.notification_whatsapp_attempts') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.notification_whatsapp_attempts')) >= 1 END,'WSP: attempts has tenant policy');
select ok(CASE WHEN to_regclass('public.notification_whatsapp_attempts') IS NULL THEN false ELSE pg_temp.nuniq('notification_whatsapp_attempts') >= 3 END,'WSP: attempts unique tenant/request key, one live attempt per notification, provider id per sender');

select ok(CASE WHEN to_regclass('public.notification_whatsapp_receipts') IS NULL THEN false ELSE
  (select relrowsecurity from pg_class where oid=to_regclass('public.notification_whatsapp_receipts'))
  and not has_table_privilege('authenticated','public.notification_whatsapp_receipts','SELECT')
  and not has_table_privilege('authenticated','public.notification_whatsapp_receipts','INSERT')
  and not has_table_privilege('anon','public.notification_whatsapp_receipts','SELECT')
  and not has_table_privilege('service_role','public.notification_whatsapp_receipts','INSERT')
  and not has_table_privilege('service_role','public.notification_whatsapp_receipts','UPDATE')
END,'WSP: receipts no authenticated/anon grants and no direct service DML (normalized insert only)');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.notification_whatsapp_receipts') and attnum>0 and not attisdropped order by attnum$q$,
$q$select * from (values('id' collate "default"),('tenant_id' collate "default"),('attempt_id' collate "default"),('sender_account_id' collate "default"),('receipt_fingerprint' collate "default"),('event_kind' collate "default"),('provider_event_at' collate "default"),('received_at' collate "default"),('evidence_digest' collate "default"),('billing_category' collate "default"),('billing_evidence_ref' collate "default"),('created_at' collate "default")) as e$q$,'WSP: exact receipts columns (fingerprint, no raw body/phone)');
select ok(CASE WHEN to_regclass('public.notification_whatsapp_receipts') IS NULL THEN false ELSE (select count(*) from pg_policy where polrelid=to_regclass('public.notification_whatsapp_receipts')) >= 1 END,'WSP: receipts has tenant policy');
select ok(CASE WHEN to_regclass('public.notification_whatsapp_receipts') IS NULL THEN false ELSE pg_temp.nuniq('notification_whatsapp_receipts') >= 1 END,'WSP: receipts unique sender/fingerprint');

-- ---------------------------------------------------------------------------
-- S3: wallet paise cutover shape (unit-agnostic behavior is suite 76's)
-- ---------------------------------------------------------------------------
select ok(CASE WHEN to_regclass('public.messaging_wallets') IS NULL THEN false ELSE
  pg_temp.col('public.messaging_wallets','balance_paise')
  and pg_temp.col('public.messaging_wallets','currency')
  and pg_temp.col('public.messaging_wallets','original_balance_credits')
  and pg_temp.col('public.messaging_wallets','conversion_paise_per_credit')
  and pg_temp.col('public.messaging_wallets','converted_at')
END,'WSP: wallet carries paise balance, INR currency and immutable conversion evidence');
select ok(CASE WHEN to_regclass('public.messaging_wallet_ledger') IS NULL THEN false ELSE
  pg_temp.col('public.messaging_wallet_ledger','delta_paise')
  and pg_temp.col('public.messaging_wallet_ledger','balance_after_paise')
  and pg_temp.col('public.messaging_wallet_ledger','currency')
  and pg_temp.col('public.messaging_wallet_ledger','original_delta_credits')
  and pg_temp.col('public.messaging_wallet_ledger','conversion_approval_ref')
END,'WSP: ledger carries paise deltas, INR currency and immutable conversion evidence');

-- ---------------------------------------------------------------------------
-- S4: function postures
-- ---------------------------------------------------------------------------
select is_empty($q$with expected(sig,vol) as(values
('public.read_member_whatsapp_settings()','s'),
('public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)','v'),
('public.record_whatsapp_consent(uuid,public.consent_purpose,boolean,text,text,uuid)','v'))
select sig from expected e left join pg_proc p on p.oid=to_regprocedure(e.sig)
where p.oid is null or not p.prosecdef or p.provolatile::text<>e.vol
  or pg_get_userbyid(p.proowner)<>'postgres'
  or not coalesce(p.proconfig @> array['search_path=""'],false)
  or not has_function_privilege('authenticated',p.oid,'EXECUTE')
  or has_function_privilege('anon',p.oid,'EXECUTE')
  or has_function_privilege('service_role',p.oid,'EXECUTE')$q$,'WSP: three member/staff definer commands exact posture');
select is_empty($q$with expected(sig,vol) as(values
('public.request_whatsapp_dispatch(uuid,uuid)','v'),
('public.read_whatsapp_operations(timestamp with time zone,uuid,integer)','s'))
select sig from expected e left join pg_proc p on p.oid=to_regprocedure(e.sig)
where p.oid is null or p.prosecdef or p.provolatile::text<>e.vol
  or pg_get_userbyid(p.proowner)<>'postgres'
  or not coalesce(p.proconfig @> array['search_path=""'],false)
  or not has_function_privilege('authenticated',p.oid,'EXECUTE')
  or has_function_privilege('anon',p.oid,'EXECUTE')
  or has_function_privilege('service_role',p.oid,'EXECUTE')$q$,'WSP: two front-office invoker readers exact posture');
select is_empty($q$with expected(sig) as(values
('public.claim_whatsapp_dispatch(integer)'),
('public.authorize_whatsapp_dispatch(uuid,uuid)'),
('public.record_whatsapp_acceptance(uuid,uuid,text,text)'),
('public.finish_whatsapp_rejection(uuid,uuid,text,boolean)'),
('public.record_whatsapp_receipt(uuid,text,text,text,timestamp with time zone,text)'))
select sig from expected e left join pg_proc p on p.oid=to_regprocedure(e.sig)
where p.oid is null or p.prosecdef or p.provolatile::text<>'v'
  or pg_get_userbyid(p.proowner)<>'postgres'
  or not coalesce(p.proconfig @> array['search_path=""'],false)
  or has_function_privilege('authenticated',p.oid,'EXECUTE')
  or has_function_privilege('anon',p.oid,'EXECUTE')
  or not has_function_privilege('service_role',p.oid,'EXECUTE')$q$,'WSP: five service facades service-only invoker exact posture');
select ok(has_function_privilege('service_role','app.accept_paid_notification(uuid,text,bigint,uuid)'::regprocedure,'EXECUTE') = false
  and pg_temp.refusal($q$select app.accept_paid_notification(pg_temp.aid(1),'wamid.X',1::bigint,pg_temp.aid(2))$q$)='GL069',
  'WSP: paid stub stays denied with GL069 for every cost argument');
select ok(CASE WHEN to_regprocedure('public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid)') IS NULL THEN false ELSE
  (select prosecdef from pg_proc where oid=to_regprocedure('public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid)'))
  and pg_get_userbyid((select proowner from pg_proc where oid=to_regprocedure('public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid)')))='postgres'
  and has_function_privilege('authenticated',to_regprocedure('public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid)'),'EXECUTE')
  and not has_function_privilege('service_role',to_regprocedure('public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid)'),'EXECUTE')
END,'WSP: paise adjustment command definer, authenticated-only');

-- ---------------------------------------------------------------------------
-- S5: member settings and channel consent (WSP-002 boundary)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_2() returns setof text language plpgsql security invoker as $b$ begin
  if not (pg_temp.hasfn('public.read_member_whatsapp_settings()') and pg_temp.tbl('public.whatsapp_channel_consents')) then
    return next ok(false,'WSP: member consent block red (schema absent)'); return; end if;
  perform pg_temp.claim('member',null,101,906,1,false);
  perform set_config('role','authenticated',true);
  declare v jsonb; begin
    v := public.read_member_whatsapp_settings();
    return next is(v->>'recipientKind','self','WSP: adult recipient kind is self');
    return next ok(v->>'service'='true' and v->>'marketing'='false','WSP: granted service channel consent shows on, marketing stays independently off');
    return next ok(v->>'maskedPhone' is not null and v->>'maskedPhone' <> '+917500000101' and v->>'maskedPhone' like '%101','WSP: phone masked, never the raw number');
    return next is(v->>'available','false','WSP: unavailable while no sender account is configured');
  end;
  perform pg_temp.claim('member',null,108,910,1,false);
  declare v jsonb; begin
    v := public.read_member_whatsapp_settings();
    return next is(v->>'recipientKind','guardian','WSP: minor routes to the guardian recipient');
    return next ok(v->>'maskedPhone' <> '+917500001081' and v->>'maskedPhone' like '%081','WSP: guardian phone masked for a minor');
  end;
  perform pg_temp.claim('member',null,108,910,1,false);
  declare v jsonb; begin
    v := public.set_member_whatsapp_consent('service'::public.consent_purpose,true,'wsp-notice-v1');
    return next is(v->>'granted','true','WSP: member grants own channel consent');
  end;
  perform pg_temp.claim('member',null,108,910,1,false);
  declare v jsonb; n integer; begin
    v := public.set_member_whatsapp_consent('service'::public.consent_purpose,true,'wsp-notice-v1');
    return next is(v->>'granted','true','WSP: exact replay returns granted');
    select count(*) into n from public.whatsapp_channel_consents
      where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(108);
    return next is(n,1,'WSP: inert replay appends no second consent row');
  end;
  perform pg_temp.claim('member',null,108,910,1,false);
  declare v jsonb; n integer; begin
    v := public.set_member_whatsapp_consent('marketing'::public.consent_purpose,true,'wsp-notice-v1');
    return next is(v->>'purpose','marketing','WSP: marketing channel consent independent');
    select count(*) into n from public.consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(108);
    return next is(n,0,'WSP: channel consent never touches generic consents');
  end;
  perform pg_temp.claim('member',null,108,910,1,false);
  declare n integer; begin
    perform public.set_member_whatsapp_consent('service'::public.consent_purpose,false,'wsp-notice-v1');
    select count(*) into n from public.whatsapp_channel_consents
      where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(108) and granted=false;
    return next is(n,1,'WSP: withdrawal appends, history retained');
  end;
  perform pg_temp.claim('member',null,104,909,1,false);
  return next is(pg_temp.refusal($q$select public.set_member_whatsapp_consent('service'::public.consent_purpose,true,'wsp-notice-v1')$q$),
    '42501','WSP: blocked member cannot consent');
  perform pg_temp.claim('member',null,106,911,1,false);
  return next is(pg_temp.refusal($q$select public.set_member_whatsapp_consent('service'::public.consent_purpose,true,'wsp-notice-v1')$q$),
    '42501','WSP: erased member cannot consent');
  perform pg_temp.claim('member',null,107,912,1,false);
  return next is(pg_temp.refusal($q$select public.set_member_whatsapp_consent('service'::public.consent_purpose,true,'wsp-notice-v1')$q$),
    '42501','WSP: forged tenant/member claim cannot consent here');
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  declare v jsonb; begin
    v := public.record_whatsapp_consent(pg_temp.aid(101),'service'::public.consent_purpose,true,'wsp-notice-v1','desk_verification',pg_temp.aid(601));
    return next is(v->>'granted','true','WSP: desk records verified actual-recipient consent');
  end;
  return next is(pg_temp.refusal($q$select public.record_whatsapp_consent(pg_temp.aid(101),'service'::public.consent_purpose,true,'wsp-notice-v2','desk_verification',pg_temp.aid(601))$q$),
    'GL068','WSP: same request key with changed facts is a conflict');
  perform pg_temp.claim('trainer',24,null,904,1,false);
  return next is(pg_temp.refusal($q$select public.record_whatsapp_consent(pg_temp.aid(101),'service'::public.consent_purpose,true,'wsp-notice-v1','trainer',pg_temp.aid(602))$q$),
    '42501','WSP: trainer cannot record consent');
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  declare v jsonb; d text; begin
    v := public.record_whatsapp_consent(pg_temp.aid(108),'service'::public.consent_purpose,true,'wsp-notice-v1','guardian_evidence',pg_temp.aid(603));
    return next is(v->>'granted','true','WSP: owner records guardian-basis consent for the minor');
    select recipient_phone_digest into d from public.whatsapp_channel_consents
      where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(108) and recipient_basis='guardian'
      order by recorded_at desc limit 1;
    return next ok(d is not null and d <> '+917500001081','WSP: stored digest is not the raw guardian phone');
  end;
  perform set_config('role','postgres',true);
end $b$;
select * from pg_temp.visible_tap_block_2();

-- Tenant wallet fixture (paise units, opened at zero); S8 funds it through
-- the frozen super-admin adjustment and S10 drains it for the overspend case.
create function pg_temp.visible_tap_block_3() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.col('public.messaging_wallets','balance_paise') then
    return next ok(false,'WSP: wallet paise fixture red (cutover migration absent)'); return; end if;
  insert into public.messaging_wallets(tenant_id,balance_paise,currency)
  values(pg_temp.aid(1),0::bigint,'INR');
end $b$;
select * from pg_temp.visible_tap_block_3();

-- ---------------------------------------------------------------------------
-- S6: read_whatsapp_operations role boundaries and envelope
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_4() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.hasfn('public.read_whatsapp_operations(timestamp with time zone,uuid,integer)') then
    return next ok(false,'WSP: operations reader absent (red)'); return; end if;
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  perform set_config('role','authenticated',true);
  declare v jsonb; begin
    v := public.read_whatsapp_operations(null,null,50);
    return next is((select string_agg(k,',' order by k) from jsonb_object_keys(v) as j(k)),
      'chargedTotals,nextAfter,nextAfterId,operations,statusCounts,templateBlockers,wallet',
      'WSP: operations envelope is the frozen seven-key shape');
    return next ok(v::text not like '%+9175000001%','WSP: operations expose no raw phone');
    return next ok((v->'statusCounts') ? 'accepted' and (v->'statusCounts') ? 'delivered' and (v->'statusCounts') ? 'read' and (v->'statusCounts') ? 'unknown','WSP: statusCounts separates accepted/delivered/read/unknown');
    return next is(v->'wallet','null'::jsonb,'WSP: desk sees the wallet key present with JSON null, no amounts');
  end;
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  declare v jsonb; begin
    v := public.read_whatsapp_operations(null,null,50);
    return next ok(v->'wallet' is not null and v->'wallet'->>'balancePaise' is not null,'WSP: owner/manager wallet object present with exact paise balance');
  end;
  perform pg_temp.claim('trainer',24,null,904,1,false);
  return next is(pg_temp.refusal($q$select public.read_whatsapp_operations(null,null,50)$q$),'42501','WSP: trainer denied operations');
  perform pg_temp.claim('member',null,101,906,1,false);
  return next is(pg_temp.refusal($q$select public.read_whatsapp_operations(null,null,50)$q$),'42501','WSP: member denied operations');
  perform pg_temp.claim('super_admin',null,null,916,1,false);
  return next is(pg_temp.refusal($q$select public.read_whatsapp_operations(null,null,50)$q$),'42501','WSP: super_admin denied operations');
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  return next is(pg_temp.refusal($q$select public.read_whatsapp_operations(null,null,101)$q$),'22023','WSP: page limit bounded at 100');
  return next is(pg_temp.refusal($q$select public.read_whatsapp_operations(null,null,0)$q$),'22023','WSP: zero page limit refused');
  perform set_config('role','postgres',true);
end $b$;
select * from pg_temp.visible_tap_block_4();

-- ---------------------------------------------------------------------------
-- S7: request_whatsapp_dispatch queueing (WSP-001, no provider/amount input)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_5() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.hasfn('public.request_whatsapp_dispatch(uuid,uuid)') then
    return next ok(false,'WSP: dispatch request RPC absent (red)'); return; end if;
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  perform set_config('role','authenticated',true);
  declare v jsonb; v2 jsonb; begin
    v := public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(611));
    return next is(v->>'queued','true','WSP: desk queues the approved reminder');
    return next ok(v->>'notificationId' = (select id from wsp_ids where k='src_101')::text,'WSP: request echoes the source notification id');
    v2 := public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(611));
    return next is(v2->>'queued','true','WSP: exact replay of the same request key is accepted');
  end;
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(612))$q$),
    'GL068','WSP: a second key for the same event refuses instead of overwriting');
  perform pg_temp.claim('trainer',24,null,904,1,false);
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(613))$q$),
    '42501','WSP: trainer cannot request dispatch');
  perform pg_temp.claim('member',null,101,906,1,false);
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(614))$q$),
    '42501','WSP: member cannot request dispatch');
  perform pg_temp.claim('gym_owner',25,null,905,2,false);
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(615))$q$),
    'P0002','WSP: foreign owner sees the unknown-id refusal');
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch(pg_temp.aid(8888),pg_temp.aid(616))$q$),
    'P0002','WSP: unknown notification id is not an oracle');
  perform pg_temp.claim('gym_owner',null,null,901,1,true);
  return next is(pg_temp.refusal($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(617))$q$),
    '42501','WSP: impersonation cannot request dispatch');
  perform set_config('role','postgres',true);
end $b$;
select * from pg_temp.visible_tap_block_5();

-- ---------------------------------------------------------------------------
-- S8: claim/authorize facades — fail-closed, funds, tickets (WSP-006/011)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_6() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.hasfn('public.claim_whatsapp_dispatch(integer)') then
    return next ok(false,'WSP: claim facade absent (red)'); return; end if;
  perform set_config('request.jwt.claims','',true);
  declare c jsonb; begin
    c := public.claim_whatsapp_dispatch(10);
    return next is(c->>'configuration','provider_unconfigured','WSP: unconfigured provider claims nothing');
  end;
  insert into public.whatsapp_sender_accounts(id,tenant_id,provider,waba_id,sender_id,secret_reference,enabled,compliance_approved_at,template_ready_at,config_revision)
  values(pg_temp.aid(501),pg_temp.aid(1),'meta','waba-801','sender-801','vault:wsp_sender_801',true,now()-interval '1 hour',now()-interval '1 hour','cfg-1');
  insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at)
  values(pg_temp.aid(502),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(451),'bh-801','psh-801','renewal_reminder_wsp','tpl-801','en','renewal',now()-interval '30 minutes',now()-interval '10 minutes');
  insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
  values(pg_temp.aid(503),pg_temp.aid(1),pg_temp.aid(501),now()-interval '30 minutes','IN','marketing',100,100,'INR','all_in','ev-801');
  declare c jsonb; begin
    c := public.claim_whatsapp_dispatch(10);
    return next is(c->>'configuration','ready','WSP: configured provider reports ready');
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c->'attempts')='array' THEN c->'attempts' ELSE '[]'::jsonb END),0,
      'WSP: without funds the claim dispatches nothing (WSP-006)');
  end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(917),'role','authenticated','app_role','super_admin')::text,true);
  perform public.adjust_messaging_wallet_paise(pg_temp.aid(1),500::bigint,'INR','wsp-suite-funding',pg_temp.aid(630));
  perform set_config('request.jwt.claims','',true);
  declare c jsonb; a jsonb; begin
    c := public.claim_whatsapp_dispatch(10);
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c->'attempts')='array' THEN c->'attempts' ELSE '[]'::jsonb END),1,
      'WSP: funded claim reserves exactly one attempt');
    a := c->'attempts'->0;
    return next ok(a->>'ticket' is not null and a->>'attemptId' is not null,'WSP: claim returns attempt and ticket identifiers only');
    return next ok(a->>'expiresAt' is not null and (a->>'expiresAt')::timestamptz <= now()+interval '130 seconds','WSP: authorization ticket is ~120 seconds');
  end;
  return next is(pg_temp.refusal($q$select public.claim_whatsapp_dispatch(0)$q$),'22023','WSP: batch below 1 refused');
  return next is(pg_temp.refusal($q$select public.claim_whatsapp_dispatch(51)$q$),'22023','WSP: batch above 50 refused');
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  perform set_config('role','authenticated',true);
  return next lives_ok($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_102'),pg_temp.aid(621))$q$,
    'WSP: desk queues the second member reminder');
  return next lives_ok($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_110'),pg_temp.aid(622))$q$,
    'WSP: desk queues the third member reminder');
  perform set_config('role','postgres',true);
  perform set_config('request.jwt.claims','',true);
  declare c jsonb; begin
    c := public.claim_whatsapp_dispatch(10);
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c->'attempts')='array' THEN c->'attempts' ELSE '[]'::jsonb END),2,
      'WSP: claim reserves both queued attempts');
  end;
  insert into wsp_ids(k,id)
  select 'att_'||pg_temp.shortid(a.member_id), a.id from public.notification_whatsapp_attempts a
  where a.tenant_id=pg_temp.aid(1) and a.member_id in (pg_temp.aid(101),pg_temp.aid(102),pg_temp.aid(110))
  on conflict (k) do nothing;
  insert into wsp_txt(k,v)
  select 'tick_'||pg_temp.shortid(a.member_id), a.lease_ticket::text from public.notification_whatsapp_attempts a
  where a.tenant_id=pg_temp.aid(1) and a.member_id in (pg_temp.aid(101),pg_temp.aid(102),pg_temp.aid(110))
  on conflict (k) do nothing;
  declare r jsonb; begin
    r := public.authorize_whatsapp_dispatch((select id from wsp_ids where k='att_102'),
      (select v from wsp_txt where k='tick_102')::uuid);
    return next is(r->>'authorized','true','WSP: authorize admits the reserved attempt before I/O');
  end;
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  perform pg_temp.chronological_channel_decision(pg_temp.aid(110),'service',false,'wsp-notice-v1','desk_verification',pg_temp.aid(1467));
  perform set_config('request.jwt.claims','',true);
  declare r jsonb; begin
    r := public.authorize_whatsapp_dispatch((select id from wsp_ids where k='att_110'),
      (select v from wsp_txt where k='tick_110')::uuid);
    return next is(r->>'authorized','false','WSP: withdrawal committed before authorization yields no provider request');
    return next ok(r->>'recipient' is null,'WSP: a refused authorization returns no recipient');
  end;
  return next is(pg_temp.refusal($q$select public.authorize_whatsapp_dispatch(pg_temp.aid(8888),pg_temp.aid(8899))$q$),
    'P0002','WSP: unknown attempt/reservation pair is invisible');
  return next is(pg_temp.refusal($q$select public.authorize_whatsapp_dispatch((select id from wsp_ids where k='att_102'),pg_temp.aid(8898))$q$),
    'GL120','WSP: wrong ticket is a stale-ticket conflict');
  return next is(pg_temp.refusal($q$select public.authorize_whatsapp_dispatch((select id from wsp_ids where k='att_102'),(select v from wsp_txt where k='tick_102')::uuid)$q$),
    'GL120','WSP: replayed authorization cannot grant a second send');
end $b$;
select * from pg_temp.visible_tap_block_6();

-- ---------------------------------------------------------------------------
-- S9: acceptance, rejection, uncertainty, receipts, causal debit (WSP-005/007/008)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_7() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.hasfn('public.record_whatsapp_acceptance(uuid,uuid,text,text)') then
    return next ok(false,'WSP: acceptance facade absent (red)'); return; end if;
  perform set_config('request.jwt.claims','',true);
  declare r jsonb; begin
    r := public.authorize_whatsapp_dispatch((select id from wsp_ids where k='att_101'),
      (select v from wsp_txt where k='tick_101')::uuid);
    return next is(r->>'authorized','true','WSP: the first attempt authorizes for acceptance');
  end;
  declare r jsonb; begin
    r := public.record_whatsapp_acceptance((select id from wsp_ids where k='att_101'),
      (select v from wsp_txt where k='tick_101')::uuid,'wamid.A801','ev-acc-801');
    return next is(r->>'replayed','false','WSP: acceptance records once');
  end;
  declare r jsonb; begin
    r := public.record_whatsapp_acceptance((select id from wsp_ids where k='att_101'),
      (select v from wsp_txt where k='tick_101')::uuid,'wamid.A801','ev-acc-801');
    return next is(r->>'replayed','true','WSP: acceptance replay is inert');
  end;
  return next ok(exists(select 1 from public.notification_whatsapp_attempts
    where id=(select id from wsp_ids where k='att_101')
      and accepted_at is not null and provider_message_id='wamid.A801' and released_at is null),
    'WSP: acceptance stores evidence and preserves the hold');
  return next ok(not exists(select 1 from public.messaging_wallet_ledger
    where notification_id=(select id from wsp_ids where k='src_101')),'WSP: acceptance never debits');
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  perform set_config('role','authenticated',true);
  return next lives_ok($q$select public.record_whatsapp_consent(pg_temp.aid(102),'service'::public.consent_purpose,true,'wsp-notice-v1','desk_verification',pg_temp.aid(604))$q$,
    'WSP: desk appends a fresh verified consent row for the re-queued member');
  perform set_config('role','postgres',true);
  perform set_config('request.jwt.claims','',true);
  declare r jsonb; begin
    r := public.finish_whatsapp_rejection((select id from wsp_ids where k='att_102'),
      (select v from wsp_txt where k='tick_102')::uuid,'recipient_invalid',true);
    return next is(r->>'replayed','false','WSP: known rejection records once');
  end;
  return next ok(exists(select 1 from public.notification_whatsapp_attempts
    where id=(select id from wsp_ids where k='att_102')
      and released_at is not null and failure_code='recipient_invalid'),
    'WSP: known rejection releases the hold without charge');
  return next ok(exists(select 1 from public.notifications
    where id=(select id from wsp_ids where k='src_102') and status='failed'),
    'WSP: known rejection fails the notification through the legal edge');
  return next ok(not exists(select 1 from public.messaging_wallet_ledger
    where notification_id=(select id from wsp_ids where k='src_102')),'WSP: known rejection never debits');
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  perform set_config('role','authenticated',true);
  return next lives_ok($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_111'),pg_temp.aid(623))$q$,
    'WSP: desk queues the uncertainty-case reminder');
  perform set_config('role','postgres',true);
  perform set_config('request.jwt.claims','',true);
  declare c jsonb; a jsonb; begin
    c := public.claim_whatsapp_dispatch(10);
    a := c->'attempts'->0;
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c->'attempts')='array' THEN c->'attempts' ELSE '[]'::jsonb END),1,
      'WSP: the uncertainty case reserves one attempt');
    return next lives_ok(format('select public.authorize_whatsapp_dispatch(%L::uuid,%L::uuid)',a->>'attemptId',a->>'ticket'),
      'WSP: the uncertainty attempt authorizes');
    insert into wsp_ids(k,id) values('attu',(a->>'attemptId')::uuid);
    insert into wsp_txt(k,v) values('ticku',a->>'ticket');
  end;
  return next lives_ok($q$select public.finish_whatsapp_rejection((select id from wsp_ids where k='attu'),(select v from wsp_txt where k='ticku')::uuid,null,false)$q$,
    'WSP: unknown outcome records uncertainty');
  return next ok(exists(select 1 from public.notification_whatsapp_attempts
    where id=(select id from wsp_ids where k='attu') and uncertain_at is not null
      and released_at is null and failure_code is null),
    'WSP: unknown outcome preserves the unresolved attempt and hold');
  return next lives_ok($q$select public.finish_whatsapp_rejection((select id from wsp_ids where k='attu'),(select v from wsp_txt where k='ticku')::uuid,'provider_rejected',true)$q$,
    'WSP: explicit reasoned reconciliation closes the uncertain attempt');
  return next ok(exists(select 1 from public.notification_whatsapp_attempts
    where id=(select id from wsp_ids where k='attu') and released_at is not null),
    'WSP: reconciled rejection releases the held funds');
  declare r jsonb; n integer; begin
    r := public.record_whatsapp_receipt(pg_temp.aid(501),'wamid.A801','fp-del-801','delivered',now(),pg_temp.aid(701)::text);
    return next is(r->>'applied','true','WSP: verified delivery receipt applied');
    return next is(r->>'debitedPaise','-100','WSP: debit amount is the frozen server tariff, negative');
    return next is(r->>'currency','INR','WSP: debit currency is INR');
  end;
  return next ok(exists(select 1 from public.notifications
    where id=(select id from wsp_ids where k='src_101') and status='delivered' and delivered_at is not null),
    'WSP: delivery requires delivery evidence and moves the source to delivered');
  return next is((select count(*) from public.messaging_wallet_ledger
    where notification_id=(select id from wsp_ids where k='src_101')),1::bigint,
    'WSP: exactly one causal debit for the delivered attempt');
  declare r jsonb; n integer; begin
    r := public.record_whatsapp_receipt(pg_temp.aid(501),'wamid.A801','fp-del-801','delivered',now(),pg_temp.aid(701)::text);
    return next is(r->>'replayed','true','WSP: duplicate fingerprint receipt replays');
  end;
  return next is((select count(*) from public.messaging_wallet_ledger
    where notification_id=(select id from wsp_ids where k='src_101')),1::bigint,
    'WSP: duplicate receipt never debits again');
  return next lives_ok($q$select public.record_whatsapp_receipt(pg_temp.aid(501),'wamid.A801','fp-read-801','read',now(),pg_temp.aid(702)::text)$q$,
    'WSP: verified read receipt accepted after delivery');
  return next ok(exists(select 1 from public.notification_whatsapp_attempts
    where provider_message_id='wamid.A801' and provider_read_at is not null),
    'WSP: read evidence populates provider_read_at');
  return next ok(not exists(select 1 from public.notifications
    where id=(select id from wsp_ids where k='src_101') and clicked_at is not null),
    'WSP: provider read never writes clicked_at');
  return next is(pg_temp.refusal($q$select public.record_whatsapp_receipt(pg_temp.aid(501),'wamid.UNKNOWN','fp-x-801','delivered',now(),pg_temp.aid(703)::text)$q$),
    'GL122','WSP: receipt without a matching accepted attempt refuses (GL122)');
  return next lives_ok($q$select public.record_whatsapp_receipt(pg_temp.aid(501),'wamid.A801','fp-late-801','delivered',now(),pg_temp.aid(704)::text)$q$,
    'WSP: late evidence after terminal failure is retained');
  return next ok(exists(select 1 from public.notification_whatsapp_receipts
    where receipt_fingerprint='fp-late-801')
    and not exists(select 1 from public.notifications
      where id=(select id from wsp_ids where k='src_102') and status='delivered'),
    'WSP: late evidence retained for reconciliation without reviving the terminal failure');
end $b$;
select * from pg_temp.visible_tap_block_7();

-- ---------------------------------------------------------------------------
-- S10: funds serialization and rate publication boundaries (WSP-005/006)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_8() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.hasfn('public.claim_whatsapp_dispatch(integer)') then
    return next ok(false,'WSP: funds block needs the claim facade (red)'); return; end if;
  perform set_config('request.jwt.claims','',true);
  perform pg_temp.claim('gym_owner',21,null,901,1,false);
  perform set_config('role','authenticated',true);
  return next lives_ok($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_109'),pg_temp.aid(631))$q$,'WSP: queue member 109 reminder');
  return next lives_ok($q$select public.request_whatsapp_dispatch((select id from wsp_ids where k='src_112'),pg_temp.aid(632))$q$,'WSP: queue member 112 reminder');
  perform set_config('role','postgres',true);
  declare bal text; begin
    perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(917),'role','authenticated','app_role','super_admin')::text,true);
    perform public.adjust_messaging_wallet_paise(pg_temp.aid(1),(-250)::bigint,'INR','wsp-competency-test',pg_temp.aid(633));
    perform set_config('request.jwt.claims','',true);
    select balance_paise::text into bal from public.messaging_wallets where tenant_id=pg_temp.aid(1);
    return next is(bal,'150','WSP: reasoned adjustment under a real super-admin moves the exact paise balance');
  end;
  declare c jsonb; c2 jsonb; n integer; begin
    c := public.claim_whatsapp_dispatch(10);
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c->'attempts')='array' THEN c->'attempts' ELSE '[]'::jsonb END),1,
      'WSP: first send for the final funds reserves');
    c2 := public.claim_whatsapp_dispatch(10);
    return next is(jsonb_array_length(CASE WHEN jsonb_typeof(c2->'attempts')='array' THEN c2->'attempts' ELSE '[]'::jsonb END),0,
      'WSP: two sends cannot overspend the final amount');
    select count(*) into n from public.messaging_wallet_ledger
      where tenant_id=pg_temp.aid(1) and notification_id is not null;
    return next is(n,1,'WSP: only the causal payment debits the ledger (holds and the reasoned adjustment move no payment row)');
  end;
  return next lives_ok($q$insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
    values(pg_temp.aid(504),pg_temp.aid(1),pg_temp.aid(501),now(),'IN','marketing',0,0,'INR','all_in','ev-zero')$q$,
    'WSP: zero-cost tariff publication accepted');
  return next is(pg_temp.refusal($q$insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
    values(pg_temp.aid(505),pg_temp.aid(1),pg_temp.aid(501),now(),'IN','marketing',-1,0,'INR','all_in','ev-neg')$q$),
    '22023','WSP: negative tariff refused');
  return next is(pg_temp.refusal($q$insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
    values(pg_temp.aid(506),pg_temp.aid(1),pg_temp.aid(501),now(),'IN','marketing',100,100,'USD','all_in','ev-usd')$q$),
    '22023','WSP: non-INR tariff refused');
  declare wbal text; begin
    select balance_paise::text into wbal from public.messaging_wallets where tenant_id=pg_temp.aid(1);
    return next is(wbal,'150','WSP: paise balance arithmetic exact (500 - 100 debit - 250 adjustment)');
  end;
end $b$;
select * from pg_temp.visible_tap_block_8();

-- ---------------------------------------------------------------------------
-- S11: keys, channels, fallback, manual-open parity (WSP-009)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_9() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.tbl('public.notification_whatsapp_attempts') then
    return next ok(false,'WSP: keys block needs attempts table (red)'); return; end if;
  perform pg_temp.claim('front_desk',23,null,903,1,false);
  perform set_config('role','authenticated',true);
  return next lives_ok($q$select public.open_notification_whatsapp((select id from wsp_ids where k='src_101'))$q$,
    'WSP: manual open still works on the delivered source');
  declare n integer; begin
    select count(*) into n from public.notifications
      where source_notification_id=(select id from wsp_ids where k='src_101')
        and channel='whatsapp_link' and dedupe_key='whatsapp-paid:'||(select id from wsp_ids where k='src_101')::text;
    return next is(n,1,'WSP: exactly one paid child with the frozen whatsapp-paid key');
  end;
  declare n integer; begin
    select count(*) into n from public.notifications
      where source_notification_id=(select id from wsp_ids where k='src_101')
        and channel='whatsapp_link' and dedupe_key='whatsapp:'||(select id from wsp_ids where k='src_101')::text;
    return next is(n,1,'WSP: manual child keeps its existing key alongside the paid child');
  end;
  declare n integer; begin
    select count(*) into n from public.notifications
      where source_notification_id=(select id from wsp_ids where k='src_102')
        and channel='in_app' and dedupe_key='whatsapp-fallback:'||(select id from wsp_ids where k='src_102')::text;
    return next is(n,1,'WSP: known rejection surfaced one in-app fallback with the frozen key');
  end;
  declare n integer; begin
    select count(*) into n from public.messaging_wallet_ledger l
      join public.notifications nn on nn.id=l.notification_id
      where nn.dedupe_key like 'whatsapp-fallback:%';
    return next is(n,0,'WSP: fallback is never charged');
  end;
  perform set_config('role','postgres',true);
end $b$;
select * from pg_temp.visible_tap_block_9();

-- ---------------------------------------------------------------------------
-- S12: audit hygiene (WSP-010)
-- ---------------------------------------------------------------------------
create function pg_temp.visible_tap_block_10() returns setof text language plpgsql security invoker as $b$ begin
  if not pg_temp.tbl('public.whatsapp_channel_consents') then
    return next ok(false,'WSP: audit block needs consent table (red)'); return; end if;
  return next ok(exists(select 1 from public.audit_log a
    join public.whatsapp_channel_consents cc on cc.id=(a.record_id)::uuid
    where cc.tenant_id=pg_temp.aid(1)),'WSP: consent changes are audited');
  return next ok(not exists(select 1 from public.audit_log
    where tenant_id=pg_temp.aid(1) and (after::text like '%+9175000001%' or before::text like '%+9175000001%')),
    'WSP: audit carries no raw phone');
  perform pg_temp.claim('member',null,106,911,1,false);
  perform set_config('role','authenticated',true);
  return next is(pg_temp.refusal($q$select public.read_member_whatsapp_settings()$q$),
    '42501','WSP: erased member reads nothing');
  perform set_config('role','postgres',true);
end $b$;
select * from pg_temp.visible_tap_block_10();


-- WSP schema + ADR-052: count-only FK checks above cannot prove ordered
-- tenant/reference coverage. Pin template and consent FK operands independently.
select ok(exists(select 1 from pg_constraint c where c.contype='f'
 and c.conrelid=to_regclass('public.whatsapp_template_revisions')
 and c.confrelid=to_regclass('public.message_templates')
 and (select array_agg(a.attname::text order by x.ord) from unnest(c.conkey) with ordinality x(num,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=x.num)=array['tenant_id','template_id']
 and (select array_agg(a.attname::text order by x.ord) from unnest(c.confkey) with ordinality x(num,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=x.num)=array['tenant_id','id']),
 'WSP ADR-052: revision template reference enforces the matching tenant');
select ok(exists(select 1 from pg_constraint c where c.contype='f'
 and c.conrelid=to_regclass('public.notification_whatsapp_attempts')
 and c.confrelid=to_regclass('public.whatsapp_channel_consents')
 -- A stronger tenant/member/consent FK also meets the contract: verify paired
 -- operands instead of rejecting an additional member-identity operand.
 and (select array_agg(a.attname::text||'='||b.attname::text order by x.ord)
      from unnest(c.conkey,c.confkey) with ordinality x(num,refnum,ord)
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=x.num
      join pg_attribute b on b.attrelid=c.confrelid and b.attnum=x.refnum)
     @> array['tenant_id=tenant_id','member_id=member_id','channel_consent_id=id']
 and (select array_agg(a.attname::text||'='||b.attname::text order by x.ord)
      from unnest(c.conkey,c.confkey) with ordinality x(num,refnum,ord)
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=x.num
      join pg_attribute b on b.attrelid=c.confrelid and b.attnum=x.refnum)
     <@ array['tenant_id=tenant_id','member_id=member_id','channel_consent_id=id']),
 'WSP ADR-052: attempt consent reference enforces the matching tenant');


-- Runtime template-reference acceptance/refusal uses valid published fixture
-- shapes already required by WSP. No provider request or wallet movement occurs.
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active)
values(pg_temp.aid(8450),pg_temp.aid(1),'wsp_fk_probe_own','whatsapp_link','en','renewal','Renewal {{1}}',true),
(pg_temp.aid(8451),pg_temp.aid(2),'wsp_fk_probe','whatsapp_link','en','renewal','Renewal {{1}}',true);
select lives_ok($q$insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at)
values(pg_temp.aid(8502),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(8450),'bh-fk','psh-fk','renewal_fk','tpl-fk','en','renewal',now(),now())$q$,'WSP ADR-052: valid same-tenant template reference accepted');
select throws_ok($q$insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at)
values(pg_temp.aid(8503),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(8451),'bh-foreign','psh-foreign','foreign_fk','tpl-foreign','en','renewal',now(),now())$q$,'23503',null,'WSP ADR-052: existing foreign-tenant template reference refused');


-- WSP/ADR-052 fresh consent-reference probe: known valid sender, tariff,
-- revision and grant remain the same; only the referenced consent's tenant differs.
select pg_temp.claim('gym_owner',25,null,905,2,false);
select public.record_whatsapp_consent(pg_temp.aid(107),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(8462));
-- The foreign probe is genuine recipient evidence; only its tenant differs.
insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at,created_at)
select pg_temp.aid(8461),cc.tenant_id,cc.member_id,cc.purpose,cc.granted,cc.notice_version,cc.source,cc.recipient_phone_digest,cc.contact_version_ref,cc.recipient_basis,cc.recorded_by_staff_id,clock_timestamp(),clock_timestamp()
from public.whatsapp_channel_consents cc where cc.tenant_id=pg_temp.aid(2) and cc.member_id=pg_temp.aid(107) and cc.purpose='service' order by cc.recorded_at desc,cc.id desc limit 1;
-- Public COM §4/5 and Wave C: ordinary payment-availability source events are
-- independently scheduled; manual children are created only by the command.
select pg_temp.claim('gym_owner',21,null,901,1);
insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active)
values(pg_temp.aid(8504),pg_temp.aid(1),'wsp_fk_payment_notice','whatsapp_link','en','payment','Your receipt is available in the app.',true);
insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at)
values(pg_temp.aid(8505),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(8504),'bh-payment-fk','psh-payment-fk','payment_fk','tpl-payment-fk','en','payment',now(),now());
insert into public.notifications(id,tenant_id,member_id,channel,status,category,dedupe_key,payload)
values(pg_temp.aid(8601),pg_temp.aid(1),pg_temp.aid(101),'in_app','scheduled','payment','wsp-fk-payment-own','{"body":"Your receipt is available in the app."}'),
(pg_temp.aid(8602),pg_temp.aid(1),pg_temp.aid(101),'in_app','scheduled','payment','wsp-fk-payment-foreign','{"body":"Your receipt is available in the app."}');
select public.send_notification(pg_temp.aid(8601));
select public.send_notification(pg_temp.aid(8602));
select public.open_notification_whatsapp(pg_temp.aid(8601));
select public.open_notification_whatsapp(pg_temp.aid(8602));
select set_config('request.jwt.claims','',true);
select lives_ok($q$insert into public.notification_whatsapp_attempts(id,tenant_id,member_id,notification_id,sender_account_id,template_revision_id,rate_version_id,consent_id,channel_consent_id,request_key,lease_ticket,lease_expires_at,recipient_contact_revision,hold_max_paise,hold_currency)
values(pg_temp.aid(8701),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(8601),pg_temp.aid(501),pg_temp.aid(8505),pg_temp.aid(503),pg_temp.aid(401),(select id from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(101) and purpose='service' order by recorded_at desc,id desc limit 1),pg_temp.aid(8801),pg_temp.aid(8901),now()+interval '120 seconds',(select contact_version_ref from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(101) and purpose='service' order by recorded_at desc,id desc limit 1),100,'INR')$q$,
'WSP ADR-052: valid fresh same-tenant consent reference accepted');
select throws_ok($q$insert into public.notification_whatsapp_attempts(id,tenant_id,member_id,notification_id,sender_account_id,template_revision_id,rate_version_id,consent_id,channel_consent_id,request_key,lease_ticket,lease_expires_at,recipient_contact_revision,hold_max_paise,hold_currency)
values(pg_temp.aid(8702),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(8602),pg_temp.aid(501),pg_temp.aid(8505),pg_temp.aid(503),pg_temp.aid(401),pg_temp.aid(8461),pg_temp.aid(8802),pg_temp.aid(8902),now()+interval '120 seconds',(select contact_version_ref from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(101) and purpose='service' order by recorded_at desc,id desc limit 1),100,'INR')$q$,
'23503',null,'WSP ADR-052: existing foreign-tenant consent reference refused');

select * from finish();
rollback;
