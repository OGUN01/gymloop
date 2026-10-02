-- Independent INV-028 contract tests. Fixture trigger bypass is confined to this rollback.
begin;
set local role postgres;
set local search_path = public, extensions;
select plan(39);

insert into auth.users (id, email) select ('67910000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid, 'history-' || n || '@example.com' from generate_series(1,7) n;
insert into public.organizations (id,name,gym_code,status) values
 ('67910000-0000-0000-0001-000000000001','History A','H67AAA','active'),
 ('67910000-0000-0000-0001-000000000002','History B','H67BBB','active');
insert into public.branches (id,tenant_id,name) select ('67910000-0000-0000-0002-' || lpad(n::text,12,'0'))::uuid, ('67910000-0000-0000-0001-' || lpad(n::text,12,'0'))::uuid,'Main' from generate_series(1,2) n;
alter table public.staff disable trigger staff_auth_binding_invariant;
insert into public.staff (id,tenant_id,user_id,role,full_name,is_active) values
 ('67910000-0000-0000-0003-000000000001','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000001','gym_owner','Owner Recorded',true),
 ('67910000-0000-0000-0003-000000000002','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000002','gym_manager','Manager Viewer',true),
 ('67910000-0000-0000-0003-000000000003','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000003','front_desk','Desk Viewer',true),
 ('67910000-0000-0000-0003-000000000004','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000004','trainer','Trainer',true),
 ('67910000-0000-0000-0003-000000000005','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000005','front_desk','Inactive Desk',false),
 ('67910000-0000-0000-0003-000000000006','67910000-0000-0000-0001-000000000002','67910000-0000-0000-0000-000000000006','gym_owner','Foreign Recorded',true);
alter table public.staff enable trigger staff_auth_binding_invariant;
insert into public.members (id,tenant_id,branch_id,full_name,phone,email,user_id) values
 ('67910000-0000-0000-0004-000000000001','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0002-000000000001','Member Self','+919679100001','secret-member@example.com','67910000-0000-0000-0000-000000000007'),
 ('67910000-0000-0000-0004-000000000002','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0002-000000000001','Empty Member','+919679100002',null,null),
 ('67910000-0000-0000-0004-000000000003','67910000-0000-0000-0001-000000000002','67910000-0000-0000-0002-000000000002','Foreign Member','+919679100003',null,null),
 ('67910000-0000-0000-0004-000000000004','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0002-000000000001','Truly Empty','+919679100004',null,null);
insert into public.member_invites (id,tenant_id,member_id,token_hash,status,issued_by_staff_id,issued_at,expires_at,closed_at) values
 ('67910000-0000-0000-0005-000000000001','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0004-000000000001',repeat('a',64),'revoked','67910000-0000-0000-0003-000000000001','2026-01-01','2026-01-03','2026-01-02'),
 ('67910000-0000-0000-0005-000000000002','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0004-000000000002',repeat('b',64),'revoked','67910000-0000-0000-0003-000000000001','2026-01-01','2026-01-03','2026-01-02'),
 ('67910000-0000-0000-0005-000000000003','67910000-0000-0000-0001-000000000002','67910000-0000-0000-0004-000000000003',repeat('c',64),'revoked','67910000-0000-0000-0003-000000000006','2026-01-01','2026-01-03','2026-01-02');

-- Six allowed action shapes, truthful recorded identities, and deliberately poisonous JSON.
insert into public.audit_log (id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,occurred_at,"after")
select ('67910000-0000-0000-0006-' || lpad(n::text,12,'0'))::uuid,'67910000-0000-0000-0001-000000000001',
 case when n in (4,5) then '67910000-0000-0000-0000-000000000007'::uuid when n=6 then null else '67910000-0000-0000-0000-000000000001'::uuid end,
 case when n in (4,5) then 'member'::public.app_role else 'gym_owner'::public.app_role end,
 (array['member_invite.issued','member_invite.superseded','member_invite.revoked','member_invite.redeemed','member.linked','member.unlinked'])[n],
 case when n<=4 then 'member_invite' else 'member' end,
 case when n<=4 then '67910000-0000-0000-0005-000000000001'::uuid else '67910000-0000-0000-0004-000000000001'::uuid end,
 '2026-02-01'::timestamptz + n * interval '1 second',
 jsonb_build_object('email','secret-member@example.com','token_hash',repeat('a',64),'member_id','67910000-0000-0000-0004-000000000001') from generate_series(1,6) n;
-- None of these must be selected, even though their JSON claims the target member.
insert into public.audit_log (id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,occurred_at,"after")
select ('67910000-0000-0000-0007-' || lpad(n::text,12,'0'))::uuid,
 case when n=8 then null when n=9 then '67910000-0000-0000-0001-000000000002'::uuid else '67910000-0000-0000-0001-000000000001'::uuid end,
 '67910000-0000-0000-0000-000000000006','gym_owner',
 (array['member_invite.redeem_refused','staff_invite.issued','member.updated','member.linked','member_invite.issued','member_invite.issued','member.linked','member.linked','member_invite.issued'])[n],
 (array['member_invite','staff_invite','member','member_invite','member','member_invite','member','member','member_invite'])[n],
 (array['67910000-0000-0000-0005-000000000001','67910000-0000-0000-0005-000000000001','67910000-0000-0000-0004-000000000001','67910000-0000-0000-0004-000000000001','67910000-0000-0000-0005-000000000001','67910000-0000-0000-0005-000000000002','67910000-0000-0000-0004-000000000003','67910000-0000-0000-0004-000000000001','67910000-0000-0000-0005-000000000003'])[n]::uuid,
 '2026-03-01',jsonb_build_object('member_id','67910000-0000-0000-0004-000000000001','outcome','email_mismatch') from generate_series(1,9) n;
-- A foreign recorded actor on a valid target must be anonymous, never the viewer.
insert into public.audit_log (id,tenant_id,actor_user_id,actor_role,action,record_type,record_id,occurred_at) values
 ('67910000-0000-0000-0006-000000000007','67910000-0000-0000-0001-000000000001','67910000-0000-0000-0000-000000000006','gym_owner','member.unlinked','member','67910000-0000-0000-0004-000000000001','2026-02-01 00:00:07+00');
create temp table history_before as select (select count(*) from public.audit_log) audit_count,(select count(*) from public.member_invites) invite_count,(select md5(string_agg(row_to_json(m)::text,'' order by id)) from public.members m) member_digest;
grant select on history_before to authenticated;

select ok(to_regprocedure('public.read_member_invite_history(uuid)') is not null,'INV-028 reader exists');
select is((select pg_get_userbyid(proowner)::text from pg_proc where oid=to_regprocedure('public.read_member_invite_history(uuid)')),'postgres','postgres owns reader');
select ok((select prosecdef and provolatile='s' from pg_proc where oid=to_regprocedure('public.read_member_invite_history(uuid)')),'stable security definer');
select ok((select proconfig @> array['search_path=""'] from pg_proc where oid=to_regprocedure('public.read_member_invite_history(uuid)')),'empty search path');
select ok(has_function_privilege('authenticated','public.read_member_invite_history(uuid)','EXECUTE'),'authenticated execute');
select ok(not has_function_privilege('anon','public.read_member_invite_history(uuid)','EXECUTE'),'anon excluded');
select ok(not has_function_privilege('service_role','public.read_member_invite_history(uuid)','EXECUTE'),'service role excluded');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.read_member_invite_history(uuid)') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC excluded');
select is((select array_agg(n order by ord) from pg_proc p,unnest(p.proargnames,p.proargmodes) with ordinality x(n,m,ord) where p.oid=to_regprocedure('public.read_member_invite_history(uuid)') and m='t'),array['event_id','occurred_at','action','actor_name']::text[],'exact safe returned fields');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='audit_log' and indexname='audit_log_member_invite_history_idx' and indexdef like '%(tenant_id, record_type, record_id, occurred_at DESC)%'),'tenant-leading history index');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000003","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000003","app_role":"front_desk","role":"authenticated"}',true);
select is((select count(*) from public.audit_log where tenant_id='67910000-0000-0000-0001-000000000001'),0::bigint,'desk still cannot read broad audit');
select is((select count(*) from public.read_member_invite_history('67910000-0000-0000-0004-000000000001')),7::bigint,'desk sees only seven persisted allowed target events');
select is((select actor_name from public.read_member_invite_history('67910000-0000-0000-0004-000000000001') where action='member_invite.issued'),'Owner Recorded','recorded staff actor instead of current desk');
select is((select actor_name from public.read_member_invite_history('67910000-0000-0000-0004-000000000001') where action='member_invite.redeemed'),'Member Self','redemption names recorded member');
select is((select actor_name from public.read_member_invite_history('67910000-0000-0000-0004-000000000001') where action='member.linked'),'Member Self','self link names recorded member');
select is((select count(*) from public.read_member_invite_history('67910000-0000-0000-0004-000000000001') where action='member.unlinked' and actor_name is null),2::bigint,'missing and foreign actors remain null');
select ok(not exists(select 1 from public.read_member_invite_history('67910000-0000-0000-0004-000000000001') h where row_to_json(h)::text ~ 'secret-member|token_hash|outcome|tenant_id|staff_id|actor_user_id|member_id'),'projection excludes contact hash JSON identifiers');
select is((select count(*) from public.read_member_invite_history('67910000-0000-0000-0004-000000000004')),0::bigint,'empty member has no legitimate events');
select throws_ok($$select * from public.read_member_invite_history(null)$$,'22023',null,'valid actor null argument');
select throws_ok($$select * from public.read_member_invite_history('67910000-0000-0000-0004-000000000003')$$,'42501',null,'foreign member refused');
select throws_ok($$select * from public.read_member_invite_history('67910000-0000-0000-0004-000000000099')$$,'42501',null,'unknown member refused');

set local role postgres;
-- Fifty-five same-time events stress tie ordering and cap independently of earlier examples.
insert into public.audit_log (id,tenant_id,action,record_type,record_id,occurred_at)
select ('67910000-0000-0000-0008-'||lpad(n::text,12,'0'))::uuid,'67910000-0000-0000-0001-000000000001','member.linked','member','67910000-0000-0000-0004-000000000001','2026-04-01' from generate_series(1,55) n;
set local role authenticated;
select is((select count(*) from public.read_member_invite_history('67910000-0000-0000-0004-000000000001')),50::bigint,'latest fifty cap');
select results_eq($$select event_id from public.read_member_invite_history('67910000-0000-0000-0004-000000000001')$$,$$select ('67910000-0000-0000-0008-'||lpad(n::text,12,'0'))::uuid from generate_series(55,6,-1) n$$,'deterministic occurred-at then event-id descending');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000002","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000002","app_role":"gym_manager"}',true);
select lives_ok($$select * from public.read_member_invite_history('67910000-0000-0000-0004-000000000001')$$,'manager accepted');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000001","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000001","app_role":"gym_owner"}',true);
select lives_ok($$select * from public.read_member_invite_history('67910000-0000-0000-0004-000000000001')$$,'owner accepted');

-- Each refusal checks actor validation first, including null input.
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'missing identity precedes argument');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000003","tenant_id":"broken","staff_id":"broken","app_role":"front_desk"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'malformed claims normalized');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000003","tenant_id":"67910000-0000-0000-0001-000000000001","app_role":"front_desk"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'missing staff id refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000003","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000001","app_role":"gym_owner"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'stale or spoofed subject mismatch');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000005","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000005","app_role":"front_desk"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'inactive staff refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000004","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000004","app_role":"trainer"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'trainer refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000007","tenant_id":"67910000-0000-0000-0001-000000000001","member_id":"67910000-0000-0000-0004-000000000001","app_role":"member"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'member audience refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000001","app_role":"super_admin"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'platform audience refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000001","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000001","app_role":"gym_owner","impersonation_session_id":"67910000-0000-0000-0009-000000000001"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'support preview refused');
select set_config('request.jwt.claims','{"sub":"67910000-0000-0000-0000-000000000001","tenant_id":"67910000-0000-0000-0001-000000000001","staff_id":"67910000-0000-0000-0003-000000000001","member_id":"67910000-0000-0000-0004-000000000001","app_role":"gym_owner"}',true);
select throws_ok($$select * from public.read_member_invite_history(null)$$,'42501',null,'contradictory member and staff claims refused');
set local role postgres;
select is((select count(*) from public.audit_log),(select audit_count+55 from history_before),'reads and refusals write no audit');
select is((select count(*) from public.member_invites),(select invite_count from history_before),'reads change no invites');
select is((select md5(string_agg(row_to_json(m)::text,'' order by id)) from public.members m),(select member_digest from history_before),'reads change no members');
select ok(not has_table_privilege('authenticated','public.audit_log','INSERT'),'no broad audit write grant added');
select * from finish();
rollback;
