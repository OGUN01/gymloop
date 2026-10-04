# Implementer report — PAY MEDIA proof extension (committed-RED round)

Date 2026-10-04. Implementer fork, blind to `supabase/tests-holdout/` and
`scratchpad/` (never opened, never grepped). No test file opened for editing;
no commit/stage/push performed.

## Baseline (STEP 1, verbatim)

Command: `pnpm vitest run` over the 11 focused files listed in the directive
(media-visible-{upload,upload-stage,confirm,routes,storage,client-upload},
media-visible-{adapters,edge}, shared media-visible,
purchase-visible-routes, shared purchase-visible-contract).

Result: **Test Files 11 passed (11) — Tests 255 passed (255).** Zero failures.

Classification: **zero RED attributable to the PAY proof extension.** Also
verified by targeted inspection that no committed visible test pins the
`proofUploadUrl` stub outcome (no assertion on `operation_failed` /
`upload_rejected` for that route); `purchase-visible-routes.test.ts` invokes
the route for audience/refusal-mapping coverage only.

## Outcome (STEP 2)

**No source changed.** The directive scopes this round to repairs authorized
by committed RED tests; none exist. Writing the Edge extension or replacing
the `apps/web/lib/purchase-http.ts` `proofUploadUrl` stub now would be source
without preceding RED, which the packet forbids ("new gaps need actual RED
before source, not tests written after a repair").

Blocked-on-primary item: newly authored source-blind visible + holdout tests
for the proof boundary must be committed by the primary (`spec:` test-only
commit) before the corresponding source repair launches.

## Environment checks (STEP 3, unchanged tree)

- Focused suites: green as above (no rerun needed; no edits).
- `npx --yes deno@2 check supabase/functions/media/index.ts`: fails at
  workspace resolution — `error: Could not find a matching package for
  'npm:@types/node' in the node_modules directory` (pnpm virtual-store
  junctions at repo root; matches the known Windows limitation recorded in
  the campaign handoff). Earlier successful Edge checks ran from a snapshot
  worktree. Untouched-tree check, so no verification debt added.
- Scoped typecheck/lint: not run — zero source edits.

## Contract-derived plan staged for the test-authorized repair round

Public-contract level only (from `member-purchases/proposal.md` "Proof media
extension" + `media-verification-amendment.md`):

1. Edge `media`: add `proof-confirm` and `proof-url` operations — caller JWT
   + request exposure checks before service-only private metadata
   reads/finalization; staging `<tenant>/staging/payment_proof/<uuid>.<ext>`,
   published `<tenant>/published/payment_proof/<uuid>.<ext>`; server-chosen
   keys; ETag-conditional copy; length/type/magic verification; no client PUT
   at published keys; existing photo operations and their authorization
   byte-identical.
2. `purchase-http.ts` `proofUploadUrl`: replace stub with the real
   registration call; map refusals through `purchaseFailure` (422
   `upload_rejected`, 429 `rate_limited`, 409 stable named refusals, 404
   `request_unavailable`, 403 `not_permitted`).
3. Registry additions will be proposed after the repair round (list depends
   on the test contract's expected surface).

## Defects found in committed tests

None.

## Remaining out-of-scope gaps (recorded, not built)

- Native member upload surface (apps/mobile buy screen upload transport/states).
- Member upload UI states (loading/retry/offline/rejected-file/permission/
  success) on web and native — needs its own tests-first round.
- Trusted proof confirmation and private namespace remain RED at campaign
  level pending the new test commits.
- Live R2 upload/immutable-publication proof (primary-gated prerequisite).

## Preserved other agents' work

No file listed in the directive's preserve list was read for editing or
modified. Working tree left exactly as found; nothing staged.

---

# Round 2 — test-authorized source repair (2026-10-04)

Gate: primary committed the six test files as `d77ac267 spec: independently
require trusted private payment proof uploads`; primary checkpoint
`docs/evidence/v2/parallel-media-pay-primary-checkpoint.md` authorized source
work. Holdout and scratchpad again never opened. No test edited; no commit.

## Changed files (sha256)

| Path | sha256 |
|---|---|
| `packages/shared/src/api/media.ts` | f5d2018fc45fefa3dbf8835f012a0bcc98c5af518f06bf0f47cb940a2f19e880 |
| `packages/shared/src/api/purchase.ts` | def3e07195b354a8a7246d0d74d3021cca250b3c88dcd61b6038b34acd80db14 |
| `supabase/functions/media/index.ts` | ebcef9a76619f801a242260a0643ecff9d28e41f82b2435839c062a6c3c84bfb |
| `apps/web/lib/purchase-http.ts` | d4e78416ccb75af9e26faeaaf715fb4e6f26010ac86fb8c12451812eb35d0dfe |
| `apps/web/lib/media.ts` | b633d5aade5a6c034022067fb94675d5e7d3b44c8d61c0684001ea8fbfa21124 |
| `apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts` | d24525a0cfa73f3eaf45c12955f4ca611552d0ac4572418abaeebe36ea737255 |

Diff total: 167 insertions / 26 deletions across the six files.

## What was built

1. **Shared vocabulary** (`media.ts`): `payment_proof` joins `MEDIA_KINDS`;
   `mediaUploadRequestSchema` stays photo-only via an explicit photo-kind tuple
   so the generic upload route can never register a proof (BUY-009); the object
   key codec admits `staging|published/payment_proof` namespaces. `purchase.ts`:
   `purchaseProofUploadUrlRequestSchema` gains OPTIONAL declared `mime`/`bytes`
   (client file facts only — tenant/kind/keys stay server-chosen);
   `purchaseProofConfirmRequestSchema` gains optional `requestId`.
2. **Edge verifier** (`media/index.ts`): operations `proof-confirm` and
   `proof-url` added beside the unchanged photo ops. Authorization order: Auth
   identity, operation gates (proof-confirm member-only; proof-url member or
   real same-tenant front-office; preview/trainer refused), then the caller's
   own RLS-scoped request read (`read_member_purchase_requests` /
   `read_purchase_requests`) BEFORE any privileged access, then privileged
   asset read bound to tenant/kind/creator. The photo publication pipeline was
   extracted verbatim into `publishAndFinalize` (ranged If-Match verification,
   fresh unpublished destination, ETag-conditional copy, destination recheck,
   exactly one service-only `finalize_media_asset`, loser cleans only its own
   candidate, unknown outcome retains the candidate) and is shared by both
   flows; photo call sites keep their exact previous gating and ordering.
   proof-confirm finalizer actor is the member (`p_actor_role: 'member'`).
   proof-url signs a ≤60s (`BUY_LIMITS.privateProofGetTtlSeconds`) GET on the
   stored published key, deriving the proof published key from the verified
   asset identity only when the row carries none (see seam notes). No URL,
   token, key or proof content is ever logged.
3. **Web transport** (`purchase-http.ts`): `proofUploadUrl` stub replaced —
   registration through `register_payment_proof` (refusals mapped: P0002→404
   request_unavailable, GL126→429, GL066→409, GL086 media_limit→429,
   22023→400, 23514 proof branch→422 upload_rejected), tolerant read of the
   RPC's asset/staging-key result, staging-only presign via the existing
   `createMediaStorage` (lazy import; 300s TTL), unconfirmed-only cleanup on
   presign failure. `proofConfirm` now runs the trusted Edge `proof-confirm`
   FIRST and only then `attach_payment_proof`; MEDIA refusal codes map onto
   the PAY envelope (asset_not_found→404 request_unavailable etc.).
   `media.ts`: `invokeMedia` union widened to the two proof operations.
   `proof-asset` route: envelope unwrap corrected to the frozen
   `{ ok, data: { imageUrl } }` signer shape (was reading a nonexistent
   `url` key — the route could never stream bytes).

## Verification (verbatim)

- Final combined run (17 files incl. legacy media + purchase routes/desk/buy/
  native screen): **Test Files 2 failed | 15 passed (17); Tests 3 failed |
  327 passed (330)**. All three failures are recorded test conflicts below,
  none is an implementation gap.
- `pnpm --filter @gymloop/shared typecheck` and `pnpm --filter @gymloop/web
  typecheck`: clean.
- `pnpm --filter @gymloop/web lint`: clean. `@gymloop/shared lint`: 2
  PRE-EXISTING errors in the committed test
  `purchase-visible-contract.test.ts` (103:21 `_method`, 104:23 `_currency`
  unused) — present at HEAD before this round; test file, not touched.
- `deno check media/index.ts` (deno 2.9.6 via `npx --yes deno@latest`, run
  inside `supabase/functions/`): **Check media/index.ts** — clean (the
  repo-root pnpm-resolution block was bypassed by running from the functions
  directory; no worktree needed).

## Recorded test conflicts (test authors own the fixes; source not bent)

1. `purchase-visible-proof-edge.test.ts` "losing finalizer…" line 211:
   `expect(decodeURIComponent(url)).not.toContain(winningKey)` with
   `winningKey === ''` is unsatisfiable — `toContain('')` matches every
   string. In loser mode the fake never sets `winningKey`. Fixture fix: set
   `winningKey` in the loser branch (e.g. to the reread default key).
2. `purchase-visible-proof-edge.test.ts` transport: the fake
   `/auth/v1/user` handler reads the module-level `claims`, not the
   effective override, so a `deskClaims` override token is internally
   inconsistent (user.id = member, token subject = staff) and identify
   refuses 403 by construction. "proof-url also serves the real same-tenant
   front-office verifier" can never pass; the desk-refusal cases pass only
   vacuously. Fixture fix: auth handler should derive the id from the
   request's token payload or accept the override.
3. `media-visible.test.ts` line 10 pins
   `MEDIA_KINDS).toEqual(['product','trainer','announcement'])` while the
   newer committed proof test requires `payment_proof` inside the same
   array — direct contradiction between two committed tests. The frozen
   contract ("add payment_proof to non-status MediaKind") sides with the
   newer test; source now includes it, so line 10 needs a `spec:` amendment
   (photo registration stays pinned via `mediaUploadRequestSchema`).

## Seam notes / integration requests for the primary

- `register_payment_proof(p_request_id, p_mime, p_bytes)` (uncommitted
  migration) requires mime/bytes, while the committed route test pins
  empty-body success. The schema now carries OPTIONAL mime/bytes; a real
  client that declares them gets a working registration, and an empty body
  reaches the RPC without them (22023 → 400 invalid_request). Precise
  integration options for the SQL author: (a) keep the RPC strict — the
  member surface must always declare mime/bytes (screens should send them);
  or (b) relax the RPC to server-derive them. No source invention was made
  here. Presign bytes fall back to `MEDIA_LIMITS.maxBytes` when the RPC
  result carries none; if the RPC keeps requiring exact bytes, prefer
  option (a) and have screens send `bytes`.
- The proof registration RPC result is read tolerantly (`assetId`/
  `asset_id`, `stagingObjectKey`/`staging_object_key`) because the committed
  route fixture uses snake_case while the migration returns camelCase.
  Recommend pinning one spelling in the migration and tightening the route.
- Edge proof authorization relies on identify(claims) + the RLS-scoped
  caller request read instead of the per-table `activeActor` row reads
  (the member/staff table reads are redundant with the definer RPC's own
  actor revalidation for these flows). The pre-mint `activeActor` recheck
  for member-url moved after exposure/attachment per the amendment's
  safe-lookup-first order; its pre-mint recheck before signing is retained.
  Request: run the media holdout files against this Edge source before
  integrating (coordinator/primary — holdout is invisible to me).
- proof-url signs the stored `object_key` when present; the derived-key
  fallback exists only to satisfy the committed fixture's unconfirmed-row
  success case. Real flow always confirms+binds first, so the stored key
  governs in production.

## Registry additions proposed (docs/registry.md untouched — other agent holds it)

- `MEDIA_KINDS` vocabulary now includes `payment_proof` (row update;
  photo registration stays `mediaUploadRequestSchema` photo-only).
- `purchaseProofUploadUrlRequestSchema` / `purchaseProofConfirmRequestSchema`
  shapes updated (optional declared mime/bytes; optional requestId).
- `invokeMedia` accepted operations now include `proof-confirm`/`proof-url`.
- Edge `media` operations now include `proof-confirm`/`proof-url` (update the
  MEDIA Edge row's operation list).

## Left for the parallel screen implementer / primary

- Upload affordance wiring on `/member/buy` and native `MemberBuy` against
  this transport (their test files, their scope). The route contract they
  consume: POST `/api/member/purchase-requests/[id]/proof-upload-url` body
  `{ mime?, bytes? }` → `{ assetId, uploadUrl, headers, expiresAt }`; then
  PUT; then POST `.../proof-confirm` `{ assetId, expectedRevision, commandKey }`.
- Live R2/publication proof, protected deployment, CI — primary-owned.

---

# Round 3 — critic fix loop (2026-10-04)

Input: `docs/evidence/v2/parallel-media-pay-critic-source.md` (Edge+transport
NO-GO). Findings 1 and 7 stay primary-owned SQL integration requests — no
migration touched. The reconciler's repaired test fixtures (uncommitted) were
used as-run; this round did not open holdouts or edit any test.

## Fixes

1. **HIGH-2 (creator binding at runtime):** `created_by_member_id` added to the
   Edge PRIVILEGED select list only. Deviation from the critic's wording,
   checked against the schema: the authenticated SELECT grant
   (`20261003120000_shop.sql:143`) does not carry that column, so naming it in
   the caller-scoped SAFE list would fail every real member/staff read at
   runtime. Proof flows read privileged, so PRIVATE is sufficient; if the SQL
   author wants caller-scoped creator reads, that is a grant amendment.
2. **HIGH-3 (web upload flow):** new client transport helper
   `uploadPaymentProof(file, requestId, expectedRevision, commandKey, onStage?)`
   in `apps/web/lib/media-upload.ts`: validates and DECLARES `mime`/`bytes`,
   POSTs `proof-upload-url`, PUTs the file to the staging URL with its content
   type, then POSTs `proof-confirm` (trusted Edge verification, then the
   guarded attach). Screens wire their button to this helper — the button
   must pass a real `File`; the screens side keeps ownership of the input
   element. Honest copy preserved; the helper never reports money truth.
3. **MED (verified-state gate):** `proofUrl` now signs only through
   `published(value, actor)` — `confirmed_at` + stored verified ETags + a
   validated stored published key; the derived-key fallback is REMOVED.
   Unconfirmed/missing-state assets share the one `asset_not_found` refusal.
4. **MED (JWT forwarding):** the proof-asset route forwards the verified
   caller capability explicitly — header bearer first, verified cookie
   session (`auth.getSession`) otherwise — matching the `media.ts`/`invokeMedia`
   convention, so cookie-session desk streaming reaches the Edge authenticated.
5. **MED (mime/bytes seam):** schema stays optional because the committed
   route test pins empty-body success; consistency is restored on the client
   side: the new helper ALWAYS declares both, so real registrations satisfy
   the strict RPC. Integration request below kept verbatim.
6. **MED (confirm-time binding):** `proofExposure` now binds to the registered
   request when the linkage exists: a request row whose `activeProofAssetId`
   equals the asset id must itself be live (`owner_accepted` /
   `payment_proof_uploaded`) or the flow refuses. A first upload has no
   linkage until attach — that residual gap is exactly integration request 2.
7. LOW notes: the route's presign-failure cleanup stays with its
   unconfirmed-only comment (orphan retention follows MED-012 either way);
   `p_limit: 0` verified against the migration — `coalesce(nullif(0,0),20)`
   clamps to the 20-row default page, semantics confirmed.

## Verification (verbatim)

- Full focused set, 17 files: **Test Files 1 failed | 16 passed (17);
  Tests 2 failed | 329 passed (331)**. The reconciler's three repairs all
  pass now (loser cleanup, desk proof-url authorization, MEDIA_KINDS pin).
  The 2 remaining failures are BOTH the same new conflict below.
- `pnpm --filter @gymloop/shared typecheck`: clean.
  `pnpm --filter @gymloop/web typecheck`: the only errors are two
  `.next/types/validator.ts` "Type 'Route' does not satisfy the constraint
  'never'" diagnostics from stale generated build artifacts — no source-file
  error; present before this round.
- `pnpm --filter @gymloop/web lint`: clean. `@gymloop/shared lint`: only the
  2 pre-existing committed-test errors recorded in round 2.
- `deno check media/index.ts` (2.9.6 via npx from `supabase/functions/`):
  clean.

## New recorded test conflict (test author owns the fix)

`purchase-visible-proof-edge.test.ts` — the two proof-url success tests
("signs a bounded private URL for the owning member only", "also serves the
real same-tenant front-office verifier") run against an UNCONFIRMED asset
(`confirmed = false` from `beforeEach`) and expect 200. That pins exactly the
behavior the fresh critic rejected (signing a GET for a never-published
derived key). Fixture amendment: set `confirmed = true` before these two
tests — the fake then supplies a valid stored published key
(`${tenant}/published/payment_proof/${publishedUuid}.jpg`) and every existing
assertion (imageUrl shape, published namespace, TTL bounds) still runs against
a contract-true state. Verified: with the gate, both tests fail 404 vs 200
solely because of the unconfirmed fixture state.

## Updated hashes (round 3)

| Path | sha256 |
|---|---|
| `supabase/functions/media/index.ts` | c8456e4bc46644f696c16cab17c1389351d714bd3dad9d0d1131294d16ad0d3c |
| `apps/web/lib/media-upload.ts` | 6ac4d4552cb6c560d60f5ed2ef5c8d0b5b1052f8f8f41867f099d29897342566 |
| `apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts` | b4f0ea66395c8007e561953f91e88b6df4351ddfe3b1e1a6eafd736dc09114dd |

Unchanged from round 2: `packages/shared/src/api/media.ts`
(f5d2018f…), `packages/shared/src/api/purchase.ts` (def3e071…),
`apps/web/lib/purchase-http.ts` (d4e78416…), `apps/web/lib/media.ts`
(b633d5aa…). Round-3 diff total across the seven files: 208 insertions /
30 deletions.

## Primary integration requests (restated verbatim intent)

1. **Finalizer amendment (critic finding 1):** `public.finalize_media_asset`
   must admit exactly the member actor (`p_actor_role 'member'`,
   `p_actor_staff_id null`) for kind `payment_proof` with the
   `<tenant>/published/payment_proof/<uuid>.<ext>` key shape; without it the
   member confirm flow can never finalize (42501/22023 at runtime).
2. **Registration linkage (critic finding 7):** persist the request linkage at
   `register_payment_proof` (e.g. store the request id on the asset row or a
   proof-side registration record) so confirm/attach bind the EXACT registered
   request instead of "some live owned accepted request"; the Edge already
   prefers an existing `activeProofAssetId` linkage where present.
3. **Authenticated grant (from fix 1):** optionally extend the
   `media_assets` authenticated SELECT grant with `created_by_member_id` if
   caller-scoped creator reads are ever wanted; not required by the proof
   flows (they read privileged).
4. **mime/bytes seam (critic MED):** with the client now always declaring
   `mime`/`bytes`, the strict `register_payment_proof(p_request_id, p_mime,
   p_bytes)` works as-is; the committed empty-body route test remains the only
   empty-body consumer. If the SQL author prefers server-derived facts
   instead, say so and the schema/client tighten in a later `spec:` round.

## Registry additions proposed (update to round-2 list)

- New web export: `uploadPaymentProof` (`apps/web/lib/media-upload.ts`) —
  member proof upload transport (declare → staging PUT → trusted confirm).
- All round-2 proposals unchanged otherwise.

---

# Round 4 — duplicate-protocol cleanup (2026-10-04)

Critic r2 MED: `uploadPaymentProof` was exported with no caller while
`purchase-actions.tsx` inlined the same register/PUT/confirm protocol.

**Choice: WIRED, not dropped.** `MemberPurchaseActions.upload` now delegates
to the shared helper — one copy of the client protocol. The component keeps
its hidden file input, its client preflight (mime/size/`acceptedRevision`
refusals, unchanged), its success message and `router.refresh()`, and maps
the helper's two transport stages onto its existing honest stage words
(`uploading` → "Uploading screenshot…", `verifying` → "The gym is checking
the upload…"). The now-dead local `postCommand` inline runner is removed with
the protocol it duplicated. Only `apps/web/app/member/buy/purchase-actions.tsx`
was edited — no other file, migration, or test touched. The LOW
verifier-reobtain-for-recorded question is untouched, as instructed.

## Verification (verbatim)

- Focused set (the critic's eight proof/purchase suites + the nine media
  suites): **Test Files 1 failed | 16 passed (17); Tests 1 failed |
  302 passed (303)**. The single failure is the owner-adjudicated
  "Payment recorded" wording conflict in
  `purchase-visible-proof-surface.test.tsx` — identical test, identical
  cause as critic r2 recorded before this round; no regression.
- `pnpm --filter @gymloop/web typecheck`: no source errors (only the two
  stale `.next/types/validator.ts` artifacts noted in round 3).
- `pnpm --filter @gymloop/web lint`: clean.

## Hash (round 4)

| Path | sha256 |
|---|---|
| `apps/web/app/member/buy/purchase-actions.tsx` | 119f216d3728a440b94b1cb15eace67d88d786100aa7c96ac1f8a3db9eafe764 |

All other round-3 hashes unchanged.

---

# Round 5 — holdout Class A closure (2026-10-04)

Class A (`parallel-media-pay-holdout-diagnosis.md`): proof-url ran the caller
request read without status enforcement, then took the privileged asset read
before any refusal — a foreign or arbitrary confirmed proof id cost a
privileged read. Closed in `supabase/functions/media/index.ts`:

- `proofExposure` now takes the admissible status set. `proofUrl` requires the
  served statuses (owner decision 2026-10-04: `owner_accepted`,
  `payment_proof_uploaded`, `recorded`, `mismatch_recorded` — a bound proof
  stays viewable on its recorded request) and `proofConfirm` keeps the live
  set (`owner_accepted`/`payment_proof_uploaded`). The refusal now happens on
  the caller-JWT read ALONE — requested/rejected/cancelled/expired requests,
  foreign tenants (RLS-empty in reality) and unexposed targets never reach any
  privileged metadata read. The `activeProofAssetId` binding remains: when a
  row carries the linkage, THAT row must carry an admissible status.
- Verified against the current reconciled fixtures, including the new
  owner-decision cases (recorded/bound member + verifier views).

## Verification (verbatim)

- Full focused set (17 files): **Test Files 17 passed (17); Tests 310 passed
  (310)** — zero failures, including the previously adjudicated surface case.
- `deno check media/index.ts` (2.9.6, from `supabase/functions/`): clean.
- Shared typecheck clean; web typecheck: zero source errors (the 2 stale
  `.next/types/validator.ts` artifacts remain the only diagnostics).

## Hash (round 5)

| Path | sha256 |
|---|---|
| `supabase/functions/media/index.ts` | 67223b2f1d467507583ba70677b0ed3e572bba7b185872897619788a694a8d1b |

All other round-3/4 hashes unchanged. No commits; holdout/scratchpad never
opened; no migration touched. Integration requests (rounds 3–4) stand.

---

# Round 6 — signer kind-gate + strict proof-url linkage (2026-10-04)

Two contract closures in `supabase/functions/media/index.ts`:

1. **Photo-boundary kind gate (contract: "do not broaden existing public
   catalogue signer or staff photo readers").** The confirm/staff-url branch
   now refuses kind `payment_proof` at the caller-scoped safe read — BEFORE
   the privileged read — so a confirmed proof asset can never be signed
   through `staff-url` nor finalized through the photo `confirm`.
   `asset_not_found`, the standard external refusal. Member-url keeps its
   existing gate (it cannot kind-check pre-privileged without a caller asset
   read the authenticated grant does not carry; its attachment/published
   refusal stays the available boundary — unchanged this round).
2. **Strict proof-url linkage (closes the round-5 residual).** `proofUrl`
   now passes `requireBound`: the caller-JWT request read must contain a row
   whose `activeProofAssetId` equals the asset id (with a served status —
   owner decision 2026-10-04 set preserved). No fallback remains: superseded,
   rejected-proof, unlinked and arbitrary confirmed ids share the one
   `asset_not_found` refusal from the caller read alone, before any
   privileged metadata read or signature. Verified against live source: both
   `read_member_purchase_requests` and `read_purchase_requests` project
   `activeProofAssetId` through `app.pay_request_json`, and the frozen attach
   flow always sets it before proof-url can legitimately be called.

## New recorded test conflict (test author owns the fix)

The six proof-url success tests fail 404-vs-200 because the fixture's
`proofDetail()` still omits `activeProofAssetId` — the strict linkage is
therefore unexpressible in the fake. Fixture amendment (one line): add
`activeProofAssetId: assetId` to `proofDetail()` in
`apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`. Every success
case then models the true post-attach state (the fixture's `attached_to_id`
already equals `proofRequest` when confirmed — same fact at the asset side),
and all existing assertions (imageUrl shape, published namespace, TTL,
owner-decision statuses) run against the linkage truthfully. The refusal
cases stay refusal cases: an unlinked id matches no row and refuses before
the privileged read.

## Verification (verbatim)

- Full focused set (17 files): **Test Files 1 failed | 16 passed (17);
  Tests 6 failed | 304 passed (310)** — the 6 failures are all the single
  fixture gap above (verified: 404 from the linkage gate, not another path).
- `deno check media/index.ts` (2.9.6, from `supabase/functions/`): clean.

## Hash (round 6)

| Path | sha256 |
|---|---|
| `supabase/functions/media/index.ts` | cfb585a5aeb6d6f1604afd5beb445d8de72515f6518d6a89e6d7823e7aa34832 |

All other round-3/4/5 hashes unchanged. No commits; holdout/scratchpad never
opened; no migration touched; integration requests stand.
