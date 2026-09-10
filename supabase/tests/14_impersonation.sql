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

select plan(38);

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
--   a6  super_admin       one OPEN session targeting gym B, which is the gym
--                         a5's session targets. Same tenant on purpose: it is
--                         what makes "an impersonator cannot end a DIFFERENT
--                         session" a test of the policy rather than of the
--                         tenant match, since this row is one the impersonating
--                         token can read
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
  ('14000000-0000-4000-8000-0000000000a5'::uuid),
  ('14000000-0000-4000-8000-0000000000a6'::uuid),
  ('14000000-0000-4000-8000-0000000000a7'::uuid);

insert into public.platform_users (user_id, role, full_name, email) values
  ('14000000-0000-4000-8000-0000000000a1'::uuid, 'super_admin',      'Live Actor',    'a1.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a2'::uuid, 'platform_support', 'Support Actor', 'a2.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a3'::uuid, 'super_admin',      'Lapsed Actor',  'a3.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a4'::uuid, 'super_admin',      'Ended Actor',   'a4.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a5'::uuid, 'super_admin',      'Idle Actor',    'a5.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a6'::uuid, 'super_admin',      'Other Actor',   'a6.14@gymloop.test'),
  ('14000000-0000-4000-8000-0000000000a7'::uuid, 'super_admin',      'Anchor Actor',  'a7.14@gymloop.test');

-- THESE FIXTURES BACKDATE `started_at`, AND THEY HAVE TO.
--
-- Sessions 52 and 53 are EXPIRED: their expires_at is in the past. Inside a
-- transaction that is the only way an expired session can exist at all --
-- `now()` is the transaction timestamp and never advances, so a row inserted
-- here with a future expiry stays live for the whole file no matter what else
-- happens. Expiry is half of liveness and section 6 leans on it twice (the
-- hook hands an expired session's actor back its super_admin token; a lapsed
-- session leaves a start with no end), so losing the ability to write one
-- loses that half everywhere.
--
-- The immutability trigger therefore clamps the anchor FORWARD ONLY --
-- `least(coalesce(new.started_at, now()), now())` -- and not to `now()`
-- unconditionally. A future anchor is the defect: it buys a session that is
-- live for a decade. A past anchor is ordinary history, and forbidding it would
-- take the backdated fixtures in this file, in 12, in 13 and in both 10_ files
-- with it: clamped to now(), every one of those rows fails
-- `impersonation_sessions_expires_at_after_started_at_chk` and the file aborts
-- before its first assertion. The clamp that closes the hole does not need to
-- reach the past to close it.
--
-- Assertion 10 asserts that directly, so this dependency is named rather than
-- merely relied on: a file that aborts in its fixtures reports nothing at all,
-- which is the worst signal a suite can give.
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
   now() - interval '3 hour', now() - interval '2 hour', now() - interval '2 hour 30 minute'),
  ('14000000-0000-4000-8000-000000000056'::uuid, '14000000-0000-4000-8000-000000000002'::uuid,
   '14000000-0000-4000-8000-0000000000a6'::uuid, 'a different actor, the same gym',
   now() - interval '10 minute', now() + interval '50 minute', null);

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
-- 7-10. The ANCHOR, which is where the hard TTL was open.
--
-- `impersonation_sessions_ttl_chk` bounds the SPAN, `started_at` to
-- `expires_at`. It says nothing about where the span sits. So
-- `started_at = now() + interval '10 years'` with
-- `expires_at = started_at + interval '2 hours'` satisfies the TTL, satisfies
-- `expires_at > started_at`, and is LIVE RIGHT NOW -- `ended_at is null and
-- expires_at > now()` is true today and stays true for a decade. A bound on the
-- length of a session is not a bound on the session. The anchor is corrected
-- forward only: `least(coalesce(new.started_at, now()), now())`.
--
-- Four assertions, three scenarios, and the mapping is one-to-one:
--
--   7      a future anchor whose expiry is the maximum after IT is REFUSED,
--          because the bound is measured from the corrected anchor and the span
--          it then names is a decade
--   8, 9   a future anchor whose expiry is within the maximum of the PRESENT is
--          corrected and stored -- 8 that the row lands at all, 9 that the
--          anchor it landed with is not in the future
--   10     an already-expired session is writable, which is the case the
--          backdated fixtures in this file, in 12, in 13 and in both 10_ files
--          all depend on
--
-- 7 is the one to keep if only one could be kept. It is written as the LIVENESS
-- property and not as a test of the stored column, because liveness is what
-- failed: the row it offers carries a perfectly legal two-hour span, which is
-- why both existing constraints and the liveness predicate all admitted it. A
-- test that only read `started_at` back would pass against an implementation
-- that clamps the column while leaving some other route to a decade-long live
-- row.
--
-- All four run as the owner: the subject is the trigger, and inserting through
-- a policy would add an actor term that has nothing to do with it.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a7',
            'live for a decade',
            now() + interval '10 years',
            now() + interval '10 years 2 hours')$$,
  '23514', null,
  'spec "A future anchor whose expiry is the maximum after it is refused": a session anchored ten years out cannot be live for ten years. The span the caller wrote is a legal two hours and the row is refused anyway, because the anchor is corrected to the time of writing before the constraint sees it -- so the span the TTL actually measures is the decade. This is the row the defect admitted: expires_at > started_at held, the TTL held, and `ended_at is null and expires_at > now()` held today and for the next ten years'
);

select lives_ok(
  $$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at)
    values ('14000000-0000-4000-8000-000000000058',
            '14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a7',
            'anchored in the future, written now',
            now() + interval '10 years',
            now() + interval '1 hour')$$,
  'spec "A future anchor with an expiry within the maximum of the present is corrected and stored": the expiry is ONE HOUR out -- measured from the present, not from the anchor the caller asked for -- which is what makes this row storable once the anchor is corrected. Under the defect the same row is REJECTED, because an expiry an hour away does not exceed a started_at a decade away. Assertion 7 offers the other shape and is refused; the two together are what distinguish correcting the anchor from refusing the row, and the spec says the stored value is the time of writing'
);

select is(
  (select count(*) from public.impersonation_sessions
    where id = '14000000-0000-4000-8000-000000000058'::uuid
      and started_at <= now()),
  1::bigint,
  'spec "A future anchor with an expiry within the maximum of the present is corrected and stored", the stored half: the anchor is the time of writing, not the decade the caller asked for. Asserted as `<= now()` rather than `= now()` because the correction is forward-only -- `least(started_at, now())` -- so a caller who supplies a PAST anchor keeps it, and the requirement is only that nobody can place one in the future'
);

-- Actor a4, not a7: a7 now holds session 58 from the assertion above, and an
-- expired session is still an OPEN one -- ended_at is null is what the unique
-- index reads -- so a second row for a7 would collide with it and report the
-- index rather than the trigger. a4's only session was ended long ago.
select lives_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a4',
            'a session that has already lapsed',
            now() - interval '3 hour',
            now() - interval '2 hour')$$,
  'spec "An already-expired session is writable": the correction is forward-only, so a past anchor is kept and a row that is already past its expiry can be written. This is not a convenience for tests -- inside a transaction `now()` never advances, so a backdated row is the ONLY way an expired session can exist, and expiry is half of liveness. Section 6 leans on that half twice: the hook hands an expired session''s actor back its super_admin token, and a lapsed session leaves a start with no matching end. A clamp written `:= now()` rather than `least(..., now())` would take this row, the two expired fixtures above, and the backdated fixtures in 12, 13 and both 10_ files with it'
);

-- ---------------------------------------------------------------------------
-- WHICH CLAIM SETS THIS FILE MAY SET BY HAND, AND WHICH IT MAY NOT
--
-- Everything from here down sets `request.jwt.claims` directly, which is a
-- licence to construct a token the hook could never mint -- and a test built on
-- one is a test of a fiction. It happened here: the first version of this file
-- asserted that a super admin ends its own session, with a hand-set
-- `app_role = 'super_admin'` and the session LIVE. The hook returns
-- `gym_owner` for the whole duration of a live session, so that pair does not
-- occur; and underneath it there was no reachable path to set `ended_at` at
-- all, because `_platform_write` wanted a `super_admin` claim the actor cannot
-- hold plus an actor match no other admin satisfies. The assertion passed
-- against a schema in which the operation was impossible for everybody. A
-- blind critic found it. design.md 6 now carries the fourth policy that makes
-- ending reachable, and this note carries the rule.
--
-- So, per §3 and §6, an actor's mintable claims depend on the state of its own
-- sessions AT THAT POINT IN THE FILE:
--
--   no open session   -> {app_role: super_admin}, and nothing else
--   live session      -> {app_role: gym_owner, tenant_id: <target>,
--                         impersonation_session_id: <id>}, no staff_id,
--                         no member_id, and never super_admin
--
-- Every block below says which of the two it is and why the actor is in that
-- state. `sub` is set throughout, because auth.uid() reads it and
-- `_platform_write` compares it to actor_user_id.
--
-- Two assertions here DO set a pair the hook cannot mint, and that is the
-- point of them rather than a lapse: a policy whose correctness rests on the
-- hook never emitting a combination is a policy held up by a different
-- component. Testing that something WORKS through an impossible token proves
-- nothing; testing that a policy REFUSES one proves it stands on its own. Both
-- are labelled where they appear.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 11-15. Actor a5, holding no session, so `super_admin` is what the hook gives
--       it. The bounded lifetime, the audit privilege, the actor term, and the
--       create itself.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a5', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
    values ('14000000-0000-4000-8000-000000000002',
            '14000000-0000-4000-8000-0000000000a5',
            'a decade of support',
            now(), now() + interval '10 years')$$,
  '23514', null,
  'spec "A session longer than the maximum" / design.md 6: docs/security.md promises a hard TTL and names "an impersonation session with no expiry" as a thing that must never happen. Phase 1 required only `expires_at > started_at`, under which ten years is legal -- a future timestamp is not a bound. impersonation_sessions_ttl_chk is the bound, and 23514 rather than 42501 is the right signature: a table constraint, checked before any policy'
);

select throws_ok(
  $$insert into public.audit_log (tenant_id, action, record_type)
    values ('14000000-0000-4000-8000-000000000001', 'impersonation_session.started', 'impersonation_session')$$,
  '42501', null,
  'spec "The caller writes no audit row": even a super_admin session holds no INSERT privilege on audit_log -- every row this file counts exists because the database wrote it, not because this session could have. Asserted BEFORE the session is created, so the claims are ones the hook would mint at this point'
);

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000002',
            '14000000-0000-4000-8000-0000000000a1',
            'opened in somebody else''s name',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A super admin naming someone else as the actor": _platform_write gates the CALLER, and without `actor_user_id = auth.uid()` it says nothing about the actor COLUMN -- so a super admin could open a session naming a different platform user, including a platform_support account which may not impersonate at all, and the audit trail would then name the wrong person'
);

-- Exactly two hours, which design.md 6 makes legal: the bound is
-- `expires_at <= started_at + interval '2 hours'`. The boundary is the value
-- worth writing, because it is where `<` and `<=` differ and the ten-year
-- refusal above cannot tell them apart. `now()` is the transaction timestamp
-- and is therefore the same instant in both columns, so the span is exactly the
-- bound rather than a hair over it.
select lives_ok(
  $$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000055',
            '14000000-0000-4000-8000-000000000002',
            '14000000-0000-4000-8000-0000000000a5',
            'gym B asked for help with onboarding',
            now() + interval '2 hours')$$,
  'spec "A super admin creating a session" / "A super admin naming itself" / "A session within the maximum": a stated reason, an expiry exactly at the two-hour bound, and an actor that is the caller. This one statement is the control for all three refusals above -- without it, `with check (false)` and a TTL written `<` would both look correct'
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

set local role postgres;

-- ---------------------------------------------------------------------------
-- 16-21. INSIDE session 55. From the instant it was created the hook gives a5
--        `gym_owner`, the target tenant and the session id -- and never
--        `super_admin` again until the session ends. These are the only claims
--        a5 can hold now, so everything else a5 does is done through them.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a5', 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000002',
                    'app_role', 'gym_owner',
                    'impersonation_session_id', '14000000-0000-4000-8000-000000000055')::text,
  true
);
set local role authenticated;

-- The read path the write depends on, asserted rather than assumed. An UPDATE
-- needs a SELECT policy to admit the row its WHERE clause reads, and an
-- impersonating token fails impersonation_sessions_platform_select because
-- is_platform() is false on it. The whole path therefore rests on
-- impersonation_sessions_tenant_select, gated on the target tenant plus
-- is_gym_admin() -- which this token satisfies. Narrow that read gate and the
-- fix below becomes unusable in exactly the way the defect it fixes was.
select results_eq(
  $$select id from public.impersonation_sessions
     where id = '14000000-0000-4000-8000-000000000055'::uuid$$,
  $$values ('14000000-0000-4000-8000-000000000055'::uuid)$$,
  'design.md 6: the impersonating token can READ its own session row, through impersonation_sessions_tenant_select and nothing else -- which is what makes the update below reachable at all'
);

select throws_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a5',
            'a second gym at the same time',
            now() + interval '1 hour')$$,
  '42501', null,
  'spec "A second live session": the actor cannot open a second one, and the refusal is RLS rather than the index -- while its first session is live it holds gym_owner, which _platform_write refuses, and _impersonator_write is `for update` and covers no insert at all. The index is the backstop for the case no policy can see, which is assertion 24'
);

with crossed as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000056'::uuid
  returning 1
)
select is(
  (select count(*) from crossed), 0::bigint,
  'spec "The impersonator cannot end a different session": session 56 belongs to another actor and targets the SAME gym, so this token can read it -- a gym is entitled to its own impersonation history. It still affects zero rows, because _impersonator_write''s using clause reaches exactly one row, the session the caller is inside. Choosing a same-tenant target is what makes this a test of the policy rather than of the tenant match'
);

select throws_ok(
  $$update public.impersonation_sessions
       set expires_at = started_at + interval '90 minutes'
     where id = '14000000-0000-4000-8000-000000000055'$$,
  '42501', null,
  'spec "The impersonator cannot use the path for anything else": ninety minutes is comfortably inside the two-hour TTL, so the constraint has nothing to say and the refusal is the policy alone -- the row is admitted by using and rejected by with check, which requires ended_at to be not null. The one write this path permits is ending the session; an impersonator cannot extend its own expiry, which would otherwise turn a bounded session into an unbounded one from inside'
);

with ended as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000055'::uuid
  returning 1
)
select is(
  (select count(*) from ended), 1::bigint,
  'spec "The impersonator ends its own session": one row, and this is the assertion the fourth policy exists for. The previous version of this file asserted the same thing with a hand-set super_admin claim -- one the hook cannot mint while the session is live -- and so passed against a schema where ending was impossible for everybody'
);

-- NAV-003: the stale preview token still carries its impersonation claim.
-- After own-end, that token may not rewrite expiry, even though the old policy
-- accepts a row with nonnull ended_at. Refuse rather than normalize the write.
select throws_ok(
  $$update public.impersonation_sessions
     set expires_at = now() + interval '30 minutes'
   where id = '14000000-0000-4000-8000-000000000055'::uuid$$,
  '42501', null,
  'NAV-003: an ended session cannot be rewritten by its stale preview token; only the original own-end operation is permitted'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 22-23. Actor a5 again, and `super_admin` is mintable again BECAUSE the
--        session above was ended. The order of this file is the claim contract.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a5', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is(
  (select count(*) from public.audit_log
    where record_id = '14000000-0000-4000-8000-000000000055'::uuid
      and exists (select 1 from public.impersonation_sessions s
                   where s.id = '14000000-0000-4000-8000-000000000055'::uuid
                     and s.expires_at = now() + interval '2 hours')
      and (action = 'impersonation_session.started'
        or (action = 'impersonation_session.ended'
            and reason = 'gym B asked for help with onboarding'
            and before is not null
            and after is not null))),
  2::bigint,
  'spec "Ending a session" / design.md 6 and NAV-003: the original two-hour expiry remains unchanged after the refused stale-preview write, and exactly the original start plus own-end audit rows remain, carrying the original reason and before/after evidence'
);

select lives_ok(
  $$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, expires_at)
    values ('14000000-0000-4000-8000-000000000001',
            '14000000-0000-4000-8000-0000000000a5',
            'and now gym A',
            now() + interval '1 hour')$$,
  'spec "A new session after the previous one ended": the uniqueness is over OPEN sessions, so ending one frees the actor to start another -- and ending it is also what returned this actor to a super_admin token, without which it could not have made this call'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 24. Actor a3, whose only session EXPIRED without being ended. The hook gives
--     it super_admin, because expiry is half of liveness -- and the index still
--     refuses a second, because `open` is the only half an index can express.
-- ---------------------------------------------------------------------------

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
  'design.md 6: a3''s session expired two hours ago and was never ended, so the hook treats it as not live and hands back super_admin (assertion 2) -- which is precisely why this insert reaches the index at all, where assertion 17''s could not. It is still refused, because the index predicate is `ended_at is null` and cannot mention now(). That is the stated trade: it forces an explicit end, which is what writes the end audit row'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 25-28. The roles that may not create a session, and the two kinds of session
--        that may not end one.
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

with meddled as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000051'::uuid
  returning 1
)
select is(
  (select count(*) from meddled), 0::bigint,
  'spec "A gym-side session cannot end a session": an ordinary gym_owner token carries no impersonation_session_id, so app.current_impersonation_id() is null and _impersonator_write''s using clause is null -- which is not true. The fourth policy widens the table for exactly one session, the one the caller is inside, and for nobody else. Without this the policy could have been written `using (true)` and every assertion above it would still pass'
);

set local role postgres;

-- 28. A gym_manager claim carrying an impersonation_session_id.
--
-- THIS IS A TOKEN THE HOOK CANNOT MINT, deliberately. §3 gives
-- impersonation_session_id only alongside app_role gym_owner, so the pair below
-- does not occur in the wild -- and that is exactly why it is worth asserting:
-- without the role term the fourth policy added, the policy's correctness would
-- rest on the hook never emitting this pair, which is a guarantee living in a
-- different component. gym_manager rather than front_desk on purpose: a
-- manager passes is_gym_admin() and so can READ the row, which isolates the new
-- role term. front_desk would be turned away by the read gate first and would
-- prove nothing about it.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'impersonation_session_id', '14000000-0000-4000-8000-000000000051')::text,
  true
);
set local role authenticated;

with forged as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000051'::uuid
  returning 1
)
select is(
  (select count(*) from forged), 0::bigint,
  'design.md 6: _impersonator_write names the role as well as the session -- `current_app_role() = gym_owner` -- so a claim pairing an impersonation_session_id with any other role reaches nothing. This is the third instance in the phase of a policy that would otherwise have been held up by the hook''s discipline rather than by its own predicate, and the same argument ADR-047 made for tenant-scoping a constraint RLS already covered'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 29. An EXPIRED session, ended by its own still-valid token.
--
--     Deliberately not a hook-mintable claim set at this instant -- the hook
--     would now give a3 super_admin, because the session is no longer live.
--     But it is a real token: it was minted while the session WAS live and
--     remains in the holder's hands until the access token expires, which
--     design.md 7 names as the residual window and refuses to design away.
--
--     This is what pins the absence of a liveness term on the fourth policy.
--     `and expires_at > now()` would recreate the unreachable state for every
--     abandoned session -- and since the one-open-session index blocks that
--     actor until an explicit end is written, "unendable" and "that actor can
--     never impersonate again" would be the same sentence.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a3', 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner',
                    'impersonation_session_id', '14000000-0000-4000-8000-000000000052')::text,
  true
);
set local role authenticated;

with tidied as (
  update public.impersonation_sessions set ended_at = now()
   where id = '14000000-0000-4000-8000-000000000052'::uuid
  returning 1
)
select is(
  (select count(*) from tidied), 1::bigint,
  'design.md 6: an expired, never-ended session is still endable by its own claim, because _impersonator_write carries no liveness term. Adding one would make every abandoned session unendable, and the open-session index would then bar its actor from ever impersonating again -- the same composition failure the fourth policy was written to undo, reintroduced one layer down'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 30-33. Ending a session WHILE RETARGETING IT, as the impersonator of session
--        56 -- the second defect, and the one with no escalation in it at all.
--
--        `_impersonator_write` pinned `ended_at is not null` and nothing else,
--        so one statement could end a session AND move it to another gym and
--        rewrite why it existed. The audit trigger reads the NEW row, so the
--        end row would land in a gym that was never impersonated, carrying a
--        reason that was never given, while the gym actually impersonated kept
--        a start row with no matching end. Nobody gains a privilege; the audit
--        trail simply stops being true, which is the one thing INT-003 exists
--        to prevent.
--
--        NAV-003 narrows the exception to exact own-end. The mixed write must
--        now be refused, leave the session open and emit no end audit. A later
--        exact own-end still succeeds and writes the original gym/reason.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '14000000-0000-4000-8000-0000000000a6', 'role', 'authenticated',
                    'tenant_id', '14000000-0000-4000-8000-000000000002',
                    'app_role', 'gym_owner',
                    'impersonation_session_id', '14000000-0000-4000-8000-000000000056')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$update public.impersonation_sessions
     set ended_at  = now(),
         tenant_id = '14000000-0000-4000-8000-000000000001'::uuid,
         reason    = 'a gym we never entered'
   where id = '14000000-0000-4000-8000-000000000056'::uuid$$,
  '42501', null,
  'NAV-003: own-end cannot also retarget tenant or rewrite reason, even when an old immutability trigger would have normalized them'
);

select ok(
  exists (select 1 from public.impersonation_sessions
           where id = '14000000-0000-4000-8000-000000000056'::uuid
             and tenant_id = '14000000-0000-4000-8000-000000000002'::uuid
             and reason = 'a different actor, the same gym' and ended_at is null)
  and not exists (select 1 from public.audit_log
                   where record_id = '14000000-0000-4000-8000-000000000056'::uuid
                     and action = 'impersonation_session.ended'),
  'NAV-003: rejected mixed own-end preserves the original open session and emits no end audit'
);

select lives_ok(
  $$update public.impersonation_sessions set ended_at = now()
     where id = '14000000-0000-4000-8000-000000000056'::uuid$$,
  'NAV-003: exact own-end remains permitted after the refused mixed write'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '14000000-0000-4000-8000-000000000056'::uuid
      and action = 'impersonation_session.ended'
      and tenant_id = '14000000-0000-4000-8000-000000000002'::uuid
      and reason = 'a different actor, the same gym'),
  1::bigint,
  'spec "A session is written once and then only ended", the requirement: the end audit row names the gym that was actually impersonated and the reason actually given. This is the assertion that matters -- the session row being unchanged is how it is achieved, but an audit trail that says a gym was entered when it was not is the harm, and the trigger writes that row from the NEW tuple'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 34-38. The token itself, as RLS sees it. These are the claims assertion 1
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

select throws_ok(
  $$update public.plans set price_paise = 250000
     where id = '14000000-0000-4000-8000-000000000041'::uuid$$,
  '42501', null,
  'NAV-003 supersedes writable gym preview: the impersonator retains gym reads but cannot reprice a plan'
);
select is(
  (select price_paise from public.plans where id = '14000000-0000-4000-8000-000000000041'::uuid),
  200000::bigint,
  'NAV-003: the refused preview repricing leaves the original price intact'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
