# Isolated Phase 8 load test

This procedure is for HARD-004. It must never target the production Supabase
project `pecxrpskmfeuyzngvewq` or reuse production credentials or member data.
No result is a pass unless the raw k6 artifact and both tenant-isolation probes
are retained.

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
- `PHASE8_LOAD_TENANTS_JSON` (the 100 × 500 synthetic fixture)

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
