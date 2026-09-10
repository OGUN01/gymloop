-- 07_catalogue_structure.sql
--
-- Cluster: catalogue. What the add-on catalogue must be able to hold, and the
-- shape rules that hold before any order exists.
--
-- Source of truth: openspec/changes/0001-data-model/specs/catalogue/spec.md
-- (Requirement "An add-on carries what a member must see before buying" and
-- "Stock can never go negative"), docs/data-model.md "Cluster: catalogue" and
-- "## Enums", docs/domain-rules.md ADD-002, ADD-004, DQA-004.
--
-- Wrapped BEGIN .. ROLLBACK: the suite runs against the one shared Cloud
-- project and a test that commits is a bug (ADR-030).

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(24);

-- ---------------------------------------------------------------------------
-- Extension and enums the cluster owns
-- ---------------------------------------------------------------------------

select ok(
  exists (select 1 from pg_extension where extname = 'btree_gist'),
  'catalogue: btree_gist is installed, which the DQA-005 exclusion constraint needs'
);

select has_table('public', 'addon_products', 'catalogue: addon_products exists');
select has_table('public', 'addon_orders',   'catalogue: addon_orders exists');
select has_table('public', 'pt_sessions',    'catalogue: pt_sessions exists');

select enum_has_labels(
  'public', 'addon_kind',
  array['pt_package', 'diet_plan', 'product']::name[],
  'ADR-021: addon_kind carries the contract labels in contract order'
);

select enum_has_labels(
  'public', 'addon_order_status',
  array['pending', 'paid', 'active', 'completed', 'cancelled', 'refunded']::name[],
  'ADR-021: addon_order_status carries the contract labels in contract order'
);

select enum_has_labels(
  'public', 'pt_session_status',
  array['scheduled', 'completed', 'cancelled', 'no_show']::name[],
  'ADR-021: pt_session_status carries the contract labels in contract order'
);

-- ---------------------------------------------------------------------------
-- ADD-002: everything a member must see before buying is storable
-- ---------------------------------------------------------------------------

select has_column('public', 'addon_products', 'price_paise',
  'ADD-002: an add-on holds its price');
select has_column('public', 'addon_products', 'currency',
  'ADD-002: an add-on prices in an explicit currency');
select has_column('public', 'addon_products', 'validity_days',
  'ADD-002: an add-on holds its validity period');
select has_column('public', 'addon_products', 'cancellation_terms',
  'ADD-002: an add-on holds its cancellation terms');
select has_column('public', 'addon_products', 'session_count',
  'ADD-002: a PT package holds its session count');
select has_column('public', 'addon_products', 'stock_quantity',
  'ADD-002: a product holds its stock level');
select has_column('public', 'addon_products', 'trainer_staff_id',
  'ADD-002: a PT package points at the trainer whose qualification it advertises');

-- ---------------------------------------------------------------------------
-- Fixtures. Inserted as postgres, which owns the tables and, with no
-- force row level security in the contract, bypasses RLS.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('0a000000-0000-4000-8000-000000000001'::uuid, 'Catalogue Gym A', 'CATP01');

insert into public.organizations (id, name, gym_code)
values ('0b000000-0000-4000-8000-000000000001'::uuid, 'Catalogue Gym B', 'CATP02');

insert into public.staff (id, tenant_id, role, full_name)
values ('0a000000-0000-4000-8000-000000000003'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid, 'trainer', 'Catalogue Trainer');

-- Complete active disclosures isolate each original structural assertion from
-- the additional Phase 6 acceptance requirements.
insert into public.addon_products (id, tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms)
values ('0a000000-0000-4000-8000-000000000006'::uuid,
        '0a000000-0000-4000-8000-000000000001'::uuid,
        'product', 'Whey 1kg', 250000, 10, 'Whey disclosure', 30, 'Unopened returns only');

-- ---------------------------------------------------------------------------
-- ADD-002 structural: a PT package needs a session count, a product needs stock
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms, trainer_staff_id, trainer_qualification)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT 10 unmetered', 500000, 'PT disclosure', 30, 'Cancel before delivery', '0a000000-0000-4000-8000-000000000003', 'Gym-stated qualification') $$,
  '23514'::char(5),
  null,
  'ADD-002: a pt_package with no session_count is rejected'
);

select lives_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, description, validity_days, cancellation_terms, trainer_staff_id, trainer_qualification)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'pt_package', 'PT 10', 500000, 10, 'PT disclosure', 30, 'Cancel before delivery', '0a000000-0000-4000-8000-000000000003', 'Gym-stated qualification') $$,
  'ADD-002: a pt_package with a session_count is accepted'
);

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'product', 'Shaker unstocked', 30000, 'Shaker disclosure', 30, 'Unopened returns only') $$,
  '23514'::char(5),
  null,
  'ADD-002: a product with no stock_quantity is rejected'
);

select lives_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'product', 'Shaker', 30000, 25, 'Shaker disclosure', 30, 'Unopened returns only') $$,
  'ADD-002: a product with a stock_quantity is accepted'
);

select lives_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'diet_plan', 'Cut 8 weeks', 200000, 'Diet disclosure', 56, 'Cancel before delivery') $$,
  'ADD-002: a diet_plan needs neither a session_count nor a stock_quantity'
);

-- ---------------------------------------------------------------------------
-- An add-on name is unique per organisation, not globally
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'product', 'Whey 1kg', 260000, 4, 'Whey disclosure', 30, 'Unopened returns only') $$,
  '23505'::char(5),
  null,
  'ADD-002: a second add-on with an existing name at the same organisation is rejected'
);

select lives_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms)
     values ('0b000000-0000-4000-8000-000000000001'::uuid, 'product', 'Whey 1kg', 260000, 4, 'Whey disclosure', 30, 'Unopened returns only') $$,
  'ADD-002: the same add-on name at a different organisation is accepted'
);

-- ---------------------------------------------------------------------------
-- DQA-004 and ADD-004: stock can never go negative, on any write
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms)
     values ('0a000000-0000-4000-8000-000000000001'::uuid, 'product', 'Creatine', 180000, -1, 'Creatine disclosure', 30, 'Unopened returns only') $$,
  '23514'::char(5),
  null,
  'DQA-004 and ADD-004: an insert with a negative stock_quantity is rejected'
);

select lives_ok(
  $$ update public.addon_products set stock_quantity = 0
      where id = '0a000000-0000-4000-8000-000000000006'::uuid $$,
  'DQA-004: stock may reach zero'
);

select throws_ok(
  $$ update public.addon_products set stock_quantity = -1
      where id = '0a000000-0000-4000-8000-000000000006'::uuid $$,
  '23514'::char(5),
  null,
  'DQA-004 and ADD-004: an update driving stock below zero is rejected'
);

select * from finish();

rollback;
