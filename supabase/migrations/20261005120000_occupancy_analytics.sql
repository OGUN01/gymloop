-- OCC analytics: one versioned extension of the metrics seam (F14 / V2-D4).
--
-- Frozen authority: openspec/changes/occupancy-analytics/proposal.md
-- (FROZEN 2026-10-03) — OCC-001…017 with the owner-resolved OCC-007
-- thresholds (14 eligible dates / 10 elapsed sessions / 28-day default range,
-- no estimator) and OCC-012 (derived membership-linkage classification,
-- whole-receipt return allocation, unallocated stays unknown).
--
-- `public.owner_occupancy_analytics(p_from date, p_through date,
-- p_branch_id uuid default null, p_exclude_holidays boolean default true)`
-- returns ONE jsonb snapshot (OCC-002) with asOf / zone (the gym zone the
-- money months use) / months / heatmap / classes / warnings. The holiday
-- toggle (OCC-005, visibly reversible) defaults to exclusion on; passing
-- false reinstates holiday dates into the exposure denominator and their
-- visits into the cells, with an empty excludedDates disclosure. The loader
-- seam stays one rpc call; the existing `public.owner_metrics(date,date)`
-- seam is not modified — this is a separate, added read (visible suite 83
-- assertions 42/43 pin that separation).
--
-- Actor revalidation precedes every data read (OCC-001): a real, active,
-- non-impersonating gym_owner/gym_manager staff row matching the verified
-- claims. Branch targets are invisible-target refusals (P0002) for unknown
-- and foreign alike; shape/zone validation is 22023. No new GL numbers.
--
-- Money never touches floating point: integer paise and numeric aggregates
-- only, leaving the function as canonical decimal text. Arrival/class
-- populations are read under the caller's RLS (security invoker).

create or replace function public.owner_occupancy_analytics(p_from date, p_through date, p_branch_id uuid default null, p_exclude_holidays boolean default true)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_asof timestamptz;
  v_gym_tz text;
  v_zone text;
  v_zone_source text;
  v_gym_start timestamptz;
  v_gym_end timestamptz;
  v_start timestamptz;
  v_end timestamptz;
  v_exclude boolean;
  v_result jsonb;
begin
  -- OCC-001: the actor gate runs before any read. Missing/foreign claims,
  -- non-staff roles, platform roles, preview and impersonation share one
  -- refusal and reveal nothing.
  if auth.uid() is null
     or app.current_tenant_id() is null
     or app.current_impersonation_id() is not null
     or not(app.is_staff() and app.current_app_role() in ('gym_owner', 'gym_manager')) then
    raise exception 'Not permitted to read occupancy analytics' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  -- A live token alone confers nothing: the staff row must exist now, be
  -- active, belong to the claimed tenant and match the claimed role.
  if app.current_staff_id() is null or not exists(
    select 1 from public.staff s
    where s.id = app.current_staff_id()
      and s.tenant_id = v_tenant
      and s.user_id = auth.uid()
      and s.is_active
      and s.role::text = app.current_app_role()
  ) then
    raise exception 'Not permitted to read occupancy analytics' using errcode = '42501';
  end if;

  -- OCC-003: real Gregorian dates, from <= through.
  if p_from is null or p_through is null or p_from > p_through then
    raise exception 'Invalid occupancy range' using errcode = '22023', detail = 'invalid_occupancy_range';
  end if;
  v_asof := statement_timestamp();

  select timezone into v_gym_tz from public.organizations where id = v_tenant;
  if v_gym_tz is null or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name = v_gym_tz) then
    raise exception 'Invalid gym timezone' using errcode = '22023', detail = 'invalid_gym_timezone';
  end if;
  v_gym_start := p_from::timestamp at time zone v_gym_tz;
  v_gym_end := (p_through + 1)::timestamp at time zone v_gym_tz;

  -- OCC-003/004: the effective analytics zone is the branch override when
  -- given (disclosed as 'branch'), else the inherited gym zone ('gym'). An
  -- invalid configured override is an explicit error, never a fabricated
  -- zero. Unknown and foreign branches share one invisible-target refusal.
  if p_branch_id is null then
    v_zone := v_gym_tz;
    v_zone_source := 'gym';
  else
    select coalesce(b.timezone, v_gym_tz),
           case when b.timezone is null then 'gym' else 'branch' end
      into v_zone, v_zone_source
      from public.branches b
     where b.tenant_id = v_tenant and b.id = p_branch_id;
    if not found then
      raise exception 'Branch not available' using errcode = 'P0002', detail = 'branch_unavailable';
    end if;
    if v_zone_source = 'branch'
       and not exists(select 1 from pg_catalog.pg_timezone_names z where z.name = v_zone) then
      raise exception 'Invalid branch timezone' using errcode = '22023', detail = 'invalid_branch_timezone';
    end if;
  end if;
  v_start := p_from::timestamp at time zone v_zone;
  v_end := (p_through + 1)::timestamp at time zone v_zone;
  -- OCC-005: exclusion is visibly reversible. The default (and a null
  -- argument) removes holiday dates from the exposure denominator and their
  -- visits from the cells; passing false reinstates both and discloses an
  -- empty excludedDates list. Money and standing class sessions are never
  -- touched by this toggle.
  v_exclude := coalesce(p_exclude_holidays, true);

  -- One containing statement (OCC-002): every population below shares this
  -- statement snapshot and the single disclosed asOf. Events at or after
  -- asOf contribute nothing (OCC-003).
  with session_pop as (
    select s.id, s.capacity, s.status, s.ends_at
    from public.class_sessions s
    where s.tenant_id = v_tenant
      and (p_branch_id is null or s.branch_id = p_branch_id)
      and s.session_date between p_from and p_through
  ),
  visits as (
    select (a.checked_in_at at time zone v_zone)::date as local_date,
           extract(dow from a.checked_in_at at time zone v_zone)::int as weekday,
           extract(hour from a.checked_in_at at time zone v_zone)::int as hour
    from public.attendance a
    where a.tenant_id = v_tenant
      and (p_branch_id is null or a.branch_id = p_branch_id)
      and a.checked_in_at >= v_start
      and a.checked_in_at < v_end
      and a.checked_in_at < v_asof
  ),
  cal as (
    select g.d::date as d,
           extract(dow from g.d)::int as weekday,
           exists(select 1 from public.organization_holidays h
                  where h.tenant_id = v_tenant and h.holiday_on = g.d::date) as is_holiday,
           ((g.d + interval '1 day') at time zone v_zone) <= v_asof as completed
    from generate_series(p_from, p_through, interval '1 day') g(d)
  ),
  date_stats as (
    select cal.d,
           cal.is_holiday,
           not cal.completed as incomplete,
           (select count(*)::int from visits v where v.local_date = cal.d) as visits
    from cal
  ),
  eligible_dates as (
    select d.d, d.weekday from date_stats d
    where not d.incomplete and (not v_exclude or not d.is_holiday)
  ),
  eligible_count as (
    select count(*)::int as n from eligible_dates
  ),
  -- A local wall-clock hour exists when the instant round-trips to the same
  -- wall time (DST spring-forward gaps do not); repeated hours round-trip
  -- once and their occurrences combine into the one cell (OCC-006).
  cell_keys as (
    select e.weekday, h.h as hour
    from eligible_dates e
    cross join generate_series(0, 23) h(h)
    where (((e.d::timestamp + make_interval(hours => h.h)) at time zone v_zone) at time zone v_zone)
          = (e.d::timestamp + make_interval(hours => h.h))
  ),
  cell_counts as (
    select v.weekday, v.hour, count(*)::int as arrivals
    from visits v
    join eligible_dates e on e.d = v.local_date
    group by v.weekday, v.hour
  ),
  today_counts as (
    select v.weekday, v.hour, count(*)::int as today_arrivals
    from visits v
    join date_stats ds on ds.d = v.local_date and ds.incomplete
    group by v.weekday, v.hour
  ),
  -- OCC-012: a payment classifies whole by its membership linkage — new
  -- member money iff its membership is that member's first membership row
  -- (deterministic first-by-creation, tie by id); add-on money through the
  -- linked order; everything unlinked stays unallocated. Returns allocate
  -- whole to the original receipt's category; an unallocated or unknown
  -- original stays in the unknown-allocation disclosure.
  first_memb as (
    select member_id, (array_agg(id order by created_at asc, id asc))[1] as first_id
    from public.memberships
    where tenant_id = v_tenant
    group by member_id
  ),
  pay_cat as (
    select p.id,
           case
             when p.membership_id is not null
                  and p.membership_id = (select f.first_id from first_memb f where f.member_id = p.member_id) then 'new'
             when p.membership_id is not null then 'renewal'
             when exists(select 1 from public.addon_orders ao
                         where ao.tenant_id = p.tenant_id and ao.payment_id = p.id) then 'addon'
             else 'unallocated'
           end as cat
    from public.payments p
    where p.tenant_id = v_tenant and p.status::text in ('paid', 'refunded', 'reversed')
  ),
  coll as (
    select to_char(p.paid_at at time zone v_gym_tz, 'YYYY-MM') as month, p.currency,
           sum(p.amount_paise) as collected,
           sum(case when pc.cat = 'new' then p.amount_paise else 0 end) as new_p,
           sum(case when pc.cat = 'renewal' then p.amount_paise else 0 end) as ren_p,
           sum(case when pc.cat = 'addon' then p.amount_paise else 0 end) as addon_p,
           sum(case when pc.cat = 'unallocated' then p.amount_paise else 0 end) as unalloc_p
    from public.payments p
    join pay_cat pc on pc.id = p.id
    where p.paid_at is not null and p.paid_at >= v_gym_start and p.paid_at < v_gym_end
    group by 1, 2
  ),
  retr as (
    select to_char(r.processed_at at time zone v_gym_tz, 'YYYY-MM') as month, r.currency,
           sum(r.amount_paise) as returned,
           sum(case when pc.cat = 'new' then -r.amount_paise else 0 end) as new_p,
           sum(case when pc.cat = 'renewal' then -r.amount_paise else 0 end) as ren_p,
           sum(case when pc.cat = 'addon' then -r.amount_paise else 0 end) as addon_p,
           sum(case when coalesce(pc.cat, 'unallocated') not in ('new', 'renewal', 'addon')
                    then -r.amount_paise else 0 end) as unknown_p
    from public.refunds r
    join public.payments op on op.tenant_id = r.tenant_id and op.id = r.payment_id
    left join pay_cat pc on pc.id = op.id
    where r.tenant_id = v_tenant and r.status::text = 'completed'
      and r.processed_at is not null
      and r.processed_at >= v_gym_start and r.processed_at < v_gym_end
    group by 1, 2
  ),
  month_rows as (
    select coalesce(c.month, r.month) as month,
           coalesce(c.currency, r.currency) as currency,
           coalesce(c.collected, 0) as collected,
           coalesce(r.returned, 0) as returned,
           coalesce(c.new_p, 0) + coalesce(r.new_p, 0) as new_p,
           coalesce(c.ren_p, 0) + coalesce(r.ren_p, 0) as ren_p,
           coalesce(c.addon_p, 0) + coalesce(r.addon_p, 0) as addon_p,
           coalesce(c.unalloc_p, 0) + coalesce(r.unalloc_p, 0) as unalloc_p,
           coalesce(r.unknown_p, 0) as unknown_p
    from coll c
    full outer join retr r on r.month = c.month and r.currency = c.currency
  ),
  class_agg as (
    select count(*) filter (where s.status::text = 'scheduled' and s.ends_at < v_asof)::int as cohort_n,
           coalesce(sum(s.capacity) filter (where s.status::text = 'scheduled' and s.ends_at < v_asof), 0)::int as total_cap,
           count(*) filter (where s.status::text = 'cancelled')::int as cancelled_n
    from session_pop s
  ),
  hold_agg as (
    select count(*)::int as holding_n,
           count(*) filter (where b.status::text = 'attended')::int as attended_n,
           count(*) filter (where b.status::text = 'no_show')::int as noshow_n
    from public.class_bookings b
    join session_pop s on s.tenant_id = b.tenant_id and s.id = b.session_id
    where b.tenant_id = v_tenant
      and s.status::text = 'scheduled' and s.ends_at < v_asof
      and b.status::text in ('booked', 'attended', 'no_show')
  )
  select jsonb_build_object(
    'asOf', v_asof,
    'zone', v_gym_tz,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object(
               'month', m.month, 'currency', m.currency,
               'collectedPaise', m.collected::text,
               'returnedPaise', m.returned::text,
               'netPaise', (m.collected - m.returned)::text,
               'classification', jsonb_build_object(
                 'newMemberPaise', m.new_p::text,
                 'renewalPaise', m.ren_p::text,
                 'addonPaise', m.addon_p::text,
                 'unallocatedPaise', m.unalloc_p::text,
                 'unknownReturnPaise', m.unknown_p::text,
                 'label', 'Membership linkage (derived classification)'))
             order by m.month, m.currency)
      from month_rows m), '[]'::jsonb),
    'heatmap', jsonb_build_object(
      'zone', v_zone,
      'zoneSource', v_zone_source,
      'cells', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'weekday', c.weekday, 'hour', c.hour,
                 'arrivals', c.arrivals,
                 'todayArrivals', coalesce(tc.today_arrivals, 0),
                 'eligibleDates', ec.n,
                 'fraction', case when ec.n < 14 or c.arrivals = 0 then null
                             else ((trunc((c.arrivals::numeric * 10000) / ec.n)::bigint / 10000)::text
                                   || '.' || lpad((trunc((c.arrivals::numeric * 10000) / ec.n)::bigint % 10000)::text, 4, '0') || '…')
                        end,
                 'limited', ec.n < 14,
                 'message', case when ec.n < 14 then 'Limited history' else null end)
               order by c.weekday, c.hour)
        from cell_keys c
        cross join eligible_count ec
        left join today_counts tc on tc.weekday = c.weekday and tc.hour = c.hour
        left join cell_counts cc on cc.weekday = c.weekday and cc.hour = c.hour
        ), '[]'::jsonb),
      'excludedDates', coalesce((
        select jsonb_agg(jsonb_build_object('localDate', ds.d::text, 'visits', ds.visits) order by ds.d)
        from date_stats ds where v_exclude and ds.is_holiday), '[]'::jsonb),
      'arrivalDays', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'localDate', ds.d::text, 'visits', ds.visits,
                 'isHoliday', ds.is_holiday, 'incomplete', ds.incomplete) order by ds.d)
        from date_stats ds), '[]'::jsonb),
      'noEligibleDays', (select n = 0 from eligible_count ec),
      'eligibleDateCount', (select n from eligible_count ec),
      'message', (select case when n = 0 then 'No eligible days'
                             when n < 14 then 'Limited history'
                             else null end from eligible_count ec)),
    'classes', jsonb_build_object(
      'cohortSessions', ca.cohort_n,
      'totalCapacity', ca.total_cap,
      'holdingBookings', ha.holding_n,
      'bookedFillFraction', case when ca.total_cap = 0 then null
                            else ((trunc((ha.holding_n::numeric * 10000) / ca.total_cap)::bigint / 10000)::text
                                  || '.' || lpad((trunc((ha.holding_n::numeric * 10000) / ca.total_cap)::bigint % 10000)::text, 4, '0') || '…')
                       end,
      'cancelledSessionsExcluded', ca.cancelled_n,
      'attendedCount', ha.attended_n,
      'noShowCount', ha.noshow_n,
      'unmarkedCount', ha.holding_n - ha.attended_n - ha.noshow_n,
      'markingCoverage', case when ha.holding_n = 0 then null
                         else ((trunc(((ha.attended_n + ha.noshow_n)::numeric * 10000) / ha.holding_n)::bigint / 10000)::text
                               || '.' || lpad((trunc(((ha.attended_n + ha.noshow_n)::numeric * 10000) / ha.holding_n)::bigint % 10000)::text, 4, '0') || '…')
                        end,
      'incompleteMarkingDisclosed', (ha.holding_n - ha.attended_n - ha.noshow_n) > 0,
      'limited', ca.cohort_n < 10,
      'message', case when ca.cohort_n < 10 then 'Limited history' else null end),
    'warnings', jsonb_build_object(
      'undatedPayments', coalesce((
        select jsonb_agg(jsonb_build_object('paymentId', p.id, 'amountPaise', p.amount_paise::text, 'currency', p.currency) order by p.id)
        from public.payments p
        where p.tenant_id = v_tenant and p.status::text in ('paid', 'refunded', 'reversed') and p.paid_at is null), '[]'::jsonb),
      'undatedReturns', coalesce((
        select jsonb_agg(jsonb_build_object('returnId', r.id, 'amountPaise', r.amount_paise::text, 'currency', r.currency) order by r.id)
        from public.refunds r
        where r.tenant_id = v_tenant and r.status::text = 'completed' and r.processed_at is null), '[]'::jsonb))
  )
  into v_result
  from class_agg ca
  cross join hold_agg ha;

  return v_result;
end
$fn$;

-- The two-argument form the loader and the suite pin as callable: it is the
-- same snapshot with no branch scope and the default exclusion-on behavior.
create or replace function public.owner_occupancy_analytics(p_from date, p_through date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
begin
  return public.owner_occupancy_analytics(p_from, p_through, null, true);
end
$fn$;

revoke all on function public.owner_occupancy_analytics(date, date, uuid, boolean) from public, anon, service_role;
revoke all on function public.owner_occupancy_analytics(date, date) from public, anon, service_role;
grant execute on function public.owner_occupancy_analytics(date, date, uuid, boolean) to authenticated;
grant execute on function public.owner_occupancy_analytics(date, date) to authenticated;
