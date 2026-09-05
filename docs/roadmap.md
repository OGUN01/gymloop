# Roadmap

`MASTER-BUILD-PROMPT.md` is disposable after Phase 0 (its own §3). Its build order (§12) and its model/effort policy lived only in that file — nowhere else recorded which phase runs on which model, at what effort. This file is that record, so a session starting Phase 3 doesn't have to guess or re-derive it from a prompt that is no longer expected to be read.

## Model and effort policy

**Rule:** run Fable 5.1 where being wrong is expensive and hard to detect (schema/RLS mistakes surface as a data leak weeks later; a payment bug surfaces as a support ticket after money has moved; a rendered UI's fidelity to a design bar is a judgment call, not a compiler error). Run Opus 5 where errors surface immediately and cheaply (a broken auth flow fails its own tests within the session; scaffolding either builds or doesn't).

| Phase | Model | Effort |
|---|---|---|
| 0 — Foundation | Opus 5 | high |
| 0 — final critic | Fable 5.1 | xhigh |
| 1 — Data model + RLS | Fable 5.1 | xhigh |
| 2 — Identity & tenancy | Opus 5 | high |
| 3 — Core domain | Fable 5.1 | high |
| 4 — Retention engine | Fable 5.1 | high |
| 5 — Money | Fable 5.1 | xhigh |
| 6 — Growth surfaces | Opus 5 | high |
| 7 — Design & UI | Fable 5.1 | xhigh |
| 8 — Hardening | Fable 5.1 | xhigh |

This supersedes the three-phase policy in `MASTER-BUILD-PROMPT.md`'s header (which named only Phases 1, 4, and 5 for Fable) — that policy is superseded, not merely extended; treat this table as authoritative.

**Phase 7 is Fable because it is a vision task**: the blind critic judges rendered screens against captured competitor screenshots (`docs/architecture.md`'s quality-bar table). At low effort a vision-capable critic judges from overall impression without zooming into the details that actually distinguish a Linear-grade dashboard from an adequate one — which makes the comparison worthless. **Give the Phase 7 critic a crop tool** (a bounding-box-in, cropped-and-enlarged-region-out tool, or a PIL/OpenCV-equipped container) and **verify from the run logs that it actually called it** before trusting a "picks ours over the bar" verdict — an unverified claim of visual comparison is not evidence of one.

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
