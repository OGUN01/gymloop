BEGIN;

SELECT plan(9);

-- The command is a deliberately narrow member-facing read surface.
SELECT has_function(
  'public',
  'read_member_portal_settings',
  ARRAY[]::text[],
  'member portal settings command exists with no arguments'
);

-- The command validates a real member-to-subject association.  Stage the
-- minimal relation explicitly instead of assuming another test's transaction
-- left one behind.  The auth FK is irrelevant to the command's own lookup, so
-- the fixture bypasses it only while this rolled-back row is inserted.
SET LOCAL ROLE postgres;
INSERT INTO public.organizations (id, name, gym_code, status, activated_at)
VALUES ('00000000-0000-0000-0000-000000000010', 'H59 Settings Gym', 'H59SET', 'active', now());
INSERT INTO public.organization_settings
  (tenant_id, city, state, weekly_goal_default, week_start_day, streak_rule_type)
VALUES
  ('00000000-0000-0000-0000-000000000010', 'Pune', 'Maharashtra', 4, 1, 'weekly_goal');
INSERT INTO public.branches (id, tenant_id, name, is_default)
VALUES ('00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000010', 'Settings Main', true);
SET LOCAL session_replication_role = replica;
INSERT INTO public.members (id, tenant_id, branch_id, user_id, full_name, phone)
VALUES ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000010',
        '00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000001',
        'H59 Settings Member', '+919900000100');
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000001',
    'app_role', 'member',
    'tenant_id', '00000000-0000-0000-0000-000000000010',
    'member_id', '00000000-0000-0000-0000-000000000100'
  )::text,
  true
);

SELECT is(
  (SELECT array_agg(keys.key ORDER BY keys.key)
     FROM public.read_member_portal_settings() AS settings
     CROSS JOIN LATERAL jsonb_object_keys(to_jsonb(settings)) AS keys(key)),
  ARRAY['city', 'state', 'streak_rule_type', 'week_start_day', 'weekly_goal_default'],
  'member command exposes exactly the five safe settings fields'
);
SELECT is(
  (SELECT to_jsonb(settings)
     FROM public.read_member_portal_settings() AS settings),
  '{"city":"Pune","state":"Maharashtra","weekly_goal_default":4,"week_start_day":1,"streak_rule_type":"weekly_goal"}'::jsonb,
  'complete canonical member identity is accepted and receives its own five-field presentation row'
);

SELECT throws_ok(
  $$SELECT public.read_member_portal_settings()$$,
  NULL,
  NULL,
  'wrong role is rejected'
);

SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000001',
    'app_role', 'front_desk',
    'tenant_id', '00000000-0000-0000-0000-000000000010'
  )::text,
  true
);
SELECT throws_ok($$SELECT public.read_member_portal_settings()$$, NULL, NULL, 'incomplete identity is rejected');

SELECT set_config('request.jwt.claims', '{}'::text, true);
SELECT throws_ok($$SELECT public.read_member_portal_settings()$$, NULL, NULL, 'unauthenticated identity is rejected');

SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000001',
    'app_role', 'member',
    'tenant_id', '00000000-0000-0000-0000-000000000011',
    'member_id', '00000000-0000-0000-0000-000000000100'
  )::text,
  true
);
SELECT throws_ok($$SELECT public.read_member_portal_settings()$$, NULL, NULL, 'cross-tenant identity is rejected');

SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000001',
    'app_role', 'member',
    'tenant_id', '00000000-0000-0000-0000-000000000010',
    'member_id', '00000000-0000-0000-0000-000000000100',
    'staff_id', '00000000-0000-0000-0000-000000000021'
  )::text,
  true
);
SELECT throws_ok($$SELECT public.read_member_portal_settings()$$, NULL, NULL, 'mixed identity is rejected');

SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000001',
    'app_role', 'member',
    'tenant_id', '00000000-0000-0000-0000-000000000010',
    'member_id', '00000000-0000-0000-0000-000000000100'
  )::text,
  true
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.read_member_portal_settings() AS settings
    CROSS JOIN LATERAL jsonb_object_keys(to_jsonb(settings)) AS key
    WHERE key IN ('gstin', 'financial_config', 'organization_settings', 'tenant_id')
  ),
  'command does not expose settings rows or financial, GSTIN, or tenant fields'
);

SELECT * FROM finish();
ROLLBACK;
