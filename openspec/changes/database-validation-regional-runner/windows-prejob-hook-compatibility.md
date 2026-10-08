# Windows pre-job hook compatibility — frozen repair

The owner resumed the performance follow-up on 8 October: make future checks substantially faster while preserving validation. Version6 is already available to testers and requires no further Play action. This repairs the existing DBV-008 execution contract; it does not reduce the suite, change a database assertion, extend a deadline or add a paid/permanent runner.

## Concrete failure and reference

Actual trial16, DB37822050096/attempt1/source db8715c0f5e20b34f753652cc01b0b4d94566872, selected ephemeral Windows runner37. Its native job113466344205 failed in Set up runner because GitHub rejected C:/fr-sealed-20261007/hook.cmd as an unsupported script extension. Checkout, adapter setup, arming and full native validation were skipped. The guardian failed while seeking an armed receipt; its database link/restoration and the dependent seed were skipped. Preserve these failures and their cleanup evidence; they are not suite failures or speed measurements.

The comparable contract is [GitHub's pre-job script documentation](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/run-scripts): PowerShell scripts use .ps1 and are invoked synchronously through pwsh or powershell. A nonzero exit prevents the job from proceeding. The accepted original Node hook and guard remain byte-identical and retain their ten-second bound.

## Repair requirements, fixed before tests and implementation

- WHEN the Windows runner invokes its pre-job script, THE SYSTEM SHALL use a sealed .ps1 entry point outside the checkout and runner package, compatible with the documented dot-source invocation in Windows PowerShell and PowerShell7.
- WHEN that entry point runs, THE SYSTEM SHALL invoke the existing approved C:/Program Files/nodejs/node.exe with the unchanged sibling hook.mjs and exactly the sibling guard.mjs and binding.json absolute arguments. Resolve siblings from the entry point's own directory, not the caller's current directory. The production directory remains C:/fr-sealed-20261007 under its existing trusted ACL and source pins.
- WHEN the unchanged Node hook succeeds, THE SYSTEM SHALL preserve its zero exit and existing generic acceptance output. IF startup, binding or guard validation fails, THE SYSTEM SHALL preserve a nonzero exit and prevent checkout. The bridge shall add no secret/fixture logging, environment lookup, fallback executable, child retry or new timer.
- WHEN the guard stalls or rejects, THE SYSTEM SHALL retain the original hook's ten-second child bound and exact-child termination. The original Node hook, guard, constants, predicates, watchdog, publisher and registration lifetime shall remain unchanged.
- WHEN preparing a fresh trial, THE SYSTEM SHALL pin the .ps1 bytes before configuration and point only that fresh runner's ACTIONS_RUNNER_HOOK_JOB_STARTED at the .ps1. The consumed .cmd, all prior packages/evidence and original custodian deadlines shall remain intact. Any subsequent wrapper/path/digest rebinding must be declared mechanically before materialization.

## Tests, closure and measurement

Independent visible and holdout authors receive these requirements before the bridge exists, inspect neither bridge implementation nor each other's suite, and use only controlled temporary files/processes. They may copy the already accepted Node hook as an opaque fixture; they must not read private assertions, access credentials or invoke a database/provider operation. Verify documented invocation, paths with spaces and a different current directory, exact argument order, success, rejection, missing startup dependency and the original bounded stalled guard. Test files are author-owned and committed red before implementation. Preserve both PowerShell versions' actual results and generic output checks.

Before a fresh shared-project trial, finish trial16's independently verified allocated-worker teardown through the existing verifyNativeWorkloadTeardown boundary and append its genuine receipt once to the completion index. No hosted precheck classifier or fake restoration proof applies to this failure.

After local tests and a fresh source critic pass, conduct one fresh complete regional trial with the accepted matching-input baseline:163 files/16,329 assertions, native7956936ms. Require genuine checkout raw-byte identity, exact per-file plans/timers, canonical private-output acceptance, restoration/guardian/serial seed/drift and physical cleanup. Only a complete measured improvement qualifies as performance completion. Keep hosted fallback and existing UI-only/types-only selection behavior. Save a repeatable future-run procedure and archive only after full acceptance.
