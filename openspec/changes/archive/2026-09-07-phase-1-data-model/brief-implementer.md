# Migration implementer brief — Gymloop Phase 1

You write **exactly one migration file** for **exactly one cluster**. Docs live in
`C:\Users\Harsh\Desktop\gymloop`; your output file is **outside** that repo, under
`C:\Users\Harsh\Desktop\gymloop-wip\migrations\`.

## Read first, in this order

1. `C:\Users\Harsh\Desktop\gymloop-wip\agent-brief.md` — the shared brief. Every constraint binds you.
2. `AGENTS.md`
3. `docs/data-model.md` -> `## Conventions (the contract)` **in full**, then your cluster's subsection of
   `## Tables`, then `## Enums`. **This document is the specification. Implement it literally, column by
   column.** A column the list marks with the empty-set symbol is nullable and everything else is
   `not null`; a `=x` is a default; an arrow to a table name is a foreign key; `*_paise` is `bigint`.
4. `openspec/changes/0001-data-model/specs/<your-capability>/spec.md` — the EARS requirements.
5. `docs/domain-rules.md` — the requirement ids your cluster's tables cite.
6. `.claude/skills/db-migration/SKILL.md` and `.claude/skills/rls-policy/SKILL.md`.
7. Load the `supabase-postgres-best-practices` skill and the `supabase` skill before writing SQL.

## Where you write, and what you may not touch

- Your file **already exists** with its timestamp, created by `supabase migration new`. Write into it.
  **Never rename it, never create another migration file, never invent a timestamp.**
- **Do not read or write `supabase/tests/**`.** Other agents are writing there concurrently and the
  files are incomplete. You are held to the contract and the spec, not to a test file. This is
  deliberate: an implementation fitted to the visible tests is exactly what the holdout suite exists
  to detect.
- **Do not read another cluster's migration file**, even though they sit in the same directory.
- Do not edit `docs/data-model.md`. If the contract is wrong or under-specified, that is a **finding
  for the orchestrator**, reported in your final message — not an edit and not a silent choice.
- Do not commit, do not push, do not run git.

## The `tenancy` cluster has already been written and merges before you

You may assume these exist and **must not re-create any of them**:

- schema `app`, with `usage` granted to `authenticated` and `service_role`;
- `app.current_tenant_id() returns uuid`, `app.is_platform() returns boolean`,
  `app.touch_updated_at() returns trigger` — all `stable`/`security invoker`, `set search_path = ''`;
- extension `pgtap` in schema `extensions`;
- enums `app_role`, `organization_status`, `gym_preset`, `streak_rule_type`, `member_status`;
- tables `organizations`, `organization_settings`, `branches`, `staff`, `members`.

`organizations` is the foreign-key target of every `tenant_id`. Reference it; never alter it.

## Statement order — every file reads the same

1. extensions (`create extension if not exists <ext> with schema extensions;`) — only if your cluster
   owns one; `btree_gist` belongs to `catalogue` and nothing else.
2. enum types — `create type public.<name> as enum (...)`, **labels in the order `## Enums` lists them**.
   The order is part of the contract: it is what `supabase gen types` emits and what any `order by`
   follows. Create only the enums the contract's ownership table assigns to your cluster.
3. tables — inline defaults, `not null`, primary key, foreign keys, and every check expressible on one column.
4. constraints not expressible inline — multi-column checks and exclusion constraints, via `alter table ... add constraint`.
5. indexes.
6. `alter table public.<table> enable row level security;` for every table.
7. policies.
8. privileges — `revoke` then `grant`, written out per table.
9. triggers — `<table>_touch_updated_at` on exactly the tables that carry `updated_at`, and nothing else.

Head the file with a comment naming the cluster and the sections of `docs/data-model.md` it implements.
No `begin`/`commit` inside a migration. No `drop`. No `alter` against another cluster's table — a
cross-cluster seam is carried by the later table's foreign key, never by an alter.

## Non-negotiables you will be judged on

- **Every table**: `id uuid primary key default gen_random_uuid()` unless the table list gives it a
  natural or composite key; `created_at timestamptz not null default now()` **on every table without
  exception** (the table list omits it on `messaging_wallets` and `document_counters`; the contract
  says the rule wins, so they get one); `updated_at` on exactly the tables the list gives one,
  maintained by the shared trigger and by nothing else; `text` never `varchar(n)`; `jsonb` never `json`.
- **A calendar-day default is `(now() at time zone 'Asia/Kolkata')::date`, never `current_date`.**
  `current_date` evaluates in the session timezone and every Supabase connection is UTC, so it returns
  yesterday between 00:00 and 05:30 IST — real gym traffic.
- **Money** is `bigint` paise in a `*_paise` column with exactly one `currency text not null default 'INR'`
  per table carrying money, with `check (currency ~ '^[A-Z]{3}$')`. Never `numeric`, never float.
  Basis-point columns (`gst_rate_bp`, `percent_bp`) and credit balances are **not** money and take no
  currency column.
- **RLS on every table, in this migration**, with the two permissive policies from the contract's
  template, `(select app.current_tenant_id())` wrapped so the planner hoists it to an InitPlan.
  `with check` is not optional. Never `force row level security`.
- **Privileges per table, written out in full**: `revoke all on public.<t> from anon, authenticated;`
  then the tier's grant. Never the `on all tables in schema public` form. `anon` gets nothing anywhere.
  `delete` and `truncate` go to nobody. Append-only tables get `select, insert` only.
- **Indexes**: rule 1 — every tenant-scoped table has a **non-partial** btree index whose **first**
  column is `tenant_id` (a composite leading with it counts; a partial index does **not**). Rule 2 —
  every foreign-key column either leads an index of its own or sits immediately after the tenant column
  in a tenant-leading composite; a **partial** index does count for rule 2. If your cluster owns one of
  the four tables the contract names as having no tenant-leading index (`attendance_corrections`,
  `follow_ups`, `consents`, `refunds`), add `<table>_tenant_id_idx`.
- **Naming** exactly per the contract's naming table, including ADR-040's fixed rule word: a regex check
  is `<table>_<column>_format_chk`, a range or bound is `<table>_<column>_chk`, a multi-column rule is
  `<table>_<phrase>_chk`. Primary keys and inline foreign keys are auto-named — never name them by hand.

## What you must NOT build

A `security definer` function. A view or materialised view. Any trigger other than the shared
`updated_at` one. Business logic, state-machine enforcement, an audit-writing trigger, a derived
balance, a `pg_cron` job. A second copy of `app.touch_updated_at()`. A third JWT accessor. A third
tenant-path exemption. An extension other than the one your cluster owns. Phase 1 owns **shape**;
Phase 3+ owns behaviour.

## A contract question already answered — do not re-open it

A foreign key does not enforce tenancy, and the `with check` predicate inspects only `tenant_id`. So a
row in your cluster can, in principle, name a parent row belonging to another gym. **Do not fix this
with composite foreign keys or a `unique (tenant_id, id)` on a parent table.** It is recorded as an
open decision for a later phase; exploiting it requires already knowing a uuid v4 that RLS prevents you
from reading. Implement the foreign keys exactly as the table list writes them.

## Before you finish

Re-read your file against your cluster's table list **line by line**, column by column, and confirm in
your report: every column present with the right type, nullability and default; every check; every
index; RLS enabled; both policies; the privilege pair; the triggers. Then read it once more as
Postgres 17 would, hunting for a syntax error, a forward reference, a wrong array-literal type, an enum
label typo, or a regex written for a different escaping convention. You cannot run it — CI applies it —
so this read is the only thing between you and a red `main`.

You may run **read-only** `supabase db query --linked "select ..."` to check how Postgres evaluates an
expression (for example `select 'ABC123' ~ '^[A-Z0-9]{6}$'`). Never a mutating command. **Never the
Supabase MCP server.**
