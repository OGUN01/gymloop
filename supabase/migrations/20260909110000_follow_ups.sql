-- follow_ups
--
-- Phase 4's second half: what a human did about a case. A case opened and never
-- worked is worth nothing; a case worked twice by two people is worse than one
-- worked by nobody, because the member is who notices.
--
-- Four rules, and the first is the third appearance of one rule this codebase
-- already states twice.
--
-- 1. `staff_id` IS THE ACTING STAFF MEMBER. `attendance.assisted_by_staff_id`
--    (`GL016`) and `membership_pauses.requested_by_staff_id` (`GL026`) are the
--    other two, and they should look alike, because they are one rule about
--    attribution appearing three times. **The null actor is named as its own
--    clause, not left to the comparison** -- `null is distinct from null` is
--    false, which is how ADR-071 happened, one round after ADR-070 named that
--    shape. Written correctly the first time here only because it has now cost
--    two rounds elsewhere.
--
-- 2. A CORRECTION STAYS ON ITS OWN CASE. ADR-052's composite key already stops
--    `corrects_follow_up_id` crossing a tenant; nothing stopped it crossing a
--    *case*, so one case's history could be rewritten by an entry filed against
--    another. Both cases then read wrongly and neither looks wrong.
--
-- 3. TWO STAFF CANNOT CONTACT ONE CASE AT THE SAME INSTANT (NSH-006). An
--    advisory lock on the case, exactly as `app.enforce_check_in()` locks
--    (tenant, member) -- a read-then-write has the race Phase 3 spent a day
--    removing, because both reads pass before either writes.
--
--    **"Already being contacted" is defined as "landed after my transaction
--    began", and that is the honest reading of the requirement.** The spec is
--    explicit that a second follow-up an hour later must succeed: the rule is
--    about concurrency, not about a case being contacted once. So a fixed time
--    window would be the wrong mechanism -- it would refuse legitimate work at
--    59 minutes and permit a genuine double-call at 61.
--
-- 4. THE CASE'S STATUS FOLLOWS ITS CONTACT HISTORY, and is not writable as an
--    input. A caller who can set `contacted` directly can mark a case contacted
--    without contacting anybody, which is the one thing the red list must never
--    show.
--
-- Assignment needed nothing: ADR-052's `(tenant_id, assigned_to_staff_id)`
-- composite foreign key already refuses a staff member of another gym. The
-- blind suite author checked the catalogue rather than assuming a rule was
-- missing, and four of its assertions were green before this file existed.
--
-- `after insert`, by ADR-072's rule: none of this modifies the `follow_ups`
-- row, so none of it needs to run before the write -- and running before would
-- adjudicate rows row security was about to refuse. `security invoker`,
-- justified against what callers hold (ADR-066) and measured: `follow_ups`
-- write and `no_show_cases` write are both `is_staff()`, so every session that
-- can log a follow-up can already move the case, and elevation would buy
-- nothing.

create or replace function app.enforce_follow_up()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor      uuid;
  v_status     public.no_show_case_status;
begin
  -- The trusted-context carve-out, stated as the property it means rather than
  -- as a symptom that correlates with it (ADR-068): `row_security_active()` is
  -- false exactly for sessions no policy applies to -- the table owner and any
  -- `BYPASSRLS` role -- and names no role at all.
  if not pg_catalog.row_security_active('public.follow_ups') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  -- Two conditions, and the first is not redundant. A session inside row
  -- security with no `staff_id` claim -- an impersonating platform admin, a
  -- plain `super_admin` -- has nobody to record, and `new.staff_id is distinct
  -- from null` is FALSE when the caller also supplied nothing, so the
  -- comparison alone is silent exactly there.
  if v_actor is null
     or new.staff_id is distinct from v_actor then
    raise exception 'follow-up refused: a contact is logged by the staff member making it, and this session records % against an actor of %',
      new.staff_id, coalesce(v_actor::text, 'no staff identity')
      using errcode = 'GL030';
  end if;

  -- **`try` rather than `wait`, and that one word is the whole of NSH-006.**
  --
  -- `pg_try_advisory_xact_lock` returns false when ANOTHER session holds this
  -- case's lock right now — which is precisely, and without any arithmetic
  -- about time, "somebody else is contacting this member". A waiting lock would
  -- serialise the two callers and then let both write, which is the outcome the
  -- requirement exists to prevent.
  --
  -- It is re-entrant within a session, so a caller logging two follow-ups in one
  -- transaction is not fighting itself, and a pgTAP file — which runs everything
  -- in one transaction — sees no phantom contention.
  --
  -- The first attempt at this compared `created_at >= transaction_timestamp()`
  -- to spot a row that landed mid-flight. It is wrong twice over: `now()` IS the
  -- transaction start, so every row written earlier in the same transaction
  -- reads as concurrent, and the blind suite's own fixtures tripped it. **A rule
  -- about concurrency cannot be built out of timestamps that are equal by
  -- construction.** Asking the lock manager who holds the lock asks the
  -- question directly.
  --
  -- Taken after attribution rather than before it: a caller who cannot say who
  -- they are has no business holding a lock on somebody else's case.
  if not pg_catalog.pg_try_advisory_xact_lock(
       ('x' || pg_catalog.substr(
          pg_catalog.md5(new.tenant_id::text || ':' || new.case_id::text), 1, 16))::bit(64)::bigint
     ) then
    raise exception 'follow-up refused: somebody else is contacting this member right now — check what they logged before calling'
      using errcode = 'GL032';
  end if;

  select c.status into v_status
    from public.no_show_cases c
   where c.id = new.case_id
     and c.tenant_id = new.tenant_id;

  -- No row is a case this session may not read, or one in another gym. Left to
  -- the foreign key and the policy to answer rather than raising here, which
  -- would say something about a case the caller cannot see (ADR-066).
  if v_status is null then
    return null;
  end if;

  if v_status in ('returned'::public.no_show_case_status,
                  'closed'::public.no_show_case_status) then
    raise exception 'follow-up refused: this case is closed — the member came back, and a closed case is a finished record'
      using errcode = 'GL031';
  end if;

  -- A correction names an entry on the same case. ADR-052's composite key
  -- already stops it crossing a tenant; nothing stopped it crossing a case.
  if new.corrects_follow_up_id is not null
     and not exists (
       select 1
         from public.follow_ups f
        where f.id = new.corrects_follow_up_id
          and f.tenant_id = new.tenant_id
          and f.case_id = new.case_id
     ) then
    raise exception 'follow-up refused: a correction names an entry on this case, and % is not one',
      new.corrects_follow_up_id
      using errcode = 'GL033';
  end if;

  -- The status is derived from what happened. `next_follow_up_at` is what makes
  -- a case due rather than merely contacted, so it decides, and the case
  -- carries the instant so the red list can order by it without joining.
  update public.no_show_cases c
     set status = case
                    when new.next_follow_up_at is null
                      then 'contacted'::public.no_show_case_status
                    else 'follow_up_due'::public.no_show_case_status
                  end,
         contacted_at      = -- `coalesce` is a SQL construct, not a function in `pg_catalog`, so it
         -- cannot be schema-qualified — qualifying it is a 42883 at runtime, not
         -- a parse error, which is why it reached a test run rather than a
         -- migration failure. It is safe unqualified under `search_path = ''`
         -- for the same reason it cannot be qualified: the parser owns it.
         coalesce(c.contacted_at, new.created_at),
         next_follow_up_at = new.next_follow_up_at
   where c.id = new.case_id
     and c.tenant_id = new.tenant_id;

  return null;
end;
$fn$;

drop trigger if exists follow_ups_enforce on public.follow_ups;

create trigger follow_ups_enforce
  after insert on public.follow_ups
  for each row execute function app.enforce_follow_up();
