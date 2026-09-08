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
-- HOW THIS WAS RUN — no local stack, and the view is not applied to Cloud
-- yet. Verified by splicing supabase/migrations/20260909130000_red_list_view.sql
-- into a scratch copy immediately after `begin;` (follow_ups and
-- no_show_cases already exist on Cloud, so 20260909110000_follow_ups.sql did
-- not need splicing), run via `supabase db query --linked -f` against a
-- Windows scratch path, `begin … rollback`, nothing committed. Confirmed two
-- ways per ADR-069: `select num_failed() as failures;` on the line before
-- `select * from finish();` returned 0, and — because a CLI query shows only
-- the last result set — a second scratch copy rerouted every assertion's
-- select into a temp table (`insert into pg_temp.tap_capture(line) select
-- ok(...)`, granting the temp table and its sequence to `authenticated` for
-- the role-switched assertions) so the whole numbered TAP stream could be
-- read back in one result set: `ok 1` through `ok 12`, in order, nothing out
-- of sequence, nothing extra.
--
-- 12 assertions, plan(12), 12 TAP lines. All 12 GREEN on this run — the
-- migration this file was written against, sight unseen, already does what
-- the spec asks for every scenario this file covers.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count here is scoped to this file's own two fixture
--          tenants (20000000-…) — this database permanently holds a seeded
--          demo gym, and an assertion over a whole table is a time bomb.
-- ADR-066: the assertion that matters most, above.
-- ADR-069: every assertion routes through a pgTAP function (ok / is /
--          results_eq / throws_ok); nothing here is a bare top-level select
--          of a helper that could print a stray line prove would count as a
--          test nobody wrote.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(12);


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

-- Generic cases (status filter and isolation scenarios) all share the same
-- absence snapshot; nothing about them exercises the read-time computation.
insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('20000000-0000-4000-8000-000000000101'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000031'::uuid, 'open',         current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000102'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, '20000000-0000-4000-8000-000000000032'::uuid, 'open',         current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000111'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000034'::uuid, 'open',         current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000112'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000035'::uuid, 'contacted',    current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000113'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000036'::uuid, 'follow_up_due',current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000114'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000037'::uuid, 'returned',     current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000115'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000038'::uuid, 'closed',       current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000121'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000039'::uuid, 'contacted',    current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000122'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-00000000003a'::uuid, 'open',         current_date - 10, current_date - 10, 10, 7),
  ('20000000-0000-4000-8000-000000000131'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-00000000003b'::uuid, 'open',         current_date - 10, current_date - 10, 10, 7);

-- The one case built specifically to prove days_absent is recomputed, not
-- read from the frozen snapshot: opened 3 days ago when the member was 8
-- days absent (absent_days_at_open, frozen forever at 8); the member's real
-- last visit was 11 days before today, so today's days_absent must be 11.
insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, last_attended_on, absent_days_at_open, threshold_days) values
  ('20000000-0000-4000-8000-000000000103'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000033'::uuid, 'open', current_date - 3, current_date - 11, 8, 7);

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


select * from finish();
rollback;
