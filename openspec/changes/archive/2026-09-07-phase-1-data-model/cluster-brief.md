# The brief every Phase 1 cluster agent was given

Phase 1 fanned out into six clusters after the contract merged. Each cluster had four agents — a visible pgTAP author, a holdout pgTAP author, an implementer, and a blind critic — and none of them read the orchestrator's prompt. This file is the shared half of what they *were* given, kept with the change so the archived record shows what each agent actually knew rather than what it was assumed to know.

The cluster-specific half (which tables, which enums, which requirement IDs) was appended per agent and is not repeated here.

## Read first

- `AGENTS.md` — the eleven constitutional rules.
- `docs/data-model.md` — `## Conventions (the contract)` **in full**, then only your cluster's subsection of `## Tables`, plus `## Enums`.
- `openspec/changes/0001-data-model/specs/<your-capability>/spec.md` — the EARS requirements you are held to.
- `docs/domain-rules.md` — the requirement IDs your cluster's tables cite.
- `docs/registry.md` — before writing anything, and again to register what you add.
- `.claude/skills/db-migration/SKILL.md` and `.claude/skills/rls-policy/SKILL.md`.

Do **not** read `MASTER-BUILD-PROMPT.md`. Do **not** read another cluster's migration or another cluster's tests.

## Absolute constraints

1. **Never use the Supabase MCP server** (`mcp__plugin_supabase_supabase__*`). It is authenticated to a different Supabase account and a different project. Every Supabase operation goes through the `supabase` CLI.
2. **Never run `supabase db push`, `supabase db reset`, or any mutating `supabase db query`.** Migrations reach Cloud only through the `migrate` job in `.github/workflows/db.yml`, on merge to `main`, in merge order. Forward-only: a bad migration is fixed by a new migration, never by editing or deleting one that merged. A read-only `supabase db query --linked "select ..."` is permitted for catalog questions.
3. **Every pgTAP file is wrapped `BEGIN … ROLLBACK`.** The suite runs against the one shared Cloud database; there is no disposable local instance. `scripts/check-pgtap-rollback.mjs` fails CI on any file whose first statement is not `BEGIN`, whose last is not `ROLLBACK`, or which contains a `COMMIT` or a bare `END`.
4. **Tests and implementation are separate commits.** `scripts/check-test-immutability.mjs` rejects any commit touching both `supabase/tests/**` and an implementation file (`.sql` under `supabase/migrations/`, or any `.ts`) unless its message begins with `spec:`. Two commits per cluster: the tests, then the migration.
5. **No escape hatches, anywhere, ever**: no `eslint-disable`, no `@ts-ignore`, no `knip` ignore entry, no nested ESLint config. `scripts/check-escape-hatches.mjs` fails CI on any of them. If a rule genuinely blocks something legitimate, that is a finding to report, not a comment to add.
6. **`packages/db/types/database.ts` is generated. Never hand-edit it.** It is regenerated from Cloud after the migration merges, by the orchestrator, in a follow-up commit.
7. **Every exported TypeScript symbol goes in `docs/registry.md`** in the same commit (`registry-lint`). The registry also carries the database objects this phase adds — enums, the `app` schema functions — so a second agent cannot write a second copy of one.
8. **Money is integer paise in a `bigint` column** with a `currency` column beside it. Never `numeric`, never floating point.
9. **Every table carries `tenant_id` with RLS enabled in the same migration that creates it, and every RLS-referenced column is indexed in the same migration.** The only two exemptions are `platform_users` and `audit_log`, both already recorded in ADR-033. Do not add a third.

## What each role does

**Visible pgTAP author.** Writes `supabase/tests/<NN>_<cluster>_*.sql` from the EARS spec, before any DDL exists, without seeing the migration. Every assertion traces to a scenario in the spec or a requirement ID in `docs/domain-rules.md` — name the id in the assertion's description, do not restate the requirement text. The tests are expected to fail when written: nothing they reference exists yet. That is the point.

**Holdout pgTAP author.** The same job, in `github.com/OGUN01/gymloop-holdout` under `supabase/tests/`, never in this repo. Works from the same EARS spec and never sees the visible tests. It is the anti-gaming signal: if the visible suite is green and the holdout suite is red, the implementation was fitted to the tests rather than to the spec.

**Implementer.** Writes exactly one migration file (created with `supabase migration new <name>` — never invent the timestamp), makes the tests pass, and may not touch a test file. Follows the contract's statement order: extensions → enum types → tables → constraints → indexes → `enable row level security` → policies → privileges → triggers.

**Blind critic.** Fresh context, no build history. Judges the migration against the spec and the contract, not against how it was built. Its bar is the backend one in `docs/architecture.md`: zero visible-versus-holdout gap, green isolation suite, and Supabase's own RLS guidance.

## What no cluster agent may do

Add a `security definer` function. Add a view. Add a trigger other than the shared `updated_at` one the contract defines. Write business logic, a state-machine enforcement trigger, or an audit-writing trigger — Phase 1 builds the schema those will later use, and nothing more. Create an enum another cluster already owns (the contract has the ownership table). Edit another cluster's migration. Change `docs/data-model.md`'s contract section — if the contract is wrong, that is a finding for the orchestrator, not an edit.
