-- 05_membership_money_rls.sql
--
-- Cluster: membership+money. Cross-tenant half — the leak matrix for all
-- eleven tables this cluster owns, plus the privilege assertions that are
-- specific to money and history: INT-001 (no delete, no truncate),
-- webhook_events read-only (ADR-049), PAY-005 (no credential column), and the
-- MNY-002 currency-format check.
--
-- The structural half lives in 05_membership_money_structure.sql (tables,
-- enums, labels, *_paise is bigint, exactly one currency column per money
-- table, tenant_id present, RLS enabled, both policies named). Nothing it
-- asserts is repeated here.
--
-- Source of truth: openspec/changes/0001-data-model/specs/membership-and-money/spec.md,
-- docs/data-model.md § Conventions (the contract) / Cluster: membership+money,
-- docs/security.md § Tenancy isolation (RLS) and § Payment integrity.
-- Written from the spec before the DDL existed; every assertion names the
-- requirement id or the spec scenario it traces to.
--
-- ADR-030: the whole file is one transaction that rolls back. No COMMIT, no
-- bare END, no `do $$ ... end $$` block (scripts/check-pgtap-rollback.mjs).
--
-- Ordering note for the insert assertions: PostgreSQL evaluates RLS
-- WITH CHECK in ExecInsert *before* ExecConstraints and before index
-- insertion, so a cross-tenant insert raises 42501 rather than a unique or
-- check violation. Where a fixture makes a collision unavoidable
-- (razorpay_accounts is keyed by tenant_id alone) that is called out inline.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(136);

-- ===========================================================================
-- Fixtures, inserted as the owner. The contract forbids `force row level
-- security`, so RLS does not apply to `postgres` and these writes land.
-- Chain: organizations -> branches -> staff/members -> this cluster.
-- Gym codes MMRLSA / MMRLSB are unique to this file.
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001', 'Gym A membership money RLS', 'MMRLSA'),
  ('b0000000-0000-4000-8000-000000000001', 'Gym B membership money RLS', 'MMRLSB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'A Main', true),
  ('b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'gym_owner', 'A Owner'),
  ('b0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'gym_owner', 'B Owner');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Member', '+919000000001'),
  ('b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'B Member', '+919000000002');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'Gym A Plan', 30, 100000),
  ('b0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000001', 'Gym B Plan', 30, 100000);

insert into public.coupons (id, tenant_id, code, percent_bp) values
  ('a0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'ACOUPON', 1000),
  ('b0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000001', 'BCOUPON', 1000);

insert into public.memberships
  (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('a0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000005',
   'active', date '2026-09-01', date '2026-09-30', 100000),
  ('b0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000005',
   'active', date '2026-09-01', date '2026-09-30', 100000);

insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason) values
  ('a0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000007', date '2026-09-10', date '2026-09-12', 'Gym A freeze reason'),
  ('b0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000007', date '2026-09-10', date '2026-09-12', 'Gym B freeze reason');

-- Offline (cash) payments: PAY-011 requires recorded_by_staff_id, DQA-002
-- requires a reference on a `paid` row — a receipt number is that reference.
insert into public.payments
  (id, tenant_id, member_id, membership_id, amount_paise, method, status, receipt_number, recorded_by_staff_id) values
  ('a0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000007',
   100000, 'cash', 'paid', 'A-RCPT-1', 'a0000000-0000-4000-8000-000000000003'),
  ('b0000000-0000-4000-8000-000000000009', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000007',
   100000, 'cash', 'paid', 'B-RCPT-1', 'b0000000-0000-4000-8000-000000000003');

-- A second, uninvoiced payment per gym. invoices.payment_id is unique, so
-- every later invoice insert attempt needs a payment that has no invoice —
-- otherwise the attempt could fail for that reason instead of the one under
-- test. Status defaults to `created`, so DQA-002 does not demand a reference.
insert into public.payments
  (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id) values
  ('a0000000-0000-4000-8000-0000000000f9', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000004', 100000, 'cash', 'a0000000-0000-4000-8000-000000000003'),
  ('b0000000-0000-4000-8000-0000000000f9', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000004', 100000, 'cash', 'b0000000-0000-4000-8000-000000000003');

insert into public.refunds
  (id, tenant_id, payment_id, kind, amount_paise, reason) values
  ('a0000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000009', 'refund', 20000, 'Gym A refund reason'),
  ('b0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000009', 'refund', 20000, 'Gym B refund reason');

insert into public.webhook_events
  (id, tenant_id, event_id, event_type, payload, signature_valid) values
  ('a0000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-000000000001',
   'evt_mmrlsa_1', 'payment.captured', '{}'::jsonb, true),
  ('b0000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-000000000001',
   'evt_mmrlsb_1', 'payment.captured', '{}'::jsonb, true);

insert into public.invoices
  (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise) values
  ('a0000000-0000-4000-8000-00000000000c', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000009', 'A/2026-27/1', '2026-27', 'A Member', 84746, 100000),
  ('b0000000-0000-4000-8000-00000000000c', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000009', 'B/2026-27/1', '2026-27', 'B Member', 84746, 100000);

insert into public.document_counters (tenant_id, kind, financial_year) values
  ('a0000000-0000-4000-8000-000000000001', 'invoice', '2026-27'),
  ('b0000000-0000-4000-8000-000000000001', 'invoice', '2026-27');

insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id) values
  ('a0000000-0000-4000-8000-000000000001', 'rzp_test_gyma',
   'a0000000-0000-4000-8000-0000000000e1', 'a0000000-0000-4000-8000-0000000000e2'),
  ('b0000000-0000-4000-8000-000000000001', 'rzp_test_gymb',
   'b0000000-0000-4000-8000-0000000000e1', 'b0000000-0000-4000-8000-0000000000e2');

insert into public.razorpay_mandates
  (id, tenant_id, member_id, provider_subscription_id, max_amount_paise) values
  ('a0000000-0000-4000-8000-00000000000d', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000004', 'sub_mmrlsa_1', 500000),
  ('b0000000-0000-4000-8000-00000000000d', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000004', 'sub_mmrlsb_1', 500000);

-- ===========================================================================
-- 1-17. INT-001 made structural, and the append-only tier.
-- Three-argument has_table_privilege, so the assertion does not depend on
-- which role the session happens to be.
-- ===========================================================================

select ok(not has_table_privilege('authenticated', 'public.plans', 'DELETE'),
  'INT-001: authenticated holds no DELETE on plans');
select ok(not has_table_privilege('authenticated', 'public.plans', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on plans');
select ok(not has_table_privilege('authenticated', 'public.memberships', 'DELETE'),
  'INT-001: authenticated holds no DELETE on memberships');
select ok(not has_table_privilege('authenticated', 'public.memberships', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on memberships (RLS does not filter truncate)');
select ok(not has_table_privilege('authenticated', 'public.payments', 'DELETE'),
  'INT-001: authenticated holds no DELETE on payments');
select ok(not has_table_privilege('authenticated', 'public.payments', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on payments');
select ok(not has_table_privilege('authenticated', 'public.refunds', 'DELETE'),
  'INT-001: authenticated holds no DELETE on refunds');
select ok(not has_table_privilege('authenticated', 'public.refunds', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on refunds');
select ok(not has_table_privilege('authenticated', 'public.invoices', 'DELETE'),
  'INT-001: authenticated holds no DELETE on invoices');
select ok(not has_table_privilege('authenticated', 'public.invoices', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on invoices');
select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'DELETE'),
  'INT-001: authenticated holds no DELETE on webhook_events');
select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on webhook_events');
select ok(not has_table_privilege('authenticated', 'public.razorpay_mandates', 'DELETE'),
  'INT-001: authenticated holds no DELETE on razorpay_mandates');
select ok(not has_table_privilege('authenticated', 'public.razorpay_mandates', 'TRUNCATE'),
  'INT-001: authenticated holds no TRUNCATE on razorpay_mandates');

select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'UPDATE'),
  'PAY-009 (ADR-049): webhook_events is read-only to authenticated, so it holds no UPDATE');
select ok(has_table_privilege('authenticated', 'public.webhook_events', 'SELECT'),
  'PAY-009 (ADR-049): webhook_events is read-only to authenticated, so it holds SELECT and nothing else');
select ok(not has_table_privilege('authenticated', 'public.webhook_events', 'INSERT'),
  'ADR-049: webhook_events withholds INSERT from authenticated — signature_valid and payload are client-supplied, so an insert grant lets a gym write the record of a payment webhook it verified itself; only service_role writes this table');

-- ===========================================================================
-- 18-24. PAY-005 — no column can hold a raw card number or a raw UPI
-- credential, and the Razorpay row carries only Vault ids for its secrets.
-- The structural file already asserts, schema-wide, that no column named
-- card_number / card_no / cvv / upi_pin / key_secret / webhook_secret / secret
-- exists anywhere; those are not repeated. These are the names it does not
-- cover.
-- ===========================================================================

select hasnt_column('public', 'payments', 'pan',
  'PAY-005: payments has no pan column');
select hasnt_column('public', 'payments', 'upi_id',
  'PAY-005: payments has no upi_id column');
select hasnt_column('public', 'payments', 'vpa',
  'PAY-005: payments has no vpa column');
select hasnt_column('public', 'razorpay_accounts', 'pan',
  'PAY-005: razorpay_accounts has no pan column');
select hasnt_column('public', 'razorpay_accounts', 'upi_id',
  'PAY-005: razorpay_accounts has no upi_id column');
select hasnt_column('public', 'razorpay_accounts', 'vpa',
  'PAY-005: razorpay_accounts has no vpa column');

select is_empty($$
  select column_name
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'razorpay_accounts'
     and column_name ~ 'secret'
     and column_name not in ('key_secret_vault_id', 'webhook_secret_vault_id')
$$, 'PAY-005: the only secret-bearing columns on razorpay_accounts are the two Vault ids');

-- ===========================================================================
-- 25-60. Act as a signed-in gym owner of Gym A.
-- docs/security.md § Tenancy isolation: Gym A must never read or write Gym B.
-- Per table: select is filtered to Gym A, an update of Gym B's row by primary
-- key affects zero rows (a policy filters, it does not raise), and an insert
-- carrying Gym B's tenant_id raises 42501 (the `with check` half).
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- --- plans ----------------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.plans $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: plans select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.plans set name = 'HIJACKED'
     where id = 'b0000000-0000-4000-8000-000000000005'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: plans update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.plans (id, tenant_id, name, duration_days, price_paise)
  values ('b0000000-0000-4000-8000-0000000000f1', 'b0000000-0000-4000-8000-000000000001',
          'Gym B Plan Two', 30, 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: plans insert carrying gym B tenant_id is refused by with check');

-- --- coupons --------------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.coupons $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: coupons select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.coupons set code = 'HIJACKED'
     where id = 'b0000000-0000-4000-8000-000000000006'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: coupons update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.coupons (id, tenant_id, code, percent_bp)
  values ('b0000000-0000-4000-8000-0000000000f2', 'b0000000-0000-4000-8000-000000000001',
          'BCOUPON2', 1000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: coupons insert carrying gym B tenant_id is refused by with check');

-- --- memberships ----------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.memberships $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: memberships select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.memberships set status = 'cancelled'
     where id = 'b0000000-0000-4000-8000-000000000007'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: memberships update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise)
  values ('b0000000-0000-4000-8000-0000000000f3', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000005', 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: memberships insert carrying gym B tenant_id is refused by with check');

-- The other half of what `with check` is for, and the half nothing in this
-- suite covered: "an authenticated user can insert a row into another tenant,
-- OR MOVE ONE THERE" (docs/data-model.md, Row-Level Security). The row is gym
-- A's own, so the USING clause admits it and the update is not filtered away;
-- the NEW row carries gym B's tenant_id, so WITH CHECK fails and the statement
-- RAISES 42501 rather than affecting zero rows. A policy written
-- `with check (true)` beside a correct `using` would let this one succeed.
select throws_ok($$
  update public.memberships set tenant_id = 'b0000000-0000-4000-8000-000000000001'
   where id = 'a0000000-0000-4000-8000-000000000007'::uuid
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: gym A moving its OWN memberships row into gym B raises 42501 from the with check — not a filtered zero-row update, because the row is visible to the caller and it is the new tenant_id that is refused');

-- --- membership_pauses ----------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.membership_pauses $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: membership_pauses select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.membership_pauses set reason = 'HIJACKED'
     where id = 'b0000000-0000-4000-8000-000000000008'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: membership_pauses update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason)
  values ('b0000000-0000-4000-8000-0000000000f4', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000007', date '2026-10-01', date '2026-10-05', 'Cross tenant freeze')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: membership_pauses insert carrying gym B tenant_id is refused by with check');

-- --- payments -------------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.payments $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: payments select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.payments set amount_paise = 1
     where id = 'b0000000-0000-4000-8000-000000000009'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: payments update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('b0000000-0000-4000-8000-0000000000f5', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 100000, 'cash', 'b0000000-0000-4000-8000-000000000003')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: payments insert carrying gym B tenant_id is refused by with check');

-- --- refunds --------------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.refunds $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: refunds select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.refunds set amount_paise = 1
     where id = 'b0000000-0000-4000-8000-00000000000a'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: refunds update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason)
  values ('b0000000-0000-4000-8000-0000000000f6', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000009', 'refund', 1000, 'Cross tenant refund')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: refunds insert carrying gym B tenant_id is refused by with check');

-- --- webhook_events -------------------------------------------------------
-- webhook_events is read-only to authenticated (ADR-049), so both the
-- cross-tenant update and the cross-tenant insert are refused for want of
-- privilege (42501) before RLS is ever consulted. That is the correct outcome,
-- and stricter than "affects zero rows" or "rejected by with check" — but it
-- also means neither of the two assertions below is evidence about RLS.
select results_eq(
  $$ select distinct tenant_id from public.webhook_events $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: webhook_events select as gym A returns gym A rows and no other tenant'
);
select throws_ok($$
  update public.webhook_events set processing_error = 'HIJACKED'
   where id = 'b0000000-0000-4000-8000-00000000000b'::uuid
$$, '42501'::char(5), null::text,
  'INT-001 / PAY-009: webhook_events update of gym B row is refused for want of privilege');
select throws_ok($$
  insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid)
  values ('b0000000-0000-4000-8000-0000000000f7', 'b0000000-0000-4000-8000-000000000001',
          'evt_mmrlsb_2', 'payment.captured', '{}'::jsonb, true)
$$, '42501'::char(5), null::text,
  'ADR-049: webhook_events insert carrying gym B tenant_id is refused for want of privilege — the table is read-only to authenticated, so the refusal never reaches the with check');

-- --- invoices -------------------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.invoices $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: invoices select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.invoices set total_paise = 1
     where id = 'b0000000-0000-4000-8000-00000000000c'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: invoices update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.invoices
    (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise)
  values ('b0000000-0000-4000-8000-0000000000f8', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-0000000000f9', 'B/2026-27/2', '2026-27', 'B Member', 84746, 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: invoices insert carrying gym B tenant_id is refused by with check');

-- --- document_counters ----------------------------------------------------
-- Primary key is (tenant_id, kind, financial_year); the insert attempt uses a
-- kind gym B does not have, so RLS is the only reason it can fail.
select results_eq(
  $$ select distinct tenant_id from public.document_counters $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: document_counters select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.document_counters set next_number = 999
     where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid
       and kind = 'invoice' and financial_year = '2026-27'
     returning tenant_id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: document_counters update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year)
  values ('b0000000-0000-4000-8000-000000000001', 'receipt', '2026-27')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: document_counters insert carrying gym B tenant_id is refused by with check');

-- --- razorpay_accounts ----------------------------------------------------
-- Primary key is tenant_id alone, so gym B already occupies the only key this
-- insert can use. RLS WITH CHECK is evaluated before the index insertion, so
-- 42501 is what a correct policy raises; a 23505 here would mean the with
-- check half is missing.
select results_eq(
  $$ select distinct tenant_id from public.razorpay_accounts $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: razorpay_accounts select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.razorpay_accounts set key_id = 'HIJACKED'
     where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid
     returning tenant_id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: razorpay_accounts update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id)
  values ('b0000000-0000-4000-8000-000000000001', 'rzp_test_hijack',
          'b0000000-0000-4000-8000-0000000000e3', 'b0000000-0000-4000-8000-0000000000e4')
$$, '42501'::char(5), null::text,
  'PAY-005 / RLS tenancy isolation: razorpay_accounts insert carrying gym B tenant_id is refused by with check');

-- --- razorpay_mandates ----------------------------------------------------
select results_eq(
  $$ select distinct tenant_id from public.razorpay_mandates $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'RLS tenancy isolation: razorpay_mandates select as gym A returns gym A rows and no other tenant'
);
with attempt as (
    update public.razorpay_mandates set max_amount_paise = 1
     where id = 'b0000000-0000-4000-8000-00000000000d'::uuid
     returning id
  )
select is((select count(*) from attempt), 0::bigint,
  'RLS tenancy isolation: razorpay_mandates update of gym B row by primary key affects zero rows');
select throws_ok($$
  insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise)
  values ('b0000000-0000-4000-8000-0000000000fb', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 'sub_mmrlsb_2', 500000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: razorpay_mandates insert carrying gym B tenant_id is refused by with check');

-- --- INT-001 and the append-only tier, inside gym A's own tenant ----------
select throws_ok($$
  delete from public.payments where id = 'a0000000-0000-4000-8000-000000000009'::uuid
$$, '42501'::char(5), null::text,
  'INT-001: deleting a payment in the caller own tenant is refused for want of privilege');

with cancelled as (
  update public.memberships set status = 'cancelled'
   where id = 'a0000000-0000-4000-8000-000000000007'::uuid
   returning status
)
select is((select status::text from cancelled), 'cancelled'::text,
  'INT-001: cancelling the membership instead succeeds and the row remains');

select throws_ok($$
  update public.webhook_events set processing_error = 'edited by hand'
   where id = 'a0000000-0000-4000-8000-00000000000b'::uuid
$$, '42501'::char(5), null::text,
  'PAY-009: an authenticated caller updating webhook_events in its own tenant is refused for want of privilege');

-- ADR-049: the refusal that matters is the one inside the caller's OWN tenant.
-- A cross-tenant insert would be refused by the policy even with the grant in
-- place; only this one shows the grant is gone, and it is the grant that stops
-- a gym forging `signature_valid = true` for a webhook it never received.
select throws_ok($$
  insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid)
  values ('a0000000-0000-4000-8000-0000000000fc', 'a0000000-0000-4000-8000-000000000001',
          'evt_mmrlsa_forged', 'payment.captured', '{}'::jsonb, true)
$$, '42501'::char(5), null::text,
  'ADR-049: an authenticated caller inserting a webhook_events row in its own tenant is refused for want of privilege — a gym cannot forge the record of a payment webhook it verified itself');

-- ===========================================================================
-- 61-71. The platform branch (docs/security.md): super_admin sees across all
-- tenants by policy, not by disabling RLS. Scoped to this file's two gyms so
-- a seeded row elsewhere cannot change the verdict.
-- ===========================================================================

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select results_eq(
  $$ select distinct tenant_id from public.plans
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees plans of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.coupons
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees coupons of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.memberships
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees memberships of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.membership_pauses
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees membership_pauses of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.payments
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees payments of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.refunds
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees refunds of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.webhook_events
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees webhook_events of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.invoices
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees invoices of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.document_counters
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees document_counters of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.razorpay_accounts
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees razorpay_accounts of both gyms'
);
select results_eq(
  $$ select distinct tenant_id from public.razorpay_mandates
      where tenant_id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001')
      order by 1 $$,
  $$ values ('a0000000-0000-4000-8000-000000000001'::uuid), ('b0000000-0000-4000-8000-000000000001'::uuid) $$,
  'platform branch: super_admin sees razorpay_mandates of both gyms'
);

-- ===========================================================================
-- 72-104. No JWT claims at all. app.current_tenant_id() is null and
-- app.is_platform() is false, so both permissive policies OR to false: the
-- select must return zero rows and must NOT raise (a raising policy would let
-- a caller tell "nothing here" apart from "wrong tenant"), and the insert must
-- still be refused.
-- ===========================================================================

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role authenticated;

select lives_ok($$ select 1 from public.plans $$,
  'RLS tenancy isolation: plans select with no claims does not raise');
select is_empty($$ select 1 from public.plans $$,
  'RLS tenancy isolation: plans select with no claims returns zero rows');
select throws_ok($$
  insert into public.plans (id, tenant_id, name, duration_days, price_paise)
  values ('b0000000-0000-4000-8000-0000000000f1', 'b0000000-0000-4000-8000-000000000001',
          'Gym B Plan Two', 30, 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: plans insert with no claims is refused');

select lives_ok($$ select 1 from public.coupons $$,
  'RLS tenancy isolation: coupons select with no claims does not raise');
select is_empty($$ select 1 from public.coupons $$,
  'RLS tenancy isolation: coupons select with no claims returns zero rows');
select throws_ok($$
  insert into public.coupons (id, tenant_id, code, percent_bp)
  values ('b0000000-0000-4000-8000-0000000000f2', 'b0000000-0000-4000-8000-000000000001',
          'BCOUPON2', 1000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: coupons insert with no claims is refused');

select lives_ok($$ select 1 from public.memberships $$,
  'RLS tenancy isolation: memberships select with no claims does not raise');
select is_empty($$ select 1 from public.memberships $$,
  'RLS tenancy isolation: memberships select with no claims returns zero rows');
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise)
  values ('b0000000-0000-4000-8000-0000000000f3', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000005', 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: memberships insert with no claims is refused');

select lives_ok($$ select 1 from public.membership_pauses $$,
  'RLS tenancy isolation: membership_pauses select with no claims does not raise');
select is_empty($$ select 1 from public.membership_pauses $$,
  'RLS tenancy isolation: membership_pauses select with no claims returns zero rows');
select throws_ok($$
  insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason)
  values ('b0000000-0000-4000-8000-0000000000f4', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000007', date '2026-10-01', date '2026-10-05', 'Cross tenant freeze')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: membership_pauses insert with no claims is refused');

select lives_ok($$ select 1 from public.payments $$,
  'RLS tenancy isolation: payments select with no claims does not raise');
select is_empty($$ select 1 from public.payments $$,
  'RLS tenancy isolation: payments select with no claims returns zero rows');
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('b0000000-0000-4000-8000-0000000000f5', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 100000, 'cash', 'b0000000-0000-4000-8000-000000000003')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: payments insert with no claims is refused');

select lives_ok($$ select 1 from public.refunds $$,
  'RLS tenancy isolation: refunds select with no claims does not raise');
select is_empty($$ select 1 from public.refunds $$,
  'RLS tenancy isolation: refunds select with no claims returns zero rows');
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason)
  values ('b0000000-0000-4000-8000-0000000000f6', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000009', 'refund', 1000, 'Cross tenant refund')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: refunds insert with no claims is refused');

select lives_ok($$ select 1 from public.webhook_events $$,
  'RLS tenancy isolation: webhook_events select with no claims does not raise');
select is_empty($$ select 1 from public.webhook_events $$,
  'RLS tenancy isolation: webhook_events select with no claims returns zero rows');
select throws_ok($$
  insert into public.webhook_events (id, tenant_id, event_id, event_type, payload, signature_valid)
  values ('b0000000-0000-4000-8000-0000000000f7', 'b0000000-0000-4000-8000-000000000001',
          'evt_mmrlsb_2', 'payment.captured', '{}'::jsonb, true)
$$, '42501'::char(5), null::text,
  'ADR-049: webhook_events insert with no claims is refused for want of privilege — read-only to authenticated whatever the claims say');

select lives_ok($$ select 1 from public.invoices $$,
  'RLS tenancy isolation: invoices select with no claims does not raise');
select is_empty($$ select 1 from public.invoices $$,
  'RLS tenancy isolation: invoices select with no claims returns zero rows');
select throws_ok($$
  insert into public.invoices
    (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise)
  values ('b0000000-0000-4000-8000-0000000000f8', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-0000000000f9', 'B/2026-27/2', '2026-27', 'B Member', 84746, 100000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: invoices insert with no claims is refused');

select lives_ok($$ select 1 from public.document_counters $$,
  'RLS tenancy isolation: document_counters select with no claims does not raise');
select is_empty($$ select 1 from public.document_counters $$,
  'RLS tenancy isolation: document_counters select with no claims returns zero rows');
select throws_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year)
  values ('b0000000-0000-4000-8000-000000000001', 'receipt', '2026-27')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: document_counters insert with no claims is refused');

select lives_ok($$ select 1 from public.razorpay_accounts $$,
  'RLS tenancy isolation: razorpay_accounts select with no claims does not raise');
select is_empty($$ select 1 from public.razorpay_accounts $$,
  'RLS tenancy isolation: razorpay_accounts select with no claims returns zero rows');
select throws_ok($$
  insert into public.razorpay_accounts (tenant_id, key_id, key_secret_vault_id, webhook_secret_vault_id)
  values ('b0000000-0000-4000-8000-000000000001', 'rzp_test_hijack',
          'b0000000-0000-4000-8000-0000000000e3', 'b0000000-0000-4000-8000-0000000000e4')
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: razorpay_accounts insert with no claims is refused');

select lives_ok($$ select 1 from public.razorpay_mandates $$,
  'RLS tenancy isolation: razorpay_mandates select with no claims does not raise');
select is_empty($$ select 1 from public.razorpay_mandates $$,
  'RLS tenancy isolation: razorpay_mandates select with no claims returns zero rows');
select throws_ok($$
  insert into public.razorpay_mandates (id, tenant_id, member_id, provider_subscription_id, max_amount_paise)
  values ('b0000000-0000-4000-8000-0000000000fb', 'b0000000-0000-4000-8000-000000000001',
          'b0000000-0000-4000-8000-000000000004', 'sub_mmrlsb_2', 500000)
$$, '42501'::char(5), null::text,
  'RLS tenancy isolation: razorpay_mandates insert with no claims is refused');

-- ===========================================================================
-- 105-115. Back as the owner, with RLS bypassed: every one of gym B's rows is
-- byte-for-byte what the fixture wrote. A policy that filtered the update
-- away is only half the claim; this is the other half.
-- ===========================================================================

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is((select name from public.plans where id = 'b0000000-0000-4000-8000-000000000005'),
  'Gym B Plan'::text,
  'RLS tenancy isolation: gym B plans row is unchanged after gym A attempted update');
select is((select code from public.coupons where id = 'b0000000-0000-4000-8000-000000000006'),
  'BCOUPON'::text,
  'RLS tenancy isolation: gym B coupons row is unchanged after gym A attempted update');
select is((select status::text from public.memberships where id = 'b0000000-0000-4000-8000-000000000007'),
  'active'::text,
  'RLS tenancy isolation: gym B memberships row is unchanged after gym A attempted update');
select is((select reason from public.membership_pauses where id = 'b0000000-0000-4000-8000-000000000008'),
  'Gym B freeze reason'::text,
  'RLS tenancy isolation: gym B membership_pauses row is unchanged after gym A attempted update');
select is((select amount_paise from public.payments where id = 'b0000000-0000-4000-8000-000000000009'),
  100000::bigint,
  'RLS tenancy isolation: gym B payments row is unchanged after gym A attempted update');
select is((select amount_paise from public.refunds where id = 'b0000000-0000-4000-8000-00000000000a'),
  20000::bigint,
  'RLS tenancy isolation: gym B refunds row is unchanged after gym A attempted update');
select is((select processing_error from public.webhook_events where id = 'b0000000-0000-4000-8000-00000000000b'),
  null::text,
  'RLS tenancy isolation: gym B webhook_events row is unchanged after gym A attempted update');
select is((select total_paise from public.invoices where id = 'b0000000-0000-4000-8000-00000000000c'),
  100000::bigint,
  'RLS tenancy isolation: gym B invoices row is unchanged after gym A attempted update');
select is((select next_number from public.document_counters
            where tenant_id = 'b0000000-0000-4000-8000-000000000001'
              and kind = 'invoice' and financial_year = '2026-27'),
  1::integer,
  'RLS tenancy isolation: gym B document_counters row is unchanged after gym A attempted update');
select is((select key_id from public.razorpay_accounts where tenant_id = 'b0000000-0000-4000-8000-000000000001'),
  'rzp_test_gymb'::text,
  'RLS tenancy isolation: gym B razorpay_accounts row is unchanged after gym A attempted update');
select is((select max_amount_paise from public.razorpay_mandates where id = 'b0000000-0000-4000-8000-00000000000d'),
  500000::bigint,
  'RLS tenancy isolation: gym B razorpay_mandates row is unchanged after gym A attempted update');

-- ===========================================================================
-- 116-123. MNY-002 — the currency column beside every *_paise column carries
-- a format check, and it rejects a malformed code. The structural file
-- already asserts that exactly one currency column exists per money table;
-- this is the half it does not cover. `inr` is the interesting case: right
-- length, wrong case, so a check that only measured length would pass it.
-- Run as the owner: a check constraint is not a policy and does not care who
-- is writing.
-- ===========================================================================

select throws_ok($$
  insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency)
  values ('a0000000-0000-4000-8000-0000000000c1', 'a0000000-0000-4000-8000-000000000001',
          'Gym A Bad Currency Plan', 30, 100000, 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: plans rejects a lower-case currency code');

select throws_ok($$
  insert into public.coupons (id, tenant_id, code, percent_bp, currency)
  values ('a0000000-0000-4000-8000-0000000000c2', 'a0000000-0000-4000-8000-000000000001',
          'ABADCUR', 1000, 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: coupons rejects a lower-case currency code');

select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise, currency)
  values ('a0000000-0000-4000-8000-0000000000c3', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000005', 100000, 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: memberships rejects a lower-case currency code');

select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, currency)
  values ('a0000000-0000-4000-8000-0000000000c4', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000004', 100000, 'cash',
          'a0000000-0000-4000-8000-000000000003', 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: payments rejects a lower-case currency code');

select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, currency)
  values ('a0000000-0000-4000-8000-0000000000c5', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000009', 'refund', 20000, 'Bad currency refund', 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: refunds rejects a lower-case currency code');

select throws_ok($$
  insert into public.invoices
    (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise, currency)
  values ('a0000000-0000-4000-8000-0000000000c6', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000f9', 'A/2026-27/2', '2026-27', 'A Member', 84746, 100000, 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: invoices rejects a lower-case currency code');

select throws_ok($$
  insert into public.razorpay_mandates
    (id, tenant_id, member_id, provider_subscription_id, max_amount_paise, currency)
  values ('a0000000-0000-4000-8000-0000000000c7', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000004', 'sub_mmrlsa_2', 500000, 'inr')
$$, '23514'::char(5), null::text,
  'MNY-002: razorpay_mandates rejects a lower-case currency code');

select throws_ok($$
  insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency)
  values ('a0000000-0000-4000-8000-0000000000c8', 'a0000000-0000-4000-8000-000000000001',
          'Gym A Rupees Plan', 30, 100000, 'Rupees')
$$, '23514'::char(5), null::text,
  'MNY-002: a currency of Rupees is rejected, per the spec scenario');

-- ===========================================================================
-- 124-127. ADR-047 — the two constraints the contract gained after the blind
-- critics. Both are check/index shape, not policy, so they are asserted as the
-- owner like the currency block above.
--
-- The live-membership key is (tenant_id, member_id): a second live membership
-- inside one gym is still refused, and gym B naming gym A's member id — which
-- the schema permits, since no foreign key re-checks the tenant (OPEN-008) —
-- no longer takes the slot gym A needs for a member gym B cannot even see.
--
-- Its own member and its own live row, established here: the fixture member's
-- membership has been through several status transitions by this point in the
-- file, and `cancelled` sits outside the index predicate, so an assertion that
-- leaned on it would be measuring file order rather than the key.
-- ===========================================================================

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-0000000000e0', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Live Key Member', '+919000000003');

insert into public.memberships
  (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('a0000000-0000-4000-8000-0000000000e1', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-0000000000e0', 'a0000000-0000-4000-8000-000000000005',
   'active', date '2026-10-01', date '2026-10-31', 100000);

select throws_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000e2', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000e0', 'a0000000-0000-4000-8000-000000000005',
          'active', date '2026-11-01', date '2026-11-30', 100000)
$$, '23505'::char(5), null::text,
  'spec "A second active membership" (ADR-047): a second live membership for the same member in the same gym is rejected');

-- ADR-052, and this assertion used to say the opposite. The premise it rested
-- on — that gym B can name gym A's member id at all — is gone: the key is now
-- `(tenant_id, member_id) references members (tenant_id, id)`, so the write is
-- refused with 23503 rather than accepted. ADR-047's tenant-scoping of the
-- live-membership index is unchanged and still asserted, by shape, in
-- 05_membership_money_structure.sql and 04_contract_meta.sql; what changed is
-- that the row it bounded can no longer be written. Run as the owner, so RLS
-- is not in the way and the foreign key is the only thing that can refuse.
select throws_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('b0000000-0000-4000-8000-0000000000e2', 'b0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000e0', 'b0000000-0000-4000-8000-000000000005',
          'active', date '2026-11-01', date '2026-11-30', 100000)
$$, '23503'::char(5), null::text,
  'ADR-052: a membership written into gym B''s tenant naming gym A''s member is rejected with 23503 — the referential-integrity probe runs with row security off, so the composite key is what sees the other tenant''s member and refuses');

-- The live-membership predicate is `status in ('active','frozen')`, and until
-- now nothing in the suite read `frozen` at all: the structure test only asks
-- that indpred is not null, and the collision above is active-against-active.
-- An index declared `where status = 'active'` alone would pass both, and would
-- let a member hold a frozen membership and an active one at the same time.
-- So: the two statuses inside the predicate collide with each other, and the
-- three outside it (pending, expired, cancelled) do not block a new live row.

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-0000000000b1', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Frozen Member',    '+919000000011'),
  ('a0000000-0000-4000-8000-0000000000b2', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Expired Member',   '+919000000012'),
  ('a0000000-0000-4000-8000-0000000000b3', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Cancelled Member', '+919000000013'),
  ('a0000000-0000-4000-8000-0000000000b4', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'A Pending Member',   '+919000000014');

insert into public.memberships
  (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('a0000000-0000-4000-8000-0000000000b5', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-0000000000b1', 'a0000000-0000-4000-8000-000000000005',
   'frozen',    date '2026-10-01', date '2026-10-31', 100000),
  ('a0000000-0000-4000-8000-0000000000b6', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-0000000000b2', 'a0000000-0000-4000-8000-000000000005',
   'expired',   date '2026-08-01', date '2026-08-31', 100000),
  ('a0000000-0000-4000-8000-0000000000b7', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-0000000000b3', 'a0000000-0000-4000-8000-000000000005',
   'cancelled', date '2026-08-01', date '2026-08-31', 100000),
  ('a0000000-0000-4000-8000-0000000000b8', 'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-0000000000b4', 'a0000000-0000-4000-8000-000000000005',
   'pending',   date '2026-12-01', date '2026-12-31', 100000);

select throws_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000d7', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000e0', 'a0000000-0000-4000-8000-000000000005',
          'frozen', date '2026-12-01', date '2026-12-31', 100000)
$$, '23505'::char(5), null::text,
  'spec "A member has at most one live membership": a FROZEN membership for a member who already holds an active one is rejected — frozen is inside the index predicate, which an index on active alone would not catch');

select throws_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000d8', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000b1', 'a0000000-0000-4000-8000-000000000005',
          'active', date '2026-12-01', date '2026-12-31', 100000)
$$, '23505'::char(5), null::text,
  'spec "A member has at most one live membership": an ACTIVE membership for a member who already holds a frozen one is rejected — the collision is symmetric across the two live statuses');

select lives_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000d9', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000b2', 'a0000000-0000-4000-8000-000000000005',
          'active', date '2026-12-01', date '2026-12-31', 100000)
$$,
  'spec "A member has at most one live membership": an expired membership sits outside the predicate, so a renewal for that member is accepted');

select lives_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000da', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000b3', 'a0000000-0000-4000-8000-000000000005',
          'active', date '2026-12-01', date '2026-12-31', 100000)
$$,
  'spec "A member has at most one live membership": a cancelled membership sits outside the predicate, so a fresh one for that member is accepted');

select lives_ok($$
  insert into public.memberships
    (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('a0000000-0000-4000-8000-0000000000db', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-0000000000b4', 'a0000000-0000-4000-8000-000000000005',
          'active', date '2026-12-01', date '2026-12-31', 100000)
$$,
  'spec "A member has at most one live membership": a pending membership sits outside the predicate, so the activated row PAY-008 writes beside it is accepted');

-- payments: `provider` is nullable and sits inside the unique key on
-- (tenant_id, provider, provider_payment_id), and a unique index treats rows
-- with a null key column as distinct — so a provider reference without a
-- provider names a duplicate the key would never catch.

select throws_ok($$
  insert into public.payments
    (id, tenant_id, member_id, amount_paise, method, provider_order_id, provider_payment_id)
  values ('a0000000-0000-4000-8000-0000000000d2', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000004', 100000, 'razorpay',
          'order_mmrlsa_1', 'pay_mmrlsa_1')
$$, '23514'::char(5), null::text,
  'PAY-009 (ADR-047): a payment carrying a provider_payment_id with no provider is rejected');

select lives_ok($$
  insert into public.payments
    (id, tenant_id, member_id, amount_paise, method, provider, provider_order_id, provider_payment_id)
  values ('a0000000-0000-4000-8000-0000000000d3', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000004', 100000, 'razorpay', 'razorpay',
          'order_mmrlsa_2', 'pay_mmrlsa_2')
$$,
  'PAY-009 (ADR-047): the same payment with provider set is accepted — the check bounds the null, it does not forbid the reference');

-- ADR-049 — invoices.payment_id is unique PER GYM, `(tenant_id, payment_id)`,
-- the fifth instance of the ADR-047 class. A global unique on this column lets
-- gym A name gym B's payment id in its own invoice and take, permanently, the
-- slot gym B needs: a 23505 against a row gym B cannot see, update or delete.
-- Both halves are asserted, because only the pair distinguishes the two shapes.

select throws_ok($$
  insert into public.invoices
    (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise)
  values ('a0000000-0000-4000-8000-0000000000e5', 'a0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000009', 'A/2026-27/9', '2026-27', 'A Member', 84746, 100000)
$$, '23505'::char(5), null::text,
  'ADR-049: invoicing the same payment twice inside one gym is rejected — the invoice_number is fresh, so (tenant_id, payment_id) is the only key that can raise');

-- ADR-052 supersedes the second half of that pair, and it used to assert the
-- opposite. `invoices.payment_id` is now `(tenant_id, payment_id) references
-- payments (tenant_id, id)`, so gym B naming gym A's payment id is refused at
-- the key rather than accepted-but-harmless. ADR-049's tenant-scoped unique is
-- untouched and is what the assertion above still proves; this is the cause
-- ADR-052 closed underneath it.
select throws_ok($$
  insert into public.invoices
    (id, tenant_id, payment_id, invoice_number, financial_year, buyer_name, taxable_paise, total_paise)
  values ('b0000000-0000-4000-8000-0000000000e5', 'b0000000-0000-4000-8000-000000000001',
          'a0000000-0000-4000-8000-000000000009', 'B/2026-27/9', '2026-27', 'B Member', 84746, 100000)
$$, '23503'::char(5), null::text,
  'ADR-052: an invoice written into gym B''s tenant naming gym A''s payment is rejected with 23503 — the invoice_number and the (tenant_id, payment_id) key are both free, so the composite foreign key is the only thing that can raise');

select * from finish();

rollback;
