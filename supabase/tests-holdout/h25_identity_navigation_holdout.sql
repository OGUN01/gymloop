-- Independent NAV-001..005/007 database holdout, authored from dc391b4.
-- No implementation or visible suite was read. NAV-006/008 are deliberately absent.
begin;
set local role postgres;
select no_plan();

create function pg_temp.nav_event(p_user text) returns jsonb
language sql as $fn$
  select jsonb_build_object(
    'user_id', p_user,
    'authentication_method', 'token_refresh',
    'claims', jsonb_build_object(
      'sub', p_user, 'aud', 'authenticated', 'role', 'authenticated',
      'iss', 'https://holdout.invalid/auth/v1', 'aal', 'aal2',
      'exp', 2082759300, 'iat', 2082758400,
      'session_id', '92500000-0000-4000-8000-000000000099',
      'email', 'nav-holdout@example.test', 'phone', '+919250000099',
      'is_anonymous', false,
      'amr', jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', 2082758400)),
      'user_metadata', jsonb_build_object('theme', 'dark', 'nested', jsonb_build_array(1, null, true)),
      'unrelated_claim', jsonb_build_object('tenant_id', 'keep nested reserved data'),
      'app_role', 'gym_owner', 'tenant_id', 'stale-tenant',
      'staff_id', 'stale-staff', 'member_id', 'stale-member',
      'impersonation_session_id', 'stale-preview'))
$fn$;

create function pg_temp.nav_hook(p_event jsonb) returns jsonb
language plpgsql as $fn$
declare answer jsonb;
begin
  execute 'select app.custom_access_token_hook($1)' into answer using p_event;
  return answer;
exception when others then
  return jsonb_build_object('unexpected_hook_exception', sqlstate);
end;
$fn$;

create function pg_temp.nav_gym(p_claims jsonb) returns jsonb
language sql as $fn$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(p_claims) = 'object' then p_claims else '{}'::jsonb end)
  where key in ('app_role', 'tenant_id', 'staff_id', 'member_id', 'impersonation_session_id')
$fn$;

create function pg_temp.nav_reserved(p_claims jsonb) returns jsonb
language sql as $fn$
  select p_claims - array['app_role', 'tenant_id', 'staff_id', 'member_id', 'impersonation_session_id']
$fn$;

create function pg_temp.nav_attempt(p_sql text) returns text
language plpgsql as $fn$
declare affected bigint;
begin
  execute p_sql;
  get diagnostics affected = row_count;
  return 'rows=' || affected;
exception when others then
  return 'error=' || sqlstate;
end;
$fn$;

create temporary table nav_observations (
  label text primary key,
  input jsonb not null,
  expected jsonb not null,
  result jsonb
);

do $grant_temp$
begin
  execute format('grant usage on schema %I to authenticated', pg_my_temp_schema()::regnamespace);
end;
$grant_temp$;
grant select on nav_observations to authenticated;

-- Pending-approval organization defaults are intentional: this slice must not
-- introduce the later NAV-006 organization-status eligibility rule.
insert into public.organizations (id, name, gym_code) values
  ('a6250000-0000-4000-8000-000000000001', 'NAV Holdout Alpha', 'NV25A1'),
  ('a6250000-0000-4000-8000-000000000002', 'NAV Holdout Beta', 'NV25B2');
insert into public.organization_settings (tenant_id) values
  ('a6250000-0000-4000-8000-000000000001');
insert into public.branches (id, tenant_id, name, is_default) values
  ('b6250000-0000-4000-8000-000000000001', 'a6250000-0000-4000-8000-000000000001', 'Alpha', true),
  ('b6250000-0000-4000-8000-000000000002', 'a6250000-0000-4000-8000-000000000002', 'Beta', true);

insert into auth.users (id, raw_app_meta_data) values
  ('06250000-0000-4000-8000-000000000001', '{}'),
  ('06250000-0000-4000-8000-000000000002', '{}'),
  ('06250000-0000-4000-8000-000000000003', '{"active_tenant_id":"a6250000-0000-4000-8000-000000000001"}'),
  ('06250000-0000-4000-8000-000000000004', '{}'),
  ('06250000-0000-4000-8000-000000000005', '{}'),
  ('06250000-0000-4000-8000-000000000006', '{}'),
  ('06250000-0000-4000-8000-000000000007', '{}'),
  ('06250000-0000-4000-8000-000000000008', '{}');

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  ('06250000-0000-4000-8000-000000000001', 'platform_support', 'Support Above Staff', 'support-nav25@example.test', true),
  ('06250000-0000-4000-8000-000000000002', 'super_admin', 'Inactive Above Staff', 'inactive-nav25@example.test', false),
  ('06250000-0000-4000-8000-000000000007', 'super_admin', 'Preview Alpha', 'preview-alpha-nav25@example.test', true),
  ('06250000-0000-4000-8000-000000000008', 'super_admin', 'Preview Beta', 'preview-beta-nav25@example.test', true);

insert into public.staff (id, tenant_id, user_id, role, full_name, is_active, created_at) values
  ('e6250000-0000-4000-8000-000000000011', 'a6250000-0000-4000-8000-000000000001',
   '06250000-0000-4000-8000-000000000001', 'gym_owner', 'Under Support', true, '2020-01-01T00:00:00Z'),
  ('e6250000-0000-4000-8000-000000000012', 'a6250000-0000-4000-8000-000000000001',
   '06250000-0000-4000-8000-000000000002', 'gym_owner', 'Under Inactive Platform', true, '2020-01-01T00:00:00Z'),
  ('e6250000-0000-4000-8000-000000000002', 'a6250000-0000-4000-8000-000000000001',
   '06250000-0000-4000-8000-000000000003', 'gym_manager', 'Requested Alpha', true, '2021-01-01T00:00:00Z'),
  ('e6250000-0000-4000-8000-000000000001', 'a6250000-0000-4000-8000-000000000002',
   '06250000-0000-4000-8000-000000000003', 'trainer', 'Tie Winner Beta', true, '2021-01-01T00:00:00Z'),
  ('e6250000-0000-4000-8000-000000000005', 'a6250000-0000-4000-8000-000000000001',
   '06250000-0000-4000-8000-000000000005', 'front_desk', 'Inactive Staff', false, '2020-01-01T00:00:00Z');

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone, created_at) values
  ('d6250000-0000-4000-8000-000000000011', 'a6250000-0000-4000-8000-000000000001',
   'b6250000-0000-4000-8000-000000000001', '06250000-0000-4000-8000-000000000001', 'Under Support', '+919250000011', '2019-01-01T00:00:00Z'),
  ('d6250000-0000-4000-8000-000000000012', 'a6250000-0000-4000-8000-000000000001',
   'b6250000-0000-4000-8000-000000000001', '06250000-0000-4000-8000-000000000002', 'Under Inactive Platform', '+919250000012', '2019-01-01T00:00:00Z'),
  ('d6250000-0000-4000-8000-000000000013', 'a6250000-0000-4000-8000-000000000001',
   'b6250000-0000-4000-8000-000000000001', '06250000-0000-4000-8000-000000000003', 'Under Active Staff', '+919250000013', '2019-01-01T00:00:00Z'),
  ('d6250000-0000-4000-8000-000000000002', 'a6250000-0000-4000-8000-000000000001',
   'b6250000-0000-4000-8000-000000000001', '06250000-0000-4000-8000-000000000004', 'Earlier Alpha Member', '+919250000004', '2019-01-01T00:00:00Z'),
  ('d6250000-0000-4000-8000-000000000001', 'a6250000-0000-4000-8000-000000000002',
   'b6250000-0000-4000-8000-000000000002', '06250000-0000-4000-8000-000000000004', 'Later Beta Member', '+919250000004', '2020-01-01T00:00:00Z'),
  ('d6250000-0000-4000-8000-000000000005', 'a6250000-0000-4000-8000-000000000001',
   'b6250000-0000-4000-8000-000000000001', '06250000-0000-4000-8000-000000000005', 'Under Inactive Staff', '+919250000005', '2019-01-01T00:00:00Z');

insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at) values
  ('f6250000-0000-4000-8000-000000000001', 'a6250000-0000-4000-8000-000000000001',
   '06250000-0000-4000-8000-000000000007', 'independent preview alpha', now() + interval '45 minutes'),
  ('f6250000-0000-4000-8000-000000000002', 'a6250000-0000-4000-8000-000000000002',
   '06250000-0000-4000-8000-000000000008', 'independent preview beta', now() + interval '45 minutes');

insert into nav_observations (label, input, expected) values
  ('platform precedence', pg_temp.nav_event('06250000-0000-4000-8000-000000000001'), '{"app_role":"platform_support"}'),
  ('inactive platform blocks fallthrough', pg_temp.nav_event('06250000-0000-4000-8000-000000000002'), '{}'),
  ('staff requested tenant and precedence', pg_temp.nav_event('06250000-0000-4000-8000-000000000003'),
   '{"app_role":"gym_manager","tenant_id":"a6250000-0000-4000-8000-000000000001","staff_id":"e6250000-0000-4000-8000-000000000002"}'),
  ('member earliest creation beats id order', pg_temp.nav_event('06250000-0000-4000-8000-000000000004'),
   '{"app_role":"member","tenant_id":"a6250000-0000-4000-8000-000000000001","member_id":"d6250000-0000-4000-8000-000000000002"}'),
  ('inactive staff blocks member fallthrough', pg_temp.nav_event('06250000-0000-4000-8000-000000000005'), '{}'),
  ('unlinked cleanup', pg_temp.nav_event('06250000-0000-4000-8000-000000000006'), '{}'),
  ('live preview', pg_temp.nav_event('06250000-0000-4000-8000-000000000007'),
   '{"app_role":"gym_owner","tenant_id":"a6250000-0000-4000-8000-000000000001","impersonation_session_id":"f6250000-0000-4000-8000-000000000001"}'),
  ('invalid event user fallback', jsonb_set(pg_temp.nav_event('06250000-0000-4000-8000-000000000006'), '{user_id}', '"invalid UUID"'), '{}'),
  ('null event user fallback', jsonb_set(pg_temp.nav_event('06250000-0000-4000-8000-000000000006'), '{user_id}', 'null'), '{}'),
  ('missing event user fallback', pg_temp.nav_event('06250000-0000-4000-8000-000000000006') - 'user_id', '{}');
update nav_observations set result = pg_temp.nav_hook(input);

-- Selection remains deterministic while cleanup applies to every fresh result.
update auth.users set raw_app_meta_data = '{}' where id = '06250000-0000-4000-8000-000000000003';
insert into nav_observations (label, input, expected, result) values (
  'staff equal timestamp lower id', pg_temp.nav_event('06250000-0000-4000-8000-000000000003'),
  '{"app_role":"trainer","tenant_id":"a6250000-0000-4000-8000-000000000002","staff_id":"e6250000-0000-4000-8000-000000000001"}',
  pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000003')));
update auth.users set raw_app_meta_data = '{"active_tenant_id":"not-a-uuid"}' where id = '06250000-0000-4000-8000-000000000003';
insert into nav_observations (label, input, expected, result) values (
  'invalid requested tenant falls back', pg_temp.nav_event('06250000-0000-4000-8000-000000000003'),
  '{"app_role":"trainer","tenant_id":"a6250000-0000-4000-8000-000000000002","staff_id":"e6250000-0000-4000-8000-000000000001"}',
  pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000003')));
update auth.users set raw_app_meta_data = '{"active_tenant_id":"a6250000-0000-4000-8000-000000000002"}' where id = '06250000-0000-4000-8000-000000000003';
update public.staff set is_active = false where id = 'e6250000-0000-4000-8000-000000000001';
insert into nav_observations (label, input, expected, result) values (
  'inactive requested staff tenant falls back', pg_temp.nav_event('06250000-0000-4000-8000-000000000003'),
  '{"app_role":"gym_manager","tenant_id":"a6250000-0000-4000-8000-000000000001","staff_id":"e6250000-0000-4000-8000-000000000002"}',
  pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000003')));
update auth.users set raw_app_meta_data = '{"active_tenant_id":"a6250000-0000-4000-8000-000000000002"}' where id = '06250000-0000-4000-8000-000000000004';
insert into nav_observations (label, input, expected, result) values (
  'member requested tenant', pg_temp.nav_event('06250000-0000-4000-8000-000000000004'),
  '{"app_role":"member","tenant_id":"a6250000-0000-4000-8000-000000000002","member_id":"d6250000-0000-4000-8000-000000000001"}',
  pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000004')));
update public.members set status = 'paused' where id = 'd6250000-0000-4000-8000-000000000001';
insert into nav_observations (label, input, expected, result) values (
  'paused member keeps first-slice access', pg_temp.nav_event('06250000-0000-4000-8000-000000000004'),
  '{"app_role":"member","tenant_id":"a6250000-0000-4000-8000-000000000002","member_id":"d6250000-0000-4000-8000-000000000001"}',
  pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000004')));

select is(pg_temp.nav_gym(result -> 'claims'), expected, 'NAV-007 exact fresh shape: ' || label)
from nav_observations order by label;
select is(pg_temp.nav_reserved(result -> 'claims'), pg_temp.nav_reserved(input -> 'claims'),
          'NAV-007 every reserved and unrelated fact unchanged: ' || label)
from nav_observations order by label;
select ok(not (result ? 'unexpected_hook_exception'), 'NAV-007 no global Auth failure: ' || label)
from nav_observations order by label;

select ok(
  (select p.prosecdef and exists (
     select 1 from unnest(p.proconfig) config
     where split_part(config, '=', 1) = 'search_path' and split_part(config, '=', 2) in ('', '""'))
   from pg_proc p where p.oid = 'app.custom_access_token_hook(jsonb)'::regprocedure),
  'NAV-007 preserves definer hook with empty search path');
select ok(
  has_function_privilege('supabase_auth_admin', 'app.custom_access_token_hook(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'app.custom_access_token_hook(jsonb)', 'execute')
  and not has_function_privilege('anon', 'app.custom_access_token_hook(jsonb)', 'execute'),
  'NAV-007 preserves Auth-only hook execution');

-- No implementation-specific guard name: the same private invoker BEFORE
-- function must cover each granted mutation on every public writable table.
with writable as (
  select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
    and c.relname <> 'impersonation_sessions'
    and (has_table_privilege('authenticated', c.oid, 'INSERT')
      or has_table_privilege('authenticated', c.oid, 'UPDATE')
      or has_table_privilege('authenticated', c.oid, 'DELETE'))
), private_invokers as (
  select distinct p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  join pg_trigger g on g.tgfoid = p.oid
  where n.nspname = 'app' and not p.prosecdef and not g.tgisinternal
)
select ok(exists (
  select 1 from private_invokers p where not exists (
    select 1 from writable w
    cross join (values ('INSERT', 4), ('UPDATE', 16), ('DELETE', 8)) operation(privilege, bit)
    where has_table_privilege('authenticated', w.oid, operation.privilege)
      and not exists (
        select 1 from pg_trigger g where g.tgrelid = w.oid and g.tgfoid = p.oid
          and not g.tgisinternal and g.tgenabled in ('O', 'A')
          and (g.tgtype & 2) = 2 and (g.tgtype & operation.bit) = operation.bit)))
  and exists (select 1 from writable),
  'NAV-003 metadata: one enabled private invoker BEFORE guard covers every authenticated-writable public table and operation');

set local role authenticated;
select set_config('request.jwt.claims',
  (select (expected || pg_temp.nav_reserved(input -> 'claims'))::text
   from nav_observations where label = 'live preview'), true);

select is((select count(*) from public.members where tenant_id = 'a6250000-0000-4000-8000-000000000001'),
          5::bigint, 'NAV-003 preview keeps its existing target-gym member read permission');
select is((select count(*) from public.members where tenant_id = 'a6250000-0000-4000-8000-000000000002'),
          0::bigint, 'NAV-003 preview reads no other-gym member');

select is(pg_temp.nav_attempt(command), 'error=42501', 'NAV-003 product mutation refuses: ' || label)
from (values
  ('member update', $q$update public.members set full_name = 'forbidden replacement' where id = 'd6250000-0000-4000-8000-000000000002'$q$),
  ('member insert', $q$insert into public.members (tenant_id, branch_id, full_name, phone) values ('a6250000-0000-4000-8000-000000000001', 'b6250000-0000-4000-8000-000000000001', 'forbidden insert', '+919250000090')$q$),
  ('organization update', $q$update public.organizations set name = 'forbidden rename' where id = 'a6250000-0000-4000-8000-000000000001'$q$),
  ('settings update', $q$update public.organization_settings set receipt_prefix = 'BAD' where tenant_id = 'a6250000-0000-4000-8000-000000000001'$q$),
  ('branch update', $q$update public.branches set name = 'forbidden branch rename' where id = 'b6250000-0000-4000-8000-000000000001'$q$),
  ('branch insert', $q$insert into public.branches (tenant_id, name) values ('a6250000-0000-4000-8000-000000000001', 'forbidden branch insert')$q$),
  ('staff update', $q$update public.staff set full_name = 'forbidden staff rename' where id = 'e6250000-0000-4000-8000-000000000002'$q$),
  ('plan insert', $q$insert into public.plans (tenant_id, name, duration_days, price_paise) values ('a6250000-0000-4000-8000-000000000001', 'forbidden plan insert', 30, 100000)$q$)
) cases(label, command) order by label;

select is(pg_temp.nav_attempt($q$update public.members set full_name = 'foreign attempt' where id = 'd6250000-0000-4000-8000-000000000001'$q$),
          'rows=0', 'NAV-003 an unreadable other-tenant UPDATE remains filtered by RLS');
select is(pg_temp.nav_attempt($q$update public.impersonation_sessions set ended_at = now() where id = 'f6250000-0000-4000-8000-000000000002'$q$),
          'rows=0', 'NAV-003 own-end exception reaches no other actor session');
select is(pg_temp.nav_attempt($q$update public.impersonation_sessions set expires_at = now() + interval '60 minutes' where id = 'f6250000-0000-4000-8000-000000000001'$q$),
          'error=42501', 'NAV-003 own-end exception does not authorize expiry-only writes');
select is(pg_temp.nav_attempt($q$update public.impersonation_sessions set ended_at = now() where id = 'f6250000-0000-4000-8000-000000000001'$q$),
          'rows=1', 'NAV-004 complete preview can end only its own session');
select is((select count(*) from public.audit_log
           where record_id = 'f6250000-0000-4000-8000-000000000001' and action = 'impersonation_session.ended'),
          1::bigint, 'NAV-004 own-end still writes its existing audit evidence');

-- Ordinary staff keeps the existing table policy; explicit JSON null is absence.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '06250000-0000-4000-8000-000000000003', 'role', 'authenticated',
  'app_role', 'gym_manager', 'tenant_id', 'a6250000-0000-4000-8000-000000000001',
  'staff_id', 'e6250000-0000-4000-8000-000000000002', 'impersonation_session_id', null)::text, true);
select is(pg_temp.nav_attempt($q$update public.branches set name = 'legitimate manager rename' where id = 'b6250000-0000-4000-8000-000000000001'$q$),
          'rows=1', 'NAV-003 null preview fact does not revoke ordinary manager branch writes');

set local role postgres;
select is(pg_temp.nav_gym(pg_temp.nav_hook(pg_temp.nav_event('06250000-0000-4000-8000-000000000007')) -> 'claims'),
          '{"app_role":"super_admin"}'::jsonb,
          'NAV-004/007 refresh after own-end clears stale preview facts and restores platform');
select is((select ended_at from public.impersonation_sessions where id = 'f6250000-0000-4000-8000-000000000002'),
          null::timestamptz, 'NAV-004 another actor session remains live');

select * from finish();
rollback;
