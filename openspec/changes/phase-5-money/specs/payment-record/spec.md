## Purpose

What a payment may become after it is written, and what it may never stop
having been.

Phase 5's first round governed the INSERT and left the UPDATE open, and two
blind critics took fourteen findings off that one omission. A refund's amount
could be raised past the payment after the ceiling had approved it; a payment
could be walked `paid → created → paid` to buy three months for one fee and
burn three receipt numbers doing it; a desk could type its own receipt number,
edit an amount on a receipted row, backdate `paid_at` into another financial
year, and reset the gym's counter until the next payment collided and was
reported to the front desk as a success.

**Every one of those is the same defect: a rule enforced where the row is born
and not where it changes** (ADR-070). They are specified together because they
must be fixed together — patching them one at a time is how this project turned
fourteen defects into nine more in Phase 3.

Every failure here is silent. Not one of them raises anything, and not one is
visible until an audit, a reconciliation, or a renewal that never comes.

## Requirements

### Requirement: A payment that has been paid is a record, not a working document
WHEN a payment's status has ever been `paid`, THE SYSTEM SHALL refuse any change
to `amount_paise`, `currency`, `member_id`, `membership_id`, `method`,
`receipt_number`, `paid_at`, `provider`, `provider_order_id`,
`provider_payment_id` or `idempotency_key`.

What stays writable is what happened *afterwards*: `status` within the
transitions below, `notes`, and `failed_reason`. This is
`app.enforce_attendance_written_once()`'s distinction applied to money — freeze
what the row MEANT, leave writable what has become of it.

`payments` grants `update` to `authenticated`, so this belongs on the table. A
rule in a Route Handler has a supported way round it, and the console is not the
only writer.

**The receipt number is in the list and is the reason the list exists.** A
number is issued once, printed, and handed to a member. A row that can be
renumbered afterwards makes the book unauditable in the one way an auditor
notices: two documents, one number, and nothing recording that either changed.

#### Scenario: Editing the amount after payment
- **WHEN** `amount_paise` is changed on a payment that has been `paid`
- **THEN** the change SHALL be refused

#### Scenario: Choosing a receipt number by hand
- **WHEN** `receipt_number` is written on a payment the counter has already numbered
- **THEN** the change SHALL be refused

#### Scenario: Moving a payment to another member
- **WHEN** `member_id` is changed on a paid payment
- **THEN** the change SHALL be refused — the money came from somebody, and a refund against the wrong person is the failure this prevents

#### Scenario: Backdating a receipted payment
- **WHEN** `paid_at` is moved on a paid payment
- **THEN** the change SHALL be refused — the date and the number are one document, and moving one without the other makes the book disagree with itself

#### Scenario: Correcting a note
- **WHEN** `notes` is changed on a paid payment
- **THEN** the change SHALL succeed

### Requirement: A payment's status moves only where it can actually go
THE SYSTEM SHALL permit only these transitions and SHALL refuse every other:
`created` → `pending`, `paid`, `failed`; `pending` → `paid`, `failed`;
`paid` → `refunded`, `reversed`; `failed` → `created`, `pending`.
`refunded` and `reversed` are terminal.

**`paid` is unreachable from anywhere it has already been**, which is what stops
the extension and the receipt counter being farmed by pressing a button. PAY-007
says a `created`/`pending` record SHALL NOT be treated as `paid` under any
circumstance; a column that can be walked back and forward is that circumstance
arriving from the other direction.

The rule applies to every writer. A provider-initiated reversal arrives through
the webhook as `service_role`, and that is the caller most likely to replay an
old event.

#### Scenario: Farming the extension
- **WHEN** a paid payment is set to `created` and then to `paid` again
- **THEN** the first update SHALL be refused, and the membership SHALL have been extended exactly once in total

#### Scenario: A failed payment retried
- **WHEN** a payment in `failed` is set to `pending`
- **THEN** the update SHALL succeed — a retry is a new attempt, and this is the one backward edge that is real

#### Scenario: Reviving a refunded payment
- **WHEN** a payment in `refunded` is set to `paid`
- **THEN** the update SHALL be refused

### Requirement: The date a payment is filed under is the system's to decide
WHEN a session that row security applies to records a payment, THE SYSTEM SHALL
stamp `paid_at` itself and SHALL NOT accept a value supplied by the caller.

The financial year is derived from `paid_at`, and three documents claimed it was
"derived from the payment's own date rather than passed in, so a caller cannot
file a March payment into the next year by asking". A blind critic filed
payments into `2031-32` and `2019-20` by asking. **`paid_at` was the argument.**

A trusted writer keeps its own value, because the Razorpay webhook's `paid_at`
is the provider's timestamp and is the more truthful one.

#### Scenario: Filing into another financial year
- **WHEN** a desk session records a payment carrying a `paid_at` two years away
- **THEN** the payment SHALL be filed under the financial year of the instant it was actually recorded

### Requirement: The receipt counter only ever counts up
THE SYSTEM SHALL refuse any change to `document_counters.next_number` that does
not increase it, and SHALL refuse deletion of a counter row.

**Forward, not "by exactly one".** The first draft of this requirement said by
one and contradicted the receipts spec two documents over: *"a gap in a receipt
book is explainable, a reused number is not."* Only a decrease can issue a
number twice, and that is the attack. Requiring a step of one also made a
legitimate test unstageable — a holdout pre-sets the counter to prove the
allocator does not read before it writes — and a rule that forbids the test
proving its neighbour is drawn in the wrong place.

`document_counters_tenant_write` is `FOR ALL` on `is_front_office()` — the same
predicate that lets a person record a payment lets them rewrite the counter.
Reset it and the next payment collides with a number already issued.

**Kept as a rule on the table rather than by revoking the grant or elevating the
allocator.** The allocation is `security invoker` and needs the caller's own
privilege; making it `definer` would add the first unjustified elevated function
in `app` since Phase 2, which a holdout meta-test asserts against by name. A
counter that can only be advanced by one is useless to hand-edit and costs no
elevation.

#### Scenario: Resetting the counter
- **WHEN** `next_number` is set to a value below its current one
- **THEN** the change SHALL be refused

#### Scenario: Allocating a number
- **WHEN** the allocation increments the counter by one
- **THEN** it SHALL succeed

#### Scenario: Staging a counter forward
- **WHEN** `next_number` is set to a higher value
- **THEN** it SHALL succeed, leaving a gap — which a receipt book explains and a repeated number does not

### Requirement: A refund is bounded when it is written and whenever it changes
THE SYSTEM SHALL apply the refund ceiling on insert AND on update, and SHALL
refuse any change to a refund's `payment_id` or `amount_paise` once recorded.

The ceiling passed at insert and the row was then edited past it: a ₹1,000
payment carrying a ₹1,00,000 refund, and every later ceiling check reading that
inflated sum and refusing legitimate refunds. The migration that missed this
quotes ADR-070 three functions above, for a different rule.

#### Scenario: Raising a refund past the payment
- **WHEN** a recorded refund's `amount_paise` is raised so the total exceeds the payment
- **THEN** the change SHALL be refused

#### Scenario: Recording a failed retry against a fully refunded payment
- **WHEN** a refund whose own status is `failed` is recorded against a payment already refunded in full
- **THEN** it SHALL be permitted — a failed refund took nothing, and the rule that excludes failed rows from the sum must exclude them from the comparison too

### Requirement: Money leaving the gym names the person who sent it
THE SYSTEM SHALL require `refunds.initiated_by_staff_id` to be the acting staff
member, and SHALL refuse a refund that names anybody else or nobody.

The manual payment path's whole thesis is that **a manual payment has no
provider to verify against, so attribution IS the integrity**, and that rule now
appears four times on money coming *in*. On money going *out* — the direction
where a gym actually loses — there was no rule at all: the column is nullable,
stamped by nothing and checked by nothing.

#### Scenario: A refund naming a colleague
- **WHEN** a manager records a refund attributed to another staff member
- **THEN** it SHALL be refused

#### Scenario: A refund naming nobody
- **WHEN** a refund is recorded with no `initiated_by_staff_id`
- **THEN** it SHALL be attributed to the acting staff member, and refused outright if the session has no staff identity

### Requirement: A payment extends only the membership of the member who paid
THE SYSTEM SHALL refuse a payment naming a membership that belongs to a
different member.

Nothing related `payments.member_id` to `memberships.member_id`; the extension
matched on `membership_id` and tenant alone, and the console posts both ids as
client-supplied hidden fields. The receipt names one person and the month lands
on another.

#### Scenario: A payment naming another member's membership
- **WHEN** a payment for one member names a membership belonging to another
- **THEN** it SHALL be refused

### Requirement: A period is granted when it has been paid for, not when a payment arrives
WHEN a payment against a membership is `paid`, THE SYSTEM SHALL grant one period
for each whole multiple of that membership's own price that the money against it
has now reached, and no period for money that has not reached one.

**Two half payments bought two months.** ADR-083 closed the create-then-pay
door on precisely this sentence and left the instalment door open: ₹500 now and
₹500 next week is ordinary practice in an Indian gym, and it bought sixty days
on a thirty-day plan.

Counted cumulatively over the membership's own payments, so it needs no marker
column and cannot drift: a payment grants
`floor(total_after / price) − floor(total_before / price)` periods. A full
payment grants one, two halves grant one on the second, a double payment grants
two, and a part payment grants none while still being recorded and receipted.

The price is the membership's own `price_paise` — what was actually agreed,
including any discount — and never the plan's list price.

#### Scenario: Two half payments
- **WHEN** two payments each of half the membership's price are recorded
- **THEN** exactly one period SHALL be granted, on the second

#### Scenario: A part payment alone
- **WHEN** a payment below the membership's price is recorded and no other money has been taken
- **THEN** it SHALL be recorded and receipted and SHALL grant no period

#### Scenario: A membership with no price
- **WHEN** the membership's price is zero
- **THEN** the payment SHALL be recorded and SHALL grant no period, rather than raising

### Requirement: A payment against a membership with no dates grants it a period
WHEN a `paid` payment names a membership that has neither `starts_on` nor
`ends_on`, THE SYSTEM SHALL set both from the gym's today rather than silently
extending nothing.

That state is reachable — `memberships_dated_unless_pending_chk` permits a
`pending` membership with null dates — and after ADR-083 it is exactly the "sold
but not yet paid for" shape. Money was taken, a receipt issued, and nothing
happened.

A membership with a `starts_on` and no `ends_on` is still not extended — it has
not ended, so there is nothing to move.

**That state is only reachable as `pending`**, which a holdout author established
against `memberships_dated_unless_pending_chk` and reported rather than quietly
staging as something else. So "genuinely open-ended and ongoing" is the wrong
description of it: no `active` or `frozen` membership can hold a null `ends_on`
at all. What the rule actually covers is a half-dated `pending` row, and the
honest reading is that such a row is malformed rather than open-ended — it is
left alone here, and naming what should happen to it is a question for whoever
introduces a flow that can create one.

#### Scenario: Paying for a membership that has no dates
- **WHEN** a paid payment names a membership whose dates are both null
- **THEN** the membership SHALL run from the gym's today for the plan's duration

### Requirement: A refusal is the policy's to give, not a side effect of allocating
WHEN a session that may not record payments in a gym attempts to, THE SYSTEM
SHALL refuse it through the policy on `payments` and SHALL NOT first write to,
or fail against, any other table.

ADR-082 recorded this repair once and did half of it. The refusals moved to
`after`, so a member no longer meets `GL034` — but `app.stamp_payment()` is a
`before` trigger, a member can read their own gym's `organizations` row, and so
the allocation runs and is refused by `document_counters`' policy instead. The
SQLSTATE is right by accident and names a table the member has no business
knowing exists.

Allocating a number is front-office work. A session that is not front office has
nothing to allocate, and the policy on `payments` is what should answer it.

#### Scenario: A member recording their own payment
- **WHEN** a member session inserts a payment for themselves
- **THEN** it SHALL be refused by the policy on `payments`, and no counter row SHALL be touched or named
