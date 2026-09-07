-- Cluster: comms (merge 6 of 7).
-- Implements docs/data-model.md § Tables → "Cluster: comms" and the three enums it
-- owns from § Enums, under § Conventions (the contract): Naming, Migration file
-- layout, Every table, Row-Level Security, Privileges, Indexes.
-- Requirements: PAY-002 (one message per stage, made structural by the notifications
-- de-dupe key), INT-002 / DPD-002 / DPD-003 / DPD-004 (versioned, append-only,
-- purpose-split consent), STK-004 (per-member motivation opt-out reads
-- members.motivation_push_enabled, tenancy's column), ADR-016 (push is v1's primary
-- channel; the per-gym credit wallet exists from day one).
-- Depends on the tenancy contract migration only: schema app and its three functions,
-- public.organizations, public.members, public.staff. None of them is re-created here.
-- No extensions. No behaviour: no state machine for notification_status, no
-- balance-maintaining trigger (Phase 6 wires the arithmetic; the ledger is the audit
-- trail), no audit trigger, no view, no security definer function.

-- ---------------------------------------------------------------------------
-- 2. enum types (labels in docs/data-model.md § Enums order — the order is contract)
-- ---------------------------------------------------------------------------

create type public.notification_channel as enum (
  'push',
  'whatsapp_link',
  'in_app',
  'sms',
  'email'
);

create type public.notification_status as enum (
  'scheduled',
  'sent',
  'delivered',
  'failed',
  'clicked',
  'converted',
  'opted_out'
);

create type public.consent_purpose as enum (
  'marketing',
  'service'
);

-- ---------------------------------------------------------------------------
-- 3. tables
-- ---------------------------------------------------------------------------

create table public.message_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  key text not null,
  channel public.notification_channel not null,
  locale text not null default 'en'
    constraint message_templates_locale_format_chk check (locale ~ '^[a-z]{2}$'),
  body text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint message_templates_tenant_id_key_channel_locale_key
    unique (tenant_id, key, channel, locale)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  channel public.notification_channel not null,
  template_key text,
  status public.notification_status not null default 'scheduled',
  dedupe_key text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  clicked_at timestamptz,
  converted_at timestamptz,
  failed_reason text,
  related_type text,
  related_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- push_token is unique PER TENANT (ADR-047). The contract previously specified a
-- global unique on the reasoning that one token is one app install; that is true
-- of the device and wrong about the registration. A member may belong to two
-- gyms, and under a global unique whichever gym registers the handset first
-- silently denies push at the other -- permanently, since Phase 1 grants delete
-- nowhere -- with an opaque constraint name as the only diagnostic.
create table public.member_devices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  platform text not null
    constraint member_devices_platform_chk check (platform in ('ios', 'android', 'web')),
  push_token text not null,
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_devices_tenant_id_push_token_key unique (tenant_id, push_token)
);

-- Append-only (INT-002, DPD-004): withdrawal is a new row with granted = false, never
-- an edit. recorded_at is the domain timestamp (when the decision was made) and
-- coexists with created_at (when the row was inserted); they are not duplicates.
create table public.consents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  purpose public.consent_purpose not null,
  granted boolean not null,
  version text not null
    constraint consents_version_chk check (version <> ''),
  source text not null
    constraint consents_source_chk check (source <> ''),
  recorded_at timestamptz not null default now(),
  recorded_by_staff_id uuid references public.staff (id),
  created_at timestamptz not null default now()
);

-- tenant_id is the primary key: one wallet per gym. balance_credits is a credit
-- count, not money, so there is no currency column here or anywhere in this cluster.
-- created_at is present because the contract's "every table, no exceptions" rule wins
-- over the table list, which names this table as one of the two that omit it.
create table public.messaging_wallets (
  tenant_id uuid primary key references public.organizations (id),
  balance_credits bigint not null default 0
    constraint messaging_wallets_balance_credits_chk check (balance_credits >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.messaging_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  delta_credits bigint not null
    constraint messaging_wallet_ledger_delta_credits_chk check (delta_credits <> 0),
  reason text not null
    constraint messaging_wallet_ledger_reason_chk check (reason <> ''),
  notification_id uuid references public.notifications (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. constraints not expressible inline — none in this cluster
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5. indexes
-- ---------------------------------------------------------------------------

-- message_templates: index rule 1 and rule 2 are discharged by the unique constraint
-- above, whose index is non-partial and leads with tenant_id.

-- PAY-002 made structural: at most one notification per de-duplication key per gym.
-- Partial, so an ad-hoc message with no key is unconstrained.
create unique index notifications_tenant_id_dedupe_key_key
  on public.notifications (tenant_id, dedupe_key)
  where dedupe_key is not null;

-- Index rule 1 for notifications (non-partial, tenant-leading); also the send queue.
create index notifications_tenant_id_status_scheduled_for_idx
  on public.notifications (tenant_id, status, scheduled_for);

create index notifications_member_id_idx
  on public.notifications (member_id);

create index notifications_related_type_related_id_idx
  on public.notifications (related_type, related_id);

-- Index rule 1 for member_devices, and rule 2 for member_id (immediately after the
-- tenant column in a tenant-leading composite).
create index member_devices_tenant_id_member_id_idx
  on public.member_devices (tenant_id, member_id);

-- consents: the table list enumerates no tenant-leading index, so index rule 1 needs
-- this one explicitly (docs/data-model.md § Indexes names consents as such a table).
create index consents_tenant_id_idx
  on public.consents (tenant_id);

-- Current state = latest row per (member, purpose); also index rule 2 for member_id.
create index consents_member_id_purpose_recorded_at_idx
  on public.consents (member_id, purpose, recorded_at desc);

create index consents_recorded_by_staff_id_idx
  on public.consents (recorded_by_staff_id);

-- messaging_wallets: the primary key on tenant_id discharges index rules 1 and 2.

create index messaging_wallet_ledger_tenant_id_created_at_idx
  on public.messaging_wallet_ledger (tenant_id, created_at);

create index messaging_wallet_ledger_notification_id_idx
  on public.messaging_wallet_ledger (notification_id);

-- ---------------------------------------------------------------------------
-- 6. row-level security
-- ---------------------------------------------------------------------------

alter table public.message_templates enable row level security;
alter table public.notifications enable row level security;
alter table public.member_devices enable row level security;
alter table public.consents enable row level security;
alter table public.messaging_wallets enable row level security;
alter table public.messaging_wallet_ledger enable row level security;

-- ---------------------------------------------------------------------------
-- 7. policies (both accessor calls wrapped in (select …) so the planner evaluates
--    them once as an InitPlan rather than once per row)
-- ---------------------------------------------------------------------------

create policy message_templates_tenant_all on public.message_templates
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy message_templates_platform_all on public.message_templates
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy notifications_tenant_all on public.notifications
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy notifications_platform_all on public.notifications
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy member_devices_tenant_all on public.member_devices
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy member_devices_platform_all on public.member_devices
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy consents_tenant_all on public.consents
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy consents_platform_all on public.consents
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy messaging_wallets_tenant_all on public.messaging_wallets
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy messaging_wallets_platform_all on public.messaging_wallets
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy messaging_wallet_ledger_tenant_all on public.messaging_wallet_ledger
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy messaging_wallet_ledger_platform_all on public.messaging_wallet_ledger
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- ---------------------------------------------------------------------------
-- 8. privileges (ADR-037: RLS is not a privilege system, and the schema-public
--    default ACL grants delete and truncate to anon and authenticated. Written out
--    per table — never the "on all tables in schema public" form. delete and
--    truncate go to nobody; anon gets nothing. service_role is never revoked from.)
-- ---------------------------------------------------------------------------

revoke all on public.message_templates from anon, authenticated;
grant select, insert, update on public.message_templates to authenticated;

revoke all on public.notifications from anon, authenticated;
grant select, insert, update on public.notifications to authenticated;

revoke all on public.member_devices from anon, authenticated;
grant select, insert, update on public.member_devices to authenticated;

-- Append-only: no update, no delete. Withdrawal is a new row (DPD-004, INT-002).
revoke all on public.consents from anon, authenticated;
grant select, insert on public.consents to authenticated;

-- ADR-047, read-only tier: a gym must not be able to write the credit balance
-- it is billed against. With `update` a gym owner's own session could set the
-- balance to any number and leave no ledger row. Every legitimate movement is
-- written by service_role, which is never revoked from.
revoke all on public.messaging_wallets from anon, authenticated;
grant select on public.messaging_wallets to authenticated;

-- Append-only: the ledger is the audit trail of every credit movement.
revoke all on public.messaging_wallet_ledger from anon, authenticated;
grant select, insert on public.messaging_wallet_ledger to authenticated;

-- ---------------------------------------------------------------------------
-- 9. triggers — the shared app.touch_updated_at() from the contract migration, on
--    exactly the tables that carry updated_at. consents and messaging_wallet_ledger
--    have none and get none.
-- ---------------------------------------------------------------------------

create trigger message_templates_touch_updated_at
  before update on public.message_templates
  for each row execute function app.touch_updated_at();

create trigger notifications_touch_updated_at
  before update on public.notifications
  for each row execute function app.touch_updated_at();

create trigger member_devices_touch_updated_at
  before update on public.member_devices
  for each row execute function app.touch_updated_at();

create trigger messaging_wallets_touch_updated_at
  before update on public.messaging_wallets
  for each row execute function app.touch_updated_at();
