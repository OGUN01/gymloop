-- Phase 7 member money read boundary.
--
-- The mobile caller receives a JSON snapshot, so this test deliberately
-- verifies observable facts rather than the implementation or JSON layout.
-- Bigint values exceed JavaScript's safe-integer range to prove that the
-- boundary supplies decimal text, not JSON numbers (UX7 / ADD-011 / MNY-001).

begin;

select plan(7);

set local role postgres;

insert into public.organizations (id, name, gym_code) values
  ('61000000-0000-4000-8000-000000000001', 'Money mobile gym', 'MMG061');

insert into public.branches (id, tenant_id, name) values
  ('61000000-0000-4000-8000-000000000011', '61000000-0000-4000-8000-000000000001', 'Main');

insert into auth.users (id, raw_app_meta_data) values
  ('61000000-0000-4000-8000-000000000021', '{}'::jsonb),
  ('61000000-0000-4000-8000-000000000022', '{}'::jsonb),
  ('61000000-0000-4000-8000-000000000023', '{}'::jsonb);

insert into public.staff (id, tenant_id, user_id, role, full_name) values
  ('61000000-0000-4000-8000-000000000031', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000021', 'front_desk', 'Receipt desk');

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('61000000-0000-4000-8000-000000000041', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000011', '61000000-0000-4000-8000-000000000022', 'Aarav', '+916100000041'),
  ('61000000-0000-4000-8000-000000000042', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000011', '61000000-0000-4000-8000-000000000023', 'Other member', '+916100000042');

insert into public.addon_products (id, tenant_id, kind, name, description, price_paise,
                                   validity_days, stock_quantity, cancellation_terms) values
  ('61000000-0000-4000-8000-000000000051', '61000000-0000-4000-8000-000000000001',
   'product', 'Aarav mobile order', 'Own frozen product', 9007199254740993, 30, 1, 'No returns'),
  ('61000000-0000-4000-8000-000000000052', '61000000-0000-4000-8000-000000000001',
   'product', 'Other mobile order', 'Other frozen product', 9007199254740907, 30, 1, 'No returns');

-- The fixture is source data for the read boundary, not a sale-command test.
set local session_replication_role = replica;
insert into public.payments (id, tenant_id, member_id, amount_paise, currency, status,
                             method, recorded_by_staff_id, receipt_number, paid_at) values
  ('61000000-0000-4000-8000-000000000061', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000041', 9007199254740993, 'INR', 'paid', 'cash',
   '61000000-0000-4000-8000-000000000031', 'AARAV-MOBILE-RECEIPT', transaction_timestamp()),
  ('61000000-0000-4000-8000-000000000062', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000042', 9007199254740907, 'INR', 'paid', 'cash',
   '61000000-0000-4000-8000-000000000031', 'OTHER-MOBILE-RECEIPT', transaction_timestamp());

insert into public.addon_orders (id, tenant_id, member_id, addon_product_id, payment_id, status,
                                 quantity, unit_price_paise, total_paise, currency, sold_by_staff_id,
                                 sold_at, sale_snapshot) values
  ('61000000-0000-4000-8000-000000000071', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000041', '61000000-0000-4000-8000-000000000051',
   '61000000-0000-4000-8000-000000000061', 'paid', 1, 9007199254740993, 9007199254740993,
   'INR', '61000000-0000-4000-8000-000000000031', transaction_timestamp(),
   '{"name":"Aarav mobile order"}'::jsonb),
  ('61000000-0000-4000-8000-000000000072', '61000000-0000-4000-8000-000000000001',
   '61000000-0000-4000-8000-000000000042', '61000000-0000-4000-8000-000000000052',
   '61000000-0000-4000-8000-000000000062', 'paid', 1, 9007199254740907, 9007199254740907,
   'INR', '61000000-0000-4000-8000-000000000031', transaction_timestamp(),
   '{"name":"Other mobile order"}'::jsonb);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-4000-8000-000000000022","role":"authenticated","app_role":"member","tenant_id":"61000000-0000-4000-8000-000000000001","member_id":"61000000-0000-4000-8000-000000000041"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.read_member_mobile_money()$$,
  'UX7: the canonical member money snapshot compiles and runs'
);

select is(
  jsonb_typeof(public.read_member_mobile_money()),
  'object',
  'UX7: the member money snapshot is a structured JSON object'
);

select ok(
  jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == "AARAV-MOBILE-RECEIPT")'),
  'UX7: Aarav receives his own receipt'
);

select ok(
  not jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == "OTHER-MOBILE-RECEIPT")'),
  'UX7: Aarav cannot receive another member''s receipt'
);

select ok(
  jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == "61000000-0000-4000-8000-000000000071")'),
  'ADD-011: Aarav receives his own add-on order'
);

select ok(
  not jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == "61000000-0000-4000-8000-000000000072")'),
  'ADD-011: Aarav cannot receive another member''s add-on order'
);

select ok(
  jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == "9007199254740993")')
  and not jsonb_path_exists(public.read_member_mobile_money(), '$.** ? (@ == 9007199254740993)'),
  'MNY-001/MNY-002/ADD-011: bigint INR paise crosses the mobile boundary as canonical decimal text'
);

select * from finish();

rollback;
