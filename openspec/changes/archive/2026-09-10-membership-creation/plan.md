# Membership creation — first paid period

## Current scope

A dated membership with no granted periods can receive a paid period on top of
its manually entered span. The same payment then buys different membership time
from the ordinary dateless creation path.

The committed normative contract is `specs/membership-creation/spec.md`.
The first complete paid grant sets both dates: start at the later of the
existing start and the gym-local payment date, then grant the recorded sold
duration times the periods bought. Partial payments move no dates until they
buy a complete period. Existing renewals retain their extension behavior.

The earlier INSERT span cap was withdrawn; it is not part of this change.
OPEN-029's unpaid direct-creation gap remains open. Half-dated membership
semantics (OPEN-026), refund idempotency (OPEN-031), refusal precedence
(OPEN-034), and discount arithmetic (OPEN-028) are separate contracts.
Refunds remain gym-admin work; front desk must escalate a refund to a manager.

## Quality bar

Exact integer paid-period arithmetic, tenant isolation and security-invoker
privileges preserved, independently authored visible and holdout assertions,
all affected gates green. These are the measurable backend bars in
`docs/architecture.md`.

## Implementation boundary

Only the dated branch's `starts_on` and `ends_on` assignments in
`app.grant_periods()` change. Compare its executable body against migration
`20260912150000_money_does_not_grow_a_retired_membership.sql` before committing.
No schema/type signature or trigger definition changes are required.

## Verification

- [x] Commit the resumed normative contract before test edits (`f337a3a`).
- [x] Independent visible author completes tests, verified red: 805 assertions,
  8 failures, committed `5f7d53d`.
- [x] Independent holdout author completes tests, verified red: 1001 assertions,
  69 failures, committed `2878076`.
- [x] Both suites pass with migration replayed inside BEGIN/ROLLBACK: visible 809, holdout 1001.
- [x] Fresh-context critic approves the executable change after the half-dated regression was corrected.
- [x] Full pgTAP sweep: 47 files, 4243 assertions, zero failures or plan shortfalls. Seed/scenarios pass twice in one rollback transaction.
- [x] Local gates and post-push CI pass; CI applies the migration.
- [x] Browser exercise verifies the payment/receipt/membership loop; the demo snapshot is restored in the same session.
- [x] Sync the surviving requirement into current specs and archive this change.

Local lint, typecheck, duplication/dependency checks, unit tests and production
build passed on 2026-09-10 before the migration was landed. Database evidence
must include assertion counts as well as failure counts; a run that aborts
before its declared plan is not a pass.

Final evidence: `docs/evidence/2026-09-10-first-paid-period.md`. CI passed all
47 files / 4243 assertions and the seed dry run. The browser issued receipt
`2026-27/000007` for exactly one 30-day period, then the temporary payment was
removed and the original membership snapshot restored. The receipt number
remains spent by design.
