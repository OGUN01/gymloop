# Holdout pgTAP author brief — Gymloop Phase 1

You are a **holdout** test author. Your suite is the anti-gaming signal (`AGENTS.md` hard rule #10):
it is written blind from the EARS spec, nobody implementing Gymloop ever reads it, and a gap between
its pass rate and the visible suite's is treated as evidence the implementation was fitted to the
visible tests rather than to the spec.

## Two blindness rules that define your job

1. **Never read `supabase/tests/**` in the gymloop repo.** That is the visible suite, written by a
   different agent from the same spec. If you read it you become a copy of it and the signal is gone.
   Do not read it to "check for overlap" — overlap is fine, correlation is the failure.
2. **Never read any implementation.** `supabase/migrations/` does not exist in the tree during your
   run and the Cloud schema is empty. Write from the spec and the contract only.

## Read first, in this order

1. `C:\Users\Harsh\Desktop\gymloop-wip\agent-brief.md` — the shared brief, including the pgTAP file
   mechanics. Every constraint in it binds you, **except** that you write outside the gymloop repo.
2. `AGENTS.md`
3. `docs/data-model.md` → `## Conventions (the contract)` in full, then your cluster's subsection of
   `## Tables`, then `## Enums`.
4. `openspec/changes/0001-data-model/specs/<your-capability>/spec.md`
5. `docs/domain-rules.md`

## Where your file goes

Write **one** file to `C:\Users\Harsh\Desktop\gymloop-holdout-staging\<given-filename>`. Do not write
anything into the gymloop repo. Do not run git. The orchestrator pushes your file to the private
holdout repository (`github.com/OGUN01/gymloop-holdout`) at the moment your cluster's migration lands,
without reading it.

## What makes a holdout file good

- It tests **the requirement**, not the table. Where the visible suite is likely to assert "the column
  exists with this type", assert the **behaviour the spec promises**: that the constraint actually
  refuses the bad row, that the isolation actually holds, that the append-only grant actually stops an
  update. Prefer round-trip assertions (insert → observe → assert) over catalogue introspection.
- It covers the cases an implementer fitting to a visible suite would miss: the empty-string claim, the
  malformed claim, the boundary value on each range check, the *second* half of every uniqueness rule
  (the same key in a different tenant must be **accepted**), the null case of a partial unique index.
- Every assertion names the requirement id (`PAY-008`, `NSH-004`, `INT-001`, …) or the spec scenario.
- It is red when you write it and it must stay honest: never weaken an assertion so it would pass
  against an empty schema.

## The mechanics that fail CI if you get them wrong

- First statement `begin;`, last statement `rollback;`, nothing after it.
- **No `do $$ ... end $$;` block** — the checker splits on `;`, uppercases, and rejects a statement that
  is exactly `COMMIT` or exactly `END`.
- `select plan(N);` early, `select * from finish();` immediately before `rollback;`. **N must be exact.**
- Second statement: `set local search_path = extensions, public;`.
- Use fixed uuid literals prefixed `c0000000-` (gym A) and `d0000000-` (gym B) and gym codes beginning
  `H` — the visible suite uses `a…`/`b…`, and distinct fixtures make a failure name its suite.
- Never use the Supabase MCP server. Never run any mutating `supabase` command. Read-only
  `supabase db query --linked "select ..."` is permitted.
