-- no_show_scan
--
-- Phase 4's first half: noticing that a member has stopped coming, before they
-- decide they have left. Phase 3 records attendance; nothing yet reads the
-- absence of it, and that absence is the product.
--
-- IN THE DATABASE, NOT IN THE JOB, and the reason is the same one every rule in
-- this product has: `no_show_cases` grants `insert` to `authenticated`, so a
-- scan living only in an Edge Function is a scan with a way round it, and
-- "exactly one open case per member" would be a property of the job rather than
-- of the table. The cron function is a caller: it picks the gyms and invokes
-- this per gym. Nothing about the correctness of a scan depends on it running.
--
-- `security invoker`, and it is load-bearing rather than tidy. `p_tenant_id` is
-- **a tenant id arriving from a caller**, which is the shape this codebase
-- refuses everywhere else -- and under invoker it cannot become one: an
-- ordinary staff session passing another gym's id reads zero members, zero
-- attendance and zero settings through that gym's policies, so it opens
-- nothing. Under `definer` the same parameter would be a cross-tenant weapon
-- and a `before`-style oracle (ADR-066). The trusted caller -- the cron
-- function running as `service_role` -- bypasses RLS anyway, so elevation would
-- buy nothing and cost exactly that.
--
-- Every failure here is silent: a case never opened looks precisely like a
-- member who is fine, which is why this half gets the full blind arrangement
-- (ADR-059) and why the paragraphs below are longer than the code.

create or replace function app.run_no_show_scan(p_tenant_id uuid, p_today date default null)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_today     date;
  v_threshold integer;
  v_timezone  text;
  v_opened    integer;
begin
  -- The gym's own calendar day, from the gym's own timezone (NSH-001, MNY-004).
  -- `p_today` exists so a test can put a gym at a chosen day; production passes
  -- null and takes this path.
  select o.timezone,
         coalesce(p_today, (pg_catalog.now() at time zone o.timezone)::date),
         s.no_show_threshold_days
    into v_timezone, v_today, v_threshold
    from public.organizations o
    join public.organization_settings s on s.tenant_id = o.id
   where o.id = p_tenant_id;

  -- Nothing found means one of two things and **this function cannot tell them
  -- apart, by design**: a gym with no `organization_settings` row (OPEN-018),
  -- or a gym this session may not read. Under invoker both come back as no row.
  --
  -- So it returns 0 rather than raising, for the reason
  -- `app.enforce_check_in()` reaches the same conclusion: raising here would
  -- answer a question about another tenant. A gym with no configured threshold
  -- gets no scan -- it does NOT fall back to the column's default, because a
  -- default reached at this distance is a second copy of a number the settings
  -- row is supposed to own, and it would apply exactly when the real one failed
  -- to load.
  if v_today is null or v_threshold is null then
    return 0;
  end if;

  with live as (
    -- **`active` OR `frozen`, and the `frozen` is the whole of ADR-064.**
    --
    -- The first version of this read `active` only, which looks like a tighter
    -- filter and is actually a second source of truth: it decides pause state
    -- from a status column. Nothing in this product sets
    -- `memberships.status = 'frozen'` -- approving a pause stamps
    -- `membership_pauses.approved_at` and touches no status -- so a row that
    -- says `frozen` is a row that lies, and the effect of believing it is that
    -- the member is silently never evaluated again. A member who has genuinely
    -- gone quiet, wearing a status nothing maintains, is exactly the member
    -- this scan exists to find.
    --
    -- So the live set is "not finished": `expired`, `cancelled` and `pending`
    -- are out -- they have not gone quiet, they have gone, or not arrived --
    -- and being paused is asked of `membership_pauses` below, where the answer
    -- actually is. The same reading `app.enforce_check_in()` already takes.
    --
    -- Found by the blind holdout author, whose fixture wore
    -- `members.status = 'paused'` and `memberships.status = 'frozen'` with no
    -- pause row behind either. The visible suite tested `expired`, `cancelled`
    -- and `pending` and was green; this case is the one a careful reading of
    -- NSH-002 walks straight into, because NSH-002 lists `frozen` and ADR-064
    -- says the list is wrong.
    select m.member_id, min(m.starts_on) as started_on
      from public.memberships m
     where m.tenant_id = p_tenant_id
       and m.status in ('active'::public.membership_status,
                        'frozen'::public.membership_status)
     group by m.member_id
  ),
  last_visit as (
    -- Collapsed to the GYM's calendar day before any comparison. A visit at
    -- 23:55 local is that day's visit, and comparing a `timestamptz` against a
    -- `date` would silently resolve it in UTC and move it.
    select a.member_id,
           max((a.checked_in_at at time zone v_timezone)::date) as last_on
      from public.attendance a
     where a.tenant_id = p_tenant_id
     group by a.member_id
  ),
  candidate as (
    select l.member_id,
           v.last_on,
           -- Never having visited is measured from the day the membership
           -- began. Excluding these for want of a row to measure from would
           -- silently skip the members most likely to have left -- the ones who
           -- joined and never came once.
           (v_today - coalesce(v.last_on, l.started_on)) as absent_days
      from live l
      left join last_visit v on v.member_id = l.member_id
     where l.started_on is not null
  )
  insert into public.no_show_cases (
    tenant_id, member_id, status, opened_on,
    last_attended_on, absent_days_at_open, threshold_days
  )
  select p_tenant_id, c.member_id, 'open'::public.no_show_case_status, v_today,
         c.last_on, c.absent_days, v_threshold
    from candidate c
   where c.absent_days > v_threshold
     -- **Paused is derived, never read from a status column** (ADR-064).
     -- Nothing sets `memberships.status = 'frozen'`, so a scan asking the
     -- status column would flag every paused member -- and the demo data holds
     -- one, 30 days absent with an approved pause covering today, waiting to
     -- prove it. Inclusive at both ends: a pause that starts today is a pause.
     and not exists (
       select 1
         from public.membership_pauses p
         join public.memberships mm on mm.id = p.membership_id
        where p.tenant_id = p_tenant_id
          and mm.member_id = c.member_id
          and p.approved_at is not null
          and p.rejected_at is null
          and v_today between p.starts_on and p.ends_on
     )
  -- The index does the de-duplication, not a preceding read. Two scans running
  -- at once both reach this insert; `no_show_cases_tenant_id_member_id_open_key`
  -- is what makes exactly one row survive, and it has no window. A
  -- read-then-write has the race Phase 3 spent a day removing from check-in,
  -- and `app.enforce_check_in()` is the worked example of the alternative.
  --
  -- The partial predicate is repeated verbatim so Postgres can infer that
  -- index; a case that is `returned` or `closed` is not a live case, and a
  -- member who lapses again after coming back gets a new one, which is right.
  on conflict (tenant_id, member_id)
    where status in ('open'::public.no_show_case_status,
                     'contacted'::public.no_show_case_status,
                     'follow_up_due'::public.no_show_case_status)
    do nothing;

  get diagnostics v_opened = row_count;

  -- The count is of rows that actually landed, so a second run reports 0 and a
  -- scan that lost every race reports 0. Reporting intent rather than outcome
  -- would make a duplicate-suppressing scan look like a working one.
  return v_opened;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- NSH-005: a returning member closes their own case
--
--    The other half of the loop, and the half that makes the product's claim
--    true: "bring the member back" is only observable if coming back is
--    recorded as such. A case that stays open after the member returns puts
--    them on tomorrow's red list, and somebody rings a member who is standing
--    in the gym.
--
--    **`after insert`, and by ADR-072's rule rather than by habit**: this does
--    not modify the attendance row, it acts on another table, so it has no
--    reason to run before the write — and running before would mean closing a
--    case for a visit row security was about to refuse.
--
--    `security invoker`, justified against what the caller already holds
--    (ADR-066) and measured before relying on it: `attendance_tenant_write` is
--    `is_front_office()`, `no_show_cases_tenant_write` is `is_staff()`, and
--    front office is a subset of staff. So every session that can record a
--    visit can already close a case, and elevation would buy nothing while
--    costing the isolation. `postgres` and `service_role` bypass RLS either
--    way, so the seed and the fixtures are unaffected.
--
--    **The follow-up history is preserved rather than deleted** (NSH-005). The
--    recovery is the product's only evidence that the loop worked -- a case
--    opened, somebody rang, the member came back -- and a delete destroys
--    exactly the row that proves it. `follow_ups.case_id` keeps pointing at a
--    closed case, which is the point.
-- ---------------------------------------------------------------------------

create or replace function app.close_no_show_case_on_return()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  -- Both timestamps, one statement. The spec says the case transitions to
  -- `returned` and then `closed`; nothing can observe an intermediate state
  -- inside one statement, so what is recorded is the pair of facts -- when they
  -- came back, and when the case stopped being work -- rather than a state the
  -- row passes through unobservably.
  update public.no_show_cases c
     set status      = 'closed'::public.no_show_case_status,
         returned_at = new.checked_in_at,
         closed_at   = pg_catalog.now()
   where c.tenant_id = new.tenant_id
     and c.member_id = new.member_id
     -- The live set, matching `no_show_cases_tenant_id_member_id_open_key`
     -- exactly. A case already `returned` or `closed` is a finished record and
     -- re-closing it would move `closed_at` every time the member visits.
     and c.status in ('open'::public.no_show_case_status,
                      'contacted'::public.no_show_case_status,
                      'follow_up_due'::public.no_show_case_status);

  -- A member with no open case is the overwhelmingly common path: zero rows,
  -- nothing said. Returning `null` because an `after` trigger's return value is
  -- discarded, and pretending otherwise invites somebody to read meaning into it.
  return null;
end;
$fn$;

drop trigger if exists attendance_close_no_show_case on public.attendance;

create trigger attendance_close_no_show_case
  after insert on public.attendance
  for each row execute function app.close_no_show_case_on_return();
