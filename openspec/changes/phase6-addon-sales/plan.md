# Phase 6 add-on sales and fulfilment

Authorized under ADR-111 after the identity/navigation archive `59617e8`. The
normative implementation contract is `docs/planning/phase6-addon-contract.md`,
including the cross-cluster seam and bounded member-return read in ADR-116. The
contract is fixed before authors are dispatched; changes require stopping and
reconciling every author first.

Comparable references reviewed 2026-09-10: Square item editing
https://squareup.com/help/us/en/article/8335-create-and-edit-items, Square
appointment scheduling https://squareup.com/help/us/en/article/5349-schedule-and-accept-appointments,
Stripe mobile payment details https://docs.stripe.com/dashboard/mobile, and
Stripe refund states https://docs.stripe.com/refunds. Gymloop's frozen money,
manual-return, role and tenant contracts decide behavior where references differ.

Reuse registered catalogue/payment/refund/audit primitives, exact money
formatting, identity/API envelopes, member search, account frame, preview guard
and form controls. Add only the schema, RPCs, projections, routes and components
the contract proves missing. Do not hand-edit generated database types.

Money, RLS and the member security-definer read are silent-failure territory.
Independent visible and holdout authors work implementation-blind, never read
each other's suites, and commit red before source. The implementer never reads
holdout files. Database migrations apply only through CI; local candidate SQL
replays migration plus rollback-wrapped suites against the linked project only
while its DB workflow is idle.

- [x] Detailed contract, shared seam, member-return boundary and Astra working-screen brief fixed.
- [x] Independent visible and holdout tests committed red.
- [x] Catalogue, sale, fulfilment, return read and working screens implemented.
- [x] Targeted and full local gates pass.
- [x] Fresh Astra money/security and UI critics return GO.
- [ ] CI applies migration; generated types, pgTAP, seed and all workflows pass.
- [ ] Real product/diet/PT sale, fulfilment, receipt and return journey passes with exact cleanup.
- [ ] Current specifications, registry, evidence and roadmap synchronized; archive.
