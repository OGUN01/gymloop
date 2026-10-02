-- GRD-001..021/026/027. Frozen proposal plus marker amendment 258fd16;
-- independent visible DB author.
-- No production source, migrations, app tests or holdouts were read.
-- One rollback transaction cannot prove cross-backend concurrency. Sequential
-- replay and monotonic consent timestamps are tested; concurrency needs a
-- separate orchestrated rollback proof, not a committed fixture here.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(311);

create function pg_temp.gid(n integer) returns uuid language sql immutable as
$$ select ('69000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.claim(r text, s integer default 21, t integer default 1,
  u integer default 901, preview boolean default false) returns void language plpgsql as
$$ begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
  'sub',pg_temp.gid(u),'role','authenticated','app_role',r,'tenant_id',pg_temp.gid(t),
  'staff_id',case when s is not null then pg_temp.gid(s) end,
  'member_id',case when r='member' then pg_temp.gid(101) end,
  'impersonation_session_id',case when preview then pg_temp.gid(999) end))::text,true); end $$;
-- An unexpected successful refusal probe is rolled back too, so it cannot
-- pollute subsequent evidence. This helper does not elevate its caller.
create function pg_temp.refusal(q text,with_detail boolean default false) returns text language plpgsql as $$
declare detail text;
begin
  begin execute q; raise exception using errcode='Z6900';
  exception when others then
    if sqlstate='Z6900' then return 'SUCCESS'; end if;
    get stacked diagnostics detail=PG_EXCEPTION_DETAIL;
    return sqlstate||case when with_detail then ':'||coalesce(detail,'') else '' end;
  end;
end $$;
grant execute on function pg_temp.gid(integer),pg_temp.claim(text,integer,integer,integer,boolean),pg_temp.refusal(text,boolean) to authenticated,anon,service_role;

-- Catalogue proof: presence, exact vocabulary and no personal-contact columns
-- in the immutable decision history.
select enum_has_labels('public','guardian_relation',array['mother','father','grandparent','sibling','legal_guardian','other']::name[], 'GRD-004: canonical relation order');
select columns_are('public','guardian_consents',array['id','tenant_id','member_id','granted','version','source','guardian_name','guardian_relation','recorded_at','recorded_by_staff_id','created_at']::name[], 'GRD-006/026: exact immutable history fields; no phone/email or updated_at');
select col_is_pk('public','guardian_consents','id','GRD-006: consent UUID primary key');
select is_empty($q$
with w(col,typ) as (values ('guardian_name','text'),('guardian_relation','guardian_relation'),('guardian_phone','text'),('guardian_email','text'),('guardian_linked_at','timestamptz'))
select w.col from w where not exists (
select 1 from pg_attribute a join pg_type t on t.oid=a.atttypid
where a.attrelid=to_regclass('public.members') and a.attname=w.col and t.typname=w.typ
and not a.attnotnull and not exists(select 1 from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum))
$q$,'GRD-004/013: five nullable guardian columns have their exact types and no defaults');
select col_is_null('public','organization_settings','members_without_dob_attested_adult_at','GRD-002: legacy attestation starts nullable');
select is_empty($q$select a.attname from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey)
where i.indrelid='public.members'::regclass and a.attname like 'guardian_%'$q$, 'GRD-004/016: guardian contacts have no unique or other index');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.guardian_consents')),'GRD-021: consent history has RLS');
select policies_are('public','guardian_consents',array['guardian_consents_tenant_select','guardian_consents_platform_select']::name[],'GRD-021: only the canonical tenant and platform read policies exist');
select ok(has_table_privilege('authenticated','public.guardian_consents','SELECT') and not has_table_privilege('authenticated','public.guardian_consents','INSERT,UPDATE,DELETE'),'GRD-021: authenticated has select only');
select ok(not has_table_privilege('anon','public.guardian_consents','SELECT,INSERT,UPDATE,DELETE'),'GRD-021: anon has no consent grants');
select is_empty($q$
with w(n) as(values ('members_guardian_name_chk'),('members_guardian_phone_format_chk'),('members_guardian_email_format_chk'),('members_guardian_identity_chk'),('members_guardian_contact_chk'),('members_guardian_linked_state_chk'))
select n from w where not exists(select 1 from pg_constraint c where c.conrelid='public.members'::regclass and c.conname=w.n and c.contype='c')
$q$,'GRD-004/013: all six named member checks exist');
select is_empty($q$
with w(n) as(values ('guardian_consents_version_format_chk'),('guardian_consents_source_chk'),('guardian_consents_guardian_name_chk'))
select n from w where not exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.guardian_consents') and c.conname=w.n and c.contype='c')
$q$,'GRD-006: consent format checks exist');
select ok(exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.guardian_consents') and c.conname='guardian_consents_tenant_id_member_id_recorded_at_key' and c.contype='u'),'GRD-006: monotonic timestamp uniqueness');
select is_empty($q$
with w(n,cols) as(values ('guardian_consents_tenant_id_member_id_recorded_at_id_idx','(tenant_id, member_id, recorded_at DESC, id DESC)'),('guardian_consents_tenant_id_recorded_by_staff_id_idx','(tenant_id, recorded_by_staff_id)'))
select n from w where not exists(select 1 from pg_class i join pg_index x on x.indexrelid=i.oid where x.indrelid=to_regclass('public.guardian_consents') and i.relname=w.n and position(w.cols in pg_get_indexdef(i.oid))>0)
$q$,'GRD-006: newest-consent and actor indexes');
select is_empty($q$
with w(cols,ref) as(values (array['tenant_id','member_id']::text[],'members'),(array['tenant_id','recorded_by_staff_id']::text[],'staff'))
select ref from w where not exists(select 1 from pg_constraint c join pg_class r on r.oid=c.confrelid
where c.conrelid=to_regclass('public.guardian_consents') and c.contype='f' and r.relname=w.ref
and (select array_agg(a.attname::text order by k.ord) from unnest(c.conkey) with ordinality k(n,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.n)=w.cols
and (select array_agg(a.attname::text order by k.ord) from unnest(c.confkey) with ordinality k(n,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.n)=array['tenant_id','id'])
$q$,'GRD-021: tenant-composite member and actor foreign keys');
select is_empty($q$
with w(sig,elev,v) as(values
('public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text)',false,'v'),
('public.record_guardian_consent(uuid,boolean,text,text)',true,'v'),
('public.transition_member_to_own_account(uuid,text)',true,'v'),
('public.read_member_guardian(uuid)',false,'s'),('public.read_guardian_coverage()',false,'s'),
('public.list_guardian_attention(text)',false,'s'),('public.attest_members_without_dob_adult()',true,'v'))
select sig from w left join pg_proc p on p.oid=to_regprocedure(w.sig)
where p.oid is null or p.prosecdef<>w.elev or p.provolatile::text<>w.v
or not coalesce(p.proconfig @> array['search_path=""'],false)
or (w.elev and pg_get_userbyid(p.proowner)<>'postgres')
or not has_function_privilege('authenticated',p.oid,'EXECUTE')
or has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('service_role',p.oid,'EXECUTE')
$q$,'GRD-021: seven exact public signatures, posture, volatility, path and authenticated-only grants');
select is_empty($q$
with w(sig) as(values ('app.close_ineligible_cases(uuid,uuid,text)'),('app.guardian_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)'),('app.guard_legacy_adult_attestation()'),('app.members_guardian_marker()'))
select sig from w left join pg_proc p on p.oid=to_regprocedure(w.sig) where p.oid is null
or has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('service_role',p.oid,'EXECUTE')
$q$,'GRD-021: closure, audit and timestamp trigger cannot be called by sessions');
select is_empty($q$
with w(tbl,n,fn,typ,elev) as(values
('members','members_guardian_marker','members_guardian_marker',23,false),
('members','members_guardian_after_change','members_guardian_after_change',17,true),
('guardian_consents','guardian_consents_preview_read_only','enforce_preview_read_only',31,false),
('organization_settings','organization_settings_legacy_adult_attestation_guard','guard_legacy_adult_attestation',23,false))
select w.n from w where not exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
where t.tgrelid=to_regclass('public.'||w.tbl) and t.tgname=w.n and t.tgtype=w.typ and t.tgenabled='O'
and not t.tgisinternal and n.nspname='app' and p.proname=w.fn and p.prosecdef=w.elev)
$q$,'GRD-009/013/021: exact enabled trigger timing and elevation');
select ok(exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
where t.tgrelid='public.members'::regclass and t.tgname='members_guardian_marker' and t.tgqual is null
and (select array_agg(a.attname::text order by a.attname) from unnest(t.tgattr::smallint[]) k(n) join pg_attribute a on a.attrelid=t.tgrelid and a.attnum=k.n)=array['guardian_linked_at','user_id']
and pg_get_userbyid(p.proowner)='postgres' and p.provolatile='v' and coalesce(p.proconfig @> array['search_path=""'],false)),
'GRD-013 marker amendment: INSERT plus exact two UPDATE columns, no WHEN, private invoker posture');

-- Exact frozen age boundaries, including the conservative leap-day rule.
select is(app.member_adult_on(date '2008-03-01'),date '2026-03-01','GRD-001: ordinary eighteenth anniversary');
select is(app.member_adult_on(date '2008-02-29'),date '2026-03-01','GRD-001: leap-day eighteenth birthday is March 1');
select is(app.member_adult_on(null),null::date,'GRD-001: unknown birthday stays unknown');
select ok(app.member_is_minor_on(date '2008-03-01',date '2026-02-28'),'GRD-001: day before ordinary birthday');
select ok(not app.member_is_minor_on(date '2008-03-01',date '2026-03-01'),'GRD-001: birthday is adult inclusive');
select ok(app.member_is_minor_on(date '2008-02-29',date '2026-02-28'),'GRD-001: leap-day member remains minor through February 28');
select ok(not app.member_is_minor_on(date '2008-02-29',date '2026-03-01'),'GRD-001: leap-day member adult March 1');
select ok(not app.member_is_minor_on(date '2000-01-01',date '2018-01-01'),'GRD-001: fixed adult boundary');
select ok(app.member_is_minor_on(date '2026-10-03',date '2026-10-02'),'GRD-001: future birth is classified minor by pure helper');
select ok(not app.member_is_minor_on(null,date '2026-10-02') and not app.member_is_minor_on(date '2008-01-01',null),'GRD-001: null helper arguments are false');
select ok(not app.member_is_minor_on(date '2008-03-02',(timestamptz '2026-03-01 19:00+00' at time zone 'Asia/Kolkata')::date),'GRD-001: frozen Kolkata instant is March 2, adulthood reached');

-- Fixtures are confined to two gyms. Settings B deliberately remain unattested.
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
(pg_temp.gid(1),'GRD visible A','GRD69A','active','Asia/Kolkata','INR'),
(pg_temp.gid(2),'GRD visible B','GRD69B','active','Etc/GMT+12','INR');
insert into public.organization_settings(tenant_id) values(pg_temp.gid(1)),(pg_temp.gid(2));
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.gid(11),pg_temp.gid(1),'A',true),(pg_temp.gid(12),pg_temp.gid(2),'B',true);
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values
(pg_temp.gid(901),'owner69@example.test',now(),'{"provider":"email"}'),
(pg_temp.gid(902),'manager69@example.test',now(),'{"provider":"email"}'),
(pg_temp.gid(903),'desk69@example.test',now(),'{"provider":"email"}'),
(pg_temp.gid(904),'trainer69@example.test',now(),'{"provider":"email"}'),
(pg_temp.gid(905),'otherowner69@example.test',now(),'{"provider":"email"}'),
(pg_temp.gid(906),'parent69@example.test',now(),'{"provider":"google","providers":["google"]}'),
(pg_temp.gid(907),'child69@example.test',now(),'{"provider":"google","providers":["google"]}'),
(pg_temp.gid(908),'adult69@example.test',now(),'{"provider":"google","providers":["google"]}');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.gid(21),pg_temp.gid(1),pg_temp.gid(901),pg_temp.gid(11),'gym_owner','Owner'),
(pg_temp.gid(22),pg_temp.gid(1),pg_temp.gid(902),pg_temp.gid(11),'gym_manager','Manager'),
(pg_temp.gid(23),pg_temp.gid(1),pg_temp.gid(903),pg_temp.gid(11),'front_desk','Desk'),
(pg_temp.gid(24),pg_temp.gid(1),pg_temp.gid(904),pg_temp.gid(11),'trainer','Trainer'),
(pg_temp.gid(25),pg_temp.gid(2),pg_temp.gid(905),pg_temp.gid(12),'gym_owner','Other owner');
insert into public.members(id,tenant_id,branch_id,full_name,phone,email,date_of_birth,guardian_name,guardian_relation,guardian_phone,guardian_email,created_at) values
(pg_temp.gid(101),pg_temp.gid(1),pg_temp.gid(11),'Unknown before','+916900000101','unknown69@example.test',null,null,null,null,null,now()-interval '1 year'),
(pg_temp.gid(102),pg_temp.gid(1),pg_temp.gid(11),'Minor empty','+916900000102','child69@example.test',(current_date-interval '10 years')::date,null,null,null,null,now()-interval '1 year'),
(pg_temp.gid(103),pg_temp.gid(1),pg_temp.gid(11),'Minor complete','+916900000103','child69@example.test',(current_date-interval '10 years')::date,'Parent private','mother','+916900009906','parent69@example.test',now()-interval '1 year'),
(pg_temp.gid(104),pg_temp.gid(1),pg_temp.gid(11),'Adult','+916900000104','adult69@example.test',date '1990-01-01',null,null,null,null,now()-interval '1 year'),
(pg_temp.gid(105),pg_temp.gid(1),pg_temp.gid(11),'Sibling','+916900000105','sibling69@example.test',(current_date-interval '8 years')::date,'Parent private','mother','+916900009906','parent69@example.test',now()-interval '1 year'),
(pg_temp.gid(106),pg_temp.gid(1),pg_temp.gid(11),'Unknown future','+916900000106','future69@example.test',null,null,null,null,null,now()+interval '1 year'),
(pg_temp.gid(107),pg_temp.gid(2),pg_temp.gid(12),'Other unknown','+916900000107','other69@example.test',null,null,null,null,null,now()-interval '1 year'),
(pg_temp.gid(108),pg_temp.gid(1),pg_temp.gid(11),'Adult operator bound','+916900000108','operator69@example.test',date '1990-01-01','Parent private','mother','+916900009906',null,now()-interval '1 year');
select is(app.gym_today(pg_temp.gid(1)),(statement_timestamp() at time zone 'Asia/Kolkata')::date,'GRD-001: gym_today uses organization Kolkata timezone');
select is(app.gym_today(pg_temp.gid(2)),(statement_timestamp() at time zone 'Etc/GMT+12')::date,'GRD-001: non-UTC gym date uses its own zone');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(101),app.gym_today(pg_temp.gid(1))),'off_age_unknown','GRD-002: null cutoff fails safe');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(102),app.gym_today(pg_temp.gid(1))),'off_no_guardian','GRD-003: incomplete guardian');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(103),app.gym_today(pg_temp.gid(1))),'off_no_consent','GRD-003: complete guardian without consent');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(104),date '2026-10-02'),'on_adult','GRD-003: known adult on without guardian');
select ok(not app.member_scoring_eligible(pg_temp.gid(1),pg_temp.gid(104),null),'GRD-003: null evaluation date fails safe');
select is(app.member_contact_phone(pg_temp.gid(1),pg_temp.gid(103)),'+916900009906','GRD-017: minor routes to guardian phone');
select is(app.member_contact_email(pg_temp.gid(1),pg_temp.gid(103)),'parent69@example.test','GRD-017: minor routes to guardian email');
select is(app.member_contact_phone(pg_temp.gid(1),pg_temp.gid(102)),null::text,'GRD-017: incomplete guardian never falls back to child phone');
select is(app.member_contact_email(pg_temp.gid(1),pg_temp.gid(102)),null::text,'GRD-017: incomplete guardian never falls back to child email');
select is(app.member_contact_phone(pg_temp.gid(1),pg_temp.gid(104)),'+916900000104','GRD-017/027: adult own phone unchanged');
select is(app.member_contact_email(pg_temp.gid(1),pg_temp.gid(101)),'unknown69@example.test','GRD-002/017: unknown age contact remains own');

-- Refusal precedence and grants: all probes run as the actual session role.
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(107),date '2999-01-01',null,null,null,null)$q$),'42501','GRD-005: foreign member hides even malformed age');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(9999),null,null,null,null,null)$q$),'42501','GRD-005: unknown member indistinguishable from foreign');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),date '2999-01-01',null,null,null,null)$q$),'22023','GRD-005: future birthday refused');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,null,'mother',null,null)$q$),'22023','GRD-005: relation without name refused before checks');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,null,null,'+916900009906',null)$q$),'22023','GRD-005: contact without name refused');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,repeat('x',121),'mother',null,null)$q$),'23514','GRD-004: guardian name length upper bound');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,'Parent','mother','1234567890',null)$q$),'23514','GRD-004: guardian phone E.164 check');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,'Parent','mother',null,'bad@address')$q$),'23514','GRD-004: plausible guardian email required');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(107),null,'BAD','')$q$),'42501','GRD-006: authorization precedes invalid consent input');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(104),null,'v1','paper')$q$),'22023','GRD-006: null granted precedes adult refusal');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(104),true,'BAD','paper')$q$),'22023','GRD-006: version format precedes adult refusal');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(103),true,'v1',repeat('x',201))$q$),'22023','GRD-006: source length 201 rejected');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(103),true,'v1','   ')$q$),'22023','GRD-006: blank source refused');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(101),true,'v1','paper')$q$),'GL084','GRD-006: unknown age not minor');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(104),true,'v1','paper')$q$),'GL084','GRD-006: adult without guardian gets age refusal first');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(102),true,'v1','paper')$q$),'GL083','GRD-006: known minor missing guardian');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(107),'x')$q$),'42501','GRD-012: foreign handover before reason checks');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(102),'xx')$q$),'22023','GRD-012: short reason before minor refusal');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(102),'Valid reason')$q$),'GL084','GRD-012: minor before unlinked refusal');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(101),'Valid reason')$q$),'GL084','GRD-012: unknown age before unlinked refusal');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(104),'Valid reason')$q$),'GL085','GRD-012: adult without guardian linkage');
select is(pg_temp.refusal($q$select public.list_guardian_attention('other')$q$),'22023','GRD-019: attention reason is closed vocabulary');
select is(pg_temp.refusal($q$select * from public.read_member_guardian(pg_temp.gid(107))$q$),'42501','GRD-019: foreign read reveals no member');
select is(pg_temp.refusal($q$update public.organization_settings set members_without_dob_attested_adult_at=now() where tenant_id=pg_temp.gid(1)$q$),'42501','GRD-002: direct session timestamp update refused');
select is(pg_temp.refusal($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.gid(1),pg_temp.gid(103),true,'v1','paper','Parent','mother',pg_temp.gid(21))$q$),'42501','GRD-021: direct consent insertion has no grant');
select is(pg_temp.refusal($q$delete from public.guardian_consents where tenant_id=pg_temp.gid(1)$q$),'42501','GRD-021: consent history cannot be deleted');
select is(pg_temp.refusal($q$update public.guardian_consents set source='edited' where tenant_id=pg_temp.gid(1)$q$),'42501','GRD-021: consent history cannot be edited');
set local role postgres;
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.gid(1) and action like 'guardian_consent.%'),0,'GRD-020: refused consent calls write no audit');

select pg_temp.claim('trainer',24,1,904);
set local role authenticated;
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,null,null,null,null)$q$),'42501','GRD-005: trainer cannot save guardian');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(103),true,'v1','paper')$q$),'42501','GRD-006: trainer cannot record consent');
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: trainer cannot attest');
select is(pg_temp.refusal($q$select public.read_member_guardian(pg_temp.gid(103))$q$),'42501','GRD-019: trainer cannot read guardian section');
select is(pg_temp.refusal($q$select public.read_guardian_coverage()$q$),'42501','GRD-019: trainer cannot read coverage');
select is(pg_temp.refusal($q$select public.list_guardian_attention('no_birth_date')$q$),'42501','GRD-019: trainer cannot read attention');
select is((select count(*)::integer from public.guardian_consents),0,'GRD-021: trainer cannot read consent history');
set local role postgres;
select pg_temp.claim('member',null,1,907);
set local role authenticated;
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(103),false,'v1','phone')$q$),'42501','GRD-006: member cannot self-withdraw through staff command');
select is(pg_temp.refusal($q$select public.read_member_guardian(pg_temp.gid(103))$q$),'42501','GRD-019: member cannot read guardian staff projection');
select is((select count(*)::integer from public.guardian_consents),0,'GRD-021: member cannot read guardian consent history');
set local role postgres;
select pg_temp.claim('gym_manager',22,1,902);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: manager cannot perform owner attestation');
set local role postgres;
select pg_temp.claim('front_desk',23,1,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: desk cannot attest');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(104),'Valid reason')$q$),'42501','GRD-012: desk handover refused before member state');
set local role postgres;
select pg_temp.claim('gym_owner',21,1,902);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: owner claim with mismatched authenticated subject cannot attest');
set local role postgres;
select pg_temp.claim('gym_owner',21,1,901,true);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: preview owner cannot attest');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(103),true,'v1','paper')$q$),'42501','GRD-006: preview cannot record consent');
select is(pg_temp.refusal($q$select public.set_member_age_guardian(pg_temp.gid(103),null,null,null,null,null)$q$),'42501','GRD-005: preview cannot alter guardian');
set local role postgres;

-- Consent transition walk, snapshot integrity, no-op writes and immediate closure.
select pg_temp.claim('front_desk',23,1,903);
set local role authenticated;
create temp table first_consent as select * from public.record_guardian_consent(pg_temp.gid(103),true,' guardian-absence-v1 ',' paper private ');
select ok((select changed from first_consent),'GRD-006: front desk may record guardian consent');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'granted','GRD-003: standing snapshot consent');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(103),app.gym_today(pg_temp.gid(1))),'on_consent','GRD-003: consent unlocks minor scoring');
select ok(app.member_scoring_eligible(pg_temp.gid(1),pg_temp.gid(103),app.gym_today(pg_temp.gid(1))),'GRD-003: gate agrees with on_consent');
select ok(not (select changed from public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','different source')),'GRD-006: exact decision replay ignores source and writes nothing');
select is((select consent_id from public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','paper')),(select consent_id from first_consent),'GRD-006: replay returns original consent identity');
set local role postgres;
select is((select count(*)::integer from public.guardian_consents where member_id=pg_temp.gid(103)),1,'GRD-006: replay adds no history');
select ok(exists(select 1 from public.guardian_consents where member_id=pg_temp.gid(103) and guardian_name='Parent private' and guardian_relation='mother' and source='paper private' and version='guardian-absence-v1' and recorded_by_staff_id=pg_temp.gid(23)),'GRD-006: server snapshots guardian, staff and trimmed decision');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='guardian_consent.granted' and actor_user_id=pg_temp.gid(903) and actor_role='front_desk' and record_type='guardian_consent' and record_id=(select consent_id from first_consent) and before='{"standing":"none"}'::jsonb and after=jsonb_build_object('member_id',pg_temp.gid(103),'version','guardian-absence-v1')),'GRD-020: consent audit exact attribution and nonpersonal shape');

create temp table saved_member as select updated_at from public.members where id=pg_temp.gid(103);
create temp table saved_audits as select count(*) as n from public.audit_log where tenant_id=pg_temp.gid(1);
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,' Parent private ','mother',' +916900009906 ',' parent69@example.test ')$q$,'GRD-005: trim-normalized identical profile is accepted no-op');
set local role postgres;
select is((select updated_at from public.members where id=pg_temp.gid(103)),(select updated_at from saved_member),'GRD-005: no-op profile does not bump updated_at');
select is((select count(*) from public.audit_log where tenant_id=pg_temp.gid(1)),(select n from saved_audits),'GRD-020: profile no-op writes no audit');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'PARENT PRIVATE','mother','+916900009906','parent69@example.test')$q$,'GRD-003: case-only guardian name edit');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'granted','GRD-003: snapshot name comparison is case-insensitive');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'PARENT PRIVATE','mother','+916900009907','newparent69@example.test')$q$,'GRD-004: phone/email may change');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'granted','GRD-003: phone/email changes do not void consent');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent changed','mother','+916900009907','newparent69@example.test')$q$,'GRD-004: changed guardian name accepted');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'stale','GRD-003: changed name alone invalidates granted snapshot');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(103),app.gym_today(pg_temp.gid(1))),'off_consent_stale','GRD-003: stale consent turns scoring off');
select ok((select changed from public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','paper')),'GRD-006: same version after identity edit requires new snapshot');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent changed','father','+916900009907','newparent69@example.test')$q$,'GRD-004: changed relation alone accepted');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'stale','GRD-003: changed relation alone invalidates granted snapshot');
select ok((select changed from public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','paper')),'GRD-006: relation edit requires renewed snapshot');
set local role postgres;
select ok((select max(recorded_at)>min(recorded_at) from public.guardian_consents where member_id=pg_temp.gid(103)),'GRD-006: repeated decisions have strictly increasing timestamps');
insert into public.no_show_cases(id,tenant_id,member_id,status,opened_on,absent_days_at_open,threshold_days) values
(pg_temp.gid(301),pg_temp.gid(1),pg_temp.gid(103),'open',current_date,10,7);
insert into public.follow_ups(id,tenant_id,case_id,staff_id,channel,outcome,notes) values
(pg_temp.gid(401),pg_temp.gid(1),pg_temp.gid(301),pg_temp.gid(23),'call','no_response','Keep history');
set local role authenticated;
select ok((select changed from public.record_guardian_consent(pg_temp.gid(103),false,'guardian-absence-v1','phone')),'GRD-007: withdrawal appends a decision');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(103),app.gym_today(pg_temp.gid(1))),'off_consent_withdrawn','GRD-007: withdrawal is immediately visible');
select ok(not (select changed from public.record_guardian_consent(pg_temp.gid(103),false,'guardian-absence-v1','another source')),'GRD-006: withdrawal replay no-op');
set local role postgres;
select ok(exists(select 1 from public.no_show_cases where id=pg_temp.gid(301) and status='closed' and closed_at is not null and returned_at is null),'GRD-007/009: withdrawal closes rather than returns case immediately');
select is((select count(*)::integer from public.follow_ups where id=pg_temp.gid(401)),1,'GRD-007: follow-up history survives withdrawal');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.scoring_stopped' and record_id=pg_temp.gid(103) and after='{"closed_cases":1,"cause":"consent_withdrawn"}'::jsonb),'GRD-020: closure audit exact count and cause');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.gid(1) and action='guardian_consent.withdrawn'),1,'GRD-020: withdrawal replay audits once');

-- Owner attestation, precise cutoff and tenant isolation.
select pg_temp.claim('gym_owner');
set local role authenticated;
create temp table first_attestation as select * from public.attest_members_without_dob_adult();
select ok((select changed and members_without_dob_attested_adult_at is not null from first_attestation),'GRD-002: owner first call stamps cutoff');
select ok(not (select changed from public.attest_members_without_dob_adult()),'GRD-002: repeat returns changed false');
select is((select members_without_dob_attested_adult_at from public.attest_members_without_dob_adult()),(select members_without_dob_attested_adult_at from first_attestation),'GRD-002: replay preserves exact original timestamp');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(101),app.gym_today(pg_temp.gid(1))),'on_adult','GRD-002: earlier missing-DOB member covered');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(106),app.gym_today(pg_temp.gid(1))),'off_age_unknown','GRD-002: later created member remains off');
select ok((select legacy_attested_adult and age_state='unknown' and date_of_birth is null from public.read_member_guardian(pg_temp.gid(101))),'GRD-002/019: attestation invents no adult age fact or DOB');
set local role postgres;
update public.members set created_at=(select members_without_dob_attested_adult_at from first_attestation) where id=pg_temp.gid(106);
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(106),app.gym_today(pg_temp.gid(1))),'on_adult','GRD-002: cutoff equality is inclusive');
update public.members set created_at=(select members_without_dob_attested_adult_at+interval '1 microsecond' from first_attestation) where id=pg_temp.gid(106);
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(106),app.gym_today(pg_temp.gid(1))),'off_age_unknown','GRD-002: one microsecond after cutoff excluded');
select is(app.member_scoring_state(pg_temp.gid(2),pg_temp.gid(107),app.gym_today(pg_temp.gid(2))),'off_age_unknown','GRD-002: other gym does not inherit cutoff');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.gid(1) and action='organization.members_without_dob_attested_adult'),1,'GRD-002/020: attestation first call and all replays audit once');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='organization.members_without_dob_attested_adult' and record_type='organization_settings' and record_id=pg_temp.gid(1) and actor_user_id=pg_temp.gid(901) and actor_role='gym_owner' and before='{"members_without_dob_attested_adult_at":null}'::jsonb and after=jsonb_build_object('members_without_dob_attested_adult_at',(select members_without_dob_attested_adult_at from first_attestation)) and reason is null),'GRD-020: exact one-time owner audit shape');
select is(pg_temp.refusal($q$update public.organization_settings set members_without_dob_attested_adult_at=null where tenant_id=pg_temp.gid(1)$q$),'22023','GRD-002: even trusted writes cannot reset cutoff');
select is(pg_temp.refusal($q$update public.organization_settings set members_without_dob_attested_adult_at=now()+interval '1 day' where tenant_id=pg_temp.gid(1)$q$),'22023','GRD-002: even trusted writes cannot move cutoff');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(101),(current_date-interval '10 years')::date,null,null,null,null)$q$,'GRD-002: attested member DOB may be corrected');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(101),app.gym_today(pg_temp.gid(1))),'off_no_guardian','GRD-002: known minor overrides legacy cutoff');
set local role postgres;

-- INV deltas: the account email is guardian email only while the member is minor.
insert into auth.identities(id,provider_id,user_id,identity_data,provider) values
(pg_temp.gid(801),'grd-parent',pg_temp.gid(906),'{"email":"parent69@example.test","email_verified":true,"sub":"grd-parent"}','google'),
(pg_temp.gid(802),'grd-child',pg_temp.gid(907),'{"email":"child69@example.test","email_verified":true,"sub":"grd-child"}','google'),
(pg_temp.gid(803),'grd-adult',pg_temp.gid(908),'{"email":"adult69@example.test","email_verified":true,"sub":"grd-adult"}','google');
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$select public.issue_member_invite(pg_temp.gid(102),repeat('a',64))$q$),'GL083','GRD-014: incomplete guardian takes missing-address slot');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent changed','father','+916900009907',null)$q$,'GRD-014: minor may have phone and consent but no email');
select is(pg_temp.refusal($q$select public.issue_member_invite(pg_temp.gid(103),repeat('b',64))$q$),'GL083','GRD-014: complete guardian lacking email cannot invite');
create temp table sibling_invite as select * from public.issue_member_invite(pg_temp.gid(105),repeat('c',64));
select ok((select invite_id is not null from sibling_invite),'GRD-014: complete minor invite uses guardian address');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local role anon;
select is((select count(*)::integer from public.peek_member_invite(repeat('c',64))),1,'GRD-015: signed-out peek permits complete minor invite');
set local role postgres;
select pg_temp.claim(null,null,1,907);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(repeat('c',64))),'email_mismatch','GRD-015: child own Google address refuses guardian invite');
select is((select gym_name from public.redeem_member_invite(repeat('c',64))),null::text,'GRD-015: wrong account refusal reveals no gym');
set local role postgres;
select pg_temp.claim(null,null,1,906);
set local role authenticated;
create temp table linked_sibling as select outcome,statement_timestamp() as linked_at from public.redeem_member_invite(repeat('c',64));
select is((select outcome from linked_sibling),'linked','GRD-015: guardian verified Google account binds minor');
select is((select outcome from public.redeem_member_invite(repeat('c',64))),'already_linked_here','GRD-015/027: guardian redemption retains INV idempotent replay');
set local role postgres;
select ok(exists(select 1 from public.members where id=pg_temp.gid(105) and user_id=pg_temp.gid(906) and guardian_linked_at=(select linked_at from linked_sibling)),'GRD-013: guardian marker stamped at redemption statement timestamp');
-- A real guardian-linked value cannot be erased or retimed by a session.
-- Capture complete values and privileged side effects before refusal probes.
insert into auth.sessions(id,user_id) values(pg_temp.gid(710),pg_temp.gid(906));
create temp table marker_real_before as select to_jsonb(m) as member_row,
  (select jsonb_agg(to_jsonb(s) order by s.id) from auth.sessions s where s.user_id=pg_temp.gid(906)) as sessions,
  (select count(*) from public.audit_log where tenant_id=pg_temp.gid(1)) as audits
from public.members m where m.id=pg_temp.gid(105);
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=null where id=pg_temp.gid(105)$q$,true),'42501:guardian_binding_command_required','GRD-013 marker integrity: real guardian provenance cannot be cleared directly');
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 day' where id=pg_temp.gid(105)$q$,true),'42501:guardian_binding_command_required','GRD-013 marker integrity: real guardian provenance cannot be retimed directly');
select is(pg_temp.refusal($q$update public.members set user_id=pg_temp.gid(907),guardian_linked_at=null where id=pg_temp.gid(105)$q$),'GL074','GRD-013/INV: user-id change retains earlier INV refusal even alongside marker tampering');
select set_config('app.guardian_binding_command','redeem:'||pg_temp.gid(105)::text,true);
select set_config('app.member_invite_command','redeem:'||pg_temp.gid(105)::text,true);
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=null where id=pg_temp.gid(105)$q$,true),'42501:guardian_binding_command_required','GRD-013 marker integrity: forged transaction markers do not authorize a session');
set local role postgres;
select set_config('app.guardian_binding_command','',true);
select set_config('app.member_invite_command','',true);
select pg_temp.claim('gym_owner');
set local role service_role;
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=null where id=pg_temp.gid(105)$q$,true),'42501:guardian_binding_command_required','GRD-013 marker integrity: service-role connection with Auth subject is untrusted');
set local role postgres;
select is((select to_jsonb(m) from public.members m where id=pg_temp.gid(105)),(select member_row from marker_real_before),'GRD-013 marker integrity: refused tampering changes no member value or timestamp');
select is((select jsonb_agg(to_jsonb(s) order by s.id) from auth.sessions s where user_id=pg_temp.gid(906)),(select sessions from marker_real_before),'GRD-013 marker integrity: refused tampering changes no guardian session');
select is((select count(*) from public.audit_log where tenant_id=pg_temp.gid(1)),(select audits from marker_real_before),'GRD-013 marker integrity: refused tampering writes no audit');
select pg_temp.claim('front_desk',23,1,903);
set local role authenticated;
select lives_ok($q$update public.members set guardian_linked_at=guardian_linked_at where id=pg_temp.gid(105)$q$,'GRD-013 marker integrity: unchanged non-null value retains front-office permissions');
select is(pg_temp.refusal($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at) values(pg_temp.gid(112),pg_temp.gid(1),pg_temp.gid(11),'Forged marker insert','+916900000112',statement_timestamp())$q$,true),'42501:guardian_binding_command_required','GRD-013 marker integrity: non-null INSERT refused before linked-state CHECK');
select is(pg_temp.refusal($q$insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,guardian_linked_at) values(pg_temp.gid(112),pg_temp.gid(1),pg_temp.gid(11),pg_temp.gid(907),'Forged binding insert','+916900000112',statement_timestamp())$q$),'GL074','GRD-013/INV: non-null user INSERT retains earlier INV guard order');
select lives_ok($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at) values(pg_temp.gid(114),pg_temp.gid(1),pg_temp.gid(11),'Allowed null marker','+916900000114',null)$q$,'GRD-013 marker integrity: ordinary null-marker member insertion remains allowed');
select lives_ok($q$update public.members set guardian_linked_at=null where id=pg_temp.gid(114)$q$,'GRD-013 marker integrity: unchanged null marker update remains allowed');
set local role postgres;
select is((select count(*)::integer from public.members where id=pg_temp.gid(112)),0,'GRD-013 marker integrity: refused marker/binding inserts leave no row');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent private','mother','+916900009906','PARENT69@example.test')$q$,'GRD-016: siblings may share all guardian contact fields');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'withdrawn','GRD-003: withdrawal takes precedence over later identity mismatch');
select ok((select link_email_in_use from public.read_member_guardian(pg_temp.gid(103))),'GRD-016: same-gym bound sibling warns without identity details');
select lives_ok($q$select public.issue_member_invite(pg_temp.gid(103),repeat('d',64))$q$,'GRD-016: collision is checked at binding, staff can issue');
set local role postgres;
select pg_temp.claim(null,null,1,906);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(repeat('d',64))),'account_already_linked','GRD-016: same guardian Google account cannot bind second child');
set local role postgres;
select is((select user_id from public.members where id=pg_temp.gid(103)),null::uuid,'GRD-016: refused sibling redemption binds nothing');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent private','mother','+916900009906','adult69@example.test')$q$,'GRD-016: staff selects different account for second child');
select ok(not (select link_email_in_use from public.read_member_guardian(pg_temp.gid(103))),'GRD-016: alternate address removes collision hint');
select lives_ok($q$select public.issue_member_invite(pg_temp.gid(103),repeat('e',64))$q$,'GRD-016: reissue supersedes former sibling invite');
set local role postgres;
select pg_temp.claim(null,null,1,908);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(repeat('d',64))),'invite_unavailable','GRD-015/027: superseded guardian token remains unavailable');
select is((select outcome from public.redeem_member_invite(repeat('e',64))),'linked','GRD-016: second child may bind distinct guardian account');
set local role postgres;

-- Loss of completeness invalidates a pending invite in both peek and redeem.
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(102),(current_date-interval '10 years')::date,'Parent private','mother','+916900009906','child69@example.test')$q$,'GRD-014: prepare complete minor invite');
select lives_ok($q$select public.issue_member_invite(pg_temp.gid(102),repeat('f',64))$q$,'GRD-014: issue before guardian is cleared');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(102),(current_date-interval '10 years')::date,null,null,null,null)$q$,'GRD-005: all-null guardian clears record');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local role anon;
select is((select count(*)::integer from public.peek_member_invite(repeat('f',64))),0,'GRD-015: peek hides invite once guardian incomplete');
set local role postgres;
select pg_temp.claim(null,null,1,907);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(repeat('f',64))),'invite_unavailable','GRD-015: incomplete guardian is unavailable, no new oracle outcome');
set local role postgres;

-- Birthday uses the evaluation date without writes; handover is explicit.
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(105),app.member_adult_on((select date_of_birth from public.members where id=pg_temp.gid(105)))-1),'off_no_consent','GRD-011: before birthday consent remains necessary');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(105),app.member_adult_on((select date_of_birth from public.members where id=pg_temp.gid(105)))),'on_adult','GRD-011: birthday alone enables scoring without consent write');
select is((select app.member_invite_email(m,app.member_adult_on(m.date_of_birth)) from public.members m where id=pg_temp.gid(105)),'sibling69@example.test','GRD-011: birthday invite address becomes own email');
select is((select app.member_invite_email(m,app.member_adult_on(m.date_of_birth)-1) from public.members m where id=pg_temp.gid(105)),'parent69@example.test','GRD-011: day before birthday still guardian invite email');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(105),date '1990-01-01','Parent private','mother','+916900009906','parent69@example.test')$q$,'GRD-011: age correction reaches adult without unlink');
select ok((select handover_due and guardian_linked_at is not null from public.read_member_guardian(pg_temp.gid(105))),'GRD-019: adult guardian-linked account reports handover due');
select is(app.member_contact_phone(pg_temp.gid(1),pg_temp.gid(105)),'+916900000105','GRD-011/017: adulthood contact switches to own phone');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(105),repeat('x',201))$q$),'22023','GRD-012: handover reason upper bound');
set local role postgres;
insert into auth.sessions(id,user_id) values(pg_temp.gid(701),pg_temp.gid(906)),(pg_temp.gid(702),pg_temp.gid(906)),(pg_temp.gid(703),pg_temp.gid(908));
create temp table before_handover as select guardian_name,guardian_relation,guardian_phone,guardian_email from public.members where id=pg_temp.gid(105);
insert into public.member_invites(id,tenant_id,member_id,token_hash,status,issued_by_staff_id,expires_at)
values(pg_temp.gid(751),pg_temp.gid(1),pg_temp.gid(105),rpad('ae',64,'0'),'pending',pg_temp.gid(21),clock_timestamp()+interval '48 hours');
create temp table before_consent_count as select count(*) as n from public.guardian_consents where tenant_id=pg_temp.gid(1);
select pg_temp.claim('gym_manager',22,1,902);
set local role authenticated;
select lives_ok($q$select public.transition_member_to_own_account(pg_temp.gid(105),'  Now adult  ')$q$,'GRD-012: manager may hand over with trimmed reason');
set local role postgres;
select ok(exists(select 1 from public.members where id=pg_temp.gid(105) and user_id is null and guardian_linked_at is null),'GRD-012: handover clears binding and guardian marker');
select is((select count(*)::integer from auth.sessions where user_id=pg_temp.gid(906)),0,'GRD-012: every former guardian session deleted');
select is((select count(*)::integer from auth.sessions where user_id=pg_temp.gid(908)),1,'GRD-012: unrelated sibling guardian session retained');
select is((select status::text from public.member_invites where id=pg_temp.gid(751)),'pending','GRD-012: pending invitation is untouched by handover');
select results_eq($q$select guardian_name,guardian_relation,guardian_phone,guardian_email from public.members where id=pg_temp.gid(105)$q$,$q$select * from before_handover$q$,'GRD-012: handover retains guardian facts');
select is((select count(*) from public.guardian_consents where tenant_id=pg_temp.gid(1)),(select n from before_consent_count),'GRD-012: handover retains immutable consent history');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.account_transitioned' and record_type='member' and record_id=pg_temp.gid(105) and actor_user_id=pg_temp.gid(902) and actor_role='gym_manager' and before='{"user_linked":true,"guardian_linked":true}'::jsonb and after='{"user_linked":false,"guardian_linked":false}'::jsonb and reason='Now adult'),'GRD-020: handover exact audit and trimmed reason');
update public.members set user_id=pg_temp.gid(906) where id=pg_temp.gid(108);
select is((select guardian_linked_at from public.members where id=pg_temp.gid(108)),null::timestamptz,'GRD-013: operator-bound account does not gain guardian marker');
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(108),'Valid reason')$q$),'GL085','GRD-012: ordinary operator-bound adult cannot use guardian handover');
set local role postgres;
update public.members set user_id=null where id=pg_temp.gid(103);
select is((select guardian_linked_at from public.members where id=pg_temp.gid(103)),null::timestamptz,'GRD-013: changing user alone clears old guardian marker');
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=now() where id=pg_temp.gid(103)$q$),'23514','GRD-013: marker cannot exist on unbound member');

-- Scan and read-model scope: seven live members; the foreign gym is independent.
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.gid(51),pg_temp.gid(1),'GRD monthly',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
select pg_temp.gid(500+n),pg_temp.gid(1),pg_temp.gid(n),pg_temp.gid(51),'active',app.gym_today(pg_temp.gid(1))-30,app.gym_today(pg_temp.gid(1))+30,10000 from unnest(array[101,102,103,104,105,106,108]) n;
select pg_temp.claim('gym_owner');
set local role authenticated;
select ok((select changed from public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','paper')),'GRD-008: prepare eligible minor control');
select results_eq($q$select tracked,no_birth_date,minor_no_guardian,minor_consent_missing,handover_due from public.read_guardian_coverage()$q$,$q$select 4,1,2,0,0$q$,'GRD-019: coverage exact live-member state counts');
select results_eq($q$select member_id from public.list_guardian_attention('no_birth_date') order by member_id$q$,$q$select pg_temp.gid(106)$q$,'GRD-019: only unqualified unknown age in attention');
select results_eq($q$select member_id from public.list_guardian_attention('minor_no_guardian') order by member_id$q$,$q$select pg_temp.gid(101) union all select pg_temp.gid(102)$q$,'GRD-019: attention matches incomplete-guardian count');
select is((select members_without_dob_attested_adult_at from public.read_guardian_coverage()),(select members_without_dob_attested_adult_at from first_attestation),'GRD-019: coverage returns fixed owner cutoff');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is(app.run_no_show_scan(pg_temp.gid(1),app.gym_today(pg_temp.gid(1))),4,'GRD-008: scan opens only three adults and one consented minor');
select is((select count(*)::integer from public.no_show_cases where tenant_id=pg_temp.gid(1) and status in('open','contacted','follow_up_due')),4,'GRD-008: exact eligible live queue');
select is((select count(*)::integer from public.no_show_cases where tenant_id=pg_temp.gid(1) and member_id in(pg_temp.gid(101),pg_temp.gid(102),pg_temp.gid(106)) and status in('open','contacted','follow_up_due')),0,'GRD-008: unknown/incomplete members do not enter queue');
select is(app.run_no_show_scan(pg_temp.gid(1),app.gym_today(pg_temp.gid(1))),0,'GRD-008/027: repeated scan keeps existing adult behavior and counts opened only');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(103),false,'guardian-absence-v1','phone')$q$,'GRD-007: eligible scanned minor withdrawn');
select results_eq($q$select tracked,no_birth_date,minor_no_guardian,minor_consent_missing from public.read_guardian_coverage()$q$,$q$select 3,1,2,1$q$,'GRD-019: withdrawal immediately moves coverage category');
select results_eq($q$select member_id from public.list_guardian_attention('minor_consent_missing')$q$,$q$select pg_temp.gid(103)$q$,'GRD-019: consent attention returns withdrawn member');
set local role postgres;
select is((select count(*)::integer from public.no_show_cases where tenant_id=pg_temp.gid(1) and member_id=pg_temp.gid(103) and status='closed'),2,'GRD-007/008: prior closed case retained and newly scanned case closed');

-- Immediate triggers must close all three live statuses and retain follow-ups.
insert into public.members(id,tenant_id,branch_id,full_name,phone,email,date_of_birth,guardian_name,guardian_relation,guardian_phone,created_at)
select pg_temp.gid(n),pg_temp.gid(1),pg_temp.gid(11),'Closure '||n,'+916900000'||n,'closure'||n||'@example.test',(current_date-interval '10 years')::date,'Parent private','mother','+916900009906',clock_timestamp()+interval '1 day' from generate_series(109,111) n;
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(109),true,'v1','paper')$q$,'GRD-009: prepare open-case minor');
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(110),true,'v1','paper')$q$,'GRD-009: prepare contacted-case minor');
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(111),true,'v1','paper')$q$,'GRD-009: prepare follow-up-due minor');
set local role postgres;
insert into public.no_show_cases(id,tenant_id,member_id,status,opened_on,absent_days_at_open,threshold_days)
select pg_temp.gid(300+n),pg_temp.gid(1),pg_temp.gid(n),'open',current_date,10,7 from generate_series(109,111) n;
set local role authenticated;
insert into public.follow_ups(id,tenant_id,case_id,staff_id,channel,outcome) values(pg_temp.gid(410),pg_temp.gid(1),pg_temp.gid(410),pg_temp.gid(21),'call','no_response');
insert into public.follow_ups(id,tenant_id,case_id,staff_id,channel,outcome,next_follow_up_at) values(pg_temp.gid(411),pg_temp.gid(1),pg_temp.gid(411),pg_temp.gid(21),'call','timing_issue',clock_timestamp()+interval '1 day');
set local role postgres;
select results_eq($q$select status::text from public.no_show_cases where id in(pg_temp.gid(409),pg_temp.gid(410),pg_temp.gid(411)) order by id$q$,$q$values('open'::text),('contacted'::text),('follow_up_due'::text)$q$,'GRD-009: controls genuinely occupy every live status');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(109),(current_date-interval '10 years')::date,'Parent private','mother',null,null)$q$,'GRD-009: phone removal loses guardian completeness');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(110),null,'Parent private','mother','+916900009906',null)$q$,'GRD-009: DOB removal loses eligibility beyond cutoff');
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(111),false,'v1','phone')$q$,'GRD-009: withdrawal closes follow-up-due');
set local role postgres;
select is((select count(*)::integer from public.no_show_cases where id in(pg_temp.gid(409),pg_temp.gid(410),pg_temp.gid(411)) and status='closed' and closed_at is not null and returned_at is null),3,'GRD-009: open/contacted/follow-up-due all close in same transaction');
select is((select count(*)::integer from public.follow_ups where id in(pg_temp.gid(410),pg_temp.gid(411))),2,'GRD-009: all follow-up evidence survives');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.scoring_stopped' and record_id=pg_temp.gid(109) and after='{"closed_cases":1,"cause":"guardian_changed"}'),'GRD-020: guardian-change cause preserved');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.scoring_stopped' and record_id=pg_temp.gid(110) and after='{"closed_cases":1,"cause":"age_changed"}'),'GRD-020: age-change cause preserved');

-- Attendance remains available to members whose absence inference is off.
select pg_temp.claim('front_desk',23,1,903);
set local role authenticated;
select lives_ok($q$select public.record_staff_front_desk_check_in(pg_temp.gid(102),'Guardian missing does not prevent visit',pg_temp.gid(610))$q$,'GRD-010: staff assisted check-in works without guardian or consent');
select lives_ok($q$insert into public.attendance(id,tenant_id,branch_id,member_id,membership_id,source,assisted_by_staff_id,assist_reason) values(pg_temp.gid(611),pg_temp.gid(1),pg_temp.gid(11),pg_temp.gid(106),pg_temp.gid(606),'front_desk',pg_temp.gid(23),'Unknown age does not prevent visit')$q$,'GRD-010: direct assisted attendance allowed for unscored unknown-age member');
set local role postgres;
select is((select count(*)::integer from public.attendance where tenant_id=pg_temp.gid(1) and member_id in(pg_temp.gid(102),pg_temp.gid(106))),2,'GRD-010: unscored member visits are actually persisted');

-- Contact path: ordinary payment messages need no marketing consent. Send via
-- the existing lifecycle command before opening WhatsApp; no fabricated sent row.
select pg_temp.claim('gym_owner');
set local role authenticated;
insert into public.notifications(id,tenant_id,member_id,channel,status,category,template_key,dedupe_key,scheduled_for,payload) values
(pg_temp.gid(651),pg_temp.gid(1),pg_temp.gid(103),'in_app','scheduled','payment','payment_receipt','grd69:guardian',transaction_timestamp(),'{"body":"Receipt"}'),
(pg_temp.gid(652),pg_temp.gid(1),pg_temp.gid(102),'in_app','scheduled','payment','payment_receipt','grd69:no-guardian',transaction_timestamp(),'{"body":"Receipt"}'),
(pg_temp.gid(653),pg_temp.gid(1),pg_temp.gid(104),'in_app','scheduled','payment','payment_receipt','grd69:adult',transaction_timestamp(),'{"body":"Receipt"}');
select lives_ok($q$select public.send_notification(pg_temp.gid(651))$q$,'GRD-017: ordinary minor in-app payment source can send');
select lives_ok($q$select public.send_notification(pg_temp.gid(652))$q$,'GRD-017: guardian-less minor retains own in-app source');
select lives_ok($q$select public.send_notification(pg_temp.gid(653))$q$,'GRD-027: adult payment source behavior unchanged');
select ok((public.open_notification_whatsapp(pg_temp.gid(651))->>'url') like 'https://wa.me/916900009906?text=%','GRD-017: WhatsApp link resolves guardian phone rather than child phone');
select ok((public.open_notification_whatsapp(pg_temp.gid(651))->>'url') like 'https://wa.me/916900009906?text=%','GRD-017: replay compares guardian snapshot and reuses URL');
select is(public.open_notification_whatsapp(pg_temp.gid(652)),'{"communicationOptedOut":true}'::jsonb,'GRD-017: null resolved recipient yields opt-out and no URL');
select ok((public.open_notification_whatsapp(pg_temp.gid(653))->>'url') like 'https://wa.me/916900000104?text=%','GRD-027: adult WhatsApp resolves own phone');
set local role postgres;
select is((select count(*)::integer from public.notifications where source_notification_id=pg_temp.gid(651) and recipient_phone='+916900009906'),1,'GRD-017: guardian snapshot stored once');
select is((select count(*)::integer from public.notifications where source_notification_id=pg_temp.gid(652)),0,'GRD-017: null recipient creates no child');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(103),(current_date-interval '10 years')::date,'Parent private','mother','+916900009907','adult69@example.test')$q$,'GRD-017: change guardian phone after first WhatsApp');
select is(public.open_notification_whatsapp(pg_temp.gid(651)),'{"communicationOptedOut":true}'::jsonb,'GRD-017: stale recipient snapshot refuses replay URL');
set local role postgres;
select is((select recipient_phone from public.notifications where source_notification_id=pg_temp.gid(651)),'+916900009906','GRD-017: replay refusal never rewrites sent recipient snapshot');

-- Cross-tenant and audience checks now operate on real consent history.
select pg_temp.claim('gym_owner',25,2,905);
set local role authenticated;
select is((select count(*)::integer from public.guardian_consents where tenant_id=pg_temp.gid(1)),0,'GRD-021: foreign gym cannot read any guardian consent history');
select is(app.member_guardian_consent_state(pg_temp.gid(1),pg_temp.gid(103)),'none','GRD-003: unreadable member yields no consent information');
select is(app.member_scoring_state(pg_temp.gid(1),pg_temp.gid(103),current_date),null::text,'GRD-003: unreadable member scoring state is null');
select ok(not app.member_scoring_eligible(pg_temp.gid(1),pg_temp.gid(103),current_date),'GRD-003: unreadable scoring gate fails safe');
select is(app.member_contact_phone(pg_temp.gid(1),pg_temp.gid(103)),null::text,'GRD-017/021: resolver does not expose foreign guardian phone');
select is(app.gym_today(pg_temp.gid(1)),null::date,'GRD-001/021: unreadable gym date returns null');
set local role postgres;
select pg_temp.claim('trainer',24,1,904);
set local role authenticated;
select is((select count(*)::integer from public.guardian_consents where tenant_id=pg_temp.gid(1)),0,'GRD-021: trainer still reads no history after rows exist');
set local role postgres;
select pg_temp.claim('member',null,1,907);
set local role authenticated;
select is((select count(*)::integer from public.guardian_consents where tenant_id=pg_temp.gid(1)),0,'GRD-021: member still reads no history after rows exist');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is_empty($q$select id from public.audit_log where tenant_id=pg_temp.gid(1) and action in('member.age_changed','member.guardian_changed','member.scoring_stopped','guardian_consent.granted','guardian_consent.withdrawn','member.account_transitioned')
and (coalesce(before,'{}')::text||coalesce(after,'{}')::text) ~ '(Parent private|Parent changed|PARENT PRIVATE|@example[.]test|91690000|paper private|date_of_birth|guardian_name|guardian_phone|guardian_email|token)'$q$,'GRD-020/026: all guardian audits exclude personal field names and values, source and token');
select is_empty($q$select id from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.age_changed'
and ((select array_agg(k order by k) from jsonb_object_keys(before) k)is distinct from array['dob_known','minor'] or (select array_agg(k order by k) from jsonb_object_keys(after) k)is distinct from array['dob_known','minor'])$q$,'GRD-020: age audits contain exactly booleans, no birth dates');
select is_empty($q$select id from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.guardian_changed'
and ((select array_agg(k order by k) from jsonb_object_keys(before) k)is distinct from array['complete','email_present','guardian_present','phone_present','relation'] or (select array_agg(k order by k) from jsonb_object_keys(after) k)is distinct from array['complete','email_present','guardian_present','phone_present','relation'])$q$,'GRD-020: guardian audits contain exactly presence/relation facts');

-- Native shape and exact validation boundaries, independent of form validation.
select is_empty($q$
with w(col,typ,req,def) as(values ('id','uuid',true,true),('tenant_id','uuid',true,false),('member_id','uuid',true,false),('granted','bool',true,false),('version','text',true,false),('source','text',true,false),('guardian_name','text',true,false),('guardian_relation','guardian_relation',true,false),('recorded_at','timestamptz',true,true),('recorded_by_staff_id','uuid',true,false),('created_at','timestamptz',true,true))
select w.col from w left join pg_attribute a on a.attrelid=to_regclass('public.guardian_consents') and a.attname=w.col
left join pg_type t on t.oid=a.atttypid left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
where a.attname is null or t.typname<>w.typ or a.attnotnull<>w.req or (d.adbin is not null)<>w.def
$q$,'GRD-006: exact consent types, required fields and three defaults');
select ok((select pg_get_expr(d.adbin,d.adrelid) like '%clock_timestamp%' from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where a.attrelid='public.guardian_consents'::regclass and a.attname='recorded_at'),'GRD-006: consent record default uses wall clock rather than transaction clock');
select is_empty($q$
with w(sig,v) as(values ('app.member_adult_on(date)','i'),('app.member_is_minor_on(date,date)','i'),('app.gym_today(uuid)','s'),('app.member_guardian_complete(public.members)','i'),('app.member_guardian_consent_state(uuid,uuid)','s'),('app.member_scoring_state(uuid,uuid,date)','s'),('app.member_scoring_eligible(uuid,uuid,date)','s'),('app.member_invite_email(public.members,date)','s'),('app.member_invite_guardian_ok(public.members,date)','s'),('app.member_contact_phone(uuid,uuid)','s'),('app.member_contact_email(uuid,uuid)','s'))
select sig from w left join pg_proc p on p.oid=to_regprocedure(w.sig) where p.oid is null or p.prosecdef or p.provolatile::text<>w.v
or not coalesce(p.proconfig @> array['search_path=""'],false) or not has_function_privilege('authenticated',p.oid,'EXECUTE') or not has_function_privilege('service_role',p.oid,'EXECUTE')
$q$,'GRD-001/003/014/017/021: eleven ordinary helpers have invoker posture, specified volatility, empty path and both intended caller grants');
select is(pg_temp.refusal($q$update public.members set guardian_name=' Parent private ' where id=pg_temp.gid(103)$q$),'23514','GRD-004: direct table writer cannot store untrimmed name');
select is(pg_temp.refusal($q$update public.members set guardian_name='' where id=pg_temp.gid(103)$q$),'23514','GRD-004: native check rejects empty name');
select is(pg_temp.refusal($q$update public.members set guardian_name=null where id=pg_temp.gid(103)$q$),'23514','GRD-004: native check binds name and relation together');
select is(pg_temp.refusal($q$update public.members set guardian_phone='+1234567' where id=pg_temp.gid(103)$q$),'23514','GRD-004: seven phone digits below lower bound');
select is(pg_temp.refusal($q$update public.members set guardian_phone='+1234567890123456' where id=pg_temp.gid(103)$q$),'23514','GRD-004: sixteen phone digits above upper bound');
select is(pg_temp.refusal($q$update public.members set guardian_email=repeat('a',248)||'@x.test' where id=pg_temp.gid(103)$q$),'23514','GRD-004: 255-character email rejected');
select is(pg_temp.refusal($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.gid(1),pg_temp.gid(107),true,'v1','paper','Parent','mother',pg_temp.gid(21))$q$),'23503','GRD-021: trusted fixture cannot cross tenant-member FK');
select is(pg_temp.refusal($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.gid(1),pg_temp.gid(103),true,'v1','paper','Parent','mother',pg_temp.gid(25))$q$),'23503','GRD-021: trusted fixture cannot cross tenant-actor FK');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(109),(current_date-interval '10 years')::date,repeat('a',120),'other','+12345678',repeat('a',247)||'@x.test')$q$,'GRD-004: name 120, phone 8 digits and email 254 accepted');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(109),(current_date-interval '10 years')::date,repeat('a',120),'other','+123456789012345',repeat('a',247)||'@x.test')$q$,'GRD-004: phone 15 digits accepted');
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(109),true,repeat('a',64),repeat('s',200))$q$,'GRD-006: version 64 and source 200 accepted at upper boundary');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(109),true,repeat('a',65),'paper')$q$),'22023','GRD-006: version 65 rejected');
select is(pg_temp.refusal($q$insert into public.organization_settings(tenant_id,members_without_dob_attested_adult_at) values(pg_temp.gid(1),clock_timestamp())$q$),'42501','GRD-002: session INSERT cannot initialize cutoff even before duplicate-key resolution');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local role service_role;
select is(pg_temp.refusal($q$update public.organization_settings set members_without_dob_attested_adult_at=clock_timestamp() where tenant_id=pg_temp.gid(2)$q$),'42501','GRD-002: subjectless service-role tool cannot stamp cutoff');
select is(pg_temp.refusal($q$insert into public.organization_settings(tenant_id,members_without_dob_attested_adult_at) values(pg_temp.gid(2),clock_timestamp())$q$),'42501','GRD-002: service-role INSERT cannot initialize cutoff');
set local role postgres;

-- Real inactive owner, missing settings, and all platform callers fail closed.
update public.staff set is_active=false where id=pg_temp.gid(21);
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: inactive owner is refused even on replay');
set local role postgres;
update public.staff set is_active=true where id=pg_temp.gid(21);
insert into auth.users(id) values(pg_temp.gid(909)),(pg_temp.gid(910));
insert into public.platform_users(user_id,role,full_name,email,is_active) values
(pg_temp.gid(909),'super_admin','GRD platform','root69@example.test',true),
(pg_temp.gid(910),'platform_support','GRD support','support69@example.test',true);
select pg_temp.claim('super_admin',null,1,909);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: super admin cannot attest on gym owner behalf');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(104),'Valid reason')$q$),'42501','GRD-012: platform handover forbidden');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(109),true,'v1','paper')$q$),'42501','GRD-006: platform cannot record guardian consent');
select ok((select count(*)>0 from public.guardian_consents where tenant_id=pg_temp.gid(1)),'GRD-021: standard platform policy permits history read');
set local role postgres;
select pg_temp.claim('platform_support',null,1,910);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: platform support cannot attest');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(104),'Valid reason')$q$),'42501','GRD-012: platform support cannot hand over');
set local role postgres;
select pg_temp.claim('gym_owner',21,1,909,true);
set local role authenticated;
select lives_ok($q$select public.read_member_guardian(pg_temp.gid(103))$q$,'GRD-019: support preview may read staff guardian projection');
select lives_ok($q$select public.read_guardian_coverage()$q$,'GRD-019: support preview may read coverage');
select lives_ok($q$select public.list_guardian_attention('minor_consent_missing')$q$,'GRD-019: support preview may read attention');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- A trusted watched-column edit must be audited even outside product commands.
update public.members set guardian_email='trusted69@example.test' where id=pg_temp.gid(109);
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='member.guardian_changed' and record_id=pg_temp.gid(109) and actor_user_id is null and actor_role is null and after->>'email_present'='true'),'GRD-020: subjectless trusted direct changes audit with null actor/role');
select is(pg_temp.refusal($q$select app.guardian_audit(pg_temp.gid(1),null,null,'unapproved.action','member',pg_temp.gid(109),null,null,null)$q$),'22023','GRD-020: private guardian audit action allowlist refuses arbitrary actions');

-- Adult invitation keeps INV semantics and never stamps a guardian marker.
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.issue_member_invite(pg_temp.gid(104),rpad('a1',64,'0'))$q$,'GRD-027: adult invite issues to own email');
set local role postgres;
select pg_temp.claim(null,null,1,908);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(rpad('a1',64,'0'))),'linked','GRD-027: adult Google identity binds unchanged');
set local role postgres;
select is((select guardian_linked_at from public.members where id=pg_temp.gid(104)),null::timestamptz,'GRD-013/027: adult redemption never sets guardian-linked marker');
create temporary table marker_adult_before as select
  (select to_jsonb(m) from public.members m where id=pg_temp.gid(104)) as member_value,
  (select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]'::jsonb) from auth.sessions s where user_id=pg_temp.gid(908)) as sessions_value,
  (select count(*) from public.audit_log where tenant_id=pg_temp.gid(1)) as audit_count;
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$update public.members set guardian_linked_at=statement_timestamp() where id=pg_temp.gid(104)$q$,true),'42501:guardian_binding_command_required','GRD-012/013: owner cannot forge guardian provenance on an adult own-account binding');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(pg_temp.gid(104),'Attempt after refused forgery')$q$),'GL085','GRD-012: refused adult marker forgery does not enable handover');
set local role postgres;
select is((select to_jsonb(m) from public.members m where id=pg_temp.gid(104)),(select member_value from marker_adult_before),'GRD-013: adult forgery and handover refusals preserve every member value');
select is((select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]'::jsonb) from auth.sessions s where user_id=pg_temp.gid(908)),(select sessions_value from marker_adult_before),'GRD-013: adult forgery and handover refusals preserve sessions');
select is((select count(*) from public.audit_log where tenant_id=pg_temp.gid(1)),(select audit_count from marker_adult_before),'GRD-013: adult forgery and handover refusals append no audit');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(102),(current_date-interval '10 years')::date,'Parent private','mother','+916900009906','parent69@example.test')$q$,'GRD-011: prepare pending pre-birthday guardian invitation');
select lives_ok($q$select public.issue_member_invite(pg_temp.gid(102),rpad('a2',64,'0'))$q$,'GRD-011: reissue minor guardian invitation');
select lives_ok($q$select public.set_member_age_guardian(pg_temp.gid(102),date '1990-01-01','Parent private','mother','+916900009906','parent69@example.test')$q$,'GRD-011: pending invite member becomes known adult');
set local role postgres;
select pg_temp.claim(null,null,1,906);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(rpad('a2',64,'0'))),'email_mismatch','GRD-011: pending pre-birthday invite now compares own email before account binding');
set local role postgres;
select pg_temp.claim(null,null,1,907);
set local role authenticated;
select is((select outcome from public.redeem_member_invite(rpad('a2',64,'0'))),'linked','GRD-011: current adult own account matches pending token');
set local role postgres;
select is((select guardian_linked_at from public.members where id=pg_temp.gid(102)),null::timestamptz,'GRD-011/013: birthday redemption retains guardian facts but stamps no marker');

-- Explicit null-input slots, settings absence and scan recovery/closing.
select pg_temp.claim('gym_owner');
set local role authenticated;
select is(pg_temp.refusal($q$select public.set_member_age_guardian(null,null,null,null,null,null)$q$),'22023','GRD-005: authorized null member id is malformed input');
select is(pg_temp.refusal($q$select public.transition_member_to_own_account(null,'Valid reason')$q$),'22023','GRD-012: authorized null handover id is malformed input');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(109),true,null,'paper')$q$),'22023','GRD-006: null version rejected');
select is(pg_temp.refusal($q$select public.record_guardian_consent(pg_temp.gid(109),true,'v1',null)$q$),'22023','GRD-006: null source rejected');
set local role postgres;
delete from public.organization_settings where tenant_id=pg_temp.gid(2);
select pg_temp.claim('gym_owner',25,2,905);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attest_members_without_dob_adult()$q$),'42501','GRD-002: real owner without settings receives permission refusal');
set local role postgres;
insert into public.organization_settings(tenant_id) values(pg_temp.gid(2));
select set_config('request.jwt.claims','',true);
insert into public.no_show_cases(id,tenant_id,member_id,status,opened_on,absent_days_at_open,threshold_days)
values(pg_temp.gid(302),pg_temp.gid(1),pg_temp.gid(106),'open',current_date-1,10,7);
select is(app.run_no_show_scan(pg_temp.gid(1),app.gym_today(pg_temp.gid(1))),0,'GRD-008: scan closes ineligible historical queue without counting it as opened');
select ok(exists(select 1 from public.no_show_cases where id=pg_temp.gid(302) and status='closed' and closed_at is not null and returned_at is null),'GRD-008: close pass independently checks scoring eligibility');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.record_guardian_consent(pg_temp.gid(103),true,'guardian-absence-v1','paper')$q$,'GRD-009: restore minor eligibility');
set local role postgres;
select is((select count(*)::integer from public.no_show_cases where tenant_id=pg_temp.gid(1) and member_id=pg_temp.gid(103) and status in('open','contacted','follow_up_due')),0,'GRD-009: restored eligibility opens nothing immediately');
select set_config('request.jwt.claims','',true);
select is(app.run_no_show_scan(pg_temp.gid(1),app.gym_today(pg_temp.gid(1))),1,'GRD-008/009: restored consent opens new case on next scan');
select is((select count(*)::integer from public.no_show_cases where tenant_id=pg_temp.gid(1) and member_id=pg_temp.gid(103) and status='closed'),2,'GRD-008: restored eligibility never reopens closed history');

-- Marker same-statement exception and cross-gym collision privacy.
insert into auth.users(id) values(pg_temp.gid(911)),(pg_temp.gid(912));
update public.members set user_id=pg_temp.gid(911),guardian_linked_at=statement_timestamp() where id=pg_temp.gid(103);
select ok((select guardian_linked_at is not null from public.members where id=pg_temp.gid(103)),'GRD-013: statement changing both user and marker preserves explicit marker');
update public.members set user_id=pg_temp.gid(912),guardian_linked_at=guardian_linked_at where id=pg_temp.gid(103);
select is((select guardian_linked_at from public.members where id=pg_temp.gid(103)),null::timestamptz,'GRD-013: trusted rebind explicitly assigning unchanged old timestamp still clears marker');
update public.members set user_id=pg_temp.gid(911),guardian_linked_at=statement_timestamp() where id=pg_temp.gid(103);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select lives_ok($q$update public.members set user_id=pg_temp.gid(912),guardian_linked_at=guardian_linked_at where id=pg_temp.gid(103)$q$,'GRD-013: subjectless service operator may rebind with unchanged explicit marker');
set local role postgres;
select is((select guardian_linked_at from public.members where id=pg_temp.gid(103)),null::timestamptz,'GRD-013: subjectless operator rebind clears unchanged explicit marker');
select set_config('request.jwt.claims','',true);
update public.members set user_id=pg_temp.gid(911),guardian_linked_at=statement_timestamp() where id=pg_temp.gid(103);
update public.members set user_id=pg_temp.gid(912) where id=pg_temp.gid(103);
select is((select guardian_linked_at from public.members where id=pg_temp.gid(103)),null::timestamptz,'GRD-013: direct rebind without simultaneous marker clears marker');
update public.members set user_id=null where id=pg_temp.gid(103);
update public.members set user_id=pg_temp.gid(911),email='trusted69@example.test' where id=pg_temp.gid(107);
select pg_temp.claim('gym_owner');
set local role authenticated;
select ok(not (select link_email_in_use from public.read_member_guardian(pg_temp.gid(109))),'GRD-016: account collision hint looks at no other gym');
set local role postgres;

-- Deterministic attention cap/order with more than 100 actual eligible rows.
-- Bulk fixtures all postdate the cutoff; no artificial DOB or attestation.
insert into public.members(id,tenant_id,branch_id,full_name,phone,created_at)
select pg_temp.gid(n),pg_temp.gid(1),pg_temp.gid(11),'Attention '||lpad((2106-n)::text,3,'0'),'+91690'||lpad(n::text,7,'0'),clock_timestamp() from generate_series(2001,2105) n;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
select pg_temp.gid(10000+n),pg_temp.gid(1),pg_temp.gid(n),pg_temp.gid(51),'active',app.gym_today(pg_temp.gid(1))-1,app.gym_today(pg_temp.gid(1))+30,10000 from generate_series(2001,2105) n;
select pg_temp.claim('gym_owner');
set local role authenticated;
select is((select count(*)::integer from public.list_guardian_attention('no_birth_date')),100,'GRD-019: attention list capped at exactly 100 rows');
select results_eq($q$select member_id from public.list_guardian_attention('no_birth_date')$q$,$q$select pg_temp.gid(n) from generate_series(2006,2105) n order by n desc$q$,'GRD-019: cap applies after full_name/id ordering rather than insertion order');
set local role postgres;

-- Trusted linked fixture isolates unlink from the attention membership counts.
insert into auth.users(id) values(pg_temp.gid(913));
insert into auth.sessions(id,user_id) values(pg_temp.gid(713),pg_temp.gid(913));
insert into public.members(id,tenant_id,branch_id,full_name,phone,user_id,guardian_linked_at,date_of_birth)
values(pg_temp.gid(113),pg_temp.gid(1),pg_temp.gid(11),'Trusted unlink guardian','+916900000113',pg_temp.gid(913),statement_timestamp(),date '1990-01-01');
select ok((select guardian_linked_at is not null from public.members where id=pg_temp.gid(113)),'GRD-013: trusted marker-bearing INSERT retains linked provenance');
select pg_temp.claim('gym_owner');
set local role authenticated;
select lives_ok($q$select public.unlink_member_identity(pg_temp.gid(113),'Guardian binding reset')$q$,'GRD-013: authorized unlink clears trusted linked provenance');
set local role postgres;
select ok((select user_id is null and guardian_linked_at is null from public.members where id=pg_temp.gid(113)),'GRD-013: unlink clears binding and guardian marker together');
select is((select count(*)::integer from auth.sessions where user_id=pg_temp.gid(913)),0,'GRD-013: guardian unlink preserves INV session invalidation');

select * from finish();
rollback;
