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
