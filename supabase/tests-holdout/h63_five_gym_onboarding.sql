-- PILOT-006 independent holdout: five-gym atomic onboarding rehearsal.
-- This deliberately uses a fresh, unmistakably synthetic namespace.
BEGIN;

SELECT plan(20);

CREATE TEMP TABLE h63_results (
  request_key text PRIMARY KEY,
  result jsonb NOT NULL
);

DO $$
DECLARE
  h63_admin uuid := '63000000-0000-4000-8000-000000000063';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    h63_admin, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'h63-pilot-admin@gymloop.invalid', '', now(),
    '{"app_role":"super_admin"}'::jsonb,
    '{}'::jsonb, now(), now()
  );

  INSERT INTO public.platform_users (user_id, role, full_name, email, is_active)
  VALUES (h63_admin, 'super_admin', 'H63 Pilot Administrator',
    'h63-pilot-admin@gymloop.invalid', true);

  PERFORM set_config('request.jwt.claim.sub', h63_admin::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.app_role', 'super_admin', true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', h63_admin::text,
    'role', 'authenticated',
    'app_role', 'super_admin',
    'app_metadata', json_build_object('app_role', 'super_admin')
  )::text, true);
END;
$$;

GRANT SELECT, INSERT ON h63_results TO authenticated;
SET LOCAL ROLE authenticated;

INSERT INTO h63_results (request_key, result)
SELECT
  format('h63-onboard-%s', n),
  to_jsonb(public.onboard_gym(
    ('63000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    format('H63 Synthetic Gym %s', n),
    'Asia/Kolkata',
    'INR',
    (SELECT enumlabel::public.gym_preset
       FROM pg_enum
      WHERE enumtypid = 'public.gym_preset'::regtype
      ORDER BY enumsortorder
      LIMIT 1),
    format('H63 Owner %s', n),
    format('h63-owner-%s@gymloop.invalid', n),
    format('h63-onboard-%s', n)
  ))
FROM generate_series(1, 5) AS n;

SELECT is((SELECT count(*) FROM h63_results), 5::bigint,
  'five onboarding requests each return a result');

SELECT is((SELECT count(*) FROM public.organizations
  WHERE name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'five synthetic trial organizations exist');

SELECT is((SELECT count(DISTINCT gym_code) FROM public.organizations
  WHERE name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'each synthetic organization has a distinct code');

SELECT is((SELECT count(*) FROM public.organizations
  WHERE name LIKE 'H63 Synthetic Gym %' AND char_length(gym_code) = 6), 5::bigint,
  'every synthetic organization code is six characters');

SELECT is((SELECT count(*) FROM public.organizations
  WHERE name LIKE 'H63 Synthetic Gym %' AND status = 'trial'), 5::bigint,
  'every synthetic organization starts in trial');

SELECT is((SELECT count(*) FROM public.organization_settings s
  JOIN public.organizations o ON o.id = s.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'exactly one settings row is created per gym');

SELECT is((SELECT count(*) FROM public.branches b
  JOIN public.organizations o ON o.id = b.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %' AND b.is_default), 5::bigint,
  'exactly one default branch is created per gym');

SELECT is((SELECT count(*) FROM public.messaging_wallets w
  JOIN public.organizations o ON o.id = w.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %' AND w.balance_credits = 0), 5::bigint,
  'exactly one zero-credit wallet is created per gym');

SELECT is((SELECT count(*) FROM public.staff p
  JOIN public.organizations o ON o.id = p.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %'
    AND p.role = 'gym_owner' AND p.is_active AND p.user_id IS NULL), 5::bigint,
  'one active unlinked owner profile is created per gym');

SELECT is((SELECT count(*) FROM public.audit_log
  WHERE record_id IN (SELECT id FROM public.organizations WHERE name LIKE 'H63 Synthetic Gym %')), 5::bigint,
  'one keyed onboarding audit event is created per gym');

INSERT INTO h63_results (request_key, result)
SELECT format('h63-onboard-%s-replay', n), to_jsonb(public.onboard_gym(
  ('63000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  format('H63 Synthetic Gym %s', n),
  'Asia/Kolkata', 'INR',
  (SELECT enumlabel::public.gym_preset FROM pg_enum
    WHERE enumtypid = 'public.gym_preset'::regtype ORDER BY enumsortorder LIMIT 1),
  format('H63 Owner %s', n),
  format('h63-owner-%s@gymloop.invalid', n),
  format('h63-onboard-%s', n)
))
FROM generate_series(1, 5) AS n;

SELECT is((SELECT count(*) FROM public.organizations
  WHERE name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'exact replays create no additional organization');

SELECT is((SELECT count(*) FROM public.organization_settings s JOIN public.organizations o ON o.id=s.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'exact replays create no additional settings row');

SELECT is((SELECT count(*) FROM public.branches b JOIN public.organizations o ON o.id=b.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %' AND b.is_default), 5::bigint,
  'exact replays create no additional default branch');

SELECT is((SELECT count(*) FROM public.messaging_wallets w JOIN public.organizations o ON o.id=w.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'exact replays create no additional wallet');

SELECT is((SELECT count(*) FROM public.staff p JOIN public.organizations o ON o.id=p.tenant_id
  WHERE o.name LIKE 'H63 Synthetic Gym %' AND p.role='gym_owner'), 5::bigint,
  'exact replays create no additional owner profile');

SELECT is((SELECT count(*) FROM public.audit_log
  WHERE record_id IN (SELECT id FROM public.organizations WHERE name LIKE 'H63 Synthetic Gym %')), 5::bigint,
  'exact replays create no additional audit event');

SELECT is((SELECT count(*) FROM h63_results r
  JOIN h63_results replay ON replay.request_key = r.request_key || '-replay'
  WHERE r.request_key NOT LIKE '%-replay' AND r.result = replay.result), 5::bigint,
  'each exact replay returns its original result');

SELECT throws_ok(
  $$SELECT public.onboard_gym(
    '63000000-0000-4000-8000-000000000001'::uuid,
    'H63 Synthetic Gym 1 changed', 'Asia/Kolkata', 'INR',
    (SELECT enumlabel::public.gym_preset FROM pg_enum WHERE enumtypid='public.gym_preset'::regtype ORDER BY enumsortorder LIMIT 1),
    'H63 Owner 1', 'h63-owner-1@gymloop.invalid', 'h63-onboard-1'
  )$$,
  'GL068',
  'Idempotency conflict',
  'reused onboarding key with changed facts is refused'
);

SELECT is((SELECT count(*) FROM public.organizations WHERE name LIKE 'H63 Synthetic Gym %'), 5::bigint,
  'changed-facts conflict creates no organization');
SELECT is((SELECT count(*) FROM public.audit_log
  WHERE request_key IN (SELECT ('63000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid FROM generate_series(1, 5) AS n)), 5::bigint,
  'changed-facts conflict creates no audit event');

SELECT * FROM finish();
ROLLBACK;

BEGIN;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.organizations WHERE name LIKE 'H63 Synthetic Gym %') <> 0 THEN
    RAISE EXCEPTION 'PILOT-006 postflight retained a synthetic organization';
  END IF;
  IF (SELECT count(*) FROM public.organization_settings s JOIN public.organizations o ON o.id = s.tenant_id
      WHERE o.name LIKE 'H63 Synthetic Gym %') <> 0 THEN
    RAISE EXCEPTION 'PILOT-006 postflight retained synthetic settings';
  END IF;
  IF (SELECT count(*) FROM public.branches b JOIN public.organizations o ON o.id = b.tenant_id
      WHERE o.name LIKE 'H63 Synthetic Gym %') <> 0 THEN
    RAISE EXCEPTION 'PILOT-006 postflight retained a synthetic branch';
  END IF;
  IF (SELECT count(*) FROM public.audit_log
      WHERE request_key IN (SELECT ('63000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
                            FROM generate_series(1, 5) AS n)) <> 0 THEN
    RAISE EXCEPTION 'PILOT-006 postflight retained a synthetic audit event';
  END IF;
  IF (SELECT count(*) FROM auth.users WHERE id = '63000000-0000-4000-8000-000000000063'::uuid) <> 0 THEN
    RAISE EXCEPTION 'PILOT-006 postflight retained a synthetic Auth identity';
  END IF;
END;
$$;
ROLLBACK;
