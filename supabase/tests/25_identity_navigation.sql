-- NAV-001..005/007 preview boundary: independently authored from dc391b4.
-- No NAV-006/008 organization eligibility changes are assumed here.
begin;
set local role postgres;
select plan(25);

insert into public.organizations(id,name,gym_code) values
 ('a6500000-0000-4000-8000-000000000001','Visible navigation A','V25AAA'),
 ('a6500000-0000-4000-8000-000000000002','Visible navigation B','V25BBB');
insert into public.branches(id,tenant_id,name,is_default) values
 ('a6500000-0000-4000-8000-000000000011','a6500000-0000-4000-8000-000000000001','A',true),
 ('a6500000-0000-4000-8000-000000000012','a6500000-0000-4000-8000-000000000002','B',true);
insert into auth.users(id,raw_app_meta_data) values
 ('a6500000-0000-4000-8000-0000000000a1','{}'),
 ('a6500000-0000-4000-8000-0000000000a2','{}'),
 ('a6500000-0000-4000-8000-0000000000a3','{"active_tenant_id":"a6500000-0000-4000-8000-000000000002"}'),
 ('a6500000-0000-4000-8000-0000000000a4','{}'),
 ('a6500000-0000-4000-8000-0000000000a5','{}'),
 ('a6500000-0000-4000-8000-0000000000a6','{}');
insert into public.platform_users(user_id,role,full_name,email) values
 ('a6500000-0000-4000-8000-0000000000a1','super_admin','Visible root','v25root@gymloop.test'),
 ('a6500000-0000-4000-8000-0000000000a2','platform_support','Visible support','v25support@gymloop.test');
insert into public.staff(id,tenant_id,user_id,role,full_name,is_active,created_at) values
 ('a6500000-0000-4000-8000-000000000021','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-0000000000a3','trainer','Earlier',true,'2026-01-01T00:00:00Z'),
 ('a6500000-0000-4000-8000-000000000022','a6500000-0000-4000-8000-000000000002','a6500000-0000-4000-8000-0000000000a3','gym_manager','Requested',true,'2026-02-01T00:00:00Z'),
 ('a6500000-0000-4000-8000-000000000023','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-0000000000a5','front_desk','Inactive',false,'2026-01-01T00:00:00Z');
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone) values
 ('a6500000-0000-4000-8000-000000000031','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-000000000011','a6500000-0000-4000-8000-0000000000a1','Root also member','+916500000031'),
 ('a6500000-0000-4000-8000-000000000032','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-000000000011','a6500000-0000-4000-8000-0000000000a3','Staff also member','+916500000032'),
 ('a6500000-0000-4000-8000-000000000033','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-000000000011','a6500000-0000-4000-8000-0000000000a4','Member only','+916500000033'),
 ('a6500000-0000-4000-8000-000000000034','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-000000000011','a6500000-0000-4000-8000-0000000000a5','Inactive staff member','+916500000034'),
 ('a6500000-0000-4000-8000-000000000035','a6500000-0000-4000-8000-000000000002','a6500000-0000-4000-8000-000000000012',null,'Other gym','+916500000035');

-- Test-owned input constructor; all reserved/custom claims must survive exactly.
create function pg_temp.navigation_event(who text) returns jsonb language sql as $$
 select jsonb_build_object('user_id',who,'claims',jsonb_build_object(
  'sub',who,'aud','authenticated','role','authenticated','iss','https://auth.example',
  'exp',1999999999,'iat',1999999000,'aal','aal2','email','visible@example.test',
  'session_id','a6500000-0000-4000-8000-000000000099','custom',jsonb_build_object('keep',true),
  'app_role','super_admin','tenant_id','a6500000-0000-4000-8000-000000000002',
  'staff_id','a6500000-0000-4000-8000-000000000021',
  'member_id','a6500000-0000-4000-8000-000000000031',
  'impersonation_session_id','a6500000-0000-4000-8000-000000000051'))
$$;
create temporary table navigation_expected(who text, expected jsonb);
insert into navigation_expected values
 ('a6500000-0000-4000-8000-0000000000a1','{"app_role":"super_admin"}'),
 ('a6500000-0000-4000-8000-0000000000a2','{"app_role":"platform_support"}'),
 ('a6500000-0000-4000-8000-0000000000a3','{"app_role":"gym_manager","tenant_id":"a6500000-0000-4000-8000-000000000002","staff_id":"a6500000-0000-4000-8000-000000000022"}'),
 ('a6500000-0000-4000-8000-0000000000a4','{"app_role":"member","tenant_id":"a6500000-0000-4000-8000-000000000001","member_id":"a6500000-0000-4000-8000-000000000033"}'),
 ('a6500000-0000-4000-8000-0000000000a5','{}'),
 ('a6500000-0000-4000-8000-0000000000a6','{}'),
 ('invalid-user-id','{}');
select is(app.custom_access_token_hook(pg_temp.navigation_event(who))->'claims',
 ((pg_temp.navigation_event(who)->'claims') - array['app_role','tenant_id','staff_id','member_id','impersonation_session_id']) || expected,
 'NAV-007 cleaned complete claims, precedence/fallback, reserved preservation: ' || who)
from navigation_expected order by who;

update auth.users set raw_app_meta_data='{}' where id='a6500000-0000-4000-8000-0000000000a3';
select is(app.custom_access_token_hook(pg_temp.navigation_event('a6500000-0000-4000-8000-0000000000a3'))->'claims'->>'staff_id',
 'a6500000-0000-4000-8000-000000000021','NAV-007 no request preserves earliest active staff default');
update auth.users set raw_app_meta_data='{"active_tenant_id":"a6500000-0000-4000-8000-000000000099"}' where id='a6500000-0000-4000-8000-0000000000a3';
select is(app.custom_access_token_hook(pg_temp.navigation_event('a6500000-0000-4000-8000-0000000000a3'))->'claims'->>'staff_id',
 'a6500000-0000-4000-8000-000000000021','NAV-007 invalid requested tenant preserves deterministic default');
select ok(has_function_privilege('supabase_auth_admin','app.custom_access_token_hook(jsonb)','EXECUTE')
 and not has_function_privilege('authenticated','app.custom_access_token_hook(jsonb)','EXECUTE')
 and not has_function_privilege('anon','app.custom_access_token_hook(jsonb)','EXECUTE'), 'hook Auth-only execution preserved');
select ok((select p.prosecdef and exists(select 1 from unnest(p.proconfig) setting where setting in ('search_path=','search_path=""'))
 from pg_proc p where p.oid='app.custom_access_token_hook(jsonb)'::regprocedure),'hook definer and empty search path preserved');

insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,expires_at) values
 ('a6500000-0000-4000-8000-000000000051','a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-0000000000a1','Visible preview contract',now()+interval '1 hour');
select is(app.custom_access_token_hook(pg_temp.navigation_event('a6500000-0000-4000-8000-0000000000a1'))->'claims',
 ((pg_temp.navigation_event('a6500000-0000-4000-8000-0000000000a1')->'claims') - array['app_role','tenant_id','staff_id','member_id','impersonation_session_id'])
 || '{"app_role":"gym_owner","tenant_id":"a6500000-0000-4000-8000-000000000001","impersonation_session_id":"a6500000-0000-4000-8000-000000000051"}'::jsonb,
 'preview replaces stale platform/staff/member facts and preserves reserved claims');

-- One shared private invoker BEFORE guard must cover every actual writable table
-- and every granted DML operation; the own-session table has its existing guard.
select ok(exists(
 select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='app' and not p.prosecdef and p.prorettype='trigger'::regtype
 and not exists (
  select 1 from pg_class c join pg_namespace cn on cn.oid=c.relnamespace
  where cn.nspname='public' and c.relkind in ('r','p') and c.relname<>'impersonation_sessions'
  and (has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE')
    or has_any_column_privilege('authenticated',c.oid,'INSERT,UPDATE'))
  and not exists (select 1 from pg_trigger t where t.tgrelid=c.oid and t.tgfoid=p.oid
    and not t.tgisinternal and t.tgenabled in ('O','A') and (t.tgtype::integer & 3)=3
    and (not (has_table_privilege('authenticated',c.oid,'INSERT') or has_any_column_privilege('authenticated',c.oid,'INSERT')) or (t.tgtype::integer & 4)=4)
    and (not (has_table_privilege('authenticated',c.oid,'UPDATE') or has_any_column_privilege('authenticated',c.oid,'UPDATE')) or (t.tgtype::integer & 16)=16)
    and (not has_table_privilege('authenticated',c.oid,'DELETE') or (t.tgtype::integer & 8)=8))
  )
), 'NAV-003 metadata: private invoker BEFORE guard covers all authenticated-writable public tables and granted operations');

select set_config('request.jwt.claims','{"sub":"a6500000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","tenant_id":"a6500000-0000-4000-8000-000000000001","impersonation_session_id":"a6500000-0000-4000-8000-000000000051"}',true);
set local role authenticated;
select is((select count(*) from public.members where tenant_id='a6500000-0000-4000-8000-000000000001'),4::bigint,'preview retains same-tenant member reads');
select is((select count(*) from public.members where id='a6500000-0000-4000-8000-000000000035'),0::bigint,'preview reveals no other gym member');
select throws_ok($$update public.members set full_name='forged' where id='a6500000-0000-4000-8000-000000000033'$$,'42501',null,'preview cannot directly edit member');
select throws_ok($$insert into public.members(tenant_id,branch_id,full_name,phone) values ('a6500000-0000-4000-8000-000000000001','a6500000-0000-4000-8000-000000000011','forged','+916500000099')$$,'42501',null,'preview cannot directly insert member');
select throws_ok($$update public.organizations set name='forged' where id='a6500000-0000-4000-8000-000000000001'$$,'42501',null,'preview cannot mutate an otherwise owner-writable organization');
select throws_ok($$update public.branches set name='forged' where id='a6500000-0000-4000-8000-000000000011'$$,'42501',null,'preview cannot mutate branch');
select throws_ok($$update public.impersonation_sessions set reason='forged' where id='a6500000-0000-4000-8000-000000000051'$$,'42501',null,'own-end exception cannot edit reason');
select lives_ok($$update public.impersonation_sessions set ended_at=now() where id='a6500000-0000-4000-8000-000000000051'$$,'preview can end exact own session');
set local role postgres;
select ok((select ended_at is not null from public.impersonation_sessions where id='a6500000-0000-4000-8000-000000000051'),'own-end persisted');
select is((select count(*) from public.audit_log where record_id='a6500000-0000-4000-8000-000000000051' and action='impersonation_session.ended'),1::bigint,'own-end audit preserved once');
select is((select full_name from public.members where id='a6500000-0000-4000-8000-000000000033'),'Member only','refused member write left original fact');
select is(app.custom_access_token_hook(pg_temp.navigation_event('a6500000-0000-4000-8000-0000000000a1'))->'claims'->>'app_role','super_admin','end restores platform identity');
select * from finish();
rollback;
