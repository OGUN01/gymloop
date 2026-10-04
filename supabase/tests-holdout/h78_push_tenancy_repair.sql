-- Independent holdout derived solely from the frozen 2026-10-04 tenancy/readiness packet.
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT plan(48);
SELECT has_column('public','push_provider_configurations','tenant_id','configuration has a tenant');
SELECT col_not_null('public','push_provider_configurations','tenant_id','tenant is mandatory');
SELECT col_is_pk('public','push_provider_configurations','tenant_id','one indexed activation row per tenant');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey) WHERE c.conrelid='public.push_provider_configurations'::regclass AND c.contype='f' AND c.confrelid='public.organizations'::regclass AND a.attname='tenant_id'),'tenant foreign key references organizations');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.push_provider_configurations'::regclass),'configuration RLS enabled');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_provider_configurations'),'no ordinary configuration policy');
SELECT ok(NOT has_table_privilege('anon','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE'),'anon cannot access configuration');
SELECT ok(NOT has_table_privilege('authenticated','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE'),'authenticated cannot access configuration');
SELECT ok(NOT has_table_privilege('service_role','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE'),'service cannot bypass private configuration seam');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.push_provider_configurations'::regclass AND attnum>0 AND NOT attisdropped AND atttypid='boolean'::regtype),'global boolean singleton removed');
SELECT ok(EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('app.push_configuration_ready(uuid)') AND provolatile='s' AND prosecdef AND proowner='postgres'::regrole AND 'search_path=""'=ANY(proconfig)),'private readiness is stable postgres definer with empty search path');
SELECT ok(EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('app.push_configuration_ready()') AND provolatile='s' AND prosecdef AND proowner='postgres'::regrole AND 'search_path=""'=ANY(proconfig)),'claim readiness is stable postgres definer with empty search path');
SELECT ok(NOT has_function_privilege('anon','app.push_configuration_ready(uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','app.push_configuration_ready(uuid)','EXECUTE') AND NOT has_function_privilege('service_role','app.push_configuration_ready(uuid)','EXECUTE'),'parameterized readiness inaccessible to ordinary and service callers');
SELECT ok(has_function_privilege('authenticated','app.push_configuration_ready()','EXECUTE') AND NOT has_function_privilege('anon','app.push_configuration_ready()','EXECUTE') AND NOT has_function_privilege('service_role','app.push_configuration_ready()','EXECUTE'),'zero argument overload authenticated only');
SELECT is(app.push_configuration_ready(NULL::uuid),false,'null tenant never ready');
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000091'),false,'absent tenant never ready');
SET LOCAL session_replication_role = replica;
INSERT INTO public.organizations(id,name,gym_code) VALUES
 ('78800000-0000-4000-8000-000000000081','Held activation A','H78AAA'),
 ('78800000-0000-4000-8000-000000000082','Held activation B','H78BBB');
INSERT INTO public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) VALUES
 ('78800000-0000-4000-8000-000000000081','samuraiapi-51996',statement_timestamp()-interval '1 minute'),
 ('78800000-0000-4000-8000-000000000082','samuraiapi-51996',NULL);
SET LOCAL session_replication_role = origin;
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000081'),true,'A activation enables only A');
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000082'),false,'A cannot enable unactivated B');
SET LOCAL session_replication_role = replica;
INSERT INTO auth.users(id) VALUES ('78800000-0000-4000-8000-000000000201'),('78800000-0000-4000-8000-000000000202'),('78800000-0000-4000-8000-000000000203'),('78800000-0000-4000-8000-000000000204');
INSERT INTO public.staff(id,tenant_id,user_id,role,full_name) VALUES ('78800000-0000-4000-8000-000000000111','78800000-0000-4000-8000-000000000081','78800000-0000-4000-8000-000000000201','gym_owner','Held readiness 81 gym_owner'),
('78800000-0000-4000-8000-000000000112','78800000-0000-4000-8000-000000000081','78800000-0000-4000-8000-000000000202','gym_manager','Held readiness 81 gym_manager'),
('78800000-0000-4000-8000-000000000113','78800000-0000-4000-8000-000000000081','78800000-0000-4000-8000-000000000203','front_desk','Held readiness 81 front_desk'),
('78800000-0000-4000-8000-000000000114','78800000-0000-4000-8000-000000000081','78800000-0000-4000-8000-000000000204','trainer','Held readiness 81 trainer'),
('78800000-0000-4000-8000-000000000121','78800000-0000-4000-8000-000000000082','78800000-0000-4000-8000-000000000201','gym_owner','Held readiness 82 gym_owner'),
('78800000-0000-4000-8000-000000000122','78800000-0000-4000-8000-000000000082','78800000-0000-4000-8000-000000000202','gym_manager','Held readiness 82 gym_manager'),
('78800000-0000-4000-8000-000000000123','78800000-0000-4000-8000-000000000082','78800000-0000-4000-8000-000000000203','front_desk','Held readiness 82 front_desk'),
('78800000-0000-4000-8000-000000000124','78800000-0000-4000-8000-000000000082','78800000-0000-4000-8000-000000000204','trainer','Held readiness 82 trainer');
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000111"}', true);
SELECT is(app.push_configuration_ready(),true,'complete gym_owner claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000202","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"gym_manager","staff_id":"78800000-0000-4000-8000-000000000112"}', true);
SELECT is(app.push_configuration_ready(),true,'complete gym_manager claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000203","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"front_desk","staff_id":"78800000-0000-4000-8000-000000000113"}', true);
SELECT is(app.push_configuration_ready(),true,'complete front_desk claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000204","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"trainer","staff_id":"78800000-0000-4000-8000-000000000114"}', true);
SELECT is(app.push_configuration_ready(),true,'complete trainer claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'complete gym_owner claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000202","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_manager","staff_id":"78800000-0000-4000-8000-000000000122"}', true);
SELECT is(app.push_configuration_ready(),false,'complete gym_manager claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000203","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"front_desk","staff_id":"78800000-0000-4000-8000-000000000123"}', true);
SELECT is(app.push_configuration_ready(),false,'complete front_desk claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000204","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"trainer","staff_id":"78800000-0000-4000-8000-000000000124"}', true);
SELECT is(app.push_configuration_ready(),false,'complete trainer claim reads tenant 82 readiness');
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.push_provider_configurations SET activated_at=NULL WHERE tenant_id='78800000-0000-4000-8000-000000000081';
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()-interval '1 minute' WHERE tenant_id='78800000-0000-4000-8000-000000000082';
SET LOCAL session_replication_role = origin;
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000081'),false,'B activation cannot enable A reciprocally');
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000082'),true,'B own activation enables B');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000111"}', true);
SELECT is(app.push_configuration_ready(),false,'complete gym_owner claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000202","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"gym_manager","staff_id":"78800000-0000-4000-8000-000000000112"}', true);
SELECT is(app.push_configuration_ready(),false,'complete gym_manager claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000203","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"front_desk","staff_id":"78800000-0000-4000-8000-000000000113"}', true);
SELECT is(app.push_configuration_ready(),false,'complete front_desk claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000204","tenant_id":"78800000-0000-4000-8000-000000000081","app_role":"trainer","staff_id":"78800000-0000-4000-8000-000000000114"}', true);
SELECT is(app.push_configuration_ready(),false,'complete trainer claim reads tenant 81 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),true,'complete gym_owner claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000202","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_manager","staff_id":"78800000-0000-4000-8000-000000000122"}', true);
SELECT is(app.push_configuration_ready(),true,'complete gym_manager claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000203","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"front_desk","staff_id":"78800000-0000-4000-8000-000000000123"}', true);
SELECT is(app.push_configuration_ready(),true,'complete front_desk claim reads tenant 82 readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000204","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"trainer","staff_id":"78800000-0000-4000-8000-000000000124"}', true);
SELECT is(app.push_configuration_ready(),true,'complete trainer claim reads tenant 82 readiness');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{}', true);
SELECT is(app.push_configuration_ready(),false,'missing claims never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'missing subject never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'missing tenant never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner"}', true);
SELECT is(app.push_configuration_ready(),false,'missing staff never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121","member_id":"78800000-0000-4000-8000-000000000301"}', true);
SELECT is(app.push_configuration_ready(),false,'mixed staff/member never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"member","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'member role with staff identity never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"super_admin","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'platform admin never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"platform_support","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT is(app.push_configuration_ready(),false,'platform support never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121","impersonation_session_id":"78800000-0000-4000-8000-000000000401"}', true);
SELECT is(app.push_configuration_ready(),false,'impersonation never borrows configured B readiness');
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"78800000-0000-4000-8000-000000000201","tenant_id":"78800000-0000-4000-8000-000000000082","app_role":"gym_owner","staff_id":"78800000-0000-4000-8000-000000000121"}', true);
SELECT ok(NOT has_function_privilege(current_user,'public.reserve_push_attempts(integer)','EXECUTE') AND NOT has_function_privilege(current_user,'public.authorize_push_attempt(uuid,uuid)','EXECUTE') AND NOT has_function_privilege(current_user,'public.finish_push_attempt(uuid,uuid,text,text,boolean)','EXECUTE'),'ready authenticated staff retains no transport authority');
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()+interval '1 day' WHERE tenant_id='78800000-0000-4000-8000-000000000082';
SET LOCAL session_replication_role = origin;
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000082'),false,'future tenant activation is not readiness');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='push_configuration_ready'),'no public readiness facade');
SELECT * FROM finish();
ROLLBACK;
