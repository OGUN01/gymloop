# V2 campaign handoff — 2026-10-02 (batch 1 in progress)

Read this, then `docs/planning/v2-feature-map.md`, `docs/planning/v2-campaign-goal.md`, `AGENTS.md`, ADR-176 and ADR-177
in `docs/decisions.md`. **Nothing has been pushed or permanently migrated.** The
current checkpoint below supersedes the historical session-1 snapshot.

## Current checkpoint

- Initial defects are repaired in separate `spec:` commits, including the missing
  h68 holdout, suite-68/meta/catalogue fixtures and independent legacy holdouts.
- Both migrations passed the full serialized Cloud rollback splice sweep:
  **107 files / 8,934 assertions / zero failures**, with every literal plan satisfied.
  No SQL changed after this sweep. Core SQL and the narrow INV-028 history reader
  received independent static GO reviews.
- Owner-approved INV v1.4 adds pre-Google consent, safe same-account reopening and
  direct account recovery. Independent tests preceded separate implementers.
  Web/API/Team received a fresh static GO. DB/shared implementation is committed
  as `205a7ca`; web/Team implementation is committed as `4cf799a`.
- Native optional-cache failure fixes are verified. Latest auth ordering/sign-out
  repairs follow separate red checkpoints `61ab87d` and `9bfb1e6`; all **132 native
  unit checks**, **6 new held ordering checks** and **31 held recovery/cache checks**
  passed. Further independent reviews found cross-client shared-cache and durable
  Auth-write ordering gaps. The shared-cache repair passes all 41 affected held
  checks; durable Auth tests are committed red as `450d2ec` before implementation.
  The third identity finding was escalated; the existing cleanup bar is retained.
  The durable-write repair passed 137 native unit and 46 affected held checks.
  A blind review then found late SDK refresh/PKCE responses restoring Auth after
  logout. Independent actual-SDK tests were confirmed red and committed as
  `9606490`. The focused public SDK-lock repair passed all 26 affected held checks
  and received fresh static GO; native implementation is committed as `b01f331`.
  Font acceptance is complete below; deployed invite journeys and final Android
  runtime acceptance remain pending.
- The owner approved `openspec/changes/member-invites/google-brand-amendment.md`.
  INV v1.5 is frozen (`8d843c2`, platform I/O clarification `8c53737`). Independent
  font tests preceded implementation `b176b06`. Fresh source and visual R10 critics
  returned GO; all five real-browser font/theme/200% text/network-recovery cases
  passed. Web units 2,724, shared 545, native broad sweep 141 plus two focused
  stroke cases and script/held 2,526 checks are green. SQL remains unchanged.
- Production invite origin is verified as `https://fitcruxx.vercel.app/`.
  Generated invite types must follow CI migration under ADR-177; no hand edits.
- Registry/docs are updated in the working tree. Final gates, deployed browser
  journeys, Android runtime evidence, archive and every CI gate remain required.
  A separate `in.fitcruxx.v2check` debug build succeeded and is installed alongside
  the Play release. Device runtime checks are pending; this is not release evidence.
- Owner deferred USB/device testing to the end of all v2 because another agent
  is using the phone. Do not touch ADB/the device meanwhile; use web/mobile
  viewport checks, preserving final Android acceptance as an open requirement.
- Batch 2 decisions have not been applied. Resume its seven contract amendments
  after batch 1 is pushed, then carry batch 2, Waves C/D and versionCode 5 onward.
  Preserve the original full-v2 objective and the independent roles.

Detailed evidence and limits: `docs/evidence/v2/ledger.md`. Minimize usage through
focused briefs and affected checks; retain independent authors and fresh critics.

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
