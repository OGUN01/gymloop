# Gymloop — agent instructions

Multi-tenant SaaS for Indian gyms: Super Admin → Gyms (organizations) → Members. Core loop: **record attendance → detect silent-churn risk → contact early → bring the member back → collect renewal on time → deliver add-ons → show the owner what worked.** Every feature serves that loop; decorative dashboards do not.

This file is always loaded and stays small. Everything else is pulled on demand from the table below — read the relevant doc before working in its area, don't rely on memory of this file alone.

## Hard rules (constitutional — violating these fails CI or is simply wrong)

1. **If it is not in `docs/registry.md`, it does not exist.** Before writing any helper, constant, type, hook, or component, search the registry and grep the codebase. Reuse, or record why you couldn't in `docs/decisions.md`. Adding an exported symbol without registering it fails the `registry-lint` CI gate.
2. **Never use the Supabase MCP server on this project.** It is authenticated to a different account (`sageharsh9887@gmail.com`, a different org, a project in `ap-southeast-1`). Calling `apply_migration` or `execute_sql` through it would silently hit the wrong database. All Supabase work goes through the `supabase` CLI, which is correctly authenticated. CI can only use the CLI in any case. Every mutating tool on that server is denied in `.claude/settings.json` — this is the rule with the worst blast radius, so it does not rely on you remembering it.
3. **`process.env` is read in exactly one file**: `packages/shared/src/config/env.ts`. Everywhere else, import its exports (`env()`, `serverEnv()`, `clientEnv()`, `assertEnv()`). Enforced by `no-restricted-properties`.
4. **Every magic number lives in `packages/shared/src/config/constants.ts`.** Enforced by `no-magic-numbers` (scoped: array indexes, default values, enum members, and `0`/`1`/`-1` are exempt — see `docs/decisions.md` ADR-026 for why). If the rule blocks something that isn't actually a magic number, that's a finding to raise, not an `eslint-disable` to add — **no `eslint-disable` comments and no `knip` ignore entries**, anywhere, ever, without explicit sign-off recorded in `docs/decisions.md`. Enforced by `scripts/check-escape-hatches.mjs` (the `escape-hatches` CI job), not by good intentions.
5. **Canonical status vocabularies are Postgres enums**, generated into `packages/db/types/database.ts` by `supabase gen types` — never hand-written TypeScript constants. See `docs/data-model.md` for the vocabularies, `docs/decisions.md` ADR-021 for why.
6. **`packages/db/types/database.ts` is generated. Never hand-edit it.** Regenerate with `supabase gen types typescript --linked` locally (CI uses the equivalent `--project-id pecxrpskmfeuyzngvewq`, because a fresh checkout has no link state — verified byte-identical output). CI diffs it against a fresh generation from Supabase Cloud; drift fails the build.
7. **Migrations are applied by CI only, never by hand.** Forward-only.
8. **Money is integer paise, never floating point**, with an explicit currency and a tested rounding rule.
9. **Every table needs `tenant_id` (or a JOIN to one) with RLS.** Tenant id comes from the JWT claim, never a per-row subquery. RLS-referenced columns are indexed.
10. **Tests derive from the EARS spec before implementation, written by a session that hasn't seen the implementation.** A holdout suite in `github.com/OGUN01/gymloop-holdout` is never seen by the implementer. Test files are immutable to the implementer — a commit touching `tests/**` and `src/**` together needs an explicit `spec:` prefix, signalling a human-approved spec change. In practice this means **two commits**: the test, committed red, then the implementation that turns it green. If you are genuinely changing what a requirement *says* (not just how it is built), that is the `spec:` case. Phase 0 tripped this gate on its own author by combining the two — see `docs/gates.md`, "The strongest evidence was unplanned".
11. **`packages/shared` stays platform-free**: no `next/*`, `react-dom`, or `node:*` imports; no DOM lib. It's consumed by web, mobile, and Edge Functions.

## Session hygiene

One feature per session. `/clear` between features. Archive the OpenSpec change (`openspec/changes/<name>/` → `openspec/specs/`) before stopping — an unarchived change leaves the next session reading stale in-flight state instead of current truth. You have a large context window; don't stop or suggest a new session on account of context limits.

## Methodology

Every unit of work follows the **Gauntlet Loop**, no round-count budget, exits on win: bar (name a fetchable comparable reference) → spec (EARS, human-approved) → tests (visible + holdout, written first, implementation-blind, committed red) → build (make them green, may not touch test files) → gauntlet (fresh-context critic, blind comparison, win or loop) → gates (`docs/gates.md`) → archive (fold into specs, update the registry, `/clear`). If a critic rejects the same dimension three times, that's evidence the requirement is under-specified — escalate to the human, never silently lower the bar.

## Routing table

| Need | Read |
|---|---|
| What phase we're in, which model/effort to use | `docs/roadmap.md` |
| System layers, folder map, API split, dependency boundaries | `docs/architecture.md` |
| Tables, enums, tenancy shape, RLS policy shape | `docs/data-model.md` |
| Every domain/business rule, in EARS, with stable IDs | `docs/domain-rules.md` |
| RLS, DPDP, payment integrity, audit, impersonation | `docs/security.md` |
| Every constant/enum/type/util/hook/component/env var and who uses it | `docs/registry.md` |
| Why a decision was made, rejected alternatives, and open decisions not yet resolved | `docs/decisions.md` |
| The 33 production gates and their current status | `docs/gates.md` |
| How to start a new feature / migration / endpoint / RLS policy / payment flow | `.claude/skills/*/SKILL.md` |
| Current system truth vs. in-flight proposals | `openspec/specs/`, `openspec/changes/` |
| Real values for env vars | `.env.local` (gitignored) — names only in `.env.example` |

## Provisioned infrastructure (do not recreate)

Main repo `github.com/OGUN01/gymloop`; holdout repo `github.com/OGUN01/gymloop-holdout` (CI-only, never read by implementers). Supabase project ref `pecxrpskmfeuyzngvewq`, org `gjjnocawiprbwdkktogn`, region `ap-south-1`. R2 bucket `gymloop-media`.
