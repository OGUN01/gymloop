-- Frozen A-001/A-002/A-005/A-006/A-008: direct writes obey the sale contract.
-- Independent visible author; no production, migration or holdout was read.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(16);

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('56000000-0000-4000-8000-000000000001','Acceptance evidence tests','ADD56A','active','Asia/Kolkata','INR');
insert into auth.users(id) values ('56000000-0000-4000-8000-000000000901'),('56000000-0000-4000-8000-000000000902'),('56000000-0000-4000-8000-000000000903');
insert into public.staff(id,tenant_id,user_id,role,full_name) values
 ('56000000-0000-4000-8000-000000000021','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000901','gym_owner','Owner'),
 ('56000000-0000-4000-8000-000000000022','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000902','trainer','Trainer');
insert into public.branches(id,tenant_id,name,is_default) values
 ('56000000-0000-4000-8000-000000000011','56000000-0000-4000-8000-000000000001','Main',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('56000000-0000-4000-8000-000000000031','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000011','Primary member','+915600000031','active'),
 ('56000000-0000-4000-8000-000000000032','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000011','Other member','+915600000032','active');
update public.members set user_id='56000000-0000-4000-8000-000000000903' where id='56000000-0000-4000-8000-000000000031';
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,session_count,trainer_staff_id,trainer_qualification,cancellation_terms) values
 ('56000000-0000-4000-8000-000000000101','56000000-0000-4000-8000-000000000001','pt_package','Free PT','Two PT sessions',0,30,2,'56000000-0000-4000-8000-000000000022','Gym qualification','Cancel before delivery'),
 ('56000000-0000-4000-8000-000000000102','56000000-0000-4000-8000-000000000001','diet_plan','Free diet','Diet disclosure',0,30,null,null,null,'Cancel before delivery');
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 ('56000000-0000-4000-8000-000000000401','56000000-0000-4000-8000-000000000001','Other membership',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,price_paise) values
 ('56000000-0000-4000-8000-000000000402','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000032','56000000-0000-4000-8000-000000000401',10000);
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,status,method,recorded_by_staff_id,receipt_number,paid_at) values
 ('56000000-0000-4000-8000-000000000501','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000031',null,10000,'paid','cash','56000000-0000-4000-8000-000000000021','VISIBLE56A',transaction_timestamp()),
 ('56000000-0000-4000-8000-000000000502','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000032','56000000-0000-4000-8000-000000000402',10000,'paid','cash','56000000-0000-4000-8000-000000000021','VISIBLE56B',transaction_timestamp());

create function pg_temp.acceptance_evidence(p_order uuid) returns jsonb language sql stable as $fn$
 select jsonb_build_object(
   'order',(select to_jsonb(o) from public.addon_orders o where id=p_order),
   'sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.pt_sessions s where addon_order_id=p_order),
   'payments',(select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id='56000000-0000-4000-8000-000000000001'),
   'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id='56000000-0000-4000-8000-000000000001'));
$fn$;

-- The outer exception rolls back each entire probe, including trusted fixture
-- preparation. The inner exception tests the actual authenticated command and
-- records whether its failed statement preserved the pre-command evidence.
-- Only the preserve_usage case seeds a corrupt keyed pending row with triggers
-- disabled: it independently tests acceptance even after creation is repaired.
create function pg_temp.acceptance_probe(p_case text,p_kind public.addon_kind)
returns jsonb language plpgsql as $fn$
declare
 v_product public.addon_products%rowtype;
 v_order uuid:=gen_random_uuid(); v_session uuid:=gen_random_uuid();
 v_quantity integer:=case when p_case='quantity' then 2 else 1 end;
 v_insert_used integer:=case when p_case in ('created_usage','preserve_usage') then 1 else 0 end;
 v_accept_used integer:=case when p_case in ('preserve_usage','introduce_usage') then 1 else 0 end;
 v_time timestamptz:=case when p_case='backdated' then transaction_timestamp()-interval '10 days'
                        when p_case='future_dated' then transaction_timestamp()+interval '10 days' else transaction_timestamp() end;
 v_payment uuid:=case when p_case='own_payment' then '56000000-0000-4000-8000-000000000501'::uuid
                      when p_case='other_membership_payment' then '56000000-0000-4000-8000-000000000502'::uuid else null end;
 v_creation_test boolean:=p_case in ('created_usage','own_payment','other_membership_payment');
 v_before jsonb; v_after jsonb; v_result jsonb; v_state text; v_detail text;
 v_phase text:='preparation';
begin
 set constraints all deferred;
 select * into strict v_product from public.addon_products where tenant_id='56000000-0000-4000-8000-000000000001' and kind=p_kind;
 perform set_config('request.jwt.claims','{"sub":"56000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"56000000-0000-4000-8000-000000000001","staff_id":"56000000-0000-4000-8000-000000000021"}',true);
 if v_creation_test then
   v_phase:='creation';
   v_before:=pg_temp.acceptance_evidence(v_order);
 end if;
 begin
   if p_case='preserve_usage' then
     set local session_replication_role=replica;
   else
     set local role authenticated;
   end if;
   insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,
     unit_price_paise,total_paise,currency,payment_id,trainer_staff_id,sessions_total,sessions_used,
     sold_by_staff_id,idempotency_key,sale_snapshot,sale_request)
   values(v_order,'56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000031',v_product.id,
     'pending',v_quantity,0,0,'INR',v_payment,v_product.trainer_staff_id,v_product.session_count,v_insert_used,
     '56000000-0000-4000-8000-000000000021',gen_random_uuid()::text,
     jsonb_build_object('kind',p_kind,'name',v_product.name,'description',v_product.description,
       'cancellationTerms',v_product.cancellation_terms,'validityDays',v_product.validity_days,'trainerQualification',v_product.trainer_qualification),
     jsonb_build_object('memberId','56000000-0000-4000-8000-000000000031','productId',v_product.id::text,
       'quantity',v_quantity,'quoteVersion',v_product.quote_version::text,'trainerStaffId',v_product.trainer_staff_id::text,
       'initialStartsAt',case when p_kind='pt_package' then (transaction_timestamp()+interval '5 days')::text else null end,
       'initialEndsAt',case when p_kind='pt_package' then (transaction_timestamp()+interval '5 days 1 hour')::text else null end,
       'method',null,'reason','Complimentary contract test'));
   if p_case='preserve_usage' then
     set local session_replication_role=origin;
     set local role authenticated;
   end if;
   if v_creation_test then
     update public.addon_orders set status='cancelled' where id=v_order;
     set constraints all immediate;
   else
     if p_kind='pt_package' then
       insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status)
       values(v_session,'56000000-0000-4000-8000-000000000001',v_order,'56000000-0000-4000-8000-000000000022',
         '56000000-0000-4000-8000-000000000031',transaction_timestamp()+interval '5 days',transaction_timestamp()+interval '5 days 1 hour','scheduled');
       update public.addon_orders set initial_session_id=v_session where id=v_order;
     end if;
     -- Eligibility changes AFTER the pending order and initial reservation were
     -- validly prepared. An early RPC/insert check cannot satisfy this assertion.
     set local role postgres;
     perform set_config('request.jwt.claims','',true);
     if p_case in ('cancelled_member','blocked_member') then
       update public.members set status=case when p_case='cancelled_member' then 'cancelled'::public.member_status else 'blocked'::public.member_status end
       where id='56000000-0000-4000-8000-000000000031';
     elsif p_case='erased_member' then
       update public.members set erased_at=transaction_timestamp() where id='56000000-0000-4000-8000-000000000031';
     elsif p_case='inactive_trainer' then
       update public.staff set is_active=false where id='56000000-0000-4000-8000-000000000022';
     elsif p_case='non_trainer' then
       update public.staff set role='front_desk' where id='56000000-0000-4000-8000-000000000022';
     end if;
     perform set_config('request.jwt.claims','{"sub":"56000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"56000000-0000-4000-8000-000000000001","staff_id":"56000000-0000-4000-8000-000000000021"}',true);
     set local role authenticated;
     v_before:=pg_temp.acceptance_evidence(v_order);
     v_phase:='acceptance';
     begin
       update public.addon_orders set status='paid',sessions_used=v_accept_used,sold_at=v_time,
         starts_on=case when v_time is not null then (v_time at time zone 'Asia/Kolkata')::date else null end,
         expires_on=case when v_time is not null then (v_time at time zone 'Asia/Kolkata')::date+29 else null end
       where id=v_order;
       update public.addon_orders set status='active' where id=v_order;
       set constraints all immediate;
     exception when others then
       get stacked diagnostics v_state=returned_sqlstate,v_detail=pg_exception_detail;
     end;
   end if;
 exception when others then
   get stacked diagnostics v_state=returned_sqlstate,v_detail=pg_exception_detail;
 end;
 v_after:=pg_temp.acceptance_evidence(v_order);
 v_result:=jsonb_build_object('phase',v_phase,'error',v_state,'detail',v_detail,'unchanged',v_before=v_after,
   'serverTime',transaction_timestamp(),'localToday',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,
   'order',v_after->'order','completedSessions',(select count(*) from public.pt_sessions where addon_order_id=v_order and status='completed'));
 raise exception using errcode='ZX001';
exception when sqlstate 'ZX001' then return v_result;
when others then
 get stacked diagnostics v_state=returned_sqlstate,v_detail=pg_exception_detail;
 return jsonb_build_object('harnessError',v_state,'detail',v_detail,'phase',v_phase);
end $fn$;

create temp table acceptance_results(label text primary key,result jsonb);
insert into acceptance_results values
 ('control_pt',pg_temp.acceptance_probe('control','pt_package')),
 ('control_diet',pg_temp.acceptance_probe('control','diet_plan')),
 ('created_usage',pg_temp.acceptance_probe('created_usage','pt_package')),
 ('preserve_usage',pg_temp.acceptance_probe('preserve_usage','pt_package')),
 ('introduce_usage',pg_temp.acceptance_probe('introduce_usage','pt_package')),
 ('backdated',pg_temp.acceptance_probe('backdated','diet_plan')),
 ('future_dated',pg_temp.acceptance_probe('future_dated','diet_plan')),
 ('pt_quantity',pg_temp.acceptance_probe('quantity','pt_package')),
 ('diet_quantity',pg_temp.acceptance_probe('quantity','diet_plan')),
 ('own_payment',pg_temp.acceptance_probe('own_payment','diet_plan')),
 ('other_membership_payment',pg_temp.acceptance_probe('other_membership_payment','diet_plan')),
 ('cancelled_member',pg_temp.acceptance_probe('cancelled_member','diet_plan')),
 ('blocked_member',pg_temp.acceptance_probe('blocked_member','diet_plan')),
 ('erased_member',pg_temp.acceptance_probe('erased_member','diet_plan')),
 ('inactive_trainer',pg_temp.acceptance_probe('inactive_trainer','pt_package')),
 ('non_trainer',pg_temp.acceptance_probe('non_trainer','pt_package'));

select ok((result->>'error') is null and not result ? 'harnessError' and result#>>'{order,status}'='active' and (result#>>'{order,sessions_used}')::integer=0 and (result->>'completedSessions')::integer=0,'A-005/A-008 control: valid keyed PT acceptance starts with zero actual usage') from acceptance_results where label='control_pt';
select ok((result->>'error') is null and not result ? 'harnessError' and result#>>'{order,status}'='active','A-005 control: valid keyed complimentary diet acceptance succeeds') from acceptance_results where label='control_diet';
select ok(result->>'phase'='creation' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-002/A-005: newly keyed pending PT cannot carry nonzero usage even if cancelled') from acceptance_results where label='created_usage';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-005/A-008: acceptance refuses preexisting fabricated PT usage and preserves evidence') from acceptance_results where label='preserve_usage';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-005/A-008: acceptance cannot introduce PT usage without a completed session') from acceptance_results where label='introduce_usage';
select ok(not result ? 'harnessError' and ((result->>'error' is not null and (result->>'unchanged')::boolean) or ((result#>>'{order,sold_at}')::timestamptz=(result->>'serverTime')::timestamptz and (result#>>'{order,starts_on}')::date=(result->>'localToday')::date and (result#>>'{order,expires_on}')::date=(result->>'localToday')::date+29)),'A-003/A-005: a supplied past sold_at cannot backdate acceptance or its validity') from acceptance_results where label='backdated';
select ok(not result ? 'harnessError' and ((result->>'error' is not null and (result->>'unchanged')::boolean) or ((result#>>'{order,sold_at}')::timestamptz=(result->>'serverTime')::timestamptz and (result#>>'{order,starts_on}')::date=(result->>'localToday')::date and (result#>>'{order,expires_on}')::date=(result->>'localToday')::date+29)),'A-003/A-005: a supplied future sold_at cannot postpone acceptance or its validity') from acceptance_results where label='future_dated';
select ok(result->>'error' is not null and not result ? 'harnessError','A-005/A-008: a keyed PT quantity above one is refused at the table boundary') from acceptance_results where label='pt_quantity';
select ok(result->>'error' is not null and not result ? 'harnessError','A-005: a keyed diet quantity above one is refused at the table boundary') from acceptance_results where label='diet_quantity';
select ok(result->>'phase'='creation' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-006: complimentary pending-to-cancelled history cannot attach even its own member payment') from acceptance_results where label='own_payment';
select ok(result->>'phase'='creation' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-006: complimentary pending-to-cancelled history cannot attach another member membership payment') from acceptance_results where label='other_membership_payment';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-001/A-005: acceptance rechecks a now-cancelled member and preserves evidence') from acceptance_results where label='cancelled_member';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-001/A-005: acceptance rechecks a now-blocked member and preserves evidence') from acceptance_results where label='blocked_member';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-001/A-005: acceptance rechecks a now-erased member and preserves evidence') from acceptance_results where label='erased_member';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-001/A-008: acceptance rechecks an assigned trainer who became inactive') from acceptance_results where label='inactive_trainer';
select ok(result->>'phase'='acceptance' and result->>'error' is not null and (result->>'unchanged')::boolean,'A-001/A-008: acceptance rechecks an assigned staff row that is no longer a trainer') from acceptance_results where label='non_trainer';

select * from finish();
rollback;
