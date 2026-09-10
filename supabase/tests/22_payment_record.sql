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

-- NINTH-ROUND EXTENSION — Section 18 (assertions 243-290), and the first
-- round in which this file had to UNDO an assertion of its own rather than
-- only add to them. ADR-092: round eight's requirement named the harm
-- ("create a membership naming `duration_days = 3650`, pay the ordinary
-- price, get ten years") and three lines later mandated the identical
-- outcome by another route, permitting a length to be corrected on its own
-- before money arrives. Section 17f wrote that permission down as an
-- assertion — a front desk typing `duration_days = 90` onto a membership
-- whose plan says 365, and the payment buying 90 days. 222-225 are repaired
-- in place, with 17f's own header carrying the reason; 182 and 192 keep the
-- assertion and the `GL043` they always had, and only their stated reason
-- changes — a length is refused because it is derived, not because money has
-- arrived, which is why Section 18 can assert the same refusal on a
-- membership that has taken nothing. Nothing else in
-- the file rested on a hand-written length: `grep -n duration_days` returns
-- plan-table fixtures, Section 17d's legitimate plan edit (202-210, which
-- must keep working exactly as it does) and those five lines.
--
-- Section 18 is the new battery, and the whole of it is on memberships that
-- have taken NO money — the only way to tell the derived-length rule apart
-- from the money freeze, since on a part-paid row either could be what
-- refuses. The SQLSTATE for a hand-written length was open in the
-- requirement and the coordinator answered it to both blind authors at once:
-- `GL043`, because it is a term of the membership and a reader chasing it
-- looks where the other terms are. The one choice this file still had to
-- make on its own is what a length typed ALONGSIDE a legitimate plan change
-- does (18d reads it as landing at the plan's value, on the requirement's
-- own parallel with a named price); the report names it.
--
-- PLAN COUNT: 290 (242 + 48).

-- TENTH-ROUND EXTENSION — Section 19 (assertions 291-349), ADR-093 / GL045;
-- its own header states its attack list and the one place it diverges from
-- the literal text of a scenario. PLAN COUNT after it: 349.
--
-- ELEVENTH-ROUND EXTENSION — Section 20 (assertions 350-404), ADR-094 /
-- GL046, "Deciding what a member owes is gym-admin work". Section 20's own
-- header carries the attack list and the three calls this author had to make
-- (the ordering against GL043, the no-op write, and `service_role`).
--
-- AND THE SECOND ROUND IN WHICH THIS FILE HAD TO UNDO ASSERTIONS OF ITS OWN.
-- "Correcting a mistake before any money arrives" said *a front-desk session*
-- for four rounds; ADR-094 records the 300-days-for-one-month's-fee a critic
-- bought through exactly that sentence, and the scenario now says *a gym
-- admin*. Two shapes were reconciled, and NEITHER changed what any assertion
-- claims — only who performs it or which innocent column rides beside it:
--
--   * The permitted-side corrections — 118, 158, 212, 220, 222, 244, 249,
--     253, 257 and 329 — are now made by a `gym_manager` session. Every one
--     of them is about WHEN the terms are still free, not WHO may move them,
--     so the statement, the expected values and the SQLSTATE are untouched.
--     A `gym_manager` staff row was added to tenants 14, 16 and 18, which had
--     none; 17 and 19 already had one.
--   * `discount_paise` joined the restricted set (ADR-094: bounding the price
--     and leaving the discount free moves the same exploit to another
--     column), so the five places it appeared as the "ordinary edit" beside a
--     frozen column — 127/128, 142/143, 270/271, 285/286, 305/306, 336/338 —
--     carry `cancel_reason` instead, or drop it. The shapes those assertions
--     exist for (a two-column edit landing whole, a smuggled write, a
--     column-listing update) are all unchanged.
--
-- Nothing else in the file rested on a front desk changing a term:
-- `grep -n "price_paise\|plan_id\|currency\|discount_paise"` over the
-- UPDATE statements returns those sites and, otherwise, refusals — every one
-- of which is still a refusal.
--
-- PLAN COUNT: 416 (349 + 67).
--
-- TWELFTH-ROUND EXTENSION — Sections 21 (417-430) and 22 (431-445), the same
-- GL046, in one small round: `coupon_id` joins the column list, and "A comp
-- that was a typo" gets its repair path asserted as a working sequence.
-- BOTH SUITES' round-twelve sections were written by the SAME author — a
-- deliberate, recorded deviation from hard rule 10 / ADR-059, argued in
-- section 21's own header. PLAN COUNT: 445 (416 + 29).
--
-- 20i (405-416) AND THE FLIP AT 373/374 are the coordinator's two answers to
-- this round's own finding, given to both blind authors at once. Running
-- ADR-092's grep on GL046 itself showed the requirement naming the 300-days
-- harm and then permitting the identical outcome through creation: measured
-- live, a front desk creating a membership at `price_paise = 15000` on a
-- 30-day Rs 1,500 plan and taking the ordinary Rs 1,500 gets
-- `periods_granted = 10` and `ends_on` 300 days out, with NO UPDATE anywhere
-- in it — one statement fewer than the exploit GL046 was written to close,
-- and the third round running in which the fourth door was the INSERT. It is
-- closed here rather than carried as an open item.
--
-- SEVENTEENTH-ROUND EXTENSION — Sections 25, 26 and 27 (assertions 509-595),
-- the spec's three new requirements, one section each and one tenant each
-- (21, 22, 23). Each section's own header carries its attack list, the calls
-- this author had to make, and the reproduction that preceded it. Nothing
-- above 508 is touched: assertions 1-508 are unchanged and all 508 are green.
--
-- WRITTEN THE SAME WAY THE REST OF THIS FILE WAS. No migration dated
-- 20260911100000 or later was opened, no `pg_get_functiondef` or
-- `pg_proc.prosrc` of any `app.*` function under test was read (the one
-- exception is `app.is_front_office`, whose body was read to know WHICH ROLES
-- reach `memberships_tenant_write` — it is an accessor, not a rule, and it is
-- not under test here), `docs/registry.md` was not consulted for this round's
-- code (ADR-091) and `supabase/tests-holdout/` was not opened. Table shape,
-- triggers, policies, constraints, indexes and every enum's labels come from
-- the catalogue, read through `supabase db query --linked` inside
-- `begin … rollback`.
--
-- THREE CATALOGUE FACTS THAT SHAPED THESE SECTIONS, stated because guessing at
-- any of them would have produced a section that passes for the wrong reason:
--   * `refund_status` is (`requested`, `processing`, `completed`, `failed`).
--     There is no `pending`. Section 25 enumerates the four that exist.
--   * a payment cannot be INSERTed at `refunded` or `reversed` — `GL039`
--     refuses it for postgres as much as for a session, since that rule takes
--     no trusted-context carve-out. Section 26's two "money came back" fixtures
--     are therefore written `paid` and moved, which is how they arise in
--     production too.
--   * `memberships_tenant_id_member_id_live_key` is partial — `where status in
--     ('active','frozen')` — which is what makes Section 27's cancelled-row
--     move (592) a refusal the index cannot possibly be answering.
--
-- PLAN COUNT: 709 — 700 through round eighteen, plus Section 32's 9 (ADR-099,
-- WHICH of two rules answers a statement that violates both). Not run against
-- Cloud: it is committed red on purpose, ahead of the implementation.
--
-- PLAN COUNT (round eighteen): 700 — 599 through round seventeen, plus round
-- eighteen's 101 (Sections 29-31, OPEN-030, the status machine). The paragraph
-- below is round seventeen's own note on how 599 was confirmed and is left
-- standing because round eighteen confirmed 700 exactly the same way, with
-- the same wrapper and the same result: `EMITTED 700 / FAILED 31` against
-- Cloud as it stands, and `EMITTED 700 / FAILED 0` against the same file with
-- a transition rule simulated inside the transaction and rolled back. The
-- second run is what proves no fixture anywhere in this file transitions a
-- membership illegally — nothing needed repairing, and grepping for
-- `set status` would not have proved it.
--
-- PLAN COUNT (round seventeen): 599 (508 + 87, plus Section 28's 4 for the
-- coordinator's mid-round decision on the in-flight statuses). Confirmed against Cloud
-- through the same wrapper the earlier rounds used: every pgTAP call rewritten
-- to `insert into tap_out(line) …` so the whole run lands in one result set —
-- `supabase db query` returns only the LAST result set that has rows, so a raw
-- run of this file reports `finish()` and nothing else, and a suite counted
-- that way is a false GREEN waiting to happen. `plan_line` is `1..599`,
-- `ok_count` 557 + `not_ok_count` 42 = 599 matching the plan exactly, and
-- `total_lines` 601 = the plan line + 599 assertions + finish()'s one
-- diagnostic row. Nothing committed; the run returned, which is itself the
-- rollback path executing.
--
-- RED (42), and every one of them is one of this round's three requirements:
--   * 512-519, 530-531, 538-539 — a refund's status is frozen by nothing, so a
--     `completed` refund can be demoted to any of the other three, by either
--     gym-admin role, and the ceiling then re-opens (514 is the exploit's last
--     step and the assertion this section exists for);
--   * 541-548, 552, 555-556, 562 — a refund against a payment that never took
--     money is accepted, in all three of the statuses the requirement names
--     and whether the refund's own status is `completed` or `failed`;
--   * 578-593, 595 — `memberships.member_id` is writable by a front desk, a
--     gym owner and a trusted context, in a plain UPDATE, an `UPDATE … FROM`,
--     a data-modifying CTE, a `MERGE`, and a two-row statement, on a live
--     membership carrying a granted period and on a cancelled one.
--   * 557-ish note: 557 and 558 are the only pair whose RED is a CONSEQUENCE
--     rather than a direct measurement — 555's missing refusal leaves a refund
--     behind, so 558's "exactly one refund" counts two. 557 itself is green.
--
-- LEGITIMATELY GREEN BEFORE AND AFTER, which is half of what this round is
-- for, because a fix broad enough to pass every refusal above would break
-- these and nothing else in the file: 509-511 and 520-529, 532-537, 540 (a
-- full refund is accepted at the ceiling; a completed refund's own status
-- written back, and its `provider_refund_id`, stay writable; all four moves
-- among the non-completed statuses and the ordinary path INTO `completed`
-- work; no payment in tenant 21 ever exceeds its ceiling); 549-551, 553-554,
-- 559-561 (refunds against paid, refunded and reversed payments are accepted
-- and still bounded by `GL036`); 563-577 and 594 (selling, renewing, freezing,
-- unfreezing, cancelling and re-selling all still work, the same-value write
-- is allowed, and the live unique key's trap is disarmed and shown to be); and
-- 596-599, the whole of Section 28 (a full refund at `processing` blocks a
-- second, the provider rejecting it is permitted, the ceiling therefore
-- RELEASES, and nothing has left). Those four are the sharpest too-broad
-- detector in the file: an implementer who freezes every refund status change
-- in order to pass 512, 516 and 518 breaks 597 and 598 and nothing else.
--
-- THE INVARIANT IS NARROWER THAN "THE CEILING IS NEVER RELEASED", and this
-- file asserts the narrow one deliberately. The freeze is keyed on `completed`
-- while the `GL036` sum excludes only `failed`, so `requested → failed` and
-- `processing → failed` un-count a refund and release the ceiling — and the
-- requirement's second scenario permits both in as many words. Both suites'
-- authors found that independently and it went to the coordinator, whose
-- decision is that it stays permitted and the requirement will say why:
--
--   money that LEFT does not become an attempt. Money in flight may.
--
-- A refund at `requested` or `processing` is money the gym has handed to the
-- provider and the provider has not moved. It can genuinely fail — that is
-- what the status is for — and refusing the transition would strand the refund
-- with nobody able to resolve it while the ceiling permanently consumed money
-- that never left. A refund at `completed` is different in kind: the money is
-- gone, and calling it an attempt afterwards falsifies the ledger. **The
-- ceiling is deliberately weaker at the in-flight statuses**, which is a
-- property to state and assert, not a hole to close.
--
-- So the ceiling consequence is asserted on BOTH sides of that line rather
-- than only on the refusal: 514 — after a refused `completed → failed`, the
-- second full refund is still refused; 532-537 and 596-599 — after a permitted
-- `requested → failed` and a permitted `processing → failed`, the second full
-- refund IS accepted, and no money has left in either case. 535 and 537 pin
-- what still bounds the money itself: `GL036` on UPDATE means only one of the
-- two refunds can ever reach `completed`, so only one payment's worth can
-- actually go out however the in-flight statuses are walked.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(805);


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
   100000, 'paid', 'cash', 'T2-RCT-0002', '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001005'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'created', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid),
  ('22000000-0000-4000-8000-000000001006'::uuid, '22000000-0000-4000-8000-000000000002'::uuid,
   '22000000-0000-4000-8000-000000000042'::uuid, null,
   100000, 'pending', 'cash', null, '22000000-0000-4000-8000-000000000022'::uuid);

-- 1004 is the "reviving a refunded payment" fixture and it USED to be
-- inserted straight at 'refunded'. Round eight's GL039 ("A payment does not
-- arrive already refunded") forbids exactly that, for every writer and with
-- no carve-out, so this fixture was aborting the whole file at line 1 of
-- Section 2 and hiding every assertion after it. It is now staged the way
-- the requirement says money reaches that status — recorded paid, then
-- refunded — keeping its id, amount, member, membership and staff exactly as
-- they were, so assertions 21/22 still mean what they meant. Do not
-- "simplify" it back into the VALUES list above: a bare 'refunded' literal
-- there is the shape a grep for '::public.payment_status' does not find.
update public.payments set status = 'refunded'
 where id = '22000000-0000-4000-8000-000000001004'::uuid;

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
--
-- THE EXPECTED VALUE MOVED, AND THE REQUIREMENT MOVED, NOT THE TEST. This read
-- `today + 30 + 30` for as long as this file has existed: the membership's
-- TYPED span (`today … today + 30`) plus the one period the money bought. The
-- `membership-creation` contract's "the first period is set, not added"
-- (Section 37) settles that a membership which has been granted NO periods has
-- its span SET from the plan rather than extended — the span it was created
-- carrying was typed and not bought, and adding a bought period on top of a
-- typed one hands the typed one out free. 085 is created with
-- `periods_granted` defaulted to 0, so the second half payment here is its
-- FIRST grant, and one period of money now buys exactly one period of gym. The
-- first `+ 30` was the typed half; it is what fell away. `starts_on` is
-- unchanged and still today — it is the later of its own value and today, and
-- today they are the same date. WHAT THIS ASSERTION TESTS IS UNTOUCHED: two
-- half payments reaching one multiple grant exactly one period, scored against
-- the membership's own 100000 and not the plan's 120000 list price, which is
-- still the only reason this pair of payments is split in half.
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000085'::uuid $$,
  $$ select (select d from today_t8) + 30 $$,
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
--
-- THE EXPECTED VALUE MOVED, AND THE REQUIREMENT MOVED, NOT THE TEST. This read
-- `today + 30 + 60` — the membership's TYPED span plus the two periods bought.
-- 088 is created at `periods_granted = 0`, so this single payment is its FIRST
-- grant, and "the first period is set, not added" (the `membership-creation`
-- contract, Section 37) makes that grant SET the span to `duration_days x
-- periods_granted` rather than add to a span nobody paid for: 60 days, not 90.
-- The first `+ 30` was the typed half and it is what fell away; the `+ 60` —
-- the part this assertion is actually about — is unchanged. WHAT THIS ASSERTION
-- TESTS IS UNTOUCHED: two multiples in ONE payment grant exactly TWO periods,
-- which is still the only thing distinguishing "counts the money" from "grants
-- one period per statement".
select results_eq(
  $$ select ends_on from public.memberships where id = '22000000-0000-4000-8000-000000000088'::uuid $$,
  $$ select (select d from today_t8) + 60 $$,
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
   '22000000-0000-4000-8000-000000140011'::uuid, 'front_desk', 'T14 Desk'),
  ('22000000-0000-4000-8000-000000140022'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140011'::uuid, 'gym_manager', 'T14 Manager');

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

-- ROUND ELEVEN RE-ROLED THIS FIXTURE, AND ONLY THIS FIXTURE. A zero-price
-- membership on a Rs 1,000 plan is a COMPLIMENTARY one, and comping is
-- exactly the act ADR-094 calls gym-admin work: GL046 now refuses it from a
-- front desk at creation as well as on update, so the fixture as written
-- aborted the whole file at this line. Nothing about 106-109 is a claim about
-- who may create such a membership — they are about a payment against a zero
-- price leaving `periods_granted` alone — so the manager creates it, which is
-- what the contract now says such a sale is. The membership, its price and
-- every assertion below are byte for byte what they were.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000140022')::text,
  true);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('22000000-0000-4000-8000-000000140083'::uuid, '22000000-0000-4000-8000-000000140001'::uuid,
   '22000000-0000-4000-8000-000000140043'::uuid, '22000000-0000-4000-8000-000000140060'::uuid,
   'active', (select d from today_t14), (select d from today_t14) + 30, 0, 0);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000140021')::text,
  true);

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

-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000140022')::text,
  true);

select lives_ok($$
  update public.memberships set price_paise = 75000
   where id = '22000000-0000-4000-8000-000000140086'::uuid
$$, 'GL043: a gym admin correcting price_paise on a membership with periods_granted = 0 (no money has arrived yet) succeeds');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000140001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000140021')::text,
  true);


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
   '22000000-0000-4000-8000-000000160011'::uuid, 'front_desk', 'T16 Desk'),
  ('22000000-0000-4000-8000-000000160022'::uuid, '22000000-0000-4000-8000-000000160001'::uuid,
   '22000000-0000-4000-8000-000000160011'::uuid, 'gym_manager', 'T16 Manager');

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

-- 127 — an ordinary membership edit on a frozen membership. A note and a
-- status are not terms a period is scored against; a rule that froze the
-- whole ROW rather than the three terms would fail here, and this project
-- has shipped exactly that over-broad shape three times.
--
-- ROUND ELEVEN RECONCILED THE COMPANION COLUMN, NOT THE ASSERTION. This
-- statement used to carry `discount_paise = 500` as its ordinary edit; ADR-094
-- moves `discount_paise` into the set only a gym admin may change, because
-- bounding the price and leaving the discount free moves the same exploit to
-- a different column. The shape under test — a two-column edit landing whole
-- on a membership whose terms are frozen — is untouched; the companion is now
-- a column the front desk still owns. Section 20 carries the discount itself,
-- refused for the desk and allowed for a gym admin.
select lives_ok($$
  update public.memberships set cancel_reason = 'desk note', status = 'frozen'
   where id = '22000000-0000-4000-8000-000000160080'::uuid
$$, 'GL043/plan: an ordinary edit to a membership that has been granted periods — a note and a status change — is not a change of terms and is allowed');

-- 128
select results_eq(
  $$ select cancel_reason, status, plan_id, price_paise from public.memberships where id = '22000000-0000-4000-8000-000000160080'::uuid $$,
  $$ values ('desk note'::text, 'frozen'::public.membership_status, '22000000-0000-4000-8000-000000160060'::uuid, 100000::bigint) $$,
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
--
-- ROUND ELEVEN SENDS THIS ONE AS A GYM ADMIN, AND THE REASON IS A PROPERTY
-- WORTH KNOWING RATHER THAN A STALE CLAIM — the eleventh site of the same
-- "when, not who" shape as the other ten. Under a non-admin claim this
-- statement's two rows are answered by two different rules: the frozen row
-- reaches `GL043` and the moneyless row falls through to `GL046`, and
-- **Postgres does not guarantee which row a statement's row triggers fire
-- for first**. The statement is refused either way and neither row moves
-- either way — the assertion's whole substance holds — but the SQLSTATE
-- becomes a coin toss. `GL046` cannot fire for a gym admin, so sending it as
-- one leaves `GL043` the only rule in play and the code deterministic, while
-- the thing being asserted (a frozen row is in the set and that is enough)
-- is untouched.
--
-- THE GENERAL PROPERTY, so the next author does not rediscover it as a flake:
-- a mixed multi-row statement from a NON-ADMIN session is refused with
-- whichever of the two rules the first row happens to reach. Any future
-- assertion mixing frozen and unfrozen rows under a non-admin claim must
-- assert the refusal AND the unchanged values, never the code. Fixing this by
-- reordering the rules was considered and rejected: an absolute beats a
-- permission, `GL043` binds gym admins too, and 382/384 pin that order on
-- purpose — changing the rule to suit a fixture is the tail wagging the dog.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000160022')::text,
  true);

select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000160061'::uuid
   where id in ('22000000-0000-4000-8000-000000160081'::uuid,
                '22000000-0000-4000-8000-000000160085'::uuid)
$$, 'GL043'::char(5), null,
  'GL043/shapes: one statement repointing two memberships, only ONE of which has been granted a period, is refused — the frozen row is in the set and that is enough. Sent as a gym admin so that GL043 is the only rule that can answer; from a desk the moneyless row would reach GL046 instead and the code would depend on trigger firing order');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000160021')::text,
  true);

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
-- ROUND ELEVEN swapped the innocent column from `discount_paise` to
-- `cancel_reason`: after ADR-094 a discount edit is no longer legitimate for
-- THIS session, and a statement two rules could each refuse cannot pin which
-- one answers. The smuggling shape is what this assertion is about, and it is
-- unchanged.
select throws_ok($$
  update public.memberships set cancel_reason = 'desk note', periods_granted = 0
   where id = '22000000-0000-4000-8000-000000160082'::uuid
$$, 'GL044'::char(5), null,
  'GL044/reset: a legitimate note edit carrying a reset of the count in the same statement is refused — an ordinary write is not a channel for this column');

-- 143
select results_eq(
  $$ select periods_granted, cancel_reason, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000160082'::uuid $$,
  $$ values (1, null::text, (select d from today_t16) + 30) $$,
  'GL044/reset: refused AND nothing moved — not the count, and not the innocent note that shared the statement with it'
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
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000160022')::text,
  true);

select lives_ok($$
  update public.memberships
     set price_paise = 75000,
         plan_id = '22000000-0000-4000-8000-000000160061'::uuid
   where id = '22000000-0000-4000-8000-000000160084'::uuid
$$, 'GL043/permitted: a gym admin correcting both the price and the plan of a membership that has been granted nothing is allowed — nothing has been scored yet, so no recorded fact is being rewritten');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000160001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000160021')::text,
  true);


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


-- ===========================================================================
-- SECTION 17 (GL043 re-gated onto money, and GL039) — the terms money is
-- scored against are frozen by MONEY ARRIVING, the duration a period is
-- measured in is one of those terms and is recorded on the membership, and
-- a payment does not arrive already refunded. Tenant 17. Assertions
-- 174-242.
--
-- Round eight. Round seven (Section 16) made `periods_granted` unforgeable
-- so that `old.periods_granted > 0` could be trusted as the gate, and never
-- asked whether the gate says the right thing. It does not, and the exploit
-- round seven was written to close survived it (ADR-090).
--
-- A membership that has taken REAL MONEY but not yet crossed one whole
-- multiple of its price sits at `periods_granted = 0` and every one of its
-- terms is open. That is not a contrived state — it is a part payment,
-- ordinary practice in an Indian gym, which this file already proves is
-- recorded and receipted. Measured on a real row of the live demo gym,
-- Rs 10,800 arrived against a Rs 12,000 Annual: cut the price to Rs 1,000
-- (allowed, nothing had been *granted*), then pay one paisa, and `ends_on`
-- moved TEN YEARS.
--
-- WHY THE ARRANGEMENT MISSED IT, WHICH IS THE PART THAT CONCERNS THIS FILE.
-- ADR-089s requirement said "before any money has arrived" in its prose and
-- "a membership that has been granted nothing" in its scenario three lines
-- below. The implementation was built to the scenario, and BOTH blind
-- suites asserted the weaker sentence and went green — Section 15 and
-- Section 16 of this file are the visible half of that. A blind arrangement
-- cannot catch a scenario that encodes the implementation own assumption.
-- So this section was written by reading the requirement PROSE against its
-- scenario list first, and where the two could disagree the prose is what
-- is asserted. The one place they still can, and the report says so, is
-- money in a currency the membership is not priced in: the prose says "any
-- money has arrived", the granting rule scores only same-currency money,
-- and 239-242 assert the prose.
--
-- Written from openspec/changes/phase-5-money/specs/payment-record/spec.md
-- ("The terms money is scored against are frozen by money arriving",
-- GL043; "A payment does not arrive already refunded", GL039) and ADR-090,
-- by a session that has read neither supabase/tests-holdout/ nor the
-- implementation. Only the catalogue was read, black box, through
-- `supabase db query --linked`, wrapped begin...rollback, nothing
-- committed.
--
-- MEASURED ON LIVE CLOUD BEFORE WRITING A LINE, all in throwaway
-- begin...rollback transactions, all from an ordinary front-desk session:
--
--   * `memberships` HAS NO `duration_days` COLUMN. A period length is read
--     live from `plans` on every payment.
--   * on a part-paid membership (Rs 500 against a Rs 1,000 price,
--     `periods_granted = 0`, receipt 2026-27/000001 issued): cutting the
--     price ALLOWED, changing the currency ALLOWED, repointing the plan
--     ALLOWED.
--   * a payment INSERTED straight at `refunded` ALLOWED, and at `reversed`
--     ALLOWED, both taking no receipt number and granting nothing at the
--     time.
--   * the two together, with the term edit and the first payment in ONE
--     data-modifying CTE: Rs 3,000 `refunded` + 1 paisa `reversed` + Rs 500
--     `paid`, price cut to one paisa in the same statement — 350001 periods
--     granted and `ends_on` at 30774-10-18. Twenty-eight thousand years of
--     gym, one statement, no error.
--   * a gym manager setting `plans.duration_days = 3650` ALLOWED (and it
--     must stay allowed), after which an ordinary Rs 1,000 renewal on a
--     membership sold at 30 days moved `ends_on` 3650 days.
--   * a membership whose only payment was later refunded IN FULL sits at
--     `periods_granted = 0` and its price cut is ALLOWED.
--
-- WHAT IS ATTACKED. The part-paid window for each of the four terms
-- (174-187); the same window through UPDATE ... FROM, MERGE, a
-- data-modifying CTE and a two-row statement where only one row is frozen
-- (188-195); money that arrived and was then fully refunded, which the
-- total still counts, so the freeze must not thaw (196-200); a plan
-- lengthened by its gym admin, which must stay legal and must not re-length
-- a membership already sold (201-210); the statuses that are NOT money
-- arriving (211-221); the first payment and a term edit in the SAME
-- statement (226-227); a payment inserted directly at `refunded` and at
-- `reversed`, and the one-paisa payment that would have cashed the credit
-- in (228-238); and money in a currency the membership is not priced in
-- (239-242).
--
-- THE PERMITTED SIDE IS ASSERTED AS HARD AS THE REFUSED SIDE, because a fix
-- that is too broad passes every refusal test and this project has shipped
-- exactly that three times. A membership with no money at all stays fully
-- editable in all four terms AND the money that follows is scored against
-- the corrected ones (222-225); a plan edit is allowed and applies to
-- memberships created afterwards (202-203, 207-210); a part payment is
-- still recorded and receipted (175); ordinary renewals still grant
-- (184-187, 199-200, 205-206); a `created`, `pending` or `failed` payment
-- still records and still leaves the terms free (211-221, 237).
--
-- ONE OLDER FIXTURE WAS REPAIRED, AND IT IS THE ONLY EDIT THIS ROUND MADE
-- OUTSIDE THIS SECTION. Section 2's payment 1004 — the "reviving a refunded
-- payment" fixture — was INSERTED straight at `refunded`, which is precisely
-- what GL039 forbids, so once the rule lands the file aborts on that insert
-- and every assertion after it disappears. It is now recorded `paid` and
-- then updated to `refunded`, keeping its id, amount, member, membership and
-- staff, so 21/22 still mean what they meant. A test that stages its subject
-- by doing the thing the requirement forbids is the same shape as Section
-- 14b's fixture in round seven, which declared a period instead of earning
-- one.
--
-- SQLSTATES ARE ASSERTED, NOT LEFT OPEN, on the same reasoning Section 16
-- gives: `GL043` for a term, `GL039` for a payment that arrives already
-- refunded (ADR-090 names that code for it). Every refusal asserts the code
-- AND that the value did not move.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000170001'::uuid, 'PayRec Gym 17', 'PYR22H');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000170011'::uuid, '22000000-0000-4000-8000-000000170001'::uuid, 'G17 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000170021'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'front_desk', 'T17 Desk'),
  ('22000000-0000-4000-8000-000000170022'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'gym_manager', 'T17 Manager');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000170040'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 PartPaid', '+912200170040'),
  ('22000000-0000-4000-8000-000000170041'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 Shapes', '+912200170041'),
  ('22000000-0000-4000-8000-000000170042'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 Refunded', '+912200170042'),
  ('22000000-0000-4000-8000-000000170043'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 SoldAt30', '+912200170043'),
  ('22000000-0000-4000-8000-000000170044'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 NotYetPaid', '+912200170044'),
  ('22000000-0000-4000-8000-000000170045'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 NoMoney', '+912200170045'),
  ('22000000-0000-4000-8000-000000170046'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 Sibling', '+912200170046'),
  ('22000000-0000-4000-8000-000000170047'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 SameStatement', '+912200170047'),
  ('22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 ArrivesRefunded', '+912200170048'),
  ('22000000-0000-4000-8000-000000170049'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 SoldAfterEdit', '+912200170049'),
  ('22000000-0000-4000-8000-000000170050'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 ForeignMoney', '+912200170050'),
  ('22000000-0000-4000-8000-000000170051'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170011'::uuid, 'M17 NeverArrived', '+912200170051');

-- Four plans. 170060 is the general 30-day one; 170061 (365d) and 170062
-- (7d) are repoint targets in both directions; 170063 is 17d own 30-day
-- plan, used by nothing else, so that lengthening it to 3650 in the middle
-- of this section cannot perturb any other membership assertion.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000170060'::uuid, '22000000-0000-4000-8000-000000170001'::uuid, 'G17 Plan (30d)', 30, 100000),
  ('22000000-0000-4000-8000-000000170061'::uuid, '22000000-0000-4000-8000-000000170001'::uuid, 'G17 Plan (365d)', 365, 100000),
  ('22000000-0000-4000-8000-000000170062'::uuid, '22000000-0000-4000-8000-000000170001'::uuid, 'G17 Plan (7d)', 7, 100000),
  ('22000000-0000-4000-8000-000000170063'::uuid, '22000000-0000-4000-8000-000000170001'::uuid, 'G17 Plan (30d, editable)', 30, 100000);

create temp table today_t17 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000170001'::uuid;

grant select on today_t17 to public;

-- Every membership starts at `ends_on = today` so that one period is
-- `today + <its own duration>` with nothing else in the arithmetic, and
-- every one is created having been granted nothing. The ones that need
-- money EARN it below from ordinary front-desk payments.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000170080'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170040'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170081'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170041'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170082'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170042'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170083'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170043'::uuid, '22000000-0000-4000-8000-000000170063'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170084'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170044'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170085'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170045'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170086'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170046'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170087'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170047'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170088'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170090'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170050'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000),
  ('22000000-0000-4000-8000-000000170091'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170051'::uuid, '22000000-0000-4000-8000-000000170060'::uuid,
   'active', (select d from today_t17), (select d from today_t17), 100000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);
set local role authenticated;

-- The fixture money, all of it ordinary front-desk work, none of it scored:
-- three part payments of half the price (170080, 170081, 170082) and one
-- full payment (170083). No receipt_number is supplied anywhere in this
-- section — the counter issues them, which is what Requirement 2 says.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000171001'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170040'::uuid, '22000000-0000-4000-8000-000000170080'::uuid,
   50000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid),
  ('22000000-0000-4000-8000-000000171002'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170041'::uuid, '22000000-0000-4000-8000-000000170081'::uuid,
   50000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid),
  ('22000000-0000-4000-8000-000000171003'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170042'::uuid, '22000000-0000-4000-8000-000000170082'::uuid,
   50000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid),
  ('22000000-0000-4000-8000-000000171004'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
   '22000000-0000-4000-8000-000000170043'::uuid, '22000000-0000-4000-8000-000000170083'::uuid,
   100000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid);


-- ---------------------------------------------------------------------------
-- 17a (GL043) — the part-paid window, all four terms. Membership 170080:
-- Rs 500 arrived against a Rs 1,000 price, so `periods_granted` is 0 and
-- round seven freeze does not apply to a single one of its terms. This is
-- ADR-090 headline, and the demo-gym row it was measured on.
-- ---------------------------------------------------------------------------

-- 174
select results_eq(
  $$ select periods_granted, ends_on, price_paise, currency from public.memberships where id = '22000000-0000-4000-8000-000000170080'::uuid $$,
  $$ values (0, (select d from today_t17), 100000::bigint, 'INR'::text) $$,
  'GL043/part-paid: half the price arrived and bought nothing — the membership sits at periods_granted = 0 with ends_on unmoved, which is exactly the window round seven gate leaves wide open'
);

-- 175 — and it was RECEIPTED. The console says so on the page: a part
-- payment is recorded and receipted and buys none until the balance is
-- paid. If this were not true the state above would be a broken payment
-- rather than an ordinary one, and the whole section would prove nothing.
select results_eq(
  $$ select receipt_number is not null from public.payments where id = '22000000-0000-4000-8000-000000171001'::uuid $$,
  $$ values (true) $$,
  'GL043/part-paid: the part payment took a receipt number like any other payment — this is ordinary practice, not a malformed row'
);

-- 176 — the fourth term has to exist before it can be frozen. A period
-- LENGTH was the one term still read live from `plans` when money arrives.
select has_column('public', 'memberships', 'duration_days',
  'GL043/part-paid: memberships records the duration a period is measured in, rather than reading it from plans when money arrives');

-- 177 — and it is what the membership was SOLD at: the plan 30 days.
-- Read through to_jsonb so that this assertion reports a clean failure
-- rather than aborting the transaction while the column does not exist.
select results_eq(
  $$ select to_jsonb(m)->>'duration_days' from public.memberships m where m.id = '22000000-0000-4000-8000-000000170080'::uuid $$,
  $$ values ('30'::text) $$,
  'GL043/part-paid: the membership records the 30 days of the plan it was sold on'
);

-- 178 — the measured exploit first move. Allowed on live Cloud today.
select throws_ok($$
  update public.memberships set price_paise = 100000 - 99000
   where id = '22000000-0000-4000-8000-000000170080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/part-paid: cutting the price of a membership that has taken real money but crossed no multiple of it is refused — money arriving is what freezes a term, not a period being granted');

-- 179
select throws_ok($$
  update public.memberships set price_paise = 200000
   where id = '22000000-0000-4000-8000-000000170080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/part-paid: raising it is refused too — the terms are frozen in both directions, as Section 15 already holds the granted case to');

-- 180
select throws_ok($$
  update public.memberships set currency = 'USD'
   where id = '22000000-0000-4000-8000-000000170080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/part-paid: re-denominating the membership is refused — the currency is half of what a price MEANS, and the money already on record was taken in the old one');

-- 181
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000170061'::uuid
   where id = '22000000-0000-4000-8000-000000170080'::uuid
$$, 'GL043'::char(5), null,
  'GL043/part-paid: repointing it at a 365-day plan is refused — a member who agreed to a month and paid half of it can otherwise be given a year, with two ordinary receipts in the ledger');

-- 182 — the recorded length, on the membership rather than on the plan.
-- ROUND NINE: the assertion and its SQLSTATE are unchanged; the REASON is
-- different. ADR-092 moved `duration_days` out of the family of terms
-- frozen by money ("GL043 now covers three terms — price, currency, plan —
-- not four") and made it a DERIVED fact: it may change only as part of a
-- plan change and only to what that plan says, whether or not money has
-- arrived. So this write is refused here for a reason that has nothing to
-- do with the money — Section 18 asserts the same refusal on a membership
-- that has taken nothing at all, where the money freeze cannot be what
-- answers. `GL043` is the code either way: the requirement left it open
-- (the length "belongs with `periods_granted`" reads toward GL044, and it
-- lives under the frozen-terms requirement, which reads toward GL043), and
-- the coordinator answered it to both blind authors at once — it is a term
-- of the membership and a reader chasing it looks where the other terms
-- are. That answer is going into the spec.
select throws_ok($$
  update public.memberships set duration_days = 3650
   where id = '22000000-0000-4000-8000-000000170080'::uuid
$$, 'GL043'::char(5), null,
  'derived length/part-paid: lengthening the membership own recorded duration is refused — a length is derived from the plan and never typed, so no session may write it except by changing the plan');

-- 183 — the state proof for all five attempts, in one comparison.
select results_eq(
  $$ select price_paise, currency, plan_id, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000170080'::uuid $$,
  $$ values (100000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000170060'::uuid, '30'::text) $$,
  'GL043/part-paid: refused AND unmoved — all four terms are exactly what the membership was sold at'
);

-- 184 — the second half of the measured exploit: one paisa.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171005'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170040'::uuid, '22000000-0000-4000-8000-000000170080'::uuid,
          1, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/part-paid: the one-paisa payment is recorded like any other — a refused term edit does not refuse the money that follows it');

-- 185 — legitimately green before and after: at the ORIGINAL price one
-- paisa was never going to buy anything. It is here because it is the
-- outcome ADR-090 measured as ten years, and an outcome assertion is what
-- survives a fix that closes the door by a different mechanism.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170080'::uuid $$,
  $$ values (0, (select d from today_t17)) $$,
  'GL043/part-paid: one paisa bought nothing and ends_on did not move a day — Rs 500.01 is not one whole multiple of Rs 1,000'
);

-- 186/187 — the scenario own words: a further payment SHALL buy only what
-- the ORIGINAL price says it buys. 50000 + 1 + 49999 is exactly the price.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171006'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170040'::uuid, '22000000-0000-4000-8000-000000170080'::uuid,
          49999, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/part-paid: the balance of the original price is recorded');

-- 187
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170080'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL043/part-paid: the balance bought exactly ONE period of the original 30 days at the original price — not ten, and not ten years'
);


-- ---------------------------------------------------------------------------
-- 17b (GL043) — the same part-paid window through the statement shapes a
-- rule written as a single-row guard does not see. Every previous defect in
-- this phase survived the single-row case and died on one of these.
-- Membership 170081 (part-paid), 170086 (no money at all) as its innocent
-- sibling.
-- ---------------------------------------------------------------------------

-- 188
select results_eq(
  $$ select periods_granted, price_paise from public.memberships where id = '22000000-0000-4000-8000-000000170081'::uuid $$,
  $$ values (0, 100000::bigint) $$,
  'GL043/shapes: this membership is part-paid too — half the price arrived, nothing granted'
);

-- 189
select throws_ok($$
  update public.memberships m set price_paise = p.price_paise - 99000
    from public.plans p
   where p.id = m.plan_id
     and m.id = '22000000-0000-4000-8000-000000170081'::uuid
$$, 'GL043'::char(5), null,
  'GL043/shapes: the price cut written as UPDATE ... FROM is refused — the new value arriving from a joined row rather than a literal changes nothing about what the rule has to see');

-- 190
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000170081'::uuid as id) s
     on m.id = s.id
   when matched then update set price_paise = 1000
$$, 'GL043'::char(5), null,
  'GL043/shapes: the price cut written as MERGE is refused');

-- 191
select throws_ok($$
  with moved as (
    update public.memberships set price_paise = 1000
     where id = '22000000-0000-4000-8000-000000170081'::uuid
    returning id
  ) select count(*) from moved
$$, 'GL043'::char(5), null,
  'GL043/shapes: the price cut hidden in a data-modifying CTE is refused — ADR-087 records this costume walking round a rule on this very table neighbour already');

-- 192 — and the recorded length through the same door, refused for the
-- derived-fact reason 182 gives rather than because money has arrived.
select throws_ok($$
  update public.memberships m set duration_days = p.duration_days * 100
    from public.plans p
   where p.id = m.plan_id
     and m.id = '22000000-0000-4000-8000-000000170081'::uuid
$$, 'GL043'::char(5), null,
  'derived length/shapes: the recorded duration lengthened by UPDATE ... FROM is refused');

-- 193
select results_eq(
  $$ select price_paise, to_jsonb(m)->>'duration_days' from public.memberships m where m.id = '22000000-0000-4000-8000-000000170081'::uuid $$,
  $$ values (100000::bigint, '30'::text) $$,
  'GL043/shapes: refused AND unmoved through all four shapes'
);

-- 194 — one statement, two memberships, only ONE of them part-paid. The
-- other has taken no money at all and would be free to change on its own.
--
-- SENT AS A GYM ADMIN FOR THE SAME REASON AS 134, AND FOUND BY LOOKING FOR
-- THE SHAPE RATHER THAN WAITING FOR THE FLAKE: this is a MIXED multi-row
-- statement, so under a non-admin claim its part-paid row reaches `GL043`
-- while its moneyless row falls through to `GL046`, and Postgres does not
-- guarantee which row a statement's row triggers fire for first. Refused
-- either way, nothing moves either way, but the SQLSTATE would be a coin
-- toss. `GL046` cannot fire for a gym admin, so as a manager `GL043` is the
-- only rule left and answers deterministically. What is asserted — a frozen
-- row anywhere in the set refuses the whole statement, and the innocent row
-- does not move — is untouched.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000170022')::text,
  true);

select throws_ok($$
  update public.memberships set price_paise = 1000
   where id in ('22000000-0000-4000-8000-000000170081'::uuid,
                '22000000-0000-4000-8000-000000170086'::uuid)
$$, 'GL043'::char(5), null,
  'GL043/shapes: one statement cutting the price of two memberships, only one of which has taken money, is refused — the frozen row is in the set and that is enough. Sent as a gym admin so GL043 is the only rule that can answer, exactly as at 134');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);

-- 195
select results_eq(
  $$ select id, price_paise from public.memberships
      where id in ('22000000-0000-4000-8000-000000170081'::uuid, '22000000-0000-4000-8000-000000170086'::uuid)
      order by id $$,
  $$ values ('22000000-0000-4000-8000-000000170081'::uuid, 100000::bigint),
            ('22000000-0000-4000-8000-000000170086'::uuid, 100000::bigint) $$,
  'GL043/shapes: NEITHER row moved — a refusal that aborted half a statement would be worse than the change it prevented'
);


-- ---------------------------------------------------------------------------
-- 17c (GL043) — money that arrived and was then refunded IN FULL. Nobody
-- has tried this. The total a period is scored against counts money that
-- ARRIVED — paid, refunded and reversed — precisely so that it never falls,
-- so a membership whose only payment was refunded must stay FROZEN. If it
-- thawed, the re-pricing door would be for sale at the price of a refund.
-- Membership 170082.
-- ---------------------------------------------------------------------------

-- 196 — the refund itself, as an ordinary status move.
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-000000171003'::uuid
$$, 'GL043/refunded: refunding the only payment on the membership is an ordinary paid -> refunded move');

-- 197
select throws_ok($$
  update public.memberships set price_paise = 1000
   where id = '22000000-0000-4000-8000-000000170082'::uuid
$$, 'GL043'::char(5), null,
  'GL043/refunded: the terms of a membership whose only money has been refunded in full are STILL frozen — the total counts refunded money, so it is still being scored against the price');

-- 198
select results_eq(
  $$ select price_paise, periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000170082'::uuid $$,
  $$ values (100000::bigint, 0) $$,
  'GL043/refunded: refused AND unmoved'
);

-- 199
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171007'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170042'::uuid, '22000000-0000-4000-8000-000000170082'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/refunded: a further full payment is recorded');

-- 200 — and it is scored against a total that still counts the refunded
-- Rs 500: 150000 at a price of 100000 is one period, not two.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170082'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL043/refunded: one period, of the original 30 days at the original price — the refunded money still counts toward the total and the terms it is counted against never moved'
);


-- ---------------------------------------------------------------------------
-- 17d (GL043) — the duration a period is measured in is the MEMBERSHIP,
-- not the plan. `plans_tenant_write` is FOR ALL on is_gym_admin(), so one
-- manager statement setting duration_days = 3650 moved ends_on 3650 days on
-- every membership sold on that plan at once. The plan edit is legitimate
-- and must stay legal; what must change is that it applies to the NEXT
-- membership and to nothing already sold. Membership 170083 (sold at 30
-- days, one period earned) and 170089 (created afterwards). Plan 170063 is
-- used by these two and nothing else.
-- ---------------------------------------------------------------------------

-- 201
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170083'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL043/duration: sold on a 30-day plan and paid in full — one period, ends_on 30 days out'
);

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000170022')::text,
  true);
set local role authenticated;

-- 202 — the legitimate act, which the fix must not punish. Freezing the
-- plans row instead of recording the term would stop a gym re-lengthening
-- a plan for future sales, which it must be able to do.
select lives_ok($$
  update public.plans set duration_days = 3650
   where id = '22000000-0000-4000-8000-000000170063'::uuid
$$, 'GL043/duration: a gym admin lengthening one of their own plans is allowed — editing a plan is ordinary work and the fix must not take it away');

-- 203
select results_eq(
  $$ select duration_days from public.plans where id = '22000000-0000-4000-8000-000000170063'::uuid $$,
  $$ values (3650) $$,
  'GL043/duration: the plan edit LANDED — allowed and applied, not allowed and silently dropped'
);

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);
set local role authenticated;

-- 204
select results_eq(
  $$ select to_jsonb(m)->>'duration_days' from public.memberships m where m.id = '22000000-0000-4000-8000-000000170083'::uuid $$,
  $$ values ('30'::text) $$,
  'GL043/duration: the membership already sold still records the 30 days it was sold at — a plan edit is not a term edit on somebody else contract');

-- 205
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171008'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170043'::uuid, '22000000-0000-4000-8000-000000170083'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/duration: an ordinary renewal after the plan was lengthened is recorded');

-- 206 — the scenario own words: memberships already sold SHALL keep the
-- length they were sold at. Measured today: this renewal moves ends_on 3650
-- days instead of 30.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170083'::uuid $$,
  $$ values (2, (select d from today_t17) + 60) $$,
  'GL043/duration: the renewal bought 30 days, the length this membership was SOLD at — not the 3650 the plan now says');

-- 207 — and the other half of the same scenario: only memberships created
-- afterwards use the new one. A fix that froze the plan row, or that made
-- the duration unwritable, would fail here rather than above.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-000000170089'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170049'::uuid, '22000000-0000-4000-8000-000000170063'::uuid,
          'active', (select d from today_t17), (select d from today_t17), 100000)
$$, 'GL043/duration: a membership sold AFTER the plan edit is created normally');

-- 208
select results_eq(
  $$ select to_jsonb(m)->>'duration_days' from public.memberships m where m.id = '22000000-0000-4000-8000-000000170089'::uuid $$,
  $$ values ('3650'::text) $$,
  'GL043/duration: it records the NEW length — which is what editing a plan should mean');

-- 209
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171009'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170049'::uuid, '22000000-0000-4000-8000-000000170089'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/duration: it is paid for in full');

-- 210 — legitimately green before and after: the new membership gets the
-- new length either way. It is here because it is the half of the scenario
-- a too-broad fix breaks.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170089'::uuid $$,
  $$ values (1, (select d from today_t17) + 3650) $$,
  'GL043/duration: and it runs for the new 3650 days — the plan edit reached the membership sold after it and none sold before it'
);


-- ---------------------------------------------------------------------------
-- 17e (GL043) — what is NOT money arriving. `created`, `pending` and
-- `failed` are money still held or money that never came; the total counts
-- `paid`, `refunded` and `reversed`. So the terms must still be FREE, and
-- must freeze the moment the same payment row becomes paid — the rule is
-- keyed on what the money IS now, not on what it was written as. Membership
-- 170084 (created -> paid) and 170091 (pending -> failed).
-- ---------------------------------------------------------------------------

-- 211
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171010'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170044'::uuid, '22000000-0000-4000-8000-000000170084'::uuid,
          50000, 'created', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/not-yet-money: a payment is opened at created against the membership');

-- 212
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000170022')::text,
  true);

select lives_ok($$
  update public.memberships set price_paise = 80000
   where id = '22000000-0000-4000-8000-000000170084'::uuid
$$, 'GL043/not-yet-money: a gym admin correcting the price while the only payment is still created is allowed — money still held is not money that has arrived');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);


-- 213
select results_eq(
  $$ select price_paise, periods_granted from public.memberships where id = '22000000-0000-4000-8000-000000170084'::uuid $$,
  $$ values (80000::bigint, 0) $$,
  'GL043/not-yet-money: the correction LANDED'
);

-- 214 — the same row becomes money.
select lives_ok($$
  update public.payments set status = 'paid'
   where id = '22000000-0000-4000-8000-000000171010'::uuid
$$, 'GL043/not-yet-money: the payment is then taken, created -> paid');

-- 215
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170084'::uuid $$,
  $$ values (0, (select d from today_t17)) $$,
  'GL043/not-yet-money: Rs 500 against a Rs 800 price grants nothing — the part-paid window again, reached by an UPDATE rather than an INSERT'
);

-- 216 — and now the door is shut, on the same row that left it open.
select throws_ok($$
  update public.memberships set price_paise = 1000
   where id = '22000000-0000-4000-8000-000000170084'::uuid
$$, 'GL043'::char(5), null,
  'GL043/not-yet-money: once that same payment has become paid the price is frozen — the freeze is keyed on what the money is NOW, not on the status it was written at');

-- 217
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000170084'::uuid $$,
  $$ values (80000::bigint) $$,
  'GL043/not-yet-money: refused AND unmoved at the corrected price'
);

-- 218/219/220 — money that never arrives at all.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171011'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170051'::uuid, '22000000-0000-4000-8000-000000170091'::uuid,
          50000, 'pending', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/never-arrived: a pending payment is opened');

-- 219
select lives_ok($$
  update public.payments set status = 'failed'
   where id = '22000000-0000-4000-8000-000000171011'::uuid
$$, 'GL043/never-arrived: and it fails');

-- 220
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000170022')::text,
  true);

select lives_ok($$
  update public.memberships
     set price_paise = 50000, currency = 'USD', plan_id = '22000000-0000-4000-8000-000000170062'::uuid
   where id = '22000000-0000-4000-8000-000000170091'::uuid
$$, 'GL043/never-arrived: a membership whose only payment failed is still fully editable BY A GYM ADMIN — nothing has been scored against its terms, so nothing is being rewritten');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);


-- 221
select results_eq(
  $$ select price_paise, currency, plan_id from public.memberships where id = '22000000-0000-4000-8000-000000170091'::uuid $$,
  $$ values (50000::bigint, 'USD'::text, '22000000-0000-4000-8000-000000170062'::uuid) $$,
  'GL043/never-arrived: and the edit LANDED — allowed and applied'
);


-- ---------------------------------------------------------------------------
-- 17f (GL043, the permitted side) — a membership against which no money has
-- arrived at all stays editable in its three terms, and the money that
-- follows is scored against the corrected ones. A fix that is too broad
-- passes every refusal above and fails here. Membership 170085.
--
-- ROUND NINE REPAIRED THIS SUBSECTION, AND IT IS THE ONE PLACE IN THIS FILE
-- THAT ASSERTED THE DEFECT. As written it had a front desk type
-- `duration_days = 90` onto a membership whose plan says 365 and asserted
-- that the following payment bought 90 days, "which is the whole point of
-- recording the term". ADR-092 records what that permission costs when it
-- is used on its own rather than alongside a plan change: sell a 30-day
-- membership at Rs 1,500, `update memberships set duration_days = 3650`,
-- take the ordinary Rs 1,500 — 3,650 days, from any front-desk browser
-- session, and undetectable afterwards because the row it leaves is fully
-- self-consistent. The author was not wrong; the contract was.
--
-- The statement itself is UNCHANGED and still allowed — it carries a
-- legitimate plan change, and a length riding along with one is not a
-- negotiation, it is a value the plan already decides. What changed is what
-- the length becomes: the NEW PLAN's 365, not the typed 90, and the payment
-- that follows buys 365 days. The typed value is overridden rather than
-- refused for the same reason a created membership's own named length is
-- (the requirement's first scenario): the write it rides on is legitimate
-- and the column is derived from it. A write to the column WITHOUT a plan
-- change is refused outright, which is Section 18's business.
-- ---------------------------------------------------------------------------

-- 222
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000170022')::text,
  true);

select lives_ok($$
  update public.memberships
     set price_paise = 75000,
         currency = 'USD',
         plan_id = '22000000-0000-4000-8000-000000170061'::uuid,
         duration_days = 90
   where id = '22000000-0000-4000-8000-000000170085'::uuid
$$, 'GL043/permitted: a gym admin correcting the price, the currency and the plan at once before any money has arrived is allowed — nothing has been scored yet');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000170001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000170021')::text,
  true);


-- 223 — the price the caller named STANDS (a plan change re-derives the
-- price, unless the correction names one of its own, which this does); the
-- length does not, because a length is not a negotiated number.
select results_eq(
  $$ select price_paise, currency, plan_id, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000170085'::uuid $$,
  $$ values (75000::bigint, 'USD'::text, '22000000-0000-4000-8000-000000170061'::uuid, '365'::text) $$,
  'GL043/permitted: the negotiated price and the currency landed as typed, and the length landed as the NEW PLAN says — 365, not the 90 the same statement asked for'
);

-- 224
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171012'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170045'::uuid, '22000000-0000-4000-8000-000000170085'::uuid,
          75000, 'USD', 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/permitted: a payment of the corrected price, in the corrected currency, is recorded');

-- 225 — and scored against the corrected terms: one period of the plan's
-- own 365 days at the negotiated price. The typed 90 buys nothing anywhere.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170085'::uuid $$,
  $$ values (1, (select d from today_t17) + 365) $$,
  'GL043/permitted: one period of the plan''s 365 days — a desk that types a length of its own gets the plan''s, which is what "derived, never negotiated" has to mean at the moment money is scored'
);


-- ---------------------------------------------------------------------------
-- 17g (GL043) — the first payment and a term edit in the SAME statement.
-- Measured on live Cloud in the shape that combines this with 17h: Rs 3,000
-- refunded plus one paisa reversed plus Rs 500 paid, with the price cut to
-- one paisa in the same data-modifying CTE, granted 350001 periods and left
-- ends_on at the year 30774. Membership 170087, which has taken nothing
-- until this statement.
-- ---------------------------------------------------------------------------

-- 226
select throws_ok($$
  with taken as (
    insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
    values ('22000000-0000-4000-8000-000000171013'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
            '22000000-0000-4000-8000-000000170047'::uuid, '22000000-0000-4000-8000-000000170087'::uuid,
            50000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
    returning id
  ), cut as (
    update public.memberships set price_paise = 1
     where id = '22000000-0000-4000-8000-000000170087'::uuid
    returning id
  ) select count(*) from taken
$$, 'GL043'::char(5), null,
  'GL043/same-statement: taking the first payment and cutting the price in ONE statement is refused — by the end of that statement money has arrived and a term has moved, which is exactly what the requirement forbids');

-- 227
select results_eq(
  $$ select m.price_paise, m.periods_granted,
            (select count(*)::int from public.payments p where p.id = '22000000-0000-4000-8000-000000171013'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000170087'::uuid $$,
  $$ values (100000::bigint, 0, 0) $$,
  'GL043/same-statement: refused whole — the price did not move, nothing was granted, and the payment that shared the statement does not exist either'
);


-- ---------------------------------------------------------------------------
-- 17h (GL039) — a payment does not arrive already refunded. Both statuses
-- count toward the total a period is scored against, neither extends
-- anything at the time and neither takes a receipt number, so a payment
-- written straight to `refunded` puts grant credit on the books that no
-- receipt names and nothing has granted, waiting for any later payment to
-- cash it in. Measured: both inserts ALLOWED today, both taking a null
-- receipt number. Membership 170088.
-- ---------------------------------------------------------------------------

-- 228
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171014'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170088'::uuid,
          300000, 'refunded', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL039'::char(5), null,
  'GL039: a payment recorded straight at refunded is refused — a payment is recorded and THEN refunded, it does not arrive that way');

-- 229
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171015'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170088'::uuid,
          200000, 'reversed', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL039'::char(5), null,
  'GL039: and straight at reversed, which presupposes an earlier status just as plainly');

-- 230
select results_eq(
  $$ select count(*)::int from public.payments
      where id in ('22000000-0000-4000-8000-000000171014'::uuid, '22000000-0000-4000-8000-000000171015'::uuid) $$,
  $$ values (0) $$,
  'GL039: refused AND nothing written — neither row exists, so neither is sitting in the total waiting to be cashed in'
);

-- 231/232 — the harm, stated as an outcome. ADR-090 measured a Rs 3,000
-- refunded payment inserted directly and then one paisa granting three
-- periods.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171016'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170088'::uuid,
          1, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL039: the one paisa that would have cashed that credit in is recorded like any other payment');

-- 232
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170088'::uuid $$,
  $$ values (0, (select d from today_t17)) $$,
  'GL039: and it bought NOTHING — there was no phantom Rs 5,000 on the books for it to cross a multiple against');

-- 233/234 — the permitted path the requirement names: recorded, and then
-- refunded.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171017'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170088'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL039/permitted: an ordinary full payment is recorded');

-- 234
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170088'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL039/permitted: it granted its period — GL039 refuses a status, not a payment');

-- 235
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-000000171017'::uuid
$$, 'GL039/permitted: refunding it afterwards is allowed — this is the route a refunded payment is supposed to reach that status by');

-- 236
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170088'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL039/permitted: and the refund did not pull the extension back — the total counts money that arrived, which is what makes crossing a multiple mean anything'
);

-- 237/238 — GL039 must refuse two statuses, not a shape. A failed payment
-- is still recordable, and still counts for nothing.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171018'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170048'::uuid, '22000000-0000-4000-8000-000000170088'::uuid,
          500000, 'failed', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL039/permitted: a payment recorded at failed is still allowed — the rule names two statuses, not every status a caller may supply');

-- 238
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170088'::uuid $$,
  $$ values (1, (select d from today_t17) + 30) $$,
  'GL039/permitted: and Rs 5,000 of failed money bought nothing, because failed money never arrived'
);


-- ---------------------------------------------------------------------------
-- 17i (GL043) — money in a currency the membership is not priced in. It
-- buys nothing, because the total sums the membership own currency — but
-- HAS money arrived? The requirement prose says "WHERE any money has
-- arrived against a membership", and this is a paid payment naming the
-- membership; its scenario list never mentions the case. The prose is what
-- is asserted here, and the report says so, because re-denominating the
-- membership is exactly what would make that foreign money start scoring —
-- which is the harm the currency being a frozen term exists to prevent.
-- Membership 170090.
-- ---------------------------------------------------------------------------

-- 239
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000171019'::uuid, '22000000-0000-4000-8000-000000170001'::uuid,
          '22000000-0000-4000-8000-000000170050'::uuid, '22000000-0000-4000-8000-000000170090'::uuid,
          100000, 'USD', 'paid', 'cash', '22000000-0000-4000-8000-000000170021'::uuid)
$$, 'GL043/foreign: a paid payment in a currency the membership is not priced in is recorded');

-- 240
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170090'::uuid $$,
  $$ values (0, (select d from today_t17)) $$,
  'GL043/foreign: it granted no period — the total sums the membership own currency (MNY-002)'
);

-- 241
select throws_ok($$
  update public.memberships set currency = 'USD'
   where id = '22000000-0000-4000-8000-000000170090'::uuid
$$, 'GL043'::char(5), null,
  'GL043/foreign: re-denominating the membership into the currency that money came in is refused — money HAS arrived against it, and this edit is the single act that would make Rs 0 of scored money become a full period');

-- 242
select results_eq(
  $$ select currency, periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000170090'::uuid $$,
  $$ values ('INR'::text, 0, (select d from today_t17)) $$,
  'GL043/foreign: refused AND unmoved — still priced in INR, still granted nothing'
);



-- ===========================================================================
-- SECTION 18 (ADR-092) — a period's length is DERIVED, never negotiated, and
-- a plan correction carries the price with it. Tenant 18. Assertions 243-290.
--
-- Round nine, and the second consecutive round in which the requirement
-- written to close a hole opened the same hole by another route. Round
-- eight's requirement named the harm — "create a membership naming
-- `duration_days = 3650`, pay the ordinary price, get ten years" — and three
-- lines below mandated the identical outcome in two statements instead of
-- one: "Correcting the length before any money arrives ... SHALL be allowed
-- and SHALL land, and a payment SHALL be scored against the corrected
-- length." Section 17f of this file is where this suite wrote that down, and
-- it has been repaired in place; its own header says so.
--
-- Measured on live Cloud before writing a line, all in throwaway
-- begin...rollback transactions, all from an ordinary front-desk session
-- against a 30-day Rs 1,500 membership with NO money on it:
--
--   * `update memberships set duration_days = 3650` — ALLOWED, lands as
--     3650. The ordinary Rs 1,500 that follows then grants ONE period of
--     3650 days. Also through MERGE.
--   * a PLAN-ONLY correction, Monthly -> Annual, re-derives the length
--     (30 -> 365) and leaves the price at the Monthly's Rs 1,500. One
--     Rs 12,000 Annual fee then buys `floor(1200000/150000)` = EIGHT periods
--     of 365 days — measured `periods_granted = 8`, `ends_on` 2920 days out.
--   * a plan change that also NAMES a price keeps the named price and
--     re-derives the length — the one case already correct, and 253-256
--     hold it there so the price re-derivation does not stomp it.
--   * a plan change on a membership that has taken money is already refused
--     with `GL043`, and a same-value write to `duration_days` is already
--     allowed. Both must stay exactly as they are.
--
-- WHY THIS SECTION USES MEMBERSHIPS WITH NO MONEY ON THEM. Every existing
-- refusal in this file that touches a term is on a membership that has taken
-- money, so GL043 could be what answers. The rule this section is about is
-- not about money at all: a length may change only as part of a plan change,
-- at any time, whether or not money has arrived. Asserting it on a moneyless
-- membership is the only way to tell the new rule apart from the old one —
-- on a part-paid row a passing test proves nothing about which rule fired.
--
-- WHAT IS ATTACKED. The plan-only correction in both directions and what the
-- following payment BUYS, not merely that the correction was allowed (18a,
-- 18b) — ADR-078: an assertion that only checks "allowed" passes with the
-- rule deleted, which is exactly how the Rs 12,000 defect survived a round.
-- The negotiated-price correction, which must survive the re-derivation
-- (18c). A length typed in the same statement as a legitimate plan change,
-- which lands as the PLAN's (18d). Every statement shape that writes the
-- length without a plan change — plain UPDATE, MERGE, a data-modifying CTE,
-- UPDATE ... FROM, a multi-row statement, and UPDATE ... FROM giving two
-- rows two DIFFERENT values (18e) — with the permitted same-value writes in
-- the same subsection, because a rule that refuses those breaks every
-- column-listing update in the product. The whole harm end to end (18f). A
-- plan in another tenant, asserting that the refusal re-derived nothing
-- either (18g). A plan change naming a new price AND a new length on a
-- membership that has taken money (18h). And the permitted side that has
-- nothing to do with length: freeze, unfreeze, a discount, a note, an
-- ordinary renewal, and a cancellation (18i).
--
-- THE SQLSTATE IS `GL043`, ANSWERED BY THE CONTRACT RATHER THAN GUESSED AT.
-- The requirement left it genuinely open and this section was first written
-- with `null::char(5)` for exactly that reason: the length "belongs with
-- `periods_granted` rather than with the price" reads toward `GL044`, while
-- the rule lives under the frozen-terms requirement, which reads toward
-- `GL043` — and ADR-092 says the column "joins `periods_granted` (`GL044`)"
-- without ever saying that is the code it answers with. The coordinator
-- answered it to this author and the holdout author at the same time so that
-- neither had to guess and the two could not diverge: it is a term of the
-- membership, a reader chasing it looks where the other terms are, so
-- `GL043`. Nothing else about the rule moved — refused rather than ignored,
-- whether or not money has arrived, and the length unchanged afterwards.
-- Every derived-length refusal below asserts `GL043` and that the value did
-- not move. The one refusal here that is NOT this rule's — 275, another
-- gym's plan, which ADR-052's composite foreign key answers — stays
-- `null::char(5)`, as assertion 162 already does for the same reason.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000180001'::uuid, 'PayRec Gym 18', 'PYR22I'),
  ('22000000-0000-4000-8000-000000180002'::uuid, 'PayRec Gym 18B', 'PYR22J');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000180011'::uuid, '22000000-0000-4000-8000-000000180001'::uuid, 'G18 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000180021'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'front_desk', 'T18 Desk'),
  ('22000000-0000-4000-8000-000000180022'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'gym_manager', 'T18 Manager');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000180040'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 PlanOnlyUp', '+912200180040'),
  ('22000000-0000-4000-8000-000000180041'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 PlanOnlyDown', '+912200180041'),
  ('22000000-0000-4000-8000-000000180042'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 Negotiated', '+912200180042'),
  ('22000000-0000-4000-8000-000000180043'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 TypedAlongside', '+912200180043'),
  ('22000000-0000-4000-8000-000000180044'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 Shapes', '+912200180044'),
  ('22000000-0000-4000-8000-000000180045'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 Sibling', '+912200180045'),
  ('22000000-0000-4000-8000-000000180046'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 EndToEnd', '+912200180046'),
  ('22000000-0000-4000-8000-000000180047'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 ForeignPlan', '+912200180047'),
  ('22000000-0000-4000-8000-000000180048'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 PartPaid', '+912200180048'),
  ('22000000-0000-4000-8000-000000180049'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180011'::uuid, 'M18 Ordinary', '+912200180049');

-- The three lengths are deliberately paired with three DIFFERENT prices, and
-- that is the whole difference from Section 16's fixture (which priced every
-- plan identically so only the duration could move). The Rs 12,000 defect is
-- a price that did NOT follow a plan change, so a price per plan is the only
-- way to see it. 180063 belongs to tenant 18B and tenant 18 may not point at
-- it (275).
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000180060'::uuid, '22000000-0000-4000-8000-000000180001'::uuid, 'G18 Monthly (30d)', 30, 150000),
  ('22000000-0000-4000-8000-000000180061'::uuid, '22000000-0000-4000-8000-000000180001'::uuid, 'G18 Annual (365d)', 365, 1200000),
  ('22000000-0000-4000-8000-000000180062'::uuid, '22000000-0000-4000-8000-000000180001'::uuid, 'G18 Weekly (7d)', 7, 50000),
  ('22000000-0000-4000-8000-000000180063'::uuid, '22000000-0000-4000-8000-000000180002'::uuid, 'G18B Annual (365d)', 365, 1200000);

create temp table today_t18 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000180001'::uuid;

grant select on today_t18 to public;

-- Every membership starts at `ends_on = today` so one period is
-- `today + <its own recorded duration>` with nothing else in the arithmetic,
-- every one is priced at its plan's own list price, and none names a
-- duration — the length is the plan's from the moment of sale, which the
-- fixture assertions below re-read rather than assume.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000180080'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180040'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180081'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180041'::uuid, '22000000-0000-4000-8000-000000180061'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 1200000),
  ('22000000-0000-4000-8000-000000180082'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180042'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180083'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180043'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180084'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180044'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180085'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180045'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180086'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180046'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180087'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180047'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180088'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180048'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000),
  ('22000000-0000-4000-8000-000000180089'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180049'::uuid, '22000000-0000-4000-8000-000000180060'::uuid,
   'active', (select d from today_t18), (select d from today_t18), 150000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000180021')::text,
  true);
set local role authenticated;

-- The only two memberships in this section that carry money, both earned
-- from ordinary front-desk work: 180088 is part-paid (half of Rs 1,500) and
-- 180089 is paid in full. Unscored — the fixture, not the claim; each one's
-- state is asserted where its own subsection begins. Eight memberships have
-- no money at all, which is the point (see the header).
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000181001'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180048'::uuid, '22000000-0000-4000-8000-000000180088'::uuid,
   75000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid),
  ('22000000-0000-4000-8000-000000181002'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
   '22000000-0000-4000-8000-000000180049'::uuid, '22000000-0000-4000-8000-000000180089'::uuid,
   150000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid);


-- ---------------------------------------------------------------------------
-- 18a (ADR-092) — the plan-only correction, which is what a desk actually
-- does when it has sold the wrong plan, and which is tested nowhere in
-- either suite: every existing permitted-side assertion corrects the price
-- and the plan TOGETHER, which is exactly how this survived. Membership
-- 180080, sold Monthly (30 days, Rs 1,500), no money on it.
-- ---------------------------------------------------------------------------

-- 243
select results_eq(
  $$ select periods_granted, price_paise, to_jsonb(m)->>'duration_days', m.plan_id
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180080'::uuid $$,
  $$ values (0, 150000::bigint, '30'::text, '22000000-0000-4000-8000-000000180060'::uuid) $$,
  'derived length/plan-only: sold on the Monthly plan and untouched — 30 days recorded, Rs 1,500, nothing granted, no money'
);

-- 244
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000180022')::text,
  true);

select lives_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000180061'::uuid
   where id = '22000000-0000-4000-8000-000000180080'::uuid
$$, 'derived length/plan-only: correcting a mis-sold Monthly to the Annual plan, naming nothing else, is allowed — no money has arrived');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000180021')::text,
  true);


-- 245 — the fix. Measured today: the length follows the plan and the price
-- does not, which is the whole defect.
select results_eq(
  $$ select price_paise, to_jsonb(m)->>'duration_days', m.plan_id
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180080'::uuid $$,
  $$ values (1200000::bigint, '365'::text, '22000000-0000-4000-8000-000000180061'::uuid) $$,
  'derived length/plan-only: BOTH terms came from the new plan — Rs 12,000 and 365 days. Price and length come from the same plan or from neither'
);

-- 246
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181003'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180040'::uuid, '22000000-0000-4000-8000-000000180080'::uuid,
          1200000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'derived length/plan-only: one ordinary Annual fee is recorded against the corrected membership');

-- 247 — what the payment BUYS, which is the assertion the requirement's own
-- scenario was missing (ADR-078: "allowed" alone passes with the rule
-- deleted). Measured today: periods_granted = 8 and ends_on 2920 days out,
-- because floor(1200000 / 150000) is eight periods of 365 days.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180080'::uuid $$,
  $$ values (1, (select d from today_t18) + 365) $$,
  'derived length/plan-only: one Annual fee bought exactly ONE year — not the eight periods of 365 days (2,920) that a re-derived length over a Monthly price buys'
);


-- ---------------------------------------------------------------------------
-- 18b (ADR-092) — the same correction downward, which fails silently in the
-- other direction: if the price does not follow the plan, an Annual
-- corrected to Monthly keeps a Rs 12,000 price and the member's ordinary
-- Rs 1,500 buys ZERO days while being receipted. That is ADR-088's named
-- harm reached through a plan correction. Membership 180081, sold Annual,
-- no money.
-- ---------------------------------------------------------------------------

-- 248
select results_eq(
  $$ select periods_granted, price_paise, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180081'::uuid $$,
  $$ values (0, 1200000::bigint, '365'::text) $$,
  'derived length/plan-only down: sold on the Annual plan — Rs 12,000, 365 days, nothing granted'
);

-- 249
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000180022')::text,
  true);

select lives_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000180060'::uuid
   where id = '22000000-0000-4000-8000-000000180081'::uuid
$$, 'derived length/plan-only down: correcting a mis-sold Annual to Monthly, naming nothing else, is allowed to a gym admin');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000180021')::text,
  true);


-- 250
select results_eq(
  $$ select price_paise, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180081'::uuid $$,
  $$ values (150000::bigint, '30'::text) $$,
  'derived length/plan-only down: the price came down with the length — a correction that moves one and not the other is what makes an ordinary payment buy the wrong thing'
);

-- 251
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181004'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180041'::uuid, '22000000-0000-4000-8000-000000180081'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'derived length/plan-only down: the ordinary Monthly fee is recorded');

-- 252 — measured today: the price is still Rs 12,000, so Rs 1,500 is not one
-- whole multiple of it, nothing is granted, ends_on does not move, and the
-- receipt is issued anyway.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180081'::uuid $$,
  $$ values (1, (select d from today_t18) + 30) $$,
  'derived length/plan-only down: it bought a month — rather than buying nothing at all against a price the correction left behind, silently, with the money receipted'
);


-- ---------------------------------------------------------------------------
-- 18c (ADR-092) — the negotiated price survives the re-derivation. A plan
-- change re-derives the price UNLESS the correction names one in the same
-- statement, which keeps a negotiated price possible — the one of the two a
-- desk legitimately sets by hand. A fix that re-derives unconditionally
-- passes 18a and 18b and fails here. Membership 180082, no money.
-- ---------------------------------------------------------------------------

-- 253
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000180022')::text,
  true);

select lives_ok($$
  update public.memberships
     set plan_id = '22000000-0000-4000-8000-000000180061'::uuid,
         price_paise = 900000
   where id = '22000000-0000-4000-8000-000000180082'::uuid
$$, 'derived length/negotiated: correcting the plan and naming a price of its own in the same statement is allowed to a gym admin');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000180021')::text,
  true);


-- 254
select results_eq(
  $$ select price_paise, to_jsonb(m)->>'duration_days', m.plan_id
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180082'::uuid $$,
  $$ values (900000::bigint, '365'::text, '22000000-0000-4000-8000-000000180061'::uuid) $$,
  'derived length/negotiated: the named Rs 9,000 STANDS and the length is still the new plan''s 365 — a price is negotiated, a length is not'
);

-- 255
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181005'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180042'::uuid, '22000000-0000-4000-8000-000000180082'::uuid,
          900000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'derived length/negotiated: the negotiated fee is recorded');

-- 256
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180082'::uuid $$,
  $$ values (1, (select d from today_t18) + 365) $$,
  'derived length/negotiated: it bought exactly one year at the negotiated price — one period, not the one-and-a-third a re-derived Rs 12,000 price would have made of it'
);


-- ---------------------------------------------------------------------------
-- 18d (ADR-092) — a length typed in the SAME statement as a legitimate plan
-- change. This is the one place the corrected contract still leaves a real
-- choice and the report says so: "may change only as part of a plan change,
-- and ONLY TO WHAT THAT PLAN SAYS" can be read as refusing a statement that
-- names a different value, or as overriding it. It is asserted here as an
-- override, on the requirement's own parallel: its "Correcting a mis-sold
-- plan at a negotiated price" scenario says that a named PRICE stands "and
-- the length SHALL still be the new plan's" — the length losing to the plan
-- in a statement where the price wins is the shape the requirement draws.
-- Membership 180083, no money.
-- ---------------------------------------------------------------------------

-- 257
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000180022')::text,
  true);

select lives_ok($$
  update public.memberships
     set plan_id = '22000000-0000-4000-8000-000000180062'::uuid,
         duration_days = 3650
   where id = '22000000-0000-4000-8000-000000180083'::uuid
$$, 'derived length/alongside: a plan correction carrying a typed length is allowed — the write it rides on is legitimate');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000180001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000180021')::text,
  true);


-- 258 — and the length is the WEEKLY plan's 7 days, not the typed 3650; the
-- price is re-derived with it, since this statement named none.
select results_eq(
  $$ select to_jsonb(m)->>'duration_days', m.price_paise, m.plan_id
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180083'::uuid $$,
  $$ values ('7'::text, 50000::bigint, '22000000-0000-4000-8000-000000180062'::uuid) $$,
  'derived length/alongside: the length landed as the new plan''s 7 days and NOT as the 3650 typed beside it, and the price came from the same plan'
);

-- 259
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181006'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180043'::uuid, '22000000-0000-4000-8000-000000180083'::uuid,
          50000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'derived length/alongside: the Weekly fee is recorded');

-- 260 — the outcome, which is where a typed length that quietly survived
-- would show up whatever the mechanism.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180083'::uuid $$,
  $$ values (1, (select d from today_t18) + 7) $$,
  'derived length/alongside: one week of gym for a week''s money — a typed length buys nothing anywhere, in any statement'
);


-- ---------------------------------------------------------------------------
-- 18e (ADR-092) — every shape that writes the length WITHOUT a plan change.
-- Membership 180084 and its sibling 180085, neither of which has taken a
-- paisa: GL043 cannot be what refuses these, so a refusal here is the
-- derived rule and nothing else. Every one of these shapes is ALLOWED on
-- live Cloud today and lands the value it names.
--
-- The last three assertions are the permitted side of the same rule, in the
-- same subsection deliberately: a rule that refuses a write which cannot
-- move the value breaks every column-listing update an ORM sends, and this
-- project has shipped the too-broad shape three times this phase.
-- ---------------------------------------------------------------------------

-- 261
select results_eq(
  $$ select periods_granted, to_jsonb(m)->>'duration_days',
            (select count(*)::int from public.payments p where p.membership_id = m.id)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180084'::uuid $$,
  $$ values (0, '30'::text, 0) $$,
  'derived length/shapes: 30 days recorded, nothing granted, and NOT ONE PAYMENT against it — so nothing below can be refused by the money freeze'
);

-- 262
select throws_ok($$
  update public.memberships set duration_days = 3650
   where id = '22000000-0000-4000-8000-000000180084'::uuid
$$, 'GL043'::char(5), null,
  'derived length/shapes: the plain UPDATE is refused — refused, not ignored; silently discarding the write is the failure this codebase asserts against and a round-eight draft was caught doing exactly that');

-- 263
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000180084'::uuid as id) s
     on m.id = s.id
   when matched then update set duration_days = 3650
$$, 'GL043'::char(5), null,
  'derived length/shapes: the same write as MERGE is refused — measured ALLOWED on live Cloud today, landing 999 days on a membership nobody paid');

-- 264
select throws_ok($$
  with lengthened as (
    update public.memberships set duration_days = 3650
     where id = '22000000-0000-4000-8000-000000180084'::uuid
    returning id
  ) select count(*) from lengthened
$$, 'GL043'::char(5), null,
  'derived length/shapes: hidden in a data-modifying CTE it is refused — ADR-087''s third costume, tried against the derived rule');

-- 265
select throws_ok($$
  update public.memberships m set duration_days = p.duration_days * 100
    from public.plans p
   where p.id = m.plan_id
     and m.id = '22000000-0000-4000-8000-000000180084'::uuid
$$, 'GL043'::char(5), null,
  'derived length/shapes: UPDATE ... FROM is refused — a value computed from the plan''s own duration is still not what the plan SAYS, and a rule that only inspects literals would let this through');

-- 266
select throws_ok($$
  update public.memberships set duration_days = 3650
   where id in ('22000000-0000-4000-8000-000000180084'::uuid,
                '22000000-0000-4000-8000-000000180085'::uuid)
$$, 'GL043'::char(5), null,
  'derived length/shapes: one statement lengthening two memberships is refused');

-- 267 — two rows, two DIFFERENT values, in one statement. A rule that reads
-- one representative new value per statement rather than per row sees a
-- single plausible number here and lets the other one past.
select throws_ok($$
  update public.memberships m set duration_days = v.dd
    from (values ('22000000-0000-4000-8000-000000180084'::uuid, 3650),
                 ('22000000-0000-4000-8000-000000180085'::uuid, 7)) as v(id, dd)
   where m.id = v.id
$$, 'GL043'::char(5), null,
  'derived length/shapes: UPDATE ... FROM giving the two rows two DIFFERENT lengths is refused — neither of them is the length either membership''s plan says');

-- 268
select results_eq(
  $$ select id, to_jsonb(m)->>'duration_days' from public.memberships m
      where id in ('22000000-0000-4000-8000-000000180084'::uuid, '22000000-0000-4000-8000-000000180085'::uuid)
      order by id $$,
  $$ values ('22000000-0000-4000-8000-000000180084'::uuid, '30'::text),
            ('22000000-0000-4000-8000-000000180085'::uuid, '30'::text) $$,
  'derived length/shapes: refused AND unmoved through all six shapes — both memberships still record the 30 days their plan says'
);

-- 269 — permitted: the column written from its own value.
select lives_ok($$
  update public.memberships set duration_days = duration_days
   where id = '22000000-0000-4000-8000-000000180084'::uuid
$$, 'derived length/shapes: writing the length its own current value is allowed — nothing changed, so nothing was negotiated');

-- 270 — permitted: the literal form, which is what an ORM or any
-- column-listing update sends.
select lives_ok($$
  update public.memberships set duration_days = 30, cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000180084'::uuid
$$, 'derived length/shapes: the literal value the column already holds, carried alongside an ordinary note edit, is allowed — every exploit needs the value MOVED');

-- 271 — ROUND ELEVEN swapped the companion column from `discount_paise` to
-- `cancel_reason`: ADR-094 gives the discount to the gym admin, and this
-- statement is a front desk's. The shape — a derived column written its own
-- literal value beside an ordinary edit — is exactly what it was.
select results_eq(
  $$ select to_jsonb(m)->>'duration_days', m.cancel_reason, m.periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180084'::uuid $$,
  $$ values ('30'::text, 'desk note'::text, 0) $$,
  'derived length/shapes: allowed AND applied — the note landed, the length is where it was, and nothing was granted'
);


-- ---------------------------------------------------------------------------
-- 18f (ADR-092) — the harm end to end, in the two statements ADR-092
-- measured: a 30-day Rs 1,500 membership, `set duration_days = 3650`, then
-- the ordinary Rs 1,500. Measured today: periods_granted = 1, ends_on 3650
-- days out. The record it leaves is fully self-consistent — one receipt, one
-- period, `ends_on` exactly one recorded period — so no audit afterwards can
-- tell it from an honest membership on a re-lengthened plan, which is why
-- the outcome has to be asserted here and not only the refusal.
-- Membership 180086, no money until the second statement.
-- ---------------------------------------------------------------------------

-- 272
select throws_ok($$
  update public.memberships set duration_days = 3650
   where id = '22000000-0000-4000-8000-000000180086'::uuid
$$, 'GL043'::char(5), null,
  'derived length/end-to-end: the first statement is refused');

-- 273
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181007'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180046'::uuid, '22000000-0000-4000-8000-000000180086'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'derived length/end-to-end: the ordinary Rs 1,500 that follows is recorded like any other — a refused term edit does not refuse the money after it');

-- 274
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180086'::uuid $$,
  $$ values (1, (select d from today_t18) + 30) $$,
  'derived length/end-to-end: Rs 1,500 bought THIRTY days — not the ten years two ordinary front-desk statements buy today, and not a row an audit could never tell apart afterwards'
);


-- ---------------------------------------------------------------------------
-- 18g (ADR-092) — a plan change pointing at another gym's plan. Assertion
-- 162 already proves such a change is refused; what is new here is that the
-- refusal must have re-derived NOTHING. A plan change now carries a price
-- and a length with it, so a rule that derives them before the tenant
-- boundary answers would leave a membership re-priced against a plan it was
-- never allowed to point at. Membership 180087, no money.
-- ---------------------------------------------------------------------------

-- 275
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000180063'::uuid
   where id = '22000000-0000-4000-8000-000000180087'::uuid
$$, null::char(5), null,
  'derived length/tenant: repointing at a plan belonging to another gym is refused — ADR-052''s composite key stands where the money freeze does not apply');

-- 276
select results_eq(
  $$ select m.plan_id, m.price_paise, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180087'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000180060'::uuid, 150000::bigint, '30'::text) $$,
  'derived length/tenant: refused AND nothing derived — the plan, the price and the length are all exactly what this gym sold, not the other gym''s Rs 12,000 and 365 days'
);


-- ---------------------------------------------------------------------------
-- 18h (GL043) — a plan change on a membership that has taken money, naming a
-- new price and a new length as well. GL043 already refuses the plan change
-- alone (measured, live). What this adds is the composite statement: the two
-- re-derived terms and the typed one all arriving together on a row where
-- money is already being scored. Membership 180088, part-paid Rs 750 of
-- Rs 1,500 — the window ADR-090 found, where `periods_granted` is still 0.
-- ---------------------------------------------------------------------------

-- 277
select results_eq(
  $$ select periods_granted, price_paise, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180088'::uuid $$,
  $$ values (0, 150000::bigint, '30'::text) $$,
  'GL043/composite: half the price arrived and bought nothing — the part-paid window, with all three terms recorded as sold'
);

-- 278
select throws_ok($$
  update public.memberships
     set plan_id = '22000000-0000-4000-8000-000000180061'::uuid,
         price_paise = 900000,
         duration_days = 3650
   where id = '22000000-0000-4000-8000-000000180088'::uuid
$$, 'GL043'::char(5), null,
  'GL043/composite: a plan change naming a new price and a new length, on a membership money has arrived against, is refused whole');

-- 279
select results_eq(
  $$ select m.plan_id, m.price_paise, to_jsonb(m)->>'duration_days', m.periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180088'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000180060'::uuid, 150000::bigint, '30'::text, 0) $$,
  'GL043/composite: refused AND unmoved in all three — a partial refusal that let one of the three through would be the worst outcome of the four'
);

-- 280
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181008'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180048'::uuid, '22000000-0000-4000-8000-000000180088'::uuid,
          75000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'GL043/composite: the balance of the original price is recorded');

-- 281
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000180088'::uuid $$,
  $$ values (1, (select d from today_t18) + 30) $$,
  'GL043/composite: the balance bought one period of the ORIGINAL 30 days at the ORIGINAL price — the terms the member agreed to and every paisa was taken against'
);


-- ---------------------------------------------------------------------------
-- 18i — the permitted side that has nothing to do with a length, on a
-- membership that has been granted a period. Freezing, unfreezing, a
-- discount, a note, an ordinary renewal and a cancellation are all ordinary
-- gym work on a paid-up membership. A rule that froze the ROW, or that
-- refused any statement mentioning `duration_days`, or that fired on the
-- granting rule's own write, fails somewhere in here and nowhere else in
-- this file. Membership 180089, one period earned from a real payment.
-- ---------------------------------------------------------------------------

-- 282
select results_eq(
  $$ select periods_granted, ends_on, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180089'::uuid $$,
  $$ values (1, (select d from today_t18) + 30, '30'::text) $$,
  'permitted: one period earned by one ordinary full payment, thirty days recorded'
);

-- 283
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-000000180089'::uuid
$$, 'permitted: freezing a paid-up membership is allowed');

-- 284
select lives_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-000000180089'::uuid
$$, 'permitted: unfreezing it again is allowed');

-- 285
select lives_ok($$
  update public.memberships set cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000180089'::uuid
$$, 'permitted: a note on a paid-up membership is not a term and is allowed');

-- 286 — ROUND ELEVEN dropped the `discount_paise = 5000` this statement used
-- to carry: ADR-094 reserves the discount to a gym admin and this session is
-- the desk. The assertion still proves what it was written to prove — the
-- three terms and the recorded length are untouched by ordinary desk work.
select results_eq(
  $$ select m.discount_paise, m.cancel_reason, m.status, m.price_paise, m.plan_id, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180089'::uuid $$,
  $$ values (0::bigint, 'desk note'::text, 'active'::public.membership_status,
             150000::bigint, '22000000-0000-4000-8000-000000180060'::uuid, '30'::text) $$,
  'permitted: those edits LANDED — allowed and applied, not allowed and silently dropped, while the three terms and the recorded length stayed exactly as they were'
);

-- 287
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000181009'::uuid, '22000000-0000-4000-8000-000000180001'::uuid,
          '22000000-0000-4000-8000-000000180049'::uuid, '22000000-0000-4000-8000-000000180089'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000180021'::uuid)
$$, 'permitted: an ordinary renewal, after all of that, is recorded');

-- 288 — and the granting rule's own write to the membership is not caught by
-- a rule about who may write a length: it writes ends_on and the count and
-- must leave the recorded length alone.
select results_eq(
  $$ select periods_granted, ends_on, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180089'::uuid $$,
  $$ values (2, (select d from today_t18) + 60, '30'::text) $$,
  'permitted: the renewal bought another thirty days — the rule''s own write is not a change of terms and the recorded length is untouched by it');

-- 289
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member left'
   where id = '22000000-0000-4000-8000-000000180089'::uuid
$$, 'permitted: cancelling it is allowed');

-- 290
select results_eq(
  $$ select m.status, m.price_paise, m.plan_id, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000180089'::uuid $$,
  $$ values ('cancelled'::public.membership_status, 150000::bigint,
             '22000000-0000-4000-8000-000000180060'::uuid, '30'::text) $$,
  'permitted: cancelled, and the terms it was sold on are still the terms it was sold on — a membership''s history does not change because it ended'
);


-- ===========================================================================
-- SECTION 19 (ROUND TEN, ADR-093 / GL045) — "The dates a membership runs for
-- are written by the rule that grants them."
--
-- WHY THIS SECTION EXISTS. Sections 16, 17 and 18 govern what a period costs
-- (`GL043`), how long it is (`GL043`, derived from the plan) and how many
-- have been granted (`GL044`). Every one of them constrains an INPUT to an
-- arithmetic whose OUTPUT anyone can simply type. Measured from an ordinary
-- front-desk session on live Cloud, with no privilege beyond recording a
-- payment, before this section:
--
--     update public.memberships set ends_on   = starts_on + 3650 …  -- ALLOWED
--     update public.memberships set starts_on = starts_on - 3650 …  -- ALLOWED
--     merge into public.memberships … update set ends_on = ends_on+1 -- ALLOWED
--
-- Ten years, one statement, no refusal, no receipt, nothing raised.
--
-- THE FALSE PREMISE THAT KEPT IT ALIVE FOR TWO ROUNDS, RE-MEASURED HERE
-- RATHER THAN INHERITED. The docs ranked this door below the length one on
-- the claim that a hand-written `ends_on` leaves a detectable trace, since
-- `ends_on - starts_on` would disagree with `duration_days * periods_granted`.
-- ADR-092 has already retracted it — the invariant fails for 17 of 46 dated
-- memberships on the demo gym before any fraud — and this author did not
-- take the retraction on trust either: nothing below asserts, implies or
-- relies on that invariant anywhere. Every refusal here is asserted as a
-- refusal AND as the dates being unchanged, never as "an audit would notice".
--
-- WHAT IS ATTACKED. Every write shape the previous three rounds each had to
-- learn separately — plain UPDATE, MERGE, a data-modifying CTE, UPDATE … FROM
-- computing from the plan, a multi-row statement, UPDATE … FROM giving two
-- rows two DIFFERENT values, and a multi-row statement where only SOME rows
-- move while the others are written their own value (19a). Both columns and
-- both directions, including `starts_on` pulled backwards on a membership
-- that has not started yet — the check-in gate reads these dates (ADR-084),
-- so a typed `starts_on` is a free day at the turnstile and not only a free
-- month on the ledger (19b). The whole harm end to end against the ordinary
-- renewal it has to leave alone (19c). The granting rule's own multi-column
-- write, from null dates (19d). The open-ended membership a payment moves
-- nothing on (19e). A part-paid row, where the refusal must be this rule's
-- and not the terms freeze's (19f). A plan correction, which reaches the
-- dates only through the granting rule (19g). And every piece of ordinary
-- gym work on a paid-up membership that must survive: freeze, unfreeze, a
-- discount, a note, a refund, a cancellation (19h), and the whole membership
-- pause path (19i).
--
-- THE PAUSE PATH, MEASURED RATHER THAN ASSUMED. The brief asked whether
-- approving or rejecting a freeze is a legitimate writer of the membership's
-- own dates that the requirement fails to mention. Measured on live Cloud
-- (fixtures wrapped begin…rollback, nothing committed): a front-desk request,
-- an approval by the gym's configured `pause_approver_role`, and a rejection
-- are all ALLOWED, and the membership's own `starts_on`/`ends_on` are byte
-- for byte what they were before all three. `membership_pauses` carries its
-- own `starts_on`/`ends_on`, no trigger on it touches `memberships`, and the
-- route (`apps/web/app/api/memberships/pauses/route.ts`) writes only
-- `approved_by_staff_id`, `approved_at` and `rejected_at`. So it is NOT a
-- date writer, this requirement needs no exemption for it, and 19i asserts
-- that as a permitted-side guard rather than reporting an ambiguity.
--
-- THE ONE PLACE THIS AUTHOR HAD TO CHOOSE, STATED RATHER THAN HIDDEN.
-- The requirement's prose says the dates "SHALL move … only as part of
-- granting a period, and SHALL refuse every other WRITE to them", and its
-- scenario says "any session WRITES `ends_on` or `starts_on`". Read
-- literally, `set ends_on = ends_on` is a write and must be refused. Three
-- things say otherwise and this section follows them: ADR-093's own
-- mechanism sentence says they may "CHANGE only at `pg_trigger_depth() >= 2`";
-- the sibling requirement one heading above settled the identical question
-- for `periods_granted` the other way in as many words ("Writing the same
-- value back is allowed … a rule that refuses a write that cannot do harm
-- buys nothing and breaks ordinary column-listing updates"); and section 18
-- already holds that convention for `duration_days` at 269/270. A rule that
-- refused the no-op would also refuse the product's own create path, which
-- writes `ends_on: startsOn` in its INSERT column list. 304/305/306 assert
-- the no-op ALLOWED. This is a reported divergence from the literal text of
-- the scenario, not a silent one — see the report.
--
-- THE COST THIS RULE CREATES, ALSO REPORTED. Section 9's assertion 71 proves
-- that paying for an open-ended membership (a `starts_on`, `ends_on` null)
-- moves nothing, and `memberships_dated_unless_pending_chk` (assertion 72)
-- permits null dates only while pending. After GL045 such a row can never
-- acquire an `ends_on` by any route at all: no payment gives it one and no
-- session may type one. Today a desk repairs it in one statement. 320-323
-- assert the new behaviour, because "refunding and selling again" is the
-- answer this requirement gives for every other recorded fact — but the row
-- is unrepairable in place, and that is a consequence the requirement does
-- not mention.
--
-- THE SQLSTATE IS `GL045`, answered by the contract. Every refusal below
-- asserts `GL045` AND that both dates are unchanged — never the code alone,
-- which passes with a rule that refuses and rolls the wrong thing back, and
-- never the dates alone, which passes with a rule that silently discards the
-- write (the failure this codebase asserts against, and the shape a round
-- eight draft was caught in).
--
-- TENANT 19, its own gym, its own eleven memberships, no assertion depending
-- on another tenant's rows (ADR-050). Every date is read from the gym's own
-- `(now() at time zone o.timezone)::date` via `today_t19`, never
-- `current_date` and never a literal (ADR-039).
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000190001'::uuid, 'PayRec Gym 19', 'PYR22K');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000190011'::uuid, '22000000-0000-4000-8000-000000190001'::uuid, 'G19 Main', true);

-- The manager exists only so that 19i can approve a freeze as the gym's own
-- configured `pause_approver_role`, which defaults to `gym_manager`. The
-- settings row is inserted for the same reason and for no other.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000190021'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'front_desk', 'T19 Desk'),
  ('22000000-0000-4000-8000-000000190022'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'gym_manager', 'T19 Manager');

insert into public.organization_settings (tenant_id) values
  ('22000000-0000-4000-8000-000000190001'::uuid);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000190040'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Shapes', '+912200190040'),
  ('22000000-0000-4000-8000-000000190041'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Sibling', '+912200190041'),
  ('22000000-0000-4000-8000-000000190042'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 NotStarted', '+912200190042'),
  ('22000000-0000-4000-8000-000000190043'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 EndToEnd', '+912200190043'),
  ('22000000-0000-4000-8000-000000190044'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Dateless', '+912200190044'),
  ('22000000-0000-4000-8000-000000190045'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 OpenEnded', '+912200190045'),
  ('22000000-0000-4000-8000-000000190046'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 PartPaid', '+912200190046'),
  ('22000000-0000-4000-8000-000000190047'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 PlanFix', '+912200190047'),
  ('22000000-0000-4000-8000-000000190048'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Ordinary', '+912200190048'),
  ('22000000-0000-4000-8000-000000190049'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Paused', '+912200190049'),
  ('22000000-0000-4000-8000-00000019004a'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190011'::uuid, 'M19 Created', '+912200190050');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000190060'::uuid, '22000000-0000-4000-8000-000000190001'::uuid, 'G19 Monthly (30d)', 30, 150000),
  ('22000000-0000-4000-8000-000000190061'::uuid, '22000000-0000-4000-8000-000000190001'::uuid, 'G19 Annual (365d)', 365, 1200000);

create temp table today_t19 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000190001'::uuid;

grant select on today_t19 to public;

-- Six memberships sit at `starts_on = ends_on = today` so that one granted
-- period is `today + 30` with nothing else in the arithmetic and any typed
-- date is visible as a pure offset from the gym's own today. Five are
-- deliberately shaped otherwise: 190082 has not started yet (19b), 190084 has
-- no dates at all (19d), 190085 is open-ended (19e), and 190080/190081 run
-- from `today - 30` to `today + 30` for the reason 19a's header gives.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000190080'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190040'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19) - 30, (select d from today_t19) + 30, 150000),
  ('22000000-0000-4000-8000-000000190081'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190041'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19) - 30, (select d from today_t19) + 30, 150000),
  ('22000000-0000-4000-8000-000000190082'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190042'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19) + 30, (select d from today_t19) + 60, 150000),
  ('22000000-0000-4000-8000-000000190083'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190043'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19), (select d from today_t19), 150000),
  ('22000000-0000-4000-8000-000000190084'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190044'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'pending', null, null, 150000),
  ('22000000-0000-4000-8000-000000190085'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190045'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'pending', (select d from today_t19) - 10, null, 150000),
  ('22000000-0000-4000-8000-000000190086'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190046'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19), (select d from today_t19), 150000),
  ('22000000-0000-4000-8000-000000190088'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190047'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19), (select d from today_t19), 150000),
  ('22000000-0000-4000-8000-000000190089'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190048'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19), (select d from today_t19), 150000),
  ('22000000-0000-4000-8000-00000019008a'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190049'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
   'active', (select d from today_t19), (select d from today_t19), 150000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000190001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000190021')::text,
  true);
set local role authenticated;

-- The only three memberships in this section carrying money before their own
-- subsection begins, all of it earned by ordinary front-desk work: 190086 is
-- part-paid (half of Rs 1,500), 190089 and 19008a are paid in full. Each
-- one's resulting state is asserted where its subsection starts rather than
-- claimed here.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000191001'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190046'::uuid, '22000000-0000-4000-8000-000000190086'::uuid,
   75000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid),
  ('22000000-0000-4000-8000-000000191002'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190048'::uuid, '22000000-0000-4000-8000-000000190089'::uuid,
   150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid),
  ('22000000-0000-4000-8000-000000191003'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
   '22000000-0000-4000-8000-000000190049'::uuid, '22000000-0000-4000-8000-00000019008a'::uuid,
   150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid);


-- ---------------------------------------------------------------------------
-- 19a (GL045) — every statement shape that writes a date, on a membership no
-- money has ever touched, so that GL043 and GL044 cannot be what refuses any
-- of it: a refusal here is this rule and nothing else. Memberships 190080 and
-- its innocent sibling 190081. Every one of these shapes is ALLOWED on live
-- Cloud today and lands the date it names.
--
-- The last three assertions are the permitted side, kept in the same
-- subsection deliberately: a rule that refuses a write which cannot move the
-- value breaks every column-listing update the product sends, and this phase
-- has shipped the too-broad shape three times.
--
-- WHY THESE TWO MEMBERSHIPS RUN FROM `today - 30` TO `today + 30` WHEN EVERY
-- OTHER ONE IN THE SECTION SITS AT `today`/`today`. The four column-by-
-- direction cases below need room on both sides. `memberships_ends_on_after_
-- starts_on_chk` (`ends_on >= starts_on`, Phase 1) refuses any write that
-- inverts the range with `23514` BEFORE an AFTER trigger runs, so on a
-- zero-width membership `ends_on - 30` and `starts_on + 30` are answered by
-- the constraint and never reach this rule at all — measured, and the reason
-- 293 and 295 first asserted the wrong code. That ordering is ADR-066 working
-- in the benign direction (the refusal comes from the rule that has the
-- answer), and it is not what this section is about: a thirty-day window on
-- either side keeps all four cases inside the valid range so `GL045` is what
-- answers every one of them, which is the claim the requirement makes.
-- ---------------------------------------------------------------------------

-- 291
select results_eq(
  $$ select starts_on, ends_on, periods_granted,
            (select count(*)::int from public.payments p where p.membership_id = m.id)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000190080'::uuid $$,
  $$ select (select d from today_t19) - 30, (select d from today_t19) + 30, 0, 0 $$,
  'GL045/shapes: a thirty-day window either side of the gym''s , nothing granted, and NOT ONE PAYMENT against it — so nothing below can be refused by the terms freeze'
);

-- 292 — ADR-093's own statement, verbatim.
select throws_ok($$
  update public.memberships set ends_on = starts_on + 3650
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: the plain UPDATE pushing ends_on ten years out is refused — measured ALLOWED on live Cloud today, one statement, no receipt, nothing raised');

-- 293 — the other direction, which is not fraud against the gym but against
-- the member: an end date pulled backwards ends a paid-up membership early.
select throws_ok($$
  update public.memberships set ends_on = ends_on - 30
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: ends_on pulled BACKWARDS, to a value still inside the valid range, is refused too — the rule is about who writes the dates, not about which direction profits the gym');

-- 294 — ADR-093's second statement. The check-in gate reads these dates
-- (ADR-084), so a typed starts_on is a free day at the turnstile as well as
-- a free month on the ledger.
select throws_ok($$
  update public.memberships set starts_on = starts_on - 3650
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: starts_on dragged ten years backwards is refused — a rule that watched only ends_on would leave half the door open');

-- 295
select throws_ok($$
  update public.memberships set starts_on = starts_on + 30
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: starts_on pushed forwards, also staying inside the range, is refused as well — all four of column x direction answered by THIS rule, not the two that happen to be profitable');

-- 296
select throws_ok($$
  update public.memberships set starts_on = starts_on - 3650, ends_on = ends_on + 3650
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: both columns moved in one statement is refused whole — twenty years, one UPDATE');

-- 297
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000190080'::uuid as id) s
     on m.id = s.id
   when matched then update set ends_on = m.ends_on + 3650
$$, 'GL045'::char(5), null,
  'GL045/shapes: the same write as MERGE is refused — measured ALLOWED on live Cloud today, which is the costume ADR-087 named and every rule since has had to be shown');

-- 298
select throws_ok($$
  with moved as (
    update public.memberships set ends_on = ends_on + 3650
     where id = '22000000-0000-4000-8000-000000190080'::uuid
    returning id
  ) select count(*) from moved
$$, 'GL045'::char(5), null,
  'GL045/shapes: hidden inside a data-modifying CTE it is refused');

-- 299 — a value computed from the plan's own duration, so a rule that
-- inspects literals rather than the row it is given lets this straight past.
select throws_ok($$
  update public.memberships m set ends_on = m.starts_on + p.duration_days * 100
    from public.plans p
   where p.id = m.plan_id
     and m.id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045'::char(5), null,
  'GL045/shapes: UPDATE ... FROM computing the date from the plan''s own duration is refused — a hundred periods is still not a granted period');

-- 300
select throws_ok($$
  update public.memberships set ends_on = ends_on + 3650
   where id in ('22000000-0000-4000-8000-000000190080'::uuid,
                '22000000-0000-4000-8000-000000190081'::uuid)
$$, 'GL045'::char(5), null,
  'GL045/shapes: one statement extending two memberships is refused');

-- 301 — two rows, two DIFFERENT offsets, in one statement. A rule that reads
-- one representative new value per statement rather than per row sees a
-- single plausible number here and lets the other row past.
select throws_ok($$
  update public.memberships m set ends_on = m.ends_on + v.n
    from (values ('22000000-0000-4000-8000-000000190080'::uuid, 3650),
                 ('22000000-0000-4000-8000-000000190081'::uuid, 7)) as v(id, n)
   where m.id = v.id
$$, 'GL045'::char(5), null,
  'GL045/shapes: UPDATE ... FROM giving the two rows two DIFFERENT offsets is refused — neither of them was granted anything');

-- 302 — the mixed statement: one row moves, the other is written the value it
-- already holds. A per-statement rule that samples a row, or that refuses only
-- when EVERY row moved, gets this wrong in one direction or the other.
select throws_ok($$
  update public.memberships m
     set ends_on = case when m.id = '22000000-0000-4000-8000-000000190080'::uuid
                        then m.ends_on + 3650 else m.ends_on end
   where m.id in ('22000000-0000-4000-8000-000000190080'::uuid,
                  '22000000-0000-4000-8000-000000190081'::uuid)
$$, 'GL045'::char(5), null,
  'GL045/shapes: a two-row statement in which only ONE row''s date moves is refused — the row that moved is the whole statement');

-- 303
select results_eq(
  $$ select id, starts_on, ends_on from public.memberships
      where id in ('22000000-0000-4000-8000-000000190080'::uuid,
                   '22000000-0000-4000-8000-000000190081'::uuid)
      order by id $$,
  $$ values ('22000000-0000-4000-8000-000000190080'::uuid, (select d from today_t19) - 30, (select d from today_t19) + 30),
            ('22000000-0000-4000-8000-000000190081'::uuid, (select d from today_t19) - 30, (select d from today_t19) + 30) $$,
  'GL045/shapes: refused AND unmoved through all eleven shapes — both memberships still run the window they were sold, and the sibling was never in either statement''s way'
);

-- 304 — permitted: each column written from its own value.
select lives_ok($$
  update public.memberships set ends_on = ends_on, starts_on = starts_on
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045/shapes: writing both dates their own current values is allowed — nothing moved, so no period was claimed');

-- 305 — permitted: the same values arriving as expressions, alongside an
-- ordinary discount edit. This is the shape every column-listing update sends,
-- and the product's own create path writes `ends_on: startsOn` the same way.
select lives_ok($$
  update public.memberships
     set starts_on = (select d from today_t19) - 30,
         ends_on = (select d from today_t19) + 30,
         cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000190080'::uuid
$$, 'GL045/shapes: the dates the row already holds, carried alongside an ordinary note edit, are allowed — every exploit above needs a date MOVED');

-- 306 — ROUND ELEVEN swapped the companion column from `discount_paise` to
-- `cancel_reason` for the reason ADR-094 gives: the discount is gym-admin
-- work now, and this is a front-desk session. The column-listing shape this
-- assertion exists for is unchanged.
select results_eq(
  $$ select starts_on, ends_on, cancel_reason, periods_granted
       from public.memberships where id = '22000000-0000-4000-8000-000000190080'::uuid $$,
  $$ select (select d from today_t19) - 30, (select d from today_t19) + 30, 'desk note'::text, 0 $$,
  'GL045/shapes: allowed AND applied — the note landed, both dates are where they were, and nothing was granted'
);


-- ---------------------------------------------------------------------------
-- 19b (GL045) — a membership sold to start next month, whose starts_on is
-- dragged back to today. Nothing about the money changes and no period is
-- claimed; the member simply walks in thirty days early, because ADR-084's
-- check-in gate reads exactly these two dates. This is the half of the door
-- that a rule watching only `ends_on` would leave standing.
-- Membership 190082, no money.
-- ---------------------------------------------------------------------------

-- 307
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190082'::uuid $$,
  $$ select (select d from today_t19) + 30, (select d from today_t19) + 60, 0 $$,
  'GL045/not-started: sold to run next month — not live today, and nothing granted'
);

-- 308
select throws_ok($$
  update public.memberships set starts_on = (select d from today_t19)
   where id = '22000000-0000-4000-8000-000000190082'::uuid
$$, 'GL045'::char(5), null,
  'GL045/not-started: pulling starts_on forward to today, which makes the membership live at the gate a month early, is refused');

-- 309
select results_eq(
  $$ select starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000190082'::uuid $$,
  $$ select (select d from today_t19) + 30, (select d from today_t19) + 60 $$,
  'GL045/not-started: refused AND unmoved — the membership still starts when it was sold to start'
);


-- ---------------------------------------------------------------------------
-- 19c (GL045) — the harm end to end, and immediately beside it the only
-- writer this requirement permits, asserted hard. A rule that refuses the
-- typed date and also breaks the renewal has not fixed anything: the gym
-- stops being able to sell. Membership 190083, no money until 311.
-- ---------------------------------------------------------------------------

-- 310
select throws_ok($$
  update public.memberships set ends_on = starts_on + 3650
   where id = '22000000-0000-4000-8000-000000190083'::uuid
$$, 'GL045'::char(5), null,
  'GL045/end-to-end: the ten-year statement is refused');

-- 311
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191010'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190043'::uuid, '22000000-0000-4000-8000-000000190083'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/end-to-end: the ordinary Rs 1,500 that follows is recorded like any other — a refused date edit does not refuse the money after it');

-- 312 — the permitted write, asserted in all three columns at once: the rule
-- moves ends_on by exactly what the money bought, leaves starts_on alone
-- (measured: a dated membership's starts_on does not move when it is
-- renewed) and counts the period.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190083'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 30, 1 $$,
  'GL045/end-to-end: Rs 1,500 bought THIRTY days — not the ten years one front-desk statement buys today — and starts_on was not touched by the rule that moved ends_on'
);

-- 313
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191011'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190043'::uuid, '22000000-0000-4000-8000-000000190083'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/end-to-end: an ordinary renewal a month later is recorded');

-- 314 — the whole permitted side of this requirement in one row: a renewal is
-- the rule's own UPDATE to `memberships`, and a rule that fired on its own
-- writer would stop every gym in the product renewing anybody.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190083'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 60, 2 $$,
  'GL045/end-to-end: the renewal moved ends_on another thirty days and the count to two — the granting rule is the one writer this requirement exists to leave alone'
);

-- 315
select throws_ok($$
  update public.memberships set ends_on = ends_on + 3650
   where id = '22000000-0000-4000-8000-000000190083'::uuid
$$, 'GL045'::char(5), null,
  'GL045/end-to-end: and after two real payments the dates are still not the desk''s to write — a granted period does not license the next one');

-- 316
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190083'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 60, 2 $$,
  'GL045/end-to-end: refused AND unmoved — sixty days of gym for two months'' money, which is the whole arithmetic this section protects'
);


-- ---------------------------------------------------------------------------
-- 19d (GL045) — the granting rule's own multi-column write, which is the
-- hardest thing for this rule to leave alone: a paid payment against a
-- membership with no dates at all sets starts_on, ends_on, status AND
-- periods_granted in one go, and both dates move from null. A date rule that
-- fired on its own writer breaks exactly here, and the member is paid up and
-- refused at the turnstile. Membership 190084, pending, no dates.
-- ---------------------------------------------------------------------------

-- 317
select results_eq(
  $$ select starts_on, ends_on, status, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190084'::uuid $$,
  $$ select null::date, null::date, 'pending'::public.membership_status, 0 $$,
  'GL045/from-null: a pending membership with no dates at all, which the dated-unless-pending constraint permits and nothing else does'
);

-- 318
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191012'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190044'::uuid, '22000000-0000-4000-8000-000000190084'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/from-null: a full payment against a dateless pending membership is recorded');

-- 319
select results_eq(
  $$ select starts_on, ends_on, status, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190084'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 30, 'active'::public.membership_status, 1 $$,
  'GL045/from-null: the rule wrote BOTH dates, the status and the count in one go and this requirement did not catch its own writer — the membership runs from today for the plan''s thirty days'
);


-- ---------------------------------------------------------------------------
-- 19e (GL045) — the open-ended membership: a starts_on, no ends_on. Assertion
-- 71 already proves a payment moves nothing on it ("it has not ended, so
-- there is nothing to move"), and assertion 72 proves null dates are legal
-- only while pending. Put together with this requirement, such a row can
-- never acquire an ends_on by ANY route: no payment gives it one and no
-- session may type one. Today one statement repairs it. The requirement's
-- own answer — refund and sell again — still applies, but the cost is real
-- and is reported rather than discovered. Membership 190085.
-- ---------------------------------------------------------------------------

-- 320
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191013'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190045'::uuid, '22000000-0000-4000-8000-000000190085'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/open-ended: paying for an open-ended membership is recorded, not refused');

-- 321
select results_eq(
  $$ select starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000190085'::uuid $$,
  $$ select (select d from today_t19) - 10, null::date $$,
  'GL045/open-ended: the payment moved neither date — starts_on unchanged, ends_on still null, exactly as assertion 71 has always held'
);

-- 322
select throws_ok($$
  update public.memberships set ends_on = (select d from today_t19) + 20
   where id = '22000000-0000-4000-8000-000000190085'::uuid
$$, 'GL045'::char(5), null,
  'GL045/open-ended: typing the missing end date onto it is refused as well — null is a value the rule has not written, not a licence for the desk');

-- 323
select results_eq(
  $$ select starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000190085'::uuid $$,
  $$ select (select d from today_t19) - 10, null::date $$,
  'GL045/open-ended: refused AND unmoved — and this row is now unrepairable in place, which is a cost of the rule and not a defect in it'
);


-- ---------------------------------------------------------------------------
-- 19f (GL045) — money on the row changes nothing about who writes the dates,
-- and the refusal must be THIS rule's rather than the terms freeze's. A
-- part-paid membership sits in the window ADR-090 found: money has arrived,
-- `periods_granted` is still 0, and GL043 already refuses its price and its
-- plan. The dates are not terms, so an implementation that reached for the
-- nearest existing trigger would answer GL043 here and be wrong.
-- Membership 190086, Rs 750 of Rs 1,500.
-- ---------------------------------------------------------------------------

-- 324
select results_eq(
  $$ select starts_on, ends_on, periods_granted,
            (select coalesce(sum(p.amount_paise), 0)::bigint from public.payments p where p.membership_id = m.id)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000190086'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19), 0, 75000::bigint $$,
  'GL045/part-paid: half the price arrived and bought nothing — the part-paid window, with both dates still where the membership was created'
);

-- 325
select throws_ok($$
  update public.memberships set ends_on = ends_on + 3650
   where id = '22000000-0000-4000-8000-000000190086'::uuid
$$, 'GL045'::char(5), null,
  'GL045/part-paid: the typed date is refused with GL045, the dates'' own code — not GL043, which answers for a price, a currency and a plan and says nothing about when a membership runs');

-- 326
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190086'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19), 0 $$,
  'GL045/part-paid: refused AND unmoved'
);

-- 327
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191014'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190046'::uuid, '22000000-0000-4000-8000-000000190086'::uuid,
          75000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/part-paid: the balance of the price is recorded');

-- 328
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190086'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 30, 1 $$,
  'GL045/part-paid: the balance crossed the price and bought exactly one period of thirty days — a part payment is ordinary gym practice and this rule must not make it unfinishable'
);


-- ---------------------------------------------------------------------------
-- 19g (GL045) — a plan correction before any money has arrived. ADR-093 says
-- the dates are reached by a plan correction "only through the granting
-- rule", which is a claim with two halves and both are asserted: the
-- correction itself must move NEITHER date, and the payment that follows must
-- then move ends_on by the corrected length. An implementation that helpfully
-- re-derived ends_on from the new plan at correction time would pass the
-- second half and fail the first, and it would be a date this requirement
-- says nobody but the granting rule writes. Membership 190088, no money.
-- ---------------------------------------------------------------------------

-- 329
-- ROUND ELEVEN (ADR-094 / GL046) RECONCILED THIS ASSERTION, AND ONLY ITS
-- ACTOR. "Correcting a mistake before any money arrives" said *a front-desk
-- session* for four rounds, and that is the sentence a critic walked through
-- to buy 300 days for one month's fee: `price_paise` is the other factor of
-- `duration_days x floor(money / price_paise)`, and it was freely typed. The
-- scenario now says *a gym admin*. What is being tested here is unchanged --
-- WHEN the terms are still free, not WHO may move them -- so the statement,
-- the expected values and the code are all exactly as they were, and only the
-- session performing it is now one GL046 permits. Section 20 tests WHO.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000190001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000190022')::text,
  true);

select lives_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000190061'::uuid
   where id = '22000000-0000-4000-8000-000000190088'::uuid
$$, 'GL045/plan-fix: a gym admin correcting a mis-sold Monthly to the Annual plan is allowed — no money has arrived, so the terms are not frozen');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000190001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000190021')::text,
  true);


-- 330
select results_eq(
  $$ select price_paise, to_jsonb(m)->>'duration_days', starts_on, ends_on
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000190088'::uuid $$,
  $$ select 1200000::bigint, '365'::text, (select d from today_t19), (select d from today_t19) $$,
  'GL045/plan-fix: the price and the length came from the new plan and NEITHER DATE MOVED — a correction re-derives terms, it does not grant a period'
);

-- 331
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000191015'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-000000190047'::uuid, '22000000-0000-4000-8000-000000190088'::uuid,
          1200000, 'paid', 'cash', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/plan-fix: one ordinary Annual fee is recorded against the corrected membership');

-- 332
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190088'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 365, 1 $$,
  'GL045/plan-fix: the payment is the only thing that moved a date, and it moved it by the corrected plan''s 365 days — the correction reaches the dates through the granting rule and by no other route'
);


-- ---------------------------------------------------------------------------
-- 19h (GL045) — every other piece of ordinary work a gym does to a paid-up
-- membership, none of which needs to move a date. Freezing, unfreezing, a
-- discount correction, a note, a refund and a cancellation are all ordinary,
-- and a rule that froze the ROW rather than the two columns fails somewhere
-- in here and nowhere else in this file. The refund is the one worth stating:
-- money that arrived and was then returned still counts toward the total, and
-- assertion 236 already holds that the refund does not pull the extension
-- back — so a refund does not need to move a date either, and nothing here
-- gives it permission to. Membership 190089, one period from one real payment.
-- ---------------------------------------------------------------------------

-- 333
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000190089'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 30, 1 $$,
  'GL045/ordinary: one period earned by one ordinary full payment, thirty days of it'
);

-- 334
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-000000190089'::uuid
$$, 'GL045/ordinary: freezing a paid-up membership is allowed');

-- 335
select lives_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-000000190089'::uuid
$$, 'GL045/ordinary: unfreezing it again is allowed');

-- 336
-- ROUND ELEVEN dropped the `discount_paise = 5000` this statement carried:
-- ADR-094 makes the discount gym-admin work and this session is the desk.
-- What the assertion is for — ordinary desk work on a paid-up membership
-- moving no date — is untouched.
select lives_ok($$
  update public.memberships set cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000190089'::uuid
$$, 'GL045/ordinary: a note is not a date and is allowed');

-- 337
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-000000191002'::uuid
$$, 'GL045/ordinary: refunding the payment that bought the period is an ordinary paid -> refunded move');

-- 338
select results_eq(
  $$ select m.discount_paise, m.cancel_reason, m.status, m.starts_on, m.ends_on, m.periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000190089'::uuid $$,
  $$ select 0::bigint, 'desk note'::text, 'active'::public.membership_status,
            (select d from today_t19), (select d from today_t19) + 30, 1 $$,
  'GL045/ordinary: all of it LANDED and neither date moved — a freeze, an unfreeze, a discount, a note and a refund between them have no business writing when a membership runs'
);

-- 339
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member left'
   where id = '22000000-0000-4000-8000-000000190089'::uuid
$$, 'GL045/ordinary: cancelling it is allowed');

-- 340
select results_eq(
  $$ select status, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000190089'::uuid $$,
  $$ select 'cancelled'::public.membership_status, (select d from today_t19), (select d from today_t19) + 30 $$,
  'GL045/ordinary: cancelled, and the dates are still the dates the money bought — a cancellation records that a membership ended, it does not rewrite when it ran'
);


-- ---------------------------------------------------------------------------
-- 19i (GL045) — the membership pause path, which the requirement does not
-- mention and which this author measured rather than assumed. A freeze is
-- requested by the desk into `membership_pauses` and decided by the gym's own
-- configured approver; both halves are ordinary work and neither writes the
-- membership's own dates. Asserted here so that an implementation cannot
-- quietly grow a pause-driven date writer, and so that a too-broad rule
-- cannot break the freeze flow. Membership 19008a, one period.
-- ---------------------------------------------------------------------------

-- 341
select lives_ok($$
  insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values ('22000000-0000-4000-8000-000000192001'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-00000019008a'::uuid,
          (select d from today_t19) + 1, (select d from today_t19) + 5,
          'travel', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/pauses: the front desk asks for a freeze — its dates live on membership_pauses, which has a starts_on and an ends_on of its own');

-- 342
select lives_ok($$
  insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values ('22000000-0000-4000-8000-000000192002'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-00000019008a'::uuid,
          (select d from today_t19) + 10, (select d from today_t19) + 12,
          'travel again', '22000000-0000-4000-8000-000000190021'::uuid)
$$, 'GL045/pauses: a second request, so that both a decision to approve and a decision to reject can be measured');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000190001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000190022')::text,
  true);
set local role authenticated;

-- 343
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '22000000-0000-4000-8000-000000190022'::uuid, approved_at = now()
   where id = '22000000-0000-4000-8000-000000192001'::uuid
$$, 'GL045/pauses: the gym''s configured approver approves the first');

-- 344
select lives_ok($$
  update public.membership_pauses set rejected_at = now()
   where id = '22000000-0000-4000-8000-000000192002'::uuid
$$, 'GL045/pauses: and rejects the second');

-- 345
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-00000019008a'::uuid $$,
  $$ select (select d from today_t19), (select d from today_t19) + 30, 1 $$,
  'GL045/pauses: neither the approval nor the rejection touched the membership''s own dates — measured, so the pause path is not a writer this requirement has to make room for'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000190001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000190021')::text,
  true);
set local role authenticated;


-- ---------------------------------------------------------------------------
-- 19j (GL045) — creation, which the requirement leaves untouched, and the
-- edit immediately after it, which it does not. The dates named at INSERT
-- must land exactly as named — this is the product's own create path, which
-- writes both — and the same session may not then move them by one day.
-- Membership 19008b, created inside the assertion so that creation itself is
-- what is being asserted rather than a fixture.
-- ---------------------------------------------------------------------------

-- 346
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-00000019008b'::uuid, '22000000-0000-4000-8000-000000190001'::uuid,
          '22000000-0000-4000-8000-00000019004a'::uuid, '22000000-0000-4000-8000-000000190060'::uuid,
          'active', (select d from today_t19) - 5, (select d from today_t19) + 25, 150000)
$$, 'GL045/creation: a membership created naming both of its dates is allowed — creation sets them, and this requirement starts afterwards');

-- 347
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-00000019008b'::uuid $$,
  $$ select (select d from today_t19) - 5, (select d from today_t19) + 25, 0 $$,
  'GL045/creation: and they LANDED exactly as named — allowed, not allowed and silently replaced'
);

-- 348
select throws_ok($$
  update public.memberships set ends_on = ends_on + 3650
   where id = '22000000-0000-4000-8000-00000019008b'::uuid
$$, 'GL045'::char(5), null,
  'GL045/creation: the same session moving them one statement later is refused — the door creation leaves open is closed the moment the row exists');

-- 349
select results_eq(
  $$ select starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000019008b'::uuid $$,
  $$ select (select d from today_t19) - 5, (select d from today_t19) + 25 $$,
  'GL045/creation: refused AND unmoved — the dates the membership was created with are the dates it still runs for'
);



-- ===========================================================================
-- SECTION 20 (ROUND ELEVEN, ADR-094 / GL046) — "Deciding what a member owes
-- is gym-admin work."
--
-- WHY THIS SECTION EXISTS. `ends_on = duration_days x floor(money /
-- price_paise)`. Round nine made `duration_days` underivable by hand because
-- it multiplies that product; round ten made the dates and the count the
-- granting rule's alone. `price_paise` is the OTHER factor of the same
-- product and it stayed freely typed. Measured by a round-ten critic, two
-- ordinary `front_desk` statements with no privilege beyond selling and
-- taking money:
--
--     update public.memberships set price_paise = 15000 where id = …;  -- permitted, no money yet
--     insert into public.payments (… 150000, 'INR', 'paid', 'cash' …);  -- the ordinary Rs 1,500
--
--     ends_on = 2027-07-06   periods_granted = 10   money = 150000
--
-- 300 days for one Rs 1,500 receipt, and BOTH audit invariants intact —
-- `periods_granted = floor(money / price)` and `ends_on - starts_on =
-- duration_days x periods_granted` — so it leaves the same "nothing to find"
-- record that got `duration_days` closed. At `price_paise = 1` it is 150,000
-- periods and an `ends_on` in the year 14347. And rounds nine and ten made it
-- UNREPAIRABLE: `GL043` freezes the price the moment money arrives and
-- `GL045` freezes the dates, so the row cannot be put back in place at all.
--
-- The control ADR-094 chooses is WHO, not what, and this codebase already
-- answered the neighbouring question the same way: `refunds_tenant_write` is
-- `is_gym_admin()` and not `is_front_office()`, because "front_desk may
-- record money but not refund it". Deciding what a member owes is the same
-- kind of act as deciding to give money back.
--
-- WHAT IS ATTACKED. The whole role matrix in BOTH directions, because a rule
-- that refuses everybody passes every refusal assertion ever written and this
-- project has shipped the too-broad shape three times in this phase alone
-- (20c): `front_desk`, `trainer` and `member` refused AND the value unmoved;
-- `gym_manager` and `gym_owner` allowed AND the value LANDED; `service_role`
-- measured explicitly. All four columns separately, all four together, and a
-- statement carrying one permitted column beside one restricted one (20b).
-- Every write shape the previous four rounds each had to learn separately —
-- UPDATE … FROM, MERGE, a data-modifying CTE, and a two-row statement giving
-- two rows two DIFFERENT prices (20g). The cross-tenant boundary (20d). The
-- ordering against the money freeze (20e). The no-op write (20f). And the
-- whole of what the front desk must STILL be able to do, which is where a fix
-- that is too broad fails and nothing else in this file catches it (20h).
--
-- THE THREE CALLS THIS AUTHOR HAD TO MAKE, STATED RATHER THAN HIDDEN. All
-- three are reported.
--
--   1. ORDERING — `GL046` or `GL043` when a front desk changes a term of a
--      membership that has already taken money? Both refuse. 20e asserts
--      **`GL043`**, and the reason is not aesthetic: `GL043` is an absolute
--      ("nobody may change this, money has bought it") while `GL046` is a
--      permission ("only an admin may"), and answering the permission first
--      would tell a desk that a manager could still do it, which is false.
--      The mechanical consequence decides it either way: every existing
--      `GL043` assertion in this file — 121, 123, 130-135, 178-181, 189-197,
--      216, 226, 241, 278 — is made by a `front_desk` session against a
--      membership that has money, so if `GL046` answered first it would MASK
--      THE ENTIRE `GL043` BATTERY and a regression in the money freeze could
--      no longer be seen from the only role that exercises it. 20e asserts
--      the same `GL043` for a `gym_manager` on the same row, which is the
--      spec's own "A gym admin after money has arrived" scenario.
--
--      ONE CONSEQUENCE OF THAT ORDER, RECORDED RATHER THAN DISCOVERED AS A
--      FLAKE. A MIXED multi-row statement from a non-admin — one frozen row
--      and one moneyless row together — has its two rows answered by two
--      different rules, and Postgres does not guarantee which row a
--      statement's row triggers fire for first. It is refused either way and
--      nothing moves either way, but the SQLSTATE is not determinate. Every
--      multi-row refusal in this file is therefore either single-rule (20g's
--      rows are both moneyless, so only GL046 can answer) or sent as a gym
--      admin (134 and 194, for exactly this reason, each with its own note
--      there — 194 was found by searching the file for the shape rather than
--      by waiting for it to flake). Any
--      future assertion mixing the two under a non-admin claim must assert
--      the refusal and the unchanged values, not the code.
--
--   2. THE NO-OP WRITE — the requirement's verb is *changes*, and its sibling
--      one heading up settles the identical question in as many words
--      ("Writing the same value back is allowed … a rule that refuses a write
--      that cannot do harm buys nothing and breaks ordinary column-listing
--      updates"). 20f reads it that way and asserts a front desk writing all
--      four columns their own values, as expressions and as literals, is
--      ALLOWED. Every exploit in ADR-094 needs the value MOVED, and the
--      product's own create and edit paths send column-listing updates.
--
--   3. `service_role` — the requirement names gym admins and says nothing
--      about the trusted server-side writers. `app.is_gym_admin()` is purely
--      claim-based, a webhook carries no `app_role`, and the sibling rule in
--      this same trigger is deliberately role-agnostic (assertion 157: "a
--      top-level hand-write by postgres itself is refused — the rule is about
--      the write not coming from the granting rule, not about which role is
--      asking"). 20c therefore asserts `service_role` REFUSED, on the
--      requirement's own whitelist wording. Nothing in the product needs the
--      other answer — no webhook re-prices a membership — so this is the safe
--      direction as well as the literal one, but it IS a reading and not a
--      sentence the spec contains.
--
-- WHAT IS NOT PINNED, AND WHY. `trainer` and `member` do not reach a
-- membership UPDATE at all: `memberships_tenant_write` is
-- `tenant_id = current_tenant_id() AND is_front_office()`, so their rows are
-- filtered rather than rejected and the statement affects nothing while
-- raising nothing. 369-372 assert exactly that — allowed to run, value
-- unmoved — rather than inventing a SQLSTATE the policy does not produce.
-- The same is true of a cross-tenant session in 20d, and it is the ADR-066
-- property stated as an assertion: this rule must NOT answer for a row the
-- session cannot see. The one place a real code is pinned there is 379, where
-- a gym admin of THIS gym moves its own membership to another tenant while
-- re-pricing it — `GL046` permits that session, so the policy's `with check`
-- is what must answer, with `42501`, and a rule that raised `GL046` ahead of
-- the boundary would be ADR-066's exact shape.
--
-- TENANT 20, its own gym, plus a second gym (tenant 20-B) that exists only to
-- give 20d a cross-tenant session. No assertion depends on another tenant's
-- rows (ADR-050). Every date is read from the gym's own `(now() at time zone
-- o.timezone)::date` via `today_t20`, never `current_date` and never a
-- literal (ADR-039). Every refusal asserts the code AND that the value is
-- unchanged — never the code alone, which passes with a rule that rolls the
-- wrong thing back, and never the value alone, which passes with a rule that
-- silently discards the write.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000200001'::uuid, 'PayRec Gym 20', 'PYR22L'),
  ('22000000-0000-4000-8000-000000200002'::uuid, 'PayRec Gym 20B', 'PYR22M');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000200011'::uuid, '22000000-0000-4000-8000-000000200001'::uuid, 'G20 Main', true),
  ('22000000-0000-4000-8000-000000200012'::uuid, '22000000-0000-4000-8000-000000200002'::uuid, 'G20B Main', true);

-- Five staff in this gym, one per role the matrix distinguishes, so that 20c
-- can assert both directions from real rows rather than from claims alone.
-- Gym 20-B's two exist only to be somebody else's desk and somebody else's
-- owner in 20d.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000200021'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'front_desk', 'T20 Desk'),
  ('22000000-0000-4000-8000-000000200022'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'gym_manager', 'T20 Manager'),
  ('22000000-0000-4000-8000-000000200023'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'gym_owner', 'T20 Owner'),
  ('22000000-0000-4000-8000-000000200024'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'trainer', 'T20 Trainer'),
  ('22000000-0000-4000-8000-000000200025'::uuid, '22000000-0000-4000-8000-000000200002'::uuid,
   '22000000-0000-4000-8000-000000200012'::uuid, 'front_desk', 'T20B Desk'),
  ('22000000-0000-4000-8000-000000200026'::uuid, '22000000-0000-4000-8000-000000200002'::uuid,
   '22000000-0000-4000-8000-000000200012'::uuid, 'gym_owner', 'T20B Owner');

insert into public.organization_settings (tenant_id) values
  ('22000000-0000-4000-8000-000000200001'::uuid);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000200040'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Exploit', '+912200200040'),
  ('22000000-0000-4000-8000-000000200041'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 FourCols', '+912200200041'),
  ('22000000-0000-4000-8000-000000200042'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Matrix', '+912200200042'),
  ('22000000-0000-4000-8000-000000200043'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Paid', '+912200200043'),
  ('22000000-0000-4000-8000-000000200044'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 NoOp', '+912200200044'),
  ('22000000-0000-4000-8000-000000200045'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Shapes', '+912200200045'),
  ('22000000-0000-4000-8000-000000200046'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Sibling', '+912200200046'),
  ('22000000-0000-4000-8000-000000200047'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 DeskWork', '+912200200047'),
  ('22000000-0000-4000-8000-000000200048'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 CrossTenant', '+912200200048');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000200060'::uuid, '22000000-0000-4000-8000-000000200001'::uuid, 'G20 Monthly (30d)', 30, 150000),
  ('22000000-0000-4000-8000-000000200061'::uuid, '22000000-0000-4000-8000-000000200001'::uuid, 'G20 Annual (365d)', 365, 1200000);

create temp table today_t20 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000200001'::uuid;

grant select on today_t20 to public;

-- Every membership sits at `starts_on = ends_on = today` so that one granted
-- period is `today + 30` with nothing else in the arithmetic, and the 300-day
-- outcome ADR-094 measured would be visible as a pure offset. 200086 is the
-- innocent sibling of 20g and is deliberately priced DIFFERENTLY, so that a
-- two-row statement giving two rows two different values is a real shape and
-- not two copies of one.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000200080'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200040'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200081'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200041'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200082'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200042'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200083'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200043'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200084'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200044'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200085'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200045'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000),
  ('22000000-0000-4000-8000-000000200086'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200046'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 200000),
  ('22000000-0000-4000-8000-000000200088'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200048'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000);

-- A live QR session for this gym's own gate, used once at the very end of
-- 20h. The live-membership check in app.enforce_check_in() runs only on the
-- `qr_session_id is not null` branch, so an assisted check-in would pass
-- there for the wrong reason.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('22000000-0000-4000-8000-000000200091'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'pay22-t20-live',
   now() - interval '1 minute', now() + interval '1 hour', null);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- The only membership in this section carrying money before its own
-- subsection begins is 200083, and it earns its period from one ordinary
-- full payment recorded by the desk — 20e's whole point is that the money is
-- real, so it is not hand-set.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000201001'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200043'::uuid, '22000000-0000-4000-8000-000000200083'::uuid,
   150000, 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid);


-- ---------------------------------------------------------------------------
-- 20a (GL046) — ADR-094's own two statements, end to end, on a membership no
-- money has ever touched. The refusal is asserted, and so is the OUTCOME the
-- refusal exists to prevent: the ordinary Rs 1,500 that follows must buy one
-- month and not ten. Asserting only the refusal would pass against a rule
-- that refused the write and let the arithmetic run on a re-priced row, and
-- asserting only the days would pass against a rule that silently discarded
-- the price — the failure this codebase asserts against. Membership 200080.
-- ---------------------------------------------------------------------------

-- 350
select results_eq(
  $$ select periods_granted, price_paise, currency, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200080'::uuid $$,
  $$ select 0, 150000::bigint, 'INR'::text, (select d from today_t20) $$,
  'GL046/exploit: sold on the 30-day plan at Rs 1,500, no money, nothing granted — the state ADR-094 measured from'
);

-- 351 — the first of the two statements.
select throws_ok($$
  update public.memberships set price_paise = 15000
   where id = '22000000-0000-4000-8000-000000200080'::uuid
$$, 'GL046'::char(5), null,
  'GL046/exploit: the front desk cutting the price to a tenth is refused — deciding what a member owes is not the desk''s to decide, whether or not money has arrived');

-- 352
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200080'::uuid $$,
  $$ values (150000::bigint) $$,
  'GL046/exploit: refused AND unmoved — the membership still owes the Rs 1,500 it was sold at'
);

-- 353 — the second statement, which must still work: taking the money is the
-- desk's job and always was.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201002'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200040'::uuid, '22000000-0000-4000-8000-000000200080'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/exploit: the ordinary Rs 1,500 is recorded — the front desk sells at the plan''s price and takes payment, and this rule must not touch that');

-- 354 — the harm, asserted as an outcome. Ten periods and `today + 300` is
-- what ADR-094 measured; one period and `today + 30` is what one month's fee
-- buys.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200080'::uuid $$,
  $$ select 1, (select d from today_t20) + 30 $$,
  'GL046/exploit: one receipt bought exactly one month — not the ten periods and 300 days a re-priced row would have made of the same Rs 1,500, and both audit invariants would have held on that record'
);


-- ---------------------------------------------------------------------------
-- 20b (GL046) — the four columns separately, then together, then one of them
-- riding a column the desk still owns. Membership 200081, no money, so
-- nothing here can be `GL043` answering instead. `discount_paise` is in the
-- list for ADR-094's own reason: bounding the price and leaving the discount
-- free moves the identical exploit to a different column, since
-- `discount = price - 1` is the same 150,000 periods to whoever teaches the
-- granting rule to read it.
-- ---------------------------------------------------------------------------

-- 355
select throws_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: price_paise alone is refused for the front desk');

-- 356
select throws_ok($$
  update public.memberships set currency = 'USD'
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: currency alone is refused — the currency is half of what a price MEANS (MNY-002), and moving it re-denominates every paisa the granting rule will sum');

-- 357
select throws_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000200061'::uuid
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: plan_id alone is refused — a plan change now carries the price and the length with it, so it is a re-pricing by another name');

-- 358
select throws_ok($$
  update public.memberships set discount_paise = 149999
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: discount_paise alone is refused — ADR-094 rejected bounding the discount instead of the price precisely because the two are the same exploit under different names');

-- 359
select results_eq(
  $$ select price_paise, currency, plan_id, discount_paise, periods_granted
       from public.memberships where id = '22000000-0000-4000-8000-000000200081'::uuid $$,
  $$ select 150000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200060'::uuid, 0::bigint, 0 $$,
  'GL046/columns: refused AND unmoved in all four — a rule that answers for some of the list and not the rest is the hole this requirement exists to close'
);

-- 360 — all four in one statement. A rule that inspects one column and
-- returns lets the other three through with it.
select throws_ok($$
  update public.memberships
     set price_paise = 1,
         currency = 'USD',
         plan_id = '22000000-0000-4000-8000-000000200061'::uuid,
         discount_paise = 999
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: all four changed in one statement is refused whole');

-- 361 — one permitted column beside one restricted one. The worst outcome
-- available here is a partial application: the note landing while the price
-- is rolled back, or the reverse.
select throws_ok($$
  update public.memberships set cancel_reason = 'desk note', price_paise = 1
   where id = '22000000-0000-4000-8000-000000200081'::uuid
$$, 'GL046'::char(5), null,
  'GL046/columns: an ordinary note carrying a re-pricing in the same statement is refused — an ordinary write is not a channel for this column');

-- 362
select results_eq(
  $$ select price_paise, currency, plan_id, discount_paise, cancel_reason
       from public.memberships where id = '22000000-0000-4000-8000-000000200081'::uuid $$,
  $$ select 150000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200060'::uuid, 0::bigint, null::text $$,
  'GL046/columns: refused AND NOTHING applied — not the four terms and not the innocent note that shared the statement with one of them'
);


-- ---------------------------------------------------------------------------
-- 20c (GL046) — the role matrix, both directions, on membership 200082 (no
-- money). THIS IS THE SUBSECTION A TOO-BROAD FIX FAILS, and it is the only
-- one: a rule that simply froze these four columns for everybody passes every
-- refusal in 20a, 20b and 20g and fails 363-368 alone. Three times this phase
-- has shipped exactly that shape.
--
-- `trainer` and `member` are not refused BY THIS RULE and are not asserted as
-- if they were: `memberships_tenant_write` is `is_front_office()`, so their
-- rows are filtered out of the UPDATE and the statement raises nothing while
-- changing nothing. The assertion is the pair — it ran, and the value did not
-- move — which is what "refused" means at that layer.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);

-- 363
select lives_ok($$
  update public.memberships set price_paise = 90000
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a gym_manager re-pricing a membership no money has arrived against is ALLOWED — a gym legitimately sells below list, and comping a membership is a real thing gyms do');

-- 364
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200082'::uuid $$,
  $$ values (90000::bigint) $$,
  'GL046/matrix: and it LANDED — allowed and applied, not allowed and silently dropped'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000200023')::text,
  true);

-- 365
select lives_ok($$
  update public.memberships set currency = 'USD'
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a gym_owner changing the currency is allowed');

-- 366
select lives_ok($$
  update public.memberships set discount_paise = 5000
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a gym_owner changing the discount is allowed');

-- 367
select lives_ok($$
  update public.memberships set plan_id = '22000000-0000-4000-8000-000000200061'::uuid
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a gym_owner correcting a mis-sold plan is allowed');

-- 368 — and every one of the four landed, with the plan change carrying the
-- new plan's price, currency and length as ADR-092 requires. A fix that let
-- the statements through and dropped their values would pass 363-367 and
-- fail here.
select results_eq(
  $$ select price_paise, currency, plan_id, discount_paise, to_jsonb(m)->>'duration_days', periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000200082'::uuid $$,
  $$ select 1200000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200061'::uuid, 5000::bigint, '365'::text, 0 $$,
  'GL046/matrix: all four gym-admin edits LANDED — the discount stands, and the plan correction took the Annual plan''s price, currency and 365 days with it'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'trainer',
                    'staff_id', '22000000-0000-4000-8000-000000200024')::text,
  true);

-- 369
select lives_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a trainer''s re-pricing raises nothing — it is filtered by memberships_tenant_write, which is is_front_office(), so no row is reached and this rule is never asked');

-- 370
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200082'::uuid $$,
  $$ values (1200000::bigint) $$,
  'GL046/matrix: and nothing moved — a trainer cannot re-price, and the layer that says so is the policy, not this rule'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'member',
                    'member_id', '22000000-0000-4000-8000-000000200042')::text,
  true);

-- 371
select lives_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/matrix: a member re-pricing their OWN membership raises nothing, for the same reason — the write policy never reaches them');

-- 372
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200082'::uuid $$,
  $$ values (1200000::bigint) $$,
  'GL046/matrix: and nothing moved — the member the price is charged to cannot decide it either'
);

-- The trusted server-side writer, which is EXEMPT. Claims are cleared first:
-- a real webhook call carries no request.jwt.claims at all — and that is the
-- point rather than the problem. ADR-082's general form: a carve-out for
-- trusted callers is sound exactly when the rule's subject is something a
-- trusted caller legitimately lacks. GL046's subject is WHICH STAFF ROLE YOU
-- ARE, and a webhook, a migration and `seed.sql` legitimately have no staff
-- role at all. It is the same line app.enforce_payment() already draws,
-- gating its claim rules behind row_security_active('public.payments') while
-- its integrity rules take no carve-out.
--
-- So GL046 is the FIRST CLAIM RULE in this trigger. GL043, GL044 and GL045
-- are invariants about the data and stay role-agnostic, which is why 157
-- ("a top-level hand-write by postgres itself is refused") is deliberately
-- the other way and must remain so. This assertion and 415/416 are the two
-- halves of that line, asserted in both directions so a later reader can see
-- it was drawn rather than forgotten.
select set_config('request.jwt.claims', '{}', true);
set local role service_role;

-- 373
select lives_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200082'::uuid
$$, 'GL046/trusted: a service_role write is ALLOWED — it carries no app_role because it is not a staff session at all, and a rule whose subject is which staff role you are cannot be asked of it');

set local role postgres;

-- 374
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200082'::uuid $$,
  $$ values (1::bigint) $$,
  'GL046/trusted: and it LANDED — the exemption is real, not an unraised error. seed.sql writes prices and a discount with no claim, and a rule refusing that puts seed-dry-run red in CI'
);


-- ---------------------------------------------------------------------------
-- 20d (ADR-066) — the tenant boundary, which this rule must not answer ahead
-- of. Membership 200088 belongs to gym 20 and no money has touched it. The
-- verification reads are made from a gym-20 session on purpose: a gym-20B
-- session cannot SELECT this row either, so a results_eq run under the
-- attacker's own claim would return nothing and pass for the wrong reason.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 375
select results_eq(
  $$ select tenant_id, price_paise, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000200088'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200001'::uuid, 150000::bigint, 0 $$,
  'GL046/tenant: gym 20''s own membership, at the price it was sold, with no money on it — so nothing below can be GL043 answering'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200025')::text,
  true);

-- 376
select lives_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200088'::uuid
$$, 'GL046/tenant: another gym''s front desk reaching into this gym''s membership raises nothing — the row is not visible to its UPDATE, so no trigger fires and this rule is never asked about a row the session cannot see');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200002',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000200026')::text,
  true);

-- 377 — the sharper half: a session this rule WOULD permit, in the wrong
-- gym. Being a gym admin is not being a gym admin here.
select lives_ok($$
  update public.memberships set price_paise = 1
   where id = '22000000-0000-4000-8000-000000200088'::uuid
$$, 'GL046/tenant: another gym''s OWNER reaching in raises nothing either — this rule permits the role and the policy still refuses the row, which is the right order');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000200023')::text,
  true);

-- 378
select results_eq(
  $$ select tenant_id, price_paise from public.memberships
      where id = '22000000-0000-4000-8000-000000200088'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200001'::uuid, 150000::bigint $$,
  'GL046/tenant: neither cross-tenant statement moved anything — a gym admin''s reach stops at their own gym'
);

-- 379 — the one place in 20d where a real code is pinned. This gym's own
-- owner moves its membership into the other gym and re-prices it in the same
-- statement. GL046 permits this session, so what must answer is the policy's
-- `with check` — 42501. A rule raising GL046 here would be answering ahead of
-- the boundary it was meant to respect, which is ADR-066's exact shape.
select throws_ok($$
  update public.memberships
     set tenant_id = '22000000-0000-4000-8000-000000200002'::uuid,
         price_paise = 1
   where id = '22000000-0000-4000-8000-000000200088'::uuid
$$, '42501'::char(5), null,
  'GL046/tenant: a gym admin moving its own membership into another gym while re-pricing it is answered by the policy, not by this rule — the row is visible so this is a with-check refusal and not a filtered update');

-- 380
select results_eq(
  $$ select tenant_id, price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200088'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200001'::uuid, 150000::bigint $$,
  'GL046/tenant: refused AND unmoved in both columns — the membership is still this gym''s and still owes what it was sold at'
);


-- ---------------------------------------------------------------------------
-- 20e (GL046 vs GL043) — the ordering, on membership 200083, which earned one
-- real period from one real Rs 1,500. Both rules refuse; the section header
-- states why GL043 is the answer asserted and what asserting GL046 instead
-- would cost this file.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);

-- 381
select results_eq(
  $$ select periods_granted, price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200083'::uuid $$,
  $$ select 1, 150000::bigint, (select d from today_t20) + 30 $$,
  'GL046/order: one period earned by one ordinary full payment — money is on this row, so both rules now apply to it'
);

-- 382
select throws_ok($$
  update public.memberships set price_paise = 50000
   where id = '22000000-0000-4000-8000-000000200083'::uuid
$$, 'GL043'::char(5), null,
  'GL046/order: the front desk cutting the price of a membership money has bought is answered by GL043, not GL046 — the money freeze is an absolute and the authority rule is a permission, and telling a desk "you are not an admin" would imply an admin could still do it, which 384 shows is false');

-- 383
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-000000200083'::uuid $$,
  $$ values (150000::bigint) $$,
  'GL046/order: refused AND unmoved'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);

-- 384 — the spec's own "A gym admin after money has arrived" scenario.
select throws_ok($$
  update public.memberships set price_paise = 50000
   where id = '22000000-0000-4000-8000-000000200083'::uuid
$$, 'GL043'::char(5), null,
  'GL046/order: the same cut by a gym_manager is refused too, with the same GL043 — being a gym admin does not unfreeze what money has bought, and the honest instrument afterwards is a refund and a new membership');

-- 385
select results_eq(
  $$ select price_paise, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200083'::uuid $$,
  $$ select 150000::bigint, 1, (select d from today_t20) + 30 $$,
  'GL046/order: refused AND unmoved for the admin as well — this requirement widens who may re-price a FREE membership, it does not narrow what money freezes'
);


-- ---------------------------------------------------------------------------
-- 20f (GL046) — the no-op. The requirement's verb is "changes"; its sibling
-- one heading up settles the identical question for `periods_granted` in as
-- many words. A rule reading the statement's column list rather than the
-- values takes down every column-listing update the product sends, including
-- its own create and edit paths. Membership 200084, front desk, no money.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);

-- 386
select lives_ok($$
  update public.memberships
     set price_paise = price_paise,
         currency = currency,
         plan_id = plan_id,
         discount_paise = discount_paise
   where id = '22000000-0000-4000-8000-000000200084'::uuid
$$, 'GL046/no-op: the front desk writing all four columns their own current values is allowed — nothing changed, so nothing was decided');

-- 387 — the literal form, which is what an ORM or any column-listing update
-- actually sends, and which a rule comparing values rather than column lists
-- has to get right the same way.
select lives_ok($$
  update public.memberships
     set price_paise = 150000,
         currency = 'INR',
         plan_id = '22000000-0000-4000-8000-000000200060'::uuid,
         discount_paise = 0,
         cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000200084'::uuid
$$, 'GL046/no-op: the same four values as literals, beside an ordinary note, is allowed — `is distinct from` is this codebase''s idiom for exactly this and the sibling requirement settles it the same way');

-- 388
select results_eq(
  $$ select price_paise, currency, plan_id, discount_paise, cancel_reason, periods_granted
       from public.memberships where id = '22000000-0000-4000-8000-000000200084'::uuid $$,
  $$ select 150000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200060'::uuid, 0::bigint, 'desk note'::text, 0 $$,
  'GL046/no-op: allowed AND applied — the note landed and none of the four terms moved a paisa'
);


-- ---------------------------------------------------------------------------
-- 20g (GL046) — every statement shape a rule written as a single-row guard
-- does not see. Membership 200085 is the target and 200086 the innocent
-- sibling, priced differently on purpose so that 392 gives two rows two
-- genuinely different values. Neither has any money, so nothing here can be
-- GL043 answering instead.
-- ---------------------------------------------------------------------------

-- 389
select throws_ok($$
  update public.memberships m set price_paise = p.price_paise - 149999
    from public.plans p
   where p.id = '22000000-0000-4000-8000-000000200060'::uuid
     and m.id = '22000000-0000-4000-8000-000000200085'::uuid
$$, 'GL046'::char(5), null,
  'GL046/shapes: the re-pricing written as UPDATE … FROM, with the new value computed from a joined plan row rather than typed, is refused');

-- 390
select throws_ok($$
  merge into public.memberships m
  using (select '22000000-0000-4000-8000-000000200085'::uuid as id) s
     on m.id = s.id
   when matched then update set price_paise = 1
$$, 'GL046'::char(5), null,
  'GL046/shapes: the re-pricing written as MERGE is refused — ADR-087 records MERGE walking round a rule on this very table once already');

-- 391
select throws_ok($$
  with repriced as (
    update public.memberships set discount_paise = 149999
     where id = '22000000-0000-4000-8000-000000200085'::uuid
    returning id
  ) select count(*) from repriced
$$, 'GL046'::char(5), null,
  'GL046/shapes: the discount hidden in a data-modifying CTE is refused — the third of ADR-087''s three costumes');

-- 392 — one statement, two memberships, two DIFFERENT prices. A rule that
-- checks a statement's rows as a set, or stops at the first row that looks
-- fine, lets this through.
select throws_ok($$
  update public.memberships m set price_paise = v.p
    from (values ('22000000-0000-4000-8000-000000200085'::uuid, 1::bigint),
                 ('22000000-0000-4000-8000-000000200086'::uuid, 2::bigint)) as v(id, p)
   where m.id = v.id
$$, 'GL046'::char(5), null,
  'GL046/shapes: a two-row statement giving two memberships two different prices is refused — the innocent sibling is in the statement precisely so that a rule which answers per-statement instead of per-row is visible');

-- 393
select results_eq(
  $$ select id, price_paise, discount_paise from public.memberships
      where id in ('22000000-0000-4000-8000-000000200085'::uuid, '22000000-0000-4000-8000-000000200086'::uuid)
      order by id $$,
  $$ values ('22000000-0000-4000-8000-000000200085'::uuid, 150000::bigint, 0::bigint),
            ('22000000-0000-4000-8000-000000200086'::uuid, 200000::bigint, 0::bigint) $$,
  'GL046/shapes: refused AND unmoved through all four shapes — both memberships still owe exactly what each was sold at, and the sibling was never in either statement''s way'
);


-- ---------------------------------------------------------------------------
-- 20h (GL046, the permitted side) — everything the front desk must STILL be
-- able to do. This is the subsection a fix that is too broad fails, and if
-- any of it breaks the failure is critical and silent: a gym whose desk
-- cannot sell, take money or open the gate is a gym that stops working, and
-- none of the refusal assertions above would notice. Member 200047, whose
-- membership is CREATED inside the assertion rather than staged as a fixture,
-- because creating a membership at the plan's price is itself one of the
-- things the requirement promises the desk keeps.
-- ---------------------------------------------------------------------------

-- 394
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
  values ('22000000-0000-4000-8000-000000200087'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200047'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'active', (select d from today_t20), (select d from today_t20), 150000, 'INR')
$$, 'GL046/desk: the front desk creates a membership at its plan''s price — "the front desk sells at the plan''s price and takes payment" is the requirement''s own sentence, and creation is not a change of terms');

-- 395
select results_eq(
  $$ select price_paise, currency, plan_id, to_jsonb(m)->>'duration_days', periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000200087'::uuid $$,
  $$ select 150000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200060'::uuid, '30'::text, 0 $$,
  'GL046/desk: and it landed at the plan''s price and the plan''s length, granted nothing'
);

-- 396
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201003'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200047'::uuid, '22000000-0000-4000-8000-000000200087'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/desk: the desk records the payment');

-- 397
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000200087'::uuid $$,
  $$ select 1, (select d from today_t20) + 30 $$,
  'GL046/desk: it bought exactly one month'
);

-- 398
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201004'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200047'::uuid, '22000000-0000-4000-8000-000000200087'::uuid,
          150000, 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/desk: the desk takes the renewal — the granting rule''s own write to the membership is not a change of terms, and a rule that could not tell the two apart would stop every renewal in the product');

-- 399
select results_eq(
  $$ select periods_granted, ends_on from public.memberships where id = '22000000-0000-4000-8000-000000200087'::uuid $$,
  $$ select 2, (select d from today_t20) + 60 $$,
  'GL046/desk: two periods, sixty days — the renewal landed'
);

-- 400
select lives_ok($$
  insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values ('22000000-0000-4000-8000-000000202001'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200087'::uuid,
          (select d from today_t20) + 1, (select d from today_t20) + 5,
          'travel', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/desk: the desk requests a freeze — a pause is not a term of what the member owes');

-- 401
select lives_ok($$
  update public.memberships set cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000200087'::uuid
$$, 'GL046/desk: the desk edits the note');

-- 402
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-000000200087'::uuid
$$, 'GL046/desk: the desk freezes the membership — a status is not a price');

-- 403
select results_eq(
  $$ select cancel_reason, status, price_paise, currency, plan_id, discount_paise
       from public.memberships where id = '22000000-0000-4000-8000-000000200087'::uuid $$,
  $$ select 'desk note'::text, 'frozen'::public.membership_status, 150000::bigint, 'INR'::text,
            '22000000-0000-4000-8000-000000200060'::uuid, 0::bigint $$,
  'GL046/desk: both ordinary edits LANDED — allowed and applied, not allowed and silently dropped — while all four terms stayed exactly as sold'
);

-- 404 — the gate. A `frozen` membership with today inside its dates admits
-- its member, and the desk is who scans them in. Proven through the check-in
-- gate's own already-built logic rather than asserted as a status value: the
-- live-membership check runs only on the `qr_session_id is not null` branch,
-- so an assisted check-in would pass here for the wrong reason.
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200011'::uuid,
          '22000000-0000-4000-8000-000000200047'::uuid, 'qr',
          '22000000-0000-4000-8000-000000200091'::uuid)
$$, 'GL046/desk: and the member this whole section sold to, paid for and froze is admitted at the gate — the loop this product exists for still closes end to end with the desk''s own hands');



-- ---------------------------------------------------------------------------
-- 20i (GL046 at creation) — the fourth door, and the trusted-context line.
--
-- WHY THIS SUBSECTION EXISTS. GL046's sentence governs a session that CHANGES
-- those columns, and its own "A front desk selling and taking money" scenario
-- permits the creation. Measured live before this subsection was written:
--
--     insert into public.memberships (… price_paise) values (… 15000);  -- a 30-day, Rs 1,500 plan
--     insert into public.payments    (… 150000, 'paid', 'cash' …);      -- the ordinary Rs 1,500
--
--     price_paise = 15000   periods_granted = 10   ends_on 300 days out
--
-- ADR-094's own numbers, from an ordinary front-desk session, in ONE FEWER
-- STATEMENT than the exploit it was written to close. The count rule closed
-- its own creation door for exactly this reason ("closing three doors and
-- leaving the fourth is the mistake this whole requirement exists to
-- correct"); this one now does too.
--
-- THE LINE THE COORDINATOR DREW, ASSERTED IN BOTH DIRECTIONS. A membership
-- created with a price or a currency differing from its plan's, or with a
-- non-zero discount, is gym-admin work — GL046 otherwise. `plan_id` at
-- creation is just choosing a plan and is unrestricted (409/410): selling the
-- Annual instead of the Monthly is the desk's job, selling either below list
-- is not. And the trusted contexts are exempt at creation exactly as at
-- update (415/416), which is the seed's own shape.
--
-- Every membership here is `pending` with null dates — permitted by
-- memberships_dated_unless_pending_chk, outside the unique partial index on
-- (tenant_id, member_id) that covers only live rows, and deliberately
-- date-free so that OPEN-029's separate creation hole is nowhere in this
-- arithmetic. Member 200049 carries all of them.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Creation', '+912200200049');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 405 — the measured exploit's own first statement.
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise)
  values ('22000000-0000-4000-8000-000000200089'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 15000)
$$, 'GL046'::char(5), null,
  'GL046/creation: the front desk creating a membership at a tenth of its plan''s price is refused — selling below list is the manager''s, at creation exactly as on update, and this is the door the ten-periods exploit walks through in one statement instead of two');

-- 406
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency)
  values ('22000000-0000-4000-8000-00000020008a'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 'USD')
$$, 'GL046'::char(5), null,
  'GL046/creation: the plan''s own number in another currency is refused too — the currency is half of what a price MEANS (MNY-002), and the right number in the wrong denomination is not the plan''s price');

-- 407
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, discount_paise)
  values ('22000000-0000-4000-8000-00000020008b'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 5000)
$$, 'GL046'::char(5), null,
  'GL046/creation: a discount named at creation is refused — the list price with a discount beside it is the same decision as a lower price, which is why ADR-094 put the two columns in one list');

-- 408
select results_eq(
  $$ select count(*)::int from public.memberships
      where id in ('22000000-0000-4000-8000-000000200089'::uuid,
                   '22000000-0000-4000-8000-00000020008a'::uuid,
                   '22000000-0000-4000-8000-00000020008b'::uuid) $$,
  $$ values (0) $$,
  'GL046/creation: refused AND no row landed — none of the three exists, so nothing is sitting there waiting for a payment to be scored against it'
);

-- 409 — plan_id at creation is unrestricted: choosing which plan to sell is
-- the desk's job. A fix reading "the front desk may create only on one plan"
-- would pass every refusal above and fail here.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise)
  values ('22000000-0000-4000-8000-00000020008c'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200061'::uuid,
          'pending', 1200000)
$$, 'GL046/creation: the front desk selling the ANNUAL plan at the Annual plan''s own price is allowed — picking a plan is not deciding what a member owes');

-- 410
select results_eq(
  $$ select price_paise, currency, plan_id, discount_paise, to_jsonb(m)->>'duration_days'
       from public.memberships m where m.id = '22000000-0000-4000-8000-00000020008c'::uuid $$,
  $$ select 1200000::bigint, 'INR'::text, '22000000-0000-4000-8000-000000200061'::uuid, 0::bigint, '365'::text $$,
  'GL046/creation: and it landed at that plan''s price, that plan''s currency and that plan''s 365 days'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);

-- 411
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise)
  values ('22000000-0000-4000-8000-00000020008d'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 15000)
$$, 'GL046/creation: a gym_manager creating the SAME membership at the SAME tenth of the list price is allowed — the control is who, not what, and comping a membership is a real thing gyms do');

-- 412
select results_eq(
  $$ select price_paise from public.memberships where id = '22000000-0000-4000-8000-00000020008d'::uuid $$,
  $$ values (15000::bigint) $$,
  'GL046/creation: and it LANDED — the negotiated number sits on the row as evidence, which is the bound ADR-094 accepted'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000200023')::text,
  true);

-- 413
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, discount_paise)
  values ('22000000-0000-4000-8000-00000020008e'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 'USD', 5000)
$$, 'GL046/creation: a gym_owner naming a currency and a discount at creation is allowed — all three restricted columns at once, from the role the requirement names');

-- 414
select results_eq(
  $$ select price_paise, currency, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-00000020008e'::uuid $$,
  $$ select 150000::bigint, 'USD'::text, 5000::bigint $$,
  'GL046/creation: and all three landed as named'
);

-- The trusted context at creation, which is the seed's own shape: no claim at
-- all, a price below the plan's and a discount beside it. `supabase/seed.sql`
-- writes exactly this, and a rule refusing it puts seed-dry-run red in CI.
select set_config('request.jwt.claims', '{}', true);
set local role postgres;

-- 415
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, discount_paise)
  values ('22000000-0000-4000-8000-00000020008f'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200049'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 90000, 5000)
$$, 'GL046/trusted: a claimless trusted write creating a discounted membership below list is ALLOWED — the seed and every migration do exactly this, and GL046''s subject is a staff role they legitimately do not have');

-- 416
select results_eq(
  $$ select price_paise, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-00000020008f'::uuid $$,
  $$ select 90000::bigint, 5000::bigint $$,
  'GL046/trusted: and it LANDED — the exemption is asserted in both directions, here and at 373/374, so the line between this claim rule and the role-agnostic invariants beside it (157) is visible rather than inferred'
);


-- ===========================================================================
-- SECTION 21 (ROUND TWELVE) — `coupon_id` joins GL046's list.
--
-- A DELIBERATE, RECORDED DEVIATION FROM THE TWO-AUTHOR ARRANGEMENT (hard rule
-- 10 / ADR-059): sections 21 and 22 of THIS file and the round-twelve sections
-- of `supabase/tests-holdout/h22_payment_record_holdout.sql` were written by
-- the SAME author. The independence was traded knowingly, and the reason is
-- that there is nothing left for two authors to converge on: `coupon_id` is
-- one more column on a rule both suites already carry full batteries for, and
-- the repair path below is a sequence of writes each of which is already
-- specified and already asserted somewhere in these two files. What the blind
-- arrangement buys is independent INTERPRETATION of a requirement; this round
-- has no interpretation left to make. It is recorded here rather than in a
-- commit message so the next reader of this file knows it was traded and not
-- forgotten.
--
-- WHY coupon_id IS IN THE LIST. A critic measured a front desk attaching a
-- 10%-off coupon while being refused the discount it implies — measured again
-- live before this section was written, on an ordinary front-desk session:
--
--     update memberships set coupon_id     = <a live coupon> …;  -- OK
--     update memberships set discount_paise = 15000 …;           -- GL046
--
--     coupon_id = <the coupon>   discount_paise = 0
--
-- A row reading "coupon applied, discount zero" is a worse record than either
-- outcome on its own: the gym's own book says a discount was granted and its
-- own money says it was not, and nothing raises. `coupon_id` is the column
-- that names WHY a member owes less, so it is the same decision as the
-- discount and belongs to the same role — either both are gym-admin work or
-- neither is.
--
-- The shape is 20b's and 20c's and 20i's, deliberately: refused for the desk
-- with the value unchanged, allowed for a gym admin and LANDED, on UPDATE and
-- at creation, with the no-op and the trusted carve-out asserted beside them
-- exactly as 20f and 20i assert them for the other four columns. A rule that
-- handles four of the five columns is the hole this requirement keeps
-- growing back.
-- ---------------------------------------------------------------------------

set local role postgres;

-- One live coupon in this gym. `coupons` carries a composite tenant foreign
-- key (ADR-052), so a coupon a membership may name must be this tenant's own;
-- a coupon from another gym would be refused by the FK and would prove
-- nothing about GL046.
insert into public.coupons (id, tenant_id, code, percent_bp, currency, is_active) values
  ('22000000-0000-4000-8000-000000200070'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   'PYR2210', 1000, 'INR', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000200050'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Coupon', '+912200200050'),
  ('22000000-0000-4000-8000-000000200051'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 CouponCreate', '+912200200051');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000200090'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200050'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 417
select throws_ok($$
  update public.memberships set coupon_id = '22000000-0000-4000-8000-000000200070'::uuid
   where id = '22000000-0000-4000-8000-000000200090'::uuid
$$, 'GL046'::char(5), null,
  'GL046/coupon: coupon_id alone is refused for the front desk — it is the column that names why a member owes less, which is the same decision as the discount that names how much');

-- 418
select results_eq(
  $$ select coupon_id from public.memberships where id = '22000000-0000-4000-8000-000000200090'::uuid $$,
  $$ values (null::uuid) $$,
  'GL046/coupon: refused AND unmoved — no coupon is attached'
);

-- 419 — the critic's own statement, both halves in one place. Measured live
-- before this section was written: the coupon landed and the discount was
-- refused, leaving the row saying two contradictory things at once.
select throws_ok($$
  update public.memberships
     set coupon_id = '22000000-0000-4000-8000-000000200070'::uuid,
         discount_paise = 15000
   where id = '22000000-0000-4000-8000-000000200090'::uuid
$$, 'GL046'::char(5), null,
  'GL046/coupon: the coupon and the discount it implies, in one statement, are refused together');

-- 420
select results_eq(
  $$ select coupon_id, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-000000200090'::uuid $$,
  $$ select null::uuid, 0::bigint $$,
  'GL046/coupon: and NEITHER landed — this is the assertion that fails on the defect as found, where the coupon went on and the discount did not, and the gym''s book disagreed with the gym''s money with nothing raised'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);

-- 421
select lives_ok($$
  update public.memberships
     set coupon_id = '22000000-0000-4000-8000-000000200070'::uuid,
         discount_paise = 15000
   where id = '22000000-0000-4000-8000-000000200090'::uuid
$$, 'GL046/coupon: a gym_manager applying the same coupon and the same discount is ALLOWED — granting a coupon is a real thing a gym does, and the control is who, not what');

-- 422
select results_eq(
  $$ select coupon_id, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-000000200090'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200070'::uuid, 15000::bigint $$,
  'GL046/coupon: and BOTH landed — allowed and applied, not allowed and silently dropped'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);

-- 423 — the no-op, 20f's assertion with the fifth column in it. `coupon_id`
-- is nullable, so a rule written with `<>` rather than `is distinct from`
-- gets this wrong in one direction or the other on this column specifically.
select lives_ok($$
  update public.memberships
     set coupon_id = coupon_id,
         discount_paise = discount_paise,
         price_paise = price_paise,
         cancel_reason = 'desk note'
   where id = '22000000-0000-4000-8000-000000200090'::uuid
$$, 'GL046/coupon: the front desk writing coupon_id back at its own value beside an ordinary note is allowed — nothing changed, so nothing was decided, and the product''s own column-listing save sends exactly this');

-- 424
select results_eq(
  $$ select coupon_id, discount_paise, cancel_reason from public.memberships
      where id = '22000000-0000-4000-8000-000000200090'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200070'::uuid, 15000::bigint, 'desk note'::text $$,
  'GL046/coupon: allowed AND applied — the note landed and the coupon the manager granted is still on the row'
);

-- 425 — creation, which is where the last three rounds each found the door.
-- Everything else about this row is the desk's to write: the plan's own
-- price, the plan's own currency, no discount. The coupon is the only
-- offending column in it.
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id)
  values ('22000000-0000-4000-8000-00000020009a'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200051'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 'INR', '22000000-0000-4000-8000-000000200070'::uuid)
$$, 'GL046'::char(5), null,
  'GL046/coupon: the front desk CREATING a membership carrying a coupon is refused — selling with a coupon attached is the same decision as selling below list, and creation is the door this requirement has now had to close twice');

-- 426
select results_eq(
  $$ select count(*)::int from public.memberships
      where id = '22000000-0000-4000-8000-00000020009a'::uuid $$,
  $$ values (0) $$,
  'GL046/coupon: refused AND no row landed — nothing is sitting there with a coupon on it waiting for a discount to be read off it'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000200023')::text,
  true);

-- 427
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id, discount_paise)
  values ('22000000-0000-4000-8000-00000020009b'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200051'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 'INR', '22000000-0000-4000-8000-000000200070'::uuid, 15000)
$$, 'GL046/coupon: a gym_owner creating the same membership with the same coupon and the discount it implies is allowed');

-- 428
select results_eq(
  $$ select coupon_id, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-00000020009b'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200070'::uuid, 15000::bigint $$,
  'GL046/coupon: and it landed as named — the coupon and the discount agree with each other, which is the state this column joins the list to protect'
);

-- The trusted carve-out, on this column specifically: `supabase/seed.sql`
-- writes `coupon_id` in its membership upsert, as the CLI's claimless
-- `postgres` session, on the demo gym's one discounted membership. A rule
-- without ADR-082's carve-out puts seed-dry-run red in CI on this column
-- exactly as 415/416 says it would on the other four.
select set_config('request.jwt.claims', '{}', true);
set local role postgres;

-- 429
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id, discount_paise)
  values ('22000000-0000-4000-8000-00000020009c'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200051'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'pending', 150000, 'INR', '22000000-0000-4000-8000-000000200070'::uuid, 15000)
$$, 'GL046/coupon: a claimless trusted write attaching a coupon is ALLOWED — seed.sql''s own membership block writes coupon_id and discount_paise together with no app_role anywhere, and GL046''s subject is a staff role it legitimately does not have');

-- 430
select results_eq(
  $$ select coupon_id, discount_paise from public.memberships
      where id = '22000000-0000-4000-8000-00000020009c'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000200070'::uuid, 15000::bigint $$,
  'GL046/coupon: and it LANDED — the carve-out asserted in both directions on the fifth column too'
);


-- ===========================================================================
-- SECTION 22 (ROUND TWELVE) — "A comp that was a typo": the repair path
-- asserted as a working sequence rather than as an absence.
--
-- WHY THIS SECTION EXISTS. GL046 moves who may set a price; it does not stop
-- one being mistyped, and a gym admin typing Rs 150 for Rs 1,500 is now the
-- shape that remains. Once money lands on that row the price is frozen
-- (GL043) and the dates are frozen (GL045), so there is nothing to correct in
-- place — the requirement says so in its own prose and names unrepairability
-- as the harm the previous round made worse. Its answer is a sequence:
-- **refund, cancel, sell again.**
--
-- Nobody had run that sequence end to end. This section does, as one story on
-- one member, and every step of it is asserted — including the two refusals
-- that make the sequence necessary, so that a future round which quietly
-- unfreezes the price is visible here as two assertions going green in the
-- wrong direction rather than as a passing file.
--
-- MEASURED LIVE BEFORE THIS SECTION WAS WRITTEN, against the schema as it
-- stands: every step works, and the arithmetic at the end is exactly
-- `today + 30`. So these assertions are GREEN today and are here to stay
-- green — they are the requirement's own remedy, load-bearing for a sentence
-- that currently rests on nothing having tried it.
--
-- THE ONE THING THIS SECTION PROVES THAT ISN'T OBVIOUS: **the refund is not
-- the repair.** 439 asserts that after a full refund the membership still
-- reads ten periods and still ends 300 days out — money that arrived counts
-- toward the total whether or not it was given back, so a refund reverses the
-- money and not what the money bought. That is why the requirement says
-- CANCEL as well, and why "refund and re-sell" without the cancel would leave
-- a live, wrongly-dated membership at the gate.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000200052'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M20 Typo', '+912200200052');

-- Its own gate session, rather than sharing 20h's: a repair that ends in a
-- member being admitted should not be able to fail for a reason belonging to
-- another section's fixture.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('22000000-0000-4000-8000-000000200095'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'pay22-t20-live-repair',
   now() - interval '1 minute', now() + interval '1 hour', null);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);
set local role authenticated;

-- 431 — the typo. A manager may comp a membership to a paisa and should be
-- able to (ADR-094's own words), which is exactly why a manager can also
-- fat-finger one: GL046 makes this the only remaining way in, and the
-- requirement accepts that and says what to do about it.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
  values ('22000000-0000-4000-8000-000000200092'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200052'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'active', (select d from today_t20), (select d from today_t20), 15000, 'INR')
$$, 'GL046/repair: a gym_manager sells at Rs 150 where the plan lists Rs 1,500 — a typo, allowed, and indistinguishable at the moment it is made from the comp the requirement protects');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);

-- 432
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201005'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200052'::uuid, '22000000-0000-4000-8000-000000200092'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/repair: and the member pays the ordinary Rs 1,500 for it');

-- 433 — the damage, on the record, with both audit invariants intact.
select results_eq(
  $$ select periods_granted, price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200092'::uuid $$,
  $$ select 10, 15000::bigint, (select d from today_t20) + 300 $$,
  'GL046/repair: ten periods and 300 days for one month''s fee — the state the whole of this requirement is about, reached here through a typo rather than through a role'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);

-- 434
select throws_ok($$
  update public.memberships set price_paise = 150000
   where id = '22000000-0000-4000-8000-000000200092'::uuid
$$, 'GL043'::char(5), null,
  'GL046/repair: the manager cannot correct the price in place — money has arrived and GL043 is an absolute, so being the role that may set a price does not unfreeze one');

-- 435
select throws_ok($$
  update public.memberships set ends_on = (select d from today_t20) + 30
   where id = '22000000-0000-4000-8000-000000200092'::uuid
$$, 'GL045'::char(5), null,
  'GL046/repair: and cannot type the dates back either — GL045 makes them the granting rule''s alone. These two refusals are why the repair below has to be a sequence, and they are asserted here so that a round which quietly unfreezes either is visible as a green assertion pointing the wrong way');

-- 436
select results_eq(
  $$ select price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200092'::uuid $$,
  $$ select 15000::bigint, (select d from today_t20) + 300 $$,
  'GL046/repair: refused AND unmoved in both — the row is exactly as wrong as it was, which is the premise the remedy has to work from'
);

-- 437 — step one: give the money back. `refunds_tenant_write` is
-- `is_gym_admin()`, which is the precedent GL046 was built on, so the
-- remedy for a gym admin's typo is available to a gym admin and to nobody
-- else — the desk that sold it cannot start the repair.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000203001'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000201005'::uuid, 'refund', 150000, 'INR',
          'mis-priced sale, re-sold at the plan price',
          '22000000-0000-4000-8000-000000200022'::uuid)
$$, 'GL046/repair: step one — the manager refunds the payment in full, attributed to themselves');

-- 438
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-000000201005'::uuid
$$, 'GL046/repair: and the payment moves paid → refunded, which is one of the two edges out of paid the transition rule permits');

-- 439 — THE ASSERTION THAT MAKES THE CANCEL NECESSARY. Refunded money still
-- counts toward the total a period is scored against, so nothing about the
-- membership moves when it is given back.
select results_eq(
  $$ select periods_granted, ends_on, status from public.memberships
      where id = '22000000-0000-4000-8000-000000200092'::uuid $$,
  $$ select 10, (select d from today_t20) + 300, 'active'::public.membership_status $$,
  'GL046/repair: and the membership has NOT moved — still ten periods, still 300 days, still live at the gate. A refund reverses the money, not what the money bought, which is exactly why the remedy is three steps and not one'
);

-- 440
select lives_ok($$
  update public.memberships
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'sold at the wrong price; refunded and re-sold'
   where id = '22000000-0000-4000-8000-000000200092'::uuid
$$, 'GL046/repair: step two — the membership is cancelled. A status is not a term, so this stays available after money has arrived, which is the whole reason the requirement can name this remedy at all');

-- 441
select results_eq(
  $$ select status, periods_granted, price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200092'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 10, 15000::bigint, (select d from today_t20) + 300 $$,
  'GL046/repair: cancelled, and the wrong price and the wrong dates are STILL ON THE ROW. The repair does not erase the mistake, it retires it — the mis-sale, the money and the refund all stay on the books, which is what makes this an audit trail rather than an edit'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);

-- 442 — step three, and it is the DESK's again: selling at the plan's own
-- price is front-desk work, so the repair hands the gym back to the people
-- who run it rather than requiring an admin for the whole of it.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
  values ('22000000-0000-4000-8000-000000200093'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200052'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'active', (select d from today_t20), (select d from today_t20), 150000, 'INR')
$$, 'GL046/repair: step three — the desk sells the member a new membership at the plan''s price. The cancelled row is out of the live partial unique index, so the member may hold this one');

-- 443
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201006'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200052'::uuid, '22000000-0000-4000-8000-000000200093'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'GL046/repair: and takes the Rs 1,500 again — the money the member actually owes, against the membership that actually says so');

-- 444 — the whole point: the repaired sale grants what a month's fee buys,
-- and the 300 days do not follow the member across.
select results_eq(
  $$ select periods_granted, price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000200093'::uuid $$,
  $$ select 1, 150000::bigint, (select d from today_t20) + 30 $$,
  'GL046/repair: ONE period, thirty days, at the price the plan lists — the refund, the cancel and the re-sale together put the member where the honest sale would have put them, and this is the assertion that says the requirement''s remedy is a real path and not a sentence'
);

-- 445 — and the loop closes: the member the gym mis-sold, refunded and
-- re-sold walks through the gate.
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200011'::uuid,
          '22000000-0000-4000-8000-000000200052'::uuid, 'qr',
          '22000000-0000-4000-8000-000000200095'::uuid)
$$, 'GL046/repair: and the member is admitted — the repair produced a membership that WORKS, not merely one whose columns read correctly');



-- ===========================================================================
-- SECTION 23 (ROUND THIRTEEN) — "Money does not extend a membership that has
-- been retired."
--
-- WHY THIS SECTION EXISTS. `app.grant_periods()` reads a membership's price,
-- currency, dates, count and length and never its STATUS. Section 22 above
-- proves the repair the phase prescribes for a mis-sold membership — refund,
-- cancel, sell again — actually works. This section walks the same sequence
-- one step further, to the step the console cannot reach but
-- `POST /api/payments` can: the payment names the RETIRED membership instead
-- of the new one. `GL042` checks only that the member matches, and on the
-- repair path the member matches both. Measured by a critic on exactly that:
--
--     ends_on 14347-04-10 / periods 150000  ->  ends_on 26667-11-08 /
--     periods 300000, status = cancelled
--
-- The money is recorded and receipted, the cancelled row's dates move, and
-- the member is still refused at the gate, because the gate reads status and
-- the granting rule does not. **The repair path is exactly the moment a member
-- holds two memberships one of which is retired**, so this is reachable
-- precisely when the product tells someone to do it.
--
-- THE PAYMENT IS RECORDED. That half is not a concession, it is the
-- requirement: the money changed hands and a refusal after the fact leaves
-- cash in a drawer with nothing to show for it. So this section asserts the
-- payment is a FULL first-class payment — receipt allocated off the gym's own
-- counter, `paid_at` stamped, attribution still enforced, refundable, and
-- counted by the refund ceiling — as hard as it asserts the membership does
-- not move. **A rule that quietly refuses the payment instead of quietly not
-- extending is a different rule and a worse one**, and it would pass every
-- refusal assertion here if the permitted side were not nailed down beside it.
--
-- AND THE PERMITTED SIDE IS ASSERTED AS HARD AS THE REFUSED SIDE. A rule that
-- simply stops extending everything passes every "does not move" assertion in
-- this file, and this project has shipped that shape three times. So every
-- live status gets its own membership and its own arithmetic: `active` (460),
-- `frozen` (469) and `pending` (471) each take a full payment and each must
-- end thirty days out. 484 is the sharpest of them — one statement writing two
-- payments, one naming a cancelled membership and one naming a live one, where
-- the cancelled row must not move and the live row must. A rule enforced per
-- STATEMENT rather than per ROW cannot pass 483 and 484 together.
--
-- 458 is the other direction of the same worry: the live membership the member
-- also holds must not move EITHER. Money named the retired row; a fix that
-- helpfully redirects it to the live one has invented a rule nobody wrote, and
-- would be indistinguishable from the correct one without this assertion.
--
-- WHAT IS ALREADY GREEN AND MUST STAY GREEN: 446-456, 458-466, 468-473 and
-- 476-480 — the repair sequence itself, the live statuses extending, the
-- payment being recorded, receipted, attributed and refundable, and the fact
-- that a membership cancelled AFTER money arrived keeps what the money already
-- bought (479: nothing here reverses history, the same fact Section 22's 439
-- records for refunds).
--
-- SHAPES. Every write shape ADR-087 names, on the payment side this time
-- rather than the membership side: a multi-row statement (482), `MERGE` (485),
-- a data-modifying CTE (487), `INSERT … ON CONFLICT DO UPDATE` (489), and a
-- plain `created → paid` UPDATE (491). 493 then asserts all five of those
-- payments are `paid` and receipted — so a rule that answers the shapes by
-- refusing them is red here rather than green everywhere.
--
-- NO SQLSTATE IS PINNED. This requirement names none, and the only refusals in
-- this section belong to rules that already exist (attribution, the refund
-- ceiling), whose codes the spec does not restate here.
--
-- Every date is the gym's own `today_t20`, never `current_date` (ADR-039).
-- Two check-in fixtures get their own QR sessions so a gate assertion cannot
-- pass or fail for another section's reason.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Repair', '+912200200053'),
  ('22000000-0000-4000-8000-000000200054'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Expired', '+912200200054'),
  ('22000000-0000-4000-8000-000000200055'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Frozen', '+912200200055'),
  ('22000000-0000-4000-8000-000000200056'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Pending', '+912200200056'),
  ('22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Shapes', '+912200200057'),
  ('22000000-0000-4000-8000-000000200058'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 Sibling', '+912200200058'),
  ('22000000-0000-4000-8000-000000200059'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 AfterMoney', '+912200200059'),
  ('22000000-0000-4000-8000-00000020005a'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'M23 GateOnly', '+912200200060');

-- The retired and live memberships this section scores against. 2000a0 and
-- 2000a1 are NOT staged here — the repair sequence below creates them itself,
-- from the desk, because the point of 23a is that this state is reached through
-- ordinary work and not only through a fixture.
--
-- Member 200057 holds FOUR cancelled memberships at once, which the live
-- partial unique index (active/frozen only) permits — one per write shape, so
-- each shape's "did not move" is its own row and no shape can pass on another
-- shape's arithmetic.
--
-- 2000a2 is `expired` and dated in the PAST (today-60 .. today-30): a granted
-- period would move it to `greatest(ends_on, today) + 30 = today + 30`, so the
-- defect and the correct answer are thirty days apart and cannot be confused.
-- 2000ac is `cancelled` and dated into the FUTURE (today+300), so the gate
-- assertion at 475 cannot pass by the dates being stale.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency, cancelled_at, cancel_reason) values
  ('22000000-0000-4000-8000-0000002000a2'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200054'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'expired', (select d from today_t20) - 60, (select d from today_t20) - 30, 150000, 'INR', null, null),
  ('22000000-0000-4000-8000-0000002000a3'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200055'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'frozen', (select d from today_t20), (select d from today_t20), 150000, 'INR', null, null),
  ('22000000-0000-4000-8000-0000002000a4'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200056'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'pending', (select d from today_t20), (select d from today_t20), 150000, 'INR', null, null),
  ('22000000-0000-4000-8000-0000002000a5'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20), (select d from today_t20), 150000, 'INR', now(), 'retired before this section began'),
  ('22000000-0000-4000-8000-0000002000a6'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200058'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000, 'INR', null, null),
  ('22000000-0000-4000-8000-0000002000a7'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20), (select d from today_t20), 150000, 'INR', now(), 'retired before this section began'),
  ('22000000-0000-4000-8000-0000002000a8'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20), (select d from today_t20), 150000, 'INR', now(), 'retired before this section began'),
  ('22000000-0000-4000-8000-0000002000a9'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20), (select d from today_t20), 150000, 'INR', now(), 'retired before this section began'),
  ('22000000-0000-4000-8000-0000002000aa'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20), (select d from today_t20), 150000, 'INR', now(), 'retired before this section began'),
  ('22000000-0000-4000-8000-0000002000ab'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200059'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'active', (select d from today_t20), (select d from today_t20), 150000, 'INR', null, null),
  ('22000000-0000-4000-8000-0000002000ac'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-00000020005a'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
   'cancelled', (select d from today_t20) - 1, (select d from today_t20) + 300, 150000, 'INR', now(), 'cancelled with time left on the clock');

-- Two `created` payments staged as postgres, each already carrying its own
-- receipt_number so the later flip to `paid` needs no allocation to satisfy
-- payments_paid_has_reference_chk — the same isolation Section 11's own
-- UPDATE fixture uses, so 489/491 measure the extension rule and nothing else.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, receipt_number) values
  ('22000000-0000-4000-8000-00000020101a'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000a9'::uuid,
   150000, 'INR', 'created', 'cash', '22000000-0000-4000-8000-000000200021'::uuid, 'T23-RCT-UPSERT'),
  ('22000000-0000-4000-8000-00000020101b'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000aa'::uuid,
   150000, 'INR', 'created', 'cash', '22000000-0000-4000-8000-000000200021'::uuid, 'T23-RCT-CREATED');

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at) values
  ('22000000-0000-4000-8000-000000200096'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'pay22-t23-repair-gate',
   now() - interval '1 minute', now() + interval '1 hour', null),
  ('22000000-0000-4000-8000-000000200097'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
   '22000000-0000-4000-8000-000000200011'::uuid, 'pay22-t23-retired-gate',
   now() - interval '1 minute', now() + interval '1 hour', null);


-- ---------------------------------------------------------------------------
-- 23a — THE REPAIR SEQUENCE, WALKED ONE STEP TOO FAR (446-461)
--
-- Sell wrong, pay, refund, cancel, re-sell — then pay against the retired one,
-- and against the live one, and assert which of them moves.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 446
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
  values ('22000000-0000-4000-8000-0000002000a0'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'active', (select d from today_t20), (select d from today_t20), 150000, 'INR')
$$, 'retired/repair: the desk sells the member a membership — the sale that will turn out to be wrong');

-- 447
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201010'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-0000002000a0'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/repair: and the member pays for it');

set local role postgres;

-- 448
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a0'::uuid $$,
  $$ select 'active'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/repair: one period, thirty days — an ordinary sale, so that every difference measured after the cancel below is caused by the cancel and by nothing else'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);
set local role authenticated;

-- 449
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000203002'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000201010'::uuid, 'refund', 150000, 'INR',
          'mis-sold; refunding and re-selling',
          '22000000-0000-4000-8000-000000200022'::uuid)
$$, 'retired/repair: step one — the manager gives the money back');

-- 450
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-000000201010'::uuid
$$, 'retired/repair: and the payment moves paid → refunded');

-- 451
select lives_ok($$
  update public.memberships
     set status = 'cancelled', cancelled_at = now(), cancel_reason = 'mis-sold; refunded and re-sold'
   where id = '22000000-0000-4000-8000-0000002000a0'::uuid
$$, 'retired/repair: step two — the membership is retired');

set local role postgres;

-- 452
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a0'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/repair: cancelled, and still carrying the period the money bought — the refund reversed the money and not what the money bought (Section 22''s 439, restated here because everything below is measured against these two numbers)'
);

-- The gym's receipt counter, captured immediately before the payment at 454 so
-- that 456 can assert that payment took EXACTLY one number. Summed across the
-- tenant's receipt counters rather than read from one financial-year row, so
-- that a run straddling 1 April cannot make the arithmetic wrong.
create temp table dc23_before as
  select coalesce(sum(next_number), 0)::int as n
    from public.document_counters
   where tenant_id = '22000000-0000-4000-8000-000000200001'::uuid and kind = 'receipt';

grant select on dc23_before to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 453
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
  values ('22000000-0000-4000-8000-0000002000a1'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-000000200060'::uuid,
          'active', (select d from today_t20), (select d from today_t20), 150000, 'INR')
$$, 'retired/repair: step three — the desk sells the replacement. THE MEMBER NOW HOLDS TWO MEMBERSHIPS, ONE OF THEM RETIRED, which is the state this whole requirement is about and the state the prescribed repair always produces');

-- 454 — the step the console cannot take and POST /api/payments can: the
-- payment names the RETIRED membership. GL042 checks only that the member
-- matches, and on this path the member matches both.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201011'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-0000002000a0'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'scenario "Paying against a cancelled membership" — the payment is RECORDED, not refused. The money changed hands; refusing after the fact would leave cash in a drawer with nothing to show for it');

set local role postgres;

-- 455
select results_eq(
  $$ select status, receipt_number is not null, paid_at is not null, recorded_by_staff_id
       from public.payments where id = '22000000-0000-4000-8000-000000201011'::uuid $$,
  $$ select 'paid'::public.payment_status, true, true, '22000000-0000-4000-8000-000000200021'::uuid $$,
  'scenario "Paying against a cancelled membership" — and it is a FULL payment: paid, receipted, stamped, attributed. A rule that answers this requirement by quietly refusing the payment is a different rule and a worse one, and this is where that shows'
);

-- 456
select is(
  (select coalesce(sum(next_number), 0)::int from public.document_counters
    where tenant_id = '22000000-0000-4000-8000-000000200001'::uuid and kind = 'receipt'),
  (select n from dc23_before) + 1,
  'scenario "Paying against a cancelled membership" — the receipt came off the gym''s own counter and moved it by exactly one. A payment against a retired membership is counted in the receipt book like any other, because it is money the gym actually took'
);

-- 457 — THE ASSERTION THIS ROUND EXISTS FOR.
select results_eq(
  $$ select status, periods_granted, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a0'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 1, (select d from today_t20), (select d from today_t20) + 30 $$,
  'scenario "Paying against a cancelled membership" — the retired membership''s dates and count DID NOT MOVE. Measured today: they move, to periods 2 and today+60, on the row the gate already refuses'
);

-- 458 — the other direction of the same worry. Nothing said "put the money on
-- the live one instead"; a fix that helpfully redirects it has invented a rule
-- nobody wrote and would be indistinguishable from the correct one without
-- this assertion.
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a1'::uuid $$,
  $$ select 'active'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/repair: and the LIVE membership did not move either — the money named the retired row, so the answer is "do not extend", not "extend something else"'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 459
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201012'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-0000002000a1'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'scenario "Paying against the live one instead" — the same member, the same desk, the same amount, the live membership named');

set local role postgres;

-- 460
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a1'::uuid $$,
  $$ select 'active'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'scenario "Paying against the live one instead" — it extends NORMALLY. This is the assertion a rule that simply stopped extending everything would fail, and stopping everything passes every refusal in this section'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 461
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200011'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, 'qr',
          '22000000-0000-4000-8000-000000200096'::uuid)
$$, 'retired/repair: and the member walks in — the repair still produces a membership that WORKS, with a stray payment against the retired row sitting in the books beside it');


-- ---------------------------------------------------------------------------
-- 23b — THE PAYMENT IS A FIRST-CLASS PAYMENT IN EVERY OTHER RESPECT (462-465)
--
-- 455 and 456 already have the receipt, the stamp and the counter. What is
-- left is the two rules that make a payment answerable afterwards: it names
-- the human who took the money, and it can be given back, bounded by the same
-- ceiling as any other. If a rule "handles" a retired membership by putting
-- the payment in some lesser state, one of these breaks.
-- ---------------------------------------------------------------------------

-- 462
select throws_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000020101f'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200053'::uuid, '22000000-0000-4000-8000-0000002000a0'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200022'::uuid)
$$, null::char(5), null,
  'retired/first-class: a desk payment against the RETIRED membership naming a colleague as the recorder is still refused — recording the payment does not mean recording it unattributed');

set local role postgres;

-- 463
select results_eq(
  $$ select count(*)::int from public.payments
      where id = '22000000-0000-4000-8000-00000020101f'::uuid $$,
  $$ values (0) $$,
  'retired/first-class: refused AND no row landed'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);
set local role authenticated;

-- 464
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000203003'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000201011'::uuid, 'refund', 150000, 'INR',
          'paid against the retired membership by mistake',
          '22000000-0000-4000-8000-000000200022'::uuid)
$$, 'retired/first-class: the payment against the retired membership is REFUNDABLE in full — which is the only honest remedy for money that bought nothing, and it exists only because the payment was recorded in the first place');

-- 465
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000203004'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000201011'::uuid, 'refund', 1, 'INR',
          'one paisa past the ceiling',
          '22000000-0000-4000-8000-000000200022'::uuid)
$$, null::char(5), null,
  'retired/first-class: and one paisa more is refused by the ceiling — so the payment counts toward its own refund ceiling exactly like any other, rather than being some lesser record the ceiling does not see');


-- ---------------------------------------------------------------------------
-- 23c — BOTH RETIRED STATUSES, AND EVERY LIVE ONE (466-471)
--
-- `expired` is named by the requirement beside `cancelled` and is the harder
-- of the two to reach in production (ADR-064: nothing in this product ever
-- writes it), which is exactly why nobody would notice it being left out.
-- `frozen` and `pending` are the two live statuses the console's own renewal
-- path does not exercise and are therefore the two most likely to be swept up
-- by a fix aimed at `active` alone.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 466
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201013'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200054'::uuid, '22000000-0000-4000-8000-0000002000a2'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/expired: a payment naming an EXPIRED membership is recorded, exactly as the cancelled one was');

set local role postgres;

-- 467
select results_eq(
  $$ select status, periods_granted, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a2'::uuid $$,
  $$ select 'expired'::public.membership_status, 0, (select d from today_t20) - 60, (select d from today_t20) - 30 $$,
  'scenario "Paying against a cancelled membership", the requirement''s other half — `expired` is retired too, and the dates stay thirty days in the PAST rather than jumping to today+30'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 468
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201014'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200055'::uuid, '22000000-0000-4000-8000-0000002000a3'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/frozen: a payment naming a FROZEN membership is recorded');

set local role postgres;

-- 469
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a3'::uuid $$,
  $$ select 'frozen'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/frozen: and it EXTENDS. `frozen` is live — it is half of the gym''s own definition of live at the gate (memberships_tenant_id_member_id_live_key) — so a rule that reads "not active" instead of "retired" fails here'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 470
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201015'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200056'::uuid, '22000000-0000-4000-8000-0000002000a4'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/pending: a payment naming a PENDING membership is recorded');

set local role postgres;

-- 471 — status is deliberately NOT asserted here. Whether paying for a DATED
-- pending membership also activates it is a question the requirement above
-- ("A payment against a membership with no dates…") answers only for the
-- UNDATED case, and guessing at it would be scoring a rule nobody wrote.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a4'::uuid $$,
  $$ select 1, (select d from today_t20) + 30 $$,
  'retired/pending: and it EXTENDS. `pending` is "sold but not started", not "retired" — the requirement names cancelled and expired and nothing else, and a fix that reads "only active and frozen may be extended" strands every membership sold before it was paid for'
);


-- ---------------------------------------------------------------------------
-- 23d — DOES THE GATE AGREE? (472-475)
--
-- The requirement's own account of the harm ends "…and the member stays
-- refused at the gate because the gate reads status." 2000ac is the shape that
-- makes that a real question rather than a rhetorical one: cancelled, but with
-- three hundred days still on its dates, so a gate that had drifted to reading
-- dates alone would admit its member. Money then lands on it, which under the
-- measured defect is precisely the thing that puts long dates on a retired row.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 472
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000020101e'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-00000020005a'::uuid, '22000000-0000-4000-8000-0000002000ac'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/gate: money arrives against a cancelled membership that still has three hundred days on its dates');

set local role postgres;

-- 473
select results_eq(
  $$ select status, receipt_number is not null, paid_at is not null
       from public.payments where id = '22000000-0000-4000-8000-00000020101e'::uuid $$,
  $$ select 'paid'::public.payment_status, true, true $$,
  'retired/gate: recorded and receipted here too'
);

-- 474
select results_eq(
  $$ select status, periods_granted, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000ac'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) - 1, (select d from today_t20) + 300 $$,
  'retired/gate: and the retired row did not grow — a membership with time left on the clock that somebody cancelled anyway is still retired, and the leftover dates are not an invitation'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 475
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200011'::uuid,
          '22000000-0000-4000-8000-00000020005a'::uuid, 'qr',
          '22000000-0000-4000-8000-000000200097'::uuid)
$$, null::char(5), null,
  'retired/gate: the gate REFUSES him, dates and money notwithstanding — which is the sentence the requirement''s own harm statement rests on. If this ever goes green, "cancelled" has stopped meaning anything and the money rule above is the smaller half of the problem');


-- ---------------------------------------------------------------------------
-- 23e — MONEY ALREADY GRANTED STAYS GRANTED, AND STATUS CHANGES BETWEEN TWO
-- PAYMENTS (476-481)
--
-- Nothing here reverses history. A membership cancelled AFTER money arrived
-- keeps the period that money bought — the same fact Section 22's 439 records
-- for refunds, asserted here for cancellation because a fix aimed at "retired
-- memberships must not carry granted periods" would be a different and much
-- larger rule, and this is where it would show.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 476
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000020101c'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200059'::uuid, '22000000-0000-4000-8000-0000002000ab'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/history: the first payment arrives while the membership is live');

set local role postgres;

-- 477
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000ab'::uuid $$,
  $$ select 'active'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/history: and buys a period, as it should'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000200022')::text,
  true);
set local role authenticated;

-- 478
select lives_ok($$
  update public.memberships
     set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member moved cities'
   where id = '22000000-0000-4000-8000-0000002000ab'::uuid
$$, 'retired/history: then the membership is cancelled');

set local role postgres;

-- 479
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000ab'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/history: the period the money already bought STAYS BOUGHT. Nothing in this requirement reverses history — it stops a retired membership growing, it does not unwind what it grew before it was retired'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 480
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000020101d'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200059'::uuid, '22000000-0000-4000-8000-0000002000ab'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/history: and a second payment arrives on the same membership, now retired — recorded');

set local role postgres;

-- 481
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000ab'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/history: STILL one period and still thirty days — the status between the two payments is what decides, so the same membership, the same member and the same amount buy a month the first time and nothing the second'
);


-- ---------------------------------------------------------------------------
-- 23f — THE WRITE SHAPES (482-493)
--
-- ADR-087's costumes, on the payment side. A guard written into the ordinary
-- single-row INSERT path and nowhere else is the failure mode this project has
-- shipped repeatedly; every shape below reaches the same trigger by a different
-- statement, and 482 puts a cancelled and a live membership in ONE statement so
-- that a rule enforced per statement rather than per row cannot pass.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 482
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000201016'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000a5'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid),
         ('22000000-0000-4000-8000-000000201017'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200058'::uuid, '22000000-0000-4000-8000-0000002000a6'::uuid,
          150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/shapes: two payments in ONE statement — one naming a cancelled membership, one naming a live one');

set local role postgres;

-- 483
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a5'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/shapes: the cancelled row in that statement did not move'
);

-- 484
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a6'::uuid $$,
  $$ select 'active'::public.membership_status, 1, (select d from today_t20) + 30 $$,
  'retired/shapes: and the LIVE row in the SAME statement did — 483 and 484 together are the pair a rule enforced per statement rather than per row cannot pass, and either one alone would let it through'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 485
select lives_ok($$
  merge into public.payments p
  using (select '22000000-0000-4000-8000-000000201018'::uuid as id) s
     on p.id = s.id
   when not matched then
     insert (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
     values (s.id, '22000000-0000-4000-8000-000000200001'::uuid,
             '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000a7'::uuid,
             150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
$$, 'retired/shapes: the payment written as MERGE — ADR-087 records MERGE walking round a rule on this file''s own tables once already');

set local role postgres;

-- 486
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a7'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/shapes: MERGE does not move the retired membership either'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 487
select lives_ok($$
  with recorded as (
    insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
    values ('22000000-0000-4000-8000-000000201019'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
            '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000a8'::uuid,
            150000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000200021'::uuid)
    returning id
  )
  select count(*) from recorded
$$, 'retired/shapes: the payment written as a data-modifying CTE');

set local role postgres;

-- 488
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a8'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/shapes: the CTE does not move it'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 489 — the upsert reaches `paid` through the DO UPDATE arm, which is the arm
-- a rule written only into the INSERT path never sees.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-00000020101a'::uuid, '22000000-0000-4000-8000-000000200001'::uuid,
          '22000000-0000-4000-8000-000000200057'::uuid, '22000000-0000-4000-8000-0000002000a9'::uuid,
          150000, 'INR', 'created', 'cash', '22000000-0000-4000-8000-000000200021'::uuid, 'T23-RCT-UPSERT')
  on conflict (id) do update set status = 'paid'
$$, 'retired/shapes: the payment written as INSERT … ON CONFLICT DO UPDATE, reaching `paid` through the update arm');

set local role postgres;

-- 490
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000a9'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/shapes: the upsert does not move it'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000200001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000200021')::text,
  true);
set local role authenticated;

-- 491 — the ordinary online shape: an order is created, the money confirms
-- later, and the row is walked created → paid by an UPDATE. `payments` carries
-- a separate extend trigger for UPDATE, so this is a second code path and not
-- a rewording of 482.
select lives_ok($$
  update public.payments set status = 'paid'
   where id = '22000000-0000-4000-8000-00000020101b'::uuid
$$, 'retired/shapes: a created → paid UPDATE on a payment naming a retired membership');

set local role postgres;

-- 492
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-0000002000aa'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t20) $$,
  'retired/shapes: and the created → paid UPDATE does not move it either'
);

-- 493 — the guard on the whole subsection. Every one of the five shape
-- payments must have arrived as a real payment: a fix that answers MERGE, the
-- CTE, the upsert and the UPDATE by refusing them would turn 483-492 green
-- while quietly making four ordinary write shapes unusable and losing the
-- money they carried.
select results_eq(
  $$ select count(*)::int,
            count(*) filter (where status = 'paid')::int,
            count(*) filter (where receipt_number is not null)::int,
            count(*) filter (where paid_at is not null)::int
       from public.payments
      where id in ('22000000-0000-4000-8000-000000201016'::uuid,
                   '22000000-0000-4000-8000-000000201018'::uuid,
                   '22000000-0000-4000-8000-000000201019'::uuid,
                   '22000000-0000-4000-8000-00000020101a'::uuid,
                   '22000000-0000-4000-8000-00000020101b'::uuid) $$,
  $$ select 5, 5, 5, 5 $$,
  'retired/shapes: all five shape payments are on the books, paid, receipted and stamped. The requirement records the money in every shape and extends nothing in any of them'
);



-- ===========================================================================
-- SECTION 24 (ROUND SIXTEEN, GL037) — "The receipt counter only ever counts
-- up": THE EQUAL WRITE. Tenant 4, reusing Section 4's fixtures.
-- Assertions 494-508.
--
-- WHY THIS SECTION EXISTS. Section 4 above tests a decrease, +5, +1 and a
-- delete. The holdout tests a decrease, +1, +25 and a delete. NEITHER SUITE
-- EVER WROTE `next_number` TO THE VALUE IT ALREADY HELD. The requirement is
-- "SHALL refuse any change to document_counters.next_number that does not
-- increase it", and "does not increase" includes leaving it exactly where it
-- was — so the equal write is a refusal, and both suites had a hole where the
-- assertion for it should be.
--
-- The hole was found the expensive way. A seed block written as
-- `greatest(current, new)` produced an exactly-equal UPDATE the second time it
-- ran, once the counter had caught up; GL037 refused it and the seed died. An
-- assertion for the equal case would have caught that before it shipped, and
-- closing it is the whole of this round.
--
-- A DELIBERATE, RECORDED DEVIATION FROM THE TWO-AUTHOR ARRANGEMENT (hard rule
-- 10 / ADR-059), and the SECOND time this phase — sections 21 and 22 of this
-- file were the first. This section and its holdout counterpart (h22 section
-- 23) were written by the SAME author. The independence was traded knowingly,
-- not forgotten: there is no design here to converge on. The rule already
-- exists and is already implemented, the gap is one assertion SHAPE on a rule
-- both suites already carry full batteries for, and a second author reading
-- the same one-sentence requirement would write the same four statements.
-- Stated here so the next reader sees the trade rather than assuming the
-- arrangement held.
--
-- THE DISTINCTION THIS SECTION EXISTS TO DRAW. Two upsert shapes differ by one
-- clause and by everything else:
--
--   on conflict … do update
--     set next_number = greatest(document_counters.next_number, excluded.next_number)
--       -- ALWAYS fires the UPDATE. Once the row has caught up, greatest()
--       -- writes the value back unchanged, and GL037 REFUSES it.
--
--   on conflict … do update
--     set next_number = excluded.next_number
--     where excluded.next_number > document_counters.next_number
--       -- when the guard is false, does not fire the UPDATE AT ALL: no row
--       -- touched, no trigger, no exception, counter unmoved.
--
-- "Refused" and "did not fire" are the two outcomes, and the seed's defect was
-- reaching for the first shape while meaning the second. Both are asserted.
--
-- THE BOUNDARY IS NOT RE-ASSERTED HERE IN FULL, deliberately. One-less (a
-- decrease) is assertions 32/33 above and one-more is 34-37, on this same rule
-- and this same tenant; duplicating them buys nothing. This section adds the
-- missing middle — equal — in every shape it actually arrives in, and asserts
-- that the guarded form DOES fire when it should (505/506), so the "no update"
-- assertions are honest in both directions rather than being satisfied by a
-- statement that never does anything (ADR-078).
-- ===========================================================================

grant select on fy_t4 to public;

-- A counter of its own at a known value, rather than section 4's receipt row
-- at wherever the hand-edits left it: this section needs a SECOND row on the
-- same tenant and financial year for the multi-row statement at 507, and the
-- 'invoice' kind is used by neither suite anywhere else.
insert into public.document_counters (tenant_id, kind, financial_year, next_number)
values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 7);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 494 — the equal write in its plainest form. Neither an increase nor a
-- decrease: the value the row already holds, written back over itself.
select throws_ok($$
  update public.document_counters set next_number = next_number
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice'
$$, 'GL037'::char(5), null,
  'the equal write — next_number set to the value it already holds — is refused with GL037. "Only ever counts up" excludes standing still, and the rule''s own predicate is <=, not <');

set local role postgres;

-- 495
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (7) $$,
  'next_number is still 7 after the refused equal write — refusing and then moving it anyway would be worse than not refusing'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 496 — the shape it actually arrives in. `greatest(current, new)` reads as
-- "never go backwards" and is exactly the seed block that died: the moment the
-- row has caught up to the value being offered, greatest() returns the value
-- already there and the DO UPDATE arm fires an equal write.
select throws_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 7)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = greatest(document_counters.next_number, excluded.next_number)
$$, 'GL037'::char(5), null,
  'insert … on conflict … do update set next_number = greatest(current, excluded), with the row already AT the excluded value, is refused with GL037. This is the seed''s own statement, and the second run is where it dies');

set local role postgres;

-- 497
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (7) $$,
  'next_number is still 7 after the refused greatest() upsert'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 498 — the same shape with the row already BEYOND the offered value, which is
-- the ordinary steady state of a re-run seed. greatest() collapses to the
-- current value again, so this too is an equal write and not a decrease: the
-- refusal must be GL037, not a decrease being caught by accident.
select throws_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 3)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = greatest(document_counters.next_number, excluded.next_number)
$$, 'GL037'::char(5), null,
  'the same greatest() upsert with the row already PAST the excluded value is also refused with GL037 — greatest() collapses to the current value, so the statement that was meant to be a no-op is an equal write');

set local role postgres;

-- 499
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (7) $$,
  'next_number is still 7 after that refusal too'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 500 — THE PERMITTED NEIGHBOUR, and the point of the whole section. One
-- clause different: the DO UPDATE carries a WHERE, so when the offered value
-- is not greater the update never fires and there is nothing for GL037 to
-- refuse. This is the shape the seed now uses.
select lives_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 7)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = excluded.next_number
    where excluded.next_number > document_counters.next_number
$$, 'the GUARDED upsert, offered the value the row already holds, is NOT refused — the guard is false, so no UPDATE is attempted and the trigger never runs');

-- 501 — and it is not merely "no exception": no row was touched. A data-
-- modifying CTE returns a row per row ACTUALLY written, so zero here is the
-- difference between "did not fire" and "fired and was somehow forgiven". The
-- statement is the same one 500 just ran; it is a no-op, so running it twice
-- is the same as running it once, which is itself the property the seed needed.
with u as (
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 7)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = excluded.next_number
    where excluded.next_number > document_counters.next_number
  returning 1
)
select is(
  (select count(*)::int from u), 0,
  'and it updated NO ROW AT ALL — zero rows returned. "Did not fire" and "was refused" are the two outcomes of an equal write, and the seed''s defect was writing the one while meaning the other');

set local role postgres;

-- 502
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (7) $$,
  'next_number is still 7 after both no-op upserts — unmoved, exactly as it is after a refusal, which is why the counter alone cannot tell the two apart and 501 exists'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 503 — one below: the guarded form offered a LOWER value is also a no-op
-- rather than a refusal, so a re-run seed that has fallen behind the live
-- counter is silent rather than fatal.
select lives_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 3)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = excluded.next_number
    where excluded.next_number > document_counters.next_number
$$, 'the guarded upsert offered a value BELOW the row''s is likewise not refused — the guard is false, and a decrease that never fires is not a decrease');

set local role postgres;

-- 504
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (7) $$,
  'and the counter did not move backwards either — the guard protects the value as well as the statement'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 505 — the other direction (ADR-078). Everything above would also be green if
-- the guarded upsert simply never did anything under any circumstances, which
-- would be a broken seed that reports success. One above: the guard is true,
-- the update fires, and GL037 permits it because it is a real increase.
select lives_ok($$
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('22000000-0000-4000-8000-000000000004'::uuid, 'invoice', (select fy from fy_t4), 9)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = excluded.next_number
    where excluded.next_number > document_counters.next_number
$$, 'the same guarded upsert offered a HIGHER value fires and is permitted — the guard is not a way of never writing');

set local role postgres;

-- 506
select results_eq(
  $$ select next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid and kind = 'invoice' $$,
  $$ values (9) $$,
  'next_number moved to exactly 9 — the guarded upsert really does advance the counter when the value is greater, so 500-504 are assertions about a statement that works, not about one that is inert'
);

-- The two counter rows this tenant owns, captured immediately before the
-- multi-row statement so 508 asserts "unchanged" against what was actually
-- there rather than against a value carried down from section 4.
create temp table dc_r16_before as
  select kind, next_number from public.document_counters
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid
     and financial_year = (select fy from fy_t4);
grant select on dc_r16_before to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000000004',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 507 — one statement, two rows: the receipt row genuinely increases and the
-- invoice row is written its own value back. The trigger is FOR EACH ROW, so a
-- rule that only looked at the statement's net effect, or that let a row pass
-- because a sibling row moved forward, would let this through.
select throws_ok($$
  update public.document_counters
     set next_number = case when kind = 'receipt' then next_number + 1 else next_number end
   where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid
     and financial_year = (select fy from fy_t4)
$$, 'GL037'::char(5), null,
  'a multi-row UPDATE in which one row increases and another is written its own value is refused with GL037 — the equal row is judged on its own, not excused by the sibling that moved forward');

set local role postgres;

-- 508
select results_eq(
  $$ select kind, next_number from public.document_counters
      where tenant_id = '22000000-0000-4000-8000-000000000004'::uuid
        and financial_year = (select fy from fy_t4)
      order by kind $$,
  $$ select kind, next_number from dc_r16_before order by kind $$,
  'and BOTH rows are exactly where they were — the increase that would have been legal on its own went back with the refusal, because a refused row aborts the statement rather than being skipped'
);




-- ===========================================================================
-- SECTION 25 (ROUND SEVENTEEN) — "A refund that completed did not fail".
-- Tenant 21. Assertions 509-540.
--
-- THE MEASURED DEFECT. `GL036` bounds the refunds against a payment by summing
-- the ones that are not `failed`, and nothing freezes a refund's status. Full
-- refund accepted, second full refund refused by `GL036`, first refund demoted
-- to `failed`, second full refund then accepted. Money that left the gym became
-- an attempt that never happened. Reproduced from this session against Cloud,
-- in a rolled-back transaction, before a line of this section was written.
--
-- THE ENUM, READ FROM THE CATALOGUE AND NOT GUESSED. `refund_status` is
-- (`requested`, `processing`, `completed`, `failed`) — four labels, and there
-- is no `pending` among them. The brief for this round named `pending` as a
-- shape to attack; it does not exist, so the shapes below are the four that do.
--
-- WHAT IS ASSERTED BEYOND THE REFUSAL. The requirement's harm is not the write,
-- it is the CEILING moving afterwards, so every refusal here is followed by
-- both the unchanged value AND the ceiling consequence: after a refused
-- demotion, the second full refund must still be refused (514). A suite that
-- only asserted 512 would pass against an implementation that refused the
-- UPDATE and then let the sum drift some other way.
--
-- AND THE PERMITTED SIDE IS ASSERTED AS HARD AS THE REFUSED SIDE, because a
-- fix that is too broad passes every refusal test and this project has shipped
-- that three times. Three shapes are permitted and must stay permitted:
--   * a `completed` refund written its own status back (520) — "refuse any
--     change OUT OF completed" is `is distinct from`, the idiom this codebase
--     settled for `periods_granted` and for the membership dates in their own
--     requirements ("a rule that refuses a write that cannot do harm buys
--     nothing and breaks ordinary column-listing updates");
--   * a `completed` refund's OTHER columns (522) — the requirement freezes the
--     status, not the row; `payment_id` and `amount_paise` are already frozen
--     by `GL041` and nothing else on a refund is;
--   * the four moves among the non-completed statuses, and the ordinary
--     forward path INTO `completed` (524-528), which is how a refund is
--     supposed to reach the state this requirement then freezes.
--
-- NO SQLSTATE IS PINNED ON THE NEW RULE. The spec's three round-seventeen
-- requirements name no code; the codes it does name (`GL036` … `GL046`) all
-- belong to rules that already exist. Where this section refuses by the
-- EXISTING ceiling it asserts `GL036`, because the requirement names that rule
-- by name; where it refuses by the new rule it asserts `null::char(5)`, the
-- convention this file has used since assertion 1. Asserting a code nobody has
-- chosen would be this file guessing at an implementation it is not allowed to
-- read.
--
-- WHERE THE LINE ACTUALLY FALLS, and it is not "the ceiling is never
-- released". The freeze is keyed on `completed`; the `GL036` sum is keyed on
-- "not `failed`". Those are different sets, so an in-flight refund moved to
-- `failed` un-counts itself and releases the ceiling, exactly as the measured
-- defect did — and the requirement's second scenario permits it. Both suites'
-- authors reached that independently (one on `requested`, one on `processing`)
-- and the coordinator decided it mid-round: **it stays permitted, and the
-- requirement will say why.**
--
--   money that LEFT does not become an attempt. Money in flight may.
--
-- A refund at `requested` or `processing` is money handed to the provider and
-- not yet moved by it. It can genuinely fail; that is what the status is for,
-- and refusing the transition would strand the refund unresolvable while the
-- ceiling permanently consumed money that never left. `completed` is different
-- in kind — the money is gone, and calling it an attempt is falsifying the
-- ledger.
--
-- So this section asserts the CEILING CONSEQUENCE on both sides of that line,
-- not the transitions alone: refused at `completed` and the ceiling holds
-- (512/514); permitted at `requested` and the ceiling releases (532-537);
-- permitted at `processing` and the ceiling releases (596-599, on this same
-- tenant, added after the numbering above was fixed). 535 and 537 pin what
-- still bounds the money: `GL036` on UPDATE means only one of the two refunds
-- can ever reach `completed`, so only one payment's worth can go out however
-- the in-flight statuses are walked.
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000210001'::uuid, 'PayRec Gym 21', 'PYR22N');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000210011'::uuid, '22000000-0000-4000-8000-000000210001'::uuid, 'G21 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000210021'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210011'::uuid, 'gym_owner', 'T21 Owner'),
  ('22000000-0000-4000-8000-000000210022'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210011'::uuid, 'gym_manager', 'T21 Manager');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000210041'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210011'::uuid, 'M21', '+912221000041');

-- Seven paid payments, one concern each, so no assertion's ceiling arithmetic
-- depends on another's (ADR-050 applied inside a section). None names a
-- membership, so nothing here is entangled with the granting rule.
insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000210101'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 500000, 'paid', 'cash', 'T21-RCT-01', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210102'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 500000, 'paid', 'cash', 'T21-RCT-02', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210103'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 500000, 'paid', 'cash', 'T21-RCT-03', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210104'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 500000, 'paid', 'cash', 'T21-RCT-04', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210105'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 300000, 'paid', 'cash', 'T21-RCT-05', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210106'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 200000, 'paid', 'cash', 'T21-RCT-06', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210107'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 500000, 'paid', 'cash', 'T21-RCT-07', '22000000-0000-4000-8000-000000210021'::uuid);

-- Postgres fixtures: the refunds this section STARTS from. 210201 is not among
-- them — it is written by assertion 509 as the gym owner, because "a full
-- refund is accepted" is the first step of the measured sequence and asserting
-- it is cheaper than assuming it.
insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('22000000-0000-4000-8000-000000210202'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210102'::uuid, 'refund', 500000, 'completed', 'full refund, completed', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210203'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210103'::uuid, 'refund', 500000, 'completed', 'full refund, completed', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210204'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210104'::uuid, 'refund', 500000, 'completed', 'full refund, completed', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210205'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210105'::uuid, 'refund', 100000, 'requested', 'part refund, requested', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210206'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210105'::uuid, 'refund', 100000, 'processing', 'part refund, processing', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210207'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210105'::uuid, 'refund', 100000, 'failed', 'part refund, failed', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210208'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210106'::uuid, 'refund', 200000, 'requested', 'full refund, requested', '22000000-0000-4000-8000-000000210021'::uuid),
  ('22000000-0000-4000-8000-000000210209'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210107'::uuid, 'refund', 500000, 'completed', 'full refund, completed', '22000000-0000-4000-8000-000000210022'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 509 — step one of the measured sequence, and the permitted side of the whole
-- section: a full refund against a fully paid payment, landing exactly ON the
-- ceiling rather than under it.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210201'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210101'::uuid, 'refund', 500000, 'completed',
          'full refund of payment 01', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'a completed refund for the whole of a paid payment is accepted — exactly at the ceiling, not under it');

-- 510 — step two: the second full refund is refused by GL036, which the
-- requirement names. This is the ceiling working before anything is tampered
-- with, and it is what step four has to still be true of.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210210'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210101'::uuid, 'refund', 500000, 'completed',
          'second full refund of payment 01', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'GL036'::char(5), null,
  'a second full refund against the same payment is refused by GL036 — the ceiling is reached');

set local role postgres;

-- 511
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000210101'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210101'::uuid and status <> 'failed')
  $$,
  $$ values (1, 500000::bigint) $$,
  'one refund on the books against payment 01, and the non-failed total is its whole amount'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 512 — step three, and the requirement's own scenario "Demoting a completed
-- refund": the money that left the gym is told it never left.
select throws_ok($$
  update public.refunds set status = 'failed'
   where id = '22000000-0000-4000-8000-000000210201'::uuid
$$, null::char(5), null,
  'scenario "Demoting a completed refund" — a completed refund moved to failed is refused. Money that left the gym does not become an attempt that never happened');

set local role postgres;

-- 513
select results_eq(
  $$
    select
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210201'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210101'::uuid and status <> 'failed')
  $$,
  $$ values ('completed'::text, 500000::bigint) $$,
  'the refund is still completed AND the ceiling still sees its money — the value and the sum it feeds, because refusing the write while the sum moved anyway would be the same defect'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 514 — THE CEILING CONSEQUENCE, and the assertion this whole section exists
-- for. Step four of the measured sequence: with the demotion refused, the
-- second full refund must be refused for the same reason it was at 510. The
-- requirement's harm is not the UPDATE, it is this INSERT succeeding.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210210'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210101'::uuid, 'refund', 500000, 'completed',
          'second full refund, after the refused demotion', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'GL036'::char(5), null,
  'and the second full refund is STILL refused with GL036 after the refused demotion — the measured exploit end to end, closed at the step that matters');

set local role postgres;

-- 515
select results_eq(
  $$ select count(*)::int, coalesce(sum(amount_paise), 0)::bigint, min(status::text)
       from public.refunds where payment_id = '22000000-0000-4000-8000-000000210101'::uuid $$,
  $$ values (1, 500000::bigint, 'completed'::text) $$,
  'payment 01 carries exactly one refund, for its whole amount, completed — 500000 paise came in and 500000 went back out, once'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 516 — the second shape out of completed. Its own refund and its own payment,
-- so a demotion that lands at 512 cannot make this one pass or fail for the
-- wrong reason.
select throws_ok($$
  update public.refunds set status = 'requested'
   where id = '22000000-0000-4000-8000-000000210202'::uuid
$$, null::char(5), null,
  'completed to requested is refused too — "any change out of completed", not only the demotion to failed that was measured');

set local role postgres;

-- 517
select results_eq(
  $$ select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210202'::uuid $$,
  $$ values ('completed'::text) $$,
  'that refund is still completed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 518 — the third and last shape out of completed. With 512 and 516 this
-- enumerates every other label `refund_status` carries.
select throws_ok($$
  update public.refunds set status = 'processing'
   where id = '22000000-0000-4000-8000-000000210203'::uuid
$$, null::char(5), null,
  'completed to processing is refused — the third of the three labels a completed refund could be moved to, so the enum is covered exhaustively rather than by the one shape a critic happened to run');

set local role postgres;

-- 519
select results_eq(
  $$ select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210203'::uuid $$,
  $$ values ('completed'::text) $$,
  'that refund is still completed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 520 — THE SAME-VALUE WRITE, and the first of the three too-broad detectors.
-- "Refuse any change OUT OF completed": a row written its own status back has
-- not moved and cannot do the harm. This codebase settled the identical
-- question twice already, for `periods_granted` and for the membership dates —
-- "a rule that refuses a write that cannot do harm buys nothing and breaks
-- ordinary column-listing updates" — and the idiom is `is distinct from`.
select lives_ok($$
  update public.refunds set status = 'completed'
   where id = '22000000-0000-4000-8000-000000210204'::uuid
$$, 'a completed refund written its own status back is ALLOWED — nothing changed, so nothing was refused');

set local role postgres;

-- 521
select results_eq(
  $$ select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210204'::uuid $$,
  $$ values ('completed'::text) $$,
  'and it is still completed afterwards');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 522 — the second too-broad detector. The requirement freezes the STATUS of a
-- completed refund, not the row: `payment_id` and `amount_paise` are already
-- frozen by GL041 and no other column of a refund is. A provider reference
-- arriving after the refund completed is ordinary reconciliation work, and an
-- implementation that made the whole row immutable would refuse it.
select lives_ok($$
  update public.refunds set provider_refund_id = 'rfnd_T21_0004'
   where id = '22000000-0000-4000-8000-000000210204'::uuid
$$, 'a completed refund''s provider_refund_id is still writable — the status is what is frozen, not the row');

set local role postgres;

-- 523
select results_eq(
  $$ select provider_refund_id, status::text from public.refunds
      where id = '22000000-0000-4000-8000-000000210204'::uuid $$,
  $$ values ('rfnd_T21_0004'::text, 'completed'::text) $$,
  'the reference landed and the status is untouched — the write went through rather than being silently dropped'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 524-526 — the requirement's own scenario "A refund that genuinely failed":
-- the moves AMONG the non-completed statuses, all three of them, on payment 05.
-- 524 forward, 525 to failed, 526 back OUT of failed — the last one re-counts a
-- refund into the GL036 sum, which is the mirror of the move this requirement
-- was written about, and it is allowed because it stays under the ceiling.
select lives_ok($$
  update public.refunds set status = 'processing'
   where id = '22000000-0000-4000-8000-000000210205'::uuid
$$, 'scenario "A refund that genuinely failed" — requested to processing is allowed');

-- 525
select lives_ok($$
  update public.refunds set status = 'failed'
   where id = '22000000-0000-4000-8000-000000210206'::uuid
$$, 'processing to failed is allowed — a refund the provider rejected took nothing, and recording that is the whole point of the status');

-- 526
select lives_ok($$
  update public.refunds set status = 'requested'
   where id = '22000000-0000-4000-8000-000000210207'::uuid
$$, 'failed back to requested is allowed — the retry, which puts the money back INTO the GL036 sum and is permitted because the sum stays under the ceiling');

set local role postgres;

-- 527
select results_eq(
  $$
    select
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210205'::uuid),
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210206'::uuid),
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210207'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210105'::uuid and status <> 'failed')
  $$,
  $$ values ('processing'::text, 'failed'::text, 'requested'::text, 200000::bigint) $$,
  'all three moves LANDED — they are permissions, not silent no-ops (ADR-078) — and the non-failed total against payment 05 is 200000, the two rows that are not failed'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 528 — the ordinary forward path INTO completed, which is how a refund is
-- supposed to reach the state this requirement freezes. If this were refused
-- no refund could ever complete and the freeze would be protecting nothing.
select lives_ok($$
  update public.refunds set status = 'completed'
   where id = '22000000-0000-4000-8000-000000210205'::uuid
$$, 'processing to completed is allowed — the money actually leaving is the ordinary path, and it is bounded by GL036 on update as everything else is');

set local role postgres;

-- 529
select results_eq(
  $$
    select
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210205'::uuid),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210105'::uuid and status <> 'failed')
  $$,
  $$ values ('completed'::text, 200000::bigint) $$,
  'it completed, and the non-failed total is unchanged at 200000 — completing a refund that was already counted moves no money twice'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 530 — and the refund that reached `completed` legitimately, one statement
-- ago, in this same transaction, is frozen exactly like one that arrived there
-- as a fixture. A rule keyed on how the row got there rather than on where it
-- is would pass 512 and fail here.
select throws_ok($$
  update public.refunds set status = 'failed'
   where id = '22000000-0000-4000-8000-000000210205'::uuid
$$, null::char(5), null,
  'a refund that reached completed by the ordinary path is frozen the same way — the rule is about the state, not about how the row arrived at it');

set local role postgres;

-- 531
select results_eq(
  $$ select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210205'::uuid $$,
  $$ values ('completed'::text) $$,
  'still completed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 532-537 — THE CEILING RELEASING, WHICH IS DECIDED-PERMITTED, walked end to
-- end on payment 06. A `requested` refund is IN the GL036 sum, so demoting it
-- releases the ceiling exactly as the measured defect did. The coordinator's
-- mid-round decision is that this stays permitted: money in flight may become
-- an attempt, money that LEFT may not. Run against Cloud before it was written
-- down, so these six assert a measured behaviour rather than a prediction.
--
-- What they pin is where the money is bounded, and by WHICH rule: GL036
-- applied on UPDATE, which lives in a different requirement. Only one of the
-- two refunds can ever reach `completed`, so only one payment's worth can
-- actually leave — and 537 asserts exactly that, in paise. 596-599 run the
-- same walk from `processing`, which is the shape the holdout measured.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210211'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210106'::uuid, 'refund', 200000, 'requested',
          'second full refund of payment 06', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'GL036'::char(5), null,
  'a second full refund against payment 06 is refused while the first is merely requested — a requested refund is in the sum, because the sum excludes only failed rows');

-- 533
select lives_ok($$
  update public.refunds set status = 'failed'
   where id = '22000000-0000-4000-8000-000000210208'::uuid
$$, 'and demoting that REQUESTED refund to failed is ALLOWED, deliberately — money handed to the provider and not yet moved by it can genuinely fail, and refusing this would strand the refund while the ceiling consumed money that never left');

-- 534
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210211'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210106'::uuid, 'refund', 200000, 'requested',
          'second full refund of payment 06, after the un-counting', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'so the second full refund IS now accepted — the ceiling released, which is the decided behaviour and not a defect. Two full refunds sit against one payment and neither has taken anything');

-- 535
select throws_ok($$
  update public.refunds set status = 'completed'
   where id = '22000000-0000-4000-8000-000000210208'::uuid
$$, 'GL036'::char(5), null,
  'THE BOUND THAT ACTUALLY HOLDS: the un-counted refund can never be completed again, because GL036 applies on UPDATE and the ceiling is full. The door is open; the money cannot get through it twice');

-- 536
select lives_ok($$
  update public.refunds set status = 'completed'
   where id = '22000000-0000-4000-8000-000000210211'::uuid
$$, 'and exactly one of the two — the one already counted — can complete');

set local role postgres;

-- 537
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210106'::uuid and status = 'completed'),
      (select coalesce(sum(amount_paise), 0)::bigint from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210106'::uuid and status = 'completed'),
      (select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210208'::uuid)
  $$,
  $$ values (1, 200000::bigint, 'failed'::text) $$,
  'one completed refund of 200000 against a 200000 payment, and the un-counted one is stranded at failed — 200000 came in and 200000 went out, whatever was done to the statuses in between'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_manager',
                    'staff_id', '22000000-0000-4000-8000-000000210022')::text,
  true);
set local role authenticated;

-- 538 — the other gym-admin role. `refunds_tenant_write` is app.is_gym_admin(),
-- so a gym manager and a gym owner are the only sessions that reach this table
-- at all, and the rule is an invariant rather than a claim rule — it must not
-- read which of the two is asking. The refund here was initiated by the manager
-- and is being demoted by the manager, so nothing about attribution is in play.
select throws_ok($$
  update public.refunds set status = 'requested'
   where id = '22000000-0000-4000-8000-000000210209'::uuid
$$, null::char(5), null,
  'a gym MANAGER demoting a completed refund is refused as well — this is an invariant about the money, not a judgement about the claim, and it takes no role carve-out');

set local role postgres;

-- 539
select results_eq(
  $$ select status::text from public.refunds where id = '22000000-0000-4000-8000-000000210209'::uuid $$,
  $$ values ('completed'::text) $$,
  'the manager''s refund is still completed');

-- 540 — the closing money invariant for this whole tenant, stated as the thing
-- the requirement is FOR rather than as one more refusal: however the statuses
-- were walked above, no payment in this gym has had more money leave it than
-- came in. Green today and green after the fix; it is the floor the section
-- asserts nothing may fall below.
select results_eq(
  $$
    select count(*)::int from public.payments p
     where p.tenant_id = '22000000-0000-4000-8000-000000210001'::uuid
       and (select coalesce(sum(r.amount_paise), 0) from public.refunds r
             where r.payment_id = p.id and r.status <> 'failed') > p.amount_paise
  $$,
  $$ values (0) $$,
  'and not one payment in tenant 21 carries a non-failed refund total above its own amount — the invariant the freeze exists to protect, asserted over the whole gym rather than row by row'
);


-- ===========================================================================
-- SECTION 26 (ROUND SEVENTEEN) — "Money only comes back out of money that came
-- in". Tenant 22. Assertions 541-562.
--
-- THE MEASURED DEFECT. `app.enforce_refund_total()` reads a payment's
-- `amount_paise` and never its status, and `amount_paise` is not null on a
-- `created` row. A 500000-paise completed refund against a payment that never
-- arrived was accepted — reproduced from this session against Cloud before this
-- section was written. The membership page already tells the desk this is
-- impossible; it was not.
--
-- ENUMERATED FROM THE CATALOGUE. `payment_status` is (`created`, `pending`,
-- `paid`, `failed`, `refunded`, `reversed`). All six appear below: three
-- refused (541, 543, 545) and three permitted (549, 550, 551), so the rule's
-- line is drawn by assertions on both sides of it rather than by three
-- refusals that a blanket refusal would also satisfy.
--
-- A FIXTURE FACT WORTH RECORDING, because it shaped this section: a payment
-- CANNOT be inserted directly at `refunded` or `reversed` — `GL039` refuses it
-- ("a payment is recorded and then refunded — it does not arrive already
-- refunded"), for postgres as much as for a session, since that rule takes no
-- trusted-context carve-out. Those two fixtures are therefore written `paid`
-- and moved, which is the only way they exist in production either.
--
-- THE SIBLING THIS RULE MUST NOT SWALLOW. "A refund is bounded when it is
-- written and whenever it changes" carves `failed` refunds out of the ceiling —
-- "a failed refund took nothing, and the rule that excludes failed rows from
-- the sum must exclude them from the comparison too". That carve-out is about
-- the CEILING. It is not an exemption from this rule: a refund recorded as
-- itself `failed` against a payment that never arrived is still a refund naming
-- money that never came in, and 547 asserts it is refused. An implementation
-- that reuses the ceiling's `failed` short-circuit for this check would let it
-- through, which is exactly the shape of mistake this phase keeps making.
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000220001'::uuid, 'PayRec Gym 22', 'PYR22O');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000220011'::uuid, '22000000-0000-4000-8000-000000220001'::uuid, 'G22 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000220021'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220011'::uuid, 'gym_owner', 'T22 Owner');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000220041'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220011'::uuid, 'M22', '+912222000041');

-- 220101 created, 220102 pending, 220103 failed, 220104 paid, 220105 and
-- 220106 paid (moved below), 220107 created (the failed-refund case), 220108
-- pending (the becomes-paid-later case). No receipt number on the rows that
-- have not taken money: a receipt is issued when a payment becomes paid, and a
-- number on an unpaid row is a separate requirement's business.
insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000220101'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'created', 'cash', null, '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220102'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'pending', 'cash', null, '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220103'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'failed', 'cash', null, '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220104'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'paid', 'cash', 'T22-RCT-04', '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220105'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'paid', 'cash', 'T22-RCT-05', '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220106'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'paid', 'cash', 'T22-RCT-06', '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220107'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'created', 'cash', null, '22000000-0000-4000-8000-000000220021'::uuid),
  ('22000000-0000-4000-8000-000000220108'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
   '22000000-0000-4000-8000-000000220041'::uuid, 500000, 'pending', 'cash', null, '22000000-0000-4000-8000-000000220021'::uuid);

-- The two "money came in and then came back" fixtures, made the only way the
-- transition rule permits.
update public.payments set status = 'refunded' where id = '22000000-0000-4000-8000-000000220105'::uuid;
update public.payments set status = 'reversed' where id = '22000000-0000-4000-8000-000000220106'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 541 — the requirement's own scenario, first status: a `created` payment. This
-- is the exact shape a critic reproduced.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220201'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220101'::uuid, 'refund', 500000, 'completed',
          'refund of a payment that never arrived', '22000000-0000-4000-8000-000000220021'::uuid)
$$, null::char(5), null,
  'scenario "Refunding a payment that never arrived" — a refund against a CREATED payment is refused. amount_paise is not null on a created row, and that alone is what the ceiling was reading');

set local role postgres;

-- 542
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220101'::uuid $$,
  $$ values (0) $$,
  'and no refund exists against it — "no refund SHALL exist", not merely "an error was raised"');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 543
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220202'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220102'::uuid, 'refund', 500000, 'completed',
          'refund of a pending payment', '22000000-0000-4000-8000-000000220021'::uuid)
$$, null::char(5), null,
  'a refund against a PENDING payment is refused — the money is on its way, which is not the same as having arrived');

set local role postgres;

-- 544
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220102'::uuid $$,
  $$ values (0) $$,
  'no refund exists against the pending payment');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 545
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220203'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220103'::uuid, 'refund', 500000, 'completed',
          'refund of a failed payment', '22000000-0000-4000-8000-000000220021'::uuid)
$$, null::char(5), null,
  'a refund against a FAILED payment is refused — the third and last status the requirement names, so the refused side is enumerated rather than sampled');

set local role postgres;

-- 546
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220103'::uuid $$,
  $$ values (0) $$,
  'no refund exists against the failed payment');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 547 — the sibling rule's carve-out must not become a hole in this one. A
-- refund whose OWN status is `failed` is excluded from the GL036 sum and from
-- the GL036 comparison, on the reasoning that it took nothing. That reasoning
-- says nothing about whether the payment it names ever arrived, and an
-- implementation that reaches for the same short-circuit here would accept
-- this row.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220204'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220107'::uuid, 'refund', 500000, 'failed',
          'a failed refund of a payment that never arrived', '22000000-0000-4000-8000-000000220021'::uuid)
$$, null::char(5), null,
  'a refund recorded as itself FAILED against a created payment is refused too — the ceiling''s failed carve-out is about how much may go out, not about whether anything came in');

set local role postgres;

-- 548
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220107'::uuid $$,
  $$ values (0) $$,
  'and nothing was recorded against it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 549-551 — the permitted side, all three statuses the requirement names.
-- Without these a blanket refusal of every refund would satisfy 541-548.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220205'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220104'::uuid, 'refund', 100000, 'completed',
          'part refund of money that arrived', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'scenario "Refunding money that did arrive" — a refund against a PAID payment is permitted');

-- 550
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220206'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220105'::uuid, 'refund', 100000, 'completed',
          'further refund of a refunded payment', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'a refund against a REFUNDED payment is permitted — the money arrived, and how much of it may still go back is GL036''s question, not this rule''s');

-- 551
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220207'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220106'::uuid, 'reversal', 100000, 'completed',
          'reversal against a reversed payment', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'and a reversal against a REVERSED payment is permitted — the third status on the permitted side');

set local role postgres;

-- 552 — both directions in one row (ADR-078): the three permitted refunds
-- landed AND the four refused ones left nothing behind. A fix that refuses
-- everything fails the first half; a fix that refuses nothing fails the second.
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220104'::uuid),
      (select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220105'::uuid),
      (select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220106'::uuid),
      (select count(*)::int from public.refunds r join public.payments p on p.id = r.payment_id
        where p.tenant_id = '22000000-0000-4000-8000-000000220001'::uuid
          and p.status not in ('paid', 'refunded', 'reversed'))
  $$,
  $$ values (1, 1, 1, 0) $$,
  'one refund against each of the three payments that took money, and zero against every payment in this gym that did not — the requirement''s sentence as a single query'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 553 — "it SHALL be bounded by GL036 as it is today". The permitted side is
-- permitted, not unbounded: 100000 is already out against a 500000 payment, so
-- a further 500000 is refused.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220208'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220104'::uuid, 'refund', 500000, 'completed',
          'over the ceiling', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'GL036'::char(5), null,
  'and the ceiling still applies on the permitted side — this rule adds a condition to GL036, it does not replace it');

set local role postgres;

-- 554
select results_eq(
  $$ select count(*)::int, coalesce(sum(amount_paise), 0)::bigint from public.refunds
      where payment_id = '22000000-0000-4000-8000-000000220104'::uuid $$,
  $$ values (1, 100000::bigint) $$,
  'still one refund of 100000 against it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 555 — the sequence the requirement does not spell out and an implementation
-- could easily get wrong in either direction: a refund ATTEMPTED before the
-- money arrived. Refused now.
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220209'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220108'::uuid, 'refund', 100000, 'completed',
          'refund attempted before the money arrived', '22000000-0000-4000-8000-000000220021'::uuid)
$$, null::char(5), null,
  'a refund attempted while its payment is still pending is refused');

set local role postgres;

-- 556
select results_eq(
  $$ select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220108'::uuid $$,
  $$ values (0) $$,
  'nothing recorded');

-- The money then arrives, along the transition GL039 permits. The receipt
-- number goes on in the same statement because a paid payment must carry one
-- and this row has never been paid, so nothing about it is frozen yet.
update public.payments set status = 'paid', receipt_number = 'T22-RCT-08'
 where id = '22000000-0000-4000-8000-000000220108'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 557 — and the same refund, written after the money arrived, is accepted. The
-- rule reads the payment's status at the moment the refund is written; it is
-- not a permanent mark against a payment that was once unpaid. It carries its
-- own id rather than 555's, deliberately: reusing that one would collide on
-- the primary key for as long as 555's refusal is missing, and an assertion
-- that goes red on a duplicate key is an assertion failing for a reason that
-- has nothing to do with what it claims.
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220212'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220108'::uuid, 'refund', 100000, 'completed',
          'refund after the money arrived', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'the identical refund is accepted once the payment is paid — the rule reads the status now, and does not hold a payment''s history against it');

set local role postgres;

-- 558
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds where payment_id = '22000000-0000-4000-8000-000000220108'::uuid),
      (select status::text from public.payments where id = '22000000-0000-4000-8000-000000220108'::uuid)
  $$,
  $$ values (1, 'paid'::text) $$,
  'exactly one refund against it — the one written after the money arrived, and not also the one attempted before'
);

-- The other direction of the same question: a payment that was paid, was
-- refunded once, and is then marked `refunded`.
update public.payments set status = 'refunded' where id = '22000000-0000-4000-8000-000000220104'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 559
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220210'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220104'::uuid, 'refund', 100000, 'completed',
          'second part refund after the payment was marked refunded', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'a payment that was paid and has since moved to refunded still accepts a further refund within its ceiling — money that came in does not stop having come in');

set local role postgres;

-- 560
select results_eq(
  $$ select count(*)::int, coalesce(sum(amount_paise), 0)::bigint from public.refunds
      where payment_id = '22000000-0000-4000-8000-000000220104'::uuid $$,
  $$ values (2, 200000::bigint) $$,
  'two refunds totalling 200000 against a 500000 payment');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000220001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000220021')::text,
  true);
set local role authenticated;

-- 561
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000220211'::uuid, '22000000-0000-4000-8000-000000220001'::uuid,
          '22000000-0000-4000-8000-000000220104'::uuid, 'refund', 400000, 'completed',
          'over the ceiling on a refunded payment', '22000000-0000-4000-8000-000000220021'::uuid)
$$, 'GL036'::char(5), null,
  'and the ceiling followed the payment through the status change — 200000 is already out, so 400000 more is refused');

set local role postgres;

-- 562 — the closing invariant for this tenant, and the requirement's own
-- sentence: every refund on the books names a payment that actually took money.
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds r
        where r.tenant_id = '22000000-0000-4000-8000-000000220001'::uuid),
      (select count(*)::int from public.refunds r join public.payments p on p.id = r.payment_id
        where r.tenant_id = '22000000-0000-4000-8000-000000220001'::uuid
          and p.status not in ('paid', 'refunded', 'reversed'))
  $$,
  $$ values (5, 0) $$,
  'five refunds exist in tenant 22 and every one of them names a payment that took money — the count keeps a blanket refusal from passing, the zero keeps the defect from passing'
);


-- ===========================================================================
-- SECTION 27 (ROUND SEVENTEEN) — "A membership belongs to the member it was
-- sold to". Tenant 23. Assertions 563-595.
--
-- THE MEASURED DEFECT. `memberships.member_id` is frozen by nothing — not the
-- terms rule, whose column list is closed and excludes it, and not the stamp.
-- From a FRONT-DESK session, in one statement, a membership carrying a granted
-- period moved to a different member while the paid payment still named the
-- original one and carried their receipt number. Reproduced from this session
-- against Cloud, in every statement shape below, before any of them was written
-- down.
--
-- THE TRAP THE REQUIREMENT NAMES, AND HOW THIS SECTION AVOIDS IT.
-- `memberships_tenant_id_member_id_live_key` is `unique (tenant_id, member_id)
-- where status in ('active','frozen')`, so a move onto a member who already
-- holds a live membership is refused by the INDEX and a careless assertion
-- reports a false GREEN. Three separate defences:
--   * every target below (T1…T9) holds NOTHING, and 577 asserts that as its own
--     assertion, positioned BEFORE the refusals so a reader can see the trap was
--     disarmed rather than take it on trust;
--   * each attempt uses a DIFFERENT target, so an attempt that lands (as they
--     all do today) cannot turn the next one into a same-value write that is
--     refused by nothing and passes for a third wrong reason;
--   * 592 moves a CANCELLED membership, which the partial index does not cover
--     on either side, so nothing but this requirement can refuse it.
-- 594 then runs the trap deliberately, as the control: the move onto a member
-- who does hold a live membership, asserted as refused without pinning which
-- rule refuses it. It is green today for the wrong reason and green afterwards
-- for the right one, and its message says so.
--
-- PART A IS THE PERMITTED SIDE AND IT COMES FIRST. This project has three times
-- shipped a fix broad enough to pass every refusal test, so selling, renewing,
-- freezing, cancelling and re-selling are asserted on their own memberships
-- BEFORE anything is attacked — green today, and required to still be green
-- after. Creation is deliberately among them: the requirement governs a session
-- that CHANGES a member_id, and creating a membership for somebody is not
-- re-pointing one. It is also, plainly, the front desk's job.
--
-- THE SAME-VALUE WRITE (566) is allowed on the requirement's own word —
-- "changes", not "writes" — which is the precedence the sibling requirement for
-- the dates settled explicitly after a blind author caught the same wording
-- drift ("Change, not write").
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000230001'::uuid, 'PayRec Gym 23', 'PYR22P');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000230011'::uuid, '22000000-0000-4000-8000-000000230001'::uuid, 'G23 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000230021'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'front_desk', 'T23 Desk'),
  ('22000000-0000-4000-8000-000000230022'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'gym_owner', 'T23 Owner');

-- A holds the membership under attack and a cancelled one; C is the trap
-- control and holds a live membership; S is renewed, frozen, cancelled and
-- re-sold in Part A; E and F are sold to in Part A; T1..T9 hold nothing at all
-- and are the targets of the nine refused moves.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000230041'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 A', '+912223000041'),
  ('22000000-0000-4000-8000-000000230043'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 C (holds a live one)', '+912223000043'),
  ('22000000-0000-4000-8000-000000230044'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 S', '+912223000044'),
  ('22000000-0000-4000-8000-000000230045'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 E', '+912223000045'),
  ('22000000-0000-4000-8000-000000230046'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 F', '+912223000046'),
  ('22000000-0000-4000-8000-000000230051'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T1', '+912223000051'),
  ('22000000-0000-4000-8000-000000230052'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T2', '+912223000052'),
  ('22000000-0000-4000-8000-000000230053'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T3', '+912223000053'),
  ('22000000-0000-4000-8000-000000230054'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T4', '+912223000054'),
  ('22000000-0000-4000-8000-000000230055'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T5', '+912223000055'),
  ('22000000-0000-4000-8000-000000230056'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T6', '+912223000056'),
  ('22000000-0000-4000-8000-000000230057'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T7', '+912223000057'),
  ('22000000-0000-4000-8000-000000230058'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T8', '+912223000058'),
  ('22000000-0000-4000-8000-000000230059'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230011'::uuid, 'M23 T9', '+912223000059');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000230061'::uuid, '22000000-0000-4000-8000-000000230001'::uuid, 'G23 Plan (30d)', 30, 100000);

create temp table today_t23 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000230001'::uuid;
grant select on today_t23 to public;

-- Every membership starts at `ends_on = today`, so one granted period is
-- `today + 30` and nothing else is in the arithmetic (ADR-039: the date comes
-- from the gym's own clock, never a literal and never current_date).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000230081'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230041'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
   'active', (select d from today_t23), (select d from today_t23), 100000),
  ('22000000-0000-4000-8000-000000230082'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230041'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
   'cancelled', (select d from today_t23), (select d from today_t23), 100000),
  ('22000000-0000-4000-8000-000000230083'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230043'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
   'active', (select d from today_t23), (select d from today_t23), 100000),
  ('22000000-0000-4000-8000-000000230084'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230044'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
   'active', (select d from today_t23), (select d from today_t23), 100000);

-- The granted period is BOUGHT rather than typed: `periods_granted` may not be
-- written by hand at all (GL044), and the harm this requirement names is a
-- membership "carrying a granted period" moving away from the person who bought
-- it. So the fixture pays for it.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000230101'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
   '22000000-0000-4000-8000-000000230041'::uuid, '22000000-0000-4000-8000-000000230081'::uuid,
   100000, 'paid', 'cash', 'T23-RCT-01', '22000000-0000-4000-8000-000000230021'::uuid);

-- Captured after the money landed and before anything is attacked, so
-- "unchanged" below means "as the money left it" rather than "as the INSERT
-- wrote it".
create temp table ms_r17_before as
  select id, member_id, status, periods_granted, starts_on, ends_on
    from public.memberships
   where id in ('22000000-0000-4000-8000-000000230081'::uuid,
                '22000000-0000-4000-8000-000000230082'::uuid);
grant select on ms_r17_before to public;

-- 563 — the fixture exercised the granting rule rather than merely inserting a
-- row: one period bought, dates moved. Without this, every "unchanged" below
-- could be comparing an unmoved membership against itself.
select results_eq(
  $$ select periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select 1, (select d from today_t23) + 30 $$,
  'the membership under attack genuinely carries a granted period that money bought — one period, ends_on moved 30 days. This is the row the measured defect moved to another member'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- PART A — the permitted side, first, on its own rows.

-- 564 — creating a membership FOR another member is not re-pointing one. The
-- requirement governs a session that CHANGES member_id; a fix that froze the
-- column at INSERT as well would stop the gym selling anything.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-000000230085'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
          '22000000-0000-4000-8000-000000230045'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
          'active', (select d from today_t23), (select d from today_t23), 100000)
$$, 'a front desk creating a membership for a member is allowed — this rule refuses re-pointing, and selling is not re-pointing');

set local role postgres;

-- 565
select results_eq(
  $$ select member_id, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000230085'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000230045'::uuid, 0) $$,
  'and it landed naming that member, granted nothing');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 566 — the same-value write. The requirement says "changes", and its sibling
-- for the membership dates settled this precedence in as many words after a
-- blind author caught the drift: change, not write.
select lives_ok($$
  update public.memberships set member_id = member_id
   where id = '22000000-0000-4000-8000-000000230084'::uuid
$$, 'a membership written its own member_id back is allowed — nothing changed, and a rule that refuses a write that cannot do harm breaks ordinary column-listing updates');

set local role postgres;

-- 567
select results_eq(
  $$ select member_id from public.memberships where id = '22000000-0000-4000-8000-000000230084'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000230044'::uuid) $$,
  'and it still names the same member');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 568 — an ordinary renewal. The granting rule writes to `memberships` itself,
-- and a freeze written without `is distinct from` on the right column could
-- refuse the rule's own write.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id, receipt_number)
  values ('22000000-0000-4000-8000-000000230102'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
          '22000000-0000-4000-8000-000000230044'::uuid, '22000000-0000-4000-8000-000000230084'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000230021'::uuid, 'T23-RCT-02')
$$, 'an ordinary front-desk renewal still works');

set local role postgres;

-- 569
select results_eq(
  $$ select periods_granted, ends_on, member_id from public.memberships
      where id = '22000000-0000-4000-8000-000000230084'::uuid $$,
  $$ select 1, (select d from today_t23) + 30, '22000000-0000-4000-8000-000000230044'::uuid $$,
  'and it granted its period and moved the dates, still naming the member who paid — the rule''s own write to the membership is not a re-pointing'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 570-571 — freeze and unfreeze, the other ordinary UPDATE a front desk makes
-- against this table.
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-000000230084'::uuid
$$, 'freezing a membership still works');

-- 571
select lives_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-000000230084'::uuid
$$, 'and unfreezing it still works');

set local role postgres;

-- 572
select results_eq(
  $$ select status::text, member_id, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000230084'::uuid $$,
  $$ values ('active'::text, '22000000-0000-4000-8000-000000230044'::uuid, 1) $$,
  'and the freeze cycle moved the status and nothing else');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 573-575 — the requirement's own second scenario, whose heading says "Selling
-- the same member a second membership" and whose body says "a new one is sold
-- to ANOTHER member". Those are two different acts, so both are asserted rather
-- than one of them chosen. See the report: the heading and the WHEN disagree.
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now()
   where id = '22000000-0000-4000-8000-000000230084'::uuid
$$, 'scenario "Selling the same member a second membership", step one — cancelling is allowed');

-- 574
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-000000230086'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
          '22000000-0000-4000-8000-000000230044'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
          'active', (select d from today_t23), (select d from today_t23), 100000)
$$, 'step two, the heading''s reading — the SAME member is sold a second membership once the first is cancelled');

-- 575
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-000000230087'::uuid, '22000000-0000-4000-8000-000000230001'::uuid,
          '22000000-0000-4000-8000-000000230046'::uuid, '22000000-0000-4000-8000-000000230061'::uuid,
          'active', (select d from today_t23), (select d from today_t23), 100000)
$$, 'step two, the body''s reading — a new membership is sold to ANOTHER member. The remedy this phase prescribes is refund, cancel, sell again, and all three of its steps have to work');

set local role postgres;

-- 576
select results_eq(
  $$
    select
      (select count(*)::int from public.memberships
        where member_id = '22000000-0000-4000-8000-000000230044'::uuid and status = 'active'),
      (select count(*)::int from public.memberships
        where member_id = '22000000-0000-4000-8000-000000230044'::uuid and status = 'cancelled'),
      (select count(*)::int from public.memberships
        where member_id = '22000000-0000-4000-8000-000000230046'::uuid)
  $$,
  $$ values (1, 1, 1) $$,
  'one active and one cancelled for the member who was re-sold, and one for the member sold to — the whole remedy path works, which is what makes refusing the re-point affordable'
);

-- PART B — the trap, disarmed and shown to be disarmed, BEFORE any refusal is
-- asserted. If any of T1..T9 held a live membership, every throws_ok below
-- would pass on memberships_tenant_id_member_id_live_key and this suite would
-- report GREEN against an unfixed database. That is precisely how the
-- requirement says a careless author gets this wrong.

-- 577
select results_eq(
  $$ select count(*)::int from public.memberships
      where member_id in ('22000000-0000-4000-8000-000000230051'::uuid,
                          '22000000-0000-4000-8000-000000230052'::uuid,
                          '22000000-0000-4000-8000-000000230053'::uuid,
                          '22000000-0000-4000-8000-000000230054'::uuid,
                          '22000000-0000-4000-8000-000000230055'::uuid,
                          '22000000-0000-4000-8000-000000230056'::uuid,
                          '22000000-0000-4000-8000-000000230057'::uuid,
                          '22000000-0000-4000-8000-000000230058'::uuid,
                          '22000000-0000-4000-8000-000000230059'::uuid) $$,
  $$ values (0) $$,
  'THE TRAP, DISARMED: every target of every refused move below holds zero memberships of any status, so memberships_tenant_id_member_id_live_key cannot be what refuses any of them. Asserted rather than assumed, because a false GREEN here is the failure the requirement predicts by name'
);

-- PART C — the refusals. Each uses a different target, so a move that lands
-- cannot turn the next attempt into a same-value write that passes for a third
-- wrong reason.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 578 — the measured defect exactly: a FRONT DESK, one statement, a membership
-- carrying a granted period moved to a member holding nothing.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000230051'::uuid
   where id = '22000000-0000-4000-8000-000000230081'::uuid
$$, null::char(5), null,
  'scenario "Moving a membership to another member" — a front-desk session re-pointing a membership that carries a granted period is refused. The least-privileged writer who can reach the table at all, which is how it was measured');

set local role postgres;

-- 579
select results_eq(
  $$ select member_id, status::text, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, status::text, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'and the membership is exactly as the money left it — the owner, the count and both dates, not just the refusal'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000230022')::text,
  true);
set local role authenticated;

-- 580 — a gym admin. The requirement says "any session", and this is an
-- invariant about the data rather than a judgement about a claim, so being the
-- owner buys nothing.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000230052'::uuid
   where id = '22000000-0000-4000-8000-000000230081'::uuid
$$, null::char(5), null,
  'a GYM OWNER is refused too — "any session". Correcting who a membership was sold to is a refund, a cancellation and a new sale, which is the answer this phase gives for every other recorded fact');

set local role postgres;

-- 581
select results_eq(
  $$ select member_id, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'unchanged after the owner''s attempt');

set local role service_role;

-- 582 — a trusted context, with row security switched off entirely. Of the
-- rules on this table only the claim rule (GL046, "which staff role are you")
-- carries a trusted-context carve-out, on ADR-082's general form: a carve-out is
-- sound exactly when the rule's subject is something a trusted caller
-- legitimately lacks. This rule's subject is which member a membership was sold
-- to, which a webhook has as much of as anybody. So no carve-out.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000230053'::uuid
   where id = '22000000-0000-4000-8000-000000230081'::uuid
$$, null::char(5), null,
  'and a service_role session — no row security at all — is refused as well. This is an invariant about the data, not a question about the caller''s role, so it takes no trusted-context carve-out');

set local role postgres;

-- 583
select results_eq(
  $$ select member_id, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'unchanged after the trusted writer''s attempt');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 584 — UPDATE … FROM. The value arrives from a join rather than a literal, so
-- a rule that only inspected the statement's target list would miss it.
select throws_ok($$
  update public.memberships m set member_id = x.mid
    from (values ('22000000-0000-4000-8000-000000230054'::uuid)) as x(mid)
   where m.id = '22000000-0000-4000-8000-000000230081'::uuid
$$, null::char(5), null,
  'UPDATE … FROM is refused — the new value coming from a join rather than a literal changes nothing about what the row becomes');

set local role postgres;

-- 585
select results_eq(
  $$ select member_id, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'unchanged after the UPDATE … FROM');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 586 — a data-modifying CTE, which is what an ORM or a hand-written
-- "do it all in one round trip" statement actually emits.
select throws_ok($$
  with moved as (
    update public.memberships set member_id = '22000000-0000-4000-8000-000000230055'::uuid
     where id = '22000000-0000-4000-8000-000000230081'::uuid
    returning 1
  )
  select count(*) from moved
$$, null::char(5), null,
  'a data-modifying CTE is refused — the write is still a write when it is wrapped in a WITH');

set local role postgres;

-- 587
select results_eq(
  $$ select member_id, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'unchanged after the CTE');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 588 — MERGE, which reaches the table by a different statement node again.
select throws_ok($$
  merge into public.memberships m
   using (select '22000000-0000-4000-8000-000000230081'::uuid as target) s
      on m.id = s.target
    when matched then update set member_id = '22000000-0000-4000-8000-000000230056'::uuid
$$, null::char(5), null,
  'MERGE … WHEN MATCHED THEN UPDATE is refused — a row trigger sees the row whatever statement node produced it, and asserting that is cheaper than assuming it');

set local role postgres;

-- 589
select results_eq(
  $$ select member_id, periods_granted, starts_on, ends_on
       from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  $$ select member_id, periods_granted, starts_on, ends_on
       from ms_r17_before where id = '22000000-0000-4000-8000-000000230081'::uuid $$,
  'unchanged after the MERGE');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 590 — two rows, one statement, two different targets. A rule evaluated per
-- statement rather than per row, or one that stopped at the first row it liked,
-- would let the second through.
select throws_ok($$
  update public.memberships
     set member_id = case when id = '22000000-0000-4000-8000-000000230081'::uuid
                          then '22000000-0000-4000-8000-000000230057'::uuid
                          else '22000000-0000-4000-8000-000000230058'::uuid end
   where id in ('22000000-0000-4000-8000-000000230081'::uuid,
                '22000000-0000-4000-8000-000000230082'::uuid)
$$, null::char(5), null,
  'one statement moving TWO memberships to two different members is refused — the rule is per row, and a refused row aborts the statement rather than being skipped');

set local role postgres;

-- 591
select results_eq(
  $$ select id, member_id, periods_granted, starts_on, ends_on
       from public.memberships
      where id in ('22000000-0000-4000-8000-000000230081'::uuid,
                   '22000000-0000-4000-8000-000000230082'::uuid)
      order by id $$,
  $$ select id, member_id, periods_granted, starts_on, ends_on
       from ms_r17_before order by id $$,
  'and BOTH rows are where they were — including the one whose move would have been the second in the statement'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 592 — THE SHARPEST ANTI-FALSE-GREEN SHAPE IN THIS SECTION. The membership is
-- `cancelled`, and memberships_tenant_id_member_id_live_key indexes only
-- `active` and `frozen` rows. Neither the row being moved nor the member it is
-- moved to is in that index at all, so there is nothing for it to collide with:
-- if this refuses, only this requirement can be refusing it.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000230059'::uuid
   where id = '22000000-0000-4000-8000-000000230082'::uuid
$$, null::char(5), null,
  'a CANCELLED membership is refused too, and the live unique key does not index cancelled rows on either side — so this refusal cannot be the index answering. A retired membership was still sold to somebody');

set local role postgres;

-- 593
select results_eq(
  $$ select member_id, status::text from public.memberships
      where id = '22000000-0000-4000-8000-000000230082'::uuid $$,
  $$ select member_id, status::text from ms_r17_before
      where id = '22000000-0000-4000-8000-000000230082'::uuid $$,
  'the cancelled membership still names the member it was sold to');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000230001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000230021')::text,
  true);
set local role authenticated;

-- 594 — THE TRAP ITSELF, run deliberately as the control. The target already
-- holds a live membership, so today this is refused by the unique index and
-- afterwards by the requirement. It is asserted as "refused" with no SQLSTATE,
-- and it is the one assertion in this section that is green against the
-- unfixed database — which is exactly why 577 and 592 exist beside it.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000230043'::uuid
   where id = '22000000-0000-4000-8000-000000230081'::uuid
$$, null::char(5), null,
  'the trap, run on purpose: moving onto a member who ALREADY holds a live membership is refused — but by the unique index today, which is why no assertion above relies on this shape');

set local role postgres;

-- 595
select results_eq(
  $$
    select
      (select member_id from public.memberships where id = '22000000-0000-4000-8000-000000230081'::uuid),
      (select count(*)::int from public.memberships where member_id = '22000000-0000-4000-8000-000000230043'::uuid),
      (select member_id from public.payments where id = '22000000-0000-4000-8000-000000230101'::uuid)
  $$,
  $$ values ('22000000-0000-4000-8000-000000230041'::uuid, 1, '22000000-0000-4000-8000-000000230041'::uuid) $$,
  'and the closing fact the whole requirement is about: the membership, and the paid payment that bought its period and carries its receipt, still name the SAME person — which is the sentence GL042 protects from the payment side and nothing protected from this one'
);


-- ===========================================================================
-- SECTION 28 (ROUND SEVENTEEN, coordinator decision) — "money that LEFT does
-- not become an attempt; money in flight may", on `processing`. Tenant 21,
-- one new payment. Assertions 596-599.
--
-- WHY IT IS HERE AND NOT INSIDE SECTION 25. The decision arrived after 509-595
-- were numbered and after both suites had been written against them; appending
-- costs four assertion numbers and renumbering would have churned eighty-seven
-- comments and the cross-references inside their messages. Section 24 already
-- sets the precedent of a later round revisiting an earlier section's tenant.
--
-- WHAT IT ADDS THAT 532-537 DOES NOT. 532-537 walks the release from
-- `requested`; the holdout measured it from `processing`, which is the status
-- that actually means "handed to the provider, not yet moved by it" and is
-- therefore the sharper case for the decision. Section 25 already asserts
-- `processing → failed` as a permitted TRANSITION (525) — but on a part refund,
-- where no ceiling is released and so nothing about the consequence is proven.
-- The coordinator's instruction is the consequence in both cases, not the
-- transition alone, and this is the half that was missing.
--
-- The rule being asserted is the narrow one:
--   * a refund at `processing` is IN the GL036 sum, so a full one blocks a
--     second (596);
--   * moving it to `failed` is PERMITTED (597) — it can genuinely fail, and
--     refusing would strand it while the ceiling consumed money that never
--     left;
--   * so the ceiling RELEASES and the second full refund is accepted (598),
--     which is the decided behaviour;
--   * and nothing has left, which is the whole of what the invariant protects
--     (599). Compare 512/514, where the same walk from `completed` is refused
--     and the ceiling holds — because there the money is gone.
-- ===========================================================================

insert into public.payments (id, tenant_id, member_id, amount_paise, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000210108'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210041'::uuid, 200000, 'paid', 'cash', 'T21-RCT-08', '22000000-0000-4000-8000-000000210021'::uuid);

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('22000000-0000-4000-8000-000000210220'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
   '22000000-0000-4000-8000-000000210108'::uuid, 'refund', 200000, 'processing', 'full refund, with the provider', '22000000-0000-4000-8000-000000210021'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000210001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000210021')::text,
  true);
set local role authenticated;

-- 596
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210221'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210108'::uuid, 'refund', 200000, 'processing',
          'second full refund of payment 08', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'GL036'::char(5), null,
  'a full refund sitting at PROCESSING blocks a second one with GL036 — money with the provider is counted, because it is on its way out');

-- 597
select lives_ok($$
  update public.refunds set status = 'failed'
   where id = '22000000-0000-4000-8000-000000210220'::uuid
$$, 'and the provider rejecting it — processing to failed — is PERMITTED. This is the transition''s whole purpose, and refusing it would leave a refund nobody can resolve while the ceiling consumed money that never left the gym');

-- 598
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-000000210221'::uuid, '22000000-0000-4000-8000-000000210001'::uuid,
          '22000000-0000-4000-8000-000000210108'::uuid, 'refund', 200000, 'processing',
          'retry after the provider rejected the first', '22000000-0000-4000-8000-000000210021'::uuid)
$$, 'THE CEILING CONSEQUENCE, and it is a release rather than a hold: the retry is accepted. Compare 514, where the same walk from COMPLETED leaves the second refund refused — the difference is whether the money actually left');

set local role postgres;

-- 599
select results_eq(
  $$
    select
      (select count(*)::int from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210108'::uuid and status = 'completed'),
      (select count(*)::int from public.refunds
        where payment_id = '22000000-0000-4000-8000-000000210108'::uuid),
      (select count(*)::int from public.payments p
        where p.tenant_id = '22000000-0000-4000-8000-000000210001'::uuid
          and (select coalesce(sum(r.amount_paise), 0) from public.refunds r
                where r.payment_id = p.id and r.status <> 'failed') > p.amount_paise)
  $$,
  $$ values (0, 2, 0) $$,
  'and NOTHING HAS LEFT: two refund attempts against payment 08, neither completed, and still no payment in this gym carrying a non-failed total above its own amount. The ceiling moved; the ledger did not. That is the whole of the invariant'
);



-- ===========================================================================
-- SECTION 29 (ROUND EIGHTEEN, OPEN-030) — "A membership's status moves only
-- where it can go." Tenant 24. Assertions 600-677.
--
-- Written from openspec/changes/membership-lifecycle/specs/membership-
-- lifecycle/spec.md by a session that has read no implementation of this
-- change (none exists yet), has not opened supabase/tests-holdout/, and has
-- not read docs/registry.md for anything about it (ADR-091). What it did read
-- is the schema as it stands — the catalogue, and the migrations that were
-- already applied before this change began — because a test that cannot see
-- the constraints it is writing around measures the constraints instead of
-- the requirement.
--
-- THE MEASURED DEFECT. `payments` has had a state machine since Phase 5 round
-- three (`app.payment_transition_allowed()`, `GL039`). `memberships` has
-- never had one. `docs/data-model.md` has listed the legal set since Phase 1
-- and called `expired` and `cancelled` terminal, and NOTHING HAS EVER
-- ENFORCED IT. Reproduced from this session against Cloud before a line of
-- this section was written: an ordinary front-desk session walked all
-- twenty-five ordered pairs of the five statuses, and all twenty-five landed
-- — `cancelled → active` among them, reviving a retired membership in one
-- statement.
--
-- WHAT THE REQUIREMENT SAYS, TRANSCRIBED ONCE. `pending → active|cancelled`;
-- `active → frozen|cancelled|expired`; `frozen → active|cancelled|expired`;
-- nothing out of `expired` or `cancelled`; and a status written back to
-- itself is allowed, because it changes nothing and a rule that refuses a
-- write which cannot do harm breaks ordinary column-listing updates. That is
-- thirteen permitted pairs and twelve refused, and 601 asserts exactly that
-- split so the transcription is itself checked rather than assumed.
--
-- THE PAIRS ARE ENUMERATED FROM `pg_enum`, NOT GUESSED. 29a builds its
-- twenty-five fixtures by cross-joining `membership_status` with itself in
-- `enumsortorder`, so the SET of pairs comes from the database and only the
-- VERDICT comes from the requirement. 600 pins the five labels: if a sixth is
-- ever added, 600 and 601 go red together and this section is revisited
-- rather than silently under-enumerating. Every pair gets its own membership
-- and its own member, so no attempt can be refused by
-- `memberships_tenant_id_member_id_live_key` (the partial unique index on
-- `active`/`frozen`) and report a false green — Section 27's own trap,
-- disarmed the same way and asserted at 602 BEFORE anything is attacked.
--
-- VERIFYING A NO-OP IS NOT VERIFYING. 602 also asserts each of the
-- twenty-five rows really started at the `from` status the pair names. An
-- `update … where id = <a uuid that does not exist>` raises nothing and
-- changes nothing, and this file has already been bitten once by a fixture id
-- that did not match the row it meant. Every refusal below is scored as the
-- PAIR of facts the requirement names: it raised, AND the status is what it
-- was.
--
-- NO SQLSTATE IS PINNED FOR A TRANSITION. This requirement names none, and
-- pinning one would be guessing at an implementation this author has not
-- seen. 628 asserts the property that is derivable without guessing: the
-- twelve refusals all report ONE code as each other — one rule, stated once —
-- and it is none of `23505`, `42501` or `23514`. Those three are the
-- false-green routes: the live partial unique index, a policy filtering the
-- row away, and a CHECK constraint. A CHECK cannot see `OLD`, so a CHECK
-- answering here would mean something other than the transition was refused.
-- Three codes ARE pinned in this section and all three belong to rules that
-- already exist and are not this one: `GL013` at the gate (671, 676),
-- `23514` at 644, and `GL036` in Section 30 — the last because the
-- requirement's own scenario names it.
--
-- THE PERMITTED SIDE IS ASSERTED AS HARD AS THE REFUSED SIDE, AND IT COMES
-- FIRST IN EACH SUBSECTION. This project has shipped a fix broad enough to
-- pass every refusal test four times now. 29b is the whole of it: the
-- granting rule activating a `pending` membership on its first payment,
-- BOTH renewals — `active → active` and `frozen → frozen` written by
-- `app.grant_periods()`' own UPDATE, which is a self-write and which a rule
-- that refuses "any status write on UPDATE" would break for every renewal in
-- the product — pausing and returning, and cancelling a live membership,
-- which is half the repair this codebase prescribes for a mis-sale.
--
-- CAN THE RULE TELL THE GRANTING RULE'S OWN WRITE APART, AND DOES IT NEED
-- TO? It does not need to, and 629-636 say so by asserting both directions:
-- `pending → active` is legal for a hand-written statement too (604), so the
-- granting rule needs no carve-out to activate a membership — it needs only
-- not to be refused for writing `status = m.status` on every other renewal.
-- A `pg_trigger_depth()` carve-out would pass 629-636 and 604 alike; so
-- would no carve-out at all. Neither is required by the requirement and
-- neither is asserted.
--
-- THE TRUSTED-CONTEXT LINE, READ AND STATED (29d). ADR-082's general form is
-- that a rule which JUDGES A CLAIM takes a carve-out for a session that
-- carries no claim, and a rule which is an INVARIANT ABOUT THE DATA does not.
-- A transition table is the second kind: which status may follow which is a
-- fact about the row, not a question about who is asking, and the same
-- reading is already written into this file at 595's neighbour in Section 27
-- ("an invariant about the data, not a question about the caller's role, so
-- it takes no trusted-context carve-out"). So 663-666 assert the refusal for
-- a gym admin, a super admin, `service_role` and `postgres` alike. This is a
-- READING and it is stated so it can be argued with: if the coordinator
-- decides a trusted context may repair a mis-cancelled membership by hand,
-- 665 and 666 are the two assertions that must change, and that is a `spec:`
-- commit. Note that nothing in the product needs the carve-out today —
-- `supabase/seed-scenarios.sql` INSERTS `expired` memberships, it does not
-- transition any, and this requirement governs a status that CHANGES.
--
-- THE GATE (29e). ADR-084 reads this column, and the point of retiring a
-- membership is that its member stops getting in. A membership retired by a
-- LEGAL transition must stop admitting; a membership FROZEN by a legal
-- transition must keep admitting, because a freeze is a pause and not a
-- retirement. Both are asserted, and 676 counts the check-ins that actually
-- landed so that neither can pass by the gate having refused everybody.
--
-- WHAT IS GREEN TODAY AND MUST STAY GREEN: every permitted pair (603, 604,
-- 607, 609-612, 614-617, 621, 627), the whole of 29b, the permitted shapes in
-- 29c (647-649, 656-659), 668-669, and the whole of 29e. Twenty-nine
-- assertions in THIS section are red today — 605, 606, 608, 613, 618-620,
-- 622-626, 628, 645, 646, 650-655, 660-667 — none in Section 30, and two more
-- (694, 695) in Section 31. Thirty-one of seven hundred, measured against
-- Cloud before the implementer had written anything.
--
-- Every date is the gym's own `(now() at time zone o.timezone)::date` via
-- `today_t24`, never `current_date` and never a literal (ADR-039).
-- ADR-030: this section commits nothing; the file's single BEGIN … ROLLBACK
-- covers it.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000240001'::uuid, 'PayRec Gym 24', 'PYR22Q');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000240011'::uuid, '22000000-0000-4000-8000-000000240001'::uuid, 'G24 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000240021'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'front_desk', 'T24 Desk'),
  ('22000000-0000-4000-8000-000000240022'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'gym_owner', 'T24 Owner');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000240061'::uuid, '22000000-0000-4000-8000-000000240001'::uuid, 'G24 Plan (30d)', 30, 100000);

create temp table today_t24 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000240001'::uuid;
grant select on today_t24 to public;


-- ---------------------------------------------------------------------------
-- 29a — EVERY ORDERED PAIR OF THE FIVE STATUSES (600-628).
--
-- `lc_pair` is the whole of this subsection: the SET of pairs is generated
-- from `pg_enum`, the VERDICT column is the requirement transcribed, and the
-- outcome columns are filled by one loop that attempts each pair from an
-- ordinary front-desk session. `verdict` collapses the two facts every
-- refusal must carry — that it raised, and that the status did not move —
-- into one string, so a rule that raises and lets the row through reads
-- "refused, but the row moved" rather than passing half an assertion.
-- ---------------------------------------------------------------------------

create temp table lc_pair (
  seq              integer,
  from_status      public.membership_status,
  to_status        public.membership_status,
  expected_allowed boolean,
  membership_id    uuid,
  raised           boolean,
  code             text,
  final_status     public.membership_status,
  verdict          text
);
grant select, insert, update on lc_pair to public;

insert into lc_pair (seq, from_status, to_status, expected_allowed)
select row_number() over (order by f.enumsortorder, t.enumsortorder),
       f.enumlabel::public.membership_status,
       t.enumlabel::public.membership_status,
       -- The requirement's own edge list, transcribed once and checked at 601.
       (f.enumlabel = t.enumlabel)
       or (f.enumlabel = 'pending' and t.enumlabel in ('active', 'cancelled'))
       or (f.enumlabel = 'active'  and t.enumlabel in ('frozen', 'cancelled', 'expired'))
       or (f.enumlabel = 'frozen'  and t.enumlabel in ('active', 'cancelled', 'expired'))
  from (select e.enumlabel, e.enumsortorder
          from pg_enum e join pg_type ty on ty.oid = e.enumtypid
         where ty.typname = 'membership_status') f
 cross join (select e.enumlabel, e.enumsortorder
          from pg_enum e join pg_type ty on ty.oid = e.enumtypid
         where ty.typname = 'membership_status') t;

update lc_pair
   set membership_id = ('22000000-0000-4000-8000-0000002440' || lpad(seq::text, 2, '0'))::uuid;

-- One member per pair, holding exactly one membership, so no attempt can be
-- refused by the live partial unique index instead of by the requirement.
insert into public.members (id, tenant_id, branch_id, full_name, phone)
select ('22000000-0000-4000-8000-0000002430' || lpad(p.seq::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240001'::uuid,
       '22000000-0000-4000-8000-000000240011'::uuid,
       'M24 pair ' || p.seq,
       '+91222430' || lpad(p.seq::text, 4, '0')
  from lc_pair p;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at)
select p.membership_id,
       '22000000-0000-4000-8000-000000240001'::uuid,
       ('22000000-0000-4000-8000-0000002430' || lpad(p.seq::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240061'::uuid,
       p.from_status,
       (select d from today_t24), (select d from today_t24), 100000,
       case when p.from_status = 'cancelled' then now() end
  from lc_pair p;

-- 600 — the enumeration's own guard. A sixth label added to this enum makes
-- this red rather than leaving twenty-five hand-numbered assertions quietly
-- covering thirty-six pairs.
select results_eq(
  $$ select count(*)::int,
            count(*) filter (where e.enumlabel::text in
              ('pending', 'active', 'frozen', 'expired', 'cancelled'))::int
       from pg_enum e join pg_type ty on ty.oid = e.enumtypid
      where ty.typname = 'membership_status' $$,
  $$ values (5, 5) $$,
  'membership_status has exactly the five labels this section enumerates — a sixth would make 601 disagree with 600 and this whole subsection would have to be revisited rather than silently covering fewer pairs than exist'
);

-- 601 — the transcription checked against the enumeration: twenty-five
-- ordered pairs, thirteen the requirement permits (three moves out of each of
-- `active` and `frozen`, two out of `pending`, and five self-writes) and
-- twelve it refuses.
select results_eq(
  $$ select count(*)::int,
            count(*) filter (where expected_allowed)::int,
            count(*) filter (where not expected_allowed)::int
       from lc_pair $$,
  $$ values (25, 13, 12) $$,
  'twenty-five ordered pairs enumerated from pg_enum, thirteen permitted by the requirement and twelve refused — the edge list transcribed above is checked here rather than trusted'
);

-- 602 — the trap disarmed, and the no-op ruled out, BEFORE anything is
-- attacked: every fixture really holds the status its pair names, and every
-- one of the twenty-five members holds exactly one membership, so nothing
-- below can be refused by memberships_tenant_id_member_id_live_key.
select results_eq(
  $$ select (select count(*)::int
               from lc_pair p join public.memberships m on m.id = p.membership_id
              where m.status = p.from_status),
            (select count(*)::int from public.memberships
              where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid),
            (select count(distinct member_id)::int from public.memberships
              where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid) $$,
  $$ values (25, 25, 25) $$,
  'all twenty-five fixtures exist and start at the status their pair names, one membership per member — so an attempt below that changes nothing changed nothing on a row that was really there, and no refusal can come from the live partial unique index'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- The driver. Asserts nothing itself (ADR-069: it does not begin with
-- `select` and is not counted); it records what an ordinary front-desk
-- session gets for each of the twenty-five pairs. The outcome is written to
-- `lc_pair` OUTSIDE the inner block, because an exception rolls the
-- subtransaction back and a row written inside it would vanish with the
-- failure it was recording.
do $do$
declare
  r        record;
  v_raised boolean;
  v_code   text;
begin
  for r in select * from lc_pair order by seq loop
    begin
      execute format('update public.memberships set status = %L where id = %L',
                     r.to_status, r.membership_id);
      v_raised := false;
      v_code   := null;
    exception when others then
      v_raised := true;
      v_code   := sqlstate;
    end;
    update lc_pair set raised = v_raised, code = v_code where seq = r.seq;
  end loop;
end
$do$;

set local role postgres;

update lc_pair p set final_status = m.status
  from public.memberships m
 where m.id = p.membership_id;

update lc_pair
   set verdict = case
     when not raised and final_status = to_status                 then 'allowed, landed'
     when not raised and final_status is distinct from to_status  then 'allowed, but did not land'
     when raised     and final_status = from_status               then 'refused, unchanged'
     else                                                              'refused, but the row moved'
   end;

-- 603-627 — one assertion per ordered pair, in `enumsortorder`. Each scores
-- BOTH halves of what the requirement demands: a refusal that raised and left
-- the status alone, or a permission that raised nothing and actually landed.

-- 603
select is((select verdict from lc_pair where from_status = 'pending' and to_status = 'pending'),
  'allowed, landed',
  'pending → pending: scenario "Writing a status back unchanged" — a status written back to itself changes nothing and is allowed');

-- 604
select is((select verdict from lc_pair where from_status = 'pending' and to_status = 'active'),
  'allowed, landed',
  'pending → active: allowed, and allowed for a hand-written statement and not only for the granting rule — which is why the granting rule needs no carve-out to activate a membership');

-- 605
select is((select verdict from lc_pair where from_status = 'pending' and to_status = 'frozen'),
  'refused, unchanged',
  'pending → frozen: REFUSED — a membership nobody has paid for is not a membership on pause. Lands today from an ordinary front-desk session');

-- 606
select is((select verdict from lc_pair where from_status = 'pending' and to_status = 'expired'),
  'refused, unchanged',
  'pending → expired: REFUSED — a membership that never started cannot lapse. Lands today');

-- 607
select is((select verdict from lc_pair where from_status = 'pending' and to_status = 'cancelled'),
  'allowed, landed',
  'pending → cancelled: allowed — a sale called off before the money arrives is a cancellation like any other');

-- 608
select is((select verdict from lc_pair where from_status = 'active' and to_status = 'pending'),
  'refused, unchanged',
  'active → pending: REFUSED — a live membership does not go back to waiting for its first payment. Lands today');

-- 609
select is((select verdict from lc_pair where from_status = 'active' and to_status = 'active'),
  'allowed, landed',
  'active → active: allowed — the self-write, and the shape app.grant_periods() writes on every renewal of a live membership');

-- 610
select is((select verdict from lc_pair where from_status = 'active' and to_status = 'frozen'),
  'allowed, landed',
  'active → frozen: scenario "Pausing and returning", first direction — allowed');

-- 611
select is((select verdict from lc_pair where from_status = 'active' and to_status = 'expired'),
  'allowed, landed',
  'active → expired: allowed. Retiring a live membership early is not the defect — `expired` is legal to write and the product simply never writes it (ADR-064/075), which are not in conflict once stated plainly');

-- 612
select is((select verdict from lc_pair where from_status = 'active' and to_status = 'cancelled'),
  'allowed, landed',
  'active → cancelled: scenario "Retiring a live membership" — allowed, and it is half the repair this codebase prescribes for every mis-sold membership');

-- 613
select is((select verdict from lc_pair where from_status = 'frozen' and to_status = 'pending'),
  'refused, unchanged',
  'frozen → pending: REFUSED — a paused membership does not go back to waiting for its first payment. Lands today');

-- 614
select is((select verdict from lc_pair where from_status = 'frozen' and to_status = 'active'),
  'allowed, landed',
  'frozen → active: scenario "Pausing and returning", the other direction — allowed');

-- 615
select is((select verdict from lc_pair where from_status = 'frozen' and to_status = 'frozen'),
  'allowed, landed',
  'frozen → frozen: allowed — the self-write, and the shape app.grant_periods() writes when a paused member renews');

-- 616
select is((select verdict from lc_pair where from_status = 'frozen' and to_status = 'expired'),
  'allowed, landed',
  'frozen → expired: allowed — a paused membership can run out of time like any other');

-- 617
select is((select verdict from lc_pair where from_status = 'frozen' and to_status = 'cancelled'),
  'allowed, landed',
  'frozen → cancelled: allowed — a member who paused and then left is cancelled from where they are');

-- 618
select is((select verdict from lc_pair where from_status = 'expired' and to_status = 'pending'),
  'refused, unchanged',
  'expired → pending: scenario "Reviving a retired membership" — REFUSED. Lands today');

-- 619
select is((select verdict from lc_pair where from_status = 'expired' and to_status = 'active'),
  'refused, unchanged',
  'expired → active: scenario "Reviving a retired membership" — REFUSED. This is the harm the whole requirement names, on the terminal status the product itself never writes and therefore nobody would notice being left out');

-- 620
select is((select verdict from lc_pair where from_status = 'expired' and to_status = 'frozen'),
  'refused, unchanged',
  'expired → frozen: REFUSED — pausing a lapsed membership is reviving it under another name, and a rule that closes `active` and leaves `frozen` open has closed nothing. Lands today');

-- 621
select is((select verdict from lc_pair where from_status = 'expired' and to_status = 'expired'),
  'allowed, landed',
  'expired → expired: ALLOWED. The requirement''s "refuse every change OUT OF expired and cancelled" and its "a status written back to itself is allowed" meet here, and the prose settles it: a self-write is not a change out of anything and cannot do the harm. See the report — the first scenario''s wording ("changes a cancelled or expired membership''s status") overlaps the fifth''s and this is the reading taken');

-- 622
select is((select verdict from lc_pair where from_status = 'expired' and to_status = 'cancelled'),
  'refused, unchanged',
  'expired → cancelled: REFUSED — terminal is terminal in both directions, and relabelling one retirement as the other rewrites why a membership ended. Lands today');

-- 623
select is((select verdict from lc_pair where from_status = 'cancelled' and to_status = 'pending'),
  'refused, unchanged',
  'cancelled → pending: scenario "Reviving a retired membership" — REFUSED. Lands today');

-- 624
select is((select verdict from lc_pair where from_status = 'cancelled' and to_status = 'active'),
  'refused, unchanged',
  'cancelled → active: THE MEASURED DEFECT, from an ordinary front-desk session in one statement. REFUSED, and the status unchanged');

-- 625
select is((select verdict from lc_pair where from_status = 'cancelled' and to_status = 'frozen'),
  'refused, unchanged',
  'cancelled → frozen: REFUSED — the same revival routed through the status a fix aimed at `active` alone would miss. Lands today');

-- 626
select is((select verdict from lc_pair where from_status = 'cancelled' and to_status = 'expired'),
  'refused, unchanged',
  'cancelled → expired: REFUSED — a cancellation is not relabelled as a lapse afterwards. Lands today');

-- 627
select is((select verdict from lc_pair where from_status = 'cancelled' and to_status = 'cancelled'),
  'allowed, landed',
  'cancelled → cancelled: ALLOWED — the self-write again, and the one that matters most in practice: an ordinary column-listing UPDATE that carries `status` alongside a note must not be refused just because the membership is retired');

-- 628 — one rule, stated once, and not one of the three false-green routes.
-- A CHECK constraint cannot see OLD, a policy refusal is 42501 and a unique
-- index is 23505; a transition refused by any of those was refused for
-- something other than being a transition.
select results_eq(
  $$ select count(distinct code)::int,
            bool_or(code in ('23505', '42501', '23514'))
       from lc_pair where not expected_allowed $$,
  $$ values (1, false) $$,
  'all twelve refusals report the SAME SQLSTATE as each other — one transition rule, stated once — and it is none of 23505 (the live partial unique index), 42501 (a policy filtering the row away) or 23514 (a CHECK, which cannot see OLD and so cannot be judging a transition at all). No specific code is pinned: this requirement names none'
);


-- ---------------------------------------------------------------------------
-- 29b — THE TRANSITIONS THAT MUST STILL WORK (629-644), ASSERTED AS HARD AS
-- THE REFUSALS.
--
-- 633 and 635 are the two that would fail loudest and latest. `app.grant_
-- periods()` writes `status = case when m.status = 'pending' … else m.status
-- end` on EVERY grant, so every renewal of a live membership writes the
-- status back to itself from inside a trigger. A rule written as "refuse any
-- UPDATE that names status" passes every assertion in 29a and breaks every
-- renewal in the product.
--
-- 629 is the other end of the same function: a `pending` membership with no
-- dates at all is how a membership is created before its first payment, and
-- the granting rule sets its dates, its count, its `activated_at` AND its
-- status in one statement. A rule that judges the transition without seeing
-- that the dates arrive in the same write would refuse the one activation the
-- product actually performs.
--
-- 644 IS A FINDING, NOT A REFUSAL THIS REQUIREMENT ASKS FOR. The requirement
-- says `pending → cancelled` SHALL be allowed, and 607 proves it for a DATED
-- pending membership. For a DATELESS one it is refused today by
-- memberships_dated_unless_pending_chk (`status = 'pending' OR (starts_on IS
-- NOT NULL AND ends_on IS NOT NULL)`), measured against Cloud: 23514, from
-- the front desk, on the exact shape ADR-089 says a membership has before its
-- first payment. That is an interaction the requirement does not answer, so
-- it is asserted as what it IS — an existing CHECK, by its own code — rather
-- than folded into the transition rule. See the report.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000240041'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Pending Dateless', '+912224000041'),
  ('22000000-0000-4000-8000-000000240042'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Renew Active', '+912224000042'),
  ('22000000-0000-4000-8000-000000240043'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Renew Frozen', '+912224000043'),
  ('22000000-0000-4000-8000-000000240044'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Pending Dated', '+912224000044'),
  ('22000000-0000-4000-8000-000000240045'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Pause Return', '+912224000045'),
  ('22000000-0000-4000-8000-000000240046'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Expire', '+912224000046'),
  ('22000000-0000-4000-8000-000000240047'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Dateless Cancel', '+912224000047');

-- Every dated membership starts at `ends_on = today`, so one granted period is
-- exactly `today + 30` and nothing else is in the arithmetic (ADR-039).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000240081'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240041'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'pending', null, null, 100000),
  ('22000000-0000-4000-8000-000000240082'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240042'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24), (select d from today_t24), 100000),
  ('22000000-0000-4000-8000-000000240083'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240043'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'frozen', (select d from today_t24), (select d from today_t24), 100000),
  ('22000000-0000-4000-8000-000000240084'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240044'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'pending', (select d from today_t24), (select d from today_t24), 100000),
  ('22000000-0000-4000-8000-000000240085'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240045'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24), (select d from today_t24), 100000),
  ('22000000-0000-4000-8000-000000240086'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240046'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24), (select d from today_t24), 100000),
  ('22000000-0000-4000-8000-000000240087'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240047'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'pending', null, null, 100000);

-- 240085's period is BOUGHT rather than typed (GL044), so that 639 and 641 are
-- measuring an ordinary paused-and-cancelled membership that money has already
-- reached, not an empty one.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, receipt_number, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000241005'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240045'::uuid, '22000000-0000-4000-8000-000000240085'::uuid,
   100000, 'INR', 'paid', 'cash', 'T24-RCT-05', '22000000-0000-4000-8000-000000240021'::uuid);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 629
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000241001'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-000000240041'::uuid, '22000000-0000-4000-8000-000000240081'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'scenario "Activating on the first payment" — the granting rule activates a DATELESS pending membership, which is how a membership created before its first payment comes alive (ADR-089). The dates, the count, the activation stamp and the status all arrive in one statement');

set local role postgres;

-- 630
select results_eq(
  $$ select status, starts_on, ends_on, periods_granted, activated_at is not null
       from public.memberships where id = '22000000-0000-4000-8000-000000240081'::uuid $$,
  $$ select 'active'::public.membership_status, (select d from today_t24), (select d from today_t24) + 30, 1, true $$,
  'and it LANDED: active, thirty days from today, one period, and stamped as activated — the transition rule did not stop the one activation this product actually performs'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 631
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000241004'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-000000240044'::uuid, '22000000-0000-4000-8000-000000240084'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'scenario "Activating on the first payment", the DATED pending membership — the other branch of the granting rule, which extends an existing end date rather than writing the first one');

set local role postgres;

-- 632
select results_eq(
  $$ select status, ends_on, periods_granted, activated_at is not null
       from public.memberships where id = '22000000-0000-4000-8000-000000240084'::uuid $$,
  $$ select 'active'::public.membership_status, (select d from today_t24) + 30, 1, true $$,
  'and it LANDED too: active, thirty days on, one period, activated'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 633 — THE ASSERTION A RULE WRITTEN AS "REFUSE ANY UPDATE THAT NAMES STATUS"
-- FAILS. app.grant_periods() writes `status = m.status` on every grant against
-- a membership that is not pending, so this ordinary renewal writes `active`
-- onto `active` from inside a trigger.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000241002'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-000000240042'::uuid, '22000000-0000-4000-8000-000000240082'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'an ordinary renewal of an ACTIVE membership still works — and it is the self-write the granting rule performs on every grant, which is why the self-write had to be permitted rather than merely tolerated');

set local role postgres;

-- 634
select results_eq(
  $$ select status, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000240082'::uuid $$,
  $$ select 'active'::public.membership_status, (select d from today_t24) + 30, 1 $$,
  'and the renewal EXTENDED it — still active, thirty days bought. A rule that refused the self-write would leave this membership unextended with the money already taken'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 635
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000241003'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-000000240043'::uuid, '22000000-0000-4000-8000-000000240083'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'and a renewal of a FROZEN membership works too — `frozen` is a paused live membership whose member is coming back, and the granting rule writes `frozen` onto `frozen` for it');

set local role postgres;

-- 636
select results_eq(
  $$ select status, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000240083'::uuid $$,
  $$ select 'frozen'::public.membership_status, (select d from today_t24) + 30, 1 $$,
  'and it extended without unfreezing itself — paying while paused buys days, it does not decide the member is back'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 637
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-000000240085'::uuid
$$, 'scenario "Pausing and returning" on a paid-up membership from the desk — the freeze');

-- 638
select lives_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-000000240085'::uuid
$$, 'and the return');

set local role postgres;

-- 639
select results_eq(
  $$ select status, ends_on, periods_granted, price_paise from public.memberships
      where id = '22000000-0000-4000-8000-000000240085'::uuid $$,
  $$ select 'active'::public.membership_status, (select d from today_t24) + 30, 1, 100000::bigint $$,
  'and both LANDED and nothing else moved — a pause and a return are a round trip, not an event that rewrites what the member bought'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 640
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member left'
   where id = '22000000-0000-4000-8000-000000240085'::uuid
$$, 'scenario "Retiring a live membership" — cancelling a paid-up membership from the desk is allowed, and it is half the repair this codebase prescribes for every mis-sale');

-- 641
select results_eq(
  $$ select status, periods_granted, price_paise, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000240085'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 1, 100000::bigint, (select d from today_t24) + 30 $$,
  'and it landed with the terms it was sold on still on the row — a cancellation records that a membership ended, it does not erase what it was'
);

-- 642
select lives_ok($$
  update public.memberships set status = 'expired'
   where id = '22000000-0000-4000-8000-000000240086'::uuid
$$, 'writing `expired` onto a live membership is LEGAL — the requirement says so plainly, and says equally plainly that the product never does it. The transition being available and the product not using it are not in conflict');

set local role postgres;

-- 643
select results_eq(
  $$ select status, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-000000240086'::uuid $$,
  $$ select 'expired'::public.membership_status, (select d from today_t24), (select d from today_t24) $$,
  'and it landed without moving the dates — because no rule may read `expired` as the DEFINITION of lapsed; the dates remain that (ADR-064/075)'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 644 — a finding, asserted as what it is. GREEN today and required to stay
-- green: the code is pinned because the POINT is which rule answers.
select throws_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now()
   where id = '22000000-0000-4000-8000-000000240087'::uuid
$$, '23514'::char(5), null,
  'a DATELESS pending membership cannot be cancelled by hand at all — memberships_dated_unless_pending_chk refuses it, not this requirement. 607 shows `pending → cancelled` is permitted for a DATED one; for the shape a membership actually has before its first payment it is refused today by a CHECK about dates. Reported as an interaction this requirement does not answer, not resolved here by guessing');


-- ---------------------------------------------------------------------------
-- 29c — STATEMENT SHAPES (645-662).
--
-- ADR-087's list, on the status column this time. A rule written as a
-- single-row guard against `update … set status = … where id = …` is the
-- shape this project has shipped before; every one of these was measured
-- landing today from an ordinary front-desk session, including the MERGE and
-- the upsert.
--
-- 652 IS THE SHARPEST. One statement writing two rows, one transition legal
-- and one not: the statement must be refused whole and the LEGAL row must not
-- land either. A rule enforced per statement rather than per row cannot pass
-- 650 and 652 together, and a rule that refuses the illegal row while quietly
-- letting the legal one through has invented a partial statement.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select ('22000000-0000-4000-8000-00000024c0' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240001'::uuid,
       '22000000-0000-4000-8000-000000240011'::uuid,
       'M24 shape ' || i, '+91222400' || lpad((1000 + i)::text, 4, '0')
  from generate_series(1, 10) i;

-- c101, c103, c105 and c107 are RETIRED — one per attacking shape, so no shape
-- can pass on another shape's row. Everything else is live: c102 (the MERGE
-- that must still work), c104 and c106 (the two-row UPDATE … FROM), c108 (the
-- legal half of the mixed statement) and c109/c110 (the two-in-one-transaction
-- pair, which must START live or 656 measures nothing).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at)
select ('22000000-0000-4000-8000-00000024c1' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240001'::uuid,
       ('22000000-0000-4000-8000-00000024c0' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240061'::uuid,
       case when i in (1, 3, 5, 7) then 'cancelled'::public.membership_status
                                   else 'active'::public.membership_status end,
       (select d from today_t24), (select d from today_t24), 100000,
       case when i in (1, 3, 5, 7) then now() end
  from generate_series(1, 10) i;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 645
select throws_ok($$
  merge into public.memberships m
   using (select '22000000-0000-4000-8000-00000024c101'::uuid as id) s
      on m.id = s.id
    when matched then update set status = 'active'
$$, null::char(5), null,
  'MERGE reviving a cancelled membership is refused — measured landing today from the front desk, which is why the shape is here at all');

set local role postgres;

-- 646
select results_eq(
  $$ select status from public.memberships where id = '22000000-0000-4000-8000-00000024c101'::uuid $$,
  $$ values ('cancelled'::public.membership_status) $$,
  'and the row is still cancelled — refused AND unchanged, which are two facts and not one'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 647
select lives_ok($$
  merge into public.memberships m
   using (select '22000000-0000-4000-8000-00000024c102'::uuid as id) s
      on m.id = s.id
    when matched then update set status = 'cancelled', cancelled_at = now()
$$, 'and the SAME shape retiring a live membership is allowed — the shape is not the thing being refused');

-- 648
select lives_ok($$
  update public.memberships m set status = v.s
    from (values ('22000000-0000-4000-8000-00000024c104'::uuid, 'frozen'::public.membership_status),
                 ('22000000-0000-4000-8000-00000024c106'::uuid, 'cancelled'::public.membership_status)) as v(id, s)
   where m.id = v.id
$$, 'UPDATE … FROM writing a DIFFERENT status to each of two rows, both transitions legal — allowed');

set local role postgres;

-- 649
select results_eq(
  $$ select status from public.memberships
      where id in ('22000000-0000-4000-8000-00000024c102'::uuid,
                   '22000000-0000-4000-8000-00000024c104'::uuid,
                   '22000000-0000-4000-8000-00000024c106'::uuid)
      order by id $$,
  $$ values ('cancelled'::public.membership_status),
            ('frozen'::public.membership_status),
            ('cancelled'::public.membership_status) $$,
  'and all three landed — the MERGE cancellation and both halves of the two-row UPDATE. A rule that answered the shapes by refusing them is red here rather than green everywhere'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 650
select throws_ok($$
  update public.memberships m set status = v.s
    from (values ('22000000-0000-4000-8000-00000024c108'::uuid, 'cancelled'::public.membership_status),
                 ('22000000-0000-4000-8000-00000024c103'::uuid, 'active'::public.membership_status)) as v(id, s)
   where m.id = v.id
$$, null::char(5), null,
  'one statement, two rows, one transition legal and one not — the statement is refused');

set local role postgres;

-- 651
select results_eq(
  $$ select status from public.memberships
      where id in ('22000000-0000-4000-8000-00000024c103'::uuid,
                   '22000000-0000-4000-8000-00000024c108'::uuid)
      order by id $$,
  $$ values ('cancelled'::public.membership_status),
            ('active'::public.membership_status) $$,
  'and NEITHER row moved — not the illegal revival and not the legal cancellation beside it. A statement is refused whole; a rule that lets the legal half through has invented a partial statement nobody asked for'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 652
select throws_ok($$
  with revived as (
    update public.memberships set status = 'active'
     where id = '22000000-0000-4000-8000-00000024c105'::uuid
    returning id
  )
  select count(*) from revived
$$, null::char(5), null,
  'a data-modifying CTE reviving a cancelled membership is refused — the write is inside a CTE and the rule still sees it');

set local role postgres;

-- 653
select results_eq(
  $$ select status from public.memberships where id = '22000000-0000-4000-8000-00000024c105'::uuid $$,
  $$ values ('cancelled'::public.membership_status) $$,
  'and that row is still cancelled'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 654
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-00000024c107'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024c007'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
          'active', (select d from today_t24), (select d from today_t24), 100000)
  on conflict (id) do update set status = 'active'
$$, null::char(5), null,
  'INSERT … ON CONFLICT DO UPDATE reviving a cancelled membership is refused — an upsert whose UPDATE branch fires is an update, and this one lands today');

set local role postgres;

-- 655
select results_eq(
  $$ select (select status from public.memberships where id = '22000000-0000-4000-8000-00000024c107'::uuid),
            (select count(*)::int from public.memberships
              where member_id = '22000000-0000-4000-8000-00000024c007'::uuid) $$,
  $$ select 'cancelled'::public.membership_status, 1 $$,
  'and the row is still cancelled and no second membership was created beside it — the refusal is of the transition, not of the insert'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 656 / 657 — two transitions in one transaction, both legal. The whole file
-- is one transaction (ADR-030), so these two statements are exactly that.
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-00000024c109'::uuid
$$, 'two transitions in one transaction, step one: active → frozen');

-- 657
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now()
   where id = '22000000-0000-4000-8000-00000024c109'::uuid
$$, 'step two, in the same transaction: frozen → cancelled. A rule that judged against the status the row had when the transaction opened would refuse this one');

set local role postgres;

-- 658
select results_eq(
  $$ select status from public.memberships where id = '22000000-0000-4000-8000-00000024c109'::uuid $$,
  $$ values ('cancelled'::public.membership_status) $$,
  'and both landed — the second transition was judged against what the first one wrote, not against what the row held before the transaction began'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 659
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now()
   where id = '22000000-0000-4000-8000-00000024c110'::uuid
$$, 'and the other direction of the same worry, step one: active → cancelled, allowed');

-- 660
select throws_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-00000024c110'::uuid
$$, null::char(5), null,
  'step two, in the SAME transaction that cancelled it: the revival is refused. Terminal is terminal within a transaction as well as across one — the critic''s measured exploit was one session doing exactly this');

set local role postgres;

-- 661
select results_eq(
  $$ select status from public.memberships where id = '22000000-0000-4000-8000-00000024c110'::uuid $$,
  $$ values ('cancelled'::public.membership_status) $$,
  'and the cancellation stands'
);

-- 662 — the whole subsection in one comparison, so no shape can pass by
-- another shape's row. Odd rows were cancelled at the start and must be
-- cancelled still except c109/c110, which Part 656-661 retired legally.
select results_eq(
  $$ select count(*)::int
       from public.memberships
      where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid
        and id in ('22000000-0000-4000-8000-00000024c101'::uuid,
                   '22000000-0000-4000-8000-00000024c103'::uuid,
                   '22000000-0000-4000-8000-00000024c105'::uuid,
                   '22000000-0000-4000-8000-00000024c107'::uuid)
        and status = 'cancelled'::public.membership_status $$,
  $$ values (4) $$,
  'and all four retired memberships this subsection attacked — through MERGE, through a two-row UPDATE … FROM, through a data-modifying CTE and through an upsert — are still retired. Four shapes, one answer'
);


-- ---------------------------------------------------------------------------
-- 29d — ROLES (663-669), AND THE TRUSTED-CONTEXT LINE THIS AUTHOR READ.
--
-- ADR-082 draws the line between a rule that JUDGES A CLAIM — which must not
-- be asked of a session that carries none — and a rule that is an INVARIANT
-- ABOUT THE DATA, which takes no carve-out. `app.enforce_payment()` splits
-- itself on exactly that line, with the money invariants above
-- `row_security_active()` and the claim rules below it, and Section 27's own
-- `service_role` assertion says it in as many words.
--
-- A transition table is the second kind. Which status may follow which is a
-- fact about the row; asking it does not require knowing who is asking. So
-- every session is bound: the front desk (already 624), a gym admin, a super
-- admin writing across tenants through memberships_platform_write,
-- `service_role` — which has no row security at all — and `postgres`, which
-- is what migrations and the seed run as.
--
-- THIS IS A READING AND IT IS STATED SO IT CAN BE OVERRULED. If the
-- coordinator decides a trusted context may repair a mis-cancelled membership
-- by hand, 665 and 666 are the two assertions that change, and changing them
-- is a `spec:` commit. Nothing in the product needs the carve-out today:
-- supabase/seed-scenarios.sql INSERTS `expired` and `cancelled` memberships
-- and transitions none, and this requirement governs a status that CHANGES.
--
-- 668-669 are the control. A rule that answered "which role may write status"
-- by refusing every role would pass 663-667 and break the product; a gym
-- admin cancelling a live membership must still work.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select ('22000000-0000-4000-8000-00000024d0' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240001'::uuid,
       '22000000-0000-4000-8000-000000240011'::uuid,
       'M24 role ' || i, '+91222400' || lpad((2000 + i)::text, 4, '0')
  from generate_series(1, 5) i;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at)
select ('22000000-0000-4000-8000-00000024d1' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240001'::uuid,
       ('22000000-0000-4000-8000-00000024d0' || lpad(i::text, 2, '0'))::uuid,
       '22000000-0000-4000-8000-000000240061'::uuid,
       case when i = 5 then 'active'::public.membership_status
                       else 'cancelled'::public.membership_status end,
       (select d from today_t24), (select d from today_t24), 100000,
       case when i < 5 then now() end
  from generate_series(1, 5) i;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000240022')::text,
  true);
set local role authenticated;

-- 663
select throws_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-00000024d101'::uuid
$$, null::char(5), null,
  'a GYM ADMIN reviving a retired membership is refused — seniority is not the question this rule answers');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true);

-- 664
select throws_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-00000024d102'::uuid
$$, null::char(5), null,
  'a SUPER ADMIN writing across tenants through memberships_platform_write is refused too — the platform policy decides which rows they may write, not what those rows may become');

set local role service_role;

-- 665
select throws_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-00000024d103'::uuid
$$, null::char(5), null,
  'and SERVICE_ROLE — no row security at all — is refused as well. This is an invariant about the data, not a question about the caller''s role, so on ADR-082''s own line it takes no trusted-context carve-out. Stated as a reading: see the section header');

set local role postgres;

-- 666
select throws_ok($$
  update public.memberships set status = 'pending'
   where id = '22000000-0000-4000-8000-00000024d104'::uuid
$$, null::char(5), null,
  'and POSTGRES, which is what a migration and the seed run as, is refused too. Nothing in the product needs the exemption: the seed INSERTS retired memberships and transitions none');

-- 667
select results_eq(
  $$ select count(*)::int from public.memberships
      where id in ('22000000-0000-4000-8000-00000024d101'::uuid,
                   '22000000-0000-4000-8000-00000024d102'::uuid,
                   '22000000-0000-4000-8000-00000024d103'::uuid,
                   '22000000-0000-4000-8000-00000024d104'::uuid)
        and status = 'cancelled'::public.membership_status $$,
  $$ values (4) $$,
  'and all four are still cancelled — four sessions, four refusals, four rows that did not move'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000240022')::text,
  true);
set local role authenticated;

-- 668
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member moved cities'
   where id = '22000000-0000-4000-8000-00000024d105'::uuid
$$, 'and the ordinary work every one of those roles legitimately does is untouched: a gym admin retires a live membership');

set local role postgres;

-- 669
select results_eq(
  $$ select status from public.memberships where id = '22000000-0000-4000-8000-00000024d105'::uuid $$,
  $$ values ('cancelled'::public.membership_status) $$,
  'and it landed — a rule that answered "which role may write status" by refusing everybody would pass 663-667 and break the product'
);


-- ---------------------------------------------------------------------------
-- 29e — THE GATE (670-677). ADR-084 reads this column.
--
-- The point of retiring a membership is that its member stops getting in, and
-- the point of freezing one is that they do not. Both are asserted from the
-- QR path, which is the only branch of app.enforce_check_in() where the live
-- membership is checked at all (the assisted front-desk path has never
-- required a membership — Section 23 makes the same note). 677 counts what
-- actually landed, so neither direction can pass by the gate having refused
-- everybody.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-00000024e001'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Gate Cancel', '+912224003001'),
  ('22000000-0000-4000-8000-00000024e002'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Gate Freeze', '+912224003002'),
  ('22000000-0000-4000-8000-00000024e003'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Gate Expire', '+912224003003');

-- Dated so today is INSIDE the term on every one of them: a refusal below can
-- then only be about the status, never about the dates having run out.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-00000024e101'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024e001'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24) - 1, (select d from today_t24) + 30, 100000),
  ('22000000-0000-4000-8000-00000024e102'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024e002'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24) - 1, (select d from today_t24) + 30, 100000),
  ('22000000-0000-4000-8000-00000024e103'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024e003'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24) - 1, (select d from today_t24) + 30, 100000);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at) values
  ('22000000-0000-4000-8000-00000024e201'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'pay22-t24-gate-1', now() - interval '1 minute', now() + interval '2 hours'),
  ('22000000-0000-4000-8000-00000024e202'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'pay22-t24-gate-2', now() - interval '1 minute', now() + interval '2 hours'),
  ('22000000-0000-4000-8000-00000024e203'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'pay22-t24-gate-3', now() - interval '1 minute', now() + interval '2 hours'),
  ('22000000-0000-4000-8000-00000024e204'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'pay22-t24-gate-4', now() - interval '1 minute', now() + interval '2 hours');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 670
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000240001'::uuid, '22000000-0000-4000-8000-000000240011'::uuid,
          '22000000-0000-4000-8000-00000024e001'::uuid, 'qr', '22000000-0000-4000-8000-00000024e201'::uuid)
$$, 'the gate, before: a live membership with today inside its dates admits its member');

-- 671
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now()
   where id = '22000000-0000-4000-8000-00000024e101'::uuid
$$, 'the desk retires it — a legal transition');

-- 672
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000240001'::uuid, '22000000-0000-4000-8000-000000240011'::uuid,
          '22000000-0000-4000-8000-00000024e001'::uuid, 'qr', '22000000-0000-4000-8000-00000024e202'::uuid)
$$, 'GL013'::char(5), null,
  'and the same member is now refused at the gate, by the gate — GL013, with the dates untouched and thirty days still on the clock. A membership retired by a legal transition stops admitting its member, which is the entire point of retiring it');

-- 673
select lives_ok($$
  update public.memberships set status = 'frozen'
   where id = '22000000-0000-4000-8000-00000024e102'::uuid
$$, 'the desk PAUSES another one — also a legal transition, and a different thing');

-- 674
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000240001'::uuid, '22000000-0000-4000-8000-000000240011'::uuid,
          '22000000-0000-4000-8000-00000024e002'::uuid, 'qr', '22000000-0000-4000-8000-00000024e203'::uuid)
$$, 'and that member is still admitted — a freeze is a pause, not a retirement, and the gate reads it that way. Without this, "retired stops admitting" would be satisfied by a gate that refused everybody');

-- 675
select lives_ok($$
  update public.memberships set status = 'expired'
   where id = '22000000-0000-4000-8000-00000024e103'::uuid
$$, 'and the desk writes `expired` onto the third — legal, and the status the product itself never writes');

-- 676
select throws_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000240001'::uuid, '22000000-0000-4000-8000-000000240011'::uuid,
          '22000000-0000-4000-8000-00000024e003'::uuid, 'qr', '22000000-0000-4000-8000-00000024e204'::uuid)
$$, 'GL013'::char(5), null,
  'and that member is refused too — both terminal statuses close the gate, not just the one the console can reach');

set local role postgres;

-- 677
select results_eq(
  $$ select count(*)::int from public.attendance
      where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid $$,
  $$ values (2) $$,
  'and exactly two check-ins landed in this gym — the live one and the paused one, and neither of the two refusals. The gate refused what it should and admitted what it should, which one assertion of either kind alone cannot show'
);


-- ===========================================================================
-- SECTION 30 (ROUND EIGHTEEN, OPEN-030) — "Money paid against a retired
-- membership is refundable, not strandable." Tenant 24. Assertions 678-692.
--
-- WHY THIS REQUIREMENT EXISTS, AND WHY THIS SECTION IS SHORT. ADR-096 decided
-- that money paid against a retired membership stays on record BECAUSE the
-- membership might be revived and the total would then count it. Section 29
-- makes that revival unreachable, so the reasoning expires and the answer has
-- to be stated rather than implied: the payment is a complete, refundable
-- record, and the remedy is to refund it and take it against a live
-- membership.
--
-- Section 23 (446-493) already asserts most of the first half against a
-- membership cancelled from `active`: recorded, receipted, stamped,
-- attributed, not extending, refundable, and counted by GL036's ceiling. This
-- section does not restate those. It asserts the three things Section 23 does
-- not:
--
--   * the retirement route Section 23 does not walk — `frozen → cancelled`,
--     now that both retirements go through a rule;
--   * THE HARM CHECK ACROSS THE TWO REQUIREMENTS. Requirement 1 names one
--     harm: coming back out of a terminal state. Requirement 2 permits a
--     payment against a retired membership. So the question that has to be
--     asked out loud is whether the payment is a second route to the harm the
--     first requirement forbids — and 682, 689 and 692 answer it at each of
--     the three moments money touches the row: when the payment lands, when
--     it is refunded, and when the payment's own status moves to `refunded`;
--   * THE MONEY ACTUALLY COMING BACK OUT. Section 23's refund is recorded and
--     left at `requested`. "Refundable in full" is a promise about money
--     leaving, so 685-687 walk it to `completed`, pin GL036 at the ceiling
--     (the requirement's own scenario names that code, which is why it is the
--     one SQLSTATE pinned here) and assert the ledger: the completed refund
--     equals the payment, and no payment in this gym carries a non-failed
--     refund total above its own amount.
--
-- Nothing in this section is red today. It is the half of the change that a
-- correct implementation must not break, and it is here because a rule that
-- closed the revival by refusing the payment instead would pass every
-- assertion in Section 29.
-- ===========================================================================

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-00000024f001'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Stranded', '+912224004001');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-00000024f101'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024f001'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'frozen', (select d from today_t24), (select d from today_t24), 100000);

-- The gym's receipt counter before the payment at 679, so 681 can assert that
-- payment took EXACTLY one number. Summed across the tenant's counters rather
-- than read from one financial-year row, the same way Section 23 does it.
create temp table dc24_before as
  select coalesce(sum(next_number), 0)::int as n
    from public.document_counters
   where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid and kind = 'receipt';

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 678
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'mis-sold while paused'
   where id = '22000000-0000-4000-8000-00000024f101'::uuid
$$, 'the retirement route Section 23 does not walk: a PAUSED membership is cancelled. Both retirements now go through one rule and both have to reach the same place');

set local role postgres;

-- The live membership this member also holds, sold after the retirement so the
-- live partial unique index is satisfied by construction. Inserted rather than
-- asserted: creation is not what this requirement governs.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-00000024f102'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024f001'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24), (select d from today_t24), 100000);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 679
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000024f201'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f001'::uuid, '22000000-0000-4000-8000-00000024f101'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'scenario "Paying against a retired membership" — the payment is RECORDED, not refused. A manual payment is cash already in the drawer before any row is written, and refusing it leaves the gym holding money with nothing to show for it');

set local role postgres;

-- 680
select results_eq(
  $$ select status, receipt_number is not null, paid_at is not null, recorded_by_staff_id
       from public.payments where id = '22000000-0000-4000-8000-00000024f201'::uuid $$,
  $$ select 'paid'::public.payment_status, true, true, '22000000-0000-4000-8000-000000240021'::uuid $$,
  'and it is a FULL payment: paid, receipted, stamped and attributed. A rule that answered this requirement by quietly refusing the payment would be a different rule and a worse one'
);

-- 681
select is(
  (select coalesce(sum(next_number), 0)::int from public.document_counters
    where tenant_id = '22000000-0000-4000-8000-000000240001'::uuid and kind = 'receipt'),
  (select n from dc24_before) + 1,
  'and the receipt came off the gym''s own counter and moved it by exactly one — money the gym actually took is counted in the receipt book like any other'
);

-- 682 — THE HARM CHECK, first of three. Requirement 1 names one harm: coming
-- back out of a terminal state. Requirement 2 permits money to land on a
-- terminal row. This is where those two meet.
select results_eq(
  $$ select status, periods_granted, starts_on, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000024f101'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t24), (select d from today_t24) $$,
  'and the retired membership did not move — not its dates, not its count, and NOT ITS STATUS. Money is not a second route out of a terminal state, which is the one outcome the requirement above names as the harm'
);

-- 683
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000024f102'::uuid $$,
  $$ select 'active'::public.membership_status, 0, (select d from today_t24) $$,
  'and the LIVE membership the same member also holds did not move either — the money named the retired row, so the answer is "do not extend", not "extend something else"'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000240022')::text,
  true);
set local role authenticated;

-- 684
select lives_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-00000024f301'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f201'::uuid, 'refund', 100000, 'INR',
          'paid against the retired membership; giving it back',
          '22000000-0000-4000-8000-000000240022'::uuid)
$$, 'scenario "Getting that money back" — a refund for the FULL amount is allowed, which is the only honest remedy for money that can now never be granted');

-- 685
select lives_ok($$
  update public.refunds set status = 'completed'
   where id = '22000000-0000-4000-8000-00000024f301'::uuid
$$, 'and it reaches `completed` — "refundable in full" is a promise about money LEAVING, not about a row being written, and Section 23 leaves its refund at `requested`');

-- 686
select throws_ok($$
  insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
  values ('22000000-0000-4000-8000-00000024f302'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f201'::uuid, 'refund', 1, 'INR',
          'one paisa past the ceiling',
          '22000000-0000-4000-8000-000000240022'::uuid)
$$, 'GL036'::char(5), null,
  'and one paisa more is refused by GL036 — the requirement''s own scenario names that code, which is why it is the one SQLSTATE this section pins. The payment is bounded by what was taken, exactly like any other');

set local role postgres;

-- 687
select results_eq(
  $$ select
       (select coalesce(sum(r.amount_paise), 0)::bigint from public.refunds r
         where r.payment_id = '22000000-0000-4000-8000-00000024f201'::uuid
           and r.status = 'completed'::public.refund_status),
       (select p.amount_paise from public.payments p
         where p.id = '22000000-0000-4000-8000-00000024f201'::uuid),
       (select count(*)::int from public.payments p
         where p.tenant_id = '22000000-0000-4000-8000-000000240001'::uuid
           and (select coalesce(sum(r.amount_paise), 0) from public.refunds r
                 where r.payment_id = p.id and r.status <> 'failed'::public.refund_status) > p.amount_paise) $$,
  $$ select 100000::bigint, 100000::bigint, 0 $$,
  'and THE MONEY IS BACK OUT: the completed refund equals the payment to the paisa, and no payment in this gym carries a non-failed refund total above its own amount. That is the difference between money that is refundable and money that is stranded'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'gym_owner',
                    'staff_id', '22000000-0000-4000-8000-000000240022')::text,
  true);
set local role authenticated;

-- 688
select lives_ok($$
  update public.payments set status = 'refunded'
   where id = '22000000-0000-4000-8000-00000024f201'::uuid
$$, 'and the payment itself moves paid → refunded, which is the payment state machine''s own business and still works against a retired membership');

set local role postgres;

-- 689 — the harm check, second of three: the payment's own status moving is
-- the moment app.grant_periods() runs again, because `refunded` is one of the
-- three statuses its sum counts.
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000024f101'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0, (select d from today_t24) $$,
  'and the retired membership STILL has not moved — walking the payment''s own status is not a route out of a terminal state either'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 690
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000024f202'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f001'::uuid, '22000000-0000-4000-8000-00000024f102'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'scenario "Taking it against the live membership instead" — the same member, the same amount, the live membership named');

set local role postgres;

-- 691
select results_eq(
  $$ select status, periods_granted, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000024f102'::uuid $$,
  $$ select 'active'::public.membership_status, 1, (select d from today_t24) + 30 $$,
  'and it EXTENDS NORMALLY — thirty days bought. This is the assertion a rule that simply stopped extending everything would fail, and stopping everything passes every refusal above it'
);

-- 692 — the harm check, third of three, and the whole of both requirements in
-- one comparison: after a payment, a full refund, a completed refund, a
-- payment status walk and a second payment against the live row, the retired
-- membership is byte-for-byte where the cancellation left it.
select results_eq(
  $$ select status, periods_granted, starts_on, ends_on, price_paise from public.memberships
      where id = '22000000-0000-4000-8000-00000024f101'::uuid $$,
  $$ select 'cancelled'::public.membership_status, 0,
            (select d from today_t24), (select d from today_t24), 100000::bigint $$,
  'and after all of it the retired membership is exactly where the cancellation left it. Money landed on it, money left it, a payment changed status beside it and a sibling membership grew — and none of that is a way back out of `cancelled`. Where a requirement names a harm, no scenario under it may reach that harm by another route'
);



-- ===========================================================================
-- SECTION 31 (ROUND EIGHTEEN) — THE COST, AND THE REPAIR PATH END TO END.
-- Tenant 24. Assertions 693-700.
--
-- The contract's Purpose was reworded while this suite was being written, and
-- the reworded paragraph makes a claim no scenario under either requirement
-- covers:
--
--   "What this change does make permanent is the mistake: a status written to
--    `expired` or `cancelled` in error can no longer be typed back, and the
--    repair is to sell the member a new membership — which the freed
--    one-live-membership index allows."
--
-- That is the price of Section 29 and it is the right price, but only IF THE
-- REPAIR ACTUALLY WORKS. A rule that makes retirement permanent and leaves the
-- member with no way back into the gym has not traded a defect for a cost; it
-- has shipped a second defect. So both halves are asserted rather than
-- assumed, and on TWO DIFFERENT MEMBERS on purpose:
--
--   693-695  the cost. A live membership is retired by mistake and cannot be
--            typed back. Red today, and the only part of this section that is.
--   696-700  the repair, walked end to end on its own member so that it is
--            green BEFORE and after — a control, not a consequence of 694.
--            Retire, sell again, take the money, and get the member through
--            the door.
--
-- 697 is the load-bearing one and it is load-bearing because of an index.
-- `memberships_tenant_id_member_id_live_key` is `unique (tenant_id,
-- member_id) where status in ('active','frozen')`, so a retired row does not
-- occupy the member's one live slot and the new sale fits. If retirement were
-- ever made to leave a row live, this assertion is what would notice, and it
-- would notice with `23505` rather than with anything about this requirement.
-- ===========================================================================

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-00000024f011'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Retired By Mistake', '+912224004011'),
  ('22000000-0000-4000-8000-00000024f012'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'M24 Repaired', '+912224004012');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-00000024f111'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024f011'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24) - 1, (select d from today_t24) + 30, 100000),
  ('22000000-0000-4000-8000-00000024f113'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-00000024f012'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
   'active', (select d from today_t24) - 1, (select d from today_t24), 100000);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, issued_at, expires_at) values
  ('22000000-0000-4000-8000-00000024f411'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
   '22000000-0000-4000-8000-000000240011'::uuid, 'pay22-t24-repair', now() - interval '1 minute', now() + interval '2 hours');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 693
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'meant to cancel the other one'
   where id = '22000000-0000-4000-8000-00000024f111'::uuid
$$, 'the desk retires a live membership BY MISTAKE — allowed, because the rule cannot tell a mistake from a decision and must not try');

-- 694
select throws_ok($$
  update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null
   where id = '22000000-0000-4000-8000-00000024f111'::uuid
$$, null::char(5), null,
  'and typing it back is refused — THE COST OF THIS CHANGE, written as an assertion rather than left in a paragraph: a mis-cancellation is permanent, and the desk cannot undo it by hand');

set local role postgres;

-- 695
select results_eq(
  $$ select status, ends_on from public.memberships
      where id = '22000000-0000-4000-8000-00000024f111'::uuid $$,
  $$ select 'cancelled'::public.membership_status, (select d from today_t24) + 30 $$,
  'still cancelled, with thirty days it never got to use still written on it — the row is a record of what happened, mistake and all'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000240001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000240021')::text,
  true);
set local role authenticated;

-- 696 — the repair, on its OWN member so that everything below is green both
-- before this change and after it.
select lives_ok($$
  update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'retired in error'
   where id = '22000000-0000-4000-8000-00000024f113'::uuid
$$, 'another member''s live membership is retired — the same act, on the member the repair is walked for');

-- 697 — THE ASSERTION THE WHOLE COST RESTS ON.
select lives_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
  values ('22000000-0000-4000-8000-00000024f114'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f012'::uuid, '22000000-0000-4000-8000-000000240061'::uuid,
          'active', (select d from today_t24) - 1, (select d from today_t24), 100000)
$$, 'THE REPAIR: the desk sells that member a NEW membership. memberships_tenant_id_member_id_live_key covers only `active` and `frozen`, so the retired row does not occupy the member''s one live slot. A permanent retirement is only an acceptable price if this works, and this is where that is checked rather than assumed');

-- 698
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-00000024f211'::uuid, '22000000-0000-4000-8000-000000240001'::uuid,
          '22000000-0000-4000-8000-00000024f012'::uuid, '22000000-0000-4000-8000-00000024f114'::uuid,
          100000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000240021'::uuid)
$$, 'and the money goes onto the new one');

-- 699
select lives_ok($$
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id)
  values ('22000000-0000-4000-8000-000000240001'::uuid, '22000000-0000-4000-8000-000000240011'::uuid,
          '22000000-0000-4000-8000-00000024f012'::uuid, 'qr', '22000000-0000-4000-8000-00000024f411'::uuid)
$$, 'and the member walks in, on the new membership — the loop this product exists for closes even after the desk got it wrong, which is the only thing that makes a permanent retirement survivable');

set local role postgres;

-- 700
select results_eq(
  $$ select
       (select status from public.memberships where id = '22000000-0000-4000-8000-00000024f113'::uuid),
       (select status from public.memberships where id = '22000000-0000-4000-8000-00000024f114'::uuid),
       (select periods_granted from public.memberships where id = '22000000-0000-4000-8000-00000024f114'::uuid),
       (select ends_on from public.memberships where id = '22000000-0000-4000-8000-00000024f114'::uuid) $$,
  $$ select 'cancelled'::public.membership_status, 'active'::public.membership_status,
            1, (select d from today_t24) + 30 $$,
  'and the end state is the honest one: the retirement still on the books, a live membership beside it with thirty days bought, and a member inside the gym. Retirement being permanent costs a row, not a customer'
);



-- ===========================================================================
-- SECTION 32 (ROUND EIGHTEEN, ADR-099) — "Re-pointing a membership and
-- re-lengthening it in one statement". Tenant 25. Assertions 701-709.
--
-- WHICH RULE ANSWERS IS THE BEHAVIOUR, NOT AN IMPLEMENTATION DETAIL. A single
-- statement that moves a membership to another member AND writes a length
-- violates two rules at once, and the caller acts on the one that comes back.
-- `GL043` says "the length is derived — change the plan instead", which is
-- advice about a plan and sends the desk off to edit terms; the true answer is
-- `GL042` — this membership belongs to somebody else, and the repair is a
-- refund, a cancellation and a new sale. A caller told the wrong thing does the
-- wrong thing, so the ORDER of the two checks is contract.
--
-- WHY IT NEEDS ITS OWN ASSERTION. It silently stopped being true once: a later
-- migration re-emitted the enforcing function to add something unrelated and
-- moved the member_id check after the length check. Both refusals still
-- existed, both suites stayed green, and nothing noticed — because no assertion
-- anywhere named a statement that violates two rules at once.
--
-- SO THIS SECTION PROVES ORDERING RATHER THAN PRESENCE. 702 and 704 pin each
-- violation ALONE against its own code, so the pair below cannot pass by both
-- codes having quietly become the same one; 706 pins the combined statement to
-- `GL042`; 708 repeats it with the SET list written the other way round, since
-- a check ordered by the statement's column list would pass 706 and still be
-- wrong.
--
-- THE TRAP THE REQUIREMENT NAMES. `memberships_tenant_id_member_id_live_key`
-- refuses a move onto a member who already holds a live membership, and a
-- `23505` from that index would answer instead of the rule — a careless check
-- reports a false GREEN. Every target here (T1, T2, T3) holds NOTHING, 701
-- asserts that as its own assertion before any refusal is attempted, and each
-- attempt uses a different target so a move that lands cannot turn the next
-- into a same-value write refused by nothing.
--
-- NO MONEY IS TAKEN AGAINST THIS MEMBERSHIP ON PURPOSE. The terms freeze on
-- price, currency and plan engages only once money has arrived, and the length
-- rule bites whether or not it has — so an unpaid membership leaves exactly the
-- two rules this section is about in play, and no third one able to answer
-- first for a reason that is not the question.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000250001'::uuid, 'PayRec Gym 25', 'PYR22R');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000250011'::uuid, '22000000-0000-4000-8000-000000250001'::uuid, 'G25 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000250021'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250011'::uuid, 'front_desk', 'T25 Desk');

-- A holds the membership under attack. T1, T2 and T3 hold nothing at all and
-- are the targets of the three refused moves, one each.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000250041'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250011'::uuid, 'M25 A', '+912225000041'),
  ('22000000-0000-4000-8000-000000250051'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250011'::uuid, 'M25 T1', '+912225000051'),
  ('22000000-0000-4000-8000-000000250052'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250011'::uuid, 'M25 T2', '+912225000052'),
  ('22000000-0000-4000-8000-000000250053'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250011'::uuid, 'M25 T3', '+912225000053');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000250061'::uuid, '22000000-0000-4000-8000-000000250001'::uuid, 'G25 Plan (30d)', 30, 100000);

create temp table today_t25 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000250001'::uuid;
grant select on today_t25 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000250081'::uuid, '22000000-0000-4000-8000-000000250001'::uuid,
   '22000000-0000-4000-8000-000000250041'::uuid, '22000000-0000-4000-8000-000000250061'::uuid,
   'active', (select d from today_t25), (select d from today_t25), 100000);

-- 701 — THE TRAP, DISARMED, before anything is attempted: the membership names
-- A and records the 30 days its plan says, and the three targets hold zero
-- memberships of any status — so nothing below can be refused by
-- memberships_tenant_id_member_id_live_key while this section reports GREEN.
-- Asserted rather than assumed, because that false green is the failure the
-- requirement predicts by name.
select results_eq(
  $$ select m.member_id, to_jsonb(m)->>'duration_days',
            (select count(*)::int from public.memberships x
              where x.member_id in ('22000000-0000-4000-8000-000000250051'::uuid,
                                    '22000000-0000-4000-8000-000000250052'::uuid,
                                    '22000000-0000-4000-8000-000000250053'::uuid))
       from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000250081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000250041'::uuid, '30'::text, 0) $$,
  'ordering fixture: the membership names the member it was sold to and records its plan''s 30 days, and every target of every move below holds NOTHING — so the live unique key cannot be what answers any of them'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000250001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000250021')::text,
  true);
set local role authenticated;

-- 702 — the member_id violation ALONE answers with GL042. Without this, 706
-- below could pass because both rules had quietly become the same code.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000250051'::uuid
   where id = '22000000-0000-4000-8000-000000250081'::uuid
$$, 'GL042'::char(5), null,
  'ordering, control one: re-pointing alone answers with GL042 — the code whose own requirement names this harm');

set local role postgres;

-- 703
select results_eq(
  $$ select m.member_id, to_jsonb(m)->>'duration_days' from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000250081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000250041'::uuid, '30'::text) $$,
  'and the membership is unchanged after it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000250001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000250021')::text,
  true);
set local role authenticated;

-- 704 — the length violation ALONE answers with GL043. The other half of the
-- pair: the two codes are shown to be distinguishable BEFORE the combined
-- statement is asked which of them it gives.
select throws_ok($$
  update public.memberships set duration_days = 3650
   where id = '22000000-0000-4000-8000-000000250081'::uuid
$$, 'GL043'::char(5), null,
  'ordering, control two: writing a length alone answers with GL043 — so the two rules genuinely carry different codes, and asking which one a doubly-violating statement gives is a real question');

set local role postgres;

-- 705
select results_eq(
  $$ select m.member_id, to_jsonb(m)->>'duration_days' from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000250081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000250041'::uuid, '30'::text) $$,
  'and the membership is unchanged after that too');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000250001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000250021')::text,
  true);
set local role authenticated;

-- 706 — THE SCENARIO. One statement, both violations, and the answer must be
-- GL042. GL043 would tell the desk to change the plan instead, which is advice
-- about a plan; the true answer is that this membership belongs to somebody
-- else and the repair is a refund, a cancellation and a new sale. The caller
-- acts on the message, so which rule answers is the behaviour.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000250052'::uuid,
         duration_days = 3650
   where id = '22000000-0000-4000-8000-000000250081'::uuid
$$, 'GL042'::char(5), null,
  'scenario "Re-pointing a membership and re-lengthening it in one statement" — refused with the member_id rule, NOT the length rule. GL043 sends the caller to change the plan; the membership belongs to somebody else, and that is what has to come back');

set local role postgres;

-- 707
select results_eq(
  $$ select m.member_id, to_jsonb(m)->>'duration_days', m.periods_granted, m.starts_on, m.ends_on
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000250081'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000250041'::uuid, '30'::text, 0,
            (select d from today_t25), (select d from today_t25) $$,
  'and neither half of the statement landed — the owner, the length, the count and both dates are where they were'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000250001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000250021')::text,
  true);
set local role authenticated;

-- 708 — the same statement with the SET list written the other way round. A
-- check ordered by the statement's column list rather than by the rules would
-- pass 706 and answer GL043 here, which is exactly the drift ADR-099 records:
-- the order belongs to the rules, not to how the caller happened to type it.
select throws_ok($$
  update public.memberships
     set duration_days = 3650,
         member_id = '22000000-0000-4000-8000-000000250053'::uuid
   where id = '22000000-0000-4000-8000-000000250081'::uuid
$$, 'GL042'::char(5), null,
  'and with the SET list in the other order it is still GL042 — which rule answers is decided by the rules, not by the order the caller listed the columns');

set local role postgres;

-- 709
select results_eq(
  $$ select m.member_id, to_jsonb(m)->>'duration_days', m.periods_granted
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000250081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000250041'::uuid, '30'::text, 0) $$,
  'unchanged after that one as well — the membership still belongs to the member it was sold to, still measured in the days its plan says'
);


-- ===========================================================================
-- SECTION 33 (ROUND NINETEEN, ADR-099 widened) — "GL042 answers ahead of every
-- other rule that can refuse the same statement", proven against GL047; and
-- "Re-pointing onto a member who already has a membership". Tenant 26.
-- Assertions 710-722.
--
-- WHAT IS NEW HERE AND WHY IT IS NEW. Section 32 already pins GL042 ahead of
-- GL043, and the holdout suite covers GL042 against GL044, GL045 and GL046.
-- GL047 — the membership-status transition rule — is the one member of that
-- set covered NOWHERE, and it is the one that cannot be fixed by moving a
-- clause: GL047 lives in its own trigger (`memberships_status_transitions`,
-- separate on purpose, because both seed files disable the terms trigger and
-- folding it in would leave it silently off for the whole seed), and Postgres
-- fires same-timing row triggers in TRIGGER-NAME order. So no ordering of
-- checks inside the terms function can ever reach it; the answer to "which
-- rule answers" is decided by how the two trigger names sort. That is exactly
-- the kind of ordering that changes under a rename nobody thinks of as a
-- behaviour change, which is why it gets an assertion rather than a comment.
--
-- WHY GL042 AND NOT GL047. A caller acts on the message. "A membership does
-- not go from cancelled to active" is advice for somebody working on their own
-- member's membership — it says ask a manager, or sell a new one to this
-- member. The true answer is that the membership belongs to somebody else and
-- the only repair is a refund, a cancellation and a new sale. GL042 is the
-- only rule among the five about WHOSE membership this is; every other one is
-- about what may be done to a membership already agreed to be yours.
--
-- THE CONTROLS ARE THE POINT (711, 713). Two codes that have quietly collapsed
-- onto one would pass 715, 717 and 719 without the ordering being true at all.
-- So each violation is pinned ALONE first: the illegal transition by itself
-- answers GL047, the re-point by itself answers GL042, and only then is the
-- doubly-violating statement asked which of the two it gives. 717 repeats 715
-- with the SET list written the other way round — a check ordered by the
-- caller's column list would pass one and fail the other, and which rule
-- answers is not the caller's to choose.
--
-- 719 IS THE OTHER HALF OF THE SAME PROOF. `active → frozen` is a LEGAL
-- transition, so GL047 has nothing to say about it; if that statement is still
-- refused with GL042 then it is genuinely the re-point answering, and not
-- merely "any statement that writes a status loses". Without 719, an
-- implementation that refused every combined statement for the wrong reason
-- would read green.
--
-- THE INDEX IS NOT A RULE (721). `memberships_tenant_id_member_id_live_key` is
-- partial on ('active','frozen') and is checked during the UPDATE itself,
-- before any AFTER trigger runs — so pointing a LIVE membership at a member who
-- already holds a live one is `23505` and no rule ordering can change that.
-- Section 32 and every other assertion of this requirement deliberately arrange
-- targets holding NOTHING to keep the index out of the way; this one
-- deliberately walks into it, because a handler written to expect GL042 will
-- get 23505 in the likely case — two members mixed up is exactly the case where
-- the other member has a membership of their own. Both memberships in 721 are
-- `active`: if either were cancelled the index would not be in play and GL042
-- would answer instead, which is the false green this assertion exists to rule
-- out (710 asserts both statuses before it is attempted).
--
-- FIXTURES. C (cancelled, member A) is created cancelled rather than
-- transitioned into it — GL047 itself refuses the transition, so staging it by
-- hand would be staging through the rule under test. V (active, member B) is
-- the live membership used for the legal-transition case and for the index
-- case. T1-T4 hold NOTHING, one target per refused move, so no assertion below
-- can be answered by the live unique key while reporting green. X holds one
-- `active` membership and is the target of 721 alone.
--
-- No money is taken against any of these on purpose: the terms freeze engages
-- only once money has arrived, so an unpaid fixture leaves exactly the rules
-- this section is about in play. ADR-039: every date is the gym's own today.
-- ADR-030: nothing is committed; the file's single BEGIN … ROLLBACK covers it.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000260001'::uuid, 'PayRec Gym 26', 'PYR22S');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000260011'::uuid, '22000000-0000-4000-8000-000000260001'::uuid, 'G26 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000260021'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'front_desk', 'T26 Desk');

-- A holds the cancelled membership; B holds the live one. X already holds a
-- live membership of his own and is the target of the 23505 case alone. T1-T4
-- hold nothing and are the targets of the four refused moves, one each.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000260041'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 A', '+912226000041'),
  ('22000000-0000-4000-8000-000000260042'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 B', '+912226000042'),
  ('22000000-0000-4000-8000-000000260043'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 X', '+912226000043'),
  ('22000000-0000-4000-8000-000000260051'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 T1', '+912226000051'),
  ('22000000-0000-4000-8000-000000260052'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 T2', '+912226000052'),
  ('22000000-0000-4000-8000-000000260053'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 T3', '+912226000053'),
  ('22000000-0000-4000-8000-000000260054'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260011'::uuid, 'M26 T4', '+912226000054');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000260061'::uuid, '22000000-0000-4000-8000-000000260001'::uuid, 'G26 Plan (30d)', 30, 100000);

create temp table today_t26 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000260001'::uuid;
grant select on today_t26 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at) values
  -- C: cancelled, created in that state rather than transitioned into it.
  ('22000000-0000-4000-8000-000000260081'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260041'::uuid, '22000000-0000-4000-8000-000000260061'::uuid,
   'cancelled', (select d from today_t26), (select d from today_t26), 100000, now()),
  -- V: live, for the legal-transition case and for the index case.
  ('22000000-0000-4000-8000-000000260082'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260042'::uuid, '22000000-0000-4000-8000-000000260061'::uuid,
   'active', (select d from today_t26), (select d from today_t26), 100000, null),
  -- X's own live membership: what makes the partial unique index bite at 721.
  ('22000000-0000-4000-8000-000000260083'::uuid, '22000000-0000-4000-8000-000000260001'::uuid,
   '22000000-0000-4000-8000-000000260043'::uuid, '22000000-0000-4000-8000-000000260061'::uuid,
   'active', (select d from today_t26), (select d from today_t26), 100000, null);

-- 710 — the fixture asserted before anything is attempted, both ways round: the
-- four targets of the ordering assertions hold NOTHING (so the live unique key
-- cannot answer them and report a false green), and X holds exactly one LIVE
-- membership (so at 721 the index certainly CAN answer — a cancelled or expired
-- row there would put GL042 back in the frame and 721 would be measuring the
-- wrong thing).
select results_eq(
  $$ select (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000260081'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000260081'::uuid),
            (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000260082'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000260082'::uuid),
            (select count(*)::int from public.memberships x
              where x.member_id in ('22000000-0000-4000-8000-000000260051'::uuid,
                                    '22000000-0000-4000-8000-000000260052'::uuid,
                                    '22000000-0000-4000-8000-000000260053'::uuid,
                                    '22000000-0000-4000-8000-000000260054'::uuid)),
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000260043'::uuid
                and x.status in ('active', 'frozen')) $$,
  $$ values ('22000000-0000-4000-8000-000000260041'::uuid, 'cancelled'::text,
             '22000000-0000-4000-8000-000000260042'::uuid, 'active'::text, 0, 1) $$,
  'ordering fixture: the cancelled membership names A and the live one names B, all four targets of the ordering assertions hold NOTHING, and X holds exactly one LIVE membership — so nothing at 711-719 can be answered by the live unique key, and 721 certainly can be'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 711 — CONTROL ONE: the illegal transition ALONE answers with GL047. Without
-- this, 715 could pass because GL042 and GL047 had quietly become one code and
-- the ordering it claims to prove would be vacuous.
select throws_ok($$
  update public.memberships set status = 'active'
   where id = '22000000-0000-4000-8000-000000260081'::uuid
$$, 'GL047'::char(5), null,
  'ordering, control one: reviving a cancelled membership alone answers with GL047 — the transition rule, in its own trigger');

set local role postgres;

-- 712
select results_eq(
  $$ select m.member_id, m.status::text from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000260081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000260041'::uuid, 'cancelled'::text) $$,
  'and the membership is unchanged after it — still cancelled, still A''s');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 713 — CONTROL TWO: the re-point ALONE answers with GL042, on this same
-- fixture. The two codes are shown to be distinguishable BEFORE the combined
-- statement is asked which of them it gives.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000260051'::uuid
   where id = '22000000-0000-4000-8000-000000260081'::uuid
$$, 'GL042'::char(5), null,
  'ordering, control two: re-pointing alone answers with GL042 — so the two rules genuinely carry different codes and asking which one a doubly-violating statement gives is a real question');

set local role postgres;

-- 714
select results_eq(
  $$ select m.member_id, m.status::text from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000260081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000260041'::uuid, 'cancelled'::text) $$,
  'and unchanged after that too');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 715 — THE SCENARIO. One statement re-points the cancelled membership at a
-- member holding nothing AND revives it, violating GL042 and GL047 at once, and
-- the answer must be GL042. GL047 tells the caller a membership does not come
-- back from cancelled, which is advice about their own member's membership;
-- this membership is somebody else's, and the repair is a refund, a
-- cancellation and a new sale. `memberships_status_transitions` sorts before
-- `memberships_terms_frozen`, and same-timing row triggers fire in name order,
-- so this is decided by the trigger NAMES and by nothing inside either function.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000260052'::uuid,
         status = 'active'
   where id = '22000000-0000-4000-8000-000000260081'::uuid
$$, 'GL042'::char(5), null,
  'GL042 answers ahead of GL047: one statement that re-points a cancelled membership and revives it is refused with the member_id rule, not the transition rule');

set local role postgres;

-- 716
select results_eq(
  $$ select m.member_id, m.status::text, m.periods_granted, m.starts_on, m.ends_on
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000260081'::uuid $$,
  $$ select '22000000-0000-4000-8000-000000260041'::uuid, 'cancelled'::text, 0,
            (select d from today_t26), (select d from today_t26) $$,
  'and neither half of the statement landed — the owner, the status, the count and both dates are where they were'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 717 — the same statement with the SET list written the other way round. Which
-- rule answers belongs to the rules, not to the order the caller happened to
-- type the columns in.
select throws_ok($$
  update public.memberships
     set status = 'active',
         member_id = '22000000-0000-4000-8000-000000260053'::uuid
   where id = '22000000-0000-4000-8000-000000260081'::uuid
$$, 'GL042'::char(5), null,
  'and with the SET list in the other order it is still GL042 — the answer does not depend on the caller''s column order');

set local role postgres;

-- 718
select results_eq(
  $$ select m.member_id, m.status::text, m.periods_granted from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000260081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000260041'::uuid, 'cancelled'::text, 0) $$,
  'unchanged after that one as well');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 719 — A LEGAL TRANSITION PLUS A RE-POINT. `active → frozen` is permitted, so
-- GL047 has nothing to say here and the only rule left is GL042. If this were
-- refused by something else — or if 715 passed only because every statement
-- carrying a status write loses — this assertion is where that shows.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000260054'::uuid,
         status = 'frozen'
   where id = '22000000-0000-4000-8000-000000260082'::uuid
$$, 'GL042'::char(5), null,
  'a LEGAL status transition plus a re-point is still GL042 — it is the re-point answering, not "any statement that writes a status is refused"');

set local role postgres;

-- 720
select results_eq(
  $$ select m.member_id, m.status::text from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000260082'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000260042'::uuid, 'active'::text) $$,
  'and the live membership is unchanged — still B''s, still active, so the permitted half did not land either');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000260001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000260021')::text,
  true);
set local role authenticated;

-- 721 — scenario "Re-pointing onto a member who already has a membership". Both
-- rows are `active`, so both are in `memberships_tenant_id_member_id_live_key`,
-- which is checked during the UPDATE itself — before any AFTER trigger runs. An
-- index is not a rule and no rule ordering can get in front of it, so the code
-- is 23505 and NOT GL042. This is the likely case rather than an edge one: you
-- re-point because two members were mixed up, and the other member normally has
-- a membership of their own. Recorded so nobody writes a handler expecting
-- GL042 here.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000260043'::uuid
   where id = '22000000-0000-4000-8000-000000260082'::uuid
$$, '23505'::char(5), null,
  'pointing a live membership at a member who already holds one is refused by the live-membership index with 23505 — the index runs during the UPDATE, ahead of every rule, and no ordering changes that');

set local role postgres;

-- 722
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000260043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000260082'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000260042'::uuid, 'active'::text, 1) $$,
  'and the membership is unchanged — still B''s and still active, and X still holds exactly the one membership he came with'
);



-- ===========================================================================
-- SECTION 34 (ROUND TWENTY) — "GL042 answers ahead of every other RULE. It
-- does not answer ahead of the table's own SHAPE." Tenant 27.
-- Assertions 723-741.
--
-- THE CLASS SENTENCE, WHICH IS WHAT THIS SECTION PINS. CHECK constraints,
-- unique indexes, foreign keys and the row-security policy are not rules in
-- the sense the ordering requirement means. They are enforced during the
-- UPDATE itself — the policy's WITH CHECK and the CHECK constraints before the
-- new row is even stored, the unique index as it is stored, the foreign key by
-- an internal constraint trigger that sorts ahead of every trigger this project
-- names — so no trigger naming and no clause ordering inside any function can
-- put GL042 in front of them. A statement that violates one of them AND GL042
-- comes back with 23514, 23505, 23503 or 42501, and never with GL042.
--
-- ONE ASSERTION PER MECHANISM, NOT PER CONSTRAINT. Two earlier attempts at
-- this sentence enumerated the exceptions and both were measured false: the
-- first claimed GL042 answers "in every case", the second added a single
-- condition and a critic then found four more families in the scenario's own
-- column list. Enumerating exceptions to a rule about shape produces a list
-- that is always one item short. So this section asserts the four MECHANISMS —
-- memberships_ends_on_after_starts_on_chk for CHECK, memberships_plan_id_fkey
-- for the foreign key, memberships_tenant_id_member_id_live_key for the unique
-- index, memberships_tenant_write for the policy — and not the seven CHECK
-- constraints the table happens to carry today. A CHECK added tomorrow belongs
-- to the class already proven; a CHECK enumerated tomorrow leaves the list one
-- item short again.
--
-- WHY EVERY ONE OF THEM HAS A CONTROL. An assertion that a statement throws
-- 23514 proves nothing on its own: it passes identically if GL042 has stopped
-- existing, if the re-point half was silently accepted, or if the fixture never
-- violated GL042 in the first place. So each mechanism is asserted TWICE — the
-- same statement WITH the shape violation (the named SQLSTATE) and WITHOUT it
-- (GL042) — and only the pair distinguishes "the constraint answered first"
-- from "nothing was refused by GL042 at all". Each control is the violating
-- statement with the offending value replaced by the value the row already
-- holds, so the two differ in exactly the shape violation and in nothing else.
--
-- 740 IS THE BOUNDARY, AND IT IS THE ONE A PREVIOUS ROUND GOT WRONG.
-- memberships_tenant_id_member_id_live_key is PARTIAL on ('active','frozen'),
-- so it bites on the state of the membership BEING MOVED, not on the state of
-- the member it is moved onto. 734 and 740 point the same statement at the same
-- member X — who holds a live membership of his own — and differ only in
-- whether the SOURCE row is live: the active one is 23505, the cancelled one is
-- GL042. An implementation, a spec draft or a handler that reads "the target
-- already has one" as the deciding fact passes 734 and fails 740, which is
-- exactly the partition a critic measured to be wrong.
--
-- FIXTURES. L (active, A) is the row every shape case is attempted against; Q
-- (cancelled, A) is created cancelled rather than transitioned into it, since
-- GL047 refuses that transition and staging it by hand would be staging through
-- a rule. X holds one active membership of his own — that is what makes the
-- partial index bite at 734 and what makes 740 mean anything. T1-T7 hold
-- NOTHING, one target per attempt, so no control can be answered by the live
-- unique key while reporting a false green, and no attempt that unexpectedly
-- LANDS can turn the next one into a same-value write refused by nothing. A
-- second organization (27b) exists solely to be a tenant_id this session may
-- not write; nothing else is ever inserted into it.
--
-- No money is taken against any of these on purpose: the terms freeze engages
-- only once money has arrived, so an unpaid fixture leaves exactly the rules
-- and the shape this section is about in play. ADR-039: every date is the gym's
-- own today. ADR-030: nothing is committed; the file's single BEGIN … ROLLBACK
-- covers it.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000270001'::uuid, 'PayRec Gym 27', 'PYR22T'),
  -- 27b: never written to, never read from. It exists only so that 738 has a
  -- real tenant_id to attempt, rather than a uuid that would fail the tenant
  -- foreign key for a reason that is not the policy.
  ('22000000-0000-4000-8000-000000270002'::uuid, 'PayRec Gym 27b', 'PYR22U');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000270011'::uuid, '22000000-0000-4000-8000-000000270001'::uuid, 'G27 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000270021'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'front_desk', 'T27 Desk');

-- A holds both memberships under attack (L active, Q cancelled). X holds a live
-- membership of his own and is the target of 734 and 740. T1-T7 hold nothing,
-- one target per attempt.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 A', '+912227000041'),
  ('22000000-0000-4000-8000-000000270043'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 X', '+912227000043'),
  ('22000000-0000-4000-8000-000000270051'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T1', '+912227000051'),
  ('22000000-0000-4000-8000-000000270052'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T2', '+912227000052'),
  ('22000000-0000-4000-8000-000000270053'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T3', '+912227000053'),
  ('22000000-0000-4000-8000-000000270054'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T4', '+912227000054'),
  ('22000000-0000-4000-8000-000000270055'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T5', '+912227000055'),
  ('22000000-0000-4000-8000-000000270056'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T6', '+912227000056'),
  ('22000000-0000-4000-8000-000000270057'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270011'::uuid, 'M27 T7', '+912227000057');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000270061'::uuid, '22000000-0000-4000-8000-000000270001'::uuid, 'G27 Plan (30d)', 30, 100000);

create temp table today_t27 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000270001'::uuid;
grant select on today_t27 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at) values
  -- L: active, A's. Every shape case below is attempted against this row.
  ('22000000-0000-4000-8000-000000270081'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270061'::uuid,
   'active', (select d from today_t27), (select d from today_t27), 100000, null),
  -- Q: cancelled, A's, created in that state. The source row of 740.
  ('22000000-0000-4000-8000-000000270082'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270061'::uuid,
   'cancelled', (select d from today_t27), (select d from today_t27), 100000, now()),
  -- X's own live membership: what makes the partial unique index bite at 734,
  -- and what makes 740 a boundary rather than a repeat of the controls.
  ('22000000-0000-4000-8000-000000270083'::uuid, '22000000-0000-4000-8000-000000270001'::uuid,
   '22000000-0000-4000-8000-000000270043'::uuid, '22000000-0000-4000-8000-000000270061'::uuid,
   'active', (select d from today_t27), (select d from today_t27), 100000, null);

-- 723 — the whole fixture asserted before anything is attempted, because every
-- claim below depends on one of these being true: L is active and A's and dated
-- so that starts_on - 1 really does violate the dates CHECK; Q is cancelled and
-- A's, so the partial index does NOT cover it; X holds exactly one LIVE
-- membership, so at 734 the index certainly CAN answer and at 740 the only
-- thing that differs is the source row's own state; T1-T7 hold NOTHING, so no
-- control can be answered by the index while reporting green; the plan named at
-- 730 does not exist; and the tenant named at 738 does.
select results_eq(
  $$ select (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000270081'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000270081'::uuid),
            (select m.starts_on = m.ends_on from public.memberships m where m.id = '22000000-0000-4000-8000-000000270081'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000270082'::uuid),
            (select count(*)::int from public.memberships x
              where x.member_id in ('22000000-0000-4000-8000-000000270051'::uuid,
                                    '22000000-0000-4000-8000-000000270052'::uuid,
                                    '22000000-0000-4000-8000-000000270053'::uuid,
                                    '22000000-0000-4000-8000-000000270054'::uuid,
                                    '22000000-0000-4000-8000-000000270055'::uuid,
                                    '22000000-0000-4000-8000-000000270056'::uuid,
                                    '22000000-0000-4000-8000-000000270057'::uuid)),
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000270043'::uuid
                and x.status in ('active', 'frozen')),
            (select count(*)::int from public.plans p
              where p.id = '22000000-0000-4000-8000-0000002700f0'::uuid),
            (select count(*)::int from public.organizations o
              where o.id = '22000000-0000-4000-8000-000000270002'::uuid) $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'active'::text, true,
             'cancelled'::text, 0, 1, 0, 1) $$,
  'shape fixture: L is A''s and active and single-dated, Q is cancelled, all seven controls'' targets hold NOTHING, X holds exactly one LIVE membership, the plan named at 730 does not exist, and the tenant named at 738 does'
);

-- ---------------------------------------------------------------------------
-- MECHANISM 1 of 4 — CHECK. memberships_ends_on_after_starts_on_chk.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 724 — CONTROL for the CHECK case. The identical statement with `starts_on` in
-- place of `starts_on - 1`: that is the value the row already holds, so it
-- satisfies every CHECK on the table and leaves GL042 as the only thing
-- violated. Without this, 726 would pass just as happily against an
-- implementation in which GL042 had stopped refusing anything at all.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270051'::uuid,
         ends_on = starts_on
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, 'GL042'::char(5), null,
  'shape control, CHECK: re-pointing while writing a date the row already holds violates no CHECK, so the member_id rule answers — GL042');

set local role postgres;

-- 725
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on = m.ends_on from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'active'::text, true) $$,
  'and the membership is unchanged after it — still A''s, still active, still dated as it was');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 726 — THE CHECK MECHANISM. The same statement, now ending the membership the
-- day before it starts. memberships_ends_on_after_starts_on_chk is evaluated on
-- the new row before it is stored, which is before any AFTER trigger exists to
-- run, so 23514 is the answer and no ordering of rules can reach in front of it.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270052'::uuid,
         ends_on = starts_on - 1
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, '23514'::char(5), null,
  'GL042 does not answer ahead of a CHECK constraint: re-pointing while dating the membership to end before it starts comes back 23514 from memberships_ends_on_after_starts_on_chk, not GL042 — the CHECK runs during the UPDATE itself');

set local role postgres;

-- 727
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on = m.ends_on from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'active'::text, true) $$,
  'and neither half of it landed — the owner and both dates are where they were');

-- ---------------------------------------------------------------------------
-- MECHANISM 2 of 4 — FOREIGN KEY. memberships_plan_id_fkey, which is composite
-- (tenant_id, plan_id) since ADR-052.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 728 — CONTROL for the foreign-key case. The identical statement naming the
-- plan the membership already carries: the referenced row exists, so the
-- foreign key has nothing to say and GL042 is the only thing left. Naming the
-- same plan is also not a plan CHANGE, so GL043 and GL046 are not what answers
-- either — and if they were, GL042 would still have to beat them both.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270053'::uuid,
         plan_id = '22000000-0000-4000-8000-000000270061'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, 'GL042'::char(5), null,
  'shape control, foreign key: re-pointing while naming the plan the row already carries breaks no foreign key, so the member_id rule answers — GL042');

set local role postgres;

-- 729
select results_eq(
  $$ select m.member_id, m.plan_id from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270061'::uuid) $$,
  'and the membership is unchanged after it — still A''s, still on its own plan');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 730 — THE FOREIGN-KEY MECHANISM. The same statement naming a plan that does
-- not exist. The referential check is an internal constraint trigger, and those
-- sort ahead of every trigger this project names, so 23503 answers and no
-- rename of memberships_terms_frozen could ever put GL042 in front of it.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270054'::uuid,
         plan_id = '22000000-0000-4000-8000-0000002700f0'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, '23503'::char(5), null,
  'GL042 does not answer ahead of a foreign key: re-pointing while naming a plan that does not exist comes back 23503 from memberships_plan_id_fkey, not GL042');

set local role postgres;

-- 731
select results_eq(
  $$ select m.member_id, m.plan_id from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270061'::uuid) $$,
  'and neither half of it landed — the owner and the plan are where they were');

-- ---------------------------------------------------------------------------
-- MECHANISM 3 of 4 — UNIQUE INDEX.
-- memberships_tenant_id_member_id_live_key, partial on ('active','frozen').
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 732 — CONTROL for the unique-index case. The same live membership, the same
-- single-column statement, pointed at a member who holds NOTHING: the partial
-- index has no conflicting entry, so GL042 answers. This is what makes 734 a
-- statement about the index rather than about re-pointing being refused at all.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000270055'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, 'GL042'::char(5), null,
  'shape control, unique index: pointing the same live membership at a member who holds nothing collides with no index entry, so the member_id rule answers — GL042');

set local role postgres;

-- 733
select results_eq(
  $$ select m.member_id, m.status::text from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'active'::text) $$,
  'and the membership is unchanged after it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 734 — THE UNIQUE-INDEX MECHANISM, and the scenario "Re-pointing a live
-- membership onto a member who already has one". L is active and so is X's own
-- membership, so both sit in the partial index; the collision is detected as
-- the new row is stored, before any AFTER trigger runs. 23505, not GL042 — and
-- this is the LIKELY case rather than an edge one, since you re-point because
-- two members were mixed up and the other member usually has a membership of
-- their own.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000270043'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, '23505'::char(5), null,
  'GL042 does not answer ahead of a unique index: pointing a LIVE membership at a member who already holds a live one comes back 23505 from memberships_tenant_id_member_id_live_key, not GL042');

set local role postgres;

-- 735
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000270043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'active'::text, 1) $$,
  'and the membership is unchanged — still A''s and still active, and X still holds exactly the one membership he came with');

-- ---------------------------------------------------------------------------
-- MECHANISM 4 of 4 — ROW SECURITY. memberships_tenant_write's WITH CHECK.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 736 — CONTROL for the policy case. The identical statement writing this
-- session's OWN tenant_id — the value the row already holds — so the policy's
-- WITH CHECK passes and GL042 is the only thing left to refuse it.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270056'::uuid,
         tenant_id = '22000000-0000-4000-8000-000000270001'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, 'GL042'::char(5), null,
  'shape control, policy: re-pointing while writing this session''s own tenant_id satisfies memberships_tenant_write, so the member_id rule answers — GL042');

set local role postgres;

-- 737
select results_eq(
  $$ select m.member_id, m.tenant_id from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270001'::uuid) $$,
  'and the membership is unchanged after it — still A''s, still this gym''s');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 738 — THE POLICY MECHANISM. The same statement writing 27b's tenant_id. The
-- WITH CHECK on memberships_tenant_write is evaluated on the new row during the
-- UPDATE, so 42501 answers — ahead of the composite member foreign key that the
-- same write also breaks, and long ahead of any AFTER trigger.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000270057'::uuid,
         tenant_id = '22000000-0000-4000-8000-000000270002'::uuid
   where id = '22000000-0000-4000-8000-000000270081'::uuid
$$, '42501'::char(5), null,
  'GL042 does not answer ahead of the row-security policy: re-pointing while writing another tenant''s tenant_id comes back 42501 from memberships_tenant_write, not GL042');

set local role postgres;

-- 739
select results_eq(
  $$ select m.member_id, m.tenant_id from public.memberships m
      where m.id = '22000000-0000-4000-8000-000000270081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, '22000000-0000-4000-8000-000000270001'::uuid) $$,
  'and neither half of it landed — the membership is still A''s and still this gym''s');

-- ---------------------------------------------------------------------------
-- THE BOUNDARY — the SOURCE membership's state decides, not the target's.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000270001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000270021')::text,
  true);
set local role authenticated;

-- 740 — scenario "Re-pointing a membership that is not live". Word for word the
-- same statement as 734 except for which membership it names: Q is cancelled,
-- and memberships_tenant_id_member_id_live_key is partial on ('active','frozen'),
-- so Q is not in the index and the target's own live membership cannot collide
-- with a row that is not there. The index does not apply, and GL042 answers.
--
-- THIS IS THE ASSERTION THAT SEPARATES THE TWO READINGS. "The target already
-- holds a live membership" predicts 23505 here and is wrong; "the membership
-- being moved is itself live" predicts GL042 and is right. 734 and 740 point at
-- the same member X, so nothing but the source row's own status differs between
-- them, and no implementation can satisfy both readings.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000270043'::uuid
   where id = '22000000-0000-4000-8000-000000270082'::uuid
$$, 'GL042'::char(5), null,
  'a CANCELLED membership pointed at a member who already holds a live one is GL042, not 23505 — the live index is partial on (active, frozen) and does not cover the row being moved, so the SOURCE membership''s state decides which answers, not the target''s');

set local role postgres;

-- 741
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000270043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000270082'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000270041'::uuid, 'cancelled'::text, 1) $$,
  'and the cancelled membership is unchanged — still A''s, still cancelled, and X still holds exactly the one membership he came with'
);


-- ===========================================================================
-- SECTION 35 (ROUND TWENTY-ONE) — WHICH ROW'S STATUS DECIDES WHETHER THE LIVE
-- INDEX APPLIES, a foreign key pointing AT memberships, and the one outcome
-- that is not an error at all. Tenant 28. Assertions 742-757.
--
-- WHY THIS SECTION EXISTS. Three rounds of this requirement's prose were green
-- under three mutually contradictory readings of one rule, and the reason is
-- arithmetic rather than taste: EVERY assertion written across those rounds
-- re-pointed a membership WITHOUT WRITING `status`. A statement that writes no
-- status keeps the row's current status, so "the target member's state decides",
-- "the source membership's state decides" and "the tuple being stored decides"
-- all predict the same answer for every one of them. None of them could tell
-- the readings apart, which is why all three readings survived three rounds.
--
-- `memberships_tenant_id_member_id_live_key` is PARTIAL on ('active','frozen'),
-- and a partial index is evaluated against THE TUPLE BEING STORED — not the row
-- as it was, and not the target member's other rows. So the only statements that
-- can separate the readings are the ones where the tuple being stored has a
-- DIFFERENT status from the row it replaces, and they are the two at 745 and 749.
--
--   | statement                                                  | answer |
--   |------------------------------------------------------------|--------|
--   | 745  cancelled row -> live-holder, `status = 'active'`      | 23505  |
--   | 749  active row    -> live-holder, `status = 'cancelled'`   | GL042  |
--
-- Read them against the three readings:
--   * "the TARGET decides" — X holds a live membership in both, so it predicts
--     23505 for both. 749 refutes it.
--   * "the SOURCE ROW AS IT WAS decides" — Q is cancelled and L is active, so it
--     predicts GL042 at 745 and 23505 at 749. Both refute it — it predicts the
--     exact inverse of the truth.
--   * "the TUPLE BEING STORED decides" — 745 stores an `active` tuple pointed at
--     a member who already has one (23505); 749 stores a `cancelled` tuple, which
--     the partial index does not cover at all (GL042). Only this one survives.
-- No implementation, spec draft or handler can satisfy two of those three.
--
-- WHY THE CONTROLS AT 743 AND 747 ARE NOT DECORATION. They are word for word
-- the two statements above with the `status = …` clause deleted and nothing
-- else changed — same source rows, same target member X, same session. Their
-- answers are the EXACT INVERSE of the pair's: 743 (cancelled row, no status
-- write) is GL042 where 745 is 23505, and 747 (active row, no status write) is
-- 23505 where 749 is GL042. That inversion is the whole finding. Without the
-- controls, 745 and 749 would be two ordinary assertions consistent with the
-- source-decides reading that Section 34's own 734/740 pair established; WITH
-- them, the same two source rows give opposite answers depending only on the
-- status the statement writes, which no reading about a ROW — either row — can
-- account for. The controls are also what proves the pair is about the status
-- write and nothing else: four statements, one clause of difference between
-- each pair, two answers each way.
--
-- 749 MAKES A STATUS TRANSITION AND IT IS DELIBERATELY A LEGAL ONE.
-- `active -> cancelled` is permitted (Section 29's transcription of the
-- membership state machine: `active -> frozen|cancelled|expired`), so GL047 has
-- nothing to say about it and cannot be what answers. Had it been an illegal
-- transition, GL042 would still be the required answer — GL042 beats GL047 by
-- this requirement — but the assertion would no longer be able to distinguish
-- "GL042 answered" from "GL047 was never reached", and this section's whole
-- point is distinguishing things. 745's transition (`cancelled -> active`) IS
-- illegal, and that is fine and unavoidable: the index refuses it as the tuple
-- is stored, which is before any AFTER trigger exists to run, so GL047 never
-- gets the chance either way. There is no legal transition INTO the live set
-- from a status outside it that would let 745 be staged any other way.
--
-- GROUP 3 — A FOREIGN KEY POINTING AT `memberships` (753). The contract decides
-- that GL042 answers ahead of the other rules in its own trigger and ahead of
-- GL047, and it decides NOTHING ELSE — in particular it makes no claim about a
-- foreign key pointing AT this table. `attendance`, `membership_pauses`,
-- `payments` and `memberships.renewal_of_membership_id` all reference
-- `memberships(tenant_id, id)`, so changing the REFERENCED key can be refused by
-- any of them. F is given one child `payments` row (created, unpaid — no money
-- arrives, so the terms freeze is not engaged and only the rules this section is
-- about are in play), and 753 changes `member_id` AND `id` in one statement:
-- 23503 from `payments_membership_id_fkey`, not GL042. The referential check is
-- an internal constraint trigger, and those sort ahead of every trigger this
-- project names, so no rename and no clause move could ever put GL042 in front
-- of it. 751 is the control — the identical statement with the `id` write
-- deleted, so the child still points at a row that exists and GL042 is the only
-- thing left. Without it, 753 would pass just as happily against an
-- implementation where GL042 had stopped existing.
--
-- GROUP 4 — THE SILENT SUCCESS (755-757). The row-security policy's USING clause
-- is a row FILTER, not a refusal. A session whose tenant claim names another gym
-- gets `UPDATE 0` and NO EXCEPTION, and a caller coded against this requirement
-- reads a zero row count as success. `lives_ok` ALONE WOULD BE A FALSE GREEN
-- HERE — it passes identically if the update raised nothing because it matched
-- nothing and if it raised nothing because it LANDED. So 756 re-runs the same
-- statement inside a data-modifying CTE and asserts the affected row count is
-- exactly 0, and 757 asserts the membership itself is untouched. The three
-- together say what the contract says: nothing raised, nothing matched, nothing
-- moved. 28b is a real gym with a real branch and a real front-desk staff row,
-- so the session at 755 is an ordinary well-formed front-desk session of ANOTHER
-- gym rather than a malformed claim that might be refused for some other reason.
--
-- FIXTURES. A holds L (active) and Q (cancelled) — one live each, so the partial
-- index is satisfied at fixture time. Q is CREATED cancelled rather than
-- transitioned into it, since GL047 refuses that transition and staging it by
-- hand would be staging through a rule. X holds one active membership of his
-- own: that is what makes the index able to bite at all, and it is the same
-- target in all four of 743/745/747/749 so nothing but the statement differs
-- between them. B holds F, the group-3 source, kept off A and X so that F being
-- active does not collide with L or XL. T1, T2 and T3 hold NOTHING, one target
-- per attempt, so no control can be answered by the live index while reporting a
-- false green and no attempt that unexpectedly LANDS can turn the next one into
-- a same-value write refused by nothing.
--
-- ADR-039: every date is the gym's own today, never current_date. ADR-030:
-- nothing is committed; the file's single BEGIN … ROLLBACK covers it.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000280001'::uuid, 'PayRec Gym 28', 'PYR22V'),
  -- 28b: nothing of this section's subject matter is ever inserted into it. It
  -- exists so that 755 can be sent from a coherent front-desk session belonging
  -- to a REAL other gym, rather than from a claim naming a tenant that does not
  -- exist — which could be filtered away for a reason that is not the policy.
  ('22000000-0000-4000-8000-000000280002'::uuid, 'PayRec Gym 28b', 'PYR22W');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000280011'::uuid, '22000000-0000-4000-8000-000000280001'::uuid, 'G28 Main', true),
  ('22000000-0000-4000-8000-000000280012'::uuid, '22000000-0000-4000-8000-000000280002'::uuid, 'G28b Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000280021'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'front_desk', 'T28 Desk'),
  ('22000000-0000-4000-8000-000000280022'::uuid, '22000000-0000-4000-8000-000000280002'::uuid,
   '22000000-0000-4000-8000-000000280012'::uuid, 'front_desk', 'T28b Desk');

-- A holds L (active) and Q (cancelled). X holds one live membership of his own
-- and is the target of all four statements in the discriminating battery. B
-- holds F, which carries the child payment. T1/T2/T3 hold nothing.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000280041'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 A', '+912228000041'),
  ('22000000-0000-4000-8000-000000280043'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 X', '+912228000043'),
  ('22000000-0000-4000-8000-000000280045'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 B', '+912228000045'),
  ('22000000-0000-4000-8000-000000280051'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 T1', '+912228000051'),
  ('22000000-0000-4000-8000-000000280052'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 T2', '+912228000052'),
  ('22000000-0000-4000-8000-000000280053'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280011'::uuid, 'M28 T3', '+912228000053');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000280061'::uuid, '22000000-0000-4000-8000-000000280001'::uuid, 'G28 Plan (30d)', 30, 100000);

create temp table today_t28 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000280001'::uuid;
grant select on today_t28 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, cancelled_at) values
  -- L: active, A's. The source row of 747 (control) and 749 (discriminator),
  -- and the row group 4 attempts to re-point from another gym's session.
  ('22000000-0000-4000-8000-000000280081'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280041'::uuid, '22000000-0000-4000-8000-000000280061'::uuid,
   'active', (select d from today_t28), (select d from today_t28), 100000, null),
  -- Q: cancelled, A's, CREATED in that state — GL047 refuses cancelling into it
  -- by hand, and staging a fixture through a rule is staging nothing. The source
  -- row of 743 (control) and 745 (discriminator).
  ('22000000-0000-4000-8000-000000280082'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280041'::uuid, '22000000-0000-4000-8000-000000280061'::uuid,
   'cancelled', (select d from today_t28), (select d from today_t28), 100000, now()),
  -- XL: X's own live membership. Without it the partial index has no entry to
  -- collide with and none of the four statements below means anything.
  ('22000000-0000-4000-8000-000000280083'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280043'::uuid, '22000000-0000-4000-8000-000000280061'::uuid,
   'active', (select d from today_t28), (select d from today_t28), 100000, null),
  -- F: B's, active. The group-3 source, and the only membership here with a
  -- child row referencing it.
  ('22000000-0000-4000-8000-000000280084'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280045'::uuid, '22000000-0000-4000-8000-000000280061'::uuid,
   'active', (select d from today_t28), (select d from today_t28), 100000, null);

-- The child row of group 3. `created`, so no money has ARRIVED against F (only
-- paid, refunded and reversed count) and the terms freeze is not engaged —
-- leaving exactly GL042 and the referential integrity of F's own key in play.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id) values
  ('22000000-0000-4000-8000-000000280091'::uuid, '22000000-0000-4000-8000-000000280001'::uuid,
   '22000000-0000-4000-8000-000000280045'::uuid, '22000000-0000-4000-8000-000000280084'::uuid,
   50000, 'created', 'cash', '22000000-0000-4000-8000-000000280021'::uuid);

-- 742 — the whole fixture pinned before anything is attempted, because every
-- claim below depends on one of these being true: L is A's and ACTIVE (so the
-- tuple 749 stores differs from it in exactly the status), Q is A's and
-- CANCELLED (same, in the other direction), X holds exactly ONE live membership
-- (so the index certainly CAN answer), F is B's and active and carries exactly
-- one child payment (so 753's `id` write certainly CAN break a foreign key),
-- T1/T2/T3 hold NOTHING (so no control can be answered by the index while
-- reporting green), the id 753 moves F to does not already exist, and 28b does.
-- Verifying a no-op is not verifying: this file has been bitten once already by
-- a fixture id that did not match the row it meant.
select results_eq(
  $$ select (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000280081'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000280081'::uuid),
            (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000280082'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000280082'::uuid),
            (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000280084'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000280084'::uuid),
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280043'::uuid
                and x.status in ('active', 'frozen')),
            (select count(*)::int from public.payments p
              where p.membership_id = '22000000-0000-4000-8000-000000280084'::uuid),
            (select count(*)::int from public.memberships x
              where x.member_id in ('22000000-0000-4000-8000-000000280051'::uuid,
                                    '22000000-0000-4000-8000-000000280052'::uuid,
                                    '22000000-0000-4000-8000-000000280053'::uuid)),
            (select count(*)::int from public.memberships x
              where x.id = '22000000-0000-4000-8000-0000002800f1'::uuid),
            (select count(*)::int from public.organizations o
              where o.id = '22000000-0000-4000-8000-000000280002'::uuid) $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'active'::text,
             '22000000-0000-4000-8000-000000280041'::uuid, 'cancelled'::text,
             '22000000-0000-4000-8000-000000280045'::uuid, 'active'::text,
             1, 1, 0, 0, 1) $$,
  'discriminating fixture: L is A''s and ACTIVE, Q is A''s and CANCELLED, F is B''s and active with exactly one child payment, X holds exactly ONE live membership, T1-T3 hold NOTHING, the id 753 moves F to does not exist, and gym 28b does'
);

-- ---------------------------------------------------------------------------
-- THE DISCRIMINATING PAIR (745, 749) AND ITS CONTROLS (743, 747).
--
-- Four statements. All four re-point a membership at X, who holds a live one.
-- 743 and 745 both move Q, the CANCELLED row, and differ ONLY in whether the
-- statement also writes `status = 'active'`. 747 and 749 both move L, the ACTIVE
-- row, and differ ONLY in whether the statement also writes `status =
-- 'cancelled'`. The four answers are GL042, 23505, 23505, GL042 — the status
-- write inverts the answer in BOTH directions, which is a fact about the tuple
-- being stored and cannot be a fact about either row.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 743 — CONTROL for 745. Q, the cancelled row, pointed at X, who holds a live
-- membership. No status is written, so the tuple stored is still `cancelled`,
-- which the partial index does not cover: the index has nothing to say and GL042
-- answers. This is the assertion every earlier round wrote, and on its own it is
-- consistent with all three readings.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000280043'::uuid
   where id = '22000000-0000-4000-8000-000000280082'::uuid
$$, 'GL042'::char(5), null,
  'control for the pair: a CANCELLED membership pointed at a live-holder with NO status written stays outside the partial index, so the member_id rule answers — GL042');

set local role postgres;

-- 744
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280082'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'cancelled'::text, 1) $$,
  'and the membership is unchanged after it — still A''s, still cancelled, and X still holds exactly the one membership he came with');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 745 — HALF ONE OF THE DISCRIMINATING PAIR. Word for word 743 with
-- `status = 'active'` added and nothing else changed. The row being moved is
-- still cancelled and the target still holds a live membership, so "the source
-- decides" predicts GL042 and "the target decides" predicts 23505 — but what is
-- actually stored is an ACTIVE tuple pointed at a member who already has one,
-- and the partial index is evaluated against THAT. 23505.
--
-- `cancelled -> active` is an illegal transition and GL047 is not what answers:
-- the index refuses the tuple as it is stored, which is before any AFTER trigger
-- runs. It cannot be staged as a legal transition, because no status outside the
-- live set moves legally into it.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000280043'::uuid,
         status = 'active'
   where id = '22000000-0000-4000-8000-000000280082'::uuid
$$, '23505'::char(5), null,
  'THE PAIR, half one: a CANCELLED membership pointed at a live-holder WHILE the same statement writes status = active is 23505 — the partial index is evaluated against the tuple being STORED, so the row''s own cancelled state does not take it out of the index when the statement puts it back in');

set local role postgres;

-- 746
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280082'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'cancelled'::text, 1) $$,
  'and neither half of it landed — the membership is still A''s and still cancelled, and X still holds exactly one');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 747 — CONTROL for 749. L, the active row, pointed at the same X. No status is
-- written, so the tuple stored is still `active` and collides in the partial
-- index: 23505. The other assertion every earlier round wrote, and also
-- consistent with all three readings on its own.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000280043'::uuid
   where id = '22000000-0000-4000-8000-000000280081'::uuid
$$, '23505'::char(5), null,
  'control for the pair: an ACTIVE membership pointed at a live-holder with NO status written stays inside the partial index, so the index answers — 23505');

set local role postgres;

-- 748
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'active'::text, 1) $$,
  'and the membership is unchanged after it — still A''s, still active, and X still holds exactly the one membership he came with');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 749 — HALF TWO OF THE DISCRIMINATING PAIR, AND THE ASSERTION THAT KILLS THE
-- OTHER TWO READINGS OUTRIGHT. Word for word 747 with `status = 'cancelled'`
-- added and nothing else changed. The row being moved is live and the target
-- holds a live one, so "the source decides" AND "the target decides" both
-- predict 23505 — and the tuple actually stored is `cancelled`, which the
-- partial index does not cover, so the index has no entry to collide with and
-- GL042 answers.
--
-- `active -> cancelled` IS A LEGAL TRANSITION, deliberately. GL047 therefore has
-- nothing to say here, so a GREEN cannot be explained by GL047 having been
-- reached and the assertion measures exactly what it claims to.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000280043'::uuid,
         status = 'cancelled'
   where id = '22000000-0000-4000-8000-000000280081'::uuid
$$, 'GL042'::char(5), null,
  'THE PAIR, half two: an ACTIVE membership pointed at a live-holder WHILE the same statement writes status = cancelled (a LEGAL transition, so GL047 is not what answers) is GL042, not 23505 — the tuple being stored is retired and the partial index does not cover it, which no reading about the source row or the target member can produce');

set local role postgres;

-- 750
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'active'::text, 1) $$,
  'and neither half of it landed — the membership is still A''s and still ACTIVE, so the status write was refused with the re-point rather than applied beside it');

-- ---------------------------------------------------------------------------
-- GROUP 3 — A FOREIGN KEY POINTING AT `memberships`. The contract decides that
-- GL042 answers ahead of GL043-GL047 and decides nothing else; a child row
-- referencing this membership's key is outside that claim entirely.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 751 — CONTROL for 753. The identical statement with the `id` write deleted, so
-- F keeps the key its child payment references and no foreign key has anything
-- to say. T1 holds nothing, so the live index has nothing to say either. GL042
-- is the only thing left. Without this, 753 would pass identically against an
-- implementation in which GL042 had stopped refusing anything at all, or in
-- which the re-point half had been silently accepted.
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000280051'::uuid
   where id = '22000000-0000-4000-8000-000000280084'::uuid
$$, 'GL042'::char(5), null,
  'control for the foreign-key case: re-pointing a membership WITHOUT touching its own id leaves its child payment pointing at a key that still exists, so the member_id rule answers — GL042');

set local role postgres;

-- 752
select results_eq(
  $$ select m.member_id, m.id,
            (select count(*)::int from public.payments p
              where p.membership_id = '22000000-0000-4000-8000-000000280084'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280084'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280045'::uuid, '22000000-0000-4000-8000-000000280084'::uuid, 1) $$,
  'and the membership is unchanged after it — still B''s, still its own id, and its child payment still points at it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280021')::text,
  true);
set local role authenticated;

-- 753 — THE FOREIGN KEY POINTING AT THIS TABLE. The same statement, now also
-- moving F's own `id`. Its child payment references `memberships(tenant_id, id)`
-- (composite since ADR-052), so the new key leaves that reference dangling and
-- `payments_membership_id_fkey` refuses the statement with 23503. The
-- referential check is an internal constraint trigger and those sort ahead of
-- every trigger this project names, so GL042 cannot be put in front of it by any
-- rename or clause move — which is exactly why the contract does not claim it.
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000280052'::uuid,
         id = '22000000-0000-4000-8000-0000002800f1'::uuid
   where id = '22000000-0000-4000-8000-000000280084'::uuid
$$, '23503'::char(5), null,
  'GL042 does not answer ahead of a foreign key pointing AT memberships: re-pointing a membership while also moving its own id comes back 23503 from payments_membership_id_fkey, not GL042 — the contract''s ordering claim covers the rules in its own trigger and GL047, and nothing else');

set local role postgres;

-- 754
select results_eq(
  $$ select m.member_id, m.id,
            (select count(*)::int from public.payments p
              where p.membership_id = '22000000-0000-4000-8000-000000280084'::uuid),
            (select count(*)::int from public.memberships x
              where x.id = '22000000-0000-4000-8000-0000002800f1'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280084'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280045'::uuid, '22000000-0000-4000-8000-000000280084'::uuid, 1, 0) $$,
  'and neither half of it landed — the membership is still B''s under its original id, its child payment still points at it, and the id it was moved to does not exist');

-- ---------------------------------------------------------------------------
-- GROUP 4 — THE SILENT SUCCESS. The policy's USING clause is a row filter, not a
-- refusal: another gym's session gets UPDATE 0 and no exception. This is the one
-- kind of session the requirement's "any session" does not actually bind, and a
-- caller reads a zero row count as success.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000280002',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000280022')::text,
  true);
set local role authenticated;

-- 755 — an ordinary, well-formed front-desk session of gym 28b re-points gym
-- 28's membership L at gym 28's member T3. Nothing is raised. Not GL042, not
-- 42501, not anything: the row is filtered away by memberships_tenant_write's
-- USING before there is a row to refuse.
select lives_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000280053'::uuid
   where id = '22000000-0000-4000-8000-000000280081'::uuid
$$, 'a session whose tenant claim names another gym raises NOTHING when it re-points a membership — the row-security policy''s USING clause is a filter, not a refusal');

-- 756 — AND THIS IS WHY 755 ALONE WOULD BE A FALSE GREEN. `lives_ok` passes
-- identically whether the update matched nothing or LANDED, and "it landed" is
-- the harm the requirement exists to prevent. The same statement is re-run
-- inside a data-modifying CTE and its affected row count asserted to be exactly
-- zero, which is the fact that separates "silently filtered" from "silently
-- succeeded".
with u as (
  update public.memberships set member_id = '22000000-0000-4000-8000-000000280053'::uuid
   where id = '22000000-0000-4000-8000-000000280081'::uuid
  returning 1
), c as (select count(*)::int as n from u)
select is(c.n, 0,
  'and it affected ZERO rows — the outcome is UPDATE 0, not a refusal and not a change, so a caller coded against this requirement reads success where nothing happened') from c;

set local role postgres;

-- 757
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000280053'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000280081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000280041'::uuid, 'active'::text, 0) $$,
  'and the membership is unchanged after both of them — still A''s, still active, and T3 still holds nothing'
);


-- ===========================================================================
-- SECTION 36 (ROUND TWENTY-TWO) — A CHECK CONSTRAINT BEATS BOTH HALVES OF THE
-- PARTITION, and the two things that decide 23505 are two things. Tenant 29.
-- Assertions 758-782.
--
-- WHY THIS SECTION EXISTS. The two scenarios that partition a re-point by the
-- status the statement leaves behind — 23505 when it leaves the membership
-- `active` or `frozen`, GL042 when it leaves it `pending`, `expired` or
-- `cancelled` — both carry the guard "AND the resulting row satisfies the
-- table's CHECK constraints", and that guard is load-bearing. A CHECK is
-- evaluated against the tuple being stored BEFORE index insertion and BEFORE
-- every AFTER trigger, so where one bites it beats the index AND the rule, and
-- neither scenario's promised answer arrives.
--
-- One shape does it: a `pending` membership with BOTH dates null.
-- `memberships_dated_unless_pending_chk` is
-- `status = 'pending' OR (starts_on IS NOT NULL AND ends_on IS NOT NULL)`
-- (read from pg_constraint, and already pinned at assertion 72), so writing ANY
-- other status onto such a row leaves a tuple the CHECK refuses whatever else
-- the statement does. It is not a contrived shape: it is exactly what a
-- membership looks like between being sold and being paid for (ADR-083), it is
-- what `seed-scenarios.sql` leaves live in the demo gym, and assertion 644 in
-- this file already measures the same CHECK answering a plain hand-cancellation
-- of one.
--
-- GROUPS 1 AND 2 — THE FOUR NON-PENDING STATUSES, TWICE OVER (759-774). One
-- source row P (A's, pending, both dates null) is re-pointed at a member and the
-- same statement writes a status. Eight statements: four statuses x two targets.
--   * 759-766 point P at X, who HOLDS A LIVE MEMBERSHIP. Without the CHECK,
--     `active` and `frozen` here are the first scenario exactly and would be
--     23505.
--   * 767-774 point P at T1, who HOLDS NOTHING. Without the CHECK, the live
--     index has no entry to collide with at any status and all four would be
--     GL042.
-- The two targets predict DIFFERENT answers under those scenarios and the SAME
-- answer under this one, which is the only reason to write it twice: asserting
-- one target alone cannot tell a reader whether the CHECK answered or whether
-- the index (or the rule) happened to give the same code. Asserting both, and
-- getting 23514 eight times, can only be the CHECK.
--
-- GROUP 3 — THE CONTROLS (775-778), and they are not decoration. They are word
-- for word 759 with the status write changed to `pending` (775) and deleted
-- entirely (777), same source row, same target X, same session. Both come back
-- GL042. That is what proves two things at once: P is otherwise re-pointable —
-- the statement reaches GL042 rather than dying of something about P — and the
-- 23514 above is caused by the STATUS WRITE and by nothing else in the
-- statement. They are sent at X, the live-holder, deliberately: X is the target
-- where a second mechanism could plausibly have answered, so GL042 there also
-- re-proves that a `pending` tuple falls outside the partial index. Against T1
-- the same control could only ever be GL042 and would prove less.
--
-- GROUP 4 — THE TWO-PART CLAIM (779-782). The requirement says two separate
-- things decide a 23505: the TUPLE BEING STORED decides whether the row falls
-- inside the partial index's predicate at all, and the TARGET MEMBER'S OTHER
-- ROWS decide whether there is then anything to collide with. Section 35's
-- discriminating pair pinned the first half — same row, same target, the status
-- write inverting the answer. This pair pins the SECOND half, which nothing yet
-- isolates: D is a fully dated ACTIVE membership, no status is written in either
-- statement, so the tuple stored is `active` and inside the predicate both
-- times. The ONLY difference between 779 and 781 is which member the statement
-- names — X, who holds a live one (23505), or T2, who holds nothing (GL042).
-- Section 35's 747 and 751 are the same two answers but from DIFFERENT source
-- rows, with a child payment on one of them, so neither of them isolates the
-- target as the single variable. These two do.
--
-- FIXTURES. P is CREATED null-dated and pending rather than emptied into that
-- state, because GL045 refuses typing a date and there is no other way in. XL
-- gives X the live membership without which the index cannot bite. T1 and T2
-- hold NOTHING and are separate members, one per group, so that a statement
-- which unexpectedly LANDS cannot leave the next group's target holding
-- something and turn its assertion green for the wrong reason. D is B's rather
-- than A's only so the prose can name its owner without ambiguity. Every
-- refusal is followed by a results_eq re-reading the row, because throws_ok
-- proves an exception was raised and not that nothing moved.
--
-- ADR-039: every date is the gym's own today, never current_date. ADR-030:
-- nothing is committed; the file's single BEGIN … ROLLBACK covers it.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000290001'::uuid, 'PayRec Gym 29', 'PYR22Z');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000290011'::uuid, '22000000-0000-4000-8000-000000290001'::uuid, 'G29 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000290021'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'front_desk', 'T29 Desk');

-- A holds P, the null-dated pending source of groups 1-3. B holds D, the fully
-- dated active source of group 4. X holds one live membership and is the
-- live-holding target of groups 1, 3 and 4. T1 and T2 hold nothing.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000290041'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'M29 A', '+912229000041'),
  ('22000000-0000-4000-8000-000000290043'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'M29 X', '+912229000043'),
  ('22000000-0000-4000-8000-000000290045'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'M29 B', '+912229000045'),
  ('22000000-0000-4000-8000-000000290051'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'M29 T1', '+912229000051'),
  ('22000000-0000-4000-8000-000000290052'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290011'::uuid, 'M29 T2', '+912229000052');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000290061'::uuid, '22000000-0000-4000-8000-000000290001'::uuid, 'G29 Plan (30d)', 30, 100000);

create temp table today_t29 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000290001'::uuid;
grant select on today_t29 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  -- P: A's, pending, BOTH dates null — the only shape
  -- memberships_dated_unless_pending_chk permits with a null date, and the shape
  -- a membership has between being sold and being paid for. Source of 759-778.
  ('22000000-0000-4000-8000-000000290081'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290041'::uuid, '22000000-0000-4000-8000-000000290061'::uuid,
   'pending', null, null, 100000),
  -- XL: X's own live membership. Without it the partial index has no entry to
  -- collide with and neither 779 nor the two scenarios this section guards mean
  -- anything.
  ('22000000-0000-4000-8000-000000290083'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290043'::uuid, '22000000-0000-4000-8000-000000290061'::uuid,
   'active', (select d from today_t29), (select d from today_t29), 100000),
  -- D: B's, active, FULLY DATED — so no CHECK on this table has anything to say
  -- about either statement in group 4 and the target is the only variable left.
  ('22000000-0000-4000-8000-000000290084'::uuid, '22000000-0000-4000-8000-000000290001'::uuid,
   '22000000-0000-4000-8000-000000290045'::uuid, '22000000-0000-4000-8000-000000290061'::uuid,
   'active', (select d from today_t29), (select d from today_t29), 100000);

-- 758 — the fixture pinned before anything is attempted. Every claim below
-- depends on one of these: P is A's, pending, and BOTH its dates are null (so
-- the CHECK certainly CAN bite), D is B's, active, and BOTH its dates are set
-- (so the CHECK certainly CANNOT), X holds exactly ONE live membership (so the
-- index certainly CAN answer), and T1 and T2 hold NOTHING (so it certainly
-- cannot answer for them). Verifying a no-op is not verifying.
select results_eq(
  $$ select (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid),
            (select (m.starts_on is null and m.ends_on is null) from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid),
            (select m.member_id from public.memberships m where m.id = '22000000-0000-4000-8000-000000290084'::uuid),
            (select m.status::text from public.memberships m where m.id = '22000000-0000-4000-8000-000000290084'::uuid),
            (select (m.starts_on is not null and m.ends_on is not null) from public.memberships m where m.id = '22000000-0000-4000-8000-000000290084'::uuid),
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid
                and x.status in ('active', 'frozen')),
            (select count(*)::int from public.memberships x
              where x.member_id in ('22000000-0000-4000-8000-000000290051'::uuid,
                                    '22000000-0000-4000-8000-000000290052'::uuid)) $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, true,
             '22000000-0000-4000-8000-000000290045'::uuid, 'active'::text, true,
             1, 0) $$,
  'guarded fixture: P is A''s and pending with BOTH dates null, D is B''s and active with BOTH dates set, X holds exactly ONE live membership, and T1 and T2 hold NOTHING'
);

-- ---------------------------------------------------------------------------
-- GROUP 1 (759-766) — THE FOUR NON-PENDING STATUSES, POINTED AT A MEMBER WHO
-- HOLDS A LIVE MEMBERSHIP. Under the first scenario, `active` and `frozen` here
-- would be 23505 and the other two would be GL042. They are all four 23514: the
-- CHECK is evaluated on the tuple being stored, which is before index insertion
-- and before every AFTER trigger, so nothing downstream of it is ever reached.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000290001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000290021')::text,
  true);
-- The claim is set once for the whole section: `set_config(..., true)` is
-- transaction-local and `set local role` touches only `role`, so every
-- `set local role authenticated` below re-enters this same front-desk session.
set local role authenticated;

-- 759
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290043'::uuid,
         status = 'active'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'a null-dated PENDING membership re-pointed at a LIVE-HOLDER while the same statement writes status = active is 23514 from memberships_dated_unless_pending_chk — NOT the 23505 the live index would give, because a CHECK is evaluated on the tuple being stored and beats index insertion and every AFTER trigger');

set local role postgres;

-- 760
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly the one membership he came with');

set local role authenticated;

-- 761
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290043'::uuid,
         status = 'frozen'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'the same statement writing status = frozen — the other half of the live set, and the other status the first scenario promises 23505 for — is also 23514');

set local role postgres;

-- 762
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly one');

set local role authenticated;

-- 763
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290043'::uuid,
         status = 'cancelled'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'the same statement writing status = cancelled — which the second scenario promises GL042 for, since a cancelled tuple is outside the partial index — is 23514 as well: the CHECK does not care which side of the partition the status falls on, only that it is not pending');

set local role postgres;

-- 764
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly one');

set local role authenticated;

-- 765
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290043'::uuid,
         status = 'expired'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'and the fourth non-pending status, expired, completes the set — all four are 23514 against a live-holding target, so neither scenario''s answer is ever reached for this shape');

set local role postgres;

-- 766
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly one');

-- ---------------------------------------------------------------------------
-- GROUP 2 (767-774) — THE IDENTICAL FOUR, POINTED AT A MEMBER WHO HOLDS
-- NOTHING. T1 has no membership at all, so the live index cannot answer at ANY
-- status and every one of these would be GL042 if the CHECK were not there.
-- Group 1 and group 2 predict different answers under the two scenarios and the
-- same answer under the CHECK; that is the whole reason both are written. One
-- group alone leaves a reader unable to say which mechanism replied.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 767
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290051'::uuid,
         status = 'active'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'the same null-dated PENDING membership re-pointed at a member who HOLDS NOTHING while writing status = active is 23514 too — the live index has no entry to collide with here, so this one cannot be the index answering under another name');

set local role postgres;

-- 768
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290051'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 0) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and T1 still holds nothing');

set local role authenticated;

-- 769
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290051'::uuid,
         status = 'frozen'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'status = frozen at a target holding nothing — 23514, where the second half of the first scenario would have given 23505 only if there were something to collide with, and there is not');

set local role postgres;

-- 770
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290051'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 0) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and T1 still holds nothing');

set local role authenticated;

-- 771
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290051'::uuid,
         status = 'cancelled'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'status = cancelled at a target holding nothing — 23514, where the member_id rule would have answered had the row been datable');

set local role postgres;

-- 772
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290051'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 0) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and T1 still holds nothing');

set local role authenticated;

-- 773
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290051'::uuid,
         status = 'expired'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, '23514'::char(5), null,
  'status = expired at a target holding nothing — 23514, completing the second four: the answer is the same across both targets and all four statuses, which is a fact about the tuple''s own shape and cannot be a fact about the target''s other rows');

set local role postgres;

-- 774
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290051'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 0) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and T1 still holds nothing');

-- ---------------------------------------------------------------------------
-- GROUP 3 (775-778) — THE CONTROLS. Word for word 759 with the status write
-- changed to `pending` and then deleted outright: same source row P, same target
-- X, same session, nothing else touched. Both are GL042, which says P is
-- otherwise re-pointable and reaches the member_id rule, and says the 23514
-- above is caused by the status write and by nothing else about these
-- statements. Sent at X rather than T1 on purpose: X is the target where a
-- second mechanism could have answered, so GL042 here also re-proves that a
-- `pending` tuple falls outside the partial index.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 775
select throws_ok($$
  update public.memberships
     set member_id = '22000000-0000-4000-8000-000000290043'::uuid,
         status = 'pending'
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, 'GL042'::char(5), null,
  'CONTROL: 759 with status = pending instead of active — the tuple stored still satisfies memberships_dated_unless_pending_chk and still falls outside the partial index, so the member_id rule answers with GL042 even though the target holds a live membership');

set local role postgres;

-- 776
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly one');

set local role authenticated;

-- 777
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000290043'::uuid
   where id = '22000000-0000-4000-8000-000000290081'::uuid
$$, 'GL042'::char(5), null,
  'CONTROL: 759 with the status write deleted entirely — a statement that writes no status keeps the row''s pending status, the CHECK is satisfied, the index does not cover the tuple, and GL042 answers. The 23514 group is therefore about the status write and about nothing else');

set local role postgres;

-- 778
select results_eq(
  $$ select m.member_id, m.status::text, m.starts_on, m.ends_on,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290081'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290041'::uuid, 'pending'::text, null::date, null::date, 1) $$,
  'and the membership is unchanged after it — still A''s, still pending, still null-dated, and X still holds exactly one');

-- ---------------------------------------------------------------------------
-- GROUP 4 (779-782) — THE SECOND HALF OF THE TWO-PART CLAIM. Both statements
-- move D, a FULLY DATED ACTIVE membership, and neither writes a status — so the
-- tuple being stored is `active` in both, inside the partial index's predicate
-- in both, and no CHECK on this table has anything to say about either. The only
-- difference is which member is named. X holds a live membership and there is
-- something to collide with (23505); T2 holds nothing and there is not, so the
-- rule answers (GL042). Same source row, same absent status write, one variable.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 779
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000290043'::uuid
   where id = '22000000-0000-4000-8000-000000290084'::uuid
$$, '23505'::char(5), null,
  'THE TARGET HALF, one: a fully dated ACTIVE membership re-pointed at a member who ALREADY HOLDS a live one, with no status written, is 23505 — the tuple stored is inside the partial index and the target supplies the row it collides with');

set local role postgres;

-- 780
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290043'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290084'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290045'::uuid, 'active'::text, 1) $$,
  'and the membership is unchanged after it — still B''s, still active, and X still holds exactly the one membership he came with');

set local role authenticated;

-- 781
select throws_ok($$
  update public.memberships set member_id = '22000000-0000-4000-8000-000000290052'::uuid
   where id = '22000000-0000-4000-8000-000000290084'::uuid
$$, 'GL042'::char(5), null,
  'THE TARGET HALF, two: the SAME row, the SAME absent status write, pointed at a member who HOLDS NOTHING is GL042 — the tuple is still inside the index''s predicate, so being inside it is not sufficient: the target''s other rows decide whether there is anything to collide with, and only when both hold is the answer 23505');

set local role postgres;

-- 782
select results_eq(
  $$ select m.member_id, m.status::text,
            (select count(*)::int from public.memberships x
              where x.member_id = '22000000-0000-4000-8000-000000290052'::uuid)
       from public.memberships m where m.id = '22000000-0000-4000-8000-000000290084'::uuid $$,
  $$ values ('22000000-0000-4000-8000-000000290045'::uuid, 'active'::text, 0) $$,
  'and the membership is unchanged after it — still B''s, still active, and T2 still holds nothing'
);

-- ===========================================================================
-- SECTION 37 (ROUND TWENTY-THREE, contract `membership-creation`) — "THE FIRST
-- PERIOD IS SET, NOT ADDED." Tenant 30. Assertions 783-805.
--
-- WHAT THE REQUIREMENT SAYS, IN ITS OWN TERMS. `app.grant_periods()` computes
-- `ends_on = greatest(ends_on, today) + duration x periods`. It MUST add — that
-- is what a renewal is. But WHERE A MEMBERSHIP HAS BEEN GRANTED NO PERIODS, any
-- span the row carries was TYPED and not BOUGHT, and adding a bought period on
-- top of a typed one hands the typed one out free. So on a first grant the span
-- is SET from the plan rather than extended, and the row is started at THE
-- LATER OF ITS `starts_on` AND TODAY.
--
-- THE MEASURED DEFECT THIS SECTION IS BUILT AROUND. Ordinary front desk, two
-- ordinary statements: create a membership dated `today … today + 30` on a
-- 30-day plan, record ONE payment of the plan's own price, and the span becomes
-- SIXTY DAYS with `periods_granted = 1`. One period of money buying two, and
-- every audit invariant this file already pins is intact while it happens — one
-- payment, one receipt, `periods_granted = floor(money / price)`, the
-- membership's own price on the row, no frozen term touched. The ONLY number
-- that disagrees is `ends_on - starts_on` against `duration_days x
-- periods_granted`, and ADR-088 declined to make that an invariant, for reasons
-- that are still right. Nothing in this system compares those two numbers,
-- which is precisely why nothing in this system noticed. Assertion 800 compares
-- them, once, across every path this section builds.
--
-- WHAT IS *NOT* ASSERTED HERE, STATED SO IT IS NOT MISREAD AS AN OVERSIGHT. An
-- earlier draft of this contract carried a second requirement — a membership is
-- created with at most the one period it is sold, answered `GL048`. It has been
-- WITHDRAWN and struck, refuted by its own implementation: spliced into all 47
-- pgTAP files it blocked SIX of them outright and failed four assertions in a
-- seventh, because fixtures in six independently-authored files create
-- memberships spanning more than one period directly. Six files by different
-- authors at different times are not six mistakes. THERE IS NO `GL048`. Nothing
-- below asserts one, and nothing below asserts anything about what a membership
-- may be CREATED as — every fixture here is created freely and the rule under
-- test acts at the moment money lands. That is the whole point of the split:
-- the creation rule would have been keyed on what a writer may TYPE, and this
-- one is keyed on what has actually been PAID FOR, which no `alter table …
-- disable trigger` window in `seed.sql` can switch off because it IS the
-- granting rule.
--
-- WHY THE `starts_on` HALF NEEDED DECIDING AT ALL. "Set the span" fixes a
-- LENGTH and not a POSITION, and three readings satisfy the headline scenario
-- identically because in it `starts_on` is already today. They differ by up to
-- a hundred days on two real shapes, at a gate that admits on dates (ADR-084),
-- with GL045 making whatever lands permanent. Groups 2 and 3 are those two
-- shapes and they exist to separate the readings:
--   * PRE-SOLD (group 2) — starts next Monday. Keeping `starts_on` gives
--     Mon … Mon+30. Moving both to today gives a free week before Monday.
--   * LAPSED (group 3) — started and ended in the past. Keeping `starts_on`
--     leaves a member who just paid holding a membership that expired last
--     month: PAID FOR NOTHING. Moving both to today gives today … today+30.
-- "The later of its `starts_on` and today" is the one reading that answers both
-- correctly, and a THIRD reading — keep `starts_on`, floor only `ends_on` — is
-- what the first implementation did and gives the returning member a 61-DAY
-- SPAN for one month's money: the same defect from the other side. Group 3
-- catches exactly that, and it is the only group that does.
--
-- THE CONTROLS, AND WHY THREE OF THEM. This project has three times this phase
-- shipped a fix that was correct on the harm and too broad on the permitted
-- side, so the permitted side is asserted at the same weight as the harm:
--   * GROUP 4, THE RENEWAL — THE MOST IMPORTANT ASSERTION IN THIS SECTION. A
--     membership that has ALREADY BEEN GRANTED A PERIOD, paid again, must
--     EXTEND, because extending is what a renewal IS. It is built by paying a
--     dateless membership twice rather than by typing `periods_granted = 1`
--     into a fixture, because GL044 refuses a hand-written count at creation
--     (assertion 166) — so the first payment EARNS the state the second one is
--     tested against. Both halves are GREEN TODAY and must both still be green
--     afterwards. A fix that reads "always set, never add" passes every red
--     assertion in this section and fails 793, and 793 alone.
--   * GROUP 5, THE ORDINARY DATELESS PATH — the product's own answer today
--     (Section 9, assertion 69) and the yardstick the contract measures the
--     defect against: the same payment gives 30 days here and 60 days at the
--     headline. Green today, green afterwards.
--   * GROUP 6, THE CONSOLE'S ZERO-SPAN SHAPE — `starts_on = ends_on = today`,
--     the shape assertion 170 already pins, and the shape a correct fix leaves
--     numerically untouched (`greatest(today, today) + 30` and
--     `today + 30 x 1` are the same date). It is here because it is the one
--     dated first-grant path that is ALREADY right, and a fix that changed it
--     would be changing the console's own behaviour by accident.
--
-- GROUP 7 is the arithmetic rather than the boundary: ONE payment worth TWO
-- periods against a typed span. `duration x periods` has to be the multiplier
-- on a first grant too, not a single period plus whatever was typed — measured
-- in the contract as span 60, two periods granted.
--
-- FIXTURES. Seven memberships, ONE MEMBER EACH, because
-- `memberships_tenant_id_member_id_live_key` allows a member only one live
-- membership and five of these seven are live simultaneously. The lapsed
-- membership at group 3 is `active` with both dates in the past — NOT
-- `expired` and NOT `cancelled` — for a measured reason: assertion 675 records
-- that `expired` is "the status the product itself never writes", and Section
-- 30 (682) records that a payment against a RETIRED membership grants nothing
-- and moves no date at all. A terminal fixture would make group 3 assert the
-- retirement rule instead of this one. Two memberships are created `pending`
-- with typed dates (P, the pre-sold one) or with none (D and R) and the rest
-- `active`; the status spread is deliberate, so that an implementation keyed on
-- STATUS rather than on `periods_granted = 0` splits this section's answers
-- instead of passing it. No fixture names `periods_granted` at all — GL044
-- (166) refuses a typed count — and none names `duration_days`, so 783 also
-- pins that the plan's 30 was copied onto every row, without which 800's
-- identity would be comparing against nothing.
--
-- ADR-039: every date below is derived from `today_t30`, the gym's OWN today
-- read through its timezone, never `current_date`. The org is IST; a UTC-dated
-- fixture produces a 31-day span where 30 was meant, and this project has
-- shipped that defect twice. ADR-030: nothing is committed; the file's single
-- BEGIN … ROLLBACK covers this section as it covers every other.
-- ===========================================================================

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('22000000-0000-4000-8000-000000300001'::uuid, 'PayRec Gym 30', 'PYR22A');

insert into public.branches (id, tenant_id, name, is_default) values
  ('22000000-0000-4000-8000-000000300011'::uuid, '22000000-0000-4000-8000-000000300001'::uuid, 'G30 Main', true);

-- payments_offline_has_staff_chk requires a staff attribution on every
-- non-razorpay payment, and every payment below is cash at the desk.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('22000000-0000-4000-8000-000000300021'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'front_desk', 'T30 Desk');

-- One member per membership: five of the seven memberships below are live at
-- the same moment and the live partial unique index permits one apiece.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000300041'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 H (headline)', '+912230000041'),
  ('22000000-0000-4000-8000-000000300042'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 P (pre-sold)', '+912230000042'),
  ('22000000-0000-4000-8000-000000300043'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 L (lapsed)', '+912230000043'),
  ('22000000-0000-4000-8000-000000300044'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 D (dateless)', '+912230000044'),
  ('22000000-0000-4000-8000-000000300045'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 C (console)', '+912230000045'),
  ('22000000-0000-4000-8000-000000300046'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 X2 (double)', '+912230000046'),
  ('22000000-0000-4000-8000-000000300047'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 R (renewal)', '+912230000047');

-- A plain 30-day plan at the plan's own list price, so that ONE payment of
-- 100000 is exactly ONE period and no part of this section turns on truncation
-- (Section 14 owns that) or on list-price-versus-membership-price (Section 8
-- owns that).
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('22000000-0000-4000-8000-000000300061'::uuid, '22000000-0000-4000-8000-000000300001'::uuid, 'G30 Plan (30d)', 30, 100000);

create temp table today_t30 as
  select (now() at time zone o.timezone)::date as d
    from public.organizations o where o.id = '22000000-0000-4000-8000-000000300001'::uuid;
grant select on today_t30 to public;

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  -- H (…081): THE HEADLINE. Dated exactly one period, on a one-period plan.
  -- The contract's two ordinary statements, shape one.
  ('22000000-0000-4000-8000-000000300081'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300041'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'active', (select d from today_t30), (select d from today_t30) + 30, 100000),
  -- P (…082): PRE-SOLD. Starts a week out; `pending` because a membership sold
  -- and not yet paid for is what pending means, and because the rule must be
  -- keyed on the COUNT rather than on the status.
  ('22000000-0000-4000-8000-000000300082'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300042'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'pending', (select d from today_t30) + 7, (select d from today_t30) + 37, 100000),
  -- L (…083): LAPSED. Started and ended in the past, and `active` rather than
  -- `expired`/`cancelled` on purpose — see the header: a terminal row grants
  -- nothing (Section 30, 682) and would test the wrong rule.
  ('22000000-0000-4000-8000-000000300083'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300043'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'active', (select d from today_t30) - 60, (select d from today_t30) - 30, 100000),
  -- D (…084): the ordinary dateless path, untouched control.
  ('22000000-0000-4000-8000-000000300084'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300044'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'pending', null, null, 100000),
  -- C (…085): the console's own zero-span shape, byte for byte the fixture
  -- assertion 168 creates. Untouched control.
  ('22000000-0000-4000-8000-000000300085'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300045'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'active', (select d from today_t30), (select d from today_t30), 100000),
  -- X2 (…086): a typed one-period span that will take TWO periods in a single
  -- payment, so the multiplier is asserted and not just the boundary.
  ('22000000-0000-4000-8000-000000300086'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300046'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'active', (select d from today_t30), (select d from today_t30) + 30, 100000),
  -- R (…087): the RENEWAL control. Created dateless and granted nothing; its
  -- first payment EARNS the period that its second payment is then tested
  -- against, because GL044 (166) refuses a count typed into a fixture.
  ('22000000-0000-4000-8000-000000300087'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300047'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'pending', null, null, 100000);

-- 783 — THE GUARDED FIXTURE. Every claim below is a claim about a CHANGE, and
-- a change can only be read against a starting point that was verified. Four
-- things are pinned here and each of them is load-bearing: the seven spans are
-- the seven shapes named above (so groups 1-3 really are the headline, the
-- pre-sold and the lapsed row and not three copies of one another); EVERY
-- `periods_granted` IS 0 (so every first grant below really is a FIRST grant,
-- which is the only condition the requirement is keyed on); every
-- `duration_days` is the plan's 30, copied by the product rather than typed
-- here (without which 800's identity compares against a default of 1); and
-- every price is 100000 (so one payment of 100000 is exactly one period and no
-- assertion below turns on truncation).
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted, duration_days, price_paise
       from public.memberships
      where tenant_id = '22000000-0000-4000-8000-000000300001'::uuid
      order by id $$,
  $$ values
      ('22000000-0000-4000-8000-000000300081'::uuid, (select d from today_t30), (select d from today_t30) + 30, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300082'::uuid, (select d from today_t30) + 7, (select d from today_t30) + 37, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300083'::uuid, (select d from today_t30) - 60, (select d from today_t30) - 30, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300084'::uuid, null::date, null::date, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300085'::uuid, (select d from today_t30), (select d from today_t30), 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300086'::uuid, (select d from today_t30), (select d from today_t30) + 30, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300087'::uuid, null::date, null::date, 0, 30, 100000::bigint) $$,
  'guarded fixture: seven memberships in the seven shapes this section needs, EVERY ONE of them granted nothing yet, every one carrying the plan''s own 30-day term and 100000 price'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '22000000-0000-4000-8000-000000300001',
                    'app_role', 'front_desk',
                    'staff_id', '22000000-0000-4000-8000-000000300021')::text,
  true);

-- ---------------------------------------------------------------------------
-- GROUP 1 (784-785) — THE HEADLINE. The contract's own measurement, reproduced
-- as the two ordinary statements it names: a membership dated `today …
-- today + 30` on a 30-day plan, and ONE payment of the plan's own price. Today
-- this leaves a SIXTY-day span with `periods_granted = 1` — one period of money
-- buying two, and nothing else on the row disagreeing.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 784
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301001'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300041'::uuid, '22000000-0000-4000-8000-000000300081'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'the headline, statement two: an ordinary front desk records one payment of the plan''s own price against a membership dated exactly one period. It is RECORDED — the requirement is about what the money BUYS, never about refusing the money');

set local role postgres;

-- 785 — THE HEADLINE ASSERTION. One period of money buys ONE period of gym.
-- The span the row was created carrying was TYPED and not BOUGHT, so the first
-- grant SETS it from the plan instead of adding to it. `starts_on` is the later
-- of its own value and today, and today they are the same date, which is
-- exactly why this assertion alone cannot decide where `starts_on` lands and
-- groups 2 and 3 exist.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300081'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 30, 1 $$,
  'THE HEADLINE: one payment of one period''s price against a membership dated exactly one period leaves it spanning ONE period — the first grant SET the span from the plan rather than extending the span nobody paid for'
);

-- ---------------------------------------------------------------------------
-- GROUP 2 (786-787) — PRE-SOLD, the first of the two shapes the `starts_on`
-- rule exists for. The membership starts NEXT WEEK and the member pays for it
-- today. `starts_on` is the later of `today + 7` and today, so the FUTURE START
-- DATE WAS CHOSEN AND IS HONOURED: the span is `today + 7 … today + 37`, and a
-- reading that moved both dates to today would hand this member a free week
-- before their membership was ever meant to begin.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 786
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301002'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300042'::uuid, '22000000-0000-4000-8000-000000300082'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'pre-sold: the member pays today for a membership that starts next week, and the payment is recorded');

set local role postgres;

-- 787 — the pre-sold answer. TWO things are pinned in one row and both matter:
-- `starts_on` did NOT move to today (the chosen date is honoured), and the span
-- is thirty days rather than the sixty a first grant that ADDED would
-- produce here. It is `pending`, and its status is deliberately not asserted —
-- what a first grant does to `status` is not what this requirement decides, and
-- asserting it would be guessing.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300082'::uuid $$,
  $$ select (select d from today_t30) + 7, (select d from today_t30) + 37, 1 $$,
  'PRE-SOLD: a future start date was chosen and is HONOURED — the membership still starts next week and now spans exactly the one period that was paid for, not the sixty days an addition would have given it'
);

-- ---------------------------------------------------------------------------
-- GROUP 3 (788-789) — LAPSED, the second shape, and the ONLY group that
-- separates the decided reading from the one the first implementation shipped.
-- The membership started sixty days ago and ended thirty days ago; the member
-- comes back and pays. `starts_on` is the later of `today - 60` and today, so
-- it becomes TODAY — a past start date is NOT honoured, because a membership
-- nobody paid for never started.
--
-- WHY THIS GROUP IS THE DISCRIMINATOR. All three candidate readings agree at
-- the headline. Here they do not:
--   * keep `starts_on` outright  -> today - 60 … today - 30: the member has
--     just paid for a membership that EXPIRED LAST MONTH. Paid for nothing.
--   * keep `starts_on`, floor only `ends_on` at today (WHAT THE FIRST
--     IMPLEMENTATION DID) -> today - 60 … today + 30: a NINETY-day span for
--     one month's money — this requirement's own defect, reached from the other
--     side, and the reason `ends_on` alone is not enough to assert.
--   * the decided rule -> today … today + 30.
-- `ends_on` reads `today + 30` under the third reading AND under the second, so
-- this assertion is red today on `starts_on` and only on `starts_on`. That is
-- the point of asserting the two columns together in one row rather than
-- asserting the end date and calling the shape proven.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 788
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301003'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300043'::uuid, '22000000-0000-4000-8000-000000300083'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'lapsed: a member whose membership ran out last month comes back to the desk and pays, and the payment is recorded');

set local role postgres;

-- 789
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300083'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 30, 1 $$,
  'LAPSED: a PAST start date is not honoured — the membership is started at today and spans exactly thirty days, rather than carrying a start date sixty days old and a ninety-day span for one month''s money'
);

-- ---------------------------------------------------------------------------
-- GROUP 4 (790-793) — THE RENEWAL. THE MOST IMPORTANT CONTROL IN THIS SECTION,
-- and the assertion an over-broad fix fails. "Set, not added" is keyed on
-- `periods_granted = 0` and on nothing else; a membership that HAS been granted
-- a period must still EXTEND when it is paid again, because extending is what a
-- renewal IS.
--
-- The state is EARNED, not typed: GL044 (assertions 166-167) refuses a
-- `periods_granted` a hand wrote at creation, so R is created dateless and its
-- FIRST payment (790) puts it at one period and `today … today + 30`, exactly
-- as Section 9 already pins. 792 is then the renewal under test and 793 is the
-- answer: `today … today + 60`, two periods.
--
-- WHAT FAILS HERE AND NOWHERE ELSE. A fix that reads "on a first grant, set" is
-- correct and passes everything. A fix that reads "always set, never add" —
-- which passes 785, 787, 789 and 799, every red assertion in this section —
-- would leave R at `today … today + 30` after its second payment: a month of
-- money silently eaten, which is the same class of harm the requirement exists
-- to close. So would a fix keyed on "the row already carries dates" rather than
-- on the count, since R carries dates by the time 792 lands.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 790
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301004'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300047'::uuid, '22000000-0000-4000-8000-000000300087'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'renewal, the fixture half: the FIRST payment against a dateless membership, which earns the period that the renewal below is tested against');

set local role postgres;

-- 791 — the earned state, verified before the renewal is attempted rather than
-- assumed. If this is wrong the renewal below proves nothing.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300087'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 30, 1 $$,
  'renewal, the fixture half: one period EARNED from one payment, dated from the gym''s own today — the state a hand may not type and the granting rule must produce'
);

set local role authenticated;

-- 792
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301005'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300047'::uuid, '22000000-0000-4000-8000-000000300087'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'renewal: the member pays again, a month before they have to');

set local role postgres;

-- 793 — THE CONTROL THAT AN OVER-BROAD FIX FAILS. Green today. Must be green
-- afterwards. A renewal EXTENDS.
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300087'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 60, 2 $$,
  'THE RENEWAL CONTROL: a membership that has already been granted a period is EXTENDED by the next payment, not reset to one period — `starts_on` unmoved, sixty days, two periods. A fix that set the span on every grant rather than only the first would eat this month of money and pass every other assertion in this section'
);

-- ---------------------------------------------------------------------------
-- GROUP 5 (794-795) — THE ORDINARY DATELESS PATH, UNCHANGED. The product's own
-- answer today (Section 9, assertion 69) and the yardstick the contract
-- measures the defect against: against this path the same payment gives thirty
-- days, and at the headline it gave sixty. Green today, green afterwards.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 794
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301006'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300044'::uuid, '22000000-0000-4000-8000-000000300084'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'the ordinary path: a payment against a dateless pending membership');

set local role postgres;

-- 795
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300084'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 30, 1 $$,
  'THE ORDINARY PATH IS UNCHANGED: a dateless pending membership is still dated from the gym''s own today for the plan''s duration — the answer this requirement wants the dated paths to agree with, not one it changes'
);

-- ---------------------------------------------------------------------------
-- GROUP 6 (796-797) — THE CONSOLE'S ZERO-SPAN SHAPE, UNCHANGED. `starts_on =
-- ends_on = today` is what assertion 168 creates and what 170 already pins, and
-- it is the one DATED first-grant path that is already numerically right:
-- `greatest(today, today) + 30 x 1` and "set from the plan at today" are the
-- same date, so a correct fix touches nothing here. It is asserted because a
-- fix that DID change it would be changing the console's own behaviour by
-- accident, and this is the only place in the file that would notice.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 796
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301007'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300045'::uuid, '22000000-0000-4000-8000-000000300085'::uuid,
          100000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'the console''s shape: a payment against a membership created with a zero-length span');

set local role postgres;

-- 797
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300085'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 30, 1 $$,
  'THE CONSOLE''S ZERO-SPAN SHAPE IS UNCHANGED: still today … today + 30 for one period — the one dated first-grant path that was already right, and a fix that moved it would be moving the console'
);

-- ---------------------------------------------------------------------------
-- GROUP 7 (798-799) — ONE PAYMENT WORTH TWO PERIODS, ON A TYPED SPAN. The
-- boundary groups above all buy exactly one period, so none of them can tell a
-- span that was SET from the plan (`duration x periods`) from one that was set
-- to a single period and happened to match. This one can: 200000 against a
-- 100000 membership is two periods, and the span must be SIXTY days measured
-- from today — not the typed thirty plus sixty (ninety) an addition gives, and
-- not thirty.
-- ---------------------------------------------------------------------------

set local role authenticated;

-- 798
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, status, method, recorded_by_staff_id)
  values ('22000000-0000-4000-8000-000000301008'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
          '22000000-0000-4000-8000-000000300046'::uuid, '22000000-0000-4000-8000-000000300086'::uuid,
          200000, 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'two periods in a single payment against a membership carrying a typed one-period span — recorded, not refused');

set local role postgres;

-- 799
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships
      where id = '22000000-0000-4000-8000-000000300086'::uuid $$,
  $$ select (select d from today_t30), (select d from today_t30) + 60, 2 $$,
  'A FIRST GRANT SETS `duration x periods`, NOT ONE PERIOD: a single payment worth two periods leaves a sixty-day span and a count of two — proving the multiplier survives the change, which a section that only ever bought one period could not show'
);

-- ---------------------------------------------------------------------------
-- GROUP 8 (800) — THE IDENTITY, ACROSS EVERY PATH AT ONCE. The contract names
-- `ends_on - starts_on` versus `duration_days x periods_granted` as THE ONLY
-- number that disagreed while the defect was live, and ADR-088 declined to make
-- it a trigger, for reasons that are still right. So it is asserted here
-- instead, once, on all seven memberships together — six of them freshly
-- granted and the seventh renewed — because a rule that held on the headline
-- and drifted on the pre-sold or the lapsed row would be exactly as silent as
-- the defect was. Every row is compared against its OWN frozen `duration_days`,
-- not against the plan's. This group has matching membership and plan lengths;
-- it asserts the span identity, not the separate frozen-duration requirement.
-- ---------------------------------------------------------------------------

-- 800
select results_eq(
  $$ select id, (ends_on - starts_on), (duration_days * periods_granted)
       from public.memberships
      where tenant_id = '22000000-0000-4000-8000-000000300001'::uuid
      order by id $$,
  $$ values
      ('22000000-0000-4000-8000-000000300081'::uuid, 30, 30),
      ('22000000-0000-4000-8000-000000300082'::uuid, 30, 30),
      ('22000000-0000-4000-8000-000000300083'::uuid, 30, 30),
      ('22000000-0000-4000-8000-000000300084'::uuid, 30, 30),
      ('22000000-0000-4000-8000-000000300085'::uuid, 30, 30),
      ('22000000-0000-4000-8000-000000300086'::uuid, 60, 60),
      ('22000000-0000-4000-8000-000000300087'::uuid, 60, 60) $$,
  'THE IDENTITY HOLDS ON EVERY PATH: `ends_on - starts_on` equals `duration_days x periods_granted` on all seven memberships — the headline, the pre-sold, the lapsed, the dateless, the console''s zero-span, the double payment and the renewal. This is the one comparison the system never makes, which is why the defect audited clean for a whole phase'
);


-- ---------------------------------------------------------------------------
-- GROUP 9 (801-805) — A PART PAYMENT SETS NOTHING. The new contract explicitly
-- leaves both dates untouched until the accumulated money buys a whole period.
-- Section 8 checks the end date alone; these shapes also expose a start date
-- moving too early, and the dateless case must keep both dates null.
--
-- The dated fixtures deliberately carry 3650 days, which creation still allows.
-- Once the second half pays for one period, the span must become thirty days:
-- preserve a future start, move a past start to today, and start a dateless row
-- today. A typed span's length is not credit toward paid membership time.
-- ---------------------------------------------------------------------------

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('22000000-0000-4000-8000-000000300048'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 Part Future', '+912230000048'),
  ('22000000-0000-4000-8000-000000300049'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 Part Past', '+912230000049'),
  ('22000000-0000-4000-8000-000000300050'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300011'::uuid, 'M30 Part Dateless', '+912230000050');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('22000000-0000-4000-8000-000000300088'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300048'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'pending', (select d from today_t30) + 7, (select d from today_t30) + 3657, 100000),
  ('22000000-0000-4000-8000-000000300089'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300049'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'active', (select d from today_t30) - 90, (select d from today_t30) + 3560, 100000),
  ('22000000-0000-4000-8000-000000300090'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
   '22000000-0000-4000-8000-000000300050'::uuid, '22000000-0000-4000-8000-000000300061'::uuid,
   'pending', null, null, 100000);

-- 801 — verify every starting date and that no period has been granted.
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted, duration_days, price_paise
       from public.memberships
      where id in ('22000000-0000-4000-8000-000000300088'::uuid,
                   '22000000-0000-4000-8000-000000300089'::uuid,
                   '22000000-0000-4000-8000-000000300090'::uuid)
      order by id $$,
  $$ values
      ('22000000-0000-4000-8000-000000300088'::uuid, (select d from today_t30) + 7, (select d from today_t30) + 3657, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300089'::uuid, (select d from today_t30) - 90, (select d from today_t30) + 3560, 0, 30, 100000::bigint),
      ('22000000-0000-4000-8000-000000300090'::uuid, null::date, null::date, 0, 30, 100000::bigint) $$,
  'part-payment fixtures: future and past starts carry 3650 typed days, the dateless row carries none, and all three have zero granted periods on the same thirty-day terms'
);

set local role authenticated;

-- 802 — one half-price payment per membership; none reaches one period.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id) values
    ('22000000-0000-4000-8000-000000301009'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300048'::uuid, '22000000-0000-4000-8000-000000300088'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid),
    ('22000000-0000-4000-8000-000000301010'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300049'::uuid, '22000000-0000-4000-8000-000000300089'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid),
    ('22000000-0000-4000-8000-000000301011'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300050'::uuid, '22000000-0000-4000-8000-000000300090'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'half-price payments are recorded against the future, past-start and dateless memberships');

set local role postgres;

-- 803 — dates means BOTH columns, including nulls; the count remains zero.
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted
       from public.memberships
      where id in ('22000000-0000-4000-8000-000000300088'::uuid,
                   '22000000-0000-4000-8000-000000300089'::uuid,
                   '22000000-0000-4000-8000-000000300090'::uuid)
      order by id $$,
  $$ values
      ('22000000-0000-4000-8000-000000300088'::uuid, (select d from today_t30) + 7, (select d from today_t30) + 3657, 0),
      ('22000000-0000-4000-8000-000000300089'::uuid, (select d from today_t30) - 90, (select d from today_t30) + 3560, 0),
      ('22000000-0000-4000-8000-000000300090'::uuid, null::date, null::date, 0) $$,
  'a payment short of one period moves neither date and grants nothing: future, past-start and dateless shapes are all unchanged'
);

set local role authenticated;

-- 804 — the other half reaches exactly one period on each membership.
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id) values
    ('22000000-0000-4000-8000-000000301012'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300048'::uuid, '22000000-0000-4000-8000-000000300088'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid),
    ('22000000-0000-4000-8000-000000301013'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300049'::uuid, '22000000-0000-4000-8000-000000300089'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid),
    ('22000000-0000-4000-8000-000000301014'::uuid, '22000000-0000-4000-8000-000000300001'::uuid,
     '22000000-0000-4000-8000-000000300050'::uuid, '22000000-0000-4000-8000-000000300090'::uuid,
     50000, 'INR', 'paid', 'cash', '22000000-0000-4000-8000-000000300021'::uuid)
$$, 'the second half of each price is recorded and completes the first paid period');

set local role postgres;

-- 805 — setting occurs only at the first complete period, even when the typed
-- span was much longer than one period. Both dates and the earned count matter.
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted
       from public.memberships
      where id in ('22000000-0000-4000-8000-000000300088'::uuid,
                   '22000000-0000-4000-8000-000000300089'::uuid,
                   '22000000-0000-4000-8000-000000300090'::uuid)
      order by id $$,
  $$ values
      ('22000000-0000-4000-8000-000000300088'::uuid, (select d from today_t30) + 7, (select d from today_t30) + 37, 1),
      ('22000000-0000-4000-8000-000000300089'::uuid, (select d from today_t30), (select d from today_t30) + 30, 1),
      ('22000000-0000-4000-8000-000000300090'::uuid, (select d from today_t30), (select d from today_t30) + 30, 1) $$,
  'two half payments buy exactly one thirty-day span: preserve the future start, replace the past start with today, and date the dateless membership from today'
);

select * from finish();
rollback;
