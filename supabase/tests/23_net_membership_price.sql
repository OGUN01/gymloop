-- Visible contract tests for membership-net-price, authored implementation-blind.
-- No migrations, implementation source or holdout suite was read by this author.
-- Fixtures are private to this tenant; every write is rolled back (ADR-030).
-- Existing visible suites retain the detailed identity, RLS and lifecycle matrix.
begin;
set local role postgres;
set local search_path = extensions, public;
select plan(42);

insert into public.organizations (id, name, gym_code, timezone)
values ('23000000-0000-4000-8000-000000000001', 'Net Price Contract', 'NETP23', 'Asia/Kolkata');
insert into public.branches (id, tenant_id, name, is_default)
values ('23000000-0000-4000-8000-000000000011', '23000000-0000-4000-8000-000000000001', 'Main', true);
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('23000000-0000-4000-8000-000000000021', '23000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000011', 'front_desk', 'Net Price Desk'),
  ('23000000-0000-4000-8000-000000000022', '23000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000011', 'gym_owner', 'Net Price Owner');
insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency) values
  ('23000000-0000-4000-8000-000000000031', '23000000-0000-4000-8000-000000000001', 'Annual list price', 365, 1200000, 'INR'),
  ('23000000-0000-4000-8000-000000000032', '23000000-0000-4000-8000-000000000001', 'Monthly list price', 30, 100000, 'INR'),
  ('23000000-0000-4000-8000-000000000033', '23000000-0000-4000-8000-000000000001', 'Complimentary', 30, 0, 'INR'),
  ('23000000-0000-4000-8000-000000000034', '23000000-0000-4000-8000-000000000001', 'Cheaper correction', 7, 10000, 'INR');
create temp table net_today as
  select (now() at time zone timezone)::date as d from public.organizations where id = '23000000-0000-4000-8000-000000000001';
create temp table net_cases (
  n integer, label text, plan_n integer, state public.membership_status,
  start_offset integer, end_offset integer, price bigint, discount bigint
);
insert into net_cases values
  (1, 'Annual exact', 31, 'pending', null, null, 1200000, 120000),
  (2, 'One paisa boundary', 32, 'pending', null, null, 100000, 20000),
  (3, 'Many receipts and replay', 32, 'pending', -10, 500, 100000, 20000),
  (4, 'Foreign partial receipt', 32, 'pending', null, null, 100000, 20000),
  (5, 'Refunded partial receipt', 32, 'pending', null, null, 100000, 20000),
  (6, 'Reversed partial receipt', 32, 'pending', null, null, 100000, 20000),
  (7, 'Unpaid correction', 32, 'pending', null, null, 100000, 20000),
  (8, 'Paid partial receipt', 32, 'pending', null, null, 100000, 20000),
  (9, 'Cancelled', 32, 'cancelled', -30, 0, 100000, 20000),
  (10, 'Expired', 32, 'expired', -60, -30, 100000, 20000),
  (11, 'Fully discounted', 32, 'pending', null, null, 100000, 100000),
  (12, 'Zero list price', 33, 'pending', null, null, 0, 0),
  (13, 'Undiscounted control', 32, 'pending', null, null, 100000, 0),
  (14, 'Start only', 32, 'pending', -10, null, 100000, 20000),
  (15, 'End only', 32, 'pending', null, 5, 100000, 20000),
  (16, 'Future typed span', 32, 'pending', 7, 500, 100000, 20000);
insert into public.members (id, tenant_id, branch_id, full_name, phone)
select ('23000000-0000-4000-8000-' || lpad((40 + n)::text, 12, '0'))::uuid,
       '23000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000011', label, '+91230000' || lpad(n::text, 4, '0') from net_cases;
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency)
select ('23000000-0000-4000-8000-' || lpad((80 + n)::text, 12, '0'))::uuid, '23000000-0000-4000-8000-000000000001',
       ('23000000-0000-4000-8000-' || lpad((40 + n)::text, 12, '0'))::uuid,
       ('23000000-0000-4000-8000-' || lpad(plan_n::text, 12, '0'))::uuid, state,
       (select d from net_today) + start_offset, (select d from net_today) + end_offset,
       price, discount, 'INR' from net_cases;

-- The sold terms must survive later edits to the catalogue.
update public.plans set price_paise = 2400000, duration_days = 730 where id = '23000000-0000-4000-8000-000000000031';

-- 1
select results_eq(
  $$ select price_paise, discount_paise, duration_days from public.memberships where id = '23000000-0000-4000-8000-000000000081' $$,
  $$ select 1200000::bigint, 120000::bigint, 365 $$,
  'the annual membership keeps its recorded sold terms when its plan changes'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 2
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001001'::uuid, '23000000-0000-4000-8000-000000000081'::uuid, 1080000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001002'::uuid, '23000000-0000-4000-8000-000000000082'::uuid, 79999::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'the agreed annual price and a one-paisa-short monthly receipt are recorded');

set local role postgres;
set local role postgres;

-- 3
select results_eq(
  $$ select starts_on, ends_on, periods_granted, status::text from public.memberships where id = '23000000-0000-4000-8000-000000000081' $$,
  $$ select (select d from net_today), (select d from net_today) + 365, 1, 'active'::text $$,
  '12000 less 1200 buys exactly one sold year, using neither the old gross price nor the changed plan'
);

-- 4
select results_eq(
  $$ select starts_on, ends_on, periods_granted, status::text from public.memberships where id = '23000000-0000-4000-8000-000000000082' $$,
  $$ select null::date, null::date, 0, 'pending'::text $$,
  'one paisa below the positive net price grants nothing and changes neither date'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 5
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001003'::uuid, '23000000-0000-4000-8000-000000000082'::uuid, 1::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'the final paisa of the net price is received');

set local role postgres;
set local role postgres;

-- 6
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships where id = '23000000-0000-4000-8000-000000000082' $$,
  $$ select (select d from net_today), (select d from net_today) + 30, 1 $$,
  'two unequal receipts crossing exactly one net price buy exactly one period'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 7
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001004'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001005'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001006'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 79999::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'three receipts in one statement total one paisa below three net periods');

set local role postgres;
set local role postgres;

-- 8
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships where id = '23000000-0000-4000-8000-000000000083' $$,
  $$ select (select d from net_today), (select d from net_today) + 60, 2 $$,
  'integer division grants only two periods and replaces the unpaid typed span on the first grant'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 9
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001007'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 1::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'one additional paisa completes the third period');

-- 10
select lives_ok($$
  update public.payments set status = status, notes = 'replayed paid event' where id in ('23000000-0000-4000-8000-000000001004', '23000000-0000-4000-8000-000000001005', '23000000-0000-4000-8000-000000001006', '23000000-0000-4000-8000-000000001007')
$$, 'replaying already-paid receipt rows remains an ordinary no-op on payment status');

set local role postgres;
set local role postgres;

-- 11
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships where id = '23000000-0000-4000-8000-000000000083' $$,
  $$ select (select d from net_today), (select d from net_today) + 90, 3 $$,
  'the third net multiple extends once, and paid replay buys no duplicate time'
);

-- 12
select lives_ok($$
  update public.payments set status = 'refunded' where id = '23000000-0000-4000-8000-000000001004';
  update public.payments set status = 'reversed' where id = '23000000-0000-4000-8000-000000001005';
$$, 'received receipts can enter refunded and reversed states under the existing transition rules');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 13
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001008'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 79999::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'a new receipt after refund and reversal stops one paisa short of the fourth net period');

set local role postgres;
set local role postgres;

-- 14
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships where id = '23000000-0000-4000-8000-000000000083' $$,
  $$ select (select d from net_today), (select d from net_today) + 90, 3 $$,
  'refund and reversal neither erase earned periods nor let partial new money buy an extra one'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 15
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001009'::uuid, '23000000-0000-4000-8000-000000000083'::uuid, 1::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'the last paisa completes a fourth period after refunded and reversed receipts');

set local role postgres;
set local role postgres;

-- 16
select results_eq(
  $$ select starts_on, ends_on, periods_granted from public.memberships where id = '23000000-0000-4000-8000-000000000083' $$,
  $$ select (select d from net_today), (select d from net_today) + 120, 4 $$,
  'all received statuses still count, already granted periods are deducted, and renewal preserves the start'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 17
select lives_ok($$
  insert into public.payments (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id)
  select v.payment_id, m.tenant_id, m.member_id, m.id, v.amount, v.currency, 'paid', 'cash', '23000000-0000-4000-8000-000000000021'::uuid
    from (values ('23000000-0000-4000-8000-000000001010'::uuid, '23000000-0000-4000-8000-000000000084'::uuid, 160000::bigint, 'USD'::text),
                 ('23000000-0000-4000-8000-000000001011'::uuid, '23000000-0000-4000-8000-000000000085'::uuid, 1::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001012'::uuid, '23000000-0000-4000-8000-000000000086'::uuid, 1::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001013'::uuid, '23000000-0000-4000-8000-000000000088'::uuid, 1::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001014'::uuid, '23000000-0000-4000-8000-000000000089'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001015'::uuid, '23000000-0000-4000-8000-000000000090'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001016'::uuid, '23000000-0000-4000-8000-000000000091'::uuid, 100000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001017'::uuid, '23000000-0000-4000-8000-000000000092'::uuid, 100000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001018'::uuid, '23000000-0000-4000-8000-000000000093'::uuid, 100000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001019'::uuid, '23000000-0000-4000-8000-000000000094'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001020'::uuid, '23000000-0000-4000-8000-000000000095'::uuid, 80000::bigint, 'INR'::text),
                 ('23000000-0000-4000-8000-000000001021'::uuid, '23000000-0000-4000-8000-000000000096'::uuid, 80000::bigint, 'INR'::text)) as v(payment_id, membership_id, amount, currency)
    join public.memberships m on m.id = v.membership_id
$$, 'foreign, partial, retired, complimentary, undiscounted and half-dated payments are recorded without division errors');

set local role postgres;
set local role postgres;

-- 18
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted, status::text from public.memberships where id in ('23000000-0000-4000-8000-000000000084','23000000-0000-4000-8000-000000000089','23000000-0000-4000-8000-000000000090','23000000-0000-4000-8000-000000000091','23000000-0000-4000-8000-000000000092','23000000-0000-4000-8000-000000000094','23000000-0000-4000-8000-000000000095') order by id $$,
  $$ values
    ('23000000-0000-4000-8000-000000000084'::uuid, null::date, null::date, 0, 'pending'::text),
    ('23000000-0000-4000-8000-000000000089'::uuid, (select d from net_today) - 30, (select d from net_today), 0, 'cancelled'::text),
    ('23000000-0000-4000-8000-000000000090'::uuid, (select d from net_today) - 60, (select d from net_today) - 30, 0, 'expired'::text),
    ('23000000-0000-4000-8000-000000000091'::uuid, null::date, null::date, 0, 'pending'::text),
    ('23000000-0000-4000-8000-000000000092'::uuid, null::date, null::date, 0, 'pending'::text),
    ('23000000-0000-4000-8000-000000000094'::uuid, (select d from net_today) - 10, null::date, 0, 'pending'::text),
    ('23000000-0000-4000-8000-000000000095'::uuid, null::date, (select d from net_today) + 35, 1, 'pending'::text) $$,
  'currency, retired and complimentary guards and the two half-dated boundaries retain their existing behavior'
);

-- 19
select results_eq(
  $$ select id, starts_on, ends_on, periods_granted from public.memberships where id in ('23000000-0000-4000-8000-000000000093','23000000-0000-4000-8000-000000000096') order by id $$,
  $$ values ('23000000-0000-4000-8000-000000000093'::uuid, (select d from net_today), (select d from net_today) + 30, 1),
    ('23000000-0000-4000-8000-000000000096'::uuid, (select d from net_today) + 7, (select d from net_today) + 37, 1) $$,
  'zero discount still buys the list-price period and a future sold start survives its first net-price grant'
);

update public.payments set status = 'refunded' where id = '23000000-0000-4000-8000-000000001011';
update public.payments set status = 'reversed' where id = '23000000-0000-4000-8000-000000001012';

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 20
select throws_ok($$
  update public.memberships set discount_paise = 20001 where id = '23000000-0000-4000-8000-000000000088'
$$, 'GL043'::char(5), null, 'a gym admin cannot change the discount after one paisa, before any whole period was earned');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 21
select throws_ok($$
  update public.memberships set discount_paise = 20001 where id = '23000000-0000-4000-8000-000000000088'
$$, 'GL043'::char(5), null, 'the absolute received-money freeze answers before the desk pricing permission rule');

set local role postgres;
set local role service_role;

-- 22
select throws_ok($$
  update public.memberships set discount_paise = 20001 where id = '23000000-0000-4000-8000-000000000084'
$$, 'GL043'::char(5), null, 'a trusted service writer cannot change the discount after money in a foreign currency');

set local role postgres;
set local role postgres;

-- 23
select throws_ok($$
  update public.memberships set discount_paise = 20001 where id = '23000000-0000-4000-8000-000000000085'
$$, 'GL043'::char(5), null, 'postgres cannot thaw a discount because the partial receipt was refunded');

-- 24
select throws_ok($$
  update public.memberships set discount_paise = 20001 where id = '23000000-0000-4000-8000-000000000086'
$$, 'GL043'::char(5), null, 'postgres cannot thaw a discount because the partial receipt was reversed');

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 25
select lives_ok($$
  update public.memberships set discount_paise = discount_paise where id in ('23000000-0000-4000-8000-000000000084','23000000-0000-4000-8000-000000000085','23000000-0000-4000-8000-000000000086','23000000-0000-4000-8000-000000000088')
$$, 'writing the same discount leaves the paid terms intact and is allowed');

set local role postgres;
set local role postgres;

-- 26
select results_eq(
  $$ select id, discount_paise, periods_granted from public.memberships where id in ('23000000-0000-4000-8000-000000000084','23000000-0000-4000-8000-000000000085','23000000-0000-4000-8000-000000000086','23000000-0000-4000-8000-000000000088') order by id $$,
  $$ values ('23000000-0000-4000-8000-000000000084'::uuid, 20000::bigint, 0), ('23000000-0000-4000-8000-000000000085'::uuid, 20000::bigint, 0), ('23000000-0000-4000-8000-000000000086'::uuid, 20000::bigint, 0), ('23000000-0000-4000-8000-000000000088'::uuid, 20000::bigint, 0) $$,
  'every rejected paid-term edit leaves the discount and zero period count unchanged'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 27
select lives_ok($$
  update public.memberships set discount_paise = 15000 where id = '23000000-0000-4000-8000-000000000087'
$$, 'an authorized unpaid discount remains editable');

-- 28
select throws_ok($$
  update public.memberships set discount_paise = -1 where id = '23000000-0000-4000-8000-000000000087'
$$, '23514'::char(5), null, 'a negative discount fails the database CHECK');

-- 29
select throws_ok($$
  update public.memberships set discount_paise = 100001 where id = '23000000-0000-4000-8000-000000000087'
$$, '23514'::char(5), null, 'a discount one paisa above the listed price fails the database CHECK');

set local role postgres;
set local role postgres;

-- 30
select results_eq(
  $$ select price_paise, discount_paise from public.memberships where id = '23000000-0000-4000-8000-000000000087' $$,
  $$ select 100000::bigint, 15000::bigint $$,
  'the valid unpaid edit lands and both out-of-bounds updates leave its terms unchanged'
);

-- 31
select throws_ok($$
  insert into public.memberships (id, tenant_id, member_id, plan_id, status, price_paise, discount_paise)
  values ('23000000-0000-4000-8000-000000000200', '23000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000047', '23000000-0000-4000-8000-000000000032', 'pending', 100000, 100001)
$$, '23514'::char(5), null, 'even a trusted INSERT cannot create a negative net price');

-- 32
select results_eq(
  $$ select count(*)::integer from public.memberships where id = '23000000-0000-4000-8000-000000000200' $$,
  $$ select 0 $$,
  'the invalid insert leaves no membership'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 33
select throws_ok($$
  update public.memberships set plan_id = '23000000-0000-4000-8000-000000000034' where id = '23000000-0000-4000-8000-000000000087'
$$, '23514'::char(5), null, 'an unpaid plan correction cannot preserve a discount above the resulting plan price');

set local role postgres;
set local role postgres;

-- 34
select results_eq(
  $$ select plan_id, price_paise, discount_paise, duration_days from public.memberships where id = '23000000-0000-4000-8000-000000000087' $$,
  $$ select '23000000-0000-4000-8000-000000000032'::uuid, 100000::bigint, 15000::bigint, 30 $$,
  'the invalid correction is atomic and never silently reduces the discount'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 35
select lives_ok($$
  update public.memberships set plan_id = '23000000-0000-4000-8000-000000000034', discount_paise = 5000 where id = '23000000-0000-4000-8000-000000000087'
$$, 'the same authorized plan correction succeeds when it supplies a valid discount');

set local role postgres;
set local role postgres;

-- 36
select results_eq(
  $$ select plan_id, price_paise, discount_paise, duration_days from public.memberships where id = '23000000-0000-4000-8000-000000000087' $$,
  $$ select '23000000-0000-4000-8000-000000000034'::uuid, 10000::bigint, 5000::bigint, 7 $$,
  'correcting the plan derives its sold price and duration while preserving the explicitly valid discount'
);

insert into public.coupons (id, tenant_id, code, percent_bp)
values ('23000000-0000-4000-8000-000000000071', '23000000-0000-4000-8000-000000000001', 'NET23COUPON', 1000);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"gym_owner","staff_id":"23000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- 37
select lives_ok($$
  update public.memberships set coupon_id = '23000000-0000-4000-8000-000000000071' where id = '23000000-0000-4000-8000-000000000081'
$$, 'a gym admin can edit a coupon identifier even when the discount is frozen by received money');

set local role postgres;
set local role postgres;

-- 38
select results_eq(
  $$ select coupon_id, price_paise, discount_paise, periods_granted, starts_on, ends_on from public.memberships where id = '23000000-0000-4000-8000-000000000081' $$,
  $$ select '23000000-0000-4000-8000-000000000071'::uuid, 1200000::bigint, 120000::bigint, 1, (select d from net_today), (select d from net_today) + 365 $$,
  'the coupon identifier changes neither the agreed amount nor the already granted year'
);

set local role postgres;
select set_config('request.jwt.claims', '{"sub":"23000000-0000-4000-8000-000000000901","role":"authenticated","tenant_id":"23000000-0000-4000-8000-000000000001","app_role":"front_desk","staff_id":"23000000-0000-4000-8000-000000000021"}', true);
set local role authenticated;

-- 39
select throws_ok($$
  update public.memberships set coupon_id = null where id = '23000000-0000-4000-8000-000000000081'
$$, 'GL046'::char(5), null, 'the coupon identifier retains the gym-admin edit policy');

-- 40
select throws_ok($$
  update public.memberships set discount_paise = 4999 where id = '23000000-0000-4000-8000-000000000087'
$$, 'GL046'::char(5), null, 'front desk still cannot choose even a valid discount on an unpaid membership');

set local role postgres;
set local role postgres;

-- 41
select results_eq(
  $$ select coupon_id from public.memberships where id = '23000000-0000-4000-8000-000000000081' $$,
  $$ select '23000000-0000-4000-8000-000000000071'::uuid $$,
  'the refused desk coupon edit leaves the identifier in place'
);

-- 42
select results_eq(
  $$ select periods_granted, starts_on, ends_on, status::text, price_paise, discount_paise, duration_days, currency from public.memberships where id = '00000006-0000-4000-8000-000000000004' $$,
  $$ select 1, date '2025-09-12', date '2026-09-12', 'active'::text, 1200000::bigint, 120000::bigint, 365, 'INR'::text
    where exists (select 1 from public.memberships where id = '00000006-0000-4000-8000-000000000004') $$,
  'when present, the inspected demo year is counted once with its historical dates and sold terms preserved; missing demo data requires no insert'
);

select * from finish();
rollback;

