# Membership creation

## Purpose

What a membership may be created **as**. Phase 5 spent ten rounds governing
every UPDATE to a membership — the price, the length, the count, the dates — and
never once looked at the INSERT, which is where all four of those values first
arrive.

Every failure here is silent in the way this phase's worst ones were: the row
audits clean. One payment, one receipt, `periods_granted = floor(money / price)`
holding, the plan's own price on the row, no frozen term touched — and twice the
membership the money bought.

## Requirements

### Requirement: A membership is created with at most the one period it is sold
WHEN a membership is created, THE SYSTEM SHALL refuse it unless `ends_on` is at
most `starts_on` plus the plan's duration, or both dates are null.

`starts_on` and `ends_on` are what the money bought (ADR-093). Round ten froze
them against every writer below `pg_trigger_depth() >= 2` so a desk could not
type them — and creation was left as the one door where typing them was still
free. Measured, ordinary **front-desk** session, one statement, no payment
anywhere: a membership dated `today … today + 3650`, `periods_granted = 0`, live
at the turnstile today because the check-in gate reads dates (ADR-084). Ten
years, bought with nothing.

**The row cannot then be corrected.** `update … set ends_on = current_date + 30`
against it answers `GL045`: round ten's freeze binds whoever tries to undo this
exactly as firmly as whoever did it. The creation hole and the date freeze
compose into a permanent bad row, and neither round that built them was looking
at the other.

**Why "at most one period" and not "no span at all", which is where this
requirement started and what it said for its first two drafts.** No span is the
purer rule — `starts_on` and `ends_on` are what the money bought, so a membership
nobody has paid for should run for nothing. It is also unshippable without
changing the demo data, and the reason is worth writing down rather than
rediscovering.

Measured: every dated membership in the database — **all 45** — has a span of
exactly one period, and **15 of them carry no payment at all**. Those 15 are the
seed's lapsed, expired, cancelled and frozen fixtures; they are what the whole
retention loop is demonstrated on, and a lapsed member with a zero-length
membership is not a lapsed member. So "no span" forces either a seed rewrite
that changes what the demo shows, or a trusted-caller carve-out — and a carve-out
is unsound here by ADR-082's general form, because the subject is *what the money
bought* and a seed lacks that no more than a desk does.

**One period is the rule that needs neither.** Measured against the live
database before it was written, rather than argued: of 46 memberships, **45 span
exactly one period, one has both dates null, none is half-dated, and none would
be refused**. It is satisfied by every row that exists, by the console, and by
the seed. It turns the measured exploit from ten
years into one month — the length the gym sells anyway. And the residual is
bounded and visible: a desk can create at most one unpaid period at a time,
capped by the plan's own duration, held down by the one-live-membership index,
and showing on the row as a membership with no payments against it. Against a
`3650`-day span typed in one statement, that is the difference between a hole and
a rounding.

**And the requirement below erases even that the moment money arrives**, because
the first grant sets the span rather than adding to it. An unpaid period never
becomes a paid-for one.

**Zero span is what the console already writes, and that is not a concession to
it.** `POST /api/memberships` writes `status = 'active'`,
`starts_on = today`, `ends_on = today`, and both halves are argued in the file:
`active` because PAY-011 requires a gym with no gateway to stay fully functional
on cash and "a membership nobody can check in against is not that"; and
`ends_on = starts_on` because **this product has already been bitten by the
doubling once** — the line used to add the plan's duration, and ADR-083 records
that "a desk that sold a membership and then took the money for it granted sixty
days for one month's fee, in two clicks that both looked right."

**That is the finding, and it is the oldest shape in this codebase: the screen
enforces the rule and the table does not.** A correct handler is not a rule. The
requirement below is the same sentence ADR-083 wrote, moved to where a
hand-written statement also has to obey it.

**Null dates stay legal** because `memberships_dated_unless_pending_chk` permits
them while `pending`, and the granting rule has a whole branch that dates such a
row from the plan. This requirement neither adds that shape nor removes it.

**A half-dated creation — one date set and the other null — is refused**, and
that is a deliberate consequence rather than an accident of the wording. It is
half of OPEN-026, whose whole subject is that nothing in the product can create
such a row and nothing can repair one. This requirement means nothing can create
one at all. The other half of OPEN-026 — the rows that already exist — is
untouched and stays open.

**Out of scope, named rather than left to be discovered:** importing a gym's
existing members with their real dates. No such path exists today. Whoever
builds one owns the question of how a membership acquires a span it was not
sold, and this requirement is what they will have to argue with.

#### Scenario: Creating a membership that already runs longer than it was sold
- **WHEN** any session creates a membership whose span exceeds the plan's duration
- **THEN** it SHALL be refused and no membership SHALL exist

#### Scenario: Creating a membership for the period being sold
- **WHEN** a session creates a membership spanning exactly the plan's duration
- **THEN** it SHALL be allowed — this is the shape every seeded fixture already has

#### Scenario: Creating a membership with one date and not the other
- **WHEN** a session creates a membership with `starts_on` set and `ends_on` null, or the reverse
- **THEN** it SHALL be refused

#### Scenario: Creating a membership the way the console does
- **WHEN** a session creates a membership with `starts_on` and `ends_on` both today
- **THEN** it SHALL be allowed, and it SHALL be `active` if the caller asked for `active`

#### Scenario: Creating a membership with no dates at all
- **WHEN** a session creates a `pending` membership naming neither date
- **THEN** it SHALL be allowed, exactly as it is today

#### Scenario: The dates arriving from the money
- **WHEN** a payment is recorded against either shape
- **THEN** the granting rule SHALL date it from the plan, exactly as it does today

### Requirement: The first period is set, not added
WHERE a membership has been granted no periods, THE SYSTEM SHALL set its span
from the plan rather than extend a span it already carries.

`app.grant_periods()` computes `ends_on = greatest(ends_on, today) + duration ×
periods`. It must add, for renewals. But **when `periods_granted = 0`, any span
the row carries was typed and not bought**, and adding a bought period on top of
a typed one hands out the typed one free.

Measured, ordinary front desk, two ordinary statements — create dated
`today … today + 30` on a 30-day plan, then record one payment of the plan's own
price:

    span 60 days, periods_granted = 1

Against the product's own dateless path, the same payment gives 30. **Double the
membership for the same money, and every audit invariant intact**: one payment,
one receipt, `periods_granted = floor(money / price)`, the plan's price on the
row. The only disagreement is `ends_on - starts_on` against `duration_days ×
periods_granted`, and nothing in this system compares those two numbers —
ADR-088 declined to add exactly that invariant as a trigger, for reasons that
are still right.

**This is not redundant with the requirement above, and the reason is
measured rather than assumed.** `supabase/seed.sql` and `seed-scenarios.sql`
each **disable** the trigger that carries the membership-terms rules around
their own statements, and they create **15 dated memberships carrying no
payment** — every one of them a span nobody bought. Whatever refuses a span at
creation cannot reach those rows unless it lives outside that window, and even
then the seed is entitled to build history in one pass. So the creation rule is
keyed on what a writer may type, and **this one is keyed on what has actually
been paid for**, which no disable window can switch off because it is the
granting rule itself. ADR-098 paid a whole round for the lesson that a rule
folded into a function the seed disables is silently off; this requirement is
what makes that survivable rather than a second instance of it.

ADR-089's general form, applied twice: a rule is worth exactly what the
immutability of the thing it is keyed on is worth — so key two rules on two
different things.

**A renewal is untouched**, which is the whole reason for the `periods_granted =
0` key: a membership that has been granted a period extends, because extending
is what a renewal *is*.

#### Scenario: The first payment against a membership that carries a typed span
- **WHEN** a payment grants the first period of a membership whose dates were already set
- **THEN** the span SHALL become exactly one period, not one period more

#### Scenario: A renewal
- **WHEN** a payment grants a period to a membership that already has one
- **THEN** the span SHALL be extended by that period, as it is today

#### Scenario: The ordinary path
- **WHEN** a payment grants the first period of a dateless membership
- **THEN** it SHALL be dated from the plan exactly as it is today
