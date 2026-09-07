-- Phase 2 — identity: the claim accessors, the four role gates, and the access-token hook.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 1  Where the hook lives, and why not in `public`
--   § 2  The exception rule
--   § 3  The claim contract
--   § 4  Identity resolution — exactly one identity, in a fixed order
--   § 5  Gym switching — one token is one tenant
--   § 6  Impersonation (the liveness expression and the impersonating claims)
--   § 8.2 The four gates, and no fifth
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/identity/spec.md,
--                .../specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-031 (app_role is the one role vocabulary),
--   ADR-032 (claim names, accessors live in `app`, a malformed claim fails loudly),
--   ADR-042 (a migration is replayed inside begin … rollback before it is pushed).
--
-- Statement order is docs/data-model.md's: functions → privileges. No table, no enum, no
-- policy and no trigger here. No begin/commit: CI applies this forward-only.
--
-- Everything in this file lives in schema `app`. `supabase/config.toml` exposes only
-- `public` and `graphql_public`, so nothing here is a PostgREST RPC and nothing here
-- reaches packages/db/types/database.ts — which is exactly why the hook is not in
-- `public`, where Supabase's own documentation puts it (design § 1).


-- ---------------------------------------------------------------------------
-- 1. Claim accessors
--    The same shape as app.current_tenant_id() and app.is_platform() in
--    20260906115131_tenancy.sql: `stable`, `security invoker`, `set search_path = ''`,
--    reading only the request.jwt.claims GUC and never a table.
--
--    `current_setting(…, true)` returns null rather than raising when the GUC is absent,
--    so a session with no claims yields null from every accessor here and false from
--    every gate — no exception, and a policy comparing against null matches no rows.
--    A `tenant_id`, `member_id`, `staff_id` or `impersonation_session_id` that is
--    present but malformed raises `22P02` on the cast, which is the loud failure
--    ADR-032 chose: a malformed uuid cannot mean anything at all.
-- ---------------------------------------------------------------------------

-- Returns **text**, and casts nothing (design § 3, as revised). The ADR-032 analogy
-- with a malformed `tenant_id` does not hold: an unrecognised *role* has an obvious and
-- safe meaning — this session holds no privileges — and it is the reading every gate
-- below reaches anyway. Casting to `public.app_role` would make one forged claim behave
-- differently table by table: false and silent wherever a gate function is consulted,
-- `22P02` wherever a policy compares the role directly. Text throughout means an
-- unknown role reads nothing, writes nothing, and raises nowhere.
create or replace function app.current_app_role()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'app_role',
    ''
  )
$$;

create or replace function app.current_member_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'member_id',
    ''
  )::uuid
$$;

create or replace function app.current_staff_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'staff_id',
    ''
  )::uuid
$$;

create or replace function app.current_impersonation_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'impersonation_session_id',
    ''
  )::uuid
$$;


-- ---------------------------------------------------------------------------
-- 2. The three role-set gates, and no fourth (design § 8.2)
--    Written as functions rather than as inline role lists so that changing which
--    roles count as staff is one edit rather than thirty-five. They compare the claim
--    as *text*, exactly as app.is_platform() does and exactly as app.current_app_role()
--    now does: an `app_role` outside the enum is false everywhere and raises nowhere,
--    which is what makes "an unrecognised role grants nothing and raises nothing" hold
--    on every gate and on every policy that compares a label directly.
-- ---------------------------------------------------------------------------

create or replace function app.is_staff()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'app_role',
    ''
  ) in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')
$$;

create or replace function app.is_gym_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'app_role',
    ''
  ) in ('gym_owner', 'gym_manager')
$$;

create or replace function app.is_front_office()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'app_role',
    ''
  ) in ('gym_owner', 'gym_manager', 'front_desk')
$$;


-- ---------------------------------------------------------------------------
-- 3. Impersonation liveness (design § 6)
--    "A session is live when `ended_at is null and expires_at > now()`. That
--    expression appears in exactly one function and never inline in two places."
--    This is that function. The hook calls it; nothing else may re-spell it.
--
--    Note what it is *not*: the partial unique index in the triggers migration is on
--    `where ended_at is null`, because `now()` is not immutable and cannot appear in an
--    index predicate. "At most one open session" is what the index can enforce; "live"
--    is open *and* unexpired, and only this function decides that.
-- ---------------------------------------------------------------------------

create or replace function app.impersonation_is_live(
  p_ended_at   timestamptz,
  p_expires_at timestamptz
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select p_ended_at is null and p_expires_at > now()
$$;


-- ---------------------------------------------------------------------------
-- 4. The access-token hook (design § 1–6)
--
--    `security definer`, owned by `postgres`, which holds BYPASSRLS — so the hook
--    reads the three identity tables and auth.users without `supabase_auth_admin`
--    needing a single table grant, and without depending on how that role interacts
--    with RLS (which the Supabase documentation does not settle). Its whole surface
--    is one function callable by one role; see the grants at the foot of this file.
-- ---------------------------------------------------------------------------

create or replace function app.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid;
  v_claims      jsonb;
  v_requested   text;   -- raw_app_meta_data ->> 'active_tenant_id', never cast (§ 5)
  v_role        public.app_role;
  v_tenant_id   uuid;
  v_member_id   uuid;
  v_staff_id    uuid;
  v_session_id  uuid;
  v_exists      boolean;
  v_active      boolean;
begin
  -- --- claims and user id -------------------------------------------------
  -- The hook returns the *whole* claims object (§ 3). Supabase performs no implicit
  -- merge: a hook returning only its own keys drops every claim it did not copy and
  -- Auth then rejects the token. Reserved claims (iss, aud, exp, iat, sub, role, aal,
  -- session_id, email, phone, is_anonymous) are never written here — this function
  -- only ever adds the five Gymloop keys with `||`, so it cannot overwrite one.
  v_claims  := coalesce(event -> 'claims', '{}'::jsonb);
  v_user_id := nullif(event ->> 'user_id', '')::uuid;

  if v_user_id is null then
    return event;                                     -- no user_id, or JSON null: no claims
  end if;

  -- --- 1. platform_users (§ 4, first in the fixed order) -------------------
  -- A platform engineer who is also a member of a test gym gets their platform
  -- identity. `platform_users` is keyed on user_id, so there is at most one row.
  select true, pu.is_active, pu.role
    into v_exists, v_active, v_role
    from public.platform_users pu
   where pu.user_id = v_user_id;

  if v_exists then
    if not v_active then
      return event;                                   -- inactive: stop, do NOT fall through
    end if;

    -- Impersonation (§ 6). Only super_admin may impersonate; platform_support may not.
    -- At most one *open* session per actor exists (partial unique index), so the live
    -- one is unique and no ordering rule is needed.
    if v_role = 'super_admin' then
      select i.id, i.tenant_id
        into v_session_id, v_tenant_id
        from public.impersonation_sessions i
       where i.actor_user_id = v_user_id
         and app.impersonation_is_live(i.ended_at, i.expires_at);

      if v_session_id is not null then
        -- An impersonator acts *as the gym*: gym reach, not gym reach and platform
        -- reach. app.is_platform() is therefore false on this token.
        return jsonb_set(
          event,
          '{claims}',
          v_claims || jsonb_build_object(
            'app_role',                 'gym_owner',
            'tenant_id',                v_tenant_id,
            'impersonation_session_id', v_session_id
          )
        );
      end if;
    end if;

    -- An ordinary platform token carries no gym claims at all.
    return jsonb_set(event, '{claims}', v_claims || jsonb_build_object('app_role', v_role::text));
  end if;

  -- The requested tenant (§ 5). Read once, used by both remaining branches. It is
  -- never cast to uuid: the comparison below is `tenant_id::text = v_requested`, so a
  -- malformed or stale value simply matches no row and falls back, without raising.
  select u.raw_app_meta_data ->> 'active_tenant_id'
    into v_requested
    from auth.users u
   where u.id = v_user_id;

  -- --- 2. staff (§ 4, second) ---------------------------------------------
  select true into v_exists from public.staff s where s.user_id = v_user_id limit 1;

  if v_exists then
    -- Honour the requested tenant only if the user has an *active* row in it.
    select s.id, s.tenant_id, s.role
      into v_staff_id, v_tenant_id, v_role
      from public.staff s
     where s.user_id = v_user_id
       and s.is_active
       and s.tenant_id::text = v_requested;

    if v_staff_id is null then
      -- The deterministic default: earliest created_at, ties broken by the lower id.
      -- Deterministic is the requirement — "any row" is a token whose tenant changes
      -- between refreshes.
      select s.id, s.tenant_id, s.role
        into v_staff_id, v_tenant_id, v_role
        from public.staff s
       where s.user_id = v_user_id
         and s.is_active
       order by s.created_at, s.id
       limit 1;
    end if;

    if v_staff_id is null then
      return event;                                   -- rows exist but none active: stop
    end if;

    -- A staff token never carries member_id, even when the same human is also a
    -- member of that gym. One token is one identity.
    return jsonb_set(
      event,
      '{claims}',
      v_claims || jsonb_build_object(
        'app_role',  v_role::text,
        'tenant_id', v_tenant_id,
        'staff_id',  v_staff_id
      )
    );
  end if;

  -- --- 3. members (§ 4, third) --------------------------------------------
  -- `members` has no `is_active` column. Per § 4's per-table table, a member is active
  -- when `status not in ('cancelled', 'blocked') and erased_at is null`. A `paused` or
  -- `expired` member signs in normally — the renewal loop is the product, and a member
  -- whose membership lapsed is exactly the person who must be able to log in and pay.
  -- `erased_at` is DPD-006: the row survives for the financial history that references
  -- it, the session does not.
  select true into v_exists from public.members m where m.user_id = v_user_id limit 1;

  if v_exists then
    select m.id, m.tenant_id
      into v_member_id, v_tenant_id
      from public.members m
     where m.user_id = v_user_id
       and m.status not in ('cancelled', 'blocked')
       and m.erased_at is null
       and m.tenant_id::text = v_requested;

    if v_member_id is null then
      select m.id, m.tenant_id
        into v_member_id, v_tenant_id
        from public.members m
       where m.user_id = v_user_id
         and m.status not in ('cancelled', 'blocked')
         and m.erased_at is null
       order by m.created_at, m.id
       limit 1;
    end if;

    if v_member_id is null then
      return event;
    end if;

    return jsonb_set(
      event,
      '{claims}',
      v_claims || jsonb_build_object(
        'app_role',  'member',
        'tenant_id', v_tenant_id,
        'member_id', v_member_id
      )
    );
  end if;

  -- --- no identity anywhere (§ 4) -----------------------------------------
  -- A freshly signed-up auth.users row no gym has linked yet. A supported state, not
  -- an error: the session reads zero rows from every table and raises nothing.
  return event;

exception when others then
  -- ** Do not remove this handler. ** design § 2 is the paragraph it implements.
  --
  -- A Postgres auth hook fails closed with a two-second budget: Supabase propagates an
  -- exception into an HTTP error and issues no token at all. This function is global,
  -- so one unhandled exception here locks *every* user of the product out of sign-in
  -- AND token refresh simultaneously, until a migration is deployed.
  --
  -- Returning the event unmodified degrades to a token with no Gymloop claims: that
  -- session reads zero rows from every table and raises nothing, which is the state
  -- the tenancy spec already guarantees and already tests. Between "everyone is signed
  -- in and sees nothing" and "nobody can sign in", the first is a browser refresh and
  -- the second is an outage with a CI round trip as its floor.
  --
  -- This is one handler, at one boundary, on the one function whose failure mode is a
  -- total outage. It is NOT a licence to swallow errors anywhere else. Because it is
  -- silent, the hook's behaviour cannot be inferred from the product working — it is
  -- proven by calling this function directly with a synthetic event and asserting on
  -- the returned jsonb.
  return event;
end;
$$;


-- ---------------------------------------------------------------------------
-- 5. Privileges (design § 1)
--    Auth calls the hook as `supabase_auth_admin`. That role gets `usage` on the
--    schema and `execute` on this one function, and nothing else. `execute` is
--    revoked from `public`, `anon` and `authenticated`, because `execute` on a new
--    function is granted to `public` by default — leaving it would put a function
--    whose entire job is to decide who is a super admin within reach of every
--    signed-in session.
-- ---------------------------------------------------------------------------

grant usage on schema app to supabase_auth_admin;

revoke execute on function app.custom_access_token_hook(jsonb) from public;
revoke execute on function app.custom_access_token_hook(jsonb) from anon;
revoke execute on function app.custom_access_token_hook(jsonb) from authenticated;
grant  execute on function app.custom_access_token_hook(jsonb) to supabase_auth_admin;
