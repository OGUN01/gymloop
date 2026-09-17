-- Phase 6 platform control behaviours.  Every fixture is isolated under 37…;
-- no assertion depends on wall-clock equality, only database-produced values.
begin;
set local role postgres;
set local search_path = extensions, public;
select plan(42);

insert into auth.users(id,email) values
 ('37000000-0000-4000-8000-000000000901','platform37@gymloop.test'),
 ('37000000-0000-4000-8000-000000000902','owner37@gymloop.test');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('37000000-0000-4000-8000-000000000901','super_admin','Platform 37','platform37@gymloop.test',true);

select set_config('request.jwt.claims',
 '{"sub":"37000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;

create temp table platform37_result as
 select public.onboard_gym('37000000-0000-4000-8000-000000000001','  Platform Test Gym  ','Asia/Kolkata','INR',
   'premium_studio',' Main ',' Initial Owner ','  OWNER37@GYMLOOP.TEST ') as result;

select ok((select result ?& array['organization','branchId','ownerStaffId','ownerAccessPending']
  and result->>'ownerAccessPending'='true' from platform37_result),
  'ONB-001/004: onboarding returns exact pending-owner result facts');
select is((select result #>> '{organization,tenantId}' from platform37_result),
  '37000000-0000-4000-8000-000000000001','onboarding derives tenant id from request key');
select is((select result #>> '{organization,name}' from platform37_result),'Platform Test Gym',
  'onboarding trims organization name');
select is((select result #>> '{organization,status}' from platform37_result),'trial',
  'onboarding moves the new gym through pending approval into trial atomically');
select is((select result #>> '{organization,tier}' from platform37_result),null::text,
  'onboarding leaves the manual commercial tier unassigned');
select ok((select (result #>> '{organization,gymCode}') ~ '^[A-Z0-9]{6}$' from platform37_result),
  'ONB-002: database-generated gym code has the six-character identifier shape');
select ok((select count(*)=1 from public.organization_settings where tenant_id='37000000-0000-4000-8000-000000000001'),
  'ONB-001: onboarding creates exactly one settings row');
select ok((select count(*)=1 from public.branches where tenant_id='37000000-0000-4000-8000-000000000001' and is_default),
  'ONB-001: onboarding creates exactly one default branch');
select ok((select count(*)=1 from public.messaging_wallets where tenant_id='37000000-0000-4000-8000-000000000001' and balance_credits=0),
  'ONB-001: onboarding creates one zero-credit wallet');
select ok((select count(*)=0 from public.messaging_wallet_ledger where tenant_id='37000000-0000-4000-8000-000000000001'),
  'ONB-001: zero opening balance does not fabricate a ledger movement');
select ok((select count(*)=1 from public.staff where tenant_id='37000000-0000-4000-8000-000000000001'
  and role='gym_owner' and user_id is null and branch_id is null and is_active),
  'ONB-001: onboarding creates one active all-branch unlinked owner');
select ok((select no_show_threshold_days=5 and streak_rule_type='weekly_goal' and weekly_goal_default=3
  and max_freeze_days_per_year=30 and pause_approver_role='gym_owner'
 from public.organization_settings where tenant_id='37000000-0000-4000-8000-000000000001'),
  'ONB-003: premium preset copies its adopted settings once');
select ok((select trial_ends_at > created_at and activated_at is null from public.organizations
  where id='37000000-0000-4000-8000-000000000001'),
  'ONB-002: trial deadline is database-derived and activation remains unset');
select ok((select count(*)=1 from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
  and action='organization.onboarded' and request_key='37000000-0000-4000-8000-000000000001'
  and request_facts->>'command'='onboard_gym'),
  'ONB-001: changing onboarding records one keyed command audit event');

select is((select public.onboard_gym('37000000-0000-4000-8000-000000000001','Platform Test Gym','Asia/Kolkata','INR',
 'premium_studio','Main','Initial Owner','owner37@gymloop.test')),
 (select result from platform37_result),'ONB-001: exact replay returns the original onboarding result');
select is((select count(*) from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
 and action='organization.onboarded'),1::bigint,'onboarding replay appends no second audit event');
select throws_ok($$select public.onboard_gym('37000000-0000-4000-8000-000000000001','Different','Asia/Kolkata','INR','premium_studio','Main','Initial Owner','owner37@gymloop.test')$$,
 'GL068',null,'a reused onboarding key with different normalized facts is an idempotency conflict');

select throws_ok($$select public.set_gym_status('37000000-0000-4000-8000-000000000001','trial','active',null,'37000000-0000-4000-8000-000000000010')$$,
 'GL051',null,'activation refuses incomplete readiness before writing active');
select is((select status::text from public.organizations where id='37000000-0000-4000-8000-000000000001'),'trial',
  'failed readiness leaves lifecycle state unchanged');
select throws_ok($$select public.set_gym_status('37000000-0000-4000-8000-000000000001','trial','suspended','reason','37000000-0000-4000-8000-000000000011')$$,
 'GL050',null,'the command rejects a noncanonical trial-to-suspended edge');
select throws_ok($$select public.set_gym_status('37000000-0000-4000-8000-000000000001','pending_approval','trial',null,'37000000-0000-4000-8000-000000000012')$$,
 '40001',null,'CAS expected state is checked before a semantic no-op');

-- A no-op against the actual trial state must neither reserve its key nor audit.
select lives_ok($$select public.set_gym_status('37000000-0000-4000-8000-000000000001','trial','trial',null,'37000000-0000-4000-8000-000000000013')$$,
 'same-state status command is an inert no-op');
select is((select count(*) from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
 and request_key='37000000-0000-4000-8000-000000000013'),0::bigint,'status no-op has no audit evidence and leaves its key unreserved');

select is((select public.set_gym_tier('37000000-0000-4000-8000-000000000001',null,'growth','37000000-0000-4000-8000-000000000020') ->> 'tier'),
 'growth','ONB-005: tier command changes only the selected canonical manual label');
select is((select public.set_gym_tier('37000000-0000-4000-8000-000000000001','growth','growth','37000000-0000-4000-8000-000000000021') ->> 'tier'),
 'growth','tier same-value request is successful inert no-op');
select is((select count(*) from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
 and request_key='37000000-0000-4000-8000-000000000021'),0::bigint,'tier no-op does not reserve a request key');

select ok((select public.link_gym_owner('37000000-0000-4000-8000-000000000001',
  (select (result->>'ownerStaffId')::uuid from platform37_result),null,' OWNER37@GYMLOOP.TEST ',
  '37000000-0000-4000-8000-000000000030') ->> 'ownerAccessPending' = 'false'),
  'ONB-004: exact normalized Auth email links the designated owner');
select is((select user_id::text from public.staff where id=(select (result->>'ownerStaffId')::uuid from platform37_result)),
  '37000000-0000-4000-8000-000000000902','owner linking changes only the selected staff Auth association');
select is((select email from public.staff where id=(select (result->>'ownerStaffId')::uuid from platform37_result)),
  'owner37@gymloop.test','owner linking stores the lower-trimmed exact account email');
set local role postgres;
select is((select raw_app_meta_data->>'active_tenant_id' from auth.users where id='37000000-0000-4000-8000-000000000902'),
  '37000000-0000-4000-8000-000000000001','owner linking sets only the target owner preferred tenant');
set local role authenticated;
select is((select count(*) from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
  and action='staff.owner_linked' and record_id=(select (result->>'ownerStaffId')::uuid from platform37_result)
  and request_key='37000000-0000-4000-8000-000000000030'),1::bigint,
  'ONB-004: a changing owner link appends exactly one keyed owner audit event');
select ok((select public.link_gym_owner('37000000-0000-4000-8000-000000000001',
  (select (result->>'ownerStaffId')::uuid from platform37_result),'37000000-0000-4000-8000-000000000902',
  'owner37@gymloop.test','37000000-0000-4000-8000-000000000031') ->> 'ownerAccessPending' = 'false'),
  'exact already-linked owner is an inert owner-link no-op');
select is((select count(*) from public.audit_log where tenant_id='37000000-0000-4000-8000-000000000001'
  and request_key='37000000-0000-4000-8000-000000000031'),0::bigint,
  'unchanged owner link writes neither audit event nor retry reservation');

select ok((select public.set_gym_status('37000000-0000-4000-8000-000000000001','trial','active',null,
 '37000000-0000-4000-8000-000000000040')->'readiness'->>'settingsComplete'='true'),
 'OPS-002: activation succeeds only once linked-owner readiness is complete');
select ok((select status='active' and activated_at is not null from public.organizations
  where id='37000000-0000-4000-8000-000000000001'),
  'first activation stamps its server-owned activation instant');

select is((select public.start_gym_preview('37000000-0000-4000-8000-000000000001','  inspect settings  ',
 '37000000-0000-4000-8000-000000000050')->>'tenantId'),
 '37000000-0000-4000-8000-000000000001','OPS-003: super admin preview is bound to its requested existing gym');
select is((select public.start_gym_preview('37000000-0000-4000-8000-000000000001','inspect settings',
 '37000000-0000-4000-8000-000000000050')),
 (select public.start_gym_preview('37000000-0000-4000-8000-000000000001','inspect settings',
 '37000000-0000-4000-8000-000000000050')),
 'preview request-key replay returns the original session facts without extending it');

set local role postgres;
update public.impersonation_sessions set ended_at=statement_timestamp()
 where id='37000000-0000-4000-8000-000000000050';
insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,started_at,expires_at)
 values ('37000000-0000-4000-8000-000000000051','37000000-0000-4000-8000-000000000001',
  '37000000-0000-4000-8000-000000000901','historical expired preview',
  statement_timestamp()-interval '2 hours',statement_timestamp()-interval '1 hour');
select set_config('request.jwt.claims',
 '{"sub":"37000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select is((select public.end_expired_gym_preview('37000000-0000-4000-8000-000000000051')->>'sessionId'),
 '37000000-0000-4000-8000-000000000051','expired preview recovery ends the actor''s named expired session');
select ok((select ended_at is not null from public.impersonation_sessions where id='37000000-0000-4000-8000-000000000051'),
  'recovery records a database-produced end instant');

set local role postgres;
select set_config('request.jwt.claims',
 '{"sub":"37000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select throws_ok($$update public.organizations set tier='pro' where id='37000000-0000-4000-8000-000000000001'$$,
 'GL049',null,'NAV-008: authenticated direct commercial tier write cannot bypass the named command');
select lives_ok($$update public.organizations set status='active' where id='37000000-0000-4000-8000-000000000001'$$,
 'NAV-008: a same-value status write is noncommercial and remains permitted');
select throws_ok($$update public.staff set user_id=null where id=(select (result->>'ownerStaffId')::uuid from platform37_result)$$,
 'GL049',null,'ONB-004: direct authenticated Auth unbinding cannot bypass owner-link controls');

select * from finish();
rollback;
