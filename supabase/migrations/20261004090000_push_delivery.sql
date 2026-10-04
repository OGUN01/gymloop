-- NTF — Android push delivery (frozen contract, 2026-10-03).
-- Authority: openspec/changes/push-notifications/{proposal,transport-amendment,
-- pre-configuration-amendment}.md + wave-c-{delivery-declarations-draft,
-- serial-freeze-declarations}.md. The provider ships UNCONFIGURED and fail
-- closed: no pg_cron job, no Vault read, no deployment happens here. Transport
-- facades are service-only; member devices are RPC-only; the canonical
-- notification graph, audit and consent behavior are preserved.

-- ---------------------------------------------------------------------------
-- 1. member_devices amendment: durable identity, rotation revision, revocation.
-- ---------------------------------------------------------------------------
alter table public.member_devices
  add column registered_user_id uuid,
  add column installation_id uuid,
  add column token_revision bigint,
  add column invalidated_at timestamptz,
  add column invalidated_reason text,
  add constraint member_devices_invalidated_pair_chk
    check ((invalidated_at is null) = (invalidated_reason is null));

-- The device FK target for attempts; new composite member FK per ADR-052.
alter table public.member_devices
  add constraint member_devices_tenant_id_id_key unique (tenant_id, id);

-- The composite tenant/member FK already exists (ADR-052 renamed it member_devices_member_id_fkey).

-- One row per install per member; historical rows without provenance keep a
-- null installation and stay outside this key.
-- The exact unique key the public contract pins, as a table constraint.
-- Equality semantics mean NULL installations stay free of this key; legacy
-- provenance-null rows are handled by the legacy-inactive invariant below.
alter table public.member_devices
  add constraint member_devices_tenant_member_installation_key
  unique (tenant_id, member_id, installation_id);

create index member_devices_tenant_id_member_inst_idx
  on public.member_devices (tenant_id, member_id);

-- Legacy provenance-null rows are inactive until a register command adopts
-- them: the row itself may never carry is_active without provenance, so
-- dispatch eligibility and every safe projection agree with the contract.
-- Rows that predate this migration (including any fixture inserted before the
-- migration block runs) are normalized here; later writes are coerced by the
-- per-row trigger.
update public.member_devices
   set is_active = false
 where registered_user_id is null
   and is_active;

create function app.enforce_push_device_legacy()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  new.updated_at := statement_timestamp();
  if new.registered_user_id is null and new.is_active then
    new.is_active := false;
  end if;
  return new;
end
$fn$;

revoke all on function app.enforce_push_device_legacy() from public, anon, authenticated, service_role;

create trigger member_devices_legacy_inactive
  before insert or update on public.member_devices
  for each row execute function app.enforce_push_device_legacy();

-- Device tokens and metadata are available only through command-safe RPCs.
-- Table-level revocation does not remove pre-existing column privileges.
revoke all on public.member_devices from public, anon, authenticated, service_role;
do $device_columns$
declare
  v_columns text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
    into v_columns from pg_attribute a
   where a.attrelid = 'public.member_devices'::regclass
     and a.attnum > 0 and not a.attisdropped;
  execute 'revoke all (' || v_columns || ') on public.member_devices from public, anon, authenticated, service_role';
end
$device_columns$;

-- ---------------------------------------------------------------------------
-- 2. Tenant activation for the one approved Firebase project; absent = unconfigured.
-- ---------------------------------------------------------------------------
create table public.push_provider_configurations (
  tenant_id uuid primary key references public.organizations(id),
  firebase_project_id text,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_provider_configurations enable row level security;
revoke all on public.push_provider_configurations from public, anon, authenticated, service_role;

-- Trusted commands need activation facts without granting configuration reads.
create function app.push_configuration_ready(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $fn$
  select exists (
    select 1 from public.push_provider_configurations c
    where c.tenant_id = p_tenant_id
      and c.firebase_project_id = 'samuraiapi-51996'
      and c.activated_at is not null and c.activated_at <= statement_timestamp()
  )
$fn$;
alter function app.push_configuration_ready(uuid) owner to postgres;
revoke all on function app.push_configuration_ready(uuid) from public, anon, authenticated, service_role;

-- Existing invoker composition may inspect only its complete ordinary claim.
create function app.push_configuration_ready()
returns boolean language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if auth.uid() is null or app.current_tenant_id() is null
     or app.current_impersonation_id() is not null then
    return false;
  end if;
  if app.current_app_role() = 'member' then
    if app.current_member_id() is null or app.current_staff_id() is not null then
      return false;
    end if;
  elsif app.current_app_role() in ('gym_owner', 'gym_manager', 'front_desk', 'trainer') then
    if app.current_staff_id() is null or app.current_member_id() is not null then
      return false;
    end if;
  else
    return false;
  end if;
  return app.push_configuration_ready(app.current_tenant_id());
exception when invalid_text_representation then
  return false;
end
$fn$;
alter function app.push_configuration_ready() owner to postgres;
revoke all on function app.push_configuration_ready() from public, anon, authenticated, service_role;
grant execute on function app.push_configuration_ready() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. member_notification_preferences: per-category push opt-out. A missing row
--    means push enabled, subject to OS permission and consent. Own-member read
--    only; staff contexts hit the raising policy (42501), never silent rows.
-- ---------------------------------------------------------------------------
create table public.member_notification_preferences (
  tenant_id uuid not null,
  member_id uuid not null,
  category public.message_category not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_notification_preferences_pkey
    primary key (tenant_id, member_id, category),
  constraint member_notification_preferences_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id)
);

alter table public.member_notification_preferences enable row level security;

-- Two helpers so the RLS operator operands each carry the raising gate:
-- AND-conjunct order inside a policy expression is planner-dependent, so a
-- single leading guard cannot be relied on to raise for staff contexts.
create function app.push_preference_tenant()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
begin
  if auth.uid() is null
     or app.current_app_role() is distinct from 'member'
     or app.current_member_id() is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'Notification preferences are the member''s own rows'
      using errcode = '42501';
  end if;
  return app.current_tenant_id();
end
$fn$;

create function app.push_preference_member()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $fn$
  select app.current_member_id()
$fn$;

revoke all on function app.push_preference_tenant() from public, anon, service_role;
grant execute on function app.push_preference_tenant() to authenticated;
revoke all on function app.push_preference_member() from public, anon, service_role;
grant execute on function app.push_preference_member() to authenticated;

create policy member_notification_preferences_own_member_select
  on public.member_notification_preferences
  for select
  using (
    tenant_id = app.push_preference_tenant()
    and member_id = app.push_preference_member()
  );

revoke all on public.member_notification_preferences from public, anon, authenticated, service_role;
grant select on public.member_notification_preferences to authenticated;

-- ---------------------------------------------------------------------------
-- 4. notification_push_campaigns: reviewed ANC broadcast permission. Review is
--    permission to attempt, never evidence of receipt.
-- ---------------------------------------------------------------------------
create table public.notification_push_campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  announcement_id uuid not null,
  version_no integer not null,
  request_key uuid not null,
  created_by_staff_id uuid not null,
  reviewed_by_staff_id uuid not null,
  reviewed_at timestamptz not null default now(),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_push_campaigns_tenant_id_version_key
    unique (tenant_id, announcement_id, version_no),
  constraint notification_push_campaigns_tenant_id_request_key_key
    unique (tenant_id, request_key),
  constraint notification_push_campaigns_tenant_id_announcement_id_fkey
    foreign key (tenant_id, announcement_id)
      references public.announcements (tenant_id, id),
  constraint notification_push_campaigns_tenant_id_created_by_staff_id_fkey
    foreign key (tenant_id, created_by_staff_id)
      references public.staff (tenant_id, id),
  constraint notification_push_campaigns_tenant_id_reviewed_by_staff_id_fkey
    foreign key (tenant_id, reviewed_by_staff_id)
      references public.staff (tenant_id, id),
  constraint notification_push_campaigns_version_no_chk check (version_no >= 1)
);

alter table public.notification_push_campaigns enable row level security;

create policy notification_push_campaigns_front_office_select
  on public.notification_push_campaigns
  for select
  using (
    tenant_id = app.current_tenant_id()
    and app.current_app_role() in ('gym_owner', 'gym_manager', 'front_desk')
  );

revoke all on public.notification_push_campaigns from public, anon, authenticated, service_role;
grant select on public.notification_push_campaigns to authenticated;

create index notification_push_campaigns_tenant_id_created_at_idx
  on public.notification_push_campaigns (tenant_id, created_at desc, id desc);

-- ---------------------------------------------------------------------------
-- 5. notification_push_attempts: per-device transport facts. No tokens, no
--    payloads, no grants of any kind outside the owning session.
-- ---------------------------------------------------------------------------
create table public.notification_push_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  member_id uuid not null,
  notification_id uuid not null,
  device_id uuid not null,
  token_revision bigint not null,
  registered_user_id uuid not null,
  reservation_id uuid,
  started_at timestamptz,
  completed_at timestamptz,
  provider_message_id text,
  failure_code text,
  uncertain_at timestamptz,
  constraint notification_push_attempts_tenant_id_notification_id_device_id_key
    unique (tenant_id, notification_id, device_id),
  constraint notification_push_attempts_tenant_id_notification_id_fkey
    foreign key (tenant_id, notification_id)
      references public.notifications (tenant_id, id),
  constraint notification_push_attempts_tenant_id_device_id_fkey
    foreign key (tenant_id, device_id)
      references public.member_devices (tenant_id, id)
      deferrable initially deferred,
  constraint notification_push_attempts_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members (tenant_id, id),
  constraint notification_push_attempts_failure_code_chk
    check (failure_code is null or (btrim(failure_code) <> '' and char_length(btrim(failure_code)) <= 64)),
  constraint notification_push_attempts_provider_message_chk
    check (provider_message_id is null or (btrim(provider_message_id) <> '' and char_length(btrim(provider_message_id)) <= 256))
);

alter table public.notification_push_attempts enable row level security;
revoke all on public.notification_push_attempts from public, anon, authenticated, service_role;
-- service_role counts transport facts in operational reads; writes stay helper-only.
grant select on public.notification_push_attempts to service_role;

create index notification_push_attempts_tenant_id_notification_id_idx
  on public.notification_push_attempts (tenant_id, notification_id);

create index notification_push_attempts_tenant_id_started_at_idx
  on public.notification_push_attempts (tenant_id, started_at);

-- ---------------------------------------------------------------------------
-- 6. Shared private helpers.
-- ---------------------------------------------------------------------------
create function app.push_member_actor()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
begin
  if auth.uid() is null
     or app.current_app_role() is distinct from 'member'
     or app.current_member_id() is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is not null
     or app.current_impersonation_id() is not null then
    raise exception 'A complete member session is required' using errcode = '42501';
  end if;
  return app.current_member_id();
end
$fn$;

revoke all on function app.push_member_actor() from public, anon, service_role;
grant execute on function app.push_member_actor() to authenticated;

create function app.push_front_office_actor(p_allowed text[])
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_staff uuid;
begin
  if auth.uid() is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_app_role() is null
     or not (app.current_app_role() = any (p_allowed))
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires an authorized front-office session' using errcode = '42501';
  end if;
  select s.id into v_staff from public.staff s
   where s.tenant_id = app.current_tenant_id()
     and s.id = app.current_staff_id()
     and s.user_id = auth.uid()
     and s.role::text = app.current_app_role()
     and s.is_active;
  if v_staff is null then
    raise exception 'This action requires an authorized front-office session' using errcode = '42501';
  end if;
  return v_staff;
end
$fn$;

revoke all on function app.push_front_office_actor(text[]) from public, anon, service_role;
grant execute on function app.push_front_office_actor(text[]) to authenticated;

create function app.write_push_audit(
  p_tenant uuid,
  p_record_id uuid,
  p_action text,
  p_after jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if p_action not in
       ('push.device_registered', 'push.device_unregistered',
        'push.preference_changed', 'push.campaign_reviewed',
        'push.campaign_cancelled') then
    raise exception 'Unsupported push audit action' using errcode = '22023';
  end if;
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, action, record_type, record_id, after
  ) values (
    p_tenant, auth.uid(),
    case when auth.uid() is null then null
         else (select e.enumlabel::text::public.app_role
                 from pg_catalog.pg_enum e
                where e.enumtypid = 'public.app_role'::pg_catalog.regtype
                  and e.enumlabel = app.current_app_role()) end,
    p_action, 'push_delivery', p_record_id, p_after
  );
end
$fn$;

revoke all on function app.write_push_audit(uuid, uuid, text, jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Member commands.
-- ---------------------------------------------------------------------------
create function public.register_member_push_device(p_installation_id uuid, p_push_token text, p_platform text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member uuid;
  v_tenant uuid;
  v_user uuid;
  v_member_row public.members%rowtype;
  v_row public.member_devices%rowtype;
  v_revision bigint;
begin
  v_member := app.push_member_actor();
  v_tenant := app.current_tenant_id();
  v_user := auth.uid();

  if p_installation_id is null
     or p_platform is distinct from 'android'
     or p_push_token is null
     or btrim(p_push_token) = ''
     or char_length(p_push_token) > 4096 then
    raise exception 'A push device registration requires an Android installation and a bounded token'
      using errcode = '22023';
  end if;

  select m.* into v_member_row from public.members m
   where m.tenant_id = v_tenant and m.id = v_member for update;
  if v_member_row.id is null
     or v_member_row.user_id is distinct from v_user
     or v_member_row.status is distinct from 'active'::public.member_status
     or v_member_row.erased_at is not null
     or (v_member_row.date_of_birth is not null
         and app.member_is_minor_on(v_member_row.date_of_birth, app.gym_today(v_tenant))
         and not (app.member_guardian_complete(v_member_row)
                  and v_member_row.guardian_linked_at is not null)) then
    raise exception 'Push registration requires an eligible member account' using errcode = '42501';
  end if;

  -- D1 exclusivity: the account may not currently resolve to both a member row
  -- and a staff or platform identity. Generic refusal; no identity disclosure.
  if exists (select 1 from public.staff s2 where s2.user_id = v_user)
     or exists (select 1 from public.platform_users p2 where p2.user_id = v_user) then
    raise exception 'Push registration requires an eligible member account' using errcode = '42501';
  end if;

  select * into v_row from public.member_devices d
   where d.tenant_id = v_tenant
     and d.member_id = v_member
     and d.installation_id = p_installation_id
   for update;

  if v_row.id is not null then
    if v_row.registered_user_id is null then
      -- Legacy adoption: an untouched provenance-null row starts at revision one.
      update public.member_devices
         set registered_user_id = v_user,
             push_token = p_push_token,
             is_active = true,
             token_revision = 1,
             invalidated_at = null,
             invalidated_reason = null,
             last_seen_at = statement_timestamp(),
             updated_at = statement_timestamp()
       where id = v_row.id
       returning * into v_row;
      perform app.write_push_audit(v_tenant, v_row.id, 'push.device_registered',
        jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active));
      return jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active);
    end if;
    if v_row.push_token = p_push_token then
      -- Same installation, same token, live provenance: inert replay.
      return jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active);
    end if;
    -- Rotation on the same installation: one atomic revision increment.
    update public.member_devices
       set push_token = p_push_token,
           token_revision = coalesce(v_row.token_revision, 0) + 1,
           is_active = true,
           invalidated_at = null,
           invalidated_reason = null,
           last_seen_at = statement_timestamp(),
           updated_at = statement_timestamp()
     where id = v_row.id
       and token_revision = coalesce(v_row.token_revision, 0)
     returning * into v_row;
    if v_row.id is null then
      raise exception 'Device rotation lost a race; retry with the current installation state'
        using errcode = 'GL115';
    end if;
    perform app.write_push_audit(v_tenant, v_row.id, 'push.device_registered',
      jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active));
    return jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active);
  end if;

  begin
    insert into public.member_devices
      (id, tenant_id, member_id, platform, push_token, is_active, last_seen_at,
       installation_id, token_revision, registered_user_id)
    values
      (p_installation_id, v_tenant, v_member, p_platform, p_push_token, true, statement_timestamp(),
       p_installation_id, 1, v_user)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Push token is already registered for this gym' using errcode = '23505';
  end;

  perform app.write_push_audit(v_tenant, v_row.id, 'push.device_registered',
    jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active));
  return jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', v_row.is_active);
end
$fn$;

revoke all on function public.register_member_push_device(uuid, text, text) from public, anon, service_role;
grant execute on function public.register_member_push_device(uuid, text, text) to authenticated;

create function public.unregister_member_push_device(p_installation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member uuid;
  v_tenant uuid;
  v_row public.member_devices%rowtype;
begin
  v_member := app.push_member_actor();
  v_tenant := app.current_tenant_id();

  update public.member_devices d
     set is_active = false,
         invalidated_at = statement_timestamp(),
         invalidated_reason = 'member_unregistered',
         updated_at = statement_timestamp()
   where d.tenant_id = v_tenant
     and d.member_id = v_member
     and d.installation_id = p_installation_id
     and d.registered_user_id = auth.uid()
     and d.is_active
   returning * into v_row;

  if v_row.id is not null then
    perform app.write_push_audit(v_tenant, v_row.id, 'push.device_unregistered',
      jsonb_build_object('deviceId', v_row.id, 'tokenRevision', v_row.token_revision, 'active', false));
  end if;

  -- Unknown or foreign installations are inert: one answer, no existence oracle.
  return jsonb_build_object('disabled', true);
end
$fn$;

revoke all on function public.unregister_member_push_device(uuid) from public, anon, service_role;
grant execute on function public.unregister_member_push_device(uuid) to authenticated;

create function public.read_member_push_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_member uuid;
  v_tenant uuid;
  v_user uuid;
begin
  v_member := app.push_member_actor();
  v_tenant := app.current_tenant_id();
  v_user := auth.uid();

  return jsonb_build_object(
    'preferences',
    coalesce((select jsonb_agg(jsonb_build_object('category', p.category, 'enabled', p.enabled) order by p.category)
                from public.member_notification_preferences p
               where p.tenant_id = v_tenant and p.member_id = v_member), '[]'::jsonb),
    'devices',
    coalesce((select jsonb_agg(
                   jsonb_build_object(
                     'id', d.id,
                     'lastSeenAt', d.last_seen_at,
                     'active', coalesce(d.is_active and d.registered_user_id = v_user, false))
                   order by d.id)
                from public.member_devices d
               where d.tenant_id = v_tenant and d.member_id = v_member), '[]'::jsonb)
  );
end
$fn$;

revoke all on function public.read_member_push_settings() from public, anon, service_role;
grant execute on function public.read_member_push_settings() to authenticated;

create function public.set_member_push_preference(p_category public.message_category, p_enabled boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member uuid;
  v_tenant uuid;
  v_existing boolean;
begin
  v_member := app.push_member_actor();
  v_tenant := app.current_tenant_id();

  if p_category is null or p_enabled is null then
    raise exception 'A preference change needs a category and an enabled value' using errcode = '22023';
  end if;

  select p.enabled into v_existing
    from public.member_notification_preferences p
   where p.tenant_id = v_tenant and p.member_id = v_member and p.category = p_category
   for update;

  if v_existing is null then
    insert into public.member_notification_preferences (tenant_id, member_id, category, enabled)
    values (v_tenant, v_member, p_category, p_enabled);
    perform app.write_push_audit(v_tenant, v_member, 'push.preference_changed',
      jsonb_build_object('category', p_category, 'enabled', p_enabled));
  elsif v_existing is distinct from p_enabled then
    update public.member_notification_preferences
       set enabled = p_enabled, updated_at = statement_timestamp()
     where tenant_id = v_tenant and member_id = v_member and category = p_category;
    perform app.write_push_audit(v_tenant, v_member, 'push.preference_changed',
      jsonb_build_object('category', p_category, 'enabled', p_enabled));
  end if;

  -- Identical-value replay is inert: no audit, no consent mutation.
  return jsonb_build_object('category', p_category, 'enabled', p_enabled);
end
$fn$;

revoke all on function public.set_member_push_preference(public.message_category, boolean) from public, anon, service_role;
grant execute on function public.set_member_push_preference(public.message_category, boolean) to authenticated;

create function public.acknowledge_member_push(p_notification_id uuid, p_device_id uuid, p_token_revision bigint, p_event text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_member uuid;
  v_tenant uuid;
  v_device public.member_devices%rowtype;
  v_row public.notifications%rowtype;
  v_attempt public.notification_push_attempts%rowtype;
begin
  v_member := app.push_member_actor();
  v_tenant := app.current_tenant_id();

  if p_event is distinct from 'received' and p_event is distinct from 'opened' then
    raise exception 'A push acknowledgement carries received or opened only' using errcode = '22023';
  end if;

  select d.* into v_device from public.member_devices d
   where d.id = p_device_id for update;

  if v_device.id is null
     or v_device.tenant_id is distinct from v_tenant
     or v_device.member_id is distinct from v_member
     or v_device.registered_user_id is distinct from auth.uid() then
    raise exception 'Push receipts require the member''s current registered device' using errcode = '42501';
  end if;

  if v_device.token_revision is distinct from p_token_revision then
    raise exception 'The device token revision has moved on' using errcode = 'GL118';
  end if;

  select n.* into v_row from public.notifications n
   where n.tenant_id = v_tenant and n.id = p_notification_id for update;

  if v_row.id is null
     or v_row.channel is distinct from 'push'::public.notification_channel
     or v_row.member_id is distinct from v_member then
    raise exception 'Push receipts require the member''s own push notification' using errcode = '42501';
  end if;

  select a.* into v_attempt from public.notification_push_attempts a
   where a.tenant_id = v_tenant
     and a.notification_id = p_notification_id
     and a.device_id = p_device_id
   for update;

  if v_attempt.id is null
     or v_attempt.completed_at is null
     or v_attempt.provider_message_id is null
     or v_attempt.uncertain_at is not null then
    raise exception 'Push receipts require an accepted provider attempt for this device' using errcode = '42501';
  end if;

  if v_attempt.token_revision is distinct from p_token_revision then
    raise exception 'The attempt belongs to an older token revision' using errcode = 'GL118';
  end if;

  -- received: device receipt. opened: open response. Both may traverse the
  -- legal graph edges from wherever the row actually stands; the trigger
  -- stamps every timestamp as database evidence and audits each edge.
  if p_event = 'received' then
    if v_row.status = 'scheduled'::public.notification_status then
      update public.notifications set status = 'sent'
       where tenant_id = v_tenant and id = v_row.id
       returning * into v_row;
    end if;
    if v_row.status = 'sent'::public.notification_status then
      update public.notifications set status = 'delivered'
       where tenant_id = v_tenant and id = v_row.id
       returning * into v_row;
    end if;
  else
    if v_row.status = 'scheduled'::public.notification_status then
      update public.notifications set status = 'sent'
       where tenant_id = v_tenant and id = v_row.id
       returning * into v_row;
    end if;
    if v_row.status = 'sent'::public.notification_status then
      update public.notifications set status = 'delivered'
       where tenant_id = v_tenant and id = v_row.id
       returning * into v_row;
    end if;
    if v_row.status = 'delivered'::public.notification_status then
      update public.notifications set status = 'clicked'
       where tenant_id = v_tenant and id = v_row.id
       returning * into v_row;
    end if;
  end if;

  select n.* into v_row from public.notifications n
   where n.tenant_id = v_tenant and n.id = p_notification_id;

  return app.notification_result_json(v_row);
end
$fn$;

revoke all on function public.acknowledge_member_push(uuid, uuid, bigint, text) from public, anon, service_role;
grant execute on function public.acknowledge_member_push(uuid, uuid, bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Campaign review and cancellation (owner/manager; desk previews only).
-- ---------------------------------------------------------------------------
create function public.review_announcement_push(p_announcement_id uuid, p_version_no integer, p_request_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff uuid;
  v_tenant uuid;
  v_announcement public.announcements%rowtype;
  v_version public.announcement_versions%rowtype;
  v_campaign public.notification_push_campaigns%rowtype;
  v_eligible integer;
begin
  v_staff := app.push_front_office_actor(array['gym_owner', 'gym_manager']);
  v_tenant := app.current_tenant_id();

  if p_version_no is null or p_version_no < 1 or p_request_key is null then
    raise exception 'A campaign review needs a version and a request key' using errcode = '22023';
  end if;

  select a.* into v_announcement from public.announcements a
   where a.tenant_id = v_tenant and a.id = p_announcement_id for update;

  if v_announcement.id is null then
    raise exception 'Announcement unavailable' using errcode = 'P0002';
  end if;
  if v_announcement.status is distinct from 'published'
     or v_announcement.current_version is distinct from p_version_no then
    raise exception 'The campaign must review the announcement''s current live version'
      using errcode = 'GL066';
  end if;

  select v.* into v_version from public.announcement_versions v
   where v.tenant_id = v_tenant
     and v.announcement_id = p_announcement_id
     and v.version_no = p_version_no;
  if v_version.id is null then
    raise exception 'Announcement version unavailable' using errcode = 'P0002';
  end if;

  v_eligible := (select count(*)::integer from app.announcement_audience(p_announcement_id));

  -- Immutable request replay beats the version key; a different request key
  -- for a version already reviewed is the campaign conflict.
  select c.* into v_campaign from public.notification_push_campaigns c
   where c.tenant_id = v_tenant and c.request_key = p_request_key;
  if v_campaign.id is not null then
    if v_campaign.announcement_id is distinct from p_announcement_id
       or v_campaign.version_no is distinct from p_version_no then
      raise exception 'This request key already belongs to another campaign' using errcode = 'GL068';
    end if;
    return jsonb_build_object('campaignId', v_campaign.id, 'versionNo', v_campaign.version_no,
      'eligibleCount', v_eligible, 'reviewedAt', v_campaign.reviewed_at);
  end if;

  if exists (select 1 from public.notification_push_campaigns c
              where c.tenant_id = v_tenant
                and c.announcement_id = p_announcement_id
                and c.version_no = p_version_no) then
    raise exception 'This announcement version already has a reviewed campaign' using errcode = 'GL115';
  end if;

  insert into public.notification_push_campaigns
    (tenant_id, announcement_id, version_no, request_key, created_by_staff_id, reviewed_by_staff_id)
  values
    (v_tenant, p_announcement_id, p_version_no, p_request_key, v_staff, v_staff)
  returning * into v_campaign;

  perform app.write_push_audit(v_tenant, v_campaign.id, 'push.campaign_reviewed',
    jsonb_build_object('announcementId', p_announcement_id, 'versionNo', p_version_no,
                       'eligibleCount', v_eligible));

  return jsonb_build_object('campaignId', v_campaign.id, 'versionNo', v_campaign.version_no,
    'eligibleCount', v_eligible, 'reviewedAt', v_campaign.reviewed_at);
end
$fn$;

revoke all on function public.review_announcement_push(uuid, integer, uuid) from public, anon, service_role;
grant execute on function public.review_announcement_push(uuid, integer, uuid) to authenticated;

create function public.cancel_announcement_push(p_campaign_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff uuid;
  v_tenant uuid;
  v_campaign public.notification_push_campaigns%rowtype;
begin
  v_staff := app.push_front_office_actor(array['gym_owner', 'gym_manager']);
  v_tenant := app.current_tenant_id();

  select c.* into v_campaign from public.notification_push_campaigns c
   where c.tenant_id = v_tenant and c.id = p_campaign_id for update;

  -- Unknown and foreign campaigns share one target-invisible refusal.
  if v_campaign.id is null then
    raise exception 'Campaign unavailable' using errcode = 'P0002';
  end if;

  if v_campaign.cancelled_at is null then
    update public.notification_push_campaigns
       set cancelled_at = statement_timestamp(), updated_at = statement_timestamp()
     where tenant_id = v_tenant and id = v_campaign.id
     returning * into v_campaign;
    perform app.write_push_audit(v_tenant, v_campaign.id, 'push.campaign_cancelled',
      jsonb_build_object('announcementId', v_campaign.announcement_id, 'versionNo', v_campaign.version_no));
  end if;

  return jsonb_build_object('cancelled', true, 'campaignId', v_campaign.id);
end
$fn$;

revoke all on function public.cancel_announcement_push(uuid) from public, anon, service_role;
grant execute on function public.cancel_announcement_push(uuid) to authenticated;

create function public.read_push_campaigns(p_before timestamptz default null, p_before_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_rows jsonb;
  v_next_before timestamptz;
  v_next_id uuid;
  v_limit integer := 20;
  v_campaign_prefix text;
begin
  perform app.push_front_office_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  v_tenant := app.current_tenant_id();

  with page as (
    select c.*
      from public.notification_push_campaigns c
     where c.tenant_id = v_tenant
       and (p_before is null
            or (c.created_at, c.id) < (p_before, coalesce(p_before_id, '00000000-0000-0000-0000-000000000000'::uuid)))
     order by c.created_at desc, c.id desc
     limit v_limit + 1
  ), shaped as (
    select c.*,
      (select count(*) from public.notification_push_attempts a
        join public.notifications n2 on n2.tenant_id = a.tenant_id and n2.id = a.notification_id
        where a.tenant_id = c.tenant_id
          and n2.dedupe_key like 'announcement:' || c.announcement_id::text || ':v' || c.version_no::text || ':%'
          and a.provider_message_id is not null and a.uncertain_at is null) as accepted_count,
      (select count(*) from public.notifications n2
        where n2.tenant_id = c.tenant_id
          and n2.dedupe_key like 'announcement:' || c.announcement_id::text || ':v' || c.version_no::text || ':%'
          and n2.delivered_at is not null) as received_count,
      (select count(*) from public.notifications n2
        where n2.tenant_id = c.tenant_id
          and n2.dedupe_key like 'announcement:' || c.announcement_id::text || ':v' || c.version_no::text || ':%'
          and n2.clicked_at is not null) as opened_count,
      (select count(*) from public.notification_push_attempts a
        join public.notifications n2 on n2.tenant_id = a.tenant_id and n2.id = a.notification_id
        where a.tenant_id = c.tenant_id
          and n2.dedupe_key like 'announcement:' || c.announcement_id::text || ':v' || c.version_no::text || ':%'
          and a.uncertain_at is not null) as uncertain_count,
      (select count(*) from public.notification_push_attempts a
        join public.notifications n2 on n2.tenant_id = a.tenant_id and n2.id = a.notification_id
        where a.tenant_id = c.tenant_id
          and n2.dedupe_key like 'announcement:' || c.announcement_id::text || ':v' || c.version_no::text || ':%'
          and a.provider_message_id is null and a.completed_at is not null and a.uncertain_at is null) as failed_count
    from page c
  )
  select jsonb_agg(
           jsonb_build_object(
             'campaignId', s.id,
             'announcementId', s.announcement_id,
             'versionNo', s.version_no,
             'reviewedAt', s.reviewed_at,
             'cancelledAt', s.cancelled_at,
             'createdAt', s.created_at,
             'acceptedCount', s.accepted_count,
             'receivedCount', s.received_count,
             'openedCount', s.opened_count,
             'uncertainCount', s.uncertain_count,
             'failedCount', s.failed_count)
           order by s.created_at desc, s.id desc)
    into v_rows
    from shaped s;

  if v_rows is null then
    v_rows := '[]'::jsonb;
  end if;

  if jsonb_array_length(v_rows) > v_limit then
    -- The cursor is the LAST INCLUDED row: the next page resumes strictly
    -- before it, so no row is skipped and none is repeated.
    select s.created_at, s.id into v_next_before, v_next_id
      from shaped s
     order by s.created_at desc, s.id desc
     limit 1;
    v_rows := (
      select coalesce(jsonb_agg(e order by t.ord), '[]'::jsonb)
        from jsonb_array_elements(v_rows) with ordinality t(e, ord)
       where t.ord <= v_limit
    );
  end if;

  return jsonb_build_object('campaigns', v_rows,
    'nextBefore', v_next_before, 'nextBeforeId', v_next_id);
end
$fn$;

revoke all on function public.read_push_campaigns(timestamp with time zone, uuid) from public, anon;
grant execute on function public.read_push_campaigns(timestamp with time zone, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Transport work (service-only facades over private DEFINER helpers).
--    started_at carries the reservation start; authorization and finalization
--    key off it, so the pinned attempt columns stay exact.
-- ---------------------------------------------------------------------------
create function app.reserve_push_attempts_work(p_limit integer)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_budget integer;
  v_remaining integer := p_limit;
  v_quiet boolean;
  v_collected jsonb := '[]'::jsonb;
  v_batch jsonb;
begin
  if not exists (select 1 from public.push_provider_configurations c
                  where app.push_configuration_ready(c.tenant_id)) then
    return jsonb_build_object('attempts', '[]'::jsonb, 'configuration', 'provider_unconfigured');
  end if;

  for v_tenant in
    select distinct n.tenant_id
      from public.notifications n
      join public.members m on m.tenant_id = n.tenant_id and m.id = n.member_id
     where n.channel = 'push'::public.notification_channel
       and n.status = 'scheduled'::public.notification_status
       and n.scheduled_for <= statement_timestamp()
       and exists (select 1 from public.push_provider_configurations c
                    where c.tenant_id = n.tenant_id and app.push_configuration_ready(c.tenant_id)
                      and n.created_at >= c.activated_at)
       and m.status in ('active'::public.member_status, 'paused'::public.member_status, 'expired'::public.member_status)
       and m.erased_at is null
       and exists (select 1 from public.member_devices d
                    where d.tenant_id = n.tenant_id and d.member_id = n.member_id
                      and d.is_active and d.registered_user_id is not null)
     order by 1
     limit 50
  loop
    exit when v_remaining <= 0;

    -- Per-tenant budget serialization: one worker at a time per tenant.
    perform pg_advisory_xact_lock(hashtextextended('push-dispatch:' || v_tenant::text, 0));

    select count(*) into v_budget
      from public.notification_push_attempts a
     where a.tenant_id = v_tenant
       and a.started_at > statement_timestamp() - interval '60 seconds';
    if v_budget >= 100 then
      continue;
    end if;

    v_quiet := extract(hour from (statement_timestamp() at time zone 'Asia/Kolkata')) >= 21
            or extract(hour from (statement_timestamp() at time zone 'Asia/Kolkata')) < 8;

    with ins as (
      insert into public.notification_push_attempts
        (tenant_id, member_id, notification_id, device_id, token_revision,
         registered_user_id, reservation_id, started_at)
      select n.tenant_id, n.member_id, n.id, d.id, d.token_revision,
             d.registered_user_id, gen_random_uuid(), statement_timestamp()
        from public.notifications n
        join public.members m on m.tenant_id = n.tenant_id and m.id = n.member_id
        join public.member_devices d on d.tenant_id = n.tenant_id and d.member_id = n.member_id
       where n.tenant_id = v_tenant
         and n.channel = 'push'::public.notification_channel
         and n.status = 'scheduled'::public.notification_status
         and n.scheduled_for <= statement_timestamp()
       and exists (select 1 from public.push_provider_configurations c
                    where c.tenant_id = n.tenant_id and app.push_configuration_ready(c.tenant_id)
                      and n.created_at >= c.activated_at)
         and m.status in ('active'::public.member_status, 'paused'::public.member_status, 'expired'::public.member_status)
         and m.erased_at is null
         and d.is_active and d.registered_user_id = m.user_id
         and (n.category is distinct from 'promotion'::public.message_category or not v_quiet)
         and not exists (select 1 from public.notification_push_attempts a
                          where a.tenant_id = n.tenant_id and a.notification_id = n.id and a.device_id = d.id)
       order by n.scheduled_for, n.id, d.id
       limit least(v_remaining, 100 - v_budget)
      returning id, reservation_id, started_at
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'attemptId', r.id, 'reservationId', r.reservation_id,
             'expiresAt', r.started_at + interval '90 seconds') order by r.id), '[]'::jsonb)
      into v_batch
      from ins r;

    v_collected := v_collected || v_batch;
    v_remaining := v_remaining - jsonb_array_length(v_batch);
  end loop;

  return jsonb_build_object('attempts', v_collected, 'configuration', 'ready');
end
$fn$;

revoke all on function app.reserve_push_attempts_work(integer) from public, anon, authenticated;
grant execute on function app.reserve_push_attempts_work(integer) to service_role;

create function public.reserve_push_attempts(p_limit integer)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if current_user <> 'service_role' then
    raise exception 'Transport work is service-only' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'The transport batch is bounded between one and one hundred'
      using errcode = '22023';
  end if;
  return app.reserve_push_attempts_work(p_limit);
end
$fn$;

revoke all on function public.reserve_push_attempts(integer) from public, anon, authenticated;
grant execute on function public.reserve_push_attempts(integer) to service_role;

create function app.authorize_push_attempt_work(p_attempt_id uuid, p_reservation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_push_attempts%rowtype;
  v_device public.member_devices%rowtype;
  v_row public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_hour integer;
  v_refusal text;
  v_deferred timestamptz;
  v_ttl integer := 3600;
begin
  select a.* into v_attempt from public.notification_push_attempts a
   where a.id = p_attempt_id and a.reservation_id = p_reservation_id
   for update;

  if v_attempt.id is null then
    raise exception 'Push work unavailable' using errcode = 'P0002';
  end if;

  if not app.push_configuration_ready(v_attempt.tenant_id)
     or not exists (
       select 1 from public.notifications n
       join public.push_provider_configurations c on c.tenant_id = n.tenant_id
       where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
         and n.created_at >= c.activated_at
     ) then
    return jsonb_build_object('authorized', false,
      'attemptId', v_attempt.id, 'reservationId', v_attempt.reservation_id,
      'reason', 'provider_unconfigured', 'deferredUntil', null::timestamptz);
  end if;

  if v_attempt.started_at is null
     or v_attempt.started_at + interval '90 seconds' < statement_timestamp() then
    raise exception 'The dispatch reservation has expired' using errcode = 'GL115';
  end if;

  select d.* into v_device from public.member_devices d
   where d.id = v_attempt.device_id and d.tenant_id = v_attempt.tenant_id for update;
  select m.* into v_member from public.members m
   where m.tenant_id = v_attempt.tenant_id and m.id = v_attempt.member_id for update;
  select n.* into v_row from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id for update;
  select o.* into v_org from public.organizations o where o.id = v_attempt.tenant_id;

  -- The reservation's own facts must still match the live world exactly.
  if v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp()))
     or v_member.id is null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null
     or v_member.user_id is distinct from v_attempt.registered_user_id
     or v_row.id is null
     or v_row.status is distinct from 'scheduled'::public.notification_status
     or v_row.channel is distinct from 'push'::public.notification_channel
     or v_device.id is null
     or not v_device.is_active
     or v_device.registered_user_id is distinct from v_attempt.registered_user_id
     or v_device.token_revision is distinct from v_attempt.token_revision then
    v_refusal := 'recipient_ineligible';
  elsif exists (select 1 from public.member_notification_preferences p
                 where p.tenant_id = v_attempt.tenant_id
                   and p.member_id = v_attempt.member_id
                   and p.category = v_row.category
                   and p.enabled = false) then
    v_refusal := 'preference_disabled';
  elsif v_row.category = 'motivation'::public.message_category
        and coalesce(v_member.motivation_push_enabled, false) is not true then
    v_refusal := 'motivation_disabled';
  else
    v_purpose := app.notification_consent_purpose(v_row.category);
    select c.granted into v_granted
      from public.consents c
     where c.tenant_id = v_attempt.tenant_id and c.member_id = v_attempt.member_id
       and c.purpose = v_purpose
     order by c.recorded_at desc, c.id desc limit 1;
    if coalesce(v_granted, false) is not true then
      v_refusal := 'consent_withdrawn';
    elsif v_row.category = 'promotion'::public.message_category then
      v_hour := extract(hour from (statement_timestamp() at time zone 'Asia/Kolkata'))::integer;
      if v_hour >= 21 or v_hour < 8 then
        v_refusal := 'quiet_hours';
        v_deferred := date_trunc('day', statement_timestamp() at time zone 'Asia/Kolkata')
                      + interval '1 day' + interval '8 hours';
      else
        v_ttl := extract(epoch from (
          date_trunc('day', statement_timestamp() at time zone 'Asia/Kolkata')
          + interval '1 day' + interval '21 hours'
          - (statement_timestamp() at time zone 'Asia/Kolkata')))::integer;
      end if;
    elsif v_row.related_type = 'announcement' then
      if not exists (select 1 from public.announcements a
                      where a.tenant_id = v_attempt.tenant_id
                        and a.id = v_row.related_id
                        and a.status = 'published'
                        and a.current_version::text = coalesce(v_row.payload ->> 'versionNo', '')
                        and v_attempt.member_id in (select app.announcement_audience(a.id, v_attempt.member_id))) then
        v_refusal := 'source_stale';
      end if;
    elsif v_row.related_type = 'class_session' then
      if not exists (select 1 from public.class_bookings b
                      join public.class_sessions s on s.tenant_id = b.tenant_id and s.id = b.session_id
                      where b.tenant_id = v_attempt.tenant_id
                        and b.session_id = v_row.related_id
                        and b.member_id = v_attempt.member_id
                        and b.status = 'booked'::public.booking_status
                        and s.status = 'scheduled'::public.class_session_status
                        and s.starts_at > statement_timestamp())
         or not exists (select 1 from public.memberships ms
                         where ms.tenant_id = v_attempt.tenant_id
                           and ms.member_id = v_attempt.member_id
                           and ms.status in ('active'::public.membership_status, 'frozen'::public.membership_status)
                           and ms.ends_on >= app.gym_today(v_attempt.tenant_id)) then
        v_refusal := 'source_stale';
      end if;
    elsif v_row.related_type = 'no_show_case' then
      if not exists (select 1 from public.no_show_cases c2
                      where c2.tenant_id = v_attempt.tenant_id
                        and c2.id = v_row.related_id
                        and c2.member_id = v_attempt.member_id
                        and c2.status in ('open'::public.no_show_case_status, 'contacted'::public.no_show_case_status))
         or not app.member_scoring_eligible(v_attempt.tenant_id, v_attempt.member_id, app.gym_today(v_attempt.tenant_id)) then
        v_refusal := 'source_stale';
      end if;
    elsif v_row.related_type = 'membership' then
      if not exists (select 1 from public.memberships ms
                      where ms.tenant_id = v_attempt.tenant_id
                        and ms.id = v_row.related_id
                        and ms.member_id = v_attempt.member_id
                        and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                                          'frozen'::public.membership_status)
                        and ms.ends_on is not null) then
        v_refusal := 'source_stale';
      end if;
    else
      v_refusal := 'source_stale';
    end if;
  end if;

  if v_refusal is not null then
    return jsonb_build_object('authorized', false,
      'attemptId', v_attempt.id, 'reservationId', v_attempt.reservation_id,
      'reason', v_refusal, 'deferredUntil', coalesce(v_deferred, null::timestamptz));
  end if;

  return jsonb_build_object(
    'authorized', true,
    'attemptId', v_attempt.id,
    'reservationId', v_attempt.reservation_id,
    'expiresAt', v_attempt.started_at + interval '90 seconds',
    'token', v_device.push_token,
    'tokenRevision', v_attempt.token_revision,
    'message', jsonb_build_object(
      'title', v_org.name,
      'body', 'You have an update. Open the app to view it.',
      'data', jsonb_build_object(
        'notificationId', v_row.id,
        'sourceNotificationId', v_row.source_notification_id,
        'relatedType', v_row.related_type,
        'relatedId', v_row.related_id),
      'ttlSeconds', greatest(v_ttl, 1))
  );
end
$fn$;

revoke all on function app.authorize_push_attempt_work(uuid, uuid) from public, anon, authenticated;
grant execute on function app.authorize_push_attempt_work(uuid, uuid) to service_role;

create function public.authorize_push_attempt(p_attempt_id uuid, p_reservation_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if current_user <> 'service_role' then
    raise exception 'Transport work is service-only' using errcode = '42501';
  end if;
  return app.authorize_push_attempt_work(p_attempt_id, p_reservation_id);
end
$fn$;

revoke all on function public.authorize_push_attempt(uuid, uuid) from public, anon, authenticated;
grant execute on function public.authorize_push_attempt(uuid, uuid) to service_role;

create function app.finish_push_attempt_work(p_attempt_id uuid, p_reservation_id uuid,
  p_provider_message_id text, p_failure_code text, p_uncertain boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_attempt public.notification_push_attempts%rowtype;
  v_row public.notifications%rowtype;
  v_stored_kind text;
  v_replayed boolean := false;
  v_any_accepted boolean;
  v_all_terminal boolean;
  v_any_uncertain boolean;
  v_known_failure text;
begin
  select a.* into v_attempt from public.notification_push_attempts a
   where a.id = p_attempt_id and a.reservation_id = p_reservation_id
   for update;

  if v_attempt.id is null then
    raise exception 'Push work unavailable' using errcode = 'P0002';
  end if;

  -- One exact result class per call.
  if p_uncertain then
    if p_provider_message_id is not null or p_failure_code is not null then
      raise exception 'An uncertain finish carries no result fields' using errcode = '22023';
    end if;
    v_stored_kind := 'uncertain';
  elsif p_provider_message_id is not null then
    if p_failure_code is not null or btrim(p_provider_message_id) = ''
       or char_length(btrim(p_provider_message_id)) > 256 then
      raise exception 'An accepted finish carries its provider id only' using errcode = '22023';
    end if;
    v_stored_kind := 'accepted';
  else
    if p_failure_code is null or btrim(p_failure_code) = '' or char_length(btrim(p_failure_code)) > 64 then
      raise exception 'A rejected finish carries its bounded failure code' using errcode = '22023';
    end if;
    v_stored_kind := 'rejected';
  end if;

  if v_attempt.completed_at is not null or v_attempt.uncertain_at is not null then
    -- Terminal already: exact replay only, never a second result.
    v_replayed := coalesce(
      (v_stored_kind = 'accepted' and v_attempt.provider_message_id = btrim(p_provider_message_id))
      or (v_stored_kind = 'rejected' and v_attempt.failure_code = btrim(p_failure_code))
      or (v_stored_kind = 'uncertain' and v_attempt.uncertain_at is not null and v_attempt.provider_message_id is null),
      false);
    if not v_replayed then
      raise exception 'This attempt already carries a different recorded result' using errcode = 'GL068';
    end if;
  elsif v_stored_kind = 'accepted' then
    update public.notification_push_attempts
       set completed_at = statement_timestamp(), provider_message_id = btrim(p_provider_message_id)
     where id = v_attempt.id
     returning * into v_attempt;
  elsif v_stored_kind = 'rejected' then
    update public.notification_push_attempts
       set completed_at = statement_timestamp(), failure_code = btrim(p_failure_code)
     where id = v_attempt.id
     returning * into v_attempt;
  else
    update public.notification_push_attempts
       set uncertain_at = statement_timestamp()
     where id = v_attempt.id
     returning * into v_attempt;
  end if;

  -- Notification rollup: one accepted device makes the notification sent; all
  -- devices terminal with no acceptance makes it failed (uncertainty reason
  -- when applicable). Acknowledged history is never regressed.
  select n.* into v_row from public.notifications n
   where n.tenant_id = v_attempt.tenant_id and n.id = v_attempt.notification_id
   for update;

  if v_row.id is not null and v_row.status = 'scheduled'::public.notification_status then
    select bool_or(a.provider_message_id is not null and a.uncertain_at is null),
           bool_and(a.completed_at is not null or a.uncertain_at is not null),
           bool_or(a.uncertain_at is not null),
           max(a.failure_code)
      into v_any_accepted, v_all_terminal, v_any_uncertain, v_known_failure
      from public.notification_push_attempts a
     where a.tenant_id = v_attempt.tenant_id and a.notification_id = v_attempt.notification_id;

    if coalesce(v_any_accepted, false) then
      update public.notifications set status = 'sent'
       where tenant_id = v_attempt.tenant_id and id = v_attempt.notification_id
       returning * into v_row;
    elsif coalesce(v_all_terminal, false) then
      update public.notifications
         set status = 'failed',
             failed_reason = case when coalesce(v_any_uncertain, false)
                             then 'delivery_unknown' else coalesce(v_known_failure, 'provider_rejected') end
       where tenant_id = v_attempt.tenant_id and id = v_attempt.notification_id
       returning * into v_row;
    end if;
  end if;

  return jsonb_build_object('attemptId', v_attempt.id, 'replayed', v_replayed,
    'notification', app.notification_result_json(v_row));
end
$fn$;

revoke all on function app.finish_push_attempt_work(uuid, uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function app.finish_push_attempt_work(uuid, uuid, text, text, boolean) to service_role;

create function public.finish_push_attempt(p_attempt_id uuid, p_reservation_id uuid,
  p_provider_message_id text, p_failure_code text, p_uncertain boolean)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if current_user <> 'service_role' then
    raise exception 'Transport work is service-only' using errcode = '42501';
  end if;
  return app.finish_push_attempt_work(p_attempt_id, p_reservation_id, p_provider_message_id, p_failure_code, p_uncertain);
end
$fn$;

revoke all on function public.finish_push_attempt(uuid, uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.finish_push_attempt(uuid, uuid, text, text, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 10. app.run_push_events: trusted SQL scheduling. Creates missing eligible
--     inbox events per existing source keys, and (only when configured, never
--     back-filling pre-activation events) push children. Ordinary callers have
--     no EXECUTE; cron work runs in the trusted postgres context.
-- ---------------------------------------------------------------------------
create function app.run_push_events(p_tenant_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_configured boolean := app.push_configuration_ready(p_tenant_id);
  v_activated timestamptz;
  v_events integer := 0;
  v_children integer := 0;
  v_reminders integer := 0;
  v_absence integer := 0;
  v_ann uuid;
  v_ver integer;
  v_title text;
  v_kind public.announcement_kind;
  v_member uuid;
  v_notif uuid;
begin
  select c.activated_at into v_activated
    from public.push_provider_configurations c where c.tenant_id = p_tenant_id;

  -- 1. Reviewed-campaign inbox events (source truth, unconfigured-safe).
  for v_ann, v_ver, v_title, v_kind, v_member in
    select c.announcement_id, a.current_version, av.title, a.kind, m.id
      from public.notification_push_campaigns c
      join public.announcements a on a.tenant_id = c.tenant_id and a.id = c.announcement_id
      join public.announcement_versions av on av.tenant_id = c.tenant_id
           and av.announcement_id = c.announcement_id and av.version_no = c.version_no
      join public.members m on m.tenant_id = c.tenant_id
     where c.tenant_id = p_tenant_id
       and c.cancelled_at is null
       and a.status = 'published'
       and a.current_version = c.version_no
       and m.id in (select app.announcement_audience(c.announcement_id))
       and m.status in ('active'::public.member_status, 'paused'::public.member_status, 'expired'::public.member_status)
       and m.erased_at is null
     order by c.announcement_id, m.id
     limit 100
  loop
    if not exists (select 1 from public.notifications n
                    where n.tenant_id = p_tenant_id
                      and n.dedupe_key = 'announcement:' || v_ann::text || ':v'
                          || v_ver::text || ':' || v_member::text) then
      insert into public.notifications
        (tenant_id, member_id, channel, status, category, dedupe_key, related_type, related_id, scheduled_for, payload)
      values
        (p_tenant_id, v_member, 'in_app', 'scheduled',
         case when v_kind = 'transactional' then 'announcement'::public.message_category
              else 'promotion'::public.message_category end,
         'announcement:' || v_ann::text || ':v' || v_ver::text || ':' || v_member::text,
         'announcement', v_ann, statement_timestamp(),
         jsonb_build_object('body', v_title, 'announcementId', v_ann, 'versionNo', v_ver));
      v_events := v_events + 1;
    end if;
  end loop;

  -- 2. Push children of sent in-app events (configured only; cutoff honored;
  --    no backfill of pre-activation events).
  if v_configured then
    for v_notif in
      select n.id from public.notifications n
       where n.tenant_id = p_tenant_id
         and n.channel = 'in_app'::public.notification_channel
         and n.status = 'sent'::public.notification_status
         and n.created_at >= v_activated
       order by n.created_at desc
       limit 100
    loop
      exit when v_children >= 100;
      if not exists (select 1 from public.notifications c
                      where c.tenant_id = p_tenant_id
                        and c.dedupe_key = 'push:' || v_notif::text) then
        insert into public.notifications
          (tenant_id, member_id, channel, status, category, dedupe_key, related_type, related_id,
           source_notification_id, scheduled_for, payload)
        select n.tenant_id, n.member_id, 'push', 'scheduled', n.category,
               'push:' || n.id::text, n.related_type, n.related_id, n.id,
               statement_timestamp(), n.payload
          from public.notifications n
         where n.tenant_id = p_tenant_id and n.id = v_notif;
        v_children := v_children + 1;
      end if;
    end loop;
  end if;

  -- 3. Class reminders: one per booked member per upcoming session
  --    (created unconfigured too; in-app truth does not wait for the provider).
  if true then
    for v_notif, v_member in
      select s.id, b.member_id
        from public.class_bookings b
        join public.class_sessions s on s.tenant_id = b.tenant_id and s.id = b.session_id
       where b.tenant_id = p_tenant_id
         and b.status = 'booked'::public.booking_status
         and s.status = 'scheduled'::public.class_session_status
         and s.starts_at > statement_timestamp()
         and s.starts_at <= statement_timestamp() + interval '60 minutes'
       order by s.starts_at, b.member_id
       limit 100
    loop
      if not exists (select 1 from public.notifications n
                      where n.tenant_id = p_tenant_id
                        and n.dedupe_key = 'class-reminder:' || v_notif::text || ':' || v_member::text) then
        insert into public.notifications
          (tenant_id, member_id, channel, status, category, dedupe_key, related_type, related_id, scheduled_for, payload)
        values
          (p_tenant_id, v_member, 'in_app', 'scheduled', 'class_update',
           'class-reminder:' || v_notif::text || ':' || v_member::text,
           'class_session', v_notif, statement_timestamp(),
           jsonb_build_object('body', 'Your class starts soon. Open the app for details.'));
        v_reminders := v_reminders + 1;
      end if;
    end loop;
  end if;

  -- 4. Absence alerts: once per current open no-show case, at least seven
  --    completed eligible absence days, behind the GRD scoring gate.
  for v_notif, v_member in
    select c.id, c.member_id
      from public.no_show_cases c
     where c.tenant_id = p_tenant_id
       and c.status = 'open'::public.no_show_case_status
       and c.opened_on <= app.gym_today(p_tenant_id) - 7
       and app.member_scoring_eligible(p_tenant_id, c.member_id, app.gym_today(p_tenant_id))
     order by c.id
     limit 100
  loop
    if not exists (select 1 from public.notifications n
                    where n.tenant_id = p_tenant_id
                      and n.dedupe_key = 'absence:' || v_notif::text || ':' || v_member::text) then
      insert into public.notifications
        (tenant_id, member_id, channel, status, category, dedupe_key, related_type, related_id, scheduled_for, payload)
      values
        (p_tenant_id, v_member, 'in_app', 'scheduled', 'motivation',
         'absence:' || v_notif::text || ':' || v_member::text,
         'no_show_case', v_notif, statement_timestamp(),
         jsonb_build_object('body', 'We have missed you at the gym. Open the app to pick up where you left off.'));
      v_absence := v_absence + 1;
    end if;
  end loop;

  return jsonb_build_object('announcementEvents', v_events, 'pushChildren', v_children,
    'classReminders', v_reminders, 'absenceEvents', v_absence);
end
$fn$;

revoke all on function app.run_push_events(uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11. app.enforce_notification amendment: push scheduled->sent requires a
--     durable, non-uncertain recorded provider acceptance for this exact
--     notification. Data evidence, never a session flag or current_user test.
-- ---------------------------------------------------------------------------
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
         and new.source_notification_id is not null
         and new.template_key is null then
        select s.* into v_source
          from public.notifications s
         where s.tenant_id = new.tenant_id
           and s.id = new.source_notification_id
           and s.member_id = new.member_id;
        if v_source.id is null
           or v_source.category is distinct from new.category
           or v_source.related_type is distinct from new.related_type
           or v_source.related_id is distinct from new.related_id
           or v_source.template_key is distinct from 'renewal_reminder' then
          raise exception 'A renewal WhatsApp child must be an unchanged mirror of its renewal source'
            using errcode = 'GL066';
        end if;
      else
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

-- ---------------------------------------------------------------------------
-- 12. public.send_notification amendment: only the guarded push branch
--     changes. Configured push is admitted to the SQL-owned transport and
--     returns the current result without writing sent; the unconfigured
--     terminal failed/provider_unconfigured behavior is preserved exactly,
--     and unconfigured-era rows are never revived.
-- ---------------------------------------------------------------------------
create or replace function public.send_notification(p_notification_id uuid)
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
    if app.push_configuration_ready() then
      -- Configured push is admitted to the SQL-owned transport work; queueing
      -- is neither acceptance nor sent. The immutable schedule stands.
      return app.notification_result_json(v_row);
    end if;
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
-- 13. In-migration privilege assertions (ADR-074): the matrix is proven here,
--     not trusted from comments.
-- ---------------------------------------------------------------------------
do $check$
begin
  -- Member/admin commands: authenticated only, postgres-owned definers.
  if not has_function_privilege('authenticated', 'public.register_member_push_device(uuid,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.register_member_push_device(uuid,text,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.register_member_push_device(uuid,text,text)', 'EXECUTE') then
    raise exception 'push_delivery: register_member_push_device grant matrix wrong';
  end if;
  if not has_function_privilege('authenticated', 'public.acknowledge_member_push(uuid,uuid,bigint,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.acknowledge_member_push(uuid,uuid,bigint,text)', 'EXECUTE') then
    raise exception 'push_delivery: acknowledge_member_push grant matrix wrong';
  end if;
  if not has_function_privilege('authenticated', 'public.review_announcement_push(uuid,integer,uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.review_announcement_push(uuid,integer,uuid)', 'EXECUTE') then
    raise exception 'push_delivery: review_announcement_push grant matrix wrong';
  end if;
  -- Transport facades: service_role only.
  if not has_function_privilege('service_role', 'public.reserve_push_attempts(integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.reserve_push_attempts(integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.reserve_push_attempts(integer)', 'EXECUTE') then
    raise exception 'push_delivery: reserve_push_attempts grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.finish_push_attempt(uuid,uuid,text,text,boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.finish_push_attempt(uuid,uuid,text,text,boolean)', 'EXECUTE') then
    raise exception 'push_delivery: finish_push_attempt grant matrix wrong';
  end if;
  if not has_function_privilege('service_role', 'public.authorize_push_attempt(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.authorize_push_attempt(uuid,uuid)', 'EXECUTE') then
    raise exception 'push_delivery: authorize_push_attempt grant matrix wrong';
  end if;
  -- Front-office campaign reader: authenticated (and service), never anon.
  if not has_function_privilege('authenticated', 'public.read_push_campaigns(timestamp with time zone,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.read_push_campaigns(timestamp with time zone,uuid)', 'EXECUTE') then
    raise exception 'push_delivery: read_push_campaigns grant matrix wrong';
  end if;
  -- Event runner: no ordinary caller at all.
  if has_function_privilege('authenticated', 'app.run_push_events(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'app.run_push_events(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'app.run_push_events(uuid)', 'EXECUTE') then
    raise exception 'push_delivery: run_push_events grant matrix wrong';
  end if;
  -- Tables: devices and attempts inaccessible to ordinary roles.
  if has_table_privilege('authenticated', 'public.member_devices', 'SELECT')
     or has_table_privilege('authenticated', 'public.member_devices', 'INSERT')
     or has_table_privilege('authenticated', 'public.member_devices', 'UPDATE')
     or has_table_privilege('anon', 'public.member_devices', 'SELECT') then
    raise exception 'push_delivery: member_devices privilege matrix wrong';
  end if;
  if has_table_privilege('authenticated', to_regclass('public.notification_push_attempts'), 'SELECT')
     or has_table_privilege('anon', to_regclass('public.notification_push_attempts'), 'SELECT')
     or has_table_privilege('service_role', to_regclass('public.notification_push_attempts'), 'INSERT')
     or has_table_privilege('service_role', to_regclass('public.notification_push_attempts'), 'UPDATE')
     or has_table_privilege('service_role', to_regclass('public.notification_push_attempts'), 'DELETE') then
    raise exception 'push_delivery: notification_push_attempts privilege matrix wrong';
  end if;
  if not has_table_privilege('authenticated', to_regclass('public.member_notification_preferences'), 'SELECT')
     or has_table_privilege('authenticated', to_regclass('public.member_notification_preferences'), 'INSERT') then
    raise exception 'push_delivery: member_notification_preferences privilege matrix wrong';
  end if;
  if not has_table_privilege('authenticated', to_regclass('public.notification_push_campaigns'), 'SELECT')
     or has_table_privilege('authenticated', to_regclass('public.notification_push_campaigns'), 'INSERT') then
    raise exception 'push_delivery: notification_push_campaigns privilege matrix wrong';
  end if;
end
$check$;

