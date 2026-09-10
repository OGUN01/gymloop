-- Phase 6 visible database contract: the /leads list snapshot. Derived only
-- from the frozen LEAD-001..LEAD-005 / GL059..GL062 contract in
-- docs/planning/phase6-leads-contract.md and the phase6 leads spec. The
-- implementation and supabase/tests-holdout were not read. Every fixture rolls
-- back. The suite is red until public.list_leads and the leads revision column
-- exist.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(37);

-- ---------------------------------------------------------------------------
-- Fixtures. Eight gym-A leads cover every canonical stage, both assignee
-- shapes, two branches, and a same-updated_at pair whose id order must break
-- the tie. Gym B owns exactly one lead.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('59000000-0000-4000-8000-000000000001','Leads List A','LEL59A','active','Asia/Kolkata','INR'),
 ('59000000-0000-4000-8000-000000000002','Leads List B','LEL59B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('59000000-0000-4000-8000-000000000011','59000000-0000-4000-8000-000000000001','Main A',true),
 ('59000000-0000-4000-8000-000000000013','59000000-0000-4000-8000-000000000001','Annex A',false),
 ('59000000-0000-4000-8000-000000000012','59000000-0000-4000-8000-000000000002','Main B',true);
insert into auth.users(id) values
 ('59000000-0000-4000-8000-000000000901'),('59000000-0000-4000-8000-000000000903'),
 ('59000000-0000-4000-8000-000000000904'),('59000000-0000-4000-8000-000000000905'),
 ('59000000-0000-4000-8000-000000000907'),('59000000-0000-4000-8000-000000000909'),
 ('59000000-0000-4000-8000-00000000090a');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('59000000-0000-4000-8000-000000000909','platform_support','Support Probe','support@example.test',true),
 ('59000000-0000-4000-8000-00000000090a','super_admin','Super Probe','super@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('59000000-0000-4000-8000-000000000021','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000901','59000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('59000000-0000-4000-8000-000000000023','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000903','59000000-0000-4000-8000-000000000011','front_desk','Desk A1',true),
 ('59000000-0000-4000-8000-000000000024','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000904','59000000-0000-4000-8000-000000000011','front_desk','Desk A2',true),
 ('59000000-0000-4000-8000-000000000025','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000905','59000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('59000000-0000-4000-8000-000000000027','59000000-0000-4000-8000-000000000002','59000000-0000-4000-8000-000000000907','59000000-0000-4000-8000-000000000012','front_desk','Desk B',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,erased_at) values
 ('59000000-0000-4000-8000-000000000031','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Converted Member','+915900000031','active',null);

set local session_replication_role = replica;
insert into public.leads(id,tenant_id,branch_id,full_name,phone,email,source,stage,assigned_to_staff_id,trial_at,converted_member_id,converted_at,lost_reason,notes,created_at,updated_at) values
 ('59000000-0000-4000-8000-000000000601','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Alpha One','+915900000601','alpha@example.com','walk_in','new','59000000-0000-4000-8000-000000000023',null,null,null,null,null,'2026-09-01T10:00:00+00','2026-09-06T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000602','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Beta Two','+915900000602',null,'referral','contacted','59000000-0000-4000-8000-000000000024',null,null,null,null,null,'2026-09-01T10:00:00+00','2026-09-05T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000603','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Gamma Three','+915900000603',null,'instagram','trial_scheduled',null,'2026-09-20T04:30:00+00',null,null,null,null,'2026-09-01T10:00:00+00','2026-09-04T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000604','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Tie High','+915900000604',null,'google','trial_done','59000000-0000-4000-8000-000000000023','2026-09-19T04:30:00+00',null,null,null,null,'2026-09-01T10:00:00+00','2026-09-03T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000605','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Tie Low','+915900000605',null,'website','trial_done',null,'2026-09-19T04:30:00+00',null,null,null,null,'2026-09-01T10:00:00+00','2026-09-03T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000606','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Delta Six','+915900000606',null,'phone','converted','59000000-0000-4000-8000-000000000024','2026-09-18T04:30:00+00','59000000-0000-4000-8000-000000000031','2026-09-02T10:00:00+00',null,null,'2026-09-01T10:00:00+00','2026-09-02T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000607','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000011','Epsilon Seven','+915900000607',null,'other','lost',null,null,null,null,'Chose a rival gym',null,'2026-09-01T10:00:00+00','2026-09-01T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000608','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000013','Zeta Eight','+915900000608',null,'walk_in','new','59000000-0000-4000-8000-000000000023',null,null,null,null,null,'2026-08-30T10:00:00+00','2026-08-31T10:00:00+00'),
 ('59000000-0000-4000-8000-000000000651','59000000-0000-4000-8000-000000000002','59000000-0000-4000-8000-000000000012','Zoya Farooqui','+915900000651',null,'walk_in','trial_done',null,'2026-09-19T04:30:00+00',null,null,null,null,'2026-09-01T10:00:00+00','2026-09-03T10:00:00+00');
set local session_replication_role = default;

create temp table lead_fix(label text, id uuid, revision uuid);
insert into lead_fix
select v.label, l.id, l.revision
from (values
 ('l1','59000000-0000-4000-8000-000000000601'::uuid),('l2','59000000-0000-4000-8000-000000000602'::uuid),
 ('l3','59000000-0000-4000-8000-000000000603'::uuid),('tie1','59000000-0000-4000-8000-000000000604'::uuid),
 ('tie2','59000000-0000-4000-8000-000000000605'::uuid),('l6','59000000-0000-4000-8000-000000000606'::uuid),
 ('l7','59000000-0000-4000-8000-000000000607'::uuid),('l8','59000000-0000-4000-8000-000000000608'::uuid),
 ('lb','59000000-0000-4000-8000-000000000651'::uuid)) v(label,id)
join public.leads l on l.id=v.id;
grant select on lead_fix to authenticated;

create temp table lp(label text, result jsonb);
grant select,insert on lp to authenticated;

-- ---------------------------------------------------------------------------
-- The exact STABLE invoker signature and its execute grant.
-- ---------------------------------------------------------------------------

select is(to_regprocedure('public.list_leads(public.lead_stage,public.lead_source,text,uuid,text,timestamptz,uuid,integer)'),'public.list_leads(public.lead_stage,public.lead_source,text,uuid,text,timestamptz,uuid,integer)'::regprocedure,'list_leads exists with the exact eight-argument contract signature');
select results_eq($$select p.pronargs, p.prorettype='jsonb'::regtype, p.provolatile, p.prosecdef, p.proretset, coalesce(p.proconfig,'{}') @> array['search_path=""'] from pg_proc p where p.oid=to_regprocedure('public.list_leads(public.lead_stage,public.lead_source,text,uuid,text,timestamptz,uuid,integer)')$$,$$select 8, true, 's', false, false, true$$,'list_leads is a non-set-returning STABLE SECURITY INVOKER jsonb RPC with a pinned search_path');
select results_eq($$select ro, has_function_privilege(ro,'public.list_leads(public.lead_stage,public.lead_source,text,uuid,text,timestamptz,uuid,integer)','execute') from (values ('authenticated'),('anon'),('service_role')) v(ro) order by ro$$,$$values ('anon'::text,false),('authenticated'::text,true),('service_role'::text,false)$$,'only authenticated may execute list_leads');

-- ---------------------------------------------------------------------------
-- One unfiltered snapshot: shape, order, row keys and exact counts.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"59000000-0000-4000-8000-000000000001","staff_id":"59000000-0000-4000-8000-000000000023"}',true);

insert into lp select 'all', public.list_leads(null,null,null,null,null,null,null,50);
insert into lp select 'page1', public.list_leads(null,null,null,null,null,null,null,3);
insert into lp select 'page2', public.list_leads(null,null,null,null,null,'2026-09-04 10:00:00+00'::timestamptz,'59000000-0000-4000-8000-000000000603'::uuid,3);
insert into lp select 'page3', public.list_leads(null,null,null,null,null,'2026-09-02 10:00:00+00'::timestamptz,'59000000-0000-4000-8000-000000000606'::uuid,3);
insert into lp select 'stage-td', public.list_leads('trial_done',null,null,null,null,null,null,50);
insert into lp select 'source-wi', public.list_leads(null,'walk_in',null,null,null,null,null,50);
insert into lp select 'assignee-a1', public.list_leads(null,null,'59000000-0000-4000-8000-000000000023',null,null,null,null,50);
insert into lp select 'assignee-un', public.list_leads(null,null,'unassigned',null,null,null,null,50);
insert into lp select 'branch-annex', public.list_leads(null,null,null,'59000000-0000-4000-8000-000000000013',null,null,null,50);
insert into lp select 'q-name', public.list_leads(null,null,null,null,'Alpha',null,null,50);
insert into lp select 'q-phone', public.list_leads(null,null,null,null,'+915900000602',null,null,50);
insert into lp select 'empty-q', public.list_leads(null,null,null,null,'',null,null,50);

select results_eq($$select (select string_agg(k,',' order by k) from jsonb_object_keys(result) k) from lp where label='all'$$,$$select 'asOf,filteredStageCounts,nextAfter,pageResultCount,rows,totalMatchingCount'::text$$,'the list result carries exactly the six contracted keys');
select results_eq($$select string_agg(r->>'id',' ' order by ord) from lp, jsonb_array_elements(result->'rows') with ordinality as x(r,ord) where label='all'$$,$$select '59000000-0000-4000-8000-000000000601 59000000-0000-4000-8000-000000000602 59000000-0000-4000-8000-000000000603 59000000-0000-4000-8000-000000000605 59000000-0000-4000-8000-000000000604 59000000-0000-4000-8000-000000000606 59000000-0000-4000-8000-000000000607 59000000-0000-4000-8000-000000000608'::text$$,'rows sort by updated_at desc then id desc with the equal-timestamp tie broken by id desc');
select ok((select result->>'asOf' from lp where label='all') is not null,'asOf carries the statement timestamp of the snapshot');
select results_eq($$select (select string_agg(k,',' order by k) from jsonb_object_keys(result->'rows'->0) k) from lp where label='all'$$,$$select 'assignedToName,assignedToStaffId,branchId,branchName,convertedMemberId,fullName,id,lostReason,phone,revision,source,stage,trialAt,updatedAt'::text$$,'each LeadListRow carries exactly the fourteen contracted keys');
select results_eq($$select r->>'id', r->>'fullName', r->>'phone', r->>'source', r->>'stage', r->>'assignedToStaffId', r->>'assignedToName', r->>'branchId', r->>'branchName', r->>'trialAt', r->>'convertedMemberId', r->>'lostReason', (r->>'updatedAt')::timestamptz='2026-09-06 10:00:00+00'::timestamptz, (r->>'revision')::uuid=(select revision from lead_fix where label='l1') from lp, jsonb_array_elements(result->'rows') x(r) where label='all' and r->>'id'='59000000-0000-4000-8000-000000000601'$$,$$select '59000000-0000-4000-8000-000000000601','Alpha One','+915900000601','walk_in','new','59000000-0000-4000-8000-000000000023','Desk A1','59000000-0000-4000-8000-000000000011','Main A',null,null,null,true,true$$,'a row carries its lead facts with branch and assignee names resolved');
select ok((select bool_and(k ~ '^[0-9]+$') from (select result->>'pageResultCount' k from lp where label='all' union all select result->>'totalMatchingCount' from lp where label='all' union all select v.value #>> '{}' from lp, jsonb_each(result->'filteredStageCounts') v where label='all') s),'every count is a decimal integer string');
select results_eq($$select (select string_agg(k,',' order by k) from jsonb_object_keys(result->'filteredStageCounts') k) from lp where label='all'$$,$$select 'contacted,converted,lost,new,trial_done,trial_scheduled'::text$$,'filteredStageCounts carries every canonical stage key');
select results_eq($$select result->>'pageResultCount', result->>'totalMatchingCount', result->'filteredStageCounts'->>'new', result->'filteredStageCounts'->>'contacted', result->'filteredStageCounts'->>'trial_scheduled', result->'filteredStageCounts'->>'trial_done', result->'filteredStageCounts'->>'converted', result->'filteredStageCounts'->>'lost' from lp where label='all'$$,$$select '8','8','2','1','1','2','1','1'$$,'the unfiltered snapshot counts the whole population');
select is((select result->'nextAfter' from lp where label='all'),'null'::jsonb,'nextAfter is null once the page exhausts the population');

-- ---------------------------------------------------------------------------
-- Keyset pages: the cursor is the last row key, totals ignore the cursor.
-- ---------------------------------------------------------------------------

select results_eq($$select result->>'pageResultCount', result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->2->>'id', jsonb_array_length(result->'rows') from lp where label='page1'$$,$$select '3','8','59000000-0000-4000-8000-000000000601','59000000-0000-4000-8000-000000000603',3$$,'the first page returns three rows and keeps the pre-cursor total');
select results_eq($$select (select count(*) from jsonb_object_keys(result->'nextAfter')), result->'nextAfter'->>'id', (result->'nextAfter'->>'updatedAt')::timestamptz from lp where label='page1'$$,$$select 2::bigint,'59000000-0000-4000-8000-000000000603','2026-09-04 10:00:00+00'::timestamptz$$,'nextAfter carries exactly the last row id and updatedAt');
select results_eq($$select result->>'pageResultCount', result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->1->>'id', result->'rows'->2->>'id' from lp where label='page2'$$,$$select '3','8','59000000-0000-4000-8000-000000000605','59000000-0000-4000-8000-000000000604','59000000-0000-4000-8000-000000000606'$$,'page two resumes at the cursor with the tie broken by id desc');
select results_eq($$select result->'nextAfter'->>'id', (result->'nextAfter'->>'updatedAt')::timestamptz from lp where label='page2'$$,$$select '59000000-0000-4000-8000-000000000606','2026-09-02 10:00:00+00'::timestamptz$$,'page two ends at the sixth row key');
select results_eq($$select result->>'pageResultCount', result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->1->>'id', result->'nextAfter' from lp where label='page3'$$,$$select '2','8','59000000-0000-4000-8000-000000000607','59000000-0000-4000-8000-000000000608','null'::jsonb$$,'the final page returns the tail, keeps the total and reports exhaustion');

-- ---------------------------------------------------------------------------
-- Filters: stage, source, assignee, branch, query.
-- ---------------------------------------------------------------------------

select results_eq($$select result->>'pageResultCount', result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->1->>'id', result->'filteredStageCounts'->>'trial_done', result->'filteredStageCounts'->>'new', result->'filteredStageCounts'->>'converted' from lp where label='stage-td'$$,$$select '2','2','59000000-0000-4000-8000-000000000605','59000000-0000-4000-8000-000000000604','2','0','0'$$,'a stage filter matches the population and zeroes every other bucket');
select results_eq($$select result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->1->>'id' from lp where label='source-wi'$$,$$select '2','59000000-0000-4000-8000-000000000601','59000000-0000-4000-8000-000000000608'$$,'a source filter narrows to the walk-in leads');
select results_eq($$select result->>'totalMatchingCount', (select string_agg(r->>'id',',' order by ord) from jsonb_array_elements(result->'rows') with ordinality as x(r,ord)) from lp where label='assignee-a1'$$,$$select '3','59000000-0000-4000-8000-000000000601,59000000-0000-4000-8000-000000000604,59000000-0000-4000-8000-000000000608'$$,'an assignee UUID filter lists only that desk leads');
select results_eq($$select result->>'totalMatchingCount', (select string_agg(r->>'id',',' order by ord) from jsonb_array_elements(result->'rows') with ordinality as x(r,ord)) from lp where label='assignee-un'$$,$$select '3','59000000-0000-4000-8000-000000000603,59000000-0000-4000-8000-000000000605,59000000-0000-4000-8000-000000000607'$$,'the unassigned filter lists only leads with no assignee');
select results_eq($$select result->>'totalMatchingCount', result->'rows'->0->>'id', result->'rows'->0->>'branchName' from lp where label='branch-annex'$$,$$select '1','59000000-0000-4000-8000-000000000608','Annex A'$$,'a branch filter lists only the annex leads');
select results_eq($$select result->>'totalMatchingCount', result->'rows'->0->>'id' from lp where label='q-name'$$,$$select '1','59000000-0000-4000-8000-000000000601'$$,'a query matches the lead name');
select results_eq($$select result->>'totalMatchingCount', result->'rows'->0->>'id' from lp where label='q-phone'$$,$$select '1','59000000-0000-4000-8000-000000000602'$$,'a query matches the lead phone');
select results_eq($$select result->>'totalMatchingCount', jsonb_array_length(result->'rows'), result->'nextAfter' from lp where label='empty-q'$$,$$select '8',8,'null'::jsonb$$,'an empty query behaves exactly like no query');

-- ---------------------------------------------------------------------------
-- Invalid inputs.
-- ---------------------------------------------------------------------------

select throws_ok($$select public.list_leads(null,null,'not-a-uuid',null,null,null,null,null)$$,'GL060',null,'an assignee that is neither unassigned nor a UUID is GL060');
select throws_ok($$select public.list_leads(null,null,null,null,null,'2026-09-04 10:00:00+00'::timestamptz,null,3)$$,null,'a cursor must supply both its updated_at and id parts');
select throws_ok($$select public.list_leads(null,null,null,null,null,null,'59000000-0000-4000-8000-000000000603'::uuid,3)$$,null,'a cursor must supply both its updated_at and id parts');

-- ---------------------------------------------------------------------------
-- Tenant isolation and role gates.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"front_desk","tenant_id":"59000000-0000-4000-8000-000000000002","staff_id":"59000000-0000-4000-8000-000000000027"}',true);
insert into lp select 'gym-b', public.list_leads(null,null,null,null,null,null,null,50);
select results_eq($$select result->>'totalMatchingCount', jsonb_array_length(result->'rows'), result->'rows'->0->>'id', result->'rows'->0->>'fullName' from lp where label='gym-b'$$,$$select '1',1,'59000000-0000-4000-8000-000000000651','Zoya Farooqui'$$,'RLS keeps gym B to its own single lead');

select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"59000000-0000-4000-8000-000000000001","staff_id":"59000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'a trainer cannot read the lead list');
select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"member","tenant_id":"59000000-0000-4000-8000-000000000001","member_id":"59000000-0000-4000-8000-000000000031"}',true);
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'a member cannot read the lead list');
select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"59000000-0000-4000-8000-000000000001","staff_id":"59000000-0000-4000-8000-000000000021","impersonation_session_id":"59000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'a preview identity cannot read the lead list');
select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"platform_support"}',true);
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'platform support cannot read the lead list through the gym RPC');
select results_eq($$select count(*) from public.leads$$,$$select 9$$,'platform support keeps its cross-gym lead read under RLS');
select set_config('request.jwt.claims','{"sub":"59000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'super admin cannot read the lead list through the gym RPC');
select results_eq($$select count(*) from public.leads$$,$$select 9$$,'super admin keeps its existing direct lead authority');
set local role anon;
select throws_ok($$select public.list_leads(null,null,null,null,null,null,null,null)$$,'42501',null,'an anonymous caller cannot read the lead list');

select * from finish();

rollback;
