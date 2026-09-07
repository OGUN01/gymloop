-- 02_tenancy_rls — cross-tenant isolation for the five tenancy tables.
--
-- Answers openspec/changes/0001-data-model/specs/tenancy/spec.md, requirements
-- "A missing tenant claim grants nothing", "One gym can never reach another
-- gym's rows" and "Platform roles cross tenants by policy, never by disabling
-- RLS" (gate 7, gate 8).
--
-- Role shape is verbatim from docs/data-model.md, "How a pgTAP test assumes a
-- role": fixtures are inserted as the owner, which holds BYPASSRLS; isolation
-- is asserted after `set local role authenticated`. An RLS policy filters on
-- select and update (assert zero rows) and raises 42501 from a failing
-- `with check` on insert.
--
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(36);

-- ---------------------------------------------------------------------------
-- Two gyms, fully populated, inserted as the owner
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'Gym A', 'GYMAAA'),
  ('00000000-0000-4000-8000-0000000000b1'::uuid, 'Gym B', 'GYMBBB');

insert into public.organization_settings (tenant_id) values
  ('00000000-0000-4000-8000-0000000000a1'::uuid),
  ('00000000-0000-4000-8000-0000000000b1'::uuid);

insert into public.branches (id, tenant_id, name, is_default) values
  ('00000000-0000-4000-8000-0000000000a2'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'Branch A', true),
  ('00000000-0000-4000-8000-0000000000b2'::uuid, '00000000-0000-4000-8000-0000000000b1'::uuid, 'Branch B', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('00000000-0000-4000-8000-0000000000a3'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
   '00000000-0000-4000-8000-0000000000a2'::uuid, 'gym_owner', 'Alice A'),
  ('00000000-0000-4000-8000-0000000000b3'::uuid, '00000000-0000-4000-8000-0000000000b1'::uuid,
   '00000000-0000-4000-8000-0000000000b2'::uuid, 'gym_owner', 'Bhavna B');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('00000000-0000-4000-8000-0000000000a4'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
   '00000000-0000-4000-8000-0000000000a2'::uuid, 'Amit A', '+919876543210'),
  ('00000000-0000-4000-8000-0000000000b4'::uuid, '00000000-0000-4000-8000-0000000000b1'::uuid,
   '00000000-0000-4000-8000-0000000000b2'::uuid, 'Bina B', '+919876543211');

-- ---------------------------------------------------------------------------
-- No JWT claim at all. The GUC has never been set in this transaction, which
-- is the case a caller with a hook-less token actually presents.
-- ---------------------------------------------------------------------------

set local role authenticated;

select lives_ok(
  $$select count(*) from public.members$$,
  'spec "Reading with no claim at all": a claimless read does not raise'
);

select is_empty(
  $$select 1 from public.members$$,
  'spec "Reading with no claim at all": a claimless read of members returns zero rows'
);

select is_empty(
  $$select 1 from public.organizations$$,
  'spec "Reading with no claim at all": organizations compares id, and a claimless read still returns zero rows'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'Claimless', '+919000000001')$$,
  '42501', null,
  'spec "Writing with no claim at all": the row-security check rejects a claimless insert'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- An empty claim string, the other half of "a missing tenant claim"
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select is_empty(
  $$select 1 from public.members$$,
  'spec "A missing tenant claim grants nothing": an empty claim string returns zero members'
);

select is_empty(
  $$select 1 from public.branches$$,
  'spec "A missing tenant claim grants nothing": an empty claim string returns zero branches'
);

select is_empty(
  $$select 1 from public.organization_settings$$,
  'spec "A missing tenant claim grants nothing": an empty claim string returns zero settings rows'
);

select lives_ok(
  $$select count(*) from public.staff$$,
  'spec "A missing tenant claim grants nothing": an empty claim string does not raise'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2',
            'Empty Claim', '+919000000002')$$,
  '42501', null,
  'spec "A missing tenant claim grants nothing": an empty claim string cannot insert'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- Acting as a gym_owner of gym A
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-0000000000a1',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select results_eq(
  $$select gym_code from public.organizations order by 1$$,
  $$values ('GYMAAA'::text)$$,
  'spec "Reading across tenants": the organizations policy compares id, so gym A sees only itself'
);

select results_eq(
  $$select name from public.branches order by 1$$,
  $$values ('Branch A'::text)$$,
  'spec "Reading across tenants": branches'
);

select results_eq(
  $$select full_name from public.staff order by 1$$,
  $$values ('Alice A'::text)$$,
  'spec "Reading across tenants": staff'
);

select results_eq(
  $$select full_name from public.members order by 1$$,
  $$values ('Amit A'::text)$$,
  'spec "Reading across tenants": members'
);

select results_eq(
  $$select tenant_id from public.organization_settings order by 1$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'spec "Reading across tenants": organization_settings'
);

select is_empty(
  $$select 1 from public.members where id = '00000000-0000-4000-8000-0000000000b4'$$,
  'spec "Updating another tenant''s row": gym B''s row is invisible by primary key, so the same USING clause matches nothing to update'
);

select lives_ok(
  $$update public.members set full_name = 'hijacked' where id = '00000000-0000-4000-8000-0000000000b4'$$,
  'spec "Updating another tenant''s row": the policy filters the update rather than raising'
);

select lives_ok(
  $$update public.branches set name = 'hijacked' where tenant_id = '00000000-0000-4000-8000-0000000000b1'$$,
  'spec "Updating another tenant''s row": branches, filtered not raised'
);

-- organizations, organization_settings and staff all carry an UPDATE grant and
-- had no cross-tenant update assertion at all, unlike branches and members. A
-- policy filters an update, so the observable outcome is zero rows affected —
-- counted here rather than only asserted not to raise, because "did not raise"
-- is also what a successful hijack looks like.

with attempt as (
  update public.organizations set name = 'hijacked'
   where id = '00000000-0000-4000-8000-0000000000b1'
  returning 1
)
select is((select count(*) from attempt), 0::bigint,
  'spec "Updating another tenant''s row": organizations compares id, so gym A updating gym B by primary key affects zero rows');

with attempt as (
  update public.organization_settings set city = 'hijacked'
   where tenant_id = '00000000-0000-4000-8000-0000000000b1'
  returning 1
)
select is((select count(*) from attempt), 0::bigint,
  'spec "Updating another tenant''s row": organization_settings, keyed by tenant_id, affects zero rows');

with attempt as (
  update public.staff set full_name = 'hijacked'
   where id = '00000000-0000-4000-8000-0000000000b3'
  returning 1
)
select is((select count(*) from attempt), 0::bigint,
  'spec "Updating another tenant''s row": staff, affects zero rows');

-- The half of `with check` nothing in this suite covered: the contract says it
-- stops a caller inserting a row into another tenant "or moving one there".
-- The row below is gym A's own, so USING admits it and the update is not
-- filtered away; the NEW row carries gym B's tenant_id, so WITH CHECK fails and
-- the statement RAISES 42501 instead of affecting zero rows. A policy written
-- `with check (true)` beside a correct `using` would let it through.
select throws_ok(
  $$update public.members set tenant_id = '00000000-0000-4000-8000-0000000000b1'
     where id = '00000000-0000-4000-8000-0000000000a4'$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": gym A moving its OWN member row into gym B raises 42501 from the with check — the row is visible to the caller, so this is not a filtered update'
);

select throws_ok(
  $$insert into public.members (tenant_id, branch_id, full_name, phone)
    values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2',
            'Planted', '+919000000003')$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": members with check'
);

select throws_ok(
  $$insert into public.branches (tenant_id, name)
    values ('00000000-0000-4000-8000-0000000000b1', 'Planted Branch')$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": branches with check'
);

select throws_ok(
  $$insert into public.staff (tenant_id, role, full_name)
    values ('00000000-0000-4000-8000-0000000000b1', 'front_desk', 'Planted Staff')$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": staff with check'
);

select throws_ok(
  $$insert into public.organization_settings (tenant_id, city)
    values ('00000000-0000-4000-8000-0000000000b1', 'Planted City')$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": organization_settings with check'
);

select throws_ok(
  $$insert into public.organizations (name, gym_code) values ('Rogue Gym', 'ZZZZZZ')$$,
  '42501', null,
  'spec "Inserting a row labelled with another tenant": organizations with check compares id, so a gym cannot create a second tenant'
);

select throws_ok(
  $$delete from public.members where id = '00000000-0000-4000-8000-0000000000b4'$$,
  '42501', null,
  'spec "Deleting another tenant''s row" / INT-001: authenticated holds no delete privilege on members'
);

select throws_ok(
  $$delete from public.organizations where id = '00000000-0000-4000-8000-0000000000b1'$$,
  '42501', null,
  'spec "Deleting another tenant''s row" / INT-001: authenticated holds no delete privilege on organizations'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- Back as the owner: gym B is untouched by everything above
-- ---------------------------------------------------------------------------

select is(
  (select full_name from public.members where id = '00000000-0000-4000-8000-0000000000b4'::uuid),
  'Bina B',
  'spec "Updating another tenant''s row": gym B''s member row is unchanged'
);

select is(
  (select count(*) from public.members where id = '00000000-0000-4000-8000-0000000000b4'::uuid),
  1::bigint,
  'spec "Deleting another tenant''s row": gym B''s member row still exists'
);

select is(
  (select name from public.branches where id = '00000000-0000-4000-8000-0000000000b2'::uuid),
  'Branch B',
  'spec "Updating another tenant''s row": gym B''s branch row is unchanged'
);

-- ---------------------------------------------------------------------------
-- Platform roles cross tenants through the policy branch, with RLS still on
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-0000000000a1',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is(
  (select count(*) from public.organizations),
  2::bigint,
  'spec "A platform role reads every tenant": super_admin sees both gyms in organizations'
);

select is(
  (select count(*) from public.members),
  2::bigint,
  'spec "A platform role reads every tenant": super_admin sees both gyms'' members'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-0000000000a1',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select is(
  (select count(*) from public.members),
  2::bigint,
  'spec "A platform role reads every tenant": platform_support is the second platform role'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-0000000000a1',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select is(
  (select count(*) from public.members),
  1::bigint,
  'spec "A gym-side role is not a platform role": gym_owner stays inside its own tenant'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '00000000-0000-4000-8000-0000000000a1',
                    'app_role', 'front_desk')::text,
  true
);
set local role authenticated;

select is(
  (select count(*) from public.members),
  1::bigint,
  'spec "One gym can never reach another gym''s rows": isolation holds regardless of the caller''s role within gym A'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
