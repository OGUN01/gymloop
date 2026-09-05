# Architecture

## Folder map — target layout (master prompt §4)

```
apps/
  web/              Next.js 16.3 App Router, React 19.2, TS strict, Tailwind. REAL, built in Phase 0.
  mobile/           Expo/React Native, New Architecture. DEFERRED to Phase 7 — see docs/decisions.md ADR-019/ADR-020.
                    Does not exist yet. Its absence is a decision, not a bug — do not recreate it ad hoc.
packages/
  shared/           Cross-cutting config, constants, env validation. REAL, built in Phase 0. Platform-free
                    by construction — see "Boundaries" below.
  db/               Generated Supabase types (packages/db/types/database.ts) — the one artifact of the
                    truth chain described below. REAL, built in Phase 0.
  api-client/       "One generated client" consumed by both web and mobile (§4). DEFERRED to Phase 2 —
                    nothing to generate until Route Handlers exist. Generator tool is an open decision,
                    see docs/decisions.md OPEN-002.
docs/               This layer — on-demand knowledge, pulled when a session needs it, not always loaded. EXISTS.
scripts/            CI gate implementations (registry-lint, check-test-immutability) + their tests. EXISTS.
.claude/
  skills/           Procedures — progressive disclosure, ~100 tokens each at rest until invoked. EXISTS.
                    Five domain skills (new-feature, db-migration, new-api-endpoint, rls-policy,
                    payment-flow) plus six openspec-* skills installed by `openspec init`.
  commands/opsx/    OpenSpec's own slash commands (/opsx:propose, :apply, :archive, ...), installed by
                    `openspec init`. Tool-provided, not hand-written.
openspec/
  specs/            Current system truth, one capability per file, updated by archiving changes.
                    EXISTS but EMPTY — Phase 0 declared skip_specs (it changes no product behavior),
                    so the first entries arrive when Phase 1 archives.
  changes/          In-flight proposals; archived into changes/archive/ on completion. EXISTS.
supabase/
  config.toml       EXISTS. Project id + local stack config.
  migrations/       DOES NOT EXIST YET — created by Phase 1. Applied by CI only, never by hand.
  tests/            DOES NOT EXIST YET — created by Phase 1. pgTAP suites.
tests/              DOES NOT EXIST YET — created by the phase that first needs each layer.
  visible/          Phase 1+. Tests the implementer sees, derived from EARS specs before implementation.
  e2e/              Phase 3+. Playwright, the four journeys (docs/gates.md gate 32).
  load/             Phase 8. k6.
                    The holdout suite lives in a separate private repo (github.com/OGUN01/gymloop-holdout),
                    never here — that is the point of it.
```

Directories marked DOES NOT EXIST YET are part of the §10 target layout but are deliberately not created empty: an empty directory carries no information git will even track, and `knip` flags empty scaffolding. The phase that first needs one creates it. This is the same reasoning as `apps/mobile` and `packages/api-client` above, applied to directories rather than packages.

## API architecture (one place for every invariant — master prompt §4)

- **Mutations** go through Next.js Route Handlers in `apps/web`, zod-validated against schemas derived from the generated Supabase types, returning a typed error envelope. Both web and mobile consume them through `packages/api-client` once it exists (Phase 2).
- **Reads** go direct through `supabase-js` with RLS enforcing tenant isolation — for speed and Supabase Realtime, not routed through a Route Handler.
- **Supabase Edge Functions** are used for exactly two things: Razorpay webhooks and cron-triggered jobs (no-show scans, reminder dispatch). Both must sit next to the database and must not depend on Vercel being up. Nothing else runs as an Edge Function — application logic that could live in a Route Handler does, so it stays colocated with the web app.

## The truth chain for data (master prompt §10)

```
Postgres enum/table (Phase 1 migration)
   ↓ supabase gen types
packages/db/types/database.ts   — GENERATED, never hand-edited (CI diffs it; drift fails the build)
   ↓ derived
zod schemas                     — shared by API validation, web forms, mobile forms
   ↓ consumed by
apps/web Route Handlers, apps/mobile, packages/api-client
```

Canonical status vocabularies (member, membership, no-show case, payment, add-on order, notification, follow-up outcome — `docs/data-model.md`) live at the top of this chain as Postgres enums. They are never hand-written as TypeScript constants (`docs/decisions.md` ADR-021) — that would be a second, driftable source of truth for exactly the kind of thing `docs/registry.md` exists to prevent duplicating.

`packages/shared/src/config/constants.ts` holds everything that is genuinely **not** part of this chain: product name, default timezone/currency, supported locales, reminder-day offsets, trial length, tier prices, the fixed role list.

## Boundaries (enforced by `dependency-cruiser`, `.dependency-cruiser.mjs`)

- **`packages/shared` imports nothing platform-specific**: no Node core builtin, and no npm package it doesn't itself depend on — `next`, `react-dom`, and anything similar are unresolvable under pnpm's strict per-package `node_modules`, which is exactly the mechanism the `dependency-cruiser` rule keys on (`couldNotResolve: true`, not a path match — see `docs/decisions.md` ADR-022a for why the path-match version silently never fired). Its `tsconfig.json` also excludes `DOM` from `lib`, so `document`/`window`/`localStorage` fail to typecheck there. It is consumed by web, mobile, and Edge Functions — a platform leak here is invisible until Phase 7 tries to build the mobile app against it, which is the worst possible time to find out (`docs/decisions.md` ADR-022).
- **`packages/db` is generated-output-only.** Nothing imports application code into it; nothing hand-edits its one file.
- **Layer direction**: `packages/db` and `packages/shared` never import from `apps/*`. An app may import from any package; packages never import from apps. The master prompt §10 names this class of rule `db ↛ ui` and also `features/* ↛ each other`; neither is implemented under those names because neither layer exists yet (there is no `ui` package and no `features/` directory). `packages ↛ apps` is the same invariant expressed over the layers that do exist — when `features/` appears in Phase 3+, add its sibling-isolation rule then.
- **`process.env` is read in exactly one file**, `packages/shared/src/config/env.ts` — everywhere else imports its validated exports (`no-restricted-properties`, `AGENTS.md`).

## Quality bars

The Gauntlet Loop's blind critic compares our work against a **named, fetchable, comparable** reference — never against the direct competitors. Beating ₹89/month Indian gym software proves nothing; competitors are the feature-completeness reference only. Capture these with Playwright MCP from public surfaces, supplemented by published UI reference libraries where a product is behind a login. **Never authenticate into third-party accounts.**

| Surface | Bar |
|---|---|
| Owner web dashboard | Linear — speed, keyboard-first, density without clutter |
| Payments, renewals, receipts | Stripe Dashboard — payment states and failures legible at a glance |
| Member streak & history | Strava — habit made visible without shaming a missed day |
| Member dark data display | Whoop / Oura |
| Member payment flow | Revolut — minimum taps, unambiguous states |
| Front desk | Square POS — fast, tablet-first, forgiving under pressure |
| Super Admin fleet view | Vercel / Stripe Connect platform view |
| Gym onboarding wizard | Stripe onboarding — long setup that never feels long |
| QR check-in | A metro gate — sub-second scan to confirmation. Latency *is* the design |

For **backend** phases the bar is measurable rather than visual: zero visible-vs-holdout gap, Stripe-grade API ergonomics (typed error envelopes, idempotency keys, predictable pagination, errors that say how to fix themselves), the p95 latency budget from Mumbai, and a green pgTAP isolation suite.

## 2026 design direction (Phase 7, not before)

Dark-first with a refined light mode. Spatial depth and subtle tactile surfaces rather than flat cards. Thumb-optimised reach on mobile. Purposeful microinteractions and haptics — especially the check-in confirmation. Large numerals and high contrast for a gym floor. Gesture-first navigation. Expressive but restrained motion. Inclusive accessibility as a requirement, not a pass. The owner dashboard prioritises actionable lists over decorative charts. Clear English/Hindi labels and rupee amounts.

## The four journeys (E2E, gate 32)

These are what Playwright must cover end to end. They are the product, expressed as tests.

- **A — Healthy member:** QR check-in → streak update → continued visits → reminder 7 days before expiry → plan selection → payment → membership extends *only* after verified payment.
- **B — Silent churn:** member stops attending → daily scan reaches threshold → appears in red list → staff contacts and records reason → follow-up or approved pause scheduled → return check-in resolves the case and records recovery.
- **C — Add-on conversion:** member browses → relevant optional plans shown → reviews price, trainer and validity → payment verified → session/plan usage becomes visible → owner sees utilisation, not just revenue.
- **D — Front-desk assisted:** staff searches by mobile or ID → assisted check-in with reason → member receives confirmation → audit log shows who changed the record.

## Test layers

| Layer | Tool | Covers |
|---|---|---|
| Database | pgTAP | RLS, tenant isolation, constraints, triggers |
| Unit | Vitest | Streak calculation, absent-days, money, timezone maths |
| Integration | Vitest against a real local Supabase (`supabase start`) — **not mocks** | API contracts, state machines, idempotency |
| E2E | Playwright (MCP to author, CI to run) | The four journeys above |
| Load | k6 | 100 gyms × 500 members, morning check-in spike |
| Holdout | Same runners, CI-only, separate private repo | Anti-gaming signal |

## Session hygiene

One feature per session. `/clear` between features. Archive the OpenSpec change before stopping — a change that never archives leaves the next session reading a stale `changes/` entry instead of current `specs/` truth. You have ample context in a 1M-token window; do not stop or suggest a new session on account of context limits (this deliberately reverses the master prompt's earlier "restart at ~70% context" guidance, which was calibrated for smaller models and triggers a known context-anxiety failure mode).
