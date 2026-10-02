-- Independent contract-derived STI holdout; no implementation or other test suite consulted.
begin;
set local search_path = public, extensions;
select plan(158);
set local session_replication_role = replica;

insert into public.organizations(id,name,gym_code,status) values ('68900000-0000-0000-0000-000000000100','H68 Gym A','H68AAA','active'),('68900000-0000-0000-0000-000000000101','H68 Gym B','H68BBB','active');

insert into public.branches(id,tenant_id,name) values ('68900000-0000-0000-0000-000000000110','68900000-0000-0000-0000-000000000100','H68 A'),('68900000-0000-0000-0000-000000000111','68900000-0000-0000-0000-000000000101','H68 B');

insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) select ('68900000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid, 'h68-'||i||'@example.com',now(), '{}'::jsonb from generate_series(1,30) i;

insert into auth.identities(id,user_id,provider_id,provider,identity_data) select gen_random_uuid(),id,id::text,'google',jsonb_build_object('sub',id::text,'email',email) from auth.users where id::text like '68900000-%';

insert into public.staff(id,tenant_id,user_id,role,full_name,email,is_active) values ('68900000-0000-0000-0000-000000000201','68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000001','gym_owner','H68 Owner','h68-1@example.com',true),('68900000-0000-0000-0000-000000000202','68900000-0000-0000-0000-000000000101','68900000-0000-0000-0000-000000000002','gym_owner','H68 Other Owner','h68-2@example.com',true),('68900000-0000-0000-0000-000000000203','68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000003','gym_manager','H68 Manager','h68-3@example.com',true),('68900000-0000-0000-0000-000000000204','68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000004','front_desk','H68 Desk','h68-4@example.com',true),('68900000-0000-0000-0000-000000000205','68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000005','trainer','H68 Trainer','h68-5@example.com',true);

insert into public.staff(id,tenant_id,role,full_name,email) select ('68900000-0000-0000-0000-'||lpad((300+i)::text,12,'0'))::uuid,'68900000-0000-0000-0000-000000000100','front_desk','H68 Candidate '||i,'h68-'||i||'@example.com' from generate_series(6,30) i;

insert into public.staff(id,tenant_id,role,full_name,email,is_active) values ('68900000-0000-0000-0000-000000000400','68900000-0000-0000-0000-000000000100','trainer','H68 Inactive',' Taken@Example.com ',false),('68900000-0000-0000-0000-000000000401','68900000-0000-0000-0000-000000000100','front_desk','H68 No Email',null,true),('68900000-0000-0000-0000-000000000402','68900000-0000-0000-0000-000000000101','trainer','H68 Foreign','foreign@example.com',true),('68900000-0000-0000-0000-000000000403','68900000-0000-0000-0000-000000000100','gym_owner','H68 Unlinked Owner','owner@example.com',true);

insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,email,status) values ('68900000-0000-0000-0000-000000000500','68900000-0000-0000-0000-000000000101','68900000-0000-0000-0000-000000000111','68900000-0000-0000-0000-000000000012','H68 Bound Member','+916890000012','h68-12@example.com','blocked'),('68900000-0000-0000-0000-000000000501','68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000110',null,'H68 Race Member','+916890000019','h68-19@example.com','active');

insert into public.platform_users(user_id,role,full_name,email,is_active) values ('68900000-0000-0000-0000-000000000013','platform_support','H68 Platform','h68-13@example.com',false),('68900000-0000-0000-0000-000000000014','super_admin','H68 Admin','h68-14@example.com',true);

set local session_replication_role = origin;

select ok((not has_table_privilege('authenticated','public.staff_invites','INSERT')), 'STI-011 authenticated has no INSERT privilege');

select ok((not has_table_privilege('authenticated','public.staff_invites','UPDATE')), 'STI-011 authenticated has no UPDATE privilege');

select ok((not has_table_privilege('authenticated','public.staff_invites','DELETE')), 'STI-011 authenticated has no DELETE privilege');

select ok(((select relrowsecurity from pg_class where oid='public.staff_invites'::regclass)), 'STI-011 RLS enabled');

select ok((has_function_privilege('authenticated','public.invite_staff_member(text,text,text,public.app_role,uuid,text)','EXECUTE')), 'invite_staff_member authenticated execute');

select ok((not has_function_privilege('service_role','public.invite_staff_member(text,text,text,public.app_role,uuid,text)','EXECUTE')), 'invite_staff_member service role has no execute');

select ok((has_function_privilege('anon','public.invite_staff_member(text,text,text,public.app_role,uuid,text)','EXECUTE') = false), 'invite_staff_member anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.invite_staff_member(text,text,text,public.app_role,uuid,text)'::regprocedure)), 'invite_staff_member definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.invite_staff_member(text,text,text,public.app_role,uuid,text)'::regprocedure), 'v', 'invite_staff_member volatility');

select ok((has_function_privilege('authenticated','public.issue_staff_invite(uuid,text)','EXECUTE')), 'issue_staff_invite authenticated execute');

select ok((not has_function_privilege('service_role','public.issue_staff_invite(uuid,text)','EXECUTE')), 'issue_staff_invite service role has no execute');

select ok((has_function_privilege('anon','public.issue_staff_invite(uuid,text)','EXECUTE') = false), 'issue_staff_invite anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.issue_staff_invite(uuid,text)'::regprocedure)), 'issue_staff_invite definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.issue_staff_invite(uuid,text)'::regprocedure), 'v', 'issue_staff_invite volatility');

select ok((has_function_privilege('authenticated','public.revoke_staff_invite(uuid)','EXECUTE')), 'revoke_staff_invite authenticated execute');

select ok((not has_function_privilege('service_role','public.revoke_staff_invite(uuid)','EXECUTE')), 'revoke_staff_invite service role has no execute');

select ok((has_function_privilege('anon','public.revoke_staff_invite(uuid)','EXECUTE') = false), 'revoke_staff_invite anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.revoke_staff_invite(uuid)'::regprocedure)), 'revoke_staff_invite definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.revoke_staff_invite(uuid)'::regprocedure), 'v', 'revoke_staff_invite volatility');

select ok((has_function_privilege('authenticated','public.redeem_staff_invite(text)','EXECUTE')), 'redeem_staff_invite authenticated execute');

select ok((not has_function_privilege('service_role','public.redeem_staff_invite(text)','EXECUTE')), 'redeem_staff_invite service role has no execute');

select ok((has_function_privilege('anon','public.redeem_staff_invite(text)','EXECUTE') = false), 'redeem_staff_invite anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.redeem_staff_invite(text)'::regprocedure)), 'redeem_staff_invite definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.redeem_staff_invite(text)'::regprocedure), 'v', 'redeem_staff_invite volatility');

select ok((has_function_privilege('authenticated','public.peek_staff_invite(text)','EXECUTE')), 'peek_staff_invite authenticated execute');

select ok((not has_function_privilege('service_role','public.peek_staff_invite(text)','EXECUTE')), 'peek_staff_invite service role has no execute');

select ok((has_function_privilege('anon','public.peek_staff_invite(text)','EXECUTE') = true), 'peek_staff_invite anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.peek_staff_invite(text)'::regprocedure)), 'peek_staff_invite definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.peek_staff_invite(text)'::regprocedure), 's', 'peek_staff_invite volatility');

select ok((has_function_privilege('authenticated','public.unlink_staff_identity(uuid,text)','EXECUTE')), 'unlink_staff_identity authenticated execute');

select ok((not has_function_privilege('service_role','public.unlink_staff_identity(uuid,text)','EXECUTE')), 'unlink_staff_identity service role has no execute');

select ok((has_function_privilege('anon','public.unlink_staff_identity(uuid,text)','EXECUTE') = false), 'unlink_staff_identity anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.unlink_staff_identity(uuid,text)'::regprocedure)), 'unlink_staff_identity definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.unlink_staff_identity(uuid,text)'::regprocedure), 'v', 'unlink_staff_identity volatility');

select ok((has_function_privilege('authenticated','public.read_staff_app_access(uuid)','EXECUTE')), 'read_staff_app_access authenticated execute');

select ok((not has_function_privilege('service_role','public.read_staff_app_access(uuid)','EXECUTE')), 'read_staff_app_access service role has no execute');

select ok((has_function_privilege('anon','public.read_staff_app_access(uuid)','EXECUTE') = false), 'read_staff_app_access anon grant exact');

select ok(((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.read_staff_app_access(uuid)'::regprocedure)), 'read_staff_app_access definer empty search path');

select is((select provolatile::text from pg_proc where oid='public.read_staff_app_access(uuid)'::regprocedure), 's', 'read_staff_app_access volatility');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select is((select state from public.read_staff_app_access('68900000-0000-0000-0000-000000000306')), 'not_invited', 'STI-009 pristine row');

select is((select state from public.read_staff_app_access('68900000-0000-0000-0000-000000000201')), 'linked', 'STI-009 linked owner precedence');

select is((select linked_at from public.read_staff_app_access('68900000-0000-0000-0000-000000000201')), null::timestamptz, 'STI-009 operator owner has no invite linked time');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000402','bad')$q$, '42501', null, 'STI-002 foreign target before malformed hash');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000999','bad')$q$, '42501', null, 'STI-002 unknown same refusal');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000306',null)$q$, '22023', null, 'STI-002 null hash');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000306',upper(md5('h68-1') || md5('h68-tail-1')))$q$, '22023', null, 'STI-002 uppercase hash');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000400',md5('h68-400') || md5('h68-tail-400'))$q$, 'GL075', null, 'STI-002 inactive');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000403',md5('h68-403') || md5('h68-tail-403'))$q$, 'GL075', null, 'STI-002 owner');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000203',md5('h68-203') || md5('h68-tail-203'))$q$, 'GL077', null, 'STI-002 bound');

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000401',md5('h68-401') || md5('h68-tail-401'))$q$, 'GL076', null, 'STI-002 missing email');

select throws_ok($q$select * from public.invite_staff_member('Name','x@example.com',null,'gym_owner',null,md5('h68-60') || md5('h68-tail-60'))$q$, 'GL082', null, 'STI-001 owner creation prohibited');

select throws_ok($q$select * from public.invite_staff_member('Name','   ',null,'trainer',null,md5('h68-61') || md5('h68-tail-61'))$q$, 'GL076', null, 'STI-001 blank create email');

select throws_ok($q$select * from public.invite_staff_member('Name','taken@example.com',null,'trainer',null,md5('h68-62') || md5('h68-tail-62'))$q$, 'GL081', null, 'STI-001 inactive normalized duplicate');

select throws_ok($q$select * from public.invite_staff_member('Name','new@example.com',null,'trainer','68900000-0000-0000-0000-000000000111',md5('h68-63') || md5('h68-tail-63'))$q$, '42501', null, 'STI-001 foreign branch');

create temporary table h68_created as select * from public.invite_staff_member('H68 New','create@example.com',null,'gym_manager',null,md5('h68-64') || md5('h68-tail-64'));

reset role;

select ok((exists(select 1 from public.staff s join h68_created c on c.staff_id=s.id where s.user_id is null and s.is_active and s.role='gym_manager' and s.branch_id is null)), 'STI-001 create active unlinked owner-chosen role');

select ok((exists(select 1 from audit_log a join h68_created c on c.staff_id=a.record_id where action='staff.invited' and record_type='staff' and actor_role='gym_owner' and a.before is null and a.after = jsonb_build_object('role','gym_manager','branch_id',null))), 'STI-010 create audit exact');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

create temporary table h68_first as select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000306',md5('h68-6') || md5('h68-tail-6'));

reset role;

select ok((exists(select 1 from staff_invites i join h68_first f on f.invite_id=i.id where i.status='pending' and i.expires_at=i.issued_at+interval '48 hours' and i.issued_by_staff_id='68900000-0000-0000-0000-000000000201' and i.closed_at is null)), 'STI-002 pending hash-only issue expiry');

update staff_invites set issued_at=statement_timestamp()-interval '49 hours',expires_at=statement_timestamp()-interval '1 hour' where id=(select invite_id from h68_first);

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select is((select state from public.read_staff_app_access('68900000-0000-0000-0000-000000000306')), 'invite_expired', 'STI-009 derived expiry');

create temporary table h68_second as select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000306',md5('h68-66') || md5('h68-tail-66'));

select is((select superseded_invite_id from h68_second), (select invite_id from h68_first), 'STI-002 resend expired pending returns replaced id');

reset role;

select ok((exists(select 1 from staff_invites where id=(select invite_id from h68_first) and status='superseded' and closed_at is not null)), 'STI-002 resend closes prior invite');

select is((select count(*) from staff_invites where staff_id='68900000-0000-0000-0000-000000000306' and status='pending'), 1::bigint, 'STI-002 only one pending');

select ok((exists(select 1 from audit_log where action='staff_invite.superseded' and record_id=(select invite_id from h68_first) and before='{"status":"pending"}'::jsonb and after=jsonb_build_object('status','superseded','replaced_by',(select invite_id from h68_second)))), 'STI-010 supersede audit shape');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select is((select state from public.read_staff_app_access('68900000-0000-0000-0000-000000000306')), 'invite_pending', 'STI-009 pending read');

select public.revoke_staff_invite((select invite_id from h68_second));

select throws_ok($q$select public.revoke_staff_invite((select invite_id from h68_second))$q$, 'GL079', null, 'STI-002 second revoke refused');

select is((select state from public.read_staff_app_access('68900000-0000-0000-0000-000000000306')), 'not_invited', 'STI-009 revoked newest counts as none');

reset role;

select ok((exists(select 1 from staff_invites where id=(select invite_id from h68_second) and status='revoked' and closed_by_staff_id='68900000-0000-0000-0000-000000000201' and closed_at is not null)), 'STI-002 revoke stamps owner');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000003','role','authenticated','app_role','gym_manager','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000203')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-93') || md5('h68-tail-93'))$q$, '42501', null, 'STI-002 gym_manager cannot issue');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 gym_manager cannot command-read');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','reason')$q$, '42501', null, 'STI-008 gym_manager cannot unlink');

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 0::bigint, 'STI-011 gym_manager direct RLS read');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000004','role','authenticated','app_role','front_desk','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000204')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-94') || md5('h68-tail-94'))$q$, '42501', null, 'STI-002 front_desk cannot issue');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 front_desk cannot command-read');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','reason')$q$, '42501', null, 'STI-008 front_desk cannot unlink');

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 0::bigint, 'STI-011 front_desk direct RLS read');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000005','role','authenticated','app_role','trainer','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000205')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-95') || md5('h68-tail-95'))$q$, '42501', null, 'STI-002 trainer cannot issue');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 trainer cannot command-read');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','reason')$q$, '42501', null, 'STI-008 trainer cannot unlink');

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 0::bigint, 'STI-011 trainer direct RLS read');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000012','role','authenticated','app_role','member','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000999')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-102') || md5('h68-tail-102'))$q$, '42501', null, 'STI-002 member cannot issue');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 member cannot command-read');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','reason')$q$, '42501', null, 'STI-008 member cannot unlink');

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 0::bigint, 'STI-011 member direct RLS read');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000014','role','authenticated','app_role','super_admin','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000999')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-104') || md5('h68-tail-104'))$q$, '42501', null, 'STI-002 super_admin cannot issue');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 super_admin cannot command-read');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','reason')$q$, '42501', null, 'STI-008 super_admin cannot unlink');

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 3::bigint, 'STI-011 super_admin direct RLS read');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000002','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000101','staff_id','68900000-0000-0000-0000-000000000202')::text, true);

set local role authenticated;

select is((select count(*) from staff_invites where tenant_id='68900000-0000-0000-0000-000000000100'), 0::bigint, 'STI-011 foreign owner reads nothing');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201','impersonation_session_id','68900000-0000-0000-0000-000000000777')::text, true);

set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-97') || md5('h68-tail-97'))$q$, '42501', null, 'STI-002 preview issue denied');

select throws_ok($q$select * from public.read_staff_app_access('68900000-0000-0000-0000-000000000307')$q$, '42501', null, 'STI-009 preview read command denied');

select throws_ok($q$select * from public.redeem_staff_invite(md5('h68-66') || md5('h68-tail-66'))$q$, '42501', null, 'STI-004 preview redeem denied');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000307',md5('h68-7') || md5('h68-tail-7'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000308',md5('h68-8') || md5('h68-tail-8'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000309',md5('h68-9') || md5('h68-tail-9'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000310',md5('h68-10') || md5('h68-tail-10'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000311',md5('h68-11') || md5('h68-tail-11'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000312',md5('h68-12') || md5('h68-tail-12'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000313',md5('h68-13') || md5('h68-tail-13'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000314',md5('h68-14') || md5('h68-tail-14'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000315',md5('h68-15') || md5('h68-tail-15'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000316',md5('h68-16') || md5('h68-tail-16'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000317',md5('h68-17') || md5('h68-tail-17'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000318',md5('h68-18') || md5('h68-tail-18'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000319',md5('h68-19') || md5('h68-tail-19'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000320',md5('h68-20') || md5('h68-tail-20'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000321',md5('h68-21') || md5('h68-tail-21'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-22') || md5('h68-tail-22'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000323',md5('h68-23') || md5('h68-tail-23'));

reset role;

update auth.users set email='auth-user-wrong@example.com' where id='68900000-0000-0000-0000-000000000007';

update auth.identities set identity_data=jsonb_build_object('sub',user_id::text,'email',' H68-7@EXAMPLE.COM ') where user_id='68900000-0000-0000-0000-000000000007' and provider='google';

update auth.users set email_confirmed_at=null where id='68900000-0000-0000-0000-000000000008';

insert into auth.identities(id,user_id,provider_id,provider,identity_data) values(gen_random_uuid(),'68900000-0000-0000-0000-000000000009','68900000-0000-0000-0000-000000000009','email',jsonb_build_object('sub','68900000-0000-0000-0000-000000000009','email','h68-9@example.com'));

insert into auth.identities(id,user_id,provider_id,provider,identity_data) values(gen_random_uuid(),'68900000-0000-0000-0000-000000000010','68900000-0000-0000-0000-000000000010','email',jsonb_build_object('sub','68900000-0000-0000-0000-000000000010','email','h68-10@example.com'));

update auth.users set raw_app_meta_data='{"gymloop_provisioned":true}'::jsonb where id='68900000-0000-0000-0000-000000000010';

insert into auth.sessions(id,user_id,created_at,updated_at) values('68900000-0000-0000-0000-000000000600','68900000-0000-0000-0000-000000000007',now(),now());

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000007','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'linked', 'STI-004 caller 7 linked');

reset role;

select is((select user_id from staff where id='68900000-0000-0000-0000-000000000307'), '68900000-0000-0000-0000-000000000007'::uuid, 'STI-004 link identity');

select ok((exists(select 1 from staff where id='68900000-0000-0000-0000-000000000307' and role='front_desk' and full_name='H68 Candidate 7' and email='h68-7@example.com' and branch_id is null and is_active)), 'STI-005 redemption changes binding only');

select is((select count(*) from auth.sessions where user_id='68900000-0000-0000-0000-000000000007'), 0::bigint, 'STI-006 link revokes existing sessions');

select is((select current_setting('app.staff_binding_command',true)), '', 'STI-006 link setting reset');

select ok((exists(select 1 from pg_locks where locktype='advisory' and pid=pg_backend_pid() and granted and objsubid=1 and classid=((hashtextextended('identity-bind:'||'68900000-0000-0000-0000-000000000007'::text,0)>>32)&4294967295)::oid and objid=(hashtextextended('identity-bind:'||'68900000-0000-0000-0000-000000000007'::text,0)&4294967295)::oid)), 'STI-004 shared identity advisory lock observable');

select is((select app.custom_access_token_hook(jsonb_build_object('user_id','68900000-0000-0000-0000-000000000007','claims','{}'::jsonb))->'claims'->>'app_role'), 'front_desk', 'STI-005 hook owner-selected role');

select is((select app.custom_access_token_hook(jsonb_build_object('user_id','68900000-0000-0000-0000-000000000007','claims','{}'::jsonb))->'claims'->>'staff_id'), '68900000-0000-0000-0000-000000000307', 'STI-005 hook staff id');

select ok((exists(select 1 from audit_log where action='staff.linked' and record_id='68900000-0000-0000-0000-000000000307' and actor_user_id='68900000-0000-0000-0000-000000000007' and actor_role='front_desk' and record_type='staff' and before='{"user_linked":false}'::jsonb and after @> '{"user_linked":true,"via":"invite","role":"front_desk"}'::jsonb)), 'STI-010 staff link audit role');

create temporary table h68_audit_before as select count(*) n from audit_log where actor_user_id='68900000-0000-0000-0000-000000000007';
grant select on h68_audit_before to authenticated;

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000007','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'already_linked_here', 'STI-004 caller 7 already_linked_here');

select is((select gym_name from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'H68 Gym A', 'STI-004 replay returns gym');

select is((select staff_role::text from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'front_desk', 'STI-004 replay returns role');

reset role;

select is((select count(*) from audit_log where actor_user_id='68900000-0000-0000-0000-000000000007'), (select n from h68_audit_before), 'STI-004 replay makes no audit write');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000008','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-8') || md5('h68-tail-8'))), 'identity_unverified', 'STI-004 caller 8 identity_unverified');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000009','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-9') || md5('h68-tail-9'))), 'identity_unverified', 'STI-004 caller 9 identity_unverified');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000010','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-10') || md5('h68-tail-10'))), 'linked', 'STI-004 caller 10 linked');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000011','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'invite_unavailable', 'STI-004 caller 11 invite_unavailable');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000011','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-11') || md5('h68-tail-11'))), 'linked', 'STI-004 caller 11 linked');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000012','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-12') || md5('h68-tail-12'))), 'account_already_linked', 'STI-004 caller 12 account_already_linked');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000013','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-13') || md5('h68-tail-13'))), 'account_already_linked', 'STI-004 caller 13 account_already_linked');

reset role;

update staff set email='changed@example.com' where id='68900000-0000-0000-0000-000000000315';

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000015','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-15') || md5('h68-tail-15'))), 'email_mismatch', 'STI-004 caller 15 email_mismatch');

select is((select gym_name from public.redeem_staff_invite(md5('h68-15') || md5('h68-tail-15'))), null::text, 'STI-004 mismatch hides gym');

select is((select staff_role from public.redeem_staff_invite(md5('h68-15') || md5('h68-tail-15'))), null::public.app_role, 'STI-004 mismatch hides role');

reset role;

update staff set is_active=false where id='68900000-0000-0000-0000-000000000316';

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000016','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-16') || md5('h68-tail-16'))), 'invite_unavailable', 'STI-004 caller 16 invite_unavailable');

reset role;

update staff_invites set issued_at=now()-interval '49 hours',expires_at=now()-interval '1 hour' where staff_id='68900000-0000-0000-0000-000000000317';

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000017','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-17') || md5('h68-tail-17'))), 'invite_unavailable', 'STI-004 caller 17 invite_unavailable');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select lives_ok($q$select public.revoke_staff_invite((select id from staff_invites where staff_id='68900000-0000-0000-0000-000000000317' and status='pending'))$q$, 'STI-002 expired pending may revoke');

reset role;

set local session_replication_role = replica;
update staff set is_active=false where id='68900000-0000-0000-0000-000000000201';
set local session_replication_role = origin;

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000018','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-18') || md5('h68-tail-18'))), 'invite_unavailable', 'STI-004 caller 18 invite_unavailable');

reset role;

set local role anon;

select is((select count(*) from public.peek_staff_invite(md5('h68-18') || md5('h68-tail-18'))), 0::bigint, 'STI-007 inactive issuer invalidates peek');

select throws_ok($q$select * from public.peek_staff_invite(null)$q$, '22023', null, 'STI-007 null peek hash');

reset role;

set local session_replication_role = replica;
update staff set is_active=true where id='68900000-0000-0000-0000-000000000201';
set local session_replication_role = origin;

set local role anon;

select is((select staff_role::text from public.peek_staff_invite(md5('h68-18') || md5('h68-tail-18'))), 'front_desk', 'STI-007 signed-out exposes assigned role only');

select is((select count(*) from public.peek_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 0::bigint, 'STI-007 redeemed peek unavailable');

reset role;

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select * from public.issue_member_invite('68900000-0000-0000-0000-000000000501',md5('h68-119') || md5('h68-tail-119'));

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000019','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-19') || md5('h68-tail-19'))), 'linked', 'STI-004 caller 19 linked');

select is((select outcome from public.redeem_member_invite(md5('h68-119') || md5('h68-tail-119'))), 'account_already_linked', 'STI-004 member cannot bind after staff identity');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000020','role','authenticated')::text, true);

set local role authenticated;

select * from public.redeem_member_invite(md5('h68-900') || md5('h68-tail-900'));

select * from public.redeem_member_invite(md5('h68-901') || md5('h68-tail-901'));

select * from public.redeem_member_invite(md5('h68-902') || md5('h68-tail-902'));

select * from public.redeem_member_invite(md5('h68-903') || md5('h68-tail-903'));

select * from public.redeem_member_invite(md5('h68-904') || md5('h68-tail-904'));

select * from public.redeem_staff_invite(md5('h68-910') || md5('h68-tail-910'));

select * from public.redeem_staff_invite(md5('h68-911') || md5('h68-tail-911'));

select * from public.redeem_staff_invite(md5('h68-912') || md5('h68-tail-912'));

select * from public.redeem_staff_invite(md5('h68-913') || md5('h68-tail-913'));

select * from public.redeem_staff_invite(md5('h68-914') || md5('h68-tail-914'));

select is((select outcome from public.redeem_staff_invite(md5('h68-20') || md5('h68-tail-20'))), 'rate_limited', 'STI-004 mixed-family tenth failure blocks valid invite');

reset role;

select is((select count(*) from audit_log where actor_user_id='68900000-0000-0000-0000-000000000020' and action in ('member_invite.redeem_refused','staff_invite.redeem_refused')), 10::bigint, 'STI-004 rate-limited refusal writes nothing');

select ok((exists(select 1 from audit_log where actor_user_id='68900000-0000-0000-0000-000000000015' and action='staff_invite.redeem_refused' and tenant_id='68900000-0000-0000-0000-000000000100' and record_type='staff_invite' and actor_role is null and after='{"outcome":"email_mismatch"}'::jsonb)), 'STI-010 resolved refusal carries tenant and no role');

select ok((exists(select 1 from audit_log where actor_user_id='68900000-0000-0000-0000-000000000020' and action='staff_invite.redeem_refused' and tenant_id is null and record_id is null)), 'STI-010 unknown refusal has null tenant and record');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000021' where id='68900000-0000-0000-0000-000000000321'$q$, 'GL049', null, 'STI-006 direct owner binding denied');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000201','owner recovery')$q$, '42501', null, 'STI-008 cannot unlink owner');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000321',' x ')$q$, '22023', null, 'STI-008 validates trimmed reason before bound check');

select throws_ok($q$select public.unlink_staff_identity('68900000-0000-0000-0000-000000000321','valid reason')$q$, 'GL080', null, 'STI-008 unbound refused');

reset role;

insert into auth.sessions(id,user_id,created_at,updated_at) values('68900000-0000-0000-0000-000000000601','68900000-0000-0000-0000-000000000007',now(),now());

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select public.unlink_staff_identity('68900000-0000-0000-0000-000000000307','  staff departed  ');

reset role;

select is((select user_id from staff where id='68900000-0000-0000-0000-000000000307'), null::uuid, 'STI-008 unlink clears identity');

select is((select count(*) from auth.sessions where user_id='68900000-0000-0000-0000-000000000007'), 0::bigint, 'STI-008 unlink deletes sessions');

select ok((exists(select 1 from audit_log where action='staff.unlinked' and record_id='68900000-0000-0000-0000-000000000307' and reason='staff departed' and actor_role='gym_owner' and before='{"user_linked":true}'::jsonb and after='{"user_linked":false}'::jsonb)), 'STI-010 trimmed unlink reason audit');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000007','role','authenticated')::text, true);

set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-7') || md5('h68-tail-7'))), 'invite_unavailable', 'STI-004 caller 7 invite_unavailable');

reset role;

select ok((not exists(select 1 from audit_log where tenant_id='68900000-0000-0000-0000-000000000100' and action like 'staff%' and (coalesce(before::text,'')||coalesce(after::text,'')) ~ '[0-9a-f]{64}')), 'STI-010 no hash in audit payload');

reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text, true);

set local role authenticated;

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-1000') || md5('h68-tail-1000'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-1001') || md5('h68-tail-1001'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-1002') || md5('h68-tail-1002'));

select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-1003') || md5('h68-tail-1003'));

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000322',md5('h68-1004') || md5('h68-tail-1004'))$q$, 'GL078', null, 'STI-003 sixth issue on staff row denied');

reset role;

select is((select count(*) from staff_invites where staff_id='68900000-0000-0000-0000-000000000322'), 5::bigint, 'STI-003 rejected issue writes no invite');

reset role;

select set_config('request.jwt.claims','{}',true);

set local role authenticated;

select throws_ok($q$select * from public.redeem_staff_invite(md5('h68-23') || md5('h68-tail-23'))$q$, '42501', null, 'STI-004 no subject fails');

reset role;

reset role;
set local session_replication_role = replica;

insert into staff(id,tenant_id,user_id,role,full_name,email,is_active) values ('68900000-0000-0000-0000-000000000450','68900000-0000-0000-0000-000000000101','68900000-0000-0000-0000-000000000021','trainer','H68 Previously Bound','h68-21@example.com',false);

set local session_replication_role = origin;

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000021','role','authenticated')::text,true);
set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-21') || md5('h68-tail-21'))),'account_already_linked','STI-004 inactive foreign staff counts as bound');

reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text,true);
set local role authenticated;

select throws_ok($q$select * from public.invite_staff_member('Again','again@example.com',null,'trainer',null,md5('h68-64') || md5('h68-tail-64'))$q$,'23505',null,'STI-001 duplicate hash transaction aborts create');

reset role;

select is((select count(*) from staff where email='again@example.com'),0::bigint,'STI-001 reused hash leaves no orphan staff row');

select set_config('app.staff_binding_command','link:'||'68900000-0000-0000-0000-000000000023'::text,true);

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000023', full_name='Injected' where id='68900000-0000-0000-0000-000000000323'$q$,null::text,null::text,'STI-006 postgres command may not change name with binding');

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000023', email='injected@example.com' where id='68900000-0000-0000-0000-000000000323'$q$,null::text,null::text,'STI-006 postgres command may not change email with binding');

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000023', branch_id='68900000-0000-0000-0000-000000000110' where id='68900000-0000-0000-0000-000000000323'$q$,null::text,null::text,'STI-006 postgres command may not change branch with binding');

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000023', role='trainer' where id='68900000-0000-0000-0000-000000000323'$q$,null::text,null::text,'STI-006 postgres command may not change role with binding');

select set_config('app.staff_binding_command','',true);

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000001','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000100','staff_id','68900000-0000-0000-0000-000000000201')::text,true);
set local role authenticated;

select set_config('app.staff_binding_command','link:'||'68900000-0000-0000-0000-000000000023'::text,true);

select throws_ok($q$update staff set user_id='68900000-0000-0000-0000-000000000023' where id='68900000-0000-0000-0000-000000000323'$q$,'GL049',null,'STI-006 forged session setting cannot bind');

reset role;

select set_config('app.staff_binding_command','',true);

select ok(not has_function_privilege('service_role','app.staff_invite_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)','EXECUTE'),'STI-010 audit helper hidden from service role');

select ok(not has_function_privilege('authenticated','app.staff_invite_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)','EXECUTE'),'STI-010 audit helper hidden from sessions');

select throws_ok($q$select app.staff_invite_audit('68900000-0000-0000-0000-000000000100','68900000-0000-0000-0000-000000000001','gym_owner','staff.unknown','staff','68900000-0000-0000-0000-000000000323',null,null,null)$q$,'22023',null,'STI-010 audit helper rejects unknown action');

set local session_replication_role = replica;

insert into staff(id,tenant_id,role,full_name,email) values('68900000-0000-0000-0000-000000000451','68900000-0000-0000-0000-000000000101','trainer','H68 Limit Target','limit@example.com');

insert into staff_invites(id,tenant_id,staff_id,token_hash,status,issued_by_staff_id,issued_at,expires_at,closed_at) select ('68900000-0000-0000-0000-'||lpad((700+i)::text,12,'0'))::uuid,'68900000-0000-0000-0000-000000000101','68900000-0000-0000-0000-000000000451',md5('h68-hour-'||i)||md5('h68-hour-tail-'||i),'revoked','68900000-0000-0000-0000-000000000202',statement_timestamp()-interval '10 minutes',statement_timestamp()+interval '47 hours',statement_timestamp()-interval '5 minutes' from generate_series(1,30) i;

set local session_replication_role = origin;

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000002','role','authenticated','app_role','gym_owner','tenant_id','68900000-0000-0000-0000-000000000101','staff_id','68900000-0000-0000-0000-000000000202')::text,true);
set local role authenticated;

select throws_ok($q$select * from public.issue_staff_invite('68900000-0000-0000-0000-000000000402',md5('h68-1900') || md5('h68-tail-1900'))$q$,'GL078',null,'STI-003 tenant thirtieth history issue blocks another row');

select throws_ok($q$select * from public.invite_staff_member('Limited','limited@example.com',null,'trainer',null,md5('h68-1901') || md5('h68-tail-1901'))$q$,'GL078',null,'STI-003 tenant limit includes atomic create command');

reset role;

select is((select count(*) from staff where email='limited@example.com'),0::bigint,'STI-003 rate-limited creation leaves no staff row');

set local session_replication_role = replica;

update staff set role='gym_manager' where id='68900000-0000-0000-0000-000000000201';

set local session_replication_role = origin;
set local role anon;

select is((select count(*) from public.peek_staff_invite(md5('h68-23') || md5('h68-tail-23'))),0::bigint,'STI-007 issuer downgrade makes pending peek unavailable');

reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000023','role','authenticated')::text,true);
set local role authenticated;

select is((select outcome from public.redeem_staff_invite(md5('h68-23') || md5('h68-tail-23'))),'invite_unavailable','STI-004 issuer downgrade makes pending redeem unavailable');

reset role;
set local session_replication_role = replica;

update staff set role='gym_owner' where id='68900000-0000-0000-0000-000000000201';

set local session_replication_role = origin;

select set_config('request.jwt.claims',jsonb_build_object('sub','68900000-0000-0000-0000-000000000024','role','authenticated')::text,true);
set local role authenticated;

select throws_ok($q$select * from public.redeem_staff_invite(null)$q$,'22023',null,'STI-004 null redeem hash raises argument error');

select throws_ok($q$select * from public.redeem_staff_invite('bad')$q$,'22023',null,'STI-004 malformed redeem hash raises argument error');

reset role;

select is((select count(*) from audit_log where actor_user_id='68900000-0000-0000-0000-000000000024' and action='staff_invite.redeem_refused'),0::bigint,'STI-004 argument errors do not count as refusals');

select * from finish();
rollback;
