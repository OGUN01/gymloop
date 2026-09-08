-- a_rule_that_reads_a_nullable_column
--
-- The Phase 3 critic's third NO-GO. Two defects, both introduced by the
-- migration that closed the second one, and both the same mistake in different
-- clothes:
--
--     A RULE THAT READS A NULLABLE COLUMN IS NOT A RULE UNTIL THE NULL CASE
--     IS WRITTEN DOWN.
--
-- F1 -- A PAUSE COULD STILL BE CREATED WITH NO REQUESTER, BY THE ONE SESSION
--   THE SPEC SINGLES OUT. `20260908190000` stamped the requester at INSERT with
--   `new.requested_by_staff_id is distinct from v_actor_staff_id` -- and
--   `null is distinct from null` is false, so a session with no `staff_id`
--   claim sailed through. That is exactly the shape the access-token hook mints
--   for a live impersonation: `gym_owner`, a tenant, no staff id. A gym manager
--   then approves the row in good faith and the two-person rule is satisfied
--   against NULL, `GL021` being `<uuid> is not distinct from null`, also false.
--   Fixed by naming the null case, not by adjusting the comparison.
--
--   The migration that shipped that guard said in its own comment: "a null
--   actor is refused too, which also closes an impersonating session forging a
--   request." It did not. **Fourth false comment of this phase**, and ADR-070
--   had named that failure mode one round earlier -- which is the argument for
--   why a comment claiming a gap is closed has to be verified like code.
--
-- F2 -- A REJECTION COULD STAMP A FALSE APPROVER, PERMANENTLY. Every rule that
--   governs `approved_by_staff_id` sits below `if new.approved_at is null then
--   return new;`, so while there is no approval the column is ungoverned: a
--   front-desk member of staff rejected their own request and named a manager
--   as its approver in the same statement. The settled guard then froze the
--   row, so the false attribution cannot be corrected -- three attempts, three
--   `GL024`s. The same forgery was reachable in two statements by writing the
--   column onto a pending row first.
--
--   Fixed with a CHECK rather than another trigger branch, deliberately. The
--   column and the timestamp are one fact; an invariant that holds for every
--   writer -- including `postgres` and `service_role`, which the trigger
--   exempts by design -- cannot be reached from a direction nobody enumerated.
--   This is the third round in which a rule attached to a branch was got round
--   by arriving somewhere the branch did not run.
--
-- The repair below is not hypothetical: **one row in the demo data already had
-- it.** `seed-scenarios.sql` named an approver on its rejected pause, so the
-- defect was sitting in our own fixtures while three critic rounds looked past
-- it. The seed is corrected in the same commit.


-- ---------------------------------------------------------------------------
-- 1. Repair, then constrain
--
--    Forward-only and idempotent: the update is a no-op on a database where
--    nothing is wrong, and the constraint validates the whole table on add, so
--    a row this misses fails the migration loudly rather than silently.
-- ---------------------------------------------------------------------------

update public.membership_pauses
   set approved_by_staff_id = null
 where approved_at is null
   and approved_by_staff_id is not null;

alter table public.membership_pauses
  drop constraint if exists membership_pauses_approver_pairs_with_approval_chk;

alter table public.membership_pauses
  add constraint membership_pauses_approver_pairs_with_approval_chk
  check ((approved_at is null) = (approved_by_staff_id is null));


-- ---------------------------------------------------------------------------
-- 2. The null actor
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
  -- `v_actor_staff_id is null` is named FIRST and separately, and that clause is
  -- the entire fix. The previous version was the comparison alone -- and
  -- `null is distinct from null` is FALSE, so for a session carrying no
  -- `staff_id` claim the raise never fired and a pause could be created with no
  -- requester at all. The `GL025` guard above does not cover it either: that one
  -- is gated on touching a decision column, and a pending insert touches none.
  --
  -- The session it let through is the one the spec singles out. The access-token
  -- hook mints `app_role = 'gym_owner'` and a `tenant_id` for a live
  -- impersonation and deliberately no `staff_id`, so `is_front_office()` admits
  -- the write; `super_admin` reaches the same insert through
  -- `membership_pauses_platform_write`. A manager then approves the row in good
  -- faith -- it looks pending and ordinary -- the gym stops collecting, and the
  -- two-person rule was satisfied against NULL, because `GL021` compares
  -- `<uuid> is not distinct from null`, which is also false.
  --
  -- **The general form, and it cost this capability two rounds: a rule that
  -- reads a nullable column is not a rule until the null case is written down.**
  -- The migration that introduced this guard claimed in its own comment that a
  -- null actor was refused. It was the fourth false comment of this phase and
  -- ADR-070 had named that failure mode one round earlier.
  if tg_op = 'INSERT'
     and (v_actor_staff_id is null
          or new.requested_by_staff_id is distinct from v_actor_staff_id) then
    raise exception 'pause request refused: a pause is asked for by the acting staff member, and this session records % against an actor of %',
      new.requested_by_staff_id, coalesce(v_actor_staff_id::text, 'no staff identity')
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
