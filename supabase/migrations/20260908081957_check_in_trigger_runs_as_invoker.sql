-- check_in_trigger_runs_as_invoker
--
-- Implements docs/decisions.md ADR-066. Forward-only (hard rule 7): the
-- function is replaced here rather than edited in the migration that created
-- it, because that migration is applied and an applied file stops describing
-- the database the moment it is edited.
--
-- ONE WORD CHANGES: `security definer` becomes `security invoker`.
--
-- Why it was `definer`, stated first because the reasoning was not silly.
-- Under invoker the function's own lookups are filtered by the policies on the
-- tables it reads, so a caller outside `is_staff()` would see zero rows from
-- `attendance` and `organization_settings`, and one outside `is_front_office()`
-- zero from `qr_sessions` -- a **silent pass** through the very checks this
-- trigger exists to make unavoidable. That is a real failure mode, and it is
-- what definer rights were reached for.
--
-- Why it is wrong anyway: **a caller who would get that silent pass is a caller
-- `attendance_tenant_write` refuses.** The write gate is `is_front_office()`,
-- so the pass never becomes a row -- row security declines the insert
-- immediately after the trigger returns. The elevation bought a guarantee
-- another mechanism was already giving, and the price was real: a `before
-- insert` trigger runs *ahead* of the policy, so every `authenticated` session
-- could reach four tables past RLS. A member replaying a `qr_session_id` out of
-- their own readable `attendance` row got `expires_at` and `revoked_at` back in
-- an error message, from a table their read gate returns zero rows of; `GL014`
-- printed `checkin_dedupe_seconds` from `organization_settings`, which the
-- matrix explicitly denies a member.
--
-- Neither half is a defect alone. Reading past RLS is what definer is for;
-- running before the policy is what a `before` trigger does. **The pair is the
-- defect**, which is why it survived an implementer, two blind test authors and
-- the orchestrator until one of them looked at both facts together.
--
-- Measured before relying on it -- every role that may insert attendance can
-- read everything this function reads, so no check silently passes for a caller
-- who can actually write:
--
--     attendance            write  is_front_office()   <- who may insert at all
--     qr_sessions           read   is_front_office()   exactly
--     attendance            read   is_staff()          front_office is a subset
--     memberships           read   is_staff()
--     organization_settings read   is_staff()
--     members               read   is_staff()
--
-- `postgres` and `service_role` bypass RLS either way, so `seed.sql` and the
-- pgTAP fixtures are unaffected. `pg_advisory_xact_lock`, `md5` and
-- `make_interval` all grant EXECUTE to PUBLIC, so the lock needs no privilege
-- of its own -- verified, not assumed.
--
-- The fix is deleting a word, never adding a permission check inside the
-- elevated function: that check is a second copy of the policy, and the copy is
-- what goes stale.
--
-- The trigger itself is unchanged and is not re-created here; `create or
-- replace function` keeps the existing attachment.


create or replace function app.enforce_check_in()
returns trigger
language plpgsql
volatile                 -- load-bearing; see the snapshot argument in the header
security invoker
set search_path = ''
as $$
declare
  v_expires_at     timestamptz;
  v_revoked_at     timestamptz;
  v_branch_id      uuid;
  v_window_seconds integer;
begin
  -- --- Identity comes from the token, never from the caller -----------------
  -- `attendance_tenant_write` already rejects a row labelled with another gym, and
  -- ADR-052's composite foreign keys already reject a member, branch, membership,
  -- staff member or QR session belonging to one. This line means the caller does not
  -- have to get it right in the first place: it never sends a tenant at all.
  new.tenant_id := coalesce(new.tenant_id, app.current_tenant_id());

  -- ATT-005: the acting staff member is whoever is holding the session, not whoever
  -- the request says. `attendance_front_desk_has_assist_chk` still requires the
  -- non-empty reason, and `attendance_assisted_pair_chk` still requires both halves
  -- together — so a front-desk row submitted by a session with no `staff_id` claim
  -- fails the constraint rather than being recorded anonymously.
  if new.source = 'front_desk'::public.attendance_source
     and new.assisted_by_staff_id is null then
    new.assisted_by_staff_id := app.current_staff_id();
  end if;

  -- --- ATT-001 / ATT-002: the scanned session and the live membership -------
  if new.qr_session_id is not null then
    -- Read with the tenant in the predicate. The composite foreign key would also
    -- reject another gym's session, but it fires after this trigger and reports
    -- itself as 23503 — a cross-gym scan should say what it was, not leak a
    -- constraint name.
    select q.expires_at, q.revoked_at, q.branch_id
      into v_expires_at, v_revoked_at, v_branch_id
      from public.qr_sessions q
     where q.id = new.qr_session_id
       and q.tenant_id = new.tenant_id;

    if not found then
      raise exception 'check-in refused: QR session % does not belong to this gym', new.qr_session_id
        using errcode = 'GL010';
    end if;

    -- Judged at the instant of the scan, not at the instant of the write. For a live
    -- scan those are the same; for Phase 7's offline replay they are not, and a code
    -- that was valid when it was scanned stays valid when the queue drains.
    if v_expires_at <= new.checked_in_at then
      raise exception 'check-in refused: that QR session expired at %', v_expires_at
        using errcode = 'GL011';
    end if;

    if v_revoked_at is not null and v_revoked_at <= new.checked_in_at then
      raise exception 'check-in refused: that QR session was revoked at %', v_revoked_at
        using errcode = 'GL012';
    end if;

    new.branch_id := coalesce(new.branch_id, v_branch_id);

    -- `memberships_tenant_id_member_id_live_key` makes "live" at most one row, so
    -- this is an existence test and not a choice between candidates.
    if not exists (
      select 1
        from public.memberships m
       where m.tenant_id = new.tenant_id
         and m.member_id = new.member_id
         and m.status in ('active'::public.membership_status,
                          'frozen'::public.membership_status)
    ) then
      raise exception 'check-in refused: member % holds no active or frozen membership', new.member_id
        using errcode = 'GL013';
    end if;
  end if;

  -- An assisted check-in carries no session, so its branch is the member's own.
  if new.branch_id is null then
    select mb.branch_id
      into v_branch_id
      from public.members mb
     where mb.tenant_id = new.tenant_id
       and mb.id = new.member_id;

    new.branch_id := v_branch_id;
  end if;

  -- --- ATT-004 and exactly-once --------------------------------------------
  -- The lock is taken before the window is read and released only when this
  -- transaction ends, so a concurrent check-in for the same member cannot run its
  -- own window query until this one's row is either visible or gone. md5 rather than
  -- hashtext: both are core, only one is documented.
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(new.tenant_id::text || ':' || new.member_id::text), 1, 16))::bit(64)::bigint
  );

  -- Per gym, never hardcoded. A gym with no settings row has configured no window,
  -- and gets none — the alternative, falling back to the column's own default, would
  -- put a second copy of that number here and call it configuration.
  select s.checkin_dedupe_seconds
    into v_window_seconds
    from public.organization_settings s
   where s.tenant_id = new.tenant_id;

  if coalesce(v_window_seconds, 0) > 0 and exists (
    select 1
      from public.attendance a
     where a.tenant_id = new.tenant_id
       and a.member_id = new.member_id
       -- A row is never its own duplicate. This is not defensive padding: a
       -- BEFORE INSERT trigger fires for every proposed row of an
       -- `insert … on conflict (id) do update`, including the ones that will
       -- resolve to the update — which is exactly the shape `supabase/seed.sql`
       -- uses to stay re-runnable. Without this line the second seed run would
       -- find each attendance row duplicating itself and refuse.
       and a.id <> new.id
       -- Symmetric around the new row, so an out-of-order replay collides with the
       -- row it duplicates rather than sliding in behind it.
       and a.checked_in_at > new.checked_in_at - make_interval(secs => v_window_seconds)
       and a.checked_in_at < new.checked_in_at + make_interval(secs => v_window_seconds)
       -- A resubmission of the *same* device event is not a second check-in; it is
       -- the same one arriving twice, and the unique index on
       -- (tenant_id, client_event_id) is what answers it — with 23505, which the
       -- Route Handler reports as success. Were it not excluded here, the replay
       -- would hit this window first and be reported as a duplicate *error*, which
       -- the spec says it must not be.
       and (new.client_event_id is null
            or a.client_event_id is distinct from new.client_event_id)
  ) then
    raise exception
      'check-in refused: member % already checked in inside this gym''s % second window',
      new.member_id, v_window_seconds
      using errcode = 'GL014';
  end if;

  return new;
end;
$$;
