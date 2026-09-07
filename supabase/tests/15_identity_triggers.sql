-- 15_identity_triggers - the half of `is_active` and role changes that a claim
-- cannot cover: the tokens already issued.
--
-- Written from openspec/changes/phase-2-identity-and-tenancy/design.md
-- section 7 and .../specs/identity/spec.md ("Deactivation and role change
-- revoke the sessions already issued", "A role change writes an audit row"),
-- before the implementation exists (AGENTS.md rule 10).
--
-- WHY THE TRIGGER EXISTS AT ALL
--
-- A claim is a copy of a row taken at issue time. Deactivating a staff row
-- changes nothing about a token already sitting in a browser, and the default
-- access-token lifetime is an hour. Deleting the user's auth.sessions rows
-- invalidates the refresh token, so the access token in hand is the last one
-- that user will ever hold. The residual window between the trigger firing and
-- that token expiring is REAL, is named in design.md section 7, and is
-- deliberately not asserted here -- a test claiming otherwise would be testing
-- a fiction.
--
-- WHAT THIS FILE COVERS EXHAUSTIVELY, AND WHAT IT SAMPLES
--
-- Exhaustive: every transition design.md section 7 names, on all three
-- identity tables, plus the negative case beside each that keeps it honest.
--
--   platform_users, staff   is_active true -> false; a role change
--   members                 status -> cancelled; status -> blocked;
--                           erased_at set
--
-- and, as the controls: a staff update touching neither is_active nor role
-- revokes nothing and audits nothing, a member moving to `paused` revokes
-- nothing, and a user nobody touched keeps both sessions.
--
-- One assertion pins a deliberate decision rather than a requirement: a staff
-- member employed at two gyms and deactivated at one is signed out of BOTH,
-- because a session row carries no tenant and there is nothing to filter on.
-- design.md 7 states it explicitly so it is not later read as a bug, and it is
-- asserted here for the same reason -- the wider behaviour is also the right
-- one, since the deactivated identity may be the very tenant the current token
-- names.
--
-- `members` is where the contract's first draft was wrong -- it said
-- `is_active` for all three tables and members has no such column. The
-- distinction that replaced it is not cosmetic: `paused` and `expired` members
-- keep their sessions and `cancelled`, `blocked` and erased members lose them,
-- so an implementation that revoked on any status change would sign out every
-- member whose plan lapsed, which is the person the renewal loop exists to
-- bring back. The paused control is what catches that.
--
-- Also exhaustive: the audit rows, which design.md 7 now specifies column by
-- column as design.md 6 does for impersonation -- `action`, `record_type`,
-- `record_id`, `tenant_id`, `actor_user_id`, `actor_role` and the before/after
-- jsonb -- so nothing here is a guess at a vocabulary. Note the one difference
-- from section 6's trigger: THIS one runs under the caller's session, so
-- actor_user_id is auth.uid() and the claims blocks below set `sub` to a known
-- value rather than to a random uuid, which is what makes it assertable.
--
-- A deactivation is audited as well as a role change. INT-003 names only the
-- role change; design.md 7 adds the deactivation deliberately, on the grounds
-- that switching off a compromised platform account is the most
-- security-relevant write in the schema and a log recording promotions but not
-- revocations is inconsistent in the direction that matters.
--
-- Sampled: nothing.
--
-- Every write below is made through `authenticated` with the claims of the
-- role the matrix says may make it, not as the owner. That is deliberate:
-- design.md section 7 flags "that a security definer function owned by
-- postgres may delete from auth.sessions on this project is an assumption
-- until it is replayed against Cloud", and running the update as `postgres`
-- -- who holds DELETE on auth.sessions outright -- would prove nothing about
-- the case that actually happens.
--
-- ADR-050: every count is scoped to one named user or one named record.
-- ADR-030: one transaction, BEGIN ... ROLLBACK, nothing committed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

select plan(20);

-- ---------------------------------------------------------------------------
-- Fixtures. Six linked users, each with two authentication sessions, so that
-- "the sessions were deleted" is distinguishable from "there was one session
-- and something removed one row".
--
--   u1  staff, will be deactivated
--   u2  staff, will have its role changed
--   u4  staff, will be renamed -- the control
--   u3  platform_users, will be deactivated
--   u5  platform_users, will have its role changed
--   u6  staff, touched by nothing at all -- the control that catches a
--       revocation written without a WHERE clause
--   u7  member, will be cancelled
--   u8  member, will be blocked
--   u9  member, will be erased
--   ua  member, will be paused -- the control that keeps `cancelled or
--       blocked` from becoming `any status change`
--   ub  staff at BOTH gyms, deactivated at the first only
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('15000000-0000-4000-8000-000000000001'::uuid, 'Trigger Gym',   'TRIGGA'),
  ('15000000-0000-4000-8000-000000000002'::uuid, 'Trigger Gym 2', 'TRIGGB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-000000000001'::uuid, 'Main', true),
  ('15000000-0000-4000-8000-000000000012'::uuid, '15000000-0000-4000-8000-000000000002'::uuid, 'Main', true);

insert into auth.users (id) values
  ('15000000-0000-4000-8000-0000000000a1'::uuid),
  ('15000000-0000-4000-8000-0000000000a2'::uuid),
  ('15000000-0000-4000-8000-0000000000a3'::uuid),
  ('15000000-0000-4000-8000-0000000000a4'::uuid),
  ('15000000-0000-4000-8000-0000000000a5'::uuid),
  ('15000000-0000-4000-8000-0000000000a6'::uuid),
  ('15000000-0000-4000-8000-0000000000a7'::uuid),
  ('15000000-0000-4000-8000-0000000000a8'::uuid),
  ('15000000-0000-4000-8000-0000000000a9'::uuid),
  ('15000000-0000-4000-8000-0000000000aa'::uuid),
  ('15000000-0000-4000-8000-0000000000ab'::uuid);

insert into auth.sessions (id, user_id) values
  ('15000000-0000-4000-8000-0000000000b1'::uuid, '15000000-0000-4000-8000-0000000000a1'::uuid),
  ('15000000-0000-4000-8000-0000000000b2'::uuid, '15000000-0000-4000-8000-0000000000a1'::uuid),
  ('15000000-0000-4000-8000-0000000000b3'::uuid, '15000000-0000-4000-8000-0000000000a2'::uuid),
  ('15000000-0000-4000-8000-0000000000b4'::uuid, '15000000-0000-4000-8000-0000000000a2'::uuid),
  ('15000000-0000-4000-8000-0000000000b5'::uuid, '15000000-0000-4000-8000-0000000000a3'::uuid),
  ('15000000-0000-4000-8000-0000000000b6'::uuid, '15000000-0000-4000-8000-0000000000a3'::uuid),
  ('15000000-0000-4000-8000-0000000000b7'::uuid, '15000000-0000-4000-8000-0000000000a4'::uuid),
  ('15000000-0000-4000-8000-0000000000b8'::uuid, '15000000-0000-4000-8000-0000000000a4'::uuid),
  ('15000000-0000-4000-8000-0000000000b9'::uuid, '15000000-0000-4000-8000-0000000000a5'::uuid),
  ('15000000-0000-4000-8000-0000000000ba'::uuid, '15000000-0000-4000-8000-0000000000a5'::uuid),
  ('15000000-0000-4000-8000-0000000000bb'::uuid, '15000000-0000-4000-8000-0000000000a6'::uuid),
  ('15000000-0000-4000-8000-0000000000bc'::uuid, '15000000-0000-4000-8000-0000000000a6'::uuid),
  ('15000000-0000-4000-8000-0000000000bd'::uuid, '15000000-0000-4000-8000-0000000000a7'::uuid),
  ('15000000-0000-4000-8000-0000000000be'::uuid, '15000000-0000-4000-8000-0000000000a7'::uuid),
  ('15000000-0000-4000-8000-0000000000bf'::uuid, '15000000-0000-4000-8000-0000000000a8'::uuid),
  ('15000000-0000-4000-8000-0000000000c0'::uuid, '15000000-0000-4000-8000-0000000000a8'::uuid),
  ('15000000-0000-4000-8000-0000000000c1'::uuid, '15000000-0000-4000-8000-0000000000a9'::uuid),
  ('15000000-0000-4000-8000-0000000000c2'::uuid, '15000000-0000-4000-8000-0000000000a9'::uuid),
  ('15000000-0000-4000-8000-0000000000c3'::uuid, '15000000-0000-4000-8000-0000000000aa'::uuid),
  ('15000000-0000-4000-8000-0000000000c4'::uuid, '15000000-0000-4000-8000-0000000000aa'::uuid),
  ('15000000-0000-4000-8000-0000000000c5'::uuid, '15000000-0000-4000-8000-0000000000ab'::uuid),
  ('15000000-0000-4000-8000-0000000000c6'::uuid, '15000000-0000-4000-8000-0000000000ab'::uuid);

insert into public.staff (id, tenant_id, branch_id, user_id, role, full_name) values
  ('15000000-0000-4000-8000-000000000021'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a1'::uuid,
   'front_desk', 'To Be Dismissed'),
  ('15000000-0000-4000-8000-000000000022'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a2'::uuid,
   'front_desk', 'To Be Promoted'),
  ('15000000-0000-4000-8000-000000000024'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a4'::uuid,
   'trainer', 'To Be Renamed'),
  ('15000000-0000-4000-8000-000000000026'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a6'::uuid,
   'trainer', 'Untouched'),
  -- No linked user at all, which is the ordinary case: Phase 1's own fixtures
  -- create staff rows with a null user_id, and most gym staff never sign in.
  ('15000000-0000-4000-8000-000000000027'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, null,
   'front_desk', 'Never Signed In'),
  -- The same human, employed at both gyms. Only the first row is deactivated.
  ('15000000-0000-4000-8000-000000000028'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000ab'::uuid,
   'trainer', 'Two Gyms, Gym One'),
  ('15000000-0000-4000-8000-000000000029'::uuid, '15000000-0000-4000-8000-000000000002'::uuid,
   '15000000-0000-4000-8000-000000000012'::uuid, '15000000-0000-4000-8000-0000000000ab'::uuid,
   'trainer', 'Two Gyms, Gym Two');

-- Four members, all starting active and unerased, one per transition.
insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone) values
  ('15000000-0000-4000-8000-000000000031'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a7'::uuid,
   'To Be Cancelled', '+91150000031'),
  ('15000000-0000-4000-8000-000000000032'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a8'::uuid,
   'To Be Blocked',   '+91150000032'),
  ('15000000-0000-4000-8000-000000000033'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000a9'::uuid,
   'To Be Erased',    '+91150000033'),
  ('15000000-0000-4000-8000-000000000034'::uuid, '15000000-0000-4000-8000-000000000001'::uuid,
   '15000000-0000-4000-8000-000000000011'::uuid, '15000000-0000-4000-8000-0000000000aa'::uuid,
   'To Be Paused',    '+91150000034');

insert into public.platform_users (user_id, role, full_name, email) values
  ('15000000-0000-4000-8000-0000000000a3'::uuid, 'super_admin', 'To Be Deactivated', 'a3.15@gymloop.test'),
  ('15000000-0000-4000-8000-0000000000a5'::uuid, 'super_admin', 'To Be Demoted',     'a5.15@gymloop.test');

-- ---------------------------------------------------------------------------
-- 1. The triggers exist, on the two identity tables that carry both an
--    is_active column and a role column.
--
--    NOTE, and it is a finding rather than an omission: design.md section 7
--    says the trigger goes on "platform_users, staff and members", but
--    public.members has neither an is_active column nor a role column -- its
--    lifecycle is the member_status enum. There is no transition on members
--    this requirement can name, so none is asserted. See the report.
-- ---------------------------------------------------------------------------

select is_empty(
  $$select t.name
      from unnest(array['staff', 'platform_users', 'members']) as t(name)
     where not exists (
       select 1 from pg_trigger g
        where g.tgrelid = ('public.' || t.name)::regclass
          and not g.tgisinternal
          and g.tgname <> t.name || '_touch_updated_at'
     )$$,
  'design.md 7: all three identity tables carry a trigger beyond the shared updated_at one. Asserted as presence rather than by name, because the design fixes the behaviour and not the trigger''s name'
);

-- ---------------------------------------------------------------------------
-- The staff-side and member-side changes, made by the role the matrix says may
-- make them. A gym_owner claim is required: staff writes are gated `= gym_owner`
-- (design.md 8.3), so this is the real path and not a shortcut through the
-- owner role.
--
-- These are plain statements rather than assertions -- 13_role_matrix_write
-- already proves an owner may make them, and what this file is about is what
-- happens afterwards. An update that silently affected zero rows would show
-- up below as sessions that were never revoked.
-- ---------------------------------------------------------------------------

-- `sub` is a fixed value rather than a random uuid because design.md 7 makes
-- the audit row's actor_user_id auth.uid() -- this trigger, unlike section 6's,
-- runs under the caller's session -- and a random actor cannot be asserted.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '15000000-0000-4000-8000-0000000000f1', 'role', 'authenticated',
                    'tenant_id', '15000000-0000-4000-8000-000000000001',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

update public.staff set is_active = false
 where id = '15000000-0000-4000-8000-000000000021'::uuid;

update public.staff set role = 'gym_manager'
 where id = '15000000-0000-4000-8000-000000000022'::uuid;

update public.staff set full_name = 'Renamed, nothing else'
 where id = '15000000-0000-4000-8000-000000000024'::uuid;

-- The member side. gym_owner satisfies members' write gate, is_front_office().
update public.members set status = 'cancelled'
 where id = '15000000-0000-4000-8000-000000000031'::uuid;

update public.members set status = 'blocked'
 where id = '15000000-0000-4000-8000-000000000032'::uuid;

update public.members set erased_at = now()
 where id = '15000000-0000-4000-8000-000000000033'::uuid;

update public.members set status = 'paused'
 where id = '15000000-0000-4000-8000-000000000034'::uuid;

-- The multi-gym staff member, deactivated at gym A only. The gym_owner claim
-- is gym A's, so gym B's row is untouched and unreachable.
update public.staff set is_active = false
 where id = '15000000-0000-4000-8000-000000000028'::uuid;

-- ---------------------------------------------------------------------------
-- 2-7. The audit side, read here because a gym_owner reads audit_log
--      (is_gym_admin, design.md 8.3) and because reading it as the owner is
--      one more proof the row was written with the gym's tenant on it.
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-000000000022'::uuid
      and action = 'staff.role_changed'
      and record_type = 'staff'
      and tenant_id = '15000000-0000-4000-8000-000000000001'::uuid
      and actor_user_id = '15000000-0000-4000-8000-0000000000f1'::uuid
      and actor_role = 'gym_owner'
      and before ->> 'role' = 'front_desk'
      and after  ->> 'role' = 'gym_manager'),
  1::bigint,
  'spec "A role change is audited" / INT-003 / design.md 7, column by column: one audit_log row for the staff record. actor_user_id is auth.uid() -- unlike section 6''s impersonation trigger, this one runs under the caller''s session and there IS a JWT to read. The caller did not ask for the row and could not have written it: audit_log withholds INSERT from authenticated (ADR-049)'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-000000000021'::uuid
      and action = 'staff.deactivated'
      and record_type = 'staff'
      and before ->> 'is_active' = 'true'
      and after  ->> 'is_active' = 'false'),
  1::bigint,
  'spec "Deactivating a staff member is audited" / design.md 7: INT-003 names a role change and not a deactivation, and this row is a deliberate addition -- switching off a compromised account is the most security-relevant write in the schema, and a log that records a promotion but not a revocation is inconsistent in the direction that matters'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-000000000024'::uuid),
  0::bigint,
  'spec "An unrelated update revokes nothing": renaming a staff member is not an audited event, so the trigger writes nothing. A trigger that audits every update turns audit_log into a change log and INT-003 into noise'
);

select lives_ok(
  $$update public.staff set is_active = false
     where id = '15000000-0000-4000-8000-000000000027'$$,
  'design.md 7: deactivating a staff row with a NULL user_id -- the ordinary case, since most gym staff never sign in -- must not raise. A revocation written without allowing for it fails on the majority of rows'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-000000000031'::uuid
      and action = 'member.deactivated'
      and record_type = 'member'
      and tenant_id = '15000000-0000-4000-8000-000000000001'::uuid
      and after ->> 'status' = 'cancelled'),
  1::bigint,
  'spec "Cancelling a member is audited" / design.md 7: the member''s deactivation row carries the status that changed, since a member has no is_active to report'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-000000000031'::uuid
      and ((before ->> 'role') is not null or (after ->> 'role') is not null)),
  0::bigint,
  'design.md 7: members carries no role column, so cancelling a member writes a deactivation row and NO role-change row. "That asymmetry is real and is not an omission" -- and an implementation that generalised the staff trigger over all three tables would either invent a role for members or fail on a column that does not exist'
);

set local role postgres;

-- ---------------------------------------------------------------------------
-- 8-14. The session side. auth.sessions is not readable by `authenticated` at
--       all, so these are asserted as the owner, scoped to one user each.
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a1'::uuid),
  0::bigint,
  'spec "Deactivating a staff member": the user held two sessions and holds none. Deleting the session invalidates the refresh token, so the access token in hand is the last one that user receives'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a2'::uuid),
  0::bigint,
  'spec "Changing a staff member''s role": a role change counts as well as a deactivation, because a stale app_role claim is a stale privilege -- front_desk promoted to gym_manager must not keep reading with the old claim, and neither must the reverse'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a4'::uuid),
  2::bigint,
  'spec "An unrelated update revokes nothing": the renamed staff member keeps both sessions. Without this, a trigger that fires on every UPDATE would pass all three assertions above and sign the whole gym out on every edit'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a6'::uuid),
  2::bigint,
  'design.md 7: the untouched user keeps both sessions. This is the assertion that fails if the revocation was written without a WHERE clause -- which would pass every other assertion in this file'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000ab'::uuid),
  0::bigint,
  'design.md 7, pinning a deliberate decision rather than a requirement: this user is employed at TWO gyms and was deactivated at one, and holds no session at either. There is no narrower option -- a session row carries no tenant, so there is nothing to filter on -- and the wider behaviour is also the right one, because the deactivated identity may be the very tenant the current token names, and the only way to be sure the next token''s claims are correct is to force it to be minted. The cost is one re-authentication at the other gym'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a7'::uuid),
  0::bigint,
  'spec "Cancelling a member": `cancelled` is one of the two statuses that mean the gym has ended the relationship, so the member''s sessions go with it'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a8'::uuid),
  0::bigint,
  'design.md 4 and 7: `blocked` is the other one'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a9'::uuid),
  0::bigint,
  'DPD-006 / design.md 7: setting erased_at revokes, although the status is still `active`. The row survives for the financial history that references it, and the person does not keep a session -- so a trigger watching status alone leaves an erased member signed in'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000aa'::uuid),
  2::bigint,
  'spec "Pausing a member revokes nothing": this is the control that stops "cancelled or blocked" being implemented as "any status change". A paused member signs in normally -- and so does an expired one, which is the whole renewal loop. Without this assertion, a trigger firing on every status transition passes all three above'
);

-- ---------------------------------------------------------------------------
-- 16-20. The same two transitions on platform_users, made as super_admin,
--        which is the only role its policy admits (design.md 8.1).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '15000000-0000-4000-8000-0000000000f2', 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

update public.platform_users set is_active = false
 where user_id = '15000000-0000-4000-8000-0000000000a3'::uuid;

update public.platform_users set role = 'platform_support'
 where user_id = '15000000-0000-4000-8000-0000000000a5'::uuid;

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-0000000000a5'::uuid
      and action = 'platform_user.role_changed'
      and record_type = 'platform_user'
      and actor_user_id = '15000000-0000-4000-8000-0000000000f2'::uuid
      and before ->> 'role' = 'super_admin'
      and after  ->> 'role' = 'platform_support'),
  1::bigint,
  'spec "A role change writes an audit row" / design.md 7: platform_users is keyed on user_id rather than on an id column, so the audited record is the user. Demoting a super admin is the change most worth having a row for. Note the tenant is NOT asserted -- platform_users has no tenant column and audit_log''s is nullable for exactly this (ADR-033)'
);

select is(
  (select count(*) from public.audit_log
    where record_id = '15000000-0000-4000-8000-0000000000a3'::uuid
      and action = 'platform_user.deactivated'
      and record_type = 'platform_user'
      and before ->> 'is_active' = 'true'
      and after  ->> 'is_active' = 'false'),
  1::bigint,
  'design.md 7: revoking a platform account is audited. This is the row the deliberate addition exists for -- a compromised super admin being switched off is the write an incident review looks for first'
);

set local role postgres;

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a3'::uuid),
  0::bigint,
  'spec "Deactivating a platform user": the same guarantee on the platform side -- a revoked super admin does not keep an hour of super-admin claims'
);

select is(
  (select count(*) from auth.sessions
    where user_id = '15000000-0000-4000-8000-0000000000a5'::uuid),
  0::bigint,
  'design.md 7: demoting super_admin to platform_support revokes too. The demoted account''s live token still says super_admin, which is exactly the stale privilege the trigger exists to end'
);

select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
