-- Independent holdout derived solely from the frozen 2026-10-04 tenancy/readiness packet.
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT plan(22);
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
UPDATE public.push_provider_configurations SET activated_at=NULL WHERE tenant_id='78800000-0000-4000-8000-000000000081';
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()-interval '1 minute' WHERE tenant_id='78800000-0000-4000-8000-000000000082';
SET LOCAL session_replication_role = origin;
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000081'),false,'B activation cannot enable A reciprocally');
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000082'),true,'B own activation enables B');
SET LOCAL session_replication_role = replica;
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()+interval '1 day' WHERE tenant_id='78800000-0000-4000-8000-000000000082';
SET LOCAL session_replication_role = origin;
SELECT is(app.push_configuration_ready('78800000-0000-4000-8000-000000000082'),false,'future tenant activation is not readiness');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='push_configuration_ready'),'no public readiness facade');
SELECT * FROM finish();
ROLLBACK;
