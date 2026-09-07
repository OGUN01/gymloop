-- Cluster: platform (merge 7 of 7).
-- Implements docs/data-model.md § Tables → "Cluster: platform" (platform_users,
-- impersonation_sessions, audit_log, leads, member_imports) and the three enums
-- this cluster owns in § Enums (lead_source, lead_stage, import_status), under
-- § Conventions (the contract): naming, migration file layout, every-table rules,
-- § Audit rows, § Tenant-path exceptions, § Row-Level Security, § Privileges,
-- § Indexes.
--
-- Both of the schema's tenant-path exceptions live here (ADR-033):
--   platform_users has no tenant column and carries only the platform policy;
--   audit_log.tenant_id is nullable, and a null-tenant row is invisible to every
--   gym because `null = <uuid>` is null, not true — no third policy is needed.
-- Nothing writes to audit_log in Phase 1 (§ Audit rows): no audit trigger, no
-- writer function. INT-003's rows arrive with the phases that perform the actions.
--
-- Depends on the tenancy contract migration only: schema `app` and its three
-- functions, the `app_role` enum, and organizations / branches / staff / members.

-- 1. extensions
-- none: this cluster installs no extension.

-- 2. enum types

create type public.lead_source as enum (
  'walk_in',
  'referral',
  'instagram',
  'google',
  'website',
  'phone',
  'other'
);

create type public.lead_stage as enum (
  'new',
  'contacted',
  'trial_scheduled',
  'trial_done',
  'converted',
  'lost'
);

create type public.import_status as enum (
  'pending',
  'processing',
  'completed',
  'failed'
);

-- 3. tables

-- Super Admin and platform support. Tenant path: none, by design (ADR-033).
create table public.platform_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role public.app_role not null
    constraint platform_users_role_chk
      check (role in ('super_admin', 'platform_support')),
  full_name text not null,
  email text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A platform user acting as a gym owner (docs/security.md, Impersonation).
-- Tenant path: direct (the target gym).
create table public.impersonation_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  actor_user_id uuid not null references public.platform_users (user_id),
  reason text not null
    constraint impersonation_sessions_reason_chk check (reason <> ''),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz
    constraint impersonation_sessions_ended_at_after_started_at_chk
      check (ended_at is null or ended_at >= started_at),
  created_at timestamptz not null default now()
);

-- INT-003's storage. Append-only by privilege. Tenant path: direct, nullable
-- (ADR-033) — a row with no tenant is platform-level.
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.organizations (id),
  actor_user_id uuid,
  actor_role public.app_role,
  impersonation_session_id uuid references public.impersonation_sessions (id),
  action text not null
    constraint audit_log_action_format_chk
      check (action ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),
  record_type text not null
    constraint audit_log_record_type_chk check (record_type <> ''),
  record_id uuid,
  before jsonb,
  after jsonb,
  reason text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Enquiries: walk-in -> trial -> conversion, with source tracking.
-- Tenant path: direct.
create table public.leads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  branch_id uuid not null references public.branches (id),
  full_name text not null,
  phone text not null
    constraint leads_phone_format_chk check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email text,
  source public.lead_source not null,
  stage public.lead_stage not null default 'new',
  assigned_to_staff_id uuid references public.staff (id),
  trial_at timestamptz,
  converted_member_id uuid references public.members (id),
  converted_at timestamptz,
  lost_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A CSV/Excel import run with its column mapping and duplicate report.
-- Tenant path: direct.
create table public.member_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  uploaded_by_staff_id uuid not null references public.staff (id),
  file_name text not null,
  column_mapping jsonb not null,
  status public.import_status not null default 'pending',
  row_count integer
    constraint member_imports_row_count_chk check (row_count >= 0),
  imported_count integer
    constraint member_imports_imported_count_chk check (imported_count >= 0),
  duplicate_count integer
    constraint member_imports_duplicate_count_chk check (duplicate_count >= 0),
  error_report jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4. constraints not expressible inline

-- An impersonation session has a hard TTL, not an indefinite one
-- (docs/security.md, Impersonation).
alter table public.impersonation_sessions
  add constraint impersonation_sessions_expires_at_after_started_at_chk
    check (expires_at > started_at);

-- A converted lead names the member it became.
alter table public.leads
  add constraint leads_converted_has_member_chk
    check (stage <> 'converted' or converted_member_id is not null);

-- 5. indexes

-- platform_users is exempt from index rule 1 (no tenant column, ADR-033); its
-- primary key discharges rule 2 for user_id.

create index impersonation_sessions_tenant_id_started_at_idx
  on public.impersonation_sessions (tenant_id, started_at desc);
create index impersonation_sessions_actor_user_id_idx
  on public.impersonation_sessions (actor_user_id);

create index audit_log_tenant_id_occurred_at_idx
  on public.audit_log (tenant_id, occurred_at desc);
create index audit_log_record_type_record_id_idx
  on public.audit_log (record_type, record_id);
create index audit_log_impersonation_session_id_idx
  on public.audit_log (impersonation_session_id);

create index leads_tenant_id_stage_idx on public.leads (tenant_id, stage);
create index leads_tenant_id_phone_idx on public.leads (tenant_id, phone);
create index leads_branch_id_idx on public.leads (branch_id);
create index leads_assigned_to_staff_id_idx on public.leads (assigned_to_staff_id);
create index leads_converted_member_id_idx on public.leads (converted_member_id);

create index member_imports_tenant_id_created_at_idx
  on public.member_imports (tenant_id, created_at desc);
create index member_imports_uploaded_by_staff_id_idx
  on public.member_imports (uploaded_by_staff_id);

-- 6. row-level security

alter table public.platform_users enable row level security;
alter table public.impersonation_sessions enable row level security;
alter table public.audit_log enable row level security;
alter table public.leads enable row level security;
alter table public.member_imports enable row level security;

-- 7. policies

-- platform_users: the platform policy alone. No gym-side role reads it.
create policy platform_users_platform_all on public.platform_users
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- impersonation_sessions: the gym may see who impersonated it and when, and may
-- not write that record — the one tenant policy in the schema that is not `for all`.
create policy impersonation_sessions_tenant_select on public.impersonation_sessions
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()));

create policy impersonation_sessions_platform_all on public.impersonation_sessions
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy audit_log_tenant_all on public.audit_log
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy audit_log_platform_all on public.audit_log
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy leads_tenant_all on public.leads
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy leads_platform_all on public.leads
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy member_imports_tenant_all on public.member_imports
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy member_imports_platform_all on public.member_imports
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- 8. privileges (ADR-037)

revoke all on public.platform_users from anon, authenticated;
grant select, insert, update on public.platform_users to authenticated;

revoke all on public.impersonation_sessions from anon, authenticated;
grant select, insert, update on public.impersonation_sessions to authenticated;

-- Append-only: audit rows are themselves under INT-001.
revoke all on public.audit_log from anon, authenticated;
-- ADR-047, read-only tier: an audit row the audited party can write is not
-- evidence. With `insert` a gym could forge a row naming a platform user as
-- the actor, and nothing may ever delete it (INT-001). Audit writes arrive
-- from Phase 3+ on service_role, exactly as webhook_events' processed_at does.
grant select on public.audit_log to authenticated;

revoke all on public.leads from anon, authenticated;
grant select, insert, update on public.leads to authenticated;

revoke all on public.member_imports from anon, authenticated;
grant select, insert, update on public.member_imports to authenticated;

-- 9. triggers
-- Only the three tables that carry updated_at. impersonation_sessions and
-- audit_log have none, so they get no trigger.

create trigger platform_users_touch_updated_at
  before update on public.platform_users
  for each row execute function app.touch_updated_at();

create trigger leads_touch_updated_at
  before update on public.leads
  for each row execute function app.touch_updated_at();

create trigger member_imports_touch_updated_at
  before update on public.member_imports
  for each row execute function app.touch_updated_at();
