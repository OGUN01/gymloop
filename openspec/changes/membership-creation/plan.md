# Membership creation — closing OPEN-029

Phase 5 governed every UPDATE to a membership and never governed the INSERT.
Nine rounds froze the price, the length, the count and the dates against a desk
that types them; a tenth round froze the dates outright. **None of it looks at
creation**, and creation is where every one of those values first arrives.

## Measured, not assumed

From an ordinary **front-desk** session against a live gym, one statement, no
payment anywhere:

    insert into public.memberships
      (tenant_id, member_id, plan_id, status, price_paise, currency, starts_on, ends_on)
    values (…, 'active', <the plan's own price>, 'INR', current_date, current_date + 3650)

    ALLOWED: 2026-09-09 .. 2036-09-06, duration_days=30, periods_granted=0, price=150000
    payments against it: 0
    live by dates today: YES

Ten years at the turnstile, bought with nothing. `app.stamp_membership()`
correctly derives `duration_days = 30` from the plan, and **nothing reads it
back against the span** — the row is internally contradictory and no rule
notices.

## The part that makes it worse than it looks

    update public.memberships set ends_on = current_date + 30 where id = <that row>
    --> GL045

**The row cannot be corrected.** Round ten froze the dates against every writer
below `pg_trigger_depth() >= 2` precisely so the desk could not type them, and
that freeze applies just as firmly to somebody trying to undo this. So the
creation hole and the date freeze compose into a **permanent** bad row: created
in one statement by the least-privileged writer who can reach the table, and
repairable by nobody through the product.

That composition is the finding. Either half alone is a smaller problem than
the two together, and neither round that built them was looking at the other.

## What closing it must not break

`supabase/seed.sql` and `seed-scenarios.sql` create dated memberships with no
payment on every demo row, and fixtures in both suites do the same. ADR-093
already recorded this: "a membership is created with no span it has not been
paid for" contradicts the seed on every row. So the rule cannot simply be *no
span without money* — it has to be a rule the seed can satisfy, or the seed has
to change, and that choice is the contract's to make rather than the
implementation's.

Also in scope, because they are the same question asked from another side:

- **The remedy this phase prescribes is half-unavailable to the desk.** Measured:
  a front-desk `insert into public.refunds` is refused `42501` by
  `refunds_tenant_write` while a `gym_owner` passes. "Refund, cancel and sell a
  new one" is the answer `GL042`, `GL043` and this change all give, and the
  party who makes the mistake can do only the cancelling half. A rule whose
  remedy its caller cannot perform is a rule that will be worked around.
- **`pending → cancelled` is legal by the lifecycle and unreachable for a
  dateless row** (`memberships_dated_unless_pending_chk` answers `23514` first).
  A sale called off before any money arrived is exactly that row. OPEN-026's
  family, and it belongs here because it is about what a membership may be
  created AS.

## Order

Contract first. Then two blind authors — visible and holdout, neither reading
the implementation — assertions committed red, then the implementation, then a
fresh-context critic. Not the other way round; the last two rounds each found
their sharpest defect in the gap between what a requirement said and what an
author read it as saying.

Then OPEN-031 (refunds have no idempotency key), which should carry OPEN-034's
unassertable half with it: the refund amount-freeze is assigned no SQLSTATE
anywhere in the contract, so a statement demoting a completed refund and raising
its amount cannot be asserted at all.

---

## A second defect, found while writing this plan, and sharper than the first

`app.grant_periods()` **adds** a period on top of whatever span the row already
carries:

    ends_on = greatest(m.ends_on, v_today) + (v_duration * v_periods)

It has to, for renewals. But when `periods_granted = 0`, **any span the row
carries was typed, not bought** — and the grant adds a bought period on top of a
typed one. Measured, ordinary front desk, two ordinary statements:

| | created | then paid once | result |
|---|---|---|---|
| A | dated `today … today + 30` | ₹1,500 for a 30-day plan | **span 60 days**, `periods_granted = 1` |
| B | dateless (what the product does) | the same ₹1,500 | span 30 days, `periods_granted = 1` |

**A is double the membership for the same money, and it audits clean.** One
payment, one receipt, `periods_granted = floor(money / price) = 1`, the plan's
own price, no frozen term touched. The only thing wrong with the row is that
`ends_on - starts_on` is 60 where `duration_days × periods_granted` is 30 — and
**nothing in this system compares those two numbers**. ADR-088 explicitly
declined to add that invariant as a trigger, for reasons that are still right
(five legitimate early-returns leave the two disagreeing).

It is the same shape as round nine's 3,650-day defect and round ten's
`ends_on = starts_on + 3650`: an input to the money arithmetic that somebody who
should not write it can write. This one arrives through **creation**, which is
the one door those ten rounds never looked at, and it is quieter than either —
3,650 days is visible to anyone who glances at the row, and 60 days on a 30-day
plan looks like a renewal.

### Which makes this two defects, not one

1. **The unbought span** — creation writes `starts_on`/`ends_on` that no payment
   bought, and the check-in gate honours them (ADR-084 reads dates). Ten years
   at the turnstile for nothing.
2. **The doubling** — the first grant adds to that unbought span instead of
   replacing it.

They compose, and either fix alone leaves the other reachable: closing creation
without fixing the grant leaves the doubling reachable by the seed's own shape
and by any future writer; fixing the grant without closing creation still lets a
desk hand out ten free years, it just can never be paid for afterwards.

### The call, and why

**Creation may not write a span** — `starts_on` and `ends_on` are what the money
bought (ADR-093), and creation was the last place they could be typed. Measured:
the product's own path already creates dateless (path B above), so this costs
the product nothing; and `app.grant_periods()` is already built for it, with a
whole branch for the dateless case that sets both dates from the plan.

**And the first grant SETS the span rather than adding to it** — keyed on
`periods_granted = 0`, because that is exactly the condition under which any
existing span was typed rather than bought. Renewals are untouched: a membership
with a period already granted still extends, which is what a renewal is.

Belt and braces, deliberately, on the reasoning ADR-089's general form gives:
the creation rule is keyed on what a writer may type, and the grant rule is
keyed on what has actually been paid for. If a later change reopens one, the
other still refuses to turn it into days.

### What this costs, stated rather than discovered — and the draft it replaced

**The first two drafts of this plan said "creation may not write a span at
all".** That is the purer rule and it is unshippable. `supabase/seed.sql` and
`seed-scenarios.sql` create **15 dated memberships that carry no payment** — the
lapsed, expired, cancelled and frozen fixtures the entire retention loop is
demonstrated on. A lapsed member with a zero-length membership is not a lapsed
member. So "no span" costs either a seed rewrite that changes what the demo shows,
or a trusted-caller carve-out — and the carve-out is unsound by ADR-082's general
form, since the subject is *what the money bought* and a seed lacks that no more
than a desk does.

**"At most the one period it is sold" needs neither.** Measured: every dated
membership in the database — all 45 — has a span of exactly one period, so the
rule is satisfied by every row that exists, by the console's zero span, and by
the seed. It turns the exploit from ten years into one month, which is the length
the gym sells anyway.

**What it does NOT close, said plainly:** a desk can still create one unpaid
period. Bounded by the plan's duration, held to one at a time by the
one-live-membership index, visible on the row as a membership with no payments,
and **erased the moment any money arrives**, because the second requirement makes
the first grant set the span rather than add to it. That last part is why the two
requirements are not belt and braces any more — with one free period legal at
creation, the grant rule is the only thing standing between it and a paid
membership worth double. It moved from a second line of defence to the load-bearing
one, and that is a reason to write its assertions first.
