# Fresh source/security critic — PAY MEDIA proof extension (2026-10-04)

Scope: uncommitted diffs to shared media/purchase, Edge `media`, `purchase-http.ts`,
`media.ts`, `proof-asset` route; screens in buy pages + native buy. Judged against
the frozen member-purchases contract, media-verification-amendment, security doc,
pay-bar. Holdout dir never opened.

## Findings

- HIGH supabase/migrations/20261004100000_purchase_requests.sql (integration request): `public.finalize_media_asset` is NOT amended by the PAY migration — it still requires an active staff row (`perform 1 from public.staff …` with `p_actor_staff_id`), and its kind list + published-key regex admit only product|trainer|announcement. Edge `proof-confirm` passes `p_actor_role:'member'`, `p_actor_staff_id:null`, kind `payment_proof` → guaranteed 42501 (or 22023 on the old key regex). The member confirm flow can never finalize. Fix is SQL (primary-owned): `create or replace` amendment admitting exactly the member actor + payment_proof kind/key shape per the frozen proof-extension paragraph.
- HIGH supabase/functions/media/index.ts:18 (`SAFE`/`PRIVATE` selects): `created_by_member_id` is never selected, so `value.created_by_member_id` is always `undefined` → member `proof-confirm` and member `proof-url` reject `asset_not_found` for every real request. Mocked visible tests cannot catch a select-list omission. Fix: add the column to both select lists (creator identity belongs in SAFE).
- HIGH apps/web/app/member/buy/purchase-actions.tsx + purchase-http.ts proofUploadUrl: the web button POSTs `{}` — no mime/bytes — so `register_payment_proof` raises 22023 ("Registration arguments required") and the route maps it to `invalid_request`. The web upload happy path is dead end-to-end; no file input/PUT/confirm flow exists on web at all (screens implementer deferred the interactive flow). Fix: real file selection sends declared mime/bytes, then staging PUT, then proof-confirm.
- MED supabase/functions/media/index.ts proofUrl: no verified-state gate — `published()` is not consulted, so an UNCONFIRMED asset gets a signed GET for a DERIVED `<tenant>/published/payment_proof/<id>.<ext>` key that was never published (contract: missing verified state → asset_not_found). Also `extensionOf` returns `''` for unexpected mime → malformed key. Fix: require `confirmed_at` + validated published key (reuse `published(value, actor)`), refuse otherwise.
- MED apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts:55: `functions.invoke('media', …)` carries no explicit Authorization; for cookie-session requests the user JWT likely never reaches the Edge (repo convention — `media.ts`, `proofBearer` — always passes it explicitly). Desk proof streaming would then 403→generic at runtime. Verify against the installed supabase-js; if not attached, forward `bearer` explicitly as `media.ts` does.
- MED packages/shared purchaseProofUploadUrlRequestSchema vs register_payment_proof: schema marks mime/bytes optional, RPC requires both — omitting clients get `invalid_request` instead of a shape error at the schema. Either require both in the schema or have the route reject earlier; pick one and align screens.
- MED supabase/functions/media/index.ts proofConfirm: confirm-time liveness re-proof is "member owns some live accepted request", not "the request this proof was registered against" — the asset↔request linkage does not exist until `attach_payment_proof`. Money-safe (attach revalidates), but weaker than the contract's "finalization must prove live owned accepted request". Proposal to primary: persist the request linkage at registration so confirm/attach bind the exact request.
- LOW supabase/functions/media/index.ts: member-url `activeActor` moved from pre-exposure to post-lookups/pre-sign. Exposure is a caller-JWT RLS read; no added exposure; behavior effectively preserved — note only.
- LOW purchase-http.ts proofUploadUrl catch: `delete_media_asset` via a member client is refused (front-office actor required), so the cleanup call can never succeed — orphan retention follows MED-012 anyway; simplify or leave with a comment.
- LOW supabase/functions/media/index.ts proofExposure: `p_limit: 0` semantics of `read_member_purchase_requests`/`read_purchase_requests` are unverified (clamping behavior is SQL-side); verify against the migration.

## Checks

1. Authorization precedes privileged access (proof ops): PASS — `proofExposure` (caller RLS) strictly before asset/presign/copy/finalize; weakness noted (finding 7).
2. Server-chosen keys, no client storage authority: PASS — staging key from RPC, `parseMediaObjectKey` enforces `staging` area, presign only staging; confirm schema adds only optional `requestId` cross-check.
3. Immutable publication pipeline: PASS in Edge (If-Match verify, ETag-conditional copy to fresh candidate, destination recheck, single finalizer, loser cleans only own candidate, unknown-outcome retention) — FAIL as integrated: DB finalizer refuses payment_proof (finding 1).
4. Private proof-url authorization/TTL/refusal/logging: PASS on member-or-verifier gate, ≤60s `BUY_LIMITS.privateProofGetTtlSeconds`, single external refusal, no URL/token/key logging; trainers excluded at `identify()` (trainer app_role refused); MED gap on unconfirmed-state signing (finding 4).
5. Photo operations preserved: PASS — pipeline extraction is semantics-preserving for confirm; member-url `activeActor` timing note (LOW 8); staff-url/confirm paths otherwise unchanged.
6. proofConfirm ordering: PASS — trusted Edge verification strictly precedes `attach_payment_proof`; body `requestId` cross-check prevents cross-request confirm; upload/confirm failure never touches money.
7. Refusal mapping: PASS — Edge vocabulary mapped (asset_not_found→404 request_unavailable, not_permitted→403, upload_rejected→422, upload_missing/upload_changed→409, invalid_request→400, GL126/GL086 media_limit→429, 23514 proof_media_refused→422); unmapped → 500 retryable generic; no upstream echo.
8. Hygiene: PASS — no new env read, no new dependency, no suppressions/ignores, constants imported (`BUY_LIMITS`, `MEDIA_LIMITS`), money path untouched.
9. Proof-asset route: PASS on frozen `{ok,data:{imageUrl}}` unwrap, no-store byte stream, TTL/expiry/consumed checks, single generic refusal; MED risk on JWT forwarding (finding 5).
10. BUY-022 copy: PASS — "The gym checks the received money before your purchase counts", re-upload/reason paths honest; native states honestly that upload is unavailable in this build.

## Verdicts

- (a) Edge + transport: **NO-GO** — findings 1, 2 block the member flow entirely; 4, 5, 6 must be fixed before publication.
- (b) Screens: **GO-WITH-FIXES** — copy/states honest and contract-true; finding 3 (dead web upload flow) must be closed before any live scenario; native placeholder pending the owner's `expo-image-picker` decision is acceptable.
- SQL amendment (finding 1) and any registration-linkage change (finding 7) are primary-owned integration requests; do not bend source or tests to them.
