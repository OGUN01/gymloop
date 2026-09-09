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
-- Requirement 4 was revised after this file's first pass (the coordinator's
-- own correction): "forward only", not "by exactly one" — a decrease can
-- issue a receipt number twice, a forward jump only leaves a gap, and "a gap
-- in a receipt book is explainable, a reused number is not." Assertions
-- 34-37 below are written against that corrected wording.
--
-- A second critic round added one whole requirement ("A receipt number is
-- the counter's alone, at every status") and four paragraphs with their own
-- scenarios under "A period is granted…" and "A payment against a
-- membership with no dates…". Sections 10-13 (assertions 73-90) are that
-- extension; everything through 72 is unchanged from the first two passes.
--
-- The coordinator then caught this file's own arithmetic error in Section
-- 11: memberships 091/092 started at `ends_on = today + 30` (one period
-- already on them) while the expected result after ten more payments was
-- also asserted as `today + 30` — the value zero additional periods would
-- produce, not the value one correctly-granted period produces
-- (`greatest(today + 30, today) + 30 = today + 60`). As written, assertions
-- 80/82 could only ever pass by the extension rule doing nothing to these
-- two memberships, which is the opposite of what "ten rows totalling one
-- multiple grant exactly one period" means. Fixed per the coordinator's own
-- preference — 091/092/093 now start at `ends_on = today` (genuinely fresh,
-- nothing bought yet), so `today → today + 30` is one period with nothing
-- else in the arithmetic — rather than by inflating the expected value to
-- match the broken fixture. Assertions 83/84 (ten rows totalling TWO
-- multiples grant exactly two periods) are the coordinator's own addition,
-- on a third fresh membership (093): one multiple granting one period is
-- also what a rule granting exactly one period per statement regardless of
-- amount would produce, so it alone cannot tell "counts the money" apart
-- from "grants one per statement" — two multiples can, and does, since the
-- current defect (below) turns out to grant one period per ROW rather than
-- per multiple, which two multiples in ten rows exposes just as sharply.
--
-- PLAN COUNT: 90. Confirmed against Cloud via `supabase db query --linked -f`
-- through scratchpad/tapcount.py (begin…rollback, nothing committed — the
-- run completed and returned, itself confirming the rollback path executes).
-- `plan_line` is `1..90`, `ok_count` 82 + `not_ok_count` 8 = 90 matching the
-- plan exactly, `total_lines` 92 = the plan line + 90 assertions + finish()'s
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
-- Between this file's earlier passes and this one, migrations landed on
-- Cloud that fix nearly everything the first two rounds found (`supabase
-- migration list --linked` now shows 20260910120000 and 20260910130000
-- applied, neither opened). Assertions 1-72 are UNCHANGED from the previous
-- pass — every one of them still asserts exactly what it asserted before —
-- but almost all of them now read GREEN against the live implementation,
-- which is the suite doing its job on the earlier rounds' fixes, not a
-- rewrite.
--
-- RED (8) — the four new defects, each still live:
--   74/76 (the new requirement: a caller-supplied receipt_number is still
--   kept on a created payment, both on the INSERT that writes it and on a
--   direct hand-edit while it is still created — "at every status" is not
--   built yet, on either write shape); 80/82/84 (the multi-row defect,
--   reproduced on both statement shapes named in the brief AND on the
--   coordinator's two-multiples control: ten rows against a fresh
--   membership land at `today + 300` days regardless of whether their total
--   is one multiple of the price (80/82) or two (84) — the rule currently
--   grants one period per ROW in the statement, not one period per multiple
--   of money, which is a sharper diagnosis than "buys too much" alone would
--   have given); 88 (a paid payment whose currency differs from the
--   membership's still grants a period, because nothing compares the two);
--   89/90 (a dateless pending membership is dated but left pending, and its
--   member is consequently refused at a live QR check-in the same day — the
--   exact chain the brief names, proven through the check-in gate's own
--   already-built logic rather than asserted as a bare status value).
--
-- GREEN (82) — everything else: 1-73, 75, 77-79, 81, 83, 85-87. This is
-- every assertion from the first two passes (1-72) plus six of this round's
-- own new ones:
--   73/75/77/78 (the new requirement's write paths are none of them
--   refused outright — recording a forged number, hand-editing one, and the
--   gym's next paid payment are all accepted; only the STORED value, at
--   74/76, is wrong, and the next payment is in fact numbered normally at
--   78 — no collision, because nothing squatted a number in the first
--   place under the current, still-open bug); 79/81/83 (all three multi-row
--   statements are accepted, not refused — the defect is entirely in the
--   periods granted, at 80/82/84, never in whether the write lands); 85/86
--   (the control: app.enforce_refund_total() refuses two refunds in one
--   insert … select exactly as it would refuse one, and the whole
--   statement leaves no row behind — proving this section's multi-row
--   technique actually exercises the AFTER-trigger-sees-the-whole-statement
--   shape rather than passing vacuously, which is what makes 80/82/84's own
--   RED trustworthy rather than a testing artifact); 87 (a payment in
--   another currency is recorded, not refused — the defect is that it also
--   wrongly extends, at 88, not that it is rejected).
--
-- THIRD-SESSION EXTENSION — memberships.periods_granted itself (assertions
-- 91-112), added by a single author for BOTH this suite and its holdout
-- sibling. Three rounds of this contract's own arithmetic converged on this
-- column — it is what Requirement 8 says gets recorded — and
-- `grep -rln periods_granted supabase/tests supabase/tests-holdout`
-- returned nothing before this pass: every assertion through 90 above
-- proves the column's EFFECT (`ends_on`) and never reads the column
-- itself, and every fixture above that sets it at all leaves it at its
-- default 0, which ADR-088 names as the one state a real backfilled row
-- never has. ADR-088 records the defect this let ship: the one-time
-- backfill computed the column in `numeric` and Postgres ROUNDED the
-- assignment into the `integer` column, so a membership with money at
-- 0.9 of a period was backfilled to 1 instead of 0 — and worse, its next
-- full payment then granted NOTHING, because owed and granted were both
-- already 1. ₹12,000 for zero days, silently, on the one row in the demo
-- gym (Sneha Joshi's Annual) where the money and the price genuinely
-- differed by a discount.
--
-- Ordinarily two authors write the visible and holdout suites blind to
-- each other (ADR-060, hard rule 10); this gap is identical in both, so
-- one author closes it in both here, on the coordinator's explicit
-- instruction, keeping the two batteries genuinely different in what they
-- attack rather than transcribing one into the other. This suite's own
-- battery (tenant 14, fresh fixtures, `today_t14`) walks a single
-- membership through the exact truncating boundaries the ADR names
-- (0.9, 1.0, 1.999..., 2.0) one payment at a time and reads
-- `periods_granted` after each; starts a second membership already at
-- `periods_granted = 1` with matching money on record and proves the NEXT
-- payment reads that state rather than re-deriving it; asserts the
-- truncation relationship directly against the payments table (not just
-- against `ends_on`) across a part/full/double/refund-in-the-middle
-- sequence; proves currency, zero-price and below-a-multiple money all
-- leave the column untouched; and looks for the CHECK constraint the task
-- brief asserts exists.
--
-- LIVE DEFECT FOUND AND REPORTED, NOT PAPERED OVER (as first written): no
-- such CHECK constraint existed. `select conname, pg_get_constraintdef(oid)
-- from pg_constraint where conrelid = 'public.memberships'::regclass and
-- contype = 'c'` listed five CHECK constraints on the table and none
-- mentioned `periods_granted`; no trigger other than `touch_updated_at` sat
-- on `memberships` at all. A direct `update … set periods_granted = -1`,
-- run in a throwaway `begin…rollback` both as `postgres` and as an
-- authenticated `front_desk` session against its own tenant's row, landed
-- the -1 with nothing refusing it.
--
-- FOURTH-SESSION UPDATE: `check (periods_granted >= 0)` is now added, in a
-- migration not yet applied to Cloud (the coordinator named it and its
-- effect; it was not opened, per the hard rule against reading anything
-- dated 20260910000000 or later). 110/111 are unchanged and now pass once
-- that migration lands. 112 is INVERTED — see Section 14e's own header —
-- from proving the negative value landed to proving it did not, which is
-- the same "refused AND unmoved" discrimination this project has needed
-- before. Section 15 (GL043, assertions 113-119) closes the second live
-- defect this file found: a membership's price_paise and currency are now
-- frozen once periods_granted > 0, both directions, closing the price-cut
-- exploit 14a/14d's first version reported unscored.
--
-- PLAN COUNT: 119 (90 + 22 + 7). Confirmed against the spliced migration
-- (`python <scratchpad>/sweep.py 22_payment_record.sql out.sql
-- supabase/migrations/20260910210000_*.sql`, run via `supabase db query
-- --linked -f`, begin…rollback, nothing committed) the same way as above,
-- via tapcount.py. Assertions 91-119 are all GREEN against that splice.
-- Every one of 91-119 is RED against unmigrated live Cloud today, exactly
-- as this file's own earlier passes were RED against a migration not yet
-- merged (see the "RED (8)" note further up) — that is the plan working,
-- not a regression.
--
-- SEVENTH-ROUND EXTENSION — Section 16 (assertions 120-165), written by a
-- separate visible-suite author while a second author writes the holdout
-- battery for the same two requirements (GL043 widened to `plan_id`, and
-- GL044, the count itself). Neither read the other, and neither read an
-- implementation, because there is none: ADR-089 records what a blind critic
-- measured through the four doors round six left open. Section 16's own
-- header states the attack list and the two calls where the requirement left
-- a choice.
--
-- PLAN COUNT: 173 (119 + 54). Verified two ways against live Cloud, in one
-- run, begin…rollback, nothing committed: a scratchpad wrapper that inserts
-- every emitted TAP line into a temp table (so a single result set comes
-- back — `supabase db query` returns only the LAST result set with rows, and
-- that has produced false GREENs on this project before) counted 175 emitting
-- statements = plan + 173 assertions + finish(), and the run itself returned
-- exactly 175 lines with `1..173` first and no plan-mismatch diagnostic from
-- finish().
--
-- One assertion of Section 14b's is not new but its FIXTURE is: 14b used to
-- INSERT its membership at `periods_granted = 1`, which GL044 now refuses
-- ("a membership is created having been granted nothing"). It creates the
-- membership fresh and earns the period from a real payment instead.
-- Assertions 99/100 are untouched and green before and after — a fixture
-- repair, not a change to what is asserted. It was the only fixture in the
-- file inserting a non-zero count; every other membership here is created
-- at 0 or leaves the column to its default.
--
-- RED (27), all of them in Section 16 and every one of them dependent on a
-- rule that does not exist yet: 121/122/123/125 (plan_id is not frozen —
-- repointing at a longer and at a shorter plan both land, and the renewal
-- that follows is scored against whatever plan was left behind);
-- 130-135 (the same repoint through UPDATE … FROM, MERGE, a data-modifying
-- CTE, and a two-row statement carrying one frozen and one free membership —
-- all four land, and in the two-row case the innocent row moves too);
-- 137/138/140/141/142/143 (the count can be reset to 0, incremented from its
-- own value, and smuggled alongside a discount edit — and after the reset one
-- paisa buys a month); 145/146/148 (the count staged to 500, and the ordinary
-- ₹1,000 renewal that follows is then silently eaten — money receipted,
-- ends_on unmoved, nothing raised); 150-153 and 156/157 (the same three
-- statement shapes against the count, plus the hand-write by postgres
-- itself); and 166/167 (the fourth door — a membership CREATED carrying five
-- granted periods is written and stays written, ADR-089's third exploit with
-- no UPDATE anywhere in it).
--
-- GREEN (27) in Section 16, and they are not filler: 120/129/136/144/149 are
-- the fixture proofs (every membership that holds a period EARNED it from a
-- real payment); 124/127/128/126/154/155 and 158-165 are the permitted side —
-- an ordinary renewal, an ordinary edit that lands rather than being silently
-- dropped, a frozen column written its own value, a statement that changes
-- nothing, a price-and-plan correction before any money arrived and the
-- payment that is then scored against the CORRECTED terms, the tenant
-- boundary that still holds where the freeze stands aside, and the granting
-- rule's own multi-column write onto a dateless membership. 168-173 are the
-- same discipline on the insert door: a membership created the console's way
-- is granted its period and moves `ends_on` (the harm the refusal exists to
-- prevent, asserted as a consequence), an explicit `periods_granted = 0` in
-- an insert's column list stays ordinary — a rule refusing the column's
-- PRESENCE rather than a non-zero VALUE would take this whole suite down —
-- and the literal same-value write is allowed. They pass today and must
-- still pass afterwards: a fix that is too broad fails these and nothing
-- else in this file, and this project has shipped exactly that shape three
-- times this phase. Assertions 1-119 are unchanged and all green.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(173);


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

-- 34 — scenario "Staging a counter forward". The requirement is "forward
-- only", not "by exactly one": a decrease can issue a number twice (33's
-- own scenario), a forward jump only leaves a gap, and "a gap in a receipt
-- book is explainable, a reused number is not." The gap is the point, not
-- an oversight — a holdout elsewhere relies on exactly this to prove the
-- allocator does not read-before-write.
select lives_ok($$
  update public.document_counters set next_number = next_number + 5
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, 'scenario "Staging a counter forward" — jumping next_number ahead succeeds, leaving a gap rather than a reused number');

set local role postgres;

-- 35
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (10) $$,
  'next_number moved forward to exactly 10 (5 + 5) — the jump landed, gap and all'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 36 — scenario "Allocating a number", from wherever the counter has now
-- been left (10, not the original 5): this is the assertion that would
-- catch a rule which blocks hand-editing and the allocator alike, rather
-- than only the direction hand-editing may move in.
select lives_ok($$
  update public.document_counters set next_number = next_number + 1
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt'
$$, 'scenario "Allocating a number" — the allocator still advances the counter by exactly one, from wherever it was left');

set local role postgres;

-- 37
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'receipt' $$,
  $$ values (11) $$,
  'next_number is now exactly 11 (10 + 1) — the allocator''s own step is still exactly one'
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


-- ===========================================================================
-- SECTION 10 (new requirement: "A receipt number is the counter's alone, at
-- every status") — a second critic round, added after this file's first two
-- passes. Tenant 10. Assertions 73-78.
--
-- The forging session is `authenticated` throughout — "for every session row
-- security applies to" is the requirement's own scope, and postgres/
-- service_role are the trusted writers excluded from it (the same shape as
-- Requirement 3's paid_at rule). Both the INSERT and UPDATE paths are tested,
-- since the requirement's own wording ("at every status") does not stop at
-- the write that creates the row.
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000000010'::uuid, 'PayRec Gym 10', 'PYR22X');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000000020'::uuid, '22000000-0000-4000-8000-000000000010'::uuid, 'G10 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000033'::uuid, '22000000-0000-4000-8000-000000000010'::uuid,
   '22000000-0000-4000-8000-000000000020'::uuid, 'front_desk', 'T10 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000055'::uuid, '22000000-0000-4000-8000-000000000010'::uuid,
   '22000000-0000-4000-8000-000000000020'::uuid, 'M10 Forger', '+912200000055'),
  ('22000000-0000-4000-8000-000000000056'::uuid, '22000000-0000-4000-8000-000000000010'::uuid,
   '22000000-0000-4000-8000-000000000020'::uuid, 'M10 Legit', '+912200000056');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000010',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000033')::text,
  true);
set local role authenticated;

-- 73 — scenario "A number typed onto an unpaid payment": the row itself is
-- not refused (the forged number is simply not what the requirement is
-- about — recording the payment is fine).
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001023'::uuid, '22000000-0000-4000-8000-000000000010'::uuid,
          '22000000-0000-4000-8000-000000000055'::uuid, 100000, 'created', 'cash',
          '22000000-0000-4000-8000-000000000033'::uuid, '2026-27/999999')
$$, 'a created payment carrying a caller-supplied receipt_number is recorded, not refused');

set local role postgres;

-- 74
select results_eq(
  $$ select receipt_number is null from public.payments where id = '22000000-0000-4000-8000-000000001023'::uuid $$,
  $$ values (true) $$,
  'scenario "A number typed onto an unpaid payment" — the caller-supplied number is not kept on a created payment'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000010',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000033')::text,
  true);
set local role authenticated;

-- 75 — the same rule on UPDATE: the payment is still not paid (Requirement
-- 1's freeze does not yet apply), and a direct hand-edit is attempted.
select lives_ok($$
  update public.payments set receipt_number = '2026-27/888888'
   where id = '22000000-0000-4000-8000-000000001023'::uuid
$$, 'a direct hand-edit of receipt_number on a still-created payment is not refused as a write');

set local role postgres;

-- 76
select results_eq(
  $$ select receipt_number is null from public.payments where id = '22000000-0000-4000-8000-000000001023'::uuid $$,
  $$ values (true) $$,
  'the hand-edited number is not kept either — "at every status" before paid means every write, not only the first one'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000010',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000033')::text,
  true);
set local role authenticated;

-- 77 — the gym's next paid payment, an unrelated member, numbered normally:
-- the squatted number (had it been kept) is exactly what would have jammed
-- this write via payments_tenant_id_receipt_number_key.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000001024'::uuid, '22000000-0000-4000-8000-000000000010'::uuid,
          '22000000-0000-4000-8000-000000000056'::uuid, 100000, 'paid', 'cash',
          '22000000-0000-4000-8000-000000000033'::uuid)
$$, 'scenario "A number typed onto an unpaid payment" — the gym''s next paid payment is not refused');

set local role postgres;

-- 78
select results_eq(
  $$ select receipt_number is not null from public.payments where id = '22000000-0000-4000-8000-000000001024'::uuid $$,
  $$ values (true) $$,
  'the next paid payment is numbered normally — no collision, no jammed counter'
);


-- ===========================================================================
-- SECTION 11 (Requirement 8 extension: "The count is per PAYMENT, however
-- many arrive in one statement") — a second critic round. Tenant 11.
-- Assertions 79-86.
--
-- The two fixture-only inserts below (the ten 'created' rows ahead of the
-- multi-row UPDATE) run as postgres, each carrying its own receipt_number by
-- hand — a trusted writer is outside Section 10's rule by construction, so
-- this section's own arithmetic is not entangled with whether that rule is
-- built. The two statements actually under test — the INSERT … SELECT and
-- the multi-row UPDATE — run as authenticated, matching "through one
-- supabase-js call."
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000000011'::uuid, 'PayRec Gym 11', 'PYR22Y');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000000021'::uuid, '22000000-0000-4000-8000-000000000011'::uuid, 'G11 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000000034'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000021'::uuid, 'front_desk', 'T11 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000057'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000021'::uuid, 'M11a', '+912200000057'),
  ('22000000-0000-4000-8000-000000000058'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000021'::uuid, 'M11b', '+912200000058'),
  ('22000000-0000-4000-8000-000000000059'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000021'::uuid, 'M11c', '+912200000059'),
  ('22000000-0000-4000-8000-000000000062'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000021'::uuid, 'M11d', '+912200000062');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000000065'::uuid, '22000000-0000-4000-8000-000000000011'::uuid, 'G11 Plan (30d)', 30, 100000);

create temp table today_t11 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000000011'::uuid;

-- 091: the INSERT … SELECT target. 092: the multi-row UPDATE target. 093:
-- the two-multiples control, added after the coordinator caught this
-- section's own arithmetic bug — see below. All three price 100000
-- (₹1,000/30 days, the brief's own numbers). Genuinely fresh: ends_on =
-- today, nothing bought yet, so a granted period is visible as a plain
-- offset from today rather than hidden inside an already-paid-for period.
--
-- The coordinator caught this: this section originally started 091/092 at
-- ends_on = today + 30 (one period already on the membership from nothing)
-- while asserting the SAME today + 30 as the expected result after ten more
-- payments. That expected value is what zero additional periods granted
-- would produce — greatest(today + 30, today) + 30 = today + 60 is what one
-- correctly-granted period actually gives, so the assertion could only ever
-- pass by the rule doing nothing, never by the rule counting the money
-- right. Fixed by starting at zero rather than by inflating the expected
-- value, per the coordinator's own preference: "today → today + 30 shows
-- exactly one period being granted with nothing else in the arithmetic."
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000000091'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000057'::uuid, '22000000-0000-4000-8000-000000000065'::uuid,
   'active', (select d from today_t11), (select d from today_t11), 100000),
  ('22000000-0000-4000-8000-000000000092'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000058'::uuid, '22000000-0000-4000-8000-000000000065'::uuid,
   'active', (select d from today_t11), (select d from today_t11), 100000),
  ('22000000-0000-4000-8000-000000000093'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000062'::uuid, '22000000-0000-4000-8000-000000000065'::uuid,
   'active', (select d from today_t11), (select d from today_t11), 100000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000011',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000034')::text,
  true);
set local role authenticated;

-- 79 — scenario "Many payments in one statement", the INSERT … SELECT shape
-- named directly: ten rows of 10000 paise each (100000 total — exactly one
-- multiple of the membership's own 100000 price), one statement.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  select ('22000000-0000-4000-8000-000000103' || lpad(gs::text, 3, '0'))::uuid,
         '22000000-0000-4000-8000-000000000011'::uuid,
         '22000000-0000-4000-8000-000000000057'::uuid,
         '22000000-0000-4000-8000-000000000091'::uuid,
         10000, 'paid', 'cash', '22000000-0000-4000-8000-000000000034'::uuid,
         'T11-RCT-' || lpad(gs::text, 3, '0')
    from generate_series(1, 10) as gs
$$, 'scenario "Many payments in one statement" — ten payments in one insert … select are not refused');

set local role postgres;

-- 80 — the whole point: total money (100000) buys exactly one 30-day
-- period, not ten (300 days, the measured defect).
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000091'::uuid $$,
  $$ select (select d from today_t11) + 30 $$,
  'scenario "Many payments in one statement" — ten rows totalling one multiple of the price grant exactly one period, not ten'
);

-- Fixture only (postgres, trusted writer, outside Section 10's rule): ten
-- 'created' rows against membership 092, each already carrying its own
-- receipt_number so the later flip to 'paid' needs no allocation to satisfy
-- payments_paid_has_reference_chk — isolating this section's own UPDATE
-- assertion from receipt allocation entirely.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
select ('22000000-0000-4000-8000-000000104' || lpad(gs::text, 3, '0'))::uuid,
       '22000000-0000-4000-8000-000000000011'::uuid,
       '22000000-0000-4000-8000-000000000058'::uuid,
       '22000000-0000-4000-8000-000000000092'::uuid,
       10000, 'created', 'cash', '22000000-0000-4000-8000-000000000034'::uuid,
       'T11B-RCT-' || lpad(gs::text, 3, '0')
  from generate_series(1, 10) as gs;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000011',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000034')::text,
  true);
set local role authenticated;

-- 81 — the UPDATE equivalent named directly: one statement flips all ten
-- 'created' rows to 'paid' at once.
select lives_ok($$
  update public.payments set status = 'paid'
   where tenant_id = '22000000-0000-4000-8000-000000000011'::uuid
     and membership_id = '22000000-0000-4000-8000-000000000092'::uuid
     and status = 'created'
$$, 'scenario "Many payments in one statement" — the multi-row update equivalent is not refused');

set local role postgres;

-- 82
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000092'::uuid $$,
  $$ select (select d from today_t11) + 30 $$,
  'the multi-row update grants exactly one period too, not ten — the same rule, the other write shape'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000011',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000034')::text,
  true);
set local role authenticated;

-- 83 — the coordinator's own addition: one multiple granting one period is
-- also what a rule that ignores the count entirely (grants exactly one
-- period per statement, regardless of amount) would produce, so 79/80 and
-- 81/82 alone do not distinguish "counts the money" from "grants one per
-- statement". Ten rows totalling TWO multiples (20000 each, 200000 total
-- against the same 100000 price) does distinguish them.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  select ('22000000-0000-4000-8000-000000106' || lpad(gs::text, 3, '0'))::uuid,
         '22000000-0000-4000-8000-000000000011'::uuid,
         '22000000-0000-4000-8000-000000000062'::uuid,
         '22000000-0000-4000-8000-000000000093'::uuid,
         20000, 'paid', 'cash', '22000000-0000-4000-8000-000000000034'::uuid,
         'T11D-RCT-' || lpad(gs::text, 3, '0')
    from generate_series(1, 10) as gs
$$, 'ten rows totalling two multiples of the price, in one insert … select, are not refused');

set local role postgres;

-- 84 — exactly two periods, not one and not ten.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000093'::uuid $$,
  $$ select (select d from today_t11) + 60 $$,
  'ten rows totalling two multiples of the price grant exactly two periods'
);

-- A refunds fixture (postgres): one paid payment, no membership needed.
insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, recorded_by_staff_id, receipt_number) values
  ('22000000-0000-4000-8000-000000001040'::uuid, '22000000-0000-4000-8000-000000000011'::uuid,
   '22000000-0000-4000-8000-000000000059'::uuid, 100000, 'paid', 'cash',
   '22000000-0000-4000-8000-000000000034'::uuid, 'T11C-RCT-0001');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000011',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000000034')::text,
  true);
set local role authenticated;

-- 85 — the control: app.enforce_refund_total() is already correct under the
-- identical multi-row shape (two refunds of 60000 each, 120000 total,
-- against a 100000 payment, in one insert … select). This is what proves
-- the multi-row technique itself works — if the whole statement were
-- silently accepted, 79-84's own "not refused" results would say nothing
-- about whether this suite's technique can catch the defect at all.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
  select ('22000000-0000-4000-8000-000000205' || lpad(gs::text, 3, '0'))::uuid,
         '22000000-0000-4000-8000-000000000011'::uuid,
         '22000000-0000-4000-8000-000000001040'::uuid,
         'refund', 60000, 'multi-row control ' || gs,
         '22000000-0000-4000-8000-000000000034'::uuid
    from generate_series(1, 2) as gs
$$, null::char(5), null,
  'control: two refunds in one insert … select, together exceeding the payment, are refused exactly as a single one would be');

set local role postgres;

-- 86
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000001040'::uuid $$,
  $$ values (0) $$,
  'control: the whole multi-row insert left no refund rows behind — the existing ceiling is genuinely statement-safe, unlike the extension'
);


-- ===========================================================================
-- SECTION 12 (Requirement 8 extension: "The money must be the membership's
-- own currency") — a second critic round. Reuses tenant 8 (Requirement 8's
-- own tenant): the arithmetic this adds to is the same rule Section 8
-- already measures, and totals are scoped per membership_id, not per
-- tenant, so a fresh membership here pollutes nothing already asserted.
-- Assertions 87-88.
-- ===========================================================================

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000000060'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000018'::uuid, 'M8g', '+912200000060');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('22000000-0000-4000-8000-000000000090'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
   '22000000-0000-4000-8000-000000000060'::uuid, '22000000-0000-4000-8000-000000000063'::uuid,
   'active', (select d from today_t8), (select d from today_t8) + 30, 100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000008',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000031')::text,
  true);
set local role authenticated;

-- 87 — scenario "A payment in another currency": the amount (100000) exactly
-- matches the membership's own price, in a currency (USD) that is not its
-- own (INR). The console never sets currency; this is a direct write.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000001041'::uuid, '22000000-0000-4000-8000-000000000008'::uuid,
          '22000000-0000-4000-8000-000000000060'::uuid, '22000000-0000-4000-8000-000000000090'::uuid,
          100000, 'USD', 'paid', 'cash', '22000000-0000-4000-8000-000000000031'::uuid, 'T8-RCT-0006')
$$, 'a paid payment in a currency other than the membership''s own is recorded, not refused');

set local role postgres;

-- 88
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000090'::uuid $$,
  $$ select (select d from today_t8) + 30 $$,
  'scenario "A payment in another currency" — no period is granted, despite the amount exactly matching the price'
);


-- ===========================================================================
-- SECTION 13 (Requirement 9 extension: "it SHALL be made active at the same
-- time" and scenario "The member it was paid for") — a second critic round.
-- Reuses tenant 9 (Requirement 9's own tenant and its assertion 68's own
-- payment, 1021, against membership 089). Assertions 89-90.
-- ===========================================================================

-- 89 — the second half of the paragraph assertion 69 already covers the
-- first half of (dates set): the membership is also made active, not left
-- pending with real dates and a member the gate would still refuse.
select results_eq(
  $$ select status::text from public.memberships where id = '22000000-0000-4000-8000-000000000089'::uuid $$,
  $$ values ('active'::text) $$,
  'scenario "Paying for a membership that has no dates" — the membership becomes active, not merely dated'
);

-- A live QR session for tenant 9's own branch. Read from app.enforce_check_in
-- (not one of the four functions the brief names off-limits — this is a
-- different, already-built capability, consulted here only to pick a
-- fixture shape that actually exercises the gate under test): the
-- live-membership check (`status in (active, frozen)` AND today within
-- `[starts_on, ends_on]`) runs ONLY on the `qr_session_id IS NOT NULL`
-- branch. An assisted (`source = 'front_desk'`, no `qr_session_id`) check-in
-- skips that whole block today and would admit regardless of membership
-- state — a lives_ok there would pass for the wrong reason, the exact trap
-- 16_checkin.sql's own header warns against. The QR path is the one this
-- scenario actually needs.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('22000000-0000-4000-8000-000000000091'::uuid, '22000000-0000-4000-8000-000000000009'::uuid,
   '22000000-0000-4000-8000-000000000019'::uuid, 'pay22-t9-live',
   now() - interval '1 minute', now() + interval '1 hour', null);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000009',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000032')::text,
  true);
set local role authenticated;

-- 90 — scenario "The member it was paid for": the same member (049),
-- scanning a live QR session at their own gate the same day, is admitted —
-- the live-membership gate this exercises reads exactly the status and
-- dates assertions 69/87 already measured.
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000000009'::uuid,
          '22000000-0000-4000-8000-000000000019'::uuid,
          '22000000-0000-4000-8000-000000000049'::uuid, 'qr',
          '22000000-0000-4000-8000-000000000091'::uuid)
$$, 'scenario "The member it was paid for" — admitted the same day, since the membership that was just paid for is now active with today inside its dates');


-- ===========================================================================
-- SECTION 14 (Requirement 8, the column itself: memberships.periods_granted)
-- — a third-session extension, single author for both suites (see the
-- header). Tenant 14. Assertions 91-112.
-- ===========================================================================

-- Section 13 left the session as authenticated (its own last statement, the
-- QR check-in scan); this section's fixtures need postgres back first.
set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000140001'::uuid, 'PayRec Gym 14', 'PYR22E');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000140011'::uuid, '22000000-0000-4000-8000-000000140001'::uuid, 'G14 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000140021'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'front_desk', 'T14 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 Chain', '+912200140040'),
  ('22000000-0000-4000-8000-000000140041'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 AlreadyGranted', '+912200140041'),
  ('22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 Invariant', '+912200140042'),
  ('22000000-0000-4000-8000-000000140043'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 ZeroPrice', '+912200140043'),
  ('22000000-0000-4000-8000-000000140044'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 WrongCurrency', '+912200140044'),
  ('22000000-0000-4000-8000-000000140045'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 Negative', '+912200140045'),
  ('22000000-0000-4000-8000-000000140046'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'M14 PriceCorrection', '+912200140046');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000140060'::uuid, '22000000-0000-4000-8000-000000140001'::uuid, 'G14 Plan (30d)', 30, 100000);

create temp table today_t14 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000140001'::uuid;

-- Unlike the single-role sections above, this section's fixtures are
-- interleaved with role switches (postgres for setup, authenticated for the
-- scored write) within the same subsection, so today_t14 is read from both
-- — it needs an explicit grant, the same technique the holdout suite's own
-- gym_today temp table uses for the same reason.
grant select on today_t14 to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000140021')::text,
  true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 14a. Truncation, walked one payment at a time through the exact numbers
-- ADR-088 names: 90000 of 100000 (0.9 — the shipped-wrong case, which
-- rounded to 1 in the backfill's numeric arithmetic), 100000 (1),
-- 199999 (still 1), 200000 (2). Each step checks periods_granted AND
-- ends_on together, in one row, so the two can never silently disagree.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140080'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14), 100000, 0);

-- 91 — the shipped-wrong boundary: 90000 of 100000 is 0.9, and 0.9 must
-- floor to 0, not round to 1.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141001'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140080'::uuid,
          90000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0001')
$$, 'periods_granted/truncation: 90000 against a 100000 price is recorded');

-- 92
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (0, (select d from today_t14)) $$,
  'periods_granted/truncation: 90000 (0.9 of the price) grants ZERO periods, not one — this is the exact ratio ADR-088''s backfill rounded up'
);

-- 93 — +10000 = 100000 exactly, one whole multiple.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141002'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140080'::uuid,
          10000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0002')
$$, 'periods_granted/truncation: the top-up to exactly 100000 is recorded');

-- 94
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (1, (select d from today_t14) + 30) $$,
  'periods_granted/truncation: exactly 100000 grants exactly 1 period, and ends_on moves the matching 30 days'
);

-- 95 — +99999 = 199999, still short of the second multiple by one paisa.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141003'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140080'::uuid,
          99999, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0003')
$$, 'periods_granted/truncation: a further 99999 (total 199999) is recorded');

-- 96
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (1, (select d from today_t14) + 30) $$,
  'periods_granted/truncation: 199999 is still only 1 whole multiple of 100000 — one paisa short of a second period, and the column and ends_on both stay put'
);

-- 97 — the final paisa: total reaches 200000, the second multiple.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141004'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140080'::uuid,
          1, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0004')
$$, 'periods_granted/truncation: the final paisa (total 200000) is recorded');

-- 98
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (2, (select d from today_t14) + 60) $$,
  'periods_granted/truncation: 200000 grants exactly 2 periods total — the one paisa crossing the second multiple, nothing more'
);

-- ---------------------------------------------------------------------------
-- 14b. A membership whose column already reads non-zero — the state ADR-088
-- names as the one no other fixture in this suite creates, and the one a
-- real backfilled row (or a membership with payment history) always is.
-- The NEXT payment must read that state, not re-derive it from zero.
--
-- ROUND SEVEN: this fixture used to be INSERTed at `periods_granted = 1`
-- with the matching money added afterwards as decoration. GL044 now says a
-- membership is created having been granted nothing — a holdout author
-- measured a front-desk session creating one at `periods_granted = 5` and
-- then taking ₹1,000 for it, ADR-089's third exploit with no UPDATE in it —
-- so the count may not be typed at creation any more than it may be typed
-- afterwards. The membership is therefore created fresh (`ends_on = today`,
-- count 0) and EARNS its first period from the payment below, which is
-- what the old fixture only claimed had happened. Assertions 99/100 are
-- unchanged and green before and after: this is a fixture repair, not a
-- change to what is asserted.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140081'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140041'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14), 100000, 0);

-- The first payment, recorded as postgres — the history that puts this
-- membership at periods_granted = 1 and ends_on = today + 30. Not itself
-- scored: it is the fixture the scenario needs, not the payment under test.
set local role postgres;

insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
values ('22000000-0000-4000-8000-000000141010'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
        '22000000-0000-4000-8000-000000140041'::uuid, '22000000-0000-4000-8000-000000140081'::uuid,
        100000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0010');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000140021')::text,
  true);
set local role authenticated;

-- 99
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141011'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140041'::uuid, '22000000-0000-4000-8000-000000140081'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0011')
$$, 'periods_granted/already-non-zero: a second full payment, against a membership whose column already reads 1, is recorded');

-- 100
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140081'::uuid $$,
  $$ values (2, (select d from today_t14) + 60) $$,
  'periods_granted/already-non-zero: the column reads 2 (one more, not re-derived from zero) and ends_on moves by exactly one further period'
);

-- ---------------------------------------------------------------------------
-- 14c. The column asserted directly against the truth in the payments
-- table, not merely against its consequence — across a part payment, a
-- payment that crosses a multiple, a double payment, a refund landing in
-- the middle, and a further payment. periods_granted must equal
-- floor(total arrived in the membership's own currency / its own price)
-- at every step, computed the same truncating way the rule computes it
-- (an explicit ::bigint cast — sum() over bigint returns numeric, and
-- numeric/bigint does not truncate the way ADR-088 says the rule must).
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140082'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14), 100000, 0);

-- Part payment (40000 of 100000).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
values ('22000000-0000-4000-8000-000000141020'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
        '22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140082'::uuid,
        40000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0020');

-- 101
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid $$,
  $$ select (coalesce(sum(amount_paise) filter (where status in ('paid','refunded','reversed')), 0)::bigint
             / (select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid))::int
      from public.payments where membership_id = '22000000-0000-4000-8000-000000140082'::uuid
        and currency = (select currency from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid) $$,
  'periods_granted/invariant: after a 40000 part payment, the column matches floor(arrived / price) computed straight from the payments table'
);

-- Second part payment, crossing the first multiple (total 100000).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
values ('22000000-0000-4000-8000-000000141021'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
        '22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140082'::uuid,
        60000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0021');

-- 102
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid $$,
  $$ select (coalesce(sum(amount_paise) filter (where status in ('paid','refunded','reversed')), 0)::bigint
             / (select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid))::int
      from public.payments where membership_id = '22000000-0000-4000-8000-000000140082'::uuid
        and currency = (select currency from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid) $$,
  'periods_granted/invariant: after the second half crosses 100000, the column still matches the same live formula'
);

-- A double payment (250000), crossing two more multiples (total 350000).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
values ('22000000-0000-4000-8000-000000141022'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
        '22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140082'::uuid,
        250000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0022');

-- 103
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid $$,
  $$ select (coalesce(sum(amount_paise) filter (where status in ('paid','refunded','reversed')), 0)::bigint
             / (select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid))::int
      from public.payments where membership_id = '22000000-0000-4000-8000-000000140082'::uuid
        and currency = (select currency from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid) $$,
  'periods_granted/invariant: after a 250000 double payment (total 350000), the column still matches the live formula, now at 3'
);

-- A refund against the double payment, in the middle of the sequence — not
-- itself scored, it is this checkpoint's fixture. THE TOTAL MUST NOT FALL:
-- a refund does not reverse the extension it bought (Requirement 8's own
-- text), so the next assertion checks the column did not drop.
set local role postgres;

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('22000000-0000-4000-8000-000000142001'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000141022'::uuid, 'refund', 50000, 'requested',
   'periods_granted invariant probe: a refund landing mid-sequence', '22000000-0000-4000-8000-000000140021'::uuid);

-- 104
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid $$,
  $$ select (coalesce(sum(amount_paise) filter (where status in ('paid','refunded','reversed')), 0)::bigint
             / (select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid))::int
      from public.payments where membership_id = '22000000-0000-4000-8000-000000140082'::uuid
        and currency = (select currency from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid) $$,
  'periods_granted/invariant: a refund recorded against one of the payments does not change the payments table''s own arrived total, so the column is still exactly the live formula — it did not fall'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000140021')::text,
  true);
set local role authenticated;

-- One more payment (50000), crossing a fourth multiple (total 400000).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
values ('22000000-0000-4000-8000-000000141023'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
        '22000000-0000-4000-8000-000000140042'::uuid, '22000000-0000-4000-8000-000000140082'::uuid,
        50000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0023');

-- 105
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid $$,
  $$ select (coalesce(sum(amount_paise) filter (where status in ('paid','refunded','reversed')), 0)::bigint
             / (select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid))::int
      from public.payments where membership_id = '22000000-0000-4000-8000-000000140082'::uuid
        and currency = (select currency from public.memberships where id = '22000000-0000-4000-8000-000000140082'::uuid) $$,
  'periods_granted/invariant: after the whole part/full/double/refund/final sequence, the column and the live formula still agree exactly'
);

-- ---------------------------------------------------------------------------
-- 14d. Money that grants nothing leaves the column alone: zero price and
-- the wrong currency (the part-payment-below-a-multiple case is 91/92
-- above).
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140083'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140043'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14) + 30, 0, 0);

-- 106
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141030'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140043'::uuid, '22000000-0000-4000-8000-000000140083'::uuid,
          100, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0030')
$$, 'periods_granted/leaves-alone: a payment against a zero-price membership does not raise');

-- 107
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140083'::uuid $$,
  $$ values (0, (select d from today_t14) + 30) $$,
  'periods_granted/leaves-alone: a zero-price membership stays at 0 — a multiple of zero is not a meaningful threshold'
);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency, periods_granted) values
  ('22000000-0000-4000-8000-000000140084'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140044'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14) + 30, 100000, 'INR', 0);

-- 108
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141031'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140044'::uuid, '22000000-0000-4000-8000-000000140084'::uuid,
          100000, 'USD', 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0031')
$$, 'periods_granted/leaves-alone: a payment matching the price exactly, but in the wrong currency, is recorded');

-- 109
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140084'::uuid $$,
  $$ values (0, (select d from today_t14) + 30) $$,
  'periods_granted/leaves-alone: money in a currency the membership is not priced in stays at 0, despite matching the price exactly'
);

-- ---------------------------------------------------------------------------
-- 14e. periods_granted may not be negative — the task brief's own
-- expectation, checked against the live schema rather than assumed.
-- FOURTH-SESSION UPDATE: the CHECK constraint this section found missing
-- (`check (periods_granted >= 0)`) is now added, in a migration not yet on
-- Cloud (dated 20260910000000 or later — not opened, per the hard rule; the
-- coordinator named it and its effect only). 110/111 below now PASS once
-- that migration lands; 112 is INVERTED from its first version, which
-- proved the negative value landed (the live defect at the time). It now
-- proves the opposite the same way: refused AND unmoved, not merely
-- refused — the discrimination this project has been bitten by before
-- (a rule that throws but still half-writes, or clamps instead of
-- rejecting, would still fail 112 even though it passes 111).
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140085'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140045'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14) + 30, 100000, 0);

-- 110
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.memberships'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%periods_granted%'),
  1,
  'periods_granted/negative: a CHECK constraint on periods_granted >= 0 exists on public.memberships'
);

-- 111
select throws_ok($$
  update public.memberships set periods_granted = -1
   where id = '22000000-0000-4000-8000-000000140085'::uuid
$$, null::char(5), null,
  'periods_granted/negative: a direct write driving the column negative, from an authenticated front_desk session against its own tenant''s row, is refused');

set local role postgres;

-- 112 — inverted from the first version (see the section header): refused
-- AND unmoved, still at its pre-attack value of 0.
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000140085'::uuid $$,
  $$ values (0) $$,
  'periods_granted/negative: the column is unchanged at 0 after the refused update — refused AND unmoved, not merely refused'
);

-- ===========================================================================
-- SECTION 15 (GL043) — a membership's price_paise and currency are frozen
-- once periods_granted > 0. This closes the price-cut defect Section 14
-- (14a/d, first version) found and reported unscored: cutting the price
-- after a period was already bought at the old one let a single trivial
-- payment retroactively unlock a period nobody paid for at the new price.
-- The fix is symmetric (both directions frozen, not only the exploitable
-- one) and scoped to AFTER a grant — correcting a mistyped price before any
-- money has arrived is still an ordinary edit. Tenant 14, reusing its own
-- fixtures. Assertions 113-119, in a migration not yet on Cloud (see the
-- section 14e note above) — RED against live Cloud until it lands, GREEN
-- against the splice the coordinator named.
-- ===========================================================================

-- Reuses membership 140080 (Section 14a's own truncation chain), which now
-- sits at periods_granted = 2, price_paise = 100000, currency = INR — a
-- membership with real, earned history, not a hand-set fixture.

-- 113 — cutting the price after a period was granted.
select throws_ok($$
  update public.memberships set price_paise = 50000
   where id = '22000000-0000-4000-8000-000000140080'::uuid
$$, null::char(5), null,
  'GL043: cutting price_paise on a membership that already has periods_granted > 0 is refused');

-- 114 — raising it is refused too. The report on the first version of this
-- section called the raise direction "safe" — true of the arithmetic
-- (nothing decreased), not of the principle GL043 states: the price is
-- frozen once earned, in EITHER direction, not merely the direction that
-- was exploitable.
select throws_ok($$
  update public.memberships set price_paise = 200000
   where id = '22000000-0000-4000-8000-000000140080'::uuid
$$, null::char(5), null,
  'GL043: raising price_paise on the same membership is refused just as the cut was — the rule is symmetric, not only the exploitable half');

-- 115 — the state proof for both attempts: price_paise and currency are
-- exactly what they were before either was tried.
select results_eq(
  $$ select price_paise, currency from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (100000::bigint, 'INR'::text) $$,
  'GL043: neither the cut nor the raise landed — price_paise and currency are unchanged'
);

-- 116/117 — the freeze must not catch app.grant_periods()'s own writes: a
-- further real payment against this same membership (periods_granted
-- already 2, price_paise untouched by the two refused attempts above)
-- still grants normally. A rule that blocked the function maintaining
-- periods_granted/ends_on/status/activated_at while enforcing the freeze
-- on price/currency would be the shape ADR-085/ADR-086 already caught this
-- project doing twice this phase — a fix to one column's rule breaking an
-- unrelated column's own writer.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000141005'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
          '22000000-0000-4000-8000-000000140040'::uuid, '22000000-0000-4000-8000-000000140080'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000140021'::uuid, 'T14-RCT-0005')
$$, 'GL043: a genuine further payment, right after the two refused price edits, is not caught by the freeze');

select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000140080'::uuid $$,
  $$ values (3, (select d from today_t14) + 90) $$,
  'GL043: the trigger''s own maintenance columns still moved normally — a third period, at the still-unfrozen price of 100000'
);

-- 118/119 — changing the price while periods_granted = 0 still succeeds:
-- correcting a mistyped price before any money has arrived is an ordinary
-- edit, and a rule that forbade it would be wrong in the other direction.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140086'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140046'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14) + 30, 100000, 0);

select lives_ok($$
  update public.memberships set price_paise = 75000
   where id = '22000000-0000-4000-8000-000000140086'::uuid
$$, 'GL043: correcting price_paise on a membership with periods_granted = 0 (no money has arrived yet) succeeds');

select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000140086'::uuid $$,
  $$ values (75000::bigint) $$,
  'GL043: the correction landed — the freeze only starts once a period has actually been earned'
);


-- ===========================================================================
-- SECTION 16 (GL043 widened, and GL044) — the terms a period was scored
-- against, and the count it was scored into. Tenant 16. Assertions 120-165.
--
-- Round seven. ADR-089 records what a blind critic measured against round
-- six's freeze: it froze `price_paise` and `currency` and left the other two
-- doors open. `plan_id` is the third term — a period lasts the duration of
-- the membership's own plan, so repointing a 30-day membership at a 365-day
-- one and paying ₹1,000 moved `ends_on` 395 days, strictly easier than the
-- price cut the round was written to close. And the freeze is GATED on
-- `periods_granted`, which the very session it constrains can rewrite:
-- `set periods_granted = 0` then one paisa bought a month, and
-- `set periods_granted = 500` made an ordinary ₹1,000 payment buy nothing at
-- all, silently, which is ADR-088's own named harm reached by hand.
--
-- Written from openspec/changes/phase-5-money/specs/payment-record/spec.md's
-- two requirements "The terms a period was scored against do not change
-- after it is granted" (GL043) and "How many periods have been granted is
-- written by the rule and by nobody else" (GL044), plus ADR-089, by a
-- session that has read neither an implementation of them (none exists) nor
-- supabase/tests-holdout/, which a second author is writing against the same
-- two requirements at the same time. The catalogue was read (pg_trigger,
-- pg_constraint, pg_policies, information_schema — via `supabase db query
-- --linked`, wrapped begin…rollback, nothing committed) and no function
-- body was.
--
-- THE SQLSTATES ARE ASSERTED, NOT LEFT OPEN. Everywhere else in this file a
-- refusal is `null::char(5)` because the spec named no code. Here the codes
-- are the requirement ids themselves — this project raises `GL0xx` as the
-- SQLSTATE (GL010, GL016, GL030, GL034, GL036, GL037 …), and the live
-- price freeze already answers a price cut with exactly `GL043`, observed
-- black-box in a throwaway begin…rollback. So `plan_id` joining the same
-- requirement answers `GL043`, and the count rule answers `GL044`. Every
-- refusal below asserts the code AND that the value did not move: this
-- codebase has shipped a refusal that half-wrote, and "refused" alone would
-- not have caught it.
--
-- WHAT IS ATTACKED, AND WHY IT GOES BEYOND ADR-089's FOUR SHAPES. The four
-- measured shapes are here (price cut then one paisa is Section 15's
-- already; the count reset then one paisa is 137-140; the count raised to
-- 500 eating a real payment is 145-148; the plan repointed at a longer plan
-- is 121-125). Past them, every statement shape a rule written as a naive
-- single-row `update` guard can be walked around: `UPDATE … FROM`, `MERGE`,
-- and a data-modifying CTE, against BOTH frozen things (130-132, 150-152).
-- All six of those are ALLOWED on live Cloud today, measured. Then the
-- shapes that catch a fix which is too BROAD rather than too narrow — the
-- direction this project has shipped wrong three times: setting a frozen
-- column to the value it already holds (126, 154), a statement that changes
-- nothing at all (155), an ordinary edit to a column that is not a term
-- (127/128), a legitimate write that happens to carry the frozen column
-- alongside an innocent one (142/143 — the innocent column must not move
-- either), and, above all, the rule's OWN writes: an ordinary renewal
-- (124/125, 147/148), and the multi-column write that dates, activates and
-- counts a membership that had no dates at all (164/165). A rule that
-- refuses everything passes every refusal test in this file.
--
-- Two further shapes nobody had tried. 134/135: one statement updating two
-- memberships where only ONE is frozen — the whole statement must be
-- refused and NEITHER row may move, which is what a rule that checks the
-- rows it happens to look at first would fail. 156/157: the hand-write done
-- by `postgres` itself, the most privileged writer there is — "written by
-- the rule and by nobody else" says nobody, and the live price freeze
-- already refuses `postgres`, so a count rule that only refuses
-- `authenticated` would be a narrower rule than the one it sits beside.
--
-- 162/163 answer a question the brief asked rather than assumed: does
-- anything stop `plan_id` being repointed at a plan in ANOTHER TENANT? It
-- does, and not by anything in this requirement — ADR-052's composite key
-- `memberships_plan_id_fkey FOREIGN KEY (tenant_id, plan_id) REFERENCES
-- plans(tenant_id, id)` refuses it with `23503`. It is asserted on a
-- membership that has been granted NOTHING, i.e. on the path GL043 must
-- leave open, so it proves the tenant boundary still holds exactly where
-- the freeze stands aside. Labelled a control: it is green today.
--
-- THE INSERT DOOR, RAISED AS A QUESTION AND THEN DECIDED. As first written
-- this section asserted GL044 against UPDATE only and said so here: both its
-- scenarios were update-shaped, ADR-089's measurements were all `update
-- memberships`, and Section 14b of this very file seeded a membership at
-- `periods_granted = 1` by INSERT, so asserting the insert case would have
-- put this section in conflict with its own suite over a question the
-- requirement did not answer. It answers it now — a holdout author measured
-- the door: create a membership carrying `periods_granted = 5`, take
-- ₹1,000, and `ends_on` does not move while the receipt is issued, which is
-- 16d's exploit with no UPDATE in it. The requirement grew "A membership is
-- created having been granted nothing", 16g (166-173) asserts it, and
-- Section 14b's fixture has been repaired to EARN its period rather than
-- declare one — the conflict resolved in the direction the measurement
-- pointed. This section's own fixtures never depended on the answer: every
-- membership below that holds a period earned it from a real payment.
--
-- Also not re-proved here: that a refund does not pull the count back down
-- (Requirement 8's "the total counts money that ARRIVED"). That is
-- assertion 104's job, one section up, and a refund touches no column
-- either of these two requirements freezes.
--
-- MEASURED ON LIVE CLOUD BEFORE WRITING A LINE, in a throwaway
-- begin…rollback: plan repoint ALLOWED; `set periods_granted = 0` ALLOWED;
-- `= 500` ALLOWED, and the ₹1,000 payment that followed left `ends_on`
-- exactly where it was with the money receipted; `UPDATE … FROM`, `MERGE`
-- and the data-modifying CTE all ALLOWED on both columns; the two-row
-- statement ALLOWED; and `set price_paise = <its current value>` ALLOWED,
-- which is the round-six freeze already using `is distinct from` correctly
-- and the behaviour 126/154 hold the new rules to.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000160001'::uuid, 'PayRec Gym 16', 'PYR22F'),
  ('22000000-0000-4000-8000-000000160002'::uuid, 'PayRec Gym 16B', 'PYR22G');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000160011'::uuid, '22000000-0000-4000-8000-000000160001'::uuid, 'G16 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000160021'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'front_desk', 'T16 Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000160040'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 PlanFreeze', '+912200160040'),
  ('22000000-0000-4000-8000-000000160041'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 PlanShapes', '+912200160041'),
  ('22000000-0000-4000-8000-000000160042'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CountReset', '+912200160042'),
  ('22000000-0000-4000-8000-000000160043'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CountRaise', '+912200160043'),
  ('22000000-0000-4000-8000-000000160044'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 Correction', '+912200160044'),
  ('22000000-0000-4000-8000-000000160045'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 Sibling', '+912200160045'),
  ('22000000-0000-4000-8000-000000160046'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 Dateless', '+912200160046'),
  ('22000000-0000-4000-8000-000000160047'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CountShapes', '+912200160047'),
  ('22000000-0000-4000-8000-000000160048'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CreatedNormally', '+912200160048'),
  ('22000000-0000-4000-8000-000000160049'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CreatedAtZero', '+912200160049'),
  ('22000000-0000-4000-8000-000000160050'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'M16 CreatedWithCount', '+912200160050');

-- Three plans of three different lengths in tenant 16, and one in tenant 16B
-- that tenant 16 may not point at (162). All priced identically, so nothing
-- below can pass by the PRICE differing — only the DURATION does.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000160060'::uuid, '22000000-0000-4000-8000-000000160001'::uuid, 'G16 Plan (30d)', 30, 100000),
  ('22000000-0000-4000-8000-000000160061'::uuid, '22000000-0000-4000-8000-000000160001'::uuid, 'G16 Plan (365d)', 365, 100000),
  ('22000000-0000-4000-8000-000000160062'::uuid, '22000000-0000-4000-8000-000000160001'::uuid, 'G16 Plan (7d)', 7, 100000),
  ('22000000-0000-4000-8000-000000160063'::uuid, '22000000-0000-4000-8000-000000160002'::uuid, 'G16B Plan (365d)', 365, 100000);

create temp table today_t16 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000160001'::uuid;

-- Read from both roles (fixtures as postgres, scored writes as the front
-- desk), so it needs the same explicit grant today_t14 takes.
grant select on today_t16 to public;

-- Six memberships, all on the 30-day plan, all priced 100000, all starting
-- at `ends_on = today` so that "one period" is `today + 30` with nothing
-- else in the arithmetic (Section 14a's own correction, kept). None is
-- seeded with a non-zero periods_granted: the four that need a period EARN
-- it below, from a real payment, so this section is independent of whether
-- an INSERT may carry the column at all.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000160080'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160040'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160081'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160041'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160082'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160042'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160083'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160043'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160084'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160044'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160085'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160045'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0),
  ('22000000-0000-4000-8000-000000160087'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160047'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'active', (select d from today_t16), (select d from today_t16), 100000, 0);

-- The dateless one (164/165). `memberships_dated_unless_pending_chk` permits
-- null dates on `pending` and on nothing else, so this is the honest shape.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000160086'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160046'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
   'pending', 100000, 0);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000160021')::text,
  true);
set local role authenticated;

-- The four memberships that must arrive at "one period granted" EARN it, an
-- ordinary front-desk payment each. Unscored — these are the fixture, not
-- the claim; each one's resulting state is asserted where its own
-- subsection begins.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number) values
  ('22000000-0000-4000-8000-000000161001'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160040'::uuid, '22000000-0000-4000-8000-000000160080'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0001'),
  ('22000000-0000-4000-8000-000000161002'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160041'::uuid, '22000000-0000-4000-8000-000000160081'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0002'),
  ('22000000-0000-4000-8000-000000161003'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160042'::uuid, '22000000-0000-4000-8000-000000160082'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0003'),
  ('22000000-0000-4000-8000-000000161004'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160043'::uuid, '22000000-0000-4000-8000-000000160083'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0004'),
  ('22000000-0000-4000-8000-000000161005'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160047'::uuid, '22000000-0000-4000-8000-000000160087'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0005');


-- ---------------------------------------------------------------------------
-- 16a (GL043) — the PLAN is a term. ADR-089's headline: `plan_id` decides
-- how long a period is, and round six froze the price and the currency and
-- left it writable. Membership 160080, one period genuinely earned.
-- ---------------------------------------------------------------------------

-- 120
select results_eq(
  $$ select periods_granted, ends_on, plan_id from public.memberships where id = '22000000-0000-4000-8000-000000160080'::uuid $$,
  $$ values (1, (select d from today_t16) + 30, '22000000-0000-4000-8000-000000160060'::uuid) $$,
  'GL043/plan: the fixture earned its period rather than being handed one — one ordinary 100000 payment, one period, ends_on 30 days out, still on the 30-day plan'
);

-- 121
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160061'::uuid
   where id = '22000000-0000-4000-8000-000000160080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/plan: repointing a membership that has been granted a period at a LONGER (365-day) plan is refused — ADR-089 measured days_added=395 through this door, strictly easier than the price cut round six closed');

-- 122
select results_eq(
  $$ select plan_id, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160080'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000160060'::uuid, (select d from today_t16) + 30) $$,
  'GL043/plan: refused AND unmoved — the plan is still the 30-day one and ends_on has not shifted'
);

-- 123
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160062'::uuid
   where id = '22000000-0000-4000-8000-000000160080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/plan: repointing at a SHORTER (7-day) plan is refused too — the terms are frozen in both directions, exactly as price_paise already is, not merely in the direction that pays');

-- 124
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161006'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160040'::uuid, '22000000-0000-4000-8000-000000160080'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0006')
$$, 'GL043/plan: an ordinary renewal, right after two refused repointings, is still accepted — the freeze refuses edits to the terms, not payments');

-- 125 — the scenario's own words: "a further payment of the full price SHALL
-- grant one period of the ORIGINAL plan's length". 30, not 365 and not 7.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160080'::uuid $$,
  $$ values (2, (select d from today_t16) + 60) $$,
  'GL043/plan: the renewal bought one period of the ORIGINAL 30-day plan — ends_on at today+60, not today+395 and not today+37'
);

-- 126 — the permitted side of the freeze: writing the column its own current
-- value is not a change of terms. `is distinct from`, which the live price
-- freeze already gets right and this one must too.
select lives_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160060'::uuid
   where id = '22000000-0000-4000-8000-000000160080'::uuid
$$, 'GL043/plan: setting plan_id to the value it already holds is allowed — nothing changed, so no term changed');

-- 127 — an ordinary membership edit on a frozen membership. discount_paise
-- and status are not terms a period is scored against; a rule that froze the
-- whole ROW rather than the three terms would fail here, and this project
-- has shipped exactly that over-broad shape three times.
select lives_ok($$
  update public.memberships set discount_paise = 500, status = 'frozen'
   where id = '22000000-0000-4000-8000-000000160080'::uuid
$$, 'GL043/plan: an ordinary edit to a membership that has been granted periods — a discount correction and a status change — is not a change of terms and is allowed');

-- 128
select results_eq(
  $$ select discount_paise, status, plan_id, price_paise from public.memberships where id = '22000000-0000-4000-8000-000000160080'::uuid $$,
  $$ values (500::bigint, 'frozen'::public.membership_status, '22000000-0000-4000-8000-000000160060'::uuid, 100000::bigint) $$,
  'GL043/plan: that edit actually LANDED — allowed and applied, not allowed and silently dropped, while the three terms stayed exactly as they were'
);


-- ---------------------------------------------------------------------------
-- 16b (GL043) — the same freeze reached through statement shapes a rule
-- written as a single-row guard does not see. All three are ALLOWED on live
-- Cloud today. Membership 160081 (frozen), 160085 (nothing granted) as its
-- innocent sibling.
-- ---------------------------------------------------------------------------

-- 129
select results_eq(
  $$ select periods_granted, ends_on, plan_id from public.memberships where id = '22000000-0000-4000-8000-000000160081'::uuid $$,
  $$ values (1, (select d from today_t16) + 30, '22000000-0000-4000-8000-000000160060'::uuid) $$,
  'GL043/shapes: this membership earned its period too, on the 30-day plan'
);

-- 130
select throws_ok($$
  update public.memberships m set plan_id = p.id
    from public.plans p
   where p.id = '22000000-0000-4000-8000-000000160061'::uuid
     and m.id = '22000000-0000-4000-8000-000000160081'::uuid
$$, 'GL043'::char(5), null,
  'GL043/shapes: the repoint written as UPDATE … FROM is refused — the new value arriving from a joined row rather than a literal changes nothing about what the rule has to see');

-- 131
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000160081'::uuid as id) s
     on m.id = s.id
   when matched then update set plan_id = '22000000-0000-4000-8000-000000160061'::uuid
$$, 'GL043'::char(5), null,
  'GL043/shapes: the repoint written as MERGE is refused — ADR-087 records MERGE walking round a rule on this very table''s neighbour once already');

-- 132
select throws_ok($$
  with moved as (
    update public.memberships set plan_id = '22000000-0000-4000-8000-000000160061'::uuid
     where id = '22000000-0000-4000-8000-000000160081'::uuid
    returning id
  ) select count(*) from moved
$$, 'GL043'::char(5), null,
  'GL043/shapes: the repoint hidden in a data-modifying CTE is refused — the third of ADR-087''s three costumes, tried here against the freeze instead of against the arithmetic');

-- 133
select results_eq(
  $$ select plan_id, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000160060'::uuid, (select d from today_t16) + 30) $$,
  'GL043/shapes: refused AND unmoved through all three shapes — still the 30-day plan, ends_on still 30 days out'
);

-- 134 — one statement, two memberships, only one of them frozen. A rule that
-- answers for the rows it happens to reach, or that checks a statement's
-- rows as a set and stops at the first that looks fine, lets this through.
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160061'::uuid
   where id in ('22000000-0000-4000-8000-000000160081'::uuid,
                '22000000-0000-4000-8000-000000160085'::uuid)
$$, 'GL043'::char(5), null,
  'GL043/shapes: one statement repointing two memberships, only ONE of which has been granted a period, is refused — the frozen row is in the set and that is enough');

-- 135 — and the innocent row must not move either: a refusal that aborts
-- half a statement would be worse than the change it prevented.
select results_eq(
  $$ select id, plan_id from public.memberships
      where id in ('22000000-0000-4000-8000-000000160081'::uuid, '22000000-0000-4000-8000-000000160085'::uuid)
      order by id $$,
  $$ values ('22000000-0000-4000-8000-000000160081'::uuid, '22000000-0000-4000-8000-000000160060'::uuid),
            ('22000000-0000-4000-8000-000000160085'::uuid, '22000000-0000-4000-8000-000000160060'::uuid) $$,
  'GL043/shapes: NEITHER row moved — the statement was refused whole, including the membership that had been granted nothing and would otherwise have been free to change'
);


-- ---------------------------------------------------------------------------
-- 16c (GL044) — the count is the rule's. Reset it to 0 and the freeze above
-- is gated on a value the attacker just chose: ADR-089 measured 30 days of
-- gym for one paisa this way, and 75 days for ₹1,000.01 with a price cut
-- behind it. Membership 160082.
-- ---------------------------------------------------------------------------

-- 136
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160082'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/reset: one period earned by one ordinary payment, before anything is attempted'
);

-- 137
select throws_ok($$
  update public.memberships set periods_granted = 0
   where id = '22000000-0000-4000-8000-000000160082'::uuid
$$, 'GL044'::char(5), null,
  'GL044/reset: a front-desk session setting periods_granted back to 0 is refused — the value is one the rule itself can produce, so what is wrong is not the number but that a hand wrote it');

-- 138
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160082'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/reset: refused AND unmoved — the count still reads 1'
);

-- 139 — the money is still taken. A payment is not refused because somebody
-- earlier tried to rewrite the count; it simply buys what one paisa buys.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161007'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160042'::uuid, '22000000-0000-4000-8000-000000160082'::uuid,
          1, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0007')
$$, 'GL044/reset: the one-paisa payment that follows is recorded and receipted like any other');

-- 140 — the exploit's whole point, stated as an outcome rather than as a
-- mechanism: one paisa buys nothing, because the count it would have been
-- measured against could not be rewritten.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160082'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/reset: one paisa granted NOTHING — 100001 paise is still one whole multiple of 100000, and ends_on did not move a day'
);

-- 141 — the same write in expression form rather than as a literal.
select throws_ok($$
  update public.memberships set periods_granted = periods_granted + 1
   where id = '22000000-0000-4000-8000-000000160082'::uuid
$$, 'GL044'::char(5), null,
  'GL044/reset: writing the column from its own value (periods_granted + 1) is refused too — the rule is about who writes it, not about which literal appears in the statement');

-- 142 — the count smuggled alongside a write that is legitimate on its own.
select throws_ok($$
  update public.memberships set discount_paise = 999, periods_granted = 0
   where id = '22000000-0000-4000-8000-000000160082'::uuid
$$, 'GL044'::char(5), null,
  'GL044/reset: a legitimate discount edit carrying a reset of the count in the same statement is refused — an ordinary write is not a channel for this column');

-- 143
select results_eq(
  $$ select periods_granted, discount_paise, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160082'::uuid $$,
  $$ values (1, 0::bigint, (select d from today_t16) + 30) $$,
  'GL044/reset: refused AND nothing moved — not the count, and not the innocent discount that shared the statement with it'
);


-- ---------------------------------------------------------------------------
-- 16d (GL044) — raised, not lowered. ADR-089: `set periods_granted = 500`
-- then an ordinary ₹1,000 payment — money receipted, ends_on unmoved, zero
-- days granted, no error anywhere. That is ADR-088's own named harm reached
-- by hand instead of by rounding, and it is the one direction a CHECK on the
-- column's sign cannot see. Membership 160083.
-- ---------------------------------------------------------------------------

-- 144
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160083'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/raise: one period earned, before anything is attempted'
);

-- 145
select throws_ok($$
  update public.memberships set periods_granted = 500
   where id = '22000000-0000-4000-8000-000000160083'::uuid
$$, 'GL044'::char(5), null,
  'GL044/raise: staging the count far above what the money bought is refused — `periods_granted >= 0` permits 500, which is exactly why bounding the sign closes nothing');

-- 146
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160083'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/raise: refused AND unmoved at 1'
);

-- 147
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161008'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160043'::uuid, '22000000-0000-4000-8000-000000160083'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0008')
$$, 'GL044/raise: an ordinary full renewal follows');

-- 148 — the assertion the whole requirement exists for. Measured on live
-- Cloud today: the count stays at 500, ends_on does not move, the money is
-- receipted, and nothing raises. She pays ₹1,000 for zero days, silently.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160083'::uuid $$,
  $$ values (2, (select d from today_t16) + 60) $$,
  'GL044/raise: the renewal bought a month — the count is 2 and ends_on moved 30 days, rather than the payment being silently eaten by a number somebody typed'
);


-- ---------------------------------------------------------------------------
-- 16e (GL044) — the same column through the same three statement shapes,
-- through the writes that must stay allowed, and through the most
-- privileged writer there is. Membership 160087.
-- ---------------------------------------------------------------------------

-- 149
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160087'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/shapes: one period earned, before anything is attempted'
);

-- 150
select throws_ok($$
  update public.memberships m set periods_granted = 0
    from public.plans p
   where p.id = m.plan_id
     and m.id = '22000000-0000-4000-8000-000000160087'::uuid
$$, 'GL044'::char(5), null,
  'GL044/shapes: the reset written as UPDATE … FROM is refused');

-- 151
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000160087'::uuid as id) s
     on m.id = s.id
   when matched then update set periods_granted = 0
$$, 'GL044'::char(5), null,
  'GL044/shapes: the reset written as MERGE is refused');

-- 152
select throws_ok($$
  with moved as (
    update public.memberships set periods_granted = 0
     where id = '22000000-0000-4000-8000-000000160087'::uuid
    returning id
  ) select count(*) from moved
$$, 'GL044'::char(5), null,
  'GL044/shapes: the reset hidden in a data-modifying CTE is refused');

-- 153
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160087'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/shapes: refused AND unmoved through all three shapes'
);

-- 154 — permitted: the column written with the value it already holds.
select lives_ok($$
  update public.memberships set periods_granted = periods_granted
   where id = '22000000-0000-4000-8000-000000160087'::uuid
$$, 'GL044/shapes: setting periods_granted to the value it already holds is allowed — `is distinct from`, the same discrimination the live price freeze already makes');

-- 155 — permitted: a statement that changes nothing at all.
select lives_ok($$
  update public.memberships set ends_on = ends_on
   where id = '22000000-0000-4000-8000-000000160087'::uuid
$$, 'GL044/shapes: an update that changes nothing at all is allowed — a rule that refused it would break every idempotent write in the product');

set local role postgres;

-- 156 — "written by the rule and by nobody else" says nobody. The live price
-- freeze already refuses `postgres`, so a count rule that only answered
-- `authenticated` would be narrower than the rule it sits beside — and the
-- table's own owner is the writer a session GUC or a role test cannot stop.
select throws_ok($$
  update public.memberships set periods_granted = 9
   where id = '22000000-0000-4000-8000-000000160087'::uuid
$$, 'GL044'::char(5), null,
  'GL044/shapes: a top-level hand-write by postgres itself is refused — the rule is about the write not coming from the granting rule, not about which role is asking');

-- 157
select results_eq(
  $$ select periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000160087'::uuid $$,
  $$ values (1) $$,
  'GL044/shapes: refused AND unmoved even for postgres'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000160021')::text,
  true);
set local role authenticated;


-- ---------------------------------------------------------------------------
-- 16f — the permitted side, asserted as hard as the refused side. Every
-- assertion here fails against a fix that is too broad, which is the shape
-- this project has shipped three times. Memberships 160084 (nothing
-- granted), 160085 (the innocent sibling), 160086 (no dates at all).
-- ---------------------------------------------------------------------------

-- 158 — "Correcting a mistake before any money arrives": the price AND the
-- plan, in one statement, on a membership that has been granted nothing.
select lives_ok($$
  update public.memberships
     set price_paise = 75000,
         plan_id = '22000000-0000-4000-8000-000000160061'::uuid
   where id = '22000000-0000-4000-8000-000000160084'::uuid
$$, 'GL043/permitted: correcting both the price and the plan of a membership that has been granted nothing is allowed — nothing has been scored yet, so no recorded fact is being rewritten');

-- 159
select results_eq(
  $$ select price_paise, plan_id, periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000160084'::uuid $$,
  $$ values (75000::bigint, '22000000-0000-4000-8000-000000160061'::uuid, 0) $$,
  'GL043/permitted: the correction LANDED — allowed and applied, and the count is still 0'
);

-- 160
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161009'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160044'::uuid, '22000000-0000-4000-8000-000000160084'::uuid,
          75000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0009')
$$, 'GL043/permitted: a payment of the CORRECTED price against the corrected membership is recorded');

-- 161 — and it is scored against the corrected terms: one period, of the new
-- plan's 365 days, at the new price. The freeze must start at the first
-- grant, not at the membership's creation.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160084'::uuid $$,
  $$ values (1, (select d from today_t16) + 365) $$,
  'GL043/permitted: the corrected terms are what the money is scored against — one period of the NEW 365-day plan, bought at the NEW 75000 price'
);

-- 162 — CONTROL, already green: this is not GL043's doing. ADR-052's
-- composite key `memberships_plan_id_fkey (tenant_id, plan_id) references
-- plans(tenant_id, id)` refuses a plan belonging to another gym, and it is
-- asserted on a membership GL043 must leave alone, so it proves the tenant
-- boundary still stands exactly where the freeze stands aside. No SQLSTATE
-- is pinned: the requirement names none, and which mechanism answers is not
-- this assertion's business.
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160063'::uuid
   where id = '22000000-0000-4000-8000-000000160085'::uuid
$$, null::char(5), null,
  'tenant boundary: repointing a membership at a plan belonging to ANOTHER gym is refused even where GL043 does not apply — the membership has been granted nothing, so only the composite tenant foreign key stands between the two gyms');

-- 163
select is(
  (select exists (select 1 from public.plans p
                   where p.id = m.plan_id and p.tenant_id = m.tenant_id)
     from public.memberships m
    where m.id = '22000000-0000-4000-8000-000000160085'::uuid),
  true,
  'tenant boundary: refused AND unmoved — this membership''s plan still belongs to its own gym'
);

-- 164/165 — the rule's own multi-column write, which is the hardest thing
-- for either freeze to leave alone: a paid payment against a membership with
-- no dates at all sets starts_on, ends_on, status AND periods_granted in one
-- go. A count rule that refused every write to the column, or a terms rule
-- that fired on the row it is maintaining, would break exactly here — and
-- the member would be paid up and refused at the gate.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161010'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160046'::uuid, '22000000-0000-4000-8000-000000160086'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0010')
$$, 'GL044/permitted: a full payment against a dateless pending membership is recorded');

-- 165
select results_eq(
  $$ select periods_granted, starts_on, ends_on, status from public.memberships where id = '22000000-0000-4000-8000-000000160086'::uuid $$,
  $$ values (1, (select d from today_t16), (select d from today_t16) + 30, 'active'::public.membership_status) $$,
  'GL044/permitted: the rule wrote the dates, the status AND the count in one go, and neither freeze caught its own writer — the membership runs from today for the plan''s 30 days and is active'
);


-- ---------------------------------------------------------------------------
-- 16g (GL044, the fourth door) — a membership is created having been granted
-- nothing, and a write that leaves the count where it was is allowed.
--
-- 16c-16e above attack the count on an existing row, which is how the
-- requirement was first written. A holdout author went in the other way and
-- it worked: CREATE the membership carrying `periods_granted = 5`, then take
-- ₹1,000 for it — money receipted, `ends_on` unmoved, no UPDATE anywhere.
-- That is 16d's exploit reached through the door 16d does not watch, and
-- closing three of four is the mistake this whole round exists to correct.
-- Section 14b's own fixture used to walk through it, and has been repaired
-- to earn its period rather than declare one.
--
-- The two assertions that make this worth writing are the permitted ones.
-- 171: `periods_granted = 0` named explicitly in an insert's column list is
-- ordinary and must stay allowed — every membership fixture in this file
-- writes it that way, so a rule that refuses the column's PRESENCE rather
-- than a non-zero VALUE takes the whole suite down with it. 170: a
-- membership created the normal way still grants and still moves `ends_on`,
-- which is the harm the refusal exists to prevent, asserted as a consequence
-- rather than as a refusal alone.
-- ---------------------------------------------------------------------------

-- 166 — on a member of its own, so that 168's ordinary creation does not
-- depend on this one having been refused: `memberships_tenant_id_member_id_
-- live_key` allows a member only one live membership, and while the rule is
-- unbuilt this row survives.
-- 166
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted)
  values ('22000000-0000-4000-8000-000000160088'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160050'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
          'active', (select d from today_t16), (select d from today_t16), 100000, 5)
$$, 'GL044'::char(5), null,
  'GL044/created: a front-desk session creating a membership that already claims five granted periods is refused — the count is the granting rule''s at creation exactly as it is afterwards');

-- 167 — refused AND not written. A membership that exists holding a count
-- nobody earned is the whole harm; "it raised" is not enough on its own.
select results_eq(
  $$ select count(*)::int from public.memberships where id = '22000000-0000-4000-8000-000000160088'::uuid $$,
  $$ values (0) $$,
  'GL044/created: no such membership exists — the refusal left nothing behind'
);

-- 168 — the permitted side: created the way the console creates one, with the
-- column not mentioned at all and left to its default.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-000000160089'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160048'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
          'active', (select d from today_t16), (select d from today_t16), 100000)
$$, 'GL044/created: creating a membership without naming periods_granted at all — the console''s own shape — is allowed');

-- 169
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000161011'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160048'::uuid, '22000000-0000-4000-8000-000000160089'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000160021'::uuid, 'T16-RCT-0011')
$$, 'GL044/created: a full payment against that membership is recorded');

-- 170 — the harm behind the refusal, gone: the money bought a month.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160089'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/created: a membership created the normal way is granted its period and ends_on moves — which is exactly what a membership created carrying a count of its own would have silently swallowed'
);

-- 171 — and an explicit zero in the column list stays ordinary.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted)
  values ('22000000-0000-4000-8000-000000160090'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
          '22000000-0000-4000-8000-000000160049'::uuid, '22000000-0000-4000-8000-000000160060'::uuid,
          'active', (select d from today_t16), (select d from today_t16), 100000, 0)
$$, 'GL044/created: naming periods_granted explicitly as 0 is allowed — a membership created having been granted nothing is what the rule requires, not a rule against mentioning the column');

-- 172/173 — "Writing the same count back". 154 above does this with the
-- column referring to itself; this is the literal form, which is what an
-- ORM or any column-listing update sends, and the shape the requirement
-- names as the reason a same-value write must not be refused. Membership
-- 160089 reads 1 after 170.
select lives_ok($$
  update public.memberships set periods_granted = 1
   where id = '22000000-0000-4000-8000-000000160089'::uuid
$$, 'GL044/created: writing the literal value the count already holds is allowed — every exploit needs the value MOVED, and refusing a write that cannot do harm breaks ordinary column-listing updates');

-- 173
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160089'::uuid $$,
  $$ values (1, (select d from today_t16) + 30) $$,
  'GL044/created: allowed, and nothing moved — the count still reads 1 and ends_on is where the payment left it'
);


select * from finish();
rollback;
