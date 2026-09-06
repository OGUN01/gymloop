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
--   audit_log                   nullable tenant_id, append-only by privilege
--
-- ADR-030: transaction-wrapped, never committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(39);

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
  has_table_privilege('authenticated', 'public.audit_log', 'INSERT'),
  'authenticated holds INSERT on audit_log (INT-003 storage is appendable)'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'UPDATE'),
  'authenticated holds no UPDATE on audit_log — append-only is a privilege (spec: Editing an audit row)'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_log', 'DELETE'),
  'authenticated holds no DELETE on audit_log — INT-001 covers audit rows too (spec: Deleting an audit row)'
);

-- ---------------------------------------------------------------------------
-- Policy inventory. Both exceptions to the two-policy template live here, and
-- the exception is the point: a stray tenant policy on platform_users, or an
-- `impersonation_sessions_tenant_all` in place of the select-only one, would
-- pass a behaviour test that only ever read.
-- ---------------------------------------------------------------------------

select policies_are(
  'public', 'platform_users',
  ARRAY['platform_users_platform_all'],
  'platform_users carries only the platform policy and no tenant policy (ADR-033)'
);

select policies_are(
  'public', 'impersonation_sessions',
  ARRAY['impersonation_sessions_tenant_select', 'impersonation_sessions_platform_all'],
  'impersonation_sessions carries a select-only tenant policy beside the platform one (docs/data-model.md, Row-Level Security)'
);

-- ---------------------------------------------------------------------------
-- Nothing writes to audit_log in Phase 1 (docs/data-model.md, "Audit rows"):
-- no audit trigger, no writer function. The only trigger this cluster may
-- carry is the shared updated_at one, on the three tables that have an
-- updated_at column — impersonation_sessions and audit_log have none, so they
-- carry no trigger at all. An agent that built Phase 3 early fails here.
-- ---------------------------------------------------------------------------

select results_eq(
  $q$select c.relname::text collate "default", t.tgname::text collate "default"
       from pg_trigger t
       join pg_class c on c.oid = t.tgrelid
       join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and c.relname in ('platform_users', 'impersonation_sessions', 'audit_log', 'leads', 'member_imports')
      order by 1, 2$q$,
  $q$values ('leads'::text, 'leads_touch_updated_at'::text),
           ('member_imports'::text, 'member_imports_touch_updated_at'::text),
           ('platform_users'::text, 'platform_users_touch_updated_at'::text)$q$,
  'the platform cluster carries no trigger beyond the shared updated_at ones — no audit trigger in Phase 1 (docs/data-model.md, Audit rows)'
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

insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at) values
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'Gym A raised a billing dispute',
   timestamptz '2026-09-06 10:00:00+05:30', timestamptz '2026-09-06 11:00:00+05:30'),
  ('b0000000-0000-4000-8000-000000000004'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000010'::uuid, 'Gym B onboarding support',
   timestamptz '2026-09-06 12:00:00+05:30', timestamptz '2026-09-06 13:00:00+05:30');

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
  'as gym A, leads returns gym A rows and not gym B rows (gate 7, leads_tenant_all)'
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

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
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
  'as super_admin, writing a platform user is allowed (ADR-033, platform_users_platform_all)'
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

with ended as (
  update public.impersonation_sessions set ended_at = timestamptz '2026-09-06 12:30:00+05:30'
   where id = 'b0000000-0000-4000-8000-000000000004'::uuid
  returning 1
)
select is(
  (select count(*) from ended), 1::bigint,
  'as super_admin, an impersonation session is writable — the platform policy is for all (docs/data-model.md, Row-Level Security)'
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
