# 0004-retention

Phase 4: the retention engine — the daily no-show scan in each gym's own timezone, cases, follow-ups, the red list staff work from, and the schedule that runs it.

**The half of the product it is sold on.** Phase 3 recorded that a member turned up; nothing read the absence of it. A gym owner could already see who came in and still could not see who had quietly gone.

## Exit criteria met

`docs/roadmap.md` asks for Journey B end-to-end and no duplicate open cases under repeated runs.

- **CI run on `15ac779`** — all four workflows green: `CI` (nine gates), `DB` (migrate, `pgtap-rollback`, `schema-drift`, and the full TAP stream through `prove`), `Holdout`, `Test immutability`. **43 pgTAP files, 2289 assertions**, and 2289 is exactly the sum of every file's `plan(N)`.
- **The loop ran end to end in a browser** against Cloud: a case opened by the scan, shown on the red list, a follow-up logged from it, the case moving to `contacted` on its own with the contact attributed from the JWT claim rather than the form. `docs/evidence/phase4-red-list.png`.
- **Idempotence proven**: a second scan returns 0; `get diagnostics row_count` after `on conflict … do nothing` counts rows that landed, not rows attempted.
- 180 web tests; `pnpm run gates` green.

## What was built

| Object | |
|---|---|
| `app.run_no_show_scan(tenant, today)` | Opens one case per member absent past the gym's own threshold, in the gym's own timezone, excluding approved pauses — and closes cases whose membership has lapsed |
| `app.close_no_show_case_on_return()` | NSH-005: a returning member closes their own case, follow-ups preserved |
| `app.enforce_follow_up()` | Attribution, closed-case refusal, concurrency, corrections, and status derived from what happened |
| `public.run_no_show_scan_all()` | The loop over gyms — in SQL, because "which gyms get scanned" is a rule |
| `public.red_list_cases` | `security_invoker` view: days-absent at read time, latest follow-up attached |
| `cron.job no-show-scan-nightly` | `0 1 * * *`, the thing that actually runs it |
| `apps/web` | The red list, the follow-up endpoint, keyset pagination shared with the roster |

## Three critic rounds, and what they cost

Round one: 6 defects. Round two: 6 more, **four of them in code written to fix round one**. Round three: GO.

The defects worth remembering are not the individual bugs but the shapes, recorded as ADR-074 through ADR-081:

- **`revoke … from public` revokes nothing Supabase granted by name.** A *member* could run the nightly job. Phase 2 had already got this right; Phase 4 copied the intent instead of the statements. **Verify a grant with `has_function_privilege`, never with the migration's own prose.**
- **An argument for deriving one fact from evidence is an argument for deriving every fact of that kind.** The scan spent three paragraphs explaining why not to trust `memberships.status` about a *pause*, then trusted it about *expiry* ten lines later. Nothing in this product ever writes `'expired'`.
- **A correction is not a decision.** Staff log "ring Friday", correct a typo through the only mechanism an append-only log allows, and the callback was silently cancelled. Caused by doing the right thing; symptom is a member who is never called.
- **`Number.isInteger` is not "an integer Postgres accepts".** `Number.isInteger(1e21)` is `true`; its string form is `"1e+21"` and Postgres answers `22P02`. A validity check on a value crossing into another system must be written against *that system's* type.
- **A checker whose failure mode is silence is worse than no checker.** See below.

## The failure that mattered most

**The DB workflow was red on `main` for six consecutive commits while commit messages said "43/43 green, every gate."**

Three causes, compounding. I read `CI completed/success` beside `DB in_progress` and treated one workflow's verdict as another's. My local sweep agreed, because it read `num_failed()` — which ADR-069, written earlier in this same project, says is not the TAP stream. And the sweep **could not report a failure at all**: `supabase db query` returns the last result set *that has rows*, and on a failing file `finish()` emits a diagnostic row that shadows a `num_failed()` placed before it. A failing file produced no output, its name printed with nothing beside it, and the next file's result landed on that line.

One bug explained every anomaly I had noticed and rationalised — "42 results for 43 files", a file that seemed to vanish mid-run, a `grep` exiting 1.

**ADR-078's rule is the one that would have caught all of it: test a checker in both directions.** Every check in this project had been verified only against input it should pass, which proves it can say *yes* and nothing about whether it can say *no*.

`pnpm run gates` now runs all nine gates in one command and states its conclusion in words, because listing them from memory cost `knip` and the root-vs-per-package `lint` distinction in a single night.

## What the blind arrangement bought, concretely

- A holdout author found NSH-005 **entirely missing** and the live set reading pause state off a status column — both invisible to 34 passing assertions written from the same spec by a different author.
- A test author **deleted an assertion I asked for**, because a constraint made the state it described unreachable, and verified that by reading the constraint rather than assuming.
- A test author **changed a requirement by refusing to guess at it**: "an open case" versus the three states the index treats as one. It asserted the literal reading and reported the ambiguity.
- A test author **added two controls nobody requested**, for a failure mode nobody had considered: a per-status implementation would pass a single control while silently destroying a live member's in-progress case.
- The round-three critic **wrote its own implementation of the scan from the EARS text** and compared row-for-row, then proved the timezone fix *during* the 01:00 IST window the defect lived in.

## Carried forward

- **OPEN-008** (new): the red list cannot schedule a follow-up. `nextFollowUpAt` exists in the schema, the request schema and the handler, and no input supplies it — so `follow_up_due` is unreachable through the product and the index built for "which follow-ups are due" is fed by nothing. Closing it needs a decision about how a wall-clock time from `<input type="datetime-local">`, which submits no offset, becomes an instant in the gym's timezone. Phase 6, with its own spec.
- A gym with no `organization_settings` row is skipped silently and for ever; the per-gym return shape cannot distinguish it from "nothing to do". Phase 6 onboarding (OPEN-018).
- `app.enforce_follow_up()` exempts `service_role` entirely, so a future backfill would leave contacted cases sitting on the red list.
- `follow_ups.created_at` is client-writable and the view's latest-follow-up lateral has no tiebreaker — same shape as OPEN-010 on a new table.
- The migration comment claiming case status is "not writable as an input" is overstated: `authenticated` holds `update` on `no_show_cases` deliberately, and a holdout asserts a trainer works a case that way.
