-- Frozen A-001/A-005/A-008/A-012: narrow projections and private capabilities.
-- Independent visible author; no production, migration or holdout was read.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(57);

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('57000000-0000-4000-8000-000000000001','Acceptance evidence tests','ADD57A','active','Asia/Kolkata','INR');
insert into auth.users(id) values ('57000000-0000-4000-8000-000000000901'),('57000000-0000-4000-8000-000000000902'),('57000000-0000-4000-8000-000000000903');
insert into public.staff(id,tenant_id,user_id,role,full_name) values
 ('57000000-0000-4000-8000-000000000021','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000901','gym_owner','Owner'),
 ('57000000-0000-4000-8000-000000000022','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000902','trainer','Trainer');
insert into public.branches(id,tenant_id,name,is_default) values
 ('57000000-0000-4000-8000-000000000011','57000000-0000-4000-8000-000000000001','Main',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('57000000-0000-4000-8000-000000000031','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000011','Primary member','+915700000031','active'),
 ('57000000-0000-4000-8000-000000000032','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000011','Other member','+915700000032','active');
update public.members set user_id='57000000-0000-4000-8000-000000000903' where id='57000000-0000-4000-8000-000000000031';
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,session_count,trainer_staff_id,trainer_qualification,cancellation_terms) values
 ('57000000-0000-4000-8000-000000000101','57000000-0000-4000-8000-000000000001','pt_package','Free PT','Two PT sessions',0,30,2,'57000000-0000-4000-8000-000000000022','Gym qualification','Cancel before delivery'),
 ('57000000-0000-4000-8000-000000000102','57000000-0000-4000-8000-000000000001','diet_plan','Free diet','Diet disclosure',0,30,null,null,null,'Cancel before delivery');
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 ('57000000-0000-4000-8000-000000000401','57000000-0000-4000-8000-000000000001','Other membership',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,price_paise) values
 ('57000000-0000-4000-8000-000000000402','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000032','57000000-0000-4000-8000-000000000401',10000);
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,status,method,recorded_by_staff_id,receipt_number,paid_at) values
 ('57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000031',null,10000,'paid','cash','57000000-0000-4000-8000-000000000021','VISIBLE57A',transaction_timestamp()),
 ('57000000-0000-4000-8000-000000000502','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000032','57000000-0000-4000-8000-000000000402',10000,'paid','cash','57000000-0000-4000-8000-000000000021','VISIBLE57B',transaction_timestamp());


-- Seed complete legacy source rows to isolate the helper under test. Every DDL,
-- privilege and data change below is inside both a probe subtransaction and the
-- file rollback. No production function body or trigger definition is inspected.
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,stock_quantity,cancellation_terms)
values('57000000-0000-4000-8000-000000000103','57000000-0000-4000-8000-000000000001','product','Stock item','One item',10000,30,5,'No automatic restock');
set local session_replication_role=replica;
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,payment_id,trainer_staff_id,sessions_total,sessions_used,sold_by_staff_id,sold_at,starts_on,expires_on,sale_snapshot) values
 ('57000000-0000-4000-8000-000000000601','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000031','57000000-0000-4000-8000-000000000103','pending',1,10000,10000,'57000000-0000-4000-8000-000000000501',null,null,0,'57000000-0000-4000-8000-000000000021',null,null,null,'{"kind":"product","name":"Stock item","description":"One item","cancellationTerms":"No automatic restock","validityDays":30}'),
 ('57000000-0000-4000-8000-000000000602','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000031','57000000-0000-4000-8000-000000000101','active',1,0,0,null,'57000000-0000-4000-8000-000000000022',2,0,'57000000-0000-4000-8000-000000000021',transaction_timestamp(),(transaction_timestamp() at time zone 'Asia/Kolkata')::date,(transaction_timestamp() at time zone 'Asia/Kolkata')::date+29,'{"kind":"pt_package","name":"Free PT","description":"Two PT sessions","cancellationTerms":"Cancel before delivery","validityDays":30,"trainerQualification":"Gym qualification"}');
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status) values
 ('57000000-0000-4000-8000-000000000701','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000602','57000000-0000-4000-8000-000000000022','57000000-0000-4000-8000-000000000031',transaction_timestamp()-interval '2 hours',transaction_timestamp()-interval '1 hour','scheduled');
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id,idempotency_key) values
 ('57000000-0000-4000-8000-000000000801','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000501','refund',10000,'INR','requested','Full stock return','57000000-0000-4000-8000-000000000021','visible-capability-return');
set local session_replication_role=origin;

create function pg_temp.capability_evidence() returns jsonb language sql stable as $fn$
 select jsonb_build_object(
  'orders',(select jsonb_agg(to_jsonb(t) order by id) from public.addon_orders t where tenant_id='57000000-0000-4000-8000-000000000001'),
  'products',(select jsonb_agg(to_jsonb(t) order by id) from public.addon_products t where tenant_id='57000000-0000-4000-8000-000000000001'),
  'sessions',(select jsonb_agg(to_jsonb(t) order by id) from public.pt_sessions t where tenant_id='57000000-0000-4000-8000-000000000001'),
  'refunds',(select jsonb_agg(to_jsonb(t) order by id) from public.refunds t where tenant_id='57000000-0000-4000-8000-000000000001'),
  'payments',(select jsonb_agg(to_jsonb(t) order by id) from public.payments t where tenant_id='57000000-0000-4000-8000-000000000001'),
  'audit',(select jsonb_agg(to_jsonb(t) order by id) from public.audit_log t where tenant_id='57000000-0000-4000-8000-000000000001'));
$fn$;

create function pg_temp.projection_probe(p_case text) returns text language plpgsql as $fn$
declare
 v_claims jsonb:='{"sub":"57000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"member","tenant_id":"57000000-0000-4000-8000-000000000001","member_id":"57000000-0000-4000-8000-000000000031"}';
 v_state text;
begin
 if p_case='staff_id' then v_claims:=v_claims||'{"staff_id":"57000000-0000-4000-8000-000000000021"}';
 elsif p_case in ('sub','tenant_id','member_id') then v_claims:=jsonb_set(v_claims,array[p_case],'"not-a-uuid"');
 elsif p_case='role' then v_claims:=v_claims||'{"app_role":{"invalid":"role"}}';
 elsif p_case='preview' then v_claims:=v_claims||'{"impersonation_session_id":"57000000-0000-4000-8000-000000000999"}'; end if;
 perform set_config('request.jwt.claims',v_claims::text,true);
 set local role authenticated;
 begin perform public.read_member_addon_trainer_names();
 exception when others then v_state:=sqlstate; end;
 set local role postgres;
 return v_state;
end $fn$;
select is(pg_temp.projection_probe('control'),null::text,'A-001/NAV control: complete member identity reads safe trainer names');
select is(pg_temp.projection_probe('staff_id'),'42501','A-001/NAV: member trainer projection refuses any contradictory staff_id');
select is(pg_temp.projection_probe('sub'),'42501','A-001/NAV: malformed subject normalizes to not_permitted');
select is(pg_temp.projection_probe('tenant_id'),'42501','A-001/NAV: malformed tenant normalizes to not_permitted');
select is(pg_temp.projection_probe('member_id'),'42501','A-001/NAV: malformed member normalizes to not_permitted');
select is(pg_temp.projection_probe('role'),'42501','A-001/NAV: malformed role normalizes to not_permitted');
select is(pg_temp.projection_probe('preview'),'42501','A-001/NAV: member trainer projection refuses impersonation');
select set_config('request.jwt.claims','',true);

-- Isolate each private helper at its real source relation. Removing the other
-- triggers and RLS inside this rolled-back probe prevents an outer invoker guard
-- from accidentally proving the private definer's own capability check for it.
-- Positive controls require that each exact source operation really can run.
create function pg_temp.capability_probe(p_helper text,p_case text) returns jsonb language plpgsql as $fn$
declare
 v_source text:=case when p_helper='apply_addon_refund_effect' then 'refunds'
  when p_helper in ('apply_pt_session_effect','lock_addon_order_for_pt_session') then 'pt_sessions' else 'addon_orders' end;
 v_timing text:=case when p_helper like 'lock_%' then 'before' else 'after' end;
 v_id uuid:=case when v_source='refunds' then '57000000-0000-4000-8000-000000000801'::uuid
  when v_source='pt_sessions' then '57000000-0000-4000-8000-000000000701'::uuid else '57000000-0000-4000-8000-000000000601'::uuid end;
 v_target text; v_command text; v_state text; v_detail text; v_before jsonb; v_after jsonb; v_result jsonb;
 v_claims jsonb:='{"sub":"57000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000021"}';
begin
 set local role postgres;
 perform set_config('request.jwt.claims','',true);
 set constraints all deferred;
 if p_helper='apply_addon_refund_effect' then
  set local session_replication_role=replica;
  update public.addon_orders set status='paid',sold_at=transaction_timestamp() where id='57000000-0000-4000-8000-000000000601';
  set local session_replication_role=origin;
 end if;
 v_before:=pg_temp.capability_evidence();
 if p_case='wrong_table' then
  execute format('create temp table forged_source (like public.%I including defaults)',v_source);
  execute format('insert into pg_temp.forged_source select * from public.%I where id=$1',v_source) using v_id;
  v_target:='pg_temp.forged_source';
 else
  execute format('alter table public.%I disable trigger user',v_source);
  execute format('alter table public.%I disable row level security',v_source);
  v_target:=format('public.%I',v_source);
 end if;
 execute format('grant select,update,delete on %s to authenticated',v_target);
 execute format('create trigger visible_capability_probe %s %s on %s for each row execute function app.%I()',v_timing,case when p_case='wrong_operation' then 'delete' else 'update' end,v_target,p_helper);
 if p_case='missing_actor' then v_claims:=v_claims-'staff_id';
 elsif p_case='unknown_actor' then v_claims:=v_claims||'{"staff_id":"57000000-0000-4000-8000-000000000999"}';
 elsif p_case='foreign_tenant' then v_claims:=v_claims||'{"tenant_id":"57000000-0000-4000-8000-000000000099"}';
 elsif p_case='member_role' then v_claims:=v_claims-'staff_id'||'{"sub":"57000000-0000-4000-8000-000000000903","app_role":"member","member_id":"57000000-0000-4000-8000-000000000031"}';
 elsif p_case='preview' then v_claims:=v_claims||'{"impersonation_session_id":"57000000-0000-4000-8000-000000000999"}';
 elsif p_case='malformed_tenant' then v_claims:=v_claims||'{"tenant_id":"not-a-uuid"}';
 elsif p_case='wrong_subject' then v_claims:=v_claims||'{"sub":"57000000-0000-4000-8000-000000000903"}'; end if;
 v_command:=case when p_case='wrong_operation' then format('delete from %s where id=$1',v_target)
  when v_source='addon_orders' then format('update %s set status=''paid'',sold_at=transaction_timestamp() where id=$1',v_target)
  when v_source='pt_sessions' then format('update %s set status=''completed'' where id=$1',v_target)
  else format('update %s set status=''completed'',processed_at=transaction_timestamp() where id=$1',v_target) end;
 perform set_config('request.jwt.claims',v_claims::text,true);
 set local role authenticated;
 begin execute v_command using v_id;
 exception when others then get stacked diagnostics v_state=returned_sqlstate,v_detail=pg_exception_detail; end;
 set local role postgres;
 perform set_config('request.jwt.claims','',true);
 v_after:=pg_temp.capability_evidence();
 v_result:=jsonb_build_object('error',v_state,'detail',v_detail,'unchanged',v_before=v_after);
 raise exception using errcode='ZX002';
exception when sqlstate 'ZX002' then return v_result;
when others then get stacked diagnostics v_state=returned_sqlstate,v_detail=pg_exception_detail;
 return jsonb_build_object('harnessError',v_state,'detail',v_detail);
end $fn$;
create temp table capability_results(helper text,scenario text,result jsonb);
insert into capability_results select helper,scenario,pg_temp.capability_probe(helper,scenario)
from unnest(array['apply_addon_order_effects','apply_addon_refund_effect','apply_pt_session_effect','lock_addon_order_for_pt_session','lock_addon_product_for_order']) helper
cross join unnest(array['control','wrong_table','wrong_operation','missing_actor','unknown_actor','foreign_tenant','member_role','preview','malformed_tenant','wrong_subject']) scenario;
select ok(not result ? 'harnessError' and case when scenario='control' then result->>'error' is null when scenario in ('wrong_table','wrong_operation') then result->>'error' is not null and (result->>'unchanged')::boolean else result->>'error'='42501' and (result->>'unchanged')::boolean end,
 'A-005/A-008/A-012 capability '||helper||': '||scenario||case when scenario='control' then ' permits its authenticated owner source action' else ' refuses before changing source, stock, usage, return or audit evidence' end)
from capability_results order by helper,scenario;
select * from finish();
rollback;
