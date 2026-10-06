# Resume FitCruxx v2 native navigation — 2026-10-06

This is the durable handoff for compaction or a new chat. Read the current repository status and this file before continuing; do not restart the design discussion or repeat already authorized approvals. Update this handoff as work lands. The local Codex goal is active for the current chat, but a new chat must recover the objective from this repository file.

## Objective and authority

Complete openspec/changes/v2-native-navigation on **main**, with independent tests first, maximum safe parallel agents, fresh critics, required gates/green CI, and fresh OnePlus evidence. The owner approved the visual direction and behavioral plan in the 2026-10-06 conversation, subsequently approved the narrow Classes migration, requested implementation today, and explicitly requested maximum parallel agents and a persistent goal/handoff. Goal created on 2026-10-06 in chat 01a10f2e-a0f3-7db1-add6-fe2ce45a22ff; no token budget.

The first board is the approved visual bar: [orange reference](../design/v2-nav-shop-home-orange-reference-2026-10-06.png). Its bell/banner and Shop freeze location were superseded by the written choices below. The second black-number board is historical and is not the color reference.

## Read in order

1. [Device findings](v2-device-testing-findings.md), then [build handoff](v2-device-testing-handoff.md). These document the previous artifact; this UI task's authorization supersedes that testing-only handoff's no-code/no-push rules.
2. [Accepted plan and edge cases](v2-classes-and-navigation-plan-2026-10-06.md).
3. openspec/changes/v2-native-navigation/proposal.md, both specs, design.md **frozen public declarations**, and tasks.md.
4. [Buyer readiness and corrected defect classification](v2-buyer-readiness-2026-10-06.md), [future database validation plan](v2-database-validation-plan-2026-10-06.md).
5. Registry, architecture, domain rules, roadmap, decisions and gates relevant to the file being worked on. Never read holdout files as an implementer.

## Accepted behavior

- Member tabs On: **Home, Classes, Shop, You, Activity**. Off: Home, Shop, You, Activity. Classes is an owner/manager saved discovery switch, independent of business type/date/capacity. Off preserves all services, sessions, bookings and cancellation paths; My classes and Training remain in the business hub. New tenant default Off; one-time backfill On for active service or booked scheduled session ending after one captured migration clock.
- Mixed activity names come from existing services, not a new enum. Gym/Yoga/Dance/Zumba can coexist. Existing booking/membership/branch eligibility remains authoritative; no service entitlements, class credits, permanent cohorts or family accounts in this scope.
- Separate member-only boolean visibility read, canonical owner/manager audited setter/direct-field guard, and caller-owned upcoming/in-progress booking read preserving commitments after branch/service configuration changes. No other member's identity or booking; absolute server-time 28-day horizon.
- All Buy/Freeze/business hub/full announcement/desk Training routes are explicitly non-primary. Buy from Shop and renewal; Freeze next to membership in the hub; trainer native Training through More with existing role guards. Desk maximum five tabs.
- Shop Products with saved categories and honest images/placeholders, Plans, Services, purchase access, then reservations. Three rows initially, five more per explicit tap; expose hidden active count. This is rendered disclosure of the existing response; true database pagination remains separate.
- Home **no bell**: one compact **Messages for you** preview near membership; shared From your gym/studio/academy below Last visit, maximum two previews, separate View all route. Preserve announcement read/version/consent/cache behavior.
- Keep actual existing Chalkline tokens. Brief colors differ from code; do not recolor palette. Use existing primaryAction for prominent numbers/prices. Cheap Freeze copy/friendly display dates/keyboard fixes may change presentation only; preserve ISO command payload and freeze hook.

## State at latest update

**Latest checkpoint: 2026-10-06 10:40 IST.** Source implementation is committed locally at **a4d1481f**; no push yet. Full mobile visible **697/697**, web **4,496/4,496**, shared **1,071/1,071** pass. Native integration reviewer gives scoped source GO after four original P2s and the exact-scalar array follow-up. Regression/test-author commits **8d823864** and **1f97a8fb** precede fixes. Strict OpenSpec1.14.1 passes after semantically equivalent requirement shortening. Independent held fixture/IA amendments are committed **5d1db4d2**, focused **135/135**. The subsequent full root diagnostic run passed **4,761/4,763**, with two explicit20-second timeouts in an unchanged HARD-004 campaign held suite while the native build ran; isolated re-verification is pending. The earlier unchanged50,000-pair fixture exceeds Windows' default test budget but passes all16 assertions with a diagnostic30-second budget. Original default FAIL remains recorded; baseline Ubuntu CI37409128878 passed. See docs/evidence/v2/nav-discovery-review-2026-10-06.md for truthful gate details.

The separate native_nav_holdout_contract_author finished only three old held native suites, standard interface/approved-IA amendments, no visible/production reads. Root never opens held contents. Generated DB types remain untouched. Do not stage the unrelated parallel-media-pay-progress.md. All implementation files are saved and committed; repository handoff, not agent names alone, is the recovery authority.

**Protected C:/gc backup complete:** C:/Users/Harsh/AppData/Local/fitcruxx-nav-build-backups/gc-native-nav-20261006-101908-ffaa61120d8348f8af12c5ce757b959b. Owner-only ACL and all five files verified. Byte-identical Gradle SHA256 B5FFE8A3895B54AA128D06F112F11F5C265AE1406A77A40D676F924F2F33E08C; workspace26EF584A332D6250538310B436C021EE8C2FC3DE75980CC72F6135BDD627A401. Diff patch/head/manifest protected there. The two backed-up paths were restored only after re-verification, checkout safely detached at **a4d1481f**, workspace .p/maxLength24 reapplied, frozen dependency install passed. Direct Gradle forced-JS-bundle plus assembleRelease is running from05:04:37UTC; no installation. Native Gradle targets v2check/debug signing; direct Gradle avoids Expo prebuild overwriting that identity. Require APK debug certificate SHA256 fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c before install. Installed pilot vc4/signature95b8e126, test vc1/signature51ed3f60. Fresh awake before screenshots prove old seven-tab/reservation-first defect; not new-build acceptance.

- Contract commit **f0622e55**: spec: freeze member navigation and Classes discovery contract. Strict OpenSpec validation passed. Thirteen plan/spec/reference files committed. Durable handoff and AGENTS pointer committed at **0b8d9ada**. Active goal created; owner explicitly authorized maximum parallel agents.
- Independent native tests are committed first: **a19c2608**, **af83e505**, **2ce8a4fc** cover navigation/lifetime/Home/Shop/Classes/Freeze (79 new cases). Independent baseline/browser-harness amendments committed **77fa342a** preserve cancellation/refusal/lifetime assertions. Follow-up regression commits8d823864/1f97a8fb precede repairs. Full697/697 mobile result supersedes earlier focused runs.
- Database visible tests **7a62b514**: 115 SQL assertions, 69 shared and32 API cases; independent private holdout **8d36b9ed**: 141 assertions, never read by implementers. Owner26 tests committed **ca64852** before editor construction; the independent browser/type harness amendment is in77fa342a. Shared new/existing147 and owner/API/readers62 pass. No new SQL has been executed on Cloud.
- Additive SQL, strict API, owner editor/read and shared/native wrappers are committed at a4d1481f. Fresh **class_discovery_final_blind_critic** gave scoped static GO, no P1/P2, having read no tests, progress notes or runtime state. Earlier advisory critic had an accidental visible search leak and is not the required blind sign-off. Generated DB metadata is intentionally still old until CI applies this migration; type checks currently have six expected new-column/RPC errors, never hand-fixed. Expo completed local announcements route generation and was stopped.
- Main baseline was **e3ee8e1e**, also remote main, from another session's DB test fix. Shared workspace contains unrelated work: tracked docs/evidence/v2/parallel-media-pay-progress.md and many untracked historical artifacts. Never stage all or undo them.
- Native Classes/cache builder finished refresh, exact-scalar and stable-navigator repairs; integration reviewer returned scoped GO. Local gate runner is isolating unrelated campaign timeouts after the build. Static review is not device/runtime acceptance; compact reference matching and final visual critic await real screenshots.
- DB workflow **37409145394** at e3ee8e1e remains in progress: migrate/schema-drift/rollback passed, full pgTAP running. Do not run a competing local Cloud sweep or push another migration while this run is active. Previous runs failed and took roughly 110–124 minutes; full green is not yet proven.
- Historical backfill cannot be proven simply by post-migration pgTAP fixtures. Authors cover new defaults and later owner choices; deployment preflight/postflight and independent migration review must provide historical qualification evidence. Do not expose a privileged backfill API just for tests.
- Device serial **INPZT8DQPJROKFXC**, OnePlus DN2101, connected/USB powered, battery48% at last check. Both in.fitcruxx.v2check and in.fitcruxx.app are installed. The screen was woken and fresh old-artifact Home/Shop captures are committed in06af7df0. New-build acceptance is still pending.

## Parallel agent ownership

The runtime currently allows four active agents total (root plus three). Use all four safely and replace finished authors with builders/critics rather than lose test independence.

| Agent | Responsibility / state |
| --- | --- |
| /root | Contract and handoff, native UI implementer, serial staging/commits/push/device/gates; never writes tests or reads holdout |
| /root/native_nav_test_author | Finished implementation-blind native tests and independent baseline/browser/type amendments; root never edited any test |
| /root/class_discovery_visible_author | Finished independent DB/shared/API/owner visible tests; no migration reads or Cloud sweeps |
| /root/class_discovery_holdout_author | Completed private supabase/tests-holdout/163_member_class_discovery_holdout.sql, 141 assertions, rollback/plan count checked; Cloud unexecuted |
| /root/class_discovery_builder | Finished SQL/shared/API/owner settings; focused62/62 and shared147/147 pass. No holdout access or manual apply |
| /root/native_classes_builder | Finished scoped native visibility/cache/layout and Classes presentation; 50 new focused tests pass |
| /root/native_nav_integration_reviewer | Finished source GO after regression repairs; no holdout/Cloud reads |
| /root/native_nav_gates_runner | Active local tooling/isolated campaign timeout verification; no source edits or Cloud sweep |
| /root/native_nav_device_build_preflight | Active protected C:/gc direct Gradle build at a4d1481f; no install/Cloud/Play actions |
| /root/nav_sql_validation_prepare | Active read-only preparation of focused rollback validation and historical qualification evidence; no SQL execution or test-body reads |
| /root/class_discovery_final_blind_critic | Finished required scoped static blind security GO, no P1/P2; runtime unapplied |

Read-only classes_plan_review and buyer_readiness_review finished without edits. The owner interruption interrupted the three active authors; root resumed them with followup_task. Agent names only work within this live chat; in a new chat inspect status, preserve existing files, and reconstruct these independent roles with fresh agents as needed.

Existing CLS-026 pins statement_timestamp for class time semantics. The own-read absolute 28-day horizon is expressed as 672 hours to preserve DST semantics. Existing class eligibility and command fields remain unchanged.

## Immediate next steps

1. Collect verified C:/gc APK and rerun unchanged campaign suite in isolation after build completion. Preserve original failed Windows runs and public declarations; never edit held tests as an implementer.
2. Wait preceding DB CI before any Cloud replay or another migration push. ADR-042 and the db-migration skill explicitly authorize root-only rollback-DDL validation; use the existing splice/counter procedure and confirm independent visible/held wrappers have only one enclosing transaction end. Obtain historical backfill qualification evidence without a privileged backfill API.
3. Once rollback proof is green, land migration through CI. Generate packages/db/types/database.ts via the authorized CLI only after successful apply; ADR-177 permits the no-migration types follow-up while the full DB suite continues. Do not fabricate types or hide unknown visibility as Off.
4. Verify safe test APK package/debug certificate, install only v2check, inspect compact Home/Shop against the approved first board, and obtain fresh visual review. Refine arrangement using existing tokens and independent regression authors where required; re-bundle/rebuild any new source.
5. Verify exact-artifact OnePlus journeys, required local gates and green main CI, save fresh screenshots, archive completed OpenSpec requirements and update this handoff. Root serially stages only task files.

## Non-negotiable safety and release boundaries

- Never Supabase MCP. CLI project **pecxrpskmfeuyzngvewq** only. No manual migration apply, db reset/start, schema branching or hand-edited generated types. Register every new export, numbers in constants.ts, process.env app reads only env.ts, no lint/knip escape hatches.
- No payment/collection, class eligibility or lib/member-freeze-requests.ts logic changes. D1/D3/D5 belong to designated implementing work; moving Buy does not create purchase requests. D2 first-launch prompt expectation conflicts with explicit **You → Enable notifications** NTF-016; verify enable/receipt/tap, never add launch prompt. D4 GST PDFs are separately deferred; current exports are CSV.
- C:/gc is now detached at **a4d1481f**; the previous e7414c73 upload deltas are preserved in the verified protected backup above. The current native target is **in.fitcruxx.v2check** with local debug signing and workspace .p/maxLength24. Never force/reset/clean or remove its dependency store. Inspect the fresh artifact before installation. Never overwrite/uninstall any Play-signed build.
- C:/gc workspace settings: virtualStoreDir .p, virtualStoreDirMaxLength24. Root-path CMake fails; subst fails. Rebuild JS with app:createBundleReleaseJsAndAssets --rerun so shared edits are bundled.
- EXPO_PUBLIC_* mapping comes from root .env.local public vars; API/web current canonical origin **https://fitcruxx.vercel.app**, not obsolete gymloop-phi origin in old recipe. Password is literal-quoted; strip quotes in memory. Never print or include secrets in tools/logs. ADB secrets through pushed temp file read on device, verify focused Password field, delete temp safely.
- No Play Console upload. vc5 remains in Google review; vc6 is another owner decision. General-sale readiness is not proven by a UI release candidate or pilot gate exceptions.

## Completion evidence

Four- and five-tab member bars, On-empty timetable, mixed activities/own commitments, contextual Buy/renewal/Freeze/Training, redesigned Home/Shop, clean desk, large text/keyboard, required local gates and green push CI, fresh device screenshots and archived current specs. Mark only verified tasks complete. The active goal stays active until the whole accepted objective is achieved or the user explicitly pauses it.
