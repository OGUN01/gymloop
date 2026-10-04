# SLF holdout requests suite — abort diagnosis and repair (2026-10-04, holdout author)

Suite: `supabase/tests-holdout/h81_member_freeze_requests_holdout.sql`
Repaired sha256: `6ad8eb1cf1222d96ce2d773d65fb1a39d5794267c4f964e0d5f17ecad320b0ea`
(plan 139 → 138). Implementation was never read; diagnosis from the frozen
public contract plus Cloud rollback-only runtime facts supplied by the
orchestrator.

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

## Open questions for the orchestrator

None from this repair. The 14 remaining RED failures are defect-capturing pins
whose adjudication belongs to the separate builder round.
