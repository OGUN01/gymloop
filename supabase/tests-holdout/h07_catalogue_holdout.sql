-- Holdout pgTAP suite - Phase 1 cluster: catalogue
-- Tables under test: addon_products, addon_orders, pt_sessions.
-- Written blind from openspec/changes/0001-data-model/specs/catalogue/spec.md,
-- docs/data-model.md (Conventions (the contract), Cluster: catalogue, Enums)
-- and docs/domain-rules.md. The migration and the visible suite were never read.
-- Every fixture uuid is prefixed 00000000-0000-4000-8000-0000007 so a combined
-- run alongside another cluster's holdout file cannot collide.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(111);

-- ---------------------------------------------------------------------------
-- A. The shape the contract fixes
-- ---------------------------------------------------------------------------

select has_table('public', 'addon_products', 'catalogue spec Purpose: the add-on catalogue table exists');
select has_table('public', 'addon_orders', 'catalogue spec Purpose: the add-on order table exists');
select has_table('public', 'pt_sessions', 'catalogue spec Purpose: the personal-training session table exists');

select enum_has_labels('public', 'addon_kind', array['pt_package', 'diet_plan', 'product']::name[], 'docs/data-model.md Enums: addon_kind label set, in the order the contract fixes');
select enum_has_labels('public', 'addon_order_status', array['pending', 'paid', 'active', 'completed', 'cancelled', 'refunded']::name[], 'docs/data-model.md Enums: addon_order_status label set, in the order the contract fixes');
select enum_has_labels('public', 'pt_session_status', array['scheduled', 'completed', 'cancelled', 'no_show']::name[], 'docs/data-model.md Enums: pt_session_status label set, in the order the contract fixes');

select ok((select t.typname from pg_attribute a join pg_type t on t.oid = a.atttypid where a.attrelid = 'public.addon_products'::regclass and a.attname = 'kind') = 'addon_kind', 'ADR-021: addon_products.kind is the addon_kind enum, not a hand-written vocabulary');

select col_type_is('public', 'addon_products', 'price_paise', 'bigint', 'MNY-001: addon_products.price_paise');
select col_type_is('public', 'addon_orders', 'total_paise', 'bigint', 'MNY-001: addon_orders.total_paise');

select is_empty(
  $$ select a.attname::text collate "default"
       from pg_attribute a
       join pg_type t on t.oid = a.atttypid
      where a.attrelid in ('public.addon_products'::regclass, 'public.addon_orders'::regclass, 'public.pt_sessions'::regclass)
        and a.attnum > 0
        and not a.attisdropped
        and t.typname in ('numeric', 'float4', 'float8') $$,
  'MNY-001: no catalogue column is numeric or floating point'
);

select is((select count(*)::integer from pg_attribute a where a.attrelid = 'public.addon_products'::regclass and a.attnum > 0 and not a.attisdropped and a.attname = 'currency'), 1, 'MNY-002: addon_products carries exactly one currency column');
select is((select count(*)::integer from pg_attribute a where a.attrelid = 'public.addon_orders'::regclass and a.attnum > 0 and not a.attisdropped and a.attname = 'currency'), 1, 'MNY-002: addon_orders carries exactly one currency column');
select is((select count(*)::integer from pg_attribute a where a.attrelid = 'public.pt_sessions'::regclass and a.attnum > 0 and not a.attisdropped and a.attname = 'currency'), 0, 'MNY-002: pt_sessions holds no money and so carries no currency column');

select has_column('public', 'addon_products', 'validity_days', 'ADD-002: the validity period is stored');
select has_column('public', 'addon_products', 'cancellation_terms', 'ADD-002: the cancellation terms are stored');

select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.addon_products'::regclass and c.contype = 'f'
     and c.confrelid = 'public.staff'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'trainer_staff_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'ADD-002: a PT package reaches its trainer, and through staff the trainer qualification - the key is (tenant_id, trainer_staff_id) references staff (tenant_id, id) since ADR-052, a composite shape fk_ok cannot express');
select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.addon_orders'::regclass and c.contype = 'f'
     and c.confrelid = 'public.payments'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'payment_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'catalogue spec: an add-on order references the payment that bought it, and since ADR-052 by (tenant_id, payment_id) references payments (tenant_id, id), so the payment is one this gym took');
select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.pt_sessions'::regclass and c.contype = 'f'
     and c.confrelid = 'public.staff'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'trainer_staff_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'DQA-005: a session names the trainer the exclusion constraint keys on, by (tenant_id, trainer_staff_id) references staff (tenant_id, id) since ADR-052, so that trainer works at this gym');
select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.pt_sessions'::regclass and c.contype = 'f'
     and c.confrelid = 'public.addon_orders'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'addon_order_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'catalogue spec Purpose: a session belongs to the order that bought it, by (tenant_id, addon_order_id) references addon_orders (tenant_id, id) since ADR-052');

select ok(exists(select 1 from pg_extension e where e.extname = 'btree_gist'), 'DQA-005: btree_gist is installed, the equality half of the overlap exclusion needs it');
select ok(exists(select 1 from pg_constraint c where c.conrelid = 'public.pt_sessions'::regclass and c.contype = 'x' and c.conname = 'pt_sessions_trainer_overlap_excl'), 'DQA-005: the trainer double-booking rule is an exclusion constraint, not application code');

select has_trigger('public', 'addon_orders', 'addon_orders_touch_updated_at', 'docs/data-model.md Every table: updated_at is maintained by the one shared trigger');

select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.addon_products'::regclass), 'gate 7: row-level security is enabled on addon_products');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.addon_orders'::regclass), 'gate 7: row-level security is enabled on addon_orders');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.pt_sessions'::regclass), 'gate 7: row-level security is enabled on pt_sessions');

-- Phase 1's "the pair and nothing else" pinned a policy count that a later phase was
-- always going to change; Phase 2 made it five. The durable form of the same intent is
-- that a table carries no policy outside the sanctioned vocabulary, and carries at
-- least the gym-side and platform-side reads. A rogue or misnamed policy still fails.
select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.addon_products')
     and p.polname::text collate "default" not in ('addon_products_platform_select', 'addon_products_platform_write', 'addon_products_tenant_select', 'addon_products_tenant_write', 'addon_products_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['addon_products_tenant_select', 'addon_products_platform_select']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.addon_products')
                      and p.polname::text collate "default" = x)
$q$, 'docs/data-model.md Row-Level Security: addon_products carries only sanctioned policy names, gym-side and platform-side reads among them'
);
-- Phase 1's "the pair and nothing else" pinned a policy count that a later phase was
-- always going to change; Phase 2 made it five. The durable form of the same intent is
-- that a table carries no policy outside the sanctioned vocabulary, and carries at
-- least the gym-side and platform-side reads. A rogue or misnamed policy still fails.
select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.addon_orders')
     and p.polname::text collate "default" not in ('addon_orders_platform_select', 'addon_orders_platform_write', 'addon_orders_tenant_select', 'addon_orders_tenant_write', 'addon_orders_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['addon_orders_tenant_select', 'addon_orders_platform_select']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.addon_orders')
                      and p.polname::text collate "default" = x)
$q$, 'docs/data-model.md Row-Level Security: addon_orders carries only sanctioned policy names, gym-side and platform-side reads among them'
);
-- Phase 1's "the pair and nothing else" pinned a policy count that a later phase was
-- always going to change; Phase 2 made it five. The durable form of the same intent is
-- that a table carries no policy outside the sanctioned vocabulary, and carries at
-- least the gym-side and platform-side reads. A rogue or misnamed policy still fails.
select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.pt_sessions')
     and p.polname::text collate "default" not in ('pt_sessions_platform_select', 'pt_sessions_platform_write', 'pt_sessions_tenant_select', 'pt_sessions_tenant_write', 'pt_sessions_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['pt_sessions_tenant_select', 'pt_sessions_platform_select']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.pt_sessions')
                      and p.polname::text collate "default" = x)
$q$, 'docs/data-model.md Row-Level Security: pt_sessions carries only sanctioned policy names, gym-side and platform-side reads among them'
);

select isnt_empty(
  $$ select c.relname::text collate "default"
       from pg_index i
       join pg_class c on c.oid = i.indexrelid
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
      where i.indrelid = 'public.addon_orders'::regclass
        and i.indpred is null
        and a.attname = 'tenant_id'
        and c.relam = (select am.oid from pg_am am where am.amname = 'btree') $$,
  'gate 8: addon_orders has a non-partial btree index leading with its RLS column'
);

select ok(
  not has_table_privilege('anon', 'public.addon_orders', 'SELECT')
  and not has_table_privilege('anon', 'public.addon_orders', 'INSERT')
  and not has_table_privilege('anon', 'public.addon_orders', 'UPDATE')
  and not has_table_privilege('anon', 'public.addon_orders', 'DELETE')
  and not has_table_privilege('anon', 'public.addon_orders', 'TRUNCATE'),
  'docs/data-model.md Privileges: anon holds nothing on addon_orders'
);
select ok(
  has_table_privilege('authenticated', 'public.addon_orders', 'SELECT')
  and has_table_privilege('authenticated', 'public.addon_orders', 'INSERT')
  and has_table_privilege('authenticated', 'public.addon_orders', 'UPDATE'),
  'docs/data-model.md Privileges: addon_orders sits in the history tier for authenticated'
);
select ok(
  not has_table_privilege('authenticated', 'public.addon_orders', 'DELETE')
  and not has_table_privilege('authenticated', 'public.addon_orders', 'TRUNCATE'),
  'INT-001: authenticated holds neither delete nor truncate on addon_orders'
);

-- ---------------------------------------------------------------------------
-- B. Fixtures, inserted as the owner - postgres holds BYPASSRLS
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-00000070000a', 'Holdout Catalogue Gym A', 'H7CATA'),
  ('00000000-0000-4000-8000-00000070000b', 'Holdout Catalogue Gym B', 'H7CATB');

insert into public.branches (id, tenant_id, name) values
  ('00000000-0000-4000-8000-00000070001a', '00000000-0000-4000-8000-00000070000a', 'Holdout Catalogue Branch A'),
  ('00000000-0000-4000-8000-00000070001b', '00000000-0000-4000-8000-00000070000b', 'Holdout Catalogue Branch B');

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-00000070001a', 'trainer', 'Holdout Trainer A One'),
  ('00000000-0000-4000-8000-000000700022', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-00000070001a', 'trainer', 'Holdout Trainer A Two'),
  ('00000000-0000-4000-8000-00000070002b', '00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070001b', 'trainer', 'Holdout Trainer B One');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-00000070001a', 'Holdout Member A', '+919000700031'),
  ('00000000-0000-4000-8000-00000070003b', '00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070001b', 'Holdout Member B', '+919000700039');

insert into public.payments (id, tenant_id, member_id, amount_paise, method, recorded_by_staff_id, status, paid_at) values
  ('00000000-0000-4000-8000-000000700041', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', 1000000, 'cash', '00000000-0000-4000-8000-000000700021', 'paid', transaction_timestamp()),
  ('00000000-0000-4000-8000-000000700042', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', 100000, 'cash', '00000000-0000-4000-8000-000000700021', 'paid', transaction_timestamp());

insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification) values
  ('00000000-0000-4000-8000-000000700051', '00000000-0000-4000-8000-00000070000a', 'pt_package', 'Holdout PT Ten Pack', 1000000, 10, '00000000-0000-4000-8000-000000700021', 'Disclosed holdout offer', 365, 'Desk cancellation', 'Gym-qualified trainer');

insert into public.addon_products (id, tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification) values
  ('00000000-0000-4000-8000-000000700052', '00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Whey One Kg', 250000, 5, 'Disclosed holdout offer', 365, 'Desk cancellation', null),
  ('00000000-0000-4000-8000-00000070005b', '00000000-0000-4000-8000-00000070000b', 'product', 'Holdout Gym B Creatine', 150000, 3, 'Disclosed holdout offer', 365, 'Desk cancellation', null);

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, payment_id, status, quantity, unit_price_paise, total_paise, sessions_total, sessions_used, trainer_staff_id, starts_on, expires_on) values
  ('00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700051', '00000000-0000-4000-8000-000000700041', 'active', 1, 1000000, 1000000, 10, 0, '00000000-0000-4000-8000-000000700021', (transaction_timestamp() at time zone 'Asia/Kolkata')::date, (transaction_timestamp() at time zone 'Asia/Kolkata')::date+365);

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise, sessions_total, sessions_used) values
  ('00000000-0000-4000-8000-000000700062', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700051', 1000000, 1000000, 5, 4);

insert into public.addon_products(id,tenant_id,kind,name,price_paise,session_count,trainer_staff_id,trainer_qualification,description,validity_days,cancellation_terms) values
  ('00000000-0000-4000-8000-00000070005c','00000000-0000-4000-8000-00000070000b','pt_package','Gym B PT',0,10,'00000000-0000-4000-8000-00000070002b','Gym-qualified trainer','Disclosed PT offer',365,'Desk cancellation');
insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise,status,trainer_staff_id,sessions_total,starts_on,expires_on) values
  ('00000000-0000-4000-8000-00000070006b', '00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070003b', '00000000-0000-4000-8000-00000070005c', 0, 0,'active','00000000-0000-4000-8000-00000070002b',10,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+365);

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at) values
  ('00000000-0000-4000-8000-000000700071', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-01 10:00:00+05:30', '2026-10-01 11:00:00+05:30'),
  ('00000000-0000-4000-8000-00000070007b', '00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070006b', '00000000-0000-4000-8000-00000070002b', '00000000-0000-4000-8000-00000070003b', '2026-10-10 10:00:00+05:30', '2026-10-10 11:00:00+05:30');

-- ---------------------------------------------------------------------------
-- C. ADD-002 - an add-on carries what a member must see before buying
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'pt_package', 'Holdout PT No Session Count', 500000, 'Disclosed holdout offer', 365, 'Desk cancellation', 'Gym-qualified trainer') $$,
  '23514'::char(5), null,
  'ADD-002 scenario: A PT package with no session count'
);
select lives_ok(
  $$ insert into public.addon_products (id, tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-0000007000e1', '00000000-0000-4000-8000-00000070000a', 'pt_package', 'Holdout PT Five Pack', 500000, 5, '00000000-0000-4000-8000-000000700021', 'Disclosed holdout offer', 365, 'Desk cancellation', 'Gym-qualified trainer') $$,
  'ADD-002: a PT package carrying its session count is accepted'
);
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Product No Stock', 90000, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '23514'::char(5), null,
  'ADD-002 scenario: A product with no stock level'
);
select lives_ok(
  $$ insert into public.addon_products (id, tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-000000700053', '00000000-0000-4000-8000-00000070000a', 'diet_plan', 'Holdout Diet Plan Thirty Days', 100000, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  'ADD-002 scenario: A diet plan needs neither'
);
select is((select p.currency from public.addon_products p where p.id = '00000000-0000-4000-8000-000000700053'), 'INR', 'MNY-002: addon_products.currency defaults to INR');
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, session_count, trainer_staff_id, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'pt_package', 'Holdout PT Zero Sessions', 500000, 0, '00000000-0000-4000-8000-000000700021', 'Disclosed holdout offer', 365, 'Desk cancellation', 'Gym-qualified trainer') $$,
  '23514'::char(5), null,
  'ADD-002: a PT package selling zero sessions is rejected'
);
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Whey One Kg', 250000, 2, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '23505'::char(5), null,
  'ADD-002 scenario: A duplicate add-on name at one gym'
);
select lives_ok(
  $$ insert into public.addon_products (id, tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-0000007000e3', '00000000-0000-4000-8000-00000070000b', 'product', 'Holdout Whey One Kg', 250000, 2, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  'ADD-002: the add-on name is unique per organisation, not across the platform'
);

-- ---------------------------------------------------------------------------
-- D. DQA-004 / ADD-004 - stock can never go negative
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Negative Stock Product', 90000, -1, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '23514'::char(5), null,
  'DQA-004: a product written with negative stock is rejected'
);
select throws_ok(
  $$ update public.addon_products set stock_quantity = -1 where id = '00000000-0000-4000-8000-000000700052' $$,
  '23514'::char(5), null,
  'DQA-004 scenario: Stock driven below zero'
);
select lives_ok(
  $$ update public.addon_products set stock_quantity = 0 where id = '00000000-0000-4000-8000-000000700052' $$,
  'DQA-004: exhausted stock, zero, is still a legal stock level'
);
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Negative Price Product', -1, 4, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '23514'::char(5), null,
  'MNY-001: a negative add-on price is rejected'
);
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, currency, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'product', 'Holdout Bad Currency Product', 90000, 'inr', 4, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '23514'::char(5), null,
  'MNY-002: addon_products.currency must match the three-letter uppercase pattern'
);
select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000a', 'supplement_box', 'Holdout Bad Kind Product', 90000, 4, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '22P02'::char(5), null,
  'docs/data-model.md Enums: addon_kind is a closed vocabulary'
);

-- ---------------------------------------------------------------------------
-- E. addon_orders - ADD-004, the paid-order rule, and the validity window
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-0000007000d2', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 100000, 100000) $$,
  'catalogue spec scenario: A pending order with no payment'
);
select is((select o.status::text from public.addon_orders o where o.id = '00000000-0000-4000-8000-0000007000d2'), 'pending', 'docs/data-model.md Cluster: catalogue - addon_orders.status defaults to pending');
select is((select o.quantity from public.addon_orders o where o.id = '00000000-0000-4000-8000-0000007000d2'), 1, 'docs/data-model.md Cluster: catalogue - addon_orders.quantity defaults to one');
select is((select o.sessions_used from public.addon_orders o where o.id = '00000000-0000-4000-8000-0000007000d2'), 0, 'ADD-004: addon_orders.sessions_used starts at zero');
select is((select o.currency from public.addon_orders o where o.id = '00000000-0000-4000-8000-0000007000d2'), 'INR', 'MNY-002: addon_orders.currency defaults to INR');

select throws_ok(
  $$ update public.addon_orders set sessions_used = 6 where id = '00000000-0000-4000-8000-000000700062' $$,
  '23514'::char(5), null,
  'ADD-004 scenario: Consuming more sessions than were bought'
);
select lives_ok(
  $$ update public.addon_orders set sessions_used = 5 where id = '00000000-0000-4000-8000-000000700062' $$,
  'ADD-004 scenario: Consuming the last session'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise, sessions_total, sessions_used)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700051', 100000, 100000, 5, -1) $$,
  '23514'::char(5), null,
  'ADD-004 scenario: A negative used-session count'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'paid', 100000, 100000) $$,
  '23514'::char(5), null,
  'catalogue spec scenario: A paid order with no payment'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'active', 100000, 100000) $$,
  '23514'::char(5), null,
  'catalogue spec: an order past pending still carries its payment, active is not an escape from the rule'
);
select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'paid', 0, 0) $$,
  'catalogue spec: a zero-total order needs no payment reference'
);
select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, payment_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', '00000000-0000-4000-8000-000000700042', 'paid', 100000, 100000) $$,
  'catalogue spec: a paid order that carries its payment is accepted'
);
select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'cancelled', 100000, 100000) $$,
  'catalogue spec: a cancelled order needs no payment reference'
);

select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise, starts_on, expires_on)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 100000, 100000, '2026-10-10', '2026-10-09') $$,
  '23514'::char(5), null,
  'catalogue spec scenario: An expiry before the start'
);
select lives_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise, starts_on, expires_on)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 100000, 100000, '2026-10-10', '2026-10-10') $$,
  'catalogue spec: a single-day validity window, expiry equal to start, is accepted'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, quantity, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 0, 100000, 0) $$,
  '23514'::char(5), null,
  'catalogue spec scenario: A zero quantity'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 100000, -1) $$,
  '23514'::char(5), null,
  'MNY-001: a negative order total is rejected'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, currency, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'Inr', 100000, 100000) $$,
  '23514'::char(5), null,
  'MNY-002: addon_orders.currency must match the three-letter uppercase pattern'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, status, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700031', '00000000-0000-4000-8000-000000700053', 'shipped', 100000, 100000) $$,
  '22P02'::char(5), null,
  'docs/data-model.md Enums: addon_order_status is a closed vocabulary'
);

-- ---------------------------------------------------------------------------
-- F. DQA-005 - a trainer cannot be double-booked
-- ---------------------------------------------------------------------------

select is((select s.status::text from public.pt_sessions s where s.id = '00000000-0000-4000-8000-000000700071'), 'scheduled', 'docs/data-model.md Cluster: catalogue - pt_sessions.status defaults to scheduled');

select throws_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-000000700072', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-01 10:30:00+05:30', '2026-10-01 11:30:00+05:30') $$,
  '23P01'::char(5), null,
  'DQA-005 scenario: Two overlapping sessions for one trainer'
);
select lives_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-000000700073', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-01 11:00:00+05:30', '2026-10-01 12:00:00+05:30') $$,
  'DQA-005 scenario: Two adjacent sessions for one trainer'
);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,trainer_staff_id,sessions_total,starts_on,expires_on)
values ('00000000-0000-4000-8000-000000700063','00000000-0000-4000-8000-00000070000a','00000000-0000-4000-8000-000000700031','00000000-0000-4000-8000-000000700051','active',1,0,0,'00000000-0000-4000-8000-000000700022',10,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+365);
select lives_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-000000700074', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700063', '00000000-0000-4000-8000-000000700022', '00000000-0000-4000-8000-000000700031', '2026-10-01 10:30:00+05:30', '2026-10-01 11:30:00+05:30') $$,
  'DQA-005 scenario: Overlapping sessions for different trainers'
);
select throws_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-0000007000f1', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-00000070002b', '00000000-0000-4000-8000-000000700031', '2026-10-10 10:30:00+05:30', '2026-10-10 11:30:00+05:30') $$,
  '23503'::char(5), null,
  'ADR-052: gym A cannot book a session in its own tenant against gym B''s trainer - pt_sessions.trainer_staff_id is (tenant_id, trainer_staff_id) references staff (tenant_id, id). This was the write that let one gym fill another gym''s calendar; ADR-047 stopped it colliding, ADR-052 stops it existing'
);
select ok(
  (select count(*) from pg_attribute a
     where a.attrelid = 'public.pt_sessions'::regclass
       and a.attnum = (select c.conkey[1] from pg_constraint c
                        where c.conrelid = 'public.pt_sessions'::regclass
                          and c.conname = 'pt_sessions_trainer_overlap_excl')
       and a.attname = 'tenant_id') = 1,
  'ADR-047: the overlap exclusion still leads with tenant_id - ADR-052 removed the write that probed this, so the tenant term is asserted over the catalogue instead, and it stays because a constraint ignores RLS and defence in depth is the point'
);

insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at, status) values
  ('00000000-0000-4000-8000-000000700075', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-02 09:00:00+05:30', '2026-10-02 10:00:00+05:30', 'cancelled'),
  ('00000000-0000-4000-8000-000000700077', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-03 09:00:00+05:30', '2026-10-03 10:00:00+05:30', 'no_show'),
  ('00000000-0000-4000-8000-000000700079', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-04 09:00:00+05:30', '2026-10-04 10:00:00+05:30', 'completed'),
  ('00000000-0000-4000-8000-00000070007c', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-05 09:00:00+05:30', '2026-10-05 10:00:00+05:30', 'scheduled');

select lives_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-000000700076', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-02 09:30:00+05:30', '2026-10-02 10:30:00+05:30') $$,
  'DQA-005 scenario: A cancelled session frees the slot'
);
select lives_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-000000700078', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-03 09:30:00+05:30', '2026-10-03 10:30:00+05:30') $$,
  'DQA-005: a no_show session frees the slot on the same rule that frees a cancelled one'
);
select throws_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-00000070007a', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-04 09:30:00+05:30', '2026-10-04 10:30:00+05:30') $$,
  '23P01'::char(5), null,
  'DQA-005: the exclusion covers completed as well as scheduled, a session already delivered still occupied the trainer'
);
select lives_ok(
  $$ insert into public.pt_sessions (id, tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at, status)
     values ('00000000-0000-4000-8000-00000070007d', '00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700021', '00000000-0000-4000-8000-000000700031', '2026-10-05 09:30:00+05:30', '2026-10-05 10:30:00+05:30', 'cancelled') $$,
  'DQA-005: a cancelled session is outside the exclusion predicate on the way in as well as the way out'
);
select throws_ok(
  $$ update public.pt_sessions set status = 'scheduled' where id = '00000000-0000-4000-8000-00000070007d' $$,
  '23P01'::char(5), null,
  'DQA-005: reviving a cancelled session into a slot the trainer already holds is rejected'
);
select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700022', '00000000-0000-4000-8000-000000700031', '2026-10-06 10:00:00+05:30', '2026-10-06 09:00:00+05:30') $$,
  '23514'::char(5), null,
  'catalogue spec scenario: A session that ends before it starts'
);
select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700022', '00000000-0000-4000-8000-000000700031', '2026-10-06 10:00:00+05:30', '2026-10-06 10:00:00+05:30') $$,
  '23514'::char(5), null,
  'catalogue spec: a zero-length session, end equal to start, is rejected too'
);
select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at, status)
     values ('00000000-0000-4000-8000-00000070000a', '00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-000000700022', '00000000-0000-4000-8000-000000700031', '2026-11-02 08:00:00+05:30', '2026-11-02 09:00:00+05:30', 'rescheduled') $$,
  '22P02'::char(5), null,
  'docs/data-model.md Enums: pt_session_status is a closed vocabulary'
);

-- ---------------------------------------------------------------------------
-- G. gate 7 - no tenant claim has been set in this transaction at all
-- ---------------------------------------------------------------------------

set local role authenticated;

select lives_ok(
  $$ select count(*) from public.addon_products $$,
  'docs/data-model.md Row-Level Security: a missing tenant claim filters, it does not raise'
);
select is_empty(
  $$ select p.id from public.addon_products p $$,
  'gate 7: a session with no tenant claim sees no addon_products'
);
select is_empty(
  $$ select o.id from public.addon_orders o $$,
  'gate 7: a session with no tenant claim sees no addon_orders'
);
select is_empty(
  $$ select s.id from public.pt_sessions s $$,
  'gate 7: a session with no tenant claim sees no pt_sessions'
);

set local role postgres;

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is_empty(
  $$ select p.id from public.addon_products p $$,
  'gate 7: an empty claim string sees no addon_products'
);
select is_empty(
  $$ select o.id from public.addon_orders o $$,
  'gate 7: an empty claim string sees no addon_orders'
);
select is_empty(
  $$ select s.id from public.pt_sessions s $$,
  'gate 7: an empty claim string sees no pt_sessions'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- H. gate 7 - a signed-in owner of Gym A
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000070000a', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select isnt_empty(
  $$ select p.id from public.addon_products p where p.id = '00000000-0000-4000-8000-000000700051' $$,
  'gate 7: Gym A reads its own addon_products'
);
select isnt_empty(
  $$ select o.id from public.addon_orders o where o.id = '00000000-0000-4000-8000-000000700061' $$,
  'gate 7: Gym A reads its own addon_orders'
);
select isnt_empty(
  $$ select s.id from public.pt_sessions s where s.id = '00000000-0000-4000-8000-000000700071' $$,
  'gate 7: Gym A reads its own pt_sessions'
);
select is_empty(
  $$ select p.id from public.addon_products p where p.id = '00000000-0000-4000-8000-00000070005b' $$,
  'gate 7: Gym A cannot read Gym B addon_products'
);
select is_empty(
  $$ select o.id from public.addon_orders o where o.id = '00000000-0000-4000-8000-00000070006b' $$,
  'gate 7: Gym A cannot read Gym B addon_orders'
);
select is_empty(
  $$ select s.id from public.pt_sessions s where s.id = '00000000-0000-4000-8000-00000070007b' $$,
  'gate 7: Gym A cannot read Gym B pt_sessions'
);

select throws_ok(
  $$ insert into public.addon_products (tenant_id, kind, name, price_paise, stock_quantity, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-00000070000b', 'product', 'Holdout Cross Tenant Product', 90000, 1, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  '42501'::char(5), null,
  'gate 7: Gym A cannot insert an addon_products row labelled with the Gym B tenant id'
);
select throws_ok(
  $$ insert into public.addon_orders (tenant_id, member_id, addon_product_id, unit_price_paise, total_paise)
     values ('00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070003b', '00000000-0000-4000-8000-00000070005b', 90000, 90000) $$,
  '42501'::char(5), null,
  'gate 7: Gym A cannot insert an addon_orders row labelled with the Gym B tenant id'
);
select throws_ok(
  $$ insert into public.pt_sessions (tenant_id, addon_order_id, trainer_staff_id, member_id, starts_at, ends_at)
     values ('00000000-0000-4000-8000-00000070000b', '00000000-0000-4000-8000-00000070006b', '00000000-0000-4000-8000-00000070002b', '00000000-0000-4000-8000-00000070003b', '2026-12-01 10:00:00+05:30', '2026-12-01 11:00:00+05:30') $$,
  '42501'::char(5), null,
  'gate 7: Gym A cannot insert a pt_sessions row labelled with the Gym B tenant id'
);

select lives_ok(
  $$ update public.addon_products set is_active = false where id = '00000000-0000-4000-8000-00000070005b' $$,
  'gate 7: an update against a Gym B addon_products primary key filters rather than raising'
);
select lives_ok(
  $$ update public.addon_orders set status = 'cancelled' where id = '00000000-0000-4000-8000-00000070006b' $$,
  'gate 7: an update against a Gym B addon_orders primary key filters rather than raising'
);

select throws_ok(
  $$ delete from public.addon_orders where id = '00000000-0000-4000-8000-000000700061' $$,
  '42501'::char(5), null,
  'INT-001 scenario: Deleting an order'
);

set local role postgres;

select is((select p.is_active from public.addon_products p where p.id = '00000000-0000-4000-8000-00000070005b'), true, 'gate 7: the Gym B addon_products row is unchanged after Gym A tried to update it by primary key');
select is((select o.status::text from public.addon_orders o where o.id = '00000000-0000-4000-8000-00000070006b'), 'active', 'gate 7: the Gym B addon_orders row is unchanged after Gym A tried to update it by primary key');

-- ---------------------------------------------------------------------------
-- I. gate 7 - the reverse direction, and a non-platform role of Gym A
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000070000b', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select isnt_empty(
  $$ select p.id from public.addon_products p where p.id = '00000000-0000-4000-8000-00000070005b' $$,
  'gate 7: Gym B reads its own addon_products'
);
select is_empty(
  $$ select o.id from public.addon_orders o where o.id = '00000000-0000-4000-8000-000000700061' $$,
  'gate 7: Gym B cannot read Gym A addon_orders'
);
select is_empty(
  $$ select s.id from public.pt_sessions s where s.id = '00000000-0000-4000-8000-000000700071' $$,
  'gate 7: Gym B cannot read Gym A pt_sessions'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000070000a', 'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select is_empty(
  $$ select p.id from public.addon_products p where p.id = '00000000-0000-4000-8000-00000070005b' $$,
  'gate 7: a front_desk role of Gym A is still tenant-scoped, only the two platform roles cross'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- J. the platform branch - super_admin and platform_support cross by policy
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000070000a', 'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is((select count(*)::integer from public.addon_products p where p.id in ('00000000-0000-4000-8000-000000700051', '00000000-0000-4000-8000-00000070005b')), 2, 'docs/security.md Impersonation and platform access: super_admin crosses tenants on addon_products by policy');
select is((select count(*)::integer from public.addon_orders o where o.id in ('00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-00000070006b')), 2, 'docs/security.md Impersonation and platform access: super_admin crosses tenants on addon_orders by policy');
select is((select count(*)::integer from public.pt_sessions s where s.id in ('00000000-0000-4000-8000-000000700071', '00000000-0000-4000-8000-00000070007b')), 2, 'docs/security.md Impersonation and platform access: super_admin crosses tenants on pt_sessions by policy');
select lives_ok(
  $$ insert into public.addon_products (id, tenant_id, kind, name, price_paise, description, validity_days, cancellation_terms, trainer_qualification)
     values ('00000000-0000-4000-8000-0000007000e4', '00000000-0000-4000-8000-00000070000b', 'diet_plan', 'Holdout Platform Written Plan', 90000, 'Disclosed holdout offer', 365, 'Desk cancellation', null) $$,
  'docs/data-model.md Row-Level Security: the platform policy with check lets super_admin write outside its own claim tenant'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000070000a', 'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select is((select count(*)::integer from public.addon_products p where p.id in ('00000000-0000-4000-8000-000000700051', '00000000-0000-4000-8000-00000070005b')), 2, 'docs/security.md Impersonation and platform access: platform_support crosses tenants on addon_products by policy');
select is((select count(*)::integer from public.addon_orders o where o.id in ('00000000-0000-4000-8000-000000700061', '00000000-0000-4000-8000-00000070006b')), 2, 'docs/security.md Impersonation and platform access: platform_support crosses tenants on addon_orders by policy');

set local role postgres;

-- ---------------------------------------------------------------------------
-- K. a tenant claim that is present but is not a uuid must fail loudly
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'not-a-uuid', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$ select p.id from public.addon_products p $$,
  '22P02'::char(5), null,
  'docs/data-model.md app schema accessors: a malformed tenant claim raises rather than degrading into an empty gym'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
