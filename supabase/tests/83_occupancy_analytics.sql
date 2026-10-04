-- OCC-001..017 independent visible contract (Wave D occupancy, collection and
-- class fill analytics). Frozen authority, in precedence order:
-- openspec/changes/occupancy-analytics/sql-envelope-declaration.md (FROZEN
-- 2026-10-04, the complete mechanical envelope: exact four-argument RPC, exact
-- nested keys, exact fractions, per-branch arrays, reconciliations) and
-- openspec/changes/occupancy-analytics/proposal.md (FROZEN 2026-10-03, with the
-- owner-resolved choices recorded in OCC-007 and OCC-012). The earlier
-- loader-era key shapes this suite once pinned (top-level heatmap
-- zone/zoneSource/eligibleDateCount/excludedDates/arrivalDays, a single
-- classes summary object, month `classification` objects, string fraction
-- placeholders like "0.2500…") were superseded by the frozen envelope; every
-- business fact those assertions carried is re-expressed below against the
-- envelope keys rather than removed. No implementation, holdout or other OCC
-- test material was read.
--
-- RED pattern: no mirror DDL. Catalog assertions are NULL-safe
-- (to_regprocedure) and every dynamic statement runs through a catching
-- executor, so the file runs end-to-end RED before the analytics migration
-- exists (missing function 42883) and judges the real implementation once CI
-- applies it. Nothing commits: one begin/rollback pair.
--
-- Refusal-code assumptions pinned from the frozen contract plus the repo's
-- shared precedence vocabulary: actor/privilege failures 42501; value/shape
-- validation (reversed/invalid dates, invalid configured zone, null holiday
-- toggle) 22023; unknown and foreign branch share one invisible-target refusal
-- P0002 (no existence oracle). If the implementer maps any of these
-- differently, that is a contract-defect round-trip to the test author, not a
-- test edit by the implementer.
--
-- All money/count/basis-point values below are canonical decimal STRINGS and
-- every fraction is the exact {numerator,denominator,basisPoints} triple with
-- basisPoints = floor((2*n*10000+d)/(2*d)) half-up and null at a zero
-- denominator. Timestamps are compared as instants (::timestamptz), never as
-- spelling, because the envelope requires unambiguous RFC3339 instants but
-- does not pin one spelling.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(79);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('83000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text default 'gym_owner', s integer default null, m integer default null, a integer default 901, t integer default 1, p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(t),'staff_id',case when s is not null then pg_temp.u(s) end,'member_id',case when m is not null then pg_temp.u(m) end,'impersonation_session_id',case when p then pg_temp.u(999) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.state(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
-- Section G derives its range from the CURRENT gym-local run day (the
-- fixture organization's own zone), so the incomplete-today disclosures stay
-- deterministic on any run date. Callers of gym_today() re-read it per
-- assertion; the only seeded visit on that day is 616 (now()).
create function pg_temp.gym_today() returns date language sql volatile as $$select (now() at time zone (select timezone from public.organizations where id = pg_temp.u(1)))::date$$;
create function pg_temp.snap(p_from date, p_through date, p_branch_id uuid default null) returns text language plpgsql as $$declare r text; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid,true)::text' using p_from,p_through,p_branch_id into r; return r; exception when others then return sqlstate; end$$;
create function pg_temp.snapx(p_from date, p_through date, p_branch_id uuid, p_exclude_holidays boolean) returns text language plpgsql as $$declare r text; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid,$4::boolean)::text' using p_from,p_through,p_branch_id,p_exclude_holidays into r; return r; exception when others then return sqlstate; end$$;
-- jsonb snapshot helpers: snapj keeps the three-argument call (pins the
-- default omission = holiday exclusion on); snapjx passes the toggle.
create function pg_temp.snapj(p_from date, p_through date, p_branch_id uuid default null) returns jsonb language plpgsql as $$declare r jsonb; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid,true)' using p_from,p_through,p_branch_id into r; return r; exception when others then return null::jsonb; end$$;
create function pg_temp.snapjx(p_from date, p_through date, p_branch_id uuid, p_exclude_holidays boolean) returns jsonb language plpgsql as $$declare r jsonb; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid,$4::boolean)' using p_from,p_through,p_branch_id,p_exclude_holidays into r; return r; exception when others then return null::jsonb; end$$;
-- Extraction helpers over the one returned snapshot.
create function pg_temp.hb(js jsonb, p_id uuid) returns jsonb language sql immutable as $$select e from jsonb_array_elements(js->'heatmap'->'branches') e where e->>'branchId'=p_id::text$$;
create function pg_temp.cb(js jsonb, p_id uuid) returns jsonb language sql immutable as $$select e from jsonb_array_elements(js->'classes'->'branches') e where e->>'branchId'=p_id::text$$;
create function pg_temp.cell(js jsonb, p_id uuid, w integer, h integer) returns jsonb language sql immutable as $$select e from jsonb_array_elements(pg_temp.hb(js,p_id)->'cells') e where (e->>'weekday')=w::text and (e->>'hour')=h::text$$;
create function pg_temp.day(js jsonb, p_id uuid, d date) returns jsonb language sql immutable as $$select e from jsonb_array_elements(pg_temp.hb(js,p_id)->'days') e where e->>'localDate'=d::text$$;
create function pg_temp.fr(n text, d text, bp text) returns jsonb language sql immutable as $$select jsonb_build_object('numerator',n,'denominator',d,'basisPoints',bp)$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.probe(text),pg_temp.state(text),pg_temp.snap(date,date,uuid),pg_temp.snapx(date,date,uuid,boolean),pg_temp.snapj(date,date,uuid),pg_temp.snapjx(date,date,uuid,boolean),pg_temp.hb(jsonb,uuid),pg_temp.cb(jsonb,uuid),pg_temp.cell(jsonb,uuid,integer,integer),pg_temp.day(jsonb,uuid,date),pg_temp.fr(text,text,text),pg_temp.gym_today() to authenticated,anon,service_role;

-- ============ fixtures (existing schema only) ============
insert into auth.users(id) select pg_temp.u(n) from generate_series(901,916) n;
-- SLF/OCC frozen actor contract: platform subjects also require auth.users provenance.
insert into auth.users(id) values(pg_temp.u(928));
insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.u(928),'super_admin','OCC root','occ83-root@example.test',true);
-- The foreign gym's INVALID zone is lawful corruption evidence only: the
-- commercial invariant trigger refuses invalid zones on every public write
-- path (platform trusted writers included), so the frozen invalid-gym-zone
-- envelope is unreachable without registered corruption. The gym starts with
-- a VALID zone so every trigger-evaluating tenant-2 fixture write below
-- (membership, check-in, payment triggers resolve the gym zone at write
-- time) succeeds through the normal business path; the zone is corrupted
-- through the registered disable/restore seam immediately AFTER the last
-- fixture write, with the trigger restored before any application check.
insert into public.organizations(id,name,gym_code,status,timezone) values(pg_temp.u(1),'OCC A','OCC83A','active','Asia/Kolkata'),(pg_temp.u(2),'OCC B','OCC83B','active','UTC');
-- Branch 11 inherits the gym zone (null override), 12 overrides to New York,
-- 13 carries an invalid configured zone, 14 belongs to the foreign gym whose
-- GYM zone is invalid (section J exercises the invalid-gym-zone envelope).
insert into public.branches(id,tenant_id,name,timezone,is_default) values
(pg_temp.u(11),pg_temp.u(1),'A',null,true),
(pg_temp.u(12),pg_temp.u(1),'B','America/New_York',false),
(pg_temp.u(13),pg_temp.u(1),'C','Mars/Phobos',false),
(pg_temp.u(14),pg_temp.u(2),'D',null,true);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name,is_active) values
(pg_temp.u(21),pg_temp.u(1),pg_temp.u(901),pg_temp.u(11),'gym_owner','Owner',true),
(pg_temp.u(22),pg_temp.u(1),pg_temp.u(902),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(23),pg_temp.u(1),pg_temp.u(903),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(24),pg_temp.u(1),pg_temp.u(904),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(25),pg_temp.u(2),pg_temp.u(905),pg_temp.u(14),'gym_owner','Other',true),
(pg_temp.u(26),pg_temp.u(2),pg_temp.u(916),pg_temp.u(14),'gym_owner','Corrupt-zone owner',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status,erased_at) values
(pg_temp.u(101),pg_temp.u(1),pg_temp.u(11),pg_temp.u(906),'PRIVATE_MEMBER_101','+918300000101','active',null),
(pg_temp.u(102),pg_temp.u(1),pg_temp.u(11),pg_temp.u(907),'PRIVATE_MEMBER_102','+918300000102','active',null),
(pg_temp.u(106),pg_temp.u(2),pg_temp.u(14),pg_temp.u(912),'PRIVATE_FOREIGN_106','+918300000106','active',null),
(pg_temp.u(107),pg_temp.u(1),pg_temp.u(11),null,'PRIVATE_MEMBER_107','+918300000107','active',null);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values(pg_temp.u(201),pg_temp.u(1),'OCC plan',30,10000),(pg_temp.u(202),pg_temp.u(2),'OCC plan B',30,10000);
-- Membership 301 is member 101's first row (earliest created_at), 302 a
-- successor: the frozen OCC-012 rule classifies a payment by whether its
-- membership is the member's first, so created_at is pinned explicitly.
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,created_at) values
(pg_temp.u(301),pg_temp.u(1),pg_temp.u(101),pg_temp.u(201),'active','2025-06-01','2026-12-31',10000,'2025-06-01T00:00:00Z'),
-- Historical successor is closed: only one live membership per member.
(pg_temp.u(302),pg_temp.u(1),pg_temp.u(101),pg_temp.u(201),'expired','2026-01-10','2026-12-31',9000,'2026-01-10T00:00:00Z'),
(pg_temp.u(305),pg_temp.u(1),pg_temp.u(102),pg_temp.u(201),'active','2026-01-05','2026-12-31',10000,'2026-01-05T00:00:00Z'),
(pg_temp.u(306),pg_temp.u(2),pg_temp.u(106),pg_temp.u(202),'active','2026-01-05','2026-12-31',10000,'2026-01-05T00:00:00Z');
insert into public.organization_holidays(id,tenant_id,holiday_on,name) values(pg_temp.u(851),pg_temp.u(1),'2026-09-14','OCC fixture holiday');

-- Arrivals (front-office guarded path, each tenant through its own desk):
-- two same-member Monday 07:30 IST visits on different dates (OCC-004: two
-- accepted visits count twice), one second-hour visit on the holiday date,
-- two New York visits (one branch-locally outside the range, one inside but
-- on the tenant holiday date), one visit "today" for the incomplete-day
-- disclosure, and one FOREIGN visit that must never surface to tenant 1.
set local role authenticated;
select pg_temp.claim('front_desk',23,null,903,1);
insert into public.attendance(id,tenant_id,branch_id,member_id,membership_id,checked_in_at,source,assisted_by_staff_id,assist_reason) values
(pg_temp.u(611),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),pg_temp.u(301),'2026-09-14T02:00:00Z','front_desk',pg_temp.u(23),'OCC fixture'),
(pg_temp.u(612),pg_temp.u(1),pg_temp.u(11),pg_temp.u(102),pg_temp.u(305),'2026-09-21T02:00:00Z','front_desk',pg_temp.u(23),'OCC fixture'),
(pg_temp.u(613),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),pg_temp.u(301),'2026-09-14T04:00:00Z','front_desk',pg_temp.u(23),'OCC fixture'),
(pg_temp.u(614),pg_temp.u(1),pg_temp.u(12),pg_temp.u(102),pg_temp.u(305),'2026-09-14T02:00:00Z','front_desk',pg_temp.u(23),'OCC fixture'),
(pg_temp.u(615),pg_temp.u(1),pg_temp.u(12),pg_temp.u(102),pg_temp.u(305),'2026-09-15T02:00:00Z','front_desk',pg_temp.u(23),'OCC fixture');
select pg_temp.claim('gym_owner',25,null,905,2);
insert into public.attendance(id,tenant_id,branch_id,member_id,membership_id,checked_in_at,source,assisted_by_staff_id,assist_reason) values
(pg_temp.u(617),pg_temp.u(2),pg_temp.u(14),pg_temp.u(106),pg_temp.u(306),'2026-09-15T02:00:00Z','front_desk',pg_temp.u(25),'OCC fixture foreign');
-- The today arrival (616) is the settled member-gate shape (suite-82 lawful
-- mirror): rotating_screen gate setting, a live qr_sessions row, and the check-in
-- recorded under the member's own claims through that session — the trigger owns
-- checked_in_at (= the offline instant) and the replay stamp. No staff, no reason.
set local role postgres;
select set_config('request.jwt.claims','',true);
insert into public.organization_settings(tenant_id,checkin_gate_mode) values(pg_temp.u(1),'rotating_screen');
insert into public.qr_sessions(id,tenant_id,branch_id,token_hash,issued_at,expires_at,gate_mode,created_at) values
(pg_temp.u(440),pg_temp.u(1),pg_temp.u(11),'a6f2c9d4e1b37f80a5c2d9e4f1b8a3c6d9e2f5a8b1c4d7e0f3a6b9c2d5e8f1a4',statement_timestamp()-interval '1 hour',statement_timestamp()+interval '1 hour','rotating_screen',statement_timestamp());
set local role authenticated;
select pg_temp.claim('member',null,101,906,1);
-- The check-in itself goes through the canonical member gate-scan RPC (the
-- definer resolves the live session by token hash and inserts with
-- trigger-owned stamps); the returned row is captured for the today-hour pin.
create temp table occ_today_arrival as
select * from public.member_mobile_check_in('a6f2c9d4e1b37f80a5c2d9e4f1b8a3c6d9e2f5a8b1c4d7e0f3a6b9c2d5e8f1a4',pg_temp.u(460),statement_timestamp());
set local role postgres;
select set_config('request.jwt.claims','',true);

-- Money: 701 new-member money on the first membership; 702 renewal money on
-- the successor; 703 add-on money through its linked order; 704 unallocated
-- manual money; 705 a non-arrived attempt (excluded); 706 an arrived payment
-- with no paid_at (all-date warning); 707 sits exactly on the Feb 2 IST
-- midnight — excluded from the Jan-1..Feb-1 gym-local range by the upper
-- bound, but INSIDE the Jan-1..Mar-31 range (Feb money); 708 is one second
-- before it (included in both); 760 is foreign money that must never surface.
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,paid_at,created_at,recorded_by_staff_id) values
(pg_temp.u(701),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),100000,'INR','paid','cash','2026-01-15T05:00:00Z','2026-01-15T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(702),pg_temp.u(1),pg_temp.u(101),pg_temp.u(302),50000,'INR','paid','cash','2026-02-10T05:00:00Z','2026-02-10T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(703),pg_temp.u(1),pg_temp.u(102),null,5000,'INR','paid','cash','2026-02-20T05:00:00Z','2026-02-20T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(704),pg_temp.u(1),pg_temp.u(102),null,777,'INR','paid','cash','2026-02-21T05:00:00Z','2026-02-21T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(705),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),25000,'INR','created','cash',null,'2026-01-20T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(706),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),999,'INR','paid','cash',null,'2026-02-22T05:00:00Z',pg_temp.u(21)),
(pg_temp.u(707),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),12345,'INR','paid','cash','2026-02-01T18:30:00Z','2026-02-01T18:30:00Z',pg_temp.u(21)),
(pg_temp.u(708),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),30000,'INR','paid','cash','2026-02-01T18:29:59Z','2026-02-01T18:29:59Z',pg_temp.u(21)),
(pg_temp.u(760),pg_temp.u(2),pg_temp.u(106),pg_temp.u(306),4242,'INR','paid','cash','2026-02-10T05:00:00Z','2026-02-10T05:00:00Z',pg_temp.u(25));
insert into public.addon_products(id,tenant_id,kind,name,description,price_paise,validity_days,cancellation_terms,stock_quantity) values(pg_temp.u(401),pg_temp.u(1),'product','OCC product','Disclosed occupancy fixture product',5000,30,'Unopened product return within the disclosed validity window',5);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,status,quantity,unit_price_paise,total_paise,currency) values
(pg_temp.u(501),pg_temp.u(1),pg_temp.u(102),pg_temp.u(401),pg_temp.u(703),'paid',1,5000,5000,'INR');
-- Returns: 801 completes in a later month against a renewal payment (later-
-- month reduction, whole-receipt allocation); 802 requested (zero returned
-- cash); 803 completed (its processed_at is stamped by the refund invariant
-- on every write path — the completed-undated state is unreachable; see the
-- round-5 amendment below); 804 returns unallocated money (stays in the
-- unknown-allocation disclosure).
insert into public.refunds(id,tenant_id,payment_id,kind,amount_paise,currency,status,reason,processed_at) values
(pg_temp.u(801),pg_temp.u(1),pg_temp.u(702),'refund',5000,'INR','completed','OCC fixture','2026-03-05T05:00:00Z'),
(pg_temp.u(802),pg_temp.u(1),pg_temp.u(701),'refund',2000,'INR','requested','OCC fixture',null),
(pg_temp.u(803),pg_temp.u(1),pg_temp.u(701),'reversal',1500,'INR','completed','OCC fixture',null),
(pg_temp.u(804),pg_temp.u(1),pg_temp.u(704),'refund',100,'INR','completed','OCC fixture','2026-03-06T05:00:00Z');

-- Class cohort: two elapsed scheduled sessions (holding three and two
-- bookings), one cancelled session (excluded with its bookings), one future
-- session (excluded; its booking must not count).
insert into public.services(id,tenant_id,name,default_duration_minutes,default_capacity,is_active) values(pg_temp.u(411),pg_temp.u(1),'OCC service',45,10,true);
insert into public.class_sessions(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,status,cancelled_at,cancel_reason,cancelled_by_staff_id) values
(pg_temp.u(421),pg_temp.u(1),pg_temp.u(411),pg_temp.u(11),'2026-09-14','2026-09-14T01:00:00Z','2026-09-14T02:00:00Z',10,'scheduled',null,null,null),
(pg_temp.u(422),pg_temp.u(1),pg_temp.u(411),pg_temp.u(11),'2026-09-16','2026-09-16T01:00:00Z','2026-09-16T02:00:00Z',10,'scheduled',null,null,null),
(pg_temp.u(423),pg_temp.u(1),pg_temp.u(411),pg_temp.u(11),'2026-09-18','2026-09-18T01:00:00Z','2026-09-18T02:00:00Z',10,'cancelled',statement_timestamp(),'OCC fixture',pg_temp.u(21)),
(pg_temp.u(424),pg_temp.u(1),pg_temp.u(411),pg_temp.u(11),'2026-10-20','2026-10-20T01:00:00Z','2026-10-20T02:00:00Z',10,'scheduled',null,null,null);
insert into public.class_bookings(id,tenant_id,session_id,member_id,status,marked_at,acted_by_staff_id) values
(pg_temp.u(531),pg_temp.u(1),pg_temp.u(421),pg_temp.u(101),'attended',statement_timestamp(),pg_temp.u(23)),
(pg_temp.u(532),pg_temp.u(1),pg_temp.u(421),pg_temp.u(102),'no_show',statement_timestamp(),pg_temp.u(23)),
(pg_temp.u(533),pg_temp.u(1),pg_temp.u(421),pg_temp.u(107),'booked',null,null),
(pg_temp.u(534),pg_temp.u(1),pg_temp.u(422),pg_temp.u(101),'booked',null,null),
(pg_temp.u(535),pg_temp.u(1),pg_temp.u(422),pg_temp.u(102),'attended',statement_timestamp(),pg_temp.u(23)),
(pg_temp.u(536),pg_temp.u(1),pg_temp.u(424),pg_temp.u(101),'booked',null,null);

-- Registered corruption seam, applied AFTER every trigger-evaluating fixture
-- write (see the header note at the organizations insert): the foreign gym's
-- zone becomes 'Mars/Phobos' only here, with the commercial invariant trigger
-- disabled for the single UPDATE and restored immediately — every application
-- check below runs with the trigger enabled.
alter table public.organizations disable trigger organizations_commercial_invariant;
update public.organizations set timezone='Mars/Phobos' where id=pg_temp.u(2);
alter table public.organizations enable trigger organizations_commercial_invariant;

set local role authenticated;
select pg_temp.claim('gym_owner',21,null,901,1);

-- ============ A. signature and security shape ============
-- 1
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)')),'date date uuid boolean','OCC: owner_occupancy_analytics exact argument types including the holiday-exclusion toggle');
-- 2
select is((select array_to_string(proargtypes::regtype[],' ') from pg_proc where oid=to_regprocedure('public.owner_occupancy_analytics(date,date)')),'date date','OCC: the branch argument is nullable by default');
-- 3
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)') and not p.proretset and p.prorettype=to_regtype('jsonb')),'OCC: returns one jsonb snapshot value so one containing snapshot reaches the loader');
-- 4
select ok(exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)') and not p.prosecdef and pg_get_userbyid(p.proowner)='postgres' and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE') and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')),'OCC: invoker, postgres-owned, empty search path, authenticated-only execute');

-- ============ B. actor revalidation precedes any read ============
-- Top-level claims clear (subtransaction-local settings roll back with a
-- probe's begin/exception block, so a clear inside any wrapped context never
-- lands): section A left the fixture section's gym-owner claims at top level,
-- and every gate case below must be judged against an EMPTY claims context or
-- against the identity its own probe establishes.
select set_config('request.jwt.claims','',true);
-- 5
select is((select pg_temp.probe('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: missing claims are refused before any read');
-- 6
select is((select pg_temp.probe('select pg_temp.claim(''member'',null,101,906,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: a member claim gains no occupancy read');
-- 7
select is((select pg_temp.probe('select pg_temp.claim(''front_desk'',23,null,903,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: the front desk gains no occupancy read');
-- 8
select is((select pg_temp.probe('select pg_temp.claim(''trainer'',24,null,904,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: a trainer gains no occupancy read');
-- 9
select is((select pg_temp.probe('select pg_temp.claim(''super_admin'',null,null,928,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: a platform super admin gains no occupancy read');
-- 10
select is((select pg_temp.probe('select pg_temp.claim(''gym_owner'',21,null,901,1,true); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null,true)')),'42501','OCC-001: an impersonating session gains no occupancy read');
select pg_temp.claim('gym_owner',21,null,901,1);

-- ============ C. range and branch validation ============
-- 11
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-27'',''2026-09-14'',null,true)')),'22023','OCC-003: a reversed range is a value refusal');
-- 12
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-02-30'',''2026-03-01'',null,true)')),'22008','OCC-003: a non-Gregorian date is refused at the typed-date call parse (22008), before the body — the route''s zod layer rejects it earlier still');
-- 13
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(13),true)')),'22023','OCC-003: an invalid configured branch zone is an explicit zone error, not a fabricated zero');
-- 14
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(899),true)')),'P0002','OCC-001: an unknown branch is an invisible target');
-- 15
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(14),true)')),'P0002','OCC-001: a foreign branch shares the unknown-branch refusal');
-- 16
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null::uuid,null::boolean)')),'22023','OCC-003: a null holiday toggle is invalid, never silently defaulted');

-- ============ D. one snapshot: range echo, moneyRange, months, collection, warnings ============
-- Range R1 spans Jan 1..Feb 1 gym-local: 701 (Jan, new) and 708 (Feb 1
-- 23:59:59 IST, new) are inside; 707 sits exactly on the Feb 2 IST midnight
-- upper bound (excluded); 702/703/704 fall outside; 706 is undated (all-date
-- warning); 760 is foreign money (never surfaces).
-- 17
select ok(pg_temp.snapj('2026-01-01','2026-02-01',null) is not null and length(pg_temp.snapj('2026-01-01','2026-02-01',null)->>'asOf')>0,'OCC-002: the snapshot discloses one server asOf');
-- 18
select is(pg_temp.snapj('2026-01-01','2026-02-01',null)->>'zone','Asia/Kolkata','OCC-003: the top-level zone is the valid gym zone, never fabricated');
-- 19
select is(pg_temp.snapj('2026-01-01','2026-02-01',null)->'range',$j${"from":"2026-01-01","through":"2026-02-01","branchId":null,"excludeHolidays":true}$j$::jsonb,'OCC-002/003: the range echoes the actual resolved selection including the default exclusion toggle');
-- 20
select ok(pg_temp.snapj('2026-01-01','2026-02-01',null)->'moneyRange'->>'scope'='Whole gym' and pg_temp.snapj('2026-01-01','2026-02-01',null)->'moneyRange'->>'zone'='Asia/Kolkata' and pg_temp.snapj('2026-01-01','2026-02-01',null)->'moneyRange'->'error'='null'::jsonb and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{moneyRange,startsAt}')::timestamptz='2026-01-01T00:00:00+05:30'::timestamptz and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{moneyRange,endsBefore}')::timestamptz='2026-02-02T00:00:00+05:30'::timestamptz and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{moneyRange,cutoffAt}')::timestamptz=(pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{moneyRange,endsBefore}')::timestamptz and pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{moneyRange,localToday}'=pg_temp.gym_today()::text,'OCC-003: moneyRange is whole-gym gym-zone with selected-local-midnight boundaries, cutoff min(endsBefore,asOf) and disclosed localToday — the present-null error is tested as the jsonb null value, not SQL null');
-- 21
select is((select jsonb_agg(jsonb_build_object('month',m->>'month','from',m->>'from','through',m->>'through','coverage',m->>'coverage') order by m->>'month') from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-02-01',null)->'months') m),$j$[{"month":"2026-01","from":"2026-01-01","through":"2026-01-31","coverage":"full"},{"month":"2026-02","from":"2026-02-01","through":"2026-02-01","coverage":"partial"}]$j$::jsonb,'OCC-009/013: months contain every intersecting gym-local month ascending with clipped dates and truthful coverage — full January, partial single-day February endpoint');
-- 22
select ok(pg_temp.snapj('2026-01-01','2026-02-01',null)->'months'->0->'currencies'=$j$[{"currency":"INR","collectedPaise":"100000","returnedPaise":"0","netPaise":"100000","categories":{"label":"Membership linkage (derived classification)","newMember":{"collectedPaise":"100000","returnedPaise":"0","netPaise":"100000"},"renewal":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"addon":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"unallocated":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0","unknownReturnPaise":"0"}}}]$j$::jsonb and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,0,startsAt}')::timestamptz='2026-01-01T00:00:00+05:30'::timestamptz and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,0,endsBefore}')::timestamptz='2026-02-01T00:00:00+05:30'::timestamptz and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,0,cutoffAt}')::timestamptz=(pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,0,endsBefore}')::timestamptz,'OCC-009/012: January is exactly the new-member money 701 with month boundaries at clipped local midnights and cutoff = endsBefore');
-- 23
select ok(pg_temp.snapj('2026-01-01','2026-02-01',null)->'months'->1->'currencies'=$j$[{"currency":"INR","collectedPaise":"30000","returnedPaise":"0","netPaise":"30000","categories":{"label":"Membership linkage (derived classification)","newMember":{"collectedPaise":"30000","returnedPaise":"0","netPaise":"30000"},"renewal":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"addon":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"unallocated":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0","unknownReturnPaise":"0"}}}]$j$::jsonb and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,1,startsAt}')::timestamptz='2026-02-01T00:00:00+05:30'::timestamptz and (pg_temp.snapj('2026-01-01','2026-02-01',null)#>>'{months,1,endsBefore}')::timestamptz='2026-02-02T00:00:00+05:30'::timestamptz,'OCC-003/009: February holds only 708 — 707 sits exactly on the exclusive upper bound and contributes nothing');
-- 24
select is(pg_temp.snapj('2026-01-01','2026-03-31',null)->'months'->1->'currencies',$j$[{"currency":"INR","collectedPaise":"98122","returnedPaise":"0","netPaise":"98122","categories":{"label":"Membership linkage (derived classification)","newMember":{"collectedPaise":"42345","returnedPaise":"0","netPaise":"42345"},"renewal":{"collectedPaise":"50000","returnedPaise":"0","netPaise":"50000"},"addon":{"collectedPaise":"5000","returnedPaise":"0","netPaise":"5000"},"unallocated":{"collectedPaise":"777","returnedPaise":"0","netPaise":"777","unknownReturnPaise":"0"}}}]$j$::jsonb,'OCC-012: exact February classification in the wide range — 707 (Feb 2 IST) inside joins 708 as first-membership money, successor renewal, add-on via order linkage, unallocated manual, no double counting');
-- 25
select is(pg_temp.snapj('2026-01-01','2026-03-31',null)->'months'->2->'currencies',$j$[{"currency":"INR","collectedPaise":"0","returnedPaise":"5100","netPaise":"-5100","categories":{"label":"Membership linkage (derived classification)","newMember":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"renewal":{"collectedPaise":"0","returnedPaise":"5000","netPaise":"-5000"},"addon":{"collectedPaise":"0","returnedPaise":"0","netPaise":"0"},"unallocated":{"collectedPaise":"0","returnedPaise":"100","netPaise":"-100","unknownReturnPaise":"100"}}}]$j$::jsonb,'OCC-010/012: a later-month completed return reduces that month (negative net visible), allocated whole to the original receipt''s category; an unallocated original stays unknown');
-- 26
select is(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'currencies',$j$[{"currency":"INR","collectedPaise":"198122","returnedPaise":"5100","netPaise":"193022","categories":{"label":"Membership linkage (derived classification)","newMember":{"collectedPaise":"142345","returnedPaise":"0","netPaise":"142345"},"renewal":{"collectedPaise":"50000","returnedPaise":"5000","netPaise":"45000"},"addon":{"collectedPaise":"5000","returnedPaise":"0","netPaise":"5000"},"unallocated":{"collectedPaise":"777","returnedPaise":"100","netPaise":"677","unknownReturnPaise":"100"}}}]$j$::jsonb,'OCC-009/010/012: the whole-range collection reconciles exactly from the same components — categories sum to the totals at every field, net = collected − returned');
-- 27
select is((select jsonb_agg(r->>'paymentId') from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'collected') r),$j$["83000000-0000-4000-8000-000000000701","83000000-0000-4000-8000-000000000708","83000000-0000-4000-8000-000000000707","83000000-0000-4000-8000-000000000702","83000000-0000-4000-8000-000000000703","83000000-0000-4000-8000-000000000704"]$j$::jsonb,'OCC-002/012: collected components are the real receipt rows sorted by event instant then id — 708 one second before 707 at the same instant boundary');
-- 28
select is((select jsonb_agg(jsonb_build_object('returnId',r->>'returnId','paymentId',r->>'paymentId','amountPaise',r->>'amountPaise','currency',r->>'currency','category',r->>'category','allocationUnknown',r->'allocationUnknown','membershipEvidence',r->'membershipEvidence')) from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'returned') r),$j$[{"returnId":"83000000-0000-4000-8000-000000000801","paymentId":"83000000-0000-4000-8000-000000000702","amountPaise":"5000","currency":"INR","category":"renewal","allocationUnknown":false,"membershipEvidence":{"createdAt":"2026-01-10T00:00:00Z","hasEarlierMembership":true}},{"returnId":"83000000-0000-4000-8000-000000000804","paymentId":"83000000-0000-4000-8000-000000000704","amountPaise":"100","currency":"INR","category":"unallocated","allocationUnknown":true,"membershipEvidence":null}]$j$::jsonb,'OCC-010/012: returned components carry the original receipt''s category whole — renewal evidence from the successor membership, unknown-allocation flagged exactly for the unallocated original');
-- 29
select ok((select r->>'category'='newMember' and r#>>'{membershipEvidence,hasEarlierMembership}'='false' and (r#>>'{membershipEvidence,createdAt}')::timestamptz='2025-06-01T00:00:00Z'::timestamptz from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'collected') r where r->>'paymentId'=pg_temp.u(701)::text) and (select r->>'category'='renewal' and r#>>'{membershipEvidence,hasEarlierMembership}'='true' and (r#>>'{membershipEvidence,createdAt}')::timestamptz='2026-01-10T00:00:00Z'::timestamptz from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'collected') r where r->>'paymentId'=pg_temp.u(702)::text),'OCC-012: membership evidence is the receipt''s own membership row — first row means newMember, a strictly-earlier same-member row means renewal');
-- 30
select ok((select r->>'category'='addon' and r->'membershipEvidence'='null'::jsonb from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'collected') r where r->>'paymentId'=pg_temp.u(703)::text) and (select r->>'category'='unallocated' and r->'membershipEvidence'='null'::jsonb from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection'->'components'->'collected') r where r->>'paymentId'=pg_temp.u(704)::text),'OCC-012: add-on money through its order link and unallocated manual money carry no membership evidence — the present null is asserted as the jsonb null value');
-- 31
select is(pg_temp.snapj('2026-01-01','2026-03-31',null)->'warnings'->'undatedPayments',$j$[{"paymentId":"83000000-0000-4000-8000-000000000706","amountPaise":"999","currency":"INR"}]$j$::jsonb,'OCC-009: an arrived payment without paid_at stays in a visible all-date warning with exactly its pinned keys');
-- 32
select ok((select r.processed_at is not null from public.refunds r where r.id=pg_temp.u(803)) and (select coalesce(bool_and(r.processed_at is not null),true) from public.refunds r where r.tenant_id=pg_temp.u(1) and r.status='completed') and pg_temp.snapj('2026-01-01','2026-03-31',null)->'warnings'->'undatedReturns'=$j$[]$j$::jsonb,'OCC-010 (adjudicated amendment, runtime evidence): a completed return is stamped on every write path — the completed-undated state is unreachable, so the coupled invariant is pinned directly (every staged completed refund carries a stamped processed_at) and the snapshot discloses no undatedReturns under lawful staging');
-- 33
select ok(pg_temp.snapj('2026-01-01','2026-03-31',null)->'warnings'->>'scope'='Current all-date' and pg_temp.snapj('2026-01-01','2026-03-31',null)->'warnings'->'totals'=$j$[{"currency":"INR","undatedPaymentCount":"1","undatedPaymentPaise":"999","undatedReturnCount":"0","undatedReturnPaise":"0"}]$j$::jsonb,'OCC-009/010 (amended with the adjudicated unreachable-state finding): the all-date warning scope is disclosed and its totals sum exclusively from those arrays per currency — the returns array is empty under lawful staging, and its zero totals still sum exactly from it');
-- 34
select ok(pg_temp.snapj('2026-01-01','2026-03-31',null)::text not like '%4242%','OCC-001: foreign money contributes nothing anywhere in the snapshot');
-- 35
select is((select jsonb_agg(m->>'month') from jsonb_array_elements(pg_temp.snapj('2026-01-01','2026-03-31',null)->'months') m),$j$["2026-01","2026-02","2026-03"]$j$::jsonb,'OCC-009: months ascend over every intersecting gym-local month');
-- 36
select ok((pg_temp.snapj('2026-01-01','2026-03-31',null)->'months')::text not like '%25000%' and (pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection')::text not like '%25000%','OCC-009: a non-arrived attempt contributes no collected cash and no payment warning');

-- ============ E. whole-gym heatmap (gym zone, holiday exclusion) ============
-- Whole-gym arrivals are bucketed in the disclosed gym zone (a local-time
-- comparison, OCC-008); the foreign branch never appears; the invalid branch
-- stays visible with its error instead of a fabricated zero.
-- 37
select is(pg_temp.snapj('2026-09-14','2026-09-27',null)->'heatmap'->>'alignment','Local time','OCC-008: clock-time alignment is labelled a local-time comparison, not simultaneous instants');
-- 38
select is((select jsonb_agg(b->>'branchId') from jsonb_array_elements(pg_temp.snapj('2026-09-14','2026-09-27',null)->'heatmap'->'branches') b),$j$["83000000-0000-4000-8000-000000000011","83000000-0000-4000-8000-000000000012","83000000-0000-4000-8000-000000000013"]$j$::jsonb,'OCC-008: the branch array is the selected visible branch population sorted by branchId — the foreign branch is never present');
-- 39
select ok(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'zone'='Asia/Kolkata' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'zoneSource'='gym' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'error'='null'::jsonb,'OCC-003: an inherited gym zone is disclosed with its source and no error — the present null is asserted as the jsonb null value');
-- 40
select ok((pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))#>>'{range,startsAt}')::timestamptz='2026-09-14T00:00:00+05:30'::timestamptz and (pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))#>>'{range,endsBefore}')::timestamptz='2026-09-28T00:00:00+05:30'::timestamptz and (pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))#>>'{range,cutoffAt}')::timestamptz=(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))#>>'{range,endsBefore}')::timestamptz and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))#>>'{range,localToday}'=pg_temp.gym_today()::text,'OCC-003: the branch range is that branch''s effective-zone local midnights with cutoff and disclosed localToday');
-- 41
select is(pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-14')->>'visits','2','OCC-005: the excluded holiday date still discloses its real visit count from the same snapshot');
-- 42
select is(pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-14')->'hours',$j$[{"hour":0,"exists":true,"visits":"0"},{"hour":1,"exists":true,"visits":"0"},{"hour":2,"exists":true,"visits":"0"},{"hour":3,"exists":true,"visits":"0"},{"hour":4,"exists":true,"visits":"0"},{"hour":5,"exists":true,"visits":"0"},{"hour":6,"exists":true,"visits":"0"},{"hour":7,"exists":true,"visits":"1"},{"hour":8,"exists":true,"visits":"0"},{"hour":9,"exists":true,"visits":"1"},{"hour":10,"exists":true,"visits":"0"},{"hour":11,"exists":true,"visits":"0"},{"hour":12,"exists":true,"visits":"0"},{"hour":13,"exists":true,"visits":"0"},{"hour":14,"exists":true,"visits":"0"},{"hour":15,"exists":true,"visits":"0"},{"hour":16,"exists":true,"visits":"0"},{"hour":17,"exists":true,"visits":"0"},{"hour":18,"exists":true,"visits":"0"},{"hour":19,"exists":true,"visits":"0"},{"hour":20,"exists":true,"visits":"0"},{"hour":21,"exists":true,"visits":"0"},{"hour":22,"exists":true,"visits":"0"},{"hour":23,"exists":true,"visits":"0"}]$j$::jsonb,'OCC-004/006: day hours are the ordered 0..23 clock-hour exposures with existing clock hours marked and hour visits summing to the day visits');
-- 43
select ok((select count(*)=14 and bool_and((e->>'localDate')::date >= '2026-09-14' and (e->>'localDate')::date <= '2026-09-27') from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'days') e) and pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-14')->>'isHoliday'='true' and pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-14')->>'excluded'='true' and pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-14')->>'state'='completed' and pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),'2026-09-21')->>'visits'='1','OCC-005/006: one day row per selected local date ascending with truthful holiday/state/excluded flags');
-- 44
select is(jsonb_build_object('totalVisits',pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'totalVisits','completedVisits',pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'completedVisits','currentDayVisits',pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'currentDayVisits','excludedVisits',pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'excludedVisits'),$j${"totalVisits":"1","completedVisits":"1","currentDayVisits":"0","excludedVisits":"2"}$j$::jsonb,'OCC-004/005: totals reconcile — nonexcluded visits only in total/completed, both holiday-date visits disclosed as excluded');
-- 45
select is(pg_temp.cell(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11),1,7),$j${"weekday":1,"hour":7,"arrivals":"1","todayArrivals":"0","eligibleDates":"13","fraction":{"numerator":"1","denominator":"13","basisPoints":"769"},"limited":true,"message":"Limited history"}$j$::jsonb,'OCC-006/007: the Monday 07:00 cell is the exact raw fraction 1/13 half-up 769 bp with the numerator drawn only from eligible dates, today disclosed separately, and Limited history below the 14-date threshold');
-- 46
select ok((select count(*)=168 from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'cells') c) and (select min(((c->>'weekday')::integer*24+(c->>'hour')::integer))=0 and max(((c->>'weekday')::integer*24+(c->>'hour')::integer))=167 from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'cells') c) and not exists(select 1 from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'cells') c where not (c ? 'weekday' and c ? 'hour' and c ? 'arrivals' and c ? 'todayArrivals' and c ? 'eligibleDates' and c ? 'fraction' and c ? 'limited' and c ? 'message')) and not exists(select 1 from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'cells') c where (c->>'eligibleDates')<>'13' or (c->>'limited')<>'true'),'OCC-006/007: cells are all 168 weekday/hour coordinates in coordinate order, each with the exact cell keys, the same 13 eligible dates and the below-threshold limit');
-- 47
select is(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'week',$j${"arrivals":"1","eligibleDates":"13","fraction":{"numerator":"1","denominator":"13","basisPoints":"769"},"limited":true,"message":"Limited history"}$j$::jsonb,'OCC-007: the branch week aggregate counts each eligible date once — 1 arrival over 13 eligible dates, never an average of cell averages');
-- 48
select ok(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'availability'='complete' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->>'noEligibleDays'='false','OCC-005: a fully completed range with a nonexcluded day is complete and not a no-eligible-days branch');
-- 49
select ok(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'zone'='Mars/Phobos' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'zoneSource'='branch' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'error'=$j${"code":"invalid_branch_timezone"}$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'range'='null'::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'totalVisits' is null and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'excludedVisits' is null and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'days'=$j$[]$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'cells'=$j$[]$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'week'='null'::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'availability' is null,'OCC-003/008: an invalid configured branch zone keeps its branch entry with the preserved zone text and explicit error — no fallback zero, no silent dropping');
-- 50
select is(pg_temp.snapj('2026-09-14','2026-09-27',null)->'heatmap'->'reconciliation',$j${"complete":false,"totalVisits":null,"completedVisits":null,"currentDayVisits":null,"excludedVisits":null}$j$::jsonb,'OCC-008: reconciliation with an invalid included branch is incomplete with null totals, never an apparent organization total that silently omits errors');

-- ============ F. selected branch (zone override, branch-local range, cash invariance) ============
-- 51
select is((select jsonb_agg(b->>'branchId') from jsonb_array_elements(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12))->'heatmap'->'branches') b),$j$["83000000-0000-4000-8000-000000000012"]$j$::jsonb,'OCC-001: a selected branch narrows the analytics population to exactly that visible branch');
-- 52
select ok(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->>'zone'='America/New_York' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->>'zoneSource'='branch' and (pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))#>>'{range,startsAt}')::timestamptz='2026-09-14T00:00:00-04:00'::timestamptz and (pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))#>>'{range,endsBefore}')::timestamptz='2026-09-28T00:00:00-04:00'::timestamptz,'OCC-003: the branch timezone override is the effective zone and its range boundaries are that zone''s local midnights');
-- 53
select ok(pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12),'2026-09-14')->>'excluded'='true' and pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12),'2026-09-14')->>'visits'='1' and (select (e->>'visits')='1' from jsonb_array_elements(pg_temp.day(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12),'2026-09-14')->'hours') e where (e->>'hour')='22') and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->>'totalVisits'='0' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->>'excludedVisits'='1' and (select count(*)=14 from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->'days') e),'OCC-003/005: the Sep 13 New-York visit lies branch-locally outside the range and the Sep 14 22:00 visit is holiday-excluded — no arrival survives into exposure');
-- 54
select ok((select bool_and((c->>'arrivals')='0' and (c->>'eligibleDates')='13') from jsonb_array_elements(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->'cells') c),'OCC-006: the override branch carries zero arrivals with the same 13-eligible-date denominator');
-- 55
select ok(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12))->'collection'->'currencies'=pg_temp.snapj('2026-09-14','2026-09-27',null)->'collection'->'currencies' and pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12))->'moneyRange'=pg_temp.snapj('2026-09-14','2026-09-27',null)->'moneyRange','OCC-013: the branch selector never changes whole-gym cash populations or money coverage');

-- ============ G. incomplete today, current month, future month ============
-- 56
-- Re-planned snapshot call (coordinator adjudication): the resolved selection must
-- contain the asOf-derived current day, so the pin calls a seven-day window ending
-- at the run day instead of the single-day range the capture showed excluded it.
-- The disclosed hour is derived from the STORED gate-scan instant (the captured member RPC row), not
-- from now() at assertion time — the suite may legitimately cross an hour
-- boundary between the fixture insert and this assertion, and the pin's subject
-- is the recorded arrival's clock hour.
select is(pg_temp.day(pg_temp.snapj(pg_temp.gym_today()-6,pg_temp.gym_today(),null),pg_temp.u(11),pg_temp.gym_today())->>'state','current','#56a today day state: the asOf day is current in the branch heatmap');
select is(pg_temp.day(pg_temp.snapj(pg_temp.gym_today()-6,pg_temp.gym_today(),null),pg_temp.u(11),pg_temp.gym_today())->>'visits','1','#56b today day visits: the recorded gate-scan arrival is counted in the day total');
select is((select e->>'visits' from jsonb_array_elements(pg_temp.day(pg_temp.snapj(pg_temp.gym_today()-6,pg_temp.gym_today(),null),pg_temp.u(11),pg_temp.gym_today())->'hours') e where (e->>'hour')=(select extract(hour from t.checked_in_at at time zone 'Asia/Kolkata')::text from occ_today_arrival t limit 1)),'1','#56c today clock hour: the arrival sits in its own recorded clock-hour cell, never mixed into a completed average');
-- 58
select ok(pg_temp.hb(pg_temp.snapj(pg_temp.gym_today(),pg_temp.gym_today(),null),pg_temp.u(11))->>'availability'='partial' and pg_temp.hb(pg_temp.snapj(pg_temp.gym_today(),pg_temp.gym_today(),null),pg_temp.u(11))->>'noEligibleDays'='false','OCC-006: a current day makes availability partial and is not a no-eligible-days branch');
-- 59
select ok(pg_temp.snapj(pg_temp.gym_today(),pg_temp.gym_today(),null)->'moneyRange'->>'cutoffAt'=pg_temp.snapj(pg_temp.gym_today(),pg_temp.gym_today(),null)->>'asOf','OCC-002/003: the current range cutoff is the snapshot asOf itself');
-- 60
select is((select jsonb_agg(jsonb_build_object('month',m->>'month','from',m->>'from','through',m->>'through','coverage',m->>'coverage','currencies',m->'currencies') order by m->>'month') from jsonb_array_elements(pg_temp.snapj(pg_temp.gym_today(),pg_temp.gym_today(),null)->'months') m),jsonb_build_array(jsonb_build_object('month',to_char(pg_temp.gym_today(),'YYYY-MM'),'from',pg_temp.gym_today()::text,'through',pg_temp.gym_today()::text,'coverage','partial','currencies',$j$[]$j$::jsonb)),'OCC-009/013: the current month appears as Month-to-date partial with no invented currency zeros when no dated cash exists in it');
-- 61
select is((select jsonb_agg(jsonb_build_object('month',m->>'month','coverage',m->>'coverage','currencies',m->'currencies') order by m->>'month') from jsonb_array_elements(pg_temp.snapj('2027-01-01','2027-01-31',null)->'months') m),$j$[{"month":"2027-01","coverage":"unavailable","currencies":[]}]$j$::jsonb,'OCC-003: an entirely future month is unavailable with no currency zeros, never a full-period zero');

-- ============ H. class cohort and booked fill ============
-- 62
select is(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'summary',$j${"cohortSessions":"2","totalCapacity":"20","holdingBookings":"5","attendedCount":"2","noShowCount":"1","unmarkedCount":"2","cancelledSessionsExcluded":"1","bookedFill":{"numerator":"5","denominator":"20","basisPoints":"2500"},"markedPresence":{"numerator":"2","denominator":"20","basisPoints":"1000"},"markingCoverage":{"numerator":"3","denominator":"5","basisPoints":"6000"},"incompleteMarkingDisclosed":true,"limited":true,"message":"Limited history"}$j$::jsonb,'OCC-014/015/016: exact elapsed non-cancelled cohort — stored capacity, capacity-weighted fractions, cancelled excluded, no-show holds a seat, unmarked disclosed, coverage separate, 2 sessions below the 10-session threshold');
-- 63
select is(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'sessions'->0,jsonb_build_object('sessionId',pg_temp.u(421),'serviceId',pg_temp.u(411),'sessionDate','2026-09-14','startsAt','2026-09-14T01:00:00Z','endsAt','2026-09-14T02:00:00Z','capacity','10','bookedCount','1','attendedCount','1','noShowCount','1','holdingBookings','3','bookedFill',pg_temp.fr('3','10','3000'),'markedPresence',pg_temp.fr('1','10','1000'),'markingCoverage',pg_temp.fr('2','3','6667')),'OCC-014/015/016 (declaration line 143 amendment): the holiday session stayed in the cohort and its drill row carries the full declared key set including startsAt and endsAt — one booked, one attended, one no-show over stored capacity 10');
-- 64
select is(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'sessions'->1,jsonb_build_object('sessionId',pg_temp.u(422),'serviceId',pg_temp.u(411),'sessionDate','2026-09-16','startsAt','2026-09-16T01:00:00Z','endsAt','2026-09-16T02:00:00Z','capacity','10','bookedCount','1','attendedCount','1','noShowCount','0','holdingBookings','2','bookedFill',pg_temp.fr('2','10','2000'),'markedPresence',pg_temp.fr('1','10','1000'),'markingCoverage',pg_temp.fr('1','2','5000')),'OCC-015/016 (declaration line 143 amendment): the second elapsed session drills exactly with the full declared key set including startsAt and endsAt — an unmarked booking stays booked, coverage counts only explicitly marked facts');
-- 65
select is((select jsonb_agg(s->>'sessionId') from jsonb_array_elements(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'sessions') s),$j$["83000000-0000-4000-8000-000000000421","83000000-0000-4000-8000-000000000422"]$j$::jsonb,'OCC-014: the cohort is ordered sessionDate,startsAt,sessionId and excludes both the cancelled and the future session (the future booking contributes nothing)');
-- 66
select ok(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'cancelledSessions'=$j$[{"sessionId":"83000000-0000-4000-8000-000000000423","serviceId":"83000000-0000-4000-8000-000000000411","sessionDate":"2026-09-18","startsAt":"2026-09-18T01:00:00Z","endsAt":"2026-09-18T02:00:00Z"}]$j$::jsonb,'OCC-014 (captured-envelope amendment): the cancelled elapsed session is disclosed in the five-key drill form — identity keys plus its instants — without capacity, bookings or any attendance fractions');
-- 67
select is(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(11))->'services',$j$[{"serviceId":"83000000-0000-4000-8000-000000000411","summary":{"cohortSessions":"2","totalCapacity":"20","holdingBookings":"5","attendedCount":"2","noShowCount":"1","unmarkedCount":"2","cancelledSessionsExcluded":"1","bookedFill":{"numerator":"5","denominator":"20","basisPoints":"2500"},"markedPresence":{"numerator":"2","denominator":"20","basisPoints":"1000"},"markingCoverage":{"numerator":"3","denominator":"5","basisPoints":"6000"},"incompleteMarkingDisclosed":true,"limited":true,"message":"Limited history"}}]$j$::jsonb,'OCC-015 (declaration line 148 amendment): each rollup item is the full declared {serviceId, summary} pair — the sole cohort service''s aggregate equals the branch summary, and exact-key equality subsumes the no-trainer/member-identifier property');
-- 68
select is(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',pg_temp.u(12)),pg_temp.u(12))->'summary',$j${"cohortSessions":"0","totalCapacity":"0","holdingBookings":"0","attendedCount":"0","noShowCount":"0","unmarkedCount":"0","cancelledSessionsExcluded":"0","bookedFill":{"numerator":"0","denominator":"0","basisPoints":null},"markedPresence":{"numerator":"0","denominator":"0","basisPoints":null},"markingCoverage":{"numerator":"0","denominator":"0","basisPoints":null},"incompleteMarkingDisclosed":false,"limited":true,"message":"Limited history"}$j$::jsonb,'OCC-015: a branch with no elapsed sessions has a truthful zero-cohort summary — zero denominator returns no fraction, not a zero');
-- 69
select ok(pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'summary' is null and pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'error'=$j${"code":"invalid_branch_timezone"}$j$::jsonb and pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->>'availability' is null and pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'services'=$j$[]$j$::jsonb and pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'sessions'=$j$[]$j$::jsonb and pg_temp.cb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(13))->'cancelledSessions'=$j$[]$j$::jsonb,'OCC-014: an invalid branch keeps its classes entry with null summary and empty arrays');
-- 70
select is(pg_temp.snapj('2026-09-14','2026-09-27',null)->'classes'->'reconciliation',$j${"complete":false,"summary":null}$j$::jsonb,'OCC-015: class reconciliation with an invalid branch is incomplete with a null aggregate, never a mean of percentages');
-- 71
select is((select jsonb_agg(b->>'branchId') from jsonb_array_elements(pg_temp.snapj('2026-09-14','2026-09-27',null)->'classes'->'branches') b),$j$["83000000-0000-4000-8000-000000000011","83000000-0000-4000-8000-000000000012","83000000-0000-4000-8000-000000000013"]$j$::jsonb,'OCC-008: the classes branch array mirrors the same selected visible population sorted by branchId');

-- ============ I. existing seams untouched and the holiday toggle ============
-- 72
select ok(to_regprocedure('public.owner_metrics(date,date)') is not null and (select provolatile from pg_proc where oid=to_regprocedure('public.owner_metrics(date,date)'))='s' and not (select prosecdef from pg_proc where oid=to_regprocedure('public.owner_metrics(date,date)')),'OCC: the existing owner_metrics seam is untouched (still stable, still invoker)');
-- 73
select ok(to_regprocedure('public.owner_metrics(date,date)') is distinct from to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)'),'OCC: the analytics read is one versioned extension, not a changed owner_metrics');
-- 74
select ok(pg_temp.hb(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11))->>'totalVisits'='3' and pg_temp.hb(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11))->>'excludedVisits'='0' and pg_temp.day(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11),'2026-09-14')->>'excluded'='false' and pg_temp.day(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11),'2026-09-14')->>'isHoliday'='true' and pg_temp.cell(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11),1,7)->>'arrivals'='2' and pg_temp.cell(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11),1,7)->'fraction'=pg_temp.fr('2','14','1429') and pg_temp.hb(pg_temp.snapjx('2026-09-14','2026-09-27',null,false),pg_temp.u(11))->'week'=$j${"arrivals":"3","eligibleDates":"14","fraction":{"numerator":"3","denominator":"14","basisPoints":"2143"},"limited":false,"message":null}$j$::jsonb,'OCC-005: with the exclusion toggle off the holiday date returns to every denominator — 14 eligible dates, both holiday visits back in their cells, week 3/14, and the isHoliday fact stays visible');
-- 75
select ok(pg_temp.snapjx('2026-01-01','2026-03-31',null,true)->'collection'->'currencies'=pg_temp.snapjx('2026-01-01','2026-03-31',null,false)->'collection'->'currencies' and pg_temp.snapjx('2026-01-01','2026-03-31',null,true)->'months'=pg_temp.snapjx('2026-01-01','2026-03-31',null,false)->'months','OCC-005: the holiday toggle never moves actual payments, returns or class money');

-- ============ J. invalid gym zone envelope ============
-- Routing through the OWNED tenant-2 owner binding (adjudication option (a)):
-- the actor is a gym_owner whose staff binding lives in the corrupt gym, so
-- every lawful tenant resolution path (claims or owned binding) lands on
-- organizations …2.
select pg_temp.claim('gym_owner',26,null,916,2);
-- Defensive re-assertion (capture adjudication: a captured call hit the VALID
-- tenant): the routing claims are restated immediately before the snapshot calls
-- so the invalid-zone envelope is exercised strictly under the corrupt gym's
-- owner identity.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(916),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(2),'staff_id',pg_temp.u(26))::text,true);
-- 76
-- Per-call routing (capture adjudication round 13): the tenant-2 owner claims are
-- set immediately before this call, at top level, outside any wrapper.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.u(916),'role','authenticated','app_role','gym_owner','tenant_id',pg_temp.u(2),'staff_id',pg_temp.u(26))::text,true);
select is(current_setting('request.jwt.claims',true)::jsonb->>'tenant_id',pg_temp.u(2)::text,'#76 routing echo: the live claims tenant read in the same statement context as the snapshot call is the corrupt gym');
select ok(pg_temp.snapj('2026-01-01','2026-03-31',null)->>'zone' is null and pg_temp.snapj('2026-01-01','2026-03-31',null)->'moneyRange'->>'scope'='Whole gym' and pg_temp.snapj('2026-01-01','2026-03-31',null)->'moneyRange'->>'zone' is null and pg_temp.snapj('2026-01-01','2026-03-31',null)->'moneyRange'->'error'=$j${"code":"invalid_gym_timezone"}$j$::jsonb and pg_temp.snapj('2026-01-01','2026-03-31',null)->'moneyRange'->>'startsAt' is null and pg_temp.snapj('2026-01-01','2026-03-31',null)->'months'=$j$[]$j$::jsonb and pg_temp.snapj('2026-01-01','2026-03-31',null)->'collection' is null,'OCC-003 (routing first): the snapshot call executes under the corrupt gym''s owner identity — the claims context itself is pinned as the first conjunct so a fallthrough to the valid tenant is named, and the invalid gym zone yields explicit derived-field nulls, empty months and null collection');
-- 77
select ok(pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->>'zone'='Mars/Phobos' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->>'zoneSource'='gym' and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->'error'=$j${"code":"invalid_gym_timezone"}$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->'days'=$j$[]$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->'cells'=$j$[]$j$::jsonb and pg_temp.hb(pg_temp.snapj('2026-09-14','2026-09-27',null),pg_temp.u(14))->>'availability' is null,'OCC-003: a branch inheriting an invalid gym zone discloses the inherited zone text, its source and the gym-zone error');
select pg_temp.claim('gym_owner',21,null,901,1);

select * from finish();
rollback;
