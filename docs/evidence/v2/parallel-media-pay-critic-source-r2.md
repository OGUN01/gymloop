# Verification critic round 2 — PAY MEDIA proof extension (2026-10-04)

Fresh-context check of every round-1 finding plus the full changed surface.
Round-1 checklist: `parallel-media-pay-critic-source.md`. Holdout never opened.

## Per-finding closure

- HIGH-1 `finalize_media_asset` unamended — **STILL-OPEN, correctly**. The
  definition in `20261003120000_shop.sql:355` still requires an active staff
  row, kind list `product|trainer|announcement`, and a published-key regex
  without `payment_proof`; the PAY migration does not amend it. No source or
  test pretends otherwise — recorded as the primary's SQL integration request
  in the implementer report and the progress file. Member confirmation can
  never finalize against live Cloud until the primary lands that amendment.
- HIGH-2 Edge select columns — **CLOSED**. `PRIVATE` now includes
  `created_by_member_id` (`supabase/functions/media/index.ts:21`); `SAFE`
  deliberately does not, and the claim is verified: the authenticated grant
  (`20261003120000_shop.sql:143`) carries exactly the SAFE column list, so a
  caller-scoped read naming the member-creator column would fail at runtime.
  Member-creator identity is only read through the service-key PRIVATE read,
  strictly after the caller's own RLS exposure proof. No member-readable
  widening: policies and the authenticated grant are untouched.
- HIGH-3 web upload end-to-end — **CLOSED**. `purchase-actions.tsx:41-72`
  runs the real chain: hidden file input (accept jpeg/png/webp), client
  preflight against `MEDIA_MIME_TYPES`/`MEDIA_LIMITS.maxBytes`, POST
  `proof-upload-url` with `{mime, bytes}`, staging PUT with the returned
  headers, `proof-confirm` with the read model's `acceptedRevision` + fresh
  `commandKey`, refusal message on every branch, honest success copy
  ("Pending verification — the gym checks the received money"), refresh after
  attach. `purchase-http.ts` `proofUploadUrl` calls `register_payment_proof`,
  validates the server-chosen key through `parseMediaObjectKey` (staging
  area enforced), and presigns a bounded staging PUT only.
- MED proofUrl verified-state gate — **CLOSED**. `proofUrl` signs only through
  `published()` (`index.ts:257`), which requires `confirmed_at` + stored
  verified ETags + a validated published key; the derived-key fallback is gone.
- MED proof-asset JWT forwarding — **CLOSED**. `proof-asset/route.ts:58-61`
  forwards the header bearer explicitly, else the verified cookie session,
  matching `media.ts` convention; envelope unwrap is the frozen
  `{ ok, data: { imageUrl } }`; byte stream is `no-store`.
- MED mime/bytes seam — **CLOSED**. Schema keeps both optional (a committed
  test pins the empty body); the web client always declares both. The
  RPC-side requirement change stays a primary integration request, listed.
- MED confirm-time liveness — **CLOSED as far as source can go**.
  `proofExposure` (`index.ts:227-241`) binds to the registered request when
  `activeProofAssetId` matches and requires that row live; the first-upload
  residual is documented in-code and listed as integration request 2, not
  papered over.

## Ten critical checks (re-run on current code)

1. Authorization precedes privileged access: **PASS** — caller RLS
   `proofExposure` strictly before asset/private reads, presign, copy,
   finalize; re-proven after every await via `recheck`.
2. Server-chosen keys, no client storage authority: **PASS** — registration
   RPC returns the staging key; `parseMediaObjectKey` enforces staging; presign
   staging-only; published keys never client-offered.
3. Immutable publication pipeline: **PASS in source** — ranged If-Match
   verify, ETag-conditional copy to a fresh candidate, destination recheck,
   exactly one service finalizer, loser cleans only its own candidate,
   unknown-outcome retention. **FAIL as integrated** (HIGH-1, primary SQL).
4. Private proof-url authorization/TTL/refusal/logging: **PASS** —
   member-or-verifier gate, preview/trainer refused, ≤60s
   `BUY_LIMITS.privateProofGetTtlSeconds`, one external refusal, no
   URL/token/key/proof-content logging anywhere in the new paths.
5. Photo operations preserved: **PASS** — `confirm`/`member-url`/`staff-url`
   semantics unchanged by the shared pipeline extraction; generic photo
   registration schema still excludes `payment_proof`.
6. proofConfirm ordering: **PASS** — trusted Edge verification strictly
   precedes `attach_payment_proof`; body `requestId` cross-checks the route id;
   upload/confirm failure never touches money.
7. Refusal mapping: **PASS** — full Edge vocabulary mapped (404/403/422/409/
   400/429 + GL126→429, GL086 media_limit→429, 23514 proof_media_refused→422);
   unmapped → 500 retryable generic; no upstream echo.
8. Hygiene: **PASS** — no new env read, no new dependency, no
   suppressions/ignores, constants imported, money path untouched.
9. Proof-asset route: **PASS** — bounded read, TTL/expiry validation, no-store
   streaming, single generic refusal, capability forwarded explicitly.
10. BUY-022 copy: **PASS** — pending/verification wording honest on web and
    native; nothing implies bank verification or automatic settlement.

## New findings this round

- MED apps/web/lib/media-upload.ts:33: `uploadPaymentProof` is exported with
  no caller — `purchase-actions.tsx` inlines the same register/PUT/confirm
  client flow. Unused duplicate export (knip/unused-export and duplication
  risk). Fix: wire the component to the helper (or drop it); do not keep two
  copies of the client protocol.
- LOW Edge proofExposure: the bound path admits only
  `owner_accepted`/`payment_proof_uploaded`, so a verifier cannot re-obtain a
  proof URL for a `recorded`/`mismatch_recorded` request whose asset id still
  matches. BUY-009 does not pin history viewing for this operation; left
  narrow rather than silently widened — owner contract question, not a defect
  to fix in source.
- LOW (verified clean) `p_limit: 0` clamps to 20 in both read RPCs — round-1
  LOW-10 closed by inspection of `20261004100000_purchase_requests.sql`.

## Verbatim test counts

`pnpm vitest run` over the eight listed suites: **Test Files 1 failed | 7
passed (8); Tests 1 failed | 210 passed (211)**. The single failure is the
owner-adjudicated "Payment recorded" wording conflict in
`purchase-visible-proof-surface.test.tsx` (stepper stage label vs no-payment-
claim regex). `npx deno check media/index.ts` (from `supabase/functions/`):
clean, exit 0.

## Verdicts

- (a) Edge + transport: **GO-WITH-FIXES** — every round-1 source-side
  HIGH/MED closed; the remaining blockers are the primary's SQL integration
  request (HIGH-1) and the MED duplicate-helper cleanup above.
- (b) Screens: **GO** — upload flow real, states/copy contract-true; native
  placeholder pending the owner's `expo-image-picker` decision remains
  acceptable; the one failing test is the adjudicated conflict, not a screen
  defect.
