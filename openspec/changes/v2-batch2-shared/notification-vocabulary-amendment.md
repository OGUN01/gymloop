# Proposed owner amendment — commit notification vocabulary before batch 2

**Owner approved, 2026-10-02 (explicit answer in the campaign chat).** This changes the approved single-push batch-2 staging,
not its feature behaviour or acceptance bar. No migration or test is implemented
by this proposal. CI remains the only migration writer.

## Why a decision is required

Batch 2 adds `class_update` and `announcement` to the existing
`public.message_category` enum. The freshly generated Cloud type still contains
only renewal, payment, fulfilment, promotion and motivation. The local proof
splices pending migrations into each test's BEGIN/ROLLBACK transaction.
PostgreSQL forbids using a newly added value of an existing enum before that
transaction commits. The proposed CLS/ANC notification tests therefore cannot
exercise those values in the current rollback splice.

[PostgreSQL's ALTER TYPE documentation](https://www.postgresql.org/docs/17/sql-altertype.html#SQL-ALTERTYPE-NOTES)
states that the new enum value is unavailable until the adding transaction
commits. Committing a local Cloud test would violate AGENTS.md rules 7/10 and
ADR-030; omitting notification assertions would lower the approved bar.

## Recommended concrete staging

1. Wait for the whole batch-1 DB run and its generated-types follow-up to finish.
2. Freeze an independently reviewed vocabulary unit. A dedicated migration
   `20261003083000_notification_categories.sql` adds only `class_update`, then
   `announcement`, after the existing five labels. CLS/ANC no longer add labels
   in their main migrations. No table, row, role, policy, command, default,
   delivery behaviour or notice helper changes in this unit.
3. Separate visible and holdout authors amend the pinned enum assertions in
   `31_comms_schema_consent.sql` and `h29_comms_holdout.sql` before the separate
   implementer writes that migration. Validate exact ordering and preservation
   of the existing labels through catalogues inside rollback transactions.
   A fresh blind review checks the two-statement scope, current notification
   privileges/guards and compatibility. Existing routes must retain their
   validation and consent behaviour; early enum acceptance must not introduce a
   consent bypass. This is a gate to prove, not an assumed safety claim.
4. Push this small unit alone; CI commits it and runs every required gate and
   the complete existing pgTAP/holdout suite. Regenerate types through the CLI
   after migrate succeeds, use ADR-177 for the migration-free follow-up, and
   wait for the whole vocabulary DB run before another migration push.
5. Build all seven business features in parallel as dependencies permit. Their
   rollback splices can now use the committed labels. Complete all independent
   tests, full local sweep, fresh critics and gates. Push booking primitives and
   all seven business migrations together, followed by generated types under
   ADR-177. Every business feature retains the original Gauntlet Loop.

The vocabulary stage costs one additional full DB run (historically about an
hour, not a guaranteed duration). Contract/test/build work runs during that
wait. No local database, Docker, Supabase MCP, manual Cloud migration or skip of
new-label behaviour is authorized by this amendment.

## Decision footprint

Approval requires an owner amendment to batching in the handoff/ADR log,
move enum ownership in shared decisions and CLS/ANC proposals before their
authors start, and add this migration before `085000` booking primitives.
The seven business migrations still ship as one coherent batch.

The owner selected this sequence. Every gate remains required; the single-push
alternative is superseded only for this vocabulary prelude. No manual commit or
lower acceptance threshold is authorized.

## Frozen EARS for the vocabulary unit

- **V2-VOC-001:** WHEN CI applies the vocabulary migration THE SYSTEM SHALL keep
  the existing enum labels and append `class_update`, then `announcement`, in
  exactly that order. The migration SHALL contain only these two enum additions.
- **V2-VOC-002:** THE SYSTEM SHALL preserve existing notification role grants,
  RLS policies, guards, defaults, commands, rows and consent behaviour. No feature
  writer, table or delivery mechanism is introduced by this unit.
- **V2-VOC-003:** WHEN the prelude's full DB workflow passes THE SYSTEM SHALL use
  CLI-generated types and committed labels for subsequent rollback-spliced
  feature proofs. The next business migration push SHALL wait for that full run.
