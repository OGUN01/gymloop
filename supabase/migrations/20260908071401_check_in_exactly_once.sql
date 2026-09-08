-- Phase 3 — check-in: the rules that make a visit real, enforced by the database.
--
-- Implements openspec/changes/phase-3-core-domain/specs/check-in/spec.md:
--   "A check-in is recorded only against a valid QR session and a live membership"
--     (ATT-001, ATT-002)
--   "A repeated scan inside the gym's window changes nothing" (ATT-004)
--   "Two simultaneous scans produce exactly one attendance row"
--   "An assisted check-in names the staff member and the reason" (ATT-005, ATT-006)
--   "A check-in never crosses a tenant"
-- Conventions: docs/data-model.md § Conventions → Migration file layout (this file
--   has only sections 2-functions and 9-triggers; it creates no type, table,
--   constraint, index, policy or grant), § Indexes rules 3 and 4.
-- Decisions: ADR-030 (CI applies migrations, forward-only), ADR-052 (composite
--   tenant foreign keys), ADR-055 (the role matrix owns *who* may write attendance;
--   this file owns *what* a written row must satisfy).
--
-- Depends on, and never re-creates: app.current_tenant_id(), app.current_staff_id()
-- (identity accessors), and the attendance cluster's tables, constraints and indexes.
--
--
-- ===========================================================================
-- WHY THIS IS A MIGRATION AND NOT A ROUTE HANDLER
-- ===========================================================================
--
-- The spec states the requirement that decides the design: *"A de-duplication
-- implemented as a read followed by a write is not sufficient: both reads can pass
-- before either writes, and the resulting duplicate is silent."* Everything below
-- follows from taking that sentence literally.
--
-- Phase 1 already gives exactly one of the two halves.
-- `attendance_tenant_id_client_event_id_key` — unique on (tenant_id, client_event_id)
-- where client_event_id is not null — makes a **repeated submission** idempotent: the
-- same device event replayed twice raises 23505 on the second, and the Route Handler
-- reports that as success rather than as an error (ATT-007's structural half).
-- It does nothing at all about **two different submissions** for the same member a
-- second apart, which is the double-tap a metro gate actually sees.
--
-- Four mechanisms were considered for that second half:
--
--   1. A unique index over (tenant_id, member_id, <time bucket>). Rejected: the bucket
--      width is `organization_settings.checkin_dedupe_seconds`, per gym, so it is not
--      a constant and cannot appear in an index expression, which must be immutable.
--   2. An exclusion constraint on (tenant_id with =, tstzrange(checked_in_at,
--      checked_in_at + window) with &&). Rejected for the same reason — the range
--      would have to be built from another table's column.
--   3. SERIALIZABLE isolation. Rejected: PostgREST runs every request in READ
--      COMMITTED, the isolation level is not reachable per-request from a Route
--      Handler, and it converts the problem into a retry loop the caller must write.
--   4. **A transaction-level advisory lock keyed on (tenant_id, member_id), taken
--      inside a BEFORE INSERT trigger, before the window is examined.** Chosen.
--
-- How (4) is exactly-once, in full, because it rests on one non-obvious property:
--
--   * `pg_advisory_xact_lock()` is held until the transaction ends and is released
--     only after that transaction's rows become visible. Two concurrent check-ins for
--     the same member hash to the same key, so the second blocks until the first has
--     committed (or rolled back).
--   * The second transaction then runs its window query. **A PL/pgSQL function
--     declared `volatile` takes a fresh snapshot at the start of each statement it
--     executes** (PostgreSQL, "Function Volatility Categories": a VOLATILE function
--     "obtains a fresh snapshot at the start of each query"), whereas a STABLE one
--     reuses the calling query's snapshot. The calling snapshot here is the one the
--     INSERT took *before* it blocked on the lock — it predates the other
--     transaction's commit, so a STABLE function would look straight past the row it
--     is meant to find and both inserts would succeed. **This function is therefore
--     deliberately volatile, and that is load-bearing rather than a default nobody
--     chose.** (Trigger functions are volatile unless declared otherwise; it is
--     spelled out below so a later edit cannot quietly make it stable.)
--   * Because the check runs in a BEFORE INSERT trigger rather than in application
--     code, it holds for every writer: this app's Route Handler, a direct PostgREST
--     insert by any front-office session, a future Edge Function on `service_role`,
--     and the offline replay Phase 7 will add. An invariant that a code path can
--     forget is a preference; this one cannot be forgotten.
--
-- Cost, stated rather than discovered later: two concurrent check-ins for the *same*
-- member serialise, and only those — the lock key is per member, so a morning rush of
-- five hundred different members takes five hundred different keys and never queues.
-- A single INSERT statement carrying several rows takes several locks in row order,
-- so two such statements in opposite orders can deadlock; Postgres detects that and
-- aborts one, and the Route Handler inserts one row at a time.
--
-- What this file deliberately does **not** do: require `qr_session_id` when `source`
-- is `qr`. The QR rules below fire on the presence of a session, which is what the
-- Route Handler always supplies for a scan. Making the column mandatory for that
-- source would be a stricter reading of ATT-001 than the spec states, and it would
-- retroactively invalidate rows and fixtures written under Phase 1's shape.


-- ---------------------------------------------------------------------------
-- 2. Functions
--
--    `security definer`, like the two Phase 2 trigger functions, and for the same
--    class of reason: the checks must be real for every caller, not merely for the
--    ones whose role happens to be allowed to read the tables involved. Under
--    `security invoker` the de-duplication query would be filtered by
--    `attendance_tenant_select` (`is_staff()`), the window would be filtered by
--    `organization_settings_tenant_select` (`is_staff()`) and the QR session by
--    `qr_sessions_tenant_select` (`is_front_office()`) — so a caller outside those
--    gates would get **zero rows and a silent pass**, which is precisely the failure
--    mode this whole file exists to remove. Definer rights read nothing back to the
--    caller: the function only raises or stamps.
--
--    It never trusts the caller for identity. `tenant_id` and `assisted_by_staff_id`
--    come from the JWT claim through the `app` accessors (AGENTS.md hard rule 9), and
--    `branch_id` is derived from the scanned session or from the member's own row.
--    All three are filled **only where the caller left them null**, so nothing
--    already correct is rewritten, no existing insert path changes shape, and a
--    writer that supplies a wrong tenant is still refused by
--    `attendance_tenant_write` rather than quietly corrected. The Route Handler
--    supplies the tenant anyway — the generated `Insert` type requires it, since the
--    column is `not null` with no default — and reads it from the verified token
--    rather than from the request body, which carries no tenant field at all.
--
--    Index obligations (docs/data-model.md § Indexes rules 3 and 4 — "anything that
--    runs on every request carries a policy's index obligation"). Every filter below
--    is already covered and this migration adds no index:
--      attendance (tenant_id, member_id, checked_in_at)
--        → attendance_tenant_id_member_id_checked_in_at_idx
--      memberships (tenant_id, member_id, status in ('active','frozen'))
--        → memberships_tenant_id_member_id_live_key (the predicate is implied by the
--          query, so the planner can use the partial index — rule 2's reasoning)
--      organization_settings (tenant_id)  → organization_settings_pkey
--      qr_sessions (id)                   → qr_sessions_pkey
--      members (tenant_id, id)            → members_tenant_id_id_key
--
--    Error codes. Five conditions, five SQLSTATEs. `RAISE … USING errcode` accepts
--    any five characters of digits and upper-case ASCII letters, and class `GL` is
--    used by none of PostgreSQL's own conditions (checked against Appendix A: the
--    two-character classes in use are 00 01 02 03 08 09 0A 0B 0F 0L 0P 21-28 2B 2D
--    2F 34 38 39 3B 3D 3F 40 42 44 53-58 72 F0 HV P0 XX). So the Route Handler maps
--    a failure to an HTTP status and a message by **code**, never by matching error
--    text — the text below carries a uuid and a timestamp for whoever reads the
--    Postgres log, and a message that is grepped is a message nobody may reword:
--      GL010  the QR session is not this gym's, or does not exist
--      GL011  the QR session had expired when the scan happened
--      GL012  the QR session had been revoked when the scan happened
--      GL013  the member holds no `active` or `frozen` membership
--      GL014  the member already checked in inside this gym's window
-- ---------------------------------------------------------------------------

create or replace function app.enforce_check_in()
returns trigger
language plpgsql
volatile                 -- load-bearing; see the snapshot argument in the header
security definer
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


-- ---------------------------------------------------------------------------
-- 9. Triggers
--
--    `before insert` only. A check-out is an update and ATT-008 says a missing one
--    blocks nothing, so nothing here may run on update: re-checking the window when
--    a member checks out would reject the check-out of the very row it matched.
-- ---------------------------------------------------------------------------

create trigger attendance_enforce_check_in
  before insert on public.attendance
  for each row execute function app.enforce_check_in();
