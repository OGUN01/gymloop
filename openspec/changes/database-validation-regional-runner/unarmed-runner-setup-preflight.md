# Exact unarmed runner-setup failure — frozen before independent tests

Actual automatic main DB37838137505/1/866854605f06c6f5f5c0484a0f53de19c9d97690 failed recovery preflight before any mutation, selection or worker. Its operator correctly refused the already completed target, before arming or registration. Do not retry that operator or relabel this as a benchmark. Original trial17 sources/startup/failed provider records remain retained; no runtime registration or physical lifetime began.

The specific prior obstruction is DB37822050096/1/db8715c0f5e20b34f753652cc01b0b4d94566872: Windows native job113466344205 failed `Set up runner` before checkout; the hosted guardian113466555344 failed `Find the exact armed receipt, including an earlier attempt of this run` before database link/restore. No recovery could have been armed. Its positive allocated physical teardown was independently accepted and published once in the unchanged outside index. Current preflight correctly accepts that physical proof, then incorrectly treats the guardian's non-database receipt search as armed execution. DBV-006/007 require recovery after actual arming, not a fabricated receipt for this exact proven pre-arming failure. This repair preserves those requirements; it does not claim restoration or native success.

## Frozen pure interface and fail-closed contract

Register then implement `verifyUnarmedNativeSetupFailure(input)` in scripts/pgtap/unarmed-setup-failure.mjs. Return boolean only, false on any malformed, ambiguous or unsafe input, including accessors, sparse arrays, inherited/extra keys or exceptions. Reuse exactNativeDataRecord, exactNativeDataArray, NATIVE_DB_VALIDATION and the unchanged verifyNativeWorkloadTeardown. Existing hosted-smoke and never-assigned cancellation classifiers stay unchanged.

Input has exactly run, nativeJobs, guardianJobs, artifactNames, jobListingComplete, artifactListingComplete, teardownReview. Both listing flags must be literal true. Each jobs array is dense and has exactly one original projected job. Run has exactly id, attempt, sourceSha, repositoryId, repository, headRepositoryId, headRepository, event, path, branch, status, conclusion. Require positive safe decimal id, attempt '1', valid lowercase40-byte source, matching positive repository ids, both repository names OGUN01/gymloop, event push/workflow_dispatch, path .github/workflows/db.yml, main branch, completed/failure. No cancellation or rerun exemption is added.

teardownReview is directly the existing eleven-field canonical receipt, not a wrapper: formatVersion, runId, sourceSha, jobId, runnerId, runnerEnvironment, privateProofSha256, nativeProcessesStopped, ownedContainersStopped, runnerDeregistered, verifiedAt. Its runId is id-1 and jobId is the native job's decimal string. Use the existing central labelPrefix and labelShaLength (12) properties for the source-prefix label; independent authors may import registered NATIVE_DB_VALIDATION constants without reading implementation or another suite. Fixture metadata derives from this contract only.

Each job has exactly id, runId, attempt, sourceSha, name, status, conclusion, runnerId, runnerName, runnerGroupName, labels, steps, matching run and distinct positive safe job/runner ids. Native must be completed/failure/pgtap, Default runner group, nonempty runner name and exactly the four unique labels self-hosted/Windows/X64 plus NATIVE_DB_VALIDATION.labelPrefix-runId-1-sourcePrefix (order independent). Guardian must be completed/failure/timeout-guardian, GitHub Actions group, exact GitHub Actions runner-id name and sole ubuntu-latest label. Teardown review must pass the unchanged canonical verifier against native source/run-attempt/job/runner/self-hosted; all three physical flags and original proof/identity checks remain mandatory.

Artifact names are a complete dense array containing exactly native-db-schema-id-1 and native-db-ci-job-id-1 once each. Any recovery, final, smoke, manifest, timing, private-custody, restoration, unexpected, duplicate or ambiguous artifact refuses. No expired/partial artifact list can grant this exemption; the caller must retain its authenticated complete listing checks.

Steps are exact dense ordered vectors of three-field records {name,status,conclusion}, status completed throughout. No unknown, missing, duplicate, reordered, executing, cancelled or unexpected successful step is accepted. The public provider vectors below are the contract reference, not implementation or private assertions.

Native vector:
1. Set up job / success
2. Set up runner / failure
3. Record adapter setup start before checkout / skipped
4. Record hosted adapter setup start before checkout / skipped
5. Run actions/checkout@v7 / skipped
6. Run pnpm/action-setup@v6 / skipped
7. Run actions/setup-node@v7 / skipped
8. Install the frozen adapter dependencies / skipped
9. Install the frozen hosted adapter dependencies / skipped
10. Use the verified Git Bash executable for the pinned CLI installer / skipped
11. Run supabase/setup-cli@v3 / skipped
12. Run actions/download-artifact@v5 / skipped
13. Freeze full rollback-safe file and schema metadata / skipped
14. Run actions/upload-artifact@v5 / skipped
15. Validate the full native suite with outside-worker recovery custody / skipped
16. Retain sanitized native receipt / success
17. Retain client-only smoke metadata / success
18. Retain the explicit interim timing boundary / success
19. Retain sanitized encrypted-artifact custody verification / success
20. Complete job / success

Guardian vector:
1. Set up job / success
2. Run actions/checkout@v7 / success
3. Run pnpm/action-setup@v6 / success
4. Run actions/setup-node@v7 / success
5. Run pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts / success
6. Run supabase/setup-cli@v3 / success
7. Find the exact armed receipt, including an earlier attempt of this run / failure
8. Run actions/download-artifact@v5 / skipped
9. Run actions/download-artifact@v5 / skipped
10. Run supabase link --project-ref "$PROJECT_REF" --yes / skipped
11. Restore and freshly verify only the captured role-global timeout / skipped
12. Retain independently hosted restoration evidence / skipped
13. Post Run supabase/setup-cli@v3 / success
14. Post Run actions/setup-node@v7 / skipped
15. Post Run pnpm/action-setup@v6 / success
16. Post Run actions/checkout@v7 / success
17. Complete job / success

## Workflow wiring and tests first

Both independent authors receive only this frozen contract and registry; neither reads implementation or the other suite. Visible tests scripts/__tests__/native-unarmed-setup-failure.test.ts; held tests supabase/tests-holdout/native-unarmed-setup-failure.holdout.test.ts. Include acceptance plus hostile shape/identity/label/receipt/list/step mutations, especially attempted native work, attempted guardian link/restore, incomplete custody and missing physical teardown. Independently test actual workflow import/use, filters and the narrow guardian-only exception. Commit authored tests red before production; implementer never reads held bodies or edits either suite. Retain actual failed CI and all original fixtures/caps.

Workflow adds exact module paths to both event filters (existing internal scripts/pgtap/ classifier already includes it), imports the verifier and maintains a separate verifiedSetupFailures set. For a previous completed failure with no recovery, get authenticated exact attempt/complete job/artifact listings and project the complete native/guardian arrays with the existing projectUnarmedJob. Exactly one indexed physical receipt must satisfy the new verifier. Record ONLY that exact guardian run-attempt-job key. The original native worker loop still requires its existing positive physical proof. Only the final no-recovery guardian branch additionally recognizes that exact set key. Armed artifacts, unknown/partial execution, source ambiguity or incomplete evidence retain the existing block. Do not change guardian execution, recovery persistence/restore algorithms, old classifiers, DB assertions, timeouts or canonical teardown.

Require independent fresh source critic, targeted authored tests/lint, registry/escape-hatch/rollback/immutability/shared types and exact-head CI. The actual prior pair must pass the unchanged-author classifier through the genuine hosted preflight before a new full trial. No provider index mutation or fabricated recovery is included. A separately saved fresh admission plan must bind the final new HEAD/run and consumed operator; unconsumed protected runner material may be reused only after explicit fresh-state verification. No duplicate hosted baseline or sweep.
