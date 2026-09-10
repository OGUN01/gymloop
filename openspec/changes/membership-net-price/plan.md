# Membership net price

Owner authorization: on 2026-09-10 the owner chose price minus discount, then
delegated the remaining product decisions and requested completion through
Phase 6. ADR-111 records that delegation. The fixed contract is
`specs/membership-net-price/spec.md`.

The backend quality bar is exact integer arithmetic, tenant isolation and
immutable paid terms (`docs/architecture.md`). The payment surface follows the
existing receipt/desk flow; its comparable reference is Stripe Dashboard's
clear separation of price and money received. Phase 7 owns visual redesign.

Scope: net-price grants, discount bounds/freeze, displayed period price, one
documented historical reconciliation, and matching seed data. Reuse existing
money formatting. Add a platform-free `membershipNetPrice(pricePaise,
discountPaise)` helper because conversions do not calculate an agreed price;
Phase 6 metrics/reminders consume the same definition.

## Verification

- [ ] Commit fixed contract and authority before independent test authors.
- [ ] Visible and holdout tests independently written and committed red.
- [ ] Implement without changing tests; verify both suites and seed replay.
- [ ] Fresh critic GO and required local gates.
- [ ] Push on main; CI applies migration, all CI gates pass.
- [ ] Browser verifies discounted period price; reconcile historical row and verify seed consistency.
- [ ] Sync current specs, registry and evidence; archive.
