-- attendance_is_written_once_and_a_decider_is_identified
--
-- The Phase 3 blind critic's NO-GO, in one forward-only migration. Five
-- findings; three of them were introduced by the migration that closed the
-- previous NO-GO, which is the fact worth leading with.
--
-- ADR-068 names the two new defect shapes. In short:
--
-- D1/D2 -- SEPARATION OF DUTIES WAS DEFEATED BY ONE STATEMENT. `20260908150000`
--   widened the pause trigger to `insert or update` and, because OLD is null on
--   an insert, changed `old.requested_by_staff_id` to `new.`. That one edit
--   turned a comparison against a RECORDED FACT into a comparison between two
--   columns of the caller's own input. `membership_pauses` grants `update` to
--   `authenticated` and its write policy is `is_front_office()` for every
--   command, so a manager refused on the straight self-approval simply sent one
--   statement setting `requested_by_staff_id` to a colleague and approving it --
--   and the permanent record then named an employee who never asked. On an
--   INSERT both sides are always the caller's input, so the rule was vacuous
--   there by construction.
--
--   Fixed at the cause, not at the symptom: `requested_by_staff_id` becomes
--   immutable, which restores the recorded fact the comparison needs; and an
--   insert may not carry a decision at all, because on an insert there is no
--   recorded fact to compare against and no legitimate way for that state to
--   arise.
--
-- D3 -- AN IMPERSONATING PLATFORM ADMIN MET NO RULE. The guard opened with
--   `if app.current_staff_id() is null then return new;`, meaning "if I cannot
--   identify you, you are trusted". It was written for `postgres` and
--   `service_role`; its actual extension includes any `authenticated` session
--   with no `staff_id` claim -- and `app.custom_access_token_hook` mints exactly
--   that for a live impersonation session: `app_role = 'gym_owner'`, a
--   `tenant_id`, no `staff_id`. Such a session passed `is_front_office()`,
--   skipped every rule including "a decided pause stays decided", and could
--   rewrite who authorised a freeze. `docs/security.md` says an impersonating
--   token has the gym's reach and not more; it had more than a real owner's.
--
--   The predicate now names what it meant, and it asks the database rather than
--   assuming: `row_security_active()` is false exactly for the sessions no
--   policy applies to -- the table owner and any `BYPASSRLS` role -- and true
--   for an ordinary signed-in one. A session inside row security must produce a
--   staff identity before it may touch a decision.
--
--   Testing the CLAIM rather than the SESSION had a second failure the critic
--   did not reach and the blind holdout author did: `postgres` and
--   `service_role` fell OUT of the carve-out whenever `request.jwt.claims` was
--   populated -- which PostgREST does on every request, and which every pgTAP
--   file here does and never clears. It failed closed, as a `GL020` naming an
--   unrelated staff member, which is why it had never been noticed.
--
-- D4 -- EVERY CHECK-IN RULE WAS REACHABLE BY UPDATE. `attendance_enforce_check_in`
--   is `before insert`, so the de-duplication window, the live-membership gate,
--   the scanned session's validity and the acting staff member are properties of
--   INSERTING, not properties of `attendance`. `authenticated` held `update` on
--   the table with an ALL-command write policy, so one UPDATE produced two visits
--   inside the window, re-attributed a visit to a member with no live membership,
--   named an expired gate session on a row scanned with a valid one, or blanked
--   the assisted pair so the record that one person marked another present was
--   gone -- with `attendance_front_desk_has_assist_chk` still satisfied.
--
--   NOT fixed by widening the trigger's event list, and this is the interesting
--   half. An update to `attendance` is not a check-in arriving; it is a check-in
--   being rewritten, and re-running the arrival rules against a rewrite would
--   answer the wrong question.
--
--   The first fix written here was `revoke update on attendance from
--   authenticated`, and it was wrong. `06_attendance_checkin` asserts
--   `has_table_privilege('authenticated', 'attendance', 'UPDATE')` under the
--   heading INT-001, and `06_attendance_rls` exercises `set checked_out_at` --
--   a check-OUT is a legitimate later write to a visit that has already
--   happened. Revoking the grant would have closed the hole by deleting a
--   feature, and three suites said so. Narrowing the write policy to `for
--   insert` fails the same way, and additionally breaks the `with check` that
--   refuses moving one's own row into another gym.
--
--   So: the columns that carry what the check-in MEANT are frozen, and the
--   columns that record what happened afterwards stay writable. `tenant_id` is
--   deliberately NOT in the frozen list -- `attendance_tenant_write`'s `with
--   check` already refuses moving a row to another gym, and a `before` trigger
--   raising first would answer ahead of the policy, which is ADR-066 exactly.
--
-- D5 -- `assisted_by_staff_id` WAS WHOEVER THE CALLER SAID. See the comment at
--   the stamp itself.
--
-- D6 -- A COMMENT LIVE IN THE DATABASE CLAIMED A GAP WAS CLOSED THAT IS NOT.
--   See the comment at the de-duplication window.
--
-- G3 -- `membership_pauses_reason_chk` is `reason <> ''`, which accepts three
--   spaces. ADR-062 fixed that shape twice and named the remaining instances;
--   this is one it did not list.
--
-- `security invoker` throughout, and for ADR-066's reason: every role that may
-- write a pause already reads `organization_settings` and `staff` under
-- `is_staff()`, so elevation would buy nothing and cost the isolation.


-- ---------------------------------------------------------------------------
-- 1. What a visit MEANT is written once
--
--    Reads nothing -- it compares OLD against NEW and nothing else -- so it has
--    no RLS interaction to get wrong and no reason to be anything but invoker.
--
--    The carve-out is `current_user <> 'authenticated'`, and it is load-bearing
--    for one reason worth naming: `supabase/seed.sql` records attendance with
--    `insert … on conflict (id) do update` to stay re-runnable, which is an
--    UPDATE. It runs as `postgres`.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_attendance_written_once()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  -- `row_security_active`, not `current_user <> 'authenticated'`: the question
  -- is "does any policy apply to this session", and that is what this function
  -- answers -- false for the table owner and for any `BYPASSRLS` role, true for
  -- an ordinary signed-in one -- without naming a role, which would be a second
  -- copy of a fact `pg_roles` already holds. See the pause trigger below for
  -- how this was found.
  if not pg_catalog.row_security_active('public.attendance') then
    return new;
  end if;

  if new.member_id            is distinct from old.member_id
  or new.branch_id            is distinct from old.branch_id
  or new.membership_id        is distinct from old.membership_id
  or new.checked_in_at        is distinct from old.checked_in_at
  or new.source               is distinct from old.source
  or new.qr_session_id        is distinct from old.qr_session_id
  or new.assisted_by_staff_id is distinct from old.assisted_by_staff_id
  or new.assist_reason        is distinct from old.assist_reason
  or new.client_event_id      is distinct from old.client_event_id then
    raise exception 'attendance refused: a recorded visit is corrected in attendance_corrections, never rewritten'
      using errcode = 'GL017';
  end if;

  return new;
end;
$fn$;

drop trigger if exists attendance_written_once on public.attendance;

create trigger attendance_written_once
  before update on public.attendance
  for each row execute function app.enforce_attendance_written_once();


-- ---------------------------------------------------------------------------
-- 2. A reason of three spaces is not a reason (ADR-062, third instance)
-- ---------------------------------------------------------------------------

alter table public.membership_pauses
  drop constraint if exists membership_pauses_reason_chk;

alter table public.membership_pauses
  add constraint membership_pauses_reason_chk
  check (reason is null or reason !~ '^\s*$');


-- ---------------------------------------------------------------------------
-- 3. The pause decision
-- ---------------------------------------------------------------------------

create or replace function app.enforce_pause_decision()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor_staff_id uuid;
  v_actor_role     public.app_role;
  v_required_role  public.app_role;
  v_was_decided    boolean := false;
  v_touches_decision boolean;
begin
  -- The trusted-context carve-out, stated as what it means rather than as a
  -- symptom of it. `postgres` (the seed, every pgTAP fixture) and `service_role`
  -- bypass row security by design; they are not `authenticated` sessions and no
  -- policy applies to them, so a rule here would break every fixture without
  -- protecting anything a policy is not already protecting.
  --
  -- The old test was `app.current_staff_id() is null`, which is a different set:
  -- it also contained every `authenticated` session whose token carries no
  -- `staff_id` claim -- an impersonating platform admin, most of all.
  -- **The predicate is the session, and it is asked as a question about row
  -- security rather than about a role name.** The blind holdout author found
  -- why that matters, and found it by accident: two assertions about the
  -- trusted-context carve-out were green, then went red when an *unrelated,
  -- earlier* claim block changed. The old carve-out tested
  -- `app.current_staff_id() is null` -- a fact about the CLAIM -- so `postgres`
  -- and `service_role` fell outside it whenever `request.jwt.claims` happened
  -- to be populated. Two live consequences: PostgREST populates that GUC on
  -- every request including a `service_role` one, so an Edge Function writing a
  -- decided pause would fail in production; and every pgTAP file here sets
  -- claims to act as a gym user and returns to `postgres` without clearing
  -- them, so the next fixture write is judged against a stale identity. It
  -- fails closed, which is why nobody had seen it -- as a `GL020` naming a
  -- staff member who has nothing to do with the write.
  --
  -- `row_security_active()` is the only predicate that means what the
  -- requirement's words mean: false for the table owner and for any `BYPASSRLS`
  -- role, true for an ordinary signed-in session, and it names no role at all.
  if not pg_catalog.row_security_active('public.membership_pauses') then
    return new;
  end if;

  v_actor_staff_id := app.current_staff_id();

  if tg_op = 'UPDATE' then
    v_was_decided := old.approved_at is not null or old.rejected_at is not null;
    v_touches_decision :=
         new.approved_at          is distinct from old.approved_at
      or new.approved_by_staff_id is distinct from old.approved_by_staff_id
      or new.rejected_at          is distinct from old.rejected_at;
  else
    v_touches_decision := new.approved_at is not null or new.rejected_at is not null;
  end if;

  -- An `authenticated` session with no staff identity. It may hold `gym_owner`
  -- in its `app_role` claim and pass `is_front_office()` -- an impersonation
  -- token does exactly that -- but there is nobody to record as the decider and
  -- nobody the two-person rule can be applied to.
  if v_actor_staff_id is null and v_touches_decision then
    raise exception 'pause decision refused: this session carries no staff identity, so there is nobody to record as the decider'
      using errcode = 'GL025';
  end if;

  -- The requester is a recorded fact from the moment the row exists. Without
  -- this the two-person rule below is decoration: the writer could satisfy it by
  -- rewriting the other half in the same statement.
  if tg_op = 'UPDATE'
     and new.requested_by_staff_id is distinct from old.requested_by_staff_id then
    raise exception 'pause decision refused: the staff member who requested a pause is recorded once and cannot be changed'
      using errcode = 'GL026';
  end if;

  -- A pause arrives pending or it does not arrive. On an insert every column is
  -- the caller's own input in one statement, so no rule below can mean anything
  -- there; the answer is that this state has no legitimate way to arise, not a
  -- more careful evaluation of rules that cannot apply.
  if tg_op = 'INSERT' and new.approved_at is not null then
    raise exception 'pause decision refused: a pause is requested and then decided, and cannot be created already approved'
      using errcode = 'GL027';
  end if;

  -- A decision already made is not re-openable, and "the decision" is not only
  -- the three columns that record who decided. **An authorisation is an
  -- authorisation of something.** The blind holdout author found this: freezing
  -- the decision columns alone left an approved pause repointable at another
  -- member's membership, and its `ends_on` extendable, so the freeze the gym is
  -- bound by need not be the freeze anybody approved. Moving what an
  -- authorisation covers forges it as surely as rewriting who gave it, and it
  -- does so without touching a single column the old guard was watching.
  --
  -- So after a decision the row is settled: the only thing that may still move
  -- is `updated_at`, which a separate trigger stamps. `tenant_id` is not in the
  -- list on purpose — `membership_pauses_tenant_write`'s `with check` refuses
  -- moving a row to another gym, and raising here first would answer ahead of
  -- the policy (ADR-066).
  --
  -- Refused rather than ignored: silently discarding the columns would tell the
  -- caller their approval was recorded when the row still says something else.
  if v_was_decided then
    if v_touches_decision
    or new.membership_id is distinct from old.membership_id
    or new.starts_on     is distinct from old.starts_on
    or new.ends_on       is distinct from old.ends_on
    or new.reason        is distinct from old.reason then
      raise exception 'pause decision refused: this pause was already decided, and neither the decision nor what it covers can be rewritten'
        using errcode = 'GL024';
    end if;
    return new;
  end if;

  -- Only recording an approval is governed. A rejection needs no configured role
  -- and no second person -- refusing a freeze is not the commercial act granting
  -- one is -- and every other column is already governed by the write policy.
  if new.approved_at is null then
    return new;
  end if;

  if new.approved_by_staff_id is distinct from v_actor_staff_id then
    raise exception 'pause approval refused: the approver recorded (%) is not the acting staff member (%)',
      new.approved_by_staff_id, v_actor_staff_id
      using errcode = 'GL020';
  end if;

  -- `old.` and not `new.`, which is the whole of D1. The requester is immutable
  -- three checks above, so the two are equal on any statement that gets here --
  -- but writing `old.` is what makes this a comparison against a recorded fact
  -- rather than a comparison that happens to be safe because of a rule somewhere
  -- else in the same function. Only reachable on UPDATE: an INSERT carrying an
  -- approval was refused above.
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
$fn$;


-- ---------------------------------------------------------------------------
-- 4. The check-in trigger: ATT-005 attribution, and a comment that lied
-- ---------------------------------------------------------------------------

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
