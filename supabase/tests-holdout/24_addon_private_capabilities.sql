-- A-012 independent capability tests. Outer triggers/RLS are isolated only in
-- this rolled-back transaction, proving each elevated effect owns its guard.
begin;
set local role postgres;
set local search_path=public,extensions;
select plan(41);
create function pg_temp.cap_id(n integer) returns uuid language sql immutable as $fn$
 select ('ca240000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$fn$;
insert into auth.users(id) values(pg_temp.cap_id(10)),(pg_temp.cap_id(14));
insert into public.organizations(id,name,gym_code,status) values(pg_temp.cap_id(1),'Capability gym','CAPB24','active');
insert into public.organization_settings(tenant_id) values(pg_temp.cap_id(1));
insert into public.branches(id,tenant_id,name) values(pg_temp.cap_id(3),pg_temp.cap_id(1),'Main');
insert into public.staff(id,tenant_id,user_id,role,full_name) values
 (pg_temp.cap_id(11),pg_temp.cap_id(1),pg_temp.cap_id(10),'gym_owner','Owner'),
 (pg_temp.cap_id(12),pg_temp.cap_id(1),pg_temp.cap_id(14),'trainer','Trainer');
insert into public.members(id,tenant_id,branch_id,full_name,phone)
 values(pg_temp.cap_id(21),pg_temp.cap_id(1),pg_temp.cap_id(3),'Member','+919944220024');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,cancellation_terms,
 trainer_staff_id,trainer_qualification,session_count,stock_quantity) values
 (pg_temp.cap_id(40),pg_temp.cap_id(1),'product','Product','Physical product',0,30,'Desk cancellation',null,null,null,10),
 (pg_temp.cap_id(41),pg_temp.cap_id(1),'pt_package','PT','Four PT sessions',10000,30,'Desk cancellation',pg_temp.cap_id(12),'Gym qualification',4,null);
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,method,status,paid_at,recorded_by_staff_id)
 values(pg_temp.cap_id(60),pg_temp.cap_id(1),pg_temp.cap_id(21),10000,'INR','cash','paid',transaction_timestamp(),pg_temp.cap_id(11));
-- Complete keyed pending product and valid historical paid PT entitlement.
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,
 currency,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request,starts_on,expires_on)
 select pg_temp.cap_id(50),pg_temp.cap_id(1),pg_temp.cap_id(21),p.id,'pending',1,0,0,'INR',pg_temp.cap_id(11),pg_temp.cap_id(80)::text,
 jsonb_build_object('kind','product','name',p.name,'description',p.description,'cancellationTerms',p.cancellation_terms,'validityDays',30,'trainerQualification',null),
 jsonb_build_object('memberId',pg_temp.cap_id(21)::text,'productId',p.id::text,'quantity',1,'quoteVersion',p.quote_version::text,
 'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method',null,'reason','Capabilities'),
 (transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29
 from public.addon_products p where id=pg_temp.cap_id(40);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,status,quantity,unit_price_paise,total_paise,
 currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on)
 values(pg_temp.cap_id(51),pg_temp.cap_id(1),pg_temp.cap_id(21),pg_temp.cap_id(41),pg_temp.cap_id(60),'active',1,10000,10000,
 'INR',pg_temp.cap_id(12),4,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date-2,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+27);
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id)
 values(pg_temp.cap_id(61),pg_temp.cap_id(1),pg_temp.cap_id(60),'refund',10000,'INR','requested','Cash returned',pg_temp.cap_id(11));
set local session_replication_role=replica;
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
 values(pg_temp.cap_id(70),pg_temp.cap_id(1),pg_temp.cap_id(51),pg_temp.cap_id(12),pg_temp.cap_id(21),
 transaction_timestamp()-interval '2 hours',transaction_timestamp()-interval '1 hour');
set local session_replication_role=origin;

-- Resolve the fixture's queued acceptance check as cancelled before isolating
-- its triggers; the unsold pending row is then restored with those guards off.
set local session_replication_role=replica;
update public.addon_orders set status='cancelled' where id=pg_temp.cap_id(50);
set local session_replication_role=origin;
set constraints all immediate;
set constraints all deferred;
alter table public.addon_orders disable trigger user;
alter table public.refunds disable trigger user;
alter table public.pt_sessions disable trigger user;
alter table public.addon_orders disable row level security;
alter table public.refunds disable row level security;
alter table public.pt_sessions disable row level security;
update public.addon_orders set status='pending' where id=pg_temp.cap_id(50);

create function pg_temp.cap_probe(p_kind text,p_bad text default null,p_trusted boolean default false,p_service boolean default false) returns text language plpgsql as $fn$
declare claims jsonb; answer text;
begin
 claims:=jsonb_build_object('sub',case when p_kind in ('pt','pt_lock') then pg_temp.cap_id(14) else pg_temp.cap_id(10) end,
  'role','authenticated','tenant_id',pg_temp.cap_id(1),'app_role',case when p_kind in ('pt','pt_lock') then 'trainer' else 'gym_owner' end,
  'staff_id',case when p_kind in ('pt','pt_lock') then pg_temp.cap_id(12) else pg_temp.cap_id(11) end);
 if p_bad='tenant' then claims:=claims||jsonb_build_object('tenant_id',gen_random_uuid()); end if;
 if p_bad='actor' then claims:=claims||jsonb_build_object('staff_id',gen_random_uuid()); end if;
 if p_bad='role' then claims:=claims||jsonb_build_object('app_role','member','member_id',pg_temp.cap_id(21)); end if;
 if p_bad='preview' then claims:=claims||jsonb_build_object('impersonation_session_id',gen_random_uuid()); end if;
 if p_bad='subject' then claims:=claims||jsonb_build_object('sub',gen_random_uuid()); end if;
 if p_bad='missing_subject' then claims:=claims-'sub'; end if;
 begin
  perform set_config('request.jwt.claims',case when p_service then '{"role":"service_role"}' when p_trusted then '' else claims::text end,true);
  if p_service then set local role service_role;
  elsif not p_trusted then set local role authenticated; end if;
  if p_kind in ('order','product_lock') then
   update public.addon_orders set status='paid',sold_at=transaction_timestamp() where id=pg_temp.cap_id(50);
  elsif p_kind='refund' then
   update public.refunds set status='completed',processed_at=transaction_timestamp() where id=pg_temp.cap_id(61);
  else
   update public.pt_sessions set status='completed' where id=pg_temp.cap_id(70);
  end if;
  set local role postgres;
  perform set_config('request.jwt.claims','',true);
  if p_kind='product_lock' then select case when status='paid' then 'LOCKED' else 'NO_EFFECT' end into answer from public.addon_orders where id=pg_temp.cap_id(50);
  elsif p_kind='pt_lock' then select case when status='completed' then 'LOCKED' else 'NO_EFFECT' end into answer from public.pt_sessions where id=pg_temp.cap_id(70);
  elsif p_kind='order' then select case when stock_quantity=9 then 'APPLIED' else 'NO_EFFECT' end into answer from public.addon_products where id=pg_temp.cap_id(40);
  elsif p_kind='refund' then select case when status='refunded' and not exists(select 1 from public.pt_sessions where id=pg_temp.cap_id(70) and status='scheduled') then 'APPLIED' else 'NO_EFFECT' end into answer from public.addon_orders where id=pg_temp.cap_id(51);
  else select case when sessions_used=1 then 'APPLIED' else 'NO_EFFECT' end into answer from public.addon_orders where id=pg_temp.cap_id(51);
  end if;
  raise exception using errcode='HC024',message='rollback probe effects';
 exception when sqlstate 'HC024' then null;
 when others then answer:=sqlstate;
 end;
 return answer;
end;
$fn$;
do $do$ begin
 execute format('grant usage on schema %s to authenticated, service_role',pg_my_temp_schema()::regnamespace);
end; $do$;

create trigger cap_order_effect after update on public.addon_orders for each row execute function app.apply_addon_order_effects();
select is(pg_temp.cap_probe('order'),'APPLIED','Private order effect permits its real owner acceptance');
select is(pg_temp.cap_probe('order',null,true),'APPLIED','Private order effect permits trusted null-auth processing');
select is(pg_temp.cap_probe('order',null,true,true),'APPLIED','Private order effect permits subjectless trusted service processing');
select is(pg_temp.cap_probe('order','missing_subject'),'42501','Private order effect refuses authenticated claims without a subject');
select is(pg_temp.cap_probe('order','tenant'),'42501','Private order effect independently rejects a foreign tenant claim');
select is(pg_temp.cap_probe('order','actor'),'42501','Private order effect independently rejects an invented staff actor');
select is(pg_temp.cap_probe('order','role'),'42501','Private order effect independently rejects member authority');
select is(pg_temp.cap_probe('order','preview'),'42501','Private order effect independently rejects impersonation');
select is(pg_temp.cap_probe('order','subject'),'42501','Private order effect independently verifies actor subject linkage');
drop trigger cap_order_effect on public.addon_orders;
create trigger cap_refund_effect after update on public.refunds for each row execute function app.apply_addon_refund_effect();
select is(pg_temp.cap_probe('refund'),'APPLIED','Private refund effect permits its real owner completion');
select is(pg_temp.cap_probe('refund',null,true),'APPLIED','Private refund effect permits trusted null-auth processing');
select is(pg_temp.cap_probe('refund',null,true,true),'APPLIED','Private refund effect permits subjectless trusted service processing');
select is(pg_temp.cap_probe('refund','missing_subject'),'42501','Private refund effect refuses authenticated claims without a subject');
select is(pg_temp.cap_probe('refund','tenant'),'42501','Private refund effect independently rejects a foreign tenant claim');
select is(pg_temp.cap_probe('refund','actor'),'42501','Private refund effect independently rejects an invented staff actor');
select is(pg_temp.cap_probe('refund','role'),'42501','Private refund effect independently rejects member authority');
select is(pg_temp.cap_probe('refund','preview'),'42501','Private refund effect independently rejects impersonation');
select is(pg_temp.cap_probe('refund','subject'),'42501','Private refund effect independently verifies actor subject linkage');
drop trigger cap_refund_effect on public.refunds;
create trigger cap_pt_effect after update on public.pt_sessions for each row execute function app.apply_pt_session_effect();
select is(pg_temp.cap_probe('pt'),'APPLIED','Private PT effect permits its real assigned trainer completion');
select is(pg_temp.cap_probe('pt',null,true),'APPLIED','Private PT effect permits trusted null-auth processing');
select is(pg_temp.cap_probe('pt',null,true,true),'APPLIED','Private PT effect permits subjectless trusted service processing');
select is(pg_temp.cap_probe('pt','missing_subject'),'42501','Private PT effect refuses authenticated claims without a subject');
select is(pg_temp.cap_probe('pt','tenant'),'42501','Private PT effect independently rejects a foreign tenant claim');
select is(pg_temp.cap_probe('pt','actor'),'42501','Private PT effect independently rejects an invented staff actor');
select is(pg_temp.cap_probe('pt','role'),'42501','Private PT effect independently rejects member authority');
select is(pg_temp.cap_probe('pt','preview'),'42501','Private PT effect independently rejects impersonation');
select is(pg_temp.cap_probe('pt','subject'),'42501','Private PT effect independently verifies actor subject linkage');
drop trigger cap_pt_effect on public.pt_sessions;

create trigger cap_product_lock before update on public.addon_orders for each row execute function app.lock_addon_product_for_order();
select is(pg_temp.cap_probe('product_lock'),'LOCKED','Private product lock permits its real owner acceptance');
select is(pg_temp.cap_probe('product_lock',null,true),'LOCKED','Private product lock permits subjectless trusted postgres processing');
select is(pg_temp.cap_probe('product_lock',null,true,true),'LOCKED','Private product lock permits subjectless trusted service processing');
select is(pg_temp.cap_probe('product_lock','missing_subject'),'42501','Private product lock refuses authenticated claims without a subject');
drop trigger cap_product_lock on public.addon_orders;
create trigger cap_pt_lock before update on public.pt_sessions for each row execute function app.lock_addon_order_for_pt_session();
select is(pg_temp.cap_probe('pt_lock'),'LOCKED','Private session lock permits its real assigned trainer');
select is(pg_temp.cap_probe('pt_lock',null,true),'LOCKED','Private session lock permits subjectless trusted postgres processing');
select is(pg_temp.cap_probe('pt_lock',null,true,true),'LOCKED','Private session lock permits subjectless trusted service processing');
select is(pg_temp.cap_probe('pt_lock','missing_subject'),'42501','Private session lock refuses authenticated claims without a subject');
drop trigger cap_pt_lock on public.pt_sessions;

-- The same privileged functions cannot be borrowed by another table, even by a
-- structurally identical caller, or run on an unsupported source operation.
create temporary table cap_shadow_order as select * from public.addon_orders where id=pg_temp.cap_id(50);
create temporary table cap_shadow_refund as select * from public.refunds where id=pg_temp.cap_id(61);
create temporary table cap_shadow_pt as select * from public.pt_sessions where id=pg_temp.cap_id(70);
create trigger cap_shadow_order_effect after update on cap_shadow_order for each row execute function app.apply_addon_order_effects();
create trigger cap_shadow_refund_effect after update on cap_shadow_refund for each row execute function app.apply_addon_refund_effect();
create trigger cap_shadow_pt_effect after update on cap_shadow_pt for each row execute function app.apply_pt_session_effect();
select throws_ok('update cap_shadow_order set status=''paid''',null,null,'Private order effect rejects a structurally identical foreign trigger table');
select throws_ok('update cap_shadow_refund set status=''completed''',null,null,'Private refund effect rejects a structurally identical foreign trigger table');
select throws_ok('update cap_shadow_pt set status=''completed''',null,null,'Private PT effect rejects a structurally identical foreign trigger table');
create trigger cap_order_delete before delete on public.addon_orders for each row execute function app.apply_addon_order_effects();
create trigger cap_refund_delete before delete on public.refunds for each row execute function app.apply_addon_refund_effect();
create trigger cap_pt_delete before delete on public.pt_sessions for each row execute function app.apply_pt_session_effect();
select throws_ok('delete from public.addon_orders where id=pg_temp.cap_id(50)',null,null,'Private order effect refuses an unsupported DELETE operation');
select throws_ok('delete from public.refunds where id=pg_temp.cap_id(61)',null,null,'Private refund effect refuses an unsupported DELETE operation');
select throws_ok('delete from public.pt_sessions where id=pg_temp.cap_id(70)',null,null,'Private PT effect refuses an unsupported DELETE operation');
drop trigger cap_order_delete on public.addon_orders;
drop trigger cap_refund_delete on public.refunds;
drop trigger cap_pt_delete on public.pt_sessions;
alter table public.addon_orders enable row level security;
alter table public.refunds enable row level security;
alter table public.pt_sessions enable row level security;
alter table public.addon_orders enable trigger user;
alter table public.refunds enable trigger user;
alter table public.pt_sessions enable trigger user;
select * from finish();
rollback;
