-- 10_platform_rls.sql — cluster: platform. Isolation, privileges, policy and
-- trigger shape.
--
-- Written from openspec/changes/0001-data-model/specs/platform/spec.md,
-- docs/data-model.md "Conventions (the contract)" -> Row-Level Security /
-- Privileges / Audit rows / Tenant-path exceptions, and docs/security.md ->
-- Impersonation, before the DDL exists (AGENTS.md rule 10). Gate 7.
--
-- The structural half — enum label order, table existence, natural key, and
-- every "the write SHALL be rejected" check-constraint scenario — is in
-- 10_platform_shape.sql and is deliberately not repeated here.
--
-- This cluster holds both of ADR-033's tenant-path exceptions, so the matrix
-- has three shapes rather than one:
--   leads, member_imports        ordinary tenant-scoped tables
--   platform_users              no tenant column at all, platform policy only
--   impersonation_sessions      tenant policy is `for select` only
--   audit_log                   nullable tenant_id, read-only by privilege (ADR-047)
--
-- ADR-030: transaction-wrapped, never committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(40);

-- ---------------------------------------------------------------------------
-- Privileges. Asserted with the three-argument form so the result does not
-- depend on which role the session happens to be (docs/data-model.md, "How a
-- pgTAP test assumes a role"). `authenticated` holds `delete` on no table in
-- Phase 1; on these two tables the absence is permanent, not a default.
-- ---------------------------------------------------------------------------

select ok(
  not has_table_privilege('authenticated', 'public.impersonation_sessions', 'DELETE'),
  'authenticated holds no DELETE on impersonation_sessions — history, INT-001/INT-003'
);

select ok(
  has_table_privilege('authenticated', 'public.audit_log', 'SELECT'),
  'authenticated holds SELECT on audit_log (INT-003 storage is readable)'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'INSERT'),
  'authenticated holds no INSERT on audit_log — ADR-047 made it read-only, so a gym cannot forge a row naming a platform user as the actor; every audit write is service_role (INT-003)'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'UPDATE'),
  'authenticated holds no UPDATE on audit_log — ADR-047 made it read-only to authenticated, and the tier is a privilege, not a trigger (spec: Editing an audit row)'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'DELETE'),
  'authenticated holds no DELETE on audit_log — INT-001 covers audit rows too (spec: Deleting an audit row)'
);

-- ---------------------------------------------------------------------------
-- Policy inventory. Both exceptions to the template live here, and the
-- exception is the point: a stray gym-side policy on platform_users, or an
-- `impersonation_sessions_tenant_write` beside the select-only one, would pass
-- a behaviour test that only ever read.
-- ---------------------------------------------------------------------------

-- Phase 2 splits the platform policy in two everywhere (design.md 8.1):
-- `_platform_select` on is_platform() so support still reads, `_platform_write`
-- on `= super_admin` so support writes nothing. On this table that split is
-- what closes OPEN-009 -- under the single platform_users_platform_all a
-- support account could update its own row to super_admin, because the policy
-- was gated on is_platform() and support is a platform role. It needs no
-- bespoke pair: the ordinary template says exactly that. The tenant half of the
-- rule is unchanged -- ADR-033 still means there is no gym-side policy here,
-- because there is no tenant to scope to.
select policies_are(
  'public', 'platform_users',
  ARRAY['platform_users_platform_select', 'platform_users_platform_write'],
  'platform_users carries the ordinary platform pair and no gym-side policy (ADR-033, design.md 8.4)'
);

-- Four, and every one of them is a decision. impersonation_sessions is NOT one
-- of the four read-only tables: its grant is select, insert, update (the
-- history tier) and a super admin genuinely creates sessions through it, so it
-- carries `_platform_write`. What it lacks is `_tenant_write` -- a gym may read
-- the record of being impersonated and may not author it, which is a policy
-- decision rather than a grant one (design.md 8.1). And it carries one policy
-- no other table has: `_impersonator_write`, the only path by which a live
-- session can be ended at all, because while a session is live its actor holds
-- gym_owner and not super_admin (design.md 6). The behaviour of all four is
-- 14_impersonation's; what this asserts is that there is no fifth.
select policies_are(
  'public', 'impersonation_sessions',
  ARRAY['impersonation_sessions_tenant_select',
        'impersonation_sessions_platform_select',
        'impersonation_sessions_platform_write',
        'impersonation_sessions_impersonator_write'],
  'impersonation_sessions carries a select-only gym-side policy, the full platform pair, and the impersonator''s own end-my-session policy -- and nothing else (design.md 6, 8.1, 8.3)'
);

-- ---------------------------------------------------------------------------
-- NAV-003 adds the exact private preview guard to leads and member_imports,
-- alongside their shared updated_at triggers. This guard refuses a write and
-- does not write audit rows. Keep exact trigger identities, never just a count.
--
-- Phase 2 changes this for the other three tables and the scope of the
-- assertion narrows with it, rather than the assertion being deleted.
-- platform_users gains the session-revocation and role-change trigger
-- (design.md 7) and impersonation_sessions gains the audit-row trigger
-- (design.md 6), so both are excluded here and covered by name in
-- 14_impersonation and 15_identity_triggers. audit_log itself must still carry
-- nothing — a trigger on the audit table is how an append-only log stops being
-- one — and it stays in the list for exactly that reason.
-- ---------------------------------------------------------------------------

select results_eq(
  $q$select c.relname::text collate "default", t.tgname::text collate "default"
       from pg_trigger t
       join pg_class c on c.oid = t.tgrelid
       join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and c.relname in ('audit_log', 'leads', 'member_imports')
      order by 1, 2$q$,
  $q$values ('leads'::text, 'leads_preview_read_only'::text),
           ('leads'::text, 'leads_preview_write_guard'::text),
           ('leads'::text, 'leads_touch_updated_at'::text),
           ('member_imports'::text, 'member_imports_preview_read_only'::text),
           ('member_imports'::text, 'member_imports_preview_write_guard'::text),
           ('member_imports'::text, 'member_imports_touch_updated_at'::text)$q$,
  'NAV-003: leads and member_imports carry exactly their updated_at and preview guards -- both gain the statement-level preview_write_guard because the tenant policies filter a preview session''s writes to zero rows, so the row-level guard never fires for one (ADR-118, extended to member_imports by the Phase 6 import migration''s own preview-read exclusion); audit_log remains trigger-free'
);

-- The action format is `<record_type>.<verb>`, both halves lowercase. The
-- empty and dotless cases are asserted in 10_platform_shape.sql; the
-- mixed-case one is not, and a regex anchored only at the start would let it
-- through.
select throws_ok(
  $q$insert into public.audit_log (tenant_id, action, record_type)
     values (null, 'Payment.Refunded', 'payment')$q$,
  '23514', null,
  'an audit action that is not lowercase snake_case is rejected (INT-003, docs/data-model.md Audit rows)'
);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner. The contract forbids `force row level
-- security`, so postgres bypasses RLS here and every isolation assertion
-- below is made after switching role.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'Gym A', 'PLTRLA'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'Gym B', 'PLTRLB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'A Main', true),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'B Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000002'::uuid, 'front_desk', 'A Desk'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000002'::uuid, 'front_desk', 'B Desk');

-- platform_users.user_id references auth.users(id). These three rows are
-- created inside the same transaction the file rolls back, so nothing of them
-- survives on the shared Cloud project.
insert into auth.users (id) values
  ('a0000000-0000-4000-8000-000000000010'::uuid),
  ('a0000000-0000-4000-8000-000000000011'::uuid),
  ('a0000000-0000-4000-8000-000000000012'::uuid);

insert into public.platform_users (user_id, role, full_name, email) values
  ('a0000000-0000-4000-8000-000000000010'::uuid, 'super_admin', 'Platform Root', 'root.rls@gymloop.test');

-- Both rows name the same actor and BOTH are ended, and the second half of
-- that is not tidiness.
--
-- design.md section 6 puts a partial unique index on `actor_user_id where
-- ended_at is null`, so one actor may hold at most one OPEN session -- which is
-- why the gym A row is ended. The gym B row is ended for a different and
-- sharper reason: while a session is live, the hook gives its actor
-- `app_role = gym_owner`, never `super_admin`. A later assertion in this file
-- acts as super_admin with `sub` set to this actor, and if either row were
-- still open that claim set could not be minted -- the assertion would be
-- testing a token that does not occur. With both ended it is exactly what the
-- hook returns for this user. (A blind critic found that shape in
-- 14_impersonation, where it hid an operation nobody could perform;
-- 14_impersonation now owns the reachable end-a-session path in full.)
insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at, ended_at) values
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'Gym A raised a billing dispute',
   timestamptz '2026-09-06 10:00:00+05:30', timestamptz '2026-09-06 11:00:00+05:30',
   timestamptz '2026-09-06 10:45:00+05:30'),
  ('b0000000-0000-4000-8000-000000000004'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'Gym B onboarding support',
   timestamptz '2026-09-06 12:00:00+05:30', timestamptz '2026-09-06 13:00:00+05:30',
   timestamptz '2026-09-06 12:45:00+05:30');

-- Three audit rows: one per gym, plus one platform-level row whose tenant_id
-- is null (ADR-033's second exemption).
insert into public.audit_log (id, tenant_id, actor_user_id, actor_role, action, record_type, record_id, occurred_at) values
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'super_admin', 'payment.refunded', 'payment',
   'a0000000-0000-4000-8000-000000000007'::uuid, timestamptz '2026-09-06 10:05:00+05:30'),
  ('b0000000-0000-4000-8000-000000000005'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'super_admin', 'payment.refunded', 'payment',
   'b0000000-0000-4000-8000-000000000007'::uuid, timestamptz '2026-09-06 12:05:00+05:30'),
  ('a0000000-0000-4000-8000-000000000006'::uuid, null,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'super_admin', 'platform_user.role_changed', 'platform_user',
   'a0000000-0000-4000-8000-000000000010'::uuid, timestamptz '2026-09-06 09:00:00+05:30');

insert into public.leads (id, tenant_id, branch_id, full_name, phone, source, stage) values
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000002'::uuid, 'A Enquiry', '+919876511101', 'walk_in', 'new'),
  ('b0000000-0000-4000-8000-000000000007'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000002'::uuid, 'B Enquiry', '+919876511102', 'referral', 'new');

insert into public.member_imports (id, tenant_id, uploaded_by_staff_id, file_name, column_mapping) values
  ('a0000000-0000-4000-8000-000000000008'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000003'::uuid, 'gym-a-members.csv', '{"A": "full_name"}'::jsonb),
  ('b0000000-0000-4000-8000-000000000008'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000003'::uuid, 'gym-b-members.csv', '{"A": "full_name"}'::jsonb);

-- ===========================================================================
-- Act as a signed-in owner of Gym A.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- --- leads: the ordinary tenant-scoped shape -------------------------------

select results_eq(
  $q$select id from public.leads
      where id in ('a0000000-0000-4000-8000-000000000007'::uuid,
                   'b0000000-0000-4000-8000-000000000007'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000007'::uuid)$q$,
  'as gym A, leads returns gym A rows and not gym B rows (gate 7, leads_tenant_select)'
);

with crossed as (
  update public.leads set notes = 'reached across the tenant line'
   where id = 'b0000000-0000-4000-8000-000000000007'::uuid
  returning 1
)
select is(
  (select count(*) from crossed), 0::bigint,
  'as gym A, updating a gym B lead affects zero rows — a policy filters, it does not raise (gate 7)'
);

-- The move outward, which zero-rows cannot see. docs/data-model.md gives it as
-- the second reason `with check` is not optional: without it a caller can insert
-- a row into another tenant "or move one there". Gym A's own lead is admitted by
-- the USING clause, so this update is not filtered; the new tenant_id is gym B's,
-- so the WITH CHECK fails and the statement RAISES 42501.
select throws_ok(
  $q$update public.leads set tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid
      where id = 'a0000000-0000-4000-8000-000000000007'::uuid$q$,
  '42501', null,
  'as gym A, moving its OWN lead into gym B raises 42501 from the with check rather than affecting zero rows (gate 7)'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('b0000000-0000-4000-8000-000000000001'::uuid,
             'b0000000-0000-4000-8000-000000000002'::uuid,
             'Planted Enquiry', '+919876511103', 'walk_in', 'new')$q$,
  '42501', null,
  'as gym A, inserting a lead carrying the gym B tenant id is rejected by with check (gate 7)'
);

-- The control that keeps the three assertions above honest: the same insert
-- into the same table, carrying gym A own tenant id, is allowed. Without it a
-- table with RLS enabled and a `with check (false)` policy would look correct.
select lives_ok(
  $q$insert into public.leads (id, tenant_id, branch_id, full_name, phone, source, stage)
     values ('a0000000-0000-4000-8000-000000000009'::uuid,
             'a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000002'::uuid,
             'Own Enquiry', '+919876511104', 'walk_in', 'new')$q$,
  'as gym A, inserting a lead carrying the gym A tenant id is allowed (docs/data-model.md, Row-Level Security)'
);

-- --- member_imports: the same shape ----------------------------------------

select results_eq(
  $q$select id from public.member_imports
      where id in ('a0000000-0000-4000-8000-000000000008'::uuid,
                   'b0000000-0000-4000-8000-000000000008'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000008'::uuid)$q$,
  'as gym A, member_imports returns gym A rows and not gym B rows (gate 7)'
);

with crossed as (
  update public.member_imports set file_name = 'stolen.csv'
   where id = 'b0000000-0000-4000-8000-000000000008'::uuid
  returning 1
)
select is(
  (select count(*) from crossed), 0::bigint,
  'as gym A, updating a gym B import run affects zero rows (gate 7)'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping)
     values ('b0000000-0000-4000-8000-000000000001'::uuid,
             'b0000000-0000-4000-8000-000000000003'::uuid,
             'planted.csv', '{"A": "full_name"}'::jsonb)$q$,
  '42501', null,
  'as gym A, inserting an import run carrying the gym B tenant id is rejected by with check (gate 7)'
);

-- --- platform_users: ADR-033 first exemption -------------------------------
-- The row inserted above exists (asserted under super_admin below). A gym
-- sees none of it: there is no tenant policy to match on, and the platform
-- branch is false for a gym-side role.

select is_empty(
  $q$select user_id from public.platform_users
      where user_id = 'a0000000-0000-4000-8000-000000000010'::uuid$q$,
  'as gym A, the platform roster returns zero rows although the row exists (spec: A gym owner reading the platform roster)'
);

select throws_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('a0000000-0000-4000-8000-000000000011'::uuid, 'platform_support', 'Planted Support', 'planted@gymloop.test')$q$,
  '42501', null,
  'as gym A, writing a platform user is rejected — no tenant policy to satisfy (ADR-033)'
);

-- --- impersonation_sessions: read yes, write no ----------------------------

select results_eq(
  $q$select id from public.impersonation_sessions
      where tenant_id = 'a0000000-0000-4000-8000-000000000001'::uuid$q$,
  $q$values ('a0000000-0000-4000-8000-000000000004'::uuid)$q$,
  'as gym A, the gym sees who impersonated it and when (spec: A gym reading its own impersonation history)'
);

select is_empty(
  $q$select id from public.impersonation_sessions
      where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid$q$,
  'as gym A, gym B impersonation history returns zero rows (spec: A gym reading another gym impersonation history)'
);

select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000010'::uuid,
             'Invented by the gym itself',
             timestamptz '2026-09-06 14:00:00+05:30',
             timestamptz '2026-09-06 15:00:00+05:30')$q$,
  '42501', null,
  'as gym A, inventing an impersonation session for gym A itself is rejected — the tenant policy is for select only (spec: A gym inventing an impersonation session)'
);

with crossed as (
  update public.impersonation_sessions set ended_at = now()
   where id = 'a0000000-0000-4000-8000-000000000004'::uuid
  returning 1
)
select is(
  (select count(*) from crossed), 0::bigint,
  'as gym A, altering its own impersonation session affects zero rows — no policy covers update (spec: a gym SHALL NOT alter one)'
);

-- --- audit_log: ADR-033 second exemption -----------------------------------

select results_eq(
  $q$select id from public.audit_log
      where id in ('a0000000-0000-4000-8000-000000000005'::uuid,
                   'b0000000-0000-4000-8000-000000000005'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000005'::uuid)$q$,
  'as gym A, an audit row tenanted to gym A is visible and one tenanted to gym B is not (INT-003)'
);

-- The arithmetic the contract relies on: `null = <uuid>` is null, not true,
-- so the platform-level row needs no second policy to stay hidden.
select is_empty(
  $q$select id from public.audit_log
      where id = 'a0000000-0000-4000-8000-000000000006'::uuid$q$,
  'as gym A, a platform-level audit row with a null tenant returns zero rows (spec: A gym reading a platform-level audit row, ADR-033)'
);

select throws_ok(
  $q$update public.audit_log set reason = 'rewritten by the gym'
      where id = 'a0000000-0000-4000-8000-000000000005'::uuid$q$,
  '42501', null,
  'as gym A, updating an audit row inside its own tenant is refused for want of privilege (spec: Editing an audit row)'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- Act as a signed-in super admin. No tenant claim: the platform branch is
-- what carries the read, not a tenant match.
-- ===========================================================================

-- `sub` is the actor, not a random uuid, for two reasons. design.md 6 gates
-- impersonation_sessions_platform_write on `actor_user_id = (select
-- auth.uid())`, and this block writes one of those rows further down. And the
-- claim set has to be one the hook would mint for THIS user: it holds no open
-- session (both fixture rows are ended above), so `super_admin` with no tenant
-- and no impersonation claim is precisely what it gets. Every other assertion
-- in the block is indifferent to `sub`.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', 'a0000000-0000-4000-8000-000000000010', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select results_eq(
  $q$select id from public.leads
      where id in ('a0000000-0000-4000-8000-000000000007'::uuid,
                   'b0000000-0000-4000-8000-000000000007'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000007'::uuid),
           ('b0000000-0000-4000-8000-000000000007'::uuid)$q$,
  'as super_admin, both gyms leads are visible (docs/security.md, a policy branch keyed on role)'
);

select results_eq(
  $q$select id from public.member_imports
      where id in ('a0000000-0000-4000-8000-000000000008'::uuid,
                   'b0000000-0000-4000-8000-000000000008'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000008'::uuid),
           ('b0000000-0000-4000-8000-000000000008'::uuid)$q$,
  'as super_admin, both gyms import runs are visible (docs/security.md, a policy branch keyed on role)'
);

select results_eq(
  $q$select user_id from public.platform_users
      where user_id = 'a0000000-0000-4000-8000-000000000010'::uuid$q$,
  $q$values ('a0000000-0000-4000-8000-000000000010'::uuid)$q$,
  'as super_admin, the platform roster is visible (spec: A platform role reading the platform roster)'
);

select lives_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('a0000000-0000-4000-8000-000000000012'::uuid, 'platform_support', 'New Support', 'support.rls@gymloop.test')$q$,
  'as super_admin, writing a platform user is allowed (ADR-033, platform_users_platform_write)'
);

select results_eq(
  $q$select id from public.impersonation_sessions
      where id in ('a0000000-0000-4000-8000-000000000004'::uuid,
                   'b0000000-0000-4000-8000-000000000004'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000004'::uuid),
           ('b0000000-0000-4000-8000-000000000004'::uuid)$q$,
  'as super_admin, both gyms impersonation sessions are visible (docs/security.md, Impersonation)'
);

with rewritten as (
  update public.impersonation_sessions set ended_at = timestamptz '2026-09-06 12:30:00+05:30'
   where id = 'b0000000-0000-4000-8000-000000000004'::uuid
  returning 1
)
select is(
  (select count(*) from rewritten), 1::bigint,
  'as super_admin, an impersonation session row is writable where the gym-side policy is select-only — impersonation_sessions_platform_write is `for all` and this actor satisfies both its terms, the super_admin role and actor_user_id = auth.uid() (design.md 8.1). The row is already ended, which is what makes the claim set mintable; the reachable path for ending a LIVE session belongs to its own impersonating token and is asserted in 14_impersonation'
);

select results_eq(
  $q$select id from public.audit_log
      where id in ('a0000000-0000-4000-8000-000000000005'::uuid,
                   'a0000000-0000-4000-8000-000000000006'::uuid,
                   'b0000000-0000-4000-8000-000000000005'::uuid)
      order by id$q$,
  $q$values ('a0000000-0000-4000-8000-000000000005'::uuid),
           ('a0000000-0000-4000-8000-000000000006'::uuid),
           ('b0000000-0000-4000-8000-000000000005'::uuid)$q$,
  'as super_admin, both tenanted audit rows and the platform-level one are visible (spec: A platform role reading the same row)'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- Act as a signed-in user carrying no claims at all. app.current_tenant_id()
-- is null and app.is_platform() is false, so both policy branches fail and OR
-- to false: zero rows, silently — never an error, or a caller could tell
-- "nothing here" apart from "wrong tenant".
-- ===========================================================================

set local role authenticated;

select is_empty(
  $q$select id from public.leads
      where id in ('a0000000-0000-4000-8000-000000000007'::uuid,
                   'b0000000-0000-4000-8000-000000000007'::uuid)$q$,
  'with no claims, leads returns zero rows and does not raise (docs/data-model.md, Row-Level Security)'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000002'::uuid,
             'Claimless Enquiry', '+919876511105', 'walk_in', 'new')$q$,
  '42501', null,
  'with no claims, inserting a lead is rejected by with check (gate 7)'
);

select is_empty(
  $q$select id from public.member_imports
      where id in ('a0000000-0000-4000-8000-000000000008'::uuid,
                   'b0000000-0000-4000-8000-000000000008'::uuid)$q$,
  'with no claims, member_imports returns zero rows and does not raise (docs/data-model.md, Row-Level Security)'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping)
     values ('a0000000-0000-4000-8000-000000000001'::uuid,
             'a0000000-0000-4000-8000-000000000003'::uuid,
             'claimless.csv', '{"A": "full_name"}'::jsonb)$q$,
  '42501', null,
  'with no claims, inserting an import run is rejected by with check (gate 7)'
);

select is_empty(
  $q$select user_id from public.platform_users
      where user_id in ('a0000000-0000-4000-8000-000000000010'::uuid,
                        'a0000000-0000-4000-8000-000000000012'::uuid)$q$,
  'with no claims, the platform roster returns zero rows and does not raise (ADR-033)'
);

select is_empty(
  $q$select id from public.impersonation_sessions
      where id in ('a0000000-0000-4000-8000-000000000004'::uuid,
                   'b0000000-0000-4000-8000-000000000004'::uuid)$q$,
  'with no claims, impersonation sessions return zero rows and do not raise (docs/security.md, Impersonation)'
);

select is_empty(
  $q$select id from public.audit_log
      where id in ('a0000000-0000-4000-8000-000000000005'::uuid,
                   'a0000000-0000-4000-8000-000000000006'::uuid,
                   'b0000000-0000-4000-8000-000000000005'::uuid)$q$,
  'with no claims, audit rows return zero rows including the platform-level one (INT-003, ADR-033)'
);

set local role postgres;

select * from finish();

rollback;
