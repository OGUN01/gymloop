# Fast Agent parallel assignment — MEDIA and PAY uploads

You are the coordinator for one bounded FitCruxx v2 completion task. Complete
the existing photo-upload and private purchase-payment-proof flow through local
verification and fresh independent review. The primary agent retains SQL repairs,
push infrastructure, shared integration, publication, CI and release ownership.
This is a parallel assignment, not a second campaign orchestrator.

## Repository and initial reading

Workspace: `C:\Users\Harsh\Desktop\gymloop`; work against current `main`.
Read, in order, the full `docs/planning/v2-handoff.md`, feature map, campaign goal,
`AGENTS.md`, ADR-176 and ADR-177 in `docs/decisions.md`. Then read this packet,
`docs/architecture.md`, `docs/security.md`, relevant registry entries, the frozen
SHP/MEDIA and member-purchases proposals and their approved amendments, and the
applicable quality bars in `docs/design/v2/`. Inspect Git status and
`git log origin/main..HEAD` before planning changes. Older handoff snapshots are
historical; current source, decisions and hash-bound receipts govern.

Use GPT-6.1 Sol (`gpt-6.1-sol`) for every subagent, as the latest owner override
requires. Keep assignments narrow and avoid repeatedly loading the full campaign.
If this model or independent sessions are unavailable, report that limitation;
do not silently replace the required arrangement with one author/builder.

## Current checkpoint, 2026-10-04

At assignment creation, HEAD is `e8476ee57b219f40eb7f503395540b7555dc2fa3` and
origin/main is `89c6cda33ff87e3f94697190ea03f2e3cb66d122`. Confirm live values;
the primary may add independent tests/source commits while you work.

- Batch-1 and batch-2 base migrations have been applied by CI. Nine later preview
  migrations remain unapplied. The latest full preview ran 147 SQL suites:
  128 passed and 19 failed. Primary is resolving those failures, including
  fixture defects and genuine runtime defects. Do not claim current SQL green.
- Approved Firebase project is `samuraiapi-51996`, display name FitCruxx, account
  `sharmaharsh9887@gmail.com`, Android package `in.fitcruxx.app`. FCM API is enabled;
  credential custody is complete in protected GitHub environment `production-push`.
  Native configuration/channel tests pass 41/41 and the Edge push adapter tests
  pass 141/141. These are local checks, not device delivery or release acceptance.
  Do not modify, recreate or retrieve these credentials.
- MEDIA verifier exists, original production-origin R2 CORS and repository
  credential provisioning are approved/completed. Protected MEDIA Edge deployment
  and real upload/immutable-publication proof remain open.
- PAY application source has bounded fresh review and focused passes. Trusted
  proof confirmation and the separate private `payment_proof` namespace are
  incomplete. Existing MEDIA Edge supports only its original photo operations;
  the approved PAY extension must be completed without broadening those operations.
- WhatsApp release is manual handoff, per the owner-approved amendment. No Meta
  API/WABA setup is required. Do not reopen that scope.
- Owner's USB phone is still occupied by another agent. No device interaction.
- Uncommitted source, holdout and artifact changes from other agents exist.
  Preserve them. No blanket staging, reset, cleanup or overwrite.

## Your implementation scope

Own only the MEDIA/PAY application upload boundary: existing MEDIA Edge verifier,
web upload/confirm/private-proof routes and adapters, and matching member upload
UI/transport on web and native. Reuse the existing registered helpers, storage
protocol, request-authority checks and envelopes. Inspect the frozen contracts
before choosing the smallest complete source repair. Preserve all original
product/trainer/announcement upload and signing behavior.

Required outcomes:

1. An eligible owning member can request a staging upload for a live accepted
   purchase request. The server chooses tenant/kind/object keys. Caller and
   request authorization precede privileged storage access.
2. Proof confirmation uses the existing trusted verifier, correct JWT validation,
   size/type/signature verification, ETag-conditional immutable publication and
   guarded finalization/attachment. No authenticated direct-confirm bypass.
3. Only the owning member and real same-tenant authorized verifier can obtain
   the current private proof URL, no-store and at most 60 seconds. General MEDIA
   signers/catalogue exposure cannot expose proof objects. Do not log URLs,
   tokens, keys or proof contents.
4. Replay, concurrent source replacement, revoked actor, stale request/revision,
   failed verification, unknown commit outcome and losing-candidate cleanup
   retain the frozen safety guarantees. Never delete an uncertain winner.
5. Web/native upload surfaces have usable loading, retry, offline, rejected-file,
   permission and success states. A screenshot is evidence for verification,
   never an automatic claim that payment was received. Preserve money rules.

If completing this requires a SQL, generated-type, shared-config/export, dependency
or workflow change, prepare a separate exact proposal/patch for the primary.
Do not edit those shared files concurrently. Identify every blocked integration
point and continue independent work. Do not invent an RPC, response shape,
permission, retention/legal claim or product decision to make a fixture pass.

## Required independent pipeline

Because this touches identity and money, use separate source-blind visible and
holdout authors, a separate implementer who never reads `supabase/tests-holdout`
or private diagnostics, and fresh blind critics. New tests derive from the
frozen EARS contract. Reuse existing independently authored tests where valid;
new gaps need actual RED before source, not tests written after a repair.

As coordinator, you may inspect holdouts. Do not implement business source after
doing so. Never pass a holdout file, assertion, diagnostic or handoff containing
held details to the implementer. Translate a finding into its public contract
requirement. Test authors own their fixture corrections; builders do not edit tests.

Primary owns the shared Git index and commits. For new tests, save a narrowly
scoped test-ready checkpoint with exact paths, actual RED command/receipt and
hashes in `docs/evidence/v2/parallel-media-pay-progress.md`. Wait for the primary's
recorded test-only `spec:` commit before launching the corresponding source repair.
Continue other already-authorized, already-tests-first work while waiting.
Do not stage, commit, rewrite history or push from this parallel chat.

Run meaningful affected visible/holdout tests, scoped type/lint checks and Deno
checks using the repository's actual import mapping. Request a fresh source/
security critic and, for changed UI, a fresh rendered review against the frozen
bar. Do not add suppressions, knip ignores, weaken assertions or skip requirements.
After three rejections of the same dimension, escalate rather than lower the bar.

## Infrastructure and coordination limits

Never use any Supabase MCP. Correct project is `pecxrpskmfeuyzngvewq`; migrations
are CI-only. Primary alone runs shared Cloud SQL previews and owns
`scratchpad/cloud-run.lock`; do not run Cloud SQL or deploy anything here.
Do not alter database migrations, generated DB types, push/Firebase, wallets,
stock/ledger rules, central registry/decisions/handoff/ledger, seed, navigation,
CI/workflows, release/versionCode or another agent's source. Propose exact shared
changes for primary integration instead. Search registry before new symbols.
No secret output or private key reads. No computer-use skill/native UI; browser
and Playwright are permitted. No ADB, Metro, install, phone or EAS submission.

Prepare executable browser scenarios and a precise live verification checklist.
Real R2/production proof can run only after primary reports the reviewed source
published, all relevant gates green and protected MEDIA deployment complete.
Do not turn this prerequisite into an unsupported acceptance claim.

## Completion report

Keep progress and ready-for-primary checkpoints in
`docs/evidence/v2/parallel-media-pay-progress.md`. Deliver the final bounded report
at `docs/evidence/v2/parallel-media-pay-completion.md`: exact changed paths/source
hashes, test-first commit references, commands/counts/receipt hashes, critic verdicts,
registry/config/SQL proposals, live prerequisites and unverified scenarios.
Distinguish authored, built, locally verified, deployed and end-to-end accepted.
Do not mark all v2 complete. Keep owner messages short and ask only for genuine
new product/authority decisions. Minimize weekly usage with narrow parallel roles,
targeted checks and exact-hash reuse of unchanged proof.
