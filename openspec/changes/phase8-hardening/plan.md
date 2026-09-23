# Phase 8 — hardening and Android release readiness

This is the frozen contract for the Android-first Phase 8 boundary in ADR-134.
It covers Android and web only; iOS physical acceptance is deferred. A
requirement is not complete without fetchable evidence in the ledger. Unknown,
external, credential-blocked, legal, store-console, or cloud-control work is
recorded as such rather than represented by a synthetic success.

## Method and boundary

- Requirements are EARS-shaped and tests are written first from this contract.
- RLS, identity, tenant isolation, money, and operational-safety changes use
  independent visible and holdout authors plus a fresh-context security critic.
- Migrations remain CI-only and forward-only; no local migration application is
  an acceptance step.
- Focused checks are preferred and their exact command, environment, result,
  and artifact belong in the evidence ledger. A skipped or blocked check is not
  a pass.
- Playwright journeys may use separate demo-gym users/sessions to prove
  isolation; the product remains one verified gym per member in v1 and has no
  public member gym join/switch control.

## Requirements

### HARD-010 — reference-matched member experience

When a member uses authentication, Home, Activity, My gym, or You on web or
Android, the system shall use the approved minimalist v2 hierarchy and shared
light/dark tokens: immediate verified gym identity, dominant check-in, compact
truthful summaries, readable seven-day rhythm, a real profile/account surface,
and four labelled destinations. Both appearances shall be intentionally
composed, English-only, accessible at enlarged text, and usable with reduced
motion/transparency. Raw internal UUIDs shall not be presented as profile
content. Gym imagery may establish place and emotion on authentication and
profile entry surfaces; it shall not obscure controls, invent member facts, or
replace operational content.

Acceptance: representative web and physical-Android crops for auth, Home, My
gym and You in light and dark are compared with the approved boards; focused
interaction/accessibility checks cover labels, targets, enlarged text and
reduced effects.

On the You surface, verified membership state and the current gym name/code
shall appear with the member name before any wrapping email or phone value.
Web and Android shall expose one grouped account list containing Personal
details, Membership, Gym, and Appearance destinations with an accessible name
and a current-value summary. Appearance may open the existing settings flow;
the other rows may remain truthful read-only destinations for the pilot. The
layout shall wrap long contact values without horizontal overflow or pushing
the verified gym identity below the primary profile facts.

Review artifact: `docs/design/phase8/member-hig-auth-core-v4.png`. The main
surface uses one accessible settings icon; appearance lives behind the settings
hierarchy rather than as persistent page content. On iPhone, Apple precedes
Google; Android remains Google-first. The artifact is not implementation
approval until the owner accepts it.

### HARD-011 — Google sign-in grants no Gymloop identity

When an existing pre-linked user chooses Google sign-in, the system shall
complete OAuth through the approved Supabase project, establish the normal
session, classify the returned verified claims through the existing identity
boundary, and route to the canonical home from NAV-001/NAV-002. Password sign-in
shall remain available. Google sign-in shall not create or mutate a Gymloop
role, tenant, member association, membership, or claim; a provider-authenticated
account without one complete verified Gymloop identity shall reach the existing
not-linked/no-access state. Failure copy shall be generic and shall not reveal
whether an account or link exists.

Acceptance: independent visible and holdout tests cover a fixed canonical
callback, missing/bad code, exchange failure, every canonical linked-role home,
the unlinked result, refusal of caller-controlled redirect destinations, and no
identity mutation. Real-provider completion remains external until configured
and exercised with a controlled account.

### HARD-012 — OAuth redirect and credential boundary

When OAuth begins on web, the app shall derive its callback from one validated
server-owned public application origin, never a request Host header or caller
provided `next` value. The Google redirect registered in Google Cloud shall be
the Supabase Auth callback for the approved project; Supabase shall allow only
the exact production/local app callbacks required by the verified journeys.
Secrets shall remain outside source control and browser bundles. Android OAuth
shall be a separate deep-link batch that reuses the same identity classifier
and secure mobile session store; iOS remains deferred.

Acceptance: source/registry checks and focused tests prove the fixed callback
and generic failure behavior. Creating OAuth credentials, entering a client
secret, enabling the provider, and changing hosted redirect allow-lists require
real console evidence and are never inferred from local code.

### HARD-001 — truthful gate and evidence ledger

When a Phase 8 gate is reported, the system or runbook shall record the exact
requirement ID, command or procedure, commit/build identity, environment,
timestamp, result, artifact location, and any blocker or external dependency;
and it shall distinguish passed, failed, skipped, blocked, and external from
one another. No gate report shall claim completion without fetchable evidence.

Acceptance: the ledger is reviewable in a fresh checkout and contains no
invented, synthetic, or implied provider/device/store/legal success.

### HARD-002 — Android release configuration and least privilege

When Android release readiness is checked, the repository shall expose a
reviewable release configuration, test integration, least-privilege permission
set, and signed-AAB readiness proof; and it shall state separately any missing
keystore, Play signing, account, or console action. A signed-AAB readiness
proof shall not claim Play Store upload or publication.

Acceptance: focused Android checks and configuration evidence are recorded;
physical-device or Play-console evidence is marked external when unavailable.

### HARD-003 — browser journeys, accessibility, themes, language, isolation

When browser acceptance runs, Playwright shall execute journeys A–D using
separate authenticated users/sessions and shall check the real multi-tenant
boundary, including that one gym cannot read or mutate another gym's data. The
same run shall cover axe accessibility checks, light and dark appearance, and
English-only UI. It shall not create, expose, or test a public member gym
join/switch control.

Acceptance: journey artifacts identify the users, sessions, gyms, route, and
assertions; a missing journey or isolation proof is not a pass.

Browser credentials are read only through a lazy `playwrightEnv()` export in
`packages/shared/src/config/env.ts`; no test/config file reads `process.env`.
It returns a required `DEMO_ACCOUNT_PASSWORD` and an optional validated
`PLAYWRIGHT_BASE_URL` defaulting to `http://127.0.0.1:3000`. Local execution
loads the gitignored `.env.local` through Node's environment-file option; CI
supplies repository secrets. Missing credentials fail the run before tests are
collected and must never turn the suite green by skipping it.

### HARD-004 — isolated k6 load and tenant-safety test environment

When k6 load or isolation testing runs, it shall use either the existing
explicitly separate non-production target or the owner-authorized, bounded
prelaunch-shared Cloud Supabase route in ADR-162. The latter is available only
while Gymloop has no live customers. Both routes shall cover the 100-gym ×
500-member morning check-in spike and real cross-tenant read and mutation
denials. A same-project run cannot satisfy this gate by merely bypassing the
isolated-target guard or relabelling the existing demo gym.

Acceptance: the selected environment's identity, safety preflight, workload,
preapproved p95 budget, raw result, resource observations and exact fixture
cleanup are recorded. The provider restore drill remains excluded from this
route and receives no inferred pass.

**Bearer verification at load (HARD-004 identity addendum).** WHEN the check-in
API receives one syntactically valid bearer access token, THE SYSTEM SHALL
verify its signature and expiry through Supabase `getClaims(token)`, require
`role = authenticated` and a complete Gymloop staff or member identity, and
derive the subject, tenant and actor only from those verified claims before
parsing the command body. A failed verification, malformed/contradictory claim,
unsupported role, absent token, or mixed cookie/bearer transport SHALL fail
closed before any command body or database mutation. The bearer path SHALL NOT
call the per-request Auth `/user` endpoint; the approved project uses ES256,
so `getClaims` verifies against cached public signing keys. Cookie-based
requests retain their existing Auth user check. This retains the documented
maximum fifteen-minute access-token revocation window; it does not promise
instant revocation. Every admitted request remains subject to the existing
database RLS and check-in guards.

Acceptance: independent visible and holdout suites cover verified staff and
member bearers, mismatched or missing Auth role, verification error, incomplete
or contradictory identity, ambiguous transport, cookie regression, and that a
bearer request makes no `/user` call. A production-built API smoke check on the
linked Cloud project confirms ES256 and a verified bearer before the full run.

**Session continuity during the spike.** WHEN the prelaunch-shared campaign
signs in its 100 synthetic staff identities, THE SYSTEM SHALL retain each
session's initial access token, one-time refresh token, and expiry in a separate
private, owner-marked fixture, bound by gym ID to the validated check-in
fixture. The runner SHALL validate that all 100 bindings are distinct and
complete before k6 sends any check-in. It SHALL keep the refresh fixture out of
Git, command arguments, output, and public evidence, with the same restricted
local permissions as the bearer fixture.

WHILE a virtual gym session is within 120 seconds of access-token expiry, THE
SYSTEM SHALL use Supabase's Cloud refresh-token grant with the project's public
API key, then replace that virtual user's access token, refresh token and expiry
with the returned session before its next check-in. A failed, malformed,
replayed or cross-gym refresh SHALL fail the run, never continue check-ins with
an expired token or silently change gym identity. The original 900-second JWT
lifetime, 100 distinct gym sessions, 50,000 unique check-ins, two-second p95
budget and both isolation denials SHALL remain unchanged. The isolated-project
route may retain its existing fixture contract.

Acceptance: independent visible and holdout tests cover refresh-fixture
binding, missing/duplicate credentials, exact expiry boundary, one-time token
rotation, failed/malformed refresh, and no secret leakage; a real linked-Cloud
run confirms 50,000 acknowledged and persisted check-ins. The failed
2026-09-23 run is retained as evidence, not relabelled as a pass.

The reviewable pure interface is `scripts/phase8-load-session-refresh.mjs`:
`validateRefreshFixture(refreshFixture, checkInFixture)` returns gym sessions in
the check-in fixture's order; `refreshDue(session, nowSeconds, leadSeconds)`
returns a boolean; `rotateRefreshSession(session, AuthResponse,
nowSeconds, leadSeconds)` returns the replacement session or throws. A refresh
fixture has exactly `marker` and `gymSessions`; each session has exactly
`gymId`, `userId`, `token`, `refreshToken`, and integer Unix `expiresAt`.
`leadSeconds` is a positive integer. `refreshDue` becomes true at
`nowSeconds >= expiresAt - leadSeconds`. `AuthResponse` is Supabase's refresh
grant JSON `{access_token, refresh_token, expires_at, user: {id}}`; rotation
returns the same normalized five-field session shape with the old gym and user
IDs, new access and refresh tokens, and new integer Unix expiry. The k6
prelaunch route reads the second private file through the absolute
`PHASE8_LOAD_REFRESH_PATH` and the fixed lead through
`PHASE8_LOAD_REFRESH_LEAD_SECONDS`.
The prelaunch workload SHALL allocate all 100 virtual users exclusively to the
check-in scenario, with one fixed gym and 500 distinct members per user. It
SHALL run both real tenant-denial probes before that scenario, so probe virtual
users cannot displace a gym. Raw evidence SHALL identify check-in HTTP points
separately from Auth refresh and tenant probes; only check-in responses count
toward 50,000 and only check-in durations determine the two-second p95.
The k6 latency threshold SHALL use the same `name=morning_check_in` filter.

Setup-phase probe evidence has `group = ::setup` and no scenario tag; a missing,
duplicated or successful cross-tenant mutation SHALL fail reconciliation.
Validation binds every access token to the existing fixture's gym and marker,
rejects duplicate gym/user/access/refresh identities, and exposes no secret in
errors. Rotation requires the same returned Auth user ID, a fresh access token,
a different nonblank refresh token, and expiry beyond the lead window.

**Assisted check-in response-time repair.** WHEN a verified staff caller sends
a new assisted front-desk check-in with a member ID and nonblank reason, THE
SYSTEM SHALL resolve the member visible to that caller and record attendance
in one RLS-scoped PostgREST command. The member, tenant, branch and acting staff
MUST retain their existing database enforcement; the caller cannot supply a
tenant or actor. A member invisible under RLS SHALL still produce the existing
404 `member_unknown` response with no attendance. Missing or whitespace-only
reasons, unsupported roles, cross-tenant members, duplicate-window check-ins,
and reused client event IDs SHALL keep their existing refusal envelopes and
zero unintended side effects. An exact same-member event retry SHALL return
the original check-in with `replay: true`; the QR and member-mobile paths stay
on their current commands. The successful API response retains the current
`memberName`, `id`, `checked_in_at`, `source`, and `replay` fields. Reducing one
network round trip is an implementation repair, not a new latency waiver: the
unchanged 50,000-acknowledgement, zero-failed-check and p95 < 2,000 ms Cloud
bar determines whether it actually works.

**Bounded transient command retry.** WHEN that staff front-desk command
returns PostgREST `PGRST003` (the pool-acquisition timeout), OR the installed
PostgREST client reports status `0` with an empty error code after an
ambiguous transport or response-read failure, AND the request contains a
client event ID, THE SYSTEM
SHALL submit the identical command at most once more. It SHALL NOT retry a
request without an event ID, retry after a second transient failure, or retry
another database/security refusal. If the retry finds the same event already
recorded for the same member, THE SYSTEM SHALL return the original attendance
through the existing replay response; an event reused for another member
SHALL remain a conflict. Status `0` does not prove the first command failed
before SQL, so the unchanged unique event ID and replay boundary are
required. This repair does not relax the 50,000-acknowledgement, zero-failed-
check and p95 < 2,000 ms Cloud bar.

**Safe failure diagnosis.** WHEN a check-in database command ends in the
generic server-error response, THE SYSTEM SHALL emit an operational event
containing the caller's tenant ID and only a validated SQLSTATE or PostgREST
error code, or `unclassified` when the code is absent or malformed. It SHALL
NOT log the database message, request body, bearer, member identity, client
event ID or other free text. The user-facing response remains unchanged. This
event distinguishes a pool timeout from another failure in a subsequent
measured run; it does not itself pass HARD-004.

The reviewable database boundary is
`public.record_staff_front_desk_check_in(p_member_id uuid, p_reason text,
p_client_event_id uuid)`, a `volatile security invoker` function granted only
to `authenticated`. It accepts no tenant, branch or actor argument, uses the
caller's RLS-visible `members` row, and returns at most one row containing
`id`, `checked_in_at`, `source`, and `member_name`. Zero rows mean the member
was not visible. The attendance trigger and policies remain the final write
authority. The route uses this command only for staff front-desk requests,
maps a rare unique `client_event_id` collision through its existing same-member
replay lookup, and preserves the current QR/member routes.

**Prelaunch-shared route (ADR-162).** WHEN the owner authorizes testing on the
linked Cloud project, THE SYSTEM SHALL require a separate explicit
`prelaunch-shared` target mode and confirmation value, matching configured,
observed API, Supabase and credential project references, the exact linked
Supabase origin, a current no-live-customer assertion, a timestamped baseline
manifest of existing organization/member/attendance/Auth identities, a fresh
synthetic run marker, and a durable exact-ID cleanup manifest before any
fixture write or k6 call. It SHALL reject a project mismatch, missing manifest,
reused marker, unverified source, or a target other than the linked Cloud
project. The isolated-project validator below retains its existing rejection
of the production-configured reference; it is not weakened by this alternative.

WHEN a prelaunch-shared fixture is staged, THE SYSTEM SHALL use only newly
marked synthetic gyms, owners, staff, plans, memberships and members; never
rewrite, delete, or use an existing demo or staged pilot identity. It SHALL
persist the exact synthetic IDs and Auth IDs to a gitignored recovery manifest
before proceeding, and SHALL be able to resume exact-ID cleanup after an
interrupted run. A fixture or cleanup failure is non-passing. The acceptance
workload remains exactly 100 unique gym sessions × 500 owned members and
50,000 unique assisted check-ins, with both cross-tenant denial probes.

WHEN the prelaunch-shared run is prepared or running, THE SYSTEM SHALL check
the actual linked database size through the Supabase CLI and refuse or abort
if it reaches 400,000,000 bytes, if size collection fails, or if its recorded
provider quota is not the current 500,000,000-byte Free-plan limit. It SHALL
record the pre-run size and periodic sizes at intervals no greater than 60
seconds without exposing member data. It SHALL stop before the Free project's
read-only limit and never claim a pass if the observer stops. The p95 budget is
fixed in evidence before execution, not chosen after seeing the result.

WHEN a prelaunch-shared run finishes or aborts, THE SYSTEM SHALL reconcile
the raw k6 result, exact synthetic attendance count, foreign-read denial,
foreign-mutation status, pre-existing baseline invariants, and exact-ID
cleanup including synthetic Auth users. The run SHALL be reported Passed only
if the existing 50,000/p95/isolation criteria hold and a separately captured
postflight proves no unexplained synthetic remainder or change to pre-existing
identities. A failed or missing cleanup remains a blocker even if k6 is green.

The fixture's 50,000 member IDs and 100 bearer tokens SHALL be read by k6 from
one gitignored local fixture file at initialization; they SHALL NOT be placed
in an environment variable, command line, raw result, tracked file or ledger.
The caller supplies only that file path and non-secret configuration through
bounded environment values. A missing, malformed or cross-owned fixture fails
before any HTTP call.

Frozen prelaunch validator interface: `scripts/phase8-prelaunch-load-safety.mjs`
exports exactly `assertSafePrelaunchTarget`, `assertSafePrelaunchQuota`,
`assertSafePrelaunchFixture`, and `summarizePrelaunchResult` as named functions.
The existing isolated-route exports remain unchanged.

`assertSafePrelaunchTarget(target)` accepts exactly `mode`, `projectRef`,
`observedApiProjectRef`, `observedSupabaseProjectRef`, `apiUrl`, `supabaseUrl`,
`confirmation`, `credentials`, and `noLiveCustomers`. `mode` is exactly
`prelaunch-shared`; all references are the linked ref
`pecxrpskmfeuyzngvewq`; both URLs are HTTPS origin-only and the Supabase URL
is exactly `https://pecxrpskmfeuyzngvewq.supabase.co`; `confirmation` is
`PRELAUNCH_SHARED_LOAD_APPROVED`; `credentials` is exactly
`{ kind: 'prelaunch-shared', present: true, projectRef }`; and
`noLiveCustomers` is the boolean `true`. It returns only the mode, reference
and normalized origins, never credential material.

`assertSafePrelaunchQuota(snapshot)` accepts exactly `observedAt`,
`databaseBytes`, `providerQuotaBytes`, and `maxDatabaseBytes`. The time is a
canonical UTC ISO timestamp no older than fifteen minutes and not future;
`providerQuotaBytes` is exactly 500,000,000; `maxDatabaseBytes` is exactly
400,000,000; and `databaseBytes` is a nonnegative integer strictly below the
maximum. It returns only those non-secret values.

`assertSafePrelaunchFixture(fixture)` accepts exactly `marker`, `gymFixtures`,
`fixturePath`, `baselineManifestPath`, and `cleanupManifestPath`. `marker` is
`PHASE8-LOAD-` followed by a fresh UUID. `gymFixtures` uses the frozen
`{ gymId, token, memberIds, ownedMemberIds }` shape and exact 100 × 500
uniqueness/ownership rules. Each path is a nonblank local path and the three
paths are distinct. The function returns the marker, paths and counts only;
it never returns or prints tokens, member IDs or full fixture contents.

`summarizePrelaunchResult(input)` accepts exactly `status`, `target`, `quota`,
`fixture`, `rawResultPath`, `thresholds`, `measured`, `monitor`, and `cleanup`.
`status` is `prepared`, `blocked`, or `passed`. A `passed` request revalidates
the three inputs above and requires a finite positive `thresholds.p95Ms`,
`measured: { p95Ms, completedCheckIns, crossTenantReadDenied,
crossTenantMutationStatus }` meeting the unchanged 50,000/p95/denial criteria,
`monitor: { completed: true, maxObservedDatabaseBytes, maxGapSeconds }` with
size strictly below 400,000,000 and gaps no greater than 60, and
`cleanup: { completed: true, preexistingUnchanged: true,
syntheticRemainderCount: 0, authRemainderCount: 0 }`. Missing or false evidence
returns `blocked` or throws; it never returns `passed` on caller status alone.
The returned summary is credential-free and references the raw/monitor/cleanup
artifacts by path, not their private contents. A future runner may inject a
backend for tests, but it must use this exact validator before Cloud writes.

Frozen prelaunch fixture-planning interface: `scripts/phase8-prelaunch-load-fixture.mjs`
exports exactly `buildPrelaunchSyntheticPlan`, `renderPrelaunchStageSql`,
`renderPrelaunchCleanupSql`, and `parseLinkedDatabaseSize`. The planner is pure:
it has no filesystem, CLI, network or secret access. Its caller supplies a
fresh `PHASE8-LOAD-<UUID>` marker and persists the returned plan to a
gitignored recovery manifest **before** any Cloud write.

`buildPrelaunchSyntheticPlan(marker)` returns that marker and exactly 100 gyms.
Each gym has deterministic UUID `gymId`, `branchId`, `planId`, `staffId`, a
marker-scoped non-delivering synthetic owner/staff email, and exactly 500
`{memberId, membershipId}` pairs. All identifiers are distinct across the
plan; the same marker reproduces the same IDs for interrupted cleanup. The
plan contains no password, bearer token, service key or pre-existing identity.

`renderPrelaunchStageSql(plan, authBindings)` accepts exactly one distinct
`{email,userId}` binding for each planned gym, after the caller has created
those Auth users and written each returned Auth ID to the recovery manifest.
It returns one transaction that inserts only the plan's new organizations,
settings, branches, zero-price synthetic plans, front-desk staff, members and
active synthetic membership periods. No seed, migration, trigger disabling,
`ON CONFLICT`, pre-existing row update or broad truncate is allowed. It fails
closed on missing/foreign/duplicate bindings and validates all 100 × 500 plan
identities before rendering. Its final assertion checks exact staged counts.

`renderPrelaunchCleanupSql(plan)` returns one transaction that verifies any
existing planned gym IDs still carry the plan marker, deletes only rows under
the plan's exact gym IDs in FK-safe order, and verifies zero planned database
identities remain. It must work after partial staging or interrupted k6 and
must never delete from a pre-existing gym. Auth deletion is a separately
checked Admin API step using the manifest's exact user IDs and marker emails.

`parseLinkedDatabaseSize(raw)` accepts the Supabase CLI's JSON query output,
requires exactly one nonnegative safe-integer `database_bytes` value from the
linked database, and returns the number only. A missing/error/ambiguous value
fails closed. The orchestrator calls it for the baseline and at most 60-second
sampling, passes snapshots through `assertSafePrelaunchQuota`, kills k6 if the
observer fails or reaches 400,000,000 bytes, and resumes exact cleanup from
the durable manifest. No Cloud load can pass on a planner result alone.

Frozen prelaunch orchestration interface: `scripts/phase8-prelaunch-load-campaign.mjs`
exports exactly `runPrelaunchLoadCampaign(config, backend)`. `config` has
`target`, `marker`, `fixturePath`, `baselineManifestPath`,
`cleanupManifestPath`, `rawResultPath`, `thresholds: { p95Ms }`, and optional
positive `monitorIntervalMs` no greater than 30,000 (30,000 by default).
The four artifact paths are distinct local paths. The runner validates the
linked target, a fresh CLI size and the fixed quota before any Cloud mutation;
it calls the pure fixture planner and persists the plan/intent via the backend
before the first Auth user. The backend is injected so independent tests never
touch Cloud. It has async methods `writeManifest(state)`, `observeSize()`,
`captureBaseline(plan)`, `createAuthUser(email)`, `stageSql(sql)`,
`signIn(email)`, `writeFixture(fixture)`, `runK6(request)`,
`countAttendance(plan)`, `cleanupSql(sql)`, `deleteAuthUser(email, userId)`,
and `verifyPostflight(plan, baseline)`. `observeSize()` returns the exact
snapshot accepted by `assertSafePrelaunchQuota`; `createAuthUser` returns one
UUID; `signIn` returns one bearer token; `runK6` returns the measured object
accepted by `summarizePrelaunchResult`; `verifyPostflight` returns the cleanup
facts accepted there. The backend owns secret storage and actual Cloud/CLI
calls, not pass/fail judgment.

The campaign writes a durable intent before each Auth creation, records each
returned Auth ID immediately, stages only through the rendered transaction,
signs in to all 100 gyms, validates and writes the private k6 fixture, and
starts k6 only after a fresh size sample. It checks size initially, periodically
through Auth staging, SQL and k6, and at the end. Observation gaps greater
than 60 seconds, missed/failed samples, or reaching 400,000,000 bytes abort
and make the result blocked. The k6 request receives an AbortSignal and must
terminate promptly on abort. The campaign compares measured check-ins with an
independent persisted-attendance count, then always attempts exact SQL cleanup,
all marker-scoped Auth deletions (including an Auth creation that succeeded
before its ID could be recorded), and a separate pre-existing/postflight
comparison. If cleanup fails, its recovery manifest remains and no pass is
possible. Only full measured, monitored and cleaned evidence may return a
credential-free Passed summary; partial or failed work returns Blocked and
never exposes tokens, passwords or member IDs.

Frozen Cloud adapter interface: `scripts/phase8-prelaunch-load-cloud.mjs`
exports `parsePrelaunchK6Raw(raw)` and
`createPrelaunchCloudBackend(config, ports)`. The adapter implements the
campaign backend for the same linked project. `config` has exactly
`{ campaignConfig, anonKey }`, where `campaignConfig` has the frozen campaign
shape and `anonKey` is the project's public anon key;
`ports` injects only the external calls: `queryLinked(sql)` returning CLI JSON,
`createAuthUser(email, password)` returning an Auth UUID,
`signIn(email, password)` returning a bearer token, `listAuthUsers()` returning
`{id,email}` records, `deleteAuthUser(id)`, and
`executeK6({ signal, env, rawResultPath })` returning `{exitCode, raw}`.
The real operator binds these ports to the Supabase CLI, Supabase Auth and k6;
the independent tests bind fakes and perform no Cloud calls. The adapter
itself owns atomic private 0600 artifact writes and a synced append-only
recovery journal. Its first journal record contains the deterministic plan,
target reference and artifact paths; later intent and returned-ID records
append without replacing the plan. Reusing an existing journal path fails.
Password material exists in memory only, never in a journal, result or k6
environment. On Auth deletion it lists users, matches the exact marker email,
and verifies the expected ID when present; a missing ID uses exact email
lookup. A mismatch fails closed.

The adapter queries actual linked Cloud size, compares an independent snapshot
of pre-existing organization, settings, branch, plan, staff, member,
membership, attendance and Auth identities before and after, counts persisted
synthetic attendance independently, and verifies no planned tenant rows or
marker Auth users remain after cleanup. The read-only baseline is persisted
before any Auth creation. A query error or ambiguous result blocks. The
adapter never seeds, resets, migrates, truncates or modifies existing gyms.
`parsePrelaunchK6Raw` accepts newline JSON k6 points, counts only successful
`morning_check_in_spike` HTTP requests tagged `name=morning_check_in`, and
computes p95 only from their duration points. Auth refresh and both probes
are excluded from that count and latency. It requires a successful read-denial
check and a non-2xx mutation request emitted by setup. It rejects missing,
malformed or ambiguous probes. The actual k6 exit code must be zero for a
passing result. For raw JSON points, the canonical wire examples are
`{"metric":"http_reqs","type":"Point","data":{"value":1,"tags":{"scenario":"morning_check_in_spike","name":"morning_check_in","status":"200"}}}`,
`{"metric":"http_req_duration","type":"Point","data":{"value":42.5,"tags":{"scenario":"morning_check_in_spike","name":"morning_check_in"}}}`,
`{"metric":"checks","type":"Point","data":{"value":1,"tags":{"group":"::setup","check":"cross-tenant member read is denied"}}}`,
and
`{"metric":"http_reqs","type":"Point","data":{"value":1,"tags":{"group":"::setup","name":"cross_tenant_mutation","status":"403"}}}`.
The real file may add k6 metric-definition lines and extra data/tags. One
read-denial check and one mutation request must be present, each exactly once.

Frozen harness interface: `scripts/phase8-load-safety.mjs` exports
`assertSafeLoadTarget`, `buildMorningCheckInWorkload`, `summarizeRawResult`
and `preflightLoadRun`. `assertSafeLoadTarget(target)` accepts exactly the
canonical safety fields `projectRef`, `observedApiProjectRef`,
`observedSupabaseProjectRef`, `apiUrl`, `supabaseUrl`, `confirmation`, and
`credentials: { kind, present, projectRef }`. A safe target has HTTPS URLs;
all three project references and the credential reference are the same; and
the Supabase hostname is exactly `<projectRef>.supabase.co`. None may be the
production reference `pecxrpskmfeuyzngvewq`. The exact confirmation is
`NON_PRODUCTION_LOAD_APPROVED`, `kind` is exactly `non-production`, and
`present` is exactly `true`; truthy substitutes do not pass. The return value
contains only `projectRef`, normalized `apiUrl`, normalized `supabaseUrl`, and
`nonProduction: true`, never credentials.

Both URLs are origin-only base URLs: no username, password, non-root path,
query or fragment is accepted. Normalized URLs are returned as `URL.origin`
with no trailing slash.

`buildMorningCheckInWorkload({ thresholds, tenantIsolation, gymFixtures })`
requires `thresholds: { p95Ms }`, both denial flags set to the boolean `true`,
where the exact flag names are `denyCrossTenantRead` and
`denyCrossTenantMutation`, and caller-supplied real fixtures. Each fixture is
`{ gymId, token, memberIds, ownedMemberIds }`. There are exactly 100 unique
gym IDs and tokens; each contains exactly 500 unique member IDs; member IDs
are globally unique; and each fixture's member set exactly matches its owned
member set. Duplicate gym identities, tokens, member identities or
cross-owned members fail preflight. The caller supplies a finite positive p95
budget. No fixture is synthesized by the harness. The returned workload has
`gyms`, `membersPerGym`, `totalMembers`, `spike`, `thresholds`,
`tenantIsolation`, and the validated `gymFixtures`. The morning scenario
covers all 50,000 gym/member pairs, and separate probes prove both a
cross-tenant read denial and a cross-tenant mutation denial; every 2xx
mutation response is a failure.

`preflightLoadRun({ target, workload, fixturePath, rawResultPath })` validates
the target and revalidates the complete workload before returning prepared
metadata and a credential-free command. Missing or extra caller-declared
duplicate flags are not evidence; the fixture contents themselves are checked.

`summarizeRawResult(input)` accepts `rawResultPath` and a requested `status`.
`prepared` or `blocked` may be returned without execution. A requested
`passed` additionally requires the canonical `target`,
`thresholds: { p95Ms }`, and
`measured: { p95Ms, completedCheckIns, crossTenantReadDenied,
crossTenantMutationStatus }`. It returns `passed` only when the target validates,
measured p95 is finite and within the approved threshold, exactly 50,000
check-ins completed, the read denial is exactly `true`, and the mutation
status is outside the entire 200–299 range. Otherwise it throws or returns a
non-passing status. The result contains the normalized target identity and raw
artifact path, not credentials. A caller-supplied status string alone can never
turn an unverified result green.

### HARD-005 — structured redacted logging and monitoring runbook

When an application error or operational event is emitted, logs shall be
structured, carry the permitted tenant and correlation context, and redact
secrets, credentials, tokens, and unnecessary personal data. The error-monitoring
adapter and runbook shall name alert thresholds, ownership, escalation, and
retention, while identifying the provider destination as external until a real
provider configuration is verified.

Acceptance: adapter contract, redaction checks, and runbook evidence exist;
synthetic provider delivery is not accepted as external monitoring proof.

Frozen application interface: `apps/web/lib/observability.ts` exports
`createOperationalLogger(options)`. The options supply a structured `write`
sink, an optional `report` adapter and an injectable ISO timestamp source. The
returned `info` and `error` methods accept an event name plus optional
`tenantId`, `correlationId`, message and nested context; they send the same
JSON-safe, recursively redacted event to the sink, and `error` additionally
sends it to the report adapter. Keys naming authorization/cookies/passwords,
access or refresh tokens, API/service-role keys or secrets, and direct member
PII (email, phone, full name) are replaced by `[REDACTED]`; cycles are replaced
by `[Circular]`. Top-level tenant/correlation identifiers remain permitted.
Adapter failure must never replace the application failure or expose the raw
input. No monitoring vendor dependency is required until a real destination is
owner-configured.

Frozen production-monitor interface: the repository CLI is
`node scripts/phase8-production-monitor.mjs --input <json-file>` and the
scheduled destination is `.github/workflows/phase8-production-monitor.yml`.
The input contains `mode` (`scheduled` or `force-test-alert`), an injected ISO
`evaluatedAt`, deployment/run evidence, a production `logQuery` with event
rows, and a production `endpointProbe` with ordered check rows. Credible event
signals are exactly `cross_tenant_disclosure`, `payment_integrity_failure`,
`credential_exposure`, and `destructive_data_loss`; unknown or unconfirmed
classifications do not create a security incident. Five HTTP 5xx events in
the inclusive preceding five minutes create SEV-2; the latest three failed
endpoint checks create SEV-2; one credible signal creates SEV-1 and takes
precedence. `force-test-alert` creates a distinct TEST-only issue and never a
production severity or production-alert label.

JSON output is deterministic and limited to schema version, decision,
severity, test flag, evaluated time, ordered reasons, whitelisted run/
deployment/query/probe/correlation evidence, and alert-only issue metadata and
body. Unsafe correlation ids become `[REDACTED]`; raw messages, response bodies,
context, authorization, email, phone, password, token and secret values are
never copied. Missing/invalid evidence, time, or production identity exits
nonzero without JSON or echoing untrusted input. The workflow runs every five
minutes and on manual dispatch, has only `contents: read` and `issues: write`,
keeps `VERCEL_TOKEN` step-scoped, collects production Vercel logs and three
production health probes, passes a file input to the CLI, and creates or
updates the issue by `.issue.key` using `.issue.body` through `--body-file`.

The exact v1 input keys are
`{mode,evaluatedAt,evidence,logQuery,endpointProbe}`. `evidence` is
`{deploymentId,deploymentCommit,runId,runAttempt}`; `logQuery` is
`{queryId,environment,startedAt,endedAt,events}`; and `endpointProbe` is
`{probeId,environment,checks}`. An event supplies ISO `observedAt` plus optional
`correlationId`, integer `httpStatus`, `signal`, and boolean `credible`; extra
raw event fields may be present but are never copied. A check supplies ISO
`observedAt`, optional `correlationId`, boolean `ok`, and integer `httpStatus`.
Both environment values are exactly `production`, `deploymentCommit` is a
40-character hexadecimal Git commit, `runAttempt` is a positive integer, and
`logQuery.endedAt` equals `evaluatedAt` while `startedAt` covers the complete
five-minute window. The v1 output keys are
`{schemaVersion,decision,severity,testOnly,evaluatedAt,reasons,evidence}` plus
`issue` only for an alert. These names are part of the contract; a test or
implementation may not silently substitute a second wire shape.

A healthy result has `severity: "NONE"`. Credible signal rows are intentionally
collapsed to the generic ordered reason code
`CREDIBLE_SECURITY_INTEGRITY_SIGNAL`; raw signal names are not repeated in the
reason or issue body. The remaining reason codes are `API_5XX_THRESHOLD`,
`HEALTHCHECK_CONSECUTIVE_FAILURES`, and test-only `TEST_DELIVERY`.

Because GitHub scheduled events may be delayed or dropped, a dedicated
Cloudflare Worker Cron trigger shall dispatch the same monitor workflow every
five minutes through GitHub's workflow-dispatch API. The Worker has no public
HTTP handler or application data; its secret is a Gymloop-repository-only
GitHub token with Actions write permission. It sends only the workflow name,
`main` ref and `force_test_alert=false`, requires HTTP 204, and reports a
redacted failure to Cloudflare logs. The existing GitHub schedule remains a
fallback. HARD-005 is Passed only after consecutive real Cron dispatches,
completed monitoring runs, issue-delivery proof and a missed-run/failure
escalation are recorded; deploying the Worker alone is not cadence proof.
The Worker at `workers/phase8-monitor-dispatch.mjs` exports only a default
object with async `scheduled(event, env)`; it uses global `fetch` and
`env.GITHUB_ACTIONS_DISPATCH_TOKEN`, accepts only cron `*/5 * * * *`, sends one
POST and throws a generic redacted error on a non-204 or network failure.
`wrangler.phase8-monitor.jsonc` contains that exact Cron trigger.

When production evidence collection or evaluation fails before it can return a
decision, the workflow shall leave the run failed and create or update one
open, generic GitHub Issue carrying `production-alert` and
`phase8-monitor-failure`. The issue shall link the run and identify the
30-minute SEV-2 acknowledgement path, without copying provider logs, exception
text, credentials, or personal data. Repeated failures shall update that issue
instead of creating unbounded duplicates. A manual
`force_test_collection_failure` input shall exercise the same failure branch
before contacting providers, produce a clearly marked TEST-only issue without
`production-alert`, and leave the workflow run failed. The test receipt shall
be closed after verification. This covers collector failures; an absent Cron
execution still requires independent missed-run detection and escalation.
The failure handler lives at `scripts/phase8-monitor-failure.mjs` and exports
`reconcileMonitorFailure({ mode, repository, runId, issueStore })`, where `mode`
is `production` or `test`, `repository` is an `owner/name` GitHub repository,
`runId` is a positive decimal GitHub run id, and `issueStore` supplies
`findOpen(labels)`, `create(issue)`, and `update(number, issue)`. The function
validates the identifiers, builds only fixed generic issue text and labels,
then creates or updates by the mode-specific key label. A CLI wrapper accepts
only `--mode`, `--repository`, and `--run-id`, uses `gh` with argument arrays,
and inherits the workflow's `GH_TOKEN` without reading it in application code.
TEST and production issue identities must remain disjoint in either creation
order, even though both receipts carry the common failure-classification label.
The failure handler runs in a separate dependent workflow job with
`needs: monitor` and a job-level `always()` condition whenever the monitor job
did not succeed. It has its own checkout and Node setup, so a failed CLI
installation, collection/evaluation failure, or monitor-job timeout still
reaches the issue path. The monitor job retains its failed conclusion; the
dependent job cannot turn a failed monitor green. A failed GitHub platform or
issue API cannot be described as a delivered alert.

When no successful production monitor run was created in the preceding 15
minutes, an independent watchdog shall create or update one generic SEV-2
GitHub Issue with `production-alert` and `phase8-monitor-missing` labels. It
shall name the last successful run id and creation time when available, but never
copy log rows, probe bodies or credentials. Only completed, successful runs of
the production monitor on `main` with the exact production run title qualify;
manual TEST alert/failure runs cannot keep the watchdog green. Missing,
malformed, future-dated or untrusted run data fails closed. The monitor workflow
shall name ordinary scheduled and manual production runs exactly `Gymloop
production monitor`, while forced TEST runs have distinct titles containing
`TEST`; a manually dispatched non-TEST production run qualifies normally. The
watchdog uses those titles because GitHub's run-list fields do not expose the
manual dispatch inputs. A separate workflow
shall run the watchdog on its own five-minute schedule, offset from the monitor,
and on manual dispatch. The Cloudflare Cron Worker shall independently dispatch
both workflows using the existing repository-only Actions credential, attempting
both even if either dispatch fails. A forced TEST missing-run input shall prove
the issue route using a disjoint TEST-only label and no `production-alert`, and
its issue shall be closed after verification. A failed GitHub API or issue
delivery is not a delivered alert. This dual trigger gives observed missed-run
escalation, not an absolute timing guarantee if Cloudflare Cron and GitHub
schedule both fail.

The production run's `createdAt` is the GitHub queue creation timestamp, not a
claim about when its job started. A completed success must be present before it
can qualify.

The watchdog CLI is `node scripts/phase8-monitor-watchdog.mjs --input
<json-file>`. Its exact input is `{mode,evaluatedAt,repository,runs}`, where
`mode` is `scheduled` or `force-test-missing` and each run provides
`{databaseId,createdAt,status,conclusion,event,headBranch,displayTitle}`.
The pure export `evaluateMonitorCadence(input)` returns a JSON-safe decision
with `decision` (`healthy` or `alert`), `testOnly`, `evaluatedAt`, and an `issue`
only for alerts. The production title is `Gymloop production monitor`; the
watchdog rejects extra input fields, invalid times, non-Gymloop repository,
malformed run identities and run timestamps after evaluation. The 15-minute
boundary is inclusive. The workflow reconciles the alert by the mode-specific
key label, updates an existing open issue, and does not close a production
issue automatically merely because a later monitor succeeded. The forced TEST
mode still validates its input and then alerts regardless of run recency. A
separate dependent failure job uses the generic monitor-failure issue handler
when watchdog collection, evaluation or issue delivery fails; the watchdog
run remains failed. The failure job uses TEST mode for a forced TEST run.

The owner named themself as the pilot's primary GitHub alert responder and
accepted a controlled-pilot exception for an unverified independent missed-run
alert until the VPS migration. This does not mark HARD-005 Passed or prove that
a GitHub notification arrived or was acknowledged. A real responder receipt
and missed-run escalation are still required for general release. If the
watchdog is deployed and verified before pilot GO, its own evidence can close
that part without relying on the exception.

### HARD-006 — DPDP export, erasure, and retention runner

When the DPDP operational runner executes, it shall produce an auditable export
or erasure result, apply the existing owner-approved retention durations and
legal-hold behavior, and preserve a safe record of what was retained, blanked,
deleted, or refused. It shall not invent, shorten, or extend a duration without
an owner-approved contract change. Legal review and sign-off remain external
and are recorded as external until actually obtained.

Acceptance: focused runner checks cover export, erasure, retention, and hold;
legal approval is never represented by a local test result.

For the five-gym controlled pilot only, the owner accepted an explicit
exception for the unresolved privacy product decisions and qualified legal/DPA
review until the planned VPS migration. HARD-006 and DPDP gate 23 remain open;
no export/erasure compliance or legal approval may be reported as Passed from
this exception. The production owner is responsible for obtaining and recording
those decisions and review before any broader release. The exception is a
pilot-scope decision, not a change to the underlying retention, erasure or
legal-hold implementation requirements.

### HARD-007 — backup, restore, incident, and breach evidence

When operational readiness is reviewed, the repository shall contain a backup
and restore procedure, incident-response evidence, and a breach-notification
runbook naming contacts, timelines, channels, and escalation. A cloud backup or
restore drill shall be recorded as external unless it was actually performed
against the configured cloud control and its evidence is fetchable.

Acceptance: local procedure/check evidence is distinct from the external cloud
restore result; an unperformed drill is blocked, not green.

For the Free-plan five-gym controlled pilot, the owner's ADR-159 exception
removes the provider restore/PITR drill from the pilot GO decision only. It
does not mark HARD-007 or gate 29 Passed: incident/breach readiness and a
protected logical backup export still require real evidence, and any later
general release or paid-plan restoration claim requires a real Cloud Supabase
operation and validation.

The owner approved `gymloop-backups`, a private R2 bucket separate from media,
as the encrypted off-project archive for the Free-plan pilot (ADR-164). When a
manual or scheduled backup runs, it shall positively identify the source as
linked Cloud project `pecxrpskmfeuyzngvewq`, capture roles, schema, data and
migration history with the official Supabase CLI, and record capture time and
source hashes. Before any SQL leaves the ephemeral runner, the archive shall
be encrypted with integrity protection; the key and bucket-scoped writer
credential shall live in separate GitHub Actions secrets. Only ciphertext may
be uploaded as backup data; a redacted hash/identity receipt may be retained
as a separate artifact, but no plaintext SQL may be retained. When upload completes, the runner
shall retrieve the exact object, decrypt it, compare the restored archive hash
and record the R2 object identity, size, ciphertext hash and verification
result without emitting data or credentials. A missing part, failed retrieval,
hash mismatch, unexpected project, or export failure shall fail the workflow.
The runbook shall name the backup owner and cadence. This proves a protected
export and read-back, not a database restore; gate 29 remains unperformed.

The `data` SQL part SHALL include both `public` application rows and `auth`
identity rows, including `auth.users`, from two separate CLI data-only dumps
that select exactly `public` and exactly `auth`, then concatenate the complete
outputs in that order. The CLI's default managed-schema exclusions are
insufficient for Gymloop because staff and member rows reference Auth users.
The default schema dump and separate migration-history captures remain as
specified; the encrypted archive keeps its four-part format. A completed
backup receipt is incomplete if the actual data dump omits either schema.
The reviewable command seam is `backupDumpArgs(kind, filePath)`, exported from
`scripts/phase8-protected-backup.mjs` and used by the real runner for all six
CLI captures. `kind` is exactly `roles`, `schema`, `publicData`, `authData`,
`historySchema`, or `historyData`; it returns a `supabase db dump` argument
array using `--linked` and the supplied output file, never a local database
or another project. Each data array SHALL include `--data-only`, `--use-copy`,
and exactly one explicit `--schema public` or `--schema auth`; history captures
SHALL select only
`supabase_migrations`. Tests can inspect this seam without handling credentials
or plaintext customer data. The completed combined data part SHALL contain an
actual public `COPY` statement and an actual `auth.users` `COPY` statement;
quoted and unquoted PostgreSQL identifier forms are accepted. A preamble,
empty table, or successful CLI exit alone does not satisfy this evidence.

The testable entry point is `scripts/phase8-protected-backup.mjs`, exporting
`runProtectedBackup(config, ports)`. `config` contains `expectedProjectRef`,
`bucket`, `objectKey`, and `encryptionKey` (exactly 32 raw bytes in a Buffer).
The async injected ports are
`identifyLinkedProject`, `dumpRoles`, `dumpSchema`, `dumpData`,
`dumpMigrations`, `uploadCiphertext`, `downloadCiphertext`, and `now`.
Each dump returns a Buffer; upload receives `(bucket, objectKey, Buffer)`;
download receives `(bucket, objectKey)` and returns a Buffer; `now()` returns
a UTC ISO timestamp. Encryption,
decryption, and SHA-256 run inside the entry point. It returns only a safe
receipt fields `sourceProjectRef`, `bucket`, `objectKey`, `capturedAt`,
`sourceHashes` (roles, schema, data, migrations), `plaintextSha256`,
`ciphertextSha256`, `ciphertextBytes`, and `verified`. The manual and scheduled workflow is
`.github/workflows/phase8-protected-backup.yml`.

The format reader is `decryptProtectedArchive(ciphertext, encryptionKey,
expectedProjectRef)` in the same module. It shall authenticate the exact
AES-GCM object, reject a foreign source, malformed/truncated/extra archive
bytes, missing parts or mismatched part hashes, then return
`{sourceProjectRef,capturedAt,sourceHashes,parts:{roles,schema,data,migrations},historySchema,historyData}`
with each part and history field a Buffer. The migration part shall decode to
separate `history_schema.sql` and `history_data.sql` bytes
for a later authorized Cloud recovery. The operator runbook shall describe
exact-object retrieval and private ephemeral extraction; no live restore is
part of this pilot proof.

The versioned encrypted object is ASCII `GLBKP001` (8 bytes), a 12-byte IV,
a 16-byte GCM tag, then AES-256-GCM ciphertext authenticated with the magic
bytes as AAD. Plaintext is a four-byte unsigned big-endian JSON-header length,
the UTF-8 JSON header, then raw roles, schema, data, and migrations bytes in
that order. The header has `format: "gymloop-cloud-logical-v1"`,
`sourceProjectRef`, `capturedAt`, `sourceHashes` and `lengths` keyed by those
four part names. The migrations bytes are UTF-8 JSON with base64 `schema` and
`data` fields for the separate migration-history SQL captures.

### HARD-008 — production AAB and physical-device smoke proof

When Android production readiness is assessed, a production-configured signed
AAB and physical-device smoke evidence shall cover startup, authentication,
role boundaries, core check-in, offline/reconnect behavior, appearance, text
scaling, reduced motion, and least-privilege permissions. Play signing,
account access, and upload/publication remain external dependencies and shall
not be simulated.

Acceptance: artifact hashes, device/model/build identity, test steps, and
observed outcomes are recorded; missing physical-device or Play evidence is
explicitly blocked/external.

### HARD-009 — external dependency ledger and no synthetic provider success

When Phase 8 reports a dependency on a provider, legal reviewer, device,
keystore, Play account, cloud backup control, or monitoring destination, the
ledger shall name the dependency, owner, required credential or action, current
status, evidence needed, and next safe step. No synthetic response, mock
provider success, fabricated credential, or local substitute shall discharge an
external dependency.

Acceptance: every external blocker is traceable from the relevant HARD ID and
remains visibly unresolved until real evidence is attached.

## Exit criteria

The change is ready to archive only after each HARD ID has a truthful ledger
entry and focused checks are green where locally executable. External items may
be closed only with their real evidence; otherwise they remain external or
blocked. This contract adds no code, migration, test, provider, legal, device,
or store-upload completion claim.
