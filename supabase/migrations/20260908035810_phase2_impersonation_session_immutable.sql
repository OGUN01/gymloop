-- Phase 2 — an impersonation session is written once and then only ended.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 6 Impersonation — "An impersonation session is immutable except for `ended_at`,
--       and its `started_at` is set by the database"
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-042 (replayed inside begin … rollback
--   before it is pushed), ADR-049 (`audit_log` is read-only to `authenticated`).
--
-- Statement order is docs/data-model.md's: functions → policies → triggers. The policy
-- is dropped and re-created because `create policy` has no `or replace` and this one is
-- already applied — the same fix-forward exemption ADR-047's migration took, and the one
-- 20260907184315_phase2_role_matrix.sql already carries. No begin/commit.
--
-- ---------------------------------------------------------------------------
-- Two defects, both found by a blind critic against the live database
-- ---------------------------------------------------------------------------
--
-- **1. The TTL bounded the span and left the anchor free.**
-- `impersonation_sessions_ttl_chk` bounds `expires_at - started_at` to two hours, but
-- `started_at` is `timestamptz not null default now()` and client-settable with no upper
-- bound, and `app.impersonation_is_live()` asks only `ended_at is null and
-- expires_at > now()`. So
--
--     started_at = now() + interval '10 years',
--     expires_at = started_at + interval '2 hours'
--
-- passes `_ttl_chk`, passes `_expires_at_after_started_at_chk`, and is **live right now,
-- for a decade**. "A future timestamp is not a bound" was the whole argument for adding
-- the TTL, and the TTL made the identical mistake one column over.
--
-- `check (started_at <= now())` cannot express it: `now()` is not immutable and Postgres
-- rejects it in a constraint. So the database **sets** the value rather than validating
-- it, which is the only remaining place to put the rule.
--
-- **2. The end path could retarget the session — audit forgery.**
-- `impersonation_sessions_impersonator_write` pinned `ended_at is not null` and nothing
-- else, so an impersonator could end its session *and* rewrite `tenant_id` and `reason`
-- in the same statement. `app.audit_impersonation_session()` writes the end row from
-- `new.tenant_id` and `new.reason`, so `audit_log` would carry an end row for a gym that
-- was never impersonated while the real target's start row had no matching end — and
-- `audit_log_impersonation_session_id_fkey` is single-column, so referential integrity
-- does not notice.
--
-- One trigger closes both, and the rule it states is one sentence a reader can hold —
-- **a session is written once and then only ended** — rather than a list of columns that
-- every future policy has to remember to pin.


-- ---------------------------------------------------------------------------
-- 1. The immutability trigger function
--
--    `security invoker`: it only rewrites the row it was handed and touches no table, so
--    definer rights would buy nothing — the same reasoning as app.touch_updated_at().
--
--    On update it does **not** enumerate the columns to restore. `new := old` takes the
--    stored row whole and the submitted `ended_at` is put back on top, so a column added
--    to this table in a later phase is pinned the day it exists. A written-out list is
--    the version that silently stops covering the table it guards -- the same drift the
--    fourteen `<t>_member_select` policies were fixed for, one table over. Taking the row
--    whole also makes the rule literally readable: the row *is* the stored row, except
--    `ended_at`.
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
    -- The anchor is clamped **forward only**: a caller may not start a session in the
    -- future, and may start one in the past. With `expires_at` bounded against the
    -- anchor by `_ttl_chk`, a session therefore cannot be live for longer than two hours
    -- from now.
    --
    -- **`least(...)` and not a bare `now()`, and the qualifier is load-bearing.** An
    -- unconditional `started_at := now()` closes the same hole and makes an *expired*
    -- session unconstructible inside a transaction, anywhere: `now()` is the transaction
    -- timestamp and never advances, so pinning the anchor to it makes
    -- `expires_at > started_at` force every expiry into the future. Expiry is half of
    -- liveness and this phase leans on it twice -- the hook hands a lapsed session's
    -- actor back an ordinary platform token, and an abandoned session leaves a start with
    -- no end -- so neither behaviour could be tested at all. A future anchor is the
    -- defect; a past anchor is ordinary history, and the clamp does not need to reach the
    -- past to close the hole.
    --
    -- **What a backdated anchor still permits, stated rather than left implicit:** a
    -- super admin may write a session whose `started_at` precedes the write. It is
    -- detectable -- `created_at` defaults to the insert time and is immutable under the
    -- update branch below, so `started_at < created_at` names every backdated row -- and
    -- it changes nothing about liveness, since `expires_at` is bounded relative to the
    -- anchor and the audit row carries its own timestamp.
    --
    -- The `coalesce` is belt, not load-bearing: the column is `not null` with a `now()`
    -- default and Postgres fills defaults in before a `before insert` trigger runs, so
    -- `new.started_at` is already `now()` when the caller omits it. It is written because
    -- the contract specifies this expression literally and because a reader should not
    -- have to know that fact to read the line.
    new.started_at := least(coalesce(new.started_at, now()), now());
    return new;
  end if;

  -- Written once, then only ended: the row reverts to what is stored, and `ended_at` is
  -- the caller's only while it was still null.
  --
  -- **Ending is terminal.** Once `ended_at` is set nothing may change at all -- the
  -- reason is the audit log rather than the access. The end row has already been
  -- written, so un-ending gives a session that is live again *after its own log says it
  -- closed*, and ending it a second time writes a second end row against one start.
  -- "Written once and then only ended" is the rule; a session that can be reopened is
  -- neither. An update against an ended session is a silent no-op -- the row comes back
  -- unchanged rather than raising, which is this phase's semantics everywhere else.
  v_ended_at := new.ended_at;
  new        := old;

  if old.ended_at is null then
    new.ended_at := v_ended_at;
  end if;

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 2. The impersonator's end policy gains the tenant term
--    The trigger above already makes a retarget impossible. The clause goes on anyway
--    because the trigger is a *different component*, and this phase has now been bitten
--    four times by a policy whose correctness was held somewhere else (§ 8.1: the
--    fourteen member policies, `_platform_write`'s composition with the hook, this
--    policy's missing role term, and now this). A policy that defends itself alone is
--    the standing requirement, not the discovery.
--
--    Index rule 3: `tenant_id` leads `impersonation_sessions_tenant_id_started_at_idx`.
--    `ended_at` is still only in `with check`, which is evaluated against one row already
--    in hand and drives no scan (§ 8.6).
--
--    Still no liveness term, and still must not have one — an expired, never-ended
--    session must stay endable by its own claim, or the one-open-session index locks its
--    actor out permanently. See 20260908025116.
-- ---------------------------------------------------------------------------

drop policy impersonation_sessions_impersonator_write on public.impersonation_sessions;

create policy impersonation_sessions_impersonator_write on public.impersonation_sessions
  for update to authenticated
  using (id = (select app.current_impersonation_id())
         and (select app.current_app_role()) = 'gym_owner'
         and tenant_id = (select app.current_tenant_id()))
  with check (id = (select app.current_impersonation_id())
              and (select app.current_app_role()) = 'gym_owner'
              and tenant_id = (select app.current_tenant_id())
              and ended_at is not null);


-- ---------------------------------------------------------------------------
-- 3. Triggers
--
--    **Firing order, checked rather than assumed.** Alphabetical trigger naming does not
--    decide it, though it is the obvious guess. Postgres fires all
--    `before` row triggers ahead of every `after` row trigger regardless of name, and
--    sorts by name only within one of those groups. This trigger is `before` and both
--    audit triggers are `after` (`impersonation_sessions_audit_start`,
--    `impersonation_sessions_audit_end` — verified against the live catalogue), so the
--    audit rows are written from the corrected row unconditionally, and the name is free.
--    It is named for what it does rather than to win a sort, and a later reader must not
--    "fix" the ordering by renaming: the guarantee is the timing keyword.
--
--    `before insert or update` in one trigger rather than two, because the function
--    already branches on `tg_op` and two triggers would be two places to keep in step.
-- ---------------------------------------------------------------------------

create trigger impersonation_sessions_immutable
  before insert or update on public.impersonation_sessions
  for each row execute function app.impersonation_session_immutable();
