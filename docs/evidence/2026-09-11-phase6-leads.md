# Phase 6 leads — verified

The frozen LEAD-001..005 contract ships the front-office enquiry pipeline: a
graph-disciplined `leads` table, three claim-derived security-invoker RPCs
under compare-and-swap with exact replay, the list snapshot with escaped
search, and the `/leads` working screen — record, edit, stage transitions with
a gym-local trial time, convert (create or link), mark lost, with every
refusal surfaced honestly.

## Independent tests first

Visible and holdout authors worked implementation-blind and did not read each
other's suites. The visible suite (25/26/27 + the platform-shape leads section)
and the independent holdout committed red before the implementation commit
`fc888dd` touched any source. Both suites together own the stage graph edges,
the fact rules (E.164 phone, enum vocabularies, conversion evidence), the CAS
and replay contract, the GL062 cross-lead request-key arbitration, the
claim-stamped creator evidence, and the preview identity's read-only shape.

Two harness repairs happened under ADR-060 (orchestrator repairs a failing
harness, never the implementer): h10's converted/lost history inserts needed
the ADR-098 replica bypass after the INSERT discipline became ungated, and the
visible twin in `10_platform_shape.sql` needed the same — both recorded in
ADR-120 with the trigger row registered.

## Candidate checks and critics

Full local gates pass: lint, typecheck, jscpd, knip, 867 web + shared vitest,
registry-lint, escape-hatches, pgtap-rollback, build, depcruise,
test:scripts 47/47. The Cloud sweep ran the leads files green (25 = 128, 26 =
60, 27 = 37 assertions; h27 = 276). A fresh-context critic returned GO on the
fix delta; its single registry MINOR was fixed in the same push.

## Defect found and fixed in acceptance

The browser journey exposed a route defect the psql probes could not: both the
route and the visible suite addressed `transition_lead` with `p_to_stage`,
while the migration declares `p_target lead_stage`. PostgREST resolved no
overload, returned `PGRST202`, and the failure table folded it into the
default 500 — every UI stage change failed while direct SQL succeeded. The fix
(`e8427a2`, `spec:` prefix because the suite pinned the RPC call shape) names
the parameter the database declares; all 53 leads-route tests pass.

## Real browser acceptance and cleanup

Signed in as Divya Menon (front desk). `/leads` renders the full pipeline:
eight seeded leads, within-filter counts, snapshot-as-of, filters, next
actions, and the enquiry form. The live journey exercised every edge of the
graph:

1. Enquiry recorded end-to-end (reload-confirmed).
2. new → contacted (screen updated; next action became "Schedule trial").
3. contacted → trial_scheduled with gym-local trial time 2026-09-12 09:00;
   the screen showed "Trial at 2026-09-12 09:00".
4. trial_scheduled → trial_done.
5. trial_done → convert (create path): navigated to the new member page; the
   lead row flipped to `converted` with `converted_member_id` set.
6. A second enquiry ran the same path and converted through the create path
   again; both journeys' rows were removed afterwards.
7. A details-save-then-stage-save sequence on a fresh enquiry confirmed the
   save-against-loaded-revision discipline end to end.

Evidence screenshots: `docs/evidence/screens/phase6-leads-contacted.png`,
`phase6-leads-trial-scheduled.png`, `phase6-leads-trial-done.png`,
`phase6-leads-converted-member.png`, `phase6-leads-converted-link.png`.

Exact cleanup: the journey lead (e9670902…) and both converted members
(b0acdcac…, 22e44287…) were deleted by id, one seeded lead briefly moved
(Nandini Sethi, new → contacted during the stale-revision probe) was restored
to its seeded stage and null trial time, and the baseline was verified:
8 leads in the seeded stage distribution (2 new, 2 contacted, 1 each of the
rest), 46 members. No seeded row's content changed.

## Delivery

Implementation commit `fc888dd` (with the red suites at `15c8601`), types
integration `586b9f8`, and the transition-parameter repair `e8427a2`. Database
workflow `34562963974` applied migration `20260915100005`, passed pgTAP and
seed dry run, and schema-drift went green on the types push. CI
`34564043351` covers the repair commit.
