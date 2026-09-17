-- Phase 6 platform control: public command seams, capability boundaries and
-- durable evidence.  Written from phase6-platform-contract.md before its
-- implementation; this file deliberately does not name implementation helpers
-- other than the contractually named graph/default/TTL helpers.
begin;
set local role postgres;
set local search_path = extensions, public;
select plan(33);

select has_enum('public','plan_tier','OPS-005: plan tier is a generated Postgres enum');
select enum_has_labels('public','plan_tier',array['basic','growth','pro']::name[],
  'OPS-005: the only manual commercial labels are basic, growth and pro');
select col_type_is('public','organizations','tier','plan_tier',
  'OPS-005: organizations.tier uses the canonical enum, not free text');

select has_column('public','audit_log','request_key','platform commands retain their request key');
select col_type_is('public','audit_log','request_key','uuid','audit request key is UUID');
select col_is_null('public','audit_log','request_key','historic audit rows retain a null request key');
select has_column('public','audit_log','request_facts','platform audit evidence records normalized facts');
select col_type_is('public','audit_log','request_facts','jsonb','audit request facts are JSON evidence');
select col_is_null('public','audit_log','request_facts','historic audit rows retain null facts');
select ok((select exists (
  select 1 from pg_constraint c where c.conrelid='public.audit_log'::regclass
    and pg_get_constraintdef(c.oid) like '%request_key%' and pg_get_constraintdef(c.oid) like '%request_facts%')),
  'request key and facts are coupled by a database constraint');
select ok((select exists (
  select 1 from pg_index i join pg_class x on x.oid=i.indexrelid
   where i.indrelid='public.audit_log'::regclass and i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%(tenant_id, request_key)%'
     and pg_get_expr(i.indpred,i.indrelid) = '(request_key IS NOT NULL)')),
  'platform request keys are tenant-scoped unique audit evidence');

select has_function('public','onboard_gym',array['uuid','text','text','text','gym_preset','text','text','text']::name[],
  'ONB-001: exact onboard command exists');
select has_function('public','set_gym_status',array['uuid','organization_status','organization_status','text','uuid']::name[],
  'OPS-002: exact status command exists');
select has_function('public','set_gym_tier',array['uuid','plan_tier','plan_tier','uuid']::name[],
  'ONB-005: exact tier command exists');
select has_function('public','link_gym_owner',array['uuid','uuid','uuid','text','uuid']::name[],
  'ONB-004: exact owner-link command exists');
select has_function('public','start_gym_preview',array['uuid','text','uuid']::name[],
  'OPS-003: exact preview-start command exists');
select has_function('public','end_expired_gym_preview',array['uuid']::name[],
  'OPS-003: exact expired-preview recovery command exists');
select has_function('app','organization_transition_allowed',array['organization_status','organization_status']::name[],
  'OPS-002: lifecycle graph has one named helper');
select has_function('app','platform_onboarding_defaults',array[]::name[],
  'ONB-003: generated onboarding defaults helper exists');
select has_function('app','impersonation_max_ttl',array[]::name[],
  'OPS-003: one private TTL helper supplies preview duration');

select ok((select count(*)=4 and bool_and(p.prosecdef and p.provolatile='v'
  and p.proconfig @> array['search_path=""'] and pg_get_userbyid(p.proowner)='postgres'
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not has_function_privilege('public',p.oid,'EXECUTE'))
 from pg_proc p where p.oid in (
   to_regprocedure('public.onboard_gym(uuid,text,text,text,public.gym_preset,text,text,text)'),
   to_regprocedure('public.set_gym_status(uuid,public.organization_status,public.organization_status,text,uuid)'),
   to_regprocedure('public.set_gym_tier(uuid,public.plan_tier,public.plan_tier,uuid)'),
   to_regprocedure('public.link_gym_owner(uuid,uuid,uuid,text,uuid)'))),
 'platform commercial commands are postgres-owned empty-path authenticated-only definers');
select ok((select count(*)=2 and bool_and(not p.prosecdef and p.provolatile='v'
  and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE'))
 from pg_proc p where p.oid in (
   to_regprocedure('public.start_gym_preview(uuid,text,uuid)'),
   to_regprocedure('public.end_expired_gym_preview(uuid)'))),
 'preview commands are authenticated-only volatile invokers');
select ok((select p.provolatile='i' and not p.prosecdef and p.proconfig @> array['search_path=""']
  and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')
 from pg_proc p where p.oid=to_regprocedure('app.organization_transition_allowed(public.organization_status,public.organization_status)')),
 'transition graph is an immutable invoker helper available to authenticated callers');
select ok((select p.provolatile='i' and not p.prosecdef and p.proconfig @> array['search_path=""']
  and has_function_privilege('postgres',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')
 from pg_proc p where p.oid=to_regprocedure('app.platform_onboarding_defaults()')),
 'onboarding defaults are private owner-only immutable invoker data');
select ok((select p.provolatile='i' and not p.prosecdef and p.proconfig @> array['search_path=""']
  and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')
 from pg_proc p where p.oid=to_regprocedure('app.impersonation_max_ttl()')),
 'preview TTL is private and cannot be caller-selected');

select ok((select app.organization_transition_allowed('pending_approval','trial')
  and app.organization_transition_allowed('pending_approval','active')
  and app.organization_transition_allowed('trial','active')
  and app.organization_transition_allowed('trial','closed')
  and app.organization_transition_allowed('active','suspended')
  and app.organization_transition_allowed('active','closed')
  and app.organization_transition_allowed('suspended','active')
  and app.organization_transition_allowed('suspended','closed')
  and app.organization_transition_allowed('closed','closed')),
  'OPS-002: every canonical allowed lifecycle edge, including same-state, is accepted');
select ok((select not app.organization_transition_allowed('trial','suspended')
  and not app.organization_transition_allowed('closed','active')
  and not app.organization_transition_allowed('pending_approval','suspended')),
  'OPS-002: convenience lifecycle edges are refused by the single graph');
select is((select app.platform_onboarding_defaults()),
  '{"trialDays":14,"gymCodeLength":6,"presets":{"functional_box":{"streakRule":"weekly_goal","weeklyGoal":4,"maxFreezeDays":14,"pauseApproverRole":"gym_owner","noShowThresholdDays":3},"neighbourhood_gym":{"streakRule":"visit_streak","weeklyGoal":3,"maxFreezeDays":30,"pauseApproverRole":"gym_owner","noShowThresholdDays":7},"premium_studio":{"streakRule":"weekly_goal","weeklyGoal":3,"maxFreezeDays":30,"pauseApproverRole":"gym_owner","noShowThresholdDays":5}}}'::jsonb,
  'ONB-003: generated defaults have the exact adopted preset payload');

select ok((select exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='public.organizations'::regclass and not t.tgisinternal
    and p.pronamespace='app'::regnamespace and p.proname='enforce_organization_commercial')),
  'NAV-008: organization commercial direct-write guard is installed');
select ok((select exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='public.staff'::regclass and not t.tgisinternal
    and p.pronamespace='app'::regnamespace and p.proname='enforce_staff_auth_binding')),
  'ONB-004: staff Auth-association direct-write guard is installed');
select ok((select exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='public.organizations'::regclass and not t.tgisinternal
    and p.pronamespace='app'::regnamespace and p.proname like '%revoke%session%')),
  'NAV-006: status suspension/closure revokes linked refresh sessions');
select ok((select exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='public.staff'::regclass and not t.tgisinternal
    and p.pronamespace='app'::regnamespace and p.proname like '%revoke%session%')),
  'ONB-004: owner association replacement revokes incoming and outgoing sessions');
select ok((select not has_table_privilege('authenticated','public.audit_log','INSERT')
  and not has_table_privilege('authenticated','public.audit_log','UPDATE')
  and not has_table_privilege('authenticated','public.audit_log','DELETE')),
  'audit remains append-only evidence with no authenticated direct writer');

select * from finish();
rollback;
