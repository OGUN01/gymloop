-- Independent visible SHP/MEDIA contract; implementation and holdout suites not read.
-- No assertion here claims PostgreSQL verifies R2 bytes. Edge owns that evidence.
-- Serial replay/lock metadata do not prove actual cross-connection races.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(202);

create function pg_temp.sid(n integer) returns uuid language sql immutable as $$select ('72000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text, t integer default 1, s integer default null, m integer default null, u integer default null, extra jsonb default '{}'::jsonb) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',(jsonb_strip_nulls(jsonb_build_object('role','authenticated','app_role',r,'tenant_id',pg_temp.sid(t),'staff_id',pg_temp.sid(s),'member_id',pg_temp.sid(m),'sub',pg_temp.sid(u)))||extra)::text,true); end$$;
-- Catch in a subtransaction, including DETAIL: refusals must roll back all effects.
create function pg_temp.refusal(q text) returns text language plpgsql as $$declare d text; c text; begin execute q; return 'NO ERROR'; exception when others then get stacked diagnostics c=returned_sqlstate,d=pg_exception_detail; return c||case when coalesce(d,'')='' then '' else ':'||d end; end$$;
create function pg_temp.stage(n integer,k text default 'product',t integer default 1) returns text language sql immutable as $$select pg_temp.sid(t)::text||'/staging/'||k||'/'||pg_temp.sid(n)::text||'.jpg'$$;
create function pg_temp.pub(n integer,k text default 'product',t integer default 1) returns text language sql immutable as $$select pg_temp.sid(t)::text||'/published/'||k||'/'||pg_temp.sid(n)::text||'.jpg'$$;
grant execute on function pg_temp.sid(integer),pg_temp.claim(text,integer,integer,integer,integer,jsonb),pg_temp.refusal(text),pg_temp.stage(integer,text,integer),pg_temp.pub(integer,text,integer) to authenticated,anon,service_role;
create temp table captured(label text primary key,id uuid,expiry timestamptz,order_id uuid,payment_id uuid,replayed boolean,command_at timestamptz default statement_timestamp());
grant all on captured to authenticated,service_role;

select enum_has_labels('public','shop_reservation_status',array['reserved','fulfilled','cancelled_by_member','cancelled_by_gym'],'SHP-028 exact stored vocabulary has no expired/payment state');
select ok((select bool_and(relrowsecurity) and count(*)=3 from pg_class where oid in ('public.media_assets'::regclass,'public.shop_categories'::regclass,'public.shop_reservations'::regclass)),'SHP-024 all three tables enable RLS');
select ok(not has_table_privilege('authenticated','public.media_assets','SELECT'),'MED-005 no authenticated table-level SELECT');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid='public.media_assets'::regclass and attnum>0 and not attisdropped and has_column_privilege('authenticated',attrelid,attnum,'SELECT') order by attname$q$,$q$select * from (values ('attached_to_id'::text collate "default"),('bytes'::text collate "default"),('confirmed_at'::text collate "default"),('created_at'::text collate "default"),('created_by_staff_id'::text collate "default"),('deleted_at'::text collate "default"),('id'::text collate "default"),('kind'::text collate "default"),('mime'::text collate "default"),('tenant_id'::text collate "default")) as expected$q$,'MED-005 exact safe-column SELECT, no keys or ETags');
select ok(has_table_privilege('service_role','public.media_assets','SELECT') and not has_table_privilege('service_role','public.media_assets','INSERT,UPDATE,DELETE'),'MED-005 service private read without new direct DML');
select ok(not has_table_privilege('authenticated','public.media_assets','INSERT,UPDATE,DELETE') and not has_table_privilege('anon','public.media_assets','SELECT,INSERT,UPDATE,DELETE'),'MED-005 no client media DML or anon grant');
select ok(has_table_privilege('authenticated','public.shop_reservations','SELECT') and not has_table_privilege('authenticated','public.shop_reservations','INSERT,UPDATE,DELETE'),'SHP-024 reservation SELECT only');
select ok(has_table_privilege('authenticated','public.shop_categories','SELECT') and has_table_privilege('authenticated','public.shop_categories','INSERT') and has_table_privilege('authenticated','public.shop_categories','UPDATE') and not has_table_privilege('authenticated','public.shop_categories','DELETE'),'SHP-024 category normal tier without delete');
select ok(not has_table_privilege('anon','public.shop_categories','SELECT,INSERT,UPDATE,DELETE') and not has_table_privilege('anon','public.shop_reservations','SELECT,INSERT,UPDATE,DELETE'),'SHP-024 anon no new tables');
create temp table rpc_contract(sig text,definer boolean,vol text,grantee text);
insert into rpc_contract values
('public.register_media_asset(text,text,text,integer)',true,'v','authenticated'),
('public.confirm_media_asset(uuid)',false,'v',null),
('public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text)',true,'v','service_role'),
('public.delete_media_asset(uuid,boolean)',true,'v','authenticated'),
('public.set_shop_product_display(uuid,uuid,smallint,uuid)',true,'v','authenticated'),
('public.read_member_shop()',true,'s','authenticated'),
('public.read_member_shop_reservations()',true,'s','authenticated'),
('public.create_shop_reservation(uuid,integer,uuid)',true,'v','authenticated'),
('public.cancel_shop_reservation(uuid,text)',true,'v','authenticated'),
('public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid)',false,'v','authenticated'),
('public.read_shop_product_holds()',false,'s','authenticated'),
('public.reorder_shop_categories(uuid[])',false,'v','authenticated'),
('app.shop_actor(text)',false,'s',null),
('app.shop_offer_listable(public.addon_products)',false,'s',null),
('app.shop_held_quantity(uuid,uuid)',false,'s',null),
('app.media_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb)',true,'v',null),
('app.shop_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)',true,'v',null),
('app.media_attach(uuid,uuid,text,uuid)',true,'v',null),
('app.media_release(uuid,text,uuid)',true,'v',null),
('app.shop_reservation_mark_fulfilled(uuid,uuid)',true,'v','authenticated'),
('app.enforce_shop_reservation()',false,'v',null),
('app.enforce_media_asset_verification()',false,'v',null);
select ok((select count(*)=22 and bool_and(p.oid is not null and p.prosecdef=c.definer and p.provolatile::text=c.vol and p.proconfig @> array['search_path=""'] and pg_get_userbyid(p.proowner)='postgres') from rpc_contract c left join pg_proc p on p.oid=to_regprocedure(c.sig)),'SHP-024 MED-005 exact signatures, owner, volatility and empty paths');
select ok((select bool_and(not has_function_privilege('anon',to_regprocedure(sig),'EXECUTE') and coalesce(grantee='authenticated',false)=has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE') and coalesce(grantee='service_role',false)=has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE')) from rpc_contract where sig like 'public.%'),'MED-005 exact public execution matrix including denied old confirm');
select ok((select bool_and(not has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE') and not has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE') and not has_function_privilege('anon',to_regprocedure(sig),'EXECUTE')) from rpc_contract where sig in ('app.media_attach(uuid,uuid,text,uuid)','app.media_release(uuid,text,uuid)','app.media_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb)','app.shop_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)','app.shop_held_quantity(uuid,uuid)','app.enforce_media_asset_verification()')),'SHP-024 private capabilities have no application execution');
select ok((select tgtype=31 and tgfoid=to_regprocedure('app.enforce_media_asset_verification()') from pg_trigger where tgrelid='public.media_assets'::regclass and tgname='media_assets_verified_immutable'),'MED-002 media invariant BEFORE ROW INSERT UPDATE DELETE');
select ok((select tgtype=23 and tgfoid=to_regprocedure('app.enforce_shop_reservation()') from pg_trigger where tgrelid='public.shop_reservations'::regclass and tgname='shop_reservations_enforce'),'SHP-011 reservation invariant BEFORE ROW INSERT UPDATE');
select ok((select indisunique and pg_get_indexdef(indexrelid) like '%(tenant_id, kind, attached_to_id)%' and pg_get_expr(indpred,indrelid) like '%attached_to_id IS NOT NULL%deleted_at IS NULL%' from pg_index where indexrelid='public.media_assets_tenant_id_kind_attached_to_id_live_key'::regclass),'MED-004 one live image per tenant kind parent');
select ok((select indisunique and pg_get_indexdef(indexrelid) like '%(tenant_id, order_id)%' from pg_index where indexrelid='public.shop_reservations_tenant_id_order_id_key'::regclass),'SHP-010 one order fulfils at most one reservation');

insert into public.organizations(id,name,gym_code,status) values(pg_temp.sid(1),'Shop A','SHP72A','active'),(pg_temp.sid(2),'Shop B','SHP72B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.sid(11),pg_temp.sid(1),'A',true),(pg_temp.sid(12),pg_temp.sid(2),'B',true);
insert into auth.users(id) select pg_temp.sid(n) from generate_series(901,908)n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.sid(21),pg_temp.sid(1),pg_temp.sid(901),pg_temp.sid(11),'gym_owner','Owner'),(pg_temp.sid(22),pg_temp.sid(1),pg_temp.sid(902),pg_temp.sid(11),'gym_manager','Manager'),(pg_temp.sid(23),pg_temp.sid(1),pg_temp.sid(903),pg_temp.sid(11),'front_desk','Desk'),(pg_temp.sid(24),pg_temp.sid(1),pg_temp.sid(904),pg_temp.sid(11),'trainer','Trainer'),(pg_temp.sid(25),pg_temp.sid(2),pg_temp.sid(905),pg_temp.sid(12),'gym_owner','Other owner');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,date_of_birth) values
(pg_temp.sid(31),pg_temp.sid(1),pg_temp.sid(906),pg_temp.sid(11),'Member A','+917200000031','1990-01-01'),(pg_temp.sid(32),pg_temp.sid(1),pg_temp.sid(907),pg_temp.sid(11),'Member A2','+917200000032','1990-01-01'),(pg_temp.sid(33),pg_temp.sid(2),pg_temp.sid(908),pg_temp.sid(12),'Member B','+917200000033','1990-01-01');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active) values
(pg_temp.sid(101),pg_temp.sid(1),'product','Protein','Disclosed',4000000000,'INR',7,10,'Desk collection',true),
(pg_temp.sid(102),pg_temp.sid(1),'product','Last unit','Disclosed',10000,'INR',7,1,'Desk collection',true),
(pg_temp.sid(103),pg_temp.sid(1),'diet_plan','Locker','Disclosed',0,'INR',7,null,'Desk collection',true),
(pg_temp.sid(104),pg_temp.sid(1),'product','Empty stock','Disclosed',10000,'INR',7,0,'Desk collection',true),
(pg_temp.sid(105),pg_temp.sid(1),'product','Hidden','Disclosed',10000,'INR',7,2,'Desk collection',false),
(pg_temp.sid(106),pg_temp.sid(1),'product','Incomplete',null,10000,'INR',null,2,null,false),
(pg_temp.sid(107),pg_temp.sid(1),'product','Foreign currency','Disclosed',10000,'USD',7,2,'Desk collection',true),
(pg_temp.sid(108),pg_temp.sid(2),'product','Foreign tenant','Disclosed',10000,'INR',7,2,'Desk collection',true);
create temp table quotes as select id,quote_version from public.addon_products where tenant_id in(pg_temp.sid(1),pg_temp.sid(2));
grant select on quotes to authenticated,service_role;

-- Categories and opaque member read projections.
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
insert into public.shop_categories(id,tenant_id,name,sort_order) values(pg_temp.sid(201),pg_temp.sid(1),'Nutrition',0),(pg_temp.sid(202),pg_temp.sid(1),'Equipment',1);
select is(pg_temp.refusal($q$insert into public.shop_categories(tenant_id,name) values(pg_temp.sid(1),'nutrition')$q$) like '23505%',true,'SHP-002 case insensitive category uniqueness');
select is(pg_temp.refusal($q$insert into public.shop_categories(tenant_id,name) values(pg_temp.sid(2),'Foreign write')$q$) like '42501%',true,'SHP-024 category cross-tenant insert refused');
select lives_ok($q$select public.set_shop_product_display(pg_temp.sid(101),pg_temp.sid(201),2::smallint,null)$q$,'SHP-003 owner display edit');
select is(pg_temp.refusal($q$select public.reorder_shop_categories(array[pg_temp.sid(201),pg_temp.sid(999)])$q$),'22023','SHP-018 invalid reorder refuses atomically');
select results_eq($q$select sort_order::integer from public.shop_categories order by id$q$,$q$select * from (values(0),(1)) as expected$q$,'SHP-018 failed reorder leaves both positions');
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(103),pg_temp.sid(201),0::smallint,null)$q$),'GL086:category_unavailable','SHP-003 service cannot use category');
reset role;
select is((select quote_version from public.addon_products where id=pg_temp.sid(101)),(select quote_version from quotes where id=pg_temp.sid(101)),'SHP-027 display does not rotate quote');
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select results_eq($q$select item_id from public.read_member_shop() order by item_id$q$,$q$select * from (values(pg_temp.sid(101)),(pg_temp.sid(102)),(pg_temp.sid(103)),(pg_temp.sid(104))) as expected$q$,'SHP-001 exact own complete INR list including zero stock');
select results_eq($q$select availability collate "default",available_quantity from public.read_member_shop() where item_id=pg_temp.sid(104)$q$,$q$select * from (values('out_of_stock'::text collate "default",0)) as expected$q$,'SHP-004 zero stock is listable');
select results_eq($q$select section collate "default",availability collate "default",available_quantity,category_id,category_name collate "default" from public.read_member_shop() where item_id=pg_temp.sid(103)$q$,$q$select * from (values('services'::text collate "default",'available'::text collate "default",null::integer,null::uuid,null::text collate "default")) as expected$q$,'SHP-004 flat services have no quantity or category');
select is((select price_paise from public.read_member_shop() where item_id=pg_temp.sid(101)),'4000000000','SHP-015 bigint price decimal text');
select is((select count(*)::integer from public.shop_categories),0,'SHP-004 member categories direct read absent');
select is((select count(*)::integer from public.shop_reservations),0,'SHP-012 member direct reservation read absent');
select is((select count(id)::integer from public.media_assets),0,'MED-005 member safe media read absent');
select is(pg_temp.refusal('select object_key from public.media_assets') like '42501%',true,'MED-005 member private media column refused');
reset role;
select results_eq($q$select n::text collate "default" from pg_proc p cross join lateral unnest(p.proargnames,p.proargmodes) a(n,m) where p.oid=to_regprocedure('public.read_member_shop()') and m='t' order by array_position(p.proargnames,n)$q$,$q$select * from (values('item_id'::text collate "default"),('section'::text collate "default"),('name'::text collate "default"),('description'::text collate "default"),('price_paise'::text collate "default"),('currency'::text collate "default"),('gst_rate_bp'::text collate "default"),('validity_days'::text collate "default"),('cancellation_terms'::text collate "default"),('quote_version'::text collate "default"),('category_id'::text collate "default"),('category_name'::text collate "default"),('image_asset_id'::text collate "default"),('availability'::text collate "default"),('available_quantity'::text collate "default")) as expected$q$,'SHP-004 exact asset-id-only catalogue projection');
select results_eq($q$select n::text collate "default" from pg_proc p cross join lateral unnest(p.proargnames,p.proargmodes) a(n,m) where p.oid=to_regprocedure('public.read_member_shop_reservations()') and m='t' order by array_position(p.proargnames,n)$q$,$q$select * from (values('reservation_id'::text collate "default"),('item_id'::text collate "default"),('item_name'::text collate "default"),('section'::text collate "default"),('quantity'::text collate "default"),('unit_price_paise'::text collate "default"),('total_paise'::text collate "default"),('currency'::text collate "default"),('state'::text collate "default"),('created_at'::text collate "default"),('expires_at'::text collate "default"),('cancel_reason'::text collate "default"),('terms_changed'::text collate "default"),('order_id'::text collate "default"),('image_asset_id'::text collate "default")) as expected$q$,'SHP-012 exact asset-id-only own reservation projection');

-- Strict actor shape and database identity binding before command parsing.
select pg_temp.claim('member',1,null,31,907);
set local role authenticated;
select is(pg_temp.refusal('select * from public.read_member_shop()') like '42501%',true,'SHP-004 mismatched member user refused');
select is(pg_temp.refusal('select * from public.create_shop_reservation(null,null,null)') like '42501%',true,'SHP-005 actor precedes malformed input');
reset role;
select pg_temp.claim('member',1,21,31,906);
set local role authenticated;
select is(pg_temp.refusal('select * from public.read_member_shop()') like '42501%',true,'SHP-004 contradictory staff/member claim refused');
reset role;
select pg_temp.claim('member',1,null,31,906,jsonb_build_object('impersonation_session_id',pg_temp.sid(999)));
set local role authenticated;
select is(pg_temp.refusal('select * from public.read_member_shop()') like '42501%',true,'SHP-004 impersonation refused');
reset role;
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
select is(pg_temp.refusal('select * from public.read_member_shop()') like '42501%',true,'SHP-004 staff cannot use member RPC');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal('select * from public.create_shop_reservation(null,0,null)'),'22023','SHP-005 null before item/quantity');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(108),0,pg_temp.sid(999))$q$),'GL086:item_unavailable','SHP-005 foreign item opaque before quote and quantity');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(105),0,pg_temp.sid(999))$q$),'GL086:item_unavailable','SHP-005 inactive before quote and quantity');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(101),0,pg_temp.sid(999))$q$),'GL086:quote_changed','SHP-005 quote before quantity');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(103),2,(select quote_version from quotes where id=pg_temp.sid(103)))$q$),'GL086:invalid_quantity','SHP-005 service quantity exactly one');
insert into captured(label,id,expiry) select 'big',reservation_id,expires_at from public.create_shop_reservation(pg_temp.sid(101),2,(select quote_version from quotes where id=pg_temp.sid(101)));
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$),'GL086:reservation_exists','SHP-013 duplicate open reservation');
select results_eq($q$select quantity,unit_price_paise collate "default",total_paise collate "default",currency collate "default",state collate "default",terms_changed from public.read_member_shop_reservations() where reservation_id=(select id from captured where label='big')$q$,$q$select * from (values(2,'4000000000'::text collate "default",'8000000000'::text collate "default",'INR'::text collate "default",'reserved'::text collate "default",false)) as expected$q$,'SHP-012 exact snapshot total beyond 32 bits');
insert into captured(label,id,expiry) select 'last',reservation_id,expires_at from public.create_shop_reservation(pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)));
select is((select available_quantity from public.read_member_shop() where item_id=pg_temp.sid(102)),0,'SHP-006 hold excludes last unit immediately');
reset role;
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),10,'SHP-005 reservation does not change stock');
select is((select count(*)::integer from public.addon_orders where tenant_id=pg_temp.sid(1)),0,'SHP-005 reservation creates no order');
select is((select count(*)::integer from public.payments where tenant_id=pg_temp.sid(1)),0,'SHP-005 reservation creates no payment');
select is((select created_at=c.command_at and expiry=c.command_at+interval '24 hours' from captured c join public.shop_reservations r on r.id=c.id where label='big'),true,'SHP-005 actual command statement clock and exact 24 hour hold');
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)))$q$),'GL087:sold_out','SHP-006 serial contender cannot oversell held last unit');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation((select id from captured where label='big'),null)$q$) like '42501%',true,'SHP-008 other member cancellation opaque');
select is((select count(*)::integer from public.read_member_shop_reservations()),0,'SHP-012 other member sees no reservation');
reset role;
-- Bounded rollback-only command clock seam: real HTTP commands use separate
-- transactions, whereas this suite's outer BEGIN gives every sale the same
-- transaction timestamp. Preserve the exact original catalogue default, change
-- only this fixture default for the ordinary sale/fulfil calls below, then restore
-- it immediately. No money function, trigger or successful row is rewritten.
-- Mandatory external evidence: reserve in transaction A, commit; fulfil by its
-- ordinary RPC in transaction B, commit; replay in C. Use the unaltered default
-- and prove order.created_at >= reservation.created_at, one stock/payment/audit
-- effect and correct replay. Sequential statements in this suite are no proof.
create temp table shop_order_clock as
select pg_get_expr(d.adbin,d.adrelid) as original_default
from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
where d.adrelid='public.addon_orders'::regclass and a.attname='created_at';
alter table public.addon_orders alter column created_at set default statement_timestamp();
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is((select held_quantity from public.read_shop_product_holds() where product_id=pg_temp.sid(101)),2,'SHP-006 desk held quantity');
select is((select count(*)::integer from public.shop_reservations),2,'SHP-012 desk reads own tenant');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation((select id from captured where label='last'),' x ')$q$),'22023','SHP-009 reason minimum');
-- The unchanged desk sale intentionally consumes a member's soft hold.
insert into captured(label,order_id,payment_id,replayed) select 'desk-soft',order_id,payment_id,replayed from public.record_addon_sale(pg_temp.sid(31),pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)),null,null,null,'cash',null,pg_temp.sid(501));
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation((select id from captured where label='last'),(select quote_version from quotes where id=pg_temp.sid(102)),'cash',null,pg_temp.sid(502))$q$),'GL057:insufficient_stock','SHP-010 soft hold fulfil sale refusal passes through');
select lives_ok($q$select public.cancel_shop_reservation((select id from captured where label='last'),'  Sold at the desk  ')$q$,'SHP-009 desk cancels unavailable soft hold');
reset role;
select is((select status::text from public.shop_reservations where id=(select id from captured where label='last')),'cancelled_by_gym','SHP-009 gym cancellation state');
select is((select count(*)::integer from public.addon_orders where tenant_id=pg_temp.sid(1)),1,'SHP-010 failed fulfil leaves only desk sale');
select is((select count(*)::integer from public.payments where tenant_id=pg_temp.sid(1)),1,'SHP-010 failed fulfil leaves only desk payment');
select is((select cancel_reason from public.shop_reservations where id=(select id from captured where label='last')),'Sold at the desk','SHP-009 stored reason trimmed');
select is(app.shop_held_quantity(pg_temp.sid(1),pg_temp.sid(101)),2,'SHP-006 private hold parity');

-- Current-price sale, atomic fulfil, replay and key conflict.
update public.addon_products set price_paise=5000000000 where id=pg_temp.sid(101);
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select terms_changed from public.read_member_shop_reservations() where reservation_id=(select id from captured where label='big')),true,'SHP-012 quote changed while open');
select is((select item_name from public.read_member_shop_reservations() where reservation_id=(select id from captured where label='big')),'Protein','SHP-014 reservation name snapshot');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation((select id from captured where label='big'),(select quote_version from quotes where id=pg_temp.sid(101)),'cash',null,pg_temp.sid(503))$q$),'GL055:quote_changed','SHP-010 stale quote rolls back sale and reservation');
insert into captured(label,id,order_id,payment_id,replayed) select 'fulfilled',reservation_id,order_id,payment_id,replayed from public.fulfil_shop_reservation((select id from captured where label='big'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),'cash',null,pg_temp.sid(503));
select is((select replayed from captured where label='fulfilled'),false,'SHP-010 first fulfil not replay');
select is((select replayed from public.fulfil_shop_reservation((select id from captured where label='big'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),'cash',null,pg_temp.sid(503))),true,'SHP-010 same key replay accepted');
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation((select id from captured where label='big'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),'upi',null,pg_temp.sid(503))$q$),'GL052:idempotency_conflict','SHP-010 replay changed method key conflict');
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation((select id from captured where label='big'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),'cash',null,pg_temp.sid(504))$q$),'GL086:reservation_not_open','SHP-010 different key cannot fulfil twice');
reset role;
do $$declare original text; begin
  select original_default into strict original from shop_order_clock;
  execute 'alter table public.addon_orders alter column created_at set default '||original;
end$$;
select is((select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where d.adrelid='public.addon_orders'::regclass and a.attname='created_at'),(select original_default from shop_order_clock),'SHP-010 test clock restores exact original order default');
select ok((select o.created_at>=r.created_at from public.shop_reservations r join public.addon_orders o on o.id=r.order_id where r.id=(select id from captured where label='big')),'SHP-011 successful ordinary fulfil preserves temporal order invariant under fixture command clock');
select results_eq($q$select total_paise,currency collate "default",quantity from public.addon_orders where id=(select order_id from captured where label='fulfilled')$q$,$q$select * from (values(10000000000::bigint,'INR'::text collate "default",2)) as expected$q$,'SHP-010 charge current exact paise not reserved price');
select is((select amount_paise from public.payments where id=(select payment_id from captured where label='fulfilled')),10000000000::bigint,'SHP-010 exact single payment');
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),8,'SHP-010 stock decremented exactly once');
select is((select count(*)::integer from public.audit_log where record_id=(select id from captured where label='big') and action='shop_reservation.fulfilled'),1,'SHP-025 replay creates one fulfil audit');
select is(pg_temp.refusal($q$update public.shop_reservations set product_name='Forged' where id=(select id from captured where label='big')$q$),'GL086:reservation_not_open','SHP-011 terminal row immutable even postgres');

-- Exact expiry, member cancellation and trusted-writer identity guards.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at) values(pg_temp.sid(601),pg_temp.sid(1),pg_temp.sid(31),pg_temp.sid(101),'Old name','product',1,(select quote_version from quotes where id=pg_temp.sid(101)),4000000000,'INR',statement_timestamp()-interval '24 hours',statement_timestamp());
select is(app.shop_held_quantity(pg_temp.sid(1),pg_temp.sid(101)),0,'SHP-007 expiry equality holds nothing');
select is(pg_temp.refusal($q$update public.shop_reservations set expires_at=statement_timestamp()+interval '1 day' where id=pg_temp.sid(601)$q$) like 'GL086:%',true,'SHP-011 expiry cannot be extended by postgres');
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select state from public.read_member_shop_reservations() where reservation_id=pg_temp.sid(601)),'expired','SHP-007 expired derived from stored reserved');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation(pg_temp.sid(601),null)$q$),'GL086:reservation_expired','SHP-007 expired cancel refuses');
insert into captured(label,id,expiry) select 'service',reservation_id,expires_at from public.create_shop_reservation(pg_temp.sid(103),1,(select quote_version from quotes where id=pg_temp.sid(103)));
select lives_ok($q$select public.cancel_shop_reservation((select id from captured where label='service'),'Ignored member reason')$q$,'SHP-008 member cancellation ignores reason');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation((select id from captured where label='service'),null)$q$),'GL086:reservation_not_open','SHP-008 cancellation replay refuses');
reset role;
select results_eq($q$select status::text collate "default",cancel_reason collate "default",cancelled_by_staff_id from public.shop_reservations where id=(select id from captured where label='service')$q$,$q$select * from (values('cancelled_by_member'::text collate "default",null::text collate "default",null::uuid)) as expected$q$,'SHP-008 no member reason or staff attribution');
select is((select status::text from public.shop_reservations where id=pg_temp.sid(601)),'reserved','SHP-007 no stored expired transition');

-- MEDIA registration and trusted credential-only finalization.
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
insert into captured(label,id) values('image',public.register_media_asset('product',pg_temp.stage(701),'image/jpeg',100));
insert into captured(label,id) values('image2',public.register_media_asset('product',pg_temp.stage(702),'image/jpeg',100));
insert into captured(label,id) values('trainer-image',public.register_media_asset('trainer',pg_temp.stage(703,'trainer'),'image/jpeg',100));
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.pub(704),'image/jpeg',100)$q$),'22023','MED-001 published key cannot register');
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(704,'product',2),'image/jpeg',100)$q$) like '42501%',true,'MED-009 foreign namespace refuses');
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(704),'image/png',100)$q$),'22023','MED-001 MIME extension binding');
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(704),'image/jpeg',2097153)$q$),'22023','MED-010 byte ceiling');
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(701),'image/jpeg',100)$q$),'22023','MED-001 duplicate staging key stable refusal');
select is(pg_temp.refusal($q$select public.confirm_media_asset((select id from captured where label='image'))$q$) like '42501%',true,'MED-002 authenticated old confirm denied');
select is(pg_temp.refusal('select * from public.media_assets') like '42501%',true,'MED-005 staff select star cannot fetch private columns');
select is((select count(id)::integer from public.media_assets),3,'MED-005 owner safe read works');
reset role;
select ok((select object_key is null and confirmed_at is null and verified_source_etag is null and published_etag is null and attached_to_id is null and staging_object_key=pg_temp.stage(701) and created_by_staff_id=pg_temp.sid(21) from public.media_assets where id=(select id from captured where label='image')),'MED-001 registered asset is staging-only');
select is(pg_temp.refusal($q$update public.media_assets set bytes=101 where id=(select id from captured where label='image')$q$),'GL086:media_verification_invariant','MED-002 registration immutable for postgres');
select is(pg_temp.refusal($q$delete from public.media_assets where id=(select id from captured where label='image')$q$),'GL086:media_verification_invariant','MED-012 postgres cannot physically delete metadata');
select is(pg_temp.refusal($q$select public.confirm_media_asset((select id from captured where label='image'))$q$) like '42501%',true,'MED-002 even owner postgres compatibility confirm refuses');
select set_config('app.media_finalize_command','sentinel-before',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.confirm_media_asset((select id from captured where label='image'))$q$) like '42501%',true,'MED-002 service old confirm no execution');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(902),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(701),'source',pg_temp.pub(801),'published')$q$) like '42501%',true,'MED-002 actor user must match active staff');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',101,pg_temp.stage(701),'source',pg_temp.pub(801),'published')$q$),'22023','MED-002 supplied bytes must equal registration');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(701),' ',pg_temp.pub(801),'published')$q$),'22023','MED-002 blank verified ETag refuses');
select is(current_setting('app.media_finalize_command',true),'sentinel-before','MED-002 refused finalize restores prior marker');
select is(public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(701),'source',pg_temp.pub(801),'published'),true,'MED-002 credential verifier finalizes once');
select is(current_setting('app.media_finalize_command',true),'sentinel-before','MED-002 successful finalize restores prior marker immediately');
select is(public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(701),'losing-source',pg_temp.pub(802),'losing-published'),false,'MED-002 concurrent-loser replay need not match winning tuple');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',101,pg_temp.stage(701),'source',pg_temp.pub(802),'published')$q$),'22023','MED-002 replay still checks immutable registration');
select is(public.finalize_media_asset((select id from captured where label='image2'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(702),'source2',pg_temp.pub(803),'published2'),true,'MED-002 second independent publication');
reset role;
select results_eq($q$select object_key collate "default",verified_source_etag collate "default",published_etag collate "default" from public.media_assets where id=(select id from captured where label='image')$q$,$q$select pg_temp.pub(801) collate "default",'source'::text collate "default",'published'::text collate "default"$q$,'MED-002 replay preserves winner publication');
select results_eq($q$select actor_user_id,actor_role::text collate "default","before","after" from public.audit_log where record_id=(select id from captured where label='image') and action='media_asset.confirmed'$q$,$q$select * from (values(pg_temp.sid(901),'gym_owner'::text collate "default",'{"confirmed":false}'::jsonb,'{"confirmed":true}'::jsonb)) as expected$q$,'MED-011 one exact real-actor confirmation audit');
select is(pg_temp.refusal($q$update public.media_assets set published_etag='forged' where id=(select id from captured where label='image')$q$),'GL086:media_verification_invariant','MED-002 postgres cannot rewrite publication');
select set_config('app.media_finalize_command','finalize:'||(select id::text from captured where label='trainer-image'),true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"72000000-0000-4000-8000-000000000901"}',true);
select is(pg_temp.refusal($q$update public.media_assets set object_key=pg_temp.pub(804,'trainer'),verified_source_etag='s',published_etag='p',confirmed_at=statement_timestamp() where id=(select id from captured where label='trainer-image')$q$),'GL086:media_verification_invariant','MED-002 exact forged marker plus authenticated claims cannot authorize postgres writer');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('app.media_finalize_command','finalize:wrong',true);
select is(pg_temp.refusal($q$update public.media_assets set object_key=pg_temp.pub(804,'trainer'),verified_source_etag='s',published_etag='p',confirmed_at=statement_timestamp() where id=(select id from captured where label='trainer-image')$q$),'GL086:media_verification_invariant','MED-002 wrong marker/connection refuses publication');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(804,'trainer'),'p')$q$) like '42501%',true,'MED-002 postgres connection cannot masquerade as service credential');

-- Attachment replacement and soft deletion preserve metadata tombstones.
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(101),null,0::smallint,(select id from captured where label='trainer-image'))$q$) like 'GL086:%',true,'MED-004 unconfirmed/wrong-kind cannot attach');
select lives_ok($q$select public.set_shop_product_display(pg_temp.sid(101),pg_temp.sid(201),2::smallint,(select id from captured where label='image'))$q$,'MED-004 attach verified product photo');
select is(pg_temp.refusal($q$select public.delete_media_asset((select id from captured where label='image'),false)$q$),'GL086:media_in_use','MED-003 attached asset cannot delete');
select lives_ok($q$select public.delete_media_asset((select id from captured where label='image'),true)$q$,'MED-003 failed verification cleanup no-op on confirmed winner');
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(102),null,0::smallint,(select id from captured where label='image'))$q$),'GL086:media_in_use','MED-004 cannot share asset across records');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select image_asset_id from public.read_member_shop() where item_id=pg_temp.sid(101)),(select id from captured where label='image'),'MED-008 member exposed opaque image asset only');
reset role;
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
select lives_ok($q$select public.set_shop_product_display(pg_temp.sid(101),pg_temp.sid(201),2::smallint,(select id from captured where label='image2'))$q$,'MED-004 replace photo atomically releases old');
select lives_ok($q$select public.delete_media_asset((select id from captured where label='image'),false)$q$,'MED-003 deleted replay no-op');
reset role;
select ok((select attached_to_id is null and deleted_at is not null and object_key=pg_temp.pub(801) from public.media_assets where id=(select id from captured where label='image')),'MED-012 old tombstone keeps immutable published metadata');
select is((select count(*)::integer from public.media_assets where attached_to_id=pg_temp.sid(101) and deleted_at is null),1,'MED-004 exactly one live replacement');
select is((select count(*)::integer from public.audit_log where record_id=(select id from captured where label='image') and action='media_asset.deleted'),1,'MED-011 release plus delete replay audits deletion once');
select is(pg_temp.refusal($q$delete from public.media_assets where id=(select id from captured where label='image')$q$),'GL086:media_verification_invariant','MED-012 deleted metadata tombstone cannot physically prune');
select set_config('request.jwt.claims','{"role":"service_role","sub":"72000000-0000-4000-8000-000000000901"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image2'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(702),'s',pg_temp.pub(805),'p')$q$) like '42501%',true,'MED-002 service role with user subject is not credential-only');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(701),'s',pg_temp.pub(805),'p')$q$),'GL086:media_not_ready','MED-002 deleted replay cannot report success');
reset role;
update public.staff set is_active=false where id=pg_temp.sid(21);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='image2'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',100,pg_temp.stage(702),'s',pg_temp.pub(805),'p')$q$) like '42501%',true,'MED-002 revoked active actor invalidates confirmed replay');
reset role;
update public.staff set is_active=true where id=pg_temp.sid(21);

-- Role/RLS refusals for every newly elevated capability.
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is((select count(id)::integer from public.media_assets),0,'MED-005 trainer safe rows hidden');
select is((select count(*)::integer from public.shop_reservations),0,'SHP-012 trainer reservation rows hidden');
select is(pg_temp.refusal($q$select public.register_media_asset('trainer',pg_temp.stage(709,'trainer'),'image/jpeg',100)$q$) like '42501%',true,'MED-001 trainer cannot register own photo');
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(101),null,0::smallint,null)$q$) like '42501%',true,'SHP-003 trainer cannot edit display');
select is(pg_temp.refusal('select * from public.read_shop_product_holds()') like '42501%',true,'SHP-006 trainer hold read refused');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(710),'image/jpeg',100)$q$) like '42501%',true,'MED-001 front desk product forbidden');
select lives_ok($q$select public.register_media_asset('announcement',pg_temp.stage(711,'announcement'),'image/jpeg',100)$q$,'MED-001 front desk announcement allowed');
select is(pg_temp.refusal($q$insert into public.shop_categories(tenant_id,name) values(pg_temp.sid(1),'Desk category')$q$) like '42501%',true,'SHP-002 front desk category write refused');
reset role;
select pg_temp.claim('gym_owner',2,25,null,905);
set local role authenticated;
select is((select count(id)::integer from public.media_assets),0,'MED-009 foreign staff media invisible');
select is((select count(*)::integer from public.shop_reservations),0,'SHP-024 foreign staff reservations invisible');
select is((select count(*)::integer from public.shop_categories),0,'SHP-024 foreign staff categories invisible');
select is(pg_temp.refusal($q$select public.delete_media_asset((select id from captured where label='image2'),false)$q$) like '42501%',true,'MED-009 foreign asset delete opaque');
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(101),null,0::smallint,null)$q$) like '42501%',true,'SHP-024 foreign product display opaque');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation(pg_temp.sid(601),'Foreign desk')$q$) like '42501%',true,'SHP-024 foreign cancellation opaque');
reset role;
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.sid(1) and (action like 'media_asset.%' or action like 'shop_%') and (coalesce("before",'{}'::jsonb)::text||coalesce("after",'{}'::jsonb)::text) ~ '(staging/|published/|etag|https:|token)'),'MED-011 SHP-025 no keys, ETags, URLs or tokens in audit payloads');

-- Registration shape cannot be planted by a trusted writer or a forged marker.
select set_config('request.jwt.claims','',true);
select is(pg_temp.refusal($q$insert into public.media_assets(tenant_id,kind,staging_object_key,object_key,mime,bytes,created_by_staff_id,confirmed_at,verified_source_etag,published_etag) values(pg_temp.sid(1),'product',pg_temp.stage(720),pg_temp.pub(820),'image/jpeg',100,pg_temp.sid(21),statement_timestamp(),'source','published')$q$),'GL086:media_verification_invariant','MED-002 postgres cannot INSERT preconfirmed asset');
select is(pg_temp.refusal($q$update public.media_assets set id=pg_temp.sid(999) where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 media identity immutable');
select is(pg_temp.refusal($q$update public.media_assets set tenant_id=pg_temp.sid(2) where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-009 tenant immutable even postgres');
select is(pg_temp.refusal($q$update public.media_assets set kind='announcement' where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 kind immutable');
select is(pg_temp.refusal($q$update public.media_assets set staging_object_key=pg_temp.stage(721) where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 staging key immutable');
select is(pg_temp.refusal($q$update public.media_assets set mime='image/png' where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 MIME immutable');
select is(pg_temp.refusal($q$update public.media_assets set created_by_staff_id=pg_temp.sid(22) where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 creator immutable');
select is(pg_temp.refusal($q$update public.media_assets set created_at=created_at-interval '1 day' where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 creation time immutable');
select is(pg_temp.refusal($q$update public.media_assets set object_key=pg_temp.pub(821) where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 published key immutable');
select is(pg_temp.refusal($q$update public.media_assets set verified_source_etag='replacement' where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 source ETag immutable');
select is(pg_temp.refusal($q$update public.media_assets set confirmed_at=null,object_key=null,verified_source_etag=null,published_etag=null where id=(select id from captured where label='image2')$q$),'GL086:media_verification_invariant','MED-002 cannot erase published verification');
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$) like '42501%',true,'MED-002 service connection requires credential request role too');
reset role;
select set_config('request.jwt.claims','{"role":"service_role","impersonation_session_id":"72000000-0000-4000-8000-000000000999"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$) like '42501%',true,'MED-002 service impersonation marker refused');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(903),pg_temp.sid(23),'front_desk',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$) like '42501%',true,'MED-002 finalizer kind authorization independently checked');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_manager',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$) like '42501%',true,'MED-002 supplied actor role must match stored staff role');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(905),pg_temp.sid(25),'gym_owner',pg_temp.sid(2),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer',2),'p')$q$) like '42501%',true,'MED-009 service tuple cannot finalize foreign-tenant asset');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(799,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$),'22023','MED-002 exact staging registration checked');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/png',100,pg_temp.stage(703,'trainer'),'s',pg_temp.pub(822,'trainer'),'p')$q$),'22023','MED-002 exact registered MIME checked');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select id from captured where label='trainer-image'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'trainer','image/jpeg',100,pg_temp.stage(703,'trainer'),'s',pg_temp.stage(822,'trainer'),'p')$q$),'22023','MED-002 published destination cannot be staging');
reset role;

-- Open and rolling limits are independent; trusted fixtures have valid immutable inserts.
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active)
select pg_temp.sid(n),pg_temp.sid(1),'product','Limit item '||n,'Disclosed',10000,'INR',7,100,'Desk collection',true from generate_series(111,122)n;
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.sid(9000+n),pg_temp.sid(1),pg_temp.sid(32),p.id,p.name,p.kind,1,p.quote_version,p.price_paise,p.currency,statement_timestamp()-interval '1 hour',statement_timestamp()+interval '23 hours' from public.addon_products p cross join lateral (select right(p.id::text,12)::integer n) x where p.id between pg_temp.sid(111) and pg_temp.sid(115);
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(116),1,(select quote_version from public.addon_products where id=pg_temp.sid(116)))$q$),'GL086:reservation_limit','SHP-013 five open reservations prevent sixth');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(111),1,(select quote_version from public.addon_products where id=pg_temp.sid(111)))$q$),'GL086:reservation_exists','SHP-005 duplicate precedes open limit');
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(116),11,(select quote_version from public.addon_products where id=pg_temp.sid(116)))$q$),'GL086:invalid_quantity','SHP-005 quantity precedes limit');
select lives_ok($q$select public.cancel_shop_reservation(pg_temp.sid(9111),null)$q$,'SHP-008 release one of five holds');
insert into captured(label,id,expiry) select 'limit-next',reservation_id,expires_at from public.create_shop_reservation(pg_temp.sid(116),1,(select quote_version from public.addon_products where id=pg_temp.sid(116)));
reset role;
select is((select count(*)::integer from public.shop_reservations where member_id=pg_temp.sid(32) and status='reserved' and expires_at>statement_timestamp()),5,'SHP-013 replacement after cancellation stays at five');
-- Member A has three creations already; seven expired recent rows reach rolling ten.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.sid(9500+n),pg_temp.sid(1),pg_temp.sid(31),p.id,p.name,p.kind,1,p.quote_version,p.price_paise,p.currency,statement_timestamp()-interval '2 hours',statement_timestamp()-interval '1 hour' from public.addon_products p cross join lateral (select right(p.id::text,12)::integer n) x where p.id between pg_temp.sid(111) and pg_temp.sid(117);
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(118),1,(select quote_version from public.addon_products where id=pg_temp.sid(118)))$q$),'GL086:reservation_limit','SHP-013 expired recent rows still count rolling ten');
reset role;
-- Role spoofing, inactive member ordering and cancellation without current eligibility.
update public.members set status='blocked' where id=pg_temp.sid(32);
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.create_shop_reservation(pg_temp.sid(105),0,pg_temp.sid(999))$q$),'GL086:member_unavailable','SHP-005 eligibility precedes listability/quote/quantity');
select lives_ok($q$select public.cancel_shop_reservation((select id from captured where label='limit-next'),null)$q$,'SHP-008 blocked member still cancels own open intent');
reset role;
select pg_temp.claim('gym_owner',1,21,null,902);
set local role authenticated;
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(101),null,0::smallint,null)$q$) like '42501%',true,'SHP-003 claimed staff/user mismatch refused');
select is(pg_temp.refusal($q$select public.delete_media_asset((select id from captured where label='image2'),false)$q$) like '42501%',true,'MED-003 claimed staff/user mismatch refused');
reset role;
select pg_temp.claim('gym_owner',1,21,null,901,jsonb_build_object('impersonation_session_id',pg_temp.sid(999)));
set local role authenticated;
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(730),'image/jpeg',100)$q$) like '42501%',true,'MED-001 preview cannot register');
select is(pg_temp.refusal($q$select public.set_shop_product_display(pg_temp.sid(101),null,0::smallint,null)$q$) like '42501%',true,'SHP-003 preview cannot mutate display');
reset role;
-- The trigger binds privileged writers, including open snapshot rewrites.
select set_config('request.jwt.claims','',true);
select is(pg_temp.refusal($q$update public.shop_reservations set product_name='Changed snapshot' where id=pg_temp.sid(9112)$q$) like 'GL086:%',true,'SHP-011 postgres cannot alter open product snapshot');
select is(pg_temp.refusal($q$update public.shop_reservations set quantity=2 where id=pg_temp.sid(9112)$q$) like 'GL086:%',true,'SHP-011 postgres cannot alter open quantity');
select is(pg_temp.refusal($q$update public.shop_reservations set unit_price_paise=1 where id=pg_temp.sid(9112)$q$) like 'GL086:%',true,'SHP-011 postgres cannot alter open price');
select is(pg_temp.refusal($q$update public.shop_reservations set member_id=pg_temp.sid(31) where id=pg_temp.sid(9112)$q$) like 'GL086:%',true,'SHP-011 postgres cannot change member identity');
select is(pg_temp.refusal($q$update public.shop_reservations set status='fulfilled',fulfilled_at=statement_timestamp(),fulfilled_by_staff_id=pg_temp.sid(23),order_id=(select order_id from captured where label='desk-soft') where id=pg_temp.sid(9112)$q$) like 'GL086:%',true,'SHP-011 postgres cannot attach unrelated sale');
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation(pg_temp.sid(601),(select quote_version from public.addon_products where id=pg_temp.sid(101)),'cash',null,pg_temp.sid(506))$q$),'GL086:reservation_expired','SHP-007 desk cannot fulfil expired row');
select is(pg_temp.refusal($q$select app.shop_reservation_mark_fulfilled(pg_temp.sid(9112),(select order_id from captured where label='desk-soft'))$q$) <> 'NO ERROR',true,'SHP-010 directly callable mark helper rechecks unrelated order');
reset role;
update public.addon_products set is_active=false where id=pg_temp.sid(112);
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation(pg_temp.sid(9112),(select quote_version from public.addon_products where id=pg_temp.sid(112)),'cash',null,pg_temp.sid(507))$q$),'GL055:offer_unavailable','SHP-014 inactive offer cannot fulfil existing hold');
reset role;
select is((select status::text from public.shop_reservations where id=pg_temp.sid(9112)),'reserved','SHP-010 sale refusal leaves reservation open');
select is((select count(*)::integer from public.addon_orders where tenant_id=pg_temp.sid(1)),2,'SHP-010 offer refusal creates no extra order');
update public.addon_products set is_active=true where id=pg_temp.sid(112);
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select * from public.fulfil_shop_reservation(pg_temp.sid(9112),(select quote_version from public.addon_products where id=pg_temp.sid(112)),'cash',null,pg_temp.sid(507))$q$),'GL055:member_unavailable','SHP-010 blocked member sale refusal passes through');
reset role;
select is((select status::text from public.shop_reservations where id=pg_temp.sid(9112)),'reserved','SHP-010 member refusal keeps reservation open');
select is((select count(*)::integer from public.payments where tenant_id=pg_temp.sid(1)),2,'SHP-010 member refusal creates no partial payment');
update public.addon_products set stock_quantity=0 where id=pg_temp.sid(112);
select is(app.shop_held_quantity(pg_temp.sid(1),pg_temp.sid(112)),1,'SHP-006 lowering stock preserves existing hold');
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select available_quantity from public.read_member_shop() where item_id=pg_temp.sid(112)),0,'SHP-006 negative available quantity floors at zero');
reset role;
-- Tenant hourly throttle counts registration, not finalization/deletion.
insert into public.media_assets(tenant_id,kind,staging_object_key,mime,bytes,created_by_staff_id)
select pg_temp.sid(2),'product',pg_temp.stage(n,'product',2),'image/jpeg',100,pg_temp.sid(25) from generate_series(1001,1060)n;
select pg_temp.claim('gym_owner',2,25,null,905);
set local role authenticated;
select is(pg_temp.refusal($q$select public.register_media_asset('product',pg_temp.stage(1061,'product',2),'image/jpeg',100)$q$),'GL086:media_limit','MED-001 sixty registrations per tenant per rolling hour');
reset role;
select is((select count(*)::integer from public.media_assets where tenant_id=pg_temp.sid(2)),60,'MED-001 throttle refusal adds no row');
select is((select count(*)::integer from public.audit_log where tenant_id=pg_temp.sid(2) and action='media_asset.registered'),0,'MED-011 throttle refusal adds no audit');
select pg_temp.claim('gym_manager',1,22,null,902);
set local role authenticated;
select lives_ok($q$select public.register_media_asset('product',pg_temp.stage(731),'image/jpeg',2097152)$q$,'MED-010 exact byte boundary and other tenant throttle independent');
reset role;
select pg_temp.claim('member',2,null,33,908);
set local role authenticated;
select results_eq($q$select item_id from public.read_member_shop()$q$,$q$select pg_temp.sid(108)$q$,'SHP-024 member isolation works in reverse');
select is(pg_temp.refusal($q$select public.cancel_shop_reservation(pg_temp.sid(9112),null)$q$) like '42501%',true,'SHP-008 foreign member cancellation opaque');
reset role;
select set_config('request.jwt.claims','',true);
set local role anon;
select is(pg_temp.refusal('select * from public.read_member_shop()') like '42501%',true,'SHP-004 anon cannot call catalogue');
select is(pg_temp.refusal('select id from public.media_assets') like '42501%',true,'MED-005 anon has no safe-column grant');
reset role;
-- Temporary harness-only DML grant reaches the invariant as a service writer;
-- production grants were asserted above and are restored before finish.
grant update on public.media_assets to service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('app.media_finalize_command','finalize:'||(select id::text from captured where label='trainer-image'),true);
set local role service_role;
select is(pg_temp.refusal($q$update public.media_assets set object_key=pg_temp.pub(830,'trainer'),verified_source_etag='s',published_etag='p',confirmed_at=statement_timestamp() where id=(select id from captured where label='trainer-image')$q$),'GL086:media_verification_invariant','MED-002 credential service plus exact marker lacks postgres definer context');
select is(pg_temp.refusal($q$update public.media_assets set bytes=101 where id=(select id from captured where label='trainer-image')$q$),'GL086:media_verification_invariant','MED-002 service writer cannot rewrite registration');
reset role;
revoke update on public.media_assets from service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('app.media_finalize_command','finalize:'||(select id::text from captured where label='trainer-image')||':extra',true);
select is(pg_temp.refusal($q$update public.media_assets set object_key=pg_temp.pub(830,'trainer'),verified_source_etag='s',published_etag='p',confirmed_at=statement_timestamp() where id=(select id from captured where label='trainer-image')$q$),'GL086:media_verification_invariant','MED-002 suffix marker is not exact finalization command');
select ok((select pg_get_functiondef(to_regprocedure('public.create_shop_reservation(uuid,integer,uuid)')) ~* 'for\s+update'),'SHP-006 create serializes on product row, two-connection race still required');
select ok((select bool_and(pg_get_functiondef(to_regprocedure(sig)) like '%shop-reservation:%' and pg_get_functiondef(to_regprocedure(sig)) like '%pg_advisory_xact_lock%' and pg_get_functiondef(to_regprocedure(sig)) like '%hashtextextended%') from rpc_contract where sig in ('public.cancel_shop_reservation(uuid,text)','public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid)','app.shop_reservation_mark_fulfilled(uuid,uuid)')),'SHP-010 all three transitions use the prescribed reservation advisory lock namespace');
select * from finish();
rollback;
