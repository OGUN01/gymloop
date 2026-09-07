-- 09_comms_rls.sql — visible pgTAP suite, cluster: comms (cross-tenant leak matrix).
--
-- Gate 7: a leak matrix per table. All six comms tables, four caller shapes:
-- a gym_owner of gym A, a super_admin, a caller with no JWT claims at all, and a
-- caller whose tenant_id claim is the empty string.
--
-- The asymmetry the contract calls out is what this file is shaped around: an RLS
-- policy does NOT raise on select/update/delete, it filters — so those assert zero
-- rows or an unchanged row. A failing `with check` on insert DOES raise 42501, and
-- so does a missing privilege.
--
-- Written from openspec/changes/0001-data-model/specs/comms/spec.md and
-- docs/data-model.md before any migration existed.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(60);

-- ---------------------------------------------------------------------------
-- Fixtures for two gyms, inserted as the owner: the contract forbids `force row
-- level security`, so RLS does not apply to postgres here.
-- Chain: organizations -> branches -> staff/members -> this cluster's tables.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'Comms RLS Gym A', 'CMRLSA'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'Comms RLS Gym B', 'CMRLSB');

insert into public.branches (id, tenant_id, name, is_default) values
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'Main A', true),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 'Main B', true);

insert into public.staff (id, tenant_id, branch_id, role, full_name) values
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000002'::uuid, 'gym_owner', 'Owner A'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000002'::uuid, 'gym_owner', 'Owner B');

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000002'::uuid, 'Member A', '+919000000101'),
  ('b0000000-0000-4000-8000-000000000004'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000002'::uuid, 'Member B', '+919000000102');

insert into public.message_templates (id, tenant_id, key, channel, locale, body) values
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'renewal_reminder', 'push', 'en', 'Gym A copy'),
  ('b0000000-0000-4000-8000-000000000005'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'renewal_reminder', 'push', 'en', 'Gym B copy');

insert into public.notifications (id, tenant_id, member_id, channel, template_key, dedupe_key) values
  ('a0000000-0000-4000-8000-000000000006'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000004'::uuid, 'push', 'renewal_reminder', 'renewal:a:expiry_minus_7'),
  ('b0000000-0000-4000-8000-000000000006'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000004'::uuid, 'push', 'renewal_reminder', 'renewal:b:expiry_minus_7');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000004'::uuid, 'android', 'tok-comms-rls-a1'),
  ('b0000000-0000-4000-8000-000000000007'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000004'::uuid, 'ios', 'tok-comms-rls-b1');

insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source, recorded_by_staff_id) values
  ('a0000000-0000-4000-8000-000000000008'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000004'::uuid, 'marketing', true, 'v1', 'signup_form',
   'a0000000-0000-4000-8000-000000000003'::uuid),
  ('b0000000-0000-4000-8000-000000000008'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000004'::uuid, 'marketing', true, 'v1', 'signup_form',
   'b0000000-0000-4000-8000-000000000003'::uuid);

insert into public.messaging_wallets (tenant_id, balance_credits) values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 100),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 250);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('a0000000-0000-4000-8000-000000000009'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 100, 'topup'),
  ('b0000000-0000-4000-8000-000000000009'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid, 250, 'topup');

-- ---------------------------------------------------------------------------
-- 1-22. As a signed-in gym_owner of Gym A.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- 1-6. select returns only Gym A's rows.

select results_eq(
  $q$ select tenant_id from public.message_templates $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own message_templates'
);
select results_eq(
  $q$ select tenant_id from public.notifications $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own notifications'
);
select results_eq(
  $q$ select tenant_id from public.member_devices $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own member_devices — a push token is member personal data (DPD-001)'
);
select results_eq(
  $q$ select tenant_id from public.consents $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own consents (DPD-001 — the gym is the Data Fiduciary for its own members only)'
);
select results_eq(
  $q$ select tenant_id from public.messaging_wallets $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own messaging_wallets row'
);
select results_eq(
  $q$ select tenant_id from public.messaging_wallet_ledger $q$,
  $w$ values ('a0000000-0000-4000-8000-000000000001'::uuid) $w$,
  'gate 7: gym A sees only its own messaging_wallet_ledger rows'
);

-- 7-10. update of Gym B's row by primary key affects zero rows — the policy
-- filters, it does not raise. consents and messaging_wallet_ledger are omitted
-- here on purpose: they are append-only, `authenticated` holds no UPDATE on them
-- at all, so the refusal is a privilege error (42501) rather than a filtered
-- update, and 09_comms_structure.sql asserts it in that form. messaging_wallets
-- is in the same position since ADR-047 made it read-only, so its assertion
-- below is the privilege error, not a filtered update.

with u as (
  update public.message_templates set body = 'cross-tenant write'
   where id = 'b0000000-0000-4000-8000-000000000005'::uuid
  returning 1
)
select is(count(*), 0::bigint, 'gate 7: gym A updating gym B message_templates by pk affects zero rows') from u;

with u as (
  update public.notifications set template_key = 'cross-tenant write'
   where id = 'b0000000-0000-4000-8000-000000000006'::uuid
  returning 1
)
select is(count(*), 0::bigint, 'gate 7: gym A updating gym B notifications by pk affects zero rows') from u;

with u as (
  update public.member_devices set is_active = false
   where id = 'b0000000-0000-4000-8000-000000000007'::uuid
  returning 1
)
select is(count(*), 0::bigint, 'gate 7: gym A updating gym B member_devices by pk affects zero rows') from u;

select throws_ok(
  $q$ update public.messaging_wallets set balance_credits = 999
       where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid $q$,
  '42501'::text, null::text,
  'gate 7 (ADR-047): gym A updating gym B messaging_wallets is refused for want of privilege — the wallet is read-only to authenticated, so the balance cannot be set by any gym session'
);

-- 11-16. insert of a row carrying Gym B's tenant_id raises 42501 — `with check`
-- is what stops a caller writing into, or moving a row to, another tenant.

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('b0000000-0000-4000-8000-000000000001'::uuid, 'winback', 'push', 'en', 'Planted') $q$,
  '42501'::text, null::text,
  'gate 7: gym A inserting a message_templates row for gym B is rejected by with check'
);
select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel)
      values ('b0000000-0000-4000-8000-000000000001'::uuid,
              'b0000000-0000-4000-8000-000000000004'::uuid, 'push') $q$,
  '42501'::text, null::text,
  'gate 7: gym A inserting a notifications row for gym B is rejected by with check'
);
select throws_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('b0000000-0000-4000-8000-000000000001'::uuid,
              'b0000000-0000-4000-8000-000000000004'::uuid, 'web', 'tok-comms-rls-planted') $q$,
  '42501'::text, null::text,
  'gate 7: gym A inserting a member_devices row for gym B is rejected by with check'
);
select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
      values ('b0000000-0000-4000-8000-000000000001'::uuid,
              'b0000000-0000-4000-8000-000000000004'::uuid, 'marketing', false, 'v1', 'planted') $q$,
  '42501'::text, null::text,
  'DPD-001: gym A cannot record a consent decision for gym B''s member'
);
select throws_ok(
  $q$ insert into public.messaging_wallets (tenant_id, balance_credits)
      values ('b0000000-0000-4000-8000-000000000001'::uuid, 1) $q$,
  '42501'::text, null::text,
  'gate 7 (ADR-047): gym A inserting a messaging_wallets row for gym B is rejected for want of privilege — the wallet is read-only to authenticated'
);
select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('b0000000-0000-4000-8000-000000000001'::uuid, -50, 'planted') $q$,
  '42501'::text, null::text,
  'gate 7: gym A inserting a messaging_wallet_ledger row for gym B is rejected by with check'
);

-- 17-22. delete of Gym B's row is refused for want of privilege — Phase 1 grants
-- DELETE to `authenticated` on no table at all, so gym B's row stays in place
-- whichever way the caller reaches for it (verified as the owner at 55-60).

select throws_ok(
  $q$ delete from public.message_templates where id = 'b0000000-0000-4000-8000-000000000005'::uuid $q$,
  '42501'::text, null::text,
  'gate 7: gym A deleting gym B message_templates is refused, the row stays'
);
select throws_ok(
  $q$ delete from public.notifications where id = 'b0000000-0000-4000-8000-000000000006'::uuid $q$,
  '42501'::text, null::text,
  'gate 7: gym A deleting gym B notifications is refused, the row stays'
);
select throws_ok(
  $q$ delete from public.member_devices where id = 'b0000000-0000-4000-8000-000000000007'::uuid $q$,
  '42501'::text, null::text,
  'gate 7: gym A deleting gym B member_devices is refused, the row stays'
);
select throws_ok(
  $q$ delete from public.consents where id = 'b0000000-0000-4000-8000-000000000008'::uuid $q$,
  '42501'::text, null::text,
  'DPD-004/INT-001: gym A deleting gym B consents is refused, the row stays'
);
select throws_ok(
  $q$ delete from public.messaging_wallets where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid $q$,
  '42501'::text, null::text,
  'gate 7: gym A deleting gym B messaging_wallets is refused, the row stays'
);
select throws_ok(
  $q$ delete from public.messaging_wallet_ledger where id = 'b0000000-0000-4000-8000-000000000009'::uuid $q$,
  '42501'::text, null::text,
  'INT-001: gym A deleting gym B messaging_wallet_ledger is refused, the row stays'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 23-28. As a super_admin: the platform policy sees both gyms, with no
-- tenant_id claim at all.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select is((select count(*) from public.message_templates), 2::bigint,
  'gate 7: a super_admin sees message_templates from both gyms');
select is((select count(*) from public.notifications), 2::bigint,
  'gate 7: a super_admin sees notifications from both gyms');
select is((select count(*) from public.member_devices), 2::bigint,
  'gate 7: a super_admin sees member_devices from both gyms');
select is((select count(*) from public.consents), 2::bigint,
  'gate 7: a super_admin sees consents from both gyms');
select is((select count(*) from public.messaging_wallets), 2::bigint,
  'gate 7: a super_admin sees messaging_wallets from both gyms');
select is((select count(*) from public.messaging_wallet_ledger), 2::bigint,
  'gate 7: a super_admin sees messaging_wallet_ledger from both gyms');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 29-41. With no JWT claims at all. Zero rows, not an error: a policy that
-- raised would let a caller tell "nothing here" apart from "wrong tenant".
-- ---------------------------------------------------------------------------

set local role authenticated;

select lives_ok(
  $q$ select count(*) from public.message_templates
      union all select count(*) from public.notifications
      union all select count(*) from public.member_devices
      union all select count(*) from public.consents
      union all select count(*) from public.messaging_wallets
      union all select count(*) from public.messaging_wallet_ledger $q$,
  'gate 7: with no claims a select is silently empty and does not raise'
);

select is_empty($q$ select id from public.message_templates $q$,
  'gate 7: no claims, no message_templates rows');
select is_empty($q$ select id from public.notifications $q$,
  'gate 7: no claims, no notifications rows');
select is_empty($q$ select id from public.member_devices $q$,
  'gate 7: no claims, no member_devices rows');
select is_empty($q$ select id from public.consents $q$,
  'gate 7: no claims, no consents rows');
select is_empty($q$ select tenant_id from public.messaging_wallets $q$,
  'gate 7: no claims, no messaging_wallets rows');
select is_empty($q$ select id from public.messaging_wallet_ledger $q$,
  'gate 7: no claims, no messaging_wallet_ledger rows');

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 'noclaims', 'push', 'en', 'Planted') $q$,
  '42501'::text, null::text,
  'gate 7: no claims, an insert into message_templates is rejected');
select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'push') $q$,
  '42501'::text, null::text,
  'gate 7: no claims, an insert into notifications is rejected');
select throws_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'web', 'tok-comms-rls-noclaims') $q$,
  '42501'::text, null::text,
  'gate 7: no claims, an insert into member_devices is rejected');
select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'service', true, 'v1', 'noclaims') $q$,
  '42501'::text, null::text,
  'DPD-002: no claims, an insert into consents is rejected');
select throws_ok(
  $q$ insert into public.messaging_wallets (tenant_id, balance_credits)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 1) $q$,
  '42501'::text, null::text,
  'gate 7: no claims, an insert into messaging_wallets is rejected');
select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, -1, 'noclaims') $q$,
  '42501'::text, null::text,
  'gate 7: no claims, an insert into messaging_wallet_ledger is rejected');

set local role postgres;

-- ---------------------------------------------------------------------------
-- 42-54. With an empty-string tenant_id claim: identical to no claims —
-- app.current_tenant_id() nullifs the empty string before the uuid cast, so it
-- yields null rather than raising 22P02.
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select lives_ok(
  $q$ select count(*) from public.message_templates
      union all select count(*) from public.notifications
      union all select count(*) from public.member_devices
      union all select count(*) from public.consents
      union all select count(*) from public.messaging_wallets
      union all select count(*) from public.messaging_wallet_ledger $q$,
  'gate 7: an empty-string tenant_id claim is silently empty and does not raise'
);

select is_empty($q$ select id from public.message_templates $q$,
  'gate 7: empty tenant_id claim, no message_templates rows');
select is_empty($q$ select id from public.notifications $q$,
  'gate 7: empty tenant_id claim, no notifications rows');
select is_empty($q$ select id from public.member_devices $q$,
  'gate 7: empty tenant_id claim, no member_devices rows');
select is_empty($q$ select id from public.consents $q$,
  'gate 7: empty tenant_id claim, no consents rows');
select is_empty($q$ select tenant_id from public.messaging_wallets $q$,
  'gate 7: empty tenant_id claim, no messaging_wallets rows');
select is_empty($q$ select id from public.messaging_wallet_ledger $q$,
  'gate 7: empty tenant_id claim, no messaging_wallet_ledger rows');

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 'emptyclaim', 'push', 'en', 'Planted') $q$,
  '42501'::text, null::text,
  'gate 7: empty tenant_id claim, an insert into message_templates is rejected');
select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'push') $q$,
  '42501'::text, null::text,
  'gate 7: empty tenant_id claim, an insert into notifications is rejected');
select throws_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'web', 'tok-comms-rls-emptyclaim') $q$,
  '42501'::text, null::text,
  'gate 7: empty tenant_id claim, an insert into member_devices is rejected');
select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'service', true, 'v1', 'emptyclaim') $q$,
  '42501'::text, null::text,
  'DPD-002: empty tenant_id claim, an insert into consents is rejected');
select throws_ok(
  $q$ insert into public.messaging_wallets (tenant_id, balance_credits)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 1) $q$,
  '42501'::text, null::text,
  'gate 7: empty tenant_id claim, an insert into messaging_wallets is rejected');
select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, -1, 'emptyclaim') $q$,
  '42501'::text, null::text,
  'gate 7: empty tenant_id claim, an insert into messaging_wallet_ledger is rejected');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 55-60. Back as the owner: every one of Gym B's rows survived the whole matrix
-- unchanged. This is the half of "affects zero rows" that a row count cannot see.
-- ---------------------------------------------------------------------------

select is(
  (select body from public.message_templates where id = 'b0000000-0000-4000-8000-000000000005'::uuid),
  'Gym B copy',
  'gate 7: gym B message_templates row is unchanged and still present');
select is(
  (select template_key from public.notifications where id = 'b0000000-0000-4000-8000-000000000006'::uuid),
  'renewal_reminder',
  'gate 7: gym B notifications row is unchanged and still present');
select is(
  (select is_active from public.member_devices where id = 'b0000000-0000-4000-8000-000000000007'::uuid),
  true,
  'gate 7: gym B member_devices row is unchanged and still present');
select is(
  (select balance_credits from public.messaging_wallets where tenant_id = 'b0000000-0000-4000-8000-000000000001'::uuid),
  250::bigint,
  'gate 7: gym B messaging_wallets balance is unchanged');
select is(
  (select count(*) from public.consents where id = 'b0000000-0000-4000-8000-000000000008'::uuid),
  1::bigint,
  'DPD-004: gym B consent row is still in place after gym A tried to delete it');
select is(
  (select count(*) from public.messaging_wallet_ledger where id = 'b0000000-0000-4000-8000-000000000009'::uuid),
  1::bigint,
  'INT-001: gym B ledger row is still in place after gym A tried to delete it');

select * from finish();

rollback;
