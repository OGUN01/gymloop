## Why

The accepted full database gate takes 130 minutes 32 seconds for 161 files and 16,156 assertions, delaying reliable feedback and the next closed-test release. The owner authorized completing the saved faster-validation follow-up, but a speed claim requires a complete measured comparison with unchanged correctness checks.

## What Changes

- Add a small, fail-closed wrapper around the retained Supabase CLI 2.110.0 / official pg_prove 3.36 client. Keep the full visible/holdout manifest, native verdict, rollback guard, serialized CI migration path, drift and seed proofs.
- Record exact source/schema/test identities, every file's literal plan and hash, native raw output and per-file durations. Generate only an allowlisted reporting `.proverc`; do not edit existing SQL fixtures or assertions.
- Capture the original role-global timeout, restore and verify it after native success or failure, and retain a receipt for an independent GitHub-hosted cleanup guardian if the regional runner is lost.
- Prefer a single trusted-main CI job on the owner's existing Windows host/Docker Desktop client, conditional on an independent pinned-client mount/network/reporting smoke. Register it ephemerally, give it a unique OS-aware job label, and deregister/stop it after that job or its four-hour lifetime. It is not a daily-desktop runner service or a local database. The inspected WSL environment has no Node and disabled Docker integration; changing WSL/Docker settings is outside this plan.
- Keep the ordinary GitHub-hosted path as the default/fallback. If the existing environment is unsuitable, a four-hour Mumbai Lightsail trial is a separately authorized alternative requiring account/access and a spending decision.
- Prove native client `.proverc` consumption and failure discrimination independently before a serialized matching-input Cloud benchmark. Report measured improvement honestly; an unchanged/slower run does not complete the performance objective.

Out of scope: changing business behavior, assertions or SQL fixture bytes; applying migrations outside CI; a Docker/scratch database; PR execution on a self-hosted runner; a permanent desktop service; an autoscaler; changing TAP transport/parser authority; reducing the release manifest; nightly-only coverage; and Play publication implementation in this unit. A transport replacement still needs an explicit ADR-177 amendment.

## Capabilities

### New Capabilities

- `database-validation-runner`: Complete native database validation with verified manifests, reporting, restoration and a bounded optional regional CI execution path.

### Modified Capabilities

None. Existing domain requirements and SQL suites remain unchanged.

## Impact

Potential implementation surfaces are `scripts/pgtap/`, `.github/workflows/db.yml`, independent synthetic harness tests, and registry/evidence documentation. No application source or migration is required. The protected operational procedure is [runbook.md](runbook.md); the frozen public interface is [design.md](design.md).

The baseline and authorization evidence are [the saved performance plan](../../../docs/planning/v2-database-validation-plan-2026-10-06.md), [the current continuation](../../../docs/planning/v2-database-and-vc6-release-2026-10-07.md), and ADR-177 in [decisions.md](../../../docs/decisions.md). The historical baseline is not relabeled as coverage of a changed harness or the later Shop manifest. This change is planning only until the root reviews/freezes this contract and fresh independent tests land first.
