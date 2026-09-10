-- Independent complete-member boundary for the narrow trainer-name projection.
begin;
set local role postgres;
set local search_path=public,extensions;
select plan(7);
create temporary table trainer_read_ids as select gen_random_uuid() tenant,gen_random_uuid() branch,
  gen_random_uuid() member_id,gen_random_uuid() subject;
insert into auth.users(id) select subject from trainer_read_ids;
insert into public.organizations(id,name,gym_code,status) select tenant,'Trainer read gym','TRNR23','active' from trainer_read_ids;
insert into public.branches(id,tenant_id,name) select branch,tenant,'Main' from trainer_read_ids;
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone)
select member_id,tenant,branch,subject,'Member','+919922330023' from trainer_read_ids;
create temporary table trainer_read_claims as select jsonb_build_object('sub',subject,'role','authenticated',
  'tenant_id',tenant,'app_role','member','member_id',member_id) claims from trainer_read_ids;
grant select on trainer_read_claims to authenticated;
create function pg_temp.trainer_read_state(p_claims text) returns text language plpgsql as $fn$
begin
  perform set_config('request.jwt.claims',p_claims,true);
  perform * from public.read_member_addon_trainer_names();
  return 'OK';
exception when others then return sqlstate;
end;
$fn$;
do $do$ begin
  execute format('grant usage on schema %s to authenticated',pg_my_temp_schema()::regnamespace);
end; $do$;
set local role authenticated;
select is(pg_temp.trainer_read_state((select claims::text from trainer_read_claims)),'OK',
  'Complete verified member may read the narrow trainer-name projection');
select is(pg_temp.trainer_read_state((select (claims||jsonb_build_object('staff_id',gen_random_uuid()))::text from trainer_read_claims)),'42501',
  'Member trainer projection rejects a simultaneous staff claim');
select is(pg_temp.trainer_read_state((select (claims||jsonb_build_object('sub','malformed-subject'))::text from trainer_read_claims)),'42501',
  'Member trainer projection normalizes malformed subject to authorization refusal');
select is(pg_temp.trainer_read_state((select (claims||jsonb_build_object('tenant_id','malformed-tenant'))::text from trainer_read_claims)),'42501',
  'Member trainer projection normalizes malformed tenant to authorization refusal');
select is(pg_temp.trainer_read_state((select (claims||jsonb_build_object('member_id','malformed-member'))::text from trainer_read_claims)),'42501',
  'Member trainer projection normalizes malformed member to authorization refusal');
select is(pg_temp.trainer_read_state('{invalid-json'),'42501',
  'Member trainer projection normalizes malformed claim JSON to authorization refusal');
select is(pg_temp.trainer_read_state((select (claims||jsonb_build_object('impersonation_session_id',gen_random_uuid()))::text from trainer_read_claims)),'42501',
  'Member trainer projection refuses impersonation authority');
select * from finish();
rollback;
