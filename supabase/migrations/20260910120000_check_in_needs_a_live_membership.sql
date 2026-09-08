-- check_in_needs_a_live_membership
--
-- **The gate this product is sold on has never refused anybody.**
--
-- `app.enforce_check_in()` admitted a check-in whenever a membership row
-- existed with `status in ('active','frozen')`. It contained the string
-- `ends_on` zero times and `starts_on` zero times — verified from the
-- catalogue, not from the file. And **nothing in this product ever writes
-- `expired`**: ADR-064 says the status flip needs a scheduler that does not
-- exist, and ADR-075 is the round where the no-show scan was rewritten to stop
-- trusting that column and read the dates instead.
--
-- The scan got that fix. Check-in did not. So a member whose membership ended
-- in March could check in today, and tomorrow, and for ever — silently, with
-- the console cheerfully reporting "No active membership. Renew before checking
-- in." for a control the database did not have.
--
-- That is ADR-075's own sentence arriving in a sibling function: **an argument
-- for deriving one fact from evidence is an argument for deriving every fact of
-- that kind.**
--
-- Found by a blind critic reviewing Phase 5, which is the second-order point.
-- ADR-083 moved the grant of a membership's period from the sale to the
-- payment, and defended itself with "a desk that forgets the payment leaves a
-- member refused at the gate that evening — loud, and fixed in a minute". The
-- critic checked that claim against the trigger and it was false: the member
-- was admitted for ever. **A decision defended by a premise that turns out to
-- be false has to be re-decided, not quietly kept** — and re-deciding it here
-- means making the premise true, because a gate on renewal is what the product
-- promises regardless of which end of the sale grants the days.
--
-- Only the QR path is changed. The assisted front-desk path has never required
-- a membership at all — the whole `GL013` test sits inside
-- `if new.qr_session_id is not null` — and whether a gym may record a guest,
-- a trial or a walk-in against no membership is a product question this
-- migration is not the place to answer. Recorded as an open decision rather
-- than settled by a trigger nobody asked to widen.

CREATE OR REPLACE FUNCTION app.enforce_check_in()
 RETURNS trigger
 LANGUAGE plpgsql
 VOLATILE
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
  v_expires_at     timestamptz;
  v_revoked_at     timestamptz;
  v_branch_id      uuid;
  v_window_seconds integer;
  v_timezone       text;
  v_scan_day       date;
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
  -- Defaulting it when null was not enough, and the comment above was false for
  -- a year of reading: a SUPPLIED value was kept, so Desk One could record Desk
  -- Two as having marked a member present. The HTTP schema has no field for it,
  -- which made the endpoint honest and the table not — and the entire argument
  -- of this phase is that the endpoint is not the boundary.
  --
  -- Refused rather than overwritten. Silently replacing the caller's value would
  -- make the write succeed while meaning something the caller did not say, and a
  -- forged attribution deserves an answer, not a correction.
  if new.assisted_by_staff_id is not null
     and app.current_staff_id() is not null
     and new.assisted_by_staff_id is distinct from app.current_staff_id() then
    raise exception 'check-in refused: the acting staff member is % and cannot be recorded as %',
      app.current_staff_id(), new.assisted_by_staff_id
      using errcode = 'GL016';
  end if;

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
    -- **Live means the dates, not the status column.** Nothing in this product
    -- ever writes `expired` (ADR-064: the status flip needs a scheduler that
    -- does not exist), so the status-only test this replaced admitted a
    -- membership that ended in March, for ever. `app.run_no_show_scan()` was
    -- corrected for exactly this and reads `ends_on` directly (ADR-075); this
    -- function was not, and an argument for deriving one fact from evidence was
    -- always an argument for deriving every fact of that kind.
    --
    -- The gate the whole renewal loop depends on had never refused anybody.
    select o.timezone into v_timezone
      from public.organizations o
     where o.id = new.tenant_id;

    -- **The gym's day NOW, not the day the row claims to be about** — and this
    -- is the one genuine trade-off in this migration, so it is written down.
    --
    -- The QR expiry test two branches up judges at `new.checked_in_at`, for a
    -- good reason: Phase 7's offline queue drains later, and a code that was
    -- valid when it was scanned should stay valid when the row lands. The
    -- obvious move is to match it here.
    --
    -- It is the wrong move, because `checked_in_at` is CALLER-SUPPLIED and
    -- unbounded — `attendance` grants `insert` to `authenticated`. Judging
    -- liveness at a timestamp the caller chooses means anyone whose membership
    -- lapsed can send a date from when it had not, and the gate this entire
    -- migration exists to give teeth becomes decorative. Silently: nothing
    -- raises, nothing logs, and the renewal it was meant to force never comes.
    --
    -- Judging at the gym's today costs the narrow case of a 23:50 scan that
    -- syncs at 00:10 — refused, visibly, at a boundary somebody notices. This
    -- project breaks every tie the same way: prefer the failure that announces
    -- itself. Phase 7 owns the honest fix, and it is not "trust the timestamp"
    -- but `offline_recorded_at` and `replayed_at`, which exist on this table
    -- already and are exactly the evidence a backdated visit needs.
    --
    -- Never `current_date`: every Supabase connection is UTC, and a member
    -- would be refused a day early between 00:00 and 05:30 IST (ADR-039,
    -- MNY-004).
    v_scan_day := (pg_catalog.now() at time zone coalesce(v_timezone, 'UTC'))::date;

    if not exists (
      select 1
        from public.memberships m
       where m.tenant_id = new.tenant_id
         and m.member_id = new.member_id
         and m.status in ('active'::public.membership_status,
                          'frozen'::public.membership_status)
         -- A null timezone is a gym this session cannot read, and it is NOT
         -- raised on, for the whole of the reason the settings lookup below
         -- gives: under `security invoker` "no such gym" and "a gym you may not
         -- see" come back identically, and answering here would fire ahead of
         -- the policy that should refuse the row (ADR-066). The date test is
         -- skipped in that case and the status test still applies; the row is
         -- about to be refused by `attendance_tenant_write` regardless.
         and (v_timezone is null
              or ((m.starts_on is null or m.starts_on <= v_scan_day)
                  and (m.ends_on is null or m.ends_on >= v_scan_day)))
    ) then
      raise exception 'check-in refused: member % holds no membership live on % (the gym''s today)',
        new.member_id, v_scan_day
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
  -- — is therefore NOT fixed here and is NOT fixed anywhere: it is OPEN-018,
  -- deferred to Phase 6's gym onboarding, which creates the organization and its
  -- settings row in one transaction. Zero organizations are in that state today.
  --
  -- This paragraph used to claim the gap was closed "at its source below", by an
  -- `after insert` trigger on `organizations`. That trigger was written, then
  -- withdrawn when it collided with the settings rows the seed and thirty pgTAP
  -- fixtures insert themselves — and the sentence stayed, live in the database,
  -- for a reader to grep and conclude the gap was shut. A blind critic found it.
  -- It is the zero-byte-migration failure in miniature, and the reason it is
  -- worth this many lines is that a false comment does not merely fail to help:
  -- it stops the next person looking.
  if coalesce(v_window_seconds, 0) > 0 and exists (
    select 1
      from public.attendance a
     where a.tenant_id = new.tenant_id
       and a.member_id = new.member_id
       -- A row is never its own duplicate. This is not defensive padding: a
       -- BEFORE INSERT trigger fires for every proposed row of an
       -- `insert â€¦ on conflict (id) do update`, including the ones that will
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
$function$
;
