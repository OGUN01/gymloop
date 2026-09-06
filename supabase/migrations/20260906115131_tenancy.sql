-- Cluster: tenancy — the contract migration (merge 1).
--
-- Implements docs/data-model.md:
--   § Conventions (the contract) — Naming · Migration file layout · Every table ·
--     The `app` schema and the two JWT accessors · Row-Level Security · Privileges ·
--     Indexes · Enums · The contract migration
--   § Tables → Cluster: tenancy — organizations, organization_settings, branches, staff, members
--   § Enums — app_role, organization_status, gym_preset, streak_rule_type, member_status
-- Specification: openspec/changes/0001-data-model/specs/tenancy/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-031 (app_role is the one role vocabulary),
--   ADR-032 (claim names + accessors), ADR-035 (uuid v4 keys), ADR-037 (per-table privileges,
--   no `force row level security`), ADR-039 (IST-local calendar-day defaults),
--   ADR-040/041 (check-constraint naming).
--
-- Statement order is the contract's: extensions → schema/functions → enum types → tables →
-- non-inline constraints → indexes → enable RLS → policies → privileges → triggers.
-- No begin/commit: CI applies this forward-only, one file per cluster.


-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------

create extension if not exists pgtap with schema extensions;


-- ---------------------------------------------------------------------------
-- 2. The `app` schema and the three shared functions
--    docs/data-model.md § The `app` schema and the two JWT accessors, § Every table.
--    `app` is not exposed by config.toml, so nothing here is an RPC and nothing here
--    reaches packages/db/types/database.ts. All three are `security invoker` with an
--    empty search_path; the two accessors are `stable` and read only the JWT claims GUC.
-- ---------------------------------------------------------------------------

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


-- ---------------------------------------------------------------------------
-- 3. Enum types owned by this cluster
--    docs/data-model.md § Enums. Label order is part of the contract: it is what
--    `supabase gen types` emits and what any `order by` on the column follows.
-- ---------------------------------------------------------------------------

create type public.app_role as enum (
  'super_admin',
  'platform_support',
  'gym_owner',
  'gym_manager',
  'front_desk',
  'trainer',
  'member'
);

create type public.organization_status as enum (
  'pending_approval',
  'trial',
  'active',
  'suspended',
  'closed'
);

create type public.gym_preset as enum (
  'neighbourhood_gym',
  'premium_studio',
  'functional_box'
);

create type public.streak_rule_type as enum (
  'visit_streak',
  'weekly_goal',
  'calendar_streak'
);

create type public.member_status as enum (
  'active',
  'paused',
  'expired',
  'cancelled',
  'blocked'
);


-- ---------------------------------------------------------------------------
-- 4. Tables
-- ---------------------------------------------------------------------------

-- organizations — the tenant. Its `id` *is* the tenant id, so its policies compare
-- `id` rather than `tenant_id`, and the primary key discharges index rule 1.
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  gym_code text not null
    constraint organizations_gym_code_key unique
    constraint organizations_gym_code_format_chk check (gym_code ~ '^[A-Z0-9]{6}$'),
  status public.organization_status not null default 'pending_approval',
  tier text,
  trial_ends_at timestamptz,
  activated_at timestamptz,
  timezone text not null default 'Asia/Kolkata',
  -- MNY-002/ADR-041: the gym's default currency carries the format check even though
  -- no money column sits beside it — a malformed value here propagates into every
  -- amount derived from it.
  currency text not null default 'INR'
    constraint organizations_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- organization_settings — the per-gym template, one row per organization.
-- `tenant_id` is the primary key, so it needs no separate index for rule 1 or rule 2.
create table public.organization_settings (
  tenant_id uuid primary key references public.organizations (id),
  preset public.gym_preset,
  logo_url text,
  brand_accent text
    constraint organization_settings_brand_accent_format_chk
      check (brand_accent ~ '^#[0-9a-fA-F]{6}$'),
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  pincode text
    constraint organization_settings_pincode_format_chk check (pincode ~ '^[1-9][0-9]{5}$'),
  gstin text
    constraint organization_settings_gstin_format_chk
      check (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  invoice_prefix text not null default 'INV',
  receipt_prefix text not null default 'RCPT',
  financial_year_start_month smallint not null default 4
    constraint organization_settings_financial_year_start_month_chk
      check (financial_year_start_month between 1 and 12),
  -- 0 = Sunday.
  week_start_day smallint not null default 1
    constraint organization_settings_week_start_day_chk check (week_start_day between 0 and 6),
  opening_hours jsonb not null default '{}'::jsonb,
  no_show_threshold_days smallint not null default 7
    constraint organization_settings_no_show_threshold_days_chk check (no_show_threshold_days > 0),
  -- ATT-004 de-duplication window.
  checkin_dedupe_seconds integer not null default 120
    constraint organization_settings_checkin_dedupe_seconds_chk check (checkin_dedupe_seconds >= 0),
  streak_rule_type public.streak_rule_type not null default 'visit_streak',
  weekly_goal_default smallint not null default 3
    constraint organization_settings_weekly_goal_default_chk
      check (weekly_goal_default between 1 and 14),
  -- null = the platform default RENEWAL_REMINDER_WINDOWS; same axis as PAY-001,
  -- negative before expiry, positive after.
  renewal_reminder_days_from_expiry smallint[],
  grace_period_days smallint not null default 0
    constraint organization_settings_grace_period_days_chk check (grace_period_days >= 0),
  pause_reasons text[] not null default '{}'::text[],
  -- A pause approver is a member of gym-side staff, so the platform labels and
  -- `member` are excluded, exactly as on staff.role.
  pause_approver_role public.app_role not null default 'gym_manager'
    constraint organization_settings_pause_approver_role_chk
      check (pause_approver_role in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')),
  max_freeze_days_per_year smallint not null default 30
    constraint organization_settings_max_freeze_days_per_year_chk
      check (max_freeze_days_per_year >= 0),
  trainer_member_cap smallint
    constraint organization_settings_trainer_member_cap_chk check (trainer_member_cap > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- branches — the organization → branch hierarchy Phase 2's multi-branch UI needs.
-- v1 creates exactly one per organization, flagged default.
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  name text not null,
  address text,
  -- Overrides the organization's timezone when set.
  timezone text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branches_tenant_id_name_key unique (tenant_id, name)
);

-- staff — every gym-side login: owner, manager, front desk, trainer.
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  user_id uuid references auth.users (id) on delete set null,
  -- null = all branches.
  branch_id uuid references public.branches (id),
  role public.app_role not null
    constraint staff_role_chk check (role in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')),
  full_name text not null,
  phone text
    constraint staff_phone_format_chk check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email text,
  is_active boolean not null default true,
  -- ADD-002: shown to a member before a PT purchase.
  qualification text,
  max_active_clients smallint
    constraint staff_max_active_clients_chk check (max_active_clients > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- members — the gym's customer. DPD-008: photos yes, government ID never — there is
-- no column for one, and adding one is a specification change, not a migration.
create table public.members (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  branch_id uuid not null references public.branches (id),
  -- null until the member joins the app; phone auto-match sets it.
  user_id uuid references auth.users (id) on delete set null,
  -- Gym-visible id, front-desk search.
  member_code text,
  full_name text not null,
  phone text not null
    constraint members_phone_format_chk check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email text,
  gender text,
  date_of_birth date,
  photo_url text,
  status public.member_status not null default 'active',
  -- ADR-039: IST-local, never current_date — every Supabase session is UTC, so
  -- current_date returns yesterday between 00:00 and 05:30 IST. The literal
  -- duplicates DEFAULT_TIMEZONE in packages/shared/src/config/constants.ts.
  joined_on date not null default (now() at time zone 'Asia/Kolkata')::date,
  weekly_goal_visits smallint
    constraint members_weekly_goal_visits_chk check (weekly_goal_visits between 1 and 14),
  -- STK-002: weekday numbers, 0 = Sunday.
  rest_days smallint[] not null default '{}'::smallint[],
  -- STK-004.
  motivation_push_enabled boolean not null default true,
  notes text,
  -- DPD-006: personal columns blanked, row and financial history kept.
  erased_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint members_tenant_id_phone_key unique (tenant_id, phone)
);


-- ---------------------------------------------------------------------------
-- 5. Constraints not expressible inline
--    None: every check in this cluster is single-column and every total unique is a
--    table constraint above. Section kept so the seven migrations read the same.
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- 6. Indexes
--    Rule 1 (a non-partial btree leading with the tenant column) is discharged by the
--    primary key on organizations and organization_settings, by
--    branches_tenant_id_name_key, staff_tenant_id_role_idx and
--    members_tenant_id_phone_key elsewhere. Rule 2 (every FK column indexed, partial
--    allowed) is noted per index below.
-- ---------------------------------------------------------------------------

create index organizations_status_idx on public.organizations (status);

-- One default branch per organization.
create unique index branches_tenant_id_default_key
  on public.branches (tenant_id) where is_default;

-- Rule 2: staff.user_id — partial is sufficient, the RI probe `where user_id = $1`
-- implies the predicate.
create unique index staff_tenant_id_user_id_key
  on public.staff (tenant_id, user_id) where user_id is not null;
create index staff_tenant_id_role_idx on public.staff (tenant_id, role);
-- Rule 2: staff.branch_id.
create index staff_branch_id_idx on public.staff (branch_id);

-- Duplicate-phone detection for the CSV import is members_tenant_id_phone_key, above.
create unique index members_tenant_id_member_code_key
  on public.members (tenant_id, member_code) where member_code is not null;
create index members_tenant_id_status_idx on public.members (tenant_id, status);
-- Rule 2: members.branch_id.
create index members_branch_id_idx on public.members (branch_id);
-- Rule 2: members.user_id.
create unique index members_tenant_id_user_id_key
  on public.members (tenant_id, user_id) where user_id is not null;


-- ---------------------------------------------------------------------------
-- 7. Row-Level Security
--    Enabled in the same migration that creates the table, always. Never
--    `force row level security` (ADR-037).
-- ---------------------------------------------------------------------------

alter table public.organizations enable row level security;
alter table public.organization_settings enable row level security;
alter table public.branches enable row level security;
alter table public.staff enable row level security;
alter table public.members enable row level security;


-- ---------------------------------------------------------------------------
-- 8. Policies
--    Two permissive policies per table, both `for all to authenticated`. Every
--    accessor call is wrapped in `(select …)` so the planner evaluates it once as an
--    InitPlan instead of once per row. `with check` is not optional: `using` alone
--    would let a caller insert a row into another tenant, or move one there.
-- ---------------------------------------------------------------------------

create policy organizations_tenant_all on public.organizations
  for all to authenticated
  using (id = (select app.current_tenant_id()))
  with check (id = (select app.current_tenant_id()));

create policy organizations_platform_all on public.organizations
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy organization_settings_tenant_all on public.organization_settings
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy organization_settings_platform_all on public.organization_settings
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy branches_tenant_all on public.branches
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy branches_platform_all on public.branches
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy staff_tenant_all on public.staff
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy staff_platform_all on public.staff
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy members_tenant_all on public.members
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy members_platform_all on public.members
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));


-- ---------------------------------------------------------------------------
-- 9. Privileges
--    ADR-037: in `public`, the default ACL grants every privilege — including delete
--    and truncate, neither of which RLS filters — to anon and authenticated on every
--    table created by postgres. So the privilege is taken away explicitly, per table,
--    written out. Never the `on all tables in schema public` form. All five tables are
--    the `normal` tier: select, insert, update. `anon` is granted nothing anywhere;
--    `service_role` is never revoked from.
-- ---------------------------------------------------------------------------

revoke all on public.organizations from anon, authenticated;
grant select, insert, update on public.organizations to authenticated;

revoke all on public.organization_settings from anon, authenticated;
grant select, insert, update on public.organization_settings to authenticated;

revoke all on public.branches from anon, authenticated;
grant select, insert, update on public.branches to authenticated;

revoke all on public.staff from anon, authenticated;
grant select, insert, update on public.staff to authenticated;

revoke all on public.members from anon, authenticated;
grant select, insert, update on public.members to authenticated;


-- ---------------------------------------------------------------------------
-- 10. Triggers
--     One per table carrying `updated_at`, all calling the single shared function.
--     No other trigger: Phase 1 owns shape, not behaviour.
-- ---------------------------------------------------------------------------

create trigger organizations_touch_updated_at
  before update on public.organizations
  for each row execute function app.touch_updated_at();

create trigger organization_settings_touch_updated_at
  before update on public.organization_settings
  for each row execute function app.touch_updated_at();

create trigger branches_touch_updated_at
  before update on public.branches
  for each row execute function app.touch_updated_at();

create trigger staff_touch_updated_at
  before update on public.staff
  for each row execute function app.touch_updated_at();

create trigger members_touch_updated_at
  before update on public.members
  for each row execute function app.touch_updated_at();
