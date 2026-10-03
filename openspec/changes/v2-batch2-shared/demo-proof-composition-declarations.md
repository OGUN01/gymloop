# Demo proof composition correction

Frozen engineering verification protocol, 2026-10-03. Actual held diagnostics
show only the existing legacy scenario members101–116 and their memberships
refreshing joined_on, starts_on, ends_on, activated_at, cancelled_at and updated_at
through the preexisting retention-loop seed. No original30 member, staff, Auth,
product money/stock or sold price changed. The canonical legacy scenario spec
intentionally converges date-relative scenarios when it is rerun.

The new Batch-2 packet must preserve all existing legacy identities, membership
facts and money exactly. Its proof baseline therefore SHALL follow the ordinary
legacy setup, and precede every new packet execution. No legacy date refresh is
excused within either tested Batch-2 execution. No assertion may discard these
date fields or narrow its existing identity/money preservation scope.

Each independent fragment retains BEGIN/ROLLBACK and the existing single
`-- ROOT_INSERT_BATCH2_SCENARIOS_HERE` marker. Add exactly one
`-- ROOT_INSERT_LEGACY_SCENARIOS_HERE` marker before every TEMP baseline or view.
The primary first canonically splices ordinary seed.sql immediately after BEGIN.
The verification composer splits current seed-scenarios.sql at its exact unique
line `-- Batch-2 public packet: represented static states, never command evidence.`
It substitutes the unchanged legacy prefix exactly once at the legacy marker,
then substitutes the Batch-2 suffix, including that boundary line, exactly twice
at the existing Batch-2 marker. Missing/duplicate/out-of-order markers or missing/
duplicate boundary SHALL refuse composition. Both generated proofs remain strict
rollback transactions and expose unique exact pgTAP counters.

No production seed behavior changes: manual CI still applies ordinary seed.sql
and complete seed-scenarios.sql in its existing order. The legacy seed source
and its existing scenario tests remain unchanged. This protocol proves that the
new packet preserves the exact complete legacy state after lawful legacy setup;
it does not claim the older relative-date seed is immutable on a later date.
Existing cohort, clock/audit, full owned graph, foreign-relation and money tests
stay intact. Independent authors update their own fragments and any owned static
proof-wiring checks before a separate integration builder updates CI composition.
Fresh review and actual visible/holdout executions remain mandatory.
