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

### Requirement: A refund that completed did not fail
WHEN a refund's status changes, THE SYSTEM SHALL refuse any change out of
`completed`.

**The ceiling is keyed on a value the constrained party rewrites.** `GL036`
bounds the refunds against a payment by summing the ones that are not `failed`,
and nothing froze a refund's status — so a gym admin could demote a completed
refund to `failed`, which takes it out of the sum, and the books then show money
that left the gym as an attempt that never happened. Measured: full refund
accepted, second full refund refused by `GL036`, first refund demoted to
`failed`, second full refund then **accepted**.

The asymmetry is the tell: re-completing the demoted refund is refused, because
by then the sum is full. **You could un-count freely and never re-count** — a
one-way door out of the ledger.

This is ADR-089's own general form, one table over: a freeze is worth exactly
as much as the immutability of the thing it is keyed on. A payment that is
`paid` cannot walk backwards (`GL039`); a refund that completed is the same kind
of fact, and money that left the gym does not become an attempt.

#### Scenario: Demoting a completed refund
- **WHEN** a session changes a `completed` refund's status to anything else
- **THEN** it SHALL be refused and the refund SHALL be unchanged

#### Scenario: A refund that genuinely failed
- **WHEN** a refund that is not `completed` moves between its other statuses
- **THEN** it SHALL be allowed, and the ceiling it was consuming SHALL be released

**Why the door at `requested` and `processing` stays open, since both blind
authors found it and neither would guess.** The same un-counting works from
those statuses — the ceiling sums everything that is not `failed` — and the
first draft of this requirement permitted it without saying why. It is
deliberate: **a refund at `processing` is money the gym has handed to the
provider and the provider has not yet moved.** It can genuinely fail; that is
what the status is for, and refusing the transition would strand it while the
ceiling permanently consumed money that never left.

So the invariant is narrower than "the ceiling is never released": **money that
LEFT does not become an attempt. Money in flight may.**

And the ceiling is not what holds the line there — a different rule is, which
the visible author measured: `GL036` applies on UPDATE as well as INSERT, so an
un-counted refund can never be completed again once the second one has taken the
room. **At most one of the two ever reaches `completed`**, whichever order they
are written in.

The refusal code is `GL041` — a refund is a record, which is the family this
belongs to, rather than a new number. The two requirements below reuse `GL036`
and `GL042` for the same reason: each is the code whose own requirement already
names the harm being closed.

### Requirement: Money only comes back out of money that came in
WHEN a refund names a payment, THE SYSTEM SHALL refuse it unless that payment
has actually taken money — `paid`, `refunded` or `reversed`.

`app.enforce_refund_total()` reads a payment's `amount_paise` and never its
status, and `amount_paise` is not null on a `created` row. So a full refund
against a payment that never arrived was **accepted**: money recorded as leaving
the gym against money that never came in.

**The screen already claims this is impossible.**
`apps/web/app/(console)/payments/[paymentId]/page.tsx` says "a payment that is
not paid has taken nothing … The database refuses both (`GL036`)". The second
half is true and the first half was not; the only thing enforcing it was the
absence of a button, and `POST /api/refunds` takes a `paymentId`.

#### Scenario: Refunding a payment that never arrived
- **WHEN** a refund names a payment whose status is `created`, `pending` or `failed`
- **THEN** it SHALL be refused and no refund SHALL exist

#### Scenario: Refunding money that did arrive
- **WHEN** a refund names a `paid`, `refunded` or `reversed` payment
- **THEN** it SHALL be bounded by `GL036` as it is today

### Requirement: A membership belongs to the member it was sold to
WHEN a session that this rule is in force for changes a membership's
`member_id` to a different member, THE SYSTEM SHALL refuse it.

**Two sessions it is not in force for, both disclosed rather than discovered:** a
session whose tenant claim does not match never reaches the row (the policy's
`USING` filters it — `UPDATE 0`, no exception, nothing moved), and **the seed
disables this rule's trigger around its own statements**, inside which a
membership genuinely can be re-pointed. Measured, both. Neither is a hole — one
changes nothing and the other is the fixture builder — but three drafts said
"any session" and a fourth said "a session that can see it", and the seed can
see it.

"A payment extends only the membership of the member who paid" (`GL042`) is
evaluated on the **payment** row, and `memberships.member_id` was frozen by
nothing — not the terms rule, whose column list is closed and excludes it, and
not the stamp. Measured, from a **front-desk** session, in one statement: a
membership carrying a granted period moved to a different member, while the
paid payment still named the original one and carried their receipt number.

That is verbatim the harm `GL042`'s own requirement names — **"the receipt names
one person and the month lands on another"** — reached by another route, by the
least-privileged writer who can reach the table at all.

A membership is sold to somebody. Correcting who it was sold to is not an edit;
it is a refund, a cancellation and a new sale, which is the answer this phase
gives for every other recorded fact.

**A trap for whoever tests this**: several mechanisms answer before this rule
does, so a careless check reports a false GREEN on an accident rather than on
`GL042`. The move must be attempted against a **different** member who holds
nothing, with a statement that writes no status and leaves a row the table's own
constraints accept. Three shortcuts look equivalent and are not:
`memberships_tenant_id_member_id_live_key` gives `23505` when the stored tuple is
`active` or `frozen` **and** the target holds another such row; a null-dated
`pending` membership gives `23514` if a status is written without dates — the
shape `seed-scenarios.sql` leaves live in the demo gym; and re-pointing at the
member who already owns it is permitted outright, because `GL042` fires on
`is distinct from`. Which mechanism answers is **observed, not contracted**
(ADR-105).

#### Scenario: Moving a membership to another member
- **WHEN** a session that can see the membership changes its `member_id`
- **THEN** it SHALL be refused and the membership SHALL be unchanged

**"That can see it" replaces "any", because two kinds of session are not
refused** and both are recorded above: a session whose tenant claim does not
match never reaches the row at all — the policy's `USING` filters it, giving
`UPDATE 0` and no exception — and the seed disables this rule's trigger around
its own statements. Neither can move a membership, so neither is a hole; but the
scenario said "any" while an assertion in the visible suite proves a wrong-tenant
session raises nothing, and a spec-first author derives from the scenario.

**And it SHALL be this rule that answers, not another one the same statement
also violates.** A statement that re-points a membership AND writes a length is
two violations at once, and which refusal comes back is what the caller acts on:
`GL043` says "change the plan instead", which is advice about a plan, while the
true answer is that this membership belongs to somebody else and the repair is a
refund, a cancellation and a new sale. **Which rule answers is part of the
behaviour, not an implementation detail** — this file already says so for the
multi-row case, where a mixed statement is refused by whichever rule its first
row reaches. For a single row it is decidable, so it is decided here.

This is written down because it silently stopped being true: a later migration
re-emitted the enforcing function to add something unrelated and moved this
check after the length check. Both refusals still existed and every assertion in
both suites still passed, because no assertion named a statement that violates
two rules at once (ADR-099).

**"Not another one" means every other one, and a holdout author read it that way
and was right to.** The sentence above was written with the length rule in view,
so the first version of this requirement illustrated it with the length rule and
left the general claim unqualified. An author working from this text alone
asserted the general form — re-pointing *and* typing a period count, re-pointing
*and* re-dating — and measured both answering with the other rule. The
implementation checked ownership third, after the two depth-gated invariants.

**So exactly one thing is decided here: `GL042` answers ahead of every other
rule that can refuse the same statement** — `GL043`, `GL044`, `GL045`, `GL046`
and `GL047` alike. It is the only rule among them about **whose** membership
this is; every other one is about what may be done to a membership already
agreed to be yours. A caller acts on the message, and "take the money and the
dates follow", "change the plan instead" and "a membership does not go from
cancelled to active" are all advice for somebody working on their own member's
membership. The repair differs too: the others are answered by taking a payment
or by asking a manager, `GL042` only by a refund, a cancellation and a new sale.

**The order among the rest is deliberately not decided.** An earlier draft of
this paragraph numbered all four absolutes 1 to 4 and then said four lines later
that the order among 2, 3 and 4 was not claimed — a critic pointed out that a
numbered list *is* a claim, and that an implementer reading this file alone
would take `GL044`-before-`GL045` as contract. They are a set, not a sequence.
`GL046` stays last of the set for the reason already recorded: an absolute beats
a permission, and answering the permission would imply a gym admin could do it.

**`GL047` is in that set, and putting it there took a trigger rename rather than
a clause move.** `GL047` lives in its own trigger — `memberships_transitions_after_terms`
since ADR-101, `memberships_status_transitions` before it — deliberately, because both seed files disable the terms trigger and
folding it in would have left it silently off for the whole seed (ADR-098).
Postgres fires same-timing row triggers **in trigger-name order**, and
`memberships_status_transitions` sorts before `memberships_terms_frozen`, so
`GL047` answered ahead of all five rules in that function. Measured: re-pointing
a `cancelled` membership and reviving it in one statement answered `GL047` where
this requirement says `GL042`. No reordering of clauses inside the function
could ever have reached it. The trigger is renamed to sort after the terms
trigger, which keeps the property that made it separate.

#### Scenario: Re-pointing a membership and re-lengthening it in one statement
- **WHEN** one statement changes a membership's `member_id` and its `duration_days`
- **THEN** it SHALL be refused with the `member_id` rule, not the length rule

**For a row that violates both, `GL042` answers ahead of the other rules in its
own trigger — `GL043`, `GL044`, `GL045`, `GL046` — and ahead of `GL047`. That is
the whole of the normative claim, and everything below this paragraph is an
observation rather than a contract.**

**"For a row" is the load-bearing phrase and leaving it off cost a round.**
Postgres does not order the row triggers of a *statement*, so a statement
touching several rows is refused by whichever rule its first row reaches — and
a two-row statement in which one row violates `GL042` and another violates
`GL044` can answer `GL044`. Measured, from an ordinary front-desk session, with
no CASE expression and nothing exotic:

    update public.memberships set member_id = <C>, status = 'pending'
     where id in (<a>, <b>);            -->  GL047
       -- <a> alone                     -->  GL042
       -- <b> alone                     -->  GL047

**The answer even flips with the query plan** — the same SET list under
`where tenant_id = …` takes a sequential scan and answers `GL042`. This file had
the fact fifty lines upstream as an aside, and `docs/registry.md` has carried it
since round eleven; the paragraph that then called itself "the whole of the
normative claim" was written without it. Restating a claim more prominently is
an opportunity to drop one of its qualifiers.

**Why the scope shrank, recorded because it took five critic rounds to earn.**
Earlier drafts of this requirement tried to state, normatively, which of *every*
mechanism Postgres can refuse a statement with would answer first. Five attempts
were written and all five were measured false:

| attempt | killed by |
|---|---|
| "`GL042` in every case" | the live-membership index, `23505` |
| "…unless the target holds a live membership" | four more families in the scenario's own column list |
| "…CHECK, index, foreign key, policy are not rules" | `not null` (`23502`) and `before` triggers |
| "…nothing enforced earlier in the statement" | a foreign key pointing AT this table is an `after` trigger ON it |
| "…and the resulting row satisfies the table's CHECK constraints" | `not null` again (`23502`), and `42501`, and a `22003` out-of-range |

**The surface is not enumerable and was never a product requirement.**
`public.memberships` carries **22 triggers**, of which **13 fire on UPDATE** — nine of them internal,
against the four this project wrote; there are **seven** CHECK constraints, six
`not null` columns among those a caller can write, a row-security policy that
*filters* rather than refuses, and every type-range error the column set admits.
No sentence can close that set, and it grows whenever anyone adds a column, a
constraint, or a table that references this one.

**And nothing depends on it.** What a caller needs is: *the move did not happen.*
Every measured route — `GL042`, `GL043`, `GL047`, `23502`, `23503`, `23505`,
`23514`, `42501`, `22003`, and the policy's silent `UPDATE 0` — either refuses
the statement or changes nothing. ADR-092's grep passes on all of them: no route
reaches the harm. The one narrow thing that *did* matter was a real defect —
`GL043` answering where `GL042` should, so a desk correcting a mis-sale was told
"change the plan instead" — and that is exactly what the sentence above still
covers, because those five codes live in one function this project controls.

> ### Observed refusal behaviour — NOT a contract
>
> Recorded so nobody re-derives it, and explicitly **not** something to code
> against. It is measurement of one Postgres version's behaviour on one schema.
>
> * A statement is refused `23505` by `memberships_tenant_id_member_id_live_key`
>   only when **both** hold: the tuple being *stored* falls inside the index's
>   partial predicate (`status in ('active','frozen')`), **and** the target
>   member already holds another row inside it. Neither alone is enough.
> * A `pending` membership with null dates answers `23514` from
>   `memberships_dated_unless_pending_chk` when a statement writes a non-`pending`
>   status **and does not supply both dates**. Supplying them satisfies the
>   CHECK, and the statement then falls through to the rules above.
> * `not null` (`23502`), foreign keys in either direction (`23503`), the
>   row-security policy's `with check` (`42501`) and type-range errors (`22003`)
>   can each answer ahead of `GL042`.
> * A session whose tenant claim does not match never reaches the row: the
>   policy's `USING` clause filters it, giving `UPDATE 0` and **no exception**.
> * The seed disables this rule's trigger around its own statements, so a
>   membership **can** be re-pointed inside that window. Measured. It is not a
>   hole because nothing but the seed runs there, but "cannot" would be false and
>   an earlier draft said it.
>
> The suite asserts a sample of these — sections 34, 35 and 36 of
> `supabase/tests/22_payment_record.sql` — precisely so that **nobody may rely on
> them**, which is what ADR-100 prescribes for an undecided pair. They are
> regression pins, not promises.

#### Scenario: Re-pointing a membership and typing anything else onto the same row
- **WHEN** one statement changes **one membership's** `member_id` and also that same row's `periods_granted`, dates, price, or status
- **AND** nothing outside this trigger refuses the statement first
- **THEN** it SHALL be refused with the `member_id` rule

#### Scenario: One statement touching several memberships
- **WHEN** one statement violates `GL042` on one row and another of this trigger's rules on a different row
- **THEN** it SHALL be refused, and this requirement SHALL NOT decide which rule answers — Postgres does not order a statement's row triggers, and the answer varies with the query plan

#### Scenario: Re-pointing a membership at a different member who already has one
- **WHEN** one statement points a membership at a **different** member who already holds a live one
- **THEN** it SHALL be refused, and the membership SHALL be unchanged

**"Different" is not padding.** `GL042` fires on `is distinct from`, so a
statement setting `member_id` to the value it already holds is permitted — and a
membership's own owner trivially "already holds a live one", namely this
membership. An earlier draft's WHEN was satisfiable by a statement that succeeds.

#### Scenario: Selling a member a second membership
- **WHEN** a member's membership is cancelled and a new one is sold to the same member
- **THEN** both SHALL be allowed — this rule refuses re-pointing, not selling

#### Scenario: Selling somebody else a membership
- **WHEN** a membership is created for a different member
- **THEN** it SHALL be allowed — the rule governs a change, not a creation

The heading of the first of these said "the same member" while its own WHEN said
"another member", which are two different acts; a blind author asserted both
rather than choose, which was right. **Both scenarios were deleted by accident**
in the commit that rescoped this requirement — a span replacement swallowed them
— in a change whose own thesis was "nothing was deleted or weakened". A critic
found them missing. The property never lapsed, because the holdout suite asserts
it and quotes the deleted sentence verbatim, but the claim in ADR-105 was wrong
until this restored them.

### Requirement: Money leaving the gym names the person who sent it
THE SYSTEM SHALL require `refunds.initiated_by_staff_id` to be the acting staff
member, and SHALL refuse a refund that names anybody else. **A refund naming nobody is STAMPED, not refused** — the scenario below has said so since it was written, this sentence said the opposite for the whole phase, and the implementation follows the scenario (measured: a refund inserted with no actor comes back attributed to the caller's `staff_id`). A normative sentence that disagrees with its own scenario is the defect that produced two rounds of this phase, and it is the sentence a spec-first author derives from.

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

> **Narrowed by "Money does not extend a membership that has been retired",
> 476 lines below in this same file.** This sentence is unconditional and a `cancelled` or
> `expired` membership is the exception: the payment is still recorded,
> receipted, attributed, refundable and bounded by `GL036`, and the membership
> does not move.
> The exception is 476 lines below this sentence in this same file, which is far
> enough that a reader can hold one and not the other — the distance is the
> defect, not the disagreement.


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

The price is the membership's own `price_paise`, and never the plan's list
price. **This used to add "including any discount", and that was false against
the only rows where a discount exists**: `seed.sql` writes a GROSS `price_paise`
plus a separate `discount_paise`, so the demo gym's one discounted membership is
priced ₹12,000 with ₹1,200 off, has paid ₹10,800 — her agreed price — and is
scored against ₹12,000, granting nothing while the console tells the desk she
still owes ₹1,200. Nothing in the money path reads `discount_paise`, which this
same file states 220 lines below, where it contradicted this sentence for two
rounds. Whether the agreed price is the gross or the net is a product question
this phase does not answer: **OPEN-028**, and the sentence no longer claims an
answer it does not have.

#### Scenario: Two half payments
- **WHEN** two payments each of half the membership's price are recorded
- **THEN** exactly one period SHALL be granted, on the second

#### Scenario: A part payment alone
- **WHEN** a payment below the membership's price is recorded and no other money has been taken
- **THEN** it SHALL be recorded and receipted and SHALL grant no period

#### Scenario: A membership with no price
- **WHEN** the membership's price is zero
- **THEN** the payment SHALL be recorded and SHALL grant no period, rather than raising

### Requirement: The terms money is scored against are frozen by money arriving
WHERE any money has arrived against a membership, THE SYSTEM SHALL refuse any
change to the terms that money is scored against — its price, its currency, and
the plan it was sold on — and SHALL leave the membership as it stood.

The duration a period is measured in is frozen harder than these and by a
different rule: it is derived from the plan and never typed, so it cannot be
changed at all except by changing the plan, which this requirement refuses once
money has arrived.

**Frozen by the first payment, not by the first period.** A membership that has
taken real money but not yet crossed one whole multiple of its price has been
granted nothing, and an earlier draft of this requirement left it wide open —
its own scenario said "granted nothing" three lines under prose saying "before
any money has arrived", and the second sentence is the correct one. A part
payment is ordinary practice and the console says so on the page: a full price
buys a period, part of it is recorded and receipted and buys none until the
balance is paid.

Measured on a real row of the demo gym, ₹10,800 arrived against a ₹12,000
Annual: cut the price to ₹1,000 — allowed, because nothing had been *granted* —
then pay **one paisa**, and `ends_on` moves **ten years**. The money was always
being scored; the total counts every paisa that has arrived whether or not it has
crossed a multiple.

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
and for the same reason: they are what the member agreed to, and every paisa on
record was taken against them. **Correcting a mistyped price or a wrong plan
before any money has arrived stays free** — nothing has been scored yet.
Afterwards the honest instrument is a refund and a new membership, which this
phase has.

**The duration a period is measured in is one of those terms, and it SHALL be
recorded on the membership** rather than read from the plan when money arrives.
A membership already records the price and the currency it was sold at; the
duration was the one term still read live from `plans`, and one manager statement
setting `duration_days = 3650` followed by an ordinary renewal moved `ends_on`
**3650 days** — silently, and to every membership on that plan. Recording it
means editing a plan changes what the *next* membership is sold at and nothing
about one already sold, which is what editing a plan should mean. Freezing the
plan row instead would punish the legitimate act to prevent the illegitimate
one.

**A period's length is derived, never negotiated.** A membership records the
duration its plan carried at the moment of sale, and it is not a number anyone
types — at creation or afterwards, with money on record or without. The previous
draft of this requirement named the harm ("create a membership naming
`duration_days = 3650`, pay the ordinary price, get ten years") and then
permitted the identical outcome in two statements instead of one; measured, an
ordinary ₹1,500 on a 30-day plan bought **3,650 days**, and the record it leaves
is fully self-consistent — one receipt, one period granted, `ends_on` exactly one
recorded period — so no audit can see it afterwards.

**`price_paise` is a negotiated number a desk legitimately mistypes;
`duration_days` is not.** A wrong length is a wrong plan, and the instrument for
that is changing the plan, which carries the length with it. So this term
belongs with `periods_granted` rather than with the price: it may change only as
part of a plan change, and only to what that plan says.

**And a plan change carries the price too.** Correcting a mis-sold Monthly to an
Annual re-derived the length and left the Monthly price behind, so one ₹12,000
Annual fee bought `floor(1200000 / 150000)` = eight periods of 365 days —
**2,920 days**. Price and length come from the same plan or from neither, unless
the correction names a price of its own, which keeps a negotiated price possible.

**Why creating ignores a named length while editing refuses one**, which both
blind authors read as an inconsistency and were right to: `memberships.duration_days`
carries a database default, so inside a `before insert` trigger a caller who
wrote `1` and a caller who wrote nothing are **the same row**. Refusing "a length
the caller named" is not implementable at creation, because there is no such
thing to detect. On update there is — `old` exists — so there it is refused, and
refusing is the better answer wherever it can be given. Silently discarding a
write stays the thing this codebase asserts against; at creation it is discarding
a value nobody can prove was written.

**A length riding a permitted plan change lands as the plan's**, not as typed and
not refused. The statement is the sanctioned way to change a length, and the
length it produces is the plan's by definition; the caller's number is not
refused because the statement is legitimate, it is simply not where the number
comes from.

**Naming a price equal to the one already recorded is indistinguishable from
naming none**, and the plan's price wins. A row trigger sees values, not which
columns a statement listed, and `is distinct from` is this codebase's idiom for
exactly that. The consequence is worth stating because it is a real edge: a desk
that retypes the agreed number to protect it across a plan correction will get
the new plan's list price instead. **To keep a negotiated price across a plan
change, name a different number, or set the price in a second statement** — which
is permitted for as long as no money has arrived.

**The plan's currency travels with its price.** `plans` carries a currency,
the currency is half of what a price MEANS (MNY-002), and the granting rule sums
money in the membership's own currency — so taking a plan's price without its
currency would score the new number against the old denomination, which is wrong
by an exchange rate and looks entirely ordinary.

#### Scenario: Correcting a mis-sold plan with a length of its own named
- **WHEN** a plan correction also names a `duration_days`
- **THEN** the length recorded SHALL be the new plan's, and the statement SHALL be allowed

#### Scenario: A plan priced in another currency
- **WHEN** a plan correction takes the new plan's price
- **THEN** it SHALL take that plan's currency with it, or neither

#### Scenario: Creating a membership that names its own length
- **WHEN** a membership is created naming a `duration_days` of its own
- **THEN** the length recorded SHALL be the plan's, not the one named

#### Scenario: Typing a length onto a membership
- **WHEN** any session changes `duration_days` other than by changing the plan
- **THEN** it SHALL be refused with `GL043` and the length SHALL be unchanged, whether or not money has arrived

The code is `GL043` and not `GL044`, which the first draft of this requirement
left open and both authors had to ask about. The length is a term of the
membership and a reader chasing it will look where the other terms are; that
beats the conceptual tidiness of grouping it with the count it more closely
resembles.

#### Scenario: Correcting a mis-sold plan
- **WHEN** a **gym admin** changes the plan of a membership against which no money has arrived
- **THEN** the length AND the price SHALL both become the new plan's, and a payment SHALL buy exactly one period of it

#### Scenario: Correcting a mis-sold plan at a negotiated price
- **WHEN** that correction names a price of its own in the same statement
- **THEN** that price SHALL stand, and the length SHALL still be the new plan's

#### Scenario: A front desk correcting a mis-sold plan
- **WHEN** a front-desk session changes the plan of a membership, with or without money against it
- **THEN** it SHALL be refused — who may re-price is settled below and does not change with the plan

**These two scenarios said "a front-desk session" for five rounds.** Round
eleven corrected the third one below them and left these, citing the harm they
carry — which is the same defect the correction was written to fix, one
paragraph further down the same file. The visible suite's author then quietly
sent the assertion as a manager, so both suites stayed green while the contract
they derive from said the opposite of the shipped rule; the next spec-first
author would have written the front-desk assertion the spec asked for and the
next implementer would have "fixed" the trigger back into the 300-day hole.

**A cost this creates, recorded rather than left to be found.** Correcting a
mis-sold plan is now gym-admin work, and `POST /api/memberships` has no update
path — so a desk that sells the wrong plan cannot fix it at all, and OPEN-024
already blocks selling a replacement while the first is live. Whoever adds a
membership-edit screen owns that; until then the remedy is the one below:
refund, cancel, sell again.

#### Scenario: Cutting the price after a period was bought
- **WHEN** a front-desk session lowers the price of a membership that has been granted a period
- **THEN** it SHALL be refused, and the price SHALL be unchanged

#### Scenario: Cutting the price of a part-paid membership
- **WHEN** a front-desk session lowers the price of a membership that has taken money but been granted nothing
- **THEN** it SHALL be refused, and a further payment SHALL buy only what the ORIGINAL price says it buys

#### Scenario: Repointing a paid membership at a longer plan
- **WHEN** a front-desk session changes the plan of a membership that has taken any money
- **THEN** it SHALL be refused, and a further payment of the full price SHALL grant one period of the ORIGINAL length

#### Scenario: Lengthening the plan a membership was sold on
- **WHEN** a gym admin changes `duration_days` on a plan
- **THEN** memberships already sold on it SHALL keep the length they were sold at, and only memberships created afterwards SHALL use the new one

#### Scenario: Correcting a mistake before any money arrives
- **WHEN** a **gym admin** changes the price or the plan of a membership against which no money has arrived
- **THEN** it SHALL be allowed

**This scenario said "a front-desk session" for four rounds, and that is the
sentence a critic walked through to buy 300 days for one month's fee.** The
requirement names the ten-years harm in its own prose and then permitted the
identical outcome through the other factor of the same product — ADR-092's
grep, written after round nine and not run until round eleven. Who may re-price
is settled by "Deciding what a member owes is gym-admin work" below; this
scenario is about *when*, and it now says who as well so the two cannot drift
apart again.

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

### Requirement: Deciding what a member owes is gym-admin work
WHEN a session changes a membership's `price_paise`, `currency`, `plan_id`,
`discount_paise` or `coupon_id`, THE SYSTEM SHALL refuse it unless that session
is a gym admin, and SHALL leave the membership as it stood.

`ends_on` is `duration_days x floor(money / price_paise)`. The requirement above
made the length underivable by hand because it multiplies that product. **The
price is the other factor and it was freely typed.** Measured: a front desk sets
a Rs.1,500 membership's price to Rs.150 and takes the ordinary Rs.1,500 — **300
days, ten periods**, both audit invariants intact, and after round ten the row
cannot be repaired in place at all.

**The control is who, not what.** Deriving the price from the plan would leave no
way to sell at a negotiated number, which gyms do; bounding it invents a
threshold nobody chose; bounding the discount instead moves the same exploit to
a different column. This product already answers this question one table over —
`refunds_tenant_write` is gym-admin, not front-office, because "front_desk may
record money but not refund it". **Deciding what a member owes is the same kind
of act as deciding to give money back.** The front desk sells at the plan's
price and takes payment.

A gym admin can still comp a membership to a paisa, and should be able to. That
leaves the price on the row as evidence; what this removes is the front desk
doing it silently.

**`coupon_id` is in the list too**, because it is the column that names *why* a
member owes less. A critic found a front desk could attach a 10%-off coupon
while being refused the discount it implies, leaving rows reading "coupon
applied, discount zero" — either both belong to the gym admin or neither does,
and they describe the same decision.

**When the comp was a typo.** A membership sold at one paisa and then paid
against is frozen by the requirements above: the price cannot be corrected
(money has arrived) and the dates cannot be typed back. **Nobody can put that
row back, not even the owner** — and this requirement's own prose names
unrepairability as what made the previous round worse, so it has to say what to
do instead. The answer is the one this phase gives for every other recorded
fact: **refund the payment, cancel the membership, and sell a new one.** What is
not available is editing the row into a different sale, and that is deliberate.

**A refund on its own is not the repair**, which an author found by running the
sequence rather than reading it: after a full refund the membership still reads
its ten periods, still ends three hundred days out and is still `active`,
because refunded money still counts toward the total and nothing it bought comes
back. Without the cancellation the gym is left with a live, wrongly-dated
membership admitting its member at the gate. The cancellation is the repair; the
refund is the money.

**The desk cannot start it, but it can finish it — and can also do the middle
step alone, which is not obviously right.** `refunds_tenant_write` is gym-admin,
so the refund is an admin's. **Cancellation is not gated at all**: a critic
measured a front desk retiring a live, fully-paid membership by itself. So the
remedy's three steps sit at three different levels — refund (admin), cancel
(anyone front-office), re-sell (anyone front-office) — and an earlier draft of
this paragraph claimed the desk could only do the last. Whether cancelling a
paid membership should be admin work is a real question this phase does not
answer; it is not the money path, and nothing about it is silent, so it is left
where it is rather than gated in the same breath as a fix.

**A residual this rule does not remove**: a manager comping deliberately and a
manager mistyping are the same statement. `GL046` moves who can make that
mistake; it does not stop the mistake being made.

#### Scenario: A comp that was a typo
- **WHEN** a membership sold at the wrong price has taken money
- **THEN** correcting the price SHALL be refused, and the membership SHALL be repairable only by refunding, cancelling and selling again

**Which rule answers, when both could.** A membership that has already taken
money is refused by the freeze above, not by this rule — an absolute beats a
permission, and answering the permission would imply a gym admin could do it,
which they cannot. **But a single statement touching several memberships, some
frozen and some not, from a session that is not a gym admin, is refused with
whichever of the two the first row reaches**, because PostgreSQL does not order
a statement's row triggers. The refusal and the unchanged values are guaranteed;
the SQLSTATE is not. An assertion mixing frozen and unfrozen rows under a
non-admin claim must therefore assert the refusal and the values, never the
code.

#### Scenario: A front desk re-pricing a membership
- **WHEN** a front-desk session changes a membership's price, currency, plan, discount or coupon
- **THEN** it SHALL be refused and the membership SHALL be unchanged

**Selling at a price the plan does not carry is the same decision as changing
one, so creation carries the same rule.** The first draft of this requirement
governed only a session that *changes* those columns, and both blind authors
independently measured the door that leaves: a front desk **creates** the
membership at a tenth of list and takes the ordinary fee — the same 300 days,
in one statement fewer than the exploit this requirement was written to close.
That is the third round running in which creation was the unpoliced door.

`plan_id` at creation is unrestricted: choosing which plan to sell is the front
desk's job, and the price comes with it.

**Trusted contexts are exempt**, and this is the first rule here that should be.
ADR-082's general form: a carve-out is sound exactly when the rule's subject is
something a trusted caller legitimately lacks — and this rule's subject is which
staff role you are, which a webhook, a migration and the seed have none of. The
other rules in this area are invariants about the data and take no carve-out.
A **platform** session is not a trusted context in that sense: an impersonating
token carries `app_role = gym_owner` and is allowed as one, while a bare
`super_admin` re-pricing a gym's membership out of band, with no impersonation
session and no reason recorded, is what `docs/security.md` exists to prevent.

#### Scenario: A front desk selling and taking money
- **WHEN** a front-desk session creates a membership at its plan's price and records a payment against it
- **THEN** both SHALL be allowed

#### Scenario: A front desk selling below the plan's price
- **WHEN** a front-desk session creates a membership whose price or currency differs from its plan's, or which carries a discount
- **THEN** it SHALL be refused and no membership SHALL exist

#### Scenario: A gym admin selling below the plan's price
- **WHEN** a gym admin does the same
- **THEN** it SHALL be allowed and SHALL land at the price named

#### Scenario: A gym admin correcting a price before any money arrives
- **WHEN** a gym owner or manager changes the price of a membership against which no money has arrived
- **THEN** it SHALL be allowed, and a payment SHALL be scored against the corrected price

#### Scenario: A gym admin after money has arrived
- **WHEN** a gym admin changes a term of a membership that has taken money
- **THEN** it SHALL still be refused — being a gym admin does not unfreeze what money has bought

### Requirement: Money does not extend a membership that has been retired
WHEN a payment names a membership that is `cancelled` or `expired`, THE SYSTEM
SHALL record the payment and SHALL NOT extend that membership.

`app.grant_periods()` reads a membership's price, currency, dates, count and
length — **and never its status.** Measured by a critic on the very sequence
this phase prescribes as the repair for a mis-sold membership: refund, cancel,
sell a new one, and then name the *retired* one on the payment. The money is
recorded and receipted, the cancelled row's dates move, and the member stays
refused at the gate because the gate reads status. `ends_on` went to the year
26667.

It is not reachable from the console — the membership page offers only a live
or lapsed membership to renew — but `POST /api/payments` accepts any
`membershipId`, and `GL042` only checks that the member matches. **The repair
path is exactly the moment a member has two memberships and one of them is
retired**, so this is reachable precisely when the product tells someone to do
it.

Recording the payment rather than refusing it is deliberate: the money did
change hands, the receipt is the gym's record of that, and refusing after the
fact would leave cash in a drawer with nothing to show for it. What must not
happen is a retired membership silently growing.

#### Scenario: Paying against a cancelled membership
- **WHEN** a payment names a membership whose status is `cancelled`
- **THEN** the payment SHALL be recorded and receipted, and the membership's dates and count SHALL NOT move

#### Scenario: Paying against the live one instead
- **WHEN** the same payment names the member's live membership
- **THEN** it SHALL extend that membership normally

**What is suspended is the granting, not the money — and both blind authors
found that this sentence was missing.** Money paid against a retired membership
stays on record against it. If that membership is ever made live again, the
total is what it always was and the next payment grants what all of it bought.
One author measured the shape and called it the named harm arriving late; the
other bounded it and reported the two possible answers rather than picking one.
Neither scored it, because the requirement did not say.

It says now, and the reason is arithmetic rather than taste: a member who paid
₹3,000 against a membership that was cancelled has paid ₹3,000. Detaching that
money would mean they bought nothing and cannot get it back, which is a worse
answer than the one this rule was written to prevent. **The gym is never out of
pocket** — ₹3,000 buys three periods at ₹1,000 whenever it is counted.

#### Scenario: Money paid while retired, after the membership is revived
- **WHEN** a membership that took money while retired is made live again
- **THEN** the next payment SHALL grant every period the whole total has bought

### Requirement: The dates a membership runs for are written by the rule that grants them
THE SYSTEM SHALL move `starts_on` and `ends_on` only as part of granting a
period, and SHALL refuse every other change to them.

**Change, not write** — a statement that leaves a date at the value it already
held is allowed, exactly as the requirement above settles it for
`periods_granted` ("a rule that refuses a write that cannot do harm buys nothing
and breaks ordinary column-listing updates"). The first draft of this sentence
said "write", contradicting its sibling one heading up; a blind author caught it
and read the sibling, which is the right precedence.

Two requirements above govern what a period costs and how long it is. **Both
compute a date that anyone could simply type.** Measured from an ordinary
front-desk session, with no privilege beyond recording a payment:
`update memberships set ends_on = starts_on + 3650` — allowed, ten years, no
receipt, nothing raised. A membership's dates are what the money bought, on the
same argument that makes `periods_granted` the rule's to write rather than the
desk's.

Creation sets them; after that they move when a payment moves them. Correcting a
mistake means refunding, **cancelling the membership**, and selling again.

**The cancelling is not decoration**, and the first draft of this sentence left
it out. A holdout author measured the remedy the requirement recommends and it
does not work on its own: refunding a payment that granted a period moves no
date and no count, so the wrong dates stay on the row and stay live at the gate.
A refund reverses the money, not what the money bought — which is the same fact
that makes refunded money still count toward the total, one requirement above.

#### Scenario: Typing an end date
- **WHEN** any session writes `ends_on` or `starts_on` other than by granting a period
- **THEN** it SHALL be refused and the dates SHALL be unchanged

#### Scenario: A payment moving them
- **WHEN** a payment grants a period
- **THEN** the dates SHALL move by what it bought

#### Scenario: Writing a date back unchanged
- **WHEN** a statement sets a date to the value it already holds
- **THEN** it SHALL be allowed

#### Scenario: Creating a membership
- **WHEN** a membership is created with dates
- **THEN** it SHALL be allowed

**Creation is deliberately left open, and it is a hole.** A blind author
measured it: one INSERT of an `active` membership dated `today … today + 3650`,
no payment anywhere, is allowed — ten years with no UPDATE for this rule to
refuse, `periods_granted` legitimately `0`, `duration_days` legitimately the
plan's. It is the fourth door of the same shape the count rule closed at
creation.

It is **OPEN-029**, not closed here, because the rule that would close it — a
membership is created with no span it has not been paid for — is contradicted by
`supabase/seed.sql`, which creates every demo membership carrying a full
period's span, and by fixtures across both suites. Changing that is a contract
change, and contract changes made in the same breath as a fix are what produced
two of the last three rounds. It also differs from the refused UPDATE in leaving
a whole membership row as evidence, and creating memberships is an act the front
office is entitled to perform.

**A cost this requirement accepts, stated rather than discovered — and it is
four shapes, not one.** None can any longer be repaired in place, because no
payment gives them dates and no session may type one:

  * a `pending` membership holding `starts_on` with a null `ends_on`;
  * **its mirror**, `ends_on` set with a null `starts_on` — the worst of the
    four, because that row *is* extended and *is* granted its period, so the gym
    has taken the money and issued the receipt while the member stays `pending`
    and refused at the gate;
  * a **zero-price** or complimentary membership, which the granting rule can
    never extend at any amount because there is no price to divide by;
  * a **currency-mismatched** membership, for the same reason.

All four are OPEN-026's family and belong with it. Nothing in the product
creates any of them, and the honest repair is a product flow rather than a desk
typing into the money path — which is exactly what this requirement exists to
stop. Both blind authors asserted the refusal knowingly and said so in their
assertion text; the cost is chosen, not overlooked.

**And a fifth shape that is not this rule's**: a gym whose `timezone` is a
string PostgreSQL does not recognise. `organizations.timezone` is `not null
default 'Asia/Kolkata'`, so "a gym with no timezone" is unreachable, but a
mistyped one aborts a payment with a raw, unmapped `22023` naming a column the
desk cannot see. That is a defect in error mapping and belongs to whoever owns
the organisation settings screen.

### Requirement: A payment does not arrive already refunded
WHEN a payment is recorded, THE SYSTEM SHALL refuse it if it names a status that
presupposes an earlier one — `refunded` or `reversed`.

Both statuses count toward the total a period is scored against, neither extends
anything at the time, and neither takes a receipt number: a payment written
straight to `refunded` puts money on the books that no receipt names and that
nothing has granted, waiting for any later payment to cash it in. Measured — a
₹3,000 `refunded` payment inserted directly, then **one paisa**, granted three
periods. A payment is recorded and then refunded; it does not arrive that way.

#### Scenario: Recording a payment that is already refunded
- **WHEN** a session inserts a payment whose status is `refunded` or `reversed`
- **THEN** it SHALL be refused

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
