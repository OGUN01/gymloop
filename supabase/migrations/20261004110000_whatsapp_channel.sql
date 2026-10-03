-- WSP — WhatsApp channel transport (Wave C). Contract:
-- openspec/changes/whatsapp-channel/{proposal,provider-wallet-amendment,
-- existing-credit-conversion-amendment,credit-conversion-public-declarations}.md
-- plus openspec/changes/v2-batch2-shared/{wave-c-delivery-declarations-draft,
-- wave-c-serial-freeze-declarations}.md. Executable contract:
-- supabase/tests/80_whatsapp_channel.sql (visible) by an independent author.
--
-- Scope of THIS file: WSP channel-owned tables, member/front-office commands,
-- service transport facades, funds/holds/debit on the one paise wallet from
-- 20261004085000_messaging_wallet_paise.sql, and the frozen key grammar
-- (whatsapp-paid:<source_notification_id> paid child; whatsapp-fallback:<id>
-- in-app fallback; manual whatsapp:<id> untouched).
--
-- NOT done here (reported to the orchestrator as required seam extensions,
-- per the WSP implementer brief): this migration intentionally does NOT
-- re-amend app.enforce_notification / public.send_notification / app.run_
-- push_events, because the authorization to amend the shared seam is the
-- orchestrator's serial decision, not an implementer discretion. The three
-- missing extension points are documented at the bottom of this file:
--   (1) service-created insert of the whatsapp_paid child,
--   (2) whatsapp_link scheduled→sent under durable attempt evidence,
--   (3) whatsapp-caused sent→delivered on the in-app source row.
-- Until those land, the WSP transport records all provider/attempt/receipt
-- truth in its own tables and the source-row advances stay provably blocked
-- (never faked).
--
-- GL119: sender/template/rate not dispatch-ready. GL120: stale/mismatched
-- lease ticket or replayed authorization. GL121: causal debit refusal.
-- GL122: receipt without a matching accepted attempt or evidence conflict.

-- ---------------------------------------------------------------------------
-- 1. Sender accounts — credentials are a reference, never a value.
-- ---------------------------------------------------------------------------
create table public.whatsapp_sender_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  provider text not null
    constraint whatsapp_sender_accounts_provider_chk check (provider in ('meta')),
  waba_id text not null
    constraint whatsapp_sender_accounts_waba_chk check (btrim(waba_id) <> '' and char_length(btrim(waba_id)) <= 128),
  sender_id text not null
    constraint whatsapp_sender_accounts_sender_chk check (btrim(sender_id) <> '' and char_length(btrim(sender_id)) <= 64),
  secret_reference text not null
    constraint whatsapp_sender_accounts_secret_reference_chk check (secret_reference like 'vault:%' and char_length(secret_reference) <= 200),
  enabled boolean not null default false,
  compliance_approved_at timestamptz,
  template_ready_at timestamptz,
  config_revision text not null default ''
    constraint whatsapp_sender_accounts_config_revision_chk check (char_length(config_revision) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_sender_accounts_tenant_id_sender_id_key unique (tenant_id, sender_id),
  constraint whatsapp_sender_accounts_tenant_id_id_key unique (tenant_id, id)
);

alter table public.whatsapp_sender_accounts enable row level security;
revoke all on public.whatsapp_sender_accounts from public, anon, authenticated, service_role;

create policy whatsapp_sender_accounts_tenant_select
  on public.whatsapp_sender_accounts for select to authenticated
  using (tenant_id = app.current_tenant_id());

create index whatsapp_sender_accounts_tenant_id_idx
  on public.whatsapp_sender_accounts (tenant_id);

create trigger whatsapp_sender_accounts_touch_updated_at before update
  on public.whatsapp_sender_accounts for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Template revisions — approved template identity is frozen once checked;
--    approval/pause state moves through the owner/manager command path only.
-- ---------------------------------------------------------------------------
create table public.whatsapp_template_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  sender_account_id uuid not null,
  template_id uuid not null references public.message_templates (id),
  body_hash text not null
    constraint whatsapp_template_revisions_body_hash_chk check (btrim(body_hash) <> '' and char_length(btrim(body_hash)) <= 128),
  parameter_schema_hash text not null
    constraint whatsapp_template_revisions_parameter_schema_hash_chk check (btrim(parameter_schema_hash) <> '' and char_length(btrim(parameter_schema_hash)) <= 128),
  provider_template_name text not null
    constraint whatsapp_template_revisions_provider_name_chk check (btrim(provider_template_name) <> '' and char_length(btrim(provider_template_name)) <= 160),
  provider_template_id text,
  locale text not null default 'en',
  category text not null,
  approved_at timestamptz,
  paused_at timestamptz,
  disabled_at timestamptz,
  approval_evidence_digest text,
  checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_template_revisions_tenant_id_sender_id_fkey
    foreign key (tenant_id, sender_account_id)
      references public.whatsapp_sender_accounts (tenant_id, id),
  constraint whatsapp_template_revisions_tenant_id_template_id_key unique (tenant_id, template_id),
  constraint whatsapp_template_revisions_tenant_id_id_key unique (tenant_id, id)
);

alter table public.whatsapp_template_revisions enable row level security;
revoke all on public.whatsapp_template_revisions from public, anon, authenticated, service_role;
grant select on public.whatsapp_template_revisions to authenticated;

create policy whatsapp_template_revisions_tenant_select
  on public.whatsapp_template_revisions for select to authenticated
  using (tenant_id = app.current_tenant_id() and app.is_front_office());

create index whatsapp_template_revisions_tenant_id_category_idx
  on public.whatsapp_template_revisions (tenant_id, category, checked_at desc);

create function app.enforce_whatsapp_template_revision_freeze()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'A template revision is retired through state, never deleted'
      using errcode = '23514';
  end if;
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.sender_account_id is distinct from old.sender_account_id
     or new.template_id is distinct from old.template_id
     or new.body_hash is distinct from old.body_hash
     or new.parameter_schema_hash is distinct from old.parameter_schema_hash
     or new.provider_template_name is distinct from old.provider_template_name
     or new.provider_template_id is distinct from old.provider_template_id
     or new.locale is distinct from old.locale
     or new.category is distinct from old.category
     or new.checked_at is distinct from old.checked_at then
    raise exception 'An approved template revision identity is frozen'
      using errcode = '23514';
  end if;
  new.updated_at := statement_timestamp();
  return new;
end
$fn$;
alter function app.enforce_whatsapp_template_revision_freeze() owner to postgres;
revoke all on function app.enforce_whatsapp_template_revision_freeze() from public, anon, authenticated, service_role;

create trigger whatsapp_template_revisions_frozen before update or delete
  on public.whatsapp_template_revisions for each row
  execute function app.enforce_whatsapp_template_revision_freeze();

create trigger whatsapp_template_revisions_touch_updated_at before update
  on public.whatsapp_template_revisions for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Rate versions — immutable once published; INR integer paise only; the
--    22023 boundaries are raised here, not left to a bare CHECK (23514).
-- ---------------------------------------------------------------------------
create table public.whatsapp_rate_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  sender_account_id uuid not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  destination_market text not null
    constraint whatsapp_rate_versions_market_chk check (btrim(destination_market) <> '' and char_length(btrim(destination_market)) <= 8),
  provider_category text not null
    constraint whatsapp_rate_versions_category_chk check (btrim(provider_category) <> '' and char_length(btrim(provider_category)) <= 64),
  amount_paise bigint not null,
  max_amount_paise bigint not null,
  currency text not null,
  rounding_revision text not null default 'all_in'
    constraint whatsapp_rate_versions_rounding_chk check (btrim(rounding_revision) in ('all_in')),
  evidence_digest text not null
    constraint whatsapp_rate_versions_evidence_chk check (btrim(evidence_digest) <> '' and char_length(btrim(evidence_digest)) <= 256),
  created_at timestamptz not null default now(),
  constraint whatsapp_rate_versions_tenant_id_sender_id_fkey
    foreign key (tenant_id, sender_account_id)
      references public.whatsapp_sender_accounts (tenant_id, id),
  constraint whatsapp_rate_versions_tenant_id_id_key unique (tenant_id, id),
  constraint whatsapp_rate_versions_interval_chk check (effective_to is null or effective_to > effective_from)
);

alter table public.whatsapp_rate_versions enable row level security;
revoke all on public.whatsapp_rate_versions from public, anon, authenticated, service_role;

create policy whatsapp_rate_versions_tenant_select
  on public.whatsapp_rate_versions for select to service_role
  using (true);

create index whatsapp_rate_versions_account_effective_idx
  on public.whatsapp_rate_versions (tenant_id, sender_account_id, effective_from desc);

-- The real publication guard: INR-only, nonnegative, integer paise, with the
-- 22023 refusal codes the frozen contract assigns to bad tariff input.
create function app.enforce_whatsapp_rate_publication()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'A published tariff version is immutable' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'A published tariff version is immutable once used' using errcode = '23514';
  end if;
  if new.amount_paise is null or new.max_amount_paise is null or new.currency is null then
    raise exception 'A tariff requires an explicit amount, ceiling and currency'
      using errcode = '22023';
  end if;
  if new.amount_paise < 0::bigint then
    raise exception 'A tariff amount cannot be negative' using errcode = '22023';
  end if;
  if new.max_amount_paise < new.amount_paise then
    raise exception 'The tariff ceiling cannot be below its amount' using errcode = '22023';
  end if;
  if new.currency is distinct from 'INR' then
    raise exception 'WhatsApp tariffs are published in INR only' using errcode = '22023';
  end if;
  return new;
end
$fn$;
alter function app.enforce_whatsapp_rate_publication() owner to postgres;
revoke all on function app.enforce_whatsapp_rate_publication() from public, anon, authenticated, service_role;

create trigger whatsapp_rate_versions_publication before insert or update or delete
  on public.whatsapp_rate_versions for each row
  execute function app.enforce_whatsapp_rate_publication();

-- ---------------------------------------------------------------------------
-- 4. Channel consents — append-only, versioned, phone kept as a digest.
-- ---------------------------------------------------------------------------
create table public.whatsapp_channel_consents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations (id),
  member_id uuid not null,
  purpose public.consent_purpose not null,
  granted boolean not null,
  notice_version text not null
    constraint whatsapp_channel_consents_notice_chk check (btrim(notice_version) <> '' and char_length(btrim(notice_version)) <= 64),
  source text not null
    constraint whatsapp_channel_consents_source_chk check (btrim(source) <> '' and char_length(btrim(source)) <= 64),
  recipient_phone_digest text not null
    constraint whatsapp_channel_consents_digest_chk check (btrim(recipient_phone_digest) <> '' and char_length(btrim(recipient_phone_digest)) <= 128),
  contact_version_ref text not null
    constraint whatsapp_channel_consents_contact_ref_chk check (btrim(contact_version_ref) <> '' and char_length(btrim(contact_version_ref)) <= 128),
  recipient_basis text not null
    constraint whatsapp_channel_consents_basis_chk check (recipient_basis in ('self', 'guardian')),
  recorded_by_staff_id uuid,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint whatsapp_channel_consents_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id),
  constraint whatsapp_channel_consents_tenant_id_staff_id_fkey
    foreign key (tenant_id, recorded_by_staff_id) references public.staff (tenant_id, id)
);

alter table public.whatsapp_channel_consents enable row level security;
revoke all on public.whatsapp_channel_consents from public, anon, authenticated, service_role;
grant select on public.whatsapp_channel_consents to authenticated;

-- Own-member rows for the member session; the front-office safe projection
-- (owner/manager/front desk, verified staff row, never impersonation) is the
-- contract's second reader of the same table.
create policy whatsapp_channel_consents_tenant_select
  on public.whatsapp_channel_consents for select to authenticated
  using (
    tenant_id = app.current_tenant_id()
    and (
      (
        member_id = app.current_member_id()
        and app.current_impersonation_id() is null
      )
      or (
        app.is_front_office()
        and app.current_impersonation_id() is null
        and app.current_staff_id() is not null
      )
    )
  );

create index whatsapp_channel_consents_tenant_member_recorded_idx
  on public.whatsapp_channel_consents (tenant_id, member_id, recorded_at desc, id desc);

create function app.enforce_whatsapp_channel_consent_append_only()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'WhatsApp channel consent history is append-only'
    using errcode = '23514';
end
$fn$;
alter function app.enforce_whatsapp_channel_consent_append_only() owner to postgres;
revoke all on function app.enforce_whatsapp_channel_consent_append_only() from public, anon, authenticated, service_role;

create trigger whatsapp_channel_consents_append_only before update or delete
  on public.whatsapp_channel_consents for each row
  execute function app.enforce_whatsapp_channel_consent_append_only();

-- ---------------------------------------------------------------------------
-- 5. Dispatch attempts — the durable causal record; no recipient phone column.
-- ---------------------------------------------------------------------------
create table public.notification_whatsapp_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  member_id uuid not null,
  notification_id uuid not null,
  sender_account_id uuid not null,
  template_revision_id uuid not null,
  rate_version_id uuid not null,
  consent_id uuid,
  request_key uuid not null,
  lease_ticket uuid not null,
  lease_expires_at timestamptz not null,
  recipient_contact_revision text not null
    constraint notification_whatsapp_attempts_contact_revision_chk check (btrim(recipient_contact_revision) <> '' and char_length(btrim(recipient_contact_revision)) <= 128),
  hold_max_paise bigint not null
    constraint notification_whatsapp_attempts_hold_chk check (hold_max_paise > 0::bigint),
  hold_currency text not null
    constraint notification_whatsapp_attempts_hold_currency_chk check (hold_currency = 'INR'),
  authorized_at timestamptz,
  io_started_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  uncertain_at timestamptz,
  provider_message_id text
    constraint notification_whatsapp_attempts_provider_message_chk
      check (provider_message_id is null or (btrim(provider_message_id) <> '' and char_length(btrim(provider_message_id)) <= 256)),
  failure_code text
    constraint notification_whatsapp_attempts_failure_code_chk
      check (failure_code is null or (btrim(failure_code) <> '' and char_length(btrim(failure_code)) <= 64)),
  released_at timestamptz,
  charged_ledger_id uuid,
  provider_read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_whatsapp_attempts_tenant_id_request_key_key unique (tenant_id, request_key),
  constraint notification_whatsapp_attempts_tenant_id_id_key unique (tenant_id, id),
  constraint notification_whatsapp_attempts_tenant_id_notification_id_fkey
    foreign key (tenant_id, notification_id) references public.notifications (tenant_id, id),
  constraint notification_whatsapp_attempts_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id),
  constraint notification_whatsapp_attempts_tenant_id_sender_id_fkey
    foreign key (tenant_id, sender_account_id)
      references public.whatsapp_sender_accounts (tenant_id, id),
  constraint notification_whatsapp_attempts_tenant_id_template_id_fkey
    foreign key (tenant_id, template_revision_id)
      references public.whatsapp_template_revisions (tenant_id, id),
  constraint notification_whatsapp_attempts_tenant_id_rate_id_fkey
    foreign key (tenant_id, rate_version_id)
      references public.whatsapp_rate_versions (tenant_id, id),
  constraint notification_whatsapp_attempts_consent_id_fkey
    foreign key (consent_id) references public.consents (id)
);

alter table public.notification_whatsapp_attempts enable row level security;
revoke all on public.notification_whatsapp_attempts from public, anon, authenticated, service_role;
grant select on public.notification_whatsapp_attempts to service_role;

create policy notification_whatsapp_attempts_service_select
  on public.notification_whatsapp_attempts for select to service_role
  using (true);

create index notification_whatsapp_attempts_tenant_id_notification_id_idx
  on public.notification_whatsapp_attempts (tenant_id, notification_id);

create index notification_whatsapp_attempts_tenant_id_created_at_idx
  on public.notification_whatsapp_attempts (tenant_id, created_at desc);

create unique index notification_whatsapp_attempts_sender_provider_id_key
  on public.notification_whatsapp_attempts (sender_account_id, provider_message_id)
  where provider_message_id is not null;

-- One LIVE attempt per notification: closed/refused attempts are historical
-- records and the queued source may be claimed again; an uncertain or
-- accepted attempt stays live and blocks replacement.
create unique index notification_whatsapp_attempts_live_notification_key
  on public.notification_whatsapp_attempts (tenant_id, notification_id)
  where completed_at is null;

create function app.enforce_whatsapp_attempt_freeze()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'A WhatsApp attempt is closed with facts, never deleted'
      using errcode = '23514';
  end if;
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.member_id is distinct from old.member_id
     or new.notification_id is distinct from old.notification_id
     or new.sender_account_id is distinct from old.sender_account_id
     or new.template_revision_id is distinct from old.template_revision_id
     or new.rate_version_id is distinct from old.rate_version_id
     or new.consent_id is distinct from old.consent_id
     or new.request_key is distinct from old.request_key
     or new.lease_ticket is distinct from old.lease_ticket
     or new.recipient_contact_revision is distinct from old.recipient_contact_revision
     or new.hold_max_paise is distinct from old.hold_max_paise
     or new.hold_currency is distinct from old.hold_currency then
    raise exception 'A WhatsApp attempt''s identity and reservation are frozen'
      using errcode = '23514';
  end if;
  new.updated_at := statement_timestamp();
  return new;
end
$fn$;
alter function app.enforce_whatsapp_attempt_freeze() owner to postgres;
revoke all on function app.enforce_whatsapp_attempt_freeze() from public, anon, authenticated, service_role;

create trigger notification_whatsapp_attempts_frozen before update or delete
  on public.notification_whatsapp_attempts for each row
  execute function app.enforce_whatsapp_attempt_freeze();

create trigger notification_whatsapp_attempts_touch_updated_at before update
  on public.notification_whatsapp_attempts for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Provider receipts — normalized, fingerprint-idempotent, no raw bodies.
-- ---------------------------------------------------------------------------
create table public.notification_whatsapp_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  attempt_id uuid not null,
  sender_account_id uuid not null,
  receipt_fingerprint text not null
    constraint notification_whatsapp_receipts_fingerprint_chk
      check (btrim(receipt_fingerprint) <> '' and char_length(btrim(receipt_fingerprint)) <= 128),
  event_kind text not null
    constraint notification_whatsapp_receipts_event_kind_chk
      check (event_kind in ('delivered', 'read', 'failed')),
  provider_event_at timestamptz not null,
  received_at timestamptz not null default now(),
  evidence_digest text not null
    constraint notification_whatsapp_receipts_evidence_chk
      check (btrim(evidence_digest) <> '' and char_length(btrim(evidence_digest)) <= 256),
  billing_category text,
  billing_evidence_ref text,
  created_at timestamptz not null default now(),
  constraint notification_whatsapp_receipts_tenant_id_attempt_id_fkey
    foreign key (tenant_id, attempt_id)
      references public.notification_whatsapp_attempts (tenant_id, id),
  constraint notification_whatsapp_receipts_tenant_id_sender_id_fkey
    foreign key (tenant_id, sender_account_id)
      references public.whatsapp_sender_accounts (tenant_id, id)
);

alter table public.notification_whatsapp_receipts enable row level security;
revoke all on public.notification_whatsapp_receipts from public, anon, authenticated, service_role;
grant select on public.notification_whatsapp_receipts to service_role;

create policy notification_whatsapp_receipts_service_select
  on public.notification_whatsapp_receipts for select to service_role
  using (true);

create unique index notification_whatsapp_receipts_sender_fingerprint_key
  on public.notification_whatsapp_receipts (sender_account_id, receipt_fingerprint);

create trigger notification_whatsapp_receipts_append_only before update or delete
  on public.notification_whatsapp_receipts for each row
  execute function app.enforce_whatsapp_channel_consent_append_only();

-- ---------------------------------------------------------------------------
-- 7. Dispatch queue and replay-key registry (WSP-owned, no client grants).
-- ---------------------------------------------------------------------------
create table public.whatsapp_dispatch_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  notification_id uuid not null,
  request_key uuid not null,
  requested_by_staff_id uuid not null,
  closed_at timestamptz,
  requested_at timestamptz not null default now(),
  constraint whatsapp_dispatch_requests_tenant_id_notification_id_key unique (tenant_id, notification_id),
  constraint whatsapp_dispatch_requests_tenant_id_request_key_key unique (tenant_id, request_key),
  constraint whatsapp_dispatch_requests_tenant_id_notification_id_fkey
    foreign key (tenant_id, notification_id) references public.notifications (tenant_id, id),
  constraint whatsapp_dispatch_requests_tenant_id_staff_id_fkey
    foreign key (tenant_id, requested_by_staff_id) references public.staff (tenant_id, id)
);

alter table public.whatsapp_dispatch_requests enable row level security;
revoke all on public.whatsapp_dispatch_requests from public, anon, authenticated, service_role;

create policy whatsapp_dispatch_requests_tenant_select
  on public.whatsapp_dispatch_requests for select to authenticated
  using (tenant_id = app.current_tenant_id() and app.is_front_office());

create index whatsapp_dispatch_requests_tenant_id_requested_at_idx
  on public.whatsapp_dispatch_requests (tenant_id, requested_at);

create function app.wsp_mark_source_opted_out(p_tenant uuid, p_notification uuid, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_row public.notifications;
begin
  select n.* into v_row from public.notifications n
   where n.tenant_id = p_tenant and n.id = p_notification
   for update;
  if v_row.id is null then
    return;
  end if;
  -- A scheduled source records opted_out on its legal edge; an already-sent
  -- source has no opted_out edge and records the refusal as its terminal
  -- failure reason instead.
  if v_row.status = 'scheduled'::public.notification_status then
    update public.notifications n
       set status = 'opted_out'::public.notification_status,
           opted_out_reason = btrim(p_reason)
     where n.tenant_id = p_tenant and n.id = p_notification;
  elsif v_row.status = 'sent'::public.notification_status then
    update public.notifications n
       set status = 'failed'::public.notification_status,
           failed_reason = btrim(p_reason)
     where n.tenant_id = p_tenant and n.id = p_notification;
  end if;
end
$fn$;
alter function app.wsp_mark_source_opted_out(uuid,uuid,text) owner to postgres;
revoke all on function app.wsp_mark_source_opted_out(uuid,uuid,text) from public, anon, authenticated, service_role;

create function app.wsp_close_queue_row(p_tenant uuid, p_notification uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $fn$
  update public.whatsapp_dispatch_requests r
     set closed_at = coalesce(r.closed_at, clock_timestamp())
   where r.tenant_id = p_tenant
     and r.notification_id = p_notification
     and r.closed_at is null
$fn$;
alter function app.wsp_close_queue_row(uuid,uuid) owner to postgres;
revoke all on function app.wsp_close_queue_row(uuid,uuid) from public, anon, authenticated, service_role;

create table public.whatsapp_command_keys (
  request_key uuid primary key,
  tenant_id uuid not null,
  domain text not null
    constraint whatsapp_command_keys_domain_chk check (domain in ('consent', 'dispatch')),
  facts_digest text not null
    constraint whatsapp_command_keys_facts_chk check (btrim(facts_digest) <> '' and char_length(btrim(facts_digest)) <= 128),
  result_ref uuid not null,
  created_at timestamptz not null default now(),
  constraint whatsapp_command_keys_tenant_id_fkey
    foreign key (tenant_id) references public.organizations (id)
);

alter table public.whatsapp_command_keys enable row level security;
revoke all on public.whatsapp_command_keys from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Private actor validators.
-- ---------------------------------------------------------------------------
create function app.wsp_member_actor(p_require_user_bind boolean default true)
returns public.members
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid := app.current_tenant_id();
  v_member uuid := app.current_member_id();
  v_user uuid := auth.uid();
  v_row public.members;
begin
  if current_user not in ('authenticated', 'postgres') or v_tenant is null
     or v_member is null or v_user is null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real member session'
      using errcode = '42501';
  end if;
  select m.* into v_row from public.members m
   where m.tenant_id = v_tenant and m.id = v_member
     and (not p_require_user_bind or m.user_id = v_user);
  if v_row.id is null then
    if exists (select 1 from public.members m2 where m2.id = v_member) then
      -- A member claim whose identity lives in another tenant is a forged
      -- identity, not an invisible target: refuse as a permission failure.
      raise exception 'The claimed member identity does not belong to this tenant'
        using errcode = '42501';
    end if;
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if v_row.erased_at is not null or v_row.status in ('cancelled'::public.member_status, 'blocked'::public.member_status) then
    raise exception 'This member cannot manage WhatsApp settings' using errcode = '42501';
  end if;
  return v_row;
end
$fn$;
alter function app.wsp_member_actor(boolean) owner to postgres;
revoke all on function app.wsp_member_actor(boolean) from public, anon, authenticated, service_role;

create function app.wsp_front_office_actor(p_tenant_id uuid)
returns public.staff
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row public.staff;
begin
  if current_user not in ('authenticated', 'postgres') or auth.uid() is null
     or app.is_front_office() is not true
     or app.current_tenant_id() is null or app.current_tenant_id() is distinct from p_tenant_id
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real front-office session'
      using errcode = '42501';
  end if;
  select s.* into v_row from public.staff s
   where s.tenant_id = app.current_tenant_id()
     and s.id = app.current_staff_id()
     and s.user_id = auth.uid()
     and s.role::text = app.current_app_role()
     and s.is_active;
  if v_row.id is null then
    raise exception 'This action requires a real front-office session'
      using errcode = '42501';
  end if;
  return v_row;
end
$fn$;
alter function app.wsp_front_office_actor(uuid) owner to postgres;
revoke all on function app.wsp_front_office_actor(uuid) from public, anon, service_role;
-- Safe to expose: the helper is definer and validates the session itself.
grant execute on function app.wsp_front_office_actor(uuid) to authenticated;

create function app.wsp_service_context()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if current_user not in ('service_role', 'postgres') or auth.uid() is not null
     or app.current_tenant_id() is not null
     or app.current_member_id() is not null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'WhatsApp transport commands run only under the credential service context'
      using errcode = '42501';
  end if;
end
$fn$;
alter function app.wsp_service_context() owner to postgres;
revoke all on function app.wsp_service_context() from public, anon;
grant execute on function app.wsp_service_context() to service_role;

-- ---------------------------------------------------------------------------
-- 9. Member settings and consent commands.
-- ---------------------------------------------------------------------------
create function public.read_member_whatsapp_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_member public.members;
  v_service boolean := false;
  v_marketing boolean := false;
  v_notice text;
  v_contact text;
  v_minor boolean;
  v_guardian_ok boolean;
begin
  v_member := app.wsp_member_actor();
  v_minor := app.member_is_minor_on(v_member.date_of_birth, app.gym_today(v_member.tenant_id));
  v_guardian_ok := app.member_guardian_complete(v_member);
  v_contact := app.member_contact_phone(v_member.tenant_id, v_member.id);

  select c.granted into v_service
    from public.whatsapp_channel_consents c
   where c.tenant_id = v_member.tenant_id and c.member_id = v_member.id
     and c.purpose = 'service'::public.consent_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;
  select c.granted into v_marketing
    from public.whatsapp_channel_consents c
   where c.tenant_id = v_member.tenant_id and c.member_id = v_member.id
     and c.purpose = 'marketing'::public.consent_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;

  select c.notice_version into v_notice
    from public.whatsapp_channel_consents c
   where c.tenant_id = v_member.tenant_id and c.member_id = v_member.id
   order by c.recorded_at desc, c.ctid desc limit 1;

  return jsonb_build_object(
    'service', coalesce(v_service, false),
    'marketing', coalesce(v_marketing, false),
    'recipientKind', case when v_minor and v_guardian_ok then 'guardian' else 'self' end,
    'maskedPhone', case
      when v_contact is null then null
      else '••••• ' || right(v_contact, 3)
    end,
    'noticeVersion', v_notice,
    'available', exists (
      select 1 from public.whatsapp_sender_accounts a
       where a.tenant_id = v_member.tenant_id
         and a.enabled
         and a.compliance_approved_at is not null
         and a.template_ready_at is not null
    )
  );
end
$fn$;
revoke all on function public.read_member_whatsapp_settings() from public, anon, service_role;
grant execute on function public.read_member_whatsapp_settings() to authenticated;

create function app.wsp_append_channel_consent(
  p_tenant uuid, p_member uuid, p_purpose public.consent_purpose, p_granted boolean,
  p_notice text, p_source text, p_basis text, p_staff uuid, p_user uuid
) returns public.whatsapp_channel_consents
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_contact text := app.member_contact_phone(p_tenant, p_member);
  v_digest text := encode(pg_catalog.sha256(pg_catalog.convert_to(v_contact, 'UTF8')), 'hex');
  v_row public.whatsapp_channel_consents;
begin
  insert into public.whatsapp_channel_consents (
    tenant_id, member_id, purpose, granted, notice_version, source,
    recipient_phone_digest, contact_version_ref, recipient_basis, recorded_by_staff_id
  ) values (
    p_tenant, p_member, p_purpose, p_granted, p_notice, p_source,
    v_digest, v_digest, p_basis, p_staff
  ) returning * into v_row;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    p_tenant, p_user, null, app.current_impersonation_id(),
    case when p_granted then 'whatsapp_channel_consent.granted'
         else 'whatsapp_channel_consent.withdrawn' end,
    'whatsapp_channel_consent', v_row.id,
    null,
    jsonb_build_object(
      'memberId', p_member, 'purpose', p_purpose, 'granted', p_granted,
      'noticeVersion', p_notice, 'recipientBasis', p_basis, 'consentId', v_row.id
    ),
    p_source
  );
  return v_row;
end
$fn$;
alter function app.wsp_append_channel_consent(uuid,uuid,public.consent_purpose,boolean,text,text,text,uuid,uuid) owner to postgres;
revoke all on function app.wsp_append_channel_consent(uuid,uuid,public.consent_purpose,boolean,text,text,text,uuid,uuid) from public, anon, authenticated, service_role;

create function public.set_member_whatsapp_consent(
  p_purpose public.consent_purpose,
  p_granted boolean,
  p_notice_version text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member public.members;
  v_minor boolean;
  v_basis text;
  v_latest public.whatsapp_channel_consents;
  v_row public.whatsapp_channel_consents;
begin
  if p_notice_version is null or btrim(p_notice_version) = '' then
    raise exception 'A consent decision requires its notice version' using errcode = '22023';
  end if;
  if p_purpose is null or p_purpose::text not in ('service', 'marketing') then
    raise exception 'WhatsApp consent covers service and marketing purposes' using errcode = '22023';
  end if;
  if p_granted is null then
    raise exception 'A consent decision is explicit' using errcode = '22023';
  end if;

  v_member := app.wsp_member_actor();
  v_minor := app.member_is_minor_on(v_member.date_of_birth, app.gym_today(v_member.tenant_id));
  if v_minor and app.member_guardian_complete(v_member) then
    v_basis := 'guardian';
  elsif not v_minor then
    v_basis := 'self';
  else
    raise exception 'A known minor needs a complete guardian record before WhatsApp consent'
      using errcode = '42501';
  end if;
  if app.member_contact_phone(v_member.tenant_id, v_member.id) is null then
    raise exception 'There is no WhatsApp-capable recipient on this member row'
      using errcode = '42501';
  end if;

  select c.* into v_latest
    from public.whatsapp_channel_consents c
   where c.tenant_id = v_member.tenant_id and c.member_id = v_member.id
     and c.purpose = p_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;

  if v_latest.id is not null
     and v_latest.granted is not distinct from p_granted
     and v_latest.notice_version = btrim(p_notice_version) then
    return jsonb_build_object(
      'consentId', v_latest.id, 'purpose', v_latest.purpose,
      'granted', v_latest.granted, 'noticeVersion', v_latest.notice_version,
      'recordedAt', v_latest.recorded_at
    );
  end if;

  v_row := app.wsp_append_channel_consent(
    v_member.tenant_id, v_member.id, p_purpose, p_granted,
    btrim(p_notice_version), 'member_app', v_basis, null, auth.uid()
  );
  return jsonb_build_object(
    'consentId', v_row.id, 'purpose', v_row.purpose,
    'granted', v_row.granted, 'noticeVersion', v_row.notice_version,
    'recordedAt', v_row.recorded_at
  );
end
$fn$;
revoke all on function public.set_member_whatsapp_consent(public.consent_purpose, boolean, text) from public, anon, service_role;
grant execute on function public.set_member_whatsapp_consent(public.consent_purpose, boolean, text) to authenticated;

create function app.wsp_member_consent_target(p_tenant uuid, p_member uuid)
returns public.members
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row public.members;
begin
  select m.* into v_row from public.members m
   where m.tenant_id = p_tenant and m.id = p_member;
  if v_row.id is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if v_row.erased_at is not null then
    raise exception 'An erased member cannot be granted WhatsApp consent'
      using errcode = '42501';
  end if;
  return v_row;
end
$fn$;
alter function app.wsp_member_consent_target(uuid,uuid) owner to postgres;
revoke all on function app.wsp_member_consent_target(uuid,uuid) from public, anon, authenticated, service_role;

create function public.record_whatsapp_consent(
  p_member_id uuid,
  p_purpose public.consent_purpose,
  p_granted boolean,
  p_notice_version text,
  p_source text,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid := app.current_tenant_id();
  v_staff public.staff;
  v_member public.members;
  v_minor boolean;
  v_basis text;
  v_facts text;
  v_key public.whatsapp_command_keys;
  v_row public.whatsapp_channel_consents;
begin
  v_staff := app.wsp_front_office_actor(v_tenant);
  if p_notice_version is null or btrim(p_notice_version) = '' then
    raise exception 'A consent decision requires its notice version' using errcode = '22023';
  end if;
  if p_source is null or btrim(p_source) = '' then
    raise exception 'A recorded consent requires its evidence source' using errcode = '22023';
  end if;
  if p_request_key is null then
    raise exception 'A recorded consent requires its request key' using errcode = '22023';
  end if;
  if p_purpose is null or p_purpose::text not in ('service', 'marketing') then
    raise exception 'WhatsApp consent covers service and marketing purposes' using errcode = '22023';
  end if;
  if p_granted is null then
    raise exception 'A consent decision is explicit' using errcode = '22023';
  end if;

  v_member := app.wsp_member_consent_target(v_tenant, p_member_id);
  v_minor := app.member_is_minor_on(v_member.date_of_birth, app.gym_today(v_member.tenant_id));
  if v_minor and app.member_guardian_complete(v_member) then
    v_basis := 'guardian';
  elsif not v_minor then
    v_basis := 'self';
  else
    raise exception 'A known minor needs a complete guardian record before WhatsApp consent'
      using errcode = '42501';
  end if;
  if app.member_contact_phone(v_member.tenant_id, v_member.id) is null then
    raise exception 'There is no WhatsApp-capable recipient on this member row'
      using errcode = '42501';
  end if;

  v_facts := encode(pg_catalog.sha256(pg_catalog.convert_to(
    jsonb_build_object(
      'memberId', p_member_id, 'purpose', p_purpose, 'granted', p_granted,
      'noticeVersion', btrim(p_notice_version), 'source', btrim(p_source)
    )::text, 'UTF8')), 'hex');

  select k.* into v_key from public.whatsapp_command_keys k
   where k.request_key = p_request_key;
  if v_key.request_key is not null then
    if v_key.tenant_id = v_tenant and v_key.domain = 'consent' and v_key.facts_digest = v_facts then
      select c.* into v_row from public.whatsapp_channel_consents c
       where c.id = v_key.result_ref;
      return jsonb_build_object(
        'consentId', v_row.id, 'purpose', v_row.purpose,
        'granted', v_row.granted, 'noticeVersion', v_row.notice_version,
        'recordedAt', v_row.recorded_at
      );
    end if;
    raise exception 'This request key is bound to a different consent decision'
      using errcode = 'GL068';
  end if;

  v_row := app.wsp_append_channel_consent(
    v_tenant, v_member.id, p_purpose, p_granted,
    btrim(p_notice_version), btrim(p_source), v_basis, v_staff.id, auth.uid()
  );
  insert into public.whatsapp_command_keys (request_key, tenant_id, domain, facts_digest, result_ref)
    values (p_request_key, v_tenant, 'consent', v_facts, v_row.id);

  return jsonb_build_object(
    'consentId', v_row.id, 'purpose', v_row.purpose,
    'granted', v_row.granted, 'noticeVersion', v_row.notice_version,
    'recordedAt', v_row.recorded_at
  );
end
$fn$;
revoke all on function public.record_whatsapp_consent(uuid, public.consent_purpose, boolean, text, text, uuid) from public, anon, service_role;
grant execute on function public.record_whatsapp_consent(uuid, public.consent_purpose, boolean, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Front-office operations reader (invoker facade + definer worker).
-- ---------------------------------------------------------------------------
create function app.read_whatsapp_operations_work(
  p_after_created_at timestamptz, p_after_id uuid, p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid := app.current_tenant_id();
  v_owner_view boolean := app.current_app_role()::text in ('gym_owner', 'gym_manager');
  v_rows jsonb;
  v_counts jsonb;
  v_blockers jsonb;
  v_wallet jsonb;
  v_totals jsonb;
  v_next_created timestamptz;
  v_next_id uuid;
begin
  perform app.wsp_front_office_actor(app.current_tenant_id());

  select jsonb_agg(r.row_data order by r.created_at desc, r.id desc)
    into v_rows
    from (
      select a.created_at, a.id,
        jsonb_build_object(
          'notificationId', a.notification_id,
          'memberId', a.member_id,
          'maskedPhone', '••••• ' || right(coalesce(app.member_contact_phone(a.tenant_id, a.member_id), ''), 3),
          'recipientBasis', case
            when app.member_is_minor_on(m.date_of_birth, app.gym_today(a.tenant_id)) then 'guardian'
            else 'self' end,
          'sentAt', a.accepted_at,
          'deliveredAt', (select min(rc.provider_event_at) from public.notification_whatsapp_receipts rc
                           where rc.attempt_id = a.id and rc.event_kind = 'delivered'),
          'providerReadAt', a.provider_read_at,
          'uncertain', a.uncertain_at is not null and (a.completed_at is null or a.released_at is null),
          'failureCode', a.failure_code,
          'releasedAt', a.released_at,
          'requestedAt', (select q.requested_at from public.whatsapp_dispatch_requests q
                           where q.tenant_id = a.tenant_id and q.notification_id = a.notification_id),
          'updatedAt', a.updated_at
        ) as row_data
      from public.notification_whatsapp_attempts a
      join public.members m on m.tenant_id = a.tenant_id and m.id = a.member_id
      where a.tenant_id = v_tenant
        and (p_after_created_at is null
             or (a.created_at, a.id) < (p_after_created_at, coalesce(p_after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
      order by a.created_at desc, a.id desc
      limit p_limit
    ) r;

  -- Serial amendment: the standardized envelope carries the channel-level
  -- status counts, active template blockers and (owner/manager only) the
  -- wallet and charged totals; desk contexts receive nulls for both.
  select jsonb_build_object(
      'accepted', (select count(*) from public.notification_whatsapp_attempts a2
                    where a2.tenant_id = v_tenant and a2.accepted_at is not null
                      and not exists (select 1 from public.notification_whatsapp_receipts rc
                                       where rc.attempt_id = a2.id and rc.event_kind = 'delivered')
                      and a2.provider_read_at is null)::text,
      'delivered', (select count(*) from public.notification_whatsapp_attempts a2
                     where a2.tenant_id = v_tenant and a2.accepted_at is not null
                       and exists (select 1 from public.notification_whatsapp_receipts rc
                                    where rc.attempt_id = a2.id and rc.event_kind = 'delivered')
                       and a2.provider_read_at is null)::text,
      'read', (select count(*) from public.notification_whatsapp_attempts a2
                where a2.tenant_id = v_tenant and a2.provider_read_at is not null)::text,
      'unknown', (select count(*) from public.notification_whatsapp_attempts a2
                   where a2.tenant_id = v_tenant and a2.uncertain_at is not null
                     and a2.completed_at is null)::text
    ) into v_counts;
  select coalesce(jsonb_agg(jsonb_build_object(
           'templateRevisionId', t.id, 'category', t.category,
           'reason', case
             when t.disabled_at is not null then 'template_disabled'
             when t.paused_at is not null then 'template_blocked'
             else 'template_unapproved' end)), '[]'::jsonb)
    into v_blockers
    from public.whatsapp_template_revisions t
   where t.tenant_id = v_tenant
     and (t.approved_at is null or t.paused_at is not null or t.disabled_at is not null);
  select jsonb_build_object('balancePaise', w.balance_paise::text, 'currency', 'INR')
    into v_wallet
    from public.messaging_wallets w where w.tenant_id = v_tenant;
  select jsonb_build_object(
           'chargedPaise', coalesce(sum(l.delta_paise), 0)::text, 'currency', 'INR')
    into v_totals
    from public.messaging_wallet_ledger l
   where l.tenant_id = v_tenant and l.delta_paise < 0
     and l.reason = 'whatsapp_transport_delivery';
  select a.created_at, a.id into v_next_created, v_next_id
    from public.notification_whatsapp_attempts a
   where a.tenant_id = v_tenant
     and (p_after_created_at is null
          or (a.created_at, a.id) < (p_after_created_at, coalesce(p_after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
   order by a.created_at desc, a.id desc
   limit 1 offset p_limit;

  return jsonb_build_object(
    'operations', coalesce(v_rows, '[]'::jsonb),
    'nextAfter', v_next_created::text,
    'nextAfterId', v_next_id,
    'statusCounts', coalesce(v_counts, jsonb_build_object('accepted','0','delivered','0','read','0','unknown','0')),
    'templateBlockers', coalesce(v_blockers, '[]'::jsonb),
    'wallet', case when v_owner_view then v_wallet else null end,
    'chargedTotals', case when v_owner_view then v_totals else null end
  );
end
$fn$;
alter function app.read_whatsapp_operations_work(timestamptz,uuid,integer) owner to postgres;
revoke all on function app.read_whatsapp_operations_work(timestamptz,uuid,integer) from public, anon;
grant execute on function app.read_whatsapp_operations_work(timestamptz,uuid,integer) to service_role, authenticated;

create function public.read_whatsapp_operations(
  p_after_created_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_limit integer := coalesce(p_limit, 50);
begin
  perform app.wsp_front_office_actor(app.current_tenant_id());
  if p_limit is not null and (p_limit < 1 or p_limit > 100) then
    raise exception 'The operations page limit is 1 through 100' using errcode = '22023';
  end if;
  return app.read_whatsapp_operations_work(p_after_created_at, p_after_id, v_limit);
end
$fn$;
revoke all on function public.read_whatsapp_operations(timestamp with time zone, uuid, integer) from public, anon, service_role;
grant execute on function public.read_whatsapp_operations(timestamp with time zone, uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Dispatch request (front-office queueing; no cost or recipient input).
-- ---------------------------------------------------------------------------
create function app.request_whatsapp_dispatch_work(
  p_notification_id uuid, p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid := app.current_tenant_id();
  v_actor public.staff := app.wsp_front_office_actor(v_tenant);
  v_row public.notifications;
  v_member public.members;
  v_org public.organizations;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_existing public.whatsapp_dispatch_requests;
begin
  if p_request_key is null then
    raise exception 'A dispatch request requires its request key' using errcode = '22023';
  end if;
  select n.* into v_row from public.notifications n
   where n.tenant_id = v_tenant and n.id = p_notification_id;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;
  if v_row.channel is distinct from 'in_app'::public.notification_channel
     or v_row.category is null
     or v_row.status not in ('scheduled'::public.notification_status, 'sent'::public.notification_status,
                             'delivered'::public.notification_status) then
    return jsonb_build_object('notificationId', v_row.id, 'queued', false, 'reason', 'notification_unavailable');
  end if;

  -- Exact-key replay is read before current-fact checks: a durable queue row
  -- replays its own queued=true regardless of what changed since.
  select r.* into v_existing from public.whatsapp_dispatch_requests r
   where r.tenant_id = v_tenant and r.notification_id = p_notification_id;
  if v_existing.id is not null then
    if v_existing.request_key = p_request_key then
      return jsonb_build_object('notificationId', v_row.id, 'queued', true, 'reason', null);
    end if;
    raise exception 'This notification already carries a different dispatch request'
      using errcode = 'GL068';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_tenant and m.id = v_row.member_id;
  select o.* into v_org from public.organizations o where o.id = v_tenant;
  if v_member.id is null
     or v_member.erased_at is not null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp())) then
    return jsonb_build_object('notificationId', v_row.id, 'queued', false, 'reason', 'recipient_ineligible');
  end if;

  v_purpose := app.notification_consent_purpose(v_row.category);
  select c.granted into v_granted from public.consents c
   where c.tenant_id = v_tenant and c.member_id = v_member.id and c.purpose = v_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;
  if coalesce(v_granted, false) is not true then
    return jsonb_build_object('notificationId', v_row.id, 'queued', false, 'reason', 'consent_withdrawn');
  end if;

  -- STRICT OPT-IN at request time (serial adjudication): the same predicate
  -- the claim enforces; a known refusal is queued=false with an allowlisted
  -- safe reason and no queue row is inserted.
  if not app.wsp_channel_consent_ok(v_tenant, v_member.id, v_purpose) then
    return jsonb_build_object('notificationId', v_row.id, 'queued', false, 'reason', 'consent_withdrawn');
  end if;

  -- An explicitly paused/disabled template (the newest revision for this
  -- category) is a known business refusal at request time; a missing or
  -- not-yet-approved template stays retryable and refuses only at claim.
  if exists (
    select 1 from public.whatsapp_template_revisions t
     where t.tenant_id = v_tenant
       and t.category = v_row.category::text
       and t.checked_at = (
         select max(t2.checked_at) from public.whatsapp_template_revisions t2
          where t2.tenant_id = v_tenant and t2.category = v_row.category::text)
       and (t.paused_at is not null or t.disabled_at is not null)
  ) then
    return jsonb_build_object('notificationId', v_row.id, 'queued', false, 'reason', 'template_blocked');
  end if;

  begin
    insert into public.whatsapp_dispatch_requests (tenant_id, notification_id, request_key, requested_by_staff_id)
      values (v_tenant, p_notification_id, p_request_key, v_actor.id);
  exception
    when unique_violation then
      -- A reused request key bound to a different notification is the same
      -- idempotency conflict the same-notification case raises; never a raw
      -- 23505 leak.
      raise exception 'This request key is already bound to another dispatch request'
        using errcode = 'GL068';
  end;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_tenant, auth.uid(), app.current_app_role()::public.app_role, app.current_impersonation_id(),
    'whatsapp_dispatch.requested', 'whatsapp_dispatch', p_notification_id,
    null,
    jsonb_build_object('requestKey', p_request_key, 'requestedBy', v_actor.id),
    null
  );

  return jsonb_build_object('notificationId', v_row.id, 'queued', true, 'reason', null);
end
$fn$;
alter function app.request_whatsapp_dispatch_work(uuid,uuid) owner to postgres;
revoke all on function app.request_whatsapp_dispatch_work(uuid,uuid) from public, anon, service_role;
grant execute on function app.request_whatsapp_dispatch_work(uuid,uuid) to authenticated;

create function public.request_whatsapp_dispatch(p_notification_id uuid, p_request_key uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_front_office_actor(app.current_tenant_id());
  return app.request_whatsapp_dispatch_work(p_notification_id, p_request_key);
end
$fn$;
revoke all on function public.request_whatsapp_dispatch(uuid, uuid) from public, anon, service_role;
grant execute on function public.request_whatsapp_dispatch(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Service transport: claim, authorize, acceptance, rejection, receipts.
-- ---------------------------------------------------------------------------
create function app.wsp_current_template_revision(p_tenant uuid, p_category text)
returns public.whatsapp_template_revisions
language sql
stable
security definer
set search_path = ''
as $fn$
  select t.* from public.whatsapp_template_revisions t
   where t.tenant_id = p_tenant
     and t.category = p_category
     and t.approved_at is not null
     and t.paused_at is null
     and t.disabled_at is null
   order by t.checked_at desc limit 1
$fn$;
alter function app.wsp_current_template_revision(uuid,text) owner to postgres;
revoke all on function app.wsp_current_template_revision(uuid,text) from public, anon, authenticated, service_role;

create function app.wsp_current_rate_version(p_tenant uuid, p_sender uuid)
returns public.whatsapp_rate_versions
language sql
stable
security definer
set search_path = ''
as $fn$
  select r.* from public.whatsapp_rate_versions r
   where r.tenant_id = p_tenant
     and r.sender_account_id = p_sender
     and r.effective_from <= clock_timestamp()
     and (r.effective_to is null or r.effective_to > clock_timestamp())
     and r.currency = 'INR'
   order by r.effective_from desc limit 1
$fn$;
alter function app.wsp_current_rate_version(uuid,uuid) owner to postgres;
revoke all on function app.wsp_current_rate_version(uuid,uuid) from public, anon, authenticated, service_role;

create function app.wsp_channel_consent_ok(p_tenant uuid, p_member uuid, p_purpose public.consent_purpose)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row public.whatsapp_channel_consents;
  v_member public.members;
  v_current_basis text;
begin
  select m.* into v_member from public.members m
   where m.tenant_id = p_tenant and m.id = p_member;
  if v_member.id is null then
    return false;
  end if;
  if app.member_is_minor_on(v_member.date_of_birth, app.gym_today(p_tenant))
     and app.member_guardian_complete(v_member) then
    v_current_basis := 'guardian';
  else
    v_current_basis := 'self';
  end if;
  if app.member_contact_phone(p_tenant, p_member) is null
     or btrim(app.member_contact_phone(p_tenant, p_member)) = '' then
    return false;
  end if;
  -- CURRENT = latest per member+purpose. The table is append-only, so ctid
  -- is the stable insertion order; uuid ids are not time-ordered and a
  -- same-recorded_at withdrawal must never lose the tiebreak to them.
  select c.* into v_row from public.whatsapp_channel_consents c
   where c.tenant_id = p_tenant and c.member_id = p_member and c.purpose = p_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;
  -- STRICT OPT-IN (serial adjudication): a missing row is no dispatch; the
  -- recorded consent must be granted for this purpose AND recorded for the
  -- recipient-phone basis (self or the complete guardian) the member and
  -- their contact currently resolve to.
  return v_row.id is not null
     and v_row.granted is true
     and v_row.recipient_basis = v_current_basis;
end
$fn$;
alter function app.wsp_channel_consent_ok(uuid,uuid,public.consent_purpose) owner to postgres;
revoke all on function app.wsp_channel_consent_ok(uuid,uuid,public.consent_purpose) from public, anon, authenticated, service_role;

create function app.wsp_describe_configuration()
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select case when exists (
    select 1 from public.whatsapp_sender_accounts a
     where a.enabled and a.compliance_approved_at is not null and a.template_ready_at is not null
  ) then 'ready' else 'provider_unconfigured' end
$fn$;
alter function app.wsp_describe_configuration() owner to postgres;
revoke all on function app.wsp_describe_configuration() from public, anon, authenticated, service_role;

create function app.claim_whatsapp_dispatch_work(p_batch_size integer)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_configuration text := app.wsp_describe_configuration();
  v_batch integer := 0;
  v_out jsonb := '[]'::jsonb;
  v_row record;
  v_template public.whatsapp_template_revisions;
  v_rate public.whatsapp_rate_versions;
  v_account public.whatsapp_sender_accounts;
  v_member public.members;
  v_org public.organizations;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_channel_latest public.whatsapp_channel_consents;
  v_contact text;
  v_balance bigint;
  v_holds numeric;
  v_available numeric;
  v_tariff bigint;
  v_attempt public.notification_whatsapp_attempts;
  v_tenant_budget integer;
  v_ticket uuid;
begin
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 50 then
    raise exception 'The WhatsApp claim batch is 1 through 50' using errcode = '22023';
  end if;
  if v_configuration = 'provider_unconfigured' then
    return jsonb_build_object('attempts', '[]'::jsonb, 'configuration', v_configuration);
  end if;

  for v_row in
    select r.tenant_id, n.id as notification_id, n.category, n.member_id,
           n.scheduled_for, n.created_at as source_created_at, r.request_key
      from public.whatsapp_dispatch_requests r
      join public.notifications n on n.tenant_id = r.tenant_id and n.id = r.notification_id
     where r.closed_at is null
       and not exists (
       select 1 from public.notification_whatsapp_attempts a
        where a.tenant_id = r.tenant_id and a.notification_id = r.notification_id
          and a.completed_at is null)
     order by r.tenant_id, n.scheduled_for, n.id
     for update of r skip locked
  loop
    exit when v_batch >= p_batch_size;
    v_tenant_budget := (select count(*) from public.notification_whatsapp_attempts a
      where a.tenant_id = v_row.tenant_id and a.created_at > clock_timestamp() - interval '60 seconds');
    if v_tenant_budget >= 30 then
      continue;
    end if;

    select a.* into v_account from public.whatsapp_sender_accounts a
     where a.tenant_id = v_row.tenant_id
       and a.enabled and a.compliance_approved_at is not null and a.template_ready_at is not null
     order by a.id limit 1;
    if v_account.id is null then
      continue;
    end if;
    v_template := app.wsp_current_template_revision(v_row.tenant_id, v_row.category::text);
    if v_template.id is null or v_template.sender_account_id is distinct from v_account.id then
      continue;
    end if;
    v_rate := app.wsp_current_rate_version(v_row.tenant_id, v_account.id);
    if v_rate.id is null then
      continue;
    end if;
    -- Enablement cutoff: a source event created before the account became
    -- template-ready is never dispatched (no historical backfill).
    if v_row.source_created_at < least(v_account.compliance_approved_at, v_account.template_ready_at) then
      continue;
    end if;

    select m.* into v_member from public.members m
     where m.tenant_id = v_row.tenant_id and m.id = v_row.member_id;
    select o.* into v_org from public.organizations o where o.id = v_row.tenant_id;
    if v_member.id is null
       or v_member.erased_at is not null
       or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       or v_org.id is null
       or not (v_org.status = 'active'::public.organization_status
               or (v_org.status = 'trial'::public.organization_status
                   and v_org.trial_ends_at is not null
                   and v_org.trial_ends_at > statement_timestamp())) then
      -- A permanently ineligible recipient cannot retry forever: the queue
      -- row closes with its reason and the source records opted_out on the
      -- legal graph edge where it can.
      perform app.wsp_close_queue_row(v_row.tenant_id, v_row.notification_id);
      perform app.wsp_mark_source_opted_out(v_row.tenant_id, v_row.notification_id, 'recipient_ineligible');
      continue;
    end if;

    v_purpose := app.notification_consent_purpose(v_row.category);
    select c.granted into v_granted from public.consents c
     where c.tenant_id = v_row.tenant_id and c.member_id = v_member.id and c.purpose = v_purpose
     order by c.recorded_at desc, c.ctid desc limit 1;
    if coalesce(v_granted, false) is not true then
      -- Withdrawn purpose consent never retries: the queue row closes and
      -- the source records the refusal on its legal graph edge.
      perform app.wsp_close_queue_row(v_row.tenant_id, v_row.notification_id);
      perform app.wsp_mark_source_opted_out(v_row.tenant_id, v_row.notification_id, 'consent_withdrawn');
      continue;
    end if;

    -- STRICT OPT-IN (serial adjudication): a missing channel-consent row is
    -- no dispatch; the consent must be currently granted for this purpose
    -- and for the recipient the member currently resolves to. A permanent
    -- channel refusal closes the queued request exactly like a withdrawal.
    if not app.wsp_channel_consent_ok(v_row.tenant_id, v_member.id, v_purpose) then
      perform app.wsp_close_queue_row(v_row.tenant_id, v_row.notification_id);
      perform app.wsp_mark_source_opted_out(v_row.tenant_id, v_row.notification_id, 'consent_withdrawn');
      continue;
    end if;

    v_contact := app.member_contact_phone(v_row.tenant_id, v_member.id);
    if v_contact is null or btrim(v_contact) = '' then
      continue;
    end if;

    select w.balance_paise into v_balance
      from public.messaging_wallets w
     where w.tenant_id = v_row.tenant_id
     for update;
    if v_balance is null then
      continue;
    end if;
    v_holds := coalesce((select sum(a.hold_max_paise::numeric) from public.notification_whatsapp_attempts a
      where a.tenant_id = v_row.tenant_id and a.released_at is null), 0::numeric);
    v_tariff := v_rate.max_amount_paise;
    v_available := v_balance::numeric - v_holds;
    if v_available < v_tariff::numeric then
      continue;
    end if;

    v_ticket := gen_random_uuid();
    insert into public.notification_whatsapp_attempts (
      tenant_id, member_id, notification_id, sender_account_id,
      template_revision_id, rate_version_id, consent_id, request_key,
      lease_ticket, lease_expires_at, recipient_contact_revision,
      hold_max_paise, hold_currency
    ) values (
      v_row.tenant_id, v_member.id, v_row.notification_id, v_account.id,
      v_template.id, v_rate.id,
      (select c.id from public.consents c
        where c.tenant_id = v_row.tenant_id and c.member_id = v_member.id
          and c.purpose = v_purpose
        order by c.recorded_at desc, c.id desc limit 1),
      case
        when not exists (
          select 1 from public.notification_whatsapp_attempts a2
           where a2.tenant_id = v_row.tenant_id and a2.notification_id = v_row.notification_id)
        then v_row.request_key
        else uuid(md5(v_row.request_key::text || ':' || (select count(*)::text
               from public.notification_whatsapp_attempts a3
              where a3.tenant_id = v_row.tenant_id and a3.notification_id = v_row.notification_id)))
      end,
      v_ticket, clock_timestamp() + interval '120 seconds',
      encode(pg_catalog.sha256(pg_catalog.convert_to(v_contact, 'UTF8')), 'hex'),
      v_tariff, 'INR'
    ) returning * into v_attempt;

    insert into public.audit_log (
      tenant_id, actor_user_id, actor_role, impersonation_session_id,
      action, record_type, record_id, before, after, reason
    ) values (
      v_row.tenant_id, null, null, null,
      'whatsapp_attempt.claimed', 'whatsapp_attempt', v_attempt.id,
      null,
      jsonb_build_object('notificationId', v_row.notification_id, 'holdPaise', v_tariff::text),
      null
    );

    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'attemptId', v_attempt.id,
      'ticket', v_attempt.lease_ticket::text,
      'expiresAt', v_attempt.lease_expires_at
    ));
    v_batch := v_batch + 1;
  end loop;

  return jsonb_build_object('attempts', v_out, 'configuration', v_configuration);
end
$fn$;
alter function app.claim_whatsapp_dispatch_work(integer) owner to postgres;
revoke all on function app.claim_whatsapp_dispatch_work(integer) from public, anon;
grant execute on function app.claim_whatsapp_dispatch_work(integer) to service_role;

create function public.claim_whatsapp_dispatch(p_batch_size integer)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_service_context();
  return app.claim_whatsapp_dispatch_work(p_batch_size);
end
$fn$;
revoke all on function public.claim_whatsapp_dispatch(integer) from public, anon, authenticated, service_role;
grant execute on function public.claim_whatsapp_dispatch(integer) to service_role;

create function app.wsp_close_refused_attempt(p_attempt_id uuid, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant_id uuid;
  v_notification_id uuid;
begin
  update public.notification_whatsapp_attempts a
     set failure_code = substr(btrim(p_reason), 1, 64),
         completed_at = clock_timestamp(),
         released_at = clock_timestamp()
   where a.id = p_attempt_id and a.completed_at is null
     returning tenant_id, notification_id into v_tenant_id, v_notification_id;
  if v_tenant_id is not null then
    perform app.wsp_close_queue_row(v_tenant_id, v_notification_id);
  end if;
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  )
  select a.tenant_id, null, null, null,
    'whatsapp_attempt.refused', 'whatsapp_attempt', p_attempt_id,
    null,
    jsonb_build_object('reason', btrim(p_reason)),
    null
    from public.notification_whatsapp_attempts a
   where a.id = p_attempt_id;
end
$fn$;
alter function app.wsp_close_refused_attempt(uuid,text) owner to postgres;
revoke all on function app.wsp_close_refused_attempt(uuid,text) from public, anon, authenticated, service_role;

create function app.authorize_whatsapp_dispatch_work(p_attempt_id uuid, p_ticket uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_whatsapp_attempts;
  v_member public.members;
  v_org public.organizations;
  v_row public.notifications;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_channel_latest public.whatsapp_channel_consents;
  v_rate public.whatsapp_rate_versions;
  v_template public.whatsapp_template_revisions;
  v_account public.whatsapp_sender_accounts;
  v_contact text;
  v_refusal jsonb;
begin
  select a.* into v_attempt from public.notification_whatsapp_attempts a
   where a.id = p_attempt_id
   for update;
  if not found then
    raise exception 'Dispatch attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.lease_ticket is distinct from p_ticket then
    raise exception 'Authorization requires this attempt''s current lease ticket'
      using errcode = 'GL120';
  end if;
  if v_attempt.io_started_at is not null then
    raise exception 'Authorization cannot grant a second send'
      using errcode = 'GL120';
  end if;
  if clock_timestamp() > v_attempt.lease_expires_at then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'lease_expired');
    raise exception 'The authorization lease has expired' using errcode = 'GL120';
  end if;

  select n.* into v_row from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;
  select m.* into v_member from public.members m
   where m.tenant_id = v_attempt.tenant_id and m.id = v_attempt.member_id;
  select o.* into v_org from public.organizations o where o.id = v_attempt.tenant_id;

  if v_row.id is null
     or v_row.status not in ('scheduled'::public.notification_status, 'sent'::public.notification_status,
                             'delivered'::public.notification_status)
     or v_member.id is null
     or v_member.erased_at is not null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp())) then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'not_dispatchable');
    raise exception 'The attempt is no longer dispatchable' using errcode = 'GL119';
  end if;

  v_purpose := app.notification_consent_purpose(v_row.category);
  select c.granted into v_granted from public.consents c
   where c.tenant_id = v_attempt.tenant_id and c.member_id = v_member.id and c.purpose = v_purpose
   order by c.recorded_at desc, c.ctid desc limit 1;
  if coalesce(v_granted, false) is not true
     or not app.wsp_channel_consent_ok(v_attempt.tenant_id, v_member.id, v_purpose) then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'consent_withdrawn');
    -- WSP-003: a withdrawal (or a missing strict opt-in) decided before
    -- authorization is recorded on the current graph; the held funds were
    -- released above.
    select n.* into v_row from public.notifications n
     where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
     for update;
    if v_row.status = 'sent'::public.notification_status then
      -- sent has no opted_out edge in the canonical graph; the refusal is
      -- recorded as the terminal failure reason instead.
      update public.notifications n
         set status = 'failed'::public.notification_status,
             failed_reason = 'consent_withdrawn'
       where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;
    end if;
    return jsonb_build_object(
      'authorized', false, 'attemptId', v_attempt.id, 'ticket', v_attempt.lease_ticket::text,
      'reason', 'consent_withdrawn', 'deferredUntil', null, 'recipient', null
    );
  end if;

  select a.* into v_account from public.whatsapp_sender_accounts a
   where a.tenant_id = v_attempt.tenant_id and a.id = v_attempt.sender_account_id
     and a.enabled and a.compliance_approved_at is not null and a.template_ready_at is not null;
  if v_account.id is null then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'sender_unavailable');
    return jsonb_build_object(
      'authorized', false, 'attemptId', v_attempt.id, 'ticket', v_attempt.lease_ticket::text,
      'reason', 'sender_unavailable', 'deferredUntil', null, 'recipient', null
    );
  end if;
  select t.* into v_template from public.whatsapp_template_revisions t
   where t.tenant_id = v_attempt.tenant_id and t.id = v_attempt.template_revision_id
     and t.approved_at is not null and t.paused_at is null and t.disabled_at is null;
  if v_template.id is null then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'template_blocked');
    return jsonb_build_object(
      'authorized', false, 'attemptId', v_attempt.id, 'ticket', v_attempt.lease_ticket::text,
      'reason', 'template_blocked', 'deferredUntil', null, 'recipient', null
    );
  end if;
  select r.* into v_rate from public.whatsapp_rate_versions r
   where r.tenant_id = v_attempt.tenant_id and r.id = v_attempt.rate_version_id
     and r.currency = 'INR'
     and r.effective_from <= clock_timestamp()
     and (r.effective_to is null or r.effective_to > clock_timestamp());
  if v_rate.id is null then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'rate_unavailable');
    return jsonb_build_object(
      'authorized', false, 'attemptId', v_attempt.id, 'ticket', v_attempt.lease_ticket::text,
      'reason', 'rate_unavailable', 'deferredUntil', null, 'recipient', null
    );
  end if;

  v_contact := app.member_contact_phone(v_attempt.tenant_id, v_member.id);
  if v_contact is null or btrim(v_contact) = '' then
    perform app.wsp_close_refused_attempt(v_attempt.id, 'recipient_unresolved');
    return jsonb_build_object(
      'authorized', false, 'attemptId', v_attempt.id, 'ticket', v_attempt.lease_ticket::text,
      'reason', 'recipient_unresolved', 'deferredUntil', null, 'recipient', null
    );
  end if;

  update public.notification_whatsapp_attempts a
     set authorized_at = clock_timestamp(),
         io_started_at = clock_timestamp()
   where a.id = v_attempt.id
   returning * into v_attempt;

  -- The transport child of the source: frozen key whatsapp-paid:<source>,
  -- an unchanged mirror of the source's identity INCLUDING its template
  -- fields (a renewal source mirrors 'renewal_reminder'; a null mirrors
  -- null), created scheduled and marked sent only by the provider-acceptance
  -- evidence (branch (b)).
  insert into public.notifications (
    tenant_id, member_id, channel, status, template_key, template_id,
    category, related_type, related_id, dedupe_key, scheduled_for,
    payload, recipient_phone, source_notification_id
  )
  select n.tenant_id, n.member_id, 'whatsapp_link'::public.notification_channel,
         'scheduled'::public.notification_status, n.template_key, n.template_id,
         n.category, n.related_type, n.related_id,
         'whatsapp-paid:' || n.id::text, statement_timestamp(),
         n.payload, app.member_contact_phone(n.tenant_id, n.member_id), n.id
    from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
  on conflict (tenant_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_attempt.tenant_id, null, null, null,
    'whatsapp_attempt.authorized', 'whatsapp_attempt', v_attempt.id,
    null,
    jsonb_build_object('notificationId', v_attempt.notification_id),
    null
  );

  -- SEAM GAP (reported): the paid whatsapp_link child insert belongs here and
  -- needs the shared enforce_notification extension; without it we do NOT
  -- forge the row, and we do not forge claims in the JWT to sneak past the
  -- front-office-only INSERT guard.

  return jsonb_build_object(
    'authorized', true,
    'attemptId', v_attempt.id,
    'ticket', v_attempt.lease_ticket::text,
    'expiresAt', v_attempt.lease_expires_at,
    'senderAccountId', v_account.id,
    'templateRevisionId', v_template.id,
    'rateVersionId', v_rate.id,
    'recipient', v_contact,
    'template', jsonb_build_object(
      'name', v_template.provider_template_name,
      'locale', v_template.locale,
      'parameters', jsonb_build_array(null::text)
    )
  );
end
$fn$;
alter function app.authorize_whatsapp_dispatch_work(uuid,uuid) owner to postgres;
revoke all on function app.authorize_whatsapp_dispatch_work(uuid,uuid) from public, anon;
grant execute on function app.authorize_whatsapp_dispatch_work(uuid,uuid) to service_role;


create function public.authorize_whatsapp_dispatch(p_attempt_id uuid, p_ticket uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_service_context();
  return app.authorize_whatsapp_dispatch_work(p_attempt_id, p_ticket);
end
$fn$;
revoke all on function public.authorize_whatsapp_dispatch(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.authorize_whatsapp_dispatch(uuid, uuid) to service_role;

create function app.record_whatsapp_acceptance_work(
  p_attempt_id uuid, p_ticket uuid, p_provider_message_id text, p_evidence_digest text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_whatsapp_attempts;
  v_source public.notifications;
begin
  select a.* into v_attempt from public.notification_whatsapp_attempts a
   where a.id = p_attempt_id;
  if not found then
    raise exception 'Dispatch attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.lease_ticket is distinct from p_ticket then
    raise exception 'Acceptance requires this attempt''s current lease ticket'
      using errcode = 'GL120';
  end if;
  if v_attempt.io_started_at is null then
    raise exception 'Acceptance requires a ticket-initiated send'
      using errcode = 'GL120';
  end if;
  if p_provider_message_id is null or btrim(p_provider_message_id) = ''
     or char_length(btrim(p_provider_message_id)) > 256 then
    raise exception 'Acceptance requires the provider message id' using errcode = '22023';
  end if;
  if p_evidence_digest is null or btrim(p_evidence_digest) = ''
     or char_length(btrim(p_evidence_digest)) > 256 then
    raise exception 'Acceptance requires its evidence digest' using errcode = '22023';
  end if;
  if v_attempt.accepted_at is not null then
    if v_attempt.provider_message_id = btrim(p_provider_message_id) then
      return jsonb_build_object('attemptId', v_attempt.id, 'replayed', true,
        'notification', app.notification_result_json(
          (select n from public.notifications n
            where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id)));
    end if;
    raise exception 'This attempt already carries a different provider acceptance'
      using errcode = 'GL068';
  end if;

  update public.notification_whatsapp_attempts a
     set accepted_at = clock_timestamp(),
         provider_message_id = btrim(p_provider_message_id)
   where a.id = v_attempt.id
   returning * into v_attempt;

  -- The paid child carries the acceptance: scheduled→sent under the same
  -- durable attempt evidence the envelope guard requires.
  update public.notifications c
     set status = 'sent'::public.notification_status
   where c.tenant_id = v_attempt.tenant_id
     and c.channel = 'whatsapp_link'::public.notification_channel
     and c.dedupe_key = 'whatsapp-paid:' || v_attempt.notification_id::text
     and c.status = 'scheduled'::public.notification_status;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_attempt.tenant_id, null, null, null,
    'whatsapp_attempt.accepted', 'whatsapp_attempt', v_attempt.id,
    null,
    jsonb_build_object('notificationId', v_attempt.notification_id,
                       'accepted', true),
    null
  );

  select n.* into v_source from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;

  return jsonb_build_object('attemptId', v_attempt.id, 'replayed', false,
    'notification', app.notification_result_json(v_source));
end
$fn$;
alter function app.record_whatsapp_acceptance_work(uuid,uuid,text,text) owner to postgres;
revoke all on function app.record_whatsapp_acceptance_work(uuid,uuid,text,text) from public, anon;
grant execute on function app.record_whatsapp_acceptance_work(uuid,uuid,text,text) to service_role;

create function public.record_whatsapp_acceptance(p_attempt_id uuid, p_ticket uuid, p_provider_message_id text, p_evidence_digest text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_service_context();
  return app.record_whatsapp_acceptance_work(p_attempt_id, p_ticket, p_provider_message_id, p_evidence_digest);
end
$fn$;
revoke all on function public.record_whatsapp_acceptance(uuid, uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.record_whatsapp_acceptance(uuid, uuid, text, text) to service_role;

-- One locked writer for the causal transport debit. It deliberately does not
-- route through app.record_wallet_movement: that path requires a signed-in
-- super-admin actor by design (the frozen conversion unit), which a transport
-- context cannot supply without weakening identity checks. This writer keeps
-- the same locked ledger-backed balance, the same arithmetic, the same audit
-- shape, and the same append-only and evidence guards, and is flagged to the
-- orchestrator for the serial-owner decision.
-- Serial amendment (coordinator adjudication, 2026-10-03): the frozen
-- service-only causal debit writer. It binds causally by attempt id alone and
-- derives tenant, source notification and tariff server-side from locked
-- rows; no amount, tenant or recipient can ever arrive from request, webhook
-- or client data. The same locked ledger-backed balance, arithmetic, audit
-- shape and evidence guards as the conversion unit; exactly one movement per
-- attempt. app.record_wallet_movement remains the sole user-actor path.
create function app.apply_whatsapp_transport_debit(p_attempt_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_whatsapp_attempts;
  v_rate public.whatsapp_rate_versions;
  v_balance bigint;
  v_new_balance numeric;
  v_new_balance_bigint bigint;
  v_ledger_id uuid;
  v_amount bigint;
begin
  if p_attempt_id is null then
    raise exception 'A causal debit requires its attempt' using errcode = '22023';
  end if;
  select a.* into v_attempt from public.notification_whatsapp_attempts a
   where a.id = p_attempt_id
   for update;
  if not found then
    raise exception 'Dispatch attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.accepted_at is null then
    raise exception 'A causal debit requires a verified attempt acceptance'
      using errcode = 'GL121';
  end if;
  if v_attempt.charged_ledger_id is not null then
    return jsonb_build_object('ledgerId', v_attempt.charged_ledger_id,
      'debitedPaise', (select (-l.delta_paise)::text from public.messaging_wallet_ledger l
                        where l.id = v_attempt.charged_ledger_id),
      'currency', 'INR');
  end if;
  select r.* into v_rate from public.whatsapp_rate_versions r
   where r.tenant_id = v_attempt.tenant_id and r.id = v_attempt.rate_version_id;
  if v_rate.id is null or v_rate.currency is distinct from 'INR'
     or v_rate.amount_paise is null or v_rate.amount_paise < 0::bigint then
    raise exception 'The causal debit tariff is missing or not INR'
      using errcode = 'GL121';
  end if;
  v_amount := v_rate.amount_paise;
  if v_amount = 0::bigint then
    return jsonb_build_object('ledgerId', null, 'debitedPaise', '0', 'currency', 'INR');
  end if;
  select w.balance_paise into v_balance
    from public.messaging_wallets w
   where w.tenant_id = v_attempt.tenant_id
   for update;
  if v_balance is null then
    raise exception 'A causal debit requires its locked wallet'
      using errcode = 'GL121';
  end if;
  v_new_balance := v_balance::numeric - v_amount::numeric;
  if v_new_balance < 0::numeric then
    raise exception 'The transport debit would drive the wallet below zero'
      using errcode = 'GL121';
  end if;
  v_new_balance_bigint := v_new_balance::bigint;

  insert into public.messaging_wallet_ledger (
    tenant_id, delta_paise, currency, reason, notification_id, request_key,
    recorded_by_user_id, balance_after_paise
  ) values (
    v_attempt.tenant_id, (-v_amount), 'INR', 'whatsapp_transport_delivery',
    v_attempt.notification_id, v_attempt.id,
    null, v_new_balance_bigint
  ) returning id into v_ledger_id;

  update public.messaging_wallets w
     set balance_paise = v_new_balance_bigint
   where w.tenant_id = v_attempt.tenant_id;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_attempt.tenant_id, null, null, null,
    'messaging_wallet.debited', 'messaging_wallet', v_attempt.tenant_id,
    jsonb_build_object('balance_paise', v_balance::text, 'currency', 'INR'),
    jsonb_build_object(
      'balance_paise', v_new_balance_bigint::text, 'currency', 'INR',
      'ledger_id', v_ledger_id, 'delta_paise', (-v_amount)::text,
      'notification_id', v_attempt.notification_id, 'request_key', v_attempt.id,
      'recorded_by_user_id', null
    ),
    'whatsapp_transport_delivery'
  );

  return jsonb_build_object('ledgerId', v_ledger_id, 'debitedPaise', (-v_amount)::text, 'currency', 'INR');
end
$fn$;
alter function app.apply_whatsapp_transport_debit(uuid) owner to postgres;
revoke all on function app.apply_whatsapp_transport_debit(uuid) from public, anon, authenticated;
grant execute on function app.apply_whatsapp_transport_debit(uuid) to service_role;

create function app.record_whatsapp_receipt_work(
  p_sender_account_id uuid, p_provider_message_id text, p_receipt_fingerprint text,
  p_event_kind text, p_provider_at timestamptz, p_evidence_digest text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_account public.whatsapp_sender_accounts;
  v_attempt public.notification_whatsapp_attempts;
  v_source public.notifications;
  v_rate public.whatsapp_rate_versions;
  v_existing public.notification_whatsapp_receipts;
  v_debit jsonb;
  v_replayed boolean := false;
begin
  select a.* into v_account from public.whatsapp_sender_accounts a
   where a.id = p_sender_account_id;
  if not found then
    raise exception 'Sender account not found' using errcode = 'P0002';
  end if;
  if p_event_kind is null or p_event_kind::text not in ('delivered', 'read', 'failed') then
    raise exception 'Receipt kinds are delivered, read or failed' using errcode = '22023';
  end if;
  if p_provider_message_id is null or btrim(p_provider_message_id) = ''
     or char_length(btrim(p_provider_message_id)) > 256 then
    raise exception 'A receipt requires its provider message id' using errcode = '22023';
  end if;
  if p_receipt_fingerprint is null or btrim(p_receipt_fingerprint) = ''
     or char_length(btrim(p_receipt_fingerprint)) > 128 then
    raise exception 'A receipt requires its fingerprint' using errcode = '22023';
  end if;
  if p_evidence_digest is null or btrim(p_evidence_digest) = ''
     or char_length(btrim(p_evidence_digest)) > 256 then
    raise exception 'A receipt requires its verified evidence digest' using errcode = '22023';
  end if;
  if p_provider_at is null
     or p_provider_at > clock_timestamp() + interval '5 minutes'
     or p_provider_at < clock_timestamp() - interval '30 days' then
    raise exception 'The receipt timestamp is outside the accepted window' using errcode = '22023';
  end if;

  select a.* into v_attempt from public.notification_whatsapp_attempts a
   where a.sender_account_id = p_sender_account_id
     and a.provider_message_id = btrim(p_provider_message_id)
     and a.accepted_at is not null;
  if not found then
    raise exception 'A receipt requires a matching accepted attempt'
      using errcode = 'GL122';
  end if;

  select rc.* into v_existing from public.notification_whatsapp_receipts rc
   where rc.sender_account_id = p_sender_account_id
     and rc.receipt_fingerprint = btrim(p_receipt_fingerprint);
  if v_existing.id is not null then
    if v_existing.attempt_id is distinct from v_attempt.id then
      raise exception 'This receipt fingerprint belongs to another attempt'
        using errcode = 'GL122';
    end if;
    select n.* into v_source from public.notifications n
     where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;
    return jsonb_build_object(
      'attemptId', v_attempt.id, 'replayed', true, 'applied', false,
      'notification', app.notification_result_json(v_source),
      'ledgerId', v_attempt.charged_ledger_id,
      'debitedPaise', case when v_attempt.charged_ledger_id is null then '0'
                           else (select (-l.delta_paise)::text from public.messaging_wallet_ledger l
                                  where l.id = v_attempt.charged_ledger_id) end,
      'currency', 'INR'
    );
  end if;

  select r.* into v_rate from public.whatsapp_rate_versions r
   where r.tenant_id = v_attempt.tenant_id and r.id = v_attempt.rate_version_id;

  insert into public.notification_whatsapp_receipts (
    tenant_id, attempt_id, sender_account_id, receipt_fingerprint, event_kind,
    provider_event_at, evidence_digest, billing_category, billing_evidence_ref
  ) values (
    v_attempt.tenant_id, v_attempt.id, p_sender_account_id, btrim(p_receipt_fingerprint),
    p_event_kind, p_provider_at, btrim(p_evidence_digest),
    v_rate.provider_category, v_rate.id::text
  );

  if p_event_kind = 'read' then
    if v_attempt.provider_read_at is null or p_provider_at > v_attempt.provider_read_at then
      update public.notification_whatsapp_attempts a
         set provider_read_at = greatest(coalesce(a.provider_read_at, p_provider_at), p_provider_at)
       where a.id = v_attempt.id
       returning * into v_attempt;
    end if;
    -- 'delivered' branch: after the receipt and debit are durable, advance
    -- the source in-app row on the delivery evidence (envelope branch (c)).
  elsif p_event_kind = 'delivered' and v_attempt.charged_ledger_id is null
     and v_attempt.completed_at is null then
    -- A delivered receipt after a terminal rejection (reconciled or failed)
    -- is retained above for reconciliation but must never create a ledger
    -- movement: the debit gates on the attempt still being live.
    v_debit := app.apply_whatsapp_transport_debit(v_attempt.id);
    if (v_debit ->> 'ledgerId') is not null then
      update public.notification_whatsapp_attempts a
         set charged_ledger_id = (v_debit ->> 'ledgerId')::uuid,
             completed_at = clock_timestamp(),
             released_at = clock_timestamp()
       where a.id = v_attempt.id
       returning * into v_attempt;
    else
      update public.notification_whatsapp_attempts a
         set completed_at = clock_timestamp(), released_at = clock_timestamp()
       where a.id = v_attempt.id
       returning * into v_attempt;
    end if;
    perform app.wsp_close_queue_row(v_attempt.tenant_id, v_attempt.notification_id);
    -- Branch (c): the delivery receipt row

    select n.* into v_source from public.notifications n
     where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
     for update;
    if v_source.id is not null and v_source.status = 'sent'::public.notification_status then
      update public.notifications n
         set status = 'delivered'::public.notification_status
       where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
       returning * into v_source;
    end if;
    -- Branch (c): the delivery receipt row is the service-context evidence
    -- for the source in-app row's legal sent-delivered edge. Provider reads
    -- never fabricate clicks and never touch converted_at.
  end if;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_attempt.tenant_id, null, null, null,
    'whatsapp_receipt.recorded', 'whatsapp_attempt', v_attempt.id,
    null,
    jsonb_build_object('eventKind', p_event_kind, 'charged', (v_debit ->> 'debitedPaise')),
    null
  );

  select n.* into v_source from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;

  return jsonb_build_object(
    'attemptId', v_attempt.id, 'replayed', v_replayed, 'applied', true,
    'notification', app.notification_result_json(v_source),
    'ledgerId', v_debit ->> 'ledgerId',
    'debitedPaise', v_debit ->> 'debitedPaise',
    'currency', 'INR'
  );
end
$fn$;
alter function app.record_whatsapp_receipt_work(uuid,text,text,text,timestamptz,text) owner to postgres;
revoke all on function app.record_whatsapp_receipt_work(uuid,text,text,text,timestamptz,text) from public, anon;
grant execute on function app.record_whatsapp_receipt_work(uuid,text,text,text,timestamptz,text) to service_role;

create function public.record_whatsapp_receipt(
  p_sender_account_id uuid, p_provider_message_id text, p_receipt_fingerprint text,
  p_event_kind text, p_provider_at timestamptz, p_evidence_digest text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_service_context();
  return app.record_whatsapp_receipt_work(p_sender_account_id, p_provider_message_id,
    p_receipt_fingerprint, p_event_kind, p_provider_at, p_evidence_digest);
end
$fn$;
revoke all on function public.record_whatsapp_receipt(uuid, text, text, text, timestamp with time zone, text) from public, anon, authenticated, service_role;
grant execute on function public.record_whatsapp_receipt(uuid, text, text, text, timestamp with time zone, text) to service_role;

create function app.finish_whatsapp_rejection_work(
  p_attempt_id uuid, p_ticket uuid, p_failure_code text, p_outcome_known boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_whatsapp_attempts;
  v_source public.notifications;
  v_was_uncertain boolean;
begin
  select a.* into v_attempt from public.notification_whatsapp_attempts a
   where a.id = p_attempt_id;
  if not found then
    raise exception 'Dispatch attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.lease_ticket is distinct from p_ticket then
    raise exception 'Rejection requires this attempt''s current lease ticket'
      using errcode = 'GL120';
  end if;
  if p_outcome_known is null then
    raise exception 'The outcome must be stated as known or unknown' using errcode = '22023';
  end if;

  v_was_uncertain := v_attempt.uncertain_at is not null and v_attempt.completed_at is null;

  if p_outcome_known then
    if p_failure_code is null or btrim(p_failure_code) = ''
       or btrim(p_failure_code) not in ('recipient_invalid', 'provider_rejected', 'template_blocked',
                                        'rate_limited', 'account_mismatch', 'unknown') then
      raise exception 'A known rejection requires one of the allowlisted failure codes'
        using errcode = '22023';
    end if;
    if v_attempt.completed_at is not null then
      if v_attempt.failure_code = btrim(p_failure_code) and v_attempt.released_at is not null then
        return jsonb_build_object('attemptId', v_attempt.id, 'replayed', true,
          'notification', app.notification_result_json(
            (select n from public.notifications n
              where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id)));
      end if;
      raise exception 'This attempt already carries a different final result'
        using errcode = 'GL068';
    end if;

    update public.notification_whatsapp_attempts a
       set failure_code = btrim(p_failure_code),
           completed_at = clock_timestamp(),
           released_at = clock_timestamp()
     where a.id = v_attempt.id
     returning * into v_attempt;
    perform app.wsp_close_queue_row(v_attempt.tenant_id, v_attempt.notification_id);

    -- Known rejection: the source in-app row moves through the legal
    -- sent→failed edge with the attempt's failure as its reason evidence.
    select n.* into v_source from public.notifications n
     where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
     for update;
    if v_source.id is not null and v_source.status = 'sent'::public.notification_status then
      update public.notifications n
         set status = 'failed'::public.notification_status,
             failed_reason = btrim(p_failure_code)
       where n.tenant_id = v_attempt.tenant_id and n.id = v_source.id
       returning * into v_source;
    end if;

    -- The never-sent paid child terminalizes with the same reason; it cannot
    -- linger scheduled forever after a known rejection.
    update public.notifications c
       set status = 'failed'::public.notification_status,
           failed_reason = btrim(p_failure_code)
     where c.tenant_id = v_attempt.tenant_id
       and c.channel = 'whatsapp_link'::public.notification_channel
       and c.dedupe_key = 'whatsapp-paid:' || v_attempt.notification_id::text
       and c.status = 'scheduled'::public.notification_status;

    -- The in-app fallback child (frozen key whatsapp-fallback:<source>) is
    -- the separate causal row WSP-009 names; never charged, mirrored to the
    -- source, admitted by the envelope's fallback branch.
    insert into public.notifications (
      tenant_id, member_id, channel, status, template_key, template_id,
      category, related_type, related_id, dedupe_key, scheduled_for,
      payload, source_notification_id
    )
    select n.tenant_id, n.member_id, 'in_app'::public.notification_channel,
           'scheduled'::public.notification_status, null, null,
           n.category, n.related_type, n.related_id,
           'whatsapp-fallback:' || n.id::text, statement_timestamp(),
           n.payload, n.id
      from public.notifications n
     where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
    on conflict (tenant_id, dedupe_key) where dedupe_key is not null do nothing;

    insert into public.audit_log (
      tenant_id, actor_user_id, actor_role, impersonation_session_id,
      action, record_type, record_id, before, after, reason
    ) values (
      v_attempt.tenant_id, null, null, null,
      'whatsapp_attempt.rejected', 'whatsapp_attempt', v_attempt.id,
      null,
      jsonb_build_object('notificationId', v_attempt.notification_id, 'failureCode', btrim(p_failure_code),
                         'reconciled', v_was_uncertain),
      null
    );

    -- SEAM GAP (reported): the in-app fallback child
    -- (whatsapp-fallback:<source_notification_id>) is a separate causal row
    -- whose INSERT is blocked by the renewal-reserved identity branch of
    -- app.enforce_notification until the orchestrator authorizes the seam
    -- extension. The hold release above is the durable truth already saved.

    return jsonb_build_object('attemptId', v_attempt.id, 'replayed', false,
      'notification', app.notification_result_json(v_source));
  end if;

  if p_failure_code is not null then
    raise exception 'An unknown outcome carries no failure code' using errcode = '22023';
  end if;
  if v_attempt.completed_at is not null then
    raise exception 'A closed attempt cannot return to uncertainty'
      using errcode = 'GL068';
  end if;
  if v_attempt.uncertain_at is not null then
    return jsonb_build_object('attemptId', v_attempt.id, 'replayed', true,
      'notification', app.notification_result_json(
        (select n from public.notifications n
          where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id)));
  end if;

  update public.notification_whatsapp_attempts a
     set uncertain_at = clock_timestamp()
   where a.id = v_attempt.id
   returning * into v_attempt;
  perform app.wsp_close_queue_row(v_attempt.tenant_id, v_attempt.notification_id);

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    v_attempt.tenant_id, null, null, null,
    'whatsapp_attempt.uncertain', 'whatsapp_attempt', v_attempt.id,
    null,
    jsonb_build_object('notificationId', v_attempt.notification_id),
    null
  );

  select n.* into v_source from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id;

  return jsonb_build_object('attemptId', v_attempt.id, 'replayed', false,
    'notification', app.notification_result_json(v_source));
end
$fn$;
alter function app.finish_whatsapp_rejection_work(uuid,uuid,text,boolean) owner to postgres;
revoke all on function app.finish_whatsapp_rejection_work(uuid,uuid,text,boolean) from public, anon;
grant execute on function app.finish_whatsapp_rejection_work(uuid,uuid,text,boolean) to service_role;

create function public.finish_whatsapp_rejection(p_attempt_id uuid, p_ticket uuid, p_failure_code text, p_outcome_known boolean)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  perform app.wsp_service_context();
  return app.finish_whatsapp_rejection_work(p_attempt_id, p_ticket, p_failure_code, p_outcome_known);
end
$fn$;
revoke all on function public.finish_whatsapp_rejection(uuid, uuid, text, boolean) from public, anon, authenticated, service_role;
grant execute on function public.finish_whatsapp_rejection(uuid, uuid, text, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 13. In-migration privilege assertions (ADR-074).
-- ---------------------------------------------------------------------------
do $check$
begin
  -- Member/staff definers: authenticated only.
  if not has_function_privilege('authenticated', 'public.read_member_whatsapp_settings()', 'EXECUTE')
     or has_function_privilege('anon', 'public.read_member_whatsapp_settings()', 'EXECUTE')
     or has_function_privilege('service_role', 'public.read_member_whatsapp_settings()', 'EXECUTE') then
    raise exception 'whatsapp_channel: read_member_whatsapp_settings grant matrix wrong';
  end if;
  if not has_function_privilege('authenticated', 'public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.set_member_whatsapp_consent(public.consent_purpose,boolean,text)', 'EXECUTE') then
    raise exception 'whatsapp_channel: set_member_whatsapp_consent grant matrix wrong';
  end if;
  if not has_function_privilege('authenticated', 'public.record_whatsapp_consent(uuid,public.consent_purpose,boolean,text,text,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.record_whatsapp_consent(uuid,public.consent_purpose,boolean,text,text,uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.record_whatsapp_consent(uuid,public.consent_purpose,boolean,text,text,uuid)', 'EXECUTE') then
    raise exception 'whatsapp_channel: record_whatsapp_consent grant matrix wrong';
  end if;
  -- Front-office invoker readers.
  if not has_function_privilege('authenticated', 'public.read_whatsapp_operations(timestamp with time zone,uuid,integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.read_whatsapp_operations(timestamp with time zone,uuid,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.read_whatsapp_operations(timestamp with time zone,uuid,integer)', 'EXECUTE') then
    raise exception 'whatsapp_channel: read_whatsapp_operations grant matrix wrong';
  end if;
  if not has_function_privilege('authenticated', 'public.request_whatsapp_dispatch(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.request_whatsapp_dispatch(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.request_whatsapp_dispatch(uuid,uuid)', 'EXECUTE') then
    raise exception 'whatsapp_channel: request_whatsapp_dispatch grant matrix wrong';
  end if;
  -- Service facades: service_role only.
  if not has_function_privilege('service_role', 'public.claim_whatsapp_dispatch(integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.claim_whatsapp_dispatch(integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.claim_whatsapp_dispatch(integer)', 'EXECUTE') then
    raise exception 'whatsapp_channel: claim_whatsapp_dispatch grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.authorize_whatsapp_dispatch(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.authorize_whatsapp_dispatch(uuid,uuid)', 'EXECUTE') then
    raise exception 'whatsapp_channel: authorize_whatsapp_dispatch grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.record_whatsapp_acceptance(uuid,uuid,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.record_whatsapp_acceptance(uuid,uuid,text,text)', 'EXECUTE') then
    raise exception 'whatsapp_channel: record_whatsapp_acceptance grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.finish_whatsapp_rejection(uuid,uuid,text,boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.finish_whatsapp_rejection(uuid,uuid,text,boolean)', 'EXECUTE') then
    raise exception 'whatsapp_channel: finish_whatsapp_rejection grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.record_whatsapp_receipt(uuid,text,text,text,timestamp with time zone,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.record_whatsapp_receipt(uuid,text,text,text,timestamp with time zone,text)', 'EXECUTE') then
    raise exception 'whatsapp_channel: record_whatsapp_receipt grant matrix wrong';
  end if;
  -- Tables.
  if has_table_privilege('authenticated', 'public.whatsapp_sender_accounts', 'SELECT')
     or has_table_privilege('authenticated', 'public.whatsapp_sender_accounts', 'INSERT')
     or has_table_privilege('anon', 'public.whatsapp_sender_accounts', 'SELECT') then
    raise exception 'whatsapp_channel: sender accounts privilege matrix wrong';
  end if;
  if not has_table_privilege('authenticated', 'public.whatsapp_template_revisions', 'SELECT')
     or has_table_privilege('authenticated', 'public.whatsapp_template_revisions', 'INSERT')
     or has_table_privilege('authenticated', 'public.whatsapp_template_revisions', 'UPDATE')
     or has_table_privilege('anon', 'public.whatsapp_template_revisions', 'SELECT') then
    raise exception 'whatsapp_channel: template revisions privilege matrix wrong';
  end if;
  if has_table_privilege('authenticated', 'public.whatsapp_rate_versions', 'SELECT')
     or has_table_privilege('authenticated', 'public.whatsapp_rate_versions', 'INSERT')
     or has_table_privilege('anon', 'public.whatsapp_rate_versions', 'SELECT') then
    raise exception 'whatsapp_channel: rate versions privilege matrix wrong';
  end if;
  if not has_table_privilege('authenticated', 'public.whatsapp_channel_consents', 'SELECT')
     or has_table_privilege('authenticated', 'public.whatsapp_channel_consents', 'INSERT')
     or has_table_privilege('authenticated', 'public.whatsapp_channel_consents', 'UPDATE')
     or has_table_privilege('anon', 'public.whatsapp_channel_consents', 'SELECT') then
    raise exception 'whatsapp_channel: channel consents privilege matrix wrong';
  end if;
  if has_table_privilege('authenticated', 'public.notification_whatsapp_attempts', 'SELECT')
     or has_table_privilege('authenticated', 'public.notification_whatsapp_attempts', 'INSERT')
     or has_table_privilege('anon', 'public.notification_whatsapp_attempts', 'SELECT')
     or has_table_privilege('service_role', 'public.notification_whatsapp_attempts', 'INSERT')
     or has_table_privilege('service_role', 'public.notification_whatsapp_attempts', 'UPDATE')
     or has_table_privilege('service_role', 'public.notification_whatsapp_attempts', 'DELETE') then
    raise exception 'whatsapp_channel: attempts privilege matrix wrong';
  end if;
  if has_table_privilege('authenticated', 'public.notification_whatsapp_receipts', 'SELECT')
     or has_table_privilege('authenticated', 'public.notification_whatsapp_receipts', 'INSERT')
     or has_table_privilege('anon', 'public.notification_whatsapp_receipts', 'SELECT')
     or has_table_privilege('service_role', 'public.notification_whatsapp_receipts', 'INSERT')
     or has_table_privilege('service_role', 'public.notification_whatsapp_receipts', 'UPDATE') then
    raise exception 'whatsapp_channel: receipts privilege matrix wrong';
  end if;
  -- Wallet note: transport writes stay in the private definer writer only;
  -- the phase6-era wallet grants are not this migration's surface to change.
end
$check$;

create or replace function app.enforce_notification()
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
      -- Transport children of a real renewal source are the sanctioned
      -- delivery extensions (NTF-007 for push; the phase6 manual WhatsApp
      -- open for whatsapp_link). Each must mirror the immutable source;
      -- the channel-specific blocks below still enforce their own actor,
      -- snapshot and recipient rules on top.
      if new.channel = 'push'::public.notification_channel
         and new.source_notification_id is not null
         and new.template_key is null then
        select s.* into v_source
          from public.notifications s
         where s.tenant_id = new.tenant_id
           and s.id = new.source_notification_id
           and s.member_id = new.member_id;
        if v_source.id is null
           or v_source.channel is distinct from 'in_app'::public.notification_channel
           or v_source.category is distinct from new.category
           or v_source.related_type is distinct from new.related_type
           or v_source.related_id is distinct from new.related_id
           or v_source.template_key is distinct from 'renewal_reminder' then
          raise exception 'A renewal push child must be an unchanged mirror of its renewal source'
            using errcode = 'GL066';
        end if;
      elsif new.channel = 'whatsapp_link'::public.notification_channel
         and new.source_notification_id is not null then
        select s.* into v_source
          from public.notifications s
         where s.tenant_id = new.tenant_id
           and s.id = new.source_notification_id
           and s.member_id = new.member_id;
        if v_source.id is null
           or v_source.category is distinct from new.category
           or v_source.related_type is distinct from new.related_type
           or v_source.related_id is distinct from new.related_id
           or v_source.template_key is distinct from 'renewal_reminder'
           or (new.template_key is not null
               and new.template_key is distinct from v_source.template_key)
           or (new.template_id is not null
               and new.template_id is distinct from v_source.template_id) then
          raise exception 'A renewal WhatsApp child must be an unchanged mirror of its renewal source'
            using errcode = 'GL066';
        end if;
      else
        -- WSP additive branch (d): first, the in-app fallback child of a
        -- renewal source — its own causal row (frozen key
        -- whatsapp-fallback:<source>) — is admitted here and returns before
        -- the reserved renewal remainder shape applies to it.
        if new.source_notification_id is not null
           and new.template_key is null
           and new.template_id is null
           and new.channel = 'in_app'::public.notification_channel
           and new.dedupe_key = ('whatsapp-fallback:' || new.source_notification_id::text) then
          if current_user <> 'postgres'
             or auth.uid() is not null
             or not exists (
               select 1 from public.notifications s
                where s.tenant_id = new.tenant_id
                  and s.id = new.source_notification_id
                  and s.member_id = new.member_id
                  and s.channel = 'in_app'::public.notification_channel
             ) then
            raise exception 'A reserved renewal identity must carry its exact structural shape'
              using errcode = 'GL066';
          end if;
          perform app.write_notification_audit(
            new.tenant_id, new.id, 'notification.scheduled', null,
            app.notification_audit_shape(new), null
          );
          return new;
        end if;
        -- Any other source-bearing renewal child that is neither the push
        -- mirror nor the fallback keeps the frozen refusal.
        if new.template_key is distinct from 'renewal_reminder'
           or new.channel is distinct from 'in_app'::public.notification_channel
           or new.category is distinct from 'renewal'::public.message_category
           or new.template_id is not null
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
      -- WSP additive branch (a): the transport-created paid child carries the
      -- frozen key whatsapp-paid:<source> and is admitted only under its own
      -- durable SQL attempt in the service context; a member/staff caller
      -- without the open command's verify session is refused as before.
      if new.dedupe_key = ('whatsapp-paid:' || new.source_notification_id::text) then
        if current_user <> 'postgres'
           or auth.uid() is not null
           or not exists (
             select 1 from public.notification_whatsapp_attempts a
              where a.tenant_id = new.tenant_id
                and a.notification_id = new.source_notification_id
                and a.completed_at is null
                and a.uncertain_at is null
           ) then
          raise exception 'A paid WhatsApp child requires its open transport attempt'
            using errcode = '42501';
        end if;
      elsif current_user <> 'postgres' then
        raise exception 'A WhatsApp child is created only by the open command'
          using errcode = '42501';
      else
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
      end if;
      -- Serial amendment: the snapshot rule composes with the paid child —
      -- a whatsapp-paid child mirrors the source's template fields exactly,
      -- while every other (manual) child keeps phase6's null-template rule.
      if v_source.channel is distinct from 'in_app'::public.notification_channel
         or v_source.status not in ('sent'::public.notification_status, 'delivered'::public.notification_status)
         or new.category is distinct from v_source.category
         or new.related_type is distinct from v_source.related_type
         or new.related_id is distinct from v_source.related_id
         or new.payload is distinct from v_source.payload
         or (
           new.dedupe_key like 'whatsapp-paid:%'
           and (new.template_key is distinct from v_source.template_key
                or new.template_id is distinct from v_source.template_id)
         )
         or (
           new.dedupe_key not like 'whatsapp-paid:%'
           and (new.template_id is not null or new.template_key is not null)
         )
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
      -- WSP additive branch (c): a WhatsApp delivery receipt row is the
      -- service-context evidence that the source in-app row was received;
      -- provider reads never fabricate clicks and never touch this guard.
      if current_user = 'postgres'
         and auth.uid() is null
         and exists (
           select 1 from public.notification_whatsapp_receipts rc
            join public.notification_whatsapp_attempts a on a.id = rc.attempt_id
            where a.tenant_id = old.tenant_id
              and a.notification_id = old.id
              and a.accepted_at is not null
              and rc.event_kind = 'delivered'
         ) then
        null; -- admitted by WhatsApp delivery evidence
      elsif current_user <> 'postgres'
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
      -- WSP additive branch (b): the paid child is sent only on a durable,
      -- non-uncertain provider acceptance for its own notification (the same
      -- evidence rule the push channel already enforces). The manual open
      -- keeps its verified front-office session requirement.
      if not (
        current_user = 'postgres'
        and auth.uid() is null
        and exists (
          select 1 from public.notification_whatsapp_attempts a
           where a.tenant_id = old.tenant_id
             and old.source_notification_id is not null
             and old.dedupe_key = ('whatsapp-paid:' || old.source_notification_id::text)
             and a.notification_id = old.source_notification_id
             and a.provider_message_id is not null
             and a.uncertain_at is null
        )
      ) then
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
    end if;

    -- NTF: a push row is sent only on a durable, non-uncertain provider
    -- acceptance for this exact notification. Data evidence inside the same
    -- transaction, never a session flag and never merely current_user.
    if old.channel = 'push'::public.notification_channel
       and old.status = 'scheduled'::public.notification_status
       and new.status = 'sent'::public.notification_status then
      if not exists (
        select 1 from public.notification_push_attempts a
         where a.tenant_id = old.tenant_id
           and a.notification_id = old.id
           and a.provider_message_id is not null
           and a.uncertain_at is null
      ) then
        raise exception 'A push message is sent only on a recorded provider acceptance'
          using errcode = 'GL066';
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
alter function app.enforce_notification() owner to postgres;
revoke all on function app.enforce_notification() from public, anon, authenticated;
---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 15a. Serial amendment #6: open_notification_whatsapp reuses the manual
-- whatsapp:<source> child only; body otherwise identical to phase6's.
-- ---------------------------------------------------------------------------
create or replace function public.open_notification_whatsapp(p_notification_id uuid)
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

  -- Serial amendment #6 (coordinator, 2026-10-03): the reusable child is the
  -- manual whatsapp:<source> row only — the WSP transport's whatsapp-paid:
  -- child of the same source is never reused by the manual command.
  select n.* into v_child from public.notifications n
   where n.tenant_id = v_tenant
     and n.source_notification_id = v_source.id
     and n.channel = 'whatsapp_link'::public.notification_channel
     and n.dedupe_key = 'whatsapp:' || v_source.id::text;

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

alter function public.open_notification_whatsapp(uuid) owner to postgres;

-- ---------------------------------------------------------------------------
-- 14a. Serial amendment #6 companion (coordinator, 2026-10-03): the paid
-- child must co-exist with the manual whatsapp:<source> child. The phase6
-- partial unique admitted one whatsapp_link child per source; duplicate manual
-- children were already impossible through the (tenant_id, dedupe_key) unique,
-- so the index is narrowed to exclude whatsapp-paid transport children —
-- the invariant for manual children is preserved.
-- ---------------------------------------------------------------------------
drop index if exists public.notifications_tenant_id_source_notification_id_whatsapp_key;
create unique index notifications_tenant_id_source_notification_id_whatsapp_key
  on public.notifications (tenant_id, source_notification_id)
  where source_notification_id is not null and channel = 'whatsapp_link'
    and coalesce(dedupe_key, '') not like 'whatsapp-paid:%';

-- 15. Serial adjudications recorded in this migration (2026-10-03):
--   app.apply_whatsapp_transport_debit = frozen service-only causal debit
--   writer (attempt-bound, tariff derived server-side; EXECUTE service_role).
--   Strict WhatsApp channel opt-in at claim and authorize (a currently
--   granted consent row whose recipient digest matches the current contact).
--   The four whatsapp-channel branches added above are ADDITIVE to
--   app.enforce_notification as applied by 20261004090000; its push branches
--   are byte-identical to that migration.
---------------------------------------------------------------------------
