## Builder round 2 - privilege completeness audit (coordinator escalation)

Trigger: the replacement primary's splice preview hit `42883 function
public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb) does not
exist` - the 9-arg core resolves 7-arg calls via defaults, but the privilege
block still named the dead 7-arg identity.

Privilege table after the fix (per signature: owner / revoke / grant):

| Function identity | Owner | Revoke public+anon+service_role | Grant authenticated |
|---|---|---|---|
| `record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid)` (9-arg core) | yes | yes | yes |
| `record_purchase_request(uuid,uuid,uuid,text,text,text)` (6-arg wrapper, pre-existing, forwards slot=null) | yes (was missing) | yes (was missing) | yes (restored) |
| `register_payment_proof(uuid,text,integer)` (kept unkeyed) | yes | yes | yes |
| `register_payment_proof(uuid,text,integer,uuid)` (new keyed) | yes | yes | yes |
| `app.pay_proof_evidence(uuid,uuid,uuid,boolean)` (return type changed; identity unchanged) | yes | yes | yes |
| `read_purchase_proof_url(uuid)` | yes | yes | yes |
| `finalize_media_asset(...12 args...)` | create-or-replace, identity unchanged - ACLs inherited from the creating shop migration; no statement needed | | |

Stale-variant sweep: zero occurrences of the dead
`(uuid,uuid,uuid,text,text,text,jsonb)` 7-arg identity remain anywhere in the
migration (grep count 0); all other PAY identities untouched this round
(create/accept/reconfirm/cancel/reject/attach/reject-proof/readers) keep their
existing complete owner/revoke/grant blocks.

Static re-verification: `pnpm check-pgtap-rollback` 157 files green; `$fn$` 72
(even); zero `commit;`; GL126 count 0; `purchase_cap` 3.

Migration sha256 after round 2:
`d9d0370cb6da489a04fca5286ebe9efcdec6c83c2c36891c1db61eac112894f9`
(was `fd62531f...` before the privilege fix; Edge and shared files unchanged:
Edge `e62b0162514227b2...`, shared `6788e8e39dacdbc4...`).

# SQL+Edge builder round — MEDIA/PAY repair (2026-10-04)

Builder: holdout-invisible, test-RED-driven (suite 79 plan 246 + committed TS
repair suites are the spec), frozen decisions binding. Baseline HEAD `b1fefcab`.

## Changed files (sha256-16)

- `supabase/migrations/20261004100000_purchase_requests.sql` — `fd62531f619b438b`
- `supabase/functions/media/index.ts` — `e62b0162514227b2`
- `packages/shared/src/api/purchase.ts` — `6788e8e39dacdbc4`

## Implemented (per directive items 1–7)

1. **Attach**: `p_expected_revision` now required (null→22023), validated
   against the request's accepted revision (`GL066:revision_stale`), recorded
   in command facts (replay binds it); exact registration linkage enforced at
   attachment (`media_assets.linked_request_id = p_request_id`, first attach
   included — GL086:media_not_ready, indistinguishable).
2. **Record**: signature gains `p_viewed_asset uuid default null,
   p_viewed_proof_revision uuid default null` (9-arg exact per rpc pin; the
   defaults make the 6-arg legacy call shapes resolve); `p_expected_revision`
   validated (`GL066:revision_stale`); viewed-tuple validation before any
   ledger work — viewed asset must equal the request's active proof with the
   current accepted revision; null-asset-with-active-proof,
   active-with-null-viewed, incoherent (null asset + non-null revision), and
   superseded-mismatch tuples all refuse `GL066:proof_viewed_stale`; replay
   facts carry revision + viewed tuple. Renewal accepted revision is now a
   real generated request revision (was null — the repair handoff's
   "representable accepted revision"), so sold-terms comparison and revision
   echoes work end to end. PT `p_initial_slot` stays, server-validated.
3. **Registration**: new keyed overload
   `register_payment_proof(uuid,text,integer,uuid)` — same actor/key + same
   requestId/MIME/bytes replays the same asset/staging facts read-only (no new
   candidate, counter use, or deadline); changed facts/actor conflict GL068.
   The 3-arg overload stays (rpc_contract pins it; reg fixtures use it).
   Both granted identically.
4. **GL126 removed everywhere** (was in 3 sites: member hourly registration
   cap, 5-open cap, 10/day cap) → `22023` + DETAIL `purchase_cap`, raised
   before any side effect.
5. **Finalizer reorder**: member-path liveness (registered request live +
   accepted + not expired) now runs BEFORE the confirmed-asset replay return —
   a confirmed replay is read-only but never authority-free (GL066 on
   cancelled/expired). Member-status conjunct (earlier round) unchanged.
6. **Edge proof boundary rebuilt active-only** (frozen decision 1):
   `PROOF_SERVED_STATUSES` removed; `proofRows()` filters the caller's own
   RLS read to live statuses; proof-url binds the privileged asset to the
   caller read by exact `linked_request_id` (no any-live-request fallback);
   attached path requires `activeProofAssetId === assetId`; unattached path
   serves only the member's LATEST confirmed never-attached registration for
   that exact request, refusing any asset with a payment_proofs history row
   (rejected/superseded are never viewable); recorded/mismatch/closed/expired
   refuse from the caller read alone. Post-await revalidation after every
   privileged lookup and after signing: activeActor + live-rows + unchanged
   registration re-reads. Confirm-replay revalidates the registered request
   from the caller read (`read_purchase_request`-equivalent binding) plus
   activeActor. Photo `confirm`/`staff-url` kind gates unchanged; money paths,
   GL123–125, audit shapes, BUY-005 approved rejected transition untouched.
7. **Shared schemas** (`packages/shared/src/api/purchase.ts`): vocabulary
   tuples (regenerated from Constants at the types push — see debt D1);
   create schema carries explicit-null renewal revision (shop/PT still
   require the quote UUID); record schema requires `viewedAssetId` +
   `viewedProofRevision` (nullable values, mandatory keys) and widens currency
   to actual 3-letter code (frozen decision 8); row/detail/page schemas
   reshaped to the real scalar wire (camelCase, nested strict snapshots with
   canonical integer-text money, nulls parse then drop out, strict keys so no
   storage metadata survives); proof-url result accepts a null `proofId` (the
   unattached current-proof shape).

## Verification (verbatim)

- `npx deno check media/index.ts` (from `supabase/functions/`) — **exit 0**.
- `pnpm check-pgtap-rollback` — 157 files green. `$fn$` count 72 (even),
  zero `commit;`, GL126 0, purchase_cap 3.
- Committed visible suites run:
  `pnpm vitest run` (13 repair+baseline files) → **111 failed | 102 passed
  before shared reshape → 6 failed | 81 passed (87) in the 4 shared/core
  files** after; failures classified below.
- Scoped shared `tsc --noEmit`: clean for source (remaining errors live in
  `purchase-visible-runtime-contract.test.ts` — test-author debt, below).
- Shared eslint on `purchase.ts`: clean.

## Remaining RED (not in my scope) + reported test defects

- **Pending `gen types`** (ADR-177 flow; resolves automatically after the
  primary's migrate): R10 vocabulary test compares against
  `Constants.public.Enums.purchase_request_*`, absent from the generated
  types until then; the same gap makes that test file's `tsc` fail
  (3 errors) — test-side, not source.
- **Test defect (visible author fix needed):** runtime-contract
  "survives the exact declared camelCase request keys" compares
  `Object.keys(...).sort()` against a literal list that is not in JS default
  sort order (`productId` < `productName`: 'I' < 'N' at position 6) — the
  received sorted array can never equal it. Fix the literal's order in a
  `spec:` pass.
- **Old-contract viewed-fields debt (4 failures in
  `purchase-visible-contract.test.ts`):** pins the pre-viewed-evidence record
  schema (base without viewed fields accepted; 6-arg replay facts). The frozen
  decision 3 supersedes it — needs a `spec:` amendment adding
  `viewedAssetId`/`viewedProofRevision` to its fixtures.
- **Old proof-edge bound-viewing debt:** `purchase-visible-proof-edge.test.ts`
  lines ~252/266 pin "proof-url still serves … after recorded/mismatch (owner
  decision 2026-10-04)" — the frozen decision 1 REVERSES that; same
  amendment pass flips them to the one external refusal (suite 79 already
  flipped its SQL twins).
- **SQL runtime:** suite 79 plan(246) not executed locally (no local
  database) — the primary's Cloud rollback preview + pg_prove are the RED→GREEN
  proof; `supabase gen types` follows migrate (the R10 vocabulary test goes
  green with it).

## Integration notes for the primary

- Registry: new overload `register_payment_proof(uuid,text,integer,uuid)` and
  the recorder's three new parameters need registry rows; shared schema
  exports unchanged in name except the reshaped row/detail types
  (`PurchaseRequestRow`/`PurchaseRequestDetail` now describe the scalar wire).
- Web/native builders: `purchase-http.ts` still maps GL126→429 (dead but
  harmless; the DETAIL `purchase_cap`→429 mapping is theirs to add); read
  models must decode the scalar page object per the runtime-contract test.
- Defects found in committed tests: the sort-literal defect above; no source
  was bent to a defective test.

## Builder round 3 - shared-schema round (coordinator directive)

Scope: packages/shared/src/api/purchase.ts only. sha256-16 after: `5e77d989767d4b2f`.

Schema diffs:
1. `purchaseProofUploadUrlRequestSchema`: gains REQUIRED `commandKey: id`
   (frozen decision 5; spelling matches record/attach) alongside optional
   mime/bytes - a registration request without the retained key refuses.
2. Snapshot shapes (declaration nullability clause): productSnapshot
   `description`/`cancellationTerms`/`validityDays` now
   `.nullable().optional()` - present-when-present, absent-when-null, key set
   unchanged (strictObject); renewalSnapshot `planName`/`discountPaise`/`endsOn`
   likewise; money fields stay canonical decimal text when present.
3. `purchaseRecordRequestSchema` verified against apps/web/lib/purchase-http.ts
   record case: body fields (expectedRevision, commandKey, actualAmount,
   currency, method) + the viewed tuple (viewedAssetId/viewedProofRevision,
   required-nullable keys) - schema and route spelling agree; the route must
   add the viewed tuple to its body (web builder's scope; schema correctly
   refuses a body without it, per the runtime-contract pin).
4. CORRECTION of my round 1: the currency widening to any 3-letter code is
   REVERTED to `z.literal('INR')` - the committed contract test pins USD
   refused at the schema, the SQL guards refuse factual currency mismatch
   explicitly (never silently converted), and the canonical-currency
   declaration keeps recorder input INR. This revert resolves the four
   old-contract failures I had mis-attributed to viewed-fields debt (the
   committed test already carries the viewed tuple).

Verification: the four shared suites -> **86 passed | 1 failed (87)**; the
single failure is R10's `Constants.public.Enums.purchase_request_*` equality -
impossible until the primary's post-migrate `gen types` push (documented).
Scoped shared eslint exit 0; `pnpm check-pgtap-rollback` 159 files green (RPC
identities unchanged - no signature drift; the record/registration privilege
table from round 2 still covers the exact current signatures). Remaining
shared-package tsc errors are both test-file debt owned by the test author:
the R10 generated-enum properties (pending gen types) and a union-narrowing
error in the test's own code (runtime-contract line 66 accesses
`snapshot.unitPricePaise` without narrowing the shop/renewal union).

No test files edited; no commits.

## Builder round 4 - minimal cash body + currency final reading

sha256-16 after round 4: `b28e83496d4b8caf`.

1. Viewed tuple made optional as a PAIR (`absentable(id)` on both
   `viewedAssetId` and `viewedProofRevision` + superRefine refusing exactly-one-
   present): the explicit received-cash path (BUY-012) records without a viewed
   proof, so `{expectedRevision, commandKey, actualAmount, currency, method}`
   parses; a coherent asset+revision pair parses; one without the other
   refuses; SQL still binds the tuple to the active proof under locks
   (frozen decision 3 governs proof-backed recording only). actualAmount stays
   canonical decimal text (`positivePaise`), method admits the generated
   `payment_method` vocabulary, and each of revision/amount/currency/method
   remains individually required (strictObject, no defaults).
2. Currency final reading - KEPT `z.literal('INR')`. Frozen decision 8 says
   "preserve actual received currency under the frozen BUY-014 and
   canonical-currency rules ... no silent rejection or conversion of permitted
   facts"; BUY-014 routes foreign currency to "the frozen existing money
   boundary, never silently converted to INR". The existing money boundary is
   the SQL guard, which refuses a currency distinct from the accepted snapshot
   explicitly (22023) - refusal at that boundary is neither silent nor a
   conversion, and the canonical-currency declaration keeps accepted
   quotes/fulfillment INR. The committed contract test pins the schema refusing
   USD, agreeing with that reading. Decision 8 therefore constrains what the
   LEDGER records once a fact lawfully reaches it, not the recorder schema; no
   flip.

Verification: shared suites **85 passed | 2 failed (87)** - the failures are
exactly (a) R10 pending the primary's gen-types push and (b) the
runtime-contract test "requires the explicit viewed evidence on the recording
command": its line 113 pins that a minimal body WITHOUT the viewed tuple
refuses, which the coordinator's round-4 directive (BUY-012 cash path) makes
unlawful - that test needs a `spec:` amendment splitting proof-backed (tuple
required) from received-cash (tuple absent) recording. Shared eslint exit 0;
source-side tsc clean (remaining test-file debt unchanged: R10 enum props +
union narrowing at its line 66); `pnpm check-pgtap-rollback` 159 files green;
RPC identities untouched (round-2 privilege table still exact).

No test files edited; no commits.
