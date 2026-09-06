# Data model

## v1 scope — what the schema must support

Transcribed from master prompt §7, which is disposable once Phase 0 archives. This is the checklist Phase 1's schema is measured against; a capability listed here with nowhere to live in the schema is a gap, not a Phase 2 item.

Member profile and active membership · gym plans, prices, discounts and expiry rules · QR check-in with assisted front-desk fallback · attendance history · configurable no-show red list · follow-up outcomes and next actions · weekly goal / streak · renewal options with verified payment state · offline payment recording · GST invoices · PT, diet and product catalogue · basic add-on orders and usage state · **lead / enquiry management** (walk-in → trial → conversion, with source tracking) · coupon codes on renewal · owner dashboard and daily summary · super-admin console · consent, opt-out and audit history · CSV/Excel member import with column mapping and duplicate-phone detection · three gym presets (neighbourhood gym / premium studio / functional box).

**Phase 2 — the schema must accommodate these, but do not build them:** multi-branch UI (`organization → branch` from day one) · full trainer app · class/batch scheduling · UPI Autopay via Razorpay subscriptions (**mandate tables in the schema now**) · staff payroll and trainer commission · body measurements and progress photos · wearables · referrals · advanced inventory · anonymised cross-gym benchmarking · WhatsApp Business API · per-permission role matrix.

This is the **specification** Phase 1 implements — tables, enums, relationships, and the RLS policy shape. It is not DDL; migrations are written and applied by CI only, never by hand (`AGENTS.md`).

## Tenancy

Single Postgres database, Row-Level Security on every table, `tenant_id` injected via a custom access-token hook and read from the JWT claim — **never** a per-row subquery (that's gate 8, `docs/gates.md`).

Hierarchy from day one, so Phase 2's multi-branch UI needs no schema change: **organization → branch → member**. A "gym" in every other doc is an `organization`; v1 UI only ever shows one `branch` per organization, but the column exists now.

## Conventions (the contract)

Fixed before the first migration and binding on every table in the list that follows. Six cluster agents write their migrations in parallel against this section; anything left to taste here comes back as six dialects. A cluster that needs an exception records an ADR in `docs/decisions.md` first — it does not quietly deviate, and it never edits another cluster's file.

### Naming

All identifiers lowercase `snake_case` and unquoted, so nothing ever needs quoting again.

| Object | Pattern | Example |
|---|---|---|
| table | plural noun | `memberships`, `no_show_cases` (`staff` and `attendance` are mass nouns and stay as the list writes them) |
| column | `snake_case`; FK `<referenced_singular>_id`; money `*_paise`; timestamp `*_at`; date `*_on`; boolean `is_*`/`has_*` | `recorded_by_staff_id`, `price_paise`, `paid_at`, `joined_on`, `is_active` |
| enum type | singular, in `public` | `payment_status` |
| primary key | auto-named `<table>_pkey` — never named by hand | `members_pkey` |
| foreign key | declared inline on the column, auto-named `<table>_<column>_fkey` | `members_branch_id_fkey` |
| unique (total) | table constraint `<table>_<columns>_key` | `plans_tenant_id_name_key` |
| unique (partial) | `create unique index <table>_<columns>[_<qualifier>]_key` | `memberships_member_id_live_key` |
| index | `create index <table>_<columns>[_<qualifier>]_idx` | `attendance_tenant_id_member_id_checked_in_at_idx` |
| check | `<table>_<rule>_chk`, where `<rule>` is: `<column>_format` for a regex, `<column>` for a range or bound, and a short phrase for a multi-column rule | `organizations_gym_code_format_chk`, `plans_price_paise_chk`, `payments_paid_has_reference_chk` |
| exclusion | `<table>_<rule>_excl` | `pt_sessions_trainer_overlap_excl` |
| policy | `<table>_tenant_all`, `<table>_platform_all`, `<table>_tenant_select` | `payments_tenant_all` |
| trigger | `<table>_touch_updated_at` | `members_touch_updated_at` |
| migration file | `supabase migration new <cluster>` — never invent the timestamp | `20260906120000_tenancy.sql` |

`<columns>` is the index's columns in index order joined by `_`, without `desc` and without the `where` clause. `<qualifier>` is one word naming what a partial index selects (`live`, `open`, `default`, `unprocessed`) and exists because two partial indexes over the same columns otherwise collide.

### Migration file layout

One file per cluster. Statements in this order, so all seven files read the same:

1. extensions — `create extension if not exists <ext> with schema extensions;`
2. enum types — `create type public.<name> as enum (…)`
3. tables — inline defaults, `not null`, primary key, foreign keys, and every check expressible on one column
4. constraints not expressible inline — multi-column checks and exclusion constraints, via `alter table … add constraint`
5. indexes
6. `alter table public.<table> enable row level security;`
7. policies
8. privileges — `revoke`, then `grant`, per table
9. triggers

No `begin`/`commit` inside a migration; only pgTAP files are transaction-wrapped (ADR-030). No `drop`, and no `alter` against a table another cluster created. Head the file with a comment naming the cluster and the sections of this document it implements.

### Every table

- Primary key `id uuid primary key default gen_random_uuid()`. `gen_random_uuid()` is core in Postgres 17 and needs no extension. The five tables the list gives a natural or composite key (`organization_settings`, `razorpay_accounts`, `messaging_wallets`, `document_counters`, `platform_users`) use that key and have no `id`. No `bigint generated always as identity` anywhere; ADR-035 argues that departure from Supabase's own guidance.
- `created_at timestamptz not null default now()` on every table, no exceptions. (`messaging_wallets` and `document_counters` are written below without one; the rule wins.) Four tables also carry a **domain** timestamp — `consents.recorded_at`, `audit_log.occurred_at`, `webhook_events.received_at`, `qr_sessions.issued_at` — and keep both. They are not duplicates: `created_at` is when the row was inserted, the domain column is when the thing it records happened, and a backfill or a delayed webhook makes them differ. Do not collapse them.
- `updated_at timestamptz not null default now()` on exactly the tables the list gives one, each maintained by the shared trigger below and by nothing else. A table with no `updated_at` gets no trigger.
- Columns are `not null` unless the list marks `∅`. `text`, never `varchar(n)` — a length limit is a check constraint. `jsonb`, never `json`. An instant is `timestamptz`; a calendar day the gym reasons about in its own timezone is `date` (MNY-004).
- Money is an integer number of paise in a `bigint` column named `*_paise`, never `numeric` and never floating point (MNY-001). Every table carrying a money column carries exactly one currency column, `currency text not null default 'INR'`, with `constraint <table>_currency_format_chk check (currency ~ '^[A-Z]{3}$')` (MNY-002 — the name follows ADR-040's rule word, since this is a regex check; this line previously read `<table>_currency_chk`, contradicting the naming table two sections above, and a blind critic caught it before the eleven other `currency` columns landed). Basis-point columns (`gst_rate_bp`, `percent_bp`) and `messaging_wallets.balance_credits` are not money and take no currency column. The rounding rule for derived amounts is Phase 5's (MNY-003); no cluster invents one. **Every `currency` column carries the check, including `organizations.currency`, which has no money column beside it** — it is the gym's default currency and a malformed value there propagates into every amount derived from it.
- **`=today_ist` means `default (now() at time zone 'Asia/Kolkata')::date`, never `current_date`.** This is MNY-004 applied to a column default. `current_date` evaluates in the *session* timezone, and every Supabase connection is UTC — so between 00:00 and 05:30 IST, which is real gym traffic, `current_date` returns yesterday. The literal duplicates `DEFAULT_TIMEZONE` in `packages/shared/src/config/constants.ts` because a migration cannot import a TypeScript constant and a column default cannot reach `organizations.timezone`; if that constant ever changes, these defaults are the second place to change. A gym outside IST needs the application to supply the gym-local date explicitly, which is Phase 3's job — the default is only correct for the timezone every v1 gym is in. Two columns use it: `members.joined_on` and `no_show_cases.opened_on`.

`updated_at` is maintained by one function and one trigger per table, never by application code:

```sql
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger members_touch_updated_at
  before update on public.members
  for each row execute function app.touch_updated_at();
```

The function is created once, by the contract migration. A second copy of it is the failure this paragraph exists to prevent.

### The `app` schema and the two JWT accessors

Phase 2's custom access-token hook will set two claims: `tenant_id` (a uuid as a string) and `app_role` (a label from the `app_role` enum). Phase 1 fixes the claim names and writes the accessors; it does not build the hook. ADR-032 records why, and what was rejected.

The accessors live in `app`, not `public`. `supabase/config.toml` exposes only `public` and `graphql_public` to the Data API, so nothing in `app` is reachable as an RPC and nothing in `app` appears in `packages/db/types/database.ts`. Both are `stable` and `security invoker`: they read a GUC and never touch a table, so `security definer` would buy nothing and would hand a caller elevated context for free.

```sql
create schema if not exists app;
grant usage on schema app to authenticated, service_role;

create or replace function app.current_tenant_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    ''
  )::uuid
$$;

create or replace function app.is_platform()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'app_role',
    ''
  ) in ('super_admin', 'platform_support')
$$;
```

`current_setting(…, true)` returns null instead of raising when the setting is absent, so a session with no claims yields `null` from `current_tenant_id()` and `false` from `is_platform()` — no exception, and a policy comparing against null simply matches no rows. A claim that is present but is not a uuid raises `22P02` on the cast; that is correct and deliberate. A malformed claim must fail loudly rather than degrade into "sees nothing" and be mistaken for an empty gym.

`execute` on both is already granted to `public` by default, so the schema `usage` grant is the only privilege a policy needs. `anon` gets neither.

**There is no third accessor.** A per-role helper (`app.is_owner()`, `app.has_permission(…)`) belongs to Phase 2's role matrix, not to Phase 1's tenant isolation; writing one now puts a permission model in the schema before the hook that feeds it exists.

### Row-Level Security

`alter table … enable row level security` in the same migration that creates the table, always. Never `force row level security`. It buys nothing here and it misleads: the roles that carry a user request are `authenticated` and `anon`, and both are already fully subject to every policy — `force` only ever changes what the *table owner* sees. Isolation is proven for `authenticated`, and that is what the pgTAP suite asserts (gate 7). Nobody should later read the absence of `force` as an oversight.

*Correction, recorded rather than quietly fixed.* This paragraph, ADR-037, `design.md` and the pgTAP-role section below all previously argued that `force` would break the migrations and the seed, because the owner is `postgres` and `postgres` holds no JWT. **That reasoning is factually wrong on this project and a blind critic caught it.** `postgres` here has `rolbypassrls = true` (verified: `select rolname, rolbypassrls from pg_roles` — `postgres`, `service_role` and `supabase_admin` are `true`; `authenticated` and `anon` are `false`). A role with `BYPASSRLS` bypasses row security unconditionally, and `FORCE ROW LEVEL SECURITY` does not override it — so `force` would *not* have broken the seed or the pgTAP fixtures. The rule stands on the reason above instead. The lesson generalises: an argument that sounds mechanical is still a claim about this database, and this one was never run against it until now.

Two permissive policies per tenant-scoped table, both `for all to authenticated`. Every accessor call is wrapped in `(select …)` so the planner evaluates it once as an InitPlan instead of once per row — at 100 gyms × 500 members that wrapper is the difference between an index scan and a per-row function call:

```sql
alter table public.<table> enable row level security;

create policy <table>_tenant_all on public.<table>
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy <table>_platform_all on public.<table>
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));
```

`with check` is not optional. `using` alone governs which rows are visible and updatable *from*; without `with check` an authenticated user can insert a row into another tenant, or move one there.

`organizations` compares `id`, being the tenant itself:

```sql
create policy organizations_tenant_all on public.organizations
  for all to authenticated
  using (id = (select app.current_tenant_id()))
  with check (id = (select app.current_tenant_id()));
```

`impersonation_sessions` gives the gym read access only — it may see who impersonated it and when, and may not write that record:

```sql
create policy impersonation_sessions_tenant_select on public.impersonation_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()));
```

with `impersonation_sessions_platform_all` beside it, unchanged from the template.

Under a missing claim `app.current_tenant_id()` is null, `tenant_id = null` is null rather than true, and `app.is_platform()` is false; both permissive policies fail, they OR to false, and the query returns zero rows. Zero rows, not an error — a policy that raised would let a caller tell "nothing here" apart from "wrong tenant", and the pgTAP null-claim case asserts the silent-empty behaviour. The same arithmetic keeps `audit_log`'s null-`tenant_id` rows invisible to every gym without needing a second policy: `null = <uuid>` is null.

### Privileges

Verified against `pg_default_acl`: in schema `public`, default privileges grant **all** — insert, select, update, delete, truncate, references, trigger, maintain — to `anon`, `authenticated` and `service_role` on every table created by `postgres`, which is the role migrations run as. RLS restricts which *rows* are reachable; it does not remove the privilege, and `truncate` is not filtered by RLS at all. A table that enables RLS but never revokes is one dropped policy away from being world-writable. So, every table without exception:

```sql
revoke all on public.<table> from anon, authenticated;
grant select, insert, update on public.<table> to authenticated;
```

Both lines are written out per table. Never the `on all tables in schema public` form — a later cluster running it re-grants across every other cluster's tables. `service_role` is never revoked from; it is the Edge Functions' and the seed's role and bypasses RLS by design. `anon` is granted nothing anywhere in v1: a public surface that ever needs data (a gym-code lookup, say) goes through a Route Handler on `service_role`, not through an `anon` grant.

Three tiers, and the grant line is the whole difference:

| Tier | Grant to `authenticated` | Tables |
|---|---|---|
| normal | `select, insert, update` | `organizations`, `organization_settings`, `branches`, `staff`, `members`, `plans`, `coupons`, `document_counters`, `razorpay_accounts`, `qr_sessions`, `organization_holidays`, `addon_products`, `pt_sessions`, `message_templates`, `notifications`, `member_devices`, `messaging_wallets`, `platform_users`, `leads`, `member_imports` |
| append-only | `select, insert` | `attendance_corrections`, `follow_ups`, `consents`, `audit_log`, `messaging_wallet_ledger`, `webhook_events` |
| history | `select, insert, update` | `memberships`, `membership_pauses`, `payments`, `refunds`, `invoices`, `razorpay_mandates`, `attendance`, `no_show_cases`, `addon_orders`, `impersonation_sessions` |

Append-only is a privilege, not a trigger: an insert-only grant cannot be forgotten in a code path the way a guard can. `webhook_events` is append-only for `authenticated` even though `processed_at` is stamped after insert — the stamp is written by the webhook Edge Function on `service_role`.

`history` and `normal` carry the same grant today and are still named apart, because the missing `delete` means different things: on a history table it is permanent (INT-001 — cancel, refund, correct, never remove), on a normal table it is Phase 1's default. **`delete` is granted to `authenticated` on no table in Phase 1** — no v1 flow hard-deletes a row. A later phase that genuinely needs one adds the grant deliberately, per table, with the reason recorded in `docs/decisions.md`.

No sequence grants are needed anywhere: keys are uuid and no column is `generated as identity`.

A pgTAP meta-test asserts the outcome rather than the syntax — `anon` holds no privilege on any table in `public`, and `authenticated` holds `delete` on none.

### Indexes

Three rules, all mechanically checkable, all asserted by a pgTAP meta-test over `pg_index` for every table in `public`:

1. Every tenant-scoped table has at least one **non-partial** btree index whose **first column** is its tenant column. A composite leading with `tenant_id` satisfies it; a composite leading with anything else does not, and neither does a partial index — a policy predicate applies to every row, so an index that covers only some of them leaves the rest on a sequential scan. The primary key discharges the rule for `organizations` (`id`) and for the tenant-keyed tables whose key starts with `tenant_id`. Four tables in the list below enumerate indexes that do not include one: `attendance_corrections`, `follow_ups`, `consents` (no tenant-leading index at all) and `refunds` (only a partial unique one). The owning cluster adds `<table>_tenant_id_idx`, or extends an existing composite to lead with `tenant_id` where that serves a real query.
2. Every foreign-key column is indexed: it either leads an index of its own, or it sits immediately after the tenant column in a tenant-leading composite — `(tenant_id, member_id, checked_in_at desc)` indexes `attendance.member_id`, and no separate one is added. The second form counts because every read here is tenant-scoped, and the referential-integrity scan a standalone index would serve happens only when a parent key is deleted or updated: Phase 1 grants `delete` nowhere, and a uuid key is never updated. Unlike rule 1, **rule 2 accepts a partial index** — `no_show_cases.member_id` leads only `(member_id) where status in (…)` and `members.user_id` sits only in `(tenant_id, user_id) where user_id is not null`, and both are sufficient, because the RI probe is `where <fk> = $1`, which implies the partial predicate, so the planner can use the index. The meta-test must encode this difference or it will fail four tables that are correct.
3. Every column appearing in an RLS policy predicate is indexed. With the template above that is the tenant column, so rule 1 discharges it; it is stated separately because it stops being automatic the moment a policy grows a second term.

The meta-test iterates the catalogue, so it covers tables that do not exist yet as well as today's. A table that cannot satisfy all three is a schema bug; the exception is not negotiated with the test afterwards.

### Enums

Every vocabulary in `## Enums` below is a Postgres enum (ADR-021), created as `create type public.<name> as enum (…)` with the labels in the order that section lists — the order is part of the contract, because it is what `supabase gen types` emits and what any `order by` on the column follows. Each type is created exactly once, by the cluster that owns it; a second `create type` in a parallel migration is an apply failure on merge.

| Cluster | Enums it creates |
|---|---|
| tenancy | `app_role`, `organization_status`, `gym_preset`, `streak_rule_type`, `member_status` |
| membership+money | `membership_status`, `payment_status`, `payment_method`, `refund_kind`, `refund_status`, `mandate_status` |
| attendance | `attendance_source` |
| catalogue | `addon_kind`, `addon_order_status`, `pt_session_status` |
| retention | `no_show_case_status`, `contact_channel`, `follow_up_outcome` |
| comms | `notification_channel`, `notification_status`, `consent_purpose` |
| platform | `lead_source`, `lead_stage`, `import_status` |

`app_role` is created by the contract migration because four clusters need it, and it is the only role vocabulary the system has (ADR-031). Nothing enforces a legal transition in Phase 1 — the graphs in `## Enums` are documentation until the phase that first mutates each status (3, 4, 5) writes the enforcement and the illegal-transition tests (gate 14).

### Audit rows

`audit_log.action` is `<record_type>.<verb>`, both halves lowercase snake_case: `payment.refunded`, `membership.cancelled`, `attendance.corrected`, `impersonation_session.started`. The format is a constraint, and it replaces the list's `≠ ''` on that column — a pattern requiring the dot already excludes the empty string:

```sql
constraint audit_log_action_format_chk
  check (action ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
```

Phase 1 creates the table with its indexes, RLS and privileges — and **nothing writes to it**. No audit trigger, no `security definer` writer function, no application write. INT-003's rows arrive with the phases that perform the actions (3+), which is also the first point at which the actor is knowable. A cluster agent that adds an audit trigger has built Phase 3 early and wrong.

### Tenant-path exceptions

Exactly two, both in the platform cluster (ADR-033). `platform_users` has no `tenant_id` at all and carries only `platform_users_platform_all`. `audit_log` has a nullable `tenant_id`: a row with one belongs to that gym, a row without one is platform-level and reachable only through the platform policy. Every other table in the list is `direct`, and a pgTAP meta-test asserts that no third table is missing tenant scoping — so this is a closed list, not a precedent. A third exception needs an ADR before the migration, not after.

### How a pgTAP test assumes a role

Part of the contract, not of any one cluster: twelve blind authors write isolation tests in parallel, and three dialects of "act as gym A" would make their results incomparable. Every test file uses this shape.

CI's pgTAP session connects as **`cli_login_postgres`**, not as `postgres`. This paragraph previously said the opposite, and the opposite is false — `docs/decisions.md` ADR-046 records how it was measured and what it broke. `supabase test db --linked` runs `pg_prove` against the temporary login role the CLI mints, and that role is a **`NOINHERIT`** member of `postgres` with **no `BYPASSRLS`**, no privilege on any table in `public`, and no `USAGE` on `extensions`, `app` or `auth`. Under it, `select plan(58)` fails with `function plan(integer) does not exist` — the function is there and executable, the schema is simply invisible — and no fixture can be inserted at all. (`supabase db query --linked` *does* report `current_user = postgres`, which is exactly why the wrong belief survived: the two CLI commands do not authenticate the same way.)

The membership carries the `SET` option, so the session can take the roles it needs. **Every file therefore assumes the owner role explicitly, immediately after `begin;`, and never relies on inheriting it** — and where a file previously said `reset role;` it says `set local role postgres;`, because `reset role` returns to the *session* role, which here can do nothing. Both are transaction-local, so the closing `ROLLBACK` undoes them. `set local role authenticated` still works from this session (`pg_has_role('cli_login_postgres','authenticated','SET')` is true), so the isolation half of every file is unchanged.

As `postgres` the session owns every table a migration creates and holds `BYPASSRLS`, so fixtures are inserted with row security not applying, and isolation is asserted after switching role — `set local role authenticated` re-imposes RLS because ownership and `BYPASSRLS` are both evaluated against the *current* role. The absence of `force row level security` is irrelevant either way (see the correction under § Row-Level Security).

```sql
-- take the owner role; the connection does not give it to us
set local role postgres;

-- fixtures, as the owner: RLS does not apply
insert into public.organizations (id, name, gym_code) values ('…'::uuid, 'Gym A', 'AAAAAA');

-- act as a signed-in user of Gym A
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '<gym-a-uuid>', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- … assertions …

set local role postgres;
select set_config('request.jwt.claims', '', true);
```

A missing claim is the empty string, or never setting the GUC at all; both must yield `null` from `app.current_tenant_id()` and zero rows, without raising. Assert privileges with the three-argument form — `has_table_privilege('authenticated', 'public.payments', 'DELETE')` — so the assertion does not depend on which role the session happens to be. "Refused for want of privilege" is `throws_ok(…)` on SQLSTATE `42501`; an exclusion-constraint violation is `23P01`; a malformed uuid cast is `22P02`. Note the asymmetry that catches people out: an RLS policy does **not** raise on `select` or `update`, it filters, so assert zero rows — but a failing `with check` **does** raise `42501` on `insert`.

Three pgTAP mechanics that cost this phase a round trip each, recorded so the next author does not pay again. **`throws_ok` has a three-argument form whose third argument is the expected error *message*, not the description** — `throws_ok(sql, '23514', 'a negative count is rejected')` therefore asserts that Postgres said "a negative count is rejected", which it never does, and the test fails against a perfectly correct constraint. Always pass four arguments with `null` for the message: `throws_ok(sql, '23514', null, 'a negative count is rejected')`. **`results_eq` compares the two cursors as records, so it aborts the whole file with `42P22 could not determine which collation to use` if their text collations differ** — a catalogue column of type `name` (`attname`, `typname`, `polname`, `relname`, `conname`) cast to `text` carries collation `"C"`, and a bare string literal in a `values (…)` list carries none. Write `a.attname::text collate "default"` on the actual side and cast every literal on the expected side. **`finish()` is the authority on whether a file passed**: it emits nothing when the plan matched and nothing failed, and a line beginning `# Looks like you` otherwise — counting `ok` lines is not equivalent, because an assertion inside a top-level `with … select` statement still runs and still counts against the plan.

One parser constraint from `scripts/check-pgtap-rollback.mjs`: it strips comments, splits on `;`, uppercases, and rejects any file containing a statement that is exactly `COMMIT` or exactly `END`. A `do $$ … end $$;` block therefore fails the check even though it is valid SQL. Write plain SQL and pgTAP functions; no anonymous PL/pgSQL blocks in a test file.

### The contract migration

The `tenancy` cluster is the contract migration and merges alone, before any fan-out. It creates, in this order: `create extension if not exists pgtap with schema extensions;` · schema `app` and its `usage` grant · `app.current_tenant_id()`, `app.is_platform()`, `app.touch_updated_at()` · the five tenancy enums · `organizations`, `organization_settings`, `branches`, `staff`, `members` with their indexes, RLS, policies, privileges and triggers.

That list is exactly what the other six clusters depend on and none of them re-creates: the schema, the three functions, `app_role`, and `organizations` as the foreign-key target of every `tenant_id`. `btree_gist` is the one other extension Phase 1 installs and belongs to the catalogue cluster, its only user (`pt_sessions`). `pgcrypto` and `uuid-ossp` are already installed on the project; no migration creates them.

### What a cluster agent must not do

- Run `supabase db push`, `supabase db reset`, or any other mutating Supabase command. CI applies migrations on merge to `main`, in merge order (ADR-030). Never the Supabase MCP server — it is authenticated to a different account (`AGENTS.md` rule 2).
- Edit another cluster's migration, or `alter` a table another cluster created. A cross-cluster seam is carried by the later table's foreign key (`addon_orders.payment_id`), never by an alter.
- Hand-edit `packages/db/types/database.ts`. It is regenerated from Cloud after the apply (`AGENTS.md` rule 6).
- Write an `eslint-disable`, a `knip` ignore, or any other escape hatch (`AGENTS.md` rule 4).
- Create a `security definer` function, a view, a materialised view, or any trigger other than `<table>_touch_updated_at`.
- Put behaviour in the database: no state-machine enforcement, no audit writes, no derived balances, no `pg_cron` job. Phase 3+ owns behaviour; Phase 1 owns shape.
- Grant anything to `anon`; add `force row level security`; add a third accessor; add a third tenant-path exception; create an extension other than the two named above.
- Edit `docs/data-model.md`. This section and the table list are the specification the migrations implement — changing either is a `spec:` commit with human approval (`AGENTS.md` rule 10).

## Tables

The v1 schema, table by table. **Cluster** is the migration that creates the table and the agent that owns it (`.claude/skills/new-feature/SKILL.md`, "Parallel execution within a phase"). **Tenant path** is how RLS reaches the tenant id: `direct` means the row carries `tenant_id`; the two exceptions are named. Conventions every table follows without repeating them here — id, timestamps, the policy pair, the privilege block, the index rule — are in "Conventions (the contract)" above. Only what is *specific* to a table is listed under it.

Column notation: `name type` then constraints; `→ table` is a foreign key; `∅` means nullable (everything else is `not null`); `=x` is the default; money columns are integer paise (`*_paise bigint`) next to one `currency` column per table.

### Cluster: tenancy (the contract migration)

**`organizations`** — the tenant. Tenant path: `id` *is* the tenant id (the one table whose policies compare `id`, not `tenant_id`).
- `id uuid` pk · `name text` · `gym_code text` unique, check `^[A-Z0-9]{6}$` (must agree with `GYM_CODE_LENGTH`) · `status organization_status =pending_approval` · `tier text ∅` (platform billing tier, Phase 6 decides its vocabulary) · `trial_ends_at timestamptz ∅` · `activated_at timestamptz ∅` · `timezone text =Asia/Kolkata` (IANA) · `currency text =INR` · `created_at`, `updated_at`
- Indexes: `gym_code` (unique), `status`.

**`organization_settings`** — the per-gym template, one row per organization. Tenant path: `tenant_id` is the pk.
- `tenant_id uuid` pk → organizations · `preset gym_preset ∅` · `logo_url text ∅` · `brand_accent text ∅` check `^#[0-9a-fA-F]{6}$` · `address_line1 text ∅` · `address_line2 text ∅` · `city text ∅` · `state text ∅` · `pincode text ∅` check `^[1-9][0-9]{5}$` · `gstin text ∅` check `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$` · `invoice_prefix text =INV` · `receipt_prefix text =RCPT` · `financial_year_start_month smallint =4` check 1–12 · `week_start_day smallint =1` check 0–6 (0 = Sunday) · `opening_hours jsonb ={}` · `no_show_threshold_days smallint =7` check > 0 · `checkin_dedupe_seconds integer =120` check ≥ 0 (ATT-004 window) · `streak_rule_type streak_rule_type =visit_streak` · `weekly_goal_default smallint =3` check 1–14 · `renewal_reminder_days_from_expiry smallint[] ∅` (null = platform default `RENEWAL_REMINDER_WINDOWS`; same axis: negative before, positive after) · `grace_period_days smallint =0` check ≥ 0 · `pause_reasons text[] ={}` · `pause_approver_role app_role =gym_manager` · `max_freeze_days_per_year smallint =30` check ≥ 0 · `trainer_member_cap smallint ∅` check > 0 · `created_at`, `updated_at`

**`branches`** — Phase 2 multi-branch; v1 creates exactly one, flagged default. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `name text` · `address text ∅` · `timezone text ∅` (overrides the organization's when set) · `is_default boolean =false` · `created_at`, `updated_at`
- Indexes: unique partial `(tenant_id) where is_default` — one default branch per organization. Unique `(tenant_id, name)`.

**`staff`** — every gym-side login: owner, manager, front desk, trainer. Trainers are staff rows with `role = trainer`. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `user_id uuid ∅` → `auth.users(id)` on delete set null · `branch_id uuid ∅` → branches (null = all branches) · `role app_role` check in (`gym_owner`, `gym_manager`, `front_desk`, `trainer`) · `full_name text` · `phone text ∅` check E.164 `^\+[1-9][0-9]{7,14}$` · `email text ∅` · `is_active boolean =true` · `qualification text ∅` (ADD-002, trainers) · `max_active_clients smallint ∅` check > 0 (trainer-to-member cap) · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, user_id) where user_id is not null`; `(tenant_id, role)`; `branch_id`.

**`members`** — the gym's customer. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `branch_id` → branches (home branch) · `user_id uuid ∅` → `auth.users(id)` on delete set null (null until the member joins the app; phone auto-match sets it) · `member_code text ∅` (gym-visible id, front-desk search) · `full_name text` · `phone text` check E.164 · `email text ∅` · `gender text ∅` · `date_of_birth date ∅` · `photo_url text ∅` (DPD-008: photos yes, government ID never — there is no column for one) · `status member_status =active` · `joined_on date =today_ist` · `weekly_goal_visits smallint ∅` check 1–14 · `rest_days smallint[] ={}` (weekday numbers, 0 = Sunday; STK-002) · `motivation_push_enabled boolean =true` (STK-004) · `notes text ∅` · `erased_at timestamptz ∅` (DPD-006: personal columns blanked, row and financial history kept) · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, phone)` (CSV import duplicate-phone detection); unique `(tenant_id, member_code) where member_code is not null`; `(tenant_id, status)`; `branch_id`; unique `(tenant_id, user_id) where user_id is not null`.

### Cluster: membership+money (one agent — PAY-008 makes the verified payment the thing that activates a membership)

**`plans`** — a gym's membership tiers. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `name text` · `description text ∅` · `duration_days integer` check > 0 · `price_paise bigint` check ≥ 0 · `currency text =INR` · `gst_rate_bp smallint =0` check 0–10000 (basis points; 1800 = 18 %) · `max_freeze_days smallint =0` check ≥ 0 · `is_active boolean =true` · `sort_order smallint =0` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, name)`; `(tenant_id, is_active)`.

**`coupons`** — discount codes on renewal (v1) and add-ons. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `code text` · `percent_bp integer ∅` check 0–10000 · `flat_paise bigint ∅` check ≥ 0 · check exactly one of `percent_bp`/`flat_paise` is non-null · `currency text =INR` · `valid_from timestamptz ∅` · `valid_until timestamptz ∅` · `max_redemptions integer ∅` check > 0 · `redeemed_count integer =0` check ≥ 0 · `applies_to_plans boolean =true` · `applies_to_addons boolean =false` · `is_active boolean =true` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, code)`.

**`memberships`** — a member's paid period on a plan; a renewal is a new row linked by `renewal_of_membership_id`. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `plan_id` → plans · `status membership_status =pending` · `starts_on date ∅` · `ends_on date ∅` · check `status = 'pending' or (starts_on is not null and ends_on is not null)` (DQA-001 made structural: only a pending row may lack an expiry) · check `ends_on >= starts_on` · `price_paise bigint` check ≥ 0 (snapshot of the plan price) · `discount_paise bigint =0` check ≥ 0 · `currency text =INR` · `coupon_id uuid ∅` → coupons · `renewal_of_membership_id uuid ∅` → memberships · `activated_at timestamptz ∅` · `cancelled_at timestamptz ∅` · `cancel_reason text ∅` · `created_at`, `updated_at`
- Indexes: unique partial `(member_id) where status in ('active','frozen')` — at most one live membership per member; `(tenant_id, status, ends_on)` (expiry and reminder scans); `member_id`; `plan_id`; `coupon_id`; `renewal_of_membership_id`.
- Privileges: no `delete` for `authenticated` (INT-001 — cancel, never delete).

**`membership_pauses`** — approved freezes (STK-002, NSH-002). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `membership_id` → memberships · `starts_on date` · `ends_on date` check ≥ starts_on · `reason text` check ≠ '' · `requested_by_staff_id uuid ∅` → staff · `approved_by_staff_id uuid ∅` → staff · `approved_at timestamptz ∅` · `rejected_at timestamptz ∅` · check not both `approved_at` and `rejected_at` · `created_at`, `updated_at`
- Indexes: `membership_id`; `(tenant_id, starts_on, ends_on)`; `requested_by_staff_id`; `approved_by_staff_id`.

**`payments`** — one row per attempt to collect money, gateway or offline. The provider is the source of truth for `status` (PAY-006); a `created`/`pending` row is never `paid` (PAY-007). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `membership_id uuid ∅` → memberships (what this payment buys; add-on orders point at payments from their side) · `mandate_id uuid ∅` → razorpay_mandates · `coupon_id uuid ∅` → coupons · `amount_paise bigint` check > 0 · `currency text =INR` · `status payment_status =created` · `method payment_method` · `provider text ∅` (`razorpay`) · `provider_order_id text ∅` · `provider_payment_id text ∅` · `receipt_number text ∅` · `recorded_by_staff_id uuid ∅` → staff · `idempotency_key text ∅` · `paid_at timestamptz ∅` · `failed_reason text ∅` · `notes text ∅` · `created_at`, `updated_at`
- Checks: `status <> 'paid' or provider_payment_id is not null or receipt_number is not null` (DQA-002 made structural) · `method = 'razorpay' or recorded_by_staff_id is not null` (PAY-011: an offline payment carries staff attribution) · `method <> 'razorpay' or provider_order_id is not null`.
- Indexes: unique `(tenant_id, provider, provider_payment_id) where provider_payment_id is not null`; unique `(tenant_id, receipt_number) where receipt_number is not null`; unique `(tenant_id, idempotency_key) where idempotency_key is not null`; `member_id`; `membership_id`; `mandate_id`; `coupon_id`; `recorded_by_staff_id`; `(tenant_id, status, created_at)`.
- Privileges: no `delete` for `authenticated` (INT-001).

**`refunds`** — refunds and reversals as their own rows, never a mutation of the payment (PAY-010). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `payment_id` → payments · `kind refund_kind` · `amount_paise bigint` check > 0 · `currency text =INR` · `status refund_status =requested` · `provider_refund_id text ∅` · `reason text` check ≠ '' · `initiated_by_staff_id uuid ∅` → staff · `processed_at timestamptz ∅` · `created_at`, `updated_at`
- Indexes: `payment_id`; `initiated_by_staff_id`; unique `(tenant_id, provider_refund_id) where provider_refund_id is not null`.
- Privileges: no `delete` for `authenticated`.

**`webhook_events`** — every Razorpay delivery, verified or not (`docs/security.md`, payment integrity). The unique key is what makes PAY-009 idempotent. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `provider text =razorpay` · `event_id text` · `event_type text` · `payload jsonb` · `signature_valid boolean` · `received_at timestamptz =now()` · `processed_at timestamptz ∅` · `processing_error text ∅`
- Indexes: unique `(tenant_id, provider, event_id)`; partial `(tenant_id, received_at) where processed_at is null`.
- Privileges: no `delete` for `authenticated`. No `updated_at`: rows are written once, then `processed_at` is stamped.

**`invoices`** — GST invoices, numbered per gym per financial year. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `payment_id` → payments, unique · `invoice_number text` · `financial_year text` check `^[0-9]{4}-[0-9]{2}$` (e.g. `2026-27`) · `issued_at timestamptz =now()` · `seller_gstin text ∅` · `buyer_name text` · `buyer_gstin text ∅` · `place_of_supply text ∅` · `taxable_paise bigint` check ≥ 0 · `cgst_paise bigint =0` check ≥ 0 · `sgst_paise bigint =0` check ≥ 0 · `igst_paise bigint =0` check ≥ 0 · `total_paise bigint` check ≥ 0 · `currency text =INR` · `line_items jsonb =[]` · `pdf_url text ∅` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, invoice_number)`; `(tenant_id, financial_year)`.
- Privileges: no `delete` for `authenticated`.

**`document_counters`** — next number per gym, per document kind, per financial year (invoice prefix + financial-year reset from the settings row). Tenant path: direct.
- `tenant_id` → organizations · `kind text` check in (`invoice`, `receipt`) · `financial_year text` check as invoices · `next_number integer =1` check > 0 · `updated_at` · pk `(tenant_id, kind, financial_year)`.

**`razorpay_accounts`** — a gym's own Razorpay connection (ADR-008/015). Secrets live in Supabase Vault; this row holds only the Vault secret ids (Phase 5 wires Vault). Tenant path: `tenant_id` is the pk.
- `tenant_id uuid` pk → organizations · `key_id text` · `key_secret_vault_id uuid` · `webhook_secret_vault_id uuid` · `verified_at timestamptz ∅` (the ₹1 test payment) · `is_enabled boolean =false` · `created_at`, `updated_at`

**`razorpay_mandates`** — UPI Autopay via Razorpay Subscriptions; schema reserved now, unused until Phase 2 wires `subscription.*` webhooks. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `provider_customer_id text ∅` · `provider_subscription_id text` · `provider_plan_id text ∅` · `status mandate_status =created` · `max_amount_paise bigint` check > 0 · `currency text =INR` · `authenticated_at timestamptz ∅` · `next_charge_at timestamptz ∅` · `ends_at timestamptz ∅` · `cancelled_at timestamptz ∅` · `raw jsonb ∅` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, provider_subscription_id)`; `member_id`; `(tenant_id, status)`.
- Privileges: no `delete` for `authenticated`.

### Cluster: attendance

**`qr_sessions`** — rotating / session-bound QR codes (ATT-003). Only a hash of the token is stored. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `branch_id` → branches · `token_hash text` unique · `issued_at timestamptz =now()` · `expires_at timestamptz` check > issued_at · `revoked_at timestamptz ∅` · `created_by_staff_id uuid ∅` → staff · `created_at`
- Indexes: `(tenant_id, expires_at)`; `branch_id`; `created_by_staff_id`.

**`attendance`** — one row per visit. Check-out is optional (ATT-008). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `branch_id` → branches · `member_id` → members · `membership_id uuid ∅` → memberships (the live membership at check-in) · `checked_in_at timestamptz =now()` · `checked_out_at timestamptz ∅` check ≥ checked_in_at · `source attendance_source` · `qr_session_id uuid ∅` → qr_sessions · `assisted_by_staff_id uuid ∅` → staff · `assist_reason text ∅` · `client_event_id uuid ∅` (device-generated key for offline replay) · `offline_recorded_at timestamptz ∅` · `replayed_at timestamptz ∅` · `created_at`
- Checks: `source <> 'front_desk' or (assisted_by_staff_id is not null and assist_reason is not null and assist_reason <> '')` (ATT-005/006) · `(assisted_by_staff_id is null) = (assist_reason is null)` · `(offline_recorded_at is null) = (replayed_at is null)` (ATT-007's audit stamp is both timestamps or neither).
- Indexes: unique `(tenant_id, client_event_id) where client_event_id is not null` (exactly-once replay); `(tenant_id, member_id, checked_in_at desc)`; `(tenant_id, checked_in_at)`; `membership_id`; `branch_id`; `qr_session_id`; `assisted_by_staff_id`.
- Privileges: no `delete` for `authenticated` — a wrong visit is corrected, never removed. No `updated_at`.

**`attendance_corrections`** — append-only. A correction without a reason is impossible, not merely flagged (DQA-003). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `attendance_id` → attendance · `corrected_by_staff_id` → staff · `reason text` check ≠ '' · `before jsonb` · `after jsonb` · `created_at`
- Indexes: `attendance_id`; `corrected_by_staff_id`.
- Privileges: append-only — no `update`, no `delete` for `authenticated` (INT-001).

**`organization_holidays`** — the gym's holiday calendar (a holiday is never a streak break). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `holiday_on date` · `name text ∅` · `created_at`
- Indexes: unique `(tenant_id, holiday_on)`.

### Cluster: retention

**`no_show_cases`** — opened by the daily scan when absence crosses the gym's threshold; exactly one live case per member (NSH-003/004). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `status no_show_case_status =open` · `opened_on date =today_ist` · `last_attended_on date ∅` · `absent_days_at_open integer` check ≥ 0 · `threshold_days integer` check > 0 (snapshot of the setting) · `assigned_to_staff_id uuid ∅` → staff · `contacted_at timestamptz ∅` · `next_follow_up_at timestamptz ∅` · `returned_at timestamptz ∅` · `closed_at timestamptz ∅` · `created_at`, `updated_at`
- Indexes: unique partial `(member_id) where status in ('open','contacted','follow_up_due')`; `(tenant_id, status)`; `assigned_to_staff_id`; `(tenant_id, next_follow_up_at) where status = 'follow_up_due'`.
- Privileges: no `delete` for `authenticated` (INT-001: follow-up history, and the case that holds it, is kept).

**`follow_ups`** — the contact log, append-only (NSH-007). A correction is a new row pointing at the one it corrects. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `case_id` → no_show_cases · `staff_id` → staff · `channel contact_channel` · `outcome follow_up_outcome` · `notes text ∅` · `next_action text ∅` · `next_follow_up_at timestamptz ∅` · `corrects_follow_up_id uuid ∅` → follow_ups · `created_at`
- Indexes: `(case_id, created_at)`; `staff_id`; `corrects_follow_up_id`.
- Privileges: append-only — no `update`, no `delete` for `authenticated`.

### Cluster: catalogue

**`addon_products`** — PT packages, diet plans, products/supplements. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `kind addon_kind` · `name text` · `description text ∅` · `price_paise bigint` check ≥ 0 · `currency text =INR` · `gst_rate_bp smallint =0` check 0–10000 · `validity_days integer ∅` check > 0 · `session_count integer ∅` check > 0 · `trainer_staff_id uuid ∅` → staff · `stock_quantity integer ∅` check ≥ 0 (DQA-004/ADD-004 made structural) · `cancellation_terms text ∅` (ADD-002) · `is_active boolean =true` · `sort_order smallint =0` · `created_at`, `updated_at`
- Checks: `kind <> 'pt_package' or session_count is not null` · `kind <> 'product' or stock_quantity is not null`.
- Indexes: unique `(tenant_id, name)`; `(tenant_id, kind, is_active)`; `trainer_staff_id`.

**`addon_orders`** — a member's purchase of an add-on and its usage state. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `addon_product_id` → addon_products · `payment_id uuid ∅` → payments · `status addon_order_status =pending` · `quantity integer =1` check > 0 · `unit_price_paise bigint` check ≥ 0 · `total_paise bigint` check ≥ 0 · `currency text =INR` · `trainer_staff_id uuid ∅` → staff · `sessions_total integer ∅` check > 0 · `sessions_used integer =0` check ≥ 0 · `starts_on date ∅` · `expires_on date ∅` check ≥ starts_on · `cancelled_at timestamptz ∅` · `created_at`, `updated_at`
- Checks: `sessions_total is null or sessions_used <= sessions_total` (ADD-004) · `status in ('pending','cancelled') or payment_id is not null or total_paise = 0` (a paid order carries its payment).
- Indexes: `member_id`; `addon_product_id`; `payment_id`; `trainer_staff_id`; `(tenant_id, status)`.
- Privileges: no `delete` for `authenticated` (INT-001).

**`pt_sessions`** — scheduled personal-training sessions; a trainer cannot be double-booked (DQA-005 as an exclusion constraint). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `addon_order_id` → addon_orders · `trainer_staff_id` → staff · `member_id` → members · `starts_at timestamptz` · `ends_at timestamptz` check > starts_at · `status pt_session_status =scheduled` · `notes text ∅` · `created_at`, `updated_at`
- Constraints: `exclude using gist (trainer_staff_id with =, tstzrange(starts_at, ends_at) with &&) where (status in ('scheduled','completed'))` — needs `btree_gist`, created in this cluster's migration.
- Indexes: `addon_order_id`; `member_id`; `(tenant_id, trainer_staff_id, starts_at)`.

### Cluster: comms

**`message_templates`** — per-gym copy per channel and locale. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `key text` · `channel notification_channel` · `locale text =en` check `^[a-z]{2}$` · `body text` · `is_active boolean =true` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, key, channel, locale)`.

**`notifications`** — every scheduled or sent message; the de-dupe key is what makes PAY-002 (one message per stage) structural. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `channel notification_channel` · `template_key text ∅` · `status notification_status =scheduled` · `dedupe_key text ∅` (e.g. `renewal:<membership_id>:expiry_minus_7`) · `scheduled_for timestamptz =now()` · `sent_at timestamptz ∅` · `delivered_at timestamptz ∅` · `clicked_at timestamptz ∅` · `converted_at timestamptz ∅` · `failed_reason text ∅` · `related_type text ∅` · `related_id uuid ∅` · `payload jsonb ={}` · `created_at`, `updated_at`
- Indexes: unique `(tenant_id, dedupe_key) where dedupe_key is not null`; `(tenant_id, status, scheduled_for)`; `member_id`; `(related_type, related_id)`.

**`member_devices`** — the devices a member has registered for push, ADR-016's v1 primary channel. A `notifications` row with no device to deliver to is a dead end, so this table exists in Phase 1 rather than arriving with a Phase 3 migration. Deliberately minimal: it carries no delivery-receipt state, which belongs on `notifications`. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `platform text` check in (`ios`, `android`, `web`) · `push_token text` unique (globally — a token identifies one app install, so the same token at two gyms is the same device and must not be duplicated) · `last_seen_at timestamptz =now()` · `is_active boolean =true` · `created_at`, `updated_at`
- Indexes: unique `(push_token)`; `(tenant_id, member_id)`.

**`consents`** — versioned, append-only consent entries (DPD-002/003/004, INT-002). Current state = latest row per (member, purpose). Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `member_id` → members · `purpose consent_purpose` · `granted boolean` · `version text` check ≠ '' · `source text` check ≠ '' · `recorded_at timestamptz =now()` · `recorded_by_staff_id uuid ∅` → staff
- Indexes: `(member_id, purpose, recorded_at desc)`; `recorded_by_staff_id`.
- Privileges: append-only — no `update`, no `delete` for `authenticated` (withdrawal is a new row with `granted = false`).

**`messaging_wallets`** — the per-gym credit wallet ADR-016 requires from day one. Tenant path: `tenant_id` is the pk.
- `tenant_id uuid` pk → organizations · `balance_credits bigint =0` check ≥ 0 · `updated_at`

**`messaging_wallet_ledger`** — every credit movement, append-only; the balance is the sum. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `delta_credits bigint` check ≠ 0 · `reason text` check ≠ '' · `notification_id uuid ∅` → notifications · `created_at`
- Indexes: `(tenant_id, created_at)`; `notification_id`.
- Privileges: append-only.

### Cluster: platform

**`platform_users`** — Super Admin and platform support. Tenant path: **none, by design** (ADR-033) — visible only to platform roles.
- `user_id uuid` pk → `auth.users(id)` on delete cascade · `role app_role` check in (`super_admin`, `platform_support`) · `full_name text` · `email text` · `is_active boolean =true` · `created_at`, `updated_at`
- RLS: only the platform-access policy; no tenant policy.

**`impersonation_sessions`** — a platform user acting as a gym owner (`docs/security.md`, Impersonation). Tenant path: direct (the target gym).
- `id uuid` pk · `tenant_id` → organizations · `actor_user_id uuid` → platform_users · `reason text` check ≠ '' · `started_at timestamptz =now()` · `expires_at timestamptz` check > started_at · `ended_at timestamptz ∅` · `created_at`
- Indexes: `actor_user_id`; `(tenant_id, started_at desc)`.
- RLS: platform-access policy for everything; the tenant policy is **select only** (the gym can see who impersonated it and when).
- Privileges: no `delete` for `authenticated` (INT-003 history).

**`audit_log`** — INT-003. Append-only; rows with a null tenant are platform-level (role changes among platform users) and visible only to platform roles. Tenant path: direct, nullable.
- `id uuid` pk · `tenant_id uuid ∅` → organizations · `actor_user_id uuid ∅` · `actor_role app_role ∅` · `impersonation_session_id uuid ∅` → impersonation_sessions · `action text` check ≠ '' (`<record_type>.<verb>`) · `record_type text` check ≠ '' · `record_id uuid ∅` · `before jsonb ∅` · `after jsonb ∅` · `reason text ∅` · `occurred_at timestamptz =now()`
- Indexes: `(tenant_id, occurred_at desc)`; `(record_type, record_id)`; `impersonation_session_id`.
- Privileges: append-only — no `update`, no `delete` for `authenticated`. Audit rows are themselves under INT-001.

**`leads`** — enquiries: walk-in → trial → conversion, with source tracking. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `branch_id` → branches · `full_name text` · `phone text` check E.164 · `email text ∅` · `source lead_source` · `stage lead_stage =new` · `assigned_to_staff_id uuid ∅` → staff · `trial_at timestamptz ∅` · `converted_member_id uuid ∅` → members · `converted_at timestamptz ∅` · `lost_reason text ∅` · `notes text ∅` · `created_at`, `updated_at`
- Checks: `stage <> 'converted' or converted_member_id is not null`.
- Indexes: `(tenant_id, stage)`; `(tenant_id, phone)`; `branch_id`; `assigned_to_staff_id`; `converted_member_id`.

**`member_imports`** — a CSV/Excel import run with its column mapping and duplicate report. Tenant path: direct.
- `id uuid` pk · `tenant_id` → organizations · `uploaded_by_staff_id` → staff · `file_name text` · `column_mapping jsonb` · `status import_status =pending` · `row_count integer ∅` check ≥ 0 · `imported_count integer ∅` check ≥ 0 · `duplicate_count integer ∅` check ≥ 0 · `error_report jsonb ∅` · `created_at`, `updated_at`
- Indexes: `uploaded_by_staff_id`; `(tenant_id, created_at desc)`.

### Foreign-key direction across clusters (merge order)

`tenancy` → `membership+money` (needs members, staff) → `attendance` (needs memberships) → `catalogue` (needs payments) → `retention`, `comms`, `platform` (need only tenancy). A cluster never references a table from a cluster merged after it; where two clusters share a seam (payments ↔ add-on orders) the later table carries the foreign key (`addon_orders.payment_id`).

## Enums

### The seven canonical status vocabularies (with legal transitions — gate 14)

Each list below is the enum's label set, then its legal transitions; anything not listed is illegal. Phase 1 documents the graph next to the enum (this is that); the code that enforces it, and the illegal-transition tests, arrive with the phase that first mutates the status (3, 4, 5).

- **`member_status`**: `active`, `paused`, `expired`, `cancelled`, `blocked`. Transitions: active→paused, paused→active, active→expired, expired→active (renewal), active→cancelled, paused→cancelled, expired→cancelled, any→blocked, blocked→active.
- **`membership_status`**: `pending`, `active`, `frozen`, `expired`, `cancelled`. Transitions: pending→active (verified payment only, PAY-008), pending→cancelled, active→frozen, frozen→active, active→expired, frozen→expired, active→cancelled, frozen→cancelled. `expired` and `cancelled` are terminal; a renewal is a new row.
- **`no_show_case_status`**: `open`, `contacted`, `follow_up_due`, `returned`, `closed`. Transitions: open→contacted, contacted→follow_up_due, follow_up_due→contacted, open|contacted|follow_up_due→returned (a check-in, NSH-005), returned→closed, open|contacted|follow_up_due→closed. `closed` is terminal.
- **`payment_status`**: `created`, `pending`, `paid`, `failed`, `refunded`, `reversed`. Transitions: created→pending, created→paid, pending→paid, created→failed, pending→failed, paid→refunded, paid→reversed. Never anything→paid except from created/pending on a verified provider event (PAY-007/008). `failed`, `refunded`, `reversed` are terminal.
- **`addon_order_status`**: `pending`, `paid`, `active`, `completed`, `cancelled`, `refunded`. Transitions: pending→paid, paid→active, active→completed, pending→cancelled, paid→cancelled, paid|active→refunded. `completed`, `cancelled`, `refunded` are terminal.
- **`notification_status`**: `scheduled`, `sent`, `delivered`, `failed`, `clicked`, `converted`, `opted_out`. Transitions: scheduled→sent, scheduled→opted_out, scheduled→failed, sent→delivered, sent→failed, delivered→clicked, clicked→converted, delivered→converted.
- **`follow_up_outcome`**: `will_return`, `injured`, `travelling`, `timing_issue`, `unhappy`, `no_response`, `cancelled`. Not a state machine — an outcome is recorded once per follow-up row.

### Attribute vocabularies (closed sets, also Postgres enums)

- `app_role`: `super_admin`, `platform_support`, `gym_owner`, `gym_manager`, `front_desk`, `trainer`, `member` — the one source for roles (replaces `ROLES` in `packages/shared`, ADR-031).
- `organization_status`: `pending_approval`, `trial`, `active`, `suspended`, `closed`. Transitions: pending_approval→trial, pending_approval→active, trial→active, trial→closed, active→suspended, suspended→active, active→closed, suspended→closed.
- `gym_preset`: `neighbourhood_gym`, `premium_studio`, `functional_box`.
- `streak_rule_type`: `visit_streak`, `weekly_goal`, `calendar_streak` (STK-001).
- `payment_method`: `razorpay`, `cash`, `upi`, `card`, `bank_transfer`.
- `refund_kind`: `refund`, `reversal`. `refund_status`: `requested`, `processing`, `completed`, `failed` (requested→processing→completed|failed; requested→failed).
- `mandate_status` (mirrors Razorpay subscription states): `created`, `authenticated`, `active`, `paused`, `halted`, `cancelled`, `completed`, `expired`.
- `attendance_source`: `qr`, `front_desk`.
- `addon_kind`: `pt_package`, `diet_plan`, `product`.
- `pt_session_status`: `scheduled`, `completed`, `cancelled`, `no_show` (scheduled→completed|cancelled|no_show).
- `notification_channel`: `push`, `whatsapp_link`, `in_app`, `sms`, `email` (v1 sends only the first three — ADR-016).
- `consent_purpose`: `marketing`, `service` (INT-002 — independently withdrawable).
- `contact_channel`: `call`, `whatsapp`, `in_person`, `sms`.
- `lead_source`: `walk_in`, `referral`, `instagram`, `google`, `website`, `phone`, `other`. `lead_stage`: `new`, `contacted`, `trial_scheduled`, `trial_done`, `converted`, `lost` (new→contacted→trial_scheduled→trial_done→converted; any non-terminal→lost).
- `import_status`: `pending`, `processing`, `completed`, `failed`.

## Phase 2 accommodations required in the schema now

The master prompt is explicit: Phase 2 features are accommodated by the **schema**, never by speculative code. Phase 1 must leave room for:

- **Multi-branch**: `organization → branch` hierarchy (above), even though v1 UI shows one branch.
- **UPI Autopay**: Razorpay subscription **mandate tables**, unused until Phase 2's `subscription.*` webhooks are wired. v1 uses Orders API + Payment Links only.
- Everything else in Phase 2's list (trainer app, class/batch scheduling, payroll/commission, body measurements, wearables, referrals, advanced inventory, cross-gym benchmarking, WhatsApp Business API, per-permission role matrix) needs **no schema reservation** — none of it changes the shape of v1's core tables.

## Money and time

Money is **integer paise**, never floating point, with an explicit currency column and a tested rounding rule (gate 16). All scheduled logic (no-show scans, renewal reminders) is timezone-correct **per gym** (`organizations.timezone`), tested across date boundaries (gate 15).

## Per-gym configuration ("the template that makes this sellable")

One row per organization, minimum: name, logo, brand accent, address, timezone, currency, opening hours, GSTIN, invoice prefix + financial-year reset, week-start day, plans/prices/discounts, no-show threshold days, streak rule type, renewal reminder windows (`RENEWAL_REMINDER_WINDOWS`; each has an explicit `daysFromExpiry` where negative = before expiry and positive = after, so the post-due window is `+3` — see PAY-001), grace-period days after expiry, allowed pause reasons + approver, max freeze days/year, holiday calendar, follow-up outcome list, add-on catalogue, staff/trainers, trainer-to-member cap, message templates, receipt/invoice numbering.

## RLS policy map (shape, not final policy text)

- Every table carries `tenant_id` (the `organization_id`) or is reachable via one JOIN to a table that does (gate 6).
- The tenant id is read from the JWT claim set by the custom access-token hook — RLS policies reference that claim directly, never a subquery against another table (gate 8).
- RLS columns (`tenant_id` and any FK used in a policy predicate) are indexed (gate 8).
- A pgTAP cross-tenant leak suite exists per table: Gym A must never read Gym B's rows under any role (gate 7).
- `super_admin` and `platform_support` roles bypass tenant scoping by policy design, not by disabling RLS — impersonation of a gym owner writes an audit row and carries a persistent banner (`docs/security.md`).

## Data-quality alerts (data integrity, not a feature)

Flag, do not silently accept: membership without expiry date · paid order without provider reference · attendance correction without reason · negative product stock · trainer double-booking.

## What Phase 1 must produce (exit criteria, see `docs/roadmap.md`)

Schema, enums, RLS, indexes, `supabase gen types` output, and a seed script — pgTAP cross-tenant suite green on every table, one command seeds a complete demo gym (the exact seed shape, recorded here because Phase 0 never wrote a separate seed spec and the master prompt is disposable: one Tier-2 neighbourhood gym, 30 members, 3 trainers + 1 front-desk user, 4 plan tiers, 6 members absent 10–20 days, 5 memberships expiring within 7 days, PT/diet/supplement add-ons, a few leads at different stages).
