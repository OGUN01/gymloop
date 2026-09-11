-- 28_member_import_structure.sql — Phase 6 member import, visible suite 1 of 3:
-- the frozen v1 schema shape on member_imports, the two command signatures and
-- grants, caller reads, and the v1 run invariant on direct writes.
--
-- Derived only from the frozen CSV-001..CSV-006 contract detail in
-- docs/planning/phase6-import-contract.md (the sections "Schema, generated
-- types and test split" and "Detailed EARS contract" CSV-D16, plus the stable
-- error-code table's exact DB refusals), and from the pre-existing
-- member_imports catalogue facts already applied on Cloud and recorded in
-- docs/data-model.md (the Phase 1 platform migration: import_status enum,
-- member_imports_tenant_all / member_imports_platform_all policies, the
-- normal-tier select,insert,update grant). The Phase 6 import implementation
-- and supabase/tests-holdout/ were not read; no Phase 6 import migration
-- exists yet, so this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * The contract freezes both commands as "narrowly guarded, postgres-owned
--   security definer commands with a fixed safe search path" — definer, not
--   invoker, is pinned, with the leads suites' empty-search_path house pattern
--   and a postgres ownership pin.
-- * "lowercase SHA-256/country checks" are CHECK constraints, so their
--   violations are pinned as SQLSTATE 23514; the same-tenant composite branch
--   foreign key is pinned as 23503. The 5,000-row and byte caps are handler
--   limits owned by unit tests, not database behavior, and are not restated
--   here except where the contract names a database SQLSTATE.
-- * No assertion pins a mechanism (trigger vs policy vs constraint) for the
--   v1 run invariant: it is pinned purely as refusals of direct authenticated
--   v1 inserts/updates — including legacy downgrade and legacy completion —
--   and the survival of the trusted postgres path ("The postgres
--   administrative path is trusted").
-- * The contract says "Preserve existing owner/manager and platform read
--   policies", so caller reads are pinned for an owner session, a cross-gym
--   session and the platform roles against the existing policies; the
--   endpoint-level trainer/front-desk/member/impersonation exclusions are
--   command-level and live in 29_member_import_prepare.sql.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenants.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(58);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 60000000 is this file's alone; no other suite or the seed
-- uses it.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('60000000-0000-4000-8000-000000000001','Import Struct A','MIS60A','active','Asia/Kolkata','INR'),
 ('60000000-0000-4000-8000-000000000002','Import Struct B','MIS60B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000001','Main A',true),
 ('60000000-0000-4000-8000-000000000012','60000000-0000-4000-8000-000000000002','Main B',true),
 ('60000000-0000-4000-8000-000000000013','60000000-0000-4000-8000-000000000001','Second A',false);
insert into auth.users(id) values
 ('60000000-0000-4000-8000-000000000901'),('60000000-0000-4000-8000-000000000902'),
 ('60000000-0000-4000-8000-000000000907'),('60000000-0000-4000-8000-000000000909'),
 ('60000000-0000-4000-8000-00000000090a');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('60000000-0000-4000-8000-000000000909','platform_support','Support Probe','support@example.test',true),
 ('60000000-0000-4000-8000-00000000090a','super_admin','Super Probe','super@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('60000000-0000-4000-8000-000000000021','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000901','60000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('60000000-0000-4000-8000-000000000022','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000902','60000000-0000-4000-8000-000000000011','gym_manager','Manager A',true),
 ('60000000-0000-4000-8000-000000000027','60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000907','60000000-0000-4000-8000-000000000012','gym_owner','Owner B',true);

-- ---------------------------------------------------------------------------
-- Section 1 — the eight v1 columns the migration adds, with their frozen
-- types. Nullability is YES for all eight: "Nullability accommodates only
-- rows already present before this migration; there is no backfill."
-- ---------------------------------------------------------------------------

select has_column('public','member_imports','branch_id','member_imports stores the selected import branch');
select has_column('public','member_imports','request_key','member_imports stores the preview request key');
select has_column('public','member_imports','file_sha256','member_imports stores the raw file digest');
select has_column('public','member_imports','parser_contract','member_imports stores the parser contract version');
select has_column('public','member_imports','phone_default_country','member_imports stores the typed phone-country mode');
select has_column('public','member_imports','effective_on','member_imports stores the frozen gym-local effective day');
select has_column('public','member_imports','uploaded_by_user_id','member_imports stores the verified JWT uploader user');
select has_column('public','member_imports','candidate_payload_sha256','member_imports stores the canonical candidate digest');
select results_eq($$select column_name::text collate "default",data_type::text collate "default",is_nullable::text collate "default" from information_schema.columns where table_schema='public' and table_name='member_imports' and column_name in ('branch_id','request_key','file_sha256','parser_contract','phone_default_country','effective_on','uploaded_by_user_id','candidate_payload_sha256') order by column_name$$,
$$values
 ('branch_id'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default"),
 ('candidate_payload_sha256'::text collate "default",'text'::text collate "default",'YES'::text collate "default"),
 ('effective_on'::text collate "default",'date'::text collate "default",'YES'::text collate "default"),
 ('file_sha256'::text collate "default",'text'::text collate "default",'YES'::text collate "default"),
 ('parser_contract'::text collate "default",'text'::text collate "default",'YES'::text collate "default"),
 ('phone_default_country'::text collate "default",'text'::text collate "default",'YES'::text collate "default"),
 ('request_key'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default"),
 ('uploaded_by_user_id'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default")$$,
'every added v1 column is nullable history accommodation with its frozen type');

-- ---------------------------------------------------------------------------
-- Section 2 — the same-tenant composite branch foreign key, the branch index
-- and the partial request-key uniqueness.
-- ---------------------------------------------------------------------------

select ok(exists(
 select 1 from pg_constraint c
  where c.conrelid='public.member_imports'::regclass and c.contype='f' and c.confrelid='public.branches'::regclass
    and (select array_agg(a.attname::text order by ck.ord) from unnest(c.conkey) with ordinality as ck(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=ck.attnum)=array['tenant_id','branch_id']
    and (select array_agg(a.attname::text order by ck.ord) from unnest(c.confkey) with ordinality as ck(attnum,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=ck.attnum)=array['tenant_id','id']
),'the branch foreign key is same-tenant composite on (tenant_id, branch_id)');
select ok(exists(select 1 from pg_index i join pg_class t on t.oid=i.indrelid where t.relname='member_imports' and pg_get_indexdef(i.indexrelid) like '%branch_id%'),'the added branch foreign key is indexed');
select ok(exists(select 1 from pg_index i join pg_class c on c.oid=i.indexrelid join pg_class t on t.oid=i.indrelid where t.relname='member_imports' and i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, request_key)%' and pg_get_expr(i.indpred,i.indrelid)='(request_key IS NOT NULL)'),'request-key uniqueness is tenant-scoped and partial over non-null keys');

-- ---------------------------------------------------------------------------
-- Section 3 — the lowercase SHA-256 and country checks, as behavior. These run
-- as the trusted postgres path, which the contract leaves to the checks
-- themselves: CHECK constraints fire for every writer.
-- ---------------------------------------------------------------------------

-- Harness repair (ADR-060 orchestrator pattern): each fixture below now
-- carries the complete v1 evidence the invariant trigger added in
-- 20260915100006 requires before a row reaches its column CHECK
-- constraints at all (a BEFORE trigger runs ahead of every CHECK) -- an
-- otherwise-minimal row hit the trigger's own completeness gate first and
-- never exercised the specific CHECK each assertion names. The shared
-- report below is a valid two-row pending partition (one duplicate row,
-- one preview candidate) so only the one column each throws_ok names is
-- wrong.
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000b01','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000b21',repeat('A',64),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'23514',null,'an uppercase file_sha256 is refused by the lowercase digest check');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000b02','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000b22','abc','import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'23514',null,'a non-hex file_sha256 is refused by the digest check');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000b03','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000b23',repeat('ab',32),'import-parser-v1','us',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'23514',null,'a lowercase phone_default_country outside the two modes is refused');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000b04','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000b24',repeat('ab',32),'import-parser-v1','US',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'23514',null,'an unsupported uppercase phone_default_country is refused');
select lives_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000a01','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000a21',repeat('ab',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'the trusted path records a complete pending v1 run with a lowercase IN-mode digest');
select lives_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000a02','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000a22',repeat('ab',32),'import-parser-v1','E164',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'the E164 phone-country mode is accepted alongside IN');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values ('60000000-0000-4000-8000-000000000b05','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','members.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,1,'{"version":1,"summary":{"invalid":0,"duplicate":1},"previewCandidateRows":[2],"importedRows":[],"rows":[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"}],"failure":null}'::jsonb,'60000000-0000-4000-8000-000000000012','60000000-0000-4000-8000-000000000b25',repeat('ab',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32))$$,'23503',null,'the composite branch foreign key refuses another gym''s branch');

-- ---------------------------------------------------------------------------
-- Section 4 — the two commands, frozen before database authors start: exact
-- signatures, postgres ownership, security definer, fixed empty search path,
-- and authenticated-only execution (PUBLIC, anon and service_role hold
-- nothing; "Neither route uses a service role client").
-- ---------------------------------------------------------------------------

select ok((select prosecdef and provolatile='v'::"char" and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=10::smallint and proowner=(select oid from pg_roles where rolname='postgres') from pg_proc where oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),'prepare_member_import is the exact postgres-owned security-definer command with a pinned empty search path');
select is((select proargnames from pg_proc where oid=to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)')),ARRAY['p_request_key','p_file_name','p_file_sha256','p_parser_contract','p_branch_id','p_phone_default_country','p_column_mapping','p_row_count','p_rows','p_preclassified_report']::text[],'prepare_member_import derives both uploader identities and accepts no caller-chosen uploader argument');
select ok((select prosecdef and provolatile='v'::"char" and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=3::smallint and proowner=(select oid from pg_roles where rolname='postgres') from pg_proc where oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),'commit_member_import is the exact postgres-owned security-definer command with a pinned empty search path');
select is((select proargnames from pg_proc where oid=to_regprocedure('public.commit_member_import(uuid,text,jsonb)')),ARRAY['p_import_id','p_file_sha256','p_rows']::text[],'commit_member_import takes only the run, the raw file digest and the candidate rows');
select ok((select count(*)=2::bigint and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('public',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p where p.oid in (to_regprocedure('public.prepare_member_import(uuid,text,text,text,uuid,text,jsonb,integer,jsonb,jsonb)'),to_regprocedure('public.commit_member_import(uuid,text,jsonb)'))),'both import commands exist and execute only for authenticated application callers');

-- ---------------------------------------------------------------------------
-- Section 5 — caller reads through RLS, against the existing policies the
-- contract preserves. Ordinary report/run reads continue through the caller's
-- RLS client; the platform roles keep the cross-gym view.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000001","staff_id":"60000000-0000-4000-8000-000000000021"}',true);
select results_eq($$select count(*) from public.member_imports where tenant_id='60000000-0000-4000-8000-000000000001'$$,$$select 2::bigint$$,'an owner session reads the import runs of their own gym through RLS');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000002","staff_id":"60000000-0000-4000-8000-000000000027"}',true);
select results_eq($$select (select count(*) from public.member_imports where tenant_id='60000000-0000-4000-8000-000000000001'),(select count(*) from public.member_imports where tenant_id='60000000-0000-4000-8000-000000000002')$$,$$select 0::bigint,0::bigint$$,'a cross-gym session reads no import run of either gym through RLS');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*) from public.member_imports where tenant_id='60000000-0000-4000-8000-000000000001'$$,$$select 2::bigint$$,'outside RLS both fixture runs are visible to the probe');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"platform_support"}',true);
select results_eq($$select count(*) from public.member_imports where tenant_id in ('60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002')$$,$$select 2::bigint$$,'platform support keeps its cross-gym read view of import runs');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"super_admin"}',true);
select results_eq($$select count(*) from public.member_imports where tenant_id in ('60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002')$$,$$select 2::bigint$$,'the super admin keeps the platform read view of import runs');
-- Harness repair (ADR-060 orchestrator pattern): the two-policy `_all`
-- template this assertion named was Phase 1's; Phase 2 replaced it
-- everywhere with the five-name convention 04_contract_meta.sql's own
-- header records ("`_all` ceases to exist anywhere"). member_imports
-- carries the same four survivors every other table does.
select ok(exists(select 1 from pg_policies where schemaname='public' and tablename='member_imports' and policyname='member_imports_tenant_select')
      and exists(select 1 from pg_policies where schemaname='public' and tablename='member_imports' and policyname='member_imports_tenant_write')
      and exists(select 1 from pg_policies where schemaname='public' and tablename='member_imports' and policyname='member_imports_platform_select')
      and exists(select 1 from pg_policies where schemaname='public' and tablename='member_imports' and policyname='member_imports_platform_write'),'the existing tenant and platform policies survive the migration');

-- ---------------------------------------------------------------------------
-- Section 6 — the v1 run invariant: only the command path creates or moves a
-- v1 run, frozen evidence cannot be edited or cleared, legacy rows can be
-- neither completed nor converted, and the postgres path stays trusted.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);
select lives_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status) values ('60000000-0000-4000-8000-000000000a11','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','legacy.csv','{}'::jsonb,'pending')$$,'the trusted postgres path may still record a historical legacy run with null v1 evidence');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000001","staff_id":"60000000-0000-4000-8000-000000000021"}',true);

select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256,row_count,imported_count,duplicate_count,error_report) values ('60000000-0000-4000-8000-000000000c01','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','forged.csv','{"full_name":0,"phone":1}'::jsonb,'60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000c21',repeat('ab',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32),1,0,0,'{"version":1}'::jsonb)$$,null,'a direct authenticated INSERT cannot manufacture a pending v1 run');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping) values ('60000000-0000-4000-8000-000000000c02','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','blank.csv','{}'::jsonb)$$,null,'a direct authenticated INSERT cannot record a new legacy-shaped run');
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256,row_count,imported_count,duplicate_count,error_report) values ('60000000-0000-4000-8000-000000000c03','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','forged.csv','{"full_name":0,"phone":1}'::jsonb,'completed','60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000c23',repeat('ab',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32),1,1,0,'{"version":1}'::jsonb)$$,null,'a direct authenticated INSERT cannot manufacture a completed run');
select throws_ok($$update public.member_imports set status='processing' where id='60000000-0000-4000-8000-000000000a01'$$,null,'a direct authenticated write cannot advance pending to processing');
select throws_ok($$update public.member_imports set status='completed' where id='60000000-0000-4000-8000-000000000a01'$$,null,'a direct authenticated write cannot advance pending to completed');

set local role postgres;
update public.member_imports set status='processing' where id='60000000-0000-4000-8000-000000000a01';
set local role authenticated;
select throws_ok($$update public.member_imports set status='completed' where id='60000000-0000-4000-8000-000000000a01'$$,null,'even the legal-looking processing to completed step is command-path only');
-- Harness repair (ADR-098's explicit-bypass pattern): resetting a01 back to
-- pending for the immutability probes below is fixture setup, not a legal
-- product transition -- processing->pending is not a graph edge even for
-- the trusted postgres path (the structural graph is never exempted, only
-- the actor-identity check is), so this reset enters through the same
-- replica bypass history rows use.
set local role postgres;
set local session_replication_role = replica;
update public.member_imports set status='pending' where id='60000000-0000-4000-8000-000000000a01';
set local session_replication_role = default;
create temp table r1_probe as select * from public.member_imports where id='60000000-0000-4000-8000-000000000a01';
grant select on r1_probe to authenticated;
set local role authenticated;

select throws_ok($$update public.member_imports set request_key=null where id='60000000-0000-4000-8000-000000000a01'$$,null,'clearing the request key cannot turn a v1 run into a legacy escape hatch');
select throws_ok($$update public.member_imports set parser_contract=null where id='60000000-0000-4000-8000-000000000a01'$$,null,'clearing the parser contract cannot downgrade a v1 run');
select throws_ok($$update public.member_imports set file_sha256=repeat('ef',32) where id='60000000-0000-4000-8000-000000000a01'$$,null,'the raw file digest is frozen after insertion');
select throws_ok($$update public.member_imports set effective_on=effective_on+1 where id='60000000-0000-4000-8000-000000000a01'$$,null,'the frozen effective day is immutable');
select throws_ok($$update public.member_imports set column_mapping='{"full_name":9}'::jsonb where id='60000000-0000-4000-8000-000000000a01'$$,null,'the canonical mapping is frozen after insertion');
select throws_ok($$update public.member_imports set row_count=99 where id='60000000-0000-4000-8000-000000000a01'$$,null,'the row counter is frozen after insertion');
select throws_ok($$update public.member_imports set row_count=null where id='60000000-0000-4000-8000-000000000a01'$$,null,'a v1 run cannot carry a null counter');
select throws_ok($$update public.member_imports set candidate_payload_sha256=repeat('ee',32) where id='60000000-0000-4000-8000-000000000a01'$$,null,'the candidate digest is frozen after insertion');
select throws_ok($$update public.member_imports set error_report='{"version":1}'::jsonb where id='60000000-0000-4000-8000-000000000a01'$$,null,'the versioned report cannot be rewritten by a direct write');
select throws_ok($$update public.member_imports set error_report=null where id='60000000-0000-4000-8000-000000000a01'$$,null,'a v1 run cannot carry a null report');
select throws_ok($$update public.member_imports set file_name='other.csv' where id='60000000-0000-4000-8000-000000000a01'$$,null,'the sanitized original filename is frozen after insertion');
select throws_ok($$update public.member_imports set branch_id='60000000-0000-4000-8000-000000000013' where id='60000000-0000-4000-8000-000000000a01'$$,null,'the selected branch is frozen after insertion');
select throws_ok($$update public.member_imports set phone_default_country='E164' where id='60000000-0000-4000-8000-000000000a01'$$,null,'the phone-country mode is frozen after insertion');
select throws_ok($$update public.member_imports set uploaded_by_staff_id='60000000-0000-4000-8000-000000000022' where id='60000000-0000-4000-8000-000000000a01'$$,null,'the uploader staff identity is frozen and never caller chosen');
select throws_ok($$update public.member_imports set uploaded_by_user_id='60000000-0000-4000-8000-000000000902' where id='60000000-0000-4000-8000-000000000a01'$$,null,'the uploader JWT user identity is frozen and never caller chosen');
select throws_ok($$update public.member_imports set status='completed' where id='60000000-0000-4000-8000-000000000a11'$$,null,'a legacy run cannot be completed by a direct authenticated write');
select throws_ok($$update public.member_imports set branch_id='60000000-0000-4000-8000-000000000011',request_key='60000000-0000-4000-8000-000000000c31',file_sha256=repeat('ab',32),parser_contract='import-parser-v1',phone_default_country='IN',effective_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date,uploaded_by_user_id='60000000-0000-4000-8000-000000000901',candidate_payload_sha256=repeat('ef',32) where id='60000000-0000-4000-8000-000000000a11'$$,null,'a legacy row cannot be converted into a committable v1 run by a direct write');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($$insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256,row_count,imported_count,duplicate_count,error_report) values ('60000000-0000-4000-8000-000000000c04','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000021','forged.csv','{"full_name":0,"phone":1}'::jsonb,'pending','60000000-0000-4000-8000-000000000011','60000000-0000-4000-8000-000000000c24',repeat('ab',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'60000000-0000-4000-8000-000000000901',repeat('cd',32),1,0,0,'{"version":1}'::jsonb)$$,null,'a super admin session cannot manufacture a v1 run either: the existing platform read policy does not bypass the v1 run invariant');
select throws_ok($$update public.member_imports set status='completed' where id='60000000-0000-4000-8000-000000000a11'$$,null,'a super admin session cannot complete a legacy run through the existing table policies');
select set_config('request.jwt.claims','{"sub":"60000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"60000000-0000-4000-8000-000000000001","staff_id":"60000000-0000-4000-8000-000000000021"}',true);

select results_eq($$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from public.member_imports where id='60000000-0000-4000-8000-000000000a01'$$,$$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from r1_probe$$,'no direct authenticated write changed any v1 run fact');
select results_eq($$select count(*) from public.member_imports where tenant_id='60000000-0000-4000-8000-000000000001'$$,$$select 3::bigint$$,'only the two fixture v1 runs and the historical legacy run exist for this tenant');

select * from finish();

rollback;
