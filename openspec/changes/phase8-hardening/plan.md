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

When k6 load or isolation testing runs, it shall target an explicitly separate
non-production Supabase project with non-production credentials and test data.
If that separation cannot be positively verified before execution, the test
shall fail closed and no load run shall be reported. The run shall cover the
100-gym × 500-member morning check-in spike and tenant isolation assertions.

Acceptance: the environment identity, safety preflight, workload, thresholds,
and raw/result artifacts are recorded; production is never used as a load
target.

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
