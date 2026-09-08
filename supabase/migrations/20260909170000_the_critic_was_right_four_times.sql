-- the_critic_was_right_four_times
--
-- Phase 4's blind critic, NO-GO. Four database defects, and two of them are
-- this project's most reliable shape: a control that the migration's own
-- comment AND `docs/registry.md` both describe as present, which the database
-- says is absent. That is the fifth and sixth time this has happened here.
--
-- D1 -- `revoke all ... from public` DID NOT REVOKE ANYTHING. Supabase grants
--   EXECUTE to `anon` and `authenticated` explicitly, not through PUBLIC, so
--   revoking PUBLIC leaves both grants standing. The ACL said so the whole
--   time:
--
--     {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
--   Proved live over PostgREST: a front desk got 200 and opened seven real
--   cases; a **member** -- not staff at all -- got 200; a trainer got 200. Only
--   `anon` was stopped, and only because it lacks `usage` on schema `app`.
--
--   **Phase 2 got this right and Phase 4 copied the intent instead of the
--   statements.** `20260907184313` revokes `custom_access_token_hook` from
--   `public`, `anon` and `authenticated` by name, three statements. Written
--   here the same way now.
--
-- D2 -- THE VIEW USED `current_date`, WHICH ADR-039 FORBIDS IN THE MIGRATION
--   THAT CREATED THE COLUMN IT SUBTRACTS. Five lines from `opened_on`,
--   `20260906115156_retention.sql` says: never `current_date`, every Supabase
--   connection is UTC. Verified: `TimeZone = UTC` database-wide with no
--   `rolconfig` override on any role.
--
--   So `current_date` was a UTC date while `opened_on` is the gym's date,
--   stamped by the scan from `(now() at time zone o.timezone)::date`. Between
--   midnight and 05:30 IST the view read one day short -- **every morning, in
--   exactly the pre-6am window the red list exists for**. A case opened at
--   eight days against a seven-day threshold displayed "7 days away": a number
--   below the gym's own threshold, on a case that exists only because the
--   threshold was crossed.
--
-- D3 -- THE SCAN READ EXPIRY OFF A STATUS COLUMN NOTHING MAINTAINS. Three
--   paragraphs of this file already explain why asking `memberships.status`
--   about a *pause* is wrong (ADR-064). The identical argument applies to
--   expiry and was never made. `grep -rn "'expired'"` across migrations, apps
--   and packages returns only the enum's own definition: **nothing in this
--   product ever writes that label**, because a status flip needs a scheduler
--   ADR-064 says does not exist.
--
--   So a lapsed membership sits at `active` for ever, the scan opens a churn
--   case for it, and because the absence keeps growing that case climbs to the
--   TOP of the red list -- the first person the front desk is told to ring
--   every morning, about a membership that ended weeks ago. The demo data
--   already held one: `ends_on = 2026-09-05`, status `active`, flagged at 33
--   days absent.
--
-- D4 -- A CORRECTION CANCELLED THE CALLBACK IT WAS CORRECTING. The status
--   derivation did not distinguish a correction from a fresh contact, so
--   filing one -- the only way to fix anything on an append-only log -- moved
--   the case out of `follow_up_due` and nulled `next_follow_up_at`, dropping it
--   from the index built for "which follow-ups are due". Staff log "ring
--   Friday", correct a typo a minute later, and nobody rings on Friday.
--
-- G1 -- AND NOTHING RAN THE SCAN. The critic found no `pg_cron` job, no
--   schedule in `config.toml`, and no workflow deploying the Edge Function.
--   The loop was correct and reachable and never started. Scheduled here, in
--   the database, for the reasons at section 5.


-- ---------------------------------------------------------------------------
-- 1. The revoke that revokes
-- ---------------------------------------------------------------------------

revoke all on function public.run_no_show_scan_all() from public;
revoke all on function public.run_no_show_scan_all() from anon;
revoke all on function public.run_no_show_scan_all() from authenticated;
grant execute on function public.run_no_show_scan_all() to service_role;


-- ---------------------------------------------------------------------------
-- 2. The gym's day, not UTC's
-- ---------------------------------------------------------------------------

create or replace view public.red_list_cases
with (security_invoker = true) as
select
  c.id,
  c.tenant_id,
  c.member_id,
  c.status,
  c.opened_on,
  c.last_attended_on,
  c.absent_days_at_open,
  c.threshold_days,
  c.assigned_to_staff_id,
  c.contacted_at,
  c.next_follow_up_at,
  -- `now() at time zone o.timezone`, never `current_date` (ADR-039). The gym's
  -- own day is the only day this subtraction can be correct in, because
  -- `opened_on` was stamped in it.
  c.absent_days_at_open + ((pg_catalog.now() at time zone o.timezone)::date - c.opened_on)
    as days_absent,
  m.full_name as member_name,
  m.phone     as member_phone,
  lf.created_at as last_follow_up_at,
  lf.channel    as last_follow_up_channel,
  lf.outcome    as last_follow_up_outcome,
  lf.staff_name as last_follow_up_by
from public.no_show_cases c
join public.members m
  on m.id = c.member_id
 and m.tenant_id = c.tenant_id
-- Joined for its timezone alone. `organizations` is readable to any session
-- that can read a case in it, so this adds no reach.
join public.organizations o
  on o.id = c.tenant_id
left join lateral (
  select f.created_at, f.channel, f.outcome, s.full_name as staff_name
    from public.follow_ups f
    left join public.staff s
      on s.id = f.staff_id
     and s.tenant_id = f.tenant_id
   where f.case_id = c.id
     and f.tenant_id = c.tenant_id
   order by f.created_at desc
   limit 1
) lf on true
where c.status not in ('returned'::public.no_show_case_status,
                       'closed'::public.no_show_case_status);

grant select on public.red_list_cases to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Expiry is a date, not a label
-- ---------------------------------------------------------------------------

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
  select o.timezone,
         coalesce(p_today, (pg_catalog.now() at time zone o.timezone)::date),
         s.no_show_threshold_days
    into v_timezone, v_today, v_threshold
    from public.organizations o
    join public.organization_settings s on s.tenant_id = o.id
   where o.id = p_tenant_id;

  -- A gym with no settings row, or one this session may not read. Under invoker
  -- those are the same answer, so this returns 0 rather than raising: raising
  -- would answer a question about another tenant (ADR-066).
  if v_today is null or v_threshold is null then
    return 0;
  end if;

  with live as (
    -- **`ends_on` is checked, and that is the D3 fix.** `status` answers
    -- "active or frozen" and nothing else, because nothing in this product ever
    -- writes `expired` -- a status flip needs a scheduler ADR-064 says does not
    -- exist, so a lapsed membership reads `active` for ever. Asking the date is
    -- the same move ADR-064 already made for pauses, applied to the question
    -- three paragraphs of this function forgot to ask.
    --
    -- `ends_on is null` is open-ended, not expired.
    select m.member_id, min(m.starts_on) as started_on
      from public.memberships m
     where m.tenant_id = p_tenant_id
       and m.status in ('active'::public.membership_status,
                        'frozen'::public.membership_status)
       and (m.ends_on is null or m.ends_on >= v_today)
     group by m.member_id
  ),
  last_visit as (
    select a.member_id,
           max((a.checked_in_at at time zone v_timezone)::date) as last_on
      from public.attendance a
     where a.tenant_id = p_tenant_id
     group by a.member_id
  ),
  candidate as (
    select l.member_id,
           v.last_on,
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
  on conflict (tenant_id, member_id)
    where status in ('open'::public.no_show_case_status,
                     'contacted'::public.no_show_case_status,
                     'follow_up_due'::public.no_show_case_status)
    do nothing;

  get diagnostics v_opened = row_count;
  return v_opened;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- 4. A correction corrects the record; it does not re-decide the case
-- ---------------------------------------------------------------------------

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
  if not pg_catalog.row_security_active('public.follow_ups') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  if v_actor is null
     or new.staff_id is distinct from v_actor then
    raise exception 'follow-up refused: a contact is logged by the staff member making it, and this session records % against an actor of %',
      new.staff_id, coalesce(v_actor::text, 'no staff identity')
      using errcode = 'GL030';
  end if;

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

  if v_status is null then
    return null;
  end if;

  if v_status in ('returned'::public.no_show_case_status,
                  'closed'::public.no_show_case_status) then
    raise exception 'follow-up refused: this case is closed — the member came back, and a closed case is a finished record'
      using errcode = 'GL031';
  end if;

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

  -- **A correction corrects the record; it does not make a new decision about
  -- the member.** Deriving status from one blanked `next_follow_up_at` and
  -- dropped the case out of `no_show_cases_tenant_id_next_follow_up_at_due_idx`
  -- -- the index built for "which follow-ups are due". Staff log "will return,
  -- ring Friday", spot a wrong outcome a minute later, file the correction that
  -- an append-only log makes the only way to fix anything, and nobody rings on
  -- Friday. Silent, caused by doing the right thing, and the exact outcome this
  -- phase exists to prevent.
  if new.corrects_follow_up_id is not null then
    return null;
  end if;

  update public.no_show_cases c
     set status = case
                    when new.next_follow_up_at is null
                      then 'contacted'::public.no_show_case_status
                    else 'follow_up_due'::public.no_show_case_status
                  end,
         contacted_at      = coalesce(c.contacted_at, new.created_at),
         next_follow_up_at = new.next_follow_up_at
   where c.id = new.case_id
     and c.tenant_id = new.tenant_id;

  return null;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- 5. Something that runs it (G1, OPEN-007)
--
--    `pg_cron`, in the database, rather than a deployed Edge Function on a
--    schedule. Three reasons, in order of weight:
--
--    * **It needs no public endpoint.** D1 above is what a public endpoint
--      costs when one grant is written wrongly: every signed-in member could
--      run the nightly job. `cron.schedule` is reachable by nothing outside the
--      database.
--    * It needs no deployment step and no secret, so there is no state in
--      which the migration is applied and the job is not running.
--    * It cannot depend on Vercel, which is `docs/architecture.md`'s stated
--      reason for wanting an Edge Function here at all — and it depends on
--      less.
--
--    01:00 UTC is 06:30 IST: after the demo gym's day boundary and before its
--    front desk opens the list. Gyms in other timezones get their own day
--    computed by the scan itself, so one schedule serves all of them; a gym far
--    enough west would want its own job, which is a Phase 6 problem when a
--    second timezone actually exists.
--
--    The Edge Function stays as the operator's manual entry point -- a re-run
--    after an incident is a real need and one an operator should not need psql
--    for -- and `docs/architecture.md` is updated to say which is authoritative.
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron;

-- Idempotent: `cron.schedule` upserts by job name, so re-applying this
-- migration re-points the job rather than creating a second one.
select cron.schedule(
  'no-show-scan-nightly',
  '0 1 * * *',
  $cron$select public.run_no_show_scan_all()$cron$
);
