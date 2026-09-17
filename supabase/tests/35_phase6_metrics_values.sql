-- Phase 6 metrics values, fixed as-of so all component/card checks are deterministic.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(37);
insert into public.organizations(id,name,gym_code,status,timezone,currency,trial_ends_at) values
 ('35000000-0000-4000-8000-000000000001','Alpha Metrics','AM3501','active','Asia/Kolkata','INR',null),
 ('35000000-0000-4000-8000-000000000002','Broken Metrics','BM3502','trial','Not/AZone','INR','2026-09-14 00:00+00'),
 ('35000000-0000-4000-8000-000000000003','Zulu Metrics','ZM3503','active','Asia/Kolkata','INR',null);
insert into public.branches(id,tenant_id,name,is_default) values
 ('35000000-0000-4000-8000-000000000011','35000000-0000-4000-8000-000000000001','Main',true),
 ('35000000-0000-4000-8000-000000000012','35000000-0000-4000-8000-000000000002','Main',true),
 ('35000000-0000-4000-8000-000000000013','35000000-0000-4000-8000-000000000003','Main',true);
insert into auth.users(id) values ('35000000-0000-4000-8000-000000000901'),('35000000-0000-4000-8000-000000000902');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('35000000-0000-4000-8000-000000000021','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000901','35000000-0000-4000-8000-000000000011','gym_owner','Owner',true),
 ('35000000-0000-4000-8000-000000000022','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000902','35000000-0000-4000-8000-000000000011','gym_manager','Manager',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('35000000-0000-4000-8000-000000000031','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','Live','+915350000031','cancelled'),
 ('35000000-0000-4000-8000-000000000032','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','Paused','+915350000032','active'),
 ('35000000-0000-4000-8000-000000000033','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','Money','+915350000033','active');
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency) values ('35000000-0000-4000-8000-000000000041','35000000-0000-4000-8000-000000000001','Month',30,10000,'INR');
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,discount_paise,currency,periods_granted,duration_days) values
 ('35000000-0000-4000-8000-000000000051','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000031','35000000-0000-4000-8000-000000000041','active','2026-09-01','2026-09-30',10000,0,'INR',0,30),
 ('35000000-0000-4000-8000-000000000052','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000032','35000000-0000-4000-8000-000000000041','frozen','2026-09-01','2026-09-30',10000,0,'INR',0,30),
 ('35000000-0000-4000-8000-000000000053','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000033','35000000-0000-4000-8000-000000000041','expired','2026-09-01','2026-09-15',10000,0,'INR',0,30);
insert into public.membership_pauses(id,tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id,approved_by_staff_id,approved_at) values ('35000000-0000-4000-8000-000000000061','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000052','2026-09-15','2026-09-15','travel','35000000-0000-4000-8000-000000000022','35000000-0000-4000-8000-000000000021','2026-09-14 10:00+00');
insert into public.attendance(id,tenant_id,branch_id,member_id,source,checked_in_at) values
 ('35000000-0000-4000-8000-000000000071','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','35000000-0000-4000-8000-000000000031','front_desk','2026-09-15 00:00+05:30'),
 ('35000000-0000-4000-8000-000000000072','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','35000000-0000-4000-8000-000000000031','front_desk','2026-09-15 23:59:59+05:30'),
 ('35000000-0000-4000-8000-000000000073','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','35000000-0000-4000-8000-000000000031','front_desk','2026-09-16 00:00+05:30');
insert into public.no_show_cases(id,tenant_id,member_id,status,opened_on,absent_days_at_open,threshold_days,next_follow_up_at,returned_at) values
 ('35000000-0000-4000-8000-000000000081','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000031','open','2026-09-01',7,7,'2026-09-15 18:30+00',null),
 ('35000000-0000-4000-8000-000000000082','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000032','contacted','2026-09-01',7,7,'2026-09-15 19:00+00',null),
 ('35000000-0000-4000-8000-000000000083','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000033','returned','2026-09-01',7,7,null,'2026-09-15 12:00+00');
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,recorded_by_staff_id,paid_at,receipt_number) values
 ('35000000-0000-4000-8000-000000000091','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000033',null,9007199254740993,'INR','paid','cash','35000000-0000-4000-8000-000000000021','2026-09-15 10:00+00','R-big'),
 ('35000000-0000-4000-8000-000000000092','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000033',null,500,'USD','refunded','card','35000000-0000-4000-8000-000000000021','2026-09-14 10:00+00','R-old'),
 ('35000000-0000-4000-8000-000000000093','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000033',null,700,'INR','paid','upi','35000000-0000-4000-8000-000000000021',null,'R-undated');
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,processed_at) values
 ('35000000-0000-4000-8000-000000000101','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000092','refund',500,'USD','completed','old payment return','2026-09-15 11:00+00'),
 ('35000000-0000-4000-8000-000000000102','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000091','reversal',100,'INR','completed','partial','2026-09-15 11:01+00');
insert into public.leads(id,tenant_id,branch_id,full_name,phone,source,stage,created_at,converted_member_id,converted_at) values
 ('35000000-0000-4000-8000-000000000111','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','Converted','+915350000111','walk_in','converted','2026-09-15 09:00+00','35000000-0000-4000-8000-000000000031','2026-09-20 09:00+00'),
 ('35000000-0000-4000-8000-000000000112','35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000011','New','+915350000112','walk_in','new','2026-09-15 09:00+00',null,null);
select set_config('request.jwt.claims','{"sub":"35000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"35000000-0000-4000-8000-000000000001","staff_id":"35000000-0000-4000-8000-000000000021"}',true);
set local role authenticated;
create temp table probe as select app.gym_metrics('35000000-0000-4000-8000-000000000001','2026-09-15 18:30+00','2026-09-15','2026-09-15') j;
select is((select array_agg(key order by key) from jsonb_object_keys((select j from probe)) key),array['asOf','cards','components','localToday','range','tenantId','timezone','warnings'],'MET-004 response has exactly the contract keys');
select is((select array_agg(key order by key) from jsonb_object_keys((select j->'cards' from probe)) key),array['addonCash','cash','followUpsDue','leads','liveMembers','openCases','pausedMembers','pt','recovered','renewal','visitsToday'],'MET-004 cards have exactly the contract keys');
select is((select array_agg(key order by key) from jsonb_object_keys((select j->'warnings' from probe)) key),array['incompletePtOrders','undatedPayments','undatedPtOrders','undatedReturns'],'MET-004 warnings have exactly the contract keys');
select is((select array_agg(key order by key) from jsonb_object_keys((select j->'components' from probe)) key),array['cases','collected','leads','liveMembers','ptOrders','recoveries','renewals','returned','visits'],'MET-004 components have exactly the named populations');
select is((select j->'range'->>'mode' from probe),'explicit','MET-003 explicit mode');
select is((select j->'range'->>'startsAt' from probe),'2026-09-14T18:30:00+00:00','MET-003 local midnight range start');
select is((select j->'range'->>'endsBefore' from probe),'2026-09-15T18:30:00+00:00','MET-003 inclusive local through boundary');
select is((select j->'cards'->>'visitsToday' from probe),'2','MET-005 same-member visits and midnight boundary');
select is((select jsonb_array_length(j->'components'->'visits') from probe),2,'MET-005 visits card reconciles');
select is((select j->'cards'->>'liveMembers' from probe),'2','MET-005 membership, not profile, forms live population');
select is((select j->'cards'->>'pausedMembers' from probe),'1','MET-005 inclusive pause forms paused population');
select is((select j->'cards'->>'openCases' from probe),'2','MET-006 live cases are current-state');
select is((select j->'cards'->>'followUpsDue' from probe),'1','MET-006 due is <= as-of');
select is((select j->'cards'->>'recovered' from probe),'1','MET-006 returns use selected range');
select is((select j->'cards'->'cash' @> '[{"currency":"INR","collectedPaise":"9007199254740993","returnedPaise":"100","netPaise":"9007199254740893"}]'::jsonb from probe),true,'MET-007 exact bigint cash strings reconcile');
select is((select j->'cards'->'cash' @> '[{"currency":"USD","collectedPaise":"0","returnedPaise":"500","netPaise":"-500"}]'::jsonb from probe),true,'MET-007 refund-only currency remains');
select is((select j->'components'->'collected'->0->>'amountPaise' from probe),'9007199254740993','MET-007 component money is not a JS number');
select is((select j->'warnings'->'undatedPayments' @> '[{"paymentId":"35000000-0000-4000-8000-000000000093","amountPaise":"700","currency":"INR"}]'::jsonb from probe),true,'MET-007 undated arrived payment is an explicit warning');
select is((select j->'cards'->'renewal'->0->>'duePaise' from probe),app.membership_renewal_remainder('35000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000053')->>'duePaise','MET-007 renewal due is the shared remainder result');
select is((select j->'cards'->'leads'->>'converted' from probe),'1','MET-008 converted numerator');
select is((select j->'cards'->'leads'->>'total' from probe),'2','MET-008 lead cohort denominator');
select is((select jsonb_array_length(j->'components'->'leads') from probe),2,'MET-008 lead card reconciles');
select is((select j->'cards'->'pt'->>'sessionsUsed' from probe),'0','MET-008 empty PT usage is decimal zero');
select is((select j->'cards'->'pt'->>'sessionsTotal' from probe),'0','MET-008 empty PT total is decimal zero');
select is((select j->'cards'->'pt'->>'orders' from probe),'0','MET-008 empty PT orders is decimal zero');
select is((select j->'cards'->'addonCash' from probe),'[]'::jsonb,'MET-007 empty add-on cash has no invented currency');
select is((select j->'warnings'->'undatedReturns' from probe),'[]'::jsonb,'MET-007 empty undated returns are an empty array');
select is((select j->'warnings'->'undatedPtOrders' from probe),'[]'::jsonb,'MET-008 empty undated PT warnings are explicit');
select is((select j->'warnings'->'incompletePtOrders' from probe),'[]'::jsonb,'MET-008 incomplete PT warning population is explicit');
select is((select public.owner_metrics(null,null)->'range'->>'mode'),'month_to_date','MET-003 omitted dates produce month-to-date mode');
select ok(jsonb_typeof(public.owner_metrics(null,null))='object','MET-001 owner wrapper works');
select set_config('request.jwt.claims','{"sub":"35000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"gym_manager","tenant_id":"35000000-0000-4000-8000-000000000001","staff_id":"35000000-0000-4000-8000-000000000022"}',true);
select ok(jsonb_typeof(public.owner_metrics(null,null))='object','MET-001 manager wrapper works');
select set_config('request.jwt.claims','{"sub":"35000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"super_admin"}',true);
select is((select array_agg(x->>'name') from jsonb_array_elements(public.fleet_metrics()->'gyms') x),array['Alpha Metrics','Broken Metrics','Zulu Metrics'],'OPS-001 fleet orders gyms by name');
select is((select public.fleet_metrics()->'gyms' @> '[{"tenantId":"35000000-0000-4000-8000-000000000002","metricsError":{"code":"invalid_gym_timezone"},"activeMembers":null}]'::jsonb),true,'OPS-001 malformed zone is isolated');
select is((select public.fleet_metrics()->'exceptions'->'trialExpired' @> '["35000000-0000-4000-8000-000000000002"]'::jsonb),true,'OPS-001 exception derives from returned gym');
select is((select app.gym_readiness('35000000-0000-4000-8000-000000000001')->'providerReadiness'->'push'->>'ready'),'false','OPS-004 provider fixed false');
select is((select app.gym_readiness('35000000-0000-4000-8000-000000000001')->'missingSettings'->>0),'settings','OPS-004 missing settings first and dependent keys skipped');
select * from finish();
rollback;
