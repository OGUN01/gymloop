# SLF holdout requests suite — abort diagnosis and repair (2026-10-04, holdout author)

Suite: `supabase/tests-holdout/h81_member_freeze_requests_holdout.sql`
Repaired sha256: `b316e1da532ddfeac7b253a70ba1d07c1a5928fc5209d38c9620513dadb8d827`
(plan 139 → 138, then the builder-round adjudication amendments and the
round-2 residual amendments below; still plan 138). Implementation was never
read; diagnosis from the frozen public contract, the builder's public
adjudication (`docs/evidence/v2/slf-builder-report.md`), and Cloud
rollback-only runtime facts supplied by the orchestrator.

## Original abort

`ERROR: GL066: Member freeze request overlaps an effective pause or request`
through `public.approve_member_freeze_request` → `app.slf_freeze_prepare`
during the suite's FIRST expected-success approval (request key …701, member
…101, interval = gym-local today … today+4).

## Root cause 1 — fixture defect (out-of-contract direct-insert probe)

The suite asserted that a direct superuser `INSERT INTO public.membership_pauses`
naming a different employee than the caller raises the existing different-employee
guard. Runtime proof (Cloud, rollback-only, inside the suite transaction): the
INSERT PERSISTS (row observed with `requested_by_staff_id …403` while the caller
carried `402`; 7 user triggers exist on `membership_pauses`, none refused it).
The guard is a command-level authority of the existing desk pause command, not a
table-level writer guard. The frozen contract does not extend SLF-006's "never
names a different employee" to arbitrary superuser writes; D-SLF-2 records
direct-write bypass as a documented residual. The assertion over-pinned a
mechanism outside the contract — removed with the reason recorded in the file.

That persisted leftover was also the abort's direct cause: member …101 then
carried TWO undecided pauses overlapping the requested interval — the request's
own adopted source pause (lawfully excluded by SLF-005) and the unintended
forged one (not excluded). The approval therefore lawfully refused GL066.

## Root cause 2 — fixture defect (replay under the wrong actor)

After the first fix the suite aborted with `GL068: Member freeze command key
conflict` at the final approve replay of request …701 (key …811). The replay
ran under the preceding desk2 claims (subject …313) instead of the ORIGINAL
approving actor (gym_manager …310, the actor that first used key …811). SLF-013:
changed actor under a key SHALL conflict — the refusal is correct behavior, the
fixture was wrong. Repaired: the replay now runs under the original approver's
claims, with the reason recorded in the file.

## Post-repair runtime (orchestrator's Cloud rollback-only rerun)

No abort; the suite runs its full plan(138) with 14 defect-capturing failures
(the RED expectation against the incomplete/behind-contract implementation).
`check-pgtap-rollback` static guard: green on the repaired file.

## Mirror check (h81_overlaps)

The private overlap-mirror helper was re-derived against SLF-005: member-scoped
requests with effective open status, member-scoped non-rejected pauses that are
undecided or approved, exclusion of the request's own linked source pause and of
source rows belonging to closed/ineffective requests, inclusive-overlap bounds.
No divergence from the frozen contract text was found; the mirror was left
unchanged and continues to decide only expectation bookkeeping, never to replace
real-RPC behavioral proof.

## Cross-suite observation (not edited; visible author's file)

The visible suite `supabase/tests/81_member_freeze_requests.sql` does NOT
contain the forged-insert probe, so its separately observed 1 failure of 141 is
unrelated to this repair.

## Builder-round adjudication amendments (2026-10-04, second pass)

Against the builder's public adjudication (migration sha `0faadbaa…f18326`),
eight lawful amendments with recorded in-file reasons; plan count unchanged:

- **F3 (SLF-002 pending).** The scenario had run under M1's claims with M14's
  membership id as the argument, conflating bound member and target membership
  (SLF-004 binds the request to the member's OWN membership). It now runs as
  M14's own identity and pins the declared membership-state refusal, 22023
  `Membership does not permit freeze requests`, which precedes the one-effective
  guard — superseding the stand-in's GL066 convention.
- **F4 (SLF-004 span).** Membership 201 spans Jan 1 of the run year minus nine
  months to Jan 1 two years later; d0+400 fell INSIDE that span, so no refusal
  could fire. The interval is now d0+800…d0+804, always beyond the span end.
- **F5 (SLF_LIMITS one-effective).** Re-pinned to the declared class GL066 with
  the declared message `Member already has an open freeze request`; the former
  GL067 pin was the stand-in's convention, not the frozen vocabulary.
- **F6 (SLF-003 trio).** Erased and unlinked actors re-pinned to 42501
  `Member freeze authority unavailable` (slf_member_actor's declared outcome);
  the foreign-tenant case re-pinned to 42501 `Membership unavailable for freeze
  requests` per the builder's post-F2-reorder declaration. The safe reads keep
  their own P0002 collapse pins, which the builder's F9 aligns with.
- **F7 (SLF-005 overlap vs SLF_LIMITS precedence).** The former probe ran
  against member …102, who already holds the effective open request …703, so
  the one-effective guard fired first and the two conditions were conflated.
  Isolated per the preferred option: a lawful approved fixture pause on member
  …115's membership …217 (d0+6…d0+8, no open request for that member), probe
  interval d0+7…d0+9, pinning the declared overlap class GL066 (code-only; the
  declaration does not state the creation-path message). No contract question
  remains — isolation preserves the intended one-guard-per-assertion testing.
- **F11 (SLF-014 partial unique).** The probe's intent was the agreeing
  duplicate reaching the partial unique index, so the duplicate is now a full
  copy of the linked request row (every reciprocal dimension identical; only
  id and request_key differ) and pins 23505. The former literal duplicate
  disagreed on reason, dates (session `current_date` vs gym-local d0) and
  decision truth, which the additive invariant lawfully refuses with 23514
  before the index; that disagreeing shape remains covered by the suite's
  other every-writer invariant probes.
- **F1 (replay second row) and F10 (read effective state) — re-checked
  conceptually against the F2/F8 fixes.** Neither expectation depended on the
  pre-fix ordering; both observed results (0 matches; NULL effective value)
  are consistent with a JSON member-spelling mismatch, which the frozen
  contract does not pin. Both assertions now accept either casing
  (`requestId`/`request_id`; `effectiveStatus`/`effective_state`) with
  recorded reasons, so the rerun adjudicates any residual cause honestly.
  The member-list containment pin (§B8) received the same spelling tolerance
  for the same reason.

No assertion was weakened below the frozen contract: every amendment either
re-derives a lawful fixture shape, pins the builder's declared vocabulary, or
removes a spelling over-pin the contract does not make. `check-pgtap-rollback`
static guard: green. `$q$` pairs even; plan(138) unchanged; 52 throws_ok probes.

## Round-2 residual amendments (2026-10-04, after rerun on migration 0faadbaa)

Post-adjudication rerun: 3 failures of 138 remained. Amendments:

- **#61 (foreign tenant).** Re-pinned to the observed declared outcome 42501
  `Member freeze authority unavailable` with the recorded SLF-003
  authority-first reading: a foreign-tenant claim cannot resolve a valid actor
  for the target tenant, so the authority check refuses before any membership
  lookup, and the membership message would leak membership-state facts about a
  target the actor must not see.
- **#47 (replay created no second row).** The create and replay assertions
  themselves pass, so no refusal changed the count basis; the 0-count is
  consistent with the list projection carrying the request id under a JSON
  member spelling outside the two guessed names. Amended to match ANY top-level
  string field carrying the created request's id (contract pins content, not
  spelling). If the next rerun still observes zero, this is a public finding:
  the member read projection does not surface the member's own created request
  (SLF-001/SLF-004 caller-session projections; the list RPC exists to show the
  member's own requests with a deterministic descending keyset).
- **#134 (own-member scoping).** Same root cause and same treatment: the
  containment form was pinned to guessed spellings; now asserts presence of the
  member's own request and absence of the foreign member's request via the same
  any-string-field match, preserving both business facts without pinning an
  unpinned key name.

`check-pgtap-rollback` green; `$q$` pairs even; plan(138) unchanged.

## Open questions for the orchestrator

- If #47 or #134 still fail on the next rerun, they are genuine public
  findings for the builder under the read-back clauses cited above.
- F9 risk note acknowledged: the suite's cancel-of-another-member pin (P0002)
  already matches the collapsed declared behavior; no amendment needed.

