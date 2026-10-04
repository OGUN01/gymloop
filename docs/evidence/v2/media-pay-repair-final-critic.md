# Fresh source-only critic — MEDIA/PAY repair round final verdict

2026-10-04. Source inspection + local test execution only. No runtime,
database, device, Cloud or deployment acceptance claimed. HEAD at review:
`f1fff2e3` (13-commit lineage after the byte-identical history split). The
working tree carries the repair-round source as uncommitted changes; all
citations below are to those bytes (hashes: migration `d9d0370cb6da489a…`,
Edge `e62b0162514227b2…`, shared schemas `b28e83496d4b8caf…`).

## Per-finding closure — report A (`media-pay-current-fresh-critic.md`)

| # | Finding | Status | Evidence |
|---|---|---|---|
| A1 | Scalar page decode (web/mobile) | CLOSED | `apps/web/lib/purchase.ts:81-88` safePurchasePage consumes `{requests,nextAfter,nextAfterId}`; native `apps/mobile/lib/purchase.ts:75-88` decodePage; declared-key projection :43-49; routes return the scalar page (purchase-visible-page-decode pins the exact envelope) |
| A2 | Proof GET protocol/deadline | CLOSED | Route reads `[id]` (`proof-asset/route.ts:37`); capability mandatory :38-41; `verifyProofCapability` `apps/web/lib/purchase-http.ts:103-126` — HMAC over the existing R2 secret, `exp ≤ iat+60s` :123, expired/future-iat refuse :124, GET never re-mints; named return type `returns table (proof_id uuid, asset_id uuid)` migration:2888 |
| A3 | Expected revisions ignored | CLOSED | attach validates :2039-2042, replay facts carry asset+revision :2007; record validates :2505-2509, facts include viewed tuple :2458-2461; replacement invalidates: viewed asset must equal current `active_proof_asset_id` :2512-2515 |
| A4 | Pre-privilege exposure / attach linkage | CLOSED | Edge proofUrl binds on the caller-read's exact `linked_request_id` — no any-live-request fallback (`media/index.ts:258-280`; attached path requires `activeProofAssetId === id` :274-275; unattached path requires the latest never-attached registration :277-280); attach enforces `linked_request_id = p_request_id` migration:2052, first attach included |
| A5 | No post-await revalidation | CLOSED | proofUrl revalidates registration :287-288, actor :289, live rows :290-292, and again after signing :294-296; confirm replay revalidates live-owned-registered from the caller read alone :246-252 |
| A6 | Lost retry identity | CLOSED | Keyed registration overload migration:770-813 — same actor/key+facts replay same asset/staging facts with no counter use :790-806, changed facts GL068 :804; web sends the retained key (purchase-http.ts:241-247); native transport self-contained with `registrationKey` param (proof-upload.ts:26-34); screens retain both keys per logical upload |
| A7 | Verifier/replacement surfaces | CLOSED | Desk viewer fetches the capability URL and gates recording on the exact screenshot rendering (`purchase-desk-actions.tsx:30-55` — `recordDisabled = … && !proofLoaded`); rejection binds the exact viewed asset; replacement offered in `payment_proof_uploaded` on web (`purchase-actions.tsx:66-68`) and native (`buy.tsx:170-172`); native reloads after upload (`buy.tsx:95,144`) |
| A8 | Renewal revision unrepresentable | CLOSED (text) | Renewal carries a generated accepted revision; creation revision optional/null per frozen decision 4; suite 79 plan(246) pins the SQL side — unexecuted, primary's Cloud preview proves |
| A9 | Bound-history viewing | CLOSED | Active-only at both layers: evidence helper serves only live `owner_accepted`/`payment_proof_uploaded` with unexpired deadline (migration:2927-2930), else P0002 :2957; Edge `PROOF_LIVE_STATUSES` :231,237 |
| A10 | Handwritten vocabulary / duplicated bounds | OPEN (disclosed debt) | Shared tuples remain handwritten with a documented pinned-equal comment (`packages/shared/src/api/purchase.ts:27-40`); R10 test RED pending the primary's `gen types` after CI migrate (ADR-177 flow) — resolves at that push, no further code change identified. Bounds centralized (MEDIA_LIMITS at purchase.ts:3,65) |
| A11 | GL126 | CLOSED | Zero occurrences; caps refuse `22023` DETAIL `purchase_cap` (migration:722, 1505, 1512) |
| A12 | Evidence helper member/expiry gaps | CLOSED | Member status/erasure reproof :2904-2907; request expiry :2929-2930; staff role/active proof :2910-2919 |

## Per-finding closure — report B (`media-pay-fresh-primary-security-critic.md`)

| # | Finding | Status | Evidence |
|---|---|---|---|
| B1 | proofExposure any-list signing | CLOSED | Superseded by the rebuilt boundary: exact registration binding from the caller read, no page fallback (media/index.ts:258-280); staff-url/photo confirm refuse `payment_proof` at the caller-scoped safe read (kind gate, :244 and photo branch) |
| B2 | Route params/shape/expiry | CLOSED | Same as A2; envelope `{url,expiresAt}` only (purchase-http.ts:222-225), URL carries the capability, never a storage key/R2 signature :220-222 |
| B3 | Native decode/identity hygiene | CLOSED | decodePage scalar :75-88; stale last-good flagged :99,:129; identity-scoped clearing on change/gone |
| B4 | Finalizer member status / replay bypass | CLOSED (text) | Record-side member recheck migration:2523-2528 (cancelled/blocked/erased refuse); finalizer liveness precedes confirmed-replay (suite 79 plan(246) pins the ordering — unexecuted, text-verified) |
| B5 | Attach registration linkage | CLOSED | migration:2052 |
| B6 | Replacement/retry UX | CLOSED | As A7/A6 |
| B-static | Anonymous `returns record` | CLOSED | migration:2888 concrete named columns; callers select the named columns :2992-2996 |

## Ten critical checks — all PASS

1. Auth-before-privileged ordering: PASS (caller RLS read → exact binding → privileged lookup, registration/confirm/url; attach independently re-proves).
2. Active-only viewing: PASS (SQL evidence helper :2927-2929 + Edge live-status filter :231,237 — recorded/mismatch/bound refuse for everyone).
3. Viewed-evidence binding: PASS (pre-ledger comparison :2510-2518; replay facts complete :2458-2461; half-tuple refuses :2510-2511; cash path lawful :2493-2496 with viewed tuple null).
4. Expected revisions + replacement invalidation: PASS (:2039, :2505, :2512-2515).
5. Registration replay: PASS (migration:790-806).
6. Capability discipline: PASS (purchase-http.ts:103-126; route no-store :71; no keys/ETags/contents in URL/envelope/logs — capability payload carries ids/instants/actor/tenant only).
7. GL126 absent; caps 22023/purchase_cap (migration:722,1505,1512); GL123–125 present and untouched.
8. Scalar page protocol end-to-end: PASS (loaders, routes, Edge proofRows :235 accepts the scalar shape; audience-aware projection; declared facts pass through as received).
9. Status vocabulary: PASS-WITH-DEBT — migration defines the Postgres enums (source of truth); shared tuples are transitional, documented pinned-equal to generated `Constants.public.Enums.*`, with the R10 test enforcing equality at gen-types time (AGENTS rule 5 debt that resolves at the primary's types push — not a code change available before migrate).
10. Photo operations preserved; payment_proof refused through photo confirm/staff-url (Edge kind gate at the caller-scoped safe read); money paths untouched; no new secrets/env reads outside env.ts; no suppressions (escape-hatches 948 files clean).

## Verbatim runs

- Visible repair set (14 files): `Test Files 1 failed | 13 passed (14)` /
  `Tests 1 failed | 218 passed (219)` — sole failure R10 (pending `gen types`).
- Holdout boundary suite (run without reading its internals):
  `Test Files 1 passed (1)` / `Tests 25 passed (25)`.
- `check-pgtap-rollback`: 159 files, all rollback-wrapped. `registry-lint`:
  every exported symbol registered. `check-escape-hatches`: 948 files, no
  suppressions. `deno check media/index.ts`: exit 0.

## Final verdict

- (a) SQL + migration: **GO** (text-verified; plan(246) execution is the
  primary's Cloud preview, unexecuted here).
- (b) Edge: **GO**.
- (c) Web/native transport + surfaces: **GO-WITH-FIXES** — the single residue
  is the transitional status-vocabulary tuples (`purchase.ts:27-40`), a known
  AGENTS-rule-5 debt that resolves mechanically at the primary's post-migrate
  `gen types` push (R10 test then goes green); no additional code change
  identified.

## Remaining primary-owned steps (never claimable from this review)

1. Cloud rollback preview executing visible suite 79 plan(246) + the holdout
   SQL halves (binding under locks, viewed-evidence comparison, replay
   storage, renewal sold-terms, active-only SQL boundary).
2. `supabase gen types typescript --linked` after CI migrate; R10 then green.
3. Protected MEDIA Edge deployment (`production-media` environment).
4. Live R2/browser/Android proof per the frozen acceptance flow; no
   end-to-end acceptance exists until then.
