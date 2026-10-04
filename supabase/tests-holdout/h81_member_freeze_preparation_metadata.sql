-- Independent metadata supplement, derived only from frozen public preparation declaration.
-- Missing future objects must report TAP failures, never abort catalog inspection.
begin;
SET LOCAL search_path = public, extensions, pg_temp;
SELECT plan(20);

CREATE TEMP TABLE hp_relation AS
SELECT c.oid,c.relkind,c.relrowsecurity,c.relowner,c.relacl
FROM pg_catalog.pg_class c
WHERE c.oid=pg_catalog.to_regclass('app.slf_freeze_preparations');
CREATE TEMP TABLE hp_columns AS
SELECT a.attname::text name,pg_catalog.format_type(a.atttypid,a.atttypmod) type,
 a.attnotnull required
FROM pg_catalog.pg_attribute a JOIN hp_relation r ON r.oid=a.attrelid
WHERE a.attnum>0 AND NOT a.attisdropped;
CREATE TEMP TABLE hp_constraints AS
SELECT c.contype,c.confrelid,
 ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(num,pos)
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos) local_keys,
 ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(num,pos)
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos) foreign_keys
FROM pg_catalog.pg_constraint c JOIN hp_relation r ON c.conrelid=r.oid;
CREATE TEMP TABLE hp_triggers AS
SELECT t.tgname,t.tgtype::integer kind,t.tgdeferrable,t.tginitdeferred,
 t.tgconstraint,t.tgenabled,t.tgrelid,p.proname,n.nspname,p.proconfig,p.proacl,p.proowner,p.prosecdef
FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE NOT t.tgisinternal AND t.tgrelid IN
 (pg_catalog.to_regclass('public.membership_pauses'),pg_catalog.to_regclass('public.member_freeze_requests'));

SELECT ok(EXISTS(SELECT 1 FROM hp_relation WHERE relkind='r'),
 'Capability is a real private app relation, not a session marker');
SELECT is((SELECT array_agg(name||':'||type ORDER BY name) FROM hp_columns),ARRAY[
 'action:text','actor_user_id:uuid','command_key:uuid','expected_revision:bigint','facts:jsonb',
 'prepared_at:timestamp with time zone','request_id:uuid','source_pause_id:uuid','tenant_id:uuid','transaction_id:text']::text[],
 'Full transaction identity, actor/request binding and evidence have exact declared names/types');
SELECT is((SELECT array_agg(name ORDER BY name) FROM hp_columns WHERE required),ARRAY[
 'action','actor_user_id','command_key','expected_revision','facts','prepared_at','request_id','tenant_id','transaction_id']::text[],
 'Every preparation fact except pre-insertion source binding is mandatory');
SELECT ok(EXISTS(SELECT 1 FROM hp_columns WHERE name='source_pause_id' AND NOT required),
 'Adoption may begin with a null source binding');
SELECT ok(EXISTS(SELECT 1 FROM hp_constraints WHERE contype='p' AND local_keys=
 ARRAY['transaction_id','tenant_id','actor_user_id','command_key']::text[]),
 'Capability identity includes full transaction, tenant, actor and command');
SELECT ok(EXISTS(SELECT 1 FROM hp_constraints WHERE contype='f'
 AND confrelid=pg_catalog.to_regclass('public.organizations')
 AND local_keys=ARRAY['tenant_id']::text[] AND foreign_keys=ARRAY['id']::text[]),
 'Preparation tenant is bound to a real organization');
SELECT ok(EXISTS(SELECT 1 FROM hp_constraints WHERE contype='f'
 AND confrelid=pg_catalog.to_regclass('public.member_freeze_requests')
 AND ((local_keys=ARRAY['tenant_id','request_id']::text[]
 AND foreign_keys=ARRAY['tenant_id','id']::text[])
 OR (local_keys=ARRAY['request_id','tenant_id']::text[]
 AND foreign_keys=ARRAY['id','tenant_id']::text[]))),
 'Request reference preserves tenant instead of relying on a global request UUID');
SELECT ok(EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN hp_relation r ON r.oid=i.indrelid
 WHERE i.indisvalid AND i.indisready AND i.indpred IS NULL AND
 ARRAY(SELECT a.attname::text FROM unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num
 WHERE k.pos<=3 ORDER BY k.pos)=ARRAY['tenant_id','request_id','transaction_id']::text[]),
 'Scoped lookup has an unconditional usable tenant/request/transaction index');
SELECT ok(COALESCE((SELECT relrowsecurity FROM hp_relation),false),
 'Private preparation relation enables RLS');
SELECT ok(EXISTS(SELECT 1 FROM hp_relation) AND NOT EXISTS(
 SELECT 1 FROM pg_catalog.pg_policy p JOIN hp_relation r ON p.polrelid=r.oid),
 'No session policy opens preparation state');
SELECT ok(EXISTS(SELECT 1 FROM hp_relation r JOIN pg_catalog.pg_roles o ON o.oid=r.relowner WHERE o.rolname='postgres'),
 'Private capability is owned by postgres');
SELECT ok(EXISTS(SELECT 1 FROM hp_relation) AND NOT EXISTS(
 SELECT 1 FROM hp_relation r CROSS JOIN pg_catalog.pg_roles ordinary
 WHERE ordinary.rolname IN ('anon','authenticated','service_role')
 AND pg_catalog.has_table_privilege(ordinary.oid,r.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')),
 'No ordinary role including service_role holds any preparation privilege');
SELECT ok(EXISTS(SELECT 1 FROM hp_relation) AND NOT EXISTS(
 SELECT 1 FROM hp_relation r CROSS JOIN LATERAL pg_catalog.aclexplode(
 COALESCE(r.relacl,pg_catalog.acldefault('r',r.relowner))) a WHERE a.grantee=0),
 'PUBLIC has no capability relation privilege');

-- tgtype encodes ROW=1, BEFORE=2, INSERT=4, DELETE=8, UPDATE=16.
SELECT ok(EXISTS(SELECT 1 FROM hp_triggers WHERE tgname='membership_pauses_freeze_source_lock'
 AND tgrelid=pg_catalog.to_regclass('public.membership_pauses') AND kind=31 AND tgenabled IN ('O','A')),
 'Source binding/locking runs BEFORE every INSERT UPDATE DELETE');
SELECT ok(EXISTS(SELECT 1 FROM hp_triggers WHERE tgname='member_freeze_requests_source_consistency'
 AND tgrelid=pg_catalog.to_regclass('public.member_freeze_requests') AND kind=23 AND tgenabled IN ('O','A')),
 'Request scope consistency runs BEFORE every INSERT UPDATE');
SELECT ok(EXISTS(SELECT 1 FROM hp_triggers WHERE tgname='membership_pauses_freeze_source_deferred'
 AND tgrelid=pg_catalog.to_regclass('public.membership_pauses') AND kind=29 AND tgconstraint<>0
 AND tgdeferrable AND tginitdeferred AND tgenabled IN ('O','A')),
 'Source decision consistency is an initially deferred constraint for INSERT UPDATE DELETE');
SELECT ok(EXISTS(SELECT 1 FROM hp_triggers WHERE tgname='member_freeze_requests_source_deferred'
 AND tgrelid=pg_catalog.to_regclass('public.member_freeze_requests') AND kind=21 AND tgconstraint<>0
 AND tgdeferrable AND tginitdeferred AND tgenabled IN ('O','A')),
 'Request decision consistency is an initially deferred constraint for INSERT UPDATE');
SELECT is((SELECT count(*) FROM hp_triggers WHERE tgname IN
 ('membership_pauses_freeze_source_lock','member_freeze_requests_source_consistency',
 'membership_pauses_freeze_source_deferred','member_freeze_requests_source_deferred')
 AND nspname='app' AND proname='enforce_freeze_source_consistency'
 AND EXISTS(SELECT 1 FROM unnest(proconfig) setting WHERE setting IN ('search_path=""','search_path='))),4::bigint,
 'All four installed hooks reuse the declared empty-search-path consistency function');
SELECT ok(EXISTS(SELECT 1 FROM hp_triggers WHERE tgrelid=pg_catalog.to_regclass('public.membership_pauses')
 AND nspname='app' AND proname='enforce_freeze_source_consistency'
 AND (kind & 2)=0 AND (kind & 1)=1 AND (kind & 16)=16
 AND NOT tgdeferrable AND tgenabled IN ('O','A')),
 'Existing immediate source AFTER consistency check remains installed');
SELECT ok(EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='app' AND p.proname='enforce_freeze_source_consistency') AND NOT EXISTS(
 SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 WHERE n.nspname='app' AND p.proname='enforce_freeze_source_consistency'
 AND (a.grantee=0 OR a.grantee IN (SELECT oid FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated','service_role')))),
 'Consistency trigger function supplies no ordinary or PUBLIC EXECUTE bridge');

select * from finish();
rollback;
