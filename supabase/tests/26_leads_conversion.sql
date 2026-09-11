-- Phase 6 visible database contract: lead conversion, duplicate members and
-- conversion races. Derived only from the frozen LEAD-001..LEAD-005 /
-- GL059..GL062 contract in docs/planning/phase6-leads-contract.md and the
-- phase6 leads spec. The implementation and supabase/tests-holdout were not
-- read. Every fixture rolls back. Races are proved by the exact lead lock,
-- (tenant_id, phone) unique key and evidence mechanisms, replayed serially;
-- the runner cannot open a second database connection.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(60);

-- ---------------------------------------------------------------------------
-- Fixtures. The evidence and revision columns make this suite red until the
-- Phase 6 leads migration exists. Trial-done leads are historical rows with
-- null creation evidence, which the contract allows.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('58000000-0000-4000-8000-000000000001','Leads Convert A','LEC58A','active','Asia/Kolkata','INR'),
 ('58000000-0000-4000-8000-000000000002','Leads Convert B','LEC58B','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('58000000-0000-4000-8000-000000000011','58000000-0000-4000-8000-000000000001','Main A',true),
 ('58000000-0000-4000-8000-000000000012','58000000-0000-4000-8000-000000000002','Main B',true);
insert into auth.users(id) values
 ('58000000-0000-4000-8000-000000000901'),('58000000-0000-4000-8000-000000000903'),
 ('58000000-0000-4000-8000-000000000904'),('58000000-0000-4000-8000-000000000905'),
 ('58000000-0000-4000-8000-000000000907'),('58000000-0000-4000-8000-000000000908'),
 ('58000000-0000-4000-8000-000000000909');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('58000000-0000-4000-8000-000000000909','platform_support','Support Probe','support@example.test',true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
 ('58000000-0000-4000-8000-000000000021','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000901','58000000-0000-4000-8000-000000000011','gym_owner','Owner A',true),
 ('58000000-0000-4000-8000-000000000023','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000903','58000000-0000-4000-8000-000000000011','front_desk','Desk A1',true),
 ('58000000-0000-4000-8000-000000000024','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000904','58000000-0000-4000-8000-000000000011','front_desk','Desk A2',true),
 ('58000000-0000-4000-8000-000000000025','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000905','58000000-0000-4000-8000-000000000011','trainer','Trainer A',true),
 ('58000000-0000-4000-8000-000000000027','58000000-0000-4000-8000-000000000002','58000000-0000-4000-8000-000000000907','58000000-0000-4000-8000-000000000012','front_desk','Desk B',true);
insert into public.members(id,tenant_id,user_id,branch_id,full_name,phone,status,erased_at) values
 ('58000000-0000-4000-8000-000000000031','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000908','58000000-0000-4000-8000-000000000011','Member One','+915800000031','active',null),
 ('58000000-0000-4000-8000-000000000032','58000000-0000-4000-8000-000000000001',null,'58000000-0000-4000-8000-000000000011','Paused Member','+915800000032','paused',null),
 ('58000000-0000-4000-8000-000000000033','58000000-0000-4000-8000-000000000001',null,'58000000-0000-4000-8000-000000000011','Expired Member','+915800000033','expired',null),
 ('58000000-0000-4000-8000-000000000034','58000000-0000-4000-8000-000000000001',null,'58000000-0000-4000-8000-000000000011','Cancelled Member','+915800000034','cancelled',null),
 ('58000000-0000-4000-8000-000000000035','58000000-0000-4000-8000-000000000001',null,'58000000-0000-4000-8000-000000000011','Blocked Member','+915800000035','blocked',null),
 ('58000000-0000-4000-8000-000000000036','58000000-0000-4000-8000-000000000001',null,'58000000-0000-4000-8000-000000000011','Erased Member','+915800000036','active',transaction_timestamp()),
 ('58000000-0000-4000-8000-000000000037','58000000-0000-4000-8000-000000000002',null,'58000000-0000-4000-8000-000000000012','Gym B Member','+915800000037','active',null);

set local session_replication_role = replica;
insert into public.leads(id,tenant_id,branch_id,full_name,phone,email,source,stage,assigned_to_staff_id,trial_at,converted_member_id,converted_at,lost_reason,notes,created_at,updated_at) values
 ('58000000-0000-4000-8000-000000000601','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Ravi Kumar','+915800000601','ravi@example.com','walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,'Wants evening batch','2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000602','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Anita Desai','+915800000031',null,'referral','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000603','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Sanjay Gupta','+915800000034',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000604','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Priya Menon','+915800000037',null,'instagram','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000605','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Dinesh Rao','+915800000032',null,'google','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000606','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Farah Khan','+915800000033',null,'website','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000607','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Gopal Iyer','+915800000035',null,'phone','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000608','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Hema Malini','+915800000036',null,'other','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000609','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Ishaan Roy','+915800000609',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-01T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000611','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Kiran Shah','+915800000031',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000612','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Lalit Verma','+915800000612',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000613','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Mina Joshi','+915800000034',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000614','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Nikhil Bose','+915800000614',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000615','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Omkar Nair','+915800000615',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Pooja Reddy','+915800000616',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000617','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Qasim Ali','+915800000617',null,'walk_in','trial_scheduled',null,'2026-09-25T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-12T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Reena Sen','+915800000618',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000619','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Suresh Babu','+915800000619',null,'walk_in','new',null,null,null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-03T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000620','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Tanvi Shah','+915800000620',null,'walk_in','lost',null,null,null,null,'Chose a closer gym',null,'2026-09-02T10:00:00+05:30','2026-09-05T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000621','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Umesh Patel','+915800000621',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000622','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Vandana Rao','+915800000622',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000623','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Waseem Ahmed','+915800000032',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000624','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Xavier Dsouza','+915800000624',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000625','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Rollback probe','+915800000625',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000626','58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Yash Gupta','+915800000034',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30'),
 ('58000000-0000-4000-8000-000000000651','58000000-0000-4000-8000-000000000002','58000000-0000-4000-8000-000000000012','Zoya Farooqui','+915800000651',null,'walk_in','trial_done',null,'2026-09-18T10:00:00+05:30',null,null,null,null,'2026-09-02T10:00:00+05:30','2026-09-18T11:00:00+05:30');
set local session_replication_role = default;

create temp table lead_fix(label text, id uuid, revision uuid);
insert into lead_fix
select v.label, l.id, l.revision
from (values
 ('lc1','58000000-0000-4000-8000-000000000601'::uuid),('lc2','58000000-0000-4000-8000-000000000602'::uuid),
 ('lc3','58000000-0000-4000-8000-000000000603'::uuid),('lc4','58000000-0000-4000-8000-000000000604'::uuid),
 ('lc5','58000000-0000-4000-8000-000000000605'::uuid),('lc6','58000000-0000-4000-8000-000000000606'::uuid),
 ('lc7','58000000-0000-4000-8000-000000000607'::uuid),('lc8','58000000-0000-4000-8000-000000000608'::uuid),
 ('lc9','58000000-0000-4000-8000-000000000609'::uuid),('lc11','58000000-0000-4000-8000-000000000611'::uuid),
 ('lc12','58000000-0000-4000-8000-000000000612'::uuid),('lc13','58000000-0000-4000-8000-000000000613'::uuid),
 ('lc14','58000000-0000-4000-8000-000000000614'::uuid),('lc15','58000000-0000-4000-8000-000000000615'::uuid),
 ('lc16','58000000-0000-4000-8000-000000000616'::uuid),('lc17','58000000-0000-4000-8000-000000000617'::uuid),
 ('lc18','58000000-0000-4000-8000-000000000618'::uuid),('lc19','58000000-0000-4000-8000-000000000619'::uuid),
 ('lc20','58000000-0000-4000-8000-000000000620'::uuid),('lc21','58000000-0000-4000-8000-000000000621'::uuid),
 ('lc22','58000000-0000-4000-8000-000000000622'::uuid),('lc23','58000000-0000-4000-8000-000000000623'::uuid),
 ('lc24','58000000-0000-4000-8000-000000000624'::uuid),('lc25','58000000-0000-4000-8000-000000000625'::uuid),
 ('lc26','58000000-0000-4000-8000-000000000626'::uuid),('lb','58000000-0000-4000-8000-000000000651'::uuid)) v(label,id)
join public.leads l on l.id=v.id;
grant select on lead_fix to authenticated;

create temp table m1_probe as select full_name, phone, status::text as status_text, email, joined_on from public.members where id='58000000-0000-4000-8000-000000000031';
grant select on m1_probe to authenticated;

create temp table population_probe as select
 (select count(*) from public.memberships) as memberships,
 (select count(*) from public.payments) as payments,
 (select count(*) from public.attendance) as attendance,
 (select count(*) from public.consents) as consents,
 (select count(*) from auth.users) as users;

create temp table conv_results(label text, result jsonb);
grant select,insert on conv_results to authenticated;

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

-- ---------------------------------------------------------------------------
-- Create mode with no duplicate: one member, one converted lead, nothing else.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000023"}',true);

select lives_ok($$insert into conv_results select 'lc1-create', public.convert_lead('58000000-0000-4000-8000-000000000601','58000000-0000-4000-8000-000000000701',(select revision from lead_fix where label='lc1'),'create',null)$$,'create mode converts a trial_done lead with no same-gym member');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'leadId', result->>'outcome', result->>'replayed', (result->>'memberId')::uuid is not null from conv_results where label='lc1-create'$$,$$select 5::bigint,'58000000-0000-4000-8000-000000000601','created_member','false',true$$,'conversion returns exactly leadId, memberId, outcome, revision and replayed');
select results_eq($$select stage::text, converted_member_id::text=(select result->>'memberId' from conv_results where label='lc1-create'), converted_at is not null, lost_reason is null, trial_at is not null, revision::text<>(select revision::text from lead_fix where label='lc1') from public.leads where id='58000000-0000-4000-8000-000000000601'$$,$$select 'converted',true,true,true,true,true$$,'the converted lead freezes its member and the server conversion time');
select results_eq($$select tenant_id::text, branch_id::text, full_name, phone, email, status::text, joined_on=(transaction_timestamp() at time zone 'Asia/Kolkata')::date, member_code is null, user_id is null, notes is null, erased_at is null from public.members where id=(select (result->>'memberId')::uuid from conv_results where label='lc1-create')$$,$$select '58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000011','Ravi Kumar','+915800000601','ravi@example.com','active',true,true,true,true,true$$,'create mode copies the lead profile with the accepting transaction gym-local joined_on');
select results_eq($$select conversion_request_key::text, (select string_agg(k,',' order by k) from jsonb_object_keys(conversion_request_facts) k) from public.leads where id='58000000-0000-4000-8000-000000000601'$$,$$select '58000000-0000-4000-8000-000000000701','actorStaffId,expectedRevision,leadId,memberId,mode'::text$$,'conversion evidence stores the request key and exactly five facts');
select results_eq($$select conversion_request_facts->>'actorStaffId', conversion_request_facts->>'leadId', conversion_request_facts->>'expectedRevision', conversion_request_facts->>'mode', conversion_request_facts->'memberId' from public.leads where id='58000000-0000-4000-8000-000000000601'$$,$$select '58000000-0000-4000-8000-000000000023','58000000-0000-4000-8000-000000000601',(select revision::text from lead_fix where label='lc1'),'create','null'::jsonb$$,'conversion evidence binds the original actor, lead, revision and mode');
select results_eq($$select count(*) from public.members where tenant_id='58000000-0000-4000-8000-000000000001' and phone='+915800000601'$$,$$select 1::bigint$$,'create mode invents no duplicate member');

-- ---------------------------------------------------------------------------
-- An eligible same-gym duplicate: GL061 with only four member facts.
-- ---------------------------------------------------------------------------

select results_eq($$select c.returned_state, (select string_agg(k,',' order by k) from jsonb_object_keys(c.detail::jsonb) k), c.detail::jsonb->>'memberId', c.detail::jsonb->>'fullName', c.detail::jsonb->>'phone', c.detail::jsonb->>'status' from pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000602','58000000-0000-4000-8000-000000000702',(select revision from lead_fix where label='lc2'),'create',null)$sql$) c$$,$$select 'GL061','fullName,memberId,phone,status','58000000-0000-4000-8000-000000000031','Member One','+915800000031','active'$$,'GL061 discloses exactly the same-gym member id, name, phone and status');
select results_eq($$select stage::text, revision::text=(select revision::text from lead_fix where label='lc2'), converted_member_id is null, converted_at is null from public.leads where id='58000000-0000-4000-8000-000000000602'$$,$$select 'trial_done',true,true,true$$,'a GL061 refusal changes nothing');
select results_eq($$select count(*) from public.members where tenant_id='58000000-0000-4000-8000-000000000001' and phone='+915800000031'$$,$$select 1::bigint$$,'a duplicate refusal creates no member');
select results_eq($$select c.returned_state, c.detail::jsonb->>'memberId' from pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000605','58000000-0000-4000-8000-000000000703',(select revision from lead_fix where label='lc5'),'create',null)$sql$) c$$,$$select 'GL061','58000000-0000-4000-8000-000000000032'$$,'a paused member is still an eligible duplicate');
select results_eq($$select c.returned_state, c.detail::jsonb->>'memberId' from pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000606','58000000-0000-4000-8000-000000000704',(select revision from lead_fix where label='lc6'),'create',null)$sql$) c$$,$$select 'GL061','58000000-0000-4000-8000-000000000033'$$,'an expired member is still an eligible duplicate');

-- ---------------------------------------------------------------------------
-- An unavailable duplicate: a generic conflict with no member facts.
-- ---------------------------------------------------------------------------

select results_eq($$select x.r->>'memberUnavailable', (select count(*) from jsonb_object_keys(x.r)), x.r->>'memberId', x.r->>'fullName' from (values (public.convert_lead('58000000-0000-4000-8000-000000000603','58000000-0000-4000-8000-000000000705',(select revision from lead_fix where label='lc3'),'create',null)),(public.convert_lead('58000000-0000-4000-8000-000000000607','58000000-0000-4000-8000-000000000706',(select revision from lead_fix where label='lc7'),'create',null)),(public.convert_lead('58000000-0000-4000-8000-000000000608','58000000-0000-4000-8000-000000000707',(select revision from lead_fix where label='lc8'),'create',null))) x(r)$$,$$select 'true',1::bigint,null,null from generate_series(1,3)$$,'cancelled, blocked and erased duplicates all return a bare member-unavailable conflict');
select results_eq($$select l.id::text, l.stage::text, l.revision::text=f.revision::text, l.converted_member_id is null from public.leads l join lead_fix f on f.id=l.id where f.label in ('lc3','lc7','lc8') order by f.label$$,$$values ('58000000-0000-4000-8000-000000000603'::text,'trial_done'::text,true,true),('58000000-0000-4000-8000-000000000607'::text,'trial_done'::text,true,true),('58000000-0000-4000-8000-000000000608'::text,'trial_done'::text,true,true)$$,'unavailable duplicates change nothing');

-- ---------------------------------------------------------------------------
-- Cross-gym privacy: another gym's phone behaves exactly like no match.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc4-create', public.convert_lead('58000000-0000-4000-8000-000000000604','58000000-0000-4000-8000-000000000708',(select revision from lead_fix where label='lc4'),'create',null)$$,'a cross-gym phone converts like a no-match create');
select results_eq($$select result->>'outcome', result->>'replayed', (result->>'memberId')::uuid is not null from conv_results where label='lc4-create'$$,$$select 'created_member','false',true$$,'the cross-gym outcome is the ordinary created_member result');

-- Spec amendment: members RLS hides gym B's row from this gym A session, so the
-- untouched-other-gym count is captured as a probe outside RLS; the original
-- draft asked the tenant A session to count another tenant's members.
set local role postgres;
create temp table gym_b_after as select count(*) as c from public.members where phone='+915800000037' and tenant_id='58000000-0000-4000-8000-000000000002';
grant select on gym_b_after to authenticated;
set local role authenticated;
select results_eq($$select (select count(*) from public.members where phone='+915800000037' and tenant_id='58000000-0000-4000-8000-000000000001'), (select c from gym_b_after)$$,$$select 1::bigint,1::bigint$$,'the cross-gym phone becomes this gym member and leaves the other gym untouched');

-- ---------------------------------------------------------------------------
-- A lead without email or notes creates a member without them.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc9-create', public.convert_lead('58000000-0000-4000-8000-000000000609','58000000-0000-4000-8000-000000000709',(select revision from lead_fix where label='lc9'),'create',null)$$,'a lead with null email and notes converts');
select results_eq($$select email is null, notes is null, full_name, status::text from public.members where id=(select (result->>'memberId')::uuid from conv_results where label='lc9-create')$$,$$select true,true,'Ishaan Roy','active'$$,'null lead facts stay null on the created member');

-- ---------------------------------------------------------------------------
-- Link mode: exact phone, eligible member, neither profile edited.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc11-link', public.convert_lead('58000000-0000-4000-8000-000000000611','58000000-0000-4000-8000-00000000070a',(select revision from lead_fix where label='lc11'),'link_existing','58000000-0000-4000-8000-000000000031')$$,'link mode converts against the named member');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'leadId', result->>'memberId', result->>'outcome', result->>'replayed' from conv_results where label='lc11-link'$$,$$select 5::bigint,'58000000-0000-4000-8000-000000000611','58000000-0000-4000-8000-000000000031','linked_existing','false'$$,'link mode returns the linked member');
select results_eq($$select stage::text, converted_member_id::text, converted_at is not null, conversion_request_facts->>'mode', conversion_request_facts->>'memberId', conversion_request_facts->>'actorStaffId' from public.leads where id='58000000-0000-4000-8000-000000000611'$$,$$select 'converted','58000000-0000-4000-8000-000000000031',true,'link_existing','58000000-0000-4000-8000-000000000031','58000000-0000-4000-8000-000000000023'$$,'link mode converts with complete conversion evidence');
select results_eq($$select full_name, phone, status::text, email, joined_on=(select joined_on from m1_probe) from public.members where id='58000000-0000-4000-8000-000000000031'$$,$$select (select full_name from m1_probe), (select phone from m1_probe), (select status_text from m1_probe), (select email from m1_probe), true$$,'linking edits neither profile');

-- ---------------------------------------------------------------------------
-- Wrong-phone, unavailable, cross-gym and unknown link targets: one generic
-- refusal, indistinguishable from each other.
-- ---------------------------------------------------------------------------

select results_eq($$select c1.returned_state, c2.returned_state, c3.returned_state, c4.returned_state from pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000612','58000000-0000-4000-8000-00000000070b',(select revision from lead_fix where label='lc12'),'link_existing','58000000-0000-4000-8000-000000000031')$sql$) c1, pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000613','58000000-0000-4000-8000-00000000070c',(select revision from lead_fix where label='lc13'),'link_existing','58000000-0000-4000-8000-000000000034')$sql$) c2, pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000614','58000000-0000-4000-8000-00000000070d',(select revision from lead_fix where label='lc14'),'link_existing','58000000-0000-4000-8000-000000000037')$sql$) c3, pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000615','58000000-0000-4000-8000-00000000070e',(select revision from lead_fix where label='lc15'),'link_existing','58000000-0000-4000-8000-00000000feed')$sql$) c4$$,$$select 'P0002','P0002','P0002','P0002'$$,'wrong-phone, unavailable, cross-gym and unknown link targets are one generic refusal');
select results_eq($$select l.id::text, l.stage::text, l.revision::text=f.revision::text, l.converted_member_id is null from public.leads l join lead_fix f on f.id=l.id where f.label in ('lc12','lc13','lc14','lc15') order by f.label$$,$$values ('58000000-0000-4000-8000-000000000612'::text,'trial_done'::text,true,true),('58000000-0000-4000-8000-000000000613'::text,'trial_done'::text,true,true),('58000000-0000-4000-8000-000000000614'::text,'trial_done'::text,true,true),('58000000-0000-4000-8000-000000000615'::text,'trial_done'::text,true,true)$$,'refused links convert nothing');
select results_eq($$select count(*) from public.leads where converted_member_id='58000000-0000-4000-8000-000000000031'$$,$$select 1::bigint$$,'only the accepted link connected the member');

-- ---------------------------------------------------------------------------
-- Retry resolution: exact replay before revision and stage checks, GL062 for
-- changed facts or actor, stale for every other terminal race.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc16-create', public.convert_lead('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-00000000070f',(select revision from lead_fix where label='lc16'),'create',null)$$,'the first conversion wins');
select results_eq($$select result->>'outcome', result->>'replayed', (result->>'memberId')::uuid is not null from conv_results where label='lc16-create'$$,$$select 'created_member','false',true$$,'the first conversion creates the member');
select lives_ok($$insert into conv_results select 'lc16-replay', public.convert_lead('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-00000000070f',(select revision from lead_fix where label='lc16'),'create',null)$$,'an exact retry with the stale original revision is still a replay');
select results_eq($$select r.result->>'replayed', r.result->>'leadId'='58000000-0000-4000-8000-000000000616', (r.result->>'memberId')::uuid=(select (result->>'memberId')::uuid from conv_results where label='lc16-create'), (select count(*) from public.members where phone='+915800000616') from conv_results r where r.label='lc16-replay'$$,$$select 'true',true,true,1::bigint$$,'the replay resolves before revision or stage checks and creates no second member');
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-00000000070f',(select revision from lead_fix where label='lc16'),'link_existing','58000000-0000-4000-8000-000000000031')$$,'GL062',null,'a changed retry under the same key is GL062');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000024"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-00000000070f',(select revision from lead_fix where label='lc16'),'create',null)$$,'GL062',null,'a conversion retry by another actor conflicts even with equal facts');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000023"}',true);
select lives_ok($$insert into conv_results select 'lc16-second', public.convert_lead('58000000-0000-4000-8000-000000000616','58000000-0000-4000-8000-000000000710',(select revision from public.leads where id='58000000-0000-4000-8000-000000000616'),'create',null)$$,'a converted lead never converts again');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'staleLead', (result->>'currentRevision')::uuid=(select revision from public.leads where id='58000000-0000-4000-8000-000000000616'), (select count(*) from public.members where phone='+915800000616') from conv_results where label='lc16-second'$$,$$select 2::bigint,'true',true,1::bigint$$,'a fresh key on a converted lead gets the stale conflict');

-- ---------------------------------------------------------------------------
-- A stale revision under a fresh key: returned conflict, row untouched.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc18-stale', public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-000000000711','58000000-0000-4000-8000-00000000dead','create',null)$$,'a stale conversion is returned, not raised');
select results_eq($$select (select count(*) from jsonb_object_keys(result)), result->>'staleLead', (result->>'currentRevision')::uuid=(select revision from public.leads where id='58000000-0000-4000-8000-000000000618'), (select stage::text from public.leads where id='58000000-0000-4000-8000-000000000618'), (select converted_member_id is null from public.leads where id='58000000-0000-4000-8000-000000000618') from conv_results where label='lc18-stale'$$,$$select 2::bigint,'true',true,'trial_done',true$$,'a stale conversion carries exactly staleLead and the current revision and changes nothing');

-- ---------------------------------------------------------------------------
-- Only trial_done may convert.
-- ---------------------------------------------------------------------------

select results_eq($$select c1.returned_state, c2.returned_state, c3.returned_state from pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000617','58000000-0000-4000-8000-000000000712',(select revision from lead_fix where label='lc17'),'create',null)$sql$) c1, pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000619','58000000-0000-4000-8000-000000000713',(select revision from lead_fix where label='lc19'),'create',null)$sql$) c2, pg_temp.captured_error($sql$select public.convert_lead('58000000-0000-4000-8000-000000000620','58000000-0000-4000-8000-000000000714',(select revision from lead_fix where label='lc20'),'create',null)$sql$) c3$$,$$select 'GL059','GL059','GL059'$$,'trial_scheduled, new and lost leads cannot convert');
select results_eq($$select l.id::text, l.stage::text, l.revision::text=f.revision::text, l.converted_member_id is null from public.leads l join lead_fix f on f.id=l.id where f.label in ('lc17','lc19','lc20') order by f.label$$,$$values ('58000000-0000-4000-8000-000000000617'::text,'trial_scheduled'::text,true,true),('58000000-0000-4000-8000-000000000619'::text,'new'::text,true,true),('58000000-0000-4000-8000-000000000620'::text,'lost'::text,true,true)$$,'refused conversions change nothing');

-- ---------------------------------------------------------------------------
-- Races, replayed serially: one member, one converted lead, loser stale.
-- ---------------------------------------------------------------------------

select lives_ok($$insert into conv_results select 'lc21-first', public.convert_lead('58000000-0000-4000-8000-000000000621','58000000-0000-4000-8000-000000000715',(select revision from lead_fix where label='lc21'),'create',null)$$,'the first of two racing creates wins');
select lives_ok($$insert into conv_results select 'lc21-second', public.convert_lead('58000000-0000-4000-8000-000000000621','58000000-0000-4000-8000-000000000716',(select revision from lead_fix where label='lc21'),'create',null)$$,'the create-create loser does not win twice');
select results_eq($$select r.result->>'staleLead', (select count(*) from public.members where phone='+915800000621'), (select converted_member_id::text from public.leads where id='58000000-0000-4000-8000-000000000621')=(select result->>'memberId' from conv_results where label='lc21-first') from conv_results r where r.label='lc21-second'$$,$$select 'true',1::bigint,true$$,'two racing creates yield one member and one converted lead');
select lives_ok($$insert into conv_results select 'lc22-create', public.convert_lead('58000000-0000-4000-8000-000000000622','58000000-0000-4000-8000-000000000717',(select revision from lead_fix where label='lc22'),'create',null)$$,'the create side of a create-link race runs first');
select lives_ok($$insert into conv_results select 'lc22-link', public.convert_lead('58000000-0000-4000-8000-000000000622','58000000-0000-4000-8000-000000000718',(select revision from lead_fix where label='lc22'),'link_existing',(select (result->>'memberId')::uuid from conv_results where label='lc22-create'))$$,'the link side of the race cannot relink');
select results_eq($$select r.result->>'staleLead', (select count(*) from public.members where phone='+915800000622'), (select converted_member_id::text from public.leads where id='58000000-0000-4000-8000-000000000622')=(select result->>'memberId' from conv_results where label='lc22-create') from conv_results r where r.label='lc22-link'$$,$$select 'true',1::bigint,true$$,'a create-link race has one winner and cannot relink');

-- ---------------------------------------------------------------------------
-- The first conversion is final even for an authorized direct writer.
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims','',true);

select lives_ok($$update public.leads set stage='converted', converted_member_id='58000000-0000-4000-8000-000000000032', converted_at=transaction_timestamp() where id='58000000-0000-4000-8000-000000000623'$$,'a direct writer may convert a trial_done lead against an eligible exact-phone member');
select results_eq($$select stage::text, converted_member_id::text, converted_at is not null, revision::text<>(select revision::text from lead_fix where label='lc23') from public.leads where id='58000000-0000-4000-8000-000000000623'$$,$$select 'converted','58000000-0000-4000-8000-000000000032',true,true$$,'the first direct conversion is an accepted material change');
select throws_ok($$update public.leads set stage='converted', converted_member_id='58000000-0000-4000-8000-000000000031', converted_at=transaction_timestamp() where id='58000000-0000-4000-8000-000000000624'$$,null,'a direct conversion against a mismatched-phone member is refused');
select throws_ok($$update public.leads set stage='converted', converted_member_id='58000000-0000-4000-8000-000000000034', converted_at=transaction_timestamp() where id='58000000-0000-4000-8000-000000000626'$$,null,'a direct conversion against a cancelled member is refused');
select throws_ok($$update public.leads set converted_member_id='58000000-0000-4000-8000-000000000033' where id='58000000-0000-4000-8000-000000000623'$$,null,'the first conversion is final even for an authorized direct writer');

-- ---------------------------------------------------------------------------
-- Atomicity: a failed member insert rolls the whole conversion back.
-- ---------------------------------------------------------------------------

alter table public.members add constraint members_rollback_probe_chk check (full_name <> 'Rollback probe');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000023"}',true);

select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000625','58000000-0000-4000-8000-000000000719',(select revision from lead_fix where label='lc25'),'create',null)$$,null,'a failed member insert fails the whole conversion');
select results_eq($$select stage::text, revision::text=(select revision::text from lead_fix where label='lc25'), converted_member_id is null, converted_at is null from public.leads where id='58000000-0000-4000-8000-000000000625'$$,$$select 'trial_done',true,true,true$$,'the lead is untouched by the rolled-back conversion');
select results_eq($$select count(*) from public.members where phone='+915800000625'$$,$$select 0::bigint$$,'no member row survives the rollback');

set local role postgres;
alter table public.members drop constraint members_rollback_probe_chk;

-- ---------------------------------------------------------------------------
-- Role gates and cross-gym invisibility.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"trainer","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000025"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-00000000071a',(select revision from lead_fix where label='lc18'),'create',null)$$,'42501',null,'a trainer cannot convert');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000908","role":"authenticated","app_role":"member","tenant_id":"58000000-0000-4000-8000-000000000001","member_id":"58000000-0000-4000-8000-000000000031"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-00000000071b',(select revision from lead_fix where label='lc18'),'create',null)$$,'42501',null,'a member cannot convert');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000901","role":"authenticated","app_role":"gym_owner","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000021","impersonation_session_id":"58000000-0000-4000-8000-000000000801"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-00000000071c',(select revision from lead_fix where label='lc18'),'create',null)$$,'42501',null,'a preview identity cannot convert');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000909","role":"authenticated","app_role":"platform_support"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-00000000071d',(select revision from lead_fix where label='lc18'),'create',null)$$,'42501',null,'platform support cannot convert');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000907","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000002","staff_id":"58000000-0000-4000-8000-000000000027"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000618','58000000-0000-4000-8000-00000000071e',(select revision from lead_fix where label='lc18'),'create',null)$$,null,'another gym front desk gets the same generic refusal for a foreign lead');
select set_config('request.jwt.claims','{"sub":"58000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"front_desk","tenant_id":"58000000-0000-4000-8000-000000000001","staff_id":"58000000-0000-4000-8000-000000000023"}',true);
select throws_ok($$select public.convert_lead('58000000-0000-4000-8000-000000000651','58000000-0000-4000-8000-00000000071f',(select revision from lead_fix where label='lb'),'create',null)$$,null,'a cross-gym lead is the same generic refusal for this gym');

-- ---------------------------------------------------------------------------
-- Nothing else exists after any conversion path, and no audit rows appear.
-- ---------------------------------------------------------------------------

set local role postgres;
select results_eq($$select (select count(*) from public.memberships)::text=(select memberships::text from population_probe), (select count(*) from public.payments)::text=(select payments::text from population_probe), (select count(*) from public.attendance)::text=(select attendance::text from population_probe), (select count(*) from public.consents)::text=(select consents::text from population_probe), (select count(*) from auth.users)::text=(select users::text from population_probe)$$,$$select true,true,true,true,true$$,'conversion creates no membership, payment, attendance, consent or auth user');
select is((select count(*) from public.audit_log where tenant_id in ('58000000-0000-4000-8000-000000000001','58000000-0000-4000-8000-000000000002')), 0::bigint, 'lead conversions invent no audit rows');

select * from finish();

rollback;
