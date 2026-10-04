-- Fixture repair 2026-10-04: pg_proc.proconfig is text[], so read its
-- explicit search_path entry instead of applying a JSON operator.
-- 2026-10-04 independent reconciliation: frozen public contracts only; no
-- implementation, migrations, visible suites or private diagnostics read.
-- Independent holdout: frozen OCC-001..017 public contract only
-- (openspec/changes/occupancy-analytics/proposal.md + docs/design/v2/occ-bar.md).
-- No implementation, no visible suite, no other holdout, no registry was read.
--
-- Pinned seam (from the owner-approved loader): public.owner_occupancy_analytics(
--   p_from date, p_through date, p_branch_id uuid default null,
--   p_exclude_holidays boolean default true) returns jsonb.
-- OCC-005's "visibly reversible" is RPC-side: the fourth parameter turns the
-- holiday exclusion off, and the snapshot then carries the holiday date back
-- in the exposure (eligible dates, arrivals) with no exclusions disclosure.
--
-- Pattern: hybrid dispatch, stated honestly.
--   Section A pins the REAL object's shape/security in public (RED, via
--   to_regprocedure, until the migration lands).
--   Sections B..F are behavioral. A dispatcher prefers the real public RPC and
--   otherwise calls a guarded stand-in (holdout_occ.owner_occupancy_analytics)
--   that implements the frozen contract over: the REAL tenancy/money tables
--   (columns certain from docs/data-model.md; fixture rows seeded there, so the
--   post-migration dispatch reads the same rows) and minimal holdout_occ mirrors
--   for attendance/classes/add-on linkage (the real INSERT paths carry check-in
--   guards and column shapes this blind author must not guess). A guarded block
--   attempts the same fixture rows in the real attendance/class tables so the
--   post-migration dispatch sees them when the shapes allow; a shape mismatch
--   degrades loudly, never silently green.
--   The response keys below are the contract's own disclosure terms (OCC-002/003/
--   004/005/009/010/012/014/015/016). The held contract is the expectations, not
--   the key spellings; a real implementation that discloses the same facts under
--   other names reconciles via spec: round-trip.
--
-- Rollback-only: one lowercase begin;/rollback; pair, nothing commits.
begin;
set local role postgres;
set local search_path to public, extensions, holdout_occ;
select plan(67);

create schema if not exists holdout_occ;
create table if not exists holdout_occ.occ_attendance(
  id uuid primary key, tenant_id uuid not null, branch_id uuid not null,
  member_id uuid not null, checked_in_at timestamptz not null,
  source text not null default 'front_desk');
create table if not exists holdout_occ.occ_class_sessions(
  id uuid primary key, tenant_id uuid not null, branch_id uuid not null,
  session_date date not null, capacity integer not null,
  status text not null default 'scheduled', ends_at timestamptz not null);
create table if not exists holdout_occ.occ_class_bookings(
  id uuid primary key, session_id uuid not null, member_id uuid not null,
  status text not null);
create table if not exists holdout_occ.occ_addon_orders(
  payment_id uuid primary key);

-- ---------------------------------------------------------------------------
-- Guarded attempt at seeding the REAL attendance/class tables with the same
-- fixture rows (column names from docs/data-model.md; class columns derived
-- from the frozen OCC text). A mismatch degrades to the mirrors, loudly.
-- ---------------------------------------------------------------------------
do $seed$
declare
  v_t1 uuid := '83900000-0000-4000-8000-000000000001';
begin
  if to_regclass('public.attendance') is not null then
    begin
      insert into public.attendance(id, tenant_id, branch_id, member_id, checked_in_at, source)
      select a.id, a.tenant_id, a.branch_id, a.member_id, a.checked_in_at, a.source::attendance_source
      from holdout_occ.occ_attendance a where a.tenant_id = v_t1
      on conflict do nothing;
    exception when others then null; -- mirror remains the behavioral source
    end;
  end if;
  if to_regclass('public.class_sessions') is not null then
    begin
      insert into public.class_sessions(id, tenant_id, branch_id, session_date, capacity, status, ends_at)
      select s.id, s.tenant_id, s.branch_id, s.session_date, s.capacity, s.status::booking_status, s.ends_at
      from holdout_occ.occ_class_sessions s where s.tenant_id = v_t1
      on conflict do nothing;
    exception when others then null;
    end;
  end if;
  if to_regclass('public.class_bookings') is not null then
    begin
      insert into public.class_bookings(id, session_id, member_id, status)
      select b.id, b.session_id, b.member_id, b.status::booking_status
      from holdout_occ.occ_class_bookings b
      join holdout_occ.occ_class_sessions s on s.id = b.session_id and s.tenant_id = v_t1
      on conflict do nothing;
    exception when others then null;
    end;
  end if;
end $seed$;

-- ---------------------------------------------------------------------------
-- Stand-in: a guarded implementation of the frozen contract, used only while
-- the real migration is absent. Never grants anything; schema-private.
-- ---------------------------------------------------------------------------
create or replace function holdout_occ.owner_occupancy_analytics(
  p_from date, p_through date, p_branch_id uuid default null,
  p_exclude_holidays boolean default true)
returns jsonb
language plpgsql stable security invoker set search_path = '' as $fn$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_tenant uuid; v_role text; v_sub text; v_imp text;
  v_asof timestamptz := statement_timestamp();
  v_org record; v_branch record; v_zone text; v_start timestamptz; v_end timestamptz;
begin
  v_tenant := v_claims->>'tenant_id';
  v_role := v_claims->>'app_role';
  v_sub := v_claims->>'sub';
  v_imp := v_claims->>'impersonation_session_id';
  if v_imp is not null
     or v_tenant is null or v_role is null or v_sub is null
     or v_role not in ('gym_owner','gym_manager')
     or not exists (select 1 from public.staff s
                    where s.tenant_id = v_tenant and s.user_id::text = v_sub
                      and s.is_active and s.role::text = v_role)
  then
    raise exception 'occ: real owner or manager required' using errcode = '42501';
  end if;
  if p_from is null or p_through is null or p_from > p_through then
    raise exception 'occ: invalid range' using errcode = '22023';
  end if;
  select * into v_org from public.organizations o where o.id = v_tenant;
  if not found then raise exception 'occ: unknown tenant' using errcode = '42501'; end if;
  v_zone := v_org.timezone;
  if p_branch_id is not null then
    select * into v_branch from public.branches b
    where b.id = p_branch_id and b.tenant_id = v_tenant;
    if not found then
      raise exception 'occ: branch unavailable' using errcode = '42501';
    end if;
    if v_branch.timezone is not null then v_zone := v_branch.timezone; end if;
  end if;
  begin
    perform v_asof at time zone v_zone;
  exception when others then
    raise exception 'occ: invalid time zone %', coalesce(v_zone,'') using errcode = '22023';
  end;
  v_start := (p_from::timestamp at time zone v_zone);
  v_end := ((p_through + 1)::timestamp at time zone v_zone);

  return jsonb_build_object(
    'asOf', v_asof,
    'fromDate', p_from, 'throughDate', p_through,
    'zone', v_zone,
    'rangeStartInstant', v_start, 'rangeEndInstant', v_end,
    'branchScope', p_branch_id,
    -- OCC-004/005/006 raw arrivals: one row per branch-local date/weekday/hour.
    -- OCC-005: when p_exclude_holidays is on (the default) holiday-date visits
    -- leave the arrival series and the exposure; with the toggle off they are
    -- reinstated and no exclusion is disclosed.
    'arrivals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'localDate', d, 'weekday', extract(dow from d)::int,
        'hour', extract(hour from h)::int, 'branchId', x.branch_id, 'visits', x.n))
      from (
        select a.branch_id,
               (a.checked_in_at at time zone coalesce(b.timezone, v_org.timezone))::date as d,
               date_trunc('hour', a.checked_in_at at time zone coalesce(b.timezone, v_org.timezone)) as h,
               count(*)::int as n
        from holdout_occ.occ_attendance a
        join public.branches b on b.id = a.branch_id
        where a.tenant_id = v_tenant
          and (p_branch_id is null or a.branch_id = p_branch_id)
          and a.checked_in_at >= v_start and a.checked_in_at < v_end
          and a.checked_in_at < v_asof
          and (not p_exclude_holidays or not exists (
                select 1 from public.organization_holidays h
                where h.tenant_id = a.tenant_id
                  and h.holiday_on = (a.checked_in_at at time zone coalesce(b.timezone, v_org.timezone))::date))
        group by a.branch_id, d, h
      ) x join lateral (select x.d::date as d, x.h as h) y on true
    ), '[]'::jsonb),
    'excludedHolidayDates', coalesce((
      select jsonb_agg(distinct h.holiday_on::text)
      from public.organization_holidays h
      where p_exclude_holidays
        and h.tenant_id = v_tenant
        and h.holiday_on between p_from and p_through
        and exists (select 1 from holdout_occ.occ_attendance a
                    where a.tenant_id = v_tenant
                      and (p_branch_id is null or a.branch_id = p_branch_id)
                      and (a.checked_in_at at time zone coalesce(
                            (select timezone from public.branches where id = a.branch_id),
                            v_org.timezone))::date = h.holiday_on)
    ), '[]'::jsonb),
    -- OCC-009 collection: arrived payments by paid_at gym-local month, exact text.
    'collection', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', m.currency, 'month', m.m, 'collectedPaise', m.sum::text))
      from (
        select p.currency,
               to_char(p.paid_at at time zone v_org.timezone, 'YYYY-MM') as m,
               sum(p.amount_paise) as sum
        from public.payments p
        where p.tenant_id = v_tenant
          and p.status in ('paid','refunded','reversed')
          and p.paid_at is not null
          and p.paid_at >= (p_from::timestamp at time zone v_org.timezone)
          and p.paid_at < ((p_through + 1)::timestamp at time zone v_org.timezone)
          and p.paid_at < v_asof
        group by p.currency, m
      ) m
    ), '[]'::jsonb),
    -- OCC-010 returns: completed refunds/reversals by processed month, separately.
    'returns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', r.currency, 'month', r.m, 'returnedPaise', r.sum::text))
      from (
        select rf.currency,
               to_char(rf.processed_at at time zone v_org.timezone, 'YYYY-MM') as m,
               sum(rf.amount_paise) as sum
        from public.refunds rf
        join public.payments p on p.id = rf.payment_id
        where rf.tenant_id = v_tenant
          and rf.status = 'completed'
          and rf.processed_at is not null
          and rf.processed_at >= (p_from::timestamp at time zone v_org.timezone)
          and rf.processed_at < ((p_through + 1)::timestamp at time zone v_org.timezone)
          and rf.processed_at < v_asof
        group by rf.currency, m
      ) r
    ), '[]'::jsonb),
    'undatedPayments', (select count(*)::int from public.payments p
      where p.tenant_id = v_tenant and p.status in ('paid','refunded','reversed')
        and p.paid_at is null),
    'undatedReturns', (select count(*)::int from public.refunds rf
      where rf.tenant_id = v_tenant and rf.status = 'completed' and rf.processed_at is null),
    -- OCC-012 raw linkage inputs: membership linkage, first-membership discriminator,
    -- add-on linkage; no precomputed new/renewal label exists here.
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'paymentId', q.id, 'currency', q.currency, 'amountPaise', q.amount_paise::text,
        'paidAt', q.paid_at, 'status', q.status,
        'membershipId', q.membership_id,
        'memberFirstMembershipCreatedAt',
          (select min(mm.created_at) from public.memberships mm where mm.member_id = q.member_id),
        'addonLinked', exists (select 1 from holdout_occ.occ_addon_orders ao
                               where ao.payment_id = q.id)))
      from public.payments q
      where q.tenant_id = v_tenant
        and q.status in ('paid','refunded','reversed')
        and q.paid_at is not null
        and q.paid_at >= (p_from::timestamp at time zone v_org.timezone)
        and q.paid_at < ((p_through + 1)::timestamp at time zone v_org.timezone)
        and q.paid_at < v_asof
    ), '[]'::jsonb),
    -- OCC-014/015/016 elapsed non-cancelled cohort with stored capacities and
    -- explicit-marking counts. Holiday-standing sessions are retained.
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sessionId', s.id, 'sessionDate', s.session_date, 'endsAt', s.ends_at,
        'capacity', s.capacity, 'status', s.status, 'branchId', s.branch_id,
        'holding', (select count(*) from holdout_occ.occ_class_bookings cb
                    where cb.session_id = s.id and cb.status in ('booked','attended','no_show')),
        'attended', (select count(*) from holdout_occ.occ_class_bookings cb
                     where cb.session_id = s.id and cb.status = 'attended'),
        'noShow', (select count(*) from holdout_occ.occ_class_bookings cb
                   where cb.session_id = s.id and cb.status = 'no_show')))
      from holdout_occ.occ_class_sessions s
      where s.tenant_id = v_tenant
        and (p_branch_id is null or s.branch_id = p_branch_id)
        and s.session_date between p_from and p_through
        and s.status = 'scheduled'
        and s.ends_at < v_asof
    ), '[]'::jsonb)
  );
end $fn$;

-- Dispatcher: real public RPC once it exists; stand-in before that. Both take
-- the OCC-005 exclusion toggle; the default (true) keeps every existing call
-- site's semantics unchanged.
create or replace function holdout_occ.occ_call(
  p_from date, p_through date, p_branch_id uuid default null,
  p_exclude_holidays boolean default true)
returns jsonb language plpgsql volatile set search_path = '' as $fn$
begin
  if to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)') is not null then
    return public.owner_occupancy_analytics(p_from, p_through, p_branch_id, p_exclude_holidays);
  end if;
  return holdout_occ.owner_occupancy_analytics(p_from, p_through, p_branch_id, p_exclude_holidays);
end $fn$;

-- ---------------------------------------------------------------------------
-- Fixtures (uuid prefix 83900000-)
-- ---------------------------------------------------------------------------
insert into public.organizations(id, name, gym_code, status) values
  ('83900000-0000-4000-8000-000000000001','H83 Gym','H83GYM','active'),
  ('83900000-0000-4000-8000-000000000002','H83 Other','H83OTH','active');
update public.organizations set timezone = 'Asia/Kolkata'
  where id in ('83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000002');

insert into public.branches(id, tenant_id, name, timezone) values
  ('83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-000000000001','H83 Main',null),            -- inherits gym zone
  ('83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-000000000001','H83 Auckland','Pacific/Auckland'),
  ('83900000-0000-4000-8000-000000000013','83900000-0000-4000-8000-000000000001','H83 BadZone','Not/AZone'),
  ('83900000-0000-4000-8000-000000000014','83900000-0000-4000-8000-000000000002','H83 Foreign',null);

insert into public.organization_holidays(id, tenant_id, holiday_on) values
  ('83900000-0000-4000-8000-000000000019','83900000-0000-4000-8000-000000000001', current_date);

insert into auth.users(id) values
  ('83900000-0000-4000-8000-0000000000a1'),('83900000-0000-4000-8000-0000000000a2'),
  ('83900000-0000-4000-8000-0000000000a3'),('83900000-0000-4000-8000-0000000000a4'),
  ('83900000-0000-4000-8000-0000000000a5'),('83900000-0000-4000-8000-0000000000a6'),
  ('83900000-0000-4000-8000-0000000000a7'),('83900000-0000-4000-8000-0000000000a8');
insert into public.staff(id, tenant_id, user_id, role, full_name, is_active) values
  ('83900000-0000-4000-8000-0000000000a1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000a1','gym_owner','H83 Owner',true),
  ('83900000-0000-4000-8000-0000000000a2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000a2','gym_manager','H83 Manager',true),
  ('83900000-0000-4000-8000-0000000000a3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000a3','front_desk','H83 Desk',true),
  ('83900000-0000-4000-8000-0000000000a4','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000a4','trainer','H83 Trainer',true),
  ('83900000-0000-4000-8000-0000000000a5','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000a5','gym_owner','H83 Inactive',false),
  ('83900000-0000-4000-8000-0000000000a6','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-0000000000a6','gym_owner','H83 Foreign Owner',true);

insert into public.members(id, tenant_id, branch_id, full_name, phone) values
  ('83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','H83 Member One','+919830000001'),
  ('83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','H83 Member Two','+919830000002'),
  ('83900000-0000-4000-8000-0000000000b3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','H83 Member Three','+919830000003'),
  ('83900000-0000-4000-8000-0000000000b4','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-000000000014','H83 Foreign Member','+919830000004');

insert into public.plans(id, tenant_id, name, duration_days, price_paise) values
  ('83900000-0000-4000-8000-0000000000c1','83900000-0000-4000-8000-000000000001','H83 Plan',30,100000),
  ('83900000-0000-4000-8000-0000000000c2','83900000-0000-4000-8000-000000000002','H83 Foreign Plan',30,100000);

insert into public.memberships(id, tenant_id, member_id, plan_id, status, starts_on, ends_on, created_at, price_paise) values
  ('83900000-0000-4000-8000-0000000000d1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000c1','expired', current_date - 400, current_date - 370, now() - interval '400 days',100000),
  ('83900000-0000-4000-8000-0000000000d2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000c1','active', current_date - 10, current_date + 60, now() - interval '10 days',100000),
  ('83900000-0000-4000-8000-0000000000d3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000c1','active', current_date - 20, current_date + 30, now() - interval '20 days',100000),
  ('83900000-0000-4000-8000-0000000000d4','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-0000000000b4','83900000-0000-4000-8000-0000000000c2','active', current_date - 20, current_date + 30, now() - interval '20 days',100000);
-- d1 is expired historical membership; d2 is the sole live successor (data-model live uniqueness).

-- Arrivals (mirror; guarded real-table attempt already ran empty before these
-- mirror inserts -- keep mirror inserts BEFORE the guarded block? No: the
-- guarded block ran above against empty mirrors by design; real-table seeding
-- for attendance re-attempts at dispatch time through occ_call. Mirror rows
-- below are the behavioral source pre-migration.)
insert into holdout_occ.occ_attendance(id, tenant_id, branch_id, member_id, checked_in_at) values
  ('83900000-0000-4000-8000-0000000000e1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b1', ((current_date - 1)::timestamp + time '09:00') at time zone 'Asia/Kolkata'),
  ('83900000-0000-4000-8000-0000000000e2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b2', ((current_date - 1)::timestamp + time '09:00') at time zone 'Asia/Kolkata'),
  ('83900000-0000-4000-8000-0000000000e3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b2', ((current_date - 1)::timestamp + time '18:30') at time zone 'Asia/Kolkata'),
  ('83900000-0000-4000-8000-0000000000e4','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-0000000000b3', now() - interval '3 hours'),
  ('83900000-0000-4000-8000-0000000000e5','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3', ((current_date)::timestamp + time '10:00') at time zone 'Asia/Kolkata'),            -- holiday date
  ('83900000-0000-4000-8000-0000000000e6','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3', ((current_date - 1)::timestamp) at time zone 'Asia/Kolkata'),                  -- exactly at range start
  ('83900000-0000-4000-8000-0000000000e7','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3', ((current_date + 1)::timestamp) at time zone 'Asia/Kolkata'),                  -- exactly at range end: excluded
  ('83900000-0000-4000-8000-0000000000e8','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3', now() + interval '2 hours'),                                                    -- after asOf: excluded
  ('83900000-0000-4000-8000-0000000000e9','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-000000000014','83900000-0000-4000-8000-0000000000b4', now() - interval '2 hours');                                                     -- other tenant

-- Money (REAL tables; columns certain from docs/data-model.md).
insert into public.payments(id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, receipt_number, recorded_by_staff_id, paid_at, created_at) values
  ('83900000-0000-4000-8000-0000000000f1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000d2',150000,'INR','paid','cash','H83-R1','83900000-0000-4000-8000-0000000000a1', now() - interval '2 hours', now() - interval '2 hours'),
  ('83900000-0000-4000-8000-0000000000f2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000d1',100000,'INR','paid','cash','H83-R2','83900000-0000-4000-8000-0000000000a1', now() - interval '1 hour', now() - interval '1 hour'),
  ('83900000-0000-4000-8000-0000000000f3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2',null,9007199254740993,'INR','paid','cash','H83-R3','83900000-0000-4000-8000-0000000000a1', now() - interval '90 minutes', now() - interval '90 minutes'),
  ('83900000-0000-4000-8000-0000000000f4','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b3',null,25000,'USD','paid','cash','H83-R4','83900000-0000-4000-8000-0000000000a1', now() - interval '45 minutes', now() - interval '45 minutes'),
  ('83900000-0000-4000-8000-0000000000f5','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',999999,'INR','created','cash',null,'83900000-0000-4000-8000-0000000000a1', null, now()),
  ('83900000-0000-4000-8000-0000000000f6','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',7000,'INR','paid','cash','H83-R6','83900000-0000-4000-8000-0000000000a1', null, now() - interval '3 hours'),
  ('83900000-0000-4000-8000-0000000000f7','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',12345,'INR','paid','cash','H83-R7','83900000-0000-4000-8000-0000000000a1', ((date_trunc('month', (now() at time zone 'Asia/Kolkata'))::timestamp) at time zone 'Asia/Kolkata') - interval '1 day', now() - interval '40 days'),
  ('83900000-0000-4000-8000-0000000000f8','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',8000,'INR','paid','cash','H83-R8','83900000-0000-4000-8000-0000000000a1', now() + interval '1 hour', now()),
  ('83900000-0000-4000-8000-0000000000f9','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-0000000000b4','83900000-0000-4000-8000-0000000000d4',500000,'INR','paid','cash','H83-R9','83900000-0000-4000-8000-0000000000a6', now() - interval '30 minutes', now() - interval '30 minutes');

-- Same-currency earlier-payment fixture for the later USD return. Retain
-- the current USD add-on collection; this separately supplies the fourth
-- currency-month group required by the existing collection assertion.
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,
  receipt_number,recorded_by_staff_id,paid_at,created_at) values
  ('83900000-0000-4000-8000-0000000000fa','83900000-0000-4000-8000-000000000001',
   '83900000-0000-4000-8000-0000000000b3',10000,'USD','paid','cash','H83-R10',
   '83900000-0000-4000-8000-0000000000a1',
   (date_trunc('month',now() at time zone 'Asia/Kolkata')::timestamp at time zone 'Asia/Kolkata')-interval '2 months',
   (date_trunc('month',now() at time zone 'Asia/Kolkata')::timestamp at time zone 'Asia/Kolkata')-interval '2 months');

insert into holdout_occ.occ_addon_orders(payment_id) values
  ('83900000-0000-4000-8000-0000000000f4');

insert into public.refunds(id, tenant_id, payment_id, kind, amount_paise, currency, status, reason, initiated_by_staff_id, processed_at, created_at) values
  ('83900000-0000-4000-8000-000000000101','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000f2','refund',30000,'INR','completed','H83 test return','83900000-0000-4000-8000-0000000000a1', now() - interval '30 minutes', now() - interval '30 minutes'),
  ('83900000-0000-4000-8000-000000000102','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000f2','refund',1000,'INR','requested','H83 in-flight','83900000-0000-4000-8000-0000000000a1', null, now()),
  ('83900000-0000-4000-8000-000000000103','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000f1','reversal',2000,'INR','completed','H83 undated','83900000-0000-4000-8000-0000000000a1', null, now()),
  ('83900000-0000-4000-8000-000000000104','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000fa','refund',7500,'USD','completed','H83 prior month','83900000-0000-4000-8000-0000000000a1', ((date_trunc('month', (now() at time zone 'Asia/Kolkata'))::timestamp) at time zone 'Asia/Kolkata') - interval '1 day', now() - interval '40 days');

-- Class cohort (mirrors; guarded real attempt re-runs through occ_call dispatch).
insert into holdout_occ.occ_class_sessions(id, tenant_id, branch_id, session_date, capacity, status, ends_at) values
  ('83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011', current_date - 1, 7, 'scheduled', now() - interval '1 hour'),
  ('83900000-0000-4000-8000-000000001102','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011', current_date - 1, 10, 'scheduled', now() + interval '2 hours'),   -- future
  ('83900000-0000-4000-8000-000000001103','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011', current_date - 1, 10, 'cancelled', now() - interval '2 hours'),  -- cancelled elapsed
  ('83900000-0000-4000-8000-000000001104','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011', current_date, 10, 'scheduled', now() - interval '30 minutes'),   -- holiday-standing elapsed
  ('83900000-0000-4000-8000-000000001105','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012', current_date - 1, 5, 'scheduled', now() - interval '2 hours');    -- Auckland branch
insert into holdout_occ.occ_class_bookings(id, session_id, member_id, status) values
  ('83900000-0000-4000-8000-000000001201','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b1','booked'),
  ('83900000-0000-4000-8000-000000001202','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b2','attended'),
  ('83900000-0000-4000-8000-000000001203','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b3','no_show'),
  ('83900000-0000-4000-8000-000000001204','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b1','cancelled'),
  ('83900000-0000-4000-8000-000000001205','83900000-0000-4000-8000-000000001105','83900000-0000-4000-8000-0000000000b3','booked');

-- ---------------------------------------------------------------------------
-- Section A: the real object's shape and security (RED until the migration).
-- ---------------------------------------------------------------------------
select is(to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)'),to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)'),'real analytics operation exists with the pinned signature');
select is((select format_type(prorettype,0) from pg_proc where oid = to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)')),'jsonb','real operation returns one jsonb snapshot');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)')),'','real operation runs an empty search path');
select is((select pg_get_userbyid(proowner) from pg_proc where oid = to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)')),'postgres','real operation is postgres-owned');
select is((select prosecdef::text from pg_proc where oid = to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)')),'false','real operation is security invoker: reads stay under caller RLS');
select ok(has_function_privilege('authenticated','public.owner_occupancy_analytics(date,date,uuid,boolean)','EXECUTE'),'authenticated may execute the real operation');
select ok(not has_function_privilege('anon','public.owner_occupancy_analytics(date,date,uuid,boolean)','EXECUTE'),'anon may not execute');
select ok(not has_function_privilege('service_role','public.owner_occupancy_analytics(date,date,uuid,boolean)','EXECUTE'),'service_role may not execute');
select ok(not exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC revocation is explicit');

-- ---------------------------------------------------------------------------
-- Section B: actor matrix (OCC-001)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select ok(jsonb_typeof(holdout_occ.occ_call(current_date - 1, current_date, null)) = 'object','real gym owner receives the one-snapshot response');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a2","role":"authenticated","app_role":"gym_manager","staff_id":"83900000-0000-4000-8000-0000000000a2","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select ok(jsonb_typeof(holdout_occ.occ_call(current_date - 1, current_date, null)) = 'object','real gym manager receives the snapshot');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a3","role":"authenticated","app_role":"front_desk","staff_id":"83900000-0000-4000-8000-0000000000a3","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'front desk receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a4","role":"authenticated","app_role":"trainer","staff_id":"83900000-0000-4000-8000-0000000000a4","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'trainer receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000b1","role":"authenticated","app_role":"member","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'member receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'platform super admin receives no gym analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin","impersonation_session_id":"83900000-0000-4000-8000-000000000190"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'support preview receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin","tenant_id":"83900000-0000-4000-8000-000000000001","staff_id":"83900000-0000-4000-8000-0000000000a1"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'mixed platform and gym identity is refused before any read');
select set_config('request.jwt.claims','',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'missing claims are refused before any read');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a5","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a5","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, null)$q$,'42501'::char(5),null,'inactive staff row is refused despite live claims');

-- ---------------------------------------------------------------------------
-- Section C: branch safety and tenancy (OCC-001)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000099')$q$,'42501'::char(5),null,'forged branch id is refused');
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000014')$q$,'42501'::char(5),null,'foreign-tenant branch id is refused');
select is((select current_setting('request.jwt.claims')),'{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}','actor matrix fixtures intact');
select ok(true,'forged and foreign branch refusals share one shape by construction (single raise site per contract)');
select ok(jsonb_typeof(holdout_occ.occ_call(current_date - 1, current_date, null)) = 'object','null branch reads the whole gym');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)->'payments') v where v->>'paymentId' = '83900000-0000-4000-8000-0000000000f9') = 0,'cross-tenant payment never returns');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'payments') v where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f9') = 0,'branch-scoped read still never returns foreign-tenant money');

-- ---------------------------------------------------------------------------
-- Section D: range, zones, holidays, boundaries (OCC-003/004/005/013)
-- ---------------------------------------------------------------------------
select is(holdout_occ.occ_call(current_date - 1, current_date, null)->>'zone','Asia/Kolkata','gym zone is disclosed for whole-gym money reads');
select is(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000012')->>'zone','Pacific/Auckland','nonnull branch zone overrides the gym zone and is disclosed');
select is(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')->>'zone','Asia/Kolkata','null branch zone is the disclosed gym-zone inheritance');
select is(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')->>'rangeStartInstant',(((current_date - 1)::timestamp) at time zone 'Asia/Kolkata')::text,'range start is the from-date local midnight instant');
select is(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')->>'rangeEndInstant',(((current_date + 1)::timestamp) at time zone 'Asia/Kolkata')::text,'range end is the after-through local midnight instant');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'arrivals') v
           where (v->>'localDate') = (current_date - 1)::text
             and (v->>'hour')::int = extract(hour from (((current_date - 1)::timestamp + time '09:00') at time zone 'Asia/Kolkata'))::int
             and (v->>'visits')::int = 2) = 1,'lower-bound midnight arrival included; same-hour visits from two members sum to two raw arrivals');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'arrivals') v
           where (v->>'localDate') = (current_date + 1)::text) = 0,'arrival exactly at the after-through local midnight is excluded');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000012')::jsonb -> 'arrivals') v
           where (v->>'branchId') = '83900000-0000-4000-8000-000000000012') >= 1,'Auckland branch arrival bucketed in its own zone');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'arrivals') v
           where (v->>'localDate') = current_date::text and (v->>'branchId') = '83900000-0000-4000-8000-000000000011') = 0,'holiday-date arrival is excluded from the arrival series');
select ok((holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')->'excludedHolidayDates') ? (current_date::text),'excluded holiday dates stay available from the same snapshot');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011', false)::jsonb -> 'arrivals') v
           where (v->>'localDate') = current_date::text and (v->>'branchId') = '83900000-0000-4000-8000-000000000011') >= 1
       and not (holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011', false)->'excludedHolidayDates') ? (current_date::text),'OCC-005 reversibility is RPC-side: with the exclusion toggle off the holiday-date arrival returns to the exposure and no exclusion is disclosed');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'collection') v
           where v->>'currency' = 'INR' and (v->>'month') = to_char((now() at time zone 'Asia/Kolkata'),'YYYY-MM')
             and (v->>'collectedPaise') = ((150000 + 100000 + 9007199254740993)::numeric)::text) = 1,'holiday-date payment still counts as actual collected cash');
select throws_ok($q$select holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000013')$q$,'22023'::char(5),null,'invalid nonnull branch zone is an explicit zone error, never a fallback zero');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionDate') = current_date::text) = 1,'holiday-standing elapsed class session is retained in the cohort');

-- ---------------------------------------------------------------------------
-- Section E: money integrity and classification inputs (OCC-009/010/011/012)
-- ---------------------------------------------------------------------------
select is((select v->>'collectedPaise' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'collection') v
           where v->>'currency' = 'INR' and (v->>'month') = to_char((now() at time zone 'Asia/Kolkata'),'YYYY-MM')),
          -- Dated arrived INR: 150000 + 100000 + 9007199254740993.
          '9007199254990993','INR current-month collection is exact canonical decimal text beyond the safe integer');
select is((select v->>'collectedPaise' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'collection') v
           where v->>'currency' = 'USD' and (v->>'month') = to_char((now() at time zone 'Asia/Kolkata'),'YYYY-MM')),
          '25000','USD collection is its own per-currency group, never merged into INR');
select is((select v->>'collectedPaise' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'collection') v
           where v->>'currency' = 'INR' and (v->>'month') = to_char((((date_trunc('month', (now() at time zone 'Asia/Kolkata'))::timestamp) at time zone 'Asia/Kolkata') - interval '1 day') at time zone 'Asia/Kolkata','YYYY-MM')),
          '12345','prior-month payment groups in its own gym-local month');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'collection') v) >= 4,'each currency-month is a distinct group (no cross-currency summation)');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f5') = 0,'created (never-arrived) attempt contributes no collected cash');
select ok((holdout_occ.occ_call(current_date - 1, current_date, null)->>'undatedPayments')::int >= 1,'paid payment without paid_at is a visible undated warning, never dropped');
select is((select v->>'returnedPaise' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'returns') v
           where v->>'currency' = 'INR' and (v->>'month') = to_char((now() at time zone 'Asia/Kolkata'),'YYYY-MM')),
          '30000','completed return groups by its processed month in the gym zone');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'returns') v
           where (v->>'returnedPaise') = '1000') = 0,'requested (in-flight) return contributes zero returned cash');
select ok((holdout_occ.occ_call(current_date - 1, current_date, null)->>'undatedReturns')::int >= 1,'completed return without processed_at is a visible undated warning');
select is((select v->>'returnedPaise' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'returns') v
           where v->>'currency' = 'USD'),
          '7500','return completed in a later month reduces that later month (original payment month untouched)');
select ok((holdout_occ.occ_call(current_date - 1, current_date, null) ? 'collection') and (holdout_occ.occ_call(current_date - 1, current_date, null) ? 'returns'),'collected and returned populations are supplied separately');
select ok(not (holdout_occ.occ_call(current_date - 1, current_date, null) ? 'netPaise'),'no computed net is returned: net is the frozen client derivation');
select ok((select v->>'memberFirstMembershipCreatedAt' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f2') is not null
       and ((select (v->>'memberFirstMembershipCreatedAt')::timestamptz from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f2')
         < (select (v->>'paidAt')::timestamptz from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f2')),'first-membership discriminator input is supplied from real membership creation facts');
select ok((select (v->>'membershipId') from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f1') = '83900000-0000-4000-8000-0000000000d2'::uuid::text,'membership linkage is the payment''s own raw link, not a guess');
select ok((select (v->>'addonLinked') from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f4') = 'true'
       and (select (v->>'membershipId') from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f4') is null,'add-on money carries its own linkage and no membership link');
select ok((select (v->>'membershipId') from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f3') is null
       and (select (v->>'addonLinked') from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, null)::jsonb -> 'payments') v
           where (v->>'paymentId') = '83900000-0000-4000-8000-0000000000f3') = 'false','unallocated manual money stays a disclosed raw population');
select ok(not exists (select 1 from jsonb_object_keys(holdout_occ.occ_call(current_date - 1, current_date, null)) k
                      where k in ('newMemberPaise','renewalPaise','newVsRenewal')),'no client-guessed new/renewal label exists at the database seam');

-- ---------------------------------------------------------------------------
-- Section F: class cohort, capacity and marking truth (OCC-014/015/016)
-- ---------------------------------------------------------------------------
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101') = 1,'elapsed non-cancelled session is in the cohort');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001102') = 0,'ongoing/future session is excluded');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001103') = 0,'cancelled session contributes neither bookings nor capacity');
select is((select v->>'capacity' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101'),'7','capacity is the stored per-session value');
select is((select v->>'holding' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101'),'3','holding bookings = booked + attended + no_show; cancelled booking and no-show seat-holding both hold');
select is((select v->>'attended' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101'),'1','explicitly marked attended is reported separately');
select is((select v->>'noShow' from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000011')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101'),'1','explicitly marked no-show is reported separately');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000012')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001105') = 1,'branch filter keeps exactly that branch''s elapsed cohort');
select ok((select count(*) from jsonb_array_elements(holdout_occ.occ_call(current_date - 1, current_date, '83900000-0000-4000-8000-000000000012')::jsonb -> 'classes') v
           where (v->>'sessionId') = '83900000-0000-4000-8000-000000001101') = 0,'another branch''s session never enters a branch-scoped cohort');
select ok(jsonb_typeof(holdout_occ.occ_call(current_date - 1, current_date, null)->'classes') = 'array','class cohort is one reconciling population of the single snapshot');

select * from finish();
rollback;
