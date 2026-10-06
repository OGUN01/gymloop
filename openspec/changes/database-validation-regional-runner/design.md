## Context

See [proposal.md](proposal.md) for motivation. The accepted historical run is 37486763607: 161 files / 16,156 assertions, native wall 7,788 seconds, job 7,832 seconds. Its input source is 23f5566900b6999e25bcac5e9f39f4e97b95871f and matches the closed f91a7451 execution inputs. A later Shop migration/test revision needs a fresh baseline; never hardcode the historical counts as a completeness criterion.

Current db.yml links the one Mumbai Cloud project and runs both suites after migrate and rollback checks. It changes a persistent role-global timeout to ten minutes and restores an assumed two minutes only after native success. The local sweep is an older envelope-only result reader without an explicit failed-summary exit; it is not the release fallback. Reuse the registered rollback guard and the strict plain-array/legacy-envelope parsing behavior of the seed-result parser. The registry/code search found no reusable native manifest/report/cleanup wrapper.

Current capability receipts: Windows Supabase reports 2.110.0; Windows PowerShell, Node/pnpm/Git/gh and Git sh are available; Docker Desktop's Linux x86_64 server works. Root pulled official `supabase/pg_prove:3.36`, digest `sha256:eda7c5e68719e9c8287e78c017118407b48df904a51c935f5ab6098b8c0bc6bc`, and its `--network host` version probe returned pg_prove 3.36 without a database or settings changes. The official Windows runner archive also passed its published hash check. WSL lacks Node and its Docker integration is disabled. This proves client/image startup, not the still-required independent Windows mount/reporting/failure smoke. No settings will be enabled by this change. The pinned CLI's documented native client uses Docker only for pg_prove, not a database.

## Goals / Non-Goals

**Goals:** freeze one small testable orchestration boundary; measure the retained checker; make incomplete execution and failed cleanup red; and trial exactly one trusted CI job if the existing environment satisfies native prerequisites.

**Non-Goals:** alternative database transport, custom TAP authority, reusable compute autoscaling, a local database, business fixture edits, dependency reinstallations, or a permanent agent on the owner's daily desktop.

## Decisions

### Retain the native command and isolate reporting

The release invocation remains exactly `supabase test db --linked supabase/tests supabase/tests-holdout` with CLI 2.110.0. Its independent checker is the official `supabase/pg_prove:3.36` client. The CLI passes `pg_prove --ext .pg --ext .sql -r` and the two paths, read-only test mounts and host networking. Its Windows conversion strips the drive from container targets while retaining the absolute Windows host bind. Source support is not a successful smoke.

CLI 2.110.0 has no `--timer` passthrough. The client's working directory is the first test directory, which enables an approved generated `supabase/tests/.proverc` containing exactly five lines: `--timer`, `--verbose`, `--parse`, `--nocolor`, `--jobs=1`, each newline-terminated. Runtime generation must reject any pre-existing unapproved configuration, preserve any approved original bytes, and restore/remove its own generated file afterward. SQL hashes before and after must match. No debug, ignore-exit, normalization, state, shuffle, custom formatter/parser or parallel-selection flags are allowed.

Before Cloud benchmarking, an independent client-only smoke must use the pinned official client image, native pg_prove and a stub psql that emits synthetic TAP in a disposable directory. It must prove native `.proverc` consumption, raw TAP, per-file timers, exit discrimination, first-directory mount/cwd behavior, and the platform's required network mode without creating a database or reading project test bodies. The exact Windows CLI mount/network shape must be exercised; inability to prove it leaves the free trial unavailable. The smoke is fixture-only and cannot become the release transport.

### Minimal public harness boundary

Proposed implementation home: `scripts/pgtap/native.mjs`. These exact declarations are review-ready for root's freeze before independent authors start; implementations and registry entries do not exist yet. Keep internal parsing/state private and introduce no generic framework.

| Public entry | Input | Observable output |
| --- | --- | --- |
| `buildNativePgtapManifest(input)` | source/schema identity and discovered `{path, sha256, literalPlans}` records | Validated deterministic manifest, or typed refusal before execution |
| `verifyNativePgtapRun(manifest, evidence)` | complete native stdout/stderr, process status, before/after identities, cleanup receipts | Sanitized receipt; `accepted` is true only when every acceptance condition is met |
| `runNativePgtapValidation(input, ports)` | validated manifest, dedicated checkout, private retention path, run identity/limits and narrow process/files/query/receipt ports | `{evidence, receipt}`; CLI exits nonzero whenever `receipt.accepted` is false |

Use object inputs and named fields, not positional shell strings. The orchestration ports cover source/file inspection, reporting-config custody, typed timeout catalog query/alteration, outside-runner receipt persistence, one native child process, clock, and restoration verification. Tests can substitute these ports without SQL/Cloud access. Command arguments are arrays; no credential-bearing URL, interpolated shell SQL or direct `process.env` reads are introduced. Reuse central environment/config exports and register any new exported symbol/constant before landing.

Freeze the following exact plain-object shapes. All keys listed are required; reject unknown keys, wrong types, duplicate records and coercion. `Sha` means a 64-character lowercase SHA-256 hexadecimal string; `Count` means a nonnegative safe integer; `Ms` means a nonnegative safe integer in milliseconds at native timer precision; `Text` means a nonempty string. `sourceSha` is the repository's 40-character lowercase Git SHA. UTC timestamps use `YYYY-MM-DDTHH:mm:ss.sssZ`.

| Shape | Exact keys and types |
| --- | --- |
| `SchemaIdentity` | `{migrationsSha256: Sha, generatedTypesSha256: Sha}`; bound to the same successful hosted migration/drift receipt, not a caller's guessed current schema |
| `DiscoveredInputs` | `{sourceSha, schemaIdentity: SchemaIdentity, files: [{path: Text, sha256: Sha, literalPlans: [positive safe integer]}]}` |
| `Manifest` | `{formatVersion: 1, sourceSha, schemaIdentity: SchemaIdentity, files: [{path: Text, sha256: Sha, plan: positive safe integer}]}` |
| `OriginalTimeout` | `{originalPresent: boolean, originalValue: Text|null}`; present requires a value, absent requires null |
| `Target` | `{projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout'}` |
| `PrivateOutput` | `{path: Text, sha256: Sha, byteLength: Count}`; path is inside the verified protected retention directory |
| `NativeResult` | `{completed: boolean, exitCode: Count|null, signal: Text|null, stdout: string, stderr: string, elapsedMs: Ms}`; exit and signal cannot both be present; missing completion/status is failure |
| `Timings` | `{setupMs: Ms, linkMs: Ms, nativeMs: Ms, jobMs: Ms}` |
| `TimeoutCleanup` | `{original: OriginalTimeout|null, observed: OriginalTimeout|null, verified: boolean}` |
| `ReportingCleanup` | `{restored: boolean, verified: boolean}` |
| `RecoveryReceipt` | `{formatVersion: 1, runId: Text, sourceSha, manifestSha256: Sha, target: Target, original: OriginalTimeout, capturedAt: UTC timestamp, armed: true}` |
| `Evidence` | `{formatVersion: 1, runId: Text, sourceSha, schemaIdentity: SchemaIdentity, manifestSha256: Sha, native: NativeResult, outputs: {stdout: PrivateOutput|null, stderr: PrivateOutput|null}, afterFiles: [{path: Text, sha256: Sha}], timings: Timings, timeout: TimeoutCleanup, reporting: ReportingCleanup, preflightFailureCodes: [FailureCode]}` |
| `FileResult` | `{path: Text, plan: positive safe integer, executed: Count, failed: Count, verdict: 'PASS'|'FAIL'|'INCOMPLETE', durationMs: Ms|null}`; derived from native raw output, not a supplied green observation |
| `FinalReceipt` | `{formatVersion: 1, runId: Text, sourceSha, schemaIdentity: SchemaIdentity, manifestSha256: Sha, accepted: boolean, native: {completed: boolean, exitCode: Count|null, signal: Text|null}, files: [FileResult], aggregate: {files: Count, tests: Count, failed: Count, verdict: 'PASS'|'FAIL'|'INCOMPLETE'}, timings: Timings, timeout: TimeoutCleanup, reporting: ReportingCleanup, failureCodes: [FailureCode]}`; no raw output, fixture values or private paths |

`buildNativePgtapManifest` receives `DiscoveredInputs` and returns `Manifest`. Include every recursively discovered `.sql` and `.pg` file in both suites, sorted by ordinal normalized repo-relative path; reject absent/empty suites, symlinks/path escape, duplicate paths and ambiguous/comment-only/nonliteral plans. Generic runtime plan discovery may inspect bytes; authors/implementers must not view held assertion bodies. Manifest hashing is SHA-256 of compact UTF-8 JSON plus one LF, with the exact field/key order above, schema keys as above and file keys `path,sha256,plan`.

`verifyNativePgtapRun(manifest, evidence)` returns `FinalReceipt` from the retained native stdout/stderr and process status. Require exactly the expected files/plans/executed tests/timers, the native aggregate PASS, complete retained output hashes, unchanged inputs and verified cleanup. Malformed evidence is red; no external per-file PASS record overrides native output. Raw strings preserve native characters/newlines unchanged and are retained privately as UTF-8 before publishing only the sanitized receipt. An interrupted/failed preflight supplies an incomplete `NativeResult` (`completed:false`, null status, empty streams), empty `afterFiles`, nullable private outputs and unverified cleanup as appropriate; none can pass.

`FailureCode` is exactly one of `MANIFEST_INVALID`, `EVIDENCE_INVALID`, `INPUT_CHANGED`, `REPORTING_UNVERIFIED`, `TIMEOUT_CAPTURE_INVALID`, `RECEIPT_UNAVAILABLE`, `NATIVE_FAILED`, `NATIVE_INCOMPLETE`, `TAP_FAILED`, `TAP_INCOMPLETE`, `HASH_CHANGED`, `TIMEOUT_NOT_RESTORED`, `REPORTING_NOT_RESTORED`, `DEADLINE_EXCEEDED`, `RUNNER_UNTRUSTED`. Receipt code arrays are unique, sorted ordinally; an accepted receipt has an empty array. Invalid manifest input throws an ordinary Error with string property `code:'MANIFEST_INVALID'` before any execution; no extra exported error class is introduced. Invalid evidence produces `EVIDENCE_INVALID` plus any independently ascertainable failures, never throws away cleanup evidence or returns green.

`runNativePgtapValidation` receives exactly `{manifest: Manifest, runId: Text, workdir: Text, retentionDirectory: Text, limits: {deadlineUtc: UTC timestamp, nativeTimeoutMs: positive safe integer}}` and returns `{evidence: Evidence, receipt: FinalReceipt}`. Its exact ports are below. Every port is asynchronous except `now`; asynchronous port rejection becomes the relevant failed receipt and cleanup is still attempted once alteration is armed.

| Port | Exact argument and result |
| --- | --- |
| `collectFiles` | `{workdir}` -> `DiscoveredInputs`; verify bound source/schema/full manifest before and hashes after the native attempt |
| `installReportingConfig` | `{workdir, lines: ['--timer','--verbose','--parse','--nocolor','--jobs=1']}` -> `{path: Text, originalPresent: boolean, originalText: string|null, installedSha256: Sha}`; original presence/value are consistent, only approved original content may be replaced |
| `restoreReportingConfig` | the exact installation result -> `ReportingCleanup`; restore exact original bytes or absence |
| `queryTimeout` | `Target` -> `OriginalTimeout`; capture/verify only that catalog fact |
| `alterTimeout` | `{target: Target, setting: OriginalTimeout}` -> no result; temporary setting is exactly `{originalPresent:true,originalValue:'10min'}`, cleanup uses captured original |
| `persistRecoveryReceipt` | `RecoveryReceipt` -> `{acknowledged:true, sha256:Sha}`; acknowledgement of outside-runner custody is required before alteration |
| `retainPrivateOutput` | `{runId, stream:'stdout'|'stderr', text:string, retentionDirectory}` -> `PrivateOutput`; verify retained content/hash before acceptance |
| `runNativeCli` | `{command:'supabase', args:['test','db','--linked','supabase/tests','supabase/tests-holdout'], cwd:workdir, limits}` -> `NativeResult`; no credentials/SQL/flag overrides or acceptance decision |
| `now` | no argument -> `Ms` epoch milliseconds |

Internal parsing, serialization and adapter details are private; contract tests exercise exact order, arguments, receipts and red outcomes through these ports. CLI/run routing and guardian identity checks have separate synthetic boundary tests; this is not a compute framework.

CLI interface is limited to `manifest`, `run`, `verify`, and `restore` subcommands with named `--manifest`, `--receipt`, `--out-dir`, `--source-sha` arguments as applicable. `restore` is the guardian path: it validates the bound receipt, changes only the captured timeout parameter and verifies exact restoration. No arbitrary query/command override is public. Root freezes all receipt/version/error-code bytes before independent authors start; authors must raise an incomplete declaration rather than change it while other authors are running.

### Restore the catalog fact, not an assumed effective value

Capture only `pg_db_role_setting` for role postgres and `setdatabase = 0`, selecting the statement_timeout entry's presence/value. `SHOW statement_timeout` alone cannot distinguish inheritance from a role-specific setting. Reject duplicate, malformed or missing capture output. Persist the non-secret receipt outside the worker before any alteration and arm cleanup first, since a network error may happen after an ALTER commits.

Retain the existing ten-minute ceiling for this unit. After native success, error or caught termination, restore the captured value with server-side safe literal quoting, or `ALTER ROLE postgres RESET statement_timeout` if it was absent. Preserve unrelated/global/database-specific settings. Verify the same catalog presence/value through a fresh query. Preserve the native nonzero verdict and fail on restoration/verification errors; do not use `|| true`.

Add an independent GitHub-hosted cleanup guardian after the attempt with an always-run path and the bound receipt. It executes no suite/seed/migration; it can link with existing secret names and restore/verify only that role-global setting. A forced workflow cancellation or provider outage can prevent any automatic guardian from running, so unresolved restoration blocks the next shared-project job and requires the retained recovery procedure. Never claim guaranteed recovery from a killed process without a receipt.

### One trusted CI job, hosted default

Only the existing DB workflow's trusted main source may select the one-job trial. Use an exact run-id/attempt/OS-specific label and ephemeral registration, never `self-hosted` alone, a permanent service or a generic queue consumer. Labels alone are not an authorization boundary in this public personal repository: install a runner-local pre-job guard outside the application/checkout directories, bound to the approved repository, workflow/ref, source SHA, run ID and attempt, and reject mismatches before any checkout/workflow step. Independently prove that rejection occurs in the native runner setup phase; otherwise do not register. GitHub's pre-job hook has access to default variables/event metadata and nonzero exit prevents the job running, but no built-in hook timeout; the guard must have its own bound and cannot fetch source from an untrusted checkout. For Windows select the Windows/x64 label, explicit `shell: powershell` for project orchestration, and the verified Git sh required by setup-cli; PATH `bash.exe` is the WSL launcher and cannot stand in for Git Bash. Use a fresh dedicated short checkout outside the interactive workspace.

The selector must finish readiness before choosing `runs-on`; a selected offline runner does not automatically become ubuntu-latest. A pre-selection readiness failure selects hosted execution. Mid-run loss records failure; hosted re-confirmation is a separate serial attempt after timeout restoration is verified. Preserve `db-${github.ref}` / cancel-in-progress false, migrate ordering, seed dependency and all existing release gates. Regional work never applies a migration from the workstation or runs `supabase test db` ad hoc outside the assigned CI job.

The four-hour lifetime starts at runner registration and includes queue/execution time. A hosted watchdog/guardian checks the exact runner/run, stops further assignment by deregistration, verifies teardown and retains the source-bound receipt. Operator teardown stops only this runner process and removes only its verified dedicated checkout. Existing Docker Desktop, WSL state, interactive repo and unrelated containers remain outside teardown. If that narrow teardown cannot be demonstrated, do not register the runner.

### Serial matching-input evidence

Use the single full hosted native run already required after the Shop/main migration as the fresh baseline; do not dispatch a duplicate hosted baseline. Bind its exact schema/source/test bytes/plans and native pins to a metadata manifest without displaying assertion bodies. Once it finishes, conduct the one regional trial serially against that same schema/test manifest. Document any subsequent wrapper/version/reporting deltas explicitly: timing/verbose reporting is observational and cannot be described as already present in the baseline. A changed SQL/schema/native execution input invalidates that pair and its next required full CI becomes the new baseline. The accepted historical run is context, not the fresh comparable baseline. Record UTC/current-time conditions and any observed lock waits separately; do not infer a deadlock cause from speed.

Compare complete native wall time separately from link/client setup, queue and total job time. A valid faster pair is required to complete the performance objective; a failed or slower trial remains useful evidence and keeps hosted routing. No baseline/trial may compete with a local sweep, seed or migration. Generated-types/UI skip behavior stays ADR-177; new harness/config inputs must trigger fresh full confirmation.

## Risks / Trade-offs

- Windows Docker Desktop host networking/mount semantics are unproven -> independent client-only smoke first; keep hosted default and do not enable settings silently.
- Raw verbose TAP may contain fixture details -> retain it in an owner-protected directory; publish only sanitized metadata, durations and failure codes.
- Runner/host loss can strand a role default -> outside-runner recovery receipt, hosted guardian, non-green attempt and explicit next-run block until verified restoration.
- Changing source/schema between runs invalidates timing -> freeze identities and regenerate the full manifest after preceding coherent DB work.
- Regional execution may not remove SQL/lock costs -> report the measured result; no time promise or weakened coverage.
- Public repository runner exposure -> unique main-only run routing, no PR access, no installed service, four-hour deregistration/stop and fresh dedicated checkout.

## Migration Plan

Freeze this contract; author independent visible/held synthetic tests blind and commit them red; implement separately without touching tests; obtain a fresh critic; pass client-only smoke and local gates; land on main as one coherent unit. All changed harness/workflow inputs require fresh complete native CI. Then conduct the controlled pair, retain cleanup/teardown receipts, choose the proven routing and archive. No database migration is introduced by this unit. Roll back runner selection to hosted execution while retaining truthful failed evidence and verified restoration.

## Sources

[Pinned Supabase native client handler](https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/commands/test/db/db.handler.ts), [Windows path conversion](https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/shared/legacy-docker-path.ts), [pg_prove reporting options](https://pgtap.org/pg_prove.html), [GitHub ephemeral runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners), [GitHub pre-job hook behavior](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/run-scripts), [Docker Desktop host network requirements](https://docs.docker.com/engine/network/drivers/host/), [PostgreSQL role setting semantics](https://www.postgresql.org/docs/17/sql-alterrole.html), [pg_db_role_setting](https://www.postgresql.org/docs/17/catalog-pg-db-role-setting.html).
