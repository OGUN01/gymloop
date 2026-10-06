-- SHP-PAGE-001..005/009, independent visible contract. No implementation/holdout reads.
-- Database bounds, exact tuple order, fresh identity and unchanged business facts.
-- One rollback transaction; trusted fixtures are restored to ordinary triggers before reads.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(59);

create function pg_temp.page_id(n integer) returns uuid language sql immutable as $$select ('85000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.page_claim(r text default 'member', t integer default 1, s integer default null, m integer default 31, u integer default 906, extra jsonb default '{}'::jsonb) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',(jsonb_strip_nulls(jsonb_build_object('role','authenticated','app_role',r,'tenant_id',pg_temp.page_id(t),'staff_id',pg_temp.page_id(s),'member_id',pg_temp.page_id(m),'sub',pg_temp.page_id(u)))||extra)::text,true); end$$;
create function pg_temp.page_refusal(q text) returns text language plpgsql as $$declare c text; begin execute q; return 'NO ERROR'; exception when others then get stacked diagnostics c=returned_sqlstate; return c; end$$;
grant execute on function pg_temp.page_id(integer),pg_temp.page_claim(text,integer,integer,integer,integer,jsonb),pg_temp.page_refusal(text) to authenticated,anon,service_role;

select ok(to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') is not null,'SHP-PAGE-001 additive exact two-argument page RPC exists');
select ok((select prosecdef and provolatile='s' and pg_get_userbyid(proowner)='postgres' and proconfig @> array['search_path=""'] and pronargdefaults=2 from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),'SHP-PAGE-001 exact postgres STABLE definer, empty path, two defaults');
select ok(has_function_privilege('authenticated',to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)'),'EXECUTE'),'SHP-PAGE-001 authenticated execute granted');
select ok(not has_function_privilege('anon',to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)'),'EXECUTE') and not has_function_privilege('service_role',to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)'),'EXECUTE'),'SHP-PAGE-001 anon and service role execute denied');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') and a.grantee=0 and a.privilege_type='EXECUTE'),'SHP-PAGE-001 PUBLIC execute revoked');
select results_eq($q$select n::text collate "default" from pg_proc p cross join lateral unnest(p.proargnames,p.proargmodes) a(n,m) where p.oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') and m='t' order by array_position(p.proargnames,n)$q$,$q$select * from (values('active_reservations'::text collate "default"),('history'::text collate "default"),('next_after_created_at'::text collate "default"),('next_after_id'::text collate "default"),('as_of'::text collate "default")) e$q$,'SHP-PAGE-004 exact five output fields without storage or identity metadata');
select ok(exists(select 1 from pg_index where indrelid='public.shop_reservations'::regclass and indisvalid and pg_get_indexdef(indexrelid) like '%(tenant_id, member_id, created_at DESC, id DESC)%'),'SHP-PAGE-002 tenant/member-leading precise history order has an index');
select ok(exists(select 1 from pg_index where indrelid='public.shop_reservations'::regclass and indisvalid and pg_get_indexdef(indexrelid) like '%(tenant_id, member_id, expires_at%'),'SHP-PAGE-002 tenant/member-leading reserved-expiry order has an index');

insert into public.organizations(id,name,gym_code,status) values(pg_temp.page_id(1),'Page Gym A','PAGE8A','active'),(pg_temp.page_id(2),'Page Gym B','PAGE8B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.page_id(11),pg_temp.page_id(1),'A',true),(pg_temp.page_id(12),pg_temp.page_id(2),'B',true);
insert into auth.users(id) select pg_temp.page_id(n) from generate_series(901,909)n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values(pg_temp.page_id(21),pg_temp.page_id(1),pg_temp.page_id(901),pg_temp.page_id(11),'gym_owner','Owner'),(pg_temp.page_id(22),pg_temp.page_id(1),pg_temp.page_id(902),pg_temp.page_id(11),'front_desk','Desk'),(pg_temp.page_id(23),pg_temp.page_id(1),pg_temp.page_id(903),pg_temp.page_id(11),'trainer','Trainer');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,date_of_birth) values
(pg_temp.page_id(31),pg_temp.page_id(1),pg_temp.page_id(906),pg_temp.page_id(11),'Page member','+918500000031','1990-01-01'),
(pg_temp.page_id(32),pg_temp.page_id(1),pg_temp.page_id(907),pg_temp.page_id(11),'Second member','+918500000032','1990-01-01'),
(pg_temp.page_id(33),pg_temp.page_id(2),pg_temp.page_id(908),pg_temp.page_id(12),'Foreign member','+918500000033','1990-01-01'),
(pg_temp.page_id(34),pg_temp.page_id(1),pg_temp.page_id(909),pg_temp.page_id(11),'Empty member','+918500000034','1990-01-01');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active)
select pg_temp.page_id(n),pg_temp.page_id(1),'product','Current item '||n,'Disclosed',9007199254740993,'INR',7,100,'Ask desk',true from generate_series(101,106)n;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,stock_quantity,cancellation_terms,is_active) values(pg_temp.page_id(201),pg_temp.page_id(2),'product','Foreign item','Disclosed',100,'INR',7,100,'Ask desk',true);

-- Administratively constructed immutable history, not a command-path test.
set local session_replication_role = replica;
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,receipt_number,paid_at,recorded_by_staff_id)
values(pg_temp.page_id(4002),pg_temp.page_id(1),pg_temp.page_id(31),18014398509481986,'INR','paid','cash','2026-27/000001','2026-09-01T00:00:00Z',pg_temp.page_id(22));
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,quantity,unit_price_paise,total_paise,currency,status,sold_at,sold_by_staff_id,starts_on,expires_on)
values(pg_temp.page_id(4001),pg_temp.page_id(1),pg_temp.page_id(31),pg_temp.page_id(101),pg_temp.page_id(4002),2,9007199254740993,18014398509481986,'INR','completed','2026-09-01T00:00:00Z',pg_temp.page_id(22),'2026-09-01','2026-09-08');
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.page_id(n),pg_temp.page_id(1),pg_temp.page_id(31),pg_temp.page_id(101),'Snapshot item '||n,'product',2,p.quote_version,9007199254740993,'INR','2026-09-01T00:00:00.123000Z'::timestamptz+((n-1001)/2)*interval '1 microsecond','2026-09-02T00:00:00Z' from generate_series(1001,1063)n cross join public.addon_products p where p.id=pg_temp.page_id(101);
update public.shop_reservations set status='cancelled_by_member',cancelled_at='2026-09-01T01:00:00Z' where id=pg_temp.page_id(1063);
update public.shop_reservations set status='cancelled_by_gym',cancelled_at='2026-09-01T01:00:00Z',cancelled_by_staff_id=pg_temp.page_id(22),cancel_reason='Desk cancellation reason' where id=pg_temp.page_id(1062);
update public.shop_reservations set status='fulfilled',fulfilled_at='2026-09-01T01:00:00Z',fulfilled_by_staff_id=pg_temp.page_id(22),order_id=pg_temp.page_id(4001) where id=pg_temp.page_id(1061);
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.page_id(2000+n),pg_temp.page_id(1),pg_temp.page_id(31),p.id,'Active snapshot '||n,'product',1,p.quote_version,9007199254740993,'INR',transaction_timestamp()-interval '1 hour',transaction_timestamp()+greatest(n,2)*interval '1 hour' from generate_series(1,5)n join public.addon_products p on p.id=pg_temp.page_id(100+n);
update public.shop_reservations set quote_version=pg_temp.page_id(9999) where id=pg_temp.page_id(2005);
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.page_id(3001),pg_temp.page_id(1),pg_temp.page_id(32),p.id,'Second member sentinel','product',1,p.quote_version,9007199254740993,'INR','2026-09-01T00:00:00Z','2026-09-02T00:00:00Z' from public.addon_products p where p.id=pg_temp.page_id(101);
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.page_id(3002),pg_temp.page_id(2),pg_temp.page_id(33),p.id,'Foreign tenant sentinel','product',1,p.quote_version,100,'INR','2026-09-01T00:00:00Z','2026-09-02T00:00:00Z' from public.addon_products p where p.id=pg_temp.page_id(201);
insert into public.media_assets(id,tenant_id,kind,staging_object_key,object_key,mime,bytes,created_by_staff_id,confirmed_at,verified_source_etag,published_etag,attached_to_id)
values(pg_temp.page_id(5001),pg_temp.page_id(1),'product',pg_temp.page_id(1)||'/staging/product/'||pg_temp.page_id(5001)||'.jpg',pg_temp.page_id(1)||'/published/product/'||pg_temp.page_id(5002)||'.jpg','image/jpeg',100,pg_temp.page_id(21),transaction_timestamp(),'source','published',pg_temp.page_id(101));
set local session_replication_role = origin;

create temp table page_results(page_no integer, active_reservations jsonb, history jsonb, next_after_created_at timestamptz, next_after_id uuid, as_of timestamptz);
grant all on page_results to authenticated;
create temp table page_expected_history as select id,created_at from public.shop_reservations where member_id=pg_temp.page_id(31) and expires_at<transaction_timestamp();
grant select on page_expected_history to authenticated;
create function pg_temp.page_collect() returns void language plpgsql as $$declare p record; ct timestamptz; ci uuid; i integer:=0; begin loop select * into p from public.read_member_shop_reservation_page(ct,ci); insert into page_results values(i,p.active_reservations,p.history,p.next_after_created_at,p.next_after_id,p.as_of); exit when p.next_after_id is null; ct:=p.next_after_created_at; ci:=p.next_after_id; i:=i+1; if i>20 then raise exception 'Unbounded traversal'; end if; end loop; end$$;
grant execute on function pg_temp.page_collect() to authenticated;
create temp view page_history as select p.page_no,a.ordinality,row from page_results p cross join lateral jsonb_array_elements(p.history) with ordinality a(row,ordinality);
create temp view page_active as select p.page_no,a.ordinality,row from page_results p cross join lateral jsonb_array_elements(p.active_reservations) with ordinality a(row,ordinality);
grant select on page_history,page_active to authenticated;
create function pg_temp.page_business() returns jsonb language sql as $$select jsonb_build_object('reservations',(select jsonb_agg(to_jsonb(r) order by id) from public.shop_reservations r where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))),'products',(select jsonb_agg(to_jsonb(p) order by id) from public.addon_products p where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))),'orders',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))),'payments',(select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))),'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))),'receipts',(select jsonb_agg(to_jsonb(i) order by id) from public.invoices i where tenant_id in(pg_temp.page_id(1),pg_temp.page_id(2))))$$;
create temp table page_before as select pg_temp.page_business() facts;

select pg_temp.page_claim();
set local role authenticated;
select lives_ok('select pg_temp.page_collect()','SHP-PAGE-002 more than fifty history rows can be fully traversed');
select is((select count(*)::integer from page_results),13,'SHP-PAGE-002 initial plus twelve bounded continuations');
select is((select jsonb_array_length(history) from page_results where page_no=0),3,'SHP-PAGE-002 initial history exactly three, lookahead excluded');
select ok((select bool_and(jsonb_array_length(history)=5) from page_results where page_no>0),'SHP-PAGE-002 each continuation returns five and no lookahead');
select is((select count(*)::integer from page_history),63,'SHP-PAGE-002 full traversal reaches every own history row beyond legacy fifty');
select is((select count(distinct row->>'reservation_id')::integer from page_history),63,'SHP-PAGE-003 microsecond/UUID traversal neither skips nor duplicates');
select results_eq($q$select (row->>'reservation_id')::uuid from page_history order by page_no,ordinality$q$,$q$select id from page_expected_history order by created_at desc,id desc$q$,'SHP-PAGE-003 exact timestamp DESC UUID DESC over microseconds and ties');
select is((select next_after_created_at from page_results where page_no=0),(select created_at from page_expected_history where id=pg_temp.page_id(1061)),'SHP-PAGE-003 precise next timestamp is the last returned row, not lookahead');
select is((select next_after_id from page_results where page_no=0),pg_temp.page_id(1061),'SHP-PAGE-003 cursor UUID is the last returned historical UUID');
select ok((select next_after_id is null and next_after_created_at is null and jsonb_array_length(history)=5 from page_results where page_no=12),'SHP-PAGE-003 exact-full final page is terminal without empty speculative request');
select ok((select bool_and(as_of is not null and as_of<=clock_timestamp()) from page_results),'SHP-PAGE-005 every page reports its authoritative decision instant');
select is((select count(*)::integer from page_active),5,'SHP-PAGE-002 all five active holds remain accessible');
select results_eq($q$select (row->>'reservation_id')::uuid from page_active order by ordinality$q$,$q$select * from (values(pg_temp.page_id(2002)),(pg_temp.page_id(2001)),(pg_temp.page_id(2003)),(pg_temp.page_id(2004)),(pg_temp.page_id(2005))) e$q$,'SHP-PAGE-003 active expiry ASC created DESC UUID DESC');
select ok((select bool_and(active_reservations='[]'::jsonb) from page_results where page_no>0),'SHP-PAGE-002 continuation never returns active population');
select ok(not exists(select 1 from page_history where (row->>'reservation_id')::uuid in(pg_temp.page_id(3001),pg_temp.page_id(3002))) and not exists(select 1 from page_history h join page_active a on h.row->>'reservation_id'=a.row->>'reservation_id'),'SHP-PAGE-001 active/history exclude both another member and another tenant');
select ok((select bool_and(jsonb_typeof(row->'unit_price_paise')='string' and row->>'unit_price_paise'='9007199254740993' and row->>'total_paise'='18014398509481986' and row->>'currency'='INR') from page_history),'SHP-PAGE-005 huge integer paise and explicit INR remain exact strings');
select is((select row->>'item_name' from page_history where row->>'reservation_id'=pg_temp.page_id(1063)::text),'Snapshot item 1063','SHP-PAGE-005 saved name remains independent of current item name');
select results_eq($q$select row->>'state' collate "default" from page_history where (row->>'reservation_id')::uuid in(pg_temp.page_id(1061),pg_temp.page_id(1062),pg_temp.page_id(1063)) order by row->>'reservation_id'$q$,$q$select * from (values('fulfilled'::text collate "default"),('cancelled_by_gym'::text collate "default"),('cancelled_by_member'::text collate "default")) e$q$,'SHP-PAGE-005 stored terminal states keep established projection');
select ok((select bool_and(row->>'state'='expired') from page_history where (row->>'reservation_id')::uuid<pg_temp.page_id(1061)),'SHP-PAGE-005 elapsed reserved rows derive expired without writing');
select ok((select bool_and(row->>'state'='reserved') from page_active),'SHP-PAGE-005 unexpired open holds remain reserved');
select is((select row->>'cancel_reason' from page_history where row->>'reservation_id'=pg_temp.page_id(1062)::text),'Desk cancellation reason','SHP-PAGE-005 gym-only cancellation reason preserved');
select ok((select row->'cancel_reason'='null'::jsonb from page_history where row->>'reservation_id'=pg_temp.page_id(1063)::text),'SHP-PAGE-005 member cancellation reason redacted');
select is((select row->>'order_id' from page_history where row->>'reservation_id'=pg_temp.page_id(1061)::text),pg_temp.page_id(4001)::text,'SHP-PAGE-005 fulfilled-only order identifier preserved');
select ok((select bool_and(row->'order_id'='null'::jsonb) from page_history where row->>'state'<>'fulfilled'),'SHP-PAGE-005 other states cannot expose order identifiers');
select ok((select row->>'terms_changed'='true' from page_active where row->>'reservation_id'=pg_temp.page_id(2005)::text) and (select bool_and(row->>'terms_changed'='false') from page_history),'SHP-PAGE-005 terms changed derives only for open holds');
select ok((select bool_and(row->>'image_asset_id'=pg_temp.page_id(5001)::text) from page_history),'SHP-PAGE-005 confirmed undeleted product image IDs preserved');
select results_eq($q$select key::text collate "default" from page_history h cross join lateral jsonb_object_keys(row) key where row->>'reservation_id'=pg_temp.page_id(1063)::text order by key$q$,$q$select * from (values('cancel_reason'::text collate "default"),('created_at'::text collate "default"),('currency'::text collate "default"),('expires_at'::text collate "default"),('image_asset_id'::text collate "default"),('item_id'::text collate "default"),('item_name'::text collate "default"),('order_id'::text collate "default"),('quantity'::text collate "default"),('reservation_id'::text collate "default"),('section'::text collate "default"),('state'::text collate "default"),('terms_changed'::text collate "default"),('total_paise'::text collate "default"),('unit_price_paise'::text collate "default")) e$q$,'SHP-PAGE-004 exact safe per-row projection excludes private storage/contact/tenant metadata');
select is(pg_temp.page_refusal($q$select * from public.read_member_shop_reservation_page('2026-09-01T00:00:00Z',null)$q$),'22023','SHP-PAGE-004 timestamp-only cursor refused');
select is(pg_temp.page_refusal($q$select * from public.read_member_shop_reservation_page(null,pg_temp.page_id(1061))$q$),'22023','SHP-PAGE-004 UUID-only cursor refused');
select is((select count(*)::integer from public.read_member_shop_reservations()),50,'SHP-PAGE-009 legacy reservation RPC retains fifty-row cap');
reset role;
select is(pg_temp.page_business(),(select facts from page_before),'SHP-PAGE-005 reads and cursor refusals change no reservation, stock, sale, payment, audit or receipt facts');

-- Unknown cursor UUID remains a position, never another caller's authority.
select pg_temp.page_claim('member',1,null,32,907);
set local role authenticated;
select is((select jsonb_array_length(history) from public.read_member_shop_reservation_page('2027-01-01T00:00:00Z',pg_temp.page_id(1061))),1,'SHP-PAGE-001 foreign-member cursor cannot widen caller scope');
select is((select history->0->>'reservation_id' from public.read_member_shop_reservation_page()),pg_temp.page_id(3001)::text,'SHP-PAGE-001 second member reads only own row');
reset role;
select pg_temp.page_claim('member',2,null,33,908);
set local role authenticated;
select is((select history->0->>'reservation_id' from public.read_member_shop_reservation_page()),pg_temp.page_id(3002)::text,'SHP-PAGE-001 other tenant gets only own row');
reset role;
select pg_temp.page_claim('member',1,null,34,909);
set local role authenticated;
select ok((select active_reservations='[]'::jsonb and history='[]'::jsonb and next_after_created_at is null and next_after_id is null from public.read_member_shop_reservation_page()),'SHP-PAGE-003 empty caller page has an explicit terminal signal');
reset role;

-- Every denied audience uses a partial pair to prove actor-before-argument order.
create temp table page_bad_claims(label text,claims jsonb);
insert into page_bad_claims values
('anonymous','{}'),
('owner',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(901),'app_role','gym_owner','tenant_id',pg_temp.page_id(1),'staff_id',pg_temp.page_id(21))),
('front desk',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(902),'app_role','front_desk','tenant_id',pg_temp.page_id(1),'staff_id',pg_temp.page_id(22))),
('trainer',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(903),'app_role','trainer','tenant_id',pg_temp.page_id(1),'staff_id',pg_temp.page_id(23))),
('platform',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(901),'app_role','super_admin')),
('preview',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(906),'app_role','member','tenant_id',pg_temp.page_id(1),'member_id',pg_temp.page_id(31),'impersonation_session_id',pg_temp.page_id(999))),
('foreign tenant binding',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(906),'app_role','member','tenant_id',pg_temp.page_id(2),'member_id',pg_temp.page_id(31))),
('foreign user binding',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(907),'app_role','member','tenant_id',pg_temp.page_id(1),'member_id',pg_temp.page_id(31))),
('contradictory staff',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(906),'app_role','member','tenant_id',pg_temp.page_id(1),'member_id',pg_temp.page_id(31),'staff_id',pg_temp.page_id(21))),
('missing member',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(906),'app_role','member','tenant_id',pg_temp.page_id(1))),
('malformed tenant',jsonb_build_object('role','authenticated','sub',pg_temp.page_id(906),'app_role','member','tenant_id','malformed','member_id',pg_temp.page_id(31))),
('malformed subject',jsonb_build_object('role','authenticated','sub','malformed','app_role','member','tenant_id',pg_temp.page_id(1),'member_id',pg_temp.page_id(31)));
grant select on page_bad_claims to authenticated;
create function pg_temp.page_denials() returns setof text language plpgsql as $$declare c record; begin for c in select * from page_bad_claims order by label loop perform set_config('request.jwt.claims',c.claims::text,true); return next is(pg_temp.page_refusal($q$select * from public.read_member_shop_reservation_page(null,pg_temp.page_id(1061))$q$),'42501','SHP-PAGE-001 '||c.label||' refused before partial cursor'); end loop; end$$;
grant execute on function pg_temp.page_denials() to authenticated;
set local role authenticated;
select * from pg_temp.page_denials();
reset role;
select pg_temp.page_claim();
update public.members set status='blocked' where id=pg_temp.page_id(31);
set local role authenticated;
select is(pg_temp.page_refusal('select * from public.read_member_shop_reservation_page()'),'42501','SHP-PAGE-001 inactive member refused without feature data');
reset role;
update public.members set status='active' where id=pg_temp.page_id(31);
update public.members set user_id=null where id=pg_temp.page_id(31);
set local role authenticated;
select is(pg_temp.page_refusal('select * from public.read_member_shop_reservation_page()'),'42501','SHP-PAGE-001 formerly valid but unlinked member refused');
reset role;
update public.members set user_id=pg_temp.page_id(906) where id=pg_temp.page_id(31);

-- Five holds without history, then deliberate unexpected sixth active row.
set local session_replication_role = replica;
update public.shop_reservations set member_id=pg_temp.page_id(34) where id between pg_temp.page_id(2001) and pg_temp.page_id(2005);
set local session_replication_role = origin;
select pg_temp.page_claim('member',1,null,34,909);
set local role authenticated;
select ok((select jsonb_array_length(active_reservations)=5 and history='[]'::jsonb and next_after_id is null from public.read_member_shop_reservation_page()),'SHP-PAGE-002 five holds/no history returns all holds and no continuation');
reset role;
set local session_replication_role = replica;
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,created_at,expires_at)
select pg_temp.page_id(2006),pg_temp.page_id(1),pg_temp.page_id(34),p.id,'Unexpected sixth','product',1,p.quote_version,p.price_paise,'INR',transaction_timestamp(),transaction_timestamp()+interval '6 hours' from public.addon_products p where p.id=pg_temp.page_id(106);
set local session_replication_role = origin;
set local role authenticated;
select isnt(pg_temp.page_refusal('select * from public.read_member_shop_reservation_page()'),'NO ERROR','SHP-PAGE-002 unexpected sixth active hold refuses instead of silently hiding it');
reset role;

select * from finish();
rollback;
