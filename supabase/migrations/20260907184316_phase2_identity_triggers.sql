-- Phase 2 — identity behaviour: session revocation, the role-change audit row, the
-- impersonation audit rows, and one live impersonation session per actor.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 6 Impersonation (the audit rows the database writes; one live session per actor)
--   § 7 `is_active` and role changes are load-bearing (OPEN-009)
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/identity/spec.md,
--                .../specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-033 (audit_log's nullable tenant_id),
--   ADR-042 (replayed inside begin … rollback before it is pushed),
--   ADR-047/049 (audit_log is read-only to `authenticated`, so only a definer function
--   can write it — the caller could not, even if it remembered to).
--
-- Statement order is docs/data-model.md's: functions → indexes → triggers. No table, no
-- column, no policy and no grant. No begin/commit: CI applies this forward-only.
--
-- **Verified against this project before relying on it** (design § 7 asks for exactly
-- this, and says to stop and report rather than improvise if it fails):
--   `auth.sessions` exists, is owned by `supabase_auth_admin`, and has row security
--   enabled. Its ACL is
--     {postgres=ar*wdDxtm/supabase_auth_admin, supabase_auth_admin=arwdDxtm/…, dashboard_user=…}
--   so `has_table_privilege('postgres','auth.sessions','DELETE')` is true, and
--   `postgres` carries `rolbypassrls = true` (and `rolsuper = false`), so the table's
--   row security does not apply to it. A `security definer` function owned by
--   `postgres` may therefore delete from it. `auth.refresh_tokens` and
--   `auth.mfa_amr_claims` both reference `auth.sessions (id)` `on delete cascade`, so
--   deleting the session takes the refresh token with it — which is what makes the
--   access token in hand the last one that user will ever hold.
--
-- **The residual window is real and is not designed away.** Between the trigger firing
-- and the current access token expiring, a deactivated user still holds valid claims.
-- `[auth] jwt_expiry` in `supabase/config.toml` is what makes that window a number
-- someone chose. Any requirement claiming the window does not exist is false.


-- ---------------------------------------------------------------------------
-- 1. Session revocation, and the role-change and deactivation audit rows (§ 7)
--    One function for the three identity tables. The `when` clause on each trigger
--    below is what keeps an unrelated update from ever reaching it.
--
--    `security definer` for two reasons: `auth.sessions` is not writable by the role
--    performing the update, and `audit_log` is read-only to `authenticated` (ADR-049).
--
--    `members` carries neither `is_active` nor `role` — its lifecycle columns are
--    `status` and `erased_at`, and a member's role is always `member`. The deactivation
--    half maps onto `status` becoming `cancelled` or `blocked`, or `erased_at` being set
--    (DPD-006); a `paused` or `expired` member keeps their session, because renewing is
--    what they sign in to do. The role half does not apply to `members` at all, so it
--    writes no role-change audit row — that asymmetry is real and is not an omission.
--    This is the same per-table definition of "active" the access-token hook uses, so
--    the identity that would get no claims on the next sign-in is the identity whose
--    sessions go now.
-- ---------------------------------------------------------------------------

create or replace function app.revoke_sessions_on_identity_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id        uuid;
  v_deactivated    boolean := false;
  v_old_role       text;
  v_new_role       text;
  v_tenant_id      uuid;    -- null on platform_users: the row is platform-level (ADR-033)
  v_record_type    text;
  v_record_id      uuid;
  v_deact_before   jsonb;
  v_deact_after    jsonb;
  v_actor_user_id  uuid;
  v_actor_role     public.app_role;
begin
  -- Every field reference below sits inside the branch for the table that has it.
  -- A record field named in one SQL expression is resolved against the row type when
  -- that statement is first planned, so `new.id` and `new.status` may not share an
  -- expression -- a `case` over tg_table_name would fail on the table lacking the field.
  v_user_id := new.user_id;

  if tg_table_name = 'members' then
    -- Active, per § 4's per-table table, is `status not in ('cancelled','blocked') and
    -- erased_at is null`. Deactivation is the transition out of that, so pausing or
    -- expiring a member revokes nothing: both sides of the transition are still active.
    v_deactivated  := (old.status::text not in ('cancelled', 'blocked')
                       and old.erased_at is null)
                  and (new.status::text in ('cancelled', 'blocked')
                       or new.erased_at is not null);
    v_tenant_id    := new.tenant_id;
    v_record_type  := 'member';
    v_record_id    := new.id;
    v_deact_before := jsonb_build_object('status', old.status, 'erased_at', old.erased_at);
    v_deact_after  := jsonb_build_object('status', new.status, 'erased_at', new.erased_at);
  elsif tg_table_name = 'staff' then
    v_deactivated  := old.is_active and not new.is_active;
    v_old_role     := old.role::text;
    v_new_role     := new.role::text;
    v_tenant_id    := new.tenant_id;
    v_record_type  := 'staff';
    v_record_id    := new.id;
    v_deact_before := jsonb_build_object('is_active', old.is_active);
    v_deact_after  := jsonb_build_object('is_active', new.is_active);
  else
    v_deactivated  := old.is_active and not new.is_active;
    v_old_role     := old.role::text;
    v_new_role     := new.role::text;
    v_record_type  := 'platform_user';
    v_record_id    := new.user_id;   -- platform_users is keyed on user_id and has no id
    v_deact_before := jsonb_build_object('is_active', old.is_active);
    v_deact_after  := jsonb_build_object('is_active', new.is_active);
  end if;

  -- Unlike the impersonation trigger, these run under the *caller's* session, so the
  -- actor comes from the JWT. audit_log.actor_role is `public.app_role` but
  -- app.current_app_role() returns text and casts nothing (§ 3), so the label is resolved
  -- through the enum's own catalogue: a forged role records as null rather than raising
  -- `22P02`, which would turn an audit write into a failed UPDATE and reintroduce the
  -- failure mode § 3 removed. Not an inline list of the seven labels -- that is a second
  -- role vocabulary, which is what ADR-031 deleted `ROLES` from `packages/shared` to stop.
  v_actor_user_id := auth.uid();
  v_actor_role    := (select e.enumlabel::text::public.app_role
                        from pg_catalog.pg_enum e
                       where e.enumtypid = 'public.app_role'::regtype
                         and e.enumlabel = app.current_app_role());

  -- INT-003 names a role change as an audited event, and the same trigger writes it:
  -- a caller who must remember is a caller who will eventually forget. `members` has no
  -- `role` column, so it never reaches this branch -- that asymmetry is real, not an
  -- omission.
  if v_old_role is distinct from v_new_role then
    insert into public.audit_log (
      tenant_id, actor_user_id, actor_role, impersonation_session_id,
      action, record_type, record_id, before, after
    )
    values (
      v_tenant_id, v_actor_user_id, v_actor_role, app.current_impersonation_id(),
      v_record_type || '.role_changed', v_record_type, v_record_id,
      jsonb_build_object('role', v_old_role),
      jsonb_build_object('role', v_new_role)
    );
  end if;

  -- Deactivation is audited too. INT-003 does not name it, so this is a deliberate
  -- addition (§ 7): deactivating a compromised super admin is the most security-relevant
  -- write in this schema, the trigger is already firing here to revoke sessions, and a
  -- log recording "front desk became a manager" but not "the super admin was switched
  -- off" is inconsistent in the direction that matters.
  if v_deactivated then
    insert into public.audit_log (
      tenant_id, actor_user_id, actor_role, impersonation_session_id,
      action, record_type, record_id, before, after
    )
    values (
      v_tenant_id, v_actor_user_id, v_actor_role, app.current_impersonation_id(),
      v_record_type || '.deactivated', v_record_type, v_record_id,
      v_deact_before, v_deact_after
    );
  end if;

  -- A stale `app_role` claim is a stale privilege, so a role change revokes as surely
  -- as a deactivation does. A row with no linked auth user has nothing to revoke.
  --
  -- This deletes *every* session the user holds, not only the one naming this tenant --
  -- a session row carries no tenant, so there is nothing narrower to filter on, and the
  -- wider behaviour is also the right one: the deactivated identity may be the very
  -- tenant the current token names, and the only way to be sure the next token's claims
  -- are correct is to make the next token be minted. A user employed at two gyms and
  -- deactivated at one re-authenticates at the other. That is the cost, and it is not a bug.
  if v_user_id is not null
     and (v_deactivated or v_old_role is distinct from v_new_role) then
    delete from auth.sessions where user_id = v_user_id;
  end if;

  return null;
end;
$$;


-- ---------------------------------------------------------------------------
-- 2. The impersonation audit rows (§ 6)
--    Written by the database, not by the caller: INT-003 requires both, and `audit_log`
--    is read-only to `authenticated` in any case, so the caller could not write them.
--
--    The asymmetry, stated rather than papered over: an *expired* session's end row is
--    written when someone ends it, not when it expires. Nothing sweeps the table, so
--    `audit_log` shows starts without matching ends for abandoned sessions and a reader
--    must use `impersonation_sessions.expires_at` rather than assume an end row exists.
-- ---------------------------------------------------------------------------

create or replace function app.audit_impersonation_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_before jsonb;
  v_after  jsonb;
begin
  -- The row, column by column, is § 6's table. Every value comes from the session row
  -- and none from a claim: this trigger fires under `service_role` or `postgres` and
  -- holds no JWT, so `actor_user_id` is `impersonation_sessions.actor_user_id` and
  -- `actor_role` is the only role the insert policy admits.
  --
  -- INT-003 requires a before/after summary on every audited event. A start has no
  -- prior state; an end is the transition that set `ended_at`.
  --
  -- The branch is on `tg_op` and not a `case` inside the insert, because `old` is
  -- unassigned on an INSERT trigger and a record field is resolved when its expression
  -- is evaluated -- so `old.ended_at` may only appear on a path an insert never takes.
  if tg_op = 'INSERT' then
    v_action := 'impersonation_session.started';
    v_after  := jsonb_build_object('started_at', new.started_at,
                                   'expires_at', new.expires_at,
                                   'tenant_id',  new.tenant_id);
  else
    v_action := 'impersonation_session.ended';
    v_before := jsonb_build_object('ended_at', old.ended_at);
    v_after  := jsonb_build_object('ended_at', new.ended_at);
  end if;

  -- `record_id` and `impersonation_session_id` both carry the session id, deliberately:
  -- `record_id` says what the row is *about*, `impersonation_session_id` is the column
  -- every other audit row uses to say what session it was written *under*, so "everything
  -- done during session X" finds the start and end rows through the same column as the rest.
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, reason, before, after
  )
  values (
    new.tenant_id,
    new.actor_user_id,
    'super_admin',
    new.id,
    v_action,
    'impersonation_session',
    new.id,
    new.reason,          -- on both rows: an auditor reading only the end row should not
                         -- have to join back to learn why the session existed
    v_before,
    v_after
  );

  return null;
end;
$$;


-- ---------------------------------------------------------------------------
-- 3. Indexes
--    One live impersonation session per actor (§ 6), so the tenant an impersonating
--    token names is never ambiguous and the hook needs no ordering rule.
--
--    The predicate is `ended_at is null` and not the full liveness expression, because
--    `now()` is not immutable and cannot appear in an index predicate. So the qualifier
--    is `open`, not `live`: this index enforces at most one *open* session, and
--    `app.impersonation_is_live()` is the only place that decides what *live* means.
--    Open is a superset of live, so at most one live session follows.
--
--    Not tenant-scoped, deliberately, and so not an ADR-047 instance: `actor_user_id`
--    references `platform_users`, which carries no tenant column, and no gym-side role
--    can insert into this table at all (its gym-side policy is select-only).
-- ---------------------------------------------------------------------------

create unique index impersonation_sessions_actor_user_id_open_key
  on public.impersonation_sessions (actor_user_id)
  where ended_at is null;


-- ---------------------------------------------------------------------------
-- 4. Triggers
--    `after` in every case: the row's new state is what is audited, and a revocation
--    that fired before the update could revoke on an update that then rolled back.
--    Each `when` clause is the "an unrelated update revokes nothing" guarantee — the
--    function is not entered at all for a name change.
-- ---------------------------------------------------------------------------

create trigger platform_users_identity_change
  after update on public.platform_users
  for each row
  when (old.is_active is distinct from new.is_active
        or old.role is distinct from new.role)
  execute function app.revoke_sessions_on_identity_change();

create trigger staff_identity_change
  after update on public.staff
  for each row
  when (old.is_active is distinct from new.is_active
        or old.role is distinct from new.role)
  execute function app.revoke_sessions_on_identity_change();

create trigger members_identity_change
  after update on public.members
  for each row
  when (old.status is distinct from new.status
        or old.erased_at is distinct from new.erased_at)
  execute function app.revoke_sessions_on_identity_change();

create trigger impersonation_sessions_audit_start
  after insert on public.impersonation_sessions
  for each row
  execute function app.audit_impersonation_session();

create trigger impersonation_sessions_audit_end
  after update on public.impersonation_sessions
  for each row
  when (old.ended_at is null and new.ended_at is not null)
  execute function app.audit_impersonation_session();
