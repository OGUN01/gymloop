# The 33 gates

From master prompt §11. **Automated** means a CI job or tool fails the build on violation, not that a human remembers to check. **Status** is reported honestly per `AGENTS.md`'s grounding rule — most product-correctness gates have nothing to gate yet in Phase 0, which builds infrastructure, not product. What Phase 0 proves is that the *mechanism* for catching a violation works (`openspec/changes/archive/2026-09-06-phase-0-foundation/` records which gate was proven against a deliberately bad commit, with captured CI output).

Note on `knip`, since the spec bills it as "unused exports/files/deps": in this repo it reliably catches unused **files** and **dependencies**, but **not unused exports**, because `packages/shared` and `packages/db` declare `main` pointing at a barrel that `export *`s everything — knip treats an entry file's exports as public API by design. The "built twice, wired once" protection for *exports* therefore rests on `registry-lint`, not on knip. Verified by appending an unused export to `constants.ts` (knip clean) versus adding an orphan file (knip red).

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
| 6 | Every table has `tenant_id` (or reachable via one) with RLS enabled | Yes (once tables exist) | pgTAP suite, `db.yml` | **Built.** All 36 Phase 1 tables have row security enabled. Two are deliberate tenant exemptions recorded in ADR-033 (`platform_users`, `audit_log`) and a pgTAP meta-test asserts there is no third; every other table is `direct` |
| 7 | pgTAP cross-tenant leak suite per table | Yes (once tables exist) | `supabase/tests/`, `db.yml` `pgtap` job — runs against the Cloud project after `migrate`, never concurrently (workflow `concurrency`), every file `BEGIN … ROLLBACK` (enforced by `pgtap-rollback` / `scripts/check-pgtap-rollback.mjs`, ADR-030) | **Built and wired.** All 36 tables have at least one cross-tenant SELECT assertion — 18 visible files in `supabase/tests/` plus 8 holdout files, run by `db.yml`'s `pgtap` job after `migrate`, every file `BEGIN … ROLLBACK`. **Proven green** in run `34092121483`: visible `Files=18, Tests=793, Result: PASS`, holdout `Files=8, Tests=790, Result: PASS`, with the demo gym seeded in the same database — so it is green against a project that holds rows it did not write, not only against an empty one (ADR-050). It also discriminates: the twelve runs before it were red, and the run immediately before this one failed exactly 14 assertions that assumed an empty table |
| 8 | RLS columns indexed, tenant read from JWT claim not a per-row subquery | Yes (once policies exist) | pgTAP + migration review | **Built, and re-proven after Phase 2 widened the predicates.** Every tenant policy calls `app.current_tenant_id()` wrapped in `(select …)`, never a per-row subquery. Phase 2 added a role term and, on fourteen tables, a `member_id` term — so index rule 3 stopped being discharged automatically by rule 1. Every member-gated table was measured against the live schema and already led an index with `member_id` or `(tenant_id, member_id)`, so the matrix added no index; `04_contract_meta` now carries a general meta-assertion that any column named in any policy predicate leads an index or sits second in a tenant-leading one, so the next policy term with no index behind it fails on the day it merges |
| 9 | Forward-only migrations applied by CI | Yes | `db.yml` `migrate` job: `supabase db push --linked` on merge to `main`, in merge order; `--dry-run` only on a PR. Sessions never push (ADR-030 resolved OPEN-005) | Wired; no migrations exist yet to apply. Not yet proven red — the first real migration in Phase 1 is the proof |
| 10 | DB enums generate TS types, drift fails CI | Yes | `db.yml` schema-drift job (`supabase gen types --project-id` against Cloud, vs committed), run after `migrate`; on a PR that changes `supabase/migrations` it is skipped with a notice and verified on the post-merge run of `main` (ADR-030) | **Proven failing** on `chore/gate-proof`: authenticated, generated from Cloud, and caught exactly the hand-edit (`-export type GateProofBogusHandEdit = true;`). Green on `main` in the same round, so it distinguishes good from bad rather than failing always. `packages/db/types/database.ts` is now generated from the full 36-table Phase 1 schema (24 enums), and `schema-drift` is green against it in run `34092121483` — and caught a real drift two runs earlier, when the ADR-049 invoice key flipped the generated relationship off `isOneToOne` |
| 11 | A full demo gym seeded by one command | Yes (mechanism, once written) | Seed script | **Built.** `supabase/seed.sql` exists and is applied by one command, `gh workflow run seed.yml`. **Proven** in run `34091063459`: 1 organisation, 1 default branch, 4 active plans, 4 staff, 30 members, 585 attendance rows, 33 payments, 6 no-show cases, 3 add-on orders, leads at 6 distinct stages, 6 members with a live membership and no attendance in 10 days, 5 active memberships expiring within 7 days — every scenario in `demo-seed/spec.md`, measured rather than assumed. Idempotency proven by a second dispatch, run `34091157183`: identical counts |

## Backend correctness

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 12 | Zod validation and a typed error envelope on every endpoint | Yes (once endpoints exist) | Route Handler convention + review; no lint rule enforces this mechanically yet | **MET (Phase 3).** Every handler validates through a declared schema — `checkInRequestSchema` and the three in `packages/shared/src/api/memberships.ts` for the shapes mobile will post too, and the member form's own reader for the one that needs the generated `member_status` enum. **Two answers, not one**: a body that is not a form at all gets the envelope (the case two handlers used to answer with a 500), and a field error gets a 303 back to the form — with `?error=<code>` on the membership forms and a one-shot `HttpOnly` cookie on the member form, whose fields are personal data a URL would write into logs, history and `Referer`. Still no lint rule; `openspec/.../staff-console/spec.md` states the contract and the tests assert it. OPEN-002 (`packages/api-client`) remains open |
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
| 24 | Rate limiting and Turnstile on OTP, signup, and public endpoints | Yes (once written) | Cloudflare config + Route Handler middleware | N/A — **moved to Phase 3.** Phase 2 configured phone-OTP sign-in but no SMS provider credential exists, so no OTP can be sent and there is nothing to rate-limit yet. Supabase's own `[auth.rate_limit]` settings are the floor until then |

## Reliability & scale

| # | Gate | Automated? | Enforced by | Status |
|---|---|---|---|---|
| 25 | p95 latency budget asserted in CI | Yes (once endpoints exist) | Load-test assertions | N/A — endpoints don't exist yet |
| 26 | No N+1, cursor pagination on every list endpoint | Yes (once endpoints exist) | Code review + integration test query counts | **PARTIALLY MET (Phase 3).** The member roster — the only list endpoint that exists — is keyset paginated on `(full_name, id)`, default 50, clamped at 200, with an opaque cursor. The total sort order is the load-bearing part: on `full_name` alone, two members with the same name sit in an order the planner may change between requests, and a page boundary between them skips one and repeats the other, silently, only for gyms that have a duplicate name. **Re-check when Phase 4 adds the no-show list and Phase 5 the payment history** — this row is met for what exists, not for what is coming |
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

### Round 2: every gate re-proven by failure *reason*, not exit code

The first round exposed that a red job proves nothing on its own — two gates were red while testing nothing. So a second proof run (PR #2, `chore/gate-proof-2`) re-verified **all eleven** mechanisms against the stricter standard, and added `escape-hatches`, which had never been proven in CI at all. Each reason below is quoted from that run's CI logs:

| Gate | Failure reason in CI |
|---|---|
| `lint` | `No magic number: 149900` — ESLint genuinely executed this time |
| `typecheck` | `error TS2322: Type 'string' is not assignable to type 'number'.` |
| `knip` | `Unused files (8)` |
| `jscpd` | `found too many duplicates (10.5%) over threshold (0.0%)` |
| `depcruise` | `packages-not-to-apps: packages/db/gp2-layer.ts → apps/web/app/page.tsx` **and** `shared-not-to-unresolvable: …__gp2_portability__.ts → next/headers` |
| `registry-lint` | `gp2NeverImported` (+3 more) missing from the registry |
| `escape-hatches` | `suppression directives found (AGENTS.md hard rule #4): __gp2_escapehatch__.ts:1 eslint-disable` |
| `schema-drift` | committed types `out of date` — caught `Gp2BogusHandEdit` |
| `check` (test-immutability) | `touches both test files and implementation files without a \`spec:\` commit-message prefix` |
| `holdout` | `AssertionError … 'paid' !== 'pending'` from the private holdout repo |
| `build` | fails on its own `tsc`, not a cascade (turbo dependency removed, ADR-028) |

`test` and `pgtap` stayed **green** in the same run. That is the point of the exercise: a gate that fails on everything is jammed, not wired.

### The strongest evidence was unplanned

Immediately after round 2, `test-immutability` went red on `main` — not on a planted violation, but on commit `4d71390`, which changed `constants.ts` and added `__tests__/constants.test.ts` together with no `spec:` prefix. Its author was the same session that built the gate.

It was a true positive twice over. The methodology (master prompt §9) requires tests committed **red first**, with the implementer then forbidden from touching test files; combining them in one commit is precisely what the rule exists to prevent. And because that commit changed how PAY-001 is *encoded* across docs, code and tests, it was a specification change — so `spec:` was the correct prefix and simply wasn't used.

Eleven planted violations prove the gates fire on purpose-built bad commits. This one proves the gate fires on a real mistake nobody intended to make, which is the case that actually matters. The failed run stays in history; the range moves on with the next push, so `main` returns to green without rewriting pushed history.

Worth noting what `escape-hatches` caught that nothing else would: ESLint reported the planted directive only as an *unused* `eslint-disable` **warning**, which does not fail a build. Without this gate, a suppression comment would have passed CI silently.

**One caveat worth carrying forward:** the first proof run's `lint` and `test` failures were *false* — `turbo.json` made both depend on `^build`, so a broken build aborted the graph before ESLint or Vitest ran. A fresh-context critic caught it; ADR-028 fixed it. The lesson generalises: a red job is not evidence a gate works until you read *why* it went red.
