-- phase3_approver_boundary_and_missing_settings
--
-- Three findings from the Phase 3 blind critic, in one forward-only migration.
--
-- 1. ADR-065 WAS NEVER APPLIED. `20260908074851_phase3_pause_approver_matches_matrix.sql`
--    is a ZERO-BYTE FILE -- a shell command timed out between `supabase migration
--    new` and the heredoc that was to fill it, and the empty file was committed
--    and then recorded as applied. So `organization_settings_pause_approver_role_chk`
--    still permits `trainer` while `membership_pauses_tenant_write` is
--    `is_front_office()`, which is the contradiction ADR-065 says was closed.
--    A document claiming a boundary was tightened when it was not is worse than
--    the untightened boundary, because it stops anyone looking again.
--
-- 2. THE SIXTH INSTANCE OF ADR-066. `pause_approver_role` is enforced in exactly
--    one place: a TypeScript comparison in the pause Route Handler. The live
--    write gate on `membership_pauses` is `is_front_office()` for ALL commands,
--    with no constraint and no trigger -- so any front-desk session can approve a
--    freeze through `supabase-js` directly, **including one they requested
--    themselves**, going straight round the check. `max_freeze_days_per_year`
--    rides the same bypass. This is the pattern's other face: not a privilege
--    crossed in something that runs first, but a rule that lives only in a caller
--    when the table is reachable without it.
--
--    The rule moves to the table. It fires only when there is an acting staff
--    session (`app.current_staff_id()` is not null): `postgres` and
--    `service_role` carry no claim, bypass RLS by design, and are the contexts
--    the seed and the pgTAP fixtures run in.
--
--    Self-approval is refused with it. A freeze is a commercial decision and the
--    person who asked for it is not the person who should grant it.
--
-- 3. A gym with no `organization_settings` row gets NO check-in de-duplication,
--    silently. It is NOT fixed here, and the reason is worth the paragraph.
--    Detecting it inside the check-in trigger is unsafe: under `security
--    invoker` the settings read is filtered by RLS, so "no settings row" and "a
--    gym you cannot read" come back identically, and raising would answer a
--    question about another tenant *before* the policy refuses the row -- ADR-066's
--    exact pair, in the fix for something else. A first draft did raise, and two
--    blind holdout assertions about cross-tenant refusal caught it immediately.
--    Creating the row automatically from an `after insert` trigger on
--    `organizations` was the next attempt and is worse: every pgTAP fixture and
--    `seed.sql` insert their own settings row, so the trigger's row collides with
--    theirs and thirty files abort on 23505. Recorded as OPEN-018 instead:
--    zero organizations lack a settings row today, and gym onboarding -- which
--    is what would create one badly -- does not exist until Phase 6.
--
-- `security invoker` throughout (ADR-066): every caller who may write a pause or
-- attendance can already read `organization_settings` (`is_staff()`) and `staff`
-- (`is_staff()`), so elevation would buy nothing and cost the isolation.


-- ---------------------------------------------------------------------------
-- 1. Constraints
-- ---------------------------------------------------------------------------

alter table public.organization_settings
  drop constraint if exists organization_settings_pause_approver_role_chk;

alter table public.organization_settings
  add constraint organization_settings_pause_approver_role_chk
  check (pause_approver_role in ('gym_owner', 'gym_manager', 'front_desk'));


-- ---------------------------------------------------------------------------
-- 2. Functions
-- ---------------------------------------------------------------------------

create or replace function app.enforce_pause_decision()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_actor_staff_id uuid;
  v_actor_role     public.app_role;
  v_required_role  public.app_role;
begin
  v_actor_staff_id := app.current_staff_id();

  -- No acting staff session: `postgres` (the seed, every pgTAP fixture) and
  -- `service_role`. Both bypass row security by design and are trusted contexts;
  -- imposing the rule on them would break the fixtures without protecting
  -- anything a policy is not already protecting.
  if v_actor_staff_id is null then
    return new;
  end if;

  -- Only a transition into "approved" is governed. A rejection needs no special
  -- role -- refusing a freeze is not the commercial decision granting one is --
  -- and every other column is already governed by the write policy.
  if new.approved_at is null or old.approved_at is not null then
    return new;
  end if;

  if new.approved_by_staff_id is distinct from v_actor_staff_id then
    raise exception 'pause approval refused: the approver recorded (%) is not the acting staff member (%)',
      new.approved_by_staff_id, v_actor_staff_id
      using errcode = 'GL020';
  end if;

  if new.approved_by_staff_id is not distinct from old.requested_by_staff_id then
    raise exception 'pause approval refused: staff member % requested this pause and cannot also approve it',
      v_actor_staff_id
      using errcode = 'GL021';
  end if;

  select s.pause_approver_role into v_required_role
    from public.organization_settings s
   where s.tenant_id = new.tenant_id;

  if v_required_role is null then
    raise exception 'pause approval refused: gym % has no organization_settings row, so no approver role is configured', new.tenant_id
      using errcode = 'GL022';
  end if;

  select st.role into v_actor_role
    from public.staff st
   where st.id = v_actor_staff_id
     and st.tenant_id = new.tenant_id;

  if v_actor_role is distinct from v_required_role then
    raise exception 'pause approval refused: this gym requires % to approve a pause, and the acting staff member is %',
      v_required_role, coalesce(v_actor_role::text, 'not a member of this gym')
      using errcode = 'GL023';
  end if;

  return new;
end;
$$;


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

  -- A null window is NOT raised on here, and the reason is the whole of ADR-066
  -- read once more. Under `security invoker` this select is filtered by
  -- `organization_settings_tenant_select`, so "this gym has no settings row" and
  -- "this is a gym you cannot read" come back identically — null. Raising on it
  -- would answer a question about another tenant, and it would fire *before* the
  -- policy that should have refused the row, which is exactly the pair ADR-066
  -- names. A first draft of this migration did raise, and the blind holdout
  -- suite caught it: two assertions about cross-tenant refusal started failing
  -- with the new error instead of the policy's.
  --
  -- The real defect — a gym genuinely without settings getting no de-duplication
  -- — is fixed at its source below, by making a settings-less organization
  -- impossible to create, rather than by detecting one late from a context that
  -- cannot tell it apart from a permission failure.
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
-- 3. Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists membership_pauses_enforce_decision on public.membership_pauses;

create trigger membership_pauses_enforce_decision
  before update on public.membership_pauses
  for each row execute function app.enforce_pause_decision();

