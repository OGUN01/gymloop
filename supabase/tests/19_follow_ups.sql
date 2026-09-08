-- 19_follow_ups.sql — capability: follow-ups (Phase 4)
--
-- Written from openspec/changes/phase-4-retention/specs/follow-ups/spec.md,
-- by a session that has not read the implementation and did not look for it
-- (AGENTS.md rule 10). No migration dated 20260909100000 or later was
-- opened, supabase/tests-holdout/ was not read, and nothing in the catalogue
-- was inspected to find out how any of this is built. Every assertion below
-- is derived from the spec's five requirements, docs/domain-rules.md
-- NSH-005 to NSH-007, and the Phase 1 table shape in
-- 20260906115156_retention.sql (which this file DID read — it predates the
-- implementer's cutoff and is where public.follow_ups and
-- public.no_show_cases are created).
--
-- WHAT THIS FILE ASSUMES, STATED UP FRONT
--
-- follow_ups grants insert directly to authenticated and the tenant write
-- policy is "tenant_id = current tenant", nothing narrower — so every
-- behavioural assertion is a plain insert or update against the table, no
-- endpoint or RPC involved. That is the whole point of requirement 1's third
-- scenario and of ADR-066: a rule living only in a Route Handler has a
-- supported way round it.
--
-- 32 assertions, plan(32), 32 TAP lines. Confirmed against Cloud via
-- `supabase db query --linked -f`, begin…rollback, nothing committed, with
-- `select num_failed() as failures;` on the line before `select * from
-- finish();`, plus checkpoint copies truncated at assertions 24, 25, 26 and
-- 28 to localise exactly which assertion accounts for each failure (the CLI
-- shows only the last result set, so num_failed() at a chosen cut point is
-- how a specific assertion's status is isolated without it).
--
-- ORIGINAL 1-24: all confirmed GREEN as this file stands today (0 failures
-- through assertion 24) — Cloud has moved on since this file was first
-- written; whatever the state was when the RED/GREEN breakdown below this
-- paragraph was first drafted, requirements 1-4 (attribution, append-only,
-- the concurrency-lock catalogue check, and the closed-case refusal) are
-- now all built and green. That breakdown is kept, unedited, as the
-- record of what was true at the time; it is not current truth.
--
-- NEW 25-28, "A correction does not re-decide the schedule": exactly ONE
-- red without the fix — 26, the assertion that matters (status and
-- next_follow_up_at both unchanged after a correction). 25 (the correction
-- insert itself, lives_ok), 27 and 28 (the positive control: an ordinary
-- follow-up on an identically-staged case DOES move to contacted) are
-- green today, which is expected — this section's whole point is that only
-- the derive-on-correction path is broken, not follow-up handling in
-- general. All 32 (1-32) are GREEN with
-- 20260909170000_the_critic_was_right_four_times.sql spliced in immediately
-- after `begin;` in a separate scratch copy.
--
-- THE ORIGINAL RED/GREEN BREAKDOWN, AS FIRST WRITTEN (now superseded by the
-- paragraph above — kept for its own record, not as current status):
--
--   RED (11) — the rule under test is not built: 3, 4 (naming a colleague is
--   not refused, ADR-071's shape: requirement 1); 5, 6 (a claimless session's
--   write is not refused either — the same null-actor defect this project
--   has already shipped twice, GL026/GL016's cousin, still open here); 10,
--   12 (a correction can currently point at a different case's entry — only
--   the composite tenant FK is checked, not the case); 16 (no serialising
--   lock or row-locking trigger exists yet on follow_ups or no_show_cases);
--   20, 22 (recording a follow-up does not yet move the case to contacted or
--   follow_up_due, or stamp next_follow_up_at); 23, 24 (a closed case
--   currently accepts a follow-up — nothing reads the case's status before
--   inserting).
--
--   GREEN (17), and each is said here because it is coverage the suite
--   earns rather than the rule proving itself: 1, 2, 7, 8, 9, 11 (a
--   legitimate insert, and a same-case correction, are unblocked, and the
--   corrected row is untouched, because nothing has update on follow_ups —
--   append-only is already true STRUCTURALLY, by privilege, not by any rule
--   this phase adds); 13, 14, 15 (the update/delete privilege refusal in
--   requirement 2's third scenario is the SAME structural fact — revoke all;
--   grant select, insert on follow_ups, from 20260906115156_retention.sql,
--   already closes it); 17, 18 (two sequential follow-ups on one case
--   already succeed, because nothing today refuses a second contact —
--   correct per the spec's own scenario, which says the rule is about
--   concurrency and not about a case being contacted once); 19, 21 (logging
--   a follow-up with or without next_follow_up_at is not refused — only the
--   resulting case state is unproven, which is what 20 and 22 catch); 25,
--   26, 27, 28 (requirement 5, assignment, is already whole: authenticated
--   already holds update on no_show_cases, the tenant policy already scopes
--   it, and ADR-052's composite foreign key
--   (tenant_id, assigned_to_staff_id) references staff (tenant_id, id)
--   already refuses assigning a tenant A case to a tenant B staff member —
--   nothing in this requirement needed the implementer to add anything, and
--   assertions 25-28 exist to prove that rather than assume it). These
--   numbers are from the ORIGINAL 28-assertion file and do not match the
--   current numbering (the new section shifted the old 25-28 to 29-32).
--
-- WHAT IS NOT ATTEMPTED
--
-- Requirement 3's first scenario — two follow-ups AT THE SAME INSTANT — is
-- not staged for real: one transaction cannot make two backends race, so
-- assertion 16 proves only that a serialising mechanism (an advisory lock,
-- or a row lock in a trigger on follow_ups or no_show_cases) is present in
-- the write path, not that it is taken on the right key or before the right
-- read. It is written to say exactly that, and no more.
--
-- No assertion here pins a mechanism as trigger, constraint or policy — each
-- throws_ok is null::char(5), null (any SQLSTATE), matching this project's
-- existing suites (16_checkin.sql, 17_pause_decision.sql). Assertion 16 is
-- the one deliberate catalogue check and its own message says so.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own tenant A fixtures — this
--          database permanently holds a seeded demo gym and 46 members, and
--          an assertion over a whole table is a time bomb.
-- ADR-069: every assertion routes through a pgTAP function (ok / lives_ok /
--          throws_ok / results_eq); nothing here is a bare top-level select
--          of a helper that could print a stray line prove would count as a
--          test nobody wrote.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(32);


-- ---------------------------------------------------------------------------
-- Fixtures.
--
-- Tenant A does all the work; tenant B exists only to hold a staff member of
-- another gym, for the assignment-refusal scenario. Every no_show_case below
-- gets its OWN member (the live-status partial unique index on no_show_cases
-- allows only one open/contacted/follow_up_due case per member) and its own
-- case row, so that one scenario's write can never change the premises of
-- another's.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('19000000-0000-4000-8000-000000000001'::uuid, 'Follow-up Gym A', 'FUP19A'),
  ('19000000-0000-4000-8000-000000000002'::uuid, 'Follow-up Gym B', 'FUP19B');

insert into public.branches (id, tenant_id, name, is_default) values
  ('19000000-0000-4000-8000-000000000011'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('19000000-0000-4000-8000-000000000012'::uuid, '19000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('19000000-0000-4000-8000-000000000021'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('19000000-0000-4000-8000-000000000022'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Colleague'),
  ('19000000-0000-4000-8000-000000000023'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'trainer',     'A Assignee'),
  ('19000000-0000-4000-8000-000000000025'::uuid, '19000000-0000-4000-8000-000000000002'::uuid, '19000000-0000-4000-8000-000000000012'::uuid, 'front_desk',  'B Desk');

-- One member per case (thirteen), all tenant A.
insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('19000000-0000-4000-8000-000000000031'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Attrib Success',    '+911900000031'),
  ('19000000-0000-4000-8000-000000000032'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Attrib Colleague',  '+911900000032'),
  ('19000000-0000-4000-8000-000000000033'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Attrib NoClaim',    '+911900000033'),
  ('19000000-0000-4000-8000-000000000034'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Append Only',       '+911900000034'),
  ('19000000-0000-4000-8000-000000000035'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Corr Case One',     '+911900000035'),
  ('19000000-0000-4000-8000-000000000036'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Corr Case Two',     '+911900000036'),
  ('19000000-0000-4000-8000-000000000037'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Concurrency',       '+911900000037'),
  ('19000000-0000-4000-8000-000000000038'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Status No Next',    '+911900000038'),
  ('19000000-0000-4000-8000-000000000039'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Status With Next',  '+911900000039'),
  ('19000000-0000-4000-8000-00000000003a'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Closed',            '+911900000041'),
  ('19000000-0000-4000-8000-00000000003b'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Assign Success',    '+911900000042'),
  ('19000000-0000-4000-8000-00000000003c'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Assign Cross',      '+911900000043'),
  ('19000000-0000-4000-8000-00000000003d'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Privilege',         '+911900000044'),
  ('19000000-0000-4000-8000-00000000003e'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M Corr No Redecide',  '+911900000045'),
  ('19000000-0000-4000-8000-00000000003f'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000011'::uuid, 'M NonCorr Control',   '+911900000046');

-- Thirteen cases, one per member, tenant A. All 'open' (the default) except
-- the one built already 'closed'. absent_days_at_open/threshold_days are
-- arbitrary valid snapshots — nothing here exercises the scan.
insert into public.no_show_cases
  (id, tenant_id, member_id, status, opened_on, absent_days_at_open, threshold_days) values
  ('19000000-0000-4000-8000-000000000051'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000031'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000052'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000032'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000053'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000033'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000054'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000034'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000055'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000035'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000056'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000036'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000057'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000037'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000058'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000038'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-000000000059'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-000000000039'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005a'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003a'::uuid, 'closed', current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005b'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003b'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005c'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003c'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005d'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003d'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005e'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003e'::uuid, 'open',   current_date - 10, 10, 7),
  ('19000000-0000-4000-8000-00000000005f'::uuid, '19000000-0000-4000-8000-000000000001'::uuid, '19000000-0000-4000-8000-00000000003f'::uuid, 'open',   current_date - 10, 10, 7);

-- The 'closed' fixture also gets its own closed_at, so a scenario that reads
-- it back afterwards sees a genuinely finished record rather than a status
-- label with nothing behind it.
update public.no_show_cases
   set closed_at = now() - interval '1 day'
 where id = '19000000-0000-4000-8000-00000000005a'::uuid;

-- Four pre-existing follow_ups, written as postgres (bypasses row security,
-- exactly as the seed and every other fixture in this repo does) so that
-- their existence tests nothing and cannot be credited to any rule under
-- test. Each belongs to a scenario that needs a row already in place before
-- the assertion runs.
insert into public.follow_ups
  (id, tenant_id, case_id, staff_id, channel, outcome, notes, created_at) values
  -- F1: the original entry requirement 2's correction scenario corrects.
  ('19000000-0000-4000-8000-000000000071'::uuid, '19000000-0000-4000-8000-000000000001'::uuid,
   '19000000-0000-4000-8000-000000000054'::uuid, '19000000-0000-4000-8000-000000000021'::uuid,
   'call', 'no_response', 'first attempt, no answer', now() - interval '2 hours'),
  -- F_case1: belongs to case 055; requirement 2's cross-case scenario points
  -- a correction on case 056 at this row, which belongs to a different case.
  ('19000000-0000-4000-8000-000000000072'::uuid, '19000000-0000-4000-8000-000000000001'::uuid,
   '19000000-0000-4000-8000-000000000055'::uuid, '19000000-0000-4000-8000-000000000021'::uuid,
   'call', 'no_response', 'case one, original entry', now() - interval '2 hours'),
  -- F_first: "a case that was contacted an hour ago" (requirement 3, scenario
  -- "Two follow-ups in sequence").
  ('19000000-0000-4000-8000-000000000073'::uuid, '19000000-0000-4000-8000-000000000001'::uuid,
   '19000000-0000-4000-8000-000000000057'::uuid, '19000000-0000-4000-8000-000000000021'::uuid,
   'whatsapp', 'no_response', 'contacted an hour ago', now() - interval '1 hour'),
  -- F_priv: the target of requirement 2's update/delete privilege scenario.
  ('19000000-0000-4000-8000-000000000074'::uuid, '19000000-0000-4000-8000-000000000001'::uuid,
   '19000000-0000-4000-8000-00000000005d'::uuid, '19000000-0000-4000-8000-000000000021'::uuid,
   'call', 'will_return', 'original, must survive every attempt to change it', now() - interval '3 hours');


-- ---------------------------------------------------------------------------
-- Requirement: A follow-up records who did it, and it is the acting staff
-- member (1-6)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 1
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000081'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000051'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'will_return')
$$, 'scenario "Logging a follow-up" — a staff member logging a follow-up on a case in their own gym, naming themselves, is not refused');

set local role postgres;

-- 2 — lives_ok alone proves nothing here: a policy-filtered write raises
-- nothing and affects zero rows. The row has to read back.
select results_eq(
  $$
    select staff_id, case_id, channel::text collate "default", outcome::text collate "default"
      from public.follow_ups
     where id = '19000000-0000-4000-8000-000000000081'::uuid
  $$,
  $$ values ('19000000-0000-4000-8000-000000000021'::uuid,
             '19000000-0000-4000-8000-000000000051'::uuid,
             'call'::text, 'will_return'::text) $$,
  'scenario "Logging a follow-up" — it landed, recorded against the staff member who logged it'
);

-- 3 — everything about this write is otherwise legitimate: front_desk 21 is
-- acting in their own gym, on their own gym''s case, naming a real colleague
-- of that same gym. The only thing wrong is that the named staff_id is not
-- the acting one.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000088'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000052'::uuid,
          '19000000-0000-4000-8000-000000000022'::uuid,
          'call', 'will_return')
$$, null::char(5), null,
  'scenario "Naming a colleague" — a front-desk session cannot log a follow-up under a colleague''s name, even a real colleague of the same gym holding a role that may itself write this table');

set local role postgres;

-- 4
select results_eq(
  $$
    select (select count(*)::int from public.follow_ups
             where case_id = '19000000-0000-4000-8000-000000000052'::uuid),
           (select status::text collate "default" from public.no_show_cases
             where id = '19000000-0000-4000-8000-000000000052'::uuid)
  $$,
  $$ values (0, 'open'::text) $$,
  'the misattributed follow-up left no row behind and the case untouched'
);

-- 5 — the session the spec singles out: app_role and tenant_id, deliberately
-- no staff_id claim at all. Constructed exactly as the fixture recipe names
-- it. There is nobody to record, so naming a real staff member of the gym
-- does not save the write — the claim carries no identity to compare it to.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000089'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000053'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'will_return')
$$, null::char(5), null,
  'scenario "A session with no staff identity" — a session carrying app_role and tenant_id but no staff_id claim (the shape app.custom_access_token_hook mints for a live impersonation, ADR-071) logs no follow-up at all, whoever it names as staff_id');

set local role postgres;

-- 6
select results_eq(
  $$
    select (select count(*)::int from public.follow_ups
             where case_id = '19000000-0000-4000-8000-000000000053'::uuid),
           (select status::text collate "default" from public.no_show_cases
             where id = '19000000-0000-4000-8000-000000000053'::uuid)
  $$,
  $$ values (0, 'open'::text) $$,
  'the claimless write left no row behind and the case untouched'
);


-- ---------------------------------------------------------------------------
-- Requirement: The contact log is append-only (7-15)
-- ---------------------------------------------------------------------------

create temp table f1_snapshot as
  select id, tenant_id, case_id, staff_id, channel, outcome, notes, next_action,
         next_follow_up_at, corrects_follow_up_id, created_at
    from public.follow_ups
   where id = '19000000-0000-4000-8000-000000000071'::uuid;

create temp table f_case1_snapshot as
  select id, tenant_id, case_id, staff_id, channel, outcome, notes, next_action,
         next_follow_up_at, corrects_follow_up_id, created_at
    from public.follow_ups
   where id = '19000000-0000-4000-8000-000000000072'::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 7
select lives_ok($$
  insert into public.follow_ups
    (id, tenant_id, case_id, staff_id, channel, outcome, corrects_follow_up_id)
  values ('19000000-0000-4000-8000-000000000082'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000054'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'no_response',
          '19000000-0000-4000-8000-000000000071'::uuid)
$$, 'scenario "Correcting a follow-up" — a new row naming corrects_follow_up_id, on the same case as the entry it corrects, is not refused');

set local role postgres;

-- 8 — the original is not merely unasserted-against, it is compared whole to
-- a snapshot taken before the correction was written.
select results_eq(
  $$
    select id, tenant_id, case_id, staff_id, channel, outcome, notes, next_action,
           next_follow_up_at, corrects_follow_up_id, created_at
      from public.follow_ups
     where id = '19000000-0000-4000-8000-000000000071'::uuid
  $$,
  $$ select * from f1_snapshot $$,
  'scenario "Correcting a follow-up" — the original row is byte-for-byte what it was before the correction, because nothing has update on follow_ups'
);

-- 9
select results_eq(
  $$
    select case_id, corrects_follow_up_id
      from public.follow_ups
     where id = '19000000-0000-4000-8000-000000000082'::uuid
  $$,
  $$ values ('19000000-0000-4000-8000-000000000054'::uuid,
             '19000000-0000-4000-8000-000000000071'::uuid) $$,
  'the correction landed, on the corrected entry''s own case, pointing at what it corrects'
);

-- 10 — the row named by corrects_follow_up_id is real, but it belongs to
-- case 055 and this insert is filed against case 056. The composite tenant
-- foreign key (ADR-052) is satisfied — both rows are tenant A — so if this is
-- refused, it is this requirement''s own rule and not a tenancy check.
--
-- Assertions 8 and 9 read state as postgres; this one writes, so the session
-- has to be handed back to the acting staff member first. Running this under
-- postgres is exactly the bug the coordinator found: row_security_active()
-- is false for postgres, the trusted-context carve-out applies, no rule in
-- this table fires for that session at all, and throws_ok reports "no
-- exception" for a reason that has nothing to do with whether the rule
-- exists.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

select throws_ok($$
  insert into public.follow_ups
    (id, tenant_id, case_id, staff_id, channel, outcome, corrects_follow_up_id)
  values ('19000000-0000-4000-8000-000000000083'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000056'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'no_response',
          '19000000-0000-4000-8000-000000000072'::uuid)
$$, null::char(5), null,
  'scenario "Correcting a follow-up on another case" — a correction pointing at case 055''s entry, filed against case 056, is not a correction and is refused');

set local role postgres;

-- 11 — the same whole-row comparison as assertion 8, against the row the
-- refused write targeted.
select results_eq(
  $$
    select id, tenant_id, case_id, staff_id, channel, outcome, notes, next_action,
           next_follow_up_at, corrects_follow_up_id, created_at
      from public.follow_ups
     where id = '19000000-0000-4000-8000-000000000072'::uuid
  $$,
  $$ select * from f_case1_snapshot $$,
  'the cross-case correction left case 055''s original row byte-for-byte what it was'
);

-- 12
select results_eq(
  $$ select count(*)::int from public.follow_ups
      where case_id = '19000000-0000-4000-8000-000000000056'::uuid $$,
  $$ values (0) $$,
  'and landed nothing at all under case 056 — a correction pointing at another case''s entry is not a correction'
);

-- 13/14/15 — authenticated holds select, insert on follow_ups and nothing
-- else (revoke all; grant select, insert — 20260906115156_retention.sql).
-- This is a privilege check, not a policy one: it is refused for want of
-- grant no matter which row or which tenant it targets.

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 13
select throws_ok($$
  update public.follow_ups set outcome = 'cancelled'
   where id = '19000000-0000-4000-8000-000000000074'::uuid
$$, null::char(5), null,
  'scenario "Editing the log" — an UPDATE on follow_ups is refused for want of privilege, not filtered by a policy to zero rows');

-- 14
select throws_ok($$
  delete from public.follow_ups
   where id = '19000000-0000-4000-8000-000000000074'::uuid
$$, null::char(5), null,
  'scenario "Editing the log" — a DELETE on follow_ups is refused for want of privilege too, asserted separately from the UPDATE case');

set local role postgres;

-- 15
select results_eq(
  $$ select count(*)::int from public.follow_ups where id = '19000000-0000-4000-8000-000000000074'::uuid
       and outcome = 'will_return'::public.follow_up_outcome $$,
  $$ values (1) $$,
  'the refused update and the refused delete both left the row exactly as it was'
);


-- ---------------------------------------------------------------------------
-- Requirement: Two staff cannot contact one case at the same instant (16-18)
--
-- One transaction cannot stage a real race (both reads passing before either
-- write), so this proves only what a single-connection harness can: that a
-- serialising mechanism exists at all, and that the concurrency rule does not
-- also forbid a case being contacted more than once over time. Case 057
-- already carries F_first, "contacted an hour ago" by its created_at.
-- ---------------------------------------------------------------------------

-- 16 — a catalogue assertion, and it says so: it proves a serialising lock is
-- TAKEN somewhere in the write path, not that it is taken on the right key,
-- and it accepts either an advisory transaction lock (visible in pg_locks for
-- this backend, still held because nothing here has committed) or an
-- explicit row lock inside a trigger function on follow_ups or on
-- no_show_cases (the contested row NSH-006 is actually about). It is
-- deliberately not narrower than that — which mechanism is the implementer's
-- call, and this assertion exists only to say some serialising mechanism, not
-- none, sits under the write.
select ok(
  exists (
    select 1 from pg_locks
     where pid = pg_backend_pid() and locktype = 'advisory'
  )
  or exists (
    select 1
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid in ('public.follow_ups'::regclass, 'public.no_show_cases'::regclass)
       and not t.tgisinternal
       and p.proname::text collate "default" <> 'touch_updated_at'
       and p.prosrc ~* '\mfor +(update|share|no +key +update|key +share)\M'
  ),
  'requirement "Two staff cannot contact one case at the same instant" — recording a follow-up takes a serialising lock (an advisory transaction lock, or an explicit row lock in a trigger on follow_ups or no_show_cases). A read-then-decide with no lock lets two staff both pass before either writes'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 17
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000084'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000057'::uuid,
          '19000000-0000-4000-8000-000000000022'::uuid,
          'whatsapp', 'no_response')
$$, 'scenario "Two follow-ups in sequence" — a second follow-up on a case that was contacted an hour ago succeeds: the rule is about concurrency, not about a case being contacted only once');

set local role postgres;

-- 18
select results_eq(
  $$ select count(*)::int from public.follow_ups
      where case_id = '19000000-0000-4000-8000-000000000057'::uuid $$,
  $$ values (2) $$,
  'both the hour-old follow-up and the new one are on the case''s log'
);


-- ---------------------------------------------------------------------------
-- Requirement: A case's status follows its contact history (19-24)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 19
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000085'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000058'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'no_response')
$$, 'scenario "A follow-up with no next action" — logging it against an open case is not refused');

set local role postgres;

-- 20
select results_eq(
  $$
    select status::text collate "default", next_follow_up_at
      from public.no_show_cases
     where id = '19000000-0000-4000-8000-000000000058'::uuid
  $$,
  $$ values ('contacted'::text, null::timestamptz) $$,
  'scenario "A follow-up with no next action" — the case moved to contacted and carries no next-follow-up instant'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 21
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, next_follow_up_at)
  values ('19000000-0000-4000-8000-000000000086'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-000000000059'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'timing_issue', '2026-10-01 09:00:00+05:30'::timestamptz)
$$, 'scenario "A follow-up with a next action" — logging it naming next_follow_up_at is not refused');

set local role postgres;

-- 22
select results_eq(
  $$
    select status::text collate "default", next_follow_up_at
      from public.no_show_cases
     where id = '19000000-0000-4000-8000-000000000059'::uuid
  $$,
  $$ values ('follow_up_due'::text, '2026-10-01 09:00:00+05:30'::timestamptz) $$,
  'scenario "A follow-up with a next action" — the case moved to follow_up_due and carries the named instant'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 23 — case 05a is already closed, with a closed_at of its own. Nothing else
-- about this write is wrong: the case is tenant A's, the staff_id is the
-- acting one.
select throws_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-000000000087'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-00000000005a'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'will_return')
$$, null::char(5), null,
  'scenario "A closed case" — logging a follow-up against an already-closed case is refused; the case is a finished record');

set local role postgres;

-- 24
select results_eq(
  $$
    select (select count(*)::int from public.follow_ups
             where case_id = '19000000-0000-4000-8000-00000000005a'::uuid),
           (select status::text collate "default" from public.no_show_cases
             where id = '19000000-0000-4000-8000-00000000005a'::uuid)
  $$,
  $$ values (0, 'closed'::text) $$,
  'the refused follow-up left the closed case exactly as it was, with no entry added to its log'
);


-- ---------------------------------------------------------------------------
-- Scenario: A correction does not re-decide the schedule (25-28)
--
-- Two cases, each brought to follow_up_due by an identical first follow-up
-- (same fixed next_follow_up_at, so a wrong implementation cannot pass by
-- coincidence of now()-derived timestamps). The two diverge in exactly one
-- respect after that: case 05e receives a CORRECTION of that first entry
-- (corrects_follow_up_id set, no next_follow_up_at of its own); case 05f
-- receives an ordinary SECOND follow-up (no corrects_follow_up_id, no
-- next_follow_up_at). Status derivation is not itself under test here — 19-22
-- already prove a follow-up naming next_follow_up_at produces follow_up_due
-- and one naming none produces contacted — so the setup step for each case
-- is a plain insert, not its own TAP assertion (ADR-069): asserting it here
-- too would just repeat 19-22 under a new number.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001'::uuid,
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- Setup — not asserted (see header note): both cases start identically, at
-- follow_up_due, with the same fixed instant.
insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, next_follow_up_at)
values ('19000000-0000-4000-8000-00000000008a'::uuid,
        '19000000-0000-4000-8000-000000000001'::uuid,
        '19000000-0000-4000-8000-00000000005e'::uuid,
        '19000000-0000-4000-8000-000000000021'::uuid,
        'call', 'timing_issue', '2026-10-10 09:00:00+05:30'::timestamptz);

insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, next_follow_up_at)
values ('19000000-0000-4000-8000-00000000008b'::uuid,
        '19000000-0000-4000-8000-000000000001'::uuid,
        '19000000-0000-4000-8000-00000000005f'::uuid,
        '19000000-0000-4000-8000-000000000021'::uuid,
        'call', 'timing_issue', '2026-10-10 09:00:00+05:30'::timestamptz);

-- 25 — the correction itself: naming corrects_follow_up_id, no next_follow_up_at
-- of its own, on the same case as the entry it corrects.
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome, corrects_follow_up_id)
  values ('19000000-0000-4000-8000-00000000008c'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-00000000005e'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'no_response',
          '19000000-0000-4000-8000-00000000008a'::uuid)
$$, 'scenario "A correction does not re-decide the schedule" — a correction of the entry that set follow_up_due, itself naming no next_follow_up_at, is not refused');

set local role postgres;

-- 26 — THE assertion that matters: status and next_follow_up_at are BOTH
-- exactly what they were before the correction. Checked together, in one
-- row, because nulling the date and changing the status are separate halves
-- of the same bug and either one alone would leave the other undetected.
select results_eq(
  $$
    select status::text collate "default", next_follow_up_at
      from public.no_show_cases
     where id = '19000000-0000-4000-8000-00000000005e'::uuid
  $$,
  $$ values ('follow_up_due'::text, '2026-10-10 09:00:00+05:30'::timestamptz) $$,
  'scenario "A correction does not re-decide the schedule" — after the correction, the case is STILL follow_up_due and STILL carries the ORIGINAL next_follow_up_at; a correction corrects the record, it does not make a new decision about the member'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001'::uuid,
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 27 — positive control, same starting state (follow_up_due) as case 05e,
-- but this is an ORDINARY follow-up (no corrects_follow_up_id), naming no
-- next_follow_up_at of its own — the shape this whole section exists to
-- distinguish from a correction.
select lives_ok($$
  insert into public.follow_ups (id, tenant_id, case_id, staff_id, channel, outcome)
  values ('19000000-0000-4000-8000-00000000008d'::uuid,
          '19000000-0000-4000-8000-000000000001'::uuid,
          '19000000-0000-4000-8000-00000000005f'::uuid,
          '19000000-0000-4000-8000-000000000021'::uuid,
          'call', 'no_response')
$$, 'positive control — a NON-correction follow-up naming no next_follow_up_at, on a case that was follow_up_due, is not refused');

set local role postgres;

-- 28 — the control MUST move: a fix that never re-derives status at all
-- would pass assertion 26 for the wrong reason (nothing ever changes
-- anything), and this is what rules that out. A scan that flags nobody, and
-- a follow-up rule that decides nothing, fail the same way.
select results_eq(
  $$
    select status::text collate "default", next_follow_up_at
      from public.no_show_cases
     where id = '19000000-0000-4000-8000-00000000005f'::uuid
  $$,
  $$ values ('contacted'::text, null::timestamptz) $$,
  'positive control — unlike the correction, the ordinary follow-up DOES re-decide the schedule: the case moves to contacted and next_follow_up_at is cleared, exactly as 19-20 already prove for a fresh case'
);


-- ---------------------------------------------------------------------------
-- Requirement: A case can be assigned, and assignment is not a decision about
-- the member (29-32)
--
-- follow_ups grants nothing here — this requirement is about
-- no_show_cases.assigned_to_staff_id, which authenticated already holds
-- update on (20260906115156_retention.sql), gated by the tenant policy and,
-- for the cross-gym scenario, by ADR-052's composite foreign key
-- (tenant_id, assigned_to_staff_id) references staff (tenant_id, id).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 29
select lives_ok($$
  update public.no_show_cases
     set assigned_to_staff_id = '19000000-0000-4000-8000-000000000023'::uuid
   where id = '19000000-0000-4000-8000-00000000005b'::uuid
$$, 'scenario "Assigning to a colleague" — assigning a case to another staff member of the same gym is not refused');

set local role postgres;

-- 30
select results_eq(
  $$ select assigned_to_staff_id from public.no_show_cases
      where id = '19000000-0000-4000-8000-00000000005b'::uuid $$,
  $$ values ('19000000-0000-4000-8000-000000000023'::uuid) $$,
  'the assignment landed'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '19000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '19000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 31
select throws_ok($$
  update public.no_show_cases
     set assigned_to_staff_id = '19000000-0000-4000-8000-000000000025'::uuid
   where id = '19000000-0000-4000-8000-00000000005c'::uuid
$$, null::char(5), null,
  'scenario "Assigning outside the gym" — assigning a tenant A case to a staff member of tenant B is refused');

set local role postgres;

-- 32
select results_eq(
  $$ select assigned_to_staff_id from public.no_show_cases
      where id = '19000000-0000-4000-8000-00000000005c'::uuid $$,
  $$ values (null::uuid) $$,
  'the cross-gym assignment left the case unassigned'
);


select * from finish();
rollback;
