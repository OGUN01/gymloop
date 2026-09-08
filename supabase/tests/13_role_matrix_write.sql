-- 13_role_matrix_write - what each of the seven roles may WRITE inside a gym
-- it belongs to, from openspec/changes/phase-2-identity-and-tenancy/design.md
-- sections 8.1 and 8.3 and .../specs/authorization/spec.md.
--
-- THE TWO FAILURE SIGNATURES, AND WHY THIS FILE IS ORGANISED AROUND THEM
--
-- design.md 8.1 splits the gym-side policy in two: `<t>_tenant_select` carries
-- the read gate for SELECT, `<t>_tenant_write` carries the write gate on both
-- clauses for ALL. That split is not a style choice, it is what produces the
-- behaviour the spec states, and it makes the two refusals different:
--
--   * A refused UPDATE affects ZERO ROWS and raises nothing. The write
--     policy's USING is false, so the row is not among the rows the update
--     considers. Nothing has happened, and the caller cannot tell "you may not
--     write this" from "there is no such row" -- which is Phase 1's documented
--     semantics, argued in docs/data-model.md: "a policy that raised would let
--     a caller tell 'nothing here' apart from 'wrong tenant'". An error on
--     update is an existence oracle inside the tenant.
--
--   * A refused INSERT raises 42501. There is no existing row for a USING
--     clause to filter, so WITH CHECK is the only gate an insert meets, and a
--     failed WITH CHECK is an error by definition.
--
-- Under the shape design.md's first draft had -- one `for all` policy, read
-- gate on USING, write gate on WITH CHECK -- a refused UPDATE passes USING,
-- fails WITH CHECK and raises 42501. Every zero-row assertion in this file
-- fails against that shape, and that is the point: this file is what tells the
-- two shapes apart at run time, and 04_contract_meta is what tells them apart
-- in the catalogue.
--
-- WHAT THIS FILE COVERS EXHAUSTIVELY, AND WHAT IT SAMPLES
--
-- Exhaustive: the eighteen tables where the matrix's WRITE gate is NARROWER
-- than its READ gate. Those eighteen are where an implementation fails and
-- where nothing else catches it -- a `<t>_tenant_write` built by copying
-- `<t>_tenant_select`'s predicate passes every read test in
-- 12_role_matrix_read, passes every write test on the other eighteen tables,
-- and is wrong on exactly these. Each is asserted with the role that sits just
-- outside the write gate and just inside the read gate:
--
--   gym_manager, denied by `= 'gym_owner'`  : organizations, staff, razorpay_accounts
--   front_desk,  denied by `is_gym_admin()` : organization_settings, branches, plans,
--                                             coupons, refunds, organization_holidays,
--                                             addon_products, notifications,
--                                             message_templates
--   trainer,     denied by `is_front_office()`: members, memberships, membership_pauses,
--                                             attendance, attendance_corrections,
--                                             addon_orders
--
-- Sampled: the twelve tables whose write gate EQUALS their read gate get two
-- probes rather than twelve, because a wrong gate there is already visible in
-- 12_role_matrix_read's vectors and in 04_contract_meta's catalogue assertion.
-- The five tables with no `<t>_tenant_write` get one probe: four of them
-- withhold INSERT and UPDATE by privilege (ADR-047/049), which
-- 04_contract_meta asserts over the catalogue, so only
-- impersonation_sessions -- whose grant permits writes and whose policy is what
-- denies them -- is probed here.
--
-- ADR-050: every count is scoped to this file's own fixture tenants.
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(42);

-- Gym A, fully populated: every table in `public` carries rows for it, two
-- wherever the table's shape allows two, so that a member gate (`member_id =
-- the acting member`) returns one row and a gym-wide member gate returns two.
-- A table that returns two rows to a member has a member policy it should not
-- have; one that returns one where the matrix says gym-wide has the wrong
-- member gate. Gym B exists so the platform assertions can be scoped to two
-- known tenants rather than to a whole table (ADR-050).

insert into auth.users (id) values
  ('13000000-0000-4000-8000-00000000002a'::uuid),
  ('13000000-0000-4000-8000-00000000002b'::uuid);

insert into public.platform_users (user_id, role, full_name, email) values
  ('13000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'Root 13', 'root.13@gymloop.test'),
  ('13000000-0000-4000-8000-00000000002b'::uuid, 'platform_support', 'Support 13', 'support.13@gymloop.test');

insert into public.organizations (id, name, gym_code) values
  ('13000000-0000-4000-8000-000000000001'::uuid, 'Matrix Gym A', 'RMW13A'),
  ('13000000-0000-4000-8000-000000000002'::uuid, 'Matrix Gym B', 'RMW13B');

insert into public.organization_settings (tenant_id) values
  ('13000000-0000-4000-8000-000000000001'::uuid),
  ('13000000-0000-4000-8000-000000000002'::uuid);

insert into public.branches (id, tenant_id, name, is_default) values
  ('13000000-0000-4000-8000-000000000011'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('13000000-0000-4000-8000-000000000012'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'A Annexe', false),
  ('13000000-0000-4000-8000-000000000013'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('13000000-0000-4000-8000-000000000021'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'gym_owner',   'A Owner'),
  ('13000000-0000-4000-8000-000000000022'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Manager'),
  ('13000000-0000-4000-8000-000000000023'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('13000000-0000-4000-8000-000000000024'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'trainer',     'A Trainer'),
  ('13000000-0000-4000-8000-000000000025'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, '13000000-0000-4000-8000-000000000013'::uuid, 'gym_owner',   'B Owner');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('13000000-0000-4000-8000-000000000031'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'Member X', '+91130000031'),
  ('13000000-0000-4000-8000-000000000032'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'Member Y', '+91130000032'),
  ('13000000-0000-4000-8000-000000000033'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, '13000000-0000-4000-8000-000000000013'::uuid, 'Member B', '+91130000033');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('13000000-0000-4000-8000-000000000041'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'A Monthly',   30, 200000),
  ('13000000-0000-4000-8000-000000000042'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'A Quarterly', 90, 500000),
  ('13000000-0000-4000-8000-000000000043'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, 'B Monthly',   30, 200000);

insert into public.coupons (id, tenant_id, code, percent_bp) values
  ('13000000-0000-4000-8000-000000000051'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'AFIRST10', 1000),
  ('13000000-0000-4000-8000-000000000052'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'AWIN20',   2000);

insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise) values
  ('13000000-0000-4000-8000-000000000061'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, '13000000-0000-4000-8000-000000000041'::uuid, 200000),
  ('13000000-0000-4000-8000-000000000062'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, '13000000-0000-4000-8000-000000000041'::uuid, 200000),
  ('13000000-0000-4000-8000-00000000002d'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, '13000000-0000-4000-8000-000000000033'::uuid, '13000000-0000-4000-8000-000000000043'::uuid, 200000);

insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values
  ('13000000-0000-4000-8000-000000000071'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000061'::uuid, date '2026-10-01', date '2026-10-10', 'travel'),
  ('13000000-0000-4000-8000-000000000072'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000062'::uuid, date '2026-10-01', date '2026-10-10', 'injury');

insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values
  ('13000000-0000-4000-8000-000000000081'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 200000, 'cash', '13000000-0000-4000-8000-000000000023'::uuid),
  ('13000000-0000-4000-8000-000000000082'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 200000, 'cash', '13000000-0000-4000-8000-000000000023'::uuid),
  ('13000000-0000-4000-8000-00000000002e'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, '13000000-0000-4000-8000-000000000033'::uuid, 200000, 'cash', '13000000-0000-4000-8000-000000000025'::uuid);

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values
  ('13000000-0000-4000-8000-000000000091'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000081'::uuid, 'refund', 50000, 'goodwill'),
  ('13000000-0000-4000-8000-000000000092'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000082'::uuid, 'refund', 50000, 'goodwill');

insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values
  ('13000000-0000-4000-8000-0000000000a1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000081'::uuid, '13/2026-27/0001', '2026-27', 'Member X', 169492, 200000),
  ('13000000-0000-4000-8000-0000000000a2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000082'::uuid, '13/2026-27/0002', '2026-27', 'Member Y', 169492, 200000);

insert into public.document_counters (tenant_id, kind, financial_year) values
  ('13000000-0000-4000-8000-000000000001'::uuid, 'invoice', '2026-27'),
  ('13000000-0000-4000-8000-000000000001'::uuid, 'receipt', '2026-27');

insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values
  ('13000000-0000-4000-8000-000000000001'::uuid, 'rzp_test_13', gen_random_uuid(), gen_random_uuid());

insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values
  ('13000000-0000-4000-8000-0000000000b1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 'sub_13_x', 500000),
  ('13000000-0000-4000-8000-0000000000b2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 'sub_13_y', 500000);

insert into public.attendance (id, tenant_id, branch_id, member_id, source) values
  ('13000000-0000-4000-8000-0000000000c1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 'qr'),
  ('13000000-0000-4000-8000-0000000000c2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 'qr'),
  ('13000000-0000-4000-8000-00000000002f'::uuid, '13000000-0000-4000-8000-000000000002'::uuid, '13000000-0000-4000-8000-000000000013'::uuid, '13000000-0000-4000-8000-000000000033'::uuid, 'qr');

insert into public.attendance_corrections (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after) values
  ('13000000-0000-4000-8000-0000000000d1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-0000000000c1'::uuid, '13000000-0000-4000-8000-000000000023'::uuid, 'wrong member', '{}'::jsonb, '{}'::jsonb),
  ('13000000-0000-4000-8000-0000000000d2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-0000000000c2'::uuid, '13000000-0000-4000-8000-000000000023'::uuid, 'wrong time',   '{}'::jsonb, '{}'::jsonb);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at) values
  ('13000000-0000-4000-8000-0000000000e1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'hash-13-1', now() + interval '1 hour'),
  ('13000000-0000-4000-8000-0000000000e2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000012'::uuid, 'hash-13-2', now() + interval '1 hour');

insert into public.organization_holidays (id, tenant_id, holiday_on, name) values
  ('13000000-0000-4000-8000-0000000000f1'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, date '2026-10-02', 'Gandhi Jayanti'),
  ('13000000-0000-4000-8000-0000000000f2'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, date '2026-11-01', 'Diwali');

insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days) values
  ('13000000-0000-4000-8000-000000000003'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 9, 7),
  ('13000000-0000-4000-8000-000000000004'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 9, 7);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome) values
  ('13000000-0000-4000-8000-000000000005'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000003'::uuid, '13000000-0000-4000-8000-000000000024'::uuid, 'call', 'will_return'),
  ('13000000-0000-4000-8000-000000000006'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000004'::uuid, '13000000-0000-4000-8000-000000000024'::uuid, 'call', 'no_response');

-- A pt_package must carry a session_count and a product must carry a
-- stock_quantity (addon_products_pt_package_has_session_count_chk,
-- addon_products_product_has_stock_quantity_chk). Neither is a Phase 2 rule;
-- both are Phase 1 constraints this fixture has to satisfy to exist at all.
insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count) values
  ('13000000-0000-4000-8000-000000000007'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT 10',     500000, 10),
  ('13000000-0000-4000-8000-000000000008'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'diet_plan',  'Diet Plan', 100000, null);

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise) values
  ('13000000-0000-4000-8000-000000000009'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, '13000000-0000-4000-8000-000000000007'::uuid, 500000, 500000),
  ('13000000-0000-4000-8000-00000000000a'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, '13000000-0000-4000-8000-000000000007'::uuid, 500000, 500000);

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at) values
  ('13000000-0000-4000-8000-00000000000b'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000009'::uuid, '13000000-0000-4000-8000-000000000024'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, now() + interval '1 day', now() + interval '1 day 1 hour'),
  ('13000000-0000-4000-8000-00000000000c'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-00000000000a'::uuid, '13000000-0000-4000-8000-000000000024'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, now() + interval '2 day', now() + interval '2 day 1 hour');

insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source) values
  ('13000000-0000-4000-8000-00000000000d'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 'marketing', true,  'v1', 'signup'),
  ('13000000-0000-4000-8000-00000000000e'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 'marketing', false, 'v1', 'signup');

insert into public.notifications (id, tenant_id, member_id, channel) values
  ('13000000-0000-4000-8000-00000000000f'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 'push'),
  ('13000000-0000-4000-8000-000000000010'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 'push');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('13000000-0000-4000-8000-000000000014'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000031'::uuid, 'android', 'token-13-x'),
  ('13000000-0000-4000-8000-000000000015'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000032'::uuid, 'ios',     'token-13-y');

insert into public.message_templates (id, tenant_id, key, channel, body) values
  ('13000000-0000-4000-8000-000000000016'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'renewal_due', 'push',          'Your plan expires soon'),
  ('13000000-0000-4000-8000-000000000017'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'we_miss_you', 'whatsapp_link', 'We miss you');

insert into public.leads (id, tenant_id, branch_id, full_name, phone, source) values
  ('13000000-0000-4000-8000-000000000018'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'Lead One', '+91130000018', 'walk_in'),
  ('13000000-0000-4000-8000-000000000019'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000011'::uuid, 'Lead Two', '+91130000019', 'referral');

insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping) values
  ('13000000-0000-4000-8000-00000000001a'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000022'::uuid, 'batch-1.csv', '{"A": "full_name"}'::jsonb),
  ('13000000-0000-4000-8000-00000000001b'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-000000000022'::uuid, 'batch-2.csv', '{"A": "full_name"}'::jsonb);

insert into public.messaging_wallets (tenant_id) values
  ('13000000-0000-4000-8000-000000000001'::uuid);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('13000000-0000-4000-8000-00000000001c'::uuid, '13000000-0000-4000-8000-000000000001'::uuid,  1000, 'topup'),
  ('13000000-0000-4000-8000-00000000001d'::uuid, '13000000-0000-4000-8000-000000000001'::uuid,   -10, 'push sent');

insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values
  ('13000000-0000-4000-8000-00000000001e'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'evt_13_1', 'payment.captured', '{}'::jsonb, true),
  ('13000000-0000-4000-8000-00000000001f'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, 'evt_13_2', 'payment.failed',   '{}'::jsonb, true);

insert into public.audit_log (id, tenant_id, actor_user_id, actor_role, action, record_type, record_id) values
  ('13000000-0000-4000-8000-000000000026'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'payment.refunded', 'payment', '13000000-0000-4000-8000-000000000081'::uuid),
  ('13000000-0000-4000-8000-000000000027'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'payment.refunded', 'payment', '13000000-0000-4000-8000-000000000082'::uuid);

-- Both impersonation rows are ENDED. Section 6 puts a partial unique index on
-- `actor_user_id where ended_at is null`, so two LIVE sessions for one actor is
-- a constraint violation rather than a fixture; two ended ones are history,
-- which is what a gym is entitled to read.
insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at) values
  ('13000000-0000-4000-8000-000000000028'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-00000000002a'::uuid, 'billing dispute', now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour'),
  ('13000000-0000-4000-8000-000000000029'::uuid, '13000000-0000-4000-8000-000000000001'::uuid, '13000000-0000-4000-8000-00000000002b'::uuid, 'onboarding help', now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour');

-- One spare authentication user, for the super_admin insert into
-- platform_users at the end of the file.
insert into auth.users (id) values ('13000000-0000-4000-8000-00000000002c'::uuid);

-- ===========================================================================
-- 1-5. gym_manager. The three tables the matrix reserves to `= 'gym_owner'`,
--      plus the control that proves the manager is not simply write-blocked
--      everywhere. A manager READS all three (is_staff / is_gym_admin) through
--      their <t>_tenant_select policy, and fails <t>_tenant_write, so the
--      updates here affect zero rows in silence and only the insert raises.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

with attempt as (
  update public.organizations set name = 'Renamed by the manager'
   where id = '13000000-0000-4000-8000-000000000001'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'design.md 8.4: organizations carries status, tier and trial_ends_at -- the platform''s commercial relationship with the gym -- so a manager reads it and cannot write it. ZERO ROWS, not an error: the read gate lives on organizations_tenant_select and the manager fails organizations_tenant_write''s using clause, so there is no row to update'
);

select throws_ok(
  $$insert into public.staff (tenant_id, branch_id, role, full_name)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011', 'front_desk', 'Hired by the manager')$$,
  '42501', null,
  'spec "A manager inserting a staff member": staff is the gym''s privilege ledger and only gym_owner writes it'
);

with attempt as (
  update public.staff set role = 'gym_owner'
   where id = '13000000-0000-4000-8000-000000000023'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "A manager promoting itself": zero rows affected and NO ERROR RAISED. The manager reads the staff row through staff_tenant_select and fails staff_tenant_write''s using clause, so the update matches nothing. Under a single for-all policy with the read gate on using, this same statement would raise 42501 instead -- which is the difference design.md 8.1 exists to produce'
);

with attempt as (
  update public.razorpay_accounts set key_id = 'rzp_test_manager'
   where tenant_id = '13000000-0000-4000-8000-000000000001'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'design.md 8.3: razorpay_accounts reads is_gym_admin() and writes `= gym_owner`, so the manager reads the row it may not change -- and reading it is what makes zero rows, rather than an error, the observable outcome'
);

select lives_ok(
  $$insert into public.plans (tenant_id, name, duration_days, price_paise)
    values ('13000000-0000-4000-8000-000000000001', 'Manager Plan', 30, 100000)$$,
  'control: the same manager DOES write a table gated is_gym_admin(), so the four refusals above are the gate and not a blanket denial'
);

set local role postgres;

-- ===========================================================================
-- 6-17. front_desk. Every table whose write gate is is_gym_admin() while its
--       read gate admits front_desk, plus one is_gym_admin/is_gym_admin table
--       as the sample for the read-equals-write class, plus the control.
-- ===========================================================================

-- A real front-desk token always carries staff_id: app.custom_access_token_hook()
-- stamps it for every staff user (docs/registry.md). Phase 5's GL034 reads it on
-- every payments insert (the fourth appearance of the attribution rule after
-- GL016/GL026/GL030), so the fixture now matches what a genuine session carries.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '13000000-0000-4000-8000-000000000023')::text,
  true
);
set local role authenticated;

with attempt as (
  update public.organization_settings set city = 'Pune'
   where tenant_id = '13000000-0000-4000-8000-000000000001'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'design.md 8.3: organization_settings holds every threshold the retention engine runs on -- front desk reads it, does not tune it, and the attempt is silent'
);

select throws_ok(
  $$insert into public.branches (tenant_id, name)
    values ('13000000-0000-4000-8000-000000000001', 'Desk Branch')$$,
  '42501', null,
  'design.md 8.3: branches writes is_gym_admin()'
);

select throws_ok(
  $$insert into public.plans (tenant_id, name, duration_days, price_paise)
    values ('13000000-0000-4000-8000-000000000001', 'Desk Plan', 30, 100000)$$,
  '42501', null,
  'design.md 8.3: plans reads is_staff() and writes is_gym_admin() -- a plans_tenant_write built by copying plans_tenant_select''s predicate would let this through, and would pass every read assertion in 12_role_matrix_read while doing so'
);

with attempt as (
  update public.plans set price_paise = 999
   where id = '13000000-0000-4000-8000-000000000041'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "Front desk changing the price list": zero rows SHALL be affected. Front desk reads the plan through plans_tenant_select and fails plans_tenant_write, and the two being separate policies is what makes this silent rather than an error'
);

select throws_ok(
  $$insert into public.coupons (tenant_id, code, percent_bp)
    values ('13000000-0000-4000-8000-000000000001', 'DESK50', 5000)$$,
  '42501', null,
  'design.md 8.3: coupons reads is_front_office() and writes is_gym_admin() -- front desk quotes a discount code, it does not mint one'
);

select throws_ok(
  $$insert into public.refunds (tenant_id, payment_id, kind, amount_paise, reason)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000081', 'refund', 1000, 'desk refund')$$,
  '42501', null,
  'design.md 8.3: refunds reads is_front_office() and writes is_gym_admin() -- money leaves the gym only on an admin''s authority'
);

select throws_ok(
  $$insert into public.organization_holidays (tenant_id, holiday_on, name)
    values ('13000000-0000-4000-8000-000000000001', date '2026-12-25', 'Christmas')$$,
  '42501', null,
  'design.md 8.3: organization_holidays writes is_gym_admin()'
);

select throws_ok(
  $$insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity)
    values ('13000000-0000-4000-8000-000000000001', 'product', 'Desk Shaker', 50000, 20)$$,
  '42501', null,
  'design.md 8.3: addon_products reads is_staff() and writes is_gym_admin() -- the catalogue is priced by an admin'
);

select throws_ok(
  $$insert into public.notifications (tenant_id, member_id, channel)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031', 'sms')$$,
  '42501', null,
  'design.md 8.3: notifications reads is_front_office() and writes is_gym_admin() -- every send spends the messaging wallet'
);

select throws_ok(
  $$insert into public.message_templates (tenant_id, key, channel, body)
    values ('13000000-0000-4000-8000-000000000001', 'desk_note', 'sms', 'hello')$$,
  '42501', null,
  'design.md 8.3: message_templates reads is_staff() and writes is_gym_admin()'
);

select throws_ok(
  $$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000023', 'desk.csv', '{}'::jsonb)$$,
  '42501', null,
  'design.md 8.3: member_imports is is_gym_admin() on BOTH sides, the sampled member of the read-equals-write class -- front desk can neither read nor write it, and the insert still fails on with check'
);

select lives_ok(
  $$insert into public.payments (tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031', 100000, 'cash',
            '13000000-0000-4000-8000-000000000023')$$,
  'spec "Front desk recording a payment": taking money at the counter is the front desk''s job, so is_front_office() admits the insert'
);

set local role postgres;

-- ===========================================================================
-- 18-27. trainer. Every table whose write gate is is_front_office() while its
--        read gate is is_staff(), plus one is_front_office/is_front_office
--        table as the second sample of the read-equals-write class, plus the
--        two controls that make a trainer a working role rather than a
--        read-only one.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'trainer',
                    'staff_id', '13000000-0000-4000-8000-000000000024')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011', 'Trainer Signup', '+91130000041')$$,
  '42501', null,
  'design.md 8.3: members reads is_staff() and writes is_front_office() -- a trainer sees the roster and does not enrol'
);

with attempt as (
  update public.members set full_name = 'Renamed by the trainer'
   where id = '13000000-0000-4000-8000-000000000031'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'design.md 8.3: the trainer reads the member row and may not edit it. Zero rows, no error -- the trainer cannot tell "you may not write this member" from "there is no such member", which is the property docs/data-model.md argues for'
);

select throws_ok(
  $$insert into public.memberships (tenant_id, member_id, plan_id, price_paise)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031',
            '13000000-0000-4000-8000-000000000041', 100000)$$,
  '42501', null,
  'design.md 8.3: memberships reads is_staff() and writes is_front_office()'
);

select throws_ok(
  $$insert into public.membership_pauses (tenant_id, membership_id, starts_on, ends_on, reason)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000061',
            date '2026-11-01', date '2026-11-05', 'trainer said so')$$,
  '42501', null,
  'design.md 8.3: membership_pauses reads is_staff() and writes is_front_office() -- a freeze is a commercial decision'
);

-- `source` is `qr` and not `front_desk` deliberately: a front_desk row must
-- carry assisted_by_staff_id and assist_reason
-- (attendance_front_desk_has_assist_chk), and ExecConstraints runs BEFORE
-- ExecWithCheckOptions -- so an incomplete row would raise 23514 from the
-- table constraint and never reach the policy this is about.
select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, source)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011',
            '13000000-0000-4000-8000-000000000031', 'qr')$$,
  null::char(5), null,
  'spec "A trainer recording attendance": attendance reads is_staff() and writes is_front_office(), so a trainer sees the check-in log and cannot write to it. Refused however it is signalled -- app.enforce_check_in() is a `before insert` row trigger, and a before-row trigger fires ahead of ExecWithCheckOptions, so the business refusal can reach the caller before the policy does. What this assertion owns is that the write does not land, not which of the two refuses first'
);

select throws_ok(
  $$insert into public.attendance_corrections
      (tenant_id, attendance_id, corrected_by_staff_id, reason, before, after)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-0000000000c1',
            '13000000-0000-4000-8000-000000000024', 'trainer correction',
            '{}'::jsonb, '{}'::jsonb)$$,
  '42501', null,
  'design.md 8.3: attendance_corrections follows attendance -- writing the correction is the front office''s, not the trainer''s'
);

select throws_ok(
  $$insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031',
            '13000000-0000-4000-8000-000000000007', 100000, 100000)$$,
  '42501', null,
  'design.md 8.3: addon_orders reads is_staff() and writes is_front_office() -- a trainer delivers the PT package and does not sell it'
);

select throws_ok(
  $$insert into public.payments (tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031', 100000, 'cash',
            '13000000-0000-4000-8000-000000000024')$$,
  '42501', null,
  'design.md 8.4: payments is is_front_office() on both sides, the sampled read-equals-write case for a trainer -- who reads no money table at all, so the insert is refused by with check exactly as the update would be filtered'
);

select lives_ok(
  $$insert into public.follow_ups (tenant_id, case_id, staff_id, channel, outcome)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000003',
            '13000000-0000-4000-8000-000000000024', 'call', 'will_return')$$,
  'spec "A trainer recording a follow-up": follow_ups is is_staff() on both sides -- chasing a lapsed member is the trainer''s job and the retention loop stops without it'
);

select lives_ok(
  $$insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000009',
            '13000000-0000-4000-8000-000000000024',
            '13000000-0000-4000-8000-000000000031',
            now() + interval '3 day', now() + interval '3 day 1 hour')$$,
  'control: pt_sessions is is_staff() on both sides, so the trainer books the session it delivers'
);

set local role postgres;

-- ===========================================================================
-- 28-29. gym_owner. The other half of the `= gym_owner` gate, and the one
--        select-only table whose refusal comes from the policy rather than
--        from a withheld privilege.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

with promoted as (
  update public.staff set role = 'front_desk'
   where id = '13000000-0000-4000-8000-000000000024'
  returning 1
)
select is(
  (select count(*) from promoted), 1::bigint,
  'spec "An owner changing a staff member''s role": the owner is the one gym-side role the staff write gate admits'
);

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-00000000002a', 'we impersonated ourselves',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A gym inventing an impersonation session": the gym-side policy is for select only, so the gym reads who impersonated it and cannot write the record -- and unlike the four read-only tables this one carries the INSERT privilege, so the policy is the only thing standing there'
);

set local role postgres;

-- ===========================================================================
-- 30-32. A member writes nothing directly (design.md 8.5). The two signatures
--        sit side by side here: the UPDATE is FILTERED to zero rows, because
--        members_member_select is `for select` and the only policy covering
--        UPDATE is members_tenant_write, whose gate is is_front_office(); the
--        INSERTs RAISE, because with check has no member branch to satisfy and
--        an insert meets nothing else.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'member',
                    'member_id', '13000000-0000-4000-8000-000000000031')::text,
  true
);
set local role authenticated;

with attempt as (
  update public.members set full_name = 'Edited by the member'
   where id = '13000000-0000-4000-8000-000000000031'
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "A member updating their own profile": the member policy is for select, so the update is governed only by the tenant policy whose read gate is is_staff() -- zero rows, no error'
);

select throws_ok(
  $$insert into public.member_devices (tenant_id, member_id, platform, push_token)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000031', 'web', 'member-own-token')$$,
  '42501', null,
  'spec "A member registering a device": registering a push token is a Route Handler in Phase 3 carrying the caller''s JWT, not a direct write'
);

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, source)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011',
            '13000000-0000-4000-8000-000000000031', 'qr')$$,
  null::char(5), null,
  'spec "A member inserting attendance for themselves": a member who could write attendance could mark itself present without attending, which is the whole retention signal. Refused however it is signalled, for the reason given at the trainer assertion above: the check-in trigger fires before the policy does, and the property this owns is that no row lands'
);

set local role postgres;

-- ===========================================================================
-- 33-35. platform_support: reads everywhere, writes nowhere. This is what
--        design.md 8.4 buys with one clause per table -- under Phase 1 the two
--        platform roles were indistinguishable.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

with attempt as (
  update public.plans set price_paise = 111
   where id = '13000000-0000-4000-8000-000000000041'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "Support writing a gym''s data": the update SHALL affect zero rows WITHOUT RAISING. Support reads the row through plans_platform_select and fails plans_platform_write''s using clause, which carries `= super_admin` on BOTH clauses -- were using left as is_platform(), this statement would either succeed or raise, and neither is what the spec says'
);

select throws_ok(
  $$insert into public.plans (tenant_id, name, duration_days, price_paise)
    values ('13000000-0000-4000-8000-000000000001', 'Support Plan', 30, 100000)$$,
  '42501', null,
  'spec "Support writing a gym''s data": the insert has no tenant claim to satisfy the gym policy and no super_admin role to satisfy the platform one'
);

with attempt as (
  update public.platform_users set role = 'super_admin'
   where user_id = '13000000-0000-4000-8000-00000000002b'
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "Support promoting itself" / design.md 8.4: platform_users splits in two, and the support half is for select -- so no policy covers the update at all and it is filtered to zero rows rather than raising'
);

set local role postgres;

-- ===========================================================================
-- 36-37. super_admin: the write side the narrowing keeps open.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

with changed as (
  update public.plans set price_paise = 222
   where id = '13000000-0000-4000-8000-000000000041'
  returning 1
)
select is(
  (select count(*) from changed), 1::bigint,
  'spec "A super admin writing across tenants": the platform with check names super_admin, so this is the one platform role that still writes a gym''s row'
);

select lives_ok(
  $$insert into public.platform_users (user_id, role, full_name, email)
    values ('13000000-0000-4000-8000-00000000002c', 'platform_support',
            'Second Support', 'second.13@gymloop.test')$$,
  'design.md 8.4: platform_users_super_admin_all is the only way a platform account is created after the bootstrap, which is what makes it auditable and revocable'
);

set local role postgres;

-- ===========================================================================
-- 38-39. A tenant claim with no role writes nothing, on either signature.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011', 'No Role', '+91130000051')$$,
  '42501', null,
  'spec "A tenant claim with no role attempting a write": every gate function returns null for an absent app_role, and null is not true'
);

with attempt as (
  update public.members set full_name = 'No Role Edit'
   where id = '13000000-0000-4000-8000-000000000031'
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "A tenant claim with no role": the same caller cannot see the row either, so the update is filtered rather than raised'
);

set local role postgres;

-- ===========================================================================
-- 40-41. An app_role outside the seven-value vocabulary. design.md 3 makes
--        app.current_app_role() return text and cast nothing, so a forged
--        label is a role nothing matches: it reads nothing, writes nothing and
--        raises nowhere. Both signatures are asserted, because "raises
--        nowhere" is the half a cast would break and it is invisible on the
--        insert path, where 42501 is the correct answer either way.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '13000000-0000-4000-8000-000000000001',
                    'app_role', 'superuser')::text,
  true
);
set local role authenticated;

with attempt as (
  update public.members set full_name = 'Edited by a role that is not a role'
   where id = '13000000-0000-4000-8000-000000000031'::uuid
  returning 1
)
select is(
  (select count(*) from attempt), 0::bigint,
  'spec "A role claim that is not a role, attempting a write": zero rows and no error. A cast to public.app_role would raise 22P02 here -- and would raise on some tables and not others, depending on whether the predicate reached the enum comparison at all. One forged claim behaving differently table by table is the failure design.md 3 removed'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000011', 'Forged Role', '+91130000061')$$,
  '42501', null,
  'spec "An unrecognised role grants nothing and raises nothing": the insert is refused by the row-security policy -- 42501 because with check is the only gate an insert meets, and NOT 22P02 from a cast'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 42. Back as the owner: the staff row the manager tried to promote is
--     untouched. The spec asks for the row as well as the signature: "zero
--     rows SHALL be affected, no error SHALL be raised, and the row SHALL be
--     unchanged". The first two are asserted at the attempt; this is the third.
-- ===========================================================================

select is(
  (select role::text from public.staff where id = '13000000-0000-4000-8000-000000000023'::uuid),
  'front_desk',
  'spec "A manager promoting itself": the row SHALL be unchanged -- the front desk staff row still carries front_desk after the manager''s attempt'
);

select * from finish();

rollback;
