# 0001-data-model

Phase 1: the data model — 36 tables, 24 Postgres enums, RLS on every one of them, indexes, generated types, and a demo gym seeded by one command.

**Exit criteria met.** `docs/roadmap.md` asks for two things: *"pgTAP cross-tenant suite green on every table; one command seeds a complete demo gym."* Both are proven by a log, not a tick:

- **Run `34092121483`**, all four `db.yml` jobs green: visible suite `Files=18, Tests=793, Result: PASS`; holdout suite `Files=8, Tests=790, Result: PASS`; plus `migrate`, `schema-drift` and `pgtap-rollback`. **Zero visible-versus-holdout gap.**
- **Run `34091063459`** seeded the demo gym; **run `34091157183`** seeded it again and the counts were identical.

## What was built

Seven cluster migrations plus two forward-only repairs, applied by CI in merge order:

| Migration | Contents |
|---|---|
| `20260906115131_tenancy` | the `app` schema and its three accessors, 5 enums, 5 tables |
| `20260906115132_pgtap_search_path` | the database-level `search_path` that makes pgTAP reachable (ADR-045) |
| `20260906115146_membership_money` | 6 enums, 11 tables |
| `20260906115149_attendance` | 1 enum, 4 tables |
| `20260906115153_catalogue` | `btree_gist`, 3 enums, 3 tables |
| `20260906115156_retention` | 3 enums, 2 tables |
| `20260906115159_comms` | 3 enums, 6 tables |
| `20260906115203_platform` | 3 enums, 5 tables |
| `20260907044750_adr_047_…` | ADR-047's two corrections to an already-applied cluster |
| `20260907060018_adr_049_…` | ADR-049's three |

Each cluster was built by four agents who never read each other: a visible pgTAP author, a holdout pgTAP author in a repo no implementer sees, an implementer, and a blind critic. `cluster-brief.md` records exactly what they were told.

## What the critics found, and why it is the interesting part

Six blind critics reviewed the seven migrations and found the same shape four times, independently: **a uniqueness or exclusion constraint that is not tenant-scoped is a cross-tenant denial of service.** A constraint ignores RLS, so gym A can take a slot gym B needs — and gym B cannot see, update or delete the blocking row, because Phase 1 grants `delete` on nothing. It is also an existence oracle: a `23505` raised against an invisible row answers a question about another tenant. That is **ADR-047**: `pt_sessions`, `memberships`, `no_show_cases`, `member_devices`, plus two checks and a new read-only privilege tier for `messaging_wallets` and `audit_log`.

A seventh critic, reading the *finished* model with no build history, then found a **fifth instance the other six had missed** — `invoices.payment_id`, globally unique — and two adjacent privilege holes: `messaging_wallet_ledger` was left append-only in a contract that says the wallet balance *is* the sum of the ledger, so ADR-047's wallet fix was defeated by the table it did not move; and `webhook_events` let a gym forge the record of a webhook it verified itself. That is **ADR-049**.

The reason the fifth was missed is worth more than the fix: every ADR-047 instance was a `create unique index`, and `invoices_payment_id_key` is a table-level `constraint … unique` inside `create table`. **Four independent critics found four instances of one shape and stopped, because the shape they had learned was the syntax rather than the property.** `04_contract_meta.sql` now carries the rule as a catalogue-iterating assertion — every unique or exclusion index in `public` must lead with `tenant_id`, with two named exceptions — so the sixth instance fails a test instead of waiting for a critic.

## Three things that went wrong, recorded rather than tidied away

**The gate that was red for a reason nobody read.** Twelve consecutive `db.yml` runs failed, and the suite had therefore *never* been green. The failures were not tests: `pg_prove` opens one connection per file, the CLI's temporary login role has a ceiling around twenty, and past it the pooler answers `failed to retrieve database credentials` and trips its circuit breaker. Eleven red runs were read as expected-red and were not. **ADR-048**; the job now runs the two suites as separate invocations, both of which must pass. This is exactly the jammed-gate failure `docs/gates.md` records from Phase 0, repeated by a session that had read that record.

**A tick that was not evidence.** `tasks.md` had the attendance cluster checked off. Its `migrate` job had failed on a transient credential error and the migration had never applied. The task file said done; the database said otherwise.

**A suite that only passed because the database was empty.** The visible suite went green, then failed on the next run with no test and no schema change between them — the demo gym had been seeded. Fourteen assertions ran as a platform role, which is deliberately not tenant-filtered, and counted whole tables. Every one was right about the schema and wrong about the world. **ADR-050**: an assertion may only make a closed-world claim about rows it scopes to its own fixtures. `docs/decisions.md` OPEN-006 already said this project will hold a real gym's rows one day, so all fourteen were time bombs with a known fuse. **The seed was worth running for this reason alone**, independently of gate 11.

## Carried into Phase 2, deliberately

Recorded rather than archived in silence, because a known gap that nobody wrote down is indistinguishable from an oversight:

- **OPEN-008** — no foreign key re-checks the tenant. ADR-047 removed every consequence found; the write itself is still possible.
- **OPEN-009** — `is_active` is written by nothing and read by nothing; `platform_support` and `super_admin` are indistinguishable to every Phase 1 policy.
- **OPEN-010** — two integrity rules Phase 1 cannot express (`consents.recorded_at`, `notifications.dedupe_key`).
- **OPEN-011** — every "not empty" check is `<> ''`, which one space satisfies.
- **OPEN-012** — invoice arithmetic is unconstrained and unspecified. Phase 5 owns it.
- **OPEN-013** — **there is no intra-tenant authorization at all.** Any session carrying a gym's `tenant_id` can read and write every row in that gym. That is the deferred role matrix working as designed, but Phase 2 must confront it before it issues a member token, and it is DPDP-relevant.

## Gates

Rows 6, 7, 8, 10 and 11 of `docs/gates.md` moved from "N/A — Phase 1, no tables yet" to proven, each citing the run id that proves it.
