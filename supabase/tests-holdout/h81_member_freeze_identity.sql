-- Independent SLF-003 identity holdout, derived only from frozen SLF proposal
-- and docs/security.md. No visible tests, implementation or migrations read.
-- Actor validation precedes target/argument validation and side effects.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(43);
create schema holdout_slf_identity;
grant usage on schema holdout_slf_identity to authenticated;
insert into public.organizations(id,name,gym_code,status) values
 ('81a00000-0000-4000-8000-000000000001','Identity holdout','H81IDA','active');
insert into public.organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year) values ('81a00000-0000-4000-8000-000000000001','gym_manager',30);
insert into auth.users(id) values
 ('81a00000-0000-4000-8000-000000000101'),
 ('81a00000-0000-4000-8000-000000000102'),
 ('81a00000-0000-4000-8000-000000000103');
insert into public.staff(id,tenant_id,user_id,role,full_name,is_active) values
 ('81a00000-0000-4000-8000-000000000201','81a00000-0000-4000-8000-000000000001','81a00000-0000-4000-8000-000000000101','gym_owner','Identity Owner',true),
 ('81a00000-0000-4000-8000-000000000202','81a00000-0000-4000-8000-000000000001','81a00000-0000-4000-8000-000000000102','gym_manager','Identity Manager',true),
 ('81a00000-0000-4000-8000-000000000203','81a00000-0000-4000-8000-000000000001','81a00000-0000-4000-8000-000000000103','front_desk','Identity Desk',true);
create table holdout_slf_identity.baseline as select
 (select count(*) from public.member_freeze_requests where tenant_id='81a00000-0000-4000-8000-000000000001') requests,
 (select count(*) from public.member_freeze_commands where tenant_id='81a00000-0000-4000-8000-000000000001') commands,
 (select count(*) from public.membership_pauses where tenant_id='81a00000-0000-4000-8000-000000000001') pauses,
 (select count(*) from public.audit_log where tenant_id='81a00000-0000-4000-8000-000000000001') audits;
set local role authenticated;
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000101','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000201','app_role','gym_owner'))::text,true);
select lives_ok('select public.read_staff_freeze_requests(10,null,null)','SLF-003 authentic gym_owner reads the queue');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000102','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000202','app_role','gym_manager'))::text,true);
select lives_ok('select public.read_staff_freeze_requests(10,null,null)','SLF-003 authentic gym_manager reads the queue');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000103','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000203','app_role','front_desk'))::text,true);
select lives_ok('select public.read_staff_freeze_requests(10,null,null)','SLF-003 authentic front_desk reads the queue');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000101','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000201','app_role','gym_manager'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner role mismatch denied before target/shape checks');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000102','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000202','app_role','front_desk'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager role mismatch denied before target/shape checks');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000103','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000203','app_role','gym_owner'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk role mismatch denied before target/shape checks');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000101','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000201','app_role','gym_owner') || jsonb_build_object('member_id','81a00000-0000-4000-8000-000000000301'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_owner contradictory member claim denied before target/shape checks');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000102','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000202','app_role','gym_manager') || jsonb_build_object('member_id','81a00000-0000-4000-8000-000000000301'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 gym_manager contradictory member claim denied before target/shape checks');
select set_config('request.jwt.claims',(jsonb_build_object('sub','81a00000-0000-4000-8000-000000000103','role','authenticated','tenant_id','81a00000-0000-4000-8000-000000000001','staff_id','81a00000-0000-4000-8000-000000000203','app_role','front_desk') || jsonb_build_object('member_id','81a00000-0000-4000-8000-000000000301'))::text,true);
select throws_ok('select public.read_staff_freeze_requests(10,null,null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
select throws_ok('select public.read_member_freeze_request(null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
select throws_ok('select public.adopt_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
select throws_ok('select public.approve_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
select throws_ok('select public.reject_member_freeze_request(null,1,''valid refusal'',null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
select throws_ok('select public.expire_member_freeze_request(null,1,null)','42501'::char(5),null,'SLF-003 front_desk contradictory member claim denied before target/shape checks');
set local role postgres;
select is((select count(*) from public.member_freeze_requests where tenant_id='81a00000-0000-4000-8000-000000000001'),(select requests from holdout_slf_identity.baseline),'SLF-003 refused identities create no request');
select is((select count(*) from public.member_freeze_commands where tenant_id='81a00000-0000-4000-8000-000000000001'),(select commands from holdout_slf_identity.baseline),'SLF-003 refused identities append no command');
select is((select count(*) from public.membership_pauses where tenant_id='81a00000-0000-4000-8000-000000000001'),(select pauses from holdout_slf_identity.baseline),'SLF-003 refused identities create no source pause');
select is((select count(*) from public.audit_log where tenant_id='81a00000-0000-4000-8000-000000000001'),(select audits from holdout_slf_identity.baseline),'SLF-003 refused identities append no audit');
select * from finish();
rollback;
