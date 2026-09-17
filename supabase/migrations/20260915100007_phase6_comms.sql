-- Phase 6 communications and wallet: message classification, versioned consent
-- with the microsecond serialization point, the notification lifecycle graph
-- and its narrow send/acknowledge/WhatsApp commands, the one renewal remainder
-- formula and its idempotent daily reminder stages, and messaging-wallet
-- credit movement. Frozen contract: docs/planning/phase6-comms-contract.md
-- (COM-001..009, PAY-001..003, INT-002/003, DPD-002..004, STK-004;
-- GL065..069) and docs/planning/phase6-contract-seam.md. Registry:
-- docs/registry.md, "Phase 6 comms database functions" and "Phase 6 comms
-- database triggers" (to be added by the orchestrator; see the implementation
-- report for the exact entries).
--
-- This ALTERs the existing comms tables from 20260906115159_comms.sql; it
-- creates none of them. It follows the fused-trigger-slot convention
-- 20260915100005_phase6_leads.sql and 20260915100006_phase6_member_import.sql
-- established: exactly one substantive row trigger per table, reusing the
-- universal <table>_touch_updated_at name (04_contract_meta.sql's catalogue
-- shape rule), even where -- as on `consents`, which has no updated_at column
-- at all -- the name no longer describes what the trigger does. `consents`
-- had no row trigger before this migration; `notifications` already carried a
-- plain touch_updated_at, which this migration drops and recreates as the
-- big lifecycle invariant.

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------

do $migration$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'public.consents'::regclass
       and attname = 'request_key' and not attisdropped
  ) then
    raise exception 'Phase 6 comms expects an un-migrated consents table';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger
     where tgrelid = 'public.notifications'::regclass
       and tgname = 'notifications_touch_updated_at'
  ) then
    raise exception 'Phase 6 comms expects the platform notifications touch trigger';
  end if;
end
$migration$;

-- ---------------------------------------------------------------------------
-- 1. Wallet baseline assertion (contract §2). No opening entry is created;
--    a mismatch fails the migration outright for separately justified repair.
-- ---------------------------------------------------------------------------

do $migration$
declare
  v_bad record;
begin
  for v_bad in
    select w.tenant_id, w.balance_credits,
           coalesce((select sum(l.delta_credits) from public.messaging_wallet_ledger l
                      where l.tenant_id = w.tenant_id), 0) as ledger_sum
      from public.messaging_wallets w
  loop
    if v_bad.balance_credits <> v_bad.ledger_sum then
      raise exception 'messaging wallet % balance % does not equal its ledger sum % -- Phase 6 creates no opening entry; this needs a separately justified repair',
        v_bad.tenant_id, v_bad.balance_credits, v_bad.ledger_sum;
    end if;
  end loop;
end
$migration$;

-- ---------------------------------------------------------------------------
-- 2. Schema: message_category, and the new columns/indexes/FKs on the four
--    existing comms tables (contract §2)
-- ---------------------------------------------------------------------------

create type public.message_category as enum (
  'renewal',
  'payment',
  'fulfilment',
  'promotion',
  'motivation'
);

-- message_templates ----------------------------------------------------------

alter table public.message_templates
  add column category public.message_category;

-- The reserved system key, for every writer, unconditionally: renewal
-- reminders are never authored through gym CRUD, historical rows included.
alter table public.message_templates
  add constraint message_templates_reserved_key_chk
    check (key <> 'renewal_reminder')
  not valid;

-- New templates require a category, trimmed nonempty key/body and a supported
-- locale. NOT VALID grandfathers the historical row this migration finds with
-- no category, while enforcing this shape for every later INSERT or UPDATE.
alter table public.message_templates
  add constraint message_templates_v1_shape_chk
    check (
      category is not null
      and btrim(key) <> ''
      and btrim(body) <> ''
      and locale in ('en', 'hi')
    )
  not valid;

-- The composite unique key the new notification FK needs.
alter table public.message_templates
  add constraint message_templates_tenant_id_id_key unique (tenant_id, id);

-- consents ---------------------------------------------------------------

alter table public.consents
  add column request_key uuid;

create unique index consents_tenant_id_request_key_key
  on public.consents (tenant_id, request_key)
  where request_key is not null;

-- Replaces, not supplements: the contract names this exact index shape as
-- the new current-state index, with id breaking historical ties only.
drop index public.consents_member_id_purpose_recorded_at_idx;

create index consents_member_id_purpose_recorded_at_id_idx
  on public.consents (member_id, purpose, recorded_at desc, id desc);

-- notifications ------------------------------------------------------------

alter table public.notifications
  add column template_id uuid,
  add column category public.message_category,
  add column source_notification_id uuid,
  add column recipient_phone text,
  add column failed_at timestamptz,
  add column opted_out_at timestamptz,
  add column opted_out_reason text;

alter table public.notifications
  add constraint notifications_recipient_phone_format_chk
    check (recipient_phone is null or recipient_phone ~ '^\+[1-9][0-9]{7,14}$');

-- The two new self/parent FKs need a composite (tenant_id, id) unique key on
-- the referenced side; notifications_tenant_id_id_key already exists from an
-- earlier phase (the identity/navigation preview-read-only retrofit), so
-- this migration only adds the two FKs that lean on it.
alter table public.notifications
  add constraint notifications_tenant_id_template_id_fkey
    foreign key (tenant_id, template_id) references public.message_templates (tenant_id, id);

alter table public.notifications
  add constraint notifications_tenant_id_source_notification_id_fkey
    foreign key (tenant_id, source_notification_id) references public.notifications (tenant_id, id);

-- The WhatsApp child sharing its source's member is enforced by
-- app.enforce_notification() below (raising a literal 23503), not by a third
-- FK column here -- a 3-column self-FK does not fit 04_contract_meta.sql's
-- ADR-052 exemption, which admits only the exact 2-column
-- (tenant_id, x) -> (tenant_id, id) shape.

create index notifications_tenant_id_template_id_idx
  on public.notifications (tenant_id, template_id);

create index notifications_tenant_id_source_notification_id_idx
  on public.notifications (tenant_id, source_notification_id);

create unique index notifications_tenant_id_source_notification_id_whatsapp_key
  on public.notifications (tenant_id, source_notification_id)
  where source_notification_id is not null and channel = 'whatsapp_link';

-- messaging_wallet_ledger --------------------------------------------------

alter table public.messaging_wallet_ledger
  add column request_key uuid,
  add column recorded_by_user_id uuid references public.platform_users (user_id),
  add column balance_after_credits bigint
    constraint messaging_wallet_ledger_balance_after_credits_chk
      check (balance_after_credits is null or balance_after_credits >= 0);

create unique index messaging_wallet_ledger_tenant_id_request_key_key
  on public.messaging_wallet_ledger (tenant_id, request_key)
  where request_key is not null;

create unique index messaging_wallet_ledger_tenant_id_notification_id_key
  on public.messaging_wallet_ledger (tenant_id, notification_id)
  where notification_id is not null;

create index messaging_wallet_ledger_recorded_by_user_id_idx
  on public.messaging_wallet_ledger (recorded_by_user_id);

-- Not added: a single-column tenant_id FK from messaging_wallet_ledger into
-- messaging_wallets(tenant_id). 31_comms_schema_consent.sql asks for exactly
-- that shape, but messaging_wallets has no separate `id` column (its own
-- primary key IS tenant_id, by design -- one wallet per gym), so the
-- reference cannot be the 2-column (tenant_id, x) -> (tenant_id, id) pattern
-- 04_contract_meta.sql's ADR-052 rule requires of every FK into a
-- tenant-scoped parent, and a 1-column tenant_id -> tenant_id FK is not
-- exempt. The ledger already carries tenant_id -> organizations(id); every
-- command that moves the wallet locks and re-reads it by tenant_id under
-- that same key. See the implementation report for this conflict.

-- organization_settings: the CHECK the reminder-window column has never had.
-- Finite (guaranteed for smallint), nonnull, deduplicated, ascending -- an
-- unsorted, duplicate-bearing or null-containing array is malformed. A CHECK
-- expression may not contain a subquery directly (0A000), so the dedup/sort
-- comparison is wrapped in a small immutable function the constraint calls.
create function app.smallint_array_sorted_distinct(p_offsets smallint[])
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select p_offsets is null
    or (
      array_position(p_offsets, null::smallint) is null
      and p_offsets = (
        select coalesce(array_agg(d order by d), '{}'::smallint[])
          from (select distinct unnest(p_offsets) as d) s
      )
    )
$fn$;

revoke all on function app.smallint_array_sorted_distinct(smallint[]) from public, anon;
grant execute on function app.smallint_array_sorted_distinct(smallint[]) to authenticated, service_role;

alter table public.organization_settings
  add constraint organization_settings_renewal_reminder_days_from_expiry_chk
    check (app.smallint_array_sorted_distinct(renewal_reminder_days_from_expiry))
  not valid;

-- ---------------------------------------------------------------------------
-- 3. Consent: the serialization point (contract §3)
-- ---------------------------------------------------------------------------

-- The private audit writer for consent.recorded. INVOKER callers (record_consent
-- and any trusted direct insert) cannot write audit_log themselves -- the
-- table withholds INSERT from authenticated -- so this narrow definer is the
-- only path, granted broadly enough to be called from either context.
create function app.write_consent_audit(p_row public.consents)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid;
  v_role public.app_role;
  v_impersonation uuid;
begin
  if pg_catalog.pg_trigger_depth() = 0 or app.current_impersonation_id() is not null then
    raise exception 'Consent audit writes are trigger-only and unavailable during impersonation'
      using errcode = '42501';
  end if;
  v_actor := auth.uid();
  if v_actor is not null then
    select e.enumlabel::text::public.app_role into v_role
      from pg_catalog.pg_enum e
     where e.enumtypid = 'public.app_role'::pg_catalog.regtype
       and e.enumlabel = app.current_app_role();
    v_impersonation := app.current_impersonation_id();
  end if;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    p_row.tenant_id, v_actor, v_role, v_impersonation,
    'consent.recorded', 'consent', p_row.id, null,
    jsonb_build_object(
      'member_id', p_row.member_id,
      'purpose', p_row.purpose,
      'granted', p_row.granted,
      'version', p_row.version,
      'source', p_row.source,
      'recorded_at', p_row.recorded_at,
      'recorded_by_staff_id', p_row.recorded_by_staff_id,
      'request_key', p_row.request_key
    ),
    null
  );
end
$fn$;

revoke all on function app.write_consent_audit(public.consents) from public, anon;
grant execute on function app.write_consent_audit(public.consents) to authenticated, service_role;

-- app.stamp_consent -- the BEFORE INSERT invariant covering direct table
-- inserts and public.record_consent alike. Locks the visible same-gym member,
-- then in a fresh SQL command reads the latest row for member/purpose,
-- stamping recorded_at at least one microsecond past it. The actor rule
-- (a supplied different actor is GL065; a missing one is filled from the
-- claim) applies only under RLS -- a trusted direct insert may supply an
-- honest historical actor or none -- but the monotonic stamp and the blank
-- version/source refusal apply to every writer.
create function app.stamp_consent()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_last_recorded_at timestamptz;
  v_claim_staff uuid;
begin
  if btrim(coalesce(new.version, '')) = '' or btrim(coalesce(new.source, '')) = '' then
    raise exception 'A consent decision requires a non-blank version and source'
      using errcode = 'GL065';
  end if;

  perform 1 from public.members m
   where m.tenant_id = new.tenant_id and m.id = new.member_id
   for update;
  if not found then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  if pg_catalog.row_security_active('public.consents') then
    if auth.uid() is null or app.is_front_office() is not true
       or app.current_tenant_id() is distinct from new.tenant_id
       or app.current_staff_id() is null or app.current_impersonation_id() is not null then
      raise exception 'A consent decision requires a real claim-stamped staff actor' using errcode = '42501';
    end if;
    select s.id into v_claim_staff from public.staff s where s.tenant_id = new.tenant_id
      and s.id = app.current_staff_id() and s.user_id = auth.uid()
      and s.role::text = app.current_app_role() and s.is_active;
    if v_claim_staff is null then
      raise exception 'A consent decision requires a real claim-stamped staff actor' using errcode = '42501';
    end if;
    if new.recorded_by_staff_id is null then
      new.recorded_by_staff_id := v_claim_staff;
    elsif new.recorded_by_staff_id is distinct from v_claim_staff then
      raise exception 'A consent decision names its own claim-stamped actor'
        using errcode = 'GL065';
    end if;
  end if;

  select c.recorded_at into v_last_recorded_at
    from public.consents c
   where c.tenant_id = new.tenant_id
     and c.member_id = new.member_id
     and c.purpose = new.purpose
   order by c.recorded_at desc, c.id desc
   limit 1;

  if v_last_recorded_at is null then
    new.recorded_at := clock_timestamp();
  else
    new.recorded_at := greatest(clock_timestamp(), v_last_recorded_at + interval '1 microsecond');
  end if;

  perform app.write_consent_audit(new);

  return new;
end
$fn$;

-- consents had no row trigger before this migration (the base comms
-- migration's own comment: "consents ... have none and get none"). This
-- occupies the universal <table>_touch_updated_at slot 04_contract_meta.sql
-- requires, even though the table has no updated_at column to touch.
create trigger consents_touch_updated_at
  before insert on public.consents
  for each row execute function app.stamp_consent();

revoke all on function app.stamp_consent() from public, anon, authenticated;

-- app.notification_consent_purpose -- promotion -> marketing; everything
-- else -> service. A missing category fails closed.
create function app.notification_consent_purpose(p_category public.message_category)
returns public.consent_purpose
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if p_category is null then
    raise exception 'A notification category is required to resolve consent purpose'
      using errcode = 'GL065';
  end if;
  if p_category = 'promotion'::public.message_category then
    return 'marketing'::public.consent_purpose;
  end if;
  return 'service'::public.consent_purpose;
end
$fn$;

revoke all on function app.notification_consent_purpose(public.message_category) from public, anon;
grant execute on function app.notification_consent_purpose(public.message_category)
  to authenticated, service_role;

-- public.record_consent -- SECURITY INVOKER (pinned by
-- 32_comms_consent_serialization.sql's signature assertion): consents' own
-- tenant_write RLS gate is is_front_office(), the same gate this command
-- enforces, so invoker causes no mismatch here the way send_notification's
-- does below.
create function public.record_consent(
  p_member_id uuid,
  p_purpose public.consent_purpose,
  p_granted boolean,
  p_version text,
  p_source text,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_version text;
  v_source text;
  v_existing public.consents%rowtype;
  v_id uuid;
  v_recorded_at timestamptz;
  v_actor uuid;
begin
  if auth.uid() is null or app.is_front_office() is not true
     or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  select s.id into v_staff from public.staff s where s.tenant_id = v_tenant
    and s.id = app.current_staff_id() and s.user_id = auth.uid()
    and s.role::text = app.current_app_role() and s.is_active;
  if v_staff is null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;

  -- Resolve the caller-visible target before processing command facts or a
  -- replay key.  A missing/cross-gym member must not fall through to the
  -- composite FK's implementation detail.
  perform 1 from public.members m
   where m.tenant_id = v_tenant and m.id = p_member_id;
  if not found then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  v_version := btrim(coalesce(p_version, ''));
  v_source := btrim(coalesce(p_source, ''));
  if v_version = '' or v_source = '' then
    raise exception 'A consent decision requires a non-blank version and source'
      using errcode = 'GL065';
  end if;

  if p_request_key is null then
    raise exception 'A consent decision requires its request key'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'consent:' || v_tenant::text || ':' || p_request_key::text, 0
  ));

  select c.* into v_existing
    from public.consents c
   where c.tenant_id = v_tenant
     and c.request_key = p_request_key;
  if found then
    if v_existing.member_id = p_member_id
       and v_existing.purpose = p_purpose
       and v_existing.granted = p_granted
       and v_existing.version = v_version
       and v_existing.source = v_source
       and v_existing.recorded_by_staff_id = v_staff then
      return jsonb_build_object(
        'consentId', v_existing.id,
        'memberId', v_existing.member_id,
        'purpose', v_existing.purpose,
        'granted', v_existing.granted,
        'version', v_existing.version,
        'source', v_existing.source,
        'recordedAt', v_existing.recorded_at,
        'recordedByStaffId', v_existing.recorded_by_staff_id
      );
    end if;
    raise exception 'This request key is bound to a different consent decision'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  insert into public.consents (
    tenant_id, member_id, purpose, granted, version, source, request_key
  ) values (
    v_tenant, p_member_id, p_purpose, p_granted, v_version, v_source, p_request_key
  )
  returning id, recorded_at, recorded_by_staff_id into v_id, v_recorded_at, v_actor;

  return jsonb_build_object(
    'consentId', v_id,
    'memberId', p_member_id,
    'purpose', p_purpose,
    'granted', p_granted,
    'version', v_version,
    'source', v_source,
    'recordedAt', v_recorded_at,
    'recordedByStaffId', v_actor
  );
end
$fn$;

revoke all on function public.record_consent(uuid, public.consent_purpose, boolean, text, text, uuid)
  from public, anon;
grant execute on function public.record_consent(uuid, public.consent_purpose, boolean, text, text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Lifecycle: the graph, the big invariant trigger, and send_notification
--    (contract §4)
-- ---------------------------------------------------------------------------

create function app.notification_transition_allowed(
  p_from public.notification_status,
  p_to public.notification_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case
    when p_from = p_to then true
    when p_from = 'scheduled'::public.notification_status
      then p_to in ('sent'::public.notification_status,
                    'opted_out'::public.notification_status,
                    'failed'::public.notification_status)
    when p_from = 'sent'::public.notification_status
      then p_to in ('delivered'::public.notification_status,
                    'failed'::public.notification_status)
    when p_from = 'delivered'::public.notification_status
      then p_to in ('clicked'::public.notification_status,
                    'converted'::public.notification_status)
    when p_from = 'clicked'::public.notification_status
      then p_to = 'converted'::public.notification_status
    else false
  end;
$fn$;

revoke all on function app.notification_transition_allowed(public.notification_status, public.notification_status)
  from public, anon;
grant execute on function app.notification_transition_allowed(public.notification_status, public.notification_status)
  to authenticated, service_role;

-- The exact N shape audit-log "after"/"before" object (contract §8).
create function app.notification_audit_shape(p_row public.notifications)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'member_id', p_row.member_id,
    'channel', p_row.channel,
    'category', p_row.category,
    'template_key', p_row.template_key,
    'source_notification_id', p_row.source_notification_id,
    'dedupe_key', p_row.dedupe_key,
    'status', p_row.status,
    'scheduled_for', p_row.scheduled_for,
    'sent_at', p_row.sent_at,
    'delivered_at', p_row.delivered_at,
    'clicked_at', p_row.clicked_at,
    'converted_at', p_row.converted_at,
    'failed_at', p_row.failed_at,
    'failed_reason', p_row.failed_reason,
    'opted_out_at', p_row.opted_out_at,
    'opted_out_reason', p_row.opted_out_reason,
    'related_type', p_row.related_type,
    'related_id', p_row.related_id
  );
$fn$;

revoke all on function app.notification_audit_shape(public.notifications) from public, anon;

create function app.write_notification_audit(
  p_tenant uuid,
  p_record_id uuid,
  p_action text,
  p_before jsonb,
  p_after jsonb,
  p_reason text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid;
  v_role public.app_role;
  v_impersonation uuid;
begin
  if pg_catalog.pg_trigger_depth() = 0 or app.current_impersonation_id() is not null then
    raise exception 'Notification audit writes are trigger-only and unavailable during impersonation'
      using errcode = '42501';
  end if;
  v_actor := auth.uid();
  if v_actor is not null then
    select e.enumlabel::text::public.app_role into v_role
      from pg_catalog.pg_enum e
     where e.enumtypid = 'public.app_role'::pg_catalog.regtype
       and e.enumlabel = app.current_app_role();
    v_impersonation := app.current_impersonation_id();
  end if;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    p_tenant, v_actor, v_role, v_impersonation,
    p_action, 'notification', p_record_id, p_before, p_after, p_reason
  );
end
$fn$;

revoke all on function app.write_notification_audit(uuid, uuid, text, jsonb, jsonb, text) from public, anon;
grant execute on function app.write_notification_audit(uuid, uuid, text, jsonb, jsonb, text)
  to authenticated, service_role;

-- app.enforce_notification -- the big lifecycle invariant, fused into the
-- notifications_touch_updated_at slot (INVOKER, so current_user preserves
-- the real privilege context: 'authenticated' for a direct table write,
-- 'postgres' for the two narrow definer commands below and for the trusted
-- scheduler running as service_role). It also carries the audit write for
-- every changing edge (contract §8), because audit_log withholds INSERT from
-- authenticated and this table may carry only one substantive row trigger.
create function app.enforce_notification()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_action text;
  v_source public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_remainder jsonb;
  v_expected_status public.notification_status;
  v_expected_reason text;
  v_renewal public.memberships%rowtype;
  v_offsets smallint[];
  v_offset smallint;
  v_expected_body text;
begin
  new.updated_at := statement_timestamp();

  if tg_op = 'INSERT' then
    if new.category is null or new.dedupe_key is null then
      raise exception 'A new message requires a category and dedupe key'
        using errcode = 'GL066';
    end if;
    if new.status <> 'scheduled'::public.notification_status
       or new.sent_at is not null
       or new.delivered_at is not null
       or new.clicked_at is not null
       or new.converted_at is not null
       or new.failed_at is not null
       or new.failed_reason is not null
       or new.opted_out_at is not null
       or new.opted_out_reason is not null then
      raise exception 'A new message starts scheduled with no delivery evidence'
        using errcode = 'GL066';
    end if;

    -- Renewal/membership rows are scheduler-owned and have one immutable
    -- identity; a caller cannot sidestep it by replacing only the key.
    if new.template_key = 'renewal_reminder'
       or (new.category = 'renewal'::public.message_category
           and new.related_type = 'membership'
           and new.related_id is not null) then
      if current_user = 'authenticated' then
        raise exception 'A renewal reminder is created only by the trusted scheduler'
          using errcode = '42501';
      end if;
      if new.template_key is distinct from 'renewal_reminder'
         or new.channel is distinct from 'in_app'::public.notification_channel
         or new.category is distinct from 'renewal'::public.message_category
         or new.template_id is not null
         or new.source_notification_id is not null
         or new.related_type is distinct from 'membership' then
        raise exception 'A reserved renewal identity must carry its exact structural shape'
          using errcode = 'GL066';
      end if;
      select o.* into v_org from public.organizations o where o.id = new.tenant_id;
      select ms.* into v_renewal from public.memberships ms
       where ms.tenant_id = new.tenant_id
         and ms.id = new.related_id
         and ms.member_id = new.member_id
         and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                           'frozen'::public.membership_status)
         and ms.ends_on is not null;
      v_remainder := app.membership_renewal_remainder(new.tenant_id, new.related_id);
      select os.renewal_reminder_days_from_expiry into v_offsets
        from public.organization_settings os where os.tenant_id = new.tenant_id;
      if not found then
        raise exception 'A reserved renewal reminder requires gym settings'
          using errcode = 'GL066';
      end if;
      v_offset := null;
      if v_offsets is null then
        select w.days_from_expiry into v_offset
          from app.default_renewal_reminder_windows() w
         where w.window_id = new.payload ->> 'windowId';
      else
        select d into v_offset from unnest(v_offsets) d
         where app.renewal_window_id(d) = new.payload ->> 'windowId';
      end if;
      if v_org.id is null
         or v_renewal.id is null
         or v_remainder is null
         or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
         or v_offset is null
         or (statement_timestamp() at time zone v_org.timezone)::date <> v_renewal.ends_on + v_offset
         or new.dedupe_key is distinct from ('renewal:' || lower(v_renewal.id::text) || ':'
             || to_char(v_renewal.ends_on, 'YYYY-MM-DD') || ':' || (new.payload ->> 'windowId'))
         or jsonb_typeof(new.payload) <> 'object'
         or (select count(*) from jsonb_object_keys(new.payload)) <> 7
         or new.payload ->> 'locale' is distinct from 'en'
         or new.payload ->> 'membershipId' is distinct from v_renewal.id::text
         or new.payload ->> 'cycleEndsOn' is distinct from to_char(v_renewal.ends_on, 'YYYY-MM-DD')
         or new.payload ->> 'duePaise' is distinct from v_remainder ->> 'duePaise'
         or new.payload ->> 'currency' is distinct from v_remainder ->> 'currency'
         or new.scheduled_for is distinct from statement_timestamp() then
        raise exception 'A reserved renewal reminder must match the current membership cycle'
          using errcode = 'GL066';
      end if;
      v_expected_body := 'Your membership ends on ' || to_char(v_renewal.ends_on, 'YYYY-MM-DD')
        || '. Renewal amount due: ' || (v_remainder ->> 'currency') || ' '
        || trunc((v_remainder ->> 'duePaise')::numeric / 100::numeric)::text || '.'
        || lpad(mod((v_remainder ->> 'duePaise')::numeric, 100::numeric)::text, 2, '0') || '.';
      if new.payload ->> 'body' is distinct from v_expected_body then
        raise exception 'A reserved renewal reminder must carry the exact renewal body'
          using errcode = 'GL066';
      end if;
    end if;

    if new.source_notification_id is not null then
      select s.* into v_source
        from public.notifications s
       where s.tenant_id = new.tenant_id
         and s.id = new.source_notification_id
         and s.member_id = new.member_id;
      if v_source.id is null then
        raise exception 'A notification source must belong to the same tenant and member'
          using errcode = '23503';
      end if;
    end if;

    if new.channel = 'whatsapp_link'::public.notification_channel then
      if new.source_notification_id is null then
        raise exception 'A WhatsApp message requires its in-app source'
          using errcode = 'GL066';
      end if;
      if current_user <> 'postgres' then
        raise exception 'A WhatsApp child is created only by the open command'
          using errcode = '42501';
      end if;
      if auth.uid() is null
         or app.is_front_office() is not true
         or app.current_tenant_id() is distinct from new.tenant_id
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.staff st
            where st.tenant_id = new.tenant_id
              and st.id = app.current_staff_id()
              and st.user_id = auth.uid()
              and st.role::text = app.current_app_role()
              and st.is_active
         ) then
        raise exception 'A WhatsApp child requires a real front-office session'
          using errcode = '42501';
      end if;
      if v_source.channel is distinct from 'in_app'::public.notification_channel
         or v_source.status not in ('sent'::public.notification_status, 'delivered'::public.notification_status)
         or new.category is distinct from v_source.category
         or new.related_type is distinct from v_source.related_type
         or new.related_id is distinct from v_source.related_id
         or new.payload is distinct from v_source.payload
         or new.template_id is not null
         or new.template_key is not null
         or not exists (
           select 1 from public.members m
            where m.tenant_id = new.tenant_id
              and m.id = new.member_id
              and m.phone = new.recipient_phone
         ) then
        raise exception 'A WhatsApp child must be an unchanged snapshot of its source'
          using errcode = 'GL066';
      end if;
    end if;

    perform app.write_notification_audit(
      new.tenant_id, new.id, 'notification.scheduled', null,
      app.notification_audit_shape(new), null
    );
    return new;
  end if;

  -- UPDATE. Identity/content freeze precedes graph/evidence validation.
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.member_id is distinct from old.member_id
     or new.channel is distinct from old.channel
     or new.template_id is distinct from old.template_id
     or new.template_key is distinct from old.template_key
     or new.category is distinct from old.category
     or new.source_notification_id is distinct from old.source_notification_id
     or new.recipient_phone is distinct from old.recipient_phone
     or new.dedupe_key is distinct from old.dedupe_key
     or new.scheduled_for is distinct from old.scheduled_for
     or new.related_type is distinct from old.related_type
     or new.related_id is distinct from old.related_id
     or new.payload is distinct from old.payload
     or new.created_at is distinct from old.created_at then
    raise exception 'A notification''s identity and content are frozen after creation'
      using errcode = 'GL066';
  end if;

  if (old.sent_at is not null and new.sent_at is distinct from old.sent_at)
     or (old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at)
     or (old.clicked_at is not null and new.clicked_at is distinct from old.clicked_at)
     or (old.converted_at is not null and new.converted_at is distinct from old.converted_at)
     or (old.failed_at is not null and new.failed_at is distinct from old.failed_at)
     or (old.opted_out_at is not null and new.opted_out_at is distinct from old.opted_out_at) then
    raise exception 'An existing delivery event cannot be changed'
      using errcode = 'GL066';
  end if;

  if new.status is distinct from old.status then
    if not app.notification_transition_allowed(old.status, new.status) then
      raise exception 'That status change is not an edge of the notification graph'
        using errcode = 'GL066';
    end if;

    -- An authenticated caller has no generic state setter.  The only
    -- availability transition it can produce is the same current-member,
    -- current-consent decision that send_notification makes.  This closes
    -- the direct-table path without a client-settable trust flag.
    if current_user in ('authenticated', 'service_role') then
      if old.status <> 'scheduled'::public.notification_status then
        raise exception 'Direct message writes cannot record delivery evidence'
          using errcode = '42501';
      end if;
      if old.category is null then
        if new.status <> 'failed'::public.notification_status
           or new.failed_reason is distinct from 'classification_missing' then
          raise exception 'A scheduled historical message has no classification'
            using errcode = 'GL066';
        end if;
      end if;
      if old.scheduled_for > statement_timestamp() then
        raise exception 'That message is not yet due' using errcode = 'GL066';
      end if;

      select m.* into v_member from public.members m
       where m.tenant_id = old.tenant_id and m.id = old.member_id
       for update;
      select o.* into v_org from public.organizations o where o.id = old.tenant_id;

      v_expected_status := null;
      v_expected_reason := null;
      if old.category is null then
        v_expected_status := 'failed'::public.notification_status;
        v_expected_reason := 'classification_missing';
      elsif v_member.id is null
         or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
         or v_member.erased_at is not null
         or v_org.id is null
         or not (v_org.status = 'active'::public.organization_status
                 or (v_org.status = 'trial'::public.organization_status
                     and v_org.trial_ends_at is not null
                     and v_org.trial_ends_at > statement_timestamp())) then
        v_expected_status := 'opted_out'::public.notification_status;
        v_expected_reason := 'recipient_ineligible';
      elsif old.category = 'motivation'::public.message_category
            and coalesce(v_member.motivation_push_enabled, false) is not true then
        v_expected_status := 'opted_out'::public.notification_status;
        v_expected_reason := 'motivation_disabled';
      else
        v_purpose := app.notification_consent_purpose(old.category);
        select c.granted into v_granted from public.consents c
         where c.tenant_id = old.tenant_id
           and c.member_id = old.member_id
           and c.purpose = v_purpose
         order by c.recorded_at desc, c.id desc
         limit 1;
        if coalesce(v_granted, false) is not true then
          v_expected_status := 'opted_out'::public.notification_status;
          v_expected_reason := 'consent_withdrawn';
        elsif old.category = 'renewal'::public.message_category
              and old.related_type = 'membership' and old.related_id is not null then
          v_remainder := app.membership_renewal_remainder(old.tenant_id, old.related_id);
          if v_remainder is null
             or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
             or not exists (
               select 1 from public.memberships ms
                where ms.tenant_id = old.tenant_id
                  and ms.id = old.related_id
                  and ms.member_id = old.member_id
                  and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                                    'frozen'::public.membership_status)
                  and ms.ends_on::text = old.payload ->> 'cycleEndsOn'
             ) then
            v_expected_status := 'opted_out'::public.notification_status;
            v_expected_reason := 'renewal_stopped';
          end if;
        end if;
      end if;

      if v_expected_status is null then
        if old.channel = 'in_app'::public.notification_channel then
          v_expected_status := 'sent'::public.notification_status;
        elsif old.channel = 'push'::public.notification_channel then
          v_expected_status := 'failed'::public.notification_status;
          v_expected_reason := 'provider_unconfigured';
        else
          raise exception 'That channel has no v1 send action' using errcode = 'GL066';
        end if;
      end if;
      if new.status is distinct from v_expected_status
         or (v_expected_reason is not null and
             new.failed_reason is distinct from v_expected_reason and
             new.opted_out_reason is distinct from v_expected_reason) then
        raise exception 'That direct availability decision does not match current communication facts'
          using errcode = 'GL066';
      end if;
    end if;

    if old.channel = 'in_app'::public.notification_channel
       and old.status = 'sent'::public.notification_status
       and new.status = 'delivered'::public.notification_status
    then
      if current_user <> 'postgres'
         or auth.uid() is null
         or app.current_app_role() <> 'member'
         or app.current_tenant_id() is distinct from old.tenant_id
         or app.current_member_id() is distinct from old.member_id
         or app.current_staff_id() is not null
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.members m
            where m.tenant_id = old.tenant_id and m.id = old.member_id
              and m.user_id = auth.uid()
              and m.status not in ('cancelled'::public.member_status, 'blocked'::public.member_status)
              and m.erased_at is null
         ) then
        raise exception 'Only the member''s own acknowledgement marks a message delivered'
          using errcode = '42501';
      end if;
    end if;

    if old.channel = 'whatsapp_link'::public.notification_channel
       and old.status = 'scheduled'::public.notification_status
       and new.status = 'sent'::public.notification_status
    then
      if current_user <> 'postgres'
         or auth.uid() is null
         or app.is_front_office() is not true
         or app.current_tenant_id() is distinct from old.tenant_id
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.staff st
            where st.tenant_id = old.tenant_id
              and st.id = app.current_staff_id()
              and st.user_id = auth.uid()
              and st.role::text = app.current_app_role()
              and st.is_active
         ) then
        raise exception 'Only the open command may send a WhatsApp child'
          using errcode = '42501';
      end if;
    end if;

    -- Event time is database evidence, never a caller fact.  The clock is
    -- clamped to the preceding event where that relation exists.
    if new.status = 'sent'::public.notification_status then
      new.sent_at := clock_timestamp();
    elsif new.status = 'delivered'::public.notification_status then
      new.delivered_at := greatest(clock_timestamp(), old.sent_at);
    elsif new.status = 'clicked'::public.notification_status then
      new.clicked_at := greatest(clock_timestamp(), old.delivered_at);
    elsif new.status = 'converted'::public.notification_status then
      if old.status = 'delivered'::public.notification_status and new.clicked_at is not null then
        raise exception 'A delivered message cannot add a click while converting'
          using errcode = 'GL066';
      end if;
      new.converted_at := greatest(clock_timestamp(), old.delivered_at, coalesce(old.clicked_at, old.delivered_at));
    elsif new.status = 'failed'::public.notification_status then
      new.failed_at := greatest(clock_timestamp(), coalesce(old.sent_at, '-infinity'::timestamptz));
    elsif new.status = 'opted_out'::public.notification_status then
      new.opted_out_at := clock_timestamp();
    end if;

    if new.status = 'sent'::public.notification_status and new.sent_at is null then
      raise exception 'A sent message requires its sent timestamp' using errcode = 'GL066';
    elsif new.status = 'delivered'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null) then
      raise exception 'A delivered message requires its sent and delivered timestamps'
        using errcode = 'GL066';
    elsif new.status = 'clicked'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null or new.clicked_at is null) then
      raise exception 'A clicked message requires its full evidence chain'
        using errcode = 'GL066';
    elsif new.status = 'converted'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null or new.converted_at is null) then
      raise exception 'A converted message requires its full evidence chain'
        using errcode = 'GL066';
    elsif new.status = 'failed'::public.notification_status
          and (new.failed_at is null or coalesce(btrim(new.failed_reason), '') = '') then
      raise exception 'A failed message requires its timestamp and reason'
        using errcode = 'GL066';
    elsif new.status = 'failed'::public.notification_status
          and old.status = 'scheduled'::public.notification_status
          and new.sent_at is not null then
      raise exception 'A pre-send failure cannot carry sent evidence'
        using errcode = 'GL066';
    elsif new.status = 'opted_out'::public.notification_status
          and (new.opted_out_at is null or coalesce(btrim(new.opted_out_reason), '') = '') then
      raise exception 'An opted-out message requires its timestamp and reason'
        using errcode = 'GL066';
    end if;

    if (new.status = 'sent'::public.notification_status
        and (new.delivered_at is not null or new.clicked_at is not null or new.converted_at is not null
             or new.failed_at is not null or new.failed_reason is not null
             or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'delivered'::public.notification_status
           and (new.clicked_at is not null or new.converted_at is not null
                or new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'clicked'::public.notification_status
           and (new.converted_at is not null or new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'converted'::public.notification_status
           and (new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'failed'::public.notification_status
           and (new.delivered_at is not null or new.clicked_at is not null or new.converted_at is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'opted_out'::public.notification_status
           and (new.sent_at is not null or new.delivered_at is not null or new.clicked_at is not null
                or new.converted_at is not null or new.failed_at is not null or new.failed_reason is not null)) then
      raise exception 'That notification state carries inconsistent delivery evidence'
        using errcode = 'GL066';
    end if;

    v_action := 'notification.' || new.status::text;
    perform app.write_notification_audit(
      new.tenant_id, new.id, v_action,
      app.notification_audit_shape(old), app.notification_audit_shape(new),
      case new.status
        when 'failed'::public.notification_status then new.failed_reason
        when 'opted_out'::public.notification_status then new.opted_out_reason
        else null
      end
    );
  else
    if new.sent_at is distinct from old.sent_at
       or new.delivered_at is distinct from old.delivered_at
       or new.clicked_at is distinct from old.clicked_at
       or new.converted_at is distinct from old.converted_at
       or new.failed_at is distinct from old.failed_at
       or new.failed_reason is distinct from old.failed_reason
       or new.opted_out_at is distinct from old.opted_out_at
       or new.opted_out_reason is distinct from old.opted_out_reason then
      raise exception 'A same-state write cannot add delivery evidence'
        using errcode = 'GL066';
    end if;
  end if;

  return new;
end
$fn$;

drop trigger notifications_touch_updated_at on public.notifications;

create trigger notifications_touch_updated_at
  before insert or update on public.notifications
  for each row execute function app.enforce_notification();

revoke all on function app.enforce_notification() from public, anon, authenticated;

-- The exact NotificationResult envelope, shared by every command below.
create function app.notification_result_json(p_row public.notifications)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'notificationId', p_row.id,
    'memberId', p_row.member_id,
    'channel', p_row.channel,
    'status', p_row.status,
    'sentAt', p_row.sent_at,
    'deliveredAt', p_row.delivered_at,
    'failedAt', p_row.failed_at,
    'failedReason', p_row.failed_reason,
    'optedOutAt', p_row.opted_out_at,
    'optedOutReason', p_row.opted_out_reason
  );
$fn$;

revoke all on function app.notification_result_json(public.notifications) from public, anon;
grant execute on function app.notification_result_json(public.notifications) to authenticated, service_role;

-- The staff messages workspace reads rows and status totals from one RLS-bound
-- statement.  It deliberately has no application-side tenant predicate: the
-- caller's verified session and the table policy are the isolation boundary.
create function public.list_notifications(p_channel public.notification_channel default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
begin
  if auth.uid() is null
     or app.current_tenant_id() is null
     or (app.current_impersonation_id() is null and (
       app.is_front_office() is not true
       or app.current_staff_id() is null
       or not exists (
       select 1 from public.staff s
        where s.tenant_id = app.current_tenant_id()
          and s.id = app.current_staff_id()
          and s.user_id = auth.uid()
          and s.role::text = app.current_app_role()
          and s.is_active
       )
     )) then
    raise exception 'The messages list requires a real front-office session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();

  return (
    with filtered as (
      select n.id, n.member_id, m.full_name as member_name, n.channel,
             n.category, n.status, n.scheduled_for, n.sent_at, n.delivered_at,
             n.failed_at, n.failed_reason, n.opted_out_at, n.opted_out_reason,
             n.source_notification_id
        from public.notifications n
        join public.members m on m.tenant_id = n.tenant_id and m.id = n.member_id
       where n.tenant_id = v_tenant
         and (p_channel is null or n.channel = p_channel)
    )
    select jsonb_build_object(
      'asOf', statement_timestamp(),
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', f.id, 'memberId', f.member_id, 'memberName', f.member_name,
          'channel', f.channel, 'category', f.category, 'status', f.status,
          'scheduledFor', f.scheduled_for, 'sentAt', f.sent_at,
          'deliveredAt', f.delivered_at, 'failedAt', f.failed_at,
          'failedReason', f.failed_reason, 'optedOutAt', f.opted_out_at,
          'optedOutReason', f.opted_out_reason,
          'sourceNotificationId', f.source_notification_id
        ) order by f.scheduled_for desc, f.id desc) from filtered f
      ), '[]'::jsonb),
      'statusCounts', (
        select jsonb_build_object(
          'scheduled', (count(*) filter (where f.status = 'scheduled'::public.notification_status))::text,
          'sent', (count(*) filter (where f.status = 'sent'::public.notification_status))::text,
          'delivered', (count(*) filter (where f.status = 'delivered'::public.notification_status))::text,
          'failed', (count(*) filter (where f.status = 'failed'::public.notification_status))::text,
          'opted_out', (count(*) filter (where f.status = 'opted_out'::public.notification_status))::text
        ) from filtered f
      ),
      -- Keep the bigint on the database JSON boundary. Front office gets no
      -- wallet field; a verified gym admin receives its exact decimal text
      -- in the same list snapshot.
      'walletBalanceCredits', case when app.is_gym_admin() is true then (
        select w.balance_credits::text from public.messaging_wallets w
         where w.tenant_id = v_tenant
      ) else null end
    )
  );
end
$fn$;

revoke all on function public.list_notifications(public.notification_channel) from public, anon, service_role;
grant execute on function public.list_notifications(public.notification_channel) to authenticated;

-- public.send_notification -- SECURITY INVOKER, exactly as the contract
-- states. "Requiring a real gym admin" names app.is_gym_admin() (owner or
-- manager), the same gate that already governs notifications' tenant_write
-- RLS policy (04_contract_meta.sql's matrix) -- so an invoker command needs
-- no privilege escalation: the caller's own RLS grant already covers every
-- UPDATE this function performs. The command verifies the real claim-bound
-- admin row before any target lookup rather than relying on RLS to silently
-- affect zero rows.
create function public.send_notification(p_notification_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff uuid;
  v_tenant uuid;
  v_row public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_purpose public.consent_purpose;
  v_consent_granted boolean;
  v_remainder jsonb;
begin
  if auth.uid() is null or app.is_gym_admin() is not true
     or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real gym admin session' using errcode = '42501';
  end if;
  select s.id into v_staff from public.staff s
   where s.tenant_id = app.current_tenant_id() and s.id = app.current_staff_id()
     and s.user_id = auth.uid() and s.role::text = app.current_app_role() and s.is_active;
  if v_staff is null then
    raise exception 'This action requires a real gym admin session' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();

  select n.* into v_row from public.notifications n
   where n.tenant_id = v_tenant and n.id = p_notification_id
   for update;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  if v_row.status <> 'scheduled'::public.notification_status then
    return app.notification_result_json(v_row);
  end if;

  if v_row.channel in ('sms'::public.notification_channel, 'email'::public.notification_channel) then
    raise exception 'That channel has no v1 send action' using errcode = 'GL066';
  end if;
  if v_row.channel = 'whatsapp_link'::public.notification_channel then
    raise exception 'A WhatsApp source is opened through open_notification_whatsapp'
      using errcode = 'GL066';
  end if;
  if v_row.scheduled_for > statement_timestamp() then
    raise exception 'That message is not yet due' using errcode = 'GL066';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_tenant and m.id = v_row.member_id
   for update;

  -- The target lock is held before the member lock, matching direct UPDATE
  -- in app.enforce_notification(). The locked row cannot become stale while
  -- current consent and eligibility are re-read below.

  if v_row.category is null then
    -- Historical scheduled rows predate the category enum. Once the target
    -- and member are locked, terminalize it without invoking the category
    -- consent helper; the trigger stamps failed_at as database evidence.
    update public.notifications
       set status = 'failed', failed_reason = 'classification_missing'
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
    return app.notification_result_json(v_row);
  end if;

  select o.* into v_org from public.organizations o where o.id = v_tenant;

  if v_member.id is null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null
     or v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp())) then
    update public.notifications
       set status = 'opted_out', opted_out_at = statement_timestamp(),
           opted_out_reason = 'recipient_ineligible'
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
    return app.notification_result_json(v_row);
  end if;

  if v_row.category = 'motivation'::public.message_category
     and coalesce(v_member.motivation_push_enabled, false) is not true then
    update public.notifications
       set status = 'opted_out', opted_out_at = statement_timestamp(),
           opted_out_reason = 'motivation_disabled'
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
    return app.notification_result_json(v_row);
  end if;

  v_purpose := app.notification_consent_purpose(v_row.category);
  select c.granted into v_consent_granted
    from public.consents c
   where c.tenant_id = v_tenant and c.member_id = v_member.id and c.purpose = v_purpose
   order by c.recorded_at desc, c.id desc
   limit 1;
  if coalesce(v_consent_granted, false) is not true then
    update public.notifications
       set status = 'opted_out', opted_out_at = statement_timestamp(),
           opted_out_reason = 'consent_withdrawn'
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
    return app.notification_result_json(v_row);
  end if;

  if v_row.category = 'renewal'::public.message_category
     and v_row.related_type = 'membership' and v_row.related_id is not null then
    v_remainder := app.membership_renewal_remainder(v_tenant, v_row.related_id);
    if v_remainder is null
       or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
       or not exists (
         select 1 from public.memberships ms
          where ms.tenant_id = v_tenant
            and ms.id = v_row.related_id
            and ms.member_id = v_row.member_id
            and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                              'frozen'::public.membership_status)
            and ms.ends_on::text = v_row.payload ->> 'cycleEndsOn'
       ) then
      update public.notifications
         set status = 'opted_out', opted_out_at = statement_timestamp(),
             opted_out_reason = 'renewal_stopped'
       where tenant_id = v_tenant and id = p_notification_id
       returning * into v_row;
      return app.notification_result_json(v_row);
    end if;
  end if;

  if v_row.channel = 'in_app'::public.notification_channel then
    update public.notifications
       set status = 'sent', sent_at = statement_timestamp()
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
  elsif v_row.channel = 'push'::public.notification_channel then
    update public.notifications
       set status = 'failed', failed_at = statement_timestamp(),
           failed_reason = 'provider_unconfigured'
     where tenant_id = v_tenant and id = p_notification_id
     returning * into v_row;
  else
    raise exception 'That channel has no v1 send action' using errcode = 'GL066';
  end if;

  return app.notification_result_json(v_row);
end
$fn$;

revoke all on function public.send_notification(uuid) from public, anon;
grant execute on function public.send_notification(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Narrow member and WhatsApp commands (contract §5)
-- ---------------------------------------------------------------------------

create function public.acknowledge_notification(p_notification_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_member public.members%rowtype;
  v_row public.notifications%rowtype;
begin
  if auth.uid() is null
     or app.current_app_role() <> 'member'
     or app.current_member_id() is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'Acknowledging a message requires a real member session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();

  -- Lock the target before its member. A foreign, other-channel or unknown
  -- target remains the same non-enumerating P0002 outcome.
  select n.* into v_row from public.notifications n
   where n.tenant_id = v_tenant
     and n.id = p_notification_id
   for update;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;
  if v_row.channel is distinct from 'in_app'::public.notification_channel then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_tenant
     and m.id = app.current_member_id()
     and m.user_id = auth.uid()
   for update;
  if v_member.id is null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null then
    raise exception 'Acknowledging a message requires a real member session'
      using errcode = '42501';
  end if;

  if v_row.member_id is distinct from v_member.id then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  if v_row.status = 'delivered'::public.notification_status then
    return app.notification_result_json(v_row);
  end if;
  if v_row.status <> 'sent'::public.notification_status then
    raise exception 'Only a sent message can be acknowledged' using errcode = 'GL066';
  end if;

  update public.notifications
     set status = 'delivered', delivered_at = statement_timestamp()
   where tenant_id = v_tenant and id = p_notification_id
   returning * into v_row;

  return app.notification_result_json(v_row);
end
$fn$;

revoke all on function public.acknowledge_notification(uuid) from public, anon;
grant execute on function public.acknowledge_notification(uuid) to authenticated;

-- RFC 3986 percent-encoding over the exact UTF-8 bytes, so an emoji or
-- multi-byte character in a message body encodes correctly and not just
-- ASCII. No general-purpose URL-encoder exists elsewhere in this codebase.
create function app.url_encode_component(p_text text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select coalesce(string_agg(
    case
      when b between 48 and 57 or b between 65 and 90 or b between 97 and 122
        or chr(b) in ('-', '_', '.', '~') then chr(b)
      else '%' || lpad(upper(to_hex(b)), 2, '0')
    end, '' order by ord), '')
    from (
      select ord, get_byte(convert_to(coalesce(p_text, ''), 'UTF8'), ord) as b
        from generate_series(0, octet_length(convert_to(coalesce(p_text, ''), 'UTF8')) - 1) as ord
    ) bytes;
$fn$;

revoke all on function app.url_encode_component(text) from public, anon;

create function public.open_notification_whatsapp(p_notification_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff uuid;
  v_tenant uuid;
  v_source public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_child public.notifications%rowtype;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_remainder jsonb;
  v_dedupe text;
  v_url text;
begin
  if auth.uid() is null or app.is_front_office() is not true
     or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  select s.id into v_staff from public.staff s where s.tenant_id = v_tenant
    and s.id = app.current_staff_id() and s.user_id = auth.uid()
    and s.role::text = app.current_app_role() and s.is_active;
  if v_staff is null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;

  select n.* into v_source from public.notifications n
   where n.tenant_id = v_tenant
     and n.id = p_notification_id
   for update;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;
  if v_source.channel is distinct from 'in_app'::public.notification_channel
     or v_source.status not in ('sent'::public.notification_status, 'delivered'::public.notification_status) then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  if v_source.category is null then
    raise exception 'A source message has no classification' using errcode = 'GL066';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_tenant and m.id = v_source.member_id
   for update;
  select o.* into v_org from public.organizations o where o.id = v_tenant;
  if v_member.id is null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null
     or v_member.phone is null
     or v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp())) then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  if v_source.category = 'motivation'::public.message_category
     and coalesce(v_member.motivation_push_enabled, false) is not true then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  v_purpose := app.notification_consent_purpose(v_source.category);
  select c.granted into v_granted from public.consents c
   where c.tenant_id = v_tenant and c.member_id = v_member.id and c.purpose = v_purpose
   order by c.recorded_at desc, c.id desc
   limit 1;
  if coalesce(v_granted, false) is not true then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  if v_source.category = 'renewal'::public.message_category
     and v_source.related_type = 'membership' and v_source.related_id is not null then
    v_remainder := app.membership_renewal_remainder(v_tenant, v_source.related_id);
    if v_remainder is null
       or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
       or not exists (
         select 1 from public.memberships ms
          where ms.tenant_id = v_tenant
            and ms.id = v_source.related_id
            and ms.member_id = v_source.member_id
            and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                              'frozen'::public.membership_status)
            and ms.ends_on::text = v_source.payload ->> 'cycleEndsOn'
       ) then
      return jsonb_build_object('communicationOptedOut', true);
    end if;
  end if;

  v_dedupe := 'whatsapp:' || v_source.id::text;

  select n.* into v_child from public.notifications n
   where n.tenant_id = v_tenant
     and n.source_notification_id = v_source.id
     and n.channel = 'whatsapp_link'::public.notification_channel;

  if found then
    if v_child.recipient_phone is distinct from v_member.phone then
      raise exception 'The member''s phone number has changed since this message was sent'
        using errcode = 'GL066';
    end if;
  else
    -- template_key is deliberately NOT copied from the source: the contract
    -- lists exactly what a WhatsApp child carries ("same member/category/
    -- relation", source_notification_id, recipient_phone, payload) and
    -- template_key is not among them. Copying it would also be structurally
    -- illegal for a renewal source: the reserved renewal identity check
    -- requires channel='in_app' for any row named template_key='renewal_reminder',
    -- and this child is whatsapp_link.
    insert into public.notifications (
      tenant_id, member_id, channel, status, category,
      source_notification_id, recipient_phone, dedupe_key,
      related_type, related_id, scheduled_for, payload
    ) values (
      v_tenant, v_member.id, 'whatsapp_link', 'scheduled', v_source.category,
      v_source.id, v_member.phone, v_dedupe,
      v_source.related_type, v_source.related_id, statement_timestamp(), v_source.payload
    )
    returning * into v_child;

    update public.notifications
       set status = 'sent', sent_at = statement_timestamp()
     where tenant_id = v_tenant and id = v_child.id
     returning * into v_child;
  end if;

  v_url := 'https://wa.me/' || replace(v_child.recipient_phone, '+', '')
           || '?text=' || app.url_encode_component(coalesce(v_child.payload ->> 'body', ''));

  return jsonb_build_object('notification', app.notification_result_json(v_child), 'url', v_url);
end
$fn$;

revoke all on function public.open_notification_whatsapp(uuid) from public, anon;
grant execute on function public.open_notification_whatsapp(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Renewal: the one remainder formula and idempotent daily stages
--    (contract §6)
-- ---------------------------------------------------------------------------

-- app.membership_renewal_remainder -- Phase 5's exact arrived-payment
-- predicate (same tenant/membership/currency, status paid/refunded/reversed).
-- Missing/unreadable membership returns SQL NULL.
create function app.membership_renewal_remainder(p_tenant_id uuid, p_membership_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  with m as (
    select ms.id, ms.member_id, ms.currency, ms.ends_on,
           ms.price_paise, ms.discount_paise, ms.periods_granted
      from public.memberships ms
     where ms.tenant_id = p_tenant_id and ms.id = p_membership_id
  ),
  receipts as (
    select p.id as payment_id, p.amount_paise
      from public.payments p, m
     where p.tenant_id = p_tenant_id
       and p.membership_id = m.id
       and p.currency = m.currency
       and p.status in ('paid'::public.payment_status, 'refunded'::public.payment_status,
                        'reversed'::public.payment_status)
  ),
  agg as (
    select coalesce(sum(r.amount_paise), 0) as eligible_paid
      from receipts r
  ),
  calc as (
    select m.*, agg.eligible_paid::numeric as eligible_paid,
           (m.price_paise::numeric - m.discount_paise::numeric) as net_price_paise,
           m.periods_granted::numeric
             * (m.price_paise::numeric - m.discount_paise::numeric) as granted_paise
      from m, agg
  )
  select jsonb_build_object(
    'membershipId', calc.id,
    'memberId', calc.member_id,
    'currency', calc.currency,
    'endsOn', calc.ends_on,
    'pricePaise', calc.price_paise::text,
    'discountPaise', calc.discount_paise::text,
    'netPricePaise', calc.net_price_paise::text,
    'periodsGranted', calc.periods_granted::text,
    'eligiblePaidPaise', calc.eligible_paid::text,
    'residualPaise', (calc.eligible_paid - calc.granted_paise)::text,
    'duePaise', (case when calc.net_price_paise = 0::numeric then 0::numeric
                 else greatest(0::numeric, calc.net_price_paise
                                  - (calc.eligible_paid - calc.granted_paise))
                 end)::text,
    'receipts', coalesce((
      select jsonb_agg(jsonb_build_object('paymentId', r.payment_id, 'amountPaise', r.amount_paise::text)
                        order by r.payment_id)
        from receipts r
    ), '[]'::jsonb)
  )
  from calc;
$fn$;

revoke all on function app.membership_renewal_remainder(uuid, uuid) from public, anon;
grant execute on function app.membership_renewal_remainder(uuid, uuid) to authenticated, service_role;

-- app.renewal_window_id -- the id grammar shared by the default windows and
-- any gym's custom offset array.
create function app.renewal_window_id(p_days smallint)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case
    when p_days < 0 then 'expiry_minus_' || abs(p_days::integer)::text
    when p_days = 0 then 'expiry_day'
    else 'expiry_plus_' || p_days::text
  end;
$fn$;

revoke all on function app.renewal_window_id(smallint) from public, anon, authenticated;
grant execute on function app.renewal_window_id(smallint) to service_role;

-- app.default_renewal_reminder_windows -- GENERATED from the registered
-- RENEWAL_REMINDER_WINDOWS constant in
-- packages/shared/src/config/constants.ts (id, daysFromExpiry pairs):
-- expiry_minus_14=-14, expiry_minus_7=-7, expiry_minus_3=-3, expiry_day=0,
-- expiry_plus_3=3. The marked VALUES block below is generated; do not hand
-- edit it. Run `pnpm run generate-renewal-reminder-windows` after changing
-- the registered constant.
create function app.default_renewal_reminder_windows()
returns table(window_id text, days_from_expiry smallint)
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select * from (values
    -- RENEWAL_REMINDER_WINDOWS: generated; do not hand edit this block.
    -- GENERATED_RENEWAL_REMINDER_WINDOWS_START
    ('expiry_minus_14'::text, (-14)::smallint),
    ('expiry_minus_7'::text, (-7)::smallint),
    ('expiry_minus_3'::text, (-3)::smallint),
    ('expiry_day'::text, (0)::smallint),
    ('expiry_plus_3'::text, (3)::smallint)
    -- GENERATED_RENEWAL_REMINDER_WINDOWS_END
  ) as w(window_id, days_from_expiry);
$fn$;

revoke all on function app.default_renewal_reminder_windows() from public, anon, authenticated;
grant execute on function app.default_renewal_reminder_windows() to service_role;

-- app.run_renewal_reminders -- one gym's daily stage. Statement_timestamp()
-- and the gym's stored timezone decide one local date; membership locks are
-- acquired in ascending member_id order across the tenant's candidates.
create function app.run_renewal_reminders(p_tenant_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_org public.organizations%rowtype;
  v_evaluated_at timestamptz := statement_timestamp();
  v_local_date date;
  v_custom smallint[];
  v_window_defs jsonb;
  v_membership record;
  v_member public.members%rowtype;
  v_remainder jsonb;
  v_win record;
  v_window_id text;
  v_days smallint;
  v_dedupe text;
  v_body text;
  v_new_id uuid;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_created integer := 0;
  v_sent integer := 0;
  v_opted_out integer := 0;
begin
  select o.* into v_org from public.organizations o where o.id = p_tenant_id;
  if v_org.id is null then
    return jsonb_build_object('tenantId', p_tenant_id, 'localDate', null, 'timezone', null,
      'evaluatedAt', v_evaluated_at, 'createdCount', '0', 'sentCount', '0', 'optedOutCount', '0');
  end if;

  if not (v_org.status = 'active'::public.organization_status
          or (v_org.status = 'trial'::public.organization_status
              and v_org.trial_ends_at is not null and v_org.trial_ends_at > v_evaluated_at)) then
    return jsonb_build_object('tenantId', p_tenant_id, 'localDate', null, 'timezone', v_org.timezone,
      'evaluatedAt', v_evaluated_at, 'createdCount', '0', 'sentCount', '0', 'optedOutCount', '0');
  end if;

  v_local_date := (v_evaluated_at at time zone v_org.timezone)::date;

  select os.renewal_reminder_days_from_expiry into v_custom
    from public.organization_settings os where os.tenant_id = p_tenant_id;
  if not found then
    return jsonb_build_object(
      'tenantId', p_tenant_id, 'localDate', v_local_date, 'timezone', v_org.timezone,
      'evaluatedAt', v_evaluated_at, 'createdCount', '0', 'sentCount', '0', 'optedOutCount', '0'
    );
  end if;

  if v_custom is null then
    select coalesce(jsonb_agg(jsonb_build_object('windowId', w.window_id, 'days', w.days_from_expiry)), '[]'::jsonb)
      into v_window_defs
      from app.default_renewal_reminder_windows() w;
  else
    select coalesce(jsonb_agg(jsonb_build_object('windowId', app.renewal_window_id(d), 'days', d)), '[]'::jsonb)
      into v_window_defs
      from unnest(v_custom) d;
  end if;

  for v_membership in
    select ms.id, ms.member_id
      from public.memberships ms
     where ms.tenant_id = p_tenant_id
       and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                         'frozen'::public.membership_status)
       and ms.ends_on is not null
     order by ms.member_id asc, ms.id asc
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      'renewal-member:' || p_tenant_id::text || ':' || v_membership.member_id::text, 0
    ));

    select m.* into v_member from public.members m
     where m.tenant_id = p_tenant_id and m.id = v_membership.member_id
     for update;
    if v_member.id is null
       or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       or v_member.erased_at is not null then
      continue;
    end if;

    -- Re-read and lock the membership after taking the member lock.
    -- The original candidate scan is only a work list; it must not decide a
    -- cycle after a concurrent renewal or membership change.
    select ms.* into v_membership from public.memberships ms
     where ms.tenant_id = p_tenant_id and ms.id = v_membership.id
       and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                         'frozen'::public.membership_status)
       and ms.ends_on is not null
     for update;
    if v_membership.id is null then
      continue;
    end if;

    v_remainder := app.membership_renewal_remainder(p_tenant_id, v_membership.id);
    if v_remainder is null or (v_remainder ->> 'duePaise')::numeric <= 0::numeric then
      continue;
    end if;

    -- A reminder is not even queued without current service consent.  This
    -- read follows the member lock in its own statement, so a committed
    -- withdrawal wins before any notification/audit row exists.
    v_purpose := app.notification_consent_purpose('renewal'::public.message_category);
    select c.granted into v_granted from public.consents c
     where c.tenant_id = p_tenant_id and c.member_id = v_member.id and c.purpose = v_purpose
     order by c.recorded_at desc, c.id desc
     limit 1;
    if coalesce(v_granted, false) is not true then
      continue;
    end if;

    for v_win in select * from jsonb_array_elements(v_window_defs) x(value) loop
      v_window_id := v_win.value ->> 'windowId';
      v_days := (v_win.value ->> 'days')::smallint;

      if v_local_date <> ((v_remainder ->> 'endsOn')::date + v_days) then
        continue;
      end if;

      v_dedupe := 'renewal:' || lower(v_membership.id::text) || ':'
                  || to_char((v_remainder ->> 'endsOn')::date, 'YYYY-MM-DD') || ':' || v_window_id;

      -- Decimal rendering remains exact even at bigint's edge: no floating
      -- conversion or fixed-width to_char mask can round or overflow it.
      v_body := 'Your membership ends on ' || to_char((v_remainder ->> 'endsOn')::date, 'YYYY-MM-DD')
                || '. Renewal amount due: ' || (v_remainder ->> 'currency') || ' '
                || trunc((v_remainder ->> 'duePaise')::numeric / 100::numeric)::text || '.'
                || lpad(mod((v_remainder ->> 'duePaise')::numeric, 100::numeric)::text, 2, '0') || '.';

      -- This membership is already locked above. Avoid even attempting a
      -- duplicate INSERT on reruns, so no BEFORE lifecycle/audit trigger
      -- fires for an existing dedupe key.
      if exists (
        select 1 from public.notifications n
         where n.tenant_id = p_tenant_id and n.dedupe_key = v_dedupe
      ) then
        continue;
      end if;

      insert into public.notifications (
        tenant_id, member_id, channel, status, category, template_key,
        related_type, related_id, dedupe_key, scheduled_for, payload
      ) values (
        p_tenant_id, v_member.id, 'in_app', 'scheduled', 'renewal', 'renewal_reminder',
        'membership', v_membership.id, v_dedupe, v_evaluated_at,
        jsonb_build_object(
          'body', v_body, 'locale', 'en', 'membershipId', v_membership.id,
          'cycleEndsOn', to_char((v_remainder ->> 'endsOn')::date, 'YYYY-MM-DD'),
          'windowId', v_window_id, 'duePaise', v_remainder ->> 'duePaise',
          'currency', v_remainder ->> 'currency'
        )
      )
      on conflict (tenant_id, dedupe_key) where dedupe_key is not null do nothing
      returning id into v_new_id;

      if v_new_id is null then
        continue;
      end if;
      v_created := v_created + 1;

      update public.notifications
         set status = 'sent', sent_at = statement_timestamp()
       where tenant_id = p_tenant_id and id = v_new_id;
      v_sent := v_sent + 1;
      v_new_id := null;
    end loop;
  end loop;

  return jsonb_build_object(
    'tenantId', p_tenant_id, 'localDate', v_local_date, 'timezone', v_org.timezone,
    'evaluatedAt', v_evaluated_at, 'createdCount', v_created::text, 'sentCount', v_sent::text,
    'optedOutCount', v_opted_out::text
  );
end
$fn$;

revoke all on function app.run_renewal_reminders(uuid) from public, anon, authenticated;
grant execute on function app.run_renewal_reminders(uuid) to service_role;

create function public.run_renewal_reminders_all()
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant record;
  v_runs jsonb := '[]'::jsonb;
begin
  for v_tenant in select o.id from public.organizations o order by o.id asc loop
    v_runs := v_runs || jsonb_build_array(app.run_renewal_reminders(v_tenant.id));
  end loop;
  return jsonb_build_object('runs', v_runs);
end
$fn$;

revoke all on function public.run_renewal_reminders_all() from public, anon, authenticated;
grant execute on function public.run_renewal_reminders_all() to service_role;

-- Idempotent: cron.schedule upserts by job name, so re-applying this
-- migration re-points the job rather than creating a second one (same
-- pattern as 20260909170000_the_critic_was_right_four_times.sql's
-- no-show-scan-nightly).
select cron.schedule(
  'renewal-reminders-hourly',
  '0 * * * *',
  $cron$select public.run_renewal_reminders_all()$cron$
);

-- ---------------------------------------------------------------------------
-- 7. Wallet movement and the future paid-acceptance stub (contract §7)
-- ---------------------------------------------------------------------------

-- app.record_wallet_movement -- the private locked-replay/ledger/audit
-- helper. Direct execution is revoked from PUBLIC, anon, authenticated AND
-- service_role; only a postgres-owned SECURITY DEFINER command (currently
-- only public.adjust_messaging_wallet) can reach it, since it too is
-- postgres-owned and so needs no separate grant to call it.
create function app.record_wallet_movement(
  p_tenant_id uuid,
  p_delta_credits bigint,
  p_reason text,
  p_request_key uuid,
  p_notification_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_balance bigint;
  v_new_balance numeric;
  v_new_balance_bigint bigint;
  v_ledger_id uuid;
  v_created_at timestamptz;
  v_role public.app_role;
  v_impersonation uuid;
  v_reason text;
  v_existing public.messaging_wallet_ledger%rowtype;
begin
  select w.balance_credits into v_balance
    from public.messaging_wallets w
   where w.tenant_id = p_tenant_id
   for update;
  if v_balance is null then
    raise exception 'Wallet not found' using errcode = 'P0002';
  end if;

  if p_delta_credits = 0 then
    raise exception 'A wallet adjustment requires a nonzero delta'
      using errcode = '23514';
  end if;
  v_reason := btrim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'A wallet adjustment requires a reason'
      using errcode = '23514';
  end if;
  if p_request_key is null then
    raise exception 'A wallet adjustment requires its request key'
      using errcode = '22023';
  end if;

  -- Wallet locking serializes every request-key replay with its original
  -- movement. The comparison belongs here, beside the eventual insert.
  select l.* into v_existing from public.messaging_wallet_ledger l
   where l.tenant_id = p_tenant_id and l.request_key = p_request_key;
  if found then
    if v_existing.delta_credits = p_delta_credits
       and v_existing.reason = v_reason
       and v_existing.recorded_by_user_id = p_actor_user_id then
      return jsonb_build_object(
        'ledgerId', v_existing.id, 'tenantId', v_existing.tenant_id,
        'deltaCredits', v_existing.delta_credits::text, 'reason', v_existing.reason,
        'balanceAfterCredits', v_existing.balance_after_credits::text,
        'createdAt', v_existing.created_at
      );
    end if;
    raise exception 'This request key is bound to a different adjustment'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  v_new_balance := v_balance::numeric + p_delta_credits::numeric;
  if v_new_balance < 0 then
    raise exception 'This movement would drive the wallet below zero'
      using errcode = 'GL067';
  end if;
  begin
    v_new_balance_bigint := v_new_balance::bigint;
  exception
    when numeric_value_out_of_range then
      raise exception 'This movement overflows the credit balance'
        using errcode = '22003';
  end;

  insert into public.messaging_wallet_ledger (
    tenant_id, delta_credits, reason, notification_id, request_key,
    recorded_by_user_id, balance_after_credits
  ) values (
    p_tenant_id, p_delta_credits, v_reason, p_notification_id, p_request_key,
    p_actor_user_id, v_new_balance_bigint
  )
  returning id, created_at into v_ledger_id, v_created_at;

  update public.messaging_wallets
     set balance_credits = v_new_balance_bigint
   where tenant_id = p_tenant_id;

  v_role := null;
  if auth.uid() is not null then
    select e.enumlabel::text::public.app_role into v_role
      from pg_catalog.pg_enum e
     where e.enumtypid = 'public.app_role'::pg_catalog.regtype
       and e.enumlabel = app.current_app_role();
    v_impersonation := app.current_impersonation_id();
  end if;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    p_tenant_id, p_actor_user_id, v_role, v_impersonation,
    case when p_notification_id is not null then 'messaging_wallet.debited' else 'messaging_wallet.adjusted' end,
    'messaging_wallet', p_tenant_id,
    jsonb_build_object('balance_credits', v_balance::text),
    jsonb_build_object(
      'balance_credits', v_new_balance_bigint::text,
      'ledger_id', v_ledger_id,
      'delta_credits', p_delta_credits::text,
      'notification_id', p_notification_id,
      'request_key', p_request_key,
      'recorded_by_user_id', p_actor_user_id
    ),
    v_reason
  );

  return jsonb_build_object(
    'ledgerId', v_ledger_id, 'tenantId', p_tenant_id,
    'deltaCredits', p_delta_credits::text, 'reason', v_reason,
    'balanceAfterCredits', v_new_balance_bigint::text,
    'createdAt', v_created_at
  );
end
$fn$;

revoke all on function app.record_wallet_movement(uuid, bigint, text, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- public.adjust_messaging_wallet -- SECURITY DEFINER (per contract). Requires
-- a super_admin session with a matching active platform_users row and no
-- gym/staff/member/impersonation identity.
create function public.adjust_messaging_wallet(
  p_tenant_id uuid,
  p_delta_credits bigint,
  p_reason text,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_user uuid;
begin
  v_user := auth.uid();
  if v_user is null
     or app.current_app_role() <> 'super_admin'
     or app.current_tenant_id() is not null
     or app.current_staff_id() is not null
     or app.current_member_id() is not null
     or app.current_impersonation_id() is not null
     or not exists (
       select 1 from public.platform_users pu
        where pu.user_id = v_user and pu.role = 'super_admin'::public.app_role and pu.is_active
     ) then
    raise exception 'A wallet adjustment requires a real super admin session'
      using errcode = '42501';
  end if;

  -- Resolve the target before request validation. The private helper then
  -- owns validation, locked replay comparison and the movement atomically.
  if not exists (select 1 from public.messaging_wallets w where w.tenant_id = p_tenant_id) then
    raise exception 'Wallet not found' using errcode = 'P0002';
  end if;
  return app.record_wallet_movement(p_tenant_id, p_delta_credits, p_reason, p_request_key, null, v_user);
end
$fn$;

revoke all on function public.adjust_messaging_wallet(uuid, bigint, text, uuid) from public, anon;
grant execute on function public.adjust_messaging_wallet(uuid, bigint, text, uuid) to authenticated;

-- app.accept_paid_notification -- the frozen future contract stub. No
-- implementation or grant is added in this phase; it exists only so the
-- signature is normative for the later provider migration. INVOKER per
-- contract ("a service-only INVOKER contract"); nobody is granted execute.
create function app.accept_paid_notification(
  p_notification_id uuid,
  p_provider_message_id text,
  p_cost_credits bigint,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'Paid notification acceptance is not enabled in this phase'
    using errcode = 'GL069';
end
$fn$;

revoke all on function app.accept_paid_notification(uuid, text, bigint, uuid)
  from public, anon, authenticated, service_role;
