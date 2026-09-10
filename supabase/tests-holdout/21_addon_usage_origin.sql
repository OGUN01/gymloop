-- Independent A-002/A-005/A-009 tests: bought sessions do not imply used sessions.
begin;
set local role postgres;
set local search_path=public,extensions;
select plan(14);

create temporary table usage_ids as select gen_random_uuid() tenant,
  gen_random_uuid() branch,gen_random_uuid() owner_user,gen_random_uuid() owner_id,
  gen_random_uuid() trainer_id,gen_random_uuid() member_id,gen_random_uuid() product,
  gen_random_uuid() injected_order,gen_random_uuid() accepted_order,
  gen_random_uuid() injected_key,gen_random_uuid() accepted_key,gen_random_uuid() forged_session,
  gen_random_uuid() diet;
grant select on usage_ids to authenticated;
insert into auth.users(id) select owner_user from usage_ids;
insert into public.organizations(id,name,gym_code,status)
select tenant,'Usage origin holdout','USAGE1','active' from usage_ids;
insert into public.organization_settings(tenant_id) select tenant from usage_ids;
insert into public.branches(id,tenant_id,name,is_default) select branch,tenant,'Main',true from usage_ids;
insert into public.staff(id,tenant_id,user_id,role,full_name)
select owner_id,tenant,owner_user,'gym_owner'::public.app_role,'Owner' from usage_ids
union all select trainer_id,tenant,null,'trainer','Trainer' from usage_ids;
insert into public.members(id,tenant_id,branch_id,full_name,phone)
select member_id,tenant,branch,'Member','+919877660021' from usage_ids;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,
  cancellation_terms,session_count,trainer_staff_id,trainer_qualification)
select product,tenant,'pt_package','Four introductory sessions','Four individual PT sessions',0,30,
  'Desk cancellation',4,trainer_id,'Gym-qualified trainer' from usage_ids;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,cancellation_terms)
select diet,tenant,'diet_plan','Introductory diet','Individual diet guidance',0,30,'Desk cancellation' from usage_ids;
create temporary table usage_sale(order_id uuid,payment_id uuid,initial_session_id uuid,replayed boolean);
grant select,insert on usage_sale to authenticated;

-- This direct caller remains subject to ordinary authenticated grants and triggers.
-- It reconstructs the frozen wire/row contract from an accepted control sale,
-- changing only the fresh request key, fresh slot and injected usage count.
create function pg_temp.usage_attempt(p_accept boolean) returns void language plpgsql as $fn$
declare i record; o record; target_order uuid; target_key uuid; request jsonb;
begin
  select * into i from usage_ids;
  select a.* into o from public.addon_orders a where a.id=(select order_id from usage_sale);
  target_order:=case when p_accept then i.accepted_order else i.injected_order end;
  target_key:=case when p_accept then i.accepted_key else i.injected_key end;
  request:=o.sale_request || jsonb_build_object(
    'initialStartsAt',(transaction_timestamp()+interval '2 days')::text,
    'initialEndsAt',(transaction_timestamp()+interval '2 days 1 hour')::text);
  insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,
    unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,
    starts_on,expires_on,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request)
  values(target_order,i.tenant,i.member_id,i.product,'pending',1,0,0,'INR',i.trainer_id,4,1,
    o.starts_on,o.expires_on,i.owner_id,target_key::text,o.sale_snapshot,request);
  if p_accept then
    insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
    values(i.forged_session,i.tenant,target_order,i.trainer_id,i.member_id,
      transaction_timestamp()+interval '2 days',transaction_timestamp()+interval '2 days 1 hour');
    update public.addon_orders set initial_session_id=i.forged_session where id=target_order;
    update public.addon_orders set status='paid',sold_at=transaction_timestamp() where id=target_order;
    update public.addon_orders set status='active' where id=target_order;
  end if;
end;
$fn$;
create function pg_temp.accept_diet(p_quantity integer,p_shift integer) returns text language plpgsql as $fn$
declare i record; p record; stamp timestamptz; target_order uuid:=gen_random_uuid(); result text;
begin
  select * into i from usage_ids;
  select * into p from public.addon_products where id=i.diet;
  stamp:=transaction_timestamp()+p_shift*interval '1 day';
  insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,
    currency,sold_by_staff_id,idempotency_key,sold_at,starts_on,expires_on,sale_snapshot,sale_request)
  values(target_order,i.tenant,i.member_id,i.diet,'pending',p_quantity,0,0,'INR',i.owner_id,gen_random_uuid()::text,
    stamp,(stamp at time zone 'Asia/Kolkata')::date,(stamp at time zone 'Asia/Kolkata')::date+29,
    jsonb_build_object('kind','diet_plan','name',p.name,'description',p.description,'cancellationTerms',p.cancellation_terms,
      'validityDays',30,'trainerQualification',null),
    jsonb_build_object('memberId',i.member_id::text,'productId',i.diet::text,'quantity',p_quantity,'quoteVersion',p.quote_version::text,
      'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method',null,'reason','Introductory diet'));
  update public.addon_orders set status='paid' where id=target_order;
  update public.addon_orders set status='active' where id=target_order;
  select case when sold_at=transaction_timestamp()
    and starts_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date
    and expires_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29
    then 'STAMPED' else 'FORGED' end into result from public.addon_orders where id=target_order;
  return result;
exception when others then return 'REFUSED:'||sqlstate;
end;
$fn$;
do $do$
begin
  execute format('grant usage on schema %s to authenticated',pg_my_temp_schema()::regnamespace);
end;
$do$;
select set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated',
  'tenant_id',tenant,'app_role','gym_owner','staff_id',owner_id)::text,true) from usage_ids;
set local role authenticated;
insert into usage_sale select s.* from usage_ids i cross join lateral public.record_addon_sale(
  i.member_id,i.product,1,(select quote_version from public.addon_products where id=i.product),
  i.trainer_id,transaction_timestamp()+interval '1 day',transaction_timestamp()+interval '1 day 1 hour',
  null,'Introductory sessions',gen_random_uuid()) s;

select is((select sessions_used from public.addon_orders where id=(select order_id from usage_sale)),0,
  'A-002 normal new PT sale has zero consumed sessions');
select is((select count(*) from public.pt_sessions where addon_order_id=(select order_id from usage_sale) and status='completed'),0::bigint,
  'A-009 new PT sale has no completed-session evidence');
select throws_ok('select pg_temp.usage_attempt(false)',null,null,
  'A-002 direct keyed pending PT insert refuses fabricated nonzero usage');
select is((select count(*) from public.addon_orders where id=(select injected_order from usage_ids)),0::bigint,
  'A-002 rejected pending usage leaves no fabricated order');
select throws_ok('select pg_temp.usage_attempt(true)',null,null,
  'A-005 direct keyed PT acceptance cannot carry fabricated usage into active entitlement');
select is((select count(*) from public.addon_orders where id=(select accepted_order from usage_ids)),0::bigint,
  'A-005 failed fabricated acceptance leaves no accepted order');
select is((select count(*) from public.pt_sessions where id=(select forged_session from usage_ids)),0::bigint,
  'A-009 failed fabricated acceptance leaves no reservation effect');
select is((select count(*) from public.addon_orders a where a.tenant_id=(select tenant from usage_ids)
  and a.sessions_used<>(select count(*) from public.pt_sessions s where s.addon_order_id=a.id and s.status='completed')),0::bigint,
  'A-009 every new order usage count remains backed by completed-session evidence');

select ok(pg_temp.accept_diet(2,0) in ('REFUSED:GL055','REFUSED:23514'),
  'A-005 direct free diet acceptance refuses quantity two');
select is((select count(*) from public.addon_orders where tenant_id=(select tenant from usage_ids)
  and addon_product_id=(select diet from usage_ids) and quantity<>1),0::bigint,
  'A-005 refused diet quantity leaves no invalid entitlement');
select ok(pg_temp.accept_diet(1,-7) in ('STAMPED','REFUSED:GL053','REFUSED:GL055'),
  'A-005 a caller cannot backdate sold_at or its derived validity at direct acceptance');
select ok(pg_temp.accept_diet(1,7) in ('STAMPED','REFUSED:GL053','REFUSED:GL055'),
  'A-005 a caller cannot future-date sold_at or its derived validity at direct acceptance');
select is((select count(*) from public.addon_orders where tenant_id=(select tenant from usage_ids)
  and addon_product_id=(select diet from usage_ids) and (sold_at<>transaction_timestamp()
  or starts_on<>(transaction_timestamp() at time zone 'Asia/Kolkata')::date
  or expires_on<>(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29)),0::bigint,
  'A-005 every accepted diet keeps the server acceptance instant and inclusive window');
select throws_ok($sql$insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,
  unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on,
  sold_by_staff_id,idempotency_key,sale_snapshot,sale_request)
  select gen_random_uuid(),o.tenant_id,o.member_id,o.addon_product_id,'pending',2,0,0,'INR',o.trainer_staff_id,4,0,
    o.starts_on,o.expires_on,o.sold_by_staff_id,gen_random_uuid()::text,o.sale_snapshot,
    o.sale_request||jsonb_build_object('quantity',2)
  from public.addon_orders o where o.id=(select order_id from usage_sale)$sql$,null,null,
  'A-008 direct PT order insertion refuses quantity two');

select * from finish();
rollback;
