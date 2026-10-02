-- Independent visible PTF database contract, PTF-001..026/032/033.
-- Frozen a66c2cb proposal, waiver/return, expired-pack and MEDIA amendments.
-- No PTF implementation, proposed migration, app suite or holdout was read.
-- Sequential evidence is not a cross-session race proof: see acceptance notes.
-- Post-CI real competing backends must prove same-slot exclusivity, final-budget
-- recount, member booking vs unlocked trainer scheduling, reassign vs booking,
-- duplicate/distinct waivers vs completion/refund/expiry, and a lock wait across
-- gym-local midnight with a fresh validity clock. Advisory locks held here prove
-- key use only, not acquisition order or inter-backend serialization.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(314);

create function pg_temp.gid(n integer) returns uuid language sql immutable as
$$ select ('73000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.claim(r text default 'gym_owner',s integer default 21,m integer default null,u integer default 901,t integer default 1,preview boolean default false) returns void language plpgsql as
$$ begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('role','authenticated','sub',case when u is not null then pg_temp.gid(u) end,'app_role',r,'tenant_id',case when t is not null then pg_temp.gid(t) end,'staff_id',case when s is not null then pg_temp.gid(s) end,'member_id',case when m is not null then pg_temp.gid(m) end,'impersonation_session_id',case when preview then pg_temp.gid(999) end))::text,true); end $$;
-- Always undo a probe, including an unexpectedly successful command.
create function pg_temp.err(q text,details boolean default false) returns text language plpgsql as
$$ declare d text; begin begin execute q; raise exception using errcode='Z7300'; exception when others then if sqlstate='Z7300' then return 'SUCCESS'; end if; get stacked diagnostics d=PG_EXCEPTION_DETAIL; return sqlstate||case when details then ':'||coalesce(d,'') else '' end; end; end $$;
create function pg_temp.slot(day_offset integer,minute integer default 600) returns timestamptz language sql stable as
$$ select (((statement_timestamp() at time zone 'Asia/Kolkata')::date+day_offset)::timestamp at time zone 'Asia/Kolkata') + make_interval(mins=>minute) $$;
grant execute on function pg_temp.gid(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.err(text,boolean),pg_temp.slot(integer,integer) to authenticated,anon,service_role;

-- Exact new vocabulary/projections, fixed RLS and callable boundaries.
select enum_has_labels('public','pt_pack_state',array['live','fully_booked','spent','expired','closed']::name[],'PTF-005: canonical derived pack-state order');
select columns_are('public','trainer_profiles',array['id','tenant_id','staff_id','bio','specialities','photo_asset_id','is_listed','created_at','updated_at']::name[],'PTF-001: exact profile columns');
select columns_are('public','trainer_availability',array['id','tenant_id','staff_id','weekday','start_minute','end_minute','created_at']::name[],'PTF-006: replacement windows have no mutable timestamp');
select columns_are('public','trainer_time_off',array['id','tenant_id','staff_id','starts_on','ends_on','reason','created_by_staff_id','removed_at','removed_by_staff_id','created_at','updated_at']::name[],'PTF-007: exact soft-removal fields');
select columns_are('public','pt_cancellations',array['id','tenant_id','pt_session_id','addon_order_id','member_id','trainer_staff_id','outcome','cancelled_at','cancelled_by_staff_id','window_hours','policy_consumes','was_late','completed_order','consumed','reason','waived_at','waived_by_staff_id','waive_reason','created_at','updated_at']::name[],'PTF-014/016: immutable cause and separate waiver fields');
select ok((select attnotnull and atttypid='boolean'::regtype from pg_attribute where attrelid='public.pt_cancellations'::regclass and attname='completed_order'),'PTF-014: completion provenance is non-null boolean');
select is((select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where a.attrelid='public.pt_cancellations'::regclass and a.attname='completed_order'),'false','PTF-014: old cancellations default to no completion provenance');
select ok(exists(select 1 from pg_constraint where conrelid='public.pt_cancellations'::regclass and conname='pt_cancellations_completed_order_chk' and contype='c'),'PTF-014: named causal implication check exists');
select ok(exists(select 1 from pg_constraint where conrelid='public.trainer_availability'::regclass and conname='trainer_availability_window_overlap_excl' and contype='x'),'PTF-006: database availability overlap backstop exists');
select ok((select confrelid='public.media_assets'::regclass and cardinality(conkey)=2 and cardinality(confkey)=2 from pg_constraint where conrelid='public.trainer_profiles'::regclass and conname='trainer_profiles_tenant_id_photo_asset_id_fkey'),'PTF-002: profile photo FK is tenant composite');
select is_empty($q$with w(n) as(values('trainer_profiles'),('trainer_availability'),('trainer_time_off'),('pt_cancellations')) select n from w where not exists(select 1 from pg_class c join pg_namespace s on s.oid=c.relnamespace where s.nspname='public' and c.relname=w.n and c.relrowsecurity) or not has_table_privilege('authenticated','public.'||n,'SELECT') or has_table_privilege('authenticated','public.'||n,'INSERT,UPDATE,DELETE') or has_table_privilege('anon','public.'||n,'SELECT,INSERT,UPDATE,DELETE')$q$,'PTF-020: all four tables enable RLS with staff SELECT only and no anon privileges');
select policies_are('public','trainer_profiles',array['trainer_profiles_platform_select','trainer_profiles_tenant_select']::name[],'PTF-020: profile has canonical read policies only');
select policies_are('public','trainer_availability',array['trainer_availability_platform_select','trainer_availability_tenant_select']::name[],'PTF-020: availability has canonical read policies only');
select policies_are('public','trainer_time_off',array['trainer_time_off_platform_select','trainer_time_off_tenant_select']::name[],'PTF-020: time off has canonical read policies only');
select policies_are('public','pt_cancellations',array['pt_cancellations_platform_select','pt_cancellations_tenant_select']::name[],'PTF-020: cancellation has canonical read policies only');
select is_empty($q$with w(tab,cols) as(values('trainer_profiles',array['tenant_id','staff_id']),('trainer_availability',array['tenant_id','staff_id','weekday']),('trainer_time_off',array['tenant_id','staff_id','starts_on']),('pt_cancellations',array['tenant_id','trainer_staff_id','cancelled_at']),('pt_cancellations',array['tenant_id','member_id']),('pt_cancellations',array['tenant_id','addon_order_id'])) select tab,cols from w where not exists(select 1 from pg_index i where i.indrelid=to_regclass('public.'||tab) and (select array_agg(a.attname::text order by k.ord) from unnest(i.indkey::smallint[]) with ordinality k(n,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=k.n where k.ord<=cardinality(w.cols))=w.cols)$q$,'PTF-020: tenant/trainer/member/order predicate columns have leading indexes');
select ok(to_regclass('public.audit_log_actor_user_id_occurred_at_pt_booked_idx') is not null,'PTF-012: booking throttle has its named index');
select ok(exists(select 1 from pg_trigger t where t.tgrelid='public.organization_settings'::regclass and t.tgname='organization_settings_guard_pt_policy' and t.tgtype=19 and t.tgfoid=to_regprocedure('app.guard_pt_policy_write()')),'PTF-019: exact BEFORE UPDATE policy guard exists');
select is_empty($q$with w(sig) as(values
('public.read_member_trainers()'),('public.read_member_programmes()'),('public.read_member_pt_packs()'),('public.read_member_pt_sessions(text,integer,timestamptz,uuid)'),('public.read_member_pt_slots(uuid,date,date)'),('public.book_pt_session(uuid,uuid,timestamptz)'),('public.cancel_pt_booking(uuid)'),('public.set_trainer_profile(uuid,text,text[],uuid,boolean)'),('public.set_own_trainer_profile(text,text[])'),('public.set_trainer_availability(uuid,jsonb)'),('public.add_trainer_time_off(uuid,date,date,text)'),('public.remove_trainer_time_off(uuid)'),('public.read_pt_bookings(timestamptz,timestamptz,uuid,public.booking_status,integer,timestamptz,uuid)'),('public.read_pt_packs(uuid,public.pt_pack_state,integer,uuid)'),('public.cancel_pt_session_as_gym(uuid,text)'),('public.waive_pt_forfeit(uuid,text)'),('public.reassign_pt_packs(uuid,uuid,uuid[],text)'),('public.set_pt_policy(integer,boolean,integer)'))
select sig from w where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(w.sig) and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE'))$q$,'PTF-026: all 18 fixed public RPCs are postgres-owned empty-path authenticated definers');
select is_empty($q$with w(sig) as(values('app.pt_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)'),('app.pt_member_actor()'),('app.pt_staff_actor(text[],boolean)'),('app.pt_member_command_ok(uuid,uuid,uuid,text[])'),('app.pt_slot_state(uuid,uuid,timestamptz)'),('app.pt_trainer_key(uuid,uuid)'),('app.pt_booking_status(public.pt_session_status,public.booking_status)'),('app.pt_pack_state(uuid,uuid)'),('app.guard_pt_policy_write()')) select sig from w where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(w.sig) and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE'))$q$,'PTF-026: fixed helpers are private empty-path postgres-owned functions');
select is_empty($q$with w(sig) as(values('public.read_member_trainers()'),('public.read_member_programmes()'),('public.read_member_pt_packs()'),('public.read_member_pt_sessions(text,integer,timestamptz,uuid)'),('public.read_member_pt_slots(uuid,date,date)'),('public.read_pt_bookings(timestamptz,timestamptz,uuid,public.booking_status,integer,timestamptz,uuid)'),('public.read_pt_packs(uuid,public.pt_pack_state,integer,uuid)')) select sig from w where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(w.sig) and p.provolatile='s')$q$,'PTF-026: all seven named public reads are STABLE');
select is_empty($q$with w(sig) as(values('public.book_pt_session(uuid,uuid,timestamptz)'),('public.cancel_pt_booking(uuid)'),('public.set_trainer_profile(uuid,text,text[],uuid,boolean)'),('public.set_own_trainer_profile(text,text[])'),('public.set_trainer_availability(uuid,jsonb)'),('public.add_trainer_time_off(uuid,date,date,text)'),('public.remove_trainer_time_off(uuid)'),('public.cancel_pt_session_as_gym(uuid,text)'),('public.waive_pt_forfeit(uuid,text)'),('public.reassign_pt_packs(uuid,uuid,uuid[],text)'),('public.set_pt_policy(integer,boolean,integer)')) select sig from w where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(w.sig) and p.provolatile='v')$q$,'PTF-026: all eleven named public writers are VOLATILE');
select ok(exists(select 1 from pg_trigger t where t.tgrelid='public.pt_cancellations'::regclass and t.tgname='pt_cancellations_completed_order_immutable' and not t.tgisinternal and t.tgtype=19 and t.tgqual is null and t.tgfoid=to_regprocedure('app.guard_pt_cancellation_completion()') and (select array_agg(k.n order by k.ord) from unnest(t.tgattr::smallint[]) with ordinality k(n,ord))=array[(select attnum from pg_attribute where attrelid='public.pt_cancellations'::regclass and attname='completed_order')]::smallint[]),'PTF-014/026: exact BEFORE ROW UPDATE OF completed_order provenance trigger has no WHEN');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('app.guard_pt_cancellation_completion()') and not p.prosecdef and p.provolatile='v' and p.prorettype='trigger'::regtype and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'PTF-014/026: completion guard is private postgres-owned VOLATILE invoker trigger with empty path and no session/PUBLIC execution');
select is((select proargnames[1+pronargs:cardinality(proargnames)] from pg_proc where oid=to_regprocedure('public.read_member_trainers()')),array['trainer_key','display_name','qualification','bio','specialities','image_asset_id','branch_name','is_profile_listed']::text[],'PTF-003: exact trainer projection contains no staff/contact/key/MIME/ETag');
select is((select proargnames[1+pronargs:cardinality(proargnames)] from pg_proc where oid=to_regprocedure('public.read_member_programmes()')),array['programme_id','trainer_key','trainer_name','name','description','price_paise','currency','gst_rate_bp','session_count','validity_days','trainer_qualification','cancellation_terms']::text[],'PTF-004: exact programme disclosures and paise text projection');
select is((select proargnames[1+pronargs:cardinality(proargnames)] from pg_proc where oid=to_regprocedure('public.read_pt_bookings(timestamptz,timestamptz,uuid,public.booking_status,integer,timestamptz,uuid)')),array['session_id','order_id','member_id','member_name','member_code','trainer_staff_id','trainer_name','starts_at','ends_at','timezone','status','consumed','cancelled_at','sessions_total','sessions_used','sessions_remaining']::text[],'PTF-022: staff bookings have names/codes and no contact fields');
select is(app.pt_trainer_key(pg_temp.gid(1),pg_temp.gid(2)),'b0f1360f-0686-5c81-8076-6bb80756495d'::uuid,'PTF-003/MEDIA: canonical independent pseudonym vector one');
select is(app.pt_trainer_key(pg_temp.gid(1),pg_temp.gid(3)),'4da186b4-1472-ad0c-0fd5-2f778769be1d'::uuid,'PTF-003/MEDIA: canonical independent pseudonym vector two');
select isnt(app.pt_trainer_key(pg_temp.gid(2),pg_temp.gid(2)),app.pt_trainer_key(pg_temp.gid(1),pg_temp.gid(2)),'PTF-003: pseudonym is tenant-bound');

-- Real matching identities, two gyms, branch-local clock and broad validity.
insert into public.organizations(id,name,gym_code,status,timezone,currency) values
(pg_temp.gid(1),'PT Visible A','PT073A','active','Asia/Kolkata','INR'),(pg_temp.gid(2),'PT Visible B','PT073B','active','Asia/Kolkata','INR');
insert into public.organization_settings(tenant_id) values(pg_temp.gid(1)),(pg_temp.gid(2));
insert into public.branches(id,tenant_id,name,is_default,timezone) values
(pg_temp.gid(11),pg_temp.gid(1),'Main',true,'Asia/Kolkata'),(pg_temp.gid(12),pg_temp.gid(2),'Foreign',true,null),(pg_temp.gid(13),pg_temp.gid(1),'Other branch',false,'Pacific/Kiritimati');
insert into auth.users(id) select pg_temp.gid(n) from generate_series(901,911) n;
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active,qualification) values
(pg_temp.gid(21),pg_temp.gid(1),pg_temp.gid(901),pg_temp.gid(11),'gym_owner','Owner',true,null),
(pg_temp.gid(22),pg_temp.gid(1),pg_temp.gid(902),pg_temp.gid(11),'gym_manager','Manager',true,null),
(pg_temp.gid(23),pg_temp.gid(1),pg_temp.gid(903),pg_temp.gid(11),'front_desk','Desk',true,null),
(pg_temp.gid(24),pg_temp.gid(1),pg_temp.gid(904),pg_temp.gid(11),'trainer','Trainer One',true,'Certified One'),
(pg_temp.gid(25),pg_temp.gid(1),pg_temp.gid(905),null,'trainer','Trainer Two',true,'Certified Two'),
(pg_temp.gid(26),pg_temp.gid(2),pg_temp.gid(906),pg_temp.gid(12),'trainer','Foreign Trainer',true,'Foreign credential'),
(pg_temp.gid(27),pg_temp.gid(1),null,pg_temp.gid(11),'trainer','Inactive Trainer',true,'Old credential'),
(pg_temp.gid(28),pg_temp.gid(1),null,pg_temp.gid(13),'trainer','Other Branch Trainer',true,'Other credential');
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status) values
(pg_temp.gid(31),pg_temp.gid(1),pg_temp.gid(907),pg_temp.gid(11),'Member One','+917300000031','active'),
(pg_temp.gid(32),pg_temp.gid(1),pg_temp.gid(908),pg_temp.gid(11),'Member Two','+917300000032','active'),
(pg_temp.gid(33),pg_temp.gid(2),pg_temp.gid(909),pg_temp.gid(12),'Foreign Member','+917300000033','active');
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.gid(41),pg_temp.gid(1),'Membership',120,10000),(pg_temp.gid(42),pg_temp.gid(2),'Foreign membership',120,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) values
(pg_temp.gid(51),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(41),'active',app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+90,10000),
(pg_temp.gid(52),pg_temp.gid(1),pg_temp.gid(32),pg_temp.gid(41),'frozen',app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+90,10000),
(pg_temp.gid(53),pg_temp.gid(2),pg_temp.gid(33),pg_temp.gid(42),'active',app.gym_today(pg_temp.gid(2))-2,app.gym_today(pg_temp.gid(2))+90,10000);
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,gst_rate_bp,validity_days,session_count,trainer_staff_id,trainer_qualification,cancellation_terms,is_active) values
(pg_temp.gid(101),pg_temp.gid(1),'pt_package','Precise programme','Complete disclosure',9007199254740993,'INR',1800,60,4,pg_temp.gid(24),'Disclosed qualification','Current cancellation terms',true),
(pg_temp.gid(102),pg_temp.gid(1),'pt_package','Second programme','Second disclosure',0,'INR',0,60,2,pg_temp.gid(25),'Second qualification','Second terms',true),
(pg_temp.gid(103),pg_temp.gid(2),'pt_package','Foreign programme','Foreign disclosure',0,'INR',0,60,2,pg_temp.gid(26),'Foreign qualification','Foreign terms',true),
(pg_temp.gid(104),pg_temp.gid(1),'pt_package','Inactive programme',null,0,'INR',0,60,1,pg_temp.gid(24),null,null,false),
(pg_temp.gid(105),pg_temp.gid(1),'pt_package','Inactive trainer programme','Disclosed',0,'INR',0,60,1,pg_temp.gid(27),'Credential','Terms',true);
-- Null-key historical packs exercise read/eligibility states without inventing sales.
-- Real book/cancel sequences below start at zero and must obey the exact ledger.
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on) values
(pg_temp.gid(201),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(202),pg_temp.gid(1),pg_temp.gid(32),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),8,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(203),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'active',1,0,0,'INR',pg_temp.gid(25),1,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(204),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'active',1,0,0,'INR',pg_temp.gid(25),2,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(205),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),3,1,app.gym_today(pg_temp.gid(1))-30,app.gym_today(pg_temp.gid(1))-1),
(pg_temp.gid(206),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'completed',1,0,0,'INR',pg_temp.gid(24),2,2,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+30),
(pg_temp.gid(207),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'refunded',1,0,0,'INR',pg_temp.gid(24),3,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+30),
(pg_temp.gid(208),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(27),3,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+30),
(pg_temp.gid(209),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(28),3,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+30),
(pg_temp.gid(210),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),3,0,null,null),
(pg_temp.gid(212),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'active',1,0,0,'INR',pg_temp.gid(25),2,0,app.gym_today(pg_temp.gid(1))-2,app.gym_today(pg_temp.gid(1))+60),
(pg_temp.gid(211),pg_temp.gid(2),pg_temp.gid(33),pg_temp.gid(103),'active',1,0,0,'INR',pg_temp.gid(26),3,0,app.gym_today(pg_temp.gid(2))-2,app.gym_today(pg_temp.gid(2))+30);
-- Normal catalogue/order fixtures precede trainer deactivation.
update public.staff set is_active=false where id=pg_temp.gid(27);
-- A pre-existing expired pack retains three completed uses and two unclosed
-- scheduled rows. Historical import only; no positive command proof bypasses guards.
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on)
values(pg_temp.gid(290),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(101),'active',1,0,0,'INR',pg_temp.gid(24),10,3,app.gym_today(pg_temp.gid(1))-30,app.gym_today(pg_temp.gid(1))-1);
set local session_replication_role=replica;
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status)
select pg_temp.gid(490+n),pg_temp.gid(1),pg_temp.gid(290),pg_temp.gid(24),pg_temp.gid(31),pg_temp.slot(-10+n),pg_temp.slot(-10+n)+interval '1 hour',
case when n<3 then 'completed'::public.pt_session_status else 'scheduled'::public.pt_session_status end
from generate_series(0,4) n;
set local session_replication_role=origin;
create temporary table pt_probe(label text primary key,v jsonb);
grant select,insert,update on pt_probe to authenticated,service_role;
create function pg_temp.evidence() returns jsonb language sql stable as $$ select jsonb_build_object(
'orders',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.addon_orders x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'sessions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.pt_sessions x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'cancellations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.pt_cancellations x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.payments x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'refunds',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.refunds x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'audits',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.audit_log x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2))),
'notices',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.notifications x where tenant_id in(pg_temp.gid(1),pg_temp.gid(2)))) $$;

-- Profiles, validation, safe disclosures and current MEDIA exposure.
select results_eq($q$select pt_late_cancel_consumes_session,pt_cancel_window_hours,pt_session_minutes from public.organization_settings where tenant_id=pg_temp.gid(1)$q$,$q$select * from (values(true,24,60)) as expected$q$,'PTF-019: defaults are consuming late cancel, 24 hours and 60 minutes');
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_trainer_profile(pg_temp.gid(24),'  Coach biography  ',array['Strength','Mobility'],null,true)$q$,'PTF-001: owner creates and lists active trainer');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(999),repeat('x',601),array[''],null,true)$q$),'42501','PTF-001: unknown trainer visibility precedes malformed profile');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(26),'Bio',array['Strength'],null,true)$q$),'42501','PTF-001: foreign trainer is indistinguishable from unknown');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(21),'Bio',array['Strength'],null,true)$q$,true),'22023:not_a_trainer','PTF-001: same-gym nontrainer is a specific validation refusal');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),repeat('x',601),'{}',null,true)$q$,true),'22023:bio_invalid','PTF-001: 601-character biography refused');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Bio',array['Strength',' strength '],null,true)$q$,true),'22023:speciality_invalid','PTF-001: trimmed case-insensitive duplicate speciality refused');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Bio',array[repeat('x',41)],null,true)$q$,true),'22023:speciality_invalid','PTF-001: 41-character speciality refused');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Bio',array['1','2','3','4','5','6','7','8','9'],null,true)$q$,true),'22023:speciality_invalid','PTF-001: ninth speciality refused');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Bio',array[' '],null,true)$q$,true),'22023:speciality_invalid','PTF-001: blank speciality refused');
set local role postgres;
select is((select bio from public.trainer_profiles where staff_id=pg_temp.gid(24)),'Coach biography','PTF-001: stored biography is trimmed');
select is((select count(*)::integer from public.trainer_profiles where staff_id=pg_temp.gid(24)),1,'PTF-001: exactly one profile per trainer');
select pg_temp.claim('trainer',24,null,904);
set local role authenticated;
select lives_ok($q$select public.set_own_trainer_profile(repeat('x',600),array[repeat('s',40)])$q$,'PTF-001: linked trainer may update own biography at exact limits');
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(25),'Bio','{}',null,true)$q$),'42501','PTF-001: trainer cannot invoke owner listing command');
set local role postgres;
select ok((select is_listed and photo_asset_id is null and char_length(bio)=600 from public.trainer_profiles where staff_id=pg_temp.gid(24)),'PTF-001: self-service preserves listing and photo authority');
select pg_temp.claim('trainer',25,null,905);
set local role authenticated;
select lives_ok($q$select public.set_own_trainer_profile('Private biography',array['Private speciality'])$q$,'PTF-001: trainer creates own unlisted profile');
set local role postgres;
select ok((select not is_listed from public.trainer_profiles where staff_id=pg_temp.gid(25)),'PTF-001: new self-service profile stays unlisted');
select pg_temp.claim('front_desk',23,null,903);
set local role authenticated;
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Desk','{}',null,true)$q$),'42501','PTF-001: desk cannot change profile');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select results_eq($q$select display_name collate "default",bio collate "default",specialities collate "default",is_profile_listed from public.read_member_trainers() order by display_name$q$,$q$select * from (values('Trainer One'::text collate "default",repeat('x' collate "default",600),array[repeat('s' collate "default",40)],true),('Trainer Two'::text collate "default",''::text collate "default",'{}'::text[] collate "default",false)) as expected$q$,'PTF-003: listed details exposed, unlisted programme trainer details suppressed, inactive/foreign excluded');
select results_eq($q$select price_paise,currency,gst_rate_bp,trainer_qualification from public.read_member_programmes() where programme_id=pg_temp.gid(101)$q$,$q$select * from (values('9007199254740993'::text collate "default",'INR'::text collate "default",1800,'Disclosed qualification'::text collate "default")) as expected$q$,'PTF-004: price beyond JavaScript safe integer stays exact decimal text with stored GST');
select is((select count(*)::integer from public.read_member_programmes()),2,'PTF-004: inactive/incomplete/inactive-trainer/foreign offers absent');
select is((select branch_name from public.read_member_trainers() where display_name='Trainer Two'),null::text,'PTF-003: all-branch trainer has no invented branch name');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
insert into pt_probe values('photo',to_jsonb(public.register_media_asset('trainer',pg_temp.gid(1)::text||'/staging/trainer/'||pg_temp.gid(701)::text||'.png','image/png',100)));
select is(pg_temp.err($q$select public.set_trainer_profile(pg_temp.gid(24),'Photo bio','{}',(select (v#>>'{}')::uuid from pt_probe where label='photo'),true)$q$,true),'22023:photo_unavailable','PTF-002: unconfirmed trainer image cannot attach');
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select lives_ok($q$select public.finalize_media_asset((select (v#>>'{}')::uuid from pt_probe where label='photo'),pg_temp.gid(901),pg_temp.gid(21),'gym_owner',pg_temp.gid(1),'trainer','image/png',100,pg_temp.gid(1)::text||'/staging/trainer/'||pg_temp.gid(701)::text||'.png','source73',pg_temp.gid(1)::text||'/published/trainer/'||pg_temp.gid(702)::text||'.png','published73')$q$,'PTF-002/MEDIA: trusted verifier finalizes registered photo fixture without bypassing invariant');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_trainer_profile(pg_temp.gid(24),'Photo bio','{}',(select (v#>>'{}')::uuid from pt_probe where label='photo'),true)$q$,'PTF-002: owner attaches confirmed trainer image');
set local role postgres;
select is((select attached_to_id from public.media_assets where id=(select (v#>>'{}')::uuid from pt_probe where label='photo')),pg_temp.gid(24),'PTF-002: asset attached to private staff UUID rather than pseudonym');
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select results_eq($q$select trainer_key,image_asset_id from public.read_member_trainers() where display_name='Trainer One'$q$,$q$select md5('pt-trainer:'||pg_temp.gid(1)::text||':'||pg_temp.gid(24)::text)::uuid,(v#>>'{}')::uuid from pt_probe where label='photo'$q$,'PTF-003: exposed asset and canonical trainer pseudonym match same staff attachment');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_trainer_profile(pg_temp.gid(24),'Photo bio','{}',(select (v#>>'{}')::uuid from pt_probe where label='photo'),false)$q$,'PTF-003: owner withdraws profile listing');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select ok((select image_asset_id is null and bio='' and not is_profile_listed from public.read_member_trainers() where display_name='Trainer One'),'PTF-003: current unlisting withdraws image and private profile details even while programme remains');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_trainer_profile(pg_temp.gid(24),'Restored','{}',null,true)$q$,'PTF-002: owner clears photo through release protocol');
set local role postgres;
select ok((select attached_to_id is null and deleted_at is not null from public.media_assets where id=(select (v#>>'{}')::uuid from pt_probe where label='photo')),'PTF-002: removed photo retains detached metadata tombstone');
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is((select image_asset_id from public.read_member_trainers() where display_name='Trainer One'),null::uuid,'PTF-003: released photo cannot remain in current exposure');
set local role postgres;

-- Complete identity precedes argument parsing, visibility and all side effects.
insert into pt_probe values('identity_before',pg_temp.evidence());
select pg_temp.claim('member',null,31,908);
set local role authenticated;
select is(pg_temp.err($q$select public.book_pt_session(null,null,null)$q$),'42501','PTF-009/021: wrong Auth binding precedes null arguments');
select is(pg_temp.err($q$select public.read_member_trainers()$q$),'42501','PTF-021: forged member read identity refused');
set local role postgres;
select pg_temp.claim('member',21,31,907);
set local role authenticated;
select is(pg_temp.err($q$select public.read_member_pt_packs()$q$),'42501','PTF-021: mixed member/staff identity refused');
set local role postgres;
select pg_temp.claim('member',null,31,907,1,true);
set local role authenticated;
select is(pg_temp.err($q$select public.cancel_pt_booking(null)$q$),'42501','PTF-021: preview identity refused before session parsing');
set local role postgres;
select pg_temp.claim('member',null,31,null);
set local role authenticated;
select is(pg_temp.err($q$select public.read_member_programmes()$q$),'42501','PTF-021: missing Auth subject refused');
set local role postgres;
select pg_temp.claim('member',null,31,907,null);
set local role authenticated;
select is(pg_temp.err($q$select public.read_member_pt_sessions('bad')$q$),'42501','PTF-021: missing tenant precedes malformed scope');
set local role postgres;
select pg_temp.claim('gym_owner',21,null,908);
set local role authenticated;
select is(pg_temp.err($q$select public.set_pt_policy(-1,true,1)$q$),'42501','PTF-019: forged owner binding precedes policy validation');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='identity_before'),'PTF-021/024: identity refusals change no ledger, session, audit or notice');
update public.staff set is_active=false where id=pg_temp.gid(22);
select pg_temp.claim('gym_manager',22,null,902);
set local role authenticated;
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[]')$q$),'42501','PTF-006: stale inactive manager refused');
set local role postgres;
update public.staff set is_active=true where id=pg_temp.gid(22);
update public.members set erased_at=statement_timestamp() where id=pg_temp.gid(31);
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is(pg_temp.err($q$select public.read_member_pt_packs()$q$),'42501','PTF-021: erased member refuses stale claim');
set local role postgres;
update public.members set erased_at=null where id=pg_temp.gid(31);
-- Historical tenant-state fixture only; real read still runs with origin guards.
set local session_replication_role=replica;
update public.organizations set status='suspended' where id=pg_temp.gid(1);
set local session_replication_role=origin;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is(pg_temp.err($q$select public.read_member_trainers()$q$),'42501','PTF-021: ineligible gym refuses member read');
set local role postgres;
-- Historical tenant-state fixture only; real read still runs with origin guards.
set local session_replication_role=replica;
update public.organizations set status='active' where id=pg_temp.gid(1);
set local session_replication_role=origin;

-- Availability replacement: adjacent windows allowed, overlap atomic, soft time off.
select pg_temp.claim();
set local role authenticated;
select is(public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":540,"endMinute":600},{"weekday":1,"startMinute":600,"endMinute":720},{"weekday":3,"startMinute":540,"endMinute":720}]'::jsonb),3,'PTF-006: three windows including touching endpoints replace in one command');
set local role postgres;
insert into pt_probe values('windows_before',(select jsonb_agg(to_jsonb(x) order by id) from public.trainer_availability x where staff_id=pg_temp.gid(24))),('availability_refusal_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":540,"endMinute":660},{"weekday":1,"startMinute":600,"endMinute":720}]')$q$,true),'22023:window_overlap','PTF-006: overlap refused before replacing existing windows');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":7,"startMinute":0,"endMinute":60}]')$q$,true),'22023:window_invalid','PTF-006: weekday seven refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":60,"endMinute":60}]')$q$,true),'22023:window_invalid','PTF-006: empty interval refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":0,"endMinute":1441}]')$q$,true),'22023:window_invalid','PTF-006: minute beyond midnight refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"start_minute":0,"end_minute":60}]')$q$),'22023','PTF-006: snake_case storage aliases are not accepted command encoding');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":"1","startMinute":0,"endMinute":60}]')$q$),'22023','PTF-006: numeric strings are not JSON numbers');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":0,"endMinute":60,"extra":true}]')$q$),'22023','PTF-006: strict window object refuses extra keys');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":false,"endMinute":60}]')$q$),'22023','PTF-006: boolean minute refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":0,"endMinute":null}]')$q$),'22023','PTF-006: null minute refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[1]')$q$),'22023','PTF-006: nonobject window refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'{}')$q$),'22023','PTF-006: nonarray input refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),null)$q$),'22023','PTF-006: SQL null array refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1,"startMinute":0}]')$q$),'22023','PTF-006: missing required endMinute refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[{"weekday":1.5,"startMinute":0,"endMinute":60}]')$q$),'22023','PTF-006: fractional JSON weekday refused');
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),(select jsonb_agg(jsonb_build_object('weekday',1,'startMinute',n*5,'endMinute',(n+1)*5)) from generate_series(0,28) n))$q$),'22023','PTF-006: 29 otherwise-valid disjoint windows exceed maximum');
set local role postgres;
select is((select jsonb_agg(to_jsonb(x) order by id) from public.trainer_availability x where staff_id=pg_temp.gid(24)),(select v from pt_probe where label='windows_before'),'PTF-006: failed replacement preserves every old window');
select is(pg_temp.evidence(),(select v from pt_probe where label='availability_refusal_before'),'PTF-006/024: invalid replacement has no audit or ledger effects');
select is(pg_temp.err($q$insert into public.trainer_availability(tenant_id,staff_id,weekday,start_minute,end_minute) values(pg_temp.gid(1),pg_temp.gid(24),1,550,610)$q$),'23P01','PTF-006: direct trusted overlap hits exclusion backstop');
select pg_temp.claim('trainer',25,null,905);
set local role authenticated;
select is(pg_temp.err($q$select public.set_trainer_availability(pg_temp.gid(24),'[]')$q$),'42501','PTF-006: trainer cannot replace another trainer windows');
select is(public.set_trainer_availability(pg_temp.gid(25),'[]'),0,'PTF-006: linked trainer may replace own windows with empty array');
set local role postgres;
-- All-week windows make tomorrow's grid deterministic irrespective of run date.
select pg_temp.claim();
set local role authenticated;
select is(public.set_trainer_availability(pg_temp.gid(24),(select jsonb_agg(jsonb_build_object('weekday',n,'startMinute',0,'endMinute',1440)) from generate_series(0,6) n)),7,'PTF-006: owner replaces with seven full-day windows');
select is(public.set_trainer_availability(pg_temp.gid(25),(select jsonb_agg(jsonb_build_object('weekday',n,'startMinute',0,'endMinute',1440)) from generate_series(0,6) n)),7,'PTF-006: all-branch trainer has deterministic windows');
select is(pg_temp.err($q$select public.add_trainer_time_off(pg_temp.gid(24),current_date+2,current_date+1,'Reason')$q$,true),'22023:range_invalid','PTF-007: inverted time off refused');
insert into pt_probe values('time_off',to_jsonb(public.add_trainer_time_off(pg_temp.gid(24),(pg_temp.slot(4) at time zone 'Asia/Kolkata')::date,(pg_temp.slot(4) at time zone 'Asia/Kolkata')::date,'Private holiday reason')));
set local role postgres;
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(4)),'time_off','PTF-008: active time off closes offered starts');
insert into public.organization_holidays(tenant_id,holiday_on,name) values(pg_temp.gid(1),(pg_temp.slot(4) at time zone 'Asia/Kolkata')::date,'Holiday');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(4)),'holiday','PTF-008: holiday wins ahead of overlapping time off');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),statement_timestamp()+interval '59 minutes 59 seconds'),'too_soon','PTF-008: strict minimum lead refuses one second short');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),statement_timestamp()+interval '28 days'),'beyond_horizon','PTF-008: exact 28-day instant is outside horizon');
select ok(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),statement_timestamp()+interval '60 minutes')<>'too_soon','PTF-008: exact minimum lead is not too soon even when off grid');
select ok(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),statement_timestamp()+interval '27 days 23 hours 59 minutes 59 seconds')<>'beyond_horizon','PTF-008: one second before horizon is not outside horizon');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(1)+interval '1 second'),'not_offered','PTF-008: nonzero seconds are off grid');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(1,601)),'not_offered','PTF-008: minute not on session grid refused');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(1)),'open','PTF-008: free whole-hour grid start is open');
delete from public.organization_holidays where tenant_id=pg_temp.gid(1);
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.remove_trainer_time_off((select (v#>>'{}')::uuid from pt_probe where label='time_off'))$q$,'PTF-007: owner soft-removes own time off');
set local role postgres;
insert into pt_probe values('off_replay_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.remove_trainer_time_off((select (v#>>'{}')::uuid from pt_probe where label='time_off'))$q$,'PTF-007: removal replay succeeds');
set local role postgres;
select ok((select removed_at is not null and removed_by_staff_id=pg_temp.gid(21) from public.trainer_time_off where id=(select (v#>>'{}')::uuid from pt_probe where label='time_off')),'PTF-007: removal records actor and keeps row');
select is(pg_temp.evidence(),(select v from pt_probe where label='off_replay_before'),'PTF-007: removal replay writes no audit or other effect');

-- Expiry exception keeps actual reservations visible without sweeping history.
insert into pt_probe values('expired_boundary_before',pg_temp.evidence());
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select results_eq($q$select state::text collate "default",sessions_total,sessions_used,sessions_scheduled,sessions_remaining,can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(290)$q$,$q$select 'expired'::text collate "default",10,3,2,7,false$q$,'PTF-018: expired member pack counts seven unused sessions despite two unclosed reservations');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(290),pg_temp.gid(495),pg_temp.slot(1))$q$,true),'GL058:session_outside_validity','PTF-009/018: expired pack with unused capacity refuses a future booking');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select state::text collate "default",sessions_total,sessions_used,sessions_scheduled,sessions_remaining from public.read_pt_packs(null,'expired') where order_id=pg_temp.gid(290)$q$,$q$select 'expired'::text collate "default",10,3,2,7$q$,'PTF-018/032: staff expired read reports the same unused balance and actual reservations');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='expired_boundary_before'),'PTF-018: expiry reads and booking refusal change no order/session/ledger/refund/audit/notice');

-- Pack states and live-membership primitive consumption, never redefinition.
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select results_eq($q$select state::text collate "default",sessions_total,sessions_used,sessions_scheduled,sessions_remaining,can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(201)$q$,$q$select * from (values('live'::text collate "default",8,0,0,8,true)) as expected$q$,'PTF-005: live pack distinguishes purchased, used, booked and free capacity');
select results_eq($q$select state::text collate "default",sessions_remaining,can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(205)$q$,$q$select * from (values('expired'::text collate "default",2,false)) as expected$q$,'PTF-018: expired active pack preserves unspent sessions');
select results_eq($q$select state::text collate "default",can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(206)$q$,$q$select * from (values('spent'::text collate "default",false)) as expected$q$,'PTF-005: completed pack reads spent');
select results_eq($q$select state::text collate "default",can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(207)$q$,$q$select * from (values('closed'::text collate "default",false)) as expected$q$,'PTF-005: refunded pack reads closed');
select ok(not (select can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(208)),'PTF-005: inactive assigned trainer blocks booking convenience');
select ok(not (select can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(209)),'PTF-005: other-branch trainer blocks booking convenience');
select is((select count(*)::integer from public.read_member_pt_packs() where order_id in(pg_temp.gid(202),pg_temp.gid(211))),0,'PTF-021: other member and foreign packs absent');
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(202),(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date,(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date)),0,'PTF-008: other member slot list returns zero rows');
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(205),current_date,current_date)),0,'PTF-008: nonbookable expired pack has no offered starts');
select is(pg_temp.err($q$select public.read_member_pt_slots(pg_temp.gid(201),current_date,current_date+14)$q$,true),'22023:range_invalid','PTF-008: 15 inclusive days refused');
select is(pg_temp.err($q$select public.read_member_pt_sessions('invalid')$q$,true),'22023:scope_invalid','PTF-021: valid identity gets specific invalid-scope refusal');
select is(pg_temp.err($q$select public.book_pt_session(null,null,null)$q$),'22023','PTF-009: valid identity checks null inputs before visibility');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(202),pg_temp.gid(301),pg_temp.slot(1))$q$),'42501','PTF-009: same-tenant other member order refused silently');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(211),pg_temp.gid(301),pg_temp.slot(1))$q$),'42501','PTF-009: foreign order refused silently');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(999),pg_temp.gid(301),pg_temp.slot(1))$q$),'42501','PTF-009: unknown order shares visibility refusal');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(208),pg_temp.gid(301),pg_temp.slot(1))$q$,true),'GL055:trainer_unavailable','PTF-009: inactive trainer is specific pack refusal');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(209),pg_temp.gid(301),pg_temp.slot(1))$q$),'GL094','PTF-009: wrong branch precedes slot-state checks');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(210),pg_temp.gid(301),pg_temp.slot(1))$q$,true),'GL055:order_unavailable','PTF-009: missing validity cannot authorize a slot');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(201),pg_temp.gid(301),pg_temp.slot(1,601))$q$,true),'GL092:not_offered','PTF-009: write applies same grid state as read');
select ok(exists(select 1 from public.read_member_pt_slots(pg_temp.gid(201),(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date,(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date) where starts_at=pg_temp.slot(1) and ends_at=pg_temp.slot(1)+interval '60 minutes' and timezone='Asia/Kolkata'),'PTF-008: selected start and server duration are actually offered by read');
select lives_ok($q$insert into pt_probe select 'book_first',to_jsonb(b) from public.book_pt_session(pg_temp.gid(201),pg_temp.gid(301),pg_temp.slot(1)) b$q$,'PTF-008/011: slot returned by deterministic open grid is accepted');
select results_eq($q$select state::text collate "default",sessions_total,sessions_used,sessions_scheduled,sessions_remaining,can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(201)$q$,$q$select 'live'::text collate "default",8,0,1,7,true$q$,'PTF-005: live member balance still subtracts the genuine reservation');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select state::text collate "default",sessions_total,sessions_used,sessions_scheduled,sessions_remaining from public.read_pt_packs() where order_id=pg_temp.gid(201)$q$,$q$select 'live'::text collate "default",8,0,1,7$q$,'PTF-032: live staff balance still subtracts the genuine reservation');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
set local role postgres;
select results_eq($q$select tenant_id,addon_order_id,member_id,trainer_staff_id,starts_at,ends_at,status::text,notes from public.pt_sessions where id=pg_temp.gid(301)$q$,$q$select pg_temp.gid(1),pg_temp.gid(201),pg_temp.gid(31),pg_temp.gid(24),pg_temp.slot(1),pg_temp.slot(1)+interval '60 minutes','scheduled'::text,null::text$q$,'PTF-011: inserted session derives exact identities, duration, scheduled status and null notes');
select is((select count(*)::integer from public.attendance where tenant_id=pg_temp.gid(1)),0,'PTF-011: booking creates no attendance');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='pt_session.booked' and record_id=pg_temp.gid(301) and actor_user_id=pg_temp.gid(907) and actor_role='member' and after=jsonb_build_object('order_id',pg_temp.gid(201),'trainer_staff_id',pg_temp.gid(24),'starts_at',pg_temp.slot(1),'ends_at',pg_temp.slot(1)+interval '60 minutes')),'PTF-024: booking audit contains exact attributed facts');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory' and granted and ((classid::bigint<<32)|objid::bigint)=hashtextextended('pt-session:'||pg_temp.gid(1)::text||':'||pg_temp.gid(301)::text,0)),'PTF-010: successful booking holds canonical session advisory lock');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid() and locktype='advisory' and granted and ((classid::bigint<<32)|objid::bigint)=hashtextextended('addon-order:'||pg_temp.gid(1)::text||':'||pg_temp.gid(201)::text,0)),'PTF-010: successful booking holds existing order advisory lock');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(24),pg_temp.slot(1)),'taken','PTF-008: reservation removes trainer start');
insert into pt_probe values('booking_before',pg_temp.evidence());
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select ok((select replayed and status='booked' from public.book_pt_session(pg_temp.gid(201),pg_temp.gid(301),pg_temp.slot(1))),'PTF-011: exact request-key retry returns current booking');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(201),pg_temp.gid(301),pg_temp.slot(2))$q$),'GL052','PTF-011: changed start under request UUID is conflict');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(204),pg_temp.gid(302),pg_temp.slot(1))$q$),'GL091','PTF-009: member overlap across trainers wins before slot state');
select is((select count(*)::integer from public.read_member_pt_slots(pg_temp.gid(201),(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date,(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date) where starts_at=pg_temp.slot(1)),0,'PTF-008: taken start is absent from offered list');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='booking_before'),'PTF-011/024: booking replay and refused conflicts write no rows/audits/notices/money');
select pg_temp.claim('member',null,32,908);
set local role authenticated;
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(202),pg_temp.gid(302),pg_temp.slot(1))$q$),'GL096','PTF-010: different member gets trainer-slot refusal');
select lives_ok($q$select public.book_pt_session(pg_temp.gid(202),pg_temp.gid(302),pg_temp.slot(2))$q$,'PTF-009: frozen membership consumes canonical live-membership predicate');
set local role postgres;
-- Historical membership-date fixture only; command assertions retain origin.
set local session_replication_role=replica;
update public.memberships set ends_on=(pg_temp.slot(3) at time zone 'Asia/Kolkata')::date-1 where id=pg_temp.gid(52);
set local session_replication_role=origin;
select pg_temp.claim('member',null,32,908);
set local role authenticated;
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(202),pg_temp.gid(303),pg_temp.slot(3))$q$),'GL093','PTF-009: future slot after membership inclusive end refused');
set local role postgres;
-- Historical membership-date fixture only; command assertions retain origin.
set local session_replication_role=replica;
update public.memberships set ends_on=app.gym_today(pg_temp.gid(1))+90 where id=pg_temp.gid(52);
set local session_replication_role=origin;

-- Policy at cancellation time, exact cutoff, consumption and cancellation replay.
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_pt_policy(24,true,60)$q$,'PTF-019: owner sets audited policy');
select is(pg_temp.err($q$update public.organization_settings set pt_cancel_window_hours=12 where tenant_id=pg_temp.gid(1)$q$),'42501','PTF-019: direct owner policy change refused');
select is(pg_temp.err($q$select public.set_pt_policy(169,true,60)$q$,true),'22023:policy_out_of_range','PTF-019: 169-hour window refused');
select is(pg_temp.err($q$select public.set_pt_policy(24,true,16)$q$,true),'22023:policy_out_of_range','PTF-019: duration must be multiple of five');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(204),pg_temp.gid(304),pg_temp.slot(3))$q$,'PTF-013: prepare early cancellation');
select results_eq($q$select status::text collate "default",late,consumed,replayed from public.cancel_pt_booking(pg_temp.gid(304))$q$,$q$select * from (values('cancelled_by_member'::text collate "default",false,false,false)) as expected$q$,'PTF-013: outside current window cancels without consumption');
set local role postgres;
select is((select sessions_used from public.addon_orders where id=pg_temp.gid(204)),0,'PTF-014: early cancel leaves used counter zero');
select is(app.pt_slot_state(pg_temp.gid(1),pg_temp.gid(25),pg_temp.slot(3)),'open','PTF-013: cancelled slot reopens immediately');
-- One statement shares statement_timestamp across fixture insertion and cancel;
-- exact cutoff is reachable without replacing clocks or sleeping.
select pg_temp.claim('member',null,31,907);
set local role postgres;
select set_config('app.pt_member_command','book:'||pg_temp.gid(305)::text||':'||pg_temp.gid(204)::text,true);
with inserted as(insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at) values(pg_temp.gid(305),pg_temp.gid(1),pg_temp.gid(204),pg_temp.gid(25),pg_temp.gid(31),statement_timestamp()+interval '24 hours',statement_timestamp()+interval '25 hours') returning id)
select results_eq(format('select late,consumed from public.cancel_pt_booking(%L::uuid)',id),$q$select * from (values(false,false)) as expected$q$,'PTF-013: exactly at cutoff is not late and consumes zero') from inserted;
select set_config('app.pt_member_command','',true);
select set_config('app.pt_member_command','book:'||pg_temp.gid(351)::text||':'||pg_temp.gid(212)::text,true);
with inserted as(insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at) values(pg_temp.gid(351),pg_temp.gid(1),pg_temp.gid(212),pg_temp.gid(25),pg_temp.gid(31),statement_timestamp()+interval '24 hours 1 second',statement_timestamp()+interval '25 hours 1 second') returning id)
select results_eq(format('select late,consumed from public.cancel_pt_booking(%L::uuid)',id),$q$select * from (values(false,false)) as expected$q$,'PTF-013: one second before cutoff is free') from inserted;
select set_config('app.pt_member_command','book:'||pg_temp.gid(352)::text||':'||pg_temp.gid(212)::text,true);
with inserted as(insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at) values(pg_temp.gid(352),pg_temp.gid(1),pg_temp.gid(212),pg_temp.gid(25),pg_temp.gid(31),statement_timestamp()+interval '23 hours 59 minutes 59 seconds',statement_timestamp()+interval '24 hours 59 minutes 59 seconds') returning id)
select results_eq(format('select late,consumed from public.cancel_pt_booking(%L::uuid)',id),$q$select * from (values(true,true)) as expected$q$,'PTF-013: one second after cutoff uses exactly one under true policy') from inserted;
select set_config('app.pt_member_command','book:'||pg_temp.gid(353)::text||':'||pg_temp.gid(212)::text,true);
with inserted as(insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at) values(pg_temp.gid(353),pg_temp.gid(1),pg_temp.gid(212),pg_temp.gid(25),pg_temp.gid(31),statement_timestamp(),statement_timestamp()+interval '1 hour') returning id)
select is(pg_temp.err(format('select public.cancel_pt_booking(%L::uuid)',id)),'GL095','PTF-013: session starting at command instant cannot be cancelled') from inserted;
select set_config('app.pt_member_command','',true);
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_pt_policy(168,true,60)$q$,'PTF-014: increase current window before future cancellation');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(203),pg_temp.gid(306),pg_temp.slot(5))$q$,'PTF-014: reserve final session of one-session live pack');
select results_eq($q$select state::text collate "default",sessions_scheduled,sessions_remaining,can_book from public.read_member_pt_packs() where order_id=pg_temp.gid(203)$q$,$q$select * from (values('fully_booked'::text collate "default",1,0,false)) as expected$q$,'PTF-005: final reservation reads fully booked rather than spent');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(203),pg_temp.gid(307),pg_temp.slot(6))$q$,true),'GL058:session_budget_exhausted','PTF-009: reservation budget refuses beyond purchased total');
select results_eq($q$select status::text collate "default",late,consumed,sessions_remaining,replayed from public.cancel_pt_booking(pg_temp.gid(306))$q$,$q$select * from (values('cancelled_by_member'::text collate "default",true,true,0,false)) as expected$q$,'PTF-014: current consuming window uses final session exactly once');
set local role postgres;
select results_eq($q$select status::text collate "default",sessions_used,sessions_total from public.addon_orders where id=pg_temp.gid(203)$q$,$q$select * from (values('completed'::text collate "default",1,1)) as expected$q$,'PTF-014: last forfeiture completes order');
select results_eq($q$select outcome::text collate "default",window_hours,policy_consumes,was_late,consumed,completed_order,waived_at from public.pt_cancellations where pt_session_id=pg_temp.gid(306)$q$,$q$select * from (values('cancelled_by_member'::text collate "default",168,true,true,true,true,null::timestamptz)) as expected$q$,'PTF-014: same cancellation freezes policy and causal completion marker');
select is((select status::text from public.pt_sessions where id=pg_temp.gid(306)),'cancelled','PTF-014: forfeiture does not fake attendance/completed session');
insert into pt_probe values('cancel_replay_before',pg_temp.evidence()),('waive_order_terms',(select to_jsonb(x)-array['status','sessions_used','updated_at'] from public.addon_orders x where id=pg_temp.gid(203))),('waive_session',(select to_jsonb(x) from public.pt_sessions x where id=pg_temp.gid(306))),('waive_cause',(select to_jsonb(x)-array['waived_at','waived_by_staff_id','waive_reason','updated_at'] from public.pt_cancellations x where pt_session_id=pg_temp.gid(306)));
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select ok((select replayed and consumed from public.cancel_pt_booking(pg_temp.gid(306))),'PTF-013: late cancellation replay preserves effective consumption');
select ok((select replayed and status='cancelled_by_member' from public.book_pt_session(pg_temp.gid(203),pg_temp.gid(306),pg_temp.slot(5))),'PTF-011: booking replay precedes completed pack check and returns current cancellation');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='cancel_replay_before'),'PTF-013/014: both retries mutate no counter, audit, cancellation or notice');
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_pt_policy(168,false,60)$q$,'PTF-019: disable consumption without rewriting history');
set local role postgres;
select ok((select policy_consumes and window_hours=168 and consumed and completed_order from public.pt_cancellations where pt_session_id=pg_temp.gid(306)),'PTF-019: policy change leaves prior provenance intact');
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(204),pg_temp.gid(307),pg_temp.slot(6))$q$,'PTF-014: reserve under false-consumption policy');
select results_eq($q$select late,consumed from public.cancel_pt_booking(pg_temp.gid(307))$q$,$q$select * from (values(true,false)) as expected$q$,'PTF-014: late cancellation under false flag uses zero');
set local role postgres;
select ok((select not completed_order and not consumed from public.pt_cancellations where pt_session_id=pg_temp.gid(307)),'PTF-014: nonconsuming cancellation never claims order completion');

-- Completed-pack waiver: exact cause, real owner, once-only, sold terms frozen.
select pg_temp.claim('front_desk',23,null,903);
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),'Valid reason')$q$),'42501','PTF-016: desk cannot waive final-session forfeiture');
set local role postgres;
select pg_temp.claim('trainer',25,null,905);
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),'Valid reason')$q$),'42501','PTF-016: assigned trainer cannot waive');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),'Valid reason')$q$),'42501','PTF-016: owning member cannot waive');
set local role postgres;
select pg_temp.claim('gym_owner',21,null,901,1,true);
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),'Valid reason')$q$),'42501','PTF-016: owner support preview cannot waive');
set local role postgres;
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),' x ')$q$,true),'22023:reason_invalid','PTF-016: trimmed reason shorter than three refused');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(306),repeat('x',201))$q$,true),'22023:reason_invalid','PTF-016: reason above 200 refused');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(307),'Valid reason')$q$,true),'22023:not_consumed','PTF-016: false-policy cancellation cannot be waived');
set local role postgres;
insert into pt_probe values('waiver_refusals_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select set_config('app.pt_completed_waive_command','waive:'||pg_temp.gid(306)::text||':'||pg_temp.gid(203)::text,true);
select is(pg_temp.err($q$update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203)$q$),'GL053','PTF-023: direct owner forged waiver setting does not admit usage/state change');
select is(pg_temp.err($q$update public.pt_cancellations set waived_at=statement_timestamp(),waived_by_staff_id=pg_temp.gid(21),waive_reason='Forged' where pt_session_id=pg_temp.gid(306)$q$),'42501','PTF-020/023: owner cannot write waiver evidence directly');
select set_config('app.pt_completed_waive_command','',true);
set local role postgres;
select pg_temp.claim('front_desk',23,null,903);
set local role authenticated;
select set_config('app.pt_completed_waive_command','waive:'||pg_temp.gid(306)::text||':'||pg_temp.gid(203)::text,true);
select is(pg_temp.err($q$update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203)$q$),'GL053','PTF-023: front desk forged completed-waiver setting cannot change usage');
set local role postgres;
select pg_temp.claim('trainer',25,null,905);
set local role authenticated;
select results_eq($q$with changed as(update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203) returning id) select count(*)::integer from changed$q$,$q$select * from (values(0)) as expected$q$,'PTF-023: assigned trainer forged completed-waiver setting reaches no order under write RLS');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select results_eq($q$with changed as(update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203) returning id) select count(*)::integer from changed$q$,$q$select * from (values(0)) as expected$q$,'PTF-023: member forged completed-waiver setting reaches no order under write RLS');
set local role postgres;
select pg_temp.claim('gym_owner',21,null,901,1,true);
set local role authenticated;
select is(pg_temp.err($q$update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203)$q$),'42501','PTF-023: support preview forged setting cannot write completed order');
select set_config('app.pt_completed_waive_command','',true);
set local role postgres;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select set_config('app.pt_completed_waive_command','waive:'||pg_temp.gid(306)::text||':'||pg_temp.gid(203)::text,true);
select is(pg_temp.err($q$update public.addon_orders set status='active',sessions_used=0 where id=pg_temp.gid(203)$q$),'GL054','PTF-023: subjectless service role cannot open completed-pack guard exception');
select set_config('app.pt_completed_waive_command','',true);
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='waiver_refusals_before'),'PTF-023: forged settings change no order, provenance, payment, refund, audit or notice');
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select session_id,order_id,sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(306),'  Owner restores last session  ')$q$,$q$select pg_temp.gid(306),pg_temp.gid(203),0,false$q$,'PTF-016: eligible final-session waiver restores exactly one and reactivates once');
set local role postgres;
select results_eq($q$select status::text collate "default",sessions_used,sessions_total from public.addon_orders where id=pg_temp.gid(203)$q$,$q$select * from (values('active'::text collate "default",0,1)) as expected$q$,'PTF-016: completed pack is active with total-minus-one usage');
select is((select to_jsonb(x)-array['status','sessions_used','updated_at'] from public.addon_orders x where id=pg_temp.gid(203)),(select v from pt_probe where label='waive_order_terms'),'PTF-016/023: restoration preserves every sold identity/money/trainer/date/snapshot term');
select is((select to_jsonb(x) from public.pt_sessions x where id=pg_temp.gid(306)),(select v from pt_probe where label='waive_session'),'PTF-016: waiver never reopens or edits cancelled session');
select is((select to_jsonb(x)-array['waived_at','waived_by_staff_id','waive_reason','updated_at'] from public.pt_cancellations x where pt_session_id=pg_temp.gid(306)),(select v from pt_probe where label='waive_cause'),'PTF-016: consumed policy and completion provenance remain immutable');
select ok((select waived_at is not null and waived_by_staff_id=pg_temp.gid(21) and waive_reason='Owner restores last session' from public.pt_cancellations where pt_session_id=pg_temp.gid(306)),'PTF-016: all waiver fields stamp real actor and trimmed reason');
select ok(exists(select 1 from public.audit_log where tenant_id=pg_temp.gid(1) and action='pt_forfeit.waived' and record_id=pg_temp.gid(306) and actor_user_id=pg_temp.gid(901) and actor_role='gym_owner' and before='{"consumed":true,"sessions_used":1,"order_status":"completed"}'::jsonb and after='{"consumed":false,"sessions_used":0,"order_status":"active"}'::jsonb and reason='Owner restores last session'),'PTF-024: completed waiver audit states exact causal restoration and attributed reason');
select results_eq($q$select channel::text,status::text,category::text,related_type,related_id,payload from public.notifications where tenant_id=pg_temp.gid(1) and template_key='pt_forfeit_waived' and related_id=pg_temp.gid(306)$q$,$q$select 'in_app'::text,'sent'::text,'fulfilment'::text,'pt_session'::text,pg_temp.gid(306),jsonb_build_object('kind','pt_forfeit_waived','body','PT Visible A returned a session to your Second programme pack.')$q$,'PTF-025: exact transactional fulfilment notice sent despite absent marketing consent');
select ok(coalesce(current_setting('app.pt_completed_waive_command',true),'')='','PTF-023: successful waiver clears command setting');
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select ok((select not consumed and status='cancelled_by_member' from public.read_member_pt_sessions('history') where session_id=pg_temp.gid(306)),'PTF-016: member history exposes effective waived cancellation without rewriting stored flag');
set local role postgres;
insert into pt_probe values('waiver_replay_before',pg_temp.evidence());
select pg_temp.claim('gym_manager',22,null,902);
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(306),'Different valid reason')$q$,$q$select * from (values(0,true)) as expected$q$,'PTF-016: authorised manager replay returns current count without replacing owner reason');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='waiver_replay_before'),'PTF-016: second waiver restores nothing twice and writes no money/audit/notice');
select is(pg_temp.err($q$update public.pt_cancellations set completed_order=false where pt_session_id=pg_temp.gid(306)$q$,true),'22023:pt_cancellation_provenance_immutable','PTF-014: trusted edit cannot remove immutable causal completion marker');
select is(pg_temp.err($q$update public.pt_cancellations set completed_order=true where pt_session_id=pg_temp.gid(304)$q$,true),'22023:pt_cancellation_provenance_immutable','PTF-014: historical noncompleting cancellation cannot be backfilled into causal proof');
select lives_ok($q$update public.pt_cancellations set completed_order=completed_order where pt_session_id=pg_temp.gid(306)$q$,'PTF-014: unchanged completed_order value passes minimal provenance guard');

-- Active-pack waiver and fault-injected all-or-nothing restoration.
select pg_temp.claim();
set local role authenticated;
select lives_ok($q$select public.set_pt_policy(168,true,60)$q$,'PTF-016: prepare active-pack consuming policy');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(204),pg_temp.gid(308),pg_temp.slot(2))$q$,'PTF-016: reserve one of two purchased sessions');
select ok((select consumed from public.cancel_pt_booking(pg_temp.gid(308))),'PTF-014: active pack forfeits one session');
set local role postgres;
select ok((select not completed_order from public.pt_cancellations where pt_session_id=pg_temp.gid(308)),'PTF-014: nonfinal forfeit has false causal-completion marker');
insert into pt_probe values('atomic_before',pg_temp.evidence());
create function pg_temp.reject_waiver_audit() returns trigger language plpgsql as $$ begin raise exception 'Synthetic audit refusal' using errcode='Z7301'; end $$;
create trigger pt73_reject_waiver_audit before insert on public.audit_log for each row when(new.tenant_id='73000000-0000-4000-8000-000000000001'::uuid and new.action='pt_forfeit.waived') execute function pg_temp.reject_waiver_audit();
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(308),'Audit must succeed')$q$),'Z7301','PTF-016/024: audit failure aborts waiver command');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='atomic_before'),'PTF-016: audit failure rolls back counter, waiver, audit and notice together');
drop trigger pt73_reject_waiver_audit on public.audit_log;
create function pg_temp.reject_waiver_notice() returns trigger language plpgsql as $$ begin raise exception 'Synthetic notice refusal' using errcode='Z7302'; end $$;
create trigger pt73_reject_waiver_notice before insert on public.notifications for each row when(new.tenant_id='73000000-0000-4000-8000-000000000001'::uuid and new.template_key='pt_forfeit_waived') execute function pg_temp.reject_waiver_notice();
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(308),'Notice must succeed')$q$),'Z7302','PTF-016/025: notice failure aborts waiver command');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='atomic_before'),'PTF-016: notice failure rolls back restored capacity and already written audit');
drop trigger pt73_reject_waiver_notice on public.notifications;
select pg_temp.claim('gym_manager',22,null,902);
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(308),'Manager approved')$q$,$q$select * from (values(0,false)) as expected$q$,'PTF-016: manager waives nonfinal forfeit on active pack');
set local role postgres;
select is((select status::text from public.addon_orders where id=pg_temp.gid(204)),'active','PTF-016: active waiver keeps active lifecycle');

-- Real subsequent completion by another forfeiture does not invalidate replay.
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(203),pg_temp.gid(309),pg_temp.slot(6))$q$,'PTF-016: restored capacity is genuinely bookable within original validity');
select ok((select consumed from public.cancel_pt_booking(pg_temp.gid(309))),'PTF-016: later independent final forfeiture completes pack normally');
set local role postgres;
insert into pt_probe values('later_completed_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(306),'Replay after new completion')$q$,$q$select * from (values(1,true)) as expected$q$,'PTF-016: old waiver replay returns current used count after a later completion');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='later_completed_before'),'PTF-016: old waiver cannot restore another cancellation consumption');
select is_empty($q$select o.id from public.addon_orders o where o.id in(pg_temp.gid(201),pg_temp.gid(202),pg_temp.gid(203),pg_temp.gid(204)) and o.sessions_used<>(select count(*) from public.pt_sessions s where s.addon_order_id=o.id and s.status='completed')+(select count(*) from public.pt_cancellations c where c.addon_order_id=o.id and c.consumed and c.waived_at is null)$q$,'PTF-014: exact consumed ledger invariant holds after book/cancel/waive/recomplete sequences');

-- Genuine paid sales produce completion provenance; refund fixtures go through
-- ordinary refund guards, never a disabled trigger or an invented money value.
select set_config('request.jwt.claims','',true);
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,currency,validity_days,session_count,trainer_staff_id,trainer_qualification,cancellation_terms) values
(pg_temp.gid(106),pg_temp.gid(1),'pt_package','Paid single','One session',10000,'INR',60,1,pg_temp.gid(25),'Paid credential','Paid terms'),
(pg_temp.gid(107),pg_temp.gid(1),'pt_package','Paid pair','Two sessions',10000,'INR',60,2,pg_temp.gid(25),'Paid credential','Paid terms');
select pg_temp.claim();
set local role authenticated;
insert into pt_probe select 'refund_case_'||n,to_jsonb(s) from generate_series(0,5) n cross join lateral public.record_addon_sale(pg_temp.gid(31),pg_temp.gid(106),1,(select quote_version from public.addon_products where id=pg_temp.gid(106)),pg_temp.gid(25),pg_temp.slot(1,n*60),pg_temp.slot(1,(n+1)*60),'cash','Paid waiver boundary',pg_temp.gid(800+n)) s;
insert into pt_probe select 'active_paid',to_jsonb(s) from public.record_addon_sale(pg_temp.gid(31),pg_temp.gid(107),1,(select quote_version from public.addon_products where id=pg_temp.gid(107)),pg_temp.gid(25),pg_temp.slot(1,360),pg_temp.slot(1,420),'cash','Active waiver boundary',pg_temp.gid(806)) s;
insert into pt_probe select 'exact_money',to_jsonb(s) from public.record_addon_sale(pg_temp.gid(31),pg_temp.gid(101),1,(select quote_version from public.addon_products where id=pg_temp.gid(101)),pg_temp.gid(24),pg_temp.slot(1,1200),pg_temp.slot(1,1260),'cash','Exact paise sale',pg_temp.gid(807)) s;
set local role postgres;
select results_eq($q$select o.unit_price_paise,o.total_paise,o.currency,p.amount_paise,p.currency from public.addon_orders o join public.payments p on p.id=o.payment_id where o.id=(select (v->>'order_id')::uuid from pt_probe where label='exact_money')$q$,$q$select * from (values(9007199254740993::bigint,9007199254740993::bigint,'INR'::text collate "default",9007199254740993::bigint,'INR'::text collate "default")) as expected$q$,'PTF-004/023: canonical desk sale retains integer paise beyond floating-point precision');
insert into pt_probe values('exact_money_before',(select jsonb_build_object('order',to_jsonb(o)-array['status','sessions_used','updated_at'],'payment',to_jsonb(p)) from public.addon_orders o join public.payments p on p.id=o.payment_id where o.id=(select (v->>'order_id')::uuid from pt_probe where label='exact_money')));
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is((select count(*)::integer from pt_probe x cross join lateral public.cancel_pt_booking((x.v->>'initial_session_id')::uuid) c where x.label like 'refund_case_%' and c.consumed),6,'PTF-014: each genuinely sold single pack late-cancels its own last session');
select ok((select consumed from public.cancel_pt_booking((select (v->>'initial_session_id')::uuid from pt_probe where label='active_paid'))),'PTF-014: genuine two-session sale forfeits only one while active');
select ok((select consumed from public.cancel_pt_booking((select (v->>'initial_session_id')::uuid from pt_probe where label='exact_money'))),'PTF-014: paid exact-money pack consumes capacity without modifying payment');
set local role postgres;
select is((select count(*)::integer from pt_probe x join public.pt_cancellations c on c.pt_session_id=(x.v->>'initial_session_id')::uuid join public.addon_orders o on o.id=c.addon_order_id where x.label like 'refund_case_%' and c.completed_order and c.consumed and o.status='completed' and o.sessions_used=1),6,'PTF-014: all refund-case causes arise from actual final forfeiture transactions');
select set_config('request.jwt.claims','',true);
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id,idempotency_key,processed_at)
select pg_temp.gid(820+n),pg_temp.gid(1),(v->>'payment_id')::uuid,'refund',case when n=3 then 10000 else 1 end,'INR',case n when 0 then 'requested' when 1 then 'processing' when 4 then 'failed' else 'completed' end::public.refund_status,'Recorded return boundary',pg_temp.gid(21),pg_temp.gid(820+n)::text,case when n in(2,3) then statement_timestamp() end
from generate_series(0,4) n join pt_probe x on x.label='refund_case_'||n;
-- Same-tenant unrelated payment and foreign-tenant return rows are controls.
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,paid_at) values
(pg_temp.gid(850),pg_temp.gid(1),pg_temp.gid(31),10000,'INR','paid','cash',statement_timestamp()),
(pg_temp.gid(851),pg_temp.gid(2),pg_temp.gid(33),10000,'INR','paid','cash',statement_timestamp());
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,processed_at) values
(pg_temp.gid(852),pg_temp.gid(1),pg_temp.gid(850),'refund',1,'INR','completed','Unrelated payment',statement_timestamp()),
(pg_temp.gid(853),pg_temp.gid(2),pg_temp.gid(851),'refund',1,'INR','completed','Unrelated tenant',statement_timestamp());
-- Failed currency differs deliberately: failed rows do not reserve ordinary cash,
-- but still block this one exceptional completed-pack restoration.
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason) values
(pg_temp.gid(854),pg_temp.gid(1),(select (v->>'payment_id')::uuid from pt_probe where label='refund_case_4'),'reversal',1,'USD','failed','Failed different-currency attempt');
insert into pt_probe values('returns_refusal_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_0'),'Requested excludes')$q$,true),'GL055:order_unavailable','PTF-016: requested refund record blocks completed exception regardless of cash returned');
select is(pg_temp.err($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_1'),'Processing excludes')$q$,true),'GL055:order_unavailable','PTF-016: processing refund record blocks completed exception');
select is(pg_temp.err($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_2'),'Partial excludes')$q$,true),'GL055:order_unavailable','PTF-016: even one paise completed return blocks completed exception');
select is(pg_temp.err($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_3'),'Full return excludes')$q$,true),'GL055:order_unavailable','PTF-016: fully returned completed pack cannot restore');
select is(pg_temp.err($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_4'),'Failed excludes')$q$,true),'GL055:order_unavailable','PTF-016: failed refund/reversal records also block completed exception');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='returns_refusal_before'),'PTF-016: every return-status refusal preserves all pack/payment/refund/cause/audit/notice rows');
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='refund_case_5'),'Unrelated returns do not block')$q$,$q$select * from (values(0,false)) as expected$q$,'PTF-016: unrelated payment/tenant return records do not block eligible completed pack');
select lives_ok($q$select public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='exact_money'),'Exact-money session restoration')$q$,'PTF-016: ordinary active paid-pack waiver succeeds');
set local role postgres;
select is((select jsonb_build_object('order',to_jsonb(o)-array['status','sessions_used','updated_at'],'payment',to_jsonb(p)) from public.addon_orders o join public.payments p on p.id=o.payment_id where o.id=(select (v->>'order_id')::uuid from pt_probe where label='exact_money')),(select v from pt_probe where label='exact_money_before'),'PTF-016/023: book/cancel/active waiver preserve every sold term and the exact payment record');
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason) values(pg_temp.gid(855),pg_temp.gid(1),(select (v->>'payment_id')::uuid from pt_probe where label='active_paid'),'refund',1,'INR','requested','Pending ordinary return');
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit((select (v->>'initial_session_id')::uuid from pt_probe where label='active_paid'),'Ordinary active waiver')$q$,$q$select * from (values(0,false)) as expected$q$,'PTF-016: requested record does not broaden ordinary full-return predicate for active-pack waiver');
set local role postgres;
select is_empty($q$select o.id from public.addon_orders o join pt_probe x on (x.v->>'order_id')::uuid=o.id where (x.label like 'refund_case_%' or x.label in('active_paid','exact_money')) and o.sessions_used<>(select count(*) from public.pt_sessions s where s.addon_order_id=o.id and s.status='completed')+(select count(*) from public.pt_cancellations c where c.addon_order_id=o.id and c.consumed and c.waived_at is null)$q$,'PTF-014: actual paid-sale ledger stays exact across all refund boundaries and waivers');

-- Historical ordinary completion and missing/expired validity must not become
-- causal last-session completion just because their current counter is full.
select set_config('request.jwt.claims','',true);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,status,quantity,unit_price_paise,total_paise,currency,trainer_staff_id,sessions_total,sessions_used,starts_on,expires_on) values
(pg_temp.gid(213),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'completed',1,0,0,'INR',pg_temp.gid(25),1,1,app.gym_today(pg_temp.gid(1))-30,app.gym_today(pg_temp.gid(1))-1),
(pg_temp.gid(214),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'completed',1,0,0,'INR',pg_temp.gid(25),1,1,null,null),
(pg_temp.gid(215),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'completed',1,0,0,'INR',pg_temp.gid(25),1,1,app.gym_today(pg_temp.gid(1))-1,app.gym_today(pg_temp.gid(1))),
(pg_temp.gid(218),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'completed',1,0,0,'INR',pg_temp.gid(25),1,1,app.gym_today(pg_temp.gid(1))-1,app.gym_today(pg_temp.gid(1))+30),
(pg_temp.gid(219),pg_temp.gid(1),pg_temp.gid(31),pg_temp.gid(102),'active',1,0,0,'INR',pg_temp.gid(25),1,0,app.gym_today(pg_temp.gid(1))-30,app.gym_today(pg_temp.gid(1))-1);
-- Bounded historical/adversarial fixture loading follows existing visible55:
-- ADD rightly disallows newly inserting past/terminal sessions as live delivery.
-- No successful current booking/cancel/waive or MEDIA path uses this fixture seam.
set local session_replication_role=replica;
insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at,status) values
(pg_temp.gid(320),pg_temp.gid(1),pg_temp.gid(206),pg_temp.gid(24),pg_temp.gid(31),pg_temp.slot(-1,600),pg_temp.slot(-1,660),'cancelled'),
(pg_temp.gid(321),pg_temp.gid(1),pg_temp.gid(206),pg_temp.gid(24),pg_temp.gid(31),pg_temp.slot(-1,720),pg_temp.slot(-1,780),'completed'),
(pg_temp.gid(322),pg_temp.gid(1),pg_temp.gid(213),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(-2,600),pg_temp.slot(-2,660),'cancelled'),
(pg_temp.gid(323),pg_temp.gid(1),pg_temp.gid(214),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(-2,720),pg_temp.slot(-2,780),'cancelled'),
(pg_temp.gid(324),pg_temp.gid(1),pg_temp.gid(215),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(-1,840),pg_temp.slot(-1,900),'cancelled'),
(pg_temp.gid(325),pg_temp.gid(1),pg_temp.gid(218),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(-1,960),pg_temp.slot(-1,1020),'cancelled'),
(pg_temp.gid(326),pg_temp.gid(1),pg_temp.gid(218),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(20),pg_temp.slot(20)+interval '1 hour','scheduled'),
(pg_temp.gid(327),pg_temp.gid(1),pg_temp.gid(219),pg_temp.gid(25),pg_temp.gid(31),pg_temp.slot(-3,600),pg_temp.slot(-3,660),'cancelled'),
(pg_temp.gid(328),pg_temp.gid(2),pg_temp.gid(211),pg_temp.gid(26),pg_temp.gid(33),pg_temp.slot(-1,600),pg_temp.slot(-1,660),'cancelled');
insert into public.pt_cancellations(tenant_id,pt_session_id,addon_order_id,member_id,trainer_staff_id,outcome,cancelled_at,window_hours,policy_consumes,was_late,consumed)
values(pg_temp.gid(1),pg_temp.gid(320),pg_temp.gid(206),pg_temp.gid(31),pg_temp.gid(24),'cancelled_by_member',pg_temp.slot(-1,590),168,true,true,true),
(pg_temp.gid(2),pg_temp.gid(328),pg_temp.gid(211),pg_temp.gid(33),pg_temp.gid(26),'cancelled_by_member',pg_temp.slot(-1,590),168,true,true,true);
insert into public.pt_cancellations(tenant_id,pt_session_id,addon_order_id,member_id,trainer_staff_id,outcome,cancelled_at,window_hours,policy_consumes,was_late,consumed,completed_order)
select pg_temp.gid(1),s.id,s.addon_order_id,pg_temp.gid(31),pg_temp.gid(25),'cancelled_by_member',s.starts_at-interval '10 minutes',168,true,true,true,true from public.pt_sessions s where id in(pg_temp.gid(322),pg_temp.gid(323),pg_temp.gid(324),pg_temp.gid(325),pg_temp.gid(327));
update public.pt_cancellations set waived_at=pg_temp.slot(-2,600),waived_by_staff_id=pg_temp.gid(21),waive_reason='Historical owner waiver' where pt_session_id=pg_temp.gid(327);
set local session_replication_role=origin;
select ok((select not completed_order from public.pt_cancellations where pt_session_id=pg_temp.gid(320)),'PTF-014: historical cancellation without causal evidence keeps false default');
insert into pt_probe values('historical_refusal_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(320),'Ordinary completion stays terminal')$q$,true),'GL055:order_unavailable','PTF-016: full counter alone cannot revive ordinary completed pack');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(322),'Expired causal pack')$q$,true),'GL055:order_unavailable','PTF-016: expired completed pack cannot restore despite true causal marker');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(323),'Missing sold dates')$q$,true),'GL055:order_unavailable','PTF-016: missing original dates exclude completed exception');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(325),'Reservation remains')$q$,true),'GL055:order_unavailable','PTF-016: scheduled reservation excludes completed exception');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(328),'Foreign cancellation')$q$),'42501','PTF-016: foreign cancellation is silent permission refusal');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='historical_refusal_before'),'PTF-016: ordinary/expired/missing-date/reserved/foreign refusals preserve complete evidence');
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(324),'Inclusive final sold day')$q$,$q$select * from (values(0,false)) as expected$q$,'PTF-016: original gym-local expiry date is inclusive for causal restoration');
set local role postgres;
insert into pt_probe values('expired_replay_before',pg_temp.evidence());
select pg_temp.claim();
set local role authenticated;
select results_eq($q$select sessions_used,replayed from public.waive_pt_forfeit(pg_temp.gid(327),'Different valid reason')$q$,$q$select * from (values(0,true)) as expected$q$,'PTF-016: previously waived expired pack replays before current eligibility');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(327),'x')$q$,true),'22023:reason_invalid','PTF-016: replay still validates reason before returning');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='expired_replay_before'),'PTF-016: expired replay preserves historic reason and emits no new charge/refund/audit/notice');

-- Direct forged member-command settings are still stopped by Phase 2 writes.
insert into pt_probe values('direct_before',pg_temp.evidence());
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select set_config('app.pt_member_command','book:'||pg_temp.gid(330)::text||':'||pg_temp.gid(201)::text,true);
select is(pg_temp.err($q$insert into public.pt_sessions(id,tenant_id,addon_order_id,trainer_staff_id,member_id,starts_at,ends_at) values(pg_temp.gid(330),pg_temp.gid(1),pg_temp.gid(201),pg_temp.gid(24),pg_temp.gid(31),pg_temp.slot(12),pg_temp.slot(12)+interval '1 hour')$q$),'42501','PTF-023: forged member book setting never bypasses direct session write policy');
select set_config('app.pt_member_command','cancel:'||pg_temp.gid(301)::text||':'||pg_temp.gid(201)::text,true);
select results_eq($q$with changed as(update public.pt_sessions set status='cancelled' where id=pg_temp.gid(301) returning id) select count(*)::integer from changed$q$,$q$select * from (values(0)) as expected$q$,'PTF-023: forged member cancel setting reaches no row under unchanged write RLS');
select results_eq($q$with changed as(update public.addon_orders set sessions_used=0 where id=pg_temp.gid(203) returning id) select count(*)::integer from changed$q$,$q$select * from (values(0)) as expected$q$,'PTF-023: forged member setting reaches no pack under unchanged write RLS');
select set_config('app.pt_member_command','',true);
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='direct_before'),'PTF-023: forged direct DML leaves sessions, usage, money, audit and notices unchanged');

-- Gym cancel/no-show use zero; availability/time off never rewrite bookings.
insert into pt_probe values('existing_session',(select to_jsonb(x) from public.pt_sessions x where id=pg_temp.gid(301)));
select pg_temp.claim();
set local role authenticated;
select is(public.set_trainer_availability(pg_temp.gid(24),'[]'),0,'PTF-006: empty array clears all availability');
insert into pt_probe values('booked_time_off',to_jsonb(public.add_trainer_time_off(pg_temp.gid(24),(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date,(pg_temp.slot(1) at time zone 'Asia/Kolkata')::date,'Existing booking stands')));
set local role postgres;
select is((select to_jsonb(x) from public.pt_sessions x where id=pg_temp.gid(301)),(select v from pt_probe where label='existing_session'),'PTF-006/007: availability replacement and new time off preserve existing reservation');
select pg_temp.claim('front_desk',23,null,903);
set local role authenticated;
select results_eq($q$select status::text collate "default",replayed from public.cancel_pt_session_as_gym(pg_temp.gid(301),'Desk operational reason')$q$,$q$select * from (values('cancelled_by_gym'::text collate "default",false)) as expected$q$,'PTF-015: front desk cancels gym-side with required reason');
set local role postgres;
select is((select sessions_used from public.addon_orders where id=pg_temp.gid(201)),0,'PTF-014/015: gym cancellation consumes zero');
select ok((select not consumed and not was_late and not completed_order and cancelled_by_staff_id=pg_temp.gid(23) from public.pt_cancellations where pt_session_id=pg_temp.gid(301)),'PTF-015: gym cancellation stores real staff actor and nonconsuming provenance');
insert into pt_probe values('gym_cancel_before',pg_temp.evidence());
select pg_temp.claim('front_desk',23,null,903);
set local role authenticated;
select ok((select replayed from public.cancel_pt_session_as_gym(pg_temp.gid(301),'Different valid replay reason')),'PTF-015: gym cancellation replay returns true');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='gym_cancel_before'),'PTF-015/025: gym cancellation retry emits no extra notice or audit');
select pg_temp.claim('trainer',24,null,904);
set local role authenticated;
select lives_ok($q$select public.finish_pt_session(pg_temp.gid(302),'no_show')$q$,'PTF-014: assigned trainer retains no-show command');
set local role postgres;
select is((select sessions_used from public.addon_orders where id=pg_temp.gid(202)),0,'PTF-014: no-show uses zero purchased sessions');
select pg_temp.claim('member',null,32,908);
set local role authenticated;
select is(pg_temp.err($q$select public.cancel_pt_booking(pg_temp.gid(302))$q$,true),'GL058:invalid_session_transition','PTF-013: no-show cannot be cancelled into another terminal outcome');
select is((select status::text from public.read_member_pt_sessions('history') where session_id=pg_temp.gid(302)),'no_show','PTF-005: member sees honest no-show vocabulary');
set local role postgres;

-- Trainer scoping and all four new table tenant/member read boundaries.
select set_config('request.jwt.claims','',true);
insert into public.trainer_profiles(tenant_id,staff_id,bio) values(pg_temp.gid(2),pg_temp.gid(26),'Foreign private biography');
insert into public.trainer_availability(tenant_id,staff_id,weekday,start_minute,end_minute) values(pg_temp.gid(2),pg_temp.gid(26),1,600,660);
insert into public.trainer_time_off(tenant_id,staff_id,starts_on,ends_on,created_by_staff_id) values(pg_temp.gid(2),pg_temp.gid(26),current_date+1,current_date+1,pg_temp.gid(26));
select pg_temp.claim();
set local role authenticated;
select is((select count(*)::integer from public.trainer_profiles where tenant_id=pg_temp.gid(2)),0,'PTF-020: front-office cannot read foreign profile');
select is((select count(*)::integer from public.trainer_availability where tenant_id=pg_temp.gid(2)),0,'PTF-020: front-office cannot read foreign windows');
select is((select count(*)::integer from public.trainer_time_off where tenant_id=pg_temp.gid(2)),0,'PTF-020: front-office cannot read foreign time off');
select is((select count(*)::integer from public.pt_cancellations where tenant_id=pg_temp.gid(2)),0,'PTF-020: front-office cannot read populated foreign cancellation history');
select ok((select count(*)>0 from public.pt_cancellations where tenant_id=pg_temp.gid(1)),'PTF-020: front-office can read its gym cancellation rows');
select is((select count(*)::integer from public.read_pt_packs(null,'expired') where order_id=pg_temp.gid(205)),1,'PTF-018/022: staff expired filter includes unspent active history');
set local role postgres;
select pg_temp.claim('trainer',24,null,904);
set local role authenticated;
select is((select count(*)::integer from public.trainer_profiles where staff_id<>pg_temp.gid(24)),0,'PTF-020: trainer profile table reads own row only');
select is((select count(*)::integer from public.trainer_availability where staff_id<>pg_temp.gid(24)),0,'PTF-020: trainer windows exclude other trainers');
select is((select count(*)::integer from public.trainer_time_off where staff_id<>pg_temp.gid(24)),0,'PTF-020: trainer time off excludes other trainers');
select is((select count(*)::integer from public.pt_cancellations where trainer_staff_id<>pg_temp.gid(24)),0,'PTF-020: trainer cancellation table excludes other trainers');
select is((select count(*)::integer from public.read_pt_packs(pg_temp.gid(25))),0,'PTF-022: other-trainer staff pack filter gives no rows');
select is((select count(*)::integer from public.read_pt_bookings(pg_temp.slot(0,0),pg_temp.slot(28,0),pg_temp.gid(25))),0,'PTF-022: other-trainer staff booking filter gives no rows');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is_empty($q$select * from public.trainer_profiles$q$,'PTF-020: members read no private profile rows directly');
select is_empty($q$select * from public.trainer_availability$q$,'PTF-020: members read no private availability rows directly');
select is_empty($q$select * from public.trainer_time_off$q$,'PTF-020: members read no private time-off reasons directly');
select is_empty($q$select * from public.pt_cancellations$q$,'PTF-020: members read no private cancellation reasons directly');
select is(pg_temp.err($q$select public.read_pt_packs()$q$),'42501','PTF-022: member cannot invoke staff read');
select is((select count(*)::integer from public.read_member_pt_sessions('history') where session_id=pg_temp.gid(302)),0,'PTF-021: another member terminal session never appears in own history');
set local role postgres;
select pg_temp.claim('gym_owner',21,null,901,1,true);
set local role authenticated;
select lives_ok($q$select public.read_pt_packs()$q$,'PTF-022: support owner preview may read pack view');
select is(pg_temp.err($q$select public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(25),null,'Preview forbidden')$q$),'42501','PTF-017/022: support preview cannot reassign');
set local role postgres;

-- Reassignment changes only the admitted trainer term; terminal history stays.
select set_config('request.jwt.claims','',true);
insert into pt_probe values('reassign_terms',(select to_jsonb(x)-array['trainer_staff_id','updated_at'] from public.addon_orders x where id=pg_temp.gid(201)));
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(24),array[pg_temp.gid(201)],'Same trainer')$q$,true),'22023:same_trainer','PTF-017: same-trainer request refused');
select is(pg_temp.err($q$select public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(27),array[pg_temp.gid(201)],'Inactive target')$q$,true),'GL055:trainer_unavailable','PTF-017: inactive target refused');
select is(pg_temp.err($q$select public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(28),array[pg_temp.gid(201)],'Other branch')$q$),'GL094','PTF-017: target branch mismatch refused');
select is(pg_temp.err($q$select public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(25),array[pg_temp.gid(201),pg_temp.gid(211)],'Foreign batch')$q$),'42501','PTF-017: one foreign order makes entire explicit batch unavailable');
select results_eq($q$select order_id,changed,cancelled_sessions from public.reassign_pt_packs(pg_temp.gid(24),pg_temp.gid(25),array[pg_temp.gid(201)],'Trainer change approved')$q$,$q$select pg_temp.gid(201),true,0$q$,'PTF-017: owner may reassign active pack to active all-branch trainer');
set local role postgres;
select is((select to_jsonb(x)-array['trainer_staff_id','updated_at'] from public.addon_orders x where id=pg_temp.gid(201)),(select v from pt_probe where label='reassign_terms'),'PTF-017/023: reassignment preserves sold money, count, validity and every other term');
select is((select trainer_staff_id from public.pt_sessions where id=pg_temp.gid(301)),pg_temp.gid(24),'PTF-017: old cancelled session keeps original trainer permanently');
select is((select trainer_staff_id from public.addon_orders where id=pg_temp.gid(201)),pg_temp.gid(25),'PTF-017: pack alone adopts new trainer');
select ok(coalesce(current_setting('app.pt_reassign_command',true),'')='','PTF-023: reassign command setting cleared after success');

-- Branch-local midnight differs from gym-local date: membership ends on the
-- gym day of this slot but not on its trainer-branch day, and must be refused.
select set_config('request.jwt.claims','',true);
insert into pt_probe values('branch_start',to_jsonb((((statement_timestamp() at time zone 'Pacific/Kiritimati')::date+10)+time '01:00') at time zone 'Pacific/Kiritimati'));
update public.members set branch_id=pg_temp.gid(13) where id=pg_temp.gid(31);
-- Historical membership-date fixture only; command assertions retain origin.
set local session_replication_role=replica;
update public.memberships set ends_on=((select (v#>>'{}')::timestamptz from pt_probe where label='branch_start') at time zone 'Pacific/Kiritimati')::date-1 where id=pg_temp.gid(51);
set local session_replication_role=origin;
select pg_temp.claim();
set local role authenticated;
select is(public.set_trainer_availability(pg_temp.gid(28),(select jsonb_agg(jsonb_build_object('weekday',n,'startMinute',0,'endMinute',1440)) from generate_series(0,6) n)),7,'PTF-006: branch trainer owns a full weekly grid');
set local role postgres;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(209),pg_temp.gid(354),(select (v#>>'{}')::timestamptz from pt_probe where label='branch_start'))$q$),'GL093','PTF-009: live membership tested on trainer branch day rather than earlier gym day');
set local role postgres;
-- Historical membership-date fixture only; command assertions retain origin.
set local session_replication_role=replica;
update public.memberships set ends_on=((select (v#>>'{}')::timestamptz from pt_probe where label='branch_start') at time zone 'Pacific/Kiritimati')::date where id=pg_temp.gid(51);
set local session_replication_role=origin;
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select lives_ok($q$select public.book_pt_session(pg_temp.gid(209),pg_temp.gid(354),(select (v#>>'{}')::timestamptz from pt_probe where label='branch_start'))$q$,'PTF-009: membership inclusive trainer-day endpoint accepts real booking');
select is((select timezone from public.read_member_pt_sessions('upcoming') where session_id=pg_temp.gid(354)),'Pacific/Kiritimati','PTF-005/008: read returns trainer branch timezone for accepted session');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(215),pg_temp.gid(355),pg_temp.slot(1))$q$,true),'GL058:session_outside_validity','PTF-009/016: restored last-day capacity never extends original sold expiry');
set local role postgres;
update public.members set branch_id=pg_temp.gid(11) where id=pg_temp.gid(31);
-- Historical membership-date fixture only; command assertions retain origin.
set local session_replication_role=replica;
update public.memberships set ends_on=app.gym_today(pg_temp.gid(1))+90 where id=pg_temp.gid(51);
set local session_replication_role=origin;
select is_empty($q$select id from public.audit_log where tenant_id=pg_temp.gid(1) and action='trainer_profile.updated' and (before ?| array['bio','photo_asset_id','object_key','email','phone'] or after ?| array['bio','photo_asset_id','object_key','email','phone'])$q$,'PTF-024: profile audit summaries contain no biography, photo storage or contact data');
select is(pg_temp.err($q$select app.pt_audit(pg_temp.gid(1),null,null,'unapproved.action','pt_session',pg_temp.gid(999),null,null,null)$q$),'22023','PTF-024: private audit allowlist refuses arbitrary action');

insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.gid(910),'super_admin','PT platform','platform73@example.test',true),(pg_temp.gid(911),'platform_support','PT support','support73@example.test',true);
select pg_temp.claim('super_admin',null,null,910);
set local role authenticated;
select ok(exists(select 1 from public.trainer_profiles where tenant_id=pg_temp.gid(2)),'PTF-020: platform explicit read policy sees foreign profile');
select is(pg_temp.err($q$select public.set_pt_policy(24,true,60)$q$),'42501','PTF-019: platform cannot mutate gym policy');
select is(pg_temp.err($q$select public.read_pt_bookings(pg_temp.slot(0),pg_temp.slot(2))$q$),'42501','PTF-022: platform cannot invoke real-staff booking projection');
set local role postgres;
select pg_temp.claim('platform_support',null,null,911);
set local role authenticated;
select ok(exists(select 1 from public.pt_cancellations where tenant_id=pg_temp.gid(2)),'PTF-020: support explicit read policy sees foreign cancellation');
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(309),'Platform forbidden')$q$),'42501','PTF-016: platform support cannot waive');
set local role postgres;

-- Throttle counts actual booking audits plus synthetic recent history to ten;
-- replay wins before throttle and first failure remains rate limit.
select set_config('request.jwt.claims','',true);
insert into public.audit_log(id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,after,occurred_at)
select pg_temp.gid(9000+n),pg_temp.gid(1),pg_temp.gid(907),'member','pt_session.booked','pt_session',pg_temp.gid(9100+n),'{}',statement_timestamp() from generate_series(1,greatest(10-(select count(*)::integer from public.audit_log where actor_user_id=pg_temp.gid(907) and action='pt_session.booked' and occurred_at>statement_timestamp()-interval '24 hours'),0)) n;
insert into pt_probe values('throttle_before',pg_temp.evidence());
select pg_temp.claim('member',null,31,907);
set local role authenticated;
select ok((select replayed from public.book_pt_session(pg_temp.gid(203),pg_temp.gid(306),pg_temp.slot(5))),'PTF-012: genuine request replay is never throttled at ten recent bookings');
select is(pg_temp.err($q$select public.book_pt_session(pg_temp.gid(201),pg_temp.gid(340),statement_timestamp()-interval '1 minute')$q$),'GL097','PTF-009/012: throttle precedes pack/date/slot failures for fresh request');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='throttle_before'),'PTF-012: throttled attempt and replay write no audit, notice, payment or capacity');

-- The exceptional completed->active edge must also be atomic, not merely the
-- ordinary active-pack decrement tested above. Real second forfeiture 309 is
-- still unwaived and completed its order through the actual member command.
insert into pt_probe values('completed_atomic_before',pg_temp.evidence());
create trigger pt73_reject_waiver_audit before insert on public.audit_log for each row when(new.tenant_id='73000000-0000-4000-8000-000000000001'::uuid and new.action='pt_forfeit.waived') execute function pg_temp.reject_waiver_audit();
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(309),'Completed audit must succeed')$q$),'Z7301','PTF-016/024: completed-pack restoration fails atomically when audit fails');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='completed_atomic_before'),'PTF-016: completed audit failure restores terminal status, full count, cause and waiver fields');
drop trigger pt73_reject_waiver_audit on public.audit_log;
create trigger pt73_reject_waiver_notice before insert on public.notifications for each row when(new.tenant_id='73000000-0000-4000-8000-000000000001'::uuid and new.template_key='pt_forfeit_waived') execute function pg_temp.reject_waiver_notice();
select pg_temp.claim();
set local role authenticated;
select is(pg_temp.err($q$select public.waive_pt_forfeit(pg_temp.gid(309),'Completed notice must succeed')$q$),'Z7302','PTF-016/025: completed-pack restoration fails atomically when notice fails');
set local role postgres;
select is(pg_temp.evidence(),(select v from pt_probe where label='completed_atomic_before'),'PTF-016: completed notice failure rolls back guard-admitted reactivation and audit');
drop trigger pt73_reject_waiver_notice on public.notifications;

select * from finish();
rollback;
