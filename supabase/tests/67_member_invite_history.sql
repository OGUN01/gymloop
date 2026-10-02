-- INV-028 visible suite, independently authored from frozen INV v1.3.
-- No implementation, migration or holdout was consulted. All fixtures roll back.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(45);
select has_function('public','read_member_invite_history',array['uuid'],'INV-028 exact reader signature');
select ok((select prosecdef and provolatile = 's' and proowner = 'postgres'::regrole and proconfig @> array['search_path=""'] from pg_proc where oid = to_regprocedure('public.read_member_invite_history(uuid)')), 'INV-028 stable postgres-owned empty-path definer');
select is((select pg_get_function_result(oid) from pg_proc where oid = to_regprocedure('public.read_member_invite_history(uuid)')), 'TABLE(event_id uuid, occurred_at timestamp with time zone, action text, actor_name text)', 'INV-028 exact safe columns, with no raw ids/contact/audit JSON');
select is(coalesce((select has_function_privilege('authenticated',oid,'execute') from pg_proc where oid = to_regprocedure('public.read_member_invite_history(uuid)')),false), true, 'INV-028 authenticated execute grant');
select is(coalesce((select has_function_privilege('anon',oid,'execute') from pg_proc where oid = to_regprocedure('public.read_member_invite_history(uuid)')),false), false, 'INV-028 anon execute grant');
select is(coalesce((select has_function_privilege('service_role',oid,'execute') from pg_proc where oid = to_regprocedure('public.read_member_invite_history(uuid)')),false), false, 'INV-028 service_role execute grant');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid = to_regprocedure('public.read_member_invite_history(uuid)') and a.grantee = 0 and a.privilege_type = 'EXECUTE'), 'INV-028 PUBLIC has no execute grant');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='audit_log' and indexname='audit_log_member_invite_history_idx' and indexdef ~ '\(tenant_id, record_type, record_id, occurred_at DESC\)' and indexdef !~ ' WHERE '), 'INV-028 exact tenant-leading history index');
insert into auth.users(id,email,email_confirmed_at) values
('67b00000-0000-4000-8000-000000000384','hist0@example.test',now()),
('67b00000-0000-4000-8000-000000000385','hist1@example.test',now()),
('67b00000-0000-4000-8000-000000000386','hist2@example.test',now()),
('67b00000-0000-4000-8000-000000000387','hist3@example.test',now()),
('67b00000-0000-4000-8000-000000000388','hist4@example.test',now()),
('67b00000-0000-4000-8000-000000000389','hist5@example.test',now()),
('67b00000-0000-4000-8000-00000000038a','hist6@example.test',now()),
('67b00000-0000-4000-8000-00000000038b','hist7@example.test',now()),
('67b00000-0000-4000-8000-00000000038c','hist8@example.test',now());
insert into public.organizations(id,name,gym_code,status) values ('67b00000-0000-4000-8000-000000000001','History A','IH67BA','active'),('67b00000-0000-4000-8000-000000000002','History B','IH67BB','active');
insert into public.branches(id,tenant_id,name,is_default) values ('67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000001','Main',true),('67b00000-0000-4000-8000-00000000000c','67b00000-0000-4000-8000-000000000002','Main',true);
insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
('67b00000-0000-4000-8000-000000000015','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000384','gym_owner','Recorded owner',true),
('67b00000-0000-4000-8000-000000000016','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000385','gym_manager','Manager viewer',true),
('67b00000-0000-4000-8000-000000000017','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000386','front_desk','Desk viewer',true),
('67b00000-0000-4000-8000-000000000018','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000387','trainer','Trainer',true),
('67b00000-0000-4000-8000-000000000019','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-000000000388','front_desk','Inactive',false),
('67b00000-0000-4000-8000-00000000001a','67b00000-0000-4000-8000-000000000002','67b00000-0000-4000-8000-00000000000c','67b00000-0000-4000-8000-000000000389','gym_owner','Foreign actor',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,email) values
('67b00000-0000-4000-8000-000000000065','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b','67b00000-0000-4000-8000-00000000038a','Member self','+916700001001','self@example.test'),
('67b00000-0000-4000-8000-000000000066','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b',null,'Other member','+916700001002','other@example.test'),
('67b00000-0000-4000-8000-000000000067','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b',null,'Empty member','+916700001003',null),
('67b00000-0000-4000-8000-000000000068','67b00000-0000-4000-8000-000000000002','67b00000-0000-4000-8000-00000000000c',null,'Foreign member','+916700001004',null),
('67b00000-0000-4000-8000-000000000069','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000000b',null,'Bulk member','+916700001005',null);
insert into public.member_invites(id,tenant_id,member_id,token_hash,issued_by_staff_id,issued_at,expires_at) values
('67b00000-0000-4000-8000-0000000000c9','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000065',repeat('a',64),'67b00000-0000-4000-8000-000000000015',now(),now()+interval '2 days'),
('67b00000-0000-4000-8000-0000000000ca','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000066',repeat('b',64),'67b00000-0000-4000-8000-000000000015',now(),now()+interval '2 days'),
('67b00000-0000-4000-8000-0000000000cc','67b00000-0000-4000-8000-000000000002','67b00000-0000-4000-8000-000000000068',repeat('c',64),'67b00000-0000-4000-8000-00000000001a',now(),now()+interval '2 days');
insert into public.audit_log(id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,occurred_at,before,after,reason) values
('67b00000-0000-4000-8000-00000000012d','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-00000000012e','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.superseded','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-00000000012f','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.revoked','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000130','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000038a','member','member_invite.redeemed','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000131','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000038a','member','member.linked','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000132','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member.unlinked','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000133','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000389','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000134','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000038c',null,'member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000135','67b00000-0000-4000-8000-000000000001',null,null,'member.unlinked','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000141','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.redeem_refused','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000142','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.issued','member','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000143','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member.linked','member_invite','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000144','67b00000-0000-4000-8000-000000000002','67b00000-0000-4000-8000-000000000389','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000145','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000ca','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000146','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000000cc','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000147',null,'67b00000-0000-4000-8000-000000000384','gym_owner','member.linked','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000148','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member.updated','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-000000000149','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member_invite.issued','member_invite','67b00000-0000-4000-8000-0000000003e7','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-00000000014a','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member.linked','member','67b00000-0000-4000-8000-000000000066','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-00000000014b','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','staff_invite.issued','staff_invite','67b00000-0000-4000-8000-0000000000c9','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason'),
('67b00000-0000-4000-8000-00000000014c','67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-00000000038c','member','member.linked','member','67b00000-0000-4000-8000-000000000065','2026-09-01 12:00:00+00','{"private":"before-secret"}','{"email":"secret@example.test","token_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}','private reason');
insert into public.audit_log(id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,occurred_at)
select ('67b00000-0000-4000-8000-' || lpad(to_hex(1000+g),12,'0'))::uuid,'67b00000-0000-4000-8000-000000000001','67b00000-0000-4000-8000-000000000384','gym_owner','member.unlinked','member','67b00000-0000-4000-8000-000000000069','2026-09-02 12:00:00+00'::timestamptz + (g / 2)*interval '1 second' from generate_series(1,55) g;
create temporary table history_snapshot as select 'audit' as kind,md5(jsonb_agg(to_jsonb(a) order by a.id)::text) as digest from public.audit_log a where a.id::text like '67b00000-%' union all select 'invites',md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.member_invites a where a.id::text like '67b00000-%' union all select 'members',md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.members a where a.id::text like '67b00000-%';
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000386","role":"authenticated","app_role":"front_desk","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000017"}',true);
set local role authenticated;
select is((select count(*) from public.audit_log where id::text like '67b00000-%'),0::bigint,'INV-028 front desk retains no broad audit access');
select results_eq($$select event_id from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065')$$,$$select x::uuid from unnest(array['67b00000-0000-4000-8000-00000000014c','67b00000-0000-4000-8000-000000000135','67b00000-0000-4000-8000-000000000134','67b00000-0000-4000-8000-000000000133','67b00000-0000-4000-8000-000000000132','67b00000-0000-4000-8000-000000000131','67b00000-0000-4000-8000-000000000130','67b00000-0000-4000-8000-00000000012f','67b00000-0000-4000-8000-00000000012e','67b00000-0000-4000-8000-00000000012d']) x$$,'INV-028 exact action/type/tenant/member join, refusal and poisoned targets excluded; event_id breaks timestamp ties');
select results_eq($$select actor_name from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065')$$,$$values (null::text),(null::text),(null::text),(null::text),('Recorded owner'),('Member self'),('Member self'),('Recorded owner'),('Recorded owner'),('Recorded owner')$$,'INV-028 recorded same-tenant actor/self names, unknown/foreign actors null and never viewer');
select is_empty($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-000000000067'::uuid)$$,'INV-028 honest empty history');
select throws_ok($$select * from public.read_member_invite_history(null)$$,'22023',null,'INV-028 authorized null target rejected');
select throws_ok($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-0000000003e7'::uuid)$$,'42501',null,'INV-028 unknown member forbidden');
select throws_ok($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-000000000068'::uuid)$$,'42501',null,'INV-028 foreign member indistinguishable');
select throws_ok($$select * from public.read_member_invite_history('malformed'::uuid)$$,'22P02',null,'INV-028 UUID signature rejects malformed target');
select is((select count(*) from public.read_member_invite_history('67b00000-0000-4000-8000-000000000069')),50::bigint,'INV-028 hard latest fifty bound');
select results_eq($$select event_id from public.read_member_invite_history('67b00000-0000-4000-8000-000000000069')$$,$$select ('67b00000-0000-4000-8000-' || lpad(to_hex(1000+g),12,'0'))::uuid from generate_series(55,6,-1) g$$,'INV-028 latest fifty in descending time and id order including tied boundary');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select is((select count(*) from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065')),10::bigint,'INV-028 gym_owner permitted reader');
select ok((select count(*) from public.audit_log where id::text like '67b00000-%') > 10,'INV-028 gym_owner existing broad audit read retained');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000385","role":"authenticated","app_role":"gym_manager","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000016"}',true);
set local role authenticated;
select is((select count(*) from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065')),10::bigint,'INV-028 gym_manager permitted reader');
select ok((select count(*) from public.audit_log where id::text like '67b00000-%') > 10,'INV-028 gym_manager existing broad audit read retained');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000387","role":"authenticated","app_role":"trainer","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000018"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 trainer authorization precedes null argument');
select is((select count(*) from public.audit_log where id::text like '67b00000-%'),0::bigint,'INV-028 trainer retains no broad audit access');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000388","role":"authenticated","app_role":"front_desk","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000019"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 inactive authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000389","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000002","staff_id":"67b00000-0000-4000-8000-00000000001a"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065'::uuid)$$,'42501',null,'INV-028 foreign owner authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-00000000038c","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 wrong subject authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000386","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000017"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 wrong role authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000002","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 wrong tenant authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 missing subject authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 missing tenant authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 missing staff authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-0000000003e7"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 unknown stale staff claim forbidden before null target');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 missing role forbidden before null target');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015","member_id":"67b00000-0000-4000-8000-000000000065"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 member claim authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-000000000384","role":"authenticated","app_role":"gym_owner","tenant_id":"67b00000-0000-4000-8000-000000000001","staff_id":"67b00000-0000-4000-8000-000000000015","impersonation_session_id":"67b00000-0000-4000-8000-0000000003e7"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 preview authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-00000000038c","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 unlinked authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-00000000038a","role":"authenticated","app_role":"member","tenant_id":"67b00000-0000-4000-8000-000000000001","member_id":"67b00000-0000-4000-8000-000000000065"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 member authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-00000000038c","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 super admin authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"67b00000-0000-4000-8000-00000000038c","role":"authenticated","app_role":"platform_support"}',true);
set local role authenticated;
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'INV-028 support authorization precedes null argument');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065'::uuid)$$,'42501',null,'INV-028 anon cannot execute');
set local role postgres;
select set_config('request.jwt.claims','',true);
set local role service_role;
select throws_ok($$select * from public.read_member_invite_history('67b00000-0000-4000-8000-000000000065'::uuid)$$,'42501',null,'INV-028 service_role cannot execute');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.audit_log a where a.id::text like '67b00000-%'),(select digest from history_snapshot where kind='audit'),'INV-028 reader leaves audit unchanged');
select is((select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.member_invites a where a.id::text like '67b00000-%'),(select digest from history_snapshot where kind='invites'),'INV-028 reader leaves invites unchanged');
select is((select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.members a where a.id::text like '67b00000-%'),(select digest from history_snapshot where kind='members'),'INV-028 reader leaves members unchanged');
select * from finish();
rollback;
