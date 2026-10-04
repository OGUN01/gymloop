-- Independent WSP-003/010 causal channel evidence; public retained declaration 2026-10-04.
-- Hardening 2026-10-04: authorize/claim paths are guarded so the full plan runs
-- RED under the ctid tie-break defect instead of aborting at the first
-- authorize; every original expectation retained, two contract-true
-- additions (claim never leases the withdrawn member; claim leased 101).
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(19);
create function pg_temp.aid(n integer) returns uuid language sql immutable as $f$select ('80300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$f$;
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
insert into public.organizations(id,name,gym_code,status) values(pg_temp.aid(1),'WSP A','WSP8OA','active'),(pg_temp.aid(2),'WSP B','WSP8OB','active');
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

-- Frozen recorded_at/id order. Bootstrap copies command-derived exact current
-- recipient evidence; only these deliberate rows share a recording instant.
create function pg_temp.ordering_contract() returns setof text language plpgsql security invoker as $b$
declare m integer; stamp timestamptz; c jsonb; r jsonb; att uuid; ticket uuid;
begin
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 for m in select unnest(array[101,102,109,110]) loop
  perform public.record_whatsapp_consent(pg_temp.aid(m),'service',true,'wsp-notice-v1','desk_verification',pg_temp.aid(3000+m));
 end loop;
 create temp table ordering_seed as select distinct on (member_id) * from public.whatsapp_channel_consents where tenant_id=pg_temp.aid(1) order by member_id,recorded_at desc,id desc;
 perform set_config('request.jwt.claims','',true);
 insert into public.whatsapp_sender_accounts(id,tenant_id,provider,waba_id,sender_id,secret_reference,enabled,compliance_approved_at,template_ready_at,config_revision) values(pg_temp.aid(501),pg_temp.aid(1),'meta','waba-ordering','sender-ordering','vault:wsp_ordering_fixture',true,now()-interval '1 hour',now()-interval '1 hour','cfg-ordering');
 insert into public.whatsapp_template_revisions(id,tenant_id,sender_account_id,template_id,body_hash,parameter_schema_hash,provider_template_name,provider_template_id,locale,category,approved_at,checked_at) values(pg_temp.aid(502),pg_temp.aid(1),pg_temp.aid(501),pg_temp.aid(451),'bh-o','psh-o','ordering_template','tpl-o','en','renewal',now(),now());
 insert into public.whatsapp_rate_versions(id,tenant_id,sender_account_id,effective_from,destination_market,provider_category,amount_paise,max_amount_paise,currency,rounding_revision,evidence_digest) values(pg_temp.aid(503),pg_temp.aid(1),pg_temp.aid(501),now()-interval '1 hour','IN','marketing',100,100,'INR','all_in','ordering-evidence');
 insert into public.messaging_wallets(tenant_id,balance_paise,currency) values(pg_temp.aid(1),0,'INR');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(917),'role','authenticated','app_role','super_admin')::text,true);
 perform public.adjust_messaging_wallet_paise(pg_temp.aid(1),1000,'INR','ordering-test-funding',pg_temp.aid(3500));
 perform set_config('request.jwt.claims','',true);
 stamp:=clock_timestamp();
 -- Higher UUID grant first, lower UUID withdrawal LAST: physical order loses.
 insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at)
 select v.id,s.tenant_id,s.member_id,s.purpose,v.granted,s.notice_version,'verified_fixture',s.recipient_phone_digest,s.contact_version_ref,s.recipient_basis,s.recorded_by_staff_id,stamp from ordering_seed s cross join (values(pg_temp.aid(4101),true),(pg_temp.aid(4001),false)) v(id,granted) where s.member_id=pg_temp.aid(101) order by v.id desc;
 -- Higher UUID withdrawal first, lower UUID grant LAST: historical grant loses.
 insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at)
 select v.id,s.tenant_id,s.member_id,s.purpose,v.granted,s.notice_version,'verified_fixture',s.recipient_phone_digest,s.contact_version_ref,s.recipient_basis,s.recorded_by_staff_id,stamp from ordering_seed s cross join (values(pg_temp.aid(4102),false),(pg_temp.aid(4002),true)) v(id,granted) where s.member_id=pg_temp.aid(102) order by v.id desc;
 return next is((select granted from public.whatsapp_channel_consents where member_id=pg_temp.aid(101) order by recorded_at desc,id desc limit 1),true,'WSP ordering: highest UUID grant is current despite last inserted withdrawal');
 return next is((select granted from public.whatsapp_channel_consents where member_id=pg_temp.aid(102) order by recorded_at desc,id desc limit 1),false,'WSP ordering: highest UUID withdrawal is current despite last inserted grant');
 perform pg_temp.claim('gym_owner',21,null,901,1,false);
 c:=public.request_whatsapp_dispatch((select id from wsp_ids where k='src_101'),pg_temp.aid(3601));
 return next is(c->>'queued','true','WSP ordering: preparation admits exact highest grant');
 c:=public.request_whatsapp_dispatch((select id from wsp_ids where k='src_102'),pg_temp.aid(3602));
 return next is(c->>'queued','false','WSP ordering: preparation rejects exact highest withdrawal');
 return next is((select count(*) from public.notification_whatsapp_attempts where member_id=pg_temp.aid(102)),0::bigint,'WSP ordering: withdrawal preparation creates no attempt');
 perform public.request_whatsapp_dispatch((select id from wsp_ids where k='src_109'),pg_temp.aid(3609));
 perform public.request_whatsapp_dispatch((select id from wsp_ids where k='src_110'),pg_temp.aid(3610));
 perform set_config('request.jwt.claims','',true);
 c:=public.claim_whatsapp_dispatch(10);
 return next is(jsonb_array_length(c->'attempts'),3,'WSP ordering: claim admits three current grants only');
 return next ok(not exists(select 1 from public.notification_whatsapp_attempts where member_id=pg_temp.aid(102)),'WSP ordering: claim never leases the withdrawn member 102');
 return next is((select channel_consent_id from public.notification_whatsapp_attempts where member_id=pg_temp.aid(101)),pg_temp.aid(4101),'WSP ordering: claim pins UUID-highest exact evidence');
 select id,lease_ticket into att,ticket from public.notification_whatsapp_attempts where member_id=pg_temp.aid(101);
 return next ok(att is not null and ticket is not null,'WSP ordering: claim leased member 101 attempt for final I/O');
 if att is not null then
  begin
   r:=public.authorize_whatsapp_dispatch(att,ticket);
  exception when others then
   r:=jsonb_build_object('authorized',null::text,'captured_sqlstate',sqlstate,'captured_message',sqlerrm);
  end;
 else
  r:=null::jsonb;
 end if;
 return next is(r->>'authorized','true','WSP ordering: final I/O admits pinned highest grant despite lower withdrawal');
 -- For 109 and 110, the pinned seed is superseded at a genuinely later instant.
 -- Two tied new decisions again have opposite insertion and UUID orders.
 stamp:=clock_timestamp();
 insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at)
 select v.id,s.tenant_id,s.member_id,s.purpose,v.granted,'wsp-notice-v2','verified_fixture',s.recipient_phone_digest,s.contact_version_ref,s.recipient_basis,s.recorded_by_staff_id,stamp from ordering_seed s cross join (values(pg_temp.aid(4109),true),(pg_temp.aid(4009),false)) v(id,granted) where s.member_id=pg_temp.aid(109) order by v.id desc;
 insert into public.whatsapp_channel_consents(id,tenant_id,member_id,purpose,granted,notice_version,source,recipient_phone_digest,contact_version_ref,recipient_basis,recorded_by_staff_id,recorded_at)
 select v.id,s.tenant_id,s.member_id,s.purpose,v.granted,'wsp-notice-v2','verified_fixture',s.recipient_phone_digest,s.contact_version_ref,s.recipient_basis,s.recorded_by_staff_id,stamp from ordering_seed s cross join (values(pg_temp.aid(4110),false),(pg_temp.aid(4010),true)) v(id,granted) where s.member_id=pg_temp.aid(110) order by v.id desc;
 for m in select unnest(array[109,110]) loop
  select id,lease_ticket into att,ticket from public.notification_whatsapp_attempts where member_id=pg_temp.aid(m);
  if att is not null then
   begin
    r:=public.authorize_whatsapp_dispatch(att,ticket);
   exception when others then
    r:=jsonb_build_object('authorized',null::text,'captured_sqlstate',sqlstate,'captured_message',sqlerrm);
   end;
  else
   r:=null::jsonb;
  end if;
  return next is(r->>'authorized','false','WSP ordering: changed exact current evidence blocks final I/O '||m);
  return next ok(exists(select 1 from public.notification_whatsapp_attempts where id=att and failure_code='opted_out' and released_at is not null and io_started_at is null),'WSP ordering: refusal is durable without I/O '||m);
  return next ok(not exists(select 1 from public.notifications where source_notification_id=(select id from wsp_ids where k='src_'||m) and dedupe_key='whatsapp-paid:'||(select id from wsp_ids where k='src_'||m)::text),'WSP ordering: no paid child from refused evidence '||m);
  return next is((select count(*) from public.messaging_wallet_ledger where notification_id=(select id from wsp_ids where k='src_'||m)),0::bigint,'WSP ordering: no debit from refused evidence '||m);
 end loop;
 return next is((select count(*) from public.notifications where id in ((select id from wsp_ids where k='src_109'),(select id from wsp_ids where k='src_110')) and status='sent'),2::bigint,'WSP ordering: refused attempts preserve factual sent sources');
end$b$;
select * from pg_temp.ordering_contract();
select * from finish();
rollback;
