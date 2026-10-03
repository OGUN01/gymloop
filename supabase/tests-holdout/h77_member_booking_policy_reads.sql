-- Independent holdout from frozen public declarations only. No source or visible tests read.
begin;
set local role postgres;
set local search_path to public,extensions;
select plan(137);
create function pg_temp.u(n integer)returns uuid language sql immutable as $$select ('77900000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid$$;
create function pg_temp.mc(n integer default 100)returns text language sql as $$select jsonb_build_object('sub',pg_temp.u(1000+n),'role','authenticated','app_role','member','tenant_id',pg_temp.u(case when n=110 then 2 else 1 end),'member_id',pg_temp.u(n))::text$$;
create function pg_temp.run(q text,c text default pg_temp.mc(),r text default 'authenticated')returns jsonb language plpgsql as $$declare v jsonb;begin perform set_config('request.jwt.claims',coalesce(c,''),true);execute format('set local role %I',r);begin execute q into v;exception when others then v:=jsonb_build_object('error',sqlstate);end;set local role postgres;perform set_config('request.jwt.claims','',true);return coalesce(v,'null'::jsonb);end$$;
create function pg_temp.policy(c text default pg_temp.mc(),r text default 'authenticated')returns jsonb language sql as $$select pg_temp.run($q$select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb)from public.read_member_pt_policy()p$q$,c,r)$$;
create function pg_temp.row(n integer,c text default pg_temp.mc())returns jsonb language sql as $$select pg_temp.run(format($q$select to_jsonb(p)from public.read_member_class_schedule(current_date-2,current_date+8)p where session_id=%L$q$,pg_temp.u(n)),c)$$;
insert into public.organizations(id,name,gym_code,status,timezone,currency)values(pg_temp.u(1),'Held policy east','H77POLA','active','Asia/Kolkata','INR'),(pg_temp.u(2),'Held policy west','H77POLB','active','Pacific/Honolulu','INR');
insert into public.organization_settings(tenant_id)values(pg_temp.u(1)),(pg_temp.u(2));
insert into public.branches(id,tenant_id,name,timezone,is_default)values(pg_temp.u(11),pg_temp.u(1),'Home','Asia/Kolkata',true),(pg_temp.u(12),pg_temp.u(1),'Away','Pacific/Kiritimati',false),(pg_temp.u(21),pg_temp.u(2),'Foreign','Pacific/Honolulu',true);
insert into auth.users(id)select pg_temp.u(1000+n)from generate_series(100,110)n union all select pg_temp.u(201);
insert into public.staff(id,user_id,tenant_id,role,full_name,is_active)values(pg_temp.u(201),pg_temp.u(201),pg_temp.u(1),'gym_owner','Held owner',true);
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone,date_of_birth,status)select pg_temp.u(n),case when n=104 then null else pg_temp.u(1000+n)end,pg_temp.u(case when n=110 then 2 else 1 end),pg_temp.u(case when n=110 then 21 else 11 end),'Held secret person '||n,'+919779'||lpad(n::text,6,'0'),date '1990-01-01',case when n=105 then 'blocked'::public.member_status when n=106 then 'cancelled'::public.member_status when n=108 then 'paused'::public.member_status when n=109 then 'expired'::public.member_status else 'active'::public.member_status end from generate_series(100,110)n;
update public.members set erased_at=now()where id=pg_temp.u(107);
insert into public.plans(id,tenant_id,name,duration_days,price_paise,is_active)values(pg_temp.u(300),pg_temp.u(1),'Held live',365,0,true),(pg_temp.u(310),pg_temp.u(2),'Held foreign',365,0,true);
-- Import canonical live memberships; no tested command is bypassed.
set local session_replication_role=replica;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)select pg_temp.u(400+n),pg_temp.u(case when n=110 then 2 else 1 end),pg_temp.u(n),pg_temp.u(case when n=110 then 310 else 300 end),'active',current_date-30,current_date+30,0 from generate_series(100,110)n where n<>102;
set local session_replication_role=origin;
insert into public.services(id,tenant_id,name,default_duration_minutes,default_capacity,is_active)values(pg_temp.u(600),pg_temp.u(1),'Held live service',60,5,true),(pg_temp.u(601),pg_temp.u(1),'Held inactive service',60,5,false),(pg_temp.u(610),pg_temp.u(2),'Held foreign service',60,5,true);
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,status,cancelled_at,cancel_reason,cancelled_by_staff_id)
select pg_temp.u(n),pg_temp.u(case when n=710 then 2 else 1 end),pg_temp.u(case when n=710 then 610 when n=708 then 601 else 600 end),pg_temp.u(case when n=710 then 21 when n=709 then 12 else 11 end),(x.s at time zone case when n=710 then 'Pacific/Honolulu'when n=709 then 'Pacific/Kiritimati'else 'Asia/Kolkata'end)::date,x.s,x.s+interval '1 hour',case when n=701 then 1 else 5 end,case when n=703 then 'cancelled'::public.class_session_status else 'scheduled'::public.class_session_status end,case when n=703 then now()end,case when n=703 then 'Held cancelled' end,case when n=703 then pg_temp.u(201)end
from generate_series(700,711)n cross join lateral(select statement_timestamp()+case when n=702 then interval '-1 hour'else interval '4 days'end+(n-700)*interval '1 minute' s)x;
insert into public.class_bookings(id,tenant_id,session_id,member_id,status,cancelled_at,cancel_reason,marked_at)
select pg_temp.u(2000+n),pg_temp.u(1),pg_temp.u(n),pg_temp.u(case when n=701 then 101 else 100 end),case n when 703 then 'session_cancelled'::public.booking_status when 704 then 'attended'::public.booking_status when 705 then 'no_show'::public.booking_status when 707 then 'cancelled_by_gym'::public.booking_status when 708 then 'cancelled_by_member'::public.booking_status when 711 then 'cancelled_by_member'::public.booking_status else 'booked'::public.booking_status end,case when n in(703,707,708,711)then now()end,case when n=707 then 'Held desk cancellation'end,case when n in(704,705)then now()end
from unnest(array[701,703,704,705,706,707,708,711])n;
select ok(to_regprocedure('public.read_member_pt_policy()')is not null,'PT policy signature exists without selectors');
select is((select pg_get_function_result(p.oid)from pg_proc p where p.oid=to_regprocedure('public.read_member_pt_policy()')),'TABLE(cancel_window_hours integer, late_cancel_consumes_session boolean)','PT exact two output columns and types');
select ok((select p.prosecdef and p.provolatile='s' and p.proowner='postgres'::regrole and 'search_path=""'=any(p.proconfig)from pg_proc p where p.oid=to_regprocedure('public.read_member_pt_policy()')),'PT stable postgres definer empty path');
select ok((select p.prosecdef and p.provolatile='s' and p.proowner='postgres'::regrole and 'search_path=""'=any(p.proconfig)from pg_proc p where p.oid='public.read_member_class_schedule(date,date)'::regprocedure),'CLS unchanged stable postgres definer empty path');
select is(has_function_privilege('authenticated',to_regprocedure('public.read_member_pt_policy()'),'EXECUTE'),true ,'PT execute authenticated exact');
select is(has_function_privilege('anon',to_regprocedure('public.read_member_pt_policy()'),'EXECUTE'),false ,'PT execute anon exact');
select is(has_function_privilege('service_role',to_regprocedure('public.read_member_pt_policy()'),'EXECUTE'),false ,'PT execute service_role exact');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a where p.oid=to_regprocedure('public.read_member_pt_policy()')and a.grantee=0 and a.privilege_type='EXECUTE'),'PT no PUBLIC execute');
select ok(not has_function_privilege('authenticated','app.pt_member_actor()','EXECUTE'),'Private pt_member_actor() no authenticated grant');
select ok(not has_function_privilege('anon','app.pt_member_actor()','EXECUTE'),'Private pt_member_actor() no anon grant');
select ok(not has_function_privilege('service_role','app.pt_member_actor()','EXECUTE'),'Private pt_member_actor() no service_role grant');
select ok(not has_function_privilege('authenticated','app.class_member_actor()','EXECUTE'),'Private class_member_actor() no authenticated grant');
select ok(not has_function_privilege('anon','app.class_member_actor()','EXECUTE'),'Private class_member_actor() no anon grant');
select ok(not has_function_privilege('service_role','app.class_member_actor()','EXECUTE'),'Private class_member_actor() no service_role grant');
select is(pg_temp.policy(),'[{"cancel_window_hours":24,"late_cancel_consumes_session":true}]'::jsonb,'PT default current exact projection');
select is(pg_temp.row(700)->>'availability','open','CLS unbooked available row');
select is((pg_temp.row(700)->>'cancel_by')::timestamptz,(select starts_at-interval '2 hours'from public.class_sessions where id=pg_temp.u(700)),'CLS unbooked authoritative default deadline');
select is((pg_temp.row(700)->>'can_cancel')::boolean,false,'CLS prebooking deadline never admits cancellation');
select is(pg_temp.row(700)->'my_booking_id','null'::jsonb,'CLS other rows never become own booking');
update public.organization_settings set class_cancel_window_hours=0,pt_cancel_window_hours=0,pt_late_cancel_consumes_session=false where tenant_id=pg_temp.u(1);
select is((pg_temp.row(700)->>'cancel_by')::timestamptz,(select starts_at from public.class_sessions where id=pg_temp.u(700)),'CLS zero window gives exact start');
select is((pg_temp.row(706)->>'cancel_by')::timestamptz,(select starts_at from public.class_sessions where id=pg_temp.u(706)),'CLS booked zero deadline preserved');
select is(pg_temp.policy(),'[{"cancel_window_hours":0,"late_cancel_consumes_session":false}]'::jsonb,'PT current zero false pair not defaults');
update public.organization_settings set class_cancel_window_hours=168,pt_cancel_window_hours=168,pt_late_cancel_consumes_session=true where tenant_id=pg_temp.u(1);
update public.organization_settings set pt_cancel_window_hours=7,pt_late_cancel_consumes_session=false where tenant_id=pg_temp.u(2);
select is((pg_temp.row(700)->>'cancel_by')::timestamptz,(select starts_at-interval '168 hours'from public.class_sessions where id=pg_temp.u(700)),'CLS refreshed max window prebooking');
select is((pg_temp.row(706)->>'cancel_by')::timestamptz,(select starts_at-interval '168 hours'from public.class_sessions where id=pg_temp.u(706)),'CLS existing booked deadline stays current');
select is((pg_temp.row(706)->>'can_cancel')::boolean,false,'CLS existing booked expired cutoff preserved');
select is(pg_temp.policy(),'[{"cancel_window_hours":168,"late_cancel_consumes_session":true}]'::jsonb,'PT refreshed max current pair');
select is(pg_temp.policy(pg_temp.mc(110)),'[{"cancel_window_hours":7,"late_cancel_consumes_session":false}]'::jsonb,'PT foreign real caller sees only own pair');
select is(pg_temp.row(701)->>'availability','full','CLS availability boundary 701');
select is(pg_temp.row(701)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 701');
select is((pg_temp.row(701)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 701');
select is(pg_temp.row(702)->>'availability','closed','CLS availability boundary 702');
select is(pg_temp.row(702)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 702');
select is((pg_temp.row(702)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 702');
select is(pg_temp.row(703)->>'availability','cancelled','CLS availability boundary 703');
select is(pg_temp.row(703)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 703');
select is((pg_temp.row(703)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 703');
select is(pg_temp.row(704)->>'availability','booked','CLS availability boundary 704');
select is(pg_temp.row(704)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 704');
select is((pg_temp.row(704)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 704');
select is(pg_temp.row(705)->>'availability','booked','CLS availability boundary 705');
select is(pg_temp.row(705)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 705');
select is((pg_temp.row(705)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 705');
select is(pg_temp.row(707)->>'availability','closed','CLS availability boundary 707');
select is(pg_temp.row(707)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 707');
select is((pg_temp.row(707)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 707');
select is(pg_temp.row(708)->>'availability','closed','CLS availability boundary 708');
select is(pg_temp.row(708)->'cancel_by','null'::jsonb,'CLS nonopen nonbooked deadline null 708');
select is((pg_temp.row(708)->>'can_cancel')::boolean,false,'CLS cancellation unchanged 708');
select is(pg_temp.row(700,pg_temp.mc(102))->>'availability','membership_not_live','CLS member without membership not open');
select is(pg_temp.row(700,pg_temp.mc(102))->'cancel_by','null'::jsonb,'CLS membership refusal no prebooking deadline');
select is(pg_temp.row(709),'null'::jsonb,'CLS home branch restriction preserved');
select is(pg_temp.row(710),'null'::jsonb,'CLS foreign session restriction preserved');
select is(pg_temp.row(711)->>'availability','open','CLS cancelled-by-member can reopen');
select is((pg_temp.row(711)->>'cancel_by')::timestamptz,(select starts_at-interval '168 hours'from public.class_sessions where id=pg_temp.u(711)),'CLS reopened availability gets authoritative deadline');
select is((pg_temp.row(711)->>'can_cancel')::boolean,false,'CLS reopened unbooked cancellation stays false');
select is(pg_temp.policy(pg_temp.mc(108)),'[{"cancel_window_hours":168,"late_cancel_consumes_session":true}]'::jsonb,'PT valid nonblocked status 108 allowed');
select is(pg_temp.policy(pg_temp.mc(109)),'[{"cancel_window_hours":168,"late_cancel_consumes_session":true}]'::jsonb,'PT valid nonblocked status 109 allowed');
select is(pg_temp.policy('{}')->>'error','42501','PT complete actor refuses empty');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r','{}')->>'error','42501','CLS actor before invalid window empty');
select is(pg_temp.policy((pg_temp.mc()::jsonb-'sub')::text)->>'error','42501','PT complete actor refuses missing subject');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb-'sub')::text)->>'error','42501','CLS actor before invalid window missing subject');
select is(pg_temp.policy((pg_temp.mc()::jsonb-'tenant_id')::text)->>'error','42501','PT complete actor refuses missing tenant');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb-'tenant_id')::text)->>'error','42501','CLS actor before invalid window missing tenant');
select is(pg_temp.policy((pg_temp.mc()::jsonb-'member_id')::text)->>'error','42501','PT complete actor refuses missing member');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb-'member_id')::text)->>'error','42501','CLS actor before invalid window missing member');
select is(pg_temp.policy((pg_temp.mc()::jsonb-'app_role')::text)->>'error','42501','PT complete actor refuses missing app role');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb-'app_role')::text)->>'error','42501','CLS actor before invalid window missing app role');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('tenant_id','bad'))::text)->>'error','42501','PT complete actor refuses malformed tenant');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('tenant_id','bad'))::text)->>'error','42501','CLS actor before invalid window malformed tenant');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('member_id','bad'))::text)->>'error','42501','PT complete actor refuses malformed member');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('member_id','bad'))::text)->>'error','42501','CLS actor before invalid window malformed member');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('sub','bad'))::text)->>'error','42501','PT complete actor refuses malformed subject');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('sub','bad'))::text)->>'error','42501','CLS actor before invalid window malformed subject');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('staff_id',pg_temp.u(201)))::text)->>'error','42501','PT complete actor refuses mixed staff');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('staff_id',pg_temp.u(201)))::text)->>'error','42501','CLS actor before invalid window mixed staff');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('staff_id','bad'))::text)->>'error','42501','PT complete actor refuses malformed mixed staff');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('staff_id','bad'))::text)->>'error','42501','CLS actor before invalid window malformed mixed staff');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','PT complete actor refuses impersonated');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(999)))::text)->>'error','42501','CLS actor before invalid window impersonated');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id','bad'))::text)->>'error','42501','PT complete actor refuses malformed impersonation');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id','bad'))::text)->>'error','42501','CLS actor before invalid window malformed impersonation');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(101)))::text)->>'error','42501','PT complete actor refuses spoof other member');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(101)))::text)->>'error','42501','CLS actor before invalid window spoof other member');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('sub',pg_temp.u(1101)))::text)->>'error','42501','PT complete actor refuses spoof other user');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('sub',pg_temp.u(1101)))::text)->>'error','42501','CLS actor before invalid window spoof other user');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','PT complete actor refuses foreign tenant own member');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(2)))::text)->>'error','42501','CLS actor before invalid window foreign tenant own member');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(110)))::text)->>'error','42501','PT complete actor refuses foreign member own user');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(110)))::text)->>'error','42501','CLS actor before invalid window foreign member own user');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(999)))::text)->>'error','42501','PT complete actor refuses unknown member');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('member_id',pg_temp.u(999)))::text)->>'error','42501','CLS actor before invalid window unknown member');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(999)))::text)->>'error','42501','PT complete actor refuses unknown tenant');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('tenant_id',pg_temp.u(999)))::text)->>'error','42501','CLS actor before invalid window unknown tenant');
select is(pg_temp.policy(pg_temp.mc(104))->>'error','42501','PT complete actor refuses unbound');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',pg_temp.mc(104))->>'error','42501','CLS actor before invalid window unbound');
select is(pg_temp.policy(pg_temp.mc(105))->>'error','42501','PT complete actor refuses blocked');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',pg_temp.mc(105))->>'error','42501','CLS actor before invalid window blocked');
select is(pg_temp.policy(pg_temp.mc(106))->>'error','42501','PT complete actor refuses cancelled');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',pg_temp.mc(106))->>'error','42501','CLS actor before invalid window cancelled');
select is(pg_temp.policy(pg_temp.mc(107))->>'error','42501','PT complete actor refuses erased');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',pg_temp.mc(107))->>'error','42501','CLS actor before invalid window erased');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','gym_owner'))::text)->>'error','42501','PT complete actor refuses gym_owner');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','gym_owner'))::text)->>'error','42501','CLS actor before invalid window gym_owner');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','gym_manager'))::text)->>'error','42501','PT complete actor refuses gym_manager');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','gym_manager'))::text)->>'error','42501','CLS actor before invalid window gym_manager');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','front_desk'))::text)->>'error','42501','PT complete actor refuses front_desk');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','front_desk'))::text)->>'error','42501','CLS actor before invalid window front_desk');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','trainer'))::text)->>'error','42501','PT complete actor refuses trainer');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','trainer'))::text)->>'error','42501','CLS actor before invalid window trainer');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','super_admin'))::text)->>'error','42501','PT complete actor refuses super_admin');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','super_admin'))::text)->>'error','42501','CLS actor before invalid window super_admin');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','platform_support'))::text)->>'error','42501','PT complete actor refuses platform_support');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','platform_support'))::text)->>'error','42501','CLS actor before invalid window platform_support');
select is(pg_temp.policy((pg_temp.mc()::jsonb||jsonb_build_object('app_role','unknown'))::text)->>'error','42501','PT complete actor refuses unknown');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r',(pg_temp.mc()::jsonb||jsonb_build_object('app_role','unknown'))::text)->>'error','42501','CLS actor before invalid window unknown');
select is(pg_temp.run('select to_jsonb(r)from public.read_member_class_schedule(null,null)r')->>'error','22023','CLS valid actor still validates window');
select is(pg_temp.policy(pg_temp.mc(),'anon')->>'error','42501','PT anon execution denied even with member claims');
select is(pg_temp.policy(pg_temp.mc(),'service_role')->>'error','42501','PT credential role execution denied even with member claims');
select is(pg_temp.run('select to_jsonb(count(*))from public.organization_settings where tenant_id=pg_temp.u(1)'),'0'::jsonb,'PT new safe RPC does not grant member settings SELECT');
select is(pg_temp.run('select to_jsonb(app.pt_member_actor())')->>'error','42501','PT member cannot directly execute private actor');
delete from public.organization_settings where tenant_id=pg_temp.u(1);
select is(pg_temp.policy(),'[]'::jsonb,'PT missing own settings has no fabricated policy');
select is(pg_temp.policy((pg_temp.mc()::jsonb-'sub')::text)->>'error','42501','PT missing settings does not bypass actor first');
select is((pg_temp.row(700)->>'cancel_by')::timestamptz,(select starts_at-interval '2 hours'from public.class_sessions where id=pg_temp.u(700)),'CLS missing settings authoritative default 2');
select is((pg_temp.row(706)->>'cancel_by')::timestamptz,(select starts_at-interval '2 hours'from public.class_sessions where id=pg_temp.u(706)),'CLS booked missing settings retains default');
insert into public.organization_settings(tenant_id,pt_cancel_window_hours,pt_late_cancel_consumes_session)values(pg_temp.u(1),37,false);
select is(pg_temp.policy(),'[{"cancel_window_hours":37,"late_cancel_consumes_session":false}]'::jsonb,'PT subsequent read sees recreated current exact row');
update public.organizations set status='pending_approval'where id=pg_temp.u(1);
select is(pg_temp.policy()->>'error','42501','PT ineligible gym pending_approval refused');
update public.organizations set status='suspended'where id=pg_temp.u(1);
select is(pg_temp.policy()->>'error','42501','PT ineligible gym suspended refused');
update public.organizations set status='closed'where id=pg_temp.u(1);
select is(pg_temp.policy()->>'error','42501','PT ineligible gym closed refused');
update public.organizations set status='trial',trial_ends_at=statement_timestamp()-interval '1 day'where id=pg_temp.u(1);
select is(pg_temp.policy()->>'error','42501','PT expired trial refused');
update public.organizations set trial_ends_at=statement_timestamp()+interval '1 day'where id=pg_temp.u(1);
select is(pg_temp.policy(),'[{"cancel_window_hours":37,"late_cancel_consumes_session":false}]'::jsonb,'PT live trial allowed');
update public.organizations set status='active'where id=pg_temp.u(1);
create temp table h77_before as
select 'settings't,to_jsonb(x)facts from public.organization_settings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'sessions',to_jsonb(x)from public.class_sessions x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'bookings',to_jsonb(x)from public.class_bookings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'members',to_jsonb(x)from public.members x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'pt_sessions',to_jsonb(x)from public.pt_sessions x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'orders',to_jsonb(x)from public.addon_orders x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'pt_cancellations',to_jsonb(x)from public.pt_cancellations x where tenant_id in(pg_temp.u(1),pg_temp.u(2));
create temp table h77_marks as select(select count(*)from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2)))audits,(select count(*)from public.notifications where tenant_id in(pg_temp.u(1),pg_temp.u(2)))notices,(select count(*)from pg_locks where pid=pg_backend_pid()and locktype='advisory')advisories,(select count(*)from pg_locks where pid=pg_backend_pid()and mode='RowShareLock'and relation in('public.organization_settings'::regclass,'public.class_sessions'::regclass,'public.class_bookings'::regclass,'public.members'::regclass))rowshares;
select is(pg_temp.policy(),'[{"cancel_window_hours":37,"late_cancel_consumes_session":false}]'::jsonb,'PT successful read under no effect observation');
select is(pg_temp.row(700)->>'availability','open','CLS successful read under no effect observation');
select is(pg_temp.policy(pg_temp.mc(105))->>'error','42501','PT refusal under no effect observation');
select ok((select audits=(select count(*)from public.audit_log where tenant_id in(pg_temp.u(1),pg_temp.u(2)))and notices=(select count(*)from public.notifications where tenant_id in(pg_temp.u(1),pg_temp.u(2)))from h77_marks),'Policy reads and refusals append no audit or notice');
select ok((select advisories=(select count(*)from pg_locks where pid=pg_backend_pid()and locktype='advisory')from h77_marks),'Policy reads acquire no advisory locks');
select ok((select rowshares=(select count(*)from pg_locks where pid=pg_backend_pid()and mode='RowShareLock'and relation in('public.organization_settings'::regclass,'public.class_sessions'::regclass,'public.class_bookings'::regclass,'public.members'::regclass))from h77_marks),'Policy reads acquire no additional row locking table mode');
select is((select jsonb_agg(jsonb_build_object('t',t,'facts',facts)order by t,facts::text)from h77_before),(select jsonb_agg(jsonb_build_object('t',t,'facts',facts)order by t,facts::text)from(
select 'settings't,to_jsonb(x)facts from public.organization_settings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'sessions',to_jsonb(x)from public.class_sessions x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'bookings',to_jsonb(x)from public.class_bookings x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'members',to_jsonb(x)from public.members x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'pt_sessions',to_jsonb(x)from public.pt_sessions x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'orders',to_jsonb(x)from public.addon_orders x where tenant_id in(pg_temp.u(1),pg_temp.u(2))
union all select 'pt_cancellations',to_jsonb(x)from public.pt_cancellations x where tenant_id in(pg_temp.u(1),pg_temp.u(2)))s),'Policy reads preserve all configuration and booking ledger rows');
select * from finish();
rollback;
