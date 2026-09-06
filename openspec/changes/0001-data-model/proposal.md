## Why

Every later phase — identity, check-in, retention scans, money — writes to tables that do not exist yet, and `docs/data-model.md` still says "this file does not yet specify tables or relationships". Until the schema, the seven canonical enums, and Row-Level Security exist and are *proven* to isolate one gym from another under every role (including a missing tenant claim), nothing downstream can be built without inventing its own dialect of the data model. An RLS hole is silent and leaks another gym's members; it has to be closed before any product code touches the database, not discovered after.

## What Changes

- **The table list** — every v1 table, its columns, tenant path, enums, constraints, and indexes — is written into `docs/data-model.md`, closing the gap a Phase 0 blind critic flagged. It is the specification the migrations implement.
- **A contract, fixed before any parallel work**: naming, `tenant_id` placement, timestamp columns, the JWT claim names and their one accessor, the RLS policy template (tenant isolation + the `super_admin`/`platform_support` branch), the index rule, the privilege template, the audit-row shape, and the money-column rule.
- **Forward-only migrations**, applied by CI on merge to `main`, one cluster at a time: tenancy (contract), `membership+money`, `attendance`, `catalogue`, `retention`, `comms`, `platform`. Each table ships with RLS enabled, its RLS columns indexed, and its privileges set in the same migration.
- **The seven canonical status vocabularies as Postgres enums** (member, membership, no-show case, payment, add-on order, notification, follow-up outcome) plus the closed attribute vocabularies the tables need (`app_role`, `organization_status`, `payment_method`, …), each with its legal-transition table where it is a state machine.
- **Phase 2 accommodations, schema only**: `organizations → branches`, and Razorpay mandate tables. No auth hook, no Route Handlers, no UI, no business logic.
- **pgTAP suites** — visible in `supabase/tests/`, holdout in `github.com/OGUN01/gymloop-holdout` — written blind from the EARS specs before the DDL, every file `BEGIN … ROLLBACK`, run against the Cloud project after each merge. CI is extended so the holdout `.sql` files run in the same job.
- **Generated types** regenerated from Cloud after each merge and committed; the `schema-drift` gate is the check.
- **One command seeds a complete demo gym** (`supabase/seed.sql`, idempotent), applied through CI only.
- **BREAKING**: none — no prior schema exists. One Phase 0 constant is retired: `ROLES`/`Role` in `packages/shared` are replaced by the `app_role` Postgres enum, so the role vocabulary has one source (ADR-021's truth chain).

## Capabilities

### New Capabilities
- `tenancy`: organizations, branches, staff, members; the JWT-claim tenant contract every other table inherits; the RLS template and its isolation guarantees.
- `membership-and-money`: plans, coupons, memberships, pauses, payments, refunds, webhook events, invoices, document counters, per-gym Razorpay account and mandate tables. Money is integer paise with a currency column; financial rows are never hard-deleted.
- `attendance`: QR sessions, attendance with assisted check-in and offline-replay stamps, corrections, holiday calendar.
- `retention`: no-show cases (one open case per member) and the append-only follow-up log.
- `catalogue`: add-on products (PT, diet, product), add-on orders with usage state, PT sessions with a trainer double-booking exclusion.
- `comms`: notifications with one-per-stage de-duplication, message templates, versioned consents, per-gym messaging credit wallet.
- `platform`: platform users, impersonation sessions, the audit log, leads, member imports.
- `demo-seed`: one command seeds the demo gym described in `docs/data-model.md`, idempotently.

### Modified Capabilities
None — `openspec/specs/` is empty before this change.

## Impact

- **New**: `supabase/migrations/*.sql` (one per cluster, in merge order), `supabase/tests/*.sql`, `supabase/seed.sql`, `.github/workflows/seed.yml`, the holdout repo's `supabase/tests/*.sql`.
- **Changed**: `docs/data-model.md` (table list + contract), `docs/registry.md` (enums, DB functions), `docs/decisions.md` (Phase 1 ADRs + open decisions), `docs/gates.md` rows 6–11, `docs/security.md` (per-table retention pointer), `.github/workflows/db.yml` (holdout pgTAP in the `pgtap` job), `packages/db/types/database.ts` (regenerated), `packages/shared/src/config/constants.ts` (`ROLES` retired), `README.md` (seed command).
- **Out of scope, explicitly**: the custom access-token hook that sets the claims (Phase 2), per-role permission policies beyond tenant isolation (Phase 2's role matrix), audit-writing triggers and state-machine enforcement (Phase 3+), Vault wiring of Razorpay secrets (Phase 5), any UI.
