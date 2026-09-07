# Phase 1 agent brief (supplement to openspec/changes/0001-data-model/cluster-brief.md)

Repo: `C:\Users\Harsh\Desktop\gymloop`. Branch: `main`. You are one of several agents
working in parallel on disjoint files.

## Read first, in this order

1. `AGENTS.md`
2. `openspec/changes/0001-data-model/cluster-brief.md` — the shared brief. Every constraint in it binds you.
3. `docs/data-model.md` → `## Conventions (the contract)` **in full**, then only your cluster's
   subsection of `## Tables`, then `## Enums`.
4. `openspec/changes/0001-data-model/specs/<your-capability>/spec.md` — the EARS requirements you are held to.
5. `docs/domain-rules.md` — the requirement IDs your cluster cites.
6. `docs/registry.md` — before writing anything.

Do **not** read `MASTER-BUILD-PROMPT.md`. Do **not** read another cluster's files.

## Absolute constraints

- **Never use the Supabase MCP server** (`mcp__plugin_supabase_supabase__*`). It is authenticated to a
  different Supabase account and a different project; using it would silently hit the wrong database.
  Catalogue questions go through the CLI, read-only: `supabase db query --linked "select ..."`.
- **Never run `supabase db push`, `supabase db reset`, `supabase link`, or any mutating
  `supabase db query`.** CI applies migrations on merge to `main`. The Cloud schema is currently
  **empty** — no tables, no enums — and stays that way until CI applies the first migration.
- **Never commit or push to the `gymloop` repo.** The orchestrator commits, in the order the
  test-immutability gate requires. Leave your files in the working tree and report what you wrote.
  (Holdout authors are the one exception and are told so explicitly.)
- **Never hand-edit `packages/db/types/database.ts`.**
- No `eslint-disable`, no `@ts-ignore`, no `knip` ignore, no nested ESLint config, no magic number
  outside `packages/shared/src/config/constants.ts`. If a rule blocks something legitimate, that is a
  finding to report to the orchestrator, not a comment to add.
- If the contract in `docs/data-model.md` is wrong or under-specified, that is a **finding for the
  orchestrator**, not an edit. Report it; do not change that document.

## pgTAP file mechanics (test authors)

`scripts/check-pgtap-rollback.mjs` strips comments, splits the file on `;`, uppercases each
fragment, and fails CI if the first statement is not `BEGIN`, the last is not `ROLLBACK`, or any
statement is exactly `COMMIT` or exactly `END`. Therefore:

- First statement `begin;`. Last statement `rollback;`. Nothing after it.
- **No `do $$ ... end $$;` blocks** — the trailing `end` fails the check even though the SQL is valid.
  Write plain SQL and pgTAP functions only.
- `select plan(N);` early, `select * from finish();` immediately before `rollback;`. **N must equal the
  number of assertions exactly** — a wrong count fails the file even when every assertion passes.
- Second statement: `set local search_path = extensions, public;` (pgTAP lives in `extensions`).
- The role/claim idiom is fixed in `docs/data-model.md` → "How a pgTAP test assumes a role". Use it
  verbatim: fixtures inserted as the owner (RLS does not apply — the contract forbids
  `force row level security`), then `set_config('request.jwt.claims', ...)` + `set local role authenticated`,
  then `reset role` and `select set_config('request.jwt.claims', '', true)`.
- Asymmetry that catches people out: an RLS policy does **not** raise on `select`/`update`/`delete`, it
  filters — assert **zero rows** / row unchanged. A failing `with check` on `insert` **does** raise
  `42501`. Refused-for-want-of-privilege is also `42501`. Exclusion violation `23P01`. Bad uuid cast `22P02`.
  Check constraint / not-null violation `23514` / `23502`. Unique violation `23505`. FK violation `23503`.
- Assert privileges with the three-argument form, e.g.
  `has_table_privilege('authenticated', 'public.payments', 'DELETE')`, so the assertion does not depend
  on the session role.
- Name the requirement id (`ATT-004`, `PAY-008`, `INT-001`, …) or the spec scenario in each assertion's
  description string. Do not restate the requirement text.
- Use fixed uuid literals for fixtures, prefixed by gym (`a0000000-…` for gym A, `b0000000-…` for gym B)
  so a failure names its row. Use `gym_code` values unique to your file (six upper-case alphanumerics)
  so two files never collide if they ever run in one transaction.
- **Your assertions are expected to FAIL when you write them.** Nothing they reference exists yet. That
  is the point of writing them first. Never weaken an assertion so it would pass against an empty schema.
