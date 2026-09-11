-- 29_member_import_prepare.sql — Phase 6 member import, visible suite 2 of 3:
-- prepare_member_import identity and actor gates, the frozen effective day,
-- the four duplicate classes, the versioned pending report, the canonical
-- candidate digest, request-key replay and GL068 conflicts.
--
-- Derived only from the frozen CSV-001..CSV-006 contract detail in
-- docs/planning/phase6-import-contract.md (the sections "Mapping and
-- normalization", "Inspect, preview and confirmation", "Duplicate order and
-- counters", "Canonical candidate payload", "Stored and downloadable report",
-- "Stable file/API error codes" and the prepare half of "Schema, generated
-- types and test split"). The Phase 6 import implementation and
-- supabase/tests-holdout/ were not read; no Phase 6 import migration exists
-- yet, so this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * p_rows carries handler-normalized values: "The handler sends every
--   non-blank source row, its normalized parseable field facts and phase-A
--   errors", so blank joined_on stays null in the input and the RPC fills it.
--   p_preclassified_report is pinned as an array of {rowNumber, field,
--   reasonCode} objects — "contains all local field-invalid reasons by row and
--   field" — with the field allowlist and reason codes the contract names
--   (required, ambiguous_phone, invalid_date, future_date, existing_phone,
--   existing_member_code, file_phone, file_member_code).
-- * Report items are ordered "by row, field and reason-code order"; the one
--   field order the contract defines is the canonical mapping/candidate-payload
--   key order ("Keys are written in the order below": full_name, phone,
--   member_code, email, gender, date_of_birth, joined_on, notes). Row 8 of the
--   main file carries existing_phone + file_member_code, and its pinned item
--   order also agrees with the frozen duplicate-class order, so both readings
--   of the contract converge on the same report.
-- * prepare's return key names are not frozen by the contract, so the result is
--   asserted only to be a JSON object; every substantive fact is asserted on
--   the stored run and on replay effects instead.
-- * Malformed config (mapping shape, phone-country mode, digest shape,
--   row/report population) is pinned as SQLSTATE 22023: the contract's
--   "Database refusal mapping is exact" list has exactly one slot for a
--   malformed config field, "22023 is invalid_request", and a raw CHECK
--   constraint violation would leak "constraint detail" that "Messages ...
--   never include". The mapping whitelist itself is CSV-D05's ("SHALL allow
--   only the six named optional member fields"), and the definer command
--   stores that mapping as canonical immutable evidence, so it may not persist
--   an unvalidated caller mapping. Source-index range is NOT asserted here:
--   the header width is route-side knowledge.
-- * A cross-gym branch and an unknown branch are each refused and are pinned
--   indistinguishable from each other (same SQLSTATE and detail); the contract
--   never names a distinct code for either, and "The RPC never probes or
--   reports another tenant" forbids telling them apart.
-- * A gym-local midnight cannot be crossed inside one pgTAP transaction
--   (now() is transaction-stable), and the runner cannot open a second
--   connection for a concurrent replay. "Even across a gym-local midnight" and
--   "sequentially or concurrently" are therefore covered by serial exact
--   replay proving the stored run wins unchanged, which is the observable
--   content of both claims.
--
-- The 16-row main file exercises every duplicate class, the count-once rule,
-- key reservation by skipped rows, case-sensitive member-code comparison,
-- cross-gym invisibility, combined invalid-phone + future-date errors on one
-- row, a future date as the only error, an invalid joined_on that must NOT be
-- defaulted, and a blank joined_on that must be defaulted with the gym-local
-- day. A Dubai gym proves the day derives from the organization's timezone
-- rather than any database session default.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenants.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(62);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 61000000 is this file's alone; no other suite or the seed
-- uses it.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('61000000-0000-4000-8000-000000000001','Import Prepare A','MIP61A','active','Asia/Kolkata','INR'),
 ('61000000-0000-4000-8000-000000000002','Import Prepare B','MIP61B','active','Asia/Kolkata','INR'),
 ('61000000-0000-4000-8000-000000000003','Import Prepare Z','MIP61Z','active','Asia/Dubai','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('61000000-0000-4000-8000-000000000011','61000000-0000-4000-8000-000000000001','Main A',true),
 ('61000000-0000-4000-8000-000000000012','61000000-0000-4000-8000-000000000001','Second A',false),
 ('61000000-0000-4000-8000-000000000013','61000000-0000-4000-8000-000000000002','Main B',true),
 ('61000000-0000-4000-8000-000000000014','61000000-0000-4000-8000-000000000003','Main Z',true);
insert into auth.users(id) values
 ('61000000-0000-4000-8000-000000000901'),('61000000-0000-4000-8000-000000000902'),
 ('61000000-0000-4000-8000-000000000903'),('61000000-0000-4000-8000-000000000904'),
 ('61000000-0000-4000-8000-000000000905'),('61000000-0000-4000-8000-000000000906'),
 ('61000000-0000-4000-8000-000000000907'),('61000000-0000-4000-8000-000000000908'),
 ('61000000-0000-4000-8000-000000000909'),('61000000-0000-4000-8000-00000000090a'),
 ('61000000-0000-4000-8000-00000000090b');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('61000000-0000-4000-8000-00000000090a','platform_support','Support Probe','support@example.test',true),
 ('61000000-0000-4000-8000-00000000090b','super_admin','Super Probe','super@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('61000000-0000-4000-8000-000000000021','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000901','61000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('61000000-0000-4000-8000-000000000022','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000902','61000000-0000-4000-8000-000000000011','gym_manager','Manager A',true),
 ('61000000-0000-4000-8000-000000000023','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000903','61000000-0000-4000-8000-000000000011','front_desk','Desk A',true),
 ('61000000-0000-4000-8000-000000000024','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000904','61000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('61000000-0000-4000-8000-000000000026','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000906','61000000-0000-4000-8000-000000000011','gym_manager','Inactive Manager A',false),
 ('61000000-0000-4000-8000-000000000027','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000907','61000000-0000-4000-8000-000000000011','gym_owner','Wrong Link Owner',true),
 ('61000000-0000-4000-8000-000000000028','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000908','61000000-0000-4000-8000-000000000013','gym_owner','Owner B',true),
 ('61000000-0000-4000-8000-000000000029','61000000-0000-4000-8000-000000000003','61000000-0000-4000-8000-000000000909','61000000-0000-4000-8000-000000000014','gym_owner','Owner Z',true);
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,member_code,status) values
 ('61000000-0000-4000-8000-000000000031','61000000-0000-4000-8000-000000000001',null,'61000000-0000-4000-8000-000000000011','Existing Member','+919800000001','A-100','active'),
 ('61000000-0000-4000-8000-000000000033','61000000-0000-4000-8000-000000000002',null,'61000000-0000-4000-8000-000000000013','Gym B Member','+919876543210','B-100','active'),
 ('61000000-0000-4000-8000-000000000034','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000905','61000000-0000-4000-8000-000000000011','Token Member','+919800000009',null,'active');

create temp table population_probe as select
 (select count(*) from public.memberships where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')) as memberships,
 (select count(*) from public.payments where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')) as payments,
 (select count(*) from public.attendance where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')) as attendance,
 (select count(*) from public.consents where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')) as consents,
 (select count(*) from auth.users where id::text like '61000000-%') as users;

create temp table prep_results(label text, result jsonb);
grant select,insert on prep_results to authenticated;

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

-- Handler-normalized input payloads. Row 1 of the source is the header, so
-- the first report row is 2. All 16 rows are non-blank.
create temp table mi_payloads(label text, payload jsonb);
grant select on mi_payloads to authenticated;
insert into mi_payloads values
 ('main_rows',$$[
  {"rowNumber":2,"full_name":"Asha Rao","phone":"+919876543210","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Ravi Kumar","phone":"+919800000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":4,"full_name":"Sanjay Mehta","phone":"+919810000004","member_code":"A-100","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":5,"full_name":"Tara Menon","phone":"+919876543210","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":6,"full_name":"Bhavna Shah","phone":"+919820000006","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":7,"full_name":"Uma Verma","phone":"+919811000007","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":8,"full_name":"Vikram Bose","phone":"+919800000001","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":9,"full_name":"Waman Das","phone":null,"member_code":null,"email":null,"gender":null,"date_of_birth":"2999-01-01","joined_on":null,"notes":null},
  {"rowNumber":10,"full_name":"Chitra Iyer","phone":"+919830000010","member_code":"a-100","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":11,"full_name":"Dev Patel","phone":"+919840000011","member_code":null,"email":"dev@example.test","gender":"male","date_of_birth":"1990-05-15","joined_on":"2026-01-10","notes":null},
  {"rowNumber":12,"full_name":null,"phone":"+919813000012","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":13,"full_name":"Nina Joshi","phone":"+919814000013","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":14,"full_name":"Esha Gupta","phone":"+919850000014","member_code":null,"email":"esha@example.test","gender":"female","date_of_birth":null,"joined_on":null,"notes":"Prefers evening batches"},
  {"rowNumber":15,"full_name":"Zoya Sheikh","phone":"+919815000015","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":"2999-01-01","notes":null},
  {"rowNumber":16,"full_name":"Farid Khan","phone":"+919860000016","member_code":"A-400","email":null,"gender":null,"date_of_birth":null,"joined_on":"2020-06-15","notes":null},
  {"rowNumber":17,"full_name":"Gita Nair","phone":"+919815000015","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('main_report',$$[{"rowNumber":9,"field":"phone","reasonCode":"ambiguous_phone"},{"rowNumber":12,"field":"full_name","reasonCode":"required"},{"rowNumber":13,"field":"joined_on","reasonCode":"invalid_date"}]$$::jsonb),
 ('main_rows_mutated',$$[
  {"rowNumber":2,"full_name":"Asha Rao Replayed","phone":"+919876543210","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Ravi Kumar","phone":"+919800000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":4,"full_name":"Sanjay Mehta","phone":"+919810000004","member_code":"A-100","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":5,"full_name":"Tara Menon","phone":"+919876543210","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":6,"full_name":"Bhavna Shah","phone":"+919820000006","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":7,"full_name":"Uma Verma","phone":"+919811000007","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":8,"full_name":"Vikram Bose","phone":"+919800000001","member_code":"A-300","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":9,"full_name":"Waman Das","phone":null,"member_code":null,"email":null,"gender":null,"date_of_birth":"2999-01-01","joined_on":null,"notes":null},
  {"rowNumber":10,"full_name":"Chitra Iyer","phone":"+919830000010","member_code":"a-100","email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":11,"full_name":"Dev Patel","phone":"+919840000011","member_code":null,"email":"dev@example.test","gender":"male","date_of_birth":"1990-05-15","joined_on":"2026-01-10","notes":null},
  {"rowNumber":12,"full_name":null,"phone":"+919813000012","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":13,"full_name":"Nina Joshi","phone":"+919814000013","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":14,"full_name":"Esha Gupta","phone":"+919850000014","member_code":null,"email":"esha@example.test","gender":"female","date_of_birth":null,"joined_on":null,"notes":"Prefers evening batches"},
  {"rowNumber":15,"full_name":"Zoya Sheikh","phone":"+919815000015","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":"2999-01-01","notes":null},
  {"rowNumber":16,"full_name":"Farid Khan","phone":"+919860000016","member_code":"A-400","email":null,"gender":null,"date_of_birth":null,"joined_on":"2020-06-15","notes":null},
  {"rowNumber":17,"full_name":"Gita Nair","phone":"+919815000015","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('b_rows',$$[
  {"rowNumber":2,"full_name":"Bharat Rao","phone":"+919800000001","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null},
  {"rowNumber":3,"full_name":"Bina Das","phone":"+919876543210","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb),
 ('z_rows',$$[
  {"rowNumber":2,"full_name":"Zara Ali","phone":"+919710000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}
 ]$$::jsonb);

-- The canonical candidate payload recomputed in-test for the 7 candidate rows,
-- with blank joined_on defaulted to the Kolkata gym-local effective day. The
-- stored digest must equal encode(digest(convert_to(<this jsonb>::text,'UTF8'),
-- 'sha256'),'hex') — the contract's exact canonicalization.
create temp table mi_expected as
with eff as (select (transaction_timestamp() at time zone 'Asia/Kolkata')::date as d),
v(r,fn,ph,mc,em,gd,db,jo,nt) as (values
 (2,'Asha Rao','+919876543210',null::text,null::text,null::text,null::text,null::text,null::text),
 (6,'Bhavna Shah','+919820000006','A-300',null,null,null,null,null),
 (10,'Chitra Iyer','+919830000010','a-100',null,null,null,null,null),
 (11,'Dev Patel','+919840000011',null,'dev@example.test','male','1990-05-15','2026-01-10',null),
 (14,'Esha Gupta','+919850000014',null,'esha@example.test','female',null,null,'Prefers evening batches'),
 (16,'Farid Khan','+919860000016','A-400',null,null,null,'2020-06-15',null),
 (17,'Gita Nair','+919815000015',null,null,null,null,null,null)),
p as (select jsonb_agg(jsonb_build_object('rowNumber',r,'full_name',fn,'phone',ph,'member_code',mc,'email',em,'gender',gd,'date_of_birth',db,'joined_on',coalesce(jo,(select d::text from eff)),'notes',nt) order by r) as payload from v)
select payload, encode(digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') as sha from p;

-- ---------------------------------------------------------------------------
-- The main 16-row prepare, as the real gym A owner.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

select lives_ok($$insert into prep_results select 'main', public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'the owner wins a pending preview of a 16-row file');
select results_eq($$select jsonb_typeof(result)::text from prep_results where label='main'$$,$$select 'object'::text$$,'prepare returns a JSON object result');

set local role postgres;
select set_config('request.jwt.claims','',true);

select results_eq($$select tenant_id::text, uploaded_by_staff_id::text, uploaded_by_user_id::text, file_name, file_sha256, parser_contract, branch_id::text, request_key::text, phone_default_country, status::text, row_count::text, imported_count::text, duplicate_count::text, effective_on::text from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select '61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000021','61000000-0000-4000-8000-000000000901','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','61000000-0000-4000-8000-000000000a01','IN','pending','16','0','5',(transaction_timestamp() at time zone 'Asia/Kolkata')::date::text$$,'the pending run derives both uploader identities from the token and freezes every immutable request fact with the Kolkata effective day');
select results_eq($$select column_mapping = '{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb, error_report->'version' = '1'::jsonb, error_report->'importedRows' = '[]'::jsonb, error_report->'failure' = 'null'::jsonb from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select true,true,true,true$$,'the run stores the canonical mapping and a version-1 report with empty imported rows and a null failure');
select results_eq($$select error_report->'summary' = '{"invalid":4,"duplicate":5}'::jsonb, error_report->'previewCandidateRows' = '[2,6,10,11,14,16,17]'::jsonb from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select true,true$$,'the pending report counts 4 invalid and 5 duplicate rows and names exactly the 7 candidates');
select results_eq($$select error_report->'rows' = '[{"rowNumber":3,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":4,"disposition":"duplicate","field":"member_code","reasonCode":"existing_member_code"},{"rowNumber":5,"disposition":"duplicate","field":"phone","reasonCode":"file_phone"},{"rowNumber":7,"disposition":"duplicate","field":"member_code","reasonCode":"file_member_code"},{"rowNumber":8,"disposition":"duplicate","field":"phone","reasonCode":"existing_phone"},{"rowNumber":8,"disposition":"duplicate","field":"member_code","reasonCode":"file_member_code"},{"rowNumber":9,"disposition":"invalid","field":"phone","reasonCode":"ambiguous_phone"},{"rowNumber":9,"disposition":"invalid","field":"date_of_birth","reasonCode":"future_date"},{"rowNumber":12,"disposition":"invalid","field":"full_name","reasonCode":"required"},{"rowNumber":13,"disposition":"invalid","field":"joined_on","reasonCode":"invalid_date"},{"rowNumber":15,"disposition":"invalid","field":"joined_on","reasonCode":"future_date"}]'::jsonb from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select true$$,'the report pins every item: all four duplicate classes, the count-once two-code row, the combined invalid-phone plus future-date row, the un-defaulted invalid joined_on and the future-only row, in row and field order');
select results_eq($$select candidate_payload_sha256 from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select sha from mi_expected$$,'the stored candidate digest is the lowercase SHA-256 of the canonical 7-row candidate payload');
select results_eq($$select row_count, jsonb_array_length(error_report->'previewCandidateRows'), duplicate_count, (error_report->'summary'->>'invalid')::int, row_count = jsonb_array_length(error_report->'previewCandidateRows') + duplicate_count + (error_report->'summary'->>'invalid')::int from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select 16,7,5,4,true$$,'the pending equation holds: 16 rows are 7 candidates, 5 duplicates and 4 invalid');
select results_eq($$select count(*) from public.member_imports m, jsonb_array_elements_text(m.error_report->'previewCandidateRows') c where m.tenant_id='61000000-0000-4000-8000-000000000001' and m.request_key='61000000-0000-4000-8000-000000000a01' and c::int in (select (x->>'rowNumber')::int from jsonb_array_elements(m.error_report->'rows') x)$$,$$select 0::bigint$$,'no row number is both a candidate and a reported row');
select results_eq($$select count(distinct n) from (select (x->>'rowNumber')::int as n from public.member_imports m, jsonb_array_elements(m.error_report->'rows') x where m.tenant_id='61000000-0000-4000-8000-000000000001' and m.request_key='61000000-0000-4000-8000-000000000a01' union all select c::int from public.member_imports m, jsonb_array_elements_text(m.error_report->'previewCandidateRows') c where m.tenant_id='61000000-0000-4000-8000-000000000001' and m.request_key='61000000-0000-4000-8000-000000000a01') u$$,$$select 16::bigint$$,'candidates and reported rows partition all 16 non-blank rows exactly once');

-- ---------------------------------------------------------------------------
-- Exact replay returns the winning run; p_rows is not part of equivalence.
-- ---------------------------------------------------------------------------

create temp table run_probe as select * from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01';
grant select on run_probe to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

select lives_ok($$insert into prep_results select 'replay', public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'an exact replay of the same immutable facts returns the winning stored result');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from run_probe$$,'the exact replay wrote no second run and changed no stored fact, day or classification');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

select lives_ok($$insert into prep_results select 'replay-new-rows', public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows_mutated'),(select payload from mi_payloads where label='main_report'))$$,'a replay with a changed row value and identical immutable facts is still the stored replay');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select row(id,tenant_id,uploaded_by_staff_id,file_name,column_mapping,status,row_count,imported_count,duplicate_count,error_report,created_at,updated_at,branch_id,request_key,file_sha256,parser_contract,phone_default_country,effective_on,uploaded_by_user_id,candidate_payload_sha256) from run_probe$$,'the replay is not reclassified from the new row values and the winning payload and day survive');

-- ---------------------------------------------------------------------------
-- GL068: one immutable fact changed under the same request key.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('cd',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different raw file digest is GL068');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','renamed.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different filename is GL068');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v2','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different parser contract is GL068');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000012','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different branch is GL068');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','E164','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different phone-country mode is GL068');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"notes":8}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key with a different canonical mapping is GL068');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000022"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'GL068',null,'a reused request key by a different uploader conflicts even with equal facts');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

-- ---------------------------------------------------------------------------
-- Gym B wins its own run under the SAME request key uuid: the replay key is
-- (tenant_id, request_key), and B sees neither gym A's member nor its run.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000002","staff_id":"61000000-0000-4000-8000-000000000028"}',true);
select lives_ok($$insert into prep_results select 'b-own', public.prepare_member_import('61000000-0000-4000-8000-000000000a01','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000013','IN','{"full_name":0,"phone":1}'::jsonb,2,(select payload from mi_payloads where label='b_rows'),'[]'::jsonb)$$,'gym B wins its own run under the same request key uuid');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select row_count, imported_count, duplicate_count, status::text, error_report->'previewCandidateRows' = '[2]'::jsonb, error_report->'summary' = '{"invalid":0,"duplicate":1}'::jsonb from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000002' and request_key='61000000-0000-4000-8000-000000000a01'$$,$$select 2,0,1,'pending',true,true$$,'gym B classifies its own member as existing_phone and sees no gym A member, so the foreign phone row stays a candidate');
select results_eq($$select count(*) from public.member_imports where request_key='61000000-0000-4000-8000-000000000a01'$$,$$select 2::bigint$$,'the two gyms hold one run each under the shared request key uuid without disturbing each other');

-- ---------------------------------------------------------------------------
-- A Dubai gym freezes its own local effective day, not the session default.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000003","staff_id":"61000000-0000-4000-8000-000000000029"}',true);
select lives_ok($$insert into prep_results select 'z-own', public.prepare_member_import('61000000-0000-4000-8000-000000000a02','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000014','IN','{"full_name":0,"phone":1}'::jsonb,1,(select payload from mi_payloads where label='z_rows'),'[]'::jsonb)$$,'the Dubai owner wins a preview with one blank joined_on row');

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select effective_on::text, error_report->'previewCandidateRows' = '[2]'::jsonb, duplicate_count::text from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000003' and request_key='61000000-0000-4000-8000-000000000a02'$$,$$select (transaction_timestamp() at time zone 'Asia/Dubai')::date::text, true, '0'$$,'the frozen effective day is the Dubai gym-local day derived from the organization timezone');
select results_eq($$select candidate_payload_sha256 from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000003' and request_key='61000000-0000-4000-8000-000000000a02'$$,$$select encode(digest(convert_to(jsonb_build_array(jsonb_build_object('rowNumber',2,'full_name','Zara Ali','phone','+919710000002','member_code',null,'email',null,'gender',null,'date_of_birth',null,'joined_on',(transaction_timestamp() at time zone 'Asia/Dubai')::date::text,'notes',null))::text,'UTF8'),'sha256'),'hex')$$,'the canonical payload defaults the blank joined_on to the Dubai day, not a database session default');

-- ---------------------------------------------------------------------------
-- Identical facts under a fresh request key win a second run: the key, not the
-- content, is the idempotency dimension.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);
select lives_ok($$insert into prep_results select 'fresh-key', public.prepare_member_import('61000000-0000-4000-8000-000000000a03','members.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"member_code":2,"email":3,"gender":4,"date_of_birth":5,"joined_on":6,"notes":7}'::jsonb,16,(select payload from mi_payloads where label='main_rows'),(select payload from mi_payloads where label='main_report'))$$,'identical facts under a fresh request key win a second independent run');

-- ---------------------------------------------------------------------------
-- Actor gates: only a real, active, linked owner or manager of the gym.
-- Every gate call carries a fully valid payload so only the identity can fail.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d01','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a front-desk user cannot preview an import');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"trainer","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000024"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d02','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a trainer cannot preview an import');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"member","tenant_id":"61000000-0000-4000-8000-000000000001","member_id":"61000000-0000-4000-8000-000000000034"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d03','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a member cannot preview an import');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000906","role":"authenticated","app_role":"gym_manager","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000026"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d04','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'an inactive manager cannot preview an import');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000027"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d05','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a staff id that does not link to the JWT user cannot preview');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000002","staff_id":"61000000-0000-4000-8000-000000000021"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d06','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a staff id that does not belong to the claimed tenant cannot preview');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d07','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a gym_owner claim without a staff id cannot preview');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d08','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'a gym_owner claim without a tenant claim cannot preview');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021","impersonation_session_id":"61000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d09','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'an impersonation session cannot preview even with an otherwise complete owner claim');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","impersonation_session_id":"61000000-0000-4000-8000-000000000802"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d0a','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'an impersonating gym_owner role does not substitute for its deliberately absent staff id');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"platform_support"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d0b','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'platform support cannot preview an import');
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-00000000090b","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d0c','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'the super admin has no gym-side import identity');
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000d0d','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'42501',null,'anon cannot execute the import commands');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"61000000-0000-4000-8000-000000000001","staff_id":"61000000-0000-4000-8000-000000000021"}',true);

-- ---------------------------------------------------------------------------
-- Branch validation: a foreign branch and an unknown branch are refused and
-- indistinguishable.
-- ---------------------------------------------------------------------------

select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000e01','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000013','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,null,'a cross-gym branch is refused');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000e02','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-00000000feed','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,null,'an unknown branch is refused');
select results_eq($$select * from pg_temp.captured_error($sql$select public.prepare_member_import('61000000-0000-4000-8000-000000000e01','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000013','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$sql$) c$$,$$select * from pg_temp.captured_error($sql$select public.prepare_member_import('61000000-0000-4000-8000-000000000e02','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-00000000feed','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$sql$) c$$,'a foreign branch is indistinguishable from an unknown branch');

-- ---------------------------------------------------------------------------
-- Malformed config and inconsistent row/report population: 22023. "The
-- prepare/commit functions validate these set rules and derive the
-- summary/counts from them instead of trusting client counters."
-- ---------------------------------------------------------------------------

select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c01','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','[]'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a non-object mapping is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c02','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a mapping without phone is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c03','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a mapping without full_name is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c04','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1,"status":2}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a mapping for a non-importable member field is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c05','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":1,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'one source column feeding two targets is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c06','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','US','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'an unsupported phone-country mode is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c07','gate.csv',repeat('ab',31),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a non-SHA-256 file digest is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c08','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,5,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a row counter that disagrees with the row population is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c09','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[{"rowNumber":99,"field":"phone","reasonCode":"invalid_phone"}]'::jsonb)$$,'22023',null,'a preclassified reason for an absent row is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c0a','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[{"rowNumber":2,"field":"full_name","reasonCode":"required"}]'::jsonb)$$,'22023',null,'a phase-A error paired with a non-null value is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c0b','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"full_name":"Gate Row","phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a row object without rowNumber is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c0c','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'[{"rowNumber":2,"full_name":null,"phone":"+919800000002","member_code":null,"email":null,"gender":null,"date_of_birth":null,"joined_on":null,"notes":null}]'::jsonb,'[]'::jsonb)$$,'22023',null,'a null full_name without its required error is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c0d','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'{"rowNumber":2}'::jsonb,'[]'::jsonb)$$,'22023',null,'a non-array row population is malformed input');
select throws_ok($$select public.prepare_member_import('61000000-0000-4000-8000-000000000c0e','gate.csv',repeat('ab',32),'import-parser-v1','61000000-0000-4000-8000-000000000011','IN','{"full_name":0,"phone":1}'::jsonb,1,'null'::jsonb,'[]'::jsonb)$$,'22023',null,'a JSON null row population is malformed input');

-- ---------------------------------------------------------------------------
-- Nothing was invented: every refusal wrote no run, no member, no side rows.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*) from public.member_imports where tenant_id='61000000-0000-4000-8000-000000000001'$$,$$select 2::bigint$$,'gym A holds exactly the main run and the fresh-key run after every refusal');
select results_eq($$select count(*) from public.members where tenant_id='61000000-0000-4000-8000-000000000001'$$,$$select 2::bigint$$,'prepare invents no member');
select results_eq($$select (select count(*) from public.memberships where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')),(select count(*) from public.payments where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')),(select count(*) from public.attendance where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')),(select count(*) from public.consents where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')),(select count(*) from auth.users where id::text like '61000000-%')$$,$$select memberships,payments,attendance,consents,users from population_probe$$,'prepare touches no membership, payment, attendance, consent or user row');
select is((select count(*) from public.audit_log where tenant_id in ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003')), 0::bigint, 'prepare invents no audit rows');

select * from finish();

rollback;
