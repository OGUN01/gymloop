-- Holdout, Phase 2 — identity: app.custom_access_token_hook.
--
-- Written blind from openspec/changes/phase-2-identity-and-tenancy/specs/identity/spec.md
-- and design.md sections 1-5. Never from the implementation, never from the visible suite.
--
-- STAGED (ADR-043): this file references app.custom_access_token_hook, which has not
-- merged. It must not sit in supabase/tests/ until the Phase 2 migration is applied.
--
-- Everything here runs as the owner, because the hook is executable by nobody else.
-- Fixtures are scoped to three synthetic organizations and eleven synthetic auth users;
-- no assertion counts an unfiltered table (ADR-050).

begin;

-- CI's pgTAP session is the CLI's NOINHERIT login role, so the owner role is
-- assumed explicitly (ADR-046).
set local role postgres;

select plan(46);

-- ---------------------------------------------------------------------------
-- Safe wrappers. The hook does not exist before the Phase 2 migration; calling a
-- missing function would abort the whole file at the first call and report one
-- failure instead of forty. These trap that, so the file is red per assertion.
-- ---------------------------------------------------------------------------

create function pg_temp.hook_raw(p_user text) returns jsonb
language plpgsql as $fn$
declare v jsonb;
begin
  execute
    'select app.custom_access_token_hook($1)'
    into v
    using jsonb_build_object(
      'user_id', p_user,
      'authentication_method', 'password',
      'claims', jsonb_build_object(
        'sub', p_user,
        'aud', 'authenticated',
        'role', 'authenticated',
        'session_id', '99999999-9999-4999-8999-999999999999',
        'aal', 'aal1',
        'exp', 1893456000,
        'iat', 1893452400,
        'email', 'fixture@example.test',
        'is_anonymous', false));
  return v;
exception when others then
  return '{}'::jsonb;
end;
$fn$;

create function pg_temp.claims_for(p_user text) returns jsonb
language sql as $fn$
  select coalesce(pg_temp.hook_raw(p_user) -> 'claims', '{}'::jsonb)
$fn$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code, created_at) values
  ('aaaa0000-0011-4000-8000-000000000001', 'Holdout Gym A', 'HA1101', '2020-01-01T00:00:00Z'),
  ('bbbb0000-0011-4000-8000-000000000002', 'Holdout Gym B', 'HB1102', '2020-01-01T00:00:00Z'),
  ('cccc0000-0011-4000-8000-000000000003', 'Holdout Gym C', 'HC1103', '2020-01-01T00:00:00Z');

insert into public.branches (id, tenant_id, name, is_default) values
  ('aaaa0000-0011-4000-8000-0000000000b1', 'aaaa0000-0011-4000-8000-000000000001', 'Main A', true),
  ('bbbb0000-0011-4000-8000-0000000000b2', 'bbbb0000-0011-4000-8000-000000000002', 'Main B', true);

insert into auth.users (id, raw_app_meta_data) values
  ('11110000-0011-4000-8000-000000000001', '{}'::jsonb),                                    -- unlinked
  ('11110000-0011-4000-8000-000000000002', '{}'::jsonb),                                    -- active super admin
  ('11110000-0011-4000-8000-000000000003', '{}'::jsonb),                                    -- inactive platform user
  ('11110000-0011-4000-8000-000000000004', '{}'::jsonb),                                    -- inactive platform + staff + member
  ('11110000-0011-4000-8000-000000000005', '{}'::jsonb),                                    -- staff and member, same gym
  ('11110000-0011-4000-8000-000000000006', '{}'::jsonb),                                    -- member only
  ('11110000-0011-4000-8000-000000000007', '{}'::jsonb),                                    -- inactive staff only
  ('11110000-0011-4000-8000-000000000008',
     '{"active_tenant_id": "bbbb0000-0011-4000-8000-000000000002"}'::jsonb),                -- valid request
  ('11110000-0011-4000-8000-000000000009',
     '{"active_tenant_id": "cccc0000-0011-4000-8000-000000000003"}'::jsonb),                -- request for a gym it has no row in
  ('11110000-0011-4000-8000-00000000000a',
     '{"active_tenant_id": "bbbb0000-0011-4000-8000-000000000002"}'::jsonb),                -- request where the row is deactivated
  ('11110000-0011-4000-8000-00000000000b', '{}'::jsonb),                                    -- no request at all
  -- Section 4 as revised: "active" for a member is status not in (cancelled, blocked)
  -- and erased_at null. paused and expired sign in normally, because renewing is what
  -- they sign in to do.
  ('11110000-0011-4000-8000-00000000000c', '{}'::jsonb),                                    -- member, expired
  ('11110000-0011-4000-8000-00000000000d', '{}'::jsonb),                                    -- member, paused
  ('11110000-0011-4000-8000-00000000000e', '{}'::jsonb),                                    -- member, cancelled
  ('11110000-0011-4000-8000-00000000000f', '{}'::jsonb),                                    -- member, blocked
  ('11110000-0011-4000-8000-000000000010', '{}'::jsonb),                                    -- member, erased
  ('11110000-0011-4000-8000-000000000011', '{}'::jsonb);                                    -- staff in two gyms, both inactive, plus an active members row

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  ('11110000-0011-4000-8000-000000000002', 'super_admin',      'Active Super',   'a@example.test', true),
  ('11110000-0011-4000-8000-000000000003', 'super_admin',      'Inactive Super', 'b@example.test', false),
  ('11110000-0011-4000-8000-000000000004', 'platform_support', 'Triple',         'c@example.test', false);

insert into public.staff (id, tenant_id, user_id, role, full_name, is_active, created_at) values
  ('22220000-0011-4000-8000-000000000001', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000004', 'gym_manager', 'Triple Staff', true, '2021-01-01T00:00:00Z'),
  ('22220000-0011-4000-8000-000000000002', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000005', 'front_desk', 'Staff And Member', true, '2021-01-01T00:00:00Z'),
  ('22220000-0011-4000-8000-000000000003', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000007', 'trainer', 'Inactive Staff', false, '2021-01-01T00:00:00Z'),
  -- switch: active in both gyms, A created first
  ('22220000-0011-4000-8000-000000000004', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000008', 'gym_owner', 'Switcher A', true, '2020-03-01T00:00:00Z'),
  ('22220000-0011-4000-8000-000000000005', 'bbbb0000-0011-4000-8000-000000000002',
     '11110000-0011-4000-8000-000000000008', 'trainer', 'Switcher B', true, '2021-03-01T00:00:00Z'),
  -- requests a third gym
  ('22220000-0011-4000-8000-000000000006', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000009', 'gym_owner', 'Bad Request A', true, '2020-04-01T00:00:00Z'),
  ('22220000-0011-4000-8000-000000000007', 'bbbb0000-0011-4000-8000-000000000002',
     '11110000-0011-4000-8000-000000000009', 'trainer', 'Bad Request B', true, '2021-04-01T00:00:00Z'),
  -- requests a gym whose row was deactivated
  ('22220000-0011-4000-8000-000000000008', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-00000000000a', 'gym_owner', 'Deact A', true, '2020-05-01T00:00:00Z'),
  ('22220000-0011-4000-8000-000000000009', 'bbbb0000-0011-4000-8000-000000000002',
     '11110000-0011-4000-8000-00000000000a', 'trainer', 'Deact B', false, '2021-05-01T00:00:00Z'),
  -- No request: the earliest active row must win. The ids are deliberately the
  -- other way round from the created_at order, so an implementation that orders
  -- by id (or takes any row) is distinguishable from one that orders by
  -- created_at with id only as the tie-break.
  ('22220000-0011-4000-8000-0000000000cc', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-00000000000b', 'gym_owner', 'Default A', true, '2020-06-01T00:00:00Z'),
  ('22220000-0011-4000-8000-0000000000c1', 'bbbb0000-0011-4000-8000-000000000002',
     '11110000-0011-4000-8000-00000000000b', 'trainer', 'Default B', true, '2021-06-01T00:00:00Z'),
  -- Section 4 as revised: resolution is decided by the TABLE, not by a row. This user has
  -- two staff rows and neither is active, so it must not fall through to its members row.
  ('22220000-0011-4000-8000-0000000000d1', 'aaaa0000-0011-4000-8000-000000000001',
     '11110000-0011-4000-8000-000000000011', 'gym_owner', 'All Dead A', false, '2020-07-01T00:00:00Z'),
  ('22220000-0011-4000-8000-0000000000d2', 'bbbb0000-0011-4000-8000-000000000002',
     '11110000-0011-4000-8000-000000000011', 'trainer', 'All Dead B', false, '2021-07-01T00:00:00Z');

insert into public.members
  (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('33330000-0011-4000-8000-000000000001', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-000000000004',
     'Triple Member', '+911100000001'),
  ('33330000-0011-4000-8000-000000000002', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-000000000005',
     'Staff Who Is Also A Member', '+911100000002'),
  ('33330000-0011-4000-8000-000000000003', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-000000000006',
     'Member Only', '+911100000003'),
  ('33330000-0011-4000-8000-000000000004', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-00000000000c',
     'Expired Member', '+911100000004'),
  ('33330000-0011-4000-8000-000000000005', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-00000000000d',
     'Paused Member', '+911100000005'),
  ('33330000-0011-4000-8000-000000000006', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-00000000000e',
     'Cancelled Member', '+911100000006'),
  ('33330000-0011-4000-8000-000000000007', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-00000000000f',
     'Blocked Member', '+911100000007'),
  ('33330000-0011-4000-8000-000000000008', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-000000000010',
     'Erased Member', '+911100000008'),
  ('33330000-0011-4000-8000-000000000009', 'aaaa0000-0011-4000-8000-000000000001',
     'aaaa0000-0011-4000-8000-0000000000b1', '11110000-0011-4000-8000-000000000011',
     'Member Under Dead Staff', '+911100000009');

update public.members set status = 'expired'   where id = '33330000-0011-4000-8000-000000000004';
update public.members set status = 'paused'    where id = '33330000-0011-4000-8000-000000000005';
update public.members set status = 'cancelled' where id = '33330000-0011-4000-8000-000000000006';
update public.members set status = 'blocked'   where id = '33330000-0011-4000-8000-000000000007';
update public.members set erased_at = now()    where id = '33330000-0011-4000-8000-000000000008';

-- ---------------------------------------------------------------------------
-- 1-10. Where the hook lives, and who may call it (identity spec, requirement 1)
-- ---------------------------------------------------------------------------

select has_function('app', 'custom_access_token_hook', array['jsonb'],
  'the access-token hook is a function in the app schema');

select hasnt_function('public', 'custom_access_token_hook', array['jsonb'],
  'the access-token hook is not in public, so it is neither an RPC nor in the generated types');

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  true,
  'the hook is security definer, so it does not need table grants to supabase_auth_admin');

select ok(
  (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  'the hook pins its search_path');

select is(
  (select pg_get_userbyid(p.proowner) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  'postgres',
  'the hook is owned by postgres, the role that holds BYPASSRLS');

select ok(
  coalesce(has_function_privilege('supabase_auth_admin',
    to_regprocedure('app.custom_access_token_hook(jsonb)'), 'execute'), false),
  'supabase_auth_admin may execute the hook');

select ok(
  coalesce(has_schema_privilege('supabase_auth_admin', 'app', 'usage'), false),
  'supabase_auth_admin holds usage on schema app');

select ok(
  coalesce(has_function_privilege('authenticated',
    to_regprocedure('app.custom_access_token_hook(jsonb)'), 'execute'), true) = false,
  'authenticated may not execute the hook');

select ok(
  coalesce(has_function_privilege('anon',
    to_regprocedure('app.custom_access_token_hook(jsonb)'), 'execute'), true) = false,
  'anon may not execute the hook');

select ok(
  coalesce(has_function_privilege('public',
    to_regprocedure('app.custom_access_token_hook(jsonb)'), 'execute'), true) = false,
  'execute on the hook is revoked from PUBLIC');

-- ---------------------------------------------------------------------------
-- 11-16. It fails closed to a claimless token, never to an exception
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$select app.custom_access_token_hook('{"claims": {"sub": "x"}}'::jsonb)$q$,
  'an event with no user_id key returns without raising');

select lives_ok(
  $q$select app.custom_access_token_hook('{"user_id": null, "claims": {}}'::jsonb)$q$,
  'an event whose user_id is JSON null returns without raising');

select lives_ok(
  $q$select app.custom_access_token_hook('{"user_id": "not-a-uuid", "claims": {}}'::jsonb)$q$,
  'an event whose user_id is not a uuid returns without raising');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000001') ? 'tenant_id'),
  'a user matching no identity row gets no tenant_id key at all');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000001') ? 'app_role'),
  'a user matching no identity row gets no app_role key at all');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000001') ? 'impersonation_session_id'),
  'a user matching no identity row gets no impersonation_session_id key');

-- ---------------------------------------------------------------------------
-- 17-20. The whole claims object comes back, reserved claims untouched
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.hook_raw('11110000-0011-4000-8000-000000000002') ? 'claims',
  'the hook returns the event object, with claims under the claims key');

select ok(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000002') @> jsonb_build_object(
    'sub', '11110000-0011-4000-8000-000000000002',
    'aud', 'authenticated',
    'session_id', '99999999-9999-4999-8999-999999999999',
    'exp', 1893456000,
    'iat', 1893452400,
    'aal', 'aal1',
    'email', 'fixture@example.test'),
  'every pre-existing claim survives the hook with its original value');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000002') ->> 'role',
  'authenticated',
  'the Postgres role claim is never rewritten, even for a super admin');

select is(
  (select count(*) from jsonb_each_text(pg_temp.claims_for('11110000-0011-4000-8000-000000000006'))
    where value = ''),
  0::bigint,
  'no claim is emitted as an empty string');

-- ---------------------------------------------------------------------------
-- 21-24. A platform token carries no gym claims
-- ---------------------------------------------------------------------------

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000002') ->> 'app_role',
  'super_admin',
  'an active super admin resolves to app_role super_admin');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-000000000002')) k
    where k in ('tenant_id', 'member_id', 'staff_id')),
  0::bigint,
  'a platform token with no live impersonation carries no gym claims at all');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000003') ? 'app_role'),
  'a deactivated platform user gets no app_role');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000003') ? 'tenant_id'),
  'a deactivated platform user gets no tenant_id');

-- ---------------------------------------------------------------------------
-- 25-30. Resolution order, and the boundary the order exists for
-- ---------------------------------------------------------------------------

-- The full cross product: simultaneously an INACTIVE platform user, an ACTIVE
-- staff member and an ACTIVE member. Resolution stops at platform_users and the
-- inactive row must not degrade into either of the two identities below it.
select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-000000000004')) k
    where k in ('app_role', 'tenant_id', 'staff_id', 'member_id')),
  0::bigint,
  'an inactive platform user who is also active staff and an active member gets no Gymloop claim');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000005') ->> 'staff_id',
  '22220000-0011-4000-8000-000000000002',
  'a user who is both staff and a member of one gym resolves as staff');

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000005') ? 'member_id'),
  'a staff token never carries member_id, even when the same human is also a member');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000005') ->> 'app_role',
  'front_desk',
  'a staff token carries the staff row role, not member');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000006') ->> 'app_role',
  'member',
  'a user whose only identity is a members row resolves as member');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000006') ->> 'member_id'
    || '|' || (pg_temp.claims_for('11110000-0011-4000-8000-000000000006') ->> 'tenant_id'),
  '33330000-0011-4000-8000-000000000003|aaaa0000-0011-4000-8000-000000000001',
  'a member token carries that member id and that member gym');

-- ---------------------------------------------------------------------------
-- 31-33. Inactive staff, and claim well-formedness
-- ---------------------------------------------------------------------------

select ok(
  not (pg_temp.claims_for('11110000-0011-4000-8000-000000000006') ? 'staff_id'),
  'a member token never carries staff_id');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-000000000007')) k
    where k in ('app_role', 'tenant_id', 'staff_id')),
  0::bigint,
  'a user whose only staff row is inactive gets no claims');

select is(
  (select count(*) from jsonb_each(pg_temp.claims_for('11110000-0011-4000-8000-000000000006'))
    where key in ('tenant_id', 'app_role', 'member_id')
      and jsonb_typeof(value) <> 'string'),
  0::bigint,
  'tenant_id, app_role and member_id are JSON strings, not objects, numbers or nulls');

-- ---------------------------------------------------------------------------
-- 34-40. One token is one gym, and the request is validated
-- ---------------------------------------------------------------------------

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000008') ->> 'tenant_id',
  'bbbb0000-0011-4000-8000-000000000002',
  'a valid active_tenant_id request is honoured');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000008') ->> 'staff_id',
  '22220000-0011-4000-8000-000000000005',
  'the honoured request also selects that gym staff row, not the other one');

select isnt(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000009') ->> 'tenant_id',
  'cccc0000-0011-4000-8000-000000000003',
  'a request naming a gym the user has no row in is never minted');

select ok(
  pg_temp.claims_for('11110000-0011-4000-8000-000000000009') ->> 'tenant_id' in (
    'aaaa0000-0011-4000-8000-000000000001', 'bbbb0000-0011-4000-8000-000000000002'),
  'an invalid request falls back to a gym the user does belong to');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-00000000000a') ->> 'tenant_id',
  'aaaa0000-0011-4000-8000-000000000001',
  'a request naming a gym where the row was deactivated falls back to the active gym');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-00000000000b') ->> 'tenant_id',
  'aaaa0000-0011-4000-8000-000000000001',
  'with no request, the active row with the earliest created_at wins');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-00000000000b') ->> 'staff_id',
  '22220000-0011-4000-8000-0000000000cc',
  'the default orders by created_at, not by id: the later-created row has the lower id here');

-- ---------------------------------------------------------------------------
-- 41-46. What "active" means for a member (section 4, revised)
-- ---------------------------------------------------------------------------

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-00000000000c') ->> 'member_id',
  '33330000-0011-4000-8000-000000000004',
  'an expired member signs in normally: renewing is what they sign in to do');

select is(
  pg_temp.claims_for('11110000-0011-4000-8000-00000000000d') ->> 'app_role',
  'member',
  'a paused member signs in normally');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-00000000000e')) k
    where k in ('app_role', 'tenant_id', 'member_id')),
  0::bigint,
  'a cancelled member gets no claims: the gym has ended the relationship');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-00000000000f')) k
    where k in ('app_role', 'tenant_id', 'member_id')),
  0::bigint,
  'a blocked member gets no claims');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-000000000010')) k
    where k in ('app_role', 'tenant_id', 'member_id')),
  0::bigint,
  'an erased member gets no claims even though its status is still active (DPD-006)');

-- Resolution is decided by the table, not by a row: no active staff row anywhere is not
-- a licence to become the member the same human also is.
select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0011-4000-8000-000000000011')) k
    where k in ('app_role', 'tenant_id', 'staff_id', 'member_id')),
  0::bigint,
  'a user whose staff rows are inactive in every gym does not fall through to its members row');

select * from finish();

rollback;
