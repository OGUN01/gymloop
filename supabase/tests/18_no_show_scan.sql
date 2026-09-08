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
-- section — the scan's own logic. The one exception is five follow-up rows
-- in gym 11's fixture, which must be inserted as `authenticated` with this
-- gym's own claims because that is what the contacted/follow_up_due
-- transition requires to fire at all — confirmed empirically against a
-- throwaway fixture, not by reading the trigger. The role is restored to
-- `postgres` before the scan itself runs.
--
-- ELEVEN TENANTS, EACH PROVING EXACTLY ONE THING
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
--   18…0a0000  a membership whose end date has passed: still 'active', but
--               ends_on before the scan date — a control member, identical
--               but for ends_on, proves the scan does not simply stop
--               flagging everybody
--   18…0b0000  a case outlives its usefulness when the membership ends: six
--               members in three pairs (open/open, contacted/contacted,
--               follow_up_due/follow_up_due), each pair differing only in
--               ends_on — every lapsed member's live-status case must be
--               closed (with the open one's follow-up surviving) and every
--               live member's case, whatever its status, must be left
--               exactly alone
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
-- An active membership with a null ends_on is not attempted either, for a
-- different reason: it cannot exist. See gym 10's fixture comment — the
-- structural constraint that forbids it was confirmed unchanged by the fix,
-- empirically, without reading the fix's text.
--
-- Gym 11 originally asserted only the literal word "open" — the
-- requirement's first draft said "an open case" — and flagged, rather than
-- guessed, that no_show_cases_tenant_id_member_id_open_key treats three
-- statuses (open, contacted, follow_up_due) as one live case. The
-- requirement was then revised to say explicitly that "live" is all three,
-- on the harm rather than the wording: the red list renders every state
-- that is not returned or closed, so a contacted case sits at the top of it
-- exactly as an open one does. This file now asserts the resolved reading:
-- gym 11 builds one lapsed and one live member in EACH of the three live
-- states, three controls rather than one, because a per-status
-- implementation (three separate closing rules instead of one membership
-- check) could pass a single open-status control while still destroying a
-- live member's in-progress contacted or follow_up_due case.
--
-- 45 assertions, plan(45), 45 TAP lines. Verified with scratchpad/tapcount.py
-- (ADR-069: `select num_failed()` placed before `finish()` is shadowed by
-- finish()'s own diagnostic row on a failing run and can only ever observe
-- passes, which is why tapcount.py rewrites every top-level plan/ok/is/
-- results_eq/finish call to capture its emitted line into a temp table
-- instead). Run against Cloud via `supabase db query --linked -f`,
-- begin…rollback, nothing committed, no migration spliced — this project's
-- Cloud schema already has every migration through 20260909170000 applied,
-- which is why gyms 1-10 (assertions 1-37) are all green. 42 of 45 green, 3
-- red: assertions 39, 42 and 43 — closing a lapsed member's open, contacted
-- and follow_up_due case respectively, none of it implemented yet.
-- Assertions 38, 40, 41, 44 and 45 are already green without the new
-- capability and are the controls this section relies on, not evidence the
-- new rule already holds: 38 because the partial unique index already
-- blocks a second case for any of the six members regardless of closing, 40
-- because nothing currently deletes a follow-up, and 41/44/45 because
-- nothing currently touches a live member's case, in any of the three
-- states, at all.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own eleven fixture tenants —
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

select plan(45);


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


-- ---------------------------------------------------------------------------
-- Fixtures: gym 10 — a membership whose end date has passed (35-37)
--
-- Two members, identical in every respect that could open or refuse a case
-- — same starts_on, same plan, same absence, no pause — differing ONLY in
-- ends_on: Control's is far in the future, Lapsed's is five days before the
-- scan date, while both memberships still read 'active'. Only the ends_on
-- rule can tell them apart, so a scan that flags neither, or flags both,
-- fails here regardless of which specific check it is missing.
--
-- A THIRD fixture — an active membership with a null ends_on, to prove a
-- fix cannot pass by treating null as "already expired" — was drafted and
-- then dropped: `memberships_dated_unless_pending_chk`
-- (20260906115146_membership_money.sql, DQA-001 made structural: "only a
-- pending row may lack an expiry") refuses any non-pending status paired
-- with a null ends_on at the INSERT itself, before any scan logic ever
-- runs. Confirmed empirically, not by reading the fix: a scratch copy with
-- 20260909170000_the_critic_was_right_four_times.sql spliced in (bytes
-- only, never opened as text) was queried afterwards via
-- pg_get_constraintdef(), inside the same rolled-back transaction, and the
-- constraint is unchanged by the fix. An active, null-ends_on row cannot
-- exist in this schema, applied or not — there is no state left for that
-- assertion to distinguish.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-0000000a0000'::uuid, 'No-Show Gym 10', 'NSHW10');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-0000000a0000'::uuid, 7);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-0000000a0101'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-0000000a0201'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0101'::uuid, 'G10 Control', '+9170000100201'),
  ('18000000-0000-4000-8000-0000000a0202'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0101'::uuid, 'G10 Lapsed',  '+9170000100202');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-0000000a0301'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, 'G10 Monthly', 30, 150000);

-- Both memberships: 'active', same starts_on. Control's ends_on is far in
-- the future; Lapsed's is 5 days before the scan date — the ONLY column
-- that differs between the two rows.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-0000000a0401'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0201'::uuid, '18000000-0000-4000-8000-0000000a0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-0000000a0402'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0202'::uuid, '18000000-0000-4000-8000-0000000a0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date - 5,   150000);

-- Both members: 20 days absent — well past the 7-day threshold — so absence
-- is never in question for either; only ends_on can tell them apart.
insert into public.attendance (id, tenant_id, branch_id, member_id, membership_id, checked_in_at, source) values
  ('18000000-0000-4000-8000-0000000a0601'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0101'::uuid, '18000000-0000-4000-8000-0000000a0201'::uuid, '18000000-0000-4000-8000-0000000a0401'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr'),
  ('18000000-0000-4000-8000-0000000a0602'::uuid, '18000000-0000-4000-8000-0000000a0000'::uuid, '18000000-0000-4000-8000-0000000a0101'::uuid, '18000000-0000-4000-8000-0000000a0202'::uuid, '18000000-0000-4000-8000-0000000a0402'::uuid,
   (('2026-06-20'::date - 20) + time '12:00') at time zone 'Asia/Kolkata', 'qr');

-- 35 — the return value: exactly one case, not zero (a scan that flags
-- nobody) and not two (a scan that never checks ends_on at all).
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-0000000a0000'::uuid, '2026-06-20'::date),
  1,
  'scenario "A membership whose end date has passed" — of the two otherwise-identical members, exactly one (the control, whose ends_on has not passed) opens a case'
);

-- 36 — the positive control MUST be flagged, read back: without this, a fix
-- that refuses every membership (never opens a case for anybody) would pass
-- assertion 37 for the wrong reason.
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000a0000'::uuid
      and member_id = '18000000-0000-4000-8000-0000000a0201'::uuid
      and status = 'open'),
  1,
  'the control member — active, ends_on 100 days in the future, 20 days absent — has exactly one open case; ends_on being in the future is the only thing that distinguishes it from Lapsed'
);

-- 37
select is(
  (select count(*)::int from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000a0000'::uuid
      and member_id = '18000000-0000-4000-8000-0000000a0202'::uuid),
  0,
  'scenario "A membership whose end date has passed" — the member still reads active, but ends_on is 5 days before the scan date: no case is opened, though absence and everything else about the row is identical to the flagged control'
);


-- ---------------------------------------------------------------------------
-- Fixtures: gym 11 — a case outlives its usefulness when the membership
-- ends (38-45)
--
-- The requirement was revised, after this file first asserted only the
-- literal word "open", to say explicitly that "live" means open, contacted
-- or follow_up_due — the three states no_show_cases_tenant_id_member_id_open_key
-- treats as one open case, and the three the red list renders. So this
-- section now builds one lapsed member and one live member IN EACH of the
-- three live states — six members, six cases, all pre-existing (inserted
-- directly or reached by a genuine follow-up, never opened by a prior scan
-- call) — so it is never about whether a case gets opened, only about what
-- a scan does to one that already exists.
--
-- Each lapsed member is paired with a live member in the SAME starting
-- status, differing only in ends_on — exactly as gym 10's Control/Lapsed
-- pair separates the opening rule from everything else. Three controls, not
-- one, because a per-status implementation (three separate closing rules
-- instead of one membership check) could pass a single open-status control
-- while still closing every contacted or follow_up_due case regardless of
-- membership — a live member's in-progress case wrongly destroyed, which is
-- exactly the silent, harmful failure this capability exists to avoid.
--
-- The contacted and follow_up_due cases are reached the same way
-- 19_follow_ups.sql reaches them: a case starts 'open', and inserting a
-- follow_up transitions it — no next_follow_up_at named moves it to
-- 'contacted', naming one moves it to 'follow_up_due'. Setting the column
-- directly, bypassing that transition, is not attempted.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('18000000-0000-4000-8000-0000000b0000'::uuid, 'No-Show Gym 11', 'NSHW11');

insert into public.organization_settings (tenant_id, no_show_threshold_days) values
  ('18000000-0000-4000-8000-0000000b0000'::uuid, 7);

insert into public.branches (id, tenant_id, name, is_default) values
  ('18000000-0000-4000-8000-0000000b0101'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, 'Main', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('18000000-0000-4000-8000-0000000b0201'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 Open Lapsed',        '+9170000110201'),
  ('18000000-0000-4000-8000-0000000b0202'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 Open Live',          '+9170000110202'),
  ('18000000-0000-4000-8000-0000000b0203'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 Contacted Lapsed',   '+9170000110203'),
  ('18000000-0000-4000-8000-0000000b0204'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 Contacted Live',     '+9170000110204'),
  ('18000000-0000-4000-8000-0000000b0205'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 FollowUpDue Lapsed', '+9170000110205'),
  ('18000000-0000-4000-8000-0000000b0206'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'G11 FollowUpDue Live',   '+9170000110206');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('18000000-0000-4000-8000-0000000b0301'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, 'G11 Monthly', 30, 150000);

-- Six memberships, all 'active', identical starts_on. Every "Lapsed"
-- member's ends_on is 5 days before the scan date; every "Live" member's is
-- 100 days after it. Nothing else distinguishes a Lapsed row from its Live
-- counterpart.
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('18000000-0000-4000-8000-0000000b0401'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0201'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date - 5,   150000),
  ('18000000-0000-4000-8000-0000000b0402'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0202'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-0000000b0403'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0203'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date - 5,   150000),
  ('18000000-0000-4000-8000-0000000b0404'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0204'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date + 100, 150000),
  ('18000000-0000-4000-8000-0000000b0405'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0205'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date - 5,   150000),
  ('18000000-0000-4000-8000-0000000b0406'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0206'::uuid, '18000000-0000-4000-8000-0000000b0301'::uuid, 'active', '2026-06-20'::date - 200, '2026-06-20'::date + 100, 150000);

-- staff, solely to satisfy follow_ups_staff_id_fkey on the follow-ups below.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('18000000-0000-4000-8000-0000000b0701'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0101'::uuid, 'gym_manager', 'G11 Staff');

-- All six cases start 'open', inserted directly — proving what the scan
-- does to a pre-existing case, not what it takes to open one. Four of the
-- six are moved on to 'contacted' or 'follow_up_due' below, before the scan
-- runs, via the same follow-up transition 19_follow_ups.sql exercises.
insert into public.no_show_cases (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('18000000-0000-4000-8000-0000000b0501'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0201'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7),
  ('18000000-0000-4000-8000-0000000b0502'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0202'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7),
  ('18000000-0000-4000-8000-0000000b0503'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0203'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7),
  ('18000000-0000-4000-8000-0000000b0504'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0204'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7),
  ('18000000-0000-4000-8000-0000000b0505'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0205'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7),
  ('18000000-0000-4000-8000-0000000b0506'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0206'::uuid, 'open', '2026-06-01'::date, '2026-05-20'::date, 12, 7);

-- F1: logged against Open Lapsed's case before the scan runs, to prove
-- closing is not deleting.
insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, notes) values
  ('18000000-0000-4000-8000-0000000b0601'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0501'::uuid, '18000000-0000-4000-8000-0000000b0701'::uuid, 'call', 'no_response', 'tried before the membership lapsed');

-- F2-F5 reach 'contacted'/'follow_up_due' via the same transition
-- 19_follow_ups.sql exercises, which — confirmed empirically, by probing a
-- throwaway fixture in a rolled-back transaction, not by reading its
-- trigger — only fires under an authenticated session naming a tenant and
-- staff member, not under postgres. So these five rows are inserted as
-- 'authenticated' with this gym's own claims, the only departure in this
-- file from "every fixture row is inserted as postgres" — required to
-- reach the state under test, not itself part of what is under test — and
-- the role is restored to postgres immediately after, before the scan runs.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '18000000-0000-4000-8000-0000000b0000',
                    'app_role', 'front_desk',
                    'staff_id', '18000000-0000-4000-8000-0000000b0701')::text,
  true);
set local role authenticated;

-- F2/F3: naming no next_follow_up_at moves a case to 'contacted'.
insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome) values
  ('18000000-0000-4000-8000-0000000b0602'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0503'::uuid, '18000000-0000-4000-8000-0000000b0701'::uuid, 'call', 'no_response'),
  ('18000000-0000-4000-8000-0000000b0603'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0504'::uuid, '18000000-0000-4000-8000-0000000b0701'::uuid, 'call', 'no_response');

-- F4/F5: naming next_follow_up_at moves a case to 'follow_up_due'.
insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, next_follow_up_at) values
  ('18000000-0000-4000-8000-0000000b0604'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0505'::uuid, '18000000-0000-4000-8000-0000000b0701'::uuid, 'call', 'timing_issue', '2026-10-01 09:00:00+05:30'::timestamptz),
  ('18000000-0000-4000-8000-0000000b0605'::uuid, '18000000-0000-4000-8000-0000000b0000'::uuid, '18000000-0000-4000-8000-0000000b0506'::uuid, '18000000-0000-4000-8000-0000000b0701'::uuid, 'call', 'timing_issue', '2026-10-01 09:00:00+05:30'::timestamptz);

set local role postgres;

-- 38 — every member already holds a live-status case, so the partial
-- unique index (relied on, not reimplemented) blocks a second one for any
-- of them; this run opens none, and the assertions that follow examine
-- what it did to the six cases that already existed.
select is(
  app.run_no_show_scan('18000000-0000-4000-8000-0000000b0000'::uuid, '2026-06-20'::date),
  0,
  'requirement "A case outlives its usefulness when the membership ends" — all six members already have a live-status case, so this run opens no new one'
);

-- 39 — scenario "A membership that lapses under a live case", open state.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0501'::uuid),
  'closed'::public.no_show_case_status,
  'scenario "A membership that lapses under a live case" — Open Lapsed''s membership still reads active but its ends_on is before the scan date, so the scan closes the open case that outlived it'
);

-- 40 — the same scenario's second half: the follow-up survives.
select is(
  (select case_id from public.follow_ups
    where id = '18000000-0000-4000-8000-0000000b0601'::uuid),
  '18000000-0000-4000-8000-0000000b0501'::uuid,
  'closing is not deleting — the follow-up logged before the scan still exists afterwards, still naming the case it belongs to, on the same reasoning as NSH-005'
);

-- 41 — scenario "A case whose member is still live": the open-status
-- control. Without this, an implementation that closes every open case,
-- lapsed or not, would pass assertions 38-40 for the wrong reason.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0502'::uuid),
  'open'::public.no_show_case_status,
  'scenario "A case whose member is still live" — Open Live''s membership has not lapsed, so its open case is left exactly as it was; this closes lapsed cases, not every case'
);

-- 42 — "live" reaches 'contacted': the requirement's own reasoning is that
-- a case already rung about is the more embarrassing one to keep
-- suggesting, not a reason to spare it.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0503'::uuid),
  'closed'::public.no_show_case_status,
  'scenario "A membership that lapses under a live case" — Contacted Lapsed''s case, already moved to contacted by a genuine follow-up, is closed exactly as an open one is: live means open, contacted or follow_up_due'
);

-- 43 — "live" reaches 'follow_up_due'.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0505'::uuid),
  'closed'::public.no_show_case_status,
  'scenario "A membership that lapses under a live case" — FollowUpDue Lapsed''s case, already scheduled for a next follow-up, is closed exactly as an open one is'
);

-- 44 — the contacted-status control: a live member's in-progress case must
-- not be destroyed by a fix that closes every case in this status
-- regardless of membership.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0504'::uuid),
  'contacted'::public.no_show_case_status,
  'scenario "A case whose member is still live" — Contacted Live''s membership has not lapsed, so its contacted case is left exactly as it was'
);

-- 45 — the follow_up_due-status control, same reasoning as 44.
select is(
  (select status from public.no_show_cases
    where tenant_id = '18000000-0000-4000-8000-0000000b0000'::uuid
      and id = '18000000-0000-4000-8000-0000000b0506'::uuid),
  'follow_up_due'::public.no_show_case_status,
  'scenario "A case whose member is still live" — FollowUpDue Live''s membership has not lapsed, so its follow_up_due case is left exactly as it was'
);


select * from finish();

rollback;
