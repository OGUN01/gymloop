-- Independent frozen-spec SHP/MEDIA holdout. Fixture prefix 72900000.
-- No visible SHP test, feature implementation, other author output or evidence read.
-- Trusted SQL metadata receipts are not byte/R2 verification evidence.
-- Sequential winner/replay checks do not prove cross-session race correctness.
-- Two explicitly bounded rollback-only default seams below simulate later command
-- transactions inside this single BEGIN. They do not prove production clocks:
-- mandatory separate real multi-transaction ordinary-RPC reserve/fulfil/replay
-- evidence must run with the unmodified now() order default and SHP-011 guard.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(271);

create function pg_temp.u(n integer) returns uuid language sql immutable as $$
select ('72900000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid
$$;
create function pg_temp.staff_claim(n integer default 1) returns text language sql as $$
select jsonb_build_object('role','authenticated','sub',pg_temp.u(200+n),
 'tenant_id',pg_temp.u(case when n=5 then 2 else 1 end),'staff_id',pg_temp.u(200+n),
 'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk'
 when 4 then 'trainer' when 5 then 'gym_owner' when 6 then 'gym_owner' end)::text
$$;
create function pg_temp.member_claim(n integer default 1) returns text language sql as $$
select jsonb_build_object('role','authenticated','sub',pg_temp.u(300+n),
 'tenant_id',pg_temp.u(case when n=3 then 2 else 1 end),'member_id',pg_temp.u(100+n),'app_role','member')::text
$$;
create function pg_temp.run(q text,c text default pg_temp.staff_claim(),r text default 'authenticated')
returns jsonb language plpgsql as $$
declare v jsonb; d text;
begin
 perform set_config('request.jwt.claims',coalesce(c,''),true);
 execute format('set local role %I',r);
 -- Void commands need row-to-JSON conversion rather than assignment of void text to JSON.
 if q ~ '^select (public|app)\.' then
  q:='select to_jsonb(command_result) from ('||q||')command_result';
 end if;
 begin execute q into v; v:=jsonb_build_object('value',v);
 exception when others then
 get stacked diagnostics d=pg_exception_detail;
 v:=jsonb_build_object('error',sqlstate,'detail',coalesce(d,''));
 end;
 set local role postgres;
 perform set_config('request.jwt.claims','',true);
 return v;
end $$;
create function pg_temp.refused(q text,code text,detail text,label text,
 c text default pg_temp.staff_claim(),r text default 'authenticated') returns text language sql as $$
select is(pg_temp.run(q,c,r),jsonb_build_object('error',code,'detail',detail),label)
$$;
create function pg_temp.denied(q text,label text,c text default pg_temp.staff_claim(),r text default 'authenticated')
returns text language sql as $$
select is(pg_temp.run(q,c,r)->>'error','42501',label)
$$;
create function pg_temp.good(q text,label text,c text default pg_temp.staff_claim(),r text default 'authenticated')
returns text language sql as $$
select is(pg_temp.run(q,c,r)->>'error',null::text,label)
$$;
create temp table h72_state(k text primary key,v jsonb);
grant select on h72_state to authenticated,service_role;
insert into public.organizations(id,name,gym_code,status) values
(pg_temp.u(1),'SHP holdout A','H72SHA','active'),(pg_temp.u(2),'SHP holdout B','H72SHB','active');
insert into public.organization_settings(tenant_id) values(pg_temp.u(1)),(pg_temp.u(2));
insert into public.branches(id,tenant_id,name,is_default) values
(pg_temp.u(11),pg_temp.u(1),'A',true),(pg_temp.u(12),pg_temp.u(2),'B',true);
insert into auth.users(id) select pg_temp.u(n) from generate_series(201,206)n;
insert into auth.users(id) select pg_temp.u(n) from generate_series(301,303)n;
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active)
select pg_temp.u(200+n),pg_temp.u(200+n),pg_temp.u(case when n=5 then 2 else 1 end),
 pg_temp.u(case when n=5 then 12 else 11 end),
 (case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk'
 when 4 then 'trainer' when 5 then 'gym_owner' when 6 then 'gym_owner' end)::public.app_role,
 'Holdout staff '||n,n<>6 from generate_series(1,6)n;
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone,date_of_birth)
select pg_temp.u(100+n),pg_temp.u(300+n),pg_temp.u(case when n=3 then 2 else 1 end),
 pg_temp.u(case when n=3 then 12 else 11 end),'Holdout member '||n,'+91972900000'||n,'1990-01-01'
from generate_series(1,3)n;
insert into public.addon_products(id,tenant_id,kind,name,description,cancellation_terms,validity_days,price_paise,stock_quantity)
select pg_temp.u(400+n),pg_temp.u(1),'product','Holdout product '||n,'Exact disclosed item','Desk returns policy',30,
 case when n=2 then 9007199254740993 else 12001 end,case when n=3 then 0 when n=4 then 1 else 20 end
from generate_series(1,12)n;
insert into public.addon_products(id,tenant_id,kind,name,description,cancellation_terms,validity_days,price_paise) values
(pg_temp.u(450),pg_temp.u(1),'diet_plan','Locker','Locker use','Desk policy',30,5001),
(pg_temp.u(451),pg_temp.u(1),'diet_plan','Complimentary towel','Towel service','Desk policy',1,0),
(pg_temp.u(460),pg_temp.u(2),'diet_plan','Foreign service','Service','Desk policy',30,5001);
-- Hidden offers may omit disclosure terms, but product stock is always required.
insert into public.addon_products(id,tenant_id,kind,name,price_paise,is_active,stock_quantity,description) values
(pg_temp.u(470),pg_temp.u(1),'product','Hidden incomplete',100,false,0,null);
create function pg_temp.q(n integer) returns uuid language sql stable as $$
select quote_version from public.addon_products where id=pg_temp.u(n)
$$;
create function pg_temp.reserve(n integer,qty integer default 1,quote uuid default null) returns text language sql as $$
select format('select to_jsonb(x) from public.create_shop_reservation(%L::uuid,%s,%L::uuid)x',pg_temp.u(n),qty,coalesce(quote,pg_temp.q(n)))
$$;
create function pg_temp.rid(k text) returns uuid language sql stable as $$
select (v->'value'->>'reservation_id')::uuid from h72_state where h72_state.k=$1
$$;
create function pg_temp.fulfil(k text,keyn integer,quote uuid default null,method text default 'cash',reason text default null)
returns text language sql as $$
select format('select to_jsonb(x) from public.fulfil_shop_reservation(%L::uuid,%L::uuid,%L::public.payment_method,%L,%L::uuid)x',
 pg_temp.rid(k),coalesce(quote,(select p.quote_version from public.addon_products p join public.shop_reservations r on r.product_id=p.id where r.id=pg_temp.rid(k))),method,reason,pg_temp.u(keyn))
$$;
create function pg_temp.key(n integer,area text default 'staging',kind text default 'product',tenant integer default 1,ext text default 'jpg')
returns text language sql immutable as $$
select pg_temp.u(tenant)::text||'/'||area||'/'||kind||'/'||pg_temp.u(n)::text||'.'||ext
$$;
create function pg_temp.asset(k text) returns uuid language sql stable as $$
select (v->>'value')::uuid from h72_state where h72_state.k=$1
$$;
create function pg_temp.finalize(k text,overrides jsonb default '{}'::jsonb) returns text language plpgsql as $$
declare m jsonb;
begin
 select jsonb_build_object('asset',id,'user',pg_temp.u(201),'staff',pg_temp.u(201),'role','gym_owner',
 'tenant',tenant_id,'kind',kind,'mime',mime,'bytes',bytes,'stage',staging_object_key,
 'source','source-receipt','published',pg_temp.key(900,'published',kind),'etag','published-receipt') into m
 from public.media_assets where id=pg_temp.asset(k);
 m:=m||overrides;
 return format('select to_jsonb(public.finalize_media_asset(%L::uuid,%L::uuid,%L::uuid,%L::public.app_role,%L::uuid,%L,%L,%s,%L,%L,%L,%L))',
 m->>'asset',m->>'user',m->>'staff',m->>'role',m->>'tenant',m->>'kind',m->>'mime',m->>'bytes',m->>'stage',m->>'source',m->>'published',m->>'etag');
end $$;

create function pg_temp.trusted_write(q text,marker text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform set_config('app.media_finalize_command',marker,true);
 execute q;
 return 'true'::jsonb;
end $$;
create function pg_temp.expiry_boundary() returns jsonb language plpgsql as $$
declare result jsonb;
begin
 insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
 values(pg_temp.u(701),pg_temp.u(1),pg_temp.u(102),pg_temp.u(410),'Exact equality','product',1,pg_temp.q(410),12001,statement_timestamp()-interval '1 day',statement_timestamp());
 result:=jsonb_build_object('equal',(select expires_at=statement_timestamp() from public.shop_reservations where id=pg_temp.u(701)),
 'held',app.shop_held_quantity(pg_temp.u(1),pg_temp.u(410)),
 'cancel',pg_temp.run('select public.cancel_shop_reservation(pg_temp.u(701),null)',pg_temp.member_claim(2))->>'detail',
 'fulfil',pg_temp.run('select to_jsonb(x) from public.fulfil_shop_reservation(pg_temp.u(701),pg_temp.q(410),''cash'',null,pg_temp.u(803))x')->>'detail');
 return result;
end $$;

-- Bounded structural matrices: one assertion per independently forbidden grant.
select enum_has_labels('public','shop_reservation_status',array['reserved','fulfilled','cancelled_by_member','cancelled_by_gym']::name[],'canonical state enum excludes stored expiry');
select ok((select relrowsecurity from pg_class where oid=('public.'||t)::regclass),'RLS enabled '||t)
from unnest(array['media_assets','shop_categories','shop_reservations'])t;
select ok(not has_table_privilege('anon','public.'||t,p),'anon no '||p||' '||t)
from unnest(array['media_assets','shop_categories','shop_reservations'])t cross join unnest(array['SELECT','INSERT','UPDATE','DELETE'])p;
select ok(not has_table_privilege('authenticated','public.'||t,'DELETE'),'authenticated no DELETE '||t)
from unnest(array['media_assets','shop_categories','shop_reservations'])t;
select ok(not has_column_privilege('authenticated','public.media_assets',c,'SELECT'),'MED private column '||c)
from unnest(array['staging_object_key','object_key','verified_source_etag','published_etag'])c;
select ok(has_column_privilege('authenticated','public.media_assets',c,'SELECT'),'MED safe column '||c)
from unnest(array['id','tenant_id','kind','mime','bytes','created_by_staff_id','created_at','confirmed_at','deleted_at','attached_to_id'])c;
select ok(not has_table_privilege('authenticated','public.media_assets',p),'MED no table '||p)
from unnest(array['SELECT','INSERT','UPDATE'])p;
select ok(not has_function_privilege(r,'public.confirm_media_asset(uuid)','EXECUTE'),'MED old confirm revoked '||r)
from unnest(array['anon','authenticated','service_role'])r;
select ok(has_function_privilege(r,'public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text)','EXECUTE')=(r='service_role'),'MED finalizer grant '||r)
from unnest(array['anon','authenticated','service_role'])r;
select ok(not has_function_privilege(r,s,'EXECUTE'),'private helper '||s||' '||r)
from unnest(array['authenticated','service_role'])r cross join unnest(array[
'app.media_attach(uuid,uuid,text,uuid)','app.media_release(uuid,text,uuid)',
'app.media_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb)',
'app.shop_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)',
'app.shop_held_quantity(uuid,uuid)','app.enforce_media_asset_verification()'])s;
select ok((select prosecdef=d and provolatile=v::"char" and pg_get_userbyid(proowner)='postgres'
 and proconfig @> array['search_path=""'] from pg_proc where oid=s::regprocedure),'owner/path/volatility '||s)
from (values
('public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text)',true,'v'),
('public.confirm_media_asset(uuid)',false,'v'),('public.read_member_shop()',true,'s'),
('public.read_member_shop_reservations()',true,'s'),('public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid)',false,'v'),
('app.enforce_media_asset_verification()',false,'v'),('app.enforce_shop_reservation()',false,'v'))x(s,d,v);
select pg_temp.denied('select to_jsonb(x) from public.'||rpc||'()x','member read rejects '||label||' '||rpc,c)
from unnest(array['read_member_shop','read_member_shop_reservations'])rpc cross join (values
('missing','{}'),('staff',pg_temp.staff_claim()),
('contradictory',(pg_temp.member_claim()::jsonb||jsonb_build_object('staff_id',pg_temp.u(201)))::text),
('wrong user',(pg_temp.member_claim()::jsonb||jsonb_build_object('sub',pg_temp.u(302)))::text),
('preview',(pg_temp.member_claim()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text))x(label,c);
select pg_temp.denied('select to_jsonb(x) from public.read_shop_product_holds()x','holds rejects non-front office',pg_temp.staff_claim(n)) from unnest(array[4,6])n;
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_reservations',pg_temp.member_claim())->'value','0'::jsonb,'member no direct reservation rows');
select is(pg_temp.run('select to_jsonb(count(id)) from public.media_assets',pg_temp.member_claim())->'value','0'::jsonb,'member no media rows');
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_categories',pg_temp.member_claim())->'value','0'::jsonb,'member no category rows');
select is(pg_temp.run('select to_jsonb(count(*)) from public.read_member_shop() where item_id=pg_temp.u(460)',pg_temp.member_claim())->'value','0'::jsonb,'foreign catalogue hidden');
select is(pg_temp.run('select to_jsonb(availability) from public.read_member_shop() where item_id=pg_temp.u(403)',pg_temp.member_claim())->'value','"out_of_stock"'::jsonb,'zero stock listed');
select is(pg_temp.run('select to_jsonb(price_paise) from public.read_member_shop() where item_id=pg_temp.u(402)',pg_temp.member_claim())->'value','"9007199254740993"'::jsonb,'exact price above JS safe integer');
select is(pg_temp.run('select to_jsonb(available_quantity) from public.read_member_shop() where item_id=pg_temp.u(450)',pg_temp.member_claim())->'value','null'::jsonb,'services no held quantity');
select is(pg_temp.run('select to_jsonb(array(select key from jsonb_object_keys(to_jsonb(x))key order by key)) from public.read_member_shop()x limit 1',pg_temp.member_claim())->'value',
to_jsonb(array['availability','available_quantity','cancellation_terms','category_id','category_name','currency','description','gst_rate_bp','image_asset_id','item_id','name','price_paise','quote_version','section','validity_days']),'exact safe public catalogue projection');

insert into h72_state values('before',jsonb_build_object('orders',(select count(*) from public.addon_orders),'payments',(select count(*) from public.payments)));
insert into h72_state values('r1',pg_temp.run(pg_temp.reserve(401,2),pg_temp.member_claim())),('r1clock',to_jsonb(statement_timestamp()));
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_reservations',pg_temp.member_claim())->'value','0'::jsonb,'member direct reservations hidden with a real own row');
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_reservations where tenant_id=pg_temp.u(1)',pg_temp.staff_claim(5))->'value','0'::jsonb,'foreign front office real reservation hidden');
select ok((select v->>'error' is null and v->'value'->>'reservation_id' is not null from h72_state where k='r1'),'reserve succeeds');
select is((select stock_quantity from public.addon_products where id=pg_temp.u(401)),20,'reserve never decrements stock');
select ok((select count(*) from public.addon_orders)=(select (v->>'orders')::bigint from h72_state where k='before') and
 (select count(*) from public.payments)=(select (v->>'payments')::bigint from h72_state where k='before'),'reservation no money records');
select ok((select product_name='Holdout product 1' and quantity=2 and unit_price_paise=12001 and currency='INR' and status='reserved'
 and created_at=(select (v#>>'{}')::timestamptz from h72_state where k='r1clock')
 and expires_at=created_at+interval '24 hours' from public.shop_reservations where id=pg_temp.rid('r1')),'intent snapshot uses exact command clock and 24-hour expiry');
select is(pg_temp.run('select to_jsonb(available_quantity) from public.read_member_shop() where item_id=pg_temp.u(401)',pg_temp.member_claim(2))->'value','18'::jsonb,'other member derived availability');
select is(pg_temp.run('select to_jsonb(held_quantity) from public.read_shop_product_holds() where product_id=pg_temp.u(401)')->'value',to_jsonb(app.shop_held_quantity(pg_temp.u(1),pg_temp.u(401))),'desk/private hold parity under live hold');
select is(pg_temp.run('select to_jsonb(x) from public.create_shop_reservation(null,0,null)x',pg_temp.member_claim())->>'error','22023','null before product');
select pg_temp.denied('select to_jsonb(x) from public.create_shop_reservation(null,0,null)x','caller precedes null arguments','{}');
select pg_temp.refused('select to_jsonb(x) from public.create_shop_reservation(pg_temp.u(460),0,pg_temp.u(999))x','GL086','item_unavailable','foreign before quantity',pg_temp.member_claim());
select pg_temp.refused('select to_jsonb(x) from public.create_shop_reservation(pg_temp.u(470),0,pg_temp.u(999))x','GL086','item_unavailable','unlistable before quote',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(401,0,pg_temp.u(999)),'GL086','quote_changed','quote before quantity',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(401,0),'GL086','invalid_quantity','quantity before duplicate',pg_temp.member_claim());
update public.addon_products set stock_quantity=1 where id=pg_temp.u(401);
select pg_temp.refused(pg_temp.reserve(401),'GL086','reservation_exists','duplicate before stock',pg_temp.member_claim());
update public.addon_products set stock_quantity=20 where id=pg_temp.u(401);
select pg_temp.refused(pg_temp.reserve(450,2),'GL086','invalid_quantity','service exactly one',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(403),'GL087','sold_out','zero stock refused',pg_temp.member_claim());
update public.members set status='blocked' where id=pg_temp.u(101);
select pg_temp.refused(pg_temp.reserve(460,0),'GL086','item_unavailable','unknown product before member eligibility',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(470,0,pg_temp.u(999)),'GL086','member_unavailable','eligibility before offer quote quantity',pg_temp.member_claim());
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''r1''),''client invented reason'')','blocked member may cancel',pg_temp.member_claim());
select ok((select status='cancelled_by_member' and cancel_reason is null and cancelled_by_staff_id is null from public.shop_reservations where id=pg_temp.rid('r1')),'member reason ignored');
update public.members set status='active' where id=pg_temp.u(101);
select pg_temp.denied('select public.cancel_shop_reservation(pg_temp.rid(''r1''),null)','cancel privacy other or foreign member',pg_temp.member_claim(n)) from unnest(array[2,3])n;
select pg_temp.refused('select public.cancel_shop_reservation(pg_temp.rid(''r1''),null)','GL086','reservation_not_open','terminal cancel',pg_temp.member_claim());
insert into h72_state values('large',pg_temp.run(pg_temp.reserve(402,10),pg_temp.member_claim()));
select is(pg_temp.run('select to_jsonb(total_paise) from public.read_member_shop_reservations() where reservation_id=pg_temp.rid(''large'')',pg_temp.member_claim())->'value','"90071992547409930"'::jsonb,'decimal multiply exact');
select is(pg_temp.run('select to_jsonb(array(select key from jsonb_object_keys(to_jsonb(x))key order by key)) from public.read_member_shop_reservations()x limit 1',pg_temp.member_claim())->'value',
to_jsonb(array['cancel_reason','created_at','currency','expires_at','image_asset_id','item_id','item_name','order_id','quantity','reservation_id','section','state','terms_changed','total_paise','unit_price_paise']),'exact safe reservation projection');
select pg_temp.denied('select public.cancel_shop_reservation(pg_temp.u(999),null)','unknown cancellation indistinguishable',pg_temp.member_claim());
insert into h72_state values('last',pg_temp.run(pg_temp.reserve(404),pg_temp.member_claim(2)));
select pg_temp.refused(pg_temp.reserve(404),'GL087','sold_out','sequential last-unit winner holds',pg_temp.member_claim());
update public.addon_products set stock_quantity=0 where id=pg_temp.u(404);
select pg_temp.refused(pg_temp.fulfil('last',801),'GL057','insufficient_stock','soft hold insufficient stock passes through');
select ok((select status='reserved' and order_id is null from public.shop_reservations where id=pg_temp.rid('last')),'stock refusal rolls reservation back');
select is(pg_temp.run('select to_jsonb(available_quantity) from public.read_member_shop() where item_id=pg_temp.u(404)',pg_temp.member_claim())->'value','0'::jsonb,'negative availability floored');
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''last''),''Unavailable at the desk'')','desk cancel soft hold loss',pg_temp.staff_claim(3));
select is(pg_temp.run('select to_jsonb(cancel_reason) from public.read_member_shop_reservations() where reservation_id=pg_temp.rid(''last'')',pg_temp.member_claim(2))->'value','"Unavailable at the desk"'::jsonb,'gym reason visible to own member');
insert into h72_state select 'limit'||n,pg_temp.run(pg_temp.reserve(n),pg_temp.member_claim()) from generate_series(405,408)n;
update public.addon_products set stock_quantity=0 where id=pg_temp.u(409);
select pg_temp.refused(pg_temp.reserve(409),'GL086','reservation_limit','sixth open refused',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(405),'GL086','reservation_exists','duplicate wins over open limit',pg_temp.member_claim());
select pg_temp.run('select public.cancel_shop_reservation(pg_temp.rid(''large''),null)',pg_temp.member_claim());
select pg_temp.run(format('select public.cancel_shop_reservation(%L::uuid,null)',pg_temp.rid('limit'||n)),pg_temp.member_claim()) from generate_series(405,408)n;
update public.addon_products set stock_quantity=20 where id=pg_temp.u(409);
insert into h72_state values('rolling7',pg_temp.run(pg_temp.reserve(409),pg_temp.member_claim()));
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''rolling7''),null)','rolling seventh creation accepted',pg_temp.member_claim());
insert into h72_state values('rolling8',pg_temp.run(pg_temp.reserve(409),pg_temp.member_claim()));
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''rolling8''),null)','rolling eighth creation accepted',pg_temp.member_claim());
insert into h72_state values('rolling9',pg_temp.run(pg_temp.reserve(409),pg_temp.member_claim()));
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''rolling9''),null)','rolling ninth creation accepted',pg_temp.member_claim());
insert into h72_state values('rolling10',pg_temp.run(pg_temp.reserve(409),pg_temp.member_claim()));
select pg_temp.good('select public.cancel_shop_reservation(pg_temp.rid(''rolling10''),null)','rolling tenth creation accepted',pg_temp.member_claim());
select pg_temp.refused(pg_temp.reserve(409),'GL086','reservation_limit','rolling eleventh refuses even no open holds',pg_temp.member_claim());

-- Establish expired fixture only at INSERT; no edit of frozen expiry to fake time travel.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
values(pg_temp.u(700),pg_temp.u(1),pg_temp.u(102),pg_temp.u(410),'Boundary snapshot','product',1,pg_temp.q(410),12001,statement_timestamp()-interval '1 day',statement_timestamp());
select is(pg_temp.run('select to_jsonb(state) from public.read_member_shop_reservations() where reservation_id=pg_temp.u(700)',pg_temp.member_claim(2))->'value','"expired"'::jsonb,'expiry equality');
select is(pg_temp.expiry_boundary(),'{"equal":true,"held":0,"cancel":"reservation_expired","fulfil":"reservation_expired"}'::jsonb,'literal same-statement expiry boundary');
select is(pg_temp.run('select to_jsonb(available_quantity) from public.read_member_shop() where item_id=pg_temp.u(410)',pg_temp.member_claim())->'value','20'::jsonb,'expiry equality no hold');
select pg_temp.refused('select public.cancel_shop_reservation(pg_temp.u(700),null)','GL086','reservation_expired','expiry equality cancel',pg_temp.member_claim(2));
select pg_temp.refused('select to_jsonb(x) from public.fulfil_shop_reservation(pg_temp.u(700),pg_temp.q(410),''cash'',null,pg_temp.u(802))x','GL086','reservation_expired','expiry equality fulfil');
select is(pg_temp.run('update public.shop_reservations set '||col||'='||expr||' where id=pg_temp.u(700)','{}','postgres')->>'error','GL086','postgres reservation immutable '||col)
from (values ('quantity','2'),('unit_price_paise','0'),('product_name','''rewritten'''),('expires_at','expires_at+interval ''1 day'''),('member_id','pg_temp.u(101)'),('quote_version','pg_temp.u(999)'))x(col,expr);

insert into h72_state values('sale',pg_temp.run(pg_temp.reserve(411,2),pg_temp.member_claim(2)));
insert into h72_state values('oldquote',to_jsonb(pg_temp.q(411)));
update public.addon_products set price_paise=13003 where id=pg_temp.u(411);
select is(pg_temp.run('select to_jsonb(terms_changed) from public.read_member_shop_reservations() where reservation_id=pg_temp.rid(''sale'')',pg_temp.member_claim(2))->'value','true'::jsonb,'terms changed current quote');
select pg_temp.refused(pg_temp.fulfil('sale',810,(select (v#>>'{}')::uuid from h72_state where k='oldquote')),'GL055','quote_changed','fulfil quote passed through');
update public.addon_products set is_active=false where id=pg_temp.u(411);
select pg_temp.refused(pg_temp.fulfil('sale',810),'GL055','offer_unavailable','inactive sale passed through');
update public.addon_products set is_active=true where id=pg_temp.u(411);
update public.members set status='blocked' where id=pg_temp.u(102);
select pg_temp.refused(pg_temp.fulfil('sale',810),'GL055','member_unavailable','member sale refusal passed through');
update public.members set status='active' where id=pg_temp.u(102);
select pg_temp.refused(pg_temp.fulfil('sale',810,null,'razorpay'),'GL055','invalid_payment','fulfil no online charge');
select ok((select status='reserved' and order_id is null from public.shop_reservations where id=pg_temp.rid('sale')) and
 not exists(select 1 from public.addon_orders where idempotency_key=pg_temp.u(810)),'sale refusal rollback money and intent');
-- BEGIN bounded successful sale/fulfil command-transaction simulation.
-- Only the column default changes; all sale functions and invariant triggers stay active.
insert into h72_state values('order_created_default',to_jsonb((select pg_get_expr(d.adbin,d.adrelid)
 from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
 where d.adrelid='public.addon_orders'::regclass and a.attname='created_at')));
select is((select v#>>'{}' from h72_state where k='order_created_default'),'now()','canonical order default is transaction timestamp before bounded seam');
alter table public.addon_orders alter column created_at set default statement_timestamp();
insert into h72_state values('fulfilled',pg_temp.run(pg_temp.fulfil('sale',810)));
select ok((select v->>'error' is null and v->'value'->>'replayed'='false' from h72_state where k='fulfilled'),'first fulfil');
select ok((select r.status='fulfilled' and r.order_id=o.id and o.quantity=2 and o.unit_price_paise=13003 and o.total_paise=26006 and
 o.sold_by_staff_id=pg_temp.u(201) and o.created_at>=r.created_at
 from public.shop_reservations r join public.addon_orders o on o.id=r.order_id where r.id=pg_temp.rid('sale')),'conversion current integer money actor and causal order timestamp');
select is((select stock_quantity from public.addon_products where id=pg_temp.u(411)),18,'sale decrements once');
insert into h72_state values('replaybefore',jsonb_build_object('orders',(select count(*) from public.addon_orders),'payments',(select count(*) from public.payments),'audit',(select count(*) from public.audit_log where tenant_id=pg_temp.u(1))));
select is(pg_temp.run(pg_temp.fulfil('sale',810))->'value'->>'replayed','true','same key replay');
select ok((select count(*) from public.addon_orders)=(select (v->>'orders')::bigint from h72_state where k='replaybefore') and
 (select count(*) from public.payments)=(select (v->>'payments')::bigint from h72_state where k='replaybefore') and
 (select count(*) from public.audit_log where tenant_id=pg_temp.u(1))=(select (v->>'audit')::bigint from h72_state where k='replaybefore'),'replay no duplicates');
select pg_temp.refused(pg_temp.fulfil('sale',811),'GL086','reservation_not_open','terminal new key');
select pg_temp.refused(pg_temp.fulfil('sale',810,null,'upi'),'GL052','idempotency_conflict','same key changed method');
select is(pg_temp.run('update public.shop_reservations set updated_at=updated_at+interval ''1 second'' where id=pg_temp.rid(''sale'')','{}','postgres')->>'detail','reservation_not_open','terminal invariant even housekeeping timestamp');
select is(pg_temp.run(format('select pg_temp.trusted_write(%L,%L)','update public.shop_reservations set quantity=3 where id=pg_temp.rid(''sale'')','irrelevant'),
 '{"role":"service_role"}','service_role')->>'error','GL086','service credential and postgres definer cannot bypass terminal reservation');
select pg_temp.denied('select app.shop_reservation_mark_fulfilled(pg_temp.rid(''sale''),pg_temp.u(999))','member cannot forge private conversion helper',pg_temp.member_claim(2));
select pg_temp.denied(pg_temp.fulfil('sale',810),'fulfil forbidden role/tenant',c)
from (values(pg_temp.staff_claim(4)),(pg_temp.staff_claim(5)),(pg_temp.member_claim(2)))x(c);
insert into h72_state values('free',pg_temp.run(pg_temp.reserve(451),pg_temp.member_claim(2)));
select pg_temp.refused(pg_temp.fulfil('free',820,null,null,null),'GL055','invalid_payment','free reservation still requires desk reason');
insert into h72_state values('freefulfilled',pg_temp.run(pg_temp.fulfil('free',820,null,null,'Complimentary towel')));
select ok((select v->>'error' is null and v->'value'->>'payment_id' is null from h72_state where k='freefulfilled'),'free reservation converts without payment');
-- A genuine ordinary sale before a genuine reservation must remain inadmissible.
-- This negative causal guard prevents the seam from relaxing SHP-011 semantics.
insert into h72_state values('priororder',pg_temp.run('select to_jsonb(x) from public.record_addon_sale(pg_temp.u(102),pg_temp.u(410),1,pg_temp.q(410),null,null,null,''cash'',null,pg_temp.u(827))x'));
insert into h72_state values('laterreservation',pg_temp.run(pg_temp.reserve(410),pg_temp.member_claim(2)));
select ok((select o.created_at<r.created_at from public.addon_orders o cross join public.shop_reservations r
 where o.id=(select (v->'value'->>'order_id')::uuid from h72_state where k='priororder') and r.id=pg_temp.rid('laterreservation')),
 'genuine earlier ordinary sale predates later reservation even inside bounded seam');
select is(pg_temp.run(format('update public.shop_reservations set status=''fulfilled'',fulfilled_at=statement_timestamp(),fulfilled_by_staff_id=pg_temp.u(201),order_id=%L::uuid where id=pg_temp.rid(''laterreservation'')',
 (select v->'value'->>'order_id' from h72_state where k='priororder')),'{}','postgres')->>'error','GL086','postgres cannot link genuine pre-reservation order');
select ok((select status='reserved' and order_id is null from public.shop_reservations where id=pg_temp.rid('laterreservation')),'earlier-order refusal leaves reservation untouched');
-- Execute the canonical deferred order guard before DDL; never disable it.
set constraints public.addon_orders_unaccepted immediate;
set constraints public.addon_orders_unaccepted deferred;
alter table public.addon_orders alter column created_at set default now();
select is((select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
 where d.adrelid='public.addon_orders'::regclass and a.attname='created_at'),
 (select v#>>'{}' from h72_state where k='order_created_default'),'exact order default restored after bounded fulfil/replay cases');
-- END bounded successful sale/fulfil command-transaction simulation.

-- Registration, metadata receipt protocol and invariant bypass attempts.
insert into h72_state select kind,pg_temp.run(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))',kind,pg_temp.key(n,'staging',kind),'image/jpeg'))
from (values ('product',901),('trainer',902),('announcement',903))x(kind,n);
select ok(v->>'error' is null and v->>'value' is not null,'MED register '||k) from h72_state where k in ('product','trainer','announcement') order by k;
insert into h72_state values('unconfirmed',pg_temp.run(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(905),'image/jpeg')));
select is(pg_temp.run(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(901),'image/jpeg'))->>'error','22023','MED duplicate staging key');
select is(pg_temp.run(format('select to_jsonb(public.register_media_asset(%L,%L,%L,%s))','product',key,mime,bytes))->>'error',code,'MED register rejects '||label)
from (values
(pg_temp.key(904,'published'),'image/jpeg',1234,'22023','published key'),
(pg_temp.key(904,'staging','product',2),'image/jpeg',1234,'42501','foreign scope'),
(pg_temp.key(904,'staging','product',1,'png'),'image/jpeg',1234,'22023','extension mismatch'),
(pg_temp.key(904),'image/svg+xml',1234,'22023','SVG'),(pg_temp.key(904),'image/jpeg',2097153,'22023','oversize'),
(pg_temp.key(904),'image/jpeg',0,'22023','empty'))x(key,mime,bytes,code,label);
select pg_temp.denied(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(910+n),'image/jpeg'),'MED allowed real actor '||n,pg_temp.staff_claim(n)) from unnest(array[3,4,5,6])n;
select pg_temp.denied(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(917),'image/jpeg'),'MED preview cannot register',
 (pg_temp.staff_claim()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text);
select pg_temp.denied('select public.delete_media_asset(pg_temp.asset(''product''),false)','MED foreign delete privacy',pg_temp.staff_claim(5));
select pg_temp.denied('select public.delete_media_asset(pg_temp.u(999),false)','MED unknown delete privacy');
select pg_temp.denied('select public.confirm_media_asset(pg_temp.asset(''product''))','MED old confirm denied '||r,case when r='service_role' then '{"role":"service_role"}' else '{}' end,r)
from unnest(array['anon','authenticated','service_role','postgres'])r;
select pg_temp.denied(pg_temp.finalize('product'),'MED finalizer rejects '||label,c,r)
from (values
('{"role":"service_role"}','postgres','wrong original connection role'),
('{"role":"authenticated"}','service_role','wrong JWT role'),
('{"role":"service_role","sub":"72900000-0000-4000-8000-0000000000c9"}','service_role','service subject'),
('{"role":"service_role","impersonation_session_id":"72900000-0000-4000-8000-000000000999"}','service_role','service impersonation'),
(pg_temp.staff_claim(),'authenticated','end user'))x(c,r,label);
select pg_temp.refused(format('select pg_temp.trusted_write(%L,%L)',
 'update public.media_assets set object_key=pg_temp.key(999,''published''),verified_source_etag=''src'',published_etag=''pub'',confirmed_at=statement_timestamp() where id=pg_temp.asset(''product'')',
 'bogus'),'GL086','media_verification_invariant','MED bogus marker with correct credential and postgres definer','{"role":"service_role"}','service_role');
select pg_temp.refused(format('select pg_temp.trusted_write(%L,%L)',
 'update public.media_assets set object_key=pg_temp.key(999,''published''),verified_source_etag=''src'',published_etag=''pub'',confirmed_at=statement_timestamp() where id=pg_temp.asset(''product'')',
 'finalize:'||pg_temp.asset('trainer')::text),'GL086','media_verification_invariant','MED different asset marker credential definer','{"role":"service_role"}','service_role');
select pg_temp.refused('insert into public.media_assets(id,tenant_id,kind,mime,bytes,created_by_staff_id,staging_object_key,object_key,verified_source_etag,published_etag,confirmed_at) values(pg_temp.u(980),pg_temp.u(1),''product'',''image/jpeg'',1234,pg_temp.u(201),pg_temp.key(980),pg_temp.key(981,''published''),''src'',''pub'',statement_timestamp())',
 'GL086','media_verification_invariant','MED postgres inserting publication denied','{}','postgres');
select is(pg_temp.run(pg_temp.finalize('product',overrides),'{"role":"service_role"}','service_role')->>'error',code,'MED exact receipt rejects '||label)
from (values
(jsonb_build_object('user',pg_temp.u(202)),'42501','actor user'),
(jsonb_build_object('staff',pg_temp.u(206)),'42501','inactive actor'),
(jsonb_build_object('role','front_desk'),'42501','actor role'),
(jsonb_build_object('tenant',pg_temp.u(2)),'42501','tenant'),
(jsonb_build_object('bytes',1235),'22023','size'),(jsonb_build_object('mime','image/png'),'22023','MIME'),
(jsonb_build_object('stage',pg_temp.key(999)),'22023','staging'),
(jsonb_build_object('source',' '),'22023','source ETag'),(jsonb_build_object('etag',''),'22023','published ETag'),
(jsonb_build_object('published',pg_temp.key(999,'published','product',2)),'22023','published scope'),
(jsonb_build_object('published',pg_temp.key(999,'staging')),'22023','published area'))x(overrides,code,label);
select set_config('app.media_finalize_command','bogus',true);
select pg_temp.refused('update public.media_assets set object_key=pg_temp.key(999,''published''),verified_source_etag=''src'',published_etag=''pub'',confirmed_at=statement_timestamp() where id=pg_temp.asset(''product'')',
 'GL086','media_verification_invariant','MED bogus marker postgres stamp','{}','postgres');
select set_config('app.media_finalize_command','finalize:'||pg_temp.asset('product')::text,true);
select pg_temp.refused('update public.media_assets set object_key=pg_temp.key(999,''published''),verified_source_etag=''src'',published_etag=''pub'',confirmed_at=statement_timestamp() where id=pg_temp.asset(''product'')',
 'GL086','media_verification_invariant','MED exact marker wrong original role','{"role":"service_role"}','postgres');
select pg_temp.denied('update public.media_assets set confirmed_at=statement_timestamp() where id=pg_temp.asset(''product'')','MED authenticated stamp');
select set_config('app.media_finalize_command','prior-marker',true);
select is(pg_temp.run(pg_temp.finalize('product'),'{"role":"service_role"}','service_role')->'value','true'::jsonb,'MED trusted receipt first winner');
select is(current_setting('app.media_finalize_command',true),'prior-marker','MED marker restored');
select ok((select confirmed_at is not null and object_key=pg_temp.key(900,'published') and verified_source_etag='source-receipt' and published_etag='published-receipt'
 from public.media_assets where id=pg_temp.asset('product')),'MED winning publication tuple');
select ok((select count(*)=1 from public.audit_log where record_id=pg_temp.asset('product') and action='media_asset.confirmed' and actor_user_id=pg_temp.u(201) and actor_role='gym_owner'
 and before='{"confirmed":false}'::jsonb and after='{"confirmed":true}'::jsonb),'MED attributed safe confirmation audit');
select is(pg_temp.run(pg_temp.finalize('product',jsonb_build_object('published',pg_temp.key(999,'published'),'source','loser-source','etag','loser-published')),
 '{"role":"service_role"}','service_role')->'value','false'::jsonb,'MED eligible losing candidate replay');
select is((select object_key from public.media_assets where id=pg_temp.asset('product')),pg_temp.key(900,'published'),'MED replay preserves winner');
select is((select count(*) from public.audit_log where record_id=pg_temp.asset('product') and action='media_asset.confirmed'),1::bigint,'MED replay no duplicate audit');
update public.staff set is_active=false where id=pg_temp.u(201);
select pg_temp.denied(pg_temp.finalize('product'),'MED revoked actor replay','{"role":"service_role"}','service_role');
update public.staff set is_active=true where id=pg_temp.u(201);
select pg_temp.refused('update public.media_assets set '||col||'='||expr||' where id=pg_temp.asset(''product'')','GL086','media_verification_invariant','MED postgres immutable '||col,'{}','postgres')
from (values ('tenant_id','pg_temp.u(2)'),('staging_object_key','pg_temp.key(999)'),('kind','''trainer'''),('mime','''image/png'''),('bytes','1235'),
('created_by_staff_id','pg_temp.u(202)'),('created_at','created_at-interval ''1 day'''),('object_key','pg_temp.key(999,''published'')'),
('verified_source_etag','''other'''),('published_etag','''other'''),('confirmed_at','confirmed_at+interval ''1 second'''))x(col,expr);
select pg_temp.refused('delete from public.media_assets where id=pg_temp.asset(''product'')','GL086','media_verification_invariant','MED physical metadata delete','{}','postgres');
select pg_temp.good('select public.delete_media_asset(pg_temp.asset(''product''),true)','MED rejected attempt cannot delete winner');
select is((select deleted_at from public.media_assets where id=pg_temp.asset('product')),null::timestamptz,'MED winner remains undeleted');
select pg_temp.refused('select public.set_shop_product_display(pg_temp.u(412),null,0::smallint,pg_temp.asset(''unconfirmed''))','GL086','media_not_ready','MED unconfirmed attach');
select is(pg_temp.run(pg_temp.finalize('trainer'),'{"role":"service_role"}','service_role')->'value','true'::jsonb,'MED trusted trainer receipt');
select pg_temp.refused('select public.set_shop_product_display(pg_temp.u(412),null,0::smallint,pg_temp.asset(''trainer''))','GL086','media_kind_mismatch','MED confirmed wrong kind attach');
insert into h72_state values('attachquote',to_jsonb(pg_temp.q(412)));
select pg_temp.good('select public.set_shop_product_display(pg_temp.u(412),null,0::smallint,pg_temp.asset(''product''))','MED confirmed attach');
select is(to_jsonb(pg_temp.q(412)),(select v from h72_state where k='attachquote'),'image attachment preserves quote');
select pg_temp.good('select public.set_shop_product_display(pg_temp.u(412),null,0::smallint,pg_temp.asset(''product''))','MED same attachment replay');
select is((select count(*) from public.audit_log where action='media_asset.attached' and record_id=pg_temp.asset('product')),1::bigint,'MED attachment replay no duplicate audit');
select is(pg_temp.run('select to_jsonb(image_asset_id) from public.read_member_shop() where item_id=pg_temp.u(412)',pg_temp.member_claim())->'value',to_jsonb(pg_temp.asset('product')),'MED public opaque current image id');
select pg_temp.refused('select public.set_shop_product_display(pg_temp.u(410),null,0::smallint,pg_temp.asset(''product''))','GL086','media_in_use','MED cannot steal attachment');
select pg_temp.refused('select public.delete_media_asset(pg_temp.asset(''product''),false)','GL086','media_in_use','MED attached delete');
insert into h72_state values('displayquote',to_jsonb(pg_temp.q(412)));
select pg_temp.good('select public.set_shop_product_display(pg_temp.u(412),null,7::smallint,null)','MED release via display command');
select ok((select attached_to_id is null and deleted_at is not null and object_key=pg_temp.key(900,'published') from public.media_assets where id=pg_temp.asset('product')),'MED tombstone retains tuple');
select is(pg_temp.run('select to_jsonb(image_asset_id) from public.read_member_shop() where item_id=pg_temp.u(412)',pg_temp.member_claim())->'value','null'::jsonb,'MED released current exposure withdrawn');
select is(to_jsonb(pg_temp.q(412)),(select v from h72_state where k='displayquote'),'display does not rotate quote');
select pg_temp.refused(pg_temp.finalize('product'),'GL086','media_not_ready','MED deleted replay','{"role":"service_role"}','service_role');
select pg_temp.good('select public.delete_media_asset(pg_temp.asset(''product''),false)','MED delete tombstone replay');
select pg_temp.refused('delete from public.media_assets where id=pg_temp.asset(''product'')','GL086','media_verification_invariant','MED released metadata survives pruning','{}','postgres');
select pg_temp.denied('select to_jsonb(object_key) from public.media_assets limit 1','MED owner cannot recover key');
select pg_temp.denied('select to_jsonb(staging_object_key) from public.media_assets limit 1','MED member cannot recover staging',pg_temp.member_claim());
select is(pg_temp.run('select to_jsonb(count(id)) from public.media_assets',pg_temp.staff_claim(4))->'value','0'::jsonb,'MED trainer sees no assets');
select is(pg_temp.run('select to_jsonb(count(id)) from public.media_assets where tenant_id=pg_temp.u(1)',pg_temp.staff_claim(5))->'value','0'::jsonb,'MED foreign owner sees no assets');

insert into public.shop_categories(id,tenant_id,name,sort_order) values(pg_temp.u(501),pg_temp.u(1),'Supplements',0),(pg_temp.u(502),pg_temp.u(1),'Clothing',1),(pg_temp.u(503),pg_temp.u(2),'Foreign',0);
select pg_temp.denied('insert into public.shop_categories(tenant_id,name) values(pg_temp.u(1),''forbidden'')','category write denied role',c)
from (values(pg_temp.staff_claim(3)),(pg_temp.staff_claim(4)),(pg_temp.member_claim()))x(c);
select pg_temp.good('select public.reorder_shop_categories(array[pg_temp.u(502),pg_temp.u(501)])','owner reorder');
select is(pg_temp.run('select public.reorder_shop_categories(array[pg_temp.u(501),pg_temp.u(503)])')->>'error','22023','foreign reorder atomic refusal');
select is((select sort_order from public.shop_categories where id=pg_temp.u(501)),1::smallint,'failed reorder preserves order');
select is(pg_temp.run('select public.reorder_shop_categories(array[pg_temp.u(501),pg_temp.u(501)])')->>'error','22023','duplicate reorder');
select pg_temp.good('select public.set_shop_product_display(pg_temp.u(412),pg_temp.u(501),0::smallint,null)','owner category display');
update public.shop_categories set is_active=false where id=pg_temp.u(501);
select is(pg_temp.run('select to_jsonb(category_id) from public.read_member_shop() where item_id=pg_temp.u(412)',pg_temp.member_claim())->'value','null'::jsonb,'archived category uncategorized');
select pg_temp.refused('select public.set_shop_product_display(pg_temp.u(450),pg_temp.u(502),0::smallint,null)','GL086','category_unavailable','service cannot category');
select pg_temp.refused('select public.set_shop_product_display(pg_temp.u(412),pg_temp.u(503),0::smallint,null)','GL086','category_unavailable','foreign category');
select pg_temp.denied('select public.set_shop_product_display(pg_temp.u(460),null,0::smallint,null)','foreign product display privacy');
select pg_temp.denied('select public.set_shop_product_display(pg_temp.u(412),null,0::smallint,null)','front desk cannot display-edit',pg_temp.staff_claim(3));

-- Exactly 60 valid tenant registrations in the rolling hour; failed attempts did not count.
insert into h72_state select 'rate'||n,pg_temp.run(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(n),'image/jpeg')) from generate_series(1001,1056)n;
select ok((select count(*)=56 and bool_and(v->>'error' is null) from h72_state where k like 'rate%'),'MED through sixtieth registration accepted');
select pg_temp.refused(format('select to_jsonb(public.register_media_asset(%L,%L,%L,1234))','product',pg_temp.key(1057),'image/jpeg'),'GL086','media_limit','MED sixty-first tenant registration');
select is((select count(*) from public.media_assets where tenant_id=pg_temp.u(1)),60::bigint,'MED failed registrations wrote no rows');
select is(pg_temp.run('select to_jsonb(count(id)) from public.media_assets',pg_temp.member_claim())->'value','0'::jsonb,'member media rows hidden after real publications and tombstones');
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_categories',pg_temp.member_claim())->'value','0'::jsonb,'member categories hidden after real fixtures');
select is(pg_temp.run('select to_jsonb(count(*)) from public.shop_categories where tenant_id=pg_temp.u(1)',pg_temp.staff_claim(5))->'value','0'::jsonb,'foreign owner categories hidden with real fixtures');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1) and record_type='media_asset' and
 (coalesce(before::text,'')||coalesce(after::text,'')) ~ '(staging/|published/|source-receipt|published-receipt|https?://|etag|object_key)'),
 'MED audit has no keys ETags capabilities');

-- Completeness parity uses representative disclosed product/service and sold-out offers.
-- It calls the canonical sale command, not implementation-body matching.
-- BEGIN second bounded ordinary-sale command-transaction simulation.
alter table public.addon_orders alter column created_at set default statement_timestamp();
select ok(coalesce(pg_temp.run(format('select to_jsonb(x) from public.record_addon_sale(%L::uuid,%L::uuid,1,%L::uuid,null,null,null,%L::public.payment_method,%L,%L::uuid)x',
 pg_temp.u(102),pg_temp.u(n),pg_temp.q(n),case when n=451 then null else 'cash' end,case when n=451 then 'Holdout complimentary service' else null end,pg_temp.u(2000+n)))->>'error','') in ('','GL057'),
 'listed offer passes canonical sale completeness '||n)
from unnest(array[401,402,403,404,450,451])n;
-- Execute the canonical deferred order guard before DDL; never disable it.
set constraints public.addon_orders_unaccepted immediate;
set constraints public.addon_orders_unaccepted deferred;
alter table public.addon_orders alter column created_at set default now();
select is((select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
 where d.adrelid='public.addon_orders'::regclass and a.attname='created_at'),
 (select v#>>'{}' from h72_state where k='order_created_default'),'exact order default restored after bounded completeness parity cases');
-- END second bounded ordinary-sale command-transaction simulation.

select * from finish();
rollback;
