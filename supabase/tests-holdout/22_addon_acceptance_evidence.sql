-- Independent A-001/A-005/A-006 evidence checks, authored without implementation.
begin;
set local role postgres;
set local search_path=public,extensions;
select plan(16);
create function pg_temp.evidence_id(n integer) returns uuid language sql immutable as $fn$
  select ('e1060000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$fn$;
insert into auth.users(id) values(pg_temp.evidence_id(10));
insert into public.organizations(id,name,gym_code,status) values
  (pg_temp.evidence_id(1),'Evidence gym','EVID01','active'),(pg_temp.evidence_id(2),'Foreign evidence gym','EVID02','active');
insert into public.organization_settings(tenant_id) values(pg_temp.evidence_id(1));
insert into public.branches(id,tenant_id,name) values
  (pg_temp.evidence_id(3),pg_temp.evidence_id(1),'Main'),(pg_temp.evidence_id(4),pg_temp.evidence_id(2),'Main');
insert into public.staff(id,tenant_id,user_id,role,full_name) values
  (pg_temp.evidence_id(11),pg_temp.evidence_id(1),pg_temp.evidence_id(10),'gym_owner','Owner'),
  (pg_temp.evidence_id(12),pg_temp.evidence_id(1),null,'trainer','Trainer'),
  (pg_temp.evidence_id(13),pg_temp.evidence_id(2),null,'gym_owner','Foreign owner');
insert into public.members(id,tenant_id,branch_id,full_name,phone) values
  (pg_temp.evidence_id(21),pg_temp.evidence_id(1),pg_temp.evidence_id(3),'Selected member','+919811220021'),
  (pg_temp.evidence_id(22),pg_temp.evidence_id(1),pg_temp.evidence_id(3),'Different member','+919811220022'),
  (pg_temp.evidence_id(23),pg_temp.evidence_id(2),pg_temp.evidence_id(4),'Foreign member','+919811220023');
insert into public.plans(id,tenant_id,name,duration_days,price_paise)
values(pg_temp.evidence_id(30),pg_temp.evidence_id(1),'Membership',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,price_paise)
values(pg_temp.evidence_id(31),pg_temp.evidence_id(1),pg_temp.evidence_id(21),pg_temp.evidence_id(30),10000);
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,cancellation_terms,
  trainer_staff_id,trainer_qualification,session_count) values
  (pg_temp.evidence_id(40),pg_temp.evidence_id(1),'diet_plan','Paid diet','Individual diet',10000,30,'Desk cancellation',null,null,null),
  (pg_temp.evidence_id(41),pg_temp.evidence_id(1),'diet_plan','Free diet','Individual diet',0,30,'Desk cancellation',null,null,null),
  (pg_temp.evidence_id(42),pg_temp.evidence_id(1),'pt_package','Free PT','Individual PT',0,30,'Desk cancellation',pg_temp.evidence_id(12),'Gym qualification',4);
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,currency,method,status,paid_at,recorded_by_staff_id) values
  (pg_temp.evidence_id(51),pg_temp.evidence_id(1),pg_temp.evidence_id(21),null,10000,'INR','cash','created',null,pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(52),pg_temp.evidence_id(1),pg_temp.evidence_id(22),null,10000,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(53),pg_temp.evidence_id(1),pg_temp.evidence_id(21),null,10000,'USD','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(54),pg_temp.evidence_id(1),pg_temp.evidence_id(21),null,9999,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(55),pg_temp.evidence_id(1),pg_temp.evidence_id(21),pg_temp.evidence_id(31),10000,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(56),pg_temp.evidence_id(2),pg_temp.evidence_id(23),null,10000,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(13)),
  (pg_temp.evidence_id(57),pg_temp.evidence_id(1),pg_temp.evidence_id(21),null,10000,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11)),
  (pg_temp.evidence_id(58),pg_temp.evidence_id(1),pg_temp.evidence_id(21),null,10000,'INR','cash','paid',transaction_timestamp(),pg_temp.evidence_id(11));
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,status,unit_price_paise,total_paise,starts_on,expires_on)
values(pg_temp.evidence_id(60),pg_temp.evidence_id(1),pg_temp.evidence_id(21),pg_temp.evidence_id(40),pg_temp.evidence_id(57),'active',10000,10000,
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29);

create function pg_temp.evidence_attempt(p_product integer,p_payment integer,p_accept boolean,p_slot integer default 1)
returns text language plpgsql as $fn$
declare p record; target_order uuid:=gen_random_uuid(); target_session uuid:=gen_random_uuid();
  start_time timestamptz:=transaction_timestamp()+p_slot*interval '1 day'; request jsonb;
begin
  select * into p from public.addon_products where id=pg_temp.evidence_id(p_product);
  request:=jsonb_build_object('memberId',pg_temp.evidence_id(21)::text,'productId',p.id::text,'quantity',1,
    'quoteVersion',p.quote_version::text,'trainerStaffId',p.trainer_staff_id::text,
    'initialStartsAt',case when p.kind='pt_package' then start_time::text else null end,
    'initialEndsAt',case when p.kind='pt_package' then (start_time+interval '1 hour')::text else null end,
    'method',case when p.price_paise>0 then 'cash' else null end,'reason','Evidence test');
  insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,status,quantity,
    unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on,
    sold_by_staff_id,idempotency_key,sale_snapshot,sale_request)
  values(target_order,pg_temp.evidence_id(1),pg_temp.evidence_id(21),p.id,
    case when p_payment is null then null else pg_temp.evidence_id(p_payment) end,'pending',1,
    p.price_paise,p.price_paise,'INR',p.trainer_staff_id,p.session_count,0,
    (transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29,
    pg_temp.evidence_id(11),gen_random_uuid()::text,
    jsonb_build_object('kind',p.kind,'name',p.name,'description',p.description,'cancellationTerms',p.cancellation_terms,
      'validityDays',30,'trainerQualification',p.trainer_qualification),request);
  if p_accept then
    if p.kind='pt_package' then
      insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
      values(target_session,pg_temp.evidence_id(1),target_order,p.trainer_staff_id,pg_temp.evidence_id(21),start_time,start_time+interval '1 hour');
      update public.addon_orders set initial_session_id=target_session where id=target_order;
    end if;
    update public.addon_orders set status='paid',sold_at=transaction_timestamp() where id=target_order;
    update public.addon_orders set status='active' where id=target_order;
  else
    update public.addon_orders set status='cancelled' where id=target_order;
  end if;
  return 'OK';
exception when others then return sqlstate;
end;
$fn$;
do $do$ begin
  execute format('grant usage on schema %s to authenticated',pg_my_temp_schema()::regnamespace);
end; $do$;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.evidence_id(10),'role','authenticated',
  'tenant_id',pg_temp.evidence_id(1),'app_role','gym_owner','staff_id',pg_temp.evidence_id(11))::text,true);
set local role authenticated;

select is(pg_temp.evidence_attempt(40,51,false),'GL055','A-006 pending order cannot link money that has not arrived');
select is(pg_temp.evidence_attempt(40,52,false),'GL055','A-006 pending order payment must belong to the selected member');
select is(pg_temp.evidence_attempt(40,53,false),'GL055','A-006 pending order payment must use its exact currency');
select is(pg_temp.evidence_attempt(40,54,false),'GL055','A-006 pending order payment must equal its exact total');
select is(pg_temp.evidence_attempt(40,55,false),'GL055','A-006 a membership payment cannot also fund a pending add-on');
select ok(pg_temp.evidence_attempt(40,56,false) in ('GL055','23503'),'A-006 a pending order cannot link another gym payment');
select ok(pg_temp.evidence_attempt(40,57,false) in ('GL055','23505'),'A-006 arrived payment cannot fund two orders');
select is(pg_temp.evidence_attempt(41,58,false),'GL055','A-005 zero-price pending-to-cancelled order may never carry payment');
select is((select count(*) from public.addon_orders where tenant_id=pg_temp.evidence_id(1)),1::bigint,
  'A-006 rejected payment substitutions leave only the original evidenced order');

update public.members set status='cancelled' where id=pg_temp.evidence_id(21);
select is(pg_temp.evidence_attempt(41,null,true),'GL055','A-001 direct acceptance refuses a cancelled member');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- Independent historical states, followed by normal authenticated commands.
set local session_replication_role=replica;
update public.members set status='blocked' where id=pg_temp.evidence_id(21);
set local session_replication_role=origin;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.evidence_id(10),'role','authenticated',
  'tenant_id',pg_temp.evidence_id(1),'app_role','gym_owner','staff_id',pg_temp.evidence_id(11))::text,true);
set local role authenticated;
select is(pg_temp.evidence_attempt(41,null,true),'GL055','A-001 direct acceptance refuses a blocked member');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role=replica;
update public.members set status='active',erased_at=transaction_timestamp() where id=pg_temp.evidence_id(21);
set local session_replication_role=origin;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.evidence_id(10),'role','authenticated',
  'tenant_id',pg_temp.evidence_id(1),'app_role','gym_owner','staff_id',pg_temp.evidence_id(11))::text,true);
set local role authenticated;
select is(pg_temp.evidence_attempt(41,null,true),'GL055','A-001 direct acceptance refuses an erased member');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role=replica;
update public.members set erased_at=null where id=pg_temp.evidence_id(21);
set local session_replication_role=origin;
update public.staff set is_active=false where id=pg_temp.evidence_id(12);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.evidence_id(10),'role','authenticated',
  'tenant_id',pg_temp.evidence_id(1),'app_role','gym_owner','staff_id',pg_temp.evidence_id(11))::text,true);
set local role authenticated;
select is(pg_temp.evidence_attempt(42,null,true,3),'GL055','A-001 direct PT acceptance refuses an inactive assigned trainer');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.staff set is_active=true,role='front_desk' where id=pg_temp.evidence_id(12);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.evidence_id(10),'role','authenticated',
  'tenant_id',pg_temp.evidence_id(1),'app_role','gym_owner','staff_id',pg_temp.evidence_id(11))::text,true);
set local role authenticated;
select is(pg_temp.evidence_attempt(42,null,true,4),'GL055','A-001 direct PT acceptance refuses an assigned staff member who is not a trainer');
select is((select count(*) from public.addon_orders where tenant_id=pg_temp.evidence_id(1)),1::bigint,
  'A-005 ineligible acceptance leaves the original order evidence unchanged');
select is((select count(*) from public.pt_sessions where tenant_id=pg_temp.evidence_id(1)),0::bigint,
  'A-005 ineligible PT acceptance leaves no reservation');
select * from finish();
rollback;
