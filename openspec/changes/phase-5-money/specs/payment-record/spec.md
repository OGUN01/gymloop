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

### Requirement: A receipt number is the counter's alone, at every status
THE SYSTEM SHALL ignore a caller-supplied `receipt_number` for every session row
security applies to, filling it when the payment becomes paid and leaving it
null before that.

Overwriting it only on the write that makes a payment paid left a `created` row
free to carry any number at all — and **one squatted number jams the gym's book
permanently**. The next real payment collides on
`payments_tenant_id_receipt_number_key`; the failing insert rolls the counter's
increment back with it, so `next_number` never advances; and every later payment
collides on the same number for ever. Measured from an ordinary front-desk
session.

`GL037` closed the counter door and this reached the same room through the
payment row. Worse, the handler reports that collision as "already recorded" —
cash taken, nothing written, and a screen saying it is on file.

#### Scenario: A number typed onto an unpaid payment
- **WHEN** a `created` payment is written carrying a `receipt_number`
- **THEN** the number SHALL NOT be kept, and the gym's next paid payment SHALL be numbered normally

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

Counted against what the membership has ALREADY been granted, which is
recorded on it — `memberships.periods_granted` — and never derived by
subtraction: a payment grants `floor(total / price) − periods_granted` periods,
and records the new total.

**Deriving "already granted" by subtracting this payment's own amount from the
running total is wrong, and was wrong three times.** Subtraction needs a
"before" that no `AFTER` trigger has: by the time one runs, every row of its
statement, every sibling trigger invocation, and every earlier statement of the
transaction has already landed in the table being summed. Round one subtracted
per payment and ten separate statements bought ten periods. Round two subtracted
per row and ten rows in one statement bought ten periods. Round three subtracted
per statement and an `INSERT … ON CONFLICT DO UPDATE`, which fires BOTH
statement triggers, bought two. **One mistake, three shapes, each time believed
fixed.**

A recorded count is idempotent, order independent, and indifferent to how many
triggers fire for one statement or how many statements make up a transaction. A full
payment grants one, two halves grant one on the second, a double payment grants
two, and a part payment grants none while still being recorded and receipted.

**The total counts money that ARRIVED — `paid`, `refunded` and `reversed` — not
money still held.** A refund does not reverse the extension it bought, so the
total must not fall when one is issued. Summing only `paid` rows looks right and
double-grants: half now and half next week grants one period on the second, then
refunding the first half drops the total back below the line so the next half
crosses it again. Monotonic is what makes "crossed a multiple" mean anything.
This paragraph is here because a critic found the rule stated only in a SQL
comment, where the next blind test author would never read it.

**The count is per PAYMENT, however many arrive in one statement.** Ten payments
written by one `insert … select` are ten payments and grant what ten payments
buy — not ten periods each. A rule that re-derives the total from the table
cannot tell them apart: every row of a statement is already in the table by the
time an `AFTER … FOR EACH ROW` trigger runs, so each row sees the final total,
subtracts only its own amount, and concludes it was the one that crossed the
line. Measured — ₹1,000 in ten rows bought **300 days** on a 30-day plan, from
an ordinary front-desk session, through one `supabase-js` call.

**The money must be the membership's own currency.** `amount_paise` summed
across currencies and compared to `memberships.price_paise` grants a month for
money in a currency the gym does not price in (MNY-002, AGENTS.md rule 8).

**And the count must be serialised on the membership.** Two transactions each
recording half the price, concurrently, each see only their own row and each
grant nothing — and the deficit is permanent, because every later payment
measures against the same total. Silent, and in the direction the member
complains about. `app.enforce_refund_total()` takes `for update` on the payment
for exactly this reason; the extension needs the same on the membership.

#### Scenario: Many payments in one statement
- **WHEN** several paid payments against one membership are written by a single statement
- **THEN** the membership SHALL gain exactly the periods their total buys, and no more

#### Scenario: A payment in another currency
- **WHEN** a paid payment's currency differs from the membership's
- **THEN** it SHALL grant no period

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

### Requirement: The terms a period was scored against do not change after it is granted
WHERE a membership has been granted at least one period, THE SYSTEM SHALL refuse
any change to the terms its money is scored against — its price, its currency,
and the plan whose duration a period is measured in — and SHALL leave the
membership as it stood.

A period is granted for each whole multiple of the membership's own price that
its money has reached, and it lasts the duration of the membership's own plan.
**Every one of those three inputs is re-read on the next payment and applied to
all the money already on record**, so changing one retroactively re-prices or
re-lengthens periods that were already bought and paid for.

Measured, each in a single ordinary front-desk statement: cutting a ₹1,000 price
to ₹500 and then paying **one paisa** released a second month, and it compounds —
`floor(200000/50000)` is four periods, not two. Repointing a 30-day membership at
a 365-day plan and paying one further ₹1,000 moved `ends_on` **395 days**.

The terms a membership was sold on are recorded facts, like a payment's amount
and for the same reason: they are what the member agreed to, and every period
already granted was granted against them. **Correcting a mistyped price or a
wrong plan before any money has arrived stays free** — nothing has been scored
yet. Afterwards the honest instrument is a refund and a new membership, which
this phase has.

#### Scenario: Cutting the price after a period was bought
- **WHEN** a front-desk session lowers the price of a membership that has been granted a period
- **THEN** it SHALL be refused, and the price SHALL be unchanged

#### Scenario: Repointing a paid membership at a longer plan
- **WHEN** a front-desk session changes the plan of a membership that has been granted a period
- **THEN** it SHALL be refused, and a further payment of the full price SHALL grant one period of the ORIGINAL plan's length

#### Scenario: Correcting a mistake before any money arrives
- **WHEN** a front-desk session changes the price or the plan of a membership that has been granted nothing
- **THEN** it SHALL be allowed

#### Scenario: Renewing
- **WHEN** an ordinary payment extends a membership that has been granted a period
- **THEN** it SHALL succeed — the rule's own write to the membership is not a change of terms

### Requirement: How many periods have been granted is written by the rule and by nobody else
THE SYSTEM SHALL maintain `memberships.periods_granted` only as part of granting
a period, and SHALL refuse every other write to it, whatever its value.

**A freeze is worth exactly as much as the immutability of the thing it is keyed
on.** The requirement above is keyed on "has been granted at least one period";
while that count could be typed by the same session the rule constrains, the rule
guarded nothing. Measured, all from an ordinary front-desk session:

  * setting the count to `0` and then paying **one paisa** granted a full month;
  * setting it to `0`, then cutting the price, then paying one paisa granted two
    and a half months for ₹1,000.01;
  * setting it to `500` made an ordinary ₹1,000 payment grant **nothing** — the
    money taken and receipted, `ends_on` unmoved, no error anywhere. This is the
    silent harm ADR-088 was written about, reached by hand instead of by
    rounding.

Bounding the column's sign does not close any of it: every one of those uses a
value the rule itself can produce. What is wrong is not the number, it is that a
hand wrote it.

#### Scenario: Resetting the count
- **WHEN** a front-desk session sets `periods_granted` on a membership to any other value
- **THEN** it SHALL be refused, and the count SHALL be unchanged

#### Scenario: Staging the count forward
- **WHEN** a front-desk session raises `periods_granted` above what the money bought
- **THEN** it SHALL be refused — a payment that grants nothing while taking the money is worse than one that is refused outright

**A membership is created having been granted nothing.** The rule above is
written as though the only way to get a count is to type one onto an existing
row; a holdout author measured the other way in and it works — a front-desk
session **creates** a membership carrying `periods_granted = 5`, then takes
₹1,000 for it, and `ends_on` does not move while the receipt is issued. That is
the third exploit above with no UPDATE anywhere in it.

So the count SHALL be zero when a membership is created. Nothing in the product
creates one otherwise: the console's create path does not write the column, the
seed does not, and the granting rule only ever updates. **Closing three doors and
leaving the fourth is the mistake this whole requirement exists to correct** —
the round before it froze two terms of three.

**Two questions the first draft left open, decided here rather than left to the
implementation:**

  * **Writing the same value back is allowed.** `periods_granted = 1` on a row
    already reading `1` changes nothing, and every exploit needs the value
    moved. A rule that refuses a write that cannot do harm buys nothing and
    breaks ordinary column-listing updates.
  * **`discount_paise` is deliberately NOT a frozen term.** A holdout author
    asked why it is missing from the list, which was the right question: it
    exists, the seed uses it, and ADR-088's worked example is a discounted
    membership. The reason is that nothing in the money path reads it — a
    period is scored against `price_paise` alone. Freezing it would be a claim
    the system does not make. **Whoever teaches the granting rule to score
    against `price_paise - discount_paise` adds `discount_paise` to this
    requirement in the same change**, because at that moment it becomes a term
    and grows exactly the door the other three had.

#### Scenario: The rule granting a period
- **WHEN** a payment grants a period
- **THEN** the count SHALL be updated to what the money now owes

#### Scenario: A membership created with periods already granted
- **WHEN** a front-desk session creates a membership whose `periods_granted` is not zero
- **THEN** it SHALL be refused

#### Scenario: Writing the same count back
- **WHEN** a write leaves `periods_granted` at the value it already held
- **THEN** it SHALL be allowed

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
staging as something else.

**A HALF-dated `pending` row is not left alone, and this paragraph used to claim
it was.** A critic measured it: a row with `starts_on` null and `ends_on` set is
extended and its periods recorded, because the extension's guard is
`ends_on is not null` — but it is NOT activated, because activating a row with a
null `starts_on` violates the same CHECK. So money is taken, a receipt issued,
the period recorded, and the member stays refused at the gate with no product
path to fix it. Round three made that abort loudly with an unmapped `23514`;
round five's guard traded the loud failure for a silent one, which is the wrong
direction by this project's own tie-breaker.

It is reachable only by direct write — the console never creates a half-dated
row — so it is carried as an open decision rather than solved by guessing what a
malformed membership should mean. What is NOT acceptable is the spec saying one
thing while the code does another, which is what this correction fixes. So "genuinely open-ended and ongoing" is the wrong
description of it: no `active` or `frozen` membership can hold a null `ends_on`
at all. What the rule actually covers is a half-dated `pending` row, and the
honest reading is that such a row is malformed rather than open-ended — it is
left alone here, and naming what should happen to it is a question for whoever
introduces a flow that can create one.

**And it SHALL be made `active` at the same time.** Granting the dates and
leaving the row `pending` produces a membership that has been paid for and whose
member is refused at the gate, because `app.enforce_check_in()` requires
`active` or `frozen` (ADR-084). Two changes shipped in one round, contradicting
each other in exactly the area that round was about.

#### Scenario: Paying for a membership that has no dates
- **WHEN** a paid payment names a membership whose dates are both null
- **THEN** the membership SHALL run from the gym's today for the plan's duration, and SHALL become `active`

#### Scenario: The member it was paid for
- **WHEN** that member presents at the gate the same day
- **THEN** they SHALL be admitted — a membership that has been paid for admits its member

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
