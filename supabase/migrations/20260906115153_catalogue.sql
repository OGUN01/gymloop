-- Cluster: catalogue (merge 4 of 7).
-- Implements docs/data-model.md - Tables, "Cluster: catalogue" (addon_products,
-- addon_orders, pt_sessions) and the three enums this cluster owns in Enums
-- (addon_kind, addon_order_status, pt_session_status), under Conventions (the
-- contract): naming, migration file layout, every table, RLS, privileges, indexes.
-- Domain rules: ADD-002, ADD-004, DQA-004, DQA-005, INT-001, MNY-001, MNY-002.
-- Decisions: ADR-030, ADR-035, ADR-037, ADR-040, ADR-041.
-- Cross-cluster seam: addon_orders.payment_id references payments, created by the
-- membership+money cluster (merge 2); the foreign key is carried here, never by an
-- alter against payments.

-- 1. extensions --------------------------------------------------------------
-- btree_gist supplies the gist operator class for uuid equality that
-- pt_sessions_trainer_overlap_excl needs (DQA-005). This cluster is its only user.
create extension if not exists btree_gist with schema extensions;

-- 2. enum types --------------------------------------------------------------
create type public.addon_kind as enum ('pt_package', 'diet_plan', 'product');

create type public.addon_order_status as enum (
  'pending', 'paid', 'active', 'completed', 'cancelled', 'refunded'
);

create type public.pt_session_status as enum (
  'scheduled', 'completed', 'cancelled', 'no_show'
);

-- 3. tables ------------------------------------------------------------------
create table public.addon_products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  kind public.addon_kind not null,
  name text not null,
  description text,
  price_paise bigint not null
    constraint addon_products_price_paise_chk check (price_paise >= 0),
  currency text not null default 'INR'
    constraint addon_products_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  gst_rate_bp smallint not null default 0
    constraint addon_products_gst_rate_bp_chk check (gst_rate_bp between 0 and 10000),
  validity_days integer
    constraint addon_products_validity_days_chk check (validity_days > 0),
  session_count integer
    constraint addon_products_session_count_chk check (session_count > 0),
  trainer_staff_id uuid references public.staff (id),
  stock_quantity integer
    constraint addon_products_stock_quantity_chk check (stock_quantity >= 0),
  cancellation_terms text,
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint addon_products_tenant_id_name_key unique (tenant_id, name)
);

create table public.addon_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null references public.members (id),
  addon_product_id uuid not null references public.addon_products (id),
  payment_id uuid references public.payments (id),
  status public.addon_order_status not null default 'pending',
  quantity integer not null default 1
    constraint addon_orders_quantity_chk check (quantity > 0),
  unit_price_paise bigint not null
    constraint addon_orders_unit_price_paise_chk check (unit_price_paise >= 0),
  total_paise bigint not null
    constraint addon_orders_total_paise_chk check (total_paise >= 0),
  currency text not null default 'INR'
    constraint addon_orders_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  trainer_staff_id uuid references public.staff (id),
  sessions_total integer
    constraint addon_orders_sessions_total_chk check (sessions_total > 0),
  sessions_used integer not null default 0
    constraint addon_orders_sessions_used_chk check (sessions_used >= 0),
  starts_on date,
  expires_on date,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint addon_orders_expires_on_after_starts_on_chk check (expires_on >= starts_on)
);

create table public.pt_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  addon_order_id uuid not null references public.addon_orders (id),
  trainer_staff_id uuid not null references public.staff (id),
  member_id uuid not null references public.members (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.pt_session_status not null default 'scheduled',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pt_sessions_ends_at_after_starts_at_chk check (ends_at > starts_at)
);

-- 4. constraints not expressible inline --------------------------------------
-- ADD-002: a PT package must say how many sessions it sells and a product must say
-- how much stock it has; a diet plan needs neither.
alter table public.addon_products
  add constraint addon_products_pt_package_has_session_count_chk
  check (kind <> 'pt_package' or session_count is not null);

alter table public.addon_products
  add constraint addon_products_product_has_stock_quantity_chk
  check (kind <> 'product' or stock_quantity is not null);

-- ADD-004: an order can never consume more sessions than were bought.
alter table public.addon_orders
  add constraint addon_orders_sessions_used_within_total_chk
  check (sessions_total is null or sessions_used <= sessions_total);

-- An order past pending or cancelled carries the payment that bought it, unless
-- its total is zero.
alter table public.addon_orders
  add constraint addon_orders_paid_has_payment_chk
  check (status in ('pending', 'cancelled') or payment_id is not null or total_paise = 0);

-- DQA-005: a trainer cannot be double-booked. tstzrange defaults to [) bounds, so a
-- session starting exactly when the previous one ends does not overlap; a cancelled
-- or no-show session frees the slot. A violation raises SQLSTATE 23P01.
alter table public.pt_sessions
  add constraint pt_sessions_trainer_overlap_excl
  exclude using gist (
    -- ADR-047: the tenant term is load-bearing. Without it the constraint
    -- ignores RLS across tenants, so one gym can fill another gym's trainer's
    -- calendar with rows that gym can neither see nor delete, and a 23P01
    -- reports the existence of an invisible booking. Every legitimate session
    -- for a trainer carries that trainer's gym's tenant, so every real
    -- double-booking is still caught (DQA-005).
    tenant_id with =,
    trainer_staff_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status in ('scheduled', 'completed'));

-- 5. indexes -----------------------------------------------------------------
create index addon_products_tenant_id_kind_is_active_idx
  on public.addon_products (tenant_id, kind, is_active);
create index addon_products_trainer_staff_id_idx
  on public.addon_products (trainer_staff_id);

create index addon_orders_tenant_id_status_idx
  on public.addon_orders (tenant_id, status);
create index addon_orders_member_id_idx
  on public.addon_orders (member_id);
create index addon_orders_addon_product_id_idx
  on public.addon_orders (addon_product_id);
create index addon_orders_payment_id_idx
  on public.addon_orders (payment_id);
create index addon_orders_trainer_staff_id_idx
  on public.addon_orders (trainer_staff_id);

create index pt_sessions_tenant_id_trainer_staff_id_starts_at_idx
  on public.pt_sessions (tenant_id, trainer_staff_id, starts_at);
create index pt_sessions_addon_order_id_idx
  on public.pt_sessions (addon_order_id);
create index pt_sessions_member_id_idx
  on public.pt_sessions (member_id);

-- 6. row-level security ------------------------------------------------------
alter table public.addon_products enable row level security;
alter table public.addon_orders enable row level security;
alter table public.pt_sessions enable row level security;

-- 7. policies ----------------------------------------------------------------
create policy addon_products_tenant_all on public.addon_products
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy addon_products_platform_all on public.addon_products
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy addon_orders_tenant_all on public.addon_orders
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy addon_orders_platform_all on public.addon_orders
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

create policy pt_sessions_tenant_all on public.pt_sessions
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id()))
  with check (tenant_id = (select app.current_tenant_id()));

create policy pt_sessions_platform_all on public.pt_sessions
  for all to authenticated
  using ((select app.is_platform()))
  with check ((select app.is_platform()));

-- 8. privileges --------------------------------------------------------------
-- ADR-037: default privileges in public grant everything to anon and authenticated,
-- and truncate is not filtered by RLS. addon_orders is a history table: no delete,
-- ever, for a signed-in caller (INT-001) - cancellation is a status.
revoke all on public.addon_products from anon, authenticated;
grant select, insert, update on public.addon_products to authenticated;

revoke all on public.addon_orders from anon, authenticated;
grant select, insert, update on public.addon_orders to authenticated;

revoke all on public.pt_sessions from anon, authenticated;
grant select, insert, update on public.pt_sessions to authenticated;

-- 9. triggers ----------------------------------------------------------------
create trigger addon_products_touch_updated_at
  before update on public.addon_products
  for each row execute function app.touch_updated_at();

create trigger addon_orders_touch_updated_at
  before update on public.addon_orders
  for each row execute function app.touch_updated_at();

create trigger pt_sessions_touch_updated_at
  before update on public.pt_sessions
  for each row execute function app.touch_updated_at();
