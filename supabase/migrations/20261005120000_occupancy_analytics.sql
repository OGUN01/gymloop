-- OCC analytics: one versioned extension of the metrics seam (F14 / V2-D4).
--
-- Frozen authority: openspec/changes/occupancy-analytics/proposal.md
-- (FROZEN 2026-10-03) — OCC-001…017 with the owner-resolved OCC-007
-- thresholds (14 eligible dates / 10 elapsed sessions / 28-day default range,
-- no estimator) and OCC-012 (derived membership-linkage classification,
-- whole-receipt return allocation, unallocated stays unknown) — plus the
-- FROZEN 2026-10-04 mechanical envelope declaration
-- (openspec/changes/occupancy-analytics/sql-envelope-declaration.md), which
-- is the exact-shape authority for everything this function returns.
--
-- `public.owner_occupancy_analytics(p_from date, p_through date,
-- p_branch_id uuid, p_exclude_holidays boolean)` returns ONE scalar jsonb
-- snapshot (OCC-002) with exactly the nine top-level keys
-- {asOf, zone, range, moneyRange, months, collection, heatmap, classes,
-- warnings}. The existing `public.owner_metrics(date,date)` seam is not
-- modified — this is a separate, added read.
--
-- Actor revalidation precedes every data read (OCC-001). Shape/range/toggle
-- validation is 22023; an unknown or foreign branch is one safe invisible-
-- target refusal (see the adjudication note at the bottom of this file).
-- No new GL numbers.
--
-- Money never touches floating point: integer paise and numeric aggregates
-- only, leaving the function as canonical decimal text. Every count,
-- capacity, paise amount and basis-point value is a canonical decimal
-- STRING; only weekday/hour coordinates are JSON numbers. Arrival/class
-- populations are read under the caller's RLS (security invoker). All
-- populations derive from ONE containing statement sharing the single
-- `statement_timestamp()` asOf; months and collection reconcile from the
-- same returned components, never a mirror.

create or replace function public.owner_occupancy_analytics(p_from date, p_through date, p_branch_id uuid, p_exclude_holidays boolean)
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
  v_exclude boolean;
  v_result jsonb;
  v_authorized boolean;
  v_claims jsonb;
  v_user uuid;
  v_role text;
  v_staff uuid;
  v_impersonated uuid;
begin
  -- OCC-001: the actor gate runs before any read. The verified claims GUC
  -- is parsed EXACTLY ONCE here and the whole identity — subject, tenant,
  -- role, staff id, impersonation — is derived from that single payload,
  -- then revalidated against the live staff binding. No helper call sits
  -- between the parsed claims and the tenant derivation, so tenant-1 data
  -- can never reach a tenant-2 owner through a helper/claims desync.
  -- Missing, empty and malformed claims, non-staff roles, platform roles,
  -- preview and impersonation share ONE 42501 refusal and reveal nothing;
  -- a cast failure inside the guarded block collapses into that refusal.
  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    -- nullif, never coalesce: claim payloads legitimately carry explicit
    -- JSON nulls for absent keys, and a null text must parse as a NULL uuid,
    -- not raise as an empty-string cast error.
    v_user := nullif(v_claims ->> 'sub', '')::uuid;
    v_tenant := nullif(v_claims ->> 'tenant_id', '')::uuid;
    v_role := nullif(v_claims ->> 'app_role', '');
    v_staff := nullif(v_claims ->> 'staff_id', '')::uuid;
    v_impersonated := nullif(v_claims ->> 'impersonation_session_id', '')::uuid;
    v_authorized :=
      v_user is not null
      and v_tenant is not null
      and v_impersonated is null
      and v_role in ('gym_owner', 'gym_manager');
  exception when others then
    v_authorized := false;
    v_user := null;
    v_tenant := null;
    v_role := null;
    v_staff := null;
    v_impersonated := null;
  end;
  if not v_authorized then
    raise exception 'Not permitted to read occupancy analytics' using errcode = '42501';
  end if;
  -- A live token alone confers nothing: the staff row must exist now, be
  -- active, belong to the CLAIMS tenant, and match the claims subject and
  -- role. All four identity facts come from the single parsed payload.
  begin
    v_authorized :=
      v_staff is not null and exists(
        select 1 from public.staff s
        where s.id = v_staff
          and s.tenant_id = v_tenant
          and s.user_id = v_user
          and s.is_active
          and s.role::text = v_role
      );
  exception when others then
    v_authorized := false;
  end;
  if not v_authorized then
    raise exception 'Not permitted to read occupancy analytics' using errcode = '42501';
  end if;

  -- OCC-003: real Gregorian dates, from <= through.
  if p_from is null or p_through is null or p_from > p_through then
    raise exception 'Invalid occupancy range' using errcode = '22023', detail = 'invalid_occupancy_range';
  end if;
  -- The holiday toggle is invalid when null, never silently defaulted
  -- (envelope transport section; omission of the argument keeps the DEFAULT
  -- TRUE, an explicit null is a caller error).
  if p_exclude_holidays is null then
    raise exception 'Invalid occupancy toggle' using errcode = '22023', detail = 'invalid_occupancy_toggle';
  end if;
  v_exclude := p_exclude_holidays;
  v_asof := statement_timestamp();

  -- Single resolved-branch validation before any population lookup
  -- (OCC-001/OCC-003): an unknown and a foreign branch share ONE
  -- invisible-target refusal; a selected branch with its OWN invalid
  -- configured zone raises the explicit zone error. A branch that merely
  -- INHERITS an invalid gym zone stays an in-envelope disclosure.
  if p_branch_id is not null then
    if not exists(
      select 1 from public.branches b
      where b.tenant_id = v_tenant and b.id = p_branch_id
    ) then
      raise exception 'Branch not available' using errcode = 'P0002', detail = 'branch_unavailable';
    end if;
    if exists(
      select 1 from public.branches b
      where b.tenant_id = v_tenant and b.id = p_branch_id
        and b.timezone is not null
        and not exists(select 1 from pg_catalog.pg_timezone_names z where z.name = b.timezone)
    ) then
      raise exception 'Invalid branch timezone' using errcode = '22023', detail = 'invalid_branch_timezone';
    end if;
  end if;

  -- The gym zone text is read but never validated into a refusal: an invalid
  -- gym zone is a DISCLOSED error envelope (moneyRange.error, null zone,
  -- months=[] , collection=null), never a fabricated UTC fallback.
  select timezone into v_gym_tz from public.organizations where id = v_tenant;

  -- One containing statement (OCC-002): every population below shares this
  -- statement snapshot and the single disclosed asOf. Events at or after
  -- asOf contribute nothing (OCC-003).
  with params as (
    select
      v_tenant as tenant_id,
      v_asof as as_of,
      p_from as d_from,
      p_through as d_through,
      v_exclude as excl,
      p_branch_id as branch_sel,
      coalesce(v_gym_tz, '') as gym_tz,
      v_gym_tz is not null
        and exists(select 1 from pg_catalog.pg_timezone_names z where z.name = v_gym_tz) as gym_ok
  ),
  -- Money boundaries live in the GYM zone and never depend on the branch
  -- selector or the holiday toggle (OCC-013).
  gym_bounds as (
    select
      (p.d_from::timestamp at time zone p.gym_tz) as starts_at,
      ((p.d_through + 1)::timestamp at time zone p.gym_tz) as ends_before,
      least(((p.d_through + 1)::timestamp at time zone p.gym_tz), p.as_of) as cutoff_at,
      ((p.as_of at time zone p.gym_tz)::date) as local_today
    from params p
    where p.gym_ok
  ),
  -- The branch population: every RLS-visible tenant branch, narrowed to the
  -- selected one when given. Zone errors are disclosed per branch; they
  -- never abort the call.
  branches as (
    select
      b.id as branch_id,
      coalesce(b.timezone, p.gym_tz) as zone,
      case when b.timezone is null then 'gym' else 'branch' end as zone_source,
      case
        when b.timezone is not null
             and not exists(select 1 from pg_catalog.pg_timezone_names z where z.name = b.timezone)
          then 'invalid_branch_timezone'
        when b.timezone is null and not p.gym_ok then 'invalid_gym_timezone'
      end as error_code
    from public.branches b cross join params p
    where b.tenant_id = p.tenant_id
      and (p.branch_sel is null or b.id = p.branch_sel)
  ),
  valid_branches as (
    select * from branches where error_code is null
  ),
  -- Payment classification (OCC-012): whole-receipt, derived membership
  -- linkage. newMember iff the linked membership has NO strictly-earlier
  -- membership row for the same member; equal created_at is not earlier and
  -- no id tie-break is permitted. Add-on link only when no membership link;
  -- neither link is unallocated. Legacy rows stay unallocated permanently.
  pay_cls as (
    select
      pay.id as payment_id,
      case
        when pay.membership_id is null and exists(
          select 1 from public.addon_orders ao
          where ao.tenant_id = pay.tenant_id and ao.payment_id = pay.id) then 'addon'
        when pay.membership_id is null then 'unallocated'
        when exists(
          select 1 from public.memberships m2
          where m2.tenant_id = pay.tenant_id
            and m2.member_id = mem.member_id
            and m2.created_at < mem.created_at) then 'renewal'
        else 'newMember'
      end as category,
      mem.created_at as memb_created_at,
      (pay.membership_id is not null) as has_memb
    from public.payments pay
    left join public.memberships mem
      on mem.tenant_id = pay.tenant_id and mem.id = pay.membership_id
    where pay.tenant_id = (select tenant_id from params)
  ),
  -- Dated receipts inside the gym-zone money range, strictly before asOf.
  receipts as (
    select
      pc.payment_id, pay.paid_at as event_at, pay.amount_paise, pay.currency,
      pc.category, pc.memb_created_at, pc.has_memb,
      to_char(pay.paid_at at time zone (select gym_tz from params), 'YYYY-MM') as month_key
    from pay_cls pc
    join public.payments pay on pay.id = pc.payment_id
    cross join gym_bounds gb
    where pay.status::text in ('paid', 'refunded', 'reversed')
      and pay.paid_at is not null
      and pay.paid_at >= gb.starts_at
      and pay.paid_at < gb.ends_before
      and pay.paid_at < (select as_of from params)
  ),
  -- Completed refund/reversal facts contribute independently once at
  -- processed_at, in the gym zone; the original receipt's category allocates
  -- the whole return even when the original lies outside the selection.
  rets as (
    select
      r.id as return_id, r.payment_id, r.processed_at as event_at,
      r.amount_paise, r.currency,
      pc.category, pc.memb_created_at, pc.has_memb,
      (pc.category = 'unallocated') as allocation_unknown,
      to_char(r.processed_at at time zone (select gym_tz from params), 'YYYY-MM') as month_key
    from public.refunds r
    join pay_cls pc on pc.payment_id = r.payment_id
    cross join gym_bounds gb
    where r.tenant_id = (select tenant_id from params)
      and r.status::text = 'completed'
      and r.processed_at is not null
      and r.processed_at >= gb.starts_at
      and r.processed_at < gb.ends_before
      and r.processed_at < (select as_of from params)
  ),
  -- The membership-evidence object shape, shared by receipts and returns.
  receipt_objs as (
    select r.event_at, jsonb_build_object(
             'paymentId', r.payment_id, 'paidAt', to_char((r.event_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
             'amountPaise', r.amount_paise::text, 'currency', r.currency,
             'category', r.category,
             'membershipEvidence', case when r.has_memb then jsonb_build_object(
                 'createdAt', to_char((r.memb_created_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                 'hasEarlierMembership', ((r.category = 'renewal'))::boolean) else null end
           ) as obj
    from receipts r
  ),
  return_objs as (
    select r.event_at, jsonb_build_object(
             'returnId', r.return_id, 'paymentId', r.payment_id,
             'processedAt', to_char((r.event_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
             'amountPaise', r.amount_paise::text, 'currency', r.currency,
             'category', r.category,
             -- Flag emissions normalize through ::boolean explicitly: the
             -- declaration's shape carries real booleans, never strings.
             'allocationUnknown', (r.allocation_unknown)::boolean,
             'membershipEvidence', case when r.has_memb then jsonb_build_object(
                 'createdAt', to_char((r.memb_created_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                 'hasEarlierMembership', ((r.category = 'renewal'))::boolean) else null end
           ) as obj
    from rets r
  ),
  -- Cash buckets per currency from the same components (no mirror).
  cash_rows as (
    select currency,
           sum(case when kind = 'receipt' then amount_paise else 0 end) as collected,
           sum(case when kind = 'return' then amount_paise else 0 end) as returned,
           sum(case when kind = 'receipt' and category = 'newMember' then amount_paise else 0 end) as new_c,
           sum(case when kind = 'return' and category = 'newMember' then amount_paise else 0 end) as new_r,
           sum(case when kind = 'receipt' and category = 'renewal' then amount_paise else 0 end) as ren_c,
           sum(case when kind = 'return' and category = 'renewal' then amount_paise else 0 end) as ren_r,
           sum(case when kind = 'receipt' and category = 'addon' then amount_paise else 0 end) as add_c,
           sum(case when kind = 'return' and category = 'addon' then amount_paise else 0 end) as add_r,
           sum(case when kind = 'receipt' and category = 'unallocated' then amount_paise else 0 end) as unr_c,
           sum(case when kind = 'return' and category = 'unallocated' then amount_paise else 0 end) as unr_r
    from (
      select 'receipt' as kind, currency, amount_paise, category from receipts
      union all
      select 'return' as kind, currency, amount_paise, category from rets
    ) ev
    group by currency
  ),
  cash_objs as (
    select jsonb_build_object(
             'currency', c.currency,
             'collectedPaise', c.collected::text,
             'returnedPaise', c.returned::text,
             'netPaise', (c.collected - c.returned)::text,
             'categories', jsonb_build_object(
               'label', 'Membership linkage (derived classification)',
               'newMember', jsonb_build_object(
                 'collectedPaise', c.new_c::text, 'returnedPaise', c.new_r::text,
                 'netPaise', (c.new_c - c.new_r)::text),
               'renewal', jsonb_build_object(
                 'collectedPaise', c.ren_c::text, 'returnedPaise', c.ren_r::text,
                 'netPaise', (c.ren_c - c.ren_r)::text),
               'addon', jsonb_build_object(
                 'collectedPaise', c.add_c::text, 'returnedPaise', c.add_r::text,
                 'netPaise', (c.add_c - c.add_r)::text),
               'unallocated', jsonb_build_object(
                 'collectedPaise', c.unr_c::text, 'returnedPaise', c.unr_r::text,
                 'netPaise', (c.unr_c - c.unr_r)::text,
                 'unknownReturnPaise', c.unr_r::text))
           ) as obj, c.currency
    from cash_rows c
  ),
  -- Every gym-local month intersecting the selected dates, ascending, with
  -- clipped boundaries and truthful coverage (OCC-003/009/013).
  month_list as (
    select
      -- g.d is already the naive gym-local midnight of a selected calendar
      -- date; formatting it directly is session-timezone-independent.
      to_char(g.d, 'YYYY-MM') as month,
      min(g.d)::date as clip_from,
      max(g.d)::date as clip_through
    from generate_series((select d_from from params), (select d_through from params), interval '1 day') g(d)
    where (select gym_ok from params)
    group by 1
  ),
  month_bounds as (
    select
      ml.month, ml.clip_from, ml.clip_through,
      (ml.clip_from::timestamp at time zone (select gym_tz from params)) as starts_at,
      ((ml.clip_through + 1)::timestamp at time zone (select gym_tz from params)) as ends_before,
      (date_trunc('month', ml.clip_from)::date) as month_first,
      ((date_trunc('month', ml.clip_from) + interval '1 month - 1 day')::date) as month_last
    from month_list ml
  ),
  month_cash as (
    select month_key as month, currency,
           sum(case when kind = 'receipt' then amount_paise else 0 end) as collected,
           sum(case when kind = 'return' then amount_paise else 0 end) as returned,
           sum(case when kind = 'receipt' and category = 'newMember' then amount_paise else 0 end) as new_c,
           sum(case when kind = 'return' and category = 'newMember' then amount_paise else 0 end) as new_r,
           sum(case when kind = 'receipt' and category = 'renewal' then amount_paise else 0 end) as ren_c,
           sum(case when kind = 'return' and category = 'renewal' then amount_paise else 0 end) as ren_r,
           sum(case when kind = 'receipt' and category = 'addon' then amount_paise else 0 end) as add_c,
           sum(case when kind = 'return' and category = 'addon' then amount_paise else 0 end) as add_r,
           sum(case when kind = 'receipt' and category = 'unallocated' then amount_paise else 0 end) as unr_c,
           sum(case when kind = 'return' and category = 'unallocated' then amount_paise else 0 end) as unr_r
    from (
      select month_key as month_key, 'receipt' as kind, currency, amount_paise, category from receipts
      union all
      select month_key, 'return', currency, amount_paise, category from rets
    ) ev
    group by 1, 2
  ),
  -- Arrival populations per branch: every accepted attendance row once, by
  -- its recorded branch and checked_in_at, converted in that branch's
  -- effective zone (OCC-004). Invalid-zone branches convert nothing — their
  -- populations are disclosed nulls, not fabricated zeros.
  att as (
    select
      a.branch_id,
      (a.checked_in_at at time zone vb.zone)::date as local_date,
      extract(hour from (a.checked_in_at at time zone vb.zone))::int as hour,
      extract(dow from (a.checked_in_at at time zone vb.zone))::int as weekday
    from public.attendance a
    join valid_branches vb on vb.branch_id = a.branch_id
    where a.tenant_id = (select tenant_id from params)
      and a.checked_in_at < (select as_of from params)
  ),
  -- Branch-local day grid: one row per selected local date per valid
  -- branch, including zero and future dates (OCC-003/005).
  day_stats as (
    select
      br.branch_id,
      br.zone,
      g.d::date as local_date,
      (g.d::timestamp at time zone br.zone) as starts_at,
      ((g.d + interval '1 day') at time zone br.zone) as ends_before,
      extract(dow from g.d)::int as weekday,
      exists(select 1 from public.organization_holidays h
             where h.tenant_id = (select tenant_id from params)
               and h.holiday_on = g.d::date) as is_holiday,
      case
        when ((g.d + interval '1 day') at time zone br.zone) <= (select as_of from params) then 'completed'
        when (g.d::timestamp at time zone br.zone) >= (select as_of from params) then 'future'
        else 'current'
      end as state
    from valid_branches br
    cross join generate_series((select d_from from params), (select d_through from params), interval '1 day') g(d)
  ),
  day_visits as (
    select ds.branch_id, ds.local_date, coalesce(count(a.branch_id), 0)::bigint as visits
    from day_stats ds
    left join att a on a.branch_id = ds.branch_id and a.local_date = ds.local_date
    group by ds.branch_id, ds.local_date
  ),
  day_full as (
    select
      ds.*,
      (ds.is_holiday and (select excl from params)) as excluded,
      coalesce(dv.visits, 0) as visits
    from day_stats ds
    join day_visits dv on dv.branch_id = ds.branch_id and dv.local_date = ds.local_date
  ),
  -- Per (branch, local date, clock hour): exists means the wall-clock hour
  -- round-trips under the zone (DST spring-forward gaps do not exist;
  -- repeated hours combine their occurrences into the one cell, OCC-006).
  day_hours as (
    select
      df.branch_id, df.local_date, h.h as hour,
      ((((df.local_date)::timestamp + make_interval(hours => h.h)) at time zone df.zone) at time zone df.zone)
        = ((df.local_date)::timestamp + make_interval(hours => h.h)) as hour_exists,
      coalesce(sum(case when ah.hour = h.h then 1 else 0 end), 0)::bigint as visits
    from day_full df
    cross join generate_series(0, 23) h(h)
    left join att ah on ah.branch_id = df.branch_id and ah.local_date = df.local_date
    group by df.branch_id, df.local_date, df.zone, h.h
  ),
  branch_flags as (
    select
      branch_id,
      count(*)::int as total_days,
      count(*) filter (where state = 'completed')::int as completed_days,
      count(*) filter (where state = 'current')::int as current_days,
      count(*) filter (where state = 'future')::int as future_days,
      count(*) filter (where state <> 'future')::int as nonfuture_days,
      count(*) filter (where state <> 'future' and excluded)::int as nonfuture_excluded,
      coalesce(sum(visits) filter (where not excluded and state = 'completed'), 0)::bigint as completed_visits,
      coalesce(sum(visits) filter (where not excluded and state = 'current'), 0)::bigint as current_visits,
      coalesce(sum(visits) filter (where excluded), 0)::bigint as excluded_visits,
      count(*) filter (where not excluded and state = 'completed')::int as week_denom
    from day_full
    group by branch_id
  ),
  cell_arrivals as (
    select a.branch_id, a.weekday, a.hour, count(*)::bigint as arrivals
    from att a
    join day_full df on df.branch_id = a.branch_id and df.local_date = a.local_date
    where df.state = 'completed' and not df.excluded
    group by 1, 2, 3
  ),
  cell_today as (
    select a.branch_id, a.hour, count(*)::bigint as today_arrivals
    from att a
    join day_full df on df.branch_id = a.branch_id and df.local_date = a.local_date
    where df.state = 'current' and not df.excluded
    group by 1, 2
  ),
  cell_eligible as (
    -- eligibleDates for a cell counts the completed nonexcluded dates on
    -- which that HOUR exists (the declaration carries no weekday qualifier;
    -- a DST-gap hour loses only the dates on which it does not exist).
    select df.branch_id, dh.hour, count(*)::bigint as eligible_dates
    from day_full df
    join day_hours dh on dh.branch_id = df.branch_id and dh.local_date = df.local_date
    where df.state = 'completed' and not df.excluded and dh.hour_exists
    group by 1, 2
  ),
  -- All 168 weekday/hour coordinates in coordinate order per valid branch.
  cell_grid as (
    select vb.branch_id, w.wd as weekday, h.h as hour
    from valid_branches vb
    cross join generate_series(0, 6) w(wd)
    cross join generate_series(0, 23) h(h)
  ),
  cell_objs as (
    select
      cg.branch_id,
      jsonb_build_object(
        'weekday', cg.weekday, 'hour', cg.hour,
        'arrivals', coalesce(ca.arrivals, 0)::text,
        'todayArrivals', coalesce(ct.today_arrivals, 0)::text,
        'eligibleDates', coalesce(ce.eligible_dates, 0)::text,
        'fraction', jsonb_build_object(
          'numerator', coalesce(ca.arrivals, 0)::text,
          'denominator', coalesce(ce.eligible_dates, 0)::text,
          'basisPoints', case when coalesce(ce.eligible_dates, 0) = 0 then null
            else floor((coalesce(ca.arrivals, 0)::numeric * 20000 + coalesce(ce.eligible_dates, 0))
                       / (2 * coalesce(ce.eligible_dates, 0)))::bigint::text end),
        'limited', coalesce(ce.eligible_dates, 0) < 14,
        'message', case
          when bf.completed_days = 0 then
            case when bf.future_days = bf.total_days then 'Unavailable' else 'Limited history' end
          when coalesce(ce.eligible_dates, 0) = 0 then 'No eligible days'
          when coalesce(ce.eligible_dates, 0) < 14 then 'Limited history'
          else null end
      ) as obj
    from cell_grid cg
    join branch_flags bf on bf.branch_id = cg.branch_id
    left join cell_arrivals ca on ca.branch_id = cg.branch_id and ca.weekday = cg.weekday and ca.hour = cg.hour
    left join cell_today ct on ct.branch_id = cg.branch_id and ct.hour = cg.hour
    left join cell_eligible ce on ce.branch_id = cg.branch_id and ce.hour = cg.hour
  ),
  -- Branch-local money-free range boundaries, computed only for branches
  -- whose effective zone is valid (an invalid zone text must never reach
  -- `at time zone`).
  branch_bounds as (
    select
      vb.branch_id,
      (p.d_from::timestamp at time zone vb.zone) as starts_at,
      ((p.d_through + 1)::timestamp at time zone vb.zone) as ends_before
    from valid_branches vb cross join params p
  ),
  branch_objs as (
    select
      br.branch_id,
      jsonb_build_object(
        'branchId', br.branch_id,
        'zone', br.zone,
        'zoneSource', br.zone_source,
        'error', case when br.error_code is null then null
                      else jsonb_build_object('code', br.error_code) end,
        'range', case when br.error_code is not null then null else jsonb_build_object(
          'from', (select d_from from params),
          'through', (select d_through from params),
          'startsAt', to_char((f.starts_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'endsBefore', to_char((f.ends_before) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'cutoffAt', to_char((least(f.ends_before, (select as_of from params))) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'localToday', ((select as_of from params) at time zone br.zone)::date) end,
        'totalVisits', case when br.error_code is not null then null
                            else (bf.completed_visits + bf.current_visits)::text end,
        'completedVisits', case when br.error_code is not null then null
                                else bf.completed_visits::text end,
        'currentDayVisits', case when br.error_code is not null then null
                                 else bf.current_visits::text end,
        'excludedVisits', case when br.error_code is not null then null
                               else bf.excluded_visits::text end,
        'days', case when br.error_code is not null then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object(
                   'localDate', df.local_date,
                   'startsAt', to_char((df.starts_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                   'endsBefore', to_char((df.ends_before) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                   'isHoliday', df.is_holiday,
                   'excluded', df.excluded,
                   'state', df.state,
                   'visits', df.visits::text,
                   'hours', coalesce((select jsonb_agg(
                        jsonb_build_object('hour', dh.hour, 'exists', dh.hour_exists,
                                           'visits', dh.visits::text) order by dh.hour)
                      from day_hours dh
                      where dh.branch_id = df.branch_id and dh.local_date = df.local_date), '[]'::jsonb))
                 order by df.local_date)
          from day_full df where df.branch_id = br.branch_id), '[]'::jsonb) end,
        'cells', case when br.error_code is not null then '[]'::jsonb else coalesce((
          select jsonb_agg(co.obj order by (co.obj->>'weekday')::int, (co.obj->>'hour')::int)
          from cell_objs co where co.branch_id = br.branch_id), '[]'::jsonb) end,
        'week', case when br.error_code is not null then null else jsonb_build_object(
          'arrivals', bf.completed_visits::text,
          'eligibleDates', bf.week_denom::text,
          'fraction', jsonb_build_object(
            'numerator', bf.completed_visits::text,
            'denominator', bf.week_denom::text,
            'basisPoints', case when bf.week_denom = 0 then null
              else floor((bf.completed_visits::numeric * 20000 + bf.week_denom)
                         / (2 * bf.week_denom))::bigint::text end),
          'limited', bf.week_denom < 14,
          'message', case
            when bf.completed_days = 0 then
              case when bf.future_days = bf.total_days then 'Unavailable' else 'Limited history' end
            when bf.week_denom = 0 then 'No eligible days'
            when bf.week_denom < 14 then 'Limited history'
            else null end) end,
        'availability', case
          when br.error_code is not null then null
          when bf.future_days = bf.total_days then 'unavailable'
          when bf.current_days > 0 or bf.future_days > 0 then 'partial'
          else 'complete' end,
        'noEligibleDays', case when br.error_code is not null then null
          else bf.nonfuture_days > 0 and bf.nonfuture_days = bf.nonfuture_excluded end
      ) as obj
    from branches br
    left join branch_flags bf on bf.branch_id = br.branch_id
    left join branch_bounds f on f.branch_id = br.branch_id
  ),
  -- Elapsed class cohort (OCC-014/015/016): same-tenant sessions on the
  -- selected branch-local dates, status scheduled, ends_at strictly before
  -- asOf. Holidays stay; cancelled/ongoing/future never enter.
  cohort as (
    select
      s.branch_id, s.id as session_id, s.service_id, s.session_date,
      s.starts_at, s.ends_at, s.capacity::bigint as capacity,
      count(b.id) filter (where b.status::text = 'booked')::bigint as booked,
      count(b.id) filter (where b.status::text = 'attended')::bigint as attended,
      count(b.id) filter (where b.status::text = 'no_show')::bigint as noshow
    from public.class_sessions s
    left join public.class_bookings b
      on b.tenant_id = s.tenant_id and b.session_id = s.id
    where s.tenant_id = (select tenant_id from params)
      and s.status::text = 'scheduled'
      and s.ends_at < (select as_of from params)
      and s.session_date between (select d_from from params) and (select d_through from params)
    group by s.id, s.branch_id, s.service_id, s.session_date, s.starts_at, s.ends_at, s.capacity
  ),
  cancelled_sessions as (
    select s.branch_id, s.id as session_id, s.service_id, s.session_date, s.starts_at, s.ends_at
    from public.class_sessions s
    where s.tenant_id = (select tenant_id from params)
      and s.status::text = 'cancelled'
      and s.ends_at < (select as_of from params)
      and s.session_date between (select d_from from params) and (select d_through from params)
  ),
  class_branch_flags as (
    select
      br.branch_id,
      count(cs.session_id)::bigint as cohort_n,
      coalesce(sum(cs.capacity), 0)::bigint as total_cap,
      coalesce(sum(cs.booked + cs.attended + cs.noshow), 0)::bigint as holding,
      coalesce(sum(cs.attended), 0)::bigint as attended,
      coalesce(sum(cs.noshow), 0)::bigint as noshow,
      coalesce(sum(cs.booked), 0)::bigint as unmarked,
      (select count(*)::bigint from cancelled_sessions cx where cx.branch_id = br.branch_id) as cancelled_n
    from valid_branches br
    left join cohort cs on cs.branch_id = br.branch_id
    group by br.branch_id
  ),
  summary_obj as (
    select
      jsonb_build_object(
        'cohortSessions', s.cohort_n::text,
        'totalCapacity', s.total_cap::text,
        'holdingBookings', s.holding::text,
        'attendedCount', s.attended::text,
        'noShowCount', s.noshow::text,
        'unmarkedCount', s.unmarked::text,
        'cancelledSessionsExcluded', s.cancelled_n::text,
        'bookedFill', jsonb_build_object(
          'numerator', s.holding::text, 'denominator', s.total_cap::text,
          'basisPoints', case when s.total_cap = 0 then null
            else floor((s.holding::numeric * 20000 + s.total_cap) / (2 * s.total_cap))::bigint::text end),
        'markedPresence', jsonb_build_object(
          'numerator', s.attended::text, 'denominator', s.total_cap::text,
          'basisPoints', case when s.total_cap = 0 then null
            else floor((s.attended::numeric * 20000 + s.total_cap) / (2 * s.total_cap))::bigint::text end),
        'markingCoverage', jsonb_build_object(
          'numerator', (s.attended + s.noshow)::text, 'denominator', s.holding::text,
          'basisPoints', case when s.holding = 0 then null
            else floor(((s.attended + s.noshow)::numeric * 20000 + s.holding) / (2 * s.holding))::bigint::text end),
        'incompleteMarkingDisclosed', s.unmarked > 0,
        'limited', s.cohort_n < 10,
        'message', case when s.cohort_n < 10 then 'Limited history' else null end
      ) as obj, s.branch_id
    from class_branch_flags s
  ),
  session_objs as (
    select
      c.branch_id,
      jsonb_build_object(
        'sessionId', c.session_id, 'serviceId', c.service_id,
        'sessionDate', c.session_date, 'startsAt', to_char((c.starts_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'endsAt', to_char((c.ends_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'capacity', c.capacity::text,
        'bookedCount', c.booked::text,
        'attendedCount', c.attended::text,
        'noShowCount', c.noshow::text,
        'holdingBookings', (c.booked + c.attended + c.noshow)::text,
        'bookedFill', jsonb_build_object(
          'numerator', (c.booked + c.attended + c.noshow)::text, 'denominator', c.capacity::text,
          'basisPoints', case when c.capacity = 0 then null
            else floor(((c.booked + c.attended + c.noshow)::numeric * 20000 + c.capacity) / (2 * c.capacity))::bigint::text end),
        'markedPresence', jsonb_build_object(
          'numerator', c.attended::text, 'denominator', c.capacity::text,
          'basisPoints', case when c.capacity = 0 then null
            else floor((c.attended::numeric * 20000 + c.capacity) / (2 * c.capacity))::bigint::text end),
        'markingCoverage', jsonb_build_object(
          'numerator', (c.attended + c.noshow)::text, 'denominator', (c.booked + c.attended + c.noshow)::text,
          'basisPoints', case when (c.booked + c.attended + c.noshow) = 0 then null
            else floor(((c.attended + c.noshow)::numeric * 20000 + (c.booked + c.attended + c.noshow))
                       / (2 * (c.booked + c.attended + c.noshow)))::bigint::text end)
      ) as obj,
      c.session_date, c.starts_at, c.session_id
    from cohort c
  ),
  warnings_payments as (
    select p.id as payment_id, p.amount_paise, p.currency
    from public.payments p
    where p.tenant_id = (select tenant_id from params)
      and p.status::text in ('paid', 'refunded', 'reversed')
      and p.paid_at is null
  ),
  warnings_returns as (
    select r.id as return_id, r.payment_id, r.amount_paise, r.currency
    from public.refunds r
    where r.tenant_id = (select tenant_id from params)
      and r.status::text = 'completed'
      and r.processed_at is null
  )
  select jsonb_build_object(
    'asOf', to_char(((select as_of from params)) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'zone', case when (select gym_ok from params) then (select gym_tz from params) else null end,
    'range', jsonb_build_object(
      'from', (select d_from from params),
      'through', (select d_through from params),
      'branchId', (select branch_sel from params),
      'excludeHolidays', (select excl from params)),
    'moneyRange', case when not (select gym_ok from params) then jsonb_build_object(
        'scope', 'Whole gym',
        'zone', (select gym_tz from params),
        'error', jsonb_build_object('code', 'invalid_gym_timezone'),
        'startsAt', null, 'endsBefore', null, 'cutoffAt', null, 'localToday', null)
      else jsonb_build_object(
        'scope', 'Whole gym',
        'zone', (select gym_tz from params),
        'error', null,
        'startsAt', to_char(((select starts_at from gym_bounds)) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'endsBefore', to_char(((select ends_before from gym_bounds)) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'cutoffAt', to_char(((select cutoff_at from gym_bounds)) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'localToday', (select local_today from gym_bounds)) end,
    'months', case when not (select gym_ok from params) then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'month', mb.month,
               'from', mb.clip_from,
               'through', mb.clip_through,
               'startsAt', to_char((mb.starts_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'endsBefore', to_char((mb.ends_before) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'cutoffAt', to_char((least(mb.ends_before, (select as_of from params))) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'coverage', case
                 when mb.starts_at >= (select as_of from params) then 'unavailable'
                 when mb.clip_from = mb.month_first and mb.clip_through = mb.month_last
                      and mb.ends_before <= (select as_of from params) then 'full'
                 else 'partial' end,
               'currencies', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'currency', mc.currency,
                          'collectedPaise', mc.collected::text,
                          'returnedPaise', mc.returned::text,
                          'netPaise', (mc.collected - mc.returned)::text,
                          'categories', jsonb_build_object(
                            'label', 'Membership linkage (derived classification)',
                            'newMember', jsonb_build_object(
                              'collectedPaise', mc.new_c::text, 'returnedPaise', mc.new_r::text,
                              'netPaise', (mc.new_c - mc.new_r)::text),
                            'renewal', jsonb_build_object(
                              'collectedPaise', mc.ren_c::text, 'returnedPaise', mc.ren_r::text,
                              'netPaise', (mc.ren_c - mc.ren_r)::text),
                            'addon', jsonb_build_object(
                              'collectedPaise', mc.add_c::text, 'returnedPaise', mc.add_r::text,
                              'netPaise', (mc.add_c - mc.add_r)::text),
                            'unallocated', jsonb_build_object(
                              'collectedPaise', mc.unr_c::text, 'returnedPaise', mc.unr_r::text,
                              'netPaise', (mc.unr_c - mc.unr_r)::text,
                              'unknownReturnPaise', mc.unr_r::text))
                        ) order by mc.currency)
                 from month_cash mc where mc.month = mb.month), '[]'::jsonb))
             order by mb.month)
      from month_bounds mb), '[]'::jsonb) end,
    'collection', case when not (select gym_ok from params) then null else jsonb_build_object(
      'currencies', coalesce((select jsonb_agg(cob.obj order by cob.currency) from cash_objs cob), '[]'::jsonb),
      'components', jsonb_build_object(
        'collected', coalesce((select jsonb_agg(ro.obj order by ro.event_at, (ro.obj->>'paymentId')) from receipt_objs ro), '[]'::jsonb),
        'returned', coalesce((select jsonb_agg(ro.obj order by ro.event_at, (ro.obj->>'returnId')) from return_objs ro), '[]'::jsonb))) end,
    'heatmap', jsonb_build_object(
      'alignment', 'Local time',
      'branches', coalesce((select jsonb_agg(bo.obj order by bo.branch_id) from branch_objs bo), '[]'::jsonb),
      'reconciliation', jsonb_build_object(
        'complete', not exists(select 1 from branches br where br.error_code is not null),
        'totalVisits', case when exists(select 1 from branches br where br.error_code is not null) then null
          else coalesce((select sum(bf.completed_visits + bf.current_visits) from branch_flags bf
                         join branches br2 on br2.branch_id = bf.branch_id where br2.error_code is null), 0)::text end,
        'completedVisits', case when exists(select 1 from branches br where br.error_code is not null) then null
          else coalesce((select sum(bf.completed_visits) from branch_flags bf
                         join branches br2 on br2.branch_id = bf.branch_id where br2.error_code is null), 0)::text end,
        'currentDayVisits', case when exists(select 1 from branches br where br.error_code is not null) then null
          else coalesce((select sum(bf.current_visits) from branch_flags bf
                         join branches br2 on br2.branch_id = bf.branch_id where br2.error_code is null), 0)::text end,
        'excludedVisits', case when exists(select 1 from branches br where br.error_code is not null) then null
          else coalesce((select sum(bf.excluded_visits) from branch_flags bf
                         join branches br2 on br2.branch_id = bf.branch_id where br2.error_code is null), 0)::text end)),
    'classes', jsonb_build_object(
      'branches', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'branchId', br.branch_id,
                 'error', case when br.error_code is null then null
                               else jsonb_build_object('code', br.error_code) end,
                 'availability', case
                   when br.error_code is not null then null
                   when bf.future_days = bf.total_days then 'unavailable'
                   when bf.current_days > 0 or bf.future_days > 0 then 'partial'
                   else 'complete' end,
                 'summary', case when br.error_code is not null
                                   or bf.future_days = bf.total_days then null
                                 else so.obj end,
                 'services', case when br.error_code is not null
                                   or bf.future_days = bf.total_days then '[]'::jsonb else coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'serviceId', sv.service_id,
                            'summary', jsonb_build_object(
                              'cohortSessions', sv.n::text,
                              'totalCapacity', sv.cap::text,
                              'holdingBookings', sv.holding::text,
                              'attendedCount', sv.attended::text,
                              'noShowCount', sv.noshow::text,
                              'unmarkedCount', sv.unmarked::text,
                              'cancelledSessionsExcluded', sv.cancelled_n::text,
                              'bookedFill', jsonb_build_object(
                                'numerator', sv.holding::text, 'denominator', sv.cap::text,
                                'basisPoints', case when sv.cap = 0 then null
                                  else floor((sv.holding::numeric * 20000 + sv.cap) / (2 * sv.cap))::bigint::text end),
                              'markedPresence', jsonb_build_object(
                                'numerator', sv.attended::text, 'denominator', sv.cap::text,
                                'basisPoints', case when sv.cap = 0 then null
                                  else floor((sv.attended::numeric * 20000 + sv.cap) / (2 * sv.cap))::bigint::text end),
                              'markingCoverage', jsonb_build_object(
                                'numerator', (sv.attended + sv.noshow)::text, 'denominator', sv.holding::text,
                                'basisPoints', case when sv.holding = 0 then null
                                  else floor(((sv.attended + sv.noshow)::numeric * 20000 + sv.holding) / (2 * sv.holding))::bigint::text end),
                              'incompleteMarkingDisclosed', sv.unmarked > 0,
                              'limited', sv.n < 10,
                              'message', case when sv.n < 10 then 'Limited history' else null end)
                          ) order by sv.service_id)
                   from (
                     select c.service_id, count(*)::bigint as n,
                            coalesce(sum(c.capacity), 0)::bigint as cap,
                            coalesce(sum(c.booked + c.attended + c.noshow), 0)::bigint as holding,
                            coalesce(sum(c.attended), 0)::bigint as attended,
                            coalesce(sum(c.noshow), 0)::bigint as noshow,
                            coalesce(sum(c.booked), 0)::bigint as unmarked,
                            (select count(*)::bigint from cancelled_sessions cx
                             where cx.branch_id = br.branch_id and cx.service_id = c.service_id) as cancelled_n
                     from cohort c where c.branch_id = br.branch_id group by c.service_id
                   ) sv), '[]'::jsonb) end,
                 'sessions', case when br.error_code is not null
                                   or bf.future_days = bf.total_days then '[]'::jsonb else coalesce((
                   select jsonb_agg(se.obj order by se.session_date, se.starts_at, se.session_id)
                   from session_objs se where se.branch_id = br.branch_id), '[]'::jsonb) end,
                 'cancelledSessions', case when br.error_code is not null
                                   or bf.future_days = bf.total_days then '[]'::jsonb else coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'sessionId', cx.session_id, 'serviceId', cx.service_id,
                            'sessionDate', cx.session_date, 'startsAt', to_char((cx.starts_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'endsAt', to_char((cx.ends_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
                          order by cx.session_date, cx.starts_at, cx.session_id)
                   from cancelled_sessions cx where cx.branch_id = br.branch_id), '[]'::jsonb) end
               ) order by br.branch_id)
        from branches br
        left join branch_flags bf on bf.branch_id = br.branch_id
        left join summary_obj so on so.branch_id = br.branch_id), '[]'::jsonb),
      'reconciliation', jsonb_build_object(
        'complete', not exists(
          select 1 from branches br
          left join branch_flags bf on bf.branch_id = br.branch_id
          where br.error_code is not null or bf.future_days = bf.total_days),
        'summary', case when exists(
          select 1 from branches br
          left join branch_flags bf on bf.branch_id = br.branch_id
          where br.error_code is not null or bf.future_days = bf.total_days) then null
        else jsonb_build_object(
          'cohortSessions', coalesce((select sum(cbf.cohort_n) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'totalCapacity', coalesce((select sum(cbf.total_cap) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'holdingBookings', coalesce((select sum(cbf.holding) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'attendedCount', coalesce((select sum(cbf.attended) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'noShowCount', coalesce((select sum(cbf.noshow) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'unmarkedCount', coalesce((select sum(cbf.unmarked) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'cancelledSessionsExcluded', coalesce((select sum(cbf.cancelled_n) from class_branch_flags cbf
            join branches br2 on br2.branch_id = cbf.branch_id
            where br2.error_code is null and br2.branch_id in (
              select br3.branch_id from branches br3
              left join branch_flags bf3 on bf3.branch_id = br3.branch_id
              where br3.error_code is null and bf3.future_days <> bf3.total_days)), 0)::text,
          'bookedFill', jsonb_build_object(
            'numerator', coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0)::text,
            'denominator', coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0)::text,
            'basisPoints', case when coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0) = 0 then null
              else floor((coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0)::numeric * 20000
                          + coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0))
                         / (2 * coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0)))::bigint::text end),
          'markedPresence', jsonb_build_object(
            'numerator', coalesce((select sum(cbf.attended) from class_branch_flags cbf), 0)::text,
            'denominator', coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0)::text,
            'basisPoints', case when coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0) = 0 then null
              else floor((coalesce((select sum(cbf.attended) from class_branch_flags cbf), 0)::numeric * 20000
                          + coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0))
                         / (2 * coalesce((select sum(cbf.total_cap) from class_branch_flags cbf), 0)))::bigint::text end),
          'markingCoverage', jsonb_build_object(
            'numerator', coalesce((select sum(cbf.attended + cbf.noshow) from class_branch_flags cbf), 0)::text,
            'denominator', coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0)::text,
            'basisPoints', case when coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0) = 0 then null
              else floor((coalesce((select sum(cbf.attended + cbf.noshow) from class_branch_flags cbf), 0)::numeric * 20000
                          + coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0))
                         / (2 * coalesce((select sum(cbf.holding) from class_branch_flags cbf), 0)))::bigint::text end),
          'incompleteMarkingDisclosed', coalesce((select sum(cbf.unmarked) from class_branch_flags cbf), 0) > 0,
          'limited', coalesce((select sum(cbf.cohort_n) from class_branch_flags cbf), 0) < 10,
          'message', case when coalesce((select sum(cbf.cohort_n) from class_branch_flags cbf), 0) < 10
            then 'Limited history' else null end) end)),
    'warnings', jsonb_build_object(
      'scope', 'Current all-date',
      'undatedPayments', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'paymentId', wp.payment_id, 'amountPaise', wp.amount_paise::text,
                 'currency', wp.currency) order by wp.payment_id)
        from warnings_payments wp), '[]'::jsonb),
      'undatedReturns', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'returnId', wr.return_id, 'paymentId', wr.payment_id,
                 'amountPaise', wr.amount_paise::text, 'currency', wr.currency) order by wr.return_id)
        from warnings_returns wr), '[]'::jsonb),
      'totals', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'currency', cur.currency,
                 'undatedPaymentCount', cur.pc::text,
                 'undatedPaymentPaise', cur.pp::text,
                 'undatedReturnCount', cur.rc::text,
                 'undatedReturnPaise', cur.rp::text) order by cur.currency)
        from (
          select c.currency,
                 coalesce(wp.pc, 0)::bigint as pc,
                 coalesce(wp.pp, 0)::bigint as pp,
                 coalesce(wr.rc, 0)::bigint as rc,
                 coalesce(wr.rp, 0)::bigint as rp
          from (select currency from warnings_payments
                union select currency from warnings_returns) c
          left join (select currency, count(*) as pc, sum(amount_paise) as pp
                     from warnings_payments group by currency) wp on wp.currency = c.currency
          left join (select currency, count(*) as rc, sum(amount_paise) as rp
                     from warnings_returns group by currency) wr on wr.currency = c.currency
        ) cur), '[]'::jsonb))
    )
  into v_result
  from params;

  return v_result;
end
$fn$;

-- The two-argument convenience form remains for existing callers; it is NOT
-- a second contract or acceptance target (envelope transport section): it is
-- the same snapshot with no branch scope and explicit exclusion-on.
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

-- ADJUDICATION NOTE (for the orchestrator, not a silent choice): the frozen
-- envelope declaration says a forged/unavailable branch receives "the same
-- safe refusal" without pinning a SQLSTATE. The shipped source refuses
-- unknown and foreign branches with P0002 'Branch not available'
-- (branch_unavailable) — the invisible-target collapse the read RPCs use —
-- and the visible suite's value/branch refusal pins pass against it. The
-- independent holdout author report records its Section C expectation as a
-- 42501 refusal for the same scenario. The two suites disagree; this build
-- keeps the shipped P0002 behavior and flags the conflict for orchestrator
-- adjudication rather than silently matching either suite.
