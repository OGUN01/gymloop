-- 14_impersonation - a super admin acting as a gym: the claims the token
-- carries, the claims it must NOT carry, the one-live-session rule, the audit
-- rows the database writes, and the two roles this feature finally separates.
--
-- Written from openspec/changes/phase-2-identity-and-tenancy/design.md
-- section 6 and .../specs/impersonation/spec.md, before the implementation
-- exists (AGENTS.md rule 10). Phase 1 built the table and its check
-- constraints; 10_platform_rls covers those. This file is the behaviour.
--
-- WHAT THIS FILE COVERS EXHAUSTIVELY, AND WHAT IT SAMPLES
--
-- Exhaustive: all four states an impersonation session can be in when the hook
-- runs (live, expired, ended, belonging to platform_support), because each is
-- a different wrong answer and the difference between them is one boolean in
-- one predicate. Also exhaustive: the claim set an impersonating token
-- carries, asserted as EQUALITY over the whole set rather than as presence
-- tests, so a leaked staff_id or member_id fails it.
--
-- A note on `sub`, because it is load-bearing here and is inert everywhere
-- else in the suite: design.md 6 gates impersonation_sessions_platform_write on
-- `actor_user_id = (select auth.uid())`, and auth.uid() reads the `sub` claim.
-- So every claims block below sets `sub` to the platform user it is acting as,
-- rather than to a random uuid as the other files do. A block that left `sub`
-- random would fail every write here, for a reason that has nothing to do with
-- what it is testing.
--
-- Sampled: the reach of an impersonating session is probed on members,
-- platform_users and plans rather than on all thirty-six tables. Once
-- app.is_platform() is false and the tenant claim is the target gym, the reach
-- is the gym_owner row of the matrix, which 12_role_matrix_read and
-- 13_role_matrix_write already assert table by table. What is new here, and
-- what is asserted, is that the token is NOT ALSO a platform token.
--
-- ADR-050: every count is scoped to this file's own fixtures. The audit
-- assertions in particular count rows for one named record_id, never rows in
-- audit_log.
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(21);

-- ---------------------------------------------------------------------------
-- Fixtures. Five platform accounts, each in a different session state, so
-- that no assertion below depends on the state of another's row.
--
--   a1  super_admin       one LIVE session targeting gym A
--   a2  platform_support  one LIVE session targeting gym A -- which must be
--                         ignored, because support may not impersonate
--   a3  super_admin       one EXPIRED session (never ended, expiry passed)
--   a4  super_admin       one ENDED session
--   a5  super_admin       no session at all to begin with -- the actor the
--                         create / end / re-create sequence uses, so that
--                         sequence never collides with another test's row
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('14000000-0000-4000-8000-000000000001'::uuid, 'Imp Gym A', 'IMPRSA'),
  ('14000000-0000-4000-8000-000000000002'::uuid, 'Imp Gym B', 'IMPRSB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('14000000-0000-4000-8000-000000000011'::uuid, '14000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('14000000-0000-4000-8000-000000000012'::uuid, '14000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('14000000-0000-4000-8000-000000000031'::uuid, '14000000-0000-4000-8000-000000000001'::uuid,
   '14000000-0000-4000-8000-000000000011'::uuid, 'Member A', '+91140000031'),
  ('14000000-0000-4000-8000-000000000032'::uuid, '14000000-0000-4000-8000-000000000002'::uuid,
   '14000000-0000-4000-8000-000000000012'::uuid, 'Member B', '+91140000032');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('14000000-0000-4000-8000-000000000041'::uuid, '14000000-0000-4000-8000-000000000001'::uuid, 'A Monthly', 30, 200000);

insert into auth.users (id) values
  ('14000000-0000-4000-8000-0000000000a1'::uuid),
  ('14000000-0000-4000-8000-0000000000a2'::uuid),
  ('14000000-0000-4000-8000-0000000000a3'::uuid),
  ('14000000-0000-4000-8000-0000000000a4'::uuid),
  ('14000000-0000-4000-8000-0000000000a5'::uuid);

insert into public.platform_users (user_id, role, full_name, email) values
  ('14000000-0000-4000-8000-0000000000a1'::uuid, 'super_admin',      'Live Actor',    'a1.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a2'::uuid, 'platform_support', 'Support Actor', 'a2.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a3'::uuid, 'super_admin',      'Lapsed Actor',  'a3.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a4'::uuid, 'super_admin',      'Ended Actor',   'a4.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a5'::uuid, 'super_admin',      'Idle Actor',    'a5.14@gymloop.test');

insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at) values
  ('14000000-0000-4000-8000-000000000051'::uuid, '14000000-0000-4000-8000-000000000001'::uuid,
   '14000000-0000-4000-8000-0000000000a1'::uuid, 'billing dispute',
   now() - interval '10 minute', now() + interval '50 minute', null),
  ('14000000-0000-4000-8000-000000000054'::uuid, '14000000-0000-4000-8000-000000000001'::uuid,
   '14000000-0000-4000-8000-0000000000a2'::uuid, 'support wants a look',
   now() - interval '10 minute', now() + interval '50 minute', null),
  ('14000000-0000-4000-8000-000000000052'::uuid, '14000000-0000-4000-8000-000000000001'::uuid,
   '14000000-0000-4000-8000-0000000000a3'::uuid, 'abandoned halfway',
   now() - interval '3 hour', now() - interval '2 hour', null),
  ('14000000-0000-4000-8000-000000000053'::uuid, '14000000-0000-4000-8000-000000000001'::uuid,
   '14000000-0000-4000-8000-0000000000a4'::uuid, 'finished properly',
   now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour 30 minute');

-- ---------------------------------------------------------------------------
-- 1-4. What the hook makes of each session state. Called directly as an
--      ordinary function (design.md section 2's corollary), with claims of
--      exactly {sub, aud, role, session_id} so that deleting those four keys
--      from the result leaves exactly what the hook added.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '14000000-0000-4000-8000-0000000000a1',
      'claims', jsonb_build_object('sub', '14000000-0000-4000-8000-0000000000a1',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '14000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'gym_owner',
                     'tenant_id', '14000000-0000-4000-8000-000000000001',
                     'impersonation_session_id', '14000000-0000-4000-8000-000000000051'),
  'spec "The claims of an impersonating token": the target as tenant_id, gym_owner as app_role, the session id -- and no staff_id and no member_id, which the equality here is what proves. Note app_role is NOT super_admin: an impersonator has the gym''s reach, not the gym''s reach AND the platform''s'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '14000000-0000-4000-8000-0000000000a3',
      'claims', jsonb_build_object('sub', '14000000-0000-4000-8000-0000000000a3',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '14000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'super_admin'),
  'spec "An expired session": a session past expires_at is not live, so the next refresh drops the claims and the actor is an ordinary super admin again -- which is why expiry needs no sweeper job'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '14000000-0000-4000-8000-0000000000a4',
      'claims', jsonb_build_object('sub', '14000000-0000-4000-8000-0000000000a4',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '14000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'super_admin'),
  'spec "An ended session": ended_at set is the other half of "live", and the two halves are asserted separately because an implementation that checks only expiry passes the test above and fails this one'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '14000000-0000-4000-8000-0000000000a2',
      'claims', jsonb_build_object('sub', '14000000-0000-4000-8000-0000000000a2',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '14000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'platform_support'),
  'spec "Only a super admin may impersonate": the support account HAS a live session row targeting gym A and the hook ignores it entirely -- this is one half of what finally makes platform_support and super_admin different roles rather than two labels'
);

-- ---------------------------------------------------------------------------
-- 5-6. The structural half of "one live session per actor", and the audit
--      asymmetry the design names rather than papers over.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1
      from pg_index i
      join pg_class ic on ic.oid = i.indexrelid
      join pg_class c on c.oid = i.indrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'impersonation_sessions'
       and ic.relname::text = 'impersonation_sessions_actor_user_id_open_key'
       and i.indisunique and i.indisvalid and i.indnkeyatts = 1
       and (select a.attname from pg_attribute a
             where a.attrelid = c.oid and a.attnum = i.indkey[0]) = 'actor_user_id'
       and i.indpred is not null
       and pg_get_expr(i.indpred, i.indrelid) ~* 'ended_at is null'
  ),
  'design.md 6: a PARTIAL unique index named impersonation_sessions_actor_user_id_open_key on actor_user_id where ended_at is null. The qualifier is OPEN and not LIVE, and the name carries the distinction deliberately: now() is not immutable, so `expires_at > now()` cannot appear in an index predicate at all. Only the open half of liveness is enforceable, and the consequence is exact -- an actor may hold one open session which has already expired, and must end it before starting another'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '14000000-0000-4000-8000-000000000052'::uuid
      and exists (select 1 from public.impersonation_sessions
                   where id = '14000000-0000-4000-8000-000000000052'::uuid
                     and ended_at is null and expires_at < now())),
  1::bigint,
  'spec "A lapsed session has no end audit row": nothing sweeps the table, so an abandoned session leaves a start with no matching end and keeps a null ended_at beside a past expires_at. A reader of audit_log must use expires_at rather than assume an end row exists, and this asserts the shape that forces them to'
);

-- ---------------------------------------------------------------------------
-- 7-15. Acting as a super admin: being refused a session in somebody else's
--        name, creating one in its own, ending it, being refused a second OPEN
--        session -- twice, once where the first is live and once where it has
--        expired but was never ended -- and starting again once the first has
--        ended. The audit rows are counted for one named record, never over the
--        table (ADR-050).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a5', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000002',
            '14000000-0000-4000-8000-0000000000a1',
            'opened in somebody else''s name',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A super admin naming someone else as the actor": _platform_write gates the CALLER, and without `actor_user_id = auth.uid()` it says nothing about the actor COLUMN -- so a super admin could open a session naming a different platform user, including a platform_support account which may not impersonate at all, and the audit trail would then name the wrong person'
);

select lives_ok(
  $$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000055',
            '14000000-0000-4000-8000-000000000002',
            '14000000-0000-4000-8000-0000000000a5',
            'gym B asked for help with onboarding',
            now() + interval '1 hour')$$,
  'spec "A super admin creating a session" / "A super admin naming itself": a stated reason, a future expiry, and an actor that is the caller. The control for the assertion above -- without it, a policy of `with check (false)` would look correct'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '14000000-0000-4000-8000-000000000055'::uuid
      and tenant_id = '14000000-0000-4000-8000-000000000002'::uuid
      and actor_user_id = '14000000-0000-4000-8000-0000000000a5'::uuid
      and actor_role = 'super_admin'
      and impersonation_session_id = '14000000-0000-4000-8000-000000000055'::uuid
      and record_type = 'impersonation_session'
      and action = 'impersonation_session.started'
      and reason = 'gym B asked for help with onboarding'
      and before is null
      and after is not null),
  1::bigint,
  'spec "Starting a session" / design.md 6, column by column: the DATABASE writes the row. actor_user_id comes from impersonation_sessions.actor_user_id and NEVER from a claim -- the trigger fires under service_role or postgres and holds no JWT, so a hook-style `current_setting` read would write null here. record_id and impersonation_session_id both carry the session id on purpose: the first says what the row is about, the second is the column every other audit row uses to say what session it was written under. before is null on a start; after carries the summary INT-003 requires'
);

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a5',
            'a second gym at the same time',
            now() + interval '1 hour')$$,
  '23505', null,
  'spec "A second live session": the actor already has one that has not ended, so the partial unique index refuses. Without it the tenant an impersonating token names would be ambiguous and the hook would need an ordering rule nobody has written'
);

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a3', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a3',
            'the lapsed actor tries again',
            now() + interval '1 hour')$$,
  '23505', null,
  'design.md 6: actor a3''s only session EXPIRED two hours ago and was never ended, so the hook treats it as not live and sets no claims (assertion 2) -- and yet it still blocks a second one, because the index predicate is `ended_at is null` and cannot mention now(). That is the stated trade: it forces an explicit end, which is what writes the end audit row. An implementation that indexed on liveness rather than openness would let this insert through, and would need an immutable now(), which does not exist'
);

set local role postgres;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a5', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

with ended as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000055'::uuid
  returning 1
)
select is(
  (select count(*) from ended), 1::bigint,
  'design.md 6: a super admin ends its OWN session -- impersonation_sessions_platform_write names super_admin AND `actor_user_id = (select auth.uid())` on both clauses, so ending is as self-scoped as starting, and one super admin cannot close another''s session out from under the audit trail'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '14000000-0000-4000-8000-000000000055'::uuid
      and (action = 'impersonation_session.started'
        or (action = 'impersonation_session.ended'
            and reason = 'gym B asked for help with onboarding'
            and before is not null
            and after is not null))),
  2::bigint,
  'spec "Ending a session" / design.md 6: a SECOND audit row for the same session, written by the trigger on the update that sets ended_at, and carrying the session''s reason AGAIN -- an auditor reading only the end row should not have to join to learn why the session existed. before is the session as it stood with a null ended_at, after is the ended_at that was set; both are required, because INT-003 says an audit row carries a before/after summary and the first version of design.md 6''s column table simply omitted them'
);

select lives_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a5',
            'and now gym A',
            now() + interval '1 hour')$$,
  'spec "A new session after the previous one ended": the uniqueness is over LIVE sessions, so ending one frees the actor to start another'
);

select throws_ok(
  $$insert into public.audit_log (tenant_id, action, record_type)
    values ('14000000-0000-4000-8000-000000000001', 'impersonation_session.started', 'impersonation_session')$$,
  '42501', null,
  'spec "The caller writes no audit row": even a super_admin session holds no INSERT privilege on audit_log -- the rows above exist because the database wrote them, not because this session could have'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 16-17. The two roles that may not create a session at all. RLS with check
--        runs before the tuple reaches the index, so these raise 42501 and not
--        23505 -- and the actors they name (a2 and a1) each already hold an
--        open session, which is exactly why the distinction is worth stating.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a2', 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

-- The actor here IS the caller, so the actor term is satisfied and the refusal
-- can only be the role gate. That is deliberate: the two terms of
-- _platform_write are asserted one at a time.
select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a2',
            'support would like to be the gym',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A support account creating a session": impersonation_sessions_platform_write is gated `= super_admin` on both clauses (design.md 8.1), and support holds no gym-side policy here at all, so it cannot open the session it also cannot use'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a1',
            'the gym writes its own history',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A gym inventing an impersonation session": the gym gets impersonation_sessions_tenant_select and NO impersonation_sessions_tenant_write, so it reads who impersonated it and can neither create nor alter the record. Note this table is not one of the four read-only ones -- its grant permits insert and update, so the policy is the only thing standing here (design.md 8.1)'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 18-21. The token itself, as RLS sees it. These are the claims assertion 1
--        proved the hook mints, now set as the session's claims: the point is
--        that a token which is simultaneously platform-wide and gym-scoped
--        would have a strictly larger blast radius than either, for no product
--        reason.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a1', 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner',
                    'impersonation_session_id', '14000000-0000-4000-8000-000000000051')::text,
  true
);
set local role authenticated;

select ok(
  not app.is_platform(),
  'spec "An impersonating session is not a platform session": app.is_platform() reads app_role, which on an impersonating token is gym_owner -- so every <t>_platform_select policy is false for this session, every <t>_platform_write likewise, and the reach is the gym''s alone'
);

select results_eq(
  $$select id from public.members
     where id in ('14000000-0000-4000-8000-000000000031'::uuid,
                  '14000000-0000-4000-8000-000000000032'::uuid)
     order by id$$,
  $$values ('14000000-0000-4000-8000-000000000031'::uuid)$$,
  'spec "An impersonating session is not a platform session": gym A''s member is returned and gym B''s is not -- the impersonator is inside one gym, not above all of them'
);

select is_empty(
  $$select user_id from public.platform_users
     where user_id in ('14000000-0000-4000-8000-0000000000a1'::uuid,
                       '14000000-0000-4000-8000-0000000000a5'::uuid)$$,
  'spec "An impersonating session cannot reach the platform roster": platform_users has no gym-side policy at all, so an impersonating token -- including the impersonator''s own row -- reads nothing from it'
);

with changed as (
  update public.plans set price_paise = 250000
   where id = '14000000-0000-4000-8000-000000000041'::uuid
  returning 1
)
select is(
  (select count(*) from changed), 1::bigint,
  'design.md 6: an impersonator acts AS THE GYM, with the gym''s reach -- so it writes what a gym_owner writes. The claim is a narrowing of the platform role, not a read-only observation post'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
