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

## Builder rounds 5+6 - runtime-abort diagnosis (Cloud preview vs static GO)

Scope: trace every `42501` the media seam can raise and map each to the
suite-79 fixture path reaching it. NO source change was needed this round;
`pnpm check-pgtap-rollback` 159 files green; GL126 0; `$fn$` even; zero
commit. Migration hash unchanged `d9d0370c…881a70` (Edge `e62b0162…`, shared
`b28e8349…`).

### `42501` site inventory (migration d9d0370c)

- `Media asset unavailable` (1 site): finalize_media_asset's asset select by
  id+tenant. Fires at runtime only when a bare expected-success finalize call
  receives an asset id whose row is missing - in suite 79 that means a
  `regs` row that was never written because its `pg_temp.reg` raised earlier
  (lives_ok swallows the raise, the label stays absent, the downstream bare
  finalize gets NULL).
- `Verified active media actor required` (3), `Verified actor cannot finalize
  this media kind` (2), `Credential-only verifier required` (1): finalize
  actor gates - all covered by committed refusal pins; none fires on an
  expected-success path in suite 79.
- `Current bound member required` (1): a pay seam outside the finalize path.
- `app.pay_proof_evidence` raises only `P0002 Request unavailable` (always
  consumed through `pg_temp.refusal` in the suite - cannot abort).

### Classification

**SOURCE defects found: none.** The coordinator's leading hypothesis is
REFUTED at the current bytes: the viewed-evidence check DOES branch for the
no-proof cash path - `(p_viewed_asset is null) <> (active_proof_asset_id is
null)` is FALSE for the (null, null) tuple, the incoherent half-tuple clause
only fires when the revision is present without an asset, and the third clause
requires a non-null viewed asset. A lawful received-cash recording
(`(null, null, null)` viewed tuple) passes and records. Every
record-consumed app seam (`pay_grant_capability`, `pay_command_lookup/record`,
`pay_finalize`, `pay_mark_hold_consumed`, `pay_extend_membership`) carries the
authenticated grant the invoker-context recorder needs. The record identity
and privileges are the round-2-fixed 9-arg core + 6-arg wrapper (both
granted); a 7-arg call resolves through the defaults. If the replacement
primary's preview still shows uniform record death, the first thing to diff is
WHICH migration bytes their preview spliced - `42883 …(…jsonb) does not exist`
is the signature of the pre-round-2 privilege block, not of the current file.

**FIXTURE defects (suite 79 - exact setup requirements for the visible
author; tests untouched):**

- F1 (first-abort candidate; matches the uncaught-abort symptom): the keyed
  replay block (RK1/RK2, lines ~569-573) runs BEFORE the W2 finalize (line
  ~578) and W2 attach pins (~589-592). RK1 is a NEW logical upload for KF4, so
  per the suite's own pinned supersession semantics (S1/S2 tombstone at
  ~531-533) it tombstones the still-unconfirmed W2; line 578's bare
  `finalize_media_asset(W2)` then raises `GL086:media_not_ready` uncaught
  (abort). If `reg('W2')` itself was disturbed the same path yields the
  reported `42501: Media asset unavailable` via the NULL regs row. REQUIRED
  FIXTURE CHANGE: move the RK1/RK2 block to after W2's successful attach
  (attached candidates are skipped by the tombstone loop), or run the keyed
  replay on its own request.
- F2 (second abort candidate): the member-status scenario (~665-666) reuses
  BOTH `request_key sid(529)` and the `req` label `KF5`, already taken by the
  second-request scenario (~582-583). The identical-facts create replays (no
  second request exists) and `cap('KF5',529)` then violates the `req`
  primary key - uncaught abort. REQUIRED FIXTURE CHANGE: fresh key (e.g.
  `sid(531)`) and fresh label (e.g. `KF7`) for the member-status scenario and
  W3's registration; W3's cancelled-creator refusal pin then needs the member
  cancelled AFTER its own registration, which the existing order already does.
- F3 (cascades into the whole record chain): the hand-inserted proof fixtures
  (141/144/145/146, plus refusal-only 143/148) carry NO `linked_request_id`,
  so the attach-time exact-linkage enforcement (line 2052 - the repair's
  critic-demanded core) refuses every expected-success attach pin that uses
  them (276/279/322/354), K6/KR1/KR2 never reach `payment_proof_uploaded`,
  and the downstream record pins then die on the viewed-tuple rule (null
  viewed revision with an attached-proof expectation, or active-proof mismatch)
  and the status pins starve. REQUIRED FIXTURE CHANGE: set
  `linked_request_id` on 141→KR2, 144/145→K6, 146→KR1 (143/148 stay null -
  they only pin refusals). This is fixture debt, NOT source: registration-time
  linkage and its independent attach enforcement are the committed plan(246)
  pins themselves (591-592) and the repair directive.
- F4 (informational): KF3's proof-url positives (610-618) are served by the
  confirmed-unattached resolution and need no change; note for the author that
  `proofId` is null in that payload shape.

### h79 supplement (stubbed pending labels)

Hypotheses consistent with the static read, each fixture/spec-debt until a
label proves otherwise: (1) renewal pins reading/pinning the OLD null
accepted_revision - the repair replaced it with a generated request revision
(the repair handoff's own "representable accepted revision" requirement);
(2) h79 attach fixtures predating the linkage enforcement (same shape as F3);
(3) confirmed-replay-after-closure now raising GL066 instead of returning a
clean false - intended per the repair directive ("replay is read-only but not
authority-free"); (4) C2/C3 refusal pins - the current source still raises
42501 from the session gate before anything else, so a C2/C3 failure points at
either the pre-round-2 42883 state in the previewed bytes or pin drift; wait
for the exact labels before classifying further.

## Builder round 6 supplement - attach-linkage refusal adjudication (GL124)

Coordinator adjudication applied: the attach-time registration-linkage refusal
moves out of the generic media seam and raises the frozen GL124 binding
conflict with the established DETAIL discipline
(`GL124:proof_bound` - an asset registered for request A is already bound to
that request, so attaching it to B is exactly the frozen "asset already bound
to a (different) request" allocation). Every other media-seam refusal on the
attach path (unknown/foreign/unconfirmed/wrong-creator → `GL086:media_not_ready`)
is unchanged; external HTTP mapping unchanged - cross-request attempts still
share the one external refusal and never reveal which seam refused. The
holdout pin stays as authored.

Static re-verification: `pnpm check-pgtap-rollback` 159 files green; `$fn$` 72
(even); zero `commit;`; GL-allocation grep: GL123 ×9, GL124 ×5 (now including
the linkage site), GL125 reserved-but-unraised (its two guard conditions are
unreachable in the current design: renewals record honestly and double-binding
is GL124/GL068), GL126 absent (0). Suite-79 pin 591 (`<> NO ERROR`) is
satisfied; no test edits.

Migration sha256 after this adjudication:
`a12ca1cc02cd0bbcaa5734669350047c1666653117be7707fa88ec6aa145b1f1`
(was `d9d0370c…881a70`).

## Builder round 6 addendum - keyed-replay D3 diagnosis: SOURCE defect fixed

The coordinator's possibility is CONFIRMED as a real source defect, but not in
the keyed function's replay logic - in the command-table seam it delegates to.
Walk of `register_payment_proof(uuid,text,integer,uuid)` against frozen
decision 5 (bytes a12ca1cc):

- Null key refuses 22023 (decision 5 requires the retained key).
- `pay_command_lookup(tenant, request, key, 'register')` - the case expression
  mapped `register` to the STAFF capability class (it was not in the
  member-command list), and `pay_take_capability` re-proves the minted actor
  class from the claims: under the owning member's session it raised
  `42501 Capability requires a real front-office session`. Every keyed
  registration therefore died at the seam - exactly the h79 D3 failure shape
  (same asset, read-only replay, GL068 conflict all unreachable).
- Fix: both `app.pay_command_record` and `app.pay_command_lookup` now classify
  `register` as a member command (`('create','cancel','reconfirm','attach',
  'register')` → member). Two sites, mechanical, no behavior change for the
  existing commands.

Decision-5 walk (post-fix): same actor/key + same normalized
request/MIME/bytes → lookup hits → returns the ORIGINAL assetId +
stagingObjectKey read-only (no tombstone pass, no counter use, no deadline
movement - the unkeyed creator is not called on replay); changed facts or
changed actor under the key → `GL068:idempotency_conflict`; null key →
`22023`; a vanished stored asset also refuses GL068 rather than fabricating
facts. Grants: the keyed function is security definer (postgres); the
command-table seam's internal capability take re-proves the class from claims,
which the fix now resolves to the member session.

Static: rollback guard 159 files green; `$fn$` 72 even; zero `commit;`
GL123 ×9 / GL124 ×5 / GL125 reserved / GL126 absent.

Migration sha256 after this fix:
`85b9ca72f018d9733cdcaefd662be797abf875adfd03990560293d24ecc12785`
(was `a12ca1cc…45b1f1`).

## Builder round 7 - #64 mint/take asymmetry fixed (source), cascades confirmed

Diff per the holdout author's byte-level read:
- #70/#118/#71/#77/#78: cascades, NOT signature defects - confirmed against
  the attach bytes: the guard checks exactly the frozen four args (decision 3
  correctly record-only; attach demands no viewed evidence). The runtime 22023
  was the NULL assetId from #64's registration failure hitting the arg guard
  (the fixture's label subselect came up empty). No attach change; #68 needs
  no reorder either (GL086 unconfirmed check already precedes the GL124
  linkage refusal; the runtime 22023 was the NULL assetId reaching the arg
  guard).
- #64 live defect: the keyed register path performed `pay_command_lookup`
  WITHOUT a minted capability row - the seam's take re-proves a minted
  `command_note` row and starved with 42501 (the round-6 case-expression fix
  aligned the CLASS side; the MINT side was still missing). Fix: the keyed
  path now grants `command_note` member-class before its lookup, exactly as
  the attach command does (one `perform app.pay_grant_capability
  ('command_note', tenant, request, 'member')`). Decision-5 semantics
  unchanged: replay stays read-only, zero counter/deadline, GL068 conflicts.

Static: rollback guard 159 files green; `$fn$` 72 even; zero `commit;`
GL123 x9 / GL124 x5 / GL125 reserved / GL126 absent; both register
member-class sites present.

Migration sha256 after round 7:
`c3cb0d8ff46f3b5629da1c3e13e33c0bc2a251a12d86a9a42694693216c44f45`
(was `85b9ca72…c12785`).

Expected cascade: #70/#118 (NULL assetId 22023), #71/#77/#78 clear with #64;
#68 needed no change (GL086-before-GL124 already the byte order).

## Builder round 8 - KR2/finalize-refusal walk (static, current bytes c3cb0d8f)

Constraint first: h79's fixture bytes stay invisible to this builder by
design, so the KR2 walk covers (a) the migration's finalize gates against
what `accept_purchase_request` and `register_payment_proof` actually write,
and (b) suite 79's visible equivalents. The requested S/E tape from
gymloop-35 settles the rest empirically.

### Candidate 1 - gate-vs-accept mismatch: walks CLEAN

The finalizer's request-state gate (the `if v_member_path` liveness block,
immediately after the 22023 metadata gate) reads:
`purchase_requests where tenant_id = p_tenant_id and id = v_asset.linked_request_id
and status in ('owner_accepted','payment_proof_uploaded') and expires_at >
statement_timestamp()`.
- Status set: exactly frozen decision 1's admissible live set; compared
  against the canonical `status` enum column - the same column
  `accept_purchase_request` writes (`status = 'owner_accepted'`, enum-typed
  literal, via `returning * into v_request`). No versioned-copy column, no
  missing label, no wrong-column comparison.
- Expiry: accept writes `expires_at = transaction_timestamp() + 24h`; the
  gate compares `> statement_timestamp()` - live for any test-speed flow.
- Row identity: registration freezes `linked_request_id = v_request.id` (the
  exact row the member-claim read); accept updates `where id = p_request_id`
  - the same id the suite's `req` temp table carries. Both resolve to one row.

### Candidate 2 - registration-insert vs availability gate: walks CLEAN

The availability gate filters ONLY `id = p_asset_id and tenant_id =
p_tenant_id for update` (creator/kind/staging are checked after `found`).
Registration populates `id` (generated, returned in the result the `regs`
temp table stores), `tenant_id` (the claim's tenant, = the suite's `sid(1)`
in every finalize call), kind, mime, bytes, staging key, creator, linkage.
No column the gate filters on can be unpopulated by the registration path.
FORCE RLS is absent on media_assets (plain `enable row level security`,
shop.sql:124), so the definer-context select sees the row.

### What the S/E tape must therefore show (decision table)

The three distinct 42501 messages partition the failure exactly:
- `Verified active media actor required` -> the member row failed
  tenant+user+status='active'+erased_at IS NULL+`for update` at finalize time.
  In suite-79 order, member 35 is cancelled at line ~693 and member 31 erased
  at ~703 - any finalize for those members AFTER those points is an
  EXPECTED refusal; a bare (unwrapped) call there aborts.
- `Media asset unavailable` -> the finalize received an asset id with no row
  in that tenant: a NULL `(select asset from regs where label=...)`, i.e. the
  registration lives_ok swallowed a raise (check the tape for the
  registration statement's own failure - the round-5 F1/F2 fixture defects,
  or a member-hourly cap surprise).
- `Proof upload needs an accepted live request` (GL066) -> the liveness gate;
  fires when the registered request's status left the live set or expiry
  passed - after a cancel/expiry in the fixture, or if the finalize ran
  against a DIFFERENT request than the one accept updated (linkage mismatch).
Plus the member-path creator gate `Verified actor cannot finalize this media
kind` -> the finalize's p_actor_user_id does not bind the asset's
created_by_member_id row (claim vs registration-actor mismatch).

### Verdict

No source defect is provable from the bytes: both candidates walk clean, the
gate text matches the frozen admissible set and the accept-written state, and
the row-shape chain is complete. The walk cannot see h79's fixture bytes, so
the classification stays "pending tape": if the tape shows the refusal on a
path whose registration/accept state matches the walk above, that is a
SOURCE defect and the exact failing statement + message will pin which gate
body to change; until then every observed failure shape maps to a fixture
state the gates correctly refuse. Escalation bytes for the coordinator: the
finalize gate bodies at migration lines 894-916 (liveness + replay order),
the availability select at 859-860, the member/creator gates at 845-874,
registration insert at 751-757.

Static re-verified: rollback guard 159 files green; `$fn$` 72 even; zero
`commit;`; GL123 x9 / GL124 x5 / GL125 reserved / GL126 absent. No source
change this round; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 8 addendum - keyed-register linkage binding (byte walk)

Question: can the keyed register path bind `linked_request_id` to a stale or
different request than the one accept mutated?

Walk (current bytes c3cb0d8f):
1. The keyed 4-arg resolves the caller via `app.shop_actor('member')`, takes
   the request advisory lock, mints `command_note` (round-7 fix), and on a
   replay miss delegates to the unkeyed creator.
2. The unkeyed creator re-resolves the request with a THREE-column predicate:
   `tenant_id = actor.tenant_id and id = p_request_id and member_id =
   actor.member_id` — the linkage written is `linked_request_id =
   v_request.id`, i.e. EXACTLY the caller-supplied request id, tenant- and
   member-scoped. No generation, no "latest request" fallback, no key-derived
   id.
3. The suite's `pg_temp.reg`/keyed insert passes
   `(select id from req where label='KR2')` — the id `cap()` captured from
   the create; `accept_purchase_request` updates `where id = p_request_id`
   from the same label. One row, one id, no replay/row-2 divergence: a
   replayed create returns the SAME request row (BUY-016 read-only, no second
   request), so `cap` captures the accept's target.
4. Replay cannot rebind: the command lookup is keyed on
   (tenant, p_request_id, command_key, command) — a same-key replay resolves
   only for the SAME request, and the replayed asset's `linked_request_id` is
   the one frozen at the original registration (same request). The capability
   re-proof in the seam proves the SESSION class; it never touches linkage.
5. The finalize's liveness gate reads the CURRENT status of that same row;
   if accept passed immediately before, the row is `owner_accepted` with a
   24-hour expiry — the gate cannot see a not-accepted row for the same id.

Verdict: a linked_request_id divergence is NOT reachable through the seam.
If KR2's finalize refuses GL066 while the accept passed on the same request,
the divergence is fixture-layer: the finalize's asset was registered against
a DIFFERENT request id than the row accept mutated (a stale/other label's
registration result, or a create-replay/label-capture collision of the
round-5 F2 class). The coordinator's claims-reset placement theory is
consistent with the six 42501s independently: `Credential-only verifier
required` / the member gate fire on claims shape alone, before any row read
- a claims reset placed before the finalize calls produces exactly that
signature at all six bare sites, and the fix is test-side (visible author's,
already in motion).

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 8 addendum 2 - verifier-GUC walk of the finalize request read

Sharp question answered: does the finalize's request-state gate resolve the
request through claims-derived context? **No - the gate is argument-clean.**

A claims/context audit of the entire finalize body (migration lines 822-928)
shows exactly ONE claims read: line 835, `current_setting('request.jwt.claims')`,
consumed solely by the credential gate (`role = 'service_role'`, no `sub`, no
impersonation) - which the suite's simulated `{"role":"service_role"}` claims
shape satisfies by construction. The liveness block (894-906) keys on
`p_tenant_id` (the ARGUMENT) and `v_asset.linked_request_id` (the row column);
the availability select (859-860) keys on `p_asset_id + p_tenant_id`
(arguments); the member/creator gates key on `p_actor_user_id`/`p_tenant_id`
(arguments). No `app.current_tenant_id()`, `auth.uid()`, or any other
claims-derived function participates anywhere in the finalize's reads - grep
over lines 820-930 returns only the line-835 claims read. The function is
`security definer` (postgres, table owner, plain RLS - no FORCE), so the
request read is not RLS-narrowed either, and a tenant-less verifier claims
set cannot shrink it: the gate sees the accepted row the accept mutated.

Consequences:
- The GL066 at KR2's finalize cannot originate in a claims-derived tenant
  resolution inside this gate - the bytes key on the fixture-supplied
  arguments, which the fixture audit confirms are correct (asset 141 inlined
  to the same key-522 row).
- With placement verified (all 15 sites) and the fixture single-row by key
  uniqueness, the remaining explanations that survive the static walk are
  runtime-observable only: (a) the liveness predicate's expiry leg
  (`expires_at > statement_timestamp()`) - if the preview's clock/transaction
  timestamp handling differs (e.g. a statement_timestamp vs the accept's
  transaction_timestamp boundary at the 24h TTL edge - impossible at test
  speed), or (b) the gate executing against a DIFFERENT database state than
  the walk assumes (splice ordering: if `finalize_media_asset` was created or
  replaced from a DIFFERENT byte state than the one audited - the round-14
  "bytes" label should be re-checked against the actual spliced function
  body, e.g. via `pg_get_functiondef('public.finalize_media_asset'::regproc)`
  in the same preview session, which would settle source-vs-splice in one
  capture).

REQUEST: gymloop-35's full tape capture of the finalize gate's actual bind
values - specifically `p_tenant_id`, `p_asset_id`, the returned
`v_asset.linked_request_id` (add a debug re-select or log the row), the row's
`status`/`expires_at` as read by the gate, and `statement_timestamp()` at the
gate. Those four binds decide between: linkage divergence (asset bound
elsewhere), status/expiry divergence (the accept's write not visible in the
read), and a splice/byte-state divergence (the gate body in the preview is
not the audited text).

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 9 - media_assets trigger audit (strip behavior: ABSENT)

The prime suspect is cleared byte-by-byte: nothing on `media_assets` can
strip or rewrite `linked_request_id`.

1. `app.enforce_media_asset_verification` (PAY-amended, lines 593-676): the
   INSERT branch for `payment_proof` has exactly two exits — the
   starting-verified refusal (`Media must start unverified and unattached`,
   which the registration insert cannot hit: confirmed_at/object_key/etags/
   attached/deleted all null at birth) and `return new`. Every pass path
   returns NEW UNCHANGED; a BEFORE trigger can only strip a column by
   assigning it, and no assignment exists anywhere in the body. The UPDATE
   branch's immutability row-compare INCLUDES `new.created_by_member_id` and
   `new.linked_request_id` vs old - linkage CHANGES raise
   `media_verification_invariant`; they are never rewritten. The publish
   branch's service-role/claims conditions govern only the
   verification-column transition and cannot alter linkage.
2. `app.enforce_preview_read_only` (the only other media_assets trigger):
   raises solely under impersonation sessions; otherwise `return new`
   unchanged. Registration runs under a real member claim (or the definer
   context), never impersonation.
3. The re-added CHECK constraints (object-key format, verification shape)
   only REJECT rows - a CHECK cannot null a column - and neither references
   `linked_request_id`. The composite FK `(tenant_id, linked_request_id)` is
   NO ACTION (no ON DELETE/UPDATE SET NULL).
4. Consequence for production: the registration RPC's own insert goes through
   the identical trigger pair, and nothing in either body is conditional on
   the calling path - if the trigger stripped linkage, EVERY proof
   registration would strip, which the contract forbids and the bytes do not
   do.

Verdict: SOURCE-side strip behavior does not exist in the audited bytes.
With the fixture audit exhausted and the anchors pinning the insert, the
remaining live hypotheses are exactly the two runtime-observable ones from
the round-8 addendum: (a) splice/byte divergence at the preview - settle with
`pg_get_functiondef('public.finalize_media_asset'::regproc)` plus
`pg_get_triggerdef` for both media_assets triggers captured IN the preview
session; (b) the tape's four binds (p_tenant_id, p_asset_id, the read
linked_request_id, the row's status/expires_at + statement_timestamp at the
gate). If the anchors pass and the tape still shows NULL linkage on a
function body identical to the audited text, the defect is below the SQL
layer (spliced migration set mismatch) and is the primary's to resolve - the
escalation bytes are the trigger bodies (shop.sql:220-264 + PAY 593-676) and
gate lines 894-916.

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 10 - extended media_assets audit (full spliced set): CLEAN

Migrations touching `media_assets` in the entire splice: shop (121000),
PT front (130000), announcements (150000), PAY (100000). Full inventory:

1. **Triggers**: exactly two exist on the table across ALL migrations -
   `media_assets_preview_read_only` and `media_assets_verified_immutable`
   (both cleared in round 9; no other migration creates any trigger on it).
   No AFTER triggers, no statement-level triggers, no constraint triggers.
2. **PT/announcement migrations**: read-only consumers only - outbound FKs
   (trainer photo, announcement image reference media_assets), existence
   checks inside their RPCs. Nothing writes to media_assets.
3. **Rules**: zero `create rule` on media_assets anywhere in the splice.
4. **Constraints**: the composite FK `(tenant_id, linked_request_id)` is
   NO ACTION (no ON DELETE/UPDATE SET NULL, not deferrable); the re-added
   `media_assets_kind_chk` (PAY 568-569) widens the kind vocabulary to include
   `payment_proof` and constrains nothing linkage-related; shape/format CHECKs
   reject rows, never null columns. Uniqueness `(tenant_id, staging_object_key)`
   is immediate and cannot null anything. No DEFERRABLE constructs touch the
   table.
5. **Policies**: media_assets RLS is SELECT-only (platform/tenant select
   policies) - policies filter reads, never mutate writes.

**Extended-audit verdict: CLEAN.** Across the full splice, no trigger,
constraint, rule, policy, or FK interaction can null or rewrite
`linked_request_id` post-insert. Null linkage at the finalize instant is not
producible by any spliced SQL construct acting between the insert and the
finalize. The remaining explanations are precisely the two runtime ones: the
finalize's tape binds (which row/tenant it actually reads) or session-state
divergence in the preview harness - gymloop-35's round-trip capture
(insert → immediate SELECT flanking the K6/KR1/KR2 anchors) is the right
instrument: linkage-present-post-insert + NULL-at-finalize pins the
divergence between the two statements, which with a clean spliced set means
the finalize read a DIFFERENT row (asset id/tenant divergence in the tape's
binds), not a stripped column.

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 11 - Class A availability-path audit: already argument/definer-keyed

Byte-level audit of the ENTIRE finalize body (lines 822-928) for
claims-derived actor resolution: zero hits. The only claims read in the whole
function is line 835 (`current_setting('request.jwt.claims')`), consumed
exclusively by the credential gate. The availability select keys on
`p_asset_id + p_tenant_id` (arguments, definer context); the member gate,
creator gate, and liveness gate key on `p_actor_user_id`/`p_tenant_id`
(arguments); the audit seam takes the actor AS A PARAMETER
(`app.media_audit(p_tenant_id, p_actor_user_id, p_actor_role, ...)` — its body
is a parameter-keyed insert with no auth.uid()/claims read). The media_assets
UPDATE fires the security-INVOKER invariant trigger, whose `v_trusted`
conditions (`current_user = 'postgres'` in the definer's statement context +
claims.role ≠ authenticated + no sub/impersonation) are satisfied by the
suite's simulated service_role claims.

So the prescribed fix ("availability read must be argument/definer-keyed,
never claims-derived actor") is ALREADY the byte state — there is no
auth.uid()-dependent join or filter in the availability path, the member
gate, the creator gate, the liveness gate, or the audit seam. For HEALTHY
assets 144/145/146 under `{"role":"service_role"}` claims, every gate resolves
from parameters: member row (tenant+user_id+status+erased_at), asset row
(id+tenant), creator binding, metadata, liveness — all argument-keyed.

Consequence: a runtime 42501 on healthy assets under verifier claims cannot
originate in the audited availability path at the current bytes. The two
remaining explanations: (a) the previewed function body differs from the
audited text (splice divergence — the already-requested
`pg_get_functiondef('public.finalize_media_asset'::regproc)` capture decides
this in one shot); (b) the h79 calls' actor parameters differ from the
suite-79 shape — `p_actor_user_id` must be the member's AUTH user id (the
`members.user_id` binding), not the member row id; a member-id passed as
user-id makes the member gate yield nothing and reads exactly as
"actor lookup yields nothing under service_role". The round-8 decision table
already partitions the three messages; the actor-gate message is the one to
compare against h79's call arguments.

No source change required or made; migration hash unchanged
`c3cb0d8f…16c44f45`. Class B (141/143/148 capture-vs-insert ordering) stands
with the visible author as routed.

## Builder round 12 - transitive audit of the finalize's call tree: CLEAN

The finalize's complete callee inventory at current bytes (822-928):
1. `app.media_audit` (line 923) - round-11-audited: a parameter-keyed audit
   insert, no auth.uid()/claims-derived actor or tenant anywhere.
2. The two media_assets triggers (`enforce_media_asset_verification`,
   `enforce_preview_read_only`) - round-9/10-audited: the only claims read is
   the trusted-verifier determination; no claims-derived request/actor
   resolution exists in either body.
3. NOTHING ELSE. The liveness/request reads are INLINE in the finalize body
   (argument-keyed); the finalize does NOT call `app.pay_proof_evidence`
   (that is the SQL proof-URL boundary), any liveness helper, or any
   capability seam.

So the transitive call tree is argument-clean: no callee resolves the request
or actor via claims-derived tenant/actor. Per the coordinator's own framing,
that routes to the in-session functiondef capture set (finalize +
`app.media_audit` + both trigger functions) as the remaining hypothesis - a
splice divergence inside a callee body.

One sharpening that may short-circuit that capture: the message
`Proof upload needs an accepted live request` / `GL066:request_not_accepted`
is raised from FOUR sites in the migration, not one:
- register_payment_proof's request gate (line 715),
- the finalize's liveness block (lines 899/904),
- attach_payment_proof's live-request gate (line 2039).
The tape's "finalize at idx 179 refused GL066" identification rests on the
statement shape; ask gymloop-35 for the VERBATIM call text at idx 179. If it
is `finalize_media_asset`, the functiondef capture set is the only remaining
hypothesis. If it is a keyed/unkeyed `register_payment_proof` or an
`attach_payment_proof` call, the GL066 comes from THAT function's gate - and
the register path additionally scopes its request read by
`member_id = v_actor.member_id` (a claim/fixture member mismatch yields
P0002, a distinguishable error), while attach additionally enforces the
linkage + expected revision before its own live gate.

Discriminator table for the coordinator (all four sites raise the identical
message+code):
- finalize (899/904): preceded by the credential gate, member gate, asset
  availability, creator binding, and metadata checks at the same call - a
  GL066 there means the asset row WAS found (availability passed) and the
  registered request's row failed status/expiry.
- register (715): fires BEFORE any media row exists - if idx 179 is a
  register, the surrounding statements prove it.
- attach (2039): fires only after the four-arg shape + request ownership
  pass - attach PASSED at idx 184 on the same request/asset, so a 179 attach
  refusal would require the request state to differ at 179 vs 184 with
  nothing between (impossible in-transaction) - i.e. 179 was not an attach.

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 13 addendum - availability-raise decode + staging-key hypothesis

Static decode at current bytes (c3cb0d8f):

1. `Media asset unavailable` (42501) has EXACTLY ONE raise site in the
   migration: line 864, fed by the availability select at 859-860 -
   `select m.* from media_assets m where m.id = p_asset_id and m.tenant_id =
   p_tenant_id for update`. It filters on NOTHING beyond id+tenant: no
   staging key, no creator, no kind, no confirmed state, no claims-derived
   column. A healthy, linked, present row cannot fail it.

2. The staging-key comparison the coordinator hypothesized EXISTS but lives
   in a different gate with a different signature: `p_staging_object_key is
   distinct from v_asset.staging_object_key` (line 884) is inside the
   METADATA check, which raises `22023 Verified metadata does not match
   registration` - NOT the availability 42501. Ordering: availability (42501)
   → member/creator gates (42501) → deleted check (GL086) → metadata
   including the staging key (22023) → liveness (GL066). So:

   - a staging-key INSERT-vs-argument mismatch aborts as **22023**, and
     fires BEFORE the liveness gate;
   - KR2's observed refusal is **GL066** - which means, at that finalize
     call, the asset row was FOUND (availability passed), the member/creator
     gates passed, the row was not deleted, and the ENTIRE metadata check
     including the staging-key comparison PASSED. The refusal is then purely
     the liveness predicate on the request row: `status` outside
     {owner_accepted, payment_proof_uploaded} or `expires_at <=
     statement_timestamp()` on the row with id = linked_request_id.

3. Staging-key mismatch is additionally eliminated at the fixture level for
   both classes: RPC-registered assets (M1/S1/S2/W1/W2) carry
   `(select skey from regs ...)` - the same text the registration RPC itself
   returned; hand-inserted fixtures (141/143/144/145/146/148) set
   `staging_object_key` with the same deterministic `pg_temp.stage(...)`
   helper expression their finalize calls pass. Identical immutable SQL on
   both sides - no suffix/format drift is possible without editing one side.

4. Net for KR2: the visible author's key comparison will come back equal
   (guaranteed by the shared helper), and it was never capable of producing
   GL066 anyway. The GL066 narrows the defect to one predicate on one row:
   either the request row the gate reads has a status/expiry different from
   what the accept wrote (row-identity divergence - the tape's
   linked_request_id bind decides), or the accept's write was not visible to
   the finalize's read in the same transaction (no in-transaction mechanism
   for that exists in the audited bytes - which keeps the in-session
   functiondef/splice capture as the remaining instrument).

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 14 - joint statement-by-statement trace of the finalize availability path

GUC context established by the suite's wrap before every finalize call:
`set_config('request.jwt.claims', '{"role":"service_role"}', true)` +
`set local role service_role`. Statement-by-statement, with the GUC state
each read executes under:

| # | Statement (finalize body) | Context | Claims-derived? |
|---|---|---|---|
| 1 | `v_claims := current_setting('request.jwt.claims')` | session GUC | read-only; gates credential shape: role='service_role' ✓, sub null ✓, impersonation null ✓ — the wrap's exact shape passes by construction |
| 2 | member/staff gate: `perform 1 from public.members/public.staff ... for update` | definer (postgres) | argument-keyed (p_tenant_id, p_actor_user_id); tables, not views; plain RLS bypassed by the owner; no helper re-reads claims |
| 3 | availability: `select m.* from public.media_assets where id = p_asset_id and tenant_id = p_tenant_id for update` | definer | argument-keyed; id+tenant ONLY; media_assets RLS is plain (shop.sql:124), no FORCE, owner bypass |
| 4 | creator binding: members subquery on created_by_member_id + p_actor_user_id | definer | argument-keyed |
| 5 | deleted/kind/mime/bytes/staging-key/published-key metadata checks | pure comparisons | 22023 signature — cannot produce GL066 or 42501 |
| 6 | liveness: `purchase_requests where tenant_id = p_tenant_id and id = v_asset.linked_request_id and status in (live set) and expires_at > statement_timestamp()` | definer | argument + row-column keyed; the ONLY GL066 source in this call |
| 7 | confirmed-replay / consistency checks | pure comparisons | GL086 signature |
| 8 | `update media_assets ...` + `set_config('app.media_finalize_command')` | definer | the UPDATE fires `enforce_media_asset_verification` (security invoker → current_user = postgres inside the definer statement; its claims read sees the same session GUC); v_trusted evaluates TRUE under the wrap |
| 9 | `app.media_audit(p_tenant_id, p_actor_user_id, ...)` | definer-in-definer | parameter-keyed insert into audit_log (plain RLS, owner bypass); no claims read |

CALL TREE closure: the finalize invokes exactly `app.media_audit` plus the two
media_assets triggers. No callee, view (purchase_requests/members/staff/
media_assets are all TABLES — verified `create table` in tenancy.sql:243 and
PAY:23), helper, or security-invoker view re-reads claims inside statements
2–7. The only claims reads in the entire path are #1 and #8's trigger read,
both satisfied by the wrap's shape.

RECONCILIATION: if the visible author's byte-compared fixture values align
(insert tenant_id = call p_tenant_id, present p_asset_id, matching staging
key, expected row state) — and rounds 5–13 established they do — then at the
audited bytes the availability read CANNOT refuse a present row and the
liveness read CANNOT refuse a row the accept just set to owner_accepted with
a 24-hour expiry. Round 13's decode additionally proved a GL066 requires the
availability AND metadata gates to have already passed at the same call.

CLOSING INSTRUMENT (primary's, in the preview session): capture (a)
`pg_get_functiondef` for finalize_media_asset, app.media_audit,
app.enforce_media_asset_verification, app.enforce_preview_read_only; (b)
`pg_get_triggerdef` for both media_assets triggers; (c) the tape's four gate
binds (p_tenant_id, p_asset_id, read linked_request_id, row
status/expires_at + statement_timestamp). Any byte differing from the audited
text above is the splice divergence; identical bytes with a still-refusing
gate would be a PostgreSQL-layer anomaly outside the SQL audit's reach.

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 15 - capture-file verdict: INCOMPLETE (partial match, md5 unverifiable)

Read `scratchpad/79-funcdef-captures.txt` (coordinator-extended scope).

What the file contains: header rows only - finalize_media_asset
`md5=9e31dbbc…aafc clen=7159`, media_audit `md5=887da0dc…7e7b` with the 7-arg
header, and the trigger set. The promised full prosrc rows are NOT in the
file - neither function's body text is present, so a direct
prosrc-vs-migration byte comparison cannot be run from this file.

Verifiable from what landed:
- **media_audit signature: MATCH.** Captured header
  `app.media_audit(p_tenant_id uuid, p_actor uuid, p_role app_role, …)` is
  the 7-arg identity; the migration defines
  `app.media_audit(p_tenant_id uuid, p_actor uuid, p_role public.app_role,
  p_action text, p_record_id uuid, p_before jsonb, p_after jsonb)`
  (`public.app_role` canonicalizes to `app_role` in pg_get_functiondef).
- **Trigger set: MATCH.** Exactly the two expected application triggers
  (`media_assets_preview_read_only` → `enforce_preview_read_only`,
  `media_assets_verified_immutable` → `enforce_media_asset_verification`)
  plus the expected RI constraint triggers (noaction del/upd + check ins/upd
  for members/purchase_requests/organizations/staff/trainer_profiles/
  announcement_versions). No foreign or stripping trigger exists.
- **finalize length: CONSISTENT, not proven.** Captured `clen=7159` vs the
  committed AS-body of 6659 chars; pg_get_functiondef wraps the body with a
  canonical ~500-char 12-parameter header, so 6659 + header ≈ 7159 is what
  the audited text should produce. No gross divergence signal - but the md5
  cannot be checked against a body the file does not contain, and a ≤500-char
  divergence inside the body would be invisible to the length check alone.

VERDICT: **INCOMPLETE CAPTURE - partial MATCH.** To close it, gymloop-35 must
re-capture with the full `prosrc` text (or compute, in the same session:
`md5(prosrc)` alongside `length(prosrc)`, e.g.
`select md5(prosrc), length(prosrc) from pg_proc where oid =
'public.finalize_media_asset'::regproc;`), and this builder byte-compares it
against the committed AS-body (committed body md5 `431cba90…c480a83b809c`,
6659 chars, extracted verbatim between the migration's `$fn$` quotes). Until
then the splice question stays open and the evidence packet should say so
rather than recording a MATCH.

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.

## Builder round 16 - inner-$fn$ boundary hypothesis: refuted for the migration; capture incomplete

1. Re-extraction per PostgreSQL's actual parsing (first `$fn$` after the
   finalize's AS → next `$fn$`): the committed body is **6659 chars with ZERO
   inner `$fn$` occurrences**, and the first-next terminator is byte-identical
   to the `$fn$;` my round-15 extraction used (offset delta 0). There is no
   unaudited tail in the migration - my round-11/12 audits covered the whole
   body. The "their 6658 vs my 6659" delta is trailing-newline handling noise
   between two extractions of the same text; both truncation claims are moot.

2. Therefore branch 2 (unseen ~101 chars) is VACUOUS for the committed bytes.
   If the live prosrc is genuinely 6759, the +100 chars exist ONLY in the
   deployed function - the live body differs from the committed migration by
   construction, which is the splice/pipeline divergence verdict (branch 3):
   the defect lives in gymloop-35's preview pipeline (spliced set ≠ committed
   bytes), not in any migration text I can see or fix.

3. HOWEVER - the verification capture is incomplete again:
   `scratchpad/79-finalize-fdef-truth.txt` is 155 bytes containing only the
   `app.media_audit` header row. The promised finalize prosrc text and the
   dd79m-md5 PROSRCTAIL row are NOT in the file, so the 6759 number itself is
   unverified on my side. What I need to close the comparison: the actual
   PROSRCTAIL row (or the raw live prosrc text) from the preview session -
   then the diff is mechanical: committed md5 `431cba90…809c` / 6659 chars vs
   the live body; the first diverging byte IS the splice divergence.

4. Since the live body is 100 chars longer than anything the migration can
   produce, an in-body claims-dependent element would live only in the
   uncommitted divergence - once the live prosrc text lands, the tail audit
   against the runtime GL066/42501 behavior runs immediately (same walk as
   rounds 8-14).

No source change; migration hash unchanged `c3cb0d8f…16c44f45`.
