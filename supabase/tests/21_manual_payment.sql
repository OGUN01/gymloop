-- 21_manual_payment.sql — capability: manual (desk) payments (Phase 5)
--
-- Written from openspec/changes/phase-5-money/specs/manual-payment/spec.md,
-- openspec/changes/phase-5-money/specs/receipts-and-renewal/spec.md and
-- plan.md, by a session that has not read the implementation and did not
-- look for it. No migration dated 20260910000000 or later exists yet on
-- Cloud (`supabase migration list --linked` tops out at 20260909190000, and
-- that emptiness was itself the check, not an assumption) so there was
-- nothing of Phase 5's to accidentally open; supabase/tests-holdout/ was not
-- read either. Everything about table shape, constraints, grants, policies
-- and indexes below comes from the catalogue (information_schema,
-- pg_constraint, pg_policies, pg_indexes, pg_trigger, pg_proc — all read via
-- `supabase db query --linked`, never from a migration file), plus the
-- existing visible suites for house style (19_follow_ups.sql in particular,
-- for the staff-attribution shape this rule is the fourth appearance of).
--
-- WHAT THE CATALOGUE SHOWED, STATED UP FRONT
--
-- payments, refunds and document_counters already exist (Phase 1, cluster
-- membership+money) with: payments_amount_paise_chk, payments_offline_has_
-- staff_chk, payments_paid_has_reference_chk, payments_razorpay_has_order_
-- chk, payments_provider_reference_has_provider_chk (all CHECK constraints —
-- Section 0 re-asserts each once); a partial UNIQUE index on payments
-- (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL; a partial
-- UNIQUE index on payments (tenant_id, receipt_number) WHERE receipt_number
-- IS NOT NULL; authenticated holds INSERT, SELECT, UPDATE (no DELETE) on all
-- three tables; payments_tenant_write and document_counters_tenant_write
-- both gate on app.is_front_office(), refunds_tenant_write gates on the
-- narrower app.is_gym_admin() (gym_owner/gym_manager only — front_desk may
-- record money but not refund it); and the only trigger on any of the three
-- is touch_updated_at (BEFORE UPDATE, touches updated_at only — nothing
-- stamps or derives anything on INSERT today). That last fact is why almost
-- every new rule below is currently reachable with a plain authenticated
-- INSERT and nothing refuses it — the asymmetry the spec names ("a manual
-- payment has no provider to verify against") is exactly the gap this file
-- measures.
--
-- WHAT THIS FILE ASSUMES
--
-- A 'paid' payment needs receipt_number OR provider_payment_id to satisfy
-- payments_paid_has_reference_chk — a Phase 1 fact, not new. Where receipt
-- allocation IS the rule under test (Section 3), the fixture supplies
-- neither and expects the write itself to succeed once a BEFORE INSERT
-- trigger fills receipt_number in — so those lives_ok calls are RED for the
-- same reason the CHECK exists at all. Where receipt allocation is NOT under
-- test (Sections 4 and 5, extension and refunds), the fixture supplies a
-- synthetic receipt_number by hand so the Phase 1 CHECK passes and the
-- assertion measures only its own rule — "Each fixture proves only the rule
-- it names."
--
-- Four tenants, not two, and each owns exactly one concern: A (staff
-- attribution, desk-vs-provider, same-gym receipt uniqueness, refunds,
-- same/cross-gym idempotency), B (cross-tenant receipt independence and
-- idempotency), C (extension / greatest(ends_on, today) — isolated so its
-- membership dates are never read by anything else in the file), D
-- (financial-year restart — isolated so its document_counters rows are
-- never touched by any other section's payments). ADR-050: every count is
-- scoped to this file's own tenants.
--
-- "Today" is never current_date. Section 4 reads
-- (now() at time zone o.timezone)::date from tenant C's own organizations
-- row into a temp table once, and every later date in that section is an
-- offset from that captured value — never a literal date, never
-- current_date. Section 3's financial-year fixture uses explicit
-- timestamptz literals for the OLD financial year (2026-01-15, deep inside
-- January, nowhere near a month boundary) and the database's own now() for
-- the current one (2026-09-09 per today's date, equally far from the 1
-- April boundary) — so a UTC/IST discrepancy could not flip either payment
-- into the wrong financial year even if the implementation got MNY-004
-- wrong.
--
-- The financial year string is not read from any implementation: it is
-- derived by hand from the spec's own definition ("1 April - 31 March") and
-- cross-checked against document_counters_financial_year_format_chk's regex
-- (^[0-9]{4}-[0-9]{2}$, read from the catalogue): 2026-01-15 falls in
-- 2025-26, 2026-09-09 falls in 2026-27.
--
-- No assertion here pins a mechanism as trigger, constraint or policy — every
-- throws_ok is null::char(5), null (any SQLSTATE), matching this project's
-- existing suites (16_checkin.sql, 17_pause_decision.sql, 19_follow_ups.sql).
--
-- WHAT IS NOT ATTEMPTED
--
-- True concurrency (two staff recording a payment "at the same instant", or
-- two receipts allocated at the same instant) cannot be staged inside one
-- transaction — the same limitation 19_follow_ups.sql's assertion 16 states
-- for itself. The task brief's own six-item list of what is new does not
-- name a concurrency scenario as required coverage (unlike follow_ups',
-- which named a serialising-lock check explicitly), so this file does not
-- invent one. A failed-payment's receipt number outliving it
-- (receipts-and-renewal's fourth scenario under requirement 1) is also not
-- attempted: a manual/cash payment has no natural pending-then-failed
-- transition to stage it with, and it is not in the task's required list.
-- Both are gaps to close explicitly if this rule is ever revisited, not
-- gaps pretended away.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own four tenants.
-- ADR-069: every assertion routes through a pgTAP function (ok / lives_ok /
--          throws_ok / results_eq); nothing here is a bare top-level select
--          of a helper that could print a stray line prove would count as a
--          test nobody wrote.
--
-- PLAN COUNT: 43. Confirmed against Cloud via `supabase db query --linked -f`
-- (begin…rollback, nothing committed — this run's own diagnostic query
-- confirms the rollback path still executes). scratchpad/tapcount.py's
-- trigger regex was missing `lives_ok\(` (present for throws_ok, is,
-- is_empty, results_eq, ok, plan and finish, but not lives_ok) — a tool gap
-- that silently dropped every lives_ok line from the captured TAP stream
-- and undercounted this file at 31 lines instead of 45. Fixed in
-- scratchpad/tapcount.py (one token) before trusting its count. With the
-- fix: `plan_line` is `1..43`, `ok_count` 21 + `not_ok_count` 22 = 43
-- matching the plan exactly, and `total_lines` 45 = the plan line + all 43
-- assertions + finish()'s one diagnostic comment row (this run failed, so
-- finish() emitted its "Looks like you failed 22 tests" line, itself
-- captured harmlessly by the same trigger). Every one of pgTAP's "died:
-- <SQLSTATE>" reports below is lives_ok catching a real exception via its
-- own internal SAVEPOINT and continuing — not a poisoned transaction; every
-- assertion after each one still ran and queried real state, through to 43.
--
-- RED (22) — the rule under test is not built, exactly as expected:
--   8, 9 (naming a colleague is not refused — Section 1); 10, 11 (a
--   claimless session's write is not refused either — the same null-actor
--   defect this project has shipped twice before, GL016/GL026's cousin,
--   still open here); 12, 13 (a cash payment carrying a forged
--   provider_payment_id is not refused — Section 2); 14, 15 (a
--   razorpay-method payment typed in through the desk is not refused
--   either); 16, 17 (a paid cash payment naming no receipt_number of its
--   own dies on payments_paid_has_reference_chk — Phase 1's own CHECK,
--   correctly still enforced, but nothing yet fills receipt_number in
--   before it runs, so the very payment a receipt-allocating trigger would
--   rescue currently cannot be recorded at all); 18 (receipt-number
--   uniqueness is unproven because 16/17 never landed); 19 (gym B's own
--   first paid payment dies the same way); 20 (gym-independence unproven,
--   same cause); 21, 22 (the financial-year fixture payments die the same
--   way, in tenant D); 23, 24 (the financial-year restart proof is
--   unreachable because 21/22 never landed); 26, 28, 30 (a membership's
--   ends_on does not move at all: each read back exactly its own
--   pre-payment value — today (2026-09-09) for the same-day case, today+3
--   (2026-09-12) for the early case, today-21 (2026-08-19) for the late
--   case — confirming no extension trigger exists yet, for the simple,
--   early and late scenarios respectively); 37, 38 (a second refund that would
--   push the total to 110000 against a 100000 payment is not refused, and
--   the total sits at 110000 rather than the correct 40000).
--
-- GREEN (21), and each is said here because it is coverage the suite earns
-- rather than the rule proving itself:
--   1-5 (Phase 1's own CHECK constraints — amount_paise_chk,
--   offline_has_staff_chk, paid_has_reference_chk, razorpay_has_order_chk,
--   provider_reference_has_provider_chk — all still enforced, exactly as
--   the catalogue read before writing this file said they would be); 6, 7
--   (a front-desk session naming itself as recorded_by_staff_id is not
--   refused, and reads back correctly — this is the legitimate write the
--   colleague/claimless cases (8-11) are contrasted against, not itself
--   evidence of the new rule); 25, 27, 29 (the extension fixtures' own
--   lives_ok calls succeed, because each supplies a synthetic receipt_number
--   by hand and nothing else about a plain paid cash payment is refused
--   today — Phase 1 capability, not the extension rule Section 4 actually
--   measures via 26/28/30); 31, 32 (a non-paid payment extends nothing —
--   true today because nothing extends anything at all, and it will stay
--   true once the rule exists, because the rule itself only fires on
--   status='paid'); 33, 34 (a payment naming no membership is recorded and
--   nothing is extended for that member — same "true by absence today,
--   true by design once built" shape); 35, 36 (recording a refund, and the
--   original payment's row surviving byte-for-byte, are both already true —
--   refunds is a normal Phase 1 INSERT target and nothing in this schema has
--   ever had a code path that would touch payments.amount_paise from a
--   refund insert); 39-43 (idempotency — payments_tenant_id_idempotency_
--   key_key, a partial UNIQUE index on (tenant_id, idempotency_key) read
--   from the catalogue before this file was written, already guarantees one
--   row per key per gym and independence across gyms; a Phase 1 fact, not
--   anything Phase 5 has to add).

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(43);


-- ---------------------------------------------------------------------------
-- Fixtures.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('21000000-0000-4000-8000-000000000001'::uuid, 'Manual Pay Gym A', 'MPY21A'),
  ('21000000-0000-4000-8000-000000000002'::uuid, 'Manual Pay Gym B', 'MPY21B'),
  ('21000000-0000-4000-8000-000000000003'::uuid, 'Manual Pay Gym C', 'MPY21C'),
  ('21000000-0000-4000-8000-000000000004'::uuid, 'Manual Pay Gym D', 'MPY21D');

insert into public.branches (id, tenant_id, name, is_default) values
  ('21000000-0000-4000-8000-000000000011'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('21000000-0000-4000-8000-000000000012'::uuid, '21000000-0000-4000-8000-000000000002'::uuid, 'B Main', true),
  ('21000000-0000-4000-8000-000000000013'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, 'C Main', true),
  ('21000000-0000-4000-8000-000000000014'::uuid, '21000000-0000-4000-8000-000000000004'::uuid, 'D Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('21000000-0000-4000-8000-000000000021'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('21000000-0000-4000-8000-000000000022'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Colleague'),
  ('21000000-0000-4000-8000-000000000023'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Manager'),
  ('21000000-0000-4000-8000-000000000025'::uuid, '21000000-0000-4000-8000-000000000002'::uuid, '21000000-0000-4000-8000-000000000012'::uuid, 'front_desk',  'B Desk'),
  ('21000000-0000-4000-8000-000000000027'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'front_desk',  'C Desk'),
  ('21000000-0000-4000-8000-000000000028'::uuid, '21000000-0000-4000-8000-000000000004'::uuid, '21000000-0000-4000-8000-000000000014'::uuid, 'front_desk',  'D Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('21000000-0000-4000-8000-000000000040'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Phase1 Recap',    '+912100000040'),
  ('21000000-0000-4000-8000-000000000041'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Attrib Success',  '+912100000041'),
  ('21000000-0000-4000-8000-000000000042'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Attrib Colleague','+912100000042'),
  ('21000000-0000-4000-8000-000000000043'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Attrib NoClaim',  '+912100000043'),
  ('21000000-0000-4000-8000-000000000044'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Desk Provider',   '+912100000044'),
  ('21000000-0000-4000-8000-000000000045'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Desk Razorpay',   '+912100000045'),
  ('21000000-0000-4000-8000-000000000046'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Receipt A1',      '+912100000046'),
  ('21000000-0000-4000-8000-000000000047'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Receipt A2',      '+912100000047'),
  ('21000000-0000-4000-8000-000000000048'::uuid, '21000000-0000-4000-8000-000000000002'::uuid, '21000000-0000-4000-8000-000000000012'::uuid, 'M Receipt B1',      '+912100000048'),
  ('21000000-0000-4000-8000-000000000049'::uuid, '21000000-0000-4000-8000-000000000004'::uuid, '21000000-0000-4000-8000-000000000014'::uuid, 'M FY D1',           '+912100000049'),
  ('21000000-0000-4000-8000-00000000004a'::uuid, '21000000-0000-4000-8000-000000000004'::uuid, '21000000-0000-4000-8000-000000000014'::uuid, 'M FY D2',           '+912100000050'),
  ('21000000-0000-4000-8000-00000000004b'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'M Ext Simple',      '+912100000051'),
  ('21000000-0000-4000-8000-00000000004c'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'M Ext Early',       '+912100000052'),
  ('21000000-0000-4000-8000-00000000004d'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'M Ext Late',        '+912100000053'),
  ('21000000-0000-4000-8000-00000000004e'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'M Ext NoPay',       '+912100000054'),
  ('21000000-0000-4000-8000-00000000004f'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, '21000000-0000-4000-8000-000000000013'::uuid, 'M Ext NoMembership','+912100000055'),
  ('21000000-0000-4000-8000-000000000050'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Refund',          '+912100000056'),
  ('21000000-0000-4000-8000-000000000051'::uuid, '21000000-0000-4000-8000-000000000001'::uuid, '21000000-0000-4000-8000-000000000011'::uuid, 'M Idem A',          '+912100000057'),
  ('21000000-0000-4000-8000-000000000052'::uuid, '21000000-0000-4000-8000-000000000002'::uuid, '21000000-0000-4000-8000-000000000012'::uuid, 'M Idem B',          '+912100000058');

-- Tenant C's own plan and four memberships, for Section 4. Duration is 30
-- days across the board so every expected end date below is a plain offset.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('21000000-0000-4000-8000-000000000033'::uuid, '21000000-0000-4000-8000-000000000003'::uuid, 'C Plan (30d)', 30, 100000);

-- Tenant C's own gym-local "today", read from the row rather than assumed —
-- every date fixture and every expected value in Section 4 is an offset from
-- this, never a literal date.
create temp table today_c as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o
   where o.id = '21000000-0000-4000-8000-000000000003'::uuid;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('21000000-0000-4000-8000-000000000031'::uuid, '21000000-0000-4000-8000-000000000003'::uuid,
   '21000000-0000-4000-8000-00000000004b'::uuid, '21000000-0000-4000-8000-000000000033'::uuid,
   'active', (select d from today_c) - 27, (select d from today_c), 100000),
  ('21000000-0000-4000-8000-000000000032'::uuid, '21000000-0000-4000-8000-000000000003'::uuid,
   '21000000-0000-4000-8000-00000000004c'::uuid, '21000000-0000-4000-8000-000000000033'::uuid,
   'active', (select d from today_c) - 27, (select d from today_c) + 3, 100000),
  ('21000000-0000-4000-8000-000000000034'::uuid, '21000000-0000-4000-8000-000000000003'::uuid,
   '21000000-0000-4000-8000-00000000004d'::uuid, '21000000-0000-4000-8000-000000000033'::uuid,
   'active', (select d from today_c) - 51, (select d from today_c) - 21, 100000),
  ('21000000-0000-4000-8000-000000000035'::uuid, '21000000-0000-4000-8000-000000000003'::uuid,
   '21000000-0000-4000-8000-00000000004e'::uuid, '21000000-0000-4000-8000-000000000033'::uuid,
   'active', (select d from today_c) - 20, (select d from today_c) + 10, 100000);


-- ---------------------------------------------------------------------------
-- Section 0 — Phase 1's own CHECK constraints, re-asserted once each so a
-- future migration cannot quietly drop them. Not new rules: this is a
-- catalogue-confirmed recap (pg_constraint, read before writing this
-- section), and every assertion here is expected GREEN. Run as postgres
-- directly — these are CHECK constraints, not RLS, so no JWT claim is
-- needed to exercise them. (1-5)
-- ---------------------------------------------------------------------------

-- 1 — payments_amount_paise_chk
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001014'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000040'::uuid,
          0, 'cash', '21000000-0000-4000-8000-000000000021'::uuid)
$$, null::char(5), null,
  'Phase 1 recap (payments_amount_paise_chk) — a zero amount is refused');

-- 2 — payments_offline_has_staff_chk
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001015'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000040'::uuid,
          100000, 'cash', null)
$$, null::char(5), null,
  'Phase 1 recap (payments_offline_has_staff_chk) — a non-razorpay payment naming no staff member is refused');

-- 3 — payments_paid_has_reference_chk
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001016'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000040'::uuid,
          100000, 'cash', 'paid', '21000000-0000-4000-8000-000000000021'::uuid)
$$, null::char(5), null,
  'Phase 1 recap (payments_paid_has_reference_chk) — a paid payment naming neither a provider payment id nor a receipt number is refused');

-- 4 — payments_razorpay_has_order_chk
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method)
  values ('21000000-0000-4000-8000-000000001017'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000040'::uuid,
          100000, 'razorpay')
$$, null::char(5), null,
  'Phase 1 recap (payments_razorpay_has_order_chk) — a razorpay payment naming no provider_order_id is refused');

-- 5 — payments_provider_reference_has_provider_chk
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, provider_payment_id)
  values ('21000000-0000-4000-8000-000000001018'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000040'::uuid,
          100000, 'razorpay', 'pay_recap')
$$, null::char(5), null,
  'Phase 1 recap (payments_provider_reference_has_provider_chk) — a provider_payment_id with no provider named is refused');


-- ---------------------------------------------------------------------------
-- Section 1 — A recorded payment names the staff member who took it (6-11).
-- The fourth appearance of one rule, after GL016 (attendance), GL026
-- (membership_pauses) and GL030 (follow_ups). ADR-071: the null-actor case
-- is its own scenario, not one arm of a comparison.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 6
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001001'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000041'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000021'::uuid)
$$, 'scenario "Recording a payment" — a front-desk staff member recording a cash payment, naming themselves, is not refused');

set local role postgres;

-- 7 — lives_ok proves nothing about what landed; the row has to read back.
select results_eq(
  $$ select recorded_by_staff_id, amount_paise from public.payments
      where id = '21000000-0000-4000-8000-000000001001'::uuid $$,
  $$ values ('21000000-0000-4000-8000-000000000021'::uuid, 150000::bigint) $$,
  'scenario "Recording a payment" — it landed, attributed to the staff member who recorded it'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 8 — everything about this write is otherwise legitimate: front_desk 21 is
-- acting in their own gym, naming a real colleague of that same gym. The
-- only thing wrong is that the named staff_id is not the acting one.
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001002'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000042'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000022'::uuid)
$$, null::char(5), null,
  'scenario "Naming a colleague" — a front-desk session cannot record a payment under a colleague''s name, even a real colleague of the same gym');

set local role postgres;

-- 9
select results_eq(
  $$ select count(*)::int from public.payments
      where member_id = '21000000-0000-4000-8000-000000000042'::uuid $$,
  $$ values (0) $$,
  'the misattributed payment left no row behind'
);

-- 10 — the session the spec singles out: app_role and tenant_id, deliberately
-- no staff_id claim at all (the shape app.custom_access_token_hook mints for
-- a live impersonation, ADR-071).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001003'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000043'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000021'::uuid)
$$, null::char(5), null,
  'scenario "A session with no staff identity" — a session carrying app_role and tenant_id but no staff_id claim records no payment at all, whoever it names as recorded_by_staff_id');

set local role postgres;

-- 11
select results_eq(
  $$ select count(*)::int from public.payments
      where member_id = '21000000-0000-4000-8000-000000000043'::uuid $$,
  $$ values (0) $$,
  'the claimless write left no row behind'
);


-- ---------------------------------------------------------------------------
-- Section 2 — A manual payment cannot claim a provider (12-15).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 12 — provider named too, so a REFUSAL here is this rule's own and not
-- payments_provider_reference_has_provider_chk (Section 0, assertion 5).
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, provider, provider_payment_id)
  values ('21000000-0000-4000-8000-000000001004'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000044'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000021'::uuid,
          'razorpay', 'pay_forged123')
$$, null::char(5), null,
  'scenario "A cash payment carrying a provider payment id" — refused; that shape would launder a cash payment into an apparently-verified one');

set local role postgres;

-- 13
select results_eq(
  $$ select count(*)::int from public.payments
      where member_id = '21000000-0000-4000-8000-000000000044'::uuid $$,
  $$ values (0) $$,
  'the forged-provider cash payment left no row behind'
);

-- 14 — an online method through the desk. provider and provider_order_id are
-- supplied so a refusal here is this rule's own and not
-- payments_razorpay_has_order_chk (Section 0, assertion 4).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, provider, provider_order_id)
  values ('21000000-0000-4000-8000-000000001005'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000045'::uuid,
          150000, 'razorpay', 'razorpay', 'order_desk_typed')
$$, null::char(5), null,
  'scenario "An online method through the desk" — a razorpay-method payment typed in through the manual path is refused; online state is the provider''s to report (PAY-006)');

set local role postgres;

-- 15
select results_eq(
  $$ select count(*)::int from public.payments
      where member_id = '21000000-0000-4000-8000-000000000045'::uuid $$,
  $$ values (0) $$,
  'the desk-typed razorpay payment left no row behind'
);


-- ---------------------------------------------------------------------------
-- Section 3 — A receipt number is unique per gym and never reused (16-24).
-- ---------------------------------------------------------------------------

-- Same gym, two payments: 16-18.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 16 — no receipt_number, no provider_payment_id: this is exactly what
-- payments_paid_has_reference_chk (Section 0, assertion 3) refuses today.
-- It is expected to start succeeding once a BEFORE INSERT trigger fills
-- receipt_number in before that CHECK runs.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001006'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000046'::uuid,
          150000, 'cash', 'paid', '21000000-0000-4000-8000-000000000021'::uuid)
$$, 'scenario "Two payments in the same gym" — the first paid cash payment, naming no receipt number of its own, is not refused');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 17
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001007'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000047'::uuid,
          150000, 'cash', 'paid', '21000000-0000-4000-8000-000000000021'::uuid)
$$, 'scenario "Two payments in the same gym" — the second paid cash payment, in the same gym, is not refused either');

set local role postgres;

-- 18
select results_eq(
  $$
    select count(*) filter (where receipt_number is not null)::int,
           count(distinct receipt_number)::int
      from public.payments
     where id in ('21000000-0000-4000-8000-000000001006'::uuid, '21000000-0000-4000-8000-000000001007'::uuid)
  $$,
  $$ values (2, 2) $$,
  'scenario "Two payments in the same gym" — both were allocated a receipt number, and their receipt numbers differ'
);

-- Two gyms: 19-20. Snapshot tenant A's document_counters(kind=''receipt'')
-- before tenant B ever records anything.
create temp table dca_before as
  select tenant_id, kind, financial_year, next_number, created_at, updated_at
    from public.document_counters
   where tenant_id = '21000000-0000-4000-8000-000000000001'::uuid
     and kind = 'receipt';

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000025')::text,
  true);
set local role authenticated;

-- 19
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-000000001008'::uuid,
          '21000000-0000-4000-8000-000000000002'::uuid,
          '21000000-0000-4000-8000-000000000048'::uuid,
          150000, 'cash', 'paid', '21000000-0000-4000-8000-000000000025'::uuid)
$$, 'scenario "Two gyms" — gym B''s own first paid cash payment is not refused');

set local role postgres;

-- 20 — gym B got its own number AND gym A''s counter is untouched, checked
-- together: either half alone would let the other one fail silently.
select results_eq(
  $$
    select
      (select receipt_number is not null from public.payments
        where id = '21000000-0000-4000-8000-000000001008'::uuid),
      (
        not exists (
          select tenant_id, kind, financial_year, next_number, created_at, updated_at
            from public.document_counters
           where tenant_id = '21000000-0000-4000-8000-000000000001'::uuid and kind = 'receipt'
          except
          select * from dca_before
        )
        and not exists (
          select * from dca_before
          except
          select tenant_id, kind, financial_year, next_number, created_at, updated_at
            from public.document_counters
           where tenant_id = '21000000-0000-4000-8000-000000000001'::uuid and kind = 'receipt'
        )
      )
  $$,
  $$ values (true, true) $$,
  'scenario "Two gyms" — gym B was allocated a receipt number and gym A''s own counter rows are exactly what they were before gym B recorded anything'
);

-- A new financial year, tenant D, isolated: 21-24.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000028')::text,
  true);
set local role authenticated;

-- 21 — deep in January 2026 (financial year 2025-26), nowhere near the
-- 1 April boundary. created_at and paid_at are both pinned to the same
-- literal so whichever column financial-year derivation actually reads, the
-- fixture is unambiguous either way.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id, created_at, paid_at)
  values ('21000000-0000-4000-8000-000000001009'::uuid,
          '21000000-0000-4000-8000-000000000004'::uuid,
          '21000000-0000-4000-8000-000000000049'::uuid,
          150000, 'cash', 'paid', '21000000-0000-4000-8000-000000000028'::uuid,
          '2026-01-15 10:00:00+05:30'::timestamptz, '2026-01-15 10:00:00+05:30'::timestamptz)
$$, 'scenario "A new financial year" — the first payment of financial year 2025-26 is not refused');

set local role postgres;

create temp table dcd_2526_before as
  select next_number from public.document_counters
   where tenant_id = '21000000-0000-4000-8000-000000000004'::uuid
     and kind = 'receipt' and financial_year = '2025-26';

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000028')::text,
  true);
set local role authenticated;

-- 22 — deep in September 2026 (today, financial year 2026-27), also
-- nowhere near the boundary. now() is read twice in the same statement, so
-- created_at and paid_at land on the identical instant.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id, created_at, paid_at)
  values ('21000000-0000-4000-8000-00000000100a'::uuid,
          '21000000-0000-4000-8000-000000000004'::uuid,
          '21000000-0000-4000-8000-00000000004a'::uuid,
          150000, 'cash', 'paid', '21000000-0000-4000-8000-000000000028'::uuid,
          now(), now())
$$, 'scenario "A new financial year" — the first payment of financial year 2026-27, in the same gym, is not refused');

set local role postgres;

-- 23 — the restart, proven without assuming what "the first number" is:
-- both payments are the FIRST of their own financial year, so if the
-- sequence genuinely restarts they carry the same starting number.
select results_eq(
  $$
    select
      (select receipt_number is not null from public.payments where id = '21000000-0000-4000-8000-000000001009'::uuid),
      (select receipt_number is not null from public.payments where id = '21000000-0000-4000-8000-00000000100a'::uuid),
      (
        (select receipt_number from public.payments where id = '21000000-0000-4000-8000-000000001009'::uuid)
        = (select receipt_number from public.payments where id = '21000000-0000-4000-8000-00000000100a'::uuid)
      )
  $$,
  $$ values (true, true, true) $$,
  'scenario "A new financial year" — both payments were allocated a receipt number, and the new year''s first number matches the old year''s first number, because both are position one of their own sequence'
);

-- 24 — the previous year's counter is untouched, and a distinct row for the
-- new year exists — checked together.
select results_eq(
  $$
    select
      (
        (select next_number from public.document_counters
          where tenant_id = '21000000-0000-4000-8000-000000000004'::uuid
            and kind = 'receipt' and financial_year = '2025-26')
        = (select next_number from dcd_2526_before)
      ),
      exists (
        select 1 from public.document_counters
         where tenant_id = '21000000-0000-4000-8000-000000000004'::uuid
           and kind = 'receipt' and financial_year = '2026-27'
      )
  $$,
  $$ values (true, true) $$,
  'scenario "A new financial year" — financial year 2025-26''s own counter is exactly what it was before 2026-27''s first payment, and 2026-27 now has its own row'
);


-- ---------------------------------------------------------------------------
-- Section 4 — A payment extends the membership on the same rules an online
-- one would, measured from greatest(ends_on, today) in the gym's own
-- timezone (25-34). Tenant C, isolated. Every fixture supplies a synthetic
-- receipt_number by hand so payments_paid_has_reference_chk (already
-- proven in Section 0) never enters into what these assertions measure.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 25 — membership 031: ends_on = today. Structurally unremarkable (receipt_
-- number supplied), so this is expected GREEN already; the extension itself
-- is what assertion 26 measures.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id, receipt_number)
  values ('21000000-0000-4000-8000-00000000100b'::uuid,
          '21000000-0000-4000-8000-000000000003'::uuid,
          '21000000-0000-4000-8000-00000000004b'::uuid,
          '21000000-0000-4000-8000-000000000031'::uuid,
          100000, 'cash', 'paid', '21000000-0000-4000-8000-000000000027'::uuid, 'C-RCT-0001')
$$, 'scenario "A paid manual payment" — a cash payment against an active membership is not refused');

set local role postgres;

-- 26 — ends_on was today; a 30-day plan should move it to today + 30.
select results_eq(
  $$ select ends_on from public.memberships where id = '21000000-0000-4000-8000-000000000031'::uuid $$,
  $$ select (select d from today_c) + 30 $$,
  'scenario "A paid manual payment" — the membership''s end date moved forward by the plan''s 30-day duration'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 27 — membership 032: ends_on = today + 3 (renewing three days early).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id, receipt_number)
  values ('21000000-0000-4000-8000-00000000100c'::uuid,
          '21000000-0000-4000-8000-000000000003'::uuid,
          '21000000-0000-4000-8000-00000000004c'::uuid,
          '21000000-0000-4000-8000-000000000032'::uuid,
          100000, 'cash', 'paid', '21000000-0000-4000-8000-000000000027'::uuid, 'C-RCT-0002')
$$, 'scenario "Renewing early" — a cash payment three days before expiry is not refused');

set local role postgres;

-- 28 — greatest(today+3, today) = today+3, plus 30 = today+33. Three days
-- further out than a same-day renewal (assertion 26, today+30) would give.
select results_eq(
  $$ select ends_on from public.memberships where id = '21000000-0000-4000-8000-000000000032'::uuid $$,
  $$ select (select d from today_c) + 33 $$,
  'scenario "Renewing early" — the new end date is three days further out than a same-day renewal would give; the member renewing early lost nothing'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 29 — membership 034: ends_on = today - 21 (lapsed three weeks ago).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id, receipt_number)
  values ('21000000-0000-4000-8000-00000000100d'::uuid,
          '21000000-0000-4000-8000-000000000003'::uuid,
          '21000000-0000-4000-8000-00000000004d'::uuid,
          '21000000-0000-4000-8000-000000000034'::uuid,
          100000, 'cash', 'paid', '21000000-0000-4000-8000-000000000027'::uuid, 'C-RCT-0003')
$$, 'scenario "Renewing late" — a cash payment three weeks after expiry is not refused');

set local role postgres;

-- 30 — greatest(today-21, today) = today, plus 30 = today+30. Not
-- today-21+30 (=today+9), which would hand the member three free weeks.
select results_eq(
  $$ select ends_on from public.memberships where id = '21000000-0000-4000-8000-000000000034'::uuid $$,
  $$ select (select d from today_c) + 30 $$,
  'scenario "Renewing late" — the new period starts from today, not from the lapsed end date; the member renewing late gained nothing extra'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 31 — membership 035, a payment left at its default (non-paid) status.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, recorded_by_staff_id)
  values ('21000000-0000-4000-8000-00000000100e'::uuid,
          '21000000-0000-4000-8000-000000000003'::uuid,
          '21000000-0000-4000-8000-00000000004e'::uuid,
          '21000000-0000-4000-8000-000000000035'::uuid,
          100000, 'cash', '21000000-0000-4000-8000-000000000027'::uuid)
$$, 'scenario "A payment that is not paid" — recording it against an active membership is not refused');

set local role postgres;

-- 32 — an intention to pay is not a payment (PAY-008): nothing moves.
select results_eq(
  $$ select ends_on from public.memberships where id = '21000000-0000-4000-8000-000000000035'::uuid $$,
  $$ select (select d from today_c) + 10 $$,
  'scenario "A payment that is not paid" — the membership''s end date is exactly what it was, untouched'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 33 — a payment naming no membership at all.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id, receipt_number)
  values ('21000000-0000-4000-8000-00000000100f'::uuid,
          '21000000-0000-4000-8000-000000000003'::uuid,
          '21000000-0000-4000-8000-00000000004f'::uuid,
          null,
          50000, 'cash', 'paid', '21000000-0000-4000-8000-000000000027'::uuid, 'C-RCT-0004')
$$, 'scenario "A payment against no membership" — a gym may take money for something else, and it is not refused');

set local role postgres;

-- 34 — it was recorded, membership_id is genuinely null, and nothing that
-- looks like a membership sprang into being for this member.
select results_eq(
  $$
    select amount_paise, membership_id,
           (select count(*)::int from public.memberships where member_id = '21000000-0000-4000-8000-00000000004f'::uuid)
      from public.payments where id = '21000000-0000-4000-8000-00000000100f'::uuid
  $$,
  $$ values (50000::bigint, null::uuid, 0) $$,
  'scenario "A payment against no membership" — recorded with membership_id null, and no membership exists for that member'
);


-- ---------------------------------------------------------------------------
-- Section 5 — A refund is a new row, never a mutation (35-38). Tenant A.
-- The payment being refunded is a fixture, inserted as postgres so its
-- existence tests nothing and cannot be credited to any rule under test.
-- refunds_tenant_write gates on app.is_gym_admin() (gym_owner/gym_manager),
-- narrower than payments_tenant_write's is_front_office() — so the refund
-- is recorded by staff 23 (gym_manager), not staff 21 (front_desk).
-- ---------------------------------------------------------------------------

insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id, receipt_number)
values ('21000000-0000-4000-8000-000000001010'::uuid,
        '21000000-0000-4000-8000-000000000001'::uuid,
        '21000000-0000-4000-8000-000000000050'::uuid,
        100000, 'cash', 'paid', '21000000-0000-4000-8000-000000000021'::uuid, 'A-RCT-REFUND');

create temp table p_refund_snapshot as
  select id, tenant_id, member_id, membership_id, amount_paise, currency, status, method,
         provider, provider_order_id, provider_payment_id, receipt_number, recorded_by_staff_id,
         idempotency_key, paid_at, failed_reason, notes, created_at
    from public.payments
   where id = '21000000-0000-4000-8000-000000001010'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '21000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- 35 — a partial refund. Recording a new row in refunds is already a Phase
-- 1 capability (grants and policy exist; nothing new is needed for the
-- write itself to succeed) — expected GREEN.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  values ('21000000-0000-4000-8000-000000002001'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000001010'::uuid,
          'refund', 40000, 'member requested a partial refund', '21000000-0000-4000-8000-000000000023'::uuid)
$$, 'scenario "Refunding a payment" — a partial refund against a paid payment is not refused');

set local role postgres;

-- 36 — the refund landed, AND the payment row is byte-for-byte what it was
-- before — checked together, because "the refund exists" alone would not
-- catch a rule that also (wrongly) touched the original.
select results_eq(
  $$
    select
      (select amount_paise from public.refunds where id = '21000000-0000-4000-8000-000000002001'::uuid),
      (
        (select row(id, tenant_id, member_id, membership_id, amount_paise, currency, status, method,
                provider, provider_order_id, provider_payment_id, receipt_number, recorded_by_staff_id,
                idempotency_key, paid_at, failed_reason, notes, created_at)
           from public.payments where id = '21000000-0000-4000-8000-000000001010'::uuid)
        is not distinct from
        (select row(id, tenant_id, member_id, membership_id, amount_paise, currency, status, method,
                provider, provider_order_id, provider_payment_id, receipt_number, recorded_by_staff_id,
                idempotency_key, paid_at, failed_reason, notes, created_at)
           from p_refund_snapshot)
      )
  $$,
  $$ values (40000::bigint, true) $$,
  'scenario "Refunding a payment" — a refunds row exists at the amount refunded, and the payment''s own row (amount_paise included) is unchanged (PAY-010, INT-001)'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '21000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- 37 — 40000 already refunded; this second refund of 70000 would bring the
-- total to 110000 against a 100000 payment.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  values ('21000000-0000-4000-8000-000000002002'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000001010'::uuid,
          'refund', 70000, 'second refund, should not fit', '21000000-0000-4000-8000-000000000023'::uuid)
$$, null::char(5), null,
  'scenario "Refunding more than was paid" — a second refund that would push the total over the payment''s amount is refused');

set local role postgres;

-- 38
select results_eq(
  $$ select coalesce(sum(amount_paise), 0)::bigint from public.refunds
      where payment_id = '21000000-0000-4000-8000-000000001010'::uuid $$,
  $$ values (40000::bigint) $$,
  'the over-limit refund did not land; the payment''s total refunded is still exactly the partial amount'
);


-- ---------------------------------------------------------------------------
-- Section 6 — Recording the same payment twice records one payment (39-43).
-- Already true structurally: payments_tenant_id_idempotency_key_key is a
-- partial UNIQUE index on (tenant_id, idempotency_key) WHERE idempotency_key
-- IS NOT NULL (read from the catalogue before writing this section) — so
-- every assertion in this section is expected GREEN, as a Phase 1 fact
-- rather than anything Phase 5 has to add.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 39
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, idempotency_key)
  values ('21000000-0000-4000-8000-000000001011'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000051'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000021'::uuid, 'idem-mp21-001')
$$, 'scenario "The same key twice" — the first payment carrying an idempotency_key is not refused');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 40 — a different row, same tenant, same idempotency_key.
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, idempotency_key)
  values ('21000000-0000-4000-8000-000000001012'::uuid,
          '21000000-0000-4000-8000-000000000001'::uuid,
          '21000000-0000-4000-8000-000000000051'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000021'::uuid, 'idem-mp21-001')
$$, '23505'::char(5), null,
  'scenario "The same key twice" — a second write carrying the same idempotency_key, in the same gym, is refused by the partial unique index');

set local role postgres;

-- 41
select results_eq(
  $$ select count(*)::int from public.payments
      where tenant_id = '21000000-0000-4000-8000-000000000001'::uuid and idempotency_key = 'idem-mp21-001' $$,
  $$ values (1) $$,
  'scenario "The same key twice" — exactly one row exists for that key in that gym'
);

-- 42 — the same key, a different gym.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '21000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '21000000-0000-4000-8000-000000000025')::text,
  true);
set local role authenticated;

select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, idempotency_key)
  values ('21000000-0000-4000-8000-000000001013'::uuid,
          '21000000-0000-4000-8000-000000000002'::uuid,
          '21000000-0000-4000-8000-000000000052'::uuid,
          150000, 'cash', '21000000-0000-4000-8000-000000000025'::uuid, 'idem-mp21-001')
$$, 'scenario "The same key in two gyms" — the same idempotency_key, in a different gym, is not refused');

set local role postgres;

-- 43
select results_eq(
  $$ select count(*)::int from public.payments where idempotency_key = 'idem-mp21-001' $$,
  $$ values (2) $$,
  'scenario "The same key in two gyms" — both rows exist, one per gym; a key is unique within a gym, not across the product'
);


select * from finish();
rollback;
