-- Phase 2 — the hook's own lookups get indexes, and `ended_at` is clamped like
-- `started_at`. Both from the third blind critic, which returned GO; neither blocked it.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 6 Impersonation — "`ended_at` is clamped the same way, and for the same reason"
--                     — "The hook's own lookups need indexes, and § 8.6 did not cover them"
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/identity/spec.md,
--                .../specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-042 (replayed inside begin … rollback
--   before it is pushed).
--
-- Statement order is docs/data-model.md's: functions → indexes. No policy, no trigger —
-- 20260908035810 already attached `impersonation_sessions_immutable` to the function this
-- file replaces in place. No begin/commit.


-- ---------------------------------------------------------------------------
-- 1. `ended_at` is clamped forward, exactly as `started_at` is
--
--    The rest of this function, and the reasoning behind the forward-only `started_at`
--    clamp and the terminal end, is in 20260908035810. One line changes here.
--
--    The trigger took the submitted `ended_at` verbatim, and
--    `impersonation_sessions_impersonator_write` pins only `ended_at is not null` — so an
--    impersonator could close a fifty-minute session claiming it ended at its own start,
--    or in 2031. **Nothing reads the value**: liveness, the one-open-session index and
--    `impersonation_sessions_audit_end`'s `when` clause all read only its *nullness*, and
--    the audit row's own `created_at` records the true instant beside the claimed one. So
--    there is no liveness and no privilege consequence, which is why the critic found it
--    and correctly declined to block on it.
--
--    It is closed anyway, because it is **the same shape a third time**: one end of a
--    range bounded and the other left free. `_ttl_chk` bounded the span and left the
--    anchor free; the anchor clamp bounded the start and left the terminus free. A rule
--    that keeps recurring in one table is a rule worth applying everywhere it fits rather
--    than each time someone notices.
-- ---------------------------------------------------------------------------

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
    -- Forward only: a session may not start in the future, and may start in the past.
    -- A bare `now()` would make an *expired* session unconstructible inside a
    -- transaction, and expiry is half of liveness. See 20260908035810 for the full
    -- argument and for what a backdated anchor still permits.
    new.started_at := least(coalesce(new.started_at, now()), now());
    return new;
  end if;

  -- Written once, then only ended, and ending is terminal: the row reverts to what is
  -- stored, and `ended_at` is the caller's only while it was still null. `new := old`
  -- takes the row whole, so a column added to this table in a later phase is pinned the
  -- day it exists.
  v_ended_at := new.ended_at;
  new        := old;

  if old.ended_at is null and v_ended_at is not null then
    -- Clamped forward, like the anchor: a session cannot claim to have ended at a time it
    -- had not yet reached.
    --
    -- **`v_ended_at is not null` is not tidiness — without it this clamp closes sessions
    -- by accident.** `least(null, now())` is `now()`, so an update that leaves `ended_at`
    -- alone would end the session, write an end audit row and free the one-open-session
    -- slot, with nothing anywhere saying why. `impersonation_sessions_impersonator_write`
    -- refuses such an update, but `service_role` and `postgres` do not go through a
    -- policy, and they are exactly the callers a silent close would hurt. Assigning only
    -- when the caller actually set a value is the whole fix: `new := old` above has
    -- already carried the old value through.
    new.ended_at := least(v_ended_at, now());
  end if;

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 2. Indexes — the access-token hook's own lookups
--
--    `app.custom_access_token_hook()` resolves an identity by querying `staff` and
--    `members` on `user_id` **alone**. Measured against the live catalogue before writing
--    this file: the only indexes carrying that column are
--    `staff_tenant_id_user_id_key` and `members_tenant_id_user_id_key`, both leading with
--    `tenant_id`, which cannot serve `where user_id = $1`. The hook therefore did up to
--    four sequential scans on **every token mint and every refresh**, and with
--    `jwt_expiry = 900` that is four refreshes an hour per signed-in user.
--
--    Why that is worse than ordinary slowness: the hook has a two-second budget, and
--    § 2's `exception when others then return event` swallows a timeout silently. The
--    failure mode at scale is every user holding a claim-less token — a session that
--    reads zero rows and raises nothing — with nothing in any log to say why. The one
--    place a missing index turns into a silent product-wide outage rather than a slow
--    page.
--
--    **How it got through, worth stating because it is the gap and not the index:**
--    § 8.6 discharged index rule 3 for *policy* predicates and measured every one of
--    them. It never looked at the hook's own queries, which are not policy predicates and
--    which no rule in `docs/data-model.md` covers. A function that runs on every
--    authentication is as load-bearing as a policy and nothing was watching it.
--
--    Partial on `user_id is not null` to match the shape of the two existing indexes, and
--    because a null `user_id` — a member or staff row not yet linked to an auth identity
--    — is never what the hook looks up. Index rule 2 already accepts a partial index for
--    exactly this reason: the probe is `where user_id = $1`, which implies the predicate.
--
--    Both tables are empty today, which is why this is a cheap build now and a locked
--    table later.
-- ---------------------------------------------------------------------------

create index staff_user_id_idx
  on public.staff (user_id)
  where user_id is not null;

create index members_user_id_idx
  on public.members (user_id)
  where user_id is not null;
