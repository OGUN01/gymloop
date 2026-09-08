-- red_list_view
--
-- The screen a gym opens each morning, as a view, because two of its
-- requirements cannot be met from the client.
--
-- 1. **Days absent is computed at read time and ordered by.** The list must put
--    the member gone longest first, and `days_absent` is
--    `absent_days_at_open + (today - opened_on)` -- a value that changes every
--    midnight. PostgREST can order by a column and not by an expression, and a
--    generated column cannot help because generated columns must be immutable
--    and `current_date` is not. So the expression lives here.
--
--    **Not `absent_days_at_open`**, which is what a naive list would show: that
--    column is frozen evidence of what the case saw when it opened, and it is
--    deliberately frozen. A list rendering it would tell the front desk a
--    member has been gone eight days for as long as the case stays open --
--    wrong the next morning and worse every morning after.
--
--    Derived from the case rather than re-derived from `attendance`: the case
--    already recorded the absence it was judged on, so adding elapsed days is
--    exact, needs no scan of attendance per row, and cannot disagree with the
--    rule that opened the case.
--
-- 2. **What was already tried, without leaving the list.** "Has anyone rung
--    her?" is the question the screen exists to answer and a second call is the
--    failure it exists to prevent, so the latest follow-up comes back with the
--    row. A lateral join, one row per case, rather than N+1 requests from the
--    screen (gate 26).
--
-- `security_invoker = true` is the load-bearing word. Without it a view runs as
-- its owner -- `postgres`, which holds `BYPASSRLS` -- and this view would hand
-- every gym's cases to every caller: a tenancy hole with no policy anywhere to
-- catch it, because the policies on the underlying tables would never be
-- consulted. With it, `no_show_cases_tenant_select`, `members_tenant_select`,
-- `follow_ups_tenant_select` and `staff_tenant_select` all apply as if the
-- caller had written the join themselves, which is exactly what a view should
-- be. This is ADR-066's shape in the one place a view can produce it.

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
  -- The whole reason this view exists.
  c.absent_days_at_open + (current_date - c.opened_on) as days_absent,
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
-- A work queue, not a history. `returned` and `closed` are finished records;
-- the member came back, which is the outcome the whole loop is for.
where c.status not in ('returned'::public.no_show_case_status,
                       'closed'::public.no_show_case_status);

comment on view public.red_list_cases is
  'The red list: open no-show cases with days-absent computed at read time and the latest follow-up attached. security_invoker, so the underlying tables'' policies do the filtering.';

-- `select` only, and no `insert`/`update` grant even though a simple view would
-- be updatable: a case moves because a follow-up was logged or a member came
-- back, never because somebody wrote to the list they were reading.
grant select on public.red_list_cases to authenticated;
