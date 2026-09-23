# Phase 8 load test

This procedure is for HARD-004. The original isolated route still refuses the
linked project. ADR-162 adds an explicit prelaunch-shared route on the existing
Cloud Supabase project because the owner confirms there are no live customers.
Neither route may use a pre-existing demo or pilot identity as a load fixture.
No result is a pass without raw k6 evidence, both isolation probes, a live size
observer, and exact cleanup.

## Owner-authorized linked-Cloud route

The linked target is `pecxrpskmfeuyzngvewq`. Before a write, record the
configured and independently observed API and Supabase project identities,
the owner's no-live-customer assertion, and a linked CLI database-size result.
`scripts/phase8-prelaunch-load-safety.mjs` requires
`PRELAUNCH_SHARED_LOAD_APPROVED` and a current reading below 400,000,000 bytes
against the recorded 500,000,000-byte Free quota. Record a p95 budget before
the run. The fixture must have a fresh `PHASE8-LOAD-<UUID>` marker, 100 newly
created gyms, 500 owned synthetic members and one genuine staff bearer token
per gym. Write exact database and Auth identities to gitignored recovery
manifests before staging; an interrupted operation must resume cleanup from
those manifests. Keep the source's existing demo and staged pilot records out
of the fixture and check their baseline again after cleanup.

Run the Cloud size observer at intervals no greater than 60 seconds throughout
staging and k6. Abort if collection fails, the observer stops, or the database
reaches 400,000,000 bytes. Do not let the Free project reach its read-only
limit, which could also block cleanup. The current validator and k6 fixture
transport are checked in, but the Cloud fixture staging, live observer and
recovery runner are still being completed; no 50,000-request run has occurred.
Do not invoke k6 until those pieces and an exact-ID cleanup rehearsal pass.

For this route set `PHASE8_LOAD_MODE=prelaunch-shared`,
`PHASE8_LOAD_CREDENTIAL_KIND=prelaunch-shared`,
`PHASE8_LOAD_CONFIRMATION=PRELAUNCH_SHARED_LOAD_APPROVED`, and
`PHASE8_LOAD_NO_LIVE_CUSTOMERS=true`, with all four configured/observed/credential
project references matching the linked ref. The k6 fixture is a private local
JSON file, supplied by its **absolute** `PHASE8_LOAD_FIXTURE_PATH`; k6 resolves
relative `open(...)` paths from the script directory. Keep that file, the
baseline and cleanup manifests, and raw results under the ignored
`artifacts/phase8-load/` directory. The JSON has a `gymFixtures` array of
`{ gymId, token, memberIds, ownedMemberIds }`. No bearer token, member ID,
password, service key or fixture contents goes into the command line, Git or
the evidence ledger.

After k6, verify exactly 50,000 persisted synthetic attendance rows, the raw
success count and p95, foreign-read invisibility and a non-2xx foreign mutation.
Delete only the manifest's synthetic rows and Auth identities, then prove zero
synthetic remainder and unchanged pre-existing baseline. A green k6 report with
missing monitoring or cleanup is blocked under `summarizePrelaunchResult`.

## Original isolated-project route

## Preconditions

1. Provision a distinct non-production Supabase project and a deployed Gymloop
   API that is positively observed to use that project.
2. Create exactly 100 non-production gyms with 500 synthetic members each.
   Keep fixture tokens outside Git and the evidence directory.
3. Choose and record a positive p95 budget before the run.
4. Choose a non-secret fixture path and raw JSON result path. The paths may be
   recorded; their credential-bearing contents must not be committed.
5. Record the configured project reference and the independently observed API
   and Supabase project references. All must match.

## Fail-closed preflight

Prepare a local, gitignored JSON configuration matching the canonical HARD-004
interface in `openspec/changes/phase8-hardening/plan.md`. Run:

```text
node scripts/phase8-load-safety.mjs <reviewed-config.json>
```

The preflight must refuse missing or mismatched identity, the production
reference, non-HTTPS/non-origin URLs, missing approval, weak credentials,
duplicate gyms/tokens/members, cross-owned members, a missing p95 budget, or a
missing fixture/result path. Its printed metadata contains no bearer tokens.

## Execution

The root `k6` npm development dependency is only the module manifest used by
static dependency analysis; it does not install the k6 executable. Install and
record the approved standalone k6 binary before running this procedure.

Inject these values through the operator's secret mechanism, never a committed
file or shell history:

- `PHASE8_LOAD_PROJECT_REF`
- `PHASE8_LOAD_OBSERVED_API_PROJECT_REF`
- `PHASE8_LOAD_OBSERVED_SUPABASE_PROJECT_REF`
- `PHASE8_LOAD_CREDENTIAL_PROJECT_REF`
- `PHASE8_LOAD_CREDENTIAL_KIND=non-production`
- `PHASE8_LOAD_CONFIRMATION=NON_PRODUCTION_LOAD_APPROVED`
- `PHASE8_LOAD_API_URL`
- `PHASE8_LOAD_SUPABASE_URL`
- `PHASE8_LOAD_SUPABASE_ANON_KEY`
- `PHASE8_LOAD_P95_MS`
- `PHASE8_LOAD_RUN_ID` (a fresh UUID)
- `PHASE8_LOAD_FIXTURE_PATH` (absolute path to the gitignored 100 × 500 JSON fixture)

Execute only the credential-free command returned by the preflight, equivalent
to:

```text
k6 run --out json=<raw-result-path> tests/load/phase8-morning-checkin.js
```

The scenario maps 100 virtual users to 100 distinct gyms and 500 iterations to
their 500 members. It also runs cross-tenant read and mutation probes. Any 2xx
mutation response, visible cross-tenant row, failed check, or exceeded p95
budget fails the run.

## Evidence and cleanup

Record the commit, UTC time, non-production project reference, API origin,
approved p95 budget, k6 version and command, raw-result checksum, measured p95,
50,000 completed check-ins, read-denial result, mutation status, and cleanup
result in `docs/evidence/phase8/ledger.md`. Never record tokens, member data, or
the fixture JSON. Delete the synthetic tenants and revoke fixture credentials
after evidence capture.

Until every precondition exists and the run is executed, Gate 27 remains
**Partial / External**, not Passed.
