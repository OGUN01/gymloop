# FitCruxx v2 campaign goal — execution playbook (2026-10-02)

Companion to `docs/planning/v2-feature-map.md` (the what). This file is the
how: the build order, the per-feature session loop, the definition of done,
and the release plan. Every v2 session starts by reading both files.

## The method (unchanged from v1 — the Gauntlet Loop)

Every feature, no exceptions, runs the same loop inside ONE session:

1. **Bar** — a fetchable comparable reference for the feature's quality.
2. **Spec** — EARS requirements with stable IDs, committed first as a `spec:`
   commit. Human-approved wording for anything contract-level.
3. **Tests** — visible suite red first (own `spec:` commit), plus a holdout
   suite written by an independent author who reads no implementation.
   Test files are immutable to the implementer.
4. **Build** — make them green. Never touch test files.
5. **Gauntlet** — fresh-context critic on every dimension; three rejections of
   the same dimension escalates to the owner, never silently lowers the bar.
6. **Gates** — every CI gate green on `main` (CI, DB, Holdout, Test
   immutability, schema-drift, escape-hatches, registry-lint).
7. **Archive** — sync OpenSpec spec, archive the change, update
   `docs/registry.md`, ledger evidence.

**Rigor level per ADR-059:** full blind arrangement (separate visible-test
author, holdout author, implementer, fresh critic — none reading the others)
wherever a mistake is silent: identity and claim contract (INV, STI, GRD), the
whole money path (PAY), every new RLS surface (CLS, SHP, PTF read policies).
Relaxed (one implementer + spec/tests-first + all gates) for loud-defect
surfaces: screens, catalogue views, exports, copy.

**Agent economy (owner direction):** easy tasks on the cheap model slot, hard
reasoning on the strong slot. Screens/docs/assets → cheap slot. Spec/test
authors and fresh critics for blind-rigor features → the strong slot.

**Session hygiene:** one feature per session, `/clear` between them, work on
`main` directly, push each coherent unit when green. Never push a migration
while a DB run is in flight (the `db-` concurrency group serializes them).
Fix the contract, then fan out — never edit a contract while agents work
against it.

## D1 — DECIDED by owner, 2026-10-02: one Google account, one member. Period.

**Owner decision:** one Google account works as exactly one member, ever, in
the whole system. No multi-binding, no gym picker, no ambiguity — because the
UI derives from the account's single membership. An account that is already
linked anywhere gets a clear refusal at link time: this account is already
joined as a member — it cannot be linked again; ask your gym to use a
different email.

Consequences, now binding on the v2 features:

- PROV-006's exactly-one-binding rule stays the contract, unchanged. Nothing
  to build for D1 — the decision collapses into INV/STI edge cases.
- INV's redemption edge case is settled: already-linked (any gym) → refuse
  with the clear error copy above, never a picker.
- GRD's same-guardian-two-children case: both children's rows may carry the
  guardian's contact fields (for notifications and DPDP consent), but only
  ONE child's row may bind the guardian's Gmail as its app identity. A second
  child who needs app access links a different Google account (their own, or
  the other parent's) — the gym chooses at invite time. The refusal copy
  covers mistakes.
- A member who genuinely joins two gyms uses two Google accounts, or the
  second gym records them desk-only. This is accepted cost, not a bug.
- No change to the JWT claim shape — single-tenant stays.

## Build order (phases = sessions, in dependency order)

| # | Phase | Features | Why this order |
|---|---|---|---|
| 1 | V2-A1 | INV member invites | the everyday onboarding path |
| 2 | V2-A2 | STI staff invites | reuses INV machinery immediately while fresh |
| 3 | V2-A3 | GRD guardian + minors | builds on the identity work; closes DPDP-172 item |
| 4 | V2-A4 | BIZ business_type copy | small, independent, rides anytime after D1 |
| 5 | V2-B1 | PLC plans catalogue | smallest screen; warms up the member-app pattern |
| 6 | V2-B2 | SHP shop + product images (R2) | R2 upload infra reused by everything visual |
| 7 | V2-B3 | PTF trainer profiles + programmes | profiles + packs; booking calendar next |
| 8 | V2-B4 | CLS classes + timetable + booking | the centerpiece; reuses PTF calendar + lock patterns |
| 9 | V2-B5 | ANC announcements on Home | trivial once CLS/NTF shapes exist |
| 10 | V2-C1 | NTF push notifications | delivery layer for everything after |
| 11 | V2-C2 | PAY Buy tab + payment screenshots | money path, full blind; needs NTF for desk alerts |
| 12 | V2-C3 | WSP WhatsApp | provider work, independent money-adjacent |
| 13 | V2-D1 | SLF self-service | needs PAY's request flow |
| 14 | V2-D2 | TRV trainer view | needs CLS/PTF data |
| 15 | V2-D3 | LDC lead convert | small |
| 16 | V2-D4 | OCC occupancy + revenue + fill analytics | needs CLS attendance history to be meaningful |
| 17 | V2-D5 | RPE PDF/GST export | owner console only, last, low risk |
| 18 | V2-R | Release: versionCode 5 | see below |

Phases may reorder inside a wave on closed-test feedback, but never across
it (B before C, C before D) without the owner saying so.

## UI/UX consistency — non-negotiable rules

The current app's look is the Chalkline design system, owner-accepted
(ADR-170/172). Every v2 screen:

- Uses the **existing component kit** (`apps/mobile/components/ui`,
  web Chalkline kit) and `UI_TOKENS` from `packages/shared`. No new design
  language, no new color ramps, no ad-hoc spacing.
- Matches the established patterns: ledger rows for facts, `Sheet` for
  confirmations, `StateMessage` for outcomes, empty states with real copy,
  light+dark, large-text and reduced-motion clean.
- Registers every new exported symbol in `docs/registry.md`; reuses before
  creating (registry-lint fails otherwise).
- Faces the same visual bar as Chalkline: fresh-critic score, light and dark,
  390-width mobile and 1440 web, axe-clean.
- Copy matches the product's voice: specific, honest, no invented numbers,
  same refusal-code transparency as the desk flows.

## Definition of done — per feature

- `spec:` commits (spec, visible tests, holdout) precede implementation.
- All CI gates green on `main` including DB (migrations applied by CI only)
  and schema-drift (generated types regenerated via CLI, never hand-edited).
- OpenSpec change archived; `docs/registry.md` and the Phase 8-style ledger
  updated with evidence.
- Fresh-critic GO.
- Any user-visible string follows the rules above.

## Release — versionCode 5 (V2-R)

1. Bump `versionCode` to 5 in the worktree build (`docs/runbooks/`
   android-release flow; local Gradle build while EAS Free resets).
2. Verify: `jarsigner`, merged manifest, permissions unchanged, no gymloop
   addresses in the JS bundle.
3. Upload to the internal track first, roll out, device-verify the checklist
   on the phone (same HARD-008 checklist as vc4).
4. Then the closed track via library add (versionCode 5), release notes for
   the v2 features, submit with the store listing updated for whatever became
   visible.
5. Evidence into `docs/evidence/`, ledger updated.

## The goal line to paste into each feature session

> You are the orchestrator for FitCruxx v2 phase <PHASE-ID> (<FEATURE>).
> Read `docs/planning/v2-feature-map.md` (the feature contract and edge
> cases) and `docs/planning/v2-campaign-goal.md` (the method, rigor level,
> UI rules, definition of done). Run the full Gauntlet Loop for this one
> feature only: spec and tests first in `spec:` commits (visible + holdout by
> an independent author where the campaign file demands blind rigor),
> implementation, fresh-context critic, all CI gates green, push `main`,
> archive the OpenSpec change, update the registry and ledger. Reuse the
> Chalkline component kit and existing tokens — no new design language. Do
> not start, plan or push any other feature. Do not push while a DB run is in
> flight. Escalate to the owner rather than lowering any bar.

Updated 2026-10-02. The closed-test feedback merges into the feature map
before any phase's bar is written; build order inside a wave may move on it.
