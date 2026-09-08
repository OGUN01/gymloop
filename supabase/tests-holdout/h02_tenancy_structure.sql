-- h02_tenancy_structure: holdout suite for the `tenancy` cluster, part 2 of 2.
--
-- Written blind from openspec/changes/0001-data-model/specs/tenancy/spec.md.
-- Part 1 (h01) proves isolation; this half proves the structure isolation is
-- hung on: the organisation hierarchy, the gym code, the role vocabulary, the
-- member identity rules, DPDP's no-government-ID guarantee, the shared
-- updated_at trigger, and the IST-local calendar-day default.
--
-- Where the spec says SHALL NOT, the assertion attempts the thing and expects
-- the SQLSTATE. Fixture uuids share h01's 0f1d prefix and both files roll back.
--
-- Rollback-wrapped per ADR-030: first statement BEGIN, last ROLLBACK, no COMMIT
-- and no anonymous PL/pgSQL block anywhere.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path to public, extensions;

select plan(37);

-- Fixtures, as the owner. Charlie exists so that a rule scoped to one
-- organisation can be shown not to be a global one.

insert into public.organizations (id, name, gym_code) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'Holdout Gym Alpha', 'HLDTA1'),
  ('0f1d0b02-7e57-4c0b-9b02-000000000002', 'Holdout Gym Bravo', 'HLDTB2'),
  ('0f1d0c03-7e57-4c0c-9c03-000000000003', 'Holdout Gym Charlie', 'HLDTC3');

insert into public.branches (id, tenant_id, name, is_default) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000011', '0f1d0a01-7e57-4c0a-9a01-000000000001', 'Alpha Main', true),
  ('0f1d0b02-7e57-4c0b-9b02-000000000012', '0f1d0b02-7e57-4c0b-9b02-000000000002', 'Bravo Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000031', '0f1d0a01-7e57-4c0a-9a01-000000000001',
   '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Alpha Member', '+919900000051');

-- The five tenancy tables exist. Every catalogue-scanning assertion below and
-- in h01 would pass vacuously against a missing table, so this is the guard
-- that stops an empty schema from looking clean.

select has_table('public', 'organizations', 'H-TEN-101: organizations exists');
select has_table('public', 'organization_settings', 'H-TEN-102: organization_settings exists');
select has_table('public', 'branches', 'H-TEN-103: branches exists');
select has_table('public', 'staff', 'H-TEN-104: staff exists');
select has_table('public', 'members', 'H-TEN-105: members exists');

-- The gym code. It is the one identifier a member types at a strange gym, so
-- it is unique across the platform and not merely within a tenant.

select throws_ok(
  $$ insert into public.organizations (id, name, gym_code)
     values ('0f1d0e05-7e57-4c0e-9e05-000000000005', 'Gym Code Thief', 'HLDTA1') $$,
  '23505', null,
  'H-TEN-106: a gym code already taken by another organisation is refused');

select throws_ok(
  $$ insert into public.organizations (id, name, gym_code)
     values ('0f1d0e05-7e57-4c0e-9e05-000000000005', 'Lowercase Code', 'hldte5') $$,
  '23514', null,
  'H-TEN-107: a lower-case gym code is refused, the format check is upper-case only');

select throws_ok(
  $$ insert into public.organizations (id, name, gym_code)
     values ('0f1d0e05-7e57-4c0e-9e05-000000000005', 'Short Code', 'HLDT5') $$,
  '23514', null,
  'H-TEN-108: a five-character gym code is refused, the length is exactly six');

select throws_ok(
  $$ insert into public.organizations (id, name, gym_code)
     values ('0f1d0e05-7e57-4c0e-9e05-000000000005', 'Long Code', 'HLDTE55') $$,
  '23514', null,
  'H-TEN-109: a seven-character gym code is refused, the length is exactly six');

select ok(
  not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'organizations'
       and column_name = 'tenant_id'),
  'H-TEN-110: organizations is the tenant, so it isolates on id and carries no tenant_id column');

-- The hierarchy. Exactly one default branch per organisation, and that
-- uniqueness is scoped to the organisation rather than to the platform.

select throws_ok(
  $$ insert into public.branches (tenant_id, name, is_default)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'Alpha Second Default', true) $$,
  '23505', null,
  'H-TEN-111: a second default branch in one organisation is refused');

select lives_ok(
  $$ insert into public.branches (tenant_id, name, is_default)
     values ('0f1d0c03-7e57-4c0c-9c03-000000000003', 'Charlie Main', true) $$,
  'H-TEN-112: a default branch in a different organisation is accepted, the rule is per organisation');

select throws_ok(
  $$ insert into public.branches (tenant_id, name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'Alpha Main') $$,
  '23505', null,
  'H-TEN-113: two branches of one organisation cannot share a name');

-- The role vocabulary (ADR-031). staff is every gym-side login, so a platform
-- role must not be reachable by writing one into a staff row.

select throws_ok(
  $$ insert into public.staff (tenant_id, role, full_name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'super_admin', 'Escalated Owner') $$,
  '23514', null,
  'H-TEN-114: a staff row cannot hold the super_admin role');

select throws_ok(
  $$ insert into public.staff (tenant_id, role, full_name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'platform_support', 'Escalated Support') $$,
  '23514', null,
  'H-TEN-115: a staff row cannot hold the platform_support role either');

select throws_ok(
  $$ insert into public.staff (tenant_id, role, full_name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'member', 'Not Staff') $$,
  '23514', null,
  'H-TEN-116: member is a role in the enum but not a role a staff row may hold');

select throws_ok(
  $$ insert into public.staff (tenant_id, role, full_name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'chief_gym_officer', 'Invented Role') $$,
  '22P02', null,
  'H-TEN-117: a label outside app_role is refused by the type, not by application code');

select results_eq(
  $$ select e.enumlabel::text collate "default"
       from pg_enum e
       join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
      where n.nspname = 'public' and t.typname = 'app_role'
      order by e.enumsortorder $$,
  $$ values ('super_admin'), ('platform_support'), ('gym_owner'),
            ('gym_manager'), ('front_desk'), ('trainer'), ('member') $$,
  'H-TEN-118: ADR-031, app_role carries the seven v1 roles in contract order');

select throws_ok(
  $$ insert into public.staff (tenant_id, role, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'front_desk', 'Bad Phone', '9900000041') $$,
  '23514', null,
  'H-TEN-119: a staff phone without the E.164 country prefix is refused');

-- Member identity. The duplicate-phone rule is what the CSV import leans on,
-- and it has to be per gym or a member who moves gyms cannot be enrolled.

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001',
             '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Alpha Duplicate', '+919900000051') $$,
  '23505', null,
  'H-TEN-120: a second member of the same gym cannot reuse a phone number');

select lives_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0b02-7e57-4c0b-9b02-000000000002',
             '0f1d0b02-7e57-4c0b-9b02-000000000012', 'Bravo Namesake', '+919900000051') $$,
  'H-TEN-121: the same phone number at a different gym is accepted, the rule is per gym');

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001',
             '0f1d0a01-7e57-4c0a-9a01-000000000011', 'No Country Code', '9900000053') $$,
  '23514', null,
  'H-TEN-122: a member phone with no country prefix is not E.164 and is refused');

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001',
             '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Leading Zero', '+09900000054') $$,
  '23514', null,
  'H-TEN-123: an E.164 country code cannot start with zero');

select is_empty(
  $$ select column_name
       from information_schema.columns
      where table_schema = 'public' and table_name = 'members'
        and column_name ~ '(^|_)(aadhaar|aadhar|pan|passport|voter|licence|license|govt|government|national_id|identity|id_proof|id_number|uidai|ssn)(_|$)' $$,
  'H-TEN-124: DPD-008, members offers nowhere to put a government-issued identity document');

select has_column('public', 'members', 'photo_url',
  'H-TEN-125: DPD-008, a member photo is the identity artefact v1 does store');

select col_not_null('public', 'members', 'branch_id',
  'H-TEN-126: every member belongs to a branch, so the hierarchy holds from day one');

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001',
             '0f1d0f06-7e57-4c0f-9f06-000000000006', 'Orphan Member', '+919900000055') $$,
  '23503', null,
  'H-TEN-127: a member cannot reference a branch that does not exist');

-- ADR-039. Assert the default expression, not only the value: a test run at
-- 10:00 IST passes against current_date too, and the whole point of the ADR is
-- the 00:00 to 05:30 window where it does not.

select ok(
  coalesce((
    select pg_get_expr(ad.adbin, ad.adrelid)
      from pg_attrdef ad
      join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
      join pg_class c on c.oid = ad.adrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'members' and a.attname = 'joined_on'
  ), '') like '%Asia/Kolkata%',
  'H-TEN-128: ADR-039, the members.joined_on default names the gym timezone');

select ok(
  coalesce((
    select pg_get_expr(ad.adbin, ad.adrelid)
      from pg_attrdef ad
      join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
      join pg_class c on c.oid = ad.adrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'members' and a.attname = 'joined_on'
  ), 'current_date') not ilike '%current_date%',
  'H-TEN-129: ADR-039, the members.joined_on default is not current_date, which is UTC on every connection');

select is(
  (select joined_on from public.members where id = '0f1d0a01-7e57-4c0a-9a01-000000000031'),
  (now() at time zone 'Asia/Kolkata')::date,
  'H-TEN-130: MNY-004, a member joins on the gym-local calendar day');

-- app.touch_updated_at(). The probe row is stamped in 2019 on purpose: inside
-- one transaction now() is constant, so a row inserted and updated here would
-- otherwise show the same instant either way and prove nothing.

insert into public.members (id, tenant_id, branch_id, full_name, phone, created_at, updated_at)
values ('0f1d0a01-7e57-4c0a-9a01-000000000041', '0f1d0a01-7e57-4c0a-9a01-000000000001',
        '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Trigger Probe', '+919900000056',
        '2019-03-04 05:06:07+00', '2019-03-04 05:06:07+00');

update public.members set full_name = 'Trigger Probe Renamed'
 where id = '0f1d0a01-7e57-4c0a-9a01-000000000041';

select ok(
  (select updated_at from public.members where id = '0f1d0a01-7e57-4c0a-9a01-000000000041') >= now(),
  'H-TEN-131: an update moves members.updated_at forward to the current transaction time');

select is(
  (select created_at from public.members where id = '0f1d0a01-7e57-4c0a-9a01-000000000041'),
  '2019-03-04 05:06:07+00'::timestamptz,
  'H-TEN-132: the same update leaves members.created_at exactly where it was');

update public.members
   set full_name = 'Trigger Probe Renamed Again',
       updated_at = '2021-07-08 09:10:11+00'
 where id = '0f1d0a01-7e57-4c0a-9a01-000000000041';

select ok(
  (select updated_at from public.members where id = '0f1d0a01-7e57-4c0a-9a01-000000000041') >= now(),
  'H-TEN-133: updated_at is the trigger''s to set, a value supplied by the caller is overwritten');

-- DPD-006. Erasure blanks the person and keeps the row, because INT-001 needs
-- everything that references the member to keep resolving.

select col_is_null('public', 'members', 'erased_at',
  'H-TEN-134: DPD-006, members.erased_at is nullable, a live member simply has none');

update public.members
   set erased_at = now(), full_name = 'Erased Member', email = null, notes = null
 where id = '0f1d0a01-7e57-4c0a-9a01-000000000031';

select is(
  (select count(*) from public.members
    where id = '0f1d0a01-7e57-4c0a-9a01-000000000031' and erased_at is not null),
  1::bigint,
  'H-TEN-135: DPD-006, an erased member is marked rather than removed, the row survives');

-- Foreign keys re-check the tenant (ADR-052). Asserted over the catalogue
-- rather than table by table, so a Phase 2 table that arrives with a
-- single-column member_id fails here without anyone editing this file.
--
-- The three exemptions fall out of one predicate instead of being listed: a
-- key is in scope only when its parent carries a tenant_id column of its own.
-- That excludes a table's own tenant_id -> organizations key, which is the
-- tenant check, and every reference to auth.users or to platform_users, which
-- have no tenant column. audit_log is named, because it is the one exemption
-- that does not fall out: its tenant_id is nullable by ADR-033, and a composite
-- match simple key would silently stop enforcing on the platform-level rows
-- that most need an intact reference.

select is_empty($$
  select (c.conrelid::regclass)::text || ' ' || c.conname::text
    from pg_constraint c
    join pg_class rel on rel.oid = c.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
   where c.contype = 'f'
     and n.nspname = 'public'
     and rel.relname <> 'audit_log'
     and exists (
       select 1 from pg_attribute pa
        where pa.attrelid = c.confrelid
          and pa.attname = 'tenant_id'
          and pa.attnum > 0 and not pa.attisdropped)
     and not (
       array_length(c.conkey, 1) = 2
       and (select a.attname from pg_attribute a
             where a.attrelid = c.conrelid and a.attnum = c.conkey[1]) = 'tenant_id')
$$, 'H-TEN-136: ADR-052, every foreign key whose parent is tenant-scoped is composite and leads with tenant_id - a single-column key does not re-check the tenant, because Postgres runs referential-integrity probes with row security off');

-- The other half of the same rule: a composite key needs a target to match, so
-- every tenant-scoped table referenced by such a key carries the unique that
-- makes it a legal one. Scoped to real parents, because a table nothing points
-- at owes nothing yet - and Postgres refuses to create the key at all if the
-- unique is missing when a Phase 2 child finally does point at it.
--
-- "Such a key" means one the rule above requires to be composite, so the
-- audit_log exemption propagates to the parent side and the child exclusion is
-- repeated here deliberately. impersonation_sessions is the case that proves it:
-- the only key pointing at it is audit_log.impersonation_session_id, which stays
-- single-column by ADR-052 because audit_log.tenant_id is nullable, so nothing
-- composite references impersonation_sessions and it owes no unique (tenant_id,
-- id). Widen this to "parent of any foreign key" and it fails on a correct
-- schema - which it did, in this file and in the visible suite independently.

select is_empty($$
  select rel.relname::text
    from pg_class rel
    join pg_namespace n on n.oid = rel.relnamespace
   where n.nspname = 'public'
     and rel.relkind = 'r'
     and exists (
       select 1 from pg_attribute a
        where a.attrelid = rel.oid and a.attname = 'tenant_id'
          and a.attnum > 0 and not a.attisdropped)
     and exists (
       select 1 from pg_attribute a
        where a.attrelid = rel.oid and a.attname = 'id'
          and a.attnum > 0 and not a.attisdropped)
     and exists (
       select 1 from pg_constraint c
        join pg_class child on child.oid = c.conrelid
        join pg_namespace cn on cn.oid = child.relnamespace
        where c.contype = 'f' and c.confrelid = rel.oid and cn.nspname = 'public'
          and child.relname <> 'audit_log')
     and not exists (
       select 1 from pg_index i
        where i.indrelid = rel.oid
          and i.indisunique
          and i.indpred is null
          and i.indnkeyatts = 2
          and (select a.attname from pg_attribute a
                where a.attrelid = rel.oid and a.attnum = i.indkey[0]) = 'tenant_id'
          and (select a.attname from pg_attribute a
                where a.attrelid = rel.oid and a.attnum = i.indkey[1]) = 'id')
$$, 'H-TEN-137: ADR-052, every tenant-scoped table referenced by a key the rule requires to be composite carries unique (tenant_id, id), in that column order, which is what makes it a legal target - a table referenced only by audit_log''s exempt single-column key owes nothing');

select * from finish();

rollback;
