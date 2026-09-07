## Purpose

The paid side of a gym: plans and coupons, a member's membership periods and approved freezes, every attempt to collect money, refunds, provider webhook deliveries, GST invoices and their per-gym numbering, and the per-gym Razorpay connection including the Autopay mandate tables Phase 2 will need.

## Requirements

### Requirement: Money is stored as integer paise with an explicit currency
THE SYSTEM SHALL store every money amount as an integer number of paise in a `bigint` column, never as a floating-point or decimal type, and SHALL store an explicit currency code alongside it (MNY-001, MNY-002).

#### Scenario: No approximate money column exists
- **WHEN** the schema is inspected for columns whose name ends in `_paise`
- **THEN** every one SHALL be of type `bigint`

#### Scenario: Every table carrying money carries a currency
- **WHEN** the schema is inspected for tables that have a `*_paise` column
- **THEN** every one SHALL also have a `currency` column

#### Scenario: A currency code that is not a three-letter code
- **WHEN** a row is written with a currency of `Rupees`
- **THEN** the write SHALL be rejected

#### Scenario: A negative amount to be collected
- **WHEN** a payment is written with an amount of zero or less
- **THEN** the write SHALL be rejected

### Requirement: A membership without an expiry date cannot be stored once it is live
DQA-001 SHALL hold structurally: only a membership still in `pending` may lack a start and end date. Any other status SHALL require both.

#### Scenario: An active membership with no expiry
- **WHEN** a membership is written as `active` with no `ends_on`
- **THEN** the write SHALL be rejected

#### Scenario: A pending membership with no dates
- **WHEN** a membership is written as `pending` with neither date set
- **THEN** the write SHALL succeed

#### Scenario: An expiry before the start
- **WHEN** a membership is written whose `ends_on` precedes its `starts_on`
- **THEN** the write SHALL be rejected

### Requirement: A member has at most one live membership
THE SYSTEM SHALL permit a member at most one membership in `active` or `frozen` status at a time. A renewal SHALL be a new row linked to the one it renews, never an edit of the previous period.

#### Scenario: A second active membership
- **WHEN** a second membership for the same member is written as `active`
- **THEN** the write SHALL be rejected

#### Scenario: A renewal alongside an expired period
- **WHEN** a new membership is written as `active` for a member whose previous membership is `expired`
- **THEN** the write SHALL succeed

### Requirement: A paid payment always carries a reference
DQA-002 SHALL hold structurally: a payment in `paid` status SHALL carry either a provider payment reference or a receipt number, so a paid row without a reference cannot exist rather than merely being flagged.

#### Scenario: Paid with no reference at all
- **WHEN** a payment is written as `paid` with neither a provider payment id nor a receipt number
- **THEN** the write SHALL be rejected

#### Scenario: An offline payment marked paid with a receipt
- **WHEN** a cash payment is written as `paid` with a receipt number
- **THEN** the write SHALL succeed

### Requirement: An offline payment carries staff attribution
PAY-011 SHALL hold structurally: any payment whose method is not the gateway SHALL name the staff member who recorded it, so a gym with no gateway connected still produces an attributable record.

#### Scenario: Cash recorded by nobody
- **WHEN** a cash payment is written with no recording staff member
- **THEN** the write SHALL be rejected

#### Scenario: A gateway payment with no recording staff member
- **WHEN** a gateway payment is written with no recording staff member
- **THEN** the write SHALL succeed

### Requirement: Receipt and invoice numbers are unique per gym
THE SYSTEM SHALL reject a duplicate receipt number within one organisation, a duplicate invoice number within one organisation, and a duplicate provider payment reference within one organisation, and SHALL allow the same value to exist at a different organisation.

#### Scenario: A repeated receipt number at one gym
- **WHEN** a second payment at the same organisation is written with an existing receipt number
- **THEN** the write SHALL be rejected

#### Scenario: The same receipt number at another gym
- **WHEN** a payment at a different organisation is written with that same receipt number
- **THEN** the write SHALL succeed

#### Scenario: Two payments with no receipt number
- **WHEN** two payments at the same organisation are written with no receipt number
- **THEN** both writes SHALL succeed

### Requirement: A duplicate webhook delivery cannot be recorded twice
PAY-009's idempotency SHALL rest on a uniqueness constraint: THE SYSTEM SHALL reject a second webhook event row carrying the same provider event id for the same organisation.

#### Scenario: The same event delivered twice
- **WHEN** a webhook event is written a second time with the same provider event id and organisation
- **THEN** the second write SHALL be rejected

#### Scenario: The same event id at another gym
- **WHEN** the same provider event id is written for a different organisation
- **THEN** the write SHALL succeed

### Requirement: A refund is a separate record, never a mutation of the payment
PAY-010 SHALL hold structurally: refunds and reversals SHALL be stored as their own rows referencing the original payment, each carrying a stated reason.

#### Scenario: A refund with no reason
- **WHEN** a refund is written with an empty reason
- **THEN** the write SHALL be rejected

#### Scenario: A refund of a non-existent payment
- **WHEN** a refund is written referencing a payment that does not exist
- **THEN** the write SHALL be rejected

### Requirement: Financial history is never hard-deleted
INT-001 SHALL hold structurally for plans, memberships, payments, refunds, invoices and webhook events: a signed-in caller SHALL have no privilege to delete a row from any of them.

#### Scenario: Deleting a payment
- **WHEN** a caller with the `authenticated` role deletes a payment in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

#### Scenario: Cancelling a membership instead
- **WHEN** the same caller sets that member's membership status to `cancelled`
- **THEN** the update SHALL succeed and the row SHALL remain

### Requirement: Payment secrets are never stored as plaintext columns
THE SYSTEM SHALL store a gym's Razorpay key secret and webhook secret as references to Supabase Vault entries rather than as their values, and SHALL provide no column anywhere for a card number or UPI credential (PAY-005).

#### Scenario: No credential column exists
- **WHEN** the schema is inspected for a column that would hold a card number or a raw UPI credential
- **THEN** the result SHALL be empty

### Requirement: Autopay mandate tables exist unused
THE SYSTEM SHALL provide the Razorpay subscription mandate tables Phase 2's UPI Autopay needs, with a mandate status vocabulary mirroring the provider's, so enabling Autopay requires no migration. Phase 1 SHALL write no mandate logic.

#### Scenario: A mandate is unique per provider subscription
- **WHEN** a second mandate is written with an existing provider subscription id for the same organisation
- **THEN** the write SHALL be rejected

#### Scenario: A mandate with no ceiling
- **WHEN** a mandate is written with a maximum chargeable amount of zero
- **THEN** the write SHALL be rejected

### Requirement: A coupon carries exactly one kind of discount
THE SYSTEM SHALL require a coupon to define either a percentage or a flat paise amount, never both and never neither, and SHALL reject a duplicate code within one organisation.

#### Scenario: A coupon with both discount kinds
- **WHEN** a coupon is written with both a percentage and a flat amount
- **THEN** the write SHALL be rejected

#### Scenario: A coupon with neither
- **WHEN** a coupon is written with neither a percentage nor a flat amount
- **THEN** the write SHALL be rejected

### Requirement: Invoice numbering resets per gym per financial year
THE SYSTEM SHALL hold the next document number per organisation, per document kind, per financial year, so a gym's invoice and receipt series restart on its own financial-year boundary.

#### Scenario: A malformed financial year
- **WHEN** an invoice is written with a financial year of `2026`
- **THEN** the write SHALL be rejected

#### Scenario: One counter per gym, kind and year
- **WHEN** a second counter row is written for the same organisation, kind and financial year
- **THEN** the write SHALL be rejected
