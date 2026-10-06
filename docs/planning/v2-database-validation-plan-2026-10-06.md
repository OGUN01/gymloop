# Gymloop database validation performance plan

6 October 2026. Proposal for reducing database feedback time as the app grows, while retaining the existing correctness checks. This performance plan changes no CI execution, database fixture, migration or infrastructure; the separate result-parser repair preserves all existing gates.

The owner accepts the small Classes migration and wants to avoid repeated long pgTAP waits. The recommended first change is to run the existing full harness closer to the Mumbai database and measure the result. Preserve the suite and its independent verdict; optimize execution before reducing coverage.

## Measured starting point

| Completed DB run | Migration job | Schema drift job | pgTAP job | Result |
| --- | --- | --- | --- | --- |
| [37389309267](https://github.com/OGUN01/gymloop/actions/runs/37389309267) | 56 seconds | 30 seconds | 124 minutes 23 seconds | pgTAP failed |
| [37376568883](https://github.com/OGUN01/gymloop/actions/runs/37376568883) | 31 seconds | 25 seconds | 110 minutes 3 seconds | pgTAP failed |
| [37443247398](https://github.com/OGUN01/gymloop/actions/runs/37443247398) | 20 seconds | 21 seconds | 128 minutes 55 seconds | Visible73 fixture cleanup deadlock; dependent seed skipped |
| [37443247398 attempt 2](https://github.com/OGUN01/gymloop/actions/runs/37443247398/attempts/2) | Reused green job | Reused green job | 133 minutes 24 seconds | Full161files/16,156tests PASS; ordinary seed PASS; independent replay result-parser error |

The migration itself is not the long stage in these runs. Their job metadata does not establish whether the current failures involve assertions, locks, connection problems or another cause. Resolve the actual failure as well as measuring speed; a quicker red run is useful feedback but does not complete the release gate.

The retained first37443247398 attempt has narrower diagnostic evidence:161files/16,015 executed assertions, with visible73 planned356 but ran215, zero executed assertion failures and a deadlock abort at its DROP TRIGGER cleanup. The remaining141 assertions and dependent seed were unaccepted in that attempt. The [independent triage](../evidence/v2/nav-db-pt73-abort-triage-2026-10-06.json) and [read-only catalog follow-up](../evidence/v2/nav-db-pt73-catalog-2026-10-06.json) preserve the statement, raw cycle and limits: the competing backend and underlying cause remain unproven. Unchanged focused356/356 verification with restoration and one unchanged full confirmation subsequently passed. This does not establish the original cycle's cause or guarantee that regional execution removes it. Durations in the table are job metadata; first-attempt pg_prove reported7,704seconds inside the7,735-second job.

Attempt2 reported7,966seconds inside the8,004-second native job and passed the complete manifest. Its dependent ordinary seed rollback also passed; the separate independent34/26proof loop failed before its first counter verdict because CLI2.110 JSON rows were an array and the generic parser expected an envelope. [Independent triage](../evidence/v2/nav-db-seed-parser-triage-2026-10-06.json) confirms the held proof was never reached. Correct only that transport parser with synthetic tests first, preserving unique typed counters, zero failures, exact literal plans, seed/SQL bytes and every existing gate. Because db.yml itself is classified as a suite input, its correction needs fresh full native CI; the earlier pass cannot be relabeled as coverage of the changed workflow.

[ADR-177](../decisions.md) previously measured 56 minutes for 7,241 assertions over 101 files and attributed the delay principally to network round trips between CI and the Mumbai database. Its evidence is a strong reason to test regional execution, but is not a diagnosis of every current failure. The older twenty-minute and 47-file comments in [.github/workflows/db.yml](../../.github/workflows/db.yml) are not current performance promises.

## Recommended sequence

1. **Measure the current harness.** Record time per file, connection setup time, SQL or TAP errors, lock waits where observable, and total suite completion. Preserve the existing commands and files. Do not start a competing Cloud sweep while a DB run is active. Keep output free of credentials and personal fixture data.
2. **Trial a CI runner near the database.** Use an ephemeral self-hosted runner in Mumbai or another measured low-latency location. GitHub supports a fresh runner that processes one job and is then deregistered; retain its diagnostic logs outside the instance. [GitHub ephemeral runner documentation](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#ephemeral-runners-for-autoscaling). Keep Supabase CLI migration application, supabase test db, pg_prove, rollback enforcement, visible tests and holdout tests unchanged. This preserves the independent checker the project already trusts. Establish a concrete hosting and credentials plan before provisioning paid infrastructure; do not turn the owner's phone or daily desktop into a permanent release runner.
3. **Compare identical inputs.** Compare the same schema, test revision and complete expected file manifest under controlled database state. Require matching assertion plans and verdicts, including deliberately failing harness fixtures. Account for current-time tests rather than assuming elapsed runs have identical time conditions. A timeout or missing result must fail, and every test transaction must roll back.
4. **Land the harness improvement separately.** Tests for runner behavior precede implementation. A fresh critic checks that performance changes cannot make missing, failed or truncated TAP output green. Register new exports, run relevant gates, and retain a way to fall back to the current command. Do not edit application behavior or mutable production data to improve timing.
5. **Use the faster complete gate for Classes.** Keep the Classes configuration contract small, reuse current scheduling, and apply it through CI on main. Finish the full visible and holdout suite before declaring database validation green. Continue with the approved navigation, Home and Shop changes using their own relevant checks.

The initial target is a substantial measured reduction from the current runs. A five-to-ten-minute gate can be an engineering target after profiling, not a promised duration. If SQL execution or lock contention dominates, regional execution alone will not meet it.

## Avoid repeated full runs during development

Use focused approved tests for rapid development feedback, then complete the required full confirmation for the final coherent migration unit. Selection is for iteration, not a replacement release verdict. The migration author must not read or alter holdout files; independent authors and CI retain that responsibility.

Keep the existing main-only workflow and tests-first history. ADR-038 permits the red test commit and the green implementation commit in one coherent push, preserving two commits without paying for a red Cloud workflow on every iteration. Check the required local proof before pushing. Do not combine unrelated features into one migration merely to reduce workflow count.

Reuse ADR-177's existing distinction: UI-only changes do not trigger DB validation, and generated-types-only pushes run schema drift while skipping pgTAP. A no-migration follow-up can be pushed after the previous migrate job succeeds under that decision; a second migration still waits for the preceding full DB run. Keep CI green as the completion criterion and do not treat an in-flight suite as a pass.

## Further optimization if regional execution is insufficient

PostgreSQL can accept several SQL commands in one submission and return each command's result through its asynchronous result API. This creates a possible transport optimization: send a complete test file while retaining every TAP result, rather than discard all but the last result. [PostgreSQL 17 asynchronous command documentation](https://www.postgresql.org/docs/17/libpq-async.html).

This is a research option, not the first implementation step. ADR-177 explicitly rejected replacing CI with one query per file because it lost pg_prove as the independent check. A replacement transport must retain a trusted TAP parser, preserve all plans, assertions and diagnostics, support required client commands or fall back safely, and prove equivalent failure detection against the current harness. A last-result-only Supabase query or a num_failed-only summary does not meet that bar. Keep each file's BEGIN and ROLLBACK boundaries and do not run lock-conflicting files in parallel on the shared Cloud database.

Benchmark a prototype outside the release path, with independent regression tests for malformed TAP, skipped assertions, SQL errors, connection loss and unfinished transactions. Replacing the established independent runner requires an explicit amendment of ADR-177 before adoption; the current planning request does not enact that amendment.

As the suite grows, introduce test-owner-maintained dependency metadata for focused feedback: changed tables, functions, policies, triggers, shared validators and their consumers. Unknown or incomplete mappings fall back to the full suite. Filename matching alone cannot establish database impact. Moving the full gate to nightly runs would delay discovery of regressions and change the project's assurance policy; it is not required for the performance improvement above.

## Acceptance criteria for the performance work

- The full expected visible and holdout test manifest still runs for a migration push.
- Every file executes its planned assertion count; failures, SQL errors, missing output and timeouts fail the workflow.
- Transactions leave no committed fixture writes and concurrent workflows cannot apply migrations during the suite.
- Deliberately broken harness fixtures produce red results in both old and proposed execution paths.
- Reports show per-file durations, totals and failures, without credentials or personal data.
- A recorded comparison demonstrates the actual performance gain; unchanged or worse performance does not qualify as completion.
- UI-only and types-only skip behavior continues to follow the existing decisions.

The Classes feature plan remains [separate](v2-classes-and-navigation-plan-2026-10-06.md). The owner subsequently approved that narrow feature migration and its CLI-generated types; this performance proposal does not authorize CI changes, paid runner provisioning or a change to the independent test arrangement. Those remain reviewable proposals.
