BEGIN;

SET LOCAL ROLE postgres;
SET LOCAL search_path = extensions, public;

SELECT plan(19);

-- All identities, tenants, commands, and assertions are synthetic and live only
-- inside this transaction.  The fixed UUIDs make the postflight assertions
-- independent of any implementation-generated identifiers.
CREATE TEMP TABLE pilot_qa_context (
  owner_a uuid NOT NULL,
  owner_b uuid NOT NULL,
  tenant_a uuid NOT NULL,
  tenant_b uuid NOT NULL,
  staff_a uuid NOT NULL,
  staff_b uuid NOT NULL,
  link_key_a uuid NOT NULL,
  link_key_b uuid NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE pilot_qa_claims (claims jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pilot_qa_links (first_result jsonb NOT NULL, replay_result jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pilot_qa_mutation (affected bigint NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pilot_qa_deactivated (claims jsonb NOT NULL) ON COMMIT DROP;

GRANT ALL ON pilot_qa_context, pilot_qa_claims, pilot_qa_links, pilot_qa_mutation, pilot_qa_deactivated TO authenticated;

INSERT INTO auth.users (id, email)
VALUES
  ('10000000-0000-0000-0000-000000000099', 'pilot-platform@example.test'),
  ('10000000-0000-0000-0000-000000000001', 'pilot-owner-a@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'pilot-owner-b@example.test');

INSERT INTO public.platform_users (user_id, role, full_name, email, is_active)
VALUES (
  '10000000-0000-0000-0000-000000000099',
  'super_admin',
  'Pilot platform actor',
  'pilot-platform@example.test',
  true
);

SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000099","role":"authenticated","app_role":"super_admin"}';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  onboarding jsonb;
  tenant_id uuid;
  staff_id uuid;
BEGIN
  onboarding := public.onboard_gym(
    '20000000-0000-0000-0000-000000000001',
    'Pilot QA Gym A',
    'Asia/Kolkata',
    'INR',
    'premium_studio',
    'Pilot Branch A',
    'Pilot Owner A',
    'pilot-owner-a@example.test'
  );
  tenant_id := (onboarding #>> '{organization,tenantId}')::uuid;
  staff_id := (onboarding ->> 'ownerStaffId')::uuid;
  INSERT INTO pilot_qa_context(owner_a, owner_b, tenant_a, tenant_b, staff_a, staff_b, link_key_a, link_key_b)
  VALUES (
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    tenant_id,
    '00000000-0000-0000-0000-000000000000',
    staff_id,
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-0000-0000-000000000011',
    '20000000-0000-0000-0000-000000000012'
  );
END
$$;

DO $$
DECLARE
  onboarding jsonb;
  tenant_id uuid;
  staff_id uuid;
BEGIN
  onboarding := public.onboard_gym(
    '20000000-0000-0000-0000-000000000002',
    'Pilot QA Gym B',
    'Asia/Kolkata',
    'INR',
    'premium_studio',
    'Pilot Branch B',
    'Pilot Owner B',
    'pilot-owner-b@example.test'
  );
  tenant_id := (onboarding #>> '{organization,tenantId}')::uuid;
  staff_id := (onboarding ->> 'ownerStaffId')::uuid;
  UPDATE pilot_qa_context
  SET tenant_b = tenant_id, staff_b = staff_id;
END
$$;

-- An unlinked Auth user must be claimless before the owner-link command.
SET LOCAL ROLE postgres;
SELECT ok(
  NOT ((app.custom_access_token_hook(jsonb_build_object(
    'user_id', '10000000-0000-0000-0000-000000000001',
    'claims', jsonb_build_object('sub', '10000000-0000-0000-0000-000000000001', 'role', 'authenticated')
  )) -> 'claims') ? 'app_role'),
  'PILOT-007: unlinked owner has no app_role claim'
);
SELECT ok(
  NOT ((app.custom_access_token_hook(jsonb_build_object(
    'user_id', '10000000-0000-0000-0000-000000000001',
    'claims', jsonb_build_object('sub', '10000000-0000-0000-0000-000000000001', 'role', 'authenticated')
  )) -> 'claims') ? 'tenant_id'),
  'PILOT-007: unlinked owner has no tenant_id claim'
);

SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000099","role":"authenticated","app_role":"super_admin"}';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  c record;
  first_link jsonb;
  replay jsonb;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  first_link := public.link_gym_owner(c.tenant_a, c.staff_a, NULL, ' PILOT-OWNER-A@EXAMPLE.TEST ', c.link_key_a);
  replay := public.link_gym_owner(c.tenant_a, c.staff_a, NULL, ' PILOT-OWNER-A@EXAMPLE.TEST ', c.link_key_a);
  INSERT INTO pilot_qa_links(first_result, replay_result) VALUES (first_link, replay);
END
$$;

SELECT is((SELECT first_result ->> 'tenantId' FROM pilot_qa_links), (SELECT tenant_a::text FROM pilot_qa_context), 'PILOT-007: link returns tenantId');
SELECT is((SELECT first_result ->> 'ownerStaffId' FROM pilot_qa_links), (SELECT staff_a::text FROM pilot_qa_context), 'PILOT-007: link returns ownerStaffId');
SELECT is((SELECT first_result ->> 'userId' FROM pilot_qa_links), (SELECT owner_a::text FROM pilot_qa_context), 'PILOT-007: link returns userId');
SELECT is((SELECT first_result ->> 'ownerAccessPending' FROM pilot_qa_links), 'false', 'PILOT-007: owner access is not pending');
SELECT is((SELECT replay_result FROM pilot_qa_links), (SELECT first_result FROM pilot_qa_links), 'PILOT-007: exact link retry replays original result');
SELECT throws_ok(
  format($sql$SELECT public.link_gym_owner(%L::uuid, %L::uuid, NULL, %L, %L::uuid)$sql$,
    c.tenant_a, c.staff_a, 'changed@example.test', c.link_key_a),
  NULL,
  'PILOT-007: changed-facts replay is refused'
) FROM pilot_qa_context c;

SELECT is((SELECT count(*) FROM public.audit_log a, pilot_qa_context c
           WHERE a.tenant_id = c.tenant_a AND a.action = 'staff.owner_linked'
             AND a.record_id = c.staff_a), 1::bigint,
          'PILOT-007: one keyed owner_linked audit exists');

-- Link the second owner, then prove each fresh claim is restricted to its own gym.
DO $$
DECLARE
  c record;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  PERFORM public.link_gym_owner(c.tenant_b, c.staff_b, NULL, 'pilot-owner-b@example.test', c.link_key_b);
END
$$;

SET LOCAL ROLE postgres;
DO $$
DECLARE
  c record;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  INSERT INTO pilot_qa_claims(claims)
  SELECT app.custom_access_token_hook(jsonb_build_object(
    'user_id', c.owner_a,
    'claims', jsonb_build_object('sub', c.owner_a, 'role', 'authenticated')
  )) -> 'claims';
END
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', (SELECT claims::text FROM pilot_qa_claims), true);

DO $$
DECLARE
  c record;
  affected bigint;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  UPDATE public.organizations SET name = name WHERE id = c.tenant_b;
  GET DIAGNOSTICS affected = ROW_COUNT;
  INSERT INTO pilot_qa_mutation(affected) VALUES (affected);
END
$$;

SELECT is((SELECT claims ->> 'app_role' FROM pilot_qa_claims), 'gym_owner', 'PILOT-007: owner A receives gym_owner claim');
SELECT is((SELECT claims ->> 'tenant_id' FROM pilot_qa_claims), (SELECT tenant_a::text FROM pilot_qa_context), 'PILOT-007: owner A receives tenant A claim');
SELECT is((SELECT claims ->> 'staff_id' FROM pilot_qa_claims), (SELECT staff_a::text FROM pilot_qa_context), 'PILOT-007: owner A receives staff A claim');
SELECT is((SELECT count(*) FROM public.organizations WHERE id = (SELECT tenant_a FROM pilot_qa_context)), 1::bigint, 'PILOT-002: owner A reads own organization');
SELECT is((SELECT count(*) FROM public.organizations WHERE id = (SELECT tenant_b FROM pilot_qa_context)), 0::bigint, 'PILOT-002: owner A cannot read owner B organization');
SELECT is((SELECT affected FROM pilot_qa_mutation), 0::bigint, 'PILOT-002: owner A foreign mutation affects zero rows');

-- Deactivation is authorized by the platform actor, and a fresh hook is then claimless.
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000099","role":"authenticated","app_role":"super_admin"}';
DO $$
DECLARE
  c record;
  claims jsonb;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  UPDATE public.staff SET is_active = false WHERE id = c.staff_a;
END
$$;

SET LOCAL ROLE postgres;
DO $$
DECLARE
  c record;
  claims jsonb;
BEGIN
  SELECT * INTO c FROM pilot_qa_context;
  claims := (app.custom_access_token_hook(jsonb_build_object(
    'user_id', c.owner_a,
    'claims', jsonb_build_object('sub', c.owner_a, 'role', 'authenticated')
  )) -> 'claims');
  INSERT INTO pilot_qa_deactivated(claims) VALUES (claims);
END
$$;

SELECT ok(NOT ((SELECT claims FROM pilot_qa_deactivated) ? 'app_role'), 'PILOT-007: deactivated owner has no app_role claim');
SELECT ok(NOT ((SELECT claims FROM pilot_qa_deactivated) ? 'tenant_id'), 'PILOT-007: deactivated owner has no tenant_id claim');
SELECT ok(NOT ((SELECT claims FROM pilot_qa_deactivated) ? 'staff_id'), 'PILOT-007: deactivated owner has no staff_id claim');

SELECT is((SELECT count(*) FROM public.organizations o, pilot_qa_context c
           WHERE o.id IN (c.tenant_a, c.tenant_b)), 2::bigint,
          'PILOT-007: both synthetic tenants existed during the rehearsal');

SELECT * FROM finish();

ROLLBACK;
