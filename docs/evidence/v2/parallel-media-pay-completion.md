# Parallel MEDIA/PAY completion report — 2026-10-04

Coordinator for `docs/planning/v2-fast-agent-media-handoff.md`. Pipeline:
source-blind visible author + independent holdout author + implementer
(holdout-invisible) + screens implementer + test-fixture reconciler + two
fresh critics (source/security r1, rendered r1) + fresh verification critic
(r2). Per owner model policy (2026-10-03), all roles ran as fork agents on the
session model; critics inherited coordinator context — freshness-of-context
is therefore bounded, disclosed here, and mitigated by written-checklist
reviewing. Git commits, pushes, Cloud SQL, deployments and registry edits were
never performed in this chat.

## Status vocabulary applied

- **Authored**: tests written, RED proven, fixture repairs.
- **Built**: source written and locally green.
- **Locally verified**: vitest/tsc/lint/deno check receipts below.
- **Deployed**: nothing (primary-only).
- **End-to-end accepted**: nothing (requires primary + live R2).

## Test-first chain (authored → primary spec: commit → source)

1. Primary committed the gate as `d77ac267 spec: independently require trusted
   private payment proof uploads` (5 visible files + `media-proof-held.test.ts`
   + author reports; 8 files / 1211 insertions).
2. Primary's independent RED receipt (root run, unchanged files): 117 tests,
   65 failed / 52 passed — `scratchpad/media-pay-independent-red-root-20261004.log`.
   Matches visible 39/69 RED + held 26/48 RED.
3. All source followed the commit. No source file was written before RED.

## Built + locally verified (10 source files, 294+/46−)

| File | sha256 (16) |
|---|---|
| packages/shared/src/api/media.ts | f5d2018fc45fefa3 |
| packages/shared/src/api/purchase.ts | def3e07195b354a8 |
| supabase/functions/media/index.ts | c8456e4bc46644f6 |
| apps/web/lib/purchase-http.ts | d4e78416ccb75af9 |
| apps/web/lib/media.ts | b633d5aade5a6c03 |
| apps/web/lib/media-upload.ts | 6ac4d4552cb6c560 |
| apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts | b4f0ea66395c8007 |
| apps/web/app/member/buy/purchase-actions.tsx | 119f216d3728a440 |
| apps/web/app/member/buy/[requestId]/page.tsx | c58d0e90efb03a94 |
| apps/mobile/app/(member)/buy.tsx | 2bf732fde6b91f7c |

Substance: `payment_proof` kind + proof key namespaces in the shared codec;
Edge `proof-confirm`/`proof-url` (caller-RLS request read before any
privileged access; member-creator/tenant/kind binding; If-Match conditional
copy to a fresh private published key; destination recheck; one service
finalizer; loser cleans only its own candidate; ≤60s proof-url; single
external refusal; no secret logging); `purchase-http.ts` stub replaced
(GL126→429, GL086 media_limit→429, 23514 proof_media_refused→422
upload_rejected); `uploadPaymentProof` shared transport (mime/bytes declared,
staging PUT, confirm with read-model revision), wired into
`MemberPurchaseActions` (round 4; no duplicate protocol); `proof-asset` route
envelope unwrap fixed (was reading nonexistent `url` key — byte streaming
could never have worked) + explicit capability forwarding; native accepted
rows: desk reason, upload/re-upload, JPG/PNG/WebP + 2 MB + offline copy,
`expo-network` offline guard, never fakes success.

Photo operations (`confirm`/`member-url`/`staff-url`) behavior preserved;
their publication pipeline was extracted verbatim and shared, verified by
round-2 critic.

## Test results (locally verified, verbatim)

- Focused 8 critic suites (final): **1 failed / 210 passed (211)**; broader
  17-file run after round 3: 329/331; final combined set 302/303. The single
  failing test is the owner-adjudicated "Payment recorded" wording conflict —
  not a screen/source defect.
- Holdout (authored RED): 26 failed / 22 passed (48), file
  `supabase/tests-holdout/media-proof-held.test.ts` sha256 `ee83585e…c4dedc`,
  RED receipt sha256 `23b6ad17…f4fe39`. **Holdouts have not been re-run
  against the finished source by this chat** — the reconciler's contract
  reading says the fixtures should now pass, but execution is the primary's
  step (holdout files were not executed after the last source change here).
- Fixture repairs (test-author-owned, await primary `spec:` commit):
  loser-cleanup fixture made meaningful (winner-key preservation), auth double
  derives identity per request bearer, `MEDIA_KINDS` pin gains
  `payment_proof`, proof-url success fixtures stage `confirmed = true`.
  Repaired files: `purchase-visible-proof-edge.test.ts`
  sha256 `1393acff2fd4e33e`, `media-visible.test.ts` sha256 `e4bee9df3f640aff`.
- Shared/web typecheck clean (2 stale `.next` artifacts only, pre-existing
  route conflict); web lint clean; shared lint shows the 2 pre-existing
  test-file errors; mobile tsc clean; `deno check` exit 0 (2.9.6 via npx from
  `supabase/functions/`).

## Critic verdicts

- Source/security r1: Edge+transport NO-GO (3 HIGH, 4 MED); screens
  GO-WITH-FIXES. `docs/evidence/v2/parallel-media-pay-critic-source.md`.
- Rendered r1: GO-WITH-FIXES (copy truth, disclosure, money formatter, aria
  pass; 3 MINORs). `docs/evidence/v2/parallel-media-pay-critic-rendered.md`.
- Verification r2: all source-side findings CLOSED, ten critical checks PASS,
  **Edge+transport GO-WITH-FIXES → the last named fix (helper wire-or-drop)
  was applied and verified 302/303 in round 4**, **Screens GO**.
  `docs/evidence/v2/parallel-media-pay-critic-source-r2.md`.

## Registry proposals (not applied — primary owns docs/registry.md)

Existing committed tests already reference the shared proof schemas; register
on integration: the proof staging/confirm schema names as exported by
`packages/shared/src/api/purchase.ts`, the `MEDIA_KINDS` extension,
`uploadPaymentProof`, the two new Edge operation names (`proof-confirm`,
`proof-url`), and any new SQL objects the primary's finalizer amendment adds.
No knip ignores, no suppressions, no eslint-disable anywhere.

## Primary integration requests (exact, blocking runtime/live)

1. **SQL (blocks finalization entirely):** amend `finalize_media_asset` for
   member-created `payment_proof` assets + the new published-key regex
   (currently staff-only + old regex → member proof-confirm can never
   finalize). Critic r1 HIGH-1, honestly left open.
2. **SQL:** registration-time request linkage so confirm-time liveness re-proof
   binds to the registered request even on first upload
   (`proofExposure` currently requires `activeProofAssetId` match).
3. **Optional SQL:** extend the authenticated grant with
   `created_by_member_id` if SAFE-select read paths are wanted later
   (Edge deliberately reads privileged; shop.sql:143 grant evidence recorded).
4. **Contract decision:** mime/bytes RPC seam (schema optional, client always
   declares; pin one `register_payment_proof` result spelling).

## Owner decisions outstanding

1. "Payment recorded" wording conflict between
   `purchase-visible-proof-surface.test.tsx` (forbids at
   `payment_proof_uploaded`) and `purchase-visible-member-buy-page.test.tsx`
   (requires as 4-word stepper label) — needs `spec:` adjudication; both
   critics' reading: surface regex over-broad, stage label is contract-true
   (BUY-022 claims vs labels).
2. `expo-image-picker` native dependency (capability-audit rule blocks adding
   it here); native shows honest "upload not available in this build yet"
   until then.
3. LOW: may the verifier re-obtain the proof URL for `recorded`/
   `mismatch_recorded` requests? Currently refused by the bound-path gate.
4. Repo-wide blocker (other agent's uncommitted file): route conflict
   `notifications/[id]` vs `[notificationId]` kills `next dev` boot and web
   `tsc` (generated validators) — blocks ALL live browser verification.

## Live prerequisites and unverified scenarios

Executable checklist: `docs/evidence/v2/parallel-media-pay-live-checklist.md`.
Runs only after the primary reports: source published on `main`, gates green,
protected MEDIA Edge deployment complete, finalizer amendment applied.
Unverified and NOT claimed: real R2 staging PUT/conditional publish/private
GET/refusal evidence, device delivery, populated desk recording journey, all
visual criteria (themes/200%/touch targets at live render), native upload with
a real picker. Nothing here is deployed or end-to-end accepted, and no claim
is made that payment recording works against production storage.

## Report set

progress: `parallel-media-pay-progress.md` · visible author:
`parallel-media-pay-visible-author-report.md` · holdout author:
`parallel-media-pay-holdout-author-report.md` · implementer:
`parallel-media-pay-implementer-report.md` · screens:
`parallel-media-pay-screens-report.md` · test fixes:
`parallel-media-pay-test-fix-report.md` · critics:
`parallel-media-pay-critic-source.md`, `parallel-media-pay-critic-rendered.md`,
`parallel-media-pay-critic-source-r2.md` · checklist:
`parallel-media-pay-live-checklist.md`.
