-- 07_catalogue_constraints.sql
--
-- Cluster: catalogue. The rules an add-on order and a personal-training
-- session must obey, asserted as behaviour: the write is accepted, or it is
-- rejected with the SQLSTATE the shape of the rule implies.
--
-- Source of truth: openspec/changes/0001-data-model/specs/catalogue/spec.md
-- (Requirements "Sessions used can never exceed sessions bought", "A paid
-- add-on order carries its payment", "A trainer cannot be double-booked",
-- "An order validity window is coherent"), docs/domain-rules.md ADD-004,
-- DQA-005.
--
-- Wrapped BEGIN .. ROLLBACK per ADR-030.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(19);

-- ---------------------------------------------------------------------------
-- Fixtures. Inserted as postgres, which owns the tables and, with no
-- force row level security in the contract, bypasses RLS.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('0a000000-0000-4000-8000-000000000001'::uuid, 'Catalogue Gym A', 'CATC01');

insert into public.branches (id, tenant_id, name, is_default)
values ('0a000000-0000-4000-8000-000000000002'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid, 'Main', true);

insert into public.staff (id, tenant_id, role, full_name, qualification)
values ('0a000000-0000-4000-8000-000000000003'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        'trainer', 'Trainer One', 'ACSM CPT');

insert into public.staff (id, tenant_id, role, full_name, qualification)
values ('0a000000-0000-4000-8000-000000000004'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        'trainer', 'Trainer Two', 'ACE CPT');

insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('0a000000-0000-4000-8000-000000000005'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000002'::uuid,
        'Member One', '+919000000001');

insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id)
values ('0a000000-0000-4000-8000-000000000009'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000005'::uuid,
        500000, 'cash', '0a000000-0000-4000-8000-000000000003'::uuid);

insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count, trainer_staff_id)
values ('0a000000-0000-4000-8000-000000000006'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        'pt_package', 'PT 10', 500000, 10,
        '0a000000-0000-4000-8000-000000000003'::uuid);

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id,
                                 quantity, unit_price_paise, total_paise, sessions_total)
values ('0a000000-0000-4000-8000-000000000007'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000005'::uuid,
        '0a000000-0000-4000-8000-000000000006'::uuid,
        1, 500000, 500000, 10);

-- ---------------------------------------------------------------------------
-- ADD-004: sessions used can never exceed sessions bought
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id,
                                      quantity, unit_price_paise, total_paise,
                                      sessions_total, sessions_used)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             1, 500000, 500000, 5, 6) $$,
  '23514'::char(5),
  null,
  'ADD-004: an order whose sessions_used exceeds sessions_total is rejected'
);

select lives_ok(
  $$ update public.addon_orders set sessions_used = 10
      where id = '0a000000-0000-4000-8000-000000000007'::uuid $$,
  'ADD-004: consuming the last session, sessions_used equal to sessions_total, is accepted'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id,
                                      quantity, unit_price_paise, total_paise,
                                      sessions_total, sessions_used)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             1, 500000, 500000, 10, -1) $$,
  '23514'::char(5),
  null,
  'ADD-004: an order with a negative sessions_used is rejected'
);

-- ---------------------------------------------------------------------------
-- A paid add-on order carries its payment, unless its total is zero
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             'paid', 1, 500000, 500000) $$,
  '23514'::char(5),
  null,
  'catalogue: a paid order with a non-zero total and no payment_id is rejected'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             'active', 1, 500000, 500000) $$,
  '23514'::char(5),
  null,
  'catalogue: any status past pending or cancelled with a non-zero total needs a payment, active included'
);

select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             'pending', 1, 500000, 500000) $$,
  'catalogue: a pending order with no payment_id is accepted'
);

select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             'cancelled', 1, 500000, 500000) $$,
  'catalogue: a cancelled order with no payment_id is accepted'
);

select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             'paid', 1, 0, 0) $$,
  'catalogue: a paid order whose total is zero needs no payment_id'
);

select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, payment_id, status,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             '0a000000-0000-4000-8000-000000000009'::uuid,
             'paid', 1, 500000, 500000) $$,
  'catalogue: a paid order that references its payment is accepted'
);

-- ---------------------------------------------------------------------------
-- An order validity window is coherent, and a quantity is positive
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id,
                                      quantity, unit_price_paise, total_paise,
                                      starts_on, expires_on)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             1, 500000, 500000, date '2026-10-10', date '2026-10-09') $$,
  '23514'::char(5),
  null,
  'catalogue: an order whose expires_on precedes its starts_on is rejected'
);

select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id,
                                      quantity, unit_price_paise, total_paise,
                                      starts_on, expires_on)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             1, 500000, 500000, date '2026-10-10', date '2026-10-10') $$,
  'catalogue: a single-day order, expires_on equal to starts_on, is accepted'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id,
                                      quantity, unit_price_paise, total_paise)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             '0a000000-0000-4000-8000-000000000006'::uuid,
             0, 500000, 0) $$,
  '23514'::char(5),
  null,
  'catalogue: an order with a quantity of zero is rejected'
);

-- ---------------------------------------------------------------------------
-- pt_sessions fixtures: one live session, one cancelled, one completed,
-- each on its own day so the tests below do not interfere.
-- ---------------------------------------------------------------------------

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id,
                                starts_at, ends_at)
values ('0a000000-0000-4000-8000-000000000008'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000007'::uuid,
        '0a000000-0000-4000-8000-000000000003'::uuid,
        '0a000000-0000-4000-8000-000000000005'::uuid,
        timestamptz '2026-10-01 10:00:00+05:30', timestamptz '2026-10-01 11:00:00+05:30');

insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                starts_at, ends_at, status)
values ('0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000007'::uuid,
        '0a000000-0000-4000-8000-000000000003'::uuid,
        '0a000000-0000-4000-8000-000000000005'::uuid,
        timestamptz '2026-10-02 10:00:00+05:30', timestamptz '2026-10-02 11:00:00+05:30',
        'cancelled');

insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                starts_at, ends_at, status)
values ('0a000000-0000-4000-8000-000000000001'::uuid,
        '0a000000-0000-4000-8000-000000000007'::uuid,
        '0a000000-0000-4000-8000-000000000003'::uuid,
        '0a000000-0000-4000-8000-000000000005'::uuid,
        timestamptz '2026-10-03 10:00:00+05:30', timestamptz '2026-10-03 11:00:00+05:30',
        'completed');

-- ---------------------------------------------------------------------------
-- A session ends after it starts
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-05 10:00:00+05:30', timestamptz '2026-10-05 10:00:00+05:30') $$,
  '23514'::char(5),
  null,
  'catalogue: a session whose ends_at equals its starts_at is rejected'
);

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-05 10:00:00+05:30', timestamptz '2026-10-05 09:00:00+05:30') $$,
  '23514'::char(5),
  null,
  'catalogue: a session whose ends_at precedes its starts_at is rejected'
);

-- ---------------------------------------------------------------------------
-- DQA-005: a trainer cannot be double-booked
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-01 10:30:00+05:30', timestamptz '2026-10-01 11:30:00+05:30') $$,
  '23P01'::char(5),
  null,
  'DQA-005: a session overlapping a scheduled session for the same trainer is rejected'
);

select lives_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-01 11:00:00+05:30', timestamptz '2026-10-01 12:00:00+05:30') $$,
  'DQA-005: an adjacent session, starting exactly when the previous one ends, is accepted'
);

select lives_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000004'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-01 10:30:00+05:30', timestamptz '2026-10-01 11:30:00+05:30') $$,
  'DQA-005: an overlapping session for a different trainer is accepted'
);

select lives_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-02 10:30:00+05:30', timestamptz '2026-10-02 11:30:00+05:30') $$,
  'DQA-005: a cancelled session frees its slot'
);

select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id,
                                     starts_at, ends_at)
     values ('0a000000-0000-4000-8000-000000000001'::uuid,
             '0a000000-0000-4000-8000-000000000007'::uuid,
             '0a000000-0000-4000-8000-000000000003'::uuid,
             '0a000000-0000-4000-8000-000000000005'::uuid,
             timestamptz '2026-10-03 10:30:00+05:30', timestamptz '2026-10-03 11:30:00+05:30') $$,
  '23P01'::char(5),
  null,
  'DQA-005: a completed session still holds its slot, it is live history not a free hour'
);

select * from finish();

rollback;
