-- h10_platform_holdout.sql
-- Holdout pgTAP suite, Phase 1 `platform` cluster:
--   platform_users, impersonation_sessions, audit_log, leads, member_imports
--
-- Written from openspec/changes/0001-data-model/specs/platform/spec.md,
-- docs/data-model.md (Conventions in full, Cluster: platform, Enums),
-- docs/domain-rules.md (INT-001, INT-003) and docs/security.md
-- (Impersonation, Audit logging). No migration and no visible test file was read.
--
-- Every fixture uuid is prefixed 00000000-0000-4000-8000-0000010 so a combined
-- run alongside another cluster's suite cannot collide.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(165);

-- ===========================================================================
-- 1. The two tenant-path exceptions, and that they are exactly two (ADR-033)
-- ===========================================================================

select hasnt_column('public', 'platform_users', 'tenant_id',
  'ADR-033 first exemption: docs/data-model.md Tenant-path exceptions');

select col_is_null('public', 'audit_log', 'tenant_id',
  'ADR-033 second exemption: docs/data-model.md Tenant-path exceptions');

select col_not_null('public', 'impersonation_sessions', 'tenant_id',
  'spec: A gym can see who impersonated it - tenant path is direct');

select col_not_null('public', 'leads', 'tenant_id',
  'gate 6 / AGENTS.md rule 9 for leads');

select col_not_null('public', 'member_imports', 'tenant_id',
  'gate 6 / AGENTS.md rule 9 for member_imports');

select is(
  (select array_agg(c.relname::text collate "default" order by c.relname::text collate "default")
     from pg_catalog.pg_class c
     left join pg_catalog.pg_attribute a
       on a.attrelid = c.oid
      and a.attname::text collate "default" = 'tenant_id'
      and a.attnum > 0
      and not a.attisdropped
    where c.relnamespace = 'public'::regnamespace
      and c.relkind = 'r'
      and c.relname::text collate "default" <> 'organizations'
      and a.attname is null),
  array['platform_users']::text[],
  'ADR-033: the tenant-path exemption is a closed list of one non-tenant table');

select is(
  (select array_agg(c.relname::text collate "default" order by c.relname::text collate "default")
     from pg_catalog.pg_class c
     join pg_catalog.pg_attribute a
       on a.attrelid = c.oid
      and a.attname::text collate "default" = 'tenant_id'
      and a.attnum > 0
      and not a.attisdropped
    where c.relnamespace = 'public'::regnamespace
      and c.relkind = 'r'
      and not a.attnotnull),
  array['audit_log']::text[],
  'ADR-033: audit_log is the only table whose tenant_id is nullable');

-- ===========================================================================
-- 2. Column shape the cluster promises
-- ===========================================================================

select col_is_pk('public', 'platform_users', 'user_id',
  'spec: Platform accounts - the natural key is the auth user');

select fk_ok('public', 'platform_users', 'user_id', 'auth', 'users', 'id',
  'spec: Platform accounts are real auth identities');

select is(
  (select con.confdeltype::text collate "default"
     from pg_catalog.pg_constraint con
    where con.conrelid = to_regclass('public.platform_users')
      and con.contype = 'f'
      and con.confrelid = to_regclass('auth.users')),
  'c',
  'docs/data-model.md Cluster: platform - platform_users.user_id is on delete cascade');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.platform_users')
      and a.attname::text collate "default" = 'role'),
  'app_role',
  'ADR-031: platform_users.role draws on the one role vocabulary');

select col_not_null('public', 'impersonation_sessions', 'reason',
  'docs/security.md Impersonation: a mandatory typed reason');

select col_not_null('public', 'impersonation_sessions', 'expires_at',
  'docs/security.md Impersonation: a hard TTL, not an indefinite session');

select col_not_null('public', 'impersonation_sessions', 'actor_user_id',
  'INT-003: an impersonation session names its actor');

select col_is_null('public', 'impersonation_sessions', 'ended_at',
  'docs/security.md Impersonation: a running session has not ended yet');

select hasnt_column('public', 'impersonation_sessions', 'updated_at',
  'docs/data-model.md Every table: no updated_at means no touch trigger');

select col_not_null('public', 'audit_log', 'action',
  'INT-003: an audit row records the action');

select col_not_null('public', 'audit_log', 'record_type',
  'INT-003: an audit row records the record type');

select col_not_null('public', 'audit_log', 'occurred_at',
  'INT-003: an audit row records a timestamp');

select col_is_null('public', 'audit_log', 'actor_user_id',
  'ADR-033: a platform-level audit row need not name a gym-side actor');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.audit_log')
      and a.attname::text collate "default" = 'actor_role'),
  'app_role',
  'ADR-031: audit_log.actor_role draws on the one role vocabulary');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.audit_log')
      and a.attname::text collate "default" = 'before'),
  'jsonb',
  'INT-003: the before summary is jsonb, never json');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.audit_log')
      and a.attname::text collate "default" = 'after'),
  'jsonb',
  'INT-003: the after summary is jsonb, never json');

select hasnt_column('public', 'audit_log', 'updated_at',
  'docs/data-model.md Audit rows: an audit row is never revised');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.leads')
      and a.attname::text collate "default" = 'source'),
  'lead_source',
  'spec: A lead source outside the vocabulary - source is the enum');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.leads')
      and a.attname::text collate "default" = 'stage'),
  'lead_stage',
  'spec: A converted lead names the member it became - stage is the enum');

select col_not_null('public', 'leads', 'phone',
  'spec: A lead phone number that is not E.164');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.member_imports')
      and a.attname::text collate "default" = 'status'),
  'import_status',
  'spec: An import run records its mapping - status is the enum');

select is(
  (select t.typname::text collate "default"
     from pg_catalog.pg_attribute a
     join pg_catalog.pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.member_imports')
      and a.attname::text collate "default" = 'column_mapping'),
  'jsonb',
  'spec: An import run records its mapping - the mapping is jsonb');

select col_not_null('public', 'member_imports', 'column_mapping',
  'spec: An import run records its mapping');

-- ===========================================================================
-- 3. Foreign keys across the cluster seam
-- ===========================================================================

select fk_ok('public', 'impersonation_sessions', 'tenant_id', 'public', 'organizations', 'id',
  'spec: A gym reading its own impersonation history - the target gym');

select fk_ok('public', 'impersonation_sessions', 'actor_user_id', 'public', 'platform_users', 'user_id',
  'docs/security.md Impersonation: only a platform user can impersonate');

select fk_ok('public', 'audit_log', 'impersonation_session_id', 'public', 'impersonation_sessions', 'id',
  'INT-003: an audit row can be attributed to the impersonation that produced it');

select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.leads'::regclass and c.contype = 'f'
     and c.confrelid = 'public.members'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'converted_member_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'spec: A converted lead names the member it became - and since ADR-052 by (tenant_id, converted_member_id) references members (tenant_id, id), so the member it became is one of this gym''s');

select ok( exists (
  select 1 from pg_constraint c
   where c.conrelid = 'public.member_imports'::regclass and c.contype = 'f'
     and c.confrelid = 'public.staff'::regclass
     and c.conkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'uploaded_by_staff_id')]
     and c.confkey = array[
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id'),
       (select a.attnum from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'id')]),
  'spec: An import by nobody - the uploader is a staff row, and since ADR-052 by (tenant_id, uploaded_by_staff_id) references staff (tenant_id, id), so the uploader works at the gym whose members are being imported');

-- ===========================================================================
-- 4. The three enums the platform cluster owns, in the order the contract fixes
-- ===========================================================================

select is(
  (select array_agg(e.enumlabel::text collate "default" order by e.enumsortorder)
     from pg_catalog.pg_type t
     join pg_catalog.pg_enum e on e.enumtypid = t.oid
    where t.typnamespace = 'public'::regnamespace
      and t.typname::text collate "default" = 'lead_source'),
  array['walk_in', 'referral', 'instagram', 'google', 'website', 'phone', 'other']::text[],
  'docs/data-model.md Enums: lead_source label set and order');

select is(
  (select array_agg(e.enumlabel::text collate "default" order by e.enumsortorder)
     from pg_catalog.pg_type t
     join pg_catalog.pg_enum e on e.enumtypid = t.oid
    where t.typnamespace = 'public'::regnamespace
      and t.typname::text collate "default" = 'lead_stage'),
  array['new', 'contacted', 'trial_scheduled', 'trial_done', 'converted', 'lost']::text[],
  'docs/data-model.md Enums: lead_stage label set and order');

select is(
  (select array_agg(e.enumlabel::text collate "default" order by e.enumsortorder)
     from pg_catalog.pg_type t
     join pg_catalog.pg_enum e on e.enumtypid = t.oid
    where t.typnamespace = 'public'::regnamespace
      and t.typname::text collate "default" = 'import_status'),
  array['pending', 'processing', 'completed', 'failed']::text[],
  'docs/data-model.md Enums: import_status label set and order');

-- ===========================================================================
-- 5. RLS is on, force is off, and the policy set is exactly the contract's
-- ===========================================================================

select is(
  (select count(*)::int
     from pg_catalog.pg_class c
    where c.oid in (to_regclass('public.platform_users'),
                    to_regclass('public.impersonation_sessions'),
                    to_regclass('public.audit_log'),
                    to_regclass('public.leads'),
                    to_regclass('public.member_imports'))
      and c.relrowsecurity),
  5,
  'gate 7: row security is enabled on every platform-cluster table');

select is(
  (select count(*)::int
     from pg_catalog.pg_class c
    where c.oid in (to_regclass('public.platform_users'),
                    to_regclass('public.impersonation_sessions'),
                    to_regclass('public.audit_log'),
                    to_regclass('public.leads'),
                    to_regclass('public.member_imports'))
      and c.relforcerowsecurity),
  0,
  'ADR-037: no platform-cluster table forces row level security');

-- platform_users is the one table with no gym-side path at all. Phase 2 split its
-- platform policy in two so a support account cannot promote itself, so the durable
-- statement of "visible only to the platform" is that no policy on it consults the
-- tenant claim -- which no rename can make false.
select is_empty($q$
  select 'policy consults the tenant claim: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.platform_users')
     and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%'
       or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%current_tenant_id%')
  union all
  select 'no policy on platform_users at all'
   where not exists (select 1 from pg_policy p
                      where p.polrelid = to_regclass('public.platform_users'))
$q$, 'spec: Platform accounts are visible only to the platform - no policy on it reads the tenant claim');

-- "and change nothing about it" is the durable half: whatever the gym-side policies
-- are called, none of them may admit anything but SELECT.
--
-- Two things about impersonation_sessions_impersonator_write, and they are different
-- kinds of exception.
--
-- Its NAME is listed below rather than added to the five-suffix vocabulary, because it
-- is a sixth name on one table and not a sixth template: a second table growing an
-- _impersonator_write would be a mistake, and an exception naming this table keeps
-- saying so where a wider vocabulary would not.
--
-- Its GATE is exempted by shape, never by name, in the third clause. There are three
-- audiences in public and not two: a policy speaks to the platform (is_platform() or
-- = 'super_admin'), to a gym (a tenant claim plus a role), or -- on this one table --
-- to the impersonator, which is neither. That session carries a gym's tenant_id and
-- app_role gym_owner while belonging to a platform user, so anything classifying by
-- "not is_platform()" sorts it onto the gym side, where a write policy is a defect.
-- The distinction that keeps the rule sharp is the predicate: a policy admitting more
-- than SELECT here is a defect UNLESS it requires an impersonation claim on both of
-- its clauses. Exempting the name instead would pass a future _impersonator_write that
-- had lost that term, which is the exact widening this table has been through twice.
--
-- And the requirement this assertion defends is untouched by the exception, which is
-- why it is safe rather than a hole: a gym-side session carries no
-- impersonation_session_id, so app.current_impersonation_id() is null, `id = null` is
-- null rather than true, and the policy reaches no row. A gym still changes nothing
-- about its impersonation history. What reaches it is a session that IS the
-- impersonation, and only to end it.
select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.impersonation_sessions')
     and p.polname::text collate "default" not in ('impersonation_sessions_platform_select', 'impersonation_sessions_platform_write', 'impersonation_sessions_tenant_select', 'impersonation_sessions_tenant_write', 'impersonation_sessions_member_select', 'impersonation_sessions_impersonator_write')
  union all
  select 'missing policy: ' || x from unnest(array['impersonation_sessions_tenant_select', 'impersonation_sessions_platform_select']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.impersonation_sessions')
                      and p.polname::text collate "default" = x)
  union all
  select 'a gym-side policy admits more than select: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.impersonation_sessions')
     and p.polcmd <> 'r'
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%'
     and not (coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_impersonation_id%'
          and coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%current_impersonation_id%')
$q$, 'spec: A gym can see who impersonated it, and change nothing about it -- only the impersonation itself does');

-- ADR-047/049 made audit_log read-only to the gym by grant; Phase 2 makes the policy
-- say the same thing. Asserted as: no gym-side policy on audit_log admits a write.
select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.audit_log')
     and p.polname::text collate "default" not in ('audit_log_platform_select', 'audit_log_platform_write', 'audit_log_tenant_select', 'audit_log_tenant_write', 'audit_log_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['audit_log_tenant_select', 'audit_log_platform_select']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.audit_log')
                      and p.polname::text collate "default" = x)
  union all
  select 'a gym-side policy admits more than select: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.audit_log')
     and p.polcmd <> 'r'
     and coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%current_tenant_id%'
$q$, 'INT-001: no gym-side policy on audit_log admits a write, whatever it is called');

select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.leads')
     and p.polname::text collate "default" not in ('leads_platform_select', 'leads_platform_write', 'leads_tenant_select', 'leads_tenant_write', 'leads_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['leads_tenant_select', 'leads_platform_select', 'leads_tenant_write', 'leads_platform_write']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.leads')
                      and p.polname::text collate "default" = x)
$q$, 'gate 7: leads carries only sanctioned policy names, gym-side and platform-side reads among them');

select is_empty($q$
  select 'unsanctioned policy: ' || p.polname::text collate "default"
    from pg_policy p where p.polrelid = to_regclass('public.member_imports')
     and p.polname::text collate "default" not in ('member_imports_platform_select', 'member_imports_platform_write', 'member_imports_tenant_select', 'member_imports_tenant_write', 'member_imports_member_select')
  union all
  select 'missing policy: ' || x from unnest(array['member_imports_tenant_select', 'member_imports_platform_select', 'member_imports_tenant_write', 'member_imports_platform_write']) x
   where not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.member_imports')
                      and p.polname::text collate "default" = x)
$q$, 'gate 7: member_imports carries only sanctioned policy names, gym-side and platform-side reads among them');

select is(
  (select p.polcmd::text collate "default"
     from pg_catalog.pg_policy p
    where p.polrelid = to_regclass('public.impersonation_sessions')
      and p.polname::text collate "default" = 'impersonation_sessions_tenant_select'),
  'r',
  'spec: A gym inventing an impersonation session - the tenant policy is select only');

select is(
  (select p.polcmd::text collate "default"
     from pg_catalog.pg_policy p
    where p.polrelid = to_regclass('public.impersonation_sessions')
      and p.polname::text collate "default" = 'impersonation_sessions_platform_write'),
  '*',
  'docs/security.md Impersonation: the platform branch writes the session');

-- ===========================================================================
-- 6. Privileges - read-only and append-only are grants, not guards
--    (INT-001, INT-003, ADR-047)
-- ===========================================================================

select ok(
  has_table_privilege('authenticated', to_regclass('public.audit_log'), 'SELECT')
  and not has_table_privilege('authenticated', to_regclass('public.audit_log'), 'INSERT'),
  'INT-003/ADR-047: audit_log is the read-only tier - a signed-in caller may read audit rows and may not append one, or it could forge a row naming a platform actor');

select ok(
  not has_table_privilege('authenticated', to_regclass('public.audit_log'), 'UPDATE'),
  'spec: Editing an audit row - no update privilege exists to lose');

select ok(
  not has_table_privilege('authenticated', to_regclass('public.audit_log'), 'DELETE'),
  'spec: Deleting an audit row - INT-001 applies to audit rows themselves');

select ok(
  not has_table_privilege('authenticated', to_regclass('public.audit_log'), 'TRUNCATE'),
  'ADR-037: truncate is not filtered by RLS, so it is not granted');

select ok(
  has_table_privilege('authenticated', to_regclass('public.impersonation_sessions'), 'SELECT')
  and has_table_privilege('authenticated', to_regclass('public.impersonation_sessions'), 'INSERT')
  and has_table_privilege('authenticated', to_regclass('public.impersonation_sessions'), 'UPDATE'),
  'docs/data-model.md Privileges: impersonation_sessions is the history tier');

select ok(
  not has_table_privilege('authenticated', to_regclass('public.impersonation_sessions'), 'DELETE'),
  'INT-001: authenticated holds no delete on impersonation_sessions');

select ok(
  has_table_privilege('authenticated', to_regclass('public.leads'), 'SELECT')
  and has_table_privilege('authenticated', to_regclass('public.leads'), 'INSERT')
  and has_table_privilege('authenticated', to_regclass('public.leads'), 'UPDATE')
  and has_table_privilege('authenticated', to_regclass('public.member_imports'), 'SELECT')
  and has_table_privilege('authenticated', to_regclass('public.member_imports'), 'INSERT')
  and has_table_privilege('authenticated', to_regclass('public.member_imports'), 'UPDATE'),
  'docs/data-model.md Privileges: leads and member_imports are the normal tier');

select ok(
  not (has_table_privilege('authenticated', to_regclass('public.platform_users'), 'DELETE')
    or has_table_privilege('authenticated', to_regclass('public.leads'), 'DELETE')
    or has_table_privilege('authenticated', to_regclass('public.member_imports'), 'DELETE')
    or has_table_privilege('authenticated', to_regclass('public.platform_users'), 'TRUNCATE')
    or has_table_privilege('authenticated', to_regclass('public.leads'), 'TRUNCATE')
    or has_table_privilege('authenticated', to_regclass('public.member_imports'), 'TRUNCATE')),
  'ADR-037: delete is granted to authenticated on no Phase 1 table');

select ok(
  not (has_table_privilege('anon', to_regclass('public.platform_users'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.impersonation_sessions'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.audit_log'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.leads'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.member_imports'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.leads'), 'INSERT')
    or has_table_privilege('anon', to_regclass('public.audit_log'), 'INSERT')),
  'ADR-037: anon is granted nothing on any platform-cluster table');

-- ===========================================================================
-- 7. Indexes on the RLS path (gate 8)
-- ===========================================================================

select is(
  (select count(*)::int
     from (values ('public.impersonation_sessions'),
                  ('public.audit_log'),
                  ('public.leads'),
                  ('public.member_imports')) as t(rel)
    where exists (
      select 1
        from pg_catalog.pg_index i
        join pg_catalog.pg_class ic on ic.oid = i.indexrelid
        join pg_catalog.pg_am am on am.oid = ic.relam
        join pg_catalog.pg_attribute a
          on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
       where i.indrelid = to_regclass(t.rel)
         and i.indpred is null
         and am.amname::text collate "default" = 'btree'
         and a.attname::text collate "default" = 'tenant_id')),
  4,
  'gate 8: every tenant-scoped platform table leads a non-partial btree with tenant_id');

-- ===========================================================================
-- 8. Nothing writes to audit_log in Phase 1, and the only trigger anywhere is
--    the shared touch_updated_at (docs/data-model.md Audit rows)
-- ===========================================================================

select is(
  (select count(*)::int
     from pg_catalog.pg_trigger tg
    where tg.tgrelid = to_regclass('public.audit_log')
      and not tg.tgisinternal),
  0,
  'docs/data-model.md Audit rows: no trigger writes or guards audit_log');

select is(
  (select count(*)::int
     from pg_catalog.pg_trigger tg
     join pg_catalog.pg_class c on c.oid = tg.tgrelid
     join pg_catalog.pg_proc p on p.oid = tg.tgfoid
     join pg_catalog.pg_namespace pn on pn.oid = p.pronamespace
    where not tg.tgisinternal
      and c.relnamespace = 'public'::regnamespace
      and c.relkind = 'r'
      and pn.nspname::text collate "default" <> 'app'),
  0,
  'docs/data-model.md app schema: every trigger function lives in app, never in public');

select is(
  (select count(*)::int
     from pg_catalog.pg_trigger tg
     join pg_catalog.pg_class c on c.oid = tg.tgrelid
    where not tg.tgisinternal
      and c.relnamespace = 'public'::regnamespace
      and c.relkind = 'r'
      and tg.tgname::text collate "default"
          not like (c.relname::text collate "default") || '\_%'),
  0,
  'docs/data-model.md Naming: every trigger is named for the table it sits on');

-- Phase 1's "no database function writes audit_log" can never be true again: design.md
-- sections 6 and 7 make the database the only writer, because audit_log is read-only to
-- authenticated and a caller who must remember is a caller who will forget. Inverted
-- rather than deleted, because the inverse is the property that actually protects the
-- table: the writers live in `app`, not on the typed public API surface, and each one
-- must be security definer, since a signed-in caller's own rights could never insert
-- the row.
select ok(
  (select count(*)::int
     from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where p.prosrc ~* 'insert into[[:space:]]+(public\.)?audit_log'
      and (n.nspname::text collate "default" = 'public'
        or (n.nspname::text collate "default" = 'app' and not p.prosecdef))) = 0
  and (select count(*)::int
         from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where n.nspname::text collate "default" = 'app'
          and p.prosrc ~* 'audit_log'
          and p.prosecdef) > 0,
  'INT-003: audit_log is written by security definer functions in app, by at least one of them, and by nothing in public');

-- Counting every trigger on these tables pinned "Phase 1 adds nothing else", and
-- Phase 2 adds a revocation trigger to platform_users on purpose. The requirement was
-- always that each table with updated_at carries the shared trigger, so that is what
-- is counted -- by name, which does not move when a table gains another trigger.
select is(
  (select count(*)::int
     from pg_catalog.pg_trigger tg
     join pg_catalog.pg_class c on c.oid = tg.tgrelid
    where not tg.tgisinternal
      and tg.tgrelid in (to_regclass('public.platform_users'),
                         to_regclass('public.leads'),
                         to_regclass('public.member_imports'))
      and tg.tgname::text collate "default"
          = (c.relname::text collate "default") || '_touch_updated_at'),
  3,
  'docs/data-model.md Every table: the three platform tables with updated_at carry the shared trigger');

-- ===========================================================================
-- 9. Fixtures, inserted as the owner. postgres holds BYPASSRLS, so row
--    security does not apply here, and every isolation assertion below runs after
--    `set local role authenticated`. Both the role and the claims are
--    transaction-local and the closing rollback unwinds them.
-- ===========================================================================

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-00000100000a'::uuid, 'Holdout Platform Gym A', 'PLAT0A'),
  ('00000000-0000-4000-8000-00000100000b'::uuid, 'Holdout Platform Gym B', 'PLAT0B');

insert into public.branches (id, tenant_id, name) values
  ('00000000-0000-4000-8000-00000100001a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid, 'Holdout Branch A'),
  ('00000000-0000-4000-8000-00000100001b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid, 'Holdout Branch B');

insert into public.staff (id, tenant_id, role, full_name) values
  ('00000000-0000-4000-8000-00000100002a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid, 'front_desk', 'Holdout Staff A'),
  ('00000000-0000-4000-8000-00000100002b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid, 'front_desk', 'Holdout Staff B');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('00000000-0000-4000-8000-00000100003a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
   '00000000-0000-4000-8000-00000100001a'::uuid, 'Holdout Member A', '+919000000001'),
  ('00000000-0000-4000-8000-00000100003b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
   '00000000-0000-4000-8000-00000100001b'::uuid, 'Holdout Member B', '+919000000002');

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000100004a'::uuid, 'holdout-platform-1@gymloop.invalid'),
  ('00000000-0000-4000-8000-00000100004b'::uuid, 'holdout-platform-2@gymloop.invalid'),
  ('00000000-0000-4000-8000-00000100004c'::uuid, 'holdout-platform-3@gymloop.invalid'),
  ('00000000-0000-4000-8000-00000100004d'::uuid, 'holdout-platform-4@gymloop.invalid'),
  ('00000000-0000-4000-8000-00000100004e'::uuid, 'holdout-platform-5@gymloop.invalid');

insert into public.platform_users (user_id, role, full_name, email) values
  ('00000000-0000-4000-8000-00000100004a'::uuid, 'super_admin', 'Holdout Super Admin', 'holdout-platform-1@gymloop.invalid'),
  ('00000000-0000-4000-8000-00000100004b'::uuid, 'platform_support', 'Holdout Support', 'holdout-platform-2@gymloop.invalid'),
  -- A second super admin, because design.md section 6 permits one OPEN impersonation
  -- session per actor and this file needs more than one open at a time. Deliberately
  -- not 004d, which section 11 inserts itself to prove platform_support is a legal role.
  ('00000000-0000-4000-8000-00000100004e'::uuid, 'super_admin', 'Holdout Second Admin', 'holdout-platform-5@gymloop.invalid');

-- One open session per actor (impersonation_sessions_actor_user_id_open_key), so the
-- two gyms' sessions belong to two different actors rather than one.
insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at) values
  ('00000000-0000-4000-8000-00000100005a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
   '00000000-0000-4000-8000-00000100004a'::uuid, 'holdout support session', now() + interval '1 hour'),
  ('00000000-0000-4000-8000-00000100005b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
   '00000000-0000-4000-8000-00000100004b'::uuid, 'holdout support session', now() + interval '1 hour');

insert into public.audit_log (id, tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after) values
  ('00000000-0000-4000-8000-00000100006a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
   '00000000-0000-4000-8000-00000100004a'::uuid, 'super_admin', 'membership.cancelled', 'membership',
   '00000000-0000-4000-8000-00000100003a'::uuid, '{"status": "active"}'::jsonb, '{"status": "cancelled"}'::jsonb),
  ('00000000-0000-4000-8000-00000100006b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
   '00000000-0000-4000-8000-00000100004a'::uuid, 'super_admin', 'payment.refunded', 'payment',
   '00000000-0000-4000-8000-00000100003b'::uuid, null, null),
  ('00000000-0000-4000-8000-00000100006c'::uuid, null,
   '00000000-0000-4000-8000-00000100004a'::uuid, 'super_admin', 'platform_user.role_changed', 'platform_user',
   '00000000-0000-4000-8000-00000100004b'::uuid, null, null);

insert into public.leads (id, tenant_id, branch_id, full_name, phone, source) values
  ('00000000-0000-4000-8000-00000100007a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
   '00000000-0000-4000-8000-00000100001a'::uuid, 'Lead A', '+919000000011', 'walk_in'),
  ('00000000-0000-4000-8000-00000100007b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
   '00000000-0000-4000-8000-00000100001b'::uuid, 'Lead B', '+919000000012', 'instagram');

insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping) values
  ('00000000-0000-4000-8000-00000100008a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
   '00000000-0000-4000-8000-00000100002a'::uuid, 'gyma.csv', '{"Name": "full_name"}'::jsonb),
  ('00000000-0000-4000-8000-00000100008b'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
   '00000000-0000-4000-8000-00000100002b'::uuid, 'gymb.csv', '{"Name": "full_name"}'::jsonb);

-- ===========================================================================
-- 10. Column defaults, observed rather than read off the catalogue
-- ===========================================================================

select is(
  (select l.stage::text collate "default" from public.leads l
    where l.id = '00000000-0000-4000-8000-00000100007a'::uuid),
  'new',
  'docs/data-model.md Cluster: platform - a new lead starts at stage new');

select is(
  (select m.status::text collate "default" from public.member_imports m
    where m.id = '00000000-0000-4000-8000-00000100008a'::uuid),
  'pending',
  'spec: An import run records its mapping - a new run starts pending');

select is(
  (select p.is_active from public.platform_users p
    where p.user_id = '00000000-0000-4000-8000-00000100004a'::uuid),
  true,
  'docs/data-model.md Cluster: platform - a platform account is active by default');

select ok(
  (select s.started_at is not null and s.created_at is not null
     from public.impersonation_sessions s
    where s.id = '00000000-0000-4000-8000-00000100005a'::uuid),
  'docs/security.md Impersonation: a session stamps its own start');

select ok(
  (select a.occurred_at is not null from public.audit_log a
    where a.id = '00000000-0000-4000-8000-00000100006a'::uuid),
  'INT-003: an audit row stamps when the thing it records happened');

-- ===========================================================================
-- 11. Structural promises, exercised as the owner so only the constraint can
--     be what refuses the write
-- ===========================================================================

select throws_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
     values ('00000000-0000-4000-8000-000001000090'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, '', now() + interval '1 hour')$q$,
  '23514', null,
  'spec: A session with no stated reason');

select throws_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('00000000-0000-4000-8000-000001000091'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'holdout', now(), now())$q$,
  '23514', null,
  'spec: A session that never expires - expiry equal to start is not after it');

select lives_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
     values ('00000000-0000-4000-8000-00000100009a'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004e'::uuid, 'holdout valid session', now() + interval '30 minutes')$q$,
  'docs/security.md Impersonation: a reason plus a later expiry is accepted');

select throws_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at)
     values ('00000000-0000-4000-8000-000001000097'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'holdout backwards session',
             now(), now() + interval '1 hour', now() - interval '1 hour')$q$,
  '23514', null,
  'ADR-047: a session that ended before it began is rejected - the eight-year legal-hold record cannot say that');

select lives_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at)
     values ('00000000-0000-4000-8000-00000100009e'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'holdout closed session',
             now() - interval '1 hour', now() + interval '30 minutes', now())$q$,
  'ADR-047: an end after the start is accepted, and the null case above shows an open session still stores nothing there');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000092'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '', 'payment')$q$,
  '23514', null,
  'spec: An audit row with no action');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000093'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             'refunded', 'payment')$q$,
  '23514', null,
  'docs/data-model.md Audit rows: an action with no dot is not record_type.verb');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000094'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             'Payment.Refunded', 'payment')$q$,
  '23514', null,
  'docs/data-model.md Audit rows: both halves of the action are lowercase snake_case');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000095'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             'payment.refunded', '')$q$,
  '23514', null,
  'INT-003: an audit row names the record type it concerns');

select lives_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-00000100009b'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             'attendance.corrected', 'attendance')$q$,
  'docs/data-model.md Audit rows: record_type.verb is the accepted form');

select lives_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-00000100009c'::uuid, null,
             'impersonation_session.started', 'impersonation_session')$q$,
  'ADR-033: a platform-level audit row carries no tenant');

-- Harness repair (ADR-060/120): the INSERT discipline is no longer gated on
-- the writer's role, so an owner inserting at a non-new stage is refused by
-- app.enforce_lead_discipline() (GL060) before the converted-member CHECK can
-- speak. The refusal itself is what this assertion has always demanded.
select throws_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source, stage)
     values ('00000000-0000-4000-8000-000001000096'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Unconverted', '+919000000021', 'walk_in', 'converted')$q$,
  'GL060', null,
  'spec: A converted lead with no member');

-- Harness repair (ADR-060/098/120): a converted or lost history row now
-- enters only through an explicit bypass — the discipline binds the owner
-- too. Replica role so the fixture, not the enforcement trigger, is what the
-- CHECK constraint judges; the named-converted and lost-with-reason cases it
-- accepts are unchanged.
set local session_replication_role = replica;
select lives_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source, stage, converted_member_id, converted_at)
     values ('00000000-0000-4000-8000-00000100009d'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Converted', '+919000000022', 'referral', 'converted',
             '00000000-0000-4000-8000-00000100003a'::uuid, now())$q$,
  'spec: A converted lead names the member it became - the named case is accepted');

select lives_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source, stage, lost_reason)
     values ('00000000-0000-4000-8000-00000100009e'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Lost', '+919000000023', 'google', 'lost', 'went elsewhere')$q$,
  'docs/data-model.md Enums: only the converted stage requires a member');
set local session_replication_role = default;

select throws_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source)
     values ('00000000-0000-4000-8000-000001000097'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Billboard', '+919000000024', 'billboard')$q$,
  '22P02', null,
  'spec: A lead source outside the vocabulary');

select throws_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source)
     values ('00000000-0000-4000-8000-000001000098'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Bad Phone', '9000000025', 'walk_in')$q$,
  '23514', null,
  'spec: A lead phone number that is not E.164');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping, duplicate_count)
     values ('00000000-0000-4000-8000-000001000099'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100002a'::uuid, 'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'spec: A negative duplicate count');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping, row_count)
     values ('00000000-0000-4000-8000-00000100009f'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100002a'::uuid, 'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'spec: An import run records non-negative counts - row_count');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping, imported_count)
     values ('00000000-0000-4000-8000-000001000080'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100002a'::uuid, 'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'spec: An import run records non-negative counts - imported_count');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping)
     values ('00000000-0000-4000-8000-000001000081'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             null, 'orphan.csv', '{}'::jsonb)$q$,
  '23502', null,
  'spec: An import by nobody');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping, status)
     values ('00000000-0000-4000-8000-000001000082'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100002a'::uuid, 'bad.csv', '{}'::jsonb, 'billboard')$q$,
  '22P02', null,
  'docs/data-model.md Enums: import_status is a closed set');

select throws_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('00000000-0000-4000-8000-00000100004d'::uuid, 'gym_owner', 'Wrong Role', 'holdout-wrong@gymloop.invalid')$q$,
  '23514', null,
  'spec: A platform user with a gym-side role');

select throws_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('00000000-0000-4000-8000-00000100004d'::uuid, 'member', 'Wrong Role', 'holdout-wrong2@gymloop.invalid')$q$,
  '23514', null,
  'spec: Platform accounts are visible only to the platform - member is not a platform role');

select lives_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('00000000-0000-4000-8000-00000100004d'::uuid, 'platform_support', 'Holdout Support Two', 'holdout-platform-4@gymloop.invalid')$q$,
  'spec: Platform accounts - platform_support is accepted');

-- ===========================================================================
-- 12. Gym A, signed in as a gym_owner (gate 7)
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000100000a',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select ok(
  not (select app.is_platform()),
  'docs/data-model.md app schema: gym_owner is not a platform role');

select is_empty(
  $q$select p.user_id from public.platform_users p$q$,
  'spec: A gym owner reading the platform roster');

select isnt_empty(
  $q$select s.id from public.impersonation_sessions s where s.id = '00000000-0000-4000-8000-00000100005a'::uuid$q$,
  'spec: A gym reading its own impersonation history');

select is_empty(
  $q$select s.id from public.impersonation_sessions s where s.id = '00000000-0000-4000-8000-00000100005b'::uuid$q$,
  'spec: A gym reading another gym''s impersonation history');

select isnt_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006a'::uuid$q$,
  'INT-003: a gym reads the audit rows of its own tenant');

select is_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006b'::uuid$q$,
  'gate 7: gym A cannot select gym B''s audit rows');

select is_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006c'::uuid$q$,
  'spec: A gym reading a platform-level audit row');

select isnt_empty(
  $q$select l.id from public.leads l where l.id = '00000000-0000-4000-8000-00000100007a'::uuid$q$,
  'gate 7: gym A reads its own leads');

select is_empty(
  $q$select l.id from public.leads l where l.id = '00000000-0000-4000-8000-00000100007b'::uuid$q$,
  'gate 7: gym A cannot select gym B''s leads');

select isnt_empty(
  $q$select m.id from public.member_imports m where m.id = '00000000-0000-4000-8000-00000100008a'::uuid$q$,
  'gate 7: gym A reads its own import runs');

select is_empty(
  $q$select m.id from public.member_imports m where m.id = '00000000-0000-4000-8000-00000100008b'::uuid$q$,
  'gate 7: gym A cannot select gym B''s import runs');

select lives_ok(
  $q$update public.leads set full_name = 'HOLDOUT HIJACK' where id = '00000000-0000-4000-8000-00000100007b'::uuid$q$,
  'gate 7: a cross-tenant lead update by primary key filters rather than raising');

select lives_ok(
  $q$update public.member_imports set file_name = 'HOLDOUT HIJACK' where id = '00000000-0000-4000-8000-00000100008b'::uuid$q$,
  'gate 7: a cross-tenant import update by primary key filters rather than raising');

select lives_ok(
  $q$update public.impersonation_sessions set reason = 'HOLDOUT HIJACK' where id = '00000000-0000-4000-8000-00000100005a'::uuid$q$,
  'spec: A gym can see who impersonated it, and change nothing about it - its own row');

select lives_ok(
  $q$update public.impersonation_sessions set reason = 'HOLDOUT HIJACK' where id = '00000000-0000-4000-8000-00000100005b'::uuid$q$,
  'gate 7: a cross-tenant impersonation update by primary key filters rather than raising');

select throws_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source)
     values ('00000000-0000-4000-8000-000001000085'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
             '00000000-0000-4000-8000-00000100001b'::uuid, 'Planted Lead', '+919000000031', 'walk_in')$q$,
  '42501', null,
  'gate 7: gym A cannot insert a lead labelled with gym B''s tenant id');

select throws_ok(
  $q$insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping)
     values ('00000000-0000-4000-8000-000001000086'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
             '00000000-0000-4000-8000-00000100002b'::uuid, 'planted.csv', '{}'::jsonb)$q$,
  '42501', null,
  'gate 7: gym A cannot insert an import run labelled with gym B''s tenant id');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000087'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
             'payment.refunded', 'payment')$q$,
  '42501', null,
  'gate 7: gym A cannot insert an audit row labelled with gym B''s tenant id');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000088'::uuid, null, 'payment.refunded', 'payment')$q$,
  '42501', null,
  'spec: A platform-level audit row is invisible to every gym - and no gym can forge one');

select throws_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
     values ('00000000-0000-4000-8000-000001000089'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'self serve', now() + interval '1 hour')$q$,
  '42501', null,
  'spec: A gym inventing an impersonation session');

select throws_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
     values ('00000000-0000-4000-8000-00000100008c'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'self serve', now() + interval '1 hour')$q$,
  '42501', null,
  'gate 7: gym A cannot plant an impersonation session on gym B');

select throws_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('00000000-0000-4000-8000-00000100004c'::uuid, 'super_admin', 'Self Promotion', 'holdout-platform-3@gymloop.invalid')$q$,
  '42501', null,
  'spec: Platform accounts are visible only to the platform - and writable only by it');

select throws_ok(
  $q$update public.audit_log set reason = 'edited' where id = '00000000-0000-4000-8000-00000100006a'::uuid$q$,
  '42501', null,
  'spec: Editing an audit row');

select throws_ok(
  $q$delete from public.audit_log where id = '00000000-0000-4000-8000-00000100006a'::uuid$q$,
  '42501', null,
  'spec: Deleting an audit row');

select throws_ok(
  $q$delete from public.leads where id = '00000000-0000-4000-8000-00000100007a'::uuid$q$,
  '42501', null,
  'ADR-037: no v1 flow hard-deletes a row, so delete is granted nowhere');

select lives_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source)
     values ('00000000-0000-4000-8000-000001000083'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Own Lead', '+919000000032', 'phone')$q$,
  'gate 7: gym A can insert a lead into its own tenant');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-000001000084'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             'follow_up.recorded', 'follow_up')$q$,
  '42501', null,
  'INT-003/ADR-047: gym A cannot append an audit row even inside its own tenant - audit_log is read-only for authenticated and is written only by service_role');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 13. Gym B, signed in as a gym_owner - isolation is not one-directional
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000100000b',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select isnt_empty(
  $q$select l.id from public.leads l where l.id = '00000000-0000-4000-8000-00000100007b'::uuid$q$,
  'gate 7: gym B reads its own leads');

select is_empty(
  $q$select l.id from public.leads l where l.id = '00000000-0000-4000-8000-00000100007a'::uuid$q$,
  'gate 7: gym B cannot select gym A''s leads');

select is_empty(
  $q$select m.id from public.member_imports m where m.id = '00000000-0000-4000-8000-00000100008a'::uuid$q$,
  'gate 7: gym B cannot select gym A''s import runs');

select isnt_empty(
  $q$select s.id from public.impersonation_sessions s where s.id = '00000000-0000-4000-8000-00000100005b'::uuid$q$,
  'spec: A gym reading its own impersonation history - gym B');

select is_empty(
  $q$select s.id from public.impersonation_sessions s where s.id = '00000000-0000-4000-8000-00000100005a'::uuid$q$,
  'gate 7: gym B cannot select gym A''s impersonation history');

select is_empty(
  $q$select a.id from public.audit_log a where a.id in ('00000000-0000-4000-8000-00000100006a'::uuid,
                                                        '00000000-0000-4000-8000-00000100006c'::uuid)$q$,
  'spec: A platform-level audit row is invisible to every gym - gym B sees neither it nor gym A''s');

select is_empty(
  $q$select p.user_id from public.platform_users p$q$,
  'spec: A gym owner reading the platform roster - gym B');

select throws_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source)
     values ('00000000-0000-4000-8000-00000100008d'::uuid, '00000000-0000-4000-8000-00000100000a'::uuid,
             '00000000-0000-4000-8000-00000100001a'::uuid, 'Planted Lead', '+919000000033', 'walk_in')$q$,
  '42501', null,
  'gate 7: gym B cannot insert a lead labelled with gym A''s tenant id');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 14. A gym-side role that is not the owner is confined the same way - the
--     platform branch keys on the role claim, not on the tenant claim
-- ===========================================================================

-- The non-owner role here was `member` in Phase 1, when being inside the gym was the
-- whole gate. It is `front_desk` now: the matrix gives a member no policy on leads at
-- all, so a member session could no longer demonstrate what this section is about --
-- that the platform branch keys on the role claim and not on the tenant claim.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-00000100000a',
                    'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select is_empty(
  $q$select p.user_id from public.platform_users p$q$,
  'spec: Platform accounts are visible only to the platform - no gym-side role reads it');

select is_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006c'::uuid$q$,
  'ADR-033: a null-tenant audit row is invisible to a non-owner gym-side role too');

select isnt_empty(
  $q$select l.id from public.leads l where l.id = '00000000-0000-4000-8000-00000100007a'::uuid$q$,
  'gate 7: the gym-side policy admits a role the matrix names, not only the owner');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 15. The claim is empty - zero rows, never an error
-- ===========================================================================

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select ok(
  (select app.current_tenant_id()) is null,
  'docs/data-model.md Row-Level Security: an empty claim yields a null tenant, not an exception');

select ok(
  not (select app.is_platform()),
  'docs/data-model.md Row-Level Security: an empty claim is not a platform role');

select is_empty(
  $q$select p.user_id from public.platform_users p$q$,
  'gate 7: platform_users under an empty claim');

select is_empty(
  $q$select s.id from public.impersonation_sessions s
      where s.id in ('00000000-0000-4000-8000-00000100005a'::uuid,
                     '00000000-0000-4000-8000-00000100005b'::uuid)$q$,
  'gate 7: impersonation_sessions under an empty claim');

select is_empty(
  $q$select a.id from public.audit_log a
      where a.id in ('00000000-0000-4000-8000-00000100006a'::uuid,
                     '00000000-0000-4000-8000-00000100006b'::uuid,
                     '00000000-0000-4000-8000-00000100006c'::uuid)$q$,
  'gate 7: audit_log under an empty claim, including the null-tenant row');

select is_empty(
  $q$select l.id from public.leads l
      where l.id in ('00000000-0000-4000-8000-00000100007a'::uuid,
                     '00000000-0000-4000-8000-00000100007b'::uuid)$q$,
  'gate 7: leads under an empty claim');

select is_empty(
  $q$select m.id from public.member_imports m
      where m.id in ('00000000-0000-4000-8000-00000100008a'::uuid,
                     '00000000-0000-4000-8000-00000100008b'::uuid)$q$,
  'gate 7: member_imports under an empty claim');

select lives_ok(
  $q$select count(*) from public.leads$q$,
  'docs/data-model.md Row-Level Security: an empty claim returns zero rows without raising');

set local role postgres;

-- ===========================================================================
-- 16. The claim exists but carries no tenant_id and no app_role - the
--     missing-claim case (gate 7)
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select ok(
  (select app.current_tenant_id()) is null,
  'docs/data-model.md app schema: a claim set with no tenant_id key yields null');

select ok(
  not (select app.is_platform()),
  'docs/data-model.md app schema: a claim set with no app_role key is not platform');

select is_empty(
  $q$select l.id from public.leads l
      where l.id in ('00000000-0000-4000-8000-00000100007a'::uuid,
                     '00000000-0000-4000-8000-00000100007b'::uuid)$q$,
  'gate 7: leads under a missing tenant claim');

select is_empty(
  $q$select a.id from public.audit_log a
      where a.id in ('00000000-0000-4000-8000-00000100006a'::uuid,
                     '00000000-0000-4000-8000-00000100006c'::uuid)$q$,
  'gate 7: audit_log under a missing tenant claim');

select is_empty(
  $q$select s.id from public.impersonation_sessions s
      where s.id in ('00000000-0000-4000-8000-00000100005a'::uuid,
                     '00000000-0000-4000-8000-00000100005b'::uuid)$q$,
  'gate 7: impersonation_sessions under a missing tenant claim');

set local role postgres;

-- ===========================================================================
-- 17. tenant_id present but empty, and tenant_id present but malformed
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select ok(
  (select app.current_tenant_id()) is null,
  'docs/data-model.md app schema: an empty-string tenant_id is nulled before the cast');

select is_empty(
  $q$select l.id from public.leads l
      where l.id in ('00000000-0000-4000-8000-00000100007a'::uuid,
                     '00000000-0000-4000-8000-00000100007b'::uuid)$q$,
  'gate 7: leads under an empty-string tenant claim');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'not-a-uuid', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select throws_ok(
  $q$select l.id from public.leads l$q$,
  '22P02', null,
  'docs/data-model.md app schema: a malformed tenant claim fails loudly rather than looking like an empty gym');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 18. The platform branch - super_admin crosses tenants by policy
-- ===========================================================================

-- `sub` is the acting super admin's own user id, not a random one:
-- impersonation_sessions_platform_write carries `actor_user_id = (select auth.uid())`
-- on both clauses, so a session may only be created or ended by the platform user it
-- is attributed to. A random sub would make the two writes below touch zero rows for a
-- reason that has nothing to do with what they assert.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '00000000-0000-4000-8000-00000100004a', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select ok(
  (select app.is_platform()),
  'docs/security.md Tenancy isolation: super_admin is a platform role');

select isnt_empty(
  $q$select p.user_id from public.platform_users p
      where p.user_id = '00000000-0000-4000-8000-00000100004a'::uuid$q$,
  'spec: A platform role reading the platform roster');

select results_eq(
  $q$select s.id from public.impersonation_sessions s
      where s.id in ('00000000-0000-4000-8000-00000100005a'::uuid,
                     '00000000-0000-4000-8000-00000100005b'::uuid)
      order by s.id$q$,
  $q$values ('00000000-0000-4000-8000-00000100005a'::uuid),
            ('00000000-0000-4000-8000-00000100005b'::uuid)$q$,
  'docs/security.md Tenancy isolation: super_admin sees impersonation sessions of every gym');

select isnt_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006c'::uuid$q$,
  'spec: A platform role reading the same row - the null-tenant audit row');

select results_eq(
  $q$select l.id from public.leads l
      where l.id in ('00000000-0000-4000-8000-00000100007a'::uuid,
                     '00000000-0000-4000-8000-00000100007b'::uuid)
      order by l.id$q$,
  $q$values ('00000000-0000-4000-8000-00000100007a'::uuid),
            ('00000000-0000-4000-8000-00000100007b'::uuid)$q$,
  'gate 7: the platform branch crosses tenants on leads');

select results_eq(
  $q$select m.id from public.member_imports m
      where m.id in ('00000000-0000-4000-8000-00000100008a'::uuid,
                     '00000000-0000-4000-8000-00000100008b'::uuid)
      order by m.id$q$,
  $q$values ('00000000-0000-4000-8000-00000100008a'::uuid),
            ('00000000-0000-4000-8000-00000100008b'::uuid)$q$,
  'gate 7: the platform branch crosses tenants on member_imports');

-- Ordered end-then-start, which is what design.md section 6 now forces: an actor holds
-- one open session, so the platform ends the one it started before opening the next.
-- Both rows are 004a's own, because the write policy now also requires the actor to be
-- the caller.
select lives_ok(
  $q$update public.impersonation_sessions set ended_at = now()
      where id = '00000000-0000-4000-8000-00000100005a'::uuid$q$,
  'docs/security.md Impersonation: the platform branch ends a session it started');

select lives_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
     values ('00000000-0000-4000-8000-00000100008e'::uuid, '00000000-0000-4000-8000-00000100000b'::uuid,
             '00000000-0000-4000-8000-00000100004a'::uuid, 'holdout platform write', now() + interval '1 hour')$q$,
  'spec: A gym can see who impersonated it - only the platform writes the record, and only for itself');

select throws_ok(
  $q$insert into public.audit_log (id, tenant_id, action, record_type)
     values ('00000000-0000-4000-8000-00000100008f'::uuid, null,
             'platform_user.role_changed', 'platform_user')$q$,
  '42501', null,
  'ADR-033/ADR-047: not even a super_admin session writes a platform-level audit row - the grant is read-only for authenticated whatever the app_role claim says, and audit writes run on service_role');

select throws_ok(
  $q$delete from public.audit_log where id = '00000000-0000-4000-8000-00000100006c'::uuid$q$,
  '42501', null,
  'INT-001: audit rows are never hard-deleted, not even by the platform branch');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 19. The platform branch - platform_support crosses tenants too
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select ok(
  (select app.is_platform()),
  'docs/security.md Tenancy isolation: platform_support is the second platform role');

select isnt_empty(
  $q$select p.user_id from public.platform_users p
      where p.user_id = '00000000-0000-4000-8000-00000100004b'::uuid$q$,
  'spec: A platform role reading the platform roster - platform_support');

select isnt_empty(
  $q$select a.id from public.audit_log a where a.id = '00000000-0000-4000-8000-00000100006c'::uuid$q$,
  'spec: A platform role reading the same row - platform_support');

select results_eq(
  $q$select l.id from public.leads l
      where l.id in ('00000000-0000-4000-8000-00000100007a'::uuid,
                     '00000000-0000-4000-8000-00000100007b'::uuid)
      order by l.id$q$,
  $q$values ('00000000-0000-4000-8000-00000100007a'::uuid),
            ('00000000-0000-4000-8000-00000100007b'::uuid)$q$,
  'gate 7: platform_support crosses tenants on leads');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- 20. Back as the owner: confirm the cross-tenant writes attempted above
--     changed nothing, and the platform write did land
-- ===========================================================================

select is(
  (select l.full_name from public.leads l where l.id = '00000000-0000-4000-8000-00000100007b'::uuid),
  'Lead B',
  'gate 7: gym A''s update by primary key touched no row of gym B''s leads');

select is(
  (select m.file_name from public.member_imports m where m.id = '00000000-0000-4000-8000-00000100008b'::uuid),
  'gymb.csv',
  'gate 7: gym A''s update by primary key touched no row of gym B''s import runs');

select is(
  (select count(*)::int from public.impersonation_sessions s
    where s.id in ('00000000-0000-4000-8000-00000100005a'::uuid,
                   '00000000-0000-4000-8000-00000100005b'::uuid)
      and s.reason = 'holdout support session'),
  2,
  'spec: A gym can see who impersonated it, and change nothing about it - both reasons survive');

select ok(
  (select s.ended_at from public.impersonation_sessions s
    where s.id = '00000000-0000-4000-8000-00000100005a'::uuid) is not null,
  'docs/security.md Impersonation: the platform branch''s update did land');

select is(
  (select count(*)::int from public.platform_users p
    where p.user_id = '00000000-0000-4000-8000-00000100004c'::uuid),
  0,
  'spec: Platform accounts are visible only to the platform - gym A''s self-promotion wrote nothing');

select is(
  (select count(*)::int from public.audit_log a
    where a.id = '00000000-0000-4000-8000-00000100006a'::uuid
      and a.reason is null),
  1,
  'spec: Editing an audit row - the refused update left the row as written');

select * from finish();

rollback;
