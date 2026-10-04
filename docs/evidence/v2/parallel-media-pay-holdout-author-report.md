# Holdout author report — PAY MEDIA proof extension

File: `supabase/tests-holdout/media-proof-held.test.ts`
sha256: `ee83585eb207cb1563293de7d67b74440ed3c75c2f5abbb10c9c3d2945c4dedc`

RED command:
`pnpm exec vitest run supabase/tests-holdout/media-proof-held.test.ts --maxWorkers=2`

RED receipt (verbatim): `Test Files  1 failed (1)` / `Tests  26 failed | 22 passed (48)`
Receipt sha256: `23b6ad17c040e8cefaf4379af82f84967a380d997d8ab6f4110298dfc5f4fe39`

All 26 failures share one contract-level cause: the current Edge source answers
`proof-confirm` / `proof-url` with 400 `invalid_request` (unknown operation), so
every requirement the frozen proof media extension imposes is unmet. The 22
passing cases are contract-required armor pins that already hold (auth-first,
strict shape, impersonation/trainer/staff refusal, no money RPC inside the
boundary, unknown-field rejection).

Public-contract topic labels (assertion bodies stay in the test file):

- Identity/shape armor: auth precedes parsing; fixed `{operation, assetId}`
  envelope; injected tenant/request/actor/key fields refused; impersonation,
  preview, staff and trainer roles never reach proof confirmation.
- Confirm ordering: caller-JWT live-owned-accepted-request proof precedes any
  privileged read or R2 access; closed/unavailable requests refuse before
  privileged access; superseded/rejected/bound/absent dispositions never
  confirm; foreign owner and unknown asset share one indistinguishable 404;
  non-`payment_proof` assets never ride the proof boundary.
- Confirm pipeline: HEAD/ranged-GET/If-Match source verification, conditional
  copy into `<tenant>/published/payment_proof/<fresh>.<ext>`, destination
  recheck, exactly one service-role finalization with the member actor (never a
  staff actor); no client-usable PUT ever targets the published namespace.
- Fail-closed matrix: upload_missing/upload_changed/upload_rejected/
  storage_unavailable outcomes per frozen mapping; unconfirmed-only cleanup;
  never deletes a published object on failure.
- Replay/races: confirmed replay never recopies and still revalidates; unknown
  finalizer outcome retains the candidate (no rollback assumption);
  authoritative same-candidate winner is kept; concurrent winner preserved and
  the loser cleans only its own candidate; revocation at the locked finalizer
  never finalizes.
- Private URL: owning member and real same-tenant front-office verifier only;
  TTL > 0 and <= 60 s; no-store; no staging path, etag or storage key in any
  body; trainer refused; revoked/unbound actor refused; foreign/unknown/
  superseded/closed share the single `asset_not_found`; the general
  `member-url` and `staff-url` signers can never expose a `payment_proof`.
- Hygiene: no money command ever dispatches inside the MEDIA boundary; staging
  failure changes nothing.

Fixture note: the simulated request-truth RPC payload is contract-shaped
(live owned accepted request, one active proof). If a frozen public RPC shape
differs, the holdout author owns the fixture correction — never the builder.
h79 was not opened. No visible suite, implementation, apps/, packages/ or
supabase/functions/ file was read.

## Fixture repair round 1 (2026-10-04, per diagnosis F1–F6)

File sha256 after repair: `efe987d259a2feb9939815ba220fc262715a6bafcd00e3dea5ca2af426021e99`

Re-run command:
`pnpm exec vitest run supabase/tests-holdout/media-proof-held.test.ts supabase/tests-holdout/media-edge-held.test.ts supabase/tests-holdout/media-confirm-uuid-held.test.ts --maxWorkers=2`

Receipt (verbatim): `Test Files  1 failed | 2 passed (3)` / `Tests  3 failed | 98 passed (101)`
Receipt sha256: `0004170042b31ad437cfe7da625d5face706018d556778040a379000a3a0a9db`

Repairs applied (fixtures only, no source edited):
- F1: privileged service asset read now honours the PostgREST `id=eq.<uuid>` filter.
- F2: copy handler records the published object so the mandatory post-copy
  recheck (amendment §3) succeeds.
- F3: caller-scoped asset read returns the frozen safe projection row (no keys
  or ETags); removed the object-as-status-arg call.
- F4: request-truth payload now uses the frozen `{requests:[...]}` camelCase
  reader projection (`requestId`, `status`, `memberId`, `activeProofAssetId`).
- F5: sign envelope pinned as `{ imageUrl }` with `X-Amz-Expires` TTL ≤ 60.

F6 amendment applied as directed: the confirm-side foreign/unknown test now
pins the achievable contract — authorization precedes privileged access, and
foreign/unknown ids share one indistinguishable 404 `asset_not_found` with no
R2 access and no finalization, after the request-scoped read.

F6 tension recorded for the owner: at confirm time the request linkage exists
only on the asset row (`linked_request_id`, set at registration) while the
request's `active_proof_asset_id` is set only at attach, post-confirm — so a
zero-privileged-read confirm-side refusal is not achievable in the frozen
first-upload flow. The amended assertion keeps the external-refusal guarantee;
if the owner wants zero privileged reads there too, that is a spec change.

Removed by this round (was over-reach into the DB layer, noted, not silently
dropped): the confirm-side proof-disposition 4-pack. Registration creates a
proof `active`; `superseded`/`rejected`/`bound` arise only post-attach through
DB commands, and re-confirming an already-confirmed asset is a lawful no-copy
replay (amendment §1), so disposition gating is not an Edge-media-boundary
requirement — it belongs to the attach/pgTAP layer.

Remaining 3 failures — all genuine source gaps, no fixture defects left:
1. `unknown proof access ... no privileged read` — Class A (proofUrl linkage
   enforcement off), builder fix in flight.
2. `superseded proof access ... no privileged read` — same Class A root cause:
   with linkage enforcement off, a non-active confirmed proof signs. Contract:
   BUY-009 (only the current active proof is obtainable).
3. `the general staff signer can never expose a payment proof` — newly
   isolated by this repair round: `staff-url` signs a confirmed
   `payment_proof` asset. Packet outcome 3 forbids general MEDIA signers from
   exposing proof objects; the same refusal already works for `member-url`.
   Coordinator/builder to route this gap; not fixable in fixtures.
