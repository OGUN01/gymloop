-- a_case_outlives_its_membership
--
-- The other half of ADR-075. That round stopped the scan OPENING a case for a
-- member whose membership had lapsed; nothing closed the ones already open.
--
-- A case opened legitimately while the membership was live outlives it the
-- moment it expires — and because `days_absent` grows without bound, it climbs
-- to the top of the red list and stays there. **Two are live in the demo gym
-- right now** (`Suresh Bhatia`, ended 2026-09-05; `Naina Kapadia`, ended
-- 2026-09-08) and a third arrives on its own tomorrow, purely by a membership
-- reaching its end date. No manual writes involved. So the front desk is told,
-- every morning, to ring the person at the top of the list about coming back to
-- a membership that no longer exists.
--
-- It is also an inconsistency the product does not mean to have: the same
-- member is in scope or out of it depending only on *when* their membership
-- expired relative to the case.
--
-- **"Live" means all three states, and that wording was settled by a blind test
-- author asking rather than guessing.** The first draft of the requirement said
-- "an open case"; `no_show_cases_tenant_id_member_id_open_key` treats `open`,
-- `contacted` and `follow_up_due` as one open case, and the red list renders
-- everything that is not `returned` or `closed`. So a `contacted` case for a
-- lapsed member sits at the top exactly as an `open` one does — and one
-- somebody has already rung about is the more embarrassing to keep suggesting.
--
-- Closed, never deleted, on NSH-005's reasoning: the case and its follow-ups
-- are the record that somebody tried, and a delete destroys the evidence.
--
-- `returned_at` is deliberately NOT stamped. They did not return; their
-- membership ended. Reusing that column would make "came back" and "stopped
-- being a member" indistinguishable in the only place the difference is
-- recorded.

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

  if v_today is null or v_threshold is null then
    return 0;
  end if;

  -- Close first, then open. Either order works — the opening pass already
  -- excludes members without a live membership — but closing first means the
  -- function reads as "tidy up what has expired, then look for what is new",
  -- which is the order a person would describe it in.
  update public.no_show_cases c
     set status    = 'closed'::public.no_show_case_status,
         closed_at = pg_catalog.now()
   where c.tenant_id = p_tenant_id
     and c.status in ('open'::public.no_show_case_status,
                      'contacted'::public.no_show_case_status,
                      'follow_up_due'::public.no_show_case_status)
     -- The same definition of "live" the opening pass uses, deliberately
     -- written out rather than shared: if these two ever disagree, a member can
     -- be simultaneously too lapsed to open a case and too live to close one,
     -- and the case sits for ever in between. Any future edit belongs in both.
     and not exists (
       select 1
         from public.memberships m
        where m.tenant_id = p_tenant_id
          and m.member_id = c.member_id
          and m.status in ('active'::public.membership_status,
                           'frozen'::public.membership_status)
          and (m.ends_on is null or m.ends_on >= v_today)
     );

  with live as (
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

  -- Still the number OPENED, not opened-plus-closed. The spec's contract is
  -- "how many cases did this scan open", and an operator reading a nightly log
  -- needs "we found three new people" to keep meaning that when six lapsed
  -- memberships happen to close on the same night.
  get diagnostics v_opened = row_count;
  return v_opened;
end;
$fn$;
