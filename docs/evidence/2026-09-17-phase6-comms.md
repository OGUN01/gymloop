# Phase 6 communications and wallet — verified

The frozen COM-001–009, PAY-001–003, INT-002/003, DPD-002–004 and STK-004
contract now ships the consent, notification, renewal-reminder and messaging
wallet boundary together with the staff and member messaging screens.

## Independent tests and review

The visible database, shared, route and screen suites and the independent
holdout suite were authored before implementation. Contract-only fixture
repairs were committed separately with `spec:` and never combined with source.
The implementer did not inspect `supabase/tests-holdout/h29_comms_holdout.sql`.
Focused communications checks pass 225 assertions; the affected web/shared
typechecks pass; the complete local `pnpm run gates` passed lint, typecheck,
duplication, unused-code, web/shared tests, registry, renewal-window,
escape-hatch and pgTAP-rollback gates. Fresh Sol security/money/concurrency
review returned GO after the generated `message_category` source, lock order,
renewal remainder and wallet replay boundaries were reconciled.

## Live database and browser evidence

Database workflow `35254672906` applied migration
`20260915100007_phase6_comms.sql` to the linked Cloud project. The follow-up
types commit regenerated `packages/db/types/database.ts` from Cloud with the
Supabase CLI; CI, Holdout and Test immutability workflows for `4461d8c` passed.
The final closeout database workflow was `35301481339`; it succeeded on
migration, pgTAP rollback, schema drift, all 81 files / 6812 assertions, and
the seed dry-run. Main CI `35301481338`, Holdout `35301481361`, and Test
immutability `35301481359` also succeeded on `3e5120b`.

Against a fresh local web server backed by the real project:

1. Front desk sign-in (`divya@ironbox.example.com`) opened `/messages` and
   rendered the live statement snapshot: scheduled/sent/delivered/failed/
   opted-out counts, all current message rows, and the consent form with the
   generated purpose/category boundary intact.
2. Member sign-in (`aarav.member@ironbox.example.com`) opened
   `/member/messages` and rendered only Aarav's in-app inbox and append-only
   service/marketing consent history.
3. The same member requested the staff `/messages` route and was redirected to
   the member home, proving the navigation boundary with a real access token.

The journey was intentionally read-only: it created no consent, notification,
wallet or audit row, so cleanup is exactly zero rows and no seeded fact changed.

## Delivery

Implementation commit `690fafd`; generated-contract and final repair commits
`0a5a814`, `45bf5e4`, `9ae50a0`, `480756b`, `7109331`, `3e5120b`. Registry and
current OpenSpec communications requirements are synchronized with the shipped
helpers and screens. The communications browser journey above remains valid.
The current specification, registry entries and plan are synchronized. The
completed change is archived at
`openspec/changes/archive/2026-09-18-phase6-comms/`.
