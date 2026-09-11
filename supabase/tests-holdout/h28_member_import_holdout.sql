-- Independent H28 member-import holdout. Single source of truth: the frozen
-- Phase 6 import contract (docs/planning/phase6-import-contract.md, CSV-001
-- through CSV-006, status "freeze candidate under ADR-111"). No implementation
-- was read (none exists), and neither supabase/tests/** nor any apps/web code
-- was opened. Prior holdout files supplied only harness conventions (claim
-- simulation, pg_temp helpers, BEGIN ... ROLLBACK, exact plan, ADR-118/ADR-119
-- repairs: no file-level aborts, typed want-sides, no whole-table counts,
-- coalesced booleans, transaction-stable time).
--
-- Coverage, all contract-frozen: the member_imports v1 columns, composite
-- branch foreign key, branch index, digest/country checks and the partial
-- unique (tenant_id, request_key); the frozen RPC signatures, definer/search
-- path and execute grants; real-actor role gates on prepare and commit;
-- duplicate classification order (existing_phone / existing_member_code /
-- file_phone / file_member_code), case-sensitive member-code comparison,
-- cross-gym invisibility, skipped rows reserving no key; the frozen
-- effective day from the gym timezone, DB-added future_date errors combined
-- with phase-A errors, blank joined_on defaulting; report shape, partitions
-- and both counter equations; request-key exact replay vs GL068 fact
-- conflicts; commit probe semantics, GL064/GL063/22023/55000 refusals,
-- terminal replay for completed and failed runs, post-preview duplicate
-- reclassification (subset, never superset), rollback-to-failed with the
-- code-only processing_failed report; legacy rows not committable and not
-- upgradable; the invoker run-mutation invariant against direct inserts,
-- manufactured completion, legal-looking transition sequences and
-- v1-to-legacy clearing; preview-session refusal (42501 "Support preview is
-- read-only.") and caller RLS reads; retry under a new key reclassifying
-- imported phones; and no invented side effects (profile-only member facts,
-- no membership/payment/attendance/consent/auth user, audit evidence stays
-- inside the fixture tenant).
--
-- Interpretations the contract does not spell out as syntax, recorded here:
--   * p_rows uses exactly the canonical candidate payload keys (contract:
--     "Each object carries rowNumber and every whitelisted field").
--   * p_preclassified_report is a JSON array of {rowNumber, field,
--     reasonCode} items (contract: "contains all local field-invalid reasons
--     by row and field"); the exact envelope is not frozen.
--   * The prepare return envelope is not frozen, so replay is pinned through
--     the stored row (one run, retained day/report/digest) and the frozen
--     MemberImportCommitResult fields (status, replayed, counts) that the
--     contract says terminal results use; probe facts are pinned as
--     mentioned stored values.
--   * The processing-failure trigger is a candidate whose phone violates the
--     existing members E.164 check while claimed valid: phase-A phone
--     validation belongs to the handler, so the insert raises 23514, which
--     the contract consumes as "another unexpected database exception"
--     producing processing_failed.
--   * "An invoker run-mutation invariant refuses direct authenticated v1
--     inserts or updates" is pinned as a raise (attempt like 'error=%'), not
--     a silent zero-row filter, per the ADR-118 resolution; the refusal code
--     itself is not frozen and is not pinned.
--   * Branch refusals and unknown/cross-gym import ids are pinned as
--     indistinguishable refusals, not as a specific SQLSTATE.
--
-- Red against current code: the eight v1 columns, the two RPCs and their
-- grants do not exist, so every metadata assertion fails and every wrapped
-- call reports a missing-object state that the refusal pins explicitly
-- reject. True two-connection concurrency is the coordinator's (ADR-030
-- wraps the whole file in one transaction); this suite proves the
-- deterministic faces: serialized terminal replay, fresh-key conflicts and
-- the tenant-phone unique key as the final guard.
begin;
set local role postgres;
select plan(265);

-- ---------------------------------------------------------------- helpers --
create function pg_temp.h28_id(bucket integer, n integer) returns uuid
language sql immutable strict as $$
  select ('280000ff-0028-4000-8000-' || bucket::text || lpad(n::text,11,'0'))::uuid
$$;
create function pg_temp.h28_call(statement text) returns jsonb language plpgsql as $$
declare result jsonb; detail text; message text;
begin
  execute 'select to_jsonb(r) from ('||statement||') r' into strict result;
  return coalesce(result,'null'::jsonb) || jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail = pg_exception_detail, message = message_text;
  return jsonb_build_object('state',sqlstate,'message',message,'detail',detail);
end
$$;
create function pg_temp.h28_exec(statement text) returns jsonb language plpgsql as $$
declare detail text; message text;
begin
  execute statement;
  return jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail = pg_exception_detail, message = message_text;
  return jsonb_build_object('state',sqlstate,'message',message,'detail',detail);
end
$$;
create function pg_temp.h28_attempt(statement text) returns text language plpgsql as $$
declare affected bigint;
begin
  execute statement;
  get diagnostics affected = row_count;
  return 'rows=' || affected;
exception when others then
  return 'error=' || sqlstate;
end
$$;
create function pg_temp.h28_claim(role_name text default 'gym_owner',
  tenant integer default 1, staff integer default 1, member integer default null,
  sub integer default null, impersonate integer default null)
returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
    'role','authenticated','sub',pg_temp.h28_id(9,coalesce(sub,staff,member,1)),
    'app_role',role_name,'tenant_id',pg_temp.h28_id(1,tenant),
    'staff_id',pg_temp.h28_id(3,staff),'member_id',pg_temp.h28_id(5,member),
    'impersonation_session_id',pg_temp.h28_id(6,impersonate)))::text,true)
$$;
create function pg_temp.h28_missing(p_state text) returns boolean language sql immutable as $$
  select coalesce(p_state,'') in ('42883','42P01','42703','42601','42704')
$$;
create function pg_temp.h28_mentions(p_outcome jsonb, needle text) returns boolean language sql immutable as $$
  select coalesce(position(needle in coalesce(p_outcome::text,'')),0) > 0
$$;
create function pg_temp.h28_items(p_report jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_array(e.item->'rowNumber', e.item->>'disposition',
    e.item->>'reasonCode') order by e.ord),'[]'::jsonb)
  from jsonb_array_elements(coalesce(p_report,'[]'::jsonb)) with ordinality as e(item, ord)
$$;
create function pg_temp.h28_fields(p_report jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(e.item->>'field' order by e.ord),'[]'::jsonb)
  from jsonb_array_elements(coalesce(p_report,'[]'::jsonb)) with ordinality as e(item, ord)
$$;
create temp table h28_runs(n integer primary key, run_id uuid);
create temp table h28_seen(name text primary key, value jsonb);
create temp table h28_counts(name text primary key, n bigint);
grant all on h28_runs, h28_seen, h28_counts to public;
create function pg_temp.h28_rid(p_slot integer) returns uuid language sql as $$
  select run_id from h28_runs where n = p_slot
$$;
create function pg_temp.h28_run(p_slot integer) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute format('select to_jsonb(mi) from public.member_imports mi where mi.id = %L::uuid',
    pg_temp.h28_rid(p_slot)) into v;
  return v;
exception when others then return null;
end
$$;
create function pg_temp.h28_runs_for(p_tenant integer, p_key uuid) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from public.member_imports where tenant_id = %L::uuid and request_key = %L::uuid',
    pg_temp.h28_id(1,p_tenant), p_key) into n;
  return n;
exception when others then return null;
end
$$;
create function pg_temp.h28_prepare(p_tenant integer, p_slot integer, p_key uuid,
  p_name text, p_sha text, p_parser text, p_branch integer, p_country text,
  p_mapping jsonb, p_row_count integer, p_rows jsonb, p_report jsonb)
returns jsonb language plpgsql as $$
declare v_outcome jsonb; v_run uuid;
begin
  v_outcome := pg_temp.h28_call(format(
    'select public.prepare_member_import(%L::uuid,%L,%L,%L,%L::uuid,%L,%L::jsonb,%s,%L::jsonb,%L::jsonb) as value',
    p_key, p_name, p_sha, p_parser, pg_temp.h28_id(2,p_branch), p_country,
    p_mapping::text, p_row_count, p_rows::text, p_report::text));
  if v_outcome->>'state' = '00000' then
    begin
      select mi.id into v_run from public.member_imports mi
       where mi.tenant_id = pg_temp.h28_id(1,p_tenant) and mi.request_key = p_key;
      insert into h28_runs(n, run_id) values (p_slot, v_run) on conflict (n) do nothing;
    exception when others then null;
    end;
  end if;
  return v_outcome;
end
$$;
create function pg_temp.h28_commit(p_run uuid, p_sha text, p_rows jsonb) returns jsonb language plpgsql as $$
begin
  if p_rows is null then
    return pg_temp.h28_call(format('select public.commit_member_import(%L::uuid,%L,null) as value', p_run, p_sha));
  end if;
  return pg_temp.h28_call(format('select public.commit_member_import(%L::uuid,%L,%L::jsonb) as value', p_run, p_sha, p_rows::text));
end
$$;
create function pg_temp.h28_prepare_f1(p_slot integer, p_key uuid, p_name text, p_sha text,
  p_parser text, p_branch integer, p_country text, p_mapping jsonb, p_rows jsonb)
returns jsonb language plpgsql as $$
declare v_rows jsonb;
begin
  select coalesce(p_rows, jsonb_agg(jsonb_build_object(
      'rowNumber',f.n,'full_name',f.full_name,'phone',f.phone,'member_code',f.member_code,
      'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
      'joined_on',f.joined_on,'notes',f.notes) order by f.n))
  into v_rows
  from h28_f1 f;
  return pg_temp.h28_prepare(1, p_slot, p_key, p_name, p_sha, p_parser, p_branch, p_country,
    p_mapping, 13, v_rows, (select value from h28_seen where name='f1-report'));
end
$$;
create function pg_temp.h28_prepare_k5() returns jsonb language plpgsql as $$
begin
  return pg_temp.h28_prepare(1, 5, pg_temp.h28_id(8,5), 'h28-key5.csv', repeat('55',32),
    'h28-parser-v1', 1, 'IN', '{"full_name":0,"phone":1}'::jsonb, 1,
    (select value from h28_seen where name='k5-rows'), '[]'::jsonb);
end
$$;
do $grant$
begin
  execute format('grant usage on schema %I to public', pg_my_temp_schema()::regnamespace);
end
$grant$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------- A. frozen metadata ----
select has_column('public','member_imports','branch_id','H28 the run records its selected branch');
select col_type_is('public','member_imports','branch_id','uuid','H28 branch_id is a UUID');
select has_column('public','member_imports','request_key','H28 the run records its replay key');
select col_type_is('public','member_imports','request_key','uuid','H28 request_key is a UUID');
select has_column('public','member_imports','file_sha256','H28 the run records the raw file digest');
select col_type_is('public','member_imports','file_sha256','text','H28 file_sha256 is text');
select has_column('public','member_imports','parser_contract','H28 the run records the parser contract');
select col_type_is('public','member_imports','parser_contract','text','H28 parser_contract is text');
select has_column('public','member_imports','phone_default_country','H28 the run records the typed phone-country mode');
select col_type_is('public','member_imports','phone_default_country','text','H28 phone_default_country is text');
select has_column('public','member_imports','effective_on','H28 the run records the frozen effective day');
select col_type_is('public','member_imports','effective_on','date','H28 effective_on is a date');
select has_column('public','member_imports','uploaded_by_user_id','H28 the run records the winning JWT user');
select col_type_is('public','member_imports','uploaded_by_user_id','uuid','H28 uploaded_by_user_id is a UUID');
select has_column('public','member_imports','candidate_payload_sha256','H28 the run records the candidate digest');
select col_type_is('public','member_imports','candidate_payload_sha256','text','H28 candidate_payload_sha256 is text');
select col_is_null('public','member_imports','branch_id','H28 pre-migration rows may lack a branch');
select col_is_null('public','member_imports','request_key','H28 pre-migration rows may lack a request key');
select col_is_null('public','member_imports','file_sha256','H28 pre-migration rows may lack a file digest');
select col_is_null('public','member_imports','parser_contract','H28 pre-migration rows may lack a parser contract');
select col_is_null('public','member_imports','phone_default_country','H28 pre-migration rows may lack a country mode');
select col_is_null('public','member_imports','effective_on','H28 pre-migration rows may lack an effective day');
select col_is_null('public','member_imports','uploaded_by_user_id','H28 pre-migration rows may lack a JWT user');
select col_is_null('public','member_imports','candidate_payload_sha256','H28 pre-migration rows may lack a candidate digest');
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.member_imports'::regclass
  and c.contype='f' and c.confrelid='public.branches'::regclass
  and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.conrelid and attname='branch_id')]
  and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.confrelid and attname='id')]),
  'H28 the run carries a same-tenant composite branch foreign key');
select ok(exists(select 1 from pg_index i
  where i.indrelid='public.member_imports'::regclass
  and pg_get_indexdef(i.indexrelid,1,true)='branch_id'),
  'H28 the branch column is indexed');
select ok(exists(select 1 from pg_index i
  where i.indrelid='public.member_imports'::regclass and i.indisunique
  and pg_get_indexdef(i.indexrelid,1,true)='tenant_id'
  and pg_get_indexdef(i.indexrelid,2,true)='request_key'
  and pg_get_expr(i.indpred,i.indrelid)='(request_key IS NOT NULL)'),
  'H28 request keys are unique per tenant where present');
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.member_imports'::regclass
  and c.contype='c' and position('file_sha256' in pg_get_constraintdef(c.oid)) > 0),
  'H28 a check constraint governs the stored raw-file digest');
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.member_imports'::regclass
  and c.contype='c' and position('phone_default_country' in pg_get_constraintdef(c.oid)) > 0),
  'H28 a check constraint governs the phone-country mode');
select ok(to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)') is not null,
  'H28 prepare_member_import exists with the frozen ten-argument signature');
select is((select p.prorettype from pg_proc p
  where p.oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),
  'jsonb'::regtype,'H28 prepare returns jsonb');
select is((select p.pronargs from pg_proc p
  where p.oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),
  10::smallint,'H28 prepare arity is frozen at ten');
select ok(coalesce((select p.prosecdef and 'search_path=""'=any(p.proconfig) from pg_proc p
  where p.oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),false),
  'H28 prepare is a definer command with a fixed safe search path');
select is((select p.proowner from pg_proc p
  where p.oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),
  'postgres'::regrole,'H28 prepare is postgres-owned');
select ok(coalesce((select has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p
  where p.oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),false),
  'H28 prepare is executable only by authenticated application callers');
select ok(to_regprocedure('public.commit_member_import(uuid,text,jsonb)') is not null,
  'H28 commit_member_import exists with the frozen three-argument signature');
select is((select p.prorettype from pg_proc p
  where p.oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),
  'jsonb'::regtype,'H28 commit returns jsonb');
select is((select p.pronargs from pg_proc p
  where p.oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),
  3::smallint,'H28 commit arity is frozen at three');
select ok(coalesce((select p.prosecdef and 'search_path=""'=any(p.proconfig) from pg_proc p
  where p.oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),false),
  'H28 commit is a definer command with a fixed safe search path');
select is((select p.proowner from pg_proc p
  where p.oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),
  'postgres'::regrole,'H28 commit is postgres-owned');
select ok(coalesce((select has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p
  where p.oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),false),
  'H28 commit is executable only by authenticated application callers');

-- --------------------------------------------------------- B. fixtures ----
insert into public.organizations(id,name,gym_code,timezone,currency,status) values
  (pg_temp.h28_id(1,1),'H28 Import Gym A','H28IMA','Asia/Kolkata','INR','active'),
  (pg_temp.h28_id(1,2),'H28 Import Gym B','H28IMB','Pacific/Kiritimati','INR','active');
insert into public.branches(id,tenant_id,name,is_default) values
  (pg_temp.h28_id(2,1),pg_temp.h28_id(1,1),'H28 Branch One',true),
  (pg_temp.h28_id(2,2),pg_temp.h28_id(1,1),'H28 Branch Two',false),
  (pg_temp.h28_id(2,3),pg_temp.h28_id(1,2),'H28 Branch Foreign',true);
insert into auth.users(id) select pg_temp.h28_id(9,n) from generate_series(1,9) n;
insert into public.platform_users(user_id,role,full_name,email,is_active) values
  (pg_temp.h28_id(9,7),'super_admin','H28 Platform Super','h28super@example.test',true),
  (pg_temp.h28_id(9,8),'platform_support','H28 Platform Support','h28support@example.test',true);
insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
  (pg_temp.h28_id(3,1),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),pg_temp.h28_id(9,1),'gym_owner','H28 Owner',true),
  (pg_temp.h28_id(3,2),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),pg_temp.h28_id(9,2),'gym_manager','H28 Manager',true),
  (pg_temp.h28_id(3,3),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),pg_temp.h28_id(9,3),'front_desk','H28 Desk',true),
  (pg_temp.h28_id(3,4),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),pg_temp.h28_id(9,4),'trainer','H28 Trainer',true),
  (pg_temp.h28_id(3,5),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),pg_temp.h28_id(9,5),'gym_owner','H28 Inactive Owner',false),
  (pg_temp.h28_id(3,6),pg_temp.h28_id(1,2),pg_temp.h28_id(2,3),pg_temp.h28_id(9,6),'gym_owner','H28 Owner B',true),
  (pg_temp.h28_id(3,7),pg_temp.h28_id(1,1),pg_temp.h28_id(2,2),pg_temp.h28_id(9,9),'gym_manager','H28 Manager Two',true),
  (pg_temp.h28_id(3,8),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),null,'gym_owner','H28 Unlinked Owner',true);
insert into public.members(id,tenant_id,branch_id,member_code,full_name,phone,status,joined_on) values
  (pg_temp.h28_id(5,1),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),'H28A','H28 Member One','+919281000001','active','2026-09-01'),
  (pg_temp.h28_id(5,2),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),'h28lower','H28 Member Two','+919281000002','active','2026-09-01'),
  (pg_temp.h28_id(5,3),pg_temp.h28_id(1,2),pg_temp.h28_id(2,3),null,'H28 Member Foreign','+919281000010','active','2026-09-01');
insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,expires_at) values
  (pg_temp.h28_id(6,1),pg_temp.h28_id(1,1),pg_temp.h28_id(9,7),'H28 import preview',transaction_timestamp()+interval '45 minutes');
-- Legacy rows in the pre-migration shape: the contract keeps them historical.
insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report) values
  (pg_temp.h28_id(7,901),pg_temp.h28_id(1,1),pg_temp.h28_id(3,1),'h28-legacy-done.csv','{"full_name":0,"phone":1}','completed',3,3,0,null),
  (pg_temp.h28_id(7,902),pg_temp.h28_id(1,1),pg_temp.h28_id(3,1),'h28-legacy-pending.csv','{"full_name":0,"phone":1}','pending',null,null,null,null);
create temp table h28_eff(t1 date, t2 date, eff1 text, eff2 text, fut1 text);
insert into h28_eff select t1, t2, to_char(t1,'YYYY-MM-DD'), to_char(t2,'YYYY-MM-DD'), to_char(t1+1,'YYYY-MM-DD')
  from (values ((transaction_timestamp() at time zone 'Asia/Kolkata')::date,
                (transaction_timestamp() at time zone 'Pacific/Kiritimati')::date)) v(t1,t2);
create temp table h28_f1(n integer primary key, full_name text, phone text, member_code text,
  email text, gender text, date_of_birth text, joined_on text, notes text);
insert into h28_f1 values
  (2,'Asha Rao','+919876543210',null,null,null,null,'2020-01-02',null),
  (3,'Ben Bose','+919828000003','H28C1','ben@example.test','male','2000-01-31','2020-01-03',null),
  (4,'Chandra Cho','+919281000001',null,null,null,null,null,null),
  (5,'Dev Das','+919285000005','H28A',null,null,null,null,null),
  (6,'Firoz Khan','+919285000005','H28R6',null,null,null,null,null),
  (7,'Gita Gupta','+919876543210',null,null,null,null,null,null),
  (8,'Hari Har','+919287000008','H28C1',null,null,null,null,null),
  (9,null,null,null,null,null,null,null,'h28 row nine notes'),
  (10,'Jaya Joshi','+919288000010',null,null,null,null,(select fut1 from h28_eff),null),
  (11,'Kiran Kaur',null,null,null,null,(select fut1 from h28_eff),null,null),
  (12,'Isha Iyer','+919286000012',null,null,null,null,null,null),
  (13,'Jay Jain','+919281000010',null,null,null,null,null,null),
  (14,'Kabir Kaul','+919283000014','H28LOWER',null,null,null,null,null);
create temp table h28_f2(n integer primary key, full_name text, phone text, member_code text,
  email text, gender text, date_of_birth text, joined_on text, notes text);
insert into h28_f2 values
  (2,'H28 Zoya Zame','+919289000021',null,null,null,null,null,null),
  (3,'H28 Yusuf You','+919289000022',null,null,null,null,null,null),
  (4,'H28 Wahan Waz','+919281000002',null,null,null,null,null,null);
create temp table h28_f3(n integer primary key, full_name text, phone text, member_code text,
  email text, gender text, date_of_birth text, joined_on text, notes text);
insert into h28_f3 values
  (2,'H28 Fail Fay','not-a-phone',null,null,null,null,null,null),
  (3,'H28 Good Gau','+919289000033',null,null,null,null,null,null);
create temp table h28_obj1(n integer, obj jsonb);
insert into h28_obj1 select f.n, jsonb_build_object('rowNumber',f.n,'full_name',f.full_name,
  'phone',f.phone,'member_code',f.member_code,'email',f.email,'gender',f.gender,
  'date_of_birth',f.date_of_birth,'joined_on',coalesce(f.joined_on,(select eff1 from h28_eff)),'notes',f.notes)
  from h28_f1 f;
grant all on h28_eff, h28_f1, h28_f2, h28_f3, h28_obj1 to public;
insert into h28_counts values ('auth-users', (select count(*) from auth.users));
insert into h28_seen(name,value) values
  ('f1-report','[{"rowNumber":9,"field":"full_name","reasonCode":"required"},{"rowNumber":9,"field":"phone","reasonCode":"ambiguous_phone"},{"rowNumber":11,"field":"phone","reasonCode":"ambiguous_phone"}]'::jsonb),
  ('want-items','[[4,"duplicate","existing_phone"],[5,"duplicate","existing_member_code"],[7,"duplicate","file_phone"],[8,"duplicate","file_member_code"],[9,"invalid","required"],[9,"invalid","ambiguous_phone"],[10,"invalid","future_date"],[11,"invalid","ambiguous_phone"],[11,"invalid","future_date"]]'::jsonb),
  ('want-fields','["phone","member_code","phone","member_code","full_name","phone","joined_on","phone","date_of_birth"]'::jsonb),
  ('want-cand','[2,3,6,12,13,14]'::jsonb),
  ('want-summary','{"invalid":3,"duplicate":4}'::jsonb),
  ('k5-rows','[{"rowNumber":2,"full_name":"H28 Key Five","phone":"+919289000055","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb),
  ('t2-rows','[{"rowNumber":2,"full_name":"H28 Tara Tres","phone":"+68273000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb),
  ('b2-rows','[{"rowNumber":2,"full_name":"H28 Branch Two Row","phone":"+919289000066","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb);
insert into h28_seen(name,value) select 'r1-cand', jsonb_agg(obj order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13,14]);
insert into h28_seen(name,value) select 'r1-cand-renamed',
  jsonb_agg(case when n=2 then obj || '{"full_name":"Asha Rao Renamed"}'::jsonb else obj end order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13,14]);
insert into h28_seen(name,value) select 'r1-cand-missing', jsonb_agg(obj order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13]);
insert into h28_seen(name,value) select 'r1-cand-extra', jsonb_agg(obj order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13,14,4]);
insert into h28_seen(name,value) select 'r1-cand-unknownkey',
  jsonb_agg(case when n=2 then obj || '{"status":"active"}'::jsonb else obj end order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13,14]);
insert into h28_seen(name,value) select 'r1-cand-omitted',
  jsonb_agg(case when n=2 then obj - 'notes' else obj end order by n)
  from h28_obj1 where n = any(array[2,3,6,12,13,14]);
insert into h28_seen(name,value) select 'r1-cand-dup', value || jsonb_build_array(value->0)
  from h28_seen where name='r1-cand';

-- ------------------------------------- C. who may call prepare (CSV-D01) --
select pg_temp.h28_claim();
set local role authenticated;
select pg_temp.h28_claim('trainer',1,4);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a trainer cannot prepare an import');
select pg_temp.h28_claim('member',1,null,1);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a member cannot prepare an import');
select pg_temp.h28_claim('front_desk',1,3);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 front desk cannot prepare an import');
select pg_temp.h28_claim('platform_support',null,null,null,8);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 platform support cannot prepare an import');
select pg_temp.h28_claim('super_admin',null,null,null,7);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 super admin cannot prepare through the gym-side command');
select pg_temp.h28_claim('gym_owner',1,null,null,7,1);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 an impersonating gym_owner without a staff_id is refused');
select pg_temp.h28_claim('gym_owner',1,1,null,1,1);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 an impersonation session is refused explicitly even with a staff claim');
select pg_temp.h28_claim('gym_owner',1,null);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a gym_owner claim without a staff_id is refused');
select pg_temp.h28_claim('gym_owner',1,5);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 an inactive staff identity is refused');
select pg_temp.h28_claim('gym_owner',1,6);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a staff row from another gym is not a complete identity');
select pg_temp.h28_claim('gym_owner',1,999);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a staff claim naming no real row is refused');
select pg_temp.h28_claim('gym_owner',1,1,null,3);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a staff row linked to a different JWT user is refused');
select pg_temp.h28_claim('gym_owner',1,8);
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 a staff row with no auth-user link is refused');
set local role anon;
select is(pg_temp.h28_prepare_k5()->>'state','42501','H28 anon holds no execute on the command');
set local role authenticated;
select pg_temp.h28_claim();
select is(pg_temp.h28_prepare_k5()->>'state','00000','H28 a refused request key stays reusable');
select is(pg_temp.h28_run(5)->>'status','pending','H28 the retried prepare won a fresh pending run');

-- ----------------------- D. prepare input refusals create no run (CSV-D02) --
select ok(coalesce(pg_temp.h28_prepare(1,91,pg_temp.h28_id(8,91),'h28-b1.csv',repeat('55',32),'h28-parser-v1',999,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state' <> '00000'
  and not pg_temp.h28_missing(pg_temp.h28_prepare(1,91,pg_temp.h28_id(8,91),'h28-b1.csv',repeat('55',32),'h28-parser-v1',999,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state'),false),
  'H28 an unknown branch is a refusal');
select ok(coalesce(pg_temp.h28_prepare(1,92,pg_temp.h28_id(8,92),'h28-b2.csv',repeat('55',32),'h28-parser-v1',3,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state' <> '00000'
  and not pg_temp.h28_missing(pg_temp.h28_prepare(1,92,pg_temp.h28_id(8,92),'h28-b2.csv',repeat('55',32),'h28-parser-v1',3,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state'),false),
  'H28 a cross-gym branch is a refusal');
select is(pg_temp.h28_prepare(1,91,pg_temp.h28_id(8,91),'h28-b1.csv',repeat('55',32),'h28-parser-v1',999,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state',
  pg_temp.h28_prepare(1,92,pg_temp.h28_id(8,92),'h28-b2.csv',repeat('55',32),'h28-parser-v1',3,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state',
  'H28 unknown and cross-gym branches are indistinguishable');
select ok(coalesce(pg_temp.h28_run(91) is null and pg_temp.h28_run(92) is null,false),
  'H28 the refused branch requests created no run');
select ok(coalesce(pg_temp.h28_prepare(1,93,pg_temp.h28_id(8,93),'h28-b3.csv',repeat('A1',32),'h28-parser-v1',1,'IN','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state' <> '00000'
  and pg_temp.h28_run(93) is null,false),
  'H28 a non-lowercase raw-file digest is refused without a run');
select ok(coalesce(pg_temp.h28_prepare(1,94,pg_temp.h28_id(8,94),'h28-b4.csv',repeat('55',32),'h28-parser-v1',1,'US','{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='k5-rows'),'[]'::jsonb)->>'state' <> '00000'
  and pg_temp.h28_run(94) is null,false),
  'H28 an unsupported phone-country mode is refused without a run');

-- --------------- E. a won prepare stores complete immutable evidence ------
insert into h28_seen values ('k1-prepare', pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1),
  'h28-members.csv', repeat('a1',32), 'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null));
select is((select value->>'state' from h28_seen where name='k1-prepare'),'00000','H28 an active owner wins a prepare');
select is(pg_temp.h28_runs_for(1, pg_temp.h28_id(8,1)),1::bigint,'H28 the won prepare created exactly one run for its key');
insert into h28_seen values ('k1-run', pg_temp.h28_run(1));
select is((select value->>'status' from h28_seen where name='k1-run'),'pending','H28 a new v1 run starts pending');
select is((select value->>'row_count' from h28_seen where name='k1-run'),'13','H28 the run records every non-blank source row');
select is((select value->>'imported_count' from h28_seen where name='k1-run'),'0','H28 a pending run has imported nothing');
select is((select value->>'duplicate_count' from h28_seen where name='k1-run'),'4','H28 the preview classified four duplicate rows');
select ok(coalesce((select value->'error_report' is not null from h28_seen where name='k1-run'),false),
  'H28 a pending run carries a non-null report');
select is((select value->'error_report'->>'version' from h28_seen where name='k1-run'),'1','H28 the report is the versioned v1 shape');
select is((select value->'error_report'->'summary' from h28_seen where name='k1-run'),
  (select value from h28_seen where name='want-summary'),'H28 the summary counts the preview dispositions');
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k1-run'),
  (select value from h28_seen where name='want-cand'),'H28 the report names the preview candidates in ascending order');
select is((select value->'error_report'->'importedRows' from h28_seen where name='k1-run'),'[]'::jsonb,
  'H28 a pending report has imported no rows');
select ok(coalesce((select value->'error_report'->>'failure' is null from h28_seen where name='k1-run'),false),
  'H28 a pending report carries no failure');
select is((select pg_temp.h28_items(value->'error_report'->'rows') from h28_seen where name='k1-run'),
  (select value from h28_seen where name='want-items'),'H28 one ordered report item per reason across duplicates and invalids');
select is((select pg_temp.h28_fields(value->'error_report'->'rows') from h28_seen where name='k1-run'),
  (select value from h28_seen where name='want-fields'),'H28 each report item names its allowlisted field');
select is((select value->>'tenant_id' from h28_seen where name='k1-run'),pg_temp.h28_id(1,1)::text,
  'H28 the run is tenant-scoped');
select is((select value->>'uploaded_by_staff_id' from h28_seen where name='k1-run'),pg_temp.h28_id(3,1)::text,
  'H28 the run derives the acting staff identity, never a caller choice');
select is((select value->>'uploaded_by_user_id' from h28_seen where name='k1-run'),pg_temp.h28_id(9,1)::text,
  'H28 the run derives the winning JWT user identity');
select is((select value->>'file_name' from h28_seen where name='k1-run'),'h28-members.csv','H28 the sanitized filename is stored');
select is((select value->>'file_sha256' from h28_seen where name='k1-run'),repeat('a1',32),'H28 the raw file digest is stored');
select is((select value->>'parser_contract' from h28_seen where name='k1-run'),'h28-parser-v1','H28 the parser contract is stored');
select is((select value->>'phone_default_country' from h28_seen where name='k1-run'),'IN','H28 the typed country mode is stored non-null');
select is((select value->>'branch_id' from h28_seen where name='k1-run'),pg_temp.h28_id(2,1)::text,'H28 the selected branch is stored');
select is((select value->>'request_key' from h28_seen where name='k1-run'),pg_temp.h28_id(8,1)::text,'H28 the request key is stored');
select is((select value->>'effective_on' from h28_seen where name='k1-run'),(select eff1 from h28_eff),
  'H28 the effective day is frozen from the gym timezone');
select is((select value->'column_mapping' from h28_seen where name='k1-run'),
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,
  'H28 the canonical mapping is stored');
select matches(coalesce((select value->>'candidate_payload_sha256' from h28_seen where name='k1-run'),'h28-none'),
  '^[0-9a-f]{64}$','H28 the candidate digest is a lowercase SHA-256');
select is((select jsonb_array_length(value->'error_report'->'previewCandidateRows') from h28_seen where name='k1-run'),6,
  'H28 the pending partition holds six would-import rows');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
  and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014'])),
  0::bigint,'H28 a preview writes no member');

-- ------------- F. exact replay vs immutable-fact conflicts (CSV-D08) ------
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  '00000','H28 an exact sequential replay is accepted');
select is(pg_temp.h28_runs_for(1, pg_temp.h28_id(8,1)),1::bigint,'H28 the replay created no second run');
select is(pg_temp.h28_run(1)->>'effective_on',(select eff1 from h28_eff),
  'H28 the replay retains the winning effective day');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,
  (select jsonb_agg(jsonb_build_object('rowNumber',f.n,
    'full_name',case when f.n=2 then 'H28 Asha Second' else f.full_name end,'phone',f.phone,
    'member_code',f.member_code,'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
    'joined_on',f.joined_on,'notes',f.notes) order by f.n) from h28_f1 f))->>'state',
  '00000','H28 row input is not part of the replay identity');
select is(pg_temp.h28_runs_for(1, pg_temp.h28_id(8,1)),1::bigint,'H28 the changed-rows retry still created no second run');
select is(pg_temp.h28_run(1)->>'candidate_payload_sha256',(select value->>'candidate_payload_sha256' from h28_seen where name='k1-run'),
  'H28 the replay keeps the winning candidate digest without reclassification');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('c3',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed file digest conflicts');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-renamed.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed filename conflicts');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v2', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed parser contract conflicts');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 2, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed branch conflicts');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'E164',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed country mode conflicts');
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN', '{"full_name":0,"phone":1}'::jsonb, null)->>'state',
  'GL068','H28 a reused key with a changed mapping conflicts');
select pg_temp.h28_claim('gym_manager',1,2);
select is(pg_temp.h28_prepare_f1(1, pg_temp.h28_id(8,1), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  'GL068','H28 another authorized actor cannot replay someone else''s request key');
select pg_temp.h28_claim();
select is(pg_temp.h28_runs_for(1, pg_temp.h28_id(8,1)),1::bigint,'H28 the fact conflicts left exactly one run');

-- --------------------- G. the replay key is tenant-scoped (CSV-D07/D08) ---
select pg_temp.h28_claim('gym_owner',2,6);
select is(pg_temp.h28_prepare(2,101,pg_temp.h28_id(8,1),'h28-t2.csv',repeat('e5',32),'h28-parser-v1',3,'E164',
  '{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='t2-rows'),'[]'::jsonb)->>'state',
  '00000','H28 another gym reuses the same request key value independently');
select is(pg_temp.h28_run(101)->>'effective_on',(select eff2 from h28_eff),
  'H28 the other gym''s effective day is frozen from its own timezone');
select is(pg_temp.h28_run(101)->>'status','pending','H28 the foreign run rests at pending');
select is(pg_temp.h28_prepare(2,101,pg_temp.h28_id(8,1),'h28-t2.csv',repeat('e5',32),'h28-parser-v1',3,'E164',
  '{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='t2-rows'),'[]'::jsonb)->>'state',
  '00000','H28 the foreign gym replays its own key');
select is(pg_temp.h28_runs_for(2, pg_temp.h28_id(8,1)),1::bigint,'H28 the foreign replay created no second run');
select pg_temp.h28_claim();
select is(pg_temp.h28_runs_for(1, pg_temp.h28_id(8,1)),1::bigint,'H28 the first gym''s run for the reused key value is untouched');
select pg_temp.h28_claim();
select is(pg_temp.h28_prepare(1,6,pg_temp.h28_id(8,6),'h28-b2.csv',repeat('66',32),'h28-parser-v1',2,'IN',
  '{"full_name":0,"phone":1}'::jsonb,1,(select value from h28_seen where name='b2-rows'),'[]'::jsonb)->>'state',
  '00000','H28 a second same-tenant branch is a legal whole-file target');
select is(pg_temp.h28_run(6)->>'status','pending','H28 the branch-two run rests at pending');

-- -------------------------- H. caller read RLS on the run (CSV-D01) ------
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),1::bigint,
  'H28 the preparing owner reads the run through RLS');
select pg_temp.h28_claim('gym_manager',1,2);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),1::bigint,
  'H28 a manager reads the run through RLS');
select pg_temp.h28_claim('trainer',1,4);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),0::bigint,
  'H28 a trainer inspects no import run');
select pg_temp.h28_claim('member',1,null,1);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),0::bigint,
  'H28 a member inspects no import run');
select pg_temp.h28_claim('gym_owner',2,6);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),0::bigint,
  'H28 another gym''s owner reads no foreign run');
select pg_temp.h28_claim('platform_support',null,null,null,8);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),1::bigint,
  'H28 the preserved platform read policy still shows the run to support');
select pg_temp.h28_claim('super_admin',null,null,null,7);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),1::bigint,
  'H28 the preserved platform read policy still shows the run to super admin');
select pg_temp.h28_claim('gym_owner',1,null,null,7,1);
select is((select count(*) from public.member_imports where id = pg_temp.h28_rid(1)),0::bigint,
  'H28 an impersonating token inspects no import run');
set local role anon;
select is(pg_temp.h28_attempt(format('select count(*) from public.member_imports where id = %L::uuid',pg_temp.h28_rid(1))),
  'error=42501','H28 anon holds no import read at all');
set local role authenticated;
select pg_temp.h28_claim();

-- --------------------- I. commit probe and authorization (CSV-D09) ------
insert into h28_seen values ('r1-probe', pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null));
select is((select value->>'state' from h28_seen where name='r1-probe'),'00000','H28 the SQL-null state probe succeeds on a pending run');
select is(pg_temp.h28_run(1)->>'status','pending','H28 the probe leaves the run pending');
select is(pg_temp.h28_run(1)->>'candidate_payload_sha256',(select value->>'candidate_payload_sha256' from h28_seen where name='k1-run'),
  'H28 the probe writes nothing to the stored evidence');
select ok(pg_temp.h28_mentions((select value->'value' from h28_seen where name='r1-probe'),'h28-parser-v1'),
  'H28 the probe returns the stored parser contract');
select ok(pg_temp.h28_mentions((select value->'value' from h28_seen where name='r1-probe'),(select eff1 from h28_eff)),
  'H28 the probe returns the stored effective day');
select ok(pg_temp.h28_mentions((select value->'value' from h28_seen where name='r1-probe'),pg_temp.h28_id(2,1)::text),
  'H28 the probe returns the stored branch');
select ok(pg_temp.h28_mentions((select value->'value' from h28_seen where name='r1-probe'),'"phone"'),
  'H28 the probe returns the stored mapping');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('c3',32), null)->>'state','GL064',
  'H28 a byte mismatch on the probe is GL064');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('c3',32), (select value from h28_seen where name='r1-cand'))->>'state','GL064',
  'H28 the raw-file digest is checked before any row input');
select is(pg_temp.h28_run(1)->>'status','pending','H28 a byte mismatch leaves the run pending');
select pg_temp.h28_claim('gym_manager',1,2);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501',
  'H28 a real manager who does not own the preview cannot commit it');
select pg_temp.h28_claim('gym_owner',2,6);
insert into h28_seen values ('commit-crossgym', pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null));
select ok(coalesce((select value->>'state' from h28_seen where name='commit-crossgym') <> '00000'
  and not pg_temp.h28_missing((select value->>'state' from h28_seen where name='commit-crossgym')),false),
  'H28 another gym''s owner cannot commit a foreign run');
insert into h28_seen values ('commit-unknown', pg_temp.h28_commit(pg_temp.h28_id(7,998), repeat('a1',32), null));
select ok(coalesce((select value->>'state' from h28_seen where name='commit-unknown') <> '00000'
  and not pg_temp.h28_missing((select value->>'state' from h28_seen where name='commit-unknown')),false),
  'H28 an unknown import id is a refusal');
select is((select value->>'state' from h28_seen where name='commit-crossgym'),
  (select value->>'state' from h28_seen where name='commit-unknown'),
  'H28 cross-gym and unknown import ids are indistinguishable');
select pg_temp.h28_claim('trainer',1,4);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 a trainer cannot commit');
select pg_temp.h28_claim('member',1,null,1);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 a member cannot commit');
select pg_temp.h28_claim('front_desk',1,3);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 front desk cannot commit');
select pg_temp.h28_claim('platform_support',null,null,null,8);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 platform support cannot commit');
select pg_temp.h28_claim('super_admin',null,null,null,7);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 super admin cannot commit through the gym-side command');
select pg_temp.h28_claim('gym_owner',1,null,null,7,1);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 an impersonation session cannot commit');
set local role anon;
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501','H28 anon cannot commit');
set local role authenticated;
select pg_temp.h28_claim();
select is(pg_temp.h28_run(1)->>'status','pending','H28 every refused commit left the run pending');

-- ------------- J. malformed input and payload binding (CSV-D09a) --------
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), '{"rowNumber":2}'::jsonb)->>'state','22023',
  'H28 non-array row input is malformed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), 'null'::jsonb)->>'state','22023',
  'H28 JSON null row input is malformed, not a probe');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-unknownkey'))->>'state','22023',
  'H28 an unknown candidate key is malformed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-omitted'))->>'state','22023',
  'H28 an omitted candidate key is malformed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-dup'))->>'state','22023',
  'H28 duplicate candidate row numbers are malformed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32),
  (select jsonb_agg(jsonb_build_object('rowNumber',g+1,'full_name','H28 Cap Row','phone','+919299000001',
    'member_code',null,'email',null,'gender',null,'date_of_birth',null,'joined_on','2020-01-02','notes',null) order by g)
   from generate_series(1,5001) g))->>'state','22023',
  'H28 more than five thousand candidate elements are malformed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-renamed'))->>'state','GL063',
  'H28 a changed profile value with unchanged row numbers fails the digest');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-missing'))->>'state','GL063',
  'H28 a missing candidate row fails the exact row set');
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand-extra'))->>'state','GL063',
  'H28 an extra candidate row fails the exact row set');
select is(pg_temp.h28_run(1)->>'status','pending','H28 the payload refusals leave the run pending');
select is(pg_temp.h28_run(1)->>'candidate_payload_sha256',(select value->>'candidate_payload_sha256' from h28_seen where name='k1-run'),
  'H28 the payload refusals never touched the stored digest');

-- ------------------------------- K. a successful commit (CSV-D09..D14) --
insert into h28_seen values ('r1-commit', pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand')));
select is((select value->>'state' from h28_seen where name='r1-commit'),'00000','H28 the uploader commits the exact preview file');
select is((select value->'value'->>'status' from h28_seen where name='r1-commit'),'completed','H28 the result reports completed');
select is((select value->'value'->>'replayed' from h28_seen where name='r1-commit'),'false','H28 the first commit is not a replay');
select is((select value->'value'->'counts'->>'rows' from h28_seen where name='r1-commit'),'13','H28 the result counts every source row');
select is((select value->'value'->'counts'->>'imported' from h28_seen where name='r1-commit'),'6','H28 the result counts the six imported rows');
select is((select value->'value'->'counts'->>'duplicates' from h28_seen where name='r1-commit'),'4','H28 the result counts duplicate rows, not reasons');
select is((select value->'value'->'counts'->>'invalid' from h28_seen where name='r1-commit'),'3','H28 the result counts invalid rows');
set local role postgres;
insert into h28_seen values ('k1-run2', pg_temp.h28_run(1));
select is((select value->>'status' from h28_seen where name='k1-run2'),'completed','H28 the run moved to completed');
select is((select value->>'imported_count' from h28_seen where name='k1-run2'),'6','H28 the run records six imported members');
select is((select value->>'duplicate_count' from h28_seen where name='k1-run2'),'4','H28 the completed run keeps its duplicate count');
select is((select value->>'row_count' from h28_seen where name='k1-run2'),'13','H28 the completed run keeps its row count');
select is((select value->'error_report'->'importedRows' from h28_seen where name='k1-run2'),
  (select value from h28_seen where name='want-cand'),'H28 importedRows names exactly the preview candidates');
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k1-run2'),
  (select value from h28_seen where name='want-cand'),'H28 the immutable preview candidates survive completion');
select is((select pg_temp.h28_items(value->'error_report'->'rows') from h28_seen where name='k1-run2'),
  (select value from h28_seen where name='want-items'),'H28 the final report keeps one item per duplicate and invalid reason');
select ok(coalesce((select value->'error_report'->>'failure' is null from h28_seen where name='k1-run2'),false),
  'H28 a completed report carries no failure');
select is((select value->>'candidate_payload_sha256' from h28_seen where name='k1-run2'),
  (select value->>'candidate_payload_sha256' from h28_seen where name='k1-run'),
  'H28 the stored candidate digest never changes');
select ok(coalesce(((select value->>'row_count' from h28_seen where name='k1-run2')::int
  = (select value->>'imported_count' from h28_seen where name='k1-run2')::int
  + (select value->>'duplicate_count' from h28_seen where name='k1-run2')::int
  + (select value->'error_report'->'summary'->>'invalid' from h28_seen where name='k1-run2')::int),false),
  'H28 the completed counters satisfy the frozen reconciliation equation');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
  and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014'])),
  6::bigint,'H28 the commit created exactly the six promised members');
select is((select jsonb_build_array(m.branch_id::text,m.status::text,m.joined_on::text,to_jsonb(m.member_code),
    to_jsonb(m.user_id),to_jsonb(m.motivation_push_enabled),to_jsonb(m.weekly_goal_visits),m.rest_days::text,to_jsonb(m.photo_url))
  from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919876543210'),
  jsonb_build_array(pg_temp.h28_id(2,1)::text,'active','2020-01-02',to_jsonb(null::text),to_jsonb(null::uuid),
    to_jsonb(true),to_jsonb(null::smallint),'{}',to_jsonb(null::text)),
  'H28 an imported row carries only whitelisted profile facts and defaults');
select is((select m.joined_on::text from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919286000012'),
  (select eff1 from h28_eff),'H28 a blank joined_on used the frozen effective day');
select is((select m.member_code from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919283000014'),
  'H28LOWER','H28 member-code comparison stayed exact and case-sensitive');
select ok(coalesce((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919281000010')=1
  and (select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,2) and m.phone='+919281000010')=1,false),
  'H28 a cross-gym phone stays unseen: this gym''s member was created and the other gym''s untouched');
select ok(coalesce((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919281000001')=1
  and (select m.full_name from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919281000001')='H28 Member One',false),
  'H28 the import overwrote no existing member');
select is((select count(*) from public.memberships ms where ms.tenant_id=pg_temp.h28_id(1,1)
  and ms.member_id in (select m.id from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
    and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014']))),
  0::bigint,'H28 the import created no membership');
select is((select count(*) from public.payments p where p.tenant_id=pg_temp.h28_id(1,1)
  and p.member_id in (select m.id from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
    and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014']))),
  0::bigint,'H28 the import created no payment');
select is((select count(*) from public.attendance a where a.tenant_id=pg_temp.h28_id(1,1)
  and a.member_id in (select m.id from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
    and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014']))),
  0::bigint,'H28 the import created no attendance');
select is((select count(*) from public.consents c where c.tenant_id=pg_temp.h28_id(1,1)
  and c.member_id in (select m.id from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
    and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014']))),
  0::bigint,'H28 the import recorded no consent');
select is((select count(*) from auth.users),(select n from h28_counts where name='auth-users'),
  'H28 the import created no auth user');
select ok(coalesce((select count(*) from public.audit_log a
  where (a.record_id = pg_temp.h28_rid(1) or a.record_id in (select m.id from public.members m
      where m.tenant_id=pg_temp.h28_id(1,1)
      and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014'])))
  and a.tenant_id is distinct from pg_temp.h28_id(1,1))=0,false),
  'H28 any audit evidence the import wrote stays inside the fixture tenant');

-- ------------------------ L. terminal replay of a completed run (D12) --
select pg_temp.h28_claim();
set local role authenticated;
insert into h28_seen values ('r1-replay-probe', pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null));
select is((select value->>'state' from h28_seen where name='r1-replay-probe'),'00000','H28 a completed run answers the probe');
select is((select value->'value'->>'replayed' from h28_seen where name='r1-replay-probe'),'true','H28 the completed probe is a replay');
select is((select value->'value'->>'status' from h28_seen where name='r1-replay-probe'),'completed','H28 the replay returns the stored terminal status');
select is((select value->'value'->'counts'->>'imported' from h28_seen where name='r1-replay-probe'),'6',
  'H28 the replay returns the stored counters');
insert into h28_seen values ('r1-replay-rows', pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), (select value from h28_seen where name='r1-cand')));
select is((select value->>'state' from h28_seen where name='r1-replay-rows'),'00000','H28 a second full commit of a completed run is accepted as replay');
select is((select value->'value'->>'replayed' from h28_seen where name='r1-replay-rows'),'true','H28 the second full commit is labelled a replay');
set local role postgres;
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
  and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014'])),
  6::bigint,'H28 the replay created no member and changed no report');
select pg_temp.h28_claim();
set local role authenticated;
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('c3',32), null)->>'state','GL064',
  'H28 the raw-file digest is checked before terminal replay');
select pg_temp.h28_claim('gym_manager',1,2);
select is(pg_temp.h28_commit(pg_temp.h28_rid(1), repeat('a1',32), null)->>'state','42501',
  'H28 the uploader comparison precedes terminal replay');
select pg_temp.h28_claim();

-- ------- M. a candidate that became a duplicate is skipped (CSV-D10) ----
select pg_temp.h28_claim('gym_manager',1,2);
insert into h28_seen values ('k2-prepare', pg_temp.h28_prepare(1,2,pg_temp.h28_id(8,2),'h28-r2.csv',repeat('b2',32),
  'h28-parser-v1',1,'E164','{"full_name":0,"phone":1}'::jsonb,3,
  (select jsonb_agg(jsonb_build_object('rowNumber',f.n,'full_name',f.full_name,'phone',f.phone,
    'member_code',f.member_code,'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
    'joined_on',f.joined_on,'notes',f.notes) order by f.n) from h28_f2 f),'[]'::jsonb));
select is((select value->>'state' from h28_seen where name='k2-prepare'),'00000','H28 a manager may prepare an import');
insert into h28_seen values ('k2-run', pg_temp.h28_run(2));
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k2-run'),'[2,3]'::jsonb,
  'H28 the manager''s preview promised two candidates');
select is((select value->>'duplicate_count' from h28_seen where name='k2-run'),'1','H28 the preview classified one existing-phone duplicate');
select is((select value->>'row_count' from h28_seen where name='k2-run'),'3','H28 the run counts its three source rows');
set local role postgres;
select is((pg_temp.h28_exec(format('insert into public.members (id,tenant_id,branch_id,full_name,phone,status,joined_on) values (%L::uuid,%L::uuid,%L::uuid,''H28 Racer X'',''+919289000021'',''active'',%L)',
  pg_temp.h28_id(5,21),pg_temp.h28_id(1,1),pg_temp.h28_id(2,1),(select eff1 from h28_eff))))->>'state','00000',
  'H28 fixture: a same-gym member takes a candidate phone after preview');
select is((pg_temp.h28_exec(format('update public.members set phone=''+919289000029'' where id = %L::uuid',
  pg_temp.h28_id(5,2))))->>'state','00000',
  'H28 fixture: the existing duplicate member edits its phone after preview');
select pg_temp.h28_claim('gym_manager',1,2);
set local role authenticated;
insert into h28_seen values ('k2-commit', pg_temp.h28_commit(pg_temp.h28_rid(2), repeat('b2',32),
  (select jsonb_agg(jsonb_build_object('rowNumber',f.n,'full_name',f.full_name,'phone',f.phone,
    'member_code',f.member_code,'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
    'joined_on',coalesce(f.joined_on,(select eff1 from h28_eff)),'notes',f.notes) order by f.n)
   from h28_f2 f where f.n in (2,3))));
select is((select value->>'state' from h28_seen where name='k2-commit'),'00000','H28 the manager commits the rechecked candidates');
select is((select value->'value'->>'status' from h28_seen where name='k2-commit'),'completed','H28 the rechecked commit completes');
select is((select value->'value'->'counts'->>'imported' from h28_seen where name='k2-commit'),'1',
  'H28 a candidate that became a duplicate was skipped, so a subset was imported');
select is((select value->'value'->'counts'->>'duplicates' from h28_seen where name='k2-commit'),'2',
  'H28 the reclassified row is counted once as a duplicate');
set local role postgres;
insert into h28_seen values ('k2-run2', pg_temp.h28_run(2));
select ok(coalesce(((select value->>'row_count' from h28_seen where name='k2-run2')::int
  = (select value->>'imported_count' from h28_seen where name='k2-run2')::int
  + (select value->>'duplicate_count' from h28_seen where name='k2-run2')::int
  + (select value->'error_report'->'summary'->>'invalid' from h28_seen where name='k2-run2')::int),false),
  'H28 the subset outcome still satisfies the counter equation');
select is((select value->'error_report'->'importedRows' from h28_seen where name='k2-run2'),'[3]'::jsonb,
  'H28 only the surviving candidate was imported');
select is((select pg_temp.h28_items(value->'error_report'->'rows') from h28_seen where name='k2-run2'),
  '[[2,"duplicate","existing_phone"],[4,"duplicate","existing_phone"]]'::jsonb,
  'H28 the reclassified candidate and the still-skipped preview duplicate are both reported');
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k2-run2'),'[2,3]'::jsonb,
  'H28 the immutable preview candidates survive reclassification');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919289000021'),1::bigint,
  'H28 the pre-existing phone owner was not duplicated');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919289000022'),1::bigint,
  'H28 the surviving candidate became a member');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919281000002'),0::bigint,
  'H28 a preview duplicate stays skipped even after the conflicting member edited its phone');
select is((select value->>'candidate_payload_sha256' from h28_seen where name='k2-run2'),
  (select value->>'candidate_payload_sha256' from h28_seen where name='k2-run'),
  'H28 a changed final disposition never changed the stored payload digest');

-- ------------------ N. processing failure rolls back (CSV-D11/D12) -----
select pg_temp.h28_claim();
set local role authenticated;
insert into h28_seen values ('k3-prepare', pg_temp.h28_prepare(1,3,pg_temp.h28_id(8,3),'h28-r3.csv',repeat('d4',32),
  'h28-parser-v1',1,'IN','{"full_name":0,"phone":1}'::jsonb,2,
  (select jsonb_agg(jsonb_build_object('rowNumber',f.n,'full_name',f.full_name,'phone',f.phone,
    'member_code',f.member_code,'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
    'joined_on',f.joined_on,'notes',f.notes) order by f.n) from h28_f3 f),'[]'::jsonb));
select is((select value->>'state' from h28_seen where name='k3-prepare'),'00000','H28 the failure-scenario prepare wins');
insert into h28_seen values ('k3-run', pg_temp.h28_run(3));
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k3-run'),'[2,3]'::jsonb,
  'H28 the failure scenario promised two candidates');
insert into h28_seen values ('k3-commit', pg_temp.h28_commit(pg_temp.h28_rid(3), repeat('d4',32),
  (select jsonb_agg(jsonb_build_object('rowNumber',f.n,'full_name',f.full_name,'phone',f.phone,
    'member_code',f.member_code,'email',f.email,'gender',f.gender,'date_of_birth',f.date_of_birth,
    'joined_on',coalesce(f.joined_on,(select eff1 from h28_eff)),'notes',f.notes) order by f.n)
   from h28_f3 f where f.n in (2,3))));
select is((select value->>'state' from h28_seen where name='k3-commit'),'00000','H28 the failed outcome is returned in a success-shaped result');
select is((select value->'value'->>'status' from h28_seen where name='k3-commit'),'failed','H28 the result reports failed');
select is((select value->'value'->>'replayed' from h28_seen where name='k3-commit'),'false','H28 the first recorded failure is not a replay');
select is((select value->'value'->'failure'->>'code' from h28_seen where name='k3-commit'),'processing_failed',
  'H28 the result carries only the actionable failure code');
set local role postgres;
insert into h28_seen values ('k3-run2', pg_temp.h28_run(3));
select is((select value->>'status' from h28_seen where name='k3-run2'),'failed','H28 the run is recorded failed');
select is((select value->>'imported_count' from h28_seen where name='k3-run2'),'0','H28 a failed run imported nothing');
select is((select value->>'row_count' from h28_seen where name='k3-run2'),'2','H28 a failed run keeps its row count');
select is((select value->>'duplicate_count' from h28_seen where name='k3-run2'),'0','H28 a failed run keeps its preview duplicate count');
select is((select value->'error_report'->'failure'->>'code' from h28_seen where name='k3-run2'),'processing_failed',
  'H28 the stored report carries the code-only failure');
select ok(not pg_temp.h28_mentions((select value->'error_report' from h28_seen where name='k3-run2'),'not-a-phone')
  and not pg_temp.h28_mentions((select value->'error_report' from h28_seen where name='k3-run2'),'H28 Fail Fay'),
  'H28 the failed report stores no source value and no caught exception');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='not-a-phone'),0::bigint,
  'H28 the rollback removed every member the run had inserted');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1) and m.phone='+919289000033'),0::bigint,
  'H28 the rollback removed the earlier candidate too');
select is((select value->'error_report'->'importedRows' from h28_seen where name='k3-run2'),'[]'::jsonb,
  'H28 a failed report has imported no rows');
select is((select pg_temp.h28_items(value->'error_report'->'rows') from h28_seen where name='k3-run2'),'[]'::jsonb,
  'H28 a failed report keeps its empty preview items');
select pg_temp.h28_claim();
set local role authenticated;
insert into h28_seen values ('k3-replay', pg_temp.h28_commit(pg_temp.h28_rid(3), repeat('d4',32), null));
select is((select value->>'state' from h28_seen where name='k3-replay'),'00000','H28 a failed run answers the probe');
select is((select value->'value'->>'replayed' from h28_seen where name='k3-replay'),'true','H28 the failed replay is labelled');
select is((select value->'value'->>'status' from h28_seen where name='k3-replay'),'failed','H28 failed is terminal: the stored failure is replayed');
select is(pg_temp.h28_commit(pg_temp.h28_rid(3), repeat('c3',32), null)->>'state','GL064',
  'H28 the raw-file digest is checked before the failed replay too');

-- ---------- O. retrying the same file under a new key (CSV-D12/D07) -----
select is(pg_temp.h28_prepare_f1(4, pg_temp.h28_id(8,4), 'h28-members.csv', repeat('a1',32),
  'h28-parser-v1', 1, 'IN',
  '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, null)->>'state',
  '00000','H28 the same file previews again under a fresh key');
insert into h28_seen values ('k4-run', pg_temp.h28_run(4));
select is((select value->'error_report'->'previewCandidateRows' from h28_seen where name='k4-run'),'[]'::jsonb,
  'H28 every previously imported phone is now a same-gym duplicate, so nothing would import');
select is((select value->>'duplicate_count' from h28_seen where name='k4-run'),'10','H28 the retry classified ten duplicate rows');
select is((select value->>'row_count' from h28_seen where name='k4-run'),'13','H28 the retry still counts every source row');
select is((select value->>'imported_count' from h28_seen where name='k4-run'),'0','H28 the pending retry has imported nothing');
set local role postgres;
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h28_id(1,1)
  and m.phone = any(array['+919876543210','+919828000003','+919285000005','+919286000012','+919281000010','+919283000014'])),
  6::bigint,'H28 the retry preview created zero copies');

-- -------------------- P. legacy rows stay historical (CSV-D16) ---------
select pg_temp.h28_claim();
set local role authenticated;
insert into h28_seen values ('legacy-done', pg_temp.h28_commit(pg_temp.h28_id(7,901), repeat('a1',32), null));
select ok(coalesce((select value->>'state' from h28_seen where name='legacy-done') <> '00000'
  and not pg_temp.h28_missing((select value->>'state' from h28_seen where name='legacy-done')),false),
  'H28 a completed legacy row cannot be committed');
select is((select to_jsonb(mi)->>'status' from public.member_imports mi where mi.id=pg_temp.h28_id(7,901)),'completed',
  'H28 the refused legacy commit changed nothing');
insert into h28_seen values ('legacy-pending', pg_temp.h28_commit(pg_temp.h28_id(7,902), repeat('a1',32), null));
select ok(coalesce((select value->>'state' from h28_seen where name='legacy-pending') <> '00000'
  and not pg_temp.h28_missing((select value->>'state' from h28_seen where name='legacy-pending')),false),
  'H28 a pending legacy row cannot be committed');
select is((select to_jsonb(mi)->>'status' from public.member_imports mi where mi.id=pg_temp.h28_id(7,902)),'pending',
  'H28 the legacy pending row is unchanged');
select ok(pg_temp.h28_attempt(format('update public.member_imports set request_key = %L::uuid, file_sha256 = %L where id = %L::uuid',
  pg_temp.h28_id(8,902), repeat('99',32), pg_temp.h28_id(7,902))) like 'error=%',
  'H28 a caller cannot convert a legacy row into a v1 run by hand');
select ok(coalesce((select to_jsonb(mi)->'request_key' is null from public.member_imports mi where mi.id=pg_temp.h28_id(7,902)),false),
  'H28 the refused legacy upgrade stored no v1 evidence');

-- -------------- Q. the invoker run-mutation invariant (CSV-D16) --------
select ok(pg_temp.h28_attempt(format(
  'insert into public.member_imports (id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values (%L::uuid,%L::uuid,%L::uuid,%L,%L::jsonb,''pending'',1,0,0,%L::jsonb,%L::uuid,%L::uuid,%L,%L,%L,(%L)::date,%L::uuid,%L)',
  pg_temp.h28_id(7,910),pg_temp.h28_id(1,1),pg_temp.h28_id(3,1),'h28-forged.csv','{"full_name":0,"phone":1}',
  '{"version":1,"summary":{"invalid":0,"duplicate":0},"previewCandidateRows":[2],"importedRows":[],"rows":[],"failure":null}',
  pg_temp.h28_id(2,1),pg_temp.h28_id(8,910),repeat('77',32),'h28-parser-v1','IN',
  (select eff1 from h28_eff),pg_temp.h28_id(9,1),repeat('88',32))) like 'error=%',
  'H28 a caller cannot insert a complete v1 run directly');
select is((select count(*) from public.member_imports where file_name='h28-forged.csv'),0::bigint,
  'H28 the refused direct insert left no run');
select ok(pg_temp.h28_attempt(format(
  'insert into public.member_imports (id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values (%L::uuid,%L::uuid,%L::uuid,%L,%L::jsonb,''pending'',1,0,0,%L::jsonb,%L::uuid,%L::uuid,%L,%L,%L,(%L)::date,%L::uuid,%L)',
  pg_temp.h28_id(7,911),pg_temp.h28_id(1,1),pg_temp.h28_id(3,2),'h28-forged2.csv','{"full_name":0,"phone":1}',
  '{"version":1,"summary":{"invalid":0,"duplicate":0},"previewCandidateRows":[2],"importedRows":[],"rows":[],"failure":null}',
  pg_temp.h28_id(2,1),pg_temp.h28_id(8,911),repeat('77',32),'h28-parser-v1','IN',
  (select eff1 from h28_eff),pg_temp.h28_id(9,2),repeat('88',32))) like 'error=%',
  'H28 forged uploader evidence does not authorize a direct insert');
select is((select count(*) from public.member_imports where file_name='h28-forged2.csv'),0::bigint,
  'H28 the forged-evidence insert left no run');
select ok(pg_temp.h28_attempt(format(
  'insert into public.member_imports (id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status) values (%L::uuid,%L::uuid,%L::uuid,%L,%L::jsonb,''pending'')',
  pg_temp.h28_id(7,912),pg_temp.h28_id(1,1),pg_temp.h28_id(3,1),'h28-forged3.csv','{"full_name":0,"phone":1}')) like 'error=%',
  'H28 a caller cannot insert a legacy-shaped run either');
select is((select count(*) from public.member_imports where file_name='h28-forged3.csv'),0::bigint,
  'H28 the refused legacy-shaped insert left no run');
select pg_temp.h28_claim('super_admin',null,null,null,7);
select ok(pg_temp.h28_attempt(format(
  'insert into public.member_imports (id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values (%L::uuid,%L::uuid,%L::uuid,%L,%L::jsonb,''pending'',1,0,0,%L::jsonb,%L::uuid,%L::uuid,%L,%L,%L,(%L)::date,%L::uuid,%L)',
  pg_temp.h28_id(7,913),pg_temp.h28_id(1,1),pg_temp.h28_id(3,1),'h28-forged4.csv','{"full_name":0,"phone":1}',
  '{"version":1,"summary":{"invalid":0,"duplicate":0},"previewCandidateRows":[2],"importedRows":[],"rows":[],"failure":null}',
  pg_temp.h28_id(2,1),pg_temp.h28_id(8,913),repeat('77',32),'h28-parser-v1','IN',
  (select eff1 from h28_eff),pg_temp.h28_id(9,1),repeat('88',32))) like 'error=%',
  'H28 a platform claim cannot authorize a direct v1 insert through a GUC');
select is((select count(*) from public.member_imports where file_name='h28-forged4.csv'),0::bigint,
  'H28 the platform-claim insert left no run');
select pg_temp.h28_claim();
select ok(pg_temp.h28_attempt(format('update public.member_imports set status=''completed'', imported_count=1 where id = %L::uuid',
  pg_temp.h28_rid(6))) like 'error=%','H28 a caller cannot manufacture completion');
select ok(pg_temp.h28_attempt(format('update public.member_imports set status=''processing'' where id = %L::uuid',
  pg_temp.h28_rid(6))) like 'error=%','H28 a caller cannot simulate the legal transition sequence');
select ok(pg_temp.h28_attempt(format('update public.member_imports set parser_contract=null where id = %L::uuid',
  pg_temp.h28_rid(6))) like 'error=%','H28 clearing v1 evidence cannot open a legacy escape hatch');
select ok(pg_temp.h28_attempt(format('update public.member_imports set file_name=''h28-rewritten.csv'' where id = %L::uuid',
  pg_temp.h28_rid(6))) like 'error=%','H28 the stored filename is frozen');
select ok(pg_temp.h28_attempt(format('update public.member_imports set request_key = %L::uuid where id = %L::uuid',
  pg_temp.h28_id(8,961),pg_temp.h28_rid(6))) like 'error=%','H28 the request key is frozen');
select ok(pg_temp.h28_attempt(format('update public.member_imports set effective_on = ''2020-01-01'' where id = %L::uuid',
  pg_temp.h28_rid(6))) like 'error=%','H28 the effective day is frozen');
select ok(coalesce(pg_temp.h28_run(6)->>'status' = 'pending'
  and pg_temp.h28_run(6)->>'file_name' = 'h28-b2.csv'
  and pg_temp.h28_run(6)->>'parser_contract' = 'h28-parser-v1',false),
  'H28 every refused direct write left the run unchanged');
select pg_temp.h28_claim('gym_owner',1,null,null,7,1);
insert into h28_seen values ('preview-write', pg_temp.h28_exec(format(
  'update public.member_imports set file_name = ''h28-preview.csv'' where id = %L::uuid', pg_temp.h28_rid(6))));
select is((select value->>'state' from h28_seen where name='preview-write'),'42501',
  'H28 a preview session cannot write an import run');
select is((select value->>'message' from h28_seen where name='preview-write'),'Support preview is read-only.',
  'H28 the preview refusal is the system-wide read-only invariant');
select ok(coalesce(pg_temp.h28_run(6)->>'file_name' = 'h28-b2.csv',false),
  'H28 the refused preview write changed nothing');
select pg_temp.h28_claim();

-- ---------------------- R. a processing run is not committable -------
set local role postgres;
select is(pg_temp.h28_attempt(format('update public.member_imports set status=''processing'' where id = %L::uuid',
  pg_temp.h28_rid(6))),'rows=1','H28 the trusted postgres path can stage the processing state');
select pg_temp.h28_claim();
set local role authenticated;
select is(pg_temp.h28_commit(pg_temp.h28_rid(6), repeat('66',32), null)->>'state','55000',
  'H28 a processing run is neither pending nor a replayable terminal result');
select is(pg_temp.h28_run(6)->>'status','processing','H28 the refused commit left the run processing');
select is(pg_temp.h28_commit(pg_temp.h28_rid(6), repeat('c3',32), null)->>'state','GL064',
  'H28 the raw-file digest is checked before the state verdict');

select * from finish();
rollback;
