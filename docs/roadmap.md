# Roadmap

`MASTER-BUILD-PROMPT.md` is disposable after Phase 0 (its own §3). Its build order (§12) and its model/effort policy lived only in that file — nowhere else recorded which phase runs on which model, at what effort. This file is that record, so a session starting Phase 3 doesn't have to guess or re-derive it from a prompt that is no longer expected to be read.

## Model and effort policy

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
| **7 · Design & UI** | Fable 5.1 | `max` | **The design must be the best part of this product.** Also a vision task — see below. |
| 8 · Hardening | Opus 5 | `xhigh` | Last look before real gyms. |

**At `xhigh` and `max`, set a large `max_tokens`.** It is a hard ceiling on thinking *plus* response, so a long deliverable can otherwise be drafted in thinking and truncated in the reply. Because effort is the only lever, the instructions against unrequested refactoring, tidying and test sprawl matter *more*, not less: higher effort makes those behaviours more likely, and they are the cost of running hot everywhere.

**Phase 7 is a vision task.** The blind critic judges rendered screens against captured screenshots of the bars in `docs/architecture.md`'s "Quality bars" section. **Give that critic a crop tool** (bounding box in, cropped-and-enlarged region out) or a container with PIL/OpenCV, and **check the logs that it actually called it** — at lower effort it judges from an overall impression without zooming, which makes the blind comparison worthless. Loop until our screen wins the blind comparison; never lower the bar.

> **Correction, recorded rather than quietly fixed.** This table previously assigned Opus 5 to phases 0, 2 and 6 and lowered effort on 3, 4 and 7, justified by a claim that the master prompt's header "named only Phases 1, 4, and 5 for Fable." That claim was false against the file as committed — the header assigns Fable 5.1 to every phase and says in terms not to substitute a cheaper model. A blind critic caught it before Phase 1 started. The table above is now the header's, verbatim. If this policy is ever changed again, change it *because someone decided to*, and record that decision as an ADR — not by describing the source inaccurately.

## Phases (master prompt §12)

| Phase | Builds | Exit criteria |
|---|---|---|
| **0 · Foundation** | Monorepo, CI gates, doc framework, skills, OpenSpec, Supabase project, env validation | Gates provably **fail** on a deliberately bad commit — a duplicated helper, an unregistered export, a hardcoded constant |
| **1 · Data model** | Schema, enums, RLS, indexes, type generation, seed | pgTAP cross-tenant suite green on every table; one command seeds a complete demo gym |
| **2 · Identity & tenancy** | Phone-OTP members, email staff, JWT claims hook, role matrix, gym switching, impersonation + audit | Every role × every resource asserted; impersonation writes an audit row |
| **3 · Core domain** | Members, plans, memberships, pauses, QR check-in, offline queue, streaks | Holdout suite green; double-scan and offline replay produce exactly-once attendance |
| **4 · Retention engine** | Daily no-show scan per timezone, cases, follow-ups, outcomes, auto-resolution | Journey B passes end-to-end; no duplicate open cases under repeated runs |
| **5 · Money** | Razorpay per gym, orders, webhooks, offline payments, GST invoices, refunds, renewals | Payment state machine complete; duplicate webhook delivery changes nothing |
| **6 · Growth surfaces** | Add-ons, leads, notifications, owner metrics, super admin | Owner metrics reconcile exactly against underlying rows |
| **7 · Design & UI** | Bar capture → tokens → mockups → web, then mobile | Blind critic picks ours over the captured bar (with the crop-tool verification above) |
| **8 · Hardening** | Load test, a11y, backup drill, launch checklist | All 33 gates green (`docs/gates.md`) |

Each phase opens its own OpenSpec change (`openspec/changes/000N-<phase-name>/`) and follows the Gauntlet Loop (`AGENTS.md`) — bar, spec, tests-first, build, fresh-context critic, gates, archive. Phase 0's own change is the worked template — proposal, design, tasks, and the evidence trail of what was proven and what went wrong on the way: `openspec/changes/archive/2026-09-06-phase-0-foundation/`.
