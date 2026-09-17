-- h01_tenancy_isolation: holdout suite for the `tenancy` cluster, part 1 of 2.
--
-- Written blind from openspec/changes/0001-data-model/specs/tenancy/spec.md.
-- Never read the visible suite, never read the migration. This half covers the
-- JWT-claim contract, the four claim states (absent, empty, present without a
-- tenant key, malformed), cross-tenant isolation across the five tenancy
-- tables, the platform-role branch, the privilege contract, and the two `app`
-- accessors. Part 2 (h02) covers the structural guarantees.
--
-- Every fixture uuid is prefixed 0f1d so it cannot collide with the visible
-- suite or with supabase/seed.sql.
--
-- Rollback-wrapped per ADR-030: first statement BEGIN, last ROLLBACK, no COMMIT
-- and no anonymous PL/pgSQL block anywhere.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path to public, extensions;

select plan(63);

-- Fixtures, inserted as the owner. `postgres` holds BYPASSRLS, so row security
-- does not apply here. No set_config yet: the first block below depends on the
-- claims GUC never having been set in this session at all.

insert into public.organizations (id, name, gym_code) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'Holdout Gym Alpha', 'HLDTA1'),
  ('0f1d0b02-7e57-4c0b-9b02-000000000002', 'Holdout Gym Bravo', 'HLDTB2'),
  ('0f1d0c03-7e57-4c0c-9c03-000000000003', 'Holdout Gym Charlie', 'HLDTC3');

insert into public.organization_settings (tenant_id) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000001'),
  ('0f1d0b02-7e57-4c0b-9b02-000000000002');

insert into public.branches (id, tenant_id, name, is_default) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000011', '0f1d0a01-7e57-4c0a-9a01-000000000001', 'Alpha Main', true),
  ('0f1d0b02-7e57-4c0b-9b02-000000000012', '0f1d0b02-7e57-4c0b-9b02-000000000002', 'Bravo Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name, phone) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000021', '0f1d0a01-7e57-4c0a-9a01-000000000001',
   '0f1d0a01-7e57-4c0a-9a01-000000000011', 'gym_owner', 'Alpha Owner', '+919900000041'),
  ('0f1d0b02-7e57-4c0b-9b02-000000000022', '0f1d0b02-7e57-4c0b-9b02-000000000002',
   '0f1d0b02-7e57-4c0b-9b02-000000000012', 'gym_owner', 'Bravo Owner', '+919900000042');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('0f1d0a01-7e57-4c0a-9a01-000000000031', '0f1d0a01-7e57-4c0a-9a01-000000000001',
   '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Alpha Member', '+919900000051'),
  ('0f1d0b02-7e57-4c0b-9b02-000000000032', '0f1d0b02-7e57-4c0b-9b02-000000000002',
   '0f1d0b02-7e57-4c0b-9b02-000000000012', 'Bravo Member', '+919900000052');

-- 1. No usable claim. A hook-less token is the realistic Phase 1 shape, and the
--    spec says it sees nothing and raises nothing.
--
--    The contract treats two states as one missing claim: the GUC never set at
--    all, and the GUC set to the empty string. This block must run before this
--    file's first set_config, because a placeholder GUC cannot be returned to
--    "never set" - not by rollback, which restores the value and leaves the
--    placeholder defined, and not by reset or set to default, which yield the
--    empty string. Only a fresh backend is truly unset, and DISCARD ALL, the one
--    statement that would restore it, cannot run inside a transaction block, so a
--    file wrapped BEGIN..ROLLBACK (ADR-030) cannot reach that state at all.
--
--    So which of the two shapes the five assertions below exercise depends on
--    whether this file got a connection nobody has used: on a pooled connection
--    shared with the other suites it is the empty string, and the genuinely-unset
--    branch is not reachable in CI. The precondition therefore asserts what it
--    can establish - that no claim is in effect, in either shape - and the
--    assertions after it hold identically under both, which is what the contract
--    demands of them.

select ok(
  coalesce(current_setting('request.jwt.claims', true), '') = '',
  'H-TEN-001: precondition, no claim is in effect - the claims GUC is either unset or the empty string, the two shapes the contract calls a missing claim');

set local role authenticated;

select is(
  app.current_tenant_id(), null::uuid,
  'H-TEN-002: with no claims GUC the tenant accessor yields null rather than raising');

select ok(
  not app.is_platform(),
  'H-TEN-003: with no claims GUC nobody is a platform role');

select is_empty(
  $$ select id from public.members $$,
  'H-TEN-004: a claimless authenticated caller reads zero members from a populated table');

select is_empty(
  $$ select id from public.organizations $$,
  'H-TEN-005: a claimless authenticated caller reads zero organizations');

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001',
             '0f1d0a01-7e57-4c0a-9a01-000000000011', 'Claimless Insert', '+919900000061') $$,
  '42501', null,
  'H-TEN-006: a claimless authenticated caller cannot insert, the with check refuses it');

set local role postgres;

-- 2. The empty-string claim, which is what the contract calls a missing claim.

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is(
  app.current_tenant_id(), null::uuid,
  'H-TEN-007: an empty claims string yields a null tenant, not an error');

select ok(
  not app.is_platform(),
  'H-TEN-008: an empty claims string is not a platform role');

select is_empty(
  $$ select id from public.members $$,
  'H-TEN-009: an empty claims string reads zero rows and does not raise');

select throws_ok(
  $$ insert into public.branches (tenant_id, name)
     values ('0f1d0a01-7e57-4c0a-9a01-000000000001', 'Empty Claim Branch') $$,
  '42501', null,
  'H-TEN-010: an empty claims string cannot insert into a tenant-scoped table');

set local role postgres;

-- 3. Claims present, tenant_id key absent. This is exactly what a token minted
--    before Phase 2 ships the access-token hook looks like, so it must degrade
--    to "sees nothing" and not to "sees everything".

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text,
  true);
set local role authenticated;

select is(
  app.current_tenant_id(), null::uuid,
  'H-TEN-011: a token carrying no tenant_id key yields a null tenant');

select is_empty(
  $$ select id from public.branches $$,
  'H-TEN-012: a token carrying no tenant_id key reads zero branches');

set local role postgres;

-- 4. A malformed tenant claim. ADR-032 is explicit that this is the one case
--    that must fail loudly, because a silent empty result would be read as an
--    empty gym.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'gym-alpha', 'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select throws_ok(
  $$ select app.current_tenant_id() $$,
  '22P02', null,
  'H-TEN-013: ADR-032, a tenant claim that is not a uuid raises on the cast');

select throws_ok(
  $$ select id from public.members $$,
  '22P02', null,
  'H-TEN-014: ADR-032, a malformed tenant claim fails the read loudly instead of returning an empty gym');

set local role postgres;

-- 5. Gym Alpha, acting as gym_owner. Read, update by primary key, insert
--    labelled with another tenant, and delete, on all five tenancy tables.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '0f1d0a01-7e57-4c0a-9a01-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select is(
  app.current_tenant_id(), '0f1d0a01-7e57-4c0a-9a01-000000000001'::uuid,
  'H-TEN-015: the accessor returns the tenant_id claim as a uuid');

select ok(
  not app.is_platform(),
  'H-TEN-016: gym_owner is a gym-side role, not a platform role');

select results_eq(
  $$ select id from public.organizations $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000001'::uuid) $$,
  'H-TEN-017: organizations isolates on id, gym Alpha sees only its own organization row');

select results_eq(
  $$ select tenant_id from public.organization_settings $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000001'::uuid) $$,
  'H-TEN-018: gym Alpha sees only its own organization_settings row');

select results_eq(
  $$ select id from public.branches $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000011'::uuid) $$,
  'H-TEN-019: gym Alpha sees only its own branches');

select results_eq(
  $$ select id from public.staff $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000021'::uuid) $$,
  'H-TEN-020: gym Alpha sees only its own staff');

select results_eq(
  $$ select id from public.members $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000031'::uuid) $$,
  'H-TEN-021: gym Alpha sees only its own members');

select is_empty(
  $$ with touched as (
       update public.organizations set name = 'Seized By Alpha'
        where id = '0f1d0b02-7e57-4c0b-9b02-000000000002' returning id
     ) select id from touched $$,
  'H-TEN-022: updating the gym Bravo organization by primary key affects zero rows');

select is_empty(
  $$ with touched as (
       update public.organization_settings set invoice_prefix = 'SEIZED'
        where tenant_id = '0f1d0b02-7e57-4c0b-9b02-000000000002' returning tenant_id
     ) select tenant_id from touched $$,
  'H-TEN-023: updating gym Bravo organization_settings by primary key affects zero rows');

select is_empty(
  $$ with touched as (
       update public.branches set name = 'Seized By Alpha'
        where id = '0f1d0b02-7e57-4c0b-9b02-000000000012' returning id
     ) select id from touched $$,
  'H-TEN-024: updating a gym Bravo branch by primary key affects zero rows');

select is_empty(
  $$ with touched as (
       update public.staff set full_name = 'Seized By Alpha'
        where id = '0f1d0b02-7e57-4c0b-9b02-000000000022' returning id
     ) select id from touched $$,
  'H-TEN-025: updating a gym Bravo staff row by primary key affects zero rows');

select is_empty(
  $$ with touched as (
       update public.members set full_name = 'Seized By Alpha'
        where id = '0f1d0b02-7e57-4c0b-9b02-000000000032' returning id
     ) select id from touched $$,
  'H-TEN-026: updating a gym Bravo member by primary key affects zero rows');

select throws_ok(
  $$ insert into public.organizations (id, name, gym_code)
     values ('0f1d0d04-7e57-4c0d-9d04-000000000004', 'Alpha Forged Org', 'HLDTD4') $$,
  '42501', null,
  'H-TEN-027: gym Alpha cannot create an organization whose id is not its own tenant id');

select throws_ok(
  $$ insert into public.organization_settings (tenant_id)
     values ('0f1d0c03-7e57-4c0c-9c03-000000000003') $$,
  '42501', null,
  'H-TEN-028: gym Alpha cannot create organization_settings labelled with another tenant');

select throws_ok(
  $$ insert into public.branches (tenant_id, name)
     values ('0f1d0b02-7e57-4c0b-9b02-000000000002', 'Alpha Planted Branch') $$,
  '42501', null,
  'H-TEN-029: gym Alpha cannot insert a branch labelled with gym Bravo');

select throws_ok(
  $$ insert into public.staff (tenant_id, branch_id, role, full_name)
     values ('0f1d0b02-7e57-4c0b-9b02-000000000002',
             '0f1d0b02-7e57-4c0b-9b02-000000000012', 'front_desk', 'Alpha Planted Staff') $$,
  '42501', null,
  'H-TEN-030: gym Alpha cannot insert a staff row labelled with gym Bravo');

select throws_ok(
  $$ insert into public.members (tenant_id, branch_id, full_name, phone)
     values ('0f1d0b02-7e57-4c0b-9b02-000000000002',
             '0f1d0b02-7e57-4c0b-9b02-000000000012', 'Alpha Planted Member', '+919900000071') $$,
  '42501', null,
  'H-TEN-031: gym Alpha cannot insert a member labelled with gym Bravo');

select throws_ok(
  $$ delete from public.organizations where id = '0f1d0b02-7e57-4c0b-9b02-000000000002' $$,
  '42501', null,
  'H-TEN-032: INT-001, delete on organizations is refused for want of privilege');

select throws_ok(
  $$ delete from public.organization_settings where tenant_id = '0f1d0b02-7e57-4c0b-9b02-000000000002' $$,
  '42501', null,
  'H-TEN-033: INT-001, delete on organization_settings is refused for want of privilege');

select throws_ok(
  $$ delete from public.branches where id = '0f1d0b02-7e57-4c0b-9b02-000000000012' $$,
  '42501', null,
  'H-TEN-034: INT-001, delete on branches is refused for want of privilege');

select throws_ok(
  $$ delete from public.staff where id = '0f1d0b02-7e57-4c0b-9b02-000000000022' $$,
  '42501', null,
  'H-TEN-035: INT-001, delete on staff is refused for want of privilege');

select throws_ok(
  $$ delete from public.members where id = '0f1d0b02-7e57-4c0b-9b02-000000000032' $$,
  '42501', null,
  'H-TEN-036: INT-001, delete on members is refused for want of privilege');

set local role postgres;

-- Back as the owner, where BYPASSRLS lets us see what gym Bravo actually has.

select is(
  (select count(*) from public.organizations where id = '0f1d0b02-7e57-4c0b-9b02-000000000002')
  + (select count(*) from public.organization_settings where tenant_id = '0f1d0b02-7e57-4c0b-9b02-000000000002')
  + (select count(*) from public.branches where id = '0f1d0b02-7e57-4c0b-9b02-000000000012')
  + (select count(*) from public.staff where id = '0f1d0b02-7e57-4c0b-9b02-000000000022')
  + (select count(*) from public.members where id = '0f1d0b02-7e57-4c0b-9b02-000000000032'),
  5::bigint,
  'H-TEN-037: every gym Bravo row survives gym Alpha read, update, insert and delete attempts');

select is(
  (select full_name from public.members where id = '0f1d0b02-7e57-4c0b-9b02-000000000032'),
  'Bravo Member',
  'H-TEN-038: the gym Bravo member row is unchanged after the cross-tenant update attempt');

-- 6. The other gym-side roles. Isolation must not depend on which role inside
--    gym Alpha is acting.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '0f1d0a01-7e57-4c0a-9a01-000000000001',
                    'app_role', 'gym_manager')::text,
  true);
set local role authenticated;

select ok(not app.is_platform(), 'H-TEN-039: gym_manager is not a platform role');
select results_eq(
  $$ select id from public.members $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000031'::uuid) $$,
  'H-TEN-040: gym_manager in gym Alpha still sees only gym Alpha members');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '0f1d0a01-7e57-4c0a-9a01-000000000001',
                    'app_role', 'front_desk')::text,
  true);
set local role authenticated;

select ok(not app.is_platform(), 'H-TEN-041: front_desk is not a platform role');
select results_eq(
  $$ select id from public.members $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000031'::uuid) $$,
  'H-TEN-042: front_desk in gym Alpha still sees only gym Alpha members');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '0f1d0a01-7e57-4c0a-9a01-000000000001',
                    'app_role', 'trainer')::text,
  true);
set local role authenticated;

select ok(not app.is_platform(), 'H-TEN-043: trainer is not a platform role');
select results_eq(
  $$ select id from public.members $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000031'::uuid) $$,
  'H-TEN-044: trainer in gym Alpha still sees only gym Alpha members');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '0f1d0a01-7e57-4c0a-9a01-000000000001',
                    'app_role', 'member',
                    'member_id', '0f1d0a01-7e57-4c0a-9a01-000000000031')::text,
  true);
set local role authenticated;

select ok(not app.is_platform(), 'H-TEN-045: member is not a platform role');
-- The member gate is M(self): a member reads its own members row, never the gym's
-- roster. The isolation claim this file exists for is unchanged and is what is
-- asserted -- nothing of gym Beta's is reachable -- but the row set a member may
-- see narrowed in Phase 2, so the session now carries the member_id claim that
-- makes its own row visible.
select results_eq(
  $$ select id from public.members $$,
  $$ values ('0f1d0a01-7e57-4c0a-9a01-000000000031'::uuid) $$,
  'H-TEN-046: a member in gym Alpha reads its own row and nothing of gym Beta''s');

set local role postgres;

-- 7. The platform branch. Both platform claims deliberately carry no tenant_id
--    at all, so a pass proves the role alone opened the door and not a tenant
--    match. Row security stays enabled throughout.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true);
set local role authenticated;

select ok(app.is_platform(), 'H-TEN-047: super_admin is a platform role');

select is(
  (select count(*) from public.members
    where tenant_id in ('0f1d0a01-7e57-4c0a-9a01-000000000001', '0f1d0b02-7e57-4c0b-9b02-000000000002')), 2::bigint,
  'H-TEN-048: super_admin with no tenant claim reads members from both gyms - scoped to this file''s two tenants, because the platform branch is not tenant-filtered and the project holds other gyms'' rows');

select is(
  (select count(*) from public.organizations
    where id in ('0f1d0a01-7e57-4c0a-9a01-000000000001', '0f1d0b02-7e57-4c0b-9b02-000000000002', '0f1d0c03-7e57-4c0c-9c03-000000000003')), 3::bigint,
  'H-TEN-049: super_admin reads every one of this file''s three organization rows, including the one it holds no membership of');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true);
set local role authenticated;

select ok(app.is_platform(), 'H-TEN-050: platform_support is a platform role');

select is(
  (select count(*) from public.members
    where tenant_id in ('0f1d0a01-7e57-4c0a-9a01-000000000001', '0f1d0b02-7e57-4c0b-9b02-000000000002')), 2::bigint,
  'H-TEN-051: platform_support with no tenant claim reads members from both gyms - scoped the same way as H-TEN-048');

set local role postgres;

select is(
  (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('organizations', 'organization_settings', 'branches', 'staff', 'members')
      and c.relrowsecurity),
  5::bigint,
  'H-TEN-052: platform roles cross tenants by policy, row security is still on for all five tables');

-- 8. The privilege contract (ADR-037). RLS filters rows, it does not remove a
--    privilege, and truncate is not filtered by RLS at all.

select is_empty(
  $$ select c.relname || ' ' || p.priv
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
       cross join lateral (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                                  ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) as p(priv)
      where n.nspname = 'public'
        and c.relname in ('organizations', 'organization_settings', 'branches', 'staff', 'members')
        and has_table_privilege('anon', c.oid, p.priv) $$,
  'H-TEN-053: ADR-037, anon holds no privilege of any kind on any tenancy table');

select is_empty(
  $$ select c.relname || ' ' || p.priv
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
       cross join lateral (values ('DELETE'), ('TRUNCATE')) as p(priv)
      where n.nspname = 'public'
        and c.relname in ('organizations', 'organization_settings', 'branches', 'staff', 'members')
        and has_table_privilege('authenticated', c.oid, p.priv) $$,
  'H-TEN-054: INT-001, authenticated holds neither DELETE nor TRUNCATE on any tenancy table');

select is(
  (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     cross join lateral (values ('SELECT'), ('INSERT'), ('UPDATE')) as p(priv)
    where n.nspname = 'public'
      and c.relname in ('organizations', 'organization_settings', 'branches', 'staff', 'members')
      and has_table_privilege('authenticated', c.oid, p.priv)),
  15::bigint,
  'H-TEN-055: authenticated holds select, insert and update on all five tenancy tables');

-- 9. The two accessors, plus the shared touch function. All three live in app,
--    none in public, so none of them widens the Data API or the generated
--    types (ADR-032).

select is(
  (select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'current_tenant_id'),
  's'::"char",
  'H-TEN-056: app.current_tenant_id() is stable, so a policy evaluates it once per statement');

select is(
  (select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'is_platform'),
  's'::"char",
  'H-TEN-057: app.is_platform() is stable');

select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'current_tenant_id'),
  false,
  'H-TEN-058: app.current_tenant_id() is security invoker, it hands out no elevated context');

select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'is_platform'),
  false,
  'H-TEN-059: app.is_platform() is security invoker');

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('current_tenant_id', 'is_platform', 'touch_updated_at')),
  3::bigint,
  'H-TEN-060: the accessors and the shared touch function all live in schema app');

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('current_tenant_id', 'is_platform', 'touch_updated_at')),
  0::bigint,
  'H-TEN-061: none of the three is in public, so none appears as an RPC or in the generated types');

select ok(
  has_schema_privilege('authenticated', 'app', 'USAGE'),
  'H-TEN-062: authenticated can reach schema app, which is all a policy needs');

select ok(
  not has_schema_privilege('anon', 'app', 'USAGE'),
  'H-TEN-063: anon cannot reach schema app');

select * from finish();

rollback;
