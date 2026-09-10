# Phase 5 remaining contracts

Status: The net-price section was completed and archived on 2026-09-10. The
refund retry and refusal-order sections remain ACCEPTED under the owner's
delegated decision authority (ADR-111); their implementation and verification
remain outstanding.

## Membership net price — completed

- **NET-001** implemented `price_paise - discount_paise` as the amount that buys
  one membership period. ₹12,000 less ₹1,200 is fully paid at ₹10,800.
- **NET-002** freezes a membership's discount with `GL043` once eligible money
  arrives, alongside its other financial terms, and refuses a discount below zero
  or above price.
- **NET-003** calculates whole paid periods by integer division of eligible
  receipts by a positive net price. First-grant, renewal, retired-status,
  currency and partial-payment rules remain in force.
- **NET-004** avoids division and automatic payment-driven grants at a zero net
  price, retaining complimentary-membership behavior and displaying no fee.
- **NET-005** applies the net-price definition to product displays and payment
  forms. Reminder calculations and owner metrics will consume the same definition
  when their Phase 6 surfaces are implemented. The documented historical repair
  preserved payment and receipt history.

Implemented resolution:

- The database CHECK for `0 <= discount_paise <= price_paise` answers PostgreSQL
  `23514`; it is outside the project-owned refusal ordering below. A plan change
  that leaves the preserved discount above the new price is refused unless the
  same authorized write also supplies a valid discount. No discount is silently
  reduced or removed.
- The payment form continues to offer one full period by default, now at the net
  amount, clearly labelled as a period price. It does not label that default as
  an outstanding balance. Future renewal balances use the Phase 6 residual rule.
- `coupon_id` keeps its existing gym-admin edit rule; its identifier is not a
  second arithmetic input. Discount, price, currency and sold-plan freezes
  remain the controls on the amount already paid for.

### Historical reconciliation completed from live inspection

A read-only CLI query before the correction on 2026-09-10 found exactly one membership with a nonzero
discount: IronBox membership `00000006-0000-4000-8000-000000000004` has
`price_paise=1200000`, `discount_paise=120000`, `eligible_total=1080000` INR,
`duration_days=365`, dates `2025-09-12` through `2026-09-12`, active status, and
`periods_granted=0`. Its existing dated annual period was already paid in full
under the approved net-price decision.

The guarded migration recorded `periods_granted=1` and preserved those original
dates, status and receipts. It awarded no second year from the migration date,
asserted the inspected facts before changing that exact row, and updated seed
data so a later seed cannot reintroduce the zero count.

### Implementation inventory

The price calculation was centralized in `app.grant_periods()` before this
change; the net-price migration changed only its price input. The current
`app.enforce_membership_terms_frozen()` definition remains in
`20260913150000_the_rule_that_answers_is_the_one_about_whose_membership_it_is.sql`.
Its `GL043` clause includes discounts without reordering unrelated rules.

The membership detail page selects `discount_paise` and uses the agreed amount
in its sold-price display, payment default and full-period explanation. Plan
catalogue choices retain list prices. The platform-free `membershipNetPrice`
helper now provides the shared calculation. Current reminders and owner metrics
are not implemented, so their consumer changes belong to Phase 6.

The independent visible author reviewed assertion 360 in
`supabase/tests/22_payment_record.sql`: its simultaneous `price=1, discount=999`
control remains within the valid discount bounds, while the database CHECK
answers `23514` for invalid bounds.

## Refund retries — proposed resolution of OPEN-031

- **REF-001** WHEN a manager submits a refund form THE SYSTEM SHALL attach a
  stable request key. Repeating that request, including concurrent submissions,
  SHALL create one refund and one corresponding financial audit event.
- **REF-002** WHEN a request key is reused with the same payment, amount,
  currency, kind and reason in the same gym THE SYSTEM SHALL return the existing
  recorded result. WHEN any of those facts differ THE SYSTEM SHALL refuse with
  an explicit idempotency-conflict error and leave the original unchanged.
- **REF-003** THE SYSTEM SHALL scope refund keys to the gym, require a key from
  the product refund form, and preserve old refunds without a key. A new form
  SHALL get a new key so a second intentional partial refund remains possible.
- **REF-004** THE SYSTEM SHALL enforce keyed uniqueness at the database, and
  SHALL freeze a recorded refund's key, payment, amount, currency, kind and id.
  Refunds remain owner/manager work; the existing ceiling and completed-status
  rule remain in force. Adding key-based replay must not let another tenant or
  unauthorized role discover a recorded refund.
- **REF-005** WHEN recording fails for a reason other than an equivalent keyed
  replay THE SYSTEM SHALL show the actual failure, never report success merely
  because PostgreSQL raised a uniqueness error.

## Predictable money refusals — proposed resolution of OPEN-034

- **ERR-001** WHEN one payment write violates several project-owned payment
  rules THE SYSTEM SHALL apply this order: paid-record freeze `GL038`, member/
  membership identity `GL042`, legal status transition `GL039`, actor attribution
  `GL034`, manual/provider separation `GL035`.
- **ERR-002** WHEN one refund write violates several project-owned refund rules
  THE SYSTEM SHALL apply this order: immutable record or completed-status rule
  `GL041`, actor attribution `GL040`, paid-payment/total ceiling `GL036`.
  Refusing a change to an existing refund's amount or payment explicitly uses
  `GL041`, closing the previously unassigned error contract.
- **ERR-003** These orders SHALL apply only among the named project-owned rules.
  PostgreSQL privileges, RLS, foreign keys, checks and uniqueness constraints
  retain their own behavior; no ordering claim is made over those mechanisms.

## Delivery and accepted boundaries

Net-price completed its independent test authors, fresh Astra critic, local
gates, CI-only migration apply and browser evidence. Refund retry protection,
immutable refund facts, payment/refund refusal ordering and financial audit
completed together in refund-retries-and-money-audit with green final CI,
live concurrency, browser verification and exact cleanup.

The previously accepted Razorpay test-credential/signed-payload gap remains
explicit. The withdrawn universal INSERT date cap is not reinstated here;
OPEN-029's unpaid direct-creation gap and OPEN-026's malformed membership
semantics remain separately recorded. This document does not invent GST invoice
rules or change the archived Phase 5 receipt scope.
