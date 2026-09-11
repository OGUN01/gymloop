-- 31_comms_schema_consent.sql — Phase 6 communications/wallet, visible suite 1 of 3:
-- the migration's schema shape (message_category, new columns, new indexes,
-- composite FKs) and the visible behavior of the v1 invariants around consent
-- and notification identity.
--
-- Derived only from docs/planning/phase6-comms-contract.md (§1 shared boundaries,
-- §2 schema and indexes, §3 consent) plus the existing comms migration
-- (supabase/migrations/20260906115159_comms.sql). The Phase 6 comms migration
-- (20260915100007_phase6_comms.sql), any implementation and
-- supabase/tests-holdout/ were not read, so this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * "New/activated templates require a category, trimmed nonempty key/body and
--   existing supported locale" is enforced natively (a NOT VALID CHECK added to
--   the existing table), so a NEW insert without a category, with a blank/whitespace
--   key or with a locale outside en/hi fails with the native 23514 — not GL066.
--   GL066's "unclassified new message" slot is reserved for the notifications
--   invariant (asserted in 33_comms_commands.sql), which the contract names for
--   messages, not templates.
-- * "request_key uuid NULL for historical/direct entries" — the column is
--   nullable and a trusted direct insert MAY carry a null request_key (history
--   loading must stay possible); the requirement "product commands require it"
--   is pinned on public.record_consent in 32_comms_consent_serialization.sql.
--   What the schema pins here is only the unique (tenant_id, request_key)
--   partial index and its 23505 replay refusal.
-- * "New product rows require a category and nonnull dedupe key" is the
--   notification invariant's job (GL066, file 33). This file pins only the
--   columns/indexes/FKs themselves, the recipient_phone E.164 CHECK, the
--   ledger's balance CHECK, and that source/child member identity is
--   tenant-composite (the child FK is same-tenant, so a cross-gym member id is
--   refused natively).
-- * Index names are not frozen by the contract, so every index assertion
--   matches on definition (columns, uniqueness, predicate) rather than on a
--   guessed name — except the one index the contract names for REPLACEMENT:
--   consents_member_id_purpose_recorded_at_idx must be GONE after the
--   migration replaces it with (member_id, purpose, recorded_at DESC, id DESC).
-- * The IronBox baseline (4500/4500, no opening entry) is seed data asserted by
--   the seed; the migration's pre-check is not re-run here — this suite creates
--   no wallet rows at all.
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenant.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(64);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 3a000000 is this file's alone; no other suite or the seed
-- uses it. The org is created with one member who has NO consents and NO
-- notifications: schema assertions must hold on an empty cluster.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,currency) values
 ('3a000000-0000-4000-8000-000000000001','Comms Consent Schema','CCS31A','active','Asia/Kolkata','INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('3a000000-0000-4000-8000-000000000011','3a000000-0000-4000-8000-000000000001','Main',true);
-- Claims below identify real staff with matching authenticated subjects.
insert into auth.users(id) values ('3a000000-0000-4000-8000-000000000901'),('3a000000-0000-4000-8000-000000000902');
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
 ('3a000000-0000-4000-8000-000000000021','3a000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000901','3a000000-0000-4000-8000-000000000011','gym_owner','Owner'),
 ('3a000000-0000-4000-8000-000000000023','3a000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000902','3a000000-0000-4000-8000-000000000011','front_desk','Desk');
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('3a000000-0000-4000-8000-000000000031','3a000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000011','Member A','+915300000031','active'),
 ('3a000000-0000-4000-8000-000000000032','3a000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000011','Member B','+915300000032','active');

-- A historical template with no category: history must stay readable, which is
-- exactly why the new category column is nullable and its CHECK is NOT VALID.
insert into public.message_templates(id,tenant_id,key,channel,locale,body) values
 ('3a000000-0000-4000-8000-000000000101','3a000000-0000-4000-8000-000000000001','winback_absent','push','en','We have missed you');

-- A source notification the child-index assertions hang off. Inserted as the
-- owner under RLS-off — it is a plain historical-shape row (no category yet,
-- null dedupe key is not needed here).
insert into public.notifications(id,tenant_id,member_id,channel,status,dedupe_key,scheduled_for,sent_at) values
 ('3a000000-0000-4000-8000-000000000201','3a000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000031','in_app','sent','31-source:legacy',transaction_timestamp(),transaction_timestamp());

-- ---------------------------------------------------------------------------
-- 1. message_category: one new enum, labels in the contract order
-- ---------------------------------------------------------------------------

select has_enum('public','message_category',
  'COM: message_category is a Postgres enum (ADR-021 — canonical vocabularies are enums)');
select enum_has_labels('public','message_category',
  array['renewal','payment','fulfilment','promotion','motivation']::name[],
  'COM: message_category labels in the contract order — the order is what gen types emits');

-- ---------------------------------------------------------------------------
-- 2. message_templates: category column, and the new/activated rules
-- ---------------------------------------------------------------------------

select has_column('public','message_templates','category',
  'COM: message_templates gains category');
select col_type_is('public','message_templates','category','message_category',
  'COM: message_templates.category comes from the closed classification vocabulary');
select col_is_null('public','message_templates','category',
  'COM: message_templates.category is NULL for historical rows — no fabricated classification');
select ok((select count(*) from public.message_templates where category is null) >= 1,
  'COM: the inserted historical template row remains readable with a NULL category');
select ok(
  (select exists(
     select 1 from pg_constraint c
      where c.conrelid = 'public.message_templates'::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.message_templates'::regclass
        and (select array_agg(a.attname order by x.ord)
               from unnest(c.conkey) with ordinality x(attnum,ord)
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum)
             = array['tenant_id','id']
        and (select array_agg(fa.attname order by x.ord)
               from unnest(c.confkey) with ordinality x(attnum,ord)
               join pg_attribute fa on fa.attrelid = c.confrelid and fa.attnum = x.attnum)
             = array['tenant_id','id'])),
  'COM: message_templates carries a composite unique (tenant_id, id) backing the new notification FK');

select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, body)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, 'no_category', 'push', 'en', 'Body') $q$,
  '23514'::text, null::text,
  'COM: a NEW template without a category is rejected — classification is required from day one');
select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, category, body)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, '  ', 'push', 'en', 'promotion', 'Body') $q$,
  '23514'::text, null::text,
  'COM: a blank template key is rejected — keys are trimmed nonempty');
select throws_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, category, body)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, 'unsupported_locale', 'push', 'en-IN', 'promotion', 'Body') $q$,
  '23514'::text, null::text,
  'COM: a locale outside (en, hi) is rejected for new templates');
select lives_ok(
  $q$ insert into public.message_templates (tenant_id, key, channel, locale, category, body)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, 'payment_receipt', 'in_app', 'hi', 'payment', 'भुगतान प्राप्त हुआ') $q$,
  'COM: a complete new template with a supported locale and category is accepted');

-- ---------------------------------------------------------------------------
-- 3. consents: request_key, its tenant-scoped unique index, and the replaced
--    current-state index
-- ---------------------------------------------------------------------------

select has_column('public','consents','request_key',
  'COM: consents gains request_key');
select col_type_is('public','consents','request_key','uuid',
  'COM: consents.request_key is a UUID — all request keys are UUIDs, normalized by PostgreSQL UUID parsing');
select col_is_null('public','consents','request_key',
  'COM: consents.request_key is NULL for historical/direct entries — history is not rewritten');

select ok(
  (select i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%(tenant_id, request_key)%'
     and pg_get_expr(i.indpred, i.indrelid) = '(request_key IS NOT NULL)'
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where c.relname like 'consents%request_key%'
     and c.relnamespace = 'public'::regnamespace),
  'COM: consents (tenant_id, request_key) is unique and partial — null history keys stay unconstrained');

select ok(
  (select exists(
     select 1 from pg_index i
     join pg_class c on c.oid = i.indexrelid
    where c.relnamespace = 'public'::regnamespace
      and i.indisunique = false
      and pg_get_indexdef(i.indexrelid) like '%(member_id, purpose, recorded_at DESC, id DESC)%'
      and c.relname like 'consents%')),
  'COM: the consent current-state index is (member_id, purpose, recorded_at DESC, id DESC) — the id breaks historical ties only');
select ok(
  (select not exists(select 1 from pg_class c where c.oid = 'consents_member_id_purpose_recorded_at_idx'::regclass)),
  'COM: the old consents_member_id_purpose_recorded_at_idx index is gone, replaced — not merely supplemented');

select throws_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, request_key, recorded_at, recorded_by_staff_id)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
              'marketing', true, 'v1', 'front_desk_signup', '3a000000-0000-4000-8000-000000000401'::uuid,
              transaction_timestamp(), '3a000000-0000-4000-8000-000000000023'::uuid),
             ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
              'marketing', false, 'v2', 'member_app', '3a000000-0000-4000-8000-000000000401'::uuid,
              transaction_timestamp(), '3a000000-0000-4000-8000-000000000023'::uuid) $q$,
  '23505'::text, null::text,
  'COM: a second consent decision with the same (tenant, request_key) is rejected — the key binds one decision');

select lives_ok(
  $q$ insert into public.consents (tenant_id, member_id, purpose, granted, version, source, recorded_at)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
              'service', true, 'v1', 'signup_form', transaction_timestamp() - interval '400 days') $q$,
  'COM: a trusted historical consent row with a NULL request_key and NULL actor is still accepted — history stays loadable');

-- ---------------------------------------------------------------------------
-- 4. notifications: identity, evidence and phone columns
-- ---------------------------------------------------------------------------

select has_column('public','notifications','template_id',
  'COM: notifications gains template_id');
select col_type_is('public','notifications','template_id','uuid',
  'COM: notifications.template_id is uuid, snapshotting the template at scheduling');
select col_is_null('public','notifications','template_id',
  'COM: notifications.template_id is NULL for history and for reserved renewal rows');
select has_column('public','notifications','category',
  'COM: notifications gains category');
select col_type_is('public','notifications','category','message_category',
  'COM: notifications.category comes from the same closed classification vocabulary');
select col_is_null('public','notifications','category',
  'COM: notifications.category is NULL for history — old rows stay readable, just unsendable');
select has_column('public','notifications','source_notification_id');
select col_is_null('public','notifications','source_notification_id',
  'COM: notifications.source_notification_id is NULL on base rows');
select has_column('public','notifications','recipient_phone');
select col_type_is('public','notifications','recipient_phone','text',
  'COM: notifications.recipient_phone is text carrying the E.164 snapshot');
select col_is_null('public','notifications','recipient_phone',
  'COM: notifications.recipient_phone is NULL until a WhatsApp child snapshots it');
select has_column('public','notifications','failed_at');
select col_type_is('public','notifications','failed_at','timestamptz',
  'COM: notifications.failed_at is timestamptz evidence');
select has_column('public','notifications','opted_out_at');
select col_type_is('public','notifications','opted_out_at','timestamptz',
  'COM: notifications.opted_out_at is timestamptz evidence');
select has_column('public','notifications','opted_out_reason',
  'COM: notifications gains opted_out_reason evidence');

select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel, status, recipient_phone)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
              'whatsapp_link', 'scheduled', '1234567890') $q$,
  '23514'::text, null::text,
  'COM: a non-E.164 recipient_phone is rejected — the snapshot carries the member format CHECK');

-- Composite tenant FKs (ADR-052 shape): notifications → templates, self → notifications.
select ok(
  (select exists(
     select 1 from pg_constraint c
      where c.conrelid = 'public.notifications'::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.message_templates'::regclass
        and (select array_agg(a.attname order by x.ord)
               from unnest(c.conkey) with ordinality x(attnum,ord)
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum)
             = array['tenant_id','template_id']
        and (select array_agg(fa.attname order by x.ord)
               from unnest(c.confkey) with ordinality x(attnum,ord)
               join pg_attribute fa on fa.attrelid = c.confrelid and fa.attnum = x.attnum)
             = array['tenant_id','id'])),
  'COM: notifications.template_id is a composite (tenant_id, template_id) FK into message_templates');
select ok(
  (select exists(
     select 1 from pg_constraint c
      where c.conrelid = 'public.notifications'::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.notifications'::regclass
        and (select array_agg(a.attname order by x.ord)
               from unnest(c.conkey) with ordinality x(attnum,ord)
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum)
             = array['tenant_id','source_notification_id']
        and (select array_agg(fa.attname order by x.ord)
               from unnest(c.confkey) with ordinality x(attnum,ord)
               join pg_attribute fa on fa.attrelid = c.confrelid and fa.attnum = x.attnum)
             = array['tenant_id','id'])),
  'COM: notifications.source_notification_id is a same-tenant self FK — a child cannot name another gym''s source');

insert into public.message_templates(id,tenant_id,key,channel,locale,category,body) values
 ('3a000000-0000-4000-8000-000000000102','3a000000-0000-4000-8000-000000000001','child_probe','whatsapp_link','en','promotion body','promotion'),
 ('3a000000-0000-4000-8000-000000000103','3a000000-0000-4000-8000-000000000002','other_gym','in_app','en','Other gym body','payment');
insert into public.members(id,tenant_id,branch_id,full_name,phone,status) values
 ('3a000000-0000-4000-8000-000000000033','3a000000-0000-4000-8000-000000000002','3a000000-0000-4000-8000-000000000011','Member C','+915300000033','active');

select throws_ok(
  $q$ insert into public.notifications (tenant_id, member_id, channel, status, template_id)
      values ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
              'in_app', 'scheduled', '3a000000-0000-4000-8000-000000000103'::uuid) $q$,
  '23503'::text, null::text,
  'COM: a notification referencing another gym''s template is refused by the composite FK');

-- New index set on notifications.
select ok(
  (select exists(
     select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
    where c.relnamespace = 'public'::regnamespace
      and pg_get_indexdef(i.indexrelid) like '%(tenant_id, template_id)%')),
  'COM: notifications has a (tenant_id, template_id) index');
select ok(
  (select exists(
     select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
    where c.relnamespace = 'public'::regnamespace
      and pg_get_indexdef(i.indexrelid) like '%(tenant_id, source_notification_id)%'
      and not i.indisunique)),
  'COM: notifications has a non-unique (tenant_id, source_notification_id) index');
select ok(
  (select i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%(tenant_id, source_notification_id)%'
     and pg_get_expr(i.indpred, i.indrelid) like '%source_notification_id IS NOT NULL%'
     and pg_get_expr(i.indpred, i.indrelid) like '%whatsapp_link%'
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relnamespace = 'public'::regnamespace
     and i.indisunique),
  'COM: the WhatsApp child index is unique and partial on source_notification_id + whatsapp_link');
select ok(
  (select exists(select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
    where c.relname = 'notifications_tenant_id_dedupe_key_key')),
  'COM: the existing notifications dedupe index is preserved — PAY-002 still stands');
select ok(
  (select exists(select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
    where c.relname = 'notifications_tenant_id_status_scheduled_for_idx')),
  'COM: the existing notifications queue index is preserved — no second queue table');

select throws_ok(
  $q$ insert into public.notifications (id, tenant_id, member_id, channel, status, category, source_notification_id, recipient_phone, dedupe_key, scheduled_for)
      values ('3a000000-0000-4000-8000-000000000202'::uuid, '3a000000-0000-4000-8000-000000000001'::uuid,
              '3a000000-0000-4000-8000-000000000031'::uuid, 'whatsapp_link', 'scheduled', 'promotion',
              '3a000000-0000-4000-8000-000000000201'::uuid, '+915300000031',
              'whatsapp:3a000000-0000-4000-8000-000000000201', transaction_timestamp()),
             ('3a000000-0000-4000-8000-000000000203'::uuid, '3a000000-0000-4000-8000-000000000001'::uuid,
              '3a000000-0000-4000-8000-000000000031'::uuid, 'whatsapp_link', 'sent', 'promotion',
              '3a000000-0000-4000-8000-000000000201'::uuid, '+915300000031',
              'whatsapp:3a000000-0000-4000-8000-000000000201', transaction_timestamp()) $q$,
  '23505'::text, null::text,
  'COM: a second whatsapp_link child for one source is rejected — opening twice reuses one child');

select throws_ok(
  $q$ insert into public.notifications (id, tenant_id, member_id, channel, status, category, source_notification_id, recipient_phone, dedupe_key)
      values ('3a000000-0000-4000-8000-000000000204'::uuid, '3a000000-0000-4000-8000-000000000001'::uuid,
              '3a000000-0000-4000-8000-000000000032'::uuid, 'whatsapp_link', 'scheduled', 'promotion',
              '3a000000-0000-4000-8000-000000000201'::uuid, '+915300000032',
              'whatsapp:3a000000-0000-4000-8000-000000000201-x') $q$,
  '23503'::text, null::text,
  'COM: a whatsapp child naming a different member than its source is refused — source and child share the member');

-- ---------------------------------------------------------------------------
-- 5. messaging_wallet_ledger: actor, key and resulting balance
-- ---------------------------------------------------------------------------

select has_column('public','messaging_wallet_ledger','request_key',
  'COM: messaging_wallet_ledger gains request_key');
select col_type_is('public','messaging_wallet_ledger','request_key','uuid',
  'COM: messaging_wallet_ledger.request_key is a UUID idempotency key');
select col_is_null('public','messaging_wallet_ledger','request_key',
  'COM: messaging_wallet_ledger.request_key is NULL on historical entries');
select has_column('public','messaging_wallet_ledger','recorded_by_user_id',
  'COM: messaging_wallet_ledger gains recorded_by_user_id');
select col_type_is('public','messaging_wallet_ledger','recorded_by_user_id','uuid',
  'COM: messaging_wallet_ledger.recorded_by_user_id is the platform actor');
select col_is_null('public','messaging_wallet_ledger','recorded_by_user_id',
  'COM: messaging_wallet_ledger.recorded_by_user_id is NULL on history and on future notification debits');
select has_column('public','messaging_wallet_ledger','balance_after_credits',
  'COM: messaging_wallet_ledger gains balance_after_credits');
select col_type_is('public','messaging_wallet_ledger','balance_after_credits','bigint',
  'COM: messaging_wallet_ledger.balance_after_credits is bigint — credits, not money');
select col_is_null('public','messaging_wallet_ledger','balance_after_credits',
  'COM: messaging_wallet_ledger.balance_after_credits is NULL on historical entries');

select ok(
  (select exists(
     select 1 from pg_constraint c
      where c.conrelid = 'public.messaging_wallet_ledger'::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.platform_users'::regclass
        and (select array_agg(a.attname order by x.ord)
               from unnest(c.conkey) with ordinality x(attnum,ord)
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum)
             = array['recorded_by_user_id'])),
  'COM: messaging_wallet_ledger.recorded_by_user_id references platform_users(user_id)');

select ok(
  (select i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%(tenant_id, notification_id)%'
     and pg_get_expr(i.indpred, i.indrelid) = '(notification_id IS NOT NULL)'
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relnamespace = 'public'::regnamespace
     and i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%notification_id%'),
  'COM: the ledger is unique per (tenant, notification) where the notification is set — one debit per message');
select ok(
  (select exists(
     select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
    where c.relnamespace = 'public'::regnamespace
      and pg_get_indexdef(i.indexrelid) like '%recorded_by_user_id%'
      and c.relname like 'messaging_wallet_ledger%')),
  'COM: the ledger carries an index on recorded_by_user_id');
select ok(
  (select exists(
     select 1 from pg_constraint c
      where c.conrelid = 'public.messaging_wallet_ledger'::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.messaging_wallets'::regclass
        and (select array_agg(a.attname order by x.ord)
               from unnest(c.conkey) with ordinality x(attnum,ord)
               join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum)
             = array['tenant_id'])),
  'COM: the ledger''s tenant FK is composite into messaging_wallets — a movement cannot target another gym''s wallet');

-- ---------------------------------------------------------------------------
-- 6. Append-only and read-only tiers survive the migration (INT-001, DPD-004,
--    ADR-047/049) — the new columns change no privilege
-- ---------------------------------------------------------------------------

select ok(not has_table_privilege('authenticated','public.consents','UPDATE'),
  'COM: authenticated still holds no UPDATE on consents — the request_key column adds no edit path');
select ok(not has_table_privilege('authenticated','public.messaging_wallet_ledger','INSERT'),
  'COM: authenticated still holds no INSERT on the ledger — the wallet stays the sum of the ledger');
select ok(has_table_privilege('authenticated','public.messaging_wallets','SELECT')
  and not has_table_privilege('authenticated','public.messaging_wallets','UPDATE'),
  'COM: messaging_wallets stays select-only for authenticated');

-- ---------------------------------------------------------------------------
-- 7. V1 consent behavior visible at the table: the claim-stamped actor
-- ---------------------------------------------------------------------------

create temp table consent_probe(state text, detail text);
grant select,insert on consent_probe to authenticated;

-- Every probe rolls back even an incorrect success, keeping later assertions
-- independent; returned SQLSTATE/DETAIL is observed behavior, never source.
create function pg_temp.captured_error(p_sql text)
returns void language plpgsql as $fn$
declare v_state text; v_detail text;
begin
  execute p_sql;
  insert into consent_probe values (null, null);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  insert into consent_probe values (v_state, v_detail);
end $fn$;
grant execute on function pg_temp.captured_error(text) to authenticated;

-- A member-role session with no staff identity: a NEW consent decision must
-- carry a real claim-stamped staff actor, so this insert is refused.
select set_config('request.jwt.claims',
  '{"sub":"3a000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"member","tenant_id":"3a000000-0000-4000-8000-000000000001","member_id":"3a000000-0000-4000-8000-000000000031"}', true);
set local role authenticated;

select ok(pg_temp.captured_error($q$
  insert into public.consents (tenant_id, member_id, purpose, granted, version, source, request_key)
  values ('3a000000-0000-4000-8000-000000000001'::uuid, '3a000000-0000-4000-8000-000000000031'::uuid,
          'marketing', true, 'v1', 'member_app', '3a000000-0000-4000-8000-000000000402'::uuid)
$q$) is not distinct from (select state from consent_probe where state is not null)
 and (select state from consent_probe order by ctid desc limit 1) is not null,
 'COM: a NEW consent row without any staff identity is refused — a claim-stamped actor is required');

set local role postgres;
select set_config('request.jwt.claims','',true);

select ok(
  (select not exists(select 1 from public.consents
    where tenant_id = '3a000000-0000-4000-8000-000000000001'::uuid
      and request_key is not null)),
  'COM: no consent row with a request key was written by the refused session');

select * from finish();

rollback;
