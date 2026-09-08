-- Gymloop Phase 1 - holdout pgTAP suite, cluster: membership+money
-- Written from openspec/changes/0001-data-model/specs/membership-and-money/spec.md,
-- docs/data-model.md (Conventions + the cluster table list + Enums) and docs/domain-rules.md.
-- The author of this file never read the migration, and never read the visible suite.
-- Fixture uuids are namespaced 00000000-0000-4000-8000-0000005xxxxx so a combined run cannot collide.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(149);

-- ============================================================
-- 1. The eleven tables the cluster promises
-- ============================================================

select is_empty($$
  select v.t
  from (values ('plans'),('coupons'),('memberships'),('membership_pauses'),('payments'),
               ('refunds'),('webhook_events'),('invoices'),('document_counters'),
               ('razorpay_accounts'),('razorpay_mandates')) v(t)
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname::text collate "default" = v.t)
$$, 'membership+money Purpose: every table the capability names exists');

-- ============================================================
-- 2. The six enums this cluster owns, labels in the fixed order
-- ============================================================

select enum_has_labels('public'::name, 'membership_status'::name,
  array['pending','active','frozen','expired','cancelled']::name[],
  'contract Enums: membership_status label set and order'::text);

select enum_has_labels('public'::name, 'payment_status'::name,
  array['created','pending','paid','failed','refunded','reversed']::name[],
  'contract Enums: payment_status label set and order'::text);

select enum_has_labels('public'::name, 'payment_method'::name,
  array['razorpay','cash','upi','card','bank_transfer']::name[],
  'contract Enums: payment_method label set and order'::text);

select enum_has_labels('public'::name, 'refund_kind'::name,
  array['refund','reversal']::name[],
  'contract Enums: refund_kind label set and order'::text);

select enum_has_labels('public'::name, 'refund_status'::name,
  array['requested','processing','completed','failed']::name[],
  'contract Enums: refund_status label set and order'::text);

select enum_has_labels('public'::name, 'mandate_status'::name,
  array['created','authenticated','active','paused','halted','cancelled','completed','expired']::name[],
  'Autopay mandate tables exist unused: mandate_status mirrors the provider vocabulary'::text);

-- ============================================================
-- 3. Money is integer paise with an explicit currency (MNY-001, MNY-002)
-- ============================================================

select is_empty($$
  select c.relname::text collate "default" || '.' || a.attname::text collate "default"
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and a.attname::text collate "default" like '%\_paise'
    and format_type(a.atttypid, a.atttypmod) <> 'bigint'
$$, 'MNY-001 scenario "No approximate money column exists"');

select is_empty($$
  select c.relname::text collate "default"
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and exists (select 1 from pg_attribute a
                where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                  and a.attname::text collate "default" like '%\_paise')
    and not exists (select 1 from pg_attribute a
                    where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text collate "default" = 'currency')
$$, 'MNY-002 scenario "Every table carrying money carries a currency"');

select is_empty($$
  select c.relname::text collate "default"
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and a.attname::text collate "default" = 'currency'
    and (format_type(a.atttypid, a.atttypmod) <> 'text' or not a.attnotnull)
$$, 'MNY-002: every currency column is a not-null text code');

-- ============================================================
-- 4. Payment secrets are never plaintext columns (PAY-005)
-- ============================================================

select is_empty($$
  select c.relname::text collate "default" || '.' || a.attname::text collate "default"
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and a.attname::text collate "default" ~ '(card_number|cardnumber|card_no|cvv|upi_pin|upi_credential|raw_credential|card_expiry)'
$$, 'PAY-005 scenario "No credential column exists"');

select is_empty($$
  select a.attname::text collate "default"
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname::text collate "default" = 'razorpay_accounts'
    and a.attnum > 0 and not a.attisdropped
    and a.attname::text collate "default" like '%secret%'
    and format_type(a.atttypid, a.atttypmod) = 'text'
$$, 'PAY-005: a gym secret is a Vault reference, never a text column');

select col_type_is('public'::name, 'razorpay_accounts'::name, 'key_secret_vault_id'::name, 'uuid'::text,
  'PAY-005: the key secret is stored as a Vault entry id'::text);

select col_type_is('public'::name, 'razorpay_accounts'::name, 'webhook_secret_vault_id'::name, 'uuid'::text,
  'PAY-005: the webhook secret is stored as a Vault entry id'::text);

-- ============================================================
-- 5. Financial history is never hard-deleted (INT-001) and anon holds nothing
-- ============================================================

select ok(not has_table_privilege('authenticated', 'public.plans', 'DELETE'),
  'INT-001: authenticated holds no delete on plans');
select ok(not has_table_privilege('authenticated', 'public.coupons', 'DELETE'),
  'INT-001: authenticated holds no delete on coupons');
select ok(not has_table_privilege('authenticated', 'public.memberships', 'DELETE'),
  'INT-001: authenticated holds no delete on memberships');
select ok(not has_table_privilege('authenticated', 'public.membership_pauses', 'DELETE'),
  'INT-001: authenticated holds no delete on membership_pauses');
select ok(not has_table_privilege('authenticated', 'public.payments', 'DELETE'),
  'INT-001: authenticated holds no delete on payments');
select ok(not has_table_privilege('authenticated', 'public.refunds', 'DELETE'),
  'INT-001: authenticated holds no delete on refunds');
select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'DELETE'),
  'INT-001: authenticated holds no delete on webhook_events');
select ok(not has_table_privilege('authenticated', 'public.invoices', 'DELETE'),
  'INT-001: authenticated holds no delete on invoices');
select ok(not has_table_privilege('authenticated', 'public.document_counters', 'DELETE'),
  'INT-001: authenticated holds no delete on document_counters');
select ok(not has_table_privilege('authenticated', 'public.razorpay_accounts', 'DELETE'),
  'INT-001: authenticated holds no delete on razorpay_accounts');
select ok(not has_table_privilege('authenticated', 'public.razorpay_mandates', 'DELETE'),
  'INT-001: authenticated holds no delete on razorpay_mandates');

select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'UPDATE'),
  'contract Privileges: webhook_events is read-only for authenticated, so no update either');
select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'INSERT'),
  'ADR-049: authenticated holds no INSERT on webhook_events - payload and signature_valid are client supplied, so an insert grant would let a gym write the record of a webhook it verified itself');

select ok(has_table_privilege('authenticated', 'public.memberships', 'UPDATE'),
  'INT-001 scenario "Cancelling a membership instead": update is granted where delete is not');

select is_empty($$
  select v.t
  from (values ('plans'),('coupons'),('memberships'),('membership_pauses'),('payments'),
               ('refunds'),('webhook_events'),('invoices'),('document_counters'),
               ('razorpay_accounts'),('razorpay_mandates')) v(t)
  where has_table_privilege('anon', 'public.' || v.t, 'SELECT')
     or has_table_privilege('anon', 'public.' || v.t, 'INSERT')
     or has_table_privilege('anon', 'public.' || v.t, 'UPDATE')
     or has_table_privilege('anon', 'public.' || v.t, 'DELETE')
$$, 'contract Privileges: anon is granted nothing on any money table');

-- ============================================================
-- 6. RLS is enabled and both policies exist on every table (gate 7)
-- ============================================================

select is_empty($$
  select v.t
  from (values ('plans'),('coupons'),('memberships'),('membership_pauses'),('payments'),
               ('refunds'),('webhook_events'),('invoices'),('document_counters'),
               ('razorpay_accounts'),('razorpay_mandates')) v(t)
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname::text collate "default" = v.t and c.relrowsecurity)
$$, 'gate 7: row level security is enabled on every table in the cluster');

-- Stated as a property, not a policy name. Phase 1 had one `<t>_tenant_all`; Phase 2
-- split it into `<t>_tenant_select` and `<t>_tenant_write`. What the gate actually
-- requires is that the gym-side reach of every money table is decided by the tenant
-- claim, whatever the policies enforcing it are called this phase.
select is_empty($$
  select v.t
  from (values ('plans'),('coupons'),('memberships'),('membership_pauses'),('payments'),
               ('refunds'),('webhook_events'),('invoices'),('document_counters'),
               ('razorpay_accounts'),('razorpay_mandates')) v(t)
  where not exists (
    select 1 from pg_policy p
    where p.polrelid = to_regclass('public.' || v.t)
      and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%')
$$, 'gate 7: every table carries a gym-side policy scoped by the tenant claim');

select is_empty($$
  select v.t
  from (values ('plans'),('coupons'),('memberships'),('membership_pauses'),('payments'),
               ('refunds'),('webhook_events'),('invoices'),('document_counters'),
               ('razorpay_accounts'),('razorpay_mandates')) v(t)
  where not exists (
    select 1 from pg_policy p
    where p.polrelid = to_regclass('public.' || v.t)
      and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%is_platform%')
$$, 'gate 7: every table carries a platform-side policy that reads across tenants');

-- ============================================================
-- 7. Fixtures, inserted as the owner, which holds BYPASSRLS
-- ============================================================

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-000000501001'::uuid, 'Holdout Gym A', 'HM5001'),
  ('00000000-0000-4000-8000-000000501002'::uuid, 'Holdout Gym B', 'HM5002');

insert into public.branches (id, tenant_id, name) values
  ('00000000-0000-4000-8000-000000501011'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'A Main'),
  ('00000000-0000-4000-8000-000000501012'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'B Main');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501011'::uuid, 'Holdout Member A One', '+919000050001'),
  ('00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501011'::uuid, 'Holdout Member A Two', '+919000050003'),
  ('00000000-0000-4000-8000-000000501024'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501011'::uuid, 'Holdout Member A Three', '+919000050004'),
  ('00000000-0000-4000-8000-000000501022'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501012'::uuid, 'Holdout Member B One', '+919000050002');

insert into public.staff (id, tenant_id, role, full_name) values
  ('00000000-0000-4000-8000-000000501031'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'front_desk', 'Holdout Staff A'),
  ('00000000-0000-4000-8000-000000501032'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'front_desk', 'Holdout Staff B');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('00000000-0000-4000-8000-000000501041'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'Holdout Monthly', 30, 250000),
  ('00000000-0000-4000-8000-000000501042'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'Holdout Monthly', 30, 300000);

insert into public.coupons (id, tenant_id, code, percent_bp) values
  ('00000000-0000-4000-8000-000000501051'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'HOLDOUT10', 1000),
  ('00000000-0000-4000-8000-000000501052'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'HOLDOUT10', 1000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('00000000-0000-4000-8000-000000501061'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-09-01', date '2026-10-01', 250000),
  ('00000000-0000-4000-8000-000000501063'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'expired', date '2026-06-01', date '2026-07-01', 250000),
  ('00000000-0000-4000-8000-000000501064'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501024'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-09-01', date '2026-10-01', 250000),
  ('00000000-0000-4000-8000-000000501062'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, '00000000-0000-4000-8000-000000501042'::uuid, 'active', date '2026-09-01', date '2026-10-01', 300000);

insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values
  ('00000000-0000-4000-8000-000000501071'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501061'::uuid, date '2026-09-10', date '2026-09-20', 'holdout travel'),
  ('00000000-0000-4000-8000-000000501072'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501062'::uuid, date '2026-09-10', date '2026-09-20', 'holdout travel');

insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, receipt_number, recorded_by_staff_id, paid_at) values
  ('00000000-0000-4000-8000-000000501081'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501061'::uuid, 250000, 'paid', 'cash', 'RCPT-5001', '00000000-0000-4000-8000-000000501031'::uuid, now()),
  ('00000000-0000-4000-8000-000000501085'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, null, 150000, 'paid', 'cash', 'RCPT-5004', '00000000-0000-4000-8000-000000501031'::uuid, now()),
  ('00000000-0000-4000-8000-000000501082'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, '00000000-0000-4000-8000-000000501062'::uuid, 300000, 'paid', 'cash', 'RCPT-5002', '00000000-0000-4000-8000-000000501032'::uuid, now()),
  ('00000000-0000-4000-8000-000000501084'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, null, 120000, 'paid', 'cash', 'RCPT-5003', '00000000-0000-4000-8000-000000501032'::uuid, now());

insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, provider, provider_order_id, provider_payment_id, paid_at) values
  ('00000000-0000-4000-8000-000000501083'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 250000, 'paid', 'razorpay', 'razorpay', 'order_5001', 'pay_5001', now());

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values
  ('00000000-0000-4000-8000-000000501091'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'refund', 100000, 'holdout fixture'),
  ('00000000-0000-4000-8000-000000501092'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501082'::uuid, 'refund', 100000, 'holdout fixture');

insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values
  ('00000000-0000-4000-8000-0000005010a1'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'evt_5001', 'payment.captured', '{}'::jsonb, true),
  ('00000000-0000-4000-8000-0000005010a2'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'evt_5002', 'payment.captured', '{}'::jsonb, true);

insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values
  ('00000000-0000-4000-8000-0000005010b1'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'INV-5001', '2026-27', 'Holdout Member A One', 211864, 250000),
  ('00000000-0000-4000-8000-0000005010b2'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501082'::uuid, 'INV-5002', '2026-27', 'Holdout Member B One', 254237, 300000);

insert into public.document_counters (tenant_id, kind, financial_year) values
  ('00000000-0000-4000-8000-000000501001'::uuid, 'invoice', '2026-27'),
  ('00000000-0000-4000-8000-000000501002'::uuid, 'invoice', '2026-27');

insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values
  ('00000000-0000-4000-8000-000000501001'::uuid, 'rzp_test_5001', '00000000-0000-4000-8000-0000005010d1'::uuid, '00000000-0000-4000-8000-0000005010d2'::uuid),
  ('00000000-0000-4000-8000-000000501002'::uuid, 'rzp_test_5002', '00000000-0000-4000-8000-0000005010d3'::uuid, '00000000-0000-4000-8000-0000005010d4'::uuid);

insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values
  ('00000000-0000-4000-8000-0000005010c1'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 'sub_5001', 500000),
  ('00000000-0000-4000-8000-0000005010c2'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, 'sub_5002', 500000);

-- ============================================================
-- 8. No claim at all: the GUC has never been set in this transaction
-- ============================================================

set local role authenticated;

select lives_ok($$
  select 1 from public.plans
  union all select 1 from public.coupons
  union all select 1 from public.memberships
  union all select 1 from public.membership_pauses
  union all select 1 from public.payments
  union all select 1 from public.refunds
  union all select 1 from public.webhook_events
  union all select 1 from public.invoices
  union all select 1 from public.document_counters
  union all select 1 from public.razorpay_accounts
  union all select 1 from public.razorpay_mandates
$$, 'gate 7: a session with no jwt claim reads the money tables without raising');

select is_empty($$
  select 1 from public.plans
  union all select 1 from public.coupons
  union all select 1 from public.memberships
  union all select 1 from public.membership_pauses
  union all select 1 from public.payments
  union all select 1 from public.refunds
  union all select 1 from public.webhook_events
  union all select 1 from public.invoices
  union all select 1 from public.document_counters
  union all select 1 from public.razorpay_accounts
  union all select 1 from public.razorpay_mandates
$$, 'gate 7: a session with no jwt claim sees zero rows in every money table');

select ok(app.current_tenant_id() is null,
  'gate 7: the tenant accessor yields null rather than raising when no claim is set');

select ok(not app.is_platform(),
  'gate 7: the platform accessor is false when no claim is set');

set local role postgres;

-- ============================================================
-- 9. Acting as a gym_owner of Gym A
-- ============================================================

-- Phase 5 (manual-payment, GL034): app.custom_access_token_hook() stamps a `staff_id` claim
-- for every real staff token, so a session with none is not a realistic gym_owner session any
-- more -- carry the same staff id the fixtures already gave Gym A's staff member, so the write
-- control below records a payment as a real acting staff member rather than nobody.
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '00000000-0000-4000-8000-000000501001', 'app_role', 'gym_owner', 'staff_id', '00000000-0000-4000-8000-000000501031')::text, true);
set local role authenticated;

select isnt_empty($$ select 1 from public.plans where id = '00000000-0000-4000-8000-000000501041'::uuid $$,
  'gate 7 control: Gym A sees its own plan');
select isnt_empty($$ select 1 from public.memberships where id = '00000000-0000-4000-8000-000000501061'::uuid $$,
  'gate 7 control: Gym A sees its own membership');
select isnt_empty($$ select 1 from public.payments where id = '00000000-0000-4000-8000-000000501081'::uuid $$,
  'gate 7 control: Gym A sees its own payment');
select isnt_empty($$ select 1 from public.razorpay_accounts where tenant_id = '00000000-0000-4000-8000-000000501001'::uuid $$,
  'gate 7 control: Gym A sees its own Razorpay connection');

select is_empty($$ select 1 from public.plans where id = '00000000-0000-4000-8000-000000501042'::uuid $$,
  'gate 7: Gym A cannot select the plans of Gym B');
select is_empty($$ select 1 from public.coupons where id = '00000000-0000-4000-8000-000000501052'::uuid $$,
  'gate 7: Gym A cannot select the coupons of Gym B');
select is_empty($$ select 1 from public.memberships where id = '00000000-0000-4000-8000-000000501062'::uuid $$,
  'gate 7: Gym A cannot select the memberships of Gym B');
select is_empty($$ select 1 from public.membership_pauses where id = '00000000-0000-4000-8000-000000501072'::uuid $$,
  'gate 7: Gym A cannot select the membership_pauses of Gym B');
select is_empty($$ select 1 from public.payments where id = '00000000-0000-4000-8000-000000501082'::uuid $$,
  'gate 7: Gym A cannot select the payments of Gym B');
select is_empty($$ select 1 from public.refunds where id = '00000000-0000-4000-8000-000000501092'::uuid $$,
  'gate 7: Gym A cannot select the refunds of Gym B');
select is_empty($$ select 1 from public.webhook_events where id = '00000000-0000-4000-8000-0000005010a2'::uuid $$,
  'gate 7: Gym A cannot select the webhook_events of Gym B');
select is_empty($$ select 1 from public.invoices where id = '00000000-0000-4000-8000-0000005010b2'::uuid $$,
  'gate 7: Gym A cannot select the invoices of Gym B');
select is_empty($$ select 1 from public.document_counters where tenant_id = '00000000-0000-4000-8000-000000501002'::uuid $$,
  'gate 7: Gym A cannot select the document_counters of Gym B');
select is_empty($$ select 1 from public.razorpay_accounts where tenant_id = '00000000-0000-4000-8000-000000501002'::uuid $$,
  'gate 7: Gym A cannot select the razorpay_accounts of Gym B');
select is_empty($$ select 1 from public.razorpay_mandates where id = '00000000-0000-4000-8000-0000005010c2'::uuid $$,
  'gate 7: Gym A cannot select the razorpay_mandates of Gym B');

update public.plans set name = 'hijacked-holdout' where id = '00000000-0000-4000-8000-000000501042'::uuid;
update public.coupons set code = 'HIJACK5001' where id = '00000000-0000-4000-8000-000000501052'::uuid;
update public.membership_pauses set reason = 'hijacked-holdout' where id = '00000000-0000-4000-8000-000000501072'::uuid;
update public.document_counters set next_number = 9999 where tenant_id = '00000000-0000-4000-8000-000000501002'::uuid;
update public.razorpay_mandates set provider_customer_id = 'hijacked-holdout' where id = '00000000-0000-4000-8000-0000005010c2'::uuid;

select lives_ok($$ update public.memberships set cancel_reason = 'hijacked-holdout' where id = '00000000-0000-4000-8000-000000501062'::uuid $$,
  'gate 7: a cross-tenant update of memberships filters rather than raises');
select lives_ok($$ update public.payments set notes = 'hijacked-holdout' where id = '00000000-0000-4000-8000-000000501082'::uuid $$,
  'gate 7: a cross-tenant update of payments filters rather than raises');
select lives_ok($$ update public.refunds set reason = 'hijacked-holdout' where id = '00000000-0000-4000-8000-000000501092'::uuid $$,
  'gate 7: a cross-tenant update of refunds filters rather than raises');
select lives_ok($$ update public.invoices set buyer_name = 'hijacked-holdout' where id = '00000000-0000-4000-8000-0000005010b2'::uuid $$,
  'gate 7: a cross-tenant update of invoices filters rather than raises');
select lives_ok($$ update public.razorpay_accounts set key_id = 'hijacked-holdout' where tenant_id = '00000000-0000-4000-8000-000000501002'::uuid $$,
  'gate 7: a cross-tenant update of razorpay_accounts filters rather than raises');

select throws_ok($$ update public.webhook_events set processing_error = 'hijacked-holdout' where id = '00000000-0000-4000-8000-0000005010a2'::uuid $$,
  '42501'::char(5), null::text,
  'contract Privileges: an update of webhook_events is refused for want of privilege');

select throws_ok($$ insert into public.plans (id, tenant_id, name, duration_days, price_paise) values ('00000000-0000-4000-8000-0000005010e1'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'Cross Tenant Plan', 30, 100) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a plan labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.coupons (id, tenant_id, code, flat_paise) values ('00000000-0000-4000-8000-0000005010e2'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'XTENANT', 1000) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a coupon labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise) values ('00000000-0000-4000-8000-0000005010e3'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, '00000000-0000-4000-8000-000000501042'::uuid, 100) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a membership labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values ('00000000-0000-4000-8000-0000005010e4'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501062'::uuid, date '2026-11-01', date '2026-11-05', 'xtenant') $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a membership_pause labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values ('00000000-0000-4000-8000-0000005010e5'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, 100, 'cash', '00000000-0000-4000-8000-000000501032'::uuid) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a payment labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values ('00000000-0000-4000-8000-0000005010e6'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501082'::uuid, 'refund', 100, 'xtenant') $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a refund labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values ('00000000-0000-4000-8000-0000005010e7'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'evt_xtenant', 'payment.captured', '{}'::jsonb, false) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a webhook_event labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values ('00000000-0000-4000-8000-0000005010ea'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'evt_self_issued', 'payment.captured', '{}'::jsonb, true) $$,
  '42501'::char(5), null::text,
  'ADR-049: Gym A cannot insert a webhook_event into its own tenant either - the table is read-only to a gym session, so a gym cannot forge a delivery it marked signature_valid itself');
select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-0000005010e8'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501084'::uuid, 'INV-XTENANT', '2026-27', 'Cross Tenant', 100, 100) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert an invoice labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.document_counters (tenant_id, kind, financial_year) values ('00000000-0000-4000-8000-000000501002'::uuid, 'receipt', '2026-27') $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a document_counter labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values ('00000000-0000-4000-8000-000000501002'::uuid, 'rzp_xtenant', '00000000-0000-4000-8000-0000005010d1'::uuid, '00000000-0000-4000-8000-0000005010d2'::uuid) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a razorpay_account labelled with the tenant id of Gym B');
select throws_ok($$ insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values ('00000000-0000-4000-8000-0000005010e9'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, 'sub_xtenant', 100) $$,
  '42501'::char(5), null::text,
  'gate 7: Gym A cannot insert a mandate labelled with the tenant id of Gym B');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values ('00000000-0000-4000-8000-0000005010f3'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 50000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid) $$,
  'gate 7 control: Gym A can insert a payment into its own tenant');

select throws_ok($$ delete from public.payments where id = '00000000-0000-4000-8000-000000501081'::uuid $$,
  '42501'::char(5), null::text,
  'INT-001 scenario "Deleting a payment": refused for want of privilege');

select lives_ok($$ update public.memberships set status = 'cancelled', cancelled_at = now() where id = '00000000-0000-4000-8000-000000501064'::uuid $$,
  'INT-001 scenario "Cancelling a membership instead": the update succeeds');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select results_eq(
  $$ select status::text collate "default" from public.memberships where id = '00000000-0000-4000-8000-000000501064'::uuid $$,
  $$ values ('cancelled'::text) $$,
  'INT-001 scenario "Cancelling a membership instead": the row remains, cancelled');

select is_empty($$
  select 'plans' from public.plans where name = 'hijacked-holdout'
  union all select 'coupons' from public.coupons where code = 'HIJACK5001'
  union all select 'memberships' from public.memberships where cancel_reason = 'hijacked-holdout'
  union all select 'membership_pauses' from public.membership_pauses where reason = 'hijacked-holdout'
  union all select 'payments' from public.payments where notes = 'hijacked-holdout'
  union all select 'refunds' from public.refunds where reason = 'hijacked-holdout'
  union all select 'invoices' from public.invoices where buyer_name = 'hijacked-holdout'
  union all select 'document_counters' from public.document_counters where next_number = 9999
  union all select 'razorpay_accounts' from public.razorpay_accounts where key_id = 'hijacked-holdout'
  union all select 'razorpay_mandates' from public.razorpay_mandates where provider_customer_id = 'hijacked-holdout'
$$, 'gate 7: not one cross-tenant update by primary key changed a row of Gym B');

-- ============================================================
-- 10. An empty claim string behaves exactly like a missing one
-- ============================================================

set local role authenticated;

select lives_ok($$
  select 1 from public.payments
  union all select 1 from public.memberships
  union all select 1 from public.invoices
  union all select 1 from public.razorpay_accounts
$$, 'gate 7: an empty jwt claim reads without raising');

select is_empty($$
  select 1 from public.payments
  union all select 1 from public.memberships
  union all select 1 from public.invoices
  union all select 1 from public.razorpay_accounts
$$, 'gate 7: an empty jwt claim sees zero rows');

select ok(app.current_tenant_id() is null,
  'gate 7: an empty jwt claim yields a null tenant id rather than raising');

set local role postgres;

-- ============================================================
-- 11. A malformed tenant claim fails loudly rather than reading as empty
-- ============================================================

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', 'not-a-uuid', 'app_role', 'gym_owner')::text, true);
set local role authenticated;

select throws_ok($$ select 1 from public.payments $$,
  '22P02'::char(5), null::text,
  'contract accessors: a tenant claim that is not a uuid raises rather than degrading to zero rows');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ============================================================
-- 12. The platform branch crosses tenants by policy
-- ============================================================

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '00000000-0000-4000-8000-000000501001', 'app_role', 'super_admin')::text, true);
set local role authenticated;

select isnt_empty($$ select 1 from public.memberships where id = '00000000-0000-4000-8000-000000501062'::uuid $$,
  'RLS policy map: super_admin crosses tenants on memberships');
select isnt_empty($$ select 1 from public.payments where id = '00000000-0000-4000-8000-000000501082'::uuid $$,
  'RLS policy map: super_admin crosses tenants on payments');
select isnt_empty($$ select 1 from public.invoices where id = '00000000-0000-4000-8000-0000005010b2'::uuid $$,
  'RLS policy map: super_admin crosses tenants on invoices');
select isnt_empty($$ select 1 from public.razorpay_accounts where tenant_id = '00000000-0000-4000-8000-000000501002'::uuid $$,
  'RLS policy map: super_admin crosses tenants on razorpay_accounts');

select lives_ok($$ insert into public.plans (id, tenant_id, name, duration_days, price_paise) values ('00000000-0000-4000-8000-0000005010f4'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'Platform Written Plan', 30, 100) $$,
  'RLS policy map: the platform with check admits a write into another tenant');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'tenant_id', '00000000-0000-4000-8000-000000501001', 'app_role', 'platform_support')::text, true);
set local role authenticated;

select isnt_empty($$ select 1 from public.payments where id = '00000000-0000-4000-8000-000000501082'::uuid $$,
  'RLS policy map: platform_support crosses tenants on payments');
select isnt_empty($$ select 1 from public.memberships where id = '00000000-0000-4000-8000-000000501062'::uuid $$,
  'RLS policy map: platform_support crosses tenants on memberships');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ============================================================
-- 13. A membership without an expiry date cannot be stored once it is live (DQA-001)
-- ============================================================

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise) values ('00000000-0000-4000-8000-000000502001'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', 250000) $$,
  '23514'::char(5), null::text,
  'DQA-001 scenario "An active membership with no expiry"');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, price_paise) values ('00000000-0000-4000-8000-000000502002'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-09-01', 250000) $$,
  '23514'::char(5), null::text,
  'DQA-001: an active membership with a start but no end is refused');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise) values ('00000000-0000-4000-8000-000000502003'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'cancelled', 250000) $$,
  '23514'::char(5), null::text,
  'DQA-001: only a pending membership may lack both dates');

select lives_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise) values ('00000000-0000-4000-8000-000000502004'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'pending', 250000) $$,
  'DQA-001 scenario "A pending membership with no dates"');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values ('00000000-0000-4000-8000-000000502005'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-10-01', date '2026-09-01', 250000) $$,
  '23514'::char(5), null::text,
  'DQA-001 scenario "An expiry before the start"');

-- ============================================================
-- 14. A member has at most one live membership
-- ============================================================

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values ('00000000-0000-4000-8000-000000502007'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-10-01', date '2026-11-01', 250000) $$,
  '23505'::char(5), null::text,
  'one live membership scenario "A second active membership"');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values ('00000000-0000-4000-8000-000000502008'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'frozen', date '2026-10-01', date '2026-11-01', 250000) $$,
  '23505'::char(5), null::text,
  'one live membership: frozen counts as live alongside active');

select lives_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, renewal_of_membership_id) values ('00000000-0000-4000-8000-000000502009'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501023'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 'active', date '2026-09-01', date '2026-10-01', 250000, '00000000-0000-4000-8000-000000501063'::uuid) $$,
  'one live membership scenario "A renewal alongside an expired period"');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise, renewal_of_membership_id) values ('00000000-0000-4000-8000-000000502010'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501024'::uuid, '00000000-0000-4000-8000-000000501041'::uuid, 250000, '00000000-0000-4000-8000-000000502099'::uuid) $$,
  '23503'::char(5), null::text,
  'one live membership: a renewal must point at a membership that exists');

select throws_ok($$ insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values ('00000000-0000-4000-8000-000000502005'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, '00000000-0000-4000-8000-000000501042'::uuid, 'active', date '2026-10-01', date '2026-11-01', 300000) $$,
  '23503'::char(5), null::text,
  'ADR-052: gym B cannot open a membership in its own tenant naming gym A''s member - memberships.member_id is (tenant_id, member_id) references members (tenant_id, id), and the composite key refuses it where RLS never could, because referential integrity runs with row security off. The ADR-047 half of this rule, that the live-membership key is itself (tenant_id, member_id), is no longer observable from a write and is asserted over the catalogue below');

select is(
  (select count(*)::int
     from pg_index i
    where i.indrelid = 'public.memberships'::regclass
      and i.indisunique
      and i.indpred is not null
      and i.indnkeyatts = 2
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'member_id'::text
      and pg_get_expr(i.indpred, i.indrelid) like '%status%'),
  1,
  'ADR-047: exactly one unique partial index on (tenant_id, member_id) qualified by status enforces the one-live-membership rule');

-- ============================================================
-- 15. A paid payment always carries a reference (DQA-002) and offline carries staff (PAY-011)
-- ============================================================

-- Phase 5 (manual-payment): a payment that becomes 'paid' is now allocated a receipt number
-- from document_counters on EVERY write path, before payments_paid_has_reference_chk is ever
-- evaluated - so an insert that used to reach this CHECK with neither a receipt_number nor a
-- provider_payment_id no longer can; the state DQA-002 names is unreachable through a normal
-- insert. The constraint still stands (verified via pg_constraint, not assumed): assert its
-- continued existence and definition instead of a state nothing can produce any more.
select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_paid_has_reference_chk'),
  $chk$CHECK (((status <> 'paid'::payment_status) OR (provider_payment_id IS NOT NULL) OR (receipt_number IS NOT NULL)))$chk$,
  'DQA-002 scenario "Paid with no reference at all": payments_paid_has_reference_chk still stands, though a paid payment is now always allocated a receipt number before it is evaluated');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id, paid_at) values ('00000000-0000-4000-8000-000000502012'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'paid', 'cash', 'RCPT-5010', '00000000-0000-4000-8000-000000501031'::uuid, now()) $$,
  'DQA-002 scenario "An offline payment marked paid with a receipt"');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, provider, provider_order_id, provider_payment_id, paid_at) values ('00000000-0000-4000-8000-000000502013'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'paid', 'razorpay', 'razorpay', 'order_5010', 'pay_5010', now()) $$,
  'DQA-002: a gateway payment marked paid with a provider reference is accepted');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method) values ('00000000-0000-4000-8000-000000502014'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash') $$,
  '23514'::char(5), null::text,
  'PAY-011 scenario "Cash recorded by nobody"');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method) values ('00000000-0000-4000-8000-000000502015'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'upi') $$,
  '23514'::char(5), null::text,
  'PAY-011: an offline UPI payment with no recording staff member is refused');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, provider, provider_order_id) values ('00000000-0000-4000-8000-000000502016'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'razorpay', 'razorpay', 'order_5011') $$,
  'PAY-011 scenario "A gateway payment with no recording staff member"');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, provider) values ('00000000-0000-4000-8000-000000502017'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'razorpay', 'razorpay') $$,
  '23514'::char(5), null::text,
  'PAY-006: a gateway payment must carry the provider order it belongs to');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values ('00000000-0000-4000-8000-000000502018'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 0, 'cash', '00000000-0000-4000-8000-000000501031'::uuid) $$,
  '23514'::char(5), null::text,
  'MNY-001 scenario "A negative amount to be collected", at zero');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values ('00000000-0000-4000-8000-00000050201a'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501032'::uuid) $$,
  '23503'::char(5), null::text,
  'ADR-052: gym A cannot attribute its own payment to gym B''s staff member - payments.recorded_by_staff_id is (tenant_id, recorded_by_staff_id) references staff (tenant_id, id), so PAY-011''s attribution now names someone who actually works there');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, membership_id, coupon_id, mandate_id) values ('00000000-0000-4000-8000-00000050201b'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid, null, null, null) $$,
  'ADR-052: a composite key is match simple, so a row is exempt from the check when any key column is null - the three optional references left null are still accepted, which is the behaviour match full would break, and tenant_id being not null is what makes the exemption fire only on the optional column');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, provider_payment_id) values ('00000000-0000-4000-8000-000000502019'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid, 'pay_orphan_5001') $$,
  '23514'::char(5), null::text,
  'ADR-047: a provider payment reference with no provider beside it is rejected - provider sits inside the duplicate-reference unique index, and a null key column would make every such row distinct');

-- ============================================================
-- 16. Receipt, invoice and provider references are unique per gym
-- ============================================================

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id, paid_at) values ('00000000-0000-4000-8000-000000502020'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'paid', 'cash', 'RCPT-5001', '00000000-0000-4000-8000-000000501031'::uuid, now()) $$,
  '23505'::char(5), null::text,
  'unique numbering scenario "A repeated receipt number at one gym"');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id, paid_at) values ('00000000-0000-4000-8000-000000502021'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, 100000, 'paid', 'cash', 'RCPT-5001', '00000000-0000-4000-8000-000000501032'::uuid, now()) $$,
  'unique numbering scenario "The same receipt number at another gym"');

select lives_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values ('00000000-0000-4000-8000-000000502022'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid), ('00000000-0000-4000-8000-000000502023'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid) $$,
  'unique numbering scenario "Two payments with no receipt number"');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, provider, provider_order_id, provider_payment_id, paid_at) values ('00000000-0000-4000-8000-000000502024'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'paid', 'razorpay', 'razorpay', 'order_5012', 'pay_5001', now()) $$,
  '23505'::char(5), null::text,
  'unique numbering: a duplicate provider payment reference at one gym is refused');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, idempotency_key) values ('00000000-0000-4000-8000-000000502026'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid, 'idem-5001'), ('00000000-0000-4000-8000-000000502027'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid, 'idem-5001') $$,
  '23505'::char(5), null::text,
  'PAY-009: a repeated idempotency key at one gym is refused');

-- ============================================================
-- 17. A duplicate webhook delivery cannot be recorded twice (PAY-009)
-- ============================================================

select throws_ok($$ insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values ('00000000-0000-4000-8000-000000502028'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'evt_5001', 'payment.captured', '{}'::jsonb, true) $$,
  '23505'::char(5), null::text,
  'PAY-009 scenario "The same event delivered twice"');

select lives_ok($$ insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values ('00000000-0000-4000-8000-000000502029'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, 'evt_5001', 'payment.captured', '{}'::jsonb, true) $$,
  'PAY-009 scenario "The same event id at another gym"');

select lives_ok($$ insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid) values ('00000000-0000-4000-8000-000000502030'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'evt_5005', 'payment.failed', '{}'::jsonb, false) $$,
  'payment integrity: a delivery whose signature did not verify is still recorded');

select hasnt_column('public'::name, 'webhook_events'::name, 'updated_at'::name,
  'contract Every table: webhook_events is written once and carries no updated_at'::text);

-- ============================================================
-- 18. A refund is a separate record, never a mutation of the payment (PAY-010)
-- ============================================================

select throws_ok($$ insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values ('00000000-0000-4000-8000-000000502031'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'refund', 100000, '') $$,
  '23514'::char(5), null::text,
  'PAY-010 scenario "A refund with no reason"');

select throws_ok($$ insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values ('00000000-0000-4000-8000-000000502032'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000502098'::uuid, 'refund', 100000, 'orphan') $$,
  '23503'::char(5), null::text,
  'PAY-010 scenario "A refund of a non-existent payment"');

select throws_ok($$ insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason) values ('00000000-0000-4000-8000-000000502033'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'chargeback', 100000, 'unknown kind') $$,
  '22P02'::char(5), null::text,
  'contract Enums: refund_kind is a closed vocabulary');

select results_eq(
  $$ select status::text collate "default" from public.refunds where id = '00000000-0000-4000-8000-000000501091'::uuid $$,
  $$ values ('requested'::text) $$,
  'PAY-010: a refund row begins in requested and carries its own status');

select results_eq(
  $$ select status::text collate "default", amount_paise from public.payments where id = '00000000-0000-4000-8000-000000501081'::uuid $$,
  $$ values ('paid'::text, 250000::bigint) $$,
  'PAY-010: the refunded payment row is untouched by the refund beside it');

-- ============================================================
-- 19. A coupon carries exactly one kind of discount
-- ============================================================

select throws_ok($$ insert into public.coupons (id, tenant_id, code, percent_bp, flat_paise) values ('00000000-0000-4000-8000-000000502035'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'BOTH5001', 1000, 5000) $$,
  '23514'::char(5), null::text,
  'coupon scenario "A coupon with both discount kinds"');

select throws_ok($$ insert into public.coupons (id, tenant_id, code) values ('00000000-0000-4000-8000-000000502036'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'NEITHER5001') $$,
  '23514'::char(5), null::text,
  'coupon scenario "A coupon with neither"');

select lives_ok($$ insert into public.coupons (id, tenant_id, code, percent_bp) values ('00000000-0000-4000-8000-000000502037'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'HOLDOUT20', 2000) $$,
  'coupon: a percentage-only coupon is accepted');

select lives_ok($$ insert into public.coupons (id, tenant_id, code, flat_paise) values ('00000000-0000-4000-8000-000000502038'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'HOLDOUT30', 50000) $$,
  'coupon: a flat-amount-only coupon is accepted');

select throws_ok($$ insert into public.coupons (id, tenant_id, code, percent_bp) values ('00000000-0000-4000-8000-000000502039'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'HOLDOUT10', 1000) $$,
  '23505'::char(5), null::text,
  'coupon: a duplicate code within one organisation is refused');

-- ============================================================
-- 20. Plans and the currency format check (MNY-002)
-- ============================================================

select throws_ok($$ insert into public.plans (id, tenant_id, name, duration_days, price_paise) values ('00000000-0000-4000-8000-000000502043'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'Negative Plan', 30, -1) $$,
  '23514'::char(5), null::text,
  'MNY-001: a plan priced below zero is refused');

select throws_ok($$ insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency) values ('00000000-0000-4000-8000-000000502045'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, 'Rupees Plan', 30, 250000, 'Rupees') $$,
  '23514'::char(5), null::text,
  'MNY-002 scenario "A currency code that is not a three-letter code", on plans');

select throws_ok($$ insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, currency) values ('00000000-0000-4000-8000-000000502046'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 100000, 'cash', '00000000-0000-4000-8000-000000501031'::uuid, 'Rupees') $$,
  '23514'::char(5), null::text,
  'MNY-002: a payment currency that is not a three-letter code is refused');

select results_eq(
  $$ select currency::text collate "default" from public.plans where id = '00000000-0000-4000-8000-000000501041'::uuid $$,
  $$ values ('INR'::text) $$,
  'MNY-002: a money row written without a currency defaults to INR');

-- ============================================================
-- 21. Invoices and per-gym, per-year numbering
-- ============================================================

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502048'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501083'::uuid, 'INV-5009', '2026', 'Holdout Member A One', 100000, 100000) $$,
  '23514'::char(5), null::text,
  'invoice numbering scenario "A malformed financial year"');

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise, currency) values ('00000000-0000-4000-8000-000000502049'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501083'::uuid, 'INV-5008', '2026-27', 'Holdout Member A One', 100000, 100000, 'Rupees') $$,
  '23514'::char(5), null::text,
  'MNY-002: an invoice currency that is not a three-letter code is refused');

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502050'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501083'::uuid, 'INV-5007', '2026-27', 'Holdout Member A One', -1, 100000) $$,
  '23514'::char(5), null::text,
  'MNY-001: an invoice with a negative taxable amount is refused');

select lives_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502051'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501083'::uuid, 'INV-5010', '2026-27', 'Holdout Member A One', 211864, 250000) $$,
  'invoice numbering: a financial year written as 2026-27 is accepted');

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502052'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501085'::uuid, 'INV-5001', '2026-27', 'Holdout Member A One', 100000, 100000) $$,
  '23505'::char(5), null::text,
  'unique numbering: a duplicate invoice number within one organisation is refused');

select lives_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502053'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501084'::uuid, 'INV-5001', '2026-27', 'Holdout Member B One', 100000, 100000) $$,
  'unique numbering: the same invoice number at another gym is accepted');

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502054'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'INV-5011', '2026-27', 'Holdout Member A One', 100000, 100000) $$,
  '23505'::char(5), null::text,
  'invoice numbering: one payment carries at most one invoice within the gym that took it');

select throws_ok($$ insert into public.invoices (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values ('00000000-0000-4000-8000-000000502055'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501081'::uuid, 'INV-5091', '2026-27', 'Holdout Member B One', 100000, 100000) $$,
  '23503'::char(5), null::text,
  'ADR-052: gym B cannot invoice gym A''s payment from inside its own tenant - invoices.payment_id is (tenant_id, payment_id) references payments (tenant_id, id). This is the write that made the ADR-049 global unique a denial of service; the key shape it needed is asserted over the catalogue below');

select is(
  (select count(*)::int
     from pg_index i
    where i.indrelid = 'public.invoices'::regclass
      and i.indisunique
      and i.indpred is null
      and i.indnkeyatts = 2
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'tenant_id'::text
      and (select a.attname::text collate "default" from pg_attribute a
            where a.attrelid = i.indrelid and a.attnum = i.indkey[1]) = 'payment_id'::text),
  1,
  'ADR-049: exactly one unique index on (tenant_id, payment_id) backs the rule - asserted over pg_index, which sees a table-level unique constraint and a create unique index alike, since the shape of the declaration is what hid this instance from four earlier reviews');

select throws_ok($$ insert into public.document_counters (tenant_id, kind, financial_year) values ('00000000-0000-4000-8000-000000501001'::uuid, 'quotation', '2026-27') $$,
  '23514'::char(5), null::text,
  'invoice numbering: a counter kind outside invoice and receipt is refused');

select throws_ok($$ insert into public.document_counters (tenant_id, kind, financial_year) values ('00000000-0000-4000-8000-000000501001'::uuid, 'invoice', '2026-27') $$,
  '23505'::char(5), null::text,
  'invoice numbering scenario "One counter per gym, kind and year"');

-- Phase 5 (manual-payment): a 'paid' payment now allocates its own receipt counter row on
-- write, on every write path, so a 'receipt' counter for this gym and year may already exist
-- by the time a test inserts one - it does here, from the payments recorded earlier in this
-- file. The test no longer owns document_counters, so it can't prove separateness by being the
-- one to insert the receipt row without colliding. The property survives regardless: assert it
-- by observing that both an 'invoice' and a 'receipt' counter coexist for the same gym and
-- year, which is what "counted separately" actually means and stays meaningful however the
-- product's own allocation timing changes later.
select is(
  (select count(distinct kind)::int from public.document_counters
    where tenant_id = '00000000-0000-4000-8000-000000501001'::uuid and financial_year = '2026-27'),
  2,
  'invoice numbering: invoice and receipt series are counted separately per gym and year');

select col_is_pk('public'::name, 'document_counters'::name,
  array['tenant_id','kind','financial_year']::name[],
  'contract Every table: document_counters is keyed by gym, kind and financial year'::text);

-- ============================================================
-- 22. Autopay mandate tables exist unused
-- ============================================================

select throws_ok($$ insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values ('00000000-0000-4000-8000-000000502055'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 'sub_5001', 500000) $$,
  '23505'::char(5), null::text,
  'mandate scenario "A mandate is unique per provider subscription"');

select lives_ok($$ insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values ('00000000-0000-4000-8000-000000502056'::uuid, '00000000-0000-4000-8000-000000501002'::uuid, '00000000-0000-4000-8000-000000501022'::uuid, 'sub_5001', 500000) $$,
  'mandate: the same provider subscription id at another gym is accepted');

select throws_ok($$ insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values ('00000000-0000-4000-8000-000000502057'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501021'::uuid, 'sub_5011', 0) $$,
  '23514'::char(5), null::text,
  'mandate scenario "A mandate with no ceiling"');

select throws_ok($$ insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values ('00000000-0000-4000-8000-000000501001'::uuid, 'rzp_test_dup', '00000000-0000-4000-8000-0000005010d1'::uuid, '00000000-0000-4000-8000-0000005010d2'::uuid) $$,
  '23505'::char(5), null::text,
  'PAY-005: one Razorpay connection per gym');

-- ============================================================
-- 23. Membership pauses
-- ============================================================

select throws_ok($$ insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values ('00000000-0000-4000-8000-000000502058'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501061'::uuid, date '2026-09-20', date '2026-09-10', 'backwards') $$,
  '23514'::char(5), null::text,
  'membership_pauses: a freeze cannot end before it starts');

select throws_ok($$ insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason) values ('00000000-0000-4000-8000-000000502059'::uuid, '00000000-0000-4000-8000-000000501001'::uuid, '00000000-0000-4000-8000-000000501061'::uuid, date '2026-09-10', date '2026-09-20', '') $$,
  '23514'::char(5), null::text,
  'membership_pauses: a freeze carries a stated reason');

select * from finish();

rollback;
