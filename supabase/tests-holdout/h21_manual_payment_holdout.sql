-- h21_manual_payment_holdout — HOLDOUT pgTAP suite for Phase 5's manual
-- payment path and the receipt/renewal mechanics it shares with the online
-- path.
--
-- Written blind from
--   openspec/changes/phase-5-money/specs/manual-payment/spec.md
--   openspec/changes/phase-5-money/specs/receipts-and-renewal/spec.md
--   docs/domain-rules.md PAY-001..PAY-011, MNY-001..MNY-004
--   docs/decisions.md ADR-064, ADR-066..ADR-081
-- and from the live catalogue (grants, policies, constraints, triggers) as
-- of migration 20260909190000. The author of this file has not read, and
-- will not read: supabase/tests/21_manual_payment.sql (the visible suite,
-- written in parallel), any migration dated 20260910000000 or later, or
-- pg_get_functiondef/prosrc for anything Phase 5 adds.
--
-- WHAT THIS FILE IS FOR. The visible suite transcribes the two specs
-- requirement by requirement; duplicating that buys nothing. This file
-- spends its assertions on what a careful transcription tends to miss,
-- guided by this project's own defect history:
--
--   * THE SECOND STATEMENT (ADR-070). Every refusal is tested as an INSERT
--     and, separately, as an UPDATE that tries to reach the same illegal
--     state a second way — recorded_by_staff_id renamed after the fact,
--     a manual payment given a provider identity after the fact, a payment
--     that starts 'created' and is only later flipped to 'paid'. The
--     no-show scan's own trigger history (ADR-070/072) is a rule enforced
--     on INSERT that a later UPDATE walked straight past; this file assumes
--     the same shape is possible here until proven otherwise.
--   * EVERY NULLABLE COLUMN A RULE READS (ADR-071): recorded_by_staff_id,
--     receipt_number, idempotency_key, paid_at, membership_id. Each is
--     exercised at null, not just at a populated value.
--   * CONCURRENCY ON THE COUNTER. One transaction cannot open a second
--     connection (ADR-030 wraps the whole file in one), so a real race
--     cannot be staged. What CAN be staged, following h18's own precedent:
--     pre-set document_counters.next_number to the value a "lost" racer's
--     commit would have left behind, then allocate through the real path
--     and check the counter advances from THAT value by exactly one, not
--     from a stale re-read and not by more than one.
--   * MONEY AS ARITHMETIC. A refund exactly equal to the payment succeeds
--     (the rule says "exceed", not "reach"); one paise more, on a single
--     refund or as the last of several summing exactly to the total, is
--     refused. A fractional amount is proven refused, not rounded, against
--     the actual text-protocol path a real client uses — not against a
--     bare numeric literal, which Postgres itself rounds on assignment
--     before any trigger could ever see the fraction (verified empirically
--     against this project's Cloud instance; noted in the report).
--   * THE GYM'S DAY. Two gyms, Etc/GMT-12 and Etc/GMT+12 — 24 hours apart
--     and deterministic at every instant — each get an early-renewal and a
--     late-renewal fixture, built from now() at time zone <tz> rather than
--     any literal date, so the assertion is never stale (h18's own
--     ADR-039 lesson, applied twice).
--   * WHO MAY WRITE. payments' write gate is is_front_office() (front desk
--     included); refunds' write gate is is_gym_admin() — a strictly
--     narrower set that EXCLUDES front desk. That asymmetry is exactly the
--     kind of thing a same-author suite tends to assume rather than check.
--     Both gates, and the composite-FK cross-tenant guard, are already live
--     from Phase 2 (ADR-052) and are asserted here as already-green
--     evidence, not as something Phase 5 must newly build.
--   * OVER-ENFORCEMENT. Every refusal is paired with a positive case read
--     back from the table, not inferred from the refusal succeeding.
--
-- ADR-069: every assertion is a top-level `select` (or `insert into
-- _tap_lines(line) select ...` under the sweep/tapcount scripts) consumed by
-- pgTAP directly — no bare select of a value, no work done inside a `do`
-- block that could hide a result from the TAP stream.
--
-- ADR-050: nothing here counts or lists a whole table. Every count is
-- scoped to this file's own fixtures, all under uuid prefix
-- '210000ff-0021-...'.
--
-- ADR-030: one transaction, ending in ROLLBACK.
--
-- ROUND-TWENTY RECONCILIATION, independently audited against the committed
-- membership-creation contract at 826021d, without reading implementation or
-- visible tests. Every membership fixture below starts fully dated with zero
-- granted periods. Its first completed payment therefore SETS one sold period
-- from the later of its start and gym-local today; its typed end contributes no
-- bought time. Ten expected dates change for that reason alone. Assertions of
-- no grant before payment, no duplicate grant, no reversal on refund and gym-
-- local arithmetic are retained, as are all 68 assertions and the fixtures.

begin;

set local role postgres;

select plan(68);

-- ---------------------------------------------------------------------------
-- 0. Fixtures: four gyms.
--   A — Asia/Kolkata (default). The main battery: staff attribution, the
--       manual/provider rule, receipt allocation and its concurrency
--       staging, extension, idempotency, refunds.
--   B — a second gym, for counter/idempotency isolation and the
--       cross-tenant composite-FK probe.
--   P — Etc/GMT-12 (UTC+12). Timezone half of the extension pair.
--   M — Etc/GMT+12 (UTC-12), 24h from P at every instant. The other half.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('210000ff-0021-4000-8000-100000000001'::uuid, 'Holdout PAY Gym A', 'H21AGA');

insert into public.organizations (id, name, gym_code) values
  ('210000ff-0021-4000-8000-100000000002'::uuid, 'Holdout PAY Gym B', 'H21AGB');

insert into public.organizations (id, name, gym_code, timezone) values
  ('210000ff-0021-4000-8000-100000000003'::uuid, 'Holdout PAY Gym P (GMT-12)', 'H21AGP', 'Etc/GMT-12');

insert into public.organizations (id, name, gym_code, timezone) values
  ('210000ff-0021-4000-8000-100000000004'::uuid, 'Holdout PAY Gym M (GMT+12)', 'H21AGM', 'Etc/GMT+12');

insert into public.branches (id, tenant_id, name, is_default) values
  ('210000ff-0021-4000-8000-200000000001'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, 'H21 A Main', true),
  ('210000ff-0021-4000-8000-200000000002'::uuid, '210000ff-0021-4000-8000-100000000002'::uuid, 'H21 B Main', true),
  ('210000ff-0021-4000-8000-200000000003'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, 'H21 P Main', true),
  ('210000ff-0021-4000-8000-200000000004'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, 'H21 M Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('210000ff-0021-4000-8000-300000000001'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'front_desk', 'H21 A Desk 1'),
  ('210000ff-0021-4000-8000-300000000002'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'front_desk', 'H21 A Desk 2 (colleague)'),
  ('210000ff-0021-4000-8000-300000000004'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'gym_manager', 'H21 A Manager'),
  ('210000ff-0021-4000-8000-300000000005'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'trainer', 'H21 A Trainer'),
  ('210000ff-0021-4000-8000-300000000011'::uuid, '210000ff-0021-4000-8000-100000000002'::uuid, '210000ff-0021-4000-8000-200000000002'::uuid, 'front_desk', 'H21 B Desk'),
  ('210000ff-0021-4000-8000-300000000031'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, '210000ff-0021-4000-8000-200000000003'::uuid, 'front_desk', 'H21 P Desk'),
  ('210000ff-0021-4000-8000-300000000041'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, '210000ff-0021-4000-8000-200000000004'::uuid, 'front_desk', 'H21 M Desk');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('210000ff-0021-4000-8000-400000000001'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, 'H21 Plan A', 30, 100000),
  ('210000ff-0021-4000-8000-400000000002'::uuid, '210000ff-0021-4000-8000-100000000002'::uuid, 'H21 Plan B', 30, 100000),
  ('210000ff-0021-4000-8000-400000000003'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, 'H21 Plan P', 30, 100000),
  ('210000ff-0021-4000-8000-400000000004'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, 'H21 Plan M', 30, 100000);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('210000ff-0021-4000-8000-500000000001'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Staff Attribution', '+919210000001'),
  ('210000ff-0021-4000-8000-500000000003'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Provider Mismatch', '+919210000003'),
  ('210000ff-0021-4000-8000-500000000004'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Receipt One',       '+919210000004'),
  ('210000ff-0021-4000-8000-500000000005'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Receipt Two',       '+919210000005'),
  ('210000ff-0021-4000-8000-500000000006'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Receipt Three',     '+919210000006'),
  ('210000ff-0021-4000-8000-500000000007'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Dup Receipt',       '+919210000007'),
  ('210000ff-0021-4000-8000-500000000008'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Extension Basic',   '+919210000008'),
  ('210000ff-0021-4000-8000-500000000009'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Insert Then Update','+919210000009'),
  ('210000ff-0021-4000-8000-50000000000a'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Null PaidAt',       '+919210000010'),
  ('210000ff-0021-4000-8000-50000000000b'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 No Membership',     '+919210000011'),
  ('210000ff-0021-4000-8000-50000000000c'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Idempotent',        '+919210000012'),
  ('210000ff-0021-4000-8000-50000000000d'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Refund Full',       '+919210000013'),
  ('210000ff-0021-4000-8000-50000000000e'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 Refund Partials',   '+919210000014'),
  ('210000ff-0021-4000-8000-50000000000f'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-200000000001'::uuid, 'H21 RLS Probe',         '+919210000015');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('210000ff-0021-4000-8000-500000000101'::uuid, '210000ff-0021-4000-8000-100000000002'::uuid, '210000ff-0021-4000-8000-200000000002'::uuid, 'H21 B Receipt', '+919210000101');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('210000ff-0021-4000-8000-500000000201'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, '210000ff-0021-4000-8000-200000000003'::uuid, 'H21 P Early', '+919210000201'),
  ('210000ff-0021-4000-8000-500000000202'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, '210000ff-0021-4000-8000-200000000003'::uuid, 'H21 P Late',  '+919210000202');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('210000ff-0021-4000-8000-500000000211'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, '210000ff-0021-4000-8000-200000000004'::uuid, 'H21 M Early', '+919210000211'),
  ('210000ff-0021-4000-8000-500000000212'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, '210000ff-0021-4000-8000-200000000004'::uuid, 'H21 M Late',  '+919210000212');

-- Memberships. starts_on is a fixed past date; the first grant now replaces it
-- with gym-local today. All counts start at their zero default, so the typed
-- ends below are unpaid spans, not evidence of a previously bought period.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('210000ff-0021-4000-8000-600000000001'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-500000000008'::uuid, '210000ff-0021-4000-8000-400000000001'::uuid, 'active', date '2020-01-01', (now() at time zone 'Asia/Kolkata')::date + 100, 100000),
  ('210000ff-0021-4000-8000-600000000002'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-500000000009'::uuid, '210000ff-0021-4000-8000-400000000001'::uuid, 'active', date '2020-01-01', (now() at time zone 'Asia/Kolkata')::date + 60,  100000),
  ('210000ff-0021-4000-8000-600000000003'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-50000000000a'::uuid, '210000ff-0021-4000-8000-400000000001'::uuid, 'active', date '2020-01-01', (now() at time zone 'Asia/Kolkata')::date + 40,  100000),
  ('210000ff-0021-4000-8000-600000000004'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-50000000000c'::uuid, '210000ff-0021-4000-8000-400000000001'::uuid, 'active', date '2020-01-01', (now() at time zone 'Asia/Kolkata')::date + 45,  100000),
  ('210000ff-0021-4000-8000-600000000005'::uuid, '210000ff-0021-4000-8000-100000000001'::uuid, '210000ff-0021-4000-8000-50000000000d'::uuid, '210000ff-0021-4000-8000-400000000001'::uuid, 'active', date '2020-01-01', (now() at time zone 'Asia/Kolkata')::date + 20,  100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('210000ff-0021-4000-8000-600000000201'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, '210000ff-0021-4000-8000-500000000201'::uuid, '210000ff-0021-4000-8000-400000000003'::uuid, 'active', date '2020-01-01', (now() at time zone 'Etc/GMT-12')::date + 3,   100000),
  ('210000ff-0021-4000-8000-600000000202'::uuid, '210000ff-0021-4000-8000-100000000003'::uuid, '210000ff-0021-4000-8000-500000000202'::uuid, '210000ff-0021-4000-8000-400000000003'::uuid, 'active', date '2020-01-01', (now() at time zone 'Etc/GMT-12')::date - 21,  100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('210000ff-0021-4000-8000-600000000211'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, '210000ff-0021-4000-8000-500000000211'::uuid, '210000ff-0021-4000-8000-400000000004'::uuid, 'active', date '2020-01-01', (now() at time zone 'Etc/GMT+12')::date + 3,   100000),
  ('210000ff-0021-4000-8000-600000000212'::uuid, '210000ff-0021-4000-8000-100000000004'::uuid, '210000ff-0021-4000-8000-500000000212'::uuid, '210000ff-0021-4000-8000-400000000004'::uuid, 'active', date '2020-01-01', (now() at time zone 'Etc/GMT+12')::date - 21,  100000);

-- ---------------------------------------------------------------------------
-- 1. Money is integer paise, proven against the actual text-protocol path.
--
--    A bare numeric literal (1050.6) assigned to a bigint column is ROUNDED
--    by Postgres's own assignment cast before any trigger could ever see the
--    fraction — verified empirically against this project's Cloud instance:
--    `create temp table t(amount_paise bigint); insert into t values
--    (1050.6);` leaves 1051. That path cannot be made to "refuse" at the
--    database layer; the column type has already erased the input by the
--    time a check or trigger runs. The path a real client actually uses —
--    PostgREST binding a value to a bigint column — sends it in TEXT form,
--    and int8's own input function has no notion of a decimal point at
--    all: it raises 22P02, not a rounded value. That is the path this
--    assertion exercises, because it is the one an actual desk payment
--    takes.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.payments (tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000001', '1050.60', 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  '22P02', null,
  'MNY-001: a fractional amount, submitted the way a real text-protocol client submits one, is refused rather than silently rounded into a whole number of paise');

-- ---------------------------------------------------------------------------
-- 2. Staff attribution (recorded_by_staff_id) — the fourth appearance of
--    "the acting staff member, never the caller's word for it", and here
--    load-bearing since a cash payment has no provider to check it against.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '210000ff-0021-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000001', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000001', 50000, 'cash', 'created', '210000ff-0021-4000-8000-300000000002')$$,
  null, null,
  'naming a colleague as recorded_by_staff_id is refused, whoever is actually holding the session');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- A session with tenant + role but NO staff_id claim at all. It is refused
-- even though it names an otherwise-real, otherwise-valid staff member of
-- the gym — the point is that THIS session has no verified staff identity to
-- attribute anything to, not merely that the column may not be left blank
-- (payments_offline_has_staff_chk already forbids a blank one for an
-- unrelated reason, which would make a null-only test pass for the wrong
-- cause).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000002', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000001', 50000, 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  null, null,
  'a session carrying no staff_id claim at all is refused even when it names a real staff member of the gym — there is no verified identity to attribute the row to');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- Recording a payment: attributed to the acting staff member. Left null,
-- it is filled from the session, not rejected.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '210000ff-0021-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000003', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000001', 50000, 'cash', 'created', null)$$,
  'a cash payment recorded with recorded_by_staff_id left null is attributed to the session, not refused');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000004', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000001', 50000, 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  'a cash payment naming the session''s own staff member succeeds — the baseline for the update probe below');

-- The second-statement version: the same session, still itself, tries to
-- rename the actor of its own row after the fact.
select throws_ok(
  $$update public.payments set recorded_by_staff_id = '210000ff-0021-4000-8000-300000000002' where id = '210000ff-0021-4000-8000-700000000004'$$,
  null, null,
  'ADR-070: renaming recorded_by_staff_id to a colleague by UPDATE, after a correctly-attributed INSERT, is refused just as the INSERT would have been');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select recorded_by_staff_id from public.payments where id = '210000ff-0021-4000-8000-700000000003'::uuid),
  '210000ff-0021-4000-8000-300000000001'::uuid,
  'and reading the auto-filled row back shows it landed on the session''s own staff member, not null and not anybody else');

-- ---------------------------------------------------------------------------
-- 3. A manual payment cannot claim a provider, and the two directions of
--    that rule are separate refusals: desk method + provider identity, and
--    provider method through the desk. Mechanism (check, trigger, or an
--    RLS with-check clause naming the role) is deliberately not asserted —
--    only that the row is refused and that a plainly clean row is not.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '210000ff-0021-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, provider, provider_payment_id, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000005', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000003', 50000, 'cash', 'created', 'razorpay', 'pay_h21_fake_1', '210000ff-0021-4000-8000-300000000001')$$,
  null, null,
  'a desk-method payment carrying a provider payment id is refused — it would launder an unverified cash payment as apparently provider-verified');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, provider, provider_order_id, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000006', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000003', 50000, 'razorpay', 'created', 'razorpay', 'order_h21_fake_1', '210000ff-0021-4000-8000-300000000001')$$,
  null, null,
  'a razorpay-method payment recorded through the manual (authenticated) path is refused — online state is the provider''s to report, never a desk session''s');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000007', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000003', 50000, 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  'a plain cash payment with no provider fields at all is unaffected by the rule above — the baseline for the update probe below');

select throws_ok(
  $$update public.payments set provider = 'razorpay', provider_payment_id = 'pay_h21_fake_2' where id = '210000ff-0021-4000-8000-700000000007'$$,
  null, null,
  'ADR-070: the same rule, reached by UPDATE instead of INSERT — a clean cash row cannot be given a provider identity after the fact either');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 4. Receipt numbers: atomic allocation, staged concurrency, and the two
--    isolations (per gym, per document kind/year) that make the counter
--    safe to share.
-- ---------------------------------------------------------------------------

-- payments_paid_has_reference_chk (Phase 1) already demands a receipt
-- number OR a provider reference on a 'paid' row. A manual payment has
-- neither supplied by the caller, so this insert succeeding at all is
-- itself proof that something allocated one.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000008', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000004', 50000, 'cash', 'paid', now(), '210000ff-0021-4000-8000-300000000001')$$,
  'a manual payment recorded straight to paid, with no receipt_number supplied, is not refused for want of one — something allocates it');

select ok(
  (select receipt_number is not null from public.payments where id = '210000ff-0021-4000-8000-700000000008'::uuid),
  'and the allocated receipt_number is readable back on the row, not merely accepted as null');

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'receipt'
     order by financial_year desc limit 1),
  2,
  'the counter for gym A''s receipt kind now reads 2 — it started at the column default of 1 and advanced by exactly one');

-- Stage the race h18 could not stage with two connections: pre-set the
-- counter to the value a "lost" concurrent allocator's commit would have
-- left behind, then allocate through the real path again.
update public.document_counters set next_number = 50
  where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'receipt';

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000009', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000005', 50000, 'cash', 'paid', now(), '210000ff-0021-4000-8000-300000000001')$$,
  'a second allocation, against a counter pre-set to simulate a race a concurrent allocator already won, still succeeds');

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'receipt'
     order by financial_year desc limit 1),
  51,
  'the counter advanced from the pre-set 50 to 51, not from a stale re-read to 3 — the allocation reads the row it is about to update, not a memoised earlier value');

select isnt(
  (select receipt_number from public.payments where id = '210000ff-0021-4000-8000-700000000008'::uuid),
  (select receipt_number from public.payments where id = '210000ff-0021-4000-8000-700000000009'::uuid),
  'the two allocated receipt numbers differ from each other');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-70000000000a', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000006', 50000, 'cash', 'paid', now(), '210000ff-0021-4000-8000-300000000001')$$,
  'a third, immediately consecutive allocation also succeeds');

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'receipt'
     order by financial_year desc limit 1),
  52,
  'and the counter advances again by exactly one, from 51 to 52 — the sequential behaviour repeats, not a one-off');

-- Kind and financial-year isolation: an unrelated counter row for the same
-- gym, a different kind and a deliberately stale year, must be untouched by
-- every receipt allocation above.
insert into public.document_counters (tenant_id, kind, financial_year, next_number) values
  ('210000ff-0021-4000-8000-100000000001'::uuid, 'invoice', '2020-21', 500);

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'invoice' and financial_year = '2020-21'),
  500,
  'an unrelated invoice counter, for a different kind and a different year, is untouched by three receipt allocations in the same gym');

-- A refunded payment's receipt number is never reissued — already true
-- today via the Phase 1 partial unique index on (tenant_id, receipt_number)
-- where not null, which nothing in this file's fixtures relaxes on refund.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-70000000000b', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000007', 30000, 'cash', 'paid', now(), 'H21-DUP-1', '210000ff-0021-4000-8000-300000000001')$$,
  'a payment recorded with an explicit receipt number succeeds');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000007', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-70000000000b', 'refund', 30000, 'h21 full refund ahead of the reuse attempt', '210000ff-0021-4000-8000-300000000004')$$,
  'and refunding it in full succeeds');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-70000000000c', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000007', 30000, 'cash', 'paid', now(), 'H21-DUP-1', '210000ff-0021-4000-8000-300000000001')$$,
  '23505', null,
  'the same receipt number, on a different payment, is refused even though the original payment it belonged to was refunded — a refund does not free the number');

-- Two gyms: neither's counter is advanced by the other's activity.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000101', '210000ff-0021-4000-8000-100000000002', '210000ff-0021-4000-8000-500000000101', 50000, 'cash', 'paid', now(), '210000ff-0021-4000-8000-300000000011')$$,
  'gym B''s first receipt allocation succeeds independently of gym A''s activity above');

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000002' and kind = 'receipt'
     order by financial_year desc limit 1),
  2,
  'gym B''s own counter reads 2 — the default 1, advanced once — regardless of gym A''s counter having reached 52');

select is(
  (select next_number from public.document_counters
     where tenant_id = '210000ff-0021-4000-8000-100000000001' and kind = 'receipt'
     order by financial_year desc limit 1),
  52,
  'and gym A''s counter is still 52, unmoved by gym B''s allocation');

-- ---------------------------------------------------------------------------
-- 5. Extension: the basic case, the insert-then-update case (ADR-070's
--    shape applied to the extension rule itself), a null paid_at, and a
--    null membership_id.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000201', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000008', '210000ff-0021-4000-8000-600000000001', 100000, 'cash', 'paid', now(), 'H21-EXT-1', '210000ff-0021-4000-8000-300000000001')$$,
  'a paid cash payment against an active membership is recorded');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000001'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'the first grant sets one sold 30-day period from gym-local today; the 100 typed future days were never bought');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000202', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000009', '210000ff-0021-4000-8000-600000000002', 100000, 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  'a payment against the same membership is first recorded as merely created, not paid');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000002'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 60),
  'PAY-008: an intention to pay is not a payment — nothing was extended while the payment sat at created');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now(), receipt_number = 'H21-UPD-1' where id = '210000ff-0021-4000-8000-700000000202'$$,
  'the same row is then updated to paid, as a real webhook or a corrected desk entry would');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000002'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'ADR-070''s shape: the first grant fires on the UPDATE that flips status to paid, setting one sold period from today; an insert-only rule would leave the unpaid typed end unchanged');

-- paid_at left null: the rule must key off status, not off a proxy column.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000203', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000a', '210000ff-0021-4000-8000-600000000003', 100000, 'cash', 'paid', null, 'H21-NULLPAID-1', '210000ff-0021-4000-8000-300000000001')$$,
  'ADR-071: a paid payment with paid_at left null is still recorded — the column is nullable and nothing requires it');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000003'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'and the first grant sets exactly one period as it would with paid_at populated — eligibility still follows paid status');

-- membership_id left null: a gym may take money for something else.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000204', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000b', null, 20000, 'cash', 'paid', now(), 'H21-NOMEM-1', '210000ff-0021-4000-8000-300000000001')$$,
  'ADR-071: a paid payment naming no membership at all is recorded without error — a gym may take money for something a membership row does not represent');

-- ---------------------------------------------------------------------------
-- 6. Idempotency: two distinct defect shapes. A duplicate INSERT sharing an
--    idempotency_key (blocked by the Phase 1 partial unique index already);
--    and a genuine REPLAY — the identical row re-affirmed as paid a second
--    time by UPDATE — which nothing in this schema blocks structurally and
--    which is the shape a naive `after update when (new.status = 'paid')`
--    trigger, with no OLD.status guard, would double-extend on.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, idempotency_key, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000205', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000c', '210000ff-0021-4000-8000-600000000004', 100000, 'cash', 'paid', now(), 'H21-IDEM-1', 'h21-idem-key-1', '210000ff-0021-4000-8000-300000000001')$$,
  'a paid payment carrying an idempotency_key is recorded and extends its membership');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000004'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'the first genuine recording sets one sold period from today; the typed 45-day remainder is not a prior grant');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, idempotency_key, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000206', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000c', '210000ff-0021-4000-8000-600000000004', 100000, 'cash', 'paid', now(), 'H21-IDEM-2', 'h21-idem-key-1', '210000ff-0021-4000-8000-300000000001')$$,
  '23505', null,
  'the front desk pressing the button twice, as a second INSERT carrying the same idempotency_key: refused by the tenant-scoped partial unique index that already exists');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000004'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'the membership still carries exactly its first granted period — the refused duplicate INSERT left no trace');

select lives_ok(
  $$update public.payments set paid_at = now() where id = '210000ff-0021-4000-8000-700000000205' and status = 'paid'$$,
  'a genuine replay: the SAME already-paid row is re-affirmed as paid a second time by UPDATE, as a retried webhook delivery or a re-submitted confirmation would do — nothing at the schema level blocks this update');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000004'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'and the first grant is STILL the only grant — an UPDATE that re-affirms an already-paid row must not extend a second time');

-- ---------------------------------------------------------------------------
-- 7. Refunds: a new row, never a mutation; the boundary at exactly the
--    payment's amount; and several partials summing exactly to it.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000207', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000d', '210000ff-0021-4000-8000-600000000005', 100000, 'cash', 'paid', now(), 'H21-REF-BASE', '210000ff-0021-4000-8000-300000000001')$$,
  'the payment that section 7''s refunds will be tested against is recorded and paid');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000005'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'and its first grant sets one sold period from today, establishing the dates the refund must preserve');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000001', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000207', 'refund', 100000, 'h21 full refund, exactly the payment amount', '210000ff-0021-4000-8000-300000000004')$$,
  'a refund for exactly the full amount of the payment succeeds — the rule refuses what would EXCEED the amount, and equalling it is not exceeding it');

select is(
  (select amount_paise from public.payments where id = '210000ff-0021-4000-8000-700000000207'::uuid),
  100000::bigint,
  'PAY-010: the original payment''s own amount_paise is unchanged by the refund — the refund is a new row, not a mutation');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000005'::uuid),
  ((now() at time zone 'Asia/Kolkata')::date + 30),
  'and the first grant is NOT silently reversed by the refund — the corrected first-grant baseline is unchanged across money returning');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000002', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000207', 'refund', 1, 'h21 one paise more than what remains', '210000ff-0021-4000-8000-300000000004')$$,
  null, null,
  'a further refund of even one paise, against a payment already refunded in full, is refused — the cumulative total would exceed the amount');

-- A second payment, refunded in three partials that sum exactly to the
-- amount, then one paise more.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000208', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000e', 100000, 'cash', 'paid', now(), 'H21-REF-PART', '210000ff-0021-4000-8000-300000000001')$$,
  'a second payment, for the partial-refund battery, is recorded and paid');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000003', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000208', 'refund', 40000, 'h21 partial 1 of 3', '210000ff-0021-4000-8000-300000000004')$$,
  'the first of three partial refunds (40000) succeeds');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000004', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000208', 'refund', 40000, 'h21 partial 2 of 3', '210000ff-0021-4000-8000-300000000004')$$,
  'the second (40000, cumulative 80000) succeeds');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000005', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000208', 'refund', 20000, 'h21 partial 3 of 3, exactly closes the amount', '210000ff-0021-4000-8000-300000000004')$$,
  'the third (20000, cumulative exactly 100000) succeeds — several partials summing exactly to the amount is not exceeding it');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000006', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000208', 'refund', 1, 'h21 one paise past three exact partials', '210000ff-0021-4000-8000-300000000004')$$,
  null, null,
  'a fourth refund of one more paise, after three partials already summed exactly to the amount, is refused');

-- ---------------------------------------------------------------------------
-- 8. The gym's day: Etc/GMT-12 and Etc/GMT+12, 24 hours apart and
--    deterministic at every instant, so at least one (generally both) of
--    the two pairs below discriminates a naive UTC-cast or naive
--    session-timezone implementation at whatever real instant this file
--    happens to run.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000401', '210000ff-0021-4000-8000-100000000003', '210000ff-0021-4000-8000-500000000201', '210000ff-0021-4000-8000-600000000201', 100000, 'cash', 'paid', now(), 'H21-GP-EARLY', '210000ff-0021-4000-8000-300000000031')$$,
  'gym P (Etc/GMT-12): a payment renewing 3 days before expiry is recorded');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000201'::uuid),
  ((now() at time zone 'Etc/GMT-12')::date + 30),
  'the first grant starts from gym P''s own today; the three future typed days were unpaid, and the gym-local date must still be used');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000402', '210000ff-0021-4000-8000-100000000003', '210000ff-0021-4000-8000-500000000202', '210000ff-0021-4000-8000-600000000202', 100000, 'cash', 'paid', now(), 'H21-GP-LATE', '210000ff-0021-4000-8000-300000000031')$$,
  'gym P: a payment renewing three weeks after expiry is recorded');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000202'::uuid),
  ((now() at time zone 'Etc/GMT-12')::date + 30),
  'extended from gym P''s own today, not from the lapsed end date — MNY-004, never current_date and never the session (UTC) date');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000403', '210000ff-0021-4000-8000-100000000004', '210000ff-0021-4000-8000-500000000211', '210000ff-0021-4000-8000-600000000211', 100000, 'cash', 'paid', now(), 'H21-GM-EARLY', '210000ff-0021-4000-8000-300000000041')$$,
  'gym M (Etc/GMT+12, the other half of the 24-hour-apart pair): the same early-renewal case');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000211'::uuid),
  ((now() at time zone 'Etc/GMT+12')::date + 30),
  'gym M''s first grant likewise sets one sold period from ITS OWN today, evaluated 24 hours from gym P''s date');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, receipt_number, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000404', '210000ff-0021-4000-8000-100000000004', '210000ff-0021-4000-8000-500000000212', '210000ff-0021-4000-8000-600000000212', 100000, 'cash', 'paid', now(), 'H21-GM-LATE', '210000ff-0021-4000-8000-300000000041')$$,
  'gym M: the same late-renewal case');

select is(
  (select ends_on from public.memberships where id = '210000ff-0021-4000-8000-600000000212'::uuid),
  ((now() at time zone 'Etc/GMT+12')::date + 30),
  'gym M''s late renewal starts from gym M''s own today — the two gyms cannot both be right if either one is reading a UTC or session-local date instead of its own');

-- ---------------------------------------------------------------------------
-- 9. Who may write. payments' write gate is is_front_office() (front desk
--    included); refunds' write gate is is_gym_admin() — narrower, and
--    EXCLUDING front desk. Both are already live from Phase 2 (ADR-052 for
--    the cross-tenant probe); asserted here as evidence already held, not
--    as something Phase 5 must build.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '210000ff-0021-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- Recorded `paid`, not `created`: both refunds below are taken against this
-- row, and `GL036` refuses a refund against a payment that has taken no money.
-- Front desk taking cash and recording it paid is what this session does
-- anyway, and both assertions below turn on the ROLE, which a status does not
-- touch -- the refunds policy answers before the trigger runs, so the front
-- desk is still refused with 42501. The receipt number is allocated by
-- `app.stamp_payment()` as for any front-desk payment; gym A's receipt counter
-- is not asserted again after section 6, so that allocation is invisible here.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000301', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000f', 1000, 'cash', 'paid', '210000ff-0021-4000-8000-300000000001')$$,
  'front desk recording a payment in its own gym succeeds — already true under the Phase 2 role matrix');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000101', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000301', 'refund', 1000, 'h21 front desk attempts a refund', '210000ff-0021-4000-8000-300000000001')$$,
  '42501', null,
  'front desk attempting to record a REFUND in the same gym is refused — refunds'' write gate is is_gym_admin(), which front desk does not satisfy, even though it may write payments themselves');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000304', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-500000000101', 1000, 'cash', 'created', '210000ff-0021-4000-8000-300000000001')$$,
  '23503', null,
  'ADR-052: front desk of gym A, writing into its own gym (tenant_id satisfies the row-security check), naming a MEMBER of gym B is refused by the composite foreign key before any policy is even reached — a payment cannot be recorded against another gym''s member');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('210000ff-0021-4000-8000-800000000102', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-700000000301', 'refund', 1000, 'h21 manager refund succeeds', '210000ff-0021-4000-8000-300000000004')$$,
  'and as a check on the previous refusal being about the ROLE and not the row: as postgres (bypassing RLS entirely, the same fixture-building path this whole file uses), the identical refund succeeds — nothing about the row itself was wrong'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'trainer',
                     'staff_id', '210000ff-0021-4000-8000-300000000005')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
    values ('210000ff-0021-4000-8000-700000000302', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000f', 1000, 'cash', 'created', '210000ff-0021-4000-8000-300000000005')$$,
  '42501', null,
  'a trainer recording a payment is refused — is_front_office() does not include trainer, already true under the Phase 2 role matrix');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '210000ff-0021-4000-8000-100000000001',
                     'app_role', 'member',
                     'member_id', '210000ff-0021-4000-8000-50000000000f')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, amount_paise, method, status)
    values ('210000ff-0021-4000-8000-700000000303', '210000ff-0021-4000-8000-100000000001', '210000ff-0021-4000-8000-50000000000f', 1000, 'cash', 'created')$$,
  '42501', null,
  'a member session attempting to insert its own payment directly is refused — a member writes nothing directly, in this table as in every other');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 10. Elevation must justify itself (ADR-066): a closed allowlist of the
--     `security definer` functions this project already has, so a Phase 5
--     function added without the same justification is caught by name
--     rather than by re-reading its body (which this file may not do).
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prosecdef
      and p.proname not in ('audit_impersonation_session', 'custom_access_token_hook', 'revoke_sessions_on_identity_change', 'audit_money_change',
        'lock_addon_product_for_order', 'apply_addon_order_effects', 'lock_addon_order_for_pt_session', 'apply_pt_session_effect', 'apply_addon_refund_effect', 'addon_order_fully_returned')),
  0,
  'ADR-066/AUD-001/A-012: elevation remains within the closed identity, audit and approved private add-on capability allowlist');

-- ---------------------------------------------------------------------------
-- 11. PAY-011: gym A has no Razorpay account connected at all, and every
--     cash payment recorded against it above worked anyway.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select 1 from public.razorpay_accounts where tenant_id = '210000ff-0021-4000-8000-100000000001'$$,
  'PAY-011: gym A never had a razorpay_accounts row at any point in this file — every payment, extension, receipt and refund above happened with no payment gateway connected, which is the required default, not a degraded fallback');

select * from finish();

rollback;
