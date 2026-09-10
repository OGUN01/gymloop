-- h22_payment_record_holdout — HOLDOUT pgTAP suite for the payment-record
-- contract settled minutes before this file was written:
--   openspec/changes/phase-5-money/specs/payment-record/spec.md
-- and background from docs/decisions.md ADR-070, ADR-071, ADR-082, ADR-083.
--
-- The author of this file has not read, and will not read: any migration
-- dated 20260910000000 or later; pg_get_functiondef/prosrc for
-- app.stamp_payment, app.enforce_payment, app.extend_membership_on_payment
-- or app.enforce_refund_total; or supabase/tests/22_payment_record.sql (the
-- visible suite, written in parallel by a different author). Schema facts
-- used below (columns, enums, constraints, triggers by name, grants,
-- policies) came only from the live Cloud catalogue, queried the same way
-- h21's own header describes.
--
-- WHAT THIS FILE IS FOR. The visible suite transcribes the spec's own
-- scenarios; duplicating that buys nothing. This spec exists because the
-- first round governed INSERT and left UPDATE open, so every battery below
-- assumes the fix will over-correct (freeze something that was never paid)
-- or under-correct (miss an edge of the transition table, or a second path
-- into the same illegal state) and goes looking there.
--
--   * THE FREEZE, EARLY AND LATE. A `created` row must stay fully editable
--     (amount, member, membership, method) — an implementation that freezes
--     on every row breaks ordinary correction of a mistyped amount. A row
--     that has been `paid` must stay frozen even after it moves on to
--     `refunded` or `reversed` — "has EVER been paid" is a history, not a
--     current-value check.
--   * THE TRANSITION TABLE, PER SOURCE. Every permitted edge is proven to
--     succeed and, wherever two states could plausibly share a target
--     (`created` and `failed` both reach `pending`-adjacent states; `paid`
--     is a target only from `created`/`pending`), the illegal edge into the
--     same target from the wrong source is proven refused too — the
--     discriminator a set-membership check (versus a per-source table)
--     would fail.
--   * paid_at AND THE FINANCIAL YEAR IT ACTUALLY DRIVES. Both halves are
--     proven against the document_counters row that gets created, not
--     merely against the payments column — a stamped column with the wrong
--     counter row would still look right at a glance.
--   * THE COUNTER'S MONOTONICITY, PAIRED WITH THE ALLOCATOR STILL WORKING.
--     Every rejected hand-edit is followed by a read proving the value is
--     actually unchanged, then a real allocation is run through the same
--     row to prove the rule that stops hand-editing does not also stop the
--     thing it exists to protect.
--   * CUMULATIVE PERIODS, INCLUDING THE ONE THE SPEC DOES NOT SETTLE.
--     Below a multiple, exactly one via two halves, two at once, a zero
--     price, and a refund landing between two part payments — the spec
--     never says whether a payment that later becomes refunded still
--     counts toward the total that was granted, and this file stages that
--     case and reports what happens rather than asserting a side of it.
--   * REFUND ATTRIBUTION'S NULL-ACTOR SHAPE (ADR-071), gotten wrong twice
--     already elsewhere in this project: a refund naming a colleague, one
--     naming nobody with a staff claim present (attributed to the session),
--     and one from a session with no staff identity at all (refused
--     outright, even naming an otherwise-real staff member).
--   * THE REFUND CEILING RE-CHECKED ON UPDATE, not just insert: a refund
--     recorded `failed` is excluded from the ceiling sum at insert, a
--     second refund is then accepted against the room that leaves, and
--     THEN the first refund is revived out of `failed` — which must be
--     refused once it would push the live total over the payment.
--   * THE CROSS-MEMBER PAYMENT, and its cross-gym sibling: a payment naming
--     a membership belonging to a different member in the SAME gym (new
--     business rule, nothing else catches it), and one naming a membership
--     in a DIFFERENT gym entirely (already caught today by ADR-052's
--     composite foreign key — asserted here as evidence already held).
--   * THE GYM'S DAY at both ends of the clock, Etc/GMT-12 and Etc/GMT+12,
--     for the "no dates" membership-dating rule and the financial year a
--     payment is filed under.
--
-- A REACHABILITY NOTE, found while building fixtures rather than assumed:
-- `memberships_dated_unless_pending_chk` permits null starts_on/ends_on
-- ONLY when status = 'pending'. The spec's "membership with no dates" and
-- "membership with a starts_on and no ends_on, genuinely open-ended" cases
-- are therefore both reachable ONLY through a `pending` membership — never
-- through `active`, which the "open-ended" wording most naturally suggests.
-- Both fixtures below are built as `pending` for exactly this reason; see
-- the report for what that implies about whether the "genuinely open-ended"
-- scenario, as described, is exercising the shape the spec seems to intend.
--
-- Dates are read from `(now() at time zone o.timezone)::date` into a temp
-- table ONCE per gym, at the top of this file, and reused throughout —
-- still fully derived from a live `now()` and never a literal, but stable
-- across the many statements this file runs so a payment recorded a few
-- seconds after the fixtures cannot land on the wrong side of a UTC
-- midnight the fixtures did not see.
--
-- ADR-069: every assertion is a top-level `select` consumed by pgTAP
-- directly. ADR-050: every count is scoped to this file's own fixtures,
-- all under uuid prefix '220000ff-0022-...'. ADR-030: one transaction,
-- ending in ROLLBACK.
--
-- THIRD-SESSION EXTENSION — memberships.periods_granted itself (section 15,
-- plan raised 133 -> 157, later 157 -> 161 in a fourth session — see below),
-- added by a single author for BOTH this file and
-- its visible sibling on the coordinator's explicit instruction: the gap is
-- identical in each (`grep -rln periods_granted supabase/tests supabase/
-- tests-holdout` returned nothing before this pass — section 6 above proves
-- the extension only through `ends_on`, and every fixture that sets the
-- column at all leaves it at its default 0), so the usual two-author
-- blindness buys nothing here. The two batteries are kept genuinely
-- different in what they attack rather than one transcribing the other —
-- see section 15's own header for exactly how.
--
-- ADR-088 is the reason this column is worth reading directly rather than
-- only through `ends_on`: the one-time backfill computed it in `numeric`
-- and Postgres ROUNDED the assignment into the `integer` column, so 0.9 of
-- a period was stored as 1 — and a membership already reading `granted = 1`
-- when only `owed = 1` had actually arrived then let its NEXT full payment
-- through granting nothing at all, ₹12,000 for zero days, on the one row in
-- the demo gym (a discounted Annual) where the money and the price
-- genuinely differed. Section 15 goes looking for that shape directly, and
-- past it: what a value the rule could never produce does to the next
-- payment, and what a `price_paise` edit does to money already banked
-- against the old price — neither of which the visible spec settles, so
-- both are staged and reported (`diag`), not resolved, in the house style
-- section 6's own refund-mid case already established.
--
-- FOURTH-SESSION UPDATE. Both live defects section 15 found are now fixed,
-- in a migration dated 20260910000000 or later, named by the coordinator
-- and spliced in mechanically (never opened, per the hard rule) via
-- `python <scratchpad>/sweep.py h22_payment_record_holdout.sql out.sql
-- supabase/migrations/20260910210000_*.sql`. (1) `check (periods_granted
-- >= 0)` exists now — section 15e's first two assertions pass unchanged,
-- its third is inverted from proving -1 landed to proving it did not. (2)
-- GL043 — a membership's price_paise and currency are frozen once
-- periods_granted > 0, both directions — closes the price-cut defect
-- section 15d found and reported unscored. 15d is rewritten: its two
-- price-change fixtures keep their ids and baselines, but "not refused,
-- report what happened" becomes "refused, price/currency unchanged, and
-- an ordinary further payment at the still-frozen price still grants
-- normally" — plus a currency-only case and a periods_granted = 0 case the
-- freeze must not catch. See section 15's own header for the same account
-- in more detail.
--
-- FIFTH-SESSION EXTENSION — section 16, plan 161 -> 215 -> 222, written by a
-- SEPARATE author who read only the two new requirements
-- (openspec/changes/phase-5-money/specs/payment-record/spec.md: "The terms
-- a period was scored against do not change after it is granted" (GL043)
-- and "How many periods have been granted is written by the rule and by
-- nobody else" (GL044)), docs/decisions.md ADR-089 and OPEN-026, the live
-- Cloud catalogue, and this file. Not read, then or since:
-- supabase/tests/22_payment_record.sql, whose own battery for the same two
-- requirements was being written in parallel — round six had one author
-- write both suites and both missed the same two bypasses, which is why
-- this section has a different author from section 15's. Also not read:
-- prosrc or pg_get_functiondef for anything implementing GL043/GL044.
-- Section 16 assumes 15d's price/currency freeze is settled and does not
-- re-prove it; see section 16's own header for the seams it goes at
-- instead. Everything it asserts about GL043's third term (plan_id) and
-- about GL044 was RED against live Cloud when written, and every
-- permitted-side assertion in it was green and is there to fail an
-- over-broad fix.
--
-- SAME SESSION, SECOND PASS, after the requirement grew a paragraph and
-- two scenarios in answer to what this section found. (1) A membership is
-- created having been granted nothing: 16g is now SIDED — refused, and the
-- harm behind it gone — and sections 15b and 15c, which used to TYPE a
-- non-zero count into a fixture, now EARN it from real payments (15b from
-- its own two part payments, 15c rewritten around the one shape nothing
-- else here covers: a single payment crossing five multiples at once).
-- Those two repairs are fixture changes and were green both before and
-- after, which is how a fixture repair is told from a rule change.
-- (2) Writing the same count back is allowed: 16h asserts it, and asserts
-- the ordinary column-listing update that carries it, because the
-- shortest rule that passes every refusal in this section refuses both.
-- (3) discount_paise is deliberately not a frozen term — nothing in the
-- money path reads it — so nothing here asserts that it is.

-- SIXTH-SESSION EXTENSION — section 17, plan 222 -> 317, written blind by a
-- THIRD author against the round-EIGHT requirement: GL043 restated as "the
-- terms money is scored against are frozen by MONEY ARRIVING" (not by a
-- period being granted) with the duration of a period added as a fourth
-- term recorded on the membership, plus the new GL039. Round seven's gate
-- was keyed on `periods_granted > 0`; a critic showed that gate says the
-- wrong thing, and the exploit it was written to close survived it through
-- an ordinary PART PAYMENT. Sections 15d and 16 assert the old gate's
-- shape and stay as written — everything they assert is still true, since a
-- membership that has been GRANTED a period has necessarily TAKEN money —
-- and section 17 asserts the wider rule the prose actually states.
--
-- Section 17 does NOT use `throws_ok(..., null::char(5), null, ...)` for its
-- refusals, and that is deliberate: the new term lives in a column that did
-- not exist when this section was written, and a null expected code passes
-- on `42703 undefined_column`. Its own `pg_temp.h22r8_refused` treats a
-- missing column, table, function or syntax as NOT a refusal, so its
-- battery cannot go green against an unimplemented contract — the exact
-- failure mode that made this round necessary. See section 17's own header
-- for the seams it goes at, the two readings its author sided on, and the
-- one open question it stages rather than guesses.

-- SEVENTH-SESSION EXTENSION — section 18, plan 317 -> 383, written blind by
-- a FOURTH author against the round-NINE requirement (ADR-092): a period's
-- length is DERIVED, never negotiated — it may change only as part of a plan
-- change and only to what that plan says, at any time, money or no money —
-- and a plan change carries the PRICE with it unless the correction names a
-- price of its own. The refusal for a typed length is GL043, answered by the
-- coordinator to both authors rather than guessed.
--
-- TWO OF SECTION 17'S OWN ASSERTIONS CHANGED, because the contract they were
-- written against contradicted itself. Round eight named the harm ("create a
-- membership naming duration_days = 3650, pay the ordinary price, get ten
-- years") and three lines later permitted the identical outcome in two
-- statements. (1) 17c's duration-frozen refusal STANDS and its reason is
-- rewritten: it was justified by money having arrived, and the length is not
-- frozen by money — it is derived, and typing one is refused whether or not
-- a paisa has ever been taken. (2) 17c's pre-money plan-correction OPEN
-- QUESTION is now sided at the corrected plan's length, plus one new
-- assertion that the length re-derived — which is the +1 in 317 -> 383, the
-- other 65 being section 18. Nothing else in sections 0-17 moved; no fixture
-- in this file ever hand-wrote a duration_days, so nothing rested on one.

-- EIGHTH-SESSION EXTENSION — section 19, plan 383 -> 486 -> 488, written blind
-- by a
-- FIFTH author against the round-TEN requirement (ADR-093): the dates a
-- membership runs for — `starts_on` and `ends_on` — are written by the rule
-- that grants a period and by nobody else. Nine rounds governed what a period
-- costs, how long it is and how many have been granted; all of it computes a
-- date any front-desk session could simply type, and this author confirmed
-- that live in four statement shapes before writing a line.
--
-- Not read, then or since: supabase/tests/22_payment_record.sql, whose own
-- battery for GL045 was being written in parallel by a different author; any
-- migration dated 20260911140000 or later; and prosrc or pg_get_functiondef
-- for anything implementing GL045. Round nine's migration was spliced
-- mechanically to run this file, never opened. Also not read, per ADR-091:
-- docs/registry.md for anything about this round's code. Read: the
-- requirement, ADR-093 including OPEN-027, and the live Cloud catalogue.
--
-- Section 19 does not re-prove the headline refusal. It goes at the granting
-- rule's own writes at every shape it has (a depth-keyed guard keyed one step
-- wrong breaks the RENEWAL path, and that failure is silent to everyone but
-- the member), at the seam between the rule's write and a hand's write inside
-- one statement, at `starts_on` and what it buys AT THE GATE rather than only
-- in the column, at everything that legitimately moves a date and might now
-- be refused, and at the rows the rule leaves alone. It also re-measures the
-- "detectable afterwards" premise ADR-093 retracts, and finds it worse than
-- retracted: an ordinary PART PAYMENT breaks the audit invariant by itself.
-- See section 19's own header for the seams, the one place it sided rather
-- than staged, and what it reports rather than asserts.
--
-- SAME SESSION, SECOND PASS: 16i's two OPEN-026 assertions were reconciled to
-- this contract by the same author (486 -> 488). They asserted that a
-- half-dated `pending` row could be given its missing starts_on by hand — the
-- write GL045 refuses, and which 19e asserts refused on the same shape. They
-- now assert the refusal, the state the row is left in, and the thing they
-- were actually protecting: that the row stays editable in every column the
-- granting rule does not own, which is what ADR-089 rejected a consistency
-- trigger to preserve.

-- TENTH-SESSION EXTENSION - section 21, plan 582 -> 612, round TWELVE, the same
-- GL046: `coupon_id` joins the column list (21a, 14 assertions) and the
-- requirement's own repair path - refund, cancel, sell again - is run end to
-- end for the first time (21b, 16). WRITTEN BY THE SAME AUTHOR AS THE VISIBLE
-- SUITE'S ROUND-TWELVE SECTIONS: a deliberate, recorded deviation from hard
-- rule 10 / ADR-059, argued in section 21's own header. The independence was
-- traded knowingly - there is no interpretation left for a second author to
-- make on one more column of a rule both suites already cover - and nothing
-- else about the arrangement changed.
--
-- NINTH-SESSION EXTENSION - section 20, plan 488 -> 574 -> 582, written blind by a
-- SIXTH author against the round-ELEVEN requirement "Deciding what a member
-- owes is gym-admin work" (GL046, ADR-094): a session that changes a
-- membership's `price_paise`, `currency`, `plan_id` or `discount_paise` is
-- refused unless it is a gym admin. Round nine made `duration_days`
-- underivable by hand because it multiplies `floor(money / price_paise)`; the
-- PRICE is the other factor of that product and stayed freely typed, and two
-- ordinary front-desk statements bought 300 days for one Rs.1,500 receipt
-- with both audit invariants intact.
--
-- Not read, then or since: supabase/tests/22_payment_record.sql, written in
-- parallel by a different author; any migration later than round ten's;
-- prosrc or pg_get_functiondef for anything implementing GL046; and, per
-- ADR-091, docs/registry.md for anything about this round's code.
--
-- THIRTEEN PERMITTED-SIDE ASSERTIONS IN SECTIONS 16, 17, 18 AND 19 ENCODED THE
-- OLD CONTRACT and are reconciled in place, each marked "ROUND-ELEVEN
-- RECONCILIATION". The spec scenario "Correcting a mistake before any money
-- arrives" said "a FRONT-DESK session" for four rounds - the sentence a critic
-- walked through to buy 300 days - and now says "a gym admin". Every one of
-- those assertions tests WHAT a correction does, or WHEN the terms are still
-- free, rather than who may ask - so each is simply sent by a manager:
--   * 16c's plan correction; 16i's discount repair;
--   * 17c's pre-money plan correction; 17g's three-column correction;
--   * 17d's four "money has arrived" boundary pairs - arrived/created,
--     arrived/failed, arrived/sibling and arrived/moved-row - each of which
--     proves that a raised-but-unpaid payment, a failed one, a sibling
--     membership and the row a payment was merely WRITTEN against all leave
--     the terms correctable. They are round-EIGHT assertions about GL043's
--     money gate and they keep measuring exactly that; the payment statements
--     around them stay at the desk, because a payment is recorded by the
--     staff member who took it (GL034);
--   * 18b (i)-(vi) and 18c entire; 18e's discount write and mis-sold
--     correction; and 19g's column-listing save (whose own text already said
--     "when a MANAGER changes a discount").
-- The wording, the counts and the assertions themselves are untouched; only
-- the claim changes. 15d-zero is deliberately NOT among them - it runs as
-- claimless `postgres`, which section 20c's carve-out keeps green.
--
-- Section 20 does not re-prove the headline refusal. It goes at the three
-- designs ADR-094 REJECTS and what each rejection obliges to keep working, at
-- `is_gym_admin()` itself for every caller that carries no claim (the seed's
-- own upsert statement among them), at the interaction with the GL043 and
-- GL045 freezes and the one place their ordering could leak, at the CREATE
-- path - where its finding is - and at the permitted side as hard as the
-- refused. See section 20's own header for the seams, the two places it sided
-- rather than staged, and the door it asserts as open on purpose.
--
-- SEVENTH-SESSION EXTENSION (round thirteen) — section 22, plan raised
-- 612 -> 686, written by yet another blind author against the spec's newest
-- requirement, "Money does not extend a membership that has been retired".
-- `app.grant_periods()` reads a membership's price, currency, dates, count
-- and length and never its status, so money named against a cancelled or
-- expired membership moves that row's dates while the gate keeps refusing
-- its member. Section 22 leaves the headline to the visible suite and takes
-- the boundary of "retired" value by value across the whole enum, the
-- PERMITTED side as hard as the refused, every arrival at the two
-- statement-level extension triggers that is not a plain INSERT, the gate as
-- a consequence rather than a column, and one route the requirement does not
-- close (money refused a grant is not detached from the membership, and
-- `cancelled -> active` is a permitted front-desk UPDATE) which it stages and
-- reports rather than siding. See section 22's own header.

-- ELEVENTH-SESSION EXTENSION - section 24, plan 701 -> 809, round SEVENTEEN,
-- written blind by an EIGHTH author against the three newest requirements: "A
-- refund that completed did not fail", "Money only comes back out of money
-- that came in", and "A membership belongs to the member it was sold to". Two
-- authors again this round, one per suite - round sixteen's single author
-- wrote two near-identical sections and a critic said so. Section 24 leaves
-- the three headlines to the visible suite and takes the seams: the refund
-- status enum across all sixteen ordered pairs on sixteen separate rows;
-- `completed` reached by UPDATE rather than by insert; what GL040/GL041 and
-- this round together still leave writable on `refunds` and whether any of it
-- reaches the ceiling; the `created` rule from the permitted side and its
-- closure with GL039; the membership move from the desk, a manager and a
-- claimless `postgres`, against a member holding nothing AND against the one
-- holding a live membership that the requirement warns is a false green; the
-- three rules composed into single statements; and the permitted side as hard
-- as the refused. Its refusals are asserted through `pg_temp.h22r17_gl`,
-- which is true only for a `GL0…` code, because 23505 from
-- `memberships_tenant_id_member_id_live_key` and 42501 from
-- `refunds_tenant_write` would each satisfy a null-coded `throws_ok`. THE ONE
-- EXCEPTION is the live-target membership move, which the unique index
-- refuses first and always will (ADR-072 keeps these rules in AFTER
-- triggers); it is asserted through `h22r8_refused` instead, and section
-- 24e's header records the ordering so nobody moves the rule to BEFORE to
-- satisfy it. Same call round ten made for GL045 against a Phase 1 CHECK.
--
-- ITS FINDING, staged rather than asserted (24c): the requirement freezes
-- `completed` and, in its own second scenario, explicitly permits every other
-- move - including `processing -> failed`. A refund at `processing` is money
-- already with the provider. Run with `processing` in place of `completed`,
-- the requirement's own measured exploit completes end to end under the rule:
-- ceiling refuses the second refund, first is demoted to `failed`, second is
-- ACCEPTED, re-completing the first is refused by GL036. Same harm, same
-- one-way door, one enum value over. SETTLED BY THE COORDINATOR AS PERMITTED,
-- and 24c's assertions stay green as written: money at `processing` is in
-- flight and can genuinely fail, so refusing the transition would strand it
-- while the ceiling ate money that never left. The invariant survives for a
-- different reason than the freeze — GL036 applies on UPDATE, so an
-- un-counted refund can never be re-completed and at most one of the two ever
-- reaches `completed`, which is exactly what 24c/step 5 measures.
-- See section 24's own header.

-- TWELFTH-SESSION EXTENSION - section 25, plan 809 -> 919, round EIGHTEEN,
-- written blind by a NINTH author against a requirement that belongs to a
-- different change entirely: openspec/changes/membership-lifecycle/, which
-- closes OPEN-030 by giving `memberships.status` the state machine `payments`
-- has had since round three. Two requirements: which status may follow which
-- (terminal `expired` and `cancelled`, self-writes allowed), and what becomes
-- of money paid against a retired membership once revival is impossible.
--
-- THREE ASSERTIONS IN 22h CHANGED, and they are the only ones in this file
-- that did. 22h existed to stage exactly this question - it measured
-- `cancelled -> active` as a permitted front-desk UPDATE and reported that
-- round thirteen's refusal was therefore deferred rather than durable - so the
-- new requirement's whole purpose is to falsify the premise 22h asserted. The
-- revival is now asserted refused, the shape after it is asserted unchanged,
-- and the bounded "T+10 or T+100" outcome is sided at T+10. Same fixture, same
-- ids, same six assertions, same money; only the answer moved, and 22h's own
-- header records that it moved because the contract did. NOTHING ELSE IN THE
-- FILE TRANSITIONS A MEMBERSHIP ILLEGALLY: every other `status` write here was
-- checked against its fixture's own starting status and each is `active ->
-- frozen`, `frozen -> active`, `active -> cancelled`, `frozen -> cancelled`,
-- `active -> expired`, `pending -> active` or `pending -> cancelled`.
--
-- Section 25 leaves both headlines to the visible suite and takes the seams:
-- the six-link chain that keeps money paid while retired from stranding; the
-- granting rule's own `pending -> active` write and the two statement shapes
-- that imitate it; the malformed `pending` rows of OPEN-023 and OPEN-026 and
-- whether this rule is what seals them (it is not); MERGE, `UPDATE ... FROM`
-- per-row, upsert, CTE and two-statement composition; the seed's own upsert
-- shape run with `memberships_terms_frozen` disabled exactly as CI runs it;
-- and the gate. See section 25's own header for what it reports rather than
-- resolves - creation into a terminal status is unanswered by the requirement,
-- and `active -> expired` is a legal one-way door a front desk can walk a live
-- member through in one statement.

-- THIRTEENTH-SESSION EXTENSION - section 27, plan 937 -> 985, round TWENTY,
-- written blind by an ELEVENTH author against openspec/changes/
-- membership-creation/. That change proposed TWO requirements and shipped ONE:
-- the creation rule (GL048, "at most the one period it is sold") was withdrawn
-- mid-authoring after its own implementation refuted it - spliced into all 47
-- pgTAP files it blocked six of them outright and cost a seventh four
-- assertions, because six independently-authored suites build multi-period
-- memberships directly. Nothing in section 27 asserts GL048 or the half-dated
-- clause that went with it; the whole section is the surviving requirement,
-- "the first period is SET, not added", which the withdrawal leaves as the
-- only thing standing between a ten-year membership typed at creation and a
-- ten-year membership somebody has paid one month for.
--
-- Not read by this author: any migration; supabase/tests/22_payment_record.sql,
-- written in parallel by a different author; docs/decisions.md;
-- docs/registry.md; any function or trigger body.
--
-- Section 27 leaves the requirement's own three scenarios to the visible suite
-- and takes what none of them reaches: the first grant that grants MORE THAN
-- ONE period (two halves, a double payment, two payments in one statement and
-- in two), the three paths where nothing is granted and so nothing may move (a
-- part payment, a foreign currency, a complimentary membership), a plan whose
-- period is ONE DAY, the ten-year row collapsing to thirty days, and the
-- invariant `ends_on - starts_on = duration_days * periods_granted` asserted
-- over every path at once AND asserted NOT to hold where ADR-088's objection
-- says it legitimately does not. See section 27's own header.
--
-- ITS FINDING, raised staged and since SETTLED IN THE CONTRACT (27d): "set its
-- span from the plan" fixes a LENGTH and never said where `starts_on` lands.
-- Three readings fitted the sentence and agreed on every scenario the
-- requirement stages, because in all of them `starts_on` was already today; on
-- a pre-sold membership and on a lapsed member returning they differed by up to
-- a hundred days at a gate that admits on dates, and the first implementation
-- picked the reading that gave a returning member a 61-day span for one month's
-- money. The contract now says the first grant starts a membership at the LATER
-- of its `starts_on` and today, and 27d asserts the position as well as the
-- span. 27e/5 records the consequence for this file: the earlier cumulative,
-- multi-row, price and date-guard assertions encoded the pre-change arithmetic
-- and are now reconciled in place under the same `spec:` change. Their original
-- refusal, grant-count and refund checks remain intact.
--
-- INDEPENDENT CONTRACT AUDIT: a subsequent holdout author read the committed
-- membership-creation contract at f337a3a, this file, AGENTS.md and the schema
-- contract in docs/data-model.md; no visible suite, implementation, migration,
-- plan or decision narrative was read. Section 27f adds 16 assertions combining
-- future, partly elapsed and dateless starts with a part payment, a first grant
-- worth several periods, and a renewal. The existing 985 assertions are kept.

-- NET-PRICE RECONCILIATION (spec 5b041e9), by an independent holdout author.
-- Discount now participates in the agreed price and freezes on any received
-- money. Only the two post-receipt discount edits and the explicit gross-price
-- tripwire below change expectations; unpaid edits and all 1001 tests remain.
begin;

set local role postgres;

select plan(1001);

-- ---------------------------------------------------------------------------
-- 0. Fixtures.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('220000ff-0022-4000-8000-100000000001'::uuid, 'Holdout PAYREC Gym A', 'H22AGA'),
  ('220000ff-0022-4000-8000-100000000002'::uuid, 'Holdout PAYREC Gym B', 'H22AGB');

insert into public.organizations (id, name, gym_code, timezone) values
  ('220000ff-0022-4000-8000-100000000003'::uuid, 'Holdout PAYREC Gym P (GMT-12)', 'H22AGP', 'Etc/GMT-12'),
  ('220000ff-0022-4000-8000-100000000004'::uuid, 'Holdout PAYREC Gym M (GMT+12)', 'H22AGM', 'Etc/GMT+12');

insert into public.branches (id, tenant_id, name, is_default) values
  ('220000ff-0022-4000-8000-200000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 A Main', true),
  ('220000ff-0022-4000-8000-200000000002'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, 'H22 B Main', true),
  ('220000ff-0022-4000-8000-200000000003'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, 'H22 P Main', true),
  ('220000ff-0022-4000-8000-200000000004'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, 'H22 M Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('220000ff-0022-4000-8000-300000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'front_desk', 'H22 A Desk 1'),
  ('220000ff-0022-4000-8000-300000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'gym_manager', 'H22 A Manager 1'),
  ('220000ff-0022-4000-8000-300000000003'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'gym_manager', 'H22 A Manager 2 (colleague)'),
  ('220000ff-0022-4000-8000-300000000011'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-200000000002'::uuid, 'front_desk', 'H22 B Desk'),
  ('220000ff-0022-4000-8000-300000000031'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'front_desk', 'H22 P Desk'),
  ('220000ff-0022-4000-8000-300000000041'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-200000000004'::uuid, 'front_desk', 'H22 M Desk');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 Plan A', 30, 100000),
  ('220000ff-0022-4000-8000-400000000002'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, 'H22 Plan B', 30, 100000),
  ('220000ff-0022-4000-8000-400000000003'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, 'H22 Plan P', 30, 100000),
  ('220000ff-0022-4000-8000-400000000004'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, 'H22 Plan M', 30, 100000);

-- The gym's own day and financial year, computed once from a live now(),
-- never a literal, and reused everywhere below.
create function pg_temp.h22_fy(d date) returns text
language sql immutable as $$
  select case
    when extract(month from d) >= 4
      then extract(year from d)::text || '-' || lpad(((extract(year from d)::int + 1) % 100)::text, 2, '0')
    else (extract(year from d)::int - 1)::text || '-' || lpad((extract(year from d)::int % 100)::text, 2, '0')
  end
$$;

grant execute on function pg_temp.h22_fy(date) to public;

create temp table gym_today (org_key text primary key, org_id uuid, today date, fy text);
insert into gym_today (org_key, org_id, today, fy)
select 'A', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000001'::uuid
union all
select 'P', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000003'::uuid
union all
select 'M', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000000004'::uuid;

-- authenticated and service_role sessions below need to read this and the
-- other temp fixtures this file builds; they are this file's own scratch
-- state, not anything a real session could ever see.
grant select on gym_today to public;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE1 Owner',        '+919220000001'),
  ('220000ff-0022-4000-8000-500000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE1 Target',       '+919220000002'),
  ('220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FE2 Owner',        '+919220000003'),
  ('220000ff-0022-4000-8000-500000000005'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row1',  '+919220000005'),
  ('220000ff-0022-4000-8000-500000000006'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row2',  '+919220000006'),
  ('220000ff-0022-4000-8000-500000000007'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Transition Row3',  '+919220000007'),
  ('220000ff-0022-4000-8000-500000000008'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 FL2 First Paid',   '+919220000008'),
  ('220000ff-0022-4000-8000-50000000000a'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Counter RealAlloc','+919220000010'),
  ('220000ff-0022-4000-8000-50000000000b'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative Below', '+919220000011'),
  ('220000ff-0022-4000-8000-50000000000c'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative Exact', '+919220000012'),
  ('220000ff-0022-4000-8000-50000000000d'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative TwoAtOnce', '+919220000013'),
  ('220000ff-0022-4000-8000-50000000000e'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative ZeroPrice', '+919220000014'),
  ('220000ff-0022-4000-8000-50000000000f'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Cumulative RefundMid', '+919220000015'),
  ('220000ff-0022-4000-8000-500000000010'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Ceiling Base',  '+919220000016'),
  ('220000ff-0022-4000-8000-500000000011'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Colleague',     '+919220000017'),
  ('220000ff-0022-4000-8000-500000000012'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund Nobody',        '+919220000018'),
  ('220000ff-0022-4000-8000-500000000013'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refund NoIdentity',    '+919220000019'),
  ('220000ff-0022-4000-8000-500000000014'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 CrossMember Owner',    '+919220000020'),
  ('220000ff-0022-4000-8000-500000000015'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 CrossMember Payer',    '+919220000021'),
  ('220000ff-0022-4000-8000-500000000016'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Refusal Is Policys',   '+919220000022'),
  ('220000ff-0022-4000-8000-500000000017'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Pending OpenEnded',    '+919220000023'),
  ('220000ff-0022-4000-8000-500000000018'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 Receipt Squat',        '+919220000024'),
  ('220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 SecondOrder Collision','+919220000025'),
  ('220000ff-0022-4000-8000-500000000020'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow Ten',         '+919220000026'),
  ('220000ff-0022-4000-8000-500000000021'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow B1',          '+919220000027'),
  ('220000ff-0022-4000-8000-500000000022'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MultiRow B2',          '+919220000028'),
  ('220000ff-0022-4000-8000-500000000023'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MixedPaidCreated',     '+919220000029'),
  ('220000ff-0022-4000-8000-500000000024'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 UpdateMixed',          '+919220000030'),
  ('220000ff-0022-4000-8000-500000000025'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 SameMembershipTwice',  '+919220000031'),
  ('220000ff-0022-4000-8000-500000000026'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 MixedCurrency',        '+919220000032'),
  ('220000ff-0022-4000-8000-500000000027'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 WrongCurrencySimple',  '+919220000033');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000101'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-200000000002'::uuid, 'H22 B Membership Owner', '+919220000101');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000201'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'H22 P NoDates', '+919220000201');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000211'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-200000000004'::uuid, 'H22 M NoDates', '+919220000211');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000001'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  -- 'expired' rather than 'active': memberships_tenant_id_member_id_live_key
  -- permits only one live (active/frozen) membership per member, and this
  -- row exists only as a second, valid FK target for the same member to
  -- prove membership_id itself is editable pre-paid — it is never paid
  -- against, so its own status is otherwise irrelevant to this fixture.
  ('220000ff-0022-4000-8000-600000000002'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000003'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired', (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 15, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000010'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000b'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  ('220000ff-0022-4000-8000-600000000011'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000c'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 15, 100000),
  ('220000ff-0022-4000-8000-600000000012'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000d'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 5,  100000),
  ('220000ff-0022-4000-8000-600000000013'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000e'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 7,  0),
  ('220000ff-0022-4000-8000-600000000014'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000000f'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 8,  100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000020'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000014'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000021'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000017'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', (select today from gym_today where org_key='A') - 5, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000000030'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000020'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000031'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000021'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000032'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000022'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 50000,  'INR'),
  ('220000ff-0022-4000-8000-600000000033'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000023'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000034'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000024'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000035'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000025'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000036'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000026'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000037'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000027'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR');

-- SecondOrder: one member holding BOTH an already-active membership and a
-- separate pending, dateless one — the fixture for the "made active by a
-- payment" second-order collision probe.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000038'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000039'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000019'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000101'::uuid, '220000ff-0022-4000-8000-100000000002'::uuid, '220000ff-0022-4000-8000-500000000101'::uuid, '220000ff-0022-4000-8000-400000000002'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000201'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-500000000201'::uuid, '220000ff-0022-4000-8000-400000000003'::uuid, 'pending', null, null, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000211'::uuid, '220000ff-0022-4000-8000-100000000004'::uuid, '220000ff-0022-4000-8000-500000000211'::uuid, '220000ff-0022-4000-8000-400000000004'::uuid, 'pending', null, null, 100000);

-- ---------------------------------------------------------------------------
-- 1. The freeze applied too early: a payment that has never been paid is a
--    working document, not a record. All four fields via UPDATE, on a
--    payment sitting at `created`.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000001', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000001', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'FE1: a payment recorded at created, never yet paid, is inserted');

select lives_ok(
  $$update public.payments set amount_paise = 2000 where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: amount_paise on a payment that has never been paid is freely editable');

select lives_ok(
  $$update public.payments set method = 'upi' where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: method on a payment that has never been paid is freely editable');

select lives_ok(
  $$update public.payments set member_id = '220000ff-0022-4000-8000-500000000002' where id = '220000ff-0022-4000-8000-700000000001'$$,
  'FE1: member_id on a payment that has never been paid is freely editable — membership_id stayed null so this cannot also trip the cross-member rule');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000002', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000003', '220000ff-0022-4000-8000-600000000001', 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'FE2: a second created payment, naming a real membership of its own member, is inserted — the baseline for the membership_id edit below');

select lives_ok(
  $$update public.payments set membership_id = '220000ff-0022-4000-8000-600000000002' where id = '220000ff-0022-4000-8000-700000000002'$$,
  'FE2: membership_id on a payment that has never been paid is freely editable, moving between two memberships that both belong to its own member');

-- ---------------------------------------------------------------------------
-- 2. The transition table, edge by edge, per source rather than by target
--    set membership — and the freeze that follows a payment into every
--    terminal state it reaches (refunded, reversed), proven on the same
--    rows rather than fresh ones.
--
--    Row1: created -> pending -> paid -> refunded, with every illegal edge
--    reachable from each state probed before the row moves on (a refused
--    UPDATE is a no-op, so the row is still available for the next probe).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000010', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000005', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row1: a fresh created payment for the transition battery');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: created -> refunded is refused directly, with no intervening paid');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: created -> reversed is refused directly');

select lives_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: created -> pending succeeds');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> created is refused — the discriminator against failed -> created being legal below; a target-only set-membership check would wrongly allow this');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> refunded is refused');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: pending -> reversed is refused');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: pending -> paid succeeds');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal (PAY-007, farming): paid -> created is refused — paid is unreachable from anywhere it has already been');

select throws_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: paid -> pending is refused, even though pending is a legal target from created and from failed');

select throws_ok(
  $$update public.payments set status = 'failed' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: paid -> failed is refused — paid only ever moves on to refunded or reversed');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'legal: paid -> refunded succeeds');

select throws_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal (reviving): refunded -> paid is refused');

select throws_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'illegal: refunded -> created is refused — refunded is terminal');

-- The freeze, proven on this same now-refunded row: it has been paid, and
-- refunded does not lift that.
select throws_ok(
  $$update public.payments set amount_paise = 999999 where id = '220000ff-0022-4000-8000-700000000010'$$,
  null, null, 'freeze applied late enough: amount_paise on a REFUNDED payment (which has been paid) is still refused');

select lives_ok(
  $$update public.payments set notes = 'h22 row1 note after refund' where id = '220000ff-0022-4000-8000-700000000010'$$,
  'over-enforcement check: notes on the same refunded row is still writable — the freeze does not block everything');

-- ---------------------------------------------------------------------------
--    Row2: created -> failed -> pending -> paid -> reversed, covering the
--    edges Row1 did not: created -> failed, failed -> pending, paid ->
--    reversed, and the failed -> paid / failed -> refunded / failed ->
--    reversed illegal edges (failed may only ever move to created or
--    pending).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000011', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000006', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row2: a fresh created payment for the second transition battery');

select lives_ok(
  $$update public.payments set status = 'failed', failed_reason = 'h22 row2 first fail' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: created -> failed succeeds');

select throws_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> paid is refused directly — a failed attempt must return through created or pending, not straight to paid');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> refunded is refused');

select throws_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: failed -> reversed is refused');

select lives_ok(
  $$update public.payments set status = 'pending' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: failed -> pending succeeds');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: pending -> paid succeeds a second time, on a row that arrived at pending via failed rather than via created');

select lives_ok(
  $$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000011'$$,
  'legal: paid -> reversed succeeds');

select throws_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal (reviving): reversed -> paid is refused');

select throws_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'illegal: reversed -> refunded is refused — reversed is terminal, and terminal-to-terminal is not a special case');

select throws_ok(
  $$update public.payments set amount_paise = 999999 where id = '220000ff-0022-4000-8000-700000000011'$$,
  null, null, 'freeze applied late enough: amount_paise on a REVERSED payment (which has been paid) is still refused');

-- ---------------------------------------------------------------------------
--    Row3: created -> failed -> created. The one genuinely legal backward
--    edge (failed -> created, "a retry is a new attempt"), which must be
--    reachable even though the identical target from `pending` (Row1's
--    fourth probe) is refused. This is the discriminator, complete: the
--    same target status is legal from one source and illegal from another.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000012', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000007', null, 1000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'Row3: a fresh created payment for the failed -> created discriminator');

select lives_ok(
  $$update public.payments set status = 'failed', failed_reason = 'h22 row3 fail before retry' where id = '220000ff-0022-4000-8000-700000000012'$$,
  'legal: created -> failed succeeds, again, as the setup for the retry edge');

select lives_ok(
  $$update public.payments set status = 'created' where id = '220000ff-0022-4000-8000-700000000012'$$,
  'legal (PAY: a retry is a new attempt): failed -> created succeeds — the exact target Row1 proved illegal from pending');

-- ---------------------------------------------------------------------------
-- 3. The freeze applies from the first moment a row is paid, not only after
--    it moves on to a terminal state — and the receipt number specifically,
--    which is the reason the freeze list exists at all.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000020', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000008', null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'FL2: a payment recorded straight to paid allocates its own receipt_number');

select throws_ok(
  $$update public.payments set receipt_number = 'H22-HANDPICKED-1' where id = '220000ff-0022-4000-8000-700000000020'$$,
  null, null, 'FL2: choosing a receipt number by hand on a payment the counter has already numbered is refused, while the row is merely paid — not yet refunded or reversed');

select throws_ok(
  $$update public.payments set amount_paise = 1 where id = '220000ff-0022-4000-8000-700000000020'$$,
  null, null, 'FL2: amount_paise is frozen the moment the row is paid, not only once it later moves to a terminal state');

select lives_ok(
  $$update public.payments set notes = 'h22 FL2 note while merely paid' where id = '220000ff-0022-4000-8000-700000000020'$$,
  'FL2: notes remains writable on a merely-paid (non-terminal) row too');

-- ---------------------------------------------------------------------------
-- 4. paid_at is the system's to decide for a session row security applies
--    to, and a trusted writer keeps its own — proven through the financial
--    year counter row that actually gets created, not just the column.
--    Gym P (Etc/GMT-12) carries the RLS-governed half; gym M (Etc/GMT+12)
--    carries the trusted-writer half, so this section also does timezone
--    duty for the financial year derivation.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000003',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000031')::text,
  true
);
set local role authenticated;

select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000030', '220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-500000000201', null, 100000, 'cash', 'paid', %L, '220000ff-0022-4000-8000-300000000031')$sql$,
    ((select today from gym_today where org_key = 'P') + 730)::timestamptz
  ),
  'gym P: a desk session records a payment carrying a paid_at two years away — the insert itself is not refused for carrying a bogus value');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select ok(
  (select abs(extract(epoch from (paid_at - now()))) < 300 from public.payments where id = '220000ff-0022-4000-8000-700000000030'::uuid),
  'gym P: the stored paid_at is close to the instant the row was actually recorded, not the two-years-away value the session supplied');

select ok(
  (select exists(
     select 1 from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000003'
       and kind = 'receipt'
       and financial_year = (select fy from gym_today where org_key = 'P')
  )),
  'gym P: the receipt counter advanced under the financial year of the instant the payment was actually recorded');

select is_empty(
  format(
    $sql$select 1 from public.document_counters
      where tenant_id = '220000ff-0022-4000-8000-100000000003'
        and kind = 'receipt'
        and financial_year = %L$sql$,
    pg_temp.h22_fy(((select today from gym_today where org_key = 'P') + 730))
  ),
  'gym P: no counter row exists under the financial year the caller''s bogus paid_at would have implied — the desk cannot file a payment into a year by asking');

select set_config(
  'request.jwt.claims', '', true
);
set local role service_role;

select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, provider, provider_order_id, provider_payment_id)
      values ('220000ff-0022-4000-8000-700000000031', '220000ff-0022-4000-8000-100000000004', '220000ff-0022-4000-8000-500000000211', null, 100000, 'razorpay', 'paid', %L, 'razorpay', 'order_h22_trusted_1', 'pay_h22_trusted_1')$sql$,
    (((select today from gym_today where org_key = 'M') - 730)::timestamptz)
  ),
  'gym M: a trusted (service_role) writer records a payment with its own paid_at, two years in the past — the webhook''s timestamp is the more truthful one');

set local role postgres;

select is(
  (select paid_at from public.payments where id = '220000ff-0022-4000-8000-700000000031'::uuid),
  ((select today from gym_today where org_key = 'M') - 730)::timestamptz,
  'gym M: the trusted writer''s own paid_at was kept exactly, not overridden by the system''s now()');

select ok(
  (select exists(
     select 1 from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000004'
       and kind = 'receipt'
       and financial_year = pg_temp.h22_fy((select today from gym_today where org_key = 'M') - 730)
  )),
  'gym M: the receipt counter advanced under the financial year the trusted writer''s OWN paid_at implies, two years back — proving the kept value actually drives the year, not merely the column');

-- ---------------------------------------------------------------------------
-- 5. The counter's monotonicity: forward, not "by exactly one" (the spec's
--    own revision — a decrease is the only move that can reissue a number,
--    and a forward jump merely leaves a gap, which a receipt book explains
--    and a repeated number does not; requiring a step of one also made the
--    sibling manual-payment holdout's own staged-race fixture unstageable).
--    A decrease refuses and leaves the value unmoved, a forward jump of
--    more than one succeeds and leaves a gap, deletion refuses, and the
--    allocator still advances the counter by exactly one from wherever it
--    has been left — proven as a front-office session, the same predicate
--    that is FOR ALL on document_counters and could otherwise rewrite it
--    freely. Every rejection is paired with a read proving the value truly
--    did not move.
-- ---------------------------------------------------------------------------

create temp table h22_ctr_baseline as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_baseline to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$update public.document_counters set next_number = next_number + 1
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  'counter: a direct increase of exactly one succeeds');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_baseline),
  'counter: and it actually advanced by exactly one from the captured baseline');

select throws_ok(
  $$update public.document_counters set next_number = next_number - 1
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  null, null, 'counter: a decrease is refused');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_baseline),
  'counter: and the refused decrease left the value exactly where the successful +1 left it');

select lives_ok(
  $$update public.document_counters set next_number = next_number + 25
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  'counter: a forward jump of more than one succeeds — only a decrease can reissue an already-printed number, and a gap is explainable');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 + 25 from h22_ctr_baseline),
  'counter: and it actually landed on baseline+26, leaving a visible gap rather than being silently capped back to +1');

select throws_ok(
  $$delete from public.document_counters
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt'$$,
  '42501', null, 'counter: deletion of a counter row is refused — authenticated holds no DELETE grant on document_counters at all, so this is already true structurally rather than by a new rule');

select is(
  (select count(*)::int from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  1,
  'counter: the row still exists after the refused delete');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000040', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000a', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'counter: a real allocation, through the actual payment path, still succeeds after the decrease, the forward jump, and the delete attempt above');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 + 25 + 1 from h22_ctr_baseline),
  'counter: and it advanced by exactly one more from wherever the hand-edits left it (baseline+26), not from a stale re-read and not by more than one — the rule that stops hand-editing does not also stop the allocator it protects');

set local role postgres;
select set_config('request.jwt.claims', '', true);
-- ---------------------------------------------------------------------------
-- 6. A period is granted by the cumulative multiple of the membership's own
--    price that its own payments have now reached, not by the arrival of
--    any single payment. Below a multiple, exactly one via two halves, two
--    at once, a zero price, and a refund landing between two part
--    payments — the last of which the spec does not resolve, and this file
--    reports rather than resolves.
-- ---------------------------------------------------------------------------

-- Below a multiple: recorded and receipted, but nothing moves.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000050', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000b', '220000ff-0022-4000-8000-600000000010', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a payment below the membership''s own price is recorded and receipted');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000010'::uuid),
  (select today from gym_today where org_key = 'A') + 10,
  'cumulative: and grants no period — ends_on is unchanged');

-- Exactly one, via two halves (ADR-083's own example).
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000051', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000c', '220000ff-0022-4000-8000-600000000011', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: the first of two half payments is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000011'::uuid),
  (select today from gym_today where org_key = 'A') + 15,
  'cumulative: and grants no period on its own — the half alone has not reached one multiple');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000052', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000c', '220000ff-0022-4000-8000-600000000011', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: the second half is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000011'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'cumulative: and exactly one period is granted on the second half, once the cumulative total reaches the price — never two months for the two halves. ROUND-TWENTY RECONCILIATION: this read `today + 15 + 30`. The membership was created today-10..today+15 with periods_granted at ZERO, so the second half is its FIRST grant, and "the first period is set, not added" sets the span from the membership''s own recorded length and starts it at the later of its starts_on and today. The fifteen typed days nobody bought are gone; one period''s price still buys exactly one period, which is what this line was always measuring');

-- Two at once.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000053', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000d', '220000ff-0022-4000-8000-600000000012', 200000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a single payment of exactly double the membership''s price is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000012'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'cumulative: and grants two periods in one step — floor(200000/100000) - floor(0/100000) = 2. ROUND-TWENTY RECONCILIATION: this read `today + 5 + 60`. Created today-10..today+5 with periods_granted at ZERO, so this is a FIRST grant and the new requirement sets the span rather than adding to it: two periods of the membership''s own length, from today. It also pins the multi-period case the new requirement never stages a scenario for — the span is the length times the COUNT, so two months'' money still buys two months');

-- A membership with no price at all: recorded, and grants nothing, rather
-- than raising a division-by-zero.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000054', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000e', '220000ff-0022-4000-8000-600000000013', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a payment against a zero-price membership does not raise — the price=0 case is special-cased rather than dividing by it');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000013'::uuid),
  (select today from gym_today where org_key = 'A') + 7,
  'cumulative: and grants no period, since a multiple of zero is not a meaningful threshold');

-- A refunded payment in the middle of the sum. THE SPEC DOES NOT SAY
-- whether a payment that has since been refunded still counts toward the
-- cumulative total that was granted. This stages the case, bounds the
-- outcome to the only two answers a sane implementation could give (never
-- MORE than one period for money that peaked at exactly one multiple,
-- refund or no refund), and reports which one actually happened rather
-- than asserting a side of the open question.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000055', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000f', '220000ff-0022-4000-8000-600000000014', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative/refund-mid: the first half is recorded and paid');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000001', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000055', 'refund', 50000, 'h22 full refund of the first half, before the second half arrives', '220000ff-0022-4000-8000-300000000002')$$,
  'cumulative/refund-mid: and it is refunded in full before the second half is ever recorded');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000056', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000f', '220000ff-0022-4000-8000-600000000014', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative/refund-mid: the second half is then recorded');

select ok(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid)
    in ((select today from gym_today where org_key = 'A') + 8,
        (select today from gym_today where org_key = 'A') + 30),
  'cumulative/refund-mid: whatever the answer, it is bounded to zero or one period — never two, since only one multiple of the price was ever paid in, refunded or not. ROUND-TWENTY RECONCILIATION: the upper bound read `today + 8 + 30` and now reads `today + 30`. Only the bound moved: the row was created today-10..today+8 with periods_granted at ZERO, so the granting branch of this open question is a FIRST grant and sets the span instead of adding to the eight typed days. The lower bound, the row untouched at today+8, is unchanged, and the question this line stages — whether a refunded payment still counts toward the total — is exactly as open as it was');

select diag(
  format('cumulative/refund-mid OBSERVED: membership 600000000014 ends_on is %s (baseline was %s) — %s a refunded first-half payment toward the cumulative total. The spec does not say which is correct; report, do not resolve.',
    (select ends_on::text from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid),
    ((select today from gym_today where org_key = 'A') + 8)::text,
    case when (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000014'::uuid) = (select today from gym_today where org_key = 'A') + 8
         then 'this build did NOT count'
         else 'this build DID count' end
  ));

-- ---------------------------------------------------------------------------
-- 7. The refund ceiling is re-checked on UPDATE, not only on INSERT — and a
--    refund's own payment_id and amount_paise are as frozen as a payment's
--    are. A refund recorded `failed` is excluded from the ceiling sum at
--    insert; a second refund is then accepted against the room that
--    leaves; reviving the first one out of `failed` must be refused once
--    the live total would exceed the payment.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000060', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000010', null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund ceiling/update: the base payment (100000) is recorded and paid');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000010', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000060', 'refund', 90000, 'failed', 'h22 a refund recorded straight to failed', '220000ff-0022-4000-8000-300000000002')$$,
  'refund ceiling/update: a 90000 refund recorded straight to failed is accepted — a failed refund took nothing, so it is excluded from the ceiling sum at insert');

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000011', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000060', 'refund', 60000, 'h22 a second refund, against the room the failed one left', '220000ff-0022-4000-8000-300000000002')$$,
  'refund ceiling/update: a second, live 60000 refund is accepted — with the failed 90000 excluded, 60000 alone fits under the 100000 ceiling');

select throws_ok(
  $$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000010'$$,
  null, null, 'refund ceiling/update: reviving the first refund out of failed is refused — 90000 + 60000 would now exceed the 100000 payment, and the ceiling is re-checked on this UPDATE, not only at insert time');

select throws_ok(
  $$update public.refunds set amount_paise = 70000 where id = '220000ff-0022-4000-8000-800000000011'$$,
  null, null, 'refund identity: amount_paise on a recorded refund is frozen, independent of whether the new value would itself respect the ceiling');

select throws_ok(
  $$update public.refunds set payment_id = '220000ff-0022-4000-8000-700000000020' where id = '220000ff-0022-4000-8000-800000000011'$$,
  null, null, 'refund identity: payment_id on a recorded refund is frozen — a refund cannot be re-pointed at a different payment after the fact');

-- ---------------------------------------------------------------------------
-- 8. Money leaving the gym names the person who sent it (ADR-071's
--    null-actor shape): a refund naming a colleague, one naming nobody
--    with a staff claim present (attributed to the session), and one from
--    a session with no staff identity at all — refused outright, even when
--    it names an otherwise-real staff member of the gym.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000070', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000011', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the colleague test is recorded');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000020', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000070', 'refund', 50000, 'h22 a manager refunds, naming a colleague', '220000ff-0022-4000-8000-300000000003')$$,
  null, null, 'refund attribution: a manager (Manager1, holding the session) naming a colleague (Manager2) as initiated_by_staff_id is refused — the acting session, not the caller''s word, decides who sent the money');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000071', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000012', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the nobody-named test is recorded');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000021', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000071', 'refund', 50000, 'h22 a manager refunds, naming nobody', null)$$,
  'refund attribution: leaving initiated_by_staff_id null, with a real staff claim on the session, succeeds rather than being refused for want of one');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select initiated_by_staff_id from public.refunds where id = '220000ff-0022-4000-8000-800000000021'::uuid),
  '220000ff-0022-4000-8000-300000000002'::uuid,
  'refund attribution: and reading it back shows it landed on the session''s own staff member, not null and not anybody else');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000072', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000013', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: the base payment for the no-staff-identity test is recorded');

-- ADR-071's null-actor shape: app_role satisfies is_gym_admin(), but there
-- is no staff_id claim on the session at all.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000022', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000072', 'refund', 50000, 'h22 no staff_id claim, names nobody', null)$$,
  null, null, 'refund attribution: a session with no staff_id claim at all is refused outright when it names nobody — there is no verified identity to attribute the row to');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- A SEPARATE base payment for the second half of this probe: the first
-- attempt above, if it currently succeeds (the rule does not exist yet),
-- would already have booked a full refund against 700000000072 — a second
-- attempt against the SAME payment would then be refused by the
-- already-existing refund ceiling instead, passing this assertion for the
-- wrong reason entirely (exactly the failure mode a null-only test risks).
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000073', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000013', null, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'refund attribution: a second, independent base payment for the "names a real staff member anyway" half of the no-identity probe');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000023', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000073', 'refund', 50000, 'h22 no staff_id claim, names a real staff member anyway', '220000ff-0022-4000-8000-300000000002')$$,
  null, null, 'refund attribution: the same identity-less session is refused even when it names an otherwise-real staff member of the gym — the point is THIS session has no verified identity, not merely that the column is blank');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 9. A payment extends only the membership of the member who paid: the
--    same-tenant cross-member case (new — nothing else in the schema
--    catches it), and its cross-gym sibling (already caught today by
--    ADR-052's composite foreign key).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000080', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000014', '220000ff-0022-4000-8000-600000000020', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'cross-member: a payment naming its own payer''s own membership succeeds — the positive control');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000081', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000015', '220000ff-0022-4000-8000-600000000020', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  null, null, 'cross-member: a payment naming a membership that belongs to a DIFFERENT member in the SAME gym is refused — same tenant, so no foreign key catches this; only the new business rule does');

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000082', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000015', '220000ff-0022-4000-8000-600000000101', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  '23503', null, 'cross-member''s sibling: a payment whose membership_id belongs to another GYM entirely is refused by ADR-052''s composite foreign key before any business rule is even reached');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 10. A membership with no dates is dated from the gym's own today, proven
--     at both ends of the clock (Etc/GMT-12, Etc/GMT+12) — and the
--     "genuinely open-ended, not extended" shape, which the schema's own
--     memberships_dated_unless_pending_chk makes reachable only through a
--     `pending` membership (see the header note).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000090', '220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-500000000201', '220000ff-0022-4000-8000-600000000201', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000031')$$,
  'gym P (Etc/GMT-12): a paid payment against a membership with both dates null is recorded');

select is(
  (select starts_on from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid),
  (select today from gym_today where org_key = 'P'),
  'gym P: starts_on is set from the gym''s own today');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid),
  (select today from gym_today where org_key = 'P') + 30,
  'gym P: ends_on runs the plan''s duration from the gym''s own today, not from any UTC or session-local date');

select is(
  (select status from public.memberships where id = '220000ff-0022-4000-8000-600000000201'::uuid)::text,
  'active',
  'gym P (ADR-084): the membership is made active in the same step, not left pending — dated but pending is a membership its own member is refused at the gate');

-- ADR-084's own named consequence: the member it was paid for is admitted
-- at the gate the same day. `app.enforce_check_in()`'s active/frozen gate
-- (read via pg_get_functiondef, which is not one of the four forbidden
-- functions) only runs on the QR-scan path (`qr_session_id is not null`) —
-- an assisted front-desk check-in skips that block entirely and would pass
-- regardless of membership status, which would prove nothing about ADR-084
-- at all. A real QR session is staged so the gate this scenario is
-- actually about is the one being exercised.
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000000001'::uuid, '220000ff-0022-4000-8000-100000000003'::uuid, '220000ff-0022-4000-8000-200000000003'::uuid, 'h22-gate-check-token-hash', now() + interval '1 day', '220000ff-0022-4000-8000-300000000031'::uuid);

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000003', '220000ff-0022-4000-8000-200000000003', '220000ff-0022-4000-8000-500000000201', '220000ff-0022-4000-8000-600000000201', now(), 'qr', '220000ff-0022-4000-8000-900000000001')$$,
  'gym P (ADR-084): the member it was paid for scans in at the gate the same day and is admitted — a membership that has been paid for admits its member, which app.enforce_check_in()''s active/frozen gate would otherwise refuse on a merely-dated-but-pending row');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000091', '220000ff-0022-4000-8000-100000000004', '220000ff-0022-4000-8000-500000000211', '220000ff-0022-4000-8000-600000000211', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000041')$$,
  'gym M (Etc/GMT+12, 24 hours from gym P at every instant): the same no-dates case');

select is(
  (select starts_on from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid),
  (select today from gym_today where org_key = 'M'),
  'gym M: starts_on is set from ITS OWN today, evaluated independently of gym P''s');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid),
  (select today from gym_today where org_key = 'M') + 30,
  'gym M: ends_on runs the plan''s duration from gym M''s own today — the two gyms cannot both be right if either reads a UTC or session date instead of its own');

select is(
  (select status from public.memberships where id = '220000ff-0022-4000-8000-600000000211'::uuid)::text,
  'active',
  'gym M (ADR-084): made active too — evaluated independently of gym P''s row');

-- The open-ended shape: starts_on set, ends_on null, reachable only via
-- `pending` (see header note) — paying for it should not manufacture an
-- end date out of nothing.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000092', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000017', '220000ff-0022-4000-8000-600000000021', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'gym A: a paid payment against a membership with starts_on set and ends_on null is recorded');

select ok(
  (select ends_on is null from public.memberships where id = '220000ff-0022-4000-8000-600000000021'::uuid),
  'gym A: ends_on remains null — a genuinely open-ended membership has not ended, so there is nothing to move (only reachable here as `pending`, per the header note)');

-- (4)'S SECOND-ORDER EFFECT, NOT SETTLED BY THE SPEC. A membership made
-- `active` by a payment now has to share memberships_tenant_id_member_id_live_key
-- (one live — active/frozen — membership per member) with whatever ELSE
-- that member already holds live. A member with an already-active
-- membership who ALSO holds a separate pending, dateless one (reachable —
-- see the header note; e.g. a second package sold before the first
-- expired) creates exactly this collision the moment the second one is
-- paid for. The spec does not say what should happen — refuse the
-- payment, refuse only the activation while still granting the period, or
-- something else. This stages it and reports which one the live schema
-- currently does, rather than asserting a side of an unresolved question.
-- The one thing that MUST hold regardless is that the pre-existing active
-- membership is not silently altered as a side effect of the second one's
-- payment, and that IS asserted below.
set local role postgres;

create temp table h22_second_order_outcome (outcome text);
do $$
begin
  begin
    insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000150', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000019', '220000ff-0022-4000-8000-600000000039', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001');
    insert into h22_second_order_outcome(outcome) values ('succeeded');
  exception when others then
    insert into h22_second_order_outcome(outcome) values (sqlstate || ': ' || sqlerrm);
  end;
end;
$$;

select diag(
  format('second-order OUTCOME: paying member 500000000019''s second, previously-pending membership (600000000039) while their first (600000000038) is already active resulted in: %s. Membership 600000000039''s own status is now %s. The spec does not settle this; report, do not resolve.',
    (select outcome from h22_second_order_outcome),
    coalesce((select status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000039'::uuid), 'no such row')
  ));

select is(
  (select row(status, ends_on, starts_on) from public.memberships where id = '220000ff-0022-4000-8000-600000000038'::uuid),
  (select row('active'::membership_status, (select today from gym_today where org_key = 'A') + 10, (select today from gym_today where org_key = 'A') - 10)),
  'second-order: whatever happened to the second membership, the member''s PRE-EXISTING active membership is completely untouched — not deactivated, not re-dated, not silently superseded');

-- ---------------------------------------------------------------------------
-- 11. A refusal is the policy's to give: a member session inserting its own
--     payment is refused by the policy on payments itself, and the
--     document_counters row it has no business knowing about is left
--     completely untouched.
-- ---------------------------------------------------------------------------

create temp table h22_ctr_before_refusal as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_before_refusal to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'member',
                     'member_id', '220000ff-0022-4000-8000-500000000016')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.payments (tenant_id, member_id, amount_paise, method, status)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000016', 1000, 'cash', 'created')$$,
  '42501', null,
  'refusal is the policy''s: a member session inserting its own payment is refused by the policy on payments — the same 42501 a member gets everywhere else, not a failure surfaced from document_counters');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n from h22_ctr_before_refusal),
  'refusal is the policy''s: and the receipt counter is completely unchanged by the refused attempt — nothing was allocated, named, or touched on a table the member has no business knowing exists');

-- ---------------------------------------------------------------------------
-- 13. A receipt number is the counter's alone, at every status (new
--     requirement, added after a second critic round). A caller-supplied
--     receipt_number on an RLS-governed session is IGNORED, not refused —
--     the row is still written, just numberless until it is actually paid.
--     A squatted number that survives permanently jams the book (the next
--     real payment collides, the failing insert rolls the counter increment
--     back with it, and every later payment collides on the same number),
--     so this proves the squat leaves no trace AND that ordinary allocation
--     keeps working right after it. A trusted writer is the named
--     exception ("for every session row security applies to"), so its own
--     supplied value is kept — the mirror of the paid_at rule two
--     requirements up. And a genuinely failed statement (not a squat, an
--     honest constraint violation) must not leave the counter part-advanced
--     for the next real payment to trip over.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, receipt_number, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000110', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'created', 'SQUAT-1', '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: a created payment carrying a caller-supplied receipt_number is written — the row itself is not refused');

select ok(
  (select receipt_number is null from public.payments where id = '220000ff-0022-4000-8000-700000000110'::uuid),
  'receipt/squat: and the supplied number was ignored, not kept — the row is numberless until it is actually paid');

select lives_ok(
  $$update public.payments set receipt_number = 'SQUAT-2' where id = '220000ff-0022-4000-8000-700000000110'$$,
  'receipt/squat: the same session then tries to squat a DIFFERENT number onto the still-created row by UPDATE — the row update itself is not refused either');

select ok(
  (select receipt_number is null from public.payments where id = '220000ff-0022-4000-8000-700000000110'::uuid),
  'receipt/squat: and it is still ignored — the column stays null, not "SQUAT-2"');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000111', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: the gym''s next REAL paid payment, after the squat attempt, is recorded normally');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000112', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/squat: and a second one right after it is too — no jam, no collision');

select ok(
  (select count(distinct receipt_number) = 2 from public.payments
     where id in ('220000ff-0022-4000-8000-700000000111'::uuid, '220000ff-0022-4000-8000-700000000112'::uuid)
       and receipt_number is not null),
  'receipt/squat: both real payments were numbered, and numbered with two DIFFERENT numbers — the squat left no stale value for either to collide with');

-- Trusted writer exception: the rule is scoped to sessions row security
-- applies to. A trusted (service_role) writer's own supplied value is kept.
set local role service_role;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, receipt_number, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000114', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'created', 'H22-TRUSTED-KEPT-2', '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/trusted-writer: a service_role session — not one row security applies to — supplies its own receipt_number on a created row');

set local role postgres;

select is(
  (select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000114'::uuid),
  'H22-TRUSTED-KEPT-2',
  'receipt/trusted-writer: and it is kept exactly, not nulled out — the ignore-rule names sessions row security applies to, which service_role is not');

-- A genuinely failed statement (an honest constraint violation, not a
-- squat) must not leave the counter part-advanced.
create temp table h22_ctr_before_honest_failure as
  select next_number as n from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and kind = 'receipt'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22_ctr_before_honest_failure to public;

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000115', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 0, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  '23514', null, 'receipt/honest-failure: a paid payment with amount_paise = 0 is refused by payments_amount_paise_chk — unrelated to receipt numbering, but a real statement failure to prove the counter survives');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n from h22_ctr_before_honest_failure),
  'receipt/honest-failure: the counter is completely unchanged by the failed statement — whatever the allocator attempted rolled back with the rest of it, so the NEXT real payment does not inherit a stray increment');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000116', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000018', null, 1000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'receipt/honest-failure: and a real payment right after the failed one is recorded normally');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'receipt' and financial_year = (select fy from gym_today where org_key = 'A')),
  (select n + 1 from h22_ctr_before_honest_failure),
  'receipt/honest-failure: advancing by exactly one from where the failed statement left it, not skipping and not colliding');

-- ---------------------------------------------------------------------------
-- 14. The count is per PAYMENT, however many arrive in one statement, and
--     the money must be the membership's own currency. A rule that
--     re-derives the total from the table inside an AFTER ... FOR EACH ROW
--     trigger cannot tell rows in the same statement apart — by the time
--     ANY row-level AFTER trigger fires, every row of that statement is
--     already visible in the table (Postgres fires row-level AFTER
--     triggers at the end of the statement, not interleaved with each
--     row's own insertion), so a naive "read the total, subtract my own
--     amount" computation sees the FINAL total for every row and grants a
--     period to each one that, alone, looks like it crossed the line. Ten
--     rows of one whole multiple therefore reads as ten crossings. Each
--     battery below attacks a different seam of whatever replaces that
--     per-row re-derivation.
-- ---------------------------------------------------------------------------

-- Seam: the plain multi-row case the spec itself measures — ten rows,
-- one membership, one whole multiple of the price.
select lives_ok(
  format(
    $sql$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      select gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000020',
             '220000ff-0022-4000-8000-600000000030', 10000, 'cash', 'paid', %L, '220000ff-0022-4000-8000-300000000001'
      from generate_series(1, 10)$sql$,
    now()
  ),
  'multi-row/ten: ten payments of 10000 each (one whole multiple of the 100000 price) are written by a single insert ... select');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000030'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/ten: exactly ONE period is granted for the statement''s total — not ten, which is what ten independent per-row crossings would grant (300 days on this 30-day plan, the spec''s own measured defect). ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: mixed statement — two DIFFERENT memberships written by the same
-- statement, each reaching a different multiple of its OWN price.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000021', '220000ff-0022-4000-8000-600000000031', 25000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000022', '220000ff-0022-4000-8000-600000000032', 20000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/mixed-memberships: one statement carries 4 rows against membership B1 (100000 total, its own 100000 price) and 3 rows against membership B2 (100000 total, its own 50000 price)');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000031'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/mixed-memberships: B1 gains exactly one period (100000 / 100000 = 1) — unaffected by B2''s rows in the same statement. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000032'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'multi-row/mixed-memberships: B2 gains exactly two periods (100000 / 50000 = 2) in the SAME statement — each membership''s own total, not a shared or confused one. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 60`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: some rows paid, some not, in one statement.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 60000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 40000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 50000, 'cash', 'created', null,  '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/mixed-status: one statement carries two paid rows (60000+40000=100000, exactly one multiple) and one merely-created row (50000) against the same membership');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000033'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/mixed-status: exactly one period, from the 100000 that is actually paid — the created row''s 50000 is not money that arrived and must not join the total. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: an UPDATE, not an INSERT, moving some rows to paid and others to
-- failed within one statement.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values
    ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 30000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001'),
    ('220000ff-0022-4000-8000-700000000131', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 70000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001'),
    ('220000ff-0022-4000-8000-700000000132', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000024', '220000ff-0022-4000-8000-600000000034', 50000, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/update: three pending payments against one membership are set up (30000, 70000, 50000)');

select lives_ok(
  $$update public.payments
      set status = case when id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131') then 'paid'::public.payment_status else 'failed'::public.payment_status end,
          paid_at = case when id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131') then now() else null end,
          failed_reason = case when id = '220000ff-0022-4000-8000-700000000132' then 'h22 multi-row update, this one fails' else null end
      where id in ('220000ff-0022-4000-8000-700000000130', '220000ff-0022-4000-8000-700000000131', '220000ff-0022-4000-8000-700000000132')$$,
  'multi-row/update: one UPDATE moves two of the three rows to paid (30000+70000=100000, exactly one multiple) and the third to failed, all in the same statement');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000034'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/update: exactly one period — the row moved to failed contributes nothing, and the two moved to paid are counted as their statement''s own total, not three independent per-row guesses. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: the SAME membership touched twice at different amounts in one
-- statement, summing to just past one multiple.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 70000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/uneven: one statement pays 40000 then 70000 (110000 total) against one membership priced at 100000');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000035'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/uneven: exactly one period (110000 crosses 100000 once) — a per-row guess using the final total for both unequal rows would double-grant, since each row alone (40000 and 70000) still looks like the one that crossed 100000 against a shared final total. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: currency, INSIDE a multi-row statement against one membership —
-- one row in the membership's own currency, one row in a currency the gym
-- does not price this membership in.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000026', '220000ff-0022-4000-8000-600000000036', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000026', '220000ff-0022-4000-8000-600000000036', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/currency: one statement pays 100000 INR (matching the membership''s own currency) and 100000 USD against the same membership');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000036'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'multi-row/currency: exactly one period, from the INR row alone — the USD row does not join the total even though it is against the same membership in the same statement. ROUND-TWENTY RECONCILIATION: this read `today + 10 + 30`. The membership was created today-10..today+10 with periods_granted at its default of ZERO, so the grant scored here is its FIRST, and openspec/changes/membership-creation adds "the first period is set, not added": where a membership has been granted no periods the rule SETS its span from the membership''s own recorded length rather than extending a span it already carries, and starts it at the later of its starts_on and today — today here, since starts_on is ten days back. The ten days that were typed and never bought are gone; what the statement''s own total actually bought is what is left, which is the thing this assertion has always been about. The expected value moved because the requirement did, not because the assertion was weakened');

-- Seam: the plain, single-row version of the currency rule.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000140', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000027', '220000ff-0022-4000-8000-600000000037', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'currency/simple: a single paid payment for the full price, but in USD against an INR-priced membership, is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000037'::uuid),
  (select today from gym_today where org_key = 'A') + 10,
  'currency/simple: and grants no period — money in a currency the gym does not price this membership in does not count, however much of it arrives');

-- Seam: concurrency. THE SPEC NOW REQUIRES the extension serialised on the
-- membership (an implicit `for update` on the membership row, the same
-- shape app.enforce_refund_total() already takes on the payment). This
-- file runs as ONE transaction on ONE connection (ADR-030) and cannot open
-- a second one, so the actual race — two transactions each recording half
-- the price concurrently, each seeing only its own row, each granting
-- nothing, permanently — CANNOT be staged here. Unlike the receipt
-- counter's race (h21/h18's own precedent), there is no single-row value
-- to pre-set that would simulate a concurrent commit landing between this
-- session's read and write: the defect is two READERS missing each
-- other's WRITE, not one writer racing a known prior value, and this file
-- has no way to hold this transaction inside the trigger's own critical
-- section while a second session runs concurrently against it. NOT
-- STAGED. A real test needs two live connections (e.g. two psql sessions,
-- one paused mid-trigger with pg_sleep or an advisory lock while the
-- other commits) and belongs in an integration or pgbench harness outside
-- pgTAP's one-transaction model, not in this file.

-- ---------------------------------------------------------------------------
-- 15. memberships.periods_granted itself — the column section 6 and 14
--     above only ever prove through its effect on ends_on. Genuinely
--     different from the visible suite's own battery: that file walks one
--     membership one payment at a time through the truncating boundaries;
--     this one (a) proves the same truncation INSIDE a single multi-row
--     statement, catching a rounding defect and a per-row-counting defect
--     with one fixture shape; (b) starts a membership's history from TWO
--     pre-existing payment rows rather than one; (c) sets the column to a
--     value the rule could never produce on its own and lands a payment
--     against it; (d) edits price_paise AFTER a period was already granted
--     under the old price, both directions; and (e) provokes the missing
--     CHECK as `postgres` rather than a tenant session, showing the gap is
--     structural rather than an RLS hole. (c) is not settled by the spec
--     this file was given — bounded to the outcomes a sane implementation
--     could produce and reported via `diag`, exactly as section 6's own
--     refund-mid case already does, rather than asserted as though the
--     spec had decided.
--
--     FOURTH-SESSION REWRITE OF (d) AND (e). (d)'s own `diag` finding —
--     cutting price_paise after a grant let one trivial payment unlock a
--     second period paid for at the old price — is now a named rule
--     (GL043: price_paise and currency frozen once periods_granted > 0,
--     both directions) in a migration this session was told about and may
--     not open. (d) is rewritten from "not refused, report what happened"
--     to "refused, and ordinary operation around the refusal is
--     unharmed" — its own two fixtures and baselines kept, only the
--     outcome after the baseline changes — plus a currency-only case and a
--     periods_granted = 0 case the freeze must NOT catch. (e)'s CHECK is
--     likewise now real; its third assertion is inverted from proving -1
--     landed to proving it did not.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000030'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG MultiRow',      '+919220000230'),
  ('220000ff-0022-4000-8000-500000000031'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG AlreadyGranted','+919220000231'),
  ('220000ff-0022-4000-8000-500000000032'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG Impossible',    '+919220000232'),
  ('220000ff-0022-4000-8000-500000000033'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG PriceDown',     '+919220000233'),
  ('220000ff-0022-4000-8000-500000000034'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG PriceUp',       '+919220000234'),
  ('220000ff-0022-4000-8000-500000000035'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG Negative',      '+919220000235'),
  ('220000ff-0022-4000-8000-500000000036'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 PG ZeroGrant',     '+919220000236');

-- ---------------------------------------------------------------------------
-- 15a. Truncation, INSIDE one multi-row statement: three rows of 33333
-- (99999 total — the shipped-wrong ratio's own neighbourhood, one paisa
-- short of a whole multiple) written by a single INSERT, then a lone
-- top-up row completing the multiple. A per-row re-derivation (ADR-086's
-- own defect shape) would see the FINAL total on every row of the first
-- statement and could grant something from a statement that, as a whole,
-- crossed nothing.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000040'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000030'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000030', '220000ff-0022-4000-8000-600000000040', 33333, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000030', '220000ff-0022-4000-8000-600000000040', 33333, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000030', '220000ff-0022-4000-8000-600000000040', 33333, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/multi-row: three rows of 33333 (99999 total, one paisa short of the 100000 price), in one statement, are recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000040'::uuid),
  0,
  'periods_granted/multi-row: 99999 in one statement grants ZERO — a per-row re-derivation seeing a shared near-total could easily round or overcount this');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000160', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000030', '220000ff-0022-4000-8000-600000000040', 1, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/multi-row: the single paisa completing the multiple (total 100000) is recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000040'::uuid),
  1,
  'periods_granted/multi-row: exactly one period now, from the combined multi-row and single-row total');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000040'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'periods_granted/multi-row: and ends_on agrees with the column exactly');

-- ---------------------------------------------------------------------------
-- 15b. A membership whose column already reads non-zero, backed by TWO
-- pre-existing payment rows rather than one (h22's own multi-payment
-- history shape) — the state ADR-088 names as the one no fixture in
-- either suite otherwise creates.
--
-- FIFTH-SESSION REPAIR. This fixture used to TYPE the 1 in and then insert
-- the two payments it claimed to summarize. GL044 now says a membership is
-- created having been granted nothing, so the count is EARNED here
-- instead: the row is created at zero with ends_on = today, and the two
-- part payments below (40000 + 60000, one statement) are what move it to
-- 1 and to today + 30. Every assertion after them is unchanged, and this
-- is a strictly better fixture — the state it starts the battery from is
-- now one the rule itself produced rather than one a hand wrote.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000041'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000031'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000);

-- The history that EARNS this membership's periods_granted = 1 — two rows,
-- not one, in a single statement, and not themselves scored by any
-- assertion here.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
  (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000031', '220000ff-0022-4000-8000-600000000041', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
  (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000031', '220000ff-0022-4000-8000-600000000041', 60000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000161', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000031', '220000ff-0022-4000-8000-600000000041', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/already-non-zero: a second full payment, against a membership whose column already reads 1 from two prior part payments, is recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000041'::uuid),
  2,
  'periods_granted/already-non-zero: the column reads one MORE (2), not re-derived from the table''s own two-row history as if it were zero');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000041'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'periods_granted/already-non-zero: ends_on moves by exactly one further period');

-- ---------------------------------------------------------------------------
-- 15c. FIFTH-SESSION REWRITE. This subsection used to TYPE periods_granted
-- = 5 onto a membership — a value the rule could never itself produce —
-- and report via diag what a payment then did to it, because the spec had
-- not decided. It has now: GL044's "A membership created with periods
-- already granted" scenario makes that state unreachable by any means, so
-- the fixture cannot exist and the question it staged is closed.
--
-- What replaces it is the shape nothing else in this file covers: a single
-- payment crossing SEVERAL multiples at once. 500000 against a 100000
-- price is five periods in one row, EARNED — and the sixth payment must
-- then grant exactly one more, not re-derive six from scratch and not
-- grant five again. Same two TAP lines, a state the rule produced.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000042'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000032'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000);

insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
  ('220000ff-0022-4000-8000-700000000167'::uuid, '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000032', '220000ff-0022-4000-8000-600000000042', 500000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001');

select is(
  (select row(periods_granted, ends_on) from public.memberships where id = '220000ff-0022-4000-8000-600000000042'::uuid),
  (select row(5, (select today from gym_today where org_key = 'A') + 150)),
  'periods_granted/many-at-once: one payment of five times the price grants FIVE periods and 150 days in a single row — the multiple is counted, not the payment');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000162', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000032', '220000ff-0022-4000-8000-600000000042', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/many-at-once: a sixth payment against a membership already five periods deep is recorded');

select is(
  (select row(periods_granted, ends_on) from public.memberships where id = '220000ff-0022-4000-8000-600000000042'::uuid),
  (select row(6, (select today from gym_today where org_key = 'A') + 180)),
  'periods_granted/many-at-once: and it grants exactly ONE more (6, +180) — a rule re-deriving from the money rather than from the recorded count would grant six here and land on +330');

-- ---------------------------------------------------------------------------
-- 15d. FOURTH-SESSION REWRITE. This subsection first staged and reported,
-- unscored, the exact defect GL043 now closes: cutting price_paise after a
-- period was already granted let one trivial subsequent payment unlock a
-- second period bought entirely at the OLD, higher price (measured: 1
-- paisa, after a 100000->50000 cut, moved periods_granted 1->2). That is
-- now a migration this session was told about but may not open (dated
-- 20260910000000 or later) — `check`/trigger logic aside, its NAMED effect
-- is: a membership's price_paise and currency are frozen once
-- periods_granted > 0, in BOTH directions, not only the exploitable cut.
-- The two fixtures below keep their old ids and baselines; only what
-- happens AFTER the baseline changes, from "not refused" (the defect) to
-- "refused, and nothing about the ordinary case broke."
-- ---------------------------------------------------------------------------

-- Direction 1: cutting the price after one period was bought at the old,
-- higher price is now refused.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000043'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000033'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 0);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000163', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000033', '220000ff-0022-4000-8000-600000000043', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/price-cut: a full payment at the original 100000 price is recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000043'::uuid),
  1,
  'periods_granted/price-cut: baseline — one period granted at the original price');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000043'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'periods_granted/price-cut: baseline — ends_on moved by that one period. ROUND-TWENTY RECONCILIATION: this read `today + 60`. The fixture is dated today..today+30 with periods_granted typed at ZERO, so this full payment is its FIRST grant and "the first period is set, not added" sets the span from the membership''s own length instead of adding a bought period on top of a typed one. starts_on is already today, so it does not move. Everything this baseline exists to support — that one period was granted at the original price, and the price-cut refusals below are measured against it — is unchanged');

select throws_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000043'$$,
  null::char(5), null,
  'GL043/price-cut: halving the price after the period was already granted at the old one is now refused — this is the exact defect the first version of this section reported unscored');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000043'::uuid),
  100000::bigint,
  'GL043/price-cut: price_paise is unchanged at 100000 — refused AND unmoved');

-- A genuine further payment, at the still-frozen 100000 price, must still
-- work — the freeze is on price_paise/currency, not on the extension.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000164', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000033', '220000ff-0022-4000-8000-600000000043', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/price-cut: right after the refused price edit, an ordinary further payment at the unchanged price still succeeds');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000043'::uuid),
  2,
  'GL043/price-cut: and it grants normally (2 periods now) — the refused price edit did not touch app.grant_periods()''s own writes');

-- Direction 2: raising the price is refused just as symmetrically — the
-- first version of this section called this direction "safe", which was
-- true of the arithmetic (owed fell below granted, nothing negative) and
-- not of the principle GL043 states: frozen once earned, either way.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000044'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000034'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 0);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000165', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000034', '220000ff-0022-4000-8000-600000000044', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'periods_granted/price-raise: a full payment at the original 100000 price is recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000044'::uuid),
  1,
  'periods_granted/price-raise: baseline — one period granted at the original price');

select throws_ok(
  $$update public.memberships set price_paise = 200000 where id = '220000ff-0022-4000-8000-600000000044'$$,
  null::char(5), null,
  'GL043/price-raise: doubling the price after the period was already granted is refused too — same rule, the direction the first version of this section called "safe"');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000044'::uuid),
  100000::bigint,
  'GL043/price-raise: price_paise is unchanged at 100000');

-- ---------------------------------------------------------------------------
-- 15d-currency. The same freeze names currency alongside price_paise — a
-- distinct write, checked on its own rather than only alongside a price
-- change, in case an implementation freezes the row on price_paise touched
-- and lets a currency-only edit through the gap.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update public.memberships set currency = 'USD' where id = '220000ff-0022-4000-8000-600000000044'$$,
  null::char(5), null,
  'GL043/currency: changing ONLY currency (price_paise untouched) on a membership with periods_granted > 0 is refused');

select is(
  (select currency from public.memberships where id = '220000ff-0022-4000-8000-600000000044'::uuid),
  'INR',
  'GL043/currency: currency is unchanged at INR');

-- ---------------------------------------------------------------------------
-- 15d-zero. The freeze must not fire before anything has actually been
-- earned: correcting a mistyped price on a membership with
-- periods_granted = 0 is an ordinary edit and stays free.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000046'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000036'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 0);

select lives_ok(
  $$update public.memberships set price_paise = 80000 where id = '220000ff-0022-4000-8000-600000000046'$$,
  'GL043/zero-grant: correcting price_paise on a membership with periods_granted = 0 (nothing earned yet) still succeeds');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000046'::uuid),
  80000::bigint,
  'GL043/zero-grant: the correction landed');

-- ---------------------------------------------------------------------------
-- 15e. periods_granted may not be negative — checked structurally, as
-- `postgres`, rather than through a tenant session (section 5's own
-- receipt-counter DELETE check took the same structural angle). If this is
-- refused only by an RLS policy rather than a real constraint, provoking it
-- as the table owner is what tells the two apart.
--
-- FOURTH-SESSION UPDATE: `check (periods_granted >= 0)` is now added, in a
-- migration not opened here (dated 20260910000000 or later, named and
-- spliced by the coordinator, not read). The first two assertions are
-- unchanged and now pass; the third is INVERTED from proving the negative
-- value landed to proving it did not — refused AND unmoved, the same
-- discrimination the visible suite's own Section 14e note names.
-- ---------------------------------------------------------------------------

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000045'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000035'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 0);

select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.memberships'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%periods_granted%'),
  1,
  'periods_granted/negative: public.memberships carries a CHECK constraint on periods_granted >= 0');

select throws_ok(
  $$update public.memberships set periods_granted = -1 where id = '220000ff-0022-4000-8000-600000000045'$$,
  null::char(5), null,
  'periods_granted/negative: setting the column negative, as the table owner rather than through any tenant session, is refused');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000045'::uuid),
  0,
  'periods_granted/negative: the column is unchanged at 0 — refused AND unmoved, not merely refused');

-- ---------------------------------------------------------------------------
-- 12. Elevation must still justify itself (ADR-066): the same closed
--     allowlist h21 already asserts, re-checked here in case this
--     contract's own fix reached for `security definer` instead of a plain
--     trigger.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prosecdef
      and p.proname not in ('audit_impersonation_session', 'custom_access_token_hook', 'revoke_sessions_on_identity_change', 'audit_money_change')),
  0,
  'ADR-066/AUD-001: the closed elevation allowlist adds only audit_money_change, explicitly required by the frozen refund audit contract');

-- ---------------------------------------------------------------------------
-- 16. FIFTH-SESSION EXTENSION, written blind by a separate author against
--     GL043 ("the terms a period was scored against do not change after it
--     is granted") and GL044 ("how many periods have been granted is
--     written by the rule and by nobody else"), plus ADR-089's account of
--     what was measured and what was rejected. Nothing implements either
--     rule at the time this section was written; every refusal below is
--     expected RED, and every permitted-side assertion is expected green
--     and is here to fail an over-broad fix.
--
--     Section 15d already covers the two doors round six closed
--     (price_paise, currency). This section deliberately does not re-prove
--     them. It goes at the seams instead:
--
--       (a) plan_id — the THIRD input to what money buys, and by ADR-089's
--           own measurement the easiest of the four doors. Proven not only
--           by the refusal but by its consequence: a further full payment
--           must buy one period of the ORIGINAL plan's length.
--       (b) the refusal must not partially apply — plan_id changed in the
--           same statement as a legitimate column, and neither lands.
--       (c) GL044's harm, not only its refusal: after a refused
--           `periods_granted = 500`, an ordinary payment must still GRANT.
--           ADR-089's third measurement is money taken with ends_on
--           unmoved and no error anywhere, and a rule that refuses the
--           write but leaves the harm reachable has closed nothing.
--       (d) the hand write in every shape a single-row UPDATE is not:
--           multi-row, `UPDATE ... FROM`, a data-modifying CTE, `MERGE`
--           (measured working from an ordinary front-desk session on
--           2026-09-09: periods_granted set to 9), and a CTE that inserts
--           a legitimate payment and hand-writes the column in the SAME
--           statement — the "induce the rule's own write to carry an
--           attacker's value" shape. Every previous defect in this phase
--           survived the single-row case and died on one of these.
--       (e) the write attempted immediately after the rule's own write, in
--           the same transaction. A session GUC set by the granting rule
--           and never reset would pass every other test in this file and
--           fail this one; ADR-089 chose trigger depth over exactly that.
--           And the same write from `service_role`, because "by nobody
--           else" includes the trusted writer.
--       (f) the INSERT door. GL044's scenarios all said "sets
--           periods_granted on a membership"; a membership CREATED
--           carrying a count reaches the identical state without ever
--           issuing an UPDATE. Staged bounded and reported by diag on the
--           first pass, since the contract had not decided; sided on the
--           second, after it did — refused, and the harm behind it gone.
--       (g) the rows ADR-089's REJECTED consistency trigger would have
--           bricked: OPEN-026's half-dated `pending` row (measured
--           2026-09-09: it does record periods_granted = 1), whose only
--           repair is an ordinary UPDATE, and a membership whose money and
--           whose count legitimately disagree because a payment arrived in
--           a currency it is not priced in. Both must stay editable. "The
--           invariant is who writes it, not what it equals" is testable
--           only from this direction.
--       (h) the permitted side generally: a freeze, an unfreeze, a refund
--           and a renewal against a membership that has been granted a
--           period. A fix that is too broad passes every refusal test in
--           this file.
--
--     Cross-tenant is covered where it is cheap and honest about what
--     already holds it up: a plan repoint at another gym's plan is
--     expected to be refused today by ADR-052's composite foreign key, and
--     is asserted as evidence already held rather than as new work.
--
--     Every fixture membership below gets its own member, because
--     memberships_tenant_id_member_id_live_key permits one live
--     (active/frozen) membership per member.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000000005'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 Plan A Long (365d)', 365, 1200000);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000040'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Plan Repoint',   '+919220000240'),
  ('220000ff-0022-4000-8000-500000000041'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Combined',       '+919220000241'),
  ('220000ff-0022-4000-8000-500000000042'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Pre Money',      '+919220000242'),
  ('220000ff-0022-4000-8000-500000000043'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL HandWrite',      '+919220000243'),
  ('220000ff-0022-4000-8000-500000000044'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL SameTxn',        '+919220000244'),
  ('220000ff-0022-4000-8000-500000000045'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Shapes One',     '+919220000245'),
  ('220000ff-0022-4000-8000-500000000046'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Shapes Two',     '+919220000246'),
  ('220000ff-0022-4000-8000-500000000047'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Insert Door',    '+919220000247'),
  ('220000ff-0022-4000-8000-500000000048'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Permitted',      '+919220000248'),
  ('220000ff-0022-4000-8000-500000000049'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Open026',        '+919220000249'),
  ('220000ff-0022-4000-8000-50000000004a'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Currency Split', '+919220000250'),
  ('220000ff-0022-4000-8000-50000000004b'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 GL Ordinary Create', '+919220000251');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted) values
  ('220000ff-0022-4000-8000-600000000050'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000040'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000051'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000041'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000052'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000042'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000053'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000043'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000054'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000044'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000055'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000045'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000056'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000046'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000058'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000048'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-600000000059'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000049'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null,                                              (select today from gym_today where org_key = 'A'), 100000, 0),
  ('220000ff-0022-4000-8000-60000000005a'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-50000000004a'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 0);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 16a. GL043 and the third term: plan_id. Round six froze price_paise and
-- currency; the plan whose duration_days measures a period is re-read on
-- the next payment in exactly the same way, and ADR-089 measured
-- days_added=395 from one ordinary front-desk statement. Asserted through
-- the consequence as well as the refusal — a refusal that left the
-- lengthened plan in place would still be wrong on the next renewal.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000170', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000040', '220000ff-0022-4000-8000-600000000050', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/plan: a full payment at the 30-day plan is recorded by an ordinary front-desk session');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000050'::uuid),
  1,
  'GL043/plan: baseline — one period granted, so the terms have now been scored against');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000050'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'GL043/plan: baseline — that period is 30 days, the plan the money was actually scored against');

select throws_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-600000000050'$$,
  null::char(5), null,
  'GL043/plan: repointing a granted membership at a 365-day plan is refused — the plan is the third input to what money buys, and ADR-089 measured this door as strictly easier than the price cut round six closed');

select is(
  (select plan_id from public.memberships where id = '220000ff-0022-4000-8000-600000000050'::uuid),
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'GL043/plan: plan_id is unchanged — refused AND unmoved, not a refusal that leaves the row repointed anyway');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000171', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000040', '220000ff-0022-4000-8000-600000000050', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/plan: a further full payment against the same membership is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000050'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'GL043/plan: and it buys one period of the ORIGINAL plan''s length (+30, total +60) — the spec''s own scenario, and the assertion that reads +395 if the refusal above did not actually hold');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000050'::uuid),
  2,
  'GL043/plan: the count follows the money normally — the refused plan edit did not disturb the granting rule''s own writes');

-- ---------------------------------------------------------------------------
-- 16b. The refusal must not partially apply. plan_id changed in the same
-- statement as a legitimate column (status): neither may land. A rule
-- implemented as a BEFORE-trigger reset ("quietly put plan_id back")
-- rather than a refusal passes 16a and fails this pair.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000172', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000041', '220000ff-0022-4000-8000-600000000051', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/combined: the baseline payment on the combined-statement fixture is recorded and grants its period');

select throws_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005', status = 'frozen' where id = '220000ff-0022-4000-8000-600000000051'$$,
  null::char(5), null,
  'GL043/combined: a plan repoint smuggled alongside an entirely legitimate status change is refused');

select ok(
  (select plan_id = '220000ff-0022-4000-8000-400000000001'::uuid and status = 'active'::membership_status
     from public.memberships where id = '220000ff-0022-4000-8000-600000000051'::uuid),
  'GL043/combined: NEITHER half landed — the whole statement was refused, not half-applied with the plan quietly reset and the status kept');

select throws_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000002' where id = '220000ff-0022-4000-8000-600000000051'$$,
  null::char(5), null,
  'GL043/cross-tenant: repointing gym A''s granted membership at gym B''s plan is refused — expected to be held up today by ADR-052''s composite foreign key rather than by GL043, and asserted as evidence already held');

select is(
  (select plan_id from public.memberships where id = '220000ff-0022-4000-8000-600000000051'::uuid),
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'GL043/cross-tenant: plan_id is still gym A''s own plan');

-- ---------------------------------------------------------------------------
-- 16c. The permitted side of GL043: before any money has been scored,
-- correcting the plan is an ordinary edit and stays free. Section 15d-zero
-- proves this for price_paise; the plan needs its own, because a fix that
-- freezes plan_id unconditionally passes every refusal above and breaks
-- the console's own membership edit.
-- ---------------------------------------------------------------------------

-- ROUND-ELEVEN RECONCILIATION (GL046). Deciding what a member owes — price,
-- currency, plan or discount — is gym-admin work, so the session performing
-- the correction below is a manager. NOTHING about what the correction DOES
-- has changed; only who may ask for it. Section 20 asserts the front desk's
-- refusal on this same shape, and the two together are what the requirement
-- now says. This is a claim switch, not an assertion change: the count and
-- the wording are untouched.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-600000000052'$$,
  'GL043/pre-money: changing the plan of a membership that has been granted nothing still succeeds — nothing has been scored yet');

select is(
  (select plan_id from public.memberships where id = '220000ff-0022-4000-8000-600000000052'::uuid),
  '220000ff-0022-4000-8000-400000000005'::uuid,
  'GL043/pre-money: and the correction actually landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

-- ---------------------------------------------------------------------------
-- 16d. GL044, and its HARM rather than only its refusal. ADR-089's third
-- measurement is the dangerous one: periods_granted = 500 makes an
-- ordinary 1,000-rupee payment grant nothing — money receipted, ends_on
-- unmoved, no error anywhere. So each refusal is followed by "unchanged",
-- and the battery is then followed by an ordinary payment that must still
-- GRANT. A rule that refuses the write while leaving the eaten payment
-- reachable has closed nothing.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000173', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000043', '220000ff-0022-4000-8000-600000000053', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL044: a full payment is recorded, and the rule writes the count');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000053'::uuid),
  1,
  'GL044: baseline — the rule''s own write put 1 there');

select throws_ok(
  $$update public.memberships set periods_granted = 0 where id = '220000ff-0022-4000-8000-600000000053'$$,
  null::char(5), null,
  'GL044: a front-desk session setting the count back to 0 is refused — 0 is a value the rule itself can produce, so bounding the column''s sign closes nothing and only "who wrote it" can');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000053'::uuid),
  1,
  'GL044: the count is unchanged at 1 — refused AND unmoved');

select throws_ok(
  $$update public.memberships set periods_granted = 500 where id = '220000ff-0022-4000-8000-600000000053'$$,
  null::char(5), null,
  'GL044: raising the count above what the money bought is refused too — this is the direction that eats a real payment rather than the one that buys a free month');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000053'::uuid),
  1,
  'GL044: still 1 after the raise attempt');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000174', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000043', '220000ff-0022-4000-8000-600000000053', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL044/harm: an ordinary further full payment is recorded after both refusals');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000053'::uuid),
  2,
  'GL044/harm: it GRANTS — the count reads 2. Had the raise above landed, this payment would have been swallowed by the arithmetic instead');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000053'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'GL044/harm: and the member actually got the days — ADR-089''s "she pays and ends_on does not move, silently" is the failure this assertion exists for, and it is a different assertion from the refusal above');

-- ---------------------------------------------------------------------------
-- 16e. The same write, immediately after the granting rule's own write, in
-- the same transaction — and then from service_role. A session flag set by
-- the rule and never reset passes every other assertion in this file and
-- fails the first of these; ADR-089 chose trigger depth over exactly that.
-- And "by nobody else" includes the trusted writer the webhook runs as.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000175', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000044', '220000ff-0022-4000-8000-600000000054', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL044/same-txn: a payment grants a period, so the rule has just written the column in THIS transaction');

select throws_ok(
  $$update public.memberships set periods_granted = 0 where id = '220000ff-0022-4000-8000-600000000054'$$,
  null::char(5), null,
  'GL044/same-txn: a hand write in the very next statement is still refused — a flag the rule sets and never resets would let this one through and nothing else in this file would notice');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000054'::uuid),
  1,
  'GL044/same-txn: unchanged at 1');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role service_role;

select throws_ok(
  $$update public.memberships set periods_granted = 0 where id = '220000ff-0022-4000-8000-600000000054'$$,
  null::char(5), null,
  'GL044/service_role: the trusted writer is refused too — "written by the rule and by nobody else" is not "by nobody except the role the webhook happens to run as"');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000054'::uuid),
  1,
  'GL044/service_role: unchanged at 1');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 16f. Every shape a single-row UPDATE is not. Measured on 2026-09-09 from
-- an ordinary front-desk session: the MERGE below set periods_granted to
-- 9. Two memberships, so the multi-row statement has something to be
-- multi-row about, and each refusal is paired with a count of how many of
-- the two still read the value the rule put there.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    ('220000ff-0022-4000-8000-700000000176', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000045', '220000ff-0022-4000-8000-600000000055', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    ('220000ff-0022-4000-8000-700000000177', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000046', '220000ff-0022-4000-8000-600000000056', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL044/shapes: one statement, a full payment for each of two memberships, is recorded');

select is(
  (select count(*)::int from public.memberships
    where id in ('220000ff-0022-4000-8000-600000000055'::uuid, '220000ff-0022-4000-8000-600000000056'::uuid)
      and periods_granted = 1),
  2,
  'GL044/shapes: baseline — both memberships read 1, written by the rule');

select throws_ok(
  $$update public.memberships set periods_granted = 0
      where id in ('220000ff-0022-4000-8000-600000000055', '220000ff-0022-4000-8000-600000000056')$$,
  null::char(5), null,
  'GL044/shapes: ONE statement updating SEVERAL memberships is refused');

select is(
  (select count(*)::int from public.memberships
    where id in ('220000ff-0022-4000-8000-600000000055'::uuid, '220000ff-0022-4000-8000-600000000056'::uuid)
      and periods_granted = 1),
  2,
  'GL044/shapes: both rows unchanged after the multi-row attempt — not one refused and one through');

select throws_ok(
  $$update public.memberships m set periods_granted = v.n
      from (values ('220000ff-0022-4000-8000-600000000055'::uuid, 0),
                   ('220000ff-0022-4000-8000-600000000056'::uuid, 7)) as v(id, n)
     where m.id = v.id$$,
  null::char(5), null,
  'GL044/shapes: UPDATE ... FROM, giving each row its own hand-chosen value, is refused');

select is(
  (select count(*)::int from public.memberships
    where id in ('220000ff-0022-4000-8000-600000000055'::uuid, '220000ff-0022-4000-8000-600000000056'::uuid)
      and periods_granted = 1),
  2,
  'GL044/shapes: both rows unchanged after the UPDATE ... FROM attempt');

select throws_ok(
  $$with u as (
      update public.memberships set periods_granted = 0
       where id = '220000ff-0022-4000-8000-600000000055' returning 1
    ) select count(*) from u$$,
  null::char(5), null,
  'GL044/shapes: a data-modifying CTE is refused — the write is no less a hand write for being wrapped in a WITH');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000055'::uuid),
  1,
  'GL044/shapes: unchanged after the CTE attempt');

select throws_ok(
  $$merge into public.memberships m
      using (values ('220000ff-0022-4000-8000-600000000055'::uuid)) as s(id)
      on m.id = s.id
      when matched then update set periods_granted = 9$$,
  null::char(5), null,
  'GL044/shapes: MERGE is refused — measured working from an ordinary front-desk session on 2026-09-09, setting the count to 9');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000055'::uuid),
  1,
  'GL044/shapes: unchanged after the MERGE attempt');

select throws_ok(
  $$with p as (
      insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000178', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000045', '220000ff-0022-4000-8000-600000000055', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')
      returning membership_id
    )
    update public.memberships set periods_granted = 0 where id in (select membership_id from p)$$,
  null::char(5), null,
  'GL044/induced: a statement that records a perfectly legitimate payment AND hand-writes the count, together, is refused — the rule''s own write may not be used as cover for somebody else''s value');

select ok(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000055'::uuid) = 1
    and not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-700000000178'::uuid),
  'GL044/induced: and the WHOLE statement was refused — the count is still 1 and the legitimate-looking payment inside the CTE was not written either');

-- ---------------------------------------------------------------------------
-- 16g. The INSERT door — SIDED in the fifth session, having been staged
-- bounded in the fourth. This author reported that GL044's sentence
-- ("SHALL refuse every other write to it") covered a membership CREATED
-- carrying a count while none of its scenarios named one, and measured the
-- consequence live: a front-desk session created a membership with
-- periods_granted = 5, took 100000 for it, and ends_on did not move while
-- the receipt was issued — ADR-089's third exploit with no UPDATE anywhere
-- in it. The requirement now says a membership is created having been
-- granted nothing, so this is asserted as a refusal AND as the absence of
-- the harm behind it: the same membership, created the ordinary way,
-- must still grant and still move ends_on on its first payment.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, periods_granted)
    values ('220000ff-0022-4000-8000-600000000057', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-500000000047', '220000ff-0022-4000-8000-400000000001',
            'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 5)$$,
  null::char(5), null,
  'GL044/insert-door: a front-desk session CREATING a membership that carries periods_granted = 5 is refused — the count is the rule''s to write, and an INSERT is a write');

select ok(
  not exists (select 1 from public.memberships where id = '220000ff-0022-4000-8000-600000000057'::uuid),
  'GL044/insert-door: and nothing landed — refused AND unwritten, not a membership quietly created with the count reset');

-- The harm behind that refusal, on its own row and its own member, so
-- these three are green before the rule lands and must stay green after
-- it: a duplicate-key failure inherited from the refusal above would be a
-- false red, and this file has to be able to tell an over-broad fix from
-- an unimplemented one.
select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('220000ff-0022-4000-8000-600000000060', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-50000000004b', '220000ff-0022-4000-8000-400000000001',
            'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000)$$,
  'GL044/insert-door: a membership created the ordinary way, naming no count, still succeeds — a rule that refused every membership creation would pass the assertion above and break the console''s create screen');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000179', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000004b', '220000ff-0022-4000-8000-600000000060', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL044/insert-door: and a full payment against it is recorded');

select is(
  (select row(periods_granted, ends_on) from public.memberships where id = '220000ff-0022-4000-8000-600000000060'::uuid),
  (select row(1, (select today from gym_today where org_key = 'A') + 30)),
  'GL044/insert-door: the harm is gone, not merely the write — the member got the 30 days the money bought, which is the thing the seeded count silently ate when this was measured');

-- ---------------------------------------------------------------------------
-- 16h. The permitted side, generally. A fix that is too broad passes every
-- refusal above; this project has shipped that three times. On a
-- membership that HAS been granted a period: a freeze, an unfreeze and a
-- refund must all still work, and none of them may disturb the count.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000180', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000048', '220000ff-0022-4000-8000-600000000058', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'permitted: the baseline payment on the over-enforcement fixture is recorded and grants its period');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000000058'$$,
  'permitted: freezing a membership that has been granted a period still works — status is not a term the money was scored against');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000000058'$$,
  'permitted: and unfreezing it works too');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000040', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000180', 'refund', 40000, 'h22 partial refund against a granted membership', '220000ff-0022-4000-8000-300000000002')$$,
  'permitted: a refund against a payment that granted a period is still recordable — money going out is not a change of terms');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000058'::uuid),
  1,
  'permitted: and after the freeze, the unfreeze and the refund the count is still exactly 1 — none of them is a grant, and none of them may quietly re-derive it');

-- Writing the same count back, which GL044 decides is allowed. A rule
-- written as "refuse any UPDATE naming this column from outside the
-- granting rule" — the shortest thing that passes every refusal above —
-- fails both of these, and the second is the shape that matters: an ORM or
-- a console form that writes every column it loaded is not an attack.

select lives_ok(
  $$update public.memberships set periods_granted = 1 where id = '220000ff-0022-4000-8000-600000000058'$$,
  'permitted/same-value: writing the count back at the value it already held is allowed — it moves nothing, and every exploit GL044 exists for needs the value moved');

select lives_ok(
  $$update public.memberships set status = 'frozen', periods_granted = 1 where id = '220000ff-0022-4000-8000-600000000058'$$,
  'permitted/same-value: and an ordinary column-listing update that carries the unchanged count alongside a real change is allowed too — the reason the same-value case was decided this way');

-- ---------------------------------------------------------------------------
-- 16i. The rows ADR-089's REJECTED consistency trigger would have bricked.
-- "The invariant is who writes it, not what it equals" is only testable
-- from this direction: rows where the recorded count and the money on
-- record legitimately disagree, or where the row is malformed, must stay
-- editable — including by the very update that repairs them.
--
-- (i) OPEN-026's half-dated `pending` row: starts_on null, ends_on set.
-- Measured on 2026-09-09: paying it DOES record periods_granted = 1 and
-- move ends_on, while the row cannot be activated because
-- memberships_dated_unless_pending_chk refuses an active row with a null
-- starts_on. Its only repair is an ordinary UPDATE, on a row that by then
-- has a period granted against it.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000181', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000049', '220000ff-0022-4000-8000-600000000059', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'OPEN-026: a full payment against the half-dated pending row is recorded');

-- RECONCILED IN ROUND TEN, by this file's own round-ten author. These two
-- assertions read "giving that row the missing starts_on — its only repair —
-- still succeeds" and "the repaired row can then be activated". GL045 refuses
-- that write: a null date is a value the granting rule has not written, not a
-- licence for the desk. Section 19e asserts the same refusal on the same shape
-- from the other side (453/454, 457/458), the visible suite reached it
-- independently, and the requirement accepts the cost in as many words. The
-- contract is the authority; an exemption carved to keep these two green would
-- be the rule acquiring an edge nobody decided.
--
-- What 16i(i) actually existed to protect is NOT deleted. ADR-089 rejected a
-- consistency trigger because it would have bricked rows whose count and money
-- legitimately disagree; that row must still be EDITABLE, and it is — in every
-- column except the two the granting rule now owns. The last assertion here
-- proves it, and the two before it record exactly what the row is left as.
select throws_ok(
  $$update public.memberships set starts_on = (select today from gym_today where org_key = 'A')
      where id = '220000ff-0022-4000-8000-600000000059'$$,
  'GL045'::char(5), null,
  'OPEN-026 / GL045: giving that row its missing starts_on — what used to be its only repair — is REFUSED. The row has a receipted payment against it and a period granted, and the date it needs to be usable is now the granting rule''s alone to write');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000059'::uuid),
  'NULL/30/pending/1',
  'OPEN-026 / GL045: so it stays exactly as the money left it — starts_on null, ends_on moved by the period it bought, one period granted, and still `pending`, because activating a row with a null starts_on violates memberships_dated_unless_pending_chk. Money taken, receipt issued, period recorded, member refused at the gate, and now unrepairable IN PLACE');

select throws_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000000059'$$,
  '23514'::char(5), null,
  'OPEN-026 / GL045: and activating it is refused by the CHECK rather than by any rule of this phase''s — the same 23514 round three made abort loudly. The only remaining route to this member is a new membership; the requirement now says so');

-- ROUND-ELEVEN RECONCILIATION (GL046): discount_paise is one of the four
-- columns re-pricing now covers, so the session that edits it is a manager.
-- The point of the assertion — the row is still editable — is unchanged, and
-- is now the sharper claim, because a manager is who repairs such a row.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select throws_ok(
  $$update public.memberships set discount_paise = 5000 where id = '220000ff-0022-4000-8000-600000000059'$$,
  'GL043', null,
  'NET-PRICE / OPEN-026: a paid half-dated row cannot change its discount; the new contract freezes that scored term even when its lifecycle remains unresolved');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

-- ---------------------------------------------------------------------------
-- (ii) A membership whose money and whose count genuinely disagree, built
-- only out of writes the rule itself made: a payment in a currency the
-- membership is not priced in counts toward no multiple, so the table
-- holds 200000 paise against a 100000 price while the count reads 1.
-- Anything comparing the two would refuse every later update to this row.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000182', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000004a', '220000ff-0022-4000-8000-60000000005a', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'currency-split: the INR payment is recorded and grants the period');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000183', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000004a', '220000ff-0022-4000-8000-60000000005a', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'currency-split: a payment in a currency the membership is not priced in is recorded');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-60000000005a'::uuid),
  1,
  'currency-split: the count stays 1 — a currency-blind sum would read 200000 against a 100000 price and say 2, so this row now legitimately disagrees with its own money');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-60000000005a'$$,
  'currency-split: and that legitimately-disagreeing row is still editable — the rejected consistency trigger would have refused every future update to it, including the ones that fix it');

-- ---------------------------------------------------------------------------
-- 17. SIXTH-SESSION EXTENSION, written blind by yet another author against
--     the round-EIGHT form of GL043 ("the terms money is scored against are
--     frozen by MONEY ARRIVING"), the new GL039 ("a payment does not arrive
--     already refunded"), and ADR-090 — including the design ADR-090
--     rejects, because that is where the interesting failure modes live.
--     GL044 is unchanged this round and is not re-proved; section 16 has it.
--
--     WHY THIS SECTION EXISTS. Round seven froze a membership's terms once
--     `periods_granted > 0` and made that column unforgeable so the gate
--     could be trusted. A critic then showed the GATE ITSELF says the wrong
--     thing: a membership that has taken real money but not yet crossed one
--     whole multiple of its price sits at `periods_granted = 0` with every
--     term open — an ordinary PART PAYMENT — and the exploit the round was
--     written to close survived it (₹10,800 against a ₹12,000 Annual: cut
--     the price, pay one paisa, `ends_on` moves ten years).
--
--     And the reason it survived lands directly on this file. The
--     requirement's PROSE said "before any money has arrived"; its SCENARIO
--     three lines below said "granted nothing"; the implementation was
--     built to the scenario, and BOTH blind suites — this one included —
--     asserted the weaker sentence and went green. The arrangement cannot
--     catch a scenario that encodes the implementation's own assumption. So
--     this section was written by reading the requirement for internal
--     contradiction FIRST, and every assertion below follows the
--     requirement's prose, not its scenario list.
--
--     WHAT THIS AUTHOR READ: the round-eight
--     openspec/changes/phase-5-money/specs/payment-record/spec.md,
--     docs/decisions.md ADR-090 (with ADR-088/089 for background), the live
--     Cloud catalogue, and this file. NOT read, then or since:
--     supabase/tests/22_payment_record.sql (a different author was writing
--     the visible battery for the same requirement in parallel); any
--     migration dated 20260910230001 or later; prosrc or
--     pg_get_functiondef for anything implementing GL043, GL044 or GL039.
--
--     THE SEAMS, and why each is a seam rather than a re-run of the
--     headline ADR-090 already records:
--
--       (a) THE BOUNDARY OF "MONEY HAS ARRIVED" — 17d, the largest
--           subsection, because that phrase is what the whole requirement
--           now turns on and the requirement never defines it. A payment at
--           `created`; at `failed`; one INSERTED at `created` and later
--           MOVED to `paid`; money PAID AND THEN FULLY REFUNDED (the grant
--           total counts `refunded`, so the membership must stay frozen — a
--           thaw here is a free re-price); money in a currency the
--           membership is not priced in; money against a DIFFERENT
--           membership of the same member; and a payment whose
--           `membership_id` is moved while it is still a working document
--           and only then paid. Each answers one question: does the freeze
--           track the MONEY, or something merely correlated with it — a
--           payment row, a member, a granted period, a status?
--
--       (b) THE RECORDED DURATION AGAINST THE PLAN'S — 17b and 17c. The new
--           term is the only one that is FILLED rather than supplied, which
--           grows two doors nothing else in this file covers: a membership
--           that pre-dates the column (asserted structurally — a null there
--           is a silent fall-back to whatever the plan says today, which is
--           the very defect the column removes, reintroduced for every row
--           the product already has), and a caller who supplies the term at
--           CREATE time. ADR-089's whole lesson was "closing three doors
--           and leaving the fourth"; the fourth door on this term is the
--           INSERT. Then the behaviour ADR-090 actually promises: a plan
--           legitimately re-lengthened, after which an EXISTING membership
--           renews at the length it was SOLD at and a NEW one is sold at
--           the new length — two memberships, one plan, two lengths, which
--           is the whole reason for recording it rather than freezing the
--           `plans` row (ADR-090's rejected design).
--
--       (c) MULTI-ROW AND MULTI-STATEMENT — 17e. Every defect in this phase
--           survived the single-row case and died on one of these: one
--           statement editing several memberships where only SOME have
--           money, `UPDATE ... FROM`, `MERGE`, a data-modifying CTE that
--           takes the FIRST payment and cuts the price in the SAME
--           statement, and two statements in one transaction where the
--           first is entirely legitimate.
--
--       (d) THE PERMITTED SIDE, everywhere — a moneyless membership stays
--           editable in all four terms, a plan stays re-lengthenable by a
--           gym admin, a renewal against a part-paid membership still
--           works, and `created`/`pending`/`paid`/`failed` payments still
--           insert. A FIX THAT IS TOO BROAD PASSES EVERY REFUSAL TEST, and
--           this project has shipped one three times.
--
--       (e) GL039 — 17f. `refunded` and `reversed` refused on INSERT, the
--           four legitimate statuses unaffected, and the HARM behind it
--           gone: after the refused inserts, one paisa must still buy
--           nothing.
--
--     EVERY REFUSAL BELOW ASSERTS BOTH THE REFUSAL AND THAT THE VALUE IS
--     UNCHANGED, and the refusal is checked through `pg_temp.h22r8_refused`
--     rather than the house `throws_ok(..., null::char(5), null, ...)`. The
--     reason is specific to this round: the new term lives in a column that
--     does not exist yet, and `throws_ok` with a null expected code passes
--     on ANY error — including `42703 undefined_column`. A refusal battery
--     written the house way would have gone GREEN against an unimplemented
--     contract, which is exactly the failure mode this round exists to
--     correct. `h22r8_refused` treats "there is no such column, table,
--     function or syntax" as NOT a refusal.
--
--     TWO THINGS THIS AUTHOR SIDED ON THAT THE REQUIREMENT DOES NOT SAY,
--     both reported to the coordinator rather than buried here:
--       * "Money has arrived" is read as the grant total's own definition,
--         stated one requirement over: `paid`, `refunded` and `reversed`
--         count; `created`, `pending` and `failed` do not. Reading it as "a
--         payment row exists" would make "correcting a mistake before any
--         money arrives stays free" almost unreachable, since ADR-083 has
--         the console create the membership and its `created` payment
--         together, and a declined card would lock a mistyped price for
--         ever.
--       * Money in a currency the membership is NOT priced in still FREEZES
--         it, even though it grants nothing. The prose is "any money has
--         arrived against a membership", not "any money in its currency",
--         and the alternative is a live exploit in the other direction:
--         take foreign money, then re-point `currency` at it and watch
--         every unit of it score.
--     One thing this author DECLINED to side on, staged bounded and
--     reported by `diag` in the house style: whether a legitimate PRE-MONEY
--     `plan_id` correction re-records the duration (17c).
-- ---------------------------------------------------------------------------

set local role postgres;

-- A refusal probe that can tell a rule from a missing column. `execute`
-- inside a plpgsql exception block rolls back to an implicit savepoint, so a
-- refused statement leaves the transaction usable, exactly as throws_ok does.
create function pg_temp.h22r8_try(sql text) returns text
language plpgsql as $fn$
begin
  execute sql;
  return 'OK';
exception when others then
  return sqlstate;
end
$fn$;

create function pg_temp.h22r8_refused(sql text) returns boolean
language sql as $fn$
  select pg_temp.h22r8_try(sql) not in ('OK', '42703', '42P01', '42883', '42601')
$fn$;

-- Reading a column that may not exist yet must FAIL an assertion, not abort
-- the file: a bare `select duration_days ...` at top level would take the
-- whole suite down with a parse error instead of leaving one clean `not ok`.
create function pg_temp.h22r8_val(sql text) returns text
language plpgsql as $fn$
declare r text;
begin
  execute sql into r;
  return r;
exception when others then
  return 'ERR:' || sqlstate;
end
$fn$;

grant execute on function pg_temp.h22r8_try(text) to public;
grant execute on function pg_temp.h22r8_refused(text) to public;
grant execute on function pg_temp.h22r8_val(text) to public;

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-4000000000c1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 R8 Plan L (30d, to be re-lengthened)', 30, 100000);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-5000000000c0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Dur Ordinary',     '+919220000300'),
  ('220000ff-0022-4000-8000-5000000000c1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Dur InsertDoor',  '+919220000301'),
  ('220000ff-0022-4000-8000-5000000000c2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Sold Before',     '+919220000302'),
  ('220000ff-0022-4000-8000-5000000000c3'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Sold After',      '+919220000303'),
  ('220000ff-0022-4000-8000-5000000000c4'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 PreMoney Plan',   '+919220000304'),
  ('220000ff-0022-4000-8000-5000000000d0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Created Only',    '+919220000310'),
  ('220000ff-0022-4000-8000-5000000000d1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Failed Only',     '+919220000311'),
  ('220000ff-0022-4000-8000-5000000000d2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Created To Paid', '+919220000312'),
  ('220000ff-0022-4000-8000-5000000000d3'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Part Paid',       '+919220000313'),
  ('220000ff-0022-4000-8000-5000000000d4'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Fully Refunded',  '+919220000314'),
  ('220000ff-0022-4000-8000-5000000000d5'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Foreign Money',   '+919220000315'),
  ('220000ff-0022-4000-8000-5000000000d6'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Two Memberships', '+919220000316'),
  ('220000ff-0022-4000-8000-5000000000d7'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Moved From',      '+919220000317'),
  ('220000ff-0022-4000-8000-5000000000d8'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 Moved To',        '+919220000318'),
  ('220000ff-0022-4000-8000-5000000000e0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 MultiRow Money',  '+919220000320'),
  ('220000ff-0022-4000-8000-5000000000e1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 MultiRow Clean',  '+919220000321'),
  ('220000ff-0022-4000-8000-5000000000e2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 CTE Same Stmt',   '+919220000322'),
  ('220000ff-0022-4000-8000-5000000000f0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 GL039 Harm',      '+919220000330'),
  ('220000ff-0022-4000-8000-5000000000f1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 GL039 Allowed',   '+919220000331'),
  ('220000ff-0022-4000-8000-5000000000f2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 GL039 Trusted',   '+919220000332'),
  ('220000ff-0022-4000-8000-5000000000f3'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R8 No Money At All', '+919220000333');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-6000000000c2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000c2'::uuid, '220000ff-0022-4000-8000-4000000000c1'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000c4'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000c4'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d0'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d1'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d2'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d3'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d3'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d4'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d4'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d5'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d5'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d6'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d6'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d7'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d6'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired', (select today from gym_today where org_key = 'A') - 60, (select today from gym_today where org_key = 'A') - 30, 100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d8'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d7'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000d9'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000d8'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000e0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000e0'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000e1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000e1'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000e2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000e2'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000f0'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000f0'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      300000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000f1'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000f1'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000f2'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000f2'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      300000, 'INR'),
  ('220000ff-0022-4000-8000-6000000000f3'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-5000000000f3'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',  (select today from gym_today where org_key = 'A'),      (select today from gym_today where org_key = 'A'),      100000, 'INR');

-- ---------------------------------------------------------------------------
-- 17a. The duration a period is measured in is a RECORDED term. Structural,
-- as `postgres`, because the two ways this goes wrong are both invisible
-- from a tenant session: the column not existing at all, and the column
-- existing but holding NULL for every membership that pre-dates it.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'memberships' and column_name = 'duration_days'),
  1,
  'GL043/duration: public.memberships RECORDS the duration a period is measured in, rather than reading it from plans when money arrives');

select is(
  pg_temp.h22r8_val($q$select count(*)::text from public.memberships where duration_days is null$q$),
  '0',
  'GL043/duration: and NO membership anywhere is missing it — including every membership created before the column existed, which is the population a backfill either covers or silently leaves reading the plan');

-- ---------------------------------------------------------------------------
-- 17b. It is filled at creation, and the caller does not get to choose it.
-- ADR-089's lesson was "closing three doors and leaving the fourth", and the
-- fourth door on a filled term is the INSERT: a front-desk session creating
-- a membership at price 100000 carrying duration_days = 3650, then paying
-- the full price once, is the same ten-year exploit with no UPDATE anywhere
-- in it. Asserted either-way (refused outright, or the value ignored and
-- filled from the plan) and then by the harm — both are acceptable and
-- neither may leave 3650 on the row.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('220000ff-0022-4000-8000-6000000000c0', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-5000000000c0', '220000ff-0022-4000-8000-400000000001',
            'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000)$$,
  'GL043/duration: an ordinary front-desk membership create, naming no duration, still succeeds');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-6000000000c0'$q$),
  '30',
  'GL043/duration: and it recorded 30 — the duration of the plan it was actually sold on, taken at creation like the price and the currency beside it');

-- The create-with-a-duration attempt itself, in a DO block so that whichever
-- way it goes it puts nothing on the TAP stream and cannot abort the file.
do $do$
begin
  begin
    insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, duration_days)
      values ('220000ff-0022-4000-8000-6000000000c1', '220000ff-0022-4000-8000-100000000001',
              '220000ff-0022-4000-8000-5000000000c1', '220000ff-0022-4000-8000-400000000001',
              'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 3650);
  exception when others then null;
  end;
end
$do$;

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('220000ff-0022-4000-8000-6000000000c1', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-5000000000c1', '220000ff-0022-4000-8000-400000000001',
            'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000)
    on conflict do nothing$$,
  'GL043/insert-door: the same membership is then created the ordinary way if that attempt was refused, so the row exists either way and the next assertions measure the TERM rather than the refusal');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-6000000000c1'$q$),
  '30',
  'GL043/insert-door: a caller-supplied duration_days = 3650 did not survive the create — refused outright, or ignored and filled from the plan; either is acceptable and 3650 is not');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001c0', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000c1', '220000ff-0022-4000-8000-6000000000c1', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/insert-door: and one full payment against it is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-6000000000c1'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'GL043/insert-door: the harm is gone, not merely the write — that payment bought 30 days, not the 3650 the create asked for');

-- ---------------------------------------------------------------------------
-- 17c. What recording it is FOR: a plan legitimately re-lengthened. This is
-- the behaviour ADR-090 promises and the reason it REJECTED freezing the
-- `plans` row — a gym must be able to re-length a plan for future sales. So,
-- on one plan: a membership sold BEFORE the change renews at the length it
-- was sold at, and a membership sold AFTER it is sold at the new one. Two
-- memberships, one plan, two lengths, which is the whole design.
--
-- The measured defect this replaces: one manager statement setting
-- duration_days = 3650 plus one ordinary renewal moved ends_on 3650 days,
-- silently, for EVERY membership on that plan.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001c1', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000c2', '220000ff-0022-4000-8000-6000000000c2', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/re-length: the membership sold on the 30-day plan takes its first full payment');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-6000000000c2'::uuid),
  (select today from gym_today where org_key = 'A') + 30,
  'GL043/re-length: baseline — that period is 30 days, the length it was sold at');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$update public.plans set duration_days = 3650 where id = '220000ff-0022-4000-8000-4000000000c1'$$,
  'GL043/re-length: a gym admin re-lengthening a plan STILL WORKS — ADR-090 rejected freezing the plans row precisely so this stays possible, and a fix that closed this door would pass every refusal in this file');

select is(
  (select duration_days from public.plans where id = '220000ff-0022-4000-8000-4000000000c1'::uuid),
  3650,
  'GL043/re-length: and the plan edit actually landed');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001c2', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000c2', '220000ff-0022-4000-8000-6000000000c2', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/re-length: an ordinary renewal against the already-sold membership is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-6000000000c2'::uuid),
  (select today from gym_today where org_key = 'A') + 60,
  'GL043/re-length: and it bought 30 MORE days, the length that membership was SOLD at — this reads today+3680 if a period is still measured by whatever the plan says now, which is the defect measured at 3650 days for one manager statement');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-6000000000c2'::uuid),
  2,
  'GL043/re-length: two full prices, two periods — the count follows the money exactly as before');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
    values ('220000ff-0022-4000-8000-6000000000c3', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-5000000000c3', '220000ff-0022-4000-8000-4000000000c1',
            'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000)$$,
  'GL043/re-length: a NEW membership is now sold on the same, re-lengthened plan');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001c3', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000c3', '220000ff-0022-4000-8000-6000000000c3', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/re-length: and takes its first full payment');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-6000000000c3'::uuid),
  (select today from gym_today where org_key = 'A') + 3650,
  'GL043/re-length: it gets the NEW length — editing a plan changes what the NEXT membership is sold at and nothing about one already sold, which is what editing a plan should mean. One plan, two memberships, two lengths');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set duration_days = 3650 where id = '220000ff-0022-4000-8000-6000000000c2'$q$),
  'GL043/duration-frozen: typing a length onto this membership is refused. ROUND NINE CORRECTED THE REASON, not the refusal: this assertion was written as though the length were frozen BY MONEY, like the price beside it, and the pre-money half that implies is a measured 3,650-day exploit (ADR-092). The length is derived and never typed, so this is refused because it is typed — not because money has arrived. Section 18a asserts the same statement against a membership that has never been paid a paisa');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-6000000000c2'$q$),
  '30',
  'GL043/duration-frozen: and it is unchanged at 30 — refused AND unmoved');

-- A legitimate PRE-MONEY plan correction. Round eight left this open and
-- this author declined to guess; ADR-092 answers it, and the answer is the
-- reason the door exists at all: changing the plan RE-DERIVES the length,
-- which is the only instrument a desk has for a wrong term. So the bounded
-- assertion below is now sided at the corrected plan's length. The price
-- re-derives with it, which this fixture cannot show — both plans here are
-- priced 100000 — so section 18c proves that half on plans that differ.

-- ROUND-ELEVEN RECONCILIATION (GL046): a plan correction is now gym-admin
-- work, so the correction below is made by a manager and the payment after it
-- is still taken by the desk. The scenario this transcribes said "a front-desk
-- session" for four rounds and is the sentence a critic walked through to buy
-- 300 days for one month's fee; it now says "a gym admin", and so does this.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-4000000000c1' where id = '220000ff-0022-4000-8000-6000000000c4'$$,
  'GL043/pre-money: correcting the plan of a membership against which no money has arrived is still allowed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-6000000000c4'$q$),
  '3650',
  'GL043/pre-money: and the correction RE-DERIVED the recorded length from the corrected plan — a wrong length is a wrong plan, and re-pointing the plan is the only instrument that may move the term');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001c4', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000c4', '220000ff-0022-4000-8000-6000000000c4', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/pre-money: and the first payment against the corrected membership is recorded');

select is(
  (select ends_on - starts_on from public.memberships where id = '220000ff-0022-4000-8000-6000000000c4'::uuid),
  3650,
  'GL043/pre-money: and the money bought a period of the CORRECTED plan''s length — the round-eight open question, sided by ADR-092. The correction lands whole, which is what makes refusing the typed length affordable: the desk keeps an instrument for a genuinely wrong term');

-- ---------------------------------------------------------------------------
-- 17d. THE BOUNDARY OF "MONEY HAS ARRIVED". The requirement now turns on
-- that phrase and never defines it; the only definition in the document is
-- one requirement over, where the grant total is "money that ARRIVED —
-- paid, refunded and reversed — not money still held". Every case below asks
-- the same question from a different side: does the freeze track the money,
-- or something merely correlated with it?
-- ---------------------------------------------------------------------------

-- (i) A payment that has not arrived: `created`. Under ADR-083 the console
-- creates the membership and its `created` payment together, so if this row
-- froze the terms, "correcting a mistyped price before any money arrives"
-- would be unreachable in the very product this requirement is written for.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d0', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d0', '220000ff-0022-4000-8000-6000000000d0', 50000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/created: a payment is raised against the membership and not yet taken');

-- ROUND-ELEVEN RECONCILIATION (GL046): this pair proves WHEN the terms are
-- still free, not who may move them, so the correction is sent by a manager.
-- Same switch as 16c, 17c, 17g, 18b, 18c, 18e and 19g; the payment statements
-- around it stay at the desk, because a payment is recorded by the staff
-- member who took it (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 90000 where id = '220000ff-0022-4000-8000-6000000000d0'$$,
  'arrived/created: the price is still correctable — a raised, unpaid payment is not money that has arrived, and freezing on the existence of a payment ROW would lock every membership the console creates');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d0'::uuid),
  90000::bigint,
  'arrived/created: and the correction landed');
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);


-- (ii) A payment that arrived and then did not: `failed`. A declined card
-- must not lock a mistyped price for ever.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d1', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d1', '220000ff-0022-4000-8000-6000000000d1', 50000, 'cash', 'failed', '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/failed: a failed attempt is recorded against the membership');

-- ROUND-ELEVEN RECONCILIATION (GL046): this pair proves WHEN the terms are
-- still free, not who may move them, so the correction is sent by a manager.
-- Same switch as 16c, 17c, 17g, 18b, 18c, 18e and 19g; the payment statements
-- around it stay at the desk, because a payment is recorded by the staff
-- member who took it (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 90000 where id = '220000ff-0022-4000-8000-6000000000d1'$$,
  'arrived/failed: the price is still correctable — the grant total excludes failed rows, so the terms have never been scored against anything');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d1'::uuid),
  90000::bigint,
  'arrived/failed: and the correction landed');
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);


-- (iii) The same row, MOVED between statuses. The money arrives on an
-- UPDATE, not an INSERT — a rule hung on the insert path alone sees nothing,
-- and ADR-070 says every defect in this spec has had that shape: enforced
-- where the row is born and not where it changes.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d2', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d2', '220000ff-0022-4000-8000-6000000000d2', 50000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/moved: a part payment is raised at created');

select lives_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-7000000001d2'$$,
  'arrived/moved: and is then taken — the money arrives on an UPDATE, which is the only way a Razorpay payment ever arrives');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000d2'$q$),
  'arrived/moved: the terms are now frozen — half the price has arrived, nothing has been granted, periods_granted is still 0, and that is exactly the window ADR-090 measured ten years of membership through');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d2'::uuid),
  100000::bigint,
  'arrived/moved: and the price is unchanged at 100000 — refused AND unmoved');

-- (iv) The plain part payment, all four terms at once, then the consequence:
-- ADR-090's headline measured on its own fixture rather than re-quoted.
-- Three refusals, three unchanged, then one further half payment that must
-- buy exactly ONE period of the ORIGINAL length at the ORIGINAL price. If
-- any of the three edits landed, this reads two periods, or 365 days, or —
-- if the currency moved — nothing at all.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d3', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d3', '220000ff-0022-4000-8000-6000000000d3', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/part: half the price arrives, is receipted, and buys nothing — ordinary practice in an Indian gym, and the console says so on the page');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  0,
  'arrived/part: baseline — real money in, nothing granted. This is the state round seven left every term open in');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000d3'$q$),
  'arrived/part: cutting the price is refused — the money was ALREADY being scored against it, whether or not it had crossed a multiple');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  100000::bigint,
  'arrived/part: the price is unchanged at 100000');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set currency = 'USD' where id = '220000ff-0022-4000-8000-6000000000d3'$q$),
  'arrived/part: changing the currency is refused — re-denominating a membership that has taken rupees re-scores every rupee already on record');

select is(
  (select currency from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  'INR',
  'arrived/part: the currency is unchanged at INR');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-6000000000d3'$q$),
  'arrived/part: repointing it at a 365-day plan is refused');

select is(
  (select plan_id from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'arrived/part: the plan is unchanged');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d4', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d3', '220000ff-0022-4000-8000-6000000000d3', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/part: the balance is paid — a renewal against a frozen membership must still work, and a fix that broke this would pass every refusal above');

select is(
  (select row(periods_granted, ends_on) from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  (select row(1, (select today from gym_today where org_key = 'A') + 30)),
  'arrived/part: and the two halves bought exactly one 30-day period at the ORIGINAL price — the single assertion that reads wrong if any of the three refusals above merely raised while leaving the row edited');

-- (v) MONEY PAID AND THEN FULLY REFUNDED. The grant total counts refunded
-- money — "monotonic is what makes crossing a multiple mean anything" — so a
-- membership whose only money has been handed back is still scored against
-- its terms and must stay frozen. A thaw here is a free re-price reachable
-- by paying and immediately refunding, and it looks like generosity in the
-- ledger.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d5', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d4', '220000ff-0022-4000-8000-6000000000d4', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/refunded: half the price arrives');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-7000000001d5'$$,
  'arrived/refunded: and is then handed back in full');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-6000000000d4'::uuid),
  0,
  'arrived/refunded: nothing was ever granted, so the round-seven gate reads 0 here just as it does on an untouched membership');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000d4'$q$),
  'arrived/refunded: the terms are STILL frozen — the total counts refunded money, so this membership is still scored against its price, and a rule that thaws on refund sells a re-price for the cost of a same-day refund');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d4'::uuid),
  100000::bigint,
  'arrived/refunded: unchanged at 100000');

-- (vi) MONEY IN A CURRENCY THE MEMBERSHIP IS NOT PRICED IN. It grants
-- nothing, so a freeze implemented by reusing the granting rule's own
-- currency-FILTERED total sees no money at all. But the requirement's word
-- is "any money has arrived AGAINST A MEMBERSHIP", not "any money in its
-- currency" — and the alternative is a live exploit in the other direction:
-- take foreign money against an INR membership, then re-point `currency` at
-- it, and every unit of it scores. SIDED by this author and reported.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d6', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d5', '220000ff-0022-4000-8000-6000000000d5', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/currency: money in a currency the membership is not priced in is recorded and receipted');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-6000000000d5'::uuid),
  0,
  'arrived/currency: baseline — it grants nothing, which is MNY-002 and is correct');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set currency = 'USD' where id = '220000ff-0022-4000-8000-6000000000d5'$q$),
  'arrived/currency: re-denominating the membership at the currency that money came in is refused — otherwise "take foreign money, then re-price the membership into it" is a two-statement route to everything GL043 exists to stop, and a freeze keyed on the granting rule''s own currency-FILTERED total cannot see it coming');

select is(
  (select currency from public.memberships where id = '220000ff-0022-4000-8000-6000000000d5'::uuid),
  'INR',
  'arrived/currency: the currency is unchanged at INR');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000d5'$q$),
  'arrived/currency: and the price is frozen by that money too — money that has arrived against the membership is money that has arrived, however it is denominated');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d5'::uuid),
  100000::bigint,
  'arrived/currency: unchanged at 100000');

-- (vii) A payment against a DIFFERENT membership of the same member. A
-- freeze keyed on the member rather than the membership passes every refusal
-- above and locks a row nobody has paid a paisa against.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d7', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d6', '220000ff-0022-4000-8000-6000000000d6', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/sibling: money arrives against ONE of this member''s two memberships');

-- ROUND-ELEVEN RECONCILIATION (GL046): this pair proves WHEN the terms are
-- still free, not who may move them, so the correction is sent by a manager.
-- Same switch as 16c, 17c, 17g, 18b, 18c, 18e and 19g; the payment statements
-- around it stay at the desk, because a payment is recorded by the staff
-- member who took it (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 90000 where id = '220000ff-0022-4000-8000-6000000000d7'$$,
  'arrived/sibling: the member''s OTHER membership, which has taken nothing, is still fully editable — the freeze is per membership, and one keyed on the member locks rows no money was ever scored against');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d7'::uuid),
  90000::bigint,
  'arrived/sibling: and that correction landed');
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);


-- (viii) A payment INSERTED against one membership and MOVED to another
-- while it is still a working document, then paid. The money arrives at the
-- membership the row names WHEN IT IS PAID, not the one it named when it was
-- written — so the first must stay open and the second must freeze. A rule
-- that remembers "a payment once named this membership", or that reads
-- `old.membership_id`, gets both halves of this backwards.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001d8', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000d7', '220000ff-0022-4000-8000-6000000000d8', 50000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'arrived/moved-row: a payment is raised at created against the first membership');

select lives_ok(
  $$update public.payments set membership_id = '220000ff-0022-4000-8000-6000000000d9', member_id = '220000ff-0022-4000-8000-5000000000d8' where id = '220000ff-0022-4000-8000-7000000001d8'$$,
  'arrived/moved-row: and re-pointed at a second membership while still unpaid — legitimate, because a payment only becomes a record once it has been paid');

select lives_ok(
  $$update public.payments set status = 'paid' where id = '220000ff-0022-4000-8000-7000000001d8'$$,
  'arrived/moved-row: then the money arrives');

-- ROUND-ELEVEN RECONCILIATION (GL046): this pair proves WHEN the terms are
-- still free, not who may move them, so the correction is sent by a manager.
-- Same switch as 16c, 17c, 17g, 18b, 18c, 18e and 19g; the payment statements
-- around it stay at the desk, because a payment is recorded by the staff
-- member who took it (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 90000 where id = '220000ff-0022-4000-8000-6000000000d8'$$,
  'arrived/moved-row: the membership the payment was WRITTEN against stays fully editable — no money ever arrived there');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d8'::uuid),
  90000::bigint,
  'arrived/moved-row: and that correction landed');
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);


select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000d9'$q$),
  'arrived/moved-row: while the membership the payment was PAID against is frozen — the freeze follows the money, not the history of the row that carried it');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000d9'::uuid),
  100000::bigint,
  'arrived/moved-row: unchanged at 100000');

-- ---------------------------------------------------------------------------
-- 17e. MULTI-ROW AND MULTI-STATEMENT. Every defect in this phase survived
-- the single-row case and died on one of these. Section 16f did this for
-- GL044's column; GL043's terms have never been tested in any of these
-- shapes, and a rule written as a row trigger reading `old`/`new` behaves
-- differently in each.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001e0', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000e0', '220000ff-0022-4000-8000-6000000000e0', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi/setup: one of the two multi-row fixtures has taken money; the other has taken nothing');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id in ('220000ff-0022-4000-8000-6000000000e0', '220000ff-0022-4000-8000-6000000000e1')$q$),
  'multi/rows: one statement cutting the price of several memberships, only SOME of which have money, is refused');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000e0'::uuid),
  100000::bigint,
  'multi/rows: the membership with money is unchanged');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000e1'::uuid),
  100000::bigint,
  'multi/rows: and so is the one without — the whole statement was refused, not half-applied, so the desk is never left unable to tell which of its edits landed');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships m set price_paise = 60000 from public.plans p where p.id = m.plan_id and m.id = '220000ff-0022-4000-8000-6000000000e0'$q$),
  'multi/update-from: the same cut written as UPDATE ... FROM is refused');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000e0'::uuid),
  100000::bigint,
  'multi/update-from: unchanged at 100000');

select ok(
  pg_temp.h22r8_refused($q$merge into public.memberships m using (select '220000ff-0022-4000-8000-6000000000e0'::uuid as id) s on m.id = s.id when matched then update set price_paise = 60000$q$),
  'multi/merge: and written as MERGE — measured working from an ordinary front-desk session on 2026-09-09 against GL044''s column, which is why it is asked of GL043''s terms too');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000e0'::uuid),
  100000::bigint,
  'multi/merge: unchanged at 100000');

select ok(
  pg_temp.h22r8_refused($q$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-7000000001e1', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000e2', '220000ff-0022-4000-8000-6000000000e2', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning membership_id) update public.memberships set price_paise = 50000 where id in (select membership_id from p)$q$),
  'multi/cte: a data-modifying CTE that takes the FIRST payment and cuts the price in the SAME statement is refused — the money and the edit are simultaneous, which is the one ordering a rule reading the payments table cannot assume away');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-6000000000e2'::uuid),
  100000::bigint,
  'multi/cte: the price is unchanged at 100000');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-7000000001e1'::uuid),
  'multi/cte: and the payment inside that CTE was not written either — the whole statement was refused, so the gym has not silently banked money against a price it was refused permission to set');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-6000000000e0'$$,
  'multi/two-statements: a first, entirely legitimate statement in the transaction — freezing a membership is not a change of terms');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-6000000000e0'$q$),
  'multi/two-statements: the second statement, in the same transaction, is still refused — a rule that arms or disarms per transaction rather than per statement passes everything else in this file and fails here');

select ok(
  (select status = 'frozen'::membership_status and price_paise = 100000
     from public.memberships where id = '220000ff-0022-4000-8000-6000000000e0'::uuid),
  'multi/two-statements: the legitimate first statement stands and the refused second one did not land — a refusal that rolled the whole transaction back would be a different, and also wrong, answer');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-6000000000e0'$$,
  'multi/two-statements: and the fixture is restored, which is itself the unfreeze case');

-- ---------------------------------------------------------------------------
-- 17f. GL039 — a payment does not arrive already refunded. Both statuses
-- count toward the grant total, neither extends anything at the time, and
-- neither takes a receipt number (payments_paid_has_reference_chk names only
-- `paid`), so a payment written straight to `refunded` is grant credit on
-- the books that no receipt names, waiting for any later payment to cash it
-- in. Asserted as two refusals, two absences, the HARM behind them, the four
-- statuses that must still insert, and the trusted writer.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values ('220000ff-0022-4000-8000-7000000001f0', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f0', '220000ff-0022-4000-8000-6000000000f0', 300000, 'cash', 'refunded', '220000ff-0022-4000-8000-300000000001')$q$),
  'GL039: a payment inserted straight at `refunded` is refused — a payment is recorded and THEN refunded; it does not arrive that way');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-7000000001f0'::uuid),
  'GL039: and nothing landed — refused AND unwritten');

select ok(
  pg_temp.h22r8_refused($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values ('220000ff-0022-4000-8000-7000000001f1', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f0', '220000ff-0022-4000-8000-6000000000f0', 300000, 'cash', 'reversed', '220000ff-0022-4000-8000-300000000001')$q$),
  'GL039: and one inserted straight at `reversed` is refused too — the same presupposition, and the status a replayed provider event arrives as');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-7000000001f1'::uuid),
  'GL039: and nothing landed');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001f2', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f0', '220000ff-0022-4000-8000-6000000000f0', 1, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL039/harm: one paisa is then taken against the same 3,000-rupee membership');

select is(
  (select row(periods_granted, ends_on) from public.memberships where id = '220000ff-0022-4000-8000-6000000000f0'::uuid),
  (select row(0, (select today from gym_today where org_key = 'A'))),
  'GL039/harm: and it buys nothing — the harm behind the refusal is gone, not merely the write. Measured before the rule: a 3,000-rupee `refunded` insert plus one paisa granted the periods that money would have bought, with no receipt naming any of it');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001f3', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f1', '220000ff-0022-4000-8000-6000000000f1', 1, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'GL039/permitted: `created` is unaffected');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001f4', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f1', '220000ff-0022-4000-8000-6000000000f1', 1, 'cash', 'pending', '220000ff-0022-4000-8000-300000000001')$$,
  'GL039/permitted: `pending` is unaffected');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001f5', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f1', '220000ff-0022-4000-8000-6000000000f1', 1, 'cash', 'failed', '220000ff-0022-4000-8000-300000000001')$$,
  'GL039/permitted: `failed` is unaffected');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000001f6', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f1', '220000ff-0022-4000-8000-6000000000f1', 1, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL039/permitted: `paid` is unaffected — a rule matching on "a status that is not created" would close GL039 and every ordinary payment with it');

set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role service_role;

select ok(
  pg_temp.h22r8_refused($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values ('220000ff-0022-4000-8000-7000000001f7', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-5000000000f2', '220000ff-0022-4000-8000-6000000000f2', 300000, 'cash', 'refunded', '220000ff-0022-4000-8000-300000000001')$q$),
  'GL039/service_role: the trusted writer is refused too. SIDED BY THIS AUTHOR AND REPORTED — GL039 names no writer, but the harm is writer-independent (grant credit no receipt names), the transitions requirement three above it says in terms that it applies to every writer, and the webhook is the caller most likely to replay an old refund event for a payment it never recorded');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-7000000001f7'::uuid),
  'GL039/service_role: and nothing landed');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 17g. The permitted side of GL043, on a membership against which no money
-- has arrived at all: all four terms stay correctable, in one ordinary
-- column-listing update of the kind a console form writes. A fix that is too
-- broad passes every refusal in this file, and this project has shipped one
-- three times.
-- ---------------------------------------------------------------------------

-- ROUND-ELEVEN RECONCILIATION (GL046): all three columns this statement
-- corrects are now gym-admin work, so a manager sends it. The assertion still
-- guards exactly what it was written to guard — that the pre-money correction
-- is not swept away by an over-broad freeze — and section 20 adds the half it
-- could not know about, that the same statement from the desk is refused.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 80000, currency = 'USD', plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-6000000000f3'$$,
  'permitted/pre-money: price, currency and plan corrected together on a membership that has taken nothing — the whole point of "correcting a mistyped price or a wrong plan before any money has arrived stays free"');

select ok(
  (select price_paise = 80000 and currency = 'USD' and plan_id = '220000ff-0022-4000-8000-400000000005'::uuid
     from public.memberships where id = '220000ff-0022-4000-8000-6000000000f3'::uuid),
  'permitted/pre-money: and every one of the three landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-6000000000d3'$$,
  'permitted/frozen-membership: a part-paid, term-frozen membership can still be frozen — status is not a term the money was scored against, and 17d(iv) already proved a renewal against it still works');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-6000000000d3'::uuid),
  1,
  'permitted/frozen-membership: and nothing about that disturbed the count');


-- ---------------------------------------------------------------------------
-- 18. SEVENTH-SESSION EXTENSION, round NINE, written blind by a fourth
--     author against the CORRECTED requirement (ADR-092): a period's length
--     is DERIVED, never negotiated — it may change only as part of a plan
--     change and only to what that plan says, at any time, money or no
--     money — and a plan change carries the PRICE with it unless the
--     correction names a price of its own. The refusal is GL043, answered
--     by the coordinator to both authors rather than guessed: the length
--     is a term of the membership and belongs where the other terms are.
--
--     WHY THIS SECTION EXISTS, AND WHY ONE OF SECTION 17'S OWN ASSERTIONS
--     WAS WRONG. Round eight's requirement named the harm ("create a
--     membership naming duration_days = 3650, pay the ordinary price, get
--     ten years") and three lines later mandated the same outcome by
--     another route: "correcting the length before any money arrives SHALL
--     be allowed and SHALL land". Section 17 wrote to the contract it was
--     given and froze the length BY MONEY, like the price beside it. The
--     pre-money half that implies is what a critic then measured: sell a
--     30-day membership at 1,500 rupees, `update memberships set
--     duration_days = 3650`, take the ordinary 1,500 — 3,650 days, from one
--     `.update({duration_days})` in any front-desk browser session, and
--     UNDETECTABLE afterwards, because the row it leaves is fully
--     self-consistent: one receipt, one period granted, ends_on exactly one
--     recorded period. So 17c's duration-frozen assertion keeps its refusal
--     (still true, and still GL043) and loses its money-shaped reason, and
--     18a asserts the half it never reached.
--
--     WHAT THIS SECTION DOES NOT DO. It does not re-prove the two headline
--     shapes; ADR-092 records both. It goes at the SEAMS the corrected rule
--     grows, all of which are new this round because "changing the plan" is
--     now the only door the length has:
--
--       (a) THE BOUNDARY BETWEEN "CHANGED THE PLAN" AND "TYPED A LENGTH" —
--           18b. A plan change to a plan of the SAME length (a rule keyed
--           on "the length moved" sees nothing to authorise); a plan change
--           and then a plan change BACK inside one transaction (the only
--           bounded form of laundering left, and it must land on the plan's
--           real terms in both directions); setting plan_id to its OWN
--           value while writing a length (a same-value write is not a
--           change, so the length write has no plan change to ride on);
--           writing a length in one statement and the plan in the NEXT,
--           inside one transaction (a rule that arms per transaction rather
--           than per statement lets the refused length through on the later
--           legitimate one); a plan change that also names the CORRECT new
--           length, which must land; and a same-value plan write on a
--           membership that HAS taken money, which must neither be refused
--           nor re-derive its price.
--
--       (b) A PLAN CHANGE THAT NAMES THE WRONG LENGTH — 18b's last case, and
--           the ONE QUESTION THE CORRECTED REQUIREMENT STILL DOES NOT
--           ANSWER. "Only to what that plan says" refuses it; "the length
--           recorded SHALL be the plan's, not the one named" — the wording
--           of the CREATE scenario — ignores it and fills the plan's. This
--           author declines to guess: bounded assertion that holds under
--           either reading, observed value by `diag`, and the coordinator
--           told plainly. What both readings forbid, and what is measured
--           live today, is the named 3650 surviving.
--
--       (c) WHERE THE PRICE RE-DERIVATION COULD GO WRONG — 18c. It is a new
--           WRITE that no rule made before, and it lands on a column a gym
--           legitimately sets by hand. A membership sold at a negotiated
--           price; one carrying a discount_paise; a correction naming a
--           price of its own; a correction naming a price EQUAL to the old
--           one (indistinguishable from naming none under `is distinct
--           from`, so a desk that deliberately retypes the agreed price may
--           get the new plan's list price instead — reported, not guessed);
--           and a plan denominated in another currency, where taking the
--           price without the currency writes a dollar number into a rupee
--           membership.
--
--       (d) MULTI-ROW AND MULTI-STATEMENT — 18d. Every defect in this phase
--           survived the single-row case and died on one of these, and the
--           length has never been tested in any of them: MERGE and
--           `UPDATE ... FROM` are both named in ADR-092 as measured routes,
--           plus a data-modifying CTE that takes the first payment and
--           types the length in the SAME statement, and one statement
--           carrying a DIFFERENT value per row where one row is a
--           legitimate plan change and the other is a typed length.
--
--       (e) THE PERMITTED SIDE — 18e. A fix that is too broad passes every
--           refusal above, and this project has shipped one three times.
--           The rule must not touch discount_paise (deliberately not a
--           term), freeze, unfreeze, cancel, or a renewal; and after a
--           legitimate Monthly-to-Annual correction one Annual fee must buy
--           exactly ONE year, not the eight periods of 365 days — 2,920
--           days — ADR-092 measured when the length re-derived and the
--           price did not.
--
--       (f) DETECTABILITY — 18f. `ends_on - starts_on = duration_days *
--           periods_granted` is the invariant an audit would use, and the
--           exploit was invisible precisely because it PRESERVED it. It is
--           asserted here for what it is actually worth: it must still hold
--           across every fixture this section touches, so an auditor
--           running it gets no false positives from legitimate corrections.
--           Holding it proves nothing about the exploit, and the assertion
--           says so in its own text. The refusal is what closes that door.
--
--     Every refusal below asserts the code AND that the value is unchanged,
--     through `pg_temp.h22r8_refused` rather than `throws_ok(..., null, ...)`
--     for the reason section 17 gives.
--
--     MEASURED LIVE BEFORE THIS SECTION WAS WRITTEN, against the round-eight
--     implementation on Cloud, all from an ordinary front-desk session: a
--     pre-money `set duration_days = 3650` lands; the same through MERGE
--     lands; a plan change carries the length but NOT the price; a
--     same-length plan change leaves the old price standing; and a plan
--     change naming 3650 keeps the 3650 rather than the plan's 365 — the
--     caller's number beating the derivation outright.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency) values
  ('220000ff-0022-4000-8000-400000000901'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 R9 Plan Same Length (30d, 2000)', 30, 200000, 'INR'),
  ('220000ff-0022-4000-8000-400000000902'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 R9 Plan Foreign (30d, USD)',      30, 200000, 'USD');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000911'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Bare Length',    '+919220000911'),
  ('220000ff-0022-4000-8000-500000000912'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Self Plan',      '+919220000912'),
  ('220000ff-0022-4000-8000-500000000913'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Two Statements', '+919220000913'),
  ('220000ff-0022-4000-8000-500000000914'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Same Length',    '+919220000914'),
  ('220000ff-0022-4000-8000-500000000915'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Right Length',   '+919220000915'),
  ('220000ff-0022-4000-8000-500000000916'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Wrong Length',   '+919220000916'),
  ('220000ff-0022-4000-8000-500000000917'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Self Plan Paid', '+919220000917'),
  ('220000ff-0022-4000-8000-500000000918'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Negotiated',     '+919220000918'),
  ('220000ff-0022-4000-8000-500000000919'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Named Price',    '+919220000919'),
  ('220000ff-0022-4000-8000-50000000091a'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Named Same',     '+919220000920'),
  ('220000ff-0022-4000-8000-50000000091b'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Discounted',     '+919220000921'),
  ('220000ff-0022-4000-8000-50000000091c'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Foreign Plan',   '+919220000922'),
  ('220000ff-0022-4000-8000-50000000091d'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 MultiRow One',   '+919220000923'),
  ('220000ff-0022-4000-8000-50000000091e'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 MultiRow Two',   '+919220000924'),
  ('220000ff-0022-4000-8000-50000000091f'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Update From',    '+919220000925'),
  ('220000ff-0022-4000-8000-500000000920'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Merge',          '+919220000926'),
  ('220000ff-0022-4000-8000-500000000921'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 CTE',            '+919220000927'),
  ('220000ff-0022-4000-8000-500000000922'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 PerRow Legit',   '+919220000928'),
  ('220000ff-0022-4000-8000-500000000923'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 PerRow Typed',   '+919220000929'),
  ('220000ff-0022-4000-8000-500000000924'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 Permitted',      '+919220000930'),
  ('220000ff-0022-4000-8000-500000000925'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R9 MisSold',        '+919220000931');

-- Every fixture below is sold on H22 Plan A — 30 days, 100000 paise, INR —
-- except where the price or the discount column says otherwise, and none has
-- taken money until the assertion that gives it some.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency)
select
  ('220000ff-0022-4000-8000-6000000009' || f.suffix)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  ('220000ff-0022-4000-8000-5000000009' || f.suffix)::uuid,
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'active',
  (select today from gym_today where org_key = 'A'),
  (select today from gym_today where org_key = 'A'),
  f.price, f.discount, 'INR'
from (values
  ('11', 100000::bigint,     0::bigint),
  ('12', 100000::bigint,     0::bigint),
  ('13', 100000::bigint,     0::bigint),
  ('14', 100000::bigint,     0::bigint),
  ('15', 100000::bigint,     0::bigint),
  ('16', 100000::bigint,     0::bigint),
  ('17',  80000::bigint,     0::bigint),
  ('18',  80000::bigint,     0::bigint),
  ('19', 100000::bigint,     0::bigint),
  ('1a', 100000::bigint,     0::bigint),
  ('1b', 100000::bigint, 20000::bigint),
  ('1c', 100000::bigint,     0::bigint),
  ('1d', 100000::bigint,     0::bigint),
  ('1e', 100000::bigint,     0::bigint),
  ('1f', 100000::bigint,     0::bigint),
  ('20', 100000::bigint,     0::bigint),
  ('21', 100000::bigint,     0::bigint),
  ('22', 100000::bigint,     0::bigint),
  ('23', 100000::bigint,     0::bigint),
  ('24', 100000::bigint,     0::bigint),
  ('25', 100000::bigint,     0::bigint)
) as f(suffix, price, discount);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 18a. A TYPED LENGTH IS REFUSED WHATEVER THE MONEY. Section 17 proved the
-- money-shaped half on a membership that had been paid twice; this is the
-- half round eight's contract explicitly permitted and a critic then
-- measured at 3,650 days for one ordinary payment. Nothing has ever been
-- paid against this membership, which is exactly why it is the dangerous
-- case: the row it produces is indistinguishable from an honest membership
-- sold on a plan that was later re-lengthened.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set duration_days = 3650 where id = '220000ff-0022-4000-8000-600000000911'$q$),
  'GL043/length-derived: typing a length onto a membership against which NO money has arrived is refused — the length is derived from the plan and never negotiated, so the pre-money window that stays open for the price does not open for it');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000911'$q$),
  '30',
  'GL043/length-derived: and it is unchanged at 30 — refused AND unmoved. Measured live before this section: the write lands, and the ordinary payment after it buys ten years off one receipt no audit can tell from an honest one');

select lives_ok(
  $$update public.memberships set duration_days = 30 where id = '220000ff-0022-4000-8000-600000000911'$$,
  'GL043/length-derived: writing the SAME length back is allowed — a same-value write moves nothing, every exploit needs the value moved, and the console form that lists its columns writes this on every save. The decision ADR-089 already made for periods_granted, applied to the term beside it');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000911'$q$),
  '30',
  'GL043/length-derived: and it is still 30');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set duration_days = 1 where id = '220000ff-0022-4000-8000-600000000911'$q$),
  'GL043/length-derived: SHORTENING it is refused too — memberships_duration_days_chk permits 1, so a rule that only guards against lengthening leaves a desk able to cut a member''s term by hand, and "derived" is a rule about who writes the number, not which way it moves');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000911'$q$),
  '30',
  'GL043/length-derived: unchanged at 30');

-- ---------------------------------------------------------------------------
-- 18b. THE BOUNDARY BETWEEN "CHANGED THE PLAN" AND "TYPED A LENGTH". The
-- corrected rule has exactly one door, so every question worth asking is
-- about where that door starts and stops. A rule keyed on "the length
-- moved", one keyed on "the statement mentions plan_id", and one armed per
-- transaction rather than per statement each pass 18a and fail a different
-- case below.
-- ---------------------------------------------------------------------------

-- ROUND-ELEVEN RECONCILIATION (GL046), covering 18b (i) to (vi) and 18c
-- entire. Every permitted statement in those blocks is a PLAN CORRECTION, and
-- deciding what a member owes — which is what a plan correction re-derives —
-- is now gym-admin work. So a manager sends them. Nothing about the
-- derivation, the round trip, the escape hatch or the staged questions
-- changes; the refusals in (i), (ii) and (vi) are refused for a manager too,
-- because a typed length is refused whoever types it (ADR-092). The session
-- returns to the desk for (vii), which is a same-value write after money and
-- must stay open to the front office, and for 18d's refusals.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

-- (i) plan_id set to its OWN value, alongside a length. A same-value write
-- is not a change (18a proved that for the length itself), so there is no
-- plan change here for the length to ride on. A rule that arms on "plan_id
-- appears in the SET list" reads this as authorised and hands back the whole
-- exploit through a statement any client can write.

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000001', duration_days = 3650 where id = '220000ff-0022-4000-8000-600000000912'$q$),
  'GL043/self-plan: setting plan_id to its OWN value while writing a length is refused — the plan did not change, so nothing authorised the length, and a rule armed by plan_id merely APPEARING in the SET list gives the whole exploit back in one statement');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000912'$q$),
  '30',
  'GL043/self-plan: the length is unchanged at 30');

select is(
  (select plan_id from public.memberships where id = '220000ff-0022-4000-8000-600000000912'::uuid),
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'GL043/self-plan: and the plan is where it was');

-- (ii) The length in one statement, the plan in the NEXT, inside one
-- transaction. The first must be refused on its own merits and must not be
-- carried forward: a rule that arms or disarms per TRANSACTION lets the
-- refused number land on the later, entirely legitimate statement.

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set duration_days = 365 where id = '220000ff-0022-4000-8000-600000000913'$q$),
  'GL043/two-statements: the length typed alone is refused, even though the number happens to be the length of a plan this gym sells — a value that would be legitimate as a DERIVATION is not legitimate as a WRITE');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000913'$q$),
  '30',
  'GL043/two-statements: unchanged at 30');

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-600000000913'$$,
  'GL043/two-statements: the plan is then corrected in the very next statement of the same transaction, which is the legitimate instrument and must still work');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000913'$q$),
  '365',
  'GL043/two-statements: and the length is the NEW plan''s 365 — derived by the correction, not the 365 that was refused a statement earlier. A rule that arms per transaction cannot tell those two apart');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000913'::uuid),
  1200000::bigint,
  'GL043/two-statements: and the price came with it — price and length come from the same plan or from neither. Measured live before this section: the length re-derived and the price did not, which is one Annual fee buying eight periods of 365 days');

-- (iii) A plan change to a plan of the SAME length. Nothing about the
-- duration moves, so a rule keyed on "the length changed" never fires and
-- the PRICE re-derivation — the only observable here — is where it shows.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000901' where id = '220000ff-0022-4000-8000-600000000914'$$,
  'GL043/same-length: correcting a moneyless membership onto a DIFFERENT plan of the SAME length is allowed — an ordinary mis-sold-plan correction between two monthly plans, which is most of what a desk actually gets wrong');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000914'$q$),
  '30',
  'GL043/same-length: the length is still 30 — the new plan says 30, and "derived" means it equals what the plan says, not that it moved');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000914'::uuid),
  200000::bigint,
  'GL043/same-length: and the PRICE became the new plan''s 200000 — the only observable in a same-length correction, and the one a rule that fires on "the duration changed" never reaches');

-- (iv) And the plan change BACK, in the same transaction. This is the only
-- laundering route the corrected rule leaves, and it is bounded to exactly
-- what the plans table says: a round trip must land on the original plan's
-- real terms, never on a number the caller chose along the way.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000001' where id = '220000ff-0022-4000-8000-600000000914'$$,
  'GL043/plan-round-trip: changing the plan BACK to the original in the same transaction is allowed — no money has arrived, so both legs are ordinary corrections');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000914'$q$),
  '30',
  'GL043/plan-round-trip: the length is the original plan''s 30');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000914'::uuid),
  100000::bigint,
  'GL043/plan-round-trip: and the price went back to 100000 with it — a round trip lands on the plans table both ways. Derivation is what makes this door safe to leave open: whatever route a caller takes, the terms are a plan''s terms and never a caller''s');

-- (v) A plan change that also names the CORRECT new length. It is a change
-- of plan, and the number is what that plan says, so both halves of the
-- rule are satisfied and it must land. A rule written as "refuse any
-- statement that writes duration_days" refuses the console form that echoes
-- back what it just computed.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005', duration_days = 365 where id = '220000ff-0022-4000-8000-600000000915'$$,
  'GL043/right-length: a plan change that also names the CORRECT new length lands — it changes the plan, and 365 is what that plan says, which is exactly the permission the rule grants');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000915'$q$),
  '365',
  'GL043/right-length: the length is 365');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000915'::uuid),
  1200000::bigint,
  'GL043/right-length: and the price is the new plan''s, since the correction named no price of its own');

-- (vi) A plan change that names the WRONG length. THE REQUIREMENT DOES NOT
-- ANSWER THIS. "Only to what that plan says" refuses it; "the length
-- recorded SHALL be the plan's, not the one named" — the wording the CREATE
-- scenario uses for the same act — ignores it and fills the plan's. Both
-- readings are defensible; a third answer, in which 3650 survives, is what
-- is measured live today and is what both readings exist to forbid. Staged
-- in a DO block so that whichever way it goes it puts nothing on the TAP
-- stream, then one bounded assertion and a diag.

do $do$
begin
  begin
    update public.memberships
       set plan_id = '220000ff-0022-4000-8000-400000000005', duration_days = 3650
     where id = '220000ff-0022-4000-8000-600000000916';
  exception when others then null;
  end;
end
$do$;

select ok(
  pg_temp.h22r8_val($q$select duration_days::text || '/' || plan_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000916'$q$)
    in ('30/220000ff-0022-4000-8000-400000000001', '365/220000ff-0022-4000-8000-400000000005'),
  'GL043/wrong-length: OPEN QUESTION, staged not sided — a plan change naming a length that is NOT the new plan''s either fails whole (30, original plan) or lands with the plan''s own length substituted (365, new plan). The requirement supports both and settles neither; what neither permits, and what is measured live, is the caller''s 3650 standing');

select diag(
  'h22 R9 / GL043 plan change naming a wrong length: membership 600000000916 was on a 30-day plan and one statement set plan_id to the 365-day plan and duration_days to 3650. Observed (duration/plan): '
  || coalesce(pg_temp.h22r8_val($q$select duration_days::text || '/' || plan_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000916'$q$), 'null')
  || '. Reported rather than asserted because the requirement refuses it in its prose ("only to what that plan says") and ignores it in its CREATE scenario ("the length recorded SHALL be the plan''s, not the one named"), and those are different answers for the same act.');

-- Back to the desk for (vii): a same-value write is not a change of terms
-- under GL046 any more than under GL043, so the front office must still be
-- able to send it, and the payment below is taken by the desk that took it.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

-- (vii) A same-value plan write on a membership that HAS taken money. GL043
-- freezes the plan once money arrives, but a same-value write changes
-- nothing and must still be allowed — and, more to the point, it must not
-- re-derive the price. This membership was sold at a negotiated 80000 on a
-- plan whose list price is 100000; a re-derivation fired by plan_id merely
-- appearing in the SET list is a free re-price of a membership that has
-- already taken money, reachable by writing a column back onto itself.

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000009017', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000917', '220000ff-0022-4000-8000-600000000917', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/self-plan-paid: half of a negotiated 80000 price arrives, so the terms of this membership are now frozen and nothing has been granted');

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000001' where id = '220000ff-0022-4000-8000-600000000917'$$,
  'GL043/self-plan-paid: writing plan_id back onto its own value is still allowed after money has arrived — a same-value write is not a change of terms, and refusing it breaks every ordinary column-listing update the console sends');

select ok(
  (select price_paise = 80000 and duration_days = 30
     from public.memberships where id = '220000ff-0022-4000-8000-600000000917'::uuid),
  'GL043/self-plan-paid: and it re-derived NOTHING — the negotiated 80000 stands. A re-derivation armed by plan_id appearing in the SET list would re-price a membership that has already taken money, up to the list price, from a statement that changes no plan');

-- ---------------------------------------------------------------------------
-- 18c. WHERE THE PRICE RE-DERIVATION COULD GO WRONG. Carrying the price with
-- the plan is a WRITE no rule made before this round, and it lands on the
-- one term of the three that a gym legitimately sets by hand. Everything
-- below asks the same question from a different side: does re-deriving the
-- price ever clobber something a gym meant?
-- ---------------------------------------------------------------------------

-- ROUND-ELEVEN RECONCILIATION (GL046): 18c is five plan corrections and one
-- negotiated price, all of them gym-admin work now. A manager sends them.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

-- (i) It does, and by design: a negotiated price does not survive a plan
-- correction unless the correction names it again. Asserted rather than
-- assumed, because it is the cost of the rule and a reader should be able to
-- see the project chose it.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-600000000918'$$,
  'GL043/negotiated: a moneyless membership sold at a negotiated 80000 is corrected onto the Annual plan');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000918'::uuid),
  1200000::bigint,
  'GL043/negotiated: the price became the new plan''s 1200000 and the negotiated 80000 is GONE — the deliberate cost of "price and length come from the same plan or from neither". A desk that had agreed a discount must name it again in the correcting statement, and the next assertion proves it can');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000918'$q$),
  '365',
  'GL043/negotiated: and the length came with it');

-- (ii) The escape hatch the requirement provides, exercised.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005', price_paise = 80000 where id = '220000ff-0022-4000-8000-600000000919'$$,
  'GL043/named-price: a plan correction that names a price of its own is allowed');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000919'::uuid),
  80000::bigint,
  'GL043/named-price: and THAT price stands — the negotiated price is the half of this pair a desk legitimately types, so naming it beats the derivation');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000919'$q$),
  '365',
  'GL043/named-price: while the length is still the new plan''s 365 — naming a price buys an exception for the price and not for the term beside it');

-- (iii) A correction that names a price EQUAL to the old one. Under the
-- `is distinct from` idiom this project uses for same-value writes, this
-- statement is indistinguishable from one that names no price at all — so a
-- desk that deliberately retypes the agreed price to keep it may get the new
-- plan's list price instead. The requirement says "unless the correction
-- names a price of its own" and does not say whether naming the SAME number
-- counts as naming one. Bounded, and reported.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005', price_paise = 100000 where id = '220000ff-0022-4000-8000-60000000091a'$$,
  'GL043/named-same: a plan correction naming a price equal to the price already on the row is allowed either way — it is a legitimate statement under both readings');

select ok(
  (select price_paise in (100000, 1200000) from public.memberships where id = '220000ff-0022-4000-8000-60000000091a'::uuid),
  'GL043/named-same: OPEN QUESTION, staged not sided — the price is either the 100000 the statement named (a name is a name) or the new plan''s 1200000 (a same-value write is not distinguishable from no write). Any third value is wrong under both readings');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-60000000091a'$q$),
  '365',
  'GL043/named-same: and the length is the new plan''s 365 whichever way the price went — the length has no naming exception at all');

select diag(
  'h22 R9 / GL043 plan change naming a price equal to the old one: membership 60000000091a was priced 100000 and one statement set plan_id to the 1200000 Annual plan and price_paise to 100000. Observed price: '
  || coalesce((select price_paise::text from public.memberships where id = '220000ff-0022-4000-8000-60000000091a'::uuid), 'null')
  || '. Reported rather than asserted: if it reads 1200000, a desk that retyped the agreed price to protect it silently lost it, which is worth deciding on purpose rather than by whichever comparison the implementation happened to use.');

-- (iv) discount_paise across a plan correction. It is deliberately NOT a
-- term (nothing in the money path reads it), and no plan carries one, so
-- there is nothing for it to be re-derived FROM. It must survive untouched;
-- a re-derivation that rewrites the whole money block of the row would take
-- it with the price, and nothing would say so.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-60000000091b'$$,
  'GL043/discount: a moneyless membership carrying a discount_paise of 20000 is corrected onto the Annual plan');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-60000000091b'::uuid),
  20000::bigint,
  'GL043/discount: the discount is untouched — plans carry no discount, so there is nothing to derive it from, and a rule that rewrites the row''s money block wholesale would silently drop a coupon the gym granted');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-60000000091b'::uuid),
  1200000::bigint,
  'GL043/discount: while the price beside it did re-derive');

-- (v) A plan denominated in another currency. The requirement says price and
-- length come from the same plan; it says nothing about the currency, and
-- plans have one. Taking the price without it writes a dollar list price
-- into a rupee membership — a number that is wrong by an exchange rate and
-- looks completely ordinary. Bounded: the plan's terms taken together, or
-- nothing taken at all; never a USD number labelled INR.

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000902' where id = '220000ff-0022-4000-8000-60000000091c'$$,
  'GL043/foreign-plan: a moneyless INR membership is corrected onto a plan priced in USD');

select ok(
  (select (currency, price_paise) in (('USD', 200000::bigint), ('INR', 100000::bigint))
     from public.memberships where id = '220000ff-0022-4000-8000-60000000091c'::uuid),
  'GL043/foreign-plan: the plan''s terms were taken TOGETHER (USD 200000) or not taken at all (INR 100000) — never the third combination, INR 200000, which is a dollar list price wearing a rupee label and is what "the price comes from the plan" produces if the currency is left behind');

-- ---------------------------------------------------------------------------
-- Back to the desk for 18d, whose statements are all refusals of a TYPED
-- LENGTH — refused whoever sends them, and worth sending from the session
-- that would actually try.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

-- 18d. MULTI-ROW AND MULTI-STATEMENT, for the length. ADR-092 names MERGE
-- and `UPDATE ... FROM` as measured routes to the very exploit this round
-- closes, and every defect in this phase has survived the single-row case
-- and died on one of these. A rule written as a row trigger reading old/new
-- behaves differently in each.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set duration_days = 3650 where id in ('220000ff-0022-4000-8000-60000000091d', '220000ff-0022-4000-8000-60000000091e')$q$),
  'GL043/multi-rows: one statement typing a length onto several memberships is refused');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-60000000091d'$q$),
  '30',
  'GL043/multi-rows: the first is unchanged at 30');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-60000000091e'$q$),
  '30',
  'GL043/multi-rows: and so is the second — the whole statement was refused, not half-applied');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships m set duration_days = p.duration_days * 12 from public.plans p where p.id = m.plan_id and m.id = '220000ff-0022-4000-8000-60000000091f'$q$),
  'GL043/update-from: the same write as `UPDATE ... FROM`, taking its number from the plans table itself, is refused — reading a length out of a plan row is not the same act as being on that plan, and this is the shape ADR-092 measured');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-60000000091f'$q$),
  '30',
  'GL043/update-from: unchanged at 30');

select ok(
  pg_temp.h22r8_refused($q$merge into public.memberships m using (select '220000ff-0022-4000-8000-600000000920'::uuid as id) s on m.id = s.id when matched then update set duration_days = 3650$q$),
  'GL043/merge: and written as MERGE — measured landing from an ordinary front-desk session against the round-eight implementation, which is why it is asked rather than assumed');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000920'$q$),
  '30',
  'GL043/merge: unchanged at 30');

select ok(
  pg_temp.h22r8_refused($q$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000009021', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000921', '220000ff-0022-4000-8000-600000000921', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning membership_id) update public.memberships set duration_days = 3650 where id in (select membership_id from p)$q$),
  'GL043/cte: a data-modifying CTE that takes the FIRST payment and types the length in the SAME statement is refused — the money and the edit are simultaneous, which is the one ordering a rule that looks at the payments table cannot assume away');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000921'$q$),
  '30',
  'GL043/cte: the length is unchanged at 30');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-700000009021'::uuid),
  'GL043/cte: and the payment inside that CTE was not written either — the gym has not banked money against a term it was refused permission to set');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships m set plan_id = v.p, duration_days = v.d from (values ('220000ff-0022-4000-8000-600000000922'::uuid, '220000ff-0022-4000-8000-400000000005'::uuid, 365), ('220000ff-0022-4000-8000-600000000923'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 3650)) as v(id, p, d) where m.id = v.id$q$),
  'GL043/per-row: one statement carrying a DIFFERENT value per row — the first row an entirely legitimate plan change naming the right length, the second keeping its own plan and typing 3650 — is refused whole. A rule that evaluates the statement rather than each row sees one legitimate plan change and waves both through');

select ok(
  (select plan_id = '220000ff-0022-4000-8000-400000000005'::uuid
     from public.memberships where id = '220000ff-0022-4000-8000-600000000922'::uuid) is not true
  and pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000922'$q$) = '30',
  'GL043/per-row: the legitimate row did NOT land either — a statement is refused whole, so the desk is never left unable to tell which of its edits took');

select is(
  pg_temp.h22r8_val($q$select duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000923'$q$),
  '30',
  'GL043/per-row: and the typed row is unchanged at 30');

-- ---------------------------------------------------------------------------
-- 18e. THE PERMITTED SIDE. A fix that is too broad passes every refusal
-- above, and this project has shipped one three times. The last pair is the
-- one that matters most: the whole point of a plan correction is that
-- ordinary money afterwards buys an ordinary period.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000009024', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000924', '220000ff-0022-4000-8000-600000000924', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/permitted: a full payment is taken, so this membership is frozen in all its terms for everything that follows');

-- ROUND-ELEVEN RECONCILIATION (GL046): discount_paise is gym-admin work now,
-- so a manager writes it. What the assertion protects is unchanged — the
-- discount is NOT frozen by money — and section 20b re-proves the same fact
-- from the other side, that nothing in the money path reads the column.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select throws_ok(
  $$update public.memberships set discount_paise = 15000 where id = '220000ff-0022-4000-8000-600000000924'$$,
  'GL043', null,
  'NET-PRICE / GL043: an admin cannot rewrite the discount after money has arrived');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000924'::uuid),
  0::bigint,
  'NET-PRICE / GL043: the refused discount remains zero');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000000924'$$,
  'GL043/permitted: freezing a paid membership still works');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000000924'$$,
  'GL043/permitted: and unfreezing it does too');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member moved city' where id = '220000ff-0022-4000-8000-600000000924'$$,
  'GL043/permitted: and cancelling it, with its timestamp and its reason, in one ordinary multi-column update — none of that is a term the money was scored against');

-- ROUND-ELEVEN RECONCILIATION (GL046): the mis-sold-plan correction is the
-- manager's; the Annual fee after it is still taken by the desk, which is the
-- division of labour the requirement draws — "the front desk sells at the
-- plan's price and takes payment; re-pricing is the manager's".
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000005' where id = '220000ff-0022-4000-8000-600000000925'$$,
  'GL043/mis-sold: a Monthly sold by mistake is corrected onto the Annual plan before any money arrives — the ordinary desk correction the whole rule exists to keep possible');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000009025', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000925', '220000ff-0022-4000-8000-600000000925', 1200000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL043/mis-sold: and one Annual fee is taken against it');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000925'::uuid),
  (select today from gym_today where org_key = 'A') + 365,
  'GL043/mis-sold: it bought exactly ONE year. This reads today+2920 if the correction carried the length and left the Monthly price behind — floor(1200000/100000) = eight periods of 365 days for one year''s money, which is what was measured');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000925'::uuid),
  1,
  'GL043/mis-sold: one period, not eight — the count is the same defect read from the other end');

-- ---------------------------------------------------------------------------
-- 18f. DETECTABILITY. `ends_on - starts_on = duration_days * periods_granted`
-- is the invariant an audit would run, and it is worth being exact about
-- what it is for: the exploit this round closes PRESERVED it, so holding it
-- proves nothing about whether a length was hand-written. What it does prove
-- is the other direction — that the legitimate corrections above leave an
-- auditable estate, so an auditor running this query gets no false
-- positives and keeps trusting it. Scoped to this section's own fixtures,
-- per ADR-050.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.memberships
    where id::text like '220000ff-0022-4000-8000-6000000009%'
      and starts_on is not null and ends_on is not null
      and (ends_on - starts_on) is distinct from (duration_days * periods_granted)),
  0,
  'GL043/audit: every round-nine fixture — corrected plans, round trips, refused writes, renewals and cancellations alike — still satisfies ends_on - starts_on = duration_days * periods_granted. This does NOT detect the exploit: a hand-written length satisfies it too, which is exactly why it had to be refused at the write. It detects that legitimate corrections do not break the query an auditor relies on');

-- ---------------------------------------------------------------------------
-- 19. EIGHTH-SESSION EXTENSION, round TEN, written blind by a FIFTH author
--     against the requirement "The dates a membership runs for are written by
--     the rule that grants them" (GL045) and docs/decisions.md ADR-093.
--
--     Nine rounds governed what a period COSTS, how long it IS, and how many
--     have been GRANTED. All three compute a date anyone can simply type, and
--     ADR-093 measures it: `update public.memberships set ends_on = starts_on
--     + 3650` — allowed, ten years, one statement, no receipt. Confirmed live
--     by this author before writing a line, from an ordinary front-desk
--     session, in FOUR different statement shapes: plain UPDATE, MERGE,
--     UPDATE ... FROM, and INSERT ... ON CONFLICT DO UPDATE. All four land.
--     `starts_on = starts_on - 3650` lands too.
--
--     WHAT THIS SECTION DOES NOT DO. It does not re-prove the headline
--     refusal; the visible suite transcribes the scenario. It goes at the
--     seams the rule grows, and at one premise it declines to take on trust.
--
--     THE PREMISE. ADR-092 claimed a hand-written `ends_on` was detectable
--     afterwards because `ends_on - starts_on` would disagree with
--     `duration_days * periods_granted`; ADR-093 retracts that, measured at
--     17 of 46 dated memberships failing the invariant before any fraud. This
--     author re-measured it from the other end and 19h asserts the result:
--     an ORDINARY PART PAYMENT — the most common shape in an Indian gym, and
--     the one the console renders as product copy — breaks the invariant on
--     its own. A membership sold for 30 days with half the money in reads
--     span 30, duration 30, granted 0: 30 <> 0. The invariant is not a
--     detector and 18f's assertion that it holds across a section's fixtures
--     holds only because that section granted a whole period to every row it
--     touched. Nothing here rests on detection; the refusal at the write is
--     the whole mechanism.
--
--     THE SEAMS, and why each is the shape that breaks:
--
--       (a) THE GRANTING RULE'S OWN WRITES, AT EVERY SHAPE IT HAS — 19a. The
--           rule the refusal must not catch is the one that pays for the
--           whole feature, and a guard keyed on trigger depth catches it if
--           it is keyed one step wrong. Every one of these is measured GREEN
--           today and must still be green after: a first payment on a
--           DATELESS membership (sets both dates, activates); a RENEWAL on a
--           dated one (moves ends_on, leaves starts_on) and a SECOND renewal
--           after it — a rule keyed on "the dates were null" passes the first
--           and silently stops renewing, which is invisible to everyone but
--           the member; a PART payment (moves nothing); one payment crossing
--           FIVE multiples at once; TEN payments in one statement; a payment
--           written `created` and UPDATEd to `paid` (the grant fires on the
--           payment's UPDATE, not only its INSERT); the same flip through
--           `INSERT ... ON CONFLICT DO UPDATE` and through `MERGE`; a payment
--           inserted by `MERGE ... WHEN NOT MATCHED`; one inserted by a
--           data-modifying CTE; and a renewal on a LAPSED membership, where
--           the rule measures from the gym's today rather than from an
--           ends_on already in the past.
--
--       (b) THE SEAM BETWEEN "THE RULE MOVED IT" AND "A HAND MOVED IT IN THE
--           SAME TRANSACTION" — 19b. Measured live: a data-modifying CTE that
--           takes a real payment and adds 3650 days in ONE statement lands
--           both halves today, and so does the two-statement form. The
--           question a depth-keyed rule has to answer is whether the hand's
--           half is refused while the rule's half in the same statement is
--           not — and whether the refusal takes the payment down with it. Both
--           are asserted: the refusal, the dates, AND whether the legitimate
--           half landed.
--
--       (c) starts_on SPECIFICALLY, AND WHAT IT BUYS AT THE GATE — 19c. The
--           check-in gate judges liveness from these dates (ADR-084), so a
--           membership that starts in ten days is refused today, and pulling
--           `starts_on` back to today is a free ten days at the gate with
--           `ends_on` never touched — a shape no rule that watches only the
--           end date sees at all. Measured live end to end: refused GL013,
--           `update ... set starts_on = current_date` ALLOWED, admitted. The
--           gate consequence is asserted, not only the column.
--
--       (d) WHAT LEGITIMATELY MOVES A DATE AND MIGHT NOW BE REFUSED — 19d.
--           Measured, not assumed, because ADR-093 asserts it in one clause
--           ("membership pauses write their own table") and the whole round
--           exists because an unmeasured claim in ADR-092 was false. A pause
--           REQUEST, an APPROVAL by the gym's configured approver role, a
--           REJECTION, a freeze, an unfreeze, a cancellation and a REFUND
--           were each run against a real membership: NONE of them moves
--           `starts_on` or `ends_on`, or `periods_granted`. The clause is
--           true. Each is asserted as a permitted-side case so an over-broad
--           refusal fails here rather than in production, and the refund
--           result is reported by `diag` because it bears on the
--           requirement's own remedy — see the report.
--
--       (e) ROWS THE GRANTING RULE LEAVES ALONE, AND WHETHER GL045 MAKES THEM
--           UNREPAIRABLE — 19e. Four measured shapes where a payment lands,
--           is receipted, and moves no date: a half-dated `pending` row with
--           only `starts_on`; the mirror with only `ends_on` (which IS
--           extended and granted, while `starts_on` stays null and the row
--           stays `pending`, so the member stays refused at the gate); a
--           membership priced at zero; and one whose currency does not match
--           the money. In every one of them the ONLY remaining door to a
--           correct date is the hand-write GL045 refuses. That is asserted
--           and reported, not argued.
--
--       (f) THE GYM WITH NO TIMEZONE — 19f. Unreachable as literally written:
--           `organizations.timezone` is NOT NULL with a default, established
--           from the catalogue. The reachable neighbour is a gym carrying a
--           timezone Postgres does not recognise, which nothing validates.
--           Measured: a payment against its dateless membership aborts with a
--           raw, unmapped `22023` and the dates stay null — and after GL045
--           there is no way to enter them by hand either.
--
--       (g) THE PERMITTED SIDE — 19g. Same-value writes, an ordinary
--           column-listing console save, an unrelated column, creation with
--           dates (including a ten-year span, which the requirement's own
--           scenario permits), creation of a dateless `pending` row, and the
--           webhook: a `service_role` payment must still grant, while a
--           `service_role` hand-written date must not be exempt — ADR-092's
--           general form, that a trusted-caller carve-out is sound only where
--           the rule's subject is something a trusted caller lacks, and a
--           date arithmetic is not. That is the one place this author sided
--           rather than staged; it is called out in the report.
--
--     Every refusal below asserts `GL045` as the SQLSTATE — the codes in this
--     project ARE the SQLSTATEs, confirmed live (GL013, GL022, GL026, GL034
--     all came back as `sqlstate` from an exception handler) — AND reads the
--     dates back to prove they are unchanged. An explicit expected code is
--     used rather than `null::char(5)` for section 17's reason inverted: a
--     null expected code would pass on the `42501` a missing policy raises,
--     or on any unrelated constraint, and this battery must not be able to go
--     green against an unimplemented contract.
-- ---------------------------------------------------------------------------

set local role postgres;

-- A gym whose timezone is a string Postgres does not know. Nothing validates
-- this column: it is `text`, NOT NULL, defaulted, and carries no CHECK.
insert into public.organizations (id, name, gym_code, timezone) values
  ('220000ff-0022-4000-8000-100000000005'::uuid, 'Holdout PAYREC Gym X (bad tz)', 'H22AGX', 'Nowhere/Nothing');

insert into public.branches (id, tenant_id, name, is_default) values
  ('220000ff-0022-4000-8000-200000000005'::uuid, '220000ff-0022-4000-8000-100000000005'::uuid, 'H22 X Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('220000ff-0022-4000-8000-300000000051'::uuid, '220000ff-0022-4000-8000-100000000005'::uuid, '220000ff-0022-4000-8000-200000000005'::uuid, 'front_desk', 'H22 X Desk');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000000a05'::uuid, '220000ff-0022-4000-8000-100000000005'::uuid, 'H22 Plan X', 30, 100000);

-- Gym A has no organization_settings row, and without one no approver role is
-- configured, so a pause approval is refused with GL022 before it can be
-- observed at all — measured. One is created here so 19d exercises the real
-- approval path rather than a refusal that proves nothing about dates.
insert into public.organization_settings (tenant_id, pause_approver_role) values
  ('220000ff-0022-4000-8000-100000000001'::uuid, 'gym_manager');

-- A live QR session in gym A: the check-in gate's membership test lives
-- inside `if new.qr_session_id is not null`, so an assisted front-desk
-- check-in would skip the gate entirely and prove nothing (the same reason
-- section 6's own gate fixture gives).
insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000000a01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'h22-r10-gate-token-hash', now() + interval '1 day', '220000ff-0022-4000-8000-300000000001'::uuid);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-500000000a' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  '220000ff-0022-4000-8000-200000000001'::uuid,
  'H22 R10 ' || f.nm,
  '+91922000' || f.ph
from (values
  ('01','Dateless','1001'),      ('02','Renewal','1002'),        ('03','PartPay','1003'),
  ('04','FiveAtOnce','1004'),    ('05','TenInOne','1005'),       ('06','OnConflict','1006'),
  ('07','MergeInsert','1007'),   ('08','MergeFlip','1008'),      ('09','CteOnly','1009'),
  ('10','UpdateFlip','1010'),    ('11','Lapsed','1011'),         ('12','CteBoth','1012'),
  ('13','TwoStatements','1013'), ('14','UpdateFrom','1014'),     ('15','MergeTyped','1015'),
  ('16','ConflictTyped','1016'), ('17','PerRowSame','1017'),     ('18','PerRowTyped','1018'),
  ('19','FutureStart','1019'),   ('20','StartsOn','1020'),       ('21','PauseApprove','1021'),
  ('22','PauseReject','1022'),   ('23','FreezeCancel','1023'),   ('24','Refund','1024'),
  ('25','HalfStarts','1025'),    ('26','HalfEnds','1026'),       ('27','ZeroPrice','1027'),
  ('28','ForeignCurr','1028'),   ('29','SameValue','1029'),      ('2a','CreatedLong','1030'),
  ('2b','CreatedNull','1031'),   ('2c','ServiceRole','1032'),    ('2d','NoDelete','1033')
) as f(sfx, nm, ph);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000a30'::uuid, '220000ff-0022-4000-8000-100000000005'::uuid, '220000ff-0022-4000-8000-200000000005'::uuid, 'H22 R10 BadTz', '+919220001034');

-- The ordinary population: sold on H22 Plan A (30 days, 100000 paise, INR),
-- running from the gym's today for one period, nothing paid yet.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
select
  ('220000ff-0022-4000-8000-600000000a' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  ('220000ff-0022-4000-8000-500000000a' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'active',
  (select today from gym_today where org_key = 'A'),
  (select today from gym_today where org_key = 'A') + 30,
  100000, 'INR'
from (values
  ('02'),('03'),('04'),('05'),('06'),('07'),('08'),('09'),('10'),
  ('12'),('13'),('14'),('15'),('16'),('17'),('18'),('20'),('21'),
  ('22'),('23'),('24'),('29'),('2c'),('2d')
) as f(sfx);

-- The shapes that are not ordinary.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  -- a01: sold, not yet paid for — `pending` is the ONLY status a dateless row
  -- may hold (memberships_dated_unless_pending_chk), as h22's own header records.
  ('220000ff-0022-4000-8000-600000000a01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a01'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null, null, 100000, 'INR'),
  -- a11: lapsed three months ago, still `active` because nothing in this
  -- product ever writes `expired` (ADR-084).
  ('220000ff-0022-4000-8000-600000000a11'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a11'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A') - 90, (select today from gym_today where org_key = 'A') - 60, 100000, 'INR'),
  -- a19: sold today, starting in ten days. Refused at the gate today.
  ('220000ff-0022-4000-8000-600000000a19'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a19'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A') + 10, (select today from gym_today where org_key = 'A') + 40, 100000, 'INR'),
  -- a25 / a26: the two half-dated `pending` shapes.
  ('220000ff-0022-4000-8000-600000000a25'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a25'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', (select today from gym_today where org_key = 'A'), null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000a26'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a26'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null, (select today from gym_today where org_key = 'A') + 30, 100000, 'INR'),
  -- a27: a complimentary membership. memberships_price_paise_chk permits 0.
  ('220000ff-0022-4000-8000-600000000a27'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a27'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 0, 'INR'),
  -- a28: denominated in a currency the gym's cash never arrives in.
  ('220000ff-0022-4000-8000-600000000a28'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000a28'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 'USD'),
  -- a30: dateless, in the gym whose timezone Postgres cannot resolve.
  ('220000ff-0022-4000-8000-600000000a30'::uuid, '220000ff-0022-4000-8000-100000000005'::uuid, '220000ff-0022-4000-8000-500000000a30'::uuid, '220000ff-0022-4000-8000-400000000a05'::uuid, 'pending', null, null, 100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 19a. THE GRANTING RULE'S OWN WRITES, AT EVERY SHAPE IT HAS. Everything in
-- this block is green today and this section exists to keep it green. A
-- refusal keyed one step wrong on trigger depth, or keyed on "the dates were
-- null", or armed on the statement rather than on the write, takes one of
-- these with it — and a renewal that silently stops renewing is invisible to
-- the gym and visible only to the member, at the gate, weeks later.
--
-- ROUND-TWENTY RECONCILIATION (spec:). Ten expected values below moved and no
-- assertion did. openspec/changes/membership-creation/ added "the first period
-- is set, not added": where a membership has been granted NO periods, the
-- granting rule sets its span from the plan and starts it at the LATER of its
-- own starts_on and today, instead of extending a span that was typed and never
-- bought. Every row in this block's ordinary population is dated
-- today..today+30 with periods_granted at its default of zero — so what this
-- block called "a renewal" was in fact each row's FIRST grant, which is the
-- defect that change exists to close, asserted here as correct behaviour.
-- a02, a04, a05, a06, a07, a08, a09, a10 and a11 are re-expected; a01
-- (dateless) and a03 (a part payment that grants nothing) are untouched,
-- because the new rule does not reach either. Each changed line says so in
-- place, so a reader sees a contract that moved rather than a test that was
-- weakened.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a01', '220000ff-0022-4000-8000-600000000a01', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a first payment against a membership that has no dates at all is recorded');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || coalesce(ends_on::text, 'NULL') || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a01'::uuid),
  (select today::text || '/' || (today + 30)::text || '/active/1' from gym_today where org_key = 'A'),
  'GL045/grant-shapes: and the rule wrote BOTH dates and activated the row. This is the write the whole requirement is carved around, so a refusal that catches it refuses the only legitimate author the dates have');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a02', '220000ff-0022-4000-8000-600000000a02', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a renewal on a membership that already has dates is recorded');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a02'::uuid),
  '0/30/1',
  'GL045/grant-shapes: ROUND-TWENTY RECONCILIATION — this read 0/60/1, and it moved because the CONTRACT moved, not because the assertion was weakened. a02 is dated today..today+30 with periods_granted at its default of ZERO, so this payment is not a renewal at all: it is the row''s FIRST grant onto a typed span, and "the first period is set, not added" makes it SET the span from the plan rather than add a bought period on top of a typed one. The original point survives intact — the rule still writes BOTH dates here, starts_on to the later of its own value and today, which on this row is where it already was — so a guard that authorises "the write that fills the dates" and not "the write that sets them" passes a01 and still breaks this');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a03', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a02', '220000ff-0022-4000-8000-600000000a02', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: and a SECOND renewal on the same membership is recorded');

select is(
  (select (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a02'::uuid),
  '60/2',
  'GL045/grant-shapes: which moved it again — and THIS one is a genuine renewal, because the payment above granted the first period. ROUND-TWENTY RECONCILIATION: 90/2 became 60/2 for one reason only, that the row it starts from is thirty days shorter than it used to be. The renewal arithmetic is untouched and still ADDS, which the new requirement says in as many words. A rule that arms once per transaction, or once per row, renews exactly once and then stops — silently, and only the member finds out');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a04', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a03', '220000ff-0022-4000-8000-600000000a03', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a part payment — half the price — is recorded and receipted');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a03'::uuid),
  '30/0',
  'GL045/grant-shapes: and it moved NO date. The rule not firing is as much a part of the rule as the rule firing, and this is the row 19h measures the audit invariant against');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a05', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a04', '220000ff-0022-4000-8000-600000000a04', 500000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: one payment worth five whole periods is recorded');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a04'::uuid),
  '150/5',
  'GL045/grant-shapes: and the dates moved by five periods in one write. ROUND-TWENTY RECONCILIATION: 180 became 150, the typed month no longer surviving underneath the five that were bought. It now also pins something the new requirement''s own scenarios never stage, because every one of them grants exactly one period: "set its span from the plan" means duration_days * periods_granted — 150 here, not 30. A guard that permits "one period''s worth of movement" rather than "the rule wrote it" still refuses this and hands the gym back a member who paid for five months and got one');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    select ('220000ff-0022-4000-8000-70000000a1' || lpad(i::text, 2, '0'))::uuid,
           '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a05',
           '220000ff-0022-4000-8000-600000000a05', 100000, 'cash', 'paid', now(),
           '220000ff-0022-4000-8000-300000000001'
      from generate_series(1, 10) i$$,
  'GL045/grant-shapes: TEN payments in ONE statement are recorded — the multi-row shape every defect in this phase survived the single-row case and died on');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a05'::uuid),
  '300/10',
  'GL045/grant-shapes: and all ten granted. ROUND-TWENTY RECONCILIATION: 330 became 300, the typed month gone from under the ten that were paid for. Ten rows means ten fires of the rule against one membership inside one statement, and a guard that reads the row it is about to write rather than the write it is making sees ten "unexplained" date moves here');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a06', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a06', '220000ff-0022-4000-8000-600000000a06', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a payment is opened `created` — nothing is owed yet');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a06'::uuid),
  '30/0',
  'GL045/grant-shapes: and nothing moved, because nothing has been paid');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a06', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a06', '220000ff-0022-4000-8000-600000000a06', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')
    on conflict (id) do update set status = 'paid', paid_at = now()$$,
  'GL045/grant-shapes: and it is settled through INSERT ... ON CONFLICT DO UPDATE — the shape an idempotent recorder actually writes');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a06'::uuid),
  '30/1',
  'GL045/grant-shapes: which granted. ROUND-TWENTY RECONCILIATION: 60/1 became 30/1 — a first grant onto a typed span, set rather than added. The grant fires on the payment''s UPDATE, not only on its INSERT, and a date guard that only knows about the INSERT path refuses every online settlement');

select lives_ok(
  $$merge into public.payments p
    using (select '220000ff-0022-4000-8000-700000000a07'::uuid as id) s on p.id = s.id
    when not matched then insert (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000a07', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a07', '220000ff-0022-4000-8000-600000000a07', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a payment inserted by MERGE ... WHEN NOT MATCHED is recorded');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a07'::uuid),
  '30/1',
  'GL045/grant-shapes: and it granted. ROUND-TWENTY RECONCILIATION: 60/1 became 30/1, same first-grant reason as a06. MERGE is named in ADR-092 as a measured route into this table and it must stay a working one');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a08', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a08', '220000ff-0022-4000-8000-600000000a08', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: another payment is opened `created`');

select lives_ok(
  $$merge into public.payments p
    using (select '220000ff-0022-4000-8000-700000000a08'::uuid as id) s on p.id = s.id
    when matched then update set status = 'paid', paid_at = now()$$,
  'GL045/grant-shapes: and settled by MERGE ... WHEN MATCHED');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a08'::uuid),
  '30/1',
  'GL045/grant-shapes: which granted too — 30/1 rather than 60/1 since round twenty, same first-grant reason as a06');

select lives_ok(
  $$with p as (
      insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000a09', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a09', '220000ff-0022-4000-8000-600000000a09', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')
      returning id
    ) select count(*) from p$$,
  'GL045/grant-shapes: a payment taken inside a data-modifying CTE, with no hand-written date anywhere in the statement, is recorded');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a09'::uuid),
  '30/1',
  'GL045/grant-shapes: and it granted. ROUND-TWENTY RECONCILIATION: 60/1 became 30/1, same first-grant reason as a06. This is the honest half of 19b''s statement and it must survive whatever refuses the dishonest half');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a10', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a10', '220000ff-0022-4000-8000-600000000a10', 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a third payment is opened `created`');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000a10'$$,
  'GL045/grant-shapes: and settled by an ordinary UPDATE');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a10'::uuid),
  '30/1',
  'GL045/grant-shapes: which granted — 30/1 rather than 60/1 since round twenty, same first-grant reason as a06');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a11', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a11', '220000ff-0022-4000-8000-600000000a11', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a member whose membership lapsed three months ago renews');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a11'::uuid),
  '0/30/active/1',
  'GL045/grant-shapes: ROUND-TWENTY RECONCILIATION, and this is the value that moved furthest. It read -90/30/active/1: starts_on left ninety days in the past, ends_on measured from today, and the row therefore spanning 120 DAYS on ONE period granted. That is the very defect the new requirement closes, reached from the other side — an honest starts_on, an honest ends_on, and a first grant adding a bought period on top of a span that had already been lived. The contract now settles where the first grant starts a membership: at the LATER of its own starts_on and today, so a member who never paid starts today, and a pre-sold membership keeps the future date it was sold for. This returning member therefore starts today and spans exactly the thirty days they paid for. The block''s original point is unchanged and is still what the 30 asserts: the rule measures from the gym''s TODAY, not from an ends_on already sixty days in the past, or the renewal buys thirty days that finished last month');

-- ---------------------------------------------------------------------------
-- 19b. THE SEAM BETWEEN "THE RULE MOVED IT" AND "A HAND MOVED IT IN THE SAME
-- TRANSACTION". Measured live before this section was written: both shapes
-- below land in full today. A depth-keyed rule has to separate the two halves
-- of ONE statement, and the interesting question is not only whether the
-- hand's half is refused but what happens to the money in the other half.
-- Each case asserts the refusal, the dates, AND whether the payment landed.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$with p as (
      insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000a12', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a12', '220000ff-0022-4000-8000-600000000a12', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')
      returning membership_id
    )
    update public.memberships set ends_on = ends_on + 3650 where id in (select membership_id from p)$$,
  'GL045'::char(5), null,
  'GL045/one-statement: a data-modifying CTE that takes a real payment AND adds ten years to the same membership in ONE statement is refused. Measured live before this section: both halves land, leaving one receipt, one period granted, and a 3,680-day membership');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a12'::uuid),
  '30/0',
  'GL045/one-statement: and the dates are exactly where they started — not merely "not 3650", but unmoved, which is the only reading under which the statement was refused whole');

select is(
  (select count(*)::int from public.payments where id = '220000ff-0022-4000-8000-700000000a12'::uuid),
  0,
  'GL045/one-statement: and the payment did NOT land. The refusal takes the whole statement with it, which is right — a receipt that survives the refusal of the extension it paid for is money on the books against nothing');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a13', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a13', '220000ff-0022-4000-8000-600000000a13', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/two-statements: an entirely legitimate payment is recorded');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a13'::uuid),
  '30/1',
  'GL045/two-statements: and it granted a period, in the ordinary way. ROUND-TWENTY RECONCILIATION: this read 60/1. a13 is dated today..today+30 with periods_granted at its default of ZERO, so this is a FIRST grant, and the new requirement sets the span rather than adding to it');

select throws_ok(
  $$update public.memberships set ends_on = ends_on + 3650 where id = '220000ff-0022-4000-8000-600000000a13'$$,
  'GL045'::char(5), null,
  'GL045/two-statements: and the hand-written extension in the NEXT statement of the SAME transaction is still refused. A rule armed per transaction rather than per write reads "a payment already moved these dates" and lets this through');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a13'::uuid),
  '30/1',
  'GL045/two-statements: dates unchanged at the thirty days the money actually bought. ROUND-TWENTY RECONCILIATION: this read 60/1, and "sixty days" in this line''s own wording was the typed month plus the bought one — which is the defect the new requirement closes. What the line asserts is untouched: the hand-written extension in the next statement moved nothing');

select is(
  (select count(*)::int from public.payments where id = '220000ff-0022-4000-8000-700000000a13'::uuid),
  1,
  'GL045/two-statements: and the legitimate payment is still there — the refusal of the later statement must not reach back over the earlier one');

select throws_ok(
  $$update public.memberships m set ends_on = m.starts_on + 3650
      from public.members mm
     where mm.id = m.member_id and m.id = '220000ff-0022-4000-8000-600000000a14'$$,
  'GL045'::char(5), null,
  'GL045/shapes: UPDATE ... FROM is refused. Measured live: it lands');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a14'::uuid),
  '30',
  'GL045/shapes: and the span is unchanged at thirty days');

select throws_ok(
  $$merge into public.memberships m
    using (select '220000ff-0022-4000-8000-600000000a15'::uuid as id) s on m.id = s.id
    when matched then update set ends_on = m.starts_on + 3650$$,
  'GL045'::char(5), null,
  'GL045/shapes: MERGE is refused. Measured live: it lands');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a15'::uuid),
  '30',
  'GL045/shapes: and the span is unchanged at thirty days');

select throws_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000a16', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a16', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 'INR')
    on conflict (id) do update set ends_on = excluded.starts_on + 3650$$,
  'GL045'::char(5), null,
  'GL045/shapes: INSERT ... ON CONFLICT DO UPDATE is refused — the one shape where a date write is dressed as a creation, which the requirement''s own "creation sets them" clause invites a rule to wave through. Measured live: it lands');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a16'::uuid),
  '30',
  'GL045/shapes: and the span is unchanged at thirty days');

select throws_ok(
  $$update public.memberships
       set ends_on = case when id = '220000ff-0022-4000-8000-600000000a18'::uuid then ends_on + 3650 else ends_on end
     where id in ('220000ff-0022-4000-8000-600000000a17', '220000ff-0022-4000-8000-600000000a18')$$,
  'GL045'::char(5), null,
  'GL045/per-row: one statement carrying a different value per row — a same-value write on one membership and a ten-year push on the other — is refused. A rule that judges the STATEMENT rather than each row it writes sees one legal write and passes both');

select is(
  (select string_agg((ends_on - starts_on)::text, ',' order by id)
     from public.memberships where id in ('220000ff-0022-4000-8000-600000000a17'::uuid, '220000ff-0022-4000-8000-600000000a18'::uuid)),
  '30,30',
  'GL045/per-row: and BOTH rows are unchanged — the innocent row too, because a statement refused is a statement that wrote nothing');

-- ---------------------------------------------------------------------------
-- 19c. starts_on SPECIFICALLY, AND WHAT IT BUYS AT THE GATE. Every rule in
-- this family so far has been about how long a membership RUNS FOR. This is
-- about when it BEGINS, and the check-in gate reads both (ADR-084): a
-- membership starting in ten days admits nobody today. Pulling starts_on back
-- never touches ends_on, so a rule watching the end date sees nothing at all.
-- Measured live, end to end: refused, moved, admitted.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-a00000000a01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000a19', '220000ff-0022-4000-8000-600000000a19', now(), 'qr', '220000ff-0022-4000-8000-900000000a01')$$,
  'GL013'::char(5), null,
  'GL045/gate: a member whose membership starts in ten days is refused at the gate today. This is the baseline the next three assertions are worth anything against');

select throws_ok(
  $$update public.memberships set starts_on = (select today from gym_today where org_key = 'A') where id = '220000ff-0022-4000-8000-600000000a19'$$,
  'GL045'::char(5), null,
  'GL045/gate: pulling starts_on back to today is refused — a date write that leaves ends_on untouched entirely, and therefore leaves `ends_on - starts_on` LONGER than the money bought rather than shorter. Measured live: allowed');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a19'::uuid),
  '10/40',
  'GL045/gate: and both dates are unchanged');

select throws_ok(
  $$insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-a00000000a02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000a19', '220000ff-0022-4000-8000-600000000a19', now(), 'qr', '220000ff-0022-4000-8000-900000000a01')$$,
  'GL013'::char(5), null,
  'GL045/gate: and the member is STILL refused at the gate. This is the assertion that matters: the column being unchanged is a fact about a row, and this is the consequence the member actually experiences. Measured live before the rule: the same scan is ADMITTED, ten free days off one UPDATE nothing audits');

select throws_ok(
  $$update public.memberships set starts_on = starts_on + 5 where id = '220000ff-0022-4000-8000-600000000a20'$$,
  'GL045'::char(5), null,
  'GL045/starts_on: pushing starts_on FORWARD is refused too — it costs the member five days rather than buying them, and "written by the rule that grants them" is a statement about who writes the date, not about which direction it moves. A rule that only guards against lengthening leaves a desk able to shorten a member''s term by hand');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - starts_on)::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a20'::uuid),
  '0/30',
  'GL045/starts_on: and it is unchanged');

select throws_ok(
  $$update public.memberships set starts_on = starts_on - 3650 where id = '220000ff-0022-4000-8000-600000000a20'$$,
  'GL045'::char(5), null,
  'GL045/starts_on: and pulling it ten years backward on a LIVE membership is refused, with ends_on named nowhere in the statement');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - starts_on)::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a20'::uuid),
  '0/30',
  'GL045/starts_on: still unchanged');

-- ---------------------------------------------------------------------------
-- 19d. WHAT LEGITIMATELY MOVES A DATE AND MIGHT NOW BE REFUSED. ADR-093
-- disposes of this in one clause — "membership pauses write their own table" —
-- and the whole round exists because an unmeasured claim in the ADR above it
-- was false. So it was measured, on real rows, before anything here was
-- written: a pause request, an approval by the gym's configured approver, a
-- rejection, a freeze, an unfreeze, a cancellation and a refund. NONE of them
-- moves starts_on, ends_on or periods_granted. The clause is true. Each is
-- asserted so an over-broad refusal fails here instead of in a gym.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
    values ('220000ff-0022-4000-8000-b00000000a01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-600000000a21',
            (select today from gym_today where org_key = 'A') + 1, (select today from gym_today where org_key = 'A') + 8, 'travel', '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/pauses: a pause is REQUESTED for a live membership — note the request itself carries starts_on and ends_on, on its own table, which is exactly the near-miss a rule that greps for column names rather than tables would catch');

select is(
  (select (ends_on - starts_on)::text || '/' || status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a21'::uuid),
  '30/active',
  'GL045/pauses: and the membership''s own dates and status did not move');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.membership_pauses
       set approved_by_staff_id = '220000ff-0022-4000-8000-300000000002', approved_at = now()
     where id = '220000ff-0022-4000-8000-b00000000a01'$$,
  'GL045/pauses: the gym''s configured approver APPROVES it, and that still works');

select is(
  (select (ends_on - starts_on)::text || '/' || status::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a21'::uuid),
  '30/active/0',
  'GL045/pauses: and an APPROVED pause moves no date on the membership either — measured, not assumed. Nothing in the pause path needs GL045''s permission, which is the only reason the requirement can stay silent about it');

select lives_ok(
  $$insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
    values ('220000ff-0022-4000-8000-b00000000a02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-600000000a22',
            (select today from gym_today where org_key = 'A') + 1, (select today from gym_today where org_key = 'A') + 8, 'travel', '220000ff-0022-4000-8000-300000000002')$$,
  'GL045/pauses: a second pause is requested');

select lives_ok(
  $$update public.membership_pauses set rejected_at = now() where id = '220000ff-0022-4000-8000-b00000000a02'$$,
  'GL045/pauses: and REJECTED, which still works');

select is(
  (select (ends_on - starts_on)::text || '/' || status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a22'::uuid),
  '30/active',
  'GL045/pauses: and no date moved on rejection either');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000000a23'$$,
  'GL045/lifecycle: freezing a membership still works');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000000a23'$$,
  'GL045/lifecycle: and unfreezing it does too');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'member moved city' where id = '220000ff-0022-4000-8000-600000000a23'$$,
  'GL045/lifecycle: and cancelling it, with its timestamp and its reason, in one ordinary multi-column update');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a23'::uuid),
  '30',
  'GL045/lifecycle: none of which moved a date. A freeze in this product changes a status and nothing else — whatever a member is owed for the days they were frozen is not currently expressed as a date at all');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a24', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a24', '220000ff-0022-4000-8000-600000000a24', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/refund: a full payment is taken and grants a period');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a24'::uuid),
  '30/1',
  'GL045/refund: thirty days, one period. ROUND-TWENTY RECONCILIATION: this read 60/1 — a24 is dated today..today+30 with periods_granted at ZERO, so the payment is its FIRST grant and now sets the span instead of adding to it');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000a24'$$,
  'GL045/refund: and it is refunded, which still works');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a24'::uuid),
  '30/1',
  'GL045/refund: and the dates did not move back, nor did the count — 30/1 before the refund and 30/1 after it, where both readings were 60/1 before round twenty. What is asserted is the SAMENESS across the refund, and that is exactly as true at the new value. This is asserted because the requirement''s own remedy depends on it: "correcting a mistake means refunding and selling again", and a refund measurably corrects no date — see the diag below and the report');

select diag(
  'h22 R10 / GL045: the requirement offers one remedy for a wrong date — "correcting a mistake means refunding and selling again". Measured on membership 600000000a24: after the refund the span is '
  || coalesce((select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a24'::uuid), 'null')
  || ' days and periods_granted is '
  || coalesce((select periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a24'::uuid), 'null')
  || ' — both exactly what they were before it. A refund leaves the wrong dates live on the row and live at the gate; the correction only works if the old membership is also CANCELLED and a new one created, which the requirement does not say. Reported, not asserted either way.');

-- ---------------------------------------------------------------------------
-- 19e. ROWS THE GRANTING RULE LEAVES ALONE, AND WHETHER GL045 MAKES THEM
-- PERMANENTLY UNREPAIRABLE. Four shapes, all measured live: money arrives, a
-- receipt is issued, and no date moves. Before GL045 each had exactly one
-- repair — a front desk typing the date. After GL045 that door is shut and
-- the granting rule does not open another. Every one of these is a row where
-- the gym has taken money and the member cannot be made whole by any
-- statement the product permits. The refusals are asserted because the
-- requirement plainly requires them; what they COST is reported.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a25', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a25', '220000ff-0022-4000-8000-600000000a25', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/left-alone: a full payment against a half-dated `pending` membership — starts_on set, ends_on null — is recorded and receipted');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || coalesce(ends_on::text, 'NULL') || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a25'::uuid),
  (select today::text || '/NULL/pending/0' from gym_today where org_key = 'A'),
  'GL045/left-alone: and NOTHING happened — no end date, no period, still pending. The extension''s guard is `ends_on is not null`, which this row fails, and the dating rule''s guard is "both dates null", which it also fails');

select throws_ok(
  $$update public.memberships set ends_on = (select today from gym_today where org_key = 'A') + 30 where id = '220000ff-0022-4000-8000-600000000a25'$$,
  'GL045'::char(5), null,
  'GL045/left-alone: and entering the missing end date by hand is refused — correctly by the requirement, and it was the only repair this row had');

select is(
  (select coalesce(ends_on::text, 'NULL') from public.memberships where id = '220000ff-0022-4000-8000-600000000a25'::uuid),
  'NULL',
  'GL045/left-alone: so the row keeps a null ends_on, a receipted payment against it, and no path in the product to either');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a26', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a26', '220000ff-0022-4000-8000-600000000a26', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/left-alone: a full payment against the MIRROR half-dated row — ends_on set, starts_on null — is recorded');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a26'::uuid),
  'NULL/60/pending/1',
  'GL045/left-alone: which IS extended and IS granted, while starts_on stays null and the row stays `pending` — because activating a row with a null starts_on violates memberships_dated_unless_pending_chk. Money taken, receipt issued, period recorded, member refused at the gate');

select throws_ok(
  $$update public.memberships set starts_on = (select today from gym_today where org_key = 'A') where id = '220000ff-0022-4000-8000-600000000a26'$$,
  'GL045'::char(5), null,
  'GL045/left-alone: and entering the missing START date by hand — the one write that would let this paid-for member through the gate — is refused');

select is(
  (select coalesce(starts_on::text, 'NULL') from public.memberships where id = '220000ff-0022-4000-8000-600000000a26'::uuid),
  'NULL',
  'GL045/left-alone: so it stays null, the row stays pending, and the member stays out');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a27', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a27', '220000ff-0022-4000-8000-600000000a27', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/left-alone: money arrives against a COMPLIMENTARY membership, priced at zero — which memberships_price_paise_chk permits and a gym writes for a staff member or a promotion');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a27'::uuid),
  '30/0',
  'GL045/left-alone: and nothing moved — there is no price to divide by, so no whole multiple is ever crossed. A comp membership can therefore never be extended by the granting rule at all, at any amount');

select throws_ok(
  $$update public.memberships set ends_on = ends_on + 30 where id = '220000ff-0022-4000-8000-600000000a27'$$,
  'GL045'::char(5), null,
  'GL045/left-alone: and extending it by hand — the only way a comp membership was ever extended — is refused, so a gym that renews a free membership now has no statement that does it');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a27'::uuid),
  '30',
  'GL045/left-alone: unchanged at thirty days');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id, currency)
    values ('220000ff-0022-4000-8000-700000000a28', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a28', '220000ff-0022-4000-8000-600000000a28', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001', 'INR')$$,
  'GL045/left-alone: rupees arrive against a membership denominated in dollars — recorded, and receipted');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a28'::uuid),
  '30/0',
  'GL045/left-alone: and nothing moved, because the money is not in the membership''s denomination');

select throws_ok(
  $$update public.memberships set ends_on = ends_on + 30 where id = '220000ff-0022-4000-8000-600000000a28'$$,
  'GL045'::char(5), null,
  'GL045/left-alone: and the hand-repair is refused here too');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a28'::uuid),
  '30',
  'GL045/left-alone: unchanged');

select diag(
  'h22 R10 / GL045 rows the rule leaves alone: four shapes were measured where a payment lands and is receipted and no date moves — half-dated pending (starts only): 600000000a25; half-dated pending (ends only, extended and granted but never activated): 600000000a26; zero price: 600000000a27; currency mismatch: 600000000a28. Before this round each had exactly one repair, a front desk typing the date. GL045 closes it and the granting rule opens nothing in its place, so each is now a row carrying money the product cannot make right. The requirement names the FIRST of the four and accepts its cost; it does not mention the other three, and the a26 mirror is the worst of them because that row has been GRANTED its period and still cannot admit its member. Reported rather than argued: the refusals above are what the requirement says, and whether it should carve any of these out is not a blind test author''s call.');

-- ---------------------------------------------------------------------------
-- 19f. THE GYM WITH NO TIMEZONE. Not reachable as stated:
-- `organizations.timezone` is `text NOT NULL DEFAULT 'Asia/Kolkata'`, read
-- from the catalogue, so no gym can lack one. Its reachable neighbour is a
-- gym carrying a timezone string Postgres does not recognise — the column has
-- no CHECK and nothing validates it — which is what the dating rule's
-- `now() at time zone o.timezone` actually meets.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'organizations'
      and column_name = 'timezone' and is_nullable = 'NO' and column_default is not null),
  1,
  'GL045/no-timezone: a gym with NO timezone is unreachable — the column is NOT NULL with a default. The requirement''s "gym has no timezone" case is tested below in the only shape it can actually take');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000005',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000051')::text,
  true
);

select throws_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a30', '220000ff-0022-4000-8000-100000000005', '220000ff-0022-4000-8000-500000000a30', '220000ff-0022-4000-8000-600000000a30', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000051')$$,
  '22023'::char(5), null,
  'GL045/no-timezone: a payment against a dateless membership in a gym whose timezone Postgres cannot resolve aborts with a raw, unmapped 22023 — loudly, which by this project''s own tie-breaker is the right direction, but with no GL code and naming a column the desk cannot see');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || coalesce(ends_on::text, 'NULL') from public.memberships where id = '220000ff-0022-4000-8000-600000000a30'::uuid),
  'NULL/NULL',
  'GL045/no-timezone: and the membership keeps both nulls');

select throws_ok(
  $$update public.memberships
       set starts_on = current_date, ends_on = current_date + 30
     where id = '220000ff-0022-4000-8000-600000000a30'$$,
  'GL045'::char(5), null,
  'GL045/no-timezone: and the desk cannot enter them by hand either, so a gym with a mistyped timezone can sell memberships it can never date until somebody fixes the timezone — which is the correct place to fix it, and is worth the requirement saying so');

select is(
  (select coalesce(starts_on::text, 'NULL') || '/' || coalesce(ends_on::text, 'NULL') from public.memberships where id = '220000ff-0022-4000-8000-600000000a30'::uuid),
  'NULL/NULL',
  'GL045/no-timezone: both still null');

-- ---------------------------------------------------------------------------
-- 19g. THE PERMITTED SIDE. A refusal broad enough to pass every case above
-- and still be wrong is the defect this project has shipped three times. The
-- requirement now says "refuse every other CHANGE" and carries an explicit
-- same-value scenario, matching its sibling one heading up; it said "write"
-- when this section was begun, which is the one place GL045 disagreed with
-- the requirement beside it. Asserted here in the settled form.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships set starts_on = starts_on, ends_on = ends_on where id = '220000ff-0022-4000-8000-600000000a29'$$,
  'GL045/permitted: writing the SAME dates back is allowed. A same-value write moves nothing, every exploit needs the value moved, and the console form that lists its columns writes this on every save — the decision ADR-089 made for periods_granted and section 18a made for duration_days, applied to the two columns beside them');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a29'::uuid),
  '30',
  'GL045/permitted: and the row is intact');

-- ROUND-ELEVEN RECONCILIATION (GL046): this assertion's own text already
-- says "what a REST client sends when a MANAGER changes a discount", and
-- discount_paise is now one of the four columns only a gym admin may change.
-- So the session is a manager. The shape being protected — the ordinary
-- column-listing save that carries every derived column — is unchanged, and
-- section 20g asserts the front desk's version of it, where the four
-- restricted columns are written back at their own values.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships
       set starts_on = starts_on, ends_on = ends_on, periods_granted = periods_granted,
           duration_days = duration_days, discount_paise = 12000
     where id = '220000ff-0022-4000-8000-600000000a29'$$,
  'GL045/permitted: and the ordinary column-listing save that carries all four derived columns alongside the one field actually being edited is allowed. This is what a REST client sends when a manager changes a discount, and refusing it makes the membership screen unusable while stopping nothing');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000a29'::uuid),
  12000::bigint,
  'GL045/permitted: and the edit landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships set cancel_reason = 'noted at the desk' where id = '220000ff-0022-4000-8000-600000000a29'$$,
  'GL045/permitted: an unrelated column on its own is untouched by the rule');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000a2a', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a2a', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 3650, 100000, 'INR')$$,
  'GL045/permitted: a membership is CREATED carrying a ten-year span, and the requirement''s own scenario permits it — "creation sets them", with no bound on what they may be set to. Carried as OPEN-029 rather than closed, so this assertion is the permitted side of a door the requirement knows is open');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a2a'::uuid),
  '3650/0',
  'GL045/permitted: and it landed at 3,650 days on zero periods granted and no money at all — the fourth door of the shape the count rule closed at creation, left open on purpose as OPEN-029. This assertion exists so that whoever closes it later sees this row change and knows it was a choice, not a regression');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000a2b', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a2b', '220000ff-0022-4000-8000-400000000001', 'pending', null, null, 100000, 'INR')$$,
  'GL045/permitted: and a membership is created with NO dates, which after ADR-083 is the ordinary "sold but not yet paid for" shape and must stay creatable');

select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, provider, provider_order_id, provider_payment_id)
    values ('220000ff-0022-4000-8000-700000000a2c', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a2c', '220000ff-0022-4000-8000-600000000a2c', 100000, 'razorpay', 'paid', now(), 'razorpay', 'order_h22r10a2c', 'pay_h22r10a2c')$$,
  'GL045/service_role: the Razorpay webhook records an online payment as service_role');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a2c'::uuid),
  '30/1',
  'GL045/service_role: and it granted a period. ROUND-TWENTY RECONCILIATION: this read 60/1 — a2c is dated today..today+30 with periods_granted at ZERO, so the webhook''s payment is its FIRST grant and sets the span. The trusted caller must keep the rule''s own write, or every online renewal stops');

select throws_ok(
  $$update public.memberships set ends_on = starts_on + 3650 where id = '220000ff-0022-4000-8000-600000000a2c'$$,
  'GL045'::char(5), null,
  'GL045/service_role: but a hand-written date from service_role is refused too. SIDED, not staged, on ADR-092''s own general form: a trusted-caller carve-out is sound exactly where the rule''s subject is something a trusted caller legitimately lacks, and where the subject is an invariant about the data — a sequence, a total, a date arithmetic — the trusted caller needs it MORE, because no policy stands behind it. Called out in the report as the one place this author chose a side');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a2c'::uuid),
  '30',
  'GL045/service_role: and the dates are unchanged at what the money bought — 30 rather than 60 since round twenty, because what the money bought is now all the row carries');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$delete from public.memberships where id = '220000ff-0022-4000-8000-600000000a2d'$$,
  '42501'::char(5), null,
  'GL045/no-delete: delete-and-recreate is not a way round the rule, because `authenticated` holds no DELETE on memberships at all — evidence already held, asserted here because a refusal on UPDATE with a DELETE beside it would be no refusal');

-- ---------------------------------------------------------------------------
-- 19h. THE PREMISE, RE-MEASURED. ADR-092 ranked the `duration_days` door
-- above the `ends_on` door because a hand-written ends_on supposedly left
-- `ends_on - starts_on` disagreeing with `duration_days * periods_granted`;
-- ADR-093 retracts that at 17 of 46 dated memberships failing the invariant
-- before any fraud. This author re-measured it from the other end rather than
-- taking either number on trust, and the answer is worse than a false
-- positive rate: the single most ordinary transaction in an Indian gym breaks
-- the invariant by itself.
-- ---------------------------------------------------------------------------

select ok(
  (select (ends_on - starts_on) is distinct from (duration_days * periods_granted)
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a03'::uuid),
  'GL045/audit: membership 600000000a03 is entirely honest — sold for one 30-day period, half the price paid in, receipted, nothing granted — and it FAILS `ends_on - starts_on = duration_days * periods_granted` (30 vs 0). A part payment is the shape the console renders as product copy, so the invariant flags a normal gym''s ordinary business. It is not a detector, it was never a reason to rank one door below another, and nothing in this section rests on it');

select isnt(
  (select count(*)::int from public.memberships
    where id::text like '220000ff-0022-4000-8000-600000000a%'
      and starts_on is not null and ends_on is not null
      and (ends_on - starts_on) is distinct from (duration_days * periods_granted)),
  0,
  'GL045/audit: and it is not one row — several of this section''s wholly legitimate fixtures fail it, all of them created or paid exactly as the product intends. 18f asserts the invariant HOLDS across its own fixtures, and that is true there only because every row it touched was granted a whole period');

select diag(
  'h22 R10 / GL045 audit invariant: `ends_on - starts_on <> duration_days * periods_granted` is true for '
  || coalesce((select count(*)::text from public.memberships
                where id::text like '220000ff-0022-4000-8000-600000000a%'
                  and starts_on is not null and ends_on is not null
                  and (ends_on - starts_on) is distinct from (duration_days * periods_granted)), 'null')
  || ' of '
  || coalesce((select count(*)::text from public.memberships
                where id::text like '220000ff-0022-4000-8000-600000000a%'
                  and starts_on is not null and ends_on is not null), 'null')
  || ' dated round-ten fixtures, with no fraud anywhere in this section. Part payments, complimentary memberships, currency mismatches, lapsed renewals and creations-with-dates all break it honestly.');


-- ---------------------------------------------------------------------------
-- 20. NINTH-SESSION EXTENSION, round ELEVEN, written blind by a SIXTH author
--     against the requirement "Deciding what a member owes is gym-admin work"
--     (GL046) and docs/decisions.md ADR-094. `ends_on = duration_days *
--     floor(money / price_paise)`. Round nine made the length underivable by
--     hand because it multiplies that product; the PRICE is the other factor
--     and stayed freely typed, and two ordinary front-desk statements bought
--     300 days for one Rs.1,500 receipt with both audit invariants intact.
--     The control ADR-094 chose is WHO, not what: the four columns that say
--     what a member owes — price_paise, currency, plan_id, discount_paise —
--     become gym-admin work, on the precedent `refunds_tenant_write` already
--     set one table over.
--
-- Not read, then or since: supabase/tests/22_payment_record.sql, whose own
-- battery for GL046 was written in parallel by a different author; any
-- migration dated later than the round-ten one; prosrc or pg_get_functiondef
-- for anything implementing GL046. Per ADR-091, docs/registry.md was not read
-- for anything about this round's code. Read: the requirement, ADR-094
-- including the three designs it REJECTS, ADR-082's general form for
-- trusted-caller carve-outs, docs/security.md on what an impersonating token
-- carries, supabase/seed.sql's membership upsert, the live Cloud catalogue,
-- and this file.
--
-- The headline refusal is the visible suite's to prove. This section goes at
-- the seams:
--
--   * THE REJECTED DESIGNS, each of which implies something that must still
--     WORK. "Do not derive the price from the plan" means selling below list
--     must stay possible. "Do not bound the price" means a 90%-discounted
--     membership must behave and a comp to one paisa must land. "Do not bound
--     the discount" means discount_paise stays writable by an admin — and
--     stays UNREAD by the money path (OPEN-028), which is asserted from the
--     money's side, not the column's.
--   * is_gym_admin() ITSELF, which reads one JWT claim and returns FALSE for
--     a session that has none. This author sided on it and the coordinator
--     then settled it the same way, to both suites at once, so it is asserted
--     in BOTH directions here rather than staged: on ADR-082's general form, a
--     carve-out
--     for trusted callers is sound exactly where the rule's subject is
--     something a trusted caller legitimately lacks, and "which staff role
--     you are" is precisely that — unlike a receipt number or a refund
--     ceiling, which are invariants about the data and which a trusted caller
--     needs MORE. So `postgres` and `service_role` may re-price and a trainer
--     and a bare `super_admin` may not. THE SEED IS THE FORCING CASE and it
--     was read rather than guessed: seed.sql's membership block is an
--     `insert ... on conflict (id) do update set plan_id, price_paise,
--     discount_paise, currency`, run as the CLI's claimless `postgres`
--     session. A rule with no carve-out turns every seed RE-RUN red, which
--     has already happened once this phase. That exact statement shape is
--     asserted below, not a paraphrase of it.
--   * THE INTERACTION WITH THE TWO FREEZES. A gym admin after money is still
--     refused (GL043) — being an admin unfreezes nothing — and a gym admin
--     typing a date is still refused (GL045). Which rule answers a FRONT DESK
--     on a paid membership is reported by diag rather than asserted, because
--     the requirement settles the outcome and not the ordering. The leak that
--     ordering could carry is asserted from the only side where it would be a
--     leak: a MEMBER session, for whom the two cases must be indistinguishable.
--   * THE CREATE PATH, which is where this section's finding was. Both blind
--     authors measured the same door independently — create a membership at
--     one tenth of the plan's price, take the ordinary fee, 300 days in TWO
--     statements with no UPDATE anywhere — and the coordinator closed it to
--     both suites before either handed back. 20e asserts the closure, the
--     three shapes it covers, the two callers it exempts, and the part of
--     OPEN-029 it deliberately leaves open.
--   * MULTI-ROW AND MULTI-STATEMENT, the shapes every defect in this phase has
--     survived the single-row case and died on.
--   * THE PERMITTED SIDE, AS HARD AS THE REFUSED. A fix that is too broad
--     passes every refusal above and this project has shipped one three times.
--     The front desk must still create, sell, take money, renew, pause, check
--     in, edit notes, freeze — and send the ordinary column-listing save that
--     writes all four restricted columns back at their own values.
--
-- RECONCILED, and it is the reason the coordinator flagged this file: the
-- spec scenario "Correcting a mistake before any money arrives" said "a
-- FRONT-DESK session" for four rounds, and nine permitted-side assertions in
-- sections 16, 17, 18 and 19 were written to it. Each is now sent by a
-- manager; every one of them tests what a correction DOES, not who may ask
-- for it, so the claim switch preserves the assertion exactly and the plan
-- count is untouched. They are marked "ROUND-ELEVEN RECONCILIATION" in place.
-- Section 15d-zero is NOT among them: it runs as claimless `postgres`, which
-- the carve-out sided on above keeps green — if an implementation refuses
-- claimless sessions, 15d-zero goes red beside 20c and the pair says why.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('220000ff-0022-4000-8000-300000000004'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'gym_owner', 'H22 A Owner');

-- A second monthly plan in gym A, priced at twice the first. Used as the plan
-- a correction would point at (a plan change re-derives the price, so plan_id
-- is a route to the price and belongs in the same list) and as the LIST price
-- a front desk may not move.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000000b01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, 'H22 R11 Plan Premium', 30, 200000);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-500000000b' || lpad(n::text, 2, '0'))::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  '220000ff-0022-4000-8000-200000000001'::uuid,
  'H22 R11 Member ' || n,
  '+919220011' || lpad(n::text, 3, '0')
from generate_series(1, 39) as n;

-- The ordinary population: gym A's 30-day, 100000-paise plan, running from the
-- gym's today, nothing paid, nothing granted.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
select
  ('220000ff-0022-4000-8000-600000000b' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  ('220000ff-0022-4000-8000-500000000b' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-400000000001'::uuid,
  'active',
  (select today from gym_today where org_key = 'A'),
  (select today from gym_today where org_key = 'A'),
  100000, 'INR'
from (values
  ('01'),('02'),('03'),('04'),('05'),('06'),('07'),('08'),('09'),('10'),
  ('11'),('12'),('13'),('14'),('15'),
  ('20'),('21'),('22'),('23'),('24'),('25'),('26'),('27'),('28'),('29'),
  ('30'),('32'),('38'),('39')
) as f(sfx);

-- b16 and b31 carry a real span: b16 so a typed end date has somewhere to move
-- to, b31 so the check-in gate has a live membership to admit.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000000b16'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000b16'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000b31'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000b31'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 30, 100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 20a. THE THREE COLUMNS BESIDE THE PRICE, AND WHAT EACH ONE BUYS. The bare
-- price refusal is the visible suite's headline and is not re-proved here.
-- What is proved here is that the other three columns in GL046's list are
-- each a route to the same arithmetic — currency decides which payments count
-- toward the total at all, plan_id RE-DERIVES the price (ADR-092), and
-- discount_paise is the column ADR-094 rejected bounding — and that the price
-- refusal is worth something at the till, not merely in the column.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set currency = 'USD' where id = '220000ff-0022-4000-8000-600000000b01'$q$),
  'GL046/currency: a front-desk session changing the currency of a moneyless membership is refused. Currency is not decoration on a price — it decides which payments are counted toward the total at all (16i measured a currency-split membership whose money and count legitimately disagree), so re-denominating a membership is deciding what the member owes');

select is(
  (select currency from public.memberships where id = '220000ff-0022-4000-8000-600000000b01'::uuid),
  'INR',
  'GL046/currency: and it is unchanged at INR — refused AND unmoved');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set plan_id = '220000ff-0022-4000-8000-400000000b01' where id = '220000ff-0022-4000-8000-600000000b02'$q$),
  'GL046/plan: a front-desk session repointing a moneyless membership at another plan is refused. This is the column that makes the list a list of four rather than one: ADR-092 made a plan change RE-DERIVE the price, so plan_id is a route to price_paise, and a rule that named only the price would leave the desk a two-step way to the same number');

select ok(
  (select plan_id = '220000ff-0022-4000-8000-400000000001'::uuid and price_paise = 100000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b02'::uuid),
  'GL046/plan: and NEITHER moved — the plan is the one it was sold on and the price is still 100000, not the 200000 a landed correction would have re-derived');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set discount_paise = 90000 where id = '220000ff-0022-4000-8000-600000000b03'$q$),
  'GL046/discount: a front-desk session writing a 90000-paise discount onto a moneyless membership is refused. ADR-094 rejected BOUNDING this column on the ground that a bound moves the exploit rather than closing it; naming it in the who-rule is the other half of that rejection, and a fix that stopped at the three terms GL043 already freezes would leave it out');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b03'::uuid),
  0::bigint,
  'GL046/discount: and it is unchanged at 0');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 10000 where id = '220000ff-0022-4000-8000-600000000b04'$q$),
  'GL046/price: the exploit statement itself — a front desk cutting a Rs.1,000 membership to Rs.100 before any money has arrived, which every previous round permitted');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b04'::uuid),
  100000::bigint,
  'GL046/price: and the price is unchanged at 100000');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b04', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b04', '220000ff-0022-4000-8000-600000000b04', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL046/price: the ordinary full fee is then taken by the same desk, exactly as the ADR-094 sequence does');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b04'::uuid),
  '30/1',
  'GL046/price: and it bought ONE period of 30 days. This reads 300/10 if the refusal above did not actually hold — the whole of ADR-094 in one assertion, and the reason a column check is not enough on its own: the harm is at the till, not in the column');

-- ---------------------------------------------------------------------------
-- 20b. THE THREE DESIGNS ADR-094 REJECTED, each of which implies something
-- that must STILL WORK. A refusal broad enough to pass 20a and cheap enough
-- to write in an afternoon is "derive the price from the plan" or "refuse a
-- price below the plan's", and both were considered and rejected — the first
-- because a gym legitimately sells below list, the second because any bound
-- is a number nobody chose. If an implementation quietly takes one of those
-- roads instead, every refusal above still passes and this block is where it
-- fails.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b05'$$,
  'GL046/below-list: a manager sells at HALF the plan''s list price. "Rejected: derive price_paise from the plan" — a gym legitimately sells below list, and a derived price would leave no way to sell at a negotiated number at all');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b05'::uuid),
  50000::bigint,
  'GL046/below-list: and the negotiated price LANDED, not silently replaced by the plan''s 100000');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b05', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b05', '220000ff-0022-4000-8000-600000000b05', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000002')$$,
  'GL046/below-list: the negotiated Rs.500 is taken');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b05'::uuid),
  '30/1',
  'GL046/below-list: and it bought exactly one period — the money is scored against the CORRECTED price, which is the scenario "a payment SHALL be scored against the corrected price" and the whole point of leaving the door open for an admin');

select lives_ok(
  $$update public.memberships set price_paise = 10000 where id = '220000ff-0022-4000-8000-600000000b06'$$,
  'GL046/90-percent: a manager discounts by NINETY per cent. "Rejected: refuse a price below the plan''s" — any threshold is arbitrary, and ADR-094''s own words are that a gym discounting 30% is ordinary while one discounting 90% is a decision, not an error. This is the assertion a bounded implementation fails');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b06'::uuid),
  10000::bigint,
  'GL046/90-percent: and it landed');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b06', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b06', '220000ff-0022-4000-8000-600000000b06', 10000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000002')$$,
  'GL046/90-percent: the agreed Rs.100 is taken');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b06'::uuid),
  '30/1',
  'GL046/90-percent: and the 90%-discounted membership BEHAVES — one period for the agreed price, not a stalled row and not ten periods');

select lives_ok(
  $$update public.memberships set price_paise = 1 where id = '220000ff-0022-4000-8000-600000000b07'$$,
  'GL046/comp: a manager comps a membership to ONE PAISA. ADR-094 states this outcome in its own prose — "a gym_owner or gym_manager can still comp a membership to a paisa. THEY SHOULD BE ABLE TO" — and accepts the bound that the price sits on the row as evidence. A rule that stops the desk by bounding the number stops this too, and this project chose not to');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b07'::uuid),
  1::bigint,
  'GL046/comp: and it landed at 1 paisa');

select lives_ok(
  $$update public.memberships set discount_paise = 90000 where id = '220000ff-0022-4000-8000-600000000b08'$$,
  'GL046/discount-admin: discount_paise is still WRITABLE — by an admin. "Rejected: bound the discount instead" removes a bound, not the column, and the seed itself writes one on the demo gym''s discounted Annual');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b08'::uuid),
  90000::bigint,
  'GL046/discount-admin: and the discount landed');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b08', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b08', '220000ff-0022-4000-8000-600000000b08', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000002')$$,
  'GL046/discount-unread: the GROSS Rs.1,000 is taken against that 90%-discounted membership');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b08'::uuid),
  '300/10',
  'NET-PRICE / GL046: the gross receipt buys ten periods at the agreed 10000-paise net price; the old OPEN-028 tripwire is now the contracted behavior');

select is(
  (select price_paise from public.plans where id = '220000ff-0022-4000-8000-400000000b01'::uuid),
  200000::bigint,
  'GL046/list-price: gym A''s premium plan still lists at 200000 after a front-desk session tried to cut it to 10000 in 20a''s claim (measured: the statement raises nothing and updates no row, because `plans_tenant_write` is already `is_gym_admin()`). Deciding what a member owes was ALREADY the manager''s one table over, for the list price and for refunds both; GL046 closes the gap where the same decision was reachable per-membership');

select lives_ok(
  $$update public.plans set price_paise = 250000 where id = '220000ff-0022-4000-8000-400000000b01'$$,
  'GL046/list-price: and a manager re-prices the plan, which must keep working — ADR-090 rejected freezing the plans row so a gym can re-price for future sales');

select is(
  (select price_paise from public.plans where id = '220000ff-0022-4000-8000-400000000b01'::uuid),
  250000::bigint,
  'GL046/list-price: and that landed');

-- ---------------------------------------------------------------------------
-- 20c. is_gym_admin() ITSELF. It reads one JWT claim and returns FALSE for a
-- session that carries none. Four callers legitimately carry none, and one of
-- them is the seed. SIDED throughout, on ADR-082's general form, and the
-- reading is stated in each assertion so a critic can disagree with the
-- reasoning rather than guess at it.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b09'$$,
  'GL046/no-claim: a session with NO JWT claim at all — `postgres`, the CLI, the seed — may set a price. SIDED on ADR-082''s general form: a trusted-caller carve-out is sound exactly where the rule''s subject is something a trusted caller legitimately LACKS, and "which staff role you are" is exactly that. Contrast a receipt number or a refund ceiling, which are invariants about the DATA: carve those out and the webhook issues receiptless payments. This rule''s subject is an identity, and a trusted context has none to offer');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b09'::uuid),
  50000::bigint,
  'GL046/no-claim: and it landed');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b09', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b09', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 77777, 3333, 'INR')
    on conflict (id) do update set
      plan_id        = excluded.plan_id,
      price_paise    = excluded.price_paise,
      discount_paise = excluded.discount_paise,
      currency       = excluded.currency$$,
  'GL046/seed: THE SEED''S OWN STATEMENT SHAPE, not a paraphrase of it. supabase/seed.sql builds every demo membership as an `insert ... on conflict (id) do update set plan_id, price_paise, discount_paise, currency`, run as the CLI''s claimless `postgres` session, and re-running it converges rather than duplicating (its rule 1). On a re-run that DO UPDATE is a live UPDATE of three of GL046''s four columns. A rule without the carve-out above turns `gh workflow run seed.yml` red, and a seed going red on a rule written days earlier has already happened once this phase');

select is(
  (select price_paise::text || '/' || discount_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b09'::uuid),
  '77777/3333',
  'GL046/seed: and the upsert''s values landed on the existing row — the re-run converged, which is the behaviour the whole seed is built around');

select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;

select lives_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b10'$$,
  'GL046/service_role: the Razorpay webhook''s role may set a price too, on the same reading. It carries no app_role because it is not a person; 19g already asserts the mirror image for GL045 — a hand-written DATE from service_role IS refused — and the two together are ADR-082''s distinction drawn on one table: the identity rule carves out, the arithmetic rule does not');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b10'::uuid),
  50000::bigint,
  'GL046/service_role: and it landed');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'trainer',
                     'staff_id', '220000ff-0022-4000-8000-300000000004')::text,
  true
);
set local role authenticated;

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b11'::uuid),
  100000::bigint,
  'GL046/trainer: a TRAINER''s price change leaves the price where it was. Asserted as the value rather than as a refusal on purpose: `memberships_tenant_write` is `is_front_office()`, which excludes a trainer, so the row is filtered out by row security and the statement updates NOTHING and raises NOTHING. A rule asserted only through its error code would report this as unprotected; the value is what the member actually experiences');

select diag(
  'h22 R11 / GL046 trainer: `update memberships set price_paise` from a trainer session returned '
  || coalesce(pg_temp.h22r8_try($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b11'$q$), 'null')
  || ' (OK means row security filtered the row out silently — no error, no rows). Reported rather than asserted: whether a non-front-office staff role should be REFUSED or merely see nothing is a question about RLS, not about GL046, and this file does not decide it.');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'app_role', 'super_admin')::text,
  true
);

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b13'$q$),
  'GL046/super_admin: a bare platform session is NOT a gym admin and is refused. SIDED, and called out in the report as one of two places this author chose a side. `memberships_platform_write` permits the write today and it lands (measured), so this is a real choice: docs/security.md is that an impersonating token carries the target gym''s tenant_id and `app_role = gym_owner` and "is NOT a platform session", which is exactly the mechanism by which platform support makes a change ON BEHALF of a gym. A platform operator re-pricing a member''s membership out of band, with no impersonation session and no reason recorded, is the act that posture exists to prevent');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b13'::uuid),
  100000::bigint,
  'GL046/super_admin: and unchanged at 100000');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_owner',
                     'staff_id', '220000ff-0022-4000-8000-300000000004',
                     'impersonation_session_id', gen_random_uuid())::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 60000 where id = '220000ff-0022-4000-8000-600000000b14'$$,
  'GL046/impersonation: and the support path the assertion above pushes platform staff onto still WORKS — an impersonating token carrying the gym''s tenant_id, `app_role = gym_owner` and an impersonation_session_id re-prices normally. Refusing the bare platform session buys nothing if it also refuses this, and this is the half that keeps the refusal proportionate');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b14'::uuid),
  60000::bigint,
  'GL046/impersonation: and it landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_owner',
                     'staff_id', '220000ff-0022-4000-8000-300000000004')::text,
  true
);

select lives_ok(
  $$update public.memberships set price_paise = 70000, currency = 'USD', discount_paise = 1000 where id = '220000ff-0022-4000-8000-600000000b12'$$,
  'GL046/gym_owner: the OTHER admin role. `is_gym_admin()` is (gym_owner, gym_manager) and every permitted assertion above was sent by a manager; an implementation that hard-coded the manager alone passes all of them and locks the owner out of their own gym''s pricing');

select ok(
  (select price_paise = 70000 and currency = 'USD' and discount_paise = 1000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b12'::uuid),
  'GL046/gym_owner: and all three landed');

-- ---------------------------------------------------------------------------
-- 20d. THE INTERACTION WITH THE TWO FREEZES. GL046 is about WHO; GL043 and
-- GL045 are about WHAT and WHEN, and being a gym admin buys no relief from
-- either. The ordering question — which rule answers a front desk on a paid
-- membership — is reported, not asserted: the requirement settles the outcome
-- and says nothing about the code, and over-specifying it would make an
-- implementer add sequencing logic to satisfy a test rather than a gym. The
-- leak that ordering could carry IS asserted, from the only session for whom
-- it would be a leak.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b15', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b15', '220000ff-0022-4000-8000-600000000b15', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL046/after-money: the desk sells and takes the money — the baseline the next four assertions are worth anything against');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b15'$q$),
  'GL046/after-money: a GYM ADMIN cutting the price after money has arrived is still refused — the spec''s own scenario, "being a gym admin does not unfreeze what money has bought". GL046 widens who may re-price and narrows nothing; an implementation that replaced GL043''s money gate with a role gate would pass every refusal in 20a and hand the manager the exploit instead of the desk');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b15'::uuid),
  100000::bigint,
  'GL046/after-money: and unchanged');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b15'$q$),
  'GL046/ordering: and the front desk is refused on the same row, where BOTH rules have an answer');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b15'::uuid),
  100000::bigint,
  'GL046/ordering: unchanged');

select diag(
  'h22 R11 / GL046 ordering: a front desk cutting the price of a PAID membership returned '
  || coalesce(pg_temp.h22r8_try($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b15'$q$), 'null')
  || '; the same session on a MONEYLESS membership returned '
  || coalesce(pg_temp.h22r8_try($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b39'$q$), 'null')
  || '. Reported, not asserted. If the two differ, the code tells a front desk whether money has arrived — which costs nothing here, because a front desk can read the payments table directly (`payments_tenant_select` is is_front_office), so it learns nothing it could not already query. The assertion below covers the session for which it WOULD be a leak.');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'member',
                     'member_id', '220000ff-0022-4000-8000-500000000b15')::text,
  true
);

select is(
  pg_temp.h22r8_try($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b15'$q$),
  pg_temp.h22r8_try($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b16'$q$),
  'GL046/leak: a MEMBER session gets the SAME answer for a paid membership and a moneyless one — so no ordering between GL043 and GL046 can tell a member whether money has landed against a membership, which is the only place the ordering could leak anything. This holds today because row security filters both rows before any rule of this phase sees them; it stops holding the moment GL046 is implemented as a check that raises before row security has finished (ADR-082''s own second consequence — a member inserting a payment got GL034 where a 42501 belonged, in a file that quoted the rule at the point of the mistake)');

-- The verification is read back from a STAFF session on purpose: a member sees
-- only their own memberships (`memberships_member_select`), so counting both
-- rows from the member's own claim would count one and pass for the wrong
-- reason. Measured, while writing this.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select ok(
  (select count(*)::int from public.memberships
    where id in ('220000ff-0022-4000-8000-600000000b15'::uuid, '220000ff-0022-4000-8000-600000000b16'::uuid)
      and price_paise = 100000) = 2,
  'GL046/leak: and neither price moved');

select throws_ok(
  $$update public.memberships set ends_on = starts_on + 3650 where id = '220000ff-0022-4000-8000-600000000b16'$$,
  'GL045'::char(5), null,
  'GL046/dates: a GYM ADMIN typing an end date is still refused by GL045. The two rules answer different questions — GL046 says who may decide what is owed, GL045 says that nobody types what the money bought — and an implementation that read "gym-admin work" as a general unlock would hand the manager the ten-year statement round ten closed');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b16'::uuid),
  '30',
  'GL046/dates: and the span is unchanged at 30');

-- ---------------------------------------------------------------------------
-- 20e. THE CREATE PATH, AND THE DOOR IT WAS. `POST /api/memberships` copies
-- the plan's price and never lets a caller name one, so the product's own
-- create path is untouched by GL046 and had to be confirmed rather than
-- assumed. But the requirement is written on the verb CHANGES, and the table
-- is reached by more than that handler: `memberships_tenant_write` grants the
-- front office INSERT with no column restriction, which is one
-- `.insert({ price_paise })` from any front-desk browser session.
--
-- ADR-092's own grep, which ADR-094 says is now part of fixing a contract
-- rather than a thing to remember: WHERE A REQUIREMENT NAMES A HARM, NO
-- SCENARIO UNDER IT MAY PERMIT THAT HARM'S OUTCOME BY ANOTHER ROUTE. Run on
-- GL046 as first written, it failed. The requirement names the harm — "a front
-- desk sets a Rs.1,500 membership's price to Rs.150 and takes the ordinary
-- Rs.1,500: 300 days" — and its own scenario "A front desk selling and taking
-- money" permitted the desk to CREATE memberships with no bound on the price
-- it names. This author measured it live before writing a line: create at one
-- tenth of the plan's price, take the ordinary full fee, 300 days and ten
-- periods, ONE FEWER STATEMENT than the exploit ADR-094 was written to close,
-- and no UPDATE anywhere for the rule to refuse. The visible suite's author
-- measured the same door independently, and the coordinator closed it to both
-- suites before either handed back: a membership created with a `price_paise`
-- or `currency` differing from its plan's, or a non-zero `discount_paise`,
-- is gym-admin work too. Creating at the plan's own price is ordinary desk
-- work, and `plan_id` at creation is just choosing a plan.
--
-- That NARROWS OPEN-029 without closing it, and the part left open is
-- deliberate and load-bearing: creation may still set DATES freely, which is
-- what `seed.sql` and every fixture in both suites depend on. 19g's ten-year
-- creation therefore stays green, and this block asserts why the two answers
-- differ rather than leaving a reader to wonder.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b17', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b17', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 'INR')$$,
  'GL046/sell: the spec''s own permitted scenario — a front desk CREATES a membership at its plan''s price. This is exactly what `POST /api/memberships` writes, and a fix that read "the front office may not touch these columns" as covering every INSERT would break the one act the front desk exists to perform');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b17', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b17', '220000ff-0022-4000-8000-600000000b17', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL046/sell: and records the payment against it — "both SHALL be allowed"');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b17'::uuid),
  '30/1',
  'GL046/sell: one period for one fee, which is the loop this whole product is for');

select ok(
  pg_temp.h22r8_refused($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values ('220000ff-0022-4000-8000-600000000b18', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b18', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 10000, 'INR')$q$),
  'GL046/create-price: a front desk CREATING a membership on the Rs.1,000 plan at a price of its own — Rs.100, one tenth of list — is refused. Measured live before this rule: allowed, and the ordinary full fee against it bought 300 days and ten periods with both audit invariants intact. Third round running that the INSERT was the unpoliced door');

select ok(
  not exists (select 1 from public.memberships where id = '220000ff-0022-4000-8000-600000000b18'::uuid),
  'GL046/create-price: and NOTHING landed — no row, so no ten periods to buy. The harm is asserted absent rather than the statement merely refused, because a refusal that left a cheap membership behind would be no refusal at all');

select ok(
  pg_temp.h22r8_refused($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values ('220000ff-0022-4000-8000-600000000b33', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b33', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 'USD')$q$),
  'GL046/create-currency: and a front desk creating at the plan''s NUMBER in a different CURRENCY is refused too. The number matches and the money does not: a USD-denominated membership on an INR plan is a price wrong by an exchange rate that looks completely ordinary, and 18c(v) already bounded the same mistake on the UPDATE side');

select ok(
  not exists (select 1 from public.memberships where id = '220000ff-0022-4000-8000-600000000b33'::uuid),
  'GL046/create-currency: and nothing landed');

select ok(
  pg_temp.h22r8_refused($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency) values ('220000ff-0022-4000-8000-600000000b19', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b19', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 40000, 'INR')$q$),
  'GL046/create-discount: and a front desk creating a membership that carries a 40000-paise discount is refused, at the plan''s own price. Nothing in the money path reads that column today (OPEN-028), so this refusal buys nothing at the till right now — it buys that the column cannot be pre-loaded at creation against the day the granting rule starts reading it, which is the door the count rule (GL044) had to close at creation after it was closed at update');

select ok(
  not exists (select 1 from public.memberships where id = '220000ff-0022-4000-8000-600000000b19'::uuid),
  'GL046/create-discount: and nothing landed');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b34', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b34', '220000ff-0022-4000-8000-400000000b01', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 250000, 'INR')$$,
  'GL046/create-plan: `plan_id` at creation is unrestricted — a front desk sells on the gym''s OTHER plan, at that plan''s own price. Choosing which plan a member is buying is the desk''s whole job, and a rule that read "the front desk may only ever create on one plan" would pass every refusal above');

select is(
  (select price_paise::text || '/' || duration_days::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b34'::uuid),
  '250000/30',
  'GL046/create-plan: and it landed at the premium plan''s current price and length — the price the manager set two blocks up, read from the plans table at the moment of sale, which is what "at its plan''s price" has to mean if a gym may re-price at all');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b35', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b35', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 10000, 5000, 'INR')$$,
  'GL046/create-admin: a MANAGER creates the very membership the desk was just refused — one tenth of list, with a discount. Negotiating at the point of sale is real and the rule moves it up a rank rather than abolishing it; a refusal that applied to everyone would make "sell at a negotiated number", the reason ADR-094 rejected deriving the price at all, impossible at creation');

select is(
  (select price_paise::text || '/' || discount_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b35'::uuid),
  '10000/5000',
  'GL046/create-admin: and both landed');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b36', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b36', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 20000, 2000, 'INR')$$,
  'GL046/create-trusted: and the claimless trusted context creates one too, off-plan and discounted — the exemption reaches the INSERT half of the rule, not only the UPDATE half. This is `seed.sql`''s own membership shape: it writes `price_paise` from the plan and a `discount_paise` of one tenth on its fourth member, with no claim anywhere, so a create-side rule without the carve-out puts `seed-dry-run` red on the FIRST run rather than on a re-run');

select is(
  (select price_paise::text || '/' || discount_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b36'::uuid),
  '20000/2000',
  'GL046/create-trusted: and it landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b37', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b37', '220000ff-0022-4000-8000-400000000001', 'active',
            (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A') + 3650, 100000, 'INR')$$,
  'GL046/open-029: and the DATES at creation are still free — a front desk creates a TEN-YEAR membership at the plan''s honest price, and it is allowed. OPEN-029 is narrowed by this round, not closed: the money columns are now policed at creation and the span is not, because the rule that would police it contradicts `seed.sql` and the fixtures of both suites, and a contract change made in the same breath as a fix is how this phase produced rounds eight and nine');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text || '/' || price_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b37'::uuid),
  '3650/0/100000',
  'GL046/open-029: 3,650 days, nothing granted, an honest price. This is 19g''s assertion restated under the narrowed rule, and the pair is the point: the same INSERT is refused for its PRICE and permitted for its SPAN, which is a real asymmetry and now a deliberate one');

-- ---------------------------------------------------------------------------
-- 20f. MULTI-ROW AND MULTI-STATEMENT. Every defect in this phase has survived
-- the single-row case and died on one of these, and ADR-092 names MERGE and
-- `UPDATE ... FROM` as measured routes to the exploit two rounds ago. A rule
-- written as a row trigger reading old/new, one written as a statement
-- trigger, and one written per transaction each behave differently below.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id in ('220000ff-0022-4000-8000-600000000b20', '220000ff-0022-4000-8000-600000000b21')$q$),
  'GL046/multi-row: one statement re-pricing several memberships is refused');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b20'::uuid),
  100000::bigint,
  'GL046/multi-row: the first is unchanged');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b21'::uuid),
  100000::bigint,
  'GL046/multi-row: and so is the second — not a rule that catches the first row and lets the rest through');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships m set price_paise = v.p from (values ('220000ff-0022-4000-8000-600000000b22'::uuid, 40000::bigint), ('220000ff-0022-4000-8000-600000000b23'::uuid, 30000::bigint)) as v(id, p) where m.id = v.id$q$),
  'GL046/update-from: `UPDATE ... FROM` naming a DIFFERENT price per row is refused. The values come from a join rather than a literal, which is where a rule that inspects the statement text instead of the row fails');

select ok(
  (select count(*)::int from public.memberships
    where id in ('220000ff-0022-4000-8000-600000000b22'::uuid, '220000ff-0022-4000-8000-600000000b23'::uuid)
      and price_paise = 100000) = 2,
  'GL046/update-from: and both are unchanged');

select ok(
  pg_temp.h22r8_refused($q$merge into public.memberships m using (select '220000ff-0022-4000-8000-600000000b24'::uuid as id) s on m.id = s.id when matched then update set currency = 'USD'$q$),
  'GL046/merge: a MERGE re-denominating a membership is refused — the same act through the one statement shape that fires no ordinary UPDATE path');

select is(
  (select currency from public.memberships where id = '220000ff-0022-4000-8000-600000000b24'::uuid),
  'INR',
  'GL046/merge: and it is unchanged');

select ok(
  pg_temp.h22r8_refused($q$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000000b25', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b25', '220000ff-0022-4000-8000-600000000b25', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning tenant_id) update public.memberships set discount_paise = 90000 where id = '220000ff-0022-4000-8000-600000000b26' and exists (select 1 from p)$q$),
  'GL046/cte: a data-modifying CTE that takes a perfectly legitimate payment against ONE membership and rewrites another''s discount in the same statement is refused. The illegitimate half rides on a legitimate one, which is the shape a rule armed on "this statement only touches memberships" never sees');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b26'::uuid),
  0::bigint,
  'GL046/cte: the discount is unchanged');

select is(
  (select periods_granted::text || '/' || (select count(*)::text from public.payments where id = '220000ff-0022-4000-8000-700000000b25'::uuid)
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b25'::uuid),
  '0/0',
  'GL046/cte: and the PAYMENT did not land either — no receipt number burned, no period granted, the whole statement refused rather than half-applied. A refusal that kept the money and dropped the re-price would be worse than either');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = case when id = '220000ff-0022-4000-8000-600000000b27' then 10000 else price_paise end, cancel_reason = 'desk note' where id in ('220000ff-0022-4000-8000-600000000b27', '220000ff-0022-4000-8000-600000000b28')$q$),
  'GL046/mixed: one statement over two memberships where only ONE actually changes a restricted column — the other is a same-value write beside a legitimate note — is refused. A rule comparing old to new per row must fire on the row that moved, and must not be talked out of it by the row that did not');

select is(
  (select price_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000b27'::uuid),
  100000::bigint,
  'GL046/mixed: the price that would have moved is unchanged');

select is(
  (select coalesce(cancel_reason, 'NULL') from public.memberships where id = '220000ff-0022-4000-8000-600000000b28'::uuid),
  'NULL',
  'GL046/mixed: and the ENTIRELY legitimate note on the other membership did not land either — one statement, one outcome. That cost is real and is the right one: half-applying is how the console shows a desk a save that partly worked');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b29', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b29', '220000ff-0022-4000-8000-600000000b29', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL046/sequence: a wholly legitimate statement first — the desk takes a full payment, which grants a period');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000000b38'$q$),
  'GL046/sequence: the illegitimate statement immediately after it, in the same transaction, is refused on its own merits. It names a DIFFERENT membership, one that has taken nothing, so GL046 is the only rule with an answer — a price cut on the just-paid row would be refused by GL043 and would prove nothing about this round');

select ok(
  (select periods_granted = 1 and (ends_on - starts_on) = 30 and price_paise = 100000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b29'::uuid)
  and (select price_paise = 100000 from public.memberships where id = '220000ff-0022-4000-8000-600000000b38'::uuid),
  'GL046/sequence: and the legitimate statement SURVIVES while the refused one moved nothing — one period, thirty days, both prices where they were. A rule that aborted the transaction rather than the statement would take the receipted payment down with the refusal, and a desk would lose money it had already handed a receipt for');

-- ---------------------------------------------------------------------------
-- 20g. THE PERMITTED SIDE, AS HARD AS THE REFUSED. A fix that is too broad
-- passes every refusal above and this project has shipped exactly that three
-- times. Everything below is legitimately green today and is here to stay
-- green: the front desk sells, takes money, renews, pauses, checks a member
-- in, edits a note and freezes a membership, and it sends the ordinary
-- column-listing save that writes all four restricted columns back at their
-- own values. What it may NOT do is give money back, which is the precedent
-- ADR-094 built GL046 on.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000b2a', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b29', '220000ff-0022-4000-8000-600000000b29', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'permitted: the desk RENEWS — a second full fee against the same membership');

select is(
  (select periods_granted::text || '/' || (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b29'::uuid),
  '2/60',
  'permitted: and it bought a second period. The renewal is the loop this product exists for, and it is silent to everyone but the member when it stops');

select lives_ok(
  $$insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
    values ('220000ff-0022-4000-8000-b00000000b01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-600000000b30',
            (select today from gym_today where org_key = 'A') + 1, (select today from gym_today where org_key = 'A') + 8, 'travel', '220000ff-0022-4000-8000-300000000001')$$,
  'permitted: the desk requests a PAUSE — a pause carries its own price-free terms on its own table, and a rule that greps for column names rather than tables catches it');

select lives_ok(
  $$insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-a00000000b01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000b31', '220000ff-0022-4000-8000-600000000b31', now(), 'qr', '220000ff-0022-4000-8000-900000000a01')$$,
  'permitted: and a member CHECKS IN at the gate against a live membership — the first step of the loop, and the one that reads a membership without deciding anything about what it cost');

select lives_ok(
  $$update public.memberships set cancel_reason = 'called, will pay Friday' where id = '220000ff-0022-4000-8000-600000000b32'$$,
  'permitted: the desk edits a note on a membership');

select is(
  (select cancel_reason from public.memberships where id = '220000ff-0022-4000-8000-600000000b32'::uuid),
  'called, will pay Friday',
  'permitted: and it landed');

select lives_ok(
  $$update public.memberships
       set price_paise = price_paise, currency = currency, plan_id = plan_id, discount_paise = discount_paise,
           cancel_reason = 'second save from the same form'
     where id = '220000ff-0022-4000-8000-600000000b32'$$,
  'permitted/same-value: THE ASSERTION AN OVER-BROAD FIX FAILS. All four restricted columns written back at their own values alongside the one field actually being edited — what a REST client sends when it saves every column it loaded. GL046 says "CHANGES a membership''s price"; the two requirements beside it settle the same-value case explicitly, in the same words and for the same reason ("a rule that refuses a write that cannot do harm buys nothing and breaks ordinary column-listing updates"), and the shortest rule that passes every refusal in this section refuses this');

select is(
  (select cancel_reason from public.memberships where id = '220000ff-0022-4000-8000-600000000b32'::uuid),
  'second save from the same form',
  'permitted/same-value: and the real edit landed');

select ok(
  (select price_paise = 100000 and currency = 'INR' and discount_paise = 0
      and plan_id = '220000ff-0022-4000-8000-400000000001'::uuid
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b32'::uuid),
  'permitted/same-value: while all four restricted columns are exactly where they were — allowed because nothing moved, not because the rule was talked out of looking');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000000b32'$$,
  'permitted: and freezing a membership still works — a lifecycle change is not a decision about what is owed');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000b01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000b29', 'refund', 10000, 'h22 R11 desk-attempted refund', '220000ff-0022-4000-8000-300000000001')$$,
  '42501'::char(5), null,
  'permitted/precedent: what the front desk may NOT do, and the whole argument GL046 rests on. `refunds_tenant_write` is `is_gym_admin()`, not `is_front_office()` — "front_desk may record money but not refund it" — and ADR-094''s case is that deciding what a member owes is the same kind of act as deciding to give money back. Asserted as evidence already held: this is the precedent, and it must still be true for the analogy to be worth anything');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000b02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000b29', 'refund', 10000, 'h22 R11 manager refund', '220000ff-0022-4000-8000-300000000002')$$,
  'permitted/precedent: and the manager''s refund is accepted — the other half of the same policy, and the shape GL046 copies onto the membership');


set local role postgres;
select set_config('request.jwt.claims', '', true);


-- ---------------------------------------------------------------------------
-- 21. TENTH-SESSION EXTENSION, round TWELVE. Two small things on the same
--     requirement: `coupon_id` joins GL046's column list (21a), and "A comp
--     that was a typo" — the repair path the requirement PRESCRIBES and
--     nobody had ever run — is asserted end to end as a working sequence
--     (21b).
--
-- WRITTEN BY THE SAME AUTHOR AS THE VISIBLE SUITE'S ROUND-TWELVE SECTIONS.
-- That is a deliberate, recorded deviation from the two-author arrangement
-- (AGENTS.md hard rule 10 / ADR-059), and it is stated here rather than in a
-- commit message so that the next reader of this file knows the independence
-- was traded knowingly. The reason: what two blind authors buy is independent
-- INTERPRETATION of a requirement, and this round has none left to make.
-- `coupon_id` is one more column on a rule both suites already carry full
-- batteries for — the shape of the assertion is settled by the four columns
-- already there — and 21b is a sequence of writes every one of which is
-- already specified and already asserted separately in these two files. What
-- it adds is running them in order, which two authors would do identically.
-- Everything else about the arrangement is unchanged: the sections were
-- written from the requirement, committed red, and no implementation of
-- GL046 was read (no prosrc, no pg_get_functiondef, no migration later than
-- round ten's), and per ADR-091 docs/registry.md was not read for anything
-- about this round's code.
--
-- 21a — WHY THE COLUMN IS IN THE LIST, measured live before this section was
-- written, from an ordinary front-desk session:
--
--     update memberships set coupon_id      = <a live coupon> …;  -- OK
--     update memberships set discount_paise = 15000 …;            -- GL046
--
-- leaving a row that says a coupon was applied and that the discount is zero.
-- The two columns describe one decision — the coupon is the NAME of the
-- reason, the discount is its SIZE — so a rule that owns one and not the
-- other does not merely leave a door open, it manufactures rows whose two
-- halves contradict each other with nothing raised. That contradiction is
-- what this section asserts against directly: the pair statement, and then
-- the state of both columns afterwards.
--
-- 21b — WHY THE REPAIR PATH NEEDS ASSERTING AT ALL. GL046 changes who may set
-- a price; it cannot stop one being mistyped, and a gym admin fat-fingering
-- Rs.100 for Rs.1,000 is the shape that remains. The moment money lands the
-- price is frozen (GL043) and the dates are frozen (GL045), so the row cannot
-- be corrected in place — the requirement says exactly this, names
-- unrepairability as the harm the previous round made worse, and prescribes
-- "refund the payment, cancel the membership, and sell a new one". A remedy
-- named in prose and never executed is a claim, not a path. Every step is
-- asserted here, in order, on one member, including the two refusals that
-- make the sequence necessary — so a later round that quietly unfreezes
-- either shows up as an assertion going green in the wrong direction rather
-- than as a file that still passes.
--
-- THE ONE NON-OBVIOUS THING 21b PROVES: **the refund is not the repair.**
-- Money that arrived counts toward the total whether or not it was given
-- back (the granting rule's own definition, one requirement over), so a full
-- refund moves neither the count nor the dates and the wrongly-dated
-- membership stays live at the gate. That is why the requirement says CANCEL
-- as well, and it is asserted rather than assumed.
-- ---------------------------------------------------------------------------

set local role postgres;

insert into public.coupons (id, tenant_id, code, percent_bp, currency, is_active) values
  ('220000ff-0022-4000-8000-c00000000c01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   'H22R12TEN', 1000, 'INR', true);

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000000c01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-200000000001'::uuid, 'h22-r12-gate-token-hash',
   now() + interval '1 day', '220000ff-0022-4000-8000-300000000001'::uuid);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-500000000b' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  '220000ff-0022-4000-8000-200000000001'::uuid,
  'H22 R12 Member ' || f.sfx,
  '+919220012' || f.sfx || '0'
from (values ('40'),('41'),('42'),('43'),('44')) as f(sfx);

-- b40 is the update battery's row: gym A's 30-day plan at its list price,
-- no money, no coupon, no discount.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000000b40'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-500000000b40'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid,
   'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'),
   100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 21a. `coupon_id`, mirroring what this file already asserts for
-- `discount_paise`: refused for the desk with the value unchanged, allowed
-- for a gym admin and LANDED, on UPDATE and at creation, with the same-value
-- save and the trusted carve-out beside them.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set coupon_id = '220000ff-0022-4000-8000-c00000000c01' where id = '220000ff-0022-4000-8000-600000000b40'$q$),
  'GL046/coupon: a front-desk session attaching a coupon to a moneyless membership is refused. A coupon is the NAME of the reason a member owes less and discount_paise is its SIZE; ADR-094 put the discount in the list because bounding the price and leaving the discount free moves the exploit, and leaving the coupon free moves the RECORD of it');

select is(
  pg_temp.h22r8_val($q$select coalesce(coupon_id::text, 'null') from public.memberships where id = '220000ff-0022-4000-8000-600000000b40'$q$),
  'null',
  'GL046/coupon: and no coupon is attached — refused AND unmoved');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set coupon_id = '220000ff-0022-4000-8000-c00000000c01', discount_paise = 10000 where id = '220000ff-0022-4000-8000-600000000b40'$q$),
  'GL046/coupon: the coupon and the discount it implies, written together in the one statement a console actually sends, are refused together');

select is(
  pg_temp.h22r8_val($q$select coalesce(coupon_id::text, 'null') || ' / ' || discount_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b40'$q$),
  'null / 0',
  'GL046/coupon: and NEITHER half landed. THIS IS THE ASSERTION THAT FAILS ON THE DEFECT AS FOUND — measured live, the coupon went on and the discount was refused, leaving a row reading "coupon applied, discount zero": the gym''s own book contradicting the gym''s own money, with nothing raised anywhere');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$update public.memberships set coupon_id = '220000ff-0022-4000-8000-c00000000c01', discount_paise = 10000 where id = '220000ff-0022-4000-8000-600000000b40'$$,
  'GL046/coupon: a gym_manager granting the same coupon with the discount it implies is ALLOWED — running a promotion is ordinary gym work, and the control ADR-094 chose is who, not what. A fix that simply froze the column for everybody passes every refusal above and fails here');

select ok(
  (select coupon_id = '220000ff-0022-4000-8000-c00000000c01'::uuid and discount_paise = 10000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b40'::uuid),
  'GL046/coupon: and BOTH landed — allowed and applied, not allowed and silently dropped');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$update public.memberships
       set price_paise = price_paise, currency = currency, plan_id = plan_id,
           discount_paise = discount_paise, coupon_id = coupon_id,
           cancel_reason = 'coupon confirmed with the member'
     where id = '220000ff-0022-4000-8000-600000000b40'$$,
  'GL046/coupon/same-value: the ordinary column-listing save with the FIFTH column in it. `coupon_id` is nullable, which is why it is worth its own assertion: a rule written with `<>` instead of `is distinct from` gets a nullable column wrong in one direction or the other, and this row now holds a non-null one');

select ok(
  (select coupon_id = '220000ff-0022-4000-8000-c00000000c01'::uuid and discount_paise = 10000
      and cancel_reason = 'coupon confirmed with the member'
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b40'::uuid),
  'GL046/coupon/same-value: and the real edit landed while the coupon stayed exactly where the manager put it');

select ok(
  pg_temp.h22r8_refused($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id) values ('220000ff-0022-4000-8000-600000000b41', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b41', '220000ff-0022-4000-8000-400000000001', 'pending', 100000, 'INR', '220000ff-0022-4000-8000-c00000000c01')$q$),
  'GL046/coupon/create: the front desk CREATING a membership with a coupon on it is refused. Everything else in this row is the desk''s to write — the plan''s own price, the plan''s own currency, no discount — so the coupon is the only offending column in it. Creation is the door this requirement has already had to close once, and a fix that stops at UPDATE reopens it on the new column');

select is(
  pg_temp.h22r8_val($q$select count(*)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b41'$q$),
  '0',
  'GL046/coupon/create: and no row landed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_owner',
                     'staff_id', '220000ff-0022-4000-8000-300000000004')::text,
  true
);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id, discount_paise)
    values ('220000ff-0022-4000-8000-600000000b42', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b42', '220000ff-0022-4000-8000-400000000001', 'pending', 100000, 'INR', '220000ff-0022-4000-8000-c00000000c01', 10000)$$,
  'GL046/coupon/create: a gym_owner selling the same membership on the same coupon is allowed — the other admin role, because is_gym_admin() is two roles and an implementation that hard-codes the manager locks the owner out of their own gym''s promotions');

select ok(
  (select coupon_id = '220000ff-0022-4000-8000-c00000000c01'::uuid and discount_paise = 10000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b42'::uuid),
  'GL046/coupon/create: and it landed with the coupon and the discount AGREEING with each other, which is the state this column joins the list to protect');

set local role postgres;
select set_config('request.jwt.claims', '{}', true);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency, coupon_id, discount_paise)
    values ('220000ff-0022-4000-8000-600000000b43', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b43', '220000ff-0022-4000-8000-400000000001', 'pending', 100000, 'INR', '220000ff-0022-4000-8000-c00000000c01', 10000)$$,
  'GL046/coupon/trusted: a CLAIMLESS write attaching a coupon is allowed. This is not a courtesy — seed.sql''s membership block writes `coupon_id` in its `on conflict do update` list, as the CLI''s own claimless postgres session, on the demo gym''s one discounted membership. A rule without ADR-082''s carve-out on this column turns every seed re-run red, which has already happened once this phase');

select ok(
  (select coupon_id = '220000ff-0022-4000-8000-c00000000c01'::uuid and discount_paise = 10000
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b43'::uuid),
  'GL046/coupon/trusted: and it landed — the carve-out asserted in both directions on the fifth column, exactly as 20c asserts it on the other four');


-- ---------------------------------------------------------------------------
-- 21b. "A COMP THAT WAS A TYPO" — the requirement's own remedy, run.
-- Member b44 is sold a Rs.1,000 plan at Rs.100 by a manager who meant to type
-- the list price, pays the ordinary fee, and ends up with ten periods and 300
-- days. Nothing about that row can be edited afterwards. The sequence below
-- is the whole of what the requirement offers instead, and it is asserted
-- step by step because a remedy nobody has executed is a claim.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b44', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b44', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 10000, 'INR')$$,
  'repair: a gym_manager sells at a tenth of the list price. ALLOWED, and it must be — ADR-094 keeps the comp deliberately ("a gym admin can still comp a membership to a paisa, and should be able to"), and at the instant it is typed a comp and a typo are the same statement. GL046 moved WHO can make this mistake; it did not remove the mistake, which is why the requirement now has to say what happens next');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000c01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b44', '220000ff-0022-4000-8000-600000000b44', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'repair: and the desk takes the ordinary Rs.1,000 for it — the sale looks entirely normal from the till');

select is(
  (select periods_granted::text || '/' || (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b44'::uuid),
  '10/300',
  'repair: ten periods, 300 days, for one month''s fee — and both audit invariants hold on that record (periods = floor(money/price), span = duration x periods), which is why nothing downstream can find it');

select throws_ok(
  $$update public.memberships set price_paise = 100000 where id = '220000ff-0022-4000-8000-600000000b44'$$,
  'GL043'::char(5), null,
  'repair: the price cannot be corrected in place — money has arrived, and GL043 is an absolute that being a gym admin does not lift. Sent as a MANAGER on purpose: a desk session would be answered by either rule and the code would depend on nothing this file may rely on');

select throws_ok(
  $$update public.memberships set ends_on = (select today from gym_today where org_key = 'A') + 30 where id = '220000ff-0022-4000-8000-600000000b44'$$,
  'GL045'::char(5), null,
  'repair: and the dates cannot be typed back — they are the granting rule''s alone. These two refusals are the premise of everything below: they are asserted here so that a round which quietly unfreezes either one is visible as an assertion pointing the wrong way rather than as a file that still passes');

select ok(
  (select price_paise = 10000 and ends_on = (select today from gym_today where org_key = 'A') + 300
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b44'::uuid),
  'repair: refused AND unmoved in both — the row is exactly as wrong as it was');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000c01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000c01', 'refund', 100000, 'INR', 'desk attempt at the repair', '220000ff-0022-4000-8000-300000000001')$$,
  '42501'::char(5), null,
  'repair: the desk that sold it cannot START the repair — `refunds_tenant_write` is is_gym_admin(), the precedent GL046 was built on. So a mis-priced sale is made by an admin and unmade by an admin, and the desk''s part of it is the honest re-sale at the end');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000c02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000c01', 'refund', 100000, 'INR', 'mis-priced sale, refunded in full', '220000ff-0022-4000-8000-300000000002')$$,
  'repair/step one: the manager refunds the payment IN FULL, attributed to themselves — the ceiling permits exactly the amount taken and no more');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000c01'$$,
  'repair/step one: and the payment itself moves paid -> refunded, which is one of the two edges out of paid the transition rule allows');

select is(
  (select periods_granted::text || '/' || (ends_on - starts_on)::text || '/' || status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b44'::uuid),
  '10/300/active',
  'repair: AND THE MEMBERSHIP HAS NOT MOVED. Still ten periods, still 300 days, still live at the gate — refunded money counts toward the total exactly as paid money does, so a refund reverses the money and not what the money bought. This is why the requirement says cancel as well, and it is the sentence a holdout author had to measure once already for GL045');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'sold at the wrong price; refunded and re-sold' where id = '220000ff-0022-4000-8000-600000000b44'$$,
  'repair/step two: the membership is cancelled. A status is not a term of what the member owes, so it stays writable after money has arrived — which is the one property that makes this whole remedy available at all');

select ok(
  (select status = 'cancelled' and price_paise = 10000 and periods_granted = 10
      and ends_on = (select today from gym_today where org_key = 'A') + 300
     from public.memberships where id = '220000ff-0022-4000-8000-600000000b44'::uuid),
  'repair/step two: cancelled, with the wrong price and the wrong dates STILL ON THE ROW. The remedy retires the mis-sale, it does not erase it: the sale, the money and the refund all stay on the books, which is the difference between an audit trail and an edit');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000000b45', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b44', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key = 'A'), (select today from gym_today where org_key = 'A'), 100000, 'INR')$$,
  'repair/step three: THE DESK sells the same member a new membership at the plan''s own price. Two things had to be true for this line to run and neither is decoration — the cancelled row is outside `memberships_member_id_live_key`, so the member may hold a live membership again, and selling at list is front-desk work, so the gym is not left needing a manager for the last step');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000c02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000b44', '220000ff-0022-4000-8000-600000000b45', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'repair/step three: and the member pays the Rs.1,000 they actually owe, against a membership that says so');

select is(
  (select periods_granted::text || '/' || (ends_on - starts_on)::text || '/' || price_paise::text from public.memberships where id = '220000ff-0022-4000-8000-600000000b45'::uuid),
  '1/30/100000',
  'repair: ONE period, thirty days, at the list price. The 300 days did not follow the member across, the refunded money did not score against the new row, and the member is where an honest sale would have put them — this is the assertion that says the requirement''s remedy is a real path rather than a sentence, and it is the whole reason this section exists');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000b44', '220000ff-0022-4000-8000-600000000b45', now(), 'qr', '220000ff-0022-4000-8000-900000000c01')$$,
  'repair: and the member the gym mis-sold, refunded, cancelled and re-sold walks through the gate. The repair produced a membership that WORKS, not one whose columns merely read correctly — and the gate is the only place that distinction is visible to the member');

set local role postgres;
select set_config('request.jwt.claims', '', true);



-- ---------------------------------------------------------------------------
-- 22. SEVENTH-SESSION EXTENSION (round thirteen), written blind by yet
-- another author against the payment-record spec's newest requirement,
-- "Money does not extend a membership that has been retired", and against
-- nothing else: no migration dated later than this file's own header names,
-- no function body for app.grant_periods / app.extend_membership_on_payment,
-- and not supabase/tests/22_payment_record.sql, whose round-thirteen battery
-- is being written in parallel by a different author. Everything structural
-- below (the five members of `membership_status`, the CHECK that decides
-- which of them may hold null dates, the partial unique index that decides
-- which of them are "live", the trigger NAMES on payments and memberships)
-- came from the live Cloud catalogue.
--
-- The headline — a payment naming a `cancelled` membership is recorded and
-- does not move that membership — is the visible suite's to prove. This
-- section takes the seams around it.
--
--   * THE BOUNDARY OF "RETIRED", VALUE BY VALUE. `membership_status` has
--     FIVE members, not two: pending, active, frozen, expired, cancelled.
--     The requirement names two of them and is silent on the other three, so
--     each of the three is asserted on the PERMITTED side here, hard:
--     `frozen` is a paused live membership and must still take money;
--     `active` obviously must; and `pending` must, because the sibling
--     requirement one heading down REQUIRES it to ("a payment against a
--     membership with no dates grants it a period ... and it SHALL be made
--     active"). A fix written as "extend only when status = 'active'" passes
--     every refusal assertion in this section and in the visible suite, and
--     breaks that sibling outright. Three of the last rounds shipped exactly
--     that shape of over-correction.
--
--   * THE TWO REQUIREMENTS CANNOT OVERLAP, and that is a structural fact
--     rather than a hope: `memberships_dated_unless_pending_chk` permits
--     null dates ONLY for `pending`, so a `cancelled` or `expired` row can
--     never be dateless and the "grant it a period from the gym's today"
--     rule can never fire on a retired row. Asserted, because an
--     implementation that orders the two checks the wrong way round is only
--     safe BECAUSE of that CHECK, and a later migration relaxing it would
--     silently re-open the harm.
--
--   * STATUS CHANGING AROUND THE MONEY, in every shape a single INSERT is
--     not. The extension runs from two STATEMENT-level triggers with
--     transition tables (payments_extend_membership_insert and
--     payments_extend_membership_update), which is precisely where a guard
--     written on the INSERT path alone leaks: a payment left `created` while
--     the membership is still live, the membership then cancelled, and the
--     payment walked to `paid` afterwards. Also cancel-between-two-payments,
--     cancel-inside-the-same-statement (a data-modifying CTE), INSERT ...
--     ON CONFLICT DO UPDATE, MERGE, a multi-row INSERT and a multi-row
--     UPDATE each carrying one live membership and one retired one, two
--     payments naming the same retired membership in one statement, and a
--     `created` payment REPOINTED from the member's live membership onto
--     their retired one before being paid — which is the repair path's own
--     two-membership shape, reached without ever naming the retired row at
--     insert time.
--
--   * WHAT MUST NOT REGRESS. Nothing here reverses history: a period granted
--     while the membership was live stays granted when it is cancelled a
--     statement later. A refund against a payment whose membership has since
--     been cancelled still works and is still bounded by GL036. The receipt
--     counter still advances for a payment that granted nothing — the money
--     changed hands and the receipt is the gym's record of it, which is the
--     requirement's own reason for recording rather than refusing.
--
--   * THE GATE, not the column. A cancelled membership whose `ends_on` is
--     ten days in the future must not admit its member (ADR-084), before the
--     payment and after it. That is the consequence the requirement's own
--     narrative turns on — "the member stays refused at the gate because the
--     gate reads status" — and it is asserted as a refused check-in rather
--     than as a status column reading 'cancelled'.
--
-- TWO THINGS THIS SECTION REPORTS RATHER THAN RESOLVES, both measured live
-- on 2026-09-09 before the fix and both written up in the round-thirteen
-- report:
--
--   1. THE MONEY IS REFUSED A GRANT BUT IS NOT DETACHED. The requirement
--      stops the retired membership growing; it says nothing about what
--      becomes of money already banked against it. `cancelled -> active` is
--      an ordinary permitted UPDATE (this file's own section 21b turns on
--      status staying writable after money has arrived), and the granting
--      rule is CUMULATIVE. So the refusal is deferred, not durable: revive
--      the row and the very next payment — one paisa is enough — cashes in
--      every period the refused money bought. 22h stages that sequence and
--      bounds it to the only two answers, exactly as section 6 does for the
--      refunded-mid-sum question the spec also leaves open.
--
--   2. ADR-064/075 SAYS NOTHING IN THIS PRODUCT EVER WRITES `expired`, and
--      the requirement nonetheless names it. Measured: an ordinary
--      FRONT-DESK session can set a membership to `expired` today, with
--      nothing raised (22c). So the branch is reachable and worth testing —
--      but its only door is an unguarded status write, which is the same
--      door, one table over, that this whole requirement exists to close.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

create function pg_temp.h22r13_shape(mid text) returns text
language plpgsql as $fn$
declare r text;
begin
  execute format(
    'select status::text || %L || coalesce(starts_on::text, ''-'') || %L || coalesce(ends_on::text, ''-'') || %L || periods_granted::text from public.memberships where id = %L',
    '/', '..', '/', mid) into r;
  return coalesce(r, 'NO ROW');
exception when others then
  return 'ERR:' || sqlstate;
end
$fn$;

grant execute on function pg_temp.h22r13_shape(text) to public;

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000000d01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-200000000001'::uuid, 'h22-r13-gate-token-hash',
   now() + interval '1 day', '220000ff-0022-4000-8000-300000000001'::uuid);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-500000000d' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  '220000ff-0022-4000-8000-200000000001'::uuid,
  'H22 R13 Member ' || f.sfx,
  '+9192201300' || f.sfx
from (values ('01'),('02'),('03'),('04'),('05'),('06'),('07'),('08'),('09'),('10'),
             ('11'),('12'),('13'),('15'),('16'),('17'),('18'),('19'),('20'),('21'),
             ('22'),('23'),('24')) as f(sfx);

-- One membership per member at the plan's own list price, in every status
-- the enum has. d14 deliberately belongs to member d13, who therefore holds
-- a retired membership AND a live one — the repair path's own shape, and the
-- only shape in which the repointing probe (22e7) means anything.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000000d01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d01'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d02'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d02'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired',   (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d03'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d03'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'frozen',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d04'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d04'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d05'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d05'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d06'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d06'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   null, null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d07'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d07'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d08'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d08'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d09'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d09'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d10'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d10'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d11'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d11'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d12'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d12'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d13'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d13'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 20, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d14'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d13'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d15'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d15'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d16'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d16'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d17'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d17'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d18'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d18'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d19'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d19'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d20'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d20'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d21'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d21'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d22'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d22'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d23'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d23'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000000d24'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000d24'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 22a. The boundary, established from the catalogue rather than assumed, and
-- the structural reason the two requirements can never collide on one row.
-- ---------------------------------------------------------------------------

select is(
  (select string_agg(v::text, ',' order by v::text) from unnest(enum_range(null::public.membership_status)) v),
  'active,cancelled,expired,frozen,pending',
  'r13/boundary: `membership_status` has FIVE members. The requirement names two of them as retired and is silent on the other three, so the three silent ones are asserted on the permitted side below. If a later migration adds a sixth — `lapsed`, `suspended`, anything — this assertion fails FIRST and says so, before a status nobody has decided about starts quietly taking money');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'cancelled', cancelled_at = now() where id = '220000ff-0022-4000-8000-600000000d06'$q$),
  'r13/boundary: a DATELESS membership cannot be cancelled — `memberships_dated_unless_pending_chk` permits null dates only for `pending`. This is the structural fact that keeps this requirement and its sibling ("a payment against a membership with no dates grants it a period, from the gym''s today") from ever applying to the same row, and it is asserted rather than assumed because an implementation is only safe from that collision BECAUSE of the CHECK');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d06'),
  'pending/-..-/0',
  'r13/boundary: and the dateless row is untouched by the attempt — still pending, still dateless, still nothing granted');

select ok(
  pg_temp.h22r8_refused($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, currency) values ('220000ff-0022-4000-8000-600000000d30', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d21', '220000ff-0022-4000-8000-400000000001', 'cancelled', 100000, 'INR')$q$),
  'r13/boundary: nor can a dateless retired membership be CREATED. The same CHECK closes the creation door, which matters because creation is the door this phase has already had to close twice on other columns');

-- ---------------------------------------------------------------------------
-- 22b. The refused side, `cancelled`: recorded and receipted, and the row
-- does not move. Measured live before the fix at ends_on T+10 -> T+40,
-- periods 0 -> 1, on a row the gate refuses either way.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d01', '220000ff-0022-4000-8000-600000000d01', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/cancelled: the payment is RECORDED, not refused. That is deliberate and the requirement says why — the money did change hands, and refusing after the fact leaves cash in a drawer with nothing to show for it. An implementation that closes this hole by raising is wrong in the other direction, and this line is what says so');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d01'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/cancelled: and the retired membership has not moved a day or a period. MEASURED BEFORE THE FIX: ends_on went T+10 -> T+40 and periods_granted 0 -> 1, on a row whose member the gate refuses either way — money banked, receipt issued, nothing bought');

select ok(
  (select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000d01'::uuid) is not null,
  'r13/cancelled: the receipt is still issued. Granting nothing is not the same as taking nothing, and a fix that suppresses the receipt along with the extension takes the gym''s own record of the cash away with it');

select is(
  left((select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000d01'::uuid), 7),
  (select fy from gym_today where org_key = 'A'),
  'r13/cancelled: and it is a real receipt from the gym''s own financial-year counter, not a placeholder — the same allocator every other payment in this file goes through');

-- ---------------------------------------------------------------------------
-- 22c. The refused side, `expired` — the status ADR-064/075 says nothing in
-- this product ever writes. It is nonetheless reachable, and the second
-- assertion here is the one that measures that rather than assuming it.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d02', '220000ff-0022-4000-8000-600000000d02', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/expired: a payment naming an `expired` membership is recorded too');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d02'),
  'expired/' || ((select today from gym_today where org_key='A') - 40)::text || '..' || ((select today from gym_today where org_key='A') - 10)::text || '/0',
  'r13/expired: and does not move it. MEASURED BEFORE THE FIX the lapsed row was re-dated to the gym''s TODAY + 30 rather than to its own old ends_on + 30, so an `expired` row does not merely creep — it is handed a fresh full period, which is the renewal path arriving at a membership nobody renewed');

select lives_ok(
  $$update public.memberships set status = 'expired' where id = '220000ff-0022-4000-8000-600000000d04'$$,
  'r13/expired/reachability: an ordinary FRONT-DESK session can write `expired` directly, today, with nothing raised. ADR-064/075 say nothing in this product writes that status and liveness is derived from dates — true of the product, NOT true of the database. So the requirement''s `expired` branch is reachable, and its only door is an unguarded status write. Reported, not resolved: closing that door is a memberships-status question, not a payments one');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d04'),
  'expired/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/expired/reachability: and it landed — a membership live until T+10 now carries the one status the product claims never to write, from the desk, in one statement');

-- ---------------------------------------------------------------------------
-- 22d. THE PERMITTED SIDE, AS HARD AS THE REFUSED. A fix that is too broad
-- passes every refusal above; this phase has shipped that shape three times.
-- `frozen` is a PAUSED LIVE membership, `pending` is how a membership that
-- was sold but not yet paid for gets activated at all, and `active` is the
-- ordinary case. All three must still take money.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d03', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d03', '220000ff-0022-4000-8000-600000000d03', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/frozen: a member on a PAUSE pays for another month');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d03'),
  'frozen/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/frozen: and it grants a period, staying frozen. ROUND-TWENTY RECONCILIATION: the fully dated row has zero granted periods, so its past start and typed end are replaced by today and today plus one sold period. `frozen` is inside the live partial unique index alongside `active` — it is a paused membership, not a retired one — so a guard reading "grant only to active" still fails this permitted case');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d05', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d05', '220000ff-0022-4000-8000-600000000d05', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/pending-dated: a membership sold with dates but not yet paid for takes its money');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d05'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/pending-dated: and it grants AND activates. ROUND-TWENTY RECONCILIATION: both dates are present and no period was previously granted, so the first bought span runs from today for one sold period. Activation remains required; this fully dated case is distinct from both half-dated shapes deferred under OPEN-026');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d06', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d06', '220000ff-0022-4000-8000-600000000d06', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/pending-dateless: and the DATELESS pending membership — the "sold but not yet paid for" shape after ADR-083 — takes its money too');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d06'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/pending-dateless: dated from the gym''s own today for the plan''s duration, and made active. This is the assertion a "retired means anything that is not active" fix breaks hardest, because the row it has to date is by definition not active yet');

-- ---------------------------------------------------------------------------
-- 22e. STATUS CHANGING AROUND THE MONEY. The extension runs from two
-- STATEMENT-level triggers with transition tables — one on INSERT, one on
-- UPDATE — so every shape below is a distinct arrival at the same rule, and
-- a guard placed on one path leaks through the others.
-- ---------------------------------------------------------------------------

-- 22e1. Cancel BETWEEN two payments. The first must stand; the second must
-- not land; and the cancel itself must reverse nothing.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d07', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d07', '220000ff-0022-4000-8000-600000000d07', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/between: the member pays while the membership is live');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d07'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/between: the first grant sets one sold period from today. ROUND-TWENTY RECONCILIATION: this fixture carried dates but no previously granted period');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r13 between' where id = '220000ff-0022-4000-8000-600000000d07'$$,
  'r13/between: the gym then cancels it');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d07'),
  'cancelled/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/between: AND NOTHING IS REVERSED. The period the member paid for while the membership was live stays granted and the dates stay where the first grant put them. ROUND-TWENTY RECONCILIATION changes that earlier baseline, not this cancellation invariant: retiring a membership does not unwind its granted history');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d08', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d07', '220000ff-0022-4000-8000-600000000d07', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/between: a second payment then names the now-retired membership — the desk repeating what worked yesterday');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d07'),
  'cancelled/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/between: and it changes nothing. Same row, same member, same amount, same desk — only the membership status differs. ROUND-TWENTY RECONCILIATION retains the corrected first-grant baseline; the payment after cancellation still grants nothing');

-- 22e2. Cancel AFTER the payment, in the same transaction, in that order.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d09', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d08', '220000ff-0022-4000-8000-600000000d08', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/after: money first');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now() where id = '220000ff-0022-4000-8000-600000000d08'$$,
  'r13/after: cancel second, same transaction');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d08'),
  'cancelled/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/after: the grant stands. ROUND-TWENTY RECONCILIATION: the first grant on this fully dated zero-period fixture sets today through today plus one sold period. Cancellation later in the same transaction must preserve those dates and that count');

-- 22e3. THE LEAK A GUARD ON `INSERT` ALONE LEAVES: created while live,
-- cancelled, then walked to `paid`. The extension has its own AFTER UPDATE
-- statement trigger, so this is a second, independent arrival at the rule.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d10', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d09', '220000ff-0022-4000-8000-600000000d09', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/created-then-paid: a payment is opened against a LIVE membership and left at `created` — the ordinary shape of a card payment waiting on the provider');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now() where id = '220000ff-0022-4000-8000-600000000d09'$$,
  'r13/created-then-paid: the membership is cancelled while the payment is still open');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000d10'$$,
  'r13/created-then-paid: and the payment is then settled');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d09'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/created-then-paid: the retired membership does not move. THIS IS THE ASSERTION A GUARD WRITTEN ON THE INSERT PATH ALONE FAILS — the payment never named a retired membership at insert time, and the grant happens on the UPDATE trigger, which is a different statement, a different transition table and a different code path');

select ok(
  (select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000d10'::uuid) is not null,
  'r13/created-then-paid: and the receipt is still allocated when it settles — refusing the extension must not cost the payment its number, which is the one thing in this system that can never be re-issued');

-- 22e4. Cancel INSIDE the same statement, via a data-modifying CTE. The
-- extension trigger is per STATEMENT, so this is the one shape where the
-- membership's status changes and the payment arrives with no statement
-- boundary between them.
select lives_ok(
  $$with c as (
      update public.memberships set status = 'cancelled', cancelled_at = now()
       where id = '220000ff-0022-4000-8000-600000000d10' returning id, tenant_id, member_id)
    insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    select '220000ff-0022-4000-8000-700000000d11', c.tenant_id, c.member_id, c.id, 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001' from c$$,
  'r13/cte: the cancel and the payment arrive in ONE statement, the payment naming the very row the CTE retired');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d10'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/cte: and the row is retired and unmoved. A guard that reads the membership from the pre-statement snapshot, or from OLD rather than from the table, sees `active` here and lets it through');

select ok(
  (select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000d11'::uuid) is not null,
  'r13/cte: the payment is still recorded and receipted out of the same statement');

-- 22e5. INSERT ... ON CONFLICT DO UPDATE. Postgres fires the AFTER INSERT
-- and AFTER UPDATE statement triggers separately for one such statement,
-- with separate transition tables — so a rule that holds on both paths
-- individually can still be reached twice, or on the wrong one, here.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, idempotency_key, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d12', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d11', '220000ff-0022-4000-8000-600000000d11', 100000, 'INR', 'cash', 'created', 'h22-r13-upsert', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/upsert: an open payment against a cancelled membership carries an idempotency key');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, idempotency_key, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d13', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d11', '220000ff-0022-4000-8000-600000000d11', 100000, 'INR', 'cash', 'created', 'h22-r13-upsert', '220000ff-0022-4000-8000-300000000001')
    on conflict (tenant_id, idempotency_key) where idempotency_key is not null
    do update set status = 'paid', paid_at = now()$$,
  'r13/upsert: the retry lands as INSERT ... ON CONFLICT DO UPDATE and settles it — the exact statement an idempotent payments endpoint sends');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d11'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/upsert: and the retired membership does not move. One statement, two statement-level trigger firings, one row — the shape most likely to be missed by a fix tested only against a plain INSERT and a plain UPDATE');

-- 22e6. MERGE — a third syntax onto the same triggers, available since
-- Postgres 15 and live here on 17.6.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d14', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d12', '220000ff-0022-4000-8000-600000000d12', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/merge: another open payment against another cancelled membership');

select lives_ok(
  $$merge into public.payments p
      using (select '220000ff-0022-4000-8000-700000000d14'::uuid as id) s
      on p.id = s.id
      when matched then update set status = 'paid', paid_at = now()$$,
  'r13/merge: settled by MERGE rather than UPDATE');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d12'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/merge: and the retired membership does not move. MERGE routes through the same AFTER UPDATE statement trigger; a guard implemented anywhere but in the shared rule would have to be repeated per syntax, and this is the syntax nobody remembers');

-- 22e7. THE REPAIR PATH'S OWN SHAPE, WITHOUT EVER NAMING THE RETIRED ROW AT
-- INSERT TIME. Member d13 holds a retired membership and a live one, which
-- is exactly what the phase's prescribed repair leaves behind. A payment is
-- opened against the live one, repointed onto the retired one while it is
-- still editable (the freeze only bites once a row has been paid), and then
-- settled.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d15', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d13', '220000ff-0022-4000-8000-600000000d14', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/repoint: a payment is opened against the member''s LIVE membership');

select lives_ok(
  $$update public.payments set membership_id = '220000ff-0022-4000-8000-600000000d13' where id = '220000ff-0022-4000-8000-700000000d15'$$,
  'r13/repoint: and repointed onto the same member''s RETIRED one while it is still a working document. GL042 is satisfied — the member matches, which is all it checks — and the payment has never been paid, so nothing is frozen yet');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000d15'$$,
  'r13/repoint: then settled');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d13'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 40)::text || '..' || ((select today from gym_today where org_key='A') - 20)::text || '/0',
  'r13/repoint: the retired membership does not move. MEASURED BEFORE THE FIX it took a full fresh period dated from the gym''s today — a lapsed, cancelled row made to look renewed, by a route where no single statement ever both names a retired membership and pays it');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d14'),
  'active/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/repoint: and the LIVE membership it was opened against gains nothing either — the payment no longer names it. Both halves matter: a fix that redirected the money to the live row would be inventing a grant nobody recorded');

-- 22e8. A multi-row INSERT carrying one live membership and one retired one.
-- The rule is per payment; the statement must not be refused wholesale and
-- must not treat the two rows alike.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values
     ('220000ff-0022-4000-8000-700000000d16', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d15', '220000ff-0022-4000-8000-600000000d15', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
     ('220000ff-0022-4000-8000-700000000d17', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d16', '220000ff-0022-4000-8000-600000000d16', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/multi-insert: two payments in ONE statement, one naming a live membership and one naming a retired one. The statement itself is not refused — the requirement records both');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d15'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/multi-insert: the LIVE one receives its first period. ROUND-TWENTY RECONCILIATION sets its fully dated zero-period span from today. A retired membership elsewhere in the same statement must still not suppress this legitimate grant');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d16'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/multi-insert: and the RETIRED one is not, out of the same statement. The pair is the discriminator: either assertion alone is passed by a fix that is wrong in one direction');

-- 22e9. The same split, on the UPDATE path.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, recorded_by_staff_id) values
     ('220000ff-0022-4000-8000-700000000d18', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d17', '220000ff-0022-4000-8000-600000000d17', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001'),
     ('220000ff-0022-4000-8000-700000000d19', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d18', '220000ff-0022-4000-8000-600000000d18', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/multi-update: two open payments, one against a live membership and one against a retired one');

select lives_ok(
  $$update public.payments set status = 'paid', paid_at = now()
     where id in ('220000ff-0022-4000-8000-700000000d18', '220000ff-0022-4000-8000-700000000d19')$$,
  'r13/multi-update: settled together in one UPDATE — the batch a reconciliation job sends');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d17'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r13/multi-update: the live one receives its first period. ROUND-TWENTY RECONCILIATION sets the fully dated zero-period span from today; the payment UPDATE must still grant independently of the retired membership in the same statement');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d18'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/multi-update: the retired one is not — the same split proven on the second of the two statement triggers, because a guard added to only one of them is exactly the defect this requirement exists to answer, one table over');

-- 22e10. Two payments naming the SAME retired membership in one statement.
-- The cumulative rule sums per membership, so this is where a per-statement
-- aggregate that forgets the status once per group rather than once per row
-- would show up.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values
     ('220000ff-0022-4000-8000-700000000d20', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d19', '220000ff-0022-4000-8000-600000000d19', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
     ('220000ff-0022-4000-8000-700000000d21', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d19', '220000ff-0022-4000-8000-600000000d19', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/same-membership-twice: two full months paid at once, both naming the same retired membership');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d19'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/same-membership-twice: and nothing moves. MEASURED BEFORE THE FIX this took the row to two periods and sixty days in one statement — the harm is not bounded by one period per payment, it is bounded by whatever the desk types');

select is(
  (select count(distinct receipt_number)::text from public.payments
     where membership_id = '220000ff-0022-4000-8000-600000000d19'::uuid and receipt_number is not null),
  '2',
  'r13/same-membership-twice: both payments still take their own receipt number, and the two differ. The counter is per payment, not per grant, and nothing about refusing an extension may collapse two receipts into one');

-- ---------------------------------------------------------------------------
-- 22f. WHAT MUST NOT REGRESS around a payment that granted nothing: the
-- counter, the refund path, and the ceiling that bounds it.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d22', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d20', '220000ff-0022-4000-8000-600000000d20', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/counter: a payment against a retired membership');

select ok(
  (select next_number from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000001'::uuid
       and kind = 'receipt'
       and financial_year = (select fy from gym_today where org_key = 'A'))
  > (select split_part(receipt_number, '/', 2)::int from public.payments
       where id = '220000ff-0022-4000-8000-700000000d22'::uuid),
  'r13/counter: THE COUNTER STILL ADVANCED. Section 22 spends receipt numbers on payments that grant nothing, and it must — the requirement records the money precisely so the gym has a receipt for it. A fix that short-circuits before the allocator leaves cash with no number against it, which is the failure this requirement was written to avoid, arrived at from the other side');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000d01', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000d22', 'refund', 100000, 'INR', 'h22 r13 paid against a retired membership by mistake', '220000ff-0022-4000-8000-300000000002')$$,
  'r13/refund: and the money paid against a retired membership can still be GIVEN BACK. This is the only remedy the desk has once the money is banked and nothing was bought, so it had better work');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, currency, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000d02', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000d22', 'refund', 1, 'INR', 'h22 r13 one paisa past the ceiling', '220000ff-0022-4000-8000-300000000002')$$,
  'GL036'::char(5), null,
  'r13/refund: and GL036 still bounds it to the paise the payment actually took. A payment that granted nothing is not a payment that may be over-refunded — the ceiling is the amount, not the value delivered');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d20'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/refund: and the membership is where it was through all of it — paid, refunded, still retired, still unmoved');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d23', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d21', '220000ff-0022-4000-8000-600000000d21', 100000, 'INR', 'cash', 'created', '220000ff-0022-4000-8000-300000000001')$$,
  'r13/unpaid: an OPEN payment against a retired membership is recorded like any other');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d21') || ' rcpt=' ||
    coalesce((select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000000d23'::uuid), 'null'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0 rcpt=null',
  'r13/unpaid: nothing granted and no receipt — because it has not been PAID, not because the membership is retired. The two reasons produce the same row and only the paid case above tells them apart, which is why both are asserted');

-- ---------------------------------------------------------------------------
-- 22g. THE GATE. The requirement's whole narrative is that the member stays
-- refused while the row grows, so the consequence is asserted where the
-- member actually feels it rather than on the status column.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000d22', '220000ff-0022-4000-8000-600000000d22', now(), 'qr', '220000ff-0022-4000-8000-900000000d01')$$,
  null::char(5), null,
  'r13/gate: a CANCELLED membership whose ends_on is ten days away does not admit its member. The dates say live; the gate reads status (ADR-084); the member is turned away');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d24', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d22', '220000ff-0022-4000-8000-600000000d22', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/gate: the member then pays a full month against that very membership');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000d22', '220000ff-0022-4000-8000-600000000d22', now(), 'qr', '220000ff-0022-4000-8000-900000000d01')$$,
  null::char(5), null,
  'r13/gate: AND IS STILL TURNED AWAY. This is the harm in one line: before the fix the row''s ends_on had just been pushed another month out and the member was refused at the door anyway. The money bought a date on a row nobody reads and a receipt that says otherwise');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d22'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/gate: and after the fix the row does not even pretend — refused at the gate AND unmoved on the books, which at least agree with each other');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000000d23', '220000ff-0022-4000-8000-600000000d23', now(), 'qr', '220000ff-0022-4000-8000-900000000d01')$$,
  'r13/gate: while a member on a LIVE membership walks straight through the same gate on the same QR session. The refusal above is the status, not the fixture');

-- ---------------------------------------------------------------------------
-- 22h. THE ROUTE THE REQUIREMENT DOES NOT CLOSE — SIDED IN ROUND EIGHTEEN,
-- having been staged and reported here for five rounds.
--
-- As written, this subsection measured that round thirteen refused the GRANT
-- without detaching the MONEY: the granting rule is cumulative over a
-- membership's payments and `cancelled -> active` was an ordinary permitted
-- UPDATE, so the refusal was deferred rather than durable — revive the row and
-- the next payment, one paisa, cashed in every period the refused money had
-- bought. It bounded the outcome to two answers and reported which happened.
--
-- The membership-lifecycle requirement (OPEN-030) answers it by removing the
-- revival, so the three assertions that turned on `cancelled -> active` being
-- permitted are re-sided here rather than deleted: the same fixture, the same
-- ids, the same Rs.3,000 and the same one paisa, with the revival now refused
-- and the deferral therefore durable. THIS IS A FIXTURE REPAIR AND A RE-SIDING,
-- NOT A NEW BATTERY — the count is unchanged at six and section 25 is where
-- round eighteen is actually tested. What the money's stranding then obliges
-- is 25a's chain: it is refundable in full, and that is the only remedy.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d25', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d24', '220000ff-0022-4000-8000-600000000d24', 300000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/revival: three months'' fee is banked against a retired membership in one payment');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d24'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/revival: and grants nothing now. MEASURED BEFORE THE FIX: three periods and ninety days, on a cancelled row, from one statement');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000000d24'$q$),
  'r13/revival: THE ROW CANNOT BE UN-CANCELLED. (Asserted through the code-agnostic probe rather than section 24''s GL-only one, which does not exist yet this far up the file; section 25 asserts the code.) Re-sided in round eighteen: this line asserted for five rounds that `cancelled -> active` was permitted from the front desk with nothing raised, which is precisely what a critic measured and OPEN-030 recorded. The membership-lifecycle requirement makes retirement terminal, so the deferral this subsection reported is now durable');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d24'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/revival: and the refusal left it exactly as it was — still cancelled, still on its own dates, still granted nothing');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000d26', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000d24', '220000ff-0022-4000-8000-600000000d24', 1, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r13/revival: and ONE PAISA arrives against the revived row');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d24'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r13/revival: and the paisa buys nothing either. This assertion used to bound the outcome to T+10 (the money DETACHED) or T+100 (merely DEFERRED — one paisa cashing in three months) and let the diag report which. Round eighteen decides it: the revival never comes, so the banked Rs.3,000 stays refused permanently rather than waiting for a door that no longer opens');

select diag(
  format('r13/revival OBSERVED after round eighteen: membership d24 is %s, having taken Rs.3,000 while cancelled, been refused a revival, and then taken one paisa more. The route this subsection reported for five rounds is closed at the cause. What it hands on is the consequence rather than the exploit: Rs.3,000 of the member''s money is now permanently unable to buy anything on this row, which is exactly the stranding the membership-lifecycle spec''s second requirement answers with "refundable in full". Section 25a runs that answer end to end; if any link of it breaks, this money is simply gone.',
    pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000000d24')));

set local role postgres;
select set_config('request.jwt.claims', '', true);


-- ---------------------------------------------------------------------------
-- 23. ROUND SIXTEEN, GL037 — THE EQUAL WRITE. Gym A.
--
-- Section 5 of this file tests the counter with a decrease, a +1, a +25 and a
-- delete. The visible suite tests a decrease, a +5, a +1 and a delete.
-- NEITHER EVER WROTE `next_number` TO THE VALUE IT ALREADY HELD. The
-- requirement — "SHALL refuse any change to document_counters.next_number
-- that does not increase it" — covers standing still as squarely as it covers
-- going backwards, and `app.enforce_counter_monotonic()` refuses on `<=`, not
-- on `<`. Both suites had a hole exactly where that assertion should be.
--
-- The hole was found the expensive way, by a critic reading a real defect
-- rather than by either suite: a seed block written as `greatest(current,
-- new)` fires its DO UPDATE arm unconditionally, so the second time it ran —
-- once the counter had caught up — it wrote the value back unchanged, GL037
-- refused it, and the seed died. That would have turned CI red the first time
-- anyone took a payment at the desk. One assertion would have caught it.
--
-- WRITTEN BY THE SAME AUTHOR AS THE VISIBLE SUITE'S SECTION 24, which is a
-- deliberate, recorded deviation from the two-author arrangement (AGENTS.md
-- hard rule 10 / ADR-059) and the SECOND time this phase — the round-twelve
-- sections were the first. It is stated here rather than left to be inferred.
-- The reason it was traded: there is no design to converge on. The rule is
-- already implemented and already has full batteries in both suites; what is
-- missing is one assertion SHAPE, named precisely by the defect that exposed
-- it, and a second author reading the same sentence would write the same four
-- statements. Independence buys convergence on an open question, and there is
-- no open question here. Being explicit about that is the point of the note.
--
-- THE DISTINCTION THE SECTION EXISTS TO DRAW, and the whole lesson of the
-- defect: two upsert shapes differ by one clause and by everything else.
--
--   do update set next_number = greatest(document_counters.next_number,
--                                        excluded.next_number)
--     -- the UPDATE ALWAYS fires. Caught up, greatest() writes the row's own
--     -- value back, and GL037 REFUSES it. "Never go backwards" expressed as
--     -- a value is not the same as expressed as a condition.
--
--   do update set next_number = excluded.next_number
--     where excluded.next_number > document_counters.next_number
--     -- the UPDATE DOES NOT FIRE at all when the guard is false. No row
--     -- touched, no trigger, no exception, counter unmoved.
--
-- "Refused" and "did not fire" are the two outcomes of offering a counter a
-- value it already has, and they are indistinguishable by reading the counter
-- afterwards — which is why the zero-rows assertion below exists and why the
-- counter reads alone would not have caught the defect either.
--
-- The one-less and one-more boundaries are NOT restated: section 5 above
-- already asserts a decrease refused and a +1 and +25 permitted on this same
-- rule and this same gym. What is added is the missing middle, in each shape
-- it actually arrives in, plus the guarded form firing when it SHOULD, so
-- none of the "no update" assertions could be satisfied by a statement that
-- is simply inert (ADR-078).
--
-- The counter used is a fresh `invoice` row rather than gym A's receipt row,
-- which by this point in the file is wherever ~700 assertions of real payment
-- traffic have left it. A second row on the same tenant and financial year is
-- also what the multi-row statement at the end needs, and `invoice` is a kind
-- neither suite uses anywhere else.
-- ---------------------------------------------------------------------------

insert into public.document_counters (tenant_id, kind, financial_year, next_number)
values ('220000ff-0022-4000-8000-100000000001', 'invoice',
        (select fy from gym_today where org_key = 'A'), 7);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.document_counters set next_number = next_number
      where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice'$$,
  'GL037'::char(5), null,
  'r16/equal: the plainest equal write — next_number set to the value it already holds — is refused with GL037. Neither an increase nor a decrease, and "only ever counts up" excludes standing still');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  7,
  'r16/equal: and the counter is exactly where it was — a refusal that still moved the value would be worse than no refusal at all');

select throws_ok(
  $$insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 7)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = greatest(document_counters.next_number, excluded.next_number)$$,
  'GL037'::char(5), null,
  'r16/equal: THE SHAPE THE DEFECT ARRIVED IN. insert … on conflict … do update set next_number = greatest(current, excluded), with the row already AT the excluded value, is refused with GL037 — greatest() returns the current value, the DO UPDATE arm fires anyway, and the write is equal');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  7,
  'r16/equal: and the counter is still 7 after the refused greatest() upsert');

select throws_ok(
  $$insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 3)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = greatest(document_counters.next_number, excluded.next_number)$$,
  'GL037'::char(5), null,
  'r16/equal: the same greatest() upsert offered a value the row is already PAST is refused with GL037 too — the steady state of a re-run seed. The refusal is for an EQUAL write, not for a decrease caught by accident: greatest() never offers the lower number');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  7,
  'r16/equal: and the counter is still 7 after that one as well');

select lives_ok(
  $$insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 7)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = excluded.next_number
      where excluded.next_number > document_counters.next_number$$,
  'r16/guard: THE PERMITTED NEIGHBOUR. One clause different — the DO UPDATE carries its own WHERE — and offering the row the value it already holds is not refused, because no UPDATE is attempted and there is nothing for GL037 to judge');

with u as (
  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 7)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = excluded.next_number
    where excluded.next_number > document_counters.next_number
  returning 1
)
select is(
  (select count(*)::int from u), 0,
  'r16/guard: and it touched NO ROW AT ALL — a data-modifying CTE returns one row per row actually written, and it returned none. This is the assertion that separates "did not fire" from "was refused"; the counter reads cannot, because both leave it at 7. Running the statement a second time here is itself the proof that it is a no-op');

set local role postgres;

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  7,
  'r16/guard: the counter is unmoved after both no-op upserts, read outside the session that ran them');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 3)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = excluded.next_number
      where excluded.next_number > document_counters.next_number$$,
  'r16/guard: the guarded upsert offered a value BELOW the row''s is also not refused — a decrease that never fires is not a decrease, so a seed that has fallen behind the live counter is silent rather than fatal');

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  7,
  'r16/guard: and the counter did not move BACKWARDS either — the guard protects the value as well as the statement, which a bare do-update would not');

select lives_ok(
  $$insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values ('220000ff-0022-4000-8000-100000000001', 'invoice', (select fy from gym_today where org_key = 'A'), 9)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = excluded.next_number
      where excluded.next_number > document_counters.next_number$$,
  'r16/guard: THE OTHER DIRECTION (ADR-078). Offered a HIGHER value the same statement fires and is permitted — everything above would be green for a guarded upsert that never wrote anything under any circumstances, which is a broken seed that reports success');

set local role postgres;

select is(
  (select next_number from public.document_counters where tenant_id = '220000ff-0022-4000-8000-100000000001' and kind = 'invoice' and financial_year = (select fy from gym_today where org_key = 'A')),
  9,
  'r16/guard: and it landed on exactly 9 — the guarded form really does advance the counter, so the four no-op assertions are about a working statement rather than an inert one');

create temp table h22r16_before as
  select kind, next_number from public.document_counters
   where tenant_id = '220000ff-0022-4000-8000-100000000001'
     and financial_year = (select fy from gym_today where org_key = 'A');
grant select on h22r16_before to public;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.document_counters
       set next_number = case when kind = 'receipt' then next_number + 1 else next_number end
     where tenant_id = '220000ff-0022-4000-8000-100000000001'
       and financial_year = (select fy from gym_today where org_key = 'A')$$,
  'GL037'::char(5), null,
  'r16/multirow: ONE statement, TWO rows — the receipt counter genuinely advances and the invoice counter is written its own value back — is refused with GL037. The trigger is FOR EACH ROW, and a rule that judged the statement''s net effect, or excused a standing row because a sibling moved forward, would let this through');

set local role postgres;

select is(
  (select string_agg(kind || '=' || next_number, ',' order by kind) from public.document_counters
     where tenant_id = '220000ff-0022-4000-8000-100000000001'
       and financial_year = (select fy from gym_today where org_key = 'A')),
  (select string_agg(kind || '=' || next_number, ',' order by kind) from h22r16_before),
  'r16/multirow: and BOTH rows are exactly where they were before the statement. The receipt row''s increase was legal on its own and still went back with the refusal — a refused row aborts the statement rather than being skipped, which is the difference between a receipt book and a suggestion');


-- ---------------------------------------------------------------------------
-- 24. ROUND SEVENTEEN, written blind by an EIGHTH author against the three
-- newest requirements in openspec/changes/phase-5-money/specs/payment-record/
-- spec.md: "A refund that completed did not fail", "Money only comes back out
-- of money that came in", and "A membership belongs to the member it was sold
-- to".
--
-- Not read, then or since: supabase/tests/22_payment_record.sql, written in
-- parallel this round by a DIFFERENT author (round sixteen had one author
-- write both files and a critic correctly found the two sections near
-- identical); prosrc or pg_get_functiondef for anything implementing these
-- three rules; and, per ADR-091, docs/registry.md for anything about this
-- round's code. Read: the three requirements, the live Cloud catalogue, and
-- this file.
--
-- REFUSALS ARE ASSERTED THROUGH `pg_temp.h22r17_gl`, NOT `throws_ok(..., null)`.
-- The rules this section attacks have no error codes yet, and a null expected
-- code accepts ANY sqlstate — including the two that would report a false
-- GREEN here:
--   * 23505 on `memberships_tenant_id_member_id_live_key`, which the
--     requirement itself warns about: a membership move to a member who
--     already holds a live one is refused TODAY, by a unique index, for a
--     reason that has nothing to do with the rule. The requirement's own
--     "trap for whoever tests this".
--   * 42501 from `refunds_tenant_write`, which is `is_gym_admin()` — a
--     refund attempted from the front desk is refused whatever the money
--     rules say, so every refund statement below runs under a MANAGER claim.
-- `h22r17_gl` is true only for a `GL0…` application refusal, so it cannot be
-- satisfied by a unique index, an RLS denial, a missing column or a syntax
-- error. Permitted cases are asserted as `is(state, 'OK')` rather than
-- `lives_ok` so that a failure prints the sqlstate that caused it.
--
-- THE SEAMS THIS SECTION CHOSE. It does not re-prove the three headlines.
--
--   * THE REFUND STATUS ENUM, EXHAUSTIVELY. The enum is enumerated from
--     pg_enum (and that enumeration is itself asserted, so a fifth value
--     added later fails here rather than silently leaving the matrix
--     incomplete), and all sixteen ordered pairs are attempted on sixteen
--     separate refund rows — one row per pair, inserted directly at its
--     source status, so nothing depends on the order the pairs are run in
--     and no reset can be confounded with the rule. Twelve transitions and
--     four self-writes. The requirement refuses exactly three of the
--     sixteen.
--   * `completed` REACHED BY UPDATE, not only by insert. Pair 9 is
--     `failed -> completed`; 24b then attempts to demote THAT row. A guard
--     keyed on the value the row was born with passes every pair in 24a and
--     fails here.
--   * WHAT IS LEFT UNFROZEN ON `refunds`, AND WHETHER IT REACHES THE
--     CEILING. GL040/GL041 freeze `payment_id`, `amount_paise` and
--     `initiated_by_staff_id`; this round freezes `status`. That leaves
--     `currency` and `kind` writable, and `enforce_refund_total` sums
--     `amount_paise` across BOTH kinds without reading either column
--     (measured). 24b asserts the property that actually matters — the
--     ceiling still holds after both edits — and reports the two open doors
--     by `diag` rather than asserting a side the requirement does not take.
--   * THE THREE RULES IN ONE STATEMENT. A demotion and the second refund it
--     makes room for, in one data-modifying CTE; a membership move and a
--     refund in one; and, after both are refused, an ordinary refund
--     proving the path is not simply shut (ADR-078).
--   * THE `created` RULE FROM THE OTHER SIDE. A payment born `paid`, one
--     that reaches `paid` by UPDATE, one that moves on to `refunded` and one
--     to `reversed` — all four must still take refunds. And the composition
--     with GL039: `paid -> failed` is already refused, so once the `created`
--     door is shut no refund can ever come to rest against a failed payment
--     by any route. That closure is asserted, not assumed.
--   * THE MEMBERSHIP MOVE FROM EVERY WRITER. Front desk (the measured
--     defect), gym manager, and `postgres` with no claim at all — the last
--     of which fails a rule written into RLS instead of onto the table.
--     Plus the INSERT side, which is a different act and stays permitted,
--     and the requirement's own remedy (cancel, re-sell) run end to end.
--   * THE PERMITTED SIDE AS HARD AS THE REFUSED (24g): a sale, a period
--     granted, an ordinary refund inside the ceiling advanced to
--     `completed`, a renewal, a freeze, an unfreeze, a cancellation and a
--     re-sale. Every one is green today and must stay green.
--
-- THE FINDING, WHICH THIS SECTION STAGES RATHER THAN ASSERTS (24c).
-- "A refund that completed did not fail" names its harm precisely: money
-- that left the gym must not become "an attempt that never happened", and
-- the tell is that the door is one-way — un-count freely, never re-count.
-- The rule closes that door for `completed` and, in the same requirement,
-- explicitly opens it for `processing`: "a refund that is not `completed`
-- moves between its other statuses — THEN it SHALL be allowed". A refund
-- sitting at `processing` is money already handed to the provider. 24c runs
-- the requirement's own measured sequence with `processing` in place of
-- `completed` and every step is permitted by the requirement as written:
-- the ceiling refuses the second refund, the first is demoted to `failed`,
-- the second is then ACCEPTED, and re-completing the first is refused by
-- GL036. Two full refunds of a single payment exist as rows, the books show
-- one, and the door is one-way exactly as before. Because the requirement
-- permits it, nothing here asserts a refusal; the sequence is asserted at
-- what the requirement says and the outcome is reported by `diag`.
-- ---------------------------------------------------------------------------

create function pg_temp.h22r17_state(sql text) returns text
language plpgsql as $fn$
begin
  execute sql;
  return 'OK';
exception when others then
  return sqlstate;
end
$fn$;

-- True ONLY for a GL0xx application refusal. 23505 (the live-membership
-- unique index), 42501 (RLS), 42703/42P01/42883/42601 (an unimplemented
-- contract) are all FALSE here on purpose — each of them is a way this
-- battery could go green without the rule existing.
create function pg_temp.h22r17_gl(sql text) returns boolean
language sql as $fn$
  select pg_temp.h22r17_state(sql) like 'GL0%'
$fn$;

grant execute on function pg_temp.h22r17_state(text) to public;
grant execute on function pg_temp.h22r17_gl(text) to public;

create temp table h22r17_obs (k text primary key, v text);
grant all on h22r17_obs to public;

-- Fixtures. Gym A throughout. Members f01-f11, memberships f01-f03, f07 (f04,
-- f05 and f08 are created by the assertions themselves), payments f01-f19.
set local role postgres;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000000f01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Matrix Payer',       '+919220000701'),
  ('220000ff-0022-4000-8000-500000000f02'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 One-Way Door',       '+919220000702'),
  ('220000ff-0022-4000-8000-500000000f03'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Money Never Arrived','+919220000703'),
  ('220000ff-0022-4000-8000-500000000f04'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Born Paid',          '+919220000704'),
  ('220000ff-0022-4000-8000-500000000f05'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Paid By Update',     '+919220000705'),
  ('220000ff-0022-4000-8000-500000000f06'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Move Owner',         '+919220000706'),
  ('220000ff-0022-4000-8000-500000000f07'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Move Target Empty',  '+919220000707'),
  ('220000ff-0022-4000-8000-500000000f08'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Move Target Live',   '+919220000708'),
  ('220000ff-0022-4000-8000-500000000f09'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Pending Owner',      '+919220000709'),
  ('220000ff-0022-4000-8000-500000000f10'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Multirow Target',    '+919220000710'),
  ('220000ff-0022-4000-8000-500000000f11'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R17 Permitted Side',     '+919220000711');

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000f01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f06'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  ('220000ff-0022-4000-8000-600000000f02'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f08'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000),
  ('220000ff-0022-4000-8000-600000000f07'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f11'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('220000ff-0022-4000-8000-600000000f03'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f09'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending', null, null, 100000);

-- Payments are recorded by the desk that took them (GL034), under a real
-- front-desk claim, because that is the only path a manual payment has.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
  ('220000ff-0022-4000-8000-700000000f01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f02'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f03'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f04'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f05'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f06'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f01'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f07'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f02'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f11'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f04'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f13'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f04'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f16'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f02'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f17'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f02'::uuid, null, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid);

insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id) values
  ('220000ff-0022-4000-8000-700000000f08'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f03'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f09'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f03'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f10'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f03'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f12'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f05'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid),
  ('220000ff-0022-4000-8000-700000000f14'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f05'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid),
  -- A SECOND created payment, kept untouched, so the reversal probe in 24d
  -- meets an EMPTY ceiling. Aimed at the first created payment it would be
  -- answered by GL036 today (the refund above it having filled that payment's
  -- ceiling) and would report a pass while the rule it tests does not exist.
  ('220000ff-0022-4000-8000-700000000f20'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f03'::uuid, null, 100000, 'cash', 'created', '220000ff-0022-4000-8000-300000000001'::uuid);

update public.payments set status = 'pending' where id in ('220000ff-0022-4000-8000-700000000f09'::uuid, '220000ff-0022-4000-8000-700000000f12'::uuid, '220000ff-0022-4000-8000-700000000f14'::uuid);
update public.payments set status = 'failed', failed_reason = 'h22 r17: never arrived' where id = '220000ff-0022-4000-8000-700000000f10'::uuid;
update public.payments set status = 'paid', paid_at = now() where id = '220000ff-0022-4000-8000-700000000f12'::uuid;

-- The membership that carries a granted period, and the money that granted it.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
  ('220000ff-0022-4000-8000-700000000f15'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000000f06'::uuid, '220000ff-0022-4000-8000-600000000f01'::uuid, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid);

-- The refund matrix, one row per ordered pair, each inserted directly at its
-- SOURCE status so no pair depends on the order the others ran in. 1000 paise
-- against payments of 100000, so the ceiling is never a candidate explanation
-- for anything 24a refuses. Refunds are gym-admin work (`refunds_tenant_write`
-- is `is_gym_admin()`), so this and every later refund runs as a manager.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('220000ff-0022-4000-8000-800000000f01'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f01'::uuid, 'refund', 1000, 'requested',  'h22 r17 pair 01 requested->processing',  '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f02'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f01'::uuid, 'refund', 1000, 'requested',  'h22 r17 pair 02 requested->completed',   '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f03'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f01'::uuid, 'refund', 1000, 'requested',  'h22 r17 pair 03 requested->failed',      '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f04'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f01'::uuid, 'refund', 1000, 'processing', 'h22 r17 pair 04 processing->requested',  '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f05'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f02'::uuid, 'refund', 1000, 'processing', 'h22 r17 pair 05 processing->completed',  '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f06'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f02'::uuid, 'refund', 1000, 'processing', 'h22 r17 pair 06 processing->failed',     '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f07'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f02'::uuid, 'refund', 1000, 'failed',     'h22 r17 pair 07 failed->requested',      '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f08'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f02'::uuid, 'refund', 1000, 'failed',     'h22 r17 pair 08 failed->processing',     '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f09'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f03'::uuid, 'refund', 1000, 'failed',     'h22 r17 pair 09 failed->completed',      '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f10'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f03'::uuid, 'refund', 1000, 'completed',  'h22 r17 pair 10 completed->requested',   '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f11'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f03'::uuid, 'refund', 1000, 'completed',  'h22 r17 pair 11 completed->processing',  '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f12'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f03'::uuid, 'refund', 1000, 'completed',  'h22 r17 pair 12 completed->failed',      '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f13'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f04'::uuid, 'refund', 1000, 'requested',  'h22 r17 pair 13 requested->requested',   '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f14'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f04'::uuid, 'refund', 1000, 'processing', 'h22 r17 pair 14 processing->processing', '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f15'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f04'::uuid, 'refund', 1000, 'failed',     'h22 r17 pair 15 failed->failed',         '220000ff-0022-4000-8000-300000000002'::uuid),
  ('220000ff-0022-4000-8000-800000000f16'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f04'::uuid, 'refund', 1000, 'completed',  'h22 r17 pair 16 completed->completed',   '220000ff-0022-4000-8000-300000000002'::uuid);

-- ---------------------------------------------------------------------------
-- 24a. THE REFUND STATUS ENUM, EXHAUSTIVELY. Four values, sixteen ordered
-- pairs, sixteen rows — one per pair, born at its source status. The
-- requirement refuses three of them ("any change out of `completed`") and
-- allows the other thirteen; the four self-writes are the pairs it answers
-- only by implication, since writing `completed` back is not a change OUT of
-- it, and a rule that reads OLD.status without comparing NEW refuses the
-- ordinary column-listing save that carries it (the shape 16h had to assert
-- one table over, for exactly this reason).
--
-- The enum itself is asserted first. If a fifth refund status is ever added,
-- this matrix is silently incomplete, and that assertion is the only thing
-- that would say so.
-- ---------------------------------------------------------------------------

select is(
  (select string_agg(e.enumlabel, ',' order by e.enumsortorder)
     from pg_type t join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'refund_status'),
  'requested,processing,completed,failed',
  'r17/enum: refund_status is exactly these four values in this order — the matrix below is 4 x 4 and complete only while that is true. A fifth value added later fails HERE rather than leaving an untested pair');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'processing' where id = '220000ff-0022-4000-8000-800000000f01'$$),
  'OK',
  'r17/pair 01 requested -> processing: permitted. A refund handed to the provider is the ordinary first move and nothing in this requirement touches it');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f01'::uuid),
  'processing',
  'r17/pair 01: and the row actually moved — a rule broad enough to refuse this would be caught here rather than by a passing lives_ok on an inert statement');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000f02'$$),
  'OK',
  'r17/pair 02 requested -> completed: permitted. The freeze is on the way OUT of completed, never on the way in — a refund has to be able to complete at all');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f02'::uuid),
  'completed',
  'r17/pair 02: and the row is completed');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f03'$$),
  'OK',
  'r17/pair 03 requested -> failed: permitted. A refund the provider declined before it ever started took nothing and is not the fact this rule protects');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f03'::uuid),
  'failed',
  'r17/pair 03: and the row is failed');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'requested' where id = '220000ff-0022-4000-8000-800000000f04'$$),
  'OK',
  'r17/pair 04 processing -> requested: permitted. BACKWARDS, and permitted — "a refund that is not completed moves between its other statuses" is a set, not an ordering, and an implementer who reaches for a transition table like GL039''s will refuse this');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f04'::uuid),
  'requested',
  'r17/pair 04: and the row really went backwards');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000f05'$$),
  'OK',
  'r17/pair 05 processing -> completed: permitted, and the ordinary happy path of every refund that ever leaves this gym');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f05'::uuid),
  'completed',
  'r17/pair 05: and the row is completed');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f06'$$),
  'OK',
  'r17/pair 06 processing -> failed: permitted BY THIS REQUIREMENT, and it is the pair 24c is about — see that section. Asserted here as what the requirement says, not as what is safe');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f06'::uuid),
  'failed',
  'r17/pair 06: and a refund the provider was already processing is now on the books as an attempt that never happened');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'requested' where id = '220000ff-0022-4000-8000-800000000f07'$$),
  'OK',
  'r17/pair 07 failed -> requested: permitted. A refund is retried by re-requesting it, and this is the pair that makes `failed` a way station rather than a terminal state');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f07'::uuid),
  'requested',
  'r17/pair 07: and the row is requested again');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'processing' where id = '220000ff-0022-4000-8000-800000000f08'$$),
  'OK',
  'r17/pair 08 failed -> processing: permitted');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f08'::uuid),
  'processing',
  'r17/pair 08: and the row is processing');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000f09'$$),
  'OK',
  'r17/pair 09 failed -> completed: permitted — a retry that succeeds, and the ONLY route by which a row reaches `completed` after being born something else. The ceiling has room (1000 of a 100000 payment), so nothing but the status rule can answer this. 24b then tries to demote THIS row: a freeze keyed on the status the row was INSERTED with passes every other pair here and fails there');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f09'::uuid),
  'completed',
  'r17/pair 09: and the row reached completed by UPDATE rather than by insert');

select ok(
  pg_temp.h22r17_gl($$update public.refunds set status = 'requested' where id = '220000ff-0022-4000-8000-800000000f10'$$),
  'r17/pair 10 completed -> requested: REFUSED with a GL0xx code. Money that left the gym does not become a request again, and un-completing by any target is the same one-way door as demoting to failed');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f10'::uuid),
  'completed',
  'r17/pair 10: refused AND unchanged — a refusal that still moved the value would be worse than none');

select ok(
  pg_temp.h22r17_gl($$update public.refunds set status = 'processing' where id = '220000ff-0022-4000-8000-800000000f11'$$),
  'r17/pair 11 completed -> processing: REFUSED with a GL0xx code. The measured defect used `failed` because that is the value the ceiling reads; a fix that names only `failed` leaves the fact just as editable, and this pair is what tells the two apart');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f11'::uuid),
  'completed',
  'r17/pair 11: refused AND unchanged');

select ok(
  pg_temp.h22r17_gl($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f12'$$),
  'r17/pair 12 completed -> failed: REFUSED with a GL0xx code. The measured defect itself, asserted here only so the matrix is whole');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f12'::uuid),
  'completed',
  'r17/pair 12: refused AND unchanged');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'requested' where id = '220000ff-0022-4000-8000-800000000f13'$$),
  'OK',
  'r17/pair 13 requested -> requested: permitted. Writing a status back unchanged is not a change, and every ordinary column-listing save from a console form carries the status column whether or not it differs');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f13'::uuid),
  'requested',
  'r17/pair 13: and the row is untouched');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'processing' where id = '220000ff-0022-4000-8000-800000000f14'$$),
  'OK',
  'r17/pair 14 processing -> processing: permitted');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f14'::uuid),
  'processing',
  'r17/pair 14: and the row is untouched');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f15'$$),
  'OK',
  'r17/pair 15 failed -> failed: permitted');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f15'::uuid),
  'failed',
  'r17/pair 15: and the row is untouched');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000f16'$$),
  'OK',
  'r17/pair 16 completed -> completed: THE PAIR THE REQUIREMENT DOES NOT ANSWER IN WORDS. It refuses "any change OUT of completed", and writing completed back is not a change out of it — so this file sides on permitted, consistent with 16h one table over. The shortest rule that passes pairs 10, 11 and 12 (`OLD.status = completed and TG_OP = UPDATE`) refuses this one, and it is the rule an implementer reaches for first');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f16'::uuid),
  'completed',
  'r17/pair 16: and the row is still completed');

-- ---------------------------------------------------------------------------
-- 24b. `completed` REACHED BY UPDATE, AND WHAT THE FREEZE LEAVES BEHIND.
--
-- Pair 09 above put a row into `completed` by UPDATE rather than by INSERT.
-- Everything in 24a would still pass for a guard that compares NEW.status
-- against the value the row was BORN with; this one does not.
--
-- Then the column audit. `GL040`/`GL041` freeze `payment_id`, `amount_paise`
-- and `initiated_by_staff_id`; this round freezes `status`. Of what is left,
-- two columns are read by nothing and written by anyone — `currency` and
-- `kind` — and `app.enforce_refund_total` sums `amount_paise` across both
-- kinds without consulting either (measured: a `reversal` and a `refund`
-- share one ceiling). Neither is a way to take more money out, which is why
-- nothing here asserts a refusal for them; what IS asserted is the property
-- that matters, that the ceiling still holds after both edits. The edits'
-- own outcomes are reported by `diag`, because the requirement takes no side.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r17_gl($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f09'$$),
  'r17/b: a refund that reached `completed` BY UPDATE cannot be demoted either. "A refund that completed did not fail" is about the fact, not about how the row got there, and a guard reading only the inserted value would let this one through');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f09'::uuid),
  'completed',
  'r17/b: refused AND unchanged');

select is(
  pg_temp.h22r17_state($$update public.refunds
      set reason = 'h22 r17: provider confirmed, reference filed afterwards',
          provider_refund_id = 'h22r17_rfnd_0001',
          processed_at = now()
    where id = '220000ff-0022-4000-8000-800000000f16'$$),
  'OK',
  'r17/b: WHAT STAYS WRITABLE. On a completed refund the reason, the provider''s own reference and the time it was processed are all still editable — the same distinction the payment freeze draws, freeze what the row MEANT and leave what has become of it. A freeze written as "no UPDATE at all once completed" passes every refusal above and breaks the reconciliation this column exists for');

select is(
  (select reason || '|' || provider_refund_id || '|' || (processed_at is not null)::text
     from public.refunds where id = '220000ff-0022-4000-8000-800000000f16'::uuid),
  'h22 r17: provider confirmed, reference filed afterwards|h22r17_rfnd_0001|true',
  'r17/b: and all three landed — the permitted statement was not merely inert (ADR-078)');

-- The two unfrozen columns, and whether either reaches the ceiling.
insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('220000ff-0022-4000-8000-800000000f17'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f05'::uuid, 'refund', 100000, 'completed', 'h22 r17 full refund, the ceiling on payment f05 is now closed', '220000ff-0022-4000-8000-300000000002'::uuid);

insert into h22r17_obs (k, v) values
  ('currency_edit', pg_temp.h22r17_state($$update public.refunds set currency = 'USD' where id = '220000ff-0022-4000-8000-800000000f17'$$));

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f18', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f05', 'refund', 100000, 'completed', 'h22 r17 a second full refund after the first was re-labelled', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/b/currency: WHATEVER HAPPENS TO THE CURRENCY, THE CEILING STILL HOLDS. A completed refund of the whole payment is re-labelled into another currency and a second full refund is still refused — the sum is in paise and counts the row regardless of what it now claims to be denominated in. This is the assertion that matters; the edit''s own outcome is reported below and not scored');

select is(
  (select coalesce(sum(amount_paise), 0)::text from public.refunds
    where payment_id = '220000ff-0022-4000-8000-700000000f05'::uuid and status <> 'failed'),
  '100000',
  'r17/b/currency: and exactly one full refund stands against that payment');

insert into h22r17_obs (k, v) values
  ('kind_edit', pg_temp.h22r17_state($$update public.refunds set kind = 'reversal' where id = '220000ff-0022-4000-8000-800000000f17'$$));

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f19', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f05', 'refund', 100000, 'completed', 'h22 r17 a third full refund after the first was re-kinded', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/b/kind: and the same for `kind` — a completed refund re-labelled a reversal is still counted, so re-kinding is not a way to reopen a closed ceiling either');

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('220000ff-0022-4000-8000-800000000f20'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f06'::uuid, 'reversal', 60000, 'completed', 'h22 r17 a reversal, not a refund', '220000ff-0022-4000-8000-300000000002'::uuid);

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000f21', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f06', 'refund', 60000, 'completed', 'h22 r17 a refund on top of a reversal', '220000ff-0022-4000-8000-300000000002')$$,
  'GL036'::char(5), null,
  'r17/b/kind: THE TWO KINDS SHARE ONE CEILING, asserted rather than assumed. A 60000 reversal plus a 60000 refund is 120000 against a 100000 payment and GL036 refuses it. Green today; a round that segments the ceiling by kind to make the freeze simpler would open a second full withdrawal per payment and would be visible here');

select is(
  (select coalesce(sum(amount_paise), 0)::text from public.refunds
    where payment_id = '220000ff-0022-4000-8000-700000000f06'::uuid and status <> 'failed'),
  '60000',
  'r17/b/kind: and only the reversal stands against that payment');

select diag(format(
  'r17/b OBSERVED, unscored: editing a COMPLETED refund''s currency returned %s, and its kind returned %s. GL040/GL041 froze payment_id, amount_paise and initiated_by_staff_id; this round froze status. If both of the above are OK, a refund''s denomination and its very kind remain editable for the life of the row while the ceiling that bounds it is denominated in nothing at all. Neither lets more money out — the two assertions above prove that — so this is reported, not asserted.',
  (select v from h22r17_obs where k = 'currency_edit'),
  (select v from h22r17_obs where k = 'kind_edit')));

-- ---------------------------------------------------------------------------
-- 24c. THE HARM, BY ANOTHER ROUTE. The requirement's own measured sequence,
-- with `processing` where it had `completed`. Every step below is permitted
-- by the requirement as written — pair 06 above is the demotion, and the
-- requirement's second scenario says in as many words that a refund which is
-- not completed "moves between its other statuses … THEN it SHALL be
-- allowed".
--
-- A refund at `processing` is money already handed to the provider. Demote it
-- to `failed`, the ceiling forgets it, the second full refund is accepted,
-- and re-completing the first is then refused by GL036 — un-count freely,
-- never re-count, which is the requirement's own tell for the one-way door.
--
-- NOTHING HERE ASSERTS A REFUSAL, because the requirement grants one. The
-- steps are asserted at what the requirement says and the outcome is
-- reported. If a round-eighteen contract extends the freeze to `processing`,
-- three of these seven assertions invert and the diag below says which.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f22', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f07', 'refund', 100000, 'processing', 'h22 r17 full refund, handed to the provider', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/c/step 1: a full 100000 refund of a 100000 payment is recorded at `processing` — the provider has it, the money is in flight, and the ceiling counts it because it is not failed');

select throws_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000000f23', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f07', 'refund', 100000, 'completed', 'h22 r17 a second full refund, first attempt', '220000ff-0022-4000-8000-300000000002')$$,
  'GL036'::char(5), null,
  'r17/c/step 2: a second full refund is refused by GL036, exactly as the requirement''s own measurement records');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'failed' where id = '220000ff-0022-4000-8000-800000000f22'$$),
  'OK',
  'r17/c/step 3: THE DEMOTION, PERMITTED. The in-flight refund is written down to `failed`. The requirement freezes `completed` and says of everything else that it "SHALL be allowed" — so this is the contract, asserted as the contract');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f22'::uuid),
  'failed',
  'r17/c/step 3: and money the provider is processing now reads as an attempt that never happened');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f23', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f07', 'refund', 100000, 'completed', 'h22 r17 a second full refund, second attempt', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/c/step 4: and the second full refund is now ACCEPTED. Two full refunds of one payment exist as rows. This is the sentence the requirement wrote about `completed`, reached through `processing`');

select throws_ok(
  $$update public.refunds set status = 'completed' where id = '220000ff-0022-4000-8000-800000000f22'$$,
  'GL036'::char(5), null,
  'r17/c/step 5: and the demoted one cannot be re-completed when the provider confirms it — GL036 refuses, because by now the sum is full. The door is one-way in exactly the shape the requirement names: un-count freely, never re-count');

select is(
  (select coalesce(sum(amount_paise), 0)::text || '/' ||
          count(*)::text
     from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f07'::uuid
       and status <> 'failed'),
  '100000/1',
  'r17/c/step 6: the books show one refund of 100000 against a payment of 100000, and are internally consistent. The second row is invisible to every sum in the system, which is why nothing surfaces');

select diag(
  'r17/c OBSERVED, unscored: the whole sequence the requirement "A refund that completed did not fail" was written to close runs to completion with `processing` in place of `completed`, and every step of it is PERMITTED by that requirement''s own second scenario. A refund at `processing` is money already with the provider. The requirement names its harm as money that left the gym becoming an attempt that never happened, and its tell as a one-way door out of the ledger; both are reproduced above under the rule, not around it. This is reported and not asserted, because siding against it would be asserting a contract nobody has approved.');

-- ---------------------------------------------------------------------------
-- 24d. MONEY ONLY COMES BACK OUT OF MONEY THAT CAME IN — FROM BOTH SIDES.
--
-- The refused side is all three statuses the requirement names, not just the
-- `created` one the critic measured, and both refund KINDS, because
-- `enforce_refund_total` reads neither and a fix keyed on `kind = 'refund'`
-- would leave a reversal against a payment that never arrived.
--
-- The permitted side is every route into "has taken money": a payment born
-- `paid` (the ordinary manual case), one that reaches `paid` by UPDATE, and
-- the two statuses beyond it, `refunded` and `reversed`, which a rule written
-- as `status = 'paid'` would refuse — closing the SECOND refund of a
-- part-refunded payment, which is an ordinary thing to do.
--
-- And the closure. Once the `created` door is shut, can a refund ever come to
-- rest against a payment that is not one of the three? Only if a payment
-- carrying a refund could walk to `failed` afterwards — and GL039 already
-- refuses that. The two rules together, not either alone, are what makes the
-- state unreachable, so the composition is asserted here rather than assumed.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f24', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f08', 'refund', 100000, 'h22 r17 refunding a payment that never arrived', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/d: a refund naming a `created` payment is REFUSED with a GL0xx code — the measured defect. `amount_paise` is not null on a created row and the ceiling read it happily; the status is what says whether any of it ever arrived');

select is(
  (select count(*)::int from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f08'::uuid),
  0,
  'r17/d: and NO refund exists against it — the requirement says "no refund SHALL exist", which is stronger than "the statement raised"');

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f25', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f09', 'refund', 100000, 'h22 r17 refunding a pending payment', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/d: a refund naming a `pending` payment is REFUSED. Pending is the status a provider payment sits at while the gym is waiting to hear; nothing has arrived');

select is(
  (select count(*)::int from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f09'::uuid),
  0,
  'r17/d: and no refund exists against the pending one');

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f26', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f10', 'refund', 100000, 'h22 r17 refunding a failed payment', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/d: a refund naming a `failed` payment is REFUSED. The third of the three the requirement names, and the one an implementer is most likely to leave out because a failed payment feels like it needs unwinding');

select is(
  (select count(*)::int from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f10'::uuid),
  0,
  'r17/d: and no refund exists against the failed one');

select ok(
  pg_temp.h22r17_gl($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f27', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f20', 'reversal', 50000, 'h22 r17 reversing a payment that never arrived', '220000ff-0022-4000-8000-300000000002')$$),
  'r17/d: a REVERSAL naming a `created` payment is refused too. The requirement says "a refund names a payment" and the table holds both kinds under one ceiling (24b); a fix that reads `kind` leaves the whole reversal path open. It names a SECOND created payment, with an empty ceiling, on purpose: aimed at the first one this assertion is answered by GL036 today and passes while the rule under test does not exist — verifying a refusal that was already going to happen is not verifying');

select is(
  (select count(*)::int from public.refunds
    where payment_id in ('220000ff-0022-4000-8000-700000000f08'::uuid, '220000ff-0022-4000-8000-700000000f20'::uuid)),
  0,
  'r17/d: and nothing at all stands against either created payment, after three attempts of two different kinds');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f28', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f11', 'refund', 5000, 'h22 r17 an ordinary partial refund of cash taken at the desk', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/d: THE ORDINARY CASE. A payment INSERTED at `paid` — which is how every manual cash payment in this product arrives — takes a refund');

select is(
  (select count(*)::int from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f11'::uuid),
  1,
  'r17/d: and the refund is really there');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f29', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f12', 'refund', 5000, 'h22 r17 a refund of money that arrived by update', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/d: a payment that reached `paid` by UPDATE — created, pending, paid, which is the provider path — takes a refund on the same terms. The rule reads the status now, not the status the row was born with');

select is(
  (select count(*)::int from public.refunds where payment_id = '220000ff-0022-4000-8000-700000000f12'::uuid),
  1,
  'r17/d: and that one is there too');

select is(
  pg_temp.h22r17_state($$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000f11'$$),
  'OK',
  'r17/d: the first payment then moves paid -> refunded, one of the two edges out of paid');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f30', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f11', 'refund', 5000, 'h22 r17 the second instalment of a part refund', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/d: and a SECOND refund against that `refunded` payment is still permitted. The requirement names three statuses on purpose; a fix written as `status = paid` would refuse the second half of every part refund, which is loud but wrong');

select is(
  pg_temp.h22r17_state($$update public.payments set status = 'reversed' where id = '220000ff-0022-4000-8000-700000000f12'$$),
  'OK',
  'r17/d: the other payment moves paid -> reversed, the second edge out of paid');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f31', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f12', 'reversal', 5000, 'h22 r17 a reversal against a reversed payment', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/d: and a refund against a `reversed` payment is permitted — the third status the requirement names, asserted so a fix cannot quietly ship only two of the three');

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id) values
  ('220000ff-0022-4000-8000-800000000f32'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f13'::uuid, 'refund', 5000, 'h22 r17 a legal refund whose payment is then pushed backwards', '220000ff-0022-4000-8000-300000000002'::uuid);

select throws_ok(
  $$update public.payments set status = 'failed', failed_reason = 'h22 r17: unwinding a payment that already carries a refund' where id = '220000ff-0022-4000-8000-700000000f13'$$,
  'GL039'::char(5), null,
  'r17/d/closure: THE OTHER HALF OF THE DOOR. A refund written legally against a `paid` payment cannot be turned into a refund against a failed one, because GL039 refuses paid -> failed. With this round shutting the `created` door, the two rules TOGETHER make "a refund attached to a payment that took nothing" unreachable by any route — which neither rule states and neither achieves alone');

select is(
  (select status::text from public.payments where id = '220000ff-0022-4000-8000-700000000f13'::uuid),
  'paid',
  'r17/d/closure: refused AND the payment is unchanged');

insert into h22r17_obs (k, v) values
  ('cte_pay_then_refund', pg_temp.h22r17_state($$with p as (
       update public.payments set status = 'paid', paid_at = now()
        where id = '220000ff-0022-4000-8000-700000000f14' returning id
     )
     insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
     select '220000ff-0022-4000-8000-800000000f33', '220000ff-0022-4000-8000-100000000001', p.id, 'refund', 1000,
            'h22 r17 a refund written in the same statement that pays the payment', '220000ff-0022-4000-8000-300000000002'
       from p$$));

select ok(
  (select v = 'OK' or v like 'GL0%' from h22r17_obs where k = 'cte_pay_then_refund'),
  'r17/d/same-statement: a payment made `paid` and refunded in ONE statement, as a data-modifying CTE, is answered either way and never by an internal error, a null violation or a lock timeout. The requirement does not say WHEN "has actually taken money" is evaluated, and the two readings — the snapshot the refund''s own sub-statement sees, versus the state at the end of the statement — differ only here');

select ok(
  (select (o.v = 'OK') = (exists (select 1 from public.refunds where id = '220000ff-0022-4000-8000-800000000f33'::uuid))
     from h22r17_obs o where o.k = 'cte_pay_then_refund'),
  'r17/d/same-statement: and the outcome and the row agree — the refund exists if and only if the statement said so. This is the assertion a partially-applied statement would fail, and the reason the pair is worth having even though the requirement takes no side on which answer is right');

select diag(format(
  'r17/d/same-statement OBSERVED, unscored: `with p as (update payments set paid) insert into refunds select from p` returned %s. If OK, the ceiling and the arrival check both see the payment as paid at the moment the AFTER trigger runs, so a caller can pay and refund atomically. If a GL0xx, the refund is judged against the status the payment held when the statement began, and POST /api/refunds must never be composed with a payment update. The requirement settles neither; a round that changes this answer changes an API contract silently.',
  (select v from h22r17_obs where k = 'cte_pay_then_refund')));

-- ---------------------------------------------------------------------------
-- 24e. A MEMBERSHIP BELONGS TO THE MEMBER IT WAS SOLD TO.
--
-- THE TRAP THE REQUIREMENT ITSELF NAMES is why both targets are used, and WHY
-- THE TWO ARE ASSERTED DIFFERENTLY. Read this before "fixing" the ordering.
--
--   * Target holding NOTHING (the shape the defect was measured on): nothing
--     but this round's rule can refuse it, so it is asserted through
--     `h22r17_gl` and must carry a `GL0…` code. This is the pair that proves
--     the round did anything.
--   * Target ALREADY HOLDING A LIVE MEMBERSHIP (the shape a careless test
--     would use): refused by `memberships_tenant_id_member_id_live_key` with
--     23505, and it will KEEP being refused by the index. A unique index is
--     enforced at row-write time; ADR-072 puts these refusals in AFTER
--     triggers exactly so they cannot adjudicate a row the storage layer or a
--     policy was about to refuse anyway (ADR-066). The rule can only answer
--     first by becoming a BEFORE trigger, which is the thing ADR-072 forbids.
--     So this one is asserted through `h22r8_refused` — refused by ANYTHING
--     except a missing column, table, function or syntax error — plus the
--     unchanged read. It cannot go green against an unimplemented contract,
--     and it does not pin a code the rule was never going to give.
--
-- THE PRECEDENT IS GL045's: two round-ten assertions pinned that code on
-- writes that inverted the date range and a Phase 1 CHECK answered first with
-- 23514; that author widened the fixture so the rule was the only thing left
-- that could refuse, and recorded the ordering here rather than pinning the
-- constraint's code. Same shape, same answer. A future reader who "fixes"
-- this by moving the rule to a BEFORE trigger has broken ADR-072 to satisfy
-- one assertion that was never about the rule.
--
-- EVERY WRITER, because the rule says "any session". The desk is where the
-- defect was measured and is the least-privileged writer that reaches the
-- table; the manager is the one who would actually try to "correct" a
-- mis-sale; and `postgres` with no claim at all is the probe that fails a
-- rule written into RLS or into `is_gym_admin()` instead of onto the table,
-- which is how GL046 was built one requirement earlier.
--
-- AND THE INSERT SIDE, which the requirement distinguishes in its own second
-- scenario: selling a membership TO another member is not re-pointing one,
-- and a fix that refuses `member_id` on INSERT as well as UPDATE breaks every
-- sale in the product.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select ok(
  pg_temp.h22r17_gl($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f07' where id = '220000ff-0022-4000-8000-600000000f01'$$),
  'r17/e: THE MEASURED DEFECT. A FRONT-DESK session moves a membership that carries a granted period onto a member who holds NOTHING, in one statement, and it is refused with a GL0xx code. The empty target is deliberate: the requirement warns that a target already holding a live membership is refused by a unique index instead, and 23505 is not accepted here');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid),
  '220000ff-0022-4000-8000-500000000f06',
  'r17/e: refused AND the membership still belongs to the member it was sold to');

select ok(
  pg_temp.h22r8_refused($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f08' where id = '220000ff-0022-4000-8000-600000000f01'$$),
  'r17/e/trap: the same move onto a member who ALREADY HOLDS A LIVE MEMBERSHIP is refused too — BY WHATEVER ANSWERS FIRST, which is `memberships_tenant_id_member_id_live_key` with 23505, not this round''s rule. That ordering is correct and deliberate: ADR-072 puts these refusals in AFTER triggers so they cannot adjudicate a row the storage layer or a policy was already going to refuse, and a unique index is enforced at row-write time. Asserted through `h22r8_refused` (any refusal except a missing column, table, function or syntax error) rather than `h22r17_gl`, so it cannot be satisfied by an unimplemented contract but also does not pin a code the rule was never going to give. The assertion that proves THIS ROUND did something is the one above it, on a target holding nothing, where nothing else can answer');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid),
  '220000ff-0022-4000-8000-500000000f06',
  'r17/e/trap: refused AND unchanged. This half is the point of the pair — a careless author writes only the refusal, reads a pass off the index, and never learns the rule is missing');

select ok(
  pg_temp.h22r17_gl($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f07' where id = '220000ff-0022-4000-8000-600000000f03'$$),
  'r17/e: and a PENDING membership that has never taken a paisa, never granted a period and has no dates is refused too. The requirement is unconditional — "WHEN a session changes a membership''s member_id" — with no money gate of the kind GL043 has, and a fix that borrows GL043''s gate would leave the whole pre-money window open');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f03'::uuid),
  '220000ff-0022-4000-8000-500000000f09',
  'r17/e: refused AND unchanged, on the un-paid row as much as the paid one');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select ok(
  pg_temp.h22r17_gl($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f07' where id = '220000ff-0022-4000-8000-600000000f01'$$),
  'r17/e: a GYM MANAGER is refused the same move. This one matters because the manager is who would actually attempt it — "the member was entered wrong, move it" — and because GL046 one requirement earlier made exactly this column family a question of WHO. It is not: it is a question of WHETHER');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid),
  '220000ff-0022-4000-8000-500000000f06',
  'r17/e: refused AND unchanged for the manager too');

set local role postgres;

select ok(
  pg_temp.h22r17_gl($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f07' where id = '220000ff-0022-4000-8000-600000000f01'$$),
  'r17/e: and `postgres`, with no JWT claim at all, is refused as well. A rule expressed as an RLS policy or through `is_gym_admin()` passes every assertion above and fails this one; the requirement says the membership belongs to the member, not that some roles may re-point it');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid),
  '220000ff-0022-4000-8000-500000000f06',
  'r17/e: refused AND unchanged from the claimless session');

set local role authenticated;

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
      values ('220000ff-0022-4000-8000-600000000f04', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000f07', '220000ff-0022-4000-8000-400000000001', 'pending', null, null, 100000)$$),
  'OK',
  'r17/e/insert: CREATING a membership FOR another member is a different act and stays permitted. Every sale in this product writes a member_id it did not previously hold, and the shortest rule that passes all six refusals above — "member_id may not be written" — refuses this and takes the whole product with it');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f04'::uuid),
  '220000ff-0022-4000-8000-500000000f07',
  'r17/e/insert: and the new membership really belongs to the member it names');

select is(
  pg_temp.h22r17_state($$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r17: sold to the wrong member' where id = '220000ff-0022-4000-8000-600000000f01'$$),
  'OK',
  'r17/e/remedy: step one of the answer the requirement gives instead of an edit — the membership is cancelled. A status is not who it was sold to, so it stays writable');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
      values ('220000ff-0022-4000-8000-600000000f05', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000f07', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key='A'), (select today from gym_today where org_key='A') + 30, 100000)$$),
  'OK',
  'r17/e/remedy: step two — a NEW membership is sold to the right member. The requirement''s own answer ("a refund, a cancellation and a new sale") runs end to end, which is what makes the refusals above a rule rather than a dead end');

select is(
  (select (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f05'::uuid)
       || '|' ||
          (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid)),
  '220000ff-0022-4000-8000-500000000f07|220000ff-0022-4000-8000-500000000f06',
  'r17/e/remedy: and afterwards the new row belongs to the new member while the cancelled one still names the original — two records of two facts, which is the whole point of refusing the edit');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select is(
  pg_temp.h22r17_state($$update public.memberships set member_id = member_id, status = 'frozen' where id = '220000ff-0022-4000-8000-600000000f02'$$),
  'OK',
  'r17/e/write-back: an ordinary column-listing save that CARRIES member_id at its existing value, alongside a real change, is permitted. Every console form posts the whole row; a rule that fires on the column being present in the SET list rather than on the value differing refuses the ordinary freeze at the desk');

select is(
  (select status::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f02'::uuid),
  'frozen',
  'r17/e/write-back: and the real change in that statement landed — the permitted case was not inert (ADR-078)');

select ok(
  pg_temp.h22r17_gl($$update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f10'
       where id in ('220000ff-0022-4000-8000-600000000f02', '220000ff-0022-4000-8000-600000000f03')$$),
  'r17/e/multirow: ONE statement moving TWO memberships onto one empty member is refused. Neither row trips the live-membership index — the target holds nothing and only one of the two is live — so 23505 cannot answer this, and a rule judging a statement''s net effect rather than each row would let it through');

select is(
  (select (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f02'::uuid)
       || '|' ||
          (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f03'::uuid)),
  '220000ff-0022-4000-8000-500000000f08|220000ff-0022-4000-8000-500000000f09',
  'r17/e/multirow: and BOTH rows are exactly where they were — one refused row takes the whole statement with it rather than being skipped');

-- ---------------------------------------------------------------------------
-- 24f. THE THREE RULES IN ONE STATEMENT. Every defect this phase has shipped
-- survived a single-statement test and died on a composed one, so each pair
-- of rules is offered a data-modifying CTE that needs both of them to hold.
-- The last two assertions are the ADR-078 control: after both compositions
-- are refused, an ordinary refund on the same payment still succeeds, so
-- none of the refusals above could be satisfied by a path that is simply
-- shut.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id) values
  ('220000ff-0022-4000-8000-800000000f34'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-700000000f16'::uuid, 'refund', 100000, 'completed', 'h22 r17 a completed full refund, to be demoted in the same statement as its replacement', '220000ff-0022-4000-8000-300000000002'::uuid);

select ok(
  pg_temp.h22r17_gl($$with d as (
       update public.refunds set status = 'failed'
        where id = '220000ff-0022-4000-8000-800000000f34' returning id
     )
     insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, status, reason, initiated_by_staff_id)
     select '220000ff-0022-4000-8000-800000000f35', '220000ff-0022-4000-8000-100000000001',
            '220000ff-0022-4000-8000-700000000f16', 'refund', 100000, 'completed',
            'h22 r17 the second full refund, in the same statement as the demotion that makes room for it',
            '220000ff-0022-4000-8000-300000000002'
       from d$$),
  'r17/f: THE DEMOTION AND THE REFUND IT MAKES ROOM FOR, IN ONE STATEMENT. The exploit compressed until there is no moment between the two writes for a rule to observe. Refused with a GL0xx code');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f34'::uuid),
  'completed',
  'r17/f: and the completed refund is still completed');

select is(
  (select count(*)::int from public.refunds where id = '220000ff-0022-4000-8000-800000000f35'::uuid),
  0,
  'r17/f: and the second refund does not exist. Both halves, because a statement that refused the demotion but kept the insert would be worse than either');

select ok(
  pg_temp.h22r17_gl($$with r as (
       insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
       values ('220000ff-0022-4000-8000-800000000f36', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f17', 'refund', 1000, 'h22 r17 a refund alongside a membership move', '220000ff-0022-4000-8000-300000000002')
       returning id
     )
     update public.memberships set member_id = '220000ff-0022-4000-8000-500000000f10'
      where id = '220000ff-0022-4000-8000-600000000f01' and exists (select 1 from r)$$),
  'r17/f: A MEMBERSHIP MOVE CARRIED BY A LEGAL REFUND, one statement. The refund alone would be permitted (1000 against a 100000 paid payment, well inside the ceiling), so the only thing that can refuse this is the membership rule — and it must refuse the whole statement, not the half it owns');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f01'::uuid),
  '220000ff-0022-4000-8000-500000000f06',
  'r17/f: and the membership is unchanged');

select is(
  (select count(*)::int from public.refunds where id = '220000ff-0022-4000-8000-800000000f36'::uuid),
  0,
  'r17/f: and the legal refund inside that statement did NOT land either — a refusal on one row of a composed statement rolls the whole statement back, which is what makes the composition safe rather than partial');

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f37', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f17', 'refund', 1000, 'h22 r17 the same refund, on its own', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/f/control: THE SAME REFUND, ALONE, SUCCEEDS. Without this the two refusals above would be satisfied by a build that simply cannot write a refund against this payment at all, and both would report a pass for the wrong reason (ADR-078)');

select is(
  (select count(*)::int from public.refunds where id = '220000ff-0022-4000-8000-800000000f37'::uuid),
  1,
  'r17/f/control: and it is really there');

-- ---------------------------------------------------------------------------
-- 24g. THE PERMITTED SIDE, AS HARD AS THE REFUSED. Three freezes landed in
-- one round on two tables in the middle of the money path. A fix broad enough
-- to pass every refusal above and nothing else has shipped in this project
-- three times, and it is silent in exactly the way this phase is about: the
-- desk gets an error it does not understand, and the gym stops taking money.
-- One member, one membership, and the whole ordinary life of both.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select is(
  pg_temp.h22r17_state($$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000f18', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000f11', '220000ff-0022-4000-8000-600000000f07', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$),
  'OK',
  'r17/g: an ordinary sale — the desk takes Rs.1,000 in cash against a live membership and records it');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000f07'::uuid),
  1,
  'r17/g: and the granting rule ran — one whole multiple of the price arrived, one period granted. The membership rule freezes who it was sold to, and must not freeze the rule''s own write to the same row');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select is(
  pg_temp.h22r17_state($$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
      values ('220000ff-0022-4000-8000-800000000f38', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000000f18', 'refund', 40000, 'h22 r17 a goodwill part refund', '220000ff-0022-4000-8000-300000000002')$$),
  'OK',
  'r17/g: an ordinary part refund inside the ceiling, recorded at the default `requested`');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed', processed_at = now() where id = '220000ff-0022-4000-8000-800000000f38'$$),
  'OK',
  'r17/g: and it completes. Every refund in this product has to pass through this statement exactly once, and it is the statement immediately adjacent to the one the freeze refuses');

select is(
  (select status::text from public.refunds where id = '220000ff-0022-4000-8000-800000000f38'::uuid),
  'completed',
  'r17/g: and it is really completed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select is(
  pg_temp.h22r17_state($$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000f19', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000f11', '220000ff-0022-4000-8000-600000000f07', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$),
  'OK',
  'r17/g: the member renews — a second payment against the same membership, which is the whole business this product is in');

select is(
  (select periods_granted from public.memberships where id = '220000ff-0022-4000-8000-600000000f07'::uuid),
  2,
  'r17/g: and the second period is granted, refund and all. Money that came back out does not un-buy the month (section 22 established that); this asserts the renewal path still reaches the row after three freezes landed on it');

select is(
  pg_temp.h22r17_state($$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000000f07'$$),
  'OK',
  'r17/g: the membership can still be frozen');

select is(
  pg_temp.h22r17_state($$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000000f07'$$),
  'OK',
  'r17/g: and unfrozen — the pause path, which writes the same row the member_id freeze now guards');

select is(
  pg_temp.h22r17_state($$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r17: member left town' where id = '220000ff-0022-4000-8000-600000000f07'$$),
  'OK',
  'r17/g: and cancelled');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
      values ('220000ff-0022-4000-8000-600000000f08', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000f11', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key='A'), (select today from gym_today where org_key='A') + 30, 100000)$$),
  'OK',
  'r17/g: and the SAME member is sold a new one afterwards. "This rule refuses re-pointing, not selling" has to be true for the original member too, not only for the one a mis-sale was moved to');

select is(
  (select member_id::text from public.memberships where id = '220000ff-0022-4000-8000-600000000f08'::uuid),
  '220000ff-0022-4000-8000-500000000f11',
  'r17/g: and the new membership belongs to them');


-- ---------------------------------------------------------------------------
-- 25. TWELFTH-SESSION EXTENSION, round EIGHTEEN, written blind by a NINTH
-- author against a requirement that is not in this file's own spec at all:
-- openspec/changes/membership-lifecycle/specs/membership-lifecycle/spec.md,
-- which closes OPEN-030 — `memberships.status` gets the state machine
-- `payments` has had since Phase 5 round three.
--
-- Not read, then or since: supabase/tests/*.sql (the visible battery for this
-- change is being written in parallel by a different author); any migration
-- later than round seventeen's; prosrc or pg_get_functiondef for
-- app.grant_periods, app.extend_membership_on_payment, or anything
-- implementing the new rule; and, per ADR-091, docs/registry.md for anything
-- about this round's code. Read: the two requirements, this change's plan.md,
-- docs/decisions.md OPEN-023/026/030 and ADR-082/084/089/096, the live Cloud
-- catalogue, supabase/seed.sql, supabase/seed-scenarios.sql and
-- .github/workflows/db.yml.
--
-- THE ROUND HAD NO GL NUMBER WHEN THIS WAS WRITTEN. Every refusal that should
-- come from the new rule is therefore asserted through `pg_temp.h22r17_gl`,
-- which is true only for a `GL0…` sqlstate: 42703/42P01/42883/42601 (an
-- unimplemented contract), 23514 (a Phase 1 CHECK) and 42501 (RLS) are all
-- FALSE on purpose, each being a way this battery could go green without the
-- rule existing. A build that refuses these writes with a bare 23514 fails
-- here and should — GL039 is the sibling this rule is modelled on and it
-- raises a mapped code the desk can be shown.
--
-- Section 25 leaves both headlines to the visible suite. Its seams:
--
--   * THE CHAIN ADR-096 KEPT, RE-RUN END TO END (25a). ADR-096 left money
--     paid while retired on record *because a revival might yet count it*.
--     Requirement one makes that revival impossible, so every link of the
--     chain that keeps the money from stranding is asserted individually:
--     recorded, receipted from the gym's own financial-year counter,
--     attributed to the staff member who took it (GL034), refundable in full
--     and bounded by GL036 at the paisa above it, the retired row unmoved by
--     the payment AND unmoved by the refund, the paid payment un-repointable
--     onto the live membership (so refund-and-retake is provably the ONLY
--     remedy, which is what the requirement claims), and the same amount
--     taken against the live membership extending it normally. If any one of
--     those links is broken the second requirement is false.
--
--   * WHERE THE GRANTING RULE WRITES STATUS ITSELF (25b). `app.grant_periods()`
--     activates a `pending` membership on its first payment — the rule's own
--     legal transition, which any guard has to exempt. The exemption is the
--     hole: a data-modifying CTE that inserts a payment and writes
--     `cancelled -> active` in the SAME statement is a hand imitating that
--     path exactly, and it is asked twice — once with the payment naming the
--     retired row, once with it naming an entirely legitimate live one and
--     serving only as a carrier. Plus the source the rule's activation branch
--     is actually written for: a membership that was `pending`, was cancelled,
--     and is then paid.
--
--   * THE MALFORMED ROWS (25c), OPEN-023 and OPEN-026 by name. Three shapes:
--     a half-dated `pending` row, a dateless `pending` row of a member who is
--     already covered, and one whose money arrived in another currency. The
--     question asked is not "is this refused" but "does a transition rule make
--     any of them PERMANENTLY unrepairable, and is that right" — answered per
--     row, with the one repairable shape asserted on the permitted side so an
--     over-broad fix cannot take it away.
--
--   * MULTI-ROW AND MULTI-STATEMENT (25d): MERGE, `UPDATE … FROM` with a
--     different target status per row, a data-modifying CTE that pays and
--     transitions in one statement (refused AND permitted), a statement mixing
--     a legal transition with an illegal one, `INSERT … ON CONFLICT DO UPDATE`
--     as an attack, and a transition split across two statements of one
--     transaction — the shape a rule evaluated against the transaction's
--     starting snapshot waves through.
--
--   * ROLES AND TRUSTED CONTEXTS, AND THE SEED (25e). `seed-scenarios.sql`
--     builds its lapsed and cancelled fixtures by writing `expired` and
--     `cancelled` directly, and `seed-dry-run` runs both seed files inside one
--     transaction against a project where they are ALREADY COMMITTED — so
--     every one of those writes arrives as the `on conflict (id) do update set
--     status = excluded.status` half of an upsert, with the value unchanged.
--     That statement shape is asserted here verbatim rather than paraphrased,
--     on a `cancelled` row and on an `expired` one, and the creation path is
--     asserted too for the fresh-project run. The answer this section reports:
--     the rule needs NO role carve-out and the seed needs NO change, because
--     the seed only ever CREATES a terminal status or writes it back to
--     itself, and both are already permitted. Sided accordingly — claimless
--     `postgres`, `service_role` and a gym owner are each refused a revival,
--     on ADR-082's distinction as 20c draws it: a carve-out is sound where the
--     rule's subject is an identity a trusted caller lacks, and this rule's
--     subject is the data. And the last pair asks the question that makes the
--     whole carve-out argument moot if it goes wrong: with
--     `memberships_terms_frozen` DISABLED exactly as both seed files disable
--     it, the revival must STILL be refused — a rule folded into that trigger
--     would be silently off for the entire seed.
--
--   * THE GATE (25f), asserted as a refused check-in rather than as a column,
--     and then the one-way door: an `active` membership with ten days left,
--     written to `expired` from an ordinary front-desk session in one
--     statement — legal by this requirement's own second scenario — whose
--     member is refused at the gate from that moment and can never be brought
--     back. The repair that does exist (sell the same member a new membership)
--     is asserted, because it is what bounds the harm.
--
-- WHAT THIS SECTION REPORTS RATHER THAN RESOLVES, both by `diag`:
--
--   1. CREATION IS NOT A TRANSITION AND THE REQUIREMENT NEVER SAYS SO. Every
--      sentence is about a status that CHANGES. A row created directly at
--      `cancelled`, `expired` or `frozen` is unanswered — and has to stay
--      permitted, because the seed's fresh-project path is exactly that and so
--      is this file's own fixture block. 25e asserts the permitted side and
--      reports the gap; OPEN-029 already says creation is unpoliced for dates.
--
--   2. THE MALFORMED `pending` ROWS ARE UNREPAIRABLE, AND THIS RULE IS NOT
--      WHAT MAKES THEM SO. `memberships_dated_unless_pending_chk` refuses both
--      of a half-dated row's legal exits and GL045 refuses the date write that
--      would fix it first, so the row was already sealed before round
--      eighteen. 25c measures each refusal and names which rule gave it.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- Members r18-01 .. r18-60. More than are used; the unused ones cost nothing
-- and the numbering stays legible against the membership ids, which share it.
insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-5000000018' || lpad(n::text, 2, '0'))::uuid,
  '220000ff-0022-4000-8000-100000000001'::uuid,
  '220000ff-0022-4000-8000-200000000001'::uuid,
  'H22 R18 Member ' || lpad(n::text, 2, '0'),
  '+91922018' || lpad(n::text, 4, '0')
from generate_series(1, 60) as n;

insert into public.qr_sessions (id, tenant_id, branch_id, token_hash, expires_at, created_by_staff_id) values
  ('220000ff-0022-4000-8000-900000001801'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid,
   '220000ff-0022-4000-8000-200000000001'::uuid, 'h22-r18-gate-token-hash',
   now() + interval '1 day', '220000ff-0022-4000-8000-300000000001'::uuid);

-- Memberships. Ids share the member numbering except where one member
-- deliberately holds two rows: 1801 holds 1801 (retired) and 1802 (live), and
-- 1822 holds 1822 (live) and 1823 (the OPEN-023 row nothing can activate).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000001801'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001801'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001802'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001801'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001803'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001802'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired',   (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001810'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001810'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   null, null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001811'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001811'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001812'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001812'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001813'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001813'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   null, null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001814'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001814'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001820'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001820'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   (select today from gym_today where org_key='A'), null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001821'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001821'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   null, (select today from gym_today where org_key='A') + 30, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001822'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001822'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001823'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001822'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   null, null, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001824'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001824'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'pending',   (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'USD'),
  ('220000ff-0022-4000-8000-600000001830'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001830'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001831'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001831'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001832'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001832'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001834'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001834'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001835'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001835'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001836'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001836'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired',   (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001837'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001837'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001839'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001839'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001840'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001840'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001841'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001841'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'expired',   (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001842'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001842'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001843'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001843'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001844'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001844'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001848'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001848'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001849'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001849'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001850'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001850'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001851'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001851'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001852'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001852'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  -- 1854 exists only to carry the gate's control admission. `app.enforce_check_in()`
  -- refuses a second scan by the same member inside the gym's 120-second window
  -- (GL014), so the "admitted while active" control and the "admitted while
  -- frozen" assertion cannot be the same member without measuring GL014 instead
  -- of ADR-084's status gate.
  ('220000ff-0022-4000-8000-600000001854'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001854'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active',    (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 25a. THE CHAIN ADR-096 KEPT, RE-RUN END TO END. ADR-096's words: money paid
-- while retired stays on record "because the membership might be revived and
-- the total would then count it — detaching that money would mean they bought
-- nothing and cannot get it back, which is a worse answer than the one this
-- rule was written to prevent." Requirement one deletes the premise. What is
-- left holding the money up is a chain of six links, and this file has broken
-- one link of a six-link chain twice. Each is asserted on its own.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001801', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001801', '220000ff-0022-4000-8000-600000001801', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/chain: LINK 1 — the cash is RECORDED against the cancelled membership. Refusing it is the harm ADR-096 named: the money is already in the drawer when the row is written, and a refusal leaves the gym holding it with nothing to show');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001801'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/chain: LINK 2 — and it does not extend the retired row by a day or a period (round thirteen''s rule, re-asserted here because everything below depends on the money being STUCK rather than spent)');

select is(
  left(coalesce((select receipt_number from public.payments where id = '220000ff-0022-4000-8000-700000001801'::uuid), '(null)'), 7),
  (select fy from gym_today where org_key = 'A'),
  'r18/chain: LINK 3 — it is receipted, and from the gym''s own financial-year counter rather than a placeholder. The receipt is what the member holds when they come back to ask for the money; a build that suppresses it along with the extension takes away the only proof the cash arrived');

select is(
  (select recorded_by_staff_id::text from public.payments where id = '220000ff-0022-4000-8000-700000001801'::uuid),
  '220000ff-0022-4000-8000-300000000001',
  'r18/chain: LINK 4 — GL034 attribution survives. Money that nobody is recorded as having taken is money nobody can be asked about');

select is(
  (select status::text from public.payments where id = '220000ff-0022-4000-8000-700000001801'::uuid),
  'paid',
  'r18/chain: and the payment really is `paid`, not quietly demoted to `created` by a guard that decided a payment which grants nothing is not a payment');

select ok(
  pg_temp.h22r8_refused($q$update public.payments set membership_id = '220000ff-0022-4000-8000-600000001802' where id = '220000ff-0022-4000-8000-700000001801'$q$),
  'r18/chain: LINK 5 — the obvious shortcut is CLOSED. Re-pointing the paid payment onto the member''s live membership would move the money without moving any cash, and the payment identity freeze refuses it. This is what makes the requirement''s remedy — refund, then take it again — the ONLY remedy rather than the recommended one');

select is(
  (select membership_id::text from public.payments where id = '220000ff-0022-4000-8000-700000001801'::uuid),
  '220000ff-0022-4000-8000-600000001801',
  'r18/chain: and the payment still names the retired membership after that refusal');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000001801', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000001801', 'refund', 100000, 'h22 r18: paid against a retired membership, refunded in full', '220000ff-0022-4000-8000-300000000002')$$,
  'r18/chain: LINK 6 — the whole amount comes back out. This is the sentence requirement two turns on, and it is the one a fix that freezes everything about a retired membership breaks first, because the refund is written on `refunds` and read against `payments` and neither is the row anybody was trying to protect');

select is(
  pg_temp.h22r17_state($$update public.refunds set status = 'completed', processed_at = now() where id = '220000ff-0022-4000-8000-800000001801'$$),
  'OK',
  'r18/chain: and it COMPLETES. A refund stuck at `requested` is money still in the gym''s hands; the member is only made whole at this statement');

select ok(
  pg_temp.h22r17_gl($q$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id) values ('220000ff-0022-4000-8000-800000001802', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000001801', 'refund', 1, 'h22 r18: one paisa over the ceiling', '220000ff-0022-4000-8000-300000000002')$q$),
  'r18/chain: and GL036 still bounds it at exactly what was taken — one paisa more is refused. "Refundable in full" is a ceiling, not a licence, and being attached to a retired membership neither raises nor lowers it');

select is(
  (select coalesce(sum(amount_paise), 0)::text from public.refunds where payment_id = '220000ff-0022-4000-8000-700000001801'::uuid),
  '100000',
  'r18/chain: exactly Rs.1,000 refunded against exactly Rs.1,000 taken');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001801'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/chain: and the retired membership is STILL unmoved after the refund. Nothing about money leaving may touch the row either — a rule that recomputes dates or periods from live payments would fire here, on the statement furthest from anywhere anyone would look');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001802', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001801', '220000ff-0022-4000-8000-600000001802', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/chain: THE REMEDY COMPLETED — the same Rs.1,000 is taken again against the member''s LIVE membership. The requirement''s third scenario, and the whole point of the second');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001802'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r18/chain: and it grants that membership one period, thirty days. ROUND-TWENTY RECONCILIATION: this live membership has both dates and no previously granted period, so recollecting after the refund sets its span from today. The member ends up exactly where an original payment against the correct membership would have placed them');

-- The same chain on `expired`, shortened to the two links that could
-- plausibly differ: `expired` is a distinct enum value, and a fix keyed on
-- `cancelled_at is not null` (the column the cancel path also writes) passes
-- everything above and nothing here.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001803', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001802', '220000ff-0022-4000-8000-600000001803', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/chain/expired: money named against a LAPSED membership is recorded too');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001803'),
  'expired/' || ((select today from gym_today where org_key='A') - 40)::text || '..' || ((select today from gym_today where org_key='A') - 10)::text || '/0',
  'r18/chain/expired: and does not move it');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select lives_ok(
  $$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id)
    values ('220000ff-0022-4000-8000-800000001803', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000001803', 'refund', 100000, 'h22 r18: lapsed membership, money back', '220000ff-0022-4000-8000-300000000002')$$,
  'r18/chain/expired: and it too is refundable in full — the second requirement says `cancelled` OR `expired`, and this is the half nothing in the product ever writes and the seed writes twice');

select ok(
  pg_temp.h22r17_gl($q$insert into public.refunds (id, tenant_id, payment_id, kind, amount_paise, reason, initiated_by_staff_id) values ('220000ff-0022-4000-8000-800000001804', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-700000001803', 'refund', 1, 'h22 r18: over the ceiling on the lapsed one', '220000ff-0022-4000-8000-300000000002')$q$),
  'r18/chain/expired: bounded by GL036 at the same paisa');

-- ---------------------------------------------------------------------------
-- 25b. WHERE THE GRANTING RULE WRITES STATUS ITSELF. The spec's fourth
-- scenario — "the granting rule activates a `pending` membership" — is the
-- one transition the rule performs rather than polices, so every plausible
-- implementation has an exemption in it, and the exemption is the only new
-- attack surface this requirement creates. Three questions: does the rule's
-- own write still land; can a hand-written statement stand where the rule
-- stands; and can a payment be made to drive an ILLEGAL transition through
-- the rule rather than around it.
-- ---------------------------------------------------------------------------

-- Back to the desk: 25a ended on a manager's claim for its refunds, and a
-- payment is recorded by the staff member who took it (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001810', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001810', '220000ff-0022-4000-8000-600000001810', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/rule: the rule''s own transition — a dateless `pending` membership takes its first payment');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001810'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r18/rule: and is ACTIVATED by it. `pending -> active` written by the granting rule, which the requirement permits by name. A guard that cannot tell its own trigger''s write from a session''s fails here and leaves every new member refused at the gate they just paid to walk through');

select ok(
  pg_temp.h22r17_gl($q$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000001811', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001811', '220000ff-0022-4000-8000-600000001811', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning membership_id) update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id in (select membership_id from p)$q$),
  'r18/rule/imitation: A HAND IMITATING THE RULE. One statement: take the money, then write `cancelled -> active` on the row it was taken against. This is the granting rule''s own shape — a payment and an activation, together — and if the exemption is keyed on "a payment is being processed" rather than on WHO is writing, this is the statement that walks through it');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001811'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/rule/imitation: and the membership is untouched — still cancelled, still on its own dates, still granted nothing');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-700000001811'::uuid),
  'r18/rule/imitation: and the payment inside that CTE did not land either. Worth knowing rather than assuming: 25a records a bare payment against a retired membership BECAUSE the cash is real, and here the identical payment is rolled back because it was carried in on an illegal edit. The desk that composes the two loses the receipt; the desk that writes them separately keeps it');

select ok(
  pg_temp.h22r17_gl($q$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000001812', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001814', '220000ff-0022-4000-8000-600000001814', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning tenant_id) update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001811' and exists (select 1 from p)$q$),
  'r18/rule/carrier: the same shape with an ENTIRELY LEGITIMATE payment as the carrier — a different member, a live membership, a real renewal — and the revival hidden behind it on a row the payment never names. A guard that asks "is a payment in flight" rather than "did the rule write this" cannot tell these two statements apart');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001811'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/rule/carrier: unchanged');

select ok(
  not exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-700000001812'::uuid),
  'r18/rule/carrier: and the legitimate renewal was rolled back with it — a statement is refused whole, so nobody is left having banked half of one');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001814'),
  'active/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/rule/carrier: and the live membership the carrier named was not extended either');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: sold, never paid, walked away' where id = '220000ff-0022-4000-8000-600000001812'$$,
  'r18/rule/from-pending: a membership sold and never paid for is cancelled. `pending -> cancelled` is legal and is the ONLY exit a never-paid sale has');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001813', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001812', '220000ff-0022-4000-8000-600000001812', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/rule/from-pending: they then change their mind and pay — money against a membership that reached `cancelled` FROM `pending`, which is the exact source the rule''s activation branch was written for');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001812'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/rule/from-pending: and the rule does NOT activate it. This is the illegal transition driven through the granting rule rather than by hand: a build whose activation branch reads "has never been granted a period" or "activated_at is null" instead of "is pending" writes `cancelled -> active` here, from a trigger, with no session to blame');

select lives_ok(
  $$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000001814', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001813', '220000ff-0022-4000-8000-600000001813', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning tenant_id) select count(*) from p$$,
  'r18/rule/control: THE SAME CTE SHAPE, LEGAL — a payment inside a data-modifying CTE against a dateless `pending` membership. Without this the two refusals above would be satisfied by a build that simply cannot write a payment inside a CTE at all, and both would pass for the wrong reason (ADR-078)');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001813'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r18/rule/control: and the rule activated it from inside the CTE, exactly as it does from a plain INSERT');

-- ---------------------------------------------------------------------------
-- 25c. THE MALFORMED ROWS. OPEN-026 records a `pending` membership with one
-- null date — reachable only by direct write, and `memberships_dated_unless_
-- pending_chk` permits it only while the row stays `pending`. OPEN-023 records
-- a dateless `pending` row belonging to a member who is already covered, which
-- the granting rule cannot activate because the live index permits one. And
-- ADR-089's list of the rule's five early returns includes a currency
-- mismatch, which leaves a fourth shape: paid, dated, and still `pending`.
--
-- The question is not whether these are refused. It is whether a transition
-- rule makes any of them PERMANENTLY unrepairable, and whether that is right.
-- Each refusal below is measured for which rule gave it, because "this rule
-- sealed the row" and "this rule found the row already sealed" are different
-- findings and only one of them is this round's problem.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001820'$q$),
  'r18/malformed/026a: a `pending` row with a starts_on and NO ends_on cannot be activated. `pending -> active` is a legal transition and this is refused anyway — by the Phase 1 CHECK, which permits a null date only while the status is `pending`. Asserted through the code-agnostic probe on purpose: the finding is that the row is sealed, not which rule sealed it');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001820'),
  'pending/' || (select today from gym_today where org_key='A')::text || '..-/0',
  'r18/malformed/026a: and it is unchanged — still pending, still half-dated');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: give up on it' where id = '220000ff-0022-4000-8000-600000001820'$q$),
  'r18/malformed/026a: nor can it be CANCELLED — the same CHECK. Both of the two exits the new transition table gives a `pending` row are closed on this shape, so the row cannot leave `pending` by any legal move');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001820'),
  'pending/' || (select today from gym_today where org_key='A')::text || '..-/0',
  'r18/malformed/026a: unchanged again');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'cancelled', ends_on = (select today from gym_today where org_key='A') + 30, cancelled_at = now() where id = '220000ff-0022-4000-8000-600000001820'$q$),
  'r18/malformed/026a: AND THE ONE STATEMENT THAT WOULD REPAIR IT IS REFUSED TOO — supplying the missing date and the exit in one go, which is the only shape that could satisfy the CHECK, runs into GL045: the dates belong to the granting rule and to nobody else. Two rules, neither of them this round''s, and between them the row cannot be repaired by any single statement');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001820'),
  'pending/' || (select today from gym_today where org_key='A')::text || '..-/0',
  'r18/malformed/026a: unchanged a third time — the row is sealed, and it was sealed before round eighteen');

select diag(
  format('r18/malformed OBSERVED sqlstates on the half-dated `pending` row 1820: activate=%s, cancel=%s, cancel-with-date=%s. Round eighteen is not what seals this row — the first two are the Phase 1 CHECK and the third is GL045. Reported, not resolved: OPEN-026 already owns it, and whoever writes the membership-request flow it names should know that after this round a half-dated row has no legal status move left at all.',
    pg_temp.h22r8_try($q$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001820'$q$),
    pg_temp.h22r8_try($q$update public.memberships set status = 'cancelled', cancelled_at = now() where id = '220000ff-0022-4000-8000-600000001820'$q$),
    pg_temp.h22r8_try($q$update public.memberships set status = 'cancelled', ends_on = (select today from gym_today where org_key='A') + 30 where id = '220000ff-0022-4000-8000-600000001820'$q$)));

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001821'$q$),
  'r18/malformed/026b: the MIRROR shape — an ends_on and no starts_on, which is the one ADR-088''s backfill gave a periods_granted it never received. Same refusal');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001821'),
  'pending/-..' || ((select today from gym_today where org_key='A') + 30)::text || '/0',
  'r18/malformed/026b: unchanged');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'cancelled', cancelled_at = now() where id = '220000ff-0022-4000-8000-600000001821'$q$),
  'r18/malformed/026b: and cannot be cancelled either');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001821'),
  'pending/-..' || ((select today from gym_today where org_key='A') + 30)::text || '/0',
  'r18/malformed/026b: unchanged');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001820', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001822', '220000ff-0022-4000-8000-600000001823', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/malformed/023: OPEN-023''s row — a dateless `pending` membership whose member is ALREADY covered by a live one — takes its money');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001823'),
  'pending/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r18/malformed/023: MEASURED, not assumed, and sharper than OPEN-023 describes: the rule DATES the row and GRANTS it a period, and declines only the ACTIVATION — the half the live index would refuse. So the member has bought thirty days on a row their own gate reads as `pending` and turns them away from. OPEN-023 calls this "the second keeps its dates and stays pending, which is right today because the member is covered"; the money is what makes it not merely a bookkeeping shape');

select ok(
  pg_temp.h22r8_refused($q$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001823'$q$),
  'r18/malformed/023: and it cannot be activated by hand while the member''s other membership is live — refused by `memberships_tenant_id_member_id_live_key`, not by this round''s rule. Asserted through the code-agnostic probe for exactly that reason: `pending -> active` is a legal transition and something else is saying no');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: the covering membership ends' where id = '220000ff-0022-4000-8000-600000001822'$$,
  'r18/malformed/023: THE COVERING MEMBERSHIP IS THEN RETIRED, freeing the live index — the exact moment OPEN-023 says the pending row should come into force');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001823'$$,
  'r18/malformed/023: AND NOW IT CAN BE ACTIVATED BY HAND. This is the permitted-side assertion OPEN-023 hangs on: `pending -> active` is legal, the row has the dates the granting rule gave it, and the index is free. Nothing AUTOMATIC activates it — that is what OPEN-023 is about and this round does not fix it — but the manual repair exists and must not be taken away by a transition rule that treats a long-stale `pending` row as retired');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001823'),
  'active/' || (select today from gym_today where org_key='A')::text || '..' || ((select today from gym_today where org_key='A') + 30)::text || '/1',
  'r18/malformed/023: and the member is let in on the thirty days they paid for');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000001821', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001824', '220000ff-0022-4000-8000-600000001824', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'r18/malformed/currency: the fourth shape — rupees arriving against a membership priced in dollars. The rule returns early on a currency mismatch (ADR-089 lists it as one of its five)');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001824'),
  'pending/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/malformed/currency: so the money is banked and the membership is not activated — dated, paid, and still `pending`');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001824'$$,
  'r18/malformed/currency: AND THIS ONE IS STILL REPAIRABLE BY HAND. `pending -> active` is legal, the row has both dates so the CHECK is satisfied, and nothing about the mismatched money may stand in the way. This is the permitted-side assertion an over-broad fix breaks — a rule written as "refuse a status move on a row whose periods and money disagree" passes every refusal in this section and seals the one shape that was not sealed');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001824'),
  'active/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/malformed/currency: and it landed — the member is admitted at the gate again while the gym works out which currency it meant');

-- ---------------------------------------------------------------------------
-- 25d. MULTI-ROW AND MULTI-STATEMENT. Every defect this phase has shipped
-- survived the single-row UPDATE and died on one of these, and a state machine
-- is the worst case of the pattern: the legal move and the illegal one are the
-- same column, so a rule that evaluates the STATEMENT rather than each row has
-- a legitimate cancellation to wave the revival through beside it.
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.h22r17_gl($q$merge into public.memberships m using (select '220000ff-0022-4000-8000-600000001831'::uuid as id) s on m.id = s.id when matched then update set status = 'active'$q$),
  'r18/multi/merge: MERGE. Round nine measured this shape landing against an implementation that refused the plain UPDATE, which is why it is asked rather than assumed');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001831'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/merge: unchanged');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships m set status = v.s, cancelled_at = case when v.s = 'cancelled' then now() else m.cancelled_at end from (values ('220000ff-0022-4000-8000-600000001830'::uuid, 'cancelled'::public.membership_status), ('220000ff-0022-4000-8000-600000001831'::uuid, 'active'::public.membership_status)) as v(id, s) where m.id = v.id$q$),
  'r18/multi/per-row: ONE STATEMENT, A DIFFERENT TARGET STATUS PER ROW — the first an entirely ordinary cancellation, the second the revival. A rule that reads the statement rather than each row sees a legitimate retirement and lets both through');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001830'),
  'active/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/per-row: and the LEGITIMATE row did not land either — a statement is refused whole, so the desk is never left unable to tell which half of its edit took');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001831'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/per-row: the revived row is unchanged');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: end of year clear-out' where id in ('220000ff-0022-4000-8000-600000001836', '220000ff-0022-4000-8000-600000001837')$q$),
  'r18/multi/same-target: ONE TARGET, TWO SOURCES — `active -> cancelled` is legal and `expired -> cancelled` is not, in a single statement with the same SET clause. This is the shape a bulk end-of-year tidy-up actually has, and the discriminator is the source, which a rule keyed on the target alone does not have');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001837'),
  'active/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/same-target: the legal row is unchanged, because the statement was refused whole');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001836'),
  'expired/' || ((select today from gym_today where org_key='A') - 40)::text || '..' || ((select today from gym_today where org_key='A') - 10)::text || '/0',
  'r18/multi/same-target: and the retired row is unchanged');

select ok(
  pg_temp.h22r17_gl($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values ('220000ff-0022-4000-8000-600000001835', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001835', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR') on conflict (id) do update set status = excluded.status$q$),
  'r18/multi/upsert: `INSERT … ON CONFLICT (id) DO UPDATE SET status = excluded.status` — an UPDATE wearing an INSERT''s clothes, and the exact statement shape both seed files use. A rule attached to the UPDATE path by name rather than to the write itself is the plausible way to miss it');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001835'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/upsert: unchanged');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000001832'$$,
  'r18/multi/chain: statement one of a chain — the member pauses');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: paused, then left' where id = '220000ff-0022-4000-8000-600000001832'$$,
  'r18/multi/chain: statement two — they do not come back and the gym retires it. `frozen -> cancelled` is legal');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001832'$q$),
  'r18/multi/chain: statement three is REFUSED. Three statements, one transaction: a rule that compares against the status the row held when the transaction opened sees `active` here and waves it through. The comparison has to be against the row as it now stands');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001832'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/chain: and it is still cancelled');

select lives_ok(
  $$update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: two-statement probe' where id = '220000ff-0022-4000-8000-600000001834'$$,
  'r18/multi/two-statement: the same seam at its shortest — one legal retirement');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000001834'$q$),
  'r18/multi/two-statement: and `cancelled -> frozen` immediately after is refused. `frozen` is the OTHER member of the live partial unique index, so a rule that guards only the revival to `active` leaves a second door into the same live set — and a frozen membership is admitted at the gate exactly as an active one is');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001834'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/two-statement: unchanged');

select lives_ok(
  $$with p as (insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id) values ('220000ff-0022-4000-8000-700000001830', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001839', '220000ff-0022-4000-8000-600000001839', 100000, 'INR', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001') returning membership_id) update public.memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'h22 r18: paid the arrears and left in the same breath' where id in (select membership_id from p)$$,
  'r18/multi/cte-legal: THE PERMITTED HALF OF THE SAME SHAPE — a data-modifying CTE that takes a payment and cancels the membership in one statement, both legal. The refusals in 25b are about which transition, not about the shape, and without this one they could be satisfied by a build that refuses every CTE that touches both tables');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001839'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/multi/cte-legal: and BOTH halves landed — but the money BOUGHT NOTHING. MEASURED, and staged rather than sided: the extension runs from an AFTER STATEMENT trigger, so by the time it looks at the membership the same statement has already cancelled it, and round thirteen''s rule correctly refuses to extend a retired row. Rs.1,000 banked, receipt issued, zero days granted, one statement, no error. Reported below');

select ok(
  exists (select 1 from public.payments where id = '220000ff-0022-4000-8000-700000001830'::uuid and receipt_number is not null),
  'r18/multi/cte-legal: and the payment is really there with its receipt — which is what makes the line above a finding rather than a rollback');

select diag(
  'r18/multi/cte-legal REPORTED, not resolved: a single statement that takes a payment and cancels the membership in the same breath banks the money, issues the receipt and grants no period, because the statement-level extension trigger sees the row as already retired. Both halves are legal and neither rule is wrong; the ORDER is what nobody specified. It is the same money-strands-silently shape the membership-lifecycle spec''s second requirement answers for a payment named against an already-retired membership, arriving by a route that requirement does not describe — the membership was live when the desk started typing. Reachable only by a hand-written CTE today, which is why it is staged here rather than sided.');

-- ---------------------------------------------------------------------------
-- 25e. ROLES, TRUSTED CONTEXTS, AND THE SEED. `supabase/seed-scenarios.sql`
-- builds Sunita Bhosale's lapsed membership and Imran Sheikh's cancelled one
-- by writing `expired` and `cancelled` straight onto the row, and
-- `.github/workflows/db.yml`'s `seed-dry-run` runs seed.sql and
-- seed-scenarios.sql inside ONE transaction against the Cloud project where
-- `seed.yml` has already committed both — so on every CI run those writes
-- arrive as the `on conflict (id) do update set status = excluded.status` half
-- of an upsert, with the value unchanged. This project has turned that job red
-- on a rule written days earlier twice.
--
-- The answer, measured rather than hoped: the seed needs NO change and the
-- rule needs NO role carve-out. The seed only ever CREATES a terminal status
-- or writes one back to itself, and this requirement permits both — the
-- self-write by name, the creation by silence. Both halves are asserted below
-- in the seed's own statement shape rather than a paraphrase of it.
--
-- The carve-out is then refused on ADR-082's distinction, drawn here the way
-- 20c draws it: a trusted-caller carve-out is sound where the rule's subject
-- is an IDENTITY a trusted caller legitimately lacks (GL046 — which staff role
-- you are), and unsound where the subject is the DATA (GL036's ceiling, GL045's
-- dates). Which status may follow which is a fact about the row. So claimless
-- `postgres`, `service_role`, a gym owner and a gym manager are each refused a
-- revival, and the seed keeps working anyway, which is the whole argument.
--
-- The pair that matters most is the one with the trigger disabled. Both seed
-- files wrap their membership upserts in `alter table public.memberships
-- disable trigger memberships_terms_frozen`. A rule folded into THAT trigger
-- would be silently off for the entire seed, and would pass every other
-- assertion in this section.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  pg_temp.h22r17_state($$alter table public.memberships disable trigger memberships_terms_frozen$$),
  'OK',
  'r18/seed: the seed''s own preamble — both seed files disable `memberships_terms_frozen` around their membership upserts, so everything below runs in exactly the arrangement CI runs it in, not an approximation of it');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
      values ('220000ff-0022-4000-8000-600000001840', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001840', '220000ff-0022-4000-8000-400000000001', 'cancelled', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR')
      on conflict (id) do update set
        status      = excluded.status,
        starts_on   = excluded.starts_on,
        ends_on     = excluded.ends_on,
        price_paise = excluded.price_paise,
        currency    = excluded.currency$$),
  'OK',
  'r18/seed: THE SEED''S RE-RUN PATH ON A CANCELLED ROW. `cancelled -> cancelled` reaches the trigger as an ordinary UPDATE with OLD.status = NEW.status, and the requirement settles it by name — "a status written back to itself is allowed, it changes nothing". A rule that refuses every write whose NEW.status is terminal turns `seed-dry-run` red on the next push and the failure reads like a seed bug');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001840'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/seed: and the row converged rather than moved, which is the property the whole seed is built around');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
      values ('220000ff-0022-4000-8000-600000001841', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001841', '220000ff-0022-4000-8000-400000000001', 'expired', (select today from gym_today where org_key='A') - 40, (select today from gym_today where org_key='A') - 10, 100000, 'INR')
      on conflict (id) do update set
        status      = excluded.status,
        starts_on   = excluded.starts_on,
        ends_on     = excluded.ends_on,
        price_paise = excluded.price_paise,
        currency    = excluded.currency$$),
  'OK',
  'r18/seed: the same on the LAPSED row — the fixture the whole retention loop is demonstrated on. `expired -> expired`');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001841'),
  'expired/' || ((select today from gym_today where org_key='A') - 40)::text || '..' || ((select today from gym_today where org_key='A') - 10)::text || '/0',
  'r18/seed: converged');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
      values ('220000ff-0022-4000-8000-600000001845', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001845', '220000ff-0022-4000-8000-400000000001', 'cancelled', (select today from gym_today where org_key='A') - 20, (select today from gym_today where org_key='A') - 5, 100000, 'INR')$$),
  'OK',
  'r18/seed/create: THE FRESH-PROJECT PATH. On a database that has never been seeded the same statement is a plain INSERT, and a membership is CREATED already cancelled. The requirement is about a status that CHANGES and says nothing about one that is born — so this has to stay permitted, and if it is not, `seed-dry-run` goes red the first time somebody restores the project from scratch rather than on the next push, which is worse');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001845'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 20)::text || '..' || ((select today from gym_today where org_key='A') - 5)::text || '/0',
  'r18/seed/create: and it is really there, cancelled from birth');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
      values ('220000ff-0022-4000-8000-600000001846', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001846', '220000ff-0022-4000-8000-400000000001', 'expired', (select today from gym_today where org_key='A') - 70, (select today from gym_today where org_key='A') - 40, 100000, 'INR')$$),
  'OK',
  'r18/seed/create: born `expired` — literally seed-scenarios.sql''s row 102, offsets and all');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001846'),
  'expired/' || ((select today from gym_today where org_key='A') - 70)::text || '..' || ((select today from gym_today where org_key='A') - 40)::text || '/0',
  'r18/seed/create: there');

select is(
  pg_temp.h22r17_state($$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
      values ('220000ff-0022-4000-8000-600000001847', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001847', '220000ff-0022-4000-8000-400000000001', 'frozen', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 20, 100000, 'INR')$$),
  'OK',
  'r18/seed/create: and born `frozen` — seed-scenarios.sql''s row 101, Deepak Rane, whose paused membership the pause-decision battery is built on. Three statuses no transition reaches from nothing, all three created directly, all three permitted');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001847'),
  'frozen/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 20)::text || '/0',
  'r18/seed/create: there');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001849'$q$),
  'r18/seed/disabled-trigger: AND THE REVIVAL IS STILL REFUSED WITH `memberships_terms_frozen` DISABLED. This is the assertion that decides whether the seed can accidentally switch the rule off. Folding a fourth guard into the trigger both seed files already turn off would leave `memberships.status` unpoliced for the whole of `seed.yml` and the whole of `seed-dry-run`, and every other assertion in this section would still pass');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001849'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/seed/disabled-trigger: unchanged');

select is(
  pg_temp.h22r17_state($$alter table public.memberships enable trigger memberships_terms_frozen$$),
  'OK',
  'r18/seed: and the trigger is put back, exactly as both seed files put it back');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001842'$q$),
  'r18/role/no-claim: a session with NO JWT claim at all — `postgres`, the CLI, the seed itself — is refused the revival. SIDED, on ADR-082 as 20c reads it: carve out where the subject is an identity the caller lacks, do not where the subject is the data. Which status may follow which is a fact about the row, and the seed is proved above not to need the exemption');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001842'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/role/no-claim: unchanged');

select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001843'$q$),
  'r18/role/service_role: the Razorpay webhook''s role is refused it too. 19g already draws this line for GL045 — a hand-written date from service_role IS refused — and a revival is the same kind of fact');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001843'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/role/service_role: unchanged');

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_owner',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001844'$q$),
  'r18/role/owner: and the GYM OWNER is refused. The requirement says "any session" and means it — this is not a permission that a senior enough person may exercise, it is a move the data does not have. Every other rule in this phase that turned out to be about seniority (GL046) says so in its own words; this one does not');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001844'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/role/owner: unchanged');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001848'$q$),
  'r18/role/manager: and a manager. The critic''s measurement was taken from a front desk, and a fix aimed at the desk that leaves the roles above it able to revive has closed nothing — the console''s own repair flows run as a manager');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001848'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/role/manager: unchanged');

select diag(
  'r18/seed REPORTED, not resolved: creation is not a transition and the requirement never says so. Every sentence in it governs a status that CHANGES, and the three assertions above create memberships directly at `cancelled`, `expired` and `frozen` with nothing raised — which is what the seed''s fresh-project path does and what this file''s own fixture block does thirty times. It has to stay permitted, so nothing here argues otherwise; but "terminal" currently means "no transition reaches it and none leaves it", not "the database will not hold one that was never alive". OPEN-029 already records that creation is unpoliced for dates. Same door, one column over.');

-- ---------------------------------------------------------------------------
-- 25f. THE GATE (ADR-084), AND THE ONE-WAY DOOR THIS REQUIREMENT BUILDS.
-- `app.enforce_check_in()` admits `active` and `frozen` and nothing else, so
-- every transition in the table is felt by a member at a door. Asserted as a
-- refused check-in rather than as a status column, because the column is what
-- three rounds of this phase have already proved can read one thing while the
-- member experiences another.
--
-- The second half of this subsection is the finding. The requirement's Purpose
-- names "a live membership written to `expired`" as one of its two silent
-- failures; its first requirement then retracts that in prose ("retiring a
-- membership early is not the defect") and its second scenario permits exactly
-- it. Both readings can be right — but only the retraction survives the
-- change, because making retirement terminal converts that write from a
-- reversible mistake into an irreversible one. Measured at the door.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001850', '220000ff-0022-4000-8000-600000001850', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  null::char(5), null,
  'r18/gate: a cancelled membership with ten days left on its dates does not admit its member');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active', cancelled_at = null, cancel_reason = null where id = '220000ff-0022-4000-8000-600000001850'$q$),
  'r18/gate: and the one statement that would let them in is refused. This is the critic''s measurement, taken at the place the member stands rather than at the column');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001850'),
  'cancelled/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/gate: status unchanged');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001850', '220000ff-0022-4000-8000-600000001850', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  null::char(5), null,
  'r18/gate: and they are still refused afterwards — the consequence, not the column. A build that refuses the UPDATE and admits them anyway has not closed anything, and a build that raises a code nobody maps has closed it in a way the desk cannot explain');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001854', '220000ff-0022-4000-8000-600000001854', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  'r18/gate/control: a member on a live membership walks through the SAME QR session — the refusal above is the status, not the fixture');

select lives_ok(
  $$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000001851'$$,
  'r18/gate/pause: they then go on a pause. `active -> frozen`');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001851', '220000ff-0022-4000-8000-600000001851', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  'r18/gate/pause: and are STILL admitted, because the gate reads `frozen` as live. A fix that treats everything-but-active as retired closes this door on a paying member mid-pause, and the pause-decision battery one file over is built entirely on this status');

select lives_ok(
  $$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001851'$$,
  'r18/gate/pause: and back. `frozen -> active` in both directions, which is the one round trip the transition table has');

select lives_ok(
  $$update public.memberships set status = 'expired' where id = '220000ff-0022-4000-8000-600000001852'$$,
  'r18/door: THE ONE-WAY DOOR OPENS. An ordinary FRONT-DESK session writes `expired` onto a membership live for another ten days, in one statement, with nothing raised. Legal — the requirement''s second scenario permits it by name and its prose insists that retiring early is not the defect');

select throws_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001852', '220000ff-0022-4000-8000-600000001852', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  null::char(5), null,
  'r18/door: and the member is refused at the door from that moment, with ten days of paid-for time still on the row');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'active' where id = '220000ff-0022-4000-8000-600000001852'$q$),
  'r18/door: and it cannot be undone. Before this round the desk''s mistake was one statement away from repair; after it, the same mistake is permanent. The requirement''s own Purpose names this write as a silent failure and its requirement retracts the naming — both are defensible, but only one of them survives making retirement terminal, and it is worth saying which');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001852'),
  'expired/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/door: status unchanged, and the dates still say the member has ten days');

select ok(
  pg_temp.h22r17_gl($q$update public.memberships set status = 'frozen' where id = '220000ff-0022-4000-8000-600000001852'$q$),
  'r18/door: nor by the side entrance — `expired -> frozen` puts the row back inside the live index and the gate just as `active` would, and a rule that guards only the obvious target leaves this one open');

select is(
  pg_temp.h22r13_shape('220000ff-0022-4000-8000-600000001852'),
  'expired/' || ((select today from gym_today where org_key='A') - 10)::text || '..' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r18/door: unchanged');

select lives_ok(
  $$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-600000001853', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000001852', '220000ff-0022-4000-8000-400000000001', 'active', (select today from gym_today where org_key='A'), (select today from gym_today where org_key='A') + 30, 100000, 'INR')$$,
  'r18/door/repair: THE REPAIR THAT DOES EXIST — the same member is sold a NEW membership, which the live index now permits precisely because the old row was retired. This is what bounds the harm, and it must keep working or "terminal" becomes "the member is finished"');

select lives_ok(
  $$insert into public.attendance (tenant_id, branch_id, member_id, membership_id, checked_in_at, source, qr_session_id)
    values ('220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-200000000001', '220000ff-0022-4000-8000-500000001852', '220000ff-0022-4000-8000-600000001853', now(), 'qr', '220000ff-0022-4000-8000-900000001801')$$,
  'r18/door/repair: and they walk through the gate again on it. So the residue of the one-way door is a lost ROW — its dates, its periods and any money attached to it — and not a lost member');

select diag(
  'r18/door REPORTED: `active -> expired` from a front desk, in one statement, on a membership live for another ten days, is legal by this requirement and irreversible after it. The Purpose paragraph names that exact write as one of the two silent failures the change exists to stop; the requirement body retracts the naming and the second scenario permits it. The retraction is the reading this section tests, because the alternative — refusing early retirement — would refuse the cancellation half of the repair path this codebase prescribes for every mis-sold membership. What changes is the cost of the mistake: the money and dates on the retired row are now unreachable (25a''s answer is refund and re-take, which needs a payment to have been recorded, and an early `expired` write strands the DATES rather than money). Worth an explicit decision rather than an inherited one, and it is not a decision this file can make.');
-- ---------------------------------------------------------------------------
-- 26. ROUND NINETEEN, WHICH RULE ANSWERS. Written blind by a TENTH author
-- from the contract alone.
--
-- THE DEFECT CLASS: a migration re-emitted one enforcing function and moved
-- one refusal check after another. Both rules still refused, so every
-- assertion in both suites stayed green — because no assertion named a
-- single statement that violates TWO rules at once. Which rule answers is
-- part of the behaviour: the caller acts on the message, and the wrong
-- rule's message sends them to the wrong repair.
--
-- Not read by this author: any migration; supabase/tests/22_payment_record.sql;
-- docs/decisions.md; docs/registry.md; any function body. Read: the four
-- specs (payment-record, manual-payment, receipts-and-renewal,
-- membership-and-money) and docs/domain-rules.md.
--
-- The `member_id` / `duration_days` pair the payment-record spec settles by
-- name (GL042 before GL043) is deliberately ABSENT — it is covered by
-- another author. Everything below is a DIFFERENT two-rule statement.
--
-- Every assertion here is a triangle, never a lone pair: each rule is first
-- proven to answer ALONE with its own code, and only then is the statement
-- that violates both asserted. A pair assertion without its two controls is
-- worthless — it goes green just as readily when one of the two rules never
-- fires at all.
--
-- WHAT THE SPEC ACTUALLY DECIDES, and the only two sentences relied on:
--
--   1. GL042 beats everything. "**And it SHALL be this rule that answers,
--      not another one the same statement also violates.**" The sentence is
--      normative and unqualified; the length case that follows it is an
--      illustration, not its scope. So GL042 is asserted against GL044,
--      GL045 and GL046.
--
--   2. An absolute beats a permission. "A membership that has already taken
--      money is refused by the freeze above, not by this rule — an absolute
--      beats a permission, and answering the permission would imply a gym
--      admin could do it, which they cannot." GL046 is the only permission
--      in this family (it asks WHO you are); GL043, GL044 and GL045 each
--      bind every session including a gym admin. So each of the three is
--      asserted ahead of GL046, and the tell the spec itself gives is the
--      repair advice: GL046 says "fetch a manager", which is advice that
--      WORKS for an unfrozen row and is a lie for a frozen one.
--
-- What this section refuses to guess is reported by `diag` at the end:
-- five pairs the contract leaves genuinely undecided. Those are findings
-- about the contract, and inventing an order for them would be the same
-- mistake as the one this section exists to catch, made on purpose.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

create function pg_temp.h22r19_shape(mid text) returns text
language plpgsql as $fn$
declare r text;
begin
  execute format(
    'select member_id::text || %L || price_paise::text || %L || coalesce(ends_on::text, ''-'') || %L || periods_granted::text from public.memberships where id = %L',
    '/', '/', '/', mid) into r;
  return coalesce(r, 'NO ROW');
exception when others then
  return 'ERR:' || sqlstate;
end
$fn$;

grant execute on function pg_temp.h22r19_shape(text) to public;

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('220000ff-0022-4000-8000-500000001901'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R19 Free Terms',   '+919220190001'),
  -- The spare. It holds NOTHING, which is the whole point: the spec warns
  -- that `memberships_tenant_id_member_id_live_key` answers a re-point onto
  -- a member who already holds a live membership, and a careless fixture
  -- there reports a false GREEN for every GL042 assertion below.
  ('220000ff-0022-4000-8000-500000001902'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R19 Spare Holder', '+919220190002'),
  ('220000ff-0022-4000-8000-500000001903'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-200000000001'::uuid, 'H22 R19 Money Arrived','+919220190003');

-- MF: no money has ever arrived against it, so GL043 is NOT armed on it and
-- every statement below it can violate exactly the two rules it names.
-- MM: money has arrived and nothing has been granted, which is the state the
-- spec insists arms the freeze ("frozen by the first payment, not by the
-- first period"). Both are `active` and fully dated, so
-- `memberships_dated_unless_pending_chk` can never be the thing that answers.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency) values
  ('220000ff-0022-4000-8000-600000001901'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001901'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR'),
  ('220000ff-0022-4000-8000-600000001903'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001903'::uuid, '220000ff-0022-4000-8000-400000000001'::uuid, 'active', (select today from gym_today where org_key='A') - 10, (select today from gym_today where org_key='A') + 10, 100000, 'INR');

-- Half the price: money arrives, nothing is granted, and the dates and the
-- count both stay exactly where the fixture put them. A full-price payment
-- would arm the freeze just as well but would move `ends_on` and
-- `periods_granted`, and then an assertion that the row is "unchanged" would
-- be asserting the granting rule instead of the refusal.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
  ('220000ff-0022-4000-8000-700000001901'::uuid, '220000ff-0022-4000-8000-100000000001'::uuid, '220000ff-0022-4000-8000-500000001903'::uuid, '220000ff-0022-4000-8000-600000001903'::uuid, 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'::uuid);

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001903'),
  '220000ff-0022-4000-8000-500000001903/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/fixture: MM has taken half its price — money has ARRIVED, so the terms freeze is armed, and nothing has been GRANTED, so the dates and the count are still the fixture''s. Both halves matter: an implementation that armed the freeze on the first granted period instead of the first paisa makes every GL043 assertion below moot, and this row is what tells the difference');

-- ---------------------------------------------------------------------------
-- 26a. The controls. Each rule, alone, answering with its own code.
-- ---------------------------------------------------------------------------

-- GL043 alone: a GYM ADMIN, so the permission rule cannot possibly be what
-- answers. "A gym admin after money has arrived — it SHALL still be refused —
-- being a gym admin does not unfreeze what money has bought."
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'gym_manager',
                     'staff_id', '220000ff-0022-4000-8000-300000000002')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001903'$$,
  'GL043'::char(5), null,
  'r19/control GL043: a GYM MANAGER re-prices a membership that has taken money. Only the freeze can answer — the permission rule is satisfied by this session — so this pins GL043 to the freeze and nothing else. If this comes back GL046 the two codes are swapped and every pair below is measuring the wrong thing');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000000001',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000000001')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL046'::char(5), null,
  'r19/control GL046: the same re-price from a FRONT DESK, on a membership no money has ever reached. The freeze is not armed, so only the permission rule can answer — and its repair advice, "fetch a gym admin", is TRUE here. That is what makes it false in 26b/iv, where the same advice is given for a row no admin can touch either');

select throws_ok(
  $$update public.memberships set periods_granted = 3 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL044'::char(5), null,
  'r19/control GL044: the count is the rule''s to write and nobody else''s. Asserted on a value the granting rule could itself have produced, per the spec — "what is wrong is not the number, it is that a hand wrote it" — so no bound on the column can be what answers');

select throws_ok(
  $$update public.memberships set ends_on = ends_on + 3650 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL045'::char(5), null,
  'r19/control GL045: the dates are the granting rule''s to move. Ten years, one statement, an ordinary desk — the exact write the requirement was written against');

select throws_ok(
  $$update public.memberships set member_id = '220000ff-0022-4000-8000-500000001902' where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL042'::char(5), null,
  'r19/control GL042: the membership is re-pointed at a member who holds NOTHING live, so the live-membership index has nothing to say and only the rule can answer');

-- ---------------------------------------------------------------------------
-- 26b. The pairs. One statement, two rules, and the code the contract names.
-- ---------------------------------------------------------------------------

-- (i) GL042 before GL044.
select throws_ok(
  $$update public.memberships set member_id = '220000ff-0022-4000-8000-500000001902', periods_granted = 3 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL042'::char(5), null,
  'r19/pair GL042+GL044: one statement re-points the membership AND types a count onto it. "It SHALL be this rule that answers, not another one the same statement also violates" — unqualified, so it holds against the count rule exactly as it holds against the length rule. The repairs are not interchangeable: GL044 says "let a payment write it", which is advice about a membership that still belongs to the person on the receipt, and this one does not');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001901'),
  '220000ff-0022-4000-8000-500000001901/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL042+GL044: and NEITHER half landed — a refusal that let the count through would be the same defect wearing the right SQLSTATE');

-- (ii) GL042 before GL045.
select throws_ok(
  $$update public.memberships set member_id = '220000ff-0022-4000-8000-500000001902', ends_on = ends_on + 3650 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL042'::char(5), null,
  'r19/pair GL042+GL045: re-pointed AND re-dated in one statement. Same sentence, and the harm is the compound one GL042''s own requirement names — the receipt names one person, and now ten years land on another');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001901'),
  '220000ff-0022-4000-8000-500000001901/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL042+GL045: unchanged, dates included');

-- (iii) GL042 before GL046.
select throws_ok(
  $$update public.memberships set member_id = '220000ff-0022-4000-8000-500000001902', price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL042'::char(5), null,
  'r19/pair GL042+GL046: re-pointed AND re-priced, from a front desk, on a row no money has reached. TWO reasons the spec gives, pointing the same way: GL042''s "not another one the same statement also violates", and "an absolute beats a permission". GL046''s message would send this desk to fetch a manager for a statement no manager may make either');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001901'),
  '220000ff-0022-4000-8000-500000001901/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL042+GL046: unchanged, price included');

-- (iv) GL043 before GL046. The pair the spec settles in so many words.
select throws_ok(
  $$update public.memberships set price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001903'$$,
  'GL043'::char(5), null,
  'r19/pair GL043+GL046: ONE column, TWO rules — a front desk re-pricing a membership that has already taken money violates the freeze and the permission at once. "A membership that has already taken money is refused by the freeze above, not by this rule — an absolute beats a permission, and answering the permission would imply a gym admin could do it, which they cannot." Measured against 26a: the SAME statement text answers GL046 on MF and must answer GL043 here, and an implementation that checks the role first cannot tell the two apart');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001903'),
  '220000ff-0022-4000-8000-500000001903/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL043+GL046: and the membership stands as it stood, which both requirements demand in their own words');

-- (v) GL044 before GL046.
select throws_ok(
  $$update public.memberships set periods_granted = 3, price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL044'::char(5), null,
  'r19/pair GL044+GL046: a count typed alongside a price, from a front desk, on an unfrozen row. The absolute answers: GL044 binds every session, and answering the permission would tell this desk that a gym admin could type a count, which no session may do. The two exploits are also different sizes — a fetched manager can legitimately re-price, and can never legitimately set the count');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001901'),
  '220000ff-0022-4000-8000-500000001901/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL044+GL046: unchanged');

-- (vi) GL045 before GL046.
select throws_ok(
  $$update public.memberships set ends_on = ends_on + 3650, price_paise = 50000 where id = '220000ff-0022-4000-8000-600000001901'$$,
  'GL045'::char(5), null,
  'r19/pair GL045+GL046: ten years typed alongside a price. Same argument, and this is the pair where the wrong answer costs the most: GL046 tells the desk to fetch a manager, the manager re-prices the unfrozen row perfectly legally, and the date write that was the actual harm is never mentioned to anybody');

select is(
  pg_temp.h22r19_shape('220000ff-0022-4000-8000-600000001901'),
  '220000ff-0022-4000-8000-500000001901/100000/' || ((select today from gym_today where org_key='A') + 10)::text || '/0',
  'r19/pair GL045+GL046: unchanged, and MF ends this section exactly as the fixture wrote it — nine refused statements, no drift');

-- ---------------------------------------------------------------------------
-- 26c. UNDECIDED. Reported, not guessed.
-- ---------------------------------------------------------------------------

select diag(
  'r19 UNDECIDED 1/5 — GL038 vs GL039, and this is the payment-side twin of the pair the spec settles for memberships. One statement on a paid payment that sets `status` backwards AND edits `amount_paise` violates the freeze ("a payment that has been paid is a record") and the transition table at once. The two messages send the caller to opposite places: GL038 says the row is a record and the instrument is a refund, GL039 says that edge does not exist and implies the amount edit would have been fine at some other status. The spec orders neither. It is the same shape as the membership pair it DID decide, one table over, and it is worth deciding for the same reason.');

select diag(
  'r19 UNDECIDED 2/5 — GL034 vs GL035. A cash payment that both names a colleague as `recorded_by_staff_id` and carries a `provider_payment_id` violates the attribution rule and the no-provider-claim rule together. manual-payment/spec.md gives each its own requirement and no precedence. The repairs are unrelated: one is "you cannot record this on somebody else''s behalf", the other is "this row claims a verification nobody performed". Undecided — and the spec''s own thesis, that with no provider to verify against attribution IS the integrity, is an argument that GL034 should win, but it is an argument and not a sentence.');

select diag(
  'r19 UNDECIDED 3/5 — GL036 (money-arrived) vs GL040. A refund against a `created` payment, naming a colleague, is refused both because the payment never took money and because the refund names the wrong person. Neither requirement mentions the other. Materially different repairs: "refund a payment that actually arrived" against "you may only send money as yourself".');

select diag(
  'r19 UNDECIDED 4/5 — the refund amount-freeze has NO code in the contract at all, which makes one pair unassertable rather than merely undecided. "SHALL refuse any change to a refund''s `payment_id` or `amount_paise` once recorded" sits inside the GL036 requirement, while the paragraph that assigns codes sits inside the GL041 requirement and claims "a refund is a record" as GL041''s family. So a statement that demotes a `completed` refund AND raises its amount violates the completed-terminal rule and the amount freeze together, and the second one cannot be pinned to a SQLSTATE from the spec at all. Naming the code is a contract fix, not a test fix.');

select diag(
  'r19 UNDECIDED 5/5 — the order AMONG the absolutes is unwritten: GL043 vs GL044, GL043 vs GL045, GL044 vs GL045. The contract decides GL042 against everything ("not another one the same statement also violates") and every absolute against the one permission ("an absolute beats a permission"), and stops there. A statement setting `price_paise` and `ends_on` on a frozen membership, or `periods_granted` and `ends_on` on any membership, has no answer in the spec, and this section asserts none of them. Related: the payment-side GL042 ("a payment extends only the membership of the member who paid") shares a SQLSTATE with the membership-side rule but NOT its precedence sentence, which is written under the membership requirement and about it — so a payment naming another member''s membership and also naming a colleague is undecided too, despite that code appearing in decided pairs above.');

-- ---------------------------------------------------------------------------
-- 27. THIRTEENTH-SESSION EXTENSION, round TWENTY, written blind by an
-- ELEVENTH author against openspec/changes/membership-creation/ — reduced by
-- the coordinator, mid-authoring, to its ONE surviving requirement:
--
--   "THE FIRST PERIOD IS SET, NOT ADDED." Where a membership has been granted
--   no periods, the granting rule SETS its span from the plan rather than
--   extending a span it already carries.
--
-- The sibling requirement — a creation refused unless `ends_on <= starts_on +
-- the plan's duration`, GL048 — was WITHDRAWN before a line of this section
-- was committed, and this file asserts nothing about it. The orchestrator's
-- account, recorded here because it changes what the surviving requirement is
-- for: with the creation rule spliced in, six of the forty-seven pgTAP files
-- would not run at all and a seventh lost four assertions — 3087 assertions
-- reachable of 4152 — because six independently-authored suites build
-- multi-period memberships directly, a renewed membership genuinely spanning
-- several. The contract justified the rule from 45 live rows in one demo gym;
-- the rule bound every INSERT by anybody. Different populations, and nothing
-- in the measurement said so. The half-dated clause went with it: a row with
-- `ends_on` null carries no span, cannot be live at the turnstile, and is
-- inert to `app.grant_periods()` — whose dateless branch wants BOTH dates null
-- and whose dated branch wants `ends_on is not null` — so it was never this
-- change's harm.
--
-- WHICH LEAVES THE GRANT AS THE WHOLE OF THE DEFENCE, not half of it. A
-- membership may still be created spanning ten years, and the only thing
-- standing between that and a paid-for ten years is that the first period of
-- money SETS the span instead of adding to it. The change's own plan said this
-- was becoming "the load-bearing one"; it is now the only one.
--
-- Read by this author: the change's spec.md and plan.md, docs/domain-rules.md,
-- this file, the live catalogue's shape, and the coordinator's own measurement
-- above. NOT read, then or since: any migration; supabase/tests/22_payment_
-- record.sql, written in parallel by a different author; docs/decisions.md;
-- docs/registry.md; any function or trigger body.
--
-- WHERE THIS SECTION GOES. The requirement stages three scenarios — a typed
-- span paid once, a renewal, and the dateless path — and the visible suite
-- will have them. This one spends its weight on what none of the three
-- reaches:
--
--   * THE FIRST GRANT THAT GRANTS MORE THAN ONE PERIOD. Every scenario grants
--     exactly one, so "set its span from the plan" is never made to choose
--     between `duration` and `duration * periods`. Two half payments, one
--     double payment, two payments in one statement and two in two statements
--     are each run against a typed one-period span. Read literally, the
--     requirement's own sentence ("the span SHALL become exactly one period")
--     hands a member who paid for two months a single month.
--   * THE PATHS WHERE NOTHING IS GRANTED AND SO NOTHING MAY MOVE. A part
--     payment, a payment in a currency the membership is not priced in, and a
--     complimentary membership. The requirement is keyed on "has been granted
--     no periods", not on "no money has arrived", and these three are where
--     the two keys come apart. They also guard the other direction: a fix that
--     normalises the span whenever a payment lands would confiscate a free
--     month the gym deliberately gave.
--   * THE PLAN WHOSE PERIOD IS ONE DAY, where an off-by-one is a whole
--     period and where a rule that hardcoded thirty passes everything else.
--   * THE INVARIANT the requirement names in its own prose — `ends_on -
--     starts_on` against `duration_days * periods_granted` — asserted over
--     every path at once (27c), and asserted NOT to hold where it legitimately
--     does not. ADR-088 declined to enforce it as a trigger and was right to;
--     that is a reason to check it in a test, not a reason for nothing to
--     check it anywhere.
--
-- WHAT IT REFUSED TO GUESS is in 27e. The sharpest of them - "set its span
-- from the plan" fixes a LENGTH and said nothing about a POSITION - was raised
-- by this section as a staged measurement and has since been SETTLED in the
-- contract: the first grant starts a membership at the later of its `starts_on`
-- and today. 27d asserts that settlement rather than reporting it.
--
-- Fixtures are a gym of this section's own (`H22R20`) so nothing here can
-- move a row another section measures; every membership gets its own member,
-- because `memberships_tenant_id_member_id_live_key` is partial on
-- `active`/`frozen` and a second live row per member would answer 23505 for
-- the wrong reason. Every date is derived from `(now() at time zone
-- o.timezone)::date` through `gym_today`, never `current_date` (ADR-039): the
-- orchestrator's own probe read 31 days where the plan sells 30, purely
-- because it created the row on the UTC date and the rule dated it in IST.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

insert into public.organizations (id, name, gym_code, timezone) values
  ('220000ff-0022-4000-8000-100000002701'::uuid, 'Holdout PAYREC Gym R20', 'H22R20', 'Asia/Kolkata');

insert into public.branches (id, tenant_id, name, is_default) values
  ('220000ff-0022-4000-8000-200000002701'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, 'H22 R20 Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('220000ff-0022-4000-8000-300000002701'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, '220000ff-0022-4000-8000-200000002701'::uuid, 'front_desk', 'H22 R20 Desk');

-- Three plans. The 30-day paid plan carries most paths; the ONE-DAY one exists because
-- "set its span from the plan" has to read the plan, and a rule that reads a
-- constant, or reads the wrong row, is green on a suite built entirely of
-- thirty-day multiples. The complimentary path uses its own zero-priced plan:
-- the existing pricing contract permits the desk to sell at list, not to turn
-- a paid plan into a free membership. This fixture correction changes no
-- membership terms or grant assertions.
insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('220000ff-0022-4000-8000-400000002701'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, 'H22 R20 Plan 30d', 30, 100000),
  ('220000ff-0022-4000-8000-400000002702'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, 'H22 R20 Plan 1d',  1,  100000),
  ('220000ff-0022-4000-8000-400000002703'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, 'H22 R20 Plan Complimentary', 30, 0);

insert into gym_today (org_key, org_id, today, fy)
select 'R20', o.id, (now() at time zone o.timezone)::date, pg_temp.h22_fy((now() at time zone o.timezone)::date)
  from public.organizations o where o.id = '220000ff-0022-4000-8000-100000002701'::uuid;

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select
  ('220000ff-0022-4000-8000-50000000270' || f.sfx)::uuid,
  '220000ff-0022-4000-8000-100000002701'::uuid,
  '220000ff-0022-4000-8000-200000002701'::uuid,
  'H22 R20 ' || f.nm,
  '+919220270' || f.ph
from (values
  ('1','TypedOnePeriod','001'), ('2','ConsoleZeroSpan','002'), ('3','Dateless','003'),
  ('4','TwoHalves','004'),      ('5','DoubleAtOnce','005'),    ('6','TwoInOneStmt','006'),
  ('7','TwoStatements','007'),  ('8','ForeignCurrency','008'), ('9','ZeroPrice','009'),
  ('a','TenYears','010'),       ('b','OneDayPlan','011'),      ('c','FutureDated','012'),
  ('d','Lapsed','013')
) as f(sfx, nm, ph);

-- The section's own reader: offsets from THIS gym's today, never a literal,
-- with the span reported beside the count so the requirement's own invariant
-- can be read off one string.
create function pg_temp.h22r20_shape(mid text) returns text
language plpgsql as $fn$
declare r text; t date;
begin
  select today into t from gym_today where org_key = 'R20';
  execute format(
    'select coalesce((starts_on - %L::date)::text, ''-'') || ''/'' || '
    || 'coalesce((ends_on - %L::date)::text, ''-'') || ''/'' || '
    || 'coalesce((ends_on - starts_on)::text, ''-'') || ''/'' || '
    || 'periods_granted::text || ''/'' || status::text '
    || 'from public.memberships where id = %L', t, t, mid) into r;
  return coalesce(r, 'NO ROW');
exception when others then
  return 'ERR:' || sqlstate;
end
$fn$;

grant execute on function pg_temp.h22r20_shape(text) to public;

-- An ordinary front desk throughout — the session every measurement in this
-- change was taken from, and the one that records payments (GL034).
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000002701',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000002701')::text,
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 27a. NINE PATHS INTO A DATED MEMBERSHIP, ONE MEMBER EACH.
--
-- The nine are created in ONE multi-row statement, asserted once. That is
-- deliberate on two counts. It is the shape ADR-092 names as a measured route
-- into this table, and — after what the withdrawn requirement did to six other
-- suites — it is a standing assertion that WHATEVER implements "set, not
-- added" refuses no creation at all. The rule being asserted below lives in
-- the granting function; if a creation ever starts failing here, the fix has
-- wandered back to the door the contract just closed the book on.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    select ('220000ff-0022-4000-8000-60000000270' || f.sfx)::uuid,
           '220000ff-0022-4000-8000-100000002701'::uuid,
           ('220000ff-0022-4000-8000-50000000270' || f.sfx)::uuid,
           case when f.sfx = '9' then '220000ff-0022-4000-8000-400000002703'::uuid
                else '220000ff-0022-4000-8000-400000002701'::uuid end,
           f.st::public.membership_status,
           case when f.dated then (select today from gym_today where org_key='R20') + f.s0 end,
           case when f.dated then (select today from gym_today where org_key='R20') + f.e0 end,
           f.price, 'INR'
      from (values
        -- (1) the measured defect: one period typed, then one period paid for.
        ('1', 'active',  true,  0, 30, 100000),
        -- (2) what POST /api/memberships actually writes: zero span, active.
        ('2', 'active',  true,  0,  0, 100000),
        -- (3) the honest path the requirement says already works.
        ('3', 'pending', false, 0,  0, 100000),
        -- (4)-(7) four ways of paying for a typed one-period span.
        ('4', 'active',  true,  0, 30, 100000),
        ('5', 'active',  true,  0, 30, 100000),
        ('6', 'active',  true,  0, 30, 100000),
        ('7', 'active',  true,  0, 30, 100000),
        -- (8) priced in INR, about to be paid in USD.
        ('8', 'active',  true,  0, 30, 100000),
        -- (9) complimentary: no money can ever buy a period of it.
        ('9', 'active',  true,  0, 30, 0)
      ) as f(sfx, st, dated, s0, e0, price)$q$),
  'OK',
  'r20/fixtures: nine memberships, nine members, one multi-row statement. Asserted rather than assumed: the requirement that would have policed creation was withdrawn because it broke six suites'' fixtures, and this line is what notices if a fix for the SURVIVING requirement quietly re-imposes it. Every one of these spans at most one period anyway, so it is not the fixtures that are being defended — it is the door');

select is(
  (select string_agg(right(m.id::text, 2) || '=' || coalesce((m.starts_on - t.today)::text, '-') || '/' || coalesce((m.ends_on - t.today)::text, '-') || '/' || m.periods_granted::text || '/' || m.status::text, ' ' order by m.id)
     from public.memberships m, gym_today t
    where t.org_key = 'R20' and m.tenant_id = '220000ff-0022-4000-8000-100000002701'::uuid),
  '01=0/30/0/active 02=0/0/0/active 03=-/-/0/pending 04=0/30/0/active 05=0/30/0/active 06=0/30/0/active 07=0/30/0/active 08=0/30/0/active 09=0/30/0/active',
  'r20/fixtures: and every one of them landed where it was put, with `periods_granted = 0` on all nine. The count is the thing: it is the requirement''s KEY, so a fixture that arrived carrying a period would send every assertion below down the renewal branch and the whole section would pass without testing anything. Offsets are from this gym''s own today, so nothing here depends on the UTC date the suite happens to run on');

-- (1) THE MEASURED DEFECT, exactly as the change's own table A states it:
-- created `today .. today + 30` on a 30-day plan, then one payment of the
-- plan's price.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002701', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002701', '220000ff-0022-4000-8000-600000002701', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/typed-span: one ordinary cash payment at the plan''s own price. It must be RECORDED — the defect was never that a statement was refused, and a fix that refuses this has stopped the gym taking money');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002701'),
  '0/30/30/1/active',
  'r20/typed-span: THE HEADLINE. One period of money bought one period of membership. Today this row reads 0/60/60/1 — double the membership for the same money, with one payment, one receipt, `periods_granted = floor(money / price)`, the plan''s own price on the row and no frozen term touched. Nothing in this system compares the span against the count, which is why it audits clean and why this assertion has to exist');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027a1', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002701', '220000ff-0022-4000-8000-600000002701', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/typed-span: and the member renews');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002701'),
  '0/60/60/2/active',
  'r20/typed-span: THE RENEWAL STILL EXTENDS. "A renewal is untouched, which is the whole reason for the `periods_granted = 0` key." This is the mirror-image defect an over-eager reading of "set, not added" produces: a rule that SETS on every grant gives this member thirty days for their second month''s money, and the gym hears about it from the member, at the door, in a month');

-- (2) The console's own zero-span row. Green today, and here to fail an
-- over-broad fix: this is the path every real sale takes.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002702', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002702', '220000ff-0022-4000-8000-600000002702', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/zero-span: the console''s own sequence — `POST /api/memberships` writes today..today, then the desk takes the cash');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002702'),
  '0/30/30/1/active',
  'r20/zero-span: thirty days — which is also what it gives today. The zero-span row is the ONE shape where "set" and "add" agree, so it can never be the path a fix is validated on. ADR-083 records that this line used to add the duration and that the product has already been bitten by this doubling once');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027a2', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002702', '220000ff-0022-4000-8000-600000002702', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/zero-span: renewed');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002702'),
  '0/60/60/2/active',
  'r20/zero-span: sixty days on two periods');

-- (3) The dateless path — the requirement's "ordinary path", and the yardstick
-- for everything else: after the change, path (1) and path (3) must agree.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002703', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002703', '220000ff-0022-4000-8000-600000002703', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/dateless: a first payment against a `pending` membership with no dates at all');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002703'),
  '0/30/30/1/active',
  'r20/dateless: "it SHALL be dated from the plan exactly as it is today", and activated. The dateless branch is the one the requirement holds up as already correct, so it is the control for the whole section: today paths (1) and (3) differ by a factor of two on identical money, and after the change they must be indistinguishable');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027a3', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002703', '220000ff-0022-4000-8000-600000002703', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/dateless: renewed');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002703'),
  '0/60/60/2/active',
  'r20/dateless: sixty days on two periods. Three creations — a typed period, a zero span, and no dates at all — and one arithmetic at the end of them');

-- (4) TWO HALF PAYMENTS. The half that grants nothing must move nothing; the
-- half that completes the price must SET. A rule armed on "money has arrived"
-- rather than "a period has been granted" fires on the first half and dates a
-- membership nobody has finished paying for.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002704', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002704', '220000ff-0022-4000-8000-600000002704', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/halves: a typed one-period membership takes HALF its price');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002704'),
  '0/30/30/0/active',
  'r20/halves: and nothing moved, because nothing was granted. The typed span is still there and still unbought — which is now a permanent residual rather than a temporary one, since the creation rule that would have capped it was withdrawn. This row is exactly where "granted no periods" and "no money has arrived" disagree');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027a4', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002704', '220000ff-0022-4000-8000-600000002704', 50000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/halves: and the other half arrives, completing one period''s price across two receipts');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002704'),
  '0/30/30/1/active',
  'r20/halves: THIRTY DAYS, not sixty. The FIRST period is granted here by a payment that is not the first payment — so a fix that asks "is this the first payment against this membership" instead of "has this membership been granted a period" sets on the wrong one of the two. A part payment is exactly what walked through round eight''s gate, arriving from the other side');

-- (5) ONE payment worth TWO periods against a typed one-period span. Every
-- scenario in the requirement grants exactly one period, so this is where
-- "set its span from the plan" is made to choose between `duration` and
-- `duration * periods`.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002705', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002705', '220000ff-0022-4000-8000-600000002705', 200000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/double: a member pays two months up front against a membership already carrying a typed month');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002705'),
  '0/60/60/2/active',
  'r20/double: SIXTY days on two periods — `duration * periods_granted`, not `duration`. The requirement''s scenario sentence, "the span SHALL become exactly one period", is true of every case it stages because every case it stages grants one; read literally against this row it hands back thirty days for two months'' money. Today this row reads ninety, so the assertion is red against the current behaviour AND against the literal reading, and only the middle answer survives');

-- (6) TWO full payments in ONE statement. Two grants inside one statement is
-- where a rule that evaluates `periods_granted = 0` against the pre-statement
-- snapshot sets twice.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    select ('220000ff-0022-4000-8000-7000000027b' || i::text)::uuid, '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002706', '220000ff-0022-4000-8000-600000002706', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701'
      from generate_series(1, 2) i$q$),
  'OK',
  'r20/two-in-one: TWO full payments in ONE statement — the multi-row shape ADR-092 names, and the shape every defect in this phase survived the single-row case and died on');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002706'),
  '0/60/60/2/active',
  'r20/two-in-one: sixty days on two periods, whichever way the rule fires — twice at one period each (set, then extend) or once at two (set) both land here. What does NOT land here is a rule reading `periods_granted` as the statement STARTED: it sees zero for both rows, sets twice, and leaves thirty days on a count of two — a row that satisfies the requirement''s scenario sentence while breaking the invariant the requirement was written to restore');

-- (7) The same two payments in TWO statements, same transaction. The
-- intermediate state is asserted rather than skipped: it is the only place the
-- boundary between "set" and "extend" is crossed in the open.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002707', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002707', '220000ff-0022-4000-8000-600000002707', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/two-statements: the first of two payments');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002707'),
  '0/30/30/1/active',
  'r20/two-statements: the first grant SET — and the row is now indistinguishable from one sold honestly. That is the property worth naming: after the first paisa the typed period is GONE, not merely capped, which is what lets the withdrawal of the creation rule be survivable at all');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027a7', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002707', '220000ff-0022-4000-8000-600000002707', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/two-statements: and the second, in its own statement');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002707'),
  '0/60/60/2/active',
  'r20/two-statements: which extends, landing exactly where (6) landed. Two payments reach the same place whether they arrive together or apart — a property a rule keyed on the statement rather than on the row cannot deliver');

-- (8) A payment in a currency the membership does not carry. Measured
-- elsewhere in this file as a payment that lands, is receipted, and grants
-- nothing.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002708', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002708', '220000ff-0022-4000-8000-600000002708', 100000, 'USD', 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/foreign currency: a full-price payment in USD against an INR membership is recorded, exactly as it is today');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002708'),
  '0/30/30/0/active',
  'r20/foreign currency: and it granted NOTHING, so it moved nothing. Money arriving is not what this requirement is keyed on, and this row tells a `periods_granted = 0` key from a "has any payment landed" key without needing a part payment to do it — currency decides which payments count toward the price at all');

-- (9) A complimentary membership: price zero, so no money can ever buy a
-- period of it. The gym gave this month away on purpose.
select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000002709', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-500000002709', '220000ff-0022-4000-8000-600000002709', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/zero price: a complimentary membership takes a payment anyway. `memberships_price_paise_chk` permits the zero and the desk can still bank cash against it');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-600000002709'),
  '0/30/30/0/active',
  'r20/zero price: nothing granted, nothing moved — and the part worth asserting is the second half. The free month is NOT confiscated by a rule that decided an ungranted span ought to be zeroed. "Set its span from the plan" is something the granting rule does WHEN IT GRANTS, not something that happens to spans nobody paid for');

-- ---------------------------------------------------------------------------
-- 27b. THE TWO CASES THE WITHDRAWAL PUT BACK ON THIS RULE'S DESK.
--
-- (i) TEN YEARS, CREATED AND THEN PAID FOR. With no creation rule, `today ..
-- today + 3650` is an ordinary INSERT any front desk may write, and the
-- granting rule is the ONLY thing between it and ten years of turnstile bought
-- with one month's money. This is the single most important assertion in the
-- section: it is the change's original measured harm, and after the withdrawal
-- it has exactly one line of defence.
--
-- (ii) THE ONE-DAY PLAN, where a period is a day and a rule that hardcoded
-- thirty — or read the plan of the wrong membership — is invisible everywhere
-- else in this file.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-60000000270a', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270a', '220000ff-0022-4000-8000-400000002701', 'active', (select today from gym_today where org_key='R20'), (select today from gym_today where org_key='R20') + 3650, 100000, 'INR')$q$),
  'OK',
  'r20/ten years: a front desk creates a TEN-YEAR membership on a thirty-day plan, in one statement, with no payment anywhere. Asserted as PERMITTED, which is now the contract: the rule that would have refused it was withdrawn, and asserting the residual out loud is the difference between a known cost and a surprise a year from now');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270a'),
  '0/3650/3650/0/active',
  'r20/ten years: there it sits — live at the turnstile today (ADR-084 admits on dates), `periods_granted = 0`, and unrepairable, because GL045 froze the dates against whoever tries to undo it as firmly as against whoever typed them');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-70000000270a', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270a', '220000ff-0022-4000-8000-60000000270a', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/ten years: and one month''s money is taken against it');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270a'),
  '0/30/30/1/active',
  'r20/ten years: THE TEN YEARS COLLAPSE TO THIRTY DAYS. This is the whole of the change in one assertion: the grant does not add its period to what it found, it SETS. A span nobody bought survives only as long as nobody pays — and note what that means for the withdrawn requirement''s residual, which is now the entire residual: it is bounded by whether anyone ever pays, not by any number in the schema');

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-60000000270b', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270b', '220000ff-0022-4000-8000-400000002702', 'active', (select today from gym_today where org_key='R20'), (select today from gym_today where org_key='R20') + 1, 100000, 'INR')$q$),
  'OK',
  'r20/one-day plan: a day pass, sold on the one-day plan and typed with its one day');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-70000000270b', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270b', '220000ff-0022-4000-8000-60000000270b', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/one-day plan: paid for');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270b'),
  '0/1/1/1/active',
  'r20/one-day plan: ONE day, not two. The bound is read from THE PLAN — a rule that hardcoded thirty, or read the membership''s own `duration_days` before `app.stamp_membership()` derived it, or read the gym''s only other plan, passes every 30-day assertion in this file and fails here. Today this row spans two days, which is a 100 per cent overrun that looks like nothing at all');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-7000000027ab', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270b', '220000ff-0022-4000-8000-60000000270b', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/one-day plan: and the day pass is renewed for a second day');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270b'),
  '0/2/2/2/active',
  'r20/one-day plan: two days on two periods. The renewal branch reads the plan too, and on a one-day plan the whole rule fits inside the rounding of every other assertion here');

-- ---------------------------------------------------------------------------
-- 27c. THE INVARIANT, OVER EVERY PATH AT ONCE — AND WHERE IT LEGITIMATELY
-- FAILS. The requirement names this comparison as the only thing that
-- disagrees on a doubled row: "`ends_on - starts_on` against `duration_days *
-- periods_granted`, and nothing in this system compares those two numbers".
-- ADR-088 declined to enforce it as a trigger because five legitimate
-- early-returns leave the two disagreeing — and every one of those is a row
-- that has been granted NOTHING. So it is asserted here exactly where
-- ADR-088's objection does not reach, and the exemption is asserted too,
-- rather than left as a gap a future trigger could be built into.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

select is(
  (select coalesce(string_agg(right(id::text, 2) || ' span=' || coalesce((ends_on - starts_on)::text, 'null') || ' owed=' || (duration_days * periods_granted)::text, ', ' order by id), 'none')
     from public.memberships
    where tenant_id = '220000ff-0022-4000-8000-100000002701'::uuid
      and periods_granted > 0
      and (starts_on is null or ends_on is null or (ends_on - starts_on) <> duration_days * periods_granted)),
  'none',
  'r20/invariant: EVERY membership this section has granted a period to spans exactly `duration_days * periods_granted` days — nine paths, two plans, first grants and renewals, one assertion. A per-path assertion is satisfied by a rule that happens to be right on the paths somebody thought of; this one is satisfied only by a rule that is right, and it names the offending rows in its own failure message. Scoped to this section''s tenant per ADR-050');

select is(
  (select string_agg(right(id::text, 2) || '=' || (ends_on - starts_on)::text, ' ' order by id)
     from public.memberships
    where tenant_id = '220000ff-0022-4000-8000-100000002701'::uuid
      and periods_granted = 0),
  '08=30 09=30',
  'r20/invariant exemption: and the rows that have been granted NOTHING still carry the span that was typed on them — the USD-paid one and the complimentary one, thirty days each, both breaking the invariant on purpose. This is ADR-088''s objection stated as an assertion rather than left implicit: the equation is a property of GRANTED periods, not of memberships, and anybody who later promotes it to a CHECK or a trigger will fail on exactly these two rows and on every part-paid row in the product');

-- ---------------------------------------------------------------------------
-- 27d. WHERE `starts_on` LANDS. This subsection was written to STAGE a gap:
-- "set its span from the plan" fixes the LENGTH of a span and said nothing
-- about its POSITION, and three readings fitted the sentence -
--
--   (A) both dates from today:  starts = today,      ends = today + d*n
--   (B) keep starts_on:         starts = starts_on,  ends = starts_on + d*n
--   (C) keep today's floor:     ends = greatest(ends_on, today) + d*n,
--                               starts = ends - d*n
--
-- On all eleven rows above they agree, because `starts_on` was today. On the
-- two below they differ by up to 100 days at a turnstile that admits on dates,
-- and (C) - which the first implementation chose - gave a returning lapsed
-- member a span longer than the money bought, which is this change's own defect
-- reached from the other side.
--
-- THE CONTRACT NOW DECIDES IT: the first grant starts a membership at the LATER
-- of its `starts_on` and today. A future start date was sold and is honoured; a
-- past one is not, because a membership nobody paid for never started. That is
-- (A) and (B) joined at exactly the seam where they disagreed, and it is
-- neither of them alone. So the position is now ASSERTED here rather than
-- reported - a pre-sold row keeps its future start, a lapsed row is pulled to
-- today, and both span exactly what was paid for.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                     'tenant_id', '220000ff-0022-4000-8000-100000002701',
                     'app_role', 'front_desk',
                     'staff_id', '220000ff-0022-4000-8000-300000002701')::text,
  true
);
set local role authenticated;

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-60000000270c', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270c', '220000ff-0022-4000-8000-400000002701', 'active', (select today from gym_today where org_key='R20') + 10, (select today from gym_today where org_key='R20') + 40, 100000, 'INR')$q$),
  'OK',
  'r20/starts-on future: a membership sold today to START in ten days — an ordinary pre-sale, spanning exactly one period, refused by nothing');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-70000000270c', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270c', '220000ff-0022-4000-8000-60000000270c', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/starts-on future: and paid for today');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270c'),
  '10/40/30/1/active',
  'r20/starts-on future: the membership STILL STARTS IN TEN DAYS, and now spans exactly one period from there. Both halves are the contract''s: "the later of its starts_on and today" is this sale''s own future date, so the member is not made live today for a membership that has not begun, and the span is what the money bought. This assertion was span-only while the position was undecided, and was tightened when the contract settled it - which is the whole point of having staged it rather than guessed');

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    values ('220000ff-0022-4000-8000-60000000270d', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270d', '220000ff-0022-4000-8000-400000002701', 'active', (select today from gym_today where org_key='R20') - 90, (select today from gym_today where org_key='R20') - 60, 100000, 'INR')$q$),
  'OK',
  'r20/starts-on lapsed: a membership that ran out sixty days ago and was never paid for — the seed''s own lapsed-fixture shape, and 19a''s a11. This is the retention loop''s subject matter, so nothing may refuse it');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-70000000270d', '220000ff-0022-4000-8000-100000002701', '220000ff-0022-4000-8000-50000000270d', '220000ff-0022-4000-8000-60000000270d', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701')$q$),
  'OK',
  'r20/starts-on lapsed: the member comes back and pays. Whatever the rule does here, it must not refuse this — this is the transaction the whole product exists to produce');

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270d'),
  '0/30/30/1/active',
  'r20/starts-on lapsed: the returning member STARTS TODAY and spans exactly the thirty days they paid for. Before the change this row spanned a hundred and twenty, and nobody typed a defect to get there - `starts_on` was honest, `ends_on` was honest, and the first grant added a bought period on top of a span that had already been LIVED. "The later of its starts_on and today" is what makes the row right in both directions at once: reading (B) alone would have ended this membership sixty days in the PAST, and reading (C) - the first implementation - left it sixty-one days long for one month''s money');

-- A second payment: a genuine renewal on a row that has now been granted a
-- period. Recorded as a fixture rather than scored, so the one assertion that
-- follows is about the arithmetic rather than about the insert.
insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
  values ('220000ff-0022-4000-8000-7000000027ad'::uuid, '220000ff-0022-4000-8000-100000002701'::uuid, '220000ff-0022-4000-8000-50000000270d'::uuid, '220000ff-0022-4000-8000-60000000270d'::uuid, 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701'::uuid);

select is(
  pg_temp.h22r20_shape('220000ff-0022-4000-8000-60000000270d'),
  '0/60/60/2/active',
  'r20/starts-on lapsed: and the renewal EXTENDS from where the first grant left the row - sixty days on two periods. This outcome was staged rather than sided while the position was undecided, because it was the place that undecided sentence decided something else as well: had the first grant left `starts_on` ninety days back, this renewal would have landed on a 120-day span against two periods and broken the invariant 27c asserts - legitimately, and by the rule''s own hand. Settling the position settles that too, and 27c''s scoped population is exact now rather than lucky');

select diag(
  'r20/starts-on SETTLED, and recorded here because the assertions above no longer show that it ever was not. This subsection was written to STAGE the question, asserting only the span, because "set its span from the plan" fixed a length and never a position: reading (A) started every first grant at today, (B) kept `starts_on` wherever it was, (C) kept the old `greatest(ends_on, today)` floor and pulled `starts_on` back to suit. All three satisfied every scenario the requirement stages, because in all of them `starts_on` was already today. The first implementation shipped (C) and gave the lapsed member above a sixty-one-day span for one month''s money - this change''s own defect, one shape over. The contract now says the first grant starts a membership at the LATER of its `starts_on` and today, which is (A) and (B) joined at the seam where they disagreed and is neither alone; both rows above now assert the position as well as the span.');

-- ---------------------------------------------------------------------------
-- 27e. WHAT WAS REPORTED RATHER THAN GUESSED, AND WHAT BECAME OF IT. Two of
-- the five were settled in the contract after this section staged them and are
-- kept, renumbered SETTLED rather than deleted. The recorded duration is also
-- explicit in the schema contract. The universal invariant remains outside
-- this change; reconciliation of the earlier assertions is complete.
-- ---------------------------------------------------------------------------

select diag(
  'r20 SETTLED 1/5 - WHERE `starts_on` LANDS ON THE FIRST GRANT. Raised by 27d as a staged measurement rather than an assertion, on the grounds that a blind author cannot assert it without inventing contract, and that it was the kind of thing most likely to be settled BY ACCIDENT - by whichever line the implementer happened to write. It was: the first implementation kept the old `greatest(ends_on, today)` floor and gave a returning lapsed member sixty-one days for one month''s money. The contract now carries the sentence - the first grant starts a membership at the LATER of its `starts_on` and today - and 27d asserts both halves of it. Kept in this list, renumbered rather than deleted, because the value was in staging it, and a reader who finds only the assertions will not see that.');

select diag(
  'r20 DOCUMENTED 2/5 — THE RECORDED DURATION. This was originally staged as an ambiguity between the plan and the membership. The schema contract in docs/data-model.md explicitly defines memberships.duration_days as the duration sold, copied from the plan at creation or an allowed plan change and retained independently of later edits to the plan row. Section 27 uses memberships.duration_days in its scoped invariant consistently with that existing contract; this membership-creation change does not redefine how the sold duration is recorded.');

select diag(
  'r20 SETTLED 3/5 - THE MULTI-PERIOD FIRST GRANT. This was asserted here on an inference: the requirement''s scenario says the span "SHALL become exactly one period", every scenario it stages grants exactly one, and 27a/5, 27a/6 and 27a/7 assert `duration_days * periods_granted` instead - on the strength of the requirement''s own prose naming that product as the invariant being restored, which is a paragraph of rationale rather than a scenario. Read literally the sentence would hand a member who paid for two months a single month, the doubling with its sign flipped. Now measured against the implementation and confirmed: one payment worth two periods gives a sixty-day span on a count of two. The inference is retired; 19a''s a04 (five periods at once, 150 days) and a05 (ten in one statement, 300) pin the same thing from the other suite-half.');

select diag(
  'r20 UNDECIDED 4/5 — IS THE INVARIANT TRUE ON EVERY PATH AFTER THIS CHANGE? Measured across everything this section builds: no, and two of the exceptions are legitimate. (a) Rows granted NOTHING keep whatever span was typed — 27c asserts exactly this for the USD-paid and the complimentary rows, and it is also true of every part-paid row, which is ADR-088''s original objection and is unchanged by this requirement. (b) A renewal arriving after a membership has LAPSED measures from today, not from a stale `ends_on`, so it legitimately produces a span longer than `duration * periods`. This one WAS contingent on the settled question and no longer is, in the direction that narrows it: because the first grant now pulls `starts_on` up to today, a membership cannot reach its second period still carrying a lived-through span, and no row this section builds hits case (b) at all. It remains reachable in production, where a membership lapses between two real payments weeks apart - which one transaction cannot stage. (c) Anything that moves a date without granting — the pause approvals and freeze cancellations 19d covers — breaks it too. So the honest statement of the invariant is: it holds for a membership whose periods were all granted while it was live or unstarted, and nowhere else. That is a narrower claim than the requirement''s prose implies, and it is why 27c asserts it over a scoped population rather than over the table.');

select diag(
  'r20 RECONCILED 5/5 — the original audit identified earlier assertions that treated an unpaid typed span as already bought. Their first-grant expectations are now reconciled across the cumulative-periods battery, multi-row seams, price-cut baseline, section 19a, the two-statement date guard, the refund pair and the service-role pair. Each changed assertion records its contract reason in place. The assertion count and the original protections are retained: cumulative money still determines the period count, refusals still leave rows unchanged, and refunds still preserve the dates and count already granted. Zero-span fixtures keep their existing outcomes.');


-- ---------------------------------------------------------------------------
-- 27f. COMBINED BOUNDARIES FROM THE SETTLED CONTRACT.
--
-- The individual rules above must also hold when combined. Three memberships
-- receive identical money: a pre-sale with an excessive typed end, a partly
-- elapsed typed period, and a pending row with neither date. One paisa short of
-- the price must leave every date alone. The next payment takes the total to
-- three periods plus one paisa: this is the FIRST grant despite being the
-- second payment. A final payment uses that spare paisa to complete a renewal.
-- No new helper or implementation assumption is needed.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone)
select ('220000ff-0022-4000-8000-5000000027e' || i::text)::uuid,
       '220000ff-0022-4000-8000-100000002701'::uuid,
       '220000ff-0022-4000-8000-200000002701'::uuid,
       'H22 R20 First Grant Boundary ' || i::text,
       '+919220271' || lpad(i::text, 3, '0')
  from generate_series(1, 3) i;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '220000ff-0022-4000-8000-100000002701',
                    'app_role', 'front_desk',
                    'staff_id', '220000ff-0022-4000-8000-300000002701')::text,
  true
);
set local role authenticated;

select is(
  pg_temp.h22r17_state($q$insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, currency)
    select ('220000ff-0022-4000-8000-6000000027e' || f.i::text)::uuid,
           '220000ff-0022-4000-8000-100000002701'::uuid,
           ('220000ff-0022-4000-8000-5000000027e' || f.i::text)::uuid,
           '220000ff-0022-4000-8000-400000002701'::uuid,
           f.st::public.membership_status,
           (select today from gym_today where org_key = 'R20') + f.s0,
           (select today from gym_today where org_key = 'R20') + f.e0,
           100000, 'INR'
      from (values (1, 'active', 12, 3650),
                   (2, 'active', -15, 15),
                   (3, 'pending', null::int, null::int)) as f(i, st, s0, e0)$q$),
  'OK',
  'r20/boundaries: create future, partly elapsed and dateless memberships under the unchanged creation contract');

select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e1'),
  '12/3650/3638/0/active',
  'r20/boundaries future: the unpaid pre-sale retains its chosen start and excessive typed end');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e2'),
  '-15/15/30/0/active',
  'r20/boundaries elapsed: the unpaid membership began fifteen days ago and still has a future end');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e3'),
  '-/-/-/0/pending',
  'r20/boundaries dateless: the unpaid ordinary path has neither date and no granted period');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    select ('220000ff-0022-4000-8000-7000000027e' || i::text)::uuid,
           '220000ff-0022-4000-8000-100000002701'::uuid,
           ('220000ff-0022-4000-8000-5000000027e' || i::text)::uuid,
           ('220000ff-0022-4000-8000-6000000027e' || i::text)::uuid,
           99999, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701'::uuid
      from generate_series(1, 3) i$q$),
  'OK',
  'r20/boundaries partial: all three memberships take a payment one paisa short of one period');

select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e1'),
  '12/3650/3638/0/active',
  'r20/boundaries partial future: even an excessive typed end is unchanged before a full period is paid');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e2'),
  '-15/15/30/0/active',
  'r20/boundaries partial elapsed: a past start is not moved to today before a full period is paid');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e3'),
  '-/-/-/0/pending',
  'r20/boundaries partial dateless: a part payment neither dates nor activates the ordinary path');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    select ('220000ff-0022-4000-8000-7000000027f' || i::text)::uuid,
           '220000ff-0022-4000-8000-100000002701'::uuid,
           ('220000ff-0022-4000-8000-5000000027e' || i::text)::uuid,
           ('220000ff-0022-4000-8000-6000000027e' || i::text)::uuid,
           200002, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701'::uuid
      from generate_series(1, 3) i$q$),
  'OK',
  'r20/boundaries first grant: second payments bring each cumulative total to three periods plus one paisa');

select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e1'),
  '12/102/90/3/active',
  'r20/boundaries first future: set exactly three periods from the chosen future start; discard the old typed end');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e2'),
  '0/90/90/3/active',
  'r20/boundaries first elapsed: start today even though the old end is still in the future; set exactly three periods');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e3'),
  '0/90/90/3/active',
  'r20/boundaries first dateless: activate today for exactly three periods; the spare paisa buys no additional day');

select is(
  pg_temp.h22r17_state($q$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    select ('220000ff-0022-4000-8000-7000000027d' || i::text)::uuid,
           '220000ff-0022-4000-8000-100000002701'::uuid,
           ('220000ff-0022-4000-8000-5000000027e' || i::text)::uuid,
           ('220000ff-0022-4000-8000-6000000027e' || i::text)::uuid,
           99999, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000002701'::uuid
      from generate_series(1, 3) i$q$),
  'OK',
  'r20/boundaries renewal: the next payments use the carried paisa to complete a fourth period');

select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e1'),
  '12/132/120/4/active',
  'r20/boundaries renewal future: extend by one period and retain the future start chosen at sale');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e2'),
  '0/120/120/4/active',
  'r20/boundaries renewal elapsed: extend from the first grant without restoring the discarded past start');
select is(pg_temp.h22r20_shape('220000ff-0022-4000-8000-6000000027e3'),
  '0/120/120/4/active',
  'r20/boundaries renewal dateless: the ordinary path renews identically after its first grant');


set local role postgres;
select * from finish();

rollback;
