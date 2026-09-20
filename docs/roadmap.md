# Roadmap

## Current experience goal — owner override, 2026-09-18 (ADR-125)

The member v2 minimalist direction is approved; extend the same quality to the
gym-owner console, not only members. Equal light/dark support replaces the
dark-first Iron Pulse proposal. The owner adaptation image is a reviewable
proposal; it does not change metrics, money or identity contracts.

Use `docs/planning/current-campaign-goal.md`,
`docs/planning/phase7-experience-prd.md` and
`docs/planning/phase7-implementation-prompt.md` as the current goal, production
design specification and bounded execution instructions. This owner-requested
planning is allowed before Phase 6 browser closeout; implementation still starts
by finishing that closeout. Neither phase is complete on the strength of images.

`MASTER-BUILD-PROMPT.md` is disposable after Phase 0 (its own §3). Its build order (§12) and its model/effort policy lived only in that file — nowhere else recorded which phase runs on which model, at what effort. This file is that record, so a session starting Phase 3 doesn't have to guess or re-derive it from a prompt that is no longer expected to be read.

## Model and effort policy

**Owner continuation, 2026-09-18 (ADR-131):** usage remained 82% when the
owner authorized up to four additional weekly points to finish Phase 7. The
current hard stop is 86%. Sol xhigh owns implementation; Terra and Luna are
limited to bounded visual/device verification and repetitive presentation work.
No contract, blind-test, device-evidence or archive gate is waived.

**Owner continuation, 2026-09-18 (ADR-130):** after the owner-overview slice
closed at 80% weekly used, the owner revised the continuation allowance to two
points. The absolute ceiling is therefore 82% used. Complete Phase 7 against
the approved v2 references with the existing Sol/Terra/Luna hierarchy, at most
two workers, and no Astra, duplicate exploration, weakened gate or Phase 8 work.
Stop new work at 82% even if a remaining device or contract dependency prevents
the formal Phase 7 completion boundary.

**Owner continuation, 2026-09-18 (ADR-129):** the approved member and owner v2
boards are now the literal end-state references for the full Phase 7 UI/UX,
including compact responsive composition, equal light/dark finish and restrained
motion. The measured start is 78% weekly used and the owner authorizes two more
points, making 80% the absolute ceiling. Sol remains orchestrator/arbitrator,
Terra owns visual/browser defect discovery and complex interaction corrections,
and Luna owns small route-complete implementations, with at most two workers.
No Astra, weakened gate or simulated visual evidence is authorized.

**Owner continuation, 2026-09-18 (ADR-126):** Phase 6 closeout is the immediate
objective and receives a two-point allowance from the measured 75% usage, with
a 77% checkpoint. If Phase 6 is fully evidenced and archived below that point,
Phase 7 may continue under its approved PRD up to an absolute 79% used. Sol is
the orchestrator/reviewer; Terra and Luna receive bounded work, with at most two
workers. No Astra. Budget never substitutes for a browser journey, archive,
critic or gate. Phase 8 remains sequential after Phase 7.

**Owner override, 2026-09-17 (ADR-121):** use GPT-5.6 Sol for orchestration,
contract arbitration, identity/RLS/money review, Phase 7 visual direction and
fresh-context critics. Use GPT-5.6 Terra for bounded work that still requires
judgement, including migrations, RPCs, authentication seams and independent
silent-failure test authorship. Use GPT-5.6 Luna as the default worker for
small, contract-complete implementation, screen transcription, registry/docs
updates and focused fixes. Freeze the contract before dispatch and run at most
two workers concurrently unless the required blind arrangement needs separate
visible and holdout authors. Do not use GPT-6 Astra in this campaign unless the
owner explicitly authorizes it later. The live Codex weekly limit is a hard
stop: check it after every completed micro-batch and stop at 77% used without
waiving a gate or a critic finding. This supersedes the 2026-09-10 model
assignment below; that paragraph and the older Claude policy remain as history.

**Owner extension, 2026-09-18 (ADR-124):** the campaign weekly-usage hard
stop is extended from 75% to 77% used. The model restriction is unchanged:
do not use GPT-6 Astra without explicit owner authorization.

**Owner override, 2026-09-10:** use GPT-6 Astra for orchestration, money/security
work, independent money test authors and critics, and Phase 7 UI/UX. Use
GPT-5.6 Sol for moderately complex bounded work and GPT-5.6 Terra for simple
inventory, transcription and routine tasks. Run independent work in parallel,
with contracts fixed first and changes landed serially on `main`. This replaces
the Claude model assignments below; those paragraphs are retained as history.
The current authorized sequence is the remaining Phase 5 work, then Phase 6.
Phase 7 design research and redesign wait until Phase 6 is complete.

**Build phases run on Claude Opus 5 at `xhigh`; the design phase runs on Claude Fable 5.1 at `max`.** Product-owner decision, 2026-09-06, made while Phase 1 was running: the first Fable run was cut off by the account usage limit after thirty minutes, and the owner chose Opus 5 for the build phases so runs complete, keeping Fable for Phase 7 where the blind visual comparison is the whole point. This supersedes the master prompt header's Fable-everywhere rule by the owner's own call, not by a session's. Effort stays `xhigh` on every build phase — the model changed, the bar did not. **Do not lower effort or substitute a smaller model than Opus 5, and do not propose it.**

| Phase | Model | Effort | Why this effort |
|---|---|---|---|
| 0 · Foundation | Fable 5.1 | `high` | Scaffolding — errors surface instantly. |
| 0 · final critic | Fable 5.1 | `xhigh` | Deep judgement on whether the gates really fire. |
| 1 · Data model + RLS | Opus 5 | `xhigh` | An RLS hole is silent and leaks another gym's members. |
| 2 · Identity & tenancy | Opus 5 | `xhigh` | Well-trodden auth wiring; role tests fail loudly. |
| 3 · Core domain | Opus 5 | `xhigh` | Double-scan, offline replay, exactly-once. Concurrency bugs are silent. |
| 4 · Retention engine | Opus 5 | `xhigh` | Per-timezone scans, no duplicate open cases. |
| 5 · Money | Opus 5 | `xhigh` | Webhook idempotency, never-mark-paid. Real money, real disputes. |
| 6 · Growth surfaces | Opus 5 | `xhigh` | Mostly CRUD over an already-proven core. |
| **7 · Design & UI** | Fable 5.1 | `max` | **The design must be the best part of this product.** Also a vision task — see below. Under ADR-059 the screens already exist by then; Phase 7 makes them excellent rather than building them from nothing. |
| 8 · Hardening | Opus 5 | `xhigh` | Last look before real gyms. |

**Amended by ADR-053 (2026-09-07, owner's observation): this policy governs the phase's own reasoning, not every sub-agent it dispatches.** The orchestrating session, blind test authors, blind critics, and any implementer writing a security boundary stay on Opus 5 at `xhigh`. Sub-agents doing transcription from a complete specification — inventory, factual research, documentation sweeps, registry updates, emitting a migration whose shape is already fixed — run on Sonnet. The line: if the brief is incomplete and the agent must fill the gap with judgement, that gap is the deliverable and it is Opus's. See `docs/decisions.md` ADR-053 for what was rejected.

**At `xhigh` and `max`, set a large `max_tokens`.** It is a hard ceiling on thinking *plus* response, so a long deliverable can otherwise be drafted in thinking and truncated in the reply. Because effort is the only lever, the instructions against unrequested refactoring, tidying and test sprawl matter *more*, not less: higher effort makes those behaviours more likely, and they are the cost of running hot everywhere.

**Phase 7 is a vision task.** The blind critic judges rendered screens against captured screenshots of the bars in `docs/architecture.md`'s "Quality bars" section. **Give that critic a crop tool** (bounding box in, cropped-and-enlarged region out) or a container with PIL/OpenCV, and **check the logs that it actually called it** — at lower effort it judges from an overall impression without zooming, which makes the blind comparison worthless. Loop until our screen wins the blind comparison; never lower the bar.

> **Correction, recorded rather than quietly fixed.** This table previously assigned Opus 5 to phases 0, 2 and 6 and lowered effort on 3, 4 and 7, justified by a claim that the master prompt's header "named only Phases 1, 4, and 5 for Fable." That claim was false against the file as committed — the header assigns Fable 5.1 to every phase and says in terms not to substitute a cheaper model. A blind critic caught it before Phase 1 started. The table above is now the header's, verbatim. If this policy is ever changed again, change it *because someone decided to*, and record that decision as an ADR — not by describing the source inaccurately.

## How phases are built from Phase 3 onward — vertical slices (ADR-059)

**Owner decision, 2026-09-08, after Phase 2.** The build order below is the master prompt's and it defers every screen to Phase 7. That is now amended: **Phases 3 to 6 each ship a thin working slice — schema, endpoint, and a screen the owner can actually click — rather than a backend the owner cannot see.** Phase 7 stops being "build the UI" and becomes "make the UI excellent", which is what it was always for.

The reason, in the owner's words: *"all of these are taking time — we want an app."* Five phases of invisible backend before the first screen is bad sequencing, and it was nobody's deliberate decision; it fell out of a build order written when the phases were the unit of planning.

**What stays, and what is dropped, from `AGENTS.md`'s Gauntlet Loop:**

| Kept everywhere | Relaxed for Phases 3, 4 and 6 |
|---|---|
| EARS spec before code, human-approved | The full blind fan-out — one implementer, not three blind roles |
| Tests written before implementation | The separate holdout suite, except where noted opposite |
| The contract fixed **before** any agent is dispatched | A dedicated fresh-context critic per unit |
| `docs/gates.md` and every CI gate | |

**The rigor stays in full for anything where a mistake is *silent*:** every RLS or policy change, the money path (Phase 5 entire), and any change to identity or the claim contract. A wrong RLS predicate leaks another gym's members and nothing goes red; a broken check-in screen fails in front of you. Those two deserve different processes, and Phases 1 and 2 earning their cost is not an argument that Phase 6 will.

**Four cuts taken with it (ADR-060), executed at the start of Phase 3:** the holdout suite moves into this repo at `supabase/tests-holdout/` and keeps its second independent author but loses the second repository; the pgTAP suite gets shared fixtures and stops asserting the role matrix twice, targeting under four minutes against the current 688 seconds; `proposal.md`/`design.md`/`tasks.md` merge into one `plan.md` with the EARS spec still separate; and ADRs get shorter. **Product scope is unchanged** — leads, CSV import, the add-on catalogue, the messaging wallet and the super-admin console all stay in v1.

**The one process change that costs nothing and saves the most:** Phase 2 spent roughly a third of its round-trips on contract churn — the design was edited four times *after* agents had been dispatched against it, so each edit meant re-work in three places at once. **Fix the contract, then fan out. Never the other way round.** If a blind agent's finding changes the contract mid-flight, that is a signal the contract was not ready, and the cost is paid by every agent already working.

## Phases (master prompt §12)

| Phase | Builds | Exit criteria |
|---|---|---|
| **0 · Foundation** | Monorepo, CI gates, doc framework, skills, OpenSpec, Supabase project, env validation | Gates provably **fail** on a deliberately bad commit — a duplicated helper, an unregistered export, a hardcoded constant |
| **1 · Data model** | Schema, enums, RLS, indexes, type generation, seed | pgTAP cross-tenant suite green on every table; one command seeds a complete demo gym |
| **2 · Identity & tenancy** | Phone-OTP members, email staff, JWT claims hook, role matrix, gym switching, impersonation + audit | Every role × every resource asserted; impersonation writes an audit row |
| **3 · Core domain** ✅ | Members, plans, memberships, pauses, QR check-in, offline queue, streaks — **plus staff login, a member list, and a working check-in screen** (ADR-059) | **MET 2026-09-08.** Holdout green (39 files, 2152 assertions); a second scan a second later answers `GL014` with one row in the database, demonstrated in a browser. Four critic rounds, four NO-GOs, then GO — nine of fourteen defects were introduced by the fix for the previous round's, which is what ADR-066 through ADR-072 record. Archive: `openspec/changes/archive/2026-09-08-phase-3-core-domain/` |
| **4 · Retention engine** ✅ | Daily no-show scan per timezone, cases, follow-ups, outcomes, auto-resolution — **plus the red-list screen staff work from** (ADR-059) | **MET 2026-09-09.** 43 pgTAP files / 2289 assertions green under `prove`; the loop ran end to end in a browser (`docs/evidence/phase4-red-list.png`); a second scan opens nothing. Three critic rounds — round two found six defects, four of them in code written to fix round one. ADR-074 to ADR-081, and ADR-078 is the one to read: the DB workflow was red for six commits while I reported it green, because the checker could only observe passes. Archive: `openspec/changes/archive/2026-09-09-phase-4-retention/` |
| **5 · Money** ✅ | Manual payments at the desk, the gym's own receipt book, renewal that follows the money, refunds — **plus the payments ledger, the receipt and the refund control** (ADR-059). Razorpay built to the point credentials are required and named as a gap | **MET 2026-09-09.** 47 pgTAP files / 3841 assertions green, seed clean and idempotent, all nine gates green, and the desk loop run in a browser: cash taken from a member's page, numbered `2026-27/000001`, attributed from the JWT claim; a ₹500 refund from the receipt it refunds; a ₹1,500 refund against ₹1,000 remaining refused by `GL036`. **Duplicate webhook delivery changes nothing**, demonstrated as `service_role` with no Razorpay account in existence. **Seventeen rounds, sixteen NO-GOs, then GO** — four times the longest gauntlet in this project, and the reason is worth the row: the money path is one arithmetic, `ends_on = duration_days × floor(money / price)`, and **every round closed one input to it and left another open**. Price, then the gate on the price, then the plan's length, then the dates the arithmetic produces, then the price again from the other side, then the coupon that names why a member owes less, then a status nothing read, then the refund ceiling keyed on a status nothing froze. **Three rounds found no defect in the arithmetic at all** — their blockers were contract text that contradicted itself, documentation claims measurement falsified, stale data in the shared demo gym, and twice a fix introducing a fresh critical. `GL034`–`GL046`, ADR-082 to ADR-097. OPEN-026 to OPEN-033 left open deliberately, each with its measurement and the reason it was not closed. Razorpay's remaining third is `openspec/changes/archive/2026-09-09-phase-5-money/razorpay-gap.md`, unstubbed. Archive: `openspec/changes/archive/2026-09-09-phase-5-money/` |
| **6 · Growth surfaces** ✅ | Add-ons, leads, notifications, owner metrics, super admin — **each with its screen** (ADR-059). | **MET 2026-09-18.** Communications/wallet, owner/fleet metrics and platform control passed independent tests, Cloud CI (81 pgTAP files / 6812 assertions), fresh-context review and real browser journeys. Owner cards reconciled to returned rows; super-admin preview and support read-only boundaries passed; the browser-only detail defect received a separate red test (`0ad90dc`) and fix (`745108c`). Exact cleanup removed the temporary support fixture and left no operational mutation. Archives: `openspec/changes/archive/2026-09-18-phase6-{comms,metrics,platform}/`. |
| **7 · Design & UI** | Approved minimalist member direction + owner adaptation → shared light/dark tokens → core-loop web redesign → real member/desk mobile; see the Phase 7 PRD | Cropped blind visual comparison, accessible themes, real journeys, Android/iOS builds and offline/identity evidence |
| **8 · Hardening** | Load test, a11y, backup drill, launch checklist | All 33 gates green (`docs/gates.md`) |

**After Phase 5's archive, before Phase 6: the open items it left.** Phase 5 archived GO with eight recorded open items rather than a clean sheet, and closing the reachable ones is worth more than starting Phase 6 on top of them. **OPEN-030 closed** — memberships now have the state machine `payments` has had since Phase 5 round three (`GL047`, ADR-098). **Nine critic rounds** then followed on the requirement beside it, ending in GO (ADR-108). They found two real behavioural defects — a migration that silently re-emitted a hundred-line function and reordered it, and a trigger whose *name* decided which rule answered — one real scope correction, and about twenty-five corrections to the descriptions of those three things. **Not one defect was in a migration.** The lesson worth carrying, recorded as ADR-105: *write the smallest normative sentence that covers the harm, quantified over something you control, and put everything else under a heading that says it is an observation.* Four of the nine rounds died on sentences that were true of the implementation and false of the world. Verified at the desk in a browser afterwards: one period for one period's money, receipt `2026-27/000006` (ADR-109). **First-grant fix completed 2026-09-10:** a fully dated membership now receives exactly the first period bought, with future starts preserved and elapsed unpaid starts moved to gym-local today. CI passed 47 files / 4243 assertions and the seed dry run; browser receipt `2026-27/000007` demonstrated one 30-day period, followed by exact demo cleanup. Archive: `openspec/changes/archive/2026-09-10-membership-creation/`. **OPEN-028 completed 2026-09-10:** the agreed net price is now used for grants and product displays; the paid historical annual period was reconciled once without moving dates; database workflow `34450245473` passed 49 files / 4385 assertions and its seed, and the main CI, test-immutability and holdout-placeholder workflows passed. Archive: `openspec/changes/archive/2026-09-10-membership-net-price/`. OPEN-029's unpaid direct-creation gap remains open. **Refund completion 2026-09-10:** OPEN-031, OPEN-032 and OPEN-034 are closed by refund-retries-and-money-audit. Final DB workflow `34453951689` passed 51 files / 4628 assertions, seed and generated types; all final CI passed. Real concurrent requests and browser retries passed with exact demo cleanup. Archive: `openspec/changes/archive/2026-09-10-refund-retries-and-money-audit/`. **Phase 6 identity/navigation completed 2026-09-10:** complete verified identities now share one classifier and one role home; member and platform read surfaces are live; stale Gymloop claims are removed on every hook path; support preview is visibly and database-enforced read-only with exact own-session ending. Database workflow `34466593342` passed 53 files / 4729 assertions, seed and generated types; web/shared/local gates, Astra security/UI review and real browser role/preview acceptance passed with exact cleanup. Archive: `openspec/changes/archive/2026-09-10-phase6-identity-navigation/`. **Phase 6 add-on sales and fulfilment completed 2026-09-11:** the whole optional-offer loop is live — catalogue with gym-stated terms, claim-complete sales, product/diet/PT delivery, exact receipts, and manual returns that flip the order to refunded and cancel undelivered service without touching delivered usage. Implementation `3e4ca92` was applied by database workflow `34508988355`; the types commit `b0d7849` then passed database workflow `34515453967` with all 63 files / 5413 assertions green and generated types matching. That run's seed dry run failed on the pre-hardening seed, fixed in `e7f7902`; the exact CI seed command now runs clean against the live schema and CI reconfirms on the next green database run (the intervening run `34520059628` carries the leads cluster's intentionally red tests and skips the seed job). Real browser journeys proved every sale, fulfilment, receipt, return, refusal and read-only preview path with screenshots in `docs/evidence/`, and exact cleanup restored the baselines (3 orders, 5 products, 5 PT sessions, 34 payments, 0 refunds, 46 members) with no seeded row touched. Evidence: `docs/evidence/2026-09-10-phase6-addon-sales.md`. Archive: `openspec/changes/archive/2026-09-11-phase6-addon-sales/`. **Phase 6 leads completed 2026-09-11:** the front-office enquiry pipeline is live — a graph-disciplined `leads` table (migration `20260915100005`), three claim-derived security-invoker RPCs under CAS with exact replay and GL062 cross-lead arbitration, the single-statement list snapshot, and the `/leads` screen with the enquiry form, stage transitions carrying a gym-local trial time, convert (create or link) and honest refusal surfaces. Visible and holdout suites committed red; implementation `fc888dd` was applied by database workflow `34562963974` (migrate, rollback, seed and schema-drift green; the full pgTAP job failed only on the import cluster's intentionally red suites already on main, no leads file failed); the types commit `586b9f8` made drift green. Browser acceptance exposed one route defect (the suite and route both named the transition parameter `p_to_stage` while the function declares `p_target` — PGRST202 folded into the default 500), fixed in `e8427a2`; live journeys then exercised every graph edge including both conversion paths with screenshots in `docs/evidence/screens/`, and exact cleanup restored the baseline (8 leads in the seeded stage distribution, 46 members, no seeded row's content changed). Evidence: `docs/evidence/2026-09-11-phase6-leads.md`. Archive: `openspec/changes/archive/2026-09-11-phase6-leads/`. **Phase 6 member CSV import completed 2026-09-11:** the CSV/XLSX import pipeline is live — a v1-columned `member_imports` run (migration `20260915100006`) with a fused invariant trigger over the pending → processing → completed|failed graph, the `prepare_member_import` / `commit_member_import` security-definer pair with an advisory-lock-serialized commit, independent phone/member_code duplicate classification, the four HTTP endpoints, the CSV/XLSX parser, and the `/imports` five-step screen. Full blind arrangement per ADR-059; visible (28/29/30) and holdout (h28) suites committed red before the implementation `a2f78aa`, applied by database workflow `34595018276` (migrate, pgtap-rollback, pgtap and seed-dry-run green across 6,414 assertions; schema-drift red as expected before types); the types commit `6934ca7` made database workflow `34598957109` fully green. Holdout debugging under ADR-060 surfaced a genuine pre-existing security gap — `member_imports` had never received the NAV-003 impersonation-read exclusion leads got — closed in the same migration with the matching policy and statement-trigger repair. A fresh-context critic returned GO with two non-blocking findings: a registry doc-name fix (`8742b08`) and a raced member_code duplicate's diagnostic label, recorded as OPEN-035 for a forward-only follow-up migration. Real browser journeys proved the golden import path, independent-dimension duplicate detection, and owner/manager-only role refusal, with exact cleanup restoring the baseline (0 journey members, 0 journey import runs, no seeded row touched). Evidence: `docs/evidence/2026-09-11-phase6-import.md`. Archive: `openspec/changes/archive/2026-09-11-phase6-import/`. **Next:** comms/wallet, then owner metrics and the platform slice. Phase 6 defaults are accepted under the owner's delegated authority (ADR-111); implementation follows the independent tests-first process.

**Phase 6 closeout completed 2026-09-18:** the preceding historical “Next” marker is superseded. Communications/wallet, owner and fleet metrics, and platform control now join the earlier identity/navigation, add-ons, leads and import slices. Cloud evidence remains 81 pgTAP files / 6812 assertions at `3e5120b`; final owner, super-admin, support and preview browser journeys passed with exact cleanup. A browser-only platform-detail defect was captured by the separate red-test commit `0ad90dc` and corrected in `745108c`. The three final changes are archived under `openspec/changes/archive/2026-09-18-phase6-*`. Phase 7 is now active under the approved experience PRD and ADR-126's usage boundary.

**Phase 7 visual foundation completed 2026-09-18:** shared platform-neutral
tokens, pinned local Inter fonts, persistent System/Light/Dark, reduced-effect
fallbacks and accessible sign-in/account-shell foundations are live. The real
owner journey, reload persistence, 44px shell
target and 32/38/600 title passed browser measurement with no hydration or
console errors. The focused suite is 8/8, final repository gates are green and
the fresh Sol visual critic returned GO. Canonical spec:
`openspec/specs/design-system/spec.md`; archive:
`openspec/changes/archive/2026-09-18-phase7-visual-foundation/`. Phase 7 remains
active for the core-loop route redesign and real member/front-desk mobile app.

**Phase 7 language override 2026-09-18:** the owner superseded ADR-011 for all
product surfaces. Web and mobile UI are English-only: no language picker,
persisted locale, Hindi sample or Devanagari font dependency. Phase 6 message
template locale data remains unchanged because it is a delivery contract, not
a product-interface mode (ADR-132).

**Phase 7 staff check-in surface completed 2026-09-18:** the first rendered
pass shared the new tokens but retained the old centered utility composition,
and the fresh visual critic correctly returned NO-GO. ADR-128 now makes the
approved v2 boards a route-level fidelity bar. The corrected screen uses the
shared 1440px canvas, a measured 2:1 roster/supporting-gate composition, finished
44/48px controls and a deliberate two-row 390px header; light/dark, no-overflow,
console and hydration checks passed, and the fresh re-critic returned GO. No
attendance or gate-code write was made. Evidence:
`docs/evidence/2026-09-18-phase7-check-in-surface.md`; archive:
`openspec/changes/archive/2026-09-18-phase7-check-in-surface/`.

**Phase 7 follow-up surface completed 2026-09-18:** `/red-list` now uses the
approved owner-board list hierarchy while preserving the real longest-away
ordering, identity/attendance/contact truth, exact generated-enum fields and
existing POST contract. The first fresh Sol critic rejected clipped Outcome / Note
content and 24px member links. Independent regression `dd8c7ad` preceded the
focused repair `96650b7`; the replacement critic then measured full desktop
labels, exact 44px mobile member links, no 1024px overflow and zero console
warnings/errors before returning GO. The route was reviewed without submitting
a follow-up. Evidence: `docs/evidence/2026-09-18-phase7-follow-up-surface.md`;
archive: `openspec/changes/archive/2026-09-18-phase7-follow-up-surface/`.

**Phase 7 owner shell completed 2026-09-18:** authenticated gym-console routes
now share the approved owner-board frame with truthful organization/code
context, permission-filtered navigation, exact current-route state and a
responsive rail/top-shell conversion. The first fresh Sol pass rejected the
desktop footer falling below tall content and narrow identity truncation;
independent regression `fb7589a` preceded repair `c94c6cc`. The rerun measured
the rail and Sign out inside the 900px viewport on both tall core routes in both
themes, complete identity at 390px, a 247px 1024px top shell, 44px targets, no
horizontal overflow and no console warnings/errors. Evidence:
`docs/evidence/2026-09-18-phase7-owner-shell.md`; archive:
`openspec/changes/archive/2026-09-18-phase7-owner-shell/`.

**Phase 7 owner overview completed 2026-09-18:** `/dashboard` now matches the
approved owner-board hierarchy without inventing board data or adding a second
metrics read. Exactly four primary facts, six compact follow-up cases,
renewal/recovery support and every secondary disclosure reconcile to the one
existing `OwnerMetrics` snapshot. The first Sol comparison rejected density,
mobile navigation, verbose money and raw detail rows; independent regressions
and bounded corrections produced 56px case rows, compact rupee values,
humanized detail and a 390px disclosure menu. A replacement fresh Sol review
then exposed the intermediate wrapper off-canvas at 1024px; the final focused
test and CSS correction contained all nine 44px destinations, and its
blocker-only verdict returned GO. Evidence:
`docs/evidence/2026-09-18-phase7-owner-overview.md`; archive:
`openspec/changes/archive/2026-09-18-phase7-owner-overview/`.

**Phase 7 web route completion completed 2026-09-18:** the remaining owner,
member and platform interiors now use the approved English-only light/dark
system without changing their authorization, money or mutation contracts. A
fresh visual critic returned GO after focused regressions restored always-
visible authorized owner navigation, the dominant member check-in hierarchy
and the compact 1024px rail. Final Cloud workflow `35371043539` passed migration,
rollback, schema drift and all 87 visible/holdout pgTAP files / 6,886 assertions.
Evidence: `docs/evidence/2026-09-18-phase7-web-mobile-foundation.md`; archive:
`openspec/changes/archive/2026-09-18-phase7-web-completion/`. Phase 7 remains
active only for its native iOS/real-device acceptance boundary and the
owner-approved second-association decision described in the evidence.

**Phase 7 Android device acceptance advanced 2026-09-20:** the ARM64 app is
installed on a physical Android 13 device; real member and front-desk sessions,
all eight native tabs, Light/Dark and sign-out role isolation passed. The device
journey exposed and closed a stale member-money RPC column (`337b51d`,
`33d82f4`) under independent visible/holdout tests and fresh money/security GO,
then exposed a nested sign-out redirect loop fixed directly at both role
layouts. Cloud DB workflow `35462598284` applied the repair and the still-signed-
in member loaded the complete live snapshot. Evidence:
`docs/evidence/2026-09-20-phase7-android-device.md`. Physical device-max text
and Android Remove animations now preserve the authenticated member shell and
all actions, with device settings restored after capture. Phase 7 remains active
for iOS and the already-recorded second-association decision. The Android real-
QR journey is now complete: a physical airplane-mode scan queued one event, an
actual force-stop/restart exposed and closed the transient-JWKS identity defect,
reconnect moved the live week from `0 / 4` to `1 / 4`, and another restart left
it at `1 / 4`. Independent visible and blind contracts cover same-member
recovery and different-member refusal (`edeb6f1`, `fe22b4e`, `2c2b64e`,
`e3005bd`, `d82a415`, `8767ee1`, `d1a85cf`). No emulator or synthetic scan was
substituted. A fresh Sol comparison returned visual GO on the
final original-resolution Android member and front-desk renders, including the
English-only light/dark system, compact operational rows and persistent tabs.

**Phase 7 iOS build evidence advanced 2026-09-20:** EAS project
`@harsh9887/gymloop` is linked and credential-free simulator build
`22ede637-bdad-428b-b091-ceda282e7fa5` finished from SDK 57 commit `2f87add`.
This proves the native iOS project compiles on macOS without weakening the SDK
contract. It does not claim an iPhone-installable IPA or runtime journey: EAS
physical-device signing requires a paid Apple Developer team, which the owner
does not currently have, and the App Store Expo Go client does not support SDK
57. Evidence: `docs/evidence/2026-09-20-phase7-ios-build.md`. Phase 7 remains
open at that external signing boundary and the second-association decision; the
Android real-QR airplane/reconnect boundary is complete.

Each phase opens its own OpenSpec change (`openspec/changes/000N-<phase-name>/`) and follows the Gauntlet Loop (`AGENTS.md`) — bar, spec, tests-first, build, fresh-context critic, gates, archive. Phase 0's own change is the worked template — proposal, design, tasks, and the evidence trail of what was proven and what went wrong on the way: `openspec/changes/archive/2026-09-06-phase-0-foundation/`.
