# Parallel MEDIA/PAY progress — coordinator checkpoint

Packet: `docs/planning/v2-fast-agent-media-handoff.md`. Assignment started 2026-10-04.

## Coordinator baseline (2026-10-04)

- HEAD `e8476ee57b219f40eb7f503395540b7555dc2fa3` confirmed. Unpushed commits ahead
  of origin/main present (push/Firebase `spec:`/`feat:` series, PAY fix `f0fcd641`).
- Preserved untouched (other agents): `apps/web/lib/purchase.ts`,
  `apps/web/lib/purchase-commands.ts`, `apps/mobile/lib/member-freeze-requests.ts`,
  freeze-request web/mobile files, `push-event` route, the four uncommitted
  migrations, `supabase/tests-holdout/h79_purchase_requests_holdout.sql`,
  `docs/registry.md`, v2 bar docs, wave proposals.
- Gap map (coordinator survey, public contract level):
  - `supabase/functions/media/index.ts` (committed `7f2a5b9`, 259 lines) admits
    only `confirm` / `member-url` / `staff-url`. No PAY proof operations.
  - `apps/web/lib/purchase-http.ts` `proofUploadUrl` case is an explicit stub:
    returns `operation_failed` with a MEDIA-integration comment.
  - `proofConfirm` already delegates to `attach_payment_proof`;
    `proofUrl` already validates and serves `read_purchase_proof_url` output.
  - `apps/web/app/api/purchase-requests/[id]/proof-asset/route.ts` exists (67 lines).
  - DB side `payment_proofs`, key regexes (`staging/payment_proof`,
    `published/payment_proof`) and `read_purchase_proof_url` are present in the
    uncommitted `20261004100000_purchase_requests.sql` (another agent's file).
- Roles launched (fork agents per owner model policy, 2026-10-03):
  1. Source-blind visible test author — PAY MEDIA proof extension.
  2. Holdout author — same boundary, contract-only reading.
  3. Implementer — already-committed-RED work only (run committed visible
     media/purchase suites, repair source to green; no holdout access).

## Implementer round 1 (2026-10-04)

- Focused committed suites: 11 files / 255 tests, **all green**. No committed RED
  attributable to the PAY proof extension; no committed test pins the
  `proofUploadUrl` stub outcome.
- Per packet rule ("new gaps need actual RED before source"), implementer changed
  **zero source** and stopped. Repair plan staged in
  `docs/evidence/v2/parallel-media-pay-implementer-report.md` for the
  test-authorized round.
- Deno check on the Edge function blocked from repo root by pnpm virtual-store
  `@types/node` resolution (known Windows limitation); earlier green Edge checks
  ran from a snapshot worktree. No verification debt — tree unchanged.

## Visible test author round 1 (2026-10-04)

- 5 new untracked visible test files, 69 tests: **39 RED / 30 passing
  contract-required pins**. RED receipt: `Test Files 5 failed (5)` /
  `Tests 39 failed | 30 passed (69)`.
- Files (author's, uncommitted, awaiting primary `spec:` commit):
  - `packages/shared/src/api/__tests__/purchase-visible-proof-media.test.ts` (4 RED)
  - `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts` (24 RED)
  - `apps/web/app/__tests__/purchase-visible-proof-upload.test.ts` (4 RED)
  - `apps/web/app/__tests__/purchase-visible-proof-surface.test.tsx` (3 RED)
  - `apps/mobile/lib/__tests__/purchase-visible-native-proof-upload.test.tsx` (4 RED)
- Full per-file hashes, contract-level requirements and three flagged seam
  assumptions: `docs/evidence/v2/parallel-media-pay-visible-author-report.md`.

## Holdout author round 1 (2026-10-04)

- New file `supabase/tests-holdout/media-proof-held.test.ts`
  (sha256 `ee83585e…c4dedc`, author-owned, uncommitted).
- RED: `pnpm exec vitest run supabase/tests-holdout/media-proof-held.test.ts --maxWorkers=2`
  → **Tests 26 failed | 22 passed (48)**; receipt sha256 `23b6ad17…f4fe39`.
- All 26 RED from one public fact: Edge answers `proof-confirm`/`proof-url`
  with 400 `invalid_request` — frozen proof media extension absent. 22 passing
  cases are contract armor pins that already hold.
- Coverage topics (contract-derived): identity/shape armor, confirm ordering
  (auth before privileged/R2 access, one 404 for foreign/unknown), private
  publish pipeline (conditional copy to fresh published key, destination
  recheck, one member-actor finalization, no client PUT at published keys),
  fail-closed matrix with unconfirmed-only cleanup, replay/race safety (loser
  cleans only own candidate, winner preserved), private URL (member-or-verifier,
  TTL ≤60s, no-store, single external refusal, general signers never expose
  `payment_proof`), money-command hygiene.
- Report (paths/counts/hashes/topic labels only):
  `docs/evidence/v2/parallel-media-pay-holdout-author-report.md`.

## READY FOR PRIMARY — test-only spec: commit checkpoint (2026-10-04)

Primary, please commit as test-only `spec:` (this chat may not stage/commit):

1. `packages/shared/src/api/__tests__/purchase-visible-proof-media.test.ts`
2. `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
3. `apps/web/app/__tests__/purchase-visible-proof-upload.test.ts`
4. `apps/web/app/__tests__/purchase-visible-proof-surface.test.tsx`
5. `apps/mobile/lib/__tests__/purchase-visible-native-proof-upload.test.tsx`
6. `supabase/tests-holdout/media-proof-held.test.ts`

RED state at authoring: visible 39 failed / 30 passed (69) across the five
files; holdout 26 failed / 22 passed (48) standalone. Reports with per-file
sha256: `parallel-media-pay-visible-author-report.md`,
`parallel-media-pay-holdout-author-report.md`. Once the commit is recorded,
this chat launches the implementer source repair against it.

Note for the implementer round: holdout's simulated request-truth RPC payload
is contract-shaped; shape corrections belong to the holdout author, not the
builder — report shape mismatches back to this coordinator, do not edit holdouts.

## Primary gate satisfied — implementer round 2 launched (2026-10-04)

- Primary committed the test-only gate as `d77ac267 spec: independently require
  trusted private payment proof uploads` (all 5 visible files + holdout file +
  both author reports; 8 files, 1211 insertions). No staging done by this chat.
- Implementer resumed for round 2: Edge proof operations, `proofUploadUrl` stub
  replacement, smallest committed-test-authorized web/native surface additions.
  Same boundaries: holdout still invisible, no test edits, no commits, no Cloud
  SQL, no registry edits. Shape conflicts with the frozen contract are reported,
  not bent to.

## Session resume — parallel implementer round 2 (2026-10-04, later)

- Previous session ended; the resumed implementer stopped with **zero source
  changes landed** (verified: no diff on `supabase/functions/media/index.ts`
  or `apps/web/lib/purchase-http.ts`; HEAD still `d77ac267`).
- Primary checkpoint found and honored:
  `docs/evidence/v2/parallel-media-pay-primary-checkpoint.md` — authorizes
  source repair against the committed gate, records root RED **117 tests,
  65 failed / 52 passed** over the six unchanged files, permits no invented
  projections/admin clients, currency clarification `6d6a6a4a` noted.
- Two parallel implementers launched with disjoint file sets:
  1. **Source implementer** — packages/shared proof vocabulary/schemas,
     `supabase/functions/media/index.ts` proof operations, `purchase-http.ts`
     stub replacement. Identity/money-critical half, full blind discipline.
  2. **Screens implementer** — `apps/web/app/member/buy/**` and native upload
     surface only (relaxed rigor per ADR-059); no shared/Edge/transport edits.
- Both: holdout invisible, no test edits, no commits, no Cloud SQL, no
  registry/decisions edits, other agents' uncommitted files preserved.

- Test-only `spec:` commits for newly authored visible/holdout tests before any
  new-test-driven source repair launches.
- Integration requests: none yet.

## Screens implementer round (2026-10-04)

- 7/8 committed screen tests green (was 1/8). Sibling purchase suites 93/93
  green; web+mobile `tsc` clean; scoped lint clean (1 pre-existing generated-file
  warning). Changed exactly 3 files: `apps/web/app/member/buy/purchase-actions.tsx`,
  `apps/web/app/member/buy/[requestId]/page.tsx`, `apps/mobile/app/(member)/buy.tsx`.
- Report: `docs/evidence/v2/parallel-media-pay-screens-report.md`.
- **Test-vs-test conflict found, escalated, NOT resolved in source:**
  `purchase-visible-proof-surface.test.tsx` forbids "Payment recorded" on the
  detail page at `payment_proof_uploaded`; `purchase-visible-member-buy-page.test.tsx`
  requires that exact word on the same page/state (4-word stepper). Both committed
  in `d77ac267`. Needs owner/primary `spec:` adjudication of BUY-022's boundary
  (state claim vs future stepper label).
- Dependencies recorded: web interactive flow needs `expectedRevision` in the
  read model + transport envelope (source implementer scope); native picker
  needs `expo-image-picker` — absent, owner decision per capability-audit rule;
  native shows online-tap states honestly until then.
- Nothing staged/committed by this chat.

## Source implementer round 2 (2026-10-04)

- Built (6 files, 167+/26−): shared proof kind/key codec/schemas; Edge
  `proof-confirm` + `proof-url` (auth-before-privileged-access, shared
  immutable publication pipeline, ≤60s proof-url, no secret logging);
  `purchase-http.ts` stub replaced (registration → staging-only presign,
  GL126→429, GL086 media_limit→429); `proofConfirm` runs trusted Edge
  verification before `attach_payment_proof`; `media.ts` invoke union widened;
  `proof-asset/route.ts` envelope unwrap fixed (was reading nonexistent `url`
  key — byte streaming could never work).
- Focused suites 327/330 (3 recorded test conflicts, source not bent);
  shared+web typecheck clean; web lint clean; `deno check` clean (2.9.6 via
  npx from `supabase/functions/`).
- Report: `docs/evidence/v2/parallel-media-pay-implementer-report.md`.
- Recorded test conflicts (for test authors, not source): loser-fixture
  `not.toContain('')` unsatisfiable; fake auth handler ignores override claims;
  `media-visible.test.ts:10` stale exact-3 `MEDIA_KINDS` pin.
- Integration requests: `register_payment_proof` mime/bytes seam (schemas now
  optional; screens should declare); pin one RPC result spelling; media holdouts
  to be run against new Edge source by coordinator (holdout invisible to builder).

## Review round launched (2026-10-04)

Three parallel forks: fresh source/security critic (10 critical checks,
GO/NO-GO per dimension), fresh rendered-UI critic (pay-bar, light/dark/200%/320px,
screenshots under docs/evidence/v2/media/), visible-test fixture reconciler
(3 mechanical defects only; "Payment recorded" wording conflict left for
owner adjudication).

## Owner decisions outstanding

1. "Payment recorded" stepper-wording conflict (BUY-022 boundary).
2. `expo-image-picker` dependency for native upload (capability-audit rule).

## Test fixture reconciler round (2026-10-04)

- Three mechanical fixture defects repaired, source untouched, assertions
  strengthened-or-equal: loser-cleanup fixture now meaningfully asserts the
  winner's published key survives; auth double derives identity from each
  request's own bearer token (desk proof-url path genuinely exercised);
  `MEDIA_KINDS` pin gains `payment_proof` per contract with round-trip checks.
- Repaired files: `apps/web/lib/__tests__/purchase-visible-proof-edge.test.ts`
  (sha256 `52212555…b4d34`), `packages/shared/src/api/__tests__/media-visible.test.ts`
  (sha256 `e4bee9df…bbc0`). Report:
  `docs/evidence/v2/parallel-media-pay-test-fix-report.md`.
- Counts: baseline 3 failed / 180 passed (183) → **4 files / 184 passed (184)**
  (+1 strengthened). Guard run: only remaining failure is the owner-adjudication
  wording conflict. These test edits await the primary's `spec:` commit.

## Source/security critic round 1 (2026-10-04)

- Verdict: (a) Edge+transport **NO-GO**, (b) screens **GO-WITH-FIXES**.
  Report: `docs/evidence/v2/parallel-media-pay-critic-source.md`.
- HIGH findings:
  1. `finalize_media_asset` unamended by the PAY migration — still staff-only
     + old key regex, so member proof-confirm can never finalize. **Primary-owned
     SQL integration request** (exact patch listed in critic report).
  2. Edge `asset()` select lists omit `created_by_member_id` → member
     proof-confirm/proof-url always 404 at runtime; mocked tests cannot catch
     select-list omissions.
  3. Web upload dead end-to-end: button POSTs `{}`, RPC requires mime/bytes
     (22023), no file-input/PUT/confirm flow on web.
- MED: proofUrl signs derived key for unconfirmed assets; proof-asset route
  may not forward caller JWT (repo convention passes it explicitly); schema vs
  RPC mime/bytes seam; confirm-time liveness re-proof weaker than contract.
- Fix loop launched: both implementers resumed with their findings lists
  (source implementer closes 2–6 source-side; screens implementer closes its
  GO-WITH-FIXES items). Findings 1 and 7 recorded as primary integration requests.

## Owner decisions outstanding

1. "Payment recorded" stepper-wording conflict (BUY-022 boundary).
2. `expo-image-picker` dependency for native upload (capability-audit rule).
3. **New — SQL integration request**: amend `finalize_media_asset` for
   member-created payment_proof assets + new published-key regex (primary).

## Rendered UI critic round 1 (2026-10-04)

- Verdict **GO-WITH-FIXES** for the renderable surface. Report:
  `docs/evidence/v2/parallel-media-pay-critic-rendered.md`; 11 state HTML dumps
  in `docs/evidence/v2/media/` (temp harness, deleted after; zero edits).
- Live browser render impossible: **pre-existing route conflict
  `notifications/[id]` vs `[notificationId]` kills `next dev` boot** —
  other agent's uncommitted file; flagged for primary.
- PASS: copy truth, JPG/PNG/WebP + 2 MB disclosure, rejected-proof reason +
  re-upload, exact money formatter, honest mismatch/terminal states, Chalkline
  tokens, aria labels. Native 4/4 committed tests pass.
- MINOR ×3 sent to screens implementer: StageList visual mark, `cancelled`
  next-action copy, tripled "raise a request" guidance.
- Critic reading supports "Payment recorded" as stage label (surface test regex
  over-broad) — still owner `spec:` adjudication, untouched.
- NOT passed, honestly blocked: interactive upload flow and all visual criteria
  (themes, 200%, 320/1440, touch targets) — need live transport + dev boot.
  Full pay-bar GO stays blocked on those.

## Screens implementer fix round (2026-10-04)

- Source critic HIGH-3 closed: real web upload flow in `MemberPurchaseActions`
  (hidden file input, client preflight vs MEDIA_MIME_TYPES/maxBytes, POST
  `{mime, bytes}`, staging PUT, `proof-confirm` with read-model
  `acceptedRevision` + fresh command key, honest success copy, refresh after
  attach). No invented envelope parsing.
- Rendered critic 3 MINORs closed: `● ` stage mark (`cl-status` convention),
  `cancelled` next-action copy, single "raise a request" section.
- Tests: **100/101** across 6 files; the 1 failure is the owner-adjudicated
  wording conflict. Files' tsc clean; web project tsc exit 1 comes only from
  generated `.next/types/validator.ts` — the pre-existing
  `notifications/[id]`/`[notificationId]` route conflict (now also blocks tsc
  after a dev regeneration). Lints clean.
- Report updated (round 2 section, hashes). Nothing staged/committed.

## Source implementer round 3 (2026-10-04)

- All source-side critic findings closed:
  - HIGH-2: `created_by_member_id` added to Edge PRIVILEGED select (deliberately
    not SAFE — authenticated grant lacks the column; grant extension = optional
    primary integration request).
  - HIGH-3: `uploadPaymentProof(file, requestId, expectedRevision, commandKey, onStage?)`
    in `media-upload.ts` (declares mime/bytes, proof-upload-url, staging PUT,
    proof-confirm); screens wire their button to it.
  - MED ×4: proofUrl signs only through `published()` (derived-key fallback
    removed); proof-asset route forwards verified capability (header bearer,
    else cookie session); seam aligned (schema optional per committed test pin,
    client always declares); `proofExposure` binds to the registered request
    when `activeProofAssetId` matches + row live (first-upload residual =
    integration request 2).
- Focused set 17 files → **329/331**. New recorded conflict: two proof-url
  success tests run against an UNCONFIRMED asset, pinning pre-gate behavior —
  fixture amendment dispatched to test author (set confirmed=true; all existing
  assertions then contract-true). Shared/web typecheck clean (except pre-existing
  `.next` artifacts), lints clean, `deno check` clean.
- New hashes: Edge `c8456e4b…`, media-upload `6ac4d455…`, proof-asset `b4f0ea66…`.
- Integration requests for primary (restated): finalize_media_asset
  member/payment_proof amendment; registration-time request linkage; optional
  created_by_member_id grant; mime/bytes seam decision.

## Test fixture reconciler round 2 (2026-10-04)

- Both proof-url success fixtures now stage `confirmed = true` before invoking,
  so their existing assertions run contract-true against the new verified-state
  gate (BUY-008/009). No assertion weakened; refusal/foreign/auth-first checks
  untouched; zero source edits.
- Run: 6 files → **203/203 passed**, fully green. The owner-adjudicated
  "Payment recorded" conflict (in `purchase-visible-proof-surface.test.tsx`)
  remains the single open failure campaign-wide.
- New sha256 `purchase-visible-proof-edge.test.ts`:
  `1393acff2fd4e33ec192d1d49ac99702865d87cdeb91aa579c79c12d4f5fde00`.
  Report: `docs/evidence/v2/parallel-media-pay-test-fix-report.md` (round 2).

## Screens implementer fix round — recorded (2026-10-04)

- Source critic HIGH-3 closed: real web upload flow in `MemberPurchaseActions`
  (hidden file input, client preflight vs `MEDIA_MIME_TYPES`/`maxBytes`, POST
  `{mime, bytes}`, staging PUT, `proof-confirm` with read-model
  `acceptedRevision` + fresh command key, honest success copy, refresh after
  attach). No invented envelope parsing.
- Rendered critic MINORs closed: `● ` stage mark (`cl-status` convention),
  `cancelled` next-action copy, single "raise a request" section.
- Tests: **100/101** across 6 files; sole failure = owner-adjudicated wording
  conflict. Files' tsc clean; web project tsc exit 1 only from generated
  `.next/types/validator.ts` (pre-existing `notifications/[id]`/`[notificationId]`
  route conflict, another agent's file — now also blocks tsc after dev
  regeneration). Lints clean.
- Report: `docs/evidence/v2/parallel-media-pay-screens-report.md` (round 2,
  hashes). Nothing staged/committed.

## Critic round 2 launched (2026-10-04)

Fresh verification critic dispatched: per-finding CLOSED/STILL-OPEN/REGRESSED
against round 1, ten critical checks re-run on the new code, focused suites
re-run verbatim, verdict per dimension. Report target:
`docs/evidence/v2/parallel-media-pay-critic-source-r2.md`.

## Critic round 2 (2026-10-04)

- Report: `docs/evidence/v2/parallel-media-pay-critic-source-r2.md`.
- Closure: HIGH-1 STILL-OPEN (correctly — primary SQL, honestly recorded);
  HIGH-2, HIGH-3 and all four MEDs **CLOSED**, verified against source.
- Ten critical checks: **PASS** (check 3 fails only as integrated, pending the
  primary's finalizer amendment).
- Tests: 1 failed / 210 passed (211) — sole failure the owner-adjudicated
  wording conflict. `deno check` clean (exit 0).
- New findings: MED — `uploadPaymentProof` (media-upload.ts:33) exported with
  no caller; component inlines duplicate protocol → wire-or-drop dispatched to
  source implementer (round 4). LOW — verifier cannot re-obtain proof URL for
  `recorded`/`mismatch_recorded` (bound-path status gate) → owner contract
  question, code left narrow. Round-1 LOW-10 (`p_limit: 0`) verified clean.
- **Verdicts: Edge+transport GO-WITH-FIXES** (blockers = primary SQL integration
  request + helper cleanup) — **Screens GO** (native placeholder pending owner's
  `expo-image-picker` decision; failing test is the adjudicated conflict, not a
  screen defect).

## Owner decisions outstanding (updated)

1. "Payment recorded" stepper-wording conflict (BUY-022 boundary).
2. `expo-image-picker` dependency for native upload (capability-audit rule).
3. SQL integration requests: finalize_media_asset member/payment_proof amendment
   (blocks runtime finalization); registration-time request linkage; optional
   created_by_member_id grant; mime/bytes seam decision.
4. LOW: whether verifier may re-obtain proof URL for recorded/mismatch_recorded
   requests (currently refused by bound-path status gate).

## Source implementer round 4 (2026-10-04)

- Critic r2 MED closed: **WIRED** — `MemberPurchaseActions.upload` delegates to
  the shared `uploadPaymentProof`; dead inline `postCommand` runner removed with
  the duplicated protocol. Only `purchase-actions.tsx` touched
  (sha256 `119f216d3728a440…`). LOW verifier-reobtain question left as-is.
- Focused set: **302/303**; sole failure = owner-adjudicated wording conflict
  (same test, same cause as before this change; no regression). Web typecheck
  clean (2 stale `.next` artifacts only); web lint clean.
- All critic r2 named fix conditions now met. Final completion report:
  `docs/evidence/v2/parallel-media-pay-completion.md`.

## Owner decisions resolved + completion wave (2026-10-04)

Owner answered (recorded, binding):
1. **Stage label OK** — stepper may show "Payment recorded" as future stage;
   only state-claims forbidden (BUY-022).
2. **Add expo-image-picker** — native upload ships in this push.
3. **Allow re-obtain** — owner member + same-tenant verifier keep URL access
   after recorded/mismatch_recorded.

Execution:
- `expo-image-picker@^57.0.20` installed (@gymloop/mobile + lockfile only).
- Visible test author round 2 done: wording fixture narrowed to state-claims
  (GREEN, compatible with stepper pin); 7 new bound-path proof-url cases
  (GREEN at Edge boundary — the LOW gate is SQL-side `pay_take_capability`,
  folds into the SQL patch); 3 native picker cases (offline green, 2 RED-by-design).
  Files sha256-16: `80aee03a4549da67`, `68b0ab28eba3dc91`, `0f6048c5af7f1d34`.
- In flight: SQL visible RED author (finalizer member amendment +
  registration-time linkage), route-conflict builder, native picker implementer.
- Note: Edge needed NO source change for re-obtain — SQL capability gate owns it.

## Route conflict fixed (2026-10-04)

- Same defect in two trees: `api/member/notifications/` ([id]/delivered vs
  [notificationId]/push-event) AND `api/notifications/` ([id]/whatsapp vs
  [notificationId]/whatsapp-dispatch). Canonical `[id]` (committed comms
  routes read params.id; newer dirs were deviations).
- Both newer routes moved under `[id]/` byte-for-byte (other agent's
  uncommitted push-event edit travels intact); 2-line params-key adaptation
  each; one forced test import updated in `ntf-push-routes.test.ts`; stale
  generated `apps/web/.next/types/` deleted.
- Verified: vitest 140/140 (3 files) · web `tsc --noEmit` exit 0 ·
  `next dev` boot `✓ Ready in 4.1s`, no route error.
- Report: `docs/evidence/v2/parallel-media-pay-route-conflict-fix.md`.
  NOTE for commits: route moves + one test import touch tests and code —
  mixed commit needs `spec:` prefix, or the test line rides the spec: test
  commit and the moves ride feat.

## SQL visible RED author round 1 (2026-10-04)

- `supabase/tests/79_purchase_requests.sql` extended: plan(154) → **plan(203)**
  (+49 assertions, 136+/5−), sha256 `261f18d183eee6dc…9ded9`.
- Pinned: member-actor finalization into published payment_proof namespace
  (one audit, ETags, replay-false); registration refusals (P0002/22023 matrix);
  finalization refusals (42501 non-creator/staff/foreign, 22023 mismatch);
  supersession tombstones only the unconfirmed loser, winner finalizable,
  tombstoned candidate `GL086:media_not_ready`; GL126 cap (11th refuses);
  cancelled-request liveness `GL066` (linkage pinned behaviorally, no column
  name assumed); RPC surface pin 11 → 13.
- Fixture hygiene: member 32/35 used (member 31's daily cap + desk-queue count
  pin untouched). h79 supplements flagged as holdout-author work (never opened).
- RED unexecuted by design: Cloud SQL primary-owned; CI/primary preview proves.
- Re-obtain SQL cases requested (round 2 of this author) — capability-gate
  amendment cases for the owner's decision 3; migration implementer launches
  after.

## SQL visible RED author round 2 (2026-10-04)

- +13 assertions, plan(203) → **plan(216)**, sha256 `5adeb25c7efba5de…44a40`.
- Re-obtain pinned per owner decision 3: member+verifier obtain on `recorded`
  (member also on `mismatch_recorded`), payload pins (own request id, exact
  proof-asset path, ≤60s, zero keys/ETags), one shared external refusal for
  trainer/preview/unknown, cancelled-without-binding still refused. Expired =
  clock seam, holdout-owned. All RED until the migration patch + CI preview.
- SQL implementer launched (migration patch: finalizer member amendment,
  linkage verification, capability-gate re-obtain; static local checks only).

## Native picker implementer round (2026-10-04)

- **All green**: picker test file 7/7; both-files run 10/10; mobile `tsc
  --noEmit` exit 0; ESLint exit 0.
- New `apps/mobile/lib/proof-upload.ts` (sha256-16 `030bbb8e4097fcae`): native
  adapter mirroring web `uploadPaymentProof` protocol (declared mime/bytes,
  proof-upload-url, byte-exact read-back check, staging PUT, proof-confirm,
  refusal mapping, honest "Pending verification").
- `apps/mobile/app/(member)/buy.tsx` (sha256-16 `ea390a99035c2b90`): offline
  guard BEFORE picker; lazy `import('expo-image-picker')` (static import
  crashed sibling screen test via expo `__DEV__` global — tests untouchable);
  library pick images-only single; cancelled = zero network calls; `onPress`
  returns the promise (was fire-and-forget).
- Gap found: mobile rows lack `acceptedRevision` in read model — honest
  server-side refusal when absent, no fake success. Passthrough round launched
  (shared row schema + mobile mapper, canonical web mapper reference).
  Registry proposals: `uploadProofImage`, `apps/mobile/lib/proof-upload.ts`.

## Read-model passthrough round (2026-10-04)

- Mobile confirm dead-end closed: shared `purchaseRequestRowSchema` gains
  optional `acceptedRevision` (server `pay_request_json` already emits it —
  nothing invented); mobile `UploadRow` widened for
  `exactOptionalPropertyTypes`; confirm passes it through; honest refusal when
  absent.
- Verified: 4 files / **54 passed (54)**; mobile + shared `tsc --noEmit` exit 0;
  ESLint exit 0. Hashes: purchase.ts `22df42d99f7ae565`, buy.tsx
  `f4bc24ad13f29f03`, proof-upload.ts unchanged `030bbb8e4097fcae`.
- Honest limit: rows carry the field only when the mobile parse of
  `pay_request_json` succeeds for the whole row; broader row-shape integration
  noted for primary.

## Final verification + SQL critic (2026-10-04)

- Focused suites (8 files, includes wording fix): **221/221 GREEN** — zero
  failures campaign-wide in the focused visible set.
- Holdout local re-run: media-edge-held + media-confirm-uuid-held PASS;
  media-proof-held 24 failed / 81 passed — diagnosis dispatched to a
  fresh-context agent (contract-level output only; fork inheritance would leak
  held content — disclosed model deviation, necessity-driven).
- Workspace typecheck: **5/5 packages green** (route fix unblocked web).
- `check-escape-hatches`: GREEN (938 files). `dep cruise`: GREEN. `jscpd`:
  **0 clones**. `registry-lint`: GREEN after (a) registry path updates for the
  two moved notification routes, (b) 4 PAY proof exports registered
  (`uploadPaymentProof`, `uploadProofImage`, `PickedProofImage`,
  `ProofUploadResult` — one row, media-upload/proof-upload).
- `git index` repaired for the moved route paths (staged adds/deletes/renames
  only) — gates read `ls-files --cached`.
- **knip RED — borrowed, pre-existing, out of scope**: 12 unresolved imports
  ALL from untracked `scratchpad/quarantined-native-*` files (mtime 2026-10-03,
  before this session) whose imports (identity/session/mobile-context/…)
  exist but sit outside every knip workspace glob. Not PAY work; knip ignore
  forbidden without sign-off; primary/identity agent owns the repair.
- HEAD moved to `f85b22b7` (primary: freeze holdout helper repairs — other
  area). PAY work still uncommitted.
- SQL critic on the migration patch: **GO-WITH-FIXES** (static, 8/8 critical
  checks PASS, Edge seam verified exact). MED: finalizer member path lacks
  member-status re-proof (cancelled/blocked member passes actor lock) —
  status pin dispatched to SQL test author; conjunct + advisory-lock round
  follows. LOW: no request-scoped serialization on registration (harmless);
  LOW: dead `purl` helper.

## SQL test author round 3 (2026-10-04)

- Member-status re-proof pinned: plan(216) → **plan(226)**, +10 assertions
  (active positive control; cancelled/blocked/erased creator each `like 42501`,
  isolated on separate requests so supersession pins can't perturb fixtures;
  member-35 counts stay inside BUY-018 caps). Dead `pg_temp.purl` helper
  removed. Suite sha256 `5f7ec3e3b867766e…d1e02a`.
- SQL implementer round 2 dispatched: member-status conjunct at the actor gate
  (before asset/liveness, mirroring staff is_active), request-scoped advisory
  lock for registration supersession (never delete uncertain winner),
  self-check vs plan(226).

## SQL implementer round 2 (2026-10-04)

- MED closed: member-status conjunct (`status='active' and erased_at is null`)
  at the finalizer's member `for update` gate, before asset/liveness, mirroring
  staff `is_active`; replay-before-liveness untouched.
- LOW closed without new code: `register_payment_proof` already takes a
  request-scoped `pg_advisory_xact_lock` before request lookup/caps/sweep/
  insert — the critic's supersession-serialization finding was already
  satisfied by the original bytes; post-lock tombstone flow documented.
- Self-check re-verified vs plan(226); one self-correction recorded (first
  edit dropped `v_member_path:=true`, caught by grep, repaired, body re-read).
- Static: rollback guard 148 files green, $fn$ 70 (even), parens 807/807,
  zero commits. Migration sha256 `46446c5c31680ea0…881a70`. Unexecuted by
  design — primary's Cloud preview + pg_prove + gen types.
- SQL critic closure-verification round dispatched.

## SQL critic closure round — FINAL GO (2026-10-04)

- (a) Conjunct verified at lines 795-796 (member actor gate, before
  asset/liveness; cancelled/blocked/erased refuse 42501 with active controls;
  revocation-before-replay precedence correct).
- (b) Advisory-lock claim TRUE (`pg_advisory_xact_lock` on
  `'purchase-request:'||tenant||':'||request_id` before lookup; caps/sweep/
  insert under it) — critic's LOW was a missed hunk, closed all along.
- (c) plan(226) maps fully; dead helper removal verified.
- (d) Static integrity holds on final sha256 `46446c5c…81a70`.
- **FINAL VERDICT: GO** (static review; RED→GREEN proof = primary's Cloud
  preview + pg_prove of plan(226), then ADR-177 types follow-up).
- Remaining before commits: holdout failure diagnosis (fresh-context agent,
  running).

## Holdout diagnosis (2026-10-04, fresh-context agent)

- Run: 24 failed / 81 passed (105); all 24 in `media-proof-held.test.ts`
  (media-edge-held + media-confirm-uuid-held pass fully).
- **Class A = 2** (real Edge gap): proofUrl did the trusted asset read before
  tenant/kind/ownership checks — foreign/superseded ids cost a privileged read
  before the (correct) refusal. Source implementer dispatched: linkage
  enforcement from the caller-JWT request read alone, before any privileged
  read, reusing proofExposure's bound-and-live check.
- **Class B = 0**; SQL RPCs stay Cloud-pgTAP-covered.
- **Class C = 22** (six holdout fixture defects, author-owned repairs
  dispatched: mock read-value comparison, copy handler not recording the
  published object, request-truth payload shape vs frozen camelCase
  projection).
- **Spec tension flagged for owner (not silently fixed):** confirm-side
  zero-privileged-read demand for foreign/unknown ids is unachievable in the
  frozen first-upload flow (registration links request on the asset row;
  request pointer set only at attach, post-confirm). Holdout fixture amended
  to pin the achievable contract; owner adjudicates the strict reading.

## Source implementer round 5 — Class A closed (2026-10-04)

- `proofExposure` takes the admissible status set: `proofUrl` requires served
  statuses (owner decision: owner_accepted/payment_proof_uploaded/recorded/
  mismatch_recorded — bound proof stays viewable on its recorded request) and
  refuses on the caller-JWT read ALONE, before any privileged metadata read;
  `proofConfirm` keeps the live-status set. activeProofAssetId binding
  preserved (row carrying linkage must carry an admissible status).
- Requested/rejected/cancelled/expired, RLS-empty foreign callers, unexposed
  targets: all refuse before the privileged read.
- Focused set 17 files: **310/310, zero failures** (includes owner-decision
  cases + adjudicated surface test). Deno + shared/web typecheck clean.
- New Edge sha256 `67223b2f1d467507…4a8d1b`. No commits; holdout untouched.

## Holdout fixture repairs + remaining source gaps (2026-10-04)

- Holdout author repaired six fixture defects (mock filter comparison, copy
  handler published-object record, safe projection row, frozen camelCase
  `{requests:[…]]}` projection with `activeProofAssetId`, `{imageUrl}` sign
  envelope with ≤60s expiry, confirm-side case amended to the achievable
  contract with the tension recorded). Confirm-side disposition 4-pack removed
  with rationale (DB/attach-layer guarantee, not Edge-achievable; re-confirm of
  confirmed asset is lawful replay).
- Post-repair run: **3 failed / 98 passed (101)** (media-edge-held +
  media-confirm-uuid-held fully green).
- Remaining 3 routed: (1)+(2) unknown/superseded proof-url — round-5 linkage
  enforcement verification requested (may already close; concurrent runs);
  (3) NEW real gap: `staff-url` signs a confirmed payment_proof — kind gating
  missing, contract requirement ("do not broaden existing public catalogue
  signer / staff photo readers"; outcome 3) dispatched to source implementer.
  Holdout file sha256 `efe987d2…021e99`; receipt `00041700…0a9db`.

## Source implementer round 6 (2026-10-04)

- **Photo-boundary kind gate closed**: confirm/staff-url branch refuses
  `payment_proof` at the caller-scoped safe read, BEFORE the privileged read —
  proof objects can never be signed through staff-url nor finalized through
  photo confirm (standard `asset_not_found`).
- **Strict proof-url linkage closed (round-5 residual)**: round-5's "some
  served row" fallback let superseded/unlinked ids reach the privileged read +
  signature. Now `requireBound`: caller read must contain a row with
  `activeProofAssetId === assetId` at a served status; no fallback. Both read
  RPCs project `activeProofAssetId` via `app.pay_request_json`; frozen attach
  flow always sets it pre-proof-url.
- Focused set: **304/310** — the 6 proof-url success cases fail 404-vs-200
  solely on fixture omission (`proofDetail()` lacks `activeProofAssetId`);
  one-line amendment dispatched to the visible test author. Refusal cases
  green; Deno clean.
- New Edge sha256 `cfb585a5aeb6d6f1…34832`.
