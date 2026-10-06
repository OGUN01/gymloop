-- Independent frozen SHP-PAGE-001..005/009 behavioral and metadata contract.
-- No implementation or visible tests read. All fixture writes are rolled back.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(114);

create function pg_temp.page_u(n integer) returns uuid language sql immutable as $$
select ('92030000-0000-4000-8000-' || lpad(to_hex(n),12,'0'))::uuid
$$;
create function pg_temp.page_claim(n integer default 1) returns jsonb language sql immutable as $$
select jsonb_build_object('role','authenticated','sub',pg_temp.page_u(300+n),'tenant_id',pg_temp.page_u(case when n=3 then 2 else 1 end),'member_id',pg_temp.page_u(100+n),'app_role','member')
$$;
create function pg_temp.page_staff_claim() returns jsonb language sql immutable as $$
select jsonb_build_object('role','authenticated','sub',pg_temp.page_u(201),'tenant_id',pg_temp.page_u(1),'staff_id',pg_temp.page_u(201),'app_role','gym_owner')
$$;
create function pg_temp.page_run(q text, claims jsonb default pg_temp.page_claim(), connection_role text default 'authenticated') returns jsonb language plpgsql as $$
declare result jsonb;
begin
  perform set_config('request.jwt.claims',coalesce(claims::text,''),true);
  execute format('set local role %I',connection_role);
  begin execute q into result; result:=jsonb_build_object('value',result);
  exception when others then result:=jsonb_build_object('error',sqlstate); end;
  set local role postgres;
  perform set_config('request.jwt.claims','',true);
  return result;
end $$;
create function pg_temp.page_read(after_time timestamptz default null, after_id uuid default null, claims jsonb default pg_temp.page_claim()) returns jsonb language sql volatile as $$
select pg_temp.page_run(format('select to_jsonb(p) from public.read_member_shop_reservation_page(%L::timestamptz,%L::uuid)p',after_time,after_id),claims)
$$;
create function pg_temp.page_ids(rows jsonb) returns jsonb language sql immutable as $$
select coalesce(jsonb_agg(x->>'reservation_id' order by ord),'[]'::jsonb) from jsonb_array_elements(coalesce(rows,'[]'::jsonb)) with ordinality as e(x,ord)
$$;
create temp table held_page_result(k text primary key, result jsonb);
create temp table held_page_expected(id uuid, created_at timestamptz);
create temp table held_page_fixture_audit(id uuid primary key);
create function pg_temp.page_fixture_member_write(q text) returns void language plpgsql as $$
declare prior_ids uuid[];
begin
 select array_agg(id) into prior_ids from public.audit_log where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2));
 execute q;
 insert into held_page_fixture_audit select id from public.audit_log where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2)) and not(id=any(coalesce(prior_ids,'{}'::uuid[])));
end $$;
create function pg_temp.page_snapshot() returns jsonb language sql stable as $$
select jsonb_build_object(
 'reservation',(select jsonb_agg(to_jsonb(r) order by id) from public.shop_reservations r where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2))),
 'product',(select jsonb_agg(to_jsonb(p) order by id) from public.addon_products p where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2))),
 'order',(select jsonb_agg(to_jsonb(o) order by id) from public.addon_orders o where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2))),
 'payment',(select jsonb_agg(to_jsonb(p) order by id) from public.payments p where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2))),
 'receipt',(select jsonb_agg(to_jsonb(i) order by id) from public.invoices i where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2))),
 'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2)))
)
$$;

insert into public.organizations(id,name,gym_code,status) values
(pg_temp.page_u(1),'Held pages A','H203PA','active'),(pg_temp.page_u(2),'Held pages B','H203PB','active');
insert into public.organization_settings(tenant_id) values(pg_temp.page_u(1)),(pg_temp.page_u(2));
insert into public.branches(id,tenant_id,name,is_default) values
(pg_temp.page_u(11),pg_temp.page_u(1),'Held A',true),(pg_temp.page_u(12),pg_temp.page_u(2),'Held B',true);
insert into auth.users(id) select pg_temp.page_u(n) from generate_series(301,308)n;
insert into auth.users(id) values(pg_temp.page_u(201));
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active)
values(pg_temp.page_u(201),pg_temp.page_u(201),pg_temp.page_u(1),pg_temp.page_u(11),'gym_owner','Held pages owner',true);
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone,date_of_birth)
select pg_temp.page_u(100+n),pg_temp.page_u(300+n),pg_temp.page_u(case when n=3 then 2 else 1 end),pg_temp.page_u(case when n=3 then 12 else 11 end),'Held pages member '||n,'+91920300000'||n,'1990-01-01' from generate_series(1,8)n;
insert into public.addon_products(id,tenant_id,kind,name,description,cancellation_terms,validity_days,price_paise,stock_quantity)
select pg_temp.page_u(400+n),pg_temp.page_u(1),'product','Current product '||n,'Held public facts','Desk return terms',30,case when n=1 then 9007199254740993 else 12001 end,100 from generate_series(1,10)n;
insert into public.addon_products(id,tenant_id,kind,name,description,cancellation_terms,validity_days,price_paise)
values(pg_temp.page_u(450),pg_temp.page_u(1),'diet_plan','Current service','Held service facts','Desk service terms',30,5001),(pg_temp.page_u(460),pg_temp.page_u(2),'diet_plan','Foreign service','Foreign facts','Foreign terms',30,5001);

-- Trusted, past-created rows retain precise three-way timestamp ties. Closing
-- still-open fixtures obeys the unchanged reservation invariant.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(1000+n),pg_temp.page_u(1),pg_temp.page_u(101),pg_temp.page_u(401),'Historic snapshot '||n,'product',case when n=61 then 10 else 1 end,p.quote_version,9007199254740993,
 timestamptz '2025-12-31 18:29:59.123450+00' + (n/3)*interval '1 microsecond',statement_timestamp()+interval '1 day'
from generate_series(1,61)n cross join public.addon_products p where p.id=pg_temp.page_u(401);
update public.shop_reservations set status=case when id in(select pg_temp.page_u(1000+n) from generate_series(1,61)n where n%4=0) then 'cancelled_by_gym'::public.shop_reservation_status else 'cancelled_by_member'::public.shop_reservation_status end,
cancelled_at=statement_timestamp(),cancelled_by_staff_id=case when id in(select pg_temp.page_u(1000+n) from generate_series(1,61)n where n%4=0) then pg_temp.page_u(201) end,
cancel_reason=case when id in(select pg_temp.page_u(1000+n) from generate_series(1,61)n where n%4=0) then 'Exact reason from gym' end
where tenant_id=pg_temp.page_u(1) and member_id=pg_temp.page_u(101);
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(1100),pg_temp.page_u(1),pg_temp.page_u(101),p.id,'Expired stored service','diet_plan',1,p.quote_version,5001,'2026-01-01 00:00:00.000001+00','2026-01-02 00:00:00.000001+00' from public.addon_products p where p.id=pg_temp.page_u(450);
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(1099),pg_temp.page_u(1),pg_temp.page_u(101),p.id,'Collected frozen product','product',1,p.quote_version,p.price_paise,'2026-01-01 00:00:00.000000+00',statement_timestamp()+interval '1 day' from public.addon_products p where p.id=pg_temp.page_u(410);
insert into held_page_result values('fulfilled',pg_temp.page_run(format('select to_jsonb(p) from public.fulfil_shop_reservation(%L::uuid,%L::uuid,''cash'',null,%L::uuid)p',pg_temp.page_u(1099),(select quote_version from public.addon_products where id=pg_temp.page_u(410)),pg_temp.page_u(1800)),pg_temp.page_staff_claim()));
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(700+n),pg_temp.page_u(1),pg_temp.page_u(101),p.id,'Active frozen product '||n,'product',1,case when n=1 then pg_temp.page_u(1900) else p.quote_version end,p.price_paise,
 timestamptz '2026-01-03 01:00:00.000001+00'+n*interval '1 microsecond',statement_timestamp()+(case when n<=3 then 1 else 2 end)*interval '1 day'
from generate_series(1,5)n join public.addon_products p on p.id=pg_temp.page_u(400+n);
-- Same-tenant other-member and foreign-tenant pages exist at higher timestamps.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(1500+n),pg_temp.page_u(case when n=3 then 2 else 1 end),pg_temp.page_u(100+n),p.id,'Other identity snapshot','diet_plan',1,p.quote_version,p.price_paise,'2026-02-01 01:00:00+00',statement_timestamp()+interval '1 day'
from generate_series(2,3)n join public.addon_products p on p.id=pg_temp.page_u(case when n=3 then 460 else 450 end);
-- Empty member 4; five active only for member 5; corrupt six-active fixture 6.
insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
select pg_temp.page_u(2000+member_n*10+product_n),pg_temp.page_u(1),pg_temp.page_u(100+member_n),p.id,'Bounded active','product',1,p.quote_version,p.price_paise,'2026-02-01 01:00:00+00',statement_timestamp()+interval '1 day'
from generate_series(5,6)member_n cross join generate_series(1,6)product_n join public.addon_products p on p.id=pg_temp.page_u(400+product_n) where product_n<=case when member_n=5 then 5 else 6 end;
-- Existing verifier-only transition produces a trusted metadata receipt, never
-- claims byte or live storage verification. The projection must expose its ID.
insert into public.media_assets(id,tenant_id,kind,staging_object_key,mime,bytes,created_by_staff_id)
values(pg_temp.page_u(2801),pg_temp.page_u(1),'product',pg_temp.page_u(1)::text||'/staging/product/'||pg_temp.page_u(2801)::text||'.jpg','image/jpeg',100,pg_temp.page_u(201));
insert into held_page_result values('media-confirmed',pg_temp.page_run(format('select to_jsonb(public.finalize_media_asset(%L::uuid,%L::uuid,%L::uuid,''gym_owner''::public.app_role,%L::uuid,''product'',''image/jpeg'',100,%L,''held-source'',%L,''held-published''))',pg_temp.page_u(2801),pg_temp.page_u(201),pg_temp.page_u(201),pg_temp.page_u(1),pg_temp.page_u(1)::text||'/staging/product/'||pg_temp.page_u(2801)::text||'.jpg',pg_temp.page_u(1)::text||'/published/product/'||pg_temp.page_u(2801)::text||'.jpg'),' {"role":"service_role"}'::jsonb,'service_role'));
insert into held_page_result values('media-attached',pg_temp.page_run(format('select to_jsonb(x) from(select public.set_shop_product_display(%L::uuid,null,0::smallint,%L::uuid))x',pg_temp.page_u(401),pg_temp.page_u(2801)),pg_temp.page_staff_claim()));
update public.addon_products set price_paise=9007199254740994 where id=pg_temp.page_u(401);
insert into held_page_expected select id,created_at from public.shop_reservations where tenant_id=pg_temp.page_u(1) and member_id=pg_temp.page_u(101) and not(status='reserved' and expires_at>statement_timestamp());
insert into held_page_result values('before',jsonb_build_object('value',pg_temp.page_snapshot()));

-- 15 narrow metadata/grant/index assertions. No implementation body inspected.
select ok(to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') is not null,'SHP-PAGE-001 additive page function exists');
select is((select proargnames::text from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),'{p_after_created_at,p_after_id,active_reservations,history,next_after_created_at,next_after_id,as_of}','SHP-PAGE-004 exact argument and projection names');
select is((select provolatile::text from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),'s','SHP-PAGE-005 stable reader');
select ok(coalesce((select prosecdef from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),false),'SHP-PAGE-001 definer boundary');
select is((select pg_get_userbyid(proowner) from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),'postgres','SHP-PAGE-001 owner');
select ok(exists(select 1 from pg_proc p cross join unnest(p.proconfig)c where p.oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') and c in('search_path=','search_path=""')),'SHP-PAGE-001 empty search path');
select is((select pronargdefaults::integer from pg_proc where oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)')),2,'SHP-PAGE-002 both inputs default null');
select ok(coalesce(has_function_privilege('authenticated',to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)'),'EXECUTE'),false),'SHP-PAGE-001 authenticated execute');
select ok(not coalesce(has_function_privilege(r,to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)'),'EXECUTE'),true),'SHP-PAGE-001 no execute '||r) from unnest(array['anon','service_role'])r;
select ok(not exists(select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a where p.oid=to_regprocedure('public.read_member_shop_reservation_page(timestamptz,uuid)') and a.grantee=0 and a.privilege_type='EXECUTE'),'SHP-PAGE-001 no PUBLIC execute');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='shop_reservations' and indexdef ~ '\(tenant_id, member_id, created_at DESC, id DESC\)'),'SHP-PAGE-003 tenant/member precise history index');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='shop_reservations' and indexdef ~ '\(tenant_id, member_id, expires_at' and indexdef ~ 'created_at DESC, id DESC' and indexdef ~ 'reserved'),'SHP-PAGE-003 tenant/member active expiry order index');
select is((select result->>'error' from held_page_result where k='fulfilled'),null::text,'SHP-PAGE-005 independent ordinary fulfil fixture established');
select is((select count(*)::integer from held_page_expected),63,'SHP-PAGE-002 independent fixture exceeds fifty');
select is((select result->'value' from held_page_result where k='media-confirmed'),'true'::jsonb,'SHP-PAGE-005 independent verified metadata fixture established');
select is((select result->>'error' from held_page_result where k='media-attached'),null::text,'SHP-PAGE-005 independent attached image fixture established');

-- Invalid caller wins over partial cursor validation. Twenty-four independent
-- missing/malformed/contradictory/foreign audience shapes.
select is(pg_temp.page_read(null,pg_temp.page_u(1),claims)->>'error','42501','SHP-PAGE-001 auth before argument: '||label)
from (values
 ('empty','{}'::jsonb),('missing role',pg_temp.page_claim()-'app_role'),('missing subject',pg_temp.page_claim()-'sub'),
 ('missing tenant',pg_temp.page_claim()-'tenant_id'),('missing member',pg_temp.page_claim()-'member_id'),
 ('null tenant',pg_temp.page_claim()||'{"tenant_id":null}'::jsonb),('null subject',pg_temp.page_claim()||'{"sub":null}'::jsonb),
 ('malformed subject',pg_temp.page_claim()||'{"sub":"bad"}'::jsonb),('malformed tenant',pg_temp.page_claim()||'{"tenant_id":"bad"}'::jsonb),
 ('malformed member',pg_temp.page_claim()||'{"member_id":"bad"}'::jsonb),('unknown member',pg_temp.page_claim()||jsonb_build_object('member_id',pg_temp.page_u(999))),
 ('wrong subject',pg_temp.page_claim()||jsonb_build_object('sub',pg_temp.page_u(302))),('same tenant wrong member',pg_temp.page_claim()||jsonb_build_object('member_id',pg_temp.page_u(102))),
 ('foreign tenant',pg_temp.page_claim()||jsonb_build_object('tenant_id',pg_temp.page_u(2))),
 ('foreign member',pg_temp.page_claim()||jsonb_build_object('member_id',pg_temp.page_u(103),'tenant_id',pg_temp.page_u(2))),
 ('staff claim',pg_temp.page_staff_claim()),('platform admin',pg_temp.page_claim()||'{"app_role":"super_admin"}'::jsonb),
 ('platform support',pg_temp.page_claim()||'{"app_role":"platform_support"}'::jsonb),('trainer',pg_temp.page_claim()||'{"app_role":"trainer"}'::jsonb),
 ('contradictory staff',pg_temp.page_claim()||jsonb_build_object('staff_id',pg_temp.page_u(201))),
 ('preview',pg_temp.page_claim()||jsonb_build_object('impersonation_session_id',pg_temp.page_u(888))),
 ('unrecognized role',pg_temp.page_claim()||'{"app_role":"member-old"}'::jsonb),
 ('service jwt contradiction',pg_temp.page_claim()||'{"role":"service_role"}'::jsonb),
 ('anonymous jwt contradiction',pg_temp.page_claim()||'{"role":"anon"}'::jsonb)
) invalid(label,claims);
select is(pg_temp.page_run('select to_jsonb(p) from public.read_member_shop_reservation_page()p',pg_temp.page_claim(),'anon')->>'error','42501','SHP-PAGE-001 native anonymous role denied');
select is(pg_temp.page_run('select to_jsonb(p) from public.read_member_shop_reservation_page()p','{"role":"service_role"}'::jsonb,'service_role')->>'error','42501','SHP-PAGE-001 service role denied');

-- Current binding and forbidden status are reread, while paused/expired members
-- retain their established read access for renewal/cancellation.
select pg_temp.page_fixture_member_write('update public.members set user_id=null where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error','42501','SHP-PAGE-001 stale unlinked binding');
select pg_temp.page_fixture_member_write('update public.members set user_id=pg_temp.page_u(308),status=''blocked'' where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error','42501','SHP-PAGE-001 blocked member');
select pg_temp.page_fixture_member_write('update public.members set status=''cancelled'' where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error','42501','SHP-PAGE-001 cancelled member');
select pg_temp.page_fixture_member_write('update public.members set status=''active'',erased_at=statement_timestamp() where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error','42501','SHP-PAGE-001 erased member');
select pg_temp.page_fixture_member_write('update public.members set erased_at=null,status=''paused'' where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error',null::text,'SHP-PAGE-001 paused reader stays bound');
select pg_temp.page_fixture_member_write('update public.members set status=''expired'' where id=pg_temp.page_u(108)');
select is(pg_temp.page_read(null,null,pg_temp.page_claim(8))->>'error',null::text,'SHP-PAGE-001 expired reader stays bound');
select pg_temp.page_fixture_member_write('update public.members set status=''active'' where id=pg_temp.page_u(108)');

select is(pg_temp.page_read(null,pg_temp.page_u(1001))->>'error','22023','SHP-PAGE-004 ID-only cursor');
select is(pg_temp.page_read('2026-01-01 00:00:00+00',null)->>'error','22023','SHP-PAGE-004 time-only cursor');
select is(pg_temp.page_run('select to_jsonb(p) from public.read_member_shop_reservation_page(''not-time''::timestamptz,null)p')->>'error','22007','SHP-PAGE-004 impossible SQL timestamp rejected');
select is(pg_temp.page_run('select to_jsonb(p) from public.read_member_shop_reservation_page(now(),''bad-id''::uuid)p')->>'error','22P02','SHP-PAGE-004 malformed SQL UUID rejected');

insert into held_page_result values('initial',pg_temp.page_read());
select is((select result->>'error' from held_page_result where k='initial'),null::text,'SHP-PAGE-001 own initial success');
select is((select jsonb_array_length(result->'value'->'active_reservations') from held_page_result where k='initial'),5,'SHP-PAGE-002 all five active holds');
select is((select jsonb_array_length(result->'value'->'history') from held_page_result where k='initial'),3,'SHP-PAGE-002 history three, probe hidden');
select is((select pg_temp.page_ids(result->'value'->'active_reservations') from held_page_result where k='initial'),jsonb_build_array(pg_temp.page_u(703),pg_temp.page_u(702),pg_temp.page_u(701),pg_temp.page_u(705),pg_temp.page_u(704)),'SHP-PAGE-003 expiry then created then UUID active order');
select is((select pg_temp.page_ids(result->'value'->'history') from held_page_result where k='initial'),(select jsonb_agg(id order by created_at desc,id desc) from(select id,created_at from held_page_expected order by created_at desc,id desc limit 3)e),'SHP-PAGE-003 independent exact initial total order');
select is((select (result->'value'->>'next_after_id')::uuid from held_page_result where k='initial'),(select id from held_page_expected order by created_at desc,id desc offset 2 limit 1),'SHP-PAGE-003 cursor last returned ID');
select is((select (result->'value'->>'next_after_created_at')::timestamptz from held_page_result where k='initial'),(select created_at from held_page_expected order by created_at desc,id desc offset 2 limit 1),'SHP-PAGE-003 cursor exact microsecond timestamp');
select ok((select (result->'value'->>'next_after_created_at') ~ '12347(0)?[+Z]' from held_page_result where k='initial'),'SHP-PAGE-003 cursor text keeps all significant microseconds');
select ok((select (result->'value'->>'as_of')::timestamptz<=statement_timestamp() from held_page_result where k='initial'),'SHP-PAGE-005 read as_of is never in the future');
select ok((select result->'value'->>'as_of' is not null from held_page_result where k='initial'),'SHP-PAGE-005 as_of present');
select is((select count(*)::integer from held_page_result p cross join jsonb_array_elements(p.result->'value'->'history')h where p.k='initial' and (h->>'reservation_id')::uuid not in(select id from held_page_expected)),0,'SHP-PAGE-001 excludes same/foreign member rows');
select is((select result->'value'->'history'->0->>'state' from held_page_result where k='initial'),'expired','SHP-PAGE-005 derived expiry');
select is((select result->'value'->'history'->0->>'section' from held_page_result where k='initial'),'services','SHP-PAGE-005 stored service kind');
select is((select result->'value'->'history'->0->>'item_name' from held_page_result where k='initial'),'Expired stored service','SHP-PAGE-005 snapshot name retained');
select is((select result->'value'->'history'->1->>'state' from held_page_result where k='initial'),'fulfilled','SHP-PAGE-005 collected state retained');
select is((select result->'value'->'history'->1->>'order_id' from held_page_result where k='initial'),(select result->'value'->>'order_id' from held_page_result where k='fulfilled'),'SHP-PAGE-005 fulfilled ordinary order exposed');
select is((select result->'value'->'history'->2->>'unit_price_paise' from held_page_result where k='initial'),'9007199254740993','SHP-PAGE-005 bigint unit decimal exact');
select is((select result->'value'->'history'->2->>'total_paise' from held_page_result where k='initial'),'90071992547409930','SHP-PAGE-005 quantity total above safe integer decimal exact');
select is((select result->'value'->'history'->2->>'currency' from held_page_result where k='initial'),'INR','SHP-PAGE-005 explicit currency');
select is((select result->'value'->'history'->2->'cancel_reason' from held_page_result where k='initial'),'null'::jsonb,'SHP-PAGE-005 member cancel reason hidden');
select is((select result->'value'->'active_reservations'->2->'terms_changed' from held_page_result where k='initial'),'true'::jsonb,'SHP-PAGE-005 open changed quote true');
select is((select result->'value'->'history'->2->'terms_changed' from held_page_result where k='initial'),'false'::jsonb,'SHP-PAGE-005 terminal changed quote false');
select is((select result->'value'->'active_reservations'->0->'order_id' from held_page_result where k='initial'),'null'::jsonb,'SHP-PAGE-005 unfulfilled order hidden');
select is((select array_agg(key order by key)::text from held_page_result p cross join jsonb_object_keys(p.result->'value'->'history'->0)key where p.k='initial'),'{cancel_reason,created_at,currency,expires_at,image_asset_id,item_id,item_name,order_id,quantity,reservation_id,section,state,terms_changed,total_paise,unit_price_paise}','SHP-PAGE-004 opaque safe projection only');
select is((select result->'value'->'history'->0->'image_asset_id' from held_page_result where k='initial'),'null'::jsonb,'SHP-PAGE-005 no unconfirmed product image exposure');
select is((select result->'value'->'history'->2->>'image_asset_id' from held_page_result where k='initial'),pg_temp.page_u(2801)::text,'SHP-PAGE-005 history exposes confirmed current product image ID');
select is((select result->'value'->'active_reservations'->2->>'image_asset_id' from held_page_result where k='initial'),pg_temp.page_u(2801)::text,'SHP-PAGE-005 active exposes confirmed current product image ID');

create function pg_temp.page_walk() returns jsonb language plpgsql as $$
declare reply jsonb; rows jsonb:='[]'; sizes jsonb:='[]'; active_sizes jsonb:='[]'; after_time timestamptz; after_id uuid; safety integer:=0;
begin
 loop
  reply:=pg_temp.page_read(after_time,after_id);
  if reply ? 'error' then return reply; end if;
  rows:=rows || (reply->'value'->'history'); sizes:=sizes || jsonb_build_array(jsonb_array_length(reply->'value'->'history'));
  active_sizes:=active_sizes || jsonb_build_array(jsonb_array_length(reply->'value'->'active_reservations'));
  after_time:=(reply->'value'->>'next_after_created_at')::timestamptz; after_id:=(reply->'value'->>'next_after_id')::uuid;
  exit when after_time is null and after_id is null;
  safety:=safety+1; if safety>20 then return jsonb_build_object('error','cursor_loop'); end if;
 end loop;
 return jsonb_build_object('rows',rows,'sizes',sizes,'active_sizes',active_sizes,'last',reply->'value');
end $$;
insert into held_page_result values('walk',pg_temp.page_walk());
select is((select result->>'error' from held_page_result where k='walk'),null::text,'SHP-PAGE-002 complete history traversal succeeds');
select is((select pg_temp.page_ids(result->'rows') from held_page_result where k='walk'),(select jsonb_agg(id order by created_at desc,id desc) from held_page_expected),'SHP-PAGE-003 all sixty-three exact order no skips');
select is((select count(distinct x->>'reservation_id')::integer from held_page_result p cross join jsonb_array_elements(p.result->'rows')x where k='walk'),63,'SHP-PAGE-003 traversal never duplicates');
select is((select result->'sizes' from held_page_result where k='walk'),'[3,5,5,5,5,5,5,5,5,5,5,5,5]'::jsonb,'SHP-PAGE-002 three then five with full terminal page');
select is((select result->'active_sizes' from held_page_result where k='walk'),'[5,0,0,0,0,0,0,0,0,0,0,0,0]'::jsonb,'SHP-PAGE-002 no active reread during continuation');
select is((select result->'last'->'next_after_created_at' from held_page_result where k='walk'),'null'::jsonb,'SHP-PAGE-003 full final time cursor absent');
select is((select result->'last'->'next_after_id' from held_page_result where k='walk'),'null'::jsonb,'SHP-PAGE-003 full final UUID cursor absent');
select is((select count(*)::integer from held_page_result p cross join jsonb_array_elements(p.result->'rows')x where k='walk' and x->>'cancel_reason' is not null and x->>'state'<>'cancelled_by_gym'),0,'SHP-PAGE-005 reasons only gym cancellations');
select is((select count(*)::integer from held_page_result p cross join jsonb_array_elements(p.result->'rows')x where k='walk' and x->>'state'='cancelled_by_gym' and x->>'cancel_reason'='Exact reason from gym'),15,'SHP-PAGE-005 gym reasons retained exactly');

insert into held_page_result values('foreign-cursor',pg_temp.page_read('2026-02-01 01:00:00+00',pg_temp.page_u(1503)));
select is((select pg_temp.page_ids(result->'value'->'history') from held_page_result where k='foreign-cursor'),(select jsonb_agg(id order by created_at desc,id desc) from(select id,created_at from held_page_expected order by created_at desc,id desc limit 5)e),'SHP-PAGE-001 cursor never selects foreign identity');
select is((select result->'value'->'active_reservations' from held_page_result where k='foreign-cursor'),'[]'::jsonb,'SHP-PAGE-002 valid foreign pair remains continuation');
insert into held_page_result values('beyond',pg_temp.page_read('1900-01-01 00:00:00+00',pg_temp.page_u(1)));
select is((select result->'value'->'history' from held_page_result where k='beyond'),'[]'::jsonb,'SHP-PAGE-003 beyond history empty');
select is((select result->'value'->'next_after_id' from held_page_result where k='beyond'),'null'::jsonb,'SHP-PAGE-003 empty continuation terminal');
insert into held_page_result values('empty',pg_temp.page_read(null,null,pg_temp.page_claim(4)));
select is((select result->'value'->'history' from held_page_result where k='empty'),'[]'::jsonb,'SHP-PAGE-002 empty initial history');
select is((select result->'value'->'active_reservations' from held_page_result where k='empty'),'[]'::jsonb,'SHP-PAGE-002 empty initial active');
select is((select result->'value'->'next_after_id' from held_page_result where k='empty'),'null'::jsonb,'SHP-PAGE-003 empty initial terminal');
insert into held_page_result values('five-only',pg_temp.page_read(null,null,pg_temp.page_claim(5)));
select is((select jsonb_array_length(result->'value'->'active_reservations') from held_page_result where k='five-only'),5,'SHP-PAGE-002 five active only visible transport');
select is((select result->'value'->'history' from held_page_result where k='five-only'),'[]'::jsonb,'SHP-PAGE-002 five active only no history');
select is((select result->'value'->'next_after_id' from held_page_result where k='five-only'),'null'::jsonb,'SHP-PAGE-002 active-only no continuation');
select ok(pg_temp.page_read(null,null,pg_temp.page_claim(6)) ? 'error','SHP-PAGE-002 six-active anomaly refuses instead of dropping hold');

create function pg_temp.page_boundary() returns jsonb language plpgsql as $$
declare answer jsonb;
begin
 insert into public.shop_reservations(id,tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,created_at,expires_at)
 select pg_temp.page_u(2700+n),pg_temp.page_u(1),pg_temp.page_u(107),p.id,'Expiry boundary','product',1,p.quote_version,p.price_paise,statement_timestamp()-interval '1 day',statement_timestamp()+n*interval '1 microsecond'
 from generate_series(-1,1)n join public.addon_products p on p.id=pg_temp.page_u(402+n);
 answer:=pg_temp.page_read(null,null,pg_temp.page_claim(7));
 return answer;
end $$;
insert into held_page_result values('boundary',pg_temp.page_boundary());
select is((select pg_temp.page_ids(result->'value'->'active_reservations') from held_page_result where k='boundary'),jsonb_build_array(pg_temp.page_u(2701)),'SHP-PAGE-005 one microsecond future stays active');
select is((select pg_temp.page_ids(result->'value'->'history') from held_page_result where k='boundary'),jsonb_build_array(pg_temp.page_u(2700),pg_temp.page_u(2699)),'SHP-PAGE-003 expiry equality and one microsecond past history');
select is((select result->'value'->'history'->0->>'state' from held_page_result where k='boundary'),'expired','SHP-PAGE-005 exact equality is expired');
select is((select result->'value'->'history'->1->>'state' from held_page_result where k='boundary'),'expired','SHP-PAGE-005 past expired');
select ok((select (result->'value'->>'as_of')::timestamptz=(select expires_at from public.shop_reservations where id=pg_temp.page_u(2700)) from held_page_result where k='boundary'),'SHP-PAGE-005 one authoritative boundary statement timestamp');

-- Snapshot excludes the independently added boundary rows but includes all read
-- facts and financial tables, detecting accidental expiry or audit writes.
select is((select result->'value'->'reservation' from held_page_result where k='before'),(select jsonb_agg(to_jsonb(r) order by id) from public.shop_reservations r where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2)) and id not in(pg_temp.page_u(2699),pg_temp.page_u(2700),pg_temp.page_u(2701))),'SHP-PAGE-005 reservation facts unchanged by every page/refusal');
select is((select result->'value'->part from held_page_result where k='before'),case when part='audit' then (select jsonb_agg(to_jsonb(a) order by id) from public.audit_log a where tenant_id in(pg_temp.page_u(1),pg_temp.page_u(2)) and id not in(select id from held_page_fixture_audit)) else pg_temp.page_snapshot()->part end,'SHP-PAGE-005 no read side effect on '||part) from unnest(array['product','order','payment','receipt','audit'])part;
insert into held_page_result values('legacy',pg_temp.page_run('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from public.read_member_shop_reservations()r'));
select is((select result->>'error' from held_page_result where k='legacy'),null::text,'SHP-PAGE-009 legacy no-argument read remains valid');
select is((select jsonb_array_length(result->'value') from held_page_result where k='legacy'),50,'SHP-PAGE-009 legacy fifty cap unchanged');
select is((select array_agg(key order by key)::text from held_page_result p cross join jsonb_object_keys(p.result->'value'->0)key where p.k='legacy'),'{cancel_reason,created_at,currency,expires_at,image_asset_id,item_id,item_name,order_id,quantity,reservation_id,section,state,terms_changed,total_paise,unit_price_paise}','SHP-PAGE-009 legacy shape unchanged');

select * from finish();
rollback;
