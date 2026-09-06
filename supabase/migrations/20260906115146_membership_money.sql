-- Cluster: membership+money (merge 2 of 7).
-- Implements docs/data-model.md § Conventions (the contract),
-- § Tables → "Cluster: membership+money", and § Enums (the six vocabularies
-- this cluster owns), against
-- openspec/changes/0001-data-model/specs/membership-and-money/spec.md.
-- Statement order is the contract's: enum types → tables → constraints not
-- expressible inline → indexes → enable RLS → policies → privileges → triggers.
-- No extensions: gen_random_uuid() is core in Postgres 17, and pgtap, schema
-- app, app.current_tenant_id(), app.is_platform() and app.touch_updated_at()
-- are all created by the tenancy contract migration.

-- ---------------------------------------------------------------------------
-- 1. Enum types (label order is the contract's — it is what `supabase gen
--    types` emits and what any `order by` on the column follows).
--    Legal transitions are documented in docs/data-model.md § Enums; Phase 1
--    enforces none of them (the phase that first mutates each status does).
-- ---------------------------------------------------------------------------

create type public.membership_status as enum (
  'pending', 'active', 'frozen', 'expired', 'cancelled'
);

create type public.payment_status as enum (
  'created', 'pending', 'paid', 'failed', 'refunded', 'reversed'
);

create type public.payment_method as enum (
  'razorpay', 'cash', 'upi', 'card', 'bank_transfer'
);

create type public.refund_kind as enum (
  'refund', 'reversal'
);

create type public.refund_status as enum (
  'requested', 'processing', 'completed', 'failed'
);

create type public.mandate_status as enum (
  'created', 'authenticated', 'active', 'paused', 'halted', 'cancelled',
  'completed', 'expired'
);

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------

-- A gym's membership tiers.
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  name text not null,
  description text,
  duration_days integer not null
    constraint plans_duration_days_chk check (duration_days > 0),
  price_paise bigint not null
    constraint plans_price_paise_chk check (price_paise >= 0),
  currency text not null default 'INR'
    constraint plans_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  gst_rate_bp smallint not null default 0
    constraint plans_gst_rate_bp_chk check (gst_rate_bp between 0 and 10000),
  max_freeze_days smallint not null default 0
    constraint plans_max_freeze_days_chk check (max_freeze_days >= 0),
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plans_tenant_id_name_key unique (tenant_id, name)
);

-- Discount codes on renewal (v1) and add-ons.
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  code text not null,
  percent_bp integer
    constraint coupons_percent_bp_chk check (percent_bp between 0 and 10000),
  flat_paise bigint
    constraint coupons_flat_paise_chk check (flat_paise >= 0),
  currency text not null default 'INR'
    constraint coupons_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  valid_from timestamptz,
  valid_until timestamptz,
  max_redemptions integer
    constraint coupons_max_redemptions_chk check (max_redemptions > 0),
  redeemed_count integer not null default 0
    constraint coupons_redeemed_count_chk check (redeemed_count >= 0),
  applies_to_plans boolean not null default true,
  applies_to_addons boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coupons_tenant_id_code_key unique (tenant_id, code)
);

-- A member's paid period on a plan; a renewal is a new row linked by
-- renewal_of_membership_id, never an edit of the previous period.
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  plan_id uuid not null references public.plans (id),
  status public.membership_status not null default 'pending',
  starts_on date,
  ends_on date,
  price_paise bigint not null
    constraint memberships_price_paise_chk check (price_paise >= 0),
  discount_paise bigint not null default 0
    constraint memberships_discount_paise_chk check (discount_paise >= 0),
  currency text not null default 'INR'
    constraint memberships_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  coupon_id uuid references public.coupons (id),
  renewal_of_membership_id uuid references public.memberships (id),
  activated_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Approved freezes (STK-002, NSH-002).
create table public.membership_pauses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  membership_id uuid not null references public.memberships (id),
  starts_on date not null,
  ends_on date not null,
  reason text not null
    constraint membership_pauses_reason_chk check (reason <> ''),
  requested_by_staff_id uuid references public.staff (id),
  approved_by_staff_id uuid references public.staff (id),
  approved_at timestamptz,
  rejected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- UPI Autopay via Razorpay Subscriptions; schema reserved now, unused until
-- Phase 2 wires subscription.* webhooks. Created before `payments` because
-- payments.mandate_id references it and the contract requires foreign keys
-- declared inline on the column.
create table public.razorpay_mandates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  provider_customer_id text,
  provider_subscription_id text not null,
  provider_plan_id text,
  status public.mandate_status not null default 'created',
  max_amount_paise bigint not null
    constraint razorpay_mandates_max_amount_paise_chk check (max_amount_paise > 0),
  currency text not null default 'INR'
    constraint razorpay_mandates_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  authenticated_at timestamptz,
  next_charge_at timestamptz,
  ends_at timestamptz,
  cancelled_at timestamptz,
  raw jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint razorpay_mandates_tenant_id_provider_subscription_id_key
    unique (tenant_id, provider_subscription_id)
);

-- One row per attempt to collect money, gateway or offline. The provider is
-- the source of truth for status (PAY-006); a created/pending row is never
-- paid (PAY-007).
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  membership_id uuid references public.memberships (id),
  mandate_id uuid references public.razorpay_mandates (id),
  coupon_id uuid references public.coupons (id),
  amount_paise bigint not null
    constraint payments_amount_paise_chk check (amount_paise > 0),
  currency text not null default 'INR'
    constraint payments_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  status public.payment_status not null default 'created',
  method public.payment_method not null,
  provider text,
  provider_order_id text,
  provider_payment_id text,
  receipt_number text,
  recorded_by_staff_id uuid references public.staff (id),
  idempotency_key text,
  paid_at timestamptz,
  failed_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Refunds and reversals as their own rows, never a mutation of the payment
-- (PAY-010).
create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  payment_id uuid not null references public.payments (id),
  kind public.refund_kind not null,
  amount_paise bigint not null
    constraint refunds_amount_paise_chk check (amount_paise > 0),
  currency text not null default 'INR'
    constraint refunds_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  status public.refund_status not null default 'requested',
  provider_refund_id text,
  reason text not null
    constraint refunds_reason_chk check (reason <> ''),
  initiated_by_staff_id uuid references public.staff (id),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Every Razorpay delivery, verified or not. The unique key is what makes
-- PAY-009 idempotent. No updated_at: rows are written once, then processed_at
-- is stamped by the webhook Edge Function on service_role.
create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  provider text not null default 'razorpay',
  event_id text not null,
  event_type text not null,
  payload jsonb not null,
  signature_valid boolean not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_error text,
  created_at timestamptz not null default now(),
  constraint webhook_events_tenant_id_provider_event_id_key
    unique (tenant_id, provider, event_id)
);

-- GST invoices, numbered per gym per financial year.
create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  payment_id uuid not null references public.payments (id),
  invoice_number text not null,
  financial_year text not null
    constraint invoices_financial_year_format_chk
      check (financial_year ~ '^[0-9]{4}-[0-9]{2}$'),
  issued_at timestamptz not null default now(),
  seller_gstin text,
  buyer_name text not null,
  buyer_gstin text,
  place_of_supply text,
  taxable_paise bigint not null
    constraint invoices_taxable_paise_chk check (taxable_paise >= 0),
  cgst_paise bigint not null default 0
    constraint invoices_cgst_paise_chk check (cgst_paise >= 0),
  sgst_paise bigint not null default 0
    constraint invoices_sgst_paise_chk check (sgst_paise >= 0),
  igst_paise bigint not null default 0
    constraint invoices_igst_paise_chk check (igst_paise >= 0),
  total_paise bigint not null
    constraint invoices_total_paise_chk check (total_paise >= 0),
  currency text not null default 'INR'
    constraint invoices_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  line_items jsonb not null default '[]'::jsonb,
  pdf_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoices_payment_id_key unique (payment_id),
  constraint invoices_tenant_id_invoice_number_key
    unique (tenant_id, invoice_number)
);

-- Next number per gym, per document kind, per financial year. created_at is
-- present because the contract's "every table, no exceptions" rule wins over
-- the table list, which omits it.
create table public.document_counters (
  tenant_id uuid not null references public.organizations (id),
  kind text not null
    constraint document_counters_kind_chk check (kind in ('invoice', 'receipt')),
  financial_year text not null
    constraint document_counters_financial_year_format_chk
      check (financial_year ~ '^[0-9]{4}-[0-9]{2}$'),
  next_number integer not null default 1
    constraint document_counters_next_number_chk check (next_number > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, kind, financial_year)
);

-- A gym's own Razorpay connection (ADR-008/015). Secrets live in Supabase
-- Vault; this row holds only the Vault secret ids. There is no column here or
-- anywhere else for a card number or a raw UPI credential (PAY-005).
create table public.razorpay_accounts (
  tenant_id uuid primary key references public.organizations (id),
  key_id text not null,
  key_secret_vault_id uuid not null,
  webhook_secret_vault_id uuid not null,
  verified_at timestamptz,
  is_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Constraints not expressible inline (multi-column checks)
-- ---------------------------------------------------------------------------

-- A coupon carries exactly one kind of discount.
alter table public.coupons
  add constraint coupons_one_discount_kind_chk
    check ((percent_bp is null) <> (flat_paise is null));

-- DQA-001 made structural: only a pending membership may lack an expiry.
alter table public.memberships
  add constraint memberships_dated_unless_pending_chk
    check (status = 'pending' or (starts_on is not null and ends_on is not null));

alter table public.memberships
  add constraint memberships_ends_on_after_starts_on_chk
    check (ends_on >= starts_on);

alter table public.membership_pauses
  add constraint membership_pauses_ends_on_after_starts_on_chk
    check (ends_on >= starts_on);

alter table public.membership_pauses
  add constraint membership_pauses_not_approved_and_rejected_chk
    check (approved_at is null or rejected_at is null);

-- DQA-002 made structural: a paid payment always carries a reference.
alter table public.payments
  add constraint payments_paid_has_reference_chk
    check (status <> 'paid'
           or provider_payment_id is not null
           or receipt_number is not null);

-- PAY-011: an offline payment carries staff attribution.
alter table public.payments
  add constraint payments_offline_has_staff_chk
    check (method = 'razorpay' or recorded_by_staff_id is not null);

alter table public.payments
  add constraint payments_razorpay_has_order_chk
    check (method <> 'razorpay' or provider_order_id is not null);

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------

create index plans_tenant_id_is_active_idx
  on public.plans (tenant_id, is_active);

-- At most one live membership per member.
create unique index memberships_member_id_live_key
  on public.memberships (member_id)
  where status in ('active', 'frozen');

create index memberships_tenant_id_status_ends_on_idx
  on public.memberships (tenant_id, status, ends_on);
create index memberships_member_id_idx on public.memberships (member_id);
create index memberships_plan_id_idx on public.memberships (plan_id);
create index memberships_coupon_id_idx on public.memberships (coupon_id);
create index memberships_renewal_of_membership_id_idx
  on public.memberships (renewal_of_membership_id);

create index membership_pauses_membership_id_idx
  on public.membership_pauses (membership_id);
create index membership_pauses_tenant_id_starts_on_ends_on_idx
  on public.membership_pauses (tenant_id, starts_on, ends_on);
create index membership_pauses_requested_by_staff_id_idx
  on public.membership_pauses (requested_by_staff_id);
create index membership_pauses_approved_by_staff_id_idx
  on public.membership_pauses (approved_by_staff_id);

create index razorpay_mandates_member_id_idx
  on public.razorpay_mandates (member_id);
create index razorpay_mandates_tenant_id_status_idx
  on public.razorpay_mandates (tenant_id, status);

create unique index payments_tenant_id_provider_provider_payment_id_key
  on public.payments (tenant_id, provider, provider_payment_id)
  where provider_payment_id is not null;
create unique index payments_tenant_id_receipt_number_key
  on public.payments (tenant_id, receipt_number)
  where receipt_number is not null;
create unique index payments_tenant_id_idempotency_key_key
  on public.payments (tenant_id, idempotency_key)
  where idempotency_key is not null;
create index payments_tenant_id_status_created_at_idx
  on public.payments (tenant_id, status, created_at);
create index payments_member_id_idx on public.payments (member_id);
create index payments_membership_id_idx on public.payments (membership_id);
create index payments_mandate_id_idx on public.payments (mandate_id);
create index payments_coupon_id_idx on public.payments (coupon_id);
create index payments_recorded_by_staff_id_idx
  on public.payments (recorded_by_staff_id);

-- Index rule 1: refunds' only tenant-leading index would otherwise be the
-- partial unique one below, which does not discharge the rule.
create index refunds_tenant_id_idx on public.refunds (tenant_id);
create index refunds_payment_id_idx on public.refunds (payment_id);
create index refunds_initiated_by_staff_id_idx
  on public.refunds (initiated_by_staff_id);
create unique index refunds_tenant_id_provider_refund_id_key
  on public.refunds (tenant_id, provider_refund_id)
  where provider_refund_id is not null;

create index webhook_events_tenant_id_received_at_unprocessed_idx
  on public.webhook_events (tenant_id, received_at)
  where processed_at is null;

create index invoices_tenant_id_financial_year_idx
  on public.invoices (tenant_id, financial_year);

-- ---------------------------------------------------------------------------
-- 5. Row-Level Security
-- ---------------------------------------------------------------------------

alter table public.plans enable row level security;
alter table public.coupons enable row level security;
alter table public.memberships enable row level security;
alter table public.membership_pauses enable row level security;
alter table public.razorpay_mandates enable row level security;
alter table public.payments enable row level security;
alter table public.refunds enable row level security;
alter table public.webhook_events enable row level security;
alter table public.invoices enable row level security;
alter table public.document_counters enable row level security;
alter table public.razorpay_accounts enable row level security;

-- ---------------------------------------------------------------------------
-- 6. Policies — two per table, every accessor call wrapped in (select …) so
--    the planner evaluates it once as an InitPlan instead of once per row.
-- ---------------------------------------------------------------------------

create policy plans_tenant_all on public.plans
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy plans_platform_all on public.plans
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy coupons_tenant_all on public.coupons
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy coupons_platform_all on public.coupons
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy memberships_tenant_all on public.memberships
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy memberships_platform_all on public.memberships
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy membership_pauses_tenant_all on public.membership_pauses
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy membership_pauses_platform_all on public.membership_pauses
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy razorpay_mandates_tenant_all on public.razorpay_mandates
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy razorpay_mandates_platform_all on public.razorpay_mandates
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy payments_tenant_all on public.payments
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy payments_platform_all on public.payments
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy refunds_tenant_all on public.refunds
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy refunds_platform_all on public.refunds
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy webhook_events_tenant_all on public.webhook_events
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy webhook_events_platform_all on public.webhook_events
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy invoices_tenant_all on public.invoices
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy invoices_platform_all on public.invoices
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy document_counters_tenant_all on public.document_counters
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy document_counters_platform_all on public.document_counters
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy razorpay_accounts_tenant_all on public.razorpay_accounts
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy razorpay_accounts_platform_all on public.razorpay_accounts
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- ---------------------------------------------------------------------------
-- 7. Privileges (ADR-037) — written out per table, never the
--    "on all tables in schema public" form. delete and truncate go to nobody
--    (INT-001), anon gets nothing, service_role is never revoked from.
-- ---------------------------------------------------------------------------

revoke all on public.plans from anon, authenticated;
grant select, insert, update on public.plans to authenticated;

revoke all on public.coupons from anon, authenticated;
grant select, insert, update on public.coupons to authenticated;

revoke all on public.memberships from anon, authenticated;
grant select, insert, update on public.memberships to authenticated;

revoke all on public.membership_pauses from anon, authenticated;
grant select, insert, update on public.membership_pauses to authenticated;

revoke all on public.razorpay_mandates from anon, authenticated;
grant select, insert, update on public.razorpay_mandates to authenticated;

revoke all on public.payments from anon, authenticated;
grant select, insert, update on public.payments to authenticated;

revoke all on public.refunds from anon, authenticated;
grant select, insert, update on public.refunds to authenticated;

-- Append-only: processed_at is stamped by the webhook Edge Function on
-- service_role, not by a signed-in caller.
revoke all on public.webhook_events from anon, authenticated;
grant select, insert on public.webhook_events to authenticated;

revoke all on public.invoices from anon, authenticated;
grant select, insert, update on public.invoices to authenticated;

revoke all on public.document_counters from anon, authenticated;
grant select, insert, update on public.document_counters to authenticated;

revoke all on public.razorpay_accounts from anon, authenticated;
grant select, insert, update on public.razorpay_accounts to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Triggers — the shared app.touch_updated_at() on exactly the tables that
--    have updated_at, and on no others (webhook_events has none).
-- ---------------------------------------------------------------------------

create trigger plans_touch_updated_at
  before update on public.plans
  for each row execute function app.touch_updated_at();

create trigger coupons_touch_updated_at
  before update on public.coupons
  for each row execute function app.touch_updated_at();

create trigger memberships_touch_updated_at
  before update on public.memberships
  for each row execute function app.touch_updated_at();

create trigger membership_pauses_touch_updated_at
  before update on public.membership_pauses
  for each row execute function app.touch_updated_at();

create trigger razorpay_mandates_touch_updated_at
  before update on public.razorpay_mandates
  for each row execute function app.touch_updated_at();

create trigger payments_touch_updated_at
  before update on public.payments
  for each row execute function app.touch_updated_at();

create trigger refunds_touch_updated_at
  before update on public.refunds
  for each row execute function app.touch_updated_at();

create trigger invoices_touch_updated_at
  before update on public.invoices
  for each row execute function app.touch_updated_at();

create trigger document_counters_touch_updated_at
  before update on public.document_counters
  for each row execute function app.touch_updated_at();

create trigger razorpay_accounts_touch_updated_at
  before update on public.razorpay_accounts
  for each row execute function app.touch_updated_at();
