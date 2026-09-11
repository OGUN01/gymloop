-- 30_member_import_commit.sql — Phase 6 member import, visible suite 3 of 3:
-- commit_member_import state probe, the pinned terminal result, member
-- writes with CSV-D14 defaults, commit-time duplicate recheck, tamper and
-- failure atomicity, replay, retry under a fresh request key, and the
-- boundary around processing, legacy and foreign runs.
--
-- Derived only from the frozen CSV-001..CSV-006 contract detail in
-- docs/planning/phase6-import-contract.md (the sections "Inspect, preview and
-- confirmation", "Confirm and commit", "Commit-time duplicate recheck",
-- "Failure atomicity", "Retry under a fresh request key", "Boundary",
-- "Imported member rows" / CSV-D14, and "Stable file/API error codes"). The
-- Phase 6 import implementation and supabase/tests-holdout/ were not read; no
-- Phase 6 import migration exists yet, so this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * commit's p_rows carries the exact canonical candidate rows prepare
--   froze (candidate_payload_sha256 covers them), with the DB-filled
--   joined_on. "Schema-valid changed/missing/extra row or value" is GL063;
--   unknown/omitted keys, duplicate row numbers, non-array, more than 5,000
--   elements and JSON null are 22023; both leave the run pending and precede
--   member writes. A wrong raw-file digest outranks the rows check
--   ("Authorization, row lock, uploader comparison and raw-file digest
--   comparison precede terminal replay" — GL064 fires even with tampered
--   rows).
-- * p_rows SQL NULL is the state probe, distinct from JSON null (malformed,
--   22023) and from an empty array (a valid exact-candidates value when
--   prepare found no candidates — run 7 commits '[]' and wins completed).
-- * The probe response shape is NOT pinned: "This is an internal pending
--   probe response, not the terminal MemberImportCommitResult", so the probe
--   is asserted by text containment of the frozen parser contract, branch and
--   effective day, plus write-nothing row equality. Terminal results ARE
--   pinned: "Terminal results use the response fields above" — importId,
--   status, replayed, counts{rows,imported,duplicates,invalid}, failure, with
--   integer counters as JSON numbers.
-- * A legacy row (null uploaded_by_user_id) matches no JWT user, so by the
--   frozen check order no caller owns it and its commit is 42501, never a
--   terminal replay.
-- * A processing run answers the probe with 55000 import_not_pending; the
--   caller passes the run's own digest so only the status can refuse.
-- * A cross-gym run and an unknown import id are each 42501 and pinned
--   indistinguishable (same SQLSTATE and detail) — "The RPC never probes or
--   reports another tenant".
-- * The commit-time duplicate recheck is proven subset-only by pre-inserting
--   a same-gym member with one candidate's phone: that candidate flips to
--   existing_phone, no candidate is added, the preview set and digest stay
--   immutable. The genuine concurrent-insert 23505 race and a gym-local
--   midnight crossing cannot be staged from one connection (now() is
--   transaction-stable), so they are covered by this subset proof and the
--   serial replay proofs; a concurrent-commit race is likewise unstageable.
-- * An unexpected exception inside commit's atomic block is stored as
--   {"code":"processing_failed"} and returned, not raised: a temporary CHECK
--   constraint that only the third candidate's name violates makes the whole
--   commit fail, and NO member from that run survives.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed; the probe
-- CHECK constraint is dropped before finish().
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenants.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(88);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 62000000 is this file's alone.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('62000000-0000-4000-8000-000000000001','Import Commit A','MIC62A','active','Asia/Kolkata','INR'),
 ('62000000-0000-4000-8000-000000000002','Import Commit B','MIC62B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000001','Main A',true),
 ('62000000-0000-4000-8000-000000000013','62000000-0000-4000-8000-000000000002','Main B',true);
insert into auth.users(id) values
 ('62000000-0000-4000-8000-000000000901'),('62000000-0000-4000-8000-000000000902'),
 ('62000000-0000-4000-8000-000000000903'),('62000000-0000-4000-8000-000000000904'),
 ('62000000-0000-4000-8000-000000000905'),('62000000-0000-4000-8000-000000000906'),
 ('62000000-0000-4000-8000-000000000907'),('62000000-0000-4000-8000-000000000908');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('62000000-0000-4000-8000-000000000906','platform_support','Support Probe','support@example.test',true),
 ('62000000-0000-4000-8000-000000000907','super_admin','Super Probe','super@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('62000000-0000-4000-8000-000000000021','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000901','62000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('62000000-0000-4000-8000-000000000022','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000902','62000000-0000-4000-8000-000000000011','gym_owner','Owner A2',true),
 ('62000000-0000-4000-8000-000000000023','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000903','62000000-0000-4000-8000-000000000011','front_desk','Desk A',true),
 ('62000000-0000-4000-8000-000000000024','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000904','62000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('62000000-0000-4000-8000-000000000028','62000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000908','62000000-0000-4000-8000-000000000013','gym_owner','Owner B',true);
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,member_code,status) values
 ('62000000-0000-4000-8000-000000000031','62000000-0000-4000-8000-000000000001',null,'62000000-0000-4000-8000-000000000011','Existing Member','+919800000001','A-100','active'),
 ('62000000-0000-4000-8000-000000000034','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000905','62000000-0000-4000-8000-000000000011','Token Member','+919800000009',null,'active');

create temp table population_probe as select
 (select count(*) from public.memberships where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')) as memberships,
 (select count(*) from public.payments where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')) as payments,
 (select count(*) from public.attendance where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')) as attendance,
 (select count(*) from public.consents where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')) as consents,
 (select count(*) from auth.users where id::text like '62000000-%') as users;

create temp table prep_results(label text, result jsonb);
grant select,insert on prep_results to authenticated;
create temp table run_ids(label text, id uuid);
grant select,insert on run_ids to authenticated;
grant select on run_ids to anon;

create or replace function pg_temp.captured_error(p_sql text)
returns table(returned_state text,detail text)
language plpgsql
as $fn$
begin
  execute p_sql;
  return query select null::text,null::text;
exception when others then
  get stacked diagnostics returned_state=returned_sqlstate,detail=pg_exception_detail;
  return next;
end
$fn$;
grant execute on function pg_temp.captured_error(text) to authenticated;

-- Handler-normalized prepare inputs.
create temp table mi_payloads(label text, payload jsonb);
grant select on mi_payloads to authenticated;
insert into mi_payloads values
 ('r1_rows',$$[
  {"rowNumber":2,"full_name":"Asha Rao","phone":"+919800000101","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Dev Patel","phone":"+919800000102","member_code":null,"email":"dev30@example.test","gender":"male","date_of_birth":"1992-03-20","joined_on":"2026-01-10","notes":"Wants strength plan"},
  {"rowNumber":4,"full_name":"Deepa Menon","phone":"+919800000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":5,"full_name":"Future Row","phone":"+919800000005","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":"2999-01-01","notes":null}
 ]$$::jsonb),
 ('r2_rows',$$[
  {"rowNumber":2,"full_name":"Cand One","phone":"+919800000201","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Cand Two","phone":"+919800000202","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('r3_rows',$$[
  {"rowNumber":2,"full_name":"R3 One","phone":"+919800000301","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"R3 Two","phone":"+919800000302","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('r4_rows',$$[
  {"rowNumber":2,"full_name":"Quiet Row","phone":"+919800000401","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Boom Row","phone":"+919800000402","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":4,"full_name":"Dup Row","phone":"+919800000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('b_rows',$$[
  {"rowNumber":2,"full_name":"B Side","phone":"+919890000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb);
insert into mi_payloads
 select 'big_rows', jsonb_agg(jsonb_build_object('rowNumber',g,'full_name','Bulk Row','phone','+919800'||lpad(g::text,4,'0'),'member_code',null,'email',null,'gender',null,'date_of_birth',null,'joined_on',null,'notes',null) order by g)
 from generate_series(1,5001) g;

-- The exact canonical candidate payloads (DB-filled joined_on included) the
-- owner confirms with. The stored digest covers exactly these.
create temp table mi_candidates as
with eff as (select (transaction_timestamp() at time zone 'Asia/Kolkata')::date as d),
v(run,r,fn,ph,mc,em,gd,db,jo,nt) as (values
 ('r1',2,'Asha Rao','+919800000101',null::text,null::text,null::text,null::text,null::text,null::text),
 ('r1',3,'Dev Patel','+919800000102',null,'dev30@example.test','male','1992-03-20','2026-01-10','Wants strength plan'),
 ('r2',2,'Cand One','+919800000201',null,null,null,null,null,null),
 ('r2',3,'Cand Two','+919800000202',null,null,null,null,null,null),
 ('r3',2,'R3 One','+919800000301',null,null,null,null,null,null),
 ('r3',3,'R3 Two','+919800000302',null,null,null,null,null,null),
 ('r4',2,'Quiet Row','+919800000401',null,null,null,null,null,null),
 ('r4',3,'Boom Row','+919800000402',null,null,null,null,null,null),
 ('b',2,'B Side','+919890000001',null,null,null,null,null,null)),
p as (select run, jsonb_agg(jsonb_build_object('rowNumber',r,'full_name',fn,'phone',ph,'member_code',mc,'email',em,'gender',gd,'date_of_birth',db,'joined_on',coalesce(jo,(select d::text from eff)),'notes',nt) order by r) as payload from v group by run)
select run, payload from p;
insert into mi_candidates values ('r7','[]'::jsonb);
grant select on mi_candidates to authenticated;

-- Tamper variants over r2's exact candidates.
create temp table r2_variants(label text, payload jsonb);
grant select on r2_variants to authenticated;
insert into r2_variants
 select 'changed', jsonb_set(c.payload,'{0,full_name}','"Cand One Renamed"'::jsonb) from mi_candidates c where c.run='r2'
 union all select 'missing_row', c.payload - 0 from mi_candidates c where c.run='r2'
 union all select 'extra_row', c.payload || jsonb_build_array(jsonb_build_object('rowNumber',4,'full_name','Extra Row','phone','+919800000299','member_code',null,'email',null,'gender',null,'date_of_birth',null,'joined_on',(transaction_timestamp() at time zone 'Asia/Kolkata')::date::text,'notes',null)) from mi_candidates c where c.run='r2'
 union all select 'omitted_key', jsonb_set(c.payload,'{0}',(c.payload->0)-'notes') from mi_candidates c where c.run='r2'
 union all select 'unknown_key', jsonb_set(c.payload,'{0}',(c.payload->0)||'{"extra_col":1}'::jsonb) from mi_candidates c where c.run='r2'
 union all select 'dup_rows', jsonb_build_array(c.payload->0,c.payload->0) from mi_candidates c where c.run='r2'
 union all select 'object', '{"rowNumber":2}'::jsonb
 union all select 'json_null', 'null'::jsonb;

-- Two postgres-owned runs outside the command path: a processing v1 run and
-- a legacy pending row with no uploader user identity. A v1 row must start
-- pending (CSV-D16 -- "force initial pending"), so this fixture reaches
-- 'processing' the only legal way: insert pending, then take the one graph
-- edge pending->processing as a second postgres statement.
insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) values (
 '62000000-0000-4000-8000-000000000b05','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000021','processing.csv','{"full_name":0,"phone":1}'::jsonb,'pending',0,0,0,
 '{"version":1,"summary":{"invalid":0,"duplicate":0},"previewCandidateRows":[],"importedRows":[],"rows":[],"failure":null}'::jsonb,
 '62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000b05',repeat('f5',32),'import-parser-v1','IN',(transaction_timestamp() at time zone 'Asia/Kolkata')::date,'62000000-0000-4000-8000-000000000901',repeat('aa',32));
update public.member_imports set status='processing' where id='62000000-0000-4000-8000-000000000b05';
insert into public.member_imports(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count) values (
 '62000000-0000-4000-8000-000000000b06','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000021','legacy.csv','{"full_name":0,"phone":1}'::jsonb,'pending',2,0,0);
insert into run_ids values ('r5','62000000-0000-4000-8000-000000000b05'),('r6','62000000-0000-4000-8000-000000000b06');

-- ---------------------------------------------------------------------------
-- Prepare runs 1-4 as owner A, the B run as owner B, capturing each run id
-- through RLS as the owner reads it back.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);

select lives_ok($$insert into prep_results select 'r1_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a01','members.csv',repeat('a1',32),'import-parser-v1','62000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,4,(select payload from mi_payloads where label='r1_rows'),'[]'::jsonb)$$,'owner A wins a pending preview for the four-row run 1');
select lives_ok($$insert into prep_results select 'r2_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a02','members2.csv',repeat('b2',32),'import-parser-v1','62000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,2,(select payload from mi_payloads where label='r2_rows'),'[]'::jsonb)$$,'owner A wins a pending preview for the two-candidate run 2');
select lives_ok($$insert into prep_results select 'r3_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a03','members3.csv',repeat('c3',32),'import-parser-v1','62000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,2,(select payload from mi_payloads where label='r3_rows'),'[]'::jsonb)$$,'owner A wins a pending preview for the two-candidate run 3');
select lives_ok($$insert into prep_results select 'r4_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a04','members4.csv',repeat('d4',32),'import-parser-v1','62000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,3,(select payload from mi_payloads where label='r4_rows'),'[]'::jsonb)$$,'owner A wins a pending preview for the three-row run 4');
insert into run_ids
 select k.label, m.id from public.member_imports m
 join (values ('r1','62000000-0000-4000-8000-000000000a01'),('r2','62000000-0000-4000-8000-000000000a02'),('r3','62000000-0000-4000-8000-000000000a03'),('r4','62000000-0000-4000-8000-000000000a04')) as k(label,rk)
 on m.request_key = k.rk::uuid
 where m.tenant_id = '62000000-0000-4000-8000-000000000001';

select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000002","staff_id":"62000000-0000-4000-8000-000000000028"}',true);
select lives_ok($$insert into prep_results select 'b_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a09','bmembers.csv',repeat('f9',32),'import-parser-v1','62000000-0000-4000-8000-000000000013','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,1,(select payload from mi_payloads where label='b_rows'),'[]'::jsonb)$$,'owner B wins a pending preview in its own gym');
insert into run_ids select 'b', id from public.member_imports where tenant_id='62000000-0000-4000-8000-000000000002' and request_key='62000000-0000-4000-8000-000000000a09';

set local role postgres;
select set_config('request.jwt.claims','',true);

select results_eq($$select status::text, row_count, imported_count, duplicate_count, error_report->'previewCandidateRows' = '[2,3]'::jsonb, error_report->'summary' = '{"invalid":1,"duplicate":1}'::jsonb, error_report->'importedRows' = '[]'::jsonb, error_report->'failure' = 'null'::jsonb from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select 'pending',4,0,1,true,true,true,true$$,'run 1 waits pending with two candidates, one existing-phone duplicate and one future-date invalid row');
select results_eq($$select candidate_payload_sha256 from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select encode(digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') from mi_candidates where run='r1'$$,'run 1 froze the canonical candidate digest over the two defaulted rows');
select results_eq($$select status::text, error_report->'previewCandidateRows' = '[2]'::jsonb, duplicate_count from public.member_imports where id=(select id from run_ids where label='b')$$,$$select 'pending',true,0$$,'the B run waits pending with its single candidate');

create temp table r1_probe as select * from public.member_imports where id=(select id from run_ids where label='r1');
create temp table r2_pre as select * from public.member_imports where id=(select id from run_ids where label='r2');
create temp table r3_pre as select * from public.member_imports where id=(select id from run_ids where label='r3');
create temp table r4_pre as select * from public.member_imports where id=(select id from run_ids where label='r4');

-- ---------------------------------------------------------------------------
-- Run 1: the SQL-NULL state probe writes nothing and reports the frozen facts.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r1_probe_call', public.commit_member_import((select id from run_ids where label='r1'),repeat('a1',32),null)$$,'the uploader wins a state probe by passing SQL NULL rows');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result::text like '%import-parser-v1%', result::text like '%62000000-0000-4000-8000-000000000011%', result::text like '%'||(transaction_timestamp() at time zone 'Asia/Kolkata')::date::text||'%' from prep_results where label='r1_probe_call'$$,$$select true,true,true$$,'the pending probe reports the frozen parser contract, branch and gym-local effective day');
select results_eq($$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from r1_probe$$,'the probe changed no stored fact of the pending run');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone='+919800000101'$$,$$select 0::bigint$$,'the probe imported no member');

-- ---------------------------------------------------------------------------
-- Run 1: the exact-candidates commit completes with the pinned terminal
-- result and writes CSV-D14 profile-only members.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r1_commit', public.commit_member_import((select id from run_ids where label='r1'),repeat('a1',32),(select payload from mi_candidates where run='r1'))$$,'the exact-candidates commit completes the run');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select (result ?& array['importId','status','replayed','counts','failure']), (result->>'importId') = (select id::text from run_ids where label='r1'), result->>'status', result->>'replayed', (result->'counts' ?& array['rows','imported','duplicates','invalid']) from prep_results where label='r1_commit'$$,$$select true,true,'completed','false',true$$,'the terminal result uses the frozen response fields with the run id, completed status and first-commit flag');
select results_eq($$select jsonb_typeof(result->'counts'->'rows')::text, jsonb_typeof(result->'counts'->'imported')::text, jsonb_typeof(result->'counts'->'duplicates')::text, jsonb_typeof(result->'counts'->'invalid')::text from prep_results where label='r1_commit'$$,$$select 'number','number','number','number'$$,'the integer counters remain JSON numbers');
select results_eq($$select (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int, result->'failure' = 'null'::jsonb from prep_results where label='r1_commit'$$,$$select 4,2,1,1,true$$,'the completed counters derive from the final report: 4 rows are 2 imported, 1 duplicate and 1 invalid with a null failure');
select results_eq($$select full_name, phone, status::text, joined_on::text, rest_days = '{}'::smallint[], motivation_push_enabled, user_id is null, weekly_goal_visits is null, photo_url is null, branch_id::text from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone='+919800000101'$$,$$select 'Asha Rao','+919800000101','active',(transaction_timestamp() at time zone 'Asia/Kolkata')::date::text,true,true,true,true,true,'62000000-0000-4000-8000-000000000011'$$,'the imported member with a blank joined_on gets the frozen effective day and the CSV-D14 profile-only defaults');
select results_eq($$select full_name, phone, email, gender, date_of_birth::text, joined_on::text, notes, member_code is null, user_id is null from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone='+919800000102'$$,$$select 'Dev Patel','+919800000102','dev30@example.test','male','1992-03-20','2026-01-10','Wants strength plan',true,true$$,'the imported member keeps its own joined_on and profile fields with no code and no user link');
select results_eq($$select status::text, imported_count, duplicate_count, error_report->'importedRows' = '[2,3]'::jsonb, error_report->'previewCandidateRows' = '[2,3]'::jsonb, error_report->'failure' = 'null'::jsonb, candidate_payload_sha256 = (select candidate_payload_sha256 from r1_probe) from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select 'completed',2,1,true,true,true,true$$,'the stored run is completed with imported rows [2,3], an immutable preview set and an unchanged candidate digest');
select results_eq($$select error_report->'rows' from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select '[{"rowNumber":4,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":5,"disposition":"invalid","field":"joined_on","reasonCode":"future_date"}]'::jsonb$$,'the final report keeps only the non-imported rows with their dispositions');
select results_eq($$select row_count, imported_count, duplicate_count, (error_report->'summary'->>'invalid')::int, row_count = imported_count + duplicate_count + (error_report->'summary'->>'invalid')::int from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select 4,2,1,1,true$$,'the completed stored equation holds: 4 rows are 2 imported, 1 duplicate and 1 invalid');
select results_eq($$select (select count(*) from jsonb_array_elements_text(m.error_report->'importedRows') i where i::int not in (select c::int from jsonb_array_elements_text(m.error_report->'previewCandidateRows') c)), (select count(distinct n) from (select (x->>'rowNumber')::int from jsonb_array_elements(m.error_report->'rows') x union all select i::int from jsonb_array_elements_text(m.error_report->'importedRows') i) u(n)), (select count(*) from jsonb_array_elements(m.error_report->'rows') x where (x->>'rowNumber')::int in (select i::int from jsonb_array_elements_text(m.error_report->'importedRows') i)) from public.member_imports m where id=(select id from run_ids where label='r1')$$,$$select 0::bigint,4::bigint,0::bigint$$,'imported rows stay inside the preview set and partition the run with the final report rows exactly once');

create temp table r1_committed as select * from public.member_imports where id=(select id from run_ids where label='r1');

-- ---------------------------------------------------------------------------
-- Run 1: exact replay, terminal probe, then the two ownership/digest refusals
-- that precede terminal replay.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r1_replay', public.commit_member_import((select id from run_ids where label='r1'),repeat('a1',32),(select payload from mi_candidates where run='r1'))$$,'a second exact commit is a terminal replay, not an error');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='r1_replay'$$,$$select 'completed','true',4,2,1,1$$,'the replay answers with the stored terminal counters and replayed true');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000101','+919800000102')$$,$$select 2::bigint$$,'the replay imported no second member');
select results_eq($$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from public.member_imports where id=(select id from run_ids where label='r1')$$,$$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from r1_committed$$,'the replay changed no stored fact of the completed run');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r1_terminal_probe', public.commit_member_import((select id from run_ids where label='r1'),repeat('a1',32),null)$$,'the state probe on a completed run returns the terminal result');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'imported')::int from prep_results where label='r1_terminal_probe'$$,$$select 'completed','true',2$$,'the terminal probe reports replayed true with the stored counters');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r1'),repeat('cd',32),(select payload from mi_candidates where run='r1'))$$,'GL064',null,'a wrong raw-file digest is GL064 even on a completed run');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000022"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r1'),repeat('a1',32),(select payload from mi_candidates where run='r1'))$$,'42501',null,'a different uploader of the same gym is refused even on a completed run');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);

-- ---------------------------------------------------------------------------
-- Run 7: retry under a fresh request key — the imported phones are now
-- existing_phone, and an empty candidate array is a valid commit payload.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into prep_results select 'r7_prep', public.prepare_member_import('62000000-0000-4000-8000-000000000a07','members.csv',repeat('e7',32),'import-parser-v1','62000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,4,(select payload from mi_payloads where label='r1_rows'),'[]'::jsonb)$$,'the same file under a fresh request key wins a new pending run');
insert into run_ids select 'r7', id from public.member_imports where tenant_id='62000000-0000-4000-8000-000000000001' and request_key='62000000-0000-4000-8000-000000000a07';

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text, row_count, duplicate_count, error_report->'previewCandidateRows' = '[]'::jsonb, error_report->'summary' = '{"invalid":1,"duplicate":3}'::jsonb from public.member_imports where id=(select id from run_ids where label='r7')$$,$$select 'pending',4,3,true,true$$,'the retry preview has no candidates: both once-imported phones are existing_phone now');
select results_eq($$select error_report->'rows' from public.member_imports where id=(select id from run_ids where label='r7')$$,$$select '[{"rowNumber":2,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":4,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":5,"disposition":"invalid","field":"joined_on","reasonCode":"future_date"}]'::jsonb$$,'the retry report names all three duplicate rows plus the unchanged future-date invalid row');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r7_commit', public.commit_member_import((select id from run_ids where label='r7'),repeat('e7',32),'[]'::jsonb)$$,'committing the empty candidate array is a real commit, not a probe');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='r7_commit'$$,$$select 'completed','false',4,0,3,1$$,'the retry commit completes importing nothing with the stored duplicate and invalid counts');
select results_eq($$select status::text, imported_count, duplicate_count, error_report->'importedRows' = '[]'::jsonb, error_report->'failure' = 'null'::jsonb from public.member_imports where id=(select id from run_ids where label='r7')$$,$$select 'completed',0,3,true,true$$,'the retry run is completed with empty imported rows and no failure');

-- ---------------------------------------------------------------------------
-- Run 2: actor gates on the pending run — every gate probes with the run's
-- own digest so only identity can refuse.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'a front-desk user cannot inspect an import');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000024"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'a trainer cannot inspect an import');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"member","tenant_id":"62000000-0000-4000-8000-000000000001","member_id":"62000000-0000-4000-8000-000000000034"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'a member cannot inspect an import');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021","impersonation_session_id":"62000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'an impersonation session cannot inspect an import even with an otherwise complete owner claim');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","impersonation_session_id":"62000000-0000-4000-8000-000000000802"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'an impersonating gym_owner role does not substitute for its deliberately absent staff id on commit');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"platform_support"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'platform support cannot inspect an import');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'the super admin has no gym-side commit identity');
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),null)$$,'42501',null,'anon cannot execute the import commands');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000022"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from mi_candidates where run='r2'))$$,'42501',null,'a different uploader of the same gym cannot commit a pending run');
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text from public.member_imports where id=(select id from run_ids where label='r2')$$,$$select 'pending'$$,'run 2 is still pending after every actor refusal');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000201','+919800000202')$$,$$select 0::bigint$$,'no run-2 member exists after every actor refusal');

-- ---------------------------------------------------------------------------
-- Run 2: digest and payload tampering. Digest outranks rows; every tamper
-- leaves the run pending with its evidence unchanged.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('cd',32),(select payload from mi_candidates where run='r2'))$$,'GL064',null,'a wrong raw-file digest is GL064 on a pending run');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='changed'))$$,'GL063',null,'a schema-valid changed value in the candidate rows is GL063');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='missing_row'))$$,'GL063',null,'a missing candidate row is GL063');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='extra_row'))$$,'GL063',null,'an extra schema-valid candidate row is GL063');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='omitted_key'))$$,'22023',null,'a candidate row with an omitted key is malformed input');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='unknown_key'))$$,'22023',null,'a candidate row with an unknown key is malformed input');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='dup_rows'))$$,'22023',null,'duplicate row numbers in the candidate rows are malformed input');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='object'))$$,'22023',null,'a non-array candidate payload is malformed input');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from r2_variants where label='json_null'))$$,'22023',null,'a JSON null candidate payload is malformed input, not a probe');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from mi_payloads where label='big_rows'))$$,'22023',null,'more than 5,000 candidate rows are malformed input');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r2'),repeat('cd',32),(select payload from r2_variants where label='changed'))$$,'GL064',null,'the raw-file digest comparison precedes the candidate payload check');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text, candidate_payload_sha256 = (select candidate_payload_sha256 from r2_pre), error_report->'previewCandidateRows' = '[2,3]'::jsonb from public.member_imports where id=(select id from run_ids where label='r2')$$,$$select 'pending',true,true$$,'run 2 is still pending with its digest and preview set unchanged after every tamper');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000201','+919800000202')$$,$$select 0::bigint$$,'no run-2 member exists after every tamper');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r2_commit', public.commit_member_import((select id from run_ids where label='r2'),repeat('b2',32),(select payload from mi_candidates where run='r2'))$$,'the untouched exact candidates still commit after all the refusals');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='r2_commit'$$,$$select 'completed','false',2,2,0,0$$,'run 2 completes importing both candidates');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000201','+919800000202') and joined_on = (transaction_timestamp() at time zone 'Asia/Kolkata')::date$$,$$select 2::bigint$$,'both run-2 members exist with the frozen effective day as joined_on');

-- ---------------------------------------------------------------------------
-- Run 3: a same-gym member with a candidate's phone appears between preview
-- and commit — the recheck flips that candidate to existing_phone and adds
-- no candidate.
-- ---------------------------------------------------------------------------

insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('62000000-0000-4000-8000-000000000035','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000011','Race Winner','+919800000302','active');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r3_commit', public.commit_member_import((select id from run_ids where label='r3'),repeat('c3',32),(select payload from mi_candidates where run='r3'))$$,'the commit survives a same-gym phone that appeared after the preview');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='r3_commit'$$,$$select 'completed','false',2,1,1,0$$,'the recheck demotes the raced candidate to a duplicate without adding candidates');
select results_eq($$select status::text, imported_count, duplicate_count, error_report->'importedRows' = '[2]'::jsonb, error_report->'previewCandidateRows' = '[2,3]'::jsonb, error_report->'failure' = 'null'::jsonb, candidate_payload_sha256 = (select candidate_payload_sha256 from r3_pre) from public.member_imports where id=(select id from run_ids where label='r3')$$,$$select 'completed',1,1,true,true,true,true$$,'the stored run imports only the survivor, keeps the immutable preview set and digest, and stores no failure');
select results_eq($$select error_report->'rows' from public.member_imports where id=(select id from run_ids where label='r3')$$,$$select '[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"}]'::jsonb$$,'the final report records the raced row as existing_phone');
select results_eq($$select count(*), max(full_name) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone='+919800000302'$$,$$select 1::bigint,'Race Winner'$$,'the commit neither duplicated nor overwrote the pre-existing member');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone='+919800000301' and joined_on = (transaction_timestamp() at time zone 'Asia/Kolkata')::date$$,$$select 1::bigint$$,'the unraced candidate was imported with the frozen effective day');

-- ---------------------------------------------------------------------------
-- Run 4: an unexpected failure inside the atomic block. A temporary CHECK
-- constraint rejects only the second candidate's name, so the whole commit
-- rolls back, stores processing_failed, and replays as failed.
-- ---------------------------------------------------------------------------

select results_eq($$select status::text, duplicate_count, error_report->'previewCandidateRows' = '[2,3]'::jsonb, error_report->'importedRows' = '[]'::jsonb from public.member_imports where id=(select id from run_ids where label='r4')$$,$$select 'pending',1,true,true$$,'run 4 waits pending with two candidates and the existing-phone duplicate');
alter table public.members add constraint members_import_boom_chk check (full_name <> 'Boom Row');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r4_commit', public.commit_member_import((select id from run_ids where label='r4'),repeat('d4',32),(select payload from mi_candidates where run='r4'))$$,'an unexpected failure inside the commit block returns a failed result instead of raising');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', result->'failure'->>'code', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='r4_commit'$$,$$select 'failed','false','processing_failed',3,0,1,0$$,'the failed result reports processing_failed with zero imports and the retained duplicate count');
select results_eq($$select status::text, imported_count, duplicate_count, error_report->'failure'->>'code', error_report->'importedRows' = '[]'::jsonb, error_report->'previewCandidateRows' = '[2,3]'::jsonb, candidate_payload_sha256 = (select candidate_payload_sha256 from r4_pre) from public.member_imports where id=(select id from run_ids where label='r4')$$,$$select 'failed',0,1,'processing_failed',true,true,true$$,'the stored failure keeps the row count, zeroes imports, retains the duplicate count and freezes the preview set and digest');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000401','+919800000402')$$,$$select 0::bigint$$,'the atomic failure rolled back every member write of the run, including the row that would have succeeded');

alter table public.members drop constraint members_import_boom_chk;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'r4_replay', public.commit_member_import((select id from run_ids where label='r4'),repeat('d4',32),(select payload from mi_candidates where run='r4'))$$,'re-committing a failed run is a replay once the cause is gone');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', result->'failure'->>'code' from prep_results where label='r4_replay'$$,$$select 'failed','true','processing_failed'$$,'the failed replay answers replayed true with the stored failure and does not retry the writes');
select results_eq($$select count(*) from public.members where tenant_id='62000000-0000-4000-8000-000000000001' and phone in ('+919800000401','+919800000402')$$,$$select 0::bigint$$,'the failed replay still imported no member');

-- ---------------------------------------------------------------------------
-- A processing run and a legacy row: the command path refuses both without
-- touching them.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r5'),repeat('f5',32),null)$$,'55000',null,'the probe on a processing run is import_not_pending');
select throws_ok($$select public.commit_member_import((select id from run_ids where label='r6'),repeat('ff',32),null)$$,'42501',null,'a legacy row with no uploader user identity belongs to no caller');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text from public.member_imports where id=(select id from run_ids where label='r5')$$,$$select 'processing'$$,'the processing run is untouched');
select results_eq($$select status::text, imported_count from public.member_imports where id=(select id from run_ids where label='r6')$$,$$select 'pending',0$$,'the legacy row is untouched and still pending');

-- ---------------------------------------------------------------------------
-- Owner B commits its own run; owner A sees nothing of it and cannot
-- distinguish it from an unknown import id.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000002","staff_id":"62000000-0000-4000-8000-000000000028"}',true);
select lives_ok($$insert into prep_results select 'b_commit', public.commit_member_import((select id from run_ids where label='b'),repeat('f9',32),(select payload from mi_candidates where run='b'))$$,'owner B commits its own run');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select result->>'status', result->>'replayed', (result->'counts'->>'rows')::int, (result->'counts'->>'imported')::int, (result->'counts'->>'duplicates')::int, (result->'counts'->>'invalid')::int from prep_results where label='b_commit'$$,$$select 'completed','false',1,1,0,0$$,'the B run completes for its own owner');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"62000000-0000-4000-8000-000000000001","staff_id":"62000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.commit_member_import((select id from run_ids where label='b'),repeat('f9',32),null)$$,'42501',null,'a foreign gym cannot inspect another gym run');
select throws_ok($$select public.commit_member_import('62000000-0000-4000-8000-0000000000fe',repeat('f9',32),null)$$,'42501',null,'an unknown import id is refused the same way');
select results_eq($$select * from pg_temp.captured_error($sql$select public.commit_member_import((select id from run_ids where label='b'),repeat('f9',32),null)$sql$) c$$,$$select * from pg_temp.captured_error($sql$select public.commit_member_import('62000000-0000-4000-8000-0000000000fe',repeat('f9',32),null)$sql$) c$$,'a foreign run is indistinguishable from an unknown import id');

-- ---------------------------------------------------------------------------
-- Nothing was invented: no side rows, no audit.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select (select count(*) from public.memberships where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')),(select count(*) from public.payments where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')),(select count(*) from public.attendance where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')),(select count(*) from public.consents where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')),(select count(*) from auth.users where id::text like '62000000-%')$$,$$select memberships,payments,attendance,consents,users from population_probe$$,'commit touches no membership, payment, attendance, consent or user row');
select is((select count(*) from public.audit_log where tenant_id in ('62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002')), 0::bigint, 'commit invents no audit rows');

select * from finish();

rollback;
