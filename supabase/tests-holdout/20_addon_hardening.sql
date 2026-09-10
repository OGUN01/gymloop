-- Independent assertions derived from the frozen A-001--A-012 contract.
-- Historical fixture corruption is confined to this rolled-back transaction.
begin;
set local role postgres;
set local search_path = public, extensions;
select plan(19);

create temporary table hardening_ids as select
  gen_random_uuid() as tenant, gen_random_uuid() as branch,
  gen_random_uuid() as owner_user, gen_random_uuid() as trainer_user,
  gen_random_uuid() as owner_id, gen_random_uuid() as trainer_id,
  gen_random_uuid() as member_id, gen_random_uuid() as diet,
  gen_random_uuid() as pt, gen_random_uuid() as product,
  gen_random_uuid() as retry_session, gen_random_uuid() as pending_order;
grant select on hardening_ids to authenticated;
insert into auth.users(id) select owner_user from hardening_ids
union all select trainer_user from hardening_ids;
insert into public.organizations(id,name,gym_code,status)
select tenant,'Independent hardening gym','HARD20','active' from hardening_ids;
insert into public.organization_settings(tenant_id) select tenant from hardening_ids;
insert into public.branches(id,tenant_id,name,is_default)
select branch,tenant,'Main',true from hardening_ids;
insert into public.staff(id,tenant_id,user_id,role,full_name)
select owner_id,tenant,owner_user,'gym_owner'::public.app_role,'Owner' from hardening_ids
union all select trainer_id,tenant,trainer_user,'trainer','Trainer' from hardening_ids;
insert into public.members(id,tenant_id,branch_id,full_name,phone)
select member_id,tenant,branch,'Member','+919988770020' from hardening_ids;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,
  validity_days,cancellation_terms,session_count,trainer_staff_id,trainer_qualification,stock_quantity)
select diet,tenant,'diet_plan'::public.addon_kind,'Diet','Individual diet',10000,30,'Desk return',null::integer,null::uuid,null::text,null::integer from hardening_ids
union all select pt,tenant,'pt_package','PT','Four sessions',10000,30,'Desk return',4,trainer_id,'Gym qualification',null from hardening_ids
union all select product,tenant,'product','Product','Physical product',10000,30,'Desk return',null,null,null,5 from hardening_ids;
create temporary table hardening_sales(tag text,order_id uuid,payment_id uuid,initial_session_id uuid,replayed boolean);
grant select,insert on hardening_sales to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated',
  'tenant_id',tenant,'app_role','gym_owner','staff_id',owner_id)::text,true) from hardening_ids;
set local role authenticated;
insert into hardening_sales select 'diet',s.* from hardening_ids i
cross join lateral public.record_addon_sale(i.member_id,i.diet,1,
  (select quote_version from public.addon_products where id=i.diet),null,null,null,'cash',null,gen_random_uuid()) s;
insert into hardening_sales select 'pt',s.* from hardening_ids i
cross join lateral public.record_addon_sale(i.member_id,i.pt,1,
  (select quote_version from public.addon_products where id=i.pt),i.trainer_id,
  transaction_timestamp()+interval '1 day',transaction_timestamp()+interval '1 day 1 hour','cash',null,gen_random_uuid()) s;
insert into hardening_sales select 'product',s.* from hardening_ids i
cross join lateral public.record_addon_sale(i.member_id,i.product,1,
  (select quote_version from public.addon_products where id=i.product),null,null,null,'cash',null,gen_random_uuid()) s;

-- A-002/A-005: pending is a transaction stage, not permission to invent a price.
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,
  unit_price_paise,total_paise,currency,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request,
  starts_on,expires_on)
select i.pending_order,o.tenant_id,o.member_id,o.addon_product_id,'pending',o.quantity,
  o.unit_price_paise,o.total_paise,o.currency,o.sold_by_staff_id,gen_random_uuid()::text,
  o.sale_snapshot,o.sale_request,o.starts_on,o.expires_on
from hardening_ids i cross join public.addon_orders o
where o.id=(select order_id from hardening_sales where tag='product');
select throws_ok($sql$update public.addon_orders set unit_price_paise=1,total_paise=1
  where id=(select pending_order from hardening_ids)$sql$,null,null,
  'Pending keyed order cannot replace catalogue money before acceptance');
select is((select total_paise from public.addon_orders where id=(select pending_order from hardening_ids)),10000::bigint,
  'Refused pending rewrite preserves the displayed catalogue total');
update public.addon_orders set status='cancelled' where id=(select pending_order from hardening_ids);

-- A-012: different denominations must never consume an INR payment's ceiling.
select throws_ok($sql$insert into public.refunds(tenant_id,payment_id,kind,amount_paise,currency,reason,initiated_by_staff_id)
  select i.tenant,s.payment_id,'refund',10000,'USD','Wrong denomination',i.owner_id
  from hardening_ids i cross join hardening_sales s where s.tag='diet'$sql$,
  null,null,'A-012 refuses cross-currency refund headroom');
select is((select count(*) from public.refunds where payment_id=(select payment_id from hardening_sales where tag='diet')),0::bigint,
  'Rejected currency leaves no refund attempt');

-- A-012 applies to a new completed row, not just a requested-to-completed update.
select lives_ok($sql$insert into public.refunds(tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id)
  select i.tenant,s.payment_id,'refund',10000,'INR','completed','Cash actually handed back',i.owner_id
  from hardening_ids i cross join hardening_sales s where s.tag='pt'$sql$,
  'A completed direct return is accepted for exact eligible cash');
select is((select status::text from public.addon_orders where id=(select order_id from hardening_sales where tag='pt')),
  'refunded','Full directly inserted return ends active PT entitlement');
select is((select count(*) from public.pt_sessions where addon_order_id=(select order_id from hardening_sales where tag='pt') and status='scheduled'),
  0::bigint,'Full directly inserted return cancels all pending reservations');
select ok((select processed_at is not null from public.refunds where payment_id=(select payment_id from hardening_sales where tag='pt')),
  'New direct completed return records a server completion instant');

-- A-012 preserves historical completion and never treats a money return as restock.
select lives_ok($sql$insert into public.refunds(tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id)
  select i.tenant,s.payment_id,'reversal',10000,'INR','completed','Product cash returned',i.owner_id
  from hardening_ids i cross join hardening_sales s where s.tag='product'$sql$,
  'A product may have a completed return without rewriting its delivery');
select is((select status::text from public.addon_orders where id=(select order_id from hardening_sales where tag='product')),
  'completed','Returned product retains terminal handover history');
select is((select stock_quantity from public.addon_products where id=(select product from hardening_ids)),4,
  'Money return never automatically restocks the product');

-- Trusted historical fixtures preserve real recorded money but deliberately carry
-- old nonterminal status, exercising the explicit malformed-history requirement.
set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role = replica;
update public.addon_orders set status='active' where id=(select order_id from hardening_sales where tag='pt');
update public.addon_orders set starts_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date-40,
  expires_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date-1
  where id=(select order_id from hardening_sales where tag='diet');
set local session_replication_role = origin;
select set_config('request.jwt.claims',jsonb_build_object('sub',trainer_user,'role','authenticated',
  'tenant_id',tenant,'app_role','trainer','staff_id',trainer_id)::text,true) from hardening_ids;
set local role authenticated;
select throws_ok($sql$select * from public.schedule_pt_session(
  (select order_id from hardening_sales where tag='pt'),gen_random_uuid(),
  transaction_timestamp()+interval '2 days',transaction_timestamp()+interval '2 days 1 hour',null)$sql$,
  null,null,'Full returned money refuses a new session despite stale active history');
select throws_ok($sql$insert into public.pt_sessions(tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
  select i.tenant,s.order_id,i.trainer_id,i.member_id,transaction_timestamp()+interval '3 days',
  transaction_timestamp()+interval '3 days 1 hour' from hardening_ids i cross join hardening_sales s where s.tag='pt'$sql$,
  null,null,'Direct session creation cannot bypass fully returned money');

set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated',
  'tenant_id',tenant,'app_role','gym_owner','staff_id',owner_id)::text,true) from hardening_ids;
set local role authenticated;
select throws_ok($sql$update public.addon_orders set status='completed' where id=(select order_id from hardening_sales where tag='diet')$sql$,
  null,null,'Direct diet completion refuses expired delivery');
select throws_ok($sql$select * from public.complete_addon_order((select order_id from hardening_sales where tag='diet'))$sql$,
  null,null,'Diet command refuses expired delivery');

-- A fresh PT purchase permits retry but a session UUID cannot buy a new slot.
insert into hardening_sales select 'pt_retry',s.* from hardening_ids i
cross join lateral public.record_addon_sale(i.member_id,i.pt,1,
  (select quote_version from public.addon_products where id=i.pt),i.trainer_id,
  transaction_timestamp()+interval '4 days',transaction_timestamp()+interval '4 days 1 hour','cash',null,gen_random_uuid()) s;
set local role postgres;
select set_config('request.jwt.claims',jsonb_build_object('sub',trainer_user,'role','authenticated',
  'tenant_id',tenant,'app_role','trainer','staff_id',trainer_id)::text,true) from hardening_ids;
set local role authenticated;
select lives_ok($sql$select * from public.schedule_pt_session((select order_id from hardening_sales where tag='pt_retry'),
  (select retry_session from hardening_ids),transaction_timestamp()+interval '5 days',transaction_timestamp()+interval '5 days 1 hour',' stable note ')$sql$,
  'Assigned trainer creates an additional future reservation');
select is((select replayed from public.schedule_pt_session((select order_id from hardening_sales where tag='pt_retry'),
  (select retry_session from hardening_ids),transaction_timestamp()+interval '5 days',transaction_timestamp()+interval '5 days 1 hour','stable note')),
  true,'Exact normalized session retry is an inert replay');
select throws_ok($sql$select * from public.schedule_pt_session((select order_id from hardening_sales where tag='pt_retry'),
  (select retry_session from hardening_ids),transaction_timestamp()+interval '6 days',transaction_timestamp()+interval '6 days 1 hour','stable note')$sql$,
  'GL052',null,'A reused session UUID with a changed slot is an idempotency conflict');
select throws_ok($sql$insert into public.pt_sessions(tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
  select i.tenant,s.order_id,i.trainer_id,i.member_id,transaction_timestamp()-interval '2 hours',
  transaction_timestamp()-interval '1 hour' from hardening_ids i cross join hardening_sales s where s.tag='pt_retry'$sql$,
  null,null,'Direct PT insertion cannot invent a reservation before command time');

select * from finish();
rollback;
