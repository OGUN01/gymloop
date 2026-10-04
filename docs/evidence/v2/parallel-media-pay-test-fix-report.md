# Visible test fixture corrections — PAY proof edge/shared (2026-10-04)

Author-role fork. Holdout never opened; no source file edited; nothing
staged or committed. Only the two test files below were changed.

## Baseline (verbatim)

`pnpm vitest run apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts
packages/shared/src/api/__tests__/media-visible.test.ts
packages/shared/src/api/__tests__/purchase-visible-contract.test.ts
apps/web/app/__tests__/purchase-visible-routes.test.ts`
→ **Test Files 2 failed | 2 passed (4); Tests 3 failed | 180 passed (183).**

## Fix 1 — loser-candidate cleanup fixture

- File: `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
  (final sha256 `52212555d3bbd209b16993a483f1fcb3b9d7500b938311d9afe83ee773fb4d34`).
- Deciding clause: media-verification-amendment §"Verification, races, replay
  and failure" item 4 — "Loser observes false, removes only its own
  unreferenced candidate… Never remove another attempt's candidate or the
  winning published object."
- Defect: in `loser` mode the fake finalize RPC never set `winningKey`, so the
  existing assertion `not.toContain(winningKey)` ran against `''`, which
  matches every string — the winner-preservation guarantee was asserted
  vacuously.
- Edit: the fake's `loser` branch now sets
  `winningKey = <tenant>/published/payment_proof/<publishedUuid>.jpg` (a
  distinct winner key) before returning `false`. The assertions are
  unchanged: exactly one published DELETE, it must equal this attempt's own
  `candidate`, and it must not contain the winner's key — now meaningful.
  Coverage strengthened, nothing weakened.

## Fix 2 — auth double ignored override claims

- File: same (`purchase-visible-proof-edge.test.ts`).
- Deciding clauses: BUY-009 (proof GET authorized independently for own member
  OR same-tenant front-office verifier) and the amendment's
  "The Edge endpoint independently validates Auth token authenticity…"
  The desk-verifier authorization case was unreachable because the fake
  `/auth/v1/user` handler answered from the module-level `claims` variable
  regardless of the per-test override token, making every override identity
  internally inconsistent (member id in the user row, staff subject in the
  token) and refusing 403 by construction.
- Edit: the fake handler now derives `id`/`app_metadata` from the request's
  own bearer token payload (decoded JWT segment) instead of the module
  variable; the `invalid-token` 401 branch and response shape are unchanged.
  All auth-first ordering assertions (caller read precedes privileged access;
  refusal before body/privileged consumption) still pass unchanged against
  the now-consistent identities. Coverage strengthened: desk verifier path
  now genuinely exercised instead of passing vacuously.

## Fix 3 — stale MEDIA_KINDS pin

- File: `packages/shared/src/api/__tests__/media-visible.test.ts`
  (final sha256 `e4bee9df3f640affea2d4f655c7993caf5f67a3c51b220c32759a5c1e547bbc0`).
- Deciding clause: member-purchases proposal, "Proof media extension"
  paragraph — "add `payment_proof` to non-status `MediaKind`/DB kind check".
  The older committed pin of exactly three kinds directly contradicted the
  newer committed proof test; the frozen contract sides with the newer test.
- Edit: pin updated to
  `['product', 'trainer', 'announcement', 'payment_proof']`, and the
  namespace round-trip `it.each` gained `payment_proof` (strengthening). Every
  original photo-kind assertion (mime table, extensions, key round-trips,
  malformed-key refusals, photo-only upload schema) is preserved verbatim.

## After (verbatim, same four files)

**Test Files 4 passed (4); Tests 184 passed (184)** (+1 test from the
strengthened round-trip each; 3 failures → 0).

Guard run over the remaining proof suites
(`purchase-visible-proof-media`, `purchase-visible-proof-upload`,
`purchase-visible-proof-surface`, native proof upload): 1 failed | 26 passed.
The single failure is exactly the recorded owner-adjudication conflict —
`purchase-visible-proof-surface.test.tsx` "a request with an uploaded proof
stays Pending verification with no payment claim" vs
`purchase-visible-member-buy-page.test.tsx`'s required 4-word stepper
containing "Payment recorded" at `payment_proof_uploaded`. Not touched here;
needs the primary's BUY-022 `spec:` ruling.

## Adjudication note (contract vs source)

No instance found where the committed source contradicts the frozen contract
in the three repaired areas: the source already admits `payment_proof` in
`MEDIA_KINDS`, cleans only the loser's own candidate, and authorizes proof-url
from the caller's own token identity — the tests were the defective side in
all three cases.

## Round 2 — proof-url verified-state gate fixtures (2026-10-04)

Coordinator amendment: the source implementer's round 3 added the
contract-required gate — proof-url signs only through confirmed/published
state (BUY-008/BUY-009; amendment: "Missing verified state → asset_not_found"),
derived-key fallback removed. Two proof-url success fixtures still staged an
UNCONFIRMED asset, pinning exactly the pre-gate behavior the contract forbids.

- File: `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
  (new sha256 `1393acff2fd4e33ec192d1d49ac99702865d87cdeb91aa579c79c12d4f5fde00`).
- Edit: `confirmed = true` staged at the start of exactly the two proof-url
  success tests ("signs a bounded private URL for the owning member only",
  "also serves the real same-tenant front-office verifier"), so their existing
  assertions now run against a confirmed, privately published proof —
  contract-true staging, not weakened assertions. All refusal/foreign/unprivileged
  proof-url cases, the auth-first ordering checks and every other assertion are
  untouched. No source file was read for editing and none changed.
- Run (coordinator's list; note `apps/web/lib/__tests__/purchase-visible-proof-upload.test.ts`
  does not exist — the real app-side file `apps/web/app/__tests__/purchase-visible-proof-upload.test.ts`
  was included, so 6 files matched):
  **Test Files 6 passed (6); Tests 203 passed (203)** — fully green. The
  owner-adjudicated "Payment recorded" conflict lives in
  `apps/web/app/__tests__/purchase-visible-proof-surface.test.tsx`, which is
  not part of this file list; it remains the one open failure campaign-wide
  and awaits the primary's BUY-022 `spec:` ruling.
- Coverage: strengthened-or-equal throughout; nothing weakened.

## Round 3 — owner decisions encoded in visible tests (2026-10-04)

Owner decisions 2026-10-04 (authoritative): stage labels OK; expo-image-picker
approved; bound-path proof-url re-obtain allowed for owner member + same-tenant
verifier.

1. Fixture repair `purchase-visible-proof-surface.test.tsx`: blanket
   "Payment recorded" ban at payment_proof_uploaded narrowed to state-claim
   copy (payment successful / payment has been recorded / money recorded /
   payment received / bank verified); the future stage label is now asserted
   present. Preserves the member-buy-page 4-word stepper pin. GREEN.
2. New cases `purchase-visible-proof-edge.test.ts`: proof-url serves the
   owning member AND same-tenant desk after `recorded`/`mismatch_recorded`
   (≤60s, published namespace, no staging), single external refusal kept for
   trainer/impersonation/foreign. **GREEN already** — the Edge boundary has no
   bound-path status gate (verified against current Edge source). Any bound-path
   refusal the r2 critic saw lives SQL-side (`pay_take_capability` capability
   path / `pay_proof_evidence` is status-agnostic); SQL-side enforcement cases
   belong to the SQL/holdout authors (h79), not runnable locally here.
3. New RED cases `purchase-visible-native-proof-upload.test.tsx` (mocked
   `expo-image-picker` per file conventions): staged pick flow (declared
   mime/bytes, proof endpoint, honest pending copy), cancelled pick (no
   network), offline (refused before picker/network — this one passes
   against the existing guard). **RED-by-design awaiting source**: the two
   picker cases — `buy.tsx` `proofUpload` still shows the honest placeholder
   and never invokes the picker.

Final 6-file verification (verbatim): `Test Files 1 failed | 5 passed (6)` /
`Tests 2 failed | 85 passed (87)` — the 2 failures are exactly the
RED-by-design picker cases. No assertion weakened anywhere.

sha256 (16): surface `80aee03a4549da67`, edge `68b0ab28eba3dc91`,
native `0f6048c5af7f1d34`.

## Round 3 — visible SQL author: PAY migration amendment tests (2026-10-04)

Suite extended: `supabase/tests/79_purchase_requests.sql`
sha256 `261f18d183eee6dc6faf599beb2dd612c4d5ee54cbf1c08b11fbb353eb39ded9`. plan(154) → **plan(203)** (+49 assertions);
`select * from finish()` / rollback discipline unchanged; lowercase `begin;` kept.

Pinned (contract labels only):
- BUY-008 registration: member registers staging proof for a live accepted
  request; server-chosen tenant-leading private staging key; unconfirmed start.
- BUY-008 registration refusals: unknown/foreign request P0002; null arguments,
  unsupported mime, oversized (>2 MiB), empty bytes → 22023.
- BUY-008 member finalization: service-only finalize with member actor
  succeeds into `<tenant>/published/payment_proof/<fresh>.<ext>`; verified
  source + published ETags stored; replay returns false with exactly one
  `media_asset.confirmed` audit (BUY-010/016/020).
- BUY-008/009/019 finalization refusals: non-creator member (even with own
  live accepted request), staff actor on member proof, foreign tenant →
  42501; kind/namespace/mime mismatch → 22023; refused finalizations never
  publish (object_key stays null).
- BUY-010 supersession: second registration for the same request tombstones
  only the unconfirmed loser (deleted_at), winner stays live and finalizes;
  tombstoned candidate finalize → GL086:media_not_ready; fresh registration on
  a proof-uploaded request never disturbs the confirmed attached winner.
- BUY-018/GL126: member rolling-hour proof cap (tenth succeeds, eleventh
  GL126:proof_limit).
- BUY-008 liveness: after the registered request is cancelled, finalization
  refuses GL066 — registration-time request linkage pinned behaviorally.
- Frozen RPC surface: `register_payment_proof(uuid,text,integer)` (definer,
  volatile) and `read_purchase_proof_url(uuid)` (invoker, stable) added to the
  exact-signature pin; count 11 → 13.

Coverage note: h79 supplements for the same amendment are the holdout author's
job (h79 never opened here). RED is unexecuted: Cloud SQL is primary-owned;
CI/primary preview proves it. The implementer patches the migration only after
these tests are committed.

## Round 4 — owner decision 3 (binding, 2026-10-04): post-recording proof URL

Suite extended again: `supabase/tests/79_purchase_requests.sql` sha256
`5adeb25c7efba5de003200f60edcb54c3db2e774e2a857de74777809c0448a40`.
plan(203) → **plan(216)** (+13 assertions), conventions unchanged.

Pinned (BUY-009, owner decision 3):
- recorded request (KR1) → owning member obtains the private proof URL
  (RED today: the capability gate refuses bound/terminal states).
- Payload pins: names its own request; URL is exactly the application
  proof-asset path `/api/purchase-requests/<id>/proof-asset`; expiresAt
  bounded ≤60s; no staging/published keys, ETags or object_key fields.
- recorded request → same-tenant front-office verifier obtains the same
  request's proof URL.
- mismatch_recorded (KR2) → owning member obtains the proof URL.
- trainer, platform-preview (impersonation claim) and unknown request →
  each `P0002` — the one shared external refusal.
- cancelled-without-binding (KF4, closed after staging) → still refused
  `P0002`; expired needs the clock seam (holdout-owned, noted).

New helper `pg_temp.purl` is deliberately security INVOKER (plpgsql default)
so `read_purchase_proof_url`'s invoker semantics are preserved; capture table
`urls` added to the temp-table grant line.
RED unexecuted: Cloud SQL is primary-owned; CI/primary preview proves it.

## Round 5 — SQL critic MED: member-status re-proof at finalization

Suite extended: `supabase/tests/79_purchase_requests.sql` sha256
`5f7ec3e3b867766efe551a40fc8625c4c5b73434f0048711c3d12fc8afd1e02a`.
plan(216) → **plan(226)** (+10 assertions), conventions unchanged.

Pinned (BUY-001, mirrored from the staff actor gate):
- Positive control: active member creator (35, own live accepted request,
  correct registration metadata) finalizes → true.
- The same creator after `status='cancelled'` → finalize refuses like 42501
  (request still live/accepted, asset alive/unconfirmed — the member-status
  gate is the isolated cause).
- Blocked member-34 creator (prefab unconfirmed asset, valid staging key) →
  refuses like 42501.
- Erased member-31 creator (`erased_at` set post-reads; asset 143 creator
  matches, unconfirmed) → refuses like 42501.
- W3/W4 sit on separate requests (KF5/KF6) so the round-3 supersession pin
  cannot contaminate the status-refusal isolation; fresh member-35 creation
  counts stay inside BUY-018 caps.
- Dead `pg_temp.purl` helper removed (helper + grant entry) — the round-4
  capture used direct invoker-context calls; count verified unchanged.

RED unexecuted: Cloud SQL is primary-owned; CI/primary preview proves it.
Implementer round follows: the amendment must add the member-status
re-validation at the actor gate (before asset/liveness checks).

## Round 6 — implementer linkage fixture amendment (2026-10-04)

- Edit: `proofDetail()` in `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
  gains `activeProofAssetId: assetId` — implementer round 6 made strict
  proof-url linkage require the caller-read row to carry the pointer at a
  served status (no fallback; attach always sets it before proof-url is
  legitimate). Single shared fixture covers all six proof-url success cases
  (member/desk × owner_accepted/recorded/mismatch_recorded) plus
  proof-confirm; refusal cases untouched; no other change.
- Run (verbatim): `Test Files 4 passed (4)` / `Tests 72 passed (72)` — full green.
- sha256 (16): `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
  = `839c20de3edf3eb4`.
