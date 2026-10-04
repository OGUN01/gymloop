-- RPE-001..009/013 visible SQL contract for the CSV-first report-export
-- operations (Wave D report exports).
-- Frozen authority: openspec/changes/report-exports/proposal.md (FROZEN
-- 2026-10-03, CSV-first staging; the invoice half is deferred and is pinned
-- NOWHERE here) and openspec/changes/report-exports/sql-envelope-declaration.md
-- (FROZEN 2026-10-04, the authoritative mechanical envelope). Every behavioural
-- expectation comes from those frozen documents, not from any caller.
--
-- Envelope pinned here (the declaration's exact scalar shape): ONE jsonb
-- object with exactly 19 top-level keys — export_id, dataset, format,
-- generated_at_utc, snapshot_at_utc, source_cutoff_at_utc, range_from,
-- range_through, range_basis, timezone, range_start_utc,
-- range_end_exclusive_utc, branch_id, branch_scope, data_row_count,
-- returned_row_count, row_cap, has_more, rows. The superseded
-- {rows,has_more,timezone} shape is deliberately NOT accepted.
--
-- Prepared auditing is private: the invoker INSERTs into
-- app.report_export_preparations (five input columns only) and the two
-- declared triggers derive+audit. The public append_report_export_event
-- accepts ONLY 'report_export.released' with exactly {byte_count,
-- artifact_sha256}. Over-cap takes the refusal envelope path with NO
-- preparation INSERT and NO audit. Unknown and foreign branches share one
-- indistinguishable refusal (pinned 22023 under the repo's value/shape
-- precedence vocabulary — the declaration names no SQLSTATE; a different
-- mapping is a contract-defect round-trip, not a test edit).
--
-- RED pattern: no mirror DDL. Catalog assertions are NULL-safe
-- (to_regprocedure/to_regclass). Every dynamic statement runs through a
-- catching executor (pg_temp.probe / pg_temp.j / pg_temp.tt), and every
-- envelope capture is guarded (stored only when the call actually returned a
-- JSON object), so the file runs end-to-end RED before the export operations
-- migration exists (42P01/42883) — missing envelopes simply leave no res row
-- and finish() reports the honest plan mismatch instead of aborting — and it
-- judges the real implementation once CI applies it. Nothing commits: one
-- begin/rollback pair.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(206);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('82000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text default 'member', s integer default null, m integer default null, a integer default 901, t integer default 1, p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(t),'staff_id',case when s is not null then pg_temp.u(s) end,'member_id',case when m is not null then pg_temp.u(m) end,'impersonation_session_id',case when p then pg_temp.u(999) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.val(q text) returns text language plpgsql as $$declare r text; begin execute q into r; return r; exception when others then return sqlstate; end$$;
create function pg_temp.j(q text) returns jsonb language plpgsql as $$declare r jsonb; begin execute q into r; return r; exception when others then return null; end$$;
create function pg_temp.tt(q text) returns text language plpgsql as $$declare r text; begin execute q into r; return r; exception when others then return null; end$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.probe(text),pg_temp.val(text),pg_temp.j(text),pg_temp.tt(text) to authenticated,anon,service_role;
create temporary table res(k text primary key,v jsonb);
grant all on res to authenticated,anon;

-- ============ fixtures (existing schema only) ============
insert into auth.users(id) select pg_temp.u(n) from generate_series(901,906) n;
insert into public.organizations(id,name,gym_code,status,timezone) values
(pg_temp.u(1),'RPE A','RPE82A','active','Asia/Kolkata'),
(pg_temp.u(2),'RPE B','RPE82B','active','Asia/Kolkata'),
(pg_temp.u(3),'RPE C','RPE82C','active','Asia/Kolkata');
insert into public.branches(id,tenant_id,name,is_default,timezone) values
(pg_temp.u(11),pg_temp.u(1),'A',true,null),
(pg_temp.u(12),pg_temp.u(2),'B',true,null),
(pg_temp.u(13),pg_temp.u(1),'A-NY',false,'America/New_York'),
(pg_temp.u(14),pg_temp.u(3),'C',true,null);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
(pg_temp.u(21),pg_temp.u(1),pg_temp.u(901),pg_temp.u(11),'gym_owner','Owner',true),
(pg_temp.u(22),pg_temp.u(1),pg_temp.u(902),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(23),pg_temp.u(1),pg_temp.u(903),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(24),pg_temp.u(1),pg_temp.u(904),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(25),pg_temp.u(2),pg_temp.u(905),pg_temp.u(12),'gym_owner','Other',true),
(pg_temp.u(26),pg_temp.u(3),pg_temp.u(906),pg_temp.u(14),'gym_owner','Zone',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,erased_at,member_code,joined_on) values
(pg_temp.u(101),pg_temp.u(1),pg_temp.u(11),'PRIVATE_MEMBER_101','+918200000101','active',null,'RPE101',date '2026-01-05'),
(pg_temp.u(102),pg_temp.u(1),pg_temp.u(13),'PRIVATE_MEMBER_102','+918200000102','active',null,'RPE102',date '2026-01-06'),
(pg_temp.u(103),pg_temp.u(1),pg_temp.u(11),'PRIVATE_ERASED_103','+918200000103','active',statement_timestamp(),'RPE103',date '2026-01-07'),
(pg_temp.u(105),pg_temp.u(2),pg_temp.u(12),'PRIVATE_FOREIGN_105','+918200000105','active',null,'RPE105',date '2026-02-01'),
(pg_temp.u(106),pg_temp.u(3),pg_temp.u(14),'PRIVATE_ZONE_106','+918200000106','active',null,'RPE106',date '2026-03-08');
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,receipt_number,paid_at,created_at,recorded_by_staff_id) values
(pg_temp.u(401),pg_temp.u(1),pg_temp.u(101),12345,'INR','paid','upi','RPE-0001',timestamptz '2026-01-10 09:05:00+00',timestamptz '2026-01-10 09:00:00+00',pg_temp.u(21)),
(pg_temp.u(402),pg_temp.u(1),pg_temp.u(102),6789,'INR','created','cash',null,null,timestamptz '2026-01-11 10:00:00+00',pg_temp.u(21)),
(pg_temp.u(403),pg_temp.u(1),pg_temp.u(103),555,'INR','paid','cash','RPE-0003',timestamptz '2026-01-12 11:00:00+00',timestamptz '2026-01-12 10:30:00+00',pg_temp.u(21)),
(pg_temp.u(404),pg_temp.u(1),pg_temp.u(101),2500,'USD','paid','card','RPE-0004',timestamptz '2026-01-13 12:00:00+00',timestamptz '2026-01-13 11:45:00+00',pg_temp.u(21)),
-- boundary payments: 405 starts exactly AT gym-local midnight from (inclusive);
-- 406 falls exactly ON local midnight after through (excluded from January).
(pg_temp.u(405),pg_temp.u(1),pg_temp.u(101),111,'INR','paid','upi','RPE-0005',timestamptz '2025-12-31 19:00:00+00',timestamptz '2025-12-31 18:30:00+00',pg_temp.u(21)),
(pg_temp.u(406),pg_temp.u(1),pg_temp.u(101),222,'INR','created','cash',null,null,timestamptz '2026-01-31 18:30:00+00',pg_temp.u(21)),
-- unsafe-size money: beyond the JS safe-integer range, still exact integer paise.
(pg_temp.u(407),pg_temp.u(1),pg_temp.u(101),9007199254740993,'INR','paid','card','RPE-0007',timestamptz '2026-01-20 10:05:00+00',timestamptz '2026-01-20 10:00:00+00',pg_temp.u(21));
-- Arrived money precedes the terminal payment label (GL039). Preserve real
-- full-return evidence through the public refund lifecycle, not arrival in a
-- terminal state; the export still contains the same historical payment.
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,initiated_by_staff_id)
values(pg_temp.u(411),pg_temp.u(1),pg_temp.u(403),'refund',555,'INR','requested','Historical full return',pg_temp.u(21));
update public.refunds set status='processing' where id=pg_temp.u(411);
update public.refunds set status='completed',processed_at=timestamptz '2026-01-12 12:00:00+00' where id=pg_temp.u(411);
update public.payments set status='refunded' where id=pg_temp.u(403);
-- Lawful offline-replay staging: the system accepts an offline visit only as a
-- member gate replay (member claims, source 'qr', a live rotating session and a
-- client event id), so the offline-provenance export row is staged through that
-- real path — a front-desk row can never lawfully carry offline stamps.
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
(pg_temp.u(151),pg_temp.u(1),'RPE Plan',30,100000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,activated_at) values
(pg_temp.u(161),pg_temp.u(1),pg_temp.u(101),pg_temp.u(151),'active',date '2026-01-01',date '2026-01-31',100000,statement_timestamp());
insert into public.organization_settings(tenant_id,checkin_gate_mode) values
(pg_temp.u(1),'rotating_screen');
insert into public.qr_sessions(id,tenant_id,branch_id,token_hash,issued_at,expires_at,gate_mode,created_at) values
(pg_temp.u(430),pg_temp.u(1),pg_temp.u(11),'a6f2c9d4e1b37f80a5c2d9e4f1b8a3c6d9e2f5a8b1c4d7e0f3a6b9c2d5e8f1a4',timestamptz '2026-01-04 00:00:00+00',timestamptz '2026-01-06 00:00:00+00','rotating_screen',timestamptz '2026-01-04 00:00:00+00');
insert into public.attendance(id,tenant_id,branch_id,member_id,source,checked_in_at,checked_out_at,offline_recorded_at,replayed_at,assisted_by_staff_id,assist_reason) values
(pg_temp.u(421),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),'qr',timestamptz '2026-01-05 02:00:00+00',null,null,null,null,null),
(pg_temp.u(422),pg_temp.u(1),pg_temp.u(13),pg_temp.u(102),'front_desk',timestamptz '2026-01-01 02:00:00+00',null,null,null,pg_temp.u(22),'Historical staff-assisted visit');
-- The offline replay itself: recorded under member 101's own claims through the
-- live rotating session; the trigger owns checked_in_at (= offline time) and
-- replayed_at (server-owned). Check-out is the lawful later write.
select pg_temp.claim('member',null,101,901,1);
insert into public.attendance(id,tenant_id,branch_id,member_id,source,qr_session_id,client_event_id,offline_recorded_at) values
(pg_temp.u(423),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),'qr',pg_temp.u(430),pg_temp.u(431),timestamptz '2026-01-05 02:30:00+00');
select set_config('request.jwt.claims','',true);
update public.attendance set checked_out_at=timestamptz '2026-01-05 04:00:00+00' where id=pg_temp.u(423);
insert into public.attendance(id,tenant_id,branch_id,member_id,source,checked_in_at,checked_out_at,offline_recorded_at,replayed_at,assisted_by_staff_id,assist_reason) values
(pg_temp.u(424),pg_temp.u(2),pg_temp.u(12),pg_temp.u(105),'qr',timestamptz '2026-01-20 02:00:00+00',null,null,null,null,null);

-- ============ A. catalog shapes, labels, security labels, grants ============
-- export_report_snapshot: the one bounded invoker data operation per artifact.
select is(to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') is not null, true,'RPE A1: export_report_snapshot(text,date,date,uuid,integer) exists');
select is((select array_to_string(proargtypes::regtype[]::text[],',') from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'text,date,date,uuid,integer','RPE A2: exact argument types');
select is((select array_to_string(proargnames,',') from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'p_dataset,p_from,p_through,p_branch_id,p_row_cap','RPE A3: exact argument names (PostgREST named-arg calling)');
select is((select prosecdef from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),false,'RPE A4: invoker — caller RLS is the read boundary');
select is((select proname from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') and pg_get_userbyid(proowner)='postgres'),'export_report_snapshot','RPE A5: postgres-owned');
select ok((select coalesce(proconfig @> array['search_path=""'],false) from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'RPE A6: empty search path');
select is((select provolatile from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'v','RPE A7: volatile — the audited command writes the prepared attempt (registry STABLE label is not authoritative)');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'jsonb','RPE A8: returns one scalar jsonb envelope');
select is(has_function_privilege('anon','public.export_report_snapshot(text,date,date,uuid,integer)','execute'),false,'RPE A9: anon holds no EXECUTE');
select is(has_function_privilege('service_role','public.export_report_snapshot(text,date,date,uuid,integer)','execute'),false,'RPE A10: service_role holds no EXECUTE');
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
select is(has_function_privilege(current_user,'public.export_report_snapshot(text,date,date,uuid,integer)','execute'),true,'RPE A11: authenticated granted EXECUTE');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- append_report_export_event: the ONLY elevation is audit append; publicly it
-- accepts ONLY the released event (prepared auditing is private, via the
-- preparation relation's triggers).
select is(to_regprocedure('public.append_report_export_event(text,uuid,jsonb)') is not null,true,'RPE A12: append_report_export_event(text,uuid,jsonb) exists');
select is((select array_to_string(proargtypes::regtype[]::text[],',') from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'text,uuid,jsonb','RPE A13: exact argument types');
select is((select array_to_string(proargnames,',') from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'p_event,p_export_id,p_details','RPE A14: exact argument names');
select is((select prosecdef from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),true,'RPE A15: definer — the single audit-append elevation');
select is((select pg_get_userbyid(proowner) from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'postgres','RPE A16: postgres-owned');
select ok((select coalesce(proconfig @> array['search_path=""'],false) from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'RPE A17: empty search path');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'void','RPE A18: returns void');
select is(has_function_privilege('anon','public.append_report_export_event(text,uuid,jsonb)','execute'),false,'RPE A19: anon holds no EXECUTE');
select is(has_function_privilege('service_role','public.append_report_export_event(text,uuid,jsonb)','execute'),false,'RPE A20: service_role holds no EXECUTE');
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
select is(has_function_privilege(current_user,'public.append_report_export_event(text,uuid,jsonb)','execute'),true,'RPE A21: authenticated granted EXECUTE');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- app.report_export_preparations: the private metadata-only preparation relation.
select is(to_regclass('app.report_export_preparations') is not null,true,'RPE A22: app.report_export_preparations exists (private app schema)');
select is((select relrowsecurity from pg_class where oid='app.report_export_preparations'::regclass),true,'RPE A23: the preparation relation keeps RLS');
select is((select array_agg(c.column_name order by c.column_name) from information_schema.columns c where c.table_schema='app' and c.table_name='report_export_preparations'),array['actor_role','actor_user_id','branch_id','branch_scope','data_row_count','dataset','export_id','format','generated_at_utc','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','row_cap','snapshot_at_utc','source_cutoff_at_utc','tenant_id','timezone']::text[],'RPE A24: exactly the five input columns plus the fourteen declared derived columns');
select is(has_any_column_privilege('authenticated','app.report_export_preparations','dataset','insert'),true,'RPE A25: authenticated may INSERT the input columns');
select is(has_any_column_privilege('authenticated','app.report_export_preparations','tenant_id','insert'),false,'RPE A26: authenticated may NOT INSERT derived columns (tenant_id) — attribution is never caller-supplied');
select is(has_table_privilege('authenticated','app.report_export_preparations','update') and has_any_column_privilege('authenticated','app.report_export_preparations','update'),false,'RPE A27: authenticated holds no UPDATE — prepared rows are immutable');
select is(has_table_privilege('authenticated','app.report_export_preparations','delete'),false,'RPE A28: authenticated holds no DELETE');
select ok(not has_table_privilege('anon','app.report_export_preparations','select') and not has_any_column_privilege('anon','app.report_export_preparations','select') and not has_table_privilege('anon','app.report_export_preparations','insert') and not has_any_column_privilege('anon','app.report_export_preparations','insert'),'RPE A29: anon holds no SELECT or INSERT on the preparation relation');
select ok(not has_table_privilege('service_role','app.report_export_preparations','select') and not has_any_column_privilege('service_role','app.report_export_preparations','select') and not has_table_privilege('service_role','app.report_export_preparations','insert') and not has_any_column_privilege('service_role','app.report_export_preparations','insert'),'RPE A30: service_role holds no SELECT or INSERT on the preparation relation');
-- the two declared trigger functions.
select is((select prorettype::regtype::text from pg_proc join pg_namespace n on n.oid=pronamespace where proname='derive_report_export_preparation' and n.nspname='app'),'trigger','RPE A31: app.derive_report_export_preparation returns trigger');
select is((select provolatile from pg_proc join pg_namespace n on n.oid=pronamespace where proname='derive_report_export_preparation' and n.nspname='app'),'s','RPE A32: the derive trigger function is STABLE (source selector/validator)');
select is((select prosecdef from pg_proc join pg_namespace n on n.oid=pronamespace where proname='derive_report_export_preparation' and n.nspname='app'),false,'RPE A33: the derive trigger function is SECURITY INVOKER');
select ok((select coalesce(proconfig @> array['search_path=""'],false) from pg_proc join pg_namespace n on n.oid=pronamespace where proname='derive_report_export_preparation' and n.nspname='app'),'RPE A34: the derive trigger function has an empty search path');
select is(has_function_privilege('authenticated','app.derive_report_export_preparation(trigger)','execute') or has_function_privilege('anon','app.derive_report_export_preparation(trigger)','execute'),false,'RPE A35: no direct EXECUTE on the derive trigger function (trigger invocation needs no grant)');
select is((select prorettype::regtype::text from pg_proc join pg_namespace n on n.oid=pronamespace where proname='audit_report_export_preparation' and n.nspname='app'),'trigger','RPE A36: app.audit_report_export_preparation returns trigger');
select is((select provolatile from pg_proc join pg_namespace n on n.oid=pronamespace where proname='audit_report_export_preparation' and n.nspname='app'),'v','RPE A37: the audit trigger function is VOLATILE');
select is((select prosecdef from pg_proc join pg_namespace n on n.oid=pronamespace where proname='audit_report_export_preparation' and n.nspname='app'),true,'RPE A38: the audit trigger function is SECURITY DEFINER — elevation confined to audit append');
select ok((select coalesce(proconfig @> array['search_path=""'],false) from pg_proc join pg_namespace n on n.oid=pronamespace where proname='audit_report_export_preparation' and n.nspname='app'),'RPE A39: the audit trigger function has an empty search path');
select is(has_function_privilege('authenticated','app.audit_report_export_preparation(trigger)','execute') or has_function_privilege('anon','app.audit_report_export_preparation(trigger)','execute'),false,'RPE A40: no direct EXECUTE on the audit trigger function');
select is((select tgtype from pg_trigger where tgrelid='app.report_export_preparations'::regclass and tgname='report_export_preparations_derive' and not tgisinternal),7,'RPE A41: derive trigger is a BEFORE INSERT row trigger named report_export_preparations_derive');
select is((select tgtype from pg_trigger where tgrelid='app.report_export_preparations'::regclass and tgname='report_export_preparations_audit' and not tgisinternal),5,'RPE A42: audit trigger is an AFTER INSERT row trigger named report_export_preparations_audit');
select is(to_regclass('app.report_export_preparations_tenant_actor_export_idx') is not null,true,'RPE A43: the declared claim/actor access index exists');
select ok((select coalesce(indexdef like '%tenant_id%' and indexdef like '%actor_user_id%' and indexdef like '%export_id%',false) from pg_indexes where schemaname='app' and indexname='report_export_preparations_tenant_actor_export_idx'),'RPE A44: the index covers (tenant_id,actor_user_id,export_id)');
select is((select coalesce(i.indisunique,false) from pg_class c join pg_index i on i.indexrelid=c.oid where c.oid=to_regclass('public.audit_log_report_export_event_unique')),true,'RPE A45: the RPE audit event unique index exists and is UNIQUE (absent before the migration, present+unique after)');
select ok((select coalesce(indpred is not null and pg_get_indexdef(c.oid) like '%report_export.prepared%' and pg_get_indexdef(c.oid) like '%report_export.released%',false) from pg_class c join pg_index i on i.indexrelid=c.oid where c.oid=to_regclass('public.audit_log_report_export_event_unique')),'RPE A46: the unique index is a partial index over exactly the two RPE audit actions');

-- ============ B. owner-only actor revalidation BEFORE validation or reads ============
set local role authenticated;
select pg_temp.claim(); -- member, no staff
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B1: member claims gain nothing');
select set_config('request.jwt.claims','',true);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B2: anon (no claims) refused before any read');
select pg_temp.claim('gym_owner',21,null,901,1,true); -- impersonating owner
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B3: preview/impersonation claim refused before any read');
select pg_temp.claim('trainer',23,null,903,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B4: trainer refused before any read');
select pg_temp.claim('front_desk',22,null,902,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B5: front desk refused before any read');
select pg_temp.claim('gym_manager',24,null,904,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B6: manager refused before any read');
select pg_temp.claim('super_admin');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B7: platform super admin refused before any read');
select pg_temp.claim('gym_owner',999,null,901,1); -- staff id bound to nobody
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'42501','RPE B8: stale/unbound staff claim refused before any read');
select pg_temp.claim('gym_owner',21,null,901,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'OK','RPE B9: the real current owner reads');
select is(pg_temp.probe($q$select public.export_report_snapshot(null,date '2026-01-01',date '2026-01-31',null,100)$q$),'22023','RPE B10: null dataset refused');
select is(pg_temp.probe($q$select public.export_report_snapshot('invoicez',date '2026-01-01',date '2026-01-31',null,100)$q$),'22023','RPE B11: dataset vocabulary is payments|attendance|members only');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-31',date '2026-01-01',null,100)$q$),'22023','RPE B12: reversed range refused');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments','2026-02-30',date '2026-01-31',null,100)$q$),'22008','RPE B13: a non-Gregorian date is refused at the typed-date call parse (22008), before the body — the route''s zod layer rejects it earlier still');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,null)$q$),'22023','RPE B14: null row cap refused');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,0)$q$),'22023','RPE B15: zero row cap refused');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,-1)$q$),'22023','RPE B16: negative row cap refused');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,5001)$q$),'22023','RPE B17: a row cap above the declared 1..5000 bound refuses before the bounded source scan');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',pg_temp.u(999),100)$q$),'22023','RPE B18: an unknown branch shares the one unavailable refusal — no existence oracle');
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',pg_temp.u(12),100)$q$),'22023','RPE B19: a foreign (other-tenant) branch shares the SAME unavailable refusal — indistinguishable from unknown');
select pg_temp.claim('front_desk',22,null,902,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('nonsense','2026-13-01',date '2026-01-31',null,100)$q$),'42501','RPE B20: authorization precedes validation — a refused role learns no validation facts');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'OK','RPE B21: tenant 2 owner reads (their own, empty) — the invalid-zone refusal is a separate case');
-- RPE-003 historical bad-zone coverage: valid BIZ setup first. Only the registered
-- commercial trigger is suspended for this rollback-only fixture corruption;
-- restore it before invoking the production reader and restore the value afterwards.
set local role postgres;
select set_config('request.jwt.claims','',true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set timezone='Mars/Phobos' where id=pg_temp.u(3);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim('gym_owner',26,null,906,3);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'22023','RPE B22: an invalid configured gym zone refuses explicitly, never a fabricated fallback zone');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Asia/Kolkata' where id=pg_temp.u(3);

-- ============ C. payments dataset: projection, money text, ordering, blanks ============
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
insert into res(k,v) select 'pay', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,1000)::text$q$) r) s where s.r like '{%';
select is(jsonb_typeof(v->'rows'),'array','RPE C1: rows is a JSON array in one payload') from res where k='pay';
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,6,'RPE C2: every in-range payment row once (attempts, terminal states and both boundary payments included)') from res where k='pay';
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['amount_display','amount_paise','created_at_utc','currency','current_member_name','member_code','member_id','method','paid_at_utc','payment_id','receipt_number','status']::text[],'RPE C3: exact payments projection (frozen column list)') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(jsonb_typeof(r->'amount_paise'),'string','RPE C4: amount_paise crosses as canonical decimal TEXT') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'amount_paise','111','RPE C5: exact paise value — no float anywhere (boundary payment first by created_at)') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'amount_display' like '%1.11',true,'RPE C6: amount_display is the presentation text of the same paise') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'paid_at_utc',null::text,'RPE C7: a null paid time stays null — never inferred') from (select (v->'rows'->>2)::jsonb r from res where k='pay') s;
select is(r->>'created_at_utc' like '%Z',true,'RPE C8: created_at_utc is an ISO-8601 UTC instant') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'payment_id',pg_temp.u(405)::text,'RPE C9: ordering by (created_at,id) — the exact local-midnight payment is the earliest in-range row (inclusive from boundary)') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'current_member_name',null::text,'RPE C10: an erased member''s name is blank, row survives') from (select (v->'rows'->>3)::jsonb r from res where k='pay') s;
select is(r->>'member_code',null::text,'RPE C11: an erased member''s code is blank') from (select (v->'rows'->>3)::jsonb r from res where k='pay') s;
select is(r->>'member_id',pg_temp.u(103)::text,'RPE C12: the payment''s own member reference is kept (financial evidence, not an Auth id)') from (select (v->'rows'->>3)::jsonb r from res where k='pay') s;
select is(r->>'currency','USD','RPE C13: cross-currency rows keep their own currency — never converted or summed') from (select (v->'rows'->>4)::jsonb r from res where k='pay') s;
select is(r->>'status','refunded','RPE C14: canonical generated-enum status words') from (select (v->'rows'->>3)::jsonb r from res where k='pay') s;
select is((select count(*) from jsonb_array_elements(v->'rows') r where r->>'payment_id'=pg_temp.u(406)::text)::int,0,'RPE C15: the payment at exactly local midnight AFTER through is excluded (exclusive end boundary)') from res where k='pay';
insert into res(k,v) select 'feb', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-02-01',date '2026-02-28',null,1000)::text$q$) r) s where s.r like '{%';
select is((select count(*) from jsonb_array_elements(v->'rows') r where r->>'payment_id'=pg_temp.u(406)::text)::int,1,'RPE C16: that same payment belongs to the February range — the boundary moved, not the row') from res where k='feb';
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,1,'RPE C17: the February range is complete (one row, no stragglers)') from res where k='feb';
select is(r->>'amount_paise','9007199254740993','RPE C18: unsafe-size money crosses as exact canonical decimal text beyond the JS safe-integer range') from (select (v->'rows'->>5)::jsonb r from res where k='pay') s;
select is(r->>'amount_display' like '%409.93',true,'RPE C19: the exact formatter renders unsafe-size money without float drift') from (select (v->'rows'->>5)::jsonb r from res where k='pay') s;
-- branch filter uses the member's CURRENT RLS-visible branch ("Current member branch").
insert into res(k,v) select 'pay13', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',pg_temp.u(13),1000)::text$q$) r) s where s.r like '{%';
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,1,'RPE C20: branch filter keeps only payments whose member''s current branch matches') from res where k='pay13';
select is(r->>'payment_id',pg_temp.u(402)::text,'RPE C21: that one filtered row is the member-102 payment (current branch A-NY)') from (select (v->'rows'->>0)::jsonb r from res where k='pay13') s;
select is((select coalesce(nullif(pg_temp.j($q$select jsonb_array_length(public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',pg_temp.u(11),1000)->'rows')$q$)#>>'{}','')::int,-1),-1),4,'RPE C22: branch A filter keeps the four branch-A member payments — the erased member''s payment cannot satisfy a branch filter') ;
delete from res where k='pay13';
delete from res where k='pay';
delete from res where k='feb';

-- ============ D. attendance dataset: stored branch, branch-zone local stamps ============
insert into res(k,v) select 'att', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',null,1000)::text$q$) r) s where s.r like '{%';
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['attendance_id','branch_id','checked_in_at_utc','checked_in_local','checked_out_at_utc','current_member_name','member_code','member_id','offline_recorded_at_utc','replayed_at_utc','source']::text[],'RPE D1: exact attendance projection (recorded events, not bookings or inferred presence)') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,3,'RPE D2: tenant rows only, one per accepted visit') from res where k='att';
select is(r->>'checked_in_local' like '2025-12-31%',true,'RPE D3: the branch''s own zone dates the visit (America/New_York branch)') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is(r->>'checked_in_local' like '%-05:00%',true,'RPE D4: the local stamp carries its UTC offset') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is(r->>'checked_in_local' like '2026-01-05%',true,'RPE D5: a null branch zone inherits the gym zone (Kolkata)') from (select (v->'rows'->>1)::jsonb r from res where k='att') s;
select is(r->>'checked_out_at_utc' is not null,true,'RPE D6: optional check-out kept when recorded') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'offline_recorded_at_utc' is not null,true,'RPE D7: offline provenance stamp kept') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'replayed_at_utc' is not null,true,'RPE D8: replay stamp kept (ATT-007 evidence)') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'source','qr','RPE D9: canonical attendance source — the offline replay is lawfully a member gate scan (author-owned runtime correction: the original front_desk pin is impossible, offline stamps require the member gate event path)') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'attendance_id',pg_temp.u(422)::text,'RPE D10: ordering by (checked_in_at,id) — earliest first') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is((select coalesce(nullif(pg_temp.j($q$select jsonb_array_length(public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',pg_temp.u(13),1000)->'rows')$q$)#>>'{}','')::int,-1),-1),1,'RPE D11: the branch filter uses the STORED attendance branch');
select pg_temp.claim('gym_owner',25,null,905,2);
select is((select coalesce(nullif(pg_temp.j($q$select jsonb_array_length(public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',null,1000)->'rows')$q$)#>>'{}','')::int,-1),-1),1,'RPE D12: tenant 2 reads only its own visit — cross-tenant rows never enter');
select pg_temp.claim('gym_owner',21,null,901,1);
delete from res where k='att';

-- ============ E. members dataset: joining cohort of non-erased members ============
insert into res(k,v) select 'mem', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('members',date '2026-01-01',date '2026-01-31',null,1000)::text$q$) r) s where s.r like '{%';
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['branch_id','email','full_name','joined_on','member_code','member_id','phone','status']::text[],'RPE E1: exact members projection (no DOB, guardian, notes, consent or account ids)') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,2,'RPE E2: the joining cohort counts current non-erased members only') from res where k='mem';
select is((select count(*) from jsonb_array_elements(v->'rows') r where r->>'member_id'=pg_temp.u(103)::text)::int,0,'RPE E3: an erased member never appears in the roster') from res where k='mem';
select is(r->>'member_id',pg_temp.u(101)::text,'RPE E4: ordering by (joined_on,id) — earliest joined first') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is(r->>'phone','+918200000101','RPE E5: contact facts cross as stored text') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is(r->>'branch_id',pg_temp.u(13)::text,'RPE E6: the member''s current branch (not a payment/visit branch)') from (select (v->'rows'->>1)::jsonb r from res where k='mem') s;
select is((select coalesce(nullif(pg_temp.j($q$select jsonb_array_length(public.export_report_snapshot('members',date '2026-01-01',date '2026-01-31',pg_temp.u(13),1000)->'rows')$q$)#>>'{}','')::int,-1),-1),1,'RPE E7: the members branch filter uses the member''s current branch');
delete from res where k='mem';

-- ============ F. envelope shape, stamps, caps, boundaries ============
insert into res(k,v) select 'bd1', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,6)::text$q$) r) s where s.r like '{%';
insert into res(k,v) select 'bd2', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,6)::text$q$) r) s where s.r like '{%';
insert into res(k,v) select 'cap', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,2)::text$q$) r) s where s.r like '{%';
select is((select array_agg(k order by k) from jsonb_object_keys(v) k),array['branch_id','branch_scope','data_row_count','dataset','export_id','format','generated_at_utc','has_more','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','returned_row_count','row_cap','rows','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],'RPE F1: exactly the 19 declared top-level keys — no extra source/profile fields') from res where k='bd1';
select is(v->>'dataset','payments','RPE F2: the validated dataset is echoed') from res where k='bd1';
select is(v->>'format','csv','RPE F3: format is the literal csv') from res where k='bd1';
select is(v->>'range_from','2026-01-01','RPE F4a: range_from echoes the validated input') from res where k='bd1';
select is(v->>'range_through','2026-01-31','RPE F4: the validated Gregorian range is echoed unchanged') from res where k='bd1';
select is(v->>'range_basis','created_at','RPE F5: the payments range basis is created_at') from res where k='bd1';
select is(v->>'timezone','Asia/Kolkata','RPE F6: the validated gym zone is disclosed') from res where k='bd1';
select is(v->>'range_start_utc','2025-12-31T18:30:00Z','RPE F7: range_start_utc is the gym-local midnight BEFORE from converted to UTC (Kolkata +05:30)') from res where k='bd1';
select is(v->>'range_end_exclusive_utc','2026-01-31T18:30:00Z','RPE F8: range_end_exclusive_utc is gym-local midnight of the day AFTER through (exclusive)') from res where k='bd1';
select is(v->>'branch_id',null::text,'RPE F9: a null branch request carries a null branch_id') from res where k='bd1';
select is(v->>'branch_scope','all','RPE F10: a null branch request declares branch_scope all') from res where k='bd1';
select is(v->>'generated_at_utc' <= v->>'snapshot_at_utc',true,'RPE F11: generation/preparation start never follows the source snapshot') from res where k='bd1';
select is(v->>'snapshot_at_utc',v->>'source_cutoff_at_utc','RPE F12: the source cutoff IS the snapshot timestamp — never a route clock') from res where k='bd1';
select is((select v1->>'export_id' <> v2->>'export_id' from res k1 join res k2 on k1.k='bd1' and k2.k='bd2'),true,'RPE F13: every fresh download/retry obtains a fresh export UUID');
select is(jsonb_typeof(v->'data_row_count')='string' and jsonb_typeof(v->'returned_row_count')='string',true,'RPE F14: both counts cross as canonical decimal INTEGER STRINGS, never JSON numbers') from res where k='bd1';
select is(jsonb_typeof(v->'row_cap'),'number','RPE F15: row_cap is a JSON integer') from res where k='cap';
select is((v->>'row_cap')::int,2,'RPE F16: row_cap echoes the validated p_row_cap') from res where k='cap';
select is(jsonb_array_length(v->'rows'),0,'RPE F17: over cap, NO rows return — the whole file is refused, never truncated') from res where k='cap';
select is(v->>'returned_row_count','0','RPE F18: over cap, the returned count is zero') from res where k='cap';
select is((v->>'has_more')::boolean,true,'RPE F19: over cap discloses more exist (has_more true)') from res where k='cap';
select is(v->>'data_row_count','6','RPE F20: over cap still carries the exact complete snapshot count') from res where k='cap';
select is((select count(*) from app.report_export_preparations where export_id=(select (v->>'export_id')::uuid from res where k='cap'))::int,0,'RPE F21: an over-cap refusal creates NO prepared attempt') from res where k='cap';
select is((select count(*) from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='cap'))::int,0,'RPE F22: an over-cap refusal writes NO audit event') from res where k='cap';
select is(jsonb_array_length(v->'rows'),6,'RPE F23: at the exact boundary cap (6 of 6), every row returns') from res where k='bd1';
select is(v->>'returned_row_count','6','RPE F24: a bounded result returns the complete count') from res where k='bd1';
select is((v->>'has_more')::boolean,false,'RPE F25: an exhausted read says so — no phantom continuation') from res where k='bd1';
select is((select count(*) from app.report_export_preparations where export_id=(select (v->>'export_id')::uuid from res where k='bd1'))::int,1,'RPE F26: an accepted bounded result has exactly one prepared attempt');
select is((select count(*) from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='bd1') and action='report_export.prepared')::int,1,'RPE F27: the prepared audit event was appended atomically with the source operation');
select is((select after->>'snapshot_at_utc' from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='bd1') and action='report_export.prepared'),v->>'snapshot_at_utc','RPE F28: the envelope snapshot equals the audited prepared snapshot — one statement snapshot') from res where k='bd1';
select is((select after->>'data_row_count' from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='bd1') and action='report_export.prepared'),v->>'data_row_count','RPE F29: the audited count equals the envelope count') from res where k='bd1';
select is((select after->>'before' is null from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='bd1') and action='report_export.prepared'),true,'RPE F30: the prepared audit event carries no before image') from res where k='bd1';
select is((select array_agg(k order by k) from jsonb_object_keys(after) k),array['branch_id','branch_scope','data_row_count','dataset','export_id','format','generated_at_utc','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],'RPE F31: the prepared audit after-payload carries exactly the declared stamp keys — no rows, names or file content') from public.audit_log where record_id=(select (v->>'export_id')::uuid from res where k='bd1') and action='report_export.prepared';
select is((select coalesce(nullif(pg_temp.j($q$select public.export_report_snapshot('members',date '2026-01-01',date '2026-01-31',null,1000)$q$)#>>'{range_basis}',''),'-'),'-'),'joined_on','RPE F32: the members range basis is joined_on (direct date comparison)');
select is((select coalesce(nullif(pg_temp.j($q$select public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',null,1000)$q$)#>>'{range_basis}',''),'-'),'-'),'checked_in_at','RPE F33: the attendance range basis is checked_in_at');
-- offset transition: each actual local midnight, never a fixed 24-hour addition.
-- Only the registered commercial trigger is suspended for this rollback-only
-- zone change; the value is restored immediately after the pinned call.
set local role postgres;
select set_config('request.jwt.claims','',true);
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set timezone='America/New_York' where id=pg_temp.u(3);
alter table public.organizations enable trigger organizations_commercial_invariant;
set local role authenticated;
select pg_temp.claim('gym_owner',26,null,906,3);
insert into res(k,v) select 'dst', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('members',date '2026-03-07',date '2026-03-09',null,100)::text$q$) r) s where s.r like '{%';
select is(v->>'range_start_utc','2026-03-07T05:00:00Z','RPE F34: the start boundary uses the actual EST local midnight (UTC-5)') from res where k='dst';
select is(v->>'range_end_exclusive_utc','2026-03-10T04:00:00Z','RPE F35: the end boundary crosses the March 8 DST transition to EDT (UTC-4) — not a fixed 24-hour addition') from res where k='dst';
select is(v->>'timezone','America/New_York','RPE F36: the gym zone used for boundaries is disclosed') from res where k='dst';
select is(v->>'data_row_count','1','RPE F37: the joining cohort of the DST range is complete') from res where k='dst';
select is(jsonb_array_length(v->'rows'),1,'RPE F38: the DST-range rows match the count') from res where k='dst';
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.organizations set timezone='Asia/Kolkata' where id=pg_temp.u(3);
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
-- a zero-match file still stamps and still audits.
insert into res(k,v) select 'zero', s.r::jsonb from (select pg_temp.val($q$select public.export_report_snapshot('payments',date '2026-02-02',date '2026-02-28',null,1000)::text$q$) r) s where s.r like '{%';
select is(v->>'data_row_count','0','RPE F39: a zero-match export counts zero') from res where k='zero';
select is(jsonb_array_length(v->'rows'),0,'RPE F40: a zero-match export has zero data rows') from res where k='zero';
select is((v->>'has_more')::boolean,false,'RPE F40b: a zero-match export is complete — no phantom continuation') from res where k='zero';
select is((select count(*) from app.report_export_preparations where export_id=(select (v->>'export_id')::uuid from res where k='zero'))::int,1,'RPE F41: a zero-row projection still inserts one preparation') from res where k='zero';
delete from res where k='bd1'; delete from res where k='bd2'; delete from res where k='cap';
delete from res where k='dst'; delete from res where k='zero';

-- ============ G. the private preparation relation (direct, lawful same-actor use) ============
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('members',date '2026-01-01',date '2026-01-31',null,2)$q$),'OK','RPE G1: a real owner may insert a lawful bounded preparation attempt with the five input columns only');
select is((select tenant_id from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),pg_temp.u(1),'RPE G2: the tenant is derived from the verified claim, never the caller');
select is((select actor_user_id from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),pg_temp.u(901),'RPE G3: the actor is derived from the verified claim');
select is((select actor_role::text from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),'gym_owner','RPE G4: the actor role is derived from the verified owner');
select is((select range_basis from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),'joined_on','RPE G5: the range basis is derived from the dataset');
select is((select timezone from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),'Asia/Kolkata','RPE G6: the validated gym zone is derived');
select is((select branch_scope from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),'all','RPE G7: a null branch derives the all scope');
select is((select data_row_count::text from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),'2','RPE G8: the complete source count is derived and capped (2 members at cap 2)');
select is((select generated_at_utc is not null and snapshot_at_utc is not null and source_cutoff_at_utc is not null from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),true,'RPE G9: all three clock stamps are derived server-side');
select is((select snapshot_at_utc=source_cutoff_at_utc from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_scope='all' and row_cap=2),true,'RPE G10: the source cutoff equals the snapshot stamp');
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('members',date '2026-01-01',date '2026-01-31',pg_temp.u(11),2)$q$),'OK','RPE G11: a same-tenant branch preparation is lawful');
select is((select branch_scope from app.report_export_preparations where dataset='members' and range_from=date '2026-01-01' and branch_id=pg_temp.u(11))::text,pg_temp.u(11)::text,'RPE G12: a concrete branch derives its UUID scope');
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap,tenant_id) values ('members',date '2026-01-01',date '2026-01-31',null,2,pg_temp.u(1))$q$) in ('22023','42501','P0001'),true,'RPE G13: supplying a derived column is refused — attribution is never caller-supplied');
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('members',date '2026-01-01',date '2026-01-31',null,1)$q$) in ('22023','P0001'),true,'RPE G14: a count above the cap refuses the preparation INSERT (2 members, cap 1)');
select is(pg_temp.probe($q$update app.report_export_preparations set row_cap=9 where dataset='members'$q$),'42501','RPE G15: prepared rows are immutable — no UPDATE');
select is(pg_temp.probe($q$delete from app.report_export_preparations where dataset='members'$q$),'42501','RPE G16: prepared rows are immutable — no DELETE');
select pg_temp.claim(); -- member, no staff
select is((select count(*) from app.report_export_preparations)::int,0,'RPE G17: a member sees no preparation rows (RLS requires the verified owner)');
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('members',date '2026-01-01',date '2026-01-31',null,2)$q$),'42501','RPE G18: a member identity prepares nothing');
select set_config('request.jwt.claims','',true);
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('members',date '2026-01-01',date '2026-01-31',null,2)$q$),'42501','RPE G19: anon prepares nothing');
select pg_temp.claim('gym_owner',25,null,905,2);
select is((select count(*) from app.report_export_preparations)::int,0,'RPE G20: no cross-actor or cross-tenant SELECT through RLS');
select pg_temp.claim('gym_owner',21,null,901,1);
select is((select after->>'data_row_count' from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.prepared'),'2','RPE G21: the direct lawful preparation appended its prepared audit event with the derived count');
select is((select count(*) from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2))::int,1,'RPE G22: exactly one audit event per prepared attempt');
select is(pg_temp.probe($q$insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap) values ('payments',date '2026-02-02',date '2026-02-28',null,1000)$q$),'OK','RPE G23: a zero-match preparation is lawful');
select is((select data_row_count::text from app.report_export_preparations where dataset='payments' and range_from=date '2026-02-02'),'0','RPE G24: the zero-row projection still derives count zero');
select is((select count(*) from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='payments' and range_from=date '2026-02-02') and action='report_export.prepared')::int,1,'RPE G25: the zero-row attempt is audited too');

-- ============ H. the narrow public release writer ============
-- The prepared attempt from G (members, all-branch, cap 2) is the release target.
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$),'OK','RPE H1: a valid release appends with exactly the declared detail keys');
select is((select count(*) from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released')::int,1,'RPE H2: the released audit event exists for the same export UUID');
select is((select record_type from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),'report_export','RPE H3: the record_type is report_export');
select is((select after->>'byte_count' from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),'2048','RPE H4: the release records the byte count as canonical decimal text');
select is((select after->>'artifact_sha256' from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),'abababababababababababababababababababababababababababababababab','RPE H5: the release records the artifact digest');
select is((select after->>'before' is null from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),true,'RPE H6: the released event carries no before image');
select is((select array_agg(k order by k) from jsonb_object_keys(after) k),array['artifact_sha256','branch_id','branch_scope','byte_count','data_row_count','dataset','export_id','format','generated_at_utc','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],'RPE H7: the released after-payload is the prepared stamps plus exactly byte_count and artifact_sha256') from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released';
select is((select actor_user_id from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),pg_temp.u(901),'RPE H8: the release attribution is the caller''s verified subject');
select is((select tenant_id from public.audit_log where record_id=(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2) and action='report_export.released'),pg_temp.u(1),'RPE H9: the release tenant is the caller''s claim tenant');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(871),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$),'42501','RPE H10: a release for an absent prepared attempt refuses');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$),'42501','RPE H11: a foreign owner cannot release another tenant''s attempt');
select pg_temp.claim('gym_owner',21,null,901,1);
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',(select export_id from app.report_export_preparations where dataset='members' and branch_scope='all' and row_cap=2),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$) <> 'OK',true,'RPE H12: an already-released attempt refuses a second release — at most one release per attempt');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.exported',pg_temp.u(872),jsonb_build_object('byte_count','2048'))$q$),'22023','RPE H13: the public event vocabulary is report_export.released only');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(872),jsonb_build_object('dataset','payments'))$q$),'22023','RPE H14: prepared auditing is private — the public writer refuses it');
select is(pg_temp.probe($q$select public.append_report_export_event(null,pg_temp.u(872),jsonb_build_object('byte_count','2048'))$q$),'22023','RPE H15: a null event refuses');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',null,jsonb_build_object('byte_count','2048'))$q$),'22023','RPE H16: a null export id refuses');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),null)$q$),'22023','RPE H17: null release details refuse');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab','notes','extra'))$q$),'23514','RPE H18: detail keys outside the frozen set refuse — no arbitrary payloads');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab','exported_rows',jsonb_build_array(jsonb_build_object('amount_paise','12345'))))$q$),'23514','RPE H19: no exported row content can enter the audit');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','0','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$) in ('23514','22023'),true,'RPE H20: a zero byte count refuses — a released file has bytes');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','8388609','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$) in ('23514','22023'),true,'RPE H21: a byte count above the 8 MiB cap refuses');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count',2048,'artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$) in ('23514','22023'),true,'RPE H22: byte_count must be canonical decimal TEXT, not a JSON number');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','abababab'))$q$) in ('23514','22023'),true,'RPE H23: the digest must be exactly 64 hex characters');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB'))$q$) in ('23514','22023'),true,'RPE H24: the digest must be lowercase hex');
select pg_temp.claim(); -- member
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$),'42501','RPE H25: a member identity releases nothing');
select set_config('request.jwt.claims','',true);
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(872),jsonb_build_object('byte_count','2048','artifact_sha256','abababababababababababababababababababababababababababababababab'))$q$),'42501','RPE H26: anon releases nothing');
select pg_temp.claim('gym_owner',21,null,901,1);
select is((select count(*) from public.audit_log where record_id in (pg_temp.u(871),pg_temp.u(872)))::int,0,'RPE H27: every refused release wrote nothing');

-- ============ I. the surroundings stay untouched ============
select is(pg_temp.probe($q$insert into public.audit_log (tenant_id,action,record_type,record_id) values (pg_temp.u(1),'x.y','z',pg_temp.u(809))$q$),'42501','RPE I1: audit_log stays append-only to triggers/definers — authenticated gets no direct INSERT');
select is((select relrowsecurity from pg_class where oid='public.audit_log'::regclass),true,'RPE I2: audit_log keeps its RLS');
select * from finish();
rollback;
