-- Independent boundary holdout; contract and own baseline fixture shapes only.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(53);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('75910000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid$$;
create function pg_temp.sc(n integer default 1) returns text language sql as $$select jsonb_build_object('sub',pg_temp.u(200+n),'role','authenticated','tenant_id',pg_temp.u(1),'staff_id',pg_temp.u(200+n),'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' else 'front_desk' end)::text$$;
create function pg_temp.run(q text,c text default pg_temp.sc(),r text default 'authenticated') returns jsonb language plpgsql as $$declare v jsonb;begin perform set_config('request.jwt.claims',coalesce(c,''),true);execute format('set local role %I',r);begin execute q into v;exception when others then v:=jsonb_build_object('error',sqlstate);end;set local role postgres;perform set_config('request.jwt.claims','',true);return coalesce(v,'null'::jsonb);end$$;
insert into public.organizations(id,name,gym_code,status,timezone,currency)values(pg_temp.u(1),'Boundary gym','H75TBA','active','Pacific/Kiritimati','INR');
insert into public.organization_settings(tenant_id)values(pg_temp.u(1));
insert into public.branches(id,tenant_id,name,timezone,is_default)values(pg_temp.u(11),pg_temp.u(1),'Branch','Pacific/Honolulu',true);
insert into auth.users(id)select pg_temp.u(n)from generate_series(201,203)n;
insert into public.staff(id,user_id,tenant_id,role,full_name,is_active)select pg_temp.u(200+n),pg_temp.u(200+n),pg_temp.u(1),case n when 1 then 'gym_owner'::public.app_role when 2 then 'gym_manager'::public.app_role else 'front_desk'::public.app_role end,'Boundary staff',true from generate_series(1,3)n;
insert into auth.users(id)select pg_temp.u(1000+n)from generate_series(100,107)n;
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone,status)select pg_temp.u(n),pg_temp.u(1000+n),pg_temp.u(1),pg_temp.u(11),'PRIVATE date member '||n,'+919759'||lpad(n::text,6,'0'),'active'from generate_series(100,107)n;
create function pg_temp.mc(n integer) returns text language sql as $$select jsonb_build_object('sub',pg_temp.u(1000+n),'role','authenticated','tenant_id',pg_temp.u(1),'member_id',pg_temp.u(n),'app_role','member')::text$$;
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency)values(pg_temp.u(300),pg_temp.u(1),'Date plan',30,0,'INR');
select set_config('request.jwt.claims',pg_temp.sc(),true);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)select pg_temp.u(400+n),pg_temp.u(1),pg_temp.u(n),pg_temp.u(300),case n when 101 then 'frozen'::public.membership_status when 104 then 'expired'::public.membership_status when 105 then 'pending'::public.membership_status else 'active'::public.membership_status end,case n when 101 then app.gym_today(pg_temp.u(1)) when 102 then app.gym_today(pg_temp.u(1))+1 when 105 then null else app.gym_today(pg_temp.u(1))-29 end,case n when 103 then app.gym_today(pg_temp.u(1))-1 when 105 then null when 102 then app.gym_today(pg_temp.u(1))+30 else app.gym_today(pg_temp.u(1))end,0 from generate_series(100,106)n;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)values(pg_temp.u(900),pg_temp.u(1),pg_temp.u(106),pg_temp.u(300),'expired',app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+30,0);
select set_config('request.jwt.claims','',true);
create temp table results(k text primary key,v jsonb);
grant select on results to authenticated;
insert into results values('live',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('transactional','Boundary live','Date audience body','segment',array['active']::public.member_status[],'live',null,null))$q$));
insert into results values('inverse',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('transactional','Boundary inverse','Date audience body','segment',array['active']::public.member_status[],'not_live',null,null))$q$));
insert into results values('promo',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('promotional','Boundary promo','Date audience body','segment',array['active']::public.member_status[],'live',null,null))$q$));
create function pg_temp.aid(k text)returns uuid language sql as $$select (v#>>'{}')::uuid from results where results.k=$1 and v->>'error'is null$$;
select is(pg_temp.run($q$select to_jsonb(g)from public.publish_announcement(pg_temp.aid('live'))g$q$)->>'audience_count','3','ANC live publish gym-date audience');
select is(pg_temp.run($q$select to_jsonb(g)from public.publish_announcement(pg_temp.aid('inverse'))g$q$)->>'audience_count','5','ANC inverse publish gym-date audience');
select is(pg_temp.run($q$select to_jsonb(g)from public.publish_announcement(pg_temp.aid('promo'))g$q$)->>'audience_count','0','ANC promo publish gym-date audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(100)),'1'::jsonb,'ANC member 100 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(100)),'true'::jsonb,'ANC member 100 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(100)),'0'::jsonb,'ANC member 100 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(100)),'false'::jsonb,'ANC member 100 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(101)),'1'::jsonb,'ANC member 101 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(101)),'true'::jsonb,'ANC member 101 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(101)),'0'::jsonb,'ANC member 101 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(101)),'false'::jsonb,'ANC member 101 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(102)),'0'::jsonb,'ANC member 102 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(102)),'false'::jsonb,'ANC member 102 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(102)),'1'::jsonb,'ANC member 102 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(102)),'true'::jsonb,'ANC member 102 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(103)),'0'::jsonb,'ANC member 103 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(103)),'false'::jsonb,'ANC member 103 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(103)),'1'::jsonb,'ANC member 103 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(103)),'true'::jsonb,'ANC member 103 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(104)),'0'::jsonb,'ANC member 104 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(104)),'false'::jsonb,'ANC member 104 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(104)),'1'::jsonb,'ANC member 104 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(104)),'true'::jsonb,'ANC member 104 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(105)),'0'::jsonb,'ANC member 105 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(105)),'false'::jsonb,'ANC member 105 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(105)),'1'::jsonb,'ANC member 105 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(105)),'true'::jsonb,'ANC member 105 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(106)),'1'::jsonb,'ANC member 106 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(106)),'true'::jsonb,'ANC member 106 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(106)),'0'::jsonb,'ANC member 106 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(106)),'false'::jsonb,'ANC member 106 inverse marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('live')$q$,pg_temp.mc(107)),'0'::jsonb,'ANC member 107 live date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('live'),1))$q$,pg_temp.mc(107)),'false'::jsonb,'ANC member 107 live marker matches audience');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('inverse')$q$,pg_temp.mc(107)),'1'::jsonb,'ANC member 107 inverse date targeting');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('inverse'),1))$q$,pg_temp.mc(107)),'true'::jsonb,'ANC member 107 inverse marker matches audience');
select is(pg_temp.run($q$select public.read_announcement(pg_temp.aid('live'))$q$)->'announcement'->>'audienceCount','3','ANC detail same date audience');
select is(pg_temp.run($q$select public.read_announcement(pg_temp.aid('live'))$q$)->'announcement'->>'readCurrent','3','ANC staff receipts current audience');
select is(pg_temp.run($q$select to_jsonb(audience_count)from public.list_announcements()where announcement_id=pg_temp.aid('inverse')$q$),'5'::jsonb,'ANC staff list inverse count');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.announcement_receipts$q$),'0'::jsonb,'ANC staff cannot enumerate receipts');
select ok(pg_temp.run($q$select public.read_announcement(pg_temp.aid('live'))$q$)::text!~'PRIVATE date member|member_id|memberId|read_at|readAt','ANC staff detail privacy');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('promo'),1))$q$,pg_temp.mc(100)),'false'::jsonb,'ANC date targeting never bypasses marketing consent');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values(pg_temp.u(950),pg_temp.u(1),pg_temp.u(100),'marketing',true,'v1','holdout',clock_timestamp());
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid('promo')$q$,pg_temp.mc(100)),'1'::jsonb,'ANC marketing grant restores qualifying date audience');
select is(pg_temp.run($q$select public.read_announcement(pg_temp.aid('promo'))$q$)->'announcement'->>'audienceCount','1','ANC promotional reach follows consent');
insert into public.organizations(id,name,gym_code,status,timezone,currency)values(pg_temp.u(2),'Opposite gym','H75TBB','active','Pacific/Honolulu','INR');
insert into public.organization_settings(tenant_id)values(pg_temp.u(2));
insert into public.branches(id,tenant_id,name,is_default)values(pg_temp.u(12),pg_temp.u(2),'Opposite',true);
insert into auth.users(id)values(pg_temp.u(205)),(pg_temp.u(1108));
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active)values(pg_temp.u(205),pg_temp.u(205),pg_temp.u(2),pg_temp.u(12),'gym_owner','West owner',true);
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone)values(pg_temp.u(108),pg_temp.u(1108),pg_temp.u(2),pg_temp.u(12),'PRIVATE west','+919759000108');
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency)values(pg_temp.u(301),pg_temp.u(2),'West date plan',30,0,'INR');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(205),'role','authenticated','tenant_id',pg_temp.u(2),'staff_id',pg_temp.u(205),'app_role','gym_owner')::text,true);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)values(pg_temp.u(908),pg_temp.u(2),pg_temp.u(108),pg_temp.u(301),'active',app.gym_today(pg_temp.u(2)),app.gym_today(pg_temp.u(2)),0);
select set_config('request.jwt.claims','',true);
insert into results values('west',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('transactional','West live','West body','segment',array['active']::public.member_status[],'live',null,null))$q$,jsonb_build_object('sub',pg_temp.u(205),'role','authenticated','tenant_id',pg_temp.u(2),'staff_id',pg_temp.u(205),'app_role','gym_owner')::text));
select is(pg_temp.run($q$select to_jsonb(g)from public.publish_announcement(pg_temp.aid('west'))g$q$,jsonb_build_object('sub',pg_temp.u(205),'role','authenticated','tenant_id',pg_temp.u(2),'staff_id',pg_temp.u(205),'app_role','gym_owner')::text)->>'audience_count','1','ANC opposite gym current-day endpoints qualify');
select ok(app.gym_today(pg_temp.u(1))=(statement_timestamp()at time zone 'Pacific/Kiritimati')::date and app.gym_today(pg_temp.u(2))=(statement_timestamp()at time zone 'Pacific/Honolulu')::date and app.gym_today(pg_temp.u(1))=app.gym_today(pg_temp.u(2))+1,'ANC opposite gym days differ independent of server day');
-- Historical compatibility only: suspend exactly the dated-unless-pending CHECK
-- inside a subtransaction. All triggers and all other constraints stay enabled.
-- A sentinel rolls back the import and DDL before results are asserted or any
-- subsequent normal command runs. PL/pgSQL variables retain measured booleans.
create temp table legacy_check_before as
select conname,pg_get_constraintdef(oid)definition,convalidated from pg_constraint
where conrelid='public.memberships'::regclass and conname='memberships_dated_unless_pending_chk';
create temp table legacy_null_results(k integer primary key,v jsonb);
select set_config('request.jwt.claims',pg_temp.sc(),true);
do $$
declare i integer; st public.membership_status; v jsonb; live boolean; inverse boolean; shared boolean; code text; message text;
begin
for i in 1..6 loop
 st:=case when i<=3 then 'active'::public.membership_status else 'frozen'::public.membership_status end;
 v:=null;
 begin
  alter table public.memberships drop constraint memberships_dated_unless_pending_chk;
  insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise)
  values(pg_temp.u(960+i),pg_temp.u(1),pg_temp.u(107),pg_temp.u(300),st,
    case when i in(3,6)then app.gym_today(pg_temp.u(1))else null end,
    case when i in(2,5)then app.gym_today(pg_temp.u(1))else null end,0);
  select exists(select 1 from app.announcement_audience(pg_temp.aid('live'),pg_temp.u(107))) into live;
  select exists(select 1 from app.announcement_audience(pg_temp.aid('inverse'),pg_temp.u(107))) into inverse;
  shared:=app.member_has_live_membership(pg_temp.u(1),pg_temp.u(107),app.gym_today(pg_temp.u(1)));
  v:=jsonb_build_object('live',live,'inverse',inverse,'shared',shared);
  raise exception using errcode='ZH001',message='holdout legacy import rollback sentinel';
 exception
  when sqlstate 'ZH001' then null;
  when others then
   get stacked diagnostics code=returned_sqlstate,message=message_text;
   v:=jsonb_build_object('error',code,'message',message);
 end;
 insert into legacy_null_results values(i,v);
end loop;
end $$;
select set_config('request.jwt.claims','',true);
select is((select v from legacy_null_results where k=1),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical active null-endpoint shape 1 targets live and inverse exactly');
select is((select v from legacy_null_results where k=2),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical active null-endpoint shape 2 targets live and inverse exactly');
select is((select v from legacy_null_results where k=3),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical active null-endpoint shape 3 targets live and inverse exactly');
select is((select v from legacy_null_results where k=4),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical frozen null-endpoint shape 1 targets live and inverse exactly');
select is((select v from legacy_null_results where k=5),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical frozen null-endpoint shape 2 targets live and inverse exactly');
select is((select v from legacy_null_results where k=6),'{"live":true,"inverse":false,"shared":true}'::jsonb,'ANC historical frozen null-endpoint shape 3 targets live and inverse exactly');
select ok((select count(*)=1 from legacy_check_before)and not exists(
 (select conname,definition,convalidated from legacy_check_before except select conname,pg_get_constraintdef(oid),convalidated from pg_constraint where conrelid='public.memberships'::regclass and conname='memberships_dated_unless_pending_chk')
 union all
 (select conname,pg_get_constraintdef(oid),convalidated from pg_constraint where conrelid='public.memberships'::regclass and conname='memberships_dated_unless_pending_chk' except select conname,definition,convalidated from legacy_check_before)
),'ANC exact dated CHECK definition and validation restored after each legacy import');
select is((select count(*)from public.memberships where id in(select pg_temp.u(960+n)from generate_series(1,6)n)),0::bigint,'ANC historical null imports leave no membership row');
select * from finish();
rollback;
