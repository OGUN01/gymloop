# Phase 6 add-on sales and fulfilment — verified

The frozen ADD-001..009 contract (`docs/planning/phase6-addon-contract.md`, with
the ADR-116 member-return seam) delivers the whole optional-offer loop: a
catalogue with gym-stated terms, a sale that freezes those terms onto the order,
receipt-backed money, delivery for products, diet plans and PT sessions, and
exact manual returns that flip the order to refunded and cancel undelivered
service without touching delivered usage. Every screen a gym needs for it is
live: the add-on workspace, the order page with its schedule/complete/no-show
controls, the member's own add-ons page, and the receipt with its return
controls.

## Independent tests first

Visible and holdout authors worked implementation-blind and never read each
other's suites; their red commits (`284b965` through `461abcd`, led by
`bddeef8`–`cd586ef` money and chronology pins) precede the production source.
The final suite covers catalogue writes, sale acceptance and idempotency,
fulfilment boundaries per offer kind, PT chronology and trainer ownership,
receipt precision and paged refunds, return ceilings, role refusals, and
preview write guards. The database suite at the delivery revision is 63
rollback-wrapped files declaring 5413 assertions.

The implementation is isolated in `3e4ca92` (with hardening migration
`20260915100004_phase6_addon_hardening.sql`); the generated types follow in
`b0d7849`. No implementation commit touches a test file.

## Candidate checks and critics

The full local gate set passed: lint, type checking, duplication analysis,
dead-code analysis, the production build, dependency boundaries, registry lint,
escape-hatch checking, rollback checking and the TypeScript suites: 867 web
tests across 26 files and 123 shared tests, all passing. The full Cloud candidate sweep replayed the hardening
migration inside every test transaction: all 63 files, zero failures, every
declared plan complete. Fresh Astra money/security and UI critics returned GO
after their deltas; their findings are folded into the visible suite's
far-future-slot refusal (`461abcd`) and the receipt's decimal-text money.

## Real browser acceptance and cleanup

Real Supabase sessions against the deployed hook and the local Next application
proved every journey in the contract, screenshotted in this directory:

- Product: owner creates "JOURNEY Test Protein" (`phase6-addon-product-created`),
  sells to Aarav for INR 1200.00 cash, receipt `2026-27/000008`
  (`phase6-addon-product-order`, `phase6-addon-receipt`), partial return INR
  400.00 (`phase6-addon-partial-refund-confirmed`), full return INR 800.00
  flips the order to refunded (`phase6-addon-full-refund`).
- Diet plan: sells to Sneha for INR 1500.00 UPI, receipt `2026-27/000009`, the
  same request key replays without a second row, plan shared marks the order
  completed (`phase6-addon-diet-completed`).
- PT: sells the four-session package to Kavya for INR 3000.00, receipt
  `2026-27/000010` (`phase6-addon-pt-order`); a far-future session schedules,
  a no-show releases the booking without consuming usage, completion after the
  session's end consumes exactly one session (`phase6-addon-pt-completed-noshow`);
  the owner's full return INR 3000.00 flips the order active to refunded,
  cancels the remaining scheduled session, keeps the completed one's usage and
  timestamp, and freezes further delivery (`phase6-addon-pt-refunded`).
- Refusals: the trainer's catalogue is read-only, the member is bounced from
  both staff screens to `/member/add-ons`, and the front desk sees the receipt
  with INR 1500.00 available and no return form
  (`phase6-addon-refusal-trainer-catalogue`,
  `phase6-addon-refusal-member-staff-screens`,
  `phase6-addon-refusal-frontdesk-refund`).
- Support preview: a super-admin impersonation session renders every console
  page read-only with the sticky banner "Read-only preview · Iron Box Fitness —
  Vijay Nagar"; a catalogue POST returns 403 and a direct PostgREST write
  returns 403 `Support preview is read-only.`, and End preview restores the
  platform identity (`phase6-impersonation-platform`,
  `phase6-impersonation-console-banner`,
  `phase6-impersonation-addons-readonly`,
  `phase6-impersonation-order-readonly`, `phase6-impersonation-exit`). The spec
  starts a preview by a direct `impersonation_sessions` insert; a start button
  belongs to the platform slice.

Cleanup compared every created row against the live recorded manifest — three
products, three orders, four PT sessions, three payments, three refunds and
their seventeen audit rows — deleted exactly those ids (the order/session
foreign-key cycle is broken with a replication-role pointer null inside the
one cleanup transaction), then verified the baselines exactly: 3 orders,
5 products, 5 PT sessions, 34 payments, 0 refunds, 46 members, and zero
journey rows or audit rows remaining. No seeded row was touched.

## Delivery

Implementation `3e4ca92` pushed; database workflow `34508988355` applied
`20260915100004` (migrate and pgtap-rollback green; schema-drift red as
designed until regeneration). Types commit `b0d7849` then passed database
workflow `34515453967`: migrate green, all 63 files / 5413 assertions green,
schema-drift green. That run's seed dry run failed — the seed still replayed
against the pre-hardening rules — fixed in `e7f7902`, and the exact CI command
(seed and scenarios in one rolled-back transaction) now returns its clean
verdict against the live schema; CI reconfirms it on the next green database
run, because the following run `34520059628` carries the leads cluster's
intentionally red tests and skips the seed job by dependency. All other
workflows on both pushes are green.
