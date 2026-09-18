BEGIN;

SELECT plan(9);

-- The command is a deliberately narrow member-facing read surface.
SELECT has_function(
  'public',
  'read_member_portal_settings',
  ARRAY[]::text[],
  'member portal settings command exists with no arguments'
);

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
     FROM LATERAL jsonb_object_keys(to_jsonb(public.read_member_portal_settings())) AS keys(key)),
  ARRAY['city', 'state', 'streak_rule_type', 'week_start_day', 'weekly_goal_default'],
  'member command exposes exactly the five safe settings fields'
);
SELECT ok(
  public.read_member_portal_settings() IS NOT NULL,
  'complete canonical member identity is accepted'
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
    'app_role', 'member',
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
    'organization_id', '00000000-0000-0000-0000-000000000011'
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
    FROM jsonb_object_keys(to_jsonb(public.read_member_portal_settings())) AS key
    WHERE key IN ('gstin', 'financial_config', 'organization_settings', 'tenant_id')
  ),
  'command does not expose settings rows or financial, GSTIN, or tenant fields'
);

SELECT * FROM finish();
ROLLBACK;
