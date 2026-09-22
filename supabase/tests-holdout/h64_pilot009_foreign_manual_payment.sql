-- PILOT-009 independent money-path holdout. The fixtures and all effects roll back.
BEGIN;

SELECT plan(14);

INSERT INTO public.organizations (id, name, gym_code, status)
VALUES
  ('90000009-0000-4000-8000-000000000001', 'Pilot holdout A', 'H9A001', 'active'),
  ('90000009-0000-4000-8000-000000000002', 'Pilot holdout B', 'H9B001', 'active');

INSERT INTO public.branches (id, tenant_id, name, is_default)
VALUES
  ('90000009-0001-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', 'A desk', true),
  ('90000009-0001-4000-8000-000000000002', '90000009-0000-4000-8000-000000000002', 'B desk', true);

INSERT INTO public.staff (id, tenant_id, role, full_name, is_active)
VALUES ('90000009-0002-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', 'gym_owner', 'Holdout owner A', true);

INSERT INTO public.members (id, tenant_id, branch_id, full_name, phone)
VALUES
  ('90000009-0003-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', '90000009-0001-4000-8000-000000000001', 'Holdout A one', '+919000000901'),
  ('90000009-0003-4000-8000-000000000002', '90000009-0000-4000-8000-000000000001', '90000009-0001-4000-8000-000000000001', 'Holdout A two', '+919000000902'),
  ('90000009-0003-4000-8000-000000000003', '90000009-0000-4000-8000-000000000002', '90000009-0001-4000-8000-000000000002', 'Holdout B one', '+919000000903');

INSERT INTO public.plans (id, tenant_id, name, duration_days, price_paise, currency)
VALUES
  ('90000009-0004-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', 'Holdout A plan', 14, 12500, 'INR'),
  ('90000009-0004-4000-8000-000000000002', '90000009-0000-4000-8000-000000000002', 'Holdout B plan', 14, 12500, 'INR');

INSERT INTO public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
VALUES
  ('90000009-0005-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', '90000009-0003-4000-8000-000000000001', '90000009-0004-4000-8000-000000000001', 'pending', current_date, current_date, 12500, 'INR'),
  ('90000009-0005-4000-8000-000000000002', '90000009-0000-4000-8000-000000000002', '90000009-0003-4000-8000-000000000003', '90000009-0004-4000-8000-000000000002', 'pending', current_date, current_date, 12500, 'INR');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"90000009-0006-4000-8000-000000000001","role":"authenticated","app_role":"gym_owner","tenant_id":"90000009-0000-4000-8000-000000000001","staff_id":"90000009-0002-4000-8000-000000000001"}', true);

SELECT lives_ok($$
  INSERT INTO public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, idempotency_key)
  VALUES ('90000009-0007-4000-8000-000000000001', '90000009-0000-4000-8000-000000000001', '90000009-0003-4000-8000-000000000001', '90000009-0005-4000-8000-000000000001', 12500, 'INR', 'paid', 'cash', '90000009-0002-4000-8000-000000000001', 'h64-own-control')
$$, 'A signed-in owner can record a same-gym manual payment');

RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.payments WHERE id = '90000009-0007-4000-8000-000000000001'), 1, 'control payment arrived once');
SELECT ok((SELECT status = 'active' AND periods_granted = 1 AND ends_on > starts_on FROM public.memberships WHERE id = '90000009-0005-4000-8000-000000000001'), 'control payment granted one period');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE tenant_id = '90000009-0000-4000-8000-000000000001' AND record_type = 'payment'), 1, 'control payment wrote one audit event');

SET LOCAL ROLE authenticated;
SELECT throws_ok($$
  INSERT INTO public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, idempotency_key)
  VALUES ('90000009-0007-4000-8000-000000000002', '90000009-0000-4000-8000-000000000001', '90000009-0003-4000-8000-000000000003', '90000009-0005-4000-8000-000000000002', 12500, 'INR', 'paid', 'cash', '90000009-0002-4000-8000-000000000001', 'h64-foreign-attempt')
$$);

RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.payments WHERE tenant_id IN ('90000009-0000-4000-8000-000000000001', '90000009-0000-4000-8000-000000000002')), 1, 'foreign attempt created no payment in either gym');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE tenant_id IN ('90000009-0000-4000-8000-000000000001', '90000009-0000-4000-8000-000000000002') AND record_type = 'payment'), 1, 'foreign attempt created no audit event');
SELECT ok((SELECT status = 'pending' AND periods_granted = 0 AND ends_on = starts_on FROM public.memberships WHERE id = '90000009-0005-4000-8000-000000000002'), 'foreign membership kept its unpaid period');
SELECT ok((SELECT status = 'active' AND periods_granted = 1 FROM public.memberships WHERE id = '90000009-0005-4000-8000-000000000001'), 'own paid period stayed unchanged');

SET LOCAL ROLE authenticated;
SELECT throws_ok($$
  INSERT INTO public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, idempotency_key)
  VALUES ('90000009-0007-4000-8000-000000000003', '90000009-0000-4000-8000-000000000001', '90000009-0003-4000-8000-000000000002', '90000009-0005-4000-8000-000000000001', 12500, 'INR', 'paid', 'cash', '90000009-0002-4000-8000-000000000001', 'h64-same-gym-mismatch')
$$, 'GL042');

RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.payments WHERE tenant_id = '90000009-0000-4000-8000-000000000001'), 1, 'same-gym member/membership mismatch created no payment');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE tenant_id = '90000009-0000-4000-8000-000000000001' AND record_type = 'payment'), 1, 'same-gym mismatch created no audit event');
SELECT ok((SELECT status = 'active' AND periods_granted = 1 FROM public.memberships WHERE id = '90000009-0005-4000-8000-000000000001'), 'same-gym mismatch granted no extra period');
SELECT ok((SELECT status = 'pending' AND periods_granted = 0 FROM public.memberships WHERE id = '90000009-0005-4000-8000-000000000002'), 'other-gym membership remains untouched');

SELECT * FROM finish();
ROLLBACK;
