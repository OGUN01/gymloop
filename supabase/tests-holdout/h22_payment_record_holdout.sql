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

begin;

set local role postgres;

select plan(612);

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
  (select today from gym_today where org_key = 'A') + 15 + 30,
  'cumulative: and exactly one period is granted on the second half, once the cumulative total reaches the price — never two months for the two halves');

-- Two at once.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000053', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-50000000000d', '220000ff-0022-4000-8000-600000000012', 200000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'cumulative: a single payment of exactly double the membership''s price is recorded');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000012'::uuid),
  (select today from gym_today where org_key = 'A') + 5 + 60,
  'cumulative: and grants two periods in one step — floor(200000/100000) - floor(0/100000) = 2');

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
        (select today from gym_today where org_key = 'A') + 8 + 30),
  'cumulative/refund-mid: whatever the answer, it is bounded to zero or one period — never two, since only one multiple of the price was ever paid in, refunded or not');

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
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/ten: exactly ONE period is granted for the statement''s total — not ten, which is what ten independent per-row crossings would grant (300 days on this 30-day plan, the spec''s own measured defect)');

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
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/mixed-memberships: B1 gains exactly one period (100000 / 100000 = 1) — unaffected by B2''s rows in the same statement');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000032'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 60,
  'multi-row/mixed-memberships: B2 gains exactly two periods (100000 / 50000 = 2) in the SAME statement — each membership''s own total, not a shared or confused one');

-- Seam: some rows paid, some not, in one statement.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 60000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 40000, 'cash', 'paid',    now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000023', '220000ff-0022-4000-8000-600000000033', 50000, 'cash', 'created', null,  '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/mixed-status: one statement carries two paid rows (60000+40000=100000, exactly one multiple) and one merely-created row (50000) against the same membership');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000033'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/mixed-status: exactly one period, from the 100000 that is actually paid — the created row''s 50000 is not money that arrived and must not join the total');

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
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/update: exactly one period — the row moved to failed contributes nothing, and the two moved to paid are counted as their statement''s own total, not three independent per-row guesses');

-- Seam: the SAME membership touched twice at different amounts in one
-- statement, summing to just past one multiple.
select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id) values
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 40000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001'),
    (gen_random_uuid(), '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000025', '220000ff-0022-4000-8000-600000000035', 70000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'multi-row/uneven: one statement pays 40000 then 70000 (110000 total) against one membership priced at 100000');

select is(
  (select ends_on from public.memberships where id = '220000ff-0022-4000-8000-600000000035'::uuid),
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/uneven: exactly one period (110000 crosses 100000 once) — a per-row guess using the final total for both unequal rows would double-grant, since each row alone (40000 and 70000) still looks like the one that crossed 100000 against a shared final total');

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
  (select today from gym_today where org_key = 'A') + 10 + 30,
  'multi-row/currency: exactly one period, from the INR row alone — the USD row does not join the total even though it is against the same membership in the same statement');

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
  (select today from gym_today where org_key = 'A') + 60,
  'periods_granted/price-cut: baseline — ends_on moved by that one period');

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
      and p.proname not in ('audit_impersonation_session', 'custom_access_token_hook', 'revoke_sessions_on_identity_change')),
  0,
  'ADR-066: every security definer function in schema app is still one of the three already-justified ones — this contract''s fix added no new elevated function');

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

select lives_ok(
  $$update public.memberships set discount_paise = 5000 where id = '220000ff-0022-4000-8000-600000000059'$$,
  'OPEN-026 / ADR-089: and the row is still EDITABLE, which is the thing 16i was written to protect. ADR-089 rejected a consistency trigger because it would have bricked rows whose recorded count and banked money legitimately disagree; this row is one, and GL045 takes its two dates and nothing else');

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

select lives_ok(
  $$update public.memberships set discount_paise = 15000 where id = '220000ff-0022-4000-8000-600000000924'$$,
  'GL043/permitted: discount_paise is still writable after money has arrived — it is deliberately not a term, because nothing in the money path reads it, and a length rule that swept the row''s money columns together would take it');

select is(
  (select discount_paise from public.memberships where id = '220000ff-0022-4000-8000-600000000924'::uuid),
  15000::bigint,
  'GL043/permitted: and that write landed');

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
  '0/60/1',
  'GL045/grant-shapes: the renewal moved ends_on by one period and left starts_on where it was — the rule writes ONE of the two dates here and both on a01, so a guard that authorises "the write that fills the dates" and not "the write that extends them" passes a01 and breaks this');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a03', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a02', '220000ff-0022-4000-8000-600000000a02', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: and a SECOND renewal on the same membership is recorded');

select is(
  (select (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a02'::uuid),
  '90/2',
  'GL045/grant-shapes: which moved it again. A rule that arms once per transaction, or once per row, renews exactly once and then stops — silently, and only the member finds out');

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
  '180/5',
  'GL045/grant-shapes: and the dates moved by five periods in one write — a guard that permits "one period''s worth of movement" rather than "the rule wrote it" refuses this and hands the gym back a member who paid for five months and got one');

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
  '330/10',
  'GL045/grant-shapes: and all ten granted. Ten rows means ten fires of the rule against one membership inside one statement, and a guard that reads the row it is about to write rather than the write it is making sees ten "unexplained" date moves here');

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
  '60/1',
  'GL045/grant-shapes: which granted. The grant fires on the payment''s UPDATE, not only on its INSERT, and a date guard that only knows about the INSERT path refuses every online settlement');

select lives_ok(
  $$merge into public.payments p
    using (select '220000ff-0022-4000-8000-700000000a07'::uuid as id) s on p.id = s.id
    when not matched then insert (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
      values ('220000ff-0022-4000-8000-700000000a07', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a07', '220000ff-0022-4000-8000-600000000a07', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a payment inserted by MERGE ... WHEN NOT MATCHED is recorded');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a07'::uuid),
  '60/1',
  'GL045/grant-shapes: and it granted. MERGE is named in ADR-092 as a measured route into this table and it must stay a working one');

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
  '60/1',
  'GL045/grant-shapes: which granted too');

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
  '60/1',
  'GL045/grant-shapes: and it granted. This is the honest half of 19b''s statement and it must survive whatever refuses the dishonest half');

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
  '60/1',
  'GL045/grant-shapes: which granted');

select lives_ok(
  $$insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, method, status, paid_at, recorded_by_staff_id)
    values ('220000ff-0022-4000-8000-700000000a11', '220000ff-0022-4000-8000-100000000001', '220000ff-0022-4000-8000-500000000a11', '220000ff-0022-4000-8000-600000000a11', 100000, 'cash', 'paid', now(), '220000ff-0022-4000-8000-300000000001')$$,
  'GL045/grant-shapes: a member whose membership lapsed three months ago renews');

select is(
  (select (starts_on - (select today from gym_today where org_key = 'A'))::text || '/' || (ends_on - (select today from gym_today where org_key = 'A'))::text || '/' || status::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a11'::uuid),
  '-90/30/active/1',
  'GL045/grant-shapes: and the rule measured from the gym''s TODAY, not from an ends_on already sixty days in the past — otherwise the renewal buys thirty days that finished last month. starts_on stays where it was, so the row now spans 120 days on one period granted');

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
  '60/1',
  'GL045/two-statements: and it granted a period, in the ordinary way');

select throws_ok(
  $$update public.memberships set ends_on = ends_on + 3650 where id = '220000ff-0022-4000-8000-600000000a13'$$,
  'GL045'::char(5), null,
  'GL045/two-statements: and the hand-written extension in the NEXT statement of the SAME transaction is still refused. A rule armed per transaction rather than per write reads "a payment already moved these dates" and lets this through');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text
     from public.memberships where id = '220000ff-0022-4000-8000-600000000a13'::uuid),
  '60/1',
  'GL045/two-statements: dates unchanged at the sixty days the money actually bought');

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
  '60/1',
  'GL045/refund: sixty days, one period');

select lives_ok(
  $$update public.payments set status = 'refunded' where id = '220000ff-0022-4000-8000-700000000a24'$$,
  'GL045/refund: and it is refunded, which still works');

select is(
  (select (ends_on - starts_on)::text || '/' || periods_granted::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a24'::uuid),
  '60/1',
  'GL045/refund: and the dates did not move back, nor did the count. This is asserted because the requirement''s own remedy depends on it: "correcting a mistake means refunding and selling again", and a refund measurably corrects no date — see the diag below and the report');

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
  '60/1',
  'GL045/service_role: and it granted a period. The trusted caller must keep the rule''s own write, or every online renewal stops');

select throws_ok(
  $$update public.memberships set ends_on = starts_on + 3650 where id = '220000ff-0022-4000-8000-600000000a2c'$$,
  'GL045'::char(5), null,
  'GL045/service_role: but a hand-written date from service_role is refused too. SIDED, not staged, on ADR-092''s own general form: a trusted-caller carve-out is sound exactly where the rule''s subject is something a trusted caller legitimately lacks, and where the subject is an invariant about the data — a sequence, a total, a date arithmetic — the trusted caller needs it MORE, because no policy stands behind it. Called out in the report as the one place this author chose a side');

select is(
  (select (ends_on - starts_on)::text from public.memberships where id = '220000ff-0022-4000-8000-600000000a2c'::uuid),
  '60',
  'GL045/service_role: and the dates are unchanged at what the money bought');

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
  '30/1',
  'GL046/discount-unread: and it bought exactly ONE period — OPEN-028 asserted from the money''s side rather than the column''s. If the granting rule ever scores against `price_paise - discount_paise` this reads 300/10, and the requirement one heading up says whoever makes that change adds discount_paise to the frozen terms in the same commit. This assertion is the tripwire for that day');

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


select * from finish();

rollback;
