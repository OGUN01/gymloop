# Fresh primary MEDIA/PAY security critic

Verdict: **NO**. Independent source-only review at HEAD f85b22b7eaa492f6b7aa131d61337d863af2a108. Public authority: AGENTS.md; committed HEAD MEDIA verification amendment and PAY proposal; security and registry. No tests, holdout suite, other reports, diagnostics, Cloud, deployment, device, or git mutations were read/performed. No source edits.

## Major findings

1. **Private signer does not prove the requested proof's exposure.** supabase/functions/media/index.ts:227–259. proofExposure returns successfully for ANY nonempty request list when requireLive=false and the requested asset is absent. proofUrl then service-reads and signs any same-tenant published payment_proof (member creator restriction only for members). A front-office user with one request can directly invoke proof-url with a same-tenant unattached, rejected or superseded asset id; a member can access their own such asset. It also has no post-private-lookup actor/request recheck. This violates BUY-009 and the frozen proof-specific request exposure boundary. First-page (20) reads are not exact target authority.

2. **The delivered evidence GET can never serve the actual SQL result.** apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts:32–41 reads params.requestId although its segment is [id]. Even after fixing that, it requires an array with expires_at/asset_id, while migration:2844–2886 returns a camelCase jsonb object (requestId, assetId, expiresAt). Every actual request returns generic refusal. BUY-009/025 verifier/member viewing and end-to-end protocol fail. Additionally the SQL URL has no fixed expiry component and each GET remints its deadline; the issued relative URL does not itself expire after 60 seconds as frozen BUY-018/URL protocol requires.

3. **Native reads do not interoperate with the database.** apps/mobile/lib/purchase.ts:45–54 wraps the entire jsonb page in requests and calls .at(-1) on that object. read_member_purchase_requests returns {requests,nextAfter,nextAfterId}, not an array (migration:2572–2612). Thus native list fails before selecting an accepted request; BUY-025 clickable native surface cannot work. Its catch clears prior data and has no stale timestamp; identity changes do not immediately clear rows or invalidate old requests, contrary to BUY-021.

4. **Finalization does not revalidate eligible member status under its actor lock.** migration:790–813 proves only tenant/user binding, not blocked/cancelled/pending/erased state. The linked-request check at 850 only checks status/expiry, not member ownership/status under a request lock. Revoking a member while copy/verification awaits does not stop finalization. proof-confirm never invokes activeActor, and its initial proofExposure cannot guarantee continued eligibility. BUY-001/007 and the frozen dedicated live-owned-accepted finalizer protocol require this check. Replay returns false at 839 before linked-request validation, so a confirmed proof replay also bypasses the live request requirement.

5. **Registration/request binding is not enforced on attach.** migration:1980–1995 validates confirmed kind and creator, but never compares immutable media_assets.linked_request_id to p_request_id. A member can register and confirm against accepted request A, then attach the unused asset to accepted request B; the payment_proofs conflict check only blocks already-attached assets. This defeats the frozen registration/finalization owned-request linkage (PAY proposal line 64) and the end-to-end evidence identity guarantee.

6. **Replacement and retry UX cannot satisfy the protocol.** web purchase-actions.tsx:71 and mobile buy.tsx:134 expose upload only for owner_accepted, never payment_proof_uploaded, although BUY-010 explicitly requires replacement. Web/native create fresh registration and command keys on retry without retaining an unknown-outcome asset/key; after an attach timeout a retry cannot reliably replay the original command (BUY-016 and frozen retryable-unknown-outcome HTTP protocol). Native in-flight upload has no identity/lifecycle cancellation guard across file fetch/PUT/confirm (BUY-021).

Additional static blocker: app.pay_proof_evidence returns anonymous record (migration:2790), yet read_purchase_proof_url selects * from it without a column-definition list (2874/2876). PostgreSQL record-returning FROM functions require a known row definition; this needs source/runtime verification before this door can be accepted.

## Positive observations and limits

Staging-only browser PUT namespaces, conditional source ETag copy, independently rechecked destination, immutable publication metadata and unknown-finalizer candidate retention follow the MEDIA direction. Proof GET signing uses the 60-second constant. Integer amount schemas use decimal text/BigInt bounds. None compensates for broken authority or transports. No live R2/native/DB acceptance or independent full ledger assessment is claimed.

## Source stability

The first complete hash snapshot was taken after initial source reading; earlier nine-file snapshot prefixes matched. **Source changed during review:** the migration changed from A750DDA04E2A21F555C33CDFFBFAE9C606C44E1951D9E5D8E462BE06C1B84397 to 46446C5C31680EA0FFBDFE00334C67107188B23BA90E43660DAC02EED1881A70. All other listed source hashes match. Findings refer to the read snapshot, not a certified frozen current migration. This review cannot certify mutations before the first snapshot. The block below records the before-report snapshot.

```
packages/shared/src/api/media.ts F5D2018FC45FEFA3DBF8835F012A0BCC98C5AF518F06BF0F47CB940A2F19E880
packages/shared/src/api/purchase.ts 22DF42D99F7AE565EE8D70FD2EF4B0E816FD9B5FBD1B85363646D33C5776CB7D
supabase/functions/media/index.ts C8456E4BC46644F696C16CAB17C1389351D714BD3DAD9D0D1131294D16AD0D3C
supabase/migrations/20261004100000_purchase_requests.sql A750DDA04E2A21F555C33CDFFBFAE9C606C44E1951D9E5D8E462BE06C1B84397
apps/web/lib/media-upload.ts 6AC4D4552CB6C560D60F5ED2EF5C8D0B5B1052F8F8F41867F099D29897342566
apps/web/lib/media.ts B633D5AADE5A6C034022067FB94675D5E7D3B44C8D61C0684001EA8FBFA21124
apps/web/lib/purchase-http.ts D4E78416CCB75AF9E26FAEAAF715FB4E6F26010AC86FB8C12451812EB35D0DFE
apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts B4F0EA66395C8007E561953F91E88B6DF4351DDFE3B1E1A6EAFD736DC09114DD
apps/web/app/member/buy/purchase-actions.tsx 119F216D3728A440B94B1CB15EACE67D88D786100AA7C96AC1F8A3DB9EAFE764
apps/web/app/member/buy/[requestId]/page.tsx C58D0E90EFB03A94A9C28B9E1F1107C8E3620082AFD398A674032BF28C73DE5B
apps/mobile/lib/proof-upload.ts 030BBB8E4097FCAE78EB925A4AE7DD26400BCD297365208BE05B1CD35F142155
apps/mobile/lib/purchase.ts 68A92CB162CC38DF530A1E093B1ED07E2425AD6020FD4AC6AE39F5AAEBF406B4
apps/mobile/app/(member)/buy.tsx F4BC24AD13F29F0388207252FE353DB8EBA4C461291D03DD3CD46B06789E0FA6

```
