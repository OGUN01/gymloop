# DBV-008 registration-startup custody declaration

Frozen by root on 7 October 2026 before independent controlled tests or construction. This is the existing approved one-job Windows trial's startup/retirement boundary, not a service, paid provision, alternate database transport or permission to register an arbitrary worker. No real registration begins until independently frozen red tests, implementation, native controlled checks and fresh review pass.

Registry/code search found that the sealed listener launcher/watchdog protects an already registered listener. Its native listener constructor starts only `run --once`, and cannot protect `configure` before a remote row or local `.runner` exists. Reuse its sealed listener/kernel capability and existing limits, but add the minimal independently living configuration custodian below. The original launcher, watchdog, guard and publisher remain sealed and unchanged.

## Private files and exact entries

Protected source under `C:/fr-sealed-20261007/`:

- `registration-custodian-core.psm1` exports only `Invoke-NativeRegistrationCustodian` and `New-NativeRegistrationOwner`.
- `registration-custodian.ps1 -BindingPath <absolute protected admission.json> -BindingSha256 <lowercase SHA256> -ProofDirectory <absolute fresh protected lease directory>` exposes no fixture, executable, API, clock or arbitrary-command override.
- Native owner type is `NativeDbRegistrationCustody.Owner`, with internal `NativeMethods`. Retained original process/thread/job handles and exact named-job membership establish custody; a PID or asserted JSON flag does not.

The production entry fixes repository `OGUN01/gymloop`, approved native `Runner.Listener.exe`, protected roots, actual sealed hashes and the existing approved limits. Independent fixtures import the same two-entry module with controlled ports; they never invoke production configuration or a real API. Root and implementer never read held test bodies or assertion diagnostics.

## Exact records

All records have exactly the listed keys, without extras. `formatVersion` is integer1. Source and byte hashes are lowercase40/64 hexadecimal strings. IDs, attempt, PID and process creation file time are positive canonical decimal strings; attempt is exactly `'1'`. UTC values are nonnegative-epoch, four-digit-year ISO millisecond strings. Paths are absolute, canonical, non-reparse paths within their admitted protected roots. Arrival rejects future registrationUtc and an exhausted cleanup reserve. Deadline derives once from registrationUtc plus sealed maxRunnerLifetimeMs; cleanup begins deadline minus sealed nativeCleanupReserveMs. Wall UTC and elapsed monotonic time enforce the earlier bound; handoff cannot reset or extend it.

Admission:

`{formatVersion,sourceSha,runId,runAttempt,repository,runnerName,runnerLabel,registrationUtc,limitsPath,limitsSha256,runnerDirectory,workDirectory,proofDirectory,listenerExecutablePath,listenerExecutableSha256,wrapperProcessId,wrapperCreationFileTimeUtc,launcherPath,launcherSha256,watchdogPath,watchdogSha256,launchBindingPath,ownershipProofDirectory}`.

Repository is exactly `OGUN01/gymloop`; runnerLabel is the existing exact source/run/attempt-derived Windows label. Wrapper identity is the actual initiating process and creation time. Pre-admitted launch/proof paths permit exact owned-listener shutdown if setup fails before a handoff request appears.

Create-new `configuration-request.json`, exactly once after READY:

`{formatVersion,admissionSha256,sourceSha,runId,runAttempt,runnerName,runnerLabel,registrationToken,registrationTokenExpiresAt}`.

Token has the existing strict safe ASCII shape and unexpired canonical expiry; it remains private and never enters receipts or output. Core constructs only native `configure --unattended --url https://github.com/OGUN01/gymloop --token TOKEN --name NAME --labels LABEL --work WORK --ephemeral --disableupdate`, retaining default system labels. No caller argument array reaches the production entry.

Token is a nonempty string matching exactly `^[A-Za-z0-9_./+=-]+$`, bounded by existing maxProcessBytes. Expiry must be strictly after observed UTC. This boundary adds no invented token-lifetime maximum; production obtains the real provider-issued one-hour registration credential/expiry, while the independent fixed configuration and registration deadlines still apply.

Create-new READY `admission-ready.json`, before any configuration instruction:

`{formatVersion,admissionSha256,sourceSha,runId,runAttempt,runnerName,runnerLabel,registrationUtc,deadlineUtc,cleanupStartsUtc,custodianProcessId,custodianCreationFileTimeUtc,configOwnerJobName,configKillOnClose,baselineExhausted,baselineRunnerIds,verifiedAt}`.

configKillOnClose and baselineExhausted are true only from actual verified facts. Before READY, exhaust runner-list pages with stable totalCount and unique IDs. Any preexisting exact runner name OR unique label refuses admission, including unknown/offline rows. Errors, incomplete pagination or contradiction do not become absence.

Create-new `configuration-result.json`, only after actual original configuration process exit and owned-tree observation:

`{formatVersion,admissionSha256,configurationRequestSha256,sourceSha,runId,runAttempt,runnerName,runnerLabel,configProcessId,configCreationFileTimeUtc,configExecutablePath,configOwnerJobName,assignedBeforeResume,configKillOnClose,configExited,configExitCode,budgetExpired,configProcessesStopped,verifiedAt}`.

The request hash binds exact consumed private request bytes. Process/job identity comes from actual StartConfig evidence; exit/timer facts come from actual Snapshot and owned-tree stop verification. No result is emitted by inferring completion from `.runner` existence or API idle. Wrapper may launch the listener only after exact source/run/admission/request identity, configExited true, actual integer exitCode0, budgetExpired false and configProcessesStopped true, then its existing local config/API checks. Refused/nonzero/timed-out results remain failed. This configuration-only record makes no workload/container claim.

Create-new `watchdog-handoff.json`:

`{formatVersion,admissionSha256,sourceSha,runId,runAttempt,runnerId,runnerName,runnerLabel,configSha256,launchBindingPath,launchBindingSha256,ownershipProofDirectory}`.

Paths match admission exactly. Acceptance requires actual sealed launch/local-config bytes; existing ownership-ready and listener-resumed binding; original live listener PID, creation time, executable and exact kernel-job membership; and live watchdog PID, executable and complete source/run/ID/config command binding. Its original deadline cannot exceed the admission deadline. The production observer retains the verified listener handle and exact owned-kernel control while live, so shutdown remains authorized after watchdog/PID loss. A receipt's own assertion is insufficient. Before accepted handoff, wrapper loss/refusal stops any started admitted listener through that retained capability plus the configuration job. Unreadable or ambiguous started ownership remains unverified. After accepted handoff, ordinary wrapper exit is allowed; independent registration backstop remains alive.

Create-new `handoff-accepted.json`, after actual retained-control handoff verification:

`{formatVersion,admissionSha256,handoffRequestSha256,sourceSha,runId,runAttempt,runnerId,runnerName,runnerLabel,configSha256,launchBindingSha256,deadlineUtc,handoffAccepted,verifiedAt}`.

The request hash binds exact consumed handoff bytes, all identities match that request/admission, original deadline is unchanged, and handoffAccepted is true only after genuine observer verification and a successful protected acknowledgment write. Wrapper waits for this exact acknowledgment before normal exit or readiness publication. Request-file existence is insufficient. Missing/mismatched/unwritten acknowledgment preserves setup-failure custody; an acknowledgment-write failure must stop admitted listener/configuration and remain failed (`ACKNOWLEDGMENT_UNVERIFIED`), never release wrapper-loss monitoring.

Create-new final `admission-final.json`, only when the backstop ends:

`{formatVersion,admissionSha256,sourceSha,runId,runAttempt,runnerName,runnerLabel,registrationUtc,deadlineUtc,learnedRunnerId,handoffAccepted,configTerminationRequested,configProcessesStopped,runnerDeregistered,readinessState,physicalTeardownVerified,status,stopReason,verifiedAt}`.

learnedRunnerId is null or a positive canonical decimal string; flags are strict booleans. physicalTeardownVerified is always false in this config-only record. readinessState is `absent`, `matching-removed`, `unrelated-preserved` or `unverified`; status is `ADMISSION_REFUSED`, `RETIRED` or `RETIREMENT_UNVERIFIED`. stopReason is `BASELINE_CONFLICT`, `BASELINE_UNVERIFIED`, `REQUEST_INVALID`, `REQUEST_TIMEOUT`, `CONFIG_REFUSED`, `CONFIG_TIMEOUT`, `WRAPPER_LOST`, `WATCHDOG_LOST`, `BOUND_ROW_AMBIGUOUS`, `ACKNOWLEDGMENT_UNVERIFIED`, `DEADLINE` or `FULL_JOB_FINAL`. The core returns the same final record it emits through WriteReceipt; tests may inspect captured receipts alone. A baseline refusal starts no configuration and performs no remote deletion; an uncertain baseline does not claim registration absence.

Early404 never ends failure/late-creation monitoring. Retain the backstop through the original deadline unless the existing watchdog supplies genuinely verified full-job/kernel/container/registration final evidence. A configuration-only record cannot certify workload/container teardown. API uncertainty, contradictory registration identity or unverified retirement remains failed and blocks another shared-project attempt.

## Test-facing module interface

`Invoke-NativeRegistrationCustodian -Admission <exact parsed record> -AdmissionSha256 <actual raw-byte SHA> -Ports <exact hashtable>` accepts exactly these scriptblock ports:

| Port | Exact result / responsibility |
| --- | --- |
| `Clock()` | `{utc,monotonicMs}`; canonical UTC and nonnegative monotonic integer |
| `Wait(milliseconds)` | Controlled waiting; no system clock change |
| `WrapperAlive(pid,creationFileTimeUtc)` | Strict boolean for the original bound process |
| `ListRunners(page)` | `{totalCount,runners}`; sequential positive pages exhausted through terminal empty page, stable nonnegative total and no duplicate IDs |
| `GetRunner(id)` | `{status:200\|404,runner:null\|runner}`; failures throw rather than become404 |
| `DeleteRunner(id)` | Actual HTTP status; a fresh exact identity observation precedes narrow deletion and a fresh404 proves absence |
| `ReadConfigurationRequest()` | Null or raw UTF8 bytes; exactly one admitted request, never output token |
| `ObserveHandoff()` | Null or `{request:<raw UTF8 bytes>,verified:boolean,watchdogAlive:boolean,fullJobFinalVerified:boolean}`; production performs the actual retained-handle/sealed/kernel checks above |
| `StopAdmittedListener()` | `{terminationRequested:boolean}`; production uses only retained exact original-handle/kernel capability, or false if no listener started; ambiguous started custody throws |
| `RemoveOwnReadiness(id,sourceSha,runId,attempt)` | Exact readinessState enum; unrelated authority remains untouched |
| `WriteReceipt(name,record)` | Only admission-ready.json, configuration-result.json, handoff-accepted.json and admission-final.json; protected create-new writes |
| `NewOwner(admission)` | Actual native owner below; configuration is suspended and kernel-owned before first instruction |

Each runner is exactly `{id,name,os,status,busy,labels}` with labels exactly `{name,type}` records. Discovery requires one new exact name AND unique label AND existing default read-only `self-hosted`, `Windows`, `X64` labels. Windows is ordinary; unknown OS is allowed only offline and idle. Missing/default/custom-label confusion, ambiguity, preexisting baseline IDs or a different subsequent exact ID cannot be adopted. Freeze the first exact positive ID; always reassert identity before DELETE. Unrelated/rebound IDs survive.

Provider-projected runner.id and baselineRunnerIds are positive canonical decimal strings. Production converts the actual integral provider ID exactly, without floating-point or coercive malformed-ID acceptance; GET/DELETE ports take the same canonical string. totalCount/page counts are nonnegative integers and pages are positive integers. name and os are nonempty strings; status is `online` or `offline`, busy is strict boolean, and label.type is `read-only` or `custom`. Baseline can include unrelated Linux/other OS rows; discovery applies the narrower Windows/unknown predicate above. Request/handoff/receipt records accept ordinary JSON note-property records or ordinary dictionaries with exactly their fields; script-property/getter values cannot establish facts.

Limits are the exact complete NATIVE_DB_VALIDATION snapshot already protected in watchdog-limits.json, with keys: `formatVersion,sourceShaLength,digestHexLength,labelShaLength,projectRef,role,parameter,reportingLines,temporaryTimeout,nativeCommand,nativeArgs,cliVersion,clientImage,clientDigest,maxRunnerLifetimeMs,repository,mainRef,workflowRef,labelPrefix,runnerOs,job,processStopGraceMs,nativeCleanupReserveMs,artifactRetentionDays,privateDirectoryMode,privateFileMode,timeoutQueryMaxBytes,maxProcessBytes,encryptedOutputMagic,permissionMask,readinessMaxAgeMs,smokeExecutableMode,nativeClientImage,artifactMetadataStatus,artifactRedirectStatus,artifactUnixModeShiftBits,hookArgumentCount,maxRunnerLifetimeMinutes,guardProbeTimeoutMinutes,legacyBaselineRunId,legacyBaselineSourceSha,millisecondsPerSecond`. Production independently requires the unchanged approved sealed snapshot and actual hash. Imported fixture callers may create/hash a copied snapshot shortening only maxRunnerLifetimeMs, nativeCleanupReserveMs and processStopGraceMs, with positive integer grace no greater than cleanup reserve and cleanup reserve shorter than lifetime. All other pins/shape/values remain unchanged. No production CLI override admits fixture limits. Default fixture ModulePath is `C:/fr-sealed-20261007/registration-custodian-core.psm1`.

`New-NativeRegistrationOwner -ExecutablePath <path> -ExecutableSha256 <sha> -WorkingDirectory <path>` returns an owner with immutable readonly `OwnerJobName` available before READY and exactly these methods:

- `StartConfig(arguments,budgetMs)` returns `{pid,creationFileTimeUtc,executablePath,ownerJobName,assignedBeforeResume:true,killOnClose:true}` only after creating suspended, retaining original handles, assigning/verifying exact private kill-on-close job membership and resuming. Assignment failure stops the original suspended process. No breakaway or inherited job handles. Its own real monotonic timer enforces the budget independently of the orchestration or a blocked API port.
- `Snapshot()` returns `{activeProcessCount,processes,configExited,configExitCode,budgetExpired}`; processes are `{pid,creationFileTimeUtc,executablePath}`. Actual exit code is null until exit and an integer afterward; budgetExpired becomes true only from the native monotonic timeout path.
- `Stop(stopGraceMs)` returns `{terminationRequested,processesStopped}` from actual owned-job facts.
- `Dispose()` closes the kill-on-close job. Timer, stop and disposal serialize access to retained original handles; no disposed or reused handle can be targeted.

Production owner budget is sealed nativeCleanupReserveMs. Each production API child is bounded by the smaller of sealed processStopGraceMs and remaining conservative cleanup/deadline budget. No unbounded child or a loop-only configuration timeout is acceptable. Fixtures shorten only explicit imported clock/limits/owner-budget inputs, using the same control paths; the production CLI exposes none of those overrides.

## Independent red groups

Visible and held authors independently cover: complete paginated name-OR-label absence admission; genuine first-instruction exact named-job ownership/descendant stop/root loss with an unrelated sentinel; configuration failure/timeout and partial/late remote registration without `.runner`; exact new API-ID/default-label/unknown-OS/ambiguity discovery; real owned handoff plus normal wrapper exit/watchdog loss/no deadline extension; and stop-before-delete/fresh404/matching-readiness-only/API uncertainty/truthful final claims. Provider fixtures are no-network recorders. Native fixtures are harmless compiled probes with no credentials. Root never inspects held bodies or diagnostics. Fresh source-only review and actual controlled native/process results precede production admission.

Mechanical acknowledgment declaration, 7 October before acknowledgment construction: configuration-result and handoff-accepted explicitly communicate the already-frozen actual completion/acceptance states to the separate wrapper. Original authors append small independent red transport-binding regressions before these writes/consumer behavior are implemented; parent test assertions remain unchanged. These records introduce no port/export/limit/authorization relaxation.
