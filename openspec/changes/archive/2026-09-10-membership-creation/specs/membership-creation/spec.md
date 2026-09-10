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

### Requirement: A membership is created with at most the one period it is sold — WITHDRAWN

**This requirement was written, built, measured, and refuted by its own
implementation. It is kept here, struck, because the reason is worth more than
the rule was.**

It said a creation is refused unless `ends_on` is at most `starts_on` plus the
plan's duration. It was justified by a measurement: *of 46 memberships, 45 span
exactly one period and none would be refused.* That measurement is real, and it
is of the **demo gym's live rows**. The rule binds **every INSERT into
`public.memberships` by anybody**. Those are not the same population, and
nothing in the measurement said so.

Measured with the rule spliced into all 47 pgTAP files: **six files blocked
outright and a seventh failing four assertions — 3087 assertions reachable
instead of 4152.** Fixtures in six independently-authored files create
memberships spanning more than one period directly, because a renewed membership
genuinely spans several and building one through payments would be laborious.
Six files written by different authors at different times are not six mistakes.

**The half-dated clause went with it, on its own merits.** A row with `ends_on`
null carries no span, cannot be live at the turnstile because the check-in gate
reads dates (ADR-084), and is **inert to `app.grant_periods()`** — the dateless
branch requires both dates null, the dated branch requires `ends_on is not
null`, and a half-dated row matches neither, so it can never be doubled. It was
never this change's harm, and refusing it would have decided OPEN-026 in
passing, which OPEN-026 explicitly defers.

**What remains open, stated precisely.** A desk can still create a membership
dated `today … today + 3650` with no payment, and the check-in gate will honour
it. That is real and it stays in OPEN-029. **But it can no longer be turned into
money**: the requirement below makes the first grant *set* the span, so paying
such a membership collapses it to what was bought — measured, `3650 days` before
the payment and `31 days` after. The residual harm is a desk giving away gym
time it cannot bill for, which is the same class as marking somebody present,
and it wants a rule that fixtures and the seed can satisfy. Whoever writes it
should start from what refuted this one: **measure the population the rule
binds, not the population that inspired it.**

### Requirement: The first period is set, not added
WHERE a membership has been granted no periods and its dates are either both
present or both absent, THE SYSTEM SHALL set its span from the recorded sold
duration rather than extend a span it already carries.

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

**Where `starts_on` lands, decided because a blind author showed that "set the
span" does not say it.** Setting a *length* fixes no *position*, and three
readings satisfy every scenario below — because in all of them `starts_on` is
already today. They differ by up to a hundred days on two real shapes, at a gate
that admits on dates (ADR-084), with `GL045` making whatever lands permanent:

| shape | keep `starts_on` | move both to today | **decided** |
|---|---|---|---|
| pre-sold, starts next Monday | Mon … Mon+30 ✓ | live today — a free week | **Mon … Mon+30** |
| lapsed member returns and pays | expired last month — **paid for nothing** | today … today+30 ✓ | **today … today+30** |

**WHERE a membership has been granted no periods and its dates are both present,
THE SYSTEM SHALL start it at the later of its `starts_on` and today.** A future start date was chosen and is
honoured; a past one is not, because a membership nobody paid for never started.
The span is then exactly `duration_days × periods_granted` on the fully dated
and fully dateless first-grant paths, including a single payment worth two periods
(span 60, two periods granted).

A third reading — keep `starts_on`, floor only `ends_on` at today — is what the
first implementation did, and it gives the returning member a **61-day span for
one month's money**: the same defect this requirement exists to close, reached
from the other side.

**A part payment sets nothing, and a blind author was right to ask.** "Set its
span from the plan" read literally would collapse a typed span to
`duration × 0` when a payment arrives that does not complete a period — which
would be a new defect, not a fix. It does not, and the reason is a guard that
predates this change: the granting rule returns early when the periods owed do
not exceed the periods already granted, so the setting expression is never
reached. Measured on a half-price payment against a membership dated one period:
span unchanged, `periods_granted = 0`; and when the second half completes the
price, span one period, `periods_granted = 1` — where the old arithmetic gave
two.

#### Scenario: A payment that does not complete a period
- **WHEN** a payment arrives that leaves the money short of one period's price
- **THEN** nothing SHALL be granted and the membership's dates SHALL NOT move

#### Scenario: The first payment against a membership that carries a typed span
- **WHEN** a payment grants the first period of a membership whose dates were already set
- **THEN** the span SHALL become exactly one period, not one period more

#### Scenario: A renewal
- **WHEN** a payment grants a period to a membership that already has one
- **THEN** the span SHALL be extended by that period, as it is today

#### Scenario: The ordinary path
- **WHEN** a payment grants the first period of a dateless membership
- **THEN** it SHALL be dated from the plan exactly as it is today

#### Scenario: A pending membership with only an end date
- **WHEN** a payment buys a period for a pending membership with a null start date and a present end date
- **THEN** its start date SHALL remain null, its end SHALL extend from the later of its existing end and gym-local today, and it SHALL remain pending, preserving the existing behavior deferred under OPEN-026

#### Scenario: A pending membership with only a start date
- **WHEN** a payment is recorded for a pending membership with a present start date and a null end date
- **THEN** its dates and granted-period count SHALL remain unchanged, preserving the existing behavior deferred under OPEN-026
