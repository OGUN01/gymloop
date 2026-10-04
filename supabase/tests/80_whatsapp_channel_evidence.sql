-- Independent WSP-003/010 causal channel evidence; public retained declaration 2026-10-04.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(91);
create function pg_temp.aid(n integer) returns uuid language sql immutable as $f$select ('80200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$f$;
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

-- ---------------------------------------------------------------------------
-- Fixtures (trusted scheduler context)
-- ---------------------------------------------------------------------------
insert into public.organizations(id,name,gym_code,status) values(pg_temp.aid(1),'WSP A','WSP8EA','active'),(pg_temp.aid(2),'WSP B','WSP8EB','active');
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
-- Schema evidence is distinct from generic-purpose evidence. Zip FK operands;
-- physical ordinal/deparser order is not a behavior requirement.
select ok(exists(select 1 from pg_attribute where attrelid=to_regclass('public.notification_whatsapp_attempts') and attname='channel_consent_id' and attnotnull and not attisdropped),'WSP-010: exact channel evidence is mandatory');
select ok(exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.notification_whatsapp_attempts') and c.confrelid=to_regclass('public.consents') and c.contype='f' and exists(select 1 from unnest(c.conkey,c.confkey) x(a,b) join pg_attribute aa on aa.attrelid=c.conrelid and aa.attnum=x.a join pg_attribute bb on bb.attrelid=c.confrelid and bb.attnum=x.b where aa.attname='consent_id' and bb.attname='id')),'WSP-010: generic consent_id still references generic consents');
select ok(exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.notification_whatsapp_attempts') and c.confrelid=to_regclass('public.whatsapp_channel_consents') and c.contype='f' and (select array_agg(aa.attname::text||'='||bb.attname::text) from unnest(c.conkey,c.confkey) x(a,b) join pg_attribute aa on aa.attrelid=c.conrelid and aa.attnum=x.a join pg_attribute bb on bb.attrelid=c.confrelid and bb.attnum=x.b) @> array['tenant_id=tenant_id','member_id=member_id','channel_consent_id=id']),'WSP-010: tenant member channel evidence are bound together');
select ok(exists(select 1 from pg_index i where i.indrelid=to_regclass('public.notification_whatsapp_attempts') and i.indisvalid and (select a.attname from pg_attribute a where a.attrelid=i.indrelid and a.attnum=i.indkey[0])='tenant_id' and exists(select 1 from unnest(i.indkey) x(n) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=x.n where a.attname='channel_consent_id')),'WSP-010: channel evidence attempt index leads with tenant');
select ok(exists(select 1 from pg_index i where i.indrelid=to_regclass('public.whatsapp_channel_consents') and i.indisunique and i.indisvalid and (select array_agg(a.attname::text) from unnest(i.indkey) x(n) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=x.n) @> array['tenant_id','member_id','id']),'WSP-010: referenced consent identity has a unique key');

-- Five independent observable assertions per final authorization; no provider
-- adapter is invoked and a truthful initiated ticket is never called a debit.
create function pg_temp.evidence_authorize(m integer,expected boolean,label text,specific_attempt uuid default null) returns setof text language plpgsql as $f$
declare a public.notification_whatsapp_attempts%rowtype; r jsonb; source_before jsonb;
begin
 select * into a from public.notification_whatsapp_attempts where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(m) and (specific_attempt is null or id=specific_attempt) order by created_at desc,id desc limit 1;
 select to_jsonb(nn) into source_before from public.notifications nn where nn.id=a.notification_id;
 r:=public.authorize_whatsapp_dispatch(a.id,a.lease_ticket);
 return next is(r->>'authorized',expected::text,label||': final permission');
 return next ok(expected or r->>'recipient' is null,label||': refusal reveals no recipient');
 return next ok(expected or exists(select 1 from public.notification_whatsapp_attempts where id=a.id and io_started_at is null),label||': refusal starts no I/O');
 return next ok(expected or exists(select 1 from public.notification_whatsapp_attempts where id=a.id and released_at is not null),label||': refusal releases hold');
 return next is((select count(*) from public.messaging_wallet_ledger where notification_id=a.notification_id),0::bigint,label||': no debit before provider evidence');
 return next ok(expected or exists(select 1 from public.notification_whatsapp_attempts where id=a.id and failure_code='opted_out' and released_at is not null),label||': durable exact opted_out refusal and release');
 return next ok(expected or not exists(select 1 from public.notifications where source_notification_id=a.notification_id and channel='whatsapp_link' and dedupe_key='whatsapp-paid:'||a.notification_id::text),label||': refusal creates no paid child');
 return next ok(expected or (select to_jsonb(nn) from public.notifications nn where nn.id=a.notification_id)=source_before,label||': refusal preserves the factual source row');
end$f$;

-- A valid minimal attempt shape derived solely from the public WSP declaration.
create function pg_temp.attempt_probe(child integer,channel_id uuid) returns void language plpgsql as $f$
begin
 insert into public.notification_whatsapp_attempts(id,tenant_id,member_id,notification_id,sender_account_id,template_revision_id,rate_version_id,consent_id,channel_consent_id,request_key,lease_ticket,lease_expires_at,recipient_contact_revision,hold_max_paise,hold_currency)
 values(pg_temp.aid(child+100),pg_temp.aid(1),pg_temp.aid(112),pg_temp.aid(child),pg_temp.aid(501),pg_temp.aid(2051),pg_temp.aid(503),pg_temp.aid(407),channel_id,pg_temp.aid(child+200),pg_temp.aid(child+300),now()+interval '120 seconds',(select contact_version_ref from public.whatsapp_channel_consents where id=channel_id),100,'INR');
end$f$;
create function pg_temp.visible_tap_block_1() returns setof text language plpgsql security invoker as $b$
declare m integer; c jsonb; n integer; a uuid; before_balance bigint; before_attempts bigint; before_ledger bigint; prep_source jsonb;
begin
 if not pg_temp.col('public.notification_whatsapp_attempts','channel_consent_id') then
  return query select * from skip('WSP channel evidence schema absent',86); return;
 end if;
 -- Independently reuse the lawful public visible fixture. Consent commands
 -- derive actual digest/contact revision rather than inventing opt-in history.
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 for m in select unnest(array[101,102,109,110,111,112]) loop
  perform public.record_whatsapp_consent(pg_temp.aid(m),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(600+m));
 end loop;
 perform set_config('request.jwt.claims','',true);
 insert into public.whatsapp_sender_accounts(id,tenant_id,provider,waba_id,sender_id,secret_reference,enabled,compliance_approved_at,template_ready_at,config_revision)
 values(pg_temp.aid(501),pg_temp.aid(1),'meta','waba-evidence','sender-evidence','vault:wsp_evidence_fixture',true,now(),now(),'cfg-evidence');
 insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at)
 values(pg_temp.aid(502),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(451),'bh-e','psh-e','renewal_evidence','tpl-e','en','renewal',now(),now());
 insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest)
 values(pg_temp.aid(503),pg_temp.aid(1),pg_temp.aid(501),now()-interval '1 hour','IN','marketing',100,100,'INR','all_in','ev-evidence');
 insert into public.messaging_wallets(tenant_id,balance_paise,currency) values(pg_temp.aid(1),0,'INR');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(917),'role','authenticated','app_role','super_admin')::text,true);
 perform public.adjust_messaging_wallet_paise(pg_temp.aid(1),5000,'INR','evidence-test-funding',pg_temp.aid(630));
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 for m in select unnest(array[101,102,109,110,111,112]) loop
  return next lives_ok(format('select public.request_whatsapp_dispatch(%L::uuid,%L::uuid)',(select id from wsp_ids where k='src_'||m),pg_temp.aid(700+m)),'WSP-003: queue current service grant '||m);
 end loop;
 perform set_config('request.jwt.claims','',true);
 c:=public.claim_whatsapp_dispatch(10);
 return next is(jsonb_array_length(c->'attempts'),6,'WSP-003: claim selects six lawful current service grants');
 for m in select unnest(array[101,102,109,110,111,112]) loop
  return next ok(exists(select 1 from public.notification_whatsapp_attempts aa join public.whatsapp_channel_consents cc on cc.tenant_id=aa.tenant_id and cc.member_id=aa.member_id and cc.id=aa.channel_consent_id where aa.member_id=pg_temp.aid(m) and aa.tenant_id=pg_temp.aid(1) and cc.granted and cc.id=(select id from public.whatsapp_channel_consents where tenant_id=aa.tenant_id and member_id=aa.member_id and purpose='service' order by recorded_at desc,id desc limit 1)),'WSP-010: claim freezes exact current opt-in '||m);
 end loop;
 -- Authorized record retains both independent evidence identities.
 return query select * from pg_temp.evidence_authorize(101,true,'WSP service current grant');
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 perform pg_temp.chronological_channel_decision(pg_temp.aid(102),'service',false,'wsp-notice-v1','desk_verification',pg_temp.aid(1602));
 perform set_config('request.jwt.claims','',true);
 return query select * from pg_temp.evidence_authorize(102,false,'WSP withdrawal before I/O');
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 perform pg_temp.chronological_channel_decision(pg_temp.aid(109),'service',true,'wsp-notice-v2','desk_verification',pg_temp.aid(1609));
 perform set_config('request.jwt.claims','',true);
 return query select * from pg_temp.evidence_authorize(109,false,'WSP superseding version cannot rewrite causal evidence');
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 update public.members set phone='+917599000110' where id=pg_temp.aid(110);
 perform set_config('request.jwt.claims','',true);
 return query select * from pg_temp.evidence_authorize(110,false,'WSP recipient drift before I/O');
 return query select * from pg_temp.evidence_authorize(111,true,'WSP independent other service grant');
 return query select * from pg_temp.evidence_authorize(112,true,'WSP current service evidence preserved');
 -- Fresh registration probes prevent immutability from masking a missing FK.
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 -- Fresh attempt FKs reference ordinary source notifications, not paid children.
 -- A paid child may only be generated after successful I/O authorization.
 insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active) values(pg_temp.aid(2050),pg_temp.aid(1),'evidence_payment','whatsapp_link','en','payment','Your receipt is available in the app.',true);
 insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at) values(pg_temp.aid(2051),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(2050),'bh-payment','psh-payment','payment_evidence','tpl-payment','en','payment',now(),now());
 insert into public.notifications(id,tenant_id,member_id,channel,status,category,dedupe_key,payload)
 select pg_temp.aid(v.n),pg_temp.aid(1),pg_temp.aid(112),'in_app','scheduled','payment','evidence-fk-'||v.n,'{"body":"Your receipt is available in the app."}'::jsonb from (values(2001),(2002),(2003),(2004)) v(n);
 for n in select unnest(array[2001,2002,2003,2004]) loop
  perform public.send_notification(pg_temp.aid(n));
 end loop;
 perform pg_temp.claim('gym_owner',25,null,905,2,false);
 perform public.record_whatsapp_consent(pg_temp.aid(107),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(2005));
 perform set_config('request.jwt.claims','',true);
 return next lives_ok(format('select pg_temp.attempt_probe(2001,%L::uuid)',(select id from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(112) and purpose='service' order by recorded_at desc,id desc limit 1)),'WSP-010: valid fresh evidence registration accepted');
 return next throws_ok('select pg_temp.attempt_probe(2002,null)','23502',null,'WSP-010: missing channel evidence rejected');
 return next throws_ok(format('select pg_temp.attempt_probe(2003,%L::uuid)',(select id from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) and member_id=pg_temp.aid(101) and purpose='service' order by recorded_at desc,id desc limit 1)),'23503',null,'WSP-010: foreign member channel evidence rejected');
 return next throws_ok(format('select pg_temp.attempt_probe(2004,%L::uuid)',(select id from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(2) and member_id=pg_temp.aid(107) and purpose='service' order by recorded_at desc,id desc limit 1)),'23503',null,'WSP-010: foreign tenant channel evidence rejected');
 return next isnt(pg_temp.refusal(format('update public.notification_whatsapp_attempts set channel_consent_id=(select id from public.whatsapp_channel_consents where member_id=%L::uuid order by recorded_at desc,id desc limit 1) where member_id=%L::uuid',pg_temp.aid(109),pg_temp.aid(109))),'SUCCESS','WSP-010: exact causal reference immutable even within same member');
 -- Manual handoff has no paid transport or wallet side effect.
 select balance_paise into before_balance from public.messaging_wallets where tenant_id=pg_temp.aid(1);
 select count(*) into before_attempts from public.notification_whatsapp_attempts where tenant_id=pg_temp.aid(1);
 select count(*) into before_ledger from public.messaging_wallet_ledger where tenant_id=pg_temp.aid(1);
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 perform public.open_notification_whatsapp((select id from wsp_ids where k='src_111'));
 return next is((select count(*) from public.notification_whatsapp_attempts where tenant_id=pg_temp.aid(1)),before_attempts,'WSP-M03: manual handoff adds no attempt');
 return next is((select balance_paise from public.messaging_wallets where tenant_id=pg_temp.aid(1)),before_balance,'WSP-M03: manual handoff preserves balance');
 return next is((select count(*) from public.messaging_wallet_ledger where tenant_id=pg_temp.aid(1)),before_ledger,'WSP-M03: manual handoff appends no movement');
 -- Promotions have distinct generic marketing AND channel marketing evidence.
 perform public.record_consent(pg_temp.aid(101),'marketing',true,'promo-v1','desk_verification',pg_temp.aid(1900));

 insert into public.message_templates(id,tenant_id,key,channel,locale,category,body,is_active) values(pg_temp.aid(1902),pg_temp.aid(1),'promo_evidence','whatsapp_link','en','promotion','Promotion notice',true);
 insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at) values(pg_temp.aid(1903),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(1902),'bh-promo','psh-promo','promo_evidence','tpl-promo','en','promotion',now(),now());
 -- Before opt-in, an independently valid new event refuses during preparation:
 -- a refusal marker must not manufacture a transport attempt.
 insert into public.notifications(id,tenant_id,member_id,channel,status,category,dedupe_key,payload) values(pg_temp.aid(1804),pg_temp.aid(1),pg_temp.aid(101),'in_app','scheduled','promotion','evidence-prep-no-optin','{"body":"Promotion notice"}');
 perform public.send_notification(pg_temp.aid(1804));
 select to_jsonb(nn) into prep_source from public.notifications nn where nn.id=pg_temp.aid(1804);
 c:=public.request_whatsapp_dispatch(pg_temp.aid(1804),pg_temp.aid(1805));
 return next is(c->>'queued','false','WSP-003: missing channel grant refuses preparation');
 return next is((select count(*) from public.notification_whatsapp_attempts where notification_id=pg_temp.aid(1804)),0::bigint,'WSP-003: preparation refusal invents no attempt');
 return next ok(not exists(select 1 from public.notifications where source_notification_id=pg_temp.aid(1804) and channel='whatsapp_link'),'WSP-003: preparation refusal creates no paid child');
 return next is((select count(*) from public.messaging_wallet_ledger where notification_id=pg_temp.aid(1804)),0::bigint,'WSP-003: preparation refusal debits nothing');
 return next is((select to_jsonb(nn) from public.notifications nn where nn.id=pg_temp.aid(1804)),prep_source,'WSP-003: preparation preserves factual sent source');
 perform public.record_whatsapp_consent(pg_temp.aid(101),'marketing',true,'wsp-notice-v1','desk_verification',pg_temp.aid(1901));
 insert into public.notifications(id,tenant_id,member_id,channel,status,category,dedupe_key,payload) values(pg_temp.aid(1904),pg_temp.aid(1),pg_temp.aid(101),'in_app','scheduled','promotion','evidence-promo','{"body":"Promotion notice"}');
 perform public.send_notification(pg_temp.aid(1904));
 return next lives_ok($q$select public.request_whatsapp_dispatch(pg_temp.aid(1904),pg_temp.aid(1905))$q$,'WSP: valid promotion queues');
 perform set_config('request.jwt.claims','',true);
 c:=public.claim_whatsapp_dispatch(10);
 return next is(jsonb_array_length(c->'attempts'),1,'WSP: valid marketing opt-in claims');
 select (c->'attempts'->0->>'attemptId')::uuid into a;
 return next ok(exists(select 1 from public.notification_whatsapp_attempts aa join public.whatsapp_channel_consents cc on cc.id=aa.channel_consent_id where aa.id=a and cc.member_id=aa.member_id and cc.tenant_id=aa.tenant_id and cc.purpose='marketing' and cc.granted),'WSP: promotion pins marketing channel evidence');
 return next ok(exists(select 1 from public.notification_whatsapp_attempts aa join public.consents cc on cc.id=aa.consent_id where aa.id=a and cc.member_id=aa.member_id and cc.tenant_id=aa.tenant_id and cc.purpose='marketing' and cc.granted),'WSP: promotion keeps generic marketing evidence');
 -- Pin the claimed attempt explicitly; transaction timestamps may tie.
 return query select * from pg_temp.evidence_authorize(101,true,'WSP valid promotion final authorization',a);
end $b$;
select * from pg_temp.visible_tap_block_1();
select * from finish();
rollback;
