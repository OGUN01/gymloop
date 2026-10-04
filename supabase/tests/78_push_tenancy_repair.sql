-- Independent visible author; frozen serial tenant contract, no migrations/source/other tests read.
BEGIN;
SET LOCAL ROLE postgres;
SET LOCAL search_path = public, extensions;
SELECT plan(39);
SELECT has_column('public', 'push_provider_configurations', 'tenant_id', 'configuration has a tenant path');
SELECT col_not_null('public', 'push_provider_configurations', 'tenant_id', 'tenant is mandatory');
SELECT col_is_pk('public', 'push_provider_configurations', 'tenant_id', 'one indexed primary configuration per tenant');
SELECT col_is_fk('public', 'push_provider_configurations', 'tenant_id', 'tenant references organization');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
  WHERE c.conrelid='public.push_provider_configurations'::regclass AND c.contype='f'
    AND c.confrelid='public.organizations'::regclass AND a.attname='tenant_id'
), 'configuration tenant FK references organizations');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.push_provider_configurations'::regclass), 'configuration RLS enabled');
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid='public.push_provider_configurations'::regclass), 0::bigint, 'no ordinary configuration policies');
SELECT has_column('public', 'push_provider_configurations', 'firebase_project_id', 'project identity retained');
SELECT has_column('public', 'push_provider_configurations', 'activated_at', 'tenant activation retained');
SELECT has_column('public', 'push_provider_configurations', 'created_at', 'creation timestamp retained');
SELECT has_column('public', 'push_provider_configurations', 'updated_at', 'revision timestamp retained');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.push_provider_configurations'::regclass AND attname='singleton' AND NOT attisdropped), 'global singleton removed');
SELECT ok(NOT has_table_privilege('anon','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anonymous has no direct configuration access');
SELECT ok(NOT has_table_privilege('authenticated','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'all product/platform JWT roles have no direct configuration access');
SELECT ok(NOT has_table_privilege('service_role','public.push_provider_configurations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'service transport has no direct configuration access');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) privilege
  WHERE c.oid='public.push_provider_configurations'::regclass AND privilege.grantee=0
), 'PUBLIC has no direct configuration grants');
-- Supplement: exact frozen readiness-and-oauth-declaration.md, 2026-10-04.
SELECT ok((SELECT prosecdef AND provolatile='s' AND proowner='postgres'::regrole AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid='app.push_configuration_ready(uuid)'::regprocedure), 'private readiness stable postgres definer with empty path');
SELECT ok((SELECT prosecdef AND provolatile='s' AND proowner='postgres'::regrole AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid='app.push_configuration_ready()'::regprocedure), 'claim readiness stable postgres definer with empty path');
SELECT ok(NOT has_function_privilege('anon','app.push_configuration_ready(uuid)','EXECUTE'), 'anon cannot select tenant');
SELECT ok(NOT has_function_privilege('authenticated','app.push_configuration_ready(uuid)','EXECUTE'), 'authenticated cannot select tenant');
SELECT ok(NOT has_function_privilege('service_role','app.push_configuration_ready(uuid)','EXECUTE'), 'service cannot select tenant');
SELECT ok(has_function_privilege('authenticated','app.push_configuration_ready()','EXECUTE'), 'authenticated composition retained');
SELECT ok(NOT has_function_privilege('anon','app.push_configuration_ready()','EXECUTE'), 'anon cannot invoke claim readiness');
SELECT ok(NOT has_function_privilege('service_role','app.push_configuration_ready()','EXECUTE'), 'service uses frozen facades');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid IN ('app.push_configuration_ready(uuid)'::regprocedure,'app.push_configuration_ready()'::regprocedure) AND a.grantee=0 AND a.privilege_type='EXECUTE'), 'PUBLIC cannot execute either seam');
INSERT INTO public.organizations(id,name,gym_code) VALUES
 ('78000000-0000-4000-8000-000000000071','Readiness A','NTF78A'),
 ('78000000-0000-4000-8000-000000000072','Readiness B','NTF78B');
SELECT is(app.push_configuration_ready(NULL::uuid),false,'null tenant unconfigured');
SELECT is(app.push_configuration_ready('78000000-0000-4000-8000-000000000071'::uuid),false,'absent configuration unconfigured');
INSERT INTO public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) VALUES
 ('78000000-0000-4000-8000-000000000071','samuraiapi-51996',statement_timestamp());
SELECT is(app.push_configuration_ready('78000000-0000-4000-8000-000000000071'::uuid),true,'activation equality ready');
SELECT is(app.push_configuration_ready('78000000-0000-4000-8000-000000000072'::uuid),false,'configured A cannot enable absent B');
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()+interval '1 day' WHERE tenant_id='78000000-0000-4000-8000-000000000071';
SELECT is(app.push_configuration_ready('78000000-0000-4000-8000-000000000071'::uuid),false,'future activation unready');
UPDATE public.push_provider_configurations SET activated_at=statement_timestamp()-interval '1 day' WHERE tenant_id='78000000-0000-4000-8000-000000000071';
SELECT is(app.push_configuration_ready('78000000-0000-4000-8000-000000000071'::uuid),true,'past activation ready');
SELECT set_config('request.jwt.claims','',true);
SET LOCAL ROLE authenticated;
SELECT is(app.push_configuration_ready(),false,'missing claims unready');
SELECT set_config('request.jwt.claims','{"role":"authenticated","app_role":"super_admin","tenant_id":"78000000-0000-4000-8000-000000000071","platform_user_id":"78000000-0000-4000-8000-000000000073"}',true);
SELECT is(app.push_configuration_ready(),false,'platform claims unready');
SELECT set_config('request.jwt.claims','{"role":"authenticated","app_role":"member","tenant_id":"78000000-0000-4000-8000-000000000071"}',true);
SELECT is(app.push_configuration_ready(),false,'incomplete member claims unready');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"78000000-0000-4000-8000-000000000074","app_role":"member","tenant_id":"78000000-0000-4000-8000-000000000071","member_id":"78000000-0000-4000-8000-000000000075","staff_id":"78000000-0000-4000-8000-000000000076"}',true);
SELECT is(app.push_configuration_ready(),false,'mixed member staff claims unready');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"78000000-0000-4000-8000-000000000074","app_role":"gym_owner","tenant_id":"78000000-0000-4000-8000-000000000071","staff_id":"78000000-0000-4000-8000-000000000076","impersonation_session_id":"78000000-0000-4000-8000-000000000077"}',true);
SELECT is(app.push_configuration_ready(),false,'impersonation claims unready');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"78000000-0000-4000-8000-000000000074","app_role":"member","tenant_id":"78000000-0000-4000-8000-000000000071","member_id":"78000000-0000-4000-8000-000000000075"}',true);
SELECT is(app.push_configuration_ready(),true,'complete member guard sees its ready tenant');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"78000000-0000-4000-8000-000000000074","app_role":"gym_owner","tenant_id":"78000000-0000-4000-8000-000000000071","staff_id":"78000000-0000-4000-8000-000000000076"}',true);
SELECT is(app.push_configuration_ready(),true,'complete staff guard sees its ready tenant');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"78000000-0000-4000-8000-000000000074","app_role":"member","tenant_id":"78000000-0000-4000-8000-000000000072","member_id":"78000000-0000-4000-8000-000000000075"}',true);
SELECT is(app.push_configuration_ready(),false,'claim guard never inherits another tenant readiness');
SET LOCAL ROLE postgres;
SELECT * FROM finish();
ROLLBACK;


