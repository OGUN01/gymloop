# The 33 gates

From master prompt §11. **Automated** means a CI job or tool fails the build on violation, not that a human remembers to check. **Status** is reported honestly per `AGENTS.md`'s grounding rule — most product-correctness gates have nothing to gate yet in Phase 0, which builds infrastructure, not product. What Phase 0 proves is that the *mechanism* for catching a violation works (`openspec/changes/archive/2026-09-06-phase-0-foundation/` records which gate was proven against a deliberately bad commit, with captured CI output).

Note: this table is the 33 gates from §11. The separate CI-mechanism table in §10 (knip, jscpd, dependency-cruiser, registry-lint, test-immutability) is the *tooling* — several of those mechanisms enforce more than one numbered gate below.

## Spec & contract

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 1 | EARS requirements approved before code | No — process | Gauntlet Loop step 2 (`openspec` proposal + human approval) | Applied to this change: `proposal.md` preceded all implementation |
| 2 | Every requirement has ≥1 visible and ≥1 holdout test | Partial | Requirement IDs in `docs/domain-rules.md` are the anchor; a coverage check mapping IDs → tests does not exist yet | Phase 1+ — no requirements have implementations yet |
| 3 | CI blocks commits touching tests and implementation together | Yes | `.github/workflows/test-immutability.yml` + `scripts/check-test-immutability.mjs` | **Proven failing** on `chore/gate-proof` |
| 4 | Quality bar captured as real artifacts | No — process | Playwright MCP capture against named bars (`docs/architecture.md`'s quality-bar table, master prompt §9) | Phase 7 — bars named, not yet captured |
| 5 | Blind critic sign-off, exit on win not round count | No — process | Gauntlet Loop step 5 (fresh-context sub-agent, no implementation knowledge) | Applied to this change (Task 9.2) |

## Data & tenancy

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 6 | Every table has `tenant_id` (or reachable via one) with RLS enabled | Yes (once tables exist) | pgTAP suite, `db.yml` | N/A — Phase 1, no tables yet |
| 7 | pgTAP cross-tenant leak suite per table | Yes (once tables exist) | `supabase/tests/`, `db.yml` | N/A — Phase 1 |
| 8 | RLS columns indexed, tenant read from JWT claim not a per-row subquery | Yes (once policies exist) | pgTAP + migration review | N/A — Phase 1 |
| 9 | Forward-only migrations applied by CI | Yes (mechanism) | `db.yml` | Wired, no migrations exist yet to apply |
| 10 | DB enums generate TS types, drift fails CI | Yes | `db.yml` schema-drift job (`supabase gen types --project-id` against Cloud, vs committed) | **Proven failing** on `chore/gate-proof`: authenticated, generated from Cloud, and caught exactly the hand-edit (`-export type GateProofBogusHandEdit = true;`). Green on `main` in the same round, so it distinguishes good from bad rather than failing always |
| 11 | A full demo gym seeded by one command | Yes (mechanism, once written) | Seed script | N/A — Phase 1 |

## Backend correctness

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 12 | Zod validation and a typed error envelope on every endpoint | Yes (once endpoints exist) | Route Handler convention + review; no lint rule enforces this mechanically yet | N/A — Phase 2, no endpoints yet |
| 13 | Idempotency proven by replaying duplicate webhooks, scans, sends | Yes (once written) | Integration tests | N/A — Phase 4/5 |
| 14 | Explicit legal-transition table per state machine plus illegal-transition tests | Yes (once written) | Unit tests per enum in `docs/data-model.md` | N/A — Phase 1+ |
| 15 | Daily scans correct in each gym's timezone, tested across date boundaries | Yes (once written) | Unit tests | N/A — Phase 4 |
| 16 | Money as integer paise with tested rounding | Partial | `PLAN_TIER_PRICES_PAISE` in `packages/shared/src/config/constants.ts` already follows the convention; no rounding logic exists yet to test | Convention established in Phase 0; enforcement Phase 5 |
| 17 | Concurrency: double scan, two staff on one case, simultaneous renewal | Yes (once written) | Integration tests | N/A — Phase 3/4/5 |
| 18 | Offline queue replays exactly-once with an audit stamp | Yes (once written) | Integration tests | N/A — Phase 3 |

## Security & compliance

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 19 | No secrets client-side, env zod-validated, per-gym Razorpay keys encrypted at rest | Partial | `packages/shared/src/config/env.ts` (zod-validated, client/server split, lazy) is real now; Supabase Vault encryption is Phase 5 | Env validation done in Phase 0; Vault encryption N/A yet |
| 20 | Webhook signature verified per gym before any state change | Yes (once written) | Edge Function + tests | N/A — Phase 5 |
| 21 | Never `paid` without a verified provider response, never extend before that | Yes (once written) | State-machine tests (PAY-006–009, `docs/domain-rules.md`) | N/A — Phase 5 |
| 22 | Audit log on every financial, attendance-correction, follow-up, role, and impersonation mutation | Yes (once written) | DB trigger or app-layer write + pgTAP | N/A — Phase 1 (schema)/3+ (data) |
| 23 | DPDP: versioned consent, marketing/service split, withdrawal, export, erasure with legal hold | Yes (once written) | Schema + tests | N/A — Phase 1 (schema)/ongoing |
| 24 | Rate limiting and Turnstile on OTP, signup, and public endpoints | Yes (once written) | Cloudflare config + Route Handler middleware | N/A — Phase 2 |

## Reliability & scale

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 25 | p95 latency budget asserted in CI | Yes (once endpoints exist) | Load-test assertions | N/A — endpoints don't exist yet |
| 26 | No N+1, cursor pagination on every list endpoint | Yes (once endpoints exist) | Code review + integration test query counts | N/A — Phase 3+ |
| 27 | Load test at 100 gyms × 500 members with a morning check-in spike | Yes (once written) | k6 | N/A — Phase 8. **k6 not installed locally** (follow-up, `proposal.md` Impact) |
| 28 | Structured logs carrying `tenant_id`, error tracking, alert thresholds | Yes (once wired) | Sentry + log shipper | N/A — not yet configured, no app runtime code needs it in Phase 0 |
| 29 | Backup and PITR restore drill actually performed | No — operational exercise | Supabase platform backups + a manual drill | N/A — Phase 8 |

## Frontend & UX

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 30 | Every screen enumerates loading, empty, error, permission-denied, and offline states in its spec | No — spec review | UI spec template (Phase 7) | N/A — Phase 7 |
| 31 | WCAG AA contrast, 44px targets, screen-reader labels | Yes (once UI exists) | axe/Playwright a11y assertions | N/A — Phase 7 |
| 32 | Playwright E2E covers all four journeys (A–D, master prompt §9) | Yes (once written) | `tests/e2e/` | N/A — journeys don't exist until Phase 3–6 build them |
| 33 | Blind critic picks ours over the captured bar | No — process | Gauntlet Loop step 5 | N/A — Phase 7 |

## What Phase 0 actually proves

Gates **3** and **10** are proven failing against a real bad commit (PR #1, `chore/gate-proof`) — and, importantly, proven *green on `main` in the same round*, so each distinguishes a good commit from a bad one rather than merely failing always. Gates **1** and **5** are process gates this very change followed. Gate **16**'s convention (integer paise) and gate **19**'s env-validation half are real code, not placeholders. Every other gate is honestly `N/A` until the phase that needs it — a gate marked `N/A` here is not a gap in Phase 0, it is Phase 0 correctly not building product it wasn't asked to build (master prompt §3).

Beyond the numbered 33, Phase 0's own anti-slop CI mechanisms (master prompt §10) were each proven red for their own reason on the same PR: `jscpd` (duplicated file), `knip` (unused files), `dependency-cruiser` (both the layer rule and the `packages/shared` portability rule), `registry-lint` (5 unregistered exports), `lint`/`no-magic-numbers` (`149900`), `typecheck` (a real type error), and the holdout clone-and-run (`AssertionError: 2 !== 3` from a deliberately failing test in the private holdout repo, since reverted).

**One caveat worth carrying forward:** the first proof run's `lint` and `test` failures were *false* — `turbo.json` made both depend on `^build`, so a broken build aborted the graph before ESLint or Vitest ran. A fresh-context critic caught it; ADR-028 fixed it. The lesson generalises: a red job is not evidence a gate works until you read *why* it went red.
