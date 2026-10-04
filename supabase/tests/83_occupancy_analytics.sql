-- OCC-001..017 independent visible contract (Wave D occupancy, collection and
-- class fill analytics). Frozen authority:
-- openspec/changes/occupancy-analytics/proposal.md (FROZEN 2026-10-03) with the
-- owner-resolved choices recorded in OCC-007 (14/10/28 thresholds, no
-- estimator) and OCC-012 (derived membership-linkage classification,
-- whole-receipt return allocation, unallocated stays unknown). The loader
-- apps/web/lib/occupancy.ts pins the caller seam: exactly one rpc call
-- `owner_occupancy_analytics(p_from date, p_through date, p_branch_id uuid
-- default null)` whose single jsonb value carries asOf/months/heatmap/classes/
-- warnings (one containing snapshot, OCC-002); the deeper jsonb keys pinned
-- below are this suite's contract for
-- the implementing migration. No implementation, holdout or other OCC test
-- material was read.
--
-- RED pattern: no mirror DDL. Catalog assertions are NULL-safe
-- (to_regprocedure) and every dynamic statement runs through a catching
-- executor, so the file runs end-to-end RED before the analytics migration
-- exists (missing function 42883) and judges the real implementation once CI
-- applies it. Nothing commits: one begin/rollback pair.
--
-- Refusal-code assumptions pinned from the frozen contract plus the repo's
-- shared precedence vocabulary: actor/privilege failures 42501; value/shape
-- validation (reversed/invalid dates, invalid configured zone) 22023; unknown
-- and foreign branch share one invisible-target refusal P0002 (no existence
-- oracle). If the implementer maps any of these differently, that is a
-- contract-defect round-trip to the test author, not a test edit by the
-- implementer.
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
select plan(44);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$select ('83000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.claim(r text default 'gym_owner', s integer default null, m integer default null, a integer default 901, t integer default 1, p boolean default false) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',pg_temp.u(a),'role','authenticated','app_role',r,'tenant_id',pg_temp.u(t),'staff_id',case when s is not null then pg_temp.u(s) end,'member_id',case when m is not null then pg_temp.u(m) end,'impersonation_session_id',case when p then pg_temp.u(999) end))::text,true); end$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.state(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return split_part(sqlstate||':'||message,':',1); end$$;
-- Section G derives its range from the CURRENT gym-local run day (the
-- fixture organization's own zone), so the incomplete-today disclosures stay
-- deterministic on any run date. Callers of gym_today() re-read it per
-- assertion; the only seeded visit on that day is 616 (now()).
create function pg_temp.gym_today() returns date language sql volatile as $$select (now() at time zone (select timezone from public.organizations where id = pg_temp.u(1)))::date$$;
create function pg_temp.snap(p_from date, p_through date, p_branch_id uuid default null) returns text language plpgsql as $$declare r text; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid)::text' using p_from,p_through,p_branch_id into r; return r; exception when others then return sqlstate; end$$;
create function pg_temp.snapx(p_from date, p_through date, p_branch_id uuid, p_exclude_holidays boolean) returns text language plpgsql as $$declare r text; begin execute 'select public.owner_occupancy_analytics($1::date,$2::date,$3::uuid,$4::boolean)::text' using p_from,p_through,p_branch_id,p_exclude_holidays into r; return r; exception when others then return sqlstate; end$$;
grant execute on function pg_temp.u(integer),pg_temp.claim(text,integer,integer,integer,integer,boolean),pg_temp.probe(text),pg_temp.state(text),pg_temp.snap(date,date,uuid),pg_temp.snapx(date,date,uuid,boolean),pg_temp.gym_today() to authenticated,anon,service_role;

-- ============ fixtures (existing schema only) ============
insert into auth.users(id) select pg_temp.u(n) from generate_series(901,916) n;
-- SLF/OCC frozen actor contract: platform subjects also require auth.users provenance.
insert into auth.users(id) values(pg_temp.u(928));
insert into public.platform_users(user_id,role,full_name,email,is_active) values(pg_temp.u(928),'super_admin','OCC root','occ83-root@example.test',true);
insert into public.organizations(id,name,gym_code,status,timezone) values(pg_temp.u(1),'OCC A','OCC83A','active','Asia/Kolkata'),(pg_temp.u(2),'OCC B','OCC83B','active','Asia/Kolkata');
-- Branch 11 inherits the gym zone (null override), 12 overrides to New York,
-- 13 carries an invalid configured zone, 14 belongs to the foreign gym.
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
(pg_temp.u(25),pg_temp.u(2),pg_temp.u(905),pg_temp.u(14),'gym_owner','Other',true);
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
(pg_temp.u(615),pg_temp.u(1),pg_temp.u(12),pg_temp.u(102),pg_temp.u(305),'2026-09-15T02:00:00Z','front_desk',pg_temp.u(23),'OCC fixture'),
(pg_temp.u(616),pg_temp.u(1),pg_temp.u(11),pg_temp.u(101),pg_temp.u(301),now(),'front_desk',pg_temp.u(23),'OCC fixture today');
select pg_temp.claim('gym_owner',25,null,905,2);
insert into public.attendance(id,tenant_id,branch_id,member_id,membership_id,checked_in_at,source,assisted_by_staff_id,assist_reason) values
(pg_temp.u(617),pg_temp.u(2),pg_temp.u(14),pg_temp.u(106),pg_temp.u(306),'2026-09-15T02:00:00Z','front_desk',pg_temp.u(25),'OCC fixture foreign');
set local role postgres;
select set_config('request.jwt.claims','',true);

-- Money: 701 new-member money on the first membership; 702 renewal money on
-- the successor; 703 add-on money through its linked order; 704 unallocated
-- manual money; 705 a non-arrived attempt (excluded); 706 an arrived payment
-- with no paid_at (all-date warning); 707 sits exactly on the Feb 2 IST
-- midnight — excluded from assertion 18's Jan-1..Feb-1 gym-local range by the
-- upper bound, but INSIDE assertion 20's Jan-1..Mar-31 range (Feb money);
-- 708 is one second before it (included in both); 760 is foreign money that
-- must never surface.
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,paid_at,created_at) values
(pg_temp.u(701),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),100000,'INR','paid','cash','2026-01-15T05:00:00Z','2026-01-15T05:00:00Z'),
(pg_temp.u(702),pg_temp.u(1),pg_temp.u(101),pg_temp.u(302),50000,'INR','paid','cash','2026-02-10T05:00:00Z','2026-02-10T05:00:00Z'),
(pg_temp.u(703),pg_temp.u(1),pg_temp.u(102),null,5000,'INR','paid','cash','2026-02-20T05:00:00Z','2026-02-20T05:00:00Z'),
(pg_temp.u(704),pg_temp.u(1),pg_temp.u(102),null,777,'INR','paid','cash','2026-02-21T05:00:00Z','2026-02-21T05:00:00Z'),
(pg_temp.u(705),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),25000,'INR','created','cash',null,'2026-01-20T05:00:00Z'),
(pg_temp.u(706),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),999,'INR','paid','cash',null,'2026-02-22T05:00:00Z'),
(pg_temp.u(707),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),12345,'INR','paid','cash','2026-02-01T18:30:00Z','2026-02-01T18:30:00Z'),
(pg_temp.u(708),pg_temp.u(1),pg_temp.u(101),pg_temp.u(301),30000,'INR','paid','cash','2026-02-01T18:29:59Z','2026-02-01T18:29:59Z'),
(pg_temp.u(760),pg_temp.u(2),pg_temp.u(106),pg_temp.u(306),4242,'INR','paid','cash','2026-02-10T05:00:00Z','2026-02-10T05:00:00Z');
insert into public.addon_products(id,tenant_id,kind,name,price_paise,stock_quantity) values(pg_temp.u(401),pg_temp.u(1),'product','OCC product',5000,5);
insert into public.addon_orders(id,tenant_id,member_id,addon_product_id,payment_id,status,quantity,unit_price_paise,total_paise,currency) values
(pg_temp.u(501),pg_temp.u(1),pg_temp.u(102),pg_temp.u(401),pg_temp.u(703),'paid',1,5000,5000,'INR');
-- Returns: 801 completes in a later month against a renewal payment (later-
-- month reduction, whole-receipt allocation); 802 requested (zero returned
-- cash); 803 completed with no processed_at (all-date warning); 804 returns
-- unallocated money (stays in the unknown-allocation disclosure).
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

set local role authenticated;

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
-- 5
select is((select pg_temp.probe('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: missing claims are refused before any read');
-- 6
select is((select pg_temp.probe('select pg_temp.claim(''member'',null,101,906,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: a member claim gains no occupancy read');
-- 7
select is((select pg_temp.probe('select pg_temp.claim(''front_desk'',23,null,903,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: the front desk gains no occupancy read');
-- 8
select is((select pg_temp.probe('select pg_temp.claim(''trainer'',24,null,904,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: a trainer gains no occupancy read');
-- 9
select is((select pg_temp.probe('select pg_temp.claim(''super_admin'',null,null,928,1); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: a platform super admin gains no occupancy read');
-- 10
select is((select pg_temp.probe('select pg_temp.claim(''gym_owner'',21,null,901,1,true); select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',null)')),'42501','OCC-001: an impersonating session gains no occupancy read');
select pg_temp.claim('gym_owner',21,null,901,1);

-- ============ C. range and branch validation ============
-- 11
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-27'',''2026-09-14'',null)')),'22023','OCC-003: a reversed range is a value refusal');
-- 12
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-02-30'',''2026-03-01'',null)')),'22008','OCC-003: a non-Gregorian date is refused at the typed-date call parse (22008), before the body — the route''s zod layer rejects it earlier still');
-- 13
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(13))')),'22023','OCC-003: an invalid configured branch zone is an explicit zone error, not a fabricated zero');
-- 14
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(899))')),'P0002','OCC-001: an unknown branch is an invisible target');
-- 15
select is((select pg_temp.state('select * from public.owner_occupancy_analytics(''2026-09-14'',''2026-09-27'',pg_temp.u(14))')),'P0002','OCC-001: a foreign branch shares the unknown-branch refusal');

-- ============ D. one snapshot: months, classification, warnings ============
-- Range M spans Jan 1..Feb 1 gym-local: 701 (Jan, new) and 708 (Feb 1
-- 23:59:59 IST, new) are inside; 707 sits exactly on the Feb 2 IST midnight
-- upper bound (excluded); 702/703/704 fall outside; 706 is undated (all-date
-- warning); 760 is foreign money (never surfaces).
-- 16
select ok((select pg_temp.snap('2026-01-01','2026-02-01',null))::text ~ '^\{' and (select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->>'asOf' is not null and length((select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->>'asOf')>0,'OCC-002: the snapshot discloses one server asOf');
-- 17
select is((select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->>'zone','Asia/Kolkata','OCC-003: money months use the valid gym zone and disclose it');
-- 18
select is((select jsonb_agg(m order by m->>'month') from jsonb_array_elements((select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->'months') m where m->>'month' in ('2026-01','2026-02')),$j$[{"month":"2026-01","currency":"INR","collectedPaise":"100000","returnedPaise":"0","netPaise":"100000","classification":{"newMemberPaise":"100000","renewalPaise":"0","addonPaise":"0","unallocatedPaise":"0","unknownReturnPaise":"0","label":"Membership linkage (derived classification)"}},{"month":"2026-02","currency":"INR","collectedPaise":"30000","returnedPaise":"0","netPaise":"30000","classification":{"newMemberPaise":"30000","renewalPaise":"0","addonPaise":"0","unallocatedPaise":"0","unknownReturnPaise":"0","label":"Membership linkage (derived classification)"}}]$j$::jsonb,'OCC-009/012: exact January/February months — 708 included one second before the bound, 707 excluded at the bound, first-membership money classified new');
-- 19
select ok(((select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->'months')::text not like '%4242%' and ((select pg_temp.snap('2026-01-01','2026-02-01',null))::jsonb->'months')::text not like '%12345%','OCC-001: foreign money and bound-excluded money contribute nothing');
-- 20
select is((select jsonb_agg(m order by m->>'month') from jsonb_array_elements((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'months') m where m->>'month'='2026-02'),$j$[{"month":"2026-02","currency":"INR","collectedPaise":"98122","returnedPaise":"0","netPaise":"98122","classification":{"newMemberPaise":"42345","renewalPaise":"50000","addonPaise":"5000","unallocatedPaise":"777","unknownReturnPaise":"0","label":"Membership linkage (derived classification)"}}]$j$::jsonb,'OCC-012: exact February classification — 707 (Feb 2 IST) inside the wide range joins 708 as first-membership money, successor renewal, add-on via order linkage, unallocated manual, no double counting');
-- 21
select is((select jsonb_agg(m order by m->>'month') from jsonb_array_elements((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'months') m where m->>'month'='2026-03'),$j$[{"month":"2026-03","currency":"INR","collectedPaise":"0","returnedPaise":"5100","netPaise":"-5100","classification":{"newMemberPaise":"0","renewalPaise":"-5000","addonPaise":"0","unallocatedPaise":"0","unknownReturnPaise":"-100","label":"Membership linkage (derived classification)"}}]$j$::jsonb,'OCC-010/012: a later-month completed return reduces that month (negative net visible), allocated whole to the original receipt''s category; an unallocated original stays unknown');
-- 22
select is((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'warnings'->'undatedPayments',jsonb_build_array(jsonb_build_object('paymentId',pg_temp.u(706),'amountPaise','999','currency','INR')),'OCC-009: an arrived payment without paid_at stays in a visible all-date warning');
-- 23
select is((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'warnings'->'undatedReturns',jsonb_build_array(jsonb_build_object('returnId',pg_temp.u(803),'amountPaise','1500','currency','INR')),'OCC-010: a completed undated return stays in a visible all-date warning');
-- 24
select ok(((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'warnings'->'undatedPayments')::text not like '%25000%' and ((select pg_temp.snap('2026-01-01','2026-03-31',null))::jsonb->'months')::text not like '%25000%','OCC-009: a non-arrived attempt contributes no collected cash and no payment warning');

-- ============ E. whole-gym heatmap (gym zone, holiday exclusion) ============
-- Whole-gym arrivals are bucketed in the disclosed gym zone (a local-time
-- comparison, OCC-008); branch-12 visits land on their gym-local dates; the
-- foreign visit 617 never appears.
-- 25
select is((select jsonb_build_object('zone',(select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'zone','zoneSource',(select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'zoneSource')),jsonb_build_object('zone','Asia/Kolkata','zoneSource','gym'),'OCC-003/004: an inherited gym zone is disclosed for the whole-gym heatmap');
-- 26
select is(((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'eligibleDateCount')::integer,13,'OCC-005/006: the holiday date is removed from the exposure denominator (14 candidate dates − 1 holiday)');
-- 27
select ok(((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'noEligibleDays')::boolean is false and (select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'message' is not null and (select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->>'message' like '%Limited%','OCC-007: 13 eligible dates sit below the 14-date threshold and carry the Limited history disclosure');
-- 28
select is((select jsonb_path_query_array((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->'cells','$[*] ? (@.arrivals > 0)'),$j$[{"weekday":1,"hour":7,"arrivals":1,"todayArrivals":0,"eligibleDates":13,"fraction":null,"limited":true,"message":"Limited history"},{"weekday":2,"hour":7,"arrivals":1,"todayArrivals":0,"eligibleDates":13,"fraction":null,"limited":true,"message":"Limited history"}]$j$::jsonb),'OCC-004/005: exclusion moves numerator and denominator together — only eligible-date visits are counted, holiday-date visits are not, and limited cells show no fraction');
-- 29
select is((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->'excludedDates',$j$[{"localDate":"2026-09-14","visits":3}]$j$::jsonb,'OCC-005: the excluded holiday date and its visit count are available from the same snapshot');
-- 30
select ok((select coalesce(sum((d->>'visits')::integer),0) from jsonb_array_elements((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'heatmap'->'arrivalDays') d)=5,'OCC-004/008: two accepted visits by the same member count twice, branch populations are both included, and the foreign row adds nothing');

-- ============ F. branch heatmap (zone override, branch-local range) ============
-- 31
select is((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'heatmap'->>'zone','America/New_York','OCC-004: the branch timezone override is the effective heatmap zone');
-- 32
select is((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'heatmap'->>'zoneSource','branch','OCC-003: the gym-zone inheritance is disclosed as a source');
-- 33
select is(((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'heatmap'->>'eligibleDateCount')::integer,13,'OCC-005: the tenant holiday excludes the branch-LOCAL date equal to holiday_on in the override zone too');
-- 34
select ok((select coalesce(sum((c->>'arrivals')::integer),0) from jsonb_array_elements((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'heatmap'->'cells') c)=0 and (select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'heatmap'->'excludedDates' = $j$[{"localDate":"2026-09-14","visits":1}]$j$::jsonb,'OCC-003/005: the Sep 13 New-York visit lies outside the branch-local range and the Sep 14 visit is holiday-excluded — no arrival survives');

-- ============ G. incomplete today (range derived from the run day) ============
-- 35
select ok((select pg_temp.snap(pg_temp.gym_today(),pg_temp.gym_today(),null))::jsonb->'heatmap'->>'noEligibleDays' = 'true','OCC-006: today alone is not a completed exposure — no eligible days, never a quiet-day zero');
-- 36
select is((select pg_temp.snap(pg_temp.gym_today(),pg_temp.gym_today(),null))::jsonb->'heatmap'->'cells',$j$[]$j$::jsonb,'OCC-006: an all-incomplete range presents no averaged cells');
-- 37
select is((select jsonb_path_query_array((select pg_temp.snap(pg_temp.gym_today(),pg_temp.gym_today(),null))::jsonb->'heatmap'->'arrivalDays','$[*] ? (@.visits > 0)'),jsonb_build_array(jsonb_build_object('localDate',pg_temp.gym_today()::text,'visits',1,'isHoliday',false,'incomplete',true))),'OCC-006: today''s arrivals are disclosed separately as incomplete, never mixed into an average');
-- 38
select is((select pg_temp.snap(pg_temp.gym_today(),pg_temp.gym_today(),null))::jsonb->'months',$j$[]$j$::jsonb,'OCC-009: a range with no arrived payments shows no fabricated month rows');

-- ============ H. class cohort and booked fill ============
-- 39
select is((select pg_temp.snap('2026-09-14','2026-09-27',null))::jsonb->'classes',$j${"cohortSessions":2,"totalCapacity":20,"holdingBookings":5,"bookedFillFraction":"0.2500…","cancelledSessionsExcluded":1,"attendedCount":2,"noShowCount":1,"unmarkedCount":2,"markingCoverage":"0.6000…","incompleteMarkingDisclosed":true,"limited":true,"message":"Limited history"}$j$::jsonb,'OCC-014/015/016: exact elapsed non-cancelled cohort — stored capacity, capacity-weighted booked fill, cancelled excluded, no-show holds a seat, unmarked disclosed, coverage separate, 2 sessions below the 10 threshold');
-- 40
select is(((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'classes'->>'cohortSessions')::integer,0,'OCC-014: a branch with no sessions has an empty cohort');
-- 41
select is((select pg_temp.snap('2026-09-14','2026-09-27',pg_temp.u(12)))::jsonb->'classes'->>'bookedFillFraction',null,'OCC-015: zero total capacity returns no fraction, not a zero');

-- ============ I. existing seams untouched ============
-- 42
select ok(to_regprocedure('public.owner_metrics(date,date)') is not null and (select provolatile from pg_proc where oid=to_regprocedure('public.owner_metrics(date,date)'))='s' and not (select prosecdef from pg_proc where oid=to_regprocedure('public.owner_metrics(date,date)')),'OCC: the existing owner_metrics seam is untouched (still stable, still invoker)');
-- 43
select ok(to_regprocedure('public.owner_metrics(date,date)') is distinct from to_regprocedure('public.owner_occupancy_analytics(date,date,uuid,boolean)'),'OCC: the analytics read is one versioned extension, not a changed owner_metrics');
-- 44
select ok((select pg_temp.snapx('2026-09-14','2026-09-27',null,false))::jsonb->'heatmap'->>'eligibleDateCount' = '14' and (select pg_temp.snapx('2026-09-14','2026-09-27',null,false))::jsonb->'heatmap'->'excludedDates' = '[]'::jsonb and exists(select 1 from jsonb_array_elements((select pg_temp.snapx('2026-09-14','2026-09-27',null,false))::jsonb->'heatmap'->'cells') c where (c->>'weekday')='1' and (c->>'hour')='7' and (c->>'arrivals')='3'),'OCC-005: with the exclusion toggle off the holiday date returns to the exposure (14 eligible dates, no exclusions, the Monday 07:00 cell counts all three same-hour arrivals incl. the two holiday-date visits)');

select * from finish();
rollback;
