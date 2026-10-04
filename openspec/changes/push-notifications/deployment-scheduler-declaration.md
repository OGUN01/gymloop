# NTF deployment and scheduler mechanics — frozen mechanical declaration

2026-10-04. This document completes the already owner-approved transport;
it is not an activation instruction or evidence of Cloud state. The coordinator
has frozen these mechanics before independent infrastructure test authors start.
Read with proposal.md, transport-amendment.md, pre-configuration-amendment.md,
serial-tenancy-and-edge-mechanics.md, readiness-and-oauth-declaration.md,
firebase-provisioning-packet.md, native-firebase-declaration.md and
../v2-batch2-shared/wave-c-serial-freeze-declarations.md. Later frozen mechanics
take precedence over superseded proposed signatures. Existing push SQL and
adapter contracts remain unchanged. WSP acquires no scheduler or activation.

## Inert forward migration and exact private boundary

- **PSD-001.** Add `20261005130000_push_scheduler.sql` after the existing
  pending core migrations;
  never rewrite `20261004090000_push_delivery.sql`. CI alone applies it after
  the previous DB run settles. Declare supported `pg_net` and `supabase_vault`
  extensions using their platform-supported schemas. Existing `pg_cron` is
  reused. The migration creates no cron job, configuration row or Vault secret,
  reads no decrypted secret and performs no network/provider operation.

  Factual correction (2026-10-04, runtime evidence against the linked Cloud
  project): the live platform has pg_cron in schema `pg_catalog` (precedent
  migration 20260909170000 creates it with no schema clause), supabase_vault
  in `vault`, and `pg_net` NOT installed. The migration therefore declares
  `pg_net with schema extensions` (repo precedent), verifies the actual
  extension locations with a named refusal guard that runs BEFORE any
  create-extension statement, and scopes every custody ACL to the real
  schemas (`pg_catalog` for cron objects, scoped to exactly the named cron
  tables/functions). The earlier "both pre-exist in net/vault" expectation is
  superseded by this note; no owner decision is required — this is measured
  platform fact, not scope.
- **PSD-002.** Declare `app.run_push_dispatch_tick() returns jsonb`, VOLATILE,
  SECURITY DEFINER, owner postgres, `search_path=''`. Revoke effective EXECUTE
  from PUBLIC, anon, authenticated and service_role. No public facade. The only
  scheduler command is `select app.run_push_dispatch_tick();`, executed by the
  trusted postgres cron owner. Use fully qualified objects and a transaction
  advisory try-lock keyed by the fixed job name. Lock contention is an inert
  skipped tick; no secret access or HTTP request.
- **PSD-003.** Driver eligibility comes from tenant-keyed
  `public.push_provider_configurations` and `app.push_configuration_ready(uuid)`;
  never from HTTP input. An empty eligible set returns zero counts without
  reading Vault, creating attempts or touching network. For each selected tenant
  call the existing `app.run_push_events(uuid)` once; this private function
  remains the source/event/audience authority. Do not duplicate its predicates,
  invoke the broad no-show scan, reserve attempts or call FCM from SQL.
- **PSD-004.** Bound each tick to 100 tenants and one HTTP wakeup. Select eligible
  UUIDs in ascending order, cyclically from offset
  `(floor(epoch(statement_timestamp()) / 60) * 100) modulo eligible_count`,
  taking `min(100,eligible_count)` distinct rows and wrapping once. Use the same
  statement-time configuration snapshot for count and selection. No unbounded
  tenant loop, persistent global cursor/table or all-tenant activation. Each
  existing event runner retains its frozen internal batch bounds. Failures roll
  back the tick; do not enqueue after an event-runner error. This fairness bound
  is operational, not an event/member budget or delivery-time guarantee.
- **PSD-005.** After eligible event work, read exactly one nonblank Vault entry
  named `gymloop_push_dispatch_secret`. Missing/duplicate/blank entry refuses
  wakeup with a value-free operational error; never substitute a service key.
  Enqueue exactly one `net.http_post` to
  `https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch`, body
  `{}`, headers `Content-Type: application/json` and
  `x-gymloop-push-dispatch-secret: <decrypted dedicated value>`, timeout 5000 ms.
  No authorization JWT, recipient, tenant selector, query string or redirecting
  endpoint. A queued request is only a wakeup, not acceptance or receipt.
- **PSD-006.** Driver result is exactly
  `{tenantsProcessed,announcementEvents,pushChildren,classReminders,absenceEvents,wakeupsQueued,skipped}`.
  Counts are nonnegative integers; tenant count is at most 100, wakeup count
  at most one; skipped is boolean. Aggregate the existing runner's four count
  keys. Return no request id, tenant/member id, token, headers, credential,
  provider id or raw exception. Do not persist transient HTTP contents in audit
  or application tables. No new member-facing operational reader is authorized.

## Extension custody and verification

- **PSD-007.** Explicitly deny PUBLIC/anon/authenticated/service_role effective
  access to Vault plaintext/decryption and secret mutation functions, and to
  `net` queue/header/response inspection and HTTP enqueue functions. Enumerate
  installed extension objects and test effective table, column, function,
  schema and inherited privileges rather than relying on schema non-exposure.
  Retain only extension-internal execution privileges actually required by the
  trusted driver/worker. No ordinary caller may execute cron scheduling or this
  driver. Existing unrelated schedules must remain operational.
- **PSD-008.** Treat protected SQL owners and infrastructure custodians as
  privileged; Vault does not encrypt transient queued headers. No migration,
  repository file, log, audit, result, screenshot, artifact or cron text may
  contain a raw secret. A private ephemeral provisioning SQL file is permitted
  only under PSD-017 below; it is never a migration or retained artifact.
  Queue/header capture is prohibited even during debugging.

## Dedicated protected deployment protocol

- **PSD-009.** Add `.github/workflows/push-deploy.yml`, manually dispatched,
  contents:read plus the minimum read permission needed to verify Actions gates,
  protected environment `production-push`, main-only, concurrency group
  `push-production` with cancel-in-progress false. Inputs:
  `expected_commit` (required full 40-character lowercase SHA), `operation`
  (`deploy`, `activate`, `pause`, `rotate-wakeup`, `rotate-firebase`), and
  `tenant_ids` (required nonempty explicit JSON UUID array for activate only;
  unique entries, max 100; no default, wildcard, discovery or all-tenant switch).
  Other operations reject nonempty tenant_ids. An input is reviewable operator
  intent, not proof of authorization or readiness.
- **PSD-010.** Before secret access/mutation, check repository OGUN01/gymloop,
  ref main, checkout SHA == expected_commit == current remote main head and
  approved Supabase project `pecxrpskmfeuyzngvewq`. Fail stale head rather than
  silently deploying a later revision. Require completed successful exact-SHA
  CI `gates` and `deno-check`, current schema-drift and applicable independent
  holdout workflow checks. Require successful full DB migrate/seed-dry-run/pgtap
  and pgtap-rollback evidence from expected_commit or a main ancestor whose
  exact Git-tree SQL/gate inputs match expected_commit, as PSD-019 pins. Full
  visible+held SQL invariant suites must actually have run: a path-filter skip
  never becomes full-suite evidence. All earlier main DB runs must be settled;
  no overlapping migration/provisioning. Missing, cancelled, skipped, stale or
  ambiguous evidence refuses. Recheck head/gates immediately before mutation
  and activation. Do not weaken existing CI or make push deployment automatic.
- **PSD-011.** `deploy` first guarantees no new dispatch (pause protocol below),
  then provisions existing protected `PUSH_DISPATCH_SECRET`, `FCM_PROJECT_ID`
  and `FCM_SERVICE_ACCOUNT_JSON` into exact-project Edge using Supabase CLI.
  Bind Firebase project `samuraiapi-51996` and sender
  `fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com`; validate names
  and identities without printing private JSON. Runtime Supabase service
  credential stays in Edge. Only the wakeup value goes into restricted Vault;
  FCM JSON never does. Use ephemeral owner-only files/streams, no shell tracing,
  command-line secret literal or uploaded credential artifact. Vault provisioning
  uses only PSD-017's private ephemeral SQL file through the correctly linked
  Supabase CLI, never another PostgreSQL transport or SDK. Provision only
  approved names; no project, app, key or grant creation.
- **PSD-012.** Configure `[functions.push-dispatch] verify_jwt=false` only for
  this function, retaining its dedicated-secret authentication. Deploy only
  `push-dispatch` at the exact checked SHA with reviewed Deno import-map/runtime
  settings. Do not change JWT verification for other functions or extend the
  ordinary `functions.yml` automatic deploy boundary. Verify function identity,
  deployed source/version binding, JWT setting, approved environment names and
  credential/project binding. Name presence alone is insufficient value proof.
  No recipient-send smoke test is implicit in deployment verification.
- **PSD-013.** `deploy` ends paused. Separate protected `activate` occurs only
  after exact deployment/configuration verification and PSD-010/019 gates.
  Verify native identity/configuration code gates; physical acceptance remains
  separate. In one trusted SQL transaction validate every explicit tenant exists,
  reject conflicts or differently-bound rows, insert only missing selected rows
  with firebase_project_id `samuraiapi-51996` and activated_at equal to server
  transaction time, preserve existing activation cutoffs on inert replay, and
  finally schedule exactly one postgres job `push-dispatch-minute` with
  `* * * * *` and the private driver command. Existing valid job is inert replay;
  a same-name job with another owner/schedule/command is a refusal. Do not
  overwrite existing activated_at or activate unselected tenants. No secret
  read/provider request occurs in this transaction. Scheduler enablement is last.

## Pause, rotation and count-only operations

- **PSD-014.** Pause unschedules only `push-dispatch-minute` and removes the
  Edge wakeup secret so newly arriving invocations fail closed. Preserve tenant
  activation cutoffs and existing notification/attempt facts. Removing the secret
  does not cancel already-running invocations; wait for their bounded completion
  and the existing 90-second reservation window, classify started unfinished
  work under the frozen unknown-outcome rule, and verify no remaining in-flight
  work before rotation/resume. Do not clear io_started_at or retry uncertainty.
  If quiescence cannot be demonstrated, remain paused. No new broad SQL mutation
  facade or provider resend is authorized by this protocol.
- **PSD-015.** Wakeup rotation pauses first, replaces the one protected
  GitHub/Edge/Vault value, verifies old-value rejection and new-value matching
  without starting recipient work, then separately resumes only after all checks.
  No dual-secret grace period. Firebase rotation pauses, verifies the approved
  replacement identity/OAuth, accounts for previously issued access-token
  validity, revokes the retired key and discards cached tokens before resuming.
  Key creation/revocation remains an explicitly reviewed provisioning action;
  this declaration does not authorize CI to broaden Google IAM permissions.
- **PSD-016.** Operational receipts contain commit, project/function identity,
  operation, UTC timestamps, gate/version references, selected-tenant count,
  configuration-check outcomes, cron job count and driver/Edge factual counts.
  They never claim delivery from wakeup/FCM acceptance, expose secrets/header
  values or fabricate live evidence. Protected operators may inspect sanitized
  extension outcomes without exporting raw response/queue records. Lost queue
  wakeup drains on later ticks; durable attempts still prohibit blind resend.

## Registry/decision proposals and independent test dependencies

Before source work, register `app.run_push_dispatch_tick()` and the protected
workflow, private extension custody boundary, Vault name and approved cron job.
Record why the existing SQL-only scheduler cannot perform HTTP transport and
why existing media/functions deploy workflows do not satisfy exact-SHA gates.
Add shared named operational constants for tenant tick/activation input limit
100, tick interval 60 seconds, wakeup timeout 5000 ms and job/Vault names;
reuse PUSH_RESERVATION_SECONDS and existing approved endpoint/project constants.
SQL mirrored bounds require consistency proof; add no handwritten status enum,
shared platform import or generated-type edit. Two narrowly scoped private
application helpers keep provider-free verification away from extension internals:
`app.read_push_dispatch_secret() returns text` implements the exact one/nonblank
Vault lookup, and `app.enqueue_push_dispatch_wakeup(p_secret text) returns void`
implements the fixed HTTP request. Both are VOLATILE SECURITY DEFINER,
postgres-owned, `search_path=''`, with effective EXECUTE revoked from PUBLIC,
anon, authenticated and service_role. They are reachable only from the trusted
driver; neither is an ordinary RPC or operational reader. Activation/pause stay
reviewed protected operator statements, with no additional public SQL facade.

Tests may replace only these private application functions transactionally with
synthetic secret/queue implementations, and may narrow the existing private
readiness predicate to their isolated fixture tenants. They must restore all
changes by ROLLBACK, never read a real decrypted credential or enqueue a real
HTTP request, and never mutate extension functions or grant ordinary access.
Extension custody tests inspect actual installed effective ACL metadata. The
production helper definitions still require separate fixed-request/secret-lookup
verification against the frozen declaration; a synthetic seam passing alone
does not prove production transport correctness.

Tests are independently authored from this frozen packet, first committed red;
visible and held authors do not read one another or implementation. SQL tests
are BEGIN/ROLLBACK and provider-free. Required cases: inert extension migration;
effective role/inherited/column ACL denial; zero Vault/network work unconfigured;
lock overlap; mixed tenant readiness and deterministic bounded wrap; exact
runner delegation/count aggregation; missing/duplicate/blank secret; fixed
URL/headers/body/timeout and one enqueue; event failure rollback; tenant
activation atomic rejection/replay/cutoff preservation; unique cron owner/text;
no new WSP schedule. Injected queue/Vault seams must not grant ordinary access
or enqueue external work in SQL tests. Workflow tests use synthetic gate metadata
and fake CLI/network boundaries to cover stale SHA, skipped suites, pending DB,
ref/environment/identity mistakes, mutation ordering, paused deploy, activation
last, secret nondisclosure and failure cleanup. Static checks alone cannot prove
deployed identity, provider credential matching, actual scheduler execution or
physical receipt/open; those remain separate protected operational/live gates.

## Resolved mechanical algorithms and genuine execution caveats

- **PSD-017 (CLI Vault provisioning).** Supabase CLI 2.110.0 has no query bind
  parameter flag. Use a private temporary directory outside checkout, umask 077,
  files mode 0600 and cleanup trap covering success/failure/signals. Validate the
  owner-protected wakeup as nonblank high-entropy configuration; never generate
  or substitute a new value in deployment. Write one ephemeral transaction with
  `SET LOCAL standard_conforming_strings=on`; represent strings using ordinary
  single-quoted SQL literals with every single quote doubled, rejecting NUL.
  Avoid dollar-quote delimiter construction and shell interpolation. Lock and
  require zero or one existing named Vault entry; use supported Vault create or
  update function only for that name, never disclose returned decrypted values.
  Call `supabase db query --linked --file <private-path>` after exact linked-ref
  check. Capture stdout AND stderr in private ephemeral buffers; on failure emit
  only a fixed value-free failure, never echo SQL or CLI diagnostics. No tracing,
  literal argv, uploads, receipt hash or retained file. Confirm production SQL
  logging does not persist sensitive provisioning statements/parameters before
  this operation; inability to establish that condition refuses provisioning.
- **PSD-018 (non-sending configuration proof).** From protected CI send the
  intended wakeup header with deliberately invalid extra-field JSON body, for
  example `{verification:true}`; the frozen auth-before-body handler must return
  HTTP400 bad_request with zero counts/null configuration. A wrong secret must
  return HTTP401 unauthorized with the same zero/null facts. Both stop before
  DB/provider I/O. HTTP401 is the existing frozen mapping; do not change it to
  403. Paused/missing-secret state returns the existing HTTP503 configuration
  refusal. Header values and full request logs are never displayed. Verify Vault
  has exactly one named secret and its digest equals the intended protected value
  within trusted SQL, using PSD-017 transport and boolean-only output. Do not
  emit either digest. No readiness endpoint, new adapter export or recipient
  invocation is needed. This proves the wakeup value/auth boundary; FCM binding
  still needs protected identity parsing and the separately approved non-sending
  OAuth verification, whose private request/response remain unlogged.
- **PSD-019 (actual full-suite ancestor).** Fetch complete main ancestry and
  completed Actions metadata. Find a successful main DB run whose pgTAP and
  rollback checks actually executed visible+held suites, with migrate and seed
  proof successful. Its head must equal expected_commit or be an ancestor. For
  ancestor evidence require identical tree entries (path, mode and blob SHA) for
  all `supabase/`, all `packages/db/` excluding `packages/db/types/`, `scripts/`,
  `.github/workflows/`, root package manifests/lockfile and gate configuration
  files. Conservatively include shared configuration/constants imported by SQL
  consistency gates. Unknown/missing inputs refuse reuse. Generated-types-only
  differences are allowed under ADR-177 only with successful expected_commit
  schema-drift; current full CI/Deno and any independent holdout checks still
  must pass. No skipped-suite result supplies full-suite evidence. If no matching
  ancestor exists, a real full DB run is required before activation; this draft
  does not silently bypass filters. Prior failed runs may be superseded only by
  a later successful full DB run at a descendant containing their migrations;
  pending/running prior DB runs always block mutation.
- **PSD-020 (deployed bytes and initial quiescence).** Use correctly authenticated
  Supabase CLI list/download for only the approved function/project into an
  isolated private temporary location; compare downloaded deployed source and
  all bundled application imports/configuration against the exact checked Git
  tree. Bind that comparison to the listed function version/JWT setting before
  and after download; changed versions refuse. CLI metadata alone is not source
  proof; if the platform cannot return comparable bytes, refuse activation.
  Initial deployment verifies no existing active push function/version, no cron
  source and no outstanding started SQL work through sanitized count-only
  trusted queries. If an existing deployment is found, use the future-rotation
  pause protocol instead of assuming initial quiescence. Finish paused by removing
  the Edge wakeup secret after verification and confirming missing-secret denial.
  Activation reprovisions the intended wakeup, repeats PSD-018 plus byte/gate
  checks and only then performs PSD-013's final transaction. For existing workers,
  demonstrate absence of active invocations and outstanding started work using
  supported protected operational evidence; if unavailable, remain paused.
  Never manufacture health operations, clear network queues, reset reservations
  or turn a timing wait into proof of completion.

Test requirements additionally cover SQL quoting/NUL rejection/private-buffer
cleanup, boolean-only Vault matching, HTTP400/401/503 verification without I/O,
ancestor input equivalence and types-only exception, and downloaded-byte/version
comparison failure. Genuine execution caveats are platform logging visibility,
CLI source-download comparability, and active-invocation/quiescence observability.
Failure of any required proof blocks its operation; it does not create new owner
decisions about already approved transport, identities or consent. Any needed
authority or persistent credential exposure exception is a separate owner
amendment. No Cloud operations or credential reads occurred in drafting.
