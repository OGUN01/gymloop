-- Independent visible PAY contract suite, authored from the frozen BUY contract.
-- Round 2: the coordinator's 16 adjudicated suite defects are repaired here. Fixture
-- media rows follow the implemented MEDIA invariants (verified product photo through
-- the ordinary registrar and finalizer; proof rows carry a member creator). Request
-- and proof state is read through definer-owned pg_temp helpers so no assertion
-- depends on direct client table SELECT. Wall-clock expiry passage and true
-- cross-connection races (accept vs counter sale, cancel vs record) need a clock seam
-- or separate connections and are owned by the holdout and orchestrator rounds.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(246);

create function pg_temp.sid(n integer) returns uuid language sql immutable as $$select ('79100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text, t integer default 1, s integer default null, m integer default null, u integer default null, extra jsonb default '{}'::jsonb) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',(jsonb_strip_nulls(jsonb_build_object('role','authenticated','app_role',r,'tenant_id',pg_temp.sid(t),'staff_id',pg_temp.sid(s),'member_id',pg_temp.sid(m),'sub',pg_temp.sid(u)))||extra)::text,true); end$$;
create function pg_temp.refusal(q text) returns text language plpgsql as $$declare d text; c text; begin execute q; return 'NO ERROR'; exception when others then get stacked diagnostics c=returned_sqlstate,d=pg_exception_detail; return c||case when coalesce(d,'')='' then '' else ':'||d end; end$$;
create function pg_temp.replayed(q text) returns text language plpgsql as $$declare r jsonb; begin execute q into r; return r->>'replayed'; exception when others then return 'ERR '||sqlstate; end$$;
create function pg_temp.stage(n integer, k text default 'product') returns text language sql immutable as $$select pg_temp.sid(1)::text||'/staging/'||k||'/'||pg_temp.sid(n)::text||'.jpg'$$;
create function pg_temp.pub(n integer, k text default 'product') returns text language sql immutable as $$select pg_temp.sid(1)::text||'/published/'||k||'/'||pg_temp.sid(n)::text||'.jpg'$$;
create temp table req(label text primary key, id uuid);
create temp table assets(label text primary key, id uuid);
create temp table regs(label text primary key, asset uuid, skey text);
create temp table urls(label text primary key, payload jsonb);
create temp table mem_before(id uuid primary key, ends_on date);
create temp table money_before(p bigint, o bigint);
create temp table exp_before(label text primary key, expires_at timestamptz);
grant select, insert on req, assets, regs, urls, mem_before, money_before, exp_before to authenticated, service_role;
-- Definer-owned readers: the postgres-owned helper sees rows past RLS and grants.
create function pg_temp.cap(l text, k integer) returns void language plpgsql security definer as $$begin insert into req select l, id from public.purchase_requests where request_key = pg_temp.sid(k); end$$;
create function pg_temp.rq(l text) returns jsonb language plpgsql security definer as $$begin return (select to_jsonb(r) from public.purchase_requests r where r.id = (select id from req where label = l)); end$$;
create function pg_temp.rev(l text) returns uuid language plpgsql security definer as $$begin return (select r.accepted_revision from public.purchase_requests r where r.id = (select id from req where label = l)); end$$;
create function pg_temp.nkey(k integer) returns integer language plpgsql security definer as $$begin return (select count(*)::integer from public.purchase_requests where request_key = pg_temp.sid(k)); end$$;
create function pg_temp.pj(n integer) returns jsonb language plpgsql security definer as $$begin return (select to_jsonb(p) from public.payment_proofs p where p.asset_id = pg_temp.sid(n)); end$$;
create function pg_temp.nproof(l text, d text) returns integer language plpgsql security definer as $$begin return (select count(*)::integer from public.payment_proofs p where p.request_id = (select id from req where label = l) and p.disposition::text = d); end$$;
create function pg_temp.aproof(l text) returns uuid language plpgsql security definer as $$begin return (select p.asset_id from public.payment_proofs p where p.request_id = (select id from req where label = l) and p.disposition::text = 'active'); end$$;
create function pg_temp.audits(a text, l text) returns integer language plpgsql security definer as $$begin return (select count(*)::integer from public.audit_log where action = a and record_id = (select id from req where label = l)); end$$;
create function pg_temp.reg(l text, rl text) returns void language plpgsql security definer as $$declare r jsonb; begin r := public.register_payment_proof((select id from req where label = rl), 'image/jpeg', 1000); insert into regs(l, asset, skey) values (l, (r->>'assetId')::uuid, r->>'stagingObjectKey'); end$$;
create function pg_temp.regn(rl text, n integer) returns integer language plpgsql security definer as $$declare c integer := 0; begin for i in 1..n loop begin perform public.register_payment_proof((select id from req where label = rl), 'image/jpeg', 1000); c := c + 1; exception when others then null; end; end loop; return c; end$$;
create function pg_temp.mst(l text) returns jsonb language plpgsql security definer as $$begin return (select to_jsonb(m) from public.media_assets m where m.id = (select asset from regs where label = l)); end$$;
create function pg_temp.aaudits(a text, l text) returns integer language plpgsql security definer as $$begin return (select count(*)::integer from public.audit_log where action = a and record_id = (select asset from regs where label = l)); end$$;
grant execute on function pg_temp.sid(integer),pg_temp.claim(text,integer,integer,integer,integer,jsonb),pg_temp.refusal(text),pg_temp.replayed(text),pg_temp.stage(integer,text),pg_temp.pub(integer,text),pg_temp.cap(text,integer),pg_temp.rq(text),pg_temp.rev(text),pg_temp.nkey(integer),pg_temp.pj(integer),pg_temp.nproof(text,text),pg_temp.aproof(text),pg_temp.audits(text,text),pg_temp.reg(text,text),pg_temp.regn(text,integer),pg_temp.mst(text),pg_temp.aaudits(text,text) to authenticated,anon,service_role;

-- BUY-005 exact database vocabularies.
select enum_has_labels('public','purchase_request_kind',array['shop','pt','renewal'],'BUY-005 exact request kind vocabulary');
select enum_has_labels('public','purchase_request_status',array['requested','owner_accepted','payment_proof_uploaded','recorded','mismatch_recorded','rejected','cancelled','expired'],'BUY-005 exact request status vocabulary including mismatch_recorded');
select enum_has_labels('public','payment_proof_status',array['active','superseded','rejected','bound'],'BUY-005 exact proof disposition vocabulary');

-- BUY-019 database defense: RLS, revoked client access, safe RPC-only reads.
select ok((select bool_and(relrowsecurity) from pg_class where oid in ('public.purchase_requests'::regclass,'public.payment_proofs'::regclass)),'BUY-019 both new tables enable RLS');
select ok(not has_table_privilege('authenticated','public.purchase_requests','INSERT,UPDATE,DELETE'),'BUY-019 no authenticated DML on requests');
select ok(not has_table_privilege('authenticated','public.payment_proofs','INSERT,UPDATE,DELETE,SELECT'),'BUY-009/019 no authenticated proof DML or metadata SELECT');
select ok(not has_table_privilege('anon','public.purchase_requests','SELECT,INSERT,UPDATE,DELETE') and not has_table_privilege('anon','public.payment_proofs','SELECT,INSERT,UPDATE,DELETE') and has_table_privilege('service_role','public.purchase_requests','SELECT') and has_table_privilege('service_role','public.payment_proofs','SELECT') and not has_table_privilege('service_role','public.purchase_requests','INSERT,UPDATE,DELETE') and not has_table_privilege('service_role','public.payment_proofs','INSERT,UPDATE,DELETE'),'BUY-019 anon denied, service read-only');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid='public.payment_proofs'::regclass and attnum>0 and not attisdropped and has_column_privilege('authenticated',attrelid,attnum,'SELECT') order by attname$q$,$q$select * from (values('none'::text collate "default")) as expected where false$q$,'BUY-009 member has zero direct proof columns, keys and ETags unreachable');
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
('public.reject_purchase_request(uuid,uuid,text,uuid)',true,'v','authenticated'),
('public.attach_payment_proof(uuid,uuid,uuid,uuid)',true,'v','authenticated'),
('public.reject_payment_proof(uuid,uuid,uuid,text,uuid)',true,'v','authenticated'),
('public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid)',false,'v','authenticated'),
('public.read_member_purchase_requests(integer,timestamptz,uuid)',true,'s','authenticated'),
('public.read_purchase_requests(integer,timestamptz,uuid)',true,'s','authenticated'),
('public.read_purchase_request(uuid)',true,'s','authenticated'),
('public.register_payment_proof(uuid,text,integer)',true,'v','authenticated'),
('public.read_purchase_proof_url(uuid)',false,'s','authenticated');
select ok((select count(*)=13 and bool_and(p.oid is not null and p.prosecdef=c.definer and p.provolatile::text=c.vol and p.proconfig @> array['search_path=""'] and pg_get_userbyid(p.proowner)='postgres') from rpc_contract c left join pg_proc p on p.oid=to_regprocedure(c.sig)),'BUY-019 exact thirteen signatures, owners, volatility and empty paths');
select ok((select bool_and(has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE') and not has_function_privilege('anon',to_regprocedure(sig),'EXECUTE')) from rpc_contract),'BUY-019 authenticated-only execution, anon denied');
select ok((select bool_and(not has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE')) from rpc_contract),'BUY-019 service_role holds no application-command EXECUTE');

-- Fixtures: two gyms, staff, members, products, plans, memberships, proof media.
insert into public.organizations(id,name,gym_code,status) values(pg_temp.sid(1),'PAY A','PAY79A','active'),(pg_temp.sid(2),'PAY B','PAY79B','active');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.sid(11),pg_temp.sid(1),'A',true),(pg_temp.sid(12),pg_temp.sid(2),'B',true);
insert into auth.users(id) select pg_temp.sid(n) from generate_series(901,910)n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
(pg_temp.sid(21),pg_temp.sid(1),pg_temp.sid(901),pg_temp.sid(11),'gym_owner','Owner'),(pg_temp.sid(22),pg_temp.sid(1),pg_temp.sid(902),pg_temp.sid(11),'gym_manager','Manager'),(pg_temp.sid(23),pg_temp.sid(1),pg_temp.sid(903),pg_temp.sid(11),'front_desk','Desk'),(pg_temp.sid(24),pg_temp.sid(1),pg_temp.sid(904),pg_temp.sid(11),'trainer','Trainer'),(pg_temp.sid(25),pg_temp.sid(2),pg_temp.sid(905),pg_temp.sid(12),'gym_owner','Other owner');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,date_of_birth,status) values
(pg_temp.sid(31),pg_temp.sid(1),pg_temp.sid(906),pg_temp.sid(11),'Member A','+917910000031','1990-01-01','active'),
(pg_temp.sid(32),pg_temp.sid(1),pg_temp.sid(907),pg_temp.sid(11),'Member A2','+917910000032','1990-01-01','active'),
(pg_temp.sid(33),pg_temp.sid(2),pg_temp.sid(908),pg_temp.sid(12),'Member B','+917910000033','1990-01-01','active'),
(pg_temp.sid(34),pg_temp.sid(1),pg_temp.sid(909),pg_temp.sid(11),'Member Blocked','+917910000034','1990-01-01','blocked'),
(pg_temp.sid(35),pg_temp.sid(1),pg_temp.sid(910),pg_temp.sid(11),'Member Retired Plan','+917910000035','1990-01-01','active');
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,gst_rate_bp,validity_days,stock_quantity,session_count,cancellation_terms,is_active,trainer_staff_id,trainer_qualification) values
(pg_temp.sid(101),pg_temp.sid(1),'product','Whey','Disclosed',250000,'INR',1800,7,10,null,'Desk collection',true,null,null),
(pg_temp.sid(102),pg_temp.sid(1),'product','Last unit','Disclosed',10000,'INR',1800,7,1,null,'Desk collection',true,null,null),
(pg_temp.sid(103),pg_temp.sid(1),'product','Hidden','Disclosed',10000,'INR',1800,7,5,null,'Desk collection',false,null,null),
(pg_temp.sid(104),pg_temp.sid(1),'product','Free item','Disclosed',0,'INR',1800,7,5,null,'Desk collection',true,null,null),
(pg_temp.sid(105),pg_temp.sid(1),'pt_package','PT pack of ten','Disclosed',500000,'INR',1800,30,null,10,'Desk collection',true,pg_temp.sid(24),'Certified coach'),
(pg_temp.sid(108),pg_temp.sid(2),'product','Foreign product','Disclosed',10000,'INR',1800,7,2,null,'Desk collection',true,null,null);
create temp table quotes as select id,quote_version from public.addon_products where tenant_id in(pg_temp.sid(1),pg_temp.sid(2));
grant select on quotes to authenticated,service_role;
insert into public.plans(id,tenant_id,name,duration_days,price_paise,gst_rate_bp,is_active) values
(pg_temp.sid(121),pg_temp.sid(1),'Monthly',30,100000,1800,true),(pg_temp.sid(122),pg_temp.sid(1),'Retired',30,100000,1800,false),(pg_temp.sid(123),pg_temp.sid(2),'Monthly',30,100000,1800,true);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,price_paise,discount_paise,currency,duration_days,starts_on,ends_on,periods_granted,activated_at) values
(pg_temp.sid(131),pg_temp.sid(1),pg_temp.sid(31),pg_temp.sid(121),'active',100000,10000,'INR',30,current_date-10,current_date+20,0,now()),
(pg_temp.sid(132),pg_temp.sid(1),pg_temp.sid(32),pg_temp.sid(121),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now()),
(pg_temp.sid(133),pg_temp.sid(2),pg_temp.sid(33),pg_temp.sid(123),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now()),
(pg_temp.sid(134),pg_temp.sid(1),pg_temp.sid(35),pg_temp.sid(122),'active',100000,0,'INR',30,current_date-5,current_date+25,0,now());
insert into mem_before select id,ends_on from public.memberships where id in(pg_temp.sid(131),pg_temp.sid(132));
-- Proof media: confirmed rows carry a member creator and the immutable
-- registration link AT INSERT TIME (the verification trigger forbids any
-- post-creation mutation); 143 stays unconfirmed and unlinked (refusal-only).
-- 141/144/145/146 are created per-scenario below, once their request exists.
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,created_by_member_id) values
(pg_temp.sid(143),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(143,'payment_proof'),pg_temp.sid(31));
-- A verified non-proof asset through the ordinary registrar and credential-only finalizer.
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
insert into assets(label,id) values('product-photo',public.register_media_asset('product',pg_temp.stage(142),'image/jpeg',1000));
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select id from assets where label='product-photo'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'product','image/jpeg',1000,pg_temp.stage(142),'source-142',pg_temp.pub(142),'published-142'),true,'MED-002 fixture product photo verified through the ordinary finalizer');
set local role postgres;

-- BUY-001 actor matrix: canonical claims validated before any target lookup.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.accept_purchase_request(pg_temp.sid(999),pg_temp.sid(998),pg_temp.sid(997))$q$) like '42501%',true,'BUY-001 member cannot invoke the staff accept command');
select is(pg_temp.refusal($q$select public.reject_purchase_request(pg_temp.sid(999),pg_temp.sid(998),'Not permitted',pg_temp.sid(997))$q$) like '42501%',true,'BUY-001 actor precedes target lookup on the staff reject command');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(900),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like '42501%',true,'BUY-001 staff cannot invoke the member create command');
set local role postgres;
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is(pg_temp.refusal($q$select public.accept_purchase_request(pg_temp.sid(999),pg_temp.sid(998),pg_temp.sid(997))$q$) like '42501%',true,'BUY-001 trainer has no front-office accept authority');
set local role postgres;
select pg_temp.claim('member',1,null,31,906,jsonb_build_object('impersonation_session_id',pg_temp.sid(999)));
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(900),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like '42501%',true,'BUY-001 impersonation cannot create requests');
set local role postgres;
select pg_temp.claim('member',1,21,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(900),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like '42501%',true,'BUY-001 contradictory staff and member claims refused');
set local role postgres;
select pg_temp.claim('member',1,null,31,907);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(900),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like '42501%',true,'BUY-001 member claim bound to its own Auth subject');
set local role postgres;
select pg_temp.claim('member',1,null,34,909);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(900),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like '42501%',true,'BUY-001 blocked member refused before any target lookup');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(null,'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$),'22023','BUY-002 null request key refused as shape after actor');

-- BUY-002/003/018 member creates: typed intent, disclosed snapshot, scope and caps.
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),2,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-002 shop request created under its request key');
select pg_temp.cap('K1',501);
select is(pg_temp.rq('K1')->>'status','requested','BUY-002 new request starts requested');
select ok((pg_temp.rq('K1')->'snapshot') ?| array['pricePaise','unitPricePaise','totalPaise'] and pg_temp.rq('K1')->'snapshot'->>'currency'='INR','BUY-002 disclosed server snapshot carries price and explicit currency');
select is(pg_temp.replayed($q$select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),2,(select quote_version from quotes where id=pg_temp.sid(101)))$q$),'true','BUY-016 identical create replay returns the original result');
select is(pg_temp.nkey(501),1,'BUY-016 replay created no second request');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(501),'shop',pg_temp.sid(101),3,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) like 'GL068%',true,'BUY-016 changed facts under the same key conflict');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(502),'shop',pg_temp.sid(108),1,(select quote_version from quotes where id=pg_temp.sid(108)))$q$),'GL086:item_unavailable','BUY-003 cross-tenant offer not purchasable');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(503),'shop',pg_temp.sid(103),1,(select quote_version from quotes where id=pg_temp.sid(103)))$q$),'GL086:item_unavailable','BUY-003 inactive offer not purchasable');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(504),'shop',pg_temp.sid(104),1,(select quote_version from quotes where id=pg_temp.sid(104)))$q$) <> 'NO ERROR',true,'BUY-003 complimentary offers stay on the desk path');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(505),'shop',pg_temp.sid(101),11,(select quote_version from quotes where id=pg_temp.sid(101)))$q$),'GL086:invalid_quantity','BUY-018 quantity above the SHP maximum refused');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(506),'pt',pg_temp.sid(105),2,(select quote_version from quotes where id=pg_temp.sid(105)))$q$),'GL086:invalid_quantity','BUY-002 PT quantity is exactly one');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(507),'pt',pg_temp.sid(105),1,(select quote_version from quotes where id=pg_temp.sid(105)))$q$,'BUY-003 PT programme request accepted for create');
select pg_temp.cap('KPT',507);
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(508),'renewal',pg_temp.sid(133),1,null)$q$) like 'P0002%',true,'BUY-003 foreign membership is not a renewal target');
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(510),'renewal',pg_temp.sid(132),1,null)$q$) like 'P0002%',true,'BUY-003 another member of the same gym is not a renewal target');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(511),'shop',pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)))$q$,'BUY-018 open request three of five (last unit, first contender)');
select pg_temp.cap('KA',511);
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(512),'shop',pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)))$q$,'BUY-018 open request four of five (last unit, second contender)');
select pg_temp.cap('KB',512);
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(513),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 open request five of five');
select pg_temp.cap('K4',513);
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(515),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$) <> 'NO ERROR',true,'BUY-018 sixth open request refused');
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='K4'),pg_temp.sid(601))$q$,'BUY-018 cancelling opens capacity again');
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(514),'shop',pg_temp.sid(101),1,(select quote_version from quotes where id=pg_temp.sid(101)))$q$,'BUY-018 capacity regained after the cancellation');
select pg_temp.cap('K5',514);
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(509),'renewal',pg_temp.sid(134),1,null)$q$) <> 'NO ERROR',true,'BUY-003 membership on an inactive plan routes to the desk');
set local role postgres;

-- BUY-004 acceptance: front-office only, rechecks, hard hold, disclosed expiry.
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(602))$q$,'BUY-004 desk accepts the shop request');
select is(pg_temp.rq('K1')->>'status','owner_accepted','BUY-004 accepted state recorded');
select ok(pg_temp.rev('K1') is not null and (pg_temp.rq('K1')->>'accepted_at') is not null,'BUY-004 accepted revision and time persisted');
select ok((pg_temp.rq('K1')->>'expires_at')::timestamptz = (pg_temp.rq('K1')->>'accepted_at')::timestamptz + interval '24 hours','BUY-018 acceptance TTL is twenty-four hours from acceptance');
select is(pg_temp.audits('purchase_request.accepted','K1'),1,'BUY-020 acceptance audited atomically');
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KA'),(select quote_version from quotes where id=pg_temp.sid(102)),pg_temp.sid(603))$q$,'BUY-004 first acceptance of the last unit wins');
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='KB'),(select quote_version from quotes where id=pg_temp.sid(102)),pg_temp.sid(604))$q$) like 'GL123%',true,'BUY-004/GL123 second acceptance of the last unit loses to the hard hold');
select is(pg_temp.replayed($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(602))$q$),'true','BUY-016 accept replay returns the original result read-only');
select is(pg_temp.audits('purchase_request.accepted','K1'),1,'BUY-020 accept replay appended no second audit');
set local role postgres;
select pg_temp.claim('gym_owner',2,25,null,905);
set local role authenticated;
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='K1'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(605))$q$) like 'P0002%',true,'BUY-019 foreign request invisible to another tenant');
set local role postgres;
select pg_temp.claim('gym_manager',1,22,null,902);
set local role authenticated;
select lives_ok($q$update public.addon_products set price_paise=300000 where id=pg_temp.sid(101)$q$,'BUY-004 manager reprices the offer');
select isnt((select quote_version from public.addon_products where id=pg_temp.sid(101)),(select quote_version from quotes where id=pg_temp.sid(101)),'BUY-004 the reprice rotated the disclosed quote');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.accept_purchase_request((select id from req where label='K5'),(select quote_version from quotes where id=pg_temp.sid(101)),pg_temp.sid(606))$q$),'GL086:quote_changed','BUY-004 stale quote refused after a price change');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.reconfirm_purchase_quote((select id from req where label='K5'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(607))$q$,'BUY-004 member reconfirms the revised quote');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='K5'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(608))$q$,'BUY-004 acceptance after explicit member reconfirmation');

-- BUY-006 member cancellation and the hard hold against every other consumer.
select is(pg_temp.refusal($q$select public.record_addon_sale(pg_temp.sid(31),pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)),null,null,null,'cash','Counter sale over the hold',pg_temp.sid(640))$q$) like 'GL123%',true,'BUY-004/GL123 counter sale cannot consume accepted PAY stock');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_shop_reservation(pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)))$q$) like 'GL123%',true,'BUY-004/GL123 SHP member reservation cannot consume accepted PAY stock');
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='KA'),pg_temp.sid(609))$q$,'BUY-006 member cancels an accepted request');
select is(pg_temp.rq('KA')->>'status','cancelled','BUY-006 cancelled state recorded');
select is(pg_temp.replayed($q$select public.cancel_purchase_request((select id from req where label='KA'),pg_temp.sid(609))$q$),'true','BUY-016 cancel replay resolves read-only');
select is(pg_temp.audits('purchase_request.cancelled','KA'),1,'BUY-020 cancel replay appended no second audit');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.record_addon_sale(pg_temp.sid(31),pg_temp.sid(102),1,(select quote_version from quotes where id=pg_temp.sid(102)),null,null,null,'cash','Counter sale after hold release',pg_temp.sid(610))$q$,'BUY-006 hard hold released on cancellation');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KA'),pg_temp.rev('KA'),pg_temp.sid(611),'10000','INR','cash',null,null,null)$q$) <> 'NO ERROR',true,'BUY-006 cancelled request never activates a purchase');
set local role postgres;
select pg_temp.claim('gym_owner',1,21,null,901);
set local role authenticated;
select is(pg_temp.refusal($q$update public.addon_products set stock_quantity=2 where id=pg_temp.sid(101)$q$) like 'GL123%',true,'BUY-004/GL123 inventory adjustment cannot consume accepted PAY stock');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.refusal($q$select public.cancel_purchase_request((select id from req where label='K5'),pg_temp.sid(612))$q$) like 'P0002%',true,'BUY-006 only the owning member cancels');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.cancel_purchase_request((select id from req where label='K5'),pg_temp.sid(613))$q$) <> 'NO ERROR',true,'BUY-006 cancellation needs member ownership, not staff role');
set local role postgres;

-- BUY-008/010/011 proof attach, replacement and reasoned rejection on a fresh request.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(516),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-018 open request five of five after the cancellations');
select pg_temp.cap('K6',516);
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,object_key,verified_source_etag,published_etag,confirmed_at,created_by_member_id,linked_request_id) values
(pg_temp.sid(144),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(144,'payment_proof'),pg_temp.pub(144,'payment_proof'),'source-144','published-144',now(),pg_temp.sid(31),(select id from public.purchase_requests where request_key = pg_temp.sid(516))),
(pg_temp.sid(145),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(145,'payment_proof'),pg_temp.pub(145,'payment_proof'),'source-145','published-145',now(),pg_temp.sid(31),(select id from public.purchase_requests where request_key = pg_temp.sid(516)));
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='K6'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(614))$q$,'BUY-004 desk accepts the proof-flow request at the current quote');
set local role postgres;
insert into exp_before select 'K6',(pg_temp.rq('K6')->>'expires_at')::timestamptz;
insert into money_before select (select count(*) from public.payments),(select count(*) from public.addon_orders);
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='KB'),pg_temp.sid(144),pg_temp.rev('KB'),pg_temp.sid(615))$q$) <> 'NO ERROR',true,'BUY-008 proof attach requires the accepted live request');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(147),pg_temp.rev('K6'),pg_temp.sid(616))$q$) <> 'NO ERROR',true,'BUY-008 unknown asset refused without existence detail');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),(select id from assets where label='product-photo'),pg_temp.rev('K6'),pg_temp.sid(617))$q$) <> 'NO ERROR',true,'BUY-008 verified non-proof media kind refused');
select lives_ok($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(144),pg_temp.rev('K6'),pg_temp.sid(618))$q$,'BUY-008 verified proof attached to the accepted request');
select is(pg_temp.rq('K6')->>'status','payment_proof_uploaded','BUY-005 upload state recorded');
select is(pg_temp.nproof('K6','active'),1,'BUY-010 exactly one active proof');
select lives_ok($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(145),pg_temp.rev('K6'),pg_temp.sid(619))$q$,'BUY-010 member replaces the proof before verification');
select is(pg_temp.pj(144)->>'disposition','superseded','BUY-010 superseded proof is immutable history');
select is(pg_temp.aproof('K6'),pg_temp.sid(145),'BUY-010 replacement is the single active proof');
select is(pg_temp.rq('K6')->>'status','payment_proof_uploaded','BUY-005 replacement retains proof-uploaded');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(144),pg_temp.rev('K6'),pg_temp.sid(620))$q$) like 'GL124%',true,'BUY-010/GL124 superseded proof cannot regain active status');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),pg_temp.rev('K6'),'Photo unclear',pg_temp.sid(621))$q$,'BUY-011 desk rejects the proof with a member-visible reason');
select is(pg_temp.rq('K6')->>'status','owner_accepted','BUY-011 proof rejection returns the request to accepted');
select is(pg_temp.pj(145)->>'disposition','rejected','BUY-011 rejected proof retained as decision history');
select is((pg_temp.rq('K6')->>'expires_at')::timestamptz,(select expires_at from exp_before where label='K6'),'BUY-011 rejection retains the original acceptance expiry');
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),pg_temp.rev('K6'),'ab',pg_temp.sid(622))$q$),'22023','BUY-011 reason below three characters refused');
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),pg_temp.rev('K6'),repeat('x',201),pg_temp.sid(623))$q$),'22023','BUY-011 reason above two hundred characters refused');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.reject_payment_proof((select id from req where label='K6'),pg_temp.sid(145),pg_temp.rev('K6'),'Member says no',pg_temp.sid(624))$q$) like '42501%',true,'BUY-011 only the desk rejects proofs');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='K6'),pg_temp.sid(143),pg_temp.rev('K6'),pg_temp.sid(625))$q$) <> 'NO ERROR',true,'BUY-008 unconfirmed media cannot become an active proof');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='K6'),pg_temp.rev('K6'),pg_temp.sid(660),'300000','INR','cash',null,pg_temp.sid(144),pg_temp.rev('K6'))$q$) <> 'NO ERROR',true,'BUY-010/012 recording refuses a verifier context bound to the superseded proof');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='K6'),pg_temp.rev('K6'),pg_temp.sid(661),'300000','INR','cash',null,pg_temp.sid(145),pg_temp.sid(999))$q$) <> 'NO ERROR',true,'BUY-012 recording refuses a viewed revision that is not the current request revision');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='K6'),pg_temp.rev('K6'),pg_temp.sid(662),'300000','INR','cash',null,null,pg_temp.rev('K6'))$q$) <> 'NO ERROR',true,'BUY-012 proof-backed recording refuses a null viewed asset while an active proof exists');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.reject_purchase_request((select id from req where label='K6'),pg_temp.rev('K6'),'Wrong item requested',pg_temp.sid(626))$q$,'BUY-011 desk rejects the accepted request with a reason');
select is(pg_temp.rq('K6')->>'status','rejected','BUY-005 request rejection is terminal');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='K6'),pg_temp.rev('K6'),pg_temp.sid(627),'300000','INR','cash',null,pg_temp.sid(145),pg_temp.rev('K6'))$q$) <> 'NO ERROR',true,'BUY-005 rejected request cannot be recorded');
set local role postgres;
select is((select count(*) from public.payments)=(select p from money_before) and (select count(*) from public.addon_orders)=(select o from money_before),true,'BUY-008 upload and rejection created no money rows');

-- BUY-012/013 exact-price recording through the unchanged ledger.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(521),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-012 exact-price shop request created');
select pg_temp.cap('KR1',521);
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,object_key,verified_source_etag,published_etag,confirmed_at,created_by_member_id,linked_request_id) values
(pg_temp.sid(146),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(146,'payment_proof'),pg_temp.pub(146,'payment_proof'),'source-146','published-146',now(),pg_temp.sid(31),(select id from public.purchase_requests where request_key = pg_temp.sid(521)));
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KR1'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(628))$q$,'BUY-012 exact-price request accepted');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KR1'),pg_temp.sid(146),pg_temp.rev('KR1'),pg_temp.sid(629))$q$,'BUY-012 proof attached before recording');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.record_purchase_request((select id from req where label='KR1'),pg_temp.rev('KR1'),pg_temp.sid(630),(select price_paise::text from public.addon_products where id=pg_temp.sid(101)),'INR','cash',null,(select aproof('KR1')),pg_temp.rev('KR1'))$q$,'BUY-012 exact-price recording succeeds');
set local role postgres;
select is(pg_temp.rq('KR1')->>'status','recorded','BUY-005 recorded state is terminal');
select ok((pg_temp.rq('KR1')->>'recorded_payment_id') is not null and (pg_temp.rq('KR1')->>'recorded_order_id') is not null,'BUY-015 request bound to its payment and order');
select is(pg_temp.pj(146)->>'disposition','bound','BUY-010/015 proof causally bound to the recorded payment');
select ok((select p.amount_paise=300000 and p.currency='INR' and p.method='cash' and p.status='paid' and p.recorded_by_staff_id=pg_temp.sid(23) and p.member_id=pg_temp.sid(31) from public.payments p where p.id=(pg_temp.rq('KR1')->>'recorded_payment_id')::uuid),'BUY-012 actual amount, method, currency and desk actor recorded');
select is((select count(*)::integer from public.addon_orders where id=(pg_temp.rq('KR1')->>'recorded_order_id')::uuid),1,'BUY-013 existing ledger order created once');
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),9,'BUY-012 recording consumed the hold as an ordinary sale');
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.replayed($q$select public.record_purchase_request((select id from req where label='KR1'),pg_temp.rev('KR1'),pg_temp.sid(630),(select price_paise::text from public.addon_products where id=pg_temp.sid(101)),'INR','cash',null,(select aproof('KR1')),pg_temp.rev('KR1'))$q$),'true','BUY-016 recording replay returns the original result read-only');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KR1'),pg_temp.rev('KR1'),pg_temp.sid(630),'200000','INR','cash')$q$) like 'GL068%',true,'BUY-016 changed amount under the same command key conflicts');
set local role postgres;
select is((select count(*)::integer from public.addon_orders where id=(pg_temp.rq('KR1')->>'recorded_order_id')::uuid),1,'BUY-016 replay created no second order');
select is(pg_temp.audits('purchase_request.recorded','KR1'),1,'BUY-020 replay appended no second audit');

-- BUY-014 mismatched funds recorded honestly without entitlement.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(522),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-014 mismatch scenario request created');
select pg_temp.cap('KR2',522);
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,object_key,verified_source_etag,published_etag,confirmed_at,created_by_member_id,linked_request_id) values
(pg_temp.sid(141),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(141,'payment_proof'),pg_temp.pub(141,'payment_proof'),'source-141','published-141',now(),pg_temp.sid(31),(select id from public.purchase_requests where request_key = pg_temp.sid(522)));
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KR2'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(631))$q$,'BUY-014 mismatch scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KR2'),pg_temp.sid(141),pg_temp.rev('KR2'),pg_temp.sid(632))$q$,'BUY-014 mismatch scenario proof attached');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.record_purchase_request((select id from req where label='KR2'),pg_temp.rev('KR2'),pg_temp.sid(633),'200000','INR','upi',null,(select aproof('KR2')),pg_temp.rev('KR2'))$q$,'BUY-014 mismatched funds recorded as received');
set local role postgres;
select is(pg_temp.rq('KR2')->>'status','mismatch_recorded','BUY-005/014 mismatch closes the request terminally');
select ok((select p.amount_paise=200000 and p.currency='INR' and p.method='upi' and p.status='paid' and p.membership_id is null from public.payments p where p.id=(pg_temp.rq('KR2')->>'recorded_payment_id')::uuid),'BUY-014 actual amount recorded with no entitlement');
select is(pg_temp.pj(141)->>'disposition','bound','BUY-014 mismatch binds the exact viewed proof once');
select is(pg_temp.rq('KR2')->>'recorded_order_id',null,'BUY-014 mismatch created no order');
select is((select stock_quantity from public.addon_products where id=pg_temp.sid(101)),9,'BUY-014 mismatch released the hold without a sale');
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.replayed($q$select public.record_purchase_request((select id from req where label='KR2'),pg_temp.rev('KR2'),pg_temp.sid(633),'200000','INR','upi',null,(select aproof('KR2')),pg_temp.rev('KR2'))$q$),'true','BUY-016 mismatch replay resolves read-only');
set local role postgres;

-- BUY-012/014 renewal at the recorded sold terms with cumulative-period truth.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(523),'renewal',pg_temp.sid(131),1,null)$q$,'BUY-003 renewal of the held membership created');
select pg_temp.cap('KRN',523);
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(524),'renewal',pg_temp.sid(132),1,null)$q$,'BUY-014 partial renewal scenario created');
select pg_temp.cap('KRP',524);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KRN'),null,pg_temp.sid(634))$q$,'BUY-004 renewal accepted');
select ok((pg_temp.rq('KRN')->'snapshot') ? 'membershipId' and (pg_temp.rq('KRN')->'snapshot') ? 'netPricePaise','renewal revision token pins the held membership and sold terms');
select lives_ok($q$select public.record_purchase_request((select id from req where label='KRN'),pg_temp.rev('KRN'),pg_temp.sid(635),'90000','INR','cash',null,null,null)$q$,'BUY-012 renewal recorded at the sold net price');
set local role postgres;
select is(pg_temp.rq('KRN')->>'status','recorded','BUY-005 renewal recorded');
select ok((select p.membership_id=pg_temp.sid(131) and p.amount_paise=90000 from public.payments p where p.id=(pg_temp.rq('KRN')->>'recorded_payment_id')::uuid),'BUY-012 renewal payment attached to the held membership at sold terms');
select ok((select m.periods_granted=1 and m.ends_on>(select b.ends_on from mem_before b where b.id=pg_temp.sid(131)) from public.memberships m where m.id=pg_temp.sid(131)),'BUY-012 full sold-price renewal grants exactly one recorded period through the existing ledger');
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KRP'),null,pg_temp.sid(636))$q$,'BUY-014 partial renewal accepted');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(637),'50000','USD','cash',null,null,null)$q$) <> 'NO ERROR',true,'BUY-014 unsupported collection currency refused, not converted');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(638),'50000','INR','upi',null,null,null)$q$) <> 'NO ERROR',true,'BUY-012 non-cash recording without any proof refused');
select is(pg_temp.rq('KRP')->>'status','owner_accepted','BUY-014 refused recordings changed nothing');
select lives_ok($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(639),'50000','INR','cash',null,null,null)$q$,'BUY-014 partial renewal money recorded honestly as confirmed cash');
set local role postgres;
select ok((select p.amount_paise=50000 and p.membership_id=pg_temp.sid(132) from public.payments p where p.id=(pg_temp.rq('KRP')->>'recorded_payment_id')::uuid),'BUY-014 partial payment attached to the held membership');
select ok((select m.periods_granted=0 and m.ends_on=(select b.ends_on from mem_before b where b.id=pg_temp.sid(132)) from public.memberships m where m.id=pg_temp.sid(132)),'BUY-014 partial money grants no period and promises none');
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.replayed($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(639),'50000','INR','cash',null,null,null)$q$),'true','BUY-016 renewal recording replay returns the original result');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(639),'60000','INR','cash')$q$) like 'GL068%',true,'BUY-016 renewal command key binds its exact facts');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KRP'),pg_temp.rev('KRP'),pg_temp.sid(640),'50000','INR','cash',null,null,null)$q$) <> 'NO ERROR',true,'BUY-005 a recorded renewal cannot be recorded again under a new key');
set local role postgres;

-- BUY-018 the daily creation cap is one total per member: ten creations already stand.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.create_purchase_request(pg_temp.sid(541),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$) <> 'NO ERROR',true,'BUY-018 eleventh creation in a rolling day refused with open capacity free');
set local role postgres;

-- Trusted-writer bounds and the service boundary.
set local role service_role;
-- BUY-012 p_initial_slot (owner-approved serial amendment): exact-price PT
-- recording validates the slot server-side through the existing PTF locks and
-- never strands the request unbound.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(530),'pt',pg_temp.sid(105),1,(select quote_version from public.addon_products where id=pg_temp.sid(105)))$q$,'BUY-003 the PT recording scenario request is created');
select pg_temp.cap('KPT',530);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KPT'),(select quote_version from public.addon_products where id=pg_temp.sid(105)),pg_temp.sid(652))$q$,'BUY-004 the PT recording scenario is accepted');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KPT'),pg_temp.rev('KPT'),pg_temp.sid(653),(select price_paise::text from public.addon_products where id=pg_temp.sid(105)),'INR','cash',null,null,null)$q$) <> 'NO ERROR',true,'BUY-012 exact-price PT recording without a valid initial slot refuses');
select is(pg_temp.refusal($q$select public.record_purchase_request((select id from req where label='KPT'),pg_temp.rev('KPT'),pg_temp.sid(654),(select price_paise::text from public.addon_products where id=pg_temp.sid(105)),'INR','cash',jsonb_build_object('trainerStaffId',pg_temp.sid(24),'slotId',pg_temp.sid(999)),null,null)$q$) <> 'NO ERROR',true,'BUY-012 a fabricated slot is never client-trusted: PT recording validates it server-side');
set local role postgres;
select is(pg_temp.refusal('select public.record_purchase_request(null,null,null,null,null,null,null,null,null)') like '42501%',true,'BUY-019 service_role holds no application-command EXECUTE');
set local role postgres;

-- BUY-019 safe reads: scoping, projection, pagination.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(100,null,null) r),10,'BUY-019 member reads exactly own request history');
select is((select count(*)::integer from public.read_member_purchase_requests(100,null,null) r, jsonb_array_elements(r->'requests') e where e::text like '%objectKey%' or e::text like '%object_key%' or e::text ilike '%etag%' or e::text like '%url%'),0,'BUY-009 read models carry no keys, ETags or URLs');
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(2,null,null) r),2,'BUY-018 list clamps to the requested page');
select is((select r->>'nextAfter' is not null from public.read_member_purchase_requests(2,null,null) r),true,'BUY-019 keyset cursor returned for the next page');
set local role postgres;
select pg_temp.claim('member',2,null,33,908);
set local role authenticated;
select is((select jsonb_array_length(r->'requests') from public.read_member_purchase_requests(100,null,null) r),0,'BUY-019 another tenant member reads nothing');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is((select jsonb_array_length(r->'requests') from public.read_purchase_requests(100,null,null) r),11,'BUY-019 front office reads its own tenant queue');
select is(pg_temp.refusal('select public.read_purchase_request(pg_temp.sid(999))') like 'P0002%',true,'BUY-009 unknown request shares the same external refusal');
set local role postgres;
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is(pg_temp.refusal('select public.read_purchase_requests(null,null,null)') like '42501%',true,'BUY-001 trainers have no purchase queue access');
set local role postgres;

-- BUY-008 member-created payment_proof finalization through the credential-only
-- finalizer: member actor, payment_proof kind, private namespace, and the
-- registration-time request linkage (finalization proves the registered request
-- live and accepted; a replacement tombstones only the unconfirmed loser).
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(525),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-008 proof-finalization scenario request created');
select pg_temp.cap('KF1',525);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF1'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(641))$q$,'BUY-008 proof-finalization scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('M1','KF1')$q$,'BUY-008 member registers a staging proof for the live accepted request');
select is(pg_temp.mst('M1')->>'kind','payment_proof','BUY-008 registration records the payment_proof kind with a member creator');
select is(pg_temp.mst('M1')->>'object_key',null,'BUY-008 registration starts unconfirmed and unpublished');
select ok(pg_temp.mst('M1')->>'staging_object_key' like pg_temp.sid(1)::text||'/staging/payment_proof/%.jpg','BUY-008 server chooses the tenant-leading private staging key');
select is(pg_temp.refusal($q$select public.register_payment_proof(pg_temp.sid(999),'image/jpeg',1000)$q$) like 'P0002%',true,'BUY-009 unknown and foreign requests share one external registration refusal');
select is(pg_temp.refusal($q$select public.register_payment_proof(null,null,null)$q$),'22023','BUY-008 registration arguments required');
select is(pg_temp.refusal($q$select public.register_payment_proof((select id from req where label='KF1'),'image/gif',1000)$q$),'22023','BUY-008 unsupported proof mime refused');
select is(pg_temp.refusal($q$select public.register_payment_proof((select id from req where label='KF1'),'image/jpeg',2097153)$q$),'22023','BUY-008 oversized proof registration refused');
select is(pg_temp.refusal($q$select public.register_payment_proof((select id from req where label='KF1'),'image/jpeg',0)$q$),'22023','BUY-008 empty proof registration refused');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select asset from regs where label='M1'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M1'),'source-M1',pg_temp.pub(151,'payment_proof'),'published-M1'),true,'BUY-008 member-created proof finalizes into the private payment_proof namespace');
select is(pg_temp.mst('M1')->>'object_key',pg_temp.pub(151,'payment_proof'),'BUY-008 finalization stores the fresh private published key');
select ok(pg_temp.mst('M1')->>'confirmed_at' is not null and pg_temp.mst('M1')->>'verified_source_etag'='source-M1' and pg_temp.mst('M1')->>'published_etag'='published-M1','BUY-008 finalization records the verified source and published ETags');
select is(public.finalize_media_asset((select asset from regs where label='M1'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M1'),'source-M1',pg_temp.pub(151,'payment_proof'),'published-M1'),false,'BUY-010/016 finalization replay resolves read-only with exactly one confirmation');
select is(pg_temp.aaudits('media_asset.confirmed','M1'),1,'BUY-020 finalization replay appended no second audit');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('M3','KF1')$q$,'BUY-008 a further staging registration for the same request');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(906),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'payment_proof'),'published-M3')$q$) like '42501%',true,'BUY-008/009 finalization requires the asset''s registered member creator');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(901),pg_temp.sid(21),'gym_owner',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'payment_proof'),'published-M3')$q$) like '42501%',true,'BUY-008 staff actor cannot finalize a member-created proof');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'product','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'product'),'published-M3')$q$),'22023','BUY-008 finalization kind and namespace must match the registered payment_proof kind');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(907),null,'member',pg_temp.sid(2),'payment_proof','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'payment_proof'),'published-M3')$q$) like '42501%',true,'BUY-019 foreign tenant sees no proof asset at finalization');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'product'),'published-M3')$q$),'22023','BUY-008 published key must stay in the private payment_proof namespace');
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/png',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(152,'payment_proof'),'published-M3')$q$),'22023','BUY-008 finalization metadata must match registration exactly');
select is(pg_temp.mst('M3')->>'object_key',null,'BUY-008 refused finalizations never publish');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(526),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-008 creator-isolation scenario request created');
select pg_temp.cap('KF2',526);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF2'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(642))$q$,'BUY-008 creator-isolation scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('R32','KF2')$q$,'BUY-008 the isolation scenario member registers its own staging proof');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset(pg_temp.sid(143),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(143,'payment_proof'),'source-143',pg_temp.pub(153,'payment_proof'),'published-153')$q$) like '42501%',true,'BUY-008 finalization requires the asset''s registered creator even with a live accepted request of one''s own');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(527),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-010 supersession scenario request created');
select pg_temp.cap('KF3',527);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF3'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(643))$q$,'BUY-010 supersession scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('S1','KF3')$q$,'BUY-010 first candidate registered');
select lives_ok($q$select pg_temp.reg('S2','KF3')$q$,'BUY-010 replacement candidate registered for the same request');
select ok(pg_temp.mst('S1')->>'deleted_at' is not null,'BUY-010 the superseded candidate is tombstoned, never an uncertain deletion');
select ok(pg_temp.mst('S2')->>'deleted_at' is null,'BUY-010 the winning candidate stays live');
select is(pg_temp.mst('S1')->>'object_key',null,'BUY-010 the superseded candidate was never published');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='S1'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='S1'),'source-S1',pg_temp.pub(154,'payment_proof'),'published-S1')$q$),'GL086:media_not_ready','BUY-010 a tombstoned candidate can never finalize');
select is(public.finalize_media_asset((select asset from regs where label='S2'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='S2'),'source-S2',pg_temp.pub(155,'payment_proof'),'published-S2'),true,'BUY-010 the winning candidate finalizes');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select is(pg_temp.regn('KF3',4),4,'BUY-018 further proof registrations fill the member rolling hour');
select lives_ok($q$select pg_temp.reg('S3','KF3')$q$,'BUY-018 the tenth proof registration in the rolling hour succeeds');
select is(pg_temp.refusal($q$select pg_temp.reg('S9','KF3')$q$) like '22023:purchase_cap%',true,'BUY-018 the eleventh proof registration in the rolling hour refuses with the stable 22023 purchase_cap marker (no GL126 exists)');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(528),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-010 confirmed-winner scenario request created');
select pg_temp.cap('KF4',528);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF4'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(644))$q$,'BUY-010 confirmed-winner scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('W1','KF4')$q$,'BUY-010 the confirmed-winner scenario registers its proof');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select asset from regs where label='W1'),pg_temp.sid(910),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='W1'),'source-W1',pg_temp.pub(156,'payment_proof'),'published-W1'),true,'BUY-010 the confirmed-winner scenario finalizes');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KF4'),(select asset from regs where label='W1'),pg_temp.rev('KF4'),pg_temp.sid(645))$q$,'BUY-010 the confirmed winner attaches');
select lives_ok($q$select pg_temp.reg('W2','KF4')$q$,'BUY-010 a fresh registration on a proof-uploaded request is allowed');
select ok(pg_temp.mst('W1')->>'deleted_at' is null and pg_temp.mst('W1')->>'object_key' = pg_temp.pub(156,'payment_proof'),'BUY-010 a fresh registration never disturbs the confirmed attached winner');
-- BUY-010/003 exact registration-to-request linkage enforced at attachment: a confirmed asset registered for KF4 can never attach to another request, first attach included.
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select asset from regs where label='W2'),pg_temp.sid(910),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='W2'),'source-W2',pg_temp.pub(158,'payment_proof'),'published-W2'),true,'BUY-010 the second confirmed-winner candidate finalizes for its own request');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(531),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-003 the same member opens a second accepted request');
select pg_temp.cap('KFA',531);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KFA'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(648))$q$,'BUY-003 the second request is accepted');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='KFA'),(select asset from regs where label='W2'),pg_temp.rev('KFA'),pg_temp.sid(649))$q$) <> 'NO ERROR',true,'BUY-010 an asset registered for KF4 can never attach to another live request (first attach included)');
select lives_ok($q$select public.attach_payment_proof((select id from req where label='KF4'),(select asset from regs where label='W2'),pg_temp.rev('KF4'),pg_temp.sid(650))$q$,'BUY-010 the same confirmed asset still attaches to its own registered request');
select is(pg_temp.refusal($q$select public.attach_payment_proof((select id from req where label='KFA'),(select asset from regs where label='W2'),pg_temp.sid(999),pg_temp.sid(651))$q$) <> 'NO ERROR',true,'BUY-008/016 attach validates the expected revision server-side');
-- BUY-016/018 keyed registration replay: one logical upload keeps one command UUID.
select lives_ok($q$insert into regs(label,asset,skey) select 'RK1',(r->>'assetId')::uuid,r->>'stagingObjectKey' from (select public.register_payment_proof((select id from req where label='KF4'),'image/jpeg',1000,pg_temp.sid(680)) as r) v$q$,'BUY-016 the keyed registration creates the logical upload once');
select lives_ok($q$insert into regs(label,asset,skey) select 'RK2',(r->>'assetId')::uuid,r->>'stagingObjectKey' from (select public.register_payment_proof((select id from req where label='KF4'),'image/jpeg',1000,pg_temp.sid(680)) as r) v$q$,'BUY-016 the same keyed registration replays read-only');
select is((select asset from regs where label='RK1'),(select asset from regs where label='RK2'),'BUY-016 replay returns the same registered asset without a second candidate');
select is((select skey from regs where label='RK1'),(select skey from regs where label='RK2'),'BUY-016 replay returns the same staging facts without a new deadline');
select is(pg_temp.refusal($q$select public.register_payment_proof((select id from req where label='KF4'),'image/jpeg',2000,pg_temp.sid(680))$q$) <> 'NO ERROR',true,'BUY-016 changed facts under the same registration key conflict');
set local role postgres;
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='KF1'),pg_temp.sid(646))$q$,'BUY-008 the registered request is cancelled after staging');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='M3'),pg_temp.sid(907),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='M3'),'source-M3',pg_temp.pub(157,'payment_proof'),'published-M3')$q$) like 'GL066%',true,'BUY-008 finalization proves the registered request still live and accepted');
set local role postgres;

-- BUY-009 active-only proof viewing (frozen decision 1, 2026-10-04): only the
-- currently ACTIVE proof of a live request is viewable, by the owning member or
-- the real same-tenant front-office verifier; recorded/mismatch/bound history
-- is safe metadata only and refuses for everyone.
select pg_temp.claim('member',1,null,32,907);
set local role authenticated;
select lives_ok($q$insert into urls(label,payload) values ('KF3U',public.read_purchase_proof_url((select id from req where label='KF3')))$q$,'BUY-009 the owning member obtains the private proof URL for the live request''s active proof');
select is((select (payload->>'requestId')::uuid from urls where label='KF3U'),(select id from req where label='KF3'),'BUY-009 the proof URL names its own request');
select is((select payload->>'url' from urls where label='KF3U'),'/api/purchase-requests/'||(select id from req where label='KF3')::text||'/proof-asset','BUY-009 the proof URL is the application proof-asset path only');
select ok((select (payload->>'expiresAt')::timestamptz from urls where label='KF3U') is not null and (select (payload->>'expiresAt')::timestamptz from urls where label='KF3U') <= now() + interval '60 seconds','BUY-018 the issued proof URL is bounded to sixty seconds');
select is((select payload ?& array['requestId','proofId','assetId','expiresAt','url'] and not (payload ?| array['stagingObjectKey','objectKey','etag','publishedEtag','proofKey','object_key']) from urls where label='KF3U'),true,'BUY-009 the proof URL payload carries exactly the five safe keys and no storage metadata');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$insert into urls(label,payload) values ('KF3V',public.read_purchase_proof_url((select id from req where label='KF3')))$q$,'BUY-009 the same-tenant front-office verifier obtains the active proof URL');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KF3'))$q$) like 'P0002%',true,'BUY-009 another member shares the one external proof-URL refusal');
set local role postgres;

-- BUY-009 active-only: after recording, the bound proof is history and the URL
-- refuses for the owner member and the verifier alike (reverses the earlier
-- bound-viewing allowance; no owner amendment permits it). — the owning member and the same-tenant
-- front-office verifier may still view the bound proof (≤60s, no storage
-- metadata); trainer, foreign and platform-preview actors keep the one
-- external refusal; a request closed without binding keeps the refusal.
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KR1'))$q$) like 'P0002%',true,'BUY-009 the owning member cannot view a recorded request bound proof: history is metadata only');
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KR1'))$q$) like 'P0002%',true,'BUY-009 the verifier cannot view a recorded request bound proof either');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KR2'))$q$) like 'P0002%',true,'BUY-009 a mismatch_recorded request bound proof refuses for everyone');
set local role postgres;
select pg_temp.claim('trainer',1,24,null,904);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KR1'))$q$) like 'P0002%',true,'BUY-009 a trainer shares the one external proof-URL refusal');
set local role postgres;
select pg_temp.claim('member',1,null,31,906,jsonb_build_object('impersonation_session_id',pg_temp.sid(999)));
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KR1'))$q$) like 'P0002%',true,'BUY-009 platform preview shares the one external proof-URL refusal');
set local role postgres;
select pg_temp.claim('member',1,null,31,906);
set local role authenticated;
select is(pg_temp.refusal($q$select public.read_purchase_proof_url(pg_temp.sid(999))$q$) like 'P0002%',true,'BUY-009 unknown requests share the one external proof-URL refusal');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.cancel_purchase_request((select id from req where label='KF4'),pg_temp.sid(647))$q$,'BUY-009 the proof-uploaded scenario request is closed without recording');
select is(pg_temp.refusal($q$select public.read_purchase_proof_url((select id from req where label='KF4'))$q$) like 'P0002%',true,'BUY-009 closure without binding keeps the external refusal');
set local role postgres;

-- BUY-001 the finalizer's member path re-proves the live member row exactly as
-- the staff path re-proves the staff row: status and binding at finalize time.
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(529),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-001 member-status scenario request created');
select pg_temp.cap('KF5',529);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF5'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(648))$q$,'BUY-001 member-status scenario accepted');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('W3','KF5')$q$,'BUY-001 the member-status scenario registers its staging proof');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select public.create_purchase_request(pg_temp.sid(530),'shop',pg_temp.sid(101),1,(select quote_version from public.addon_products where id=pg_temp.sid(101)))$q$,'BUY-001 member-status control request created');
select pg_temp.cap('KF6',530);
set local role postgres;
select pg_temp.claim('front_desk',1,23,null,903);
set local role authenticated;
select lives_ok($q$select public.accept_purchase_request((select id from req where label='KF6'),(select quote_version from public.addon_products where id=pg_temp.sid(101)),pg_temp.sid(649))$q$,'BUY-001 member-status control accepted');
set local role postgres;
select pg_temp.claim('member',1,null,35,910);
set local role authenticated;
select lives_ok($q$select pg_temp.reg('W4','KF6')$q$,'BUY-001 the control scenario registers its staging proof');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(public.finalize_media_asset((select asset from regs where label='W4'),pg_temp.sid(910),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='W4'),'source-W4',pg_temp.pub(159,'payment_proof'),'published-W4'),true,'BUY-001 the active member creator finalizes (status control)');
set local role postgres;
update public.members set status='cancelled' where id=pg_temp.sid(35);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset((select asset from regs where label='W3'),pg_temp.sid(910),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,(select skey from regs where label='W3'),'source-W3',pg_temp.pub(158,'payment_proof'),'published-W3')$q$) like '42501%',true,'BUY-001 a cancelled member creator cannot finalize');
set local role postgres;
insert into public.media_assets(id,tenant_id,kind,mime,bytes,staging_object_key,created_by_member_id) values(pg_temp.sid(148),pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(148,'payment_proof'),pg_temp.sid(34));
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset(pg_temp.sid(148),pg_temp.sid(909),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(148,'payment_proof'),'source-148',pg_temp.pub(160,'payment_proof'),'published-160')$q$) like '42501%',true,'BUY-001 a blocked member creator cannot finalize');
set local role postgres;
update public.members set erased_at=now() where id=pg_temp.sid(31);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(pg_temp.refusal($q$select public.finalize_media_asset(pg_temp.sid(143),pg_temp.sid(906),null,'member',pg_temp.sid(1),'payment_proof','image/jpeg',1000,pg_temp.stage(143,'payment_proof'),'source-143',pg_temp.pub(161,'payment_proof'),'published-161')$q$) like '42501%',true,'BUY-001 an erased member creator cannot finalize');
set local role postgres;

-- BUY-020 audit hygiene across the whole flow.
select ok(not exists(select 1 from public.audit_log a where (a.action like 'purchase_request.%' or a.action like 'payment_proof.%') and (coalesce(a."before"::text,'')||coalesce(a."after"::text,'')||coalesce(a.reason,'')) ~* '(staging/|published/|etag|https?:|object_key)'),'BUY-020 no proof object keys, ETags or URLs in audit payloads');
select ok(pg_temp.audits('purchase_request.created','K1')=1 and exists(select 1 from public.audit_log where action='purchase_request.created' and record_id=(select id from req where label='K1') and actor_user_id=pg_temp.sid(906)),'BUY-020 creation audited once with the member actor');
select ok(exists(select 1 from public.audit_log where action='purchase_request.accepted' and record_id=(select id from req where label='K1') and actor_user_id=pg_temp.sid(903)),'BUY-020 acceptance audited with the desk actor');

select * from finish();
rollback;
