-- 20_red_list.sql — capability: the red list view (Phase 4)
--
-- Written from openspec/changes/phase-4-retention/specs/red-list/spec.md, by
-- a session that has not read supabase/migrations/20260909130000_red_list_view.sql
-- and did not look for it (AGENTS.md rule 10). supabase/tests-holdout/ was
-- not read either. This file DID read, via information_schema.columns,
-- pg_policies and pg_class, three things that are shape rather than
-- implementation: the view's exposed column list and types, the RLS
-- policies already governing no_show_cases / members / follow_ups
-- (unchanged by this capability — 08_retention_rls.sql and 19_follow_ups.sql
-- already exercise them directly), and — after splicing the still-unmerged
-- migration into a rolled-back scratch transaction, never opened as text —
-- the view's actual reloptions and grants, to confirm what to assert against
-- rather than guessing at a column list. docs/decisions.md ADR-066 and
-- ADR-050 shaped what follows; the spec's file header names Linear as the
-- bar and the four-minutes-before-6am test, neither of which this file
-- (a pgTAP suite, not a screen) can exercise — Requirement "The screen works
-- before JavaScript does" belongs to the route/page implementation, not here.
--
-- THE ASSERTION THAT MATTERS MOST (1)
--
-- public.red_list_cases is owned by postgres, which holds BYPASSRLS. Without
-- `security_invoker = true` the view would run with the owner's rights and
-- hand every gym's no-show cases to every caller, consulting no policy on
-- no_show_cases, members or follow_ups at all — and nothing else in this
-- suite would notice: 04_contract_meta filters relkind in ('r','p'), so a
-- view's options are invisible to every meta-assertion in the repo. Assertion
-- 1 is structural (pg_class.reloptions), assertions 2-3 are behavioural
-- (two tenants, a policy-consulted read); the GUARD at assertion 2 exists
-- because a `set local role postgres` left in place makes an RLS-dependent
-- assertion meaningless (row_security_active() false, no policy applies) —
-- found twice in this repo in one day, so it is checked immediately before
-- the read it protects, not assumed from the surrounding role switches.
--
-- WHAT ELSE IS COVERED, AND WHY EACH FIXTURE PROVES ONLY ITS OWN RULE
--
--   4  days_absent is computed at read time, not read from the frozen
--      absent_days_at_open. Case 103 was opened 3 days ago when the member
--      was 8 days absent (frozen forever at 8 by design — it is evidence of
--      what the case was judged against); the member's real last visit was
--      11 days before today, so days_absent must report 11. This is the
--      requirement's whole point, per the spec's own file header.
--   5  Only unfinished cases appear. Five cases (111-115), one per status,
--      identical in every other respect: open, contacted, follow_up_due are
--      on the list; returned and closed, finished records, are not.
--   6-8  The latest follow-up is attached (case 121, two follow-ups at fixed
--      timestamps 10:00 and 11:00 IST so the comparison never depends on how
--      long this file takes to run — not now()-interval), and a case with
--      none (122) is not dropped: an inner join to follow_ups would silently
--      hide every case nobody has touched, which is precisely the work this
--      screen exists to do.
--   9-12  select-only to authenticated: INSERT, UPDATE and DELETE through
--      the view are each refused (throws_ok, sqlstate unpinned — the spec
--      says "refused", not which mechanism refuses it: withheld privilege,
--      or the view being a join with no INSTEAD OF trigger and therefore not
--      auto-updatable, both raise), and assertion 12 confirms the refused
--      writes left the underlying no_show_cases row genuinely untouched
--      rather than merely unread.
--
-- WHAT IS NOT ATTEMPTED
--
-- Ordering ("the member absent longest is first") and pagination (gate 26,
-- keyset cursor) are not asserted here — the spec's own file header frames
-- this capability as a screen, and those two requirements describe the
-- endpoint/query layer's contract over the view, not a property of the view
-- itself; testing them against a bare `select * from red_list_cases` would
-- be asserting an ORDER BY nobody promised at this layer. Same for "logging
-- a follow-up moves the case" and the concurrency scenario — those are
-- follow_ups' own requirements, already covered by 19_follow_ups.sql, and
-- repeating them here would test the same rule through a second window
-- rather than a new one.
--
-- HOW THIS WAS RUN — no local stack. The view itself
-- (20260909130000_red_list_view.sql) and its scan/follow-up dependencies are
-- already on Cloud; only 20260909170000_the_critic_was_right_four_times.sql
-- is unmerged, and is what the with-fix runs below splice in. Run via
-- `supabase db query --linked -f` against a Windows scratch path,
-- `begin … rollback`, nothing committed, with `select num_failed() as
-- failures;` on the line before `select * from finish();`, plus checkpoint
-- copies truncated at assertions 12 and 16 to localise which new assertion
-- accounted for each failure.
--
-- ORIGINAL 1-12: confirmed GREEN today (0 failures through assertion 12),
-- unaffected by the additions below.
--
-- NEW 13-19, three scenarios from the tightened spec (see the section
-- headers above each): "Days absent counts in the gym's own day" (13-16),
-- "run_no_show_scan_all() is not executable by authenticated or anon"
-- (17-18), "A nightly schedule exists" (19). Without the fix: 4 of 19 red —
-- 14 (gym C's days_absent, wrong because UTC's current_date and gym C's own
-- day disagree at the instant this was run; gym D's 16 happens to agree
-- with UTC at the same instant and is green — see the section header for
-- why exactly one of the pair is always wrong, never both, never neither),
-- 17, 18 (authenticated and anon both currently hold execute on
-- run_no_show_scan_all — confirmed directly via has_function_privilege
-- before writing the assertions), and 19 (pg_cron is not installed at all
-- yet — confirmed via pg_extension — so no nightly job can exist). With
-- 20260909170000_the_critic_was_right_four_times.sql spliced in immediately
-- after `begin;` in a separate scratch copy: all 19 GREEN, including a
-- direct recheck that assertions 14 AND 16 both read 15 (not just whichever
-- one UTC happened to agree with before the fix).
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count here is scoped to this file's own fixture tenants
--          (20000000-…) — this database permanently holds a seeded demo
--          gym, and an assertion over a whole table is a time bomb.
-- ADR-066: the assertion that matters most, above.
-- ADR-069: every assertion routes through a pgTAP function (ok / is /
--          results_eq / throws_ok); nothing here is a bare top-level select
--          of a helper that could print a stray line prove would count as a
--          test nobody wrote.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(19);


-- ---------------------------------------------------------------------------
-- Fixtures. Two tenants (A, B); tenant B exists only to hold one case for the
-- isolation scenario. Every scenario below gets its own member and its own
-- case, so one scenario's fixture can never be mistaken for another's.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('20000000-0000-4000-8000-000000000001'::uuid, 'Red List Gym A', 'RED20A'),
  ('20000000-0000-4000-8000-000000000002'::uuid, 'Red List Gym B', 'RED20B');

insert into public.branches (id, tenant_id, name, is_default) values
  ('20000000-0000-4000-8000-000000000011'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('20000000-0000-4000-8000-000000000012'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('20000000-0000-4000-8000-000000000021'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('20000000-0000-4000-8000-000000000023'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Colleague'),
  ('20000000-0000-4000-8000-000000000022'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, '20000000-0000-4000-8000-000000000012'::uuid, 'front_desk',  'B Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('20000000-0000-4000-8000-000000000031'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Iso A',        '+912000000031'),
  ('20000000-0000-4000-8000-000000000032'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, '20000000-0000-4000-8000-000000000012'::uuid, 'M Iso B',        '+912000000032'),
  ('20000000-0000-4000-8000-000000000033'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Days',         '+912000000033'),
  ('20000000-0000-4000-8000-000000000034'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Status Open',  '+912000000034'),
  ('20000000-0000-4000-8000-000000000035'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Status Cont',  '+912000000035'),
  ('20000000-0000-4000-8000-000000000036'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Status Due',   '+912000000036'),
  ('20000000-0000-4000-8000-000000000037'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Status Ret',   '+912000000037'),
  ('20000000-0000-4000-8000-000000000038'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Status Closed','+912000000038'),
  ('20000000-0000-4000-8000-000000000039'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M FollowUp',     '+912000000039'),
  ('20000000-0000-4000-8000-00000000003a'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M NoFollowUp',   '+912000000041'),
  ('20000000-0000-4000-8000-00000000003b'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000011'::uuid, 'M Write',        '+912000000042');

-- Gym-local "today" for tenants A and B, computed the exact way the view
-- computes it: `(now() at time zone o.timezone)::date`, read from
-- organizations.timezone rather than hardcoding the column default so a
-- later change to that default cannot silently reintroduce this bug. Both
-- gyms carry the default (Asia/Kolkata, ahead of UTC), so `current_date`
-- (which evaluates in UTC, ADR-039) disagrees with it for part of every
-- day — and did, in this exact fixture, until a blind critic caught
-- assertion 4 reading 12 where it should read 11: `opened_on` had been
-- stamped from `current_date` while the view (correctly, after the fix
-- under test) reads "today" from the gym's own timezone, so
-- `absent_days_at_open + (today - opened_on)` picked up an extra day
-- whenever the gym's local date had already rolled over ahead of UTC's.
-- One temp table per tenant (mirrors `tz_fixture` below, which does the
-- same thing for gyms C and D), so every row below reads from it rather
-- than repeating the expression.
create temp table today_a as
select (now() at time zone o.timezone)::date as d
  from public.organizations o where o.id = '20000000-0000-4000-8000-000000000001'::uuid;

create temp table today_b as
select (now() at time zone o.timezone)::date as d
  from public.organizations o where o.id = '20000000-0000-4000-8000-000000000002'::uuid;

-- Generic cases (status filter and isolation scenarios) all share the same
-- absence snapshot; nothing about them exercises the read-time computation.
insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('20000000-0000-4000-8000-000000000101'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000031'::uuid, 'open',         (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000102'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, '20000000-0000-4000-8000-000000000032'::uuid, 'open',         (select d from today_b) - 10, (select d from today_b) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000111'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000034'::uuid, 'open',         (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000112'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000035'::uuid, 'contacted',    (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000113'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000036'::uuid, 'follow_up_due',(select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000114'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000037'::uuid, 'returned',     (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000115'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000038'::uuid, 'closed',       (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000121'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000039'::uuid, 'contacted',    (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000122'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-00000000003a'::uuid, 'open',         (select d from today_a) - 10, (select d from today_a) - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000131'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-00000000003b'::uuid, 'open',         (select d from today_a) - 10, (select d from today_a) - 10, 10, 7);

-- The one case built specifically to prove days_absent is recomputed, not
-- read from the frozen snapshot: opened 3 days ago (gym-local) when the
-- member was 8 days absent (absent_days_at_open, frozen forever at 8); the
-- member's real last visit was 11 days before today (gym-local), so today's
-- days_absent must be 11.
insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('20000000-0000-4000-8000-000000000103'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000033'::uuid, 'open', (select d from today_a) - 3, (select d from today_a) - 11, 8, 7);

-- Two follow-ups on the same case, written as postgres (bypasses RLS,
-- exactly as 19_follow_ups.sql's own fixtures) so their existence tests
-- nothing and cannot be credited to any rule under test. Fixed timestamps,
-- not now()-interval, so the "latest" comparison never depends on how long
-- this file takes to run.
insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, created_at) values
  ('20000000-0000-4000-8000-000000000201'::uuid, '20000000-0000-4000-8000-000000000001'::uuid,
   '20000000-0000-4000-8000-000000000121'::uuid, '20000000-0000-4000-8000-000000000021'::uuid,
   'call', 'no_response', '2026-06-01 10:00:00+05:30'::timestamptz),
  ('20000000-0000-4000-8000-000000000202'::uuid, '20000000-0000-4000-8000-000000000001'::uuid,
   '20000000-0000-4000-8000-000000000121'::uuid, '20000000-0000-4000-8000-000000000023'::uuid,
   'whatsapp', 'will_return', '2026-06-01 11:00:00+05:30'::timestamptz);


-- ---------------------------------------------------------------------------
-- STRUCTURAL — the assertion that matters most (1)
-- ---------------------------------------------------------------------------

-- 1
select ok(
  exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'red_list_cases'
       and c.relkind = 'v'
       and 'security_invoker=true' = any (c.reloptions)
  ),
  'STRUCTURAL — public.red_list_cases carries security_invoker=true in pg_class.reloptions. The view is owned by postgres, which holds BYPASSRLS; without this option it would run with the owner''s rights, consulting no policy on no_show_cases, members or follow_ups at all, and hand every gym''s cases to every caller. It is the one option whose absence is silent, total, and invisible to every other test in this repo: 04_contract_meta filters relkind in (''r'',''p''), so no meta-assertion anywhere else ever looks at a view''s options'
);


-- ---------------------------------------------------------------------------
-- Behavioural isolation, and the role guard immediately before it (2-3)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '20000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '20000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 2 — this exact bug (a lingering `set local role postgres` making an
-- RLS-dependent assertion meaningless) has been found twice in this repo in
-- one day; asserted immediately before the isolation check it guards.
select ok(
  row_security_active('public.no_show_cases'),
  'GUARD — querying as authenticated (front_desk, tenant A), not postgres: row_security_active(''public.no_show_cases'') is true, so the isolation assertion that follows is actually exercising a policy and not a trusted-context bypass'
);

-- 3 — both rows exist and both would satisfy the view''s join; only a policy
-- that is actually consulted keeps tenant B''s case off tenant A''s screen.
select results_eq(
  $$
    select id from public.red_list_cases
     where id in ('20000000-0000-4000-8000-000000000101'::uuid, '20000000-0000-4000-8000-000000000102'::uuid)
     order by id
  $$,
  $$ values ('20000000-0000-4000-8000-000000000101'::uuid) $$,
  'BEHAVIOURAL — a staff session of gym A selecting from red_list_cases sees its own gym''s case and none of gym B''s'
);


-- ---------------------------------------------------------------------------
-- days_absent is computed at read time, not read from absent_days_at_open (4)
-- ---------------------------------------------------------------------------

-- 4
select results_eq(
  $$
    select days_absent, absent_days_at_open
      from public.red_list_cases
     where id = '20000000-0000-4000-8000-000000000103'::uuid
  $$,
  $$ values (11, 8) $$,
  'requirement "Days absent is computed at read time" — a case opened 3 days ago at 8 days absent (frozen in absent_days_at_open) reports 11 today, not the frozen 8: the member''s last visit was 11 days ago and days_absent is measured from that, afresh, every read'
);


-- ---------------------------------------------------------------------------
-- Only unfinished cases appear (5)
-- ---------------------------------------------------------------------------

-- 5
select results_eq(
  $$
    select id from public.red_list_cases
     where id in (
       '20000000-0000-4000-8000-000000000111'::uuid,
       '20000000-0000-4000-8000-000000000112'::uuid,
       '20000000-0000-4000-8000-000000000113'::uuid,
       '20000000-0000-4000-8000-000000000114'::uuid,
       '20000000-0000-4000-8000-000000000115'::uuid
     )
     order by id
  $$,
  $$ values
      ('20000000-0000-4000-8000-000000000111'::uuid),
      ('20000000-0000-4000-8000-000000000112'::uuid),
      ('20000000-0000-4000-8000-000000000113'::uuid)
  $$,
  'requirement "The list shows open cases" — open, contacted and follow_up_due are on the list; returned and closed, finished records, are not, though all five otherwise satisfy the view''s join identically'
);


-- ---------------------------------------------------------------------------
-- The latest follow-up is the one attached; a case with none is not dropped
-- (6-7)
-- ---------------------------------------------------------------------------

-- 6
select results_eq(
  $$
    select last_follow_up_channel::text collate "default",
           last_follow_up_outcome::text collate "default",
           last_follow_up_by,
           last_follow_up_at
      from public.red_list_cases
     where id = '20000000-0000-4000-8000-000000000121'::uuid
  $$,
  $$ values ('whatsapp'::text, 'will_return'::text, 'A Colleague'::text, '2026-06-01 11:00:00+05:30'::timestamptz) $$,
  'requirement "What was already tried is visible" — with two follow-ups on the case, the view attaches the LATER one (11:00, A Colleague, whatsapp, will_return), not the earlier (10:00, A Desk, call, no_response)'
);

-- 7
select is(
  (select count(*)::int from public.red_list_cases where id = '20000000-0000-4000-8000-000000000122'::uuid),
  1,
  'scenario "A case nobody has touched" — a case with zero follow-ups still appears on the list; an inner join to follow_ups would have silently dropped it, which is precisely the work this screen exists to show'
);

-- 8
select results_eq(
  $$
    select last_follow_up_at, last_follow_up_channel, last_follow_up_outcome, last_follow_up_by
      from public.red_list_cases
     where id = '20000000-0000-4000-8000-000000000122'::uuid
  $$,
  $$ values (null::timestamptz, null::public.contact_channel, null::public.follow_up_outcome, null::text) $$,
  'scenario "A case nobody has touched" — its latest-follow-up columns come back null rather than the row being absent'
);


-- ---------------------------------------------------------------------------
-- It is select-only to authenticated (9-12)
-- ---------------------------------------------------------------------------

-- 9
select throws_ok($$
  insert into public.red_list_cases (id) values (gen_random_uuid())
$$, null::char(5), null,
  'requirement "It is select-only to authenticated" — an INSERT into the view is refused, whether for want of privilege or because the view is not simple enough to be updatable; a case never moves because someone wrote to the list they were reading'
);

-- 10
select throws_ok($$
  update public.red_list_cases set status = 'closed' where id = '20000000-0000-4000-8000-000000000131'::uuid
$$, null::char(5), null,
  'requirement "It is select-only to authenticated" — an UPDATE through the view is refused the same way'
);

-- 11
select throws_ok($$
  delete from public.red_list_cases where id = '20000000-0000-4000-8000-000000000131'::uuid
$$, null::char(5), null,
  'requirement "It is select-only to authenticated" — a DELETE through the view is refused the same way'
);

set local role postgres;

-- 12
select is(
  (select status::text from public.no_show_cases where id = '20000000-0000-4000-8000-000000000131'::uuid),
  'open',
  'the three refused writes through the view left the underlying case exactly as it was — a case moves because a follow-up was logged or a member came back, never because somebody wrote to the list they were reading'
);


-- ---------------------------------------------------------------------------
-- Days absent counts in the gym's own day, never UTC (13-16)
--
-- current_date evaluates in the session timezone and every Supabase
-- connection is UTC — ADR-039, quoted verbatim in the header of the
-- migration that created opened_on (20260906115156_retention.sql). Gyms C
-- and D sit in Etc/GMT-12 (UTC+12) and Etc/GMT+12 (UTC-12): fixed offsets,
-- no DST, exactly 24h apart, so their own calendar "today" differs by
-- exactly one day at every instant — the same construction 18_no_show_scan
-- uses and for the same reason, captured once into a temp table so every
-- assertion below reasons about the same two dates the fixtures were built
-- from. Each member's last_attended_on is set 15 days before THEIR OWN
-- gym's today, so the correct days_absent is 15 for both, always.
--
-- The discriminating property: UTC's current_date always equals EXACTLY ONE
-- of the two gyms' own today (never both, never neither — see 18's header
-- for the proof), so a view reading current_date computes the right number
-- for whichever gym UTC happens to agree with at run time, and a number
-- off by exactly one day for the other. Which gym that is varies with when
-- this file happens to run; that at least one of assertions 14/16 is wrong
-- for that bug does not.
-- ---------------------------------------------------------------------------

create temp table tz_fixture as
select
  (now() at time zone 'Etc/GMT-12')::date as date_a,
  (now() at time zone 'Etc/GMT+12')::date as date_b;

insert into public.organizations (id, name, gym_code, timezone) values
  ('20000000-0000-4000-8000-000000000401'::uuid, 'Red List Gym C', 'RED20C', 'Etc/GMT-12'),
  ('20000000-0000-4000-8000-000000000402'::uuid, 'Red List Gym D', 'RED20D', 'Etc/GMT+12');

insert into public.branches (id, tenant_id, name, is_default) values
  ('20000000-0000-4000-8000-000000000411'::uuid, '20000000-0000-4000-8000-000000000401'::uuid, 'C Main', true),
  ('20000000-0000-4000-8000-000000000412'::uuid, '20000000-0000-4000-8000-000000000402'::uuid, 'D Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('20000000-0000-4000-8000-000000000421'::uuid, '20000000-0000-4000-8000-000000000401'::uuid, '20000000-0000-4000-8000-000000000411'::uuid, 'front_desk', 'C Desk'),
  ('20000000-0000-4000-8000-000000000422'::uuid, '20000000-0000-4000-8000-000000000402'::uuid, '20000000-0000-4000-8000-000000000412'::uuid, 'front_desk', 'D Desk');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('20000000-0000-4000-8000-000000000431'::uuid, '20000000-0000-4000-8000-000000000401'::uuid, '20000000-0000-4000-8000-000000000411'::uuid, 'M TZ C', '+9120000000431'),
  ('20000000-0000-4000-8000-000000000432'::uuid, '20000000-0000-4000-8000-000000000402'::uuid, '20000000-0000-4000-8000-000000000412'::uuid, 'M TZ D', '+9120000000432');

insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days)
select '20000000-0000-4000-8000-000000000441'::uuid, '20000000-0000-4000-8000-000000000401'::uuid, '20000000-0000-4000-8000-000000000431'::uuid, 'open'::public.no_show_case_status, date_a - 3, date_a - 15, 12, 7
  from tz_fixture
union all
select '20000000-0000-4000-8000-000000000442'::uuid, '20000000-0000-4000-8000-000000000402'::uuid, '20000000-0000-4000-8000-000000000432'::uuid, 'open'::public.no_show_case_status, date_b - 3, date_b - 15, 12, 7
  from tz_fixture;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '20000000-0000-4000-8000-000000000401',
                    'app_role', 'front_desk',
                    'staff_id', '20000000-0000-4000-8000-000000000421')::text,
  true);
set local role authenticated;

-- 13 — the guard, immediately before the read it protects (see the file
-- header and the assertion-2 guard above: a lingering postgres role makes
-- this whole read meaningless, and it has been found four times in this repo).
select ok(
  row_security_active('public.no_show_cases'),
  'GUARD — querying as authenticated (front_desk, gym C / Etc/GMT-12), not postgres: row_security_active is true for the days-absent read that follows'
);

-- 14
select is(
  (select days_absent from public.red_list_cases where id = '20000000-0000-4000-8000-000000000441'::uuid),
  15,
  'scenario "Days absent counts in the gym''s own day" — gym C (Etc/GMT-12): last_attended_on is 15 days before gym C''s OWN today, and days_absent must read 15 regardless of what UTC''s current_date happens to be right now'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '20000000-0000-4000-8000-000000000402',
                    'app_role', 'front_desk',
                    'staff_id', '20000000-0000-4000-8000-000000000422')::text,
  true);
set local role authenticated;

-- 15
select ok(
  row_security_active('public.no_show_cases'),
  'GUARD — querying as authenticated (front_desk, gym D / Etc/GMT+12), not postgres: row_security_active is true for the days-absent read that follows'
);

-- 16 — the discriminating half of the pair: gym D''s own today is ALWAYS
-- exactly one day away from gym C''s (assertion 14''s), so UTC''s current_date
-- cannot agree with both — whichever of 14/16 UTC does not coincidentally
-- agree with is forced wrong by a current_date-based bug, on any run.
select is(
  (select days_absent from public.red_list_cases where id = '20000000-0000-4000-8000-000000000442'::uuid),
  15,
  'scenario "Days absent counts in the gym''s own day" — gym D (Etc/GMT+12), read at the same real instant as gym C: days_absent must read 15 measured against gym D''s OWN today, which is always exactly one calendar day away from gym C''s'
);

set local role postgres;


-- ---------------------------------------------------------------------------
-- run_no_show_scan_all() is not executable by authenticated or by anon (17-18)
--
-- public.run_no_show_scan_all() (confirmed in the catalogue: zero arguments,
-- returns record) is the Edge Function's own entry point, and it is meant to
-- run only on the nightly schedule, as postgres. `revoke ... from public`
-- does NOT remove Supabase's own explicit per-role grants to authenticated
-- and anon — every fresh function starts world-executable via those grants
-- regardless of what is revoked from PUBLIC, and that gap is exactly the bug
-- these two assertions pin: has_function_privilege is what actually proves
-- the ACL, not the presence of a revoke statement anywhere in a migration.
-- ---------------------------------------------------------------------------

-- 17
select ok(
  not has_function_privilege('authenticated', 'public.run_no_show_scan_all()', 'execute'),
  'requirement — authenticated does NOT hold execute on public.run_no_show_scan_all(); revoking from PUBLIC alone does not touch Supabase''s explicit per-role grant to authenticated, which is the actual ACL entry that has to be revoked'
);

-- 18
select ok(
  not has_function_privilege('anon', 'public.run_no_show_scan_all()', 'execute'),
  'requirement — anon does NOT hold execute on public.run_no_show_scan_all() either, asserted separately from authenticated because Supabase grants each role its own ACL entry'
);


-- ---------------------------------------------------------------------------
-- A nightly schedule exists (19)
--
-- This pins a MECHANISM — that some pg_cron job runs the scan nightly — not
-- its exact cron expression or job name, which are the implementer's call.
-- Guarded with a DO block rather than a bare `select ... from cron.job`
-- because pg_cron is not installed on this project until the fix creates
-- it: without the guard, this assertion would raise `schema "cron" does not
-- exist` and abort the whole transaction on every run before the fix lands,
-- rather than simply reporting red.
--
-- CORRECTION, found by a blind critic: the value is computed inside the DO
-- block (it has to be — whether `cron.job` can even be referenced depends on
-- a runtime check of pg_extension), but ADR-069 still requires the assertion
-- itself to be a plain top-level `select ok(...)`, never a `perform ok(...)`
-- inside the block. `perform` discards ok()'s returned text; ok() still
-- advances pgTAP's internal counter, but nothing is written to stdout, and
-- `prove` reads TAP lines from stdout, not the counter. This file's own
-- comment used to claim "exactly one TAP line is still produced either
-- way" — that was wrong, is deleted, and is exactly why CI read "you
-- planned 19 tests but ran 18" while `num_failed()` read 0 locally: the
-- counter agreed with plan(19), the emitted stream did not, and
-- `num_failed()` only ever reads the counter. The fix keeps the DO block for
-- the guarded computation, writes its result into a temp table (the same
-- pattern the tz_fixture assertions above already use for a value computed
-- ahead of the pgTAP call that reads it), and moves the actual `ok()` to a
-- bare top-level `select`, so it always emits its TAP line.
-- ---------------------------------------------------------------------------

do $do$
declare
  v_scheduled boolean;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $sql$
      select exists (
        select 1 from cron.job
         where command ilike '%run_no_show_scan_all%'
           and active
      )
    $sql$ into v_scheduled;
  else
    v_scheduled := false;
  end if;

  create temp table cron_fixture as select v_scheduled as scheduled;
end
$do$;

-- 19
select ok(
  (select scheduled from cron_fixture),
  'requirement — a cron.job row exists and is active, running public.run_no_show_scan_all(); this pins that SOME nightly mechanism exists, not which schedule or job name'
);


select * from finish();
rollback;
