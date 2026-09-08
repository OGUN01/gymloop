-- 17_pause_decision.sql — capability: pause decision (Phase 3)
--
-- Written from openspec/changes/phase-3-core-domain/specs/pause-decision/spec.md,
-- by a session that has not read the implementation and did not look for it
-- (AGENTS.md rule 10). No migration under 20260908090000_* was opened, no
-- function source was read, and nothing in the catalogue was inspected to find
-- out how the rule was built. Every assertion below is derived from the five
-- requirements and from the Phase 1 table shape.
--
-- WHAT THIS FILE ASSUMES, STATED UP FRONT BECAUSE IT IS THE CONTRACT CLAIM
--
-- Every behavioural assertion is a plain `update public.membership_pauses`
-- (and, once, a plain `insert`). That is the whole point of the third scenario
-- of the first requirement: `membership_pauses` grants INSERT and UPDATE
-- directly to `authenticated`, and the write gate admits any front-office
-- session of the row's own gym, so an approval rule that lives in a Route
-- Handler is not a rule — a front-desk session writing through supabase-js
-- goes straight round it, and the freeze it grants itself is money the gym
-- never collects. The mechanism therefore has to sit under the write. No
-- assertion here calls an endpoint or an RPC.
--
-- WHY TWO GYMS WITH DIFFERENT CONFIGURED ROLES
--
--   Gym A: organization_settings.pause_approver_role = 'gym_manager'
--   Gym B: organization_settings.pause_approver_role = 'front_desk'
--
-- A suite built on one gym cannot tell a genuine per-gym read from a constant
-- that happens to match it. Assertions 4 and 17 are the discriminating pair —
-- a front_desk approval, refused in gym A and accepted in gym B — and 2 and 20
-- are its mirror for gym_manager. No hardcoded role satisfies all four.
--
-- WHAT IS PROVEN AND WHAT IS ONLY APPROXIMATED
--
--   Proven outright. The configured role is read per gym (2/4/17/20). Equality
--   is equality and not seniority: a gym_owner is refused in a gym whose
--   configured approver is gym_manager (5). The approver is the acting staff
--   member (7). The requester cannot grant their own freeze — not plainly (18)
--   and not by rewriting who asked in the same breath (9) — and a colleague of
--   the right role can (11). Rejection is ungoverned, including by the very
--   actor whose approval was refused one assertion earlier in the same gym on
--   the same kind of row (20 vs 21) — that pair is what goes red when a later
--   reader "tidies" the asymmetry into symmetry. The recorded requester is
--   immutable (27/28), a pause cannot be born decided (35), and a session
--   carrying no staff identity decides nothing (29-32) while a trusted
--   non-authenticated context still writes freely (33/34).
--
--   Approximated, and said so. Assertions 24 and 26 wrap the second decision
--   in an exception-swallowing DO block, because the "a decided pause stays
--   decided" requirement says "nothing SHALL change" and does not say whether
--   the second approver is refused loudly or ignored quietly. Both readings
--   satisfy the requirement, so the assertion is on the state afterwards, not
--   on the outcome of the statement. Assertions 29-32 do NOT get that
--   treatment: "Only a session with a staff identity may decide" says the
--   write SHALL be refused, so those are throws_ok.
--
--   Not attempted. Nothing here concerns which roles may write pauses at all;
--   the write gate is `is_front_office()` and belongs to the authorization
--   suite. Every acting session below is front office, so every refusal in
--   this file is the pause rule refusing and not the policy filtering. A
--   trainer session would see zero rows affected and no error, which would
--   make a `throws_ok` here silently untrustworthy.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own two fixture tenants — this
--          database permanently holds a seeded demo gym, and an assertion over
--          a whole table is a time bomb.
-- ADR-044: no catalogue `name` column is compared against a bare literal.

begin;

set local role postgres;

set local search_path = extensions, public;

select plan(37);


-- ---------------------------------------------------------------------------
-- Fixtures. Two gyms whose configured approver roles are swapped relative to
-- one another, so that each of the two roles is the approver in one gym and an
-- outsider in the other.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('17000000-0000-4000-8000-000000000001'::uuid, 'Pause Gym A', 'PSE17A'),
  ('17000000-0000-4000-8000-000000000002'::uuid, 'Pause Gym B', 'PSE17B');

insert into public.organization_settings (tenant_id, pause_approver_role) values
  ('17000000-0000-4000-8000-000000000001'::uuid, 'gym_manager'),
  ('17000000-0000-4000-8000-000000000002'::uuid, 'front_desk');

insert into public.branches (id, tenant_id, name, is_default) values
  ('17000000-0000-4000-8000-000000000011'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('17000000-0000-4000-8000-000000000012'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, 'B Main', true);

-- Gym A holds two managers, because the fourth requirement's second scenario
-- needs "a different staff member holding the configured role" to be a real
-- row and not a hypothetical one.
insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('17000000-0000-4000-8000-000000000021'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000011'::uuid, 'front_desk',  'A Desk'),
  ('17000000-0000-4000-8000-000000000022'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Manager One'),
  ('17000000-0000-4000-8000-000000000023'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000011'::uuid, 'gym_manager', 'A Manager Two'),
  ('17000000-0000-4000-8000-000000000024'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000011'::uuid, 'gym_owner',   'A Owner'),
  ('17000000-0000-4000-8000-000000000025'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000012'::uuid, 'front_desk',  'B Desk'),
  ('17000000-0000-4000-8000-000000000027'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000012'::uuid, 'gym_manager', 'B Manager');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('17000000-0000-4000-8000-000000000031'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000011'::uuid, 'A Member', '+911700000031'),
  ('17000000-0000-4000-8000-000000000032'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000012'::uuid, 'B Member', '+911700000032');

insert into public.plans (id, tenant_id, name, duration_days, price_paise) values
  ('17000000-0000-4000-8000-000000000041'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, 'A Monthly', 30, 200000),
  ('17000000-0000-4000-8000-000000000042'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, 'B Monthly', 30, 200000);

insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise) values
  ('17000000-0000-4000-8000-000000000051'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000031'::uuid, '17000000-0000-4000-8000-000000000041'::uuid, 'active', current_date - 10, current_date + 50, 200000),
  ('17000000-0000-4000-8000-000000000052'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000032'::uuid, '17000000-0000-4000-8000-000000000042'::uuid, 'active', current_date - 10, current_date + 50, 200000);

-- Seventeen pending pauses — approved_at and rejected_at both null — one per
-- decision this file makes, so no assertion inherits state from another.
-- The requester is chosen per row so that the reason a write is refused is
-- never ambiguous: where the role is on trial the requester is somebody else,
-- and where the requester is on trial the role is the configured one.
insert into public.membership_pauses
  (id, tenant_id, membership_id, starts_on, ends_on, reason, requested_by_staff_id) values
  ('17000000-0000-4000-8000-000000000061'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'travel',            '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000062'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'injury',            '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000063'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'exams',             '17000000-0000-4000-8000-000000000021'::uuid),
  ('17000000-0000-4000-8000-000000000064'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'family wedding',    '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000065'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'surgery',           '17000000-0000-4000-8000-000000000022'::uuid),
  ('17000000-0000-4000-8000-000000000066'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'relocation',        '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000067'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'raised in error',   '17000000-0000-4000-8000-000000000021'::uuid),
  ('17000000-0000-4000-8000-000000000068'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'posting abroad',    '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000069'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'unclear request',   '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-00000000006a'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000052'::uuid, current_date + 1, current_date + 8,  'travel',            '17000000-0000-4000-8000-000000000027'::uuid),
  ('17000000-0000-4000-8000-00000000006b'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000052'::uuid, current_date + 1, current_date + 8,  'injury',            '17000000-0000-4000-8000-000000000025'::uuid),
  ('17000000-0000-4000-8000-00000000006c'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000052'::uuid, current_date + 1, current_date + 8,  'duplicate',         '17000000-0000-4000-8000-000000000025'::uuid),
  ('17000000-0000-4000-8000-00000000006d'::uuid, '17000000-0000-4000-8000-000000000002'::uuid, '17000000-0000-4000-8000-000000000052'::uuid, current_date + 1, current_date + 8,  'own request',       '17000000-0000-4000-8000-000000000025'::uuid),
  -- Three more for the requirements the blind critic added. All three are
  -- requested by the owner (24), so that in every one of them the acting
  -- session is a stranger to the request and the requester rule is not what
  -- refuses.
  ('17000000-0000-4000-8000-00000000006e'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'reassignment',      '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-00000000006f'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'impersonated',      '17000000-0000-4000-8000-000000000024'::uuid),
  ('17000000-0000-4000-8000-000000000070'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'trusted context',   '17000000-0000-4000-8000-000000000024'::uuid),
  -- 71 is assertion 9's own row, requested by manager 22 exactly as 65 is.
  -- It exists so that the write assertion 9 attempts — the one a broken
  -- implementation lets through — cannot decide the row assertions 11 and 12
  -- need pending.
  ('17000000-0000-4000-8000-000000000071'::uuid, '17000000-0000-4000-8000-000000000001'::uuid, '17000000-0000-4000-8000-000000000051'::uuid, current_date + 1, current_date + 8,  'own request A',     '17000000-0000-4000-8000-000000000022'::uuid);


-- ---------------------------------------------------------------------------
-- The mechanism, in the catalogue (1)
--
-- Behaviour alone cannot distinguish a rule every writer meets from one only
-- the endpoint meets, and this capability exists precisely because the writer
-- who does not use the endpoint is the one that matters. The exclusion of
-- app.touch_updated_at() is not decoration: membership_pauses already carries
-- a before-update trigger from Phase 1, so an existence test that did not
-- exclude it would pass against an implementation that never shipped.
-- ---------------------------------------------------------------------------

-- 1
select ok(
  exists (
    select 1
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.membership_pauses'::regclass
       and not t.tgisinternal
       and p.proname::text collate "default" <> 'touch_updated_at'
       and (t.tgtype & 16) <> 0
  ),
  'requirement "The gym decides which role approves a freeze" — the rule is enforced under the write: a trigger other than the shared updated_at stamp fires on update of public.membership_pauses. A rule enforced in a caller is a rule with a way round it, and membership_pauses grants UPDATE straight to authenticated'
);


-- ---------------------------------------------------------------------------
-- The gym decides which role approves a freeze — gym A, whose configured
-- approver role is gym_manager (2-6)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 2
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000061'::uuid
$$, 'scenario "The configured role approves" — gym A''s configured approver role is gym_manager, and a manager of gym A approving a pending pause is not refused');

set local role postgres;

-- 3 — lives_ok alone proves nothing here: an update the policy filtered out
-- affects zero rows and raises nothing. The approval has to be on the row.
select results_eq(
  $$
    select approved_by_staff_id, approved_at is not null, rejected_at is null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000061'::uuid
  $$,
  $$ values ('17000000-0000-4000-8000-000000000022'::uuid, true, true) $$,
  'scenario "The configured role approves" — the approval landed: the manager is recorded, the timestamp is stamped, and the pause is not also rejected'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '17000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 4 — scenarios "Another staff role approves" and "The rule cannot be gone
-- around" in one statement. This session may write membership_pauses: the
-- write gate is is_front_office() and front_desk is inside it, so what refuses
-- this is the approval rule and not the policy. The pause was requested by the
-- owner, so nothing about the requester is in play either.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000021'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000062'::uuid
$$, null::char(5), null,
  'scenarios "Another staff role approves" and "The rule cannot be gone around" — a front-desk session of gym A writing the approval columns straight at the table, no endpoint involved, is refused because gym A''s configured approver role is gym_manager');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner',
                    'staff_id', '17000000-0000-4000-8000-000000000024')::text,
  true);
set local role authenticated;

-- 5 — the requirement says the role must EQUAL the configured role. It does
-- not say "or more senior". An implementation that lets the owner approve
-- anything because owners outrank managers goes red here, and it should: the
-- gym chose gym_manager, and the setting is the gym's decision, not a floor.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000024'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000063'::uuid
$$, null::char(5), null,
  'scenario "Another staff role approves" — the gym owner is another staff role. Equality with the configured role is the test, not seniority, so the owner of a gym that nominated its managers cannot approve');

set local role postgres;

-- 6
select is(
  (select count(*)::int from public.membership_pauses
    where tenant_id = '17000000-0000-4000-8000-000000000001'::uuid
      and id in ('17000000-0000-4000-8000-000000000062'::uuid,
                 '17000000-0000-4000-8000-000000000063'::uuid)
      and approved_at is null
      and rejected_at is null
      and approved_by_staff_id is null),
  2,
  'both refused approvals left their pauses exactly as they were — still pending, no approver recorded, nothing half-written'
);


-- ---------------------------------------------------------------------------
-- The approver is whoever is acting, and cannot be someone else (7-8)
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 7 — everything about this write is otherwise correct: the acting session is
-- a manager, the gym's configured role is gym_manager, the named approver is
-- ALSO a manager of the same gym, and neither of them requested the pause. The
-- one thing wrong is that the approver named is not the person acting. If this
-- passes, an approval can be pinned on a colleague who never made it.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000023'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000064'::uuid
$$, null::char(5), null,
  'scenario "Attributing an approval to another staff member" — the recorded approver must be the acting staff member, so a manager cannot record a second, equally-qualified manager as having granted the freeze');

set local role postgres;

-- 8
select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '17000000-0000-4000-8000-000000000064'::uuid),
  null::uuid,
  'the misattributed approval left no approver behind at all'
);


-- ---------------------------------------------------------------------------
-- The person who asked is not the person who grants (9-12)
--
-- Pauses 71 and 65 were both requested by manager 22, who holds gym A's
-- configured approver role. Every other condition is satisfied, so separation
-- of duties is the only thing that can refuse either — and manager 23,
-- identical in role and gym, differing only in not having asked, must be able
-- to grant one.
--
-- Two rows and not one, deliberately. Assertion 9 is a write that a broken
-- implementation LETS THROUGH, so if it shared a row with assertion 11 then
-- the hole at 9 would decide 11's row and take 11 and 12 down with it — three
-- red assertions reporting one defect, two of them about a rule that is not
-- broken. A test that goes red for somebody else's reason is a test that will
-- be misread.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 9 — CORRECTED. This assertion used to issue the naive self-approval: it set
-- only the approval columns and left requested_by_staff_id alone. That form
-- passes against a system with the hole wide open, because the statement a
-- self-approving manager would actually write is this one — rewriting who
-- asked and granting the freeze in the SAME UPDATE. membership_pauses grants
-- update to authenticated and its write policy is is_front_office() for every
-- command, so nothing stops the two columns moving together. A separation-of-
-- duties rule the writer can satisfy by rewriting the other half of the
-- comparison is decoration, and the naive assertion could not tell the two
-- apart. This is therefore both scenario "Approving one's own request" and
-- scenario "Reassigning the request in the approving statement" — the second
-- is what makes the first a control at all.
select throws_ok($$
  update public.membership_pauses
     set requested_by_staff_id = '17000000-0000-4000-8000-000000000023'::uuid,
         approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000071'::uuid
$$, null::char(5), null,
  'scenarios "Approving one''s own request" and "Reassigning the request in the approving statement" — the manager who raised this pause holds exactly the role the gym configured, and cannot buy their way past the two-person rule by moving the request onto a colleague in the same statement. Recording an employee as having asked for a freeze they never asked for is the falsification, and the approval riding on it is the loss');

set local role postgres;

-- 10 — the requester is half of the comparison assertion 9 relies on, so the
-- state check has to include it: a refusal that still let requested_by move
-- would leave the permanent record naming manager 23, who never asked.
select is(
  (select count(*)::int from public.membership_pauses
    where id = '17000000-0000-4000-8000-000000000071'::uuid
      and approved_at is null and rejected_at is null
      and requested_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid),
  1,
  'the refused self-approval left the pause pending AND left manager 22 recorded as the person who asked — available for somebody else to decide, on the true facts'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- 11 — the same row, the same role, the same gym; the only difference from
-- assertion 9 is who asked. An implementation that refused every manager, or
-- that refused any row once a decision had been attempted, fails here.
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000023'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000065'::uuid
$$, 'scenario "A different staff member of the right role approves it" — the second manager, who did not raise the request, may grant it');

set local role postgres;

-- 12
select results_eq(
  $$
    select approved_by_staff_id, approved_at is not null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000065'::uuid
  $$,
  $$ values ('17000000-0000-4000-8000-000000000023'::uuid, true) $$,
  'scenario "A different staff member of the right role approves it" — the colleague''s approval landed and is recorded against them'
);


-- ---------------------------------------------------------------------------
-- Rejecting a pause is not the decision approving one is (13-16)
--
-- This is the requirement a later reader will get wrong, so it is asserted at
-- the two places the tidying would land: the role, and the requester. Refusing
-- a freeze costs the gym nothing; granting one is money it does not collect.
-- The asymmetry is deliberate and these assertions exist to make removing it
-- expensive.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '17000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 13 — the same session, the same gym and the same kind of row as assertion 4,
-- where the approval was refused. Only the decision differs.
select lives_ok($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '17000000-0000-4000-8000-000000000066'::uuid
$$, 'scenario "Any staff member may reject" — front desk is not gym A''s configured approver role and rejects anyway: a rejection needs no configured role');

-- 14 — the requester rejecting their own request. Placed inside the same
-- session because it is the same person: staff 21 raised pause 67.
select lives_ok($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '17000000-0000-4000-8000-000000000067'::uuid
$$, 'scenario "The requester may reject their own request" — a rejection needs no second person either, so the staff member who raised a pause may withdraw it by refusing it');

set local role postgres;

-- 15 — a rejection is a rejection and not a quiet approval. There is no
-- rejected_by column in the schema, so who refused is deliberately unrecorded;
-- an implementation that stamped approved_by_staff_id on the way past would
-- leave a freeze that reads as granted.
select results_eq(
  $$
    select rejected_at is not null, approved_at is null, approved_by_staff_id is null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000066'::uuid
  $$,
  $$ values (true, true, true) $$,
  'scenario "Any staff member may reject" — the rejection landed as a rejection: rejected_at set, and nothing written into either approval column'
);

-- 16
select is(
  (select count(*)::int from public.membership_pauses
    where id = '17000000-0000-4000-8000-000000000067'::uuid
      and rejected_at is not null and approved_at is null),
  1,
  'scenario "The requester may reject their own request" — the self-rejection landed'
);


-- ---------------------------------------------------------------------------
-- The configured role is the GYM's, read per gym — gym B, whose configured
-- approver role is front_desk (17-22)
--
-- Assertions 17 and 20 are the same two roles as 2 and 4 with the outcomes
-- swapped. Together the four say that the approver role is read from the row's
-- own gym: no single hardcoded role, and no role read from the wrong gym,
-- satisfies all four.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000002',
                    'app_role', 'front_desk',
                    'staff_id', '17000000-0000-4000-8000-000000000025')::text,
  true);
set local role authenticated;

-- 17
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000025'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-00000000006a'::uuid
$$, 'scenario "The configured role approves" — gym B nominated front_desk, so the SAME role refused in gym A at assertion 4 approves here');

-- 18 — the third requirement again, at the other role. The acting session
-- holds gym B's configured approver role and still may not grant the freeze it
-- asked for. Run inside this session because it is the same staff member.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000025'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-00000000006d'::uuid
$$, null::char(5), null,
  'scenario "Approving one''s own request" — "whatever their role" means at front_desk too: gym B''s configured approver still cannot grant a freeze they themselves requested');

set local role postgres;

-- 19
select results_eq(
  $$
    select approved_by_staff_id, approved_at is not null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-00000000006a'::uuid
  $$,
  $$ values ('17000000-0000-4000-8000-000000000025'::uuid, true) $$,
  'the front-desk approval landed in gym B — with assertion 4''s refusal in gym A, this pair is the per-gym read: no constant role satisfies both'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000002',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000027')::text,
  true);
set local role authenticated;

-- 20 — the mirror of assertion 2. Same role, opposite gym, opposite outcome.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000027'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-00000000006b'::uuid
$$, null::char(5), null,
  'scenario "Another staff role approves" — gym B nominated front_desk, so the SAME gym_manager role that approved in gym A at assertion 2 is an outsider here');

-- 21 — THE ASYMMETRY, at its sharpest. Identical session to assertion 20,
-- identical gym, identical kind of pending row; the only difference is that
-- this is a rejection. If a later reader "tidies" the fifth requirement into
-- symmetry — making rejection require the configured role, or a second person,
-- because approval does — this assertion is what goes red.
select lives_ok($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '17000000-0000-4000-8000-00000000006c'::uuid
$$, 'requirement "Rejecting a pause is not the decision approving one is" — the very manager whose APPROVAL was refused one statement ago may REJECT, in the same gym, on the same kind of row. Only the transition into approved is governed');

set local role postgres;

-- 22
select results_eq(
  $$
    select rejected_at is not null, approved_at is null, approved_by_staff_id is null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-00000000006c'::uuid
  $$,
  $$ values (true, true, true) $$,
  'the outsider''s rejection landed in gym B, and landed as a rejection'
);


-- ---------------------------------------------------------------------------
-- A decided pause stays decided (23-26)
--
-- The requirement says "nothing SHALL change" and does not say whether the
-- second decider is refused loudly or ignored quietly. Both readings satisfy
-- it, so the second decision is issued inside an exception-swallowing block
-- and the assertion is on the state afterwards. That is the requirement as
-- written; if the intended behaviour is specifically a raise, the spec should
-- say so and this file should be tightened.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 23
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000068'::uuid
$$, 'the first manager approves the pause that assertion 24 will attempt to approve a second time');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000023')::text,
  true);
set local role authenticated;

-- The second approver is impeccable on every other count: gym A's configured
-- role, a different person from both the requester and the first approver,
-- recording themselves. The only thing wrong is that the decision was already
-- made.
do $$
begin
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000023'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000068'::uuid;
exception when others then null;
end $$;

set local role postgres;

-- 24
select is(
  (select approved_by_staff_id from public.membership_pauses
    where id = '17000000-0000-4000-8000-000000000068'::uuid),
  '17000000-0000-4000-8000-000000000022'::uuid,
  'scenario "Approving an already-approved pause" — the original approver is still the one recorded. A second, equally-qualified manager cannot overwrite who granted the freeze'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'front_desk',
                    'staff_id', '17000000-0000-4000-8000-000000000021')::text,
  true);
set local role authenticated;

-- 25
select lives_ok($$
  update public.membership_pauses
     set rejected_at = now()
   where id = '17000000-0000-4000-8000-000000000069'::uuid
$$, 'the front desk rejects the pause that the next block will attempt to approve');

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- "Decided" is not only "approved". A rejected pause is decided too, and an
-- approval that overturned it would let a freeze the gym refused be granted by
-- whoever asked next.
do $$
begin
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000069'::uuid;
exception when others then null;
end $$;

set local role postgres;

-- 26
select results_eq(
  $$
    select rejected_at is not null, approved_at is null, approved_by_staff_id is null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000069'::uuid
  $$,
  $$ values (true, true, true) $$,
  'requirement "A decided pause stays decided" — a rejection is a decision. The configured approver cannot reach past it and grant the freeze the gym has already refused'
);


-- ---------------------------------------------------------------------------
-- The person who asked is recorded once and cannot be changed (27-28)
--
-- Scenario "Reassigning the request in the approving statement" is assertion
-- 9, where it belongs: the rewrite only matters because it is what turns the
-- two-person rule into a formality. This section is the other scenario, the
-- rewrite standing on its own, with no decision anywhere near it.
--
-- Manager 22 is a stranger to pause 6e — the owner raised it — holds gym A's
-- configured approver role, and touches no approval column. Every rule in
-- every requirement above is satisfied or irrelevant. The only thing that can
-- refuse this statement is the requester being fixed from the moment the pause
-- exists, which is exactly what makes it worth asserting separately: an
-- implementation that guards requested_by only when the approval columns move
-- in the same UPDATE passes assertion 9 and fails here, and it should, because
-- the falsified record — an employee named as having asked for a freeze — is
-- the harm whether or not a decision rides along with it.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 27
select throws_ok($$
  update public.membership_pauses
     set requested_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid
   where id = '17000000-0000-4000-8000-00000000006e'::uuid
$$, null::char(5), null,
  'scenario "Reassigning the request on its own" — requested_by_staff_id is fixed from the moment the pause exists. A manager may write this table and still may not move somebody else''s request onto themselves, or their own onto somebody else'
);

set local role postgres;

-- 28
select is(
  (select requested_by_staff_id from public.membership_pauses
    where id = '17000000-0000-4000-8000-00000000006e'::uuid),
  '17000000-0000-4000-8000-000000000024'::uuid,
  'the refused reassignment left the owner recorded as the person who asked'
);


-- ---------------------------------------------------------------------------
-- Only a session with a staff identity may decide (29-34)
--
-- WHAT IS BEING CONSTRUCTED HERE, SAID PLAINLY: the claim set below is the
-- SHAPE app.custom_access_token_hook mints for a live impersonation session —
-- app_role 'gym_owner' and a tenant_id, deliberately no staff_id — set
-- directly with set_config, exactly as every other session in this file is.
-- This tests the guard against that claim shape. It does not test the hook,
-- and it does not need a real impersonation row: what reaches the write is a
-- claim set, and a claim set is what is asserted against. If the hook ever
-- stops minting this shape that is the hook's suite's problem, not this one's.
--
-- Such a session passes is_front_office() — app_role is gym_owner — so it may
-- write membership_pauses and the row is visible to it. What it cannot do is
-- meet any rule in this file: not the configured role, not the two-person
-- rule, not "a decided pause stays decided", because every one of them is a
-- comparison against a staff_id that is not there. A guard that returns early
-- when it cannot identify the caller reads that as trust.
--
-- Assertions 33/34 are the other half and are not optional: the early return
-- is legitimate for postgres and service_role, which bypass row security by
-- design and are what every fixture and the seed run as. An implementation
-- that fixed 29-32 with a blanket refusal, or with a CHECK constraint, would
-- break every fixture in the repo — 33/34 is what catches that before it is
-- shipped, and 29 vs 33 is the discriminating pair: the same statement, the
-- same absent staff identity, opposite outcomes, because one is subject to row
-- security and the other is not.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true);
set local role authenticated;

-- 29 — the named approver is manager 22: a real staff member of gym A holding
-- the configured approver role, and not the requester. Under every rule above
-- this row is impeccable. The one thing wrong is that nobody with a staff
-- identity is acting.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-00000000006f'::uuid
$$, null::char(5), null,
  'scenario "An impersonating platform admin approves a freeze" — a token carrying app_role gym_owner and a tenant_id but no staff_id passes the write gate and has no staff identity to check anything against. docs/security.md says impersonation has the gym''s reach and not more; granting a freeze no member of the gym could grant is more'
);

-- 30 — the same session at the worst path of all: rewriting a decision that
-- has already been made. Pause 61 was approved by manager 22 at assertion 2.
-- Every rule in this file keys off the pause being undecided, so this is the
-- statement that skips them all.
select throws_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000023'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000061'::uuid
$$, null::char(5), null,
  'scenario "An impersonating platform admin rewrites a decision" — the staff-identity guard has to run before the already-decided check, not after it, or the one caller who meets no rule is the one caller who can overwrite who granted a freeze'
);

set local role postgres;

-- 31
select is(
  (select count(*)::int from public.membership_pauses
    where id = '17000000-0000-4000-8000-00000000006f'::uuid
      and approved_at is null and rejected_at is null
      and approved_by_staff_id is null),
  1,
  'the impersonated approval left the pause pending and nothing half-written'
);

-- 32
select results_eq(
  $$
    select approved_by_staff_id from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000061'::uuid
  $$,
  $$ values ('17000000-0000-4000-8000-000000000022'::uuid) $$,
  'scenario "An impersonating platform admin rewrites a decision" — manager 22, who actually made the decision at assertion 2, is still the one recorded'
);

-- The trusted context. Role postgres, no jwt claims at all — the same shape
-- every fixture insert in this file and every row of the seed runs as, and
-- the same statement assertion 29 was refused for.
select set_config('request.jwt.claims', '', true);

-- 33
select lives_ok($$
  update public.membership_pauses
     set approved_by_staff_id = '17000000-0000-4000-8000-000000000022'::uuid,
         approved_at = now()
   where id = '17000000-0000-4000-8000-000000000070'::uuid
$$, 'scenario "The seed and the fixtures are unaffected" — a trusted context that is not an authenticated session writes a decision with no staff identity of its own and is not refused');

-- 34
select results_eq(
  $$
    select approved_by_staff_id, approved_at is not null
      from public.membership_pauses
     where id = '17000000-0000-4000-8000-000000000070'::uuid
  $$,
  $$ values ('17000000-0000-4000-8000-000000000022'::uuid, true) $$,
  'the trusted context''s write landed — row security does not apply to it, and a rule imposed there would break every fixture without protecting anything a policy is not already protecting'
);


-- ---------------------------------------------------------------------------
-- A pause cannot be created already decided (35-36)
--
-- CORRECTED. Assertion 35 used to name the acting staff member as BOTH the
-- requester and the approver, which meant the self-approval rule refused it
-- and the insert rule was never on trial: the assertion's message claimed a
-- rule its fixture could not distinguish from one already proven at assertion
-- 9, and an assertion whose name claims more than its fixture proves is worse
-- than no assertion, because it reads as coverage. The requester is now the
-- owner (24) and the acting session is manager 22, holding gym A's configured
-- approver role and recording itself. Role rule satisfied, approver-is-actor
-- satisfied, two-person rule satisfied. The only thing left that can refuse
-- this insert is the insert rule.
--
-- Assertion 36 is the carve-out the requirement states in the same breath, and
-- it is load-bearing: the seed and the demo scenario data legitimately create
-- an already-approved pause — there is one covering today, and Phase 4's
-- no-show scan is built to find it — as postgres, which bypasses row security.
-- An implementation that reached for a CHECK constraint would pass 35 and
-- break the seed; 36 is where that shows up as red instead of as a broken
-- environment.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '17000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_manager',
                    'staff_id', '17000000-0000-4000-8000-000000000022')::text,
  true);
set local role authenticated;

-- 35
select throws_ok($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id, approved_at)
  values ('17000000-0000-4000-8000-0000000000ff'::uuid,
          '17000000-0000-4000-8000-000000000001'::uuid,
          '17000000-0000-4000-8000-000000000051'::uuid,
          current_date + 1, current_date + 8, 'born approved',
          '17000000-0000-4000-8000-000000000024'::uuid,
          '17000000-0000-4000-8000-000000000022'::uuid,
          now())
$$, null::char(5), null,
  'scenario "A pause born approved" — a session subject to row security cannot insert a pause carrying approved_at, naming a colleague as the requester and itself as the approver. On an insert both sides of every rule above are the caller''s own input in one statement, so the rules are vacuous by construction there and the state simply has no legitimate way to arise: a gym wanting an immediately-approved freeze writes two statements, and the second one is governed'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- 36
select lives_ok($$
  insert into public.membership_pauses
    (id, tenant_id, membership_id, starts_on, ends_on, reason,
     requested_by_staff_id, approved_by_staff_id, approved_at)
  values ('17000000-0000-4000-8000-0000000000fe'::uuid,
          '17000000-0000-4000-8000-000000000001'::uuid,
          '17000000-0000-4000-8000-000000000051'::uuid,
          current_date + 1, current_date + 8, 'seeded approved',
          '17000000-0000-4000-8000-000000000024'::uuid,
          '17000000-0000-4000-8000-000000000022'::uuid,
          now())
$$, 'requirement "A pause cannot be created already decided" — "a session subject to row security" and not "whoever is asking": the seed creates an already-approved pause as postgres, and a constraint that no context can bypass would take the demo data and Phase 4''s no-show scan down with it');

-- 37 — ADR-050: scoped to this file's own two tenants. Seventeen pauses were
-- inserted as fixtures and assertion 36 legitimately added an eighteenth; the
-- refused insert at 35 left nothing behind, and no refused update created a
-- row of its own.
select is(
  (select count(*)::int from public.membership_pauses
    where tenant_id in ('17000000-0000-4000-8000-000000000001'::uuid,
                        '17000000-0000-4000-8000-000000000002'::uuid)),
  18,
  'the two fixture gyms hold exactly the eighteen pauses this file created: every refusal above refused, and none of them left a partial row'
);

select * from finish();

rollback;
