-- RPE-001..009/013 visible SQL contract for the CSV-first report-export
-- operations (Wave D report exports).
-- Frozen authority: openspec/changes/report-exports/proposal.md (FROZEN
-- 2026-10-03, CSV-first staging; the invoice half is deferred and is pinned
-- NOWHERE here). The caller seam was read to pin exact operation signatures
-- and result shape (apps/web/app/api/report-exports/route.ts); every
-- behavioural expectation comes from the frozen contract, not the caller.
--
-- RED pattern: no mirror DDL (suite 81's pattern). Every catalog assertion is
-- NULL-safe (to_regprocedure) and every dynamic statement runs through a
-- catching executor, so the file runs end-to-end RED before the export
-- operations migration exists (42P01/42883) and judges the real
-- implementation once CI applies it. Nothing commits: one begin/rollback pair.
--
-- Refusal-code assumptions pinned from the frozen contract plus the repo's
-- shared precedence vocabulary: actor/privilege failures 42501 (owner-only
-- actor revalidation BEFORE any target or source read; unknown and foreign
-- branches/ids share one unavailable response); value/shape validation 22023
-- (dataset vocabulary, Gregorian range, from<=through, row cap, event
-- vocabulary, null arguments); invariant violations 23514 (audit details
-- allowlist — no arbitrary payloads, no exported content in audit). If the
-- implementer maps any of these differently, that is a contract-defect
-- round-trip to the test author, not a test edit by the implementer.
--
-- Result-shape assumption (from the caller): export_report_snapshot returns
-- ONE jsonb payload {"rows": [...], "has_more": boolean, "timezone": text};
-- rows carry the frozen dataset columns with money as canonical decimal text.
-- A bare-array return fails the shape pins below (the route treats it as a
-- pre-migration shape; the production contract is the payload).
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(99);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('82000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text default 'member', s integer default null, m integer default null, a integer default 901, t integer default 1, p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(t),'staff_id',case when s is not null then pg_temp.u(s) end,'member_id',case when m is not null then pg_temp.u(m) end,'impersonation_session_id',case when p then pg_temp.u(999) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.val(q text) returns text language plpgsql as $$declare r text; begin execute q into r; return r; exception when others then return sqlstate; end$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.probe(text),pg_temp.val(text) to authenticated,anon,service_role;
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
(pg_temp.u(105),pg_temp.u(2),pg_temp.u(12),'PRIVATE_FOREIGN_105','+918200000105','active',null,'RPE105',date '2026-02-01');
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,receipt_number,paid_at,created_at,recorded_by_staff_id) values
(pg_temp.u(401),pg_temp.u(1),pg_temp.u(101),12345,'INR','paid','upi','RPE-0001',timestamptz '2026-01-10 09:05:00+00',timestamptz '2026-01-10 09:00:00+00',pg_temp.u(21)),
(pg_temp.u(402),pg_temp.u(1),pg_temp.u(102),6789,'INR','created','cash',null,null,timestamptz '2026-01-11 10:00:00+00',pg_temp.u(21)),
(pg_temp.u(403),pg_temp.u(1),pg_temp.u(103),555,'INR','refunded','cash','RPE-0003',timestamptz '2026-01-12 11:00:00+00',timestamptz '2026-01-12 10:30:00+00',pg_temp.u(21)),
(pg_temp.u(404),pg_temp.u(1),pg_temp.u(101),2500,'USD','paid','card',null,timestamptz '2026-01-13 12:00:00+00',timestamptz '2026-01-13 11:45:00+00',null);
insert into public.attendance(id,tenant_id,branch_id,member_id,source,checked_in_at,checked_out_at,offline_recorded_at,replayed_at) values
(pg_temp.u(421),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),'qr',timestamptz '2026-01-05 02:00:00+00',null,null,null),
(pg_temp.u(422),pg_temp.u(1),pg_temp.u(13),pg_temp.u(102),'front_desk',timestamptz '2026-01-01 02:00:00+00',null,null,null),
(pg_temp.u(423),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),'front_desk',timestamptz '2026-01-05 03:00:00+00',timestamptz '2026-01-05 04:00:00+00',timestamptz '2026-01-05 02:30:00+00',timestamptz '2026-01-05 03:05:00+00'),
(pg_temp.u(424),pg_temp.u(2),pg_temp.u(12),pg_temp.u(105),'qr',timestamptz '2026-01-20 02:00:00+00',null,null,null);

-- ============ A. catalog shapes, labels, security labels, grants ============
-- export_report_snapshot: the one bounded invoker data operation per artifact.
select is(to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') is not null, true,'RPE A1: export_report_snapshot(text,date,date,uuid,integer) exists');
select is((select array_to_string(proargtypes::regtype[]::text[],',') from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'text,date,date,uuid,integer','RPE A2: exact argument types');
select is((select array_to_string(proargnames,',') from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'p_dataset,p_from,p_through,p_branch_id,p_row_cap','RPE A3: exact argument names (PostgREST named-arg calling)');
select is((select prosecdef from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),false,'RPE A4: invoker — caller RLS is the read boundary');
select is((select proname from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') and pg_get_userbyid(proowner)='postgres'),'export_report_snapshot','RPE A5: postgres-owned');
select ok((select coalesce(proconfig @> array['search_path=""'],false) from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'RPE A6: empty search path');
select is((select provolatile in ('v','s') from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),true,'RPE A7: stable or volatile, never immutable');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'jsonb','RPE A8: returns jsonb (payload with rows/has_more/timezone)');
select is(has_function_privilege('anon','public.export_report_snapshot(text,date,date,uuid,integer)','execute'),false,'RPE A9: anon holds no EXECUTE');
select is(has_function_privilege('service_role','public.export_report_snapshot(text,date,date,uuid,integer)','execute'),false,'RPE A10: service_role holds no EXECUTE');
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
select is(has_function_privilege(current_user,'public.export_report_snapshot(text,date,date,uuid,integer)','execute'),true,'RPE A11: authenticated granted EXECUTE');
set local role postgres;
select set_config('request.jwt.claims','',true);
-- append_report_export_event: the ONLY elevation is audit append.
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
select pg_temp.claim('front_desk',22,null,902,1);
select is(pg_temp.probe($q$select public.export_report_snapshot('nonsense','2026-13-01',date '2026-01-31',null,100)$q$),'42501','RPE B17: authorization precedes validation — a refused role learns no validation facts');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'OK','RPE B18: tenant 2 owner reads (their own, empty) — the invalid-zone refusal is a separate case');
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
select is(pg_temp.probe($q$select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,100)$q$),'22023','RPE B19: an invalid configured gym zone refuses explicitly, never a fabricated fallback zone');
set local role postgres;
select set_config('request.jwt.claims','',true);

update public.organizations set timezone='Asia/Kolkata' where id=pg_temp.u(3);

-- ============ C. payments dataset: projection, money text, ordering, blanks ============
set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);
insert into res(k,v) values ('pay',(select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,1000)));
select is(jsonb_typeof(v->'rows'),'array','RPE C1: rows is a JSON array in one payload') from res where k='pay';
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,4,'RPE C2: every in-range payment row once (attempts and terminal states included)') from res where k='pay';
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['amount_display','amount_paise','created_at_utc','currency','current_member_name','member_code','member_id','method','paid_at_utc','payment_id','receipt_number','status']::text[],'RPE C3: exact payments projection (frozen column list)') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(jsonb_typeof(r->'amount_paise'),'string','RPE C4: amount_paise crosses as canonical decimal TEXT') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'amount_paise','12345','RPE C5: exact paise value — no float anywhere') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'amount_display' like '%123.45',true,'RPE C6: amount_display is the presentation text of the same paise') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'paid_at_utc',null::jsonb,'RPE C7: a null paid time stays null — never inferred') from (select (v->'rows'->>1)::jsonb r from res where k='pay') s;
select is(r->>'created_at_utc' like '%Z',true,'RPE C8: created_at_utc is an ISO-8601 UTC instant') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'payment_id',pg_temp.u(401)::text,'RPE C9: ordering by (created_at,id) — earliest first') from (select (v->'rows'->>0)::jsonb r from res where k='pay') s;
select is(r->>'current_member_name',null::jsonb,'RPE C10: an erased member''s name is blank, row survives') from (select (v->'rows'->>2)::jsonb r from res where k='pay') s;
select is(r->>'member_code',null::jsonb,'RPE C11: an erased member''s code is blank') from (select (v->'rows'->>2)::jsonb r from res where k='pay') s;
select is(r->>'member_id',pg_temp.u(103)::text,'RPE C12: the payment''s own member reference is kept (financial evidence, not an Auth id)') from (select (v->'rows'->>2)::jsonb r from res where k='pay') s;
select is(r->>'currency','USD','RPE C13: cross-currency rows keep their own currency — never converted or summed') from (select (v->'rows'->>3)::jsonb r from res where k='pay') s;
select is(r->>'status','refunded','RPE C14: canonical generated-enum status words') from (select (v->'rows'->>2)::jsonb r from res where k='pay') s;
delete from res where k='pay';

-- ============ D. attendance dataset: stored branch, branch-zone local stamps ============
insert into res(k,v) values ('att',(select public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',null,1000)));
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['attendance_id','branch_id','checked_in_at_utc','checked_in_local','checked_out_at_utc','current_member_name','member_code','member_id','offline_recorded_at_utc','replayed_at_utc','source']::text[],'RPE D1: exact attendance projection (recorded events, not bookings or inferred presence)') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,3,'RPE D2: tenant rows only, one per accepted visit') from res where k='att';
select is(r->>'checked_in_local' like '2025-12-31%',true,'RPE D3: the branch''s own zone dates the visit (America/New_York branch)') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is(r->>'checked_in_local' like '%-05:00%',true,'RPE D4: the local stamp carries its UTC offset') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
select is(r->>'checked_in_local' like '2026-01-05%',true,'RPE D5: a null branch zone inherits the gym zone (Kolkata)') from (select (v->'rows'->>1)::jsonb r from res where k='att') s;
select is(r->>'checked_out_at_utc' is not null,true,'RPE D6: optional check-out kept when recorded') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'offline_recorded_at_utc' is not null,true,'RPE D7: offline provenance stamp kept') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'replayed_at_utc' is not null,true,'RPE D8: replay stamp kept (ATT-007 evidence)') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'source','front_desk','RPE D9: canonical attendance source') from (select (v->'rows'->>2)::jsonb r from res where k='att') s;
select is(r->>'attendance_id',pg_temp.u(422)::text,'RPE D10: ordering by (checked_in_at,id) — earliest first') from (select (v->'rows'->>0)::jsonb r from res where k='att') s;
delete from res where k='att';
select is(pg_temp.val($q$select coalesce(jsonb_array_length(public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',pg_temp.u(13),1000)->'rows'),-1)$q$)::int,1,'RPE D11: the branch filter uses the stored branch');
select pg_temp.claim('gym_owner',25,null,905,2);
select is(pg_temp.val($q$select jsonb_array_length(public.export_report_snapshot('attendance',date '2026-01-01',date '2026-01-31',null,1000)->'rows')$q$)::int,1,'RPE D12: tenant 2 reads only its own visit — cross-tenant rows never enter');
select pg_temp.claim('gym_owner',21,null,901,1);

-- ============ E. members dataset: joining cohort of non-erased members ============
insert into res(k,v) values ('mem',(select public.export_report_snapshot('members',date '2026-01-01',date '2026-01-31',null,1000)));
select is((select array_agg(k order by k) from jsonb_object_keys(r) k),array['branch_id','email','full_name','joined_on','member_code','member_id','phone','status']::text[],'RPE E1: exact members projection (no DOB, guardian, notes, consent or account ids)') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is((select count(*) from jsonb_array_elements(v->'rows'))::int,2,'RPE E2: the joining cohort counts current non-erased members only') from res where k='mem';
select is((select count(*) from jsonb_array_elements(v->'rows') r where r->>'member_id'=pg_temp.u(103)::text)::int,0,'RPE E3: an erased member never appears in the roster');
select is(r->>'member_id',pg_temp.u(101)::text,'RPE E4: ordering by (joined_on,id) — earliest joined first') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is(r->>'phone','+918200000101','RPE E5: contact facts cross as stored text') from (select (v->'rows'->>0)::jsonb r from res where k='mem') s;
select is(r->>'branch_id',pg_temp.u(13)::text,'RPE E6: the member''s current branch (not a payment/visit branch)') from (select (v->'rows'->>1)::jsonb r from res where k='mem') s;
delete from res where k='mem';

-- ============ F. payload shape, cap+1, gym zone ============
insert into res(k,v) values ('cap',(select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,2)));
select is((select array_agg(k order by k) from jsonb_object_keys(v) k),array['has_more','rows','timezone']::text[],'RPE F1: the payload carries rows, has_more and the validated zone') from res where k='cap';
select is(jsonb_array_length(v->'rows'),2,'RPE F2: at most p_row_cap rows return') from res where k='cap';
select is((v->>'has_more')::boolean,true,'RPE F3: a full page discloses more exist (the caller probes cap+1)') from res where k='cap';
delete from res where k='cap';
insert into res(k,v) values ('cap4',(select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',null,4)));
select is((v->>'has_more')::boolean,false,'RPE F4: an exhausted read says so — no phantom continuation') from res where k='cap4';
select is(v->>'timezone','Asia/Kolkata','RPE F5: the validated gym zone is disclosed in the payload') from res where k='cap4';
delete from res where k='cap4';
insert into res(k,v) values ('nb',(select public.export_report_snapshot('payments',date '2026-01-01',date '2026-01-31',pg_temp.u(82999999),100)));
select is(jsonb_array_length(v->'rows'),0,'RPE F6: an unknown/foreign branch reads as an empty scope — never another gym''s rows') from res where k='nb';
select is((v->>'has_more')::boolean,false,'RPE F7: the empty branch scope is a complete result') from res where k='nb';
delete from res where k='nb';

-- ============ G. the narrow audit append (the only elevation) ============
select pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(801),jsonb_build_object('tenant_id',pg_temp.u(1),'actor_user_id',pg_temp.u(901),'actor_role','gym_owner','dataset','payments','range_from','2026-01-01','range_through','2026-01-31','range_basis','created_at','timezone','Asia/Kolkata','branch_scope','whole_gym','row_count',4))$q$);
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(801),jsonb_build_object('tenant_id',pg_temp.u(1),'actor_user_id',pg_temp.u(901),'actor_role','gym_owner','dataset','payments','range_from','2026-01-01','range_through','2026-01-31','range_basis','created_at','timezone','Asia/Kolkata','branch_scope','whole_gym','row_count',4))$q$),'OK','RPE G1: a prepared event with the frozen detail shape appends');
select is((select count(*) from public.audit_log where record_id=pg_temp.u(801))::int,1,'RPE G2: exactly one audit row per event');
select is((select action from public.audit_log where record_id=pg_temp.u(801)),'report_export.prepared','RPE G3: the action follows <record_type>.<verb> and names the export');
select is((select record_type from public.audit_log where record_id=pg_temp.u(801)),'report_export','RPE G4: record_type is report_export');
select is((select actor_user_id from public.audit_log where record_id=pg_temp.u(801)),pg_temp.u(901),'RPE G5: the audit actor is the CALLER''S verified subject');
select is((select actor_role::text from public.audit_log where record_id=pg_temp.u(801)),'gym_owner','RPE G6: the audit role is the caller''s claim role');
select is((select tenant_id from public.audit_log where record_id=pg_temp.u(801)),pg_temp.u(1),'RPE G7: the audit tenant is the caller''s claim tenant');
select pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(802),jsonb_build_object('tenant_id',pg_temp.u(1),'actor_user_id',pg_temp.u(905),'actor_role','gym_owner','dataset','payments','range_from','2026-01-01','range_through','2026-01-31','range_basis','created_at','timezone','Asia/Kolkata','branch_scope','whole_gym','row_count',4))$q$);
select is((select actor_user_id from public.audit_log where record_id=pg_temp.u(802)),pg_temp.u(901),'RPE G8: a spoofed actor inside the details never attributes the audit row — claims only');
select pg_temp.probe($q$select public.append_report_export_event('report_export.released',pg_temp.u(801),jsonb_build_object('tenant_id',pg_temp.u(1),'actor_user_id',pg_temp.u(901),'actor_role','gym_owner','dataset','payments','range_from','2026-01-01','range_through','2026-01-31','range_basis','created_at','timezone','Asia/Kolkata','branch_scope','whole_gym','row_count',4,'byte_count',2048,'artifact_sha256','a3f1'))$q$);
select is((select after->>'artifact_sha256' from public.audit_log where record_id=pg_temp.u(801) and action='report_export.released'),'a3f1','RPE G9: the released event records the artifact digest with the same export uuid');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.foo',pg_temp.u(803),jsonb_build_object('dataset','payments'))$q$),'22023','RPE G10: the event vocabulary is prepared|released only');
select is(pg_temp.probe($q$select public.append_report_export_event(null,pg_temp.u(803),jsonb_build_object('dataset','payments'))$q$),'22023','RPE G11: a null event refuses');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',null,jsonb_build_object('dataset','payments'))$q$),'22023','RPE G12: a null export id refuses');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(803),null)$q$),'22023','RPE G13: null details refuse');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(803),jsonb_build_object('dataset','payments','notes','extra'))$q$),'23514','RPE G14: detail keys outside the frozen set refuse — no arbitrary payloads');
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(803),jsonb_build_object('dataset','payments','exported_rows',jsonb_build_array(jsonb_build_object('amount_paise','12345'))))$q$),'23514','RPE G15: no exported row content can enter the audit');
select pg_temp.claim(); -- member, no staff
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(803),jsonb_build_object('dataset','payments'))$q$),'42501','RPE G16: a member identity appends nothing');
select set_config('request.jwt.claims','',true);
select is(pg_temp.probe($q$select public.append_report_export_event('report_export.prepared',pg_temp.u(803),jsonb_build_object('dataset','payments'))$q$),'42501','RPE G17: anon appends nothing');
select is((select count(*) from public.audit_log where record_id in (pg_temp.u(801),pg_temp.u(802),pg_temp.u(803)))::int,3,'RPE G18: refused calls wrote nothing — prepared, spoof-checked prepared, released');
select pg_temp.claim('gym_owner',21,null,901,1);

-- ============ H. the surroundings stay untouched ============
select is(pg_temp.probe($q$insert into public.audit_log (tenant_id,action,record_type,record_id) values (pg_temp.u(1),'x.y','z',pg_temp.u(809))$q$),'42501','RPE H1: audit_log stays append-only to triggers/definers — authenticated gets no direct INSERT');
select is((select relrowsecurity from pg_class where oid='public.audit_log'::regclass),true,'RPE H2: audit_log keeps its RLS');
select * from finish();
rollback;
