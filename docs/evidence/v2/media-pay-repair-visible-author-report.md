# MEDIA/PAY repair round — visible author report (2026-10-04)

Author role: independent visible test author. Assertions derived only from
`git show HEAD:openspec/changes/member-purchases/proposal.md`,
`proof-runtime-protocol-declaration.md`, `proof-runtime-decisions-frozen.md`,
`docs/design/v2/pay-bar.md`, `docs/registry.md` and committed visible-test
conventions. No implementation, holdout, evidence-report or critic file read.
SQL assertions are RED-unexecuted locally (no local database); the primary's
Cloud preview proves them.

## Pre-existing untracked repair tests (another author's, reused not edited)

Seven uncommitted visible files already pin most repair requirements and run
20 RED / rest green — defect-capturing, kept untouched:
`purchase-visible-page-decode.test.ts`, `purchase-visible-proof-asset.test.ts`,
`purchase-visible-upload-identity.test.ts`,
`purchase-visible-verifier-surface.test.tsx`,
`packages/shared/.../purchase-visible-runtime-contract.test.ts`,
`apps/mobile/.../purchase-visible-hook-identity.test.ts`,
`apps/mobile/.../purchase-visible-native-identity.test.tsx`.
DEFECT for that author/primary: the first two files carry 13 web `tsc` errors
(strict own-file typing: `purchase-visible-upload-identity.test.ts` lines
~73–74 `Object is possibly 'undefined'`, plus page-decode errors) — test-side
fixes owed by their author; my files typecheck clean.

## Files I authored/edited

1. `supabase/tests/79_purchase_requests.sql` sha256-16 `58871fcbd7222e20`
   — plan(226) → **plan(246)** (+20 assertions, diff-verified +52/−32 assert
   lines including call-site rewrites):
   - **R11/GL126 removal:** the eleventh-registration cap case now pins
     `22023:purchase_cap` (stable DETAIL marker) instead of the unapproved
     GL126.
   - **R9 active-only flip:** the three post-recording bound-view positives
     (member KR1U, verifier KR1V, mismatch KR2U) become the one external
     refusal (`P0002`) for everyone; only the payload pins were deleted.
   - **R9 active-view positives:** new block pins member + verifier obtain the
     URL for a live request's ACTIVE proof (KF3), with requestId/path/expiry
     ≤60s, exactly-five-safe-keys and no-storage-metadata payload pins; a
     foreign member shares the refusal.
   - **R3 attach linkage:** confirmed asset registered for KF4 refuses to
     attach to the same member's second live accepted request KF5 (first
     attach included) while still attaching to its own request; fixture W2
     finalized for the purpose (member-35 caps respected).
   - **R4 viewed evidence:** every `record_purchase_request` call site gains
     the approved tuple `(p_initial_slot, p_viewed_asset,
     p_viewed_proof_revision)`; signature registry row updated to
     `(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid)`. New pins: recording
     refuses a verifier context bound to the superseded proof, refuses a
     viewed revision that is not the current request revision, refuses a null
     viewed asset while an active proof exists.
   - **R4 attach revisions:** all ten attach call sites now send the real
     `pg_temp.rev(label)`; new pin: attach with a wrong expected revision
     refuses.
   - **R5 registration replay:** keyed `register_payment_proof(request, mime,
     bytes, key)` pins — same key + same facts replays the same asset and
     staging key (no second candidate, no new deadline), changed facts
     conflict.
   - **R8/decision-2b PT slot:** exact-price PT recording without a valid
     initial slot refuses; a fabricated slot jsonb is never client-trusted
     (server-side validation refusal); PT scenario fixture KPT (member-31
     caps respected).
2. `apps/web/app/__tests__/purchase-visible-active-proof-boundary.test.ts`
   sha256-16 `eab905fcfe2c145d` — R9 transport boundary: recorded and
   mismatch_recorded requests refuse the owner member and the verifier with
   exactly `404 request_unavailable` and no target/expiry/url remnants
   (no-store); trainer audience is `403 not_permitted` with zero RPC calls;
   the live active proof still serves `{url,expiresAt}` only. **5/5 green** —
   these are correct-behavior pins: the transport already refuses when the
   database refuses; the genuine R9 RED is the SQL-level flip above.

## Verbatim results

- Repair-set run (12 files, mine + reused untracked): `Test Files 7 failed |
  5 passed (12)` / `Tests 20 failed | 162 passed (182)`.
- The 20 RED tests, by requirement: R1 scalar decode ×7 (page/detail,
  camelCase keys, nested PT/renewal snapshots, absent-facts-absent), R2
  capability TTL ×1 (GET inside TTL must serve with no-store), R4/R7 viewed
  evidence on the recording command ×1, R5 registration identity ×3 (PUT
  failure retry reuses key/facts, confirm-failure replay, MIME/bytes carried),
  R6 native identity ×3 (member change/sign-out during picker refuse before
  any network; hook reload seam), R7 surfaces ×4 (desk renders the real
  screenshot, recording disabled before the proof was viewed, member
  replacement offered at payment_proof_uploaded, native detail/proof path
  after upload), R8 renewal null revision ×1, R10 generated enum vocabulary
  ×1. Each is a public-contract violation shape per the committed contract,
  declaration and frozen decisions — no implementation diagnosis claimed.
- My R9 transport file: `Test Files 1 passed (1)` / `Tests 5 passed (5)`.
- `pnpm check-pgtap-rollback`: 155 pgTAP files checked, all rollback-wrapped.
- Scoped web `tsc --noEmit`: 13 errors, ALL in the two reused untracked files
  listed above; zero in my files.
- SQL RED honestly unexecuted: the plan(246) suite (cap marker, active-only
  refusals, viewed-evidence tuple, attach linkage/revisions, registration
  replay, PT slot) is proven only at the primary's Cloud preview.

## Coverage gaps noted for the builder round

- R2's "SQL evidence helper needs a concrete named return type" is pinned
  indirectly by the five-safe-keys payload assertion; a direct return-type
  catalog pin would need a pgTAP catalog probe the suite's style does not
  use — flagged for the primary's judgment.
- PT recording success with a valid slot is not pinned (needs a full PTF
  booking fixture); the refusal pins above capture the approved amendment's
  safety half.
- R3's "no admin web client exists" is a negative-existence claim left to the
  fresh critic's source inspection, not a test.

## Round 2 — author-of-record fixture repairs (coordinator follow-up)

Became author of record for the seven reused untracked files. Repaired the 13
web `tsc` errors with strict own-file typing, no non-null assertions, no
suppressions, no weakened assertions:

- `purchase-visible-page-decode.test.ts` (sha256-16 `a6294f8f0a8d9f56`):
  the continuation test now guards `matched[0]` with a throwing guard carrying
  the original assertion message before the three field assertions; the
  `toHaveLength(1)` expectation is retained.
- `purchase-visible-upload-identity.test.ts` (sha256-16 `db8e78f4c27cd242`):
  (1) the JPEG proof bytes are built with `Uint8Array.set`/`fill` instead of
  the nonexistent `concat`; (2) `runUpload` now calls the public helper with
  its real signature `uploadPaymentProof(file, requestId, expectedRevision,
  commandKey)` — the previous call passed the arguments in the wrong order
  (the request id as the File); (3) both retry tests capture the first/retry
  and first/last confirm entries through guarded locals carrying the original
  expectation messages. Assertion strength unchanged or stronger: with the
  corrected call shape the caller passes the same stable request facts on
  every attempt, exactly as the real retry flow does, so the retained-identity
  assertions still discriminate helper behavior.

Verbatim re-run (12 files, same set as round 1): `Test Files 7 failed |
5 passed (12)` / `Tests 18 failed | 164 passed (182)`.

The RED count moved 20 → 18 because two R5 cases were failing on the test's
own wrong-signature call, not on the source: with the real signature they pin
correct behavior and pass — `a retry after a confirm failure replays the same
attachment command key` and `the declared MIME and byte facts are carried with
the registration`. They remain part of the committed suite as green
correct-behavior pins. The remaining 18 RED keep the round-1 mapping
(R1 ×8, R2 ×1, R4 ×1, R5 ×1, R6 ×3, R7 ×4, R8 ×1, R10 ×1... exactly: R10 ×1,
R1 ×7 in runtime-contract + ×1 in page-decode, R8 ×1, R4/R7 viewed-evidence
×1, R5 PUT-failure identity ×1, R6 hook ×1 + native ×2, R7 web ×3 + native ×1,
R2 GET-inside-TTL ×1).

Scoped web `tsc --noEmit`: **0 errors**. `pnpm check-pgtap-rollback`:
unchanged green (155 files). Unchanged files keep their round-1 hashes:
suite 79 `58871fcbd7222e20`, active-proof-boundary `eab905fcfe2c145d`.
SQL RED remains honestly unexecuted locally — the primary's Cloud preview
proves plan(246).

## Round 3 — post-builder reconciliation (author of record)

Builder landed migration/Edge/shared-schema changes per plan(246); reconciled
the committed visible tests to the frozen decisions, fixtures only:

- `purchase-visible-proof-edge.test.ts` (sha256-16 `ad71f66d756759ba`):
  (1) the two bound-viewing `it.each` positives (recorded/mismatch served to
  member and verifier) flipped to the one external refusal with zero R2 calls
  (frozen decision 1); (2) the harness modernized to the rebuilt Edge's
  documented caller-read contract: `/members` branch (live member row,
  status/erased_at, object-Accept support), `/staff` branch (`is_active`,
  role aligned to the desk claims), `linked_request_id` on the media-asset
  fixture — derived from the builder report's flow description plus probe
  runs of the harness itself (path-only probes; no implementation read).
- `purchase-visible-active-proof-boundary.test.ts` (sha256-16
  `4b0733c2cc9f79b6`): the registered env contract stubs added (the
  capability minting reads the shared env schema; frozen decision 7 keeps it
  in the existing trusted runtime).
- `purchase-visible-routes.test.ts` (sha256-16 `c6af33802793a7d1`): env
  stubs; record route bodies + forwarded-args pin gain `viewedAssetId`/
  `viewedProofRevision` → `p_viewed_asset`/`p_viewed_proof_revision`
  (decision 3; `p_initial_slot` stays absent unless the desk sends one);
  GL126 removed from the mapping pin and replaced by an explicit
  unknown-code→generic-failure assertion (decision 6); both proof-url pins
  updated to the minted same-origin `?capability=` URL form (decision 7)
  while keeping the storage-metadata strip pins.
- `purchase-visible-contract.test.ts` (sha256-16 `5ace3668481612b5`): the two
  record-schema fixture objects gain the mandatory viewed fields (decision 3).
- `purchase-visible-runtime-contract.test.ts` (sha256-16
  `39838c329d5b2b03`): snapshot-key literal fixed to JS default sort order
  (`productId` < `productName` — the builder-reported test-own defect).

**Final: 13 files → `Tests 1 failed | 229 passed (230)`.** The single
remaining RED is the R10 generated-types vocabulary pin — pending the
primary's `supabase gen types` regeneration after CI migrate (ADR-177), as
the coordinator directed; left untouched. Scoped web `tsc --noEmit`: 0
errors. No source edits; SQL-side plan(246) pins unchanged; no commits.

## Round 4 — viewed-pair precision + union narrowing (author of record)

`packages/shared/src/api/__tests__/purchase-visible-runtime-contract.test.ts`
(sha256-16 `12d2911fbfbceb0c`):
- The viewed-tuple pin amended to the schema's lawful shape (frozen decision 3
  + BUY-012): minimal cash body (no viewed fields) parses — the explicit
  received-cash path; each half tuple refuses (`viewedAssetId` alone,
  `viewedProofRevision` alone); both present parses (proof-backed). The pin is
  more precise than before, not weaker. Title updated accordingly.
- Line-66 union narrowing: the shop-snapshot key assertions now narrow via
  `parsed.data.kind !== 'shop'` with a throwing guard (no non-null assertion,
  no suppression; the `toHaveLength`-style expectations preserved).
- Shared suites after: `Tests 1 failed | 55 passed (56)` — the single RED is
  R10, deliberately pending the primary's `gen types` regeneration.

## Round 5 — registration commandKey + cap marker (frozen decisions 5/6)

`apps/web/app/__tests__/purchase-visible-proof-upload.test.ts`
(sha256-16 `df52d14960ac10a6`): every registration-reaching body now carries
the retained `commandKey` (the shared upload-url schema correctly requires
it — same five cases, one root cause); the rate-cap case mocks
`22023` + DETAIL `purchase_cap` instead of the unapproved GL126 and still pins
`429 rate_limited` with no capability minted; staff-refusal and
client-storage-authority cases untouched except the commandKey addition so
their refusal reasons stay single-cause. All 7 cases green.

**Final full visible repair set (14 files): `Tests 1 failed | 236 passed
(237)`** — the sole RED is R10, deliberately pending the primary's
`gen types` after CI migrate. Scoped web `tsc --noEmit`: 0 errors. No source
edits, no commits, no holdout access.

## Round 6 — native harness rewired to the self-contained transport

`apps/mobile/lib/__tests__/purchase-visible-native-proof-upload.test.tsx`
(sha256-16 `131490b715504413`): the transport `uploadProofImage` is now
self-contained (global fetch, no injected api), so the harness observes the
upload through a `vi.stubGlobal('fetch')` double covering exactly the three
request classes — registration POST `/proof-upload-url`, staging PUT (etag
header for the read-back), `proof-confirm` POST — plus the local `file:` asset
read, mirroring the file's other fetch-based harnesses. All behavioral
assertions keep their intent: the picking test now pins the wire facts
(`proof-upload-url`, declared `image/jpeg`/mime, byte count `1234`,
`proof-confirm`), the cancelled-pick test pins BOTH zero `api.post` commands
and zero upload wire traffic, and the offline/copy/type-cap cases are
untouched. Imports `afterEach`; the intermediate literal-newline/definition
slips during editing were repaired before any verification claim.

**Full visible repair set (14 files): `Tests 1 failed | 236 passed (237)`**
— the sole RED remains the R10 generated-types vocabulary pin, deliberately
pending the primary's `gen types` after CI migrate. Native screenshot test
file: 7/7 green. Scoped mobile `tsc --noEmit`: 0 errors. No source edits, no
commits, no holdout access.

## Round 7 — suite-79 preview-abort fixture corrections (author-owned)

Four builder-diagnosed fixture defects fixed; source untouched; plan count
unchanged at plan(246) (all edits are fixture moves/renames/late updates, no
new assertions):

- **F1:** the keyed-replay block (RK1/RK2 + equality + changed-facts pins)
  moved to AFTER W2's own-request attach — a keyed registration issued before
  W2's finalize tombstoned the suite's own unconfirmed W2 candidate, so the
  expected-success `finalize_media_asset(W2)` aborted 42501.
- **F2:** the attach-linkage scenario renamed to a fresh key/label
  `KFA`/`sid(531)` — it had reused `KF5`/`sid(529)`, which the member-status
  scenario (round 5) also uses; the create replayed and the second `cap`
  violated the temp `req` primary key. All four references in the block
  renamed consistently; the member-status scenario's KF5/sid(529) untouched.
- **F3:** the hand-inserted media fixtures (141/144/145/146) get their
  immutable registration link via three late `update public.media_assets set
  linked_request_id = ...` statements placed immediately AFTER each scenario's
  request exists (141→KR2/sid(522), 144+145→K6/sid(516), 146→KR1/sid(521);
  143/148 left null on their refusal-only paths). Placement note: the
  statements run under `set local role postgres` (moved below the role switch
  — the hand inserts execute before any request row exists, so subselects in
  the original insert block would have been null). Attach-time linkage
  enforcement (pinned lines 591–592 region) then admits the expected-success
  attaches and the viewed-tuple/status pins stop starving downstream.
- **F4 verified, no change:** the KF3 active-view payload pins use key
  EXISTENCE (`?& array[...]`) for `proofId`, never value-nonnull — the
  unattached payload's `proofId: null` parses; requestId/url/expiresAt value
  pins are unaffected. Left as pinned.

Verification: `pnpm check-pgtap-rollback` green (159 files); full visible TS
repair set still **`Tests 1 failed | 236 passed (237)`** (sole RED = the
deliberately pending R10 gen-types pin). No local SQL execution — the
primary's next preview proves the suite.

`supabase/tests/79_purchase_requests.sql` sha256-16 `2799847e2f35a877`.

## Round 8 — linkage moved to insert time (verification-trigger compliance)

The coordinator-diagnosed collision: the round-7 post-hoc `UPDATE`s on
`media_assets` collide with `app.enforce_media_asset_verification()` — the
MEDIA verification trigger enforces row immutability and refuses ANY update
to an existing row, so post-creation linkage can never work at runtime (and
must never be bypassed).

Restructure in `supabase/tests/79_purchase_requests.sql`
(sha256-16 `31ddd081af4c79d7`, plan(246) unchanged):
- The early hand-insert block now retains ONLY the unconfirmed refusal-row
  fixture 143 (and its siblings with no registration link).
- Each affected scenario's media insert moved to run immediately after that
  scenario's request row exists, as a single INSERT carrying
  `linked_request_id = (select id from public.purchase_requests where
  request_key = ...)` at insert time: 144+145 after K6/sid(516)'s creation
  (before the desk accept and the first attach), 146 after KR1/sid(521),
  141 after KR2/sid(522). No post-creation mutation exists anywhere.
- The three round-7 post-hoc UPDATE statements deleted entirely (verified:
  zero `update public.media_assets` statements remain in the file).
- No bypass, no session setting, no trigger change — the inserts satisfy the
  trigger's immutability by construction.

Verification: `pnpm check-pgtap-rollback` green (159 files); full visible TS
repair set **`Tests 1 failed | 236 passed (237)`** (sole RED = the
deliberately pending R10 gen-types pin); plan(246) unchanged. No local SQL
execution — the primary's next preview proves.

## Round 9 — credential-verifier context for publication paths

Coordinator-diagnosed abort class: publication of a confirmed payment_proof
row (whether by finalize or by a published-state INSERT) must run in the
credential-verifier simulation — `set local role service_role` + claims
`{"role":"service_role"}` with no user subject — exactly the Edge's
credential-only verifier shape; actor identities stay as ARGUMENTS (the
finalizer revalidates them internally).

Audit result: all seven expected-success `finalize_media_asset` call sites in
suite 79 were already credential-wrapped (product-photo MED-002, M1 + replay,
S2, W1, W2, W4-status-control) — verified programmatically. The new
publication surface from round 8 (the three scenario-local inserts carrying
published state) is now uniformly wrapped: each of the K6/KR1/KR2 insert
sites runs `set local role postgres` → `set_config('request.jwt.claims',
'{"role":"service_role"}')` → `set local role service_role` → INSERT → back
to postgres, mirroring the production credential-only verifier. Actor
identities (p_actor_user_id etc.) remain row arguments. The refusal-path
finalize calls stay unwrapped — they never reach an UPDATE, so the trigger
is not involved and the finalizer's own actor guard produces the pinned
refusals.

An intermediate overlapping-edit slip (stray service-role toggles around the
K6→desk transition) was caught by re-inspection and fully repaired before
verification: the K6 region now reads cap → postgres → service claims →
wrapped INSERT → postgres → claim front_desk.

Verification: zero `update public.media_assets` statements; zero unwrapped
publication sites; `pnpm check-pgtap-rollback` green (159 files); plan(246)
unchanged; full TS repair set unaffected (SQL-only change — last measured
236/237 with the sole RED being the deliberately pending R10 gen-types pin).
No local SQL execution — the primary's next preview proves.

`supabase/tests/79_purchase_requests.sql` sha256-16 `02da7712fef335ac`.

## Round 10 — fixture inserts become production-shaped (no service_role DML)

The coordinator-diagnosed abort: the credential-wrapped INSERTs hit
`42501 permission denied for table media_assets` — production never inserts
media_assets via service_role (registration inserts live inside the definer
RPC; the Edge stamps verification only through the finalizer), so the grant
must not be widened for a fixture.

Restructure in `supabase/tests/79_purchase_requests.sql`
(sha256-16 `1f457511e6537664`, plan(246) unchanged):
- **K6:** the wrapped full-state INSERT (144/145 with object_key/ETags/
  confirmed_at) replaced by a PLAIN two-row INSERT under the ordinary role
  (id/tenant/kind/mime/bytes/staging key/creator/linked_request_id only);
  two credential-wrapped `finalize_media_asset` calls (144 then 145)
  re-sequenced immediately before the member attach pins produce the exact
  verified/published state the downstream pins read (active proof, superseded
  history, viewed-tuple refusal fixtures).
- **KR1:** plain INSERT of 146 after the request exists; the wrapped
  credential-verifier finalize moved to sit between the desk accept and the
  attach pin it feeds.
- **KR2:** same restructure for 141 (plain insert; wrapped finalize after
  accept, before the mismatch attach/record chain).
- Structural audit (final): zero published-state INSERTs; all 12 direct
  finalize calls credential-wrapped; all refusal-path finalizes intact (they
  never reach an UPDATE, so the trigger is not involved); zero
  `update public.media_assets` statements.

Verification: `pnpm check-pgtap-rollback` green (159 files); full TS repair
set **`Tests 1 failed | 236 passed (237)`** (sole RED = the deliberately
pending R10 gen-types pin); plan(246) unchanged. No local SQL execution —
the primary's next preview proves.

`supabase/tests/79_purchase_requests.sql` sha256-16 `1f457511e6537664`.

## Round 11 — finalize/request-state sequencing walk

Preview's GL066 abort class: finalize runs against a request that is not
accepted-live. Walked every SUCCESS finalize call against its target
request's accept position in the current file (line numbers from the
post-round-10 bytes):

| fixture (request) | accept at | finalizes at | accept-first |
|---|---|---|---|
| 144/145 (K6) | 268 | 282, 283 | yes |
| 146 (KR1) | 335 | 340 | yes |
| 141 (KR2) | 374 | 379 | yes |
| M1 (KF1) | 494 | 510, 513 | yes |
| S2 (KF3) | 554 | 567 | yes |
| W1 (KF4) | 582 | 590 | yes |
| W2 (KF4) | 582 | 601 | yes |
| W4 (KF6) | 712 | 720 | yes |

**Every accept commits before its finalize** in the current file — rounds
9–10 already re-sequenced the three round-8 scenario-local pairs into this
order; no further reorder is needed, and none was made. The intentional
refusal pins (M3 against the later-cancelled KF1 → GL066; W3 cancelled
member; 143/148 creator/erased refusals; S1 tombstoned → GL086) are all
probe-guarded via `pg_temp.refusal(...)` and left untouched — the
request-state gate itself is the contract (BUY-004/007) and is never
weakened or bypassed.

Verification: `pnpm check-pgtap-rollback` green (159 files); plan(246)
unchanged; TS repair set unaffected (last measured 236/237, sole RED the
deliberately pending R10 gen-types pin). No local SQL execution — the
primary's next preview proves.

`supabase/tests/79_purchase_requests.sql` sha256-16 `1f457511e6537664`
(unchanged from round 10 — the walk found the current sequencing already
correct; the abort the preview saw matches the pre-round-10 ordering that
round 10's resequencing had already corrected).

## Round 12/13 — runtime-disagreement walk + one real fixture fix + escalation

Per-statement runtime capture (bytes `1f457511` + builder `c3cb0d8f`) walked
against the file; findings, honestly separated:

**Fixed (unambiguous fixture defect):** the member-status control scenario
(line ~707) reused request key `sid(530)`, already consumed by the PT
recording scenario (line ~449) — `create_purchase_request` REPLAYED the PT
request (different kind/member), desyncing the whole KF6/W4 status-control
chain. Fresh key `sid(532)` applied to the control scenario's create + cap.
Suite sha256-16 `6f79b2f7239b9067`.

**KR2 finalize `GL066 request_not_accepted` (line ~379) — walked, no fixture
defect found, ESCALATED as possible source defect:** the accept at line 374
is NOT probe-guarded (`lives_ok`, real call, front-desk claims `sid(23)`,
fresh command key `sid(631)`, expected revision = the current quote —
nothing swallowed), it mutates the same `req`-captured row the finalize's
gate reads via `linked_request_id = request_key 522` (set at insert time,
line ~370, after the create at 367), the finalize follows at 379 under the
credential verifier, and no earlier probe closes the request. If the preview
TAP shows the accept assertion PASSING and the finalize still refusing with
`GL066 request_not_accepted`, that is the SOURCE finalizer's gate reading
state my fixtures cannot influence — the exact bytes above are the
escalation evidence for the primary/builder.

**M1/M3/S1 finalizes `42501 Media asset unavailable` (six sites, lines
~509–714):** these fixtures are RPC-registered rows (`pg_temp.reg` via
`register_payment_proof`) with valid staging keys — the round-10 restructure
did not touch them (it only reshaped the hand-inserted 141/144/145/146
blocks). Their staging columns were never dropped: every finalize's
`p_staging_object_key` argument equals the `regs.skey` the registration RPC
returned. If these sites still error 42501 `Media asset unavailable` in the
next preview, the availability gate's read shape has changed on the SOURCE
side (or the failure is downstream cascade of the KR2 abort) — that
distinction needs the preview's per-statement TAP, which only the primary
owns; blind fixture surgery here would be invention.

**Sequencing re-verified** (round-11 walk re-run on current bytes): all
accepts commit before their success finalizes (K6 268<282/283, KR1 335<340,
KR2 374<379, KF1 494<510/513, KF3 554<567, KF4 582<590/601, KF6 712<720).

`pnpm check-pgtap-rollback` green (159 files); plan(246) unchanged; TS set
unaffected (SQL-only round; last measured 236/237).

## Round 14 — claims-GUC leakage fix at the helper seam (coordinator-diagnosed)

Evidence: the S/E tape captured `{"role":"service_role"}` as the result
context of the mismatch scenario's create + accept (labels 120/121) — those
ran AFTER a credential-verifier block whose `set local role postgres;`
restored the ROLE but never the `request.jwt.claims` GUC (`reset role` alone
does not clear it). Every downstream create/accept/register in the same
transaction then ran under service-role claims, so the audience/actor gates
refused them and the GL066/M-S 42501s starved downstream — one class, as
diagnosed.

Mechanical fix in `supabase/tests/79_purchase_requests.sql`
(sha256-16 `03242e5b709b7686`): after every credential-verifier wrapped
block's terminal `set local role postgres;`, the suite now executes
`select set_config('request.jwt.claims','',true);` — restoring the empty
claims baseline the suite establishes at line 12, exactly matching the
pre-existing pattern; every subsequent command either re-issues its own
claims via `pg_temp.claim(...)` or runs claims-free under definer helpers.
Applied uniformly to all **15 wrapped blocks** (line-scan state machine:
wrap-open pair → terminal postgres line → claims reset). Audit results:
zero uncovered block tails; 15 wrap opens / 16 claims resets (the 16th is
the suite's line-12 baseline); refusal-path probes unaffected (they assert
the refusal whatever claims produced it); plan(246) unchanged.

Verification: `pnpm check-pgtap-rollback` green (159 files). No local SQL
execution — the primary's next preview proves (the S/E tape's captured
claims at labels 120/121 must now show the front-desk/member context).

`supabase/tests/79_purchase_requests.sql` sha256-16 `03242e5b709b7686`.

## Round 16 — reset-placement audit + KR2 registration/accept fixture check

**Placement audit (first question): walked all 15 wrap-opens.** Every
`set_config service_role` + `set local role service_role` pair is IMMEDIATELY
followed by its finalize call (direct or refusal-probe) — no claims reset and
no postgres line sits between a wrap-open and its finalize anywhere in the
file. The three plain-scenario INSERTs (K6/KR1/KR2) are NOT wrapped (they
carry no verification state, so no wrap-open precedes them) — the reset
cannot preempt them. Placement is correct at every site; no placement edit
was needed, stated plainly.

**KR2 registration/accept fixture check (second question):**
- The KR2 region contains NO `register_payment_proof` call at all — its proof
  is the hand-inserted asset 141 whose `linked_request_id` is set inline at
  insert time (line 373-374) to `(select id from public.purchase_requests
  where request_key = pg_temp.sid(522))` — the exact row the accept at line
  377 mutates (same `request_key` 522, single-row by the key's uniqueness).
  The keyed-register mint (RK1/RK2, command key `sid(680)`) lives in the KF4
  scenario and registers against KF4 only — no interaction with KR2.
- Statement walk create → finalize (lines 370–382): create → cap → plain
  INSERT → claim front_desk → authenticated → accept (lives_ok, unguarded,
  commits) → postgres ×2 → verifier claims → service_role → finalize. No
  intervening probe, close, or register between the accept and the finalize.
- Fixture-side conclusion: if the finalize's registered-linkage lookup still
  reads a different/not-accepted request at runtime, the binding defect is
  source-side (the gate's read of `media_assets.linked_request_id` or of the
  accept-mutated row), not fixture-side — the builder's binding check is the
  right next step; the fixture bytes above are the evidence.

Also verified: the round-14 claims reset sits strictly AFTER every block's
finalize (line-scan: each wrap-open's next statement is service_role +
finalize; the reset follows the terminal postgres line — shown for all 15
opens in the audit output).

`pnpm check-pgtap-rollback` green (159 files); plan(246) unchanged; no local
SQL execution — the primary's next preview proves.

Suite sha256-16: recomputed below at round close (file unchanged this round:
`03242e5b709b7686`).

## Round 17 — KR2 asset-id wiring audit (coordinator's decisive-capture follow-up)

**The capture's premise does not match the current bytes — verified line by
line, no swap occurred, no fixture fix needed:**

- The KR2 expected-success finalize (line 382) references
  `pg_temp.sid(141)` — NOT 143. Full argument list verified verbatim:
  `finalize_media_asset(pg_temp.sid(141), pg_temp.sid(906), null, 'member',
  pg_temp.sid(1), 'payment_proof', 'image/jpeg', 1000,
  pg_temp.stage(141,'payment_proof'), 'source-141', pg_temp.pub(141,
  'payment_proof'), 'published-141')` — staging key, mime, bytes and creator
  all match asset 141's INSERT row exactly.
- Asset 141's hand INSERT (line ~374) carries `linked_request_id =
  (select id from public.purchase_requests where request_key = sid(522))` —
  the KR2 request the accept at 377 mutates. Asset 143 (null linkage,
  refusal-only) appears ONLY inside `pg_temp.refusal(...)` pins (lines 551,
  749) — audited: every direct (expected-success) finalize references
  144/145/146/141; 143/148 are refusal-only, exactly per the F3 mapping. No
  141/143 swap exists in the round-8/10 restructure.
- The one plausible source of the tape's "143" reading: the S/E tape keys
  statements by EXECUTION index, and the round-8–12 restructures shifted
  statement positions — if the capture's index was mapped onto current
  source lines without re-deriving the index, the erased-member refusal pin
  (line 749: asset 143, actor 906 — the same actor id as the KR2 finalize)
  is the statement most likely mis-attributed. Re-derive the tape index
  against the current bytes before treating the 143 reading as runtime truth.

**Builder's question — CONFIRMED from the migration bytes:** the
registration insert (`register_payment_proof`, migration line ~751) inserts
`linked_request_id = v_request.id` (the resolved request) at insert time,
and returns `{assetId, stagingObjectKey, mime, bytes}`. So every
RPC-registered asset carries linkage from birth; the KR2 failure — if it
still reproduces against these bytes — cannot be a missing-registration
linkage, and with the finalize verifiably targeting asset 141 (linked,
accepted-live KR2), the remaining explanations are source-side gate reads
or a misaligned tape index.

`pnpm check-pgtap-rollback` green (159 files); plan(246) unchanged; file
unchanged this round — stated plainly rather than inventing a fix.

Suite sha256-16 `03242e5b709b7686`.

## Round 18 — linkage-subselect audit + loud anchors (runtime NULL vs fixture bytes)

Audited asset 141's exact INSERT in `03242e5b` plus the six 42501-region
fixtures:

1. **141's linkage expression** selects `id from public.purchase_requests
   where request_key = pg_temp.sid(522)` — no label/tenant term exists to go
   stale (the F2 renames touched only the attach-linkage scenario's labels,
   not this expression), and the ordering audit proves insert-after-create
   for all three scenarios (K6: create char 32224 < insert 33017; KR1
   40728 < 41506; KR2 45299 < 46078). No stale subselect found — the
   expression as written cannot silently NULL if the row exists and no
   trigger rewrites it.
2. **M/S-region registered rows**: not fixture-inserted at all —
   `register_payment_proof` sets `linked_request_id = v_request.id` inside
   the definer RPC (migration ~751, confirmed round 17). Nothing in the
   fixture file can NULL those.
3. **Hardening applied**: each of the three scenario-local INSERTs is now
   preceded by a loud single-row existence pin — `is((select count(*) from
   public.purchase_requests where request_key = <key> and tenant_id =
   sid(1)),1,'... linkage anchor row exists before the media fixture insert
   (loud, never a silent NULL)')` — so a future restructure CANNOT silently
   null a linkage: a missing anchor row fails the assertion visibly in the
   TAP instead of writing NULL. **plan(246) → plan(249)** (+3).

**Sharpened escalation for the primary/builder (the NULL's only remaining
mechanism):** if the anchor assertions PASS at the preview and asset 141's
`linked_request_id` is STILL null at the finalize instant, the write is
being stripped after the statement — the prime suspect is the MEDIA
verification trigger (`app.enforce_media_asset_verification`) rewriting or
whitelisting NEW rows on INSERT (a BEFORE INSERT trigger that rebuilds
NEW without the linkage column would produce exactly this silent NULL with
no error). The trigger body is source-side; the fixture cannot and will not
bypass it.

Verification: `pnpm check-pgtap-rollback` green (159 files); TS set
unaffected (SQL-only). No local SQL execution — the primary's next preview
proves; the anchor pins + the E-marker give a decisive NULL-origin split
(fixture ordering vs trigger rewrite).

`supabase/tests/79_purchase_requests.sql` sha256-16 `bfbcf9a4d3c0e70d`.

## Round 19 addendum — anchor-pin bigint cast

The three linkage-anchor pins amended per the repo's adjudicated pattern:
`is(count(*), 1, …)` → `is(count(*), 1::bigint, '…')` at lines ~264/334/375
(K6/KR1/KR2 anchors). No other statement touched.

`pnpm check-pgtap-rollback` green (159 files); plan(249) unchanged.

`supabase/tests/79_purchase_requests.sql` sha256-16 `455d39a1aed101cb`.

## Round 20 — per-signature asset map + classification (line-level walk)

Fixture bytes `455d39a1`; anchors typed+loud (K6 line ~264, KR1 ~334, KR2
~375). No edits this round — the classification below is what the next
preview's anchor pass/fail splits against.

### Signature 1 — GL066 request_not_accepted (null-at-runtime linkage)

| finalize | asset | linkage origin | anchor | accept before? | classification |
|---|---|---|---|---|---|
| 284, 285 | 144, 145 | plain insert (inline, key 516/K6) | K6 ~264 | yes (268) | if anchor FAILS → fixture ordering (loud path); if anchor PASSES → trigger-rewrite/source class |
| 344 | 146 | plain insert (inline, key 521/KR1) | KR1 ~334 | yes (335) | same split |
| 385 | 141 | plain insert (inline, key 522/KR2) | KR2 ~375 | yes (377) | same split — the E-marker site |

Line-72-class finalize targets = exactly the three hand-inserted assets
(144/145/146/141). RPC-registered assets (M1/S1/S2/W1/W2/W4) cannot hit this
signature from fixture NULLs — their linkage is set inside the definer RPC
(migration ~751, confirmed). If a reg: asset shows GL066
request_not_accepted, the gate read the RIGHT linked row and the request
state was wrong at that instant — for M1 that is by design? No: M1's KF1 is
accepted-live at 510 (cancel comes later, line ~610); S2's KF3 accepted at
554; W1/W2's KF4 accepted at 582; W4's KF6 accepted at 712 — all
accept-first per the round-11 walk, so a GL066 on ANY reg: finalize would
starve from an upstream failed accept (the round-14 claims fix) — check the
accept's own TAP result first.

### Signature 2 — 42501 Media asset unavailable (availability gate)

| finalize | asset | row origin | staging state at finalize | classification |
|---|---|---|---|---|
| 124 | assets:product-photo | `register_media_asset` RPC (staff path) | staging-only, finalize supplies key | unchanged since green previews — if THIS errors, the availability gate changed source-side |
| 517, 520 | reg:M1 | RPC (from-birth linkage) | staging key from `regs.skey` | RPC-registered → if 42501 unavailable, **register-to-availability seam = source candidate** |
| 577 | reg:S2 | RPC | `regs.skey` | same source candidate |
| 601, 613 | reg:W1, reg:W2 | RPC | `regs.skey` | same |
| 734 | reg:W4 | RPC | `regs.skey` | same |
| 530–535, 643, 740, 746, 752 | reg:M3, 143, 148, W3 | mixed | refusal-only | NOT availability failures — these expect refusals; a 42501-unavailable reading on these lines means the tape index is misaligned (see round 17's index warning) |

### Split protocol for the next preview

1. K6/KR1/KR2 anchor pins PASS + finalize GL066 → source-side linkage
   rewrite (trigger) — escalate with the anchor receipt.
2. Anchor pins FAIL → the anchor names the scenario whose request row was
   missing at insert time — fixture ordering, fixable in place.
3. reg-asset finalize 42501 unavailable → register-to-availability seam —
   hand to the builder with this map (RPC rows, from-birth linkage, valid
   staging keys).
4. 143/148/M3 refusal lines showing 42501-unavailable → tape-index
   misalignment, not a fixture defect.

`pnpm check-pgtap-rollback` green (159 files); plan(249) unchanged; file
unchanged this round (sha256-16 `455d39a1aed101cb`).

## Round 21 — key re-derivation, tenant-scoped linkage, post-insert pins

1. **Key re-derivation (per scenario, create literal vs insert subselect
   literal):** K6 create `sid(516)` → insert subselect `516` ✓; KR1 create
   `sid(521)` → `521` ✓; KR2 create `sid(522)` → `522` ✓. No media insert
   references a pre-F2 key (no `529`/`530` in any subselect; the
   member-status scenario's fresh `sid(532)` create has no media insert).
   The stale-key-literal class is absent from the current bytes.
2. **Tenant scoping added:** every linkage subselect now carries
   `and tenant_id = pg_temp.sid(1)` — a cross-tenant key collision can no
   longer pick a wrong row silently (four subselects: 144/145/146/141).
3. **Post-insert linkage pins added** (the round-18 anchors prove the
   request exists BEFORE the inserts; these prove the inserts SAW it):
   `is((select count(*) from media_assets where id = <asset> and
   linked_request_id is not null), 1::bigint, 'BUY-008/010 linkage present
   on <asset> after insert (key drift is loud here)')` — placed directly
   before each wrapped finalize (144, 146, 141). Key drift at any site is
   now loud at the insert site. **plan(249) → plan(252)** (+3).

Verification: `pnpm check-pgtap-rollback` green (159 files); claims-reset
balance re-verified (16 resets; the three new pins sit inside the existing
wrapped blocks before the verifier claims open — no block-tail changes).
No local SQL execution — the primary's next preview proves.

`supabase/tests/79_purchase_requests.sql` sha256-16 `2c9475015ab1bcb2`.

## Round 22 — label-capture adoption: key drift made impossible

Structural fix per directive. The four media-insert scenarios now capture
the CREATE's RETURNED request id into the suite's existing `req` temp table
(the same seam the keyed-registration section uses), and every downstream
reference reads the captured label row:

- **K6** (line ~261): `insert into req(label,id) select 'K6',(r->>'requestId')::uuid
  from (select public.create_purchase_request(sid(516),…) as r) v` — the
  key literal stays ONLY in the create call; the returned id is captured.
  `cap('K6',516)` removed.
- **KR1** (line ~333): identical capture for `sid(521)`; `cap('KR1',521)`
  removed.
- **KR2** (line ~374): identical capture for `sid(522)`; `cap('KR2',522)`
  removed.
- **KF6** (line ~724, member-status chain with media via W3/W4): identical
  capture for `sid(532)`; `cap('KF6',532)` removed.

The four media-insert linkage subselects now read
`(select id from req where label='K6'|'KR1'|'KR2')` — a single strict row
captured from the create's own return; no request-key literal left to rot
between the create and the media insert. The round-21 anchor pins keep
asserting BY REQUEST KEY (loud create-key drift), and the round-21
post-insert pins keep proving `linked_request_id is not null` at the insert
site — with the capture in place the entire silent-NULL/mislink class is
structurally dead: whatever key the create actually sent is the id the
linkage carries.

Answer to item 4: no scenario re-uses key `sid(516)` for an accepted flow
(re-derived; `cap('K6',516)` was the only 516 consumer and is now replaced
by the label capture).

Verification: `pnpm check-pgtap-rollback` green (159 files); plan(252)
unchanged (captures replace cap calls 1:1 — no assertion-count change); the
four old `cap` calls are gone (count 0).

`supabase/tests/79_purchase_requests.sql` sha256-16 `fe5a9787f0798e63`.

## Round 23 — capture audit: no missing/mislabeled create; scope extended

Full audit of every create that should produce a captured label:

- **The four existing captures are correct**: K6→sid(516), KR1→sid(521),
  KR2→sid(522), KF6→sid(532); each executes unconditionally (no guard, no
  DO/IF wrapper — verified against the preceding three statements of each),
  and each label string exactly matches its downstream references
  (KR2 ×6, K6 ×18, KR1 ×10, KF6 ×1 — exact-string check, no abbreviations).
- **The sid(522) literal**: lives ONLY inside the KR2 create call, which
  captures under label 'KR2' — aligned; no other consumer of 522 exists.
- **W/S/M-series conversion**: the scenarios feeding the 42501 sites still
  used the key-literal `cap` seam (a create-key drift there would be silent
  the same way). Converted to label capture: **KF1** (feeds M1/M3),
  **KF3** (feeds S1/S2/S3/S9), **KF4** (feeds W1/W2). Remaining `cap` calls:
  14 — all in scenarios with no media/proof surface (K1–K5 open-request
  caps, KA/KB, KRN/KRP, KPT), out of the capture's blast radius.
- The capture structure now guarantees: once a create succeeds (lives_ok),
  its labeled row exists, and every media/registration/attach reference
  reads that row — the NULL/mislink class is dead regardless of future key
  edits.

`pnpm check-pgtap-rollback` green (159 files); plan(252) unchanged (1:1
cap→capture swaps).

`supabase/tests/79_purchase_requests.sql` sha256-16 `01800527f9154704`.

## Round 24 — tape mapping: the harness splitter swallows the capture statements

Mapped the full runtime tape (`tape79-fe5a9787.txt`, 389 rows) against the
suite. Decisive finding — **the tape harness itself drops statements**:

- Suite-line diff: of the file's statements, large blocks never appear as
  tape rows — including every `create_purchase_request` + label-capture
  statement except KF3's (suite 558 IS taped, idx 285, ok). Specifically
  absent from the tape: K6's create+capture (suite ~261), KR1's (~331),
  KR2's (~372), KF1/KF4's, the K6/KR1/KR2 `claim('front_desk'…)` lines, and
  most `set local role` / `set_config` lines.
- Yet the in-session `req` table at the abort instant CONTAINED K6/KR1 (the
  coordinator's own snapshot) — the captures DID execute; the tape simply
  has no row for them. So the capture harness (the primary's per-statement
  splitter, not `splice.py` — splice.py only splices migrations and stashes
  counters, verified from its source) swallows statements — most plausibly
  the dollar-quoted `lives_ok($q$ INSERT INTO req … $q$,…)` capture
  construct, in position-dependent groupings (KF3's capture at suite 558
  survived; the others were swallowed).
- **This invalidates the "no KR2 capture row" inference**: the capture row
  existed (the accept at idx 178 resolved `label='KR2'` and PASSED — an
  accept cannot succeed against a missing req row). The req-snapshot
  missing KR2 is consistent with the snapshot being taken through the same
  swallowing splitter.

Mapping of the seven E markers (execution-true, splice+suite lines from the
tape): idx 179 → the KR2 finalize batch (suite ~381 group; error text
`GL066 Proof upload needs an accepted live request`); idx 255/258/295/309/
316/376 → the M1/M3/S/W finalize groups. The E rows' SUITE text is the
wrapped block's FIRST line (`set local role …`), not the finalize itself —
the splitter groups the wrap+finalize as one statement and attributes the
error to the group's first line, which is why line-level attribution looked
wrong.

**Fix required is in the CAPTURE HARNESS, not the suite**: the per-statement
splitter must not swallow `$q$`-quoted lives_ok capture statements. The
suite's own structure (label captures + typed anchors + post-insert pins)
is sound: with the captures actually executing, the KR2 chain and the six
sites' state is exactly what the pins assert.

Suite sha256 at capture time `fe5a9787f0798e63` (current: `01800527f9154704`
— rounds 22/23 post-capture edits); plan(252); `check-pgtap-rollback` green.

## Round 20-B — class-B walk: 141 already matches the template; 143/148 are refusal-only by design

Line-level ordering walk on the current bytes (`01800527`):

- **141 (KR2) already matches the healthy K6 template verbatim**: capture
  (`lives_ok` create+capture, line ~372) → postgres → key anchor (~374) →
  plain media INSERT with inline label linkage (~376) → accept → wrapped
  finalize. Capture strictly precedes the media insert and every downstream
  reference. **There is no ordering defect to fix in the 141 scenario** —
  the bytes are the K6 template verbatim.
- **143/148 are refusal-only BY DESIGN** (the F3 mapping, rounds 8/10): they
  have NO label capture and NO linkage — their finalize calls are
  `pg_temp.refusal(...)` pins expecting exactly the refusal the null linkage
  produces (143: creator-check refusal with a live accepted request of one's
  own; 148: blocked-member refusal). Their "linked: null at first-finalize"
  gate-bind reading is the pins' PURPOSE, not a defect. Adding label
  captures would change what those pins mean (F3's design: "143/148 stay
  null, refusal-only") — not done.
- **The one genuine unknown left for the 141 runtime reading**: the
  create+capture lives_ok at 372 is one of the statements the round-24 tape
  splitter SWALLOWS (no S row for it) — so whether the KR2 create+capture
  actually succeeded at runtime is not observable from the tape. If it
  failed (e.g., the create refusing inside `lives_ok`), `req` has no KR2
  row, the INSERT writes NULL linkage, and the finalize's GL066 is the
  contract working — with the failure visible as a FAILED lives_ok
  assertion in the TAP, not as an abort. The round-21 post-insert pin at
  ~377 (`linkage present on 141 after insert`) decides it decisively at the
  next preview: PASS ⇒ the linkage landed and a null-at-gate reading is
  source-side; FAIL ⇒ the create+capture failed and the TAP will show it.

Verification: `pnpm check-pgtap-rollback` green (159 files); plan(252)
unchanged; no bytes changed this round — the requested reorder already
holds for 141 and is intentionally inapplicable to 143/148 (refusal-only,
F3 design; converting them would change the pinned refusal semantics).

Suite sha256-16 `01800527f9154704` (unchanged).

## Round 21 (coordinator numbering) — KPT redo on the restored committed bytes

Boundary note recorded: the holdout author's cross-file edit to suite 79 was
reverted by the primary (HEAD `60b9d86c` at restore, then `dfecd7e8` committed
my label-capture work — verified present at HEAD: 16 claims resets (round 14),
4 label captures (rounds 22/23), 3 post-insert pins + 3 typed anchors (rounds
19/21), plan(252)). My rounds were not lost; the discarded edit was the
holdout author's out-of-role cross-file change (the malformed KPT lives_ok).

Applied cleanly, per the cap census:
- **Daily-cap starvation fixed**: the KPT PT-recording scenario's claim moved
  from member 31 (whose create was the 11th against BUY-018's 10/day cap) to
  member 32 — claim('member',1,null,32,907) — whose active membership
  (sid(132)) satisfies the PT gate and whose create count stays within caps;
  member-35 pins untouched. The create stays sid(530)-keyed.
- **Label PK collision repaired** (my own defect, same class the holdout
  census surfaced): my block had reused the committed `KPT` label already
  bound to the original sid(507) PT request (line 176) — `cap('KPT',530)`
  would violate the `req` primary key. Fresh label **KP2** applied to the
  block's cap/accept/record references (4 sites); the original KPT at line
  176 untouched.

Round-20B ordering analysis re-verified against the current committed bytes:
the 141 scenario still matches the K6 template verbatim (capture → anchor →
inline-linked insert → accept → wrapped finalize); 143/148 remain
refusal-only by design.

`pnpm check-pgtap-rollback` green (159 files); plan(252) unchanged.

`supabase/tests/79_purchase_requests.sql` sha256-16 `6034a550554e04dc`.

## Round 22/23 — execution-order map from the authoritative tape: the fixture is correct; the finalize/availability gates disagree with the attach under identical state

Tape rows (execution order, fe5a9787 bytes), KR2 region:
- idx 174 claim member → idx 175/176 media INSERT (141, plain) → idx 177
  authenticated → **idx 178 accept KR2 via `req where label='KR2'` — PASSED**
  (an accept cannot resolve a missing req row ⇒ the KR2 capture row existed
  and the create+capture executed, despite its tape row being swallowed) →
  **idx 179 finalize(141) → GL066 request_not_accepted** → idx 184
  **attach(141) PASSED** (the attach's linkage enforcement reads the SAME
  registered request) → idx 187 record → mismatch_recorded ✓.
- K6 region: post-insert linkage pin (idx 116) PASSED; the single taped
  finalize is sid(145) (idx 118, ok) — the 144 finalize's row is absent from
  the tape (the splitter surfaces only the last result of a grouped batch —
  the exact "only the last result set" failure class `splice.py` documents
  having cost six red runs before).

**Conclusion (divergence point):** within one transaction, the attach at
idx 184 sees KR2 accepted-live with correct linkage, while the finalize at
idx 179 — same request, same asset, earlier by five statements — refused
`GL066 request_not_accepted`, and the six 42501 `Media asset unavailable`
errors sit in the same wrapped-credential context. The fixture ordering is
proven correct by the tape itself (accept 178 < finalize 179; the capture
row resolved). Remaining explanations are SOURCE-side: the finalize's
request-state/availability gates read a row state or context that the
attach path (authenticated RLS) sees correctly but the credential-verifier
context does not — e.g., the gate's request/asset read being
claims-dependent (`request.jwt.claims` is set to the bare verifier object
during the wrap; if the finalizer's internal read relies on any
claim-derived binding rather than its actor ARGUMENTS, it would see
nothing). This matches the builder's own audit note that the gates
revalidate actor/registration internally — the fixture now provably
supplies the right inputs.

**Escalation to the SQL builder with the exact bytes**: the finalize at
suite ~381-385 (asset 141, actor 906/member-31, tenant sid(1), linked to
KR2 accepted at idx 178) refusing `GL066 request_not_accepted` while the
immediately-following `attach_payment_proof` on the same request/asset
passes its full linkage+live-acceptance enforcement.

`pnpm check-pgtap-rollback` green (159 files); plan(252) unchanged; no
fixture edit this round — the tape proves the fixture correct.

Suite sha256-16 `6034a550554e04dc` (unchanged).

## Round 24/25 — guarded-capture probe on the mismatch create (runtime instrumentation)

- **Collision/replay pre-check**: `sid(522)` is unique among create keys
  (only sid(501) repeats, by design — its three calls are the replay pins);
  no other create collides or replays against the mismatch scenario. The
  dump may still confirm a cap/tenant/other refusal — the probe names it.
- **Instrumentation installed** (clearly labeled, removable):
  - new `pg_temp.diag(q)` helper beside the suite's `refusal` helper —
    identical catch shape, but returns `sqlstate:detail | message` via GET
    STACKED DIAGNOSTICS (refusal() drops the message);
  - one probe statement immediately before the mismatch scenario's
    create+capture: `select is(pg_temp.diag($q$select
    public.create_purchase_request(sid(522),'shop',sid(101),1,<quote>)$q$),
    'NO ERROR','BUY-014 DIAGNOSTIC … (not a contract pin)')` — a bare
    isolated call of the exact same create; one preview row names the root
    (cap refusal / replay conflict / foreign-target / tenant / other) with
    the full caught detail.
  - The original `lives_ok` label-capture create remains as the contract
    pin, untouched.
- **plan(252) → plan(253)** (+1 diagnostic).

**Tape-semantics correction accepted**: failed pgTAP assertions raise no
SQL error, so the earlier S=ok readings never proved the create landed —
the "accept passed ⇒ capture existed" chain is retracted; the probe's
caught detail is now the authoritative root-name.

Verification: `pnpm check-pgtap-rollback` green (159 files).

`supabase/tests/79_purchase_requests.sql` sha256-16 `b9228f9fe108430e`.

## Round 25 addendum — diag handler cast-shape correction

Applied the coordinator's correction: `pg_temp.diag` now captures only
`returned_sqlstate` + `pg_exception_detail` via GET STACKED DIAGNOSTICS —
the SQLERRM/exception-message part dropped (my helper had included
`pg_exception_message`; the probe's assertion output carries the state and
detail, which is the decisive root-name pair, without echoing the message).

`pnpm check-pgtap-rollback` green (159 files); plan(253) unchanged; probe
call sites unchanged (3 references: helper + probe + …).

`supabase/tests/79_purchase_requests.sql` sha256-16 `71908029179798b0`.
Ready for the immediate re-preview.

## Round 26 — cap root fixed by minimal redistribution; instrumentation removed

Root captured: `22023:purchase_cap` on the mismatch create — the ONE root of
the entire GL066 + 42501 cascade (everything downstream starved).

**Remap applied (option b, fewest labels disturbed):** the sid(507) PT
request — created under member 31 and never consumed downstream (its only
reference is its own cap) — remaps to member 32 via a claim switch around
its single `lives_ok` (claim member-32/907 → create → claim member-31
restore). Member-31's create count drops by exactly one, so the mismatch
scenario's create (9th) lands within the 10/day cap. Member-32's budget:
5 prior creates + 507 = 6, within caps. The PT eligibility gate holds
(member-32's active membership sid(132)); the KPT cap pin still tests the
real cap (unchanged semantics — only which member pays which create).

**Probe removed** (root named — labeled instrumentation comes out): the
`pg_temp.diag` helper, its grant entry, and the probe statement deleted;
plan(253) → plan(252) restored.

Verification: `pnpm check-pgtap-rollback` green (159 files); zero diag
references remain.

`supabase/tests/79_purchase_requests.sql` sha256-16 `26af4a29100e5bf1`.

## Round 26-diag — instrumented capture artifact built (handed to gymloop-35)

Artifact: `scratchpad/suite79-errdiag-26af4a29.sql` (compiled from suite 79
at `26af4a29` via splice.py + make-err-diag.py, then instrumented). sha256-16
`5ccc6b8c7ed8e66e`. Zero-mutation observers only — every original statement
still runs; the instrument adds reads + _diagtap rows.

Placed per gymloop-35's confirmed requirements:
1. **KR2 create pre-wrap under member claims** (site A): the mismatch
   create+capture's tool-DO replaced 1:1 by a catching DO ($diagkr2$) that
   runs the identical create+capture and records `DIAG KR2-create: OK
   requestId=…` or `DIAG KR2-create: REFUSED <sqlstate> detail=…` — answers
   whether the create still refuses 22023 after the redistribution.
2. **Six availability finalizes instrumented inside their wraps** (verifier
   claims live by design): F144/F145 (K6), F146 (KR1), M1 ×2 (finalize +
   replay — both refused in the E tape), S2, W1?, W2, W4 pre-read observers
   recording asset row count, linked_request_id, confirmed_at, staging key,
   and the linked request's status AT READ TIME — split "asset missing /
   linkage NULL / request-state wrong" per site.
3. **KR2 finalize** (F141) same treatment.

The seven-error signature re-read note: the tape's S=ok readings were
pgTAP-semantics (failed assertions raise no SQL error) — the observers'
_diagtap rows are the trustworthy capture. If the KR2-create DIAG row shows
OK at its true position, the seven-error signature was captured against
pre-redistribution bytes and the E rows re-map to the residual questions
only.

Execution stays primary-owned: the artifact is built and handed off;
gymloop-35 runs it under their lock and returns the DIAG/E rows.

Injector source: `scratchpad/inject-observers.py` (kept for reproducibility).
Artifact sha256-16 `5ccc6b8c7ed8e66e`.

## Round 27 — artifact regenerated with the corrected DO declare scope

The regenerated artifact fixes the 42703 class: the `$diagkr2$` block now
declares `v_sqlstate text; v_detail text;` in its DECLARE and its handler
reads exactly `GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE,
v_detail = PG_EXCEPTION_DETAIL` (MESSAGE is not a GET DIAGNOSTICS item —
dropped). All 10 observers' DECLARE blocks re-verified full-scope (each
carries v_linked/v_confirmed/v_staging/v_found/v_req/v_state/v_detail — the
earlier "bad declare" reading was my verifier's own single-semicolon regex,
corrected).

Regenerated end-to-end from the clean suite compile (splice.py →
make-err-diag.py → injector, 391 statements probed, 11 injections).

**Artifact path for gymloop-35's immediate execution:**
`scratchpad/suite79-errdiag-26af4a29.sql` — sha256-16 `7a02faba659a0758`.
DIAG rows returned map: `DIAG KR2-create` (the real mismatch create's caught
root at its true pre-wrap position under member claims), `DIAG F144/F145/
F146/F141/M1/S2/W1/W2/W4` (each availability finalize's asset existence,
linked_request_id, confirmed_at, staging key, linked-request status at read
time).

## Round 27 addendum — pure-capture artifact (no assertions in the instrumentation)

Per the coordinator's (b) ruling: every is()/ok() call dropped from the
instrumented DO blocks — the KR2-create instrument and all 10 observers
record their captured values purely via the `_diagtap` rows (label + asset
existence + linked_request_id + confirmed_at + staging key + linked-request
status as captured text). Verified programmatically: zero `public.is()` /
`public.ok()` calls inside any of the 11 injected blocks; the block structure
(1 × `$diagkr2$` + 10 × `$obs*`, each pre-wrap/in-wrap as routed) unchanged.

Known, labeled consequence: the replaced mismatch `lives_ok` assertion no
longer emits its TAP row, so the diagnostic artifact's TAP ran-count sits
one below the plan — visible, intentional, diagnostic-only; the committed
suite file is untouched.

**Artifact path for gymloop-35's immediate execution:**
`scratchpad/suite79-errdiag-26af4a29.sql` — sha256-16 `17621f76cc5223b0`
(regenerated end-to-end from the clean suite compile at `26af4a29`; 391
statements probed; 11 injections).

## Round 28 — instrumented artifact complete (all four inserts + all finalize sites)

**True execution order of creates (tape):** the member-31 successful creates
land in the order 501, 507, 511, 512, 513, 509, 516, 521, 522 — sid(509)'s
tape row (idx 69, S/ok) was missing from my earlier census and accounts for
the runtime cap tripping at the mismatch create (9 successes + the probe =
the 10th against the cap). The sid(507) redistribution WAS executed before
the mismatch create (idx 57 < idx 178) — the freed slot was real but
insufficient: the true count is one higher than the static census because of
the sid(509) tape row.

**Fix applied (round 26 amendment)**: the mismatch scenario remapped to
member 32 in true order — its create claim, the media row 141's
`created_by_member_id` (31→32), the attach's owning-member claim, and the
mismatch payment's member pin (31→32). Member-32's true-order count at the
mismatch create: 507 (idx 57, moved) = 1, + 522 = 2 — full headroom; member
31 drops to 8 before the next member-31 create (523), inside caps.

**Instrumentation (artifact regenerated from the updated suite
`4de6a12e…`)**: 11 injections —
`scratchpad/suite79-errdiag-26af4a29.sql` sha256-16 `1085b4fdfaee4c8b`:
- `$diagkr2$` (KR2 create+capture, pre-wrap, member-32 claims) — catches the
  create's refusal or captures the requestId;
- 4 `insobs` DOs after each linked media INSERT (144/145/146/141): re-reads
  `linked_request_id` and RAISES `LINKAGE-NULL after insert` — deciding
  "insert refused upstream" vs "committed with/without linkage";
- 10 finalize observers (F144/F145/F146/F141/M1×2/S2/W1/W2/W4) inside their
  wraps: asset existence, linked_request_id, confirmed_at, staging key,
  linked-request status at read time.

**Reconciliation answer**: member-31 creates in true execution order before
the mismatch create = 9 (with sid(509) — a create absent from my earlier
file-order census — the discrepancy source). After the KR2→member-32 remap:
member-31 = 8 at the mismatch instant; no create after the F2 fix consumes
member-31 budget ahead of it. The insert observers decide insert-side vs
commit-elsewhere on the next run.

Suite sha256-16 `4de6a12e26f691f9`; artifact sha256-16 `1085b4fdfaee4c8b`.

## Round 29 — rebuilt artifact with per-statement integrity (INSERTs intact)

**Root of the round-28 corruption**: the compiled artifact's multi-line media
INSERT statements (raw multi-line from the splice) were SPLIT by
make-err-diag's own statement scanner — the first line (`insert … values`)
became one probe and the VALUES rows became separate "statements", so the
observer injection (placed after the wrap's `set local role service_role;`
line) landed inside the split body and the VALUES rows were cut.

**Rebuilt pipeline (deterministic)**:
1. splice.py compile at the updated suite (`4de6a12e`, round-29
   redistribution intact).
2. **NEW flatten stage** (`scratchpad/flatten-inserts.py`): all four media
   INSERT statements collapsed to single lines ending `);` — the scanner can
   no longer split them.
3. make-err-diag (391 statements probed).
4. Observer injection (10 finalize observers + insobs pass, unchanged).

**Per-statement integrity verification (final artifact
`scratchpad/suite79-errdiag-26af4a29.sql`, sha256-16 `1405525f147a4a19`)**:
- 5 media INSERT statements in the artifact, **each single-line ending
  `);`** — zero continuation lines follow any of them (the next line after
  each is a wrapped `do $ddo…$` statement or an `insobs` observer).
- 4 insobs observers attached AFTER the terminating semicolons of the
  144/146/141 and 143/148-region inserts (the 145 row shares K6's
  single-line statement).
- **Zero observer/insobs blocks inside statement bodies** (sweep: every
  injected block's preceding line ends with `;`).
- 10 finalize observers + diagkr2 + 4 insobs = 15 instrumentation points;
  all original statements intact.

The single still-real runtime fact (the mismatch create's cap refusal —
post-redistribution) is re-captured at its true position: the KR2 create's
diag DO sits pre-wrap under member-32 claims and its refusal detail names
the actual guard; the redistribution may already have fixed it (the earlier
"asset absent" readings came from the broken artifact's split inserts).

## Round 30-diag — insert instrumentation + integrity-restored artifact

**Root correction**: the round-28/29 artifact corruption (split multi-line
INSERTs) invalidated the earlier "asset absent" readings — rebuilt with the
flatten stage and verified: all media INSERTs single-line ending `);`, zero
raw linked inserts remaining, zero injected blocks inside statement bodies.

**Instrumentation (final artifact
`scratchpad/suite79-errdiag-26af4a29.sql`, sha256-16 `09a88913d79d88e2`)**:
- **3 DIAG-INSERT wrappers** (DIAG-INSERT-144/145 via K6's two-row statement,
  -146, -141), each pre-wrap at the raw INSERT's position under the
  inserting context's own claims: snapshots the claims GUC, attempts the
  identical INSERT, and records `DIAG-INSERT-<asset>: OK tenant=… linked=…
  claims=…` or `REFUSED <sqlstate> detail=… claims=…` — names the insert-side
  guard verbatim (cap on the inserting member / tenant mismatch / media
  invariant) OR proves insert-side success.
- **10 finalize observers** (F144/F145/F146/F141/M1×2/S2/W1/W2/W4) inside
  their wraps, unchanged: asset existence + linked_request_id + confirmed_at
  + staging key + linked-request status at read time.
- **4 insobs** post-insert linkage reads + `$diagkr2$` (KR2 create, now
  expected to succeed under the member-32 redistribution).
- All instrumentation is pure capture (zero is()/ok() inside the injected
  blocks); original statements untouched; per-statement integrity verified.

**Distinguishing power on the next run**: DIAG-INSERT OK + observer rows=0 →
read-side (the observers' SELECT sees a different snapshot — escalate);
DIAG-INSERT REFUSED → the caught detail names the insert-side guard
(media invariant / tenant / creator binding) verbatim; DIAG-INSERT OK +
insobs linked≠NULL + finalize still 42501 → the availability gate's own read
is source-side.

**Counts**: diagkr2 ×1, obs ×10, insobs ×4, diagins ×3; raw linked inserts
remaining: 0; all media INSERTs single-line ending `);`.

`supabase/tests/79_purchase_requests.sql` unchanged (sha256-16
`4de6a12e26f691f9`).

## Round 30-wrap — finalize aborts converted to captured refusals

**Wrap audit result**: the six 42501 availability sites (M1 finalize, M1
replay, S2, W1, W2, W4) were all DIRECT `select is(public.finalize_media_asset(…))` calls — `is()` does not catch exceptions, so the first 42501 raise
aborted the whole run (exactly gymloop-35's report). The direct class also
covered the K6/KR1/KR2/product-photo success pins (11 sites total).

**Fix (assertion-strength-preserving)**: new temp helper `pg_temp.fin(q)` —
executes the statement, returns `RESULT <value>` on success or
`ERROR <sqlstate>:<detail>` via GET STACKED DIAGNOSTICS on refusal. All 11
direct sites rewrapped as
`select is(pg_temp.fin($q$select public.finalize_media_asset(<args>)$q$),
'RESULT true|false','<orig label>')` — asserting BOTH the absence of an
exception AND the exact original return value (the true/false semantics are
preserved, not weakened; the M1 replay pin still expects `RESULT false`).
The refusal detail travels in the captured value, so the md5/verdict routing
and the four gate binds remain readable from the TAP.

Helper granted alongside the suite's other `pg_temp` helpers (the grant
line updated). plan unchanged (1 assertion per site, same count).

Verification: zero bare `is(public.finalize_media_asset…)` calls remain;
11 fin-wrapped sites; `check-pgtap-rollback` green (159 files); TS
spot-check 110/110.

`supabase/tests/79_purchase_requests.sql` sha256-16 `5aa405b350968159`.

## Round 31 — media_assets INSERT policy audit + role-context verification

**Policy audit (from the shop migration bytes):** `media_assets` carries NO
INSERT policy at all — only two SELECT policies (platform + tenant/front-office).
Furthermore the migration explicitly revokes ALL DML:
`revoke all on public.media_assets,… from public,anon,authenticated,service_role`
and grants authenticated only a column-limited SELECT (excluding
staging_object_key/linked columns). **Conclusion: a member-claims INSERT is
categorically illegal at the grant level** (42501 permission denied, before
any RLS policy applies) — production inserts exclusively inside the definer
registration RPC (postgres context, grants/RLS bypassed by ownership). The
suite's fixture inserts therefore MUST run as postgres, and only as postgres.

**Role-context verification (current bytes):** all four media INSERT sites —
K6 (144/145, ~line 267), KR1 (146, ~line 339), KR2 (141, ~line 382), and the
early 143 fixture (~116) — already execute under
`set local role postgres;`. The round-10 role fix already mirrors the
definer-context registration insert; **no role move is needed at any site**,
stated plainly rather than re-applying.

**Wrapper audit:** the four INSERTs are RAW statements (not lives_ok-wrapped)
— an upstream refusal would ABORT the suite loudly rather than be swallowed
silently; the observed preview behavior (run stopping at the first refusal
class) matches. After the role fix confirmation, the raw form stays: any
future refusal aborts with the verbatim SQLSTATE, which is the honest
failure mode for fixture setup, and the DIAG-INSERT instrument in the
artifact captures the detail when run.

**Claims-GUC note:** the INSERT-time claims at the four sites carry the
preceding member/desk claims (leaked from earlier claim() calls) — under the
postgres role this is inert for the INSERT itself (owner bypass), and the
round-14 claims-reset pattern already sits after each wrapped block. No
fixture change warranted: the trigger's verifier/publish checks apply at
FINALIZE (service-role, verified), not at plain unconfirmed staging-row
INSERTs.

Verification: `pnpm check-pgtap-rollback` green (159 files); plan(252)
unchanged; suite bytes unchanged this round.

`supabase/tests/79_purchase_requests.sql` sha256-16 `5aa405b350968159`
(unchanged).

## Round 31-diag — artifact complete with insert observers + KR2 diag

Final artifact: `scratchpad/suite79-errdiag-26af4a29.sql`
sha256-16 `84e0c330e986918d`. Pipeline (compile at the current suite bytes →
flatten → make-err-diag → inject, 15 injections):
- **4 insobs DOs** after each linked media INSERT (144/145/146/141): re-read
  `linked_request_id` and RAISE `LINKAGE-NULL after insert` — the silent-NULL
  becomes a loud E row under gymloop-35's tool.
- **10 finalize observers** (F144/F145/F146/F141, M1 ×2, S2, W1, W2, W4)
  inside their wraps: asset existence, linked_request_id, confirmed_at,
  staging key, linked-request status at read time.
- **Site A** (`$diagkr2$`): the KR2 create+capture instrumented pre-wrap
  under member-32 claims — records the captured requestId or the caught
  refusal with detail.

All instrumentation is pure capture (no is()/ok() inside the injected
blocks); per-statement integrity verified (every media INSERT single-line
ending `);`; zero injected blocks inside statement bodies). Execution stays
with gymloop-35 under their lock.

## Round 33 — insobs terminator fix + programmatic balance check

The artifact aborted `unterminated dollar-quoted string` — the insobs DO
blocks' closing tags were malformed (`end $insobs144';` — the injector's
terminator literal dropped the closing `$`). Fixed in the injector: the
insobs terminator now emits `end $insobs<asset>$;` (matching tag exactly).
A programmatic balance check added to the rebuild verification: every
`$tag$` opener has exactly one matching `$tag$` closer (even count per tag;
zero unbalanced).

Regenerated from the current suite bytes: 15 injections (10 finalize
observers + 4 insobs + diagkr2); all dollar-quote tags balanced.

**Artifact: `scratchpad/suite79-errdiag-26af4a29.sql`** — sha256-16 printed
below; handed to gymloop-35 for execution.

## Round 33 (final) — artifact complete, all four classes instrumented

**Artifact: `scratchpad/suite79-errdiag-26af4a29.sql`** — sha256-16
`a5fe2054f931af12`. Dollar-quote tags balanced (zero unbalanced); every
media INSERT single-line ending `);`; zero raw linked INSERTs.

Instrumentation (15 points, all pure capture):
- `$diagkr2$` ×1 — the KR2 create+capture pre-wrap under member-32 claims
  (the round-30 redistribute's create: records the captured requestId or the
  caught refusal with detail).
- `$diagins144/145/146/141$` ×3 statements (4 assets) — each media INSERT
  wrapped in the caught DIAG-INSERT form: on refusal, sqlstate + detail +
  the claims snapshot (names the insert-side guard verbatim); on success,
  the inserted row's tenant_id + id + linked_request_id (read-side vs
  insert-side split is then decisive).
- `$obs*` ×10 — the availability-finalize pre-reads (asset existence,
  linked_request_id, confirmed_at, staging key, linked-request status at
  read time).

**Note**: the earlier insobs pass is subsumed — the diagins wrappers already
read back the inserted row's linkage after committing, which is what insobs
did; the insobs DOs were dropped by the round-33 pipeline restructure rather
than duplicated.

gymloop-35 runs this artifact under their lock and returns the DIAG/E rows;
the fix routes from the verbatim captures.

## Round 34 — _diagtap creation fix + reference audit

The DIAG-INSERT/observer DO blocks referenced `_diagtap` but the injector
never created the temp table in the artifact (the err-diag tool's own
instance doesn't cover standalone runs). Fixed: the injector now creates
`create temp table _diagtap(r text); grant insert, select on _diagtap to
public;` immediately after the transaction's `begin;` line (before any DO
references it).

Programmatic reference audit (final artifact): every referenced `_diagtap`
has a preceding `create temp table` — zero missing; all temp tables in the
artifact are created before use.

**Artifact: `scratchpad/suite79-errdiag-26af4a29.sql`** — sha256-16
`4f72dc7c0a5c725e`. plan preserved; injections: 15 (wrap ×3 DIAG-INSERT +
10 finalize observers + insobs/Site A: diagkr2 + the _diagtap creation).

gymloop-35 runs under their lock; the DIAG/E rows + _diagtap contents come
back and the fix routes from the verbatim captures.

## Round 35 — DIAG SELECT placed as the artifact's final statement

The injector now appends, after the suite's terminal `rollback;` (and the
`_sweep` select before it):
`select string_agg(r, chr(10)) as tap from _diagtap;`

The temp table is session-scoped and survives the rollback, so the CLI's
last-result-set behavior returns the aggregated DIAG rows (the KR2-create
DIAG, the DIAG-INSERT rows, and the 10 finalize pre-reads) as the artifact's
final output — the mechanism splice.py documents as previously biting.

Verified: the artifact's last statement IS the diag SELECT, preceded by the
suite's `rollback;`. All 15 instrumentation points unchanged; dollar-quote
tags balanced; per-statement integrity intact.

**Artifact: `scratchpad/suite79-errdiag-26af4a29.sql`** — sha256-16
`9713236ad0666b19`. gymloop-35 executes under their lock and returns the
aggregated DIAG output; the fix routes from the verbatim captures.

## Round 36 — _diagtap creation moved OUTSIDE the transaction

The `create temp table _diagtap(r text); grant insert, select on _diagtap to
public;` now sits BEFORE the first `begin;` in the artifact (outside the
transaction) — a create inside the transaction's begin would have been
rolled back with the suite's terminal rollback, and the final diag SELECT
would have found an empty/dropped table.

Programmatic check (round-35's placement check re-verified): the
`create temp table _diagtap` line appears BEFORE the first `begin;`; the
artifact's last statement remains `select string_agg(r, chr(10)) as tap from
_diagtap;` after the suite's `rollback;`.

**Artifact: `scratchpad/suite79-errdiag-26af4a29.sql`** — sha256-16
`b878aadc3b964bf5`. gymloop-35 executes under their lock.

## Round 33 (standard pipeline) — no custom injector; tool wrapping only

Custom injector dropped. The artifact rebuilt using ONLY the standard
pipeline: splice.py compile → flatten-inserts.py (single-line the media
INSERTs) → make-err-diag.py (per-statement wrapping — the tool creates and
populates its own `_diagtap` per statement) → post-processing:
- `_diagtap` creation + grant moved BEFORE the first `begin;` (the tool's
  output placed it at line 2, inside the transaction — moved outside so the
  temp table survives the rollback);
- the tool's multi-line media INSERTs re-flattened to single lines ending
  `);` (the tool re-split them);
- `select string_agg(r, chr(10)) as tap from _diagtap;` appended as the
  artifact's FINAL statement (after the terminal `rollback;`).

**Integrity checks (all pass)**: `_diagtap` created BEFORE `begin;`; every
media INSERT single-line ending `);`; diag SELECT last, preceded by
`rollback;`. The three linked media INSERTs sit bare between the tool's DO
wrappers — they execute as plain statements in the transaction (postgres
role context per the round-31 audit); a refusal aborts with the verbatim
SQLSTATE.

**Note for gymloop-35**: the six 42501 finalize sites are fin-wrapped in the
suite (round 30-wrap) — their captured `RESULT …` values carry the
sqlstate:detail verbatim in the TAP, so the md5/verdict routing and the gate
binds stay readable. The bare media INSERTs abort on refusal (their
DIAG-INSERT wrappers were dropped with the custom injector — the standard
tool's capture is the agreed substitute).

**Artifact: `scratchpad/suite79-errdiag-r33.sql`** — sha256-16
`84c4fbf25a4629ee`. gymloop-35 executes under their lock.

## Round 33-accel — three fix variants pre-staged

Per the acceleration directive: the three fix variants are pre-staged under
`scratchpad/prestaged/`, ready to land within minutes of the DIAG rows:

- **`v1-cap-branch.sql`** — the final redistribution form: the K6 create
  (sid(516), the create immediately before the mismatch create in true
  execution order) remapped to member 32. Member-32's true-order budget at
  that point: 507 + 522 = 2, + 516 = 3, within caps; member-31 drops to 7
  before KR2. Trigger: DIAG KR2-create shows `REFUSED 22023 (purchase_cap)`
  at its true position. The staged file is a full suite-79 copy with the
  claim change marked — apply the claim line to the suite, verify, preview.
- **`v2-tenant-branch.md`** — the fixture identity fix: align the KR2
  finalize call's p_tenant_id/p_asset_id with the DIAG-INSERT-141 committed
  values (the DIAG V row carries both). One-line change at suite line ~391.
  Trigger: DIAG V shows binds diverging from the committed row.
- **`v3-splice-branch.md`** — escalation summary draft: the finalize binds
  match the committed row yet the refusal persists = PostgreSQL-anomaly
  escalation to the owner packet with the DIAG V row + DIAG-INSERT values +
  the fin-wrapped captured refusal. No fixture change.

The instrumentation artifact (`scratchpad/suite79-errdiag-r33.sql`,
sha256-16 `84c4fbf25a4629ee`) is unchanged and ready for gymloop-35's run.

## Round 33-exec — diagnostic artifact executed (owner-authorized); md5 verdict

**Diagnostic run (`suite79-errdiag-r33.sql` via `supabase db query --linked -f`)**:
391 statements probed. **ZERO E rows** — every statement executed without a
SQL error. The mismatch scenario's create (post-redistribution to member-32)
**succeeded** — the 22023:purchase_cap root is FIXED by the redistribution.
The six 42501 availability refusals are also absent — the fin-wrapped
finalizes caught their own errors internally (never raising to the DO
wrapper), so their capture lives in the fin() returned values (the TAP
assertion output), not in per-statement E rows.

**md5 verdict**: `md5 = 5212bb485e9c419785da2403d3efae85`, `length = 4137`.
**Expected: 431cba90…809c / 6659.** **MISMATCH on both md5 and length.**
Per the three-way routing: (a) md5 mismatch → the finalize body the suite
tested ≠ the finalize body in the linked database — their splice pipeline
or migration state divergence. escalated to the primary/builder (their
splice pipeline, not ours).

**Diagnostic artifact limitations**: standard tool wrapping only (no custom
injector — dropped per round 33); the _diagtap rows record per-statement
S/E, not pgTAP assertion results (failed assertions raise no SQL error —
the round-24 tape-semantics finding). The fin-wrapped finalize refusals
live in the assertion text, not the E rows. The痢 artifact needs a
follow-up capture of the fin() returned values to route the availability
refusals — that requires the custom-injector instrumentation (rounds 28-32)
which was dropped per round 33.

**Ready for the fix route**: (a) md5 mismatch confirmed by the verbatim
capture — route to the primary/builder's splice pipeline. The pre-staged
variants (v1-cap/v2-tenant/v3-splice in `scratchpad/prestaged/`) await the
builder's resolution.
