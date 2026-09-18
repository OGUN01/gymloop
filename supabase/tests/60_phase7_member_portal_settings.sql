-- Phase 7 member portal settings boundary.
--
-- A member receives a deliberately tiny presentation-settings projection from
-- one claim-scoped public command.  The caller never selects the source
-- organization_settings row.  This suite is intentionally red until the
-- command and both callers are implemented; it is transaction-only (ADR-030).

begin;

select plan(10);

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('60000000-0000-4000-8000-000000000001', 'Portal Gym A', 'PGA001'),
  ('60000000-0000-4000-8000-000000000002', 'Portal Gym B', 'PGB001');

insert into public.branches (id, tenant_id, name) values
  ('60000000-0000-4000-8000-000000000011', '60000000-0000-4000-8000-000000000001', 'A Main'),
  ('60000000-0000-4000-8000-000000000012', '60000000-0000-4000-8000-000000000002', 'B Main');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('60000000-0000-4000-8000-000000000021', '60000000-0000-4000-8000-000000000001',
   '60000000-0000-4000-8000-000000000011', 'Portal Member A', '+916000000021'),
  ('60000000-0000-4000-8000-000000000022', '60000000-0000-4000-8000-000000000002',
   '60000000-0000-4000-8000-000000000012', 'Portal Member B', '+916000000022');

insert into public.organization_settings (tenant_id, city, state, weekly_goal_default,
                                          week_start_day, streak_rule_type)
values
  ('60000000-0000-4000-8000-000000000001', 'Pune', 'Maharashtra', 4, 1, 'weekly_goal'),
  ('60000000-0000-4000-8000-000000000002', 'Surat', 'Gujarat', 6, 0, 'visit_streak');

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-4000-8000-000000000031',
    'role', 'authenticated',
    'app_role', 'member',
    'tenant_id', '60000000-0000-4000-8000-000000000001',
    'member_id', '60000000-0000-4000-8000-000000000021'
  )::text,
  true
);
set local role authenticated;

select results_eq(
  $$select public.read_member_portal_settings()$$,
  $$select jsonb_build_object(
    'city', 'Pune', 'state', 'Maharashtra', 'weekly_goal_default', 4,
    'week_start_day', 1, 'streak_rule_type', 'weekly_goal'
  )$$,
  'a complete canonical member receives only their tenant presentation settings'
);

select results_eq(
  $$select string_agg(key, ',' order by key)
      from jsonb_object_keys(public.read_member_portal_settings()) as key$$,
  $$select 'city,state,streak_rule_type,week_start_day,weekly_goal_default'$$,
  'the member settings command returns exactly the five approved keys'
);

select is(
  (select count(*) from jsonb_object_keys(public.read_member_portal_settings())
    where key in ('id', 'tenant_id', 'gstin', 'financial_year_start_month',
                  'checkin_dedupe_seconds', 'trainer_member_cap')),
  0::bigint,
  'the member projection exposes no settings row, tenant id, GSTIN, or financial fields'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"member","tenant_id":"60000000-0000-4000-8000-000000000001"}',
  true
);
select throws_ok(
  $$select public.read_member_portal_settings()$$,
  null::char(5), null,
  'an incomplete member identity is refused'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000001","member_id":"60000000-0000-4000-8000-000000000021"}',
  true
);
select throws_ok(
  $$select public.read_member_portal_settings()$$,
  null::char(5), null,
  'a non-member role carrying member_id is refused'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"member","tenant_id":"60000000-0000-4000-8000-000000000002","member_id":"60000000-0000-4000-8000-000000000021"}',
  true
);
select throws_ok(
  $$select public.read_member_portal_settings()$$,
  null::char(5), null,
  'a member claim whose tenant does not own member_id is refused'
);

select ok(
  not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'read_member_portal_settings'
       and pg_get_functiondef(p.oid) ilike '%organization_settings%'
  )
  or exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'read_member_portal_settings'
       and pg_get_functiondef(p.oid) ilike '%current_member_id%'
       and pg_get_functiondef(p.oid) ilike '%current_tenant_id%'
  ),
  'the public command is claim-scoped and cannot be a tenant-blind settings read'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.read_member_portal_settings()',
    'EXECUTE'
  ),
  'authenticated can reach the narrow public command'
);

select ok(
  not has_table_privilege('authenticated', 'public.organization_settings', 'SELECT'),
  'members cannot select organization_settings directly'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'read_member_portal_settings'
       and pg_get_function_result(p.oid) ilike '%json%'
  ),
  'the settings boundary has a typed structured result rather than exposing a table row'
);

select * from finish();

rollback;
