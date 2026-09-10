-- Independent holdout derived from membership-net-price/spec.md at 5b041e9,
-- membership-creation and payment-record specs, generated schema types, and
-- this directory's fixtures. No implementation, migration or visible test read.
-- Temporary helpers only compose fixtures or expose SQLSTATE/row observations;
-- every assertion is a top-level TAP result. All writes are rolled back.
begin;
set local role postgres;
select plan(100);

create function pg_temp.h23_id(bucket integer, n integer) returns uuid
language sql immutable as $$
  select ('230000ff-0023-4000-8000-' || bucket::text || lpad(n::text, 11, '0'))::uuid
$$;
create function pg_temp.h23_exec(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return '00000';
exception when others then
  return sqlstate;
end
$$;
create function pg_temp.h23_shape(n integer) returns text
language sql stable as $$
  select concat_ws('/', periods_granted,
      coalesce((starts_on - (now() at time zone 'Asia/Kolkata')::date)::text, 'NULL'),
      coalesce((ends_on - (now() at time zone 'Asia/Kolkata')::date)::text, 'NULL'), status)
  from public.memberships where id = pg_temp.h23_id(6, n)
$$;
create function pg_temp.h23_pay(n integer, receipt integer, amount bigint,
    denomination text default 'INR', state public.payment_status default 'paid')
returns void language sql as $$
  insert into public.payments
    (id, tenant_id, member_id, membership_id, amount_paise, currency,
     method, status, recorded_by_staff_id, idempotency_key)
  values (pg_temp.h23_id(7, receipt), pg_temp.h23_id(1, 1),
    pg_temp.h23_id(5, n), pg_temp.h23_id(6, n), amount, denomination,
    'cash', state, pg_temp.h23_id(3, 1), 'h23-receipt-' || receipt::text)
$$;
grant execute on function pg_temp.h23_id(integer, integer),
  pg_temp.h23_exec(text), pg_temp.h23_shape(integer),
  pg_temp.h23_pay(integer, integer, bigint, text, public.payment_status) to public;

insert into public.organizations(id, name, gym_code, timezone) values
  (pg_temp.h23_id(1, 1), 'H23 Net Price A', 'H23NPA', 'Asia/Kolkata'),
  (pg_temp.h23_id(1, 2), 'H23 Net Price B', 'H23NPB', 'Asia/Kolkata');
insert into public.branches(id, tenant_id, name, is_default)
select pg_temp.h23_id(2, n), pg_temp.h23_id(1, n), 'Main', true
from generate_series(1, 2) n;
insert into public.staff(id, tenant_id, branch_id, role, full_name) values
  (pg_temp.h23_id(3, 1), pg_temp.h23_id(1, 1), pg_temp.h23_id(2, 1), 'front_desk', 'H23 Desk'),
  (pg_temp.h23_id(3, 2), pg_temp.h23_id(1, 1), pg_temp.h23_id(2, 1), 'gym_manager', 'H23 Manager'),
  (pg_temp.h23_id(3, 3), pg_temp.h23_id(1, 1), pg_temp.h23_id(2, 1), 'gym_owner', 'H23 Owner');
insert into public.plans(id, tenant_id, name, duration_days, price_paise) values
  (pg_temp.h23_id(4, 1), pg_temp.h23_id(1, 1), 'Annual', 365, 1200000),
  (pg_temp.h23_id(4, 2), pg_temp.h23_id(1, 1), 'Odd Paise', 37, 11003),
  (pg_temp.h23_id(4, 3), pg_temp.h23_id(1, 1), 'Short Correction', 11, 500),
  (pg_temp.h23_id(4, 4), pg_temp.h23_id(1, 2), 'Other Gym', 37, 11003);
insert into public.members(id, tenant_id, branch_id, full_name, phone)
select pg_temp.h23_id(5, n), pg_temp.h23_id(1, case when n = 24 then 2 else 1 end),
  pg_temp.h23_id(2, case when n = 24 then 2 else 1 end), 'H23 Member ' || n,
  '+91923000' || lpad(n::text, 4, '0') from generate_series(1, 26) n;
insert into public.memberships(id, tenant_id, member_id, plan_id, status,
    starts_on, ends_on, price_paise, discount_paise, currency)
select pg_temp.h23_id(6, n), pg_temp.h23_id(1, case when n = 24 then 2 else 1 end),
  pg_temp.h23_id(5, n), pg_temp.h23_id(4, case when n = 1 then 1 when n = 24 then 4 else 2 end),
  (case when n = 7 then 'cancelled' when n = 8 then 'expired' else 'pending' end)::public.membership_status,
  case when n in (4, 18, 19) then null
       when n in (7, 8) then (now() at time zone 'Asia/Kolkata')::date - 80
       when n = 22 then (now() at time zone 'Asia/Kolkata')::date + 9
       else (now() at time zone 'Asia/Kolkata')::date end,
  case when n in (4, 17, 19) then null
       when n in (7, 8) then (now() at time zone 'Asia/Kolkata')::date - 1
       when n = 22 then (now() at time zone 'Asia/Kolkata')::date + 10
       else (now() at time zone 'Asia/Kolkata')::date + 2 end,
  case when n = 1 then 1200000 else 11003 end,
  case when n = 1 then 120000 when n = 4 then 11003 when n = 21 then 11002 else 1004 end,
  'INR'
from generate_series(1, 24) n;
insert into public.coupons(id, tenant_id, code, percent_bp) values
  (pg_temp.h23_id(8, 1), pg_temp.h23_id(1, 1), 'H23HALF', 5000),
  (pg_temp.h23_id(8, 2), pg_temp.h23_id(1, 1), 'H23TENTH', 1000);

-- Real front-office receipts against independently negotiated fixture terms.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated',
  'sub', gen_random_uuid(), 'tenant_id', pg_temp.h23_id(1, 1),
  'app_role', 'front_desk', 'staff_id', pg_temp.h23_id(3, 1))::text, true);
set local role authenticated;
select lives_ok($$select pg_temp.h23_pay(1, 1, 1080000)$$,
  'H23 annual: net amount is received');
select is(pg_temp.h23_shape(1), '1/0/365/active',
  'H23 annual: one net fee sets exactly the sold year');
select lives_ok($$select pg_temp.h23_pay(2, 2, 9998)$$,
  'H23 partial: one paisa short is received');
select is(pg_temp.h23_shape(2), '0/0/2/pending',
  'H23 partial: no rounding up or date movement below net');
select lives_ok($$select pg_temp.h23_pay(2, 3, 1)$$,
  'H23 partial: final paisa is received');
select is(pg_temp.h23_shape(2), '1/0/37/active',
  'H23 partial: exact cumulative net grants once');
select lives_ok($$select pg_temp.h23_pay(2, 4, 9998)$$,
  'H23 renewal: next incomplete fee is received');
select is(pg_temp.h23_shape(2), '1/0/37/active',
  'H23 renewal: old money does not round the next period up');
select lives_ok($$select pg_temp.h23_pay(2, 5, 1)$$,
  'H23 renewal: next final paisa is received');
select is(pg_temp.h23_shape(2), '2/0/74/active',
  'H23 renewal: the second net fee extends only one sold period');
select lives_ok($$insert into public.payments
    (id, tenant_id, member_id, membership_id, amount_paise, method, status, recorded_by_staff_id)
  select pg_temp.h23_id(7, 100 + n), pg_temp.h23_id(1, 1), pg_temp.h23_id(5, 3),
    pg_temp.h23_id(6, 3), 3333, 'cash', 'paid', pg_temp.h23_id(3, 1)
  from generate_series(1, 6) n$$,
  'H23 batch: six third-period receipts in one statement');
select is(pg_temp.h23_shape(3), '2/0/74/active',
  'H23 batch: statement earns two periods, not six copies of total');
select lives_ok($$update public.payments set status = status, notes = 'replayed'
  where membership_id = pg_temp.h23_id(6, 3)$$,
  'H23 replay: batch paid status replay is harmless');
select is(pg_temp.h23_shape(3), '2/0/74/active',
  'H23 replay: batch replay grants no time');
select is(pg_temp.h23_exec($$select pg_temp.h23_pay(2, 5, 1)$$), '23505',
  'H23 replay: repeated receipt identity is rejected');
select is(pg_temp.h23_shape(2), '2/0/74/active',
  'H23 replay: duplicate receipt leaves paid time intact');
select lives_ok($$select pg_temp.h23_pay(4, 6, 11003)$$,
  'H23 zero: fully discounted membership accepts a receipted payment without division error');
select is(pg_temp.h23_shape(4), '0/NULL/NULL/pending',
  'H23 zero: no payment-driven activation, dates or periods');
select lives_ok($$select pg_temp.h23_pay(5, 7, 999900, 'USD')$$,
  'H23 currency: foreign receipt is still recorded');
select is(pg_temp.h23_shape(5), '0/0/2/pending',
  'H23 currency: foreign money buys no net periods');
select lives_ok($$select pg_temp.h23_pay(5, 8, 9998)$$,
  'H23 currency: near-full domestic fee is received');
select is(pg_temp.h23_shape(5), '0/0/2/pending',
  'H23 currency: foreign surplus cannot cover domestic one-paisa shortage');
select lives_ok($$select pg_temp.h23_pay(5, 9, 1)$$,
  'H23 currency: domestic fee is completed');
select is(pg_temp.h23_shape(5), '1/0/37/active',
  'H23 currency: only domestic net total scores');
select lives_ok($$select pg_temp.h23_pay(6, 10, 4000)$$,
  'H23 refund: first partial receipt lands');
select lives_ok($$update public.payments set status = 'refunded' where id = pg_temp.h23_id(7, 10)$$,
  'H23 refund: received partial moves to refunded');
select lives_ok($$select pg_temp.h23_pay(6, 11, 5999)$$,
  'H23 refund: complement arrives after refund');
select is(pg_temp.h23_shape(6), '1/0/37/active',
  'H23 refund: received refunded history still completes exactly one net period');
select lives_ok($$update public.payments set status = 'reversed' where id = pg_temp.h23_id(7, 11)$$,
  'H23 reversal: second received partial is reversed');
select lives_ok($$select pg_temp.h23_pay(6, 12, 9998)$$,
  'H23 reversal: new almost-full fee is recorded');
select is(pg_temp.h23_shape(6), '1/0/37/active',
  'H23 reversal: previously consumed refunded and reversed money grants nothing twice');
select lives_ok($$select pg_temp.h23_pay(6, 13, 1)$$,
  'H23 reversal: new fee is completed');
select is(pg_temp.h23_shape(6), '2/0/74/active',
  'H23 reversal: exactly the newly completed net period is added');
select lives_ok($$select pg_temp.h23_pay(7, 14, 999900)$$,
  'H23 cancelled: substantial receipt remains recordable');
select is(pg_temp.h23_shape(7), '0/-80/-1/cancelled',
  'H23 cancelled: no discounted time is granted');
select lives_ok($$select pg_temp.h23_pay(8, 15, 999900)$$,
  'H23 expired: substantial receipt remains recordable');
select is(pg_temp.h23_shape(8), '0/-80/-1/expired',
  'H23 expired: no discounted time is granted');
select lives_ok($$select pg_temp.h23_pay(17, 16, 9999)$$,
  'H23 half-start: full net fee is receipted');
select is(pg_temp.h23_shape(17), '0/0/NULL/pending',
  'H23 half-start: existing open-ended boundary is preserved');
select lives_ok($$select pg_temp.h23_pay(18, 17, 9999)$$,
  'H23 half-end: full net fee is receipted');
select is(pg_temp.h23_shape(18), '1/NULL/39/pending',
  'H23 half-end: existing extension-only boundary is preserved');
select lives_ok($$select pg_temp.h23_pay(19, 18, 9999)$$,
  'H23 dateless: full net fee is receipted');
select is(pg_temp.h23_shape(19), '1/0/37/active',
  'H23 dateless: full net fee grants the ordinary first period');
select lives_ok($$select pg_temp.h23_pay(21, 19, 3)$$,
  'H23 one-paisa: three net fees arrive together');
select is(pg_temp.h23_shape(21), '3/0/111/active',
  'H23 one-paisa: positive net boundary remains exact');
select lives_ok($$select pg_temp.h23_pay(22, 20, 19998)$$,
  'H23 future: two complete net fees are received');
select is(pg_temp.h23_shape(22), '2/9/83/active',
  'H23 future: future agreed start survives first multiple grant');

-- A not-yet-received attempt must not freeze an admin correction.
select lives_ok($$select pg_temp.h23_pay(9, 21, 1, 'INR', 'created')$$,
  'H23 unreceived: created attempt is recorded');
select lives_ok($$select pg_temp.h23_pay(9, 22, 1, 'INR', 'pending')$$,
  'H23 unreceived: pending attempt is recorded');
select lives_ok($$select pg_temp.h23_pay(9, 23, 1, 'INR', 'failed')$$,
  'H23 unreceived: failed attempt is recorded');
select lives_ok($$select pg_temp.h23_pay(12, 24, 1)$$,
  'H23 coupon: part-paid coupon fixture is recorded');
select lives_ok($$select pg_temp.h23_pay(13, 25, 1)$$,
  'H23 trusted: part-paid freeze fixture is recorded');
select lives_ok($$select pg_temp.h23_pay(14, 26, 1, 'USD')$$,
  'H23 freeze-any-currency: foreign part payment is recorded');
select lives_ok($$select pg_temp.h23_pay(15, 27, 1)$$,
  'H23 freeze-refunded: part payment is recorded');
select lives_ok($$update public.payments set status = 'refunded' where id = pg_temp.h23_id(7, 27)$$,
  'H23 freeze-refunded: received money moves to refunded');
select lives_ok($$select pg_temp.h23_pay(16, 28, 1, 'USD')$$,
  'H23 freeze-reversed: foreign part payment is recorded');
select lives_ok($$update public.payments set status = 'reversed' where id = pg_temp.h23_id(7, 28)$$,
  'H23 freeze-reversed: received foreign money moves to reversed');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 10)$$), 'GL046',
  'H23 permissions: unpaid discount remains gym-admin work');
select is(pg_temp.h23_exec($$update public.memberships set coupon_id = pg_temp.h23_id(8, 1)
  where id = pg_temp.h23_id(6, 12)$$), 'GL046',
  'H23 permissions: coupon-only paid-row edit remains gym-admin work');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 13)$$), 'GL043',
  'H23 refusal order: paid-term invariant precedes desk pricing permission');
select is(pg_temp.h23_exec($$update public.memberships set member_id = pg_temp.h23_id(5, 25),
  discount_paise = 1005 where id = pg_temp.h23_id(6, 13)$$), 'GL042',
  'H23 refusal order: membership identity precedes changed paid discount');

select set_config('request.jwt.claims', json_build_object('role', 'authenticated',
  'sub', gen_random_uuid(), 'tenant_id', pg_temp.h23_id(1, 1),
  'app_role', 'gym_manager', 'staff_id', pg_temp.h23_id(3, 2))::text, true);
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 9)$$), '00000',
  'H23 unreceived: attempts do not freeze changed discount');
select is((select discount_paise from public.memberships where id = pg_temp.h23_id(6, 9)),
  1005::bigint, 'H23 unreceived: corrected discount persists');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 0
  where id = pg_temp.h23_id(6, 13)$$), 'GL043',
  'H23 paid freeze: decreasing discount cannot increase the agreed paid price');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 11003
  where id = pg_temp.h23_id(6, 14)$$), 'GL043',
  'H23 paid freeze: any-currency receipt freezes even a change to free');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 15)$$), 'GL043',
  'H23 paid freeze: refund cannot thaw discount');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 16)$$), 'GL043',
  'H23 paid freeze: foreign reversal cannot thaw discount');
select is((select count(*)::integer from public.memberships
  where id in (pg_temp.h23_id(6, 13), pg_temp.h23_id(6, 14), pg_temp.h23_id(6, 15), pg_temp.h23_id(6, 16))
    and discount_paise = 1004 and periods_granted = 0), 4,
  'H23 paid freeze: all sub-period refusals leave the sold amounts and count intact');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = discount_paise,
  price_paise = price_paise, cancel_reason = 'same paid terms confirmed'
  where id = pg_temp.h23_id(6, 13)$$), '00000',
  'H23 same values: ordinary paid record save remains allowed');
select is(pg_temp.h23_exec($$update public.memberships set coupon_id = pg_temp.h23_id(8, 1)
  where id = pg_temp.h23_id(6, 12)$$), '00000',
  'H23 coupon: manager may attach only its identifier after part payment');
select is((select price_paise::text || '/' || discount_paise::text || '/' || periods_granted::text
  from public.memberships where id = pg_temp.h23_id(6, 12)), '11003/1004/0',
  'H23 coupon: percentage metadata calculates no discount and grants no time');
select is(pg_temp.h23_exec($$update public.memberships set coupon_id = null
  where id = pg_temp.h23_id(6, 12)$$), '00000',
  'H23 coupon: manager may remove identifier without repricing');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = -1
  where id = pg_temp.h23_id(6, 20)$$), '23514',
  'H23 bounds: negative discount update is a database CHECK refusal');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 11004
  where id = pg_temp.h23_id(6, 20)$$), '23514',
  'H23 bounds: one above gross update is a database CHECK refusal');
select is((select discount_paise from public.memberships where id = pg_temp.h23_id(6, 20)),
  1004::bigint, 'H23 bounds: rejected updates preserve discount');
select is(pg_temp.h23_exec($$insert into public.memberships
    (id, tenant_id, member_id, plan_id, price_paise, discount_paise)
  values (pg_temp.h23_id(6, 25), pg_temp.h23_id(1, 1), pg_temp.h23_id(5, 25),
    pg_temp.h23_id(4, 2), 11003, -1)$$), '23514',
  'H23 bounds: negative discount insert is refused');
select is(pg_temp.h23_exec($$insert into public.memberships
    (id, tenant_id, member_id, plan_id, price_paise, discount_paise)
  values (pg_temp.h23_id(6, 25), pg_temp.h23_id(1, 1), pg_temp.h23_id(5, 25),
    pg_temp.h23_id(4, 2), 11003, 11004)$$), '23514',
  'H23 bounds: over-price discount insert is refused');
select is((select count(*)::integer from public.memberships where id = pg_temp.h23_id(6, 25)),
  0, 'H23 bounds: invalid insert leaves no row');
select is(pg_temp.h23_exec($$update public.memberships set price_paise = 1003
  where id = pg_temp.h23_id(6, 20)$$), '23514',
  'H23 bounds: changing only gross cannot strand a larger discount');
select is(pg_temp.h23_exec($$update public.memberships set plan_id = pg_temp.h23_id(4, 3)
  where id = pg_temp.h23_id(6, 11)$$), '23514',
  'H23 correction: derived cheaper list price cannot silently clamp discount');
select is((select price_paise::text || '/' || discount_paise::text || '/' || duration_days::text
  from public.memberships where id = pg_temp.h23_id(6, 11)), '11003/1004/37',
  'H23 correction: rejected plan correction preserves all sold terms');
select is(pg_temp.h23_exec($$update public.memberships set plan_id = pg_temp.h23_id(4, 3),
  discount_paise = 499 where id = pg_temp.h23_id(6, 11)$$), '00000',
  'H23 correction: valid discount supplied with cheaper plan is allowed');
select is((select price_paise::text || '/' || discount_paise::text || '/' || duration_days::text
  from public.memberships where id = pg_temp.h23_id(6, 11)), '500/499/11',
  'H23 correction: explicitly negotiated one-paisa net survives derivation');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 0
  where id = pg_temp.h23_id(6, 20)$$), '00000',
  'H23 bounds: zero discount is valid');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = price_paise
  where id = pg_temp.h23_id(6, 20)$$), '00000',
  'H23 bounds: exactly full discount is valid');
select is((select price_paise - discount_paise from public.memberships where id = pg_temp.h23_id(6, 20)),
  0::bigint, 'H23 bounds: full discount stores zero agreed amount');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1
  where id = pg_temp.h23_id(6, 24)$$), '00000',
  'H23 RLS: wrong-tenant update sees no row and raises no term oracle');
select is((select count(*)::integer from public.memberships where id = pg_temp.h23_id(6, 24)),
  0, 'H23 RLS: foreign discounted membership is unreadable');

-- Trusted calls still obey arithmetic, CHECKs and already-received terms.
set local role postgres;
select set_config('request.jwt.claims', '', true);
set local role service_role;
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 13)$$), 'GL043',
  'H23 trusted: service-role part-paid discount cannot change');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = -1
  where id = pg_temp.h23_id(6, 10)$$), '23514',
  'H23 trusted: service-role negative discount is checked');
select lives_ok($$select pg_temp.h23_pay(23, 29, 9999)$$,
  'H23 trusted: service-role receipt grants the same net fee');
select is(pg_temp.h23_shape(23), '1/0/37/active',
  'H23 trusted: service-role receipt buys one sold period');
set local role postgres;
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 1005
  where id = pg_temp.h23_id(6, 16)$$), 'GL043',
  'H23 trusted: claimless owner cannot change foreign reversed paid terms');
select is((select discount_paise from public.memberships where id = pg_temp.h23_id(6, 24)),
  1004::bigint, 'H23 RLS: privileged inspection confirms foreign row stayed unchanged');
select lives_ok($$update public.plans set price_paise = 22006, duration_days = 91
  where id = pg_temp.h23_id(4, 2)$$,
  'H23 sold snapshot: plan catalogue can be repriced and relengthened');
select lives_ok($$select pg_temp.h23_pay(23, 30, 9999)$$,
  'H23 sold snapshot: renewal still accepts old sold net fee');
select is(pg_temp.h23_shape(23), '2/0/74/active',
  'H23 sold snapshot: current catalogue cannot reprice or relengthen sold periods');
select is(pg_temp.h23_exec($$update public.memberships set discount_paise = 11004
  where id = pg_temp.h23_id(6, 10)$$), '23514',
  'H23 trusted: claimless owner cannot insert negative net via update');
select is((select discount_paise from public.memberships where id = pg_temp.h23_id(6, 13)),
  1004::bigint, 'H23 trusted: all paid-row refusals preserve recorded discount');

-- Missing demo data is allowed; an existing known historical row must already
-- be reconciled by deployment, without buying another year at today's date.
select ok(not exists (select 1 from public.memberships
    where id = '00000006-0000-4000-8000-000000000004')
  or exists (select 1 from public.memberships m
    where m.id = '00000006-0000-4000-8000-000000000004'
      and m.periods_granted = 1 and m.status = 'active'
      and m.starts_on = date '2025-09-12' and m.ends_on = date '2026-09-12'
      and m.price_paise = 1200000 and m.discount_paise = 120000
      and m.currency = 'INR' and m.duration_days = 365
      and (select sum(p.amount_paise) from public.payments p
        where p.tenant_id = m.tenant_id and p.membership_id = m.id
          and p.member_id = m.member_id and p.currency = m.currency
          and p.status in ('paid', 'refunded', 'reversed')) = 1080000),
  'H23 historical: existing discounted year keeps its original span, receipts and one granted period');

select * from finish();
rollback;
