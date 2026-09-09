## Purpose

A gym takes money at the desk — cash, UPI, card, bank transfer — and that is **the path most Indian gyms will actually use**, not a degraded mode (owner decision, 2026-09-08). PAY-011 always required it to work without a gateway; what is settled now is that it is first class, and built first, because a phase that cannot start until a secret arrives is a phase that does not start.

**The asymmetry that makes this separate code, stated rather than blurred.** An online payment has a provider that is the only source of truth for its state (PAY-006): no client report can mark it paid. A manual payment has no provider to verify against at all. Its integrity comes from somewhere else — **a named staff member, a receipt number the gym can be audited against, and an audit row** — and pretending the two paths are one thing would mean either trusting a client for online money or inventing a verification that manual money cannot have.

## Requirements

### Requirement: Money is integer paise, and nothing derives a fraction of one
THE SYSTEM SHALL store every amount as integer paise (MNY-001), and SHALL NOT compute an amount by any operation that can produce a fraction.

A manual payment's amount is **entered, not calculated**: it is what the person handed over. Nothing in this path multiplies, applies a percentage, or divides — so the rounding rule MNY-003 asks for has nothing to decide here, and that is a property to preserve rather than a gap to fill. The first arithmetic on money in this product is GST, and it gets its own rule where it lives.

#### Scenario: An amount that is not a whole number of paise
- **WHEN** a payment is recorded with a fractional amount
- **THEN** it SHALL be refused rather than rounded — rounding somebody's money silently is worse than asking them to type it again

#### Scenario: A zero or negative amount
- **WHEN** a payment is recorded for zero or less
- **THEN** it SHALL be refused

### Requirement: A recorded payment names the staff member who took it
THE SYSTEM SHALL record `payments.recorded_by_staff_id` as the acting staff member, and SHALL refuse a value naming anybody else.

**This is the fourth appearance of one rule** — after `attendance.assisted_by_staff_id` (`GL016`), `membership_pauses.requested_by_staff_id` (`GL026`) and `follow_ups.staff_id` (`GL030`) — and here it is load-bearing in a way it was not before: with no provider to verify against, **attribution is the integrity**. A cash payment nobody is recorded as having taken is a cash payment nobody can be asked about.

The null actor is named as its own clause, not left to a comparison, because `null is distinct from null` is false (ADR-071).

#### Scenario: Recording a payment
- **WHEN** a staff member records a cash payment
- **THEN** it SHALL be attributed to them

#### Scenario: Naming a colleague
- **WHEN** a staff member records a payment naming a different staff member
- **THEN** the write SHALL be refused

#### Scenario: A session with no staff identity
- **WHEN** a session inside row security carrying no `staff_id` claim records a payment
- **THEN** the write SHALL be refused

### Requirement: A manual payment cannot claim a provider
THE SYSTEM SHALL refuse a payment whose `method` is one of the desk methods but which carries `provider`, `provider_order_id` or `provider_payment_id`, and SHALL refuse a `razorpay` payment recorded through the manual path.

The two paths are separate code because their integrity comes from different places. A row that is manual in its method and online in its identifiers is a row that claims a verification nobody performed — and it is the shape that would let a forged provider id launder a cash payment into an apparently-verified one.

#### Scenario: A cash payment carrying a provider payment id
- **WHEN** a payment with method `cash` is recorded with a `provider_payment_id`
- **THEN** it SHALL be refused

#### Scenario: An online method through the desk
- **WHEN** a payment with method `razorpay` is recorded by the manual path
- **THEN** it SHALL be refused — online state is the provider's to report (PAY-006)

### Requirement: A receipt number is unique per gym and never reused
THE SYSTEM SHALL allocate `receipt_number` from the gym's own `document_counters`, unique within the gym, and SHALL NOT reuse a number after a payment is voided or refunded.

A receipt is what a gym is audited against. Two payments sharing a number, or a number reappearing after a refund, is the failure that makes a book unauditable — and it is invisible until somebody is audited.

**The counter is not a read-then-write.** Two staff taking money at the same moment both read the same `next_number` and both write it; the allocation must be atomic in the same sense `app.enforce_check_in()` is, and for the same reason.

#### Scenario: Two payments in the same gym
- **WHEN** two payments are recorded
- **THEN** their receipt numbers SHALL differ

#### Scenario: Two payments at the same instant
- **WHEN** two staff record a payment concurrently
- **THEN** both SHALL succeed and their receipt numbers SHALL differ

#### Scenario: Two gyms
- **WHEN** two gyms each record their first payment
- **THEN** each SHALL get its own gym's number, and one gym's sequence SHALL NOT be advanced by another's activity

#### Scenario: A refunded payment's number
- **WHEN** a payment is refunded
- **THEN** its receipt number SHALL remain on the original row and SHALL NOT be issued again

### Requirement: A payment extends the membership on the same rules an online one would
WHEN a payment is recorded as paid against a membership, THE SYSTEM SHALL extend that membership exactly as a verified online payment would (PAY-008, PAY-011).

> **Narrowed by `payment-record/spec.md`, "Money does not extend a membership
> that has been retired".** This sentence is unconditional and a `cancelled` or
> `expired` membership is the exception: the payment is still recorded,
> receipted, attributed, refundable and bounded by `GL036`, and the membership
> does not move.
> The exception lives in another file, which is exactly why it is repeated here —
> a blind author reading only this one would stage a cancelled membership and get
> a red assertion against correct code.

The renewal pipeline must not be able to tell the two apart. If it can, a gym on the manual path gets a second-class product — which is the thing the owner's decision rules out.

#### Scenario: A paid manual payment
- **WHEN** a cash payment is recorded against an active membership
- **THEN** that membership's end date SHALL move by the length the membership was sold at (`memberships.duration_days`, ADR-090 — the plan's duration at the moment of sale, which stops diverging from the plan the day anyone re-lengthens it)

#### Scenario: A payment against no membership
- **WHEN** a payment is recorded with no membership
- **THEN** it SHALL be recorded and nothing SHALL be extended — a gym may take money for something else

### Requirement: A refund is a new row, never a mutation
THE SYSTEM SHALL record a refund as a row in `refunds` referencing the payment, and SHALL NOT alter the original payment's amount (PAY-010, INT-001).

#### Scenario: Refunding a payment
- **WHEN** a payment is refunded
- **THEN** a `refunds` row SHALL exist and the payment's `amount_paise` SHALL be unchanged

#### Scenario: Refunding more than was paid
- **WHEN** refunds against one payment would exceed its amount
- **THEN** the write SHALL be refused

### Requirement: Recording the same payment twice records one payment
WHEN a payment carries an `idempotency_key`, THE SYSTEM SHALL record it once however many times it arrives.

A front desk on a bad connection presses the button twice. The member is charged once in the world and must appear charged once in the book — and the guard belongs to the table, because `payments` grants `insert` to `authenticated` and a rule in a Route Handler has a supported way round it.

#### Scenario: The same key twice
- **WHEN** two payments are recorded carrying the same `idempotency_key`
- **THEN** exactly one row SHALL exist

#### Scenario: The same key in two gyms
- **WHEN** two gyms record a payment with the same key
- **THEN** both SHALL exist — a key is unique within a gym, not across the product
