-- Cluster: retention (merge 5 of 7).
-- Implements docs/data-model.md § Conventions (the contract), § Tables → "Cluster: retention",
-- and the three retention vocabularies in § Enums.
-- Domain rules: NSH-003, NSH-004, NSH-005, NSH-007, INT-001.
-- Depends on the tenancy contract migration only: schema `app`, `app.current_tenant_id()`,
-- `app.is_platform()`, `app.touch_updated_at()`, `public.organizations`, `public.members`,
-- `public.staff`. None of those is re-created or altered here.
-- No extensions: `gen_random_uuid()` is core in Postgres 17.

-- ---------------------------------------------------------------------------
-- 2. Enum types
-- ---------------------------------------------------------------------------

-- Labels in the exact order docs/data-model.md § Enums lists them; the order is
-- part of the contract because it is what `supabase gen types` emits and what any
-- `order by` on the column follows. The transition graph is documentation in
-- Phase 1 — Phase 4 writes the enforcement and the illegal-transition tests.
create type public.no_show_case_status as enum (
  'open',
  'contacted',
  'follow_up_due',
  'returned',
  'closed'
);

create type public.contact_channel as enum (
  'call',
  'whatsapp',
  'in_person',
  'sms'
);

create type public.follow_up_outcome as enum (
  'will_return',
  'injured',
  'travelling',
  'timing_issue',
  'unhappy',
  'no_response',
  'cancelled'
);

-- ---------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------

-- Opened by Phase 4's daily scan when absence crosses the gym's threshold.
-- `absent_days_at_open` and `threshold_days` are snapshots: a later change to
-- `organization_settings.no_show_threshold_days` must not rewrite the history of
-- why a case exists.
create table public.no_show_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  status public.no_show_case_status not null default 'open',
  -- ADR-039: never `current_date`. `current_date` evaluates in the session
  -- timezone and every Supabase connection is UTC, so between 00:00 and 05:30 IST
  -- it returns yesterday. The literal duplicates `DEFAULT_TIMEZONE` in
  -- packages/shared/src/config/constants.ts, which a migration cannot import.
  opened_on date not null default (now() at time zone 'Asia/Kolkata')::date,
  last_attended_on date,
  absent_days_at_open integer not null
    constraint no_show_cases_absent_days_at_open_chk check (absent_days_at_open >= 0),
  threshold_days integer not null
    constraint no_show_cases_threshold_days_chk check (threshold_days > 0),
  assigned_to_staff_id uuid references public.staff (id),
  contacted_at timestamptz,
  next_follow_up_at timestamptz,
  returned_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The contact log (NSH-007). Append-only by privilege, not by trigger: a
-- correction is a new row pointing at the one it corrects.
create table public.follow_ups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  case_id uuid not null references public.no_show_cases (id),
  staff_id uuid not null references public.staff (id),
  channel public.contact_channel not null,
  outcome public.follow_up_outcome not null,
  notes text,
  next_action text,
  next_follow_up_at timestamptz,
  corrects_follow_up_id uuid references public.follow_ups (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. Constraints not expressible inline
-- ---------------------------------------------------------------------------

-- None: every check in this cluster is single-column and declared inline above.

-- ---------------------------------------------------------------------------
-- 5. Indexes
-- ---------------------------------------------------------------------------

-- NSH-003/NSH-004 made structural: at most one live case per member, so a
-- repeated scan run cannot open a duplicate. Also discharges index rule 2 for
-- `member_id` — the contract accepts a partial index for the FK rule, because the
-- referential-integrity probe is `where member_id = $1`, which implies this
-- predicate. No redundant standalone index is added.
-- ADR-047: keyed on (tenant_id, member_id), not member_id alone. A globally
-- unique key lets one gym take the live-case slot for another gym's member id
-- and block that gym's daily scan permanently -- the exact failure NSH-003/004
-- exist to prevent. member_id still leads position 2 of a tenant-leading
-- index, which satisfies the contract's foreign-key index rule.
create unique index no_show_cases_tenant_id_member_id_open_key
  on public.no_show_cases (tenant_id, member_id)
  where status in ('open', 'contacted', 'follow_up_due');

-- Index rule 1 for no_show_cases: non-partial, leading with the tenant column.
create index no_show_cases_tenant_id_status_idx
  on public.no_show_cases (tenant_id, status);

create index no_show_cases_assigned_to_staff_id_idx
  on public.no_show_cases (assigned_to_staff_id);

-- Phase 4's "which follow-ups are due" scan.
create index no_show_cases_tenant_id_next_follow_up_at_due_idx
  on public.no_show_cases (tenant_id, next_follow_up_at)
  where status = 'follow_up_due';

-- Index rule 1 for follow_ups: the contract flags this table as one whose
-- enumerated indexes include none leading with the tenant column, and names
-- `<table>_tenant_id_idx` as the fix.
create index follow_ups_tenant_id_idx
  on public.follow_ups (tenant_id);

create index follow_ups_case_id_created_at_idx
  on public.follow_ups (case_id, created_at);

create index follow_ups_staff_id_idx
  on public.follow_ups (staff_id);

create index follow_ups_corrects_follow_up_id_idx
  on public.follow_ups (corrects_follow_up_id);

-- ---------------------------------------------------------------------------
-- 6. Row-Level Security
-- ---------------------------------------------------------------------------

-- No `force row level security` (ADR-037): it only ever changes what the table
-- owner sees, and isolation is proven for `authenticated`.
alter table public.no_show_cases enable row level security;
alter table public.follow_ups enable row level security;

-- ---------------------------------------------------------------------------
-- 7. Policies
-- ---------------------------------------------------------------------------

-- Every accessor call is wrapped in `(select …)` so the planner evaluates it once
-- as an InitPlan instead of once per row.
create policy no_show_cases_tenant_all on public.no_show_cases
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy no_show_cases_platform_all on public.no_show_cases
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy follow_ups_tenant_all on public.follow_ups
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy follow_ups_platform_all on public.follow_ups
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- ---------------------------------------------------------------------------
-- 8. Privileges
-- ---------------------------------------------------------------------------

-- ADR-037: default privileges in `public` grant everything — including `delete`
-- and `truncate`, which RLS does not filter — to `anon` and `authenticated` on
-- every table `postgres` creates. Revoked and re-granted per table, written out in
-- full; never the `on all tables in schema public` form.

-- History tier: no `delete` (INT-001 — the case holds the follow-up history, so
-- resolving a case must not remove it).
revoke all on public.no_show_cases from anon, authenticated;
grant select, insert, update on public.no_show_cases to authenticated;

-- Append-only tier (NSH-007): no `update`, no `delete`. A correction is a new row.
revoke all on public.follow_ups from anon, authenticated;
grant select, insert on public.follow_ups to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Triggers
-- ---------------------------------------------------------------------------

-- `follow_ups` has no `updated_at` and therefore gets no trigger.
create trigger no_show_cases_touch_updated_at
  before update on public.no_show_cases
  for each row execute function app.touch_updated_at();
