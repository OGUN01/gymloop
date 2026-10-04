# Parallel MEDIA/PAY — fresh blind SQL critic (2026-10-04)

Static review only — Cloud SQL is primary-owned; nothing executed. Target:
uncommitted `supabase/migrations/20261004100000_purchase_requests.sql`
(sha256 `a750dda04e2a21f5…c1b84397`, 217+/19−). Judged against
`supabase/tests/79_purchase_requests.sql` plan(216), the frozen BUY contract,
and the implementer self-check report (claims verified against bytes).

## Findings

- MED `finalize_media_asset` member path: the actor lock re-proves tenant+user
  binding but NOT member account status — a cancelled/blocked/erased member
  still passes (`members.status`/`erased_at` unchecked; compare the
  `shop_actor` discipline at migration line 1211). Edge's `proofExposure`
  recheck partially mitigates (caller-RLS request read), but BUY-001's
  blocked/cancelled/erased refusal should be one cheap conjunct on the
  existing `for update` members select. Suite does not pin it — add both.
- LOW register_payment_proof supersession loop has no request-scoped
  serialization: two concurrent registrations can both pass the loop and leave
  two live unconfirmed candidates. Harmless — BUY-010's one-active-proof
  invariant is enforced at attach/confirm and the loser is never deleted while
  uncertain — but an advisory lock on the request would close it.
- LOW suite `purl` helper (line 42) is dead unless used elsewhere in-file;
  harmless. (Out of patch scope.)
- Out-of-scope hunks ride the same working-tree file from other agents'
  uncommitted work — sanity-checked, not blocking: `currency` generated column
  (valid, plain-source only), GL055 kind-change refusal (consistent with
  ADD/SHP invariants), `pay_held_view` definer wrapper (postgres-owned
  `security definer`, inner private reader stays ungranted — SHP-024 kept).

## Per-check results

1. Member finalization admission — **PASS**: creator-only + payment_proof-only
   + registered live accepted request; 42501 (non-creator/staff/foreign),
   22023 (kind/namespace/mime), GL086 (tombstone/inconsistent), GL066
   (cancelled registered request) all raised before the single privileged
   UPDATE; replay returns false read-only before liveness (BUY-016).
2. Staff-created asset behavior — **PASS**: staff path and shared publication
   block unchanged; staff actor refused on member-created proofs only.
3. linked_request_id — **PASS**: composite FK to `purchase_requests
   (tenant_id, id)` (unique key at line 71), partial index on
   (tenant_id, linked_request_id), immutability trigger extended to bind
   trusted writers, no new table policy, tombstone semantics intact.
4. Re-obtain — **PASS**: status-aware proof selection (`active` pre-recording,
   `bound` for recorded/mismatch_recorded — recording sets `bound` at line
   2304); payload keeps requestId/url/expiresAt only (suite pins zero keys/
   ETags); trainer/impersonation/unknown/foreign collapse to one P0002;
   cancelled-without-binding refused; pre-recording refusals unchanged.
5. Rollback safety / privileges — **PASS**: 70 `$fn$` (even), zero commit/
   dblink/COPY; `search_path=''` on amended definers; original
   `revoke all … from public,anon,authenticated,service_role` + service_role
   grant in 20261003120000_shop.sql (735/743) survives CREATE OR REPLACE;
   body independently refuses non-service_role callers; no new PUBLIC/anon
   execute; 'proof_url' capability no longer minted or consumed anywhere
   (path was unreachable — removal consistent).
6. Money paths / SQLSTATE / audit — **PASS**: record_purchase_request and
   ledger untouched by the three amendments; no SQLSTATE outside GL123–126 +
   shared classes; audits carry only confirmed/deleted booleans and actor ids.
7. plan(216) mapping — **PASS**: every new assertion group (member finalize
   M1/M3/S1/S2/W1/143, registration refusals, supersession, GL126 cap,
   KR1U/KR1V/KR2U re-obtain, trainer/preview/unknown refusals, KF4) has a
   matching behavior in the patch; no unsatisfiable assertion found.
8. Types regeneration — **PASS**: no hand-edit of packages/db/types
   (clean in git status); new `media_assets.linked_request_id` +
   `purchase_requests.currency` require the documented ADR-177 `supabase gen
   types` follow-up after CI migrate; schema-drift gate will (correctly) fail
   until then.

## Edge seam (coordinator-flagged, verified here)

Edge `publishAndFinalize` args (index.ts:189) match the amended signature
exactly — 12 params, same names/order; the proof path passes
`p_actor_role='member'`, `p_actor_staff_id=null` (index.ts:248, 189).

## Verdict

**GO-WITH-FIXES** — one MED (member-status conjunct in the finalizer member
path, plus its suite pin) before treating the money-adjacent publish path as
complete; LOWs optional. RED→GREEN proof remains the primary's Cloud preview +
pg_prove (plan 216), then ADR-177 types follow-up.

## Closure round (2026-10-04, final bytes sha256 46446c5c…81a70)

- MED closed — **VERIFIED in bytes**: `finalize_media_asset` member actor gate
  (line 795-796) now reads `m.status='active' and m.erased_at is null for
  update`, before the asset select and liveness check. Cancelled/blocked/
  erased creators cannot pass (suite pins all three at 42501 with an active
  status control). No other refusal changed — the conjunct only narrows the
  member actor gate; revocation-before-replay is the correct precedence
  (handoff: revoked actor refuses safely; BUY-016 replay binds non-revoked
  actors). Staff gate already had the equivalent (`is_active`).
- LOW resolved — **advisory-lock claim TRUE in bytes**: `pg_advisory_xact_lock
  (hashtextextended('purchase-request:'||tenant||':'||request_id,0))` sits
  before the request lookup; hourly caps (GL126 + media GL086), the
  supersession sweep and the insert all follow under it. My serialization
  finding was already closed in the original bytes — missed it above the diff
  hunk context.
- plan(226) — **VERIFIED**: 216 + 10 status pins map to the conjunct
  (positive control, cancelled, blocked, erased; W3/W4 request isolation
  prevents supersession contamination); dead `purl` helper removed,
  count verified. Suite sha256 `5f7ec3e3…1e02a`.
- Final-byte sanity: 222+/19−, 70 `$fn$` (even), zero `commit;`, all other
  checks (money untouched, audits carry no keys/URLs, privileges intact,
  refusal matrix unchanged) hold on this hash.

## FINAL VERDICT: **GO**

Static review only (Cloud SQL primary-owned). Remaining proof obligations are
unchanged and external to this review: primary's Cloud rollback preview +
pg_prove of plan(226), then the ADR-177 `supabase gen types` follow-up after
CI migrate (`media_assets.linked_request_id`, `purchase_requests.currency`).
