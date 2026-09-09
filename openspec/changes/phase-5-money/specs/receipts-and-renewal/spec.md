## Purpose

The two things a payment causes: a number the gym can be audited against, and a membership that runs longer than it did before. Both are silent when wrong — a duplicate receipt number is invisible until an auditor asks, and a membership extended twice is invisible until the member is charged again far too late.

## Requirements

### Requirement: A receipt number is allocated atomically, per gym, per financial year
THE SYSTEM SHALL allocate receipt numbers from `document_counters` keyed on `(tenant_id, kind, financial_year)`, and SHALL allocate each number to exactly one payment.

**Not a read-then-write.** Two staff taking money at the same moment both read the same `next_number` and both write it, and the result is two receipts bearing one number — which is precisely the state that makes a book unauditable. The allocation is an atomic increment returning the value it consumed, in the same sense `app.enforce_check_in()` takes its lock before it reads: **the row that hands out the number is the row that records it was handed out.**

`financial_year` is India's — 1 April to 31 March — because that is what the gym files against, and it is derived from the payment's own date rather than passed in, so a caller cannot file a March payment into the next year by asking.

#### Scenario: Two payments at the same instant
- **WHEN** two staff record a payment in the same gym concurrently
- **THEN** both SHALL succeed and their receipt numbers SHALL differ

#### Scenario: A new financial year
- **WHEN** the first payment of a new financial year is recorded
- **THEN** its number SHALL restart the sequence for that year, and the previous year's counter SHALL be untouched

#### Scenario: Two gyms
- **WHEN** two gyms record payments
- **THEN** neither gym's sequence SHALL be advanced by the other's activity

#### Scenario: A failed payment
- **WHEN** a payment is recorded and then fails
- **THEN** its number SHALL NOT be reissued to a later payment — a gap in a receipt book is explainable, a reused number is not

### Requirement: A payment extends the membership it names, once
WHEN a payment against a membership is `paid`, THE SYSTEM SHALL extend that membership by the plan's duration **for each whole multiple of the membership's own price that the money against it has reached**, and SHALL do so exactly once however many times the payment is recorded, retried or replayed.

> **Narrowed by `payment-record/spec.md`, "Money does not extend a membership
> that has been retired".** This sentence is unconditional and a `cancelled` or
> `expired` membership is the exception: the payment is still recorded,
> receipted, attributed, refundable and bounded by `GL036`, and the membership
> does not move.
> Note this is the second narrowing of the same sentence: the note a few lines
> below records the first, when the cumulative rule superseded "extend by the
> plan's duration" full stop.


> **Superseded in detail by `payment-record/spec.md`, "A period is granted when it has been paid for".** As first written this requirement said a paid payment extends by the plan's duration full stop, and a critic pointed out that it now contradicts the cumulative rule for every part payment — two documents in one change, and the next blind test author reads whichever they open first. The cumulative rule is the one to build against; this requirement's scenarios below remain true for a payment of the full price, which is the ordinary case.

**The extension belongs to the table, not to the handler**, for the reason every Phase 3 and 4 rule does: `memberships` grants `update` to `authenticated`, so a rule living in a Route Handler has a supported way round it. And it must be idempotent in the same sense the check-in guard is — a duplicate that extends a membership twice gives a member a free month and is discovered, if ever, by an owner reconciling revenue against expiry dates.

#### Scenario: A paid membership payment
- **WHEN** a payment against an active membership is recorded as paid
- **THEN** that membership's `ends_on` SHALL move forward by the plan's duration

#### Scenario: The same payment recorded twice
- **WHEN** the same payment arrives twice carrying one `idempotency_key`
- **THEN** the membership SHALL be extended once

#### Scenario: A payment that is not paid
- **WHEN** a payment is recorded in any state other than paid
- **THEN** nothing SHALL be extended — an intention to pay is not a payment (PAY-008)

#### Scenario: A refunded payment
- **WHEN** a payment that extended a membership is refunded
- **THEN** the extension SHALL NOT be silently reversed; the refund is recorded and what happens to the membership is a decision a human makes, because a member who paid, attended, and was refunded has not un-attended

### Requirement: Extending is measured from the later of today and the current end
THE SYSTEM SHALL extend from `greatest(ends_on, today)` in the gym's own timezone, never from `now()` alone and never from `ends_on` alone.

A member renewing three days early must not lose three days; a member renewing three weeks late must not receive three weeks they did not pay for. Both are wrong in a direction somebody notices, and only one of them complains.

The gym's own day, never `current_date`: every Supabase connection is UTC, and this is the same defect ADR-039 names and Phase 4 shipped anyway (ADR-078's round).

#### Scenario: Renewing early
- **WHEN** a member renews three days before expiry
- **THEN** the new end date SHALL be three days further out than a same-day renewal would give

#### Scenario: Renewing late
- **WHEN** a member renews three weeks after expiry
- **THEN** the new period SHALL start from today, not from the lapsed end date

### Requirement: A receipt is legible to the person who paid
THE SYSTEM SHALL produce, for any recorded payment, a page showing the gym, the member, the amount in rupees, the method, the date, the receipt number and the staff member who took it.

Amount is rendered from integer paise at the edge and nowhere else: **no intermediate representation of money is a float, and the division by 100 happens once, in the view layer, on its way to a human** (MNY-001).

#### Scenario: A recorded payment
- **WHEN** staff open a payment's receipt
- **THEN** it SHALL show all seven facts, and the amount SHALL match the stored paise exactly

#### Scenario: Another gym's payment
- **WHEN** a receipt for a payment in another gym is requested
- **THEN** nothing SHALL be shown — the policy is what refuses, not a check in the page
