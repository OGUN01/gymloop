-- Independent author: frozen ADR-111/116 add-on contract and EARS only.
-- No add-on implementation or visible add-on tests were read. Prior holdouts
-- supply harness conventions, not expected business behavior.
-- Every fixture, fault injector and assertion is rolled back. Concurrent races
-- require separate coordinator connections; this suite observes the contracted
-- advisory locks and deterministic replay/budget effects without publishing data.
begin;
set local role postgres;
select plan(176);

create function pg_temp.h26_id(bucket integer, n integer) returns uuid
language sql immutable strict as $$
  select ('260000ff-0026-4000-8000-' || bucket::text || lpad(n::text,11,'0'))::uuid
$$;
create function pg_temp.h26_exec(statement text) returns jsonb language plpgsql as $$
declare result jsonb; detail text;
begin
  execute statement;
  return jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail=pg_exception_detail;
  return jsonb_build_object('state',sqlstate,'detail',detail);
end
$$;
create function pg_temp.h26_call(statement text) returns jsonb language plpgsql as $$
declare result jsonb; detail text;
begin
  execute 'select to_jsonb(r) from ('||statement||') r' into strict result;
  return result||jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail=pg_exception_detail;
  return jsonb_build_object('state',sqlstate,'detail',detail);
end
$$;
create function pg_temp.h26_claim(role_name text default 'gym_owner',
  tenant integer default 1, staff integer default 1, member integer default null)
returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
    'role','authenticated','sub',pg_temp.h26_id(9,coalesce(staff,member,1)),
    'app_role',role_name,'tenant_id',pg_temp.h26_id(1,tenant),
    'staff_id',pg_temp.h26_id(3,staff),'member_id',pg_temp.h26_id(5,member)))::text,true)
$$;
create temp table h26_seen(name text primary key, value jsonb);
grant all on h26_seen to public;
create function pg_temp.h26_sale(product integer, nonce integer, delta jsonb default '{}')
returns jsonb language plpgsql as $$
declare args jsonb; result jsonb; detail text;
begin
  select value into args from h26_seen where name='offer-'||product;
  args:=jsonb_build_object('memberId',pg_temp.h26_id(5,1),
    'productId',pg_temp.h26_id(4,product),'quantity',1,
    'quoteVersion',args->>'quote_version','trainerStaffId',null,
    'initialStartsAt',null,'initialEndsAt',null,'method','cash','reason',null)||delta;
  execute 'select to_jsonb(r) from public.record_addon_sale($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) r'
  into strict result using (args->>'memberId')::uuid,(args->>'productId')::uuid,
    (args->>'quantity')::integer,(args->>'quoteVersion')::uuid,
    (args->>'trainerStaffId')::uuid,(args->>'initialStartsAt')::timestamptz,
    (args->>'initialEndsAt')::timestamptz,(args->>'method')::public.payment_method,
    args->>'reason',pg_temp.h26_id(8,nonce);
  return result||jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail=pg_exception_detail;
  return jsonb_build_object('state',sqlstate,'detail',detail);
end
$$;
create function pg_temp.h26_observation(tenant integer default 1) returns jsonb
language sql as $$
  select jsonb_build_object(
    'orders',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.addon_orders r where tenant_id=pg_temp.h26_id(1,tenant)),
    'payments',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.payments r where tenant_id=pg_temp.h26_id(1,tenant)),
    'sessions',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.pt_sessions r where tenant_id=pg_temp.h26_id(1,tenant)),
    'receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.financial_year),'[]') from public.document_counters r where tenant_id=pg_temp.h26_id(1,tenant)),
    'stock',(select coalesce(jsonb_agg(jsonb_build_array(id,stock_quantity) order by id),'[]') from public.addon_products r where tenant_id=pg_temp.h26_id(1,tenant)),
    'audit',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.audit_log r where tenant_id=pg_temp.h26_id(1,tenant)))
$$;
create function pg_temp.h26_bad_member(delta jsonb) returns text language plpgsql as $$
declare prior text:=current_setting('request.jwt.claims'); result text;
begin
  perform set_config('request.jwt.claims',(prior::jsonb||delta)::text,true);
  result:=pg_temp.h26_call('select public.read_member_addon_returns(null) as value')->>'state';
  perform set_config('request.jwt.claims',prior,true);
  return result;
end
$$;
grant execute on all functions in schema pg_temp to public;

-- Metadata fixes privilege and historic-null boundaries without reading bodies.
select has_column('public','addon_products','quote_version','H26 database-owned quote exists');
select col_not_null('public','addon_products','quote_version','H26 every current offer has a quote');
select col_type_is('public','addon_products','quote_version','uuid','H26 quote is a UUID');
select col_is_null('public','addon_orders',column_name,'H26 historical '||column_name||' may be unknown')
from unnest(array['sold_by_staff_id','idempotency_key','sold_at','sale_snapshot','sale_request','initial_session_id']) column_name;
select col_hasnt_default('public','addon_orders',column_name,'H26 no invented historic '||column_name)
from unnest(array['sold_by_staff_id','idempotency_key','sold_at','sale_snapshot','sale_request','initial_session_id']) column_name;
select ok(coalesce((select not p.prosecdef and p.provolatile='v' and 'search_path=""'=any(p.proconfig)
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p where p.oid=to_regprocedure(signature)),false),
  'H26 invoker mutation boundary: '||signature)
from unnest(array[
  'public.record_addon_sale(uuid,uuid,integer,uuid,uuid,timestamp with time zone,timestamp with time zone,public.payment_method,text,uuid)',
  'public.schedule_pt_session(uuid,uuid,timestamp with time zone,timestamp with time zone,text)',
  'public.finish_pt_session(uuid,public.pt_session_status)',
  'public.complete_addon_order(uuid)',
  'public.complete_manual_addon_refund(uuid,bigint,text,text)']) signature;
select ok(coalesce((select p.prosecdef and p.provolatile='s'
  and pg_get_userbyid(p.proowner)='postgres' and 'search_path=""'=any(p.proconfig)
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p where p.oid=to_regprocedure('public.read_member_addon_returns(uuid)')),false),
  'H26 bounded member projection is stable, postgres-owned and nonpublic');
select ok(exists(select 1 from pg_index i where i.indexrelid=to_regclass('public.'||index_name)
  and i.indisunique and pg_get_indexdef(i.indexrelid,1,true)='tenant_id'
  and pg_get_indexdef(i.indexrelid,2,true)=column_name
  and pg_get_expr(i.indpred,i.indrelid)='('||column_name||' IS NOT NULL)'),
  'H26 unique tenant-scoped '||column_name)
from (values('addon_orders_tenant_id_idempotency_key_key','idempotency_key'),
  ('addon_orders_tenant_id_payment_id_key','payment_id')) required(index_name,column_name);
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.addon_orders'::regclass
  and c.conname='addon_orders_tenant_id_'||column_name||'_fkey'
  and c.contype='f' and c.confrelid=to_regclass('public.'||parent)
  and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.conrelid and attname=column_name)]
  and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.confrelid and attname='id')]),
  'H26 tenant-composite '||column_name||' reference')
from (values('sold_by_staff_id','staff'),('initial_session_id','pt_sessions')) required(column_name,parent);

insert into public.organizations(id,name,gym_code,timezone,currency,status) values
  (pg_temp.h26_id(1,1),'H26 Gym A','H26GYA','Asia/Kolkata','INR','active'),
  (pg_temp.h26_id(1,2),'H26 Gym B','H26GYB','Pacific/Kiritimati','INR','active');
insert into public.branches(id,tenant_id,name,is_default)
select pg_temp.h26_id(2,n),pg_temp.h26_id(1,n),'Main',true from generate_series(1,2) n;
insert into public.staff(id,tenant_id,branch_id,role,full_name) values
  (pg_temp.h26_id(3,1),pg_temp.h26_id(1,1),pg_temp.h26_id(2,1),'gym_owner','H26 Owner'),
  (pg_temp.h26_id(3,2),pg_temp.h26_id(1,1),pg_temp.h26_id(2,1),'gym_manager','H26 Manager'),
  (pg_temp.h26_id(3,3),pg_temp.h26_id(1,1),pg_temp.h26_id(2,1),'front_desk','H26 Desk'),
  (pg_temp.h26_id(3,4),pg_temp.h26_id(1,1),pg_temp.h26_id(2,1),'trainer','H26 Trainer'),
  (pg_temp.h26_id(3,5),pg_temp.h26_id(1,1),pg_temp.h26_id(2,1),'trainer','H26 Other Trainer'),
  (pg_temp.h26_id(3,6),pg_temp.h26_id(1,2),pg_temp.h26_id(2,2),'gym_owner','H26 Owner B');
insert into public.members(id,tenant_id,branch_id,full_name,phone)
select pg_temp.h26_id(5,n),pg_temp.h26_id(1,case when n=3 then 2 else 1 end),
  pg_temp.h26_id(2,case when n=3 then 2 else 1 end),'H26 Member '||n,
  '+91926000000'||n from generate_series(1,3) n;
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,
  validity_days,cancellation_terms,trainer_staff_id,trainer_qualification,session_count,stock_quantity)
select pg_temp.h26_id(4,n),pg_temp.h26_id(1,1),kind::public.addon_kind,'H26 Offer '||n,
  'Full disclosed service '||n,price,'INR',31,'Return reviewed at desk',
  case when kind='pt_package' then pg_temp.h26_id(3,4) end,
  case when kind='pt_package' then 'Gym-stated qualification; not platform verified' end,
  case when kind='pt_package' then 2 end,case when kind='product' then 8 end
from (values(1,'product',9007199254740993::bigint),(2,'product',0::bigint),
  (3,'diet_plan',107::bigint),(4,'diet_plan',0::bigint),(5,'pt_package',601::bigint),
  (6,'pt_package',0::bigint),(7,'product',9223372036854775807::bigint)) offers(n,kind,price);
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,
  validity_days,cancellation_terms,stock_quantity)
values(pg_temp.h26_id(4,8),pg_temp.h26_id(1,2),'product','H26 Foreign offer','Full disclosure',109,
  1,'Desk return policy',2);
insert into h26_seen select 'offer-'||n,to_jsonb(p) from generate_series(1,8) n
join public.addon_products p on p.id=pg_temp.h26_id(4,n);
insert into h26_seen values('pt-input',jsonb_build_object('trainerStaffId',pg_temp.h26_id(3,4),
  'initialStartsAt',transaction_timestamp()+interval '1 day',
  'initialEndsAt',transaction_timestamp()+interval '1 day 1 hour'));

-- Quote ownership, stock-only stability, and full exact money at acceptance.
select pg_temp.h26_claim();
set local role authenticated;
update public.addon_products set quote_version=pg_temp.h26_id(8,999),stock_quantity=7,sort_order=17
where id=pg_temp.h26_id(4,1);
select is((select quote_version::text from public.addon_products where id=pg_temp.h26_id(4,1)),
  (select value->>'quote_version' from h26_seen where name='offer-1'),
  'H26 quote spoof plus stock/presentation edit preserves the database version');
insert into h26_seen values('sale-product',pg_temp.h26_sale(1,1,'{"quantity":2,"reason":"  आकार  A  "}'));
select is((select value->>'state' from h26_seen where name='sale-product'),'00000','H26 positive product accepted');
select is((select value->>'replayed' from h26_seen where name='sale-product'),'false','H26 first sale is not replay');
select is((select jsonb_build_array(status,total_paise::text,unit_price_paise::text,quantity,sold_by_staff_id,
  payment_id is not null,initial_session_id,sessions_used,sessions_total,sold_at=transaction_timestamp(),
  starts_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date,expires_on=starts_on+30)
  from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')),
  jsonb_build_array('completed','18014398509481986','9007199254740993',2,pg_temp.h26_id(3,1),
    true,null,0,null,true,true,true),'H26 exact amount, actor, product fulfilment and inclusive acceptance dates');
select is((select stock_quantity from public.addon_products where id=pg_temp.h26_id(4,1)),5,
  'H26 product quantity is deducted once');
select is((select jsonb_build_array(p.amount_paise::text,p.currency,p.method,p.status,p.membership_id,
  p.recorded_by_staff_id,p.notes,p.idempotency_key,p.receipt_number is not null,p.paid_at is not null,
  p.coupon_id,p.mandate_id,p.provider,p.provider_order_id,p.provider_payment_id)
  from public.payments p where id=(select (value->>'payment_id')::uuid from h26_seen where name='sale-product')),
  jsonb_build_array('18014398509481986','INR','cash','paid',null,pg_temp.h26_id(3,1),'आकार  A',
    'addon-sale:'||pg_temp.h26_id(8,1),true,true,null,null,null,null,null),
  'H26 paid sale is one attributed ordinary receipt with no membership/provider/coupon facts');
select is((select sale_snapshot from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')),
  jsonb_build_object('kind','product','name','H26 Offer 1','description','Full disclosed service 1',
    'cancellationTerms','Return reviewed at desk','validityDays',31,'trainerQualification',null),
  'H26 frozen disclosure has the exact public contract keys');
select is((select sale_request from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')),
  jsonb_build_object('memberId',pg_temp.h26_id(5,1),'productId',pg_temp.h26_id(4,1),'quantity',2,
    'quoteVersion',(select value->>'quote_version' from h26_seen where name='offer-1'),
    'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method','cash','reason','आकार  A'),
  'H26 request evidence is exact, null-explicit, Unicode preserving and outer-trimmed');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory'
  and granted and objsubid=1 and ((classid::bigint<<32)|objid::bigint)=
    hashtextextended('addon-sale:'||pg_temp.h26_id(1,1)||':'||pg_temp.h26_id(8,1),0)),
  'H26 accepted sale holds the specified transaction request-key lock');
insert into h26_seen values('after-product',pg_temp.h26_observation());
select is(pg_temp.h26_sale(1,1,'{"quantity":2,"reason":"आकार  A"}'),
  (select value||'{"replayed":true}' from h26_seen where name='sale-product'),'H26 normalized exact retry returns the first ids');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='after-product'),
  'H26 exact sale replay touches no order/payment/receipt/stock/session/audit');
select is(pg_temp.h26_sale(1,1,'{"quantity":2,"reason":"आकार  A"}'::jsonb||mutation)->>'state','GL052',
  'H26 changed original request fact conflicts: '||label)
from (values('member',jsonb_build_object('memberId',pg_temp.h26_id(5,2))),
  ('product',jsonb_build_object('productId',pg_temp.h26_id(4,2))),('quantity','{"quantity":3}'::jsonb),
  ('quote',jsonb_build_object('quoteVersion',pg_temp.h26_id(8,500))),
  ('trainer',jsonb_build_object('trainerStaffId',pg_temp.h26_id(3,4))),
  ('start',jsonb_build_object('initialStartsAt',transaction_timestamp())),
  ('end',jsonb_build_object('initialEndsAt',transaction_timestamp()+interval '1 hour')),
  ('method','{"method":"upi"}'::jsonb),('reason case','{"reason":"आकार  a"}'::jsonb),
  ('reason internal spacing','{"reason":"आकार A"}'::jsonb)) changes(label,mutation);
select pg_temp.h26_claim('gym_manager',1,2);
select is(pg_temp.h26_sale(1,1,'{"quantity":2,"reason":"आकार  A"}')->>'state','GL052',
  'H26 another authorized seller cannot replay someone else''s request key');
select pg_temp.h26_claim();
update public.addon_products set price_paise=11,description='Changed after the accepted sale',is_active=false
where id=pg_temp.h26_id(4,1);
select isnt((select quote_version::text from public.addon_products where id=pg_temp.h26_id(4,1)),
  (select value->>'quote_version' from h26_seen where name='offer-1'),'H26 material terms rotate the quote');
insert into h26_seen values('after-edit',pg_temp.h26_observation());
select is(pg_temp.h26_sale(1,1,'{"quantity":2,"reason":"आकार  A"}'),
  (select value||'{"replayed":true}' from h26_seen where name='sale-product'),
  'H26 replay resolves the original sale before current deactivation/repricing');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='after-edit'),
  'H26 replay after offer change remains inert');

-- Free and paid service kinds, reason/method contradictions and checked overflow.
insert into h26_seen values('free-product',pg_temp.h26_sale(2,2,'{"method":null,"reason":"  Welcome  gift  "}')),
  ('paid-diet',pg_temp.h26_sale(3,3)),
  ('free-diet',pg_temp.h26_sale(4,4,'{"method":null,"reason":"Included"}')),
  ('paid-pt',pg_temp.h26_sale(5,5,(select value from h26_seen where name='pt-input'))),
  ('free-pt',pg_temp.h26_sale(6,6,(select value||jsonb_build_object('method',null,'reason','Included',
    'initialStartsAt',transaction_timestamp()+interval '2 days',
    'initialEndsAt',transaction_timestamp()+interval '2 days 1 hour') from h26_seen where name='pt-input')));
select is(value->>'state','00000','H26 accepts '||name) from h26_seen where name in
  ('free-product','paid-diet','free-diet','paid-pt','free-pt');
select is((select jsonb_build_array(payment_id,total_paise::text,sold_at=transaction_timestamp(),
  sold_by_staff_id is not null,idempotency_key is not null,status,sale_request->>'reason')
  from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='free-product')),
  jsonb_build_array(null,'0',true,true,true,'completed','Welcome  gift'),'H26 complimentary sale is attributed with frozen reason and no payment');
select is((select count(*)::integer from public.payments where tenant_id=pg_temp.h26_id(1,1)),3,
  'H26 three positive sales create three payments; all three free kinds create none');
select is((select count(*)::integer from public.memberships where tenant_id=pg_temp.h26_id(1,1)),0,
  'H26 add-on payments create no membership entitlement');
select is((select count(*)::integer from public.pt_sessions s join public.addon_orders o
  on o.id=s.addon_order_id and o.tenant_id=s.tenant_id where o.id in
  (select (value->>'order_id')::uuid from h26_seen where name in ('paid-pt','free-pt'))
  and s.id=o.initial_session_id and s.status='scheduled' and s.member_id=o.member_id
  and s.trainer_staff_id=o.trainer_staff_id),2,'H26 each PT acceptance owns its exact initial reservation');
insert into h26_seen values('before-failures',pg_temp.h26_observation());
select isnt(pg_temp.h26_sale(7,71,'{"quantity":2}')->>'state','00000','H26 bigint multiplication overflow cannot create a sale');
select isnt(pg_temp.h26_sale(2,72,'{"method":null,"reason":"  "}')->>'state','00000','H26 blank complimentary reason is invalid');
select isnt(pg_temp.h26_sale(2,73,'{"method":"cash","reason":"Gift"}')->>'state','00000','H26 free sale cannot fabricate a manual payment method');
select isnt(pg_temp.h26_sale(3,74,'{"method":null}')->>'state','00000','H26 paid sale requires a payment method');
select is(pg_temp.h26_sale(3,75,'{"quantity":2}')->>'detail','invalid_quantity','H26 diet quantity is exactly one');
select is(pg_temp.h26_sale(5,76,(select value||'{"quantity":2}' from h26_seen where name='pt-input'))->>'detail',
  'invalid_quantity','H26 PT quantity is exactly one');
select is(pg_temp.h26_sale(2,77,'{"quantity":0,"method":null,"reason":"Gift"}')->>'detail',
  'invalid_quantity','H26 zero quantity cannot pass the free-money path');
select is(pg_temp.h26_sale(2,78,'{"quantity":99,"method":null,"reason":"Gift"}')->>'detail',
  'insufficient_stock','H26 stock refusal also covers free products');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='before-failures'),
  'H26 all refused money/quantity/stock paths roll back every observable effect');

-- Rejected first requests leave their keys reusable, and tenant keys are disjoint.
select is(pg_temp.h26_sale(2,78,'{"method":null,"reason":"Gift"}')->>'replayed','false',
  'H26 failed stock request consumes no key');
select pg_temp.h26_claim('gym_owner',2,6);
insert into h26_seen values('foreign-sale',pg_temp.h26_sale(8,1,jsonb_build_object('memberId',pg_temp.h26_id(5,3))));
select is((select value->>'replayed' from h26_seen where name='foreign-sale'),'false','H26 same sale key is independent in another gym');
select is((select count(*)::integer from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')),0,
  'H26 another gym cannot select the first sale');
select is(pg_temp.h26_sale(3,89)->>'state','P0002','H26 invisible member/offer is not found');
select pg_temp.h26_claim();
select is(pg_temp.h26_sale(8,90)->>'state','P0002','H26 foreign offer is not found');
select is(pg_temp.h26_sale(3,91,jsonb_build_object('memberId',pg_temp.h26_id(5,3)))->>'state','P0002',
  'H26 foreign member is not found');

-- The complete identities are checked before an existing or absent object.
select pg_temp.h26_claim('trainer',1,4);
select is(pg_temp.h26_sale(3,3)->>'state','42501','H26 trainer cannot recover a sale result by its key');
select is(pg_temp.h26_sale(3,999)->>'state','42501','H26 trainer new sale is refused before lookup');
select pg_temp.h26_claim('member',1,null,1);
select is(pg_temp.h26_sale(3,3)->>'state','42501','H26 member cannot record even its own sale');
select pg_temp.h26_claim();
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||
  jsonb_build_object('impersonation_session_id',pg_temp.h26_id(9,999)))::text,true);
select is(pg_temp.h26_sale(3,3)->>'state','42501','H26 preview with a fabricated staff claim cannot replay');
select pg_temp.h26_claim('front_desk',1,3);
select is(pg_temp.h26_sale(4,79,'{"method":null,"reason":"Desk gift"}')->>'state','00000',
  'H26 real front desk may record complimentary acceptance');

-- Full frozen records and project error precedence, exercised by a legal writer.
select pg_temp.h26_claim();
insert into h26_seen select 'frozen-product',to_jsonb(o) from public.addon_orders o
where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product');
select is(pg_temp.h26_exec(format('update public.addon_orders set %s where id=%L',assignment,
  (select value->>'order_id' from h26_seen where name='sale-product')))->>'state','GL053',
  'H26 accepted record freezes '||label)
from (values('identity','member_id='''||pg_temp.h26_id(5,2)||''''),
  ('seller','sold_by_staff_id='''||pg_temp.h26_id(3,2)||''''),
  ('request key','idempotency_key='''||pg_temp.h26_id(8,500)||''''),
  ('request JSON','sale_request=sale_request||''{"reason":"replacement"}''::jsonb'),
  ('snapshot extra key','sale_snapshot=sale_snapshot||''{"injected":"yes"}''::jsonb'),
  ('quantity','quantity=3'),('unit price','unit_price_paise=unit_price_paise+1'),
  ('total','total_paise=total_paise+1'),('currency','currency=''USD'''),
  ('payment','payment_id=null'),('sold instant','sold_at=sold_at+interval ''1 second'''),
  ('start date','starts_on=starts_on-1'),('expiry date','expires_on=expires_on+1'),
  ('trainer','trainer_staff_id='''||pg_temp.h26_id(3,4)||''''),
  ('sessions bought','sessions_total=7')) mutations(label,assignment);
select is(pg_temp.h26_exec(format('update public.addon_orders set quantity=3,status=''pending'' where id=%L',
  (select value->>'order_id' from h26_seen where name='sale-product')))->>'detail','order_is_a_record',
  'H26 immutable sale facts take precedence over an invalid order transition');
select is((select to_jsonb(o) from public.addon_orders o where id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')),
  (select value from h26_seen where name='frozen-product'),'H26 frozen-row attacks change no stored fact or timestamp');
select isnt(pg_temp.h26_exec(format('update public.addon_orders set sessions_used=1 where id=%L',
  (select value->>'order_id' from h26_seen where name='paid-pt')))->>'state','00000',
  'H26 staff cannot fabricate used PT sessions by direct parent update');
select is(pg_temp.h26_exec(format('update public.addon_products set kind=''diet_plan'',stock_quantity=null where id=%L',pg_temp.h26_id(4,1)))->>'state',
  'GL055','H26 referenced catalogue kind cannot reinterpret delivered history');

-- Session creation key, ownership, reservation release and lock namespace.
select pg_temp.h26_claim('trainer',1,4);
insert into h26_seen values('schedule-sql',to_jsonb(format(
  'select * from public.schedule_pt_session(%L,%L,%L,%L,%L)',
  (select value->>'order_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(6,1),
  transaction_timestamp()+interval '3 days',transaction_timestamp()+interval '3 days 1 hour','  Session  α  ')));
insert into h26_seen values('scheduled',pg_temp.h26_call((select value#>>'{}' from h26_seen where name='schedule-sql')));
select is((select value->>'state' from h26_seen where name='scheduled'),'00000','H26 assigned trainer books remaining purchased session');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory' and granted and objsubid=1
  and ((classid::bigint<<32)|objid::bigint)=hashtextextended('addon-order:'||pg_temp.h26_id(1,1)||':'||
    (select value->>'order_id' from h26_seen where name='paid-pt'),0)),
  'H26 session command holds the specified shared order lock');
select is(pg_temp.h26_call((select value#>>'{}' from h26_seen where name='schedule-sql')),
  (select value||'{"replayed":true}' from h26_seen where name='scheduled'),'H26 same session UUID and original input is replay');
select is(pg_temp.h26_call(format('select * from public.schedule_pt_session(%L,%L,%L,%L,%L)',
  (select value->>'order_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(6,1),
  transaction_timestamp()+interval '3 days',transaction_timestamp()+interval '3 days 1 hour','Session α'))->>'state',
  'GL052','H26 session key compares internal note whitespace');
select is(pg_temp.h26_call(format('select * from public.schedule_pt_session(%L,%L,%L,%L,null)',
  (select value->>'order_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(6,2),
  transaction_timestamp()+interval '4 days',transaction_timestamp()+interval '4 days 1 hour'))->>'detail',
  'session_budget_exhausted','H26 scheduled reservations count against bought sessions');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''completed'')',pg_temp.h26_id(6,1)))->>'detail',
  'session_not_ended','H26 future completion cannot consume a session');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''cancelled'')',pg_temp.h26_id(6,1)))->>'replayed',
  'false','H26 cancellation releases a reservation without usage');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''cancelled'')',pg_temp.h26_id(6,1)))->>'replayed',
  'true','H26 exact terminal status is a replay');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''no_show'')',pg_temp.h26_id(6,1)))->>'detail',
  'invalid_session_transition','H26 changed terminal command is refused');
select is(pg_temp.h26_call(format('select * from public.schedule_pt_session(%L,%L,%L,%L,null)',
  (select value->>'order_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(6,2),
  transaction_timestamp()+interval '4 days',transaction_timestamp()+interval '4 days 1 hour'))->>'state',
  '00000','H26 cancelled reservation permits a new session UUID');
select is((select sessions_used from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='paid-pt')),0,
  'H26 cancellation and booking do not invent consumption');
select pg_temp.h26_claim('trainer',1,5);
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''no_show'')',pg_temp.h26_id(6,2)))->>'detail',
  'trainer_not_yours','H26 different trainer cannot close another trainer''s booking');
select isnt(pg_temp.h26_exec(format('update public.pt_sessions set trainer_staff_id=%L where id=%L',
  pg_temp.h26_id(3,5),pg_temp.h26_id(6,2)))->>'state','00000','H26 OLD assignment prevents claiming another trainer''s row');
select pg_temp.h26_claim('trainer',1,4);
select isnt(pg_temp.h26_exec(format('update public.pt_sessions set trainer_staff_id=%L where id=%L',
  pg_temp.h26_id(3,5),pg_temp.h26_id(6,2)))->>'state','00000','H26 NEW assignment prevents handing away an immutable session');
select is(pg_temp.h26_exec(format('update public.pt_sessions set notes=''changed'',status=''scheduled'' where id=%L',
  pg_temp.h26_id(6,1)))->>'detail','session_is_a_record','H26 immutable session fact precedes invalid terminal transition');

-- Trusted historical entitlement fixtures permit deterministic ended-slot tests.
-- They do not fabricate missing disclosure, acceptance actor, date or request.
set local role postgres;
select set_config('request.jwt.claims','',true);
-- Model rows already present before this feature, including ended scheduled
-- appointments. Only this rollback fixture suppresses new-write triggers;
-- relational checks remain enabled and all tested actions use normal triggers.
alter table public.addon_orders disable trigger user;
alter table public.pt_sessions disable trigger user;
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,
  unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on)
select pg_temp.h26_id(7,n),pg_temp.h26_id(1,1),pg_temp.h26_id(5,1),pg_temp.h26_id(4,6),'active',
  1,0,0,'INR',pg_temp.h26_id(3,4),2,0,
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date-2,
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date+1
from generate_series(1,2) n;
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at)
select pg_temp.h26_id(6,20+n),pg_temp.h26_id(1,1),pg_temp.h26_id(7,1),pg_temp.h26_id(3,4),pg_temp.h26_id(5,1),
  transaction_timestamp()-n*interval '2 hours',transaction_timestamp()-n*interval '2 hours'+interval '1 hour'
from generate_series(1,2) n;
alter table public.pt_sessions enable trigger user;
alter table public.addon_orders enable trigger user;
select pg_temp.h26_claim('trainer',1,4);
set local role authenticated;
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''completed'')',pg_temp.h26_id(6,21)))->>'order_status',
  'active','H26 consuming first ended session preserves remaining entitlement');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''completed'')',pg_temp.h26_id(6,21)))->>'replayed',
  'true','H26 ended-session double completion is inert');
select is(pg_temp.h26_call(format('select * from public.finish_pt_session(%L,''completed'')',pg_temp.h26_id(6,22)))->>'order_status',
  'completed','H26 final consumed session completes the parent exactly once');
select is((select sessions_used from public.addon_orders where id=pg_temp.h26_id(7,1)),2,
  'H26 consumed usage is exactly the two completed session rows');
select is((select jsonb_build_array(sale_snapshot,sale_request,sold_at,sold_by_staff_id,idempotency_key,initial_session_id)
  from public.addon_orders where id=pg_temp.h26_id(7,1)),jsonb_build_array(null,null,null,null,null,null),
  'H26 historical delivery invents no sale disclosure, actor, date or key');

-- Diet completion is an independent natural command; PT is never hand-completed.
select pg_temp.h26_claim();
insert into h26_seen values('diet-done',pg_temp.h26_call(format('select * from public.complete_addon_order(%L)',
  (select value->>'order_id' from h26_seen where name='paid-diet'))));
select is((select value->>'order_status' from h26_seen where name='diet-done'),'completed','H26 explicit diet completion succeeds');
select is(pg_temp.h26_call(format('select * from public.complete_addon_order(%L)',
  (select value->>'order_id' from h26_seen where name='paid-diet'))),
  (select value||'{"replayed":true}' from h26_seen where name='diet-done'),'H26 diet completion natural identity is read-only replay');
select is(pg_temp.h26_call(format('select * from public.complete_addon_order(%L)',
  (select value->>'order_id' from h26_seen where name='paid-pt')))->>'detail','wrong_order_kind',
  'H26 general completion cannot grant PT usage');

-- Partial/full return handover, exact confirmation and recorded cash projection.
insert into h26_seen values('partial-refund',pg_temp.h26_call(format(
  'select * from public.record_refund(%L,200,''INR'',''refund'',''Personal explanation'',%L)',
  (select value->>'payment_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(8,200))));
select is((select value->>'state' from h26_seen where name='partial-refund'),'00000','H26 ordinary refund request targets the add-on payment');
select is(pg_temp.h26_call(format('select * from public.complete_manual_addon_refund(%L,201,''INR'',''Personal explanation'')',
  (select value->>'refund_id' from h26_seen where name='partial-refund')))->>'state','GL048',
  'H26 changed confirmation amount refuses returned-money recording');
insert into h26_seen values('partial-done',pg_temp.h26_call(format(
  'select * from public.complete_manual_addon_refund(%L,200,''INR'',''Personal explanation'')',
  (select value->>'refund_id' from h26_seen where name='partial-refund'))));
select is((select value->>'state' from h26_seen where name='partial-done'),'00000','H26 manual handover records the actual partial return');
select ok((select value->>'processed_at' is not null from h26_seen where name='partial-done'),'H26 new completion has a server time');
select is((select status::text from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='paid-pt')),
  'active','H26 partial return preserves active service entitlement');
insert into h26_seen values('before-refund-replay',pg_temp.h26_observation());
select is(pg_temp.h26_call(format('select * from public.complete_manual_addon_refund(%L,200,''INR'',''Personal explanation'')',
  (select value->>'refund_id' from h26_seen where name='partial-refund'))),
  (select value||'{"replayed":true}' from h26_seen where name='partial-done'),'H26 completed manual return replay preserves the original event time');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='before-refund-replay'),
  'H26 refund replay leaves parent/booking/audit facts unchanged');
select is(pg_temp.h26_exec(format('update public.refunds set processed_at=processed_at+interval ''1 second'' where id=%L',
  (select value->>'refund_id' from h26_seen where name='partial-refund')))->>'state','GL041','H26 returned event time is immutable');
insert into h26_seen values('full-refund',pg_temp.h26_call(format(
  'select * from public.record_refund(%L,401,''INR'',''reversal'',''Final return'',%L)',
  (select value->>'payment_id' from h26_seen where name='paid-pt'),pg_temp.h26_id(8,201))));
insert into h26_seen values('full-done',pg_temp.h26_call(format(
  'select * from public.complete_manual_addon_refund(%L,401,''INR'',''Final return'')',
  (select value->>'refund_id' from h26_seen where name='full-refund'))));
select is((select value->>'order_status' from h26_seen where name='full-done'),'refunded','H26 completed refund plus reversal exhausts purchased money');
select is((select count(*)::integer from public.pt_sessions where addon_order_id=(select (value->>'order_id')::uuid
  from h26_seen where name='paid-pt') and status='scheduled'),0,'H26 full return atomically cancels every remaining PT reservation');
select is((select amount_paise::text from public.payments where id=(select (value->>'payment_id')::uuid from h26_seen where name='paid-pt')),
  '601','H26 full returned money never erases the original receipt amount');
select is(pg_temp.h26_sale(5,5,(select value from h26_seen where name='pt-input')),
  (select value||'{"replayed":true}' from h26_seen where name='paid-pt'),'H26 original sale replay survives full return');
insert into h26_seen values('terminal-refund',pg_temp.h26_call(format(
  'select * from public.record_refund(%L,107,''INR'',''refund'',''Completed diet return'',%L)',
  (select value->>'payment_id' from h26_seen where name='paid-diet'),pg_temp.h26_id(8,202))));
select is(pg_temp.h26_call(format('select * from public.complete_manual_addon_refund(%L,107,''INR'',''Completed diet return'')',
  (select value->>'refund_id' from h26_seen where name='terminal-refund')))->>'order_status','completed',
  'H26 full return preserves an already completed fulfilment record');
insert into h26_seen values('product-refund',pg_temp.h26_call(format(
  'select * from public.record_refund(%L,9007199254740993,''INR'',''refund'',''Private desk explanation'',%L)',
  (select value->>'payment_id' from h26_seen where name='sale-product'),pg_temp.h26_id(8,203))));
select pg_temp.h26_claim('member',1,null,1);
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='sale-product')))->'value'->'returns','[]'::jsonb,
  'H26 a requested return is not disclosed as completed cash');
select pg_temp.h26_claim();
select is(pg_temp.h26_call(format('select * from public.complete_manual_addon_refund(%L,9007199254740993,''INR'',''Private desk explanation'')',
  (select value->>'refund_id' from h26_seen where name='product-refund')))->>'order_status','completed',
  'H26 product return preserves physical fulfilment history');
select is((select stock_quantity from public.addon_products where id=pg_temp.h26_id(4,1)),5,
  'H26 returned money is never an automatic physical stock return');

select pg_temp.h26_claim('member',1,null,1);
insert into h26_seen values('member-returns',pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='paid-pt'))));
select is((select value->>'state' from h26_seen where name='member-returns'),'00000','H26 complete own member identity can read recorded returns');
select is((select array_agg(k order by k) from h26_seen,
  lateral jsonb_object_keys(value->'value') k where name='member-returns'),array['orderId','returns'],
  'H26 projection contains only its exact envelope keys');
select is((select count(*)::integer from h26_seen,lateral jsonb_array_elements(value->'value'->'returns') r
  where name='member-returns' and (select array_agg(k order by k) from jsonb_object_keys(r) k)=
    array['amountPaise','currency','kind','processedAt','refundId'] and jsonb_typeof(r->'amountPaise')='string'),2,
  'H26 every visible return is minimized and exact decimal text');
select is((select array_agg(r->>'kind' order by r->>'kind') from h26_seen,
  lateral jsonb_array_elements(value->'value'->'returns') r where name='member-returns'),array['refund','reversal'],
  'H26 projection preserves both generated return kinds');
select is((select sum((r->>'amountPaise')::bigint)::text from h26_seen,
  lateral jsonb_array_elements(value->'value'->'returns') r where name='member-returns'),'601',
  'H26 member completed-return sum reconciles to the exact receipt');
select is((select count(*)::integer from public.refunds where payment_id=(select (value->>'payment_id')::uuid
  from h26_seen where name='paid-pt')),0,'H26 member direct refund reads stay denied');
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='free-product')))->'value'->'returns','[]'::jsonb,
  'H26 own complimentary order has an empty return array');
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='sale-product')))->'value'->'returns'->0->'amountPaise',
  '"9007199254740993"'::jsonb,'H26 member return amounts remain exact above JavaScript integer precision');
select is(pg_temp.h26_call('select public.read_member_addon_returns(null) as value')->>'state','22023',
  'H26 authorized member null argument is invalid');
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='foreign-sale')))->>'state','P0002',
  'H26 foreign tenant order gives the same not-found boundary');
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',pg_temp.h26_id(7,999)))->>'state','P0002',
  'H26 absent order gives the same not-found boundary');
select pg_temp.h26_claim('member',1,null,2);
select is(pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
  (select value->>'order_id' from h26_seen where name='paid-pt')))->>'state','P0002','H26 same-gym other member cannot read returns');
select pg_temp.h26_claim();
select is(pg_temp.h26_call('select public.read_member_addon_returns(null) as value')->>'state','42501',
  'H26 projection refuses staff before validating its argument');
select pg_temp.h26_claim('member',1,null,1);
select is(pg_temp.h26_bad_member(mutation),'42501','H26 projection rejects malformed/dual identity: '||label)
from (values('subject absent','{"sub":null}'::jsonb),('subject invalid','{"sub":"invalid"}'::jsonb),
  ('tenant absent','{"tenant_id":null}'::jsonb),('tenant invalid','{"tenant_id":"invalid"}'::jsonb),
  ('member absent','{"member_id":null}'::jsonb),('member invalid','{"member_id":"invalid"}'::jsonb),
  ('staff mixed',jsonb_build_object('staff_id',pg_temp.h26_id(3,1))),
  ('preview mixed',jsonb_build_object('impersonation_session_id',pg_temp.h26_id(9,99))),
  ('platform role','{"app_role":"super_admin"}'::jsonb),('unknown role','{"app_role":"invented"}'::jsonb)) identities(label,mutation);

-- Audit reconstruction: the accepted row and each prior event form one chain.
set local role postgres;
select set_config('request.jwt.claims','',true);
-- Corrupt historical linkage is isolated to a subtransaction. The definer must
-- independently re-check payment facts even though the order is the member's.
create function pg_temp.h26_inconsistent_payment() returns text language plpgsql as $$
declare observed text;
begin
  begin
    alter table public.payments disable trigger user;
    update public.payments set member_id=pg_temp.h26_id(5,2)
    where id=(select (value->>'payment_id')::uuid from h26_seen where name='sale-product');
    alter table public.payments enable trigger user;
    perform pg_temp.h26_claim('member',1,null,1);
    set local role authenticated;
    observed:=pg_temp.h26_call(format('select public.read_member_addon_returns(%L) as value',
      (select value->>'order_id' from h26_seen where name='sale-product')))->>'state';
    raise exception using errcode='H0026',message='rollback only this inconsistent fixture';
  exception when sqlstate 'H0026' then null;
  end;
  return observed;
end
$$;
select is(pg_temp.h26_inconsistent_payment(),'P0002',
  'H26 readable own order cannot launder another member''s linked payment');
select is((select count(*)::integer from public.audit_log where record_id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product')
  and action='addon_order.created'),1,'H26 every order has exactly one creation event');
select is((select jsonb_build_array(record_type,tenant_id,actor_user_id,actor_role,before,reason) from public.audit_log
  where record_id=(select (value->>'order_id')::uuid from h26_seen where name='sale-product') and action='addon_order.created'),
  jsonb_build_array('addon_order',pg_temp.h26_id(1,1),pg_temp.h26_id(9,1),'gym_owner',null,'आकार  A'),
  'H26 order creation audit names verified actor, original reason and null before');
select is((select count(*)::integer from public.audit_log a where a.record_type='addon_order' and a.tenant_id=pg_temp.h26_id(1,1)
  and (select array_agg(k order by k) from jsonb_object_keys(a.after) k) is distinct from
    (select array_agg(attname::text order by attname::text) from pg_attribute where attrelid='public.addon_orders'::regclass
      and attnum>0 and not attisdropped and attname not in ('id','tenant_id','created_at','updated_at'))),0,
  'H26 every order audit summary contains every domain column and no storage metadata');
select ok(exists(select 1 from public.audit_log a join public.addon_orders o on a.record_id=o.id
  where o.id=pg_temp.h26_id(7,1) and a.action='addon_order.updated' and a.after->>'sessions_used'='2'
    and a.after->>'status'='completed' and a.actor_user_id=pg_temp.h26_id(9,4)),
  'H26 private PT effects retain the real trainer audit actor');
select ok(exists(select 1 from public.audit_log a where a.record_id=(select (value->>'order_id')::uuid from h26_seen where name='free-product')
  and a.after->>'status'='completed' and a.reason='Welcome  gift'),
  'H26 complimentary acceptance and fulfilment are audited');

-- Inject failures at ordinary child boundaries; the sale itself gets no special
-- privilege to suppress a child error or classify a native failure as replay.
create function pg_temp.h26_fail_child() returns trigger language plpgsql as $$
begin
  if tg_table_name='audit_log' and to_jsonb(new)->>'reason'='H26 fail audit' then
    raise exception using errcode='P0026',message='holdout audit refused';
  elsif tg_table_name='payments' and to_jsonb(new)->>'notes'='H26 fail payment' then
    raise exception using errcode='P0027',message='holdout payment refused';
  end if;
  return new;
end
$$;
create trigger h26_fail_audit before insert on public.audit_log for each row execute function pg_temp.h26_fail_child();
create trigger h26_fail_payment after insert on public.payments for each row execute function pg_temp.h26_fail_child();
select pg_temp.h26_claim();
set local role authenticated;
select is(pg_temp.h26_exec(format(
  'insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,unit_price_paise,total_paise) values(%L,%L,%L,%L,107,107)',
  pg_temp.h26_id(7,300),pg_temp.h26_id(1,1),pg_temp.h26_id(5,1),pg_temp.h26_id(4,3)))->>'detail',
  'invalid_snapshot','H26 direct authenticated insertion cannot evade keyed request evidence');
insert into h26_seen values('before-unaccepted',pg_temp.h26_observation());
select is(pg_temp.h26_exec(format(
  'insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,unit_price_paise,total_paise,sold_by_staff_id,idempotency_key,sale_snapshot,sale_request) values(%L,%L,%L,%L,107,107,%L,%L,%L::jsonb,%L::jsonb); set constraints all immediate',
  pg_temp.h26_id(7,301),pg_temp.h26_id(1,1),pg_temp.h26_id(5,1),pg_temp.h26_id(4,3),pg_temp.h26_id(3,1),pg_temp.h26_id(8,601),
  (select sale_snapshot from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='paid-diet')),
  (select sale_request from public.addon_orders where id=(select (value->>'order_id')::uuid from h26_seen where name='paid-diet'))))->>'detail',
  'unaccepted_order','H26 complete but pending keyed sale cannot survive transaction end');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='before-unaccepted'),
  'H26 deferred refusal removes the pending order and its audit event');
insert into h26_seen values('before-child-fault',pg_temp.h26_observation());
select is(pg_temp.h26_sale(3,301,'{"reason":"H26 fail audit"}')->>'state','P0026','H26 audit failure aborts the entire sale');
select is(pg_temp.h26_sale(3,302,'{"reason":"H26 fail payment"}')->>'state','P0027','H26 payment child failure propagates unchanged');
select is(pg_temp.h26_sale(5,303,(select value||jsonb_build_object(
  'initialStartsAt',transaction_timestamp()+interval '2 days',
  'initialEndsAt',transaction_timestamp()+interval '2 days 1 hour') from h26_seen where name='pt-input'))->>'state','23P01',
  'H26 overlapping initial booking is a genuine exclusion failure');
select is(pg_temp.h26_observation(),(select value from h26_seen where name='before-child-fault'),
  'H26 audit/payment/session failures roll back order, money, receipt allocation, booking and stock');
set local role postgres;
drop trigger h26_fail_audit on public.audit_log;
drop trigger h26_fail_payment on public.payments;
select pg_temp.h26_claim();
set local role authenticated;
select is(pg_temp.h26_sale(3,301,'{"reason":"H26 fail audit"}')->>'replayed','false','H26 failed audit did not consume the sale key');
select is(pg_temp.h26_sale(3,302,'{"reason":"H26 fail payment"}')->>'replayed','false','H26 failed child did not consume the sale key');
set local role postgres;
select set_config('request.jwt.claims','',true);
alter table public.addon_products disable trigger user;
update public.addon_products set currency='USD' where id=pg_temp.h26_id(4,7);
alter table public.addon_products enable trigger user;
update h26_seen set value=(select to_jsonb(p) from public.addon_products p where id=pg_temp.h26_id(4,7)) where name='offer-7';
select pg_temp.h26_claim();
set local role authenticated;
select is(pg_temp.h26_sale(7,399)->>'detail','unsupported_currency','H26 v1 refuses non-INR sale without conversion');
select * from finish();
rollback;
