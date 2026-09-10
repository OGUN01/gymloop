-- A-005/A-008/A-009/A-010/A-012 regression boundaries, written implementation-blind.
-- Historical fixtures deliberately retain contradictory old state; compatibility
-- must not turn that state into permission to deliver or invent returned money.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(15);

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('55000000-0000-4000-8000-000000000001','Add-on boundary tests','ADD55A','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('55000000-0000-4000-8000-000000000011','55000000-0000-4000-8000-000000000001','Main',true);
insert into public.staff(id,tenant_id,branch_id,role,full_name) values
 ('55000000-0000-4000-8000-000000000021','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000011','gym_owner','Owner'),
 ('55000000-0000-4000-8000-000000000022','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000011','trainer','Trainer');
insert into public.members(id,tenant_id,branch_id,full_name,phone) values
 ('55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000011','Member','+915500000031');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,session_count,trainer_staff_id,trainer_qualification,stock_quantity,cancellation_terms,is_active) values
 ('55000000-0000-4000-8000-000000000101','55000000-0000-4000-8000-000000000001','diet_plan','Diet','Diet disclosure',10000,'INR',30,null,null,null,null,'Terms',true),
 ('55000000-0000-4000-8000-000000000102','55000000-0000-4000-8000-000000000001','pt_package','PT','PT disclosure',0,'INR',30,2,'55000000-0000-4000-8000-000000000022','Gym qualification',null,'Terms',true),
 ('55000000-0000-4000-8000-000000000103','55000000-0000-4000-8000-000000000001','product','Product','Product disclosure',0,'INR',30,null,null,null,5,'Terms',true);

-- Trusted null-key history is allowed, but its dates and fulfilment prerequisites
-- still govern whether the current command may create new delivery.
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on) values
 ('55000000-0000-4000-8000-000000000201','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000101','active',1,0,0,'INR',null,null,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date-30,(transaction_timestamp() at time zone 'Asia/Kolkata')::date-1),
 ('55000000-0000-4000-8000-000000000202','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000101','active',1,0,0,'INR',null,null,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+1,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+30),
 ('55000000-0000-4000-8000-000000000203','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000103','active',1,0,0,'INR',null,null,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+30),
 ('55000000-0000-4000-8000-000000000204','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000102','active',1,0,0,'INR','55000000-0000-4000-8000-000000000022',2,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+1,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+30),
 ('55000000-0000-4000-8000-000000000205','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000102','active',1,0,0,'INR','55000000-0000-4000-8000-000000000022',2,0,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+30),
 ('55000000-0000-4000-8000-000000000206','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000101','pending',1,0,0,'INR',null,null,0,null,null);
set local session_replication_role=replica;
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status) values
 ('55000000-0000-4000-8000-000000000301','55000000-0000-4000-8000-000000000001','55000000-0000-4000-8000-000000000204','55000000-0000-4000-8000-000000000022','55000000-0000-4000-8000-000000000031',transaction_timestamp()-interval '2 hours',transaction_timestamp()-interval '1 hour','scheduled');
set local session_replication_role=origin;

-- Each probe rolls back even an incorrect success, keeping later assertions
-- independent. Returned SQLSTATE/DETAIL is observed behavior, never source.
create function pg_temp.boundary_error(command text) returns text language plpgsql as $fn$
declare state text; detail text;
begin
  execute command;
  raise exception using errcode='ZX001';
exception when sqlstate 'ZX001' then return null;
when others then
  get stacked diagnostics state=returned_sqlstate,detail=pg_exception_detail;
  return state||':'||coalesce(detail,'');
end $fn$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"55000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"55000000-0000-4000-8000-000000000001","staff_id":"55000000-0000-4000-8000-000000000021"}',true);
select is(pg_temp.boundary_error($$select * from public.complete_addon_order('55000000-0000-4000-8000-000000000201')$$),'GL055:order_unavailable','A-010: expired diet cannot complete through the delivery RPC');
select is(pg_temp.boundary_error($$select * from public.complete_addon_order('55000000-0000-4000-8000-000000000202')$$),'GL055:order_unavailable','A-010: future sold validity does not authorize diet delivery today');
select is(pg_temp.boundary_error($$select * from public.complete_addon_order('55000000-0000-4000-8000-000000000203')$$),'GL055:wrong_order_kind','A-003/A-010: nonterminal product cannot masquerade as explicit diet delivery');
select ok(pg_temp.boundary_error($$update public.addon_orders set status='completed' where id='55000000-0000-4000-8000-000000000201'$$) is not null,'A-010: direct active-to-completed cannot deliver an expired diet');
select ok(pg_temp.boundary_error($$update public.addon_orders set status='completed' where id='55000000-0000-4000-8000-000000000205'$$) is not null,'A-009: direct active-to-completed cannot bypass all purchased PT sessions');
select ok(pg_temp.boundary_error($$update public.addon_orders set status='paid' where id='55000000-0000-4000-8000-000000000206'$$) is not null,'A-005: null-key pending legacy history cannot be accepted as a new sale');
select ok(pg_temp.boundary_error($$update public.addon_orders set status='refunded' where id='55000000-0000-4000-8000-000000000202'$$) is not null,'A-012: direct refunded transition needs completed returned-money evidence');

select set_config('request.jwt.claims','{"sub":"55000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"trainer","tenant_id":"55000000-0000-4000-8000-000000000001","staff_id":"55000000-0000-4000-8000-000000000022"}',true);
select is(pg_temp.boundary_error($$select * from public.finish_pt_session('55000000-0000-4000-8000-000000000301','completed')$$),'GL058:session_outside_validity','A-009: ended session cannot consume PT usage before the sold window starts');

-- Fresh scheduling reserves the final capacity and exact replay stays inert.
select lives_ok($$select * from public.schedule_pt_session('55000000-0000-4000-8000-000000000205','55000000-0000-4000-8000-000000000302',transaction_timestamp()+interval '2 days',transaction_timestamp()+interval '2 days 1 hour','  Same  notes  ')$$,'A-008/A-009: trainer schedules a valid session');
select results_eq($$select * from public.schedule_pt_session('55000000-0000-4000-8000-000000000205','55000000-0000-4000-8000-000000000302',transaction_timestamp()+interval '2 days',transaction_timestamp()+interval '2 days 1 hour','Same  notes')$$,$$select '55000000-0000-4000-8000-000000000302'::uuid,'55000000-0000-4000-8000-000000000205'::uuid,true$$,'A-008: exact session UUID/slot/normalized-notes retry returns the original reservation');
select is(pg_temp.boundary_error($$select * from public.schedule_pt_session('55000000-0000-4000-8000-000000000205','55000000-0000-4000-8000-000000000302',transaction_timestamp()+interval '2 days',transaction_timestamp()+interval '2 days 1 hour','Changed notes')$$),'GL052:idempotency_conflict','A-008: changed schedule retry remains a named conflict');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory' and granted and ((classid::bigint<<32)|objid::bigint)=hashtextextended('addon-order:55000000-0000-4000-8000-000000000001:55000000-0000-4000-8000-000000000205',0)),'A-009/A-012: schedule holds the exact shared order advisory lock');

set local role postgres;
select set_config('request.jwt.claims','',true);
create temp table accepted(order_id uuid,payment_id uuid,initial_session_id uuid,replayed boolean);
grant select,insert on accepted to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"55000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"55000000-0000-4000-8000-000000000001","staff_id":"55000000-0000-4000-8000-000000000021"}',true);
insert into accepted select * from public.record_addon_sale('55000000-0000-4000-8000-000000000031','55000000-0000-4000-8000-000000000101',1,(select quote_version from public.addon_products where id='55000000-0000-4000-8000-000000000101'),null,null,null,'cash',null,'55000000-0000-4000-8000-000000000401');
select is(pg_temp.boundary_error($$update public.addon_orders set sale_snapshot=null where id=(select order_id from accepted)$$),'GL053:order_is_a_record','A-005: accepted disclosure cannot be erased');
select is(pg_temp.boundary_error($$update public.addon_orders set sale_request=jsonb_set(sale_request,'{reason}','"replacement"') where id=(select order_id from accepted)$$),'GL053:order_is_a_record','A-005: accepted request facts cannot be replaced');
select ok(pg_temp.boundary_error($$update public.addon_orders set status='refunded' where id=(select order_id from accepted)$$) is not null,'A-012: paid active sale cannot claim full return without any completed refund');

select * from finish();
rollback;

