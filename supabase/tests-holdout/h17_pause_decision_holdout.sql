-- h17_pause_decision_holdout — HOLDOUT pgTAP suite for Phase 3's pause-decision
-- capability.
--
-- Written blind from openspec/changes/phase-3-core-domain/specs/pause-decision/spec.md,
-- docs/security.md (impersonation) and docs/decisions.md ADR-066/ADR-067. The
-- author of this file has not read supabase/tests/17_pause_decision.sql, either
-- Phase 3 pause migration, or the body of app.enforce_pause_decision() in any
-- form — not the source, not prosrc, not even the trigger's event list, because
-- knowing which statements the guard fires on would tell me which of my
-- assertions are already answered and is precisely the knowledge that makes a
-- holdout worthless. Table shape, grants, policies, constraint names and enum
-- values were read from the catalogue, because a test must know what it writes
-- against.
--
-- WHAT THIS FILE IS FOR. The visible suite transcribes the spec requirement by
-- requirement. Duplicating that would buy nothing, so this file deliberately
-- spends its assertions elsewhere:
--
--   * THE SECOND STATEMENT. Every rule here is written about one write. A rule
--     that refuses an outcome in one statement very often permits the same
--     outcome in two — clear the decision, then re-make it; reassign the
--     requester, then approve; smuggle the approver in at insert time, then
--     stamp approved_at on its own. ADR-067's second defect is exactly this
--     shape, and it is unlikely to have been the last of it.
--   * THE COLUMNS THE RULE DOES NOT MENTION. `authenticated` holds `update` on
--     the whole table and the write policy is `is_front_office()` for ALL
--     commands, so a front desk can reach `membership_id`, `starts_on`,
--     `ends_on` and `rejected_at` on a row somebody else already approved. The
--     spec governs who may approve; it says nothing about what an approval,
--     once given, is an approval OF. A seven-day freeze whose `ends_on` is
--     afterwards moved out two years is money the gym stops collecting,
--     carrying a valid authorisation for something else entirely — the precise
--     harm the spec's Purpose names.
--   * THE CLAIM SHAPES THAT ARE NOT A STAFF MEMBER. Impersonation, a plain
--     super_admin, a member, a trainer, a staff id from another gym, and a
--     well-formed claim naming a staff row that does not exist.
--   * REFUSAL VERSUS NO-OP. An `update … where id = …` that matches zero rows
--     because a policy filtered it "succeeds" and changes nothing, while a
--     trigger raises. Both are correct refusals and the spec does not choose
--     between them, so almost every negative here asserts the ROW STATE
--     afterwards rather than the presence of an error. pg_temp.attempt() runs
--     the write and swallows any error precisely so the assertion that follows
--     is about the row and not about the mechanism.
--   * THE CARVE-OUT ITSELF. Two requirements exempt sessions "subject to row
--     security", for the seed and the fixtures. That is a boundary like any
--     other and it can be got wrong in both directions: too narrow and it
--     breaks `service_role` and the Edge Functions, too broad and a guard that
--     infers trust from a missing claim hands the exemption to any
--     `authenticated` session whose token happens not to carry that claim.
--     Both directions are probed, and so is the more basic question of what the
--     carve-out is keyed ON — the SESSION, which is what "subject to row
--     security" means, or the contents of the claims GUC, which a BYPASSRLS
--     session may carry for reasons having nothing to do with who it is.
--
-- ADR-050: the project permanently holds a seeded demo gym, and the visible
-- suite runs in the same job. Nothing here counts or lists a whole table —
-- every count and every set assertion is scoped to this file's own tenants, and
-- every uuid lives in the `170000ff-…` space so it cannot collide with the
-- visible suite's `17000000-…`.
--
-- ADR-030: one transaction, ending in ROLLBACK.

begin;

-- ADR-046: CI's session may be a NOINHERIT login role; the owner role, which
-- holds BYPASSRLS, is assumed explicitly rather than inherited.
set local role postgres;

select plan(47);

-- ---------------------------------------------------------------------------
-- pg_temp.attempt(): run a write, return 'ok' or the SQLSTATE, never abort.
--
-- Security invoker, so it executes with whatever role and claims are current.
-- Its return value is deliberately ignored by most callers: the question this
-- file asks after a refused write is "what does the row say now", not "did
-- Postgres raise". A policy-filtered update raises nothing and changes nothing;
-- a trigger raises; both are refusals and the spec picks neither.
--
-- CALL IT ONLY ONE OF TWO WAYS, and never as a bare top-level `select`:
--
--   do $do$ begin perform pg_temp.attempt($$ … $$); end $do$;   -- result discarded
--   select is(pg_temp.attempt($$ … $$), 'ok', '…');             -- result asserted
--
-- CI pipes psql in tuples-only unaligned mode straight into `prove`, so a bare
-- `select pg_temp.attempt(…)` prints its return value on a line of its own —
-- and when the write succeeds that value is the string `ok`, which is VALID
-- TAP. `prove` counts each one as an unnumbered extra test, and the run fails
-- with "tests out of sequence" against a plan that was perfectly correct. The
-- assertions are fine; the stream is carrying tests nobody wrote. Nothing in a
-- local `supabase db query` run can see this: it shows only the last result set,
-- and num_failed() counts failed assertions while knowing nothing about how
-- many lines were printed.
--
-- Prefer the asserting form wherever the write is MEANT to succeed — a setup
-- step that quietly fails is how a suite ends up proving something other than
-- what it says.
-- ---------------------------------------------------------------------------
create function pg_temp.attempt(sql text) returns text
language plpgsql as $fn$
begin
  execute sql;
  return 'ok';
exception when others then
  return sqlstate;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Fixtures. Two gyms whose configured approver roles DIFFER, and gym B's is not
-- the column default.
--
--   Gym A: pause_approver_role = 'gym_manager'  (which IS the default)
--   Gym B: pause_approver_role = 'front_desk'
--
-- An implementation that hardcodes 'gym_manager', or that reads the default
-- rather than the row, is right about gym A and wrong about gym B. A suite that
-- only ever fixtures one gym cannot tell those apart.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('170000ff-0000-4000-8000-00000000a001', 'Holdout Pause Gym A', 'HPD17A'),
       ('170000ff-0000-4000-8000-00000000b001', 'Holdout Pause Gym B', 'HPD17B');

insert into public.organization_settings (tenant_id, pause_approver_role)
values ('170000ff-0000-4000-8000-00000000a001', 'gym_manager'),
       ('170000ff-0000-4000-8000-00000000b001', 'front_desk');

insert into public.branches (id, tenant_id, name)
values ('170000ff-0000-4000-8000-00000000a011', '170000ff-0000-4000-8000-00000000a001', 'H17 Main A'),
       ('170000ff-0000-4000-8000-00000000b011', '170000ff-0000-4000-8000-00000000b001', 'H17 Main B');

-- Gym A staff. Three gym_managers, because the two-person rule and the
-- "already decided" rule both need a SECOND equally-qualified approver to be
-- meaningful — a suite with one manager cannot express "somebody who would have
-- been allowed, had the row still been pending".
insert into public.staff (id, tenant_id, branch_id, role, full_name)
values ('170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'gym_manager', 'H17 Manager A1 (requester)'),
       ('170000ff-0000-4000-8000-00000000a022', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'gym_manager', 'H17 Manager A2 (approver)'),
       ('170000ff-0000-4000-8000-00000000a023', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'gym_manager', 'H17 Manager A3 (second approver)'),
       ('170000ff-0000-4000-8000-00000000a024', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'front_desk', 'H17 Front Desk A'),
       ('170000ff-0000-4000-8000-00000000a025', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'gym_owner', 'H17 Owner A'),
       ('170000ff-0000-4000-8000-00000000a026', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'trainer', 'H17 Trainer A'),
       ('170000ff-0000-4000-8000-00000000b021', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b011', 'front_desk', 'H17 Front Desk B (approver)'),
       ('170000ff-0000-4000-8000-00000000b022', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b011', 'gym_manager', 'H17 Manager B');

insert into public.plans (id, tenant_id, name, duration_days, price_paise)
values ('170000ff-0000-4000-8000-00000000a031', '170000ff-0000-4000-8000-00000000a001',
        'H17 Plan A', 30, 100000),
       ('170000ff-0000-4000-8000-00000000b031', '170000ff-0000-4000-8000-00000000b001',
        'H17 Plan B', 30, 100000);

-- Two members in gym A. The second exists only so that "repoint an approved
-- pause at a different membership" is a question this file can ask.
insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('170000ff-0000-4000-8000-00000000a041', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'H17 Member A1', '+919700170001'),
       ('170000ff-0000-4000-8000-00000000a042', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a011', 'H17 Member A2', '+919700170002'),
       ('170000ff-0000-4000-8000-00000000b041', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b011', 'H17 Member B1', '+919700170003');

insert into public.memberships (id, tenant_id, member_id, plan_id, price_paise)
values ('170000ff-0000-4000-8000-00000000a051', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a041', '170000ff-0000-4000-8000-00000000a031', 100000),
       ('170000ff-0000-4000-8000-00000000a052', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a042', '170000ff-0000-4000-8000-00000000a031', 100000),
       ('170000ff-0000-4000-8000-00000000b051', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b041', '170000ff-0000-4000-8000-00000000b031', 100000);

-- Pending pauses, one per attack, so that no assertion's fixture is another
-- assertion's wreckage. All requested by Manager A1.
insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
select id, '170000ff-0000-4000-8000-00000000a001', '170000ff-0000-4000-8000-00000000a051',
       date '2026-10-01', date '2026-10-08', 'H17 pending freeze',
       '170000ff-0000-4000-8000-00000000a021'
from (values
  ('170000ff-0000-4000-8000-000000000101'::uuid), -- configured role approves (happy path)
  ('170000ff-0000-4000-8000-000000000102'::uuid), -- front desk approves
  ('170000ff-0000-4000-8000-000000000103'::uuid), -- requester approves own
  ('170000ff-0000-4000-8000-000000000104'::uuid), -- approval attributed to a colleague
  ('170000ff-0000-4000-8000-000000000105'::uuid), -- two-move: reassign requester, then approve
  ('170000ff-0000-4000-8000-000000000106'::uuid), -- front desk rejects
  ('170000ff-0000-4000-8000-000000000107'::uuid), -- requester rejects own
  ('170000ff-0000-4000-8000-000000000108'::uuid), -- trainer rejects
  ('170000ff-0000-4000-8000-000000000109'::uuid), -- impersonator approves
  ('170000ff-0000-4000-8000-00000000010a'::uuid), -- impersonator rejects
  ('170000ff-0000-4000-8000-00000000010b'::uuid), -- plain super_admin approves
  ('170000ff-0000-4000-8000-00000000010c'::uuid), -- member token
  ('170000ff-0000-4000-8000-00000000010d'::uuid), -- claim names a staff row that does not exist
  ('170000ff-0000-4000-8000-00000000010e'::uuid), -- token with no `sub` approves
  ('170000ff-0000-4000-8000-00000000010f'::uuid), -- reassign requester, alone
  ('170000ff-0000-4000-8000-000000000120'::uuid), -- reject AND reassign requester, one statement
  ('170000ff-0000-4000-8000-000000000121'::uuid), -- edit dates on a pending pause (control)
  ('170000ff-0000-4000-8000-000000000122'::uuid), -- gym owner approves (not A's configured role)
  ('170000ff-0000-4000-8000-000000000123'::uuid), -- approve-and-amend, one statement
  ('170000ff-0000-4000-8000-000000000124'::uuid)  -- reject-and-amend, one statement
) as t(id);

-- Pause in gym B, whose configured approver is front_desk.
insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
values ('170000ff-0000-4000-8000-0000000001b1', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b051', date '2026-10-01', date '2026-10-08',
        'H17 gym B freeze', '170000ff-0000-4000-8000-00000000b022'),
       ('170000ff-0000-4000-8000-0000000001b2', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b051', date '2026-11-01', date '2026-11-08',
        'H17 gym B freeze 2', '170000ff-0000-4000-8000-00000000b021'),
       ('170000ff-0000-4000-8000-0000000001b3', '170000ff-0000-4000-8000-00000000b001',
        '170000ff-0000-4000-8000-00000000b051', date '2026-12-01', date '2026-12-08',
        'H17 gym B freeze 3', '170000ff-0000-4000-8000-00000000b022');

-- Already-approved pauses, written by postgres — which the spec exempts, and
-- which is the only way this file can obtain a legitimately-decided row to
-- attack without first depending on the very rule under test.
--
-- Each is requested by Manager A1 and approved by Manager A2: two different
-- people, so the outcome-level invariant at the end of this file has teeth.
insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason,
   requested_by_staff_id, approved_by_staff_id, approved_at)
select id, '170000ff-0000-4000-8000-00000000a001', '170000ff-0000-4000-8000-00000000a051',
       date '2026-10-01', date '2026-10-08', 'H17 approved freeze',
       '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
       timestamptz '2026-09-01 10:00:00+05:30'
from (values
  ('170000ff-0000-4000-8000-000000000110'::uuid), -- clear the decision
  ('170000ff-0000-4000-8000-000000000111'::uuid), -- reassign requester after approval
  ('170000ff-0000-4000-8000-000000000112'::uuid), -- repoint membership_id
  ('170000ff-0000-4000-8000-000000000113'::uuid), -- extend ends_on
  ('170000ff-0000-4000-8000-000000000114'::uuid), -- flip approval to rejection
  ('170000ff-0000-4000-8000-000000000115'::uuid), -- a second qualified approver overwrites
  ('170000ff-0000-4000-8000-000000000116'::uuid), -- impersonator rewrites the decision
  ('170000ff-0000-4000-8000-000000000117'::uuid)  -- dedicated target for the generic column sweep
) as t(id);

-- A decided-by-REJECTION row, dedicated and separate from the approved fixtures
-- above. "A decided pause stays decided" is stated for the freeze in general,
-- but every worked scenario in the spec is an approval — this row is what lets
-- the generic sweep below ask whether a REJECTED pause is frozen too, or
-- whether the guard was written watching only approved_at.
insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason,
   requested_by_staff_id, rejected_at)
values ('170000ff-0000-4000-8000-000000000118', '170000ff-0000-4000-8000-00000000a001',
        '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
        'H17 rejected freeze, sweep target', '170000ff-0000-4000-8000-00000000a021',
        timestamptz '2026-09-01 10:00:00+05:30');

-- ---------------------------------------------------------------------------
-- 1-4. THE GYM DECIDES WHICH ROLE APPROVES — and it is the gym's row that
-- decides, not a constant and not the column default.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000101'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000101'),
  '170000ff-0000-4000-8000-00000000a022'::uuid,
  'The configured approver role approves, and the approval is recorded — the rule refuses the wrong people without refusing the right one');

-- Front desk is front-office, so row security admits the row and lets the
-- statement reach the rule. Anything that refuses this is refusing it on the
-- role, which is what the spec asks for.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a024',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000102'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null and approved_by_staff_id is null
     from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000102'),
  'A staff role that is not the gym''s configured approver leaves the pause pending — and leaves no approver recorded either');

-- Gym B's configured approver is front_desk. This is the assertion a suite that
-- fixtures a single gym cannot make.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000b001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000b021')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000b021',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-0000000001b1'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-0000000001b1'),
  '170000ff-0000-4000-8000-00000000b021'::uuid,
  'Gym B''s front desk approves in gym B, because front_desk is what gym B configured — the role is read per gym, not hardcoded');

-- gym_manager is the COLUMN DEFAULT for pause_approver_role, and it is gym A's
-- value. An implementation that reads the default instead of gym B's row, or
-- that hardcodes the common case, passes every gym A assertion and fails here.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000b001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000b022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000b022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-0000000001b2'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-0000000001b2'),
  'A gym_manager cannot approve in a gym that configured front_desk — the enum''s default value is not every gym''s answer');

-- ---------------------------------------------------------------------------
-- 5-7. WHO IS RECORDED, AND WHO MAY NOT DECIDE ALONE.
-- ---------------------------------------------------------------------------

-- Manager A2 approves but names Manager A3 — who holds the configured role, so
-- the ROLE test passes and only the attribution rule can refuse this.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a023',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000104'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null and approved_by_staff_id is null
     from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000104'),
  'An approval cannot be attributed to a colleague, even one who could lawfully have given it — the recorded approver is the acting staff member or nobody');

-- The requester holds the configured role. Only the two-person rule stands
-- between them and their own freeze.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a021')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a021',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000103'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000103'),
  'The staff member who requested a freeze cannot grant it, though their role would otherwise allow it');

-- The gym owner is the most senior role in the gym and is NOT gym A's
-- configured approver. "Senior enough" is not the test the spec states.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_owner',
                    'staff_id', '170000ff-0000-4000-8000-00000000a025')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a025',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000122'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000122'),
  'The gym owner is not gym A''s configured approver and so may not approve — the rule is equality with a configured role, not a seniority ordering');

-- ---------------------------------------------------------------------------
-- 8-11. `requested_by_staff_id` IS FIXED — in every context, not only while the
-- statement happens to be an approval.
--
-- This is the file's central bet. The spec argues that requester-immutability
-- is what makes the two-person rule a control at all, and its two scenarios are
-- both about a PENDING pause. If the immutability check is written inside the
-- branch that handles "is this an approval?" — which is how every other rule
-- here is necessarily written, and how ADR-067 says this guard was already
-- structured once — then it is absent from a rejection and absent from an
-- already-decided row, and the permanent record of who asked for a freeze can
-- be rewritten by routing around the approval.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

-- (a) On its own, on a pending pause. The spec states this one.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set requested_by_staff_id = '170000ff-0000-4000-8000-00000000a023'
   where id = '170000ff-0000-4000-8000-00000000010f'$$); end $do$;

-- (b) Carried by a REJECTION — which the spec says is ungoverned, needing no
--     role and no second person. Ungoverned as to the decision is not
--     ungoverned as to the record of who asked.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now(),
         requested_by_staff_id = '170000ff-0000-4000-8000-00000000a023'
   where id = '170000ff-0000-4000-8000-000000000120'$$); end $do$;

-- (c) On a pause that is ALREADY APPROVED — where "a decided pause stays
--     decided" makes the approval rules stop applying, and stopping is exactly
--     what ADR-067 warns is read as permission.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set requested_by_staff_id = '170000ff-0000-4000-8000-00000000a023'
   where id = '170000ff-0000-4000-8000-000000000111'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select requested_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010f'),
  '170000ff-0000-4000-8000-00000000a021'::uuid,
  'The recorded requester of a pending pause cannot be reassigned on its own');

select is(
  (select requested_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000120'),
  '170000ff-0000-4000-8000-00000000a021'::uuid,
  'The recorded requester cannot be reassigned by hiding the reassignment inside a rejection — a statement the approval rules deliberately do not govern');

select is(
  (select requested_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000111'),
  '170000ff-0000-4000-8000-00000000a021'::uuid,
  'The recorded requester of an ALREADY-APPROVED pause cannot be reassigned — "the approval rules no longer apply" must not mean "this row is now editable"');

-- (d) The whole point of (a): the spec's single-statement scenario, taken in
--     two moves by the requester themself. Move one launders the record, move
--     two collects the freeze. If either move is refused the outcome is safe;
--     the assertion is on the outcome, not on which move failed.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a021')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set requested_by_staff_id = '170000ff-0000-4000-8000-00000000a023'
   where id = '170000ff-0000-4000-8000-000000000105'$$); end $do$;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a021',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000105'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000105'),
  'Self-approval reached in two statements is still self-approval: reassigning the requester first must not open the freeze the two-person rule closed');

-- ---------------------------------------------------------------------------
-- 12-15. THE COLUMNS THE RULE DOES NOT MENTION.
--
-- The spec governs the transition into approved. It says nothing about what an
-- approval is an approval OF. `authenticated` holds `update` on the table and
-- the write policy is `is_front_office()` for ALL commands, so every one of
-- these statements reaches the row.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

-- Move an approved freeze onto a DIFFERENT member's membership. Manager A2's
-- authorisation, given for member A1, now vouches for member A2's freeze.
-- Composite keys (ADR-052) permit this: both memberships are in tenant A.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set membership_id = '170000ff-0000-4000-8000-00000000a052'
   where id = '170000ff-0000-4000-8000-000000000112'$$); end $do$;

-- Stretch an approved seven-day freeze to two years. Nothing about the approval
-- record changes; the money the gym does not collect changes by a hundredfold.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set ends_on = date '2028-10-08'
   where id = '170000ff-0000-4000-8000-000000000113'$$); end $do$;

-- Flip an approval into a rejection. Setting rejected_at alone would hit
-- membership_pauses_not_approved_and_rejected_chk, so this clears approved_at
-- in the same statement — one write that changes a decision by a route neither
-- the approval rules nor the rejection rules were written about.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_at = null, approved_by_staff_id = null, rejected_at = now()
   where id = '170000ff-0000-4000-8000-000000000114'$$); end $do$;

-- Control. A PENDING pause is still being negotiated and no rule freezes its
-- dates. If this is refused, the implementation has over-enforced — it is
-- protecting a decision that has not been made.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set starts_on = date '2026-10-05',
         ends_on = date '2026-10-19',
         reason = 'H17 amended before any decision'
   where id = '170000ff-0000-4000-8000-000000000121'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select membership_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000112'),
  '170000ff-0000-4000-8000-00000000a051'::uuid,
  'An approved pause cannot be repointed at another member''s membership — an authorisation is an authorisation of something, and moving what it covers forges it as surely as rewriting who gave it');

select is(
  (select ends_on from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000113'),
  date '2026-10-08',
  'An approved pause cannot have its end date extended — the freeze the approver granted is the freeze the gym is bound by');

select ok(
  (select approved_at is not null and rejected_at is null
     and approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022'::uuid
     from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000114'),
  'An approval cannot be flipped into a rejection: clearing approved_at in the same statement that sets rejected_at is still re-deciding a decided pause');

select is(
  (select ends_on from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000121'),
  date '2026-10-19',
  'A PENDING pause may still be amended — the rule protects decisions, and refusing this would be protecting one that was never made');

-- ---------------------------------------------------------------------------
-- 16-17. A DECIDED PAUSE STAYS DECIDED — including against being UN-decided.
--
-- The spec's scenario is a second approver overwriting the first. The cheaper
-- attack is to clear the decision, which turns a governed row into a pending
-- one, after which every rule here applies to a row that has already served its
-- purpose. ADR-067's rule — falling out of a branch is a decision to permit —
-- predicts a guard written around `new.approved_at is not null` never looks at
-- a statement that sets it back to null.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_at = null, approved_by_staff_id = null
   where id = '170000ff-0000-4000-8000-000000000110'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000110'),
  '170000ff-0000-4000-8000-00000000a022'::uuid,
  'A decided pause cannot be UN-decided: clearing approved_at would launder a governed row back into a pending one, and every rule here is about the transition into approved');

-- Manager A3 holds the configured role and did not request this pause, so they
-- would have been a lawful approver had it still been pending. The only thing
-- that may refuse them is that the decision has already been made.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a023')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a023',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000115'$$); end $do$;

reset role;
set local role postgres;

select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000115'),
  '170000ff-0000-4000-8000-00000000a022'::uuid,
  'A second, equally-qualified approver cannot overwrite the first — the record of who authorised the money must not become the record of whoever wrote last');

-- ---------------------------------------------------------------------------
-- 18-24. THE CLAIM SHAPES THAT ARE NOT A STAFF MEMBER.
--
-- is_front_office() reads app_role out of the claim and nothing else, so an
-- impersonating token — app_role 'gym_owner', the target gym's tenant_id, and
-- deliberately NO staff_id — passes the write policy while carrying no staff
-- identity at all. docs/security.md says such a token has the gym's reach and
-- not more; approving a freeze is more.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_owner',
                    'impersonation_session_id', gen_random_uuid())::text, true);
set local role authenticated;

-- Approving. The recorded approver has to be SOME staff row to satisfy the
-- composite key, so the impersonator names one — which is the whole problem:
-- the session has no identity of its own to be checked against.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000109'$$); end $do$;

-- Rewriting a decision already made.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a023'
   where id = '170000ff-0000-4000-8000-000000000116'$$); end $do$;

-- Rejecting. The spec's requirement says "record or alter a DECISION", and a
-- rejection is a decision; its two scenarios only name approvals. Asserted as
-- a refusal because the requirement's words are broader than its examples.
do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '170000ff-0000-4000-8000-00000000010a'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000109'),
  'An impersonating support session cannot approve a freeze — it carries a gym role and no staff identity, and impersonation is meant to be the most constrained path, not the least');

select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000116'),
  '170000ff-0000-4000-8000-00000000a022'::uuid,
  'An impersonating support session cannot rewrite a decision already recorded');

select ok(
  (select rejected_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010a'),
  'An impersonating support session cannot record a rejection either — refusing a freeze is still deciding it, and the session still cannot say who decided');

-- A plain super_admin. membership_pauses_platform_write is
-- current_app_role() = 'super_admin' for ALL commands, so this token reaches
-- every row in every tenant, and it carries no staff_id.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-00000000010b'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010b'),
  'A platform super admin cannot approve a gym''s freeze: the platform write policy reaches the row, and having no staff identity is exactly why reaching it is not enough');

-- A member token. Not front-office, so row security filters the row before any
-- rule runs and the update matches nothing. That is a correct refusal and this
-- assertion exists to prove the row is untouched, not that an error was raised.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'member',
                    'member_id', '170000ff-0000-4000-8000-00000000a041')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-00000000010c'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010c'),
  'A member''s own token cannot approve their freeze — the update matches zero rows, which is a refusal with no error, and the row proves it');

-- A trainer. Staff, in the gym, and not front-office: the role matrix refuses
-- the write, so a rejection the spec calls ungoverned is still not theirs.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'trainer',
                    'staff_id', '170000ff-0000-4000-8000-00000000a026')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '170000ff-0000-4000-8000-000000000108'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select rejected_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000108'),
  'A trainer cannot reject a pause: "any staff member may reject" is bounded by who may write the table at all, and the role matrix answers that first');

-- A well-formed claim naming a staff row that does not exist. Every claim is
-- present and plausible; only the lookup fails. A guard that resolves the
-- acting staff member, finds nothing, and falls out of its branch has just
-- authorised an anonymous approval — ADR-067's second shape, reached by a
-- different door.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-0000000000ff')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-00000000010d'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010d'),
  'A claim naming a staff row that does not exist approves nothing — "I could not find who you are" is not "you are whoever the row says"');

-- ---------------------------------------------------------------------------
-- 25-26. REJECTION IS GENUINELY UNGOVERNED. Two controls against
-- over-enforcement: a rule that refuses everything passes every negative
-- assertion above and is still wrong.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '170000ff-0000-4000-8000-000000000106'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select rejected_at is not null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000106'),
  'The front desk may reject although it may not approve — refusing a freeze costs the gym nothing and needs no configured role');

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a021')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '170000ff-0000-4000-8000-000000000107'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select rejected_at is not null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000107'),
  'The requester may withdraw their own request by rejecting it — the two-person rule guards the grant, not the refusal');

-- ---------------------------------------------------------------------------
-- 27. ACROSS GYMS. Gym A's configured approver, holding gym B's tenant_id.
-- is_front_office() reads only app_role, so the claim passes the write gate and
-- the tenant term matches; the acting staff row belongs to another gym.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000b001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-0000000001b3'$$); end $do$;

reset role;
set local role postgres;

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-0000000001b3'),
  'Gym A''s manager cannot approve gym B''s freeze — by the composite key or by the rule, whichever reaches it first, but the pause stays pending either way');

-- ---------------------------------------------------------------------------
-- 28-33. INSERT, AND THE "SUBJECT TO ROW SECURITY" CARVE-OUT.
--
-- Two requirements exempt sessions that row security does not apply to, so the
-- seed and the fixtures keep working. That exemption is a boundary, and a
-- boundary can be drawn wrong in both directions:
--
--   too narrow — a guard keyed on `current_user = 'postgres'` refuses
--                service_role, which is the Edge Functions' role and has
--                BYPASSRLS just as postgres does;
--   too broad  — a guard that infers "trusted" from a null auth.uid(), or from
--                the absence of claims it happens to look for, hands the
--                exemption to any `authenticated` session whose token carries
--                no `sub`. is_front_office() reads app_role alone, so such a
--                token still passes the write policy.
--
-- Both directions are probed. row_security_active() is the question these
-- rules actually mean to ask; anything else is an approximation with a gap.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

-- Born approved: naming a colleague as requester and itself as approver, so
-- every rule above would have been satisfied had it been an update.
do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id, approved_at)
  values ('170000ff-0000-4000-8000-000000000131', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 born approved by a staff session',
          '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
          now())$$); end $do$;

-- Born REJECTED. The spec now names rejected_at explicitly alongside
-- approved_at: "a pause arrives pending or it does not arrive" is the rule and
-- half of it used to not be enforced. requested_by_staff_id is deliberately
-- the ACTOR of this very insert (a022, the session's own claim), not a021 as
-- the earlier fixtures in this file use — a born-rejected row naming a
-- colleague as requester would be refused for two reasons at once, and this
-- assertion exists to isolate the rejected-at-birth rule alone.
do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, rejected_at)
  values ('170000ff-0000-4000-8000-000000000135', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 born rejected', '170000ff-0000-4000-8000-00000000a022', now())$$); end $do$;

-- Half born. approved_by_staff_id is set at insert — a column no requirement
-- forbids on insert, because the spec's reasoning is that insert-time rules are
-- vacuous — and approved_at is stamped afterwards, on its own, by the same
-- person. The approver was never checked at insert and, at update, is not being
-- changed. This is the born-approved defect taken in two moves.
-- This insert is asserted rather than discarded, and the reason is worth
-- stating: the assertion below passes if EITHER move was refused, so a setup
-- write that quietly failed would make it green for a reason that has nothing
-- to do with what it claims. Naming the expected outcome here is what stops
-- that. It is also a claim in its own right — no requirement forbids recording
-- a proposed approver on an undecided pause, only arriving already decided.
select is(pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id)
  values ('170000ff-0000-4000-8000-000000000130', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 half born', '170000ff-0000-4000-8000-00000000a022',
          '170000ff-0000-4000-8000-00000000a022')$$),
  'ok',
  'A pause may be created naming a proposed approver while still undecided — only arriving already DECIDED is refused, so the next assertion is about the update and not about this insert having failed');

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_at = now()
   where id = '170000ff-0000-4000-8000-000000000130'$$); end $do$;

reset role;
set local role postgres;

select is_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-000000000131'$$,
  'A session subject to row security cannot insert a pause that is already approved — a row that arrives at the destination was never governed on the way');

select is_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-000000000135'$$,
  'A pause may NOT be born rejected either, now that the spec names rejected_at alongside approved_at — a born-rejected row would permanently record a refusal against a request nobody made, with no way to undo it. (Requester was the actor of the insert itself, so only this rule, not requester-immutability, can be what refuses it.)');

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-000000000130')
    is not false,
  'Self-approval assembled across an insert and an update is still self-approval — naming yourself approver where no rule looks, then stamping approved_at where the rule sees nothing change');

-- Direction one: an `authenticated` session whose token carries no `sub`, so
-- auth.uid() is null. It is still fully subject to row security, and
-- is_front_office() still passes it. Nothing about it is trusted.
--
-- Both claims below are IDENTICAL to a session tested earlier except for the
-- missing `sub`, so that a failure here isolates the inference rather than
-- restating a defect already named:
--   the insert mirrors assertion 29's session exactly (gym_manager, staff_id
--   Manager A2), so a failure here is about `sub` alone;
--   the update mirrors assertion 2's session exactly (front_desk, staff_id
--   Front Desk A), which assertion 2 has already established is refused when
--   the same token carries a `sub`.
select set_config('request.jwt.claims',
  json_build_object('role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id, approved_at)
  values ('170000ff-0000-4000-8000-000000000134', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 born approved, no sub claim',
          '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
          now())$$); end $do$;

-- And on the update path. front_desk is not gym A's configured approver, which
-- assertion 2 proved is refused for exactly this staff member — the only
-- difference here is that the token carries no `sub`.
select set_config('request.jwt.claims',
  json_build_object('role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a024',
         approved_at = now()
   where id = '170000ff-0000-4000-8000-00000000010e'$$); end $do$;

reset role;
set local role postgres;

select is_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-000000000134'$$,
  'A token carrying no `sub` is not the seed: a null auth.uid() means row security still applies and nobody is identified, which is the opposite of trusted');

select ok(
  (select approved_at is null from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000010e'),
  'A token with a staff_id but no `sub` is still governed on the update path — assertion 2 refused this exact staff member, and dropping `sub` must not be a way to look like the seed');

-- Direction two: the trusted contexts, and the question of what actually makes
-- them trusted.
--
-- "Subject to row security" is a property of the SESSION, not of the claims
-- GUC. postgres and service_role hold BYPASSRLS; no policy on this table is
-- consulted for them whatever `request.jwt.claims` happens to contain. And it
-- very often contains something: PostgREST sets that GUC from the bearer token
-- on every request including a service_role one, and every pgTAP file in this
-- repository — this one included — sets claims to act as a gym user and then
-- returns to postgres to write more fixtures WITHOUT clearing them. A carve-out
-- that asks "is a staff_id claim present" instead of "is this session subject
-- to row security" is therefore not exempting the seed and the fixtures at all;
-- it is exempting whichever of them happen to have an empty GUC at the moment
-- they write.
--
-- So the claims left over from the block above are deliberately NOT cleared for
-- the next two assertions. That is not contamination — it is the state the
-- exempted callers are genuinely in.

-- Still postgres, claims still set to the front-desk session above.
select lives_ok(
  $$insert into public.membership_pauses
      (id, tenant_id, membership_id, starts_on, ends_on, reason,
       requested_by_staff_id, approved_by_staff_id, approved_at)
    values ('170000ff-0000-4000-8000-000000000136', '170000ff-0000-4000-8000-00000000a001',
            '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
            'H17 born approved by postgres with claims still set',
            '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
            now())$$,
  'postgres writes an already-approved pause while a claims GUC is still set — row security does not apply to it, so a leftover claim cannot make it a governed session, and every fixture file in this suite depends on that');

set local role service_role;

do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id, approved_at)
  values ('170000ff-0000-4000-8000-000000000133', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 born approved by service_role',
          '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
          now())$$); end $do$;

reset role;
set local role postgres;

select isnt_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-000000000133'$$,
  'service_role may insert an already-approved pause — it holds BYPASSRLS exactly as postgres does, and PostgREST hands it a populated claims GUC on every request, which is the normal case for an Edge Function and not an edge one');

-- And the plainest form: postgres with no claims at all, which is the seed
-- itself. If even this were refused, the requirement's own carve-out would be
-- unimplemented and `seed.sql` would not run.
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.membership_pauses
      (id, tenant_id, membership_id, starts_on, ends_on, reason,
       requested_by_staff_id, approved_by_staff_id, approved_at)
    values ('170000ff-0000-4000-8000-000000000132', '170000ff-0000-4000-8000-00000000a001',
            '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
            'H17 born approved by postgres',
            '170000ff-0000-4000-8000-00000000a021', '170000ff-0000-4000-8000-00000000a022',
            now())$$,
  'The seed still creates already-approved pauses — row security does not apply to it, and imposing this rule there protects nothing a policy is not already protecting');

-- ---------------------------------------------------------------------------
-- 37-40. THE NEW INSERT-TIME RULE, ISOLATED FROM THE BORN-DECIDED RULE.
--
-- ADR-070's own finding: immutability-on-UPDATE was defeated by insert-then-
-- approve, because INSERT is where requested_by_staff_id first enters and was
-- still whatever the caller typed. These four probe the insert itself, on a
-- PENDING pause, so no other rule (born-decided, self-approval) can be what
-- refuses them — a clean read on whether this specific rule exists.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

-- (a) A pending pause naming a COLLEAGUE as requester. Nothing about this row
--     is decided, so only "the requester is the acting staff member at insert"
--     can refuse it.
do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values ('170000ff-0000-4000-8000-000000000119', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 insert naming a colleague as requester',
          '170000ff-0000-4000-8000-00000000a021')$$); end $do$;

-- (b) A pending pause naming NOBODY — requested_by_staff_id left null. The
--     column is nullable, so nothing but this rule stands between a caller and
--     a freeze nobody is recorded as having asked for.
do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason)
  values ('170000ff-0000-4000-8000-00000000011a', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 insert naming nobody as requester')$$); end $do$;

-- (c) Positive control: the acting session names ITSELF. If this is refused
--     too, the rule has over-enforced and the two negatives above are not
--     evidence of anything.
do $do$ begin perform pg_temp.attempt($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id)
  values ('170000ff-0000-4000-8000-00000000011b', '170000ff-0000-4000-8000-00000000a001',
          '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
          'H17 insert naming the acting session as requester',
          '170000ff-0000-4000-8000-00000000a024')$$); end $do$;

reset role;
set local role postgres;

select is_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-000000000119'$$,
  'A pending pause cannot be created naming a colleague as requester — the acting staff member at INSERT is the only legitimate requester, exactly as ADR-070 argues, isolated here from the born-decided rule by leaving the row undecided');

select is_empty(
  $$select 1 from public.membership_pauses
     where id = '170000ff-0000-4000-8000-00000000011a'$$,
  'A pending pause cannot be created naming nobody as requester — a nullable column is not an escape hatch from the same rule');

select is(
  (select requested_by_staff_id from public.membership_pauses
    where id = '170000ff-0000-4000-8000-00000000011b'),
  '170000ff-0000-4000-8000-00000000a024'::uuid,
  'A staff member may still open a pause naming themselves as requester — the insert-time rule is not a ban on inserting, only on inserting a false record');

-- (d) The seed's own carve-out, now for the new rule: a trusted context (no
--     claims at all, the seed's own shape) inserting a REJECTED pause naming a
--     requester who never touched this session. If this rule is keyed on
--     row_security_active() like every other rule in this file ought to be, it
--     does not apply here at all.
select set_config('request.jwt.claims', '', true);

select lives_ok(
  $$insert into public.membership_pauses
      (id, tenant_id, membership_id, starts_on, ends_on, reason,
       requested_by_staff_id, rejected_at)
    values ('170000ff-0000-4000-8000-00000000011c', '170000ff-0000-4000-8000-00000000a001',
            '170000ff-0000-4000-8000-00000000a051', date '2026-10-01', date '2026-10-08',
            'H17 seed inserts a rejected pause naming whoever it likes',
            '170000ff-0000-4000-8000-00000000a021', now())$$,
  'The seed is exempt from BOTH new rules at once: an already-rejected pause naming a requester the session never was — if either carve-out is keyed on the claim rather than row_security_active(), this is where a leftover or absent claim would show it');

-- ---------------------------------------------------------------------------
-- 41-42. THE GENERIC COLUMN SWEEP.
--
-- "Every column except X" is a claim about a SET. A hand-typed list of frozen
-- columns is exactly the shape that was wrong twice already (ADR-070: id and
-- created_at, both times). pg_temp.frozen_probe() enumerates
-- information_schema.columns itself, so a column added tomorrow is swept in
-- without this file being edited, and perturbs each with a value chosen to be
-- valid if no freeze rule existed — an FK column gets a real alternate row, not
-- a random uuid — so a refusal here is attributable to the freeze rule and not
-- to an incidental foreign-key or check violation.
--
-- Run twice: once against an APPROVED row, once against a REJECTED one. The
-- spec's own worked examples are all approvals; running it against a rejected
-- row is what asks whether "a decided pause" was ever meant to include one.
-- approved_at and rejected_at cannot both be probed on the same row — Phase
-- 1's own CHECK constraint refuses that regardless of any freeze rule — so
-- each run excludes whichever of the pair is not already set on that row.
-- ---------------------------------------------------------------------------

create function pg_temp.frozen_probe(
  p_table text, p_row_id uuid, p_excluded text[], p_fk_overrides jsonb default '{}'::jsonb
) returns text[] language plpgsql as $fn$
declare
  before_row jsonb;
  after_row jsonb;
  col record;
  new_val text;
  leaked text[] := '{}';
  id_survived boolean;
begin
  execute format('select to_jsonb(t) from public.%I t where id = %L', p_table, p_row_id)
    into before_row;

  -- id is tested LAST and separately (below), never inside this loop: if id
  -- itself is not frozen and leaks first, every later UPDATE in this loop is
  -- still keyed `where id = p_row_id` against a row that has already moved,
  -- so it would silently match zero rows and every remaining column would
  -- misreport as leaked too. Testing id last, by existence rather than by
  -- value-diff, keeps the per-column results below trustworthy regardless of
  -- what id does.
  for col in
    select c.column_name, c.data_type
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = p_table
       and c.column_name <> all(p_excluded)
       and c.column_name <> 'id'
     order by c.ordinal_position
  loop
    if p_fk_overrides ? col.column_name then
      new_val := quote_literal(p_fk_overrides ->> col.column_name);
    elsif col.column_name = 'source' then
      new_val := quote_literal(case when before_row ->> 'source' = 'front_desk' then 'qr' else 'front_desk' end);
    elsif col.data_type = 'uuid' then
      new_val := 'gen_random_uuid()';
    elsif col.data_type = 'date' then
      new_val := quote_literal(((before_row ->> col.column_name)::date + 1)::text);
    elsif col.data_type = 'timestamp with time zone' then
      if before_row ->> col.column_name is null then
        new_val := 'now()';
      else
        new_val := quote_literal(((before_row ->> col.column_name)::timestamptz + interval '1 second')::text);
      end if;
    elsif col.data_type = 'text' then
      new_val := quote_literal(coalesce(before_row ->> col.column_name, '') || '_frozen_probe');
    elsif col.data_type = 'boolean' then
      new_val := (not coalesce((before_row ->> col.column_name)::boolean, false))::text;
    elsif col.data_type in ('integer', 'smallint', 'bigint', 'numeric') then
      new_val := (coalesce((before_row ->> col.column_name)::numeric, 0) + 1)::text;
    else
      leaked := leaked || (col.column_name || ' [UNPROBED TYPE ' || col.data_type || ']');
      continue;
    end if;

    begin
      execute format('update public.%I set %I = %s where id = %L',
        p_table, col.column_name, new_val, p_row_id);
    exception when others then
      null;
    end;
  end loop;

  execute format('select to_jsonb(t) from public.%I t where id = %L', p_table, p_row_id)
    into after_row;

  for col in
    select c.column_name
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = p_table
       and c.column_name <> all(p_excluded)
       and c.column_name <> 'id'
  loop
    if (before_row ->> col.column_name) is distinct from (after_row ->> col.column_name) then
      leaked := leaked || col.column_name;
    end if;
  end loop;

  -- id, last, by existence under the original value rather than by comparing
  -- values (there is nothing left to compare it to once it might have moved).
  if 'id' <> all(p_excluded) then
    begin
      execute format('update public.%I set id = gen_random_uuid() where id = %L', p_table, p_row_id);
    exception when others then
      null;
    end;

    execute format('select exists(select 1 from public.%I where id = %L)', p_table, p_row_id)
      into id_survived;

    if not id_survived then
      leaked := leaked || 'id'::text;
    end if;
  end if;

  return leaked;
end;
$fn$;

select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

select is(
  pg_temp.frozen_probe('membership_pauses', '170000ff-0000-4000-8000-000000000117'::uuid,
    array['tenant_id', 'updated_at', 'rejected_at'],
    jsonb_build_object('membership_id', '170000ff-0000-4000-8000-00000000a052',
                        'requested_by_staff_id', '170000ff-0000-4000-8000-00000000a023',
                        'approved_by_staff_id', '170000ff-0000-4000-8000-00000000a023')),
  '{}'::text[],
  'An APPROVED pause freezes every column but updated_at — swept from the catalogue rather than a hand-typed list, so id and created_at (ADR-070''s own two misses) are covered along with anything nobody has named yet');

select is(
  pg_temp.frozen_probe('membership_pauses', '170000ff-0000-4000-8000-000000000118'::uuid,
    array['tenant_id', 'updated_at', 'approved_at', 'approved_by_staff_id'],
    jsonb_build_object('membership_id', '170000ff-0000-4000-8000-00000000a052',
                        'requested_by_staff_id', '170000ff-0000-4000-8000-00000000a023')),
  '{}'::text[],
  'A REJECTED pause freezes just as hard as an approved one — the spec''s worked scenarios name only approvals, and a guard built by watching approved_at alone would leave every rejected pause permanently editable');

-- ---------------------------------------------------------------------------
-- 43-44. THE STATEMENT THAT DOES THE DECIDING: may it also amend?
--
-- Every rule above is about a row that is ALREADY decided. "Once a pause
-- carries a decision" reads as a precondition on the row BEFORE the
-- statement — which leaves open whether the very statement that first grants
-- or refuses a freeze may also, in the same breath, move what it is granting.
-- The Purpose section's own words ("an authorisation is an authorisation of
-- something") argue no; the requirement's literal text does not say so. Two
-- fresh PENDING pauses, attacked in one statement each, so no earlier
-- assertion's fixture is disturbed and the closing OUTCOMES count below is
-- unaffected unless this is where the money actually moves.
-- ---------------------------------------------------------------------------

-- Approve pause 123 AND stretch its ends_on in the same UPDATE. Manager A2
-- holds gym A's configured role and did not request it, so the approval half
-- of this statement is, on its own, entirely lawful.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'gym_manager',
                    'staff_id', '170000ff-0000-4000-8000-00000000a022')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set approved_by_staff_id = '170000ff-0000-4000-8000-00000000a022',
         approved_at = now(),
         ends_on = date '2028-10-08'
   where id = '170000ff-0000-4000-8000-000000000123'$$); end $do$;

-- Reject pause 124 AND stretch its ends_on in the same UPDATE. Front desk may
-- reject on its own, with no role check at all — so if amending rides along
-- with a reject just as easily as with an approval, the hole is not specific
-- to the two-person rule.
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '170000ff-0000-4000-8000-00000000a001',
                    'app_role', 'front_desk',
                    'staff_id', '170000ff-0000-4000-8000-00000000a024')::text, true);
set local role authenticated;

do $do$ begin perform pg_temp.attempt($$
  update public.membership_pauses
     set rejected_at = now(),
         ends_on = date '2028-10-08'
   where id = '170000ff-0000-4000-8000-000000000124'$$); end $do$;

reset role;
set local role postgres;

select ok(
  not (
    (select approved_at is not null from public.membership_pauses
      where id = '170000ff-0000-4000-8000-000000000123')
    and
    (select ends_on <> date '2026-10-08' from public.membership_pauses
      where id = '170000ff-0000-4000-8000-000000000123')
  ),
  'A pause cannot be granted for different dates than it was requested for by amending ends_on in the same statement that approves it — either both changes land or neither does, and only "neither" leaves the freeze the approver actually read intact. (If this is red: the guard reads OLD.approved_at to decide whether a row is already decided, which is the correct check for every OTHER assertion in this file, but means the FIRST statement that decides a row is not yet "a decided pause" while it runs — a genuine spec ambiguity, not necessarily this rule''s defect, and worth escalating rather than silently accepting either reading.)');

select ok(
  not (
    (select rejected_at is not null from public.membership_pauses
      where id = '170000ff-0000-4000-8000-000000000124')
    and
    (select ends_on <> date '2026-10-08' from public.membership_pauses
      where id = '170000ff-0000-4000-8000-000000000124')
  ),
  'Rejecting a pause cannot smuggle a date change through alongside it — rejection needs no role and no second person, so if the amend rides along here too, the hole is in every decision, not only approvals');

-- ---------------------------------------------------------------------------
-- 34-36. OUTCOMES, SCOPED TO THIS FILE'S TENANTS (ADR-050).
--
-- Every assertion above names one row and one route. These three ask the
-- question the gym's accountant would ask: across everything this file did, is
-- the set of granted freezes exactly the set somebody was allowed to grant?
-- They catch a route nobody thought to name.
-- ---------------------------------------------------------------------------

select results_eq(
  $$select id from public.membership_pauses
     where tenant_id in ('170000ff-0000-4000-8000-00000000a001',
                         '170000ff-0000-4000-8000-00000000b001')
       and approved_at is not null
     order by id$$,
  $$values ('170000ff-0000-4000-8000-000000000101'::uuid),  -- gym A's configured approver
           ('170000ff-0000-4000-8000-000000000110'::uuid),  -- fixture, unchanged
           ('170000ff-0000-4000-8000-000000000111'::uuid),  -- fixture, unchanged
           ('170000ff-0000-4000-8000-000000000112'::uuid),  -- fixture, unchanged
           ('170000ff-0000-4000-8000-000000000113'::uuid),  -- fixture, unchanged
           ('170000ff-0000-4000-8000-000000000114'::uuid),  -- fixture, not flipped
           ('170000ff-0000-4000-8000-000000000115'::uuid),  -- fixture, not re-approved
           ('170000ff-0000-4000-8000-000000000116'::uuid),  -- fixture, not rewritten
           ('170000ff-0000-4000-8000-000000000117'::uuid),  -- fixture, sweep target, unchanged
           ('170000ff-0000-4000-8000-000000000132'::uuid),  -- postgres, no claims
           ('170000ff-0000-4000-8000-000000000133'::uuid),  -- service_role, exempt
           ('170000ff-0000-4000-8000-000000000136'::uuid),  -- postgres, claims still set
           ('170000ff-0000-4000-8000-0000000001b1'::uuid)$$, -- gym B's configured approver
  'Exactly thirteen freezes are granted across both gyms — the two the configured approvers gave, the eight that were already decided (including the sweep target), and the three the exempt contexts seeded. Any fourteenth is money a gym stopped collecting on nobody''s authority — and in particular neither the approve-and-amend nor the reject-and-amend probe below may have slipped a pause into this set');

select is_empty(
  $$select id from public.membership_pauses
     where tenant_id in ('170000ff-0000-4000-8000-00000000a001',
                         '170000ff-0000-4000-8000-00000000b001')
       and approved_at is not null
       and approved_by_staff_id is not distinct from requested_by_staff_id$$,
  'No granted freeze in either gym names the same staff member as requester and approver — the two-person rule stated as a property of the data rather than of any one statement');

select is_empty(
  $$select p.id
      from public.membership_pauses p
      join public.staff s
        on s.tenant_id = p.tenant_id and s.id = p.approved_by_staff_id
      join public.organization_settings os on os.tenant_id = p.tenant_id
     where p.tenant_id in ('170000ff-0000-4000-8000-00000000a001',
                           '170000ff-0000-4000-8000-00000000b001')
       and p.approved_at is not null
       and s.role <> os.pause_approver_role$$,
  'Every granted freeze in either gym was granted by someone holding that gym''s own configured approver role — checked against the settings row rather than against any constant');

select * from finish();

rollback;
