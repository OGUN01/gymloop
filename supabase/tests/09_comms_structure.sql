-- 09_comms_structure.sql — visible pgTAP suite, cluster: comms (structure).
--
-- Written from openspec/changes/0001-data-model/specs/comms/spec.md and
-- docs/data-model.md "Cluster: comms" + "Conventions (the contract)", before any
-- migration existed. Every assertion names the spec scenario or the requirement id
-- it descends from; it does not restate the requirement text.
--
-- Six tables: message_templates, notifications, member_devices, consents,
-- messaging_wallets, messaging_wallet_ledger. Three enums: notification_channel,
-- notification_status, consent_purpose.
--
-- Phase 1 enforces no legal-transition rules for notification_status — gate 14
-- belongs to the phase that first mutates the status. Nothing here asserts one.

begin;

-- The CLI mints a NOINHERIT login role for CI (docs/decisions.md ADR-046):
-- the owner role is assumed explicitly, never inherited from the connection.
set local role postgres;

set local search_path = extensions, public;

select plan(72);

-- ---------------------------------------------------------------------------
-- Fixtures, inserted as the owner: the contract forbids `force row level
-- security`, so RLS does not apply to postgres here (docs/data-model.md,
-- "How a pgTAP test assumes a role").
-- ---------------------------------------------------------------------------

insert into public.organizations (id, name, gym_code) values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'Comms Structure Gym A', 'CMSTRA'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'Comms Structure Gym B', 'CMSTRB');

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
   'a0000000-0000-4000-8000-000000000002'::uuid, 'Member A', '+919000000001'),
  ('b0000000-0000-4000-8000-000000000004'::uuid, 'b0000000-0000-4000-8000-000000000001'::uuid,
   'b0000000-0000-4000-8000-000000000002'::uuid, 'Member B', '+919000000002');

insert into public.message_templates (id, tenant_id, key, channel, locale, body) values
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'renewal_reminder', 'push', 'en', 'Your membership expires soon');

insert into public.notifications (id, tenant_id, member_id, channel, dedupe_key) values
  ('a0000000-0000-4000-8000-000000000006'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000004'::uuid, 'push', 'renewal:a0000000:expiry_minus_7');

insert into public.member_devices (id, tenant_id, member_id, platform, push_token) values
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   'a0000000-0000-4000-8000-000000000004'::uuid, 'android', 'tok-comms-structure-a1');

insert into public.messaging_wallets (tenant_id) values
  ('a0000000-0000-4000-8000-000000000001'::uuid);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('a0000000-0000-4000-8000-000000000009'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid,
   500, 'topup');

-- ---------------------------------------------------------------------------
-- 1-6. The six tables the comms cluster owns exist.
-- ---------------------------------------------------------------------------

select has_table('public', 'message_templates', 'comms: message_templates exists (spec: a template is unique per gym, key, channel and locale)');
select has_table('public', 'notifications', 'comms: notifications exists (PAY-002 needs somewhere to record the send)');
select has_table('public', 'member_devices', 'comms: member_devices exists (spec: a push notification has somewhere to go, ADR-016)');
select has_table('public', 'consents', 'comms: consents exists (DPD-002)');
select has_table('public', 'messaging_wallets', 'comms: messaging_wallets exists (ADR-016 credit wallet from day one)');
select has_table('public', 'messaging_wallet_ledger', 'comms: messaging_wallet_ledger exists (ADR-016)');

-- ---------------------------------------------------------------------------
-- 7-12. The three enums, with their labels in the contract's order —
-- docs/data-model.md "Enums": the order is part of the contract because it is
-- what `supabase gen types` emits and what any `order by` follows.
-- ---------------------------------------------------------------------------

select has_enum('public', 'notification_channel', 'comms: notification_channel is a Postgres enum (ADR-021)');
select enum_has_labels(
  'public', 'notification_channel',
  array['push', 'whatsapp_link', 'in_app', 'sms', 'email']::name[],
  'comms: notification_channel labels in the contract order (spec: a channel outside the vocabulary)'
);

select has_enum('public', 'notification_status', 'comms: notification_status is a Postgres enum (ADR-021)');
select enum_has_labels(
  'public', 'notification_status',
  array['scheduled', 'sent', 'delivered', 'failed', 'clicked', 'converted', 'opted_out']::name[],
  'comms: notification_status labels in the contract order (spec: a status outside the vocabulary)'
);

select has_enum('public', 'consent_purpose', 'comms: consent_purpose is a Postgres enum (ADR-021)');
select enum_has_labels(
  'public', 'consent_purpose',
  array['marketing', 'service']::name[],
  'comms: consent_purpose labels in the contract order (INT-002)'
);

-- ---------------------------------------------------------------------------
-- 13-31. Columns, types and nullability the table list marks specially.
-- ---------------------------------------------------------------------------

select col_type_is('public', 'message_templates', 'channel', 'notification_channel',
  'comms: message_templates.channel comes from the closed vocabulary');
select col_default_is('public', 'message_templates', 'locale', 'en'::text,
  'comms: message_templates.locale defaults to en (spec: the same key in another locale)');

select col_type_is('public', 'notifications', 'status', 'notification_status',
  'comms: notifications.status comes from the closed vocabulary (spec: a status outside the vocabulary)');
select col_default_is('public', 'notifications', 'status', 'scheduled'::text,
  'comms: notifications.status defaults to scheduled (PAY-002 — a reminder is written scheduled, then sent)');
select col_is_null('public', 'notifications', 'dedupe_key',
  'comms: notifications.dedupe_key is nullable (spec: ad-hoc messages with no key)');
select col_not_null('public', 'notifications', 'member_id',
  'comms: notifications.member_id is required — PAY-002 dedupes a message to a member');
select col_type_is('public', 'notifications', 'payload', 'jsonb',
  'comms: notifications.payload is jsonb, never json (contract: Every table)');

select col_type_is('public', 'member_devices', 'platform', 'text',
  'comms: member_devices.platform is text with a check, not a fourth enum (contract: Enums ownership table)');
select col_not_null('public', 'member_devices', 'push_token',
  'comms: member_devices.push_token is required (spec: a push notification has somewhere to go)');

select col_not_null('public', 'consents', 'granted',
  'comms: consents.granted is required — DPD-004 withdrawal is a row with granted = false');
select col_is_null('public', 'consents', 'recorded_by_staff_id',
  'comms: consents.recorded_by_staff_id is nullable — a member can consent in-app with no staff actor (DPD-002)');
select has_column('public', 'consents', 'recorded_at',
  'comms: consents.recorded_at is the domain timestamp DPD-002 requires');
select has_column('public', 'consents', 'created_at',
  'comms: consents keeps created_at beside recorded_at (contract: Every table, no exceptions)');

select has_column('public', 'messaging_wallets', 'created_at',
  'comms: messaging_wallets has created_at — the contract wins over the table list omission');
select hasnt_column('public', 'messaging_wallets', 'id',
  'comms: messaging_wallets is keyed by tenant_id and has no id column (contract: Every table)');
select col_is_pk('public', 'messaging_wallets', 'tenant_id',
  'comms: messaging_wallets.tenant_id is the primary key (spec: one wallet per gym)');
select col_type_is('public', 'messaging_wallets', 'balance_credits', 'bigint',
  'comms: messaging_wallets.balance_credits is bigint — credits, not money, so no currency column beside it');

select col_type_is('public', 'messaging_wallet_ledger', 'delta_credits', 'bigint',
  'comms: messaging_wallet_ledger.delta_credits is bigint (spec: the balance is the sum)');
select col_is_null('public', 'messaging_wallet_ledger', 'notification_id',
  'comms: messaging_wallet_ledger.notification_id is nullable — a top-up moves credits with no notification');

-- ---------------------------------------------------------------------------
-- 32-38. Check constraints reject bad values.
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 'onboarding', 'push', 'en-IN', 'Welcome') $q$,
  '23514'::text, null::text,
  'comms: a malformed locale is rejected (spec scenario: a malformed locale)'
);

select throws_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'windows', 'tok-comms-structure-a2') $q$,
  '23514'::text, null::text,
  'comms: member_devices.platform outside (ios, android, web) is rejected'
);

select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'marketing', true, '', 'signup_form') $q$,
  '23514'::text, null::text,
  'comms: an empty consent version is rejected (spec scenario: consent with no version, DPD-002)'
);

select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'marketing', true, 'v1', '') $q$,
  '23514'::text, null::text,
  'comms: an empty consent source is rejected (DPD-002 — a consent decision states where it came from)'
);

select throws_ok(
  $q$ update public.messaging_wallets set balance_credits = -1
      where tenant_id = 'a0000000-0000-4000-8000-000000000001'::uuid $q$,
  '23514'::text, null::text,
  'comms: a wallet balance driven below zero is rejected (spec scenario: a balance driven below zero)'
);

select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 0, 'noop') $q$,
  '23514'::text, null::text,
  'comms: a ledger delta of zero is rejected (spec scenario: a ledger entry that moves nothing)'
);

select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, -10, '') $q$,
  '23514'::text, null::text,
  'comms: an empty ledger reason is rejected (spec: every movement carries a non-empty reason)'
);

-- ---------------------------------------------------------------------------
-- 39-47. Uniqueness. PAY-002 is made structural here: the unique partial index
-- on notifications (tenant_id, dedupe_key) where dedupe_key is not null is what
-- stops a reminder job that runs twice from sending twice.
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 'renewal_reminder', 'push', 'en', 'Second copy') $q$,
  '23505'::text, null::text,
  'comms: a duplicate (tenant, key, channel, locale) template is rejected (spec scenario: a duplicate template)'
);

select lives_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 'renewal_reminder', 'push', 'hi', 'Hindi copy') $q$,
  'comms: the same key and channel in another locale is accepted (spec scenario: the same key in another locale)'
);

select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'push', 'renewal:a0000000:expiry_minus_7') $q$,
  '23505'::text, null::text,
  'PAY-002: a second notification with the same dedupe key in the same gym is rejected (spec scenario: the same reminder stage scheduled twice)'
);

select lives_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
      values ('b0000000-0000-4000-8000-000000000001'::uuid,
              'b0000000-0000-4000-8000-000000000004'::uuid, 'push', 'renewal:a0000000:expiry_minus_7') $q$,
  'PAY-002: the same dedupe key at a different gym is accepted (spec scenario: the same key at another gym)'
);

select lives_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'push', null),
             ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'push', null) $q$,
  'PAY-002: two notifications with a null dedupe key in the same gym are both accepted — the index is partial (spec scenario: ad-hoc messages with no key)'
);

select lives_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('b0000000-0000-4000-8000-000000000001'::uuid,
              'b0000000-0000-4000-8000-000000000004'::uuid, 'ios', 'tok-comms-structure-a1') $q$,
  'comms (ADR-047): push_token is unique PER GYM, not globally — a member may belong to two gyms, so the same handset registered at a second gym is accepted (spec scenario: the same push token registered twice)'
);

select throws_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'ios', 'tok-comms-structure-a1') $q$,
  '23505'::text, null::text,
  'comms (ADR-047): the same push token registered twice within one gym is still rejected — (tenant_id, push_token) is unique'
);

select lives_ok(
  $q$ insert into public.member_devices (tenant_id, member_id, platform, push_token)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'ios', 'tok-comms-structure-a3') $q$,
  'comms: a second device for the same member with a different token is accepted (spec scenario: a member with several devices)'
);

select throws_ok(
  $q$ insert into public.messaging_wallets (tenant_id)
      values ('a0000000-0000-4000-8000-000000000001'::uuid) $q$,
  '23505'::text, null::text,
  'comms: a second wallet row for the same organisation is rejected (spec scenario: one wallet per gym)'
);

-- ---------------------------------------------------------------------------
-- 48-52. Consent is per (member, purpose), append-only, and the two purposes
-- are independently withdrawable (INT-002, DPD-003, DPD-004). Current state is
-- the latest row per (member, purpose), so there is deliberately NO unique
-- constraint on (member_id, purpose) to violate.
-- ---------------------------------------------------------------------------

select lives_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'marketing', true, 'v1', 'signup_form',
              now() - interval '2 days'),
             ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'service', true, 'v1', 'signup_form',
              now() - interval '2 days') $q$,
  'INT-002: a member holds a marketing row and a service row at once — they are independent purposes'
);

select is(
  (select count(*) from public.consents
    where member_id = 'a0000000-0000-4000-8000-000000000004'::uuid),
  2::bigint,
  'DPD-003: marketing and service consent are stored as separately controlled entries'
);

select lives_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at)
      values ('a0000000-0000-4000-8000-000000000001'::uuid,
              'a0000000-0000-4000-8000-000000000004'::uuid, 'marketing', false, 'v1', 'member_app',
              now()) $q$,
  'DPD-004: two rows with the same (member_id, purpose) and different recorded_at are both accepted — withdrawal is a new row, not an edit (spec scenario: withdrawing consent)'
);

select is(
  (select count(*) from public.consents
    where member_id = 'a0000000-0000-4000-8000-000000000004'::uuid and purpose = 'marketing'),
  2::bigint,
  'DPD-004: the earlier marketing row still exists after withdrawal — consent history is not deleted (spec scenario: withdrawing consent)'
);

-- This assertion used to read the `service` row after inserting a `marketing`
-- row and check that `service` was unchanged, which no schema can make fail.
-- What INT-002 actually claims is about the DERIVED current state the contract
-- defines — "current state = latest row per (member, purpose)" — so that is what
-- is read: the marketing withdrawal is current for marketing and has not
-- displaced the service grant. This does fail against a real defect, e.g. a
-- recorded_at the writer cannot set (a trigger stamping it, or a generated
-- column), which would make the two marketing rows unorderable and resolve the
-- current marketing state back to `true`.
select results_eq(
  $q$ select distinct on (purpose) purpose::text collate "default" as purpose_text, granted
        from public.consents
       where member_id = 'a0000000-0000-4000-8000-000000000004'::uuid
       order by purpose, recorded_at desc $q$,
  $q$ values ('marketing'::text, false), ('service'::text, true) $q$,
  'INT-002: current state is the latest row per (member, purpose) — marketing now reads withdrawn and service still reads granted (spec scenario: withdrawing one purpose leaves the other)'
);

-- ---------------------------------------------------------------------------
-- 53-63. Append-only is a privilege, not a trigger (contract: Privileges;
-- INT-001, DPD-004, and the same shape NSH-007 gives follow-ups). An
-- insert-only grant cannot be forgotten in a code path the way a guard can.
-- Asserted with the three-argument form so it does not depend on the session role.
-- ---------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.consents', 'SELECT'),
  'DPD-002: authenticated may read consents');
select ok(has_table_privilege('authenticated', 'public.consents', 'INSERT'),
  'DPD-004: authenticated may append a consent row');
select ok(not has_table_privilege('authenticated', 'public.consents', 'UPDATE'),
  'DPD-004: authenticated holds no UPDATE on consents — append-only');
select ok(not has_table_privilege('authenticated', 'public.consents', 'DELETE'),
  'INT-001: authenticated holds no DELETE on consents — consent history survives withdrawal');

select ok(has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'SELECT'),
  'comms: authenticated may read messaging_wallet_ledger');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'INSERT'),
  'ADR-049: authenticated holds no INSERT on messaging_wallet_ledger — the contract says the balance IS the sum of the ledger, so an append grant would let a gym mint its own messaging credits and defeat ADR-047''s read-only wallet');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'UPDATE'),
  'ADR-049: authenticated holds no UPDATE on messaging_wallet_ledger — read-only, not append-only');
select ok(not has_table_privilege('authenticated', 'public.messaging_wallet_ledger', 'DELETE'),
  'INT-001: authenticated holds no DELETE on messaging_wallet_ledger — the balance is the sum of an unbroken ledger');

-- act as a signed-in owner of Gym A: the refusal must hold inside the caller's
-- OWN tenant, which is what makes it a privilege and not tenant isolation.
select set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated',
                    'tenant_id', 'a0000000-0000-4000-8000-000000000001', 'app_role', 'gym_owner')::text,
  true
);
set local role authenticated;

select throws_ok(
  $q$ update public.consents set granted = false
      where member_id = 'a0000000-0000-4000-8000-000000000004'::uuid and purpose = 'service' $q$,
  '42501'::text, null::text,
  'DPD-004: an authenticated caller updating a consent row in their own tenant is refused for want of privilege (spec scenario: editing a consent record)'
);

select throws_ok(
  $q$ delete from public.consents
      where member_id = 'a0000000-0000-4000-8000-000000000004'::uuid and purpose = 'service' $q$,
  '42501'::text, null::text,
  'INT-001: an authenticated caller deleting a consent row in their own tenant is refused for want of privilege (spec scenario: deleting a consent record)'
);

select throws_ok(
  $q$ update public.messaging_wallet_ledger set delta_credits = 1
      where id = 'a0000000-0000-4000-8000-000000000009'::uuid $q$,
  '42501'::text, null::text,
  'INT-001: an authenticated caller updating a ledger row in their own tenant is refused for want of privilege (spec scenario: editing the ledger)'
);

-- ADR-049, and the refusal that has to hold inside the caller's OWN tenant: a
-- cross-tenant insert would be refused by the policy even with the grant still
-- in place, so only this one shows the grant is gone. Without it the wallet
-- being read-only buys nothing — the gym simply appends its own credit rows.
select throws_ok(
  $q$ insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason)
      values ('a0000000-0000-4000-8000-000000000001'::uuid, 500, 'self-issued credits') $q$,
  '42501'::text, null::text,
  'ADR-049: an authenticated caller appending a ledger row in their own tenant is refused for want of privilege — the balance is the sum of the ledger, so this is the same hole ADR-047 closed on messaging_wallets'
);

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 64-71. `updated_at` triggers exist on exactly the tables the list gives an
-- `updated_at`, and on no others: "a table with no updated_at gets no trigger"
-- (contract: Every table). consents is append-only and messaging_wallet_ledger
-- is read-only (ADR-049); neither has an updated_at or a trigger.
-- ---------------------------------------------------------------------------

select has_trigger('public', 'message_templates', 'message_templates_touch_updated_at',
  'comms: message_templates carries the shared updated_at trigger');
select has_trigger('public', 'notifications', 'notifications_touch_updated_at',
  'comms: notifications carries the shared updated_at trigger — its delivery stamps are updated in place');
select has_trigger('public', 'member_devices', 'member_devices_touch_updated_at',
  'comms: member_devices carries the shared updated_at trigger');
select has_trigger('public', 'messaging_wallets', 'messaging_wallets_touch_updated_at',
  'comms: messaging_wallets carries the shared updated_at trigger');

select hasnt_column('public', 'consents', 'updated_at',
  'DPD-004: consents has no updated_at — a consent row is never updated');
select hasnt_trigger('public', 'consents', 'consents_touch_updated_at',
  'DPD-004: consents therefore carries no updated_at trigger');
select hasnt_column('public', 'messaging_wallet_ledger', 'updated_at',
  'INT-001: messaging_wallet_ledger has no updated_at — a ledger row is never updated');
select hasnt_trigger('public', 'messaging_wallet_ledger', 'messaging_wallet_ledger_touch_updated_at',
  'INT-001: messaging_wallet_ledger therefore carries no updated_at trigger');

select * from finish();

rollback;
