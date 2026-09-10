# Refund retries and financial audit — verified

The fixed contract (`b48a2b9`, delegated authority ADR-111) adds an exact
tenant-scoped refund retry result, deterministic ordering among the named money
refusals, and atomic audit rows for payment/refund INSERT and UPDATE.

## Independent tests first

Separate Astra authors read the contract and their own test conventions, without
implementation or each other's suites. Visible tests were committed in
`95a778a`; holdout tests in `72de5bb`, before implementation edits.

The unchanged shared schema failed 6 of 17 tests; the unchanged route failed
35 of 54. The visible database file declares 116 assertions and the independent
holdout declares 127, both rollback-wrapped. Database baselines were queued
behind the preceding net-price CI run; no local sweep overlaps that workflow.
The holdout author extended only the explicit audit-definer allowlists in the
two prior money holdouts. The implementer has not read holdout source.

After the net-price database workflow completed, the visible baseline refused
the missing key column (`42703`). The first holdout baseline exposed an omitted
fixture price (`23502`); its author supplied that required price in `1c89913`.
The first visible candidate exposed a pgTAP catalogue-collation ambiguity
(`42P22`); its author aligned comparison collations in `5bfc2ef`, preserving
every expectation. Neither correction changed the implementation or contract.
The corrected candidate passes all 116 visible and 127 holdout assertions, with
complete plans and rollback in both files.
Rechecking the corrected fixtures against the unchanged database produced the
expected visible missing-column failure and 96 failing holdout assertions out
of its complete 127-test plan.

## Candidate checks

All 71 targeted shared/route tests pass, as do the full web/shared suites,
lint, duplication, dead-code, dependency boundaries, registry, escape-hatch and
rollback checks. Running the shell gate wrapper initially could not find Node
for its final three scripts; those scripts were rerun successfully through the
workspace's PowerShell runtime. Type checking and production build pass after
the CLI generated the public RPC types from the CI-applied schema.

The full candidate rollback sweep passed all 51 files and 4628 assertions,
with zero failures and every declared plan complete. Both seed files also
passed the independent three net-price assertions after one and two runs,
against both existing and isolated fresh fixtures. Web tests pass 306/306,
shared tests 84/84 and script tests 47/47. Strict OpenSpec validation passes.

The only current typecheck errors identify the new `record_refund` RPC and its
result fields, absent from types generated before that RPC exists in Cloud.
Delivery therefore has two steps under the repository's CI-only migration
rule: push the verified migration and caller, then generate types from the
applied schema and push that generated file. The first head is not claimed
fully green; final typecheck, build, drift and CI remain required.

CI applied migration commit `363d917` in database workflow `34453701833`.
The CLI then generated the new nullable refund key and exact RPC signature
from Cloud; local typecheck and the production build both pass with those
generated types. The build's incidental `next-env.d.ts` path rewrite was
restored. Final CI and live acceptance checks remain pending.

A fresh-context Astra critic returned GO for static review: preserved original
enforcement clauses, correct named order, exact invoker replay, no swallowed
unrelated failures, narrow audit privilege and complete summaries, real staff
identity, and the per-render UUID. The review read no tests and made no database
calls. It does not substitute for runtime and concurrency verification.

## Final delivery evidence

Final head `badbc2f2c348fad85bb45a352dea35a5b9b09176` passed main CI
`34453951676`, immutability `34453951697`, holdout placeholder `34453951658`
and database workflow `34453951689`. The database run passed migration, generated
type drift, rollback checks, all 51 files / 4628 assertions, and seed checks.
Earlier pending-state paragraphs above describe the two-step delivery history.

Live independent database sessions demonstrated actual transaction-lock overlap.
Equivalent requests returned one refund id with first `replayed=false`, second
`replayed=true`, and one audit row. Conflicting amounts sharing a key produced
GL048 for the competing request. Both trials passed and exact cleanup restored
the complete tenant snapshot.

The real owner browser recorded a one-rupee refund from Sneha's receipt.
Reposting its nonce through the actual HTTP route returned 303 to that receipt;
changing the amount to 1.01 returned 303 with `error=idempotency_conflict`.
All tenant snapshots after those HTTP requests equaled the first-submission
snapshot, including timestamps and audit rows. A freshly rendered browser form
recorded a second intentional one-rupee refund with a distinct key. Each intent
created exactly one refund and one owner-attributed `refund.created` audit.

Both exercises used exact row manifests and full-value cleanup guards. Final
payments, memberships, document counters, refunds and audit snapshots equal
their respective pre-exercise snapshots; no receipt number was spent or rewound.
Runtime manifests are retained locally under the temporary refund verification
directory (concurrency run `a0751d2c5c0c464aa5459b944ca6b224`, browser run
`57756c91640240898ffe49597f70ce1e`). No provider refund was sent.

The synchronized refund specification passes strict validation. A broader
all-spec strict check exposed an existing tenancy requirement missing the
literal SHALL/MUST wording; 24 specifications passed and that one failed.
This unrelated documentation warning is not represented as a passing check.
