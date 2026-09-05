## Why

Gymloop is a production multi-tenant SaaS, built across many future agent sessions that will not have read `MASTER-BUILD-PROMPT.md`. Coding-agent output degrades measurably from roughly 65% context fill, and errors compound because a session's own output becomes its next context — so a single session cannot build this system, and every session after this one must work from files, not from memory or from a 367-line bootstrap prompt. Right now no such files exist: the working directory holds only `.env.local`, `.gitignore`, and a `supabase/.temp/` link record. This change creates the source of truth those future sessions need, before any product feature is built.

## What Changes

- Monorepo bootstrap: pnpm + Turborepo workspace, `apps/web` (minimal, real) and `packages/{shared,db}` (real); `apps/mobile` and `packages/api-client` explicitly deferred (Phase 7 / Phase 2) rather than stubbed, to keep the `knip` unused-export gate meaningful from day one.
- `packages/shared/src/config/{constants,env}.ts`: the single source for magic values and for env-var access, both zod-validated where applicable, both registered in `docs/registry.md`.
- Supabase project linked and initialized (`supabase init`), first `supabase gen types` run against the (currently empty) `gymloop` schema, proving the generated-types chain end to end before Phase 1 schema work depends on it.
- Doc framework: `CLAUDE.md` + `AGENTS.md` (routing table, hard rules), seven `docs/*.md` files populated with the real content from the master prompt (architecture, data model, domain rules in EARS, security, registry, decisions, gates), and five `.claude/skills/*/SKILL.md` procedure files.
- OpenSpec adopted as the change-tracking tool (`openspec/specs/`, `openspec/changes/`), this proposal being its first change.
- CI: one GitHub Actions job per gate (typecheck, lint, knip, jscpd, dependency-cruiser, registry-lint, build, test, test-immutability, schema-drift, holdout-clone), each proven to actually fail on a deliberately bad commit rather than merely configured.
- **BREAKING**: none — there is no prior implementation to break.

## Capabilities

No product capability is introduced or modified — see `skip_specs_reason` in `.openspec.yaml`. This change is scaffolding: repo layout, CI gates, and documentation, with no application behavior for a spec to describe. The first product capability spec is opened in Phase 1 (`0001-data-model`).

## Impact

- **New:** `apps/web`, `packages/shared`, `packages/db`, `docs/`, `.claude/skills/`, `openspec/`, `.github/workflows/`, `scripts/{registry-lint,check-test-immutability}.mjs`, root workspace config.
- **Infrastructure:** `github.com/OGUN01/gymloop` gains its first commits and two repo secrets (`SUPABASE_ACCESS_TOKEN`, `HOLDOUT_DEPLOY_KEY`); `github.com/OGUN01/gymloop-holdout` gains a deploy key and a minimal test scaffold so the holdout-clone gate has something real to run.
- **Not touched:** application features, business logic, UI, database migrations, seed data — all explicitly out of scope for this phase (`MASTER-BUILD-PROMPT.md` §3).
- **Follow-ups surfaced, not fixed here:** Docker daemon not running locally (blocks `supabase start` / pgTAP specifically, once Phase 1 adds real tests — the schema-drift gate no longer needs Docker at all, see `docs/decisions.md` ADR-024); k6 not installed (blocks the load layer until Phase 8); `packages/api-client`'s generator tool is unnamed by the master prompt and left as an open question for Phase 2.
