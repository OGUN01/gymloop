# Membership net price

## Purpose

A membership sold for INR 12000 with INR 1200 off is paid in full by INR 10800.
Use that agreed price consistently without repricing paid history.

## ADDED Requirements

### Requirement: A period costs the listed price minus its discount
THE SYSTEM SHALL score each membership period against integer
`price_paise - discount_paise`, using the membership's recorded sold terms,
never its plan's current price. Positive net prices use integer division of
eligible received money by net price, minus already granted periods. Eligible
money remains paid/refunded/reversed receipts in the membership's currency.
Existing first-grant dates, renewals, retired statuses, partial payments,
half-dated boundaries and exactly-once accounting continue unchanged.

#### Scenario: The agreed annual price
- **WHEN** an eligible membership priced 1200000 paise with a 120000 paise discount receives 1080000 paise in its currency
- **THEN** it SHALL have bought exactly one period

#### Scenario: Partial and multiple payments
- **WHEN** eligible receipts cross one or more whole multiples of the positive net price
- **THEN** exactly those whole periods SHALL be granted, and fractional periods SHALL not be rounded up

#### Scenario: Refund history and payment replay
- **WHEN** money is refunded, reversed, or a paid event is replayed
- **THEN** previously granted periods SHALL not be bought again by the same money

#### Scenario: Foreign currency or retired membership
- **WHEN** a receipt has a different currency, or its membership is cancelled or expired
- **THEN** it SHALL grant no new time under the existing payment-record rules

### Requirement: A discount cannot make the agreed price negative or change paid terms
THE SYSTEM SHALL enforce `0 <= discount_paise <= price_paise` with a database
CHECK (`23514`). WHEN any paid/refunded/reversed money exists against a
membership in any currency THE SYSTEM SHALL refuse a changed discount with
`GL043`, for every writer, including trusted writers. Existing project-owned
membership refusal order and gym-admin pricing permissions remain in force.
CHECK/RLS/privilege precedence is not part of the project-owned rule order.

#### Scenario: Discount outside its bounds
- **WHEN** a write supplies a negative discount or one greater than its price
- **THEN** it SHALL be refused with `23514` and leave the row unchanged

#### Scenario: A discount after part payment
- **WHEN** any received money exists and an otherwise valid discount changes
- **THEN** the write SHALL be refused with `GL043`, even before a whole period is granted

#### Scenario: A plan correction makes a preserved discount invalid
- **WHEN** an authorized unpaid membership changes to a plan whose resulting price is below its discount
- **THEN** the write SHALL be refused unless the same write supplies a valid discount; no silent discount reduction SHALL occur

#### Scenario: Coupon identifier
- **WHEN** a gym admin changes only a coupon identifier
- **THEN** the existing coupon edit policy SHALL apply; the identifier SHALL not calculate or alter the agreed amount

### Requirement: Complimentary memberships have no collection fee
WHERE net price is zero THE SYSTEM SHALL display zero fee and SHALL not divide
or automatically grant payment-driven periods. Existing complimentary
membership lifecycle and creation behavior remain unchanged.

#### Scenario: Fully discounted membership
- **WHEN** price and discount are equal
- **THEN** the displayed fee SHALL be zero and recording money SHALL not raise a division error or grant periods

### Requirement: Product calculations use the same agreed price
THE SYSTEM SHALL display the net period price in the membership detail, payment
default and full-period explanation. Plan catalogue choices remain list prices.
The payment default SHALL describe one full period, not an outstanding balance.
The platform-free shared function `membershipNetPrice(pricePaise: number,
discountPaise: number): number` SHALL return their exact integer difference for
safe nonnegative integer inputs with discount at most price, and SHALL throw
`RangeError` for invalid, fractional, non-finite or unsafe inputs.

#### Scenario: Discounted membership on screen
- **WHEN** staff opens the 12000-less-1200 membership
- **THEN** its agreed period price and payment default SHALL both show 10800 rupees

#### Scenario: Exact calculation boundary
- **WHEN** shared calculation receives invalid or unsafe input
- **THEN** it SHALL fail explicitly rather than round, clamp or return an inexact fee

### Requirement: Reconcile the existing paid year without granting another year
THE SYSTEM SHALL reconcile IronBox membership
`00000006-0000-4000-8000-000000000004` to one granted historical period while
preserving its 2025-09-12 through 2026-09-12 dates, active status and receipt
history. The correction SHALL guard the inspected tenant, identity, currency,
price 1200000, discount 120000, duration 365 and eligible total 1080000 before
changing an existing zero count. Missing demo data requires no insert; already
reconciled data requires no change. Unexpected existing discounted history
SHALL stop the migration for reconciliation, not be silently repriced.

#### Scenario: The already-paid demo year
- **WHEN** the inspected historical row is reconciled
- **THEN** periods_granted SHALL become one and its dates and receipts SHALL remain unchanged

#### Scenario: Seed replay
- **WHEN** the demo seed is run after reconciliation, including a second run
- **THEN** the same historical period SHALL remain counted once
