# WEB+NATIVE builder report — MEDIA/PAY repair round (2026-10-04)

Scope: web transport/routes/screens + native transport/screen per the repair
directive. supabase/** and packages/shared/** untouched (parallel builder owns
them; shared was being rewritten concurrently to the same frozen decisions —
my consumers were aligned to the NEW declared scalar row shape).

## Changed files (sha256-16)

- apps/web/lib/purchase-http.ts `c15ffe74de77ad5d` — GL126 removed; caps map
  `22023` DETAIL `purchase_cap` → 429 `rate_limited` (DETAIL-mapping pattern);
  record forwards `p_viewed_asset`/`p_viewed_proof_revision` when the body
  carries them; proofUploadUrl forwards `p_command_key`; proof-url mints the
  same-origin capability (HMAC-SHA256 over request/proof/asset/tenant/actor +
  issued/expire instants, keyed by the existing R2 server secret, base64url
  payload, no storage key inside) and returns only `{url,expiresAt}`;
  refuses a null proofId (confirmed-unattached registration is not viewable).
- apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts
  `9e4bac227ffc81f3` — rewritten: `[id]` segment read (the old code read
  `requestId` from an `[id]` segment — every GET could never work); mandatory
  unforgeable capability (absent/garbage/tampered/expired/foreign-request/
  changed-actor all refuse BEFORE any object access; expiry immutable ≤
  issued+60s, GET never re-mints); GET-only export; published key reconstructed
  server-side inside the caller's tenant (never in URL or response); bytes
  stream with `no-store`; member/staff identity only.
- apps/web/lib/purchase.ts `704fcc3ab8d9f600` — loaders decode the declared
  scalar page `{requests,nextAfter,nextAfterId}` and camelCase detail
  (the snake_case projection that could never decode the real protocol is
  gone); declared-key whitelist projection + null-strip before the shared
  schema (absent facts stay absent, no storage metadata survives).
  NOTE: file was already dirty from another agent — additive surgical edits,
  flagged.
- apps/web/lib/purchase-view.ts `30d272c452e63656` — display fields derive
  from the nested camelCase snapshot (shop/PT total, renewal sold terms) with
  the flat legacy fields as fallback; `activeProofAssetId` surfaces for the
  desk viewer. Additive; file was clean before.
- apps/web/lib/media-upload.ts `dfc82f5cfc28ab9e` — registration body carries
  the retained command key: one registration identity per logical upload,
  retries replay identical facts (R5).
- apps/web/app/(console)/purchase-requests/[requestId]/purchase-desk-actions.tsx
  `f6baafb6e3f4b342` — real proof viewer (bounded capability URL fetched from
  proof-url, exact-screenshot render gates recording), reject-proof sends the
  exact viewed assetId (never empty), record sends the viewed-evidence tuple,
  disclosure unchanged.
- apps/web/app/(console)/purchase-requests/[requestId]/page.tsx
  `22cc062c2d76b223` — passes `activeProofAssetId`.
- apps/web/app/member/buy/purchase-actions.tsx `2f6f2c1d14fc5ab5` —
  replacement affordance in `payment_proof_uploaded` ("Replace payment
  screenshot"); re-upload label for rejected proofs.
- apps/mobile/lib/purchase.ts `cf42699c68562c53` — native hook decodes the
  declared scalar page (the wrap-and-`.at(-1)` bug gone), tolerant declared-key
  decode with snapshot-derived display fields, identity change/sign-out clears
  identity-scoped state, failed reads keep the last-good page flagged `stale`
  (BUY-021), reload seam exposed; exports `MemberPurchaseRow`.
- apps/mobile/lib/proof-upload.ts `c8cf4499cf9ec10f` — registration body
  carries the command key (same-facts replay, R5).
- apps/mobile/app/(member)/buy.tsx `25fd0507af19ecd8` — picker opens
  synchronously from the press (launcher warmed at mount) so the press-time
  identity is comparable after the picker await: member change or sign-out
  refuses before ANY network command (R6); replacement affordance in
  `payment_proof_uploaded`; reload after successful upload; honest copy.
- docs/registry.md `595cc26f4e01cfdf` — two rows added
  (`verifyProofCapability`, `MemberPurchaseRow`).

## Verification (verbatim)

- Repair web+native set (9 files): **Test Files 9 passed (9) / Tests 53
  passed (53)** — page-decode (8), proof-asset (11), upload-identity (3),
  verifier-surface (6), member-buy-page, desk-queue, hook-identity (3),
  native-identity (4), native-proof-upload (7).
- Committed boundary + routes files: **Test Files 2 passed (2) / Tests 83
  passed (83)** — including the R9 active-only boundary (recorded/mismatch
  refuse member+verifier alike) and the capability-envelope routes test.
- `registry-lint`: green. Web `tsc --noEmit`: clean. Mobile `tsc --noEmit`:
  clean.

## Integration dependencies (SQL/Edge/shared builder + primary)

1. Shared schema (in flight by the parallel builder, aligned to the frozen
   decisions): `purchaseProofUploadUrlRequestSchema` must admit the
   registration `commandKey` (route forwards it as `p_command_key` once the
   schema lets it through); `register_payment_proof` gains the key;
   `record_purchase_request` gains `p_initial_slot`/`p_viewed_asset`/
   `p_viewed_proof_revision` (the shared record schema already requires the
   viewed tuple — the desk UI sends it).
2. `read_purchase_proof_url` should include the asset MIME in its jsonb so the
   capability pins the exact content type; without it the GET probes the three
   bounded published-key extensions (deterministic, ≤3 candidate GETs).
3. Committed-test defects for the test author (spec:): the
   `purchase-visible-proof-upload.test.ts` "registration rate cap" case still
   mocks a `GL126` refusal — GL126 is not authorized (frozen decision 6); it
   must expect `22023` DETAIL `purchase_cap` instead. The
   `purchase-visible-routes.test.ts` record cases must carry the now-required
   viewed-evidence tuple in their bodies.
4. The proof-asset GET reauthorizes cryptographically (capability binds
   request/proof/asset/actor/tenant + immutable expiry, HMAC-verified) without
   a DB round-trip per GET — the live active-proof DB truth is enforced at
   mint time. If the fresh critic requires a per-GET DB recheck, that is a
   spec question against the committed GET tests (which pin a no-DB happy
   path).

## Concurrency note

packages/shared/src/api/purchase.ts was rewritten mid-round by the parallel
builder to the same frozen decisions (scalar camelCase row + nested snapshots,
absentable nulls, renewal null revision, viewed tuple, currency preserved). My
consumers were aligned to that landed shape; one transient mid-edit state
(briefly missing `check-in` module in the shared index) was observed and is
that builder's in-flight work.


## Round 2 — coordinator contract-list closure (2026-10-04)

Checked against the declaration directly (never the held suite):

1. **H5 registration key** — web body `{mime, bytes, commandKey}`, native body
   `{mime, bytes, commandKey}`; route forwards `p_command_key`; retries carry
   the caller-retained key (identical bodies). Field name matches the
   declaration's command vocabulary. Schema admission = shared/SQL builder
   (integration note stands).
2. **H2 envelope** — `apiOk({url, expiresAt})` only, `noStore`; expiry is the
   SQL-issued immutable deadline (capability `exp` equals it, ≤
   issuedAt+60s, refused when ≤ now); a GET never resets it. The earlier
   boundary-suite failure was the shared package's transient mid-edit state —
   **boundary suite now 5/5**.
3. **H10** — capability payload carries only request/proof/asset ids, tenant,
   viewer identity and the two instants (+ optional MIME); no storage-derived
   material; the published key is reconstructed server-side and never appears
   in the URL, envelope, body or logs.
4. **H9** — record forwards expectedRevision/actualAmount/currency/method (+
   viewed tuple when present); reasons are now trimmed at the route BEFORE
   validation and forwarding, so padding can neither hide a short reason nor
   overflow a real one, and the trimmed form reaches the reader.
5. **H1 divergence found and fixed** — the single projection whitelist was
   stripping the staff-only facts from the DESK path. The projection is now
   audience-aware: the front-office reader keeps `memberName`/`memberId`
   (staff-only, never member-supplied authority, never on the member
   projection); both audiences decode the same scalar page + cursor pair with
   the no-fabrication projection.

Verification (verbatim): repair set 12 files → **Tests 1 failed | 142 passed
(143)** — the single failure is the recorded committed-test defect
(GL126 mock case in purchase-visible-proof-upload.test.ts, frozen decision 6;
test author owns the spec: amendment). Web + mobile `tsc --noEmit` clean.

Updated sha256-16: purchase-http `2d495e14ca9ed66a`, purchase.ts
`e33d00fbe35d6dd1` (audience-aware projection + reason trim), all others
unchanged from round 1 (`30d272c4…`, `9e4bac22…`, `f6baafb6…`,
`2f6f2c1d…`, `cf42699c…`, `c8cf4499…`, `25fd0507…`, `dfc82f5c…`,
`9e4bac22…`).


## Round 3 — explicit retained registration key + seam re-verification

1. **Transport signature (frozen decision 5, caller-owned key):**
   `uploadPaymentProof(file, requestId, expectedRevision, commandKey,
   registrationKey?, onStage?)` and `uploadProofImage(api, requestId, image,
   expectedRevision, commandKey, registrationKey?)` now RECEIVE the caller-
   retained registration key explicitly (position after commandKey); the
   upload-url body carries it (`commandKey: registrationKey ?? commandKey` —
   the single-command fallback keeps the caller's own retained key when no
   separate registration key exists). The screens now OWN and RETAIN both keys
   per logical upload (ref map on native keyed by requestId; ref on web),
   clearing them only on the definitive success; retries transmit the
   identical values. Shared schema requirement = SQL/Edge builder (standing
   integration note).
2. **Route response shape** re-verified at the boundary: member + desk GET
   `data` IS the scalar page `{requests,nextAfter,nextAfterId}` (page-decode
   asserts the exact key set), no-store, declared camelCase projection,
   audience-aware (staff-only `memberName`/`memberId` never on member rows),
   no-fabrication strip, full cursor pair.
3. **proof-url** re-verified: `data` exactly `{url,expiresAt}`, no-store;
   capability payload = request/proof/asset ids + tenant + actor + issue/
   expire instants (+ optional declared MIME) — no storage-derived material.
4. **record/reject** — record forwards revision/amount/currency/method +
   viewed tuple; reject trims at the route before validation (both reject and
   reject-proof via the shared pre-parse trim).

Independent probe: the committed active-proof boundary suite was run TWICE
in separate processes (full set + standalone re-probe) — **5/5 both times**;
the earlier "transient mid-edit" reading was wrong per the coordinator — the
suite now passes against the settled shared package, and I will not claim
more than these two observed runs.

Verification: repair set **10 files / 58 tests, all green** (probe repeated:
boundary 5/5 standalone). Web + mobile `tsc --noEmit` clean.

Round-3 updated sha256-16: apps/web/lib/media-upload.ts `11e463724bccdbb7`,
apps/mobile/lib/proof-upload.ts `e2ef94d70f5438c6`,
apps/mobile/app/(member)/buy.tsx `06b36a0cf8b55cb7`,
apps/web/app/member/buy/purchase-actions.tsx `8aa42f87fe892857`; unchanged
from round 2: purchase-http `2d495e14ca9ed66a`, purchase.ts
`e33d00fbe35d6dd1`, purchase-view `30d272c452e63656`, proof-asset route
`9e4bac227ffc81f3`, desk actions `f6baafb6e3f4b342`, desk page
`22cc062c2d76b223`, native hook `cf42699c68562c53`, registry `595cc26f4e01cfdf`.


## Round 4/5 — native registration gap + projection null semantics

**Native zero-registration diagnosis (round 4 item 1):** my own probe proved
the transport registers for `{uri:'file:///proof.png', mimeType:'image/png',
fileSize:1234}` — the zero-call class had TWO real causes, both fixed:
1. The picker-await identity guard compared identity by OBJECT identity; a
   runtime handing back an equal-but-fresh identity object (as a harness or
   re-render does) false-positived the refuse-before-network guard. The guard
   now compares the identity SCOPE (kind/user/tenant/member facts), so equal
   facts proceed and only a genuinely changed identity refuses
   (`identityScope()` helper).
2. The network guards treated an UNKNOWN network state as offline
   (`isConnected !== true` / `!isConnected`) — in a harness without an
   expo-network answer that refused before the registration. All three guards
   (screen upload, hook runCommand, hook reload) now refuse only on a
   DEFINITIVE offline state (`isConnected === false` or
   `isInternetReachable === false`); an unknown state proceeds and the command
   answers honestly (BUY-021).

**Route projection (round 5 item):** `stripNullFacts` removed — the
audience-aware whitelist now passes declared keys through EXACTLY as received
(an explicit `recordedPaymentId: null` stays on the row as received; absent
stays absent) and strips only non-declared keys; the shared decode schema owns
the null semantics. Minimal surgical edit on the other agent's file, flagged.

**Web retry lens re-check:** the screen retains both keys in a ref until the
definitive success; the transport sends `commandKey: registrationKey ??
commandKey`; a retry after PUT/confirm failure re-sends the identical
registration key and facts through the same retained identity.

**Verification (verbatim):** 12 files → **Tests 5 failed | 138 passed (143)**.
The 5 failures are ONE root cause outside my scope: the shared
`purchaseProofUploadUrlRequestSchema` now (correctly, frozen decision 5)
REQUIRES the registration `commandKey`, while the committed
`purchase-visible-proof-upload.test.ts` posts `{}` bodies — the test author
owns the spec: amendment (bodies carry the retained key; the GL126 case must
also flip to 22023/purchase_cap). Web + mobile `tsc --noEmit` clean.

Round-5 sha256-16: apps/web/lib/purchase.ts `0c1076e5212f313d`,
apps/mobile/lib/purchase.ts `cf42699c68562c53`, buy.tsx `b6a234309330e7b1`,
purchase-http `7510bc4674da41c2`, media-upload `3ccfaa12bfe99f7d`,
proof-upload `9252bf2a6da0a887`.


## Round 6 — web-symmetric native transport

`uploadProofImage(image, requestId, expectedRevision, commandKey,
registrationKey?)` — the injected api parameter is gone; the transport owns
its HTTP end to end exactly like `uploadPaymentProof`: registration and
confirm are global-fetch POSTs to the same request paths with the same strict
JSON bodies (registration carries requestId-from-route + declared MIME/bytes +
the caller-retained registration key), envelope `ok` checks on both HTTP
status and body, staging PUT unchanged. Body shapes and the retained-key
semantics are byte-identical to round 5. The identity-scope guard and the
definitive-offline guard stay in the screen/hook layer where they were built.
The screen call site dropped the api argument; its retained-keys ref is
unchanged.

Known committed-test breakage from this contract-mandated refactor (test
author owns the spec:): `purchase-visible-native-proof-upload.test.tsx`
observes the upload through `api.post` (h.post) — the transport now uses
global fetch, so that harness must stub fetch instead. All other tests in the
file pass unchanged.

Verification: 9 non-affected files → **51/51 green**; native-identity +
hook-identity 7/7; web + mobile `tsc --noEmit` clean.

Round-6 sha256-16: apps/mobile/lib/proof-upload.ts `388cc3ba563123a6`,
apps/mobile/app/(member)/buy.tsx `f6200682aaa3dbfe`.


## Round 7 — argument-order alignment

`uploadProofImage(image, requestId, expectedRevision, commandKey,
registrationKey?)` — first two parameters swapped to match
`uploadPaymentProof`'s exact argument order; screen call site updated.
Nothing else changed.

Verification: 9 files → **51/51 green**; mobile `tsc --noEmit` clean.
Round-7 sha256-16: proof-upload `b19215f242611cf5`, buy.tsx
`f91ae9ae56d6c67a`.
