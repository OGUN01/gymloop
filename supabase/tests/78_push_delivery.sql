-- NTF-001..016 independent visible contract (Wave C push delivery).
-- Frozen authority: openspec/changes/push-notifications/{proposal,transport-amendment,
-- pre-configuration-amendment}.md plus v2-batch2-shared/wave-c-serial-freeze-declarations.md.
-- No cross-session concurrency claimed; races are modeled sequentially. The provider is
-- unconfigured in every run (the approved default), so configured dispatch behavior and
-- quiet-hour boundary reasons are pinned by the contract and verified at configured
-- acceptance, not here.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(138);
create function pg_temp.aid(n integer) returns uuid language sql immutable as $$select ('78100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.ntf_claim(r text default 'gym_owner',s integer default null,m integer default null,u integer default 901,t integer default 1,p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.aid(u),'role','authenticated','app_role',r,'tenant_id',pg_temp.aid(t),'staff_id',case when s is not null then pg_temp.aid(s) end,'member_id',case when m is not null then pg_temp.aid(m) end,'impersonation_session_id',case when p then pg_temp.aid(999) end))::text,true); end$$;
create function pg_temp.ntf_refusal(q text) returns text language plpgsql as $$declare detail text; begin begin execute q; raise exception using errcode='Z7500'; exception when others then if sqlstate='Z7500' then return 'SUCCESS'; end if; get stacked diagnostics detail=PG_EXCEPTION_DETAIL; return sqlstate||case when detail<>'' then ':'||detail else '' end; end; end$$;
create temp table ntf_ids(k text primary key,id uuid not null);
grant all on ntf_ids to authenticated,service_role;
grant execute on function pg_temp.aid(integer),pg_temp.ntf_claim(text,integer,integer,integer,integer,boolean),pg_temp.ntf_refusal(text) to authenticated,anon,service_role;

-- ============ A. canonical vocabulary and table shapes ============
select enum_has_labels('public','message_category',array['renewal','payment','fulfilment','promotion','motivation','class_update','announcement']::name[],'NTF-002: canonical message_category unchanged by NTF');
select enum_has_labels('public','notification_status',array['scheduled','sent','delivered','failed','clicked','converted','opted_out']::name[],'NTF contract: canonical notification_status unchanged by NTF');
select enum_has_labels('public','notification_channel',array['push','whatsapp_link','in_app','sms','email']::name[],'NTF contract: canonical notification_channel unchanged by NTF');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid='public.member_devices'::regclass and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('created_at' collate "default"),('id' collate "default"),('installation_id' collate "default"),('invalidated_at' collate "default"),('invalidated_reason' collate "default"),('is_active' collate "default"),('last_seen_at' collate "default"),('member_id' collate "default"),('platform' collate "default"),('push_token' collate "default"),('registered_user_id' collate "default"),('tenant_id' collate "default"),('token_revision' collate "default"),('updated_at' collate "default")) as expected order by column1 collate "default"$q$,
'NTF contract: member_devices exact amended columns');
select is((select count(*)::integer from pg_attribute a join pg_type t on t.oid=a.atttypid where a.attrelid='public.member_devices'::regclass and a.attname in('registered_user_id','installation_id') and t.typname='uuid'),2,'NTF contract: device identity columns are uuids');
select is((select count(*)::integer from pg_attribute a join pg_type t on t.oid=a.atttypid where a.attrelid='public.member_devices'::regclass and a.attname='token_revision' and t.typname='int8'),1,'NTF contract: token_revision is bigint');
select is((select count(*)::integer from pg_index i where i.indrelid='public.member_devices'::regclass and i.indisunique and i.indnkeyatts=3 and (select string_agg(a.attname,',' order by ord) from unnest(i.indkey::smallint[]) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=ord.attnum)='tenant_id,member_id,installation_id'),1,'NTF contract: unique (tenant,member,installation) on member_devices');
select is((select count(*)::integer from pg_index i where i.indrelid='public.member_devices'::regclass and i.indisunique and i.indnkeyatts=2 and (select string_agg(a.attname,',' order by ord) from unnest(i.indkey::smallint[]) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=ord.attnum) in('tenant_id,push_token','push_token,tenant_id')),1,'NTF contract: existing tenant/token uniqueness retained');
select is((select count(*)::integer from pg_constraint c where c.conrelid='public.member_devices'::regclass and c.contype='f' and c.confrelid='public.members'::regclass and cardinality(c.conkey)=2 and cardinality(c.confkey)=2 and c.conkey[1]=(select attnum from pg_attribute where attrelid='public.member_devices'::regclass and attname='tenant_id')),1,'NTF contract: composite tenant/member FK on member_devices');
select ok((select relrowsecurity from pg_class where oid='public.member_devices'::regclass) and not coalesce(has_table_privilege('authenticated','public.member_devices','SELECT'),false) and not coalesce(has_table_privilege('authenticated','public.member_devices','INSERT'),false) and not coalesce(has_table_privilege('authenticated','public.member_devices','UPDATE'),false) and not coalesce(has_table_privilege('authenticated','public.member_devices','DELETE'),false) and not coalesce(has_table_privilege('anon','public.member_devices','SELECT'),false),'NTF contract: member_devices RLS with every ordinary privilege revoked; tokens projected only by RPC');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.member_notification_preferences') and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('category' collate "default"),('created_at' collate "default"),('enabled' collate "default"),('member_id' collate "default"),('tenant_id' collate "default"),('updated_at' collate "default")) as expected order by column1 collate "default"$q$,
'NTF contract: member_notification_preferences exact columns');
select is((select count(*)::integer from pg_constraint c where c.conrelid=to_regclass('public.member_notification_preferences') and c.contype='p' and (select string_agg(a.attname,',' order by ord) from unnest(c.conkey) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=ord.attnum)='tenant_id,member_id,category'),1,'NTF contract: preferences PK (tenant,member,category)');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.member_notification_preferences')) and coalesce(has_table_privilege('authenticated',to_regclass('public.member_notification_preferences'),'SELECT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_notification_preferences'),'INSERT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_notification_preferences'),'UPDATE'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_notification_preferences'),'DELETE'),false),'NTF contract: preferences own-member read-only grants, writes through the definer command');
select is((select count(*)::integer from pg_policy where polrelid=to_regclass('public.member_notification_preferences')),1,'NTF contract: preferences exactly one own-member policy');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.notification_push_campaigns') and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('announcement_id' collate "default"),('cancelled_at' collate "default"),('created_at' collate "default"),('created_by_staff_id' collate "default"),('id' collate "default"),('request_key' collate "default"),('reviewed_at' collate "default"),('reviewed_by_staff_id' collate "default"),('tenant_id' collate "default"),('updated_at' collate "default"),('version_no' collate "default")) as expected order by column1 collate "default"$q$,
'NTF contract: notification_push_campaigns exact columns');
select is((select count(*)::integer from pg_constraint c where c.conrelid=to_regclass('public.notification_push_campaigns') and c.contype='u'),2,'NTF contract: campaigns exactly two uniques (version, request key)');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.notification_push_campaigns')) and coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_campaigns'),'SELECT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_campaigns'),'INSERT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_campaigns'),'UPDATE'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_campaigns'),'DELETE'),false),'NTF contract: campaigns front-office read-only grants');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.notification_push_attempts') and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('completed_at' collate "default"),('device_id' collate "default"),('failure_code' collate "default"),('id' collate "default"),('member_id' collate "default"),('notification_id' collate "default"),('provider_message_id' collate "default"),('registered_user_id' collate "default"),('reservation_id' collate "default"),('started_at' collate "default"),('tenant_id' collate "default"),('token_revision' collate "default"),('uncertain_at' collate "default")) as expected order by column1 collate "default"$q$,
'NTF contract: notification_push_attempts exact columns (no raw token, no payload column)');
select ok(not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_attempts'),'SELECT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_attempts'),'INSERT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_attempts'),'UPDATE'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.notification_push_attempts'),'DELETE'),false) and not coalesce(has_table_privilege('anon',to_regclass('public.notification_push_attempts'),'SELECT'),false),'NTF contract: attempts no authenticated/anon grants at all');
select is((select count(*)::integer from pg_constraint c where c.conrelid=to_regclass('public.notification_push_attempts') and c.contype='u'),1,'NTF contract: attempts exactly one unique (tenant,notification,device) per the serial revision rule');
select ok((select bool_and(cnt>=1) from (
  select count(*)::integer cnt from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='tenant_id'
  where c.contype='f' and cardinality(c.conkey)>=2 and c.conkey[1]=a.attnum
  and c.conrelid in(to_regclass('public.notification_push_campaigns'),to_regclass('public.notification_push_attempts'),to_regclass('public.member_notification_preferences'))
  group by c.conrelid) s),'NTF contract: every new table carries a composite tenant FK');

-- ============ fixtures ============
insert into public.organizations(id,name,gym_code,status) values(pg_temp.aid(1),'NTF A','NTF78A','active'),(pg_temp.aid(2),'NTF B','NTF78B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.aid(11),pg_temp.aid(1),'A',true),(pg_temp.aid(12),pg_temp.aid(2),'B',true);
insert into auth.users(id) select pg_temp.aid(n) from generate_series(901,914) n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.aid(21),pg_temp.aid(1),pg_temp.aid(901),pg_temp.aid(11),'gym_owner','Owner'),
(pg_temp.aid(22),pg_temp.aid(1),pg_temp.aid(902),pg_temp.aid(11),'gym_manager','Manager'),
(pg_temp.aid(23),pg_temp.aid(1),pg_temp.aid(903),pg_temp.aid(11),'front_desk','Desk'),
(pg_temp.aid(24),pg_temp.aid(1),pg_temp.aid(904),pg_temp.aid(11),'trainer','Trainer'),
(pg_temp.aid(25),pg_temp.aid(2),pg_temp.aid(905),pg_temp.aid(12),'gym_owner','Other');
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,date_of_birth,status,erased_at) values
(pg_temp.aid(101),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(906),'PRIVATE_MEMBER_101','+917810000101','1990-01-01','active',null),
(pg_temp.aid(102),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(907),'PRIVATE_MEMBER_102','+917810000102','1990-01-01','active',null),
(pg_temp.aid(103),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(908),'PRIVATE_MINOR_NOGUARD','+917810000103',(app.gym_today(pg_temp.aid(1))-10)::date,'active',null),
(pg_temp.aid(104),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(909),'PRIVATE_MINOR_GUARDIAN','+917810000104',(app.gym_today(pg_temp.aid(1))-10)::date,'active',null),
(pg_temp.aid(105),pg_temp.aid(1),pg_temp.aid(11),pg_temp.aid(910),'PRIVATE_BLOCKED_105','+917810000105','1990-01-01','blocked',null),
(pg_temp.aid(107),pg_temp.aid(2),pg_temp.aid(12),pg_temp.aid(912),'PRIVATE_FOREIGN_MEMBER','+917810000107','1990-01-01','active',null);
update public.members set guardian_name='Guardian Four',guardian_relation='mother',guardian_phone='+917819000909',guardian_email='guardian909@example.test',guardian_linked_at=statement_timestamp() where id=pg_temp.aid(104);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.aid(201),pg_temp.aid(1),'NTF plan',30,100000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,currency) values
(pg_temp.aid(301),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1))+30,100000,'INR'),
(pg_temp.aid(302),pg_temp.aid(1),pg_temp.aid(102),pg_temp.aid(201),'active',app.gym_today(pg_temp.aid(1))-1,app.gym_today(pg_temp.aid(1))+30,100000,'INR');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at) values
(pg_temp.aid(401),pg_temp.aid(1),pg_temp.aid(101),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(402),pg_temp.aid(1),pg_temp.aid(102),'service',true,'v1','signup',now()-interval '1 day'),
(pg_temp.aid(403),pg_temp.aid(1),pg_temp.aid(101),'marketing',true,'v1','signup',now()-interval '1 day');
-- legacy device row: provenance unknown until self-registration; second device pre-registered
insert into public.member_devices(id,tenant_id,member_id,platform,push_token,is_active,last_seen_at,installation_id,token_revision,registered_user_id) values
(pg_temp.aid(601),pg_temp.aid(1),pg_temp.aid(101),'android','legacy-token-781',true,now()-interval '30 days',pg_temp.aid(651),1,null),
(pg_temp.aid(661),pg_temp.aid(1),pg_temp.aid(101),'android','fcm-token-781-H',true,now(),pg_temp.aid(662),1,pg_temp.aid(906));
insert into public.notifications(id,tenant_id,member_id,channel,status,category,dedupe_key,related_type,related_id,scheduled_for,payload) values
(pg_temp.aid(801),pg_temp.aid(1),pg_temp.aid(101),'push','scheduled','renewal','renewal:781membership:781member',null,null,statement_timestamp(),'{"body":"Renewal due"}'),
(pg_temp.aid(802),pg_temp.aid(1),pg_temp.aid(101),'in_app','scheduled','class_update','class-cancelled:781session:781member',null,null,statement_timestamp(),'{"body":"Class cancelled"}'),
(pg_temp.aid(803),pg_temp.aid(1),pg_temp.aid(101),'push','scheduled','promotion','promo:781fix:101',null,null,statement_timestamp(),'{"body":"Promo"}'),
(pg_temp.aid(804),pg_temp.aid(1),pg_temp.aid(101),'push','scheduled','payment','payment:781fix:101',null,null,statement_timestamp(),'{"body":"Payment"}'),
(pg_temp.aid(805),pg_temp.aid(1),pg_temp.aid(101),'push','scheduled','motivation','motivation:781fix:101',null,null,statement_timestamp(),'{"body":"Absent alert"}');
insert into public.notification_push_attempts(id,tenant_id,member_id,notification_id,device_id,token_revision,registered_user_id,reservation_id,started_at,completed_at,provider_message_id) values
(pg_temp.aid(851),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(801),pg_temp.aid(652),2,pg_temp.aid(906),pg_temp.aid(861),now()-interval '1 minute',now(),'projects/781/messages/accepted-1'),
(pg_temp.aid(852),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(803),pg_temp.aid(652),2,pg_temp.aid(906),pg_temp.aid(862),now()-interval '1 minute',now()-interval '30 seconds',null),
(pg_temp.aid(854),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(804),pg_temp.aid(652),2,pg_temp.aid(906),pg_temp.aid(864),now()-interval '1 minute',now(),'projects/781/messages/accepted-2');
update public.notification_push_attempts set uncertain_at=now() where id=pg_temp.aid(852);
insert into public.notification_push_attempts(id,tenant_id,member_id,notification_id,device_id,token_revision,registered_user_id,reservation_id) values
(pg_temp.aid(853),pg_temp.aid(1),pg_temp.aid(101),pg_temp.aid(803),pg_temp.aid(661),1,pg_temp.aid(906),pg_temp.aid(863));
reset role;

-- ============ B. exact RPC postures ============
select is_empty($q$with expected(sig,vol) as
(values('public.register_member_push_device(uuid,text,text)','v'),
('public.unregister_member_push_device(uuid)','v'),
('public.read_member_push_settings()','s'),
('public.set_member_push_preference(public.message_category,boolean)','v'),
('public.acknowledge_member_push(uuid,uuid,bigint,text)','v'),
('public.review_announcement_push(uuid,integer,uuid)','v'),
('public.cancel_announcement_push(uuid)','v'))
select sig from expected e left join pg_proc p on p.oid=to_regprocedure(e.sig)
where p.oid is null or not p.prosecdef or p.provolatile::text<>e.vol or pg_get_userbyid(p.proowner)<>'postgres' or not coalesce(p.proconfig @> array['search_path=""'],false) or not has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('service_role',p.oid,'EXECUTE')$q$,
'NTF contract: seven member/admin commands are postgres definers, authenticated-only, empty search_path');
select is_empty($q$with expected(sig) as
(values('public.reserve_push_attempts(integer)'),
('public.authorize_push_attempt(uuid,uuid)'),
('public.finish_push_attempt(uuid,uuid,text,text,boolean)'))
select sig from expected e left join pg_proc p on p.oid=to_regprocedure(e.sig)
where p.oid is null or p.prosecdef or p.provolatile::text not in('v','s') or pg_get_userbyid(p.proowner)<>'postgres' or not coalesce(p.proconfig @> array['search_path=""'],false) or not has_function_privilege('service_role',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE')$q$,
'NTF contract: transport facades are invoker postgres routines with service_role-only EXECUTE');
select ok(exists(select 1 from pg_proc p where oid=to_regprocedure('public.read_push_campaigns(timestamp with time zone,uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and coalesce(p.proconfig @> array['search_path=""'],false) and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')),'NTF contract: campaign reader is a front-office postgres definer, authenticated-only against anon');
select ok(not has_function_privilege('authenticated',to_regprocedure('app.run_push_events(uuid)'),'EXECUTE') and not has_function_privilege('anon',to_regprocedure('app.run_push_events(uuid)'),'EXECUTE'),'NTF contract: SQL event runner denied to ordinary callers');
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select app.run_push_events(pg_temp.aid(1))$q$),'42501','NTF contract: an ordinary authenticated caller cannot run the SQL event runner');
reset role;

-- ============ C. device registration and rotation ============
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
create temp table ntf_reg as select public.register_member_push_device(pg_temp.aid(652),'fcm-token-781-A','android') as result;
select is((select (result->>'tokenRevision')::int from ntf_reg),1,'NTF-003: first registration is revision one');
select is((select registered_user_id from public.member_devices where id=(select (result->>'deviceId')::uuid from ntf_reg)),pg_temp.aid(906),'NTF-003: device binds the authenticated account');
select is((select is_active from public.member_devices where id=(select (result->>'deviceId')::uuid from ntf_reg)),true,'NTF-003: registered device active');
select public.register_member_push_device(pg_temp.aid(652),'fcm-token-781-A','android') as result;
select is((select token_revision from public.member_devices where installation_id=pg_temp.aid(652) and member_id=pg_temp.aid(101)),1::bigint,'NTF-003: same installation/token replay inert, no revision bump');
select is((select count(*)::integer from public.member_devices where member_id=pg_temp.aid(101) and installation_id=pg_temp.aid(652)),1,'NTF-003: replay creates no second row');
select public.register_member_push_device(pg_temp.aid(652),'fcm-token-781-A2','android') as result;
select is((select token_revision from public.member_devices where installation_id=pg_temp.aid(652) and member_id=pg_temp.aid(101)),2::bigint,'NTF-004: rotation increments revision atomically');
select is((select token_revision from public.member_devices where installation_id=pg_temp.aid(652) and member_id=pg_temp.aid(101)),2::bigint,'NTF-004: rotation leaves the frozen revision readable without reading the raw token');
select is((select is_active from public.member_devices where installation_id=pg_temp.aid(652) and member_id=pg_temp.aid(101)),true,'NTF-004: rotated device stays active with cleared invalidation');
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(653),'fcm-token-781-B','ios')$q$),'22023','NTF-003: non-Android platform refused');
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(653),'','android')$q$),'22023','NTF-003: blank token refused');
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(653),repeat('x',4097),'android')$q$),'22023','NTF contract: token above 4096 characters refused');
select is(pg_temp.ntf_refusal($q$insert into public.member_devices(id,tenant_id,member_id,platform,push_token,is_active,last_seen_at) values(pg_temp.aid(655),pg_temp.aid(1),pg_temp.aid(101),'android','direct-781',true,now())$q$),'42501','NTF contract: direct authenticated device INSERT revoked');
select is(pg_temp.ntf_refusal($q$select push_token from public.member_devices limit 1$q$),'42501','NTF contract: direct authenticated token SELECT revoked');
select is(pg_temp.ntf_refusal($q$update public.member_devices set is_active=false where member_id=pg_temp.aid(101)$q$),'42501','NTF contract: direct authenticated device UPDATE revoked');
reset role;
select pg_temp.ntf_claim('member',null,102,907,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(654),'fcm-token-781-A2','android')$q$),'23505','NTF-003: another member registering the same token is a generic conflict');
select ok(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(654),'fcm-token-781-A2','android')$q$) not like '%PRIVATE%' and pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(654),'fcm-token-781-A2','android')$q$) not like '%78100000-0000-4000-8000-000000000101%','NTF-003/013: token conflict leaks no other member identity');
select is((select count(*)::integer from public.member_devices where installation_id=pg_temp.aid(654)),0,'NTF-003: refused collision creates no row');
reset role;
select pg_temp.ntf_claim('member',null,103,908,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(656),'fcm-token-781-C','android')$q$),'42501','NTF-003: known minor without a complete guardian record cannot register a device');
reset role;
select pg_temp.ntf_claim('member',null,104,909,1,false);
set local role authenticated;
create temp table ntf_minor_reg as select public.register_member_push_device(pg_temp.aid(657),'fcm-token-781-D','android') as result;
select is((select registered_user_id from public.member_devices where id=(select (result->>'deviceId')::uuid from ntf_minor_reg)),pg_temp.aid(909),'NTF-003: guardian-linked minor with a complete record registers on the linked account');
reset role;
select pg_temp.ntf_claim('member',null,105,910,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(658),'fcm-token-781-E','android')$q$),'42501','NTF-003: blocked member cannot register a device');
reset role;
select pg_temp.ntf_claim();
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.register_member_push_device(pg_temp.aid(659),'fcm-token-781-F','android')$q$),'42501','NTF contract: missing complete actor precedes device registration');
reset role;

-- legacy provenance-null row stays inactive; matching self-registration adopts it
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
select is((select bool_and((d.value->>'active')='false') from jsonb_array_elements(public.read_member_push_settings()::jsonb->'devices') d where d.value->>'id'=pg_temp.aid(601)::text),true,'NTF-003: legacy provenance-null device is inactive until self-registration');
select public.register_member_push_device(pg_temp.aid(651),'legacy-token-781','android') as result;
select is((select registered_user_id from public.member_devices where installation_id=pg_temp.aid(651)),pg_temp.aid(906),'NTF-003: matching self-registration adopts the legacy row');
select is((select is_active from public.member_devices where installation_id=pg_temp.aid(651)),true,'NTF-003: adopted legacy device becomes active');
select is((select token_revision from public.member_devices where installation_id=pg_temp.aid(651)),1::bigint,'NTF-003: adopting an untouched legacy row starts at revision one');
reset role;

-- ============ D. unregister ============
select pg_temp.ntf_claim('member',null,102,907,1,false);
set local role authenticated;
create temp table ntf_b_reg as select public.register_member_push_device(pg_temp.aid(660),'fcm-token-781-G','android') as result;
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
create temp table ntf_unreg as select public.unregister_member_push_device(pg_temp.aid(660)) as result;
select is((select (result->>'disabled')::text from ntf_unreg),'true','NTF-004: unregister answers disabled:true');
select is((select count(*)::integer from public.member_devices where installation_id=pg_temp.aid(660)),0,'NTF-004: another member''s device rows are invisible, not refused (no existence oracle)');
create temp table ntf_unreg2 as select public.unregister_member_push_device(pg_temp.aid(699)) as result;
select is((select (result->>'disabled')::text from ntf_unreg2),'true','NTF-004: unknown installation is inert disabled:true');
select public.unregister_member_push_device(pg_temp.aid(652)) as result;
select is((select is_active from public.member_devices where installation_id=pg_temp.aid(652)),false,'NTF-004: own unregister deactivates the exact device');
reset role;

-- ============ E. read settings ============
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
select ok(public.read_member_push_settings()::text not like '%fcm-token-781%' and public.read_member_push_settings()::text not like '%legacy-token-781%' and public.read_member_push_settings()::text not like '%guardian909%','NTF-013: settings projection carries no token or guardian contact');
select ok(public.read_member_push_settings()::jsonb ? 'preferences' and public.read_member_push_settings()::jsonb ? 'devices','NTF-016: settings exposes the preferences and devices keys');
reset role;
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.read_member_push_settings()$q$),'42501','NTF contract: staff identity gains no member settings read');
reset role;
select pg_temp.ntf_claim('trainer',24,null,904,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.read_member_push_settings()$q$),'42501','NTF contract: trainer gains no member settings read');
reset role;

-- ============ F. category preferences ============
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
create temp table ntf_pref as select public.set_member_push_preference('promotion',false) as result;
select is((select result->>'category' from ntf_pref),'promotion','NTF-002: preference answers its category');
select is((select (result->>'enabled')::text from ntf_pref),'false','NTF-002: preference answers its enabled value');
select is((select count(*)::integer from public.member_notification_preferences where member_id=pg_temp.aid(101) and category='promotion'),1,'NTF-002: preference persisted as one row');
select public.set_member_push_preference('promotion',false) as result;
select is((select count(*)::integer from public.member_notification_preferences where member_id=pg_temp.aid(101) and category='promotion'),1,'NTF-002: identical value replay inert');
select is((select count(*)::integer from public.consents where member_id=pg_temp.aid(101)),2,'NTF-002: preference change mutates no consent row');
select public.set_member_push_preference('renewal',true) as result;
select is((select count(*)::integer from public.member_notification_preferences where member_id=pg_temp.aid(101) and category='renewal'),1,'NTF-002: transactional category settable');
reset role;
select pg_temp.ntf_claim('member',null,102,907,1,false);
set local role authenticated;
select is((select count(*)::integer from public.member_notification_preferences where member_id=pg_temp.aid(101)),0,'NTF-002: another member cannot read foreign preference rows');
select public.set_member_push_preference('promotion',true) as result;
select is((select count(*)::integer from public.member_notification_preferences where member_id=pg_temp.aid(102) and category='promotion'),1,'NTF-002: foreign-context write created own row');
reset role;
select set_config('request.jwt.claims','',true);
select is((select enabled from public.member_notification_preferences where member_id=pg_temp.aid(101) and category='promotion'),false,'NTF-002: the foreign-context write left member 101''s row untouched');
reset role;
select pg_temp.ntf_claim('front_desk',23,null,903,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select * from public.member_notification_preferences$q$),'42501','NTF-002: front desk reads no preference rows');
reset role;
select pg_temp.ntf_claim('trainer',24,null,904,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select * from public.member_notification_preferences$q$),'42501','NTF-002: trainer reads no preference rows');
reset role;

-- ============ G. acknowledge_member_push ============
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
create temp table ntf_ack as select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),2,'received') as result;
select is((select result->>'status' from ntf_ack),'delivered','NTF-009: received moves the accepted push to delivered');
select is((select status::text from public.notifications where id=pg_temp.aid(801)),'delivered','NTF-009: delivered state persisted');
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),2,'seen')$q$),'22023','NTF-009: event outside received|opened refused');
create temp table ntf_open as select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),2,'opened') as result;
select is((select result->>'status' from ntf_open),'clicked','NTF-009: opened moves delivered to clicked');
select ok((select clicked_at is not null from public.notifications where id=pg_temp.aid(801)),'NTF-009: opened stamps clicked_at');
create temp table ntf_open2 as select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),2,'opened') as result;
select is((select result->>'deliveredAt' from ntf_open),(select result->>'deliveredAt' from ntf_open2),'NTF-009: replayed opened keeps the exact first evidence');
create temp table ntf_pending as select public.acknowledge_member_push(pg_temp.aid(804),pg_temp.aid(652),2,'opened') as result;
select is((select result->>'status' from ntf_pending),'clicked','NTF-009: opened applies sent→delivered→clicked with accepted attempt evidence');
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(9999),2,'opened')$q$),'42501','NTF-009: unknown device shares the refusal');
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(660),2,'opened')$q$),'42501','NTF-009: another member''s device shares the same refusal');
select ok(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),1,'opened')$q$) like 'GL118%','NTF-004/009: stale token revision refused with the receipt-evidence conflict code');
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(803),pg_temp.aid(652),2,'received')$q$),'42501','NTF-009: uncertain attempt is not accepted evidence');
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(802),pg_temp.aid(652),2,'received')$q$),'42501','NTF-009: in-app event has no push attempt evidence');
reset role;
select pg_temp.ntf_claim('member',null,102,907,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.acknowledge_member_push(pg_temp.aid(801),pg_temp.aid(652),2,'received')$q$),'42501','NTF-009: foreign member shares the identical refusal');
reset role;

-- ============ H. unconfigured transport is fail-closed ============
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
create temp table ntf_reserve as select public.reserve_push_attempts(10) as result;
select is((select result->>'configuration' from ntf_reserve),'provider_unconfigured','NTF-015/pre-config: unconfigured transport claims nothing');
select is((select count(*)::integer from ntf_reserve, jsonb_array_elements(result->'attempts')),0,'NTF-015: unconfigured reserve returns an empty attempt list');
select is((select count(*)::integer from public.notification_push_attempts),4,'NTF-015: unconfigured reserve creates no attempt rows');
select is(pg_temp.ntf_refusal($q$select public.reserve_push_attempts(0)$q$),'22023','NTF contract: reserve limit below one refused');
select is(pg_temp.ntf_refusal($q$select public.reserve_push_attempts(101)$q$),'22023','NTF contract: reserve limit above one hundred refused');
select ok(pg_temp.ntf_refusal($q$select public.authorize_push_attempt(pg_temp.aid(9999),pg_temp.aid(861))$q$) like 'P0002%','NTF contract: authorize on an unknown/foreign pair is target-invisible');
select ok(pg_temp.ntf_refusal($q$select public.finish_push_attempt(pg_temp.aid(9999),pg_temp.aid(861),'projects/781/messages/x',null,false)$q$) like 'P0002%','NTF contract: finish without a live reservation is target-invisible');
create temp table ntf_finish1 as select public.finish_push_attempt(pg_temp.aid(851),pg_temp.aid(861),'projects/781/messages/accepted-1',null,false) as result;
select is((select (result->>'replayed')::text from ntf_finish1),'true','NTF-008: exact-result finish replays read-only');
select ok(pg_temp.ntf_refusal($q$select public.finish_push_attempt(pg_temp.aid(851),pg_temp.aid(861),null,'UNREGISTERED',false)$q$) like 'GL068%','NTF-008: a different result for the same attempt is the replay conflict');
create temp table ntf_auth as select public.authorize_push_attempt(pg_temp.aid(853),pg_temp.aid(863)) as result;
select is((select (result->>'authorized')::text from ntf_auth),'false','NTF-005/pre-config: authorization refuses while configuration is absent');
select ok(not (select result ? 'token' from ntf_auth),'NTF-013: a refused authorization never returns a token');
select is((select scheduled_for from public.notifications where id=pg_temp.aid(803)),(select scheduled_for from public.notifications where id=pg_temp.aid(803)),'NTF-006: frozen scheduled_for is immutable');
select is((select count(*)::integer from public.notification_push_attempts where notification_id=pg_temp.aid(803) and started_at is not null),1,'NTF-006: no promotion dispatch evidence exists in the unconfigured default');
reset role;
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.reserve_push_attempts(1)$q$),'42501','NTF contract: authenticated JWT cannot invoke the transport facade');
reset role;

-- ============ I. send_notification unconfigured push truth ============
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
create temp table ntf_push_send as select public.send_notification(pg_temp.aid(801)) as result;
select is((select result->>'status' from ntf_push_send),'clicked','NTF contract: an already-processed push row replays its current result');
reset role;
select set_config('request.jwt.claims','',true);
select ok(pg_temp.ntf_refusal($q$update public.notifications set status='scheduled' where id=pg_temp.aid(801)$q$) like 'GL066%','NTF contract: a terminal push row is never revived backwards');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is((select status::text from public.notifications where id=pg_temp.aid(801)),'clicked','NTF-015: transport work cannot resurrect a terminal notification');
reset role;
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
create temp table ntf_unconf as select public.send_notification(pg_temp.aid(805)) as result;
select is((select result->>'status' from ntf_unconf),'failed','NTF-015: unconfigured push send is terminal failed');
select is((select result->>'failedReason' from ntf_unconf),'provider_unconfigured','NTF-015: unconfigured reason is provider_unconfigured');
select is((select status::text from public.notifications where id=pg_temp.aid(805)),'failed','NTF-015: unconfigured push stays failed');
select is((select failed_at is not null from public.notifications where id=pg_temp.aid(805)),true,'NTF-015: unconfigured failure is stamped');
create temp table ntf_inapp_send as select public.send_notification(pg_temp.aid(802)) as result;
select is((select result->>'status' from ntf_inapp_send),'sent','NTF-001: in-app event sends at zero cost regardless of provider');
select is((select sent_at is not null from public.notifications where id=pg_temp.aid(802)),true,'NTF-001: in-app send is stamped');
reset role;
select set_config('request.jwt.claims','',true);
select is((select count(*)::integer from public.messaging_wallet_ledger where tenant_id=pg_temp.aid(1)),0,'NTF-012: the push path writes zero wallet ledger movements');
select ok(not exists(select 1 from pg_proc where oid=to_regprocedure('app.accept_paid_notification(uuid,text,bigint,uuid)') and has_function_privilege('authenticated',oid,'EXECUTE')),'NTF-012: paid acceptance stub stays ungranted');
select ok(pg_temp.ntf_refusal($q$select app.accept_paid_notification(pg_temp.aid(801),'projects/781/messages/x',100,pg_temp.aid(861))$q$) like 'GL069%','NTF-012: paid acceptance stub still raises GL069');
reset role;

-- ============ J. ANC campaign review, exact keys, cancellation ============
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
insert into ntf_ids values('notice',public.create_announcement_draft('transactional','Push notice','Plain body','all_members',null,null,null,null));
select public.publish_announcement((select id from ntf_ids where k='notice'));
create temp table ntf_review as select public.review_announcement_push((select id from ntf_ids where k='notice'),1,pg_temp.aid(870)) as result;
select is((select (result->>'versionNo')::int from ntf_review),1,'NTF-011: review freezes the current live version');
select is((select (result->>'eligibleCount')::int from ntf_review),4,'NTF-011: review recomputes the live audience count');
create temp table ntf_review2 as select public.review_announcement_push((select id from ntf_ids where k='notice'),1,pg_temp.aid(870)) as result;
select is((select result->>'campaignId' from ntf_review2),(select result->>'campaignId' from ntf_review),'NTF-011: the same request key replays the same campaign');
select is((select count(*)::integer from public.notification_push_campaigns where announcement_id=(select id from ntf_ids where k='notice')),1,'NTF-011: replay creates no second campaign');
select ok(pg_temp.ntf_refusal($q$select public.review_announcement_push((select id from ntf_ids where k='notice'),1,pg_temp.aid(871))$q$) like 'GL115%','NTF-011: a new request key for the same version is the campaign-conflict code');
reset role;
select pg_temp.ntf_claim('front_desk',23,null,903,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.review_announcement_push((select id from ntf_ids where k='notice'),1,pg_temp.aid(872))$q$),'42501','NTF-011: front desk previews but never reviews');
select lives_ok($q$select public.read_push_campaigns(null,null)$q$,'NTF-011: front desk reads campaign facts');
reset role;
select pg_temp.ntf_claim('trainer',24,null,904,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.read_push_campaigns(null,null)$q$),'42501','NTF-011: trainer reads no campaign facts');
reset role;
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$select public.read_push_campaigns(null,null)$q$),'42501','NTF-011: member reads no campaign facts');
reset role;
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
select ok(public.read_push_campaigns(null,null)::text not like '%push_token%' and public.read_push_campaigns(null,null)::text not like '%reservation%' and public.read_push_campaigns(null,null)::text not like '%PRIVATE_MEMBER%','NTF-013: campaign facts expose no token, reservation or recipient identity');
reset role;
select set_config('request.jwt.claims','',true);
select app.run_push_events(pg_temp.aid(1)) as result;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.aid(1) and dedupe_key='announcement:'||(select id from ntf_ids where k='notice')::text||':v1:'||pg_temp.aid(101)::text),1,'NTF-007: the reviewed campaign creates the exact ANC inbox key for an audience member');
select is((select category::text from public.notifications where dedupe_key='announcement:'||(select id from ntf_ids where k='notice')::text||':v1:'||pg_temp.aid(101)::text),'announcement','NTF-002: transactional ANC uses the announcement category');
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.aid(1) and dedupe_key like 'announcement:%v1:%'),4,'NTF-007: one inbox event per audience member');
select app.run_push_events(pg_temp.aid(1)) as result;
select is((select count(*)::integer from public.notifications where tenant_id=pg_temp.aid(1) and dedupe_key like 'announcement:%v1:%'),4,'NTF-007: repeated runner passes create no duplicate events');
select pg_temp.ntf_claim('gym_owner',21,null,901,1,false);
set local role authenticated;
create temp table ntf_cancel as select public.cancel_announcement_push((select (result->>'campaignId')::uuid from ntf_review)) as result;
select is((select (result->>'cancelled')::text from ntf_cancel),'true','NTF-011: owner cancels the campaign');
select is((select cancelled_at is not null from public.notification_push_campaigns where id=(select (result->>'campaignId')::uuid from ntf_review)),true,'NTF-011: cancellation stamped');
select is(pg_temp.ntf_refusal($q$select public.cancel_announcement_push(pg_temp.aid(9999))$q$),'P0002','NTF-011: unknown campaign is target-invisible, indistinguishable from foreign');
reset role;
select set_config('request.jwt.claims','',true);
select is((select count(*)::integer from public.notification_push_campaigns where tenant_id=pg_temp.aid(1) and announcement_id=(select id from ntf_ids where k='notice') and version_no=1),1,'NTF-011: review created exactly one campaign row');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.aid(1) and (action ilike '%campaign%' or action ilike '%push%')),'NTF-014: campaign review is audited');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.aid(1) and (coalesce(before::text,'')||coalesce(after::text,'')) like '%fcm-token-781%'),0,'NTF-014: no audit row carries a push token');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.aid(1) and (coalesce(before::text,'')||coalesce(after::text,'')) like '%PRIVATE_MEMBER%'),0,'NTF-014: no audit row carries recipient identities');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.aid(1) and after->>'enabled' is not null and action not ilike '%consent%'),'NTF-014: preference changes are audited with the enabled fact');

-- ============ K. enforce_notification evidence admission ============
select ok(pg_temp.ntf_refusal($q$update public.notifications set status='sent',sent_at=now() where id=pg_temp.aid(803)$q$) like 'GL066%','NTF contract: push scheduled→sent without a durable accepted attempt is refused');
select ok(pg_temp.ntf_refusal($q$update public.notifications set status='sent',sent_at=now() where id=pg_temp.aid(805)$q$) like 'GL066%','NTF contract: a failed push row cannot be revived to sent directly');
select ok(pg_temp.ntf_refusal($q$update public.notifications set failed_reason=null where id=pg_temp.aid(805)$q$) like 'GL066%','NTF contract: failure timestamp/reason pairing stays frozen');

-- ============ L. zero-charge and consent independence ============
select is((select count(*)::integer from public.messaging_wallet_ledger where tenant_id=pg_temp.aid(1)),0,'NTF-012: zero wallet movement end to end');
select ok(exists(select 1 from pg_proc where oid='app.notification_transition_allowed(public.notification_status,public.notification_status)'::regprocedure),'NTF contract: transition graph helper unchanged');
select pg_temp.ntf_claim('member',null,101,906,1,false);
set local role authenticated;
select is(pg_temp.ntf_refusal($q$delete from public.consents where member_id=pg_temp.aid(101)$q$),'42501','NTF-002: preference holders cannot revoke consent rows directly');
reset role;
select set_config('request.jwt.claims','',true);
select is((select count(*)::integer from public.consents where member_id=pg_temp.aid(101)),2,'NTF-002: consent rows unchanged by every push-path action');
select * from finish();
rollback;
