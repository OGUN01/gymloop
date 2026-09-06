-- Cluster: attendance (merge 3 of 7).
--
-- Implements docs/data-model.md:
--   § Tables → "Cluster: attendance" — qr_sessions, attendance,
--     attendance_corrections, organization_holidays.
--   § Enums → "Attribute vocabularies" — attendance_source, the one enum this
--     cluster owns per § Conventions → Enums (ownership table).
--   § Conventions (the contract) — Naming, Migration file layout, Every table,
--     Row-Level Security, Privileges, Indexes.
--
-- Requirements: ATT-003 (hash-only, expiring QR session), ATT-005/006 (assisted
-- check-in names staff + reason), ATT-007 (exactly-once offline replay and its
-- audit stamp), ATT-008 (check-out optional), DQA-003 + INT-001 (a visit is
-- corrected, never removed), STK-002 (holiday calendar).
--
-- Depends on, and never re-creates: schema `app` and app.current_tenant_id() /
-- app.is_platform() (tenancy contract migration), organizations, branches, staff,
-- members (tenancy), memberships (membership+money).
--
-- No extensions. No triggers: no table in this cluster carries `updated_at`, and
-- § Every table says a table with no `updated_at` gets no trigger. ATT-004's
-- de-duplication window is organization_settings.checkin_dedupe_seconds, read by
-- application logic in Phase 3 — Phase 1 owns shape, not behaviour.


-- ---------------------------------------------------------------------------
-- Enum types
-- ---------------------------------------------------------------------------

create type public.attendance_source as enum ('qr', 'front_desk');


-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- Rotating / session-bound QR codes (ATT-003). Only a hash of the token is
-- stored; there is no column anywhere for a raw token. `created_at` is when the
-- row was inserted, `issued_at` is when the token was issued — both are kept,
-- per § Every table.
create table public.qr_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  branch_id uuid not null references public.branches (id),
  token_hash text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by_staff_id uuid references public.staff (id),
  created_at timestamptz not null default now(),
  constraint qr_sessions_token_hash_key unique (token_hash),
  constraint qr_sessions_expires_at_after_issued_at_chk check (expires_at > issued_at)
);

-- One row per visit. Check-out is optional (ATT-008); a check-out earlier than
-- its check-in is not.
create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  branch_id uuid not null references public.branches (id),
  member_id uuid not null references public.members (id),
  membership_id uuid references public.memberships (id),
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  source public.attendance_source not null,
  qr_session_id uuid references public.qr_sessions (id),
  assisted_by_staff_id uuid references public.staff (id),
  assist_reason text,
  client_event_id uuid,
  offline_recorded_at timestamptz,
  replayed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint attendance_checked_out_at_after_checked_in_at_chk check (checked_out_at >= checked_in_at)
);

-- Append-only. A correction without a reason is impossible, not merely flagged
-- (DQA-003).
create table public.attendance_corrections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  attendance_id uuid not null references public.attendance (id),
  corrected_by_staff_id uuid not null references public.staff (id),
  reason text not null,
  before jsonb not null,
  after jsonb not null,
  created_at timestamptz not null default now(),
  constraint attendance_corrections_reason_chk check (reason <> '')
);

-- The gym's holiday calendar: at most one entry per organisation per date, so a
-- holiday is never an ambiguous streak break (STK-002).
create table public.organization_holidays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  holiday_on date not null,
  name text,
  created_at timestamptz not null default now(),
  constraint organization_holidays_tenant_id_holiday_on_key unique (tenant_id, holiday_on)
);


-- ---------------------------------------------------------------------------
-- Constraints not expressible inline (multi-column rules)
-- ---------------------------------------------------------------------------

-- ATT-005/006: a front-desk check-in carries both the acting staff member and a
-- non-empty reason. A QR check-in needs neither.
alter table public.attendance
  add constraint attendance_front_desk_has_assist_chk
  check (
    source <> 'front_desk'
    or (
      assisted_by_staff_id is not null
      and assist_reason is not null
      and assist_reason <> ''
    )
  );

-- Neither half of the assisted pair is recorded without the other.
alter table public.attendance
  add constraint attendance_assisted_pair_chk
  check ((assisted_by_staff_id is null) = (assist_reason is null));

-- ATT-007's audit stamp is both timestamps or neither.
alter table public.attendance
  add constraint attendance_offline_stamp_pair_chk
  check ((offline_recorded_at is null) = (replayed_at is null));


-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- qr_sessions: index rule 1 is discharged by (tenant_id, expires_at); rule 2 by
-- the two FK indexes below plus that composite for tenant_id.
create index qr_sessions_tenant_id_expires_at_idx
  on public.qr_sessions (tenant_id, expires_at);
create index qr_sessions_branch_id_idx
  on public.qr_sessions (branch_id);
create index qr_sessions_created_by_staff_id_idx
  on public.qr_sessions (created_by_staff_id);

-- ATT-007's structural half: a device-generated event id replays exactly once
-- per organisation. Partial, so rows with no client_event_id never collide.
create unique index attendance_tenant_id_client_event_id_key
  on public.attendance (tenant_id, client_event_id)
  where client_event_id is not null;

-- Rule 1 (non-partial, tenant-leading) and, per rule 2, the index for
-- attendance.member_id — no standalone member_id index is added.
create index attendance_tenant_id_member_id_checked_in_at_idx
  on public.attendance (tenant_id, member_id, checked_in_at desc);
create index attendance_tenant_id_checked_in_at_idx
  on public.attendance (tenant_id, checked_in_at);
create index attendance_membership_id_idx
  on public.attendance (membership_id);
create index attendance_branch_id_idx
  on public.attendance (branch_id);
create index attendance_qr_session_id_idx
  on public.attendance (qr_session_id);
create index attendance_assisted_by_staff_id_idx
  on public.attendance (assisted_by_staff_id);

-- attendance_corrections enumerates no tenant-leading index in the table list,
-- so index rule 1 requires this one explicitly.
create index attendance_corrections_tenant_id_idx
  on public.attendance_corrections (tenant_id);
create index attendance_corrections_attendance_id_idx
  on public.attendance_corrections (attendance_id);
create index attendance_corrections_corrected_by_staff_id_idx
  on public.attendance_corrections (corrected_by_staff_id);

-- organization_holidays: rules 1 and 2 are discharged by the
-- organization_holidays_tenant_id_holiday_on_key unique constraint's index.


-- ---------------------------------------------------------------------------
-- Row-Level Security
-- ---------------------------------------------------------------------------

alter table public.qr_sessions enable row level security;
alter table public.attendance enable row level security;
alter table public.attendance_corrections enable row level security;
alter table public.organization_holidays enable row level security;


-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

create policy qr_sessions_tenant_all on public.qr_sessions
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy qr_sessions_platform_all on public.qr_sessions
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy attendance_tenant_all on public.attendance
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy attendance_platform_all on public.attendance
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy attendance_corrections_tenant_all on public.attendance_corrections
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy attendance_corrections_platform_all on public.attendance_corrections
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy organization_holidays_tenant_all on public.organization_holidays
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy organization_holidays_platform_all on public.organization_holidays
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));


-- ---------------------------------------------------------------------------
-- Privileges (ADR-037: revoke then grant, per table, written out in full)
-- ---------------------------------------------------------------------------

-- normal tier
revoke all on public.qr_sessions from anon, authenticated;
grant select, insert, update on public.qr_sessions to authenticated;

revoke all on public.organization_holidays from anon, authenticated;
grant select, insert, update on public.organization_holidays to authenticated;

-- history tier — no `delete`: a wrong visit is corrected, never removed (INT-001)
revoke all on public.attendance from anon, authenticated;
grant select, insert, update on public.attendance to authenticated;

-- append-only tier — no `update`, no `delete` (DQA-003, INT-001)
revoke all on public.attendance_corrections from anon, authenticated;
grant select, insert on public.attendance_corrections to authenticated;
