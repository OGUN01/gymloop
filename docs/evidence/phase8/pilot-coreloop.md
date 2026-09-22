# PILOT-002 / PILOT-003 preparation check — 2026-09-22

## Scope and method

This was a read-only preparation review. It did not create a gym, authenticate
another user, submit a form, call a mutation endpoint, inspect the holdout
suite, or change the deployed application. It also did not use a personal
browser session as a product-test fixture.

## Established deployed-app evidence

`docs/evidence/phase8/ledger.md` records these already-executed results against
`https://gymloop-phi.vercel.app`:

| Pilot requirement | Exact existing evidence | What it proves | What remains open |
|---|---|---|---|
| PILOT-002 | 2026-09-21 two-owner smoke: reciprocal foreign-member detail 404s, a foreign payment receipt 404, tenant-scoped member search, separate own-gym visit totals, and Iron front-desk to QA-member `POST /api/check-in` refusal with zero matching attendance rows. The QA-owner-to-Iron rollback-only RLS probe and the reverse live API refusal are also recorded. | Bounded deployed read isolation, selected direct foreign-read refusals, and check-in refusal in both directions with the recorded no-side-effect postflights. | It is not one checked-in two-owner browser run and does not cover every PILOT-002 surface/mutation. The ledger truth remains **Partial**. |
| PILOT-003 A | Read-only production role/route/axe checks, plus prior synthetic manual-payment and receipt/renewal evidence in the ledger. | Individual routes and manual-only payment boundary are supported; no Razorpay branch is enabled (PAY-012). | No independently authenticated, deployed A journey joining check-in to verified renewal in browser automation. |
| PILOT-003 B | The ledger's synthetic recovery path records front-desk follow-up, return check-in, closed case, and owner-metrics observation. | One durable backend/API recovery path, explicitly labelled synthetic and not real outreach. | No checked-in deployed browser journey covering the whole contact/return flow. |
| PILOT-003 C | Existing add-on manual-payment/receipt/fulfilment evidence is bounded to prior synthetic journeys. | The manual-only add-on branch has prior evidence. | No independently authenticated deployed browser path from purchase through visible usage. |
| PILOT-003 D | The ledger's assisted-check-in-to-member-read path records staff attribution and member visibility. | One API/write-to-member-read handoff. | No browser confirmation/actor-audit journey, and no final Android exact-artifact acceptance. |

## Authentication and fixture constraint

The checked-in Playwright suite (`tests/e2e/phase8-accessibility.spec.ts`) can
authenticate only the five password-backed Iron Box demo identities named in
`docs/demo-accounts.md`. Its assertions are read-only role landing, forbidden
route and accessibility checks; it has no second-gym actor.

The synthetic QA gym's sole active owner is Google-authenticated. The ledger
records that this owner has no controlled password or pre-authenticated
Playwright storage-state fixture. The existing evidence therefore deliberately
uses a separate Google in-app browser session and an Iron Box Playwright
context; that is not a repeatable checked-in two-owner acceptance test.

Adding a browser A–D suite required a controlled second-gym credential and a
safe fixture lifecycle. ADR-147 and PILOT-007 subsequently froze a distinct
synthetic QA owner and retained-history contract; those decisions are now made,
but the fixture and the run have not been created. Browser
attendance, follow-up, payment and add-on actions create immutable audit and/or
financial history and cannot be wrapped in the database rollback used by
PILOT-001/PILOT-006. Deleting them to clean a test conflicts with INT-001 and
INT-003.

## Current-session result

The preparation agent did not use a personal Edge session as a product-test
fixture. The orchestrator separately inspected the already-open Gymloop
in-app-browser QA-owner session read-only: the dashboard loaded and the QA
Members page showed one synthetic member. No new authentication session or
business mutation was created. This is not a second independent owner or an
A–D journey.

## Verdict and next safe action

PILOT-002 and PILOT-003 remain open. ADR-147 resolves the retained-history
policy, and independent visible/holdout authors are preparing tests from the
frozen contract. The next operational steps are to create and verify the
separate QA owner through the authorized Auth/staff/link flow, run one guarded
two-owner A–D acceptance, and deactivate that test identity. The existing
read-only role/route scan remains supporting evidence only; it cannot promote
either pilot requirement by itself.
