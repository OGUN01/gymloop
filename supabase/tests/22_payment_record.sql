-- 22_payment_record.sql — capability: what a payment may become after it is
-- written (Phase 5, contract `payment-record`).
--
-- Written from openspec/changes/phase-5-money/specs/payment-record/spec.md
-- by a session that has not read app.stamp_payment, app.enforce_payment,
-- app.extend_membership_on_payment or app.enforce_refund_total's source
-- (never queried via pg_get_functiondef or pg_proc.prosrc — only their
-- names, argument lists and prosecdef flag, read from pg_proc, to confirm
-- they exist and are security invoker) and has not opened any migration
-- dated 20260910000000 or later. `supabase migration list --linked` shows
-- 20260910090000_manual_payment.sql already applied on Cloud — its filename
-- is visible from `ls`, its content was never read — so this file's own
-- fixtures, and everything about table shape, constraints, grants, policies
-- and triggers below, come entirely from the catalogue (information_schema,
-- pg_constraint, pg_trigger, pg_policies, pg_type/pg_enum — all read via
-- `supabase db query --linked`, wrapped begin…rollback, nothing committed)
-- plus 21_manual_payment.sql for house style. supabase/tests-holdout/ was
-- not read either.
--
-- WHAT THE CATALOGUE SHOWED, STATED UP FRONT
--
-- payments carries four triggers: payments_stamp (BEFORE INSERT OR UPDATE,
-- app.stamp_payment), payments_enforce and payments_extend_membership (both
-- AFTER INSERT OR UPDATE, app.enforce_payment / app.extend_membership_on_
-- payment), and payments_touch_updated_at. refunds carries only
-- refunds_enforce_total (BEFORE INSERT ONLY — no BEFORE UPDATE trigger
-- exists on refunds at all beyond touch_updated_at) and touch_updated_at.
-- document_counters carries only touch_updated_at — no trigger anywhere
-- constrains next_number's direction or magnitude, or blocks DELETE.
-- payments_tenant_write and refunds_tenant_write both grant UPDATE (refunds
-- gates on the narrower app.is_gym_admin(), payments and document_counters
-- on app.is_front_office()) with no column-level restriction. This is why
-- the brief's seven demonstrated defects are all reachable today: the
-- BEFORE INSERT-only refund ceiling, the transition-free status column, the
-- unbounded document_counters UPDATE, and the frozen-field list are none of
-- them enforced on UPDATE by anything currently on these tables. The
-- INSERT-time checks proven by 21_manual_payment.sql (CHECK constraints,
-- staff attribution, receipt allocation, extension-on-paid, idempotency)
-- are assumed to still hold and are not re-proven here except where a
-- requirement below is explicitly about their UPDATE-time counterpart.
--
-- SCOPE: the spec's own file has ten `### Requirement` headings. The task
-- is "nine requirements, all about what happens to a payment AFTER it
-- exists." Nine of the ten fit that description exactly (frozen fields,
-- status transitions, paid_at stamping, the receipt counter, refund
-- bounding, refund attribution, cross-member membership, cumulative
-- periods, no-dates memberships). The tenth — "A refusal is the policy's to
-- give, not a side effect of allocating" — is about a session that may not
-- INSERT a payment at all being refused at the right layer; it is not a
-- rule about a payment that already exists, and the task's own framing
-- excludes it by that description. It is not tested here. This reading is
-- stated rather than silently assumed — see the report for this call named
-- explicitly as a scope decision, not resolved ambiguity.
--
-- WHAT THIS FILE ASSUMES AND HOW IT ISOLATES
--
-- Nine tenants, numbered to match the nine requirements below, each owning
-- exactly one concern (ADR-050): tenant 1 (frozen fields after paid),
-- tenant 2 (status transitions, including the paid→created→paid farm),
-- tenant 3 (paid_at stamping / financial year), tenant 4 (document_counters
-- integrity), tenant 5 (refund ceiling on UPDATE + refund immutability),
-- tenant 6 (refund attribution), tenant 7 (cross-member membership),
-- tenant 8 (cumulative periods), tenant 9 (no-dates memberships). No
-- assertion's count depends on another tenant's rows.
--
-- Every date is read from the gym's own `(now() at time zone o.timezone)::
-- date`, captured once per tenant into a `today_tN` temp table, never
-- `current_date` and never a bare literal date used as an *expected* value
-- (ADR-039 — this project has shipped that defect twice). Tenant 3's fixture
-- payments carry literal far-future/far-past `paid_at` timestamps
-- (2031-04-15, 2019-04-15) deliberately — those are the attacker's supplied
-- values, exactly as 21_manual_payment.sql's own financial-year fixture used
-- explicit literals for the value under attack while comparing against the
-- gym's own captured "today" for the correct one.
--
-- No assertion pins a mechanism as trigger, constraint or policy: every
-- throws_ok is null::char(5), null (any SQLSTATE) except the one place the
-- spec names a real one (the idempotency unique-index collision pattern is
-- not retested here — that is 21_manual_payment.sql's Section 6 — but where
-- this file's own Section 5 hits a partial UNIQUE-style rule it still
-- reports null::char(5), null, since no requirement here names a SQLSTATE).
--
-- Farming (Requirement 2, "paid is unreachable from anywhere it has already
-- been"): the spec's allowed-transition table lists no self-loop for any
-- status, so whether a same-value 'paid' → 'paid' UPDATE is itself refused
-- is genuinely unaddressed by the transition table's own wording — an
-- implementation could reasonably treat "no change" as not a transition at
-- all. Scoring that second step either way would be guessing at a rule the
-- spec does not state, so it is executed but not scored (a DO block
-- swallowing whatever it does), and the actual proof — the scenario's own
-- word for it — is the membership's extension count afterward, which the
-- spec pins exactly ("extended exactly once in total"). See the report for
-- this named as the one place a scenario's wording left a real choice.
--
-- Requirement 9's "genuinely open-ended" case (starts_on set, ends_on null)
-- is only reachable when status is 'pending' — memberships_dated_unless_
-- pending_chk (`CHECK (status = 'pending' OR (starts_on IS NOT NULL AND
-- ends_on IS NOT NULL))`, reasserted at assertion 72) permits null dates on
-- no other status. The fixture is staged that way honestly rather than
-- pretending an active open-ended membership was tested.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own nine tenants.
-- ADR-069: every scored assertion routes through a pgTAP function (ok /
--          lives_ok / throws_ok / results_eq / is); the one DO block in
--          Section 2 asserts nothing and is not counted by tapcount.py
--          (it does not begin with `select`).
--
-- PLAN COUNT: 72. Confirmed against Cloud via `supabase db query --linked -f`
-- through scratchpad/tapcount.py (begin…rollback, nothing committed — the
-- run completed and returned, itself confirming the rollback path executes).
-- `plan_line` is `1..72`, `ok_count` 24 + `not_ok_count` 48 = 72 matching the
-- plan exactly, `total_lines` 74 = the plan line + 72 assertions + finish()'s
-- one diagnostic comment row. node scripts/check-pgtap-rollback.mjs was run
-- against this file's own content in isolation (via its exported pure
-- `findNonRolledBackTests`, not the CLI entry point, which always scans
-- every tracked and untracked file under both supabase/tests/ AND
-- supabase/tests-holdout/ regardless of argv) and reports it clean. The
-- CLI entry point itself currently fails on a pre-existing holdout file,
-- supabase/tests-holdout/h22_payment_record_holdout.sql, not ending in
-- ROLLBACK — that file was not written by this session, was not opened by
-- it (the hard rule above forbids it), and is the holdout author's own
-- output for this same contract; it is unrelated to and unfixed by this
-- change, reported here only so it is not mistaken for something this file
-- broke.
--
-- RED (48) — the rule under test is not built, exactly as expected:
--   1-7, 11 (eight of the eleven frozen-field UPDATE attempts on a paid
--   payment succeed outright — amount_paise, currency, member_id,
--   membership_id, method, receipt_number, paid_at, idempotency_key are
--   all still writable after paid; only provider, provider_order_id and
--   provider_payment_id, 8-10, already refuse); 12 (the full-row snapshot
--   is therefore not unchanged); 15 (paid → created succeeds — the first
--   half of the farm); 16 (status reads back as created); 17 (the
--   membership was extended twice, 60 days on a 30-day plan, not once —
--   the farm buys exactly what the brief described); 20/21 (refunded →
--   paid revives the payment); 22/23 (created → refunded, not in the
--   allowed table, still succeeds); 24/25 (pending → created, backward,
--   still succeeds) — Requirement 2's transition table does not exist as
--   a check on UPDATE at all today, every transition is currently legal;
--   27/29 (a desk session's caller-supplied paid_at, two years off in
--   either direction, is stored verbatim rather than the instant of
--   recording — the exact defect named in the brief); 32/33 (next_number
--   can be walked backward); 34/35 (next_number can be jumped ahead by
--   more than one — 33 and 35's own "still 5" expectation reads the
--   cumulative drift from the previous refused-in-theory step, since nothing
--   refuses either one today: decrementing then jumping in the same section
--   lands the counter at 9, not 5, before assertion 36 ever adds its own
--   legitimate +1); 37 (consequently next_number reads 10, not 6, after the
--   legitimate increment — the same cascade, not a new defect: 33/35/37
--   together are one finding, not three); 40/41 (a refund raised past its
--   payment's ceiling on UPDATE succeeds — refunds_enforce_total is BEFORE
--   INSERT only per the catalogue, and nothing runs on UPDATE at all);
--   42/43 (a refund's amount_paise can also simply be decreased — the
--   freeze is not conditional on the ceiling, and neither exists yet);
--   44/45 (a refund's payment_id can be repointed to an unrelated payment);
--   46/47 (recording a refund AS 'failed' against an already-fully-refunded
--   payment dies on GL036 instead of being permitted — app.enforce_refund_
--   total's existing INSERT-time ceiling sums every refund regardless of
--   its own status, so a failed retry is refused by the very ceiling it is
--   supposed to be exempt from — this is PAY's failed-rows defect read
--   backward: excluding failed rows from the sum without excluding them
--   from the comparison was the bug that let a refund exceed the payment;
--   not excluding them from either is this one); 48/49 (a refund naming a
--   colleague as initiated_by_staff_id is recorded, not refused — the
--   attribution rule proven four times over for payments has no refunds
--   counterpart yet); 51 (a refund naming nobody is recorded with
--   initiated_by_staff_id left null, not auto-attributed to the acting
--   staff member); 52/53 (a claimless session's refund is recorded rather
--   than refused, landing a third row); 54/55 (a payment naming another
--   member's membership is recorded on INSERT, and that other member's
--   membership is extended by it — the exact defect the brief names);
--   56/57 (the same repoint succeeds on UPDATE too); 59 (a single 50%
--   payment already extends a 30-day membership by a full 30 days — "two
--   half payments bought two months" reproduced exactly, on the first
--   half alone); 61 (the second half adds a third full period on top,
--   landing at three periods' worth of date for two periods' worth of
--   money); 63 (a lone part payment, 30% of price, still grants a full
--   period); 65 (so does a payment against a zero-price membership — it
--   does not raise, per 64, but it still wrongly extends); 67 (a single
--   double payment grants only one period, not two — the current rule
--   grants exactly one period per paid payment regardless of amount, in
--   every direction: too generous below one multiple, not generous enough
--   above it); 69 (a membership with null starts_on/ends_on is left
--   completely untouched by a full payment — dated nowhere, given no
--   period).
--
-- GREEN (24), and each is said here because it is coverage the suite earns
-- rather than the rule proving itself:
--   8-10 (provider, provider_order_id and provider_payment_id already
--   refuse a change on a paid payment, unlike the other eight frozen
--   columns — a real, if partial, head start on Requirement 1); 13/14
--   (notes may still be corrected on a paid payment, exactly as required —
--   true today because nothing currently restricts UPDATE at all, and it
--   will stay true once the freeze rule exists, because notes is
--   deliberately outside it); 18/19 (failed → pending, the one legitimate
--   backward edge, already succeeds — also true by current absence of any
--   restriction, and correct either way); 26/28 (a desk session's INSERT
--   with a wildly off paid_at is not refused — the recording itself is
--   fine, only the stored value at 27/29 is wrong); 30/31 (a service_role
--   webhook write keeps its own supplied paid_at exactly — the trusted
--   writer half of Requirement 3 already works, asymmetric with the
--   RLS-bound half exactly as the requirement describes); 36 (incrementing
--   next_number by exactly one succeeds, as it always has); 38/39 (deleting
--   a document_counters row is already refused, and the row still exists
--   afterward — the one full Requirement 4 scenario that already holds);
--   50 (a refund naming nobody is not itself refused — only failing to
--   auto-attribute, at 51, is wrong); 58/60/62/64/66 (every payment in
--   Section 8 is recorded without being refused — Requirement 8 is entirely
--   about what the payment then does to the membership, not about whether
--   it is accepted, and none of these five is); 68/70 (a payment against a
--   no-dates membership, in either the null/null or the starts_on-only
--   shape, is recorded without raising); 71 (the starts_on-only, open-ended
--   membership is left completely untouched, which is what the requirement
--   asks for — reached here because the current rule appears to skip any
--   membership whose ends_on is already null outright, the same behaviour
--   that wrongly produces 69's failure for the null/null case; the two
--   assertions are one mechanism read from both sides, not two different
--   ones, and only one side happens to want what it does); 72
--   (memberships_dated_unless_pending_chk is exactly what the catalogue
--   showed before this file was written, and is what makes both of
--   Section 9's null-date fixtures reachable at all).

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(72);


-- ---------------------------------------------------------------------------
-- Fixtures shared by every section — organizations and branches only.
-- Everything else (staff, members, plans, memberships, payments, refunds)
-- is created inside the section that owns it, immediately before use.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000000001'::uuid, 'PayRec Gym 1', 'PYR221'),
  ('22000000-0000-4000-8000-000000000002'::uuid, 'PayRec Gym 2', 'PYR222'),
  ('22000000-0000-4000-8000-000000000003'::uuid, 'PayRec Gym 3', 'PYR223'),
  ('22000000-0000-4000-8000-000000000004'::uuid, 'PayRec Gym 4', 'PYR224'),
  ('22000000-0000-4000-8000-000000000005'::uuid, 'PayRec Gym 5', 'PYR225'),
  ('22000000-0000-4000-8000-000000000006'::uuid, 'PayRec Gym 6', 'PYR226'),
  ('22000000-0000-4000-8000-000000000007'::uuid, 'PayRec Gym 7', 'PYR227'),
  ('22000000-0000-4000-8000-000000000008'::uuid, 'PayRec Gym 8', 'PYR228'),
  ('22000000-0000-4000-8000-000000000009'::uuid, 'PayRec Gym 9', 'PYR229');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000000011'::uuid, '22000000-0000-4000-8000-000000000001'::uuid, 'G1 Main', true),
  ('22000000-0000-4000-8000-000000000012'::uuid, '22000000-0000-4000-8000-000000000002'::uuid, 'G2 Main', true),
  ('22000000-0000-4000-8000-000000000013'::uuid, '22000000-0000-4000-8000-000000000003'::uuid, 'G3 Main', true),
  ('22000000-0000-4000-8000-000000000014'::uuid, '22000000-0000-4000-8000-000000000004'::uuid, 'G4 Main', true),
  ('22000000-0000-4000-8000-000000000015'::uuid, '22000000-0000-4000-8000-000000000005'::uuid, 'G5 Main', true),
  ('22000000-0000-4000-8000-000000000016'::uuid, '22000000-0000-4000-8000-000000000006'::uuid, 'G6 Main', true),
  ('22000000-0000-4000-8000-000000000017'::uuid, '22000000-0000-4000-8000-000000000007'::uuid, 'G7 Main', true),
  ('22000000-0000-4000-8000-000000000018'::uuid, '22000000-0000-4000-8000-000000000008'::uuid, 'G8 Main', true),
  ('22000000-0000-4000-8000-000000000019'::uuid, '22000000-0000-4000-8000-000000000009'::uuid, 'G9 Main', true);


-- ===========================================================================
-- SECTION 1 (Requirement 1) — A payment that has been paid is a record, not
-- a working document. Tenant 1. Assertions 1-14.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000021'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
   '22000000-0000-4000-8000-000000000011'::uuid, 'front_desk', 'T1 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000040'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
   '22000000-0000-4000-8000-000000000011'::uuid, 'M1 Primary', '+912200000040'),
  ('22000000-0000-4000-8000-000000000041'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
   '22000000-0000-4000-8000-000000000011'::uuid, 'M1 Alt', '+912200000041');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000060'::uuid, '22000000-0000-4000-8000-000000000001'::uuid, 'G1 Plan (30d)', 30, 100000);

create temp table today_t1 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000001'::uuid;

-- 081 is the same member's OTHER membership, held 'expired' rather than
-- 'active' — memberships_tenant_id_member_id_live_key permits only one
-- active-or-frozen membership per member, and this section only needs a
-- second real membership row to repoint onto, not a second live one.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000080'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
   '22000000-0000-4000-8000-000000000040'::uuid, '22000000-0000-4000-8000-000000000060'::uuid,
   'active', (select d from today_t1) - 15, (select d from today_t1) + 15, 100000),
  ('22000000-0000-4000-8000-000000000081'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
   '22000000-0000-4000-8000-000000000040'::uuid, '22000000-0000-4000-8000-000000000060'::uuid,
   'expired', (select d from today_t1) - 60, (select d from today_t1) - 30, 100000);

-- The payment under attack. Inserted as postgres so its starting shape is
-- exactly what this section needs regardless of what INSERT-time stamping
-- does or does not do — that is 21_manual_payment.sql's and Section 3's
-- concern, not this one's. membership_id (081) is the repoint target and
-- deliberately belongs to the SAME member as the payment (040), so a
-- refusal there is attributable only to "membership_id is frozen," never
-- to Requirement 7's cross-member rule (that is Section 7, its own tenant).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method,
                              provider, provider_order_id, provider_payment_id, receipt_number,
                              recorded_by_staff_id, idempotency_key, paid_at, notes)
values ('22000000-0000-4000-8000-000000001001'::uuid, '22000000-0000-4000-8000-000000000001'::uuid,
        '22000000-0000-4000-8000-000000000040'::uuid, '22000000-0000-4000-8000-000000000080'::uuid,
        100000, 'INR', 'paid', 'cash', null, null, null, 'T1-RCT-0001',
        '22000000-0000-4000-8000-000000000021'::uuid, 'T1-IDEM-01',
        '2026-09-01 10:00:00+05:30'::timestamptz, 'original note');

create temp table p1_snapshot as
  select amount_paise, currency, member_id, membership_id, method, receipt_number, paid_at,
         provider, provider_order_id, provider_payment_id, idempotency_key
    from public.payments where id = '22000000-0000-4000-8000-000000001001'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 1
select throws_ok($$
  update public.payments set amount_paise = 999999
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'scenario "Editing the amount after payment" — amount_paise is refused once the payment has been paid');

-- 2
select throws_ok($$
  update public.payments set currency = 'USD'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'currency is refused once the payment has been paid');

-- 3
select throws_ok($$
  update public.payments set member_id = '22000000-0000-4000-8000-000000000041'::uuid
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'scenario "Moving a payment to another member" — member_id is refused once the payment has been paid');

-- 4
select throws_ok($$
  update public.payments set membership_id = '22000000-0000-4000-8000-000000000081'::uuid
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'membership_id is refused once the payment has been paid, even repointing to another membership of the same member');

-- 5
select throws_ok($$
  update public.payments set method = 'upi'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'method is refused once the payment has been paid');

-- 6
select throws_ok($$
  update public.payments set receipt_number = 'T1-RCT-9999'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'scenario "Choosing a receipt number by hand" — receipt_number is refused once the payment has been paid');

-- 7
select throws_ok($$
  update public.payments set paid_at = paid_at + interval '1 day'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'scenario "Backdating a receipted payment" — paid_at is refused once the payment has been paid');

-- 8
select throws_ok($$
  update public.payments set provider = 'razorpay'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'provider is refused once the payment has been paid');

-- 9
select throws_ok($$
  update public.payments set provider_order_id = 'order_forged'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'provider_order_id is refused once the payment has been paid');

-- 10 — provider is set alongside provider_payment_id in the same statement
-- so a refusal is attributable to the freeze rule and not incidentally to
-- payments_provider_reference_has_provider_chk (which would fire on
-- provider_payment_id alone, since this payment''s own provider is null).
select throws_ok($$
  update public.payments set provider_payment_id = 'T1-PAY-FORGED', provider = 'razorpay'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'provider_payment_id is refused once the payment has been paid');

-- 11
select throws_ok($$
  update public.payments set idempotency_key = 'T1-IDEM-99'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, null::char(5), null,
  'idempotency_key is refused once the payment has been paid');

set local role postgres;

-- 12 — the state proof for all eleven attempts above, in one comparison:
-- every frozen column is byte-for-byte what it was before any attack.
select results_eq(
  $$
    select (row(amount_paise, currency, member_id, membership_id, method, receipt_number, paid_at,
                provider, provider_order_id, provider_payment_id, idempotency_key))
           is not distinct from
           (select row(amount_paise, currency, member_id, membership_id, method, receipt_number, paid_at,
                       provider, provider_order_id, provider_payment_id, idempotency_key)
              from p1_snapshot)
      from public.payments where id = '22000000-0000-4000-8000-000000001001'::uuid
  $$,
  $$ values (true) $$,
  'none of the eleven frozen-field attempts landed — the row is exactly what it was'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 13
select lives_ok($$
  update public.payments set notes = 'corrected note'
   where id = '22000000-0000-4000-8000-000000001001'::uuid
$$, 'scenario "Correcting a note" — notes may be changed on a paid payment');

set local role postgres;

-- 14
select results_eq(
  $$ select notes from public.payments where id = '22000000-0000-4000-8000-000000001001'::uuid $$,
  $$ values ('corrected note'::text) $$,
  'the corrected note landed'
);


-- ===========================================================================
-- SECTION 2 (Requirement 2) — A payment's status moves only where it can
-- actually go. Tenant 2. Assertions 15-25.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000022'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000012'::uuid, 'front_desk', 'T2 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000042'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000012'::uuid, 'M2', '+912200000042');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000061'::uuid, '22000000-0000-4000-8000-000000000002'::uuid, 'G2 Plan (30d)', 30, 100000);

create temp table today_t2 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000002'::uuid;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000082'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, '22000000-0000-4000-8000-000000000061'::uuid,
   'active', (select d from today_t2) - 15, (select d from today_t2) + 15, 100000);

-- Five payments, one per transition case, each already sitting in the state
-- the scenario attacks from — inserted as postgres so the starting status is
-- exactly what each scenario needs.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000001002'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, '22000000-0000-4000-8000-000000000082'::uuid,
   100000, 'paid', 'cash', 'T2-RCT-0001', '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001003'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'failed', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001004'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'refunded', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001005'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'created', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001006'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'pending', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid);

-- Baseline: membership 082's ends_on right after payment 1002 landed as
-- 'paid' at insert time (one legitimate extension, if extension fires on
-- INSERT at all — Section 8 is where that arithmetic itself is measured).
create temp table mem082_after_one_payment as
  select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000082'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 15 — scenario "Farming the extension", first half.
select throws_ok($$
  update public.payments set status = 'created' where id = '22000000-0000-4000-8000-000000001002'::uuid
$$, null::char(5), null,
  'scenario "Farming the extension" — the first update (paid to created) is refused');

set local role postgres;

-- 16
select results_eq(
  $$ select status::text from public.payments where id = '22000000-0000-4000-8000-000000001002'::uuid $$,
  $$ values ('paid'::text) $$,
  'the payment is still paid after the refused first step'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- Second half of the farm, attempted regardless of what the first half did.
-- Not scored: the spec's transition table names no self-loop for any
-- status, so whether 'paid' -> 'paid' (if step 15 was correctly refused) or
-- 'created' -> 'paid' (if it was not) is itself refused is not something
-- this spec's wording pins down — scoring it would be guessing at a rule
-- nobody wrote. What the scenario actually promises is the next assertion.
do $$
begin
  update public.payments set status = 'paid' where id = '22000000-0000-4000-8000-000000001002'::uuid;
exception when others then null;
end;
$$;

set local role postgres;

-- 17 — the scenario's own proof, regardless of how the two attempts above
-- landed: the membership was extended exactly once in total.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000082'::uuid $$,
  $$ select ends_on from mem082_after_one_payment $$,
  'scenario "Farming the extension" — the membership was extended exactly once in total, however many times paid was walked'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 18 — scenario "A failed payment retried".
select lives_ok($$
  update public.payments set status = 'pending' where id = '22000000-0000-4000-8000-000000001003'::uuid
$$, 'scenario "A failed payment retried" — failed to pending succeeds, the one backward edge that is real');

set local role postgres;

-- 19
select results_eq(
  $$ select status::text from public.payments where id = '22000000-0000-4000-8000-000000001003'::uuid $$,
  $$ values ('pending'::text) $$,
  'the retried payment is now pending'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 20 — scenario "Reviving a refunded payment".
select throws_ok($$
  update public.payments set status = 'paid' where id = '22000000-0000-4000-8000-000000001004'::uuid
$$, null::char(5), null,
  'scenario "Reviving a refunded payment" — refunded to paid is refused');

set local role postgres;

-- 21
select results_eq(
  $$ select status::text from public.payments where id = '22000000-0000-4000-8000-000000001004'::uuid $$,
  $$ values ('refunded'::text) $$,
  'the payment is still refunded'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 22 — not in the allowed list at all: created may only go to pending, paid
-- or failed.
select throws_ok($$
  update public.payments set status = 'refunded' where id = '22000000-0000-4000-8000-000000001005'::uuid
$$, null::char(5), null,
  'created to refunded is not an allowed transition and is refused');

set local role postgres;

-- 23
select results_eq(
  $$ select status::text from public.payments where id = '22000000-0000-4000-8000-000000001005'::uuid $$,
  $$ values ('created'::text) $$,
  'the payment is still created'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 24 — pending may only go forward to paid or failed, never back to created.
select throws_ok($$
  update public.payments set status = 'created' where id = '22000000-0000-4000-8000-000000001006'::uuid
$$, null::char(5), null,
  'pending to created is not an allowed transition and is refused');

set local role postgres;

-- 25
select results_eq(
  $$ select status::text from public.payments where id = '22000000-0000-4000-8000-000000001006'::uuid $$,
  $$ values ('pending'::text) $$,
  'the payment is still pending'
);


-- ===========================================================================
-- SECTION 3 (Requirement 3) — The date a payment is filed under is the
-- system's to decide. Tenant 3. Assertions 26-31.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000023'::uuid, '22000000-0000-4000-8000-000000000003'::uuid,
   '22000000-0000-4000-8000-000000000013'::uuid, 'front_desk', 'T3 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000043'::uuid, '22000000-0000-4000-8000-000000000003'::uuid,
   '22000000-0000-4000-8000-000000000013'::uuid, 'M3', '+912200000043');

create temp table today_t3 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000003'::uuid;

-- receipt_number is supplied by hand in both authenticated fixtures below so
-- payments_paid_has_reference_chk and receipt allocation (a different rule,
-- proven in 21_manual_payment.sql) never enter into what this section
-- measures — the only thing under test is paid_at itself.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- 26 — scenario "Filing into another financial year", supplying a paid_at
-- two years in the future (financial year 2031-32).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id, receipt_number, paid_at)
  values ('22000000-0000-4000-8000-000000001007'::uuid,
          '22000000-0000-4000-8000-000000000003'::uuid,
          '22000000-0000-4000-8000-000000000043'::uuid,
          100000, 'cash', 'paid', '22000000-0000-4000-8000-000000000023'::uuid, 'T3-RCT-FUT',
          '2031-04-15 10:00:00+05:30'::timestamptz)
$$, 'a desk session recording a payment with a far-future paid_at is not refused');

set local role postgres;

-- 27
select results_eq(
  $$ select (paid_at at time zone 'Asia/Kolkata')::date = (select d from today_t3) from public.payments
      where id = '22000000-0000-4000-8000-000000001007'::uuid $$,
  $$ values (true) $$,
  'scenario "Filing into another financial year" — the payment is filed under the financial year of the instant it was actually recorded, not the caller-supplied 2031-04-15'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000003',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- 28 — the same scenario, backdated two years instead (financial year 2019-20).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status, recorded_by_staff_id, receipt_number, paid_at)
  values ('22000000-0000-4000-8000-000000001008'::uuid,
          '22000000-0000-4000-8000-000000000003'::uuid,
          '22000000-0000-4000-8000-000000000043'::uuid,
          100000, 'cash', 'paid', '22000000-0000-4000-8000-000000000023'::uuid, 'T3-RCT-PAST',
          '2019-04-15 10:00:00+05:30'::timestamptz)
$$, 'a desk session recording a payment with a far-past paid_at is not refused');

set local role postgres;

-- 29
select results_eq(
  $$ select (paid_at at time zone 'Asia/Kolkata')::date = (select d from today_t3) from public.payments
      where id = '22000000-0000-4000-8000-000000001008'::uuid $$,
  $$ values (true) $$,
  'the backdated payment is filed under the financial year of the instant it was actually recorded, not the caller-supplied 2019-04-15'
);

-- Trusted writer: service_role, no RLS, keeps its own paid_at (the Razorpay
-- webhook's own timestamp is the more truthful one). Claims are reset to
-- empty first so nothing bleeds over from the authenticated session above —
-- a real webhook call carries no request.jwt.claims at all.
select set_config('request.jwt.claims', '{}', true);
set local role service_role;

-- 30
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, method, status,
                                provider, provider_order_id, provider_payment_id, paid_at)
  values ('22000000-0000-4000-8000-000000001009'::uuid,
          '22000000-0000-4000-8000-000000000003'::uuid,
          '22000000-0000-4000-8000-000000000043'::uuid,
          100000, 'razorpay', 'paid',
          'razorpay', 'order_webhook_1', 'pay_webhook_1',
          '2026-09-01 12:00:00+05:30'::timestamptz)
$$, 'a service_role (webhook) write naming its own paid_at is not refused');

set local role postgres;

-- 31
select results_eq(
  $$ select paid_at from public.payments where id = '22000000-0000-4000-8000-000000001009'::uuid $$,
  $$ values ('2026-09-01 12:00:00+05:30'::timestamptz) $$,
  'a trusted writer''s own paid_at is kept exactly as supplied, unlike the RLS-bound sessions above'
);


-- ===========================================================================
-- SECTION 4 (Requirement 4) — The receipt counter only ever counts up, by
-- one. Tenant 4. Assertions 32-39.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000024'::uuid, '22000000-0000-4000-8000-000000000004'::uuid,
   '22000000-0000-4000-8000-000000000014'::uuid, 'front_desk', 'T4 Desk');

create temp table today_t4 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000004'::uuid;

-- financial_year derived from the gym's own captured today, never hardcoded
-- (1 April - 31 March, the same rule 21_manual_payment.sql derived by hand
-- and cross-checked against document_counters_financial_year_format_chk).
create temp table fy_t4 as
  select case when extract(month from d)::int >= 4
           then extract(year from d)::text || '-' || lpad(((extract(year from d)::int + 1) % 100)::text, 2, '0')
           else (extract(year from d)::int - 1)::text || '-' || lpad((extract(year from d)::int % 100)::text, 2, '0')
         end as fy
    from today_t4;

insert into public.document_counters (tenant_id, kind, financial_year, next_number)
values ('22000000-0000-4000-8000-000000000004'::uuid, 'receipt', (select fy from fy_t4), 5);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 32 — scenario "Resetting the counter".
select throws_ok($$
  update public.document_counters set next_number = next_number - 1
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, null::char(5), null,
  'scenario "Resetting the counter" — decreasing next_number is refused');

set local role postgres;

-- 33
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (5) $$,
  'next_number is still 5 after the refused decrease'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 34 — jumping ahead is not "an increase of exactly one" either, and hides
-- receipts as effectively as a reset does.
select throws_ok($$
  update public.document_counters set next_number = next_number + 5
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, null::char(5), null,
  'jumping next_number ahead by more than one is refused');

set local role postgres;

-- 35
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (5) $$,
  'next_number is still 5 after the refused jump'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 36 — scenario "Allocating a number".
select lives_ok($$
  update public.document_counters set next_number = next_number + 1
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, 'scenario "Allocating a number" — incrementing next_number by exactly one succeeds');

set local role postgres;

-- 37
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (6) $$,
  'next_number is now exactly 6'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 38
select throws_ok($$
  delete from public.document_counters
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, null::char(5), null,
  'deleting a counter row is refused');

set local role postgres;

-- 39 — existence only, not the exact next_number: that value is already
-- this section's own subject at 33/35/37, and tangling it into this
-- assertion too would blame a delete-refusal failure on an unrelated
-- earlier one, or credit it for cascading drift that has nothing to do
-- with DELETE.
select results_eq(
  $$ select count(*)::int from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (1) $$,
  'the counter row still exists after the refused delete'
);


-- ===========================================================================
-- SECTION 5 (Requirement 5) — A refund is bounded when it is written and
-- whenever it changes. Tenant 5. Assertions 40-47.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000025'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000015'::uuid, 'front_desk', 'T5 Desk'),
  ('22000000-0000-4000-8000-000000000026'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000015'::uuid, 'gym_manager', 'T5 Manager');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000044'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000015'::uuid, 'M5', '+912200000044');

-- Three payments (postgres fixtures, receipt numbers supplied by hand): 1010
-- (100000, the one under the ceiling test), 1011 (200000, an unrelated
-- payment used only as a repoint target), 1012 (50000, fully refunded
-- already, used for the failed-retry scenario).
insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000001010'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000044'::uuid, 100000, 'paid', 'cash', 'T5-RCT-0001', '22000000-0000-4000-8000-000000000025'::uuid),
  ('22000000-0000-4000-8000-000000001011'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000044'::uuid, 200000, 'paid', 'cash', 'T5-RCT-0002', '22000000-0000-4000-8000-000000000025'::uuid),
  ('22000000-0000-4000-8000-000000001012'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000000044'::uuid, 50000, 'paid', 'cash', 'T5-RCT-0003', '22000000-0000-4000-8000-000000000025'::uuid);

-- Two refunds already recorded against 1010 (40000 + 50000 = 90000, still
-- under its 100000 ceiling), and one refund already fully refunding 1012
-- (50000 = its own amount_paise) — all postgres fixtures, so the INSERT
-- path (already proven in 21_manual_payment.sql) tests nothing here.
insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('22000000-0000-4000-8000-000000002001'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000001010'::uuid, 'refund', 40000, 'requested', 'partial refund a', '22000000-0000-4000-8000-000000000026'::uuid),
  ('22000000-0000-4000-8000-000000002002'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000001010'::uuid, 'refund', 50000, 'requested', 'partial refund c', '22000000-0000-4000-8000-000000000026'::uuid),
  ('22000000-0000-4000-8000-000000002003'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
   '22000000-0000-4000-8000-000000001012'::uuid, 'refund', 50000, 'requested', 'full refund', '22000000-0000-4000-8000-000000000026'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000005',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000026')::text,
  true);
set local role authenticated;

-- 40 — scenario "Raising a refund past the payment": 2001 (40000) raised to
-- 70000 would bring the total against 1010 to 70000 + 50000 = 120000,
-- exceeding its 100000 amount_paise.
select throws_ok($$
  update public.refunds set amount_paise = 70000 where id = '22000000-0000-4000-8000-000000002001'::uuid
$$, null::char(5), null,
  'scenario "Raising a refund past the payment" — raising amount_paise so the total exceeds the payment is refused');

set local role postgres;

-- 41
select results_eq(
  $$
    select
      (select amount_paise from public.refunds where id = '22000000-0000-4000-8000-000000002001'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds where payment_id = '22000000-0000-4000-8000-000000001010'::uuid)
  $$,
  $$ values (40000::bigint, 90000::bigint) $$,
  'the raise did not land — refund 2001 is still 40000 and the total against payment 1010 is still 90000'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000005',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000026')::text,
  true);
set local role authenticated;

-- 42 — a decrease, well inside the ceiling. "SHALL refuse any change ...
-- once recorded" is unconditional, not only increases past the cap.
select throws_ok($$
  update public.refunds set amount_paise = 10000 where id = '22000000-0000-4000-8000-000000002001'::uuid
$$, null::char(5), null,
  'a refund''s amount_paise is refused even when the change is a decrease well inside the ceiling — it is recorded, not editable, once written');

set local role postgres;

-- 43
select results_eq(
  $$ select amount_paise from public.refunds where id = '22000000-0000-4000-8000-000000002001'::uuid $$,
  $$ values (40000::bigint) $$,
  'refund 2001 is still 40000 after the refused decrease'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000005',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000026')::text,
  true);
set local role authenticated;

-- 44
select throws_ok($$
  update public.refunds set payment_id = '22000000-0000-4000-8000-000000001011'::uuid
   where id = '22000000-0000-4000-8000-000000002001'::uuid
$$, null::char(5), null,
  'a refund''s payment_id is refused once recorded');

set local role postgres;

-- 45
select results_eq(
  $$ select payment_id from public.refunds where id = '22000000-0000-4000-8000-000000002001'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000001010'::uuid) $$,
  'refund 2001 still points at payment 1010 after the refused repoint'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000005',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000026')::text,
  true);
set local role authenticated;

-- 46 — scenario "Recording a failed retry against a fully refunded
-- payment": payment 1012 (50000) is already fully refunded by refund 2003
-- (50000). A new refund of 20000 against it, but recorded as itself
-- 'failed', must be permitted — a failed refund took nothing.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000002004'::uuid, '22000000-0000-4000-8000-000000000005'::uuid,
          '22000000-0000-4000-8000-000000001012'::uuid, 'refund', 20000, 'failed',
          'second attempt, failed to process', '22000000-0000-4000-8000-000000000026'::uuid)
$$, 'scenario "Recording a failed retry against a fully refunded payment" — permitted, since a failed refund took nothing');

set local role postgres;

-- 47
select results_eq(
  $$
    select
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000002004'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000001012'::uuid and status <> 'failed')
  $$,
  $$ values ('failed'::text, 50000::bigint) $$,
  'the failed retry landed at status failed, and the non-failed total against payment 1012 is still exactly its own amount_paise, unaffected'
);


-- ===========================================================================
-- SECTION 6 (Requirement 6) — Money leaving the gym names the person who
-- sent it. Tenant 6. Assertions 48-53.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000027'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
   '22000000-0000-4000-8000-000000000016'::uuid, 'front_desk', 'T6 Desk'),
  ('22000000-0000-4000-8000-000000000028'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
   '22000000-0000-4000-8000-000000000016'::uuid, 'gym_manager', 'T6 Manager'),
  ('22000000-0000-4000-8000-000000000029'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
   '22000000-0000-4000-8000-000000000016'::uuid, 'gym_manager', 'T6 Colleague');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000045'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
   '22000000-0000-4000-8000-000000000016'::uuid, 'M6', '+912200000045');

insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000001013'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
   '22000000-0000-4000-8000-000000000045'::uuid, 100000, 'paid', 'cash', 'T6-RCT-0001', '22000000-0000-4000-8000-000000000027'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000006',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000028')::text,
  true);
set local role authenticated;

-- 48 — scenario "A refund naming a colleague".
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000002005'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
          '22000000-0000-4000-8000-000000001013'::uuid, 'refund', 30000, 'attributed to a colleague',
          '22000000-0000-4000-8000-000000000029'::uuid)
$$, null::char(5), null,
  'scenario "A refund naming a colleague" — a manager cannot record a refund attributed to another staff member');

set local role postgres;

-- 49
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000001013'::uuid $$,
  $$ values (0) $$,
  'the misattributed refund left no row behind'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000006',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000028')::text,
  true);
set local role authenticated;

-- 50 — scenario "A refund naming nobody", session WITH a staff identity:
-- attributed to the acting staff member, not refused.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000002006'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
          '22000000-0000-4000-8000-000000001013'::uuid, 'refund', 30000, 'no attribution supplied', null)
$$, 'scenario "A refund naming nobody" — a session with a staff identity is not refused, and is attributed to itself');

set local role postgres;

-- 51
select results_eq(
  $$ select initiated_by_staff_id from public.refunds where id = '22000000-0000-4000-8000-000000002006'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000000028'::uuid) $$,
  'the refund landed, attributed to the acting staff member'
);

-- 52 — the other half of the same scenario: a session with no staff
-- identity at all is refused outright, whoever (or nobody) it names.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000006',
                    'app_role', 'gym_manager')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000002007'::uuid, '22000000-0000-4000-8000-000000000006'::uuid,
          '22000000-0000-4000-8000-000000001013'::uuid, 'refund', 20000, 'claimless session', null)
$$, null::char(5), null,
  'scenario "A refund naming nobody" — a session with no staff identity records no refund at all');

set local role postgres;

-- 53
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000001013'::uuid $$,
  $$ values (1) $$,
  'exactly one refund exists against payment 1013 — the one legitimate write (assertion 50), not the claimless attempt'
);


-- ===========================================================================
-- SECTION 7 (Requirement 7) — A payment extends only the membership of the
-- member who paid. Tenant 7. Assertions 54-57.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000030'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000017'::uuid, 'front_desk', 'T7 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000046'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000017'::uuid, 'M7a', '+912200000046'),
  ('22000000-0000-4000-8000-000000000047'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000017'::uuid, 'M7b', '+912200000047');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000062'::uuid, '22000000-0000-4000-8000-000000000007'::uuid, 'G7 Plan (30d)', 30, 100000);

create temp table today_t7 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000007'::uuid;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000083'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000046'::uuid, '22000000-0000-4000-8000-000000000062'::uuid,
   'active', (select d from today_t7) - 15, (select d from today_t7) + 15, 100000),
  ('22000000-0000-4000-8000-000000000084'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000047'::uuid, '22000000-0000-4000-8000-000000000062'::uuid,
   'active', (select d from today_t7) - 15, (select d from today_t7) + 15, 100000);

-- A legitimate payment for member 046 against its OWN membership (083),
-- left at status 'created' so the later UPDATE attempt is not itself
-- refused by Requirement 1's frozen-field rule (which only applies once
-- a payment has been paid).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000001015'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
   '22000000-0000-4000-8000-000000000046'::uuid, '22000000-0000-4000-8000-000000000083'::uuid,
   100000, 'created', 'cash', '22000000-0000-4000-8000-000000000030'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000007',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000030')::text,
  true);
set local role authenticated;

-- 54 — scenario "A payment naming another member's membership", on INSERT:
-- member 046's payment names membership 084, which belongs to member 047.
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001014'::uuid, '22000000-0000-4000-8000-000000000007'::uuid,
          '22000000-0000-4000-8000-000000000046'::uuid, '22000000-0000-4000-8000-000000000084'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000000030'::uuid, 'T7-RCT-CROSS')
$$, null::char(5), null,
  'scenario "A payment naming another member''s membership" — refused on insert');

set local role postgres;

-- 55 — the state proof: no payment landed for member 046 from this attempt,
-- and member 047's own membership was not extended by it.
select results_eq(
  $$
    select
      (select count(*)::int from public.payments where id = '22000000-0000-4000-8000-000000001014'::uuid),
      (select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000084'::uuid)
  $$,
  $$ select 0, (select d from today_t7) + 15 $$,
  'the cross-member insert left no payment row, and membership 084''s end date is exactly what it was'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000007',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000030')::text,
  true);
set local role authenticated;

-- 56 — the same rule, on UPDATE: payment 1015 (member 046's own, against
-- its own membership 083) is repointed to member 047's membership.
select throws_ok($$
  update public.payments set membership_id = '22000000-0000-4000-8000-000000000084'::uuid
   where id = '22000000-0000-4000-8000-000000001015'::uuid
$$, null::char(5), null,
  'the same rule on update — repointing an existing payment to another member''s membership is refused');

set local role postgres;

-- 57
select results_eq(
  $$ select membership_id from public.payments where id = '22000000-0000-4000-8000-000000001015'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000000083'::uuid) $$,
  'payment 1015 still names its own member''s membership after the refused repoint'
);


-- ===========================================================================
-- SECTION 8 (Requirement 8) — A period is granted when it has been paid
-- for, not when a payment arrives. Tenant 8. Assertions 58-67.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000031'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'front_desk', 'T8 Desk');

-- One member per membership below (not one member with four memberships):
-- memberships_tenant_id_member_id_live_key permits only one active-or-frozen
-- membership per member, and all four cases here need to be simultaneously
-- 'active'.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000048'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'M8a', '+912200000048'),
  ('22000000-0000-4000-8000-000000000148'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'M8b', '+912200000148'),
  ('22000000-0000-4000-8000-000000000248'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'M8c', '+912200000248'),
  ('22000000-0000-4000-8000-000000000348'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'M8d', '+912200000348');

-- The plan's own list price (120000) is deliberately different from every
-- membership's price_paise (100000) below, so a period granted at the
-- correct 100000 boundary (and not at 120000) is itself proof the rule
-- reads the membership's own price, never the plan's list price.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000063'::uuid, '22000000-0000-4000-8000-000000000008'::uuid, 'G8 Plan (30d, list 1200)', 30, 120000);

create temp table today_t8 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000008'::uuid;

-- Four independent memberships, one per boundary case, all starting at the
-- same ends_on so each case's expected arithmetic is a plain multiple of
-- the plan's 30-day duration from the same baseline.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000085'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000048'::uuid, '22000000-0000-4000-8000-000000000063'::uuid,
   'active', (select d from today_t8), (select d from today_t8) + 30, 100000),
  ('22000000-0000-4000-8000-000000000086'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000148'::uuid, '22000000-0000-4000-8000-000000000063'::uuid,
   'active', (select d from today_t8), (select d from today_t8) + 30, 100000),
  ('22000000-0000-4000-8000-000000000087'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000248'::uuid, '22000000-0000-4000-8000-000000000063'::uuid,
   'active', (select d from today_t8), (select d from today_t8) + 30, 0),
  ('22000000-0000-4000-8000-000000000088'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000348'::uuid, '22000000-0000-4000-8000-000000000063'::uuid,
   'active', (select d from today_t8), (select d from today_t8) + 30, 100000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 58 — membership 085, first half payment: total_after (50000) has not
-- reached one multiple of 100000. Below one multiple.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001016'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000048'::uuid, '22000000-0000-4000-8000-000000000085'::uuid,
          50000, 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0001')
$$, 'scenario "Two half payments" — the first half is recorded and not refused');

set local role postgres;

-- 59 — below one multiple: no period granted, end date untouched.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000085'::uuid $$,
  $$ select (select d from today_t8) + 30 $$,
  'below one multiple — the first half alone granted no period'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 60 — the second half: total_after (100000) reaches exactly one multiple.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001017'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000048'::uuid, '22000000-0000-4000-8000-000000000085'::uuid,
          50000, 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0002')
$$, 'scenario "Two half payments" — the second half is recorded and not refused');

set local role postgres;

-- 61 — exactly one multiple: exactly one period granted, on the second
-- payment. If the rule read the plan's 120000 list price instead of the
-- membership's own 100000, total_after (100000) would still be below one
-- multiple and this would fail.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000085'::uuid $$,
  $$ select (select d from today_t8) + 30 + 30 $$,
  'scenario "Two half payments" — exactly one period was granted, on the second, using the membership''s own price'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 62 — scenario "A part payment alone": membership 086 has taken no other
-- money at all, and this payment (30000) is below its 100000 price.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001018'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000148'::uuid, '22000000-0000-4000-8000-000000000086'::uuid,
          30000, 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0003')
$$, 'scenario "A part payment alone" — recorded and receipted, not refused');

set local role postgres;

-- 63
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000086'::uuid $$,
  $$ select (select d from today_t8) + 30 $$,
  'scenario "A part payment alone" — no period granted, the end date is untouched'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 64 — scenario "A membership with no price": membership 087's price_paise
-- is 0. THE SYSTEM SHALL record the payment and grant no period, rather
-- than raising (a naive floor(total/price) divides by zero here).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001019'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000248'::uuid, '22000000-0000-4000-8000-000000000087'::uuid,
          100, 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0004')
$$, 'scenario "A membership with no price" — recorded without raising');

set local role postgres;

-- 65
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000087'::uuid $$,
  $$ select (select d from today_t8) + 30 $$,
  'a zero-price membership grants no period, its end date untouched'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 66 — two multiples in a single payment (membership 088, price 100000,
-- amount 200000).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001020'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000348'::uuid, '22000000-0000-4000-8000-000000000088'::uuid,
          200000, 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0005')
$$, 'a double payment against a fresh membership is recorded, not refused');

set local role postgres;

-- 67 — two multiples: exactly two periods granted in one payment.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000088'::uuid $$,
  $$ select (select d from today_t8) + 30 + 60 $$,
  'two multiples in a single payment grant exactly two periods'
);


-- ===========================================================================
-- SECTION 9 (Requirement 9) — A payment against a membership with no dates
-- grants it a period. Tenant 9. Assertions 68-72.
-- ===========================================================================

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000032'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-000000000019'::uuid, 'front_desk', 'T9 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000049'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-000000000019'::uuid, 'M9a', '+912200000049'),
  ('22000000-0000-4000-8000-00000000004a'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-000000000019'::uuid, 'M9b', '+912200000050');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000064'::uuid, '22000000-0000-4000-8000-000000000009'::uuid, 'G9 Plan (30d)', 30, 100000);

create temp table today_t9 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000009'::uuid;

-- 089: sold but not yet paid for — status pending, both dates null. This is
-- the only shape memberships_dated_unless_pending_chk permits with either
-- date null (asserted directly at 72).
-- 08a: genuinely open-ended — status pending (required by the same CHECK,
-- since ends_on is null here too), starts_on already in the past, ends_on
-- null.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000089'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-000000000049'::uuid, '22000000-0000-4000-8000-000000000064'::uuid,
   'pending', null, null, 100000),
  ('22000000-0000-4000-8000-00000000008a'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-00000000004a'::uuid, '22000000-0000-4000-8000-000000000064'::uuid,
   'pending', (select d from today_t9) - 10, null, 100000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000009',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000032')::text,
  true);
set local role authenticated;

-- 68 — scenario "Paying for a membership that has no dates".
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001021'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
          '22000000-0000-4000-8000-000000000049'::uuid, '22000000-0000-4000-8000-000000000089'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000000032'::uuid, 'T9-RCT-0001')
$$, 'scenario "Paying for a membership that has no dates" — recorded, not refused');

set local role postgres;

-- 69
select results_eq(
  $$ select starts_on, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000089'::uuid $$,
  $$ select (select d from today_t9), (select d from today_t9) + 30 $$,
  'scenario "Paying for a membership that has no dates" — both dates are set from the gym''s own today, for the plan''s duration'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000009',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000032')::text,
  true);
set local role authenticated;

-- 70 — the open-ended half: a starts_on already set, ends_on null. Paying
-- for it should move nothing — "it has not ended, so there is nothing to
-- move."
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001022'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
          '22000000-0000-4000-8000-00000000004a'::uuid, '22000000-0000-4000-8000-00000000008a'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000000032'::uuid, 'T9-RCT-0002')
$$, 'paying for an open-ended membership (a starts_on, no ends_on) is not refused');

set local role postgres;

-- 71
select results_eq(
  $$ select starts_on, ends_on from public.memberships where id = '22000000-0000-4000-8000-00000000008a'::uuid $$,
  $$ select (select d from today_t9) - 10, null::date $$,
  'the open-ended membership''s dates are untouched — starts_on unchanged, ends_on still null'
);

-- 72 — the constraint that makes both null-date cases above reachable only
-- through a pending membership; a future migration relaxing it would
-- change what this requirement has to cope with.
select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'public.memberships'::regclass
      and conname = 'memberships_dated_unless_pending_chk'),
  $chk$CHECK (((status = 'pending'::membership_status) OR ((starts_on IS NOT NULL) AND (ends_on IS NOT NULL))))$chk$,
  'memberships_dated_unless_pending_chk still permits null dates on a pending membership only, and nowhere else'
);


select * from finish();
rollback;
