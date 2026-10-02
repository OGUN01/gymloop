-- 68_staff_invites - STI-001..STI-018: staff invites and self-linking.
--
-- Written from openspec/changes/staff-invites/proposal.md and the frozen INV contract
-- (openspec/changes/member-invites/proposal.md) BEFORE any implementation exists
-- (AGENTS.md rule 10). This is the VISIBLE suite; an independent holdout author writes
-- h68_staff_invites_holdout.sql without reading this file. Nothing here reads an
-- implementation, and nothing here may be edited by the implementer.
--
-- WHY THIS FILE IS SO LARGE. This feature decides who becomes staff of a gym. A silent mistake
-- hands a stranger a manager, front-desk or trainer session in somebody else's gym, so every
-- requirement is probed twice: once on the path that must work and once on every path that
-- must refuse, and each refusal is built so that ONLY the cause under test is wrong (an
-- invitee that fails the email rule is otherwise perfectly verified, and so on). A refusal
-- that fires for the wrong reason would pass a looser suite.
--
-- HOW THE FIXTURES ARE ARRANGED.
--   * Every fixture UUID is 68000000-0000-4000-8000-... and every gym code starts STI68/STI681.
--   * Gym A is the working gym; B is the foreign gym; S is suspended; T is a trial that is
--     still running; X is a trial that has ended; L1 and L2 carry the rate-limit histories.
--   * A pool of 40 invitees (auth user, verified Google identity, unlinked staff row, one
--     pending invite whose hash is the case number repeated, two sessions each) is mutated
--     once per case by the fixture section, so a refusal test needs no set-up of its own.
--     Case numbers, hash pairs and what is special about each case are listed where they are
--     mutated and again where they are probed.
--   * The auth.users.email of an invitee is deliberately NOT the address on the staff row,
--     while the Google identity email is. An implementation that matches the wrong email
--     therefore fails the happy path, not just a refusal. (Case 17 is the reverse decoy.)
--   * Fixtures are written as postgres with no JWT subject, so the GL049 trigger treats them
--     as trusted (migrations and seed data behave the same way). Every probe switches to a
--     persona with a claims blob and a database role, and every return to fixture work clears
--     the claims first: a stale subject would make the GL049 trigger demand a platform admin.
--   * Refusal rows are RETURNED by redeem (never raised), so they commit with their audit row
--     and throttle evidence; the suite reads them back as postgres.
--   * Cases whose SQLSTATE the contract does not name are asserted as "refused with some
--     error and nothing changed" rather than guessed (the statement is wrapped in a block that
--     must not succeed). Every other refusal names its SQLSTATE.
--
-- ADR-050: every count below is scoped to a named fixture row or fixture tenant. ADR-030:
-- one transaction, begin ... rollback, nothing committed.
begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);
select plan(433);

-- ===========================================================================
-- FIXTURES
-- ===========================================================================

insert into public.organizations(id, name, gym_code, status, timezone, currency, trial_ends_at) values
  ('68000000-0000-4000-8000-000000000001',  'Sti Gym A',  'STI68A', 'active',    'Asia/Kolkata', 'INR', null),
  ('68000000-0000-4000-8000-000000000002',  'Sti Gym B',  'STI68B', 'active',    'Asia/Kolkata', 'INR', null),
  ('68000000-0000-4000-8000-000000000003',  'Sti Gym S',  'STI68S', 'suspended', 'Asia/Kolkata', 'INR', null),
  ('68000000-0000-4000-8000-000000000004',  'Sti Gym T',  'STI68T', 'trial',     'Asia/Kolkata', 'INR', now() + interval '10 days'),
  ('68000000-0000-4000-8000-000000000005',  'Sti Gym X',  'STI68X', 'trial',     'Asia/Kolkata', 'INR', now() - interval '1 day'),
  ('68000000-0000-4000-8000-000000000006', 'Sti Gym L1', 'STI681', 'active',    'Asia/Kolkata', 'INR', null),
  ('68000000-0000-4000-8000-000000000007', 'Sti Gym L2', 'STI682', 'active',    'Asia/Kolkata', 'INR', null);

insert into public.branches(id, tenant_id, name, is_default, timezone) values
  ('68000000-0000-4000-8000-0000000000b1', '68000000-0000-4000-8000-000000000001', 'A Main',   true,  'Asia/Kolkata'),
  ('68000000-0000-4000-8000-0000000000b2', '68000000-0000-4000-8000-000000000001', 'A Second', false, 'Asia/Kolkata'),
  ('68000000-0000-4000-8000-0000000000b3', '68000000-0000-4000-8000-000000000002', 'B Main',   true,  'Asia/Kolkata');

-- Core Auth users: the personas of the suite. Pool users are created below.
insert into auth.users(id) values
  ('68000000-0000-4000-8000-000000000101'), ('68000000-0000-4000-8000-000000000102'), ('68000000-0000-4000-8000-000000000103'), ('68000000-0000-4000-8000-000000000104'), ('68000000-0000-4000-8000-000000000105'), ('68000000-0000-4000-8000-000000000106'), ('68000000-0000-4000-8000-000000000107'),
  ('68000000-0000-4000-8000-000000000108'), ('68000000-0000-4000-8000-000000000109'), ('68000000-0000-4000-8000-00000000010a'), ('68000000-0000-4000-8000-00000000010b'), ('68000000-0000-4000-8000-00000000010c'), ('68000000-0000-4000-8000-00000000010d'), ('68000000-0000-4000-8000-00000000010e'),
  ('68000000-0000-4000-8000-000000000110'), ('68000000-0000-4000-8000-000000000111'), ('68000000-0000-4000-8000-000000000112'), ('68000000-0000-4000-8000-000000000115'), ('68000000-0000-4000-8000-000000000119'), ('68000000-0000-4000-8000-000000000121'), ('68000000-0000-4000-8000-000000000122'),
  ('68000000-0000-4000-8000-000000000123'), ('68000000-0000-4000-8000-000000000131'), ('68000000-0000-4000-8000-000000000132'), ('68000000-0000-4000-8000-000000000133'), ('68000000-0000-4000-8000-000000000134');
insert into auth.users(id, email, email_confirmed_at) values
  ('68000000-0000-4000-8000-00000000010f', 'owner.link.sti@example.com', now()),
  ('68000000-0000-4000-8000-000000000113',   'unlink3.sti@example.com',    now());

-- Pool of 44 Auth users. Their account email is a decoy ("primaryNN"); the Google identity
-- email (below) is the address the staff row carries.
insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data)
select ('68000000-0000-4000-8000-00000000a1' || lpad(to_hex(g), 2, '0'))::uuid,
       'primary' || lpad(g::text, 2, '0') || '.sti@example.com',
       now() - interval '30 days',
       '{}'::jsonb
  from generate_series(1, 44) as g;

-- A verified Google identity for the first 40 pool users (no password identity).
insert into auth.identities(user_id, provider_id, provider, identity_data)
select ('68000000-0000-4000-8000-00000000a1' || lpad(to_hex(g), 2, '0'))::uuid,
       'sti68-google-' || lpad(g::text, 2, '0'),
       'google',
       jsonb_build_object('sub', 'sti68-google-' || lpad(g::text, 2, '0'),
                          'email', 'inv' || lpad(g::text, 2, '0') || '.sti@example.com',
                          'email_verified', true)
  from generate_series(1, 40) as g;
insert into auth.identities(user_id, provider_id, provider, identity_data) values
  ('68000000-0000-4000-8000-000000000113', 'sti68-google-u3', 'google',
   '{"sub":"sti68-google-u3","email":"unlink3.sti@example.com","email_verified":true}'::jsonb);

insert into public.platform_users(user_id, role, full_name, email, is_active) values
  ('68000000-0000-4000-8000-000000000106', 'super_admin',      'Platform Admin',   'pa.sti@example.com',  true),
  ('68000000-0000-4000-8000-00000000010e', 'platform_support', 'Platform Support', 'ps.sti@example.com',  true),
  ('68000000-0000-4000-8000-00000000a118', 'platform_support', 'Platform Twenty-Four', 'p24.sti@example.com', true);

-- Core staff. sOA is the working owner of gym A; the dead owner is deactivated but still
-- carries a user, so a stale token for it is a real "owner claim, inactive row" probe.
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active) values
  ('68000000-0000-4000-8000-000000000201',   '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-000000000101',  '68000000-0000-4000-8000-0000000000b1', 'gym_owner',   'Olive Owner',    null, 'owner.a.sti@example.com',    true),
  ('68000000-0000-4000-8000-000000000202',   '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-000000000102',  '68000000-0000-4000-8000-0000000000b1', 'gym_manager', 'Mona Manager',   null, 'manager.a.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000203',   '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-000000000103',  '68000000-0000-4000-8000-0000000000b1', 'front_desk',  'Femi Desk',      null, 'desk.a.sti@example.com',     true),
  ('68000000-0000-4000-8000-000000000204',   '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-000000000104',  '68000000-0000-4000-8000-0000000000b1', 'trainer',     'Tara Trainer',   null, 'trainer.a.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000207',   '68000000-0000-4000-8000-000000000002',  '68000000-0000-4000-8000-000000000107',  '68000000-0000-4000-8000-0000000000b3', 'gym_owner',   'Bela Owner',     null, 'owner.b.sti@example.com',    true),
  ('68000000-0000-4000-8000-000000000208',   '68000000-0000-4000-8000-000000000003',  '68000000-0000-4000-8000-000000000108',  null,      'gym_owner',   'Sana Owner',     null, null,                         true),
  ('68000000-0000-4000-8000-000000000209',   '68000000-0000-4000-8000-000000000004',  '68000000-0000-4000-8000-000000000109',  null,      'gym_owner',   'Tej Owner',      null, null,                         true),
  ('68000000-0000-4000-8000-00000000020a',   '68000000-0000-4000-8000-000000000005',  '68000000-0000-4000-8000-00000000010a',  null,      'gym_owner',   'Xena Owner',     null, null,                         true),
  ('68000000-0000-4000-8000-00000000020b',  '68000000-0000-4000-8000-000000000006', '68000000-0000-4000-8000-00000000010b', null,      'gym_owner',   'Lia Owner',      null, null,                         true),
  ('68000000-0000-4000-8000-00000000020c',  '68000000-0000-4000-8000-000000000007', '68000000-0000-4000-8000-00000000010c', null,      'gym_owner',   'Lev Owner',      null, null,                         true),
  ('68000000-0000-4000-8000-00000000020d',  '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-00000000010d', null,      'gym_owner',   'Dead Owner',     null, 'dead.owner.a.sti@example.com', false),
  ('68000000-0000-4000-8000-00000000020e', '68000000-0000-4000-8000-000000000001',  null,       null,      'gym_owner',   'Issuer Twelve',  null, null,                         true),
  ('68000000-0000-4000-8000-00000000020f', '68000000-0000-4000-8000-000000000001',  null,       null,      'gym_owner',   'Issuer Thirteen', null, null,                        true),
  ('68000000-0000-4000-8000-000000000211',  '68000000-0000-4000-8000-000000000001',  null,       null,      'gym_owner',   'Second Owner',   null, 'owner2.a.sti@example.com',   true),
  ('68000000-0000-4000-8000-000000000212',  '68000000-0000-4000-8000-000000000002',  null,       '68000000-0000-4000-8000-0000000000b3', 'gym_owner',   'Linkable Owner', null, 'owner.link.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000213',   '68000000-0000-4000-8000-000000000002',  null,       null,      'front_desk',  'B Target',       null, 'b.target.sti@example.com',   true),
  ('68000000-0000-4000-8000-000000000214',  '68000000-0000-4000-8000-000000000001',  null,       null,      'front_desk',  'Default Target', null, 'default.target.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000215',    '68000000-0000-4000-8000-000000000001',  null,       null,      'front_desk',  'Matrix Target',  null, 'matrix.target.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000270',  '68000000-0000-4000-8000-000000000002',  '68000000-0000-4000-8000-00000000a117',  null,      'trainer',     'Bound Staff 23', null, null,                         true),
  ('68000000-0000-4000-8000-000000000271',  '68000000-0000-4000-8000-000000000001',  '68000000-0000-4000-8000-00000000a119',  null,      'trainer',     'Bound Staff 25', null, null,                         true);

-- Pool staff rows: unlinked, active front desk in gym A, email = the Google identity email.
-- Cases 03, 10 and 11 live in other gyms and are written by hand further down.
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active)
select ('68000000-0000-4000-8000-00000000b1' || lpad(to_hex(g), 2, '0'))::uuid,
       '68000000-0000-4000-8000-000000000001'::uuid, null, null, 'front_desk'::public.app_role,
       'Invitee ' || lpad(g::text, 2, '0'), null,
       'inv' || lpad(g::text, 2, '0') || '.sti@example.com', true
  from generate_series(1, 40) as g
 where g not in (3, 10, 11);

-- Members that already hold an Auth account elsewhere (D1 probes 22 and 30), and a member
-- persona in gym A.
insert into public.members(id, tenant_id, branch_id, user_id, full_name, phone, email) values
  ('68000000-0000-4000-8000-000000000301',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-0000000000b1', '68000000-0000-4000-8000-000000000105', 'Mina Member',     '+919800068301', 'member.a.sti@example.com'),
  ('68000000-0000-4000-8000-000000000322', '68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-0000000000b3', '68000000-0000-4000-8000-00000000a116',   'Bound Member 22', '+919800068322', null),
  ('68000000-0000-4000-8000-000000000330', '68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-0000000000b3', '68000000-0000-4000-8000-00000000a11e',   'Bound Member 30', '+919800068330', null);

-- Two sessions for every pool user and for the unlink targets, so that "this user's sessions
-- were deleted" is distinguishable from "there was one and something removed it".
insert into auth.sessions(id, user_id)
select ('68000000-0000-4000-8000-00000000d1' || lpad(to_hex(g), 2, '0'))::uuid,
       ('68000000-0000-4000-8000-00000000a1' || lpad(to_hex(g), 2, '0'))::uuid
  from generate_series(1, 40) as g;
insert into auth.sessions(id, user_id)
select ('68000000-0000-4000-8000-00000000d2' || lpad(to_hex(g), 2, '0'))::uuid,
       ('68000000-0000-4000-8000-00000000a1' || lpad(to_hex(g), 2, '0'))::uuid
  from generate_series(1, 40) as g;
insert into auth.sessions(id, user_id) values
  ('68000000-0000-4000-8000-00000000d301', '68000000-0000-4000-8000-000000000111'), ('68000000-0000-4000-8000-00000000d302', '68000000-0000-4000-8000-000000000111'),
  ('68000000-0000-4000-8000-00000000d303', '68000000-0000-4000-8000-000000000112'), ('68000000-0000-4000-8000-00000000d304', '68000000-0000-4000-8000-000000000112'),
  ('68000000-0000-4000-8000-00000000d305', '68000000-0000-4000-8000-000000000113'), ('68000000-0000-4000-8000-00000000d306', '68000000-0000-4000-8000-000000000113'),
  ('68000000-0000-4000-8000-00000000d307', '68000000-0000-4000-8000-000000000115'), ('68000000-0000-4000-8000-00000000d308', '68000000-0000-4000-8000-000000000115'),
  ('68000000-0000-4000-8000-00000000d309', '68000000-0000-4000-8000-000000000119'), ('68000000-0000-4000-8000-00000000d30a', '68000000-0000-4000-8000-000000000119'),
  ('68000000-0000-4000-8000-00000000d30b', '68000000-0000-4000-8000-000000000131'), ('68000000-0000-4000-8000-00000000d30c', '68000000-0000-4000-8000-000000000131');

-- Named targets for the issue / revoke / unlink / read / trigger sections.
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active) values
  ('68000000-0000-4000-8000-000000000221', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Issue One',          null, 'issue1.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000222', '68000000-0000-4000-8000-000000000001', null,       null, 'trainer',     'Issue Two',          null, 'issue2.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000223', '68000000-0000-4000-8000-000000000001', null,       null, 'gym_manager', 'Issue Three',        null, 'issue3.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000224', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Issue Inactive',     null, 'issue4.sti@example.com', false),
  ('68000000-0000-4000-8000-000000000225', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000110', null, 'gym_manager', 'Issue Linked',       null, 'issue5.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000226', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Issue No Email',     null, null,                     true),
  ('68000000-0000-4000-8000-000000000227', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Issue Blank Email',  null, '   ',                    true),
  ('68000000-0000-4000-8000-000000000228', '68000000-0000-4000-8000-000000000001', null,       null, 'trainer',     'Issue Padded Email', null, '  Padded.Issue@Example.com  ', true),
  ('68000000-0000-4000-8000-000000000231', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Revoke One',         null, 'revoke1.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000232', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Revoke Two',         null, 'revoke2.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000233', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Revoke Three',       null, 'revoke3.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000234', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Revoke Four',        null, 'revoke4.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000235', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Revoke Five',        null, 'revoke5.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000241', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000111',  null, 'gym_manager', 'Unlink One',         null, 'unlink1.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000242', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000112',  null, 'front_desk',  'Unlink Two',         null, 'unlink2.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000243', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000113',  null, 'trainer',     'Unlink Three',       null, 'unlink3.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000244', '68000000-0000-4000-8000-000000000001', null,       null, 'front_desk',  'Unlink Four',        null, 'unlink4.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000245', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000115',  null, 'gym_owner',   'Unlink Five Owner',  null, 'unlink5.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000249', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000119',  null, 'front_desk',  'Unlink Control',     null, 'unlink9.sti@example.com', true),
  ('68000000-0000-4000-8000-000000000251',  '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000121',  null, 'gym_manager', 'Read Operator Bound', null, 'read1.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000252',  '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000122',  null, 'front_desk',  'Read Audit Linked',   null, 'read2.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000253',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Inactive',       null, 'read3.sti@example.com',  false),
  ('68000000-0000-4000-8000-000000000255',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Pending',        null, 'read5.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000256',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Expired',        null, 'read6.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000257',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Never Invited',  null, null,                     true),
  ('68000000-0000-4000-8000-000000000258',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Revoked',        null, 'read8.sti@example.com',  true),
  ('68000000-0000-4000-8000-000000000259',  '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Redeemed',       null, 'read9.sti@example.com',  true),
  ('68000000-0000-4000-8000-00000000025a', '68000000-0000-4000-8000-000000000001', null,        null, 'front_desk',  'Read Resent',         null, 'read10.sti@example.com', true),
  ('68000000-0000-4000-8000-00000000025b', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000123', null, 'front_desk',  'Read Linked Inactive', null, 'read11.sti@example.com', false),
  ('68000000-0000-4000-8000-000000000261', '68000000-0000-4000-8000-000000000001', null, null, 'gym_manager', 'Trigger One',      null, null, true),
  ('68000000-0000-4000-8000-000000000262', '68000000-0000-4000-8000-000000000001', null, null, 'gym_owner',   'Trigger Owner',    null, null, true),
  ('68000000-0000-4000-8000-000000000263', '68000000-0000-4000-8000-000000000001', null, null, 'trainer',     'Trigger Inactive', null, null, false),
  ('68000000-0000-4000-8000-000000000265', '68000000-0000-4000-8000-000000000001', null, null, 'front_desk',  'Trigger Five',     null, null, true);

-- Rate-limit gyms. L1: 29 invites in the last hour over six staff rows (5,5,5,5,5,4), ten
-- more two hours ago over two other rows, one fresh row. L2: s1 holds four invites inside 24
-- hours (none inside the hour), s2 holds five issued 25 hours ago.
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active)
select ('68000000-0000-4000-8000-00000000e1' || lpad(to_hex(g), 2, '0'))::uuid,
       '68000000-0000-4000-8000-000000000006'::uuid, null, null, 'front_desk'::public.app_role, 'L1 Recent ' || g, null,
       'l1.recent' || g || '.sti@example.com', true
  from generate_series(1, 6) as g;
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active)
select ('68000000-0000-4000-8000-00000000e2' || lpad(to_hex(g), 2, '0'))::uuid,
       '68000000-0000-4000-8000-000000000006'::uuid, null, null, 'front_desk'::public.app_role, 'L1 Old ' || g, null,
       'l1.old' || g || '.sti@example.com', true
  from generate_series(1, 2) as g;
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active) values
  ('68000000-0000-4000-8000-00000000e301', '68000000-0000-4000-8000-000000000006', null, null, 'front_desk', 'L1 Fresh Row', null, 'l1.freshrow.sti@example.com', true),
  ('68000000-0000-4000-8000-00000000e401', '68000000-0000-4000-8000-000000000007', null, null, 'front_desk', 'L2 Four Recent', null, 'l2.s1.sti@example.com', true),
  ('68000000-0000-4000-8000-00000000e402', '68000000-0000-4000-8000-000000000007', null, null, 'front_desk', 'L2 Five Stale',  null, 'l2.s2.sti@example.com', true);

-- Implausible addresses (PROV-002 rule: one @, non-empty local part, dotted domain, no
-- whitespace) on otherwise perfectly invitable rows.
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active)
select ('68000000-0000-4000-8000-00000000f1' || lpad(to_hex(g), 2, '0'))::uuid,
       '68000000-0000-4000-8000-000000000001'::uuid, null, null, 'front_desk'::public.app_role, 'Bad Email ' || g, null,
       (array['plainaddress', 'two@@x.com', 'user@nodot', 'sp ace@x.com', '@x.com', 'a@b@c.com'])[g], true
  from generate_series(1, 6) as g;

-- The hand-written cases that live in other gyms: 03 (trial gym still running), 10
-- (suspended gym), 11 (trial gym that has ended).
insert into public.staff(id, tenant_id, user_id, branch_id, role, full_name, phone, email, is_active) values
  ('68000000-0000-4000-8000-00000000b103', '68000000-0000-4000-8000-000000000004', null, null, 'trainer',    'Trial Trainer 03',     null, 'inv03.sti@example.com', true),
  ('68000000-0000-4000-8000-00000000b10a', '68000000-0000-4000-8000-000000000003', null, null, 'front_desk', 'Suspended Desk 10',    null, 'inv10.sti@example.com', true),
  ('68000000-0000-4000-8000-00000000b10b', '68000000-0000-4000-8000-000000000005', null, null, 'front_desk', 'Expired Trial Desk 11', null, 'inv11.sti@example.com', true);

-- Invites. The pool invites are pending, issued five hours ago (outside the tenant hour,
-- inside the staff day) and expire in 43 hours: expiry is always issue + 48 hours.
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at)
select ('68000000-0000-4000-8000-00000000c1' || lpad(to_hex(g), 2, '0'))::uuid,
       '68000000-0000-4000-8000-000000000001'::uuid,
       ('68000000-0000-4000-8000-00000000b1' || lpad(to_hex(g), 2, '0'))::uuid,
       repeat(lpad(to_hex(g), 2, '0'), 32),
       'pending'::public.staff_invite_status, '68000000-0000-4000-8000-000000000201'::uuid,
       now() - interval '5 hours', now() + interval '43 hours'
  from generate_series(1, 40) as g
 where g not in (3, 10, 11);
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at) values
  ('68000000-0000-4000-8000-00000000c103', '68000000-0000-4000-8000-000000000004', '68000000-0000-4000-8000-00000000b103', repeat('03', 32), 'pending', '68000000-0000-4000-8000-000000000209', now() - interval '5 hours', now() + interval '43 hours'),
  ('68000000-0000-4000-8000-00000000c10a', '68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-00000000b10a', repeat('0a', 32), 'pending', '68000000-0000-4000-8000-000000000208', now() - interval '5 hours', now() + interval '43 hours'),
  ('68000000-0000-4000-8000-00000000c10b', '68000000-0000-4000-8000-000000000005', '68000000-0000-4000-8000-00000000b10b', repeat('0b', 32), 'pending', '68000000-0000-4000-8000-00000000020a', now() - interval '5 hours', now() + interval '43 hours');

-- Named invites: pending (cI2, cR1, cR5, cU1, cB1, cRd3, cRd5, cRd10b), pending but expired
-- (cI3, cRd6), revoked (cR2, cRd8), redeemed (cR3, cRd9), superseded (cR4, cRd10a).
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id) values
  ('68000000-0000-4000-8000-000000000502',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000222',  repeat('a2', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000503',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000223',  repeat('a3', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '49 hours', now() - interval '1 hour',   null, null, null),
  ('68000000-0000-4000-8000-000000000531',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000231',  repeat('b1', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000532',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000232',  repeat('b2', 32), 'revoked',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', now() - interval '4 hours', '68000000-0000-4000-8000-000000000201', null),
  ('68000000-0000-4000-8000-000000000533',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000233',  repeat('b3', 32), 'redeemed',   '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', now() - interval '4 hours', null, '68000000-0000-4000-8000-000000000134'),
  ('68000000-0000-4000-8000-000000000534',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000234',  repeat('b4', 32), 'superseded', '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', now() - interval '4 hours', null, null),
  ('68000000-0000-4000-8000-000000000535',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000235',  repeat('b6', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000541',    '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000241',  repeat('b5', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000513',    '68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-000000000213',  repeat('e5', 32), 'pending',    '68000000-0000-4000-8000-000000000207', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000553',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000253',  repeat('d3', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000555',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000255',  repeat('d5', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null),
  ('68000000-0000-4000-8000-000000000556',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000256',  repeat('d6', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '49 hours', now() - interval '1 hour',   null, null, null),
  ('68000000-0000-4000-8000-000000000558',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000258',  repeat('d8', 32), 'revoked',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', now() - interval '4 hours', '68000000-0000-4000-8000-000000000201', null),
  ('68000000-0000-4000-8000-000000000559',   '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000259',  repeat('d9', 32), 'redeemed',   '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', now() - interval '4 hours', null, '68000000-0000-4000-8000-000000000134'),
  ('68000000-0000-4000-8000-00000000055a', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-00000000025a', repeat('da', 32), 'superseded', '68000000-0000-4000-8000-000000000201', now() - interval '6 hours',  now() + interval '42 hours', now() - interval '5 hours', null, null),
  ('68000000-0000-4000-8000-00000000055b', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-00000000025a', repeat('db', 32), 'pending',    '68000000-0000-4000-8000-000000000201', now() - interval '5 hours',  now() + interval '43 hours', null, null, null);

-- L1: 29 invites inside the hour (issued ten minutes ago), ten two hours ago.
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at)
select gen_random_uuid(), '68000000-0000-4000-8000-000000000006'::uuid,
       ('68000000-0000-4000-8000-00000000e1' || lpad(to_hex(r), 2, '0'))::uuid,
       md5('l1r' || r || '-' || k) || md5('l1r' || r || '+' || k),
       'revoked'::public.staff_invite_status, '68000000-0000-4000-8000-00000000020b'::uuid,
       now() - interval '10 minutes', now() - interval '10 minutes' + interval '48 hours', now() - interval '9 minutes'
  from generate_series(1, 6) as r
 cross join generate_series(1, 5) as k
 where k <= case when r = 6 then 4 else 5 end;
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at)
select gen_random_uuid(), '68000000-0000-4000-8000-000000000006'::uuid,
       ('68000000-0000-4000-8000-00000000e2' || lpad(to_hex(r), 2, '0'))::uuid,
       md5('l1o' || r || '-' || k) || md5('l1o' || r || '+' || k),
       'revoked'::public.staff_invite_status, '68000000-0000-4000-8000-00000000020b'::uuid,
       now() - interval '2 hours', now() - interval '2 hours' + interval '48 hours', now() - interval '119 minutes'
  from generate_series(1, 2) as r
 cross join generate_series(1, 5) as k;
-- L2: s1 four invites at 3, 6, 12 and 23 hours; s2 five invites 25 hours ago.
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at)
select gen_random_uuid(), '68000000-0000-4000-8000-000000000007'::uuid, '68000000-0000-4000-8000-00000000e401'::uuid,
       md5('l2s1-' || h) || md5('l2s1+' || h),
       'revoked'::public.staff_invite_status, '68000000-0000-4000-8000-00000000020c'::uuid,
       now() - make_interval(hours => h), now() - make_interval(hours => h) + interval '48 hours',
       now() - make_interval(hours => h) + interval '1 minute'
  from unnest(array[3, 6, 12, 23]) as h;
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at)
select gen_random_uuid(), '68000000-0000-4000-8000-000000000007'::uuid, '68000000-0000-4000-8000-00000000e402'::uuid,
       md5('l2s2-' || k) || md5('l2s2+' || k),
       'revoked'::public.staff_invite_status, '68000000-0000-4000-8000-00000000020c'::uuid,
       now() - interval '25 hours', now() - interval '25 hours' + interval '48 hours', now() - interval '24 hours 59 minutes'
  from generate_series(1, 5) as k;

-- ---------------------------------------------------------------------------
-- Pool cases (case number = hash pair repeated 32 times; 10 -> 0a ... 26 -> 1a):
--   01 manager, branch and phone set, padded mixed-case address; Google email lower-case
--   02 plain front desk                      03 trainer in the running trial gym T
--   04 expired pending                       05 revoked
--   06 superseded (a newer pending exists: hash c6)
--   07 staff row inactive                    08 staff row is an owner
--   09 staff row already linked elsewhere    10 suspended gym      11 ended trial gym
--   12 issuer deactivated after issue        13 issuer demoted after issue
--   14 issuer was never an owner             15 row became an owner after issue
--   16 replay by a different account         17 email mismatch (account email is the decoy)
--   18 email not confirmed                   19 no Google identity (password identity)
--   20 Google + password identity            21 Google + password identity, operator provisioned
--   22 account bound as a member elsewhere   23 account bound as staff elsewhere
--   24 account is a platform user            25 account bound as another row of the same gym
--   26 nine refusals in the window (5 member, 4 staff)
--   27 twelve refusals, all 25 minutes old   28 ten refusals inside the window
--   29 unverified AND wrong email            30 bound elsewhere AND wrong email
--   31 expired invite AND unverified         32 impersonation / control account
--   33 staff email blank                     34 staff email null
--   36 staff email changed after issue
-- ---------------------------------------------------------------------------
update public.staff
   set role = 'gym_manager', branch_id = '68000000-0000-4000-8000-0000000000b1', phone = '+919800068001',
       email = ' Mixed.Case01@Example.com ', full_name = 'Mixed Case Manager'
 where id = '68000000-0000-4000-8000-00000000b101';
update auth.identities
   set identity_data = identity_data || '{"email":"mixed.case01@example.com"}'::jsonb
 where user_id = '68000000-0000-4000-8000-00000000a101' and provider = 'google';

update public.staff_invites
   set issued_at = now() - interval '49 hours', expires_at = now() - interval '1 hour'
 where id in ('68000000-0000-4000-8000-00000000c104', '68000000-0000-4000-8000-00000000c11f');
update public.staff_invites
   set status = 'revoked', closed_at = now() - interval '4 hours', closed_by_staff_id = '68000000-0000-4000-8000-000000000201'
 where id = '68000000-0000-4000-8000-00000000c105';
update public.staff_invites
   set status = 'superseded', closed_at = now() - interval '2 hours'
 where id = '68000000-0000-4000-8000-00000000c106';
insert into public.staff_invites(id, tenant_id, staff_id, token_hash, status, issued_by_staff_id, issued_at, expires_at) values
  ('68000000-0000-4000-8000-00000000c206', '68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-00000000b106', repeat('c6', 32), 'pending', '68000000-0000-4000-8000-000000000201', now() - interval '2 hours', now() + interval '46 hours');

update public.staff set is_active = false where id = '68000000-0000-4000-8000-00000000b107';
update public.staff set role = 'gym_owner' where id in ('68000000-0000-4000-8000-00000000b108', '68000000-0000-4000-8000-00000000b10f');
update public.staff set user_id = '68000000-0000-4000-8000-00000000a129' where id = '68000000-0000-4000-8000-00000000b109';

update public.staff_invites set issued_by_staff_id = '68000000-0000-4000-8000-00000000020e' where id = '68000000-0000-4000-8000-00000000c10c';
update public.staff_invites set issued_by_staff_id = '68000000-0000-4000-8000-00000000020f' where id = '68000000-0000-4000-8000-00000000c10d';
update public.staff_invites set issued_by_staff_id = '68000000-0000-4000-8000-000000000202'   where id = '68000000-0000-4000-8000-00000000c10e';
update public.staff set is_active = false where id = '68000000-0000-4000-8000-00000000020e';
update public.staff set role = 'gym_manager' where id = '68000000-0000-4000-8000-00000000020f';

update auth.users set email = 'inv17.sti@example.com' where id = '68000000-0000-4000-8000-00000000a111';
update auth.identities
   set identity_data = identity_data || '{"email":"other.person17@example.com"}'::jsonb
 where user_id = '68000000-0000-4000-8000-00000000a111' and provider = 'google';

update auth.users set email_confirmed_at = null where id in ('68000000-0000-4000-8000-00000000a112', '68000000-0000-4000-8000-00000000a11d', '68000000-0000-4000-8000-00000000a11f');

delete from auth.identities where user_id = '68000000-0000-4000-8000-00000000a113' and provider = 'google';
insert into auth.identities(user_id, provider_id, provider, identity_data) values
  ('68000000-0000-4000-8000-00000000a113', 'sti68-email-19', 'email', '{"sub":"sti68-email-19","email":"inv19.sti@example.com","email_verified":true}'::jsonb),
  ('68000000-0000-4000-8000-00000000a114', 'sti68-email-20', 'email', '{"sub":"sti68-email-20","email":"inv20.sti@example.com","email_verified":true}'::jsonb),
  ('68000000-0000-4000-8000-00000000a115', 'sti68-email-21', 'email', '{"sub":"sti68-email-21","email":"inv21.sti@example.com","email_verified":true}'::jsonb);
update auth.users set email = 'inv19.sti@example.com' where id = '68000000-0000-4000-8000-00000000a113';
update auth.users set raw_app_meta_data = '{"gymloop_provisioned":true}'::jsonb where id = '68000000-0000-4000-8000-00000000a115';

update auth.identities
   set identity_data = identity_data || '{"email":"other.person29@example.com"}'::jsonb
 where user_id = '68000000-0000-4000-8000-00000000a11d' and provider = 'google';
update auth.identities
   set identity_data = identity_data || '{"email":"other.person30@example.com"}'::jsonb
 where user_id = '68000000-0000-4000-8000-00000000a11e' and provider = 'google';

update public.staff set email = '   ' where id = '68000000-0000-4000-8000-00000000b121';
update public.staff set email = null where id = '68000000-0000-4000-8000-00000000b122';
update public.staff set email = 'changed.after36@example.com' where id = '68000000-0000-4000-8000-00000000b124';

-- Refusal history for the throttle cases. Both families count: member_invite.redeem_refused
-- rows (written by INV) and staff_invite.redeem_refused rows (written here).
insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, occurred_at)
select null::uuid, '68000000-0000-4000-8000-00000000a11a'::uuid, null::public.app_role,
       case when g <= 5 then 'member_invite.redeem_refused' else 'staff_invite.redeem_refused' end,
       case when g <= 5 then 'member_invite' else 'staff_invite' end,
       null::uuid, null::jsonb, '{"outcome":"invite_unavailable"}'::jsonb, now() - interval '5 minutes'
  from generate_series(1, 9) as g;
insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, occurred_at)
select null::uuid, '68000000-0000-4000-8000-00000000a11b'::uuid, null::public.app_role,
       case when g <= 6 then 'member_invite.redeem_refused' else 'staff_invite.redeem_refused' end,
       case when g <= 6 then 'member_invite' else 'staff_invite' end,
       null::uuid, null::jsonb, '{"outcome":"invite_unavailable"}'::jsonb, now() - interval '25 minutes'
  from generate_series(1, 12) as g;
insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, occurred_at)
select null::uuid, '68000000-0000-4000-8000-00000000a11c'::uuid, null::public.app_role,
       case when g <= 5 then 'member_invite.redeem_refused' else 'staff_invite.redeem_refused' end,
       case when g <= 5 then 'member_invite' else 'staff_invite' end,
       null::uuid, null::jsonb, '{"outcome":"invite_unavailable"}'::jsonb, now() - interval '10 minutes'
  from generate_series(1, 10) as g;

-- Audit history for the read-model cases: two staff.linked rows for Rd2 (the newer one is
-- the answer), a later staff.unlinked for the same row, and a newer staff.linked for a
-- DIFFERENT staff row in the same gym.
insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, occurred_at) values
  ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000122', null,        'staff.linked',   'staff', '68000000-0000-4000-8000-000000000252', '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-09-01 10:00:00+00'),
  ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000122', null,        'staff.linked',   'staff', '68000000-0000-4000-8000-000000000252', '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-09-20 10:00:00+00'),
  ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000101',  'gym_owner', 'staff.unlinked', 'staff', '68000000-0000-4000-8000-000000000252', '{"user_linked":true}'::jsonb,  '{"user_linked":false}'::jsonb,              timestamptz '2026-09-25 10:00:00+00'),
  ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000103',  null,        'staff.linked',   'staff', '68000000-0000-4000-8000-000000000203', '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-09-29 10:00:00+00');


-- ===========================================================================
-- 1. STRUCTURE: the fixed names of the contract (enum, table, keys, indexes, policy, grants,
--    functions) and the database-level rules that hold for every writer.
-- ===========================================================================

select has_enum('public', 'staff_invite_status', 'STI structure: the invite lifecycle is a canonical Postgres enum');
select enum_has_labels('public', 'staff_invite_status', array['pending', 'redeemed', 'revoked', 'superseded']::name[],
  'STI structure: exactly the four lifecycle labels, in contract order');
select has_table('public', 'staff_invites', 'STI structure: public.staff_invites exists');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.staff_invites'::regclass),
  'STI-011: row level security is enabled on staff_invites');

select is(
  (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || case when a.attnotnull then 'nn' else 'null' end, ',' order by a.attname)
     from pg_attribute a
    where a.attrelid = 'public.staff_invites'::regclass and a.attnum > 0 and not a.attisdropped),
  'closed_at:timestamp with time zone:null,closed_by_staff_id:uuid:null,created_at:timestamp with time zone:nn,expires_at:timestamp with time zone:nn,id:uuid:nn,issued_at:timestamp with time zone:nn,issued_by_staff_id:uuid:nn,redeemed_user_id:uuid:null,staff_id:uuid:nn,status:staff_invite_status:nn,tenant_id:uuid:nn,token_hash:text:nn,updated_at:timestamp with time zone:nn',
  'STI-017: the column set is exactly the contract (ids, hash, status, timestamps) and carries no personal data');

select ok(exists(select 1 from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'staff_invites' and i.indexname = 'staff_invites_token_hash_key'
     and i.indexdef like 'CREATE UNIQUE INDEX%' and i.indexdef like '%(token_hash)%'),
  'STI structure: staff_invites_token_hash_key is a global unique on token_hash');
select ok(exists(select 1 from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'staff_invites' and i.indexname = 'staff_invites_one_pending_key'
     and i.indexdef like 'CREATE UNIQUE INDEX%' and i.indexdef like '%(tenant_id, staff_id)%' and i.indexdef like '%pending%'),
  'STI-002: staff_invites_one_pending_key is a partial unique on (tenant_id, staff_id) for pending rows');

select ok(exists(select 1 from pg_constraint c
   where c.conrelid = 'public.staff_invites'::regclass and c.contype = 'f' and c.confrelid = 'public.staff'::regclass
     and (select array_agg(a.attname::text order by k.ord)
            from unnest(c.conkey) with ordinality as k(attnum, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) = array['tenant_id', 'staff_id']
     and (select array_agg(a.attname::text order by k.ord)
            from unnest(c.confkey) with ordinality as k(attnum, ord)
            join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum) = array['tenant_id', 'id']),
  'STI structure: composite foreign key (tenant_id, staff_id) references staff (tenant_id, id)');
select ok(exists(select 1 from pg_constraint c
   where c.conrelid = 'public.staff_invites'::regclass and c.contype = 'f' and c.confrelid = 'public.staff'::regclass
     and (select array_agg(a.attname::text order by k.ord)
            from unnest(c.conkey) with ordinality as k(attnum, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) = array['tenant_id', 'issued_by_staff_id']
     and (select array_agg(a.attname::text order by k.ord)
            from unnest(c.confkey) with ordinality as k(attnum, ord)
            join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum) = array['tenant_id', 'id']),
  'STI structure: composite foreign key (tenant_id, issued_by_staff_id) references staff (tenant_id, id)');
select ok(exists(select 1 from pg_constraint c
   where c.conrelid = 'public.staff_invites'::regclass and c.contype = 'f' and c.confrelid = 'public.organizations'::regclass),
  'STI structure: tenant_id references organizations');
select ok(exists(select 1 from pg_constraint c
   where c.conrelid = 'public.staff_invites'::regclass and c.contype = 'f' and c.confrelid = 'auth.users'::regclass
     and c.confdeltype = 'n'),
  'STI structure: redeemed_user_id references auth.users and is set null when the user is deleted');
select is((select count(*) from pg_constraint c
    where c.conrelid = 'public.staff_invites'::regclass and c.contype = 'c'
      and c.conname in ('staff_invites_token_hash_format_chk', 'staff_invites_expiry_chk', 'staff_invites_closed_state_chk')),
  3::bigint, 'STI structure: the three ADR-040 check constraints carry the contract names');

select ok(exists(select 1 from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'staff_invites' and i.indexdef like '%(tenant_id, staff_id, issued_at DESC)%'),
  'STI-003 index: (tenant_id, staff_id, issued_at desc) serves the per-row throttle and the read model');
select ok(exists(select 1 from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'staff_invites' and i.indexdef like '%(tenant_id, issued_at)%'),
  'STI-003 index: (tenant_id, issued_at) serves the per-gym hourly throttle');
select ok(exists(select 1 from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'audit_log'
     and i.indexdef like '%(actor_user_id, occurred_at)%' and i.indexdef like '%staff_invite.redeem_refused%'),
  'STI-004 index: partial audit_log index on (actor_user_id, occurred_at) for staff_invite.redeem_refused');
select is((select count(*) from pg_trigger t
    where t.tgrelid = 'public.staff_invites'::regclass and not t.tgisinternal
      and t.tgname in ('staff_invites_touch_updated_at', 'staff_invites_preview_read_only')),
  2::bigint, 'STI structure: the standard touch and preview triggers exist under their convention names');

select is((select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'staff_invites'),
  1::bigint, 'STI-011: staff_invites has exactly one policy');
select ok((select count(*) = 1 and bool_and(p.cmd = 'SELECT' and p.roles = array['authenticated']::name[] and p.qual like '%gym_owner%')
     from pg_policies p where p.schemaname = 'public' and p.tablename = 'staff_invites'),
  'STI-011: the only policy is a select policy for authenticated that names gym_owner');
select ok(has_table_privilege('authenticated', 'public.staff_invites', 'SELECT'),
  'STI-011: authenticated can select staff_invites (the policy filters)');
select ok(not has_table_privilege('authenticated', 'public.staff_invites', 'INSERT,UPDATE,DELETE,TRUNCATE'),
  'STI-011: authenticated holds no insert, update, delete or truncate privilege on staff_invites');
select ok(not has_table_privilege('anon', 'public.staff_invites', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
  'STI-011: anon holds no privilege at all on staff_invites');

select has_function('public', 'invite_staff_member', array['text', 'text', 'text', 'app_role', 'uuid', 'text']::name[],
  'STI-001: public.invite_staff_member(name, email, phone, role, branch, hash) exists');
select has_function('public', 'issue_staff_invite', array['uuid', 'text']::name[], 'STI-002: public.issue_staff_invite(staff, hash) exists');
select has_function('public', 'revoke_staff_invite', array['uuid']::name[], 'STI-002: public.revoke_staff_invite(invite) exists');
select has_function('public', 'redeem_staff_invite', array['text']::name[], 'STI-004: public.redeem_staff_invite(hash) exists');
select has_function('public', 'peek_staff_invite', array['text']::name[], 'STI-007: public.peek_staff_invite(hash) exists');
select has_function('public', 'unlink_staff_identity', array['uuid', 'text']::name[], 'STI-008: public.unlink_staff_identity(staff, reason) exists');
select has_function('public', 'read_staff_app_access', array['uuid']::name[], 'STI-009: public.read_staff_app_access(staff) exists');
select has_function('app', 'staff_invite_audit',
  array['uuid', 'uuid', 'app_role', 'text', 'text', 'uuid', 'jsonb', 'jsonb', 'text']::name[],
  'STI-010: app.staff_invite_audit(tenant, actor, role, action, type, record, before, after, reason) exists');

select ok((select count(*) = 8 and bool_and(p.prosecdef and p.proconfig @> array['search_path=""'] and pg_get_userbyid(p.proowner) = 'postgres')
     from pg_proc p where p.oid = any (array[to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)'),to_regprocedure('public.issue_staff_invite(uuid,text)'),to_regprocedure('public.revoke_staff_invite(uuid)'),to_regprocedure('public.redeem_staff_invite(text)'),to_regprocedure('public.peek_staff_invite(text)'),to_regprocedure('public.unlink_staff_identity(uuid,text)'),to_regprocedure('public.read_staff_app_access(uuid)'),to_regprocedure('app.staff_invite_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)')]::oid[])),
  'STI structure: the seven commands and the audit helper are postgres-owned security definers with an empty search_path');

select is(replace(pg_get_function_result(to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)')), 'public.', ''),
  'TABLE(staff_id uuid, invite_id uuid, expires_at timestamp with time zone)', 'STI-001: invite_staff_member returns (staff_id, invite_id, expires_at)');
select is(replace(pg_get_function_result(to_regprocedure('public.issue_staff_invite(uuid,text)')), 'public.', ''),
  'TABLE(invite_id uuid, expires_at timestamp with time zone, superseded_invite_id uuid)', 'STI-002: issue_staff_invite returns (invite_id, expires_at, superseded_invite_id)');
select is(pg_get_function_result(to_regprocedure('public.revoke_staff_invite(uuid)')),
  'uuid', 'STI-002: revoke_staff_invite returns the invite id');
select is(replace(pg_get_function_result(to_regprocedure('public.redeem_staff_invite(text)')), 'public.', ''),
  'TABLE(outcome text, gym_name text, staff_role app_role)', 'STI-004: redeem_staff_invite returns (outcome, gym_name, staff_role)');
select is(replace(pg_get_function_result(to_regprocedure('public.peek_staff_invite(text)')), 'public.', ''),
  'TABLE(gym_name text, staff_role app_role)', 'STI-007: peek_staff_invite returns the gym name and the role and nothing else');
select is(pg_get_function_result(to_regprocedure('public.unlink_staff_identity(uuid,text)')),
  'void', 'STI-008: unlink_staff_identity returns void');
select is(replace(pg_get_function_result(to_regprocedure('public.read_staff_app_access(uuid)')), 'public.', ''),
  'TABLE(state text, invite_id uuid, issued_at timestamp with time zone, expires_at timestamp with time zone, linked_at timestamp with time zone)',
  'STI-009: read_staff_app_access returns (state, invite_id, issued_at, expires_at, linked_at)');
select is(pg_get_function_result(to_regprocedure('app.staff_invite_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)')),
  'void', 'STI-010: the audit helper returns void');

select ok((select count(f) = 7 and bool_and(has_function_privilege('authenticated', f, 'EXECUTE')) from unnest(array[to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)'),to_regprocedure('public.issue_staff_invite(uuid,text)'),to_regprocedure('public.revoke_staff_invite(uuid)'),to_regprocedure('public.redeem_staff_invite(text)'),to_regprocedure('public.peek_staff_invite(text)'),to_regprocedure('public.unlink_staff_identity(uuid,text)'),to_regprocedure('public.read_staff_app_access(uuid)')]::oid[]) as f),
  'STI-011: authenticated can execute all seven commands');
select ok((select count(f) = 1 and bool_and(has_function_privilege('anon', f, 'EXECUTE')) from unnest(array[to_regprocedure('public.peek_staff_invite(text)')]::oid[]) as f),
  'STI-007/011: anon can execute peek_staff_invite');
select ok((select count(f) = 6 and bool_and(not has_function_privilege('anon', f, 'EXECUTE')) from unnest(array[to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)'),to_regprocedure('public.issue_staff_invite(uuid,text)'),to_regprocedure('public.revoke_staff_invite(uuid)'),to_regprocedure('public.redeem_staff_invite(text)'),to_regprocedure('public.unlink_staff_identity(uuid,text)'),to_regprocedure('public.read_staff_app_access(uuid)')]::oid[]) as f),
  'STI-011: anon cannot execute any of the other six commands');
select ok((select count(f) = 7 and bool_and(not has_function_privilege('service_role', f, 'EXECUTE')) from unnest(array[to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)'),to_regprocedure('public.issue_staff_invite(uuid,text)'),to_regprocedure('public.revoke_staff_invite(uuid)'),to_regprocedure('public.redeem_staff_invite(text)'),to_regprocedure('public.peek_staff_invite(text)'),to_regprocedure('public.unlink_staff_identity(uuid,text)'),to_regprocedure('public.read_staff_app_access(uuid)')]::oid[]) as f),
  'STI-011: service_role cannot execute any of the seven commands');
select ok((select count(f) = 7 and bool_and(not has_function_privilege('public', f, 'EXECUTE')) from unnest(array[to_regprocedure('public.invite_staff_member(text,text,text,public.app_role,uuid,text)'),to_regprocedure('public.issue_staff_invite(uuid,text)'),to_regprocedure('public.revoke_staff_invite(uuid)'),to_regprocedure('public.redeem_staff_invite(text)'),to_regprocedure('public.peek_staff_invite(text)'),to_regprocedure('public.unlink_staff_identity(uuid,text)'),to_regprocedure('public.read_staff_app_access(uuid)')]::oid[]) as f),
  'STI-011: the PUBLIC pseudo-role cannot execute any of the seven commands');
select ok((select count(f) = 1
        and bool_and(not has_function_privilege('anon', f, 'EXECUTE') and not has_function_privilege('authenticated', f, 'EXECUTE')
                     and not has_function_privilege('service_role', f, 'EXECUTE') and not has_function_privilege('public', f, 'EXECUTE'))
     from unnest(array[to_regprocedure('app.staff_invite_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text)')]::oid[]) as f),
  'STI-010: nobody but the owner can execute the audit helper');

-- The binding guard keeps its identity: both existing triggers stay, and the amended function stays a
-- SECURITY INVOKER (a definer would run as its owner for every caller, which would make the
-- current_user test that separates a command from a session meaningless).
select is((select count(*) from pg_trigger t
    where t.tgrelid = 'public.staff'::regclass and not t.tgisinternal
      and t.tgname in ('staff_auth_binding_invariant', 'staff_auth_binding_session_revoke')),
  2::bigint, 'STI-006: the guard trigger and the session-revoke trigger are both still installed on staff');
select ok((select not p.prosecdef and p.proconfig @> array['search_path=""']
        and not has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and not has_function_privilege('service_role', p.oid, 'EXECUTE') and not has_function_privilege('public', p.oid, 'EXECUTE')
     from pg_proc p where p.oid = to_regprocedure('app.enforce_staff_auth_binding()')),
  'STI-006: the amended guard is still an invoker trigger function with a pinned search_path and no API-role execute privilege');

-- Database rules that hold for every writer, proved by direct inserts as postgres.
select lives_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e1', 32), '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  'STI structure: a minimal insert succeeds and relies on the column defaults');
select ok((select i.status::text = 'pending' and i.id is not null and i.issued_at is not null and i.created_at is not null
              and i.updated_at is not null and i.closed_at is null and i.closed_by_staff_id is null and i.redeemed_user_id is null
     from public.staff_invites i where i.token_hash = repeat('e1', 32)),
  'STI structure: defaults are pending, a generated id and timestamps, and no closing facts');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('A', 64), '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_token_hash_format_chk"',
  'STI structure: an uppercase hash is refused by staff_invites_token_hash_format_chk');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('a', 63), '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_token_hash_format_chk"',
  'STI structure: a 63-character hash is refused by staff_invites_token_hash_format_chk');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e2', 32), '68000000-0000-4000-8000-000000000201', now())$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_expiry_chk"',
  'STI structure: expires_at must be later than issued_at (staff_invites_expiry_chk)');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e3', 32), 'pending', '68000000-0000-4000-8000-000000000201', now() + interval '48 hours', now())$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_closed_state_chk"',
  'STI structure: a pending invite cannot carry closed_at (staff_invites_closed_state_chk)');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e3', 32), 'revoked', '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_closed_state_chk"',
  'STI structure: a closed invite must carry closed_at (staff_invites_closed_state_chk)');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at, redeemed_user_id)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e3', 32), 'revoked', '68000000-0000-4000-8000-000000000201', now() + interval '48 hours', now(), '68000000-0000-4000-8000-000000000134')$$,
  '23514', 'new row for relation "staff_invites" violates check constraint "staff_invites_closed_state_chk"',
  'STI structure: only a redeemed invite may name redeemed_user_id (staff_invites_closed_state_chk)');
select lives_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at, redeemed_user_id)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e4', 32), 'redeemed', '68000000-0000-4000-8000-000000000201', now() + interval '48 hours', now(), '68000000-0000-4000-8000-000000000134')$$,
  'STI structure: a redeemed invite may name the redeeming Auth user');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('01', 32), 'revoked', '68000000-0000-4000-8000-000000000201', now() + interval '48 hours', now())$$,
  '23505', 'duplicate key value violates unique constraint "staff_invites_token_hash_key"',
  'STI-001: a token hash can exist once in the whole system');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e6', 32), '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  '23505', 'duplicate key value violates unique constraint "staff_invites_one_pending_key"',
  'STI-002: a staff row cannot hold two pending invites');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at)
    values ('68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-000000000214', repeat('e7', 32), 'revoked', '68000000-0000-4000-8000-000000000207', now() + interval '48 hours', now())$$,
  '23503', null, 'STI-011: the tenant and staff of an invite must belong together (composite key)');
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, status, issued_by_staff_id, expires_at, closed_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000214', repeat('e8', 32), 'revoked', '68000000-0000-4000-8000-000000000207', now() + interval '48 hours', now())$$,
  '23503', null, 'STI-011: the issuing staff of an invite must belong to the invite tenant (composite key)');

-- ===========================================================================
-- 2. THE AUDIT HELPER ALLOWLIST (STI-010). Exactly eight actions; anything else, including
--    the INV actions and the existing staff.* actions, raises 22023. Probed as postgres in
--    gym S under an unused actor, so the probe rows never touch another section's counts.
-- ===========================================================================
set local role postgres;
select set_config('request.jwt.claims','',true);
select lives_ok($$select app.staff_invite_audit('68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-000000000134', 'gym_owner'::public.app_role, a.action,
        case when a.action like 'staff.%' then 'staff' else 'staff_invite' end, '68000000-0000-4000-8000-000000000f01', null, null, null)
     from unnest(array['staff.invited', 'staff_invite.issued', 'staff_invite.superseded', 'staff_invite.revoked',
                       'staff_invite.redeemed', 'staff_invite.redeem_refused', 'staff.linked', 'staff.unlinked']) as a(action)$$,
  'STI-010: all eight allowlisted actions are accepted by the helper');
select is((select count(distinct a.action) from public.audit_log a where a.record_id = '68000000-0000-4000-8000-000000000f01' and a.tenant_id = '68000000-0000-4000-8000-000000000003'),
  8::bigint, 'STI-010: each of the eight actions wrote one audit row');
select throws_ok($$select app.staff_invite_audit('68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-000000000134', 'gym_owner'::public.app_role, 'member_invite.issued', 'member_invite', '68000000-0000-4000-8000-000000000f01', null, null, null)$$,
  '22023', null, 'STI-010: an INV action is not in the staff allowlist');
select throws_ok($$select app.staff_invite_audit('68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-000000000134', 'gym_owner'::public.app_role, 'staff.owner_linked', 'staff', '68000000-0000-4000-8000-000000000f01', null, null, null)$$,
  '22023', null, 'STI-010: the platform owner-link action is not in the staff allowlist');
select throws_ok($$select app.staff_invite_audit('68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-000000000134', 'gym_owner'::public.app_role, 'staff.deactivated', 'staff', '68000000-0000-4000-8000-000000000f01', null, null, null)$$,
  '22023', null, 'STI-010: an existing identity audit action is not in the staff allowlist');
select throws_ok($$select app.staff_invite_audit('68000000-0000-4000-8000-000000000003', '68000000-0000-4000-8000-000000000134', 'gym_owner'::public.app_role, '', 'staff_invite', '68000000-0000-4000-8000-000000000f01', null, null, null)$$,
  '22023', null, 'STI-010: an empty action is refused');


-- ===========================================================================
-- 3. PEEK (STI-007), probed BEFORE any redemption touches the pool. A valid pending invite
--    shows the gym name and the role; every other cause shows nothing at all, so the
--    pre-sign-in endpoint is no oracle for what happened to an invite.
-- ===========================================================================
select set_config('request.jwt.claims','',true);
set local role anon;
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('01',32))$$,
  $$values ('Sti Gym A'::text, 'gym_manager'::text)$$,
  'STI-007: a signed-out caller sees the gym name and the staff role of a pending invite');
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('02',32))$$,
  $$values ('Sti Gym A'::text, 'front_desk'::text)$$,
  'STI-007: the role shown is the role on the staff row, not a constant');
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('03',32))$$,
  $$values ('Sti Gym T'::text, 'trainer'::text)$$,
  'STI-007: a gym on a running trial is eligible');
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('c6', 32))$$,
  $$values ('Sti Gym A'::text, 'front_desk'::text)$$,
  'STI-007: the newer pending invite of a resent row peeks');
select is_empty($$select * from public.peek_staff_invite(repeat('04',32))$$, 'STI-007: an expired pending invite shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('05',32))$$, 'STI-007: a revoked invite shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('06',32))$$, 'STI-007: a superseded invite shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('07',32))$$, 'STI-007: an invite for an inactive staff row shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('08',32))$$, 'STI-007: an invite for an owner row shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('09',32))$$, 'STI-007: an invite for an already linked row shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0a',32))$$, 'STI-007: an invite of a suspended gym shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0b',32))$$, 'STI-007: an invite of a gym whose trial has ended shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0c',32))$$, 'STI-007: an invite whose issuer was deactivated shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0d',32))$$, 'STI-007: an invite whose issuer is no longer an owner shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0e',32))$$, 'STI-007: an invite issued by a non-owner shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('0f',32))$$, 'STI-007: an invite whose row became an owner after issue shows nothing');
select is_empty($$select * from public.peek_staff_invite(repeat('ee', 32))$$, 'STI-007: an unknown hash shows nothing');
select throws_ok($$select * from public.peek_staff_invite('not-a-hash')$$, '22023', null, 'STI-007: a hash that is not 64 hex characters raises 22023');
select throws_ok($$select * from public.peek_staff_invite(repeat('A', 64))$$, '22023', null, 'STI-007: an uppercase hash raises 22023');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a102","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('02',32))$$,
  $$values ('Sti Gym A'::text, 'front_desk'::text)$$,
  'STI-007: a signed-in caller without a gym identity can peek as well');

-- ===========================================================================
-- 4. invite_staff_member (STI-001)
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select staff_id is not null, invite_id is not null, expires_at > now() + interval '40 hours'
     from public.invite_staff_member('Ravi Kumar', 'ravi.sti@example.com', '+919800068801', 'front_desk', '68000000-0000-4000-8000-0000000000b1', repeat('f1', 32))$$,
  $$values (true, true, true)$$,
  'STI-001: a gym owner creates a staff row and its first invite in one call');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select tenant_id, user_id, branch_id, role::text, full_name, phone, email, is_active, qualification, max_active_clients
     from public.staff where tenant_id = '68000000-0000-4000-8000-000000000001' and email = 'ravi.sti@example.com'$$,
  $$values ('68000000-0000-4000-8000-000000000001'::uuid, null::uuid, '68000000-0000-4000-8000-0000000000b1'::uuid, 'front_desk'::text, 'Ravi Kumar'::text, '+919800068801'::text,
            'ravi.sti@example.com'::text, true, null::text, null::smallint)$$,
  'STI-001: the created staff row is active, unlinked, in the owner gym, with exactly the submitted values');
select results_eq($$select i.status::text, i.token_hash = repeat('f1', 32), i.issued_by_staff_id, i.expires_at - i.issued_at = interval '48 hours',
        i.closed_at is null, i.closed_by_staff_id is null, i.redeemed_user_id is null
     from public.staff_invites i join public.staff s on s.id = i.staff_id and s.tenant_id = i.tenant_id
    where i.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'ravi.sti@example.com'$$,
  $$values ('pending'::text, true, '68000000-0000-4000-8000-000000000201'::uuid, true, true, true, true)$$,
  'STI-001: exactly one pending hash-only invite that expires 48 hours after issue and names the issuing owner');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type, a.after
     from public.audit_log a
    where a.action = 'staff.invited'
      and a.record_id = (select s.id from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'ravi.sti@example.com')$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff'::text,
            jsonb_build_object('role', 'front_desk', 'branch_id', '68000000-0000-4000-8000-0000000000b1'::uuid))$$,
  'STI-010: staff.invited is audited against the new staff id with after = {role, branch_id}');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type,
        (select array_agg(k order by k) from jsonb_object_keys(a.after) as k),
        a.after ->> 'staff_id', (a.after ->> 'expires_at')::timestamptz = i.expires_at, jsonb_typeof(a.after -> 'superseded_invite_id')
     from public.audit_log a join public.staff_invites i on i.id = a.record_id
    where a.action = 'staff_invite.issued'
      and i.staff_id = (select s.id from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'ravi.sti@example.com')$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff_invite'::text,
            array['expires_at', 'staff_id', 'superseded_invite_id']::text[],
            (select s.id::text from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'ravi.sti@example.com'),
            true, 'null'::text)$$,
  'STI-010: staff_invite.issued is audited against the invite id with after = {staff_id, expires_at, superseded_invite_id} and nothing else');

select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select staff_id is not null, invite_id is not null
     from public.invite_staff_member('Tina Trainer', 'tina.sti@example.com', null, 'trainer', null, repeat('f2', 32))$$,
  $$values (true, true)$$,
  'STI-001: branch and phone are optional');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select tenant_id, user_id, branch_id, role::text, full_name, phone, is_active
     from public.staff where tenant_id = '68000000-0000-4000-8000-000000000001' and email = 'tina.sti@example.com'$$,
  $$values ('68000000-0000-4000-8000-000000000001'::uuid, null::uuid, null::uuid, 'trainer'::text, 'Tina Trainer'::text, null::text, true)$$,
  'STI-001: a null branch means all branches and a null phone stays null');
select ok((select count(*) = 1 and bool_and(a.after ->> 'role' = 'trainer' and jsonb_typeof(a.after -> 'branch_id') = 'null')
     from public.audit_log a
    where a.action = 'staff.invited'
      and a.record_id = (select s.id from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'tina.sti@example.com')),
  'STI-010: a null branch is audited as an explicit JSON null');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($$select * from public.invite_staff_member('Mo Manager', 'mo.sti@example.com', null, 'gym_manager', null, repeat('f3', 32))$$,
  'STI-001: a manager can be invited');
select lives_ok($$select * from public.invite_staff_member('Pad Person', '  Padded.Sti@Example.COM  ', null, 'front_desk', null, repeat('f4', 32))$$,
  'STI-001: an address with surrounding spaces and mixed case is accepted');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select s.role::text from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'mo.sti@example.com'),
  'gym_manager', 'STI-001: the invited role is the role on the new row');
select is((select count(*) from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and lower(btrim(s.email)) = 'padded.sti@example.com'),
  1::bigint, 'STI-001: the padded address created exactly one staff row');

-- Refusals. Each refusal is probed with otherwise valid input, so only the cause under test is wrong.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Refuse Role', 'refuse.sti@example.com', null, 'gym_owner', null, repeat('e9', 32))$$,
  'GL082', null, 'STI-001: the role gym_owner is not invitable');
select throws_ok($$select * from public.invite_staff_member('Refuse Role', 'refuse.sti@example.com', null, 'member', null, repeat('e9', 32))$$,
  'GL082', null, 'STI-001: the role member is not invitable');
select throws_ok($$select * from public.invite_staff_member('Refuse Role', 'refuse.sti@example.com', null, 'super_admin', null, repeat('e9', 32))$$,
  'GL082', null, 'STI-001: the role super_admin is not invitable');
select throws_ok($$select * from public.invite_staff_member('Refuse Role', 'refuse.sti@example.com', null, 'platform_support', null, repeat('e9', 32))$$,
  'GL082', null, 'STI-001: the role platform_support is not invitable');
select throws_ok($$select * from public.invite_staff_member('Refuse Role', 'refuse.sti@example.com', null, null::public.app_role, null, repeat('e9', 32))$$,
  'GL082', null, 'STI-001: a null role is not invitable');
select throws_ok($$select * from public.invite_staff_member('Dup Exact', 'ravi.sti@example.com', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL081', null, 'STI-001: an address already used by an active staff row of the gym is refused');
select throws_ok($$select * from public.invite_staff_member('Dup Case', '  RAVI.STI@EXAMPLE.COM ', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL081', null, 'STI-001: the duplicate check is trimmed and case-insensitive');
select throws_ok($$select * from public.invite_staff_member('Dup Padded', 'PADDED.STI@example.com', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL081', null, 'STI-001: a row created from a padded mixed-case address still blocks the clean spelling');
select throws_ok($$select * from public.invite_staff_member('Dup Inactive', 'issue4.sti@example.com', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL081', null, 'STI-001: an address used by an INACTIVE staff row of the gym is refused too');
select throws_ok($$select * from public.invite_staff_member('Dup Owner', 'owner.a.sti@example.com', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL081', null, 'STI-001: the gym owner address counts as used');
select throws_ok($$select * from public.invite_staff_member('Bad Email', null, null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: a null email is refused');
select throws_ok($$select * from public.invite_staff_member('Bad Email', '', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: an empty email is refused');
select throws_ok($$select * from public.invite_staff_member('Bad Email', '   ', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: a blank email is refused');
select throws_ok($$select * from public.invite_staff_member('Bad Email', 'plainaddress', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: an address without @ is refused');
select throws_ok($$select * from public.invite_staff_member('Bad Email', 'user@nodot', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: an address whose domain has no dot is refused');
select throws_ok($$select * from public.invite_staff_member('Bad Email', 'sp ace@x.com', null, 'front_desk', null, repeat('e9', 32))$$,
  'GL076', null, 'STI-001: an address with whitespace inside is refused');
select throws_ok($$select * from public.invite_staff_member('Branch Probe', 'refuse.sti@example.com', null, 'front_desk', '68000000-0000-4000-8000-0000000000b3', repeat('e9', 32))$$,
  '42501', null, 'STI-001: a branch of another gym is refused with 42501');
select throws_ok($$select * from public.invite_staff_member('Branch Probe', 'refuse.sti@example.com', null, 'front_desk', '68000000-0000-4000-8000-0000000fffff', repeat('e9', 32))$$,
  '42501', null, 'STI-001: an unknown branch is indistinguishable from a foreign one');
select throws_ok($$select * from public.invite_staff_member('Hash Probe', 'refuse.sti@example.com', null, 'front_desk', null, repeat('A', 64))$$,
  '22023', null, 'STI-001: an uppercase hash is malformed input');
select throws_ok($$select * from public.invite_staff_member('Hash Probe', 'refuse.sti@example.com', null, 'front_desk', null, repeat('a', 63))$$,
  '22023', null, 'STI-001: a 63-character hash is malformed input');
select throws_ok($$select * from public.invite_staff_member('Hash Probe', 'refuse.sti@example.com', null, 'front_desk', null, null::text)$$,
  '22023', null, 'STI-001: a null hash is malformed input');
select throws_ok($$select * from public.invite_staff_member('Atomic Probe', 'refuse.sti@example.com', null, 'front_desk', null, repeat('01',32))$$,
  '23505', null, 'STI-001: a hash that is already in use fails the whole call');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is_empty($$select 1 from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and lower(btrim(s.email)) = 'refuse.sti@example.com'$$,
  'STI-001: no refusal, including the one that fails at the invite insert, leaves a staff row behind');
select is((select count(*) from public.audit_log a where a.tenant_id = '68000000-0000-4000-8000-000000000001' and a.action = 'staff.invited'),
  4::bigint, 'STI-010: only the four successful calls were audited as staff.invited');

-- The duplicate check is scoped to the gym: another gym may invite the same address.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000107","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000002","staff_id":"68000000-0000-4000-8000-000000000207"}',true);
set local role authenticated;
select lives_ok($$select * from public.invite_staff_member('Cross Gym Same Email', 'owner.a.sti@example.com', null, 'front_desk', null, repeat('f0', 32))$$,
  'STI-001: the duplicate rule is per gym, so another gym can use the same address');
select is((select count(*) from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000002' and s.email = 'owner.a.sti@example.com'),
  1::bigint, 'STI-001: the cross-gym invite created its row in the caller gym');


-- ===========================================================================
-- 5. issue_staff_invite and revoke_staff_invite (STI-002)
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select invite_id is not null, expires_at > now() + interval '40 hours', superseded_invite_id is null
     from public.issue_staff_invite('68000000-0000-4000-8000-000000000221', repeat('f5', 32))$$,
  $$values (true, true, true)$$,
  'STI-002: an owner issues the first invite for an invitable staff row');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*), count(*) filter (where status = 'pending'), bool_and(token_hash = repeat('f5', 32)),
        bool_and(issued_by_staff_id = '68000000-0000-4000-8000-000000000201'), bool_and(expires_at - issued_at = interval '48 hours'), bool_and(tenant_id = '68000000-0000-4000-8000-000000000001')
     from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000221'$$,
  $$values (1::bigint, 1::bigint, true, true, true, true)$$,
  'STI-002: one pending hash-only invite, 48 hours, issued by the calling owner');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type,
        (select array_agg(k order by k) from jsonb_object_keys(a.after) as k),
        a.after ->> 'staff_id', jsonb_typeof(a.after -> 'superseded_invite_id'), (a.after ->> 'expires_at')::timestamptz = i.expires_at
     from public.audit_log a join public.staff_invites i on i.id = a.record_id
    where a.action = 'staff_invite.issued' and i.staff_id = '68000000-0000-4000-8000-000000000221'$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff_invite'::text,
            array['expires_at', 'staff_id', 'superseded_invite_id']::text[], '68000000-0000-4000-8000-000000000221'::text, 'null'::text, true)$$,
  'STI-010: a first issue is audited with a null superseded_invite_id');

-- Resend over a valid pending invite: the old one is superseded in the same call.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select invite_id is not null, superseded_invite_id
     from public.issue_staff_invite('68000000-0000-4000-8000-000000000222', repeat('f6', 32))$$,
  $$values (true, '68000000-0000-4000-8000-000000000502'::uuid)$$,
  'STI-002: a resend returns the id of the invite it superseded');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text, closed_at is not null, redeemed_user_id is null
     from public.staff_invites where id = '68000000-0000-4000-8000-000000000502'$$,
  $$values ('superseded'::text, true, true)$$,
  'STI-002: the superseded invite is closed');
select results_eq($$select count(*), count(*) filter (where status = 'pending'), count(*) filter (where status = 'superseded')
     from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000222'$$,
  $$values (2::bigint, 1::bigint, 1::bigint)$$,
  'STI-002: after a resend the row has exactly one pending invite');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type, a.before,
        a.after = jsonb_build_object('status', 'superseded',
                    'replaced_by', (select i.id from public.staff_invites i where i.staff_id = '68000000-0000-4000-8000-000000000222' and i.status = 'pending'))
     from public.audit_log a where a.action = 'staff_invite.superseded' and a.record_id = '68000000-0000-4000-8000-000000000502'$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff_invite'::text, '{"status":"pending"}'::jsonb, true)$$,
  'STI-010: staff_invite.superseded is audited with before {status:pending} and after {status:superseded, replaced_by}');
select is((select min(a.after ->> 'superseded_invite_id') from public.audit_log a join public.staff_invites i on i.id = a.record_id
    where a.action = 'staff_invite.issued' and i.staff_id = '68000000-0000-4000-8000-000000000222' and i.status = 'pending'),
  '68000000-0000-4000-8000-000000000502'::text, 'STI-010: the resend issue row names the invite it replaced');
select set_config('request.jwt.claims','',true);
set local role anon;
select is_empty($$select * from public.peek_staff_invite(repeat('a2', 32))$$, 'STI-002: the superseded token no longer peeks');
select results_eq($$select gym_name, staff_role::text from public.peek_staff_invite(repeat('f6', 32))$$,
  $$values ('Sti Gym A'::text, 'trainer'::text)$$, 'STI-002: the new token peeks');

-- Resend over an expired pending invite: an expired invite is still pending in the table.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select superseded_invite_id from public.issue_staff_invite('68000000-0000-4000-8000-000000000223', repeat('f8', 32))$$,
  $$values ('68000000-0000-4000-8000-000000000503'::uuid)$$, 'STI-002: a resend supersedes a pending invite even when it has expired');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*) filter (where status = 'pending'), count(*) filter (where status = 'superseded' and closed_at is not null), count(*)
     from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000223'$$,
  $$values (1::bigint, 1::bigint, 2::bigint)$$, 'STI-002: the expired invite was closed and replaced by one pending invite');

-- Refusals.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000224', repeat('e9', 32))$$, 'GL075', null, 'STI-002: an inactive staff row is not invitable');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000211', repeat('e9', 32))$$, 'GL075', null, 'STI-002: a gym_owner row is never invitable');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000225', repeat('e9', 32))$$, 'GL077', null, 'STI-002: a staff row that is already linked is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000226', repeat('e9', 32))$$, 'GL076', null, 'STI-002: a staff row without an email is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000227', repeat('e9', 32))$$, 'GL076', null, 'STI-002: a staff row with a blank email is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f101', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email without @ is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f102', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email with two @ in a row is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f103', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email whose domain has no dot is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f104', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email with whitespace inside is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f105', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email with an empty local part is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000f106', repeat('e9', 32))$$, 'GL076', null, 'STI-002: an email with two @ separated by text is refused');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-0000000fffff', repeat('e9', 32))$$, '42501', null, 'STI-002: an unknown staff id is refused as forbidden');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000213', repeat('e9', 32))$$, '42501', null, 'STI-002: a staff row of another gym is indistinguishable from an unknown one');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000221', repeat('A', 64))$$, '22023', null, 'STI-002: an uppercase hash is malformed input');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000221', repeat('a', 63))$$, '22023', null, 'STI-002: a 63-character hash is malformed input');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000221', null::text)$$, '22023', null, 'STI-002: a null hash is malformed input');
select lives_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000228', repeat('f9', 32))$$, 'STI-002: an email with surrounding spaces is still invitable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000108","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000003","staff_id":"68000000-0000-4000-8000-000000000208"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000b10a', repeat('e9', 32))$$, 'GL075', null, 'STI-002: a suspended gym is not eligible');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010a","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000005","staff_id":"68000000-0000-4000-8000-00000000020a"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000b10b', repeat('e9', 32))$$, 'GL075', null, 'STI-002: a gym whose trial has ended is not eligible');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.staff_invites
    where staff_id in ('68000000-0000-4000-8000-000000000224', '68000000-0000-4000-8000-000000000211', '68000000-0000-4000-8000-000000000225', '68000000-0000-4000-8000-000000000226', '68000000-0000-4000-8000-000000000227', '68000000-0000-4000-8000-00000000f101', '68000000-0000-4000-8000-00000000f102', '68000000-0000-4000-8000-00000000f103', '68000000-0000-4000-8000-00000000f104', '68000000-0000-4000-8000-00000000f105', '68000000-0000-4000-8000-00000000f106')),
  0::bigint, 'STI-002: no refused issue left an invite behind');
select results_eq($$select count(*), count(*) filter (where status = 'pending') from public.staff_invites where staff_id in ('68000000-0000-4000-8000-00000000b10a', '68000000-0000-4000-8000-00000000b10b')$$,
  $$values (2::bigint, 2::bigint)$$, 'STI-002: the ineligible-gym refusals left the existing invites untouched');
select results_eq($$select count(*), count(*) filter (where status = 'pending' and token_hash = repeat('f5', 32)) from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000221'$$,
  $$values (1::bigint, 1::bigint)$$, 'STI-002: malformed-hash refusals changed nothing for a row that already had a pending invite');
select ok((select count(*) = 1 and bool_and(status = 'pending') from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000228'),
  'STI-002: the padded-address row has its one pending invite');
select is((select count(*) from public.audit_log where tenant_id = '68000000-0000-4000-8000-000000000001' and action = 'staff_invite.issued'),
  8::bigint, 'STI-010: exactly eight successful issues in gym A so far were audited (four creates, four issues)');
select is((select count(*) from public.audit_log where tenant_id = '68000000-0000-4000-8000-000000000001' and action = 'staff_invite.superseded'),
  2::bigint, 'STI-010: exactly two supersessions were audited');

-- Revoke.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000531')$$, $$values ('68000000-0000-4000-8000-000000000531'::uuid)$$,
  'STI-002: revoking a pending invite returns its id');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text, closed_at is not null, closed_by_staff_id, redeemed_user_id from public.staff_invites where id = '68000000-0000-4000-8000-000000000531'$$,
  $$values ('revoked'::text, true, '68000000-0000-4000-8000-000000000201'::uuid, null::uuid)$$, 'STI-002: the revoked invite is closed by the revoking owner');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type, a.before, a.after
     from public.audit_log a where a.action = 'staff_invite.revoked' and a.record_id = '68000000-0000-4000-8000-000000000531'$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff_invite'::text, '{"status":"pending"}'::jsonb, '{"status":"revoked"}'::jsonb)$$,
  'STI-010: staff_invite.revoked is audited with before {status:pending} and after {status:revoked}');
select set_config('request.jwt.claims','',true);
set local role anon;
select is_empty($$select * from public.peek_staff_invite(repeat('b1', 32))$$, 'STI-002: a revoked token no longer peeks');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000531')$$, 'GL079', null, 'STI-002: revoking an already revoked invite fails GL079');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000532')$$, 'GL079', null, 'STI-002: revoking a revoked invite fails GL079');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000533')$$, 'GL079', null, 'STI-002: revoking a redeemed invite fails GL079');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000534')$$, 'GL079', null, 'STI-002: revoking a superseded invite fails GL079');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-0000000fffff')$$, '42501', null, 'STI-002: an unknown invite is refused as forbidden');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000513')$$, '42501', null, 'STI-002: an invite of another gym is indistinguishable from an unknown one');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000213', repeat('e9', 32))$$, '42501', null, 'STI-011: issuing for another gym staff row is refused as forbidden');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000213', 'cross gym probe')$$, '42501', null, 'STI-011: unlinking another gym staff row is refused as forbidden, not GL080');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000213')$$, '42501', null, 'STI-011: reading another gym staff row is refused as forbidden');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select status::text from public.staff_invites where id = '68000000-0000-4000-8000-000000000513'$$, $$values ('pending'::text)$$,
  'STI-011: the other gym invite is still pending after the cross-gym attempts');
select results_eq($$select i.status::text from public.staff_invites i where i.id in ('68000000-0000-4000-8000-000000000532', '68000000-0000-4000-8000-000000000533', '68000000-0000-4000-8000-000000000534') order by i.id$$,
  $$values ('revoked'::text), ('redeemed'::text), ('superseded'::text)$$, 'STI-002: refused revokes did not alter closed invites');

-- ===========================================================================
-- 6. OWNER-ONLY MATRIX (STI-001, 002, 008, 009, 011): every persona that is not a real,
--    active gym owner of the right gym is refused 42501 by every command. The impersonator
--    appears twice: once with a COMPLETE staff identity plus the impersonation claim (so
--    that only the impersonation rule can refuse it) and once as a realistic preview token.
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000102","role":"authenticated","app_role":"gym_manager","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000202"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a gym manager cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a gym manager cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a gym manager cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a gym manager cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a gym manager cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000103","role":"authenticated","app_role":"front_desk","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000203"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: front desk cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: front desk cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: front desk cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: front desk cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: front desk cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000104","role":"authenticated","app_role":"trainer","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000204"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a trainer cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a trainer cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a trainer cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a trainer cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a trainer cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000105","role":"authenticated","app_role":"member","tenant_id":"68000000-0000-4000-8000-000000000001","member_id":"68000000-0000-4000-8000-000000000301"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a member cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a member cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a member cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a member cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a member cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000106","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a super admin cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a super admin cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a super admin cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a super admin cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a super admin cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010e","role":"authenticated","app_role":"platform_support"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: platform support cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: platform support cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: platform support cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: platform support cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: platform support cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201","impersonation_session_id":"68000000-0000-4000-8000-000000000f02"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: an impersonating owner with a complete staff identity cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: an impersonating owner with a complete staff identity cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: an impersonating owner with a complete staff identity cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: an impersonating owner with a complete staff identity cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: an impersonating owner with a complete staff identity cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000106","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","impersonation_session_id":"68000000-0000-4000-8000-000000000f02"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a realistic preview token cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a realistic preview token cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a realistic preview token cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a realistic preview token cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a realistic preview token cannot read staff app access');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000107","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000002","staff_id":"68000000-0000-4000-8000-000000000207"}',true);
set local role authenticated;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: the owner of another gym cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: the owner of another gym cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: the owner of another gym cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: the owner of another gym cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: the owner of another gym cannot read staff app access');
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select * from public.invite_staff_member('Matrix Person','matrix.sti@example.com',null,'front_desk',null,repeat('ea',32))$$,'42501',null,'STI-001/011: a signed-out anon caller cannot create and invite a staff member');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215',repeat('ea',32))$$,'42501',null,'STI-002/011: a signed-out anon caller cannot issue a staff invite');
select throws_ok($$select public.revoke_staff_invite('68000000-0000-4000-8000-000000000535')$$,'42501',null,'STI-002/011: a signed-out anon caller cannot revoke a staff invite');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249','matrix probe reason')$$,'42501',null,'STI-008/011: a signed-out anon caller cannot unlink a staff identity');
select throws_ok($$select * from public.read_staff_app_access('68000000-0000-4000-8000-000000000215')$$,'42501',null,'STI-009/011: a signed-out anon caller cannot read staff app access');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is_empty($$select 1 from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000001' and s.email = 'matrix.sti@example.com'$$,
  'STI-011: no refused persona created a staff row');
select is((select count(*) from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000215'), 0::bigint,
  'STI-011: no refused persona issued an invite for the matrix target');
select is((select status::text from public.staff_invites where id = '68000000-0000-4000-8000-000000000535'), 'pending',
  'STI-011: no refused persona revoked the matrix invite');
select results_eq($$select s.user_id, (select count(*) from auth.sessions x where x.user_id = '68000000-0000-4000-8000-000000000119') from public.staff s where s.id = '68000000-0000-4000-8000-000000000249'$$,
  $$values ('68000000-0000-4000-8000-000000000119'::uuid, 2::bigint)$$, 'STI-011: no refused persona unlinked the control row or deleted its sessions');

-- Forged, stale and malformed owner claims are refused by the actor check alone.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000102","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000202"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215', repeat('ea', 32))$$, '42501', null,
  'STI-011: a manager whose token claims gym_owner is refused (claim role must equal the staff row role)');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000249', 'forged probe reason')$$, '42501', null,
  'STI-011: the same forged role is refused by unlink');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000102","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215', repeat('ea', 32))$$, '42501', null,
  'STI-011: owner claims whose subject is not the user of the named staff row are refused');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010d","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-00000000020d"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215', repeat('ea', 32))$$, '42501', null,
  'STI-011: a deactivated owner row with live owner claims is refused');
select throws_ok($$select * from public.invite_staff_member('Dead Owner Probe', 'matrix.sti@example.com', null, 'front_desk', null, repeat('ea', 32))$$, '42501', null,
  'STI-001: a deactivated owner cannot create staff either');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201","member_id":"68000000-0000-4000-8000-000000000301"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215', repeat('ea', 32))$$, '42501', null,
  'STI-011: owner claims that also carry a member id are refused');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000002","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-000000000215', repeat('ea', 32))$$, '42501', null,
  'STI-011: a tenant claim that differs from the staff row tenant is refused');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.staff_invites where staff_id = '68000000-0000-4000-8000-000000000215'), 0::bigint,
  'STI-011: no forged or stale claim issued an invite');


-- ===========================================================================
-- 7. LIMITS (STI-003): 30 issues per gym per rolling hour and 5 per staff row per rolling
--    24 hours, counted over staff_invites.issued_at, by BOTH issue_staff_invite and
--    invite_staff_member. A refusal is GL078 and writes nothing.
--
--    Gym L1 holds 29 invites from ten minutes ago over six rows (5,5,5,5,5,4), ten more from
--    two hours ago over two other rows (5 each) and a fresh row. Margins on every window are
--    at least an hour, so the suite clock cannot push a row across a boundary.
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010b","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000006","staff_id":"68000000-0000-4000-8000-00000000020b"}',true);
set local role authenticated;
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000e101', repeat('eb', 32))$$, 'GL078', null,
  'STI-003: a row with five invites inside 24 hours is refused although the gym is under its hourly limit');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000e201', repeat('eb', 32))$$, 'GL078', null,
  'STI-003: invites older than the gym hour still count toward the per-row day');
select results_eq($$select staff_id is not null, invite_id is not null
     from public.invite_staff_member('L1 Fresh', 'l1.fresh.sti@example.com', null, 'front_desk', null, repeat('fa', 32))$$,
  $$values (true, true)$$,
  'STI-003: the thirtieth invite of the hour is allowed, so the ten invites from two hours ago do not count toward the hour');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000e301', repeat('eb', 32))$$, 'GL078', null,
  'STI-003: the thirty-first invite of the hour is refused, so invite_staff_member counted toward the gym limit');
select throws_ok($$select * from public.invite_staff_member('L1 Fresh Two', 'l1.fresh2.sti@example.com', null, 'front_desk', null, repeat('eb', 32))$$,
  'GL078', null, 'STI-003: invite_staff_member is refused at the gym limit');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000e106', repeat('eb', 32))$$, 'GL078', null,
  'STI-003: a row with only four invites is refused at the gym limit, which is independent of the per-row count');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is_empty($$select 1 from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000006' and s.email = 'l1.fresh2.sti@example.com'$$,
  'STI-003: a refused create leaves no staff row behind');
select is((select count(*) from public.staff_invites where tenant_id = '68000000-0000-4000-8000-000000000006'), 40::bigint,
  'STI-003: the refusals wrote no invite (29 recent, 10 older, 1 allowed)');
select is((select count(*) from public.audit_log where tenant_id = '68000000-0000-4000-8000-000000000006' and action in ('staff.invited', 'staff_invite.issued')), 2::bigint,
  'STI-003: only the allowed call was audited (one staff.invited and one staff_invite.issued)');

-- Gym L2: per-row day window.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010c","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000007","staff_id":"68000000-0000-4000-8000-00000000020c"}',true);
set local role authenticated;
select results_eq($$select invite_id is not null, superseded_invite_id is null
     from public.issue_staff_invite('68000000-0000-4000-8000-00000000e402', repeat('fc', 32))$$,
  $$values (true, true)$$,
  'STI-003: five invites issued 25 hours ago do not count toward the per-row limit');
select results_eq($$select invite_id is not null from public.issue_staff_invite('68000000-0000-4000-8000-00000000e401', repeat('fd', 32))$$,
  $$values (true)$$,
  'STI-003: the fifth invite inside 24 hours is allowed (four earlier ones, the oldest 23 hours ago)');
select throws_ok($$select * from public.issue_staff_invite('68000000-0000-4000-8000-00000000e401', repeat('eb', 32))$$, 'GL078', null,
  'STI-003: the sixth invite inside 24 hours is refused');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*), count(*) filter (where status = 'pending'), bool_and(token_hash = repeat('fd', 32) or status <> 'pending')
     from public.staff_invites where staff_id = '68000000-0000-4000-8000-00000000e401'$$,
  $$values (5::bigint, 1::bigint, true)$$,
  'STI-003: the refused sixth call wrote nothing and did not supersede the pending invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000010c","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000007","staff_id":"68000000-0000-4000-8000-00000000020c"}',true);
set local role authenticated;
select results_eq($$select staff_id is not null, invite_id is not null
     from public.invite_staff_member('L2 Fresh', 'l2.fresh.sti@example.com', null, 'trainer', null, repeat('fe', 32))$$,
  $$values (true, true)$$, 'STI-003: a staff row created by invite_staff_member starts with one invite');
select lives_ok($$select public.issue_staff_invite((select s.id from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000007' and s.email = 'l2.fresh.sti@example.com'), h)
     from unnest(array[repeat('c1', 32), repeat('c2', 32), repeat('c3', 32), repeat('c4', 32)]) as h$$,
  'STI-003: four resends after the create are allowed (five invites in total for the row)');
select throws_ok($$select * from public.issue_staff_invite((select s.id from public.staff s where s.tenant_id = '68000000-0000-4000-8000-000000000007' and s.email = 'l2.fresh.sti@example.com'), repeat('eb', 32))$$,
  'GL078', null, 'STI-003: the sixth invite is refused, so the create by invite_staff_member counted toward the per-row limit');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*), count(*) filter (where status = 'pending'), count(*) filter (where status = 'superseded')
     from public.staff_invites i join public.staff s on s.id = i.staff_id
    where s.tenant_id = '68000000-0000-4000-8000-000000000007' and s.email = 'l2.fresh.sti@example.com'$$,
  $$values (5::bigint, 1::bigint, 4::bigint)$$,
  'STI-003: the row has five invites, four superseded and one pending');


-- ===========================================================================
-- 8. REDEEM (STI-004, STI-005, STI-006 as exercised through the command)
--
--    Every refusal is a returned row with gym_name and staff_role null; it commits together
--    with its audit row. Each case below differs from a perfectly good redemption in
--    exactly one respect (see the case table in the fixtures).
-- ===========================================================================

-- 8.1 The happy path: case 01, a manager. The staff row carries a padded mixed-case address
--     (" Mixed.Case01@Example.com "), the Google identity the lower-case spelling, and the
--     Auth account email is a decoy, so only the Google identity can make this succeed.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a101","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('01',32))$$,
  $$values ('linked'::text, 'Sti Gym A'::text, 'gym_manager'::text)$$,
  'STI-004: a verified Google account whose identity email matches the row (trimmed, case-insensitive) is linked');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select user_id from public.staff where id = '68000000-0000-4000-8000-00000000b101'), '68000000-0000-4000-8000-00000000a101'::uuid,
  'STI-004: staff.user_id is the redeeming Auth user');
select ok((select row(s.tenant_id, s.branch_id, s.role::text, s.full_name, s.phone, s.email, s.is_active, s.qualification, s.max_active_clients, s.created_at)
             is not distinct from
             row('68000000-0000-4000-8000-000000000001'::uuid, '68000000-0000-4000-8000-0000000000b1'::uuid, 'gym_manager'::text, 'Mixed Case Manager'::text, '+919800068001'::text,
                 ' Mixed.Case01@Example.com '::text, true, null::text, null::smallint, now())
     from public.staff s where s.id = '68000000-0000-4000-8000-00000000b101'),
  'STI-005: redemption changes only user_id; role, branch, name, phone, email and status of the row are untouched');
select results_eq($$select status::text, redeemed_user_id, closed_at is not null from public.staff_invites where id = '68000000-0000-4000-8000-00000000c101'$$,
  $$values ('redeemed'::text, '68000000-0000-4000-8000-00000000a101'::uuid, true)$$,
  'STI-004: the invite is redeemed by that user and closed');
select results_eq($$select (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-00000000a101'),
        (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-00000000a120'),
        (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-00000000a102')$$,
  $$values (0::bigint, 2::bigint, 2::bigint)$$,
  'STI-004: the existing binding trigger deleted the invitee sessions and only theirs');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-00000000a101',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-00000000a101', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'gym_manager', 'tenant_id', '68000000-0000-4000-8000-000000000001', 'staff_id', '68000000-0000-4000-8000-00000000b101'),
  'STI-004/005: the access-token hook mints the staff claims, with app_role taken from the row');
select results_eq($$select a.actor_user_id, a.tenant_id, a.record_type, a.before, a.after,
        (a.actor_role is null or a.actor_role::text = 'gym_manager')
     from public.audit_log a where a.action = 'staff_invite.redeemed' and a.record_id = '68000000-0000-4000-8000-00000000c101'$$,
  $$values ('68000000-0000-4000-8000-00000000a101'::uuid, '68000000-0000-4000-8000-000000000001'::uuid, 'staff_invite'::text, '{"status":"pending"}'::jsonb,
            jsonb_build_object('status', 'redeemed', 'staff_id', '68000000-0000-4000-8000-00000000b101'::uuid), true)$$,
  'STI-010: staff_invite.redeemed is audited under the redeeming user with before {status:pending} and after {status:redeemed, staff_id}');
select results_eq($$select a.actor_user_id, a.tenant_id, a.record_type, a.before, a.after,
        (a.actor_role is null or a.actor_role::text = 'gym_manager')
     from public.audit_log a where a.action = 'staff.linked' and a.record_id = '68000000-0000-4000-8000-00000000b101'$$,
  $$values ('68000000-0000-4000-8000-00000000a101'::uuid, '68000000-0000-4000-8000-000000000001'::uuid, 'staff'::text, '{"user_linked":false}'::jsonb,
            jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', '68000000-0000-4000-8000-00000000c101'::uuid, 'role', 'gym_manager'), true)$$,
  'STI-010: staff.linked is audited with after {user_linked, via, invite_id, role}');
select ok(exists(select 1 from pg_locks l
    where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
      and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('identity-bind:' || '68000000-0000-4000-8000-00000000a101', 0)),
  'STI-004: redeem took the per-account advisory lock with the exact INV key identity-bind:<uid>');
select is(current_setting('app.staff_binding_command', true), '',
  'STI-006: the transaction-local binding command setting is reset to empty right after the write');
select set_config('request.jwt.claims','',true);
set local role anon;
select is_empty($$select * from public.peek_staff_invite(repeat('01',32))$$, 'STI-007: a redeemed token no longer peeks');

-- 8.2 Replay: the account recorded on a redeemed invite gets already_linked_here with no write;
--     anybody else gets the generic refusal.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a101","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('01',32))$$,
  $$values ('already_linked_here'::text, 'Sti Gym A'::text, 'gym_manager'::text)$$,
  'STI-004: presenting the token again as the linked account is an idempotent already_linked_here');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log where record_id = '68000000-0000-4000-8000-00000000c101'
            and action in ('staff_invite.redeemed', 'staff_invite.redeem_refused')),
  1::bigint, 'STI-004: the replay wrote nothing');
select is((select count(*) from public.audit_log where record_id = '68000000-0000-4000-8000-00000000b101' and action = 'staff.linked'),
  1::bigint, 'STI-004: the replay did not write a second link row');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a110","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('01',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$,
  'STI-004: a different account presenting a redeemed token is told the generic refusal');

-- 8.3 More successful links: a front desk (02), a trainer in a running trial gym (03), an
--     operator-provisioned account that also has a password identity (21), and an account
--     whose old refusals fall outside the throttle window (27).
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a102","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('02',32))$$,
  $$values ('linked'::text, 'Sti Gym A'::text, 'front_desk'::text)$$, 'STI-004: a front desk invite links with the front_desk role');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a103","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('03',32))$$,
  $$values ('linked'::text, 'Sti Gym T'::text, 'trainer'::text)$$, 'STI-004: a trainer invite in a running trial gym links with the trainer role');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a115","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('15',32))$$,
  $$values ('linked'::text, 'Sti Gym A'::text, 'front_desk'::text)$$,
  'STI-004: Google plus password identities are accepted when the account is operator provisioned (PROV-006a)');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11b","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1b',32))$$,
  $$values ('linked'::text, 'Sti Gym A'::text, 'front_desk'::text)$$,
  'STI-004: twelve refusals older than the 15 minute window do not throttle');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select user_id, role::text, is_active, branch_id from public.staff where id = '68000000-0000-4000-8000-00000000b102'$$,
  $$values ('68000000-0000-4000-8000-00000000a102'::uuid, 'front_desk'::text, true, null::uuid)$$, 'STI-005: the front desk row is bound and otherwise unchanged');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-00000000a102',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-00000000a102', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'front_desk', 'tenant_id', '68000000-0000-4000-8000-000000000001', 'staff_id', '68000000-0000-4000-8000-00000000b102'),
  'STI-005: the hook mints front_desk claims for the front desk row');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-00000000a103',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-00000000a103', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'trainer', 'tenant_id', '68000000-0000-4000-8000-000000000004', 'staff_id', '68000000-0000-4000-8000-00000000b103'),
  'STI-005: the hook mints trainer claims for the trial gym row');
select results_eq($$select (select user_id from public.staff where id = '68000000-0000-4000-8000-00000000b115'), (select user_id from public.staff where id = '68000000-0000-4000-8000-00000000b11b')$$,
  $$values ('68000000-0000-4000-8000-00000000a115'::uuid, '68000000-0000-4000-8000-00000000a11b'::uuid)$$, 'STI-004: the provisioned account and the account with stale refusals are both bound');

-- 8.4 invite_unavailable: fourteen different reasons, one generic refusal. Every caller is a
--     perfectly verified account with a matching email, so the invite or the row is the only
--     thing that can be wrong. (16 is the replay above.)
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a104","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('04',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an expired pending invite is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a105","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('05',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: a revoked invite is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a106","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('06',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: a superseded invite is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a107","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('07',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite for an inactive staff row is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a108","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('08',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-006: an owner row can never be linked by an invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a109","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('09',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: a row that is already bound is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10a","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0a',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite of a suspended gym is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10b","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0b',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite of a gym whose trial has ended is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10c","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0c',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite whose issuer was deactivated is unavailable (revalidated at redemption)');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10d","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0d',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite whose issuer is no longer an owner is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10e","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0e',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-004: an invite issued by a non-owner is unavailable');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a10f","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('0f',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$, 'STI-006: a row promoted to owner after issue can no longer be linked');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11f","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1f',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$,
  'STI-004: an unavailable invite is reported as such even when the caller is also unverified (state is checked before identity)');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log a
    join (values ('68000000-0000-4000-8000-00000000a104'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a105'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a106'::uuid, '68000000-0000-4000-8000-000000000001'::uuid),
                 ('68000000-0000-4000-8000-00000000a107'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a108'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a109'::uuid, '68000000-0000-4000-8000-000000000001'::uuid),
                 ('68000000-0000-4000-8000-00000000a10a'::uuid, '68000000-0000-4000-8000-000000000003'::uuid), ('68000000-0000-4000-8000-00000000a10b'::uuid, '68000000-0000-4000-8000-000000000005'::uuid), ('68000000-0000-4000-8000-00000000a10c'::uuid, '68000000-0000-4000-8000-000000000001'::uuid),
                 ('68000000-0000-4000-8000-00000000a10d'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a10e'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a10f'::uuid, '68000000-0000-4000-8000-000000000001'::uuid),
                 ('68000000-0000-4000-8000-00000000a110'::uuid, '68000000-0000-4000-8000-000000000001'::uuid), ('68000000-0000-4000-8000-00000000a11f'::uuid, '68000000-0000-4000-8000-000000000001'::uuid)) as v(u, t)
      on a.actor_user_id = v.u and a.tenant_id = v.t
   where a.action = 'staff_invite.redeem_refused' and a.record_type = 'staff_invite'
     and a.after = '{"outcome":"invite_unavailable"}'::jsonb),
  14::bigint, 'STI-010: every unavailable refusal wrote one staff_invite.redeem_refused row with the resolved gym and after = {outcome}');
select is((select count(*) from public.audit_log a
   where a.actor_user_id in ('68000000-0000-4000-8000-00000000a104', '68000000-0000-4000-8000-00000000a105', '68000000-0000-4000-8000-00000000a106', '68000000-0000-4000-8000-00000000a107', '68000000-0000-4000-8000-00000000a108', '68000000-0000-4000-8000-00000000a109', '68000000-0000-4000-8000-00000000a10a', '68000000-0000-4000-8000-00000000a10b', '68000000-0000-4000-8000-00000000a10c',
                             '68000000-0000-4000-8000-00000000a10d', '68000000-0000-4000-8000-00000000a10e', '68000000-0000-4000-8000-00000000a10f', '68000000-0000-4000-8000-00000000a110', '68000000-0000-4000-8000-00000000a11f')
     and a.action in ('staff_invite.redeem_refused', 'staff_invite.redeemed', 'staff.linked', 'member_invite.redeem_refused')),
  14::bigint, 'STI-010: exactly one audit row per refusal and nothing else');
select is((select count(*) from public.staff s
   where s.id in ('68000000-0000-4000-8000-00000000b104', '68000000-0000-4000-8000-00000000b105', '68000000-0000-4000-8000-00000000b106', '68000000-0000-4000-8000-00000000b107', '68000000-0000-4000-8000-00000000b108', '68000000-0000-4000-8000-00000000b10a', '68000000-0000-4000-8000-00000000b10b', '68000000-0000-4000-8000-00000000b10c', '68000000-0000-4000-8000-00000000b10d', '68000000-0000-4000-8000-00000000b10e', '68000000-0000-4000-8000-00000000b10f', '68000000-0000-4000-8000-00000000b11f')
     and s.user_id is not null),
  0::bigint, 'STI-004: none of the refused rows was bound');
select is((select user_id from public.staff where id = '68000000-0000-4000-8000-00000000b109'), '68000000-0000-4000-8000-00000000a129'::uuid,
  'STI-004: the row that was already bound elsewhere kept its binding');
select results_eq($$select i.status::text, count(*) from public.staff_invites i
    where i.id in ('68000000-0000-4000-8000-00000000c104', '68000000-0000-4000-8000-00000000c105', '68000000-0000-4000-8000-00000000c106', '68000000-0000-4000-8000-00000000c107', '68000000-0000-4000-8000-00000000c108', '68000000-0000-4000-8000-00000000c10a', '68000000-0000-4000-8000-00000000c10b', '68000000-0000-4000-8000-00000000c10c', '68000000-0000-4000-8000-00000000c10d', '68000000-0000-4000-8000-00000000c10e', '68000000-0000-4000-8000-00000000c10f', '68000000-0000-4000-8000-00000000c11f')
    group by i.status order by i.status$$,
  $$values ('pending'::text, 10::bigint), ('revoked'::text, 1::bigint), ('superseded'::text, 1::bigint)$$,
  'STI-004: refusals changed no invite status');
select is((select count(*) from auth.sessions where user_id in ('68000000-0000-4000-8000-00000000a104', '68000000-0000-4000-8000-00000000a105', '68000000-0000-4000-8000-00000000a106', '68000000-0000-4000-8000-00000000a107', '68000000-0000-4000-8000-00000000a108', '68000000-0000-4000-8000-00000000a109', '68000000-0000-4000-8000-00000000a10a',
    '68000000-0000-4000-8000-00000000a10b', '68000000-0000-4000-8000-00000000a10c', '68000000-0000-4000-8000-00000000a10d', '68000000-0000-4000-8000-00000000a10e', '68000000-0000-4000-8000-00000000a10f', '68000000-0000-4000-8000-00000000a110', '68000000-0000-4000-8000-00000000a11f')),
  28::bigint, 'STI-004: refusals deleted no sessions');

-- 8.5 email_mismatch (the identity is verified, the address is not the one on the row).
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a111","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('11',32))$$,
  $$values ('email_mismatch'::text, null::text, null::text)$$,
  'STI-004: the Google identity email must match; an Auth account email that matches is not enough');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok(exists(select 1 from pg_locks l
    where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
      and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('identity-bind:' || '68000000-0000-4000-8000-00000000a111', 0)),
  'STI-004: a refusing redemption also takes the per-account advisory lock first');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11e","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1e',32))$$,
  $$values ('email_mismatch'::text, null::text, null::text)$$,
  'STI-004: the email check comes before the already-linked check');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a121","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('21',32))$$,
  $$values ('email_mismatch'::text, null::text, null::text)$$, 'STI-004: a blank address on the row never matches');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a122","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('22',32))$$,
  $$values ('email_mismatch'::text, null::text, null::text)$$, 'STI-004: a missing address on the row never matches');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a124","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('24',32))$$,
  $$values ('email_mismatch'::text, null::text, null::text)$$,
  'STI-004: the CURRENT address on the row is compared, so an address edited after issue invalidates the match');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log a
    where a.action = 'staff_invite.redeem_refused' and a.tenant_id = '68000000-0000-4000-8000-000000000001' and a.record_type = 'staff_invite'
      and a.after = '{"outcome":"email_mismatch"}'::jsonb
      and a.actor_user_id in ('68000000-0000-4000-8000-00000000a111', '68000000-0000-4000-8000-00000000a11e', '68000000-0000-4000-8000-00000000a121', '68000000-0000-4000-8000-00000000a122', '68000000-0000-4000-8000-00000000a124')),
  5::bigint, 'STI-010: each email mismatch was audited once with its outcome');
select is((select count(*) from public.staff where id in ('68000000-0000-4000-8000-00000000b111', '68000000-0000-4000-8000-00000000b11e', '68000000-0000-4000-8000-00000000b121', '68000000-0000-4000-8000-00000000b122', '68000000-0000-4000-8000-00000000b124') and user_id is not null),
  0::bigint, 'STI-004: no mismatching account was bound');
select is((select count(*) from auth.sessions where user_id in ('68000000-0000-4000-8000-00000000a111', '68000000-0000-4000-8000-00000000a11e', '68000000-0000-4000-8000-00000000a121', '68000000-0000-4000-8000-00000000a122', '68000000-0000-4000-8000-00000000a124')),
  10::bigint, 'STI-004: a mismatch deletes no sessions');

-- 8.6 identity_unverified (PROV-006a): confirmed email, Google identity, and no password
--     identity unless the account is operator provisioned.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a112","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('12',32))$$,
  $$values ('identity_unverified'::text, null::text, null::text)$$, 'STI-004: an account without a confirmed email is unverified');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a113","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('13',32))$$,
  $$values ('identity_unverified'::text, null::text, null::text)$$, 'STI-004: an account without a Google identity is unverified even if its email matches');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a114","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('14',32))$$,
  $$values ('identity_unverified'::text, null::text, null::text)$$, 'STI-004: a Google identity next to a password identity is unverified unless provisioned');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11d","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1d',32))$$,
  $$values ('identity_unverified'::text, null::text, null::text)$$, 'STI-004: the identity check comes before the email check');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log a
    where a.action = 'staff_invite.redeem_refused' and a.tenant_id = '68000000-0000-4000-8000-000000000001' and a.record_type = 'staff_invite'
      and a.after = '{"outcome":"identity_unverified"}'::jsonb
      and a.actor_user_id in ('68000000-0000-4000-8000-00000000a112', '68000000-0000-4000-8000-00000000a113', '68000000-0000-4000-8000-00000000a114', '68000000-0000-4000-8000-00000000a11d')),
  4::bigint, 'STI-010: each unverified refusal was audited once with its outcome');
select is((select count(*) from public.staff where id in ('68000000-0000-4000-8000-00000000b112', '68000000-0000-4000-8000-00000000b113', '68000000-0000-4000-8000-00000000b114', '68000000-0000-4000-8000-00000000b11d') and user_id is not null),
  0::bigint, 'STI-004: no unverified account was bound');

-- 8.7 account_already_linked (D1: one account, one identity in the whole system).
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a116","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('16',32))$$,
  $$values ('account_already_linked'::text, null::text, null::text)$$, 'STI-004: an account bound as a member of another gym cannot become staff');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a117","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('17',32))$$,
  $$values ('account_already_linked'::text, null::text, null::text)$$, 'STI-004: an account bound as staff of another gym cannot be linked again');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a118","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('18',32))$$,
  $$values ('account_already_linked'::text, null::text, null::text)$$, 'STI-004: a platform user cannot become gym staff');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a119","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('19',32))$$,
  $$values ('account_already_linked'::text, null::text, null::text)$$, 'STI-004: an account bound to another row of the same gym cannot be linked to a second row');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log a
    where a.action = 'staff_invite.redeem_refused' and a.tenant_id = '68000000-0000-4000-8000-000000000001' and a.record_type = 'staff_invite'
      and a.after = '{"outcome":"account_already_linked"}'::jsonb
      and a.actor_user_id in ('68000000-0000-4000-8000-00000000a116', '68000000-0000-4000-8000-00000000a117', '68000000-0000-4000-8000-00000000a118', '68000000-0000-4000-8000-00000000a119')),
  4::bigint, 'STI-010: each already-linked refusal was audited once with its outcome');
select results_eq($$select (select user_id from public.members where id = '68000000-0000-4000-8000-000000000322'), (select user_id from public.staff where id = '68000000-0000-4000-8000-000000000270'),
        (select user_id from public.staff where id = '68000000-0000-4000-8000-000000000271'), (select count(*) from public.platform_users where user_id = '68000000-0000-4000-8000-00000000a118')$$,
  $$values ('68000000-0000-4000-8000-00000000a116'::uuid, '68000000-0000-4000-8000-00000000a117'::uuid, '68000000-0000-4000-8000-00000000a119'::uuid, 1::bigint)$$,
  'STI-004: the existing bindings of the refused accounts are untouched');
select is((select count(*) from public.staff where id in ('68000000-0000-4000-8000-00000000b116', '68000000-0000-4000-8000-00000000b117', '68000000-0000-4000-8000-00000000b118', '68000000-0000-4000-8000-00000000b119') and user_id is not null),
  0::bigint, 'STI-004: no target row was bound by a D1 refusal');

-- 8.8 The shared throttle: ten refused redemptions in 15 minutes, counted over BOTH
--     member_invite.redeem_refused and staff_invite.redeem_refused, per Auth user.
--     Case 26 holds 5 member-family and 4 staff-family refusals from five minutes ago.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11a","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('ee', 32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$,
  'STI-004: nine refusals across both families still allow the next attempt, which refuses an unknown token');
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1a',32))$$,
  $$values ('rate_limited'::text, null::text, null::text)$$,
  'STI-004: with ten refusals across both families a perfectly valid token is answered rate_limited');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select count(*), count(*) filter (where action = 'staff_invite.redeem_refused'),
        count(*) filter (where action = 'member_invite.redeem_refused'), count(*) filter (where tenant_id is null)
     from public.audit_log where actor_user_id = '68000000-0000-4000-8000-00000000a11a'$$,
  $$values (10::bigint, 5::bigint, 5::bigint, 10::bigint)$$,
  'STI-004: the unknown-token refusal wrote one staff-family row without a tenant and rate_limited wrote nothing');
select results_eq($$select a.tenant_id, a.record_type, a.after from public.audit_log a
    where a.actor_user_id = '68000000-0000-4000-8000-00000000a11a' and a.occurred_at > now() - interval '1 minute'$$,
  $$values (null::uuid, 'staff_invite'::text, '{"outcome":"invite_unavailable"}'::jsonb)$$,
  'STI-010: a refusal for an unresolvable token is audited without a tenant');
select results_eq($$select i.status::text, s.user_id is null from public.staff_invites i join public.staff s on s.id = i.staff_id where i.id = '68000000-0000-4000-8000-00000000c11a'$$,
  $$values ('pending'::text, true)$$, 'STI-004: the throttled valid invite was neither redeemed nor consumed');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a11c","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('1c',32))$$,
  $$values ('rate_limited'::text, null::text, null::text)$$,
  'STI-004: ten refusals inside the window are enough, and the throttle runs before the token is looked at');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log where actor_user_id = '68000000-0000-4000-8000-00000000a11c'), 10::bigint,
  'STI-004: rate_limited writes nothing');
select results_eq($$select i.status::text, s.user_id is null from public.staff_invites i join public.staff s on s.id = i.staff_id where i.id = '68000000-0000-4000-8000-00000000c11c'$$,
  $$values ('pending'::text, true)$$, 'STI-004: the throttled valid invite for case 28 is untouched');
select ok(exists(select 1 from pg_locks l
    where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
      and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('identity-bind:' || '68000000-0000-4000-8000-00000000a11c', 0)),
  'STI-004: the advisory lock is taken before the throttle is evaluated');

-- 8.9 An impersonating session can never redeem, even with an otherwise valid invite.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a120","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","impersonation_session_id":"68000000-0000-4000-8000-000000000f02"}',true);
set local role authenticated;
select throws_ok($$select * from public.redeem_staff_invite(repeat('20',32))$$, '42501', null,
  'STI-004: a session carrying an impersonation claim is refused with 42501');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select i.status::text, s.user_id is null from public.staff_invites i join public.staff s on s.id = i.staff_id where i.id = '68000000-0000-4000-8000-00000000c120'$$,
  $$values ('pending'::text, true)$$, 'STI-004: the impersonation refusal left the invite pending and the row unbound');
select is((select count(*) from public.audit_log where actor_user_id = '68000000-0000-4000-8000-00000000a120'), 0::bigint,
  'STI-004: the impersonation refusal wrote no audit row');

-- 8.10 The anon role cannot redeem; the throttle evidence cannot be forged by a plain caller
--      because the audit table is not writable.
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$select * from public.redeem_staff_invite(repeat('20',32))$$, '42501', null,
  'STI-004/011: anon cannot execute redeem_staff_invite');


-- ===========================================================================
-- 9. UNLINK (STI-008) and RELINK
--    Targets: tU1 manager (pending invite on the side), tU2 front desk, tU3 trainer (reason
--    validation, then unlink, then a new invite), tU4 never linked, tU5 a linked OWNER, tU9
--    a control row in the same gym that must not be touched.
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', null)$$, '22023', null, 'STI-008: a missing reason is malformed input');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', '')$$, '22023', null, 'STI-008: an empty reason is malformed input');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', '    ')$$, '22023', null, 'STI-008: a blank reason is malformed input');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', 'ab')$$, '22023', null, 'STI-008: a two-character reason is too short');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', '  ab  ')$$, '22023', null, 'STI-008: the reason length is measured after trimming');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', repeat('x', 201))$$, '22023', null, 'STI-008: a 201-character reason is too long');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select user_id, (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-000000000113') from public.staff where id = '68000000-0000-4000-8000-000000000243'$$,
  $$values ('68000000-0000-4000-8000-000000000113'::uuid, 2::bigint)$$, 'STI-008: every invalid reason left the row linked and the sessions alive');

select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000241', repeat('r', 200))$$,
  'STI-008: an owner unlinks a linked manager with a reason of exactly 200 characters');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select s.user_id is null, (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-000000000111'),
        (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-000000000119'), (select x.user_id from public.staff x where x.id = '68000000-0000-4000-8000-000000000249'),
        s.role::text, s.is_active, s.email
     from public.staff s where s.id = '68000000-0000-4000-8000-000000000241'$$,
  $$values (true, 0::bigint, 2::bigint, '68000000-0000-4000-8000-000000000119'::uuid, 'gym_manager'::text, true, 'unlink1.sti@example.com'::text)$$,
  'STI-008: user_id is cleared, only the former user sessions are deleted, other staff of the gym are untouched, role and email stay');
select results_eq($$select a.actor_user_id, a.actor_role::text, a.tenant_id, a.record_type, a.before, a.after, a.reason = repeat('r', 200)
     from public.audit_log a where a.action = 'staff.unlinked' and a.record_id = '68000000-0000-4000-8000-000000000241'$$,
  $$values ('68000000-0000-4000-8000-000000000101'::uuid, 'gym_owner'::text, '68000000-0000-4000-8000-000000000001'::uuid, 'staff'::text, '{"user_linked":true}'::jsonb, '{"user_linked":false}'::jsonb, true)$$,
  'STI-010: staff.unlinked is audited with before {user_linked:true}, after {user_linked:false} and the reason');
select results_eq($$select status::text, token_hash = repeat('b5', 32) from public.staff_invites where id = '68000000-0000-4000-8000-000000000541'$$,
  $$values ('pending'::text, true)$$, 'STI-008: a pending invite is left untouched by an unlink');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-000000000111',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-000000000111', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  '{}'::jsonb, 'STI-008: the former user no longer receives staff claims');
select is(current_setting('app.staff_binding_command', true), '',
  'STI-006: the unlink command also resets the transaction-local setting');

select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000242', '  abc  ')$$,
  'STI-008: a reason of three characters after trimming is accepted');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000242', 'second attempt')$$, 'GL080', null,
  'STI-008: unlinking a row that is no longer linked fails GL080');
select throws_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000244', 'never linked row')$$, 'GL080', null,
  'STI-008: unlinking a row that was never linked fails GL080');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select count(*) = 1 and bool_and(btrim(a.reason) = 'abc') from public.audit_log a where a.action = 'staff.unlinked' and a.record_id = '68000000-0000-4000-8000-000000000242'),
  'STI-008: the reason is recorded');
select is((select count(*) from public.audit_log where action = 'staff.unlinked' and record_id in ('68000000-0000-4000-8000-000000000242', '68000000-0000-4000-8000-000000000244')),
  1::bigint, 'STI-010: the GL080 refusals were not audited as unlinks');

-- The owner row can never be unlinked through this command. The contract names no SQLSTATE, so
-- the probe demands only that the statement fails and that nothing changes.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($q$do $t$ begin begin perform public.unlink_staff_identity('68000000-0000-4000-8000-000000000245', 'owner row probe'); exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: a linked owner row cannot be unlinked through the staff command');
select lives_ok($q$do $t$ begin begin perform public.unlink_staff_identity('68000000-0000-4000-8000-000000000201', 'self unlink probe'); exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: an owner cannot unlink their own owner row');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select (select x.user_id from public.staff x where x.id = '68000000-0000-4000-8000-000000000245'), (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-000000000115'),
        (select x.user_id from public.staff x where x.id = '68000000-0000-4000-8000-000000000201')$$,
  $$values ('68000000-0000-4000-8000-000000000115'::uuid, 2::bigint, '68000000-0000-4000-8000-000000000101'::uuid)$$,
  'STI-006: the owner bindings and sessions are intact after the refused unlinks');

-- Relink: tU3 is unlinked with a normal reason and then re-invited; the same Google account
-- links again, which proves that an unlink frees the account for the D1 count.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-000000000243', 'Left the gym')$$, 'STI-008: the trainer row is unlinked');
select results_eq($$select superseded_invite_id is null from public.issue_staff_invite('68000000-0000-4000-8000-000000000243', repeat('f7', 32))$$,
  $$values (true)$$, 'STI-008: a new invite can be issued for an unlinked row');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000113","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('f7', 32))$$,
  $$values ('linked'::text, 'Sti Gym A'::text, 'trainer'::text)$$,
  'STI-008: the former user can be linked again through a new invite');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select user_id, role::text from public.staff where id = '68000000-0000-4000-8000-000000000243'$$,
  $$values ('68000000-0000-4000-8000-000000000113'::uuid, 'trainer'::text)$$, 'STI-008: the row is bound again to the same account');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-000000000113',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-000000000113', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'trainer', 'tenant_id', '68000000-0000-4000-8000-000000000001', 'staff_id', '68000000-0000-4000-8000-000000000243'),
  'STI-008: after the relink the hook mints the trainer claims again');
select is((select count(*) from public.audit_log where record_id = '68000000-0000-4000-8000-000000000243' and action in ('staff.unlinked', 'staff.linked')),
  2::bigint, 'STI-010: the unlink and the relink were each audited once');

-- ===========================================================================
-- 10. READ MODEL (STI-009): five states, fixed precedence, owner-only.
--     linked (non-null user_id) > unavailable (inactive or gym_owner role) > newest invite
--     (invite_pending if it expires in the future, invite_expired if not; a closed newest
--     invite counts as none) > not_invited.
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select results_eq($$select state, linked_at from public.read_staff_app_access('68000000-0000-4000-8000-000000000251')$$,
  $$values ('linked'::text, null::timestamptz)$$, 'STI-009: an operator-bound row is linked and has no linked_at');
select results_eq($$select state, linked_at from public.read_staff_app_access('68000000-0000-4000-8000-000000000252')$$,
  $$values ('linked'::text, timestamptz '2026-09-20 10:00:00+00')$$,
  'STI-009: linked_at is the latest staff.linked audit time of THIS row (not an earlier link, an unlink, or another row)');
select results_eq($$select state, linked_at is null from public.read_staff_app_access('68000000-0000-4000-8000-000000000201')$$,
  $$values ('linked'::text, true)$$, 'STI-009: a platform-linked owner row is reported as linked');
select results_eq($$select state from public.read_staff_app_access('68000000-0000-4000-8000-00000000025b')$$,
  $$values ('linked'::text)$$, 'STI-009: linked outranks unavailable (a linked but inactive row is linked)');
select results_eq($$select state, invite_id from public.read_staff_app_access('68000000-0000-4000-8000-000000000253')$$,
  $$values ('unavailable'::text, null::uuid)$$, 'STI-009: an inactive unlinked row is unavailable even with a pending invite');
select results_eq($$select state, invite_id from public.read_staff_app_access('68000000-0000-4000-8000-000000000211')$$,
  $$values ('unavailable'::text, null::uuid)$$, 'STI-009: an unlinked owner row is unavailable');
select results_eq($$select r.state, r.invite_id, r.issued_at = i.issued_at, r.expires_at = i.expires_at, r.linked_at is null
     from public.read_staff_app_access('68000000-0000-4000-8000-000000000255') r, public.staff_invites i where i.id = '68000000-0000-4000-8000-000000000555'$$,
  $$values ('invite_pending'::text, '68000000-0000-4000-8000-000000000555'::uuid, true, true, true)$$, 'STI-009: a pending unexpired invite is invite_pending and names itself');
select results_eq($$select r.state, r.invite_id, r.expires_at = i.expires_at
     from public.read_staff_app_access('68000000-0000-4000-8000-000000000256') r, public.staff_invites i where i.id = '68000000-0000-4000-8000-000000000556'$$,
  $$values ('invite_expired'::text, '68000000-0000-4000-8000-000000000556'::uuid, true)$$, 'STI-009: a pending invite past its expiry is invite_expired');
select results_eq($$select state, invite_id from public.read_staff_app_access('68000000-0000-4000-8000-000000000257')$$,
  $$values ('not_invited'::text, null::uuid)$$, 'STI-009: a row without invites and without an email is not_invited');
select results_eq($$select state, invite_id from public.read_staff_app_access('68000000-0000-4000-8000-000000000258')$$,
  $$values ('not_invited'::text, null::uuid)$$, 'STI-009: a revoked newest invite counts as none');
select results_eq($$select state from public.read_staff_app_access('68000000-0000-4000-8000-000000000259')$$,
  $$values ('not_invited'::text)$$, 'STI-009: a redeemed newest invite on an unlinked row counts as none');
select results_eq($$select state from public.read_staff_app_access('68000000-0000-4000-8000-000000000234')$$,
  $$values ('not_invited'::text)$$, 'STI-009: a superseded newest invite counts as none');
select results_eq($$select state, invite_id from public.read_staff_app_access('68000000-0000-4000-8000-00000000025a')$$,
  $$values ('invite_pending'::text, '68000000-0000-4000-8000-00000000055b'::uuid)$$, 'STI-009: the newest invite decides (the resent one, not the superseded one)');
select results_eq($$select r.state, r.linked_at = (select max(a.occurred_at) from public.audit_log a where a.action = 'staff.linked' and a.record_id = '68000000-0000-4000-8000-00000000b101')
     from public.read_staff_app_access('68000000-0000-4000-8000-00000000b101') r$$,
  $$values ('linked'::text, true)$$, 'STI-009: a row linked by redemption reports the time of its staff.linked audit row');
select results_eq($$select state, invite_id is not null from public.read_staff_app_access('68000000-0000-4000-8000-000000000222')$$,
  $$values ('invite_pending'::text, true)$$, 'STI-009: a freshly resent invite reads as invite_pending');

-- A redeemed token must not keep claiming a link that no longer exists: after the owner unlinks
-- the row, the account that once redeemed it gets the generic refusal, not already_linked_here.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select lives_ok($$select public.unlink_staff_identity('68000000-0000-4000-8000-00000000b101', 'Replay after unlink probe')$$,
  'STI-008: the redeemed row is unlinked by its owner');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-00000000a101","role":"authenticated"}',true);
set local role authenticated;
select results_eq($$select outcome, gym_name, staff_role::text from public.redeem_staff_invite(repeat('01',32))$$,
  $$values ('invite_unavailable'::text, null::text, null::text)$$,
  'STI-004: replaying a redeemed token after the row was unlinked is the generic refusal, never already_linked_here');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select s.user_id is null, (select count(*) from public.audit_log a where a.record_id = '68000000-0000-4000-8000-00000000b101' and a.action = 'staff.linked')
     from public.staff s where s.id = '68000000-0000-4000-8000-00000000b101'$$,
  $$values (true, 1::bigint)$$, 'STI-004: the refused replay did not rebind the row or write a second link row');


-- ===========================================================================
-- 11. TENANCY AND PRIVILEGES AT THE ROW LEVEL (STI-011, STI-017)
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select ok((select count(*) > 0 from public.staff_invites where tenant_id = '68000000-0000-4000-8000-000000000001'),
  'STI-011: a gym owner reads the invites of their own gym');
select is((select count(*) from public.staff_invites where tenant_id <> '68000000-0000-4000-8000-000000000001'), 0::bigint,
  'STI-011: a gym owner sees no invite of any other gym');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000107","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000002","staff_id":"68000000-0000-4000-8000-000000000207"}',true);
set local role authenticated;
select ok((select count(*) > 0 from public.staff_invites where tenant_id = '68000000-0000-4000-8000-000000000002'),
  'STI-011: the owner of the other gym reads that gym invites');
select is((select count(*) from public.staff_invites where tenant_id = '68000000-0000-4000-8000-000000000001'), 0::bigint,
  'STI-011: and none of gym A');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000102","role":"authenticated","app_role":"gym_manager","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000202"}',true);
set local role authenticated;
select is((select count(*) from public.staff_invites where tenant_id in ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002')), 0::bigint,
  'STI-011: a gym manager of the same gym reads no staff invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000103","role":"authenticated","app_role":"front_desk","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000203"}',true);
set local role authenticated;
select is((select count(*) from public.staff_invites where tenant_id in ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002')), 0::bigint,
  'STI-011: front desk reads no staff invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000104","role":"authenticated","app_role":"trainer","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000204"}',true);
set local role authenticated;
select is((select count(*) from public.staff_invites where tenant_id in ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002')), 0::bigint,
  'STI-011: a trainer reads no staff invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000105","role":"authenticated","app_role":"member","tenant_id":"68000000-0000-4000-8000-000000000001","member_id":"68000000-0000-4000-8000-000000000301"}',true);
set local role authenticated;
select is((select count(*) from public.staff_invites where tenant_id in ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002')), 0::bigint,
  'STI-011: a member reads no staff invite');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000106","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select is((select count(*) from public.staff_invites where tenant_id in ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002')), 0::bigint,
  'STI-011: a super admin reads no staff invite through the table');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$insert into public.staff_invites(tenant_id, staff_id, token_hash, issued_by_staff_id, expires_at)
    values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000222', repeat('e9', 32), '68000000-0000-4000-8000-000000000201', now() + interval '48 hours')$$,
  '42501', null, 'STI-011: even an owner cannot insert an invite directly');
select throws_ok($$update public.staff_invites set status = 'revoked', closed_at = now() where id = '68000000-0000-4000-8000-000000000535'$$,
  '42501', null, 'STI-011: even an owner cannot update an invite directly');
select throws_ok($$delete from public.staff_invites where id = '68000000-0000-4000-8000-000000000535'$$,
  '42501', null, 'STI-011: even an owner cannot delete an invite directly');
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select status::text from public.staff_invites where id = '68000000-0000-4000-8000-000000000535'), 'pending',
  'STI-011: the direct write attempts changed nothing');

-- ===========================================================================
-- 12. THE BINDING GUARD (STI-006): app.enforce_staff_auth_binding / GL049
--
--    Only two shapes are admitted, and only for a caller whose current_user is postgres (a
--    definer command): LINK = old.user_id null to new.user_id = the uid named by the setting
--    'link:<uid>', staff row active, role one of manager / front_desk / trainer; UNLINK =
--    user_id cleared with the setting 'unlink:<old uid>', role unchanged, active unchanged.
--    Everything else behaves exactly as before: GL049 for sessions, a platform admin for a
--    definer, trust for a caller without a JWT subject.
-- ===========================================================================

-- 12.1 Sessions: an owner is the only role the staff policy lets reach the trigger by UPDATE,
--      and a session that sets the command setting for itself gets nothing from it.
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
set local role authenticated;
select throws_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'$$, 'GL049', null,
  'STI-006: a gym owner session cannot write staff.user_id directly');
select throws_ok($$update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000249'$$, 'GL049', null,
  'STI-006: a gym owner session cannot clear staff.user_id directly');
select set_config('app.staff_binding_command', 'link:68000000-0000-4000-8000-000000000133', true);
select throws_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'$$, 'GL049', null,
  'STI-006: a session that sets the link command setting itself is still refused (the caller must be the definer)');
select set_config('app.staff_binding_command', 'unlink:68000000-0000-4000-8000-000000000119', true);
select throws_ok($$update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000249'$$, 'GL049', null,
  'STI-006: a session that sets the unlink command setting itself is still refused');
select set_config('app.staff_binding_command', '', true);
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  'GL049', null, 'STI-006: an owner cannot insert a staff row that is already bound');
select throws_ok($$update public.staff set role = 'gym_owner' where id = '68000000-0000-4000-8000-000000000202'$$, 'GL049', null,
  'STI-006: promoting a linked staff row to owner stays a platform-only change');

-- 12.2 Every other role: an insert that carries a user_id reaches the trigger before the policy
--      check and is refused; an update is filtered out by the owner-only write policy and so
--      changes nothing (checked once, below).
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000102","role":"authenticated","app_role":"gym_manager","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000202"}',true);
set local role authenticated;
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  'GL049', null, 'STI-006: a gym manager cannot create a bound staff row');
do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'; exception when others then null; end; end $t$;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000103","role":"authenticated","app_role":"front_desk","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000203"}',true);
set local role authenticated;
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  'GL049', null, 'STI-006: front desk cannot create a bound staff row');
do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'; exception when others then null; end; end $t$;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000104","role":"authenticated","app_role":"trainer","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000204"}',true);
set local role authenticated;
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  'GL049', null, 'STI-006: a trainer cannot create a bound staff row');
do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'; exception when others then null; end; end $t$;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000105","role":"authenticated","app_role":"member","tenant_id":"68000000-0000-4000-8000-000000000001","member_id":"68000000-0000-4000-8000-000000000301"}',true);
set local role authenticated;
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  'GL049', null, 'STI-006: a member cannot create a bound staff row');
do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'; exception when others then null; end; end $t$;
select set_config('request.jwt.claims','',true);
set local role anon;
select throws_ok($$insert into public.staff(tenant_id, user_id, role, full_name) values ('68000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000133', 'front_desk', 'Direct Insert Probe')$$,
  '42501', null, 'STI-006: anon holds no insert privilege on staff at all');
select throws_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'$$,
  '42501', null, 'STI-006: anon holds no update privilege on staff at all');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select count(*) = 0 from public.staff where id = '68000000-0000-4000-8000-000000000265' and user_id is not null),
  'STI-006: no direct write by manager, front desk, trainer or member bound the row');
select is_empty($$select 1 from public.staff where full_name = 'Direct Insert Probe'$$,
  'STI-006: no refused insert left a staff row behind');

-- 12.3 A definer-style caller (current_user is postgres) with a JWT subject that is NOT a
--      platform admin. This is exactly the context in which redeem and unlink write. The
--      contract names no SQLSTATE for the refusals (the unchanged old path would ask for a
--      platform admin), so each probe demands failure and the state is checked afterwards.
set local role postgres;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000131","role":"authenticated"}',true);
select set_config('app.staff_binding_command', '', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000265'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: without the command setting a definer-style caller cannot bind a row');
select set_config('app.staff_binding_command', 'link:68000000-0000-4000-8000-000000000132', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000265'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: a link setting that names a different user admits nothing');
select set_config('app.staff_binding_command', 'unlink:68000000-0000-4000-8000-000000000131', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000265'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the unlink verb does not admit a link');
select set_config('app.staff_binding_command', 'link:68000000-0000-4000-8000-000000000131', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000262'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the link shape never admits a gym_owner row');
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000263'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the link shape never admits an inactive row');
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131', is_active = false where id = '68000000-0000-4000-8000-000000000265'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the link shape cannot also deactivate the row');
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000131', role = 'gym_owner' where id = '68000000-0000-4000-8000-000000000265'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the link shape cannot also promote the row to owner');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
select set_config('app.staff_binding_command', 'unlink:68000000-0000-4000-8000-000000000115', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000245'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the unlink shape never admits a linked gym_owner row');
select set_config('app.staff_binding_command', '', true);
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select count(*) = 0 from public.staff where id in ('68000000-0000-4000-8000-000000000262', '68000000-0000-4000-8000-000000000263', '68000000-0000-4000-8000-000000000265') and user_id is not null)
      and (select user_id = '68000000-0000-4000-8000-000000000115' from public.staff where id = '68000000-0000-4000-8000-000000000245'),
  'STI-006: none of the refused definer-style writes changed any row');

-- 12.4 The admitted shapes themselves.
set local role postgres;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000131","role":"authenticated"}',true);
select set_config('app.staff_binding_command', 'link:68000000-0000-4000-8000-000000000131', true);
select lives_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000131' where id = '68000000-0000-4000-8000-000000000261'$$,
  'STI-006: the link shape (setting names the new user, row active, manager role) is admitted for a definer-style caller');
select set_config('app.staff_binding_command', '', true);
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select user_id, (select count(*) from auth.sessions where user_id = '68000000-0000-4000-8000-000000000131') from public.staff where id = '68000000-0000-4000-8000-000000000261'$$,
  $$values ('68000000-0000-4000-8000-000000000131'::uuid, 0::bigint)$$, 'STI-006: the row is bound and the existing trigger deleted the new user sessions');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000131","role":"authenticated"}',true);
select set_config('app.staff_binding_command', 'link:68000000-0000-4000-8000-000000000132', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = '68000000-0000-4000-8000-000000000132' where id = '68000000-0000-4000-8000-000000000261'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the link shape needs the old user_id to be null, so a bound row cannot be repointed');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000101","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000001","staff_id":"68000000-0000-4000-8000-000000000201"}',true);
select set_config('app.staff_binding_command', 'unlink:68000000-0000-4000-8000-000000000132', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000261'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the unlink setting must name the user being unlinked');
select set_config('app.staff_binding_command', 'unlink:68000000-0000-4000-8000-000000000131', true);
select lives_ok($q$do $t$ begin begin update public.staff set user_id = null, role = 'trainer' where id = '68000000-0000-4000-8000-000000000261'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the unlink shape cannot also change the role');
select lives_ok($q$do $t$ begin begin update public.staff set user_id = null, is_active = false where id = '68000000-0000-4000-8000-000000000261'; exception when others then return; end; raise exception 'statement unexpectedly succeeded'; end $t$$q$, 'STI-006: the unlink shape cannot also deactivate the row');
select lives_ok($$update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000261'$$,
  'STI-006: the unlink shape (setting names the old user, role and status unchanged) is admitted');
select set_config('app.staff_binding_command', '', true);
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select user_id is null and role = 'gym_manager' and is_active from public.staff where id = '68000000-0000-4000-8000-000000000261'),
  'STI-006: the row is unbound again with role and status intact');

-- 12.5 Callers without a JWT subject keep their trust: migrations, seeds and the operator
--      provisioning tool (postgres or service_role, no subject).
set local role postgres;
select set_config('request.jwt.claims','',true);
select lives_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'$$,
  'STI-018: a postgres caller without a JWT subject can still bind a staff row');
select lives_ok($$update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000265'$$,
  'STI-018: and unbind it');
select set_config('request.jwt.claims', '', true);
set local role service_role;
select lives_ok($$update public.staff set user_id = '68000000-0000-4000-8000-000000000133' where id = '68000000-0000-4000-8000-000000000265'$$,
  'STI-018: the service role without a JWT subject (the operator provisioning tool) can still bind a staff row');
select lives_ok($$update public.staff set user_id = null where id = '68000000-0000-4000-8000-000000000265'$$,
  'STI-018: and unbind it');
set local role postgres;
select set_config('request.jwt.claims','',true);

-- ===========================================================================
-- 13. NOTHING ELSE MOVED (STI-018): the platform owner-link and owner-retirement commands,
--     and the hook, behave as before the guard was amended.
-- ===========================================================================
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000106","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select is((select public.link_gym_owner('68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-000000000212', null, ' Owner.Link.Sti@Example.com ', '68000000-0000-4000-8000-000000000f11') ->> 'ownerAccessPending'),
  'false', 'STI-018: the platform command still links a gym owner row by its exact Auth email');
set local role postgres;
select set_config('request.jwt.claims','',true);
select results_eq($$select user_id, role::text, email from public.staff where id = '68000000-0000-4000-8000-000000000212'$$,
  $$values ('68000000-0000-4000-8000-00000000010f'::uuid, 'gym_owner'::text, 'owner.link.sti@example.com'::text)$$,
  'STI-018: the owner row is bound to the Auth user with that email');
select is((app.custom_access_token_hook(jsonb_build_object('user_id', '68000000-0000-4000-8000-00000000010f',
        'claims', jsonb_build_object('sub', '68000000-0000-4000-8000-00000000010f', 'aud', 'authenticated', 'role', 'authenticated', 'session_id', '68000000-0000-4000-8000-000000000f01'))) -> 'claims')
        - array['sub', 'aud', 'role', 'session_id'],
  jsonb_build_object('app_role', 'gym_owner', 'tenant_id', '68000000-0000-4000-8000-000000000002', 'staff_id', '68000000-0000-4000-8000-000000000212'),
  'STI-018: the hook mints owner claims for a platform-linked owner');
select is((select count(*) from public.audit_log where action = 'staff.owner_linked' and record_id = '68000000-0000-4000-8000-000000000212'),
  1::bigint, 'STI-018: the owner link keeps its own audit action');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000106","role":"authenticated","app_role":"super_admin"}',true);
set local role authenticated;
select is((select public.deactivate_gym_owner('68000000-0000-4000-8000-000000000002', '68000000-0000-4000-8000-000000000212', '68000000-0000-4000-8000-00000000010f', '68000000-0000-4000-8000-000000000f12') ->> 'isActive'),
  'false', 'STI-018: the platform command still retires a linked owner');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok((select not is_active and user_id = '68000000-0000-4000-8000-00000000010f' from public.staff where id = '68000000-0000-4000-8000-000000000212'),
  'STI-018: the retired owner keeps its binding and is inactive');
select set_config('request.jwt.claims','{"sub":"68000000-0000-4000-8000-000000000107","role":"authenticated","app_role":"gym_owner","tenant_id":"68000000-0000-4000-8000-000000000002","staff_id":"68000000-0000-4000-8000-000000000207"}',true);
set local role authenticated;
select throws_ok($$update public.staff set is_active = true where id = '68000000-0000-4000-8000-000000000212'$$, 'GL049', null,
  'STI-018: a gym owner session still cannot touch a linked owner row');

-- ===========================================================================
-- 14. HYGIENE (STI-010): no token and no token hash anywhere in the audit trail of the
--     fixture gyms or fixture actors.
-- ===========================================================================
set local role postgres;
select set_config('request.jwt.claims','',true);
select is_empty($$select a.id from public.audit_log a
   where (a.tenant_id::text like '68000000-%' or a.actor_user_id::text like '68000000-%')
     and (coalesce(a.before::text, '') ~ '[0-9a-f]{64}' or coalesce(a.after::text, '') ~ '[0-9a-f]{64}'
          or coalesce(a.reason, '') ~ '[0-9a-f]{64}' or coalesce(a.request_facts::text, '') ~ '[0-9a-f]{64}')$$,
  'STI-010: no audit row of the suite carries a 64-character hex string, so no token hash was audited');
select is_empty($$select a.id from public.audit_log a
   where (a.tenant_id::text like '68000000-%' or a.actor_user_id::text like '68000000-%')
     and a.action like 'staff%' and a.action not in ('staff.invited', 'staff_invite.issued', 'staff_invite.superseded', 'staff_invite.revoked',
         'staff_invite.redeemed', 'staff_invite.redeem_refused', 'staff.linked', 'staff.unlinked', 'staff.owner_linked', 'staff.owner_deactivated',
         'staff.role_changed', 'staff.deactivated')$$,
  'STI-010: the suite produced no audit action outside the contract allowlist and the pre-existing identity actions');


set local role postgres;
select set_config('request.jwt.claims','',true);
select * from finish();
rollback;
