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

insert into auth.users (id, raw_app_meta_data) values
  ('60000000-0000-4000-8000-000000000031', '{}'::jsonb),
  ('60000000-0000-4000-8000-000000000032', '{}'::jsonb);

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('60000000-0000-4000-8000-000000000021', '60000000-0000-4000-8000-000000000001',
   '60000000-0000-4000-8000-000000000011', '60000000-0000-4000-8000-000000000031', 'Portal Member A', '+916000000021'),
  ('60000000-0000-4000-8000-000000000022', '60000000-0000-4000-8000-000000000002',
   '60000000-0000-4000-8000-000000000012', '60000000-0000-4000-8000-000000000032', 'Portal Member B', '+916000000022');

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
  $$select city, state, weekly_goal_default, week_start_day, streak_rule_type::text
      from public.read_member_portal_settings()$$,
  $$values ('Pune'::text, 'Maharashtra'::text, 4::smallint, 1::smallint, 'weekly_goal'::text)$$,
  'a complete canonical member receives only their tenant presentation settings'
);

select results_eq(
  $$select pg_get_function_result(p.oid)
      from pg_proc p
     where p.oid = to_regprocedure('public.read_member_portal_settings()')$$,
  $$values ('TABLE(city text, state text, weekly_goal_default smallint, week_start_day smallint, streak_rule_type streak_rule_type)'::text)$$,
  'the member settings command has exactly the approved five-column TABLE signature'
);

select is(
  (select count(*)
     from pg_proc p
     cross join lateral unnest(p.proargnames) with ordinality as n(name, ord)
    where p.oid = to_regprocedure('public.read_member_portal_settings()')
      and p.proargmodes[n.ord] = 't'
      and n.name not in ('city', 'state', 'weekly_goal_default', 'week_start_day', 'streak_rule_type')),
  0::bigint,
  'the member projection exposes no settings row, tenant id, GSTIN, or financial fields'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"member","tenant_id":"60000000-0000-4000-8000-000000000001"}',
  true
);
select throws_ok(
  $$select * from public.read_member_portal_settings()$$,
  null::char(5), null,
  'an incomplete member identity is refused'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000001","member_id":"60000000-0000-4000-8000-000000000021"}',
  true
);
select throws_ok(
  $$select * from public.read_member_portal_settings()$$,
  null::char(5), null,
  'a non-member role carrying member_id is refused'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"member","tenant_id":"60000000-0000-4000-8000-000000000002","member_id":"60000000-0000-4000-8000-000000000021"}',
  true
);
select throws_ok(
  $$select * from public.read_member_portal_settings()$$,
  null::char(5), null,
  'a member claim whose tenant does not own member_id is refused'
);

select ok(
  exists (
    select 1
      from pg_proc p
     where p.oid = to_regprocedure('public.read_member_portal_settings()')
       and p.prosecdef
       and p.proargmodes = array['t','t','t','t','t']::"char"[]
  ),
  'the public command is a security-definer claim-scoped five-column boundary'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.read_member_portal_settings()',
    'EXECUTE'
  ),
  'authenticated can reach the narrow public command'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-4000-8000-000000000031","role":"authenticated","app_role":"member","tenant_id":"60000000-0000-4000-8000-000000000001","member_id":"60000000-0000-4000-8000-000000000021"}',
  true
);
select results_eq(
  $$select tenant_id from public.organization_settings$$,
  $$select tenant_id from public.organization_settings where false$$,
  'members cannot read organization_settings rows directly; the projection command is the only settings path'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.oid = to_regprocedure('public.read_member_portal_settings()')
       and pg_get_function_result(p.oid) ilike 'table%'
  ),
  'the settings boundary has a typed structured result rather than exposing a table row'
);

select * from finish();

rollback;
