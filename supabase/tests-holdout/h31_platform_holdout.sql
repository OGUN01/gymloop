BEGIN;

SELECT plan(49);

-- H31 is deliberately self-contained: the keys are also the tenants it creates.
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
VALUES
  ('31000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'h31-admin@example.test', 'not-used', statement_timestamp(), '{"existing":"admin"}', '{"display":"Admin"}'),
  ('31000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'h31-owner@example.test', 'not-used', statement_timestamp(), '{"other":"preserved"}', '{"nickname":"Owner"}'),
  ('31000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'h31-other@example.test', 'not-used', statement_timestamp(), '{}'::jsonb, '{}'::jsonb);

INSERT INTO public.platform_users (user_id, role, full_name, email, is_active)
VALUES
  ('31000000-0000-4000-8000-000000000001', 'super_admin', 'H31 Admin', 'h31-admin@example.test', true),
  ('31000000-0000-4000-8000-000000000003', 'platform_support', 'H31 Support', 'h31-other@example.test', true);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin"}',
  true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$ SELECT public.onboard_gym(
    '31000000-0000-4000-8000-000000000101', ' H31 Platform Gym ', 'Asia/Kolkata', 'INR',
    'neighbourhood_gym', ' H31 Main ', ' H31 Owner ', NULL
  ) $$,
  'a complete non-impersonating super admin can onboard a gym'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000101'::uuid),
  1::bigint,
  'onboarding creates exactly its request-key organization'
);
SELECT is(
  (SELECT status::text FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000101'::uuid),
  'trial',
  'onboarding reaches trial in its one transaction'
);
SELECT is(
  (SELECT count(*) FROM public.organization_settings WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid),
  1::bigint,
  'onboarding creates one settings row'
);
SELECT is(
  (SELECT count(*) FROM public.branches WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND is_default),
  1::bigint,
  'onboarding creates exactly one default branch'
);
SELECT is(
  (SELECT balance_credits FROM public.messaging_wallets WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid),
  0::bigint,
  'onboarding creates a zero-credit wallet'
);
SELECT is(
  (SELECT count(*) FROM public.staff WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND role = 'gym_owner' AND is_active AND user_id IS NULL),
  1::bigint,
  'onboarding creates one unlinked active owner profile'
);
SELECT is(
  (SELECT request_facts->>'command' FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND action = 'organization.onboarded'),
  'onboard_gym',
  'onboarding writes keyed command evidence rather than a mutable ledger'
);
SELECT is(
  (SELECT request_facts->'request'->>'name' FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND action = 'organization.onboarded'),
  'H31 Platform Gym',
  'onboarding audit records normalized immutable request facts'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.onboard_gym('31000000-0000-4000-8000-000000000102', 'Atomicity', 'Not/AZone', 'INR', 'neighbourhood_gym', 'Atomicity', 'Owner', NULL) $$,
  '22023', NULL,
  'invalid onboarding input refuses before leaving a partial organization'
);
RESET ROLE;
SELECT is(
  (SELECT count(*) FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000102'::uuid),
  0::bigint,
  'failed onboarding leaves no organization behind'
);
SET LOCAL ROLE authenticated;
SELECT is(
  public.onboard_gym('31000000-0000-4000-8000-000000000101', ' H31 Platform Gym ', 'Asia/Kolkata', 'INR', 'neighbourhood_gym', ' H31 Main ', ' H31 Owner ', NULL),
  public.onboard_gym('31000000-0000-4000-8000-000000000101', ' H31 Platform Gym ', 'Asia/Kolkata', 'INR', 'neighbourhood_gym', ' H31 Main ', ' H31 Owner ', NULL),
  'identical onboarding replay returns the recorded public result'
);
SELECT throws_ok(
  $$ SELECT public.onboard_gym('31000000-0000-4000-8000-000000000101', 'Different', 'Asia/Kolkata', 'INR', 'neighbourhood_gym', 'H31 Main', 'H31 Owner', NULL) $$,
  'GL068', NULL,
  'reusing an onboarding key with changed facts is a conflict'
);
SELECT throws_ok(
  $$ UPDATE public.organizations SET tier = 'basic' WHERE id = '31000000-0000-4000-8000-000000000101'::uuid $$,
  'GL049', NULL,
  'an authenticated super-admin claim cannot bypass tier assignment with direct SQL'
);
SELECT throws_ok(
  $$ UPDATE public.organizations SET status = 'active' WHERE id = '31000000-0000-4000-8000-000000000101'::uuid $$,
  'GL049', NULL,
  'direct authenticated status writes cannot bypass the platform command'
);
SELECT throws_ok(
  $$ INSERT INTO public.organizations (id, name, gym_code, timezone, currency, status) VALUES ('31000000-0000-4000-8000-000000000199', 'Bypass', 'H31BAD', 'Asia/Kolkata', 'INR', 'trial') $$,
  'GL049', NULL,
  'direct authenticated organization creation is refused before it can form a partial gym'
);

RESET ROLE;
CREATE TEMP TABLE h31_ids AS
SELECT
  '31000000-0000-4000-8000-000000000101'::uuid AS tenant_id,
  (SELECT id FROM public.staff WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND role = 'gym_owner') AS owner_staff_id;

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ UPDATE public.staff SET user_id = '31000000-0000-4000-8000-000000000002'::uuid WHERE id = (SELECT owner_staff_id FROM h31_ids) $$,
  'GL049', NULL,
  'direct authenticated owner Auth binding is refused'
);
SELECT throws_ok(
  $$ SELECT public.link_gym_owner('31000000-0000-4000-8000-000000000101', (SELECT owner_staff_id FROM h31_ids), NULL, 'nobody@example.test', '31000000-0000-4000-8000-000000000111') $$,
  '22023', NULL,
  'owner linking does not expose or accept an absent Auth account'
);
SELECT lives_ok(
  $$ SELECT public.link_gym_owner('31000000-0000-4000-8000-000000000101', (SELECT owner_staff_id FROM h31_ids), NULL, ' H31-OWNER@example.test ', '31000000-0000-4000-8000-000000000112') $$,
  'owner linking resolves one exact normalized existing Auth user'
);
SELECT throws_ok(
  $$ SELECT public.link_gym_owner('31000000-0000-4000-8000-000000000101', (SELECT owner_staff_id FROM h31_ids), NULL, 'h31-other@example.test', '31000000-0000-4000-8000-000000000114') $$,
  '22023', NULL,
  'a platform identity is never a candidate owner account'
);

RESET ROLE;
SELECT is(
  (SELECT user_id FROM public.staff WHERE id = (SELECT owner_staff_id FROM h31_ids)),
  '31000000-0000-4000-8000-000000000002'::uuid,
  'owner link changes only the selected owner association'
);
SELECT is(
  (SELECT raw_app_meta_data->>'active_tenant_id' FROM auth.users WHERE id = '31000000-0000-4000-8000-000000000002'::uuid),
  '31000000-0000-4000-8000-000000000101',
  'owner link writes the protected preferred tenant'
);
SELECT is(
  (SELECT raw_app_meta_data->>'other' FROM auth.users WHERE id = '31000000-0000-4000-8000-000000000002'::uuid),
  'preserved',
  'owner link preserves unrelated protected Auth metadata'
);
INSERT INTO auth.sessions (id, user_id, created_at, updated_at)
VALUES ('31000000-0000-4000-8000-000000000121', '31000000-0000-4000-8000-000000000002', statement_timestamp(), statement_timestamp());

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ UPDATE public.staff SET role = 'gym_manager' WHERE id = (SELECT owner_staff_id FROM h31_ids) $$,
  'GL049', NULL,
  'a linked owner cannot be demoted directly as an owner-link bypass'
);
SELECT is(
  public.link_gym_owner('31000000-0000-4000-8000-000000000101', (SELECT owner_staff_id FROM h31_ids), '31000000-0000-4000-8000-000000000002', 'h31-owner@example.test', '31000000-0000-4000-8000-000000000113')->>'ownerAccessPending',
  'false',
  'an unchanged owner link is an inert successful no-op'
);

RESET ROLE;
SELECT is(
  (SELECT count(*) FROM auth.sessions WHERE id = '31000000-0000-4000-8000-000000000121'::uuid),
  1::bigint,
  'an exact owner-link no-op does not rewrite or revoke sessions'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin"}',
  true
);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000101', 'trial', 'active', NULL, '31000000-0000-4000-8000-000000000131') $$,
  'activation succeeds only after the onboarding facts and linked owner make readiness complete'
);
SELECT throws_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000101', 'active', 'pending_approval', NULL, '31000000-0000-4000-8000-000000000132') $$,
  'GL050', NULL,
  'the canonical status graph rejects an active to pending edge'
);
SELECT throws_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000101', 'active', 'suspended', '   ', '31000000-0000-4000-8000-000000000133') $$,
  '22023', NULL,
  'a changing suspension requires a nonblank normalized reason'
);

RESET ROLE;
SELECT ok(
  (SELECT activated_at IS NOT NULL FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000101'::uuid),
  'first activation server-stamps activated_at'
);
CREATE TEMP TABLE h31_state AS
SELECT activated_at, (SELECT count(*) FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid) AS audit_count
FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000101'::uuid;

SET LOCAL ROLE authenticated;
SELECT is(
  public.set_gym_status('31000000-0000-4000-8000-000000000101', 'active', 'active', NULL, '31000000-0000-4000-8000-000000000134')->'organization'->>'status',
  'active',
  'same-state status is an inert no-op'
);

RESET ROLE;
SELECT is(
  (SELECT activated_at FROM public.organizations WHERE id = '31000000-0000-4000-8000-000000000101'::uuid),
  (SELECT activated_at FROM h31_state),
  'a status no-op does not touch activation timing'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid),
  (SELECT audit_count FROM h31_state),
  'a status no-op neither reserves evidence nor appends audit history'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000101', 'active', 'suspended', 'H31 support check', '31000000-0000-4000-8000-000000000135') $$,
  'a deliberate suspension uses the platform lifecycle command'
);
SELECT throws_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000101', 'active', 'closed', 'stale', '31000000-0000-4000-8000-000000000136') $$,
  '40001', NULL,
  'a stale expected status is not converted to a successful retry'
);

RESET ROLE;
SELECT is(
  (SELECT request_facts->>'command' FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND action = 'organization.status_changed' ORDER BY occurred_at DESC LIMIT 1),
  'set_gym_status',
  'changing lifecycle commands append keyed, command-specific audit evidence'
);
SELECT is(
  (SELECT count(*) FROM auth.sessions WHERE user_id = '31000000-0000-4000-8000-000000000002'::uuid),
  0::bigint,
  'suspension revokes linked gym-user refresh sessions'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.set_gym_tier('31000000-0000-4000-8000-000000000101', NULL, 'growth', '31000000-0000-4000-8000-000000000141') $$,
  'tier assignment is a separate CAS platform command'
);
SELECT throws_ok(
  $$ SELECT public.set_gym_tier('31000000-0000-4000-8000-000000000101', NULL, 'pro', '31000000-0000-4000-8000-000000000142') $$,
  '40001', NULL,
  'tier CAS refuses an old expected value'
);

RESET ROLE;
CREATE TEMP TABLE h31_tier_audit AS
SELECT count(*) AS n FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND action = 'organization.tier_changed';
SET LOCAL ROLE authenticated;
SELECT is(
  public.set_gym_tier('31000000-0000-4000-8000-000000000101', 'growth', 'growth', '31000000-0000-4000-8000-000000000143')->>'tier',
  'growth',
  'same-tier assignment is an inert no-op'
);

RESET ROLE;
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE tenant_id = '31000000-0000-4000-8000-000000000101'::uuid AND action = 'organization.tier_changed'),
  (SELECT n FROM h31_tier_audit),
  'tier no-op does not append a commercial audit event'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin"}',
  true
);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.onboard_gym('31000000-0000-4000-8000-000000000103', 'H31 Unready', 'Asia/Kolkata', 'INR', 'functional_box', 'H31 Unready', 'Unlinked', NULL) $$,
  'a second fixture gym can remain deliberately owner-unlinked'
);
SELECT throws_ok(
  $$ SELECT public.set_gym_status('31000000-0000-4000-8000-000000000103', 'trial', 'active', NULL, '31000000-0000-4000-8000-000000000144') $$,
  'GL051', NULL,
  'activation refuses an owner-access incomplete gym'
);
RESET ROLE;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin","tenant_id":"31000000-0000-4000-8000-000000000101"}',
  true
);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.start_gym_preview('31000000-0000-4000-8000-000000000101', ' H31 suspended-gym support ', '31000000-0000-4000-8000-000000000151') $$,
  '42501', NULL,
  'a contradictory platform-plus-gym claim cannot start a preview'
);

RESET ROLE;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin"}',
  true
);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.start_gym_preview('31000000-0000-4000-8000-000000000101', ' H31 suspended-gym support ', '31000000-0000-4000-8000-000000000151') $$,
  'a clean super-admin identity may preview a suspended gym'
);

RESET ROLE;
SELECT is(
  has_function_privilege('authenticated', 'app.platform_onboarding_defaults()', 'EXECUTE'),
  false,
  'authenticated callers have no EXECUTE grant on the private onboarding-defaults helper'
);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated","app_role":"super_admin"}',
  true
);
SET LOCAL ROLE authenticated;
SELECT is(
  public.start_gym_preview('31000000-0000-4000-8000-000000000101', ' H31 suspended-gym support ', '31000000-0000-4000-8000-000000000151'),
  public.start_gym_preview('31000000-0000-4000-8000-000000000101', ' H31 suspended-gym support ', '31000000-0000-4000-8000-000000000151'),
  'preview retry returns the original hard-expiry result without reopening it'
);
SELECT throws_ok(
  $$ SELECT public.start_gym_preview('31000000-0000-4000-8000-000000000101', 'second open preview', '31000000-0000-4000-8000-000000000152') $$,
  '23505', NULL,
  'a different open preview is refused with only the named uniqueness error'
);
SELECT throws_ok(
  $$ SELECT public.end_expired_gym_preview('31000000-0000-4000-8000-000000000151') $$,
  '22023', NULL,
  'expired-preview recovery cannot end a still-live session'
);

SELECT * FROM finish();
ROLLBACK;
