-- 03_tenancy_constraints — the behavioural rules of the tenancy cluster.
--
-- Answers openspec/changes/0001-data-model/specs/tenancy/spec.md, requirements
-- "The organisation hierarchy exists from day one", "The role vocabulary is a
-- database enum", "A member's identifying details are unique within their gym
-- and never include a government ID" and "Erasure blanks personal data without
-- destroying the row".
--
-- SQLSTATEs per docs/data-model.md, "How a pgTAP test assumes a role":
-- 23505 unique violation, 23503 foreign-key violation, 23514 check violation,
-- 22P02 malformed input for a type.
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

select plan(19);

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'Gym A', 'GYMAAA'),
  ('00000000-0000-4000-8000-0000000000b1'::uuid, 'Gym B', 'GYMBBB');

insert into public.branches (id, tenant_id, name, is_default)
values ('00000000-0000-4000-8000-0000000000a2'::uuid,
        '00000000-0000-4000-8000-0000000000a1'::uuid, 'Main', true);

-- ---------------------------------------------------------------------------
-- Exactly one default branch per organisation; names unique inside one gym
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.branches (tenant_id, name, is_default)
    values ('00000000-0000-4000-8000-0000000000a1', 'Second', true)$$,
  '23505', null,
  'spec "A second default branch": the partial unique index allows one default branch per organisation'
);

select lives_ok(
  $$insert into public.branches (tenant_id, name, is_default)
    values ('00000000-0000-4000-8000-0000000000a1', 'Second', false)$$,
  'spec "The organisation hierarchy exists from day one": a gym may hold more than one branch'
);

select lives_ok(
  $$insert into public.branches (id, tenant_id, name, is_default)
    values ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b1', 'Main', true)$$,
  'spec "A second default branch": the constraint is per organisation, so gym B keeps its own default branch and may reuse gym A''s branch name'
);

select throws_ok(
  $$insert into public.branches (tenant_id, name) values ('00000000-0000-4000-8000-0000000000a1', 'Main')$$,
  '23505', null,
  'spec "The organisation hierarchy exists from day one": branch names are unique within one organisation'
);

select throws_ok(
  $$insert into public.organizations (name, gym_code) values ('Copycat Gym', 'GYMAAA')$$,
  '23505', null,
  'spec "A gym code is globally unique": the second write is rejected'
);

select throws_ok(
  $$insert into public.branches (tenant_id, name)
    values ('00000000-0000-4000-8000-00000000dead', 'Orphan')$$,
  '23503', null,
  'gate 6: tenant_id is a foreign key to organizations, so a branch cannot name a gym that does not exist'
);

-- ---------------------------------------------------------------------------
-- Member identity: unique phone inside one gym, E.164, unique member code
-- ---------------------------------------------------------------------------

insert into public.members (id, tenant_id, branch_id, full_name, phone, member_code)
values ('00000000-0000-4000-8000-0000000000a4'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
        '00000000-0000-4000-8000-0000000000a2'::uuid, 'Amit A', '+919876543210', 'M001');

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'Amit Again', '+919876543210')$$,
  '23505', null,
  'spec "A duplicate phone within one gym": the CSV import''s duplicate-phone detection is a database constraint'
);

select lives_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2',
            'Amit Elsewhere', '+919876543210')$$,
  'spec "The same phone number at a different gym": uniqueness is scoped to the tenant'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'No Country Code', '9876543210')$$,
  '23514', null,
  'spec "A malformed phone number": member phones are stored in E.164 form'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone, member_code)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'Code Clash', '+919876543296', 'M001')$$,
  '23505', null,
  'the gym-visible member code the front desk searches on is unique within the gym'
);

select lives_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone) values
      ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', 'No Code One', '+919876543297'),
      ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', 'No Code Two', '+919876543298')$$,
  'the member-code index is partial, so many members may carry no code at all'
);

-- ---------------------------------------------------------------------------
-- The role vocabulary, and the gym-side subset of it
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name)
    values ('00000000-0000-4000-8000-0000000000a1', 'super_admin', 'Sneaky Admin')$$,
  '23514', null,
  'spec "A gym-side staff row cannot hold a platform role": super_admin is refused by the check'
);

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name)
    values ('00000000-0000-4000-8000-0000000000a1', 'platform_support', 'Sneaky Support')$$,
  '23514', null,
  'spec "A gym-side staff row cannot hold a platform role": platform_support is the second platform role'
);

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name)
    values ('00000000-0000-4000-8000-0000000000a1', 'head_honcho', 'Invented Role')$$,
  '22P02', null,
  'spec "An invalid role label" / ADR-031: the enum, not a text column, is what refuses an unknown role'
);

-- ---------------------------------------------------------------------------
-- Erasure keeps the row (DPD-006, INT-001)
-- ---------------------------------------------------------------------------

select lives_ok(
  $$update public.members
       set erased_at = now(), email = null, notes = null, photo_url = null,
           member_code = null, gender = null, date_of_birth = null
     where id = '00000000-0000-4000-8000-0000000000a4'$$,
  'spec "An erased member is still referenced" / DPD-006: the personal columns are nullable so they can be blanked'
);

select is(
  (select count(*) from public.members where id = '00000000-0000-4000-8000-0000000000a4'::uuid),
  1::bigint,
  'spec "An erased member is still referenced" / INT-001: the row itself survives erasure'
);

-- ---------------------------------------------------------------------------
-- The one shared updated_at trigger, and only that trigger
-- ---------------------------------------------------------------------------

insert into public.members (id, tenant_id, branch_id, full_name, phone, created_at, updated_at)
values ('00000000-0000-4000-8000-0000000000a6'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
        '00000000-0000-4000-8000-0000000000a2'::uuid, 'Timestamp Probe', '+919876543299',
        '2020-01-01 00:00:00+05:30'::timestamptz, '2020-01-01 00:00:00+05:30'::timestamptz);

update public.members set full_name = 'Timestamp Probe Renamed'
where id = '00000000-0000-4000-8000-0000000000a6'::uuid;

select is(
  (select updated_at from public.members where id = '00000000-0000-4000-8000-0000000000a6'::uuid),
  now(),
  'the shared app.touch_updated_at trigger moves updated_at on every update, and application code never does'
);

select is(
  (select created_at from public.members where id = '00000000-0000-4000-8000-0000000000a6'::uuid),
  '2020-01-01 00:00:00+05:30'::timestamptz,
  'created_at records when the row was inserted and is never rewritten by the trigger'
);

select is_empty(
  $$select t.name
      from unnest(array['organizations', 'organization_settings', 'branches', 'staff', 'members']) as t(name)
     where not exists (
       select 1 from pg_trigger g
        where g.tgrelid = ('public.' || t.name)::regclass
          and g.tgname = t.name || '_touch_updated_at'
          and not g.tgisinternal
     )$$,
  'every tenancy table carrying updated_at carries the one shared <table>_touch_updated_at trigger'
);

select * from finish();

rollback;
