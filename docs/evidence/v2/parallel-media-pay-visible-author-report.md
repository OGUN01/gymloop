# Visible test author report — PAY MEDIA proof extension

Role: source-blind visible test author. All assertions derive from the frozen
contracts: `openspec/changes/member-purchases/proposal.md` (BUY-008/009/010/
011/018/021/022, proof media extension paragraph, transport mapping),
`openspec/changes/v2-batch2-shared/media-verification-amendment.md`,
`docs/design/v2/pay-bar.md`, registry rows for MEDIA/PAY. Existing committed
visible suites were read for conventions only. No implementation source, no
holdout files, no scratchpad, no migrations were read.

## New files (5, all untracked, nothing staged or committed)

| Path | Tests | sha256 (first 16) |
|---|---|---|
| `packages/shared/src/api/__tests__/purchase-visible-proof-media.test.ts` | 12 | `77e1bd233526b4d1` |
| `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts` | 42 | `cf7880cddc252dcb` |
| `apps/web/app/__tests__/purchase-visible-proof-upload.test.ts` | 7 | `28d5d9da20ad6a0b` |
| `apps/web/app/__tests__/purchase-visible-proof-surface.test.tsx` | 4 | `bd65b1b31ff4c212` |
| `apps/mobile/lib/__tests__/purchase-visible-native-proof-upload.test.tsx` | 4 | `212fbfed85670804` |

Full sha256:
- `77e1bd233526b4d187efb4d3926ee0fe668e967ad43aa6b54923c101df8949c7`
- `cf7880cddc252dcbdc0acd443f8d811a3fd18b14e6823f5cf6c7f5ee99663312`
- `28d5d9da20ad6a0bc099d7f09cde0a07cc4b1c800dddc03df11dcf8724962c5c`
- `bd65b1b31ff4c212c29a1269b3f9530ced7f91f3932c2c91c33340d0d9d83b73`
- `212fbfed8567080447b9bd7a857a4c9740b85441256c490bdf96b901bdb0b255`

## RED receipt

Command (repo root):

```
pnpm vitest run packages/shared/src/api/__tests__/purchase-visible-proof-media.test.ts apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts apps/web/app/__tests__/purchase-visible-proof-upload.test.ts apps/web/app/__tests__/purchase-visible-proof-surface.test.tsx apps/mobile/lib/__tests__/purchase-visible-native-proof-upload.test.tsx
```

Verbatim counts: `Test Files  5 failed (5)` / `Tests  39 failed | 30 passed (69)`.
Per file: shared 4 failed / 8 passed; edge 24 failed / 18 passed; route 4
failed / 3 passed; web surface 3 failed / 1 passed; native 4 failed / 0 passed.
The 30 passing are regression pins of behavior the contract requires to
survive the extension (photo kinds, signature check, refusal-copy hygiene,
proof-url result stripping, existing status copy).

## What each RED block requires (public contract level)

Shared boundary (`purchase-visible-proof-media.test.ts`):
1. `payment_proof` must join `MEDIA_KINDS`; photo MIME family, extension map,
   `matchesImageSignature` and the 2 MiB ceiling (`BUY_LIMITS.proofMaxBytes`
   equals `MEDIA_LIMITS.maxBytes`) stay unchanged.
2. `buildMediaObjectKey`/`parseMediaObjectKey` must round-trip
   `<tenant>/{staging,published}/payment_proof/<uuid>.<ext>`; malformed
   namespaces still refuse.
3. `purchaseProofConfirmRequestSchema` admits exactly asset + revision +
   command key (request id optional); no client storage authority field.
4. `purchaseProofUploadUrlRequestSchema` must never admit a client-chosen
   object key, tenant or ETag.
5. `purchaseProofUrlResultSchema` strips `object_key`/`published_etag` and
   exposes exactly requestId/proofId/assetId/url/expiresAt.
6. BUY-022 copy: upload CTA says screenshot, pending-verification label, no
   "payment successful"/"bank verified"/automatic settlement.

Trusted Edge boundary (`purchase-visible-proof-edge.test.ts`, fake
Auth/PostgREST/R2 transport in the established suite style):
1. `proof-confirm` and `proof-url` are admitted extension operations on the
   same endpoint (currently refused as unknown operations).
2. Owning-member proof-confirm: caller-token request/asset exposure read
   strictly precedes any privileged (service-key) access and any R2 traffic;
   ranged If-Match source GET with magic check; conditional
   (`x-amz-copy-source-if-match`) copy to a fresh
   `<tenant>/published/payment_proof/<uuid>.<ext>` distinct from the staging
   key; post-copy If-Match recheck; exactly one service-key
   `finalize_media_asset` carrying tenant, `payment_proof` and the member
   actor; success envelope `{ assetId, confirmed: true }`; no-store.
3. Refusals with zero storage/finalizer traffic: unexposed request, foreign
   tenant, deleted asset (single external 404 `asset_not_found`); trainer,
   impersonation, invalid token (403); extra request fields (400, the frozen
   exact-body rule carries over).
4. Failure matrix fails closed without finalization or any money-side write:
   missing staging 409 `upload_missing`; changed source 409 `upload_changed`
   (GET and copy legs); wrong size/MIME/magic 422 `upload_rejected`;
   published-verification failure 500 `storage_unavailable`.
5. A staging key outside the payment_proof namespace is refused before any
   storage access.
6. Confirmed replay succeeds with no recopy and no second finalization;
   losing finalizer deletes only its own unreferenced candidate and preserves
   the winner; unknown finalizer outcome retains the candidate (never deletes
   on an unconfirmed reread); rejected verification cleans through the
   unconfirmed-only caller command, never a trusted row write.
7. `proof-url` returns only `{ imageUrl }` for the owning member and the real
   same-tenant front-office verifier; signed URL is published-payment_proof
   only, never staging, with signed expiry ≤ `BUY_LIMITS.privateProofGetTtlSeconds`
   (60s); trainer/impersonation/foreign member refused without storage.
8. The generic member photo signer (`member-url`) can never expose a
   `payment_proof` object even when a catalogue exposure would match.
9. Error output and logs never contain the credential, staging key or signed
   capability. Original photo operations (`confirm`/`member-url`/`staff-url`)
   stay admitted; undefined operations still refuse.

Web transport (`purchase-visible-proof-upload.test.ts`):
1. Member proof-upload-url grants a staging-only PUT bound to
   `/staging/payment_proof/`, never `/published/`, with 300s presign expiry,
   an `assetId`, and no `object_key`/ETag metadata; registration goes through
   the `register_payment_proof` registration boundary.
2. `P0002` → 404 `request_unavailable` without a capability; `GL126` → 429
   `rate_limited` without a capability; signing failure → 500 with no raw
   credential echo; staff actor → 403 before body; client-supplied object key
   → 400 before registration.

Member surfaces (`purchase-visible-proof-surface.test.tsx`,
`purchase-visible-native-proof-upload.test.tsx`):
1. Accepted request offers the upload with honest pending-verification copy;
   affordance names JPG/PNG/WebP and the 2 MB cap before upload (web + native).
2. Rejected proof shows the exact desk reason and a re-upload path (BUY-011).
3. Uploaded-but-unverified stays "Pending verification" with no payment claim.
4. Native offline blocks the upload with a clear error and never queues a fake
   success (BUY-021).

## Seam assumptions the implementer/primary should sanity-check

- The Edge proof-op request body is pinned to the frozen exact
  `{ operation, assetId }` shape (request context resolved server-side from
  the registered asset), consistent with the approved amendment's body rule.
- The route-level mock feeds `register_payment_proof` a
  `{ asset_id, staging_object_key }` result — the registry describes the RPC
  as "member proof registration with server-generated staging key"; if the
  committed RPC returns a different shape, that fixture is a `spec:` item,
  not an implementer edit.
- The member buy detail page render path was reused from the committed
  member-buy-page suite's mock seams.

No source files, tests of other agents, registry or decisions files were
touched. Nothing committed.
