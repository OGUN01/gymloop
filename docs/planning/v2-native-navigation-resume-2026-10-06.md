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

- Contract commit **f0622e55**: spec: freeze member navigation and Classes discovery contract. Strict OpenSpec validation passed. Thirteen plan/spec/reference files committed. No application implementation or Classes migration has been written yet.
- Main baseline was **e3ee8e1e**, also remote main, from another session's DB test fix. Shared workspace contains unrelated work: tracked docs/evidence/v2/parallel-media-pay-progress.md and many untracked historical artifacts. Never stage all or undo them.
- Existing focused native baseline: three files, 22 tests passed. It covered old navigation/Shop behavior, not the new contract. New independent tests are being authored and have not yet been committed.
- DB workflow **37409145394** at e3ee8e1e remains in progress: migrate/schema-drift/rollback passed, full pgTAP running. Do not run a competing local Cloud sweep or push another migration while this run is active. Previous runs failed and took roughly 110–124 minutes; full green is not yet proven.
- Historical backfill cannot be proven simply by post-migration pgTAP fixtures. Authors cover new defaults and later owner choices; deployment preflight/postflight and independent migration review must provide historical qualification evidence. Do not expose a privileged backfill API just for tests.
- Device serial **INPZT8DQPJROKFXC**, OnePlus DN2101, connected/USB powered, battery 48% at last check. Both in.fitcruxx.v2check and in.fitcruxx.app are installed. Latest exploratory capture was black because screen was asleep; it is not acceptance proof. Existing before-UI screenshots from earlier analysis are under docs/evidence/screens/2026-10-06-device-*.

## Parallel agent ownership

The runtime currently allows four active agents total (root plus three). Use all four safely and replace finished authors with builders/critics rather than lose test independence.

| Agent | Responsibility / state |
| --- | --- |
| /root | Contract and handoff, native UI implementer, serial staging/commits/push/device/gates; never writes tests or reads holdout |
| /root/native_nav_test_author | Implementation-blind native visible author. Written navigation (18), visibility lifetime (13), Home/context (18) groups; Shop harness and Classes group in progress. Owns apps/mobile/**/__tests__ only |
| /root/class_discovery_visible_author | Independent DB/shared/API visible author; new rollback-wrapped visible SQL and strict client/API tests in progress; no migration reads or Cloud sweeps |
| /root/class_discovery_holdout_author | Independent holdout SQL author; contents private. Report only path/count/general coverage/readiness; no visible or implementation reads |

Read-only classes_plan_review and buyer_readiness_review finished without edits. The owner interruption interrupted the three active authors; root resumed them with followup_task. Agent names only work within this live chat; in a new chat inspect status, preserve existing files, and reconstruct these independent roles with fresh agents as needed.

## Immediate next steps

1. Finish and commit ready red test groups separately from implementation; do not let root or a builder edit test files. For amendments to old expected IA, the approved spec author records why and root uses spec: test commit. Preserve public declarations at f0622e55.
2. Root builds native nav/context/Home/Shop after its tests are committed. As slots free, use a separate Classes-boundary implementer for SQL/shared/API/owner settings and a native hook/Classes implementer if needed, with disjoint ownership and registry/constant appends coordinated by root.
3. No source fan-out before the relevant tests/public contract are fixed. Obtain fresh-context security and visual critics separately from builders.
4. Wait previous DB CI before migration landing; CI applies it. Generate packages/db/types/database.ts via Supabase CLI only after apply. Integrate new typed reads and member visibility only when available; do not fabricate types or hide errors as Off.
5. Run relevant gates, safe C:/gc build, exact-artifact device journeys and fresh screenshots. Push coherent green units on main, verify CI, archive only completed OpenSpec requirements and update this handoff.

## Non-negotiable safety and release boundaries

- Never Supabase MCP. CLI project **pecxrpskmfeuyzngvewq** only. No manual migration apply, db reset/start, schema branching or hand-edited generated types. Register every new export, numbers in constants.ts, process.env app reads only env.ts, no lint/knip escape hatches.
- No payment/collection, class eligibility or lib/member-freeze-requests.ts logic changes. D1/D3/D5 belong to designated implementing work; moving Buy does not create purchase requests. D2 first-launch prompt expectation conflicts with explicit **You → Enable notifications** NTF-016; verify enable/receipt/tap, never add launch prompt. D4 GST PDFs are separately deferred; current exports are CSV.
- C:/gc is detached at **e7414c73**, with dirty apps/mobile/android/app/build.gradle and pnpm-workspace.yaml plus untracked .p store. The previous upload left applicationId **in.fitcruxx.app**, versionCode5 and release signing. Preserve those local deltas before updating checkout; switch build to **in.fitcruxx.v2check** with local debug signing. Inspect before installation. Never overwrite/uninstall any Play-signed build.
- C:/gc workspace settings: virtualStoreDir .p, virtualStoreDirMaxLength24. Root-path CMake fails; subst fails. Rebuild JS with app:createBundleReleaseJsAndAssets --rerun so shared edits are bundled.
- EXPO_PUBLIC_* mapping comes from root .env.local public vars; API/web current canonical origin **https://fitcruxx.vercel.app**, not obsolete gymloop-phi origin in old recipe. Password is literal-quoted; strip quotes in memory. Never print or include secrets in tools/logs. ADB secrets through pushed temp file read on device, verify focused Password field, delete temp safely.
- No Play Console upload. vc5 remains in Google review; vc6 is another owner decision. General-sale readiness is not proven by a UI release candidate or pilot gate exceptions.

## Completion evidence

Four- and five-tab member bars, On-empty timetable, mixed activities/own commitments, contextual Buy/renewal/Freeze/Training, redesigned Home/Shop, clean desk, large text/keyboard, required local gates and green push CI, fresh device screenshots and archived current specs. Mark only verified tasks complete. The active goal stays active until the whole accepted objective is achieved or the user explicitly pauses it.
