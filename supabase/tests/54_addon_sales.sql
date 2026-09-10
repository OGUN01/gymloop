-- Phase 6 visible database contract: add-on catalogue, sale, fulfilment and returns.
-- Derived only from the frozen A-001..A-012 / GL052..GL058 EARS contract.
-- The implementation and supabase/tests-holdout were not read. Every fixture rolls back.
-- Concurrency is proved here by the exact unique/conditional-write/lock mechanisms and
-- serial replay. The runner cannot open a second authenticated database connection.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(199);

-- ---------------------------------------------------------------------------
-- Exact schema, indexes, callable boundaries and private capabilities.
-- ---------------------------------------------------------------------------

select has_column('public','addon_products','trainer_qualification','catalogue stores the disclosed trainer qualification');
select has_column('public','addon_products','quote_version','catalogue stores the database quote version');
select has_column('public','addon_orders','sold_by_staff_id','orders attribute the accepting seller');
select has_column('public','addon_orders','idempotency_key','orders store the sale request key');
select has_column('public','addon_orders','sold_at','orders store the acceptance instant');
select has_column('public','addon_orders','sale_snapshot','orders freeze disclosed terms');
select has_column('public','addon_orders','sale_request','orders freeze normalized request evidence');
select has_column('public','addon_orders','initial_session_id','PT orders identify their initial reservation');

select results_eq($$select column_name::text collate "default",data_type::text collate "default",is_nullable::text collate "default" from information_schema.columns where table_schema='public' and table_name='addon_products' and column_name in ('trainer_qualification','quote_version') order by column_name$$,$$values ('quote_version'::text collate "default",'uuid'::text collate "default",'NO'::text collate "default"),('trainer_qualification'::text collate "default",'text'::text collate "default",'YES'::text collate "default")$$,'new catalogue columns have exact types and nullability');
select results_eq($$select column_name::text collate "default",data_type::text collate "default",is_nullable::text collate "default",column_default::text collate "default" from information_schema.columns where table_schema='public' and table_name='addon_orders' and column_name in ('idempotency_key','initial_session_id','sale_request','sale_snapshot','sold_at','sold_by_staff_id') order by column_name$$,$$values ('idempotency_key'::text collate "default",'text'::text collate "default",'YES'::text collate "default",null::text collate "default"),('initial_session_id'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default",null::text collate "default"),('sale_request'::text collate "default",'jsonb'::text collate "default",'YES'::text collate "default",null::text collate "default"),('sale_snapshot'::text collate "default",'jsonb'::text collate "default",'YES'::text collate "default",null::text collate "default"),('sold_at'::text collate "default",'timestamp with time zone'::text collate "default",'YES'::text collate "default",null::text collate "default"),('sold_by_staff_id'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default",null::text collate "default")$$,'new order columns are nullable compatibility fields with no defaults');

select ok((select conkey=(select array_agg(attnum order by ord) from unnest(array[(select attnum from pg_attribute where attrelid='public.addon_orders'::regclass and attname='tenant_id'),(select attnum from pg_attribute where attrelid='public.addon_orders'::regclass and attname='sold_by_staff_id')]) with ordinality x(attnum,ord)) and confkey=(select array_agg(attnum order by ord) from unnest(array[(select attnum from pg_attribute where attrelid='public.staff'::regclass and attname='tenant_id'),(select attnum from pg_attribute where attrelid='public.staff'::regclass and attname='id')]) with ordinality x(attnum,ord)) from pg_constraint where conrelid='public.addon_orders'::regclass and conname='addon_orders_tenant_id_sold_by_staff_id_fkey'),'seller foreign key is tenant-composite');
select ok((select confrelid='public.pt_sessions'::regclass and array_length(conkey,1)=2 and array_length(confkey,1)=2 from pg_constraint where conrelid='public.addon_orders'::regclass and conname='addon_orders_tenant_id_initial_session_id_fkey'),'initial session foreign key is tenant-composite');

select ok((select i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, idempotency_key)%' and pg_get_expr(i.indpred,i.indrelid)='(idempotency_key IS NOT NULL)' from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='addon_orders_tenant_id_idempotency_key_key'),'sale key uniqueness is tenant-scoped and partial');
select ok((select i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, payment_id)%' and pg_get_expr(i.indpred,i.indrelid)='(payment_id IS NOT NULL)' from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='addon_orders_tenant_id_payment_id_key'),'one payment buys at most one add-on order per tenant');
select ok(to_regclass('public.addon_orders_sold_by_staff_id_idx') is not null,'seller foreign key is indexed');
select ok(to_regclass('public.addon_orders_initial_session_id_idx') is not null,'initial session foreign key is indexed');
select ok(to_regclass('public.addon_orders_tenant_id_sold_at_idx') is not null,'accepted-order cohort time is tenant indexed');
select ok(to_regclass('public.pt_sessions_tenant_id_addon_order_id_status_idx') is not null,'PT reservation counting is tenant/order/status indexed');

select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and proretset and pronargs=10 from pg_proc where oid=to_regprocedure('public.record_addon_sale(uuid,uuid,integer,uuid,uuid,timestamptz,timestamptz,public.payment_method,text,uuid)')),'record_addon_sale is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and proretset and pronargs=5 from pg_proc where oid=to_regprocedure('public.schedule_pt_session(uuid,uuid,timestamptz,timestamptz,text)')),'schedule_pt_session is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and proretset and pronargs=2 from pg_proc where oid=to_regprocedure('public.finish_pt_session(uuid,public.pt_session_status)')),'finish_pt_session is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and proretset and pronargs=1 from pg_proc where oid=to_regprocedure('public.complete_addon_order(uuid)')),'complete_addon_order is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and proretset and pronargs=4 from pg_proc where oid=to_regprocedure('public.complete_manual_addon_refund(uuid,bigint,text,text)')),'complete_manual_addon_refund is the exact volatile invoker command');
select ok((select prosecdef and provolatile='s' and proconfig @> array['search_path=""'] and prorettype='jsonb'::regtype and pg_get_userbyid(proowner)='postgres' from pg_proc where oid=to_regprocedure('public.read_member_addon_returns(uuid)')),'member return read is the exact postgres-owned stable definer');

select ok((select count(*)=6 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')) from pg_proc p where p.oid in (to_regprocedure('public.record_addon_sale(uuid,uuid,integer,uuid,uuid,timestamptz,timestamptz,public.payment_method,text,uuid)'),to_regprocedure('public.schedule_pt_session(uuid,uuid,timestamptz,timestamptz,text)'),to_regprocedure('public.finish_pt_session(uuid,public.pt_session_status)'),to_regprocedure('public.complete_addon_order(uuid)'),to_regprocedure('public.complete_manual_addon_refund(uuid,bigint,text,text)'),to_regprocedure('public.read_member_addon_returns(uuid)'))),'all six public RPCs exist and are authenticated-only');
select ok(not has_table_privilege('authenticated','public.addon_orders','DELETE') and not has_table_privilege('authenticated','public.addon_orders','TRUNCATE') and not has_table_privilege('authenticated','public.payments','DELETE') and not has_table_privilege('authenticated','public.refunds','DELETE'),'financial and order history cannot be deleted by authenticated callers');
select ok(not exists(select 1 from pg_policies where schemaname='public' and tablename='refunds' and policyname='refunds_member_select'),'refunds retain no direct member SELECT policy');

-- ---------------------------------------------------------------------------
-- Fixtures. New columns below intentionally make this suite red before Phase 6.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('54000000-0000-4000-8000-000000000001','Add-on Visible A','ADD54A','active','Asia/Kolkata','INR'),
 ('54000000-0000-4000-8000-000000000002','Add-on Visible B','ADD54B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('54000000-0000-4000-8000-000000000011','54000000-0000-4000-8000-000000000001','Main',true),
 ('54000000-0000-4000-8000-000000000012','54000000-0000-4000-8000-000000000002','Main',true);
insert into auth.users(id) values
 ('54000000-0000-4000-8000-000000000901'),('54000000-0000-4000-8000-000000000902'),
 ('54000000-0000-4000-8000-000000000903'),('54000000-0000-4000-8000-000000000904'),
 ('54000000-0000-4000-8000-000000000905'),('54000000-0000-4000-8000-000000000906'),
 ('54000000-0000-4000-8000-000000000907'),('54000000-0000-4000-8000-000000000908'),
 ('54000000-0000-4000-8000-000000000909');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('54000000-0000-4000-8000-000000000021','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000901','54000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('54000000-0000-4000-8000-000000000022','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000902','54000000-0000-4000-8000-000000000011','gym_manager','Manager A',true),
 ('54000000-0000-4000-8000-000000000023','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000903','54000000-0000-4000-8000-000000000011','front_desk','Desk A1',true),
 ('54000000-0000-4000-8000-000000000024','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000904','54000000-0000-4000-8000-000000000011','front_desk','Desk A2',true),
 ('54000000-0000-4000-8000-000000000025','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000905','54000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('54000000-0000-4000-8000-000000000029','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000909','54000000-0000-4000-8000-000000000011','trainer','Trainer A2',true),
 ('54000000-0000-4000-8000-000000000026','54000000-0000-4000-8000-000000000001',null,'54000000-0000-4000-8000-000000000011','trainer','Inactive Trainer A',false),
 ('54000000-0000-4000-8000-000000000027','54000000-0000-4000-8000-000000000002','54000000-0000-4000-8000-000000000906','54000000-0000-4000-8000-000000000012','front_desk','Desk B',true),
 ('54000000-0000-4000-8000-000000000028','54000000-0000-4000-8000-000000000002','54000000-0000-4000-8000-000000000907','54000000-0000-4000-8000-000000000012','trainer','Trainer B',true);
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status,erased_at) values
 ('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000908','54000000-0000-4000-8000-000000000011','Member A','+915400000031','active',null),
 ('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000001',null,'54000000-0000-4000-8000-000000000011','Member A2','+915400000032','active',null),
 ('54000000-0000-4000-8000-000000000033','54000000-0000-4000-8000-000000000001',null,'54000000-0000-4000-8000-000000000011','Cancelled A','+915400000033','cancelled',null),
 ('54000000-0000-4000-8000-000000000034','54000000-0000-4000-8000-000000000001',null,'54000000-0000-4000-8000-000000000011','Blocked A','+915400000034','blocked',null),
 ('54000000-0000-4000-8000-000000000035','54000000-0000-4000-8000-000000000001',null,'54000000-0000-4000-8000-000000000011','Erased A','+915400000035','active',transaction_timestamp()),
 ('54000000-0000-4000-8000-000000000036','54000000-0000-4000-8000-000000000002',null,'54000000-0000-4000-8000-000000000012','Member B','+915400000036','active',null);

insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,session_count,trainer_staff_id,trainer_qualification,stock_quantity,cancellation_terms,is_active) values
 ('54000000-0000-4000-8000-000000000101','54000000-0000-4000-8000-000000000001','product','BigInt product','Exact product',4000000000,'INR',7,null,null,null,8,'No automatic restock',true),
 ('54000000-0000-4000-8000-000000000102','54000000-0000-4000-8000-000000000001','diet_plan','Free diet','Complimentary diet',0,'INR',14,null,null,null,null,'Cancel before acceptance',true),
 ('54000000-0000-4000-8000-000000000103','54000000-0000-4000-8000-000000000001','pt_package','PT three','Three personal sessions',120000,'INR',30,3,'54000000-0000-4000-8000-000000000025','Gym-stated PT qualification',null,'Cancel scheduled sessions',true),
 ('54000000-0000-4000-8000-000000000104','54000000-0000-4000-8000-000000000001','product','Last item','One remaining',10000,'INR',2,null,null,null,1,'No automatic restock',true),
 ('54000000-0000-4000-8000-000000000105','54000000-0000-4000-8000-000000000001','product','Incomplete legacy',null,10000,'INR',null,null,null,null,2,null,false),
 ('54000000-0000-4000-8000-000000000106','54000000-0000-4000-8000-000000000001','product','USD offer','Unsupported',10000,'USD',2,null,null,null,2,'No conversion',true),
 ('54000000-0000-4000-8000-000000000107','54000000-0000-4000-8000-000000000002','product','Gym B product','Exact B',25000,'INR',7,null,null,null,4,'No automatic restock',true);

create temp table foreign_quote_probe as select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000107';
grant select on foreign_quote_probe to authenticated;

-- quote_version is database-owned and changes only with actual terms.
select ok((select quote_version is not null from public.addon_products where id='54000000-0000-4000-8000-000000000101'),'insert stamps a non-null quote version');
create temp table quote_probe as select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101';
update public.addon_products set stock_quantity=stock_quantity+1,sort_order=sort_order+1,gst_rate_bp=gst_rate_bp+1 where id='54000000-0000-4000-8000-000000000101';
select results_eq($$select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'$$,$$select quote_version from quote_probe$$,'stock, presentation order and unused GST metadata preserve the quote');
update public.addon_products set description='Changed exact product' where id='54000000-0000-4000-8000-000000000101';
select isnt((select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'),(select quote_version from quote_probe),'an acceptance-term edit rotates the quote');
update quote_probe set quote_version=(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101');
select lives_ok($$update public.addon_products set quote_version='54000000-0000-4000-8000-000000000999' where id='54000000-0000-4000-8000-000000000101'$$,'a client attempt to assign quote_version is ignored rather than trusted');
select results_eq($$select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'$$,$$select quote_version from quote_probe$$,'client quote-version spoofing preserves the database version');
select throws_ok($$update public.addon_products set is_active=true where id='54000000-0000-4000-8000-000000000105'$$,'GL055',null,'an incomplete legacy offer cannot be activated');
select lives_ok($$update public.addon_products set name='Incomplete legacy retained',is_active=false where id='54000000-0000-4000-8000-000000000105'$$,'incomplete legacy disclosure stays readable and may remain inactive');

create temp table sale_results(label text,order_id uuid,payment_id uuid,initial_session_id uuid,replayed boolean);
grant select,insert on sale_results to authenticated;
create temp table session_results(label text,session_id uuid,order_id uuid,replayed boolean);
grant select,insert on session_results to authenticated;
create temp table finish_results(label text,session_id uuid,order_id uuid,session_status public.pt_session_status,order_status public.addon_order_status,replayed boolean);
grant select,insert on finish_results to authenticated;
create temp table order_results(label text,order_id uuid,order_status public.addon_order_status,replayed boolean);
grant select,insert on order_results to authenticated;
create temp table refund_completion_results(label text,refund_id uuid,order_id uuid,refund_status public.refund_status,order_status public.addon_order_status,processed_at timestamptz,replayed boolean);
grant select,insert on refund_completion_results to authenticated;

-- ---------------------------------------------------------------------------
-- A-001..A-007: positive sale, exact money, stock and request replay.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
set local role authenticated;
select lives_ok($$insert into sale_results select 'product-first',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'),null,null,null,'cash','  Paid  CAFÉ  ','54000000-0000-4000-8000-000000000201') s$$,'front office accepts an affirmatively selected positive product sale');
select results_eq($$select replayed,payment_id is not null,initial_session_id is null from sale_results where label='product-first'$$,$$select false,true,true$$,'first product sale returns one fresh order and payment only');
select results_eq($$select o.status::text,o.quantity,o.unit_price_paise,o.total_paise,o.currency,o.sessions_used,o.sessions_total,o.trainer_staff_id,o.initial_session_id,o.sold_by_staff_id,o.idempotency_key from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'$$,$$select 'completed'::text,2,4000000000::bigint,8000000000::bigint,'INR'::text,0,null::integer,null::uuid,null::uuid,'54000000-0000-4000-8000-000000000023'::uuid,'54000000-0000-4000-8000-000000000201'::text$$,'product sale freezes attributed bigint money and completes immediately');
select results_eq($$select (select count(*) from jsonb_object_keys(o.sale_snapshot)),o.sale_snapshot->>'kind',o.sale_snapshot->>'name',o.sale_snapshot->>'description',o.sale_snapshot->>'cancellationTerms',(o.sale_snapshot->>'validityDays')::integer,o.sale_snapshot->'trainerQualification' from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'$$,$$select 6::bigint,'product'::text,'BigInt product'::text,'Changed exact product'::text,'No automatic restock'::text,7,'null'::jsonb$$,'sale snapshot has exactly the six disclosed product facts');
select results_eq($$select (select count(*) from jsonb_object_keys(o.sale_request)),o.sale_request->>'memberId',o.sale_request->>'productId',(o.sale_request->>'quantity')::integer,o.sale_request->>'quoteVersion',o.sale_request->'trainerStaffId',o.sale_request->'initialStartsAt',o.sale_request->'initialEndsAt',o.sale_request->>'method',o.sale_request->>'reason' from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'$$,$$select 9::bigint,'54000000-0000-4000-8000-000000000031'::text,'54000000-0000-4000-8000-000000000101'::text,2,(select quote_version::text from public.addon_products where id='54000000-0000-4000-8000-000000000101'),'null'::jsonb,'null'::jsonb,'null'::jsonb,'cash'::text,'Paid  CAFÉ'::text$$,'sale request has exactly nine normalized facts with explicit nulls');
select results_eq($$select p.tenant_id,p.member_id,p.amount_paise,p.currency,p.status::text,p.method::text,p.recorded_by_staff_id,p.membership_id,p.mandate_id,p.coupon_id,p.provider,p.provider_order_id,p.provider_payment_id,p.idempotency_key,p.notes,p.paid_at is not null,p.receipt_number is not null from public.payments p join sale_results x on x.payment_id=p.id where x.label='product-first'$$,$$select '54000000-0000-4000-8000-000000000001'::uuid,'54000000-0000-4000-8000-000000000031'::uuid,8000000000::bigint,'INR'::text,'paid'::text,'cash'::text,'54000000-0000-4000-8000-000000000023'::uuid,null::uuid,null::uuid,null::uuid,null::text,null::text,null::text,'addon-sale:54000000-0000-4000-8000-000000000201'::text,'Paid  CAFÉ'::text,true,true$$,'positive sale creates one ordinary arrived manual payment with no membership or provider fields');
select results_eq($$select stock_quantity from public.addon_products where id='54000000-0000-4000-8000-000000000101'$$,$$select 7$$,'product stock decrements by quantity exactly once');
select results_eq($$select o.starts_on,o.expires_on,o.sold_at is not null,o.expires_on-o.starts_on from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'$$,$$select (sold_at at time zone 'Asia/Kolkata')::date,(sold_at at time zone 'Asia/Kolkata')::date+6,true,6 from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'$$,'inclusive validity derives from the frozen acceptance instant in gym time');
select results_eq($$select count(*) from public.memberships where member_id='54000000-0000-4000-8000-000000000031'$$,$$select 0::bigint$$,'an add-on payment grants no membership period');
select ok((select exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory')),'sale key/order processing holds a transaction advisory lock');

set local role postgres;
select set_config('request.jwt.claims','',true);
create temp table product_replay_before as select (select to_jsonb(o) from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first') order_row,(select to_jsonb(p) from public.payments p join sale_results x on x.payment_id=p.id where x.label='product-first') payment_row,(select stock_quantity from public.addon_products where id='54000000-0000-4000-8000-000000000101') stock,(select count(*) from public.audit_log where tenant_id='54000000-0000-4000-8000-000000000001') audits;
update public.addon_products set price_paise=4100000000,is_active=false where id='54000000-0000-4000-8000-000000000101';
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
set local role authenticated;
select lives_ok($$insert into sale_results select 'product-replay',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201') s$$,'exact retry resolves before current offer edits or deactivation');
select results_eq($$select a.order_id=b.order_id,a.payment_id=b.payment_id,a.initial_session_id is not distinct from b.initial_session_id,b.replayed from sale_results a join sale_results b on b.label='product-replay' where a.label='product-first'$$,$$select true,true,true,true$$,'exact retry returns the original ids and replayed true');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select (select to_jsonb(o) from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),(select to_jsonb(p) from public.payments p join sale_results x on x.payment_id=p.id where x.label='product-first'),(select stock_quantity from public.addon_products where id='54000000-0000-4000-8000-000000000101'),(select count(*) from public.audit_log where tenant_id='54000000-0000-4000-8000-000000000001')$$,$$select order_row,payment_row,stock,audits from product_replay_before$$,'replay writes no order, payment, stock or audit change');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay member is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000104',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay product is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',3,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay quantity is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,'54000000-0000-4000-8000-000000000998',null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay quote is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),'54000000-0000-4000-8000-000000000025',null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay trainer is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,transaction_timestamp(),null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay slot start is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,transaction_timestamp(),'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay slot end is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'upi','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay method is idempotency_conflict');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay reason case is idempotency_conflict');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000024"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='product-first'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$$,'GL052',null,'changed replay seller is idempotency_conflict');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000002","staff_id":"54000000-0000-4000-8000-000000000027"}',true);
select lives_ok($$insert into sale_results select 'other-gym-key',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000036','54000000-0000-4000-8000-000000000107',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000107'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000201') s$$,'the same request key is independent in another gym');
select results_eq($$select count(distinct order_id) from sale_results where label in ('product-first','other-gym-key')$$,$$select 2::bigint$$,'tenant-scoped key creates distinct cross-gym orders');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select lives_ok($$insert into sale_results select 'free-diet',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'  Community  award  ','54000000-0000-4000-8000-000000000202') s$$,'complimentary diet acceptance requires and records its reason');
select results_eq($$select o.status::text,o.total_paise,o.payment_id,x.payment_id,o.sale_request->>'reason',o.sale_request->'method',o.sold_at is not null from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='free-diet'$$,$$select 'active'::text,0::bigint,null::uuid,null::uuid,'Community  award'::text,'null'::jsonb,true$$,'complimentary diet is active with no payment and immutable normalized evidence');
select results_eq($$select count(*) from public.payments where idempotency_key='addon-sale:54000000-0000-4000-8000-000000000202'$$,$$select 0::bigint$$,'complimentary acceptance creates no zero payment or receipt');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'   ','54000000-0000-4000-8000-000000000203')$$,'GL055',null,'complimentary acceptance refuses a blank reason');

select lives_ok($$insert into sale_results select 'last-stock',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000204') s$$,'the final in-stock unit sells successfully');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000205')$$,'GL057',null,'the next final-stock contender is insufficient_stock');
select results_eq($$select stock_quantity,(select count(*) from public.addon_orders where idempotency_key='54000000-0000-4000-8000-000000000205'),(select count(*) from public.payments where idempotency_key='addon-sale:54000000-0000-4000-8000-000000000205') from public.addon_products where id='54000000-0000-4000-8000-000000000104'$$,$$select 0,0::bigint,0::bigint$$,'failed stock sale leaves no negative stock, order, payment or consumed key');

set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role=replica;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active,quote_version) values ('54000000-0000-4000-8000-000000000108','54000000-0000-4000-8000-000000000001','product','Historical incomplete active',null,10000,'INR',7,2,null,true,'54000000-0000-4000-8000-000000000808');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000108',1,'54000000-0000-4000-8000-000000000808',null,null,null,'cash',null,'54000000-0000-4000-8000-000000000206')$$,'GL055',null,'active historical offer with incomplete disclosure is catalogue_incomplete');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000207')$$,'GL055',null,'inactive offer is offer_unavailable');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000107',1,(select quote_version from foreign_quote_probe),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000208')$$,'P0002',null,'foreign offer is indistinguishable from missing');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000106',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000106'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000209')$$,'GL055',null,'non-INR sale is unsupported_currency');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000033','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000210')$$,'GL055',null,'cancelled member is member_unavailable');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000034','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000211')$$,'GL055',null,'blocked member is member_unavailable');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000035','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000212')$$,'GL055',null,'erased member is member_unavailable');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000036','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000213')$$,'P0002',null,'foreign member is indistinguishable from missing');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000104',0,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000214')$$,'GL055',null,'zero quantity is invalid_quantity');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'reason','54000000-0000-4000-8000-000000000215')$$,'GL055',null,'diet quantity greater than one is invalid_quantity');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000104',1,'54000000-0000-4000-8000-000000000997',null,null,null,'cash',null,'54000000-0000-4000-8000-000000000216')$$,'GL055',null,'stale displayed offer version is quote_changed');

-- Invalid timezone, payment shape and arithmetic fail before any child survives.
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Not/A_Zone' where id='54000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'Gift','54000000-0000-4000-8000-000000000217')$$,'GL055',null,'invalid gym timezone is invalid_validity');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Asia/Kolkata' where id='54000000-0000-4000-8000-000000000001';
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active) values ('54000000-0000-4000-8000-000000000109','54000000-0000-4000-8000-000000000001','product','Overflow offer','Overflow must refuse',5000000000000000000,'INR',2,2,'No automatic restock',true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000109',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000109'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000218')$$,'GL055',null,'checked bigint multiplication refuses overflow as invalid_payment');
select results_eq($$select (select count(*) from public.addon_orders where idempotency_key in ('54000000-0000-4000-8000-000000000217','54000000-0000-4000-8000-000000000218')),(select count(*) from public.payments where idempotency_key in ('addon-sale:54000000-0000-4000-8000-000000000217','addon-sale:54000000-0000-4000-8000-000000000218'))$$,$$select 0::bigint,0::bigint$$,'invalid timezone and overflow consume no key and leave no payment');

-- ---------------------------------------------------------------------------
-- A-002/A-008/A-009: PT initial reservation, capacity, time and terminal replay.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into sale_results select 'pt-first',s.* from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000025',clock_timestamp()+interval '2 seconds',clock_timestamp()+interval '3 seconds','upi','  PT  intake  ','54000000-0000-4000-8000-000000000220') s$$,'PT sale atomically creates its explicitly selected initial slot');
select results_eq($$select o.status::text,o.sessions_total,o.sessions_used,o.trainer_staff_id,o.initial_session_id=x.initial_session_id,x.payment_id is not null,x.replayed from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='pt-first'$$,$$select 'active'::text,3,0,'54000000-0000-4000-8000-000000000025'::uuid,true,true,false$$,'PT acceptance freezes trainer, session budget and initial reservation identity');
select results_eq($$select s.id=x.initial_session_id,s.addon_order_id=x.order_id,s.tenant_id,s.member_id,s.trainer_staff_id,s.status::text,s.starts_at::text=o.sale_request->>'initialStartsAt',s.ends_at::text=o.sale_request->>'initialEndsAt' from public.pt_sessions s join sale_results x on x.initial_session_id=s.id join public.addon_orders o on o.id=x.order_id where x.label='pt-first'$$,$$select true,true,'54000000-0000-4000-8000-000000000001'::uuid,'54000000-0000-4000-8000-000000000031'::uuid,'54000000-0000-4000-8000-000000000025'::uuid,'scheduled'::text,true,true$$,'initial session exactly matches the frozen order and request');
select results_eq($$select (select count(*) from jsonb_object_keys(o.sale_snapshot)),o.sale_snapshot->>'kind',o.sale_snapshot->>'trainerQualification' from public.addon_orders o join sale_results x on x.order_id=o.id where x.label='pt-first'$$,$$select 6::bigint,'pt_package'::text,'Gym-stated PT qualification'::text$$,'PT snapshot freezes kind and gym-stated qualification');

select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000025',clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour','cash',null,'54000000-0000-4000-8000-000000000221')$$,'GL055',null,'PT quantity must equal one');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),null,clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour','cash',null,'54000000-0000-4000-8000-000000000222')$$,'GL055',null,'PT requested trainer must be present and match');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000026',clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour','cash',null,'54000000-0000-4000-8000-000000000223')$$,'GL055',null,'inactive or mismatched trainer is trainer_unavailable');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000028',clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour','cash',null,'54000000-0000-4000-8000-000000000224')$$,'P0002',null,'foreign trainer reference reveals no cross-tenant fact');
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000025',null,null,'cash',null,'54000000-0000-4000-8000-000000000225')$$,'22023',null,'PT sale requires both initial slot instants');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select lives_ok($$insert into session_results select 'second',s.* from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000301',clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour','  Keep  form  notes  ') s$$,'assigned trainer schedules a second reservation');
select results_eq($$select replayed from session_results where label='second'$$,$$select false$$,'first schedule is not replayed');
select results_eq($$select status::text,notes from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'$$,$$select 'scheduled'::text,'Keep  form  notes'::text$$,'schedule normalizes only outer note whitespace');
select lives_ok($$insert into session_results select 'second-replay',s.* from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000301',(select starts_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),'Keep  form  notes') s$$,'exact schedule retry succeeds');
select results_eq($$select a.session_id=b.session_id,b.replayed from session_results a join session_results b on b.label='second-replay' where a.label='second'$$,$$select true,true$$,'schedule replay returns the original UUID without write');
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000301',(select starts_at+interval '1 minute' from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),'Keep  form  notes')$$,'GL058',null,'same session UUID with changed slot is session_identity_mismatch');
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000301',(select starts_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),'keep  form  notes')$$,'GL058',null,'same session UUID with changed note case is session_identity_mismatch');
select lives_ok($$insert into session_results select 'third-adjacent',s.* from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000302',(select ends_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at+interval '1 hour' from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),null) s$$,'adjacent PT slots are valid');
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000303',clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 1 hour',null)$$,'GL058',null,'used plus scheduled cannot exceed the purchased reservation budget');
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000304',(select starts_at+interval '30 minutes' from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at+interval '30 minutes' from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),null)$$,'GL058',null,'budget refusal owns precedence before overlap while full');

select lives_ok($$insert into finish_results select 'cancel-second',f.* from public.finish_pt_session('54000000-0000-4000-8000-000000000301','cancelled') f$$,'trainer cancellation closes the reservation without usage');
select results_eq($$select session_status::text,order_status::text,replayed from finish_results where label='cancel-second'$$,$$select 'cancelled'::text,'active'::text,false$$,'cancellation preserves active order and is a first terminal command');
select results_eq($$select sessions_used from public.addon_orders where id=(select order_id from sale_results where label='pt-first')$$,$$select 0$$,'cancelled reservation consumes no session');
select lives_ok($$insert into session_results select 'replacement',s.* from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000303',clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 1 hour',null) s$$,'cancellation frees capacity for a new session UUID');
select throws_ok($$select * from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'completed')$$,'GL058',null,'a PT session cannot complete before its end');
select lives_ok($$select pg_sleep(3.2)$$,'the one-second initial slot reaches its server end before completion');
select lives_ok($$insert into finish_results select 'complete-initial',f.* from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'completed') f$$,'ended initial PT session completes');
select results_eq($$select sessions_used,status::text from public.addon_orders where id=(select order_id from sale_results where label='pt-first')$$,$$select 1,'active'::text$$,'scheduled to completed consumes exactly one and preserves active state before the last use');
select lives_ok($$insert into finish_results select 'complete-replay',f.* from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'completed') f$$,'same PT terminal command replays');
select results_eq($$select replayed,session_status::text from finish_results where label='complete-replay'$$,$$select true,'completed'::text$$,'PT completion replay is read only and reports stored state');
select throws_ok($$select * from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'no_show')$$,'GL058',null,'different PT terminal status is invalid_session_transition');
select throws_ok($$select * from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'scheduled')$$,'22023',null,'finish command accepts only terminal target statuses');

-- Both OLD and NEW trainer assignment checks under authenticated direct writes.
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000029"}',true);
select throws_ok($$update public.pt_sessions set status='no_show' where id='54000000-0000-4000-8000-000000000302'$$,'GL056',null,'trainer cannot change a session whose OLD assignment is another trainer');
select throws_ok($$insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status) values ('54000000-0000-4000-8000-000000000305','54000000-0000-4000-8000-000000000001',(select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000025','54000000-0000-4000-8000-000000000031',clock_timestamp()+interval '3 days',clock_timestamp()+interval '3 days 1 hour','scheduled')$$,'GL056',null,'trainer cannot INSERT a session whose NEW assignment is another trainer');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$update public.pt_sessions set trainer_staff_id='54000000-0000-4000-8000-000000000029' where id='54000000-0000-4000-8000-000000000302'$$,'GL053',null,'session identity is immutable even when NEW trainer differs');
select throws_ok($$update public.pt_sessions set notes='rewritten' where id='54000000-0000-4000-8000-000000000302'$$,'GL053',null,'scheduled slot notes are immutable after creation');

-- General completion belongs to product/diet only and is exactly replayable.
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select lives_ok($$insert into order_results select 'diet-complete',c.* from public.complete_addon_order((select order_id from sale_results where label='free-diet')) c$$,'front office explicitly completes an active diet plan');
select results_eq($$select order_status::text,replayed from order_results where label='diet-complete'$$,$$select 'completed'::text,false$$,'first diet completion reports completed and not replayed');
select lives_ok($$insert into order_results select 'diet-replay',c.* from public.complete_addon_order((select order_id from sale_results where label='free-diet')) c$$,'completed diet completion replays');
select results_eq($$select order_status::text,replayed from order_results where label='diet-replay'$$,$$select 'completed'::text,true$$,'diet replay is inert');
select lives_ok($$insert into order_results select 'product-replay',c.* from public.complete_addon_order((select order_id from sale_results where label='product-first')) c$$,'already completed product completion replays');
select results_eq($$select order_status::text,replayed from order_results where label='product-replay'$$,$$select 'completed'::text,true$$,'product replay reports stored completed state');
select throws_ok($$select * from public.complete_addon_order((select order_id from sale_results where label='pt-first'))$$,'GL055',null,'general completion refuses PT as wrong_order_kind');

-- ---------------------------------------------------------------------------
-- A-011/A-012: explicit manual return completion and truthful order effects.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);
create temp table refund_results(label text,refund_id uuid,replayed boolean);
grant select,insert on refund_results to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into refund_results select 'partial-request',r.* from public.record_refund((select payment_id from sale_results where label='pt-first'),20000,'INR','refund','  Partial  PT  return  ','54000000-0000-4000-8000-000000000401') r$$,'owner records a requested partial manual add-on refund');
select results_eq($$select r.status::text,r.amount_paise,r.currency,r.reason,r.processed_at from public.refunds r join refund_results x on x.refund_id=r.id where x.label='partial-request'$$,$$select 'requested'::text,20000::bigint,'INR'::text,'Partial  PT  return'::text,null::timestamptz$$,'refund request is reserved headroom rather than returned cash');
select lives_ok($$insert into refund_completion_results select 'partial-complete',c.* from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20000,'INR','Partial  PT  return') c$$,'owner explicitly confirms partial cash was returned');
select results_eq($$select refund_status::text,order_status::text,processed_at is not null,replayed from refund_completion_results where label='partial-complete'$$,$$select 'completed'::text,'active'::text,true,false$$,'partial completion stamps time and preserves active order');
select results_eq($$select status::text,sessions_used from public.addon_orders where id=(select order_id from sale_results where label='pt-first')$$,$$select 'active'::text,1$$,'partial returned money does not erase PT use');

set local role postgres;
select set_config('request.jwt.claims','',true);
create temp table refund_replay_before as select (select to_jsonb(r) from public.refunds r join refund_results x on x.refund_id=r.id where x.label='partial-request') refund_row,(select to_jsonb(o) from public.addon_orders o where id=(select order_id from sale_results where label='pt-first')) order_row,(select count(*) from public.audit_log where tenant_id='54000000-0000-4000-8000-000000000001') audits;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into refund_completion_results select 'partial-replay',c.* from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20000,'INR','Partial  PT  return') c$$,'exact completed refund confirmation replays');
select results_eq($$select replayed,processed_at=(select processed_at from refund_completion_results where label='partial-complete') from refund_completion_results where label='partial-replay'$$,$$select true,true$$,'refund replay preserves its original processing instant');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select (select to_jsonb(r) from public.refunds r join refund_results x on x.refund_id=r.id where x.label='partial-request'),(select to_jsonb(o) from public.addon_orders o where id=(select order_id from sale_results where label='pt-first')),(select count(*) from public.audit_log where tenant_id='54000000-0000-4000-8000-000000000001')$$,$$select refund_row,order_row,audits from refund_replay_before$$,'refund completion replay writes no refund, order or audit change');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select * from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20001,'INR','Partial  PT  return')$$,'GL048',null,'changed completed amount is the existing refund confirmation conflict');
select throws_ok($$select * from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20000,'USD','Partial  PT  return')$$,'GL048',null,'changed completed currency is the existing refund confirmation conflict');
select throws_ok($$select * from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20000,'INR','partial  PT  return')$$,'GL048',null,'changed completed reason is the existing refund confirmation conflict');

select lives_ok($$insert into refund_results select 'remaining-request',r.* from public.record_refund((select payment_id from sale_results where label='pt-first'),100000,'INR','reversal','Final returned balance','54000000-0000-4000-8000-000000000402') r$$,'owner records the remaining returned-money request');
select lives_ok($$insert into refund_completion_results select 'remaining-complete',c.* from public.complete_manual_addon_refund((select refund_id from refund_results where label='remaining-request'),100000,'INR','Final returned balance') c$$,'full completed returned sum is accepted');
select results_eq($$select status::text,sessions_used from public.addon_orders where id=(select order_id from sale_results where label='pt-first')$$,$$select 'refunded'::text,1$$,'full return moves eligible PT order to refunded without reducing completed usage');
select results_eq($$select id,status::text from public.pt_sessions where addon_order_id=(select order_id from sale_results where label='pt-first') order by (id=(select initial_session_id from sale_results where label='pt-first')) desc,id$$,$$values ((select initial_session_id from sale_results where label='pt-first'),'completed'::text),('54000000-0000-4000-8000-000000000301'::uuid,'cancelled'::text),('54000000-0000-4000-8000-000000000302'::uuid,'cancelled'::text),('54000000-0000-4000-8000-000000000303'::uuid,'cancelled'::text)$$,'full return cancels scheduled slots and preserves completed/cancelled PT history');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000306',clock_timestamp()+interval '4 days',clock_timestamp()+interval '4 days 1 hour',null)$$,'GL055',null,'fully returned order refuses later use as order_unavailable');

-- A full return against already-completed product history does not rewrite fulfilment or stock.
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into refund_results select 'product-full-request',r.* from public.record_refund((select payment_id from sale_results where label='product-first'),8000000000,'INR','refund','Physical return confirmed separately','54000000-0000-4000-8000-000000000403') r$$,'owner records full money return for a completed product');
select lives_ok($$insert into refund_completion_results select 'product-full-complete',c.* from public.complete_manual_addon_refund((select refund_id from refund_results where label='product-full-request'),8000000000,'INR','Physical return confirmed separately') c$$,'completed product return records actual returned cash');
select results_eq($$select o.status::text,p.stock_quantity from public.addon_orders o join sale_results x on x.order_id=o.id cross join public.addon_products p where x.label='product-first' and p.id='54000000-0000-4000-8000-000000000101'$$,$$select 'completed'::text,7$$,'terminal completed product remains completed and never auto-restocks');

-- ---------------------------------------------------------------------------
-- ADR-116 member return projection: identity, ownership and minimization.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role=replica;
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id,idempotency_key) values
 ('54000000-0000-4000-8000-000000000451','54000000-0000-4000-8000-000000000001',(select payment_id from sale_results where label='pt-first'),'refund',1,'INR','requested','Pending internal attempt','54000000-0000-4000-8000-000000000021','54000000-0000-4000-8000-000000000451'),
 ('54000000-0000-4000-8000-000000000452','54000000-0000-4000-8000-000000000001',(select payment_id from sale_results where label='pt-first'),'refund',1,'INR','failed','Failed internal attempt','54000000-0000-4000-8000-000000000021','54000000-0000-4000-8000-000000000452');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"54000000-0000-4000-8000-000000000001","member_id":"54000000-0000-4000-8000-000000000031"}',true);
select lives_ok($$select public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))$$,'complete verified member reads returns for their own order');
select results_eq($$select (select count(*) from jsonb_object_keys(j)),j ? 'orderId',jsonb_array_length(j->'returns') from (select public.read_member_addon_returns((select order_id from sale_results where label='pt-first')) j) q$$,$$select 2::bigint,true,2$$,'member projection has exactly orderId/returns and omits pending and failed attempts');
select results_eq($$select bool_and((select count(*) from jsonb_object_keys(e))=5 and e ?& array['refundId','kind','amountPaise','currency','processedAt'] and not (e ?| array['reason','initiatedByStaffId','providerRefundId','idempotencyKey','status'])) from jsonb_array_elements(public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))->'returns') e$$,$$select true$$,'each return exposes exactly five allowed fields and no internal fact');
select results_eq($$select e->>'kind',e->>'amountPaise',e->>'currency',(e->>'processedAt') is not null from jsonb_array_elements(public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))->'returns') with ordinality x(e,n) order by n$$,$$values ('refund'::text,'20000'::text,'INR'::text,true),('reversal'::text,'100000'::text,'INR'::text,true)$$,'completed returns preserve generated kind, decimal-string paise, currency and stable processing order');
select is_empty($$select * from public.refunds$$,'member direct SELECT on refunds returns no rows');
select results_eq($$select public.read_member_addon_returns((select order_id from sale_results where label='free-diet'))->'returns'$$,$$select '[]'::jsonb$$,'complimentary own order reports an empty return list');
select throws_ok($$select public.read_member_addon_returns((select order_id from sale_results where label='other-gym-key'))$$,'P0002',null,'foreign-tenant order is uniform not_found to a member');
select throws_ok($$select public.read_member_addon_returns('54000000-0000-4000-8000-000000000999')$$,'P0002',null,'missing order is the same not_found result');
select throws_ok($$select public.read_member_addon_returns(null)$$,'22023',null,'authorized member null order argument is invalid');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.read_member_addon_returns(null)$$,'42501',null,'identity authorization precedes null argument validation');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"54000000-0000-4000-8000-000000000001"}',true);
select throws_ok($$select public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))$$,'42501',null,'member identity missing member_id is refused');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"54000000-0000-4000-8000-000000000001","member_id":"54000000-0000-4000-8000-000000000031","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))$$,'42501',null,'contradictory member/staff identity is refused');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"54000000-0000-4000-8000-000000000001","member_id":"54000000-0000-4000-8000-000000000031","impersonation_session_id":"54000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.read_member_addon_returns((select order_id from sale_results where label='pt-first'))$$,'42501',null,'impersonation claim is refused by member return definer');

-- ---------------------------------------------------------------------------
-- RLS, role and direct-write record defenses.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'Owner cannot sell','54000000-0000-4000-8000-000000000230')$$,'42501',null,'owner role cannot invoke front-office sale command');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000307',clock_timestamp()+interval '4 days',clock_timestamp()+interval '4 days 1 hour',null)$$,'42501',null,'front desk cannot invoke trainer schedule command');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$select * from public.complete_addon_order((select order_id from sale_results where label='free-diet'))$$,'42501',null,'trainer cannot invoke front-office completion command');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"54000000-0000-4000-8000-000000000001","member_id":"54000000-0000-4000-8000-000000000031"}',true);
select throws_ok($$select * from public.complete_addon_order((select order_id from sale_results where label='free-diet'))$$,'42501',null,'member cannot invoke any add-on mutation command');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"54000000-0000-4000-8000-000000000001","impersonation_session_id":"54000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select * from public.complete_manual_addon_refund((select refund_id from refund_results where label='partial-request'),20000,'INR','Partial  PT  return')$$,'42501',null,'mutation definer/invoker path refuses impersonation');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$with changed as (update public.addon_orders set quantity=99 where id=(select order_id from sale_results where label='other-gym-key') returning 1) select count(*) from changed$$,$$select 0::bigint$$,'RLS filters direct update of another gym order to zero rows');
select throws_ok($$update public.addon_orders set quantity=3 where id=(select order_id from sale_results where label='product-first')$$,'GL053',null,'accepted order quantity is an immutable record fact');
select throws_ok($$update public.addon_orders set sale_snapshot=sale_snapshot||'{"extra":true}'::jsonb where id=(select order_id from sale_results where label='product-first')$$,'GL053',null,'accepted snapshot rejects extra client data');
select throws_ok($$update public.addon_orders set sessions_used=sessions_used+1 where id=(select order_id from sale_results where label='pt-first')$$,'GL053',null,'caller cannot directly manufacture PT usage');
select throws_ok($$update public.addon_orders set status='active' where id=(select order_id from sale_results where label='product-first')$$,'GL054',null,'completed order cannot leave its terminal state');
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values ('54000000-0000-4000-8000-000000000041','54000000-0000-4000-8000-000000000001','Fixture membership plan',30,100000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,price_paise) values ('54000000-0000-4000-8000-000000000061','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000041','pending',100000);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$update public.payments set membership_id='54000000-0000-4000-8000-000000000061' where id=(select payment_id from sale_results where label='product-first')$$,'GL038',null,'arrived add-on payment cannot later buy a membership');

set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'] and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app' and p.prosecdef and pg_get_functiondef(p.oid) like '%addon_%'),'every private elevated add-on helper has empty path and no user execute privilege');
select ok((select exists(select 1 from pg_trigger t where t.tgrelid='public.addon_orders'::regclass and not t.tgisinternal and pg_get_triggerdef(t.oid) like '%audit_money_change%')),'addon_orders are attached to the existing money audit writer');

-- Capture SQL DETAIL because throws_ok proves SQLSTATE/message, not DETAIL.
create or replace function pg_temp.captured_error(p_sql text)
returns table(returned_state text,detail text)
language plpgsql
as $fn$
begin
  execute p_sql;
  return query select null::text,null::text;
exception when others then
  get stacked diagnostics returned_state=returned_sqlstate,detail=pg_exception_detail;
  return next;
end
$fn$;
grant execute on function pg_temp.captured_error(text) to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000101',2,(select (sale_request->>'quoteVersion')::uuid from public.addon_orders where idempotency_key='54000000-0000-4000-8000-000000000201'),null,null,null,'cash','Paid  CAFÉ','54000000-0000-4000-8000-000000000201')$sql$)$$,$$values ('GL052'::text,'idempotency_conflict'::text)$$,'GL052 carries exact idempotency_conflict DETAIL');
select results_eq($$select * from pg_temp.captured_error($sql$update public.addon_orders set quantity=4 where id=(select order_id from sale_results where label='product-first')$sql$)$$,$$values ('GL053'::text,'order_is_a_record'::text)$$,'GL053 carries exact order_is_a_record DETAIL');
select results_eq($$select * from pg_temp.captured_error($sql$update public.addon_orders set status='active' where id=(select order_id from sale_results where label='product-first')$sql$)$$,$$values ('GL054'::text,'invalid_order_transition'::text)$$,'GL054 carries exact invalid_order_transition DETAIL');
select results_eq($$select * from pg_temp.captured_error($sql$update public.pt_sessions set notes='changed' where id='54000000-0000-4000-8000-000000000302'$sql$)$$,$$values ('GL053'::text,'session_is_a_record'::text)$$,'GL053 carries exact session_is_a_record DETAIL');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000108',1,'54000000-0000-4000-8000-000000000808',null,null,null,'cash',null,'54000000-0000-4000-8000-000000000240')$sql$)$$,$$values ('GL055'::text,'catalogue_incomplete'::text)$$,'GL055 identifies catalogue_incomplete exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000101',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000101'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000241')$sql$)$$,$$values ('GL055'::text,'offer_unavailable'::text)$$,'GL055 identifies offer_unavailable exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000104',1,'54000000-0000-4000-8000-000000000997',null,null,null,'cash',null,'54000000-0000-4000-8000-000000000242')$sql$)$$,$$values ('GL055'::text,'quote_changed'::text)$$,'GL055 identifies quote_changed exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000106',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000106'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000243')$sql$)$$,$$values ('GL055'::text,'unsupported_currency'::text)$$,'GL055 identifies unsupported_currency exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000033','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000244')$sql$)$$,$$values ('GL055'::text,'member_unavailable'::text)$$,'GL055 identifies member_unavailable exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000103'),'54000000-0000-4000-8000-000000000026',clock_timestamp()+interval '5 days',clock_timestamp()+interval '5 days 1 hour','cash',null,'54000000-0000-4000-8000-000000000245')$sql$)$$,$$values ('GL055'::text,'trainer_unavailable'::text)$$,'GL055 identifies trainer_unavailable exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'Gift','54000000-0000-4000-8000-000000000246')$sql$)$$,$$values ('GL055'::text,'invalid_quantity'::text)$$,'GL055 identifies invalid_quantity exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000109',2,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000109'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000247')$sql$)$$,$$values ('GL055'::text,'invalid_payment'::text)$$,'GL055 identifies checked-money overflow as invalid_payment');

set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Bad/Zone' where id='54000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'Gift','54000000-0000-4000-8000-000000000248')$sql$)$$,$$values ('GL055'::text,'invalid_validity'::text)$$,'GL055 identifies invalid_validity exactly');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Asia/Kolkata' where id='54000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$insert into public.addon_orders(tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request) values ('54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102','pending',1,0,0,'INR','54000000-0000-4000-8000-000000000023','54000000-0000-4000-8000-000000000249','{}','{}')$sql$)$$,$$values ('GL055'::text,'invalid_snapshot'::text)$$,'GL055 identifies invalid_snapshot exactly');
select results_eq($$select * from pg_temp.captured_error($sql$insert into public.addon_orders(tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request) values ('54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102','pending',1,0,0,'INR','54000000-0000-4000-8000-000000000024','54000000-0000-4000-8000-000000000250','{"kind":"diet_plan","name":"Free diet","description":"Complimentary diet","cancellationTerms":"Cancel before acceptance","validityDays":14,"trainerQualification":null}',jsonb_build_object('memberId','54000000-0000-4000-8000-000000000031','productId','54000000-0000-4000-8000-000000000102','quantity',1,'quoteVersion',(select quote_version::text from public.addon_products where id='54000000-0000-4000-8000-000000000102'),'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method',null,'reason','Gift'))$sql$)$$,$$values ('GL056'::text,'seller_not_yours'::text)$$,'GL056 identifies seller_not_yours exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.complete_addon_order((select order_id from sale_results where label='pt-first'))$sql$)$$,$$values ('GL055'::text,'order_unavailable'::text)$$,'fully returned order identifies order_unavailable exactly');
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.finish_pt_session((select initial_session_id from sale_results where label='pt-first'),'no_show')$sql$)$$,$$values ('GL058'::text,'invalid_session_transition'::text)$$,'GL058 identifies invalid_session_transition exactly');

set local role postgres;
select set_config('request.jwt.claims','',true);
set local session_replication_role=replica;
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on,sold_at) values
 ('54000000-0000-4000-8000-000000000501','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103','active',1,0,0,'INR','54000000-0000-4000-8000-000000000025',1,1,(clock_timestamp() at time zone 'Asia/Kolkata')::date,(clock_timestamp() at time zone 'Asia/Kolkata')::date+30,clock_timestamp()),
 ('54000000-0000-4000-8000-000000000502','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000103','active',1,0,0,'INR','54000000-0000-4000-8000-000000000025',2,0,(clock_timestamp() at time zone 'Asia/Kolkata')::date,(clock_timestamp() at time zone 'Asia/Kolkata')::date+30,clock_timestamp());
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status) values ('54000000-0000-4000-8000-000000000510','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000502','54000000-0000-4000-8000-000000000025','54000000-0000-4000-8000-000000000031',clock_timestamp()+interval '1 hour',clock_timestamp()+interval '2 hours','scheduled');
set local session_replication_role=origin;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.complete_addon_order('54000000-0000-4000-8000-000000000502')$sql$)$$,$$values ('GL055'::text,'wrong_order_kind'::text)$$,'GL055 identifies wrong_order_kind exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000104',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000104'),null,null,null,'cash',null,'54000000-0000-4000-8000-000000000251')$sql$)$$,$$values ('GL057'::text,'insufficient_stock'::text)$$,'GL057 identifies insufficient_stock exactly');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000025"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.schedule_pt_session('54000000-0000-4000-8000-000000000501','54000000-0000-4000-8000-000000000511',clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 1 hour',null)$sql$)$$,$$values ('GL058'::text,'session_budget_exhausted'::text)$$,'GL058 identifies session_budget_exhausted exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.schedule_pt_session('54000000-0000-4000-8000-000000000502','54000000-0000-4000-8000-000000000512',clock_timestamp()+interval '40 days',clock_timestamp()+interval '40 days 1 hour',null)$sql$)$$,$$values ('GL058'::text,'session_outside_validity'::text)$$,'GL058 identifies session_outside_validity exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.finish_pt_session('54000000-0000-4000-8000-000000000510','completed')$sql$)$$,$$values ('GL058'::text,'session_not_ended'::text)$$,'GL058 identifies session_not_ended exactly');
select results_eq($$select * from pg_temp.captured_error($sql$select * from public.schedule_pt_session((select order_id from sale_results where label='pt-first'),'54000000-0000-4000-8000-000000000301',(select starts_at+interval '1 minute' from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),(select ends_at from public.pt_sessions where id='54000000-0000-4000-8000-000000000301'),'Keep  form  notes')$sql$)$$,$$values ('GL058'::text,'session_identity_mismatch'::text)$$,'GL058 identifies session_identity_mismatch exactly');

create or replace function pg_temp.leave_unaccepted_order()
returns void language plpgsql as $fn$
begin
  insert into public.addon_orders(tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request)
  values ('54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102','pending',1,0,0,'INR','54000000-0000-4000-8000-000000000023','54000000-0000-4000-8000-000000000252','{"kind":"diet_plan","name":"Free diet","description":"Complimentary diet","cancellationTerms":"Cancel before acceptance","validityDays":14,"trainerQualification":null}',jsonb_build_object('memberId','54000000-0000-4000-8000-000000000031','productId','54000000-0000-4000-8000-000000000102','quantity',1,'quoteVersion',(select quote_version::text from public.addon_products where id='54000000-0000-4000-8000-000000000102'),'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method',null,'reason','Gift'));
  set constraints all immediate;
end $fn$;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select results_eq($$select * from pg_temp.captured_error('select pg_temp.leave_unaccepted_order()')$$,$$values ('GL055'::text,'unaccepted_order'::text)$$,'GL055 identifies a surviving pending keyed sale as unaccepted_order');

select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"trainer","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000029"}',true);
select results_eq($$select * from pg_temp.captured_error($sql$update public.pt_sessions set status='no_show' where id='54000000-0000-4000-8000-000000000510'$sql$)$$,$$values ('GL056'::text,'trainer_not_yours'::text)$$,'GL056 identifies trainer_not_yours exactly');

-- Every disallowed enum edge is invalid_order_transition; accepted edges are
-- exercised by sale, completion and full-return operations above.
set local role postgres;
select set_config('request.jwt.claims','',true);
create or replace function pg_temp.order_transition_matrix_ok()
returns boolean language plpgsql as $fn$
declare f public.addon_order_status; t public.addon_order_status; oid uuid; got text; invalid boolean;
begin
  for f in select unnest(enum_range(null::public.addon_order_status)) loop
    for t in select unnest(enum_range(null::public.addon_order_status)) loop
      invalid := (f='pending' and t in ('active','completed','refunded')) or
                 (f='paid' and t in ('pending','completed')) or
                 (f='active' and t in ('pending','paid','cancelled')) or
                 (f in ('completed','cancelled','refunded') and t<>f);
      if invalid then
        oid := gen_random_uuid();
        insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency)
        values (oid,'54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000031','54000000-0000-4000-8000-000000000102',f,1,0,0,'INR');
        begin
          update public.addon_orders set status=t where id=oid;
          return false;
        exception when others then
          get stacked diagnostics got=returned_sqlstate;
          if got<>'GL054' then return false; end if;
        end;
      end if;
    end loop;
  end loop;
  return true;
end $fn$;
select ok(pg_temp.order_transition_matrix_ok(),'all 21 disallowed addon_order_status enum pairs raise GL054');

-- Exact audit shape and atomicity.
select results_eq($$select count(*) from public.audit_log a join sale_results x on x.order_id=a.record_id where x.label='product-first' and a.action='addon_order.created'$$,$$select 1::bigint$$,'paid product sale writes one addon_order.created event');
select results_eq($$select a.record_type,a.tenant_id,a.actor_user_id,a.actor_role::text,a.reason,a."before" is null,(select array_agg(k order by k) from jsonb_object_keys(a."after") k)=(select array_agg(column_name::text order by column_name) from information_schema.columns where table_schema='public' and table_name='addon_orders' and column_name not in ('id','tenant_id','created_at','updated_at')) from public.audit_log a join sale_results x on x.order_id=a.record_id where x.label='product-first' and a.action='addon_order.created'$$,$$select 'addon_order'::text,'54000000-0000-4000-8000-000000000001'::uuid,'54000000-0000-4000-8000-000000000903'::uuid,'front_desk'::text,'Paid  CAFÉ'::text,true,true$$,'created audit has exact actor, reason and every domain column');
select results_eq($$select count(*),bool_and((select array_agg(k order by k) from jsonb_object_keys(a."before") k)=(select array_agg(column_name::text order by column_name) from information_schema.columns where table_schema='public' and table_name='addon_orders' and column_name not in ('id','tenant_id','created_at','updated_at')) and (select array_agg(k order by k) from jsonb_object_keys(a."after") k)=(select array_agg(column_name::text order by column_name) from information_schema.columns where table_schema='public' and table_name='addon_orders' and column_name not in ('id','tenant_id','created_at','updated_at'))) from public.audit_log a join sale_results x on x.order_id=a.record_id where x.label='product-first' and a.action='addon_order.updated'$$,$$select 3::bigint,true$$,'product acceptance writes exact before/after summaries for each database-derived transition');
select results_eq($$select count(*) from public.audit_log a join sale_results x on x.order_id=a.record_id where x.label='free-diet' and a.action in ('addon_order.created','addon_order.updated')$$,$$select 4::bigint$$,'complimentary acceptance plus explicit completion audits every accepted order write');

alter table public.audit_log add constraint visible_addon_audit_failure check (reason is distinct from 'Audit rollback') not valid;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"54000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"54000000-0000-4000-8000-000000000001","staff_id":"54000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select * from public.record_addon_sale('54000000-0000-4000-8000-000000000032','54000000-0000-4000-8000-000000000102',1,(select quote_version from public.addon_products where id='54000000-0000-4000-8000-000000000102'),null,null,null,null,'Audit rollback','54000000-0000-4000-8000-000000000260')$$,'23514',null,'audit failure rolls back an otherwise valid complimentary acceptance');
set local role postgres;
select set_config('request.jwt.claims','',true);
alter table public.audit_log drop constraint visible_addon_audit_failure;
select results_eq($$select (select count(*) from public.addon_orders where idempotency_key='54000000-0000-4000-8000-000000000260'),(select count(*) from public.audit_log where reason='Audit rollback')$$,$$select 0::bigint,0::bigint$$,'audit failure leaves no order, audit or consumed key');

select * from finish();
rollback;
