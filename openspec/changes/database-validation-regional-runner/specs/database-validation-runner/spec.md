## Purpose

Provide complete, independently checked native database validation with trustworthy timing and cleanup while measuring a bounded regional CI execution option.

## ADDED Requirements

### Requirement: DBV-015 Exact owner-configured timeout baseline

WHEN the owner explicitly approves the one-time trial19 configuration action, THE SYSTEM SHALL establish and independently verify present2min only for the fixed failed run37857261809/attempt1/source8072af53493867a093ea128dc306f375d3ca1789/nativejob113584968728/runner39, retain its failed verdict and unknown original, and discharge only its missing-original block after canonical physical closure, official two-worker custody and independent outside review. IF any bound identity, configuration, verification, custody or cleanup proof is incomplete, THE SYSTEM SHALL retain the block. The complete frozen interface is in `trial19-owner-timeout-baseline.md`.

#### Scenario: Owner configuration is verified independently
- **WHEN** the exact approved main CI dispatch sets the fixed baseline and a separate hosted worker freshly verifies it, with accepted official provenance and outside review
- **THEN** a new full run may capture and restore its own original; the old attempt remains failed and no original restoration is fabricated

#### Scenario: Incomplete or wrong authority
- **WHEN** the action, tuple, configured state, outside evidence or physical closure differs or is incomplete
- **THEN** the shared-project recovery block remains and the action cannot be replayed automatically

### Requirement: DBV-001 Exact complete manifest

WHEN a database suite is required, THE SYSTEM SHALL freeze the exact current visible and holdout file manifest, source revision, schema identity, each file's SHA-256 and positive literal assertion plan before execution, and SHALL reject absent suites, duplicate paths, invalid paths, missing or ambiguous plans, unexpected files and changed hashes.

#### Scenario: Complete current revision
- **WHEN** both suites have unique valid files, one literal plan per file and matching source hashes
- **THEN** the manifest includes every discovered supported test file exactly once and the expected assertion total equals the sum of its plans

#### Scenario: Historical count is incomplete
- **WHEN** a manifest omits a later-added file despite matching a historical file count
- **THEN** validation fails before database execution

### Requirement: DBV-002 Retained native authority

WHEN executing the release suite, THE SYSTEM SHALL retain Supabase CLI 2.110.0, the official pg_prove 3.36 client, the full native command, sequential files and the native exit verdict, without replacing transport, parser authority or test bytes.

#### Scenario: Native command fails
- **WHEN** the native process exits nonzero, loses its connection, is interrupted or times out
- **THEN** the attempt fails even if preceding assertions or a partial report appear successful

### Requirement: DBV-003 Verified reporting configuration

WHEN native timing is enabled, THE SYSTEM SHALL install only the approved reporting configuration, preserve original configuration and SQL bytes, retain raw native stdout/stderr privately, and report a duration and native plan/result for every expected file. IF the pinned client has not demonstrably consumed that configuration in an independent client-only smoke, THE SYSTEM SHALL refuse a Cloud benchmark.

#### Scenario: Reporting smoke proves consumption
- **WHEN** an independent native client smoke consumes the approved configuration
- **THEN** its output contains raw TAP and elapsed time per smoke file, and failure fixtures retain their native red verdict

#### Scenario: Missing per-file timer
- **WHEN** a completed file lacks a valid timer or an unapproved configuration flag appears
- **THEN** the attempt cannot satisfy reporting acceptance

### Requirement: DBV-004 Complete evidence before green

WHEN publishing a successful suite receipt, THE SYSTEM SHALL require the native successful exit, complete untruncated stream, exactly one result for every manifest file, matching plans and executed counts, zero assertion failures, matching aggregate totals, unchanged test hashes and verified cleanup. IF any required evidence is absent, duplicated, malformed or inconsistent, THE SYSTEM SHALL fail closed.

#### Scenario: Success-looking truncated stream
- **WHEN** native output is missing a file, plan, completion or aggregate verdict
- **THEN** the receipt is failed regardless of any earlier success marker

### Requirement: DBV-005 Rollback and serialization

WHILE database validation is executing, THE SYSTEM SHALL preserve rollback enforcement for both suites, run only against project pecxrpskmfeuyzngvewq, serialize database workflows through the existing db concurrency group, and prevent overlapping full sweeps, seed operations or migrations. WHEN migrations are required, THE SYSTEM SHALL apply them only through existing CI.

#### Scenario: Transaction guard rejects unsafe input
- **WHEN** an input would commit or lacks its required rollback boundary
- **THEN** validation rejects it before Cloud execution

### Requirement: DBV-006 Original timeout restoration

WHEN the native harness temporarily raises the postgres role-global statement timeout, THE SYSTEM SHALL capture its original presence and exact value, persist a bound recovery receipt before alteration, restore that value or original absence after success or failure, and verify the resulting catalog state. IF capture, receipt persistence, restoration or verification fails, THE SYSTEM SHALL fail the attempt.

#### Scenario: Original setting is absent
- **WHEN** the original role-global timeout entry was absent
- **THEN** cleanup removes only the temporary timeout entry and verifies absence rather than installing an assumed two-minute value

#### Scenario: Native assertion failure
- **WHEN** native execution fails after the timeout alteration
- **THEN** cleanup runs, verifies restoration and retains the native failure verdict

### Requirement: DBV-007 Independent recovery guardian

WHEN a regional attempt is armed, THE SYSTEM SHALL retain a non-secret recovery receipt outside that runner and an independent GitHub-hosted cleanup guardian capable of restoring and verifying the captured timeout after runner loss. IF recovery remains unverified, THE SYSTEM SHALL keep validation failed and prohibit another shared-project sweep or migration until recovery is resolved.

#### Scenario: Regional runner disappears
- **WHEN** the runner is lost after the temporary alteration
- **THEN** the hosted guardian restores from the bound receipt, records verification and leaves the interrupted attempt failed

### Requirement: DBV-008 Trusted one-job execution

WHEN selecting a self-hosted trial, THE SYSTEM SHALL accept only the exact approved main source and owner-authorized CI run, an ephemeral runner with a unique OS-aware run label, and a four-hour maximum registered lifetime. THE SYSTEM SHALL reject PR/fork/untrusted execution, permanent service installation and implicit WSL/Docker setting changes.

#### Scenario: One regional CI job ends
- **WHEN** the assigned job completes or its lifetime expires
- **THEN** the runner is deregistered, its process stops and its dedicated checkout is cleaned only after required receipts and protected logs are retained

#### Scenario: PR requests regional label
- **WHEN** a PR or an untrusted source asks for self-hosted execution
- **THEN** it cannot receive the regional runner or its credentials

### Requirement: DBV-009 Hosted fallback

WHEN regional readiness is unavailable before job selection, THE SYSTEM SHALL use the ordinary GitHub-hosted native path with the same acceptance checks. IF a selected regional job later fails or disappears, THE SYSTEM SHALL record failure and SHALL permit a separate hosted confirmation only after cleanup verification, without overlapping the attempts or relabeling the failed one.

#### Scenario: No regional runner exists
- **WHEN** regional readiness cannot be established
- **THEN** the hosted path remains selectable and missing regional capacity cannot produce a green skipped suite

### Requirement: DBV-010 Matching-input benchmark

WHEN comparing hosted and regional performance, THE SYSTEM SHALL reuse the full hosted native CI already required after the preceding Shop/main migration as baseline, execute the regional trial serially with identical schema identity, test bytes, plans and native execution inputs, record every source/wrapper/version/reporting delta and time-sensitive condition, and report available baseline totals separately from regional per-file/setup/native/job timings. IF schema/test/native execution inputs differ or either run fails, THE SYSTEM SHALL refuse a performance acceptance claim. THE SYSTEM SHALL NOT dispatch a duplicate full hosted baseline solely for this trial or claim that newly added reporting existed in the earlier baseline.

#### Scenario: Same full suite passes on both paths
- **WHEN** comparable complete runs pass
- **THEN** the report gives measured durations and their actual difference without promising an unmeasured five-to-ten-minute result

#### Scenario: Regional result is slower
- **WHEN** regional time is unchanged or worse
- **THEN** full correctness remains reported separately and the performance objective remains incomplete

### Requirement: DBV-011 Failure discrimination before adoption

WHEN adopting reporting or regional routing, THE SYSTEM SHALL first show independent synthetic fixtures remain red for assertion failure, missing/extra plans, malformed/truncated TAP, SQL/client errors after passing assertions, connection loss, timeout, missing files, unchanged-looking totals with incorrect per-file plans, restoration failure and unsafe transaction boundaries.

#### Scenario: Deliberately broken harness input
- **WHEN** an independent fixture models one prohibited failure
- **THEN** both retained hosted and proposed execution/reporting paths refuse a successful verdict

### Requirement: DBV-012 Existing release gates and privacy

WHEN this unit is deployed, THE SYSTEM SHALL preserve drift, ordinary and independent seed proofs, test immutability and ADR-177's UI/types-only skip behavior, and SHALL classify changed harness inputs fail closed for fresh validation. WHEN publishing progress or artifacts, THE SYSTEM SHALL expose only file metadata, counts, timings, verdicts and sanitized diagnostic codes, excluding credentials and personal fixture values from public output.

#### Scenario: Harness implementation changes
- **WHEN** the wrapper, reporting controls, rollback guard or workflow changes
- **THEN** previous native success is insufficient and fresh complete native confirmation is required

### Requirement: DBV-013 Explicit paid alternative

IF the free existing-environment trial cannot satisfy native prerequisites and a paid Mumbai alternative is proposed, THE SYSTEM SHALL require the owner's provider account/access and explicit spending ceiling before provisioning, enforce one instance and its four-hour lifetime, retain off-instance diagnostics and record verified deletion.

#### Scenario: Paid account is unavailable
- **WHEN** no authorized account/access/spending decision exists
- **THEN** no paid resource is created and the hosted native gate remains available

### Requirement: DBV-014 Exact unallocated cancellation

WHEN an original trusted main database attempt is cancelled before its native job and independent guardian are assigned a worker, THE SYSTEM SHALL classify that pair only from complete authenticated original run/job/artifact metadata and a unique independently reviewed kind-tagged proof. THE SYSTEM SHALL require exact source/repository/head repository/run/attempt/job bindings, explicit null worker identities, dense empty steps, compatible unallocated hosted labels, original zero-duration provider cancellation clocks and no conflicting same-attempt custody. IF any worker assignment, executed step, identity ambiguity, missing pair, conflicting custody or incomplete evidence exists, THE SYSTEM SHALL refuse this classification and retain the existing allocated-worker and armed-recovery checks.

#### Scenario: Cancellation materializes jobs with no worker
- **WHEN** the provider completes a reviewed exact never-assigned native/guardian pair after cancellation
- **THEN** preflight records only that absence of execution and permits that exact pair through the worker/no-recovery branches without asserting restoration, physical deletion or native success

#### Scenario: A cancellation follows partial execution
- **WHEN** either job has an assigned worker, an executed step or same-attempt native/recovery custody
- **THEN** the unallocated classifier refuses and the existing teardown/restoration requirements remain in force
