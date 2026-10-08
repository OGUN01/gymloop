# Faster checks for future FitCruxx changes

Owner request, 9 October2026: shorten development feedback without losing database, tenant, money or identity validation. The tester build is already version6 and available. This follow-up changes the validation machinery, not the released application.

## Choose the smallest relevant feedback loop

1. Freeze the requirement and reuse existing registry entries before implementation. Keep independent visible/holdout authors for silent failures. Commit tests first and implementation separately; push the coherent locally green unit once.
2. During implementation, run the affected tests and relevant lint/type checks. Use one worker on a resource-constrained Windows host. Do not repeatedly run the complete application or database suite after unchanged inputs have already passed.
3. UI/docs changes retain the existing database exclusion. Generated-types-only changes retain schema drift without the full pgTAP sweep. Migrations, SQL tests, database functions or harness/workflow changes still require complete database validation. The PowerShell pre-job entry is included explicitly in both existing workflow filters.
4. Keep the one shared-project database concurrency group. Do not overlap migrations, seed replay or full sweeps. Do not run a separate hosted baseline when an accepted complete matching-input run already exists.

## Complete database validation

The accepted current full baseline is DB37775385597/attempt1:163files,16,329assertions, zero failures, native7,956,936ms (about133minutes). A regional runner is still undergoing acceptance; no faster measured result is claimed yet. It uses the same Supabase CLI, official pg_prove client, sequential SQL files, rollback requirements, native verdict, timeout restoration, hosted guardian, schema drift and serial seed proofs.

Before registering the single-job Windows runner, verify current source binding, complete manifest/input equivalence, previous recovery/teardown receipts, no competing database job, actual Docker/client responsiveness and enough host resources. Check the official package, protected paths and supported `.ps1` hook before dispatch. Keep historical failed packages and original custodian deadlines intact.

Use fresh short runner/work directories on D: only after their NTFS, no-reparse and trusted-access checks. Protected evidence and tools stay on their approved C: paths. Moving checkout files does not move Docker storage or solve a shortage of memory.

The hook's active deadline is nine seconds with termination headroom inside the unchanged ten-second physical admission limit. Reject late success using a monotonic clock. Require both independent process contracts to pass with observed exact-child closure and no survivors. A failed startup check ends that admission; preserve it and resolve the concrete failure before another attempt.

Arm the bound readiness operator before registering/starting the runner. Its actual receipt must precede the wrapper. Publish only through the existing bound publisher and only during the original live selector/lifetime window; no copied readiness records, late retries or deadline extensions. Keep hosted fallback available when readiness is unavailable.

Completion requires the actual complete native receipt, per-file plans/timers, private-output verification, exact timeout restoration, guardian, serial seed/drift, runner deregistration and process/container cleanup. Compare the genuine elapsed time with the matching baseline before adopting the faster route. Save the exact source/run/attempt and failure evidence; never label an unfinished or failed trial a speed improvement.

## Current implementation checkpoint

The unsupported `.cmd` startup entry caused trial16 to stop before checkout; canonical teardown and the once-only outside index publication are complete. All six independent suites now pass:13visible and12held deadline cases,25visible and23held classifier cases, and13visible and14held physical PowerShell cases across both Windows hosts. The original11.2781ms physical overrun and later fixture failures remain preserved. Relevant lint, shared types, registry, escape-hatches,163-file rollback and whitespace gates pass. The fresh source critic accepts the supported bridge and monotonic deadline correction. The full regional benchmark and adoption/archive remain pending. See `v2-database-and-vc6-release-2026-10-07.md` and the active OpenSpec change for exact evidence.
