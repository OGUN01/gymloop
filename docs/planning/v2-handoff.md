# V2 campaign handoff — 2026-10-03 (batch 2 applied; application builds)

Read this, then `docs/planning/v2-feature-map.md`, `docs/planning/v2-campaign-goal.md`, `AGENTS.md`, ADR-176 and ADR-177
in `docs/decisions.md`. **Batch 1 is pushed and CI applied its migrations.** The
current checkpoint below supersedes the historical session-1 snapshot.

## Current checkpoint

- Batch 1 defects, independent tests, implementations and migration/type pushes
  are complete. Full rollback proof: **107 files / 8,934 assertions / zero failures**
  with exact plans. CI 37011785563 is green; DB 37009955982 is wholly green and
  resolves historical pre-types drift. Normal committed baselines pass web
  92 suites/2,724 tests, native 14 files/143 tests and shared 545 tests.
- Real deployed role/navigation checks passed 5/5, including owner-only Team.
  Genuine Google invite/recovery journeys, final Android runtime acceptance and
  archive remain open; do not present role navigation as invitation redemption.
- Owner deferred every USB/device interaction until final v2 testing because
  another agent uses the phone. Do not use ADB/Metro or change that agent's build;
  continue web/mobile viewport work. The owner tests nothing until all v2 is built.
- The CI-only vocabulary prelude is applied. DB 37021183243 passed migrate,
  full pgTAP and seed; its historical pre-types drift is resolved by CLI-generated
  follow-up ccc62e4 / DB **37022798758 (all jobs green)**. Related CI/held/immutability
  runs passed. The later business/type pushes are recorded below.
- Seven batch-2 contracts, separate SQL authors and central catalogue tests are
  committed first. All eight sources are committed separately as 2ef398c; ANC's
  exact platform-policy reconciliation is complete. CI has applied all eight
  business migrations from push b2a331f. PTF's canonical preview clarification 1feffcf received fresh
  GO; separate visible356/held381 tests preceded the isolated source correction.
  Both suites now pass. Fresh blind PTF and Shop source critics returned static
  GO; those reviews do not establish real races, publication or screen quality.
- Focused runtime passes include GRD visible311/held293, BIZ visible61/held71,
  PLC visible32/held30, ANC visible157/held88, CLS notice42/held46, PTF visible356/
  held381, and Shop visible211/held276. Classes held221 now passes genuine member
  check-in parity through the canonical token-proof RPC, with normal guards.
  Classes visible710 now passes after its independent author corrected eight
  six-argument fixture calls in 8afa142. Existing seed/scenarios also passed a
  rollback preview with eight draft migrations. Canonical full sweep r18 pinned
  2897658: 123 files, 119 green, three one-assertion legacy holdout failures and
  one guardian fixture abort after India midnight. Independent repairs preserved
  the legacy role matrix, added the exact approved table/helper inventories, and
  used actual gym-local tomorrow for the future-DOB refusal. Canonical retry r20
  pinned a5b4225: all four repaired suites green, 1,415/1,415 assertions. All eight
  migration hashes match r18. These earlier partial receipts are superseded by
  the final all-green r27 below. Cloud testing is serialized and forbidden
  during any DB workflow.
- Owner approved explicit rejection of class `24:00` and announcement audiences
  using status plus inclusive gym-local membership dates. Freeze a16ae30 preceded
  four independent new SQL suites and isolated source repairs. Canonical r23
  passed 398/398. A fresh source critic then found the approved malformed-timezone
  fallback missing from shared `app.gym_today`; independent tests preserved the
  normal invalid-write guard and used a bounded rollback-only legacy fixture,
  with the exact commercial trigger restored before every application check.
  Tests bf9e3fc preceded the final verification: canonical r26 passed all six
  affected suites, **1,057/1,057** assertions. Fresh blind final source review
  returned GO; bytes outside the six changed routines match their predecessors.
  This is source/SQL proof only. The complete canonical sweep r27, pinned
  bf9e3fc and all eight migration hashes, passed **127/127 files, 12,679/12,679
  assertions, zero failures**. Existing seed/scenarios passed final rollback r2
  against those same eight migration bytes. Machine receipt:
  docs/evidence/v2/batch2-canonical-r27.json. Local rollback (127 files),
  immutability (74 commits), registry and escape gates passed. Source push b2a331f
  triggered DB 37061065081: migrate passed, full pgTAP remains running, and the
  historical pre-generation drift failed as expected. CLI-generated type-only
  follow-up 89c6cda is pushed under ADR-177; DB 37061577506 awaits the source run.
  Its drift success is still required. CI 37061577452 is now wholly green after
  the permitted one-time failed-job retry. The historical source CI encountered
  a damaged Playwright trace; its result is not the current types-head result.
- Independent BIZ/PLC app acceptance tests are committed red as 64b5820,
  before application source. BIZ source is drafted; a fresh critic requires
  refreshed Settings state, plural vocabulary, request-scoped read consolidation,
  platform exception envelopes and cache-error-safe sign-out. Independent new
  tests precede the fixes. GRD app tests are committed first as 07f2366; its
  drafted source passes 347 focused visible and 114 held cases after an
  independent full-caller fixture repair (eef8f1d). A fresh GRD critic found
  unsafe child-address fallback on failed guardian reads, wrong email-field
  guidance and birthday binding copy; separate regression authors precede fixes.
  These initial findings have focused fixes and regression suites. Subsequent
  fresh reviews still require the guardian birthday-reissue note to use the
  member's own Google email and the platform detail page to survive a rejected
  organization read. Independent regressions precede both corrections.
  SHP/MEDIA app tests are committed red as fca9b84 after independent harness,
  typing and executable coverage repair. MEDIA source passes 129 visible cases;
  separate UUID regression 56e5b12 precedes its canonical-identity repair.
  Current MEDIA holdouts pass 57/57 after independently correcting valid HTTP
  range and UUID fixtures. Fresh final review and live publication remain open.
  Shared BIZ vocabulary foundation 9eb1487 unlocks PLC; full BIZ app source is
  still uncommitted. One legacy BIZ holdout over-pins the projection to exactly
  business_type; independent contract assessment is required before any repair.
  PTF app/held/live suites are committed first as 6491b98: actual missing-target
  RED, scoped lint and strict own-file typing verified. Its backend builder is
  active; native rendered command coverage remains required before UI build.
  CLS/ANC app drafts still need readiness and test-first commits. Builders
  must never read holdout files or the orchestrator's private failure evidence.
- Owner approved the PT final-session exception, then clarified that ANY
  same-tenant/order-payment refund record blocks it (including pending and failed).
  Public boundary and immutable completed_order posture received independent GO;
  original visible308/held315 tests precede the separate implementation. Their actual
  schema-red captures are recorded; the held fixture first needed valid canonical
  membership dates. Partial source was drafted before that actual runtime capture;
  test commits preceded all source edits. Owner also retained expired packs'
  unused balance: total10-used3 with scheduled2 returns remaining7 and scheduled2
  separately, stays unbookable and changes no ledger. Independent tests preceded
  the separate expired-reader correction. Current visible356/held381 include
  the canonical preview proof and pass. Real concurrency, midnight waits and
  screens remain open; no complete PT win is claimed.
- ANC's narrower frozen direct-table policy lists take precedence through the
  exact ADR-184 exception, independently reviewed GO: no platform policy on any
  of its three tables; support-preview remains actor-checked read-only RPC access.
  The corrected central test commit precedes the completed ANC source draft;
  both ANC suites pass their frozen contract, with no notification fan-out or
  platform policy. The later independent date-boundary finding is recorded above;
  ANC targeting is now owner-resolved and independently source-approved as above;
  complete runtime and screen acceptance remain open.
- Shop rollback-only success fixtures use a narrowly bounded order-created default
  seam to model separate command transactions without changing money functions,
  guards or successful rows. Genuine multi-transaction ordinary-RPC reserve,
  fulfil and replay evidence is still mandatory. Independent Shop app tests are
  now commissioned; other app drafts stay uncommitted until the SQL/types staging.
- Owner resolved PLC's contradictory mixed-claim requirement in favor of the
  exact minimal member-policy edit, retaining legacy staff predicates. Public
  freeze b6730b7 received independent GO; visible32 and held30 pass. No mixed
  staff identity validation is claimed or new authorization policy added.
- Exact owner-approved private R2 production-origin PUT CORS is applied and its
  positive/negative preflights verified. Existing four registered R2 values are
  provisioned to repository secrets with independent name/timestamp receipt.
  Edge secret provisioning/deploy, verified immutable publication/current
  exposure and live upload remain pending. No media object was written for CORS.
- Registry/ADRs and guardian privacy inventory are being integrated. Carry app
  red/build/critics/gates forward under ADR-177, then Waves C/D and versionCode 5.
  Prepared Wave C/D drafts are not frozen. PAY stock/mismatch/renewal choices
  and NTF transport/Firebase identity questions remain pending with the owner;
  neither draft authorizes provider setup or implementation. Preserve ALL-v2 scope.

Evidence and limits: `docs/evidence/v2/ledger.md`. Use GPT-6.1 Sol, narrow briefs
and affected checks to minimize weekly usage; keep independent roles/fresh critics.

## Owner standing instructions (follow exactly)

1. Goal: complete **all of v2** (every feature in the feature map), each through the full Gauntlet Loop, with 100% precision.
2. **Latest owner override, 2026-10-02: use GPT-6.1 Sol for every subagent** (`model: "gpt-6.1-sol"`). This supersedes the earlier Sonnet 5.5-only instruction. The session-1 reports and Sonnet references below are historical handoff state, not the current model policy; do not use the old aliases for resumed work.
3. **Batching approved** to go faster: migrations of several features go out in ONE push (one DB run, one types regeneration).
   Batch 1 = INV + STI. Batch 2 = GRD, BIZ, PLC, SHP, PTF, CLS, ANC (Wave A remainder and Wave B run in parallel; owner said so).
   Then Wave C (NTF, PAY, WSP) and Wave D (SLF, TRV, LDC, OCC, RPE), then the release (versionCode 5). Draft contracts early; freeze C/D bars after closed-test feedback unless the owner says go.
4. **The owner tests nothing until everything is built.** After each batch is built the orchestrator verifies it (gates, blind critics, browser pass); at the very end the orchestrator runs a full v2 end-to-end itself (Playwright, browser, Android). Limits: never type the owner's Google password; Google sign-in needs the owner's one real pass; Android needs an emulator/device (check `adb`) or a checklist for the owner.
5. **Owner approved ADR-177:** (a) a types-only push skips the 56-minute pgTAP step (commit `9d05cf5`, already made in `db.yml`); (b) a push with NO migration may follow a migration push as soon as that push's `migrate` job succeeds (~30 s) — a second migration still waits for the whole run.
6. Never use any Supabase MCP server (wrong account). Migrations are applied by CI only. Escalate rather than lower a bar. The Gauntlet's blind arrangement stays (separate authors for visible tests, holdout, implementer, fresh critics; implementers never read `supabase/tests-holdout/`).
7. Owner-gated (do not do without them): opening public Auth signup (`auth-signup.yml` mode `enable-signup`), FCM keys, Meta WhatsApp templates/DLT, R2 bucket CORS, Play Console steps, any legal sign-off.
8. Owner answers already given: **GRD** legacy members — each gym owner attests ONCE (audited) that members with no DOB are adults; **PTF** late cancel consumes one session (per-gym flag, owner waiver; no-show consumes nothing, recorded gap); **PLC** show the stored GST rate, claim neither inclusive nor exclusive; **CLS** frozen memberships are bookable (parity with check-in).

## Where the code is

The remaining sections preserve the session-1 snapshot and its then-open items.
For resumed work, apply the latest standing model override above and verify the
current tree/evidence instead of treating these historical statuses as current.

### Local commits (14, unpushed) — `git log origin/main..HEAD`
Contract + ADR-176 + bar (`f777e3e`), `ci:` ADR-177 (`9d05cf5`), INV tests (visible pgTAP 67 + meta 04 amendments; holdout h67; visible TS ×2; holdout TS), INV amendments v1.1, STI tests (visible TS, holdout TS, visible pgTAP 68), STI amendments v1.1, batch-2 contract drafts + decisions + `splice.py` fix (`9d80e75`), INV suite-67 peek fix (`5852302`).
Contract files: `openspec/changes/member-invites/proposal.md` (INV-001…024 + "Contract amendments v1.1"), `openspec/changes/staff-invites/proposal.md` (STI-001…018 + v1.1), `openspec/changes/v2-batch2-shared/{shared,decisions}.md`, and the seven batch-2 proposals under `openspec/changes/{guardian-minors,business-type,plans-catalogue,shop,pt-front,classes,announcements}/proposal.md`. Quality bar: `docs/design/v2/inv-bar.md`.

### Uncommitted working tree (implementation; commit in coherent units after verifying)
- INV migration `supabase/migrations/20261002100000_member_invites.sql` — passed 440/443 of suite 67; the 3 failures were a test bug, fixed in `5852302` but **not re-run**.
- STI migration `supabase/migrations/20261002110000_staff_invites.sql` — 68 ran 433/433 with 4 failures (all test defects, below).
- INV shared/web/mobile: `packages/shared/src/api/member-invites.ts`, constants + index edits, `apps/web/lib/{api,auth-actions,member-invite-*,member-invites}.ts`, 4 routes under `apps/web/app/api/{member-invites,member-identity}`, `apps/web/app/auth/callback/route.ts`, `apps/web/app/invite/**`, `apps/web/app/google-glyph.tsx`, `apps/web/app/styles/member-invites.css`, `apps/web/app/(console)/members/[memberId]/{page,app-access-panel}.tsx`, `member-form.tsx`, `not-linked/page.tsx`, `(public)/privacy/page.tsx`, `apps/mobile/{lib/invite.ts,app/invite/[token].tsx,app/not-linked.tsx}`. All visible INV TS tests were green (web 2168 tests, mobile 91, shared 540).
- STI shared + routes: `packages/shared/src/api/staff-invites.ts`, `apps/web/lib/staff-invites.ts`, 5 routes under `apps/web/app/api/{staff-members,staff-invites,staff-identity}`, callback staff branch, `startStaffInviteGoogleSignIn`. Visible STI tests for these were green; INV code was generalized to share helpers (jscpd threshold is 0).
- **NOT built:** STI accept pages (`app/staff-invite/**`), sign-in `?linked=staff` notice, Team console (`app/(console)/team/**`) and the owner nav item — the implementer was stopped before writing anything.

## Known defects / open items before the first push (in priority order)

1. **`supabase/tests-holdout/h68_staff_invites_holdout.sql` does not exist.** The STI holdout pgTAP author was stopped before writing it. Relaunch one (Sonnet, blind: reads both proposals only; lowercase `begin;` / exact `select * from finish();`, literal `plan(N)`, fixture prefix `68900000-…`; must not read `supabase/tests/68_*`, `67_*`, `h67_*` or any invite TS test).
2. **Visible suite 68 has 4 defective assertions** (found by the STI migration implementer): #17/#18 (lines ~480–484) assert exactly one policy / only `gym_owner` but the platform-pair rule in `04_contract_meta` requires `staff_invites_platform_select` too; #385 (line ~1694) expects a super admin to read 0 invite rows but platform roles read all; #216 (line ~1011) expects the owner of another gym to be refused, but that owner legitimately creates staff in their own gym. Fix by re-engaging the STI visible DB author (blind rules apply to its replacement), as a `spec:` commit.
3. **Policy names.** `04_contract_meta` and `docs/data-model.md` pin `<table>_tenant_select` + `<table>_platform_select`. INV's migration follows that. STI's migration used `staff_invites_owner_select` → rename to `staff_invites_tenant_select` (contract text already says so).
4. **`04_contract_meta` needs the STI amendments** (separate `spec:` pass after #2): `staff_invites_token_hash_key` unique carve-out, the seven STI definer signatures + volatility, `staff_invites_preview_read_only`, matrix row. INV's amendments are already in.
5. **`supabase/tests/07_catalogue_constraints.sql` fails 3 assertions on Cloud today with NO migration spliced** (date-dependent DQA-005 fixture). CI's pgTAP run would be red regardless of this work. Investigate, and fix the test's date dependence in a `spec:` commit before pushing.
6. **Re-run everything locally before pushing:** splice BOTH migrations (`python scripts/pgtap/splice.py …`, now handles files that open with `begin;`); run all visible files AND the holdout files (`h67`, `h68`, plus all older ones) — the orchestrator runs holdouts and never shows file contents to implementers. Ensure `failures=0` and `ran=plan` per file. Do not run while a DB workflow run is in flight (`gh run list --workflow db.yml`). Serialize Cloud runs between agents with the atomic lock dir `…/scratchpad/cloud-run.lock` (mkdir/rmdir). `scripts/pgtap/sweep.py` also chokes on ~10 older holdout files with uppercase `BEGIN;` — run those individually.
7. **Remaining INV follow-ups:** add `queryParams: { prompt: 'select_account' }` to both invite sign-in starters if tests allow (run member/staff pages tests + phase8 OAuth test; the holdout is run by the orchestrator); replace the local glyph in `apps/web/app/sign-in/page.tsx` with `app/google-glyph.tsx`; the bar's INV-Q9 (invite status on the member list) and INV-Q11 (audit line in member history) are not built — decide after the critic.
8. **Registry + docs:** every new export is unregistered (`registry-lint` fails). Register all symbols (lists are in the implementer reports: shared invite/staff helpers + constants incl. `MEMBER_UNLINK_REASON_LENGTH`, `STAFF_INVITE_*`, web libs, route handlers, `GoogleGlyph`, `switchInviteAccount`, `INVITE_PAGE_METADATA`, `InviteReady/InviteSignedOut/InviteRefusal`, `AppAccessPanel`, mobile `lib/invite.ts` ×5 + `InviteLink`, SQL functions/tables/enums/triggers). Also: INV/STI rows in `docs/domain-rules.md`, `docs/data-model.md` tables, `docs/security.md` retention rows, `docs/runbooks/closed-test-testers.md`, fold into `openspec/specs/identity` + `openspec/specs/mobile` ("no public-code join" amended), v2 ledger `docs/evidence/v2/ledger.md`, archive the OpenSpec changes.
9. **Production hazard:** an unset `WEB_APP_URL` defaults to `http://127.0.0.1:3000`; verify the deployed value before any invite is shared.

## Remaining pipeline for batch 1 (INV + STI)

(1) fix items 1–5; (2) relaunch the STI pages + Team console implementer (brief: contract STI v1.1 + INV pages as base, generalize INV view parts, jscpd = 0, Team nav for `gym_owner` only, tests `staff-invite-pages`, `team-console`, `team-navigation`, e2e nav spec); (3) full local sweep (item 6) → green; (4) `pnpm gates`-style local checks (typecheck, lint, knip, jscpd, depcruise, registry-lint, escape-hatches, vitest all packages, `test:scripts`); (5) commit implementation in coherent commits (`spec:` prefix only where tests and code mix — avoid); (6) parallel fresh blind critics (DB/RLS, API, web UI, mobile, copy/privacy) scoring against the bar `docs/design/v2/inv-bar.md`; fix; (7) push 1 (migrations + tests + `ci:`); when `migrate` succeeds regenerate types with `supabase gen types typescript --linked` and push types + TS (ADR-177), no hand-editing `packages/db/types/database.ts`; (8) wait for `ci.yml` (flaky e2e: re-run once) and the ~56-minute pgTAP run to go green; (9) archive, registry, ledger.

## Batch 2 status

Seven contract drafts are committed (GRD 256 lines, BIZ 367, PLC 311, SHP 311, PTF 276, CLS 358, ANC 400). The orchestrator's decisions and owner answers are in `openspec/changes/v2-batch2-shared/decisions.md` (authoritative). **The patch instructions were sent to the drafters but all were stopped at the start of patching: assume NONE of the decisions has been applied inside the seven proposals.** Next: re-send each drafter its resolution list (or apply by hand): add the booking-primitives migration `20261003085000_booking_primitives.sql` (CLS owns), GRD owner-attestation, BIZ `businessNouns.class`, PLC holdout `h71`, SHP generic `POST /api/member/media-url` + `unique(tenant_id,id)`, PTF drops its trainer-photos route and owns `SegmentedControl`/`ClassesSegments`, ANC holdout `h75`, and replace each "Contract questions" section with "Resolved by the orchestrator". Then commission a bar document `docs/design/v2/<id>-bar.md` per feature (public references only), then blind test authors (visible DB, holdout DB, visible app, holdout app) for GRD, SHP, PTF, CLS; lighter for PLC (visible + h71), ANC (visible + h75), BIZ (visible + holdout for the owner command); a single mechanical `spec:` pass amends shared pinned tests (`01_tenancy_structure`, `31_comms_schema_consent`, `h29_comms_holdout` labels, `04_contract_meta`); implementers; a final member-app IA integration step (tabs Home · Classes · Shop · Activity · You, Gym screen, Classes|Training); then one migration push for batch 2 with the same ADR-177 flow. Migration order: `085000` primitives, `090000` GRD, `100000` BIZ, `110000` PLC, `120000` SHP, `130000` PTF, `140000` CLS, `150000` ANC. SQLSTATE registry: INV/STI GL074–082, GRD 083–085, SHP 086–087, ANC 088, booking 090–096, PTF 097, CLS 110–114.

## Facts worth knowing

- **DB run cost:** `db.yml`'s pgTAP step is ~56 min (101 files, 7,241 assertions, runner CPU ~4 s — network round trips to Mumbai). Other jobs < 30 s. Only pushes touching `supabase/**`, non-type `packages/db/**`, `scripts/check-pgtap-rollback*` or `db.yml` run it.
- **Windows shell:** a bash heredoc containing unmatched quotes/backticks failed once — write long text with the Write tool then `cat >>`. Never `taskkill /F /IM python.exe` (an author did and may have killed other agents' scripts).
- **Test immutability:** a commit touching tests and non-script code needs a `spec:` prefix; the normal flow is separate commits. Test files are immutable to implementers; defects are reported to the orchestrator and fixed by a test author in a `spec:` commit.
- **Seed/demo accounts:** `docs/demo-accounts.md`; demo gym code `IRNBX1`. Deployed web: `https://fitcruxx.vercel.app`. Auth redirect allow-list is exact URLs (no query).
- **Memory:** `C:\Users\Harsh\.claude\projects\C--Users-Harsh-Desktop-gymloop\memory\` (see `feedback-sonnet-only-agents.md`, `gymloop-v2-campaign-state.md`).
