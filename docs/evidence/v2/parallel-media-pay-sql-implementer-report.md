# SQL implementer report — PAY migration amendment (round 1, 2026-10-04)

Target: `supabase/migrations/20261004100000_purchase_requests.sql` (uncommitted,
unapplied — amended in place; no new migration). Post-patch sha256:
`a750dda04e2a21f555c33cdffbfae9c606c44e1951d9e5d8e462be06c1b84397`.
Spec: the +62 new RED assertions in `supabase/tests/79_purchase_requests.sql`
(plan 154 → 216; finalizer/linkage 49 + re-obtain 13). All edits additive/surgical;
no test file touched; h79 and tests-holdout never opened; no Cloud SQL; no commits.

(See round 2 below for the coordinator-directed follow-up against plan(226);
current file sha256 `46446c5c31680ea0ffbdfe00334c67107188b23ba90e43660dac02eed1881a70`.)

## Patch summary (three amendments)

1. **Member finalization** — `create or replace function public.finalize_media_asset`
   (PAY-side amendment of shop.sql's credential-only finalizer; shop.sql itself
   untouched, migration order guarantees replacement). New member path
   (`p_actor_role='member' and p_actor_staff_id is null`): locks the active member
   row before the asset (revocation serializes), then requires the asset be kind
   `payment_proof` AND `created_by_member_id` resolve to the calling user. Staff
   path byte-for-byte as before, plus one new refusal: a staff actor can never
   finalize a member-created proof (42501). Metadata check extended: `payment_proof`
   admitted to the kind set; published-key regex branches per kind
   (`published/payment_proof/…` vs the original photo namespaces), same
   tenant-prefix/kind-segment/extension-mime checks → 22023. Deleted →
   `GL086:media_not_ready`; replay (confirmed) → read-only `false` with no second
   audit — both unchanged and BEFORE the new liveness gate. Member path then
   re-proves the registered request live and accepted (`status in
   ('owner_accepted','payment_proof_uploaded') and expires_at > now()`); any
   failure → `GL066:request_not_accepted`. Publish block (marker, conditional
   update, single audit) unchanged.
2. **Registration-time request linkage** — `media_assets.linked_request_id uuid`
   (+ composite FK to `purchase_requests(tenant_id,id)` + partial index), set by
   `register_payment_proof` at insert (`v_request.id`). Registration-facts
   immutability row-compare in `enforce_media_asset_verification` extended with
   the column. No schema change the tests forbid (they pin behavior, not schema).
   Verified the pre-existing registration already bound request+asset in its
   authorization logic; the linkage column makes that binding durable for the
   finalizer's re-proof.
3. **Re-obtain gate (owner decision 3)** — `app.pay_proof_evidence` reworked: the
   minted-capability take (`'proof_url'`, never minted by any command — the path
   was unreachable for a direct invoker read) is replaced by in-function
   re-proof of the real, unimpersonated session class (member: complete member
   claims + own member row; staff: real active front-office row). Request-level
   owner check unchanged. Proof selection is now status-aware: live
   pre-recording states serve the single `active` proof; `recorded` /
   `mismatch_recorded` serve the `bound` proof (owner decision 3, ≤60s, no
   storage metadata — payload unchanged); every other state (rejected,
   cancelled, expired) keeps the one external refusal. `read_purchase_proof_url`
   resolves the actor itself and collapses trainer / impersonation /
   contradictory / incomplete session shapes into the same `P0002` refusal
   (previously `app.shop_actor` raised 42501 for those — the tests pin P0002).
   Signature, invoker/stability, grants and the thirteen-RPC surface pin
   unchanged.

## Self-check table (static reasoning — UNEXECUTED; Cloud SQL is primary-owned)

| Assertion group (suite 79 lines) | Satisfied by | Why (static) |
|---|---|---|
| 465-469 M1 member finalize true + replay false + 1 audit | Amendment 1 | member path end-to-end; replay returns before liveness and audit |
| 473/477/478/479/480/481/482/483 M3 refusal matrix | Amendment 1 | creator check → 42501; staff-on-member → 42501; kind/namespace/mime → 22023; foreign tenant → 42501 at asset select; refusals precede publish |
| 453-461 registration matrix (lives, keys, P0002, 22023 ×3) | existing register + Edit C | unchanged authorization; linkage insert added after all refusals |
| 496/500 R32 creator isolation (asset 143) | Amendment 1 | creator-mismatch 42501 fires before liveness |
| 513-517 S1/S2 supersession | Amendment 1+Edit C | sweep tombstones the member's own unconfirmed candidate for the same request; winner untouched |
| 521-522 tombstone never finalizes / winner finalizes | Amendment 1 | deleted check `GL086:media_not_ready`; live winner passes |
| 526-528 GL126 cap 10/hour | unchanged register | tombstoned rows still count (rows exist in rolling hour) |
| 541-551 W1/W2 confirmed-winner safety | Amendment 1+Edit C | sweep excludes confirmed/attached; fresh registration allowed on proof-uploaded |
| 559 cancelled-request liveness GL066 | Amendment 1 | finalizer re-proves the linked request post-replay-check |
| 567-599 re-obtain matrix (13) | Amendment 3 | recorded/mismatch serve bound proof to member+verifier; trainer/preview/unknown/cancelled → P0002; payload pins (id, app path, ≤60s, no keys/ETags) unchanged |
| 77-81 RPC surface (13 sigs, owners, volatility, grants) | unchanged | create-or-replace kept signatures/kinds identical |

Defective assertions found: **none**. One nuance verified: the ≤60s bound
compares `transaction_timestamp()+60s` against the test's `now()` — equal
timestamps inside one pgtap transaction, so the pin holds with equality.

## Integration notes for the primary

- `supabase gen types typescript --linked` required after CI migrate
  (`media_assets.linked_request_id` is new) — primary/CI-only.
- h79 holdout supplements for the finalizer amendment remain the holdout
  author's job (h79 never opened here).
- Real RED→GREEN proof: primary's Cloud rollback preview + pg_prove; static
  checks here are `pnpm check-pgtap-rollback` green (147 files), $fn$ delimiters
  even (70), parentheses balanced (806/806), zero `commit;` statements, one
  definition each of the three amended functions.
- The Edge proof-confirm path must call the finalizer with the member shape
  `(assetId, member auth uid, NULL staff, 'member', tenant, 'payment_proof', …)`
  — matches the suite's call shape; coordinator should confirm the Edge's
  actual call matches.

## Round 2 — SQL critic findings closed (2026-10-04)

Spec: suite 79 plan(226) (round 5 in the test-fix report; +10 assertions;
suite sha256 `5f7ec3e3b867766efe551a40fc8625c4c5b73434f0048711c3d12fc8afd1e02a`).
Post-round-2 migration sha256:
`46446c5c31680ea0ffbdfe00334c67107188b23ba90e43660dac02eed1881a70`.

1. **MED member-status re-proof — CLOSED.** The finalizer's member actor gate
   (`for update` members select, before any asset/liveness check) gains
   `m.status='active' and m.erased_at is null`, mirroring the staff
   `is_active` conjunct. Cancelled/blocked/paused/expired/erased creators
   refuse 42501 at the gate. Actor gate ≠ liveness: the replay-before-liveness
   ordering is untouched (actor proof, like the staff path's, precedes even
   the replay return — a revoked creator cannot replay).
2. **LOW request-scoped serialization — VERIFIED ALREADY CLOSED, no new lock.**
   `register_payment_proof` already takes
   `pg_advisory_xact_lock(hashtextextended('purchase-request:'||tenant||':'||request_id,0))`
   before the request lookup, cap counts, supersession sweep and insert. Two
   concurrent registrations for one request serialize on that lock; the second
   (READ COMMITTED, post-lock snapshot) observes the first's committed
   candidate and tombstones it in its sweep — two live unconfirmed candidates
   for one request are unreachable. "Never delete an uncertain winner": the
   sweep predicate excludes confirmed and attached rows. Refusal ordering
   unchanged (the lock pre-dates this patch and sits after the 22023 arg
   checks, before P0002). Adding a second lock would change nothing; the
   honest close is the verification above.
3. **Self-check re-verified against plan(226)** (the dead `pg_temp.purl`
   helper was removed by the test author; the re-obtain cases now insert
   `public.read_purchase_proof_url(...)` results directly — same RPC, same
   pins, no migration impact):
   - W4 status control finalize true (member 35 active) → member gate passes,
     unchanged happy path ✓
   - W3 after `status='cancelled'` → gate `not found` → 42501 ✓
   - asset 148 with blocked creator (member 34) → gate refuses 42501 ✓
   - asset 143 after `erased_at` set → gate refuses 42501 ✓ (creator-mismatch
     case for the same asset, caller sid(907), still 42501 via the creator
     identity check — gate passes, check fires)
   - all round-1 groups (finalization matrix, registration matrix,
     supersession, GL126 cap, liveness GL066, re-obtain 13, RPC surface 13)
     re-walked against the patched function bodies: unchanged conclusions ✓

## Static verification (round 2)

- `pnpm check-pgtap-rollback`: 148 pgTAP files checked, all rollback-wrapped (exit 0).
- `$fn$` delimiters 70 (even); parentheses 807/807; zero `commit;` statements.
- `v_member_path:=true` exactly one assignment (edit-remainder defect introduced
  and repaired within this round; final body verified end-to-end by re-read).
- One early self-correction recorded: the first status-conjunct edit
  accidentally dropped the `v_member_path:=true` assignment; caught by grep
  before any verification run and repaired. Final body re-read in full.
- Still UNEXECUTED by design: Cloud rollback preview + pg_prove (primary),
  `supabase gen types --linked` after CI migrate (primary/CI).
