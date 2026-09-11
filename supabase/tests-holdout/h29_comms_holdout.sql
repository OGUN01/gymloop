-- h29_comms_holdout — HOLDOUT pgTAP suite for the Phase 6 communications/wallet
-- contract (docs/planning/phase6-comms-contract.md, ADR-111, 2026-09-10).
--
-- Written blind from that contract, phase6-contract-seam.md, docs/data-model.md,
-- docs/domain-rules.md, docs/security.md, docs/registry.md, supabase/seed.sql
-- (fixture id shape only) and existing migrations through 20260915100006, plus
-- other h2x_*.sql files for house style only. Never read: supabase/tests/ (the
-- visible suite, 31/32/33_comms*.sql), h28_member_import_holdout.sql, or any
-- implementation. AGENTS.md hard rule 10 / ADR-060.
--
-- Nothing in this cluster exists yet as of 20260915100006: every RPC/trigger
-- call below is expected to answer 42883 (undefined_function) or 42703
-- (undefined_column) today. That is the correct RED state — the assertions
-- encode the contract's promised behaviour for the implementer to turn green,
-- not today's schema. Wrapped BEGIN … ROLLBACK per ADR-030/ADR-042.
--
-- Fixture ids are prefixed b2900000-0000-4000-8000-00000000XXXX so nothing
-- here can collide with another cluster's fixtures.

begin;

set local role postgres;
set local search_path to public, extensions;

select plan(123);

-- ===========================================================================
-- FIXTURES — inserted as postgres (BYPASSRLS). Rows that must land in a
-- non-'scheduled' notification status, or carry a controlled membership
-- ends_on/periods_granted/duration_days, go in under
-- `session_replication_role = replica` (ADR-098's stated-out-loud bypass):
-- the invariant triggers this contract describes are not under test in the
-- fixture-setup itself, only in the assertions that follow.
-- ===========================================================================

insert into public.organizations (id, name, gym_code, status, timezone, currency) values
  ('b2900000-0000-4000-8000-000000000a00'::uuid, 'Holdout Comms Gym A', 'H29CMA', 'active', 'Asia/Kolkata', 'INR'),
  ('b2900000-0000-4000-8000-000000000b00'::uuid, 'Holdout Comms Gym B', 'H29CMB', 'active', 'Asia/Kolkata', 'INR'),
  ('b2900000-0000-4000-8000-000000000c00'::uuid, 'Holdout Comms Gym C Suspended', 'H29CMC', 'suspended', 'Asia/Kolkata', 'INR');

insert into public.organization_settings (tenant_id) values
  ('b2900000-0000-4000-8000-000000000a00'::uuid),
  ('b2900000-0000-4000-8000-000000000b00'::uuid),
  ('b2900000-0000-4000-8000-000000000c00'::uuid);

insert into public.branches (id, tenant_id, name, is_default) values
  ('b2900000-0000-4000-8000-000000000a01'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'Holdout Comms Branch A', true),
  ('b2900000-0000-4000-8000-000000000b01'::uuid, 'b2900000-0000-4000-8000-000000000b00'::uuid, 'Holdout Comms Branch B', true),
  ('b2900000-0000-4000-8000-000000000c01'::uuid, 'b2900000-0000-4000-8000-000000000c00'::uuid, 'Holdout Comms Branch C', true);

-- Synthetic auth.users rows so staff/member/platform_users FKs resolve and
-- auth.uid()-matching invariants (real staff/member identity) have something
-- to match against. Each fixture reuses its own id as its auth user id.
insert into auth.users (id) values
  ('b2900000-0000-4000-8000-000000000a02'::uuid), ('b2900000-0000-4000-8000-000000000a03'::uuid),
  ('b2900000-0000-4000-8000-000000000a04'::uuid), ('b2900000-0000-4000-8000-000000000b02'::uuid),
  ('b2900000-0000-4000-8000-000000000a10'::uuid), ('b2900000-0000-4000-8000-000000000a11'::uuid),
  ('b2900000-0000-4000-8000-000000000a12'::uuid), ('b2900000-0000-4000-8000-000000000a13'::uuid),
  ('b2900000-0000-4000-8000-000000000b10'::uuid), ('b2900000-0000-4000-8000-0000000000f1'::uuid);

insert into public.staff (id, tenant_id, user_id, branch_id, role, full_name, is_active) values
  ('b2900000-0000-4000-8000-000000000a02'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a02'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'gym_owner', 'Holdout Owner A', true),
  ('b2900000-0000-4000-8000-000000000a03'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a03'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'front_desk', 'Holdout Front Desk A', true),
  ('b2900000-0000-4000-8000-000000000a04'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a04'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'trainer', 'Holdout Trainer A', true),
  ('b2900000-0000-4000-8000-000000000b02'::uuid, 'b2900000-0000-4000-8000-000000000b00'::uuid, 'b2900000-0000-4000-8000-000000000b02'::uuid, 'b2900000-0000-4000-8000-000000000b01'::uuid, 'gym_owner', 'Holdout Owner B', true);

insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone, status, motivation_push_enabled) values
  ('b2900000-0000-4000-8000-000000000a10'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'Holdout Member A1', '+919000000001', 'active', true),
  ('b2900000-0000-4000-8000-000000000a11'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'b2900000-0000-4000-8000-000000000a11'::uuid, 'Holdout Member A2 No Motivation', '+919000000002', 'active', false),
  ('b2900000-0000-4000-8000-000000000a12'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'b2900000-0000-4000-8000-000000000a12'::uuid, 'Holdout Member A3 Blocked', '+919000000003', 'blocked', true),
  ('b2900000-0000-4000-8000-000000000a13'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a01'::uuid, 'b2900000-0000-4000-8000-000000000a13'::uuid, 'Holdout Member A4 Zero Due', '+919000000004', 'active', true),
  ('b2900000-0000-4000-8000-000000000b10'::uuid, 'b2900000-0000-4000-8000-000000000b00'::uuid, 'b2900000-0000-4000-8000-000000000b01'::uuid, 'b2900000-0000-4000-8000-000000000b10'::uuid, 'Holdout Member B1', '+919000000011', 'active', true);

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  ('b2900000-0000-4000-8000-0000000000f1'::uuid, 'super_admin', 'Holdout Super Admin', 'h29-super@holdout.test', true);

insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency) values
  ('b2900000-0000-4000-8000-000000000a20'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'Holdout Plan A', 30, 100000, 'INR');

-- Memberships with controlled ends_on/periods_granted/duration_days, bypassing
-- app.stamp_membership()/app.grant_periods()/the GL047 transition trigger,
-- which are not under test here (ADR-098 replica bypass, stated out loud).
set local session_replication_role = replica;

insert into public.memberships
  (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency, periods_granted, duration_days) values
  -- A1: ends 3 days ago -> localDate = ends_on + 3 matches expiry_plus_3.
  ('b2900000-0000-4000-8000-000000000a30'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'b2900000-0000-4000-8000-000000000a20'::uuid, 'active', (current_date - 33), (current_date - 3), 100000, 0, 'INR', 1, 30),
  -- A2: ends today -> matches expiry_day; member has motivation disabled and no consent row (missing-consent fixture too).
  ('b2900000-0000-4000-8000-000000000a31'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a11'::uuid, 'b2900000-0000-4000-8000-000000000a20'::uuid, 'active', (current_date - 30), current_date, 100000, 0, 'INR', 1, 30),
  -- A big-value remainder fixture, no window relevance.
  ('b2900000-0000-4000-8000-000000000a32'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'b2900000-0000-4000-8000-000000000a20'::uuid, 'expired', (current_date - 400), (current_date - 370), 9007199254740993, 0, 'INR', 1, 30),
  -- cancelled membership sitting in an otherwise matching window: must be skipped.
  ('b2900000-0000-4000-8000-000000000a33'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a12'::uuid, 'b2900000-0000-4000-8000-000000000a20'::uuid, 'cancelled', (current_date - 33), (current_date - 3), 100000, 0, 'INR', 1, 30),
  -- zero-due membership (complimentary, distinct member so the one-live-membership
  -- index does not collide with A30): due must be zero, no reminder.
  ('b2900000-0000-4000-8000-000000000a34'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a13'::uuid, 'b2900000-0000-4000-8000-000000000a20'::uuid, 'active', (current_date - 33), (current_date - 3), 0, 0, 'INR', 1, 30);

insert into public.payments
  (id, tenant_id, member_id, membership_id, amount_paise, currency, status, method, recorded_by_staff_id, receipt_number, paid_at) values
  ('b2900000-0000-4000-8000-000000000a40'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'b2900000-0000-4000-8000-000000000a30'::uuid, 100000, 'INR', 'paid', 'cash', 'b2900000-0000-4000-8000-000000000a03'::uuid, 'H29RCPT001', now() - interval '33 days'),
  ('b2900000-0000-4000-8000-000000000a41'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'b2900000-0000-4000-8000-000000000a32'::uuid, 9007199254740993, 'INR', 'paid', 'cash', 'b2900000-0000-4000-8000-000000000a03'::uuid, 'H29RCPT002', now() - interval '400 days');

set local session_replication_role = origin;

-- A service consent for member A1 (eligible for reminders), none for A2/A3.
insert into public.consents (id, tenant_id, member_id, purpose, granted, version, source, recorded_at) values
  ('b2900000-0000-4000-8000-000000000a50'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'service', true, 'h29-v1', 'holdout fixture', now() - interval '10 days');

insert into public.messaging_wallets (tenant_id, balance_credits) values
  ('b2900000-0000-4000-8000-000000000a00'::uuid, 500),
  ('b2900000-0000-4000-8000-000000000b00'::uuid, 500);

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason) values
  ('b2900000-0000-4000-8000-000000000a51'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 500, 'holdout fixture top up'),
  ('b2900000-0000-4000-8000-000000000b51'::uuid, 'b2900000-0000-4000-8000-000000000b00'::uuid, 500, 'holdout fixture top up');

-- A source in_app renewal-shaped notification, sent, for the WhatsApp/ack tests
-- below. status is not 'scheduled', so the fixture insert bypasses the future
-- invariant trigger (ADR-098 pattern) rather than going through send_notification,
-- which is the thing under test elsewhere in this file.
set local session_replication_role = replica;

insert into public.notifications
  (id, tenant_id, member_id, channel, status, dedupe_key, scheduled_for, sent_at, related_type, related_id, payload) values
  ('b2900000-0000-4000-8000-000000000a60'::uuid, 'b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a10'::uuid, 'in_app', 'sent', 'h29:source:a60', now() - interval '1 hour', now() - interval '1 hour', 'membership', 'b2900000-0000-4000-8000-000000000a30'::uuid, jsonb_build_object('body','Your membership ends soon.'));

set local session_replication_role = origin;

-- ===========================================================================
-- PART 1 — §1 shared boundaries: function shape and ACLs (catalog-only,
-- safe against nonexistent objects via to_regprocedure + coalesce).
-- ===========================================================================

select ok(coalesce((select not p.prosecdef and p.provolatile = 'v' and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure(
      'public.record_consent(uuid,public.consent_purpose,boolean,text,text,uuid)')), false),
  '3: record_consent is volatile, invoker, empty search_path');
select ok(coalesce(has_function_privilege('authenticated', to_regprocedure(
    'public.record_consent(uuid,public.consent_purpose,boolean,text,text,uuid)'), 'EXECUTE'), false),
  '1/3: authenticated may execute record_consent');
select ok(not coalesce(has_function_privilege('anon', to_regprocedure(
    'public.record_consent(uuid,public.consent_purpose,boolean,text,text,uuid)'), 'EXECUTE'), true),
  '1: anon may not execute record_consent, default PUBLIC/anon execute is revoked');

select ok(coalesce((select p.provolatile = 'i' and not p.prosecdef and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('app.notification_consent_purpose(public.message_category)')), false),
  '3: app.notification_consent_purpose is immutable, invoker, empty search_path');
select ok(coalesce(has_function_privilege('authenticated', to_regprocedure(
    'app.notification_consent_purpose(public.message_category)'), 'EXECUTE'), false),
  '1: authenticated may execute the pure category helper');
select ok(coalesce(has_function_privilege('service_role', to_regprocedure(
    'app.notification_consent_purpose(public.message_category)'), 'EXECUTE'), false),
  '1: service_role may execute the pure category helper');

select ok(coalesce((select p.provolatile = 'i' and not p.prosecdef
    from pg_catalog.pg_proc p where p.oid = to_regprocedure(
      'app.notification_transition_allowed(public.notification_status,public.notification_status)')), false),
  '4: app.notification_transition_allowed is immutable invoker');

select ok(coalesce((select p.provolatile = 'v' and not p.prosecdef and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.send_notification(uuid)')), false),
  '4: send_notification is volatile, invoker, empty search_path');
select ok(not coalesce(has_function_privilege('anon', to_regprocedure('public.send_notification(uuid)'), 'EXECUTE'), true),
  '1: anon may not execute send_notification');

select ok(coalesce((select p.prosecdef and p.proowner = 'postgres'::regrole and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.acknowledge_notification(uuid)')), false),
  '5: acknowledge_notification is definer, owned by postgres, empty search_path');
select ok(not coalesce(has_function_privilege('anon', to_regprocedure('public.acknowledge_notification(uuid)'), 'EXECUTE'), true),
  '5: anon may not execute acknowledge_notification');

select ok(coalesce((select p.prosecdef and p.proowner = 'postgres'::regrole and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.open_notification_whatsapp(uuid)')), false),
  '5: open_notification_whatsapp is definer, owned by postgres, empty search_path');

select ok(coalesce((select p.provolatile = 's' and not p.prosecdef
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('app.membership_renewal_remainder(uuid,uuid)')), false),
  '6: app.membership_renewal_remainder is stable invoker');
select ok(coalesce(has_function_privilege('service_role', to_regprocedure('app.membership_renewal_remainder(uuid,uuid)'), 'EXECUTE'), false),
  '6: service_role may execute the remainder helper for the scheduler');

select ok(coalesce(has_function_privilege('service_role', to_regprocedure('app.default_renewal_reminder_windows()'), 'EXECUTE'), false)
    and not coalesce(has_function_privilege('authenticated', to_regprocedure('app.default_renewal_reminder_windows()'), 'EXECUTE'), true),
  '6: the default-window helper is service_role only, not authenticated');

select ok(not coalesce(has_function_privilege('authenticated', to_regprocedure('app.run_renewal_reminders(uuid)'), 'EXECUTE'), true)
    and not coalesce(has_function_privilege('authenticated', to_regprocedure('public.run_renewal_reminders_all()'), 'EXECUTE'), true),
  '6: neither renewal-reminder runner is an authenticated RPC');

select ok(coalesce((select p.prosecdef and 'search_path=""' = any(p.proconfig)
    from pg_catalog.pg_proc p where p.oid = to_regprocedure(
      'public.adjust_messaging_wallet(uuid,bigint,text,uuid)')), false),
  '7: adjust_messaging_wallet is definer, empty search_path');
select ok(coalesce(has_function_privilege('authenticated', to_regprocedure(
    'public.adjust_messaging_wallet(uuid,bigint,text,uuid)'), 'EXECUTE'), false),
  '7: authenticated may execute adjust_messaging_wallet (the super_admin gate is inside the body)');

select ok(not coalesce(has_function_privilege('public', to_regprocedure(
      'app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)'), 'EXECUTE'), true)
    and not coalesce(has_function_privilege('anon', to_regprocedure(
      'app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)'), 'EXECUTE'), true)
    and not coalesce(has_function_privilege('authenticated', to_regprocedure(
      'app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)'), 'EXECUTE'), true)
    and not coalesce(has_function_privilege('service_role', to_regprocedure(
      'app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)'), 'EXECUTE'), true),
  '7: app.record_wallet_movement is executable by nobody directly - only its owning command may call it');

-- ===========================================================================
-- PART 2 — §2 schema and indexes.
-- ===========================================================================

select enum_has_labels('public', 'message_category',
  ARRAY['renewal', 'payment', 'fulfilment', 'promotion', 'motivation']::name[],
  '2: message_category is exactly the contract vocabulary, in contract order');
select has_column('public', 'message_templates', 'category', '2: message_templates.category exists');
select has_column('public', 'consents', 'request_key', '2: consents.request_key exists');
select has_column('public', 'notifications', 'template_id', '2: notifications.template_id exists');
select has_column('public', 'notifications', 'category', '2: notifications.category exists');
select has_column('public', 'notifications', 'source_notification_id', '2: notifications.source_notification_id exists');
select has_column('public', 'notifications', 'recipient_phone', '2: notifications.recipient_phone exists');
select has_column('public', 'notifications', 'failed_at', '2: notifications.failed_at exists');
select has_column('public', 'notifications', 'opted_out_at', '2: notifications.opted_out_at exists');
select has_column('public', 'notifications', 'opted_out_reason', '2: notifications.opted_out_reason exists');
select has_column('public', 'messaging_wallet_ledger', 'request_key', '2: messaging_wallet_ledger.request_key exists');
select has_column('public', 'messaging_wallet_ledger', 'recorded_by_user_id', '2: messaging_wallet_ledger.recorded_by_user_id exists');
select has_column('public', 'messaging_wallet_ledger', 'balance_after_credits', '2: messaging_wallet_ledger.balance_after_credits exists');
select col_type_is('public', 'messaging_wallet_ledger', 'balance_after_credits', 'bigint',
  '2: balance_after_credits is a plain bigint, never a JS-unsafe numeric surprise at rest');

select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'consents'
    and indexdef ilike '%(tenant_id, request_key)%' and indexdef ilike '%where (request_key is not null)%'),
  '2: consents carries the unique partial (tenant_id, request_key) where key is not null');
select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'messaging_wallet_ledger'
    and indexdef ilike '%(tenant_id, request_key)%' and indexdef ilike '%where (request_key is not null)%'),
  '2: messaging_wallet_ledger carries the unique partial (tenant_id, request_key) where key is not null');
select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'consents'
    and indexdef ilike '%(member_id, purpose, recorded_at desc, id desc)%'),
  '2: consents current-state index leads (member_id, purpose, recorded_at desc, id desc)');
select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'notifications'
    and indexdef ilike '%(tenant_id, source_notification_id)%' and indexdef ilike '%unique%'
    and indexdef ilike '%whatsapp_link%'),
  '2: notifications carries unique (tenant_id, source_notification_id) where channel=whatsapp_link');
select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'messaging_wallet_ledger'
    and indexdef ilike '%unique%' and indexdef ilike '%(tenant_id, notification_id)%'
    and indexdef ilike '%where (notification_id is not null)%'),
  '2: messaging_wallet_ledger carries unique (tenant_id, notification_id) where notification_id is not null');
select ok(exists(select 1 from pg_indexes where schemaname = 'public' and tablename = 'message_templates'
    and indexdef ilike '%unique%' and indexdef ilike '%(tenant_id, id)%'),
  '2: message_templates carries a composite unique (tenant_id, id) for the new FK');

-- ===========================================================================
-- PART 3 — §3 consent and the serialization point.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a03',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a03', 'app_role', 'front_desk')::text, true);
set local role authenticated;

select throws_ok(
  $tap$ select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, '', 'holdout source', gen_random_uuid()) $tap$,
  'GL065'::char(5), null,
  '3: a blank version is invalid_consent (GL065)');
select throws_ok(
  $tap$ select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'v1', '', gen_random_uuid()) $tap$,
  'GL065'::char(5), null,
  '3: a blank source is invalid_consent (GL065)');
select throws_ok(
  $tap$ select public.record_consent('b2900000-0000-4000-8000-000000000b10'::uuid, 'marketing'::public.consent_purpose,
    true, 'v1', 'holdout', gen_random_uuid()) $tap$,
  'P0002'::char(5), null,
  '1/3: a cross-gym member id is indistinguishable P0002, never leaks existence');

select lives_ok($tap$
do $$
declare
  v_key uuid := gen_random_uuid();
  v_first jsonb;
  v_replay jsonb;
begin
  v_first := public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'h29-v1', 'holdout consent flow', v_key);
  if not (v_first ? 'consentId' and v_first ? 'memberId' and v_first ? 'purpose' and v_first ? 'granted'
      and v_first ? 'version' and v_first ? 'source' and v_first ? 'recordedAt' and v_first ? 'recordedByStaffId') then
    raise exception 'record_consent result missing a contract key: %', v_first;
  end if;
  if (v_first ->> 'recordedByStaffId') <> 'b2900000-0000-4000-8000-000000000a03' then
    raise exception 'recordedByStaffId should be the caller''s real staff id, got %', v_first;
  end if;
  -- exact replay: same key returns the identical accepted object, no second row.
  v_replay := public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'h29-v1', 'holdout consent flow', v_key);
  if v_replay <> v_first then
    raise exception 'exact replay must return the original accepted object unchanged: % vs %', v_first, v_replay;
  end if;
end $$;
$tap$, '3: record_consent returns the exact contract shape and an exact-key replay is idempotent');

select throws_ok($tap$
  select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    false, 'h29-v1', 'holdout consent flow', 'b2900000-0000-4000-8000-0000000000aa'::uuid)
$tap$, 'GL068'::char(5), null,
  '3: a fresh request key with different facts is fine; a REUSED key with different facts is GL068 (see next test for the reuse)');

select lives_ok($tap$
do $$
declare
  v_key uuid := gen_random_uuid();
begin
  perform public.record_consent('b2900000-0000-4000-8000-000000000a11'::uuid, 'service'::public.consent_purpose,
    true, 'h29-v1', 'holdout', v_key);
  begin
    perform public.record_consent('b2900000-0000-4000-8000-000000000a11'::uuid, 'service'::public.consent_purpose,
      false, 'h29-v1', 'holdout', v_key);
    raise exception 'a reused request key with a different granted value must be refused, not accepted';
  exception when sqlstate 'GL068' then
    null; -- expected
  end;
end $$;
$tap$, '3: a request key reused with a changed fact (granted flipped) is GL068, not a silent upsert');

select lives_ok($tap$
do $$
declare
  v_before timestamptz;
  v_grant jsonb;
  v_withdraw jsonb;
begin
  v_before := clock_timestamp();
  v_grant := public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'service'::public.consent_purpose,
    true, 'h29-v2', 'holdout ordering', gen_random_uuid());
  v_withdraw := public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'service'::public.consent_purpose,
    false, 'h29-v2', 'holdout ordering', gen_random_uuid());
  if (v_withdraw ->> 'recordedAt')::timestamptz <= (v_grant ->> 'recordedAt')::timestamptz then
    raise exception 'a later withdrawal in the same transaction must stamp strictly later than the grant: % then %', v_grant, v_withdraw;
  end if;
  if (select granted from public.consents
       where member_id = 'b2900000-0000-4000-8000-000000000a10' and purpose = 'service'
       order by recorded_at desc, id desc limit 1) <> false then
    raise exception 'the later withdrawal must be the current state, ordered by (recorded_at desc, id desc)';
  end if;
end $$;
$tap$, '3: grant then withdrawal in one transaction still orders correctly and withdrawal wins current state');

select throws_ok($tap$
  select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'h29-v1', 'holdout', gen_random_uuid())
$tap$, '42501'::char(5), null,
  '1: a trainer (not front office) calling record_consent is forbidden');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a04',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a04', 'app_role', 'trainer')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'h29-v1', 'holdout', gen_random_uuid())
$tap$, '42501'::char(5), null,
  '1: a trainer session (not front office) is refused, no fifth gate is introduced');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a03',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a03', 'app_role', 'front_desk')::text, true);
set local role authenticated;

-- app.stamp_consent() also governs a direct table INSERT. A supplied actor that
-- differs from the verified staff claim is GL065; the trigger applies under RLS.
select throws_ok($tap$
  insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_by_staff_id)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'marketing', true,
    'h29-direct', 'holdout direct insert', 'b2900000-0000-4000-8000-000000000a02')
$tap$, 'GL065'::char(5), null,
  '3: app.stamp_consent() refuses a supplied actor that differs from the verified staff claim (GL065)');

select lives_ok($tap$
do $$
declare
  v_id uuid;
begin
  insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'marketing', true,
    'h29-direct2', 'holdout direct insert no actor')
  returning id into v_id;
  if (select recorded_by_staff_id from public.consents where id = v_id) <> 'b2900000-0000-4000-8000-000000000a03' then
    raise exception 'a missing actor on a direct insert must be filled from the verified staff claim';
  end if;
end $$;
$tap$, '3: app.stamp_consent() fills a missing actor from the verified staff claim on a direct insert');

set local role postgres;

-- Blank version/source fails even in the trusted owner context (§3: "even in
-- trusted context"). The trigger applies to every writer, not only RLS-bound ones.
select throws_ok($tap$
  insert into public.consents (tenant_id, member_id, purpose, granted, version, source)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'service', true, '', 'trusted')
$tap$, 'GL065'::char(5), null,
  '3: a blank version fails even under a trusted postgres session');

-- ===========================================================================
-- PART 4 — §3 app.notification_consent_purpose.
-- ===========================================================================

select lives_ok($tap$
do $$
begin
  if app.notification_consent_purpose('promotion'::public.message_category) <> 'marketing'::public.consent_purpose then
    raise exception 'promotion must map to marketing';
  end if;
end $$;
$tap$, '3: promotion maps to marketing');

select lives_ok($tap$
do $$
declare
  v_cat public.message_category;
begin
  foreach v_cat in array array['renewal','payment','fulfilment','motivation']::public.message_category[] loop
    if app.notification_consent_purpose(v_cat) <> 'service'::public.consent_purpose then
      raise exception 'category % must map to service', v_cat;
    end if;
  end loop;
end $$;
$tap$, '3: renewal/payment/fulfilment/motivation all map to service');

select throws_ok($tap$ select app.notification_consent_purpose(null::public.message_category) $tap$,
  '3: a missing/null category fails closed rather than silently defaulting');

-- ===========================================================================
-- PART 5 — §4 the exact lifecycle transition graph.
-- ===========================================================================

select lives_ok($tap$
do $$
declare
  v_statuses text[] := array['scheduled','sent','delivered','failed','clicked','converted','opted_out'];
  v_legal text[] := array['scheduled:sent','scheduled:opted_out','scheduled:failed',
    'sent:delivered','sent:failed','delivered:clicked','delivered:converted','clicked:converted'];
  v_from text; v_to text; v_actual boolean; v_expected boolean;
begin
  foreach v_from in array v_statuses loop
    foreach v_to in array v_statuses loop
      v_expected := (v_from = v_to) or (v_from || ':' || v_to = any(v_legal));
      v_actual := app.notification_transition_allowed(v_from::public.notification_status, v_to::public.notification_status);
      if v_actual is distinct from v_expected then
        raise exception 'graph mismatch % -> %: expected % got %', v_from, v_to, v_expected, v_actual;
      end if;
    end loop;
  end loop;
end $$;
$tap$, '4: app.notification_transition_allowed matches the exact contract graph for all 49 pairs, same-state included');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:illegal1:' || gen_random_uuid()::text)
  returning id into v_id; -- starts scheduled
  update public.notifications set status = 'delivered' where id = v_id; -- scheduled -> delivered is not an edge
end $$;
$tap$, 'GL066'::char(5), null,
  '4: an illegal graph edge (scheduled -> delivered, skipping sent) is refused GL066');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:illegal2:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'sent', sent_at = now() where id = v_id;
  update public.notifications set status = 'failed', failed_at = now(), failed_reason = 'x' where id = v_id;
  update public.notifications set status = 'sent' where id = v_id; -- failed is terminal, cannot move back
end $$;
$tap$, 'GL066'::char(5), null,
  '4: failed is terminal - failed -> sent is refused GL066');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:illegal3:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'sent', sent_at = now() where id = v_id;
  update public.notifications set status = 'delivered', delivered_at = now() where id = v_id;
  update public.notifications set status = 'scheduled' where id = v_id; -- backward edge
end $$;
$tap$, 'GL066'::char(5), null,
  '4: a backward edge (delivered -> scheduled) is refused GL066');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:samestate:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'sent', sent_at = now() where id = v_id;
  -- same-state (sent -> sent) is allowed, but it may not append new evidence.
  update public.notifications set status = 'sent', delivered_at = now() where id = v_id;
end $$;
$tap$, 'GL066'::char(5), null,
  '4: a same-state write cannot smuggle in new evidence (sent -> sent setting delivered_at is refused)');

set local role postgres;

-- ===========================================================================
-- PART 6 — §4 enforce_notification invariants: reserved identity, freeze,
-- backdating, event pairing.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;

select throws_ok($tap$
  insert into public.notifications (tenant_id, member_id, channel, template_key, category, related_type, related_id)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app', 'renewal_reminder',
    'renewal', 'membership', 'b2900000-0000-4000-8000-000000000a30')
$tap$, '42501'::char(5), null,
  '4: a direct authenticated write cannot create a base renewal row - creation belongs to the trusted scheduler');

select throws_ok($tap$
  insert into public.notifications (tenant_id, member_id, channel, template_key, category, related_type, related_id, payload)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app', 'renewal_reminder',
    'promotion', 'membership', 'b2900000-0000-4000-8000-000000000a30', '{"forged":true}'::jsonb)
$tap$, '4: naming the reserved renewal template key with a different category/payload does not bypass the identity check');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_field text;
  v_failed_fields text[] := array[]::text[];
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key, related_type, related_id, payload)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'push',
    'h29:freeze:' || gen_random_uuid()::text, 'membership', 'b2900000-0000-4000-8000-000000000a30', '{"a":1}'::jsonb)
  returning id into v_id;

  begin
    update public.notifications set channel = 'in_app' where id = v_id;
    v_failed_fields := v_failed_fields || 'channel';
  exception when others then null;
  end;
  begin
    update public.notifications set category = 'renewal' where id = v_id;
    v_failed_fields := v_failed_fields || 'category';
  exception when others then null;
  end;
  begin
    update public.notifications set dedupe_key = 'h29:tampered' where id = v_id;
    v_failed_fields := v_failed_fields || 'dedupe_key';
  exception when others then null;
  end;
  begin
    update public.notifications set payload = '{"tampered":true}'::jsonb where id = v_id;
    v_failed_fields := v_failed_fields || 'payload';
  exception when others then null;
  end;
  begin
    update public.notifications set related_id = gen_random_uuid() where id = v_id;
    v_failed_fields := v_failed_fields || 'related_id';
  exception when others then null;
  end;

  if array_length(v_failed_fields, 1) > 0 then
    raise exception 'these identity/content fields must be frozen after creation and were not: %', v_failed_fields;
  end if;
end $$;
$tap$, '4: channel, category, dedupe_key, payload and related identity are frozen after creation');

select throws_ok($tap$
do $$
declare
  v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:pairing:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'failed', failed_at = now() where id = v_id; -- no failed_reason
end $$;
$tap$, '4: failed_at without a nonempty failed_reason is refused (evidence pairing)');

select throws_ok($tap$
do $$
declare
  v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'push',
    'h29:pairing2:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'delivered', delivered_at = now() where id = v_id; -- no sent_at
end $$;
$tap$, '4: delivered requires sent_at/delivered_at, delivered with no sent_at is refused');

select throws_ok($tap$
do $$
declare
  v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:pairing3:' || gen_random_uuid()::text)
  returning id into v_id;
  update public.notifications set status = 'sent', sent_at = now() where id = v_id;
  update public.notifications set status = 'sent', sent_at = now() - interval '1 hour' where id = v_id; -- backdate an existing event
end $$;
$tap$, '4: an existing event timestamp cannot be changed once written');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_scheduled timestamptz := now();
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key, scheduled_for)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'push',
    'h29:backdate:' || gen_random_uuid()::text, v_scheduled)
  returning id into v_id;
  update public.notifications set status = 'sent', sent_at = now() - interval '10 minutes' where id = v_id;
  if (select sent_at from public.notifications where id = v_id) < v_scheduled - interval '1 second' then
    raise exception 'a caller-supplied backdated sent_at must be clamped to clock_timestamp(), not honoured verbatim';
  end if;
end $$;
$tap$, '4: a caller cannot backdate a new event; the database stamps and clamps its own clock');

set local role postgres;

-- ===========================================================================
-- PART 7 — §4 public.send_notification.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a03',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a03', 'app_role', 'front_desk')::text, true);
set local role authenticated;
select throws_ok($tap$ select public.send_notification('b2900000-0000-4000-8000-000000000a60'::uuid) $tap$,
  '42501'::char(5), null,
  '4: send_notification requires a real gym admin, front desk is refused');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;

select throws_ok($tap$
  select public.send_notification('b2900000-0000-4000-8000-000000000a99'::uuid)
$tap$, 'P0002'::char(5), null,
  '4: send_notification against a missing/cross-gym id is P0002, identical to any other absent target');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key, scheduled_for)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:future:' || gen_random_uuid()::text, now() + interval '1 hour')
  returning id into v_id;
  perform public.send_notification(v_id);
end $$;
$tap$, 'GL066'::char(5), null,
  '4: sending a row scheduled in the future is GL066');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_result jsonb;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a12', 'in_app',
    'h29:ineligible:' || gen_random_uuid()::text)
  returning id into v_id; -- member A12 is 'blocked'
  v_result := public.send_notification(v_id);
  if (v_result ->> 'status') <> 'opted_out' or (v_result ->> 'optedOutReason') <> 'recipient_ineligible' then
    raise exception 'an ineligible member must answer opted_out/recipient_ineligible, got %', v_result;
  end if;
end $$;
$tap$, '4: sending to an ineligible member gives opted_out/recipient_ineligible');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_result jsonb;
begin
  -- member A2 (no motivation, no service consent) has no consent row at all.
  insert into public.notifications (tenant_id, member_id, channel, category, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a11', 'in_app', 'fulfilment',
    'h29:noconsent:' || gen_random_uuid()::text)
  returning id into v_id;
  v_result := public.send_notification(v_id);
  if (v_result ->> 'status') <> 'opted_out' or (v_result ->> 'optedOutReason') <> 'consent_withdrawn' then
    raise exception 'missing service consent must give opted_out/consent_withdrawn, got %', v_result;
  end if;
end $$;
$tap$, '4: sending with no recorded service consent gives opted_out/consent_withdrawn');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_result jsonb;
begin
  -- member A2 has motivation_push_enabled = false.
  insert into public.notifications (tenant_id, member_id, channel, category, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a11', 'in_app', 'motivation',
    'h29:nomotivation:' || gen_random_uuid()::text)
  returning id into v_id;
  v_result := public.send_notification(v_id);
  if (v_result ->> 'status') <> 'opted_out' or (v_result ->> 'optedOutReason') <> 'motivation_disabled' then
    raise exception 'disabled motivation must give opted_out/motivation_disabled, got %', v_result;
  end if;
end $$;
$tap$, '4: sending a motivation category to a member with motivation_push_enabled=false gives motivation_disabled');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_result jsonb;
  v_ledger_count int;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:inapp:' || gen_random_uuid()::text)
  returning id into v_id;
  v_result := public.send_notification(v_id);
  if (v_result ->> 'status') <> 'sent' or (v_result ->> 'sentAt') is null then
    raise exception 'an eligible in_app send must become sent with sentAt set, got %', v_result;
  end if;
  select count(*) into v_ledger_count from public.messaging_wallet_ledger where notification_id = v_id;
  if v_ledger_count <> 0 then
    raise exception 'in_app is zero cost, no ledger row may be created';
  end if;
end $$;
$tap$, '4: an eligible in_app send is sent at zero cost with no ledger row');

select lives_ok($tap$
do $$
declare
  v_id uuid;
  v_result jsonb;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'push',
    'h29:push:' || gen_random_uuid()::text)
  returning id into v_id;
  v_result := public.send_notification(v_id);
  if (v_result ->> 'status') <> 'failed' or (v_result ->> 'failedReason') <> 'provider_unconfigured'
      or (v_result ->> 'sentAt') is not null or (v_result ->> 'deliveredAt') is not null then
    raise exception 'push must fail provider_unconfigured with null sent/delivered_at, got %', v_result;
  end if;
end $$;
$tap$, '4: push becomes failed/provider_unconfigured with null sent/delivered timestamps, zero cost');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'sms',
    'h29:sms:' || gen_random_uuid()::text)
  returning id into v_id;
  perform public.send_notification(v_id);
end $$;
$tap$, 'GL066'::char(5), null,
  '4: sms has no v1 send action, GL066');

set local role postgres;

-- ===========================================================================
-- PART 8 — §5 public.acknowledge_notification.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a10',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'member_id', 'b2900000-0000-4000-8000-000000000a10', 'app_role', 'member')::text, true);
set local role authenticated;

select lives_ok($tap$
do $$
declare
  v_result jsonb;
begin
  v_result := public.acknowledge_notification('b2900000-0000-4000-8000-000000000a60'::uuid);
  if (v_result ->> 'status') <> 'delivered' or (v_result ->> 'deliveredAt') is null then
    raise exception 'sent -> delivered must succeed with deliveredAt set, got %', v_result;
  end if;
end $$;
$tap$, '5: acknowledge_notification transitions sent -> delivered and returns the exact result shape');

select lives_ok($tap$
do $$
declare
  v_a jsonb; v_b jsonb;
begin
  v_a := public.acknowledge_notification('b2900000-0000-4000-8000-000000000a60'::uuid);
  v_b := public.acknowledge_notification('b2900000-0000-4000-8000-000000000a60'::uuid);
  if v_a <> v_b then
    raise exception 'a repeat acknowledge on an already-delivered row must be an inert replay: % vs %', v_a, v_b;
  end if;
end $$;
$tap$, '5: acknowledging an already-delivered notification is an inert replay, no timestamp/audit change');

select throws_ok($tap$
  select public.acknowledge_notification('b2900000-0000-4000-8000-000000000b10'::uuid)
$tap$, 'P0002'::char(5), null,
  '5: acknowledging another gym''s / nonexistent notification id is indistinguishable P0002');

select throws_ok($tap$
do $$
declare v_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:notack:' || gen_random_uuid()::text)
  returning id into v_id; -- still 'scheduled'
  perform public.acknowledge_notification(v_id);
end $$;
$tap$, 'GL066'::char(5), null,
  '5: acknowledging a row not in sent status (still scheduled) is GL066');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.acknowledge_notification('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, '5: a staff claim (not a complete member claim) may not call acknowledge_notification');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-0000000000f1',
    'role', 'authenticated', 'app_role', 'gym_owner', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'impersonation_session_id', gen_random_uuid())::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.acknowledge_notification('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, '5: an impersonation claim is refused, member-claim-only');

set local role postgres;

-- ===========================================================================
-- PART 9 — §5 public.open_notification_whatsapp.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a10',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'member_id', 'b2900000-0000-4000-8000-000000000a10', 'app_role', 'member')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.open_notification_whatsapp('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, '42501'::char(5), null,
  '5: open_notification_whatsapp requires a real front-office identity, a member is refused');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a03',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a03', 'app_role', 'front_desk')::text, true);
set local role authenticated;

select lives_ok($tap$
do $$
declare
  v_result jsonb;
  v_child_id uuid;
  v_notif jsonb;
  v_ledger_count int;
begin
  v_result := public.open_notification_whatsapp('b2900000-0000-4000-8000-000000000a60'::uuid);
  v_notif := v_result -> 'notification';
  if not (v_result ? 'notification' and v_result ? 'url') then
    raise exception 'result must be exactly {notification,url}, got %', v_result;
  end if;
  if (v_notif ->> 'status') <> 'sent' then
    raise exception 'the whatsapp child must transition scheduled -> sent, got %', v_notif;
  end if;
  v_child_id := (v_notif ->> 'notificationId')::uuid;
  if (select dedupe_key from public.notifications where id = v_child_id) <> 'whatsapp:b2900000-0000-4000-8000-000000000a60' then
    raise exception 'the child dedupe_key must be whatsapp:<source id>';
  end if;
  if (select source_notification_id from public.notifications where id = v_child_id) <> 'b2900000-0000-4000-8000-000000000a60' then
    raise exception 'the child must carry source_notification_id';
  end if;
  if (v_result ->> 'url') !~ '^https://wa\.me/91' then
    raise exception 'the url must be https://wa.me/<phone without +>?text=..., got %', v_result ->> 'url';
  end if;
  select count(*) into v_ledger_count from public.messaging_wallet_ledger where notification_id = v_child_id;
  if v_ledger_count <> 0 then
    raise exception 'opening WhatsApp never charges a credit';
  end if;
end $$;
$tap$, '5: the first open creates exactly one whatsapp_link child with the exact dedupe key, source link and URL, zero credit');

select lives_ok($tap$
do $$
declare
  v_first jsonb; v_second jsonb;
  v_child_count int;
begin
  v_first := public.open_notification_whatsapp('b2900000-0000-4000-8000-000000000a60'::uuid);
  v_second := public.open_notification_whatsapp('b2900000-0000-4000-8000-000000000a60'::uuid);
  if v_first <> v_second then
    raise exception 'a repeated open while still eligible must return the identical child/url: % vs %', v_first, v_second;
  end if;
  select count(*) into v_child_count from public.notifications
    where source_notification_id = 'b2900000-0000-4000-8000-000000000a60';
  if v_child_count <> 1 then
    raise exception 'repeated opening must never create a second child, found %', v_child_count;
  end if;
end $$;
$tap$, '5: repeated opening is inert - same child, same url, no second row');

select throws_ok($tap$
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key, source_notification_id)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'whatsapp_link',
    'whatsapp:b2900000-0000-4000-8000-000000000a60', 'b2900000-0000-4000-8000-000000000a60')
$tap$, '23505'::char(5), null,
  '5: a direct second whatsapp_link child for the same source, same dedupe key, is rejected by the unique index');

select throws_ok($tap$
do $$
declare v_scheduled_id uuid;
begin
  insert into public.notifications (tenant_id, member_id, channel, dedupe_key)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app',
    'h29:notyetsent:' || gen_random_uuid()::text)
  returning id into v_scheduled_id; -- still scheduled, never sent/delivered
  perform public.open_notification_whatsapp(v_scheduled_id);
end $$;
$tap$, '5: a source that is not yet sent/delivered cannot open a WhatsApp child');

select lives_ok($tap$
do $$
declare
  v_source_id uuid;
  v_result jsonb;
  v_child_count int;
begin
  -- member A2 has no service/marketing consent recorded at all.
  set local session_replication_role = replica;
  insert into public.notifications (tenant_id, member_id, channel, status, dedupe_key, sent_at)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a11', 'in_app', 'sent',
    'h29:optedout-source:' || gen_random_uuid()::text, now())
  returning id into v_source_id;
  set local session_replication_role = origin;
  begin
    v_result := public.open_notification_whatsapp(v_source_id);
    raise exception 'a member with no current consent must never receive a whatsapp url, got %', v_result;
  exception when others then
    if sqlstate <> '42501' then
      raise exception 'expected 403 communication_opted_out (mapped to 42501/insufficient_privilege), got %', sqlstate;
    end if;
  end;
  select count(*) into v_child_count from public.notifications where source_notification_id = v_source_id;
  if v_child_count <> 0 then
    raise exception 'a refused open must create no child row';
  end if;
end $$;
$tap$, '5: refused current consent gives 403 communication_opted_out and creates no child, no url is exposed');

select throws_ok($tap$
do $$
declare
  v_source_id uuid;
  v_child_id uuid;
begin
  set local session_replication_role = replica;
  insert into public.notifications (tenant_id, member_id, channel, status, dedupe_key, sent_at, recipient_phone)
  values ('b2900000-0000-4000-8000-000000000a00', 'b2900000-0000-4000-8000-000000000a10', 'in_app', 'sent',
    'h29:phonecheck:' || gen_random_uuid()::text, now(), '+919000000001')
  returning id into v_source_id;
  set local session_replication_role = origin;
  perform public.open_notification_whatsapp(v_source_id);
  update public.members set phone = '+919000099999' where id = 'b2900000-0000-4000-8000-000000000a10';
  perform public.open_notification_whatsapp(v_source_id); -- phone now differs from the frozen snapshot
end $$;
$tap$, 'GL066'::char(5), null,
  '5: a member phone that now differs from the child''s frozen recipient snapshot refuses with GL066, never rewrites it');

set local role postgres;
update public.members set phone = '+919000000001' where id = 'b2900000-0000-4000-8000-000000000a10';

-- ===========================================================================
-- PART 10 — §6 app.membership_renewal_remainder.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a03',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a03', 'app_role', 'front_desk')::text, true);
set local role authenticated;

select lives_ok($tap$
do $$
declare
  v_result jsonb;
begin
  -- A30: price 100000, discount 0, periodsGranted 1, one paid receipt of 100000.
  -- A=100000, T=100000, R=T-1*A=0, due=greatest(0,A-0)=100000.
  v_result := app.membership_renewal_remainder('b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a30'::uuid);
  if (v_result ->> 'netPricePaise') <> '100000' or (v_result ->> 'residualPaise') <> '0'
      or (v_result ->> 'duePaise') <> '100000' then
    raise exception 'exact remainder formula mismatch for a fully-paid single period: %', v_result;
  end if;
end $$;
$tap$, '6: A=price-discount, T=receipts, R=T-periodsGranted*A, due=greatest(0,A-R) is exact for a fully-paid period');

select lives_ok($tap$
do $$
declare
  v_result jsonb;
begin
  -- A34: price 0 (complimentary) -> due is 0 regardless of R.
  v_result := app.membership_renewal_remainder('b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a34'::uuid);
  if (v_result ->> 'duePaise') <> '0' then
    raise exception 'a zero net price must give zero due, got %', v_result;
  end if;
end $$;
$tap$, '6: A=0 (complimentary) gives due=0 by the explicit CASE, never a divide or a nonzero grant');

select lives_ok($tap$
do $$
declare
  v_result jsonb;
begin
  -- A32/A41: price 9007199254740993 (2^53+1), one paid receipt of the same
  -- amount, periodsGranted 1 -> R=0, due=9007199254740993 exactly, beyond
  -- Number.MAX_SAFE_INTEGER (9007199254740991) and must survive as text.
  v_result := app.membership_renewal_remainder('b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a32'::uuid);
  if (v_result ->> 'duePaise') <> '9007199254740993' or (v_result ->> 'eligiblePaidPaise') <> '9007199254740993' then
    raise exception 'large value beyond JS safe integer must be exact decimal text, got %', v_result;
  end if;
  if jsonb_typeof(v_result -> 'duePaise') <> 'string' then
    raise exception 'duePaise must be a JSON string, never a JS number, got type %', jsonb_typeof(v_result -> 'duePaise');
  end if;
end $$;
$tap$, '6: a remainder beyond Number.MAX_SAFE_INTEGER is exact decimal text, not a JSON number');

select lives_ok($tap$
do $$
declare
  v_result jsonb;
begin
  v_result := app.membership_renewal_remainder('b2900000-0000-4000-8000-000000000a00'::uuid, gen_random_uuid());
  if v_result is not null then
    raise exception 'a missing/unreadable membership must return SQL NULL, got %', v_result;
  end if;
end $$;
$tap$, '6: a missing membership id returns SQL NULL, not an error or a fabricated zero');

select lives_ok($tap$
do $$
declare
  v_result jsonb;
  v_receipts jsonb;
begin
  v_result := app.membership_renewal_remainder('b2900000-0000-4000-8000-000000000a00'::uuid, 'b2900000-0000-4000-8000-000000000a30'::uuid);
  v_receipts := v_result -> 'receipts';
  if jsonb_array_length(v_receipts) <> 1 or (v_receipts -> 0 ->> 'paymentId') <> 'b2900000-0000-4000-8000-000000000a40' then
    raise exception 'receipts must be the id-sorted {paymentId,amountPaise} rows that fed the sum, got %', v_receipts;
  end if;
end $$;
$tap$, '6: receipts are the exact id-sorted {paymentId,amountPaise} rows behind eligiblePaidPaise');

set local role postgres;

-- ===========================================================================
-- PART 11 — §6 app.default_renewal_reminder_windows and the settings CHECK.
-- ===========================================================================

select lives_ok($tap$
do $$
declare
  v_rows record;
  v_expected jsonb := '[{"id":"expiry_minus_14","days":-14},{"id":"expiry_minus_7","days":-7},
    {"id":"expiry_minus_3","days":-3},{"id":"expiry_day","days":0},{"id":"expiry_plus_3","days":3}]'::jsonb;
  v_i int := 0;
  v_actual jsonb := '[]'::jsonb;
begin
  for v_rows in select * from app.default_renewal_reminder_windows() order by days_from_expiry loop
    v_actual := v_actual || jsonb_build_object('id', v_rows.window_id, 'days', v_rows.days_from_expiry);
  end loop;
  if v_actual <> v_expected then
    raise exception 'default windows must be exactly RENEWAL_REMINDER_WINDOWS, generated: % vs contract %', v_actual, v_expected;
  end if;
end $$;
$tap$, '6: app.default_renewal_reminder_windows() is generated from RENEWAL_REMINDER_WINDOWS exactly, in order');

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;
select throws_ok($tap$
  update public.organization_settings set renewal_reminder_days_from_expiry = array[3,3,-7]::smallint[]
  where tenant_id = 'b2900000-0000-4000-8000-000000000a00'
$tap$, '23514'::char(5), null,
  '6: a malformed (duplicated, unsorted) custom offset array fails the settings CHECK');
select lives_ok($tap$
  update public.organization_settings set renewal_reminder_days_from_expiry = array[]::smallint[]
  where tenant_id = 'b2900000-0000-4000-8000-000000000a00'
$tap$, '6: an explicit empty offset array is a valid setting - it disables reminders, it is not malformed');
select lives_ok($tap$
  update public.organization_settings set renewal_reminder_days_from_expiry = null
  where tenant_id = 'b2900000-0000-4000-8000-000000000a00'
$tap$, '6: null restores the platform-default windows');

set local role postgres;

-- ===========================================================================
-- PART 12 — §6 app.run_renewal_reminders / public.run_renewal_reminders_all.
-- ===========================================================================

select lives_ok($tap$
do $$
declare
  v_result jsonb;
  v_notif_id uuid;
begin
  v_result := app.run_renewal_reminders('b2900000-0000-4000-8000-000000000a00'::uuid);
  if (v_result ->> 'createdCount')::int < 1 or (v_result ->> 'sentCount')::int < 1 then
    raise exception 'membership A30 (expiry_plus_3, consented member A1, positive due) must produce a created+sent row: %', v_result;
  end if;
  if not exists (select 1 from public.notifications
      where dedupe_key = 'renewal:b2900000-0000-4000-8000-000000000a30:' || to_char(current_date - 3, 'YYYY-MM-DD') || ':expiry_plus_3') then
    raise exception 'the dedupe key must be exactly renewal:<membership uuid>:<ends_on>:<window_id>';
  end if;
end $$;
$tap$, '6: an eligible membership/window/consent produces exactly the contract dedupe key, created then sent in one transaction');

select lives_ok($tap$
do $$
declare
  v_before int; v_after int; v_result jsonb;
begin
  select count(*) into v_before from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a30';
  v_result := app.run_renewal_reminders('b2900000-0000-4000-8000-000000000a00'::uuid);
  select count(*) into v_after from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a30';
  if v_after <> v_before then
    raise exception 'a same-day rerun on an existing key must be inert, row count changed % -> %', v_before, v_after;
  end if;
  if (v_result ->> 'createdCount')::int <> 0 then
    raise exception 'a rerun must report zero new createdCount for the already-keyed cycle, got %', v_result;
  end if;
end $$;
$tap$, '6: rerunning the same gym/day is inert - the existing key stands, no duplicate row, zero new counts');

select lives_ok($tap$
do $$
declare
  v_created int;
begin
  select count(*) into v_created from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a31';
  perform app.run_renewal_reminders('b2900000-0000-4000-8000-000000000a00'::uuid);
  -- member A2 has no service consent at all -> must remain skipped.
  if exists (select 1 from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a31') then
    raise exception 'a membership with no recorded service consent must never get a reminder';
  end if;
end $$;
$tap$, '6: absent service consent skips the cycle - no notification, no key consumed');

select lives_ok($tap$
do $$
begin
  if exists (select 1 from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a33') then
    raise exception 'a cancelled membership sitting in an otherwise-matching window must never get a reminder';
  end if;
end $$;
$tap$, '6: a cancelled membership is excluded even when its ends_on matches a configured offset');

select lives_ok($tap$
do $$
begin
  if exists (select 1 from public.notifications where related_id = 'b2900000-0000-4000-8000-000000000a34') then
    raise exception 'a zero-due membership must never get a reminder';
  end if;
end $$;
$tap$, '6: zero due skips the cycle');

select throws_ok($tap$
  select app.run_renewal_reminders('b2900000-0000-4000-8000-000000000a00'::uuid)
$tap$, '42501'::char(5), null,
  '6: app.run_renewal_reminders is service_role/owner only, an authenticated gym_owner is refused');

set local role postgres;

select lives_ok($tap$
do $$
begin
  if exists (select 1 from public.notifications n
      join public.memberships m on m.id = n.related_id
      where m.tenant_id = 'b2900000-0000-4000-8000-000000000c00') then
    raise exception 'a suspended gym must produce no notification at all';
  end if;
  perform public.run_renewal_reminders_all();
  if exists (select 1 from public.notifications n
      join public.memberships m on m.id = n.related_id
      where m.tenant_id = 'b2900000-0000-4000-8000-000000000c00') then
    raise exception 'run_renewal_reminders_all must still create nothing for the suspended gym C';
  end if;
end $$;
$tap$, '6: an ineligible (suspended) gym creates no notification, from either the per-gym or the all-gym entry point');

select lives_ok($tap$
do $$
declare
  v_result jsonb;
  v_runs jsonb;
  v_last text := '';
  v_run jsonb;
begin
  v_result := public.run_renewal_reminders_all();
  if not (v_result ? 'runs') then
    raise exception 'run_renewal_reminders_all must return exactly {runs:[RunResult...]}, got %', v_result;
  end if;
  v_runs := v_result -> 'runs';
  for v_run in select * from jsonb_array_elements(v_runs) loop
    if not (v_run ? 'tenantId' and v_run ? 'localDate' and v_run ? 'timezone' and v_run ? 'evaluatedAt'
        and v_run ? 'createdCount' and v_run ? 'sentCount' and v_run ? 'optedOutCount') then
      raise exception 'each RunResult must carry exactly the contract keys, got %', v_run;
    end if;
    if (v_run ->> 'tenantId') < v_last then
      raise exception 'runs must visit tenant ids in ascending order';
    end if;
    v_last := v_run ->> 'tenantId';
  end loop;
end $$;
$tap$, '6: run_renewal_reminders_all returns {runs:[...]} in exact RunResult shape, tenant ids ascending');

-- ===========================================================================
-- PART 13 — §7 wallet: public.adjust_messaging_wallet / app.record_wallet_movement.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000a02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'staff_id', 'b2900000-0000-4000-8000-000000000a02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 10, 'holdout topup', gen_random_uuid())
$tap$, '42501'::char(5), null,
  '7: adjust_messaging_wallet requires super_admin, a gym_owner is refused');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-0000000000f1',
    'role', 'authenticated', 'app_role', 'super_admin', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 10, 'holdout topup', gen_random_uuid())
$tap$, '7: a super_admin claim carrying a gym tenant_id (an impersonated/gym-scoped shape) is refused - no gym/staff/member identity is permitted');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-0000000000f1',
    'role', 'authenticated', 'app_role', 'super_admin')::text, true);
set local role authenticated;

select throws_ok($tap$
  select public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 0, 'holdout zero', gen_random_uuid())
$tap$, '23514'::char(5), null,
  '7: a zero delta is refused (invalid_adjustment)');
select throws_ok($tap$
  select public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 10, '', gen_random_uuid())
$tap$, '23514'::char(5), null,
  '7: a blank reason is refused (invalid_adjustment)');
select throws_ok($tap$
  select public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000c00'::uuid, -5000000, 'holdout ceiling', gen_random_uuid())
$tap$, 'GL067'::char(5), null,
  '7: a delta that would drive the wallet below zero is GL067');

select lives_ok($tap$
do $$
declare
  v_key uuid := gen_random_uuid();
  v_first jsonb; v_replay jsonb;
  v_balance_before bigint;
begin
  v_first := public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 25, 'holdout replay topup', v_key);
  v_balance_before := (v_first ->> 'balanceAfterCredits')::bigint;
  -- Move the balance again so a naive replay could disagree with current state.
  perform public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 5, 'holdout second move', gen_random_uuid());
  v_replay := public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 25, 'holdout replay topup', v_key);
  if v_replay <> v_first or (v_replay ->> 'balanceAfterCredits')::bigint <> v_balance_before then
    raise exception 'exact replay must return the ORIGINAL immutable entry even after the balance moved again: % vs %', v_first, v_replay;
  end if;
end $$;
$tap$, '7: an exact replay returns the original immutable ledger entry, even if the current balance has since changed');

select throws_ok($tap$
do $$
declare v_key uuid := gen_random_uuid();
begin
  perform public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 25, 'holdout conflict a', v_key);
  perform public.adjust_messaging_wallet('b2900000-0000-4000-8000-000000000a00'::uuid, 30, 'holdout conflict b', v_key);
end $$;
$tap$, 'GL068'::char(5), null,
  '7: the same request key with a different delta/reason is GL068');

select throws_ok($tap$
  select public.adjust_messaging_wallet(gen_random_uuid(), 5, 'holdout no wallet', gen_random_uuid())
$tap$, '7: a target tenant with no wallet row at all is refused');

set local role postgres;
select throws_ok($tap$
  insert into public.messaging_wallet_ledger (tenant_id, delta_credits, reason, balance_after_credits)
  values ('b2900000-0000-4000-8000-000000000a00', 5, 'holdout direct forge', 999999)
$tap$, '42501'::char(5), null,
  '7: authenticated/service_role cannot directly insert a ledger row carrying a forged balance_after_credits');

-- ===========================================================================
-- PART 14 — §8 exact audit shapes.
-- ===========================================================================

select lives_ok($tap$
do $$
declare
  v_row record;
begin
  select before, after, reason into v_row from public.audit_log
    where action = 'messaging_wallet.adjusted' and tenant_id = 'b2900000-0000-4000-8000-000000000a00'
    order by occurred_at desc limit 1;
  if v_row.after is null or not (v_row.after ? 'balance_credits' and v_row.after ? 'ledger_id'
      and v_row.after ? 'delta_credits' and v_row.after ? 'notification_id' and v_row.after ? 'request_key'
      and v_row.after ? 'recorded_by_user_id') then
    raise exception 'messaging_wallet.adjusted audit "after" must be exactly W, got %', v_row.after;
  end if;
  if v_row.before is null or not (v_row.before ? 'balance_credits') or (v_row.before - 'balance_credits') <> '{}'::jsonb then
    raise exception 'messaging_wallet.adjusted audit "before" must be exactly {balance_credits}, got %', v_row.before;
  end if;
end $$;
$tap$, '8: messaging_wallet.adjusted audit before/after are exactly the contract shapes');

select lives_ok($tap$
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.audit_log
    where action = 'messaging_wallet.adjusted' and record_id::text = 'b2900000-0000-4000-8000-000000000a00';
  if v_count < 1 then
    raise exception 'one wallet movement must have exactly one wallet audit event, found %', v_count;
  end if;
end $$;
$tap$, '8: one wallet movement produces one wallet audit event, not separate balance/ledger duplicates');

select lives_ok($tap$
do $$
declare
  v_row record;
begin
  select after into v_row from public.audit_log
    where action = 'notification.sent' and record_id = 'b2900000-0000-4000-8000-000000000a60'
    order by occurred_at desc limit 1;
  if v_row.after is not null and (v_row.after ? 'payload' or v_row.after ? 'recipient_phone' or v_row.after ? 'updated_at') then
    raise exception 'notification audit "after" must exclude message body/payload, phone and updated_at, got %', v_row.after;
  end if;
end $$;
$tap$, '8: notification audit N excludes message body/payload, phone and automatic updated_at');

select lives_ok($tap$
do $$
declare
  v_row record;
begin
  select before, after into v_row from public.audit_log
    where action = 'consent.recorded' and tenant_id = 'b2900000-0000-4000-8000-000000000a00'
    order by occurred_at desc limit 1;
  if v_row.before is not null then
    raise exception 'consent.recorded before must be NULL, got %', v_row.before;
  end if;
  if v_row.after is null or not (v_row.after ? 'member_id' and v_row.after ? 'purpose' and v_row.after ? 'granted'
      and v_row.after ? 'version' and v_row.after ? 'source' and v_row.after ? 'recorded_at'
      and v_row.after ? 'recorded_by_staff_id' and v_row.after ? 'request_key') then
    raise exception 'consent.recorded after must carry exactly the contract fields, got %', v_row.after;
  end if;
end $$;
$tap$, '8: consent.recorded audit is NULL -> the exact contract fact set, request_key included');

-- ===========================================================================
-- PART 15 — cross-tenant invisibility and impersonation refusal roundup.
-- ===========================================================================

select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-000000000b02',
    'role', 'authenticated', 'tenant_id', 'b2900000-0000-4000-8000-000000000b00',
    'staff_id', 'b2900000-0000-4000-8000-000000000b02', 'app_role', 'gym_owner')::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.send_notification('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, 'P0002'::char(5), null,
  '1: gym B cannot reach gym A''s notification id through send_notification - P0002, not a leak');
select throws_ok($tap$
  select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'v1', 'holdout cross', gen_random_uuid())
$tap$, 'P0002'::char(5), null,
  '1: gym B''s front office cannot record consent for gym A''s member - P0002');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', 'b2900000-0000-4000-8000-0000000000f1',
    'role', 'authenticated', 'app_role', 'gym_owner', 'tenant_id', 'b2900000-0000-4000-8000-000000000a00',
    'impersonation_session_id', gen_random_uuid())::text, true);
set local role authenticated;
select throws_ok($tap$
  select public.send_notification('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, '1: an impersonation claim on send_notification is refused (every private write helper rejects impersonation)');
select throws_ok($tap$
  select public.open_notification_whatsapp('b2900000-0000-4000-8000-000000000a60'::uuid)
$tap$, '1: an impersonation claim on open_notification_whatsapp is refused');
select throws_ok($tap$
  select public.record_consent('b2900000-0000-4000-8000-000000000a10'::uuid, 'marketing'::public.consent_purpose,
    true, 'v1', 'holdout impersonation', gen_random_uuid())
$tap$, '1: an impersonation claim on record_consent is refused');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();

rollback;
