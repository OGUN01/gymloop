# Screens implementer report — member payment-proof upload surfaces

Round 1: see history below. Round 2 (critic fix round) is current.

## Round 2 — source critic GO-WITH-FIXES + rendered critic GO-WITH-FIXES

Scope honored: only screen files; Edge/transport/shared/migrations untouched.

### Changed files (sha256-16)

- `apps/web/app/member/buy/purchase-actions.tsx` — `194e96dde84ad352`
- `apps/web/app/member/buy/[requestId]/page.tsx` — `c58d0e90efb03a94`
- `apps/web/app/member/buy/page.tsx` — `805b5572bc17d1bc`
- `apps/mobile/app/(member)/buy.tsx` — `2bf732fde6b91f7c` (unchanged from round 1)

### Source critic finding 3 (HIGH) — web upload flow built

`MemberPurchaseActions` now runs the real flow against the landed transport:
hidden `file` input (accept jpg/png/webp) → client preflight (mime in
`MEDIA_MIME_TYPES`, `1 ≤ bytes ≤ MEDIA_LIMITS.maxBytes`; reuses
`purchaseRequestRefusalMessage('upload_rejected')` copy) → POST
`proof-upload-url` `{mime, bytes}` → PUT staging URL with returned headers →
POST `proof-confirm` `{assetId, expectedRevision, commandKey}` where
`expectedRevision` comes from the read model's `acceptedRevision` (passed from
the detail page; the desk flow already used the same field). Staged progress
copy ("Uploading screenshot…", "The gym is checking the upload…"), refusal
messages for every non-ok branch, honest success line ("Screenshot uploaded.
Pending verification — the gym checks the received money."), `router.refresh()`
after attach. No invented envelope parsing: unexpected shapes surface the
generic refusal, never a fake success. Nothing queued offline (BUY-021).

### Rendered critic fixes

1. `StageList` current stage now renders the Chalkline visual mark
   (`<span aria-hidden="true">● </span>` inside the `<strong>`, the
   announcement-card `cl-status` mark convention).
2. `cancelled` state gains honest next-action copy on the detail page:
   "This request was cancelled and nothing was charged. Raise a new request
   any time from the shop, a training programme or your plan."
3. Buy list page "raise a request" guidance reduced to the single
   "Raise a request from" link section; header copy now states the mechanics
   only ("You pay outside the app; the desk verifies the money before your
   purchase counts."); empty state trimmed to "No purchase requests yet."

### Recorded, not fixed (per coordinator)

- The `payment_proof_uploaded` "Payment recorded" test-vs-test conflict stays
  owner-adjudicated; stepper left intact.
- Pre-existing `notifications/[id]` vs `[notificationId]` route conflict
  (another agent's file) now also surfaces as `.next/types/validator.ts` tsc
  errors (`Type '"/member"' is not assignable to type 'never'`) after a dev
  regeneration — primary-owned; my files typecheck clean.

## Test results (round 2, verbatim)

- Two screen files + four sibling suites: **Tests 1 failed | 100 passed (101)**,
  `Test Files 1 failed | 5 passed (6)`. The 1 failure is the owner-adjudicated
  conflict above (unchanged from round 1; not resolvable in source).
- `tsc --noEmit` web/mobile: clean for touched files; web project exit 1 caused
  solely by generated `.next/types/validator.ts` route-conflict errors above.
- Scoped lint: web clean (exit 0); mobile 0 errors + the one pre-existing
  generated `.expo/types/router.d.ts` warning.

## Round 1 (historical)

Changed: purchase-actions.tsx affordance condition + copy; [requestId]/page.tsx
status pass-through; native buy.tsx accepted-row affordance/reason/copy +
offline guard. 7/8 green; native picker dependency recorded as owner decision
(`expo-image-picker` absent; online tap states the gap honestly).

## Dependencies / remaining gaps

- Web/native interactive states beyond the committed static contracts
  (permission flow, retry-on-transport-failure detail) ride on the transport
  implementer's landed envelopes; flows above already consume them defensively.
- Owner decisions: `expo-image-picker` dependency for native upload; the
  "Payment recorded" test adjudication.

## Native picker round (2026-10-04)

- `expo-image-picker@^57.0.20` installed (coordinator, apps/mobile/package.json
  + lockfile only). Native upload wired per owner decision 2026-10-04.
- Changed: `apps/mobile/lib/proof-upload.ts` (NEW — native adapter: declared
  mime/bytes via `purchaseProofUploadUrlRequestSchema`, POST
  `proof-upload-url`, byte-exact read-back check, staging PUT with
  content-type, POST `proof-confirm` with `assetId`/`expectedRevision`/
  `requestId`/`commandKey`; refusals through `purchaseRequestRefusalMessage`;
  honest "Pending verification" success; never reports money truth)
  sha256-16 `030bbb8e4097fcae` — and `apps/mobile/app/(member)/buy.tsx` (proofUpload:
  offline guard FIRST via expo-network, then lazy `import('expo-image-picker')`
  — static import broke the sibling screen test with expo's `__DEV__` global —
  library pick images-only, single selection, cancelled = "No screenshot
  selected." + zero network calls, asset fields null-normalized for
  `exactOptionalPropertyTypes`).
- `onPress` now returns the promise (awaitable flow, no `void` discard).
- Results verbatim: proof-upload file `Test Files 1 passed (1)` /
  `Tests 7 passed (7)` — **both RED-by-design cases green**. Sibling screen
  file green again after the lazy-import fix: `Test Files 2 passed (2)` /
  `Tests 10 passed (10)`. Mobile `tsc --noEmit` clean (exit 0). ESLint on both
  touched files clean (exit 0).
- sha256-16: proof-upload.ts `f97e61c6a49c9e67` (recompute below if needed),
  buy.tsx now `ea390a99035c2b90`.

### Read-model passthrough round (coordinator-approved, same round day)

- Coordinator approved closing the confirm dead-end. Verified: NO committed
  test pins `acceptedRevision` (grep over packages/shared/src/api/__tests__
  and mobile tests: no matches) — took the no-pin branch: smallest additive
  read-model passthrough, no new test authorship, no invented source.
- Server truth checked: `pay_request_json` (uncommitted PAY migration,
  read-only reference) already emits camelCase `acceptedRevision`
  (uuid or stripped-by-`jsonb_strip_nulls` when unaccepted) — the mobile
  read path consumes that same key, so passthrough = admitting the field in
  the shared row model.
- Changes: `packages/shared/src/api/purchase.ts` —
  `purchaseRequestRowSchema` gains `acceptedRevision: id.nullable().optional()`
  (additive; mirrors the canonical web mapper `acceptedRevision:
  source.accepted_revision` at apps/web/lib/purchase.ts:37; strictObject
  keeps it once parsed) sha256-16 `22df42d99f7ae565`;
  `apps/mobile/app/(member)/buy.tsx` — `UploadRow.acceptedRevision` widened
  `| undefined` for `exactOptionalPropertyTypes` against the shared type
  sha256-16 `f4bc24ad13f29f03`; `apps/mobile/lib/proof-upload.ts` unchanged
  (already carried `expectedRevision` into the confirm body) sha256-16
  `030bbb8e4097fcae`.
- Verification verbatim: 4 files → `Test Files 4 passed (4)` /
  `Tests 54 passed (54)` (proof-upload 7, native screen 3, shared contract,
  proof media). Mobile `tsc --noEmit` exit 0; shared `tsc --noEmit` exit 0;
  ESLint on all three files exit 0.
- Honest limits: rows still only carry `acceptedRevision` when the mobile
  read parse of `pay_request_json` output succeeds for the whole row
  (broader row-shape integration outside this directive); when absent,
  confirm honestly refuses server-side — no fake success.
