-- a_frozen_column_list_goes_stale
--
-- The Phase 3 critic's second NO-GO. It verified every fix from the first one
-- is real in the database, then found five more -- three of them created by
-- those fixes, which is now the third round running that this has been true.
--
-- D1 (CRITICAL) -- SEPARATION OF DUTIES WAS STILL DEFEATABLE, IN TWO
--   STATEMENTS. `20260908170000` made `requested_by_staff_id` immutable on
--   UPDATE, and that put it outside the writer's reach only once the row
--   existed. INSERT is where it enters, and there it was still whatever the
--   caller typed -- or null, the column being nullable. So: insert a pause
--   naming a colleague as requester, approve it in the next statement. The
--   two-person comparison passes, the freeze is granted, the gym stops
--   collecting, and the permanent record names an employee who never asked.
--
--   ADR-068's own sentence is what this violates: *a rule of the form "A must
--   differ from B" is a control only if at least one of A and B is outside the
--   writer's reach in that statement.* The fix made it outside reach on the
--   statement that changes it and left it inside reach on the statement that
--   sets it. The requester is now stamped from the session at INSERT, exactly
--   as `GL016` already does for `assisted_by_staff_id` on `attendance` -- the
--   answer was in the same migration, one function away.
--
-- D2/D3 -- A FROZEN-COLUMN LIST GOES STALE, AND BOTH OF MINE ALREADY HAD.
--   `attendance` named nine columns and left four writable: `id` (the identity
--   the check-in response hands back and `attendance_corrections` points at),
--   `created_at`, and `offline_recorded_at`/`replayed_at`, Phase 7's offline
--   provenance, forgeable onto a row that was never offline. `membership_pauses`
--   named seven and left `id` and `created_at`, so a decided pause could be
--   renumbered and become unfindable at the id anything else was holding.
--
--   Both were stale on the day they were written, which is the point: a
--   denylist of frozen columns has to be revisited every time the table grows,
--   by someone who remembers it exists. Comparing the rows as **jsonb minus an
--   allowlist** inverts the default -- a column added tomorrow is frozen unless
--   the migration that adds it says otherwise.
--
-- D6 -- AND THE STATEMENT THAT DOES THE DECIDING WAS GOVERNED BY NOTHING.
--   Found by the blind holdout author after everything above was written, by
--   asking the question that had already produced D1: what do two things in one
--   statement buy that one does not? An approver set `approved_at` AND moved
--   `ends_on` in the same UPDATE. Every rule held -- right role, not the
--   requester, row pending when the statement began -- because the settled
--   guard reads `old` and the row was not yet decided when it looked. A
--   seven-day freeze was granted as a two-year one, and the record reads as a
--   properly authorised freeze that nobody requested in that form.
--
--   The shape, third time in this capability: **the rules were attached to the
--   states, and the transition between them is a place a rule can be left out
--   of.** A decision may decide; it may not also change what is being decided.
--
-- D4 -- A PAUSE COULD BE BORN REJECTED. The insert guard named `approved_at`
--   only, while the comment above it stated the general rule. The row lands
--   already decided, the settled guard freezes it, and a refusal is permanently
--   recorded against a request nobody made.
--
-- Two comments are corrected here as well, because a comment that states
-- something the code does not do is the failure this project has now paid for
-- three times:
--
--   * `20260908170000`'s section-1 header says the carve-out is
--     `current_user <> 'authenticated'`. It is not -- the code twelve lines
--     below it uses `row_security_active()`, and ADR-068 records
--     `current_user <> 'authenticated'` as **the wrong answer**. The rejected
--     draft's description survived as the description of the shipped one.
--     That file is applied and forward-only, so the correction lives here.
--   * `packages/shared/src/api/memberships.ts` said the table refuses to let
--     `requested_by_staff_id` change "afterwards, which is what makes the
--     two-person rule a control rather than decoration". True of UPDATE, false
--     of INSERT, and it is the sentence a reader would have trusted instead of
--     re-deriving D1. Corrected in that file.
--
-- `security invoker` throughout, and the carve-out is `row_security_active()`
-- on the table in question -- "does any policy apply to this session", false
-- for the owner and for `BYPASSRLS` roles, naming no role at all.


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

  -- **The allowlist, not a list of frozen columns.** The first version of this
  -- named nine columns and a blind critic found the four it did not: `id` (the
  -- identity `POST /api/check-in` hands back and `attendance_corrections`
  -- points at, so a visit could be renumbered out from under anything holding
  -- it), `created_at` (the row's only audit timestamp), and
  -- `offline_recorded_at` / `replayed_at` (Phase 7's offline provenance,
  -- stampable onto a row that was never offline). It was stale on the day it
  -- was written, which is what a denylist does.
  --
  -- Comparing the rows as jsonb inverts it: a column added tomorrow is frozen
  -- by default, and the only way to make one writable is to name it here,
  -- deliberately, in the migration that adds it.
  --
  -- `checked_out_at` is what may still move -- a check-out is a later fact
  -- about a visit that happened, not a rewrite of it. `tenant_id` is subtracted
  -- from BOTH sides rather than permitted: `attendance_tenant_write`'s `with
  -- check` already refuses moving a row to another gym, and raising here would
  -- answer ahead of the policy (ADR-066).
  if pg_catalog.to_jsonb(new) - 'checked_out_at' - 'tenant_id'
     is distinct from
     pg_catalog.to_jsonb(old) - 'checked_out_at' - 'tenant_id' then
    raise exception 'attendance refused: a recorded visit is corrected in attendance_corrections, never rewritten'
      using errcode = 'GL017';
  end if;

  return new;
end;
$fn$;


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
  --
  -- `rejected_at` as well as `approved_at`, because the first version named
  -- only approval and half a rule is not the rule. A born-rejected row moves no
  -- money, so it reads as harmless -- but it lands already decided, the settled
  -- guard below then freezes it, and a front-office session has permanently
  -- recorded a refusal against a request nobody made.
  if tg_op = 'INSERT'
     and (new.approved_at is not null or new.rejected_at is not null) then
    raise exception 'pause decision refused: a pause is requested and then decided, and cannot be created already approved or rejected'
      using errcode = 'GL027';
  end if;

  -- **The requester is stamped from the session, not merely frozen after it.**
  -- Immutability on UPDATE put this column outside the writer's reach only once
  -- the row existed -- and INSERT is where it enters. So a manager inserted a
  -- pause naming a colleague (or naming nobody: the column is nullable) and
  -- approved it in the next statement. The comparison below passed, the freeze
  -- was granted, and the record named an employee who never asked. Two
  -- statements instead of one, by one person, with no rule crossed.
  --
  -- ADR-068's own sentence, applied where it was needed: a rule of the form
  -- "A must differ from B" is a control only if one of A and B is outside the
  -- writer's reach IN THAT STATEMENT. Refused rather than corrected, exactly as
  -- `GL016` refuses a supplied `assisted_by_staff_id`; a null actor is refused
  -- too, which also closes an impersonating session forging a request.
  if tg_op = 'INSERT'
     and new.requested_by_staff_id is distinct from v_actor_staff_id then
    raise exception 'pause request refused: the requester recorded (%) is not the acting staff member (%)',
      new.requested_by_staff_id, v_actor_staff_id
      using errcode = 'GL026';
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
    -- Every column, not a list of them -- the same inversion as `attendance`
    -- above, and for the same reason: the list that named seven omitted `id`
    -- (so a decided pause could be renumbered and become unfindable at the id
    -- anything else held) and `created_at` (its only record of when it was
    -- asked for). `updated_at` is what may still move; `tenant_id` is
    -- subtracted from both sides so the policy answers it, not this trigger.
    if pg_catalog.to_jsonb(new) - 'updated_at' - 'tenant_id'
       is distinct from
       pg_catalog.to_jsonb(old) - 'updated_at' - 'tenant_id' then
      raise exception 'pause decision refused: this pause was already decided, and neither the decision nor what it covers can be rewritten'
        using errcode = 'GL024';
    end if;
    return new;
  end if;

  -- **The transition itself, which nothing governed.** Everything above
  -- governs the row before a decision and after one; a guard that reads `old`
  -- to ask "was this already decided?" is blind to the statement doing the
  -- deciding. So an approver approved and moved `ends_on` in one statement --
  -- a seven-day freeze granted as a two-year one -- and every rule held: right
  -- role, not the requester, row pending when the statement began. The record
  -- then reads as a properly authorised freeze that nobody requested and
  -- nobody approved in that form.
  --
  -- Third appearance of one shape here: the rules were attached to the STATES,
  -- and the transition between them is a place a rule can be left out of. The
  -- approver's authority is to grant the request that was made, not to alter it
  -- and grant that instead -- a granter who can rewrite what they are granting
  -- makes the requester's half of the two-person rule decorative.
  --
  -- Found by the blind holdout author, probing "what can two things in one
  -- statement buy that one cannot" after exactly that question had already
  -- produced the insert-then-approve defect.
  if tg_op = 'UPDATE' and (new.approved_at is not null or new.rejected_at is not null) then
    if pg_catalog.to_jsonb(new) - 'approved_at' - 'approved_by_staff_id' - 'rejected_at' - 'updated_at' - 'tenant_id'
       is distinct from
       pg_catalog.to_jsonb(old) - 'approved_at' - 'approved_by_staff_id' - 'rejected_at' - 'updated_at' - 'tenant_id' then
      raise exception 'pause decision refused: a decision may decide, and may not also change what is being decided'
        using errcode = 'GL028';
    end if;
  end if;

  -- Only recording an approval is governed further. A rejection needs no
  -- configured role and no second person -- refusing a freeze is not the
  -- commercial act granting one is.
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
