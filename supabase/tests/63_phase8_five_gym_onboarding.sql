-- PILOT-006: one verified super admin atomically onboards five trial gyms.
-- Every fixture is synthetic, deterministic and transaction-only.
begin;

select plan(27);

set local role postgres;
set local search_path = extensions, public;

-- One platform identity is sufficient for all five requests.  No owner Auth
-- identities are created: each owner profile must remain active and unlinked.
insert into auth.users(id, email) values
  ('63000000-0000-4000-8000-000000000901', 'pilot63-platform@gymloop.test');
insert into public.platform_users(user_id, role, full_name, email, is_active) values
  ('63000000-0000-4000-8000-000000000901', 'super_admin', 'Pilot 63 Super Admin',
   'pilot63-platform@gymloop.test', true);

select set_config('request.jwt.claims',
  '{"sub":"63000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',
  true);
set local role authenticated;

create temporary table pilot63_requests(
  request_key uuid primary key,
  gym_name text not null,
  branch_name text not null,
  owner_name text not null,
  owner_email text not null
) on commit drop;

insert into pilot63_requests values
 ('63000000-0000-4000-8000-000000000001','Pilot 63 Gym 1','Pilot 63 Gym 1 Main','Pilot 63 Owner 1','owner63-1@gymloop.test'),
 ('63000000-0000-4000-8000-000000000002','Pilot 63 Gym 2','Pilot 63 Gym 2 Main','Pilot 63 Owner 2','owner63-2@gymloop.test'),
 ('63000000-0000-4000-8000-000000000003','Pilot 63 Gym 3','Pilot 63 Gym 3 Main','Pilot 63 Owner 3','owner63-3@gymloop.test'),
 ('63000000-0000-4000-8000-000000000004','Pilot 63 Gym 4','Pilot 63 Gym 4 Main','Pilot 63 Owner 4','owner63-4@gymloop.test'),
 ('63000000-0000-4000-8000-000000000005','Pilot 63 Gym 5','Pilot 63 Gym 5 Main','Pilot 63 Owner 5','owner63-5@gymloop.test');

create temporary table pilot63_results(
  request_key uuid primary key,
  result jsonb not null
) on commit drop;

insert into pilot63_results(request_key, result)
select r.request_key,
       public.onboard_gym(r.request_key, r.gym_name, 'Asia/Kolkata', 'INR',
         'premium_studio'::public.gym_preset, r.branch_name, r.owner_name, r.owner_email)
from pilot63_requests r
order by r.request_key;

select is((select count(*) from pilot63_results), 5::bigint,
  'PILOT-006: five distinct onboarding requests return five results');
select is((select count(*) from public.organizations
  where id in (select request_key from pilot63_requests)), 5::bigint,
  'PILOT-006: five organizations are created');
select is((select count(distinct gym_code) from public.organizations
  where id in (select request_key from pilot63_requests)), 5::bigint,
  'PILOT-006: all five gyms receive distinct codes');
select ok((select bool_and(gym_code ~ '^[A-Z0-9]{6}$') from public.organizations
  where id in (select request_key from pilot63_requests)),
  'PILOT-006: every gym code is exactly six alphanumeric characters');
select is((select count(*) from public.organizations
  where id in (select request_key from pilot63_requests) and status='trial'), 5::bigint,
  'PILOT-006: every organization starts in trial');
select is((select count(*) from public.organizations
  where id in (select request_key from pilot63_requests) and trial_ends_at > created_at and activated_at is null), 5::bigint,
  'PILOT-006: every trial has a database-derived boundary and no activation');

select is((select count(*) from (select tenant_id from public.organization_settings
  where tenant_id in (select request_key from pilot63_requests) group by tenant_id having count(*)=1) exact), 5::bigint,
  'PILOT-006: exactly one settings row exists per gym');
select is((select count(*) from (select tenant_id from public.branches
  where tenant_id in (select request_key from pilot63_requests) and is_default group by tenant_id having count(*)=1) exact), 5::bigint,
  'PILOT-006: exactly one default branch exists per gym');
select is((select count(*) from (select tenant_id from public.messaging_wallets
  where tenant_id in (select request_key from pilot63_requests) and balance_credits=0 group by tenant_id having count(*)=1) exact), 5::bigint,
  'PILOT-006: exactly one zero-credit wallet exists per gym');
select is((select count(*) from public.messaging_wallet_ledger
  where tenant_id in (select request_key from pilot63_requests)), 0::bigint,
  'PILOT-006: zero opening balance creates no ledger movement');
select is((select count(*) from (select tenant_id from public.staff
  where tenant_id in (select request_key from pilot63_requests)
    and role='gym_owner' and user_id is null and branch_id is null and is_active group by tenant_id having count(*)=1) exact), 5::bigint,
  'PILOT-006: exactly one active unlinked owner profile exists per gym');
select is((select count(*) from (select tenant_id from public.audit_log
  where tenant_id in (select request_key from pilot63_requests)
    and action='organization.onboarded' and request_key in (select request_key from pilot63_requests)
    and request_facts->>'command'='onboard_gym' group by tenant_id having count(*)=1) exact), 5::bigint,
  'PILOT-006: exactly one keyed onboarding audit exists per gym');

select is((select count(*) from pilot63_results p
  join public.organizations o on o.id=p.request_key
  where p.result #>> '{organization,tenantId}'=p.request_key::text
    and p.result #>> '{organization,status}'='trial'
    and p.result #>> '{organization,gymCode}'=o.gym_code), 5::bigint,
  'PILOT-006: each result identifies its exact trial organization and code');
select is((select count(*) from pilot63_results
  where result ?& array['organization','branchId','ownerStaffId','ownerAccessPending']
    and result->>'ownerAccessPending'='true'), 5::bigint,
  'PILOT-006: each result exposes the pending unlinked-owner shape');

-- Exact replay must return the original result and must not create siblings.
select is((select count(*) from pilot63_requests r
  where public.onboard_gym(r.request_key, r.gym_name, 'Asia/Kolkata', 'INR',
    'premium_studio'::public.gym_preset, r.branch_name, r.owner_name, r.owner_email)
    = (select p.result from pilot63_results p where p.request_key=r.request_key)), 5::bigint,
  'PILOT-006: exact replay returns each original result');
select is((select count(*) from public.organization_settings
  where tenant_id in (select request_key from pilot63_requests)), 5::bigint,
  'PILOT-006: replay creates no second settings row');
select is((select count(*) from public.branches
  where tenant_id in (select request_key from pilot63_requests) and is_default), 5::bigint,
  'PILOT-006: replay creates no second default branch');
select is((select count(*) from public.messaging_wallets
  where tenant_id in (select request_key from pilot63_requests)), 5::bigint,
  'PILOT-006: replay creates no second wallet');
select is((select count(*) from public.staff
  where tenant_id in (select request_key from pilot63_requests) and role='gym_owner'), 5::bigint,
  'PILOT-006: replay creates no second owner profile');
select is((select count(*) from public.audit_log
  where tenant_id in (select request_key from pilot63_requests) and action='organization.onboarded'), 5::bigint,
  'PILOT-006: replay creates no second onboarding audit');

-- A reused key with changed facts is refused for every gym and leaves the
-- original organization and audit facts unchanged.
select throws_ok($$select public.onboard_gym('63000000-0000-4000-8000-000000000001','Pilot 63 Gym 1 Changed','Asia/Kolkata','INR','premium_studio','Pilot 63 Gym 1 Main','Pilot 63 Owner 1','owner63-1@gymloop.test')$$,
  'GL068', null, 'PILOT-006: changed facts for gym 1 key are refused');
select throws_ok($$select public.onboard_gym('63000000-0000-4000-8000-000000000002','Pilot 63 Gym 2 Changed','Asia/Kolkata','INR','premium_studio','Pilot 63 Gym 2 Main','Pilot 63 Owner 2','owner63-2@gymloop.test')$$,
  'GL068', null, 'PILOT-006: changed facts for gym 2 key are refused');
select throws_ok($$select public.onboard_gym('63000000-0000-4000-8000-000000000003','Pilot 63 Gym 3 Changed','Asia/Kolkata','INR','premium_studio','Pilot 63 Gym 3 Main','Pilot 63 Owner 3','owner63-3@gymloop.test')$$,
  'GL068', null, 'PILOT-006: changed facts for gym 3 key are refused');
select throws_ok($$select public.onboard_gym('63000000-0000-4000-8000-000000000004','Pilot 63 Gym 4 Changed','Asia/Kolkata','INR','premium_studio','Pilot 63 Gym 4 Main','Pilot 63 Owner 4','owner63-4@gymloop.test')$$,
  'GL068', null, 'PILOT-006: changed facts for gym 4 key are refused');
select throws_ok($$select public.onboard_gym('63000000-0000-4000-8000-000000000005','Pilot 63 Gym 5 Changed','Asia/Kolkata','INR','premium_studio','Pilot 63 Gym 5 Main','Pilot 63 Owner 5','owner63-5@gymloop.test')$$,
  'GL068', null, 'PILOT-006: changed facts for gym 5 key are refused');

select is((select count(*) from public.organizations
  where id in (select request_key from pilot63_requests)), 5::bigint,
  'PILOT-006: changed-facts refusals leave all five organizations intact');
select is((select count(*) from public.audit_log
  where tenant_id in (select request_key from pilot63_requests) and action='organization.onboarded'), 5::bigint,
  'PILOT-006: changed-facts refusals append no audit rows');

select * from finish();
rollback;
