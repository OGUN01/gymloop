-- SLF-001..018 independent visible contract (Wave D member freeze requests).
-- Frozen authority: openspec/changes/member-self-service/proposal.md (FROZEN
-- 2026-10-03) with owner-resolved allowance semantics in SLF-012 and the
-- OPEN-016 documented residual. No implementation, holdout or other SLF test
-- material was read.
--
-- RED pattern: no mirror DDL. Every catalog assertion is NULL-safe
-- (to_regclass/to_regprocedure) and every dynamic statement runs through a
-- catching executor, so the file runs end-to-end RED before the SLF migration
-- exists (missing relation 42P01 / missing function 42883) and judges the real
-- implementation once CI applies it. Nothing commits: one begin/rollback pair.
--
-- Refusal-code assumptions pinned from the frozen contract plus the repo's
-- shared precedence vocabulary (the draft reserves no new GL number): actor
-- and privilege failures 42501; value/shape validation 22023; check and
-- invariant violations 23514; unique conflicts 23505; state/stale/overlap/
-- bound/terminal/expiry conflicts GL066; allowance insufficiency GL067;
-- idempotency-key conflicts GL068; invisible targets P0002. If the
-- implementer maps any of these differently, that is a contract-defect
-- round-trip to the test author, not a test edit by the implementer.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(141);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('81000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text default 'member', s integer default null, m integer default null, a integer default 901, t integer default 1, p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(t),'staff_id',case when s is not null then pg_temp.u(s) end,'member_id',case when m is not null then pg_temp.u(m) end,'impersonation_session_id',case when p then pg_temp.u(999) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.val(q text) returns text language plpgsql as $$declare r text; begin execute q into r; return r; exception when others then return sqlstate; end$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.probe(text),pg_temp.val(text) to authenticated,anon,service_role;
create temporary table proof(k text primary key,v jsonb);
grant all on proof to authenticated;

-- ============ fixtures (existing schema only) ============
insert into auth.users(id) select pg_temp.u(n) from generate_series(901,916) n;
insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.u(928),'super_admin','SLF root','slf81-root@example.test',true);
insert into public.organizations(id,name,gym_code,status,timezone) values(pg_temp.u(1),'SLF A','SLF81A','active','Asia/Kolkata'),(pg_temp.u(2),'SLF B','SLF81B','active','Asia/Kolkata');
insert into public.branches(id,tenant_id,name,is_default) values(pg_temp.u(11),pg_temp.u(1),'A',true),(pg_temp.u(12),pg_temp.u(2),'B',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
(pg_temp.u(21),pg_temp.u(1),pg_temp.u(901),pg_temp.u(11),'gym_owner','Owner',true),
(pg_temp.u(22),pg_temp.u(1),pg_temp.u(902),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(23),pg_temp.u(1),pg_temp.u(903),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(24),pg_temp.u(1),pg_temp.u(904),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(25),pg_temp.u(2),pg_temp.u(905),pg_temp.u(12),'gym_owner','Other',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status,erased_at) values
(pg_temp.u(101),pg_temp.u(1),pg_temp.u(11),pg_temp.u(906),'PRIVATE_MEMBER_101','+918100000101','active',null),
(pg_temp.u(102),pg_temp.u(1),pg_temp.u(11),pg_temp.u(907),'PRIVATE_MEMBER_102','+918100000102','active',null),
(pg_temp.u(103),pg_temp.u(1),pg_temp.u(11),null,'PRIVATE_BLOCKED_103','+918100000103','blocked',null),
(pg_temp.u(104),pg_temp.u(1),pg_temp.u(11),null,'PRIVATE_CANCELLED_104','+918100000104','cancelled',null),
(pg_temp.u(105),pg_temp.u(1),pg_temp.u(11),null,'PRIVATE_ERASED_105','+918100000105','active',statement_timestamp()),
(pg_temp.u(106),pg_temp.u(2),pg_temp.u(12),pg_temp.u(912),'PRIVATE_FOREIGN_106','+918100000106','active',null),
(pg_temp.u(107),pg_temp.u(1),pg_temp.u(11),pg_temp.u(913),'PRIVATE_PENDING_107','+918100000107','active',null),
(pg_temp.u(108),pg_temp.u(1),pg_temp.u(11),pg_temp.u(914),'PRIVATE_REJECT_108','+918100000108','active',null),
(pg_temp.u(109),pg_temp.u(1),pg_temp.u(11),pg_temp.u(915),'PRIVATE_BUDGET_109','+918100000109','active',null);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.u(201),pg_temp.u(1),'SLF plan',30,10000),(pg_temp.u(202),pg_temp.u(2),'SLF plan B',30,10000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise) values
(pg_temp.u(301),pg_temp.u(1),pg_temp.u(101),pg_temp.u(201),'active',app.gym_today(pg_temp.u(1))-10,app.gym_today(pg_temp.u(1))+30,10000),
(pg_temp.u(302),pg_temp.u(1),pg_temp.u(102),pg_temp.u(201),'active',app.gym_today(pg_temp.u(1))-10,app.gym_today(pg_temp.u(1))+30,10000),
(pg_temp.u(303),pg_temp.u(1),pg_temp.u(107),pg_temp.u(201),'pending',app.gym_today(pg_temp.u(1))-10,app.gym_today(pg_temp.u(1))+30,10000),
(pg_temp.u(304),pg_temp.u(2),pg_temp.u(106),pg_temp.u(202),'active',app.gym_today(pg_temp.u(2))-10,app.gym_today(pg_temp.u(2))+30,10000),
(pg_temp.u(305),pg_temp.u(1),pg_temp.u(108),pg_temp.u(201),'active',app.gym_today(pg_temp.u(1))-10,app.gym_today(pg_temp.u(1))+30,10000),
(pg_temp.u(306),pg_temp.u(1),pg_temp.u(109),pg_temp.u(201),'active',app.gym_today(pg_temp.u(1))-10,app.gym_today(pg_temp.u(1))+30,10000);
insert into public.organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year) values(pg_temp.u(1),'gym_manager',30),(pg_temp.u(2),'gym_manager',30) on conflict(tenant_id) do update set pause_approver_role=excluded.pause_approver_role,max_freeze_days_per_year=excluded.max_freeze_days_per_year;
-- Undecided source pauses inserted on the trusted path; 601 is approved here
-- by the configured approver through the ordinary staff path, 602 stays
-- undecided until the budget flow approves it, 603 stays undecided forever as
-- the linked evidence of closed requests.
insert into public.membership_pauses(id,tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id) values
(pg_temp.u(601),pg_temp.u(1),pg_temp.u(302),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+5,'Desk approved pause',pg_temp.u(21)),
(pg_temp.u(602),pg_temp.u(1),pg_temp.u(306),app.gym_today(pg_temp.u(1))+6,app.gym_today(pg_temp.u(1))+9,'Budget fixture pause',pg_temp.u(21)),
(pg_temp.u(603),pg_temp.u(1),pg_temp.u(302),app.gym_today(pg_temp.u(1))+10,app.gym_today(pg_temp.u(1))+12,'Closed-request evidence pause',pg_temp.u(21));
set local role authenticated;
select pg_temp.claim('gym_manager',22,null,902,1);
select pg_temp.probe('update public.membership_pauses set approved_by_staff_id=pg_temp.u(22),approved_at=statement_timestamp() where id=pg_temp.u(601)');
set local role postgres;
select set_config('request.jwt.claims','',true);

-- ============ A. vocabulary and table shapes ============
select is((select array_agg(e.enumlabel order by e.enumsortorder) from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace ns on ns.oid=t.typnamespace where ns.nspname='public' and t.typname='member_freeze_request_status'),array['requested','desk_submitted','approved','rejected','cancelled','expired']::text[],'SLF: exact request status vocabulary');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.member_freeze_requests') and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('adopted_at' collate "default"),('adopted_by_staff_id' collate "default"),('cancelled_by_user_id' collate "default"),('closed_at' collate "default"),('created_at' collate "default"),('decided_at' collate "default"),('decided_by_staff_id' collate "default"),('decision_reason' collate "default"),('ends_on' collate "default"),('id' collate "default"),('member_id' collate "default"),('membership_id' collate "default"),('reason' collate "default"),('requested_by_user_id' collate "default"),('request_key' collate "default"),('revision' collate "default"),('source_pause_id' collate "default"),('starts_on' collate "default"),('status' collate "default"),('tenant_id' collate "default"),('updated_at' collate "default")) as expected order by column1 collate "default"$q$,
'SLF: member_freeze_requests exact columns');
select results_eq($q$select attname::text collate "default" from pg_attribute where attrelid=to_regclass('public.member_freeze_commands') and attnum>0 and not attisdropped order by attname::text collate "default"$q$,
$q$select * from (values('action' collate "default"),('actor_user_id' collate "default"),('command_key' collate "default"),('created_at' collate "default"),('facts' collate "default"),('id' collate "default"),('request_id' collate "default"),('result' collate "default"),('tenant_id' collate "default")) as expected order by column1 collate "default"$q$,
'SLF: member_freeze_commands exact columns');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.member_freeze_requests')) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'SELECT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'INSERT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'UPDATE'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'DELETE'),false) and not coalesce(has_table_privilege('anon',to_regclass('public.member_freeze_requests'),'SELECT'),false) and not coalesce(has_table_privilege('anon',to_regclass('public.member_freeze_requests'),'INSERT'),false),'SLF-014: requests RLS enabled, anon and authenticated hold no direct privileges');
select ok((select relrowsecurity from pg_class where oid=to_regclass('public.member_freeze_commands')) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_commands'),'SELECT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_commands'),'INSERT'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_commands'),'UPDATE'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_commands'),'DELETE'),false) and not coalesce(has_table_privilege('anon',to_regclass('public.member_freeze_commands'),'SELECT'),false),'SLF-014: commands RLS enabled, anon and authenticated hold no privileges at all');
select is((select count(*)::integer from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='tenant_id' where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_requests') and c.confrelid='public.members'::regclass and cardinality(c.conkey)=2 and cardinality(c.confkey)=2 and c.conkey[1]=a.attnum),1,'SLF-014: composite tenant/member FK on requests');
select is((select count(*)::integer from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='tenant_id' where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_requests') and c.confrelid='public.memberships'::regclass and cardinality(c.conkey)=2 and cardinality(c.confkey)=2 and c.conkey[1]=a.attnum),1,'SLF-014: composite tenant/membership FK on requests');
select is((select count(*)::integer from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='tenant_id' where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_requests') and c.confrelid='public.membership_pauses'::regclass and cardinality(c.conkey)=2 and cardinality(c.confkey)=2 and c.conkey[1]=a.attnum),1,'SLF-014: composite tenant/source-pause FK on requests');
select is((select count(*)::integer from pg_constraint c where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_requests') and c.confrelid='auth.users'::regclass and c.conkey=(select array[attnum] from pg_attribute where attrelid=to_regclass('public.member_freeze_requests') and attname='requested_by_user_id')),1,'SLF-014: requested_by_user_id binds Auth subjects');
select is((select count(*)::integer from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='tenant_id' where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_commands') and c.confrelid=to_regclass('public.member_freeze_requests') and cardinality(c.conkey)=2 and cardinality(c.confkey)=2 and c.conkey[1]=a.attnum),1,'SLF-014: composite tenant/request FK on commands');
select is((select count(*)::integer from pg_constraint c where c.contype='f' and c.conrelid=to_regclass('public.member_freeze_commands') and c.confrelid='auth.users'::regclass and c.conkey=(select array[attnum] from pg_attribute where attrelid=to_regclass('public.member_freeze_commands') and attname='actor_user_id')),1,'SLF-014: command actor binds Auth subjects');
select ok(exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.member_freeze_commands') and c.contype='c' and pg_get_constraintdef(c.oid) like '%action%'),'SLF-014: command action vocabulary is enforced by a check');
select is((select count(*)::integer from pg_index i where i.indrelid=to_regclass('public.member_freeze_requests') and i.indisunique and i.indpred is null and i.indnkeyatts=2 and (select string_agg(a.attname,',' order by ord) from unnest(i.indkey::smallint[]) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=ord.attnum) in('tenant_id,request_key','request_key,tenant_id')),1,'SLF-014: unique (tenant_id,request_key) on requests');
select is((select count(*)::integer from pg_index i where i.indrelid=to_regclass('public.member_freeze_requests') and i.indisunique and i.indpred is not null and i.indnkeyatts=2 and (select string_agg(a.attname,',' order by ord) from unnest(i.indkey::smallint[]) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=ord.attnum) in('tenant_id,source_pause_id','source_pause_id,tenant_id')),1,'SLF-014: partial unique (tenant_id,source_pause_id) on requests');
select is((select count(*)::integer from pg_index i where i.indrelid=to_regclass('public.member_freeze_commands') and i.indisunique and i.indpred is null and i.indnkeyatts=2 and (select string_agg(a.attname,',' order by ord) from unnest(i.indkey::smallint[]) with ordinality ord(attnum,ord) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=ord.attnum) in('tenant_id,command_key','command_key,tenant_id')),1,'SLF-014: unique (tenant_id,command_key) on commands');
select ok(exists(select 1 from pg_index i join pg_attribute a1 on a1.attrelid=i.indrelid and a1.attnum=i.indkey[0] join pg_attribute a2 on a2.attrelid=i.indrelid and a2.attnum=i.indkey[1] where i.indrelid=to_regclass('public.member_freeze_requests') and a1.attname='tenant_id' and a2.attname='member_id'),'SLF-014: requests indexed tenant-leading by member');
select ok(exists(select 1 from pg_index i join pg_attribute a1 on a1.attrelid=i.indrelid and a1.attnum=i.indkey[0] join pg_attribute a2 on a2.attrelid=i.indrelid and a2.attnum=i.indkey[1] join pg_attribute a3 on a3.attrelid=i.indrelid and a3.attnum=i.indkey[2] join pg_attribute a4 on a4.attrelid=i.indrelid and a4.attnum=i.indkey[3] where i.indrelid=to_regclass('public.member_freeze_requests') and a1.attname='tenant_id' and a2.attname='membership_id' and a3.attname='starts_on' and a4.attname='ends_on'),'SLF-014: requests indexed for overlap lookups');
select ok(exists(select 1 from pg_index i join pg_attribute a1 on a1.attrelid=i.indrelid and a1.attnum=i.indkey[0] join pg_attribute a2 on a2.attrelid=i.indrelid and a2.attnum=i.indkey[1] where i.indrelid=to_regclass('public.member_freeze_requests') and a1.attname='tenant_id' and a2.attname='status'),'SLF-014: requests indexed tenant-leading by status');
select ok(exists(select 1 from pg_index i join pg_attribute a1 on a1.attrelid=i.indrelid and a1.attnum=i.indkey[0] join pg_attribute a2 on a2.attrelid=i.indrelid and a2.attnum=i.indkey[1] where i.indrelid=to_regclass('public.member_freeze_commands') and a1.attname='tenant_id' and a2.attname='request_id'),'SLF-014: commands indexed tenant-leading by request');
select ok(exists(select 1 from pg_index i join pg_attribute a1 on a1.attrelid=i.indrelid and a1.attnum=i.indkey[0] join pg_attribute a2 on a2.attrelid=i.indrelid and a2.attnum=i.indkey[1] where i.indrelid=to_regclass('public.member_freeze_commands') and a1.attname='tenant_id' and a2.attname='actor_user_id'),'SLF-014: commands indexed tenant-leading by actor');
select is((select count(*)::integer from pg_attribute a where a.attrelid=to_regclass('public.member_freeze_requests') and a.attnotnull and a.attname in('id','tenant_id','member_id','membership_id','requested_by_user_id','request_key','starts_on','ends_on','reason','status','revision','created_at','updated_at')),13,'SLF-014: every non-nullable request column is NOT NULL');
select is((select count(*)::integer from pg_attribute a where a.attrelid=to_regclass('public.member_freeze_commands') and a.attnotnull),9,'SLF-014: every command column is NOT NULL');
select ok(not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'REFERENCES'),false) and not coalesce(has_table_privilege('authenticated',to_regclass('public.member_freeze_requests'),'TRIGGER'),false),'SLF-014: no REFERENCES or TRIGGER grants on requests');
select ok((select count(*)::integer from pg_policy where polrelid=to_regclass('public.member_freeze_requests'))>=2,'SLF-014: request policies cover member-own, front-office and platform branches');
select is((select count(*)::integer from pg_policy where polrelid=to_regclass('public.member_freeze_commands')),0,'SLF-014: commands carry no policies; no authenticated surface exists');

-- ============ B. RPC contract ============
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.request_member_freeze(uuid,date,date,text,uuid)')),'uuid date date text uuid','SLF: request_member_freeze exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.cancel_member_freeze_request(uuid,uuid)')),'uuid uuid','SLF: cancel_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.adopt_member_freeze_request(uuid,bigint,uuid)')),'uuid bigint uuid','SLF: adopt_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.approve_member_freeze_request(uuid,bigint,uuid)')),'uuid bigint uuid','SLF: approve_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.reject_member_freeze_request(uuid,bigint,text,uuid)')),'uuid bigint text uuid','SLF: reject_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.expire_member_freeze_request(uuid,bigint,uuid)')),'uuid bigint uuid','SLF: expire_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.read_member_freeze_request(uuid)')),'uuid','SLF: read_member_freeze_request exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.read_member_freeze_requests(integer,timestamptz,uuid)')),'integer timestamp with time zone uuid','SLF: read_member_freeze_requests exact argument types');
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.read_staff_freeze_requests(integer,timestamptz,uuid)')),'integer timestamp with time zone uuid','SLF: read_staff_freeze_requests exact argument types');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.request_member_freeze(uuid,date,date,text,uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: request_member_freeze postgres definer, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.cancel_member_freeze_request(uuid,uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: cancel_member_freeze_request postgres definer, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.adopt_member_freeze_request(uuid,bigint,uuid)') and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: adopt_member_freeze_request invoker, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.approve_member_freeze_request(uuid,bigint,uuid)') and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: approve_member_freeze_request invoker, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.reject_member_freeze_request(uuid,bigint,text,uuid)') and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: reject_member_freeze_request invoker, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.expire_member_freeze_request(uuid,bigint,uuid)') and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: expire_member_freeze_request invoker, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.read_member_freeze_request(uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: read_member_freeze_request safe definer, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.read_member_freeze_requests(integer,timestamptz,uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: read_member_freeze_requests safe definer, empty path, authenticated-only execute');
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.read_staff_freeze_requests(integer,timestamptz,uuid)') and p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'SLF: read_staff_freeze_requests safe definer, empty path, authenticated-only execute');
select is((select provolatile from pg_proc where oid=to_regprocedure('public.read_member_freeze_request(uuid)')),'s','SLF: single read is stable');
select is((select provolatile from pg_proc where oid=to_regprocedure('public.read_member_freeze_requests(integer,timestamptz,uuid)')),'s','SLF: member list read is stable');
select is((select provolatile from pg_proc where oid=to_regprocedure('public.read_staff_freeze_requests(integer,timestamptz,uuid)')),'s','SLF: staff list read is stable');

-- ============ C. shape behavior through direct guarded DML ============
-- C1 is a fully valid CLOSED (rejected) row so the later member flow starts
-- with no open request for member 101.
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,decided_by_staff_id,decided_at,decision_reason,closed_at) values(pg_temp.u(401),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(511),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Fixture closure','rejected',pg_temp.u(23),statement_timestamp(),'Fixture decision',statement_timestamp())$q$),'OK','SLF-014: a fully decided request row satisfies every invariant');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(402),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(512),app.gym_today(pg_temp.u(1))+5,app.gym_today(pg_temp.u(1))+4,'Backwards')$q$),'23514','SLF-014: ends before starts refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(403),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(513),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'')$q$),'23514','SLF-014: empty reason refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(404),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(514),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,repeat('x',2001))$q$),'23514','SLF-014: reason above 2000 characters refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,decided_by_staff_id,decided_at,decision_reason,closed_at) values(pg_temp.u(405),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(515),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'No source','approved',pg_temp.u(22),statement_timestamp(),'Decision',statement_timestamp())$q$),'23514','SLF-014: approved without a source link refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,adopted_by_staff_id,adopted_at) values(pg_temp.u(406),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(516),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Orphan adoption',pg_temp.u(23),statement_timestamp())$q$),'23514','SLF-014: adopted pair without a source link refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,closed_at) values(pg_temp.u(407),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(517),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'No canceller','cancelled',statement_timestamp())$q$),'23514','SLF-014: cancelled without the original member subject refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,decided_by_staff_id,decided_at,decision_reason) values(pg_temp.u(408),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(518),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'No closure','rejected',pg_temp.u(23),statement_timestamp(),'Decision')$q$),'23514','SLF-014: terminal status without closed_at refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,closed_at) values(pg_temp.u(409),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(519),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Open with closure','requested',statement_timestamp())$q$),'23514','SLF-014: open status with a closure stamp refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,decided_by_staff_id,decided_at,closed_at) values(pg_temp.u(410),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(520),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'No reason','rejected',pg_temp.u(23),statement_timestamp(),statement_timestamp())$q$),'23514','SLF-014: rejected without a decision reason refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,decided_by_staff_id,decided_at,decision_reason,closed_at) values(pg_temp.u(411),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(521),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Short reason','rejected',pg_temp.u(23),statement_timestamp(),'No',statement_timestamp())$q$),'23514','SLF-014: decision reason below three characters refused');
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(412),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(511),app.gym_today(pg_temp.u(1))+6,app.gym_today(pg_temp.u(1))+8,'Duplicate key')$q$),'23505','SLF-014: duplicate (tenant_id,request_key) refused');
select pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,cancelled_by_user_id,closed_at,source_pause_id,adopted_by_staff_id,adopted_at) values(pg_temp.u(413),pg_temp.u(1),pg_temp.u(102),pg_temp.u(302),pg_temp.u(907),pg_temp.u(522),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+2,'Linked one','cancelled',pg_temp.u(907),statement_timestamp(),pg_temp.u(603),pg_temp.u(23),statement_timestamp())$q$);
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status,cancelled_by_user_id,closed_at,source_pause_id,adopted_by_staff_id,adopted_at) values(pg_temp.u(414),pg_temp.u(1),pg_temp.u(102),pg_temp.u(302),pg_temp.u(907),pg_temp.u(523),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+2,'Linked two','cancelled',pg_temp.u(907),statement_timestamp(),pg_temp.u(603),pg_temp.u(23),statement_timestamp())$q$),'23505','SLF-014: a source pause binds at most one request');
select is(pg_temp.probe($q$insert into public.member_freeze_commands(id,tenant_id,request_id,actor_user_id,command_key,action,facts,result) values(pg_temp.u(420),pg_temp.u(1),pg_temp.u(401),pg_temp.u(906),pg_temp.u(524),'create','{}','{}')$q$),'OK','SLF-014: a valid command row satisfies every invariant');
select is(pg_temp.probe($q$insert into public.member_freeze_commands(id,tenant_id,request_id,actor_user_id,command_key,action,facts,result) values(pg_temp.u(421),pg_temp.u(1),pg_temp.u(401),pg_temp.u(906),pg_temp.u(525),'steal','{}','{}')$q$),'23514','SLF-014: command action outside the frozen vocabulary refused');
select is(pg_temp.probe($q$insert into public.member_freeze_commands(id,tenant_id,request_id,actor_user_id,command_key,action,facts,result) values(pg_temp.u(422),pg_temp.u(1),pg_temp.u(401),pg_temp.u(906),pg_temp.u(524),'create','{}','{}')$q$),'23505','SLF-014: duplicate (tenant_id,command_key) refused');
select is(pg_temp.probe($q$update public.member_freeze_commands set result='{"changed":true}' where id=pg_temp.u(420)$q$),'23514','SLF-014: command results are immutable for every writer');
select is(pg_temp.probe($q$delete from public.member_freeze_commands where id=pg_temp.u(420)$q$),'23514','SLF-014: commands are not deletable');
select is(pg_temp.probe($q$delete from public.member_freeze_requests where id=pg_temp.u(401)$q$),'23514','SLF-014: requests are not deletable');
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(430),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(526),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Direct')$q$),'42501','SLF-014: authenticated direct INSERT refused');
select is(pg_temp.probe('select count(*) from public.member_freeze_requests'),'42501','SLF-014: authenticated direct SELECT refused');
select is(pg_temp.probe($q$update public.member_freeze_requests set reason='Edited' where id=pg_temp.u(401)$q$),'42501','SLF-014: authenticated direct UPDATE refused');
select is(pg_temp.probe($q$insert into public.member_freeze_commands(id,tenant_id,request_id,actor_user_id,command_key,action,facts,result) values(pg_temp.u(431),pg_temp.u(1),pg_temp.u(401),pg_temp.u(906),pg_temp.u(527),'create','{}','{}')$q$),'42501','SLF-014: authenticated direct command INSERT refused');
select is(pg_temp.probe('select count(*) from public.member_freeze_commands'),'42501','SLF-014: authenticated direct command SELECT refused');
set local role postgres;
select is(pg_temp.val('select revision::text from public.member_freeze_requests where id=pg_temp.u(401)'),'1','SLF-014: revision starts at one');

-- ============ D. member request flow ============
insert into proof select 'audit0',to_jsonb(count(*)) from public.audit_log where tenant_id=pg_temp.u(1);
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Family function',pg_temp.u(701))$q$),'OK','SLF-004: eligible member creates one requested freeze');
set local role postgres;
select pg_temp.probe($q$insert into proof select 'r101',to_jsonb(id) from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$);
select is(pg_temp.val($q$select status::text||':'||revision::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),'requested:1','SLF-004: request created requested with revision one');
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))-1,app.gym_today(pg_temp.u(1))+1,'Backwards',pg_temp.u(730))$q$),'22023','SLF-004: start before gym-local today refused');
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+31,'Too long',pg_temp.u(731))$q$),'22023','SLF-004: interval beyond the membership span refused');
select pg_temp.claim('member',null,107,913,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(303),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Pending plan',pg_temp.u(732))$q$),'22023','SLF-002: pending membership disables freeze creation');
select pg_temp.claim('member',null,103,916,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Blocked',pg_temp.u(733))$q$),'42501','SLF-003: blocked member gains no self-service authority');
select pg_temp.claim('member',null,105,916,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Erased',pg_temp.u(734))$q$),'42501','SLF-003: erased member gains no self-service authority');
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'   ',pg_temp.u(735))$q$),'22023','SLF-004: blank reason refused');
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,repeat('x',2001),pg_temp.u(736))$q$),'22023','SLF-004: reason above 2000 characters refused');
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+6,app.gym_today(pg_temp.u(1))+8,'Second open',pg_temp.u(702))$q$),'GL066','SLF_LIMITS: one open request per member is enforced');
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Family function',pg_temp.u(701))$q$),'OK','SLF-013: exact same-key retry replays read-only');
set local role postgres;
select is(pg_temp.val($q$select count(*)::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),'1','SLF-013: replay creates no second request');
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+5,app.gym_today(pg_temp.u(1))+7,'Changed facts',pg_temp.u(701))$q$),'GL068','SLF-013: changed facts under a used key conflict');
select pg_temp.claim('member',null,102,907,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(302),app.gym_today(pg_temp.u(1))+3,app.gym_today(pg_temp.u(1))+6,'Overlap',pg_temp.u(737))$q$),'GL066','SLF-005: inclusive overlap with an approved pause refused');
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(302),app.gym_today(pg_temp.u(1))+6,app.gym_today(pg_temp.u(1))+8,'Adjacent',pg_temp.u(741))$q$),'OK','SLF-005: adjacent intervals sharing no date allowed');
set local role postgres;
-- Expiry fixture: the frozen RPC table limits expire to "only already
-- ineffective open request" (SLF-010: the start day has elapsed). Such a row is
-- a legitimate unmaterialized state, so it is seeded here on the trusted path;
-- the RPC-created adjacency request above moves to key 741 so key 703 names
-- this elapsed fixture for the E-section expiry flow.
select is(pg_temp.probe($q$insert into public.member_freeze_requests(id,tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) values(pg_temp.u(415),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),pg_temp.u(906),pg_temp.u(703),app.gym_today(pg_temp.u(1))-5,app.gym_today(pg_temp.u(1))-2,'Elapsed fixture')$q$),'OK','SLF-010: an elapsed-start open request is a legitimate state the expire command exists to close');
select pg_temp.probe($q$insert into proof select 'r102',to_jsonb(id) from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(703)$q$);
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(302),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Foreign target',pg_temp.u(738))$q$),'42501','SLF-003: another member''s membership is not requestable');
select pg_temp.claim('member',null,106,912,2);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Cross tenant',pg_temp.u(739))$q$),'42501','SLF-003: cross-tenant membership refused');
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe('select public.read_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''))'),'OK','SLF-001: member reads own request');
select pg_temp.claim('member',null,102,907,1);
select is(pg_temp.probe('select public.read_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''))'),'P0002','SLF-001: another member''s request is invisible');
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe('select public.read_member_freeze_requests(50,null,null)'),'OK','SLF-001: member list read succeeds');
select pg_temp.claim('member',null,107,913,1);
select is(pg_temp.probe('select public.read_member_freeze_requests(50,null,null)'),'OK','SLF-002: pending membership keeps permitted history reads');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(928),'role','authenticated','app_role','super_admin')::text,true);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'42501','SLF-003: platform actors gain no SLF read');
select pg_temp.claim('member',null,101,906,1,true);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Impersonated',pg_temp.u(740))$q$),'42501','SLF-003: impersonated subject refused');

-- ============ E. desk adoption, approval, rejection, withdrawal, expiry ============
select pg_temp.claim('trainer',24,null,904,1);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),1,pg_temp.u(723))'),'42501','SLF-006: trainer is not front office');
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),1,pg_temp.u(724))'),'42501','SLF-006: members cannot adopt requests');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),1,pg_temp.u(725))'),'42501','SLF-006: foreign-tenant staff refused');
select pg_temp.claim('front_desk',23,null,903,1);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),2,pg_temp.u(713))'),'GL066','SLF-013: stale expected revision refuses adoption');
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),1,pg_temp.u(712))'),'OK','SLF-006: real front office adopts the request');
set local role postgres;
select is(pg_temp.val($q$select status::text||':'||revision::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),'desk_submitted:2','SLF-006: adoption links and moves to desk_submitted');
select is(pg_temp.val($q$select p.requested_by_staff_id::text from public.membership_pauses p join public.member_freeze_requests r on r.source_pause_id=p.id where r.tenant_id=pg_temp.u(1) and r.request_key=pg_temp.u(701)$q$),pg_temp.u(23)::text,'SLF-006: source pause stamps the adopting caller as requester');
select is(pg_temp.val($q$select (p.approved_at is null and p.rejected_at is null)::text from public.membership_pauses p join public.member_freeze_requests r on r.source_pause_id=p.id where r.tenant_id=pg_temp.u(1) and r.request_key=pg_temp.u(701)$q$),'true','SLF-006: adopted source pause arrives undecided');
select is(pg_temp.val($q$select (source_pause_id is not null)::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),'true','SLF-006: request atomically links its source pause');
set local role authenticated;
select pg_temp.claim('front_desk',23,null,903,1);
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),2,pg_temp.u(721))'),'42501','SLF-007: the adopter cannot approve their own sponsorship');
select pg_temp.claim('gym_owner',21,null,901,1);
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),2,pg_temp.u(722))'),'42501','SLF-007: owner rank does not override the configured approver role');
select pg_temp.claim('gym_manager',22,null,902,1);
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),2,pg_temp.u(714))'),'OK','SLF-007: configured-role second staff member approves');
set local role postgres;
select is(pg_temp.val($q$select status::text||':'||revision::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),'approved:3','SLF-007: approval moves the request to approved');
select is(pg_temp.val($q$select p.approved_by_staff_id::text from public.membership_pauses p join public.member_freeze_requests r on r.source_pause_id=p.id where r.tenant_id=pg_temp.u(1) and r.request_key=pg_temp.u(701)$q$),pg_temp.u(22)::text,'SLF-007: source pause records the real approver');
select is(pg_temp.val($q$select (p.approved_at is not null)::text from public.membership_pauses p join public.member_freeze_requests r on r.source_pause_id=p.id where r.tenant_id=pg_temp.u(1) and r.request_key=pg_temp.u(701)$q$),'true','SLF-007: source pause approval is stamped');
select is(pg_temp.val($q$select decided_by_staff_id::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(701)$q$),pg_temp.u(22)::text,'SLF-007: request decision pair names the approving staff');
set local role authenticated;
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),3,pg_temp.u(715))'),'GL066','SLF-013: an approved request is terminal');
-- Budget recheck: tighten the gym allowance, then a member whose approved
-- history plus the proposal exceeds it must fail at final approval only.
set local role postgres;
update public.organization_settings set max_freeze_days_per_year=5 where tenant_id=pg_temp.u(1);
set local role authenticated;
select pg_temp.claim('member',null,109,915,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(306),app.gym_today(pg_temp.u(1))+1,app.gym_today(pg_temp.u(1))+3,'Budget request',pg_temp.u(705))$q$),'OK','SLF-012: request creation does not consume allowance');
set local role postgres;
select pg_temp.probe($q$insert into proof select 'r109',to_jsonb(id) from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(705)$q$);
set local role authenticated;
select pg_temp.claim('front_desk',23,null,903,1);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r109''),1,pg_temp.u(716))'),'OK','SLF-012: adoption does not consume allowance');
set local role postgres;
select pg_temp.probe('update public.membership_pauses set approved_by_staff_id=pg_temp.u(22),approved_at=statement_timestamp() where id=pg_temp.u(602)');
set local role authenticated;
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r109''),2,pg_temp.u(728))'),'GL067','SLF-012: final approval rechecks the frozen annual allowance');
-- Rejection flow for member 108.
select pg_temp.claim('member',null,108,914,1);
select is(pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(305),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Reject flow',pg_temp.u(706))$q$),'OK','SLF-008: rejection flow request created');
set local role postgres;
select pg_temp.probe($q$insert into proof select 'r108',to_jsonb(id) from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(706)$q$);
set local role authenticated;
select pg_temp.claim('front_desk',23,null,903,1);
select is(pg_temp.probe('select public.adopt_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r108''),1,pg_temp.u(717))'),'OK','SLF-008: rejection flow request adopted');
select is(pg_temp.probe('select public.reject_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r108''),2,''Not this month'',pg_temp.u(718))'),'OK','SLF-008: front office rejects with a member-visible reason');
set local role postgres;
select is(pg_temp.val($q$select status::text||':'||revision::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(706)$q$),'rejected:3','SLF-008: rejection closes the request');
select is(pg_temp.val($q$select decided_by_staff_id::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(706)$q$),pg_temp.u(23)::text,'SLF-008: rejection records the real actor');
select is(pg_temp.val($q$select decision_reason from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(706)$q$),'Not this month','SLF-008: rejection reason is stored for the member');
select is(pg_temp.val($q$select (p.rejected_at is not null)::text from public.membership_pauses p join public.member_freeze_requests r on r.source_pause_id=p.id where r.tenant_id=pg_temp.u(1) and r.request_key=pg_temp.u(706)$q$),'true','SLF-008: the linked pending source pause is rejected by the real caller');
set local role authenticated;
select is(pg_temp.probe('select public.reject_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r108''),3,''No'',pg_temp.u(726))'),'22023','SLF-008: rejection reason below three characters refused');
select is(pg_temp.probe('select public.reject_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r108''),3,repeat(''y'',201),pg_temp.u(727))'),'22023','SLF-008: rejection reason above 200 characters refused');
-- Member withdrawal.
select pg_temp.claim('member',null,109,915,1);
select is(pg_temp.probe('select public.cancel_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r109''),pg_temp.u(707))'),'OK','SLF-009: the owning member withdraws an unapproved request');
set local role postgres;
select is(pg_temp.val($q$select status::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(705)$q$),'cancelled','SLF-009: withdrawal closes the request as cancelled');
select is(pg_temp.val($q$select cancelled_by_user_id::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(705)$q$),pg_temp.u(915)::text,'SLF-009: withdrawal records the original member subject');
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select is(pg_temp.probe('select public.cancel_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r109''),pg_temp.u(729))'),'42501','SLF-009: another member cannot withdraw a request');
select is(pg_temp.probe('select public.cancel_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),pg_temp.u(708))'),'GL066','SLF-009: an approved freeze is never undone by withdrawal');
set local role postgres;
select is(pg_temp.probe($q$update public.membership_pauses set approved_by_staff_id=pg_temp.u(22),approved_at=statement_timestamp() where id=(select source_pause_id from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(705))$q$),'23514','SLF-014: the additive invariant refuses deciding a linked closed request');
-- Expiry.
select pg_temp.claim('front_desk',23,null,903,1);
select is(pg_temp.probe('select public.expire_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r102''),1,pg_temp.u(709))'),'OK','SLF-010: an authorized staff command materializes closure once');
set local role postgres;
select is(pg_temp.val($q$select status::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(703)$q$),'expired','SLF-010: materialized expiry closes the request');
select is(pg_temp.val($q$select (closed_at is not null)::text from public.member_freeze_requests where tenant_id=pg_temp.u(1) and request_key=pg_temp.u(703)$q$),'true','SLF-010: materialized expiry stamps closure');
set local role authenticated;
select is(pg_temp.probe('select public.expire_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r102''),2,pg_temp.u(710))'),'GL066','SLF-010: expiry materializes exactly once');
select is(pg_temp.probe('select public.approve_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r102''),2,pg_temp.u(711))'),'GL066','SLF-010: an expired request cannot be approved');
-- Staff reads.
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'OK','SLF-001: front office reads the same-tenant queue');
select pg_temp.claim('trainer',24,null,904,1);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'42501','SLF-003: trainers gain no freeze queue');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.probe('select public.read_staff_freeze_requests(50,null,null)'),'OK','SLF-003: a valid foreign-tenant front-office caller reads their own (empty) queue; scoping, not refusal');
-- Audit truth.
set local role postgres;
select pg_temp.probe($q$insert into proof select 'audit1',to_jsonb(count(*)) from public.audit_log where tenant_id=pg_temp.u(1)$q$);
select ok((select count(*)::bigint from public.audit_log where tenant_id=pg_temp.u(1)) > (select (v::text)::bigint from proof where k='audit0'),'SLF-015: successful transitions append atomic audit events');
set local role authenticated;
select pg_temp.claim('trainer',24,null,904,1);
select pg_temp.probe('select public.expire_member_freeze_request((select (v->>''id'')::uuid from proof where k=''r101''),3,pg_temp.u(719))');
set local role postgres;
select ok((select count(*)::bigint from public.audit_log where tenant_id=pg_temp.u(1)) = (select (v::text)::bigint from proof where k='audit1'),'SLF-015: refused commands append no audit');
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
select pg_temp.probe($q$select public.request_member_freeze(pg_temp.u(301),app.gym_today(pg_temp.u(1))+2,app.gym_today(pg_temp.u(1))+4,'Family function',pg_temp.u(701))$q$);
set local role postgres;
select ok((select count(*)::bigint from public.audit_log where tenant_id=pg_temp.u(1)) = (select (v::text)::bigint from proof where k='audit1'),'SLF-015: exact replays append no audit');
rollback;
