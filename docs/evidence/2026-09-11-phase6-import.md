# Phase 6 member CSV import — verified

The frozen CSV-D01..D16 contract ships the member CSV/XLSX import pipeline: a
v1-columned `member_imports` run with a fused invariant trigger, the
`prepare_member_import` / `commit_member_import` security-definer command
pair, the four HTTP endpoints, the CSV/XLSX parser, and the `/imports`
five-step working screen — upload, mapping, preview, confirm, report.

## Independent tests first

Full blind arrangement, per ADR-059 (silent-failure territory: identity, RLS,
money-adjacent member creation). Database tests (visible `28_member_import_
structure`, `29_member_import_prepare`, `30_member_import_commit` + holdout
`h28_member_import_holdout`) and the unit/route/screen suites
(`member-import-routes.test.ts`, `member-import-parse.test.ts`,
`comms`-adjacent screen tests out of scope here) were authored
implementation-blind and committed red before any source: `adc95e7` (unit,
route and screen suites) and `02281b6` (parser unit suite, authored by a
separately-tracked agent that landed after the implementation existed due to
an agent-crash relaunch — noted rather than hidden, since the parser's own
assertions were still never read by its implementer).

Three harness repairs happened under ADR-060 (orchestrator repairs a failing
harness, never the implementer): `bbab888` (strict indexed-access on the
report-row assertions), `c2e546d` (two unsatisfiable assertions in the errors
test), and `9e46890` (the visible and holdout suites' pgtap calling-convention
bugs, stale Phase-1 policy names, and the genuinely-missing NAV-003
impersonation-exclusion retrofit the holdout debugging surfaced — see below).

## Candidate checks and critics

Local pgTAP sweep across the full cross-repo suite (75 files) ran 71 green /
4 red before the implementation push, the 4 red being exactly the
not-yet-implemented comms cluster's suites (31/32/33/h29), never the import
cluster's own files: `28_member_import_structure` 58/58,
`29_member_import_prepare` 62/62, `30_member_import_commit` 88/88,
`h28_member_import_holdout` 265/265 — 6,414 assertions total across the sweep.

A fresh-context blind critic reviewed the landed cluster against the frozen
contract with no prior discussion context: tenancy/RLS composition, the
v1 run state graph under every writer, the advisory-lock commit concurrency
design, independent phone/member_code duplicate classification, and report
persistence correctness. **Verdict: GO.** Two non-blocking findings: the
registry named the wrong trigger (`member_imports_v1_invariant` instead of
the actual `member_imports_touch_updated_at` fusion — corrected in `8742b08`
along with registering the previously-undocumented
`member_imports_preview_write_guard` statement trigger), and a raced
member_code duplicate is reported with `field`/`reasonCode` hardcoded to
`phone` instead of naming whichever constraint actually fired. The second was
not fixed in place — `20260915100006` was already applied on Cloud by the
time of the critic's review, so a local edit to that file would only diverge
from the live schema rather than change it (ADR-030). Recorded as **OPEN-035**
in `docs/decisions.md` with the drafted fix shape for whoever picks it up; not
a money hole and not blocking (the row's disposition and every persisted
count are correct — only a diagnostic label in the errors CSV can misname the
column).

## A genuine security gap found by holdout debugging

While repairing `h28`'s failing assertions (never read by the implementer,
per ADR-060), the orchestrator found `member_imports` had never received the
NAV-003 impersonation-read exclusion that leads got in `20260915100005` — a
support preview session could still read and, via the RLS-silent-zero-rows
gap, attempt to write a gym's import runs. Closed in the same migration with
the `and (select app.current_impersonation_id()) is null` clause on both
tenant policies and a new `member_imports_preview_write_guard` statement-level
trigger (the same pattern as leads' identical sibling), with `04_contract_
meta.sql`, `10_platform_rls.sql` and `h28` itself updated to match. This is
exactly the class of defect ADR-059's full-blind rigor exists to catch.

## Real browser acceptance and cleanup

Signed in as the gym owner (`owner@ironbox.example.com`). `/imports` renders
the five-step screen. Ran three journeys against a fresh dev server (the
first attempt hit a stale Turbopack module cache from an earlier long-running
dev server and was discarded after confirming via `supabase db query` that it
created no member rows and left its run stuck at `pending`):

1. **Golden path**: uploaded a 2-row CSV (`journey_members.csv`), mapped all
   8 columns, previewed (2 rows, would import 2, 0 duplicates, 0 invalid,
   phones normalized to `+91`, effective day correctly `Asia/Kolkata`-local),
   confirmed. Report: imported 2, 0 duplicates, 0 invalid. Verified in the
   database: `error_report.rows` empty (imported entries correctly excluded),
   `importedRows` `[2,3]`, both members created with every field exactly as
   uploaded, both visible in the console member list.
2. **Duplicate detection**: re-uploaded the identical file. Preview correctly
   reported both rows as `Duplicate` with **both** `existing_phone,
   existing_member_code` reason codes shown together (independent per-row
   dimensions, confirming the critic's traced behavior end to end) and
   `duplicate_count = 2`, `would import = 0`.
3. **Role refusal**: signed in as the trainer account (`rohit@ironbox.
   example.com`); navigating to `/imports` redirected to `/console` —
   `canImportMembers` correctly gates the screen to owner/manager.

Exact cleanup: the two journey members (`92e8085c…`, `966222ff…`) and all
three `member_imports` rows created during the journeys (the golden-path
completed run, the discarded stale-server pending run, and the uncommitted
duplicate-preview pending run) were deleted by id. Verified back to baseline:
zero rows matching the journey's phones or file name in either table
afterward. No seeded row was touched.

## Delivery

Test-red commits `adc95e7`, `02281b6`; harness repairs `bbab888`, `c2e546d`,
`9e46890`; implementation `a2f78aa`; types integration `6934ca7`; critic
follow-up docs `8742b08`. Database workflow `34595018276` (push 1) applied
migration `20260915100006` and passed `migrate`, `pgtap-rollback`, `pgtap`
(6,414 assertions, only the comms cluster's intentionally red files not
green) and `seed-dry-run`, with `schema-drift` red as expected before types
regeneration. Database workflow `34598957109` (push 2, types-only) passed
every job including `schema-drift`. CI `34595018237` and `34598957125`, and
the Holdout and Test-immutability workflows on both pushes, all green.
