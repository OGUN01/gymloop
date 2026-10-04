-- Independent holdout repair 2026-10-04: fallback elimination.
-- Authored from the frozen public contract ONLY (OCC-001..017 in
-- openspec/changes/occupancy-analytics/proposal.md, the frozen
-- sql-envelope-declaration.md, docs/design/v2/occ-bar.md). No implementation,
-- migration, visible suite, other holdout, registry or private diagnostic was
-- read; docs/data-model.md was not consulted either, so real-table column
-- guesses for attendance/class staging are exception-swallowed with an
-- explicit staging-health assertion (loud, never silently green).
--
-- Repair of the prior revision: the private stand-in mirror
-- (holdout_occ.owner_occupancy_analytics) and the occ_call dispatcher are
-- REMOVED. Every behavioral assertion below invokes the real four-argument
-- public RPC `public.owner_occupancy_analytics(date,date,uuid,boolean)`
-- directly under real caller identity. If the real call fails, the suite
-- fails; no helper-built aggregate, mirror selector or separately refreshed
-- drill proves anything here.
--
-- Snapshots are materialized ONCE per named capture into pg_temp.h83_snap so
-- every extracted value provably comes from one returned JSON object
-- (OCC-002). Refusal checks execute direct calls.
--
-- Rollback-only: one lowercase begin;/rollback; pair, nothing commits.
begin;
set local role postgres;
set local time zone 'Asia/Kolkata';
set local search_path = extensions, public;
select set_config('request.jwt.claims','',true);
select plan(185);

-- Snapshot/error temp tables are created BEFORE any helper function body,
-- because language-SQL helper bodies are validated at CREATE time and would
-- fail with 42P01 if they referenced a not-yet-created relation.
create temp table h83_snap(k text primary key, r jsonb not null);
create temp table h83_seed_errors(line text not null);
grant select, insert on pg_temp.h83_snap to authenticated;
grant select on pg_temp.h83_seed_errors to authenticated;

-- ---------------------------------------------------------------- helpers
create function pg_temp.snap(k text) returns jsonb language sql as $f$
  select r from pg_temp.h83_snap where h83_snap.k = $1
$f$;

create function pg_temp.branch(js jsonb, bid text) returns jsonb language sql as $f$
  select b from jsonb_array_elements(js) b
  where b->>'branchId' = $2 limit 1
$f$;

create function pg_temp.cell(js jsonb, wd int, hr int) returns jsonb language sql as $f$
  select c from jsonb_array_elements(js) c
  where (c->>'weekday')::int = $2 and (c->>'hour')::int = $3 limit 1
$f$;

create function pg_temp.day(js jsonb, d date) returns jsonb language sql as $f$
  select x from jsonb_array_elements(js) x
  where x->>'localDate' = $1::text limit 1
$f$;

create function pg_temp.sess(js jsonb, sid text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(js) x
  where x->>'sessionId' = $2 limit 1
$f$;

create function pg_temp.cash(js jsonb, cur text) returns jsonb language sql as $f$
  select c from jsonb_array_elements(js) c
  where c->>'currency' = $2 limit 1
$f$;

-- The frozen categories shape is an OBJECT: {label, newMember, renewal,
-- addon, unallocated}, each category {collectedPaise,returnedPaise,netPaise}
-- (+ unknownReturnPaise on unallocated only). The helper returns the
-- categories object only when its carried label matches the declared string,
-- so a divergent label surfaces as null and fails the assertions loudly.
create function pg_temp.cat(cash_row jsonb, label text) returns jsonb language sql as $f$
  select case when cash_row->'categories'->>'label' = $2 then cash_row->'categories' end
$f$;

create function pg_temp.pay(js jsonb, pid text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(js) x
  where x->>'paymentId' = $2 limit 1
$f$;

create function pg_temp.ret(js jsonb, rid text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(js) x
  where x->>'returnId' = $2 limit 1
$f$;

-- Exception-safe real-RPC capture: a failing real call is recorded as an
-- __error__ snapshot (surfaced by the health assertion) instead of aborting
-- the whole rollback-only transaction before any TAP is emitted.
create function pg_temp.capture(k text, fn date, td date, br uuid, ex boolean) returns void language plpgsql as $f$
begin
  begin
    insert into pg_temp.h83_snap values (k, public.owner_occupancy_analytics(fn, td, br, ex));
  exception when others then
    insert into pg_temp.h83_snap values (k, jsonb_build_object('__error__', SQLSTATE || ':' || SQLERRM));
  end;
end $f$;

-- ---------------------------------------------------------------- fixtures
-- The commercial trigger's INSERT branch validates the domain (non-empty
-- name, zone in pg_timezone_names, currency INR), so every organization
-- fixture row is inserted with explicit lawful values; no NULL-zone default.
insert into public.organizations(id, name, gym_code, status, timezone, currency) values
  ('83900000-0000-4000-8000-000000000001','H83 Gym','H83GYM','active','Asia/Kolkata','INR'),
  ('83900000-0000-4000-8000-000000000002','H83 Other','H83OTH','active','Asia/Kolkata','INR');
update public.organizations set timezone = 'Asia/Kolkata'
  where id in ('83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000002');

insert into public.branches(id, tenant_id, name, timezone) values
  ('83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-000000000001','H83 Main',null),            -- inherits gym zone
  ('83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-000000000001','H83 Auckland','Pacific/Auckland'),
  ('83900000-0000-4000-8000-000000000013','83900000-0000-4000-8000-000000000001','H83 BadZone','Not/AZone'),
  ('83900000-0000-4000-8000-000000000014','83900000-0000-4000-8000-000000000002','H83 Foreign',null);

-- Holidays: today (main-range exclusion) and 2026-09-21/22 (all-holiday range).
insert into public.organization_holidays(id, tenant_id, holiday_on) values
  ('83900000-0000-4000-8000-000000000019','83900000-0000-4000-8000-000000000001', current_date),
  ('83900000-0000-4000-8000-00000000001a','83900000-0000-4000-8000-000000000001', date '2026-09-21'),
  ('83900000-0000-4000-8000-00000000001b','83900000-0000-4000-8000-000000000001', date '2026-09-22');

insert into auth.users(id) values
  ('83900000-0000-4000-8000-0000000000a1'),('83900000-0000-4000-8000-0000000000a2'),
  ('83900000-0000-4000-8000-0000000000a3'),('83900000-0000-4000-8000-0000000000a4'),
  ('83900000-0000-4000-8000-0000000000a5'),('83900000-0000-4000-8000-0000000000a6'),
  ('83900000-0000-4000-8000-0000000000a8');
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
  -- d0: EQUAL created_at sibling for member b2 (id sorts BEFORE d3). Equal
  -- timestamps are not earlier per the frozen rule; no id tie-break is
  -- permitted, so d3 must still classify newMember.
  ('83900000-0000-4000-8000-0000000000d0','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000c1','expired', current_date - 25, current_date - 5, now() - interval '20 days',100000),
  ('83900000-0000-4000-8000-0000000000d4','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-0000000000b4','83900000-0000-4000-8000-0000000000c2','active', current_date - 20, current_date + 30, now() - interval '20 days',100000);

insert into public.payments(id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, receipt_number, recorded_by_staff_id, paid_at, created_at) values
  -- f1 -> d2 (b1's second membership) = renewal, in range.
  ('83900000-0000-4000-8000-0000000000f1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000d2',150000,'INR','paid','cash','H83-R1','83900000-0000-4000-8000-0000000000a1', now() - interval '2 hours', now() - interval '2 hours'),
  -- f2 -> d1 (b1's first membership) = newMember; carries the in-range completed return.
  ('83900000-0000-4000-8000-0000000000f2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b1','83900000-0000-4000-8000-0000000000d1',100000,'INR','paid','cash','H83-R2','83900000-0000-4000-8000-0000000000a1', now() - interval '1 hour', now() - interval '1 hour'),
  -- f3 unlinked, exact value beyond the safe JS integer.
  ('83900000-0000-4000-8000-0000000000f3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2',null,9007199254740993,'INR','paid','cash','H83-R3','83900000-0000-4000-8000-0000000000a1', now() - interval '90 minutes', now() - interval '90 minutes'),
  -- f4 add-on-linked USD.
  ('83900000-0000-4000-8000-0000000000f4','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b3',null,25000,'USD','paid','cash','H83-R4','83900000-0000-4000-8000-0000000000a1', now() - interval '45 minutes', now() - interval '45 minutes'),
  -- f5 created (never arrived): no cash, not even a warning.
  ('83900000-0000-4000-8000-0000000000f5','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',999999,'INR','created','cash',null,'83900000-0000-4000-8000-0000000000a1', null, now()),
  -- f6 arrived paid without paid_at: undated warning only.
  ('83900000-0000-4000-8000-0000000000f6','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',7000,'INR','paid','cash','H83-R6','83900000-0000-4000-8000-0000000000a1', null, now() - interval '3 hours'),
  -- f7 prior-month dated payment (outside the selected range; must not leak in).
  ('83900000-0000-4000-8000-0000000000f7','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',12345,'INR','paid','cash','H83-R7','83900000-0000-4000-8000-0000000000a1', ((date_trunc('month', (now() at time zone 'Asia/Kolkata'))::timestamp) at time zone 'Asia/Kolkata') - interval '1 day', now() - interval '40 days'),
  -- f8 paid after asOf: excluded.
  ('83900000-0000-4000-8000-0000000000f8','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',8000,'INR','paid','cash','H83-R8','83900000-0000-4000-8000-0000000000a1', now() + interval '1 hour', now()),
  -- f9 other tenant.
  ('83900000-0000-4000-8000-0000000000f9','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-0000000000b4','83900000-0000-4000-8000-0000000000d4',500000,'INR','paid','cash','H83-R9','83900000-0000-4000-8000-0000000000a6', now() - interval '30 minutes', now() - interval '30 minutes'),
  -- fb -> d3 dated, in range: pins the equal-created_at no-earlier rule.
  ('83900000-0000-4000-8000-0000000000fb','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b2','83900000-0000-4000-8000-0000000000d3',5000,'INR','paid','cash','H83-RB','83900000-0000-4000-8000-0000000000a1', now() - interval '4 hours', now() - interval '4 hours'),
  -- fa unlinked USD paid two months back (outside every selected range); its
  -- completed return below lands INSIDE the main range -> later-month net.
  ('83900000-0000-4000-8000-0000000000fa','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b3',null,10000,'USD','paid','cash','H83-RA','83900000-0000-4000-8000-0000000000a1',
   (date_trunc('month',now() at time zone 'Asia/Kolkata')::timestamp at time zone 'Asia/Kolkata')-interval '2 months',
   (date_trunc('month',now() at time zone 'Asia/Kolkata')::timestamp at time zone 'Asia/Kolkata')-interval '2 months');

-- f4's add-on classification requires a lawful real add-on order linked to the
-- payment; this blind author must not guess the full order shape, so a minimal
-- guarded attempt stages it and any shape mismatch lands in h83_seed_errors
-- (surfaced by the staging-health assertion) — the disclosed-category
-- assertions below then fail loudly instead of silently passing.
create temp table h83_addon_links(payment_id uuid primary key);
insert into h83_addon_links(payment_id) values ('83900000-0000-4000-8000-0000000000f4');

insert into public.refunds(id, tenant_id, payment_id, kind, amount_paise, currency, status, reason, initiated_by_staff_id, processed_at, created_at) values
  -- r101 completed in-range return of f2 (newMember receipt).
  ('83900000-0000-4000-8000-000000000101','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000f2','refund',30000,'INR','completed','H83 test return','83900000-0000-4000-8000-0000000000a1', now() - interval '30 minutes', now() - interval '30 minutes'),
  -- r102 requested (in-flight): contributes zero returned cash.
  ('83900000-0000-4000-8000-000000000102','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000f2','refund',1000,'INR','requested','H83 in-flight','83900000-0000-4000-8000-0000000000a1', null, now()),
  -- r103 removed per the 2026-10-04 adjudication: a COMPLETED return with a
  -- null processed_at is unreachable (the phase6 refund guard couples the two
  -- in both directions), so there is no lawful undated-return fixture.
  -- r104 completed USD return inside the main range; original fa outside it;
  -- unallocated receipt -> allocationUnknown true.
  ('83900000-0000-4000-8000-000000000104','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000fa','refund',7500,'USD','completed','H83 prior sale','83900000-0000-4000-8000-0000000000a1', now() - interval '30 minutes', now() - interval '30 minutes');

-- Arrivals. Real-table staging is exception-swallowed with a loud health
-- assertion; the values below are the contract-required facts.
do $seed$
begin
  begin
    -- Lawful member-gate provenance: attendance_source is 'qr' (member gate);
    -- source is NOT NULL and front_desk would additionally require staff+reason.
    -- Lawful member-gate provenance: attendance_source is 'qr' (member gate);
    -- source is NOT NULL, and front_desk would additionally require the staff
    -- + reason pair. The staged facts and timestamps are unchanged.
    insert into public.attendance(id, tenant_id, branch_id, member_id, source, checked_in_at) values
      -- Main branch (Kolkata), yesterday: two members at 09:00, the first
      -- member AGAIN at 09:30 (two accepted visits by one member count twice),
      -- one at 18:30, one exactly at the range-start local midnight.
      ('83900000-0000-4000-8000-0000000000e1','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b1','qr', ((current_date - 1)::timestamp + time '09:00') at time zone 'Asia/Kolkata'),
      ('83900000-0000-4000-8000-0000000000e2','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b2','qr', ((current_date - 1)::timestamp + time '09:00') at time zone 'Asia/Kolkata'),
      ('83900000-0000-4000-8000-000000000e10','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b1','qr', ((current_date - 1)::timestamp + time '09:30') at time zone 'Asia/Kolkata'),
      ('83900000-0000-4000-8000-0000000000e3','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b2','qr', ((current_date - 1)::timestamp + time '18:30') at time zone 'Asia/Kolkata'),
      ('83900000-0000-4000-8000-0000000000e6','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3','qr', ((current_date - 1)::timestamp) at time zone 'Asia/Kolkata'),
      -- Today (holiday): one visit inside the current day, hour pinned to one
      -- hour before the transaction clock so it is always before asOf.
      ('83900000-0000-4000-8000-0000000000e5','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3','qr', date_trunc('hour', now()) - interval '1 hour'),
      -- Exactly at the after-through local midnight: excluded.
      ('83900000-0000-4000-8000-0000000000e7','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3','qr', ((current_date + 1)::timestamp) at time zone 'Asia/Kolkata'),
      -- After asOf: excluded.
      ('83900000-0000-4000-8000-0000000000e8','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-0000000000b3','qr', now() + interval '2 hours'),
      -- Other tenant.
      ('83900000-0000-4000-8000-0000000000e9','83900000-0000-4000-8000-000000000002','83900000-0000-4000-8000-000000000014','83900000-0000-4000-8000-0000000000b4','qr', now() - interval '2 hours'),
      -- Auckland branch, deterministic branch-local 15:00 yesterday.
      ('83900000-0000-4000-8000-0000000000e4','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-0000000000b3','qr', ((current_date - 1)::timestamp + time '15:00') at time zone 'Pacific/Auckland'),
      -- DST gap: Sunday 2026-09-27 02:00-03:00 NZST does not exist; the visit
      -- sits on Sunday 2026-09-20 02:30 NZST so the Sunday/02 cell gains one
      -- eligible date while 2026-09-27 contributes none.
      ('83900000-0000-4000-8000-000000000e11','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-0000000000b3','qr', '2026-09-19T14:30:00Z'::timestamptz),
      -- DST repeat: Sunday 2026-04-05 02:30 occurs twice (NZDT then NZST);
      -- both instants bucket into the same coordinate and the date counts once.
      ('83900000-0000-4000-8000-000000000e12','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-0000000000b3','qr', '2026-04-04T13:30:00Z'::timestamptz),
      ('83900000-0000-4000-8000-000000000e13','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-0000000000b3','qr', '2026-04-04T14:30:00Z'::timestamptz);
  exception when others then
    insert into h83_seed_errors values ('attendance: ' || SQLERRM);
  end;
  begin
    -- Lawful service link: class_sessions.service_id is NOT NULL and the
    -- session rows stage against one real per-tenant services row. starts_at
    -- is staged explicitly before ends_at on every row.
    insert into public.services(id, tenant_id, name, description, default_duration_minutes, default_capacity, sort_order, is_active)
      values ('83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000001','H83 Strength','H83 holdout service',45,10,1,true);
    insert into public.class_sessions(id, tenant_id, service_id, branch_id, session_date, starts_at, capacity, status, ends_at, cancelled_at, cancel_reason, cancelled_by_staff_id) values
      ('83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000011', current_date - 1, now() - interval '3 hours', 7, 'scheduled', now() - interval '1 hour', null, null, null),
      ('83900000-0000-4000-8000-000000001102','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000011', current_date - 1, now() - interval '30 minutes', 10, 'scheduled', now() + interval '2 hours', null, null, null),   -- ongoing/future
      ('83900000-0000-4000-8000-000000001103','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000011', current_date - 1, now() - interval '4 hours', 10, 'cancelled', now() - interval '2 hours', now() - interval '2 hours 30 minutes', 'H83 cancelled for the holdout cohort', '83900000-0000-4000-8000-0000000000a1'),  -- cancelled elapsed; cancel_state_chk triple staged
      ('83900000-0000-4000-8000-000000001104','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000011', current_date, now() - interval '2 hours', 10, 'scheduled', now() - interval '30 minutes', null, null, null),   -- holiday-standing elapsed
      ('83900000-0000-4000-8000-000000001105','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000000c30','83900000-0000-4000-8000-000000000012', current_date - 1, now() - interval '3 hours', 5, 'scheduled', now() - interval '2 hours', null, null, null);    -- Auckland
  exception when others then
    insert into h83_seed_errors values ('class_sessions: ' || SQLERRM);
  end;
  begin
    -- booking_status has no bare 'cancelled': the member-cancel path stages
    -- 'cancelled_by_member', and cancel evidence requires cancelled_at.
    -- Route (a): tenant_id is trigger-derived under real claims contexts, so
    -- the fixture stages it explicitly for every booking row (tenant …0001).
    insert into public.class_bookings(id, tenant_id, session_id, member_id, status, cancelled_at, marked_at) values
      ('83900000-0000-4000-8000-000000001201','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b1','booked', null, null),
      ('83900000-0000-4000-8000-000000001202','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b2','attended', null, now() - interval '65 minutes'),
      ('83900000-0000-4000-8000-000000001203','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000001101','83900000-0000-4000-8000-0000000000b3','no_show', null, now() - interval '80 minutes'),
      -- (a second b1 row on …1101 was removed: unique(tenant,session,member)
      -- admits one row per pair; the member-cancel scenario needs no second
      -- booking for these cohort pins)
      ('83900000-0000-4000-8000-000000001205','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-000000001105','83900000-0000-4000-8000-0000000000b3','booked', null, null);
  exception when others then
    insert into h83_seed_errors values ('class_bookings: ' || SQLERRM);
  end;
  -- Direction (b), coordinator-approved: the addon staging runs in ONE
  -- transaction with no inner begin/exception wrapper — an addon trigger
  -- error aborts the run loudly (never swallowed into h83_seed_errors),
  -- and the payment IS visible to the addon trigger's invoker read at the
  -- acceptance UPDATE, so the exact-buy guard sees what it needs.
  begin
    -- Role re-set immediately before the offer staging: the fixtures run as
    -- postgres (row_security_active false), so RLS-gated guard clauses skip;
    -- unconditional offer-match conjuncts are satisfied by exact mirroring.
    set local role postgres;
    -- Lawful exact-buy staging per the phase6 ownsale guard: the order
    -- mirrors a dedicated on-clock payment (same member, exact total, same
    -- currency INR, paid with paid_at, no membership/mandate/coupon/
    -- provider, recorded_by = sold_by) and the payment's idempotency key is
    -- exactly 'addon-sale:' || the order's key. The USD payment …f4 keeps
    -- its per-currency pin and is NOT the order's payment.
    -- A listable product offer carries complete disclosed terms: non-blank
    -- description and cancellation_terms and validity_days > 0 (the same
    -- completeness checks record_addon_sale applies to active offers).
    insert into public.addon_products(id, tenant_id, kind, name, description, price_paise, currency, gst_rate_bp, stock_quantity, validity_days, cancellation_terms, quote_version, is_active)
      values ('83900000-0000-4000-8000-0000000000ae','83900000-0000-4000-8000-000000000001','product','H83 Towel Pass','H83 towel service for the analytics cohort',25000,'INR',0,10,30,'Non-refundable; usable for 30 days from sale.','83900000-0000-4000-8000-0000000000af',true);
    insert into public.payments(id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, receipt_number, recorded_by_staff_id, idempotency_key, paid_at, created_at)
      values ('83900000-0000-4000-8000-0000000000ac','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b3',null,25000,'INR','paid','cash','H83-RAC','83900000-0000-4000-8000-0000000000a3','addon-sale:83900000-0000-4000-8000-0000000000b0', now() - interval '40 minutes', now() - interval '40 minutes');

  exception when others then
    declare v_ctx text; v_detail text;
    begin
      get stacked diagnostics v_ctx = pg_exception_context, v_detail = pg_exception_detail;
      insert into h83_seed_errors values ('addon_offer/payment staging: ' || SQLERRM || ' ctx=' || v_ctx || ' detail=' || v_detail);
    end;
  end;
  -- Block 2: the order staging runs in its OWN subtransaction, so a guard
  -- refusal here can no longer roll the committed offer and payment back.
  begin
    -- A keyed sale begins pending with complete frozen evidence: snapshot
    -- exactly six keys matching the product (trainerQualification explicit
    -- jsonb null because the product carries none), request exactly nine keys
    -- with numeric quantity and the product's quote_version; the uid-shaped
    -- key satisfies the guard's key regex.
    -- A pending sale carries NO payment link yet: the frozen-terms guard
    -- arms once payment_id is set, and the acceptance UPDATE is what links
    -- the payment while the row is still pending and unpaid.
    insert into public.addon_orders(id, tenant_id, member_id, addon_product_id, status, quantity, unit_price_paise, total_paise, currency, idempotency_key, sold_by_staff_id, sale_snapshot, sale_request)
      values ('83900000-0000-4000-8000-0000000000ad','83900000-0000-4000-8000-000000000001','83900000-0000-4000-8000-0000000000b3','83900000-0000-4000-8000-0000000000ae','pending',1,25000,25000,'INR','83900000-0000-4000-8000-0000000000b0','83900000-0000-4000-8000-0000000000a3',
        -- The snapshot derives FROM the live product row at insert time, so
        -- it mirrors every guarded field exactly (including trainer_
        -- qualification as the row actually carries it — jsonb null when the
        -- column is SQL NULL).
        (select jsonb_build_object('kind',p.kind,'name',p.name,'description',p.description,'cancellationTerms',p.cancellation_terms,'validityDays',p.validity_days,'trainerQualification',p.trainer_qualification)
           from public.addon_products p
          where p.tenant_id = '83900000-0000-4000-8000-000000000001' and p.id = '83900000-0000-4000-8000-0000000000ae'),
        jsonb_build_object('memberId','83900000-0000-4000-8000-0000000000b3','productId','83900000-0000-4000-8000-0000000000ae','quantity',1,'quoteVersion',(select p.quote_version::text from public.addon_products p where p.tenant_id = '83900000-0000-4000-8000-000000000001' and p.id = '83900000-0000-4000-8000-0000000000ae'),'trainerStaffId',null,'initialStartsAt',null,'initialEndsAt',null,'method','cash','reason','H83 analytics staging'));
    -- The pending->paid acceptance derives the gym-local validity window from
    -- the acceptance instant: starts_on = sold date, expires_on = +29 days.
    -- The acceptance UPDATE carries the acceptance instant and derives the
    -- gym-local validity window from THAT SAME instant (the guard computes
    -- v_expected_start := new.sold_at at gym zone ::date and
    -- v_expected_end := starts_on + validityDays - 1; now() is
    -- transaction-stable, so the three expressions agree exactly).
    -- PAYCHECK diagnostic: stage the payment's live values ahead of the
    -- acceptance UPDATE so the staging-health text names any mismatching
    -- exact-buy guard column.
    insert into h83_seed_errors values ('PAYCHECK: member='||(select member_id::text from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' amt='||(select amount_paise::text from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' cur='||(select currency from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' status='||(select status from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' paid_at='||(select coalesce(paid_at::text,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' idemp='||(select coalesce(idempotency_key,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' recby='||(select coalesce(recorded_by_staff_id::text,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' memb_id='||(select coalesce(membership_id::text,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' mandate='||(select coalesce(mandate_id::text,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' coupon='||(select coalesce(coupon_id::text,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac')||' provider='||(select coalesce(provider,'NULL')||'/'||coalesce(provider_order_id,'NULL')||'/'||coalesce(provider_payment_id,'NULL') from public.payments where id='83900000-0000-4000-8000-0000000000ac'));
    -- The acceptance UPDATE runs as the production desk actor (BUY-013: the
    -- recording call is the real authenticated staff caller), so the addon
    -- trigger's invoker read sees the payment under the staff RLS the way
    -- production's desk session does.
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a3","role":"authenticated","app_role":"front_desk","staff_id":"83900000-0000-4000-8000-0000000000a3","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
    update public.addon_orders
      set status = 'paid',
          payment_id = '83900000-0000-4000-8000-0000000000ac',
          sold_at = now(),
          starts_on = (now() at time zone 'Asia/Kolkata')::date,
          expires_on = (now() at time zone 'Asia/Kolkata')::date + 29
      where id = '83900000-0000-4000-8000-0000000000ad';
    -- Restore the fixture's postgres session for the remaining staging.
    set local role postgres;
    perform set_config('request.jwt.claims','',true);
  end;
  -- Unconditional post-block probe: reads the payments row's committed
  -- state after the addon staging (ABSENT if the block rolled back), so the
  -- staging-health text names any exact-buy divergence directly.
  insert into h83_seed_errors values ('PAYCHECK-POST '||coalesce((select jsonb_build_object('id',id,'status',status,'amount',amount_paise,'currency',currency,'member',member_id,'paid_at',paid_at::text,'idempotency_key',idempotency_key,'recby',recorded_by_staff_id::text,'memb',membership_id::text,'mandate',mandate_id::text,'coupon',coupon_id::text,'prov',provider,'provoid',provider_order_id,'provpay',provider_payment_id)::text from public.payments where id='83900000-0000-4000-8000-0000000000ac'),'ABSENT'));
end $seed$;

select ok((select count(*) from h83_seed_errors) = 0,
          'real attendance/class staging succeeded'
          || coalesce(' (errors: ' || (select string_agg(line, ' ;; ' order by ctid) from h83_seed_errors), ''));

-- Owner identity for every materialized snapshot.
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;

select pg_temp.capture('main',    current_date - 1, current_date, null, true);
select pg_temp.capture('filter',  current_date - 1, current_date, '83900000-0000-4000-8000-000000000011'::uuid, true);
select pg_temp.capture('b11',     current_date - 1, current_date, '83900000-0000-4000-8000-000000000011'::uuid, true);
select pg_temp.capture('b12',     current_date - 1, current_date, '83900000-0000-4000-8000-000000000012'::uuid, true);
select pg_temp.capture('nohol',   current_date - 1, current_date, null, false);
select pg_temp.capture('sep',     date '2026-09-01', date '2026-09-30', null, true);
select pg_temp.capture('dst',     date '2026-09-20', date '2026-09-27', '83900000-0000-4000-8000-000000000012'::uuid, true);
select pg_temp.capture('apr',     date '2026-04-05', date '2026-04-05', '83900000-0000-4000-8000-000000000012'::uuid, true);
select pg_temp.capture('hol',     date '2026-09-21', date '2026-09-22', '83900000-0000-4000-8000-000000000011'::uuid, true);
select pg_temp.capture('future',  current_date + 30, current_date + 31, null, true);

select ok(not exists (select 1 from pg_temp.h83_snap where r ? '__error__'),
          'every materialized real-RPC call succeeded'
          || coalesce((select ' (' || k || ': ' || (r->>'__error__') || ')' from pg_temp.h83_snap where r ? '__error__' limit 1), ''));

-- ---------------------------------------------------------------------------
-- Section A: the real object's shape and security.
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
-- Section B: actor matrix (OCC-001) — direct calls.
-- ---------------------------------------------------------------------------
select ok(jsonb_typeof(pg_temp.snap('main')) = 'object','real gym owner receives the one-snapshot response');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a2","role":"authenticated","app_role":"gym_manager","staff_id":"83900000-0000-4000-8000-0000000000a2","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select ok(jsonb_typeof(public.owner_occupancy_analytics(current_date - 1, current_date, null, true)) = 'object','real gym manager receives the snapshot');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a3","role":"authenticated","app_role":"front_desk","staff_id":"83900000-0000-4000-8000-0000000000a3","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'front desk receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a4","role":"authenticated","app_role":"trainer","staff_id":"83900000-0000-4000-8000-0000000000a4","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'trainer receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000b1","role":"authenticated","app_role":"member","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'member receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'platform super admin receives no gym analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin","impersonation_session_id":"83900000-0000-4000-8000-000000000190"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'support preview receives no analytics');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin","tenant_id":"83900000-0000-4000-8000-000000000001","staff_id":"83900000-0000-4000-8000-0000000000a1"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'mixed platform and gym identity is refused before any read');
select set_config('request.jwt.claims','',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'missing claims are refused before any read');
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a5","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a5","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, true)$q$,'42501'::char(5),null,'inactive staff row is refused despite live claims');

-- Restore owner identity for the remaining sections.
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);

-- ---------------------------------------------------------------------------
-- Section C: branch safety and tenancy (OCC-001).
-- ---------------------------------------------------------------------------
-- Orchestrator adjudication (recorded in the sql-envelope-declaration): the
-- forged/unavailable branch refusal stays P0002 — the declaration's "same
-- safe refusal" clause plus the repo-wide target-invisibility precedent make
-- the single unavailable signal correct; a 42501 would reveal authorization
-- state about the branch.
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, '83900000-0000-4000-8000-000000000099'::uuid, true)$q$,'P0002'::char(5),null,'forged branch id is refused with the same safe unavailable signal');
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, '83900000-0000-4000-8000-000000000014'::uuid, true)$q$,'P0002'::char(5),null,'foreign-tenant branch id is refused with the same safe unavailable signal');
select is((select current_setting('request.jwt.claims')),'{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}','actor matrix fixtures intact');
select ok(jsonb_typeof(pg_temp.snap('main')) = 'object','null branch reads the whole gym');
select ok((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected') v
           where v->>'paymentId' = '83900000-0000-4000-8000-0000000000f9') = 0,'cross-tenant payment never returns');

-- ---------------------------------------------------------------------------
-- Section D: exact envelope, selection echo, zones, month coverage.
-- ---------------------------------------------------------------------------
-- Order-insensitive key-set pin: Postgres jsonb normalizes object key order
-- internally (length-then-bytes), so the declaration's listing order is
-- author-facing, not storage order or contract behavior; the SET of keys is
-- what the envelope pins. Two canonically-normalized jsonb comparisons would
-- agree the same way; sorting both sides makes the same point explicitly.
select is((select array_agg(k order by k) from (select k, ord from jsonb_object_keys(pg_temp.snap('main')) with ordinality as t(k,ord)) s),
          array['asOf','classes','collection','heatmap','moneyRange','months','range','warnings','zone'],
          'top-level envelope is exactly the nine frozen keys (set-wise; listing order is author-facing, not contract behavior)');
select is(pg_temp.snap('main')->'range'->>'from',(current_date - 1)::text,'range echoes the actual resolved from date');
select is(pg_temp.snap('main')->'range'->>'through',current_date::text,'range echoes the actual resolved through date');
select is(pg_temp.snap('main')->'range'->>'branchId',null,'whole-gym selection echoes a null branchId');
select is(pg_temp.snap('main')->'range'->>'excludeHolidays','true','range echoes the holiday toggle');
select ok(pg_temp.snap('main')->>'asOf' is not null,'server asOf is disclosed');
select is(pg_temp.snap('main')->>'zone','Asia/Kolkata','gym zone is disclosed for whole-gym money reads');
select is(pg_temp.snap('b12')->>'zone','Pacific/Auckland','nonnull branch zone overrides the gym zone and is disclosed');
select is(pg_temp.snap('b11')->>'zone','Asia/Kolkata','null branch zone is the disclosed gym-zone inheritance');
select is(pg_temp.snap('main')->'moneyRange'->>'scope','Whole gym','money scope is always Whole gym');
select is(pg_temp.snap('main')->'moneyRange'->>'cutoffAt',pg_temp.snap('main')->>'asOf','money cutoff is min(endsBefore, asOf): the range ends after now, so the cutoff equals asOf');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'months'))::bigint,1::bigint,'months contains exactly the gym-local months intersecting the selection');
select is((select m->>'month' from jsonb_array_elements(pg_temp.snap('main')->'months') m limit 1),to_char(now() at time zone 'Asia/Kolkata','YYYY-MM'),'the intersecting month is the current gym-local month');
select is((select m->>'coverage' from jsonb_array_elements(pg_temp.snap('main')->'months') m limit 1),'partial','an incomplete calendar-month selection is partial, never full');
select ok((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'months') m where exists (select 1 from jsonb_array_elements(m->'currencies') c where c->>'currency' = 'INR')) = 1
       and (select count(*) from jsonb_array_elements(pg_temp.snap('main')->'months') m where exists (select 1 from jsonb_array_elements(m->'currencies') c where c->>'currency' = 'USD')) = 1,'month currency union covers every dated selected currency');
select is((select m->>'coverage' from jsonb_array_elements(pg_temp.snap('sep')->'months') m limit 1),'full','a complete calendar-month selection fully in the past is full');
select is(pg_temp.cash(pg_temp.snap('sep')->'collection'->'currencies','INR')->>'collectedPaise','12345','prior-month payment groups only in its own selected gym-local month');
select is((select m->>'coverage' from jsonb_array_elements(pg_temp.snap('future')->'months') m limit 1),'unavailable','an entirely future month is unavailable, never a full zero');
select is((select m->'currencies' from jsonb_array_elements(pg_temp.snap('future')->'months') m limit 1),'[]'::jsonb,'unavailable months carry an empty currency union, never invented zeros');
select is(pg_temp.snap('future')->'collection'->'currencies','[]'::jsonb,'an entirely future range returns no collected cash at all');

-- Holiday exclusion is pinned behaviorally with the flag passed explicitly:
-- the frozen four-argument envelope has no defaulted form to omit, and the
-- null-toggle refusal elsewhere proves omission is impossible.
select ok(coalesce((select d->>'excluded'
           from jsonb_array_elements(public.owner_occupancy_analytics(current_date - 1, current_date, null, true)->'heatmap'->'branches') b
           cross join lateral jsonb_array_elements(b->'days') d
           where b->>'branchId' = '83900000-0000-4000-8000-000000000011'
             and d->>'localDate' = current_date::text
           limit 1), 'missing') = 'true','explicit true keeps holiday exclusion on (OCC-005)');

-- ---------------------------------------------------------------------------
-- Section E: heatmap exposure, holidays, DST, reconciliation (OCC-004..008).
-- ---------------------------------------------------------------------------
select is((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'heatmap'->'branches'))::bigint,3::bigint,'heatmap carries the whole selected visible branch population');
select is((select array_agg(b->>'branchId' order by b->>'branchId') from jsonb_array_elements(pg_temp.snap('main')->'heatmap'->'branches') b),
          array['83900000-0000-4000-8000-000000000011','83900000-0000-4000-8000-000000000012','83900000-0000-4000-8000-000000000013'],
          'heatmap branches are sorted by branchId');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'zoneSource','gym','inherited gym zone is disclosed as zoneSource gym');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'zone','Asia/Kolkata','effective zone for the inheriting branch is the gym zone');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'error',null,'a valid branch carries no zone error');
select is(pg_temp.branch(pg_temp.snap('b12')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->>'zoneSource','branch','own branch zone is disclosed as zoneSource branch');
select is(pg_temp.branch(pg_temp.snap('b12')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->>'zone','Pacific/Auckland','own branch zone is the effective zone');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000013')->'error'->>'code','invalid_branch_timezone','invalid nonnull branch zone is an explicit per-branch error, never a fallback zero');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000013')->>'range',null,'invalid branch exposes no range boundaries');
select ok(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000013')->'days' = '[]'::jsonb
       and pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000013')->'cells' = '[]'::jsonb,'invalid branch keeps its entry with empty exposure, never silently dropped');
select is((select count(*) from jsonb_array_elements(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days'))::bigint,2::bigint,'one day row per selected local date, including zero and excluded dates');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'localDate',current_date::text,'today is present as a day row');
select ok(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'excluded' = 'true'
       and pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'isHoliday' = 'true','the holiday date is marked excluded with the toggle on');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'visits','1','the excluded holiday visit stays visible in its day row (never erased)');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'state','current','today is the current day relative to asOf');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date - 1)->>'state','completed','yesterday is a completed day');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date - 1)->>'visits','5','yesterday raw arrivals: two members at 09:00, the first member again at 09:30, one at 18:30, one exactly at the range-start midnight');
select is((select sum((h->>'visits')::int) from jsonb_array_elements(pg_temp.day(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date - 1)->'hours') h)::bigint,5::bigint,'day hours reconcile to the day visits');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'totalVisits','5','branch total visits sum only nonexcluded day visits');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'completedVisits','5','completed visits are yesterday''s five');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'currentDayVisits','0','the excluded current day contributes zero nonexcluded current visits');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'excludedVisits','1','excluded holiday visits are disclosed separately');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'availability','partial','a range containing the current day is partial');
select is((select count(*) from jsonb_array_elements(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells'))::bigint,168::bigint,'cells include all 168 weekday/hour coordinates in coordinate order');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,9)->>'arrivals','3','the 09:00 hour counts two members and the same member''s second visit (three raw arrivals)');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,9)->>'eligibleDates','1','only yesterday is an eligible completed date for yesterday''s weekday');
select ok(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,9)->>'limited' = 'true'
       and pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,9)->>'message' = 'Limited history','below 14 eligible dates the cell is Limited history with the raw fraction retained');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,18)->>'arrivals','1','the 18:30 arrival buckets into hour 18');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from (current_date - 1))::int,0)->>'arrivals','1','an arrival exactly at the lower-bound local midnight buckets into hour 0 (lower bound included)');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from current_date)::int,extract(hour from (date_trunc('hour', now()) - interval '1 hour') at time zone 'Asia/Kolkata')::int)->>'arrivals','0','the excluded holiday visit never enters any cell numerator');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from current_date)::int,extract(hour from (date_trunc('hour', now()) - interval '1 hour') at time zone 'Asia/Kolkata')::int)->>'todayArrivals','0','an excluded holiday visit never enters todayArrivals');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from current_date)::int,10)->>'message','No eligible days','a coordinate with no completed nonexcluded eligible dates discloses No eligible days, not a zero average');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',extract(dow from current_date)::int,10)->>'basisPoints',null,'a zero-denominator cell fraction carries null basis points');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'week'->>'arrivals','5','the week aggregate sums completed nonexcluded date visits');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'week'->>'eligibleDates','1','the week aggregate counts each completed nonexcluded date once');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'week'->>'basisPoints','50000','the week fraction is the exact half-up ratio of its own numerator and denominator');
select is(pg_temp.branch(pg_temp.snap('main')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'week'->>'limited','true','the week aggregate is limited below 14 eligible dates');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('b12')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',current_date - 1)->>'visits','1','the Auckland visit buckets on its own branch-local date under the branch zone');
select is(pg_temp.snap('main')->'heatmap'->'reconciliation'->>'complete','false','one invalid branch makes the heatmap reconciliation incomplete');
select is(pg_temp.snap('main')->'heatmap'->'reconciliation'->>'totalVisits',null,'an incomplete reconciliation returns null totals instead of a silently partial organization sum');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('nohol')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'excluded','false','with the toggle off the holiday date is not excluded');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('nohol')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'days',current_date)->>'isHoliday','true','with the toggle off the date still discloses its holiday fact');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('filter')->'heatmap'->'branches'))::bigint,1::bigint,'a branch-scoped read exposes exactly that branch');
select is((select h->>'exists' from jsonb_array_elements(pg_temp.day(pg_temp.branch(pg_temp.snap('dst')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',date '2026-09-27')->'hours') h where (h->>'hour')::int = 2),'false','the DST-gap clock hour does not exist on 2026-09-27 in Auckland');
select is((select h->>'visits' from jsonb_array_elements(pg_temp.day(pg_temp.branch(pg_temp.snap('dst')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',date '2026-09-20')->'hours') h where (h->>'hour')::int = 2),'1','the pre-gap Sunday visit buckets into hour 2 on 2026-09-20');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('dst')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'cells',0,2)->>'eligibleDates','1','the missing DST hour contributes no eligible date to its coordinate');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('dst')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'cells',0,2)->>'arrivals','1','only the existing hour''s visit reaches the Sunday/02 cell');
select is(pg_temp.day(pg_temp.branch(pg_temp.snap('apr')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',date '2026-04-05')->>'visits','2','both repeated-clock instants bucket into the same local date');
select is((select count(*) from jsonb_array_elements(pg_temp.day(pg_temp.branch(pg_temp.snap('apr')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',date '2026-04-05')->'hours'))::bigint,24::bigint,'a repeated-hour day still exposes exactly 24 ordered clock hours');
select is((select h->>'visits' from jsonb_array_elements(pg_temp.day(pg_temp.branch(pg_temp.snap('apr')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'days',date '2026-04-05')->'hours') h where (h->>'hour')::int = 2),'2','the two occurrences of the repeated clock hour combine into one coordinate');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('apr')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'cells',0,2)->>'arrivals','2','the repeated-hour cell sums both occurrences');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('apr')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->'cells',0,2)->>'eligibleDates','1','the repeated hour counts its date once, not twice');
select is(pg_temp.branch(pg_temp.snap('hol')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'noEligibleDays','true','an all-holiday range discloses noEligibleDays');
select is(pg_temp.branch(pg_temp.snap('hol')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'week'->>'message','No eligible days','an all-holiday range shows No eligible days, not a quiet branch');
select is(pg_temp.cell(pg_temp.branch(pg_temp.snap('hol')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'cells',1,9)->>'basisPoints',null,'an all-holiday coordinate has no average at all');

-- ---------------------------------------------------------------------------
-- Section F: money, months, classification, warnings (OCC-009..013).
-- ---------------------------------------------------------------------------
select is((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected'))::bigint,5::bigint,'exactly the five dated in-range arrived receipts are returned');
select is((select array_agg(v->>'paymentId' order by ord) from (select v, ord from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected') with ordinality as t(v,ord)) s),
          array['83900000-0000-4000-8000-0000000000fb','83900000-0000-4000-8000-0000000000f1','83900000-0000-4000-8000-0000000000f3','83900000-0000-4000-8000-0000000000f2','83900000-0000-4000-8000-0000000000f4'],
          'receipt components are sorted by event instant then id');
select is(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f1')->>'category','renewal','a payment on the member''s later membership row classifies renewal');
select is(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f1')->'membershipEvidence'->>'hasEarlierMembership','true','the renewal receipt discloses its earlier-membership evidence');
select ok(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f2')->>'category' = 'newMember'
       and pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f2')->'membershipEvidence'->>'hasEarlierMembership' = 'false','a payment on the member''s first membership row classifies newMember with its evidence');
select is(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000fb')->>'category','newMember','an equal-created_at membership sibling is not an earlier row: no id tie-break is permitted');
-- Adjudication 2026-10-04: a USD add-on order is unachievable (the offer
-- guard requires INR products), so a USD payment with no addon_orders row
-- and no membership evidence truthfully classifies 'unallocated'.
select ok(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f4')->>'category' = 'unallocated'
       and pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f4')->'membershipEvidence' is null,'an unlinked USD payment carries no membership evidence and classifies unallocated (USD addon orders are unachievable: products are INR-only)');
select is(pg_temp.pay(pg_temp.snap('main')->'collection'->'components'->'collected','83900000-0000-4000-8000-0000000000f3')->>'category','unallocated','an unlinked manual payment stays unallocated, never guessed into a membership category');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'newMember'->>'collectedPaise','105000','INR new-member collected is the exact sum of both newMember receipts');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'newMember'->>'netPaise','75000','INR new-member net nets the completed in-category return exactly');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'newMember'->>'returnedPaise','30000','INR new-member returned equals the completed return of its receipt');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'renewal'->>'collectedPaise','150000','INR renewal collected is exact');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'renewal'->>'netPaise','150000','INR renewal net is exact');
select ok(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'renewal' ? 'unknownReturnPaise' = false,'unknownReturnPaise appears in the unallocated category only');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'unallocated'->>'collectedPaise','9007199254740993','the unallocated receipt keeps its exact integer paise beyond the safe JS integer');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR'),'Membership linkage (derived classification)')->'addon'->>'collectedPaise','25000','the staged INR add-on sale contributes its exact 25000 to the addon category');
select is(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR')->>'collectedPaise','9007199255020993','INR collected reconciles to the exact category sum beyond the safe JS integer (incl. the 25000 addon sale)');
select is(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR')->>'netPaise','9007199254990993','INR net is the exact integer difference, never floating point (incl. the 25000 addon sale)');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'addon'->>'collectedPaise','0','USD add-on collection is empty: no USD addon order is achievable (adjudication)');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'unallocated'->>'collectedPaise','25000','the unlinked USD receipt carries the USD unallocated group');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'unallocated'->>'unknownReturnPaise','7500','the unknown-allocation return is disclosed exactly once, in the unallocated category');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'unallocated'->>'unknownReturnPaise',pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'unallocated'->>'returnedPaise','unknownReturnPaise equals that category''s returnedPaise, never an extra summand');
select is(pg_temp.cat(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD'),'Membership linkage (derived classification)')->'unallocated'->>'netPaise','-7500','the returns-only unallocated category is a visible negative, spelled with a sign and never -0');
select is(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','USD')->>'netPaise','17500','USD cash net nets collected and returned exactly');
select is((select (a->>'collectedPaise')::numeric from jsonb_array_elements(pg_temp.snap('main')->'collection'->'currencies') a where a->>'currency'='INR'),
          (select sum((e.value->>'collectedPaise')::numeric) from jsonb_each(pg_temp.cash(pg_temp.snap('main')->'collection'->'currencies','INR')->'categories') e
           where e.key in ('newMember','renewal','addon','unallocated')),
          'the four categories sum exactly to the currency cash collected');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected') v where v->>'paymentId' = '83900000-0000-4000-8000-0000000000f5'),'a created (never-arrived) attempt contributes no collected cash');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected') v where v->>'paymentId' = '83900000-0000-4000-8000-0000000000f8'),'a payment at or after asOf contributes nothing');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'collected') v where v->>'paymentId' = '83900000-0000-4000-8000-0000000000f9'),'no cross-tenant payment ever appears');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'returned') v where (v->>'amountPaise') = '1000'),'a requested (in-flight) return contributes zero returned cash');
select is(pg_temp.snap('filter')->'collection',pg_temp.snap('main')->'collection','the branch selector never moves cash: whole-business collection is identical under a branch filter');
select is(pg_temp.snap('nohol')->'collection',pg_temp.snap('main')->'collection','the holiday toggle never moves cash');
select is(pg_temp.ret(pg_temp.snap('main')->'collection'->'components'->'returned','83900000-0000-4000-8000-000000000101')->>'category','newMember','a return allocates whole to the original receipt''s category');
select is(pg_temp.ret(pg_temp.snap('main')->'collection'->'components'->'returned','83900000-0000-4000-8000-000000000101')->>'allocationUnknown','false','an allocated return is not marked unknown');
select ok(pg_temp.ret(pg_temp.snap('main')->'collection'->'components'->'returned','83900000-0000-4000-8000-000000000104')->>'category' = 'unallocated'
       and pg_temp.ret(pg_temp.snap('main')->'collection'->'components'->'returned','83900000-0000-4000-8000-000000000104')->>'allocationUnknown' = 'true','a return of an unallocated receipt stays in the unknown-allocation disclosure');
select is((select array_agg(v->>'returnId' order by ord) from (select v, ord from jsonb_array_elements(pg_temp.snap('main')->'collection'->'components'->'returned') with ordinality as t(v,ord)) s),
          array['83900000-0000-4000-8000-000000000101','83900000-0000-4000-8000-000000000104'],
          'returned components are sorted by event instant then id');
select is(pg_temp.snap('main')->'warnings'->>'scope','Current all-date','the warning population is the current all-date scope');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'warnings'->'undatedPayments'))::bigint,1::bigint,'exactly the one arrived undated payment is warned');
select is(pg_temp.snap('main')->'warnings'->'undatedPayments'->0, jsonb_build_object('paymentId','83900000-0000-4000-8000-0000000000f6','amountPaise','7000','currency','INR'), 'undated payment rows carry exactly the frozen keys and values');
-- Adjudication (declaration warnings section, 2026-10-04): completed<=>processed_at
-- is coupled in both directions by the phase6 refund guard, so undatedReturns
-- is always empty; the coupled invariant is pinned on the lawful staged rows.
select ok(
  (select processed_at is not null from public.refunds where id = '83900000-0000-4000-8000-000000000101')
  and coalesce((select true from public.refunds where id = '83900000-0000-4000-8000-000000000102' and status <> 'completed' and processed_at is null), false)
  and pg_temp.snap('main')->'warnings'->'undatedReturns' = '[]'::jsonb,
  'undatedReturns is always empty and the completed<=>processed_at coupling holds on lawful rows');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('main')->'warnings'->'totals'))::bigint,1::bigint,'totals are grouped per currency');
select is(pg_temp.snap('main')->'warnings'->'totals'->0, jsonb_build_object('currency','INR','undatedPaymentCount','1','undatedPaymentPaise','7000','undatedReturnCount','0','undatedReturnPaise','0'), 'warning totals sum exclusively from the warned rows per currency');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('future')->'warnings'->'undatedPayments'))::bigint,1::bigint,'the all-date warning population is independent of the selected range');

-- ---------------------------------------------------------------------------
-- Section G: elapsed class cohort, capacity, marking, fractions (OCC-014..016).
-- ---------------------------------------------------------------------------
select is((select count(*) from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001101')::bigint,1::bigint,'the elapsed non-cancelled session is in the branch cohort');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->>'capacity','7','capacity is the stored per-session value, not a service default');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->>'holdingBookings','3','holding bookings are booked + attended + no_show; the cancelled booking contributes zero');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->>'bookedCount','1','still-booked unmarked bookings are disclosed');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->>'attendedCount','1','explicitly marked attended is disclosed');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->>'noShowCount','1','explicitly marked no-show is disclosed and held its seat');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->'bookedFill'->>'numerator','3','session drill bookedFill keeps its exact raw numerator');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->'bookedFill'->>'denominator','7','session drill bookedFill keeps its exact stored-capacity denominator');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->'bookedFill'->>'basisPoints','4286','session drill bookedFill rounds half-up exactly');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->'markedPresence'->>'basisPoints','1429','marked presence over capacity rounds half-up exactly');
select is(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions','83900000-0000-4000-8000-000000001101')->'markingCoverage'->>'basisPoints','6667','marking coverage rounds half-up exactly');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001102'),'an ongoing/future session never enters the elapsed cohort');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001103'),'a cancelled session contributes neither bookings nor capacity to the cohort');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'cancelledSessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001103')::bigint,1::bigint,'the elapsed cancelled session is disclosed in cancelledSessions');
select is((select array_agg(k order by ord) from (select k, ord from jsonb_object_keys(pg_temp.sess(pg_temp.snap('b11')->'classes'->'branches'->0->'cancelledSessions','83900000-0000-4000-8000-000000001103')) with ordinality as t(k,ord)) s),
          array['sessionId','serviceId','sessionDate','startsAt','endsAt'],
          'cancelled drill rows carry exactly the five frozen keys and no capacity or bookings');
select is((select count(*) from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001104')::bigint,1::bigint,'a holiday session which remained scheduled and elapsed stays in the cohort');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'cohortSessions','2','the branch cohort is exactly its two elapsed non-cancelled sessions');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'totalCapacity','17','summary capacity sums stored session capacities');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'holdingBookings','3','summary holding bookings sum session rows');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'unmarkedCount','1','summary unmarked count equals the still-booked bookings');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'cancelledSessionsExcluded','1','summary discloses the excluded cancelled session count');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->'bookedFill'->>'basisPoints','1765','summary booked fill is capacity weighted, never a mean of percentages');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->'markedPresence'->>'basisPoints','588','summary marked presence is capacity weighted');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->'markingCoverage'->>'basisPoints','6667','summary marking coverage is holding-weighted');
select ok(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'limited' = 'true'
       and pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'message' = 'Limited history','below 10 elapsed sessions the cohort summary is Limited history');
select is(pg_temp.snap('b11')->'classes'->'branches'->0->'summary'->>'incompleteMarkingDisclosed','true','unmarked bookings force the incomplete-marking disclosure');
select is(pg_temp.snap('b12')->'classes'->'branches'->0->'summary'->'bookedFill'->>'basisPoints','2000','the Auckland branch summary is its own capacity-weighted cohort');
select ok(pg_temp.branch(pg_temp.snap('main')->'classes'->'branches','83900000-0000-4000-8000-000000000013')->>'summary' is null
       and pg_temp.branch(pg_temp.snap('main')->'classes'->'branches','83900000-0000-4000-8000-000000000013')->'sessions' = '[]'::jsonb,'the invalid branch keeps its classes entry with a null summary and empty arrays');
select is(pg_temp.snap('main')->'classes'->'reconciliation'->>'complete','false','one invalid branch makes the classes reconciliation incomplete');
select is(pg_temp.snap('main')->'classes'->'reconciliation'->'summary',null,'an incomplete classes reconciliation returns a null summary instead of a partial aggregate');
select ok((select count(*) from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches')) = 1
       and not exists (select 1 from jsonb_array_elements(pg_temp.snap('b11')->'classes'->'branches'->0->'sessions') s where s->>'sessionId' = '83900000-0000-4000-8000-000000001105'),'a branch-scoped read exposes only that branch''s cohort');

-- ---------------------------------------------------------------------------
-- Section H: argument validation refusals.
-- ---------------------------------------------------------------------------
select throws_ok($q$select public.owner_occupancy_analytics(current_date, current_date - 1, null, true)$q$,'22023'::char(5),null,'an inverted range is invalid');
select throws_ok($q$select public.owner_occupancy_analytics(null, current_date, null, true)$q$,'22023'::char(5),null,'a missing from date is invalid, never defaulted');
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, null, null, true)$q$,'22023'::char(5),null,'a missing through date is invalid, never defaulted');
select throws_ok($q$select public.owner_occupancy_analytics(current_date - 1, current_date, null, null)$q$,'22023'::char(5),null,'a null holiday toggle is invalid, never silently defaulted');

-- ---------------------------------------------------------------------------
-- Section I: invalid gym zone (end-of-life fixture change, rollback undoes it).
-- The corruption UPDATE must carry platform-super-admin REQUEST CLAIMS: the
-- organizations commercial trigger gates writes through the JWT claims, not
-- the current SQL role, so neither the reset identity nor `role postgres`
-- satisfies it. Super-admin claims are set around the corruption and the
-- ordinary owner claims are restored immediately after (the corrupt zone is
-- itself the fixture the assertions then read).
set local role postgres;
insert into public.platform_users(user_id, role, full_name, email, is_active)
  values ('83900000-0000-4000-8000-0000000000a8','super_admin','Fixture Super Admin','fixture-super-admin@example.invalid',true);
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a8","role":"authenticated","app_role":"super_admin"}',true);
-- The trigger's UPDATE branch refuses invalid zones even for super admins,
-- so the zone corruption stages through the registered disable/restore seam:
-- user triggers on organizations are disabled around the single guarded
-- UPDATE and restored immediately, before any application check runs.
alter table public.organizations disable trigger user;
update public.organizations set timezone = 'Not/AZone'
  where id = '83900000-0000-4000-8000-000000000001';
alter table public.organizations enable trigger user;
select set_config('request.jwt.claims','{"sub":"83900000-0000-4000-8000-0000000000a1","role":"authenticated","app_role":"gym_owner","staff_id":"83900000-0000-4000-8000-0000000000a1","tenant_id":"83900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select pg_temp.capture('badzone', current_date - 1, current_date, null, true);
select is(pg_temp.snap('badzone')->>'zone','Not/AZone','an invalid gym zone is preserved as its text, never fabricated into UTC');
select is(pg_temp.snap('badzone')->'moneyRange'->'error'->>'code','invalid_gym_timezone','an invalid gym zone is an explicit money-scope error');
select is(pg_temp.snap('badzone')->'months','[]'::jsonb,'an invalid gym zone yields no months');
select is(pg_temp.snap('badzone')->'collection',null,'an invalid gym zone yields no collection at all');
select ok(pg_temp.branch(pg_temp.snap('badzone')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->'error'->>'code' = 'invalid_gym_timezone'
       and pg_temp.branch(pg_temp.snap('badzone')->'heatmap'->'branches','83900000-0000-4000-8000-000000000011')->>'range' is null,'the inheriting branch fails with the gym-zone error and no boundaries');
select is(pg_temp.branch(pg_temp.snap('badzone')->'heatmap'->'branches','83900000-0000-4000-8000-000000000012')->>'error',null,'a branch with its own valid zone stays individually valid while the gym zone is invalid');

select * from finish();
rollback;
