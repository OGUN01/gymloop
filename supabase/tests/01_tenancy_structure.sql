-- 01_tenancy_structure — the shape of the tenancy contract migration.
--
-- Cluster: tenancy (docs/data-model.md, "Cluster: tenancy (the contract
-- migration)"). Written blind from openspec/changes/0001-data-model/specs/
-- tenancy/spec.md before any DDL exists; every assertion names the spec
-- scenario or the docs/domain-rules.md requirement id it answers.
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

select plan(58);

-- ---------------------------------------------------------------------------
-- The app schema and the three functions the other six clusters depend on
-- (docs/data-model.md "The app schema and the two JWT accessors", ADR-032)
-- ---------------------------------------------------------------------------

select has_schema('app', 'ADR-032: the accessors live in a private app schema, not in public');

select has_function('app', 'current_tenant_id', '{}'::name[], 'ADR-032: the one tenant accessor exists');
select function_returns('app', 'current_tenant_id', '{}'::name[], 'uuid', 'ADR-032: the tenant claim is read as a uuid');
select volatility_is('app', 'current_tenant_id', '{}'::name[], 'stable', 'ADR-032: stable, so the (select ...) wrapper folds to one InitPlan');
select isnt_definer('app', 'current_tenant_id', '{}'::name[], 'ADR-032: security invoker, never definer');

select has_function('app', 'is_platform', '{}'::name[], 'ADR-032: the one platform-role accessor exists');
select function_returns('app', 'is_platform', '{}'::name[], 'boolean', 'ADR-032: the platform branch is a boolean');
select volatility_is('app', 'is_platform', '{}'::name[], 'stable', 'ADR-032: stable, so the (select ...) wrapper folds to one InitPlan');
select isnt_definer('app', 'is_platform', '{}'::name[], 'ADR-032: security invoker, never definer');

select has_function('app', 'touch_updated_at', '{}'::name[], 'the contract migration creates the one shared updated_at function');
select function_returns('app', 'touch_updated_at', '{}'::name[], 'trigger', 'the shared updated_at function is a trigger function');
select isnt_definer('app', 'touch_updated_at', '{}'::name[], 'the shared updated_at function is security invoker');

select ok(has_schema_privilege('authenticated', 'app', 'USAGE'), 'ADR-032: authenticated holds usage on app so a policy can call the accessors');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'), 'ADR-032: anon gets neither accessor');

-- ---------------------------------------------------------------------------
-- The five enums this cluster owns, with the contract's label ORDER
-- (docs/data-model.md "Enums", ADR-021, ADR-031)
-- ---------------------------------------------------------------------------

select has_enum('public', 'app_role', 'ADR-031: the role vocabulary is a Postgres enum, not a TypeScript constant');
select enum_has_labels(
  'public', 'app_role',
  array['super_admin', 'platform_support', 'gym_owner', 'gym_manager', 'front_desk', 'trainer', 'member']::name[],
  'ADR-031 / spec "The role vocabulary is a database enum": the seven v1 roles, in contract order'
);

select has_enum('public', 'organization_status', 'ADR-021: organization_status is a Postgres enum');
select enum_has_labels(
  'public', 'organization_status',
  array['pending_approval', 'trial', 'active', 'suspended', 'closed']::name[],
  'ADR-021: organization_status labels in contract order'
);

select has_enum('public', 'gym_preset', 'ADR-021: gym_preset is a Postgres enum');
select enum_has_labels(
  'public', 'gym_preset',
  array['neighbourhood_gym', 'premium_studio', 'functional_box']::name[],
  'ADR-021: the three v1 gym presets, in contract order'
);

select has_enum('public', 'streak_rule_type', 'STK-001: streak_rule_type is a Postgres enum');
select enum_has_labels(
  'public', 'streak_rule_type',
  array['visit_streak', 'weekly_goal', 'calendar_streak']::name[],
  'STK-001: the three configurable streak rule types, in contract order'
);

select has_enum('public', 'member_status', 'ADR-021: member_status is a Postgres enum');
select enum_has_labels(
  'public', 'member_status',
  array['active', 'paused', 'expired', 'cancelled', 'blocked']::name[],
  'ADR-021: member_status labels in contract order'
);

-- ---------------------------------------------------------------------------
-- The five tables exist (spec "The organisation hierarchy exists from day one")
-- ---------------------------------------------------------------------------

select has_table('public', 'organizations', 'spec "The organisation hierarchy exists from day one": organizations is the tenant');
select has_table('public', 'organization_settings', 'the per-gym template table exists');
select has_table('public', 'branches', 'spec "The organisation hierarchy exists from day one": organization contains branches');
select has_table('public', 'staff', 'every gym-side login is a staff row');
select has_table('public', 'members', 'spec "A member''s identifying details are unique within their gym": members exists');

-- ---------------------------------------------------------------------------
-- Exact column set, type and nullability per table. One assertion per table,
-- ordered by column name in C collation so declaration order is irrelevant.
-- The exactness is load-bearing for DPD-008: an extra column is a failure, so
-- a government-id column cannot be added without failing this test.
-- ---------------------------------------------------------------------------

select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.organizations'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('activated_at'::text, 'timestamptz'::text, false),
           ('created_at'::text, 'timestamptz'::text, true),
           ('currency'::text, 'text'::text, true),
           ('gym_code'::text, 'text'::text, true),
           ('id'::text, 'uuid'::text, true),
           ('name'::text, 'text'::text, true),
           ('status'::text, 'organization_status'::text, true),
           ('tier'::text, 'text'::text, false),
           ('timezone'::text, 'text'::text, true),
           ('trial_ends_at'::text, 'timestamptz'::text, false),
           ('updated_at'::text, 'timestamptz'::text, true)
  $$,
  'the contract''s column list for organizations, with types and nullability'
);

select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.organization_settings'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('address_line1'::text, 'text'::text, false),
           ('address_line2'::text, 'text'::text, false),
           ('brand_accent'::text, 'text'::text, false),
           ('checkin_dedupe_seconds'::text, 'int4'::text, true),
           ('city'::text, 'text'::text, false),
           ('created_at'::text, 'timestamptz'::text, true),
           ('financial_year_start_month'::text, 'int2'::text, true),
           ('grace_period_days'::text, 'int2'::text, true),
           ('gstin'::text, 'text'::text, false),
           ('invoice_prefix'::text, 'text'::text, true),
           ('logo_url'::text, 'text'::text, false),
           ('max_freeze_days_per_year'::text, 'int2'::text, true),
           ('no_show_threshold_days'::text, 'int2'::text, true),
           ('opening_hours'::text, 'jsonb'::text, true),
           ('pause_approver_role'::text, 'app_role'::text, true),
           ('pause_reasons'::text, '_text'::text, true),
           ('pincode'::text, 'text'::text, false),
           ('preset'::text, 'gym_preset'::text, false),
           ('receipt_prefix'::text, 'text'::text, true),
           ('renewal_reminder_days_from_expiry'::text, '_int2'::text, false),
           ('state'::text, 'text'::text, false),
           ('streak_rule_type'::text, 'streak_rule_type'::text, true),
           ('tenant_id'::text, 'uuid'::text, true),
           ('trainer_member_cap'::text, 'int2'::text, false),
           ('updated_at'::text, 'timestamptz'::text, true),
           ('week_start_day'::text, 'int2'::text, true),
           ('weekly_goal_default'::text, 'int2'::text, true)
  $$,
  'the contract''s column list for organization_settings, with types and nullability'
);

select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.branches'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('address'::text, 'text'::text, false),
           ('created_at'::text, 'timestamptz'::text, true),
           ('id'::text, 'uuid'::text, true),
           ('is_default'::text, 'bool'::text, true),
           ('name'::text, 'text'::text, true),
           ('tenant_id'::text, 'uuid'::text, true),
           ('timezone'::text, 'text'::text, false),
           ('updated_at'::text, 'timestamptz'::text, true)
  $$,
  'the contract''s column list for branches, with types and nullability'
);

select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.staff'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('branch_id'::text, 'uuid'::text, false),
           ('created_at'::text, 'timestamptz'::text, true),
           ('email'::text, 'text'::text, false),
           ('full_name'::text, 'text'::text, true),
           ('id'::text, 'uuid'::text, true),
           ('is_active'::text, 'bool'::text, true),
           ('max_active_clients'::text, 'int2'::text, false),
           ('phone'::text, 'text'::text, false),
           ('qualification'::text, 'text'::text, false),
           ('role'::text, 'app_role'::text, true),
           ('tenant_id'::text, 'uuid'::text, true),
           ('updated_at'::text, 'timestamptz'::text, true),
           ('user_id'::text, 'uuid'::text, false)
  $$,
  'the contract''s column list for staff, with types and nullability'
);

select results_eq(
  $$
    select a.attname::text collate "default", t.typname::text collate "default", a.attnotnull
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.members'::regclass and a.attnum > 0 and not a.attisdropped
    order by a.attname::text collate "C"
  $$,
  $$
    values ('branch_id'::text, 'uuid'::text, true),
           ('created_at'::text, 'timestamptz'::text, true),
           ('date_of_birth'::text, 'date'::text, false),
           ('email'::text, 'text'::text, false),
           ('erased_at'::text, 'timestamptz'::text, false),
           ('full_name'::text, 'text'::text, true),
           ('gender'::text, 'text'::text, false),
           ('id'::text, 'uuid'::text, true),
           ('joined_on'::text, 'date'::text, true),
           ('member_code'::text, 'text'::text, false),
           ('motivation_push_enabled'::text, 'bool'::text, true),
           ('notes'::text, 'text'::text, false),
           ('phone'::text, 'text'::text, true),
           ('photo_url'::text, 'text'::text, false),
           ('rest_days'::text, '_int2'::text, true),
           ('status'::text, 'member_status'::text, true),
           ('tenant_id'::text, 'uuid'::text, true),
           ('updated_at'::text, 'timestamptz'::text, true),
           ('user_id'::text, 'uuid'::text, false),
           ('weekly_goal_visits'::text, 'int2'::text, false)
  $$,
  'DPD-008: the contract''s exact column list for members, so there is no column for a government id'
);

-- ---------------------------------------------------------------------------
-- Defaults, asserted from a minimally-specified row rather than from the
-- rendered default expression. Fixtures are inserted as the owner (BYPASSRLS).
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('00000000-0000-4000-8000-0000000000a1'::uuid, 'Gym A', 'GYMAAA');

insert into public.organization_settings (tenant_id)
values ('00000000-0000-4000-8000-0000000000a1'::uuid);

insert into public.branches (id, tenant_id, name)
values ('00000000-0000-4000-8000-0000000000a2'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'Main');

insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('00000000-0000-4000-8000-0000000000a4'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
        '00000000-0000-4000-8000-0000000000a2'::uuid, 'Amit A', '+919876543210');

select results_eq(
  $$
    select status::text, timezone, currency, tier, trial_ends_at, activated_at
    from public.organizations where id = '00000000-0000-4000-8000-0000000000a1'::uuid
  $$,
  $$ values ('pending_approval'::text, 'Asia/Kolkata'::text, 'INR'::text, null::text, null::timestamptz, null::timestamptz) $$,
  'a new gym defaults to pending_approval, IST and INR (docs/data-model.md, organizations)'
);

select results_eq(
  $$
    select invoice_prefix, receipt_prefix, financial_year_start_month, week_start_day,
           no_show_threshold_days, checkin_dedupe_seconds, streak_rule_type::text,
           weekly_goal_default, grace_period_days, pause_approver_role::text,
           max_freeze_days_per_year, opening_hours::text, pause_reasons
    from public.organization_settings where tenant_id = '00000000-0000-4000-8000-0000000000a1'::uuid
  $$,
  $$
    values ('INV'::text, 'RCPT'::text, 4::smallint, 1::smallint, 7::smallint, 120::integer, 'visit_streak'::text,
            3::smallint, 0::smallint, 'gym_manager'::text, 30::smallint, '{}'::text, '{}'::text[])
  $$,
  'NSH-003 / ATT-004 / STK-001 / PAY-001: the per-gym template defaults the contract fixes'
);

select is(
  (select is_default from public.branches where id = '00000000-0000-4000-8000-0000000000a2'::uuid),
  false,
  'a branch is not the default branch unless it says so'
);

select results_eq(
  $$
    select status::text, motivation_push_enabled, rest_days, weekly_goal_visits, erased_at, member_code
    from public.members where id = '00000000-0000-4000-8000-0000000000a4'::uuid
  $$,
  $$ values ('active'::text, true, '{}'::smallint[], null::smallint, null::timestamptz, null::text) $$,
  'STK-002 / STK-004 / DPD-006: a new member is active, opted in, with no rest days and not erased'
);

select matches(
  (select pg_get_expr(d.adbin, d.adrelid)
     from pg_attrdef d
     join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.members'::regclass and a.attname = 'joined_on'),
  'Asia/Kolkata',
  'ADR-039 / MNY-004: members.joined_on defaults to the IST-local calendar day'
);

select doesnt_match(
  (select pg_get_expr(d.adbin, d.adrelid)
     from pg_attrdef d
     join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.members'::regclass and a.attname = 'joined_on'),
  'current_date',
  'ADR-039: members.joined_on does not use current_date, which is UTC on every Supabase connection'
);

select case
  when to_regclass('public.no_show_cases') is null
    then skip('ADR-039: no_show_cases belongs to the retention cluster and has not landed yet', 1)
  else matches(
    (select pg_get_expr(d.adbin, d.adrelid)
       from pg_attrdef d
       join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
      where d.adrelid = to_regclass('public.no_show_cases') and a.attname = 'opened_on'),
    'Asia/Kolkata',
    'ADR-039 / MNY-004: no_show_cases.opened_on defaults to the IST-local calendar day'
  )
end;

-- ---------------------------------------------------------------------------
-- Column-level check constraints, asserted by the write they must refuse.
-- A check violation is SQLSTATE 23514 (docs/data-model.md, "How a pgTAP test
-- assumes a role"). Failing inserts and updates roll back to the statement's
-- implicit savepoint, so they leave no state behind.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.organizations (name, gym_code) values ('Bad Code Gym', 'abc123')$$,
  '23514', null,
  'spec "A malformed gym code": a gym code must be six upper-case alphanumeric characters'
);

select throws_ok(
  $$update public.organizations set currency = 'inr' where id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'MNY-002: organizations.currency is checked even with no money column beside it'
);

select ok(
  exists (select 1 from pg_constraint
           where conrelid = 'public.organizations'::regclass
             and conname = 'organizations_gym_code_format_chk'),
  'ADR-040: a regex check is named <table>_<column>_format_chk'
);

select ok(
  exists (select 1 from pg_constraint
           where conrelid = 'public.organizations'::regclass
             and conname = 'organizations_currency_format_chk'),
  'ADR-041: the currency check follows ADR-040''s rule word, not the superseded literal template'
);

select throws_ok(
  $$update public.organization_settings set brand_accent = 'red' where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'the gym''s brand accent must be a six-digit hex colour (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set pincode = '012345' where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'an Indian pincode may not start with zero (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set gstin = 'NOTAGSTIN' where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'GSTIN is checked in full, because it lands on every GST invoice (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set financial_year_start_month = 13 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'financial_year_start_month is bounded 1-12 (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set week_start_day = 7 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'week_start_day is bounded 0-6 (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set no_show_threshold_days = 0 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'NSH-003: a no-show threshold of zero days would open a case for everyone'
);

select throws_ok(
  $$update public.organization_settings set checkin_dedupe_seconds = -1 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'ATT-004: the de-duplication window cannot be negative'
);

select throws_ok(
  $$update public.organization_settings set weekly_goal_default = 15 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'STK-001: the default weekly goal is bounded 1-14'
);

select throws_ok(
  $$update public.organization_settings set max_freeze_days_per_year = -1 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'max_freeze_days_per_year cannot be negative (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$update public.organization_settings set trainer_member_cap = 0 where tenant_id = '00000000-0000-4000-8000-0000000000a1'$$,
  '23514', null,
  'a trainer-to-member cap of zero is not a cap (docs/data-model.md, organization_settings)'
);

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000a1', 'front_desk', 'No Plus', '9876543210')$$,
  '23514', null,
  'spec "A malformed phone number": staff phones are stored in E.164 form'
);

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name, max_active_clients)
    values ('00000000-0000-4000-8000-0000000000a1', 'trainer', 'Zero Cap', 0)$$,
  '23514', null,
  'ADD-003: a trainer''s active-client cap must be positive'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, weekly_goal_visits)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'Zero Goal', '+919876500001', 0)$$,
  '23514', null,
  'STK-001: a member''s weekly goal is bounded 1-14'
);

select * from finish();

rollback;
