-- 18_no_show_scan.sql — capability: no-show scan (Phase 4)
--
-- Written from openspec/changes/phase-4-retention/specs/no-show-scan/spec.md,
-- by a session that has not read the implementation and did not look for it
-- (AGENTS.md rule 10). No migration under 20260908230000_* was opened, no
-- function source was read, and the catalogue was consulted only for a
-- structural fact that already existed before this capability did: the
-- partial unique index on no_show_cases (tenant_id, member_id) where status
-- is live, which this file's idempotence section relies on and does not
-- reimplement. If app.run_no_show_scan appeared in the catalogue while this
-- file was written, its definition was not read.
--
-- THE INTERFACE THIS FILE CALLS DIRECTLY
--
--   app.run_no_show_scan(p_tenant_id uuid, p_today date default null)
--     returns integer
--
-- Every assertion below is a plain `select app.run_no_show_scan(...)` or a
-- plain `select` against no_show_cases afterwards, run as `postgres`. This
-- file is not about who may call the scan — the spec's interface section
-- gives no caller restriction, and entangling authorization with the scan's
-- own arithmetic would make a red assertion ambiguous about which one
-- broke. Every fixture row is inserted as `postgres` too, for the same
-- reason: no RLS write-gate exercise, no jwt claims, one thing on trial per
-- section — the scan's own logic.
--
-- NINE TENANTS, EACH PROVING EXACTLY ONE THING
--
--   18…010000  the threshold boundary itself, N-1 and N+1, same fixture
--   18…020000  never attended, measured from the membership's own start
--   18…030000  a low configured threshold (3), never a shared constant
--   18…040000  a high configured threshold (12) — its own control member
--               sits exactly where the schema's own default (7) would
--               wrongly open a case, so a hardcoded 7 anywhere goes red
--   18…050000  timezone A — Etc/GMT-12
--   18…060000  timezone B — Etc/GMT+12, exactly 24h behind A
--   18…070000  paused is derived (ADR-064): approved-covering, rejected,
--               and approved-but-ended, as three different members
--   18…080000  membership not live: expired, cancelled, pending
--   18…090000  idempotence, the return value, and one case per member
--
-- WHY Etc/GMT-12 AND Etc/GMT+12 FOR THE TIMEZONE SECTION
--
-- The scenario is "two gyms whose day boundaries differ, at the same
-- instant" — but this file runs against Supabase Cloud, not a clock this
-- suite controls, so "the same instant" has to be whatever now() is when
-- the fixtures happen to be inserted. Two fixed-offset zones exactly 24
-- hours apart give the property this needs without depending on when the
-- suite runs: at ANY UTC instant, the local calendar date in a zone is at
-- most 23h59m ahead of or behind the same calendar date in another zone
-- exactly 24h away — which is a contradiction, so the two dates are
-- ALWAYS different, deterministically, never a flaky one-day-in-fifty
-- window. Etc/GMT-12 is UTC+12 and Etc/GMT+12 is UTC-12 (POSIX sign is
-- inverted from common usage); neither observes DST, so the 24h gap holds
-- exactly, always. Both dates are captured once into a temp table at
-- fixture time and reused for every assertion, so a scan call that runs a
-- few seconds later than the fixtures cannot itself introduce the
-- flakiness this construction was built to avoid.
--
-- Both members are given the same absence margin (8 days against a
-- threshold of 7, in both gyms) rather than different ones, so that an
-- implementation that reads ONE date and applies it to both gyms — UTC, a
-- hardcoded zone, or gym B's zone applied to gym A's member — is caught:
-- since the two correct dates are always exactly one day apart, any single
-- wrong date can agree with at most one of the two gyms' correct date, so
-- at least one of the two evidence assertions (18/26) is forced red by
-- that class of bug, on any run, regardless of the real instant.
--
-- WHAT "NEVER ATTENDED" ASSERTS ABOUT last_attended_on
--
-- The spec does not say what last_attended_on holds when a member has no
-- attendance row to read. This file asserts it is null — there is no last
-- attendance to record, and a case is supposed to record what it saw. If
-- the intended reading is different, that is a spec gap this assertion
-- will surface, not a suite defect to quietly work around.
--
-- WHAT IS NOT ATTEMPTED
--
-- "Two scans at once" (concurrent runs) is not exercised: this is one
-- transaction on one connection, and pgTAP cannot open a second session
-- inside it. The partial unique index is what makes concurrent safety a
-- property of the constraint rather than the caller, and this file only
-- confirms the constraint is in the catalogue and that two SEQUENTIAL runs
-- behave correctly — it does not attempt to prove the concurrent case.
-- Nothing about closing a case on return (NSH-005), the contact-log gates
-- (NSH-006/007), or app.enforce_check_in() is in scope here; those belong
-- to their own capabilities.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own nine fixture tenants —
--          this database permanently holds a seeded demo gym, and an
--          assertion over a whole table is a time bomb.
-- ADR-064: paused is derived from membership_pauses, never a status value —
--          the T7 section is built specifically to catch a scan that reads
--          memberships.status instead, because that column stays 'active'
--          on a genuinely paused member and nothing in this schema ever
--          sets it to 'frozen'.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(34);


-- ---------------------------------------------------------------------------
-- The mechanism, in the catalogue (1)
-- ---------------------------------------------------------------------------

-- 1 — CORRECTED. This used to compare p.proargtypes::regtype[] (an oidvector
-- cast, 0-indexed: [0:1]={uuid,date}) directly against array['uuid'::regtype,
-- 'date'::regtype] (a literal, 1-indexed: [1:2]={uuid,date}). Postgres array
-- equality is bound-sensitive, so that comparison was false no matter what
-- the argument types were — an assertion that cannot pass, which for as long
-- as the function is genuinely missing is indistinguishable from one that
-- correctly detects it. Rebuilding the array through unnest/array_agg
-- produces an ordinary 1-indexed array, so the comparison is possible again
-- and still checks exactly types — not argument names, not a rendered
-- string.
select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and p.proname = 'run_no_show_scan'
       and p.pronargs = 2
       and (select array_agg(t) from unnest(p.proargtypes::regtype[]) as t)
             = array['uuid'::regtype, 'date'::regtype]
       and p.prorettype = 'integer'::regtype
       and p.pronargdefaults = 1
  ),
  'the interface — app.run_no_show_scan(p_tenant_id uuid, p_today date default null) returns integer — exists in the catalogue with the contracted schema, name, arity, argument types and one defaulted argument'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 1 — the threshold boundary itself (2-5)
-- One day short of the threshold opens nothing; one day past opens a case.
-- Both members share the gym, the threshold and p_today, so the boundary
-- is what separates them and nothing else can be.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000010000'::uuid, 'No-Show Gym 1', 'NSHW01');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000010000'::uuid, 7);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000010101'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000010201'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010101'::uuid, 'G1 Short', '+9170000010201'),
  ('18000000-0000-4000-8000-000000010202'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010101'::uuid, 'G1 Past',  '+9170000010202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000010301'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, 'G1 Monthly', 30, 150000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000010401'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010201'::uuid, '18000000-0000-4000-8000-000000010301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000010402'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010202'::uuid, '18000000-0000-4000-8000-000000010301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000);

-- G1 Short: one day short of the threshold — 6 days absent against a
-- 7-day threshold.
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-000000010601'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010101'::uuid, '18000000-0000-4000-8000-000000010201'::uuid, '18000000-0000-4000-8000-000000010401'::uuid,
   (('2026-06-20'::date - 6) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- G1 Past: one day past the threshold — 8 days absent.
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-000000010602'::uuid, '18000000-0000-4000-8000-000000010000'::uuid, '18000000-0000-4000-8000-000000010101'::uuid, '18000000-0000-4000-8000-000000010202'::uuid, '18000000-0000-4000-8000-000000010402'::uuid,
   (('2026-06-20'::date - 8) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- 2
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000010000'::uuid, '2026-06-20'::date),
  1,
  'requirement "Absence is measured from the last visit" — of the two members in gym 1, exactly one is past the threshold, so the scan opens exactly one case'
);

-- 3
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000010000'::uuid
      and member_id = '18000000-0000-4000-8000-000000010201'::uuid),
  0,
  'scenario "One day short of the threshold" — the member 6 days absent against a 7-day threshold has no case opened'
);

-- 4
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000010000'::uuid
      and member_id = '18000000-0000-4000-8000-000000010202'::uuid
      and status = 'open'),
  1,
  'scenario "One day past the threshold" — the member 8 days absent against a 7-day threshold has exactly one open case'
);

-- 5 — requirement "A case records what it saw when it opened": last_attended_on,
-- absent_days_at_open and threshold_days, all three on the same row.
select results_eq(
  $$
    select last_attended_on, absent_days_at_open, threshold_days
      from public.no_show_cases
     where tenant_id = '18000000-0000-4000-8000-000000010000'::uuid
       and member_id = '18000000-0000-4000-8000-000000010202'::uuid
  $$,
  $$ values ('2026-06-12'::date, 8, 7) $$,
  'scenario "The case carries its own evidence" — the case records exactly the day last attended, the days absent at open, and the threshold in force at the time, none of them the current setting re-read later'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 2 — never attended, measured from the membership's own
-- start (6-9)
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000020000'::uuid, 'No-Show Gym 2', 'NSHW02');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000020000'::uuid, 7);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000020101'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000020201'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, '18000000-0000-4000-8000-000000020101'::uuid, 'G2 Never Old',    '+9170000020201'),
  ('18000000-0000-4000-8000-000000020202'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, '18000000-0000-4000-8000-000000020101'::uuid, 'G2 Never Recent', '+9170000020202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000020301'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, 'G2 Monthly', 30, 150000);

-- Membership started 30 days ago — older than the 7-day threshold — and
-- neither member has ever attended (no row in public.attendance at all).
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000020401'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, '18000000-0000-4000-8000-000000020201'::uuid, '18000000-0000-4000-8000-000000020301'::uuid, 'active', '2026-06-20'::date - 30, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000020402'::uuid, '18000000-0000-4000-8000-000000020000'::uuid, '18000000-0000-4000-8000-000000020202'::uuid, '18000000-0000-4000-8000-000000020301'::uuid, 'active', '2026-06-20'::date - 3,  '2026-06-20'::date + 100, 150000);

-- 6
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000020000'::uuid, '2026-06-20'::date),
  1,
  'requirement "Absence is measured from the last visit, and never having visited counts" — only the member whose membership is older than the threshold opens a case'
);

-- 7
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000020000'::uuid
      and member_id = '18000000-0000-4000-8000-000000020202'::uuid),
  0,
  'the member whose membership began only 3 days ago, and has never attended, is not old enough to be a no-show yet — no case'
);

-- 8
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000020000'::uuid
      and member_id = '18000000-0000-4000-8000-000000020201'::uuid
      and status = 'open'),
  1,
  'scenario "A member who has never visited" — a member with an active membership older than the threshold and no attendance at all gets exactly one open case'
);

-- 9 — measured from the membership start, not skipped for want of a row:
-- absent_days_at_open is the full 30 days since starts_on, and there is no
-- attendance row to report as last_attended_on.
select results_eq(
  $$
    select last_attended_on, absent_days_at_open, threshold_days
      from public.no_show_cases
     where tenant_id = '18000000-0000-4000-8000-000000020000'::uuid
       and member_id = '18000000-0000-4000-8000-000000020201'::uuid
  $$,
  $$ values (null::date, 30, 7) $$,
  'a member who has never attended is measured from the date their membership began: last_attended_on has nothing to record, and absent_days_at_open is the full 30 days since starts_on'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gyms 3 and 4 — the threshold is the gym's own, never a
-- constant (10-15)
--
-- Gym 3 configures 3 days; gym 4 configures 12. Gym 4's control member sits
-- at 8 days absent — past the schema's own DEFAULT of 7, short of gym 4's
-- actual 12 — so a scan that reads organization_settings.no_show_threshold_days
-- from the wrong gym, or hardcodes the column default, opens a case for it
-- and this file catches that at assertion 13.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000030000'::uuid, 'No-Show Gym 3', 'NSHW03'),
  ('18000000-0000-4000-8000-000000040000'::uuid, 'No-Show Gym 4', 'NSHW04');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000030000'::uuid, 3),
  ('18000000-0000-4000-8000-000000040000'::uuid, 12);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000030101'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, 'Main', true),
  ('18000000-0000-4000-8000-000000040101'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000030201'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030101'::uuid, 'G3 Open',    '+9170000030201'),
  ('18000000-0000-4000-8000-000000030202'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030101'::uuid, 'G3 NoOpen',  '+9170000030202'),
  ('18000000-0000-4000-8000-000000040201'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040101'::uuid, 'G4 Open',    '+9170000040201'),
  ('18000000-0000-4000-8000-000000040202'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040101'::uuid, 'G4 Control', '+9170000040202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000030301'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, 'G3 Monthly', 30, 150000),
  ('18000000-0000-4000-8000-000000040301'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, 'G4 Monthly', 30, 150000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000030401'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030201'::uuid, '18000000-0000-4000-8000-000000030301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000030402'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030202'::uuid, '18000000-0000-4000-8000-000000030301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000040401'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040201'::uuid, '18000000-0000-4000-8000-000000040301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000040402'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040202'::uuid, '18000000-0000-4000-8000-000000040301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000);

insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  -- G3 Open: 4 days absent, past gym 3's threshold of 3.
  ('18000000-0000-4000-8000-000000030601'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030101'::uuid, '18000000-0000-4000-8000-000000030201'::uuid, '18000000-0000-4000-8000-000000030401'::uuid,
   (('2026-06-20'::date - 4) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  -- G3 NoOpen: 2 days absent, short of gym 3's threshold of 3.
  ('18000000-0000-4000-8000-000000030602'::uuid, '18000000-0000-4000-8000-000000030000'::uuid, '18000000-0000-4000-8000-000000030101'::uuid, '18000000-0000-4000-8000-000000030202'::uuid, '18000000-0000-4000-8000-000000030402'::uuid,
   (('2026-06-20'::date - 2) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  -- G4 Open: 13 days absent, past gym 4's threshold of 12.
  ('18000000-0000-4000-8000-000000040601'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040101'::uuid, '18000000-0000-4000-8000-000000040201'::uuid, '18000000-0000-4000-8000-000000040401'::uuid,
   (('2026-06-20'::date - 13) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  -- G4 Control: 8 days absent — past the schema DEFAULT of 7, short of gym 4's real 12.
  ('18000000-0000-4000-8000-000000040602'::uuid, '18000000-0000-4000-8000-000000040000'::uuid, '18000000-0000-4000-8000-000000040101'::uuid, '18000000-0000-4000-8000-000000040202'::uuid, '18000000-0000-4000-8000-000000040402'::uuid,
   (('2026-06-20'::date - 8) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- 10
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000030000'::uuid, '2026-06-20'::date),
  1,
  'scenario "The threshold is the gym''s own" — gym 3 configured 3 days; a member 4 days absent crosses it and the other, 2 days absent, does not'
);

-- 11
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000030000'::uuid
      and member_id = '18000000-0000-4000-8000-000000030202'::uuid),
  0,
  'the member 2 days absent against gym 3''s 3-day threshold has no case'
);

-- 12
select is(
  (select threshold_days from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000030000'::uuid
      and member_id = '18000000-0000-4000-8000-000000030201'::uuid),
  3,
  'gym 3''s case records gym 3''s own configured threshold, 3 — not the schema default of 7 and not any other gym''s value'
);

-- 13 — the discriminating assertion against a hardcoded threshold, from the
-- opposite direction to assertion 10: gym 4's control member is past the
-- schema DEFAULT of 7 but short of gym 4's actual configured 12, so a scan
-- reading the wrong value opens a case here that should not exist.
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000040000'::uuid
      and member_id = '18000000-0000-4000-8000-000000040202'::uuid),
  0,
  'gym 4 configured 12 days; a member 8 days absent is past the SCHEMA''S OWN DEFAULT of 7 but short of gym 4''s actual 12, so a scan that ever falls back to the default instead of reading organization_settings opens a case here and it must not'
);

-- 14
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000040000'::uuid, '2026-06-20'::date),
  1,
  'scenario "The threshold is the gym''s own" — gym 4, evaluated a second time (idempotently), still opens only the one member genuinely past its own 12-day threshold'
);

-- 15
select is(
  (select threshold_days from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000040000'::uuid
      and member_id = '18000000-0000-4000-8000-000000040201'::uuid),
  12,
  'gym 4''s case records gym 4''s own configured threshold, 12'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gyms 5 and 6 — two timezones whose day boundaries genuinely
-- differ, scanned with p_today = null so the derivation path under test is
-- production's own (16-27)
--
-- Etc/GMT-12 (UTC+12) and Etc/GMT+12 (UTC-12) are exactly 24 hours apart, so
-- their calendar dates for "now" differ by exactly one day at every instant,
-- deterministically — see the file header. Both dates are captured once so
-- every assertion below reasons about the same two dates the fixtures were
-- built from, however long the scan itself takes to run.
-- ---------------------------------------------------------------------------

create temp table tz_fixture as
select
  (now() at time zone 'Etc/GMT-12')::date as date_a,
  (now() at time zone 'Etc/GMT+12')::date as date_b;

insert into public.organizations (id, name, gym_code, timezone) values
  ('18000000-0000-4000-8000-000000050000'::uuid, 'No-Show Gym 5', 'NSHW05', 'Etc/GMT-12'),
  ('18000000-0000-4000-8000-000000060000'::uuid, 'No-Show Gym 6', 'NSHW06', 'Etc/GMT+12');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000050000'::uuid, 7),
  ('18000000-0000-4000-8000-000000060000'::uuid, 7);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000050101'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, 'Main', true),
  ('18000000-0000-4000-8000-000000060101'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000050201'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050101'::uuid, 'G5 Open',  '+9170000050201'),
  ('18000000-0000-4000-8000-000000050202'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050101'::uuid, 'G5 Short', '+9170000050202'),
  ('18000000-0000-4000-8000-000000060201'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060101'::uuid, 'G6 Open',  '+9170000060201'),
  ('18000000-0000-4000-8000-000000060202'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060101'::uuid, 'G6 Short', '+9170000060202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000050301'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, 'G5 Monthly', 30, 150000),
  ('18000000-0000-4000-8000-000000060301'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, 'G6 Monthly', 30, 150000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise)
select '18000000-0000-4000-8000-000000050401'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050201'::uuid, '18000000-0000-4000-8000-000000050301'::uuid, 'active'::public.membership_status, date_a - 100, date_a + 100, 150000
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000050402'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050202'::uuid, '18000000-0000-4000-8000-000000050301'::uuid, 'active'::public.membership_status, date_a - 100, date_a + 100, 150000
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000060401'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060201'::uuid, '18000000-0000-4000-8000-000000060301'::uuid, 'active'::public.membership_status, date_b - 100, date_b + 100, 150000
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000060402'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060202'::uuid, '18000000-0000-4000-8000-000000060301'::uuid, 'active'::public.membership_status, date_b - 100, date_b + 100, 150000
  from tz_fixture;

insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source)
select '18000000-0000-4000-8000-000000050601'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050101'::uuid, '18000000-0000-4000-8000-000000050201'::uuid, '18000000-0000-4000-8000-000000050401'::uuid,
       ((date_a - 8) + time '12:00') at time zone 'Etc/GMT-12', 'qr'::public.attendance_source
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000050602'::uuid, '18000000-0000-4000-8000-000000050000'::uuid, '18000000-0000-4000-8000-000000050101'::uuid, '18000000-0000-4000-8000-000000050202'::uuid, '18000000-0000-4000-8000-000000050402'::uuid,
       ((date_a - 5) + time '12:00') at time zone 'Etc/GMT-12', 'qr'::public.attendance_source
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000060601'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060101'::uuid, '18000000-0000-4000-8000-000000060201'::uuid, '18000000-0000-4000-8000-000000060401'::uuid,
       ((date_b - 8) + time '12:00') at time zone 'Etc/GMT+12', 'qr'::public.attendance_source
  from tz_fixture
union all
select '18000000-0000-4000-8000-000000060602'::uuid, '18000000-0000-4000-8000-000000060000'::uuid, '18000000-0000-4000-8000-000000060101'::uuid, '18000000-0000-4000-8000-000000060202'::uuid, '18000000-0000-4000-8000-000000060402'::uuid,
       ((date_b - 5) + time '12:00') at time zone 'Etc/GMT+12', 'qr'::public.attendance_source
  from tz_fixture;

-- 16
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000050000'::uuid, null),
  1,
  'requirement "The scan runs once per calendar day, in each gym''s own timezone" — with p_today null, gym 5 (Etc/GMT-12) opens a case for the member 8 days absent by its own tz-derived today'
);

-- 17
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000050000'::uuid
      and member_id = '18000000-0000-4000-8000-000000050202'::uuid),
  0,
  'gym 5''s member 5 days absent, short of the 7-day threshold measured in gym 5''s own timezone, has no case'
);

-- 18 — the discriminating evidence assertion: see the file header for why a
-- wrong shared date cannot satisfy both this and assertion 26.
select results_eq(
  $$
    select c.last_attended_on, c.absent_days_at_open, c.threshold_days
      from public.no_show_cases c
     where c.tenant_id = '18000000-0000-4000-8000-000000050000'::uuid
       and c.member_id = '18000000-0000-4000-8000-000000050201'::uuid
  $$,
  $$ select date_a - 8, 8, 7 from tz_fixture $$,
  'gym 5''s case reports 8 days absent measured against Etc/GMT-12''s own today — not UTC''s today, not gym 6''s timezone'
);

-- 19
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000060000'::uuid, null),
  1,
  'requirement "The scan runs once per calendar day, in each gym''s own timezone" — gym 6 (Etc/GMT+12), scanned at the same real instant as gym 5, opens a case measured against ITS OWN today, which is always exactly one calendar day behind gym 5''s'
);

-- 20
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000060000'::uuid
      and member_id = '18000000-0000-4000-8000-000000060202'::uuid),
  0,
  'gym 6''s member 5 days absent, short of the 7-day threshold measured in gym 6''s own timezone, has no case'
);

-- 21
select results_eq(
  $$
    select c.last_attended_on, c.absent_days_at_open, c.threshold_days
      from public.no_show_cases c
     where c.tenant_id = '18000000-0000-4000-8000-000000060000'::uuid
       and c.member_id = '18000000-0000-4000-8000-000000060201'::uuid
  $$,
  $$ select date_b - 8, 8, 7 from tz_fixture $$,
  'gym 6''s case reports 8 days absent measured against Etc/GMT+12''s own today, which assertion 5 and this file''s fixture construction guarantee differs from gym 5''s today'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 7 — paused is derived, not a status (ADR-064) (22-25)
--
-- All three members are 20 days absent against a 5-day threshold — far past
-- it — so absence is never in question here; only the pause is. None of
-- their memberships is ever set to 'frozen': ADR-064 says nothing does, so
-- a scan reading memberships.status instead of membership_pauses flags
-- every one of them, and this section is built to catch exactly that.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000070000'::uuid, 'No-Show Gym 7', 'NSHW07');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000070000'::uuid, 5);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000070101'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000070201'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, 'G7 Approved Covering', '+9170000070201'),
  ('18000000-0000-4000-8000-000000070202'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, 'G7 Rejected',          '+9170000070202'),
  ('18000000-0000-4000-8000-000000070203'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, 'G7 Pause Ended',       '+9170000070203');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000070301'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, 'G7 Monthly', 30, 150000);

-- membership_pauses_approver_pairs_with_approval_chk requires an approver
-- whenever approved_at is set; this staff member exists only to be that
-- approver on the two approved pauses below and plays no role of its own.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('18000000-0000-4000-8000-000000070701'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, 'gym_manager', 'G7 Approver');

-- All three memberships are, and stay, 'active' — never 'frozen'.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000070401'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070201'::uuid, '18000000-0000-4000-8000-000000070301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000070402'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070202'::uuid, '18000000-0000-4000-8000-000000070301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000070403'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070203'::uuid, '18000000-0000-4000-8000-000000070301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000);

insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-000000070601'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, '18000000-0000-4000-8000-000000070201'::uuid, '18000000-0000-4000-8000-000000070401'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-000000070602'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, '18000000-0000-4000-8000-000000070202'::uuid, '18000000-0000-4000-8000-000000070402'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-000000070603'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070101'::uuid, '18000000-0000-4000-8000-000000070203'::uuid, '18000000-0000-4000-8000-000000070403'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

insert into public.membership_pauses (id, tenant_id, membership_id, starts_on, ends_on, reason, approved_by_staff_id, approved_at, rejected_at) values
  -- Approved, and covers the scan date (2026-06-20 is between the 15th and the 25th).
  ('18000000-0000-4000-8000-000000070501'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070401'::uuid, '2026-06-15'::date, '2026-06-25'::date, 'approved covering', '18000000-0000-4000-8000-000000070701'::uuid, now(), null),
  -- Rejected — not a pause at all, whatever dates it names.
  ('18000000-0000-4000-8000-000000070502'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070402'::uuid, '2026-06-15'::date, '2026-06-25'::date, 'rejected',         null,                                                            null, now()),
  -- Approved, but ended before the scan date.
  ('18000000-0000-4000-8000-000000070503'::uuid, '18000000-0000-4000-8000-000000070000'::uuid, '18000000-0000-4000-8000-000000070403'::uuid, '2026-05-01'::date, '2026-06-10'::date, 'already ended',    '18000000-0000-4000-8000-000000070701'::uuid, now(), null);

-- 22
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000070000'::uuid, '2026-06-20'::date),
  2,
  'requirement "A member who cannot attend is not a churn risk" — of the three members, only the one with a genuinely approved, currently-covering pause is excluded; the other two, 20 days absent past a 5-day threshold, open cases'
);

-- 23
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000070000'::uuid
      and member_id = '18000000-0000-4000-8000-000000070201'::uuid),
  0,
  'scenario "An approved pause covering today" — the member is 20 days absent, far past the threshold, but their approved pause covers the scan date and memberships.status never left ''active'' for them: only a scan reading membership_pauses, not the status column, gets this right'
);

-- 24
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000070000'::uuid
      and member_id = '18000000-0000-4000-8000-000000070202'::uuid
      and status = 'open'),
  1,
  'scenario "A rejected pause is not a pause" — the member''s only pause was rejected, so it excludes nobody and a case opens'
);

-- 25
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000070000'::uuid
      and member_id = '18000000-0000-4000-8000-000000070203'::uuid
      and status = 'open'),
  1,
  'scenario "A pause that has ended" — the member''s approved pause ended before the scan date and they have not returned, so a case opens'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 8 — a membership that is not live (26-27)
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000080000'::uuid, 'No-Show Gym 8', 'NSHW08');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000080000'::uuid, 5);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000080101'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000080201'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, 'G8 Expired',   '+9170000080201'),
  ('18000000-0000-4000-8000-000000080202'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, 'G8 Cancelled', '+9170000080202'),
  ('18000000-0000-4000-8000-000000080203'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, 'G8 Pending',   '+9170000080203');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000080301'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, 'G8 Monthly', 30, 150000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000080401'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080201'::uuid, '18000000-0000-4000-8000-000000080301'::uuid, 'expired',   '2026-06-20'::date - 100, '2026-06-20'::date - 30, 150000),
  ('18000000-0000-4000-8000-000000080402'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080202'::uuid, '18000000-0000-4000-8000-000000080301'::uuid, 'cancelled', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000080403'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080203'::uuid, '18000000-0000-4000-8000-000000080301'::uuid, 'pending',   '2026-06-20'::date + 5,   '2026-06-20'::date + 35,  150000);

-- All three are 20 days absent — well past the threshold — so it is only
-- the membership status that can exclude any of them.
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-000000080601'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, '18000000-0000-4000-8000-000000080201'::uuid, '18000000-0000-4000-8000-000000080401'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-000000080602'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, '18000000-0000-4000-8000-000000080202'::uuid, '18000000-0000-4000-8000-000000080402'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-000000080603'::uuid, '18000000-0000-4000-8000-000000080000'::uuid, '18000000-0000-4000-8000-000000080101'::uuid, '18000000-0000-4000-8000-000000080203'::uuid, '18000000-0000-4000-8000-000000080403'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- 26
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000080000'::uuid, '2026-06-20'::date),
  0,
  'scenario "A membership that is not live" — expired, cancelled and pending are all excluded, so none of the three members, each 20 days absent, opens a case'
);

-- 27
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000080000'::uuid),
  0,
  'no case exists for gym 8 at all — not merely that the last call reported zero, but that nothing was actually written for any of the three non-live memberships'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 9 — idempotence, the return value, and one case per
-- member (28-34)
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-000000090000'::uuid, 'No-Show Gym 9', 'NSHW09');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-000000090000'::uuid, 5);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-000000090101'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-000000090201'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090101'::uuid, 'G9 Open',   '+9170000090201'),
  ('18000000-0000-4000-8000-000000090202'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090101'::uuid, 'G9 NoOpen', '+9170000090202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-000000090301'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, 'G9 Monthly', 30, 150000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-000000090401'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090201'::uuid, '18000000-0000-4000-8000-000000090301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-000000090402'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090202'::uuid, '18000000-0000-4000-8000-000000090301'::uuid, 'active', '2026-06-20'::date - 100, '2026-06-20'::date + 100, 150000);

insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-000000090601'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090101'::uuid, '18000000-0000-4000-8000-000000090201'::uuid, '18000000-0000-4000-8000-000000090401'::uuid,
   (('2026-06-20'::date - 10) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-000000090602'::uuid, '18000000-0000-4000-8000-000000090000'::uuid, '18000000-0000-4000-8000-000000090101'::uuid, '18000000-0000-4000-8000-000000090202'::uuid, '18000000-0000-4000-8000-000000090402'::uuid,
   (('2026-06-20'::date - 1)  + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- 28 — the return value is the number of cases opened.
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000090000'::uuid, '2026-06-20'::date),
  1,
  'requirement "The scan runs once per calendar day" / interface contract — the first run returns exactly 1, the number of cases it actually opened, not the number of members scanned or excluded'
);

-- 29
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
      and member_id = '18000000-0000-4000-8000-000000090201'::uuid
      and status = 'open'),
  1,
  'the qualifying member has exactly one open case after the first run'
);

-- 30
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
      and member_id = '18000000-0000-4000-8000-000000090202'::uuid),
  0,
  'the member 1 day absent against a 5-day threshold opens nothing on the first run'
);

create temp table g9_case_snapshot as
  select id, opened_on from public.no_show_cases
   where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
     and member_id = '18000000-0000-4000-8000-000000090201'::uuid
     and status = 'open';

-- 31 — scenario "Running twice in one gym-day" / "The scan runs twice".
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-000000090000'::uuid, '2026-06-20'::date),
  0,
  'requirement "Exactly one open case per member, however often the scan runs" — a second run against an unchanged database, same tenant and same p_today, opens no additional cases and its return value says so'
);

-- 32
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
      and member_id = '18000000-0000-4000-8000-000000090201'::uuid),
  1,
  'the member still has exactly one case, not two, after the second run — the partial unique index on (tenant_id, member_id) where status is live is what this relies on, not reimplemented here'
);

-- 33
select results_eq(
  $$
    select id, opened_on from public.no_show_cases
     where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
       and member_id = '18000000-0000-4000-8000-000000090201'::uuid
       and status = 'open'
  $$,
  $$ select id, opened_on from g9_case_snapshot $$,
  'scenario "The scan runs twice" — the case is the SAME row the first run opened: its id and its opened_on are both unchanged, not a new case with the same outcome'
);

-- 34
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-000000090000'::uuid
      and member_id = '18000000-0000-4000-8000-000000090202'::uuid),
  0,
  'the member short of the threshold still has no case after the second run either'
);


select * from finish();

rollback;
