# Proposed one-time owner configuration recovery

**Owner approved the one-time CI reset on 2026-10-09**, replying “Approve the one-time CI reset” to this exact proposal. This authorizes preparation, independent tests, implementation and the one exact CI configuration action below. The existing DBV-006/007 recovery rule remains enforced until the reviewed narrow amendment is implemented and actual independent configuration evidence is accepted. Approval does not certify restoration, permit a repeat reset or complete the performance goal.

Approval metadata: questionItemId `["request_user_input_async","call_37c378f02146450db1b1f343523b62c9",0]`; direct owner reply `Approve the one-time CI reset`; date2026-10-09. The exact question was: “The earlier failed run has no saved cleanup receipt, so the existing recovery rule blocks another full database check. May I use CI to set and independently verify the last proven two-minute database timeout, record it as an owner-approved new baseline, and continue testing? The old run will stay recorded as failed.” It linked this exact proposal. No administrator/UAC journal authorization is inferred.

Trial19 (DB37857261809/attempt1/source8072af53493867a093ea128dc306f375d3ca1789, native113584968728/runner39) failed without a retained original-timeout receipt. Exact physical teardown is independently accepted and outside index13 is preserved. Missing files and current values cannot prove its unknown historical original. The CSV disk-history approach was closed unexecuted because it cannot establish exhaustive historical coverage. Do not fabricate restoration or relabel the failed run.

The last completed release's independently verified configuration was a present postgres role-global statement_timeout of **2min**, verified2026-10-08T14:31:34.343Z after successful full validation. Evidence: docs/evidence/v2/database-release-acceptance-2026-10-08.json, full DB37775385597. This is a known prior configuration, not proof of trial19's missing original.

## Concrete requested action

With explicit owner approval, implement one narrowly bound CI configuration-maintenance action for that exact historical tuple. Use only projectpecxrpskmfeuyzngvewq, rolepostgres and parameterstatement_timeout. Under existing db-main serialization and pinned CLI, capture the current configuration, set the role-global timeout to the owner's chosen **2min** baseline, and independently re-read and verify that exact configured state. Retain official run/job/source/artifact provenance and failed history. No migration, table data, application feature, test SQL, generated type, device install or Play release changes are included.

Record this as **owner-authorized configuration re-establishment**, never as successful restoration of the unknown original. A separately verified typed receipt may discharge only this tuple's outstanding recovery block after the original physical closure is freshly confirmed. All unrelated historical attempts, future capture/restore requirements, outside-worker recovery receipts, fail-closed preflight checks and complete native/holdout coverage remain mandatory. There is no automatic fallback or general permission to guess an original timeout.

### Proposed EARS amendment

WHEN the owner explicitly approves re-establishing the known2min configuration for the exact failed trial19 tuple, THE SYSTEM SHALL permit only the serialized CI maintenance action and independent configured-state verification described above, SHALL retain the historical attempt as failed with original restoration unverified, and SHALL reject every wrong identity, incomplete/expired proof, missing physical teardown, failed configuration/verification or unapproved target before accepting its one-time baseline receipt.

WHEN that one-time owner-configured baseline is independently verified, THE SYSTEM SHALL permit a fresh full validation with a newly captured original and unchanged native test authority; it SHALL NOT infer the historical original, publish a fabricated restoration receipt or reduce any assertion/deadline/cleanup check.

Independent visible/holdout tests must be written and committed red before implementation; a fresh critic and exact-head gates precede the sole CI maintenance dispatch. Only after verified configuration and physical cleanup may a fresh regional full benchmark start. No faster full result or completion is claimed by this proposal.

Concrete implementation and mechanical test-port draft: [trial19-owner-timeout-baseline.md](../../openspec/changes/database-validation-regional-runner/trial19-owner-timeout-baseline.md). Root must freeze it before independent authors start; the declaration is not implemented evidence.
