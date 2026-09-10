-- Phase 6 visible database contract: enquiry stage graph, durable evidence, CAS
-- and role gates. Derived only from the frozen LEAD-001..LEAD-005 / GL059..GL062
-- contract in docs/planning/phase6-leads-contract.md and the phase6 leads spec.
-- The implementation and supabase/tests-holdout were not read. Every fixture
-- rolls back. Concurrency is proved by the exact lock/unique/evidence mechanisms
-- and serial replay; the runner cannot open a second database connection.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(128);

-- ---------------------------------------------------------------------------
-- Exact schema, evidence columns and callable boundaries.
-- ---------------------------------------------------------------------------

select has_column('public','leads','created_by_staff_id','leads attribute the real creating staff member');
select has_column('public','leads','creation_request_key','leads store the creation request key');
select has_column('public','leads','creation_request_facts','leads freeze normalized creation evidence');
select has_column('public','leads','conversion_request_key','leads store the conversion request key');
select has_column('public','leads','conversion_request_facts','leads freeze normalized conversion evidence');
select has_column('public','leads','revision','leads carry a database-owned revision uuid');
select results_eq($$select column_name::text collate "default",data_type::text collate "default",is_nullable::text collate "default" from information_schema.columns where table_schema='public' and table_name='leads' and column_name in ('created_by_staff_id','creation_request_facts','creation_request_key','conversion_request_facts','conversion_request_key','revision') order by column_name$$,$$values ('conversion_request_facts'::text collate "default",'jsonb'::text collate "default",'YES'::text collate "default"),('conversion_request_key'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default"),('created_by_staff_id'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default"),('creation_request_facts'::text collate "default",'jsonb'::text collate "default",'YES'::text collate "default"),('creation_request_key'::text collate "default",'uuid'::text collate "default",'YES'::text collate "default"),('revision'::text collate "default",'uuid'::text collate "default",'NO'::text collate "default")$$,'evidence columns are nullable history and revision is a nonnull uuid');
select ok((select conkey=(select array_agg(attnum order by ord) from unnest(array[(select attnum from pg_attribute where attrelid='public.leads'::regclass and attname='tenant_id'),(select attnum from pg_attribute where attrelid='public.leads'::regclass and attname='created_by_staff_id')]) with ordinality x(attnum,ord)) and confkey=(select array_agg(attnum order by ord) from unnest(array[(select attnum from pg_attribute where attrelid='public.staff'::regclass and attname='tenant_id'),(select attnum from pg_attribute where attrelid='public.staff'::regclass and attname='id')]) with ordinality x(attnum,ord)) from pg_constraint where conrelid='public.leads'::regclass and conname='leads_tenant_id_created_by_staff_id_fkey'),'creator foreign key is tenant-composite');
select ok(to_regclass('public.leads_created_by_staff_id_idx') is not null,'creator foreign key is indexed');
select ok(exists(select 1 from pg_index i join pg_class c on c.oid=i.indexrelid join pg_class t on t.oid=i.indrelid where t.relname='leads' and i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, creation_request_key)%' and pg_get_expr(i.indpred,i.indrelid)='(creation_request_key IS NOT NULL)'),'creation request key uniqueness is tenant-scoped and partial');
select ok(exists(select 1 from pg_index i join pg_class c on c.oid=i.indexrelid join pg_class t on t.oid=i.indrelid where t.relname='leads' and i.indisunique and pg_get_indexdef(i.indexrelid) like '%(tenant_id, conversion_request_key)%' and pg_get_expr(i.indpred,i.indrelid)='(conversion_request_key IS NOT NULL)'),'conversion request key uniqueness is tenant-scoped and partial');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=8 from pg_proc where oid=to_regprocedure('public.create_lead(uuid,uuid,text,text,text,public.lead_source,uuid,text)')),'create_lead is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=9 from pg_proc where oid=to_regprocedure('public.update_lead(uuid,uuid,uuid,text,text,text,public.lead_source,uuid,text)')),'update_lead is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=5 from pg_proc where oid=to_regprocedure('public.transition_lead(uuid,uuid,public.lead_stage,timestamptz,text)')),'transition_lead is the exact volatile invoker command');
select ok((select not prosecdef and provolatile='v' and proconfig @> array['search_path=""'] and not proretset and prorettype='jsonb'::regtype and pronargs=5 from pg_proc where oid=to_regprocedure('public.convert_lead(uuid,uuid,uuid,text,uuid)')),'convert_lead is the exact volatile invoker command');
select ok((select count(*)=4 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')) from pg_proc p where p.oid in (to_regprocedure('public.create_lead(uuid,uuid,text,text,text,public.lead_source,uuid,text)'),to_regprocedure('public.update_lead(uuid,uuid,uuid,text,text,text,public.lead_source,uuid,text)'),to_regprocedure('public.transition_lead(uuid,uuid,public.lead_stage,timestamptz,text)'),to_regprocedure('public.convert_lead(uuid,uuid,uuid,text,uuid)'))),'all four public lead mutation RPCs exist and are authenticated-only');

-- ---------------------------------------------------------------------------
-- Fixtures. The evidence and revision columns below make this suite red until
-- the Phase 6 leads migration exists.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('57000000-0000-4000-8000-000000000001','Leads Visible A','LEA57A','active','Asia/Kolkata','INR'),
 ('57000000-0000-4000-8000-000000000002','Leads Visible B','LEA57B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('57000000-0000-4000-8000-000000000011','57000000-0000-4000-8000-000000000001','Koramangala',true),
 ('57000000-0000-4000-8000-000000000012','57000000-0000-4000-8000-000000000002','Main B',true);
insert into auth.users(id) values
 ('57000000-0000-4000-8000-000000000901'),('57000000-0000-4000-8000-000000000902'),
 ('57000000-0000-4000-8000-000000000903'),('57000000-0000-4000-8000-000000000904'),
 ('57000000-0000-4000-8000-000000000905'),('57000000-0000-4000-8000-000000000906'),
 ('57000000-0000-4000-8000-000000000907'),('57000000-0000-4000-8000-000000000908'),
 ('57000000-0000-4000-8000-000000000909'),('57000000-0000-4000-8000-00000000090a');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('57000000-0000-4000-8000-000000000909','platform_support','Support Probe','support@example.test',true),
 ('57000000-0000-4000-8000-00000000090a','super_admin','Super Probe','super@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('57000000-0000-4000-8000-000000000021','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000901','57000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('57000000-0000-4000-8000-000000000022','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000902','57000000-0000-4000-8000-000000000011','gym_manager','Manager A',true),
 ('57000000-0000-4000-8000-000000000023','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000903','57000000-0000-4000-8000-000000000011','front_desk','Desk A1',true),
 ('57000000-0000-4000-8000-000000000024','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000904','57000000-0000-4000-8000-000000000011','front_desk','Desk A2',true),
 ('57000000-0000-4000-8000-000000000025','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000905','57000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('57000000-0000-4000-8000-000000000026','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000906','57000000-0000-4000-8000-000000000011','front_desk','Inactive Desk A',false),
 ('57000000-0000-4000-8000-000000000027','57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000907','57000000-0000-4000-8000-000000000012','front_desk','Desk B',true);
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status,erased_at) values
 ('57000000-0000-4000-8000-000000000031','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000908','57000000-0000-4000-8000-000000000011','Member A','+915700000031','active',null),
 ('57000000-0000-4000-8000-000000000032','57000000-0000-4000-8000-000000000001',null,'57000000-0000-4000-8000-000000000011','Cancelled A','+915700000032','cancelled',null);

-- Historical terminal rows keep their null evidence: the contract allows
-- pre-evidence converted history while requiring complete evidence for new
-- RPC conversions. Replica role so the phase 6 enforcement triggers trust the
-- fixture instead of refusing it.
set local session_replication_role = replica;
insert into public.leads(id,tenant_id,branch_id,full_name,phone,email,source,stage,assigned_to_staff_id,trial_at,converted_member_id,converted_at,lost_reason,notes,created_at,updated_at) values
 ('57000000-0000-4000-8000-000000000401','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000011','Historic Converted','+915700000401',null,'walk_in','converted',null,null,'57000000-0000-4000-8000-000000000031','2026-08-01T10:00:00+05:30',null,'Joined in August','2026-07-20T10:00:00+05:30','2026-08-01T10:00:00+05:30'),
 ('57000000-0000-4000-8000-000000000402','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000011','Historic Lost','+915700000402',null,'phone','lost',null,null,null,null,'Went to a rival gym',null,'2026-07-21T10:00:00+05:30','2026-07-25T10:00:00+05:30'),
 ('57000000-0000-4000-8000-000000000403','57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000012','Gym B Trial','+915700000403',null,'referral','trial_done',null,'2026-09-01T10:00:00+05:30',null,null,null,null,'2026-08-20T10:00:00+05:30','2026-09-01T10:00:00+05:30');
set local session_replication_role = default;

create temp table lead_rpc(label text, result jsonb);
grant select,insert on lead_rpc to authenticated;

-- ---------------------------------------------------------------------------
-- Creation evidence, exact replay and GL062, as front desk A1.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000023"}',true);

select lives_ok($$insert into lead_rpc select 'first', public.create_lead('57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000011','  Rahul   Sharma ','+919876543210',' rahul@example.com ','walk_in','57000000-0000-4000-8000-000000000024','  Walk-in  note  ')$$,'front office records an enquiry with unnormalized input');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), (result->>'leadId')::uuid is not null, (result->>'revision')::uuid is not null, result->>'replayed' from lead_rpc where label='first'$$,$$select 3::bigint,true,true,'false'$$,'creation returns exactly leadId, revision and replayed');
select results_eq($$select stage::text, full_name, phone, email, source::text, assigned_to_staff_id::text, trial_at is null, converted_member_id is null, converted_at is null, lost_reason is null, created_by_staff_id::text, creation_request_key::text, revision is not null from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,$$select 'new','Rahul Sharma','+919876543210','rahul@example.com','walk_in','57000000-0000-4000-8000-000000000024',true,true,true,null,'57000000-0000-4000-8000-000000000023','57000000-0000-4000-8000-000000000501',true$$,'a new enquiry row carries normalized facts, a null stage payload and stamped evidence');
select results_eq($$select string_agg(k,',' order by k) from public.leads, jsonb_object_keys(creation_request_facts) k where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,$$select 'actorStaffId,assignedToStaffId,branchId,email,fullName,notes,phone,source'::text$$,'creation facts carry exactly the eight request facts');
select results_eq($$select creation_request_facts->>'actorStaffId', creation_request_facts->>'branchId', creation_request_facts->>'fullName', creation_request_facts->>'phone', creation_request_facts->>'email', creation_request_facts->>'source', creation_request_facts->>'assignedToStaffId', creation_request_facts->>'notes' from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,$$select '57000000-0000-4000-8000-000000000023','57000000-0000-4000-8000-000000000011','Rahul Sharma','+919876543210','rahul@example.com','walk_in','57000000-0000-4000-8000-000000000024','Walk-in note'$$,'creation evidence binds the acting staff and the normalized facts');

select lives_ok($$insert into lead_rpc select 'l1-contacted', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='first'),(select (result->>'revision')::uuid from lead_rpc where label='first'),'contacted',null,null)$$,'contacting a new lead is the first legal edge');
select results_eq($$select stage::text, trial_at is null, lost_reason is null, revision::text<>(select result->>'revision' from lead_rpc where label='first') from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,$$select 'contacted',true,true,true$$,'an accepted transition rotates the database-owned revision');

select lives_ok($$insert into lead_rpc select 'replay', public.create_lead('57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000011','  Rahul   Sharma ','+919876543210',' rahul@example.com ','walk_in','57000000-0000-4000-8000-000000000024','  Walk-in  note  ')$$,'an exact retry replays the committed creation');
select results_eq($$select r.result->>'leadId'=(select result->>'leadId' from lead_rpc where label='first'), (r.result->>'revision')::uuid=l.revision, r.result->>'replayed' from lead_rpc r join public.leads l on l.id=(r.result->>'leadId')::uuid where r.label='replay'$$,$$select true,true,'true'$$,'replay returns the original lead id with its current revision, not an old snapshot');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000011','Rahul Sharma Changed','+919876543210','rahul@example.com','walk_in','57000000-0000-4000-8000-000000000024',null)$$,'GL062',null,'a reused creation key with different facts is GL062');

select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000024"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000011','  Rahul   Sharma ','+919876543210',' rahul@example.com ','walk_in','57000000-0000-4000-8000-000000000024','  Walk-in  note  ')$$,'GL062',null,'a creation retry by another actor conflicts even when every stored fact matches');
select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000023"}',true);

select lives_ok($$insert into lead_rpc select 'second-key', public.create_lead('57000000-0000-4000-8000-000000000502','57000000-0000-4000-8000-000000000011','  Rahul   Sharma ','+919876543210',' rahul@example.com ','walk_in','57000000-0000-4000-8000-000000000024','  Walk-in  note  ')$$,'identical facts under a fresh key record a second enquiry');
select results_eq($$select count(*) from public.leads where tenant_id='57000000-0000-4000-8000-000000000001' and phone='+919876543210'$$,$$select 2$$,'the replay created no extra row while the fresh key created exactly one');

select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000503','57000000-0000-4000-8000-000000000011','Trainer Assignee','+915700000503',null,'walk_in','57000000-0000-4000-8000-000000000025',null)$$,'GL060',null,'a trainer assignee is an invalid assignee fact');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000504','57000000-0000-4000-8000-000000000011','Inactive Assignee','+915700000504',null,'walk_in','57000000-0000-4000-8000-000000000026',null)$$,'GL060',null,'an inactive assignee is an invalid assignee fact');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000505','57000000-0000-4000-8000-000000000011','Foreign Assignee','+915700000505',null,'walk_in','57000000-0000-4000-8000-000000000027',null)$$,'P0002',null,'a cross-gym assignee reveals no foreign fact');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000506','57000000-0000-4000-8000-000000000012','Foreign Branch','+915700000506',null,'walk_in',null,null)$$,'P0002',null,'a cross-gym branch reveals no foreign fact');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000507','57000000-0000-4000-8000-00000000feed','Unknown Branch','+915700000507',null,'walk_in',null,null)$$,null,'an unknown branch is refused');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000508',null,'No Branch','+915700000508',null,'walk_in',null,null)$$,null,'a creation without a branch is refused');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000509','57000000-0000-4000-8000-000000000011','Bad Phone','98765',null,'walk_in',null,null)$$,null,'a non-E.164 phone is refused');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-00000000050a','57000000-0000-4000-8000-000000000011',null,'+91570000050a',null,'walk_in',null,null)$$,null,'a creation without a name is refused');
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-00000000050b','57000000-0000-4000-8000-000000000011','Bad Source','+91570000050b',null,'linkedin',null,null)$$,null,'a non-canonical source is refused');

-- ---------------------------------------------------------------------------
-- The canonical stage graph through transition_lead, on one live lead.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into lead_rpc select 'l2', public.create_lead('57000000-0000-4000-8000-000000000511','57000000-0000-4000-8000-000000000011','Sunita Rao','+915700000511',null,'walk_in',null,null)$$,'a second enquiry starts at new');
select lives_ok($$insert into lead_rpc select 'l2-contacted', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'contacted',null,null)$$,'new to contacted is legal');
select results_eq($$select r.result->'lead'->>'stage', (r.result->'lead'->>'revision')::uuid=l.revision, l.trial_at is null, l.lost_reason is null from lead_rpc r join public.leads l on l.id=(r.result->'lead'->>'id')::uuid where r.label='l2-contacted'$$,$$select 'contacted',true,true,true$$,'a transition returns the new stage and the rotated revision');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'contacted',null,null)$$,'GL059',null,'a self-transition is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'new',null,null)$$,'GL059',null,'a reverse transition is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_done','2026-09-20T10:00:00+05:30',null)$$,'GL059',null,'a skipped transition is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'converted',null,null)$$,'GL059',null,'conversion through the transition RPC is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_scheduled',null,null)$$,'GL060',null,'trial_scheduled without trial_at is an invalid trial fact');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_scheduled','2026-09-20T10:00:00+05:30','Should not be here')$$,'GL060',null,'a non-lost target forbids a loss reason');
select lives_ok($$insert into lead_rpc select 'l2-scheduled', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_scheduled','2026-09-20T10:00:00+05:30',null)$$,'contacted to trial_scheduled with an instant is legal');
select results_eq($$select stage::text, trial_at='2026-09-20 04:30:00+00'::timestamptz, lost_reason is null, revision::text<>(select revision::text from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2') and stage='contacted') from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')$$,$$select 'trial_scheduled',true,true,true$$,'trial_scheduled stores the exact instant and rotates the revision');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_scheduled','2026-09-20T10:00:00+05:30',null)$$,'GL059',null,'a trial_scheduled self-transition is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'contacted',null,null)$$,'GL059',null,'leaving trial_scheduled backwards is refused');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'lost',null,null)$$,'GL060',null,'lost without a reason is an invalid loss fact');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'lost','   ','')$$,'GL060',null,'lost with a whitespace-only reason is an invalid loss fact');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_done',null,null)$$,'GL060',null,'trial_done without trial_at is an invalid trial fact');
select lives_ok($$insert into lead_rpc select 'l2-done', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'trial_done','2026-09-20T10:00:00+05:30',null)$$,'trial_scheduled to trial_done is legal');
select results_eq($$select stage::text, trial_at='2026-09-20 04:30:00+00'::timestamptz, lost_reason is null from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')$$,$$select 'trial_done',true,true$$,'trial_done keeps its trial instant');
select lives_ok($$insert into lead_rpc select 'l2-lost', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'lost',null,'  Chose   another gym  ')$$,'trial_done to lost with a reason is legal');
select results_eq($$select stage::text, lost_reason, trial_at is not null from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')$$,$$select 'lost','Chose another gym',true$$,'lost normalizes its reason and keeps the trial instant');

create temp table lost_probe as select revision, lost_reason, updated_at from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2');

select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'new',null,null)$$,'GL059',null,'a lost lead cannot reopen');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'contacted',null,null)$$,'GL059',null,'a lost lead cannot move at all');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l2'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')),'lost',null,'Stay lost')$$,'GL059',null,'a lost self-transition is refused');
select results_eq($$select stage::text, revision::text=(select revision::text from lost_probe), lost_reason, updated_at=(select updated_at from lost_probe) from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l2')$$,$$select 'lost',true,'Chose another gym',true$$,'refused terminal writes leave the row byte-identical');

-- ---------------------------------------------------------------------------
-- Lost is reachable from every nonterminal stage; remaining forbidden edges.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into lead_rpc select 'l3', public.create_lead('57000000-0000-4000-8000-000000000512','57000000-0000-4000-8000-000000000011','Asha Verma','+915700000512',null,'instagram',null,null)$$,'a third enquiry starts at new');
select lives_ok($$insert into lead_rpc select 'l3-lost', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l3'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l3')),'lost',null,'Not interested')$$,'new to lost is legal');
select results_eq($$select stage::text, lost_reason, trial_at is null, converted_member_id is null, converted_at is null from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l3')$$,$$select 'lost','Not interested',true,true,true$$,'a lost row from new keeps all other stage payloads null');
select lives_ok($$insert into lead_rpc select 'l4', public.create_lead('57000000-0000-4000-8000-000000000513','57000000-0000-4000-8000-000000000011','Vikram Patel','+915700000513',null,'google',null,null)$$,'a fourth enquiry starts at new');
select lives_ok($$insert into lead_rpc select 'l4-contacted', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l4'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l4')),'contacted',null,null)$$,'contacting the fourth enquiry is legal');
select lives_ok($$insert into lead_rpc select 'l4-lost', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l4'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l4')),'lost',null,'Price too high')$$,'contacted to lost is legal');
select results_eq($$select stage::text, lost_reason from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l4')$$,$$select 'lost','Price too high'$$,'the fourth enquiry reached lost from contacted');
select lives_ok($$insert into lead_rpc select 'l5', public.create_lead('57000000-0000-4000-8000-000000000514','57000000-0000-4000-8000-000000000011','Meera Khan','+915700000514',null,'referral',null,null)$$,'a fifth enquiry stays at new for the CAS and edit checks');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')),'trial_scheduled','2026-09-20T10:00:00+05:30',null)$$,'GL059',null,'new to trial_scheduled skips contacted');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')),'trial_done','2026-09-20T10:00:00+05:30',null)$$,'GL059',null,'new to trial_done skips two stages');
select lives_ok($$insert into lead_rpc select 'l6', public.create_lead('57000000-0000-4000-8000-000000000515','57000000-0000-4000-8000-000000000011','Rohit Bose','+915700000515',null,'phone',null,null)$$,'a sixth enquiry stays at new for the direct-write checks');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l6'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')),'new',null,null)$$,'GL059',null,'a new self-transition is refused');
select results_eq($$select r.label, l.stage::text, l.trial_at is null, l.revision::text=r.result->>'revision' from lead_rpc r join public.leads l on l.id=(r.result->>'leadId')::uuid where r.label in ('l5','l6') order by r.label$$,$$values ('l5'::text,'new'::text,true,true),('l6'::text,'new'::text,true,true)$$,'refused edges rotate nothing');

-- ---------------------------------------------------------------------------
-- CAS conflicts and generic invisibility.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into lead_rpc select 'stale-transition', public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),'57000000-0000-4000-8000-00000000dead','contacted',null,null)$$,'a CAS miss is a returned conflict, not an exception');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'staleLead', (result->>'currentRevision')::uuid=(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')) from lead_rpc where label='stale-transition'$$,$$select 2::bigint,'true',true$$,'a stale CAS result carries exactly staleLead and the current revision');
select results_eq($$select stage::text, revision::text=(select result->>'revision' from lead_rpc where label='l5'), trial_at is null, lost_reason is null from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select 'new',true,true,true$$,'a refused CAS transition leaves the row untouched');
select lives_ok($$insert into lead_rpc select 'stale-update', public.update_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),'57000000-0000-4000-8000-00000000dead','57000000-0000-4000-8000-000000000011','Meera Khan','+915700000514',null,'referral',null,null)$$,'a stale update CAS miss is also returned');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'staleLead', (result->>'currentRevision')::uuid=(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')) from lead_rpc where label='stale-update'$$,$$select 2::bigint,'true',true$$,'a stale update carries exactly staleLead and the current revision');
select results_eq($$select full_name, notes is null, revision::text=(select result->>'revision' from lead_rpc where label='l5') from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select 'Meera Khan',true,true$$,'a refused CAS update leaves the row untouched');
select throws_ok($$select public.update_lead('57000000-0000-4000-8000-00000000feed','57000000-0000-4000-8000-00000000dead','57000000-0000-4000-8000-000000000011','Nobody','+915700000799',null,'walk_in',null,null)$$,null,'an unknown lead is a generic refusal');
select throws_ok($$select public.update_lead('57000000-0000-4000-8000-000000000403','57000000-0000-4000-8000-00000000dead','57000000-0000-4000-8000-000000000011','Invisible','+915700000798',null,'walk_in',null,null)$$,null,'a cross-gym lead is the same generic refusal');
select throws_ok($$select public.transition_lead('57000000-0000-4000-8000-00000000feed','57000000-0000-4000-8000-00000000dead','contacted',null,null)$$,null,'an unknown transition target is a generic refusal');

-- ---------------------------------------------------------------------------
-- Same-stage detail edits, no-op writes and revision ownership.
-- ---------------------------------------------------------------------------

create temp table detail_probe as select revision, updated_at from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5');

select lives_ok($$insert into lead_rpc select 'detail', public.update_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')),'57000000-0000-4000-8000-000000000011','Meera Khan','+915700000514','meera@example.com','referral',null,'Prefers evening trials')$$,'a same-stage detail edit is allowed');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), (select string_agg(k,',' order by k) from jsonb_object_keys(result->'lead') k) from lead_rpc where label='detail'$$,$$select 1::bigint,'assignedToName,assignedToStaffId,branchId,branchName,convertedAt,convertedMemberId,createdAt,email,fullName,id,lostReason,notes,phone,revision,source,stage,trialAt,updatedAt'::text$$,'an update returns exactly the eighteen-field LeadDetail');
select results_eq($$select email, notes, stage::text, revision::text<>(select revision::text from detail_probe), updated_at>(select updated_at from detail_probe) from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select 'meera@example.com','Prefers evening trials','new',true,true$$,'a material detail edit rotates revision and updated_at');

create temp table noop_probe as select revision, updated_at from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5');

select lives_ok($$insert into lead_rpc select 'noop', public.update_lead((select (result->>'leadId')::uuid from lead_rpc where label='l5'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')),'57000000-0000-4000-8000-000000000011','Meera Khan','+915700000514','meera@example.com','referral',null,'Prefers evening trials')$$,'an identical update is accepted as a no-op');
select results_eq($$select revision::text=(select revision::text from noop_probe), updated_at=(select updated_at from noop_probe), stage::text from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select true,true,'new'$$,'a no-op write rotates neither revision nor updated_at');

set local role postgres;
select set_config('request.jwt.claims','',true);

create or replace function pg_temp.revision_spoof_probe()
returns text language plpgsql as $fn$
begin
  update public.leads set revision='57000000-0000-4000-8000-00000000dead' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5');
  return 'applied';
exception when others then
  return 'refused';
end
$fn$;
select ok(pg_temp.revision_spoof_probe() in ('applied','refused') and (select revision::text from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5'))<>'57000000-0000-4000-8000-00000000dead','a client attempt to assign the revision never becomes the stored revision');

create temp table direct_probe as select revision, updated_at, creation_request_facts from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5');

select lives_ok($$update public.leads set full_name='Meera Khan Edited' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,'an authorized direct writer may edit business facts of a live lead');
select results_eq($$select full_name, stage::text, revision::text<>(select revision::text from direct_probe), updated_at>(select updated_at from direct_probe) from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select 'Meera Khan Edited','new',true,true$$,'a direct material edit also rotates revision and updated_at');
select results_eq($$select creation_request_facts from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l5')$$,$$select creation_request_facts from direct_probe$$,'direct edits never rewrite creation evidence');

-- ---------------------------------------------------------------------------
-- The database enforces the graph and immutability on direct writes too.
-- ---------------------------------------------------------------------------

select throws_ok($$update public.leads set trial_at='2026-09-20T10:00:00+05:30' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')$$,'GL060',null,'a direct write cannot put a trial instant on a new lead');
select throws_ok($$update public.leads set lost_reason='Direct loss' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')$$,'GL060',null,'a direct write cannot put a loss reason on a new lead');
select throws_ok($$update public.leads set converted_member_id='57000000-0000-4000-8000-000000000031' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')$$,'GL060',null,'a direct write cannot put conversion fields on a new lead');
select throws_ok($$update public.leads set converted_at='2026-09-20T10:00:00+05:30' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')$$,'GL060',null,'a direct write cannot put a conversion time on a new lead');
select throws_ok($$update public.leads set stage='trial_done' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l6')$$,'GL059',null,'a direct write cannot skip stages');
select throws_ok($$update public.leads set stage='new' where id='57000000-0000-4000-8000-000000000402'$$,'GL059',null,'a direct write cannot reopen a lost row');
select throws_ok($$update public.leads set full_name='Renamed Converted' where id='57000000-0000-4000-8000-000000000401'$$,null,'a terminal row cannot change its business facts');
select throws_ok($$update public.leads set converted_member_id='57000000-0000-4000-8000-000000000032' where id='57000000-0000-4000-8000-000000000401'$$,null,'a converted member freezes');
select throws_ok($$update public.leads set converted_at='2026-09-20T10:00:00+05:30' where id='57000000-0000-4000-8000-000000000401'$$,null,'a converted time freezes');
select throws_ok($$update public.leads set tenant_id='57000000-0000-4000-8000-000000000002' where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'tenant is immutable');
select throws_ok($$update public.leads set created_at='2020-01-01T00:00:00+05:30' where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'created_at is immutable');
select throws_ok($$update public.leads set creation_request_key='57000000-0000-4000-8000-00000000beef' where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'creation evidence key is immutable');
select throws_ok($$update public.leads set creation_request_facts='{}'::jsonb where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'creation evidence facts are immutable');
select throws_ok($$update public.leads set created_by_staff_id='57000000-0000-4000-8000-000000000024' where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'the creating actor is immutable');
select throws_ok($$update public.leads set id='57000000-0000-4000-8000-00000000cafe' where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')$$,null,'the lead id is immutable');
select throws_ok($$update public.leads set conversion_request_key='57000000-0000-4000-8000-00000000face' where id='57000000-0000-4000-8000-000000000401'$$,null,'conversion evidence cannot be fabricated on a historical row');

-- ---------------------------------------------------------------------------
-- Role gates: only non-impersonating front office may touch lead data.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000521','57000000-0000-4000-8000-000000000011','Trainer Attempt','+915700000521',null,'walk_in',null,null)$$,'42501',null,'a trainer cannot record an enquiry');
select throws_ok($$select public.transition_lead((select (result->>'leadId')::uuid from lead_rpc where label='first'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')),'lost',null,'Trainer loss')$$,'42501',null,'a trainer cannot transition a lead');
select throws_ok($$select public.update_lead((select (result->>'leadId')::uuid from lead_rpc where label='first'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')),'57000000-0000-4000-8000-000000000011','Rahul Sharma','+919876543210','rahul@example.com','walk_in',null,null)$$,'42501',null,'a trainer cannot edit lead details');
select is_empty($$update public.leads set notes='Trainer edit' returning 1$$,'a trainer direct UPDATE touches no rows');
select throws_ok($$insert into public.leads(tenant_id,branch_id,full_name,phone,source) values ('57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000011','Trainer Insert','+915700000522','walk_in')$$,'42501',null,'a trainer direct INSERT is refused');

select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"57000000-0000-4000-8000-000000000001","member_id":"57000000-0000-4000-8000-000000000031"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000523','57000000-0000-4000-8000-000000000011','Member Attempt','+915700000523',null,'walk_in',null,null)$$,'42501',null,'a member cannot record an enquiry');
select is_empty($$select * from public.leads$$,'a member reads no leads');
select is_empty($$update public.leads set notes='Member edit' returning 1$$,'a member direct UPDATE touches no rows');

select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"57000000-0000-4000-8000-000000000001","staff_id":"57000000-0000-4000-8000-000000000021","impersonation_session_id":"57000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000524','57000000-0000-4000-8000-000000000011','Preview Attempt','+915700000524',null,'walk_in',null,null)$$,'42501',null,'a preview identity cannot record an enquiry');
select is_empty($$select * from public.leads$$,'a preview identity sees no lead rows');
select is_empty($$update public.leads set notes='Preview edit' returning 1$$,'a preview identity mutates nothing');

select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"platform_support"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000525','57000000-0000-4000-8000-000000000011','Support Attempt','+915700000525',null,'walk_in',null,null)$$,'42501',null,'platform support cannot create leads');
select throws_ok($$select public.update_lead((select (result->>'leadId')::uuid from lead_rpc where label='first'),(select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='first')),'57000000-0000-4000-8000-000000000011','Rahul Sharma','+919876543210','rahul@example.com','walk_in',null,null)$$,'42501',null,'platform support cannot edit leads');

create temp table platform_read_probe as select count(*) as c from public.leads;
grant select on platform_read_probe to authenticated;
select results_eq($$select count(*)::text from public.leads$$,$$select c::text from platform_read_probe$$,'platform support keeps its cross-gym read-only view');

select set_config('request.jwt.claims','{"sub":"57000000-0000-4000-8000-00000000090a","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000526','57000000-0000-4000-8000-000000000011','Super Attempt','+915700000526',null,'walk_in',null,null)$$,'42501',null,'super admin has no gym-side RPC identity');
create temp table super_probe as select revision from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l3');
grant select on super_probe to authenticated;
select lives_ok($$update public.leads set notes='Super admin note' where id=(select (result->>'leadId')::uuid from lead_rpc where label='l3')$$,'super admin retains direct database authority');
select results_eq($$select notes, revision::text<>(select revision::text from super_probe) from public.leads where id=(select (result->>'leadId')::uuid from lead_rpc where label='l3')$$,$$select 'Super admin note',true$$,'a super admin direct write is a material accepted change');

select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select public.create_lead('57000000-0000-4000-8000-000000000527','57000000-0000-4000-8000-000000000011','Anon Attempt','+915700000527',null,'walk_in',null,null)$$,'42501',null,'anon cannot execute lead RPCs');

-- ---------------------------------------------------------------------------
-- No invented audit writes.
-- ---------------------------------------------------------------------------

set local role postgres;
select is((select count(*) from public.audit_log), 0::bigint, 'lead writes invent no audit rows');

select * from finish();

rollback;
