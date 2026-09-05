---
name: db-migration
description: Fires when the user asks to add or change a database table, column, enum, index, or trigger — anything that needs a Supabase migration. Expects the shape of the change (which table/enum/column, and why) as input. Do not use this for RLS-policy-only changes with no schema change — use rls-policy instead.
---

# DB migration

Every migration in this project carries all of the following, in this order — a migration missing any of them is incomplete, not "good enough for now":

1. **`tenant_id`** — every new table either has one (referencing `organizations`) or is reachable via exactly one JOIN to a table that does. No table is exempt without a documented reason in `docs/decisions.md`.
2. **RLS policy** — enabled on the new table from the same migration that creates it, never a follow-up. Tenant id is read from the JWT claim, never a per-row subquery (`docs/security.md`).
3. **Index** — every column referenced in an RLS policy predicate is indexed in the same migration.
4. **pgTAP test** — a cross-tenant leak test for the new table (Gym A cannot read/write Gym B's rows) and a constraint/trigger test for anything the migration adds. Written before or alongside the migration, not after.
5. **Regenerate types** — after `supabase start`, `supabase gen types typescript --local > packages/db/types/database.ts` (not `--linked` — the two emit different template output even against an identical schema, and CI's drift check validates against `--local`; see `docs/decisions.md` ADR-024). Never hand-edit that file.
6. **Register** — any new enum, table-derived type, or constant this migration makes possible goes into `docs/registry.md` in the same commit.

Migrations are forward-only and applied by CI only — write the migration file, do not run `supabase db push` against the shared project from a local session unless you are deliberately testing against `supabase start`'s local instance first. If the new table introduces or changes a status vocabulary, update `docs/data-model.md`'s canonical list and write the legal-transition table + illegal-transition tests (gate 14, `docs/gates.md`) in the same change.
