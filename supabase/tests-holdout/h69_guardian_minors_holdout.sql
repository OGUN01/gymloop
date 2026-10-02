-- Independent GRD holdout: frozen proposal and bar only; no visible suite or implementation read.
-- Fixture prefix 69900000. Every assertion catches refusal without ending the rollback proof.
-- GRD-001..021/027: dates, cutoff, consent identity, actor/tenancy, contact and binding.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(292);

create function pg_temp.u(n integer) returns uuid language sql immutable as $$
select ('69900000-0000-4000-8000-' || lpad(to_hex(n),12,'0'))::uuid
$$;
create function pg_temp.claims(n integer default 1) returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(200+n),'role','authenticated',
 'tenant_id',pg_temp.u(case when n=5 then 2 else 1 end),'staff_id',pg_temp.u(200+n),
 'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk'
 when 4 then 'trainer' when 5 then 'gym_owner' else 'gym_owner' end)::text
$$;
create function pg_temp.run(q text, c text default pg_temp.claims(), r text default 'authenticated')
returns jsonb language plpgsql as $$
declare v jsonb; con text; det text;
begin
 perform set_config('request.jwt.claims',coalesce(c,''),true);
 execute format('set local role %I',r);
 begin execute q into v;
 exception when others then
 get stacked diagnostics con=constraint_name, det=pg_exception_detail;
 v:=jsonb_build_object('error',sqlstate,'constraint',con,'detail',det);
 end;
 set local role postgres;
 perform set_config('request.jwt.claims','',true);
 return coalesce(v,'null'::jsonb);
end $$;

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
(pg_temp.u(1),'GRD holdout A','H69GRA','active','Asia/Kolkata','INR'),
(pg_temp.u(2),'GRD holdout B','H69GRB','active','Pacific/Kiritimati','INR'),
(pg_temp.u(3),'GRD cutoff fixture','H69GRC','active','Asia/Kolkata','INR');
insert into public.organization_settings(tenant_id) values(pg_temp.u(1)),(pg_temp.u(2));
insert into public.organization_settings(tenant_id,members_without_dob_attested_adult_at)
values(pg_temp.u(3),'2026-01-01 00:00:00+00');
insert into public.branches(id,tenant_id,name,is_default) values
(pg_temp.u(11),pg_temp.u(1),'A',true),(pg_temp.u(12),pg_temp.u(2),'B',true),
(pg_temp.u(13),pg_temp.u(3),'C',true);
insert into auth.users(id) select pg_temp.u(n) from generate_series(201,207) n;
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active) values
(pg_temp.u(201),pg_temp.u(201),pg_temp.u(1),pg_temp.u(11),'gym_owner','Owner',true),
(pg_temp.u(202),pg_temp.u(202),pg_temp.u(1),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(203),pg_temp.u(203),pg_temp.u(1),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(204),pg_temp.u(204),pg_temp.u(1),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(205),pg_temp.u(205),pg_temp.u(2),pg_temp.u(12),'gym_owner','Other owner',true),
(pg_temp.u(206),pg_temp.u(206),pg_temp.u(1),pg_temp.u(11),'gym_owner','Inactive owner',false);
insert into public.members(id,tenant_id,branch_id,full_name,phone,email,date_of_birth,joined_on,created_at)
select pg_temp.u(100+n),pg_temp.u(1),pg_temp.u(11),'GRD member '||n,
 '+91969900'||lpad(n::text,4,'0'),'child'||n||'@h69.test',
 case when n=1 then date '1990-01-01' when n between 3 and 9 then current_date-3650 else null end,
 current_date-60,clock_timestamp()-interval '1 day' from generate_series(1,10) n;
insert into public.members(id,tenant_id,branch_id,full_name,phone,email,date_of_birth) values
(pg_temp.u(120),pg_temp.u(2),pg_temp.u(12),'Foreign child','+919699000020','foreign@h69.test',current_date-3650);
insert into public.members(id,tenant_id,branch_id,full_name,phone,created_at) select
 pg_temp.u(130+n),pg_temp.u(3),pg_temp.u(13),'Cutoff '||n,'+91969900003'||n,
 timestamptz '2026-01-01 00:00:00+00'+case n when 1 then interval '-1 microsecond'
 when 2 then interval '0' else interval '1 microsecond' end from generate_series(1,3)n;
update public.members set guardian_name='Guardian Secret',guardian_relation='mother',
 guardian_phone='+919699111111',guardian_email='guardian@h69.test' where id in(pg_temp.u(104),pg_temp.u(105),pg_temp.u(106),pg_temp.u(107),pg_temp.u(108),pg_temp.u(109));

select enum_has_labels('public','guardian_relation',array['mother','father','grandparent','sibling','legal_guardian','other']::name[],'GRD-004 canonical relation order');
select ok((select relrowsecurity from pg_class where oid='public.guardian_consents'::regclass),'GRD-021 RLS enabled');
select is(app.member_adult_on(date '2008-02-29'),date '2026-03-01','GRD-001 leap birthday uses later day');
select is(app.member_adult_on(date '2008-03-01'),date '2026-03-01','GRD-001 ordinary anniversary');
select is(app.member_adult_on(null),null::date,'GRD-001 unknown stays unknown');
select ok(app.member_is_minor_on('2008-02-29','2026-02-28') and not app.member_is_minor_on('2008-02-29','2026-03-01'),'GRD-001 leap day inclusive boundary');
select ok(app.member_is_minor_on('2008-03-01','2026-02-28') and not app.member_is_minor_on('2008-03-01','2026-03-01'),'GRD-001 ordinary inclusive boundary');
select ok(not app.member_is_minor_on('2000-01-01','2018-01-01') and app.member_is_minor_on('2026-10-03','2026-10-02'),'GRD-001 adulthood and future DOB');
select ok(not app.member_is_minor_on(null,current_date) and not app.member_is_minor_on('2008-01-01',null),'GRD-001 null arguments are not minors');
select is((timestamptz '2026-03-01 19:00+00' at time zone 'Asia/Kolkata')::date,date '2026-03-02','GRD-001 fixed non-UTC date boundary');
select is(app.gym_today(pg_temp.u(2)),(statement_timestamp() at time zone 'Pacific/Kiritimati')::date,'GRD-001 gym date uses organization timezone');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(101),current_date),'on_adult','GRD-003 adult independent of guardian');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(102),current_date),'off_age_unknown','GRD-002 null cutoff fails safe');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(103),current_date),'off_no_guardian','GRD-003 incomplete record');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(104),current_date),'off_no_consent','GRD-003 complete without consent');
select ok(not app.member_scoring_eligible(pg_temp.u(1),pg_temp.u(101),null),'GRD-003 null evaluation date fails closed');
select is(app.member_scoring_state(pg_temp.u(3),pg_temp.u(131),current_date),'on_adult','GRD-002 strictly before cutoff');
select is(app.member_scoring_state(pg_temp.u(3),pg_temp.u(132),current_date),'on_adult','GRD-002 equality included');
select is(app.member_scoring_state(pg_temp.u(3),pg_temp.u(133),current_date),'off_age_unknown','GRD-002 one microsecond after excluded');
select is(app.member_contact_phone(pg_temp.u(1),pg_temp.u(104)),'+919699111111','GRD-017 complete minor routes guardian');
select is(app.member_contact_phone(pg_temp.u(1),pg_temp.u(103)),null::text,'GRD-017 incomplete never routes child');
select is(app.member_contact_email(pg_temp.u(1),pg_temp.u(104)),'guardian@h69.test','GRD-017 guardian email');
select is(app.member_contact_email(pg_temp.u(1),pg_temp.u(103)),null::text,'GRD-017 no guardian means no recipient email');
select is(app.member_contact_phone(pg_temp.u(1),pg_temp.u(102)),'+919699000002','GRD-002 unknown contact remains own');
select is((select app.member_invite_email(m,current_date) from public.members m where id=pg_temp.u(104)),'guardian@h69.test','GRD-014 guardian invite address');
select is((select app.member_invite_email(m,current_date) from public.members m where id=pg_temp.u(102)),'child2@h69.test','GRD-027 unknown invite unchanged');
select is(pg_temp.run('select to_jsonb(app.member_scoring_state(pg_temp.u(2),pg_temp.u(120),current_date))'),'null'::jsonb,'GRD-021 foreign scoring state unreadable');
select is(pg_temp.run('select to_jsonb(app.member_scoring_eligible(pg_temp.u(2),pg_temp.u(120),current_date))'),'false'::jsonb,'GRD-021 foreign eligibility false');
select is(pg_temp.run('select to_jsonb(app.member_guardian_consent_state(pg_temp.u(2),pg_temp.u(120)))'),'"none"'::jsonb,'GRD-021 foreign consent indistinguishable');

-- Metadata checks do not inspect function bodies.

select is((select array_agg(polname::text order by polname) from pg_policy where polrelid='public.guardian_consents'::regclass),array['guardian_consents_platform_select','guardian_consents_tenant_select']::text[],'GRD-021 exactly canonical platform and tenant SELECT policies');
select ok(not exists(select 1 from pg_policy where polrelid='public.guardian_consents'::regclass and (polcmd<>'r' or polwithcheck is not null)),'GRD-021 no consent write policy');
select ok((select bool_and(polroles=array[(select oid from pg_roles where rolname='authenticated')]) from pg_policy where polrelid='public.guardian_consents'::regclass),'GRD-021 policies target authenticated alone');

select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='members' and column_name like 'guardian_%' and (is_nullable<>'YES' or column_default is not null)),'GRD-004 guardian facts nullable without defaults');
select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='guardian_consents' and column_name in('updated_at','guardian_phone','guardian_email')),'GRD-026 minimal retained consent facts');
select ok(exists(select 1 from pg_trigger where tgrelid='public.guardian_consents'::regclass and tgname='guardian_consents_preview_read_only' and tgtype=31 and not tgisinternal),'GRD-021 preview row guard');
select ok(exists(select 1 from pg_trigger where tgrelid='public.organization_settings'::regclass and tgname='organization_settings_legacy_adult_attestation_guard' and tgtype=23 and not tgisinternal),'GRD-002 timestamp INSERT/UPDATE row guard');

select ok(not has_table_privilege('authenticated','public.guardian_consents','INSERT') and
 not has_table_privilege('authenticated','public.guardian_consents','UPDATE') and
 not has_table_privilege('authenticated','public.guardian_consents','DELETE'),'GRD-006 append-only sessions');
select ok(not has_table_privilege('anon','public.guardian_consents','SELECT'),'GRD-021 anonymous table denied');
select is(pg_temp.run('select to_jsonb(count(*)) from public.guardian_consents',pg_temp.claims(4)),'0'::jsonb,'GRD-021 trainer sees no consent');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(120)) g')->>'error','42501','GRD-019 foreign read refused');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(999)) g')->>'error','42501','GRD-019 missing read same refusal');
select is(pg_temp.run('select to_jsonb(g) from public.list_guardian_attention(''arbitrary'') g')->>'error','22023','GRD-019 invalid attention reason');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(101),true,''guardian-absence-v1'',''paper'') g')->>'error','GL084','GRD-006 adult consent refused');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(102),true,''guardian-absence-v1'',''paper'') g')->>'error','GL084','GRD-006 unknown consent refused');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(103),true,''guardian-absence-v1'',''paper'') g')->>'error','GL083','GRD-006 incomplete guardian refused');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),null,''v1'',''paper'') g')->>'error','22023','GRD-006 null granted refused');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),true,''UPPER'',''paper'') g')->>'error','22023','GRD-006 version syntax');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),true,''v1'',repeat(''x'',201)) g')->>'error','22023','GRD-006 source maximum');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),true,''v1'',''  '') g')->>'error','22023','GRD-006 blank source');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(120),null,''UPPER'','''') g')->>'error','42501','GRD-006 visibility before input refusal');
select is(pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(104),current_date+1,null,null,null,null))')->>'error','22023','GRD-005 future date rejected');
select is(pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(104),current_date-3650,null,''mother'',null,null))')->>'error','22023','GRD-005 relation without name');
select is(pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(104),current_date-3650,''name'',''mother'',''bad'',null))')->>'constraint','members_guardian_phone_format_chk','GRD-005 phone format constraint');
select is(pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(104),current_date-3650,repeat(''x'',121),''mother'',null,null))')->>'constraint','members_guardian_name_chk','GRD-005 name maximum');
select is(pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(104),current_date-3650,''name'',''mother'',null,''bad''))')->>'constraint','members_guardian_email_format_chk','GRD-005 email constraint');

select set_config('request.jwt.claims',pg_temp.claims(),true);
select lives_ok($q$do $$declare a record;b record; n bigint;begin
 select * into a from public.record_guardian_consent(pg_temp.u(104),true,' guardian-absence-v1 ',' paper secret ');
 if not a.changed then raise exception 'first consent did not change';end if;
 select count(*) into n from public.audit_log where tenant_id=pg_temp.u(1);
 select * into b from public.record_guardian_consent(pg_temp.u(104),true,'guardian-absence-v1','different source');
 if b.changed or b.consent_id<>a.consent_id or b.recorded_at<>a.recorded_at then raise exception 'not exact replay';end if;
 if (select count(*) from public.audit_log where tenant_id=pg_temp.u(1))<>n then raise exception 'replay audited';end if;
 if not exists(select 1 from public.guardian_consents where id=a.consent_id and guardian_name='Guardian Secret' and guardian_relation='mother' and source='paper secret' and recorded_by_staff_id=pg_temp.u(201)) then raise exception 'snapshot or attribution';end if;
end $$;$q$,'GRD-006 first append snapshot, trim, replay ignores source without audit');
select set_config('request.jwt.claims','',true);

select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(104),current_date),'on_consent','GRD-003 granted enables');
select lives_ok($q$do $$declare n bigint; t timestamptz;begin
 select count(*),max(recorded_at) into n,t from public.guardian_consents where member_id=pg_temp.u(104);
 update public.members set guardian_name='GUARDIAN SECRET' where id=pg_temp.u(104);
 if app.member_guardian_consent_state(pg_temp.u(1),pg_temp.u(104))<>'granted' then raise exception 'case insensitive identity';end if;
 update public.members set guardian_phone='+919699222222',guardian_email=null where id=pg_temp.u(104);
 if app.member_guardian_consent_state(pg_temp.u(1),pg_temp.u(104))<>'granted' then raise exception 'contact invalidated consent';end if;
 if app.member_contact_email(pg_temp.u(1),pg_temp.u(104)) is not null then raise exception 'child email fallback';end if;
 update public.members set guardian_name='Different Guardian' where id=pg_temp.u(104);
 if app.member_scoring_state(pg_temp.u(1),pg_temp.u(104),current_date)<>'off_consent_stale' then raise exception 'renamed guardian still scoring';end if;
 if (select count(*) from public.guardian_consents where member_id=pg_temp.u(104))<>n then raise exception 'history changed';end if;
end $$;$q$,'GRD-003 identity stale but phone/email changes preserve consent/history');

select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),true,''guardian-absence-v1'',''re-consent'') g')->>'changed','true','GRD-006 stale requires fresh snapshot');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),false,''guardian-absence-v1'',''withdraw'') g')->>'changed','true','GRD-007 withdrawal appends');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(104),current_date),'off_consent_withdrawn','GRD-007 withdrawal immediate');
update public.members set guardian_name='Another Guardian' where id=pg_temp.u(104);
select is(app.member_guardian_consent_state(pg_temp.u(1),pg_temp.u(104)),'withdrawn','GRD-003 withdrawal wins over changed identity');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(104),false,''guardian-absence-v1'',''other source'') g')->>'changed','false','GRD-006 withdrawal replay independent of snapshot');
select ok((select bool_and(prev is null or recorded_at>prev) from(select recorded_at,lag(recorded_at)over(order by recorded_at)prev from public.guardian_consents where member_id=pg_temp.u(104))s),'GRD-006 strictly monotonic consent timestamps');
select is(pg_temp.run($q$update public.organization_settings set members_without_dob_attested_adult_at=clock_timestamp() where tenant_id=pg_temp.u(1) returning to_jsonb(tenant_id)$q$)->>'error','42501','GRD-002 authenticated cannot forge first timestamp');
select is(pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult() g')->>'changed','true','GRD-002 owner first attestation');
select is(pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult() g')->>'changed','false','GRD-002 owner replay');
select is((select count(*) from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.members_without_dob_attested_adult'),1::bigint,'GRD-020 one attestation audit');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(102),current_date),'on_adult','GRD-002 legacy restored');
select is(app.member_scoring_state(pg_temp.u(2),pg_temp.u(120),current_date),'off_no_guardian','GRD-002 other tenant unaffected');
insert into public.members(id,tenant_id,branch_id,full_name,phone,created_at) values(pg_temp.u(140),pg_temp.u(1),pg_temp.u(11),'After attestation','+919699000140',clock_timestamp()+interval '1 second');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(140),current_date),'off_age_unknown','GRD-002 new unknown member remains off');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(102))g')->>'age_state','unknown','GRD-019 attestation invents no known age');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(102))g')->>'legacy_attested_adult','true','GRD-019 legacy disclosure');
update public.members set date_of_birth=current_date-3650 where id=pg_temp.u(102);
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(102),current_date),'off_no_guardian','GRD-002 DOB minor overrides cutoff');
select is(pg_temp.run('select to_jsonb(public.transition_member_to_own_account(pg_temp.u(104),''valid reason''))')->>'error','GL084','GRD-012 minor before binding refusal');
select is(pg_temp.run('select to_jsonb(public.transition_member_to_own_account(pg_temp.u(101),''x''))')->>'error','22023','GRD-012 reason before binding refusal');
select is(pg_temp.run('select to_jsonb(public.transition_member_to_own_account(pg_temp.u(101),''valid reason''))')->>'error','GL085','GRD-012 adult own/unbound not guardian handover');
select is(pg_temp.run('select to_jsonb(g) from public.issue_member_invite(pg_temp.u(103),repeat(''a'',64))g')->>'error','GL083','GRD-014 missing guardian invite refused');
select is(pg_temp.run('select to_jsonb(g) from public.issue_member_invite(pg_temp.u(104),repeat(''b'',64))g')->>'error','GL083','GRD-014 complete but no email refused');

-- A frozen membership fixture bypasses unrelated period-grant triggers (ADR-098).
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency)
values(pg_temp.u(300),pg_temp.u(1),'GRD holdout plan',120,10000,'INR');
set local session_replication_role=replica;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,discount_paise,currency,periods_granted,duration_days)
select pg_temp.u(400+n),pg_temp.u(1),pg_temp.u(100+n),pg_temp.u(300),'active',current_date-60,current_date+60,10000,0,'INR',1,120 from generate_series(1,10)n;
set local session_replication_role=origin;
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,''v1'',''paper'')g')->>'changed','true','GRD-006 establish closure fixture consent');
insert into public.no_show_cases(id,tenant_id,member_id,status,opened_on,absent_days_at_open,threshold_days)
values(pg_temp.u(501),pg_temp.u(1),pg_temp.u(105),'open',current_date-10,20,7),
(pg_temp.u(502),pg_temp.u(1),pg_temp.u(106),'contacted',current_date-10,20,7),
(pg_temp.u(503),pg_temp.u(1),pg_temp.u(107),'follow_up_due',current_date-10,20,7);
insert into public.follow_ups(id,tenant_id,case_id,staff_id,channel,outcome,notes)
values(pg_temp.u(510),pg_temp.u(1),pg_temp.u(501),pg_temp.u(201),'call','no_response','Retain this history');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),false,''v1'',''withdrawn'')g')->>'changed','true','GRD-007 withdrawal closes open queue immediately');
select ok((select status='closed' and closed_at is not null and returned_at is null from public.no_show_cases where id=pg_temp.u(501)),'GRD-007 closure is not a return');
select is((select count(*) from public.follow_ups where id=pg_temp.u(510)),1::bigint,'GRD-007 follow-up survives withdrawal');
update public.members set guardian_phone=null where id=pg_temp.u(106);
select ok((select status='closed' and closed_at is not null and returned_at is null from public.no_show_cases where id=pg_temp.u(502)),'GRD-009 direct contact edit closes contacted case');
update public.members set guardian_relation='father' where id=pg_temp.u(107);
select ok((select status='closed' and closed_at is not null from public.no_show_cases where id=pg_temp.u(503)),'GRD-009 relation edit closes due case');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and record_id=pg_temp.u(105) and action='member.scoring_stopped' and after=jsonb_build_object('closed_cases',1,'cause','consent_withdrawn')),'GRD-020 closure exact cause/count');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,''v1'',''again'')g')->>'changed','true','GRD-009 renewed consent gains eligibility');
select is((select status::text from public.no_show_cases where id=pg_temp.u(501)),'closed','GRD-009 gaining eligibility does not reopen old case');
select lives_ok($q$select app.run_no_show_scan(pg_temp.u(1),current_date)$q$,'GRD-008 scan with controlled date');
select ok(exists(select 1 from public.no_show_cases where tenant_id=pg_temp.u(1) and member_id=pg_temp.u(101) and status in('open','contacted','follow_up_due')),'GRD-008 adult remains scored');
select ok(not exists(select 1 from public.no_show_cases where tenant_id=pg_temp.u(1) and member_id in(pg_temp.u(102),pg_temp.u(103),pg_temp.u(104),pg_temp.u(106),pg_temp.u(107)) and status in('open','contacted','follow_up_due')),'GRD-008 ineligible members never remain in queue');
select ok(exists(select 1 from public.no_show_cases where tenant_id=pg_temp.u(1) and member_id=pg_temp.u(105) and id<>pg_temp.u(501) and status='open'),'GRD-008 re-consent scan opens new case instead of reopening');
select ok(pg_temp.run('select to_jsonb(g) from public.record_staff_front_desk_check_in(pg_temp.u(103),''Holdout assisted'',pg_temp.u(550))g')->>'error' is null,'GRD-010 guardianless minor assisted attendance allowed');
select is((select count(*) from public.attendance where tenant_id=pg_temp.u(1) and member_id=pg_temp.u(103) and client_event_id=pg_temp.u(550)),1::bigint,'GRD-010 attendance persisted while scoring off');
select is(pg_temp.run('select to_jsonb(count(*)) from public.guardian_consents where tenant_id=pg_temp.u(1)',pg_temp.claims(5)),'0'::jsonb,'GRD-021 foreign front office cannot read real consent rows');
select is(pg_temp.run('select to_jsonb(count(*)) from public.guardian_consents',pg_temp.claims(4)),'0'::jsonb,'GRD-021 trainer cannot read populated consent table');

-- A guardian Google identity, plus an ordinary child identity, exercise D1 and routing.
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values
(pg_temp.u(601),'guardian@h69.test',now(),'{"provider":"google","providers":["google"]}'::jsonb),
(pg_temp.u(602),'child8@h69.test',now(),'{"provider":"google","providers":["google"]}'::jsonb);
insert into auth.identities(provider_id,user_id,identity_data,provider) values
('h69-google-601',pg_temp.u(601),'{"sub":"h69-google-601","email":"guardian@h69.test","email_verified":true}'::jsonb,'google'),
('h69-google-602',pg_temp.u(602),'{"sub":"h69-google-602","email":"child8@h69.test","email_verified":true}'::jsonb,'google');
select ok(pg_temp.run('select to_jsonb(g) from public.issue_member_invite(pg_temp.u(108),repeat(''c'',64))g')->>'invite_id' is not null,'GRD-014 issue complete minor invite');
select is(pg_temp.run('select to_jsonb(g) from public.peek_member_invite(repeat(''c'',64))g','','anon')->>'gym_name','GRD holdout A','GRD-015 anonymous peek only gym name');
select is(pg_temp.run('select to_jsonb(g) from public.redeem_member_invite(repeat(''c'',64))g',jsonb_build_object('sub',pg_temp.u(602),'role','authenticated')::text)->>'outcome','email_mismatch','GRD-015 own child account refuses guardian invite');
select is(pg_temp.run('select to_jsonb(g) from public.redeem_member_invite(repeat(''c'',64))g',jsonb_build_object('sub',pg_temp.u(601),'role','authenticated')::text)->>'outcome','linked','GRD-015 guardian Google binds child membership');
select ok((select user_id=pg_temp.u(601) and guardian_linked_at is not null from public.members where id=pg_temp.u(108)),'GRD-013 successful minor redemption marker');
-- Owner-approved marker-integrity regressions against the actual successful guardian redemption above.
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(3))->>'error',null::text,'GRD marker unchanged trusted value remains writable by real desk');
insert into auth.sessions(id,user_id)values(pg_temp.u(624),pg_temp.u(601));
create temp table h69_marker_real as select to_jsonb(m)facts from public.members m where id=pg_temp.u(108);
create temp table h69_marker_sessions as select to_jsonb(a)facts from auth.sessions a where user_id=pg_temp.u(601);
create temp table h69_marker_audit as select count(*)n from public.audit_log where tenant_id=pg_temp.u(1);
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'error','42501','GRD real guardian marker clear role 1 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker clear role 1 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'error','42501','GRD real guardian marker replace role 1 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker replace role 1 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'error','42501','GRD real guardian marker clear role 2 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker clear role 2 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'error','42501','GRD real guardian marker replace role 2 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker replace role 2 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'error','42501','GRD real guardian marker clear role 3 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker clear role 3 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'error','42501','GRD real guardian marker replace role 3 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'detail','guardian_binding_command_required','GRD real guardian marker replace role 3 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'error','42501','GRD service subject cannot clear marker refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'detail','guardian_binding_command_required','GRD service subject cannot clear marker exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'error','42501','GRD service subject cannot replace marker refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(108)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'detail','guardian_binding_command_required','GRD service subject cannot replace marker exact detail');
do $$begin perform set_config('app.guardian_binding_command','true',true);perform set_config('app.member_invite_verified','true',true);end$$;
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(),'authenticated')->>'error','42501','GRD forged transaction settings cannot clear provenance refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$,pg_temp.claims(),'authenticated')->>'detail','guardian_binding_command_required','GRD forged transaction settings cannot clear provenance exact detail');
do $$begin perform set_config('app.guardian_binding_command','',true);perform set_config('app.member_invite_verified','',true);end$$;
select is(pg_temp.run($q$update public.members set user_id=pg_temp.u(602),guardian_linked_at=null where id=pg_temp.u(108)returning to_jsonb(id)$q$)->>'error','GL074','GRD mixed user-marker change preserves INV refusal order');
select is((select to_jsonb(m)from public.members m where id=pg_temp.u(108)),(select facts from h69_marker_real),'GRD real guardian refusals preserve every member value');
select is((select coalesce(jsonb_agg(facts order by facts->>'id'),'[]')from h69_marker_sessions),(select coalesce(jsonb_agg(to_jsonb(a)order by a.id::text),'[]')from auth.sessions a where user_id=pg_temp.u(601)),'GRD real guardian refusals preserve session contents');
select is((select count(*)from public.audit_log where tenant_id=pg_temp.u(1)),(select n from h69_marker_audit),'GRD real guardian refusals write no audit');
select ok(pg_temp.run('select to_jsonb(g) from public.issue_member_invite(pg_temp.u(109),repeat(''d'',64))g')->>'invite_id' is not null,'GRD-016 sibling same guardian contact allowed');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(109))g')->>'link_email_in_use','true','GRD-016 collision boolean discloses no other member');
select is(pg_temp.run('select to_jsonb(g) from public.redeem_member_invite(repeat(''d'',64))g',jsonb_build_object('sub',pg_temp.u(601),'role','authenticated')::text)->>'outcome','account_already_linked','GRD-016 one account never binds sibling');
update public.members set guardian_phone=null where id=pg_temp.u(109);
select is(pg_temp.run('select to_jsonb(g) from public.peek_member_invite(repeat(''d'',64))g','','anon'),'null'::jsonb,'GRD-015 guardian removed after issue invalidates peek');
select is(pg_temp.run('select to_jsonb(g) from public.redeem_member_invite(repeat(''d'',64))g',jsonb_build_object('sub',pg_temp.u(602),'role','authenticated')::text)->>'outcome','invite_unavailable','GRD-015 removed guardian unavailable before email comparison');
insert into auth.sessions(id,user_id) values(pg_temp.u(620),pg_temp.u(601)),(pg_temp.u(621),pg_temp.u(602));
update public.members set date_of_birth=current_date-10000 where id=pg_temp.u(108);
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(108),current_date),'on_adult','GRD-011 adulthood automatically changes eligibility');
select is(app.member_contact_email(pg_temp.u(1),pg_temp.u(108)),'child8@h69.test','GRD-011 adulthood routes own address');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(108))g')->>'handover_due','true','GRD-019 guardian account remains until explicit handover');
select ok(pg_temp.run('select to_jsonb(public.transition_member_to_own_account(pg_temp.u(108),''  Now adult  ''))',pg_temp.claims(2))->>'error' is null,'GRD-012 manager hands over');
select ok((select user_id is null and guardian_linked_at is null and guardian_name='Guardian Secret' from public.members where id=pg_temp.u(108)),'GRD-012 binding clears while guardian profile retained');
select is((select count(*) from auth.sessions where user_id=pg_temp.u(601)),0::bigint,'GRD-012 former guardian sessions revoked');
select is((select count(*) from auth.sessions where user_id=pg_temp.u(602)),1::bigint,'GRD-012 unrelated child session retained');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='member.account_transitioned' and record_id=pg_temp.u(108) and actor_user_id=pg_temp.u(202) and actor_role='gym_manager' and reason='Now adult' and before='{"user_linked":true,"guardian_linked":true}'::jsonb and after='{"user_linked":false,"guardian_linked":false}'::jsonb),'GRD-020 handover exact audit attributed to manager');


-- Recipient snapshots must use the guardian resolver in both initial open and replay.
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source) values
(pg_temp.u(701),pg_temp.u(1),pg_temp.u(105),'service',true,'v1','holdout'),
(pg_temp.u(702),pg_temp.u(1),pg_temp.u(103),'service',true,'v1','holdout');
insert into public.notifications(id,tenant_id,member_id,channel,category,dedupe_key,payload) values
(pg_temp.u(711),pg_temp.u(1),pg_temp.u(105),'in_app','fulfilment','h69:guardian:source','{"body":"Service notice"}'::jsonb),
(pg_temp.u(712),pg_temp.u(1),pg_temp.u(103),'in_app','fulfilment','h69:incomplete:source','{"body":"Service notice"}'::jsonb);
select ok(pg_temp.run('select public.send_notification(pg_temp.u(711))')->>'error' is null,'GRD-027 ordinary in-app lifecycle');
select ok(pg_temp.run('select public.send_notification(pg_temp.u(712))')->>'error' is null,'GRD-010 absence gate does not suppress in-app service');
select matches(pg_temp.run('select public.open_notification_whatsapp(pg_temp.u(711))')->>'url','^https://wa[.]me/919699111111[?]','GRD-017 WhatsApp URL uses guardian phone');
select is((select recipient_phone from public.notifications where source_notification_id=pg_temp.u(711)),'+919699111111','GRD-017 guardian snapshot retained');
select is(pg_temp.run('select public.open_notification_whatsapp(pg_temp.u(712))')->>'communicationOptedOut','true','GRD-017 missing guardian phone returns opted out');
select is((select count(*) from public.notifications where source_notification_id=pg_temp.u(712)),0::bigint,'GRD-017 no child row or fallback recipient');
update public.members set guardian_phone='+919699333333' where id=pg_temp.u(105);
select is(pg_temp.run('select public.open_notification_whatsapp(pg_temp.u(711))')->>'error','GL066','GRD-017 guardian snapshot mismatch replay refuses');
select ok(pg_temp.run($q$update public.notifications set recipient_phone='+919699000005' where source_notification_id=pg_temp.u(711) returning to_jsonb(id)$q$)->>'error' is not null,'GRD-017 direct child contact cannot bypass guardian resolver');

select is(pg_temp.run($q$update public.organization_settings set members_without_dob_attested_adult_at=null where tenant_id=pg_temp.u(1) returning to_jsonb(tenant_id)$q$,'','postgres')->>'error','22023','GRD-002 trusted write cannot reset attestation');
select is(pg_temp.run($q$update public.organization_settings set members_without_dob_attested_adult_at=members_without_dob_attested_adult_at+interval '1 microsecond' where tenant_id=pg_temp.u(1) returning to_jsonb(tenant_id)$q$,'','postgres')->>'error','22023','GRD-002 trusted write cannot move cutoff');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and relation='public.organization_settings'::regclass and mode='RowShareLock' and granted),'GRD-002 attestation acquired FOR UPDATE relation lock');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and relation='public.members'::regclass and mode='RowShareLock' and granted),'GRD-006/012 member commands acquired FOR UPDATE relation lock');
select ok(not has_function_privilege('authenticated','app.close_ineligible_cases(uuid,uuid,text)','EXECUTE') and not has_function_privilege('service_role','app.close_ineligible_cases(uuid,uuid,text)','EXECUTE'),'GRD-021 close helper not exposed');
select ok(not has_function_privilege('authenticated','app.guardian_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)','EXECUTE') and not has_function_privilege('service_role','app.guardian_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)','EXECUTE'),'GRD-021 audit helper not exposed');
select is(pg_temp.run($q$select to_jsonb(app.guardian_audit(pg_temp.u(1),null,null,'not.allowlisted','member',pg_temp.u(101),null,null,null))$q$,'','postgres')->>'error','22023','GRD-020 audit action allowlist');
select is(pg_temp.run($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.u(1),pg_temp.u(105),true,'v1','direct','spoof','mother',pg_temp.u(201)) returning to_jsonb(id)$q$)->>'error','42501','GRD-006 direct consent cannot spoof snapshot');
select is(pg_temp.run($q$update public.guardian_consents set granted=true where member_id=pg_temp.u(104) returning to_jsonb(id)$q$)->>'error','42501','GRD-006 direct UPDATE denied');
select is(pg_temp.run($q$delete from public.guardian_consents where member_id=pg_temp.u(104) returning to_jsonb(id)$q$)->>'error','42501','GRD-006 direct DELETE denied');
select lives_ok($q$do $$declare a public.members;b public.members;n bigint;v jsonb;begin
 select * into a from public.members where id=pg_temp.u(105);
 select count(*) into n from public.audit_log where tenant_id=pg_temp.u(1);
 v:=pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,''  Guardian Secret  '',''mother'','' +919699333333 '','' guardian@h69.test ''))');
 if v ? 'error' then raise exception 'trimmed profile refused: %',v;end if;
 select * into b from public.members where id=pg_temp.u(105);
 if b.updated_at<>a.updated_at or b.user_id is distinct from a.user_id or b.status<>a.status then raise exception 'no-op changed unrelated facts';end if;
 if (select count(*) from public.audit_log where tenant_id=pg_temp.u(1))<>n then raise exception 'no-op audited';end if;
end $$;$q$,'GRD-005 trimmed exact profile replay writes nothing');
select ok(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'tracked' is not null,'GRD-019 coverage readable for front office');
select ok(not exists(select 1 from jsonb_array_elements(coalesce(pg_temp.run($q$select coalesce(jsonb_agg(to_jsonb(g)),'[]'::jsonb) from public.list_guardian_attention('no_birth_date')g$q$),'[]'::jsonb))g where g->>'member_id'=pg_temp.u(110)::text),'GRD-019 legacy attested missing DOB omitted from attention');
select is(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(101))g',pg_temp.claims(4))->>'error','42501','GRD-019 trainer reader forbidden');
select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g',pg_temp.claims(4))->>'error','42501','GRD-019 trainer coverage forbidden');
select is(pg_temp.run($q$select to_jsonb(g) from public.list_guardian_attention('no_birth_date')g$q$,pg_temp.claims(4))->>'error','42501','GRD-019 trainer attention forbidden');
select ok(pg_temp.run('select to_jsonb(g) from public.read_member_guardian(pg_temp.u(101))g',(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'age_state'='adult','GRD-019 preview retains read-only access');


select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'tracked','4','GRD-019 exact tracked live cohort');
select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'no_birth_date','0','GRD-019 excludes cutoff cohort and no-membership unknown');
select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'minor_no_guardian','4','GRD-019 exact incomplete-minor count');
select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'minor_consent_missing','2','GRD-019 withdrawn and none counted once');
select is(pg_temp.run('select to_jsonb(g) from public.read_guardian_coverage()g')->>'handover_due','0','GRD-019 handed-over account leaves no due count');
select is(pg_temp.run($q$select to_jsonb(count(*)) from public.list_guardian_attention('minor_no_guardian')g$q$),'4'::jsonb,'GRD-019 attention count equals coverage');
select is(pg_temp.run($q$select to_jsonb(count(*)) from public.list_guardian_attention('minor_consent_missing')g$q$),'2'::jsonb,'GRD-019 consent attention count equals coverage');

-- No audit payload may retain the deliberately distinctive personal fixture values.
select ok(not exists(select 1 from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2),pg_temp.u(3))
 and action in('member.age_changed','member.guardian_changed','member.scoring_stopped','guardian_consent.granted','guardian_consent.withdrawn','member.account_transitioned','organization.members_without_dob_attested_adult')
 and (coalesce(before::text,'')||coalesce(after::text,''))~'Guardian Secret|Different Guardian|Another Guardian|699111111|699222222|@h69|paper secret'),'GRD-020 no personal values in guardian audit');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='guardian_consent.granted' and
 (after is null or jsonb_typeof(after)<>'object' or not(after ?& array['member_id','version']) or after-array['member_id','version']<>'{}'::jsonb or before is null or jsonb_typeof(before)<>'object' or not(before ? 'standing') or before-'standing'<>'{}'::jsonb)),'GRD-020 exact consent audit projection');

select ok(has_function_privilege('authenticated','public.attest_members_without_dob_adult()','EXECUTE') and not has_function_privilege('anon','public.attest_members_without_dob_adult()','EXECUTE') and not has_function_privilege('service_role','public.attest_members_without_dob_adult()','EXECUTE'),'GRD-021 exact public audience attest_members_without_dob_adult');
select ok(has_function_privilege('authenticated','public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text)','EXECUTE') and not has_function_privilege('anon','public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text)','EXECUTE') and not has_function_privilege('service_role','public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text)','EXECUTE'),'GRD-021 exact public audience set_member_age_guardian');
select ok(has_function_privilege('authenticated','public.record_guardian_consent(uuid,boolean,text,text)','EXECUTE') and not has_function_privilege('anon','public.record_guardian_consent(uuid,boolean,text,text)','EXECUTE') and not has_function_privilege('service_role','public.record_guardian_consent(uuid,boolean,text,text)','EXECUTE'),'GRD-021 exact public audience record_guardian_consent');
select ok(has_function_privilege('authenticated','public.transition_member_to_own_account(uuid,text)','EXECUTE') and not has_function_privilege('anon','public.transition_member_to_own_account(uuid,text)','EXECUTE') and not has_function_privilege('service_role','public.transition_member_to_own_account(uuid,text)','EXECUTE'),'GRD-021 exact public audience transition_member_to_own_account');
select ok(has_function_privilege('authenticated','public.read_member_guardian(uuid)','EXECUTE') and not has_function_privilege('anon','public.read_member_guardian(uuid)','EXECUTE') and not has_function_privilege('service_role','public.read_member_guardian(uuid)','EXECUTE'),'GRD-021 exact public audience read_member_guardian');
select ok(has_function_privilege('authenticated','public.read_guardian_coverage()','EXECUTE') and not has_function_privilege('anon','public.read_guardian_coverage()','EXECUTE') and not has_function_privilege('service_role','public.read_guardian_coverage()','EXECUTE'),'GRD-021 exact public audience read_guardian_coverage');
select ok(has_function_privilege('authenticated','public.list_guardian_attention(text)','EXECUTE') and not has_function_privilege('anon','public.list_guardian_attention(text)','EXECUTE') and not has_function_privilege('service_role','public.list_guardian_attention(text)','EXECUTE'),'GRD-021 exact public audience list_guardian_attention');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,pg_temp.claims(4))->>'error','42501','GRD actors trainer: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,pg_temp.claims(4))->>'error','42501','GRD actors trainer: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,pg_temp.claims(4))->>'error','42501','GRD actors trainer: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,pg_temp.claims(4))->>'error','42501','GRD actors trainer: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,pg_temp.claims(6))->>'error','42501','GRD actors inactive: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,pg_temp.claims(6))->>'error','42501','GRD actors inactive: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,pg_temp.claims(6))->>'error','42501','GRD actors inactive: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,pg_temp.claims(6))->>'error','42501','GRD actors inactive: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(207)))::text)->>'error','42501','GRD actors wrong subject: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(207)))::text)->>'error','42501','GRD actors wrong subject: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(207)))::text)->>'error','42501','GRD actors wrong subject: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('sub',pg_temp.u(207)))::text)->>'error','42501','GRD actors wrong subject: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','GRD actors wrong tenant: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','GRD actors wrong tenant: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','GRD actors wrong tenant: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','GRD actors wrong tenant: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,(pg_temp.claims()::jsonb-'staff_id')::text)->>'error','42501','GRD actors missing staff: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,(pg_temp.claims()::jsonb-'staff_id')::text)->>'error','42501','GRD actors missing staff: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,(pg_temp.claims()::jsonb-'staff_id')::text)->>'error','42501','GRD actors missing staff: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,(pg_temp.claims()::jsonb-'staff_id')::text)->>'error','42501','GRD actors missing staff: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('member_id',pg_temp.u(105)))::text)->>'error','42501','GRD actors member contamination: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('member_id',pg_temp.u(105)))::text)->>'error','42501','GRD actors member contamination: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('member_id',pg_temp.u(105)))::text)->>'error','42501','GRD actors member contamination: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('member_id',pg_temp.u(105)))::text)->>'error','42501','GRD actors member contamination: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','GRD actors preview: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','GRD actors preview: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','GRD actors preview: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','GRD actors preview: handover refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(201))::text)->>'error','42501','GRD actors claim only owner: attest refused');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(201))::text)->>'error','42501','GRD actors claim only owner: consent refused');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(201))::text)->>'error','42501','GRD actors claim only owner: profile refused');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(201))::text)->>'error','42501','GRD actors claim only owner: handover refused');
select is(pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult()g',pg_temp.claims(2))->>'error','42501','GRD-002 role 2 cannot attest');
select is(pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult()g',pg_temp.claims(3))->>'error','42501','GRD-002 role 3 cannot attest');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(101),'valid reason'))$q$,pg_temp.claims(3))->>'error','42501','GRD-012 desk cannot hand over');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,'','anon')->>'error','42501','GRD-021 anon denied attest');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,'','service_role')->>'error','42501','GRD-021 service_role denied attest');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,'','anon')->>'error','42501','GRD-021 anon denied consent');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,'','service_role')->>'error','42501','GRD-021 service_role denied consent');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,'','anon')->>'error','42501','GRD-021 anon denied profile');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,'Guardian Secret','mother','+919699111111','guardian@h69.test'))$q$,'','service_role')->>'error','42501','GRD-021 service_role denied profile');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,'','anon')->>'error','42501','GRD-021 anon denied handover');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,'','service_role')->>'error','42501','GRD-021 service_role denied handover');
select is(pg_temp.run($q$update public.organization_settings set members_without_dob_attested_adult_at=clock_timestamp() where tenant_id=pg_temp.u(2) returning to_jsonb(tenant_id)$q$,'','service_role')->>'error','42501','GRD-002 direct service_role timestamp refused');
select is(pg_temp.run($q$insert into public.organization_settings(tenant_id,members_without_dob_attested_adult_at) values(pg_temp.u(3),clock_timestamp()) returning to_jsonb(tenant_id)$q$,'','service_role')->>'error','42501','GRD-002 service INSERT cannot forge timestamp');

insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.u(207),'super_admin','Holdout platform','platform@h69.test',true);
update public.members set user_id=pg_temp.u(602) where id=pg_temp.u(101);
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses attest');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses consent');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,null,null,null,null))$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses profile');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses handover');
select is(pg_temp.run($q$select to_jsonb(g) from public.read_member_guardian(pg_temp.u(105))g$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses reader');
select is(pg_temp.run($q$select to_jsonb(g) from public.read_guardian_coverage()g$q$,jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text)->>'error','42501','GRD actors member refuses coverage');
select is(pg_temp.run($q$select to_jsonb(g) from public.attest_members_without_dob_adult()g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses attest');
select is(pg_temp.run($q$select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,'v1','paper')g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses consent');
select is(pg_temp.run($q$select to_jsonb(public.set_member_age_guardian(pg_temp.u(105),current_date-3650,null,null,null,null))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses profile');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(105),'valid reason'))$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses handover');
select is(pg_temp.run($q$select to_jsonb(g) from public.read_member_guardian(pg_temp.u(105))g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses reader');
select is(pg_temp.run($q$select to_jsonb(g) from public.read_guardian_coverage()g$q$,jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text)->>'error','42501','GRD actors platform refuses coverage');
select is(pg_temp.run('select to_jsonb(count(*)) from public.guardian_consents',jsonb_build_object('sub',pg_temp.u(602),'role','authenticated','app_role','member','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(101))::text),'0'::jsonb,'GRD-021 member cannot read guardian consent history');
select is(pg_temp.run($q$update public.members set guardian_linked_at=clock_timestamp() where id=pg_temp.u(103) returning to_jsonb(id)$q$,'','postgres')->>'constraint','members_guardian_linked_state_chk','GRD-013 marker requires binding');
select is(pg_temp.run($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.u(1),pg_temp.u(120),true,'v1','fixture','Guardian','mother',pg_temp.u(201)) returning to_jsonb(id)$q$,'','postgres')->>'error','23503','GRD-021 cross-tenant member FK');
select is(pg_temp.run($q$insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_by_staff_id) values(pg_temp.u(1),pg_temp.u(105),true,'v1','fixture','Guardian','mother',pg_temp.u(205)) returning to_jsonb(id)$q$,'','postgres')->>'error','23503','GRD-021 cross-tenant staff FK');
select is(pg_temp.run($q$update public.members set user_id=pg_temp.u(602) where id=pg_temp.u(108) returning to_jsonb(id)$q$)->>'error','GL074','GRD-027 direct binding guard unchanged');
select is(pg_temp.run($q$update public.members set user_id=pg_temp.u(601),guardian_linked_at=clock_timestamp() where id=pg_temp.u(108) returning to_jsonb(id)$q$,'','postgres')->>'error',null::text,'GRD-013 trusted simultaneous binding and marker allowed');
-- The member-role refusal fixture has finished; release its account before
-- reusing that same real identity for the trusted marker-clearing rebind.
update public.members set user_id=null where id=pg_temp.u(101);
update public.members set user_id=pg_temp.u(602) where id=pg_temp.u(108);
select is((select guardian_linked_at from public.members where id=pg_temp.u(108)),null::timestamptz,'GRD-013 changing only user clears stale guardian marker');


update public.members set date_of_birth=((current_date+1)-interval '18 years')::date where id=pg_temp.u(102);
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(102),current_date),'off_no_guardian','GRD-001 eve of birthday minor');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(102),current_date+1),'on_adult','GRD-001 birthday gate inclusive');
select lives_ok($q$select app.run_no_show_scan(pg_temp.u(1),current_date+1)$q$,'GRD-008 scan evaluation date controls birthday');
select ok(exists(select 1 from public.no_show_cases where tenant_id=pg_temp.u(1) and member_id=pg_temp.u(102) and status='open'),'GRD-008 future test hook opens newly adult');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='member.age_changed' and (before is null or jsonb_typeof(before)<>'object' or not(before ?& array['dob_known','minor']) or before-array['dob_known','minor']<>'{}'::jsonb or after is null or jsonb_typeof(after)<>'object' or not(after ?& array['dob_known','minor']) or after-array['dob_known','minor']<>'{}'::jsonb)),'GRD-020 age audit excludes date facts');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='member.guardian_changed' and ((before-array['guardian_present','relation','complete','phone_present','email_present'])<>'{}'::jsonb or (after-array['guardian_present','relation','complete','phone_present','email_present'])<>'{}'::jsonb)),'GRD-020 guardian audit exact nonpersonal keys');


select is(pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult()g')->>'members_without_dob_attested_adult_at',(select to_jsonb(members_without_dob_attested_adult_at)#>>'{}' from public.organization_settings where tenant_id=pg_temp.u(1)),'GRD-002 replay returns stored immutable cutoff');
select lives_ok($q$do $$declare n bigint; t timestamptz;begin
 select count(*) into n from public.audit_log where tenant_id=pg_temp.u(1);
 select members_without_dob_attested_adult_at into t from public.organization_settings where tenant_id=pg_temp.u(1);
 perform pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult()g');
 perform pg_temp.run('select to_jsonb(g) from public.attest_members_without_dob_adult()g');
 if (select count(*) from public.audit_log where tenant_id=pg_temp.u(1))<>n or
 (select members_without_dob_attested_adult_at from public.organization_settings where tenant_id=pg_temp.u(1))<>t then raise exception 'attestation replay writes';end if;
end $$;$q$,'GRD-002 repeated attestation has no write/audit effect');
select is(pg_temp.run($q$update public.members set guardian_relation='father' where id=pg_temp.u(105) returning to_jsonb(id)$q$)->>'error',null::text,'GRD-004 direct front-office guardian edit allowed and guarded');
select is(app.member_scoring_state(pg_temp.u(1),pg_temp.u(105),current_date),'off_consent_stale','GRD-003 relation change invalidates granted snapshot');
select is(pg_temp.run('select to_jsonb(g) from public.record_guardian_consent(pg_temp.u(105),true,''v1'',''updated relation'')g',pg_temp.claims(3))->>'changed','true','GRD-006 real desk can re-consent changed relation');
select is((select recorded_by_staff_id from public.guardian_consents where member_id=pg_temp.u(105) order by recorded_at desc,id desc limit 1),pg_temp.u(203),'GRD-006 desk attribution copied from identity');
select lives_ok($q$do $$declare n bigint; before_row public.members; after_row public.members; v jsonb;begin
 select * into before_row from public.members where id=pg_temp.u(108);
 update public.members set user_id=pg_temp.u(601),guardian_linked_at=clock_timestamp() where id=pg_temp.u(108);
 select guardian_linked_at into before_row.guardian_linked_at from public.members where id=pg_temp.u(108);
 v:=pg_temp.run('select to_jsonb(public.set_member_age_guardian(pg_temp.u(108),current_date-10000,null,null,null,null))');
 if v ? 'error' then raise exception 'clear refused';end if;
 select * into after_row from public.members where id=pg_temp.u(108);
 if after_row.guardian_name is not null or after_row.guardian_relation is not null or after_row.guardian_phone is not null or after_row.guardian_email is not null then raise exception 'guardian not cleared';end if;
 if after_row.guardian_linked_at is distinct from before_row.guardian_linked_at or after_row.user_id<>pg_temp.u(601) then raise exception 'profile clear touched binding';end if;
end $$;$q$,'GRD-005 clearing guardian retains linked marker/account');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and action='organization.members_without_dob_attested_adult' and (actor_user_id is distinct from pg_temp.u(201) or actor_role is distinct from 'gym_owner'::public.app_role or record_type<>'organization_settings' or record_id<>pg_temp.u(1) or reason is not null or before<>'{"members_without_dob_attested_adult_at":null}'::jsonb or (after-array['members_without_dob_attested_adult_at'])<>'{}'::jsonb)),'GRD-020 attestation exact attribution and shape');

-- Final marker shape, ordinary-account provenance, INSERT integrity, and trusted clearing boundaries.
create temp table h69_marker_trigger as select t.* from pg_trigger t where t.tgrelid='public.members'::regclass and t.tgname='members_guardian_marker';
select is((select tgtype::integer from h69_marker_trigger),23,'GRD marker trigger BEFORE INSERT OR UPDATE ROW');
select is((select tgqual::text from h69_marker_trigger),null::text,'GRD marker trigger has no WHEN clause');
select is((select array_agg(a.attname::text order by x.ord)from h69_marker_trigger t cross join lateral unnest(t.tgattr::smallint[])with ordinality x(num,ord)join pg_attribute a on a.attrelid=t.tgrelid and a.attnum=x.num),array['user_id','guardian_linked_at']::text[],'GRD marker UPDATE columns exact');
select ok((select not p.prosecdef and p.proowner='postgres'::regrole and 'search_path=""'=any(p.proconfig)and not has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')from pg_proc p where p.oid=(select tgfoid from h69_marker_trigger)),'GRD marker private invoker posture');
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)values(pg_temp.u(603),'adult-own@h69.test',now(),'{"provider":"google","providers":["google"]}'::jsonb);
insert into auth.identities(provider_id,user_id,identity_data,provider)values('h69-google-603',pg_temp.u(603),'{"sub":"h69-google-603","email":"adult-own@h69.test","email_verified":true}'::jsonb,'google');
insert into auth.users(id)select pg_temp.u(n)from generate_series(604,609)n;
insert into public.members(id,tenant_id,branch_id,full_name,phone,email,date_of_birth)values(pg_temp.u(144),pg_temp.u(1),pg_temp.u(11),'Own adult marker probe','+919699991140','adult-own@h69.test',date '1990-01-01');
select is(pg_temp.run($q$select to_jsonb(g)from public.issue_member_invite(pg_temp.u(144),repeat('e',64))g$q$)->>'error',null::text,'GRD ordinary adult invite remains allowed');
select is(pg_temp.run($q$select to_jsonb(g)from public.redeem_member_invite(repeat('e',64))g$q$,jsonb_build_object('sub',pg_temp.u(603),'role','authenticated')::text)->>'outcome','linked','GRD ordinary adult redemption byte-identical linked outcome');
select is((select guardian_linked_at from public.members where id=pg_temp.u(144)),null::timestamptz,'GRD ordinary adult redemption never stamps guardian provenance');
insert into auth.sessions(id,user_id)values(pg_temp.u(625),pg_temp.u(603));
create temp table h69_marker_adult as select to_jsonb(m)facts from public.members m where id=pg_temp.u(144);
create temp table h69_marker_adult_sessions as select to_jsonb(a)facts from auth.sessions a where user_id=pg_temp.u(603);
create temp table h69_marker_adult_audit as select count(*)n from public.audit_log where tenant_id=pg_temp.u(1);
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'error','42501','GRD adult own-account provenance forgery role 1 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(1),'authenticated')->>'detail','guardian_binding_command_required','GRD adult own-account provenance forgery role 1 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'error','42501','GRD adult own-account provenance forgery role 2 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(2),'authenticated')->>'detail','guardian_binding_command_required','GRD adult own-account provenance forgery role 2 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'error','42501','GRD adult own-account provenance forgery role 3 refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,pg_temp.claims(3),'authenticated')->>'detail','guardian_binding_command_required','GRD adult own-account provenance forgery role 3 exact detail');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'error','42501','GRD adult provenance service subject forgery refuses');
select is(pg_temp.run($q$update public.members set guardian_linked_at=statement_timestamp()where id=pg_temp.u(144)returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'detail','guardian_binding_command_required','GRD adult provenance service subject forgery exact detail');
select is(pg_temp.run($q$select to_jsonb(public.transition_member_to_own_account(pg_temp.u(144),'Own account stays'))$q$)->>'error','GL085','GRD rejected forgery cannot authorize adult own-account handover');
select is((select to_jsonb(m)from public.members m where id=pg_temp.u(144)),(select facts from h69_marker_adult),'GRD adult forgery refusals preserve all values');
select is((select coalesce(jsonb_agg(to_jsonb(a)order by a.id::text),'[]')from auth.sessions a where user_id=pg_temp.u(603)),(select coalesce(jsonb_agg(facts order by facts->>'id'),'[]')from h69_marker_adult_sessions),'GRD adult forgery preserves own-account sessions');
select is((select count(*)from public.audit_log where tenant_id=pg_temp.u(1)),(select n from h69_marker_adult_audit),'GRD adult forgery and handover refusals write no audit');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at)values(pg_temp.u(141),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991141',statement_timestamp())returning to_jsonb(id)$q$,pg_temp.claims(),'authenticated')->>'error','42501','GRD unbound nonnull marker INSERT command required refuses');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at)values(pg_temp.u(141),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991141',statement_timestamp())returning to_jsonb(id)$q$,pg_temp.claims(),'authenticated')->>'detail','guardian_binding_command_required','GRD unbound nonnull marker INSERT command required exact detail');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at)values(pg_temp.u(141),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991141',statement_timestamp())returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'error','42501','GRD service subject nonnull marker INSERT refuses');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at)values(pg_temp.u(141),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991141',statement_timestamp())returning to_jsonb(id)$q$,jsonb_build_object('sub',pg_temp.u(201),'role','service_role')::text,'service_role')->>'detail','guardian_binding_command_required','GRD service subject nonnull marker INSERT exact detail');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,guardian_linked_at)values(pg_temp.u(141),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991141',null)returning to_jsonb(id)$q$)->>'error',null::text,'GRD null-marker INSERT remains permitted by owner RLS');
select is(pg_temp.run($q$update public.members set guardian_linked_at=null where id=pg_temp.u(141)returning to_jsonb(id)$q$)->>'error',null::text,'GRD unchanged null marker update remains allowed');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,user_id,guardian_linked_at)values(pg_temp.u(142),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991142',pg_temp.u(604),statement_timestamp())returning to_jsonb(id)$q$)->>'error','GL074','GRD mixed bound INSERT preserves original INV precedence');
select is((select count(*)from public.members where id=pg_temp.u(142)),0::bigint,'GRD refused mixed INSERT leaves no member row');
select is(pg_temp.run($q$insert into public.members(id,tenant_id,branch_id,full_name,phone,user_id,guardian_linked_at)values(pg_temp.u(142),pg_temp.u(1),pg_temp.u(11),'Insert marker probe','+919699991142',pg_temp.u(604),statement_timestamp())returning to_jsonb(id)$q$,'','service_role')->>'error',null::text,'GRD subjectless service retains trusted INSERT boundary');
select is(pg_temp.run($q$update public.members set guardian_linked_at=guardian_linked_at+interval '1 second'where id=pg_temp.u(142)returning to_jsonb(id)$q$,'','service_role')->>'error',null::text,'GRD subjectless service retains trusted marker update boundary');
select is(pg_temp.run($q$update public.members set user_id=pg_temp.u(605),guardian_linked_at=guardian_linked_at where id=pg_temp.u(142)returning to_jsonb(id)$q$,'','service_role')->>'error',null::text,'GRD operator rebind explicitly assigns unchanged marker');
select is((select guardian_linked_at from public.members where id=pg_temp.u(142)),null::timestamptz,'GRD operator rebind compares values and clears unchanged old timestamp');
update public.members set user_id=pg_temp.u(606),guardian_linked_at=statement_timestamp()where id=pg_temp.u(142);
select is(pg_temp.run($q$select to_jsonb(public.unlink_member_identity(pg_temp.u(142),'Verified unlink'))$q$)->>'error',null::text,'GRD legitimate INV unlink remains permitted');
select ok((select user_id is null and guardian_linked_at is null from public.members where id=pg_temp.u(142)),'GRD INV unlink clears both binding and marker');
update public.members set user_id=pg_temp.u(607),guardian_linked_at=statement_timestamp()where id=pg_temp.u(142);update public.members set user_id=pg_temp.u(608),guardian_linked_at=guardian_linked_at where id=pg_temp.u(142);
select is((select guardian_linked_at from public.members where id=pg_temp.u(142)),null::timestamptz,'GRD postgres rebind clears explicitly unchanged marker value');

-- Unknown-age redemption also remains ordinary, with no invented guardian provenance.
update auth.users set email='unknown-own@h69.test',email_confirmed_at=now(),raw_app_meta_data='{"provider":"google","providers":["google"]}'::jsonb where id=pg_temp.u(609);
insert into auth.identities(provider_id,user_id,identity_data,provider)values('h69-google-609',pg_temp.u(609),'{"sub":"h69-google-609","email":"unknown-own@h69.test","email_verified":true}'::jsonb,'google');
insert into public.members(id,tenant_id,branch_id,full_name,phone,email)values(pg_temp.u(143),pg_temp.u(1),pg_temp.u(11),'Unknown-age own account','+919699991143','unknown-own@h69.test');
select is(pg_temp.run($q$select to_jsonb(g)from public.issue_member_invite(pg_temp.u(143),repeat('f',64))g$q$)->>'error',null::text,'GRD unknown-age ordinary invite remains allowed');
select is(pg_temp.run($q$select to_jsonb(g)from public.redeem_member_invite(repeat('f',64))g$q$,jsonb_build_object('sub',pg_temp.u(609),'role','authenticated')::text)->>'outcome','linked','GRD unknown-age ordinary redemption linked outcome retained');
select is((select guardian_linked_at from public.members where id=pg_temp.u(143)),null::timestamptz,'GRD unknown-age ordinary redemption stamps null marker');

select * from finish();
rollback;
