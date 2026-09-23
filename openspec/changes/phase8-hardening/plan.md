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

### HARD-006 — DPDP export, erasure, and retention runner

When the DPDP operational runner executes, it shall produce an auditable export
or erasure result, apply the existing owner-approved retention durations and
legal-hold behavior, and preserve a safe record of what was retained, blanked,
deleted, or refused. It shall not invent, shorten, or extend a duration without
an owner-approved contract change. Legal review and sign-off remain external
and are recorded as external until actually obtained.

Acceptance: focused runner checks cover export, erasure, retention, and hold;
legal approval is never represented by a local test result.

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
