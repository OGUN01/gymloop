-- Independent visible PAY contract suite; implementation and holdout suites not read.
-- Schema is absent today: every statement below is expected RED until the PAY
-- migration lands. Nothing here creates schema.
-- Not exercised here (needs a clock seam or true cross-connection races, owned by
-- the holdout/orchestrator rounds): wall-clock expiry passage, concurrent
-- accept-vs-counter-sale on separate connections, cancel-vs-record interleaving.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(143);

create function pg_temp.sid(n integer) returns uuid language sql immutable as $$select ('79100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text, t integer default 1, s integer default null, m integer default null, u integer default null, extra jsonb default '{}'::jsonb) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',(jsonb_strip_nulls(jsonb_build_object('role','authenticated','app_role',r,'tenant_id',pg_temp.sid(t),'staff_id',pg_temp.sid(s),'member_id',pg_temp.sid(m),'sub',pg_temp.sid(u)))||extra)::text,true); end$$;
create function pg_temp.refusal(q text) returns text language plpgsql as $$declare d text; c text; begin execute q; return 'NO ERROR'; exception when others then get stacked diagnostics c=returned_sqlstate,d=pg_exception_detail; return c||case when coalesce(d,'')='' then '' else ':'||d end; end$$;
grant execute on function pg_temp.sid(integer),pg_temp.claim(text,integer,integer,integer,integer,jsonb),pg_temp.refusal(text) to authenticated,anon,service_role;
create temp table req(label text primary key, id uuid);
create temp table mem_before(id uuid primary key, ends_on date);
create temp table money_before(p bigint, o bigint);
grant select on req,mem_before,money_before to authenticated,service_role;

-- BUY-005 exact database vocabularies.
select enum_has_labels('public','purchase_request_kind',array['shop','pt','renewal'],'BUY-005 exact request kind vocabulary');
select enum_has_labels('public','purchase_request_status',array['requested','owner_accepted','payment_proof_uploaded','recorded','mismatch_recorded','rejected','cancelled','expired'],'BUY-005 exact request status vocabulary including mismatch_recorded');
select enum_has_labels('public','payment_proof_status',array['active','superseded','rejected','bound'],'BUY-005 exact proof disposition vocabulary');

-- BUY-019 database defense: RLS, revoked client access, safe RPC-only reads.
select ok((select bool_and(relrowsecurity) from pg_class where oid in ('public.purchase_requests'::regclass,'public.payment_proofs'::regclass)),'BUY-019 both new tables enable RLS');
select ok(not has_table_privilege('authenticated','public.purchase_requests','INSERT,UPDATE,DELETE'),'BUY-019 no authenticated DML on requests');
select ok(not has_table_privilege('authenticated','public.payment_proofs','INSERT,UPDATE,DELETE,SELECT'),'BUY-009/019 no authenticated proof DML or metadata SELECT');
select ok(not has_table_privilege('anon','public.purchase_requests','SELECT,INSERT,UPDATE,DELETE') and not has_table_privilege('anon','public.payment_proofs','SELECT,INSERT,UPDATE,DELETE') and has_table_privilege('service_role','public.purchase_requests','SELECT') and has_table_privilege('service_role','public.payment_proofs','SELECT') and not has_table_privilege('service_role','public.purchase_requests','INSERT,UPDATE,DELETE') and not has_table_privilege('service_role','public.payment_proofs','INSERT,UPDATE,DELETE'),'BUY-019 anon denied, service read-only');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid='public.payment_proofs'::regclass and attnum>0 and not attisdropped and has_column_privilege('authenticated',attrelid,attnum,'SELECT') order by attname$q$,$q$select * from (values('none'::text collate "default")) where false$q$,'BUY-009 member has zero direct proof columns, keys and ETags unreachable');
select ok((select count(*)>0 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='purchase_requests' and pg_get_indexdef(i.indexrelid) like '%(tenant_id, member_id)%'),'BUY-019 tenant-leading member lookup index on requests');
select ok((select count(*)>0 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='payment_proofs' and pg_get_indexdef(i.indexrelid) like '%(tenant_id, request_id)%'),'BUY-019 tenant-leading request lookup index on proofs');
select ok((select count(*)>0 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='purchase_requests' and i.indisunique and pg_get_indexdef(i.indexrelid) like '%recorded_payment_id%'),'BUY-015 unique request-to-payment binding');
select ok((select count(*)>0 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='payment_proofs' and i.indisunique and pg_get_indexdef(i.indexrelid) like '%request_id%') and (select count(*)>0 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='payment_proofs' and i.indisunique and pg_get_expr(i.indpred,i.indrelid) like '%active%'),'BUY-010/015 unique proof-to-request and one active proof per request');
select ok((select count(*)>0 from pg_constraint where conrelid='public.purchase_requests'::regclass and contype='f' and pg_get_constraintdef(oid) like '%members%' and pg_get_constraintdef(oid) like '%(tenant_id, member_id)%'),'BUY-015 composite tenant/member FK on requests');
select ok((select count(*)>0 from pg_constraint where conrelid='public.payment_proofs'::regclass and contype='f' and pg_get_constraintdef(oid) like '%purchase_requests%' and pg_get_constraintdef(oid) like '%(tenant_id, request_id)%'),'BUY-015 composite tenant/request FK on proofs');

-- Frozen public RPC surface: exact signatures, ownership, volatility, grants.
create temp table rpc_contract(sig text,definer boolean,vol text,grantee text);
insert into rpc_contract values
('public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid)',true,'v','authenticated'),
('public.accept_purchase_request(uuid,uuid,uuid)',true,'v','authenticated'),
('public.reconfirm_purchase_quote(uuid,uuid,uuid)',true,'v','authenticated'),
('public.cancel_purchase_request(uuid,uuid)',true,'v','authenticated'),
('public.reject_purchase_request(uuid,uuid,uuid,text,uuid)',true,'v','authenticated'),
('public.attach_payment_proof(uuid,uuid,uuid,uuid)',true,'v','authenticated'),
('public.reject_payment_proof(uuid,uuid,uuid,uuid,text,uuid)',true,'v','authenticated'),
('public.record_purchase_request(uuid,uuid,uuid,text,text,text)',false,'v','authenticated'),
('public.read_member_purchase_requests(integer,timestamptz,uuid)',true,'s','authenticated'),
('public.read_purchase_requests(integer,timestamptz,uuid)',true,'s','authenticated'),
('public.read_purchase_request(uuid)',true,'s','authenticated');
select ok((select count(*)=11 and bool_and(p.oid is not null and p.prosecdef=c.definer and p.provolatile::text=c.vol and p.proconfig @> array['search_path=""'] and pg_get_userbyid(p.proowner)='postgres') from rpc_contract c left join pg_proc p on p.oid=to_regprocedure(c.sig)),'BUY-019 exact eleven signatures, owners, volatility and empty paths');
select ok((select bool_and(has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE') and not has_function_privilege('anon',to_regprocedure(sig),'EXECUTE')) from rpc_contract),'BUY-019 authenticated-only execution, anon denied');
select ok((select bool_and(not has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE')) from rpc_contract),'BUY-019 service_role holds no application-command EXECUTE');

-- Fixtures: two gyms, staff, members, products, plans, memberships, proof media.
insert into public.organizations(id,name,gym_code,status) values(pg_temp.sid(1),'PAY A','PAY79A','active'),(pg_temp.sid(2),'PAY B','PAY79B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.sid(11),pg_temp.sid(1),'A',true),(pg_temp.sid(12),pg_temp.sid(2),'B',true);
insert into auth.users(id) select pg_temp.sid(n) from generate_series(901,909)n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.sid(21),pg_temp.sid(1),pg_temp.sid(901),pg_temp.sid(11),'gym_owner','Owner'),(pg_temp.sid(22),pg_temp.sid(1),pg_temp.sid(902),pg_temp.sid(11),'gym_manager','Manager'),(pg_temp.sid(23),pg_temp.sid(1),pg_temp.sid(903),pg_temp.sid(11),'front_desk','Desk'),(pg_temp.sid(24),pg_temp.sid(1),pg_temp.sid(904),pg_temp.sid(11),'trainer','Trainer'),(pg_temp.sid(25),pg_temp.sid(2),pg_temp.sid(905),pg_temp.sid(12),'gym_owner','Other owner');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,date_of_birth,status) values
(pg_temp.sid(31),pg_temp.sid(1),pg_temp.sid(906),pg_temp.sid(11),'Member A','+917910000031','1990-01-01','active'),
(pg_temp.sid(32),pg_temp.sid(1),pg_temp.sid(907),pg_temp.sid(11),'Member A2','+917910000032','1990-01-01','active'),
(pg_temp.sid(33),pg_temp.sid(2),pg_temp.sid(908),pg_temp.sid(12),'Member B','+917910000033','1990-01-01','active'),
(pg_temp.sid(34),pg_temp.sid(1),pg_temp.sid(909),pg_temp.sid(11),'Member Blocked','+917910000034','1990-01-01','blocked');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,gst_rate_bp,validity_days,stock_quantity,session_count,cancellation_terms,is_active,trainer_staff_id) values
(pg_temp.sid(101),pg_temp.sid(1),'product','Whey','Disclosed',250000,'INR',1800,7,10,null,'Desk collection',true,null),
(pg_temp.sid(102),pg_temp.sid(1),'product','Last unit','Disclosed',10000,'INR',1800,7,1,null,'Desk collection',true,null),
(pg_temp.sid(103),pg_temp.sid(1),'product','Hidden','Disclosed',10000,'INR',1800,7,5,null,'Desk collection',false,null),
(pg_temp.sid(104),pg_temp.sid(1),'product','Free item','Disclosed',0,'INR',1800,7,5,null,'Desk collection',true,null),
(pg_temp.sid(105),pg_temp.sid(1),'pt_package','PT pack of ten','Disclosed',500000,'INR',1800,30,null,10,'Desk collection',true,pg_temp.sid(24)),
(pg_temp.sid(108),pg_temp.sid(2),'product','Foreign product','Disclosed',10000,'INR',1800,7,2,null,'Desk collection',true,null);
create temp table quotes as select id,quote_version from public.addon_products where tenant_id in(pg_temp.sid(1),pg_temp.sid(2));
grant select on quotes to authenticated,service_role;
insert into public.plans(id,tenant_id,name,duration_days,price_paise,gst_rate_bp,is_active) values
(pg_temp.sid(121),pg_temp.sid(1),'Monthly',30,100000,1800,true),(pg_temp.sid(122),pg_temp.sid(1),'Retired',30,100000,1800,false);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,price_paise,discount_paise,currency,duration_days,starts_on,ends_on,periods_granted,activated_at) values
(pg_temp.sid(131),pg_temp.sid(1),pg_temp.sid(31),pg_temp.sid(121),'active',100000,10000,'INR',30,current_date-10,current_date+20,0,now()),
(pg_temp.sid(132),pg_temp.sid(1),pg_temp.sid(32),pg_temp.sid(121),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now()),
(pg_temp.sid(133),pg_temp.sid(2),pg_temp.sid(33),pg_temp.sid(121),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now()),
(pg_temp.sid(134),pg_temp.sid(1),pg_temp.sid(32),pg_temp.sid(122),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now());
insert into mem_before select id,ends_on from public.memberships where id in(pg_temp.sid(131),pg_temp.sid(132));
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,object_key,confirmed_at,created_by_staff_id) values
(pg_temp.sid(141),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/payment_proof/'||pg_temp.sid(141)::text||'.jpg',pg_temp.sid(1)::text||'/published/payment_proof/'||pg_temp.sid(141)::text||'.jpg',now(),null),
(pg_temp.sid(142),pg_temp.sid(1),'product','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/product/'||pg_temp.sid(142)::text||'.jpg',pg_temp.sid(1)::text||'/published/product/'||pg_temp.sid(142)::text||'.jpg',now(),pg_temp.sid(23)),
(pg_temp.sid(143),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/payment_proof/'||pg_temp.sid(143)::text||'.jpg',null,null,null),
(pg_temp.sid(144),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/payment_proof/'||pg_temp.sid(144)::text||'.jpg',pg_temp.sid(1)::text||'/published/payment_proof/'||pg_temp.sid(144)::text||'.jpg',now(),null),
(pg_temp.sid(145),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/payment_proof/'||pg_temp.sid(145)::text||'.jpg',pg_temp.sid(1)::text||'/published/payment_proof/'||pg_temp.sid(145)::text||'.jpg',now(),null),
(pg_temp.sid(146),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.sid(1)::text||'/staging/payment_proof/'||pg_temp.sid(146)::text||'.jpg',pg_temp.sid(1)::text||'/published/payment_proof/'||pg_temp.sid(146)::text||'.jpg',now(),null);

-- BUY-001 actor matrix: canonical claims validated before any target lookup.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal('select public.accept_purchase_request(null,null,null)') like '42501%',true,'BUY-001 member cannot invoke the staff accept command');
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 actor precedes malformed create input');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 staff cannot invoke the member create command');
reset role;
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is(pg_temp.refusal('select public.accept_purchase_request(null,null,null)') like '42501%',true,'BUY-001 trainer has no front-office accept authority');
reset role;
select pg_temp.claim('member',1,null,31,906,jsonb_build_object('impersonation_session_id',pg_temp.sid(999)));
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 impersonation cannot create requests');
reset role;
select pg_temp.claim('member',1,21,31,906);
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 contradictory staff and member claims refused');
reset role;
select pg_temp.claim('member',1,null,31,907);
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 member claim bound to its own Auth subject');
reset role;
select pg_temp.claim('member',1,null,34,909);
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,null,null,null,null)') like '42501%',true,'BUY-001 blocked member refused before any target lookup');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal('select public.create_purchase_request(null,''shop'',null,null,null)'),'22023','BUY-002 null request key refused as shape after actor');

-- BUY-002/003/018 member creates: typed intent, disclosed snapshot, scope and caps.
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),2,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-002 shop request created under its request key');
insert into req select 'K1',id from public.purchase_requests where request_key=pg_temp.sid(501);
select results_eq($q$select status::text collate "default" from public.purchase_requests where request_key=pg_temp.sid(501)$q$,$q$select * from (values('requested'::text collate "default")) as expected$q$,'BUY-002 new request starts requested');
select ok((select snapshot ?| array['pricePaise','unitPricePaise','totalPaise'] and snapshot->>'currency'='INR' from public.purchase_requests where request_key=pg_temp.sid(501)),'BUY-002 disclosed server snapshot carries price and explicit currency');
select is((select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),2,(select quote_version from quotes where id=pg_temp.sid(101))) ->>'replayed'),'true','BUY-016 identical create replay returns the original result');
select is((select count(*) from public.purchase_requests where request_key=pg_temp.sid(501)),1,'BUY-016 replay created no second request');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),3,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like 'GL068%',true,'BUY-016 changed facts under the same key conflict');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(502),'shop',pg_temp.sid(108),1,(select quote_version from quotes where id=pg_temp.sid(108)))$q$),'GL086:item_unavailable','BUY-003 cross-tenant offer not purchasable');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(503),'shop',pg_temp.sid(103),1,(select quote_version from quotes where id=pg_temp.sid(103)))$q$),'GL086:item_unavailable','BUY-003 inactive offer not purchasable');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(504),'shop',pg_temp.sid(104),1,(select quote_version from quotes where id=pg_temp.sid(104)))$q$) <> 'NO ERROR',true,'BUY-003 complimentary offers stay on the desk path');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(505),'shop',pg_temp.sid(101),11,(select quote_version from quotes where id=pg_temp.sid(101)))$q$),'GL086:invalid_quantity','BUY-018 quantity above the SHP maximum refused');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(506),'pt',pg_temp.sid(105),2,(select quote_version from quotes where id=pg_temp.sid(105)))$q$),'GL086:invalid_quantity','BUY-002 PT quantity is exactly one');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(507),'pt',pg_temp.sid(105),1,(select quote_version from quotes where id=pg_temp.sid(105)))$q$,'BUY-003 PT programme request accepted for create');
insert into req select 'KPT',id from public.purchase_requests where request_key=pg_temp.sid(507);
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(508),'renewal',pg_temp.sid(133),1,null)$q$) like 'P0002%',true,'BUY-003 foreign membership is not a renewal target');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(509),'renewal',pg_temp.sid(134),1,null)$q$) <> 'NO ERROR',true,'BUY-003 membership on an inactive plan routes to the desk');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(511),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 open request two of five');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(512),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 open request three of five');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(513),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 open request four of five');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(514),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 open request five of five');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(515),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) <> 'NO ERROR',true,'BUY-018 sixth open request refused');
insert into req select 'K4',id from public.purchase_requests where request_key=pg_temp.sid(513);
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='K4'),pg_temp.sid(601))$q$,'BUY-018 cancelling opens capacity again');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(515),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 same key reused only after the old request closed');
insert into req select 'K6',id from public.purchase_requests where request_key=pg_temp.sid(515);
insert into req select 'K5',id from public.purchase_requests where request_key=pg_temp.sid(514);

-- BUY-004 acceptance: front-office only, rechecks, hard hold, disclosed expiry.
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(602))$q$,'BUY-004 desk accepts the shop request');
insert into req select 'KA',id from public.purchase_requests where request_key=pg_temp.sid(511);
insert into req select 'KB',id from public.purchase_requests where request_key=pg_temp.sid(512);
select results_eq($q$select status::text collate "default" from public.purchase_requests where request_key=pg_temp.sid(501)$q$,$q$select * from (values('owner_accepted'::text collate "default")) as expected$q$,'BUY-004 accepted state recorded');
select ok((select accepted_revision is not null and accepted_at is not null from public.purchase_requests where request_key=pg_temp.sid(501)),'BUY-004 accepted revision and time persisted');
select results_eq($q$select expires_at = accepted_at + interval '24 hours' from public.purchase_requests where request_key=pg_temp.sid(501)$q$,$q$select * from (values(true)) as expected$q$,'BUY-018 acceptance TTL is twenty-four hours from acceptance');
select ok((select count(*)=1 from audit_log where action='purchase_request.accepted' and record_id=(select id from req where label='K1')),'BUY-020 acceptance audited atomically');
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KA'),(select quote_version from quotes where id=pg_temp.sid(102)),pg_temp.sid(603))$q$,'BUY-004 first acceptance of the last unit wins');
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='KB'),(select quote_version from quotes where id=pg_temp.sid(102)),pg_temp.sid(604))$q$) like 'GL123%',true,'BUY-004/GL123 second acceptance of the last unit loses to the hard hold');
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(602))$q$) like 'GL068%',true,'BUY-016 accept replay resolves read-only');
reset role;
select pg_temp.claim('gym_owner',2,25,null,905);
set local role authenticated;
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(605))$q$) like 'P0002%',true,'BUY-019 foreign request invisible to another tenant');
reset role;
select pg_temp.claim('gym_manager',1,22,null,902);
set local role authenticated;
select lives_ok($q$update public.addon_products set price_paise=300000 where id=pg_temp.sid(101)$q$,'BUY-004 desk reprices the offer before acceptance of a stale quote');
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='K5'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(606))$q$),'GL086:quote_changed','BUY-004 stale quote refused after a price change');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.reconfirm_purchase_quote((select id from req where label='K5'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(607))$q$,'BUY-004 member reconfirms the revised quote');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='K5'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(608))$q$,'BUY-004 acceptance after explicit member reconfirmation');

-- BUY-006 member cancellation: ownership, hold release, no later activation.
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.record_addon_sale(pg_temp.sid(31),pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)),null,null,null,'cash','Counter sale over the hold',pg_temp.sid(640))$q$) like 'GL123%',true,'BUY-004/GL123 counter sale cannot consume accepted PAY stock');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_shop_reservation(pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)))$q$) like 'GL123%',true,'BUY-004/GL123 SHP member reservation cannot consume accepted PAY stock');
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='KA'),pg_temp.sid(609))$q$,'BUY-006 member cancels an accepted request');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='KA')$q$,$q$select * from (values('cancelled'::text collate "default")) as expected$q$,'BUY-006 cancelled state recorded');
select lives_ok($q$select public.record_addon_sale(pg_temp.sid(31),pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)),null,null,null,'cash','Counter sale after hold release',pg_temp.sid(610))$q$,'BUY-006 hard hold released on cancellation');
select is((select public.cancel_purchase_request((select id from req where label='KA'),pg_temp.sid(609)) ->>'replayed'),'true','BUY-016 cancel replay resolves read-only');
select is((select count(*) from audit_log where action='purchase_request.cancelled' and record_id=(select id from req where label='KA')),1,'BUY-020 cancel replay appended no second audit');
reset role;
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
select is(pg_temp.refusal($q$update public.addon_products set stock_quantity=5 where id=pg_temp.sid(101)$q$) like 'GL123%',true,'BUY-004/GL123 inventory adjustment cannot consume accepted PAY stock');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KA'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KA')),pg_temp.sid(611),'10000','INR','cash')$q$) <> 'NO ERROR',true,'BUY-006 cancelled request never activates a purchase');
reset role;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.refusal($q$select public.cancel_purchase_request((select id from req where label='K6'),pg_temp.sid(612))$q$) like 'P0002%',true,'BUY-006 only the owning member cancels');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.cancel_purchase_request((select id from req where label='K6'),pg_temp.sid(613))$q$) <> 'NO ERROR',true,'BUY-006 cancellation needs member ownership, not staff role');

-- BUY-008/010/011 proof attach, replacement and reasoned rejection.
reset role;
insert into money_before select (select count(*) from public.payments),(select count(*) from public.addon_orders);
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(144),null,pg_temp.sid(614))$q$) <> 'NO ERROR',true,'BUY-008 proof attach requires the accepted live request');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(147),null,pg_temp.sid(615))$q$) <> 'NO ERROR',true,'BUY-008 unknown asset refused without existence detail');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(142),null,pg_temp.sid(616))$q$) <> 'NO ERROR',true,'BUY-008 non-proof media kind refused');
select lives_ok($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(144),null,pg_temp.sid(617))$q$,'BUY-008 verified proof attached to the accepted request');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='K6')$q$,$q$select * from (values('payment_proof_uploaded'::text collate "default")) as expected$q$,'BUY-005 upload state recorded');
select ok((select count(*)=1 from public.payment_proofs where request_id=(select id from req where label='K6') and disposition='active'),'BUY-010 exactly one active proof');
select lives_ok($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(145),null,pg_temp.sid(618))$q$,'BUY-010 member replaces the proof before verification');
select results_eq($q$select disposition::text collate "default" from public.payment_proofs where asset_id=pg_temp.sid(144)$q$,$q$select * from (values('superseded'::text collate "default")) as expected$q$,'BUY-010 superseded proof is immutable history');
select results_eq($q$select asset_id from public.payment_proofs where request_id=(select id from req where label='K6') and disposition='active'$q$,$q$select * from (values(pg_temp.sid(145))) as expected$q$,'BUY-010 replacement is the single active proof');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(144),null,pg_temp.sid(619))$q$) like 'GL124%',true,'BUY-010/GL124 superseded proof cannot regain active status');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),(select quote_version from quotes where id=pg_temp.sid(101)),'Photo unclear',pg_temp.sid(620))$q$,'BUY-011 desk rejects the proof with a member-visible reason');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='K6')$q$,$q$select * from (values('owner_accepted'::text collate "default")) as expected$q$,'BUY-011 proof rejection returns the request to accepted');
select results_eq($q$select disposition::text collate "default" from public.payment_proofs where asset_id=pg_temp.sid(145)$q$,$q$select * from (values('rejected'::text collate "default")) as expected$q$,'BUY-011 rejected proof retained as decision history');
select results_eq($q$select expires_at = (select expires_at from public.purchase_requests where id=(select id from req where label='K1')) from public.purchase_requests where id=(select id from req where label='K6')$q$,$q$select * from (values(true)) as expected$q$,'BUY-011 rejection retains the original acceptance expiry');
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),(select quote_version from quotes where id=pg_temp.sid(101)),'ab',pg_temp.sid(621))$q$),'22023','BUY-011 reason below three characters refused');
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),(select quote_version from quotes where id=pg_temp.sid(101)),repeat('x',201),pg_temp.sid(622))$q$),'22023','BUY-011 reason above two hundred characters refused');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),(select quote_version from quotes where id=pg_temp.sid(101)),'Member says no',pg_temp.sid(623))$q$) like '42501%',true,'BUY-011 only the desk rejects proofs');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(143),null,pg_temp.sid(624))$q$) <> 'NO ERROR',true,'BUY-008 unconfirmed media cannot become an active proof');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.reject_purchase_request((select id from req where label='K6'),(select quote_version from quotes where id=pg_temp.sid(101)),'Wrong item requested',pg_temp.sid(625))$q$,'BUY-011 desk rejects the request with a reason');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='K6')$q$,$q$select * from (values('rejected'::text collate "default")) as expected$q$,'BUY-005 request rejection is terminal');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='K6'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='K6')),pg_temp.sid(626),'250000','INR','cash')$q$) <> 'NO ERROR',true,'BUY-005 rejected request cannot be recorded');
select is((select count(*) from public.payments)=(select p from money_before) and (select count(*) from public.addon_orders)=(select o from money_before),true,'BUY-008 upload and rejection created no money rows');

-- BUY-012/013 exact-price recording through the unchanged ledger.
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(521),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-012 exact-price shop request created');
insert into req select 'KR1',id from public.purchase_requests where request_key=pg_temp.sid(521);
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KR1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(627))$q$,'BUY-012 exact-price request accepted');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KR1'),pg_temp.sid(146),null,pg_temp.sid(628))$q$,'BUY-012 proof attached before recording');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.record_purchase_request((select id from req where label='KR1'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KR1')),pg_temp.sid(629),'250000','INR','cash')$q$,'BUY-012 exact-price recording succeeds');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='KR1')$q$,$q$select * from (values('recorded'::text collate "default")) as expected$q$,'BUY-005 recorded state is terminal');
select ok((select recorded_payment_id is not null and recorded_order_id is not null from public.purchase_requests where id=(select id from req where label='KR1')),'BUY-015 request bound to its payment and order');
select results_eq($q$select disposition::text collate "default" from public.payment_proofs where asset_id=pg_temp.sid(146)$q$,$q$select * from (values('bound'::text collate "default")) as expected$q$,'BUY-010/015 proof causally bound to the recorded payment');
select ok((select count(*)=1 from public.addon_orders where id=(select recorded_order_id from public.purchase_requests where id=(select id from req where label='KR1'))),'BUY-013 existing ledger order created once');
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),9,'BUY-012 recording consumed the hold as an ordinary sale');
select is((select public.record_purchase_request((select id from req where label='KR1'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KR1')),pg_temp.sid(629),'250000','INR','cash') ->>'replayed'),'true','BUY-016 recording replay returns the original result read-only');
select is((select count(*) from public.addon_orders where id=(select recorded_order_id from public.purchase_requests where id=(select id from req where label='KR1'))),1,'BUY-016 replay created no second order');
select is((select count(*) from audit_log where action='purchase_request.recorded' and record_id=(select id from req where label='KR1')),1,'BUY-020 replay appended no second audit');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KR1'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KR1')),pg_temp.sid(629),'200000','INR','cash')$q$) like 'GL068%',true,'BUY-016 changed amount under the same command key conflicts');

-- BUY-014 mismatched funds recorded honestly without entitlement.
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(522),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-014 mismatch scenario request created');
insert into req select 'KR2',id from public.purchase_requests where request_key=pg_temp.sid(522);
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KR2'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(630))$q$,'BUY-014 mismatch scenario accepted');
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KR2'),pg_temp.sid(141),null,pg_temp.sid(631))$q$,'BUY-014 mismatch scenario proof attached');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.record_purchase_request((select id from req where label='KR2'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KR2')),pg_temp.sid(632),'200000','INR','upi')$q$,'BUY-014 mismatched funds recorded as received');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='KR2')$q$,$q$select * from (values('mismatch_recorded'::text collate "default")) as expected$q$,'BUY-005/014 mismatch closes the request terminally');
select ok((select p.amount_paise=200000 and p.membership_id is null from public.payments p where p.id=(select recorded_payment_id from public.purchase_requests where id=(select id from req where label='KR2'))),'BUY-014 actual amount recorded with no entitlement');
select is((select recorded_order_id from public.purchase_requests where id=(select id from req where label='KR2')),null,'BUY-014 mismatch created no order');
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),9,'BUY-014 mismatch released the hold without a sale');
select is((select public.record_purchase_request((select id from req where label='KR2'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KR2')),pg_temp.sid(632),'200000','INR','upi') ->>'replayed'),'true','BUY-016 mismatch replay resolves read-only');

-- BUY-012/014 renewal at the recorded sold terms with cumulative-period truth.
reset role;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(523),'renewal',pg_temp.sid(131),1,null)$q$,'BUY-003 renewal of the held membership created');
insert into req select 'KRN',id from public.purchase_requests where request_key=pg_temp.sid(523);
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(524),'renewal',pg_temp.sid(132),1,null)$q$,'BUY-014 partial renewal scenario created');
insert into req select 'KRP',id from public.purchase_requests where request_key=pg_temp.sid(524);
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KRN'),null,pg_temp.sid(633))$q$,'BUY-004 renewal accepted');
select ok((select s ? 'membershipId' and s ? 'netPricePaise' from public.purchase_requests s where id=(select id from req where label='KRN')),'renewal revision token pins the held membership and sold terms');
select lives_ok($q$select public.record_purchase_request((select id from req where label='KRN'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KRN')),pg_temp.sid(634),'90000','INR','cash')$q$,'BUY-012 renewal recorded at the sold net price');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='KRN')$q$,$q$select * from (values('recorded'::text collate "default")) as expected$q$,'BUY-005 renewal recorded');
select ok((select p.membership_id=pg_temp.sid(131) and p.amount_paise=90000 from public.payments p where p.id=(select recorded_payment_id from public.purchase_requests where id=(select id from req where label='KRN'))),'BUY-012 renewal payment attached to the held membership at sold terms');
select results_eq($q$select m.ends_on from public.memberships m where m.id=pg_temp.sid(131)$q$,$q$select ends_on + 30 from mem_before where id=pg_temp.sid(131)$q$,'BUY-012 full sold-price renewal grants exactly one recorded period');
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KRP'),null,pg_temp.sid(635))$q$,'BUY-014 partial renewal accepted');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KRP')),pg_temp.sid(636),'50000','USD','cash')$q$) <> 'NO ERROR',true,'BUY-014 unsupported collection currency refused, not converted');
select results_eq($q$select status::text collate "default" from public.purchase_requests where id=(select id from req where label='KRP')$q$,$q$select * from (values('owner_accepted'::text collate "default")) as expected$q$,'BUY-014 refused currency recording changed nothing');
select lives_ok($q$select public.record_purchase_request((select id from req where label='KRP'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KRP')),pg_temp.sid(637),'50000','INR','cash')$q$,'BUY-014 partial renewal money recorded honestly');
select ok((select p.amount_paise=50000 and p.membership_id=pg_temp.sid(132) from public.payments p where p.id=(select recorded_payment_id from public.purchase_requests where id=(select id from req where label='KRP'))),'BUY-014 partial payment attached to the held membership');
select results_eq($q$select m.ends_on from public.memberships m where m.id=pg_temp.sid(132)$q$,$q$select ends_on from mem_before where id=pg_temp.sid(132)$q$,'BUY-014 partial money grants no period and promises none');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),(select accepted_revision from public.purchase_requests where id=(select id from req where label='KRP')),pg_temp.sid(638),'50000','INR','cash')$q$) like 'GL068%',true,'BUY-016 renewal replay key binds exact facts');

-- Trusted-writer bounds and the service boundary.
reset role;
set local role service_role;
select is(pg_temp.refusal('select public.record_purchase_request(null,null,null,null,null,null)') like '42501%',true,'BUY-019 service_role holds no application-command EXECUTE');
reset role;

-- BUY-019 safe reads: scoping, projection, pagination.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(100,null,null) r),11,'BUY-019 member reads exactly own request history');
select is((select count(*) from public.read_member_purchase_requests(100,null,null) r, jsonb_array_elements(r->'requests') e where e::text like '%objectKey%' or e::text like '%object_key%' or e::text ilike '%etag%' or e::text like '%url%'),0,'BUY-009 read models carry no keys, ETags or URLs');
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(2,null,null) r),2,'BUY-018 list clamps to the requested page');
select is((select r->>'nextAfter' is not null from public.read_member_purchase_requests(2,null,null) r),true,'BUY-019 keyset cursor returned for the next page');
reset role;
select pg_temp.claim('member',2,null,33,908);
set local role authenticated;
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(100,null,null) r),0,'BUY-019 another tenant member reads nothing');
reset role;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select ok((select jsonb_array_length(r->'requests') >= 11 from public.read_purchase_requests(100,null,null) r),'BUY-019 front office reads its own tenant queue');
select is(pg_temp.refusal('select public.read_purchase_request(pg_temp.sid(999))') like 'P0002%',true,'BUY-009 unknown request shares the same external refusal');
reset role;
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is(pg_temp.refusal('select public.read_purchase_requests(null,null,null)') like '42501%',true,'BUY-001 trainers have no purchase queue access');
reset role;

-- BUY-020 audit hygiene across the whole flow.
select ok((select count(*)=0 from audit_log a where a.action like 'purchase_request.%' or a.action like 'payment_proof.%') or (select count(*)=0 from audit_log a where (a.action like 'purchase_request.%' or a.action like 'payment_proof.%') and (coalesce(a.before::text,'')||coalesce(a.after::text,'')||coalesce(a.request_facts::text,'')) like '%payment_proof/%'),'BUY-020 no proof object keys or URLs in audit payloads');
select ok((select count(*)>0 from audit_log where action='purchase_request.created' and record_id=(select id from req where label='K1') and actor_user_id=pg_temp.sid(906)),'BUY-020 creation audited with the member actor');
select ok((select count(*)>0 from audit_log where action='purchase_request.accepted' and record_id=(select id from req where label='K1') and actor_user_id=pg_temp.sid(903)),'BUY-020 acceptance audited with the desk actor');
select is(pg_temp.refusal('select public.accept_paid_notification(null,null,1,null)') like 'GL069%',true,'BUY-013 paid-acceptance stub stays denied, zero wallet movement anywhere');

rollback;
