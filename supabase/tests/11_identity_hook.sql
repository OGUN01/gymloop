-- 11_identity_hook - the custom access-token hook: where it lives, who may
-- call it, and exactly which claims it stamps for each shape of identity.
--
-- Written from openspec/changes/phase-2-identity-and-tenancy/design.md
-- sections 1-5 and .../specs/identity/spec.md, before the implementation
-- exists (AGENTS.md rule 10).
--
-- WHY THIS IS TESTABLE AT ALL, AND HOW
--
-- design.md section 2: the hook's whole body sits inside
-- `exception when others then return event`, so every failure it has is
-- silent. Its behaviour therefore cannot be inferred from the product
-- working. It is an ordinary `(jsonb) returns jsonb` function, so this file
-- calls it directly as `postgres` with a synthetic event and asserts on the
-- returned jsonb -- which is the only way any of section 3 through 5 is
-- provable.
--
-- WHAT THIS FILE COVERS EXHAUSTIVELY, AND WHAT IT SAMPLES
--
-- Exhaustive: every branch of the resolution order in section 4 (platform,
-- staff, member, inactive, unlinked, and the commit-by-table rule) and every
-- branch of the gym-switching rule in section 5 (a valid request, a request
-- naming a tenant the user does not belong to, a request whose row has been
-- deactivated, and no request at all -- twice, for determinism). Each one is a
-- distinct wrong implementation, so none of them is sampled.
--
-- Also exhaustive: all five values of `member_status` that section 4's table
-- distinguishes, plus `erased_at`. `members` has no `is_active` column -- its
-- lifecycle is `status`, and a member is active when that status is neither
-- `cancelled` nor `blocked` AND `erased_at` is null. The four rows that matter
-- are asserted one by one rather than sampled, because the wrong reading here
-- is not a typo: `status = 'active'` is the obvious implementation and it locks
-- every `expired` and `paused` member out of the product, which is precisely
-- the person the renewal loop exists to bring back. A test that only exercised
-- `active` and `cancelled` would pass against it.
--
-- The claim-set assertions are written as EQUALITY on the whole set of
-- Gymloop claims, not as presence tests. Every call in this file passes claims
-- of exactly `{sub, aud, role, session_id}`, so deleting those four keys from
-- the result leaves exactly what the hook added.
--
-- Note the PARENTHESES around `(... -> 'claims')`, and do not remove them.
-- Postgres puts `-` (subtraction) ABOVE "any other operator" in its precedence
-- table, so `->` binds LOOSER than `-`: written without them,
-- `x -> 'claims' - array[...]` parses as `x -> ('claims' - array[...])`, which
-- resolves as `json - text[]`, tries to parse the literal `claims` as json, and
-- fails with `22P02 invalid input syntax for type json`. Writing the deletion
-- as `- 'sub' - 'aud' - ...` instead misparses identically and surfaces as
-- `42725 operator is not unique: unknown - unknown`. Either way the file does
-- not run at all, so this is not a failing assertion, it is no assertions. The
-- array form is still the better one once the parse is right, because it types
-- unambiguously and names the four keys once -- but it is not what fixes the
-- parse, and a reader who removes the parens because "the array made it
-- unambiguous" puts the bug straight back. Comparing that to a literal
-- jsonb object catches, in one assertion, all six ways section 3 can be
-- broken: a missing claim, an extra one, an empty string, a JSON null, a wrong
-- value, and a staff_id leaking onto a member token.
--
-- Sampled: only the exception-handler branch, which is probed with three
-- degenerate events (no user_id key, a null user_id, an unmatched user_id)
-- rather than with an enumeration of everything that could raise -- the
-- handler is `when others`, so a fourth probe would exercise the same line.
--
-- ADR-050: every fixture is its own; nothing here counts a whole table.
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(33);

-- ---------------------------------------------------------------------------
-- 1-9. Where the hook lives and who may call it (design.md section 1).
--
-- These nine run before any fixture, because they are the assertions that
-- still mean something if the hook is defined but never called: a hook in
-- `public` is a PostgREST RPC and a schema-drift diff on every regeneration,
-- and a hook `authenticated` may execute is a function that decides who is a
-- super admin, callable by anyone signed in.
-- ---------------------------------------------------------------------------

select has_function(
  'app', 'custom_access_token_hook', '{jsonb}'::name[],
  'spec "The hook is not on the public API surface" / design.md 1: the hook is app.custom_access_token_hook(jsonb), matching the URI pg-functions://postgres/app/custom_access_token_hook'
);

select hasnt_function(
  'public', 'custom_access_token_hook', '{jsonb}'::name[],
  'design.md 1: and it is NOT in public -- config.toml exposes public to the Data API and supabase gen types reads it, so a hook there is both an RPC and a permanent schema-drift diff'
);

select is(
  (select pg_get_function_result(p.oid)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  'jsonb',
  'design.md 2: the hook returns jsonb, which is what makes it callable from pgTAP with a synthetic event rather than only through a sign-in'
);

select ok(
  has_schema_privilege('supabase_auth_admin', 'app', 'USAGE'),
  'spec "Auth''s own role can execute the hook": supabase_auth_admin holds usage on schema app -- Phase 1 granted it to authenticated and service_role only, so this is a new grant and not an inherited one'
);

select ok(
  has_function_privilege('supabase_auth_admin', 'app.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'spec "Auth''s own role can execute the hook": the one role that must call it, can'
);

select ok(
  not has_function_privilege('authenticated', 'app.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'spec "A signed-in caller cannot execute the hook": authenticated already holds usage on schema app (Phase 1), so revoking execute on this function is the only thing standing between a signed-in session and the function that decides who is a super admin'
);

select ok(
  not has_function_privilege('anon', 'app.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'spec "A signed-in caller cannot execute the hook": anon holds it not at all either'
);

select ok(
  (select p.proacl is not null
          and not exists (select 1 from unnest(p.proacl) a where a::text like '=%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  'design.md 1: execute is revoked from PUBLIC. A newly created function grants execute to PUBLIC by default and records that as a NULL proacl, so "no explicit grant to anon" is not the same statement -- this asserts the acl exists AND carries no entry for the pseudo-role'
);

select ok(
  (select p.prosecdef
          and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c
                       where c like 'search_path=%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'custom_access_token_hook'),
  'design.md 1: the hook is security definer with a pinned search_path. security definer is what lets it read five tables without granting supabase_auth_admin anything on them; a security definer function with an unpinned search_path is the classic escalation, so the two are asserted together'
);

-- ---------------------------------------------------------------------------
-- Fixtures. Three gyms: A and B are gyms the multi-gym users belong to, C is
-- the gym none of them belongs to, which is what makes the "requested tenant
-- the user does not belong to" case a cross-tenant escalation rather than a
-- typo.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('11000000-0000-4000-8000-000000000001'::uuid, 'Hook Gym A', 'HOOKGA'),
  ('11000000-0000-4000-8000-000000000002'::uuid, 'Hook Gym B', 'HOOKGB'),
  ('11000000-0000-4000-8000-000000000003'::uuid, 'Hook Gym C', 'HOOKGC');

insert into public.branches (id, tenant_id, name, is_default) values
  ('11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('11000000-0000-4000-8000-000000000012'::uuid, '11000000-0000-4000-8000-000000000002'::uuid, 'B Main', true),
  ('11000000-0000-4000-8000-000000000013'::uuid, '11000000-0000-4000-8000-000000000003'::uuid, 'C Main', true);

-- The users. `active_tenant_id` is written into raw_app_meta_data at insert
-- time; design.md section 5 makes that key the only input to gym switching and
-- says it is writable by service_role and by Auth alone, never by the user.
insert into auth.users (id, raw_app_meta_data) values
  ('11000000-0000-4000-8000-0000000000a1'::uuid, '{}'::jsonb),  -- active super_admin
  ('11000000-0000-4000-8000-0000000000a2'::uuid, '{}'::jsonb),  -- active platform_support
  ('11000000-0000-4000-8000-0000000000a3'::uuid, '{}'::jsonb),  -- INACTIVE super_admin, also an active member
  ('11000000-0000-4000-8000-0000000000a4'::uuid, '{}'::jsonb),  -- active super_admin, also an active member
  ('11000000-0000-4000-8000-0000000000a5'::uuid, '{}'::jsonb),  -- staff AND member of the same gym
  ('11000000-0000-4000-8000-0000000000a6'::uuid, '{}'::jsonb),  -- member only
  ('11000000-0000-4000-8000-0000000000a7'::uuid, '{}'::jsonb),  -- linked to nothing
  ('11000000-0000-4000-8000-0000000000a8'::uuid,
     jsonb_build_object('active_tenant_id', '11000000-0000-4000-8000-000000000002')),
  ('11000000-0000-4000-8000-0000000000a9'::uuid,
     jsonb_build_object('active_tenant_id', '11000000-0000-4000-8000-000000000002')),
  ('11000000-0000-4000-8000-0000000000aa'::uuid, '{}'::jsonb),  -- staff, only row inactive
  ('11000000-0000-4000-8000-0000000000ab'::uuid,
     jsonb_build_object('active_tenant_id', '11000000-0000-4000-8000-000000000003')),
  ('11000000-0000-4000-8000-0000000000ac'::uuid, '{}'::jsonb),  -- multi-gym staff, no request
  ('11000000-0000-4000-8000-0000000000ad'::uuid, '{}'::jsonb),  -- member, status expired
  ('11000000-0000-4000-8000-0000000000ae'::uuid, '{}'::jsonb),  -- member, status paused
  ('11000000-0000-4000-8000-0000000000af'::uuid, '{}'::jsonb),  -- member, status cancelled
  ('11000000-0000-4000-8000-0000000000b0'::uuid, '{}'::jsonb),  -- member, status blocked
  ('11000000-0000-4000-8000-0000000000b1'::uuid, '{}'::jsonb),  -- member, active but erased
  ('11000000-0000-4000-8000-0000000000b2'::uuid, '{}'::jsonb);  -- staff in two gyms, BOTH inactive, plus an active members row

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  ('11000000-0000-4000-8000-0000000000a1'::uuid, 'super_admin',      'Root',          'root.11@gymloop.test',    true),
  ('11000000-0000-4000-8000-0000000000a2'::uuid, 'platform_support', 'Support',       'support.11@gymloop.test', true),
  ('11000000-0000-4000-8000-0000000000a3'::uuid, 'super_admin',      'Retired Root',  'retired.11@gymloop.test', false),
  ('11000000-0000-4000-8000-0000000000a4'::uuid, 'super_admin',      'Root Who Lifts','lifts.11@gymloop.test',   true);

-- The staff rows. created_at is set explicitly wherever the deterministic
-- default matters: section 5 makes it "the active row with the earliest
-- created_at", so a fixture that leaves both rows on now() cannot tell a
-- correct implementation from one that returns whichever row the planner
-- happened to hand back first.
insert into public.staff (id, tenant_id, user_id, role, full_name, is_active, created_at) values
  ('11000000-0000-4000-8000-000000000021'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000a5'::uuid, 'gym_manager', 'Staff And Member', true,  timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000022'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000a8'::uuid, 'front_desk',  'A8 in gym A',      true,  timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000023'::uuid, '11000000-0000-4000-8000-000000000002'::uuid,
   '11000000-0000-4000-8000-0000000000a8'::uuid, 'gym_owner',   'A8 in gym B',      true,  timestamptz '2026-06-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000024'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000a9'::uuid, 'trainer',     'A9 in gym A',      true,  timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000025'::uuid, '11000000-0000-4000-8000-000000000002'::uuid,
   '11000000-0000-4000-8000-0000000000a9'::uuid, 'trainer',     'A9 in gym B',      false, timestamptz '2026-06-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000026'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000aa'::uuid, 'front_desk',  'Dismissed',        false, timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000027'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000ab'::uuid, 'front_desk',  'AB in gym A',      true,  timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000028'::uuid, '11000000-0000-4000-8000-000000000002'::uuid,
   '11000000-0000-4000-8000-0000000000ab'::uuid, 'gym_owner',   'AB in gym B',      true,  timestamptz '2026-06-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-000000000029'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000ac'::uuid, 'front_desk',  'AC in gym A',      true,  timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-00000000002a'::uuid, '11000000-0000-4000-8000-000000000002'::uuid,
   '11000000-0000-4000-8000-0000000000ac'::uuid, 'gym_owner',   'AC in gym B',      true,  timestamptz '2026-06-01 10:00:00+05:30'),
  -- Both of this user's staff rows are inactive, and they also hold an active
  -- members row. Section 4: resolution is committed by the TABLE, not by the
  -- row -- having any staff row commits to staff, and if none of that table's
  -- rows is active the answer is no claims, not a fall-through to members.
  ('11000000-0000-4000-8000-00000000002b'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-0000000000b2'::uuid, 'front_desk',  'B2 in gym A',      false, timestamptz '2026-01-01 10:00:00+05:30'),
  ('11000000-0000-4000-8000-00000000002c'::uuid, '11000000-0000-4000-8000-000000000002'::uuid,
   '11000000-0000-4000-8000-0000000000b2'::uuid, 'gym_owner',   'B2 in gym B',      false, timestamptz '2026-06-01 10:00:00+05:30');

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('11000000-0000-4000-8000-000000000031'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000a3'::uuid, 'Retired Root Lifts', '+91110000031'),
  ('11000000-0000-4000-8000-000000000032'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000a4'::uuid, 'Root Lifts',         '+91110000032'),
  ('11000000-0000-4000-8000-000000000033'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000a5'::uuid, 'Manager Lifts',      '+91110000033'),
  ('11000000-0000-4000-8000-000000000034'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000a6'::uuid, 'Ordinary Member',    '+91110000034'),
  ('11000000-0000-4000-8000-00000000003a'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000b2'::uuid, 'Dismissed But Lifts', '+91110000040');

-- The five lifecycle states section 4's table distinguishes. `status` defaults
-- to `active`, so each of these sets it explicitly; the last is `active` with
-- an erasure timestamp, which is DPD-006 and is the one case where the status
-- column alone gives the wrong answer.
insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone, status, erased_at) values
  ('11000000-0000-4000-8000-000000000035'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000ad'::uuid,
   'Lapsed Member',   '+91110000035', 'expired',   null),
  ('11000000-0000-4000-8000-000000000036'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000ae'::uuid,
   'Paused Member',   '+91110000036', 'paused',    null),
  ('11000000-0000-4000-8000-000000000037'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000af'::uuid,
   'Cancelled Member','+91110000037', 'cancelled', null),
  ('11000000-0000-4000-8000-000000000038'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000b0'::uuid,
   'Blocked Member',  '+91110000038', 'blocked',   null),
  ('11000000-0000-4000-8000-000000000039'::uuid, '11000000-0000-4000-8000-000000000001'::uuid,
   '11000000-0000-4000-8000-000000000011'::uuid, '11000000-0000-4000-8000-0000000000b1'::uuid,
   'Erased Member',   '+91110000039', 'active',    timestamptz '2026-08-01 10:00:00+05:30');

-- ---------------------------------------------------------------------------
-- 10-13. The exception handler and the unlinked user (design.md section 2,
--        spec "A failing hook degrades to a claimless token, never to an
--        outage"). A Postgres auth hook fails closed for EVERY user of the
--        project at once, so "returns without raising" is the difference
--        between a session that reads nothing and nobody being able to sign
--        in until a migration ships.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app.custom_access_token_hook(
      jsonb_build_object('claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a7',
                                                      'role', 'authenticated')))$$,
  'spec "An event that is not the documented shape": an event with no user_id key returns rather than raising'
);

select lives_ok(
  $$select app.custom_access_token_hook(
      jsonb_build_object('user_id', null,
                         'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a7',
                                                      'role', 'authenticated')))$$,
  'spec "A null user id": user_id set to JSON null returns rather than raising'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a7',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a7',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "An unlinked user''s claims" / design.md 4: a freshly signed-up auth.users row no gym has linked yet is a SUPPORTED state -- it gets no Gymloop claim at all, and specifically not a tenant_id whose value is an empty string or null'
);

select is(
  app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a7',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a7',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims',
  jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a7',
                     'aud', 'authenticated', 'role', 'authenticated',
                     'session_id', '11000000-0000-4000-8000-0000000000f1'),
  'spec "The hook returns the whole claims object": the unlinked path returns the claims it was given, key for key -- Auth performs no implicit merge and rejects a token missing its required claims, so a hook that returns only its own keys issues no token at all'
);

-- ---------------------------------------------------------------------------
-- 14-17. Platform identities (design.md section 3: "A platform token carries
--        no gym claims") and the reserved claims.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a1',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a1',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'super_admin'),
  'spec "A platform user carries no gym claims": an active super_admin with no live impersonation session gets app_role and NOTHING else -- no tenant_id, no member_id, no staff_id'
);

select ok(
  app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a1',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a1',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims'
  @> jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a1',
                        'aud', 'authenticated', 'role', 'authenticated',
                        'session_id', '11000000-0000-4000-8000-0000000000f1'),
  'spec "Pre-existing claims survive": every reserved claim the event arrived with is present in the result with its original value, on the path that DOES add claims'
);

select is(
  app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a1',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a1',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims' ->> 'role',
  'authenticated',
  'spec "The Postgres role claim is never rewritten": `role` decides which Postgres role the request runs as, so a hook that wrote app_role into it would be the most destructive thing this function could do -- asserted separately from the whole-object check because it is the one reserved claim whose name invites the mistake'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a2',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a2',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'platform_support'),
  'design.md 3: platform_support is a platform identity too, and carries the same shape -- app_role alone'
);

-- ---------------------------------------------------------------------------
-- 18-19. An inactive identity gets nothing AND DOES NOT FALL THROUGH
--        (design.md section 4). "Skip the inactive row and keep looking" is
--        the obvious alternative reading and it is wrong: it would silently
--        turn a dismissed super admin into a member.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a3',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a3',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "A deactivated super admin who is also an active member": resolution STOPS at the inactive platform row -- no app_role, no tenant_id and no member_id, even though this user has a perfectly good members row one step down the order'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000aa',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000aa',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "A deactivated staff member": a staff row with is_active false yields no app_role and no tenant_id'
);

-- ---------------------------------------------------------------------------
-- 20-22. The resolution order itself: platform, then staff, then member,
--        stopping at the first match (design.md section 4). Each of the three
--        users below matches in two tables at once, which is the only way to
--        observe an order.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a4',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a4',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'super_admin'),
  'spec "A platform user who is also a gym member": platform_users is read first, so the platform engineer who trains at a test gym gets their platform identity and no member_id'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a5',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a5',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'gym_manager',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'staff_id',  '11000000-0000-4000-8000-000000000021'),
  'spec "A staff member who is also a member of the same gym" / design.md 3: one token is one identity, so the staff claim set is complete and carries no member_id even though the same human has a members row in the same tenant'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a6',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a6',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'member',
                     'tenant_id',  '11000000-0000-4000-8000-000000000001',
                     'member_id',  '11000000-0000-4000-8000-000000000034'),
  'spec "A gym member": the third table in the order, carrying app_role member, the gym''s tenant_id and that member''s id -- and no staff_id'
);

-- ---------------------------------------------------------------------------
-- 23-27. What "active" means for a member (design.md section 4's table).
--
-- `members` has no is_active column. A member is active when `status` is
-- neither `cancelled` nor `blocked` and `erased_at` is null -- so `expired` and
-- `paused` members sign in normally. That is not leniency: a member whose
-- membership lapsed is exactly the person who has to log in and pay, and the
-- renewal loop is the product. The obvious implementation, `status = 'active'`,
-- locks both of them out and would pass a test that only tried `active` and
-- `cancelled`.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ad',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ad',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'member',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'member_id', '11000000-0000-4000-8000-000000000035'),
  'spec "A lapsed member can still sign in": status `expired` resolves to a full member identity. Renewing is what this person signs in to do, and a hook that reads `status = active` shuts the door on the exact member the retention loop exists to bring back'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ae',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ae',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'member',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'member_id', '11000000-0000-4000-8000-000000000036'),
  'spec "A lapsed member can still sign in": status `paused` likewise -- a freeze is a state of the membership, not of the person''s access to their own record'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000af',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000af',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "A cancelled or blocked member cannot": `cancelled` is the gym ending the relationship, and it is one of exactly two statuses that do'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000b0',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000b0',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "A cancelled or blocked member cannot": `blocked` is the other one'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000b1',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000b1',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'spec "An erased member cannot" / DPD-006: status is `active` and erased_at is set. The row survives for the financial history that references it, and the person holds no session -- so a hook that tested status alone would hand a live token to an erased record'
);

-- 28. The commit-by-table rule, which is the half of section 4 a single
--     inactive row cannot show. This user has TWO staff rows, both inactive,
--     and an ACTIVE members row. Having any staff row commits resolution to
--     `staff`; none of them being active ends it there. "Skip the inactive rows
--     and keep looking" would hand this dismissed employee a member identity.

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000b2',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000b2',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb,
  'design.md 4, "resolution is committed by the table, not by the row": both staff rows are inactive and the active members row is not reached. This is also the only reading consistent with section 5''s scenario where a user active in gym A and deactivated in gym B gets gym A -- there, one inactive row must NOT end resolution, so the rule has to be about the table'
);

-- ---------------------------------------------------------------------------
-- 29-33. Gym switching (design.md section 5). One auth.users row may match
--        several staff rows in different tenants -- the schema permits it on
--        purpose, since the uniqueness is per tenant. The requested tenant is
--        honoured only after being validated, because minting a token for a
--        tenant the user has no active row in is a cross-tenant escalation
--        whose only cost would be a metadata write.
-- ---------------------------------------------------------------------------

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a8',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a8',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'gym_owner',
                     'tenant_id', '11000000-0000-4000-8000-000000000002',
                     'staff_id',  '11000000-0000-4000-8000-000000000023'),
  'spec "A valid requested tenant": active_tenant_id names gym B, the user has an active staff row there, so the token is gym B''s -- and the role and staff_id come from THAT row, not from the default one'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ab',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ab',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'front_desk',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'staff_id',  '11000000-0000-4000-8000-000000000027'),
  'spec "A requested tenant the user does not belong to": active_tenant_id names gym C, where this user has no row at all -- the hook falls back to the deterministic default (gym A, the earliest created_at) and does not raise, and above all does not mint a token for gym C'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000a9',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000a9',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'trainer',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'staff_id',  '11000000-0000-4000-8000-000000000024'),
  'spec "A requested tenant where the user''s row has been deactivated": the row in gym B exists and is inactive, so the request is not honoured -- validating the request means checking it is ACTIVE, not merely that a row is there'
);

select is(
  (app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ac',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ac',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f1')))
    -> 'claims') - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'front_desk',
                     'tenant_id', '11000000-0000-4000-8000-000000000001',
                     'staff_id',  '11000000-0000-4000-8000-000000000029'),
  'spec "No requested tenant at all": with no active_tenant_id the default is the active row with the earliest created_at -- gym A''s, not gym B''s'
);

select is(
  app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ac',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ac',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f2')))
    -> 'claims' ->> 'tenant_id',
  app.custom_access_token_hook(
    jsonb_build_object(
      'user_id', '11000000-0000-4000-8000-0000000000ac',
      'claims', jsonb_build_object('sub', '11000000-0000-4000-8000-0000000000ac',
                                   'aud', 'authenticated', 'role', 'authenticated',
                                   'session_id', '11000000-0000-4000-8000-0000000000f3')))
    -> 'claims' ->> 'tenant_id',
  'spec "No requested tenant at all": two calls return the same tenant. An implementer choosing "any active row" produces a token whose tenant changes between refreshes -- a bug that only ever appears in production, and one a single call can never catch'
);

select * from finish();

rollback;
