BEGIN;

select plan(6);

set local session_replication_role = replica;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '60000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'mobile-money-member@example.test',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.organizations (id, name, gym_code, status)
values (
  '60000000-0000-0000-0000-000000000010',
  'Mobile money holdout gym',
  'MONEY60',
  'active'
);

insert into public.branches (id, tenant_id, name, is_default)
values (
  '60000000-0000-0000-0000-000000000011',
  '60000000-0000-0000-0000-000000000010',
  'Mobile money branch',
  true
);

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone)
values
  (
    '60000000-0000-0000-0000-000000000012',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000011',
    '60000000-0000-0000-0000-000000000001',
    'Mobile money member',
    '+919000000060'
  ),
  (
    '60000000-0000-0000-0000-000000000013',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000011',
    null,
    'Other mobile money member',
    '+919000000061'
  );

insert into public.addon_products (
  id, tenant_id, kind, name, description, price_paise, currency,
  quote_version, validity_days, stock_quantity, cancellation_terms, is_active
) values
  (
    '60000000-0000-0000-0000-000000000014',
    '60000000-0000-0000-0000-000000000010',
    'product',
    'Renamed catalogue product',
    'Current catalogue description',
    9007199254740993,
    'INR',
    '60000000-0000-0000-0000-000000000015',
    30,
    5,
    'Current cancellation terms',
    true
  ),
  (
    '60000000-0000-0000-0000-000000000016',
    '60000000-0000-0000-0000-000000000010',
    'product',
    'Foreign catalogue product',
    'Foreign description',
    7000000000000001,
    'INR',
    '60000000-0000-0000-0000-000000000017',
    30,
    5,
    'Foreign cancellation terms',
    true
  );

insert into public.payments (
  id, tenant_id, member_id, amount_paise, currency, status, method,
  receipt_number, paid_at
) values
  (
    '60000000-0000-0000-0000-000000000018',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000012',
    9007199254740993,
    'INR',
    'paid',
    'cash',
    'MOBILE-MONEY-OWN-RECEIPT',
    now()
  ),
  (
    '60000000-0000-0000-0000-000000000019',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000013',
    7000000000000001,
    'INR',
    'paid',
    'cash',
    'MOBILE-MONEY-FOREIGN-RECEIPT',
    now()
  );

insert into public.addon_orders (
  id, tenant_id, member_id, addon_product_id, payment_id, status, quantity,
  unit_price_paise, total_paise, currency, sale_snapshot, sold_at
) values
  (
    '60000000-0000-0000-0000-000000000020',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000012',
    '60000000-0000-0000-0000-000000000014',
    '60000000-0000-0000-0000-000000000018',
    'completed',
    1,
    9007199254740993,
    9007199254740993,
    'INR',
    jsonb_build_object(
      'kind', 'product',
      'name', 'Frozen sold product',
      'description', 'Frozen sold description',
      'cancellationTerms', 'Frozen sold cancellation terms',
      'validityDays', 30,
      'trainerQualification', null
    ),
    now()
  ),
  (
    '60000000-0000-0000-0000-000000000021',
    '60000000-0000-0000-0000-000000000010',
    '60000000-0000-0000-0000-000000000013',
    '60000000-0000-0000-0000-000000000016',
    '60000000-0000-0000-0000-000000000019',
    'completed',
    1,
    7000000000000001,
    7000000000000001,
    'INR',
    jsonb_build_object(
      'kind', 'product',
      'name', 'Foreign frozen product',
      'description', 'Foreign frozen description',
      'cancellationTerms', 'Foreign cancellation terms',
      'validityDays', 30,
      'trainerQualification', null
    ),
    now()
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-0000-0000-000000000001',
    'role', 'authenticated',
    'tenant_id', '60000000-0000-0000-0000-000000000010',
    'app_role', 'member',
    'member_id', '60000000-0000-0000-0000-000000000012'
  )::text,
  true
);
set local role authenticated;

select lives_ok(
  $$ select public.read_member_mobile_money() $$,
  'complete member mobile money read runs against the addon_orders schema'
);

select ok(
  jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "MOBILE-MONEY-OWN-RECEIPT")'
  ),
  'member mobile money read includes the canonical own receipt'
);

select ok(
  jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "Frozen sold product")'
  ),
  'member mobile money read exposes the frozen sold add-on fact'
);

select ok(
  not jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "Renamed catalogue product")'
  ),
  'member mobile money read does not substitute a later catalogue rename for sold facts'
);

select ok(
  not jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "MOBILE-MONEY-FOREIGN-RECEIPT")'
  )
  and not jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "Foreign frozen product")'
  ),
  'member mobile money read excludes another member receipts and add-ons'
);

select ok(
  jsonb_path_exists(
    public.read_member_mobile_money(),
    '$.** ? (@.type() == "string" && @ == "9007199254740993")'
  ),
  'member mobile money read serializes bigint paise as canonical decimal text'
);

select * from finish();

ROLLBACK;
