-- Holdout, Phase 2 — impersonation, the revocation trigger, and the audit rows the
-- database writes for both.
--
-- Written blind from openspec/changes/phase-2-identity-and-tenancy/specs/impersonation/spec.md,
-- the revocation and audit requirements of specs/identity/spec.md, and design.md sections 6
-- and 7. Never from the implementation, never from the visible suite.
--
-- STAGED (ADR-043): references app.custom_access_token_hook, app.current_impersonation_id,
-- the impersonation audit trigger and the revocation trigger, none of which have merged.
--
-- ADR-050: the two organizations, the six platform accounts and the four auth users below
-- are this file's own fixtures. Every count is filtered to them; nothing counts a table.

begin;

-- CI's pgTAP session is the CLI's NOINHERIT login role, so the owner role is
-- assumed explicitly (ADR-046).
set local role postgres;

select plan(58);

create function pg_temp.hook_raw(p_user text) returns jsonb
language plpgsql as $fn$
declare v jsonb;
begin
  execute 'select app.custom_access_token_hook($1)' into v
    using jsonb_build_object(
      'user_id', p_user,
      'authentication_method', 'password',
      'claims', jsonb_build_object(
        'sub', p_user, 'aud', 'authenticated', 'role', 'authenticated',
        'session_id', '99999999-9999-4999-8999-999999999999',
        'exp', 1893456000, 'iat', 1893452400));
  return v;
exception when others then
  return '{}'::jsonb;
end;
$fn$;

create function pg_temp.claims_for(p_user text) returns jsonb
language sql as $fn$ select coalesce(pg_temp.hook_raw(p_user) -> 'claims', '{}'::jsonb) $fn$;

create function pg_temp.attempt(p_sql text) returns text
language plpgsql as $fn$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'rows=' || n;
exception when others then
  return 'error=' || sqlstate;
end;
$fn$;

-- Section 8.1 as revised: a refused insert raises 42501, and so does a write the
-- grant itself withholds. Both call sites below are inserts.
create function pg_temp.rejected(p_sql text) returns boolean
language sql as $fn$ select pg_temp.attempt(p_sql) = 'error=42501' $fn$;

create function pg_temp.allowed(p_sql text) returns boolean
language sql as $fn$ select pg_temp.attempt(p_sql) = 'rows=1' $fn$;

do $do$
begin
  execute format('grant usage on schema %s to authenticated', pg_my_temp_schema()::regnamespace);
end;
$do$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('aaaa0000-0014-4000-8000-000000000001', 'Holdout Gym A', 'HA1401'),
  ('bbbb0000-0014-4000-8000-000000000002', 'Holdout Gym B', 'HB1402');

insert into public.branches (id, tenant_id, name, is_default) values
  ('aaaa0000-0014-4000-8000-0000000000b1', 'aaaa0000-0014-4000-8000-000000000001', 'Main A', true),
  ('bbbb0000-0014-4000-8000-0000000000b2', 'bbbb0000-0014-4000-8000-000000000002', 'Main B', true);

insert into auth.users (id) values
  ('11110000-0014-4000-8000-0000000000f1'),   -- super admin with a live session
  ('11110000-0014-4000-8000-0000000000f2'),   -- support, with a session row it must not honour
  ('11110000-0014-4000-8000-0000000000f3'),   -- super admin with an expired session
  ('11110000-0014-4000-8000-0000000000f4'),   -- super admin with an ended session
  ('11110000-0014-4000-8000-0000000000f5'),   -- super admin used for the one-live-session rule
  ('11110000-0014-4000-8000-0000000000f6'),   -- super admin whose session lapses unended
  ('11110000-0014-4000-8000-0000000000f7'),   -- super admin acting through RLS
  ('11110000-0014-4000-8000-0000000000e1'),   -- staff, deactivated
  ('11110000-0014-4000-8000-0000000000e2'),   -- staff, role changed
  ('11110000-0014-4000-8000-0000000000e3'),   -- staff, renamed only
  ('11110000-0014-4000-8000-0000000000e4'),   -- platform user, deactivated
  ('11110000-0014-4000-8000-0000000000d1'),   -- member, cancelled
  ('11110000-0014-4000-8000-0000000000d2'),   -- member, paused
  ('11110000-0014-4000-8000-0000000000d3'),   -- member, erased
  ('11110000-0014-4000-8000-0000000000f8'),   -- super admin, for the TTL bound
  ('11110000-0014-4000-8000-0000000000f9'),   -- super admin, for the session that ends itself
  ('11110000-0014-4000-8000-0000000000fa'),   -- super admin, for the write-once session
  ('11110000-0014-4000-8000-0000000000fb'),   -- super admin, for the future-anchored insert
  ('11110000-0014-4000-8000-0000000000fc'),   -- super admin, for the future-anchored attempt
  ('11110000-0014-4000-8000-0000000000fd');   -- super admin, for the already-expired write

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('33330000-0014-4000-8000-0000000000a1', 'aaaa0000-0014-4000-8000-000000000001',
     'aaaa0000-0014-4000-8000-0000000000b1', null, 'Member A One', '+911400000001'),
  ('33330000-0014-4000-8000-0000000000b1', 'bbbb0000-0014-4000-8000-000000000002',
     'bbbb0000-0014-4000-8000-0000000000b2', null, 'Member B One', '+911400000002'),
  ('33330000-0014-4000-8000-0000000000c1', 'aaaa0000-0014-4000-8000-000000000001',
     'aaaa0000-0014-4000-8000-0000000000b1', '11110000-0014-4000-8000-0000000000d1',
     'To Cancel', '+911400000003'),
  ('33330000-0014-4000-8000-0000000000c2', 'aaaa0000-0014-4000-8000-000000000001',
     'aaaa0000-0014-4000-8000-0000000000b1', '11110000-0014-4000-8000-0000000000d2',
     'To Pause', '+911400000004'),
  ('33330000-0014-4000-8000-0000000000c3', 'aaaa0000-0014-4000-8000-000000000001',
     'aaaa0000-0014-4000-8000-0000000000b1', '11110000-0014-4000-8000-0000000000d3',
     'To Erase', '+911400000005');

insert into public.platform_users (user_id, role, full_name, email) values
  ('11110000-0014-4000-8000-0000000000f1', 'super_admin',      'Live Actor',    'f1@example.test'),
  ('11110000-0014-4000-8000-0000000000f2', 'platform_support', 'Support Actor', 'f2@example.test'),
  ('11110000-0014-4000-8000-0000000000f3', 'super_admin',      'Expired Actor', 'f3@example.test'),
  ('11110000-0014-4000-8000-0000000000f4', 'super_admin',      'Ended Actor',   'f4@example.test'),
  ('11110000-0014-4000-8000-0000000000f5', 'super_admin',      'Twice Actor',   'f5@example.test'),
  ('11110000-0014-4000-8000-0000000000f6', 'super_admin',      'Lapsed Actor',  'f6@example.test'),
  ('11110000-0014-4000-8000-0000000000f7', 'super_admin',      'RLS Actor',     'f7@example.test'),
  ('11110000-0014-4000-8000-0000000000e4', 'super_admin',      'To Deactivate', 'e4@example.test'),
  ('11110000-0014-4000-8000-0000000000f8', 'super_admin',      'TTL Actor',     'f8@example.test'),
  ('11110000-0014-4000-8000-0000000000f9', 'super_admin',      'Self Ender',    'f9@example.test'),
  ('11110000-0014-4000-8000-0000000000fa', 'super_admin',      'Write Once',    'fa@example.test'),
  ('11110000-0014-4000-8000-0000000000fb', 'super_admin',      'Anchor One',    'fb@example.test'),
  ('11110000-0014-4000-8000-0000000000fc', 'super_admin',      'Anchor Two',    'fc@example.test'),
  ('11110000-0014-4000-8000-0000000000fd', 'super_admin',      'Already Past',  'fd@example.test');

insert into public.staff (id, tenant_id, user_id, role, full_name) values
  ('22220000-0014-4000-8000-0000000000a1', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000e1', 'front_desk', 'To Deactivate'),
  ('22220000-0014-4000-8000-0000000000a2', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000e2', 'front_desk', 'To Promote'),
  ('22220000-0014-4000-8000-0000000000a3', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000e3', 'front_desk', 'To Rename'),
  ('22220000-0014-4000-8000-0000000000a4', 'aaaa0000-0014-4000-8000-000000000001',
     null, 'gym_owner', 'Owner A');

insert into auth.sessions (id, user_id) values
  ('cccc0000-0014-4000-8000-0000000000e1', '11110000-0014-4000-8000-0000000000e1'),
  ('cccc0000-0014-4000-8000-0000000000e2', '11110000-0014-4000-8000-0000000000e2'),
  ('cccc0000-0014-4000-8000-0000000000e3', '11110000-0014-4000-8000-0000000000e3'),
  ('cccc0000-0014-4000-8000-0000000000e4', '11110000-0014-4000-8000-0000000000e4'),
  ('cccc0000-0014-4000-8000-0000000000d1', '11110000-0014-4000-8000-0000000000d1'),
  ('cccc0000-0014-4000-8000-0000000000d2', '11110000-0014-4000-8000-0000000000d2'),
  ('cccc0000-0014-4000-8000-0000000000d3', '11110000-0014-4000-8000-0000000000d3');

-- The sessions whose liveness the hook must distinguish. Live and ended ones insert
-- normally; started_at is left to the trigger, which is the point of the new rule.
insert into public.impersonation_sessions
  (id, tenant_id, actor_user_id, reason, expires_at, ended_at) values
  ('dddd0000-0014-4000-8000-000000000001', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f1', 'support ticket 4711',
     now() + interval '1 hour', null),
  ('dddd0000-0014-4000-8000-000000000002', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f2', 'support may not impersonate',
     now() + interval '1 hour', null),
  ('dddd0000-0014-4000-8000-000000000004', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f4', 'ended',
     now() + interval '15 minutes', now()),
  -- The live session the self-ending block impersonates. Its actor is f9 and nobody
  -- else's: an actor holding a LIVE session is one the hook gives gym_owner claims to,
  -- and tests 14 and 15 assert f4 does not have that.
  ('dddd0000-0014-4000-8000-000000000008', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f9', 'the session that ends itself',
     now() + interval '1 hour', null),
  -- The live session the write-once block ends, retargets and rewrites in one
  -- statement. Its expiry is exactly now() + 1 hour and now() is the transaction
  -- timestamp, so the later assertions can name the value rather than remember it.
  ('dddd0000-0014-4000-8000-000000000009', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000fa', 'the session that is written once',
     now() + interval '1 hour', null);

-- The clamp is forward only -- least(coalesce(new.started_at, now()), now()) -- so a
-- backdated start survives and an expired session is an ordinary insert again. An
-- earlier draft of this file disabled the trigger to write these three rows; that was
-- a hole in exactly the surface the rule protects, and the rule changing removed the
-- need for it.
insert into public.impersonation_sessions
  (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at) values
  ('dddd0000-0014-4000-8000-000000000003', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f3', 'expired',
     now() - interval '2 hours', now() - interval '1 hour', null),
  ('dddd0000-0014-4000-8000-000000000006', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f6', 'lapsed, nobody ended it',
     now() - interval '3 hours', now() - interval '2 hours', null),
  ('dddd0000-0014-4000-8000-000000000007', 'aaaa0000-0014-4000-8000-000000000001',
     '11110000-0014-4000-8000-0000000000f5', 'expired, still endable',
     now() - interval '90 minutes', now() - interval '30 minutes', null);

-- ---------------------------------------------------------------------------
-- 1-2. The two structures behind the whole capability
-- ---------------------------------------------------------------------------

select has_function('app', 'current_impersonation_id', array[]::text[],
  'the impersonation claim is read through an app accessor, like every other claim');

select ok(
  exists (
    select 1
      from pg_index i
      join pg_class ic on ic.oid = i.indexrelid
      join pg_class t  on t.oid  = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and t.relname = 'impersonation_sessions'
       and i.indisunique
       and ic.relname::text collate "default"
             = 'impersonation_sessions_actor_user_id_open_key'
       and pg_get_indexdef(i.indexrelid) like '%actor_user_id%'
       and coalesce(pg_get_expr(i.indpred, i.indrelid), '') like '%ended_at%'),
  'one open session per actor is enforced by impersonation_sessions_actor_user_id_open_key');

-- ---------------------------------------------------------------------------
-- 3-4. Only a super admin may create a session
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f2', 'role', 'authenticated',
  'app_role', 'platform_support')::text, true);
set local role authenticated;

select ok(
  pg_temp.rejected($q$insert into public.impersonation_sessions
                      (tenant_id, actor_user_id, reason, expires_at)
                    values ('bbbb0000-0014-4000-8000-000000000002',
                            '11110000-0014-4000-8000-0000000000f2', 'support tried',
                            now() + interval '1 hour')$q$),
  'a platform_support account cannot create an impersonation session');

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f7', 'role', 'authenticated',
  'app_role', 'super_admin')::text, true);

select ok(
  pg_temp.allowed($q$insert into public.impersonation_sessions
                       (tenant_id, actor_user_id, reason, expires_at)
                     values ('bbbb0000-0014-4000-8000-000000000002',
                             '11110000-0014-4000-8000-0000000000f7', 'support ticket 4712',
                             now() + interval '1 hour')$q$),
  'a super admin creates an impersonation session with a reason and a future expiry');

-- ---------------------------------------------------------------------------
-- 5-8. The claims of an impersonating token
-- ---------------------------------------------------------------------------

set local role postgres;

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f1') ->> 'tenant_id',
  'aaaa0000-0014-4000-8000-000000000001',
  'an impersonating token carries the session target as tenant_id');

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f1') ->> 'app_role',
  'gym_owner',
  'an impersonating token acts as the gym owner, not as the platform');

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f1') ->> 'impersonation_session_id',
  'dddd0000-0014-4000-8000-000000000001',
  'an impersonating token names the session it is acting under');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0014-4000-8000-0000000000f1')) k
    where k in ('staff_id', 'member_id')),
  0::bigint,
  'an impersonating token carries neither staff_id nor member_id');

-- ---------------------------------------------------------------------------
-- 9-11. An impersonator has the gym reach, not the gym reach and the platform reach
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f1', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner',
  'impersonation_session_id', 'dddd0000-0014-4000-8000-000000000001')::text, true);
set local role authenticated;

-- Named row rather than a count. ADR-050's lesson generalises past the seeded demo
-- gym: an expected number tracks how much data happens to exist, and this one broke
-- the moment the revocation fixtures added three more members to the same gym. The
-- property is "the target gym's rows are reachable", and the row scoping is test 10's.
select isnt_empty(
  $q$select id from public.members
      where id = '33330000-0014-4000-8000-0000000000a1'$q$,
  'an impersonating session reads the target gym rows');

select is(
  (select count(*) from public.members
    where tenant_id = 'bbbb0000-0014-4000-8000-000000000002'),
  0::bigint,
  'an impersonating session reads nothing from a second gym');

select is(
  (select count(*) from public.platform_users), 0::bigint,
  'an impersonating session cannot reach the platform roster');

-- ---------------------------------------------------------------------------
-- 12-17. Expired, ended, and the role that may not impersonate at all
-- ---------------------------------------------------------------------------

set local role postgres;

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f3') ->> 'app_role',
  'super_admin',
  'an expired session leaves an ordinary platform token');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0014-4000-8000-0000000000f3')) k
    where k in ('tenant_id', 'impersonation_session_id')),
  0::bigint,
  'an expired session sets neither tenant_id nor impersonation_session_id');

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f4') ->> 'app_role',
  'super_admin',
  'an ended session leaves an ordinary platform token');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0014-4000-8000-0000000000f4')) k
    where k in ('tenant_id', 'impersonation_session_id')),
  0::bigint,
  'an ended session sets neither tenant_id nor impersonation_session_id');

select is(
  pg_temp.claims_for('11110000-0014-4000-8000-0000000000f2') ->> 'app_role',
  'platform_support',
  'a support account with a live session row still gets its own platform role');

select is(
  (select count(*) from jsonb_object_keys(
     pg_temp.claims_for('11110000-0014-4000-8000-0000000000f2')) k
    where k in ('tenant_id', 'impersonation_session_id')),
  0::bigint,
  'a live session row belonging to platform_support is never honoured by the hook');

-- ---------------------------------------------------------------------------
-- 18-19. One live session per actor
-- ---------------------------------------------------------------------------

-- Four arguments, with a null expected message. throws_ok's THIRD argument is the
-- expected message, not the description -- a three-argument call compares the
-- description against Postgres's own error text. It fails loudly here, but the
-- dangerous direction is the other one: a description that happened to match the
-- message would let a wrong SQLSTATE pass unnoticed.
select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
     values ('bbbb0000-0014-4000-8000-000000000002',
             '11110000-0014-4000-8000-0000000000f1', 'a second live one',
             now() + interval '1 hour')$q$,
  '23505', null,
  'a second live session for the same actor is rejected');

-- The stated cost of indexing only the open half: an actor whose session expired but
-- was never ended cannot open a new one until someone ends it, which is what writes
-- the end audit row.
select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
     values ('bbbb0000-0014-4000-8000-000000000002',
             '11110000-0014-4000-8000-0000000000f6', 'after an expired one',
             now() + interval '1 hour')$q$,
  '23505', null,
  'an expired but unended session still blocks a second one for the same actor');

update public.impersonation_sessions set ended_at = now()
 where id = 'dddd0000-0014-4000-8000-000000000001';

select lives_ok(
  $q$insert into public.impersonation_sessions
       (id, tenant_id, actor_user_id, reason, expires_at)
     values ('dddd0000-0014-4000-8000-000000000005',
             'bbbb0000-0014-4000-8000-000000000002',
             '11110000-0014-4000-8000-0000000000f1', 'the next one',
             now() + interval '1 hour')$q$,
  'a new session is allowed once the previous one has ended');

-- ---------------------------------------------------------------------------
-- 20-24. The audit rows the database writes, and the one it must refuse
-- ---------------------------------------------------------------------------

-- Section 6 now specifies this row column by column. The trigger fires under postgres
-- or service_role and holds no JWT, so every value comes from the session row.
select ok(
  exists (
    select 1 from public.audit_log
     where action = 'impersonation_session.started'
       and record_type = 'impersonation_session'
       and record_id = 'dddd0000-0014-4000-8000-000000000001'
       and impersonation_session_id = 'dddd0000-0014-4000-8000-000000000001'
       and tenant_id = 'aaaa0000-0014-4000-8000-000000000001'
       and actor_user_id = '11110000-0014-4000-8000-0000000000f1'
       and actor_role = 'super_admin'
       and reason = 'support ticket 4711'),
  'the start audit row carries every column section 6 names, the actor coming from the session row');

select ok(
  exists (
    select 1 from public.audit_log
     where action = 'impersonation_session.ended'
       and record_type = 'impersonation_session'
       and record_id = 'dddd0000-0014-4000-8000-000000000001'
       and impersonation_session_id = 'dddd0000-0014-4000-8000-000000000001'
       and actor_user_id = '11110000-0014-4000-8000-0000000000f1'
       and reason = 'support ticket 4711'),
  'the end audit row repeats the reason and is found through impersonation_session_id');

select is(
  (select count(*) from public.audit_log
    where record_id = 'dddd0000-0014-4000-8000-000000000001'),
  2::bigint,
  'ending the session writes a second audit row for it, without the caller asking');

select is(
  (select count(*) from public.audit_log
    where record_id = 'dddd0000-0014-4000-8000-000000000006'),
  1::bigint,
  'a session that lapsed unended has a start audit row and no end audit row');

select ok(
  (select expires_at < now() and ended_at is null from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-000000000006'),
  'the lapsed session still shows its expiry and a null end time, so a reader can tell');

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f7', 'role', 'authenticated',
  'app_role', 'super_admin')::text, true);
set local role authenticated;

select ok(
  pg_temp.rejected($q$insert into public.audit_log (tenant_id, action, record_type)
                    values ('aaaa0000-0014-4000-8000-000000000001',
                            'impersonation.started', 'impersonation_session')$q$),
  'not even a super admin writes an audit row by hand: the database is the only writer');

-- ---------------------------------------------------------------------------
-- 25-26. A gym sees who impersonated it, and only its owner and manager may look
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0014-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner', 'staff_id', '22220000-0014-4000-8000-0000000000a4')::text, true);

select ok(
  (select count(*) from public.impersonation_sessions) > 0,
  'an owner reads the impersonation sessions targeting its own gym');

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0014-4000-8000-000000000002', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'front_desk', 'staff_id', '22220000-0014-4000-8000-0000000000a1')::text, true);

select is(
  (select count(*) from public.impersonation_sessions), 0::bigint,
  'front desk reads no impersonation history');

-- ---------------------------------------------------------------------------
-- 27-30. Deactivation and role change revoke the sessions already issued
-- ---------------------------------------------------------------------------

set local role postgres;

update public.staff set is_active = false
 where id = '22220000-0014-4000-8000-0000000000a1';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000e1'),
  0::bigint,
  'deactivating a staff row deletes that user authentication sessions');

update public.staff set role = 'gym_manager'
 where id = '22220000-0014-4000-8000-0000000000a2';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000e2'),
  0::bigint,
  'changing a staff row role deletes that user authentication sessions');

-- INT-003 names a role change as an audited event, and the same trigger owes the row.
select ok(
  exists (
    select 1 from public.audit_log
     where record_id = '22220000-0014-4000-8000-0000000000a2'
       and before ->> 'role' = 'front_desk'
       and after  ->> 'role' = 'gym_manager'),
  'a staff role change writes an audit row naming the previous and the new role');

update public.platform_users set is_active = false
 where user_id = '11110000-0014-4000-8000-0000000000e4';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000e4'),
  0::bigint,
  'deactivating a platform user deletes that user authentication sessions');

-- Section 7 as revised: for members, "stops being active" is status becoming
-- cancelled or blocked, or erased_at being set. paused and expired revoke nothing.
update public.members set status = 'cancelled'
 where id = '33330000-0014-4000-8000-0000000000c1';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000d1'),
  0::bigint,
  'cancelling a member deletes that user authentication sessions');

update public.members set erased_at = now()
 where id = '33330000-0014-4000-8000-0000000000c3';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000d3'),
  0::bigint,
  'erasing a member deletes that user authentication sessions (DPD-006)');

update public.members set status = 'paused'
 where id = '33330000-0014-4000-8000-0000000000c2';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000d2'),
  1::bigint,
  'pausing a member revokes nothing: a paused member signs in to renew');

update public.staff set full_name = 'Renamed, Nothing Else'
 where id = '22220000-0014-4000-8000-0000000000a3';

select is(
  (select count(*) from auth.sessions
    where user_id = '11110000-0014-4000-8000-0000000000e3'),
  1::bigint,
  'an update that changes neither is_active nor role revokes nothing');

-- ---------------------------------------------------------------------------
-- 37-43. An impersonating session ends itself, and reaches nothing else
--
-- The claims below are the ones the hook actually mints for an impersonating
-- caller -- app_role gym_owner, the target as tenant_id, the session id, and no
-- staff_id or member_id. A super_admin claim here would be a fiction: while a
-- session is live its actor cannot hold one, which is the whole reason this
-- fourth policy exists.
-- ---------------------------------------------------------------------------

set local role postgres;

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f9', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner',
  'impersonation_session_id', 'dddd0000-0014-4000-8000-000000000008')::text, true);
set local role authenticated;

-- The path reaches exactly one row, so an attempt on another actor's live session
-- is filtered rather than refused -- zero rows, no error, the same semantics as
-- every other refused update in the schema.
select ok(
  pg_temp.attempt($q$update public.impersonation_sessions set ended_at = now()
                     where id = 'dddd0000-0014-4000-8000-000000000002'$q$) = 'rows=0',
  'an impersonating session cannot end a different actor session');

-- The with check is the interesting half: ending is the only thing this path can
-- do, so an impersonator cannot buy itself more time.
select ok(
  pg_temp.attempt($q$update public.impersonation_sessions
                        set expires_at = now() + interval '1 hour'
                      where id = 'dddd0000-0014-4000-8000-000000000008'$q$) = 'error=42501',
  'an impersonating session cannot extend its own expiry through the end path');

-- Seam: the policy is `for update`, so it opens no way to write a fresh session
-- either. The platform write policy would need a super_admin claim, which this
-- caller is prevented from holding for exactly as long as it is impersonating.
select ok(
  pg_temp.attempt($q$insert into public.impersonation_sessions
                       (tenant_id, actor_user_id, reason, expires_at)
                     values ('aaaa0000-0014-4000-8000-000000000001',
                             '11110000-0014-4000-8000-0000000000f9', 'a fresh one',
                             now() + interval '1 hour')$q$) = 'error=42501',
  'an impersonating session cannot open a new session, which would be an extension by another name');

select ok(
  pg_temp.attempt($q$update public.impersonation_sessions set ended_at = now()
                     where id = 'dddd0000-0014-4000-8000-000000000008'$q$) = 'rows=1',
  'an impersonating session ends its own session');

select ok(
  exists (
    select 1 from public.audit_log
     where action = 'impersonation_session.ended'
       and record_id = 'dddd0000-0014-4000-8000-000000000008'
       and impersonation_session_id = 'dddd0000-0014-4000-8000-000000000008'
       and actor_user_id = '11110000-0014-4000-8000-0000000000f9'),
  'the end audit row lands when the impersonator ends its own session');

-- Seam: the policy carries no liveness term, and must not. Requiring the session
-- to be live would recreate the unreachable state for an abandoned one -- and the
-- open-session index forces an explicit end before that actor can work again.
select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000f5', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner',
  'impersonation_session_id', 'dddd0000-0014-4000-8000-000000000007')::text, true);

select ok(
  pg_temp.attempt($q$update public.impersonation_sessions set ended_at = now()
                     where id = 'dddd0000-0014-4000-8000-000000000007'$q$) = 'rows=1',
  'an expired session is still endable by its own claim, so an abandoned one is not stuck open');

-- A gym-side session with no impersonation claim reaches nothing, even for a
-- session targeting its own gym.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0014-4000-8000-000000000004', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner', 'staff_id', '22220000-0014-4000-8000-0000000000a4')::text, true);

select ok(
  pg_temp.attempt($q$update public.impersonation_sessions set ended_at = now()
                     where id = 'dddd0000-0014-4000-8000-000000000002'$q$) = 'rows=0',
  'a gym owner carrying no impersonation claim cannot end a session targeting its own gym');

-- ---------------------------------------------------------------------------
-- 44-45. A hard TTL is a bound, not a future timestamp
--
-- As the owner, so only the constraint can be what refuses the write. Neither
-- assertion sits on the boundary: the design says "two hours" without naming the
-- operator, and a test that depends on which one was chosen is a test of the
-- implementer's coin toss.
-- ---------------------------------------------------------------------------

set local role postgres;

select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
     values ('aaaa0000-0014-4000-8000-000000000001',
             '11110000-0014-4000-8000-0000000000f8', 'ten years of support',
             now() + interval '10 years')$q$,
  '23514', null,
  'a session whose expiry is ten years after its start is rejected');

select lives_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
     values ('aaaa0000-0014-4000-8000-000000000001',
             '11110000-0014-4000-8000-0000000000f8', 'one hour of support',
             now() + interval '1 hour')$q$,
  'a session whose expiry is one hour after its start is accepted');

-- The operator is `<=` now, so the boundary is testable, and a bound's boundary is
-- the one case an off-by-one gets wrong. started_at defaults to now() and both now()
-- calls are the same transaction timestamp, so this span is exactly two hours. f9 is
-- free because the block above ended its session.
select lives_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
     values ('aaaa0000-0014-4000-8000-000000000001',
             '11110000-0014-4000-8000-0000000000f9', 'exactly the maximum',
             now() + interval '2 hours')$q$,
  'a session whose expiry is exactly two hours after its start is accepted');

-- ---------------------------------------------------------------------------
-- 47-55. A session is written once and then only ended
--
-- Two mechanisms now stop a retarget, and a test that only proves "the retarget
-- failed" cannot say which one held. They are deliberately separated below:
--
--   the trigger catches   a change to reason or expires_at, which no policy clause
--                         mentions at all -- assertions 49 and 51 are the only
--                         things in either suite that would notice if the trigger
--                         were dropped as redundant;
--   the policy catches    a caller whose impersonation claim names this session but
--                         whose tenant claim names another gym -- assertion 52. The
--                         trigger cannot help there: it restores columns on a row
--                         the policy has already admitted.
--
-- Their overlap is the tenant column, and only there.
-- ---------------------------------------------------------------------------

set local role postgres;

select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000fa', 'role', 'authenticated',
  'tenant_id', 'aaaa0000-0014-4000-8000-000000000001',
  'app_role', 'gym_owner',
  'impersonation_session_id', 'dddd0000-0014-4000-8000-000000000009')::text, true);
set local role authenticated;

-- One statement that ends the session and, in the same breath, retargets it at
-- another gym and rewrites why it existed. It is not refused -- the trigger restores
-- the columns before the row-security check ever sees them, so the write lands with
-- only the end time changed. That is the shape to assert: succeeded, and changed
-- nothing it was not allowed to change.
select ok(
  pg_temp.attempt($q$update public.impersonation_sessions
                        set ended_at = now(),
                            tenant_id = 'bbbb0000-0014-4000-8000-000000000002',
                            reason    = 'rewritten after the fact'
                      where id = 'dddd0000-0014-4000-8000-000000000009'$q$) = 'rows=1',
  'ending a session succeeds even when the statement also tries to retarget and rewrite it');

select is(
  (select tenant_id from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-000000000009'),
  'aaaa0000-0014-4000-8000-000000000001'::uuid,
  'the stored tenant is the gym that was actually impersonated, not the one the caller sent');

select is(
  (select reason from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-000000000009'),
  'the session that is written once',
  'the stored reason is unchanged -- the one column no policy clause mentions');

select ok(
  exists (
    select 1 from public.audit_log
     where action = 'impersonation_session.ended'
       and record_id = 'dddd0000-0014-4000-8000-000000000009'
       and tenant_id = 'aaaa0000-0014-4000-8000-000000000001'
       and reason = 'the session that is written once'),
  'the end audit row names the gym actually impersonated, so the trigger ran before the audit trigger');

-- The session has ended. Extending it now is the same class of write, and the same
-- mechanism refuses it: the policy admits the row, the trigger puts the expiry back.
do $extend$ begin
  perform pg_temp.attempt($q$update public.impersonation_sessions
                               set expires_at = now() + interval '2 hours'
                             where id = 'dddd0000-0014-4000-8000-000000000009'$q$);
end; $extend$;

select is(
  (select expires_at from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-000000000009'),
  now() + interval '1 hour',
  'the stored expiry is unchanged after an attempt to extend an ended session');

-- Clearing the end time is the one write the trigger cannot catch, because ended_at is
-- the one column it must not restore. The policy's `with check` carries it instead, so
-- a session that has ended does not come back to life.
do $reopen$ begin
  perform pg_temp.attempt($q$update public.impersonation_sessions set ended_at = null
                             where id = 'dddd0000-0014-4000-8000-000000000009'$q$);
end; $reopen$;

select is(
  (select ended_at from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-000000000009'),
  now(),
  'an ended session cannot be re-opened by clearing its end time');

-- The policy-only half: the impersonation claim names this session, but the tenant
-- claim names another gym. No column restoration can catch this, because the row is
-- never admitted in the first place.
select set_config('request.jwt.claims', json_build_object(
  'sub', '11110000-0014-4000-8000-0000000000fa', 'role', 'authenticated',
  'tenant_id', 'bbbb0000-0014-4000-8000-000000000002',
  'app_role', 'gym_owner',
  'impersonation_session_id', 'dddd0000-0014-4000-8000-000000000009')::text, true);

select ok(
  pg_temp.attempt($q$update public.impersonation_sessions set ended_at = now()
                     where id = 'dddd0000-0014-4000-8000-000000000009'$q$) = 'rows=0',
  'a claim naming this session but another gym reaches no row: the tenant term, not the trigger');

-- ---------------------------------------------------------------------------
-- The anchor, as the owner so only the trigger and the constraints can act
-- ---------------------------------------------------------------------------

set local role postgres;

-- started_at ten years out with an expiry one hour out is a row that could not exist
-- without the trigger -- expires_at > started_at would refuse it. It is accepted
-- because the anchor is applied first, which is the whole claim.
do $anchor_one$ begin
  perform pg_temp.attempt($q$insert into public.impersonation_sessions
                               (id, tenant_id, actor_user_id, reason, started_at, expires_at)
                             values ('dddd0000-0014-4000-8000-00000000000a',
                                     'aaaa0000-0014-4000-8000-000000000001',
                                     '11110000-0014-4000-8000-0000000000fb',
                                     'anchored in the future',
                                     now() + interval '10 years', now() + interval '1 hour')$q$);
end; $anchor_one$;

select ok(
  (select started_at from public.impersonation_sessions
    where id = 'dddd0000-0014-4000-8000-00000000000a') <= now() + interval '1 minute',
  'a start time ten years out is replaced by the time of writing');

-- The form the critic measured: the anchor in the future and the expiry two hours
-- after it, which spans a decade once the anchor is corrected. Whether that is
-- corrected or refused is the implementer's to choose; what may never happen is a
-- session sitting in the table alive for ten years, so that is what is asserted.
-- The bound is measured from the corrected anchor, so an expiry two hours after a
-- start ten years out names a span of a decade and is refused. Under the old
-- unclamped rule this row was accepted and live for ten years, which is what the
-- second critic measured.
select throws_ok(
  $q$insert into public.impersonation_sessions
       (id, tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('dddd0000-0014-4000-8000-00000000000b',
             'aaaa0000-0014-4000-8000-000000000001',
             '11110000-0014-4000-8000-0000000000fc', 'ten years live',
             now() + interval '10 years',
             now() + interval '10 years' + interval '2 hours')$q$,
  '23514', null,
  'a future anchor cannot buy a longer session: the span is measured from the corrected start');

-- A past anchor is history, not a defect. This is also what every expired fixture row
-- in this file depends on, so it is asserted rather than assumed.
do $already_past$ begin
  perform pg_temp.attempt($q$insert into public.impersonation_sessions
                               (id, tenant_id, actor_user_id, reason, started_at, expires_at)
                             values ('dddd0000-0014-4000-8000-00000000000c',
                                     'aaaa0000-0014-4000-8000-000000000001',
                                     '11110000-0014-4000-8000-0000000000fd', 'already over',
                                     now() - interval '3 hours', now() - interval '2 hours')$q$);
end; $already_past$;

select ok(
  exists (select 1 from public.impersonation_sessions
           where id = 'dddd0000-0014-4000-8000-00000000000c'
             and started_at = now() - interval '3 hours')
  and not (pg_temp.claims_for('11110000-0014-4000-8000-0000000000fd') ? 'impersonation_session_id'),
  'a session whose start and expiry are both past is written, keeps its start, and is not live');

-- The net, kept from the round when the outcome was unspecified: whatever path a row
-- arrives by, none may sit in the table anchored ahead of now or outliving the bound.
select is(
  (select count(*) from public.impersonation_sessions
    where tenant_id in ('aaaa0000-0014-4000-8000-000000000001',
                        'bbbb0000-0014-4000-8000-000000000002')
      and (started_at > now() + interval '1 minute'
        or expires_at > now() + interval '2 hours' + interval '1 minute')),
  0::bigint,
  'no impersonation session is anchored in the future or outlives the bound, however it was written');

-- Firing order, pinned rather than inferred from its effect. Postgres runs BEFORE row
-- triggers in name order, so if both are BEFORE the immutability one must sort first;
-- if the audit trigger is AFTER, the order is guaranteed whatever they are called.
-- Asserting only the corrected audit row would pass for the wrong reason on a schema
-- where the names happen to sort the right way today and are renamed tomorrow.
select ok(
  exists (
    select 1 from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
     where tg.tgrelid = 'public.impersonation_sessions'::regclass and not tg.tgisinternal
       and p.proname::text collate "default" = 'impersonation_session_immutable'
       and (tg.tgtype & 2) = 2)
  and not exists (
    select 1
      from pg_trigger i join pg_proc ip on ip.oid = i.tgfoid,
           pg_trigger a join pg_proc ap on ap.oid = a.tgfoid
     where i.tgrelid = 'public.impersonation_sessions'::regclass and not i.tgisinternal
       and a.tgrelid = 'public.impersonation_sessions'::regclass and not a.tgisinternal
       and ip.proname::text collate "default" = 'impersonation_session_immutable'
       and ap.proname::text collate "default" <> 'impersonation_session_immutable'
       and ap.prosrc ~* 'audit_log'
       and (a.tgtype & 2) = 2
       and (i.tgname::text collate "default") >= (a.tgname::text collate "default")),
  'the immutability trigger is a BEFORE trigger and no audit trigger fires ahead of it');

select * from finish();

rollback;
