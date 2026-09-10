-- 12_role_matrix_read - what each of the seven roles may READ inside a gym it
-- belongs to, from openspec/changes/phase-2-identity-and-tenancy/design.md
-- section 8.3 (the authoritative matrix) and .../specs/authorization/spec.md.
--
-- WHAT THIS FILE COVERS EXHAUSTIVELY, AND WHAT IT SAMPLES
--
-- Exhaustive, by behaviour: all thirty-six tables against each of eight
-- sessions -- the four gym-side staff roles, the member, the member with no
-- member_id claim, the trainer holding one, the caller with a tenant claim and no role, and the caller
-- whose role is outside the vocabulary. Every assertion below is one vector
-- over the whole of `public`, comparing the rows a session actually sees
-- against the rows the matrix says it should, table by table. That is 288
-- cells for eight of the assertions, and it is affordable because the fixture makes
-- the expected
-- number a property of the gate rather than of the table: gym A holds two rows
-- in every table that can hold two, one owned by member X and one by member Y.
-- So a staff role with the read gate sees 2, a staff role without sees 0, a
-- member-scoped gate yields 1, a gym-wide member gate yields 2, and no member
-- policy at all yields 0. The four numbers are distinguishable, which is the
-- whole point: a member policy copied onto a table that should have none shows
-- up as 1 or 2 where 0 is wanted, and a member gate written `tenant_id` alone
-- instead of `member_id = ...` shows up as 2 where 1 is wanted.
--
-- The catalogue half of the matrix -- which gate function each policy names,
-- which tables carry a `<t>_member_select` at all, and that no fifth gate was
-- invented -- is asserted once over the catalogue in 04_contract_meta.sql
-- rather than being restated here. This file is behaviour only.
--
-- Also exhaustive, and each over all thirty-six tables: the caller with a
-- tenant claim and no role, the caller with a role outside the vocabulary, and
-- the member with no member_id claim. The last of those is only interesting
-- because design.md 8.3 revised M(all) to `current_member_id() is not null`:
-- under the earlier gate -- the tenant match alone -- five tables would have
-- been readable by any session carrying a tenant claim, and no test written
-- against a member WITH a member_id could have seen it.
--
-- Sampled: the platform roles cross tenants on four representative tables
-- rather than all thirty-six (Phase 1 already proves the platform branch is
-- not tenant-filtered; what is new in Phase 2 is only that the gym-side gates
-- did not accidentally narrow it), and the member's cross-tenant blindness on
-- four tables covering all three member-gate shapes.
--
-- ADR-050: every count is scoped to this file's own two fixture tenants. The
-- project permanently holds a seeded demo gym; an unscoped count asserts the
-- size of the database, not the reach of a policy.
--
-- `audit_log` is scoped one level deeper still, to the two rows this fixture
-- authored by id, and that is not fussiness. design.md 6 has a trigger write a
-- start row for every impersonation session created, and this fixture creates
-- two -- so a count over the tenant measures the TRIGGER as well as the policy,
-- and reads 4 where the matrix has nothing to say about 4. Rewriting the
-- expectation to 4 would make it track how many audit rows the fixture happens
-- to provoke, which is the same brittleness ADR-050 recorded when the demo seed
-- broke seventeen assertions: an expectation that follows the world instead of
-- the contract. The trigger's rows are asserted where they belong, in
-- 14_impersonation, against the columns design.md 6 specifies.
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(13);

-- Gym A, fully populated: every table in `public` carries rows for it, two
-- wherever the table's shape allows two, so that a member gate (`member_id =
-- the acting member`) returns one row and a gym-wide member gate returns two.
-- A table that returns two rows to a member has a member policy it should not
-- have; one that returns one where the matrix says gym-wide has the wrong
-- member gate. Gym B exists so the platform assertions can be scoped to two
-- known tenants rather than to a whole table (ADR-050).

insert into auth.users (id) values
  ('12000000-0000-4000-8000-00000000002a'::uuid),
  ('12000000-0000-4000-8000-00000000002b'::uuid);

insert into public.platform_users (user_id, role, full_name, email) values
  ('12000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'Root 12', 'root.12@gymloop.test'),
  ('12000000-0000-4000-8000-00000000002b'::uuid, 'platform_support', 'Support 12', 'support.12@gymloop.test');

insert into public.organizations (id, name, gym_code) values
  ('12000000-0000-4000-8000-000000000001'::uuid, 'Matrix Gym A', 'RMR12A'),
  ('12000000-0000-4000-8000-000000000002'::uuid, 'Matrix Gym B', 'RMR12B');

insert into public.organization_settings (tenant_id) values
  ('12000000-0000-4000-8000-000000000001'::uuid),
  ('12000000-0000-4000-8000-000000000002'::uuid);

insert into public.branches (id, tenant_id, name, is_default) values
  ('12000000-0000-4000-8000-000000000011'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('12000000-0000-4000-8000-000000000012'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'A Annexe', false),
  ('12000000-0000-4000-8000-000000000013'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('12000000-0000-4000-8000-000000000021'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'gym_owner',   'A Owner'),
  ('12000000-0000-4000-8000-000000000022'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Manager'),
  ('12000000-0000-4000-8000-000000000023'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('12000000-0000-4000-8000-000000000024'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'trainer',     'A Trainer'),
  ('12000000-0000-4000-8000-000000000025'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, '12000000-0000-4000-8000-000000000013'::uuid, 'gym_owner',   'B Owner');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('12000000-0000-4000-8000-000000000031'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'Member X', '+91120000031'),
  ('12000000-0000-4000-8000-000000000032'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'Member Y', '+91120000032'),
  ('12000000-0000-4000-8000-000000000033'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, '12000000-0000-4000-8000-000000000013'::uuid, 'Member B', '+91120000033');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('12000000-0000-4000-8000-000000000041'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'A Monthly',   30, 200000),
  ('12000000-0000-4000-8000-000000000042'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'A Quarterly', 90, 500000),
  ('12000000-0000-4000-8000-000000000043'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, 'B Monthly',   30, 200000);

insert into public.coupons (id, tenant_id, code, percent_bp) values
  ('12000000-0000-4000-8000-000000000051'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'AFIRST10', 1000),
  ('12000000-0000-4000-8000-000000000052'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'AWIN20',   2000);

insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise) values
  ('12000000-0000-4000-8000-000000000061'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, '12000000-0000-4000-8000-000000000041'::uuid, 200000),
  ('12000000-0000-4000-8000-000000000062'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, '12000000-0000-4000-8000-000000000041'::uuid, 200000),
  ('12000000-0000-4000-8000-00000000002d'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, '12000000-0000-4000-8000-000000000033'::uuid, '12000000-0000-4000-8000-000000000043'::uuid, 200000);

insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values
  ('12000000-0000-4000-8000-000000000071'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000061'::uuid, date '2026-10-01', date '2026-10-10', 'travel'),
  ('12000000-0000-4000-8000-000000000072'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000062'::uuid, date '2026-10-01', date '2026-10-10', 'injury');

-- Gym A's two payments are recorded `paid`, because gym A's two refunds are
-- taken against them and `GL036` refuses a refund against a payment that has
-- taken no money. Nothing in this file reads a payment's status -- every
-- assertion is a row COUNT per table -- so this is the fixture saying what it
-- always meant: the money came in, and some of it went back. The receipt
-- numbers are supplied rather than allocated so `app.stamp_payment()` takes
-- its trusted-writer-keeps-its-own-number path and leaves `document_counters`
-- alone: those two rows are themselves counted below, and an allocation here
-- would insert a third ahead of them and then collide with them.
insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, receipt_number, recorded_by_staff_id) values
  ('12000000-0000-4000-8000-000000000081'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 200000, 'cash', 'paid',    '12/2026-27/R0001', '12000000-0000-4000-8000-000000000023'::uuid),
  ('12000000-0000-4000-8000-000000000082'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 200000, 'cash', 'paid',    '12/2026-27/R0002', '12000000-0000-4000-8000-000000000023'::uuid),
  ('12000000-0000-4000-8000-00000000002e'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, '12000000-0000-4000-8000-000000000033'::uuid, 200000, 'cash', 'created', null,               '12000000-0000-4000-8000-000000000025'::uuid);

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values
  ('12000000-0000-4000-8000-000000000091'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000081'::uuid, 'refund', 50000, 'goodwill'),
  ('12000000-0000-4000-8000-000000000092'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000082'::uuid, 'refund', 50000, 'goodwill');

insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values
  ('12000000-0000-4000-8000-0000000000a1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000081'::uuid, '12/2026-27/0001', '2026-27', 'Member X', 169492, 200000),
  ('12000000-0000-4000-8000-0000000000a2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000082'::uuid, '12/2026-27/0002', '2026-27', 'Member Y', 169492, 200000);

insert into public.document_counters (tenant_id, kind, financial_year) values
  ('12000000-0000-4000-8000-000000000001'::uuid, 'invoice', '2026-27'),
  ('12000000-0000-4000-8000-000000000001'::uuid, 'receipt', '2026-27');

insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values
  ('12000000-0000-4000-8000-000000000001'::uuid, 'rzp_test_12', gen_random_uuid(), gen_random_uuid());

insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values
  ('12000000-0000-4000-8000-0000000000b1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 'sub_12_x', 500000),
  ('12000000-0000-4000-8000-0000000000b2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 'sub_12_y', 500000);

insert into public.attendance (id, tenant_id, branch_id, member_id, source) values
  ('12000000-0000-4000-8000-0000000000c1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 'qr'),
  ('12000000-0000-4000-8000-0000000000c2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 'qr'),
  ('12000000-0000-4000-8000-00000000002f'::uuid, '12000000-0000-4000-8000-000000000002'::uuid, '12000000-0000-4000-8000-000000000013'::uuid, '12000000-0000-4000-8000-000000000033'::uuid, 'qr');

insert into public.attendance_corrections (id, tenant_id, attendance_id, corrected_by_staff_id, reason, before, after) values
  ('12000000-0000-4000-8000-0000000000d1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-0000000000c1'::uuid, '12000000-0000-4000-8000-000000000023'::uuid, 'wrong member', '{}'::jsonb, '{}'::jsonb),
  ('12000000-0000-4000-8000-0000000000d2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-0000000000c2'::uuid, '12000000-0000-4000-8000-000000000023'::uuid, 'wrong time',   '{}'::jsonb, '{}'::jsonb);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at) values
  ('12000000-0000-4000-8000-0000000000e1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'hash-12-1', now() + interval '1 hour'),
  ('12000000-0000-4000-8000-0000000000e2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000012'::uuid, 'hash-12-2', now() + interval '1 hour');

insert into public.organization_holidays (id, tenant_id, holiday_on, name) values
  ('12000000-0000-4000-8000-0000000000f1'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, date '2026-10-02', 'Gandhi Jayanti'),
  ('12000000-0000-4000-8000-0000000000f2'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, date '2026-11-01', 'Diwali');

insert into public.no_show_cases (id, tenant_id, member_id, absent_days_at_open, threshold_days) values
  ('12000000-0000-4000-8000-000000000003'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 9, 7),
  ('12000000-0000-4000-8000-000000000004'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 9, 7);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome) values
  ('12000000-0000-4000-8000-000000000005'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000003'::uuid, '12000000-0000-4000-8000-000000000024'::uuid, 'call', 'will_return'),
  ('12000000-0000-4000-8000-000000000006'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000004'::uuid, '12000000-0000-4000-8000-000000000024'::uuid, 'call', 'no_response');

-- Phase 6 active offers carry complete kind-specific disclosure. These facts
-- are fixtures only; the role read/write expectations below are unchanged.
insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification) values
  ('12000000-0000-4000-8000-000000000007'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT 10',     500000, 10, '12000000-0000-4000-8000-000000000024', 'Ten PT sessions', 90, 'Cancel before delivery', 'Gym-stated qualification'),
  ('12000000-0000-4000-8000-000000000008'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'diet_plan',  'Diet Plan', 100000, null, null, 'Diet plan disclosure', 30, 'Cancel before delivery', null);

-- Consistent legacy complimentary orders exercise access without adding money rows.
insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise, status, trainer_staff_id, sessions_total, starts_on, expires_on) values
  ('12000000-0000-4000-8000-000000000009'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, '12000000-0000-4000-8000-000000000007'::uuid, 0, 0, 'active', '12000000-0000-4000-8000-000000000024', 10, (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date+90),
  ('12000000-0000-4000-8000-00000000000a'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, '12000000-0000-4000-8000-000000000007'::uuid, 0, 0, 'active', '12000000-0000-4000-8000-000000000024', 10, (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date+90);

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at) values
  ('12000000-0000-4000-8000-00000000000b'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000009'::uuid, '12000000-0000-4000-8000-000000000024'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, now() + interval '1 day', now() + interval '1 day 1 hour'),
  ('12000000-0000-4000-8000-00000000000c'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-00000000000a'::uuid, '12000000-0000-4000-8000-000000000024'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, now() + interval '2 day', now() + interval '2 day 1 hour');

insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source) values
  ('12000000-0000-4000-8000-00000000000d'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 'marketing', true,  'v1', 'signup'),
  ('12000000-0000-4000-8000-00000000000e'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 'marketing', false, 'v1', 'signup');

insert into public.notifications (id, tenant_id, member_id, channel) values
  ('12000000-0000-4000-8000-00000000000f'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 'push'),
  ('12000000-0000-4000-8000-000000000010'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 'push');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('12000000-0000-4000-8000-000000000014'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000031'::uuid, 'android', 'token-12-x'),
  ('12000000-0000-4000-8000-000000000015'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000032'::uuid, 'ios',     'token-12-y');

insert into public.message_templates (id, tenant_id, key, channel, body) values
  ('12000000-0000-4000-8000-000000000016'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'renewal_due', 'push',          'Your plan expires soon'),
  ('12000000-0000-4000-8000-000000000017'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'we_miss_you', 'whatsapp_link', 'We miss you');

insert into public.leads (id, tenant_id, branch_id, full_name, phone, source) values
  ('12000000-0000-4000-8000-000000000018'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'Lead One', '+91120000018', 'walk_in'),
  ('12000000-0000-4000-8000-000000000019'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000011'::uuid, 'Lead Two', '+91120000019', 'referral');

insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping) values
  ('12000000-0000-4000-8000-00000000001a'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000022'::uuid, 'batch-1.csv', '{"A": "full_name"}'::jsonb),
  ('12000000-0000-4000-8000-00000000001b'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000022'::uuid, 'batch-2.csv', '{"A": "full_name"}'::jsonb);

insert into public.messaging_wallets (tenant_id) values
  ('12000000-0000-4000-8000-000000000001'::uuid);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('12000000-0000-4000-8000-00000000001c'::uuid, '12000000-0000-4000-8000-000000000001'::uuid,  1000, 'topup'),
  ('12000000-0000-4000-8000-00000000001d'::uuid, '12000000-0000-4000-8000-000000000001'::uuid,   -10, 'push sent');

insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values
  ('12000000-0000-4000-8000-00000000001e'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'evt_12_1', 'payment.captured', '{}'::jsonb, true),
  ('12000000-0000-4000-8000-00000000001f'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, 'evt_12_2', 'payment.failed',   '{}'::jsonb, true);

insert into public.audit_log (id, tenant_id, actor_user_id, actor_role, action, record_type, record_id) values
  ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'payment.refunded', 'payment', '12000000-0000-4000-8000-000000000081'::uuid),
  ('12000000-0000-4000-8000-000000000027'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-00000000002a'::uuid, 'super_admin', 'payment.refunded', 'payment', '12000000-0000-4000-8000-000000000082'::uuid);

-- Both impersonation rows are ENDED. Section 6 puts a partial unique index on
-- `actor_user_id where ended_at is null`, so two LIVE sessions for one actor is
-- a constraint violation rather than a fixture; two ended ones are history,
-- which is what a gym is entitled to read.
insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at) values
  ('12000000-0000-4000-8000-000000000028'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-00000000002a'::uuid, 'billing dispute', now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour'),
  ('12000000-0000-4000-8000-000000000029'::uuid, '12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-00000000002b'::uuid, 'onboarding help', now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour');

-- ---------------------------------------------------------------------------
-- 1-4. The four gym-side staff roles, each against all thirty-six tables.
--
-- gym_owner and gym_manager have identical READ vectors by the matrix -- they
-- differ only on the write side -- so both are asserted rather than one, which
-- is what makes "the manager was given the owner's read gate somewhere" a
-- passing observation rather than an untested assumption.
-- ---------------------------------------------------------------------------

-- gym_owner
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 1::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 4
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 2
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "An owner reading everything in their gym" / design.md 8.3: gym_owner reads every table in public that holds rows for its gym, and reads nothing from platform_users'
);

set local role postgres;

-- gym_manager
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 1::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 4
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 2
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'design.md 8.3: gym_manager''s read vector is the owner''s -- is_gym_admin() admits it everywhere is_staff() and is_front_office() do, and the two roles differ only on the write side'
);

set local role postgres;

-- front_desk
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 1::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 4
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "Front desk reading the gym''s own configuration" / design.md 8.3: front_desk reads the is_staff() and is_front_office() tables and nothing gated is_gym_admin()'
);

set local role postgres;

-- trainer
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001',
                    'app_role', 'trainer')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 1::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 4
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A trainer reading money" and "A trainer reading the retention loop" / design.md 8.4: a trainer reads the retention loop and no money, no personal-contact table and no gym configuration'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 5. The member, against all thirty-six tables. Three shapes have to be
--    distinguished and the fixture distinguishes them: `M` returns member X's
--    one row out of two, `M(all)` returns both of the gym's rows, and a table
--    with no member policy returns nothing at all even though the member's own
--    row sits in it (razorpay_mandates and no_show_cases both carry a
--    member_id and both are `--` in the matrix; they are the two rows that
--    catch a member policy added by pattern rather than by the matrix).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001',
                    'app_role', 'member',
                    'member_id', '12000000-0000-4000-8000-000000000031')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 1::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 2
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 1
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A member reads only their own rows, and only from the tables the matrix names" / design.md 8.3: every member-scoped table returns member X''s row alone, every gym-wide one returns the gym''s rows, and every table the matrix marks `--` returns nothing'
);

-- 6. The same member, blind across the tenant line. A member gate is ANDed
--    with the tenant match, not substituted for it, so gym B's rows stay
--    invisible even on the tables a member reads gym-wide.

select is_empty(
  $$select tbl, seen from (
    select 'members'::text, (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000002'::uuid)
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000002'::uuid)
    union all select 'payments',   (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000002'::uuid)
    union all select 'plans',      (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000002'::uuid)
  ) v(tbl, seen)
   where seen <> 0$$,
  'spec "A member reads only their own rows": the member gate is ANDed with the tenant match, so gym B stays invisible on M, M(self) and M(all) tables alike'
);

set local role postgres;

-- 7. A member_id claim carried by a session that is NOT a member.
--
--    design.md 8.1 gives every member policy an explicit
--    `(select app.current_app_role()) = 'member'` term, because without it the
--    policy's correctness depends on a property of a different component: the
--    hook never pairs a member_id claim with another role, but the POLICY does
--    not say so. On the five M(all) tables the term grants nothing -- a trainer
--    reads those anyway. On consents, notifications, member_devices and
--    payments it is a real widening, because a trainer is outside those read
--    gates entirely, so those four are what this asserts.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001'::uuid,
                    'app_role', 'trainer',
                    'member_id', '12000000-0000-4000-8000-000000000031'::uuid)::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen from (
    select 'consents'::text,       (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'notifications',  (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'payments',       (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
  ) v(tbl, seen)
   where seen <> 0$$,
  'spec "A member claim carried by a session that is not a member": the member policy requires the ROLE as well as the claim. A trainer holding a member_id would otherwise read that member''s consents, notifications, devices and payments -- four tables whose read gate is is_front_office(), which a trainer fails'
);

set local role postgres;

-- 8. A member claim with NO member_id key, against all thirty-six tables.
--
--    Every one must return zero -- including the five the matrix marks M(all),
--    which is the whole point of design.md 8.3's revision. `M(all)` is
--    `(select app.current_member_id()) is not null`, NOT the tenant match
--    alone. A gate of the tenant match alone would hand organizations,
--    branches, plans, addon_products and organization_holidays to any session
--    carrying a tenant claim and no member claim -- and, since the gate would
--    not mention the role either, to a session with no role claim at all,
--    flatly against the authorization spec's first requirement. Those five
--    rows are what distinguishes the two gates, and they are why this vector
--    covers all thirty-six tables rather than only the nine gated on
--    member_id.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001'::uuid,
                    'app_role', 'member')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 0::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A member with no member claim" / design.md 8.3: a member session with no member_id claim reads zero rows from every table in public, the five gym-wide member tables included -- M(all) is `current_member_id() is not null`, not the tenant match alone'
);

set local role postgres;

-- 9. A tenant claim with no app_role at all. Phase 1 made this caller read its
--    own gym; Phase 2 makes it read nothing anywhere, which is the whole
--    difference the role matrix introduces.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001'::uuid)::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 0::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A tenant claim alone grants nothing": a session with a valid tenant claim and no app_role claim reads zero rows from every table in public'
);

set local role postgres;

-- 10. An app_role outside the seven-value vocabulary, against all thirty-six
--    tables.
--
--    Zero rows everywhere and NOTHING RAISED. app.current_app_role() returns
--    text and casts nothing (design.md 3), so a forged label is simply a role
--    nothing matches. Returning public.app_role instead would raise 22P02 --
--    and, worse, would raise inconsistently: the gate functions would answer
--    false and yield zero rows while the policies comparing the role directly
--    would raise, so one forged claim would behave differently table by table.
--    is_empty() over the whole vector asserts both halves at once, because an
--    assertion that raised would not report a failure, it would abort the file.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '12000000-0000-4000-8000-000000000001'::uuid,
                    'app_role', 'superuser')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id = '12000000-0000-4000-8000-000000000001'::uuid), 0::bigint
    union all select 'organization_settings', (select count(*) from public.organization_settings where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'branches', (select count(*) from public.branches where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'staff', (select count(*) from public.staff where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'members', (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'plans', (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'coupons', (select count(*) from public.coupons where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'memberships', (select count(*) from public.memberships where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'membership_pauses', (select count(*) from public.membership_pauses where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'payments', (select count(*) from public.payments where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'refunds', (select count(*) from public.refunds where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'invoices', (select count(*) from public.invoices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'document_counters', (select count(*) from public.document_counters where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_accounts', (select count(*) from public.razorpay_accounts where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'razorpay_mandates', (select count(*) from public.razorpay_mandates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'attendance_corrections', (select count(*) from public.attendance_corrections where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'qr_sessions', (select count(*) from public.qr_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'organization_holidays', (select count(*) from public.organization_holidays where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'no_show_cases', (select count(*) from public.no_show_cases where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'follow_ups', (select count(*) from public.follow_ups where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_products', (select count(*) from public.addon_products where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'addon_orders', (select count(*) from public.addon_orders where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'pt_sessions', (select count(*) from public.pt_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'consents', (select count(*) from public.consents where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'notifications', (select count(*) from public.notifications where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_devices', (select count(*) from public.member_devices where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'message_templates', (select count(*) from public.message_templates where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'leads', (select count(*) from public.leads where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'member_imports', (select count(*) from public.member_imports where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallets', (select count(*) from public.messaging_wallets where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'messaging_wallet_ledger', (select count(*) from public.messaging_wallet_ledger where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'webhook_events', (select count(*) from public.webhook_events where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'audit_log', (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid)), 0
    union all select 'impersonation_sessions', (select count(*) from public.impersonation_sessions where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid), 0
    union all select 'platform_users', (select count(*) from public.platform_users where user_id = '12000000-0000-4000-8000-00000000002a'::uuid), 0
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A role claim that is not a role" / design.md 3: an app_role outside the vocabulary reads zero rows from every table in public and raises nowhere -- the role claim is compared as text and never cast'
);

set local role postgres;

-- 11. No claims at all. Phase 1's guarantee, re-asserted because the gates are
--     new: a claimless session still reads zero rows and still raises nothing,
--     rather than raising inside a gate function.

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is_empty(
  $$select tbl, seen from (
    select 'members'::text, (select count(*) from public.members where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'attendance', (select count(*) from public.attendance where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'plans',      (select count(*) from public.plans where tenant_id = '12000000-0000-4000-8000-000000000001'::uuid)
    union all select 'audit_log',  (select count(*) from public.audit_log where id in ('12000000-0000-4000-8000-000000000026'::uuid, '12000000-0000-4000-8000-000000000027'::uuid))
  ) v(tbl, seen)
   where seen <> 0$$,
  'spec "A tenant claim alone grants nothing" / ADR-032: a claimless session reads zero rows and the gate functions return false rather than raising'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 12-13. The platform roles still cross tenants. design.md section 8.4 narrows
--        the platform WITH CHECK to super_admin and leaves USING as
--        is_platform(), so both platform roles must still READ both gyms --
--        a narrowing applied to the wrong clause would show up here.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 2::bigint
    union all select 'members',    (select count(*) from public.members where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'payments',   (select count(*) from public.payments where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'attendance', (select count(*) from public.attendance where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'plans',      (select count(*) from public.plans where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "A super admin writing across tenants" (read half) / design.md 8.4: super_admin still reads both gyms on the USING clause, which the write-side narrowing must not touch'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select is_empty(
  $$select tbl, seen, want from (
    select 'organizations'::text, (select count(*) from public.organizations where id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 2::bigint
    union all select 'members',    (select count(*) from public.members where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'payments',   (select count(*) from public.payments where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'attendance', (select count(*) from public.attendance where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
    union all select 'plans',      (select count(*) from public.plans where tenant_id in ('12000000-0000-4000-8000-000000000001'::uuid, '12000000-0000-4000-8000-000000000002'::uuid)), 3
  ) v(tbl, seen, want)
   where seen is distinct from want$$,
  'spec "Support reads across tenants": platform_support reads both gyms exactly as super_admin does -- the two roles are distinguished on the write side, not the read side'
);

set local role postgres;

select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
