-- 10_platform_shape.sql — cluster: platform.
--
-- Written from openspec/changes/0001-data-model/specs/platform/spec.md and
-- docs/data-model.md "Conventions (the contract)" + "Cluster: platform",
-- before the DDL exists (AGENTS.md rule 10). Shape, vocabularies, and every
-- "the write SHALL be rejected" scenario in the capability spec.
--
-- ADR-030: transaction-wrapped, never committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(30);

-- ---------------------------------------------------------------------------
-- Enums. Label order is part of the contract (docs/data-model.md, "Enums") —
-- it is what `supabase gen types` emits, so it is asserted, not just the set.
-- ---------------------------------------------------------------------------

select enum_has_labels(
  'public', 'lead_source',
  ARRAY['walk_in', 'referral', 'instagram', 'google', 'website', 'phone', 'other'],
  'lead_source carries the contract labels in contract order (ADR-021)'
);

select enum_has_labels(
  'public', 'lead_stage',
  ARRAY['new', 'contacted', 'trial_scheduled', 'trial_done', 'converted', 'lost'],
  'lead_stage carries the contract labels in contract order (ADR-021)'
);

select enum_has_labels(
  'public', 'import_status',
  ARRAY['pending', 'processing', 'completed', 'failed'],
  'import_status carries the contract labels in contract order (ADR-021)'
);

-- ---------------------------------------------------------------------------
-- The five tables exist.
-- ---------------------------------------------------------------------------

select has_table('public', 'platform_users', 'platform_users exists (ADR-033)');
select has_table('public', 'impersonation_sessions', 'impersonation_sessions exists (docs/security.md, Impersonation)');
select has_table('public', 'audit_log', 'audit_log exists (INT-003)');
select has_table('public', 'leads', 'leads exists');
select has_table('public', 'member_imports', 'member_imports exists');

-- platform_users is one of the five natural-key tables: its key is user_id and
-- it has no surrogate id (docs/data-model.md, "Every table").
select col_is_pk('public', 'platform_users', 'user_id', 'platform_users is keyed on user_id');
select hasnt_column('public', 'platform_users', 'id', 'platform_users has no surrogate id column');

-- ---------------------------------------------------------------------------
-- Fixtures. Inserted as postgres, which owns these tables and therefore
-- bypasses RLS (the contract forbids `force row level security`).
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code)
values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'Shape Gym', 'PLTSHA');

insert into public.branches (id, tenant_id, name, is_default)
values ('aaaaaaaa-0000-4000-8000-000000000002'::uuid,
        'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'Main', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name)
values ('aaaaaaaa-0000-4000-8000-000000000003'::uuid,
        'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
        'aaaaaaaa-0000-4000-8000-000000000002'::uuid, 'front_desk', 'Desk One');

insert into public.members (id, tenant_id, branch_id, full_name, phone)
values ('aaaaaaaa-0000-4000-8000-000000000004'::uuid,
        'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
        'aaaaaaaa-0000-4000-8000-000000000002'::uuid, 'Converted Member', '+919876500001');

insert into auth.users (id) values
  ('aaaaaaaa-0000-4000-8000-000000000005'::uuid),
  ('aaaaaaaa-0000-4000-8000-000000000015'::uuid),
  ('aaaaaaaa-0000-4000-8000-000000000025'::uuid);

insert into public.platform_users (user_id, role, full_name, email)
values ('aaaaaaaa-0000-4000-8000-000000000005'::uuid, 'super_admin', 'Root Admin', 'root@gymloop.test');

-- ---------------------------------------------------------------------------
-- Requirement: Platform accounts are visible only to the platform.
-- Scenario: A platform user with a gym-side role.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('aaaaaaaa-0000-4000-8000-000000000015'::uuid, 'platform_support', 'Support One', 'support@gymloop.test')$q$,
  'platform_users accepts platform_support (ADR-033, ADR-031)'
);

select throws_ok(
  $q$insert into public.platform_users (user_id, role, full_name, email)
     values ('aaaaaaaa-0000-4000-8000-000000000025'::uuid, 'gym_owner', 'Impostor', 'impostor@gymloop.test')$q$,
  '23514', null,
  'a platform user with a gym-side role is rejected (spec: A platform user with a gym-side role)'
);

-- ---------------------------------------------------------------------------
-- Requirement: An impersonation session always has a reason and an expiry.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.impersonation_sessions (id, tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('aaaaaaaa-0000-4000-8000-000000000006'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
             'Billing dispute raised by the owner',
             timestamptz '2026-09-06 10:00:00+05:30',
             timestamptz '2026-09-06 11:00:00+05:30')$q$,
  'an impersonation session with a reason and a later expiry is accepted (docs/security.md, Impersonation)'
);

select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
             '',
             timestamptz '2026-09-06 10:00:00+05:30',
             timestamptz '2026-09-06 11:00:00+05:30')$q$,
  '23514', null,
  'an impersonation session with an empty reason is rejected (spec: A session with no stated reason)'
);

select throws_ok(
  $q$insert into public.impersonation_sessions (tenant_id, actor_user_id, reason, started_at, expires_at)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
             'Indefinite support session',
             timestamptz '2026-09-06 10:00:00+05:30',
             timestamptz '2026-09-06 10:00:00+05:30')$q$,
  '23514', null,
  'an impersonation session whose expiry is not after its start is rejected (spec: A session that never expires)'
);

-- ---------------------------------------------------------------------------
-- Requirement: The audit log is append-only and carries actor, action,
-- record and time. Phase 1 creates the table and nothing writes to it
-- (docs/data-model.md, "Audit rows") — these assert the shape a Phase 3+
-- writer will fill, never that a trigger fires.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.audit_log
       (tenant_id, actor_user_id, actor_role, impersonation_session_id,
        action, record_type, record_id, before, after, reason, occurred_at)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
             'super_admin',
             'aaaaaaaa-0000-4000-8000-000000000006'::uuid,
             'impersonation_session.started', 'impersonation_session',
             'aaaaaaaa-0000-4000-8000-000000000006'::uuid,
             '{"ended_at": null}'::jsonb, '{"ended_at": null}'::jsonb,
             'Billing dispute raised by the owner',
             timestamptz '2026-09-06 10:00:00+05:30')$q$,
  'audit_log carries actor, actor role, action, record type, record id, before/after and a timestamp (INT-003)'
);

select throws_ok(
  $q$insert into public.audit_log (tenant_id, action, record_type)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid, '', 'payment')$q$,
  '23514', null,
  'an audit row with an empty action is rejected (spec: An audit row with no action)'
);

select throws_ok(
  $q$insert into public.audit_log (tenant_id, action, record_type)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'refunded', 'payment')$q$,
  '23514', null,
  'an audit action with no dot is rejected — action is <record_type>.<verb> (INT-003)'
);

select throws_ok(
  $q$insert into public.audit_log (tenant_id, action, record_type)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'payment.refunded', '')$q$,
  '23514', null,
  'an audit row with an empty record type is rejected (INT-003)'
);

-- ---------------------------------------------------------------------------
-- Requirement: A converted lead names the member it became.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Walk-in Enquiry', '+919876500002', 'walk_in', 'new')$q$,
  'a new lead with an E.164 phone and a vocabulary source is accepted'
);

select lives_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage, converted_member_id, converted_at)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Converted Enquiry', '+919876500003', 'referral', 'converted',
             'aaaaaaaa-0000-4000-8000-000000000004'::uuid,
             timestamptz '2026-09-06 10:00:00+05:30')$q$,
  'a converted lead that names its member is accepted'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Ghost Conversion', '+919876500004', 'walk_in', 'converted')$q$,
  '23514', null,
  'a converted lead with no converted member is rejected (spec: A converted lead with no member)'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Billboard Enquiry', '+919876500005', 'billboard', 'new')$q$,
  '22P02', null,
  'a lead source outside the vocabulary is rejected (spec: A lead source outside the vocabulary)'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Nurtured Enquiry', '+919876500006', 'walk_in', 'nurturing')$q$,
  '22P02', null,
  'a lead stage outside the vocabulary is rejected (spec: source and stage are constrained to their enums)'
);

select throws_ok(
  $q$insert into public.leads (tenant_id, branch_id, full_name, phone, source, stage)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
             'Local Number', '9876500007', 'walk_in', 'new')$q$,
  '23514', null,
  'a lead phone that is not E.164 is rejected (spec: A lead phone number that is not E.164)'
);

-- ---------------------------------------------------------------------------
-- Requirement: An import run records its mapping and its duplicate report.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.member_imports
       (tenant_id, uploaded_by_staff_id, file_name, column_mapping, status,
        row_count, imported_count, duplicate_count)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
             'members-sep.csv', '{"A": "full_name", "B": "phone"}'::jsonb, 'completed',
             120, 118, 2)$q$,
  'an import run records the uploading staff member, the column mapping and its counts'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping, row_count)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
             'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'a negative row count is rejected (spec: counts of rows read, rows imported and duplicates found are non-negative)'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping, imported_count)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
             'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'a negative imported count is rejected (spec: counts are non-negative)'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping, duplicate_count)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid,
             'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
             'bad.csv', '{}'::jsonb, -1)$q$,
  '23514', null,
  'a negative duplicate count is rejected (spec: A negative duplicate count)'
);

select throws_ok(
  $q$insert into public.member_imports (tenant_id, uploaded_by_staff_id, file_name, column_mapping)
     values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid, null, 'orphan.csv', '{}'::jsonb)$q$,
  '23502', null,
  'an import run with no uploading staff member is rejected (spec: An import by nobody)'
);

select * from finish();

rollback;
