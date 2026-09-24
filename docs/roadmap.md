# Roadmap

**2026-09-23 linked-Cloud load result (ADR-162):** the owner confirmed no live
customers and authorized the existing Gymloop Cloud Supabase project for the
finite HARD-004 synthetic 100 × 500 run. The sixth full run passed with
50,000/50,000 acknowledged API check-ins, 664.5 ms p95 against the fixed
2,000 ms limit, both cross-tenant denials, database size below the 400 MB
abort ceiling, and independently verified exact cleanup. Earlier failed runs
and all receipts remain in the Phase 8 ledger. The provider restore/PITR
exception is limited to the controlled five-gym pilot; the encrypted R2
logical-backup receipt passed once. Other pilot gates, including privacy,
monitoring responder ownership, exact-AAB Play install and owner visual
acceptance, remain open. The legacy isolated load route stays available.

**2026-09-23 monitoring update:** the independent watchdog is implemented and
deployed. A TEST-only missing-run issue, a healthy watchdog evaluation and one
Cloudflare dual dispatch to green monitor/watchdog workflows are in the Phase 8
ledger. A later assignment repair sent fresh TEST missing-run, collection-
failure and threshold issues to the owner's `OGUN01` GitHub account, with all
three routes verified live. Actual human notification and acknowledgement plus
protected roster/access review remain open, so HARD-005 is Partial.

**Controlled-pilot scope update (ADR-168, 2026-09-23):** the owner accepted
privacy product decisions and qualified legal/DPA review as unresolved pilot
exceptions until the planned VPS migration, accepted an unverified independent
missing-run alert as a pilot exception, and named themself primary GitHub alert
responder. The underlying HARD-005/006 and DPDP/alert gates remain open; this
does not establish legal compliance or a human alert acknowledgement. Other
applicable A–D, Play artifact, visual and security evidence still governs GO.

**Free-plan five-gym pilot exception (ADR-159, 2026-09-22):** the owner excludes
the provider restore/PITR drill from the controlled-pilot GO decision because
the current Supabase Free plan does not include that control. Gate 29 remains
unperformed and open for general release; a protected logical backup export
and every other applicable pilot/Phase 8 gate still require real evidence.
This supersedes the earlier requirement to make all 33 rows green before the
controlled pilot, not the requirement to report each row truthfully.

**Manual-payment-only initial release (ADR-146, 2026-09-21):** a gym collects
money externally and records it through Gymloop's desk interface. Gateway
charge initiation, callbacks and provider onboarding are deferred. The Phase 5
manual receipt/renewal/refund work remains required; inactive Razorpay schema
is not an enabled feature. This scope change does not pass unrelated Phase 8
privacy, backup, load, monitoring, Play, tenancy or visual gates.

**Current Phase 8 owner direction, 2026-09-21 (ADR-143):** Sol owns completing
and evidencing every non-visual Android/web gate; the owner handles the separate
UI/UX redesign. The execution order is in `docs/planning/current-campaign-goal.md`
and exact pass/partial/external status is in `docs/evidence/phase8/ledger.md`.
The two-gym authenticated smoke is real but is not the complete HARD-003 A–D
Playwright gate. No external or legal gate is passed by taking responsibility
for it, and no destructive linked reset is authorized without verified recovery.

**Owner Phase 8 synthetic-testing direction, 2026-09-21 (ADR-142):** the owner
states Gymloop has no live customers and authorizes broad synthetic functional
testing in the currently linked project, with an eventual data reset. The
project is nevertheless production-configured and already contains demo Auth
users and transactional rows. Keep test data identifiable and use rollback-
wrapped SQL where possible. Do not run a destructive linked reset until a
verified backup and a procedure to recreate the five demo Auth sign-ins exist;
`seed.sql` cannot recreate them. The frozen 100 × 500 load acceptance still
requires a distinct non-production target, and provider/legal/store evidence
cannot be synthesized by adding rows. This direction supersedes ADR-140's
blanket exact-cleanup requirement for bounded prelaunch demo-data checks, not
its prohibition on unproven destructive recovery or production stress.

**Owner Phase 8 autonomous closeout, 2026-09-21 (ADR-141):** the owner lifted
the earlier 30%-used weekly stop for this campaign and directed completion of
all safely executable non-visual Phase 8 work, with economical model and test
use. Continue bounded verification against the existing Gymloop Supabase
project; defer a separate staging project and the UI redesign. This does not
change HARD-004's production-refusing load contract, permit a production
restore/stress run, or convert missing legal, backup, monitoring, provider,
Play-policy, or exact-artifact evidence into a pass. Record external blockers
truthfully and do not archive Phase 8 until its exit criteria are met.

**Owner Phase 8 bounded-production verification and future VPS direction,
2026-09-21 (ADR-140):** from 25% measured weekly usage, the owner authorized
five further points, stopping new work at 30%. Reuse the existing free Gymloop
Supabase project for bounded functional checks with exact baseline and cleanup
where a write is truly necessary. This does not replace HARD-003's second-gym
isolation fixture or HARD-004's distinct non-production load target; production
load and restore drills remain prohibited. The owner intends a later self-hosted
Supabase deployment on a VPS, but no infrastructure switch is approved in this
slice. A future migration must explicitly verify Auth claims/hooks, Vault and
secrets, Edge Functions, Cloudflare R2, backups, monitoring, capacity and
rollback before any traffic moves. Visual redesign remains owner-deferred.

**Chalkline redesign, 2026-09-24 (ADR-170, ADR-171):** every web route and Android screen is rebuilt in the owner-chosen Chalkline direction and refined through five rounds of fresh strict critics (every screen ≥ 8.1/10; evidence `docs/evidence/2026-09-24-chalkline-redesign.md`). HARD-010 is **ready for the owner's review**, not accepted: acceptance must come from the owner.

**Owner Phase 8 non-visual continuation, 2026-09-21 (ADR-139):** visual redesign
is owner-deferred; HARD-010 stays NO-GO until independently accepted. The owner
confirmed Ductx as Gymloop's intended Play publisher and authorized two more
weekly-usage points from 22% used, stopping new work at 24%. The local code and
signed AAB do not discharge the remaining non-production, provider, legal,
restore, Play declaration/install or publication gates; see the Phase 8 ledger.

**Owner Phase 8 production closeout, 2026-09-21 (ADR-138):** from 19% weekly
used, one additional point permits the narrow member-profile correction,
current-source Android AAB and physical/web verification, and Play internal-test
preparation. The stop for new work is 20% used. Gymloop is not yet created in
the available Play developer account; policy/export declarations require the
account holder's truthful certification. The remaining legal, monitoring,
non-production load, restore, exact-AAB Play install, and store-publication
gates retain their real statuses. No signed build is a publication claim.
At the 20% stop, the fresh HARD-010 review remained NO-GO despite the repaired
gym identity and verified Android/web builds; see the Phase 8 ledger. Phase 8
remains active, not archived or production-approved.


**Owner Phase 8 experience/auth continuation, 2026-09-20 (ADR-136):** Phase 7's
Android-first functional boundary remains archived, but its visual finish is not
accepted as the product bar. Phase 8 now begins with a focused member experience
refinement before the remaining hardening work: the approved minimalist v2
boards are literal conformance references for authentication, Home, Activity,
My gym and You; light and dark must be equally intentional; presentation is
English-only; gym imagery is purposeful on authentication/profile surfaces and
does not replace operational content. Google sign-in is added for existing,
pre-linked Gymloop identities on web first and Android second. It grants no
membership or role, performs no self-service linking, and an unlinked provider
identity reaches the existing no-access state. The measured start is 9% weekly
usage and the owner's extended allowance makes **12% used the hard stop for new
work**. Sol freezes/reviews the contract, while at most two bounded Terra/Luna
workers own independent identity tests, narrow implementation, and visual/device
verification. No Astra, broad speculative rewrite, unreviewed cloud credential,
or synthetic provider success is authorized.

**Owner Phase 8 non-visual resume, 2026-09-21 (ADR-137):** the remaining UI/UX
refinement is deferred to a later session. This continuation is limited to the
locally executable Android/web production, Google-authentication and truthful
evidence closeout. Passing focused evidence is reused rather than rerun. iOS and
every provider/legal/cloud/store action without real evidence remain deferred or
external; HARD-010 is not represented as visually accepted.

**Owner Android-first continuation, 2026-09-20:** iOS runtime acceptance is
deferred until Android is complete through Phase 8. V1 remains one verified gym
association per member; no public gym-code join/switch surface will be added,
and a future secure invitation/linking mechanism is post-v1. Phase 7 is green
and archived under this Android-first boundary; Phase 8 is now active for
hardening and Android release readiness. Usage was 6% at this continuation;
ADR-135's two-point allowance makes 8% used the hard stop. External provider credentials, legal approval,
platform backup controls and Play-account actions are reported honestly rather
than replaced by synthetic success.

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
| **7 · Design & UI** ✅ | Approved minimalist member direction + owner adaptation → shared light/dark tokens → core-loop web redesign → real member/desk mobile; see the Phase 7 PRD | **MET 2026-09-20 under ADR-134.** Web and Android member/front-desk surfaces passed cropped visual review, accessible Light/Dark device journeys, verified role isolation and real offline QR replay. Physical iOS runtime is explicitly deferred, not claimed. Canonical mobile spec: `openspec/specs/mobile/spec.md`; archive: `openspec/changes/archive/2026-09-20-phase7-mobile-foundation/`. |
| **8 · Hardening** | Load test, a11y, backup/export readiness, launch checklist | Controlled five-gym pilot: every applicable gate evidenced, with only gate 29's Free-plan provider restore/PITR drill owner-excepted under ADR-159 and still reported open; full general-release completion still requires the actual drill (`docs/gates.md`) |

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
`openspec/changes/archive/2026-09-18-phase7-web-completion/`. At that milestone,
the native Android/association acceptance boundary remained open and was closed
by the 2026-09-20 evidence and ADR-134 decision below.

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
all actions, with device settings restored after capture. The Android real-
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
57. Evidence: `docs/evidence/2026-09-20-phase7-ios-build.md`. ADR-134 subsequently
deferred this external signing/runtime boundary and chose one verified gym for
v1; neither is represented as physical iOS acceptance.

**Phase 7 completed 2026-09-20 under ADR-134:** Android is the accepted v1
runtime. Physical Android member and desk sessions, all eight tabs, Light/Dark,
maximum text, reduced motion, role isolation and real airplane-mode QR replay
through a cold restart passed on device. The owner chose one verified gym
association for v1, with no public-code join/switch control; secure invitation
linking and physical iOS runtime remain future work. Fresh security/money and
visual critics returned GO, and CI is green. Canonical mobile spec:
`openspec/specs/mobile/spec.md`; archive:
`openspec/changes/archive/2026-09-20-phase7-mobile-foundation/`. Phase 8 is active.

**Phase 8 production release advanced 2026-09-20:** the web/API is live at
`https://gymloop-phi.vercel.app` on Vercel `bom1`, and EAS build
`146221dd-dab2-4ef1-a99b-61dc14be4675` produced the signed Android `1.0.0`
store AAB with unique version code `2` from `7a31384`. Bundletool validation,
signature verification and merged-manifest inspection passed with the same
approved upload certificate and least-privilege permission set. The latest
production deployment `9h745WmLGeD3YeMBtMkgCrb54qdm` is Ready from `5e4b534`.
Auth workflow `35533772247` enabled Google with the exact hook/site/allow-list
boundary, public settings reported Google enabled, and a controlled real Google
account completed OAuth to the unlinked/no-access state without receiving a
Gymloop identity. HARD-011 and HARD-012 are Passed. HARD-002 is Passed; HARD-008
remains Partial / External until the exact artifact is installed from a Play
internal track (or an explicitly authorized derived APK set) and the physical
checklist runs. Phase 8 remains active for the owner-deferred visual acceptance,
external non-production load fixture, monitoring destination,
legal/data-lifecycle decisions, restore drill and Play actions.

Each phase opens its own OpenSpec change (`openspec/changes/000N-<phase-name>/`) and follows the Gauntlet Loop (`AGENTS.md`) — bar, spec, tests-first, build, fresh-context critic, gates, archive. Phase 0's own change is the worked template — proposal, design, tasks, and the evidence trail of what was proven and what went wrong on the way: `openspec/changes/archive/2026-09-06-phase-0-foundation/`.
