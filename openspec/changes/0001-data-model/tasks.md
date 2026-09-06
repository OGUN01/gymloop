# Tasks — 0001-data-model

Seven migrations. One lands alone and serially; six fan out in parallel and land one at a time behind it. A cluster is not done until the `db.yml` run of the push that carried it is green in all four jobs — `pgtap-rollback`, `migrate`, `schema-drift`, `pgtap` — and a green tick is not the evidence, the log is.

Each cluster is two commits in one push (ADR-038): the pgTAP tests, then the migration. `check-test-immutability` is a per-commit gate, so the order in history is what it checks.

## 1. Contract (serial, before any fan-out)

- [x] 1.1 Reconcile the interrupted run's uncommitted contract: read it as a blind critic, keep what is right, fix what is wrong.
- [x] 1.2 Write the missing table list into `docs/data-model.md` — every table, its columns, tenant path, enums, constraints, indexes.
- [x] 1.3 Fix the contract's own defects found on that read: `member_devices` missing from the table list, the tenancy spec's foreign-key index scenario contradicting index rule 2, `design.md` describing a pull-request flow the owner replaced with trunk-only, `ROLES`/`Role` still present after ADR-031 retired them.
- [x] 1.4 Number the two decisions that had none: ADR-037 (the privilege contract, its `pg_default_acl` basis re-verified against Cloud) and ADR-038 (two commits, one push, and the red pgTAP run bought once).
- [x] 1.5 Push the contract to `main` and confirm CI green.
- [x] 1.6 `tenancy` cluster: blind visible pgTAP author, blind holdout pgTAP author, implementer — all three from the spec, none reading the others.
- [x] 1.7 Orchestrator review of the contract migration against the contract document, line by line, plus an ADR-042 replay of the migration against all four visible pgTAP files inside `begin … rollback` on Cloud: 130 assertions, 0 failures, and `information_schema` verified empty afterwards.
- [x] 1.8 Push tests alone; the red `db.yml` run is **34047023577** — `pgtap` FAIL, reason `function plan(integer) does not exist`, on all four visible files *and* both holdout files, which is also the first proof that the holdout half of the job really runs. `pgtap-rollback`, `migrate` and `schema-drift` green in the same run, so the job discriminates rather than failing always. Then push the migration.
- [x] 1.9 Regenerate `packages/db/types/database.ts` from Cloud after the apply; `schema-drift` green in run 34047869109.

## 2. Fan-out clusters (parallel build, serial landing, in dependency order)

Each: blind visible pgTAP author · blind holdout pgTAP author · implementer · blind critic. Each agent searches `docs/registry.md` before writing and registers what it adds.

- [x] 2.1 `membership+money` — 6 enums, 11 tables. Depends on tenancy.
- [ ] 2.2 `attendance` — 1 enum, 4 tables. Depends on `memberships`.
- [ ] 2.3 `catalogue` — `btree_gist`, 3 enums, 3 tables. Depends on `payments`.
- [ ] 2.4 `retention` — 3 enums, 2 tables. Depends on tenancy only.
- [ ] 2.5 `comms` — 3 enums, 6 tables. Depends on tenancy only.
- [ ] 2.6 `platform` — 3 enums, 5 tables. Depends on tenancy only.

## 3. Seed and close

- [ ] 3.1 `supabase/seed.sql` — idempotent, the exact demo gym `docs/data-model.md` specifies, applied only by `gh workflow run seed.yml` (ADR-034).
- [ ] 3.2 Final full pgTAP run on `main`, visible plus holdout, every table.
- [ ] 3.3 Final regeneration of the generated types; `schema-drift` green.
- [ ] 3.4 Blind final critic against the backend bar: green isolation suite on every table, every table isolated under every role including a missing claim, zero visible-versus-holdout gap, Supabase RLS best practices.
- [ ] 3.5 Archive: fold into `openspec/specs/`, update `docs/registry.md` (enums from the generated types, the three `app` functions), `docs/gates.md` rows 6–11 with the CI run ids, `docs/data-model.md`, `docs/decisions.md`. Run report as the archived change's `README.md`.
