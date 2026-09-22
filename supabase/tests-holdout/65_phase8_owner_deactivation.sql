BEGIN;

SET LOCAL ROLE postgres;
SET LOCAL search_path = extensions, public;

SELECT plan(17);

CREATE TEMP TABLE pilot_deactivation_context (
  platform_user uuid NOT NULL,
  owner_user uuid NOT NULL,
  support_user uuid NOT NULL,
  tenant_id uuid NOT NULL,
  foreign_tenant_id uuid NOT NULL,
  owner_staff_id uuid NOT NULL,
  foreign_staff_id uuid NOT NULL,
  request_key uuid NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE pilot_deactivation_results (first_result jsonb NOT NULL, replay_result jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pilot_deactivation_claims (claims jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pilot_deactivation_errors (name text NOT NULL, sqlstate text, detail text) ON COMMIT DROP;

GRANT ALL ON pilot_deactivation_context, pilot_deactivation_results,
  pilot_deactivation_claims, pilot_deactivation_errors TO authenticated;

INSERT INTO auth.users (id, email)
VALUES
  ('30000000-0000-0000-0000-000000000001', 'pilot-deactivation-admin@example.test'),
  ('30000000-0000-0000-0000-000000000002', 'pilot-deactivation-owner@example.test'),
  ('30000000-0000-0000-0000-000000000003', 'pilot-deactivation-support@example.test');

INSERT INTO public.platform_users (user_id, role, full_name, email, is_active)
VALUES
  ('30000000-0000-0000-0000-000000000001', 'super_admin', 'Pilot deactivation admin', 'pilot-deactivation-admin@example.test', true),
  ('30000000-0000-0000-0000-000000000003', 'platform_support', 'Pilot deactivation support', 'pilot-deactivation-support@example.test', true);

SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated","app_role":"super_admin"}';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  onboarding jsonb;
  tenant_id uuid;
  staff_id uuid;
BEGIN
  onboarding := public.onboard_gym(
    '30000000-0000-0000-0000-000000000011',
    'Pilot Deactivation Gym A',
    'Asia/Kolkata',
    'INR',
    'premium_studio',
    'Pilot Deactivation Branch A',
    'Pilot Deactivation Owner',
    'pilot-deactivation-owner@example.test'
  );
  tenant_id := (onboarding #>> '{organization,tenantId}')::uuid;
  staff_id := (onboarding ->> 'ownerStaffId')::uuid;
  INSERT INTO pilot_deactivation_context
    (platform_user, owner_user, support_user, tenant_id, foreign_tenant_id, owner_staff_id, foreign_staff_id, request_key)
  VALUES
    ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000003', tenant_id,
     '00000000-0000-0000-0000-000000000000', staff_id,
     '00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000021');
END
$$;

DO $$
DECLARE
  onboarding jsonb;
  tenant_value uuid;
  staff_value uuid;
BEGIN
  onboarding := public.onboard_gym(
    '30000000-0000-0000-0000-000000000012',
    'Pilot Deactivation Gym B',
    'Asia/Kolkata',
    'INR',
    'premium_studio',
    'Pilot Deactivation Branch B',
    'Pilot Foreign Owner',
    'pilot-deactivation-foreign@example.test'
  );
  tenant_value := (onboarding #>> '{organization,tenantId}')::uuid;
  staff_value := (onboarding ->> 'ownerStaffId')::uuid;
  UPDATE pilot_deactivation_context
  SET foreign_tenant_id = tenant_value, foreign_staff_id = staff_value;
END
$$;

DO $$
DECLARE
  c record;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  PERFORM public.link_gym_owner(
    c.tenant_id,
    c.owner_staff_id,
    NULL,
    'pilot-deactivation-owner@example.test',
    '30000000-0000-0000-0000-000000000020'
  );
END
$$;

-- A real session row gives the identity trigger an existing session to revoke.
SET LOCAL ROLE postgres;
DO $$
DECLARE
  c record;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  INSERT INTO auth.sessions (id, user_id)
  VALUES ('30000000-0000-0000-0000-000000000031', c.owner_user);
END
$$;

-- Gym owner, platform support, and preview-shaped callers cannot execute the command.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated","app_role":"gym_owner"}';
DO $$
DECLARE
  c record;
  state text;
  detail text;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, c.request_key);
    INSERT INTO pilot_deactivation_errors VALUES ('gym_owner', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('gym_owner', state, detail);
  END;
END
$$;

SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated","app_role":"platform_support"}';
DO $$
DECLARE
  c record;
  state text;
  detail text;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, c.request_key);
    INSERT INTO pilot_deactivation_errors VALUES ('platform_support', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('platform_support', state, detail);
  END;
END
$$;

SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated","app_role":"super_admin","tenant_id":"00000000-0000-0000-0000-000000000000","impersonation_session_id":"30000000-0000-0000-0000-000000000041"}';
DO $$
DECLARE
  c record;
  state text;
  detail text;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, c.request_key);
    INSERT INTO pilot_deactivation_errors VALUES ('preview', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('preview', state, detail);
  END;
END
$$;

SELECT ok((SELECT sqlstate <> 'NO_ERROR' FROM pilot_deactivation_errors WHERE name = 'gym_owner'), 'PILOT-008: gym owner caller is refused');
SELECT ok((SELECT sqlstate <> 'NO_ERROR' FROM pilot_deactivation_errors WHERE name = 'platform_support'), 'PILOT-008: platform support caller is refused');
SELECT ok((SELECT sqlstate <> 'NO_ERROR' FROM pilot_deactivation_errors WHERE name = 'preview'), 'PILOT-008: preview caller is refused');

-- A non-preview super-admin deactivates exactly the linked owner.
SET LOCAL request.jwt.claims = '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated","app_role":"super_admin"}';
DO $$
DECLARE
  c record;
  first_result jsonb;
  replay_result jsonb;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  first_result := public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, c.request_key);
  replay_result := public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, c.request_key);
  INSERT INTO pilot_deactivation_results VALUES (first_result, replay_result);
END
$$;

SELECT is((SELECT count(*) FROM public.staff s, pilot_deactivation_context c
           WHERE s.id = c.owner_staff_id AND s.tenant_id = c.tenant_id
             AND s.user_id = c.owner_user AND s.is_active = false), 1::bigint,
          'PILOT-008: exactly the linked owner row is inactive');
SELECT is((SELECT count(*) FROM public.staff s, pilot_deactivation_context c
           WHERE s.id = c.owner_staff_id AND s.full_name = 'Pilot Deactivation Owner'), 1::bigint,
          'PILOT-008: owner history remains');
SELECT is((SELECT replay_result FROM pilot_deactivation_results), (SELECT first_result FROM pilot_deactivation_results),
          'PILOT-008: exact keyed replay returns original result');
SELECT is((SELECT count(*) FROM public.audit_log a, pilot_deactivation_context c
           WHERE a.tenant_id = c.tenant_id AND a.action = 'staff.owner_deactivated'
             AND a.record_type = 'staff' AND a.record_id = c.owner_staff_id
             AND a.request_key = c.request_key AND a.actor_user_id = c.platform_user
             AND (a.before ->> 'is_active') = 'true' AND (a.after ->> 'is_active') = 'false'), 1::bigint,
          'PILOT-008: one keyed audit records actor and before/after state');
SET LOCAL ROLE postgres;
SELECT is((SELECT count(*) FROM auth.sessions s, pilot_deactivation_context c WHERE s.user_id = c.owner_user), 0::bigint,
          'PILOT-008: identity trigger revokes the owner session');
SET LOCAL ROLE authenticated;

-- Reusing the key with changed facts is GL068; stale and foreign targets are refused.
DO $$
DECLARE
  c record;
  state text;
  detail text;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.platform_user, c.request_key);
    INSERT INTO pilot_deactivation_errors VALUES ('changed', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('changed', state, detail);
  END;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.owner_staff_id, c.owner_user, '30000000-0000-0000-0000-000000000022');
    INSERT INTO pilot_deactivation_errors VALUES ('stale', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('stale', state, detail);
  END;
  BEGIN
    PERFORM public.deactivate_gym_owner(c.tenant_id, c.foreign_staff_id, c.owner_user, '30000000-0000-0000-0000-000000000023');
    INSERT INTO pilot_deactivation_errors VALUES ('foreign', 'NO_ERROR', '');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, detail = PG_EXCEPTION_DETAIL;
    INSERT INTO pilot_deactivation_errors VALUES ('foreign', state, detail);
  END;
END
$$;

SELECT is((SELECT sqlstate FROM pilot_deactivation_errors WHERE name = 'changed'), 'GL068', 'PILOT-008: changed facts raise GL068');
SELECT is((SELECT detail FROM pilot_deactivation_errors WHERE name = 'changed'), 'idempotency_conflict', 'PILOT-008: changed facts identify idempotency_conflict');
SELECT ok((SELECT sqlstate <> 'NO_ERROR' FROM pilot_deactivation_errors WHERE name = 'stale'), 'PILOT-008: stale linked-user or inactive state is refused');
SELECT ok((SELECT sqlstate <> 'NO_ERROR' FROM pilot_deactivation_errors WHERE name = 'foreign'), 'PILOT-008: foreign staff is refused');
SELECT is((SELECT count(*) FROM public.audit_log a, pilot_deactivation_context c
           WHERE a.tenant_id = c.tenant_id AND a.action = 'staff.owner_deactivated'
             AND a.record_id = c.owner_staff_id AND a.request_key = c.request_key), 1::bigint,
          'PILOT-008: refused retries add no audit row');

-- Fresh hook resolution for the inactive owner carries no Gymloop claims.
SET LOCAL ROLE postgres;
DO $$
DECLARE
  c record;
BEGIN
  SELECT * INTO c FROM pilot_deactivation_context;
  INSERT INTO pilot_deactivation_claims(claims)
  SELECT (app.custom_access_token_hook(jsonb_build_object(
    'user_id', c.owner_user,
    'claims', jsonb_build_object('sub', c.owner_user, 'role', 'authenticated')
  )) -> 'claims');
END
$$;

SELECT ok(NOT ((SELECT claims FROM pilot_deactivation_claims) ? 'app_role'), 'PILOT-008: inactive owner receives no app_role');
SELECT ok(NOT ((SELECT claims FROM pilot_deactivation_claims) ? 'tenant_id'), 'PILOT-008: inactive owner receives no tenant_id');
SELECT ok(NOT ((SELECT claims FROM pilot_deactivation_claims) ? 'staff_id'), 'PILOT-008: inactive owner receives no staff_id');

SELECT is((SELECT count(*) FROM public.organizations o, pilot_deactivation_context c
           WHERE o.id IN (c.tenant_id, c.foreign_tenant_id)), 2::bigint,
          'PILOT-008: both synthetic tenants existed during the rehearsal');

SELECT * FROM finish();

ROLLBACK;
