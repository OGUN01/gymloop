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
