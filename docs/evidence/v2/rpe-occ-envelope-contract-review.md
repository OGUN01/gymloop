# RPE / OCC mechanical-envelope fresh review

Verdict: **GO — corrected declarations are ready for primary serial freeze.**
2026-10-04. Documentation-only; no runtime/deployment assertion.

Read AGENTS.md, both frozen proposals/current sql-envelope-declaration.md,
docs/architecture.md and relevant data-model/registry entries. Re-review checked
the current declarations against this review's prior findings. Did not read source,
tests, holdouts or other reports. No Git, Cloud, browser or device action.
Only this review document was written.

## RPE capability and snapshot feasibility

The original invoker-to-ungranted-helper path is replaced with a feasible metadata
relation and migration-installed triggers. Trigger invocation needs no ordinary
caller EXECUTE grant on the private trigger function. Column-level INSERT permits
only dataset/range/branch/cap; derived fields are server-filled, required and cannot
be assigned by authenticated callers. BEFORE validation uses original caller RLS;
AFTER audit alone elevates privileges. Same-actor/tenant active-owner RLS and
immutable metadata prevent forged count/stamps/attribution and cross-actor reads.
No exported rows/contact data are persisted; no source policy is expanded.

The audited command is VOLATILE. Its one source/preparation/assembly statement
and STABLE invoker validation reads can retain the containing statement snapshot.
UUID generation does not change source snapshots. Count/boundary reconciliation
rolls back on mismatch. Zero rows prepare normally; over-cap prepares nothing.
Implementation must prove the declared actor-first ordering before source access;
CTE textual ordering alone is not such proof.

Direct staging INSERT creates only lawful bounded preparations, never arbitrary
count/stamps/events. The private definer reads only validated metadata, never
report sources. Staging SELECT exposes only the caller's own audit-linkage metadata.
Original source privileges and erasure remain authoritative. No owner amendment
is required for this mechanical relation. Register relation, triggers/functions,
indexes and volatility/grants; record its reuse decision before implementation.

Release accepts only the released event and byte/digest fields, revalidates actor,
copies prepared metadata and enforces a partial audit uniqueness index atomically.
This closes the previous concurrency ambiguity without changing business behavior.

## OCC corrections verified

- Below 14 eligible dates, normalized heatmap values/common-scale encoding are
  prohibited; raw numerator/denominator remain available with Limited history.
- Class cohort percentages/ranking stay suppressed below 10 elapsed sessions;
  raw evidence and required individual-session drills remain available.
- Undated warnings explicitly require arrived payment/completed return status
  and null event date; their scope remains current all-date authorized tenant.
- Future-only populations are unavailable; current-only arrivals stay separate;
  noEligibleDays no longer treats future-only dates as observed exposure.
- Cancelled exclusions use selected dates and endsAt < asOf, no bookings/capacity,
  and service counters contain only corresponding exclusions.
- Earlier-membership evidence uses strictly smaller created_at; tied timestamps
  are not earlier and no id tie-break invents renewal classification.
- allocationUnknown is true exactly for unallocated returns, making the specified
  unknownReturnPaise equality reconcile with the disjoint categories.

Exact strings/currency arithmetic, same-snapshot components, limited-identity
session/service/payment/return drills, DST/holiday exposures, branch-zone errors,
all-branch reconciliation and cutoffs remain faithful. Verified owner/manager
access stays explicit despite registry shorthand. No additional person/contact/
Auth/booking/trainer identifiers, statuses, smoothing, opening-hour history,
financial branch attribution or causal claims are introduced.

## Freeze and evidence boundary

No remaining owner choice or declaration blocker was found. Field names/nulls,
sorting and codec choices do not require additional approval gates.
GO approves declaration consistency and feasibility only; it does not certify
implemented triggers/grants/RLS, runtime snapshots, transport or presentation.
Independent authors must test real canonical RPCs and real route/audit seams;
helper mirrors or client-rebuilt populations cannot establish this contract.
