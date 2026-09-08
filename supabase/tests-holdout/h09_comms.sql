-- h09_comms — HOLDOUT pgTAP suite for the `comms` cluster of Gymloop Phase 1.
--
-- Written blind from openspec/changes/0001-data-model/specs/comms/spec.md and
-- docs/data-model.md's contract, without reading the migration or the visible
-- suite (AGENTS.md hard rule 10). Tables under test:
--   message_templates, notifications, member_devices,
--   consents, messaging_wallets, messaging_wallet_ledger
--
-- Wrapped BEGIN … ROLLBACK per ADR-030: the suite runs against the one shared
-- Cloud project and must leave nothing behind.
--
-- Identifiers are prefixed 09c0/H9CM/h9-comms so nothing here can collide with
-- another cluster's fixtures if the suites ever share a session.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path to public, extensions;

select plan(91);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner. `postgres` holds BYPASSRLS, so row security
-- does not apply here; it is re-imposed by `set local role authenticated`.
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code, status) values
  ('09c00000-0000-4000-8000-000000000a00'::uuid, 'Holdout Comms Gym A', 'H9CMGA', 'active'),
  ('09c00000-0000-4000-8000-000000000b00'::uuid, 'Holdout Comms Gym B', 'H9CMGB', 'active');

insert into public.branches (id, tenant_id, name, is_default) values
  ('09c00000-0000-4000-8000-000000000a01'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, 'Holdout Comms Branch A', true),
  ('09c00000-0000-4000-8000-000000000b01'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, 'Holdout Comms Branch B', true);

insert into public.members (id, tenant_id, branch_id, full_name, phone) values
  ('09c00000-0000-4000-8000-000000000a02'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, '09c00000-0000-4000-8000-000000000a01'::uuid, 'Holdout Comms Member A', '+919009000901'),
  ('09c00000-0000-4000-8000-000000000b02'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, '09c00000-0000-4000-8000-000000000b01'::uuid, 'Holdout Comms Member B', '+919009000902');

insert into public.message_templates (id, tenant_id, key, channel, locale, body) values
  ('09c00000-0000-4000-8000-000000000a11'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, 'holdout.renewal', 'push', 'en', 'Gym A template body'),
  ('09c00000-0000-4000-8000-000000000b11'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, 'holdout.renewal', 'push', 'en', 'Gym B template body');

insert into public.notifications (id, tenant_id, member_id, channel) values
  ('09c00000-0000-4000-8000-000000000a10'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, '09c00000-0000-4000-8000-000000000a02'::uuid, 'push'),
  ('09c00000-0000-4000-8000-000000000b10'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, '09c00000-0000-4000-8000-000000000b02'::uuid, 'push');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('09c00000-0000-4000-8000-000000000a12'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, '09c00000-0000-4000-8000-000000000a02'::uuid, 'android', 'h9.comms.holdout.token.a1'),
  ('09c00000-0000-4000-8000-000000000b12'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, '09c00000-0000-4000-8000-000000000b02'::uuid, 'ios', 'h9.comms.holdout.token.b1');

-- recorded_at is deliberately backdated: it is the domain timestamp (when the
-- member decided), created_at is when the row landed. Backdating also makes the
-- "latest row per (member, purpose)" ordering deterministic, since now() is
-- constant for the whole transaction.
insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source, recorded_at) values
  ('09c00000-0000-4000-8000-000000000a13'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, '09c00000-0000-4000-8000-000000000a02'::uuid, 'marketing', true, 'v1', 'holdout fixture', now() - interval '1 day'),
  ('09c00000-0000-4000-8000-000000000a15'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, '09c00000-0000-4000-8000-000000000a02'::uuid, 'service', true, 'v1', 'holdout fixture', now() - interval '1 day'),
  ('09c00000-0000-4000-8000-000000000b13'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, '09c00000-0000-4000-8000-000000000b02'::uuid, 'marketing', true, 'v1', 'holdout fixture', now() - interval '1 day');

insert into public.messaging_wallets (tenant_id, balance_credits) values
  ('09c00000-0000-4000-8000-000000000a00'::uuid, 100),
  ('09c00000-0000-4000-8000-000000000b00'::uuid, 100);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('09c00000-0000-4000-8000-000000000a14'::uuid, '09c00000-0000-4000-8000-000000000a00'::uuid, 100, 'holdout fixture top up'),
  ('09c00000-0000-4000-8000-000000000b14'::uuid, '09c00000-0000-4000-8000-000000000b00'::uuid, 100, 'holdout fixture top up');

-- ===========================================================================
-- PART 0 — no tenant claim at all. The GUC has never been set in this
-- transaction. Zero rows, and no exception: a policy that raised would let a
-- caller tell "wrong tenant" apart from "empty gym".
-- ===========================================================================

set local role authenticated;

select lives_ok(
  $$ select count(*) from public.notifications $$,
  'ISO no-claim: selecting notifications with no request.jwt.claims set does not raise'
);
select is_empty(
  $$ select 1 from public.notifications $$,
  'ISO no-claim: notifications returns zero rows when no tenant claim is present'
);
select is_empty(
  $$ select 1 from public.messaging_wallets $$,
  'ISO no-claim: messaging_wallets returns zero rows when no tenant claim is present'
);

set local role postgres;

-- ===========================================================================
-- PART 1 — signed in as a gym_owner of Gym A. Reads, writes and labelling must
-- all stop at the tenant boundary.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '09c00000-0000-4000-8000-000000000a00',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- message_templates
select isnt_empty(
  $$ select 1 from public.message_templates where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO message_templates: Gym A sees its own template rows'
);
select is_empty(
  $$ select 1 from public.message_templates where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO message_templates: Gym A cannot read Gym B template rows'
);
select throws_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, body) values ('09c00000-0000-4000-8000-000000000b00', 'holdout.cross', 'push', 'x') $$,
  '42501'::char(5), null,
  'ISO message_templates: Gym A cannot insert a row labelled with Gym B'
);

-- notifications
select isnt_empty(
  $$ select 1 from public.notifications where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO notifications: Gym A sees its own notification rows'
);
select is_empty(
  $$ select 1 from public.notifications where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO notifications: Gym A cannot read Gym B notification rows'
);
select throws_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'push') $$,
  '42501'::char(5), null,
  'ISO notifications: Gym A cannot insert a row labelled with Gym B'
);

-- member_devices
select isnt_empty(
  $$ select 1 from public.member_devices where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO member_devices: Gym A sees its own device rows'
);
select is_empty(
  $$ select 1 from public.member_devices where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO member_devices: Gym A cannot read Gym B device rows'
);
select throws_ok(
  $$ insert into public.member_devices (tenant_id, member_id, platform, push_token) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'web', 'h9.comms.holdout.token.x9') $$,
  '42501'::char(5), null,
  'ISO member_devices: Gym A cannot insert a row labelled with Gym B'
);

-- consents
select isnt_empty(
  $$ select 1 from public.consents where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO consents: Gym A sees its own consent rows'
);
select is_empty(
  $$ select 1 from public.consents where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO consents: Gym A cannot read Gym B consent rows'
);
select throws_ok(
  $$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'marketing', true, 'v1', 'holdout cross tenant') $$,
  '42501'::char(5), null,
  'ISO consents: Gym A cannot insert a row labelled with Gym B'
);

-- messaging_wallets
select isnt_empty(
  $$ select 1 from public.messaging_wallets where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO messaging_wallets: Gym A sees its own wallet row'
);
select is_empty(
  $$ select 1 from public.messaging_wallets where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO messaging_wallets: Gym A cannot read Gym B wallet row'
);
select throws_ok(
  $$ insert into public.messaging_wallets (tenant_id, balance_credits) values ('09c00000-0000-4000-8000-000000000b00', 5) $$,
  '42501'::char(5), null,
  'ISO messaging_wallets: Gym A cannot insert a wallet row labelled with Gym B'
);

-- messaging_wallet_ledger
select isnt_empty(
  $$ select 1 from public.messaging_wallet_ledger where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ISO messaging_wallet_ledger: Gym A sees its own ledger rows'
);
select is_empty(
  $$ select 1 from public.messaging_wallet_ledger where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  'ISO messaging_wallet_ledger: Gym A cannot read Gym B ledger rows'
);
select throws_ok(
  $$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason) values ('09c00000-0000-4000-8000-000000000b00', 10, 'holdout cross tenant') $$,
  '42501'::char(5), null,
  'ISO messaging_wallet_ledger: Gym A cannot insert a row labelled with Gym B'
);

-- The policy is not simply deny-all: a correctly labelled write succeeds.
select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'in_app') $$,
  'ISO notifications: Gym A may insert a row labelled with its own tenant'
);

-- An RLS policy filters an UPDATE rather than raising, so these three statements
-- are expected to match zero rows and succeed silently. The assertions that
-- they changed nothing are made below, as the owner, which is the only vantage
-- point from which Gym B's rows are readable.
update public.message_templates set body = 'holdout tamper' where id = '09c00000-0000-4000-8000-000000000b11';
update public.notifications set failed_reason = 'holdout tamper' where id = '09c00000-0000-4000-8000-000000000b10';
update public.member_devices set is_active = false where id = '09c00000-0000-4000-8000-000000000b12';

-- messaging_wallets is the exception: ADR-047 puts it in the read-only tier, so
-- authenticated holds no UPDATE at all and the write is refused outright rather
-- than filtered down to zero rows.
select throws_ok(
  $$ update public.messaging_wallets set balance_credits = 999 where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  '42501'::char(5), null,
  'ISO messaging_wallets: ADR-047 read-only tier, a wallet update is refused for want of privilege and never reaches the policy'
);

-- Delete is granted to nobody in Phase 1, on any table.
select throws_ok(
  $$ delete from public.notifications where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  '42501'::char(5), null,
  'ISO notifications: delete is refused for want of privilege'
);
select ok(not has_table_privilege('authenticated', 'public.message_templates', 'DELETE'),
  'ISO message_templates: authenticated holds no DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'DELETE'),
  'ISO notifications: authenticated holds no DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.member_devices', 'DELETE'),
  'ISO member_devices: authenticated holds no DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.consents', 'DELETE'),
  'ISO consents: authenticated holds no DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallets', 'DELETE'),
  'ISO messaging_wallets: authenticated holds no DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'DELETE'),
  'ISO messaging_wallet_ledger: authenticated holds no DELETE privilege');

set local role postgres;

-- Gym B's rows survived Gym A's four cross-tenant updates untouched.
select results_eq(
  $$ select body from public.message_templates where id = '09c00000-0000-4000-8000-000000000b11' $$,
  ARRAY['Gym B template body'],
  'ISO message_templates: Gym B row is unchanged after Gym A attempted to update it by primary key'
);
select results_eq(
  $$ select coalesce(failed_reason, 'unset') from public.notifications where id = '09c00000-0000-4000-8000-000000000b10' $$,
  ARRAY['unset'],
  'ISO notifications: Gym B row is unchanged after Gym A attempted to update it by primary key'
);
select results_eq(
  $$ select is_active from public.member_devices where id = '09c00000-0000-4000-8000-000000000b12' $$,
  ARRAY[true],
  'ISO member_devices: Gym B row is unchanged after Gym A attempted to update it by primary key'
);
select results_eq(
  $$ select balance_credits from public.messaging_wallets where tenant_id = '09c00000-0000-4000-8000-000000000b00' $$,
  ARRAY[100::bigint],
  'ISO messaging_wallets: Gym B wallet is unchanged after Gym A''s refused update by primary key'
);

-- ===========================================================================
-- PART 2 — the claim is present but empty. Same silent-empty behaviour as no
-- claim at all: app.current_tenant_id() is null, so the predicate is null.
-- ===========================================================================

select set_config('request.jwt.claims', '', true);
set local role authenticated;

select lives_ok(
  $$ select count(*) from public.consents $$,
  'ISO empty-claim: selecting consents with an empty request.jwt.claims does not raise'
);
select is_empty(
  $$ select 1 from public.consents $$,
  'ISO empty-claim: consents returns zero rows when the claim is the empty string'
);

set local role postgres;

-- ===========================================================================
-- PART 3 — the platform branch. super_admin and platform_support cross tenants
-- (ADR-032, ADR-033) and carry no tenant claim of their own.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'super_admin')::text,
  true
);
set local role authenticated;

select results_eq(
  $$ select count(*) from public.notifications where id in ('09c00000-0000-4000-8000-000000000a10', '09c00000-0000-4000-8000-000000000b10') $$,
  ARRAY[2::bigint],
  'ISO platform: super_admin reads notifications across both tenants with no tenant claim'
);
select results_eq(
  $$ select count(*) from public.consents where id in ('09c00000-0000-4000-8000-000000000a13', '09c00000-0000-4000-8000-000000000b13') $$,
  ARRAY[2::bigint],
  'ISO platform: super_admin reads consents across both tenants'
);
select results_eq(
  $$ select count(*) from public.messaging_wallets where tenant_id in ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000b00') $$,
  ARRAY[2::bigint],
  'ISO platform: super_admin reads messaging_wallets across both tenants'
);
select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'in_app') $$,
  'ISO platform: the platform policy with check admits a row labelled with any tenant'
);

set local role postgres;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'app_role', 'platform_support')::text,
  true
);
set local role authenticated;

select results_eq(
  $$ select count(*) from public.member_devices where id in ('09c00000-0000-4000-8000-000000000a12', '09c00000-0000-4000-8000-000000000b12') $$,
  ARRAY[2::bigint],
  'ISO platform: platform_support reads member_devices across both tenants'
);

set local role postgres;

-- ===========================================================================
-- PART 4 — the cluster's own promises. Back in Gym A's seat.
-- ===========================================================================

select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', '09c00000-0000-4000-8000-000000000a00',
                    'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

-- --- PAY-002: one message per stage, made structural ------------------------

select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'push', 'holdout:renewal:expiry_minus_7') $$,
  'PAY-002: the first notification carrying a de-duplication key is accepted'
);
select throws_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'push', 'holdout:renewal:expiry_minus_7') $$,
  '23505'::char(5), null,
  'PAY-002: a second notification reusing the de-duplication key within the same organisation is rejected'
);
select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'push', null) $$,
  'PAY-002: an ad-hoc notification with no de-duplication key is accepted'
);
select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'push', null) $$,
  'PAY-002: a second notification with no de-duplication key is also accepted, the key is only unique where it is present'
);

-- --- message_templates: unique per gym, key, channel and locale -------------

select throws_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.renewal', 'push', 'en', 'duplicate') $$,
  '23505'::char(5), null,
  'message_templates: a duplicate of (tenant, key, channel, locale) is rejected so a send is never ambiguous'
);
select lives_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.renewal', 'push', 'hi', 'same key another locale') $$,
  'message_templates: the same key and channel in a different locale is accepted'
);
select lives_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.renewal', 'in_app', 'en', 'same key another channel') $$,
  'message_templates: the same key and locale on a different channel is accepted'
);
select throws_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.locale', 'push', 'en-IN', 'x') $$,
  '23514'::char(5), null,
  'message_templates: a locale of en-IN is rejected, the locale is exactly two lower-case letters'
);
select throws_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.locale', 'push', 'EN', 'x') $$,
  '23514'::char(5), null,
  'message_templates: an upper-case locale of EN is rejected'
);
select throws_ok(
  $$ insert into public.message_templates (tenant_id, key, channel, locale, body) values ('09c00000-0000-4000-8000-000000000a00', 'holdout.locale', 'push', 'eng', 'x') $$,
  '23514'::char(5), null,
  'message_templates: a three-letter locale of eng is rejected'
);

-- --- notifications: the vocabularies are closed -----------------------------

select throws_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, status) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'push', 'bounced') $$,
  '22P02'::char(5), null,
  'notifications: a status of bounced is rejected, delivery reporting cannot invent a state'
);
select throws_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'telegram') $$,
  '22P02'::char(5), null,
  'notifications: a channel of telegram is rejected, the channel vocabulary is closed'
);
select results_eq(
  $$ select status::text from public.notifications where id = '09c00000-0000-4000-8000-000000000a10' $$,
  ARRAY['scheduled'],
  'notifications: a row written with no status defaults to scheduled'
);

-- --- member_devices: one row per push token per gym (ADR-047) ---------------

select lives_ok(
  $$ insert into public.member_devices (tenant_id, member_id, platform, push_token) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'web', 'h9.comms.holdout.token.a2') $$,
  'ADR-016: a member may register a second device with a different push token'
);
select throws_ok(
  $$ insert into public.member_devices (tenant_id, member_id, platform, push_token) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'android', 'h9.comms.holdout.token.a1') $$,
  '23505'::char(5), null,
  'ADR-016: a push token already registered at this gym is rejected, the uniqueness is (tenant_id, push_token)'
);
select throws_ok(
  $$ insert into public.member_devices (tenant_id, member_id, platform, push_token) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'windows', 'h9.comms.holdout.token.a3') $$,
  '23514'::char(5), null,
  'ADR-016: a device platform outside (ios, android, web) is rejected'
);

-- --- consents: append-only, versioned, split by purpose ---------------------

select ok(has_table_privilege('authenticated', 'public.consents', 'INSERT'),
  'DPD-002: authenticated may insert a consent row');
select ok(has_table_privilege('authenticated', 'public.consents', 'SELECT'),
  'DPD-002: authenticated may read consent rows');
select ok(not has_table_privilege('authenticated', 'public.consents', 'UPDATE'),
  'DPD-004: authenticated holds no UPDATE privilege on consents, the table is append-only');
select throws_ok(
  $$ update public.consents set granted = false where id = '09c00000-0000-4000-8000-000000000a13' $$,
  '42501'::char(5), null,
  'DPD-004: updating a consent row inside the callers own tenant is refused for want of privilege'
);
select throws_ok(
  $$ delete from public.consents where id = '09c00000-0000-4000-8000-000000000a13' $$,
  '42501'::char(5), null,
  'DPD-004: deleting a consent row inside the callers own tenant is refused for want of privilege'
);
select throws_ok(
  $$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'marketing', true, '', 'holdout') $$,
  '23514'::char(5), null,
  'DPD-002: a consent row with an empty version is rejected, consent is versioned'
);
select throws_ok(
  $$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'marketing', true, 'v1', '') $$,
  '23514'::char(5), null,
  'DPD-002: a consent row with an empty source is rejected'
);
select lives_ok(
  $$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source) values ('09c00000-0000-4000-8000-000000000a00', '09c00000-0000-4000-8000-000000000a02', 'marketing', false, 'v1', 'holdout withdrawal') $$,
  'DPD-004: withdrawing marketing consent is a new row carrying granted = false'
);
select results_eq(
  $$ select granted from public.consents where id = '09c00000-0000-4000-8000-000000000a13' $$,
  ARRAY[true],
  'DPD-004: the earlier marketing grant still exists after withdrawal, the history is not deleted'
);
select results_eq(
  $$ select granted from public.consents where member_id = '09c00000-0000-4000-8000-000000000a02' and purpose = 'marketing' order by recorded_at desc limit 1 $$,
  ARRAY[false],
  'DPD-004: the latest marketing row for the member is the withdrawal'
);
select results_eq(
  $$ select granted from public.consents where member_id = '09c00000-0000-4000-8000-000000000a02' and purpose = 'service' order by recorded_at desc limit 1 $$,
  ARRAY[true],
  'INT-002: withdrawing marketing consent leaves the latest service consent row untouched'
);
select ok(
  (select recorded_at < created_at from public.consents where id = '09c00000-0000-4000-8000-000000000a13'),
  'DPD-002: recorded_at and created_at are two distinct columns, a backdated consent keeps both'
);

-- --- messaging_wallet_ledger: read-only to a gym session (ADR-049) ----------

select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'INSERT'),
  'ADR-049: authenticated holds no INSERT on messaging_wallet_ledger - the balance is the sum of the ledger, so an append-only grant here would hand a gym the credit minting that ADR-047 took away from the wallet');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'UPDATE'),
  'ADR-049: authenticated holds no UPDATE privilege on messaging_wallet_ledger either, the ledger is read-only to a gym session');
select throws_ok(
  $$ update public.messaging_wallet_ledger set reason = 'holdout tamper' where id = '09c00000-0000-4000-8000-000000000a14' $$,
  '42501'::char(5), null,
  'ADR-016: updating a ledger row inside the callers own tenant is refused for want of privilege'
);
select throws_ok(
  $$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason) values ('09c00000-0000-4000-8000-000000000a00', 5, 'holdout self issued credit') $$,
  '42501'::char(5), null,
  'ADR-049: a gym session crediting its own ledger, correctly labelled with its own tenant, is refused for want of privilege'
);

-- messaging_wallets' and messaging_wallet_ledger's own constraints are asserted
-- in PART 5 instead: ADR-047 and ADR-049 moved both tables into the read-only
-- tier, so a gym session can no longer reach them - both are written by
-- service_role and by nobody else.

set local role postgres;

-- ===========================================================================
-- PART 5 — cross-gym facts and shape, asserted as the owner so nothing is
-- hidden by a policy or by a role's catalogue visibility.
-- ===========================================================================

select lives_ok(
  $$ insert into public.member_devices (tenant_id, member_id, platform, push_token) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'ios', 'h9.comms.holdout.token.a1') $$,
  'ADR-016/ADR-047: the same push token registered at a second gym is accepted, push_token is unique per gym - a member may belong to two gyms and each needs its own delivery target for the one handset'
);
select lives_ok(
  $$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key) values ('09c00000-0000-4000-8000-000000000b00', '09c00000-0000-4000-8000-000000000b02', 'push', 'holdout:renewal:expiry_minus_7') $$,
  'PAY-002: the same de-duplication key at a different gym is accepted, the key is unique per organisation'
);
select results_eq(
  $$ select count(*) from public.message_templates where key = 'holdout.renewal' and channel = 'push' and locale = 'en' $$,
  ARRAY[2::bigint],
  'message_templates: the same key, channel and locale coexist at two gyms, the uniqueness is tenant-scoped'
);

-- --- messaging_wallets: one per gym, never negative -------------------------
-- Asserted as the owner because ADR-047's read-only tier leaves no user session
-- that may write the wallet at all.
select throws_ok(
  $$ update public.messaging_wallets set balance_credits = -1 where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  '23514'::char(5), null,
  'ADR-016: a wallet balance driven below zero is rejected'
);
select lives_ok(
  $$ update public.messaging_wallets set balance_credits = 0 where tenant_id = '09c00000-0000-4000-8000-000000000a00' $$,
  'ADR-016: a wallet balance of exactly zero is accepted, the bound is inclusive'
);
select throws_ok(
  $$ insert into public.messaging_wallets (tenant_id, balance_credits) values ('09c00000-0000-4000-8000-000000000a00', 50) $$,
  '23505'::char(5), null,
  'ADR-016: a second wallet row for the same organisation is rejected, tenant_id is the primary key'
);

-- --- messaging_wallet_ledger: every movement is non-zero and gives a reason --
select throws_ok(
  $$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason) values ('09c00000-0000-4000-8000-000000000a00', 0, 'holdout no movement') $$,
  '23514'::char(5), null,
  'ADR-016: a ledger row with a delta of zero is rejected, a ledger row records a movement'
);
select lives_ok(
  $$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason) values ('09c00000-0000-4000-8000-000000000a00', -5, 'holdout debit') $$,
  'ADR-016: a negative delta is accepted, a debit is a movement'
);
select throws_ok(
  $$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason) values ('09c00000-0000-4000-8000-000000000a00', 5, '') $$,
  '23514'::char(5), null,
  'ADR-016: a ledger row with an empty reason is rejected'
);
select is_empty(
  $$ select table_name from information_schema.columns where table_schema = 'public' and column_name = 'currency' and table_name in ('message_templates', 'notifications', 'member_devices', 'consents', 'messaging_wallets', 'messaging_wallet_ledger') $$,
  'MNY-002: no table in the comms cluster carries a currency column, messaging credits are a count and not money'
);
select col_type_is('public', 'messaging_wallets', 'balance_credits', 'bigint',
  'ADR-016: balance_credits is a plain bigint credit count');
select has_column('public', 'messaging_wallets', 'created_at',
  'the contract: every table carries created_at, messaging_wallets included');
select has_column('public', 'messaging_wallet_ledger', 'created_at',
  'the contract: messaging_wallet_ledger carries created_at');
select has_column('public', 'consents', 'recorded_at',
  'DPD-002: consents carries recorded_at, the domain timestamp of the decision');
select has_column('public', 'consents', 'created_at',
  'the contract: consents also carries created_at, the insert timestamp');
select enum_has_labels('public', 'notification_channel',
  ARRAY['push', 'whatsapp_link', 'in_app', 'sms', 'email']::name[],
  'ADR-016: notification_channel is exactly the contract vocabulary, in contract order');
select enum_has_labels('public', 'notification_status',
  ARRAY['scheduled', 'sent', 'delivered', 'failed', 'clicked', 'converted', 'opted_out']::name[],
  'notification_status is exactly the contract vocabulary, in contract order');
select enum_has_labels('public', 'consent_purpose',
  ARRAY['marketing', 'service']::name[],
  'INT-002: consent_purpose is exactly marketing and service, independently withdrawable');

select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
