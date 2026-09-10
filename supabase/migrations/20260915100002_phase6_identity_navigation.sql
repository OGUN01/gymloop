-- NAV-003/007: remove stale Gymloop authorization on every hook outcome and
-- enforce support preview read-only at every authenticated-writable table.
-- Existing identity precedence, selection, eligibility, RLS and hook ACL remain.
-- New version follows the highest existing migration per ADR-112.
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
  -- cleans its five Gymloop keys before adding the resolved shape with `||`.
  v_claims := (case when jsonb_typeof(event -> 'claims') = 'object'
    then event -> 'claims' else '{}'::jsonb end)
    - array['app_role', 'tenant_id', 'staff_id', 'member_id', 'impersonation_session_id'];
  -- Assign the cleaned event before any lookup/cast that can take the fallback.
  event := jsonb_set(event, '{claims}', v_claims);
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
  -- Returning the cleaned event degrades to a token with no Gymloop claims: that
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

-- The session immutability trigger runs before the table-wide preview guard by
-- trigger name. Inspect the submitted row here, before it is normalized back to
-- OLD, so a preview cannot hide a tenant/reason rewrite inside an otherwise
-- valid own-session end. Non-preview callers keep the Phase 2 normalization.
create or replace function app.impersonation_session_immutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ended_at timestamptz;
begin
  if tg_op = 'INSERT' then
    new.started_at := least(coalesce(new.started_at, now()), now());
    return new;
  end if;

  if pg_catalog.row_security_active(tg_relid)
     and (auth.jwt() -> 'impersonation_session_id') is not null
     and (auth.jwt() -> 'impersonation_session_id') <> 'null'::jsonb
     and (
       old.id is distinct from app.current_impersonation_id()
       or old.actor_user_id is distinct from auth.uid()
       or old.tenant_id is distinct from app.current_tenant_id()
       or app.current_app_role() is distinct from 'gym_owner'
       or old.ended_at is not null
       or new.ended_at is null
       or (to_jsonb(new) - 'ended_at') is distinct from (to_jsonb(old) - 'ended_at')
     ) then
    raise exception using errcode = '42501', message = 'Support preview is read-only.';
  end if;

  v_ended_at := new.ended_at;
  new        := old;

  if old.ended_at is null and v_ended_at is not null then
    new.ended_at := least(v_ended_at, now());
  end if;

  return new;
end;
$$;

-- Trigger execution is private; no callable definer or new table policy is added.
create function app.enforce_preview_read_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if pg_catalog.row_security_active(tg_relid)
     and (auth.jwt() -> 'impersonation_session_id') is not null
     and (auth.jwt() -> 'impersonation_session_id') <> 'null'::jsonb then
    -- The existing immutable-session trigger normalizes the row before this
    -- guard. Only its own end remains possible; no actor or tenant is inferred.
    if tg_table_schema = 'public' and tg_table_name = 'impersonation_sessions'
       and tg_op = 'UPDATE' then
      if old.id = app.current_impersonation_id()
         and old.actor_user_id = auth.uid()
         and old.tenant_id = app.current_tenant_id()
         and app.current_app_role() = 'gym_owner'
         and new.ended_at is not null
         and (to_jsonb(new) - 'ended_at') = (to_jsonb(old) - 'ended_at') then
        return new;
      end if;
    end if;
    raise exception using errcode = '42501', message = 'Support preview is read-only.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function app.enforce_preview_read_only() from public, anon, authenticated;

-- Enumerate actual grants, rather than a handwritten table list. Independent
-- metadata tests require this boundary on future authenticated-writable tables.
do $$
declare
  v_table record;
begin
  for v_table in
    select c.relname
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and (pg_catalog.has_table_privilege('authenticated', c.oid, 'INSERT')
         or pg_catalog.has_table_privilege('authenticated', c.oid, 'UPDATE')
         or pg_catalog.has_table_privilege('authenticated', c.oid, 'DELETE'))
     order by c.relname
  loop
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function app.enforce_preview_read_only()',
      v_table.relname || '_preview_read_only', v_table.relname);
  end loop;
end;
$$;
