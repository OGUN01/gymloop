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
docs/               This layer — on-demand knowledge, pulled when a session needs it, not always loaded.
.claude/skills/     Procedures — progressive disclosure, ~100 tokens each at rest until invoked.
openspec/
  specs/            Current system truth, one capability per file, updated by archiving changes.
  changes/          In-flight proposals; archived back into specs/ on completion.
supabase/
  migrations/       Applied by CI only, never by hand (AGENTS.md hard rule).
  tests/            pgTAP suites.
tests/
  visible/          Tests the implementer sees, derived from EARS specs before implementation.
  e2e/              Playwright, the four journeys (docs/gates.md gate 32).
  load/             k6.
                    The holdout suite lives in a separate private repo (github.com/OGUN01/gymloop-holdout),
                    never here — that is the point of it.
```

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
- **Layer direction**: `packages/db` and `packages/shared` never import from `apps/*`. An app may import from any package; packages never import from apps. (`db ↛ ui` in gate terms — `docs/gates.md` gate 26's spirit extended to the dependency graph itself.)
- **`process.env` is read in exactly one file**, `packages/shared/src/config/env.ts` — everywhere else imports its validated exports (`no-restricted-properties`, `AGENTS.md`).

## Session hygiene

One feature per session. `/clear` between features. Archive the OpenSpec change before stopping — a change that never archives leaves the next session reading a stale `changes/` entry instead of current `specs/` truth. You have ample context in a 1M-token window; do not stop or suggest a new session on account of context limits (this reverses earlier guidance calibrated for smaller models — see `docs/decisions.md`'s build-methodology memory note if this looks surprising).
