-- BUY: member purchase requests and private payment claims (PAY).
-- Frozen contract: openspec/changes/member-purchases/proposal.md (FROZEN
-- 2026-10-03) + approved contract-resolution-amendment.md.
-- Applied by CI only. Never applied by hand. Every test wraps its own
-- BEGIN/ROLLBACK; this migration itself is forward-only.
--
-- Owner-approved resolutions folded in: hard stock holds for accepted
-- requests (GL123), mismatch_recorded honest terminal outcome, renewals at
-- the held membership's recorded sold terms. Existing surfaces amended
-- narrowly: record_addon_sale / create_shop_reservation refuse only when an
-- active PAY hard hold causes the shortage; read_member_shop availability
-- and the direct stock-update guard account for accepted holds.

create type public.purchase_request_kind as enum ('shop', 'pt', 'renewal');
create type public.purchase_request_status as enum (
  'requested', 'owner_accepted', 'payment_proof_uploaded',
  'recorded', 'mismatch_recorded', 'rejected', 'cancelled', 'expired');
create type public.payment_proof_status as enum ('active', 'superseded', 'rejected', 'bound');

-- ---------------------------------------------------------------------------
-- purchase_requests
-- ---------------------------------------------------------------------------
create table public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  member_id uuid not null,
  kind public.purchase_request_kind not null,
  target_id uuid not null,
  request_key uuid not null,
  quantity integer not null
    constraint purchase_requests_quantity_chk check (quantity between 1 and 10),
  snapshot jsonb not null,
  quote_revision uuid,
  reconfirmed_revision uuid,
  status public.purchase_request_status not null default 'requested',
  active_proof_asset_id uuid,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_revision uuid,
  accepted_at timestamptz,
  accepted_by_user_id uuid,
  accepted_by_staff_id uuid,
  reject_reason text,
  rejected_at timestamptz,
  rejected_by_user_id uuid,
  rejected_by_staff_id uuid,
  cancelled_at timestamptz,
  cancelled_by_user_id uuid,
  recorded_payment_id uuid,
  recorded_order_id uuid,
  recorded_membership_id uuid,
  recorded_amount_paise bigint,
  recorded_currency text,
  currency text generated always as (coalesce(recorded_currency, 'INR'::text)) stored not null
    constraint purchase_requests_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  recorded_at timestamptz,
  recorded_by_user_id uuid,
  recorded_by_staff_id uuid,
  hold_consumed_at timestamptz,
  expired_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint purchase_requests_tenant_id_member_id_fkey
    foreign key (tenant_id, member_id) references public.members(tenant_id, id),
  constraint purchase_requests_tenant_id_recorded_payment_fkey
    foreign key (tenant_id, recorded_payment_id) references public.payments(tenant_id, id),
  constraint purchase_requests_tenant_id_recorded_order_fkey
    foreign key (tenant_id, recorded_order_id) references public.addon_orders(tenant_id, id),
  constraint purchase_requests_tenant_id_recorded_membership_fkey
    foreign key (tenant_id, recorded_membership_id) references public.memberships(tenant_id, id),
  constraint purchase_requests_tenant_id_id_key unique (tenant_id, id),
  constraint purchase_requests_tenant_id_request_key_open_key
    unique (tenant_id, request_key),
  constraint purchase_requests_expires_after_created_chk
    check (expires_at > created_at),
  constraint purchase_requests_reason_bounds_chk
    check (reject_reason is null or (btrim(reject_reason) = reject_reason
      and char_length(reject_reason) between 3 and 200))
);
create index purchase_requests_tenant_id_member_idx
  on public.purchase_requests (tenant_id, member_id);
create index purchase_requests_tenant_id_member_created_idx
  on public.purchase_requests (tenant_id, member_id, created_at desc, id desc);
create index purchase_requests_tenant_id_status_target_idx
  on public.purchase_requests (tenant_id, status, kind, target_id)
  where status in ('owner_accepted', 'payment_proof_uploaded');
create unique index purchase_requests_tenant_id_payment_once_key
  on public.purchase_requests (tenant_id, recorded_payment_id)
  where recorded_payment_id is not null;
create unique index purchase_requests_tenant_id_order_once_key
  on public.purchase_requests (tenant_id, recorded_order_id)
  where recorded_order_id is not null;
create unique index purchase_requests_tenant_id_member_open_key
  on public.purchase_requests (tenant_id, member_id, kind, request_key)
  where status in ('requested', 'owner_accepted', 'payment_proof_uploaded');

-- ---------------------------------------------------------------------------
-- payment_proofs — a screenshot is the member's claim, never money.
-- ---------------------------------------------------------------------------
create table public.payment_proofs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  request_id uuid not null,
  asset_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  disposition public.payment_proof_status not null default 'active',
  decided_at timestamptz,
  decided_by_user_id uuid,
  decided_by_staff_id uuid,
  decision_reason text,
  bound_payment_id uuid,
  bound_at timestamptz,
  object_purge_after timestamptz,
  hold_until timestamptz,
  constraint payment_proofs_tenant_id_request_id_fkey
    foreign key (tenant_id, request_id) references public.purchase_requests(tenant_id, id),
  constraint payment_proofs_tenant_id_asset_id_fkey
    foreign key (tenant_id, asset_id) references public.media_assets(tenant_id, id),
  constraint payment_proofs_tenant_id_bound_payment_fkey
    foreign key (tenant_id, bound_payment_id) references public.payments(tenant_id, id),
  constraint payment_proofs_tenant_id_request_asset_key
    unique (tenant_id, request_id, asset_id),
  constraint payment_proofs_tenant_id_asset_once_key
    unique (tenant_id, asset_id),
  constraint payment_proofs_bound_requires_decision_chk
    check ((bound_payment_id is null and bound_at is null)
      or (bound_payment_id is not null and bound_at is not null
        and decided_at is not null and decided_by_user_id is not null))
);
create unique index payment_proofs_tenant_id_request_active_key
  on public.payment_proofs (tenant_id, request_id)
  where disposition = 'active';
create unique index payment_proofs_tenant_id_payment_once_key
  on public.payment_proofs (tenant_id, bound_payment_id)
  where bound_payment_id is not null;
create index payment_proofs_tenant_id_request_created_idx
  on public.payment_proofs (tenant_id, request_id, created_at desc, id desc);
create index payment_proofs_tenant_id_member_created_idx
  on public.payment_proofs (tenant_id, created_by_user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS and privileges
-- ---------------------------------------------------------------------------
alter table public.purchase_requests enable row level security;
alter table public.payment_proofs enable row level security;

create policy purchase_requests_tenant_select
  on public.purchase_requests for select to authenticated
  using (
    tenant_id = (select app.current_tenant_id())
    and (
      (app.current_app_role() = 'member'
        and app.current_staff_id() is null
        and member_id = app.current_member_id())
      or
      (app.current_app_role() in ('gym_owner', 'gym_manager', 'front_desk')
        and app.current_member_id() is null)
    )
  );

-- payment_proofs: no policy at all — authenticated reads nothing directly;
-- the safe read RPCs and the private proof-url path are the only doors.
revoke all on public.purchase_requests, public.payment_proofs from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on public.purchase_requests from authenticated, service_role;
revoke all on public.payment_proofs from authenticated, service_role;
grant select on public.purchase_requests to authenticated;
grant select on public.purchase_requests, public.payment_proofs to service_role;

-- ---------------------------------------------------------------------------
-- Private machinery (schema app; never exposed by config.toml)
-- ---------------------------------------------------------------------------
create table app.pay_stock_allowance (
  token uuid primary key,
  tenant_id uuid not null,
  product_id uuid not null,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create table app.purchase_request_commands (
  tenant_id uuid not null,
  request_id uuid not null,
  command_key uuid not null,
  command text not null,
  facts jsonb not null,
  actor_user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, request_id, command_key, command)
);

-- Capability guard: trusted outer commands mint a one-shot transaction-local
-- token bound to (capability, tenant, request); every guarded definer helper
-- consumes it as its first act and independently re-proves a real unimpersonated
-- front-office identity. A plain session can neither mint a usable token (the
-- take re-proves staff identity) nor reuse one (one-shot delete-on-take).
create table app.pay_capabilities (
  token uuid primary key,
  capability text not null,
  actor_kind text not null,
  tenant_id uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now()
);

create function app.pay_grant_capability(
  p_cap text, p_tenant_id uuid, p_request_id uuid, p_actor_kind text
) returns uuid
language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_token uuid := gen_random_uuid();
begin
  if p_actor_kind is null or p_actor_kind not in ('member', 'staff')
    or p_cap is null or p_tenant_id is null or p_request_id is null then
    raise exception 'Capability arguments required' using errcode = '22023';
  end if;
  insert into app.pay_capabilities(token, capability, actor_kind, tenant_id, request_id)
    values (v_token, p_cap, p_actor_kind, p_tenant_id, p_request_id);
  return v_token;
end
$fn$;

create function app.pay_take_capability(
  p_cap text, p_tenant_id uuid, p_request_id uuid, p_actor_kind text
) returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_token text;
begin
  -- The token alone proves nothing: the taker re-proves the minted actor class.
  if p_actor_kind = 'member' then
    if auth.uid() is null or app.current_app_role() is distinct from 'member'
      or app.current_staff_id() is not null or app.current_member_id() is null
      or app.current_impersonation_id() is not null then
      raise exception 'Capability requires the owning member session' using errcode = '42501';
    end if;
  else
    if auth.uid() is null or app.is_front_office() is not true
      or app.current_impersonation_id() is not null
      or app.current_member_id() is not null
      or not exists (select 1 from public.staff s
           where s.tenant_id = p_tenant_id and s.id = app.current_staff_id()
             and s.user_id = auth.uid() and s.role::text = app.current_app_role()
             and s.is_active) then
      raise exception 'Capability requires a real front-office session' using errcode = '42501';
    end if;
  end if;
  -- Validate-only: the row is transaction-scoped (dies with the transaction on
  -- any outcome), minted only by a trusted outer command that has already proven
  -- the actor it speaks for. Member-minted rows unlock only the member-safe
  -- helpers; every staff-side helper re-proves staff identity above.
  if not exists (select 1 from app.pay_capabilities c
       where c.capability = p_cap and c.actor_kind = p_actor_kind
         and c.tenant_id = p_tenant_id and c.request_id = p_request_id) then
    raise exception 'Capability token is not valid for this command'
      using errcode = '42501';
  end if;
end
$fn$;

create function app.pay_held_quantity(p_tenant_id uuid, p_product_id uuid)
returns integer
language sql stable security invoker set search_path = ''
as $fn$
  select coalesce(sum(r.quantity), 0)::integer
    from public.purchase_requests r
   where r.tenant_id = p_tenant_id
     and r.kind = 'shop'
     and r.target_id = p_product_id
     and r.status in ('owner_accepted', 'payment_proof_uploaded')
     and r.expires_at > statement_timestamp()
     and r.hold_consumed_at is null
$fn$;

create function app.pay_audit(
  p_tenant_id uuid, p_actor_user_id uuid, p_role text, p_action text,
  p_record_type text, p_record_id uuid,
  p_before jsonb, p_after jsonb, p_reason text,
  p_request_key uuid, p_facts jsonb
) returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_action is null or p_action not in (
    'purchase_request.created','purchase_request.accepted','purchase_request.quote_reconfirmed',
    'purchase_request.rejected','purchase_request.cancelled','purchase_request.expired',
    'purchase_request.recorded','payment_proof.attached','payment_proof.superseded',
    'payment_proof.rejected','payment_proof.bound'
  ) then
    raise exception 'Unsupported purchase audit action' using errcode = '22023';
  end if;
  if (p_request_key is null) <> (p_facts is null) then
    raise exception 'Audit request evidence is incomplete' using errcode = '22023';
  end if;
  insert into public.audit_log(
    tenant_id, actor_user_id, actor_role, action, record_type, record_id,
    before, after, reason, request_key, request_facts
  ) values (
    p_tenant_id, p_actor_user_id, p_role::public.app_role, p_action,
    p_record_type, p_record_id, p_before, p_after, p_reason,
    p_request_key, p_facts
  );
end
$fn$;

create function app.pay_command_record(
  p_tenant_id uuid, p_request_id uuid, p_command_key uuid,
  p_command text, p_facts jsonb, p_actor_user_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_existing app.purchase_request_commands%rowtype;
begin
  perform app.pay_take_capability('command_note', p_tenant_id, p_request_id,
    case when p_command in ('create','cancel','reconfirm','attach','register') then 'member' else 'staff' end);
  select * into v_existing
    from app.purchase_request_commands c
   where c.tenant_id = p_tenant_id and c.request_id = p_request_id
     and c.command_key = p_command_key and c.command = p_command;
  if found then return to_jsonb(v_existing); end if;
  insert into app.purchase_request_commands(
    tenant_id, request_id, command_key, command, facts, actor_user_id
  ) values (p_tenant_id, p_request_id, p_command_key, p_command, p_facts, p_actor_user_id);
  return null;
end
$fn$;

create function app.pay_command_lookup(
  p_tenant_id uuid, p_request_id uuid, p_command_key uuid, p_command text
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $fn$
declare v_row app.purchase_request_commands%rowtype;
begin
  perform app.pay_take_capability('command_note', p_tenant_id, p_request_id,
    case when p_command in ('create','cancel','reconfirm','attach','register') then 'member' else 'staff' end);
  select * into v_row
    from app.purchase_request_commands c
   where c.tenant_id = p_tenant_id and c.request_id = p_request_id
     and c.command_key = p_command_key and c.command = p_command;
  if found then return to_jsonb(v_row); end if;
  return null;
end
$fn$;

-- Service-only expiry materialization: closure and its audit exactly once;
-- expired holds cease holding through the predicate even without this.
create function app.expire_purchase_requests(
  p_cutoff timestamptz default statement_timestamp()
) returns integer
language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_count integer := 0; v_request public.purchase_requests%rowtype;
begin
  for v_request in
    select r.* from public.purchase_requests r
     where r.status in ('requested', 'owner_accepted', 'payment_proof_uploaded')
       and r.expires_at <= p_cutoff
     order by r.created_at, r.id
     for update
  loop
    update public.purchase_requests
       set status = 'expired', expired_at = p_cutoff, updated_at = now()
     where tenant_id = v_request.tenant_id and id = v_request.id
       and status = v_request.status;
    if found then
      perform app.pay_audit(
        v_request.tenant_id, null, 'gym_owner', 'purchase_request.expired',
        'purchase_request', v_request.id,
        jsonb_build_object('status', v_request.status),
        jsonb_build_object('status', 'expired'),
        null, null, null);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end
$fn$;

-- ---------------------------------------------------------------------------
-- payment_proofs triggers: bound trusted writers too (BUY-019)
-- ---------------------------------------------------------------------------
create function app.enforce_payment_proof() returns trigger
language plpgsql volatile security invoker set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' then
    if new.disposition is distinct from 'active'
      or new.decided_at is not null or new.decided_by_staff_id is not null
      or new.decided_by_user_id is not null or new.bound_payment_id is not null
      or new.bound_at is not null or new.decision_reason is not null then
      raise exception 'Proof rows must start active and undecided'
        using errcode = 'GL066', detail = 'proof_facts_frozen';
    end if;
    if not exists (
      select 1 from public.media_assets m
       where m.tenant_id = new.tenant_id and m.id = new.asset_id
         and m.kind = 'payment_proof' and m.confirmed_at is not null
    ) then
      raise exception 'Proof asset is not a verified payment proof'
        using errcode = 'GL066', detail = 'media_not_ready';
    end if;
    return new;
  end if;
  if row(new.id, new.tenant_id, new.request_id, new.asset_id,
         new.created_by_user_id, new.created_at)
    is distinct from row(old.id, old.tenant_id, old.request_id, old.asset_id,
         old.created_by_user_id, old.created_at) then
    raise exception 'Proof registration facts are frozen'
      using errcode = 'GL066', detail = 'proof_facts_frozen';
  end if;
  if old.disposition in ('superseded', 'rejected', 'bound') then
    raise exception 'Proof disposition is terminal'
      using errcode = 'GL066', detail = 'proof_state_invalid';
  end if;
  if row(new.bound_payment_id, new.bound_at)
    is distinct from row(old.bound_payment_id, old.bound_at)
    and new.disposition is distinct from 'bound' then
    raise exception 'Proof binding moves only at binding'
      using errcode = 'GL066', detail = 'proof_state_invalid';
  end if;
  if new.disposition = 'superseded'
    and (new.decided_at is null or new.decided_by_user_id is null) then
    raise exception 'Proof decision evidence is incomplete'
      using errcode = 'GL066', detail = 'proof_state_invalid';
  end if;
  if new.disposition = 'rejected'
    and (new.decided_at is null or new.decided_by_user_id is null
      or new.decision_reason is null
      or char_length(btrim(new.decision_reason)) not between 3 and 200
      or btrim(new.decision_reason) <> new.decision_reason) then
    raise exception 'Proof decision evidence is incomplete'
      using errcode = 'GL066', detail = 'proof_state_invalid';
  end if;
  if new.disposition = 'bound'
    and (new.bound_payment_id is null or new.bound_at is null
      or new.decided_at is null or new.decided_by_user_id is null) then
    raise exception 'Proof decision evidence is incomplete'
      using errcode = 'GL066', detail = 'proof_state_invalid';
  end if;
  if new.disposition = 'active' and new is not distinct from old then
    null;
  end if;
  return new;
end
$fn$;
create trigger payment_proofs_enforce
  before insert or update on public.payment_proofs
  for each row execute function app.enforce_payment_proof();

-- ---------------------------------------------------------------------------
-- purchase_requests trigger: frozen identity + state machine (BUY-005/015/019)
-- ---------------------------------------------------------------------------
create function app.enforce_purchase_request() returns trigger
language plpgsql volatile security invoker set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'requested'
      or new.accepted_at is not null or new.accepted_by_user_id is not null
      or new.rejected_at is not null or new.cancelled_at is not null
      or new.recorded_at is not null or new.expired_at is not null
      or new.recorded_payment_id is not null or new.recorded_order_id is not null
      or new.recorded_membership_id is not null
      or new.hold_consumed_at is not null
      or new.active_proof_asset_id is not null then
      raise exception 'Requests must start requested'
        using errcode = 'GL066', detail = 'request_state_invalid';
    end if;
    return new;
  end if;
  if row(new.id, new.tenant_id, new.member_id, new.kind, new.target_id,
         new.request_key, new.quantity, new.quote_revision,
         new.created_by_user_id, new.created_at)
    is distinct from row(old.id, old.tenant_id, old.member_id, old.kind,
         old.target_id, old.request_key, old.quantity,
         old.quote_revision, old.created_by_user_id, old.created_at) then
    raise exception 'Request facts are frozen'
      using errcode = 'GL066', detail = 'request_facts_frozen';
  end if;
  if new.snapshot is distinct from old.snapshot
    and not (new.reconfirmed_revision is not null
      and new.reconfirmed_revision is distinct from old.reconfirmed_revision) then
    raise exception 'Request facts are frozen'
      using errcode = 'GL066', detail = 'request_facts_frozen';
  end if;
  if old.status = new.status and new is not distinct from old then
    return new;
  end if;
  if old.status in ('recorded', 'mismatch_recorded', 'rejected', 'cancelled', 'expired') then
    raise exception 'Request state is terminal'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if old.status <> new.status and not (
       (old.status = 'requested'
         and new.status in ('owner_accepted', 'rejected', 'cancelled', 'expired'))
    or (old.status = 'owner_accepted'
         and new.status in ('payment_proof_uploaded', 'rejected', 'recorded', 'mismatch_recorded',
                            'cancelled', 'expired'))
    or (old.status = 'payment_proof_uploaded'
         and new.status in ('owner_accepted', 'recorded', 'mismatch_recorded',
                            'cancelled', 'expired'))
  ) then
    raise exception 'Request transition is not permitted'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status = 'owner_accepted'
    and (new.accepted_at is null or new.accepted_by_user_id is null) then
    raise exception 'Acceptance evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status = 'rejected'
    and (new.rejected_at is null or new.reject_reason is null) then
    raise exception 'Closure evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status = 'cancelled' and new.cancelled_at is null then
    raise exception 'Closure evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status = 'expired' and new.expired_at is null then
    raise exception 'Closure evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status in ('recorded', 'mismatch_recorded')
    and (new.recorded_at is null or new.recorded_payment_id is null
      or new.recorded_amount_paise is null or new.recorded_currency is null) then
    raise exception 'Recording evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if new.status = 'recorded' and new.kind = 'shop'
    and new.recorded_order_id is null then
    raise exception 'Recording evidence is incomplete'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  return new;
end
$fn$;
create trigger purchase_requests_enforce
  before insert or update on public.purchase_requests
  for each row execute function app.enforce_purchase_request();

-- ---------------------------------------------------------------------------
-- MEDIA: the payment_proof kind, member creator, private proof namespace.
-- The visible proof flow registers through register_payment_proof and
-- publishes through the trusted credential verifier; the proof kind is not
-- reachable through the public catalogue signer or staff photo readers.
-- ---------------------------------------------------------------------------
alter table public.media_assets alter column created_by_staff_id drop not null;
alter table public.media_assets add column created_by_member_id uuid;
alter table public.media_assets add constraint media_assets_tenant_id_created_by_member_fkey
  foreign key (tenant_id, created_by_member_id) references public.members(tenant_id, id);
create index media_assets_tenant_id_created_by_member_created_idx
  on public.media_assets (tenant_id, created_by_member_id, created_at desc);

-- Registration-time request linkage: the member's staging registration binds
-- the asset to the live accepted request it was staged for, so the trusted
-- finalizer can re-prove that exact request live and accepted at publish
-- time (BUY-008/010) — including before the first attach.
alter table public.media_assets add column linked_request_id uuid;
alter table public.media_assets add constraint media_assets_tenant_id_linked_request_fkey
  foreign key (tenant_id, linked_request_id) references public.purchase_requests(tenant_id, id);
create index media_assets_tenant_id_linked_request_idx
  on public.media_assets (tenant_id, linked_request_id)
  where linked_request_id is not null;

alter table public.media_assets drop constraint media_assets_kind_chk;
alter table public.media_assets add constraint media_assets_kind_chk
  check (kind in ('product', 'trainer', 'announcement', 'payment_proof'));

alter table public.media_assets drop constraint media_assets_staging_object_key_format_chk;
alter table public.media_assets add constraint media_assets_staging_object_key_format_chk
  check (staging_object_key ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/staging/(product|trainer|announcement|payment_proof)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$');

alter table public.media_assets drop constraint media_assets_object_key_format_chk;
alter table public.media_assets add constraint media_assets_object_key_format_chk
  check (object_key is null or object_key ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement|payment_proof)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$');

alter table public.media_assets drop constraint media_assets_verification_shape_chk;
alter table public.media_assets add constraint media_assets_verification_shape_chk check (
  (kind = 'payment_proof'
    and ((confirmed_at is null and object_key is null)
      or (confirmed_at is not null and object_key is not null)))
  or (kind <> 'payment_proof'
    and ((confirmed_at is null and object_key is null and verified_source_etag is null and published_etag is null)
      or (confirmed_at is not null and object_key is not null and verified_source_etag is not null
        and published_etag is not null and btrim(verified_source_etag) <> '' and btrim(published_etag) <> '')))
);

create or replace function app.enforce_media_asset_verification() returns trigger
language plpgsql volatile security invoker set search_path = ''
as $fn$
declare
  v_claims jsonb;
  v_trusted boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'Media metadata is retained' using errcode='GL086',detail='media_verification_invariant';
  end if;
  v_claims := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  v_trusted := (current_user = 'postgres' or current_user = 'service_role')
    and v_claims->>'role' is distinct from 'authenticated'
    and nullif(v_claims->>'sub', '') is null
    and nullif(v_claims->>'impersonation_session_id', '') is null;
  if tg_op = 'INSERT' then
    if new.kind = 'payment_proof' then
      if (new.confirmed_at is not null or new.object_key is not null) then
        if not v_trusted
          or new.object_key is null or new.confirmed_at is null
          or new.attached_to_id is not null or new.deleted_at is not null
          or new.object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/payment_proof/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
          or split_part(new.object_key, '/', 1) <> new.tenant_id::text then
          raise exception 'Only the credential verifier may publish' using errcode='GL086',detail='media_verification_invariant';
        end if;
        return new;
      end if;
      if new.verified_source_etag is not null or new.published_etag is not null
        or new.attached_to_id is not null or new.deleted_at is not null then
        raise exception 'Media must start unverified and unattached' using errcode='GL086',detail='media_verification_invariant';
      end if;
      return new;
    end if;
    if new.confirmed_at is not null or new.object_key is not null or new.verified_source_etag is not null
      or new.published_etag is not null or new.attached_to_id is not null or new.deleted_at is not null then
      raise exception 'Media must start unverified and unattached' using errcode='GL086',detail='media_verification_invariant';
    end if;
    return new;
  end if;
  if row(new.id, new.tenant_id, new.kind, new.staging_object_key, new.mime, new.bytes,
         new.created_by_staff_id, new.created_by_member_id, new.linked_request_id, new.created_at)
    is distinct from row(old.id, old.tenant_id, old.kind, old.staging_object_key, old.mime, old.bytes,
         old.created_by_staff_id, old.created_by_member_id, old.linked_request_id, old.created_at)
    or (old.deleted_at is not null and new is distinct from old) then
    raise exception 'Media registration and tombstones are immutable' using errcode='GL086',detail='media_verification_invariant';
  end if;
  if row(new.object_key, new.verified_source_etag, new.published_etag, new.confirmed_at)
    is distinct from row(old.object_key, old.verified_source_etag, old.published_etag, old.confirmed_at) then
    if old.confirmed_at is not null or old.deleted_at is not null or old.object_key is not null
      or old.verified_source_etag is not null or old.published_etag is not null
      or new.confirmed_at is null or new.object_key is null
      or new.attached_to_id is distinct from old.attached_to_id or new.deleted_at is distinct from old.deleted_at
      or (new.kind <> 'payment_proof'
        and (current_user <> 'postgres'
          or current_setting('role', true) is distinct from 'service_role'))
      or (new.kind = 'payment_proof' and not v_trusted)
      or current_setting('app.media_finalize_command', true) is distinct from ('finalize:' || old.id::text) then
      raise exception 'Only the credential verifier may publish' using errcode='GL086',detail='media_verification_invariant';
    end if;
    if new.kind = 'payment_proof' then
      if new.object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/payment_proof/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
        or split_part(new.object_key, '/', 1) <> new.tenant_id::text
        or split_part(new.object_key, '/', 3) <> new.kind
        or split_part(new.object_key, '.', 2) <> (case new.mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
        raise exception 'Only the credential verifier may publish' using errcode='GL086',detail='media_verification_invariant';
      end if;
    else
      if new.verified_source_etag is null or new.published_etag is null
        or btrim(new.verified_source_etag) = '' or btrim(new.published_etag) = ''
        or new.object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
        or split_part(new.object_key, '/', 1) <> new.tenant_id::text or split_part(new.object_key, '/', 3) <> new.kind
        or split_part(new.object_key, '.', 2) <> (case new.mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
        raise exception 'Only the credential verifier may publish' using errcode='GL086',detail='media_verification_invariant';
      end if;
    end if;
  end if;
  if new.attached_to_id is not null and (new.confirmed_at is null or new.deleted_at is not null)
    or (old.attached_to_id is not null and new.attached_to_id is not null and old.attached_to_id <> new.attached_to_id)
    or (new.deleted_at is not null and new.attached_to_id is not null) then
    raise exception 'Media attachment state is invalid' using errcode='GL086',detail='media_verification_invariant';
  end if;
  return new;
end
$fn$;

-- Member-side private proof registration: server generates the key; the
-- member never chooses a key. Proves a live owned accepted request.
create function public.register_payment_proof(
  p_request_id uuid, p_mime text, p_bytes integer
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c_bytes constant integer := 2097152;
  c_hourly constant integer := 60;
  c_member_hourly constant integer := 10;
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_id uuid;
  v_ext text;
  v_key text;
  v_prior record;
begin
  select * into v_actor from app.shop_actor('member');
  if p_request_id is null or p_mime is null or p_bytes is null then
    raise exception 'Registration arguments required' using errcode = '22023';
  end if;
  if p_mime not in ('image/jpeg', 'image/png', 'image/webp')
    or p_bytes is null or p_bytes <= 0 or p_bytes > c_bytes then
    raise exception 'Malformed proof registration' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));
  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
     and r.member_id = v_actor.member_id;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_request.status not in ('owner_accepted', 'payment_proof_uploaded')
    or v_request.expires_at <= statement_timestamp() then
    raise exception 'Proof upload needs an accepted live request'
      using errcode = 'GL066', detail = 'request_not_accepted';
  end if;
  if (select count(*) from public.media_assets m
       where m.tenant_id = v_actor.tenant_id and m.kind = 'payment_proof'
         and m.created_by_member_id = v_actor.member_id
         and m.created_at > statement_timestamp() - interval '1 hour')
    >= c_member_hourly then
    raise exception 'Proof registration limit reached' using errcode = '22023', detail = 'purchase_cap';
  end if;
  if (select count(*) from public.media_assets m
       where m.tenant_id = v_actor.tenant_id
         and m.created_at > statement_timestamp() - interval '1 hour')
    >= c_hourly then
    raise exception 'Media registration limit reached' using errcode = 'GL086', detail = 'media_limit';
  end if;
  v_ext := case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' else 'webp' end;
  v_id := gen_random_uuid();
  v_key := v_actor.tenant_id::text || '/staging/payment_proof/' || v_id::text || '.' || v_ext;
  -- Replacement (BUY-010): this registration supersedes the member's own
  -- still-unconfirmed candidate for the same request — tombstoned, never
  -- deleted, and never touching a confirmed or attached winner.
  for v_prior in
    select m.id from public.media_assets m
     where m.tenant_id = v_actor.tenant_id and m.kind = 'payment_proof'
       and m.created_by_member_id = v_actor.member_id
       and m.linked_request_id = v_request.id
       and m.confirmed_at is null and m.deleted_at is null and m.attached_to_id is null
       and m.created_at <= statement_timestamp()
     for update
  loop
    update public.media_assets set deleted_at = statement_timestamp()
     where id = v_prior.id and tenant_id = v_actor.tenant_id;
    perform app.media_audit(v_actor.tenant_id, v_actor.user_id, 'member',
      'media_asset.deleted', v_prior.id,
      jsonb_build_object('deleted', false), jsonb_build_object('deleted', true));
  end loop;
  insert into public.media_assets(
    tenant_id, kind, staging_object_key, mime, bytes,
    created_by_staff_id, created_by_member_id, linked_request_id, created_at
  ) values (
    v_actor.tenant_id, 'payment_proof', v_key, p_mime, p_bytes,
    null, v_actor.member_id, v_request.id, statement_timestamp()
  ) returning media_assets.id into v_id;
  return jsonb_build_object(
    'assetId', v_id, 'stagingObjectKey', v_key,
    'mime', p_mime, 'bytes', p_bytes
  );
end
$fn$;

-- Keyed registration replay (frozen decision 5): one logical upload keeps one
-- command UUID. Same actor/key and same normalized request/MIME/bytes return
-- the original registration result read-only — no second candidate, counter
-- use or deadline; changed facts conflict (GL068). The unkeyed overload above
-- stays for callers that register without retry identity.
create function public.register_payment_proof(
  p_request_id uuid, p_mime text, p_bytes integer, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_existing jsonb;
  v_facts jsonb;
  v_asset public.media_assets%rowtype;
  v_result jsonb;
begin
  select * into v_actor from app.shop_actor('member');
  if p_command_key is null then
    raise exception 'Registration arguments required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));
  v_facts := jsonb_build_object('mime', p_mime, 'bytes', p_bytes);
  -- The command-table seam's take re-proves a minted capability row; the
  -- register path mints its own member-class capability here, exactly as the
  -- attach command does, so the lookup's take resolves instead of starving.
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'member');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'register');
  if v_existing is not null then
    -- Replay compares the CALLER-comparable facts only (frozen decision 5):
    -- the stored facts additionally carry the mint's own assetId output,
    -- which no caller can know at replay time, so the equality test
    -- normalizes to requestId (the lookup keys on it) + mime + bytes + actor.
    -- Every accessor below pins the jsonb type explicitly: the runtime
    -- capture showed `text ->> unknown` when the seam's return/row value
    -- resolved as text, and a text left-operand must never reach `->>`.
    if ((v_existing::jsonb)->'facts'->>'mime') = p_mime
      and ((v_existing::jsonb)->'facts'->>'bytes')::integer = p_bytes
      and (v_existing::jsonb)->>'actor_user_id' = v_actor.user_id::text then
      -- Read-only replay of the original registration result: same asset, same
      -- staging facts, no second counter use or deadline.
      select a.* into v_asset from public.media_assets a
       where a.tenant_id = v_actor.tenant_id
         and a.id = ((v_existing::jsonb)->'facts'->>'assetId')::uuid;
      if not found then
        raise exception 'Proof registration key already named different facts'
          using errcode = 'GL068', detail = 'idempotency_conflict';
      end if;
      return jsonb_build_object(
        'assetId', v_asset.id, 'stagingObjectKey', v_asset.staging_object_key,
        'mime', p_mime, 'bytes', p_bytes);
    end if;
    raise exception 'Proof registration key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;
  v_result := public.register_payment_proof(p_request_id, p_mime, p_bytes);
  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'register',
    jsonb_build_object('assetId', ((v_result::jsonb)->>'assetId')::uuid, 'mime', p_mime, 'bytes', p_bytes),
    v_actor.user_id);
  return v_result;
end
$fn$;

-- ---------------------------------------------------------------------------
-- AMENDED (PAY): the credential-only finalizer learns the member-creator path
-- for payment_proof assets. Staff-created photo behavior is unchanged; a
-- member-created proof finalizes only through its registered member creator,
-- into the private payment_proof namespace, and only while the registered
-- request is still live and accepted (registration-time linkage).
-- ---------------------------------------------------------------------------
create or replace function public.finalize_media_asset(p_asset_id uuid,p_actor_user_id uuid,p_actor_staff_id uuid,p_actor_role public.app_role,
  p_tenant_id uuid,p_kind text,p_mime text,p_bytes integer,p_staging_object_key text,p_source_etag text,p_published_object_key text,p_published_etag text)
returns boolean language plpgsql volatile security definer set search_path='' as $fn$
declare
  v_claims jsonb;
  v_asset public.media_assets%rowtype;
  v_prior_marker text;
  v_member_path boolean := false;
begin
  v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  if current_setting('role',true) is distinct from 'service_role' or v_claims->>'role' is distinct from 'service_role'
    or nullif(v_claims->>'sub','') is not null or nullif(v_claims->>'impersonation_session_id','') is not null then
    raise exception 'Credential-only verifier required' using errcode='42501';
  end if;
  -- Lock the active actor before the asset; revocation and finalization serialize.
  if p_actor_role='member' and p_actor_staff_id is null then
    if p_actor_user_id is null or p_tenant_id is null then
      raise exception 'Verified active media actor required' using errcode='42501';
    end if;
    -- The member gate re-proves the live member row exactly as the staff path
    -- re-proves the staff row: status and binding at finalize time. Cancelled,
    -- blocked, paused, expired or erased creators refuse here (42501), before
    -- any asset or liveness check.
    perform 1 from public.members m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id
      and m.status='active' and m.erased_at is null for update;
    if not found then
      raise exception 'Verified active media actor required' using errcode='42501';
    end if;
    v_member_path:=true;
  else
    perform 1 from public.staff s where s.id=p_actor_staff_id and s.tenant_id=p_tenant_id and s.user_id=p_actor_user_id
      and s.role=p_actor_role and s.is_active and s.role in ('gym_owner','gym_manager','front_desk') for update;
    if not found or p_actor_user_id is null or p_actor_staff_id is null or p_tenant_id is null
      or p_actor_role is null or (p_kind in ('product','trainer') and p_actor_role='front_desk') then
      raise exception 'Verified active media actor required' using errcode='42501';
    end if;
  end if;
  select m.* into v_asset from public.media_assets m where m.id=p_asset_id and m.tenant_id=p_tenant_id for update;
  if not found then raise exception 'Media asset unavailable' using errcode='42501'; end if;
  if v_member_path then
    -- Only the asset's registered member creator, only for a payment_proof asset.
    if v_asset.kind is distinct from 'payment_proof' or v_asset.created_by_member_id is null
      or not exists (select 1 from public.members m where m.tenant_id=p_tenant_id
        and m.id=v_asset.created_by_member_id and m.user_id=p_actor_user_id) then
      raise exception 'Verified actor cannot finalize this media kind' using errcode='42501';
    end if;
  else
    -- A staff actor can never finalize a member-created proof.
    if v_asset.created_by_member_id is not null
      or (v_asset.kind in ('product','trainer') and p_actor_role='front_desk') then
      raise exception 'Verified actor cannot finalize this media kind' using errcode='42501';
    end if;
  end if;
  if v_asset.deleted_at is not null then
    raise exception 'Media asset is deleted' using errcode='GL086',detail='media_not_ready';
  end if;
  if p_kind is null or p_kind not in ('product','trainer','announcement','payment_proof') or p_kind is distinct from v_asset.kind
    or p_mime is distinct from v_asset.mime or p_bytes is distinct from v_asset.bytes
    or p_staging_object_key is distinct from v_asset.staging_object_key
    or p_source_etag is null or btrim(p_source_etag)='' or p_published_etag is null or btrim(p_published_etag)=''
    or p_published_object_key is null
    or p_published_object_key !~ (case when p_kind='payment_proof'
      then '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/payment_proof/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
      else '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$' end)
    or split_part(p_published_object_key,'/',1)<>p_tenant_id::text or split_part(p_published_object_key,'/',3)<>p_kind
    or split_part(p_published_object_key,'.',2)<>(case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
    raise exception 'Verified metadata does not match registration' using errcode='22023';
  end if;
  if v_member_path then
    -- The registered request must still be live and accepted at publish time —
    -- and at replay time: a confirmed-asset replay is read-only but not
    -- authority-free, so this revalidation precedes the replay return too.
    if v_asset.linked_request_id is null then
      raise exception 'Proof upload needs an accepted live request' using errcode='GL066',detail='request_not_accepted';
    end if;
    perform 1 from public.purchase_requests r where r.tenant_id=p_tenant_id and r.id=v_asset.linked_request_id
      and r.status in ('owner_accepted','payment_proof_uploaded') and r.expires_at>statement_timestamp();
    if not found then
      raise exception 'Proof upload needs an accepted live request' using errcode='GL066',detail='request_not_accepted';
    end if;
  end if;
  if v_asset.confirmed_at is not null then
    if v_asset.object_key is null or v_asset.verified_source_etag is null or v_asset.published_etag is null
      or btrim(v_asset.verified_source_etag)='' or btrim(v_asset.published_etag)='' then
      raise exception 'Media verification is inconsistent' using errcode='GL086',detail='media_not_ready';
    end if;
    return false;
  end if;
  if v_asset.object_key is not null or v_asset.verified_source_etag is not null or v_asset.published_etag is not null then
    raise exception 'Media verification is inconsistent' using errcode='GL086',detail='media_not_ready';
  end if;
  v_prior_marker:=current_setting('app.media_finalize_command',true);
  perform set_config('app.media_finalize_command','finalize:'||p_asset_id::text,true);
  update public.media_assets set object_key=p_published_object_key,verified_source_etag=p_source_etag,
    published_etag=p_published_etag,confirmed_at=statement_timestamp() where id=p_asset_id and tenant_id=p_tenant_id;
  perform set_config('app.media_finalize_command',coalesce(v_prior_marker,''),true);
  perform app.media_audit(p_tenant_id,p_actor_user_id,p_actor_role,'media_asset.confirmed',p_asset_id,
    jsonb_build_object('confirmed',false),jsonb_build_object('confirmed',true));
  return true;
  -- No exception handler is needed: PostgreSQL restores the transaction-local marker with
  -- the failed command's subtransaction; every successful update restores it immediately.
end
$fn$;

-- ---------------------------------------------------------------------------
-- AMENDED: record_addon_sale learns about accepted PAY hard holds, but only
-- refuses when a PAY hold causes the shortage; everything else is unchanged.
-- ---------------------------------------------------------------------------
create or replace function public.record_addon_sale(
  p_member_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_quote_version uuid,
  p_trainer_staff_id uuid,
  p_initial_starts_at timestamptz,
  p_initial_ends_at timestamptz,
  p_method public.payment_method,
  p_reason text,
  p_idempotency_key uuid
)
returns table (
  order_id uuid,
  payment_id uuid,
  initial_session_id uuid,
  replayed boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_product public.addon_products%rowtype;
  v_existing public.addon_orders%rowtype;
  v_order_id uuid := gen_random_uuid();
  v_payment_id uuid;
  v_session_id uuid;
  v_reason text := nullif(btrim(p_reason), '');
  v_total_numeric numeric;
  v_total bigint;
  v_timezone text;
  v_accept_at timestamptz := transaction_timestamp();
  v_starts_on date;
  v_expires_on date;
  v_snapshot jsonb;
  v_request jsonb;
  v_pay_held integer;
begin
  if auth.uid() is null
     or app.is_front_office() is not true
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'An add-on sale requires a real front-office session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  v_staff := app.current_staff_id();
  if p_member_id is null or p_product_id is null or p_quantity is null
     or p_quote_version is null or p_idempotency_key is null then
    raise exception 'The add-on sale request is incomplete'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'addon-sale:' || v_tenant::text || ':' || p_idempotency_key::text, 0
  ));

  select o.* into v_existing from public.addon_orders o
   where o.tenant_id = v_tenant
     and o.idempotency_key = p_idempotency_key::text;
  if found then
    if v_existing.sold_by_staff_id is not distinct from v_staff
       and v_existing.sale_request->>'memberId' is not distinct from p_member_id::text
       and v_existing.sale_request->>'productId' is not distinct from p_product_id::text
       and (v_existing.sale_request->>'quantity')::integer is not distinct from p_quantity
       and v_existing.sale_request->>'quoteVersion' is not distinct from p_quote_version::text
       and (v_existing.sale_request->>'trainerStaffId')::uuid is not distinct from p_trainer_staff_id
       and (v_existing.sale_request->>'initialStartsAt')::timestamptz is not distinct from p_initial_starts_at
       and (v_existing.sale_request->>'initialEndsAt')::timestamptz is not distinct from p_initial_ends_at
       and (v_existing.sale_request->>'method')::public.payment_method is not distinct from p_method
       and v_existing.sale_request->>'reason' is not distinct from v_reason then
      return query select v_existing.id, v_existing.payment_id,
        v_existing.initial_session_id, true;
      return;
    end if;
    raise exception 'This sale request key already names different facts'
      using errcode = 'GL052', detail = 'idempotency_conflict';
  end if;

  if not exists (
    select 1 from public.members m
     where m.tenant_id = v_tenant and m.id = p_member_id
  ) then
    raise exception 'The member was not found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.members m
     where m.tenant_id = v_tenant and m.id = p_member_id
       and m.status not in ('cancelled', 'blocked') and m.erased_at is null
  ) then
    raise exception 'The member is unavailable for an add-on sale'
      using errcode = 'GL055', detail = 'member_unavailable';
  end if;

  select p.* into v_product from public.addon_products p
   where p.tenant_id = v_tenant and p.id = p_product_id;
  if not found then
    raise exception 'The add-on offer was not found' using errcode = 'P0002';
  end if;
  if not v_product.is_active then
    raise exception 'The add-on offer is unavailable'
      using errcode = 'GL055', detail = 'offer_unavailable';
  end if;
  if v_product.description is null or btrim(v_product.description) = ''
     or v_product.cancellation_terms is null or btrim(v_product.cancellation_terms) = ''
     or v_product.validity_days is null or v_product.validity_days <= 0
     or (
       v_product.kind = 'pt_package' and (
         v_product.trainer_staff_id is null
         or v_product.trainer_qualification is null
         or btrim(v_product.trainer_qualification) = ''
         or v_product.session_count is null
         or v_product.stock_quantity is not null
       )
     )
     or (
       v_product.kind = 'product' and (
         v_product.stock_quantity is null
         or v_product.trainer_staff_id is not null
         or v_product.trainer_qualification is not null
         or v_product.session_count is not null
       )
     )
     or (
       v_product.kind = 'diet_plan' and (
         v_product.stock_quantity is not null
         or v_product.trainer_staff_id is not null
         or v_product.trainer_qualification is not null
         or v_product.session_count is not null
       )
     ) then
    raise exception 'The add-on offer disclosure is incomplete'
      using errcode = 'GL055', detail = 'catalogue_incomplete';
  end if;
  if v_product.currency <> 'INR' then
    raise exception 'This add-on currency is unsupported'
      using errcode = 'GL055', detail = 'unsupported_currency';
  end if;
  if v_product.quote_version is distinct from p_quote_version then
    raise exception 'The displayed add-on quote has changed'
      using errcode = 'GL055', detail = 'quote_changed';
  end if;
  if p_quantity <= 0
     or (v_product.kind in ('pt_package', 'diet_plan') and p_quantity <> 1) then
    raise exception 'The add-on quantity is invalid'
      using errcode = 'GL055', detail = 'invalid_quantity';
  end if;

  -- BUY hard holds: an accepted purchase request reserves stock against every
  -- other consumer. Refuse only when a PAY hold causes the shortage.
  if v_product.kind = 'product' then
    v_pay_held := app.pay_held_view(v_tenant, p_product_id);
    if v_pay_held > 0
       and v_product.stock_quantity - v_pay_held < p_quantity then
      raise exception 'Accepted purchase requests hold this stock'
        using errcode = 'GL123', detail = 'stock_reserved';
    end if;
  end if;

  if v_product.kind = 'pt_package' then
    if p_trainer_staff_id is not null and not exists (
      select 1 from public.staff s
       where s.tenant_id = v_tenant and s.id = p_trainer_staff_id
    ) then
      raise exception 'The requested trainer was not found' using errcode = 'P0002';
    end if;
    if p_trainer_staff_id is null
       or p_trainer_staff_id is distinct from v_product.trainer_staff_id
       or not exists (
         select 1 from public.staff s
          where s.tenant_id = v_tenant and s.id = p_trainer_staff_id
            and s.role = 'trainer' and s.is_active
       ) then
      raise exception 'The selected trainer is unavailable'
        using errcode = 'GL055', detail = 'trainer_unavailable';
    end if;
    if p_initial_starts_at is null or p_initial_ends_at is null then
      raise exception 'A PT sale requires its initial slot'
        using errcode = '22023';
    end if;
    if p_initial_ends_at <= p_initial_starts_at
       or p_initial_starts_at < v_accept_at then
      raise exception 'The initial PT slot is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end if;
  elsif p_trainer_staff_id is not null
        or p_initial_starts_at is not null or p_initial_ends_at is not null then
    raise exception 'Non-PT sales cannot carry PT fields'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  v_total_numeric := v_product.price_paise::numeric * p_quantity::numeric;
  if v_total_numeric > 9223372036854775807::numeric then
    raise exception 'The add-on payment exceeds bigint capacity'
      using errcode = 'GL055', detail = 'invalid_payment';
  end if;
  v_total := v_total_numeric::bigint;
  if v_total > 0 and (p_method is null or p_method = 'razorpay') then
    raise exception 'A paid add-on requires an offline payment method'
      using errcode = 'GL055', detail = 'invalid_payment';
  end if;
  if v_total = 0 and (p_method is not null or v_reason is null) then
    raise exception 'A complimentary add-on requires a reason and no payment method'
      using errcode = 'GL055', detail = 'invalid_payment';
  end if;

  select o.timezone into v_timezone from public.organizations o
   where o.id = v_tenant;
  if v_timezone is null
     or not exists (select 1 from pg_timezone_names where name = v_timezone) then
    raise exception 'The gym timezone is invalid'
      using errcode = 'GL055', detail = 'invalid_validity';
  end if;
  begin
    v_starts_on := (v_accept_at at time zone v_timezone)::date;
    v_expires_on := v_starts_on + (v_product.validity_days - 1);
  exception when others then
    raise exception 'The add-on validity window is invalid'
      using errcode = 'GL055', detail = 'invalid_validity';
  end;
  if v_product.kind = 'pt_package' and (
    p_initial_starts_at < v_starts_on::timestamp at time zone v_timezone
    or p_initial_ends_at > (v_expires_on + 1)::timestamp at time zone v_timezone
  ) then
    raise exception 'The initial PT slot is outside validity'
      using errcode = 'GL055', detail = 'invalid_validity';
  end if;

  v_snapshot := jsonb_build_object(
    'kind', v_product.kind::text,
    'name', v_product.name,
    'description', v_product.description,
    'cancellationTerms', v_product.cancellation_terms,
    'validityDays', v_product.validity_days,
    'trainerQualification', v_product.trainer_qualification
  );
  v_request := jsonb_build_object(
    'memberId', p_member_id::text,
    'productId', p_product_id::text,
    'quantity', p_quantity,
    'quoteVersion', p_quote_version::text,
    'trainerStaffId', p_trainer_staff_id::text,
    'initialStartsAt', p_initial_starts_at::text,
    'initialEndsAt', p_initial_ends_at::text,
    'method', p_method::text,
    'reason', v_reason
  );

  insert into public.addon_orders (
    id, tenant_id, member_id, addon_product_id, status, quantity,
    unit_price_paise, total_paise, currency, trainer_staff_id,
    sessions_total, sessions_used, starts_on, expires_on,
    sold_by_staff_id, idempotency_key, sold_at, sale_snapshot, sale_request
  ) values (
    v_order_id, v_tenant, p_member_id, p_product_id, 'pending', p_quantity,
    v_product.price_paise, v_total, v_product.currency,
    case when v_product.kind = 'pt_package' then p_trainer_staff_id end,
    case when v_product.kind = 'pt_package' then v_product.session_count end,
    0, v_starts_on, v_expires_on, v_staff, p_idempotency_key::text,
    v_accept_at, v_snapshot, v_request
  );

  if v_product.kind = 'pt_package' then
    v_session_id := gen_random_uuid();
    insert into public.pt_sessions (
      id, tenant_id, addon_order_id, trainer_staff_id, member_id,
      starts_at, ends_at, status, notes
    ) values (
      v_session_id, v_tenant, v_order_id, p_trainer_staff_id, p_member_id,
      p_initial_starts_at, p_initial_ends_at, 'scheduled', null
    );
    update public.addon_orders set initial_session_id = v_session_id
     where tenant_id = v_tenant and id = v_order_id;
  end if;

  if v_total > 0 then
    v_payment_id := gen_random_uuid();
    insert into public.payments (
      id, tenant_id, member_id, membership_id, mandate_id, coupon_id,
      amount_paise, currency, status, method, provider, provider_order_id,
      provider_payment_id, recorded_by_staff_id, idempotency_key, notes
    ) values (
      v_payment_id, v_tenant, p_member_id, null, null, null,
      v_total, v_product.currency, 'paid', p_method, null, null,
      null, v_staff, 'addon-sale:' || p_idempotency_key::text, v_reason
    );
  end if;

  update public.addon_orders
     set payment_id = v_payment_id, status = 'paid'
   where tenant_id = v_tenant and id = v_order_id;
  update public.addon_orders set status = 'active'
   where tenant_id = v_tenant and id = v_order_id;
  if v_product.kind = 'product' then
    update public.addon_orders set status = 'completed'
     where tenant_id = v_tenant and id = v_order_id;
  end if;

  return query select v_order_id, v_payment_id, v_session_id, false;
end
$fn$;

revoke all on function public.record_addon_sale(
  uuid, uuid, integer, uuid, uuid, timestamptz, timestamptz,
  public.payment_method, text, uuid
) from public, anon;
grant execute on function public.record_addon_sale(
  uuid, uuid, integer, uuid, uuid, timestamptz, timestamptz,
  public.payment_method, text, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- AMENDED: create_shop_reservation refuses with GL123 when an accepted PAY
-- hold causes the shortage; soft-hold behavior is otherwise unchanged.
-- ---------------------------------------------------------------------------
create or replace function public.create_shop_reservation(p_item_id uuid,p_quantity integer,p_quote_version uuid)
returns table (reservation_id uuid,expires_at timestamptz)
language plpgsql volatile security definer set search_path='' as $fn$
declare
  c_ttl constant interval:=interval '24 hours'; c_open_limit constant integer:=5;
  c_daily_limit constant integer:=10; c_max_quantity constant integer:=10;
  v_actor record; v_product public.addon_products%rowtype; v_member public.members%rowtype;
  v_now timestamptz:=statement_timestamp(); v_id uuid; v_expires timestamptz; v_pay_held integer;
begin
  select * into v_actor from app.shop_actor('member');
  if p_item_id is null or p_quantity is null or p_quote_version is null then raise exception 'Reservation arguments required' using errcode='22023'; end if;
  select p.* into v_product from public.addon_products p where p.tenant_id=v_actor.tenant_id and p.id=p_item_id for update;
  if not found then raise exception 'Item unavailable' using errcode='GL086',detail='item_unavailable'; end if;
  -- Member row serializes cross-product quota decisions after the mandated product lock.
  select m.* into v_member from public.members m where m.tenant_id=v_actor.tenant_id and m.id=v_actor.member_id for update;
  if not found or v_member.user_id is distinct from v_actor.user_id then
    raise exception 'Current bound member required' using errcode='42501';
  end if;
  if v_member.status in ('cancelled','blocked') or v_member.erased_at is not null then
    raise exception 'Member unavailable' using errcode='GL086',detail='member_unavailable';
  end if;
  if not app.shop_offer_listable(v_product) then raise exception 'Item unavailable' using errcode='GL086',detail='item_unavailable'; end if;
  if v_product.quote_version is distinct from p_quote_version then raise exception 'Quote changed' using errcode='GL086',detail='quote_changed'; end if;
  if p_quantity<1 or p_quantity>c_max_quantity or (v_product.kind='diet_plan' and p_quantity<>1) then
    raise exception 'Quantity invalid' using errcode='GL086',detail='invalid_quantity';
  end if;
  if exists(select 1 from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id
    and r.product_id=p_item_id and r.status='reserved' and r.expires_at>v_now) then
    raise exception 'Item already reserved' using errcode='GL086',detail='reservation_exists';
  end if;
  if (select count(*) from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id and r.status='reserved' and r.expires_at>v_now)>=c_open_limit
    or (select count(*) from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id and r.created_at>v_now-c_ttl)>=c_daily_limit then
    raise exception 'Reservation limit reached' using errcode='GL086',detail='reservation_limit';
  end if;
  if v_product.kind='product' then
    v_pay_held:=app.pay_held_quantity(v_actor.tenant_id,p_item_id);
    if v_product.stock_quantity-app.shop_held_quantity(v_actor.tenant_id,p_item_id)-v_pay_held<p_quantity then
      if v_pay_held>0 then
        raise exception 'Accepted purchase requests hold this stock' using errcode='GL123',detail='stock_reserved';
      end if;
      raise exception 'Not enough left to reserve' using errcode='GL087',detail='sold_out';
    end if;
  end if;
  v_expires:=v_now+c_ttl;
  insert into public.shop_reservations(tenant_id,member_id,product_id,product_name,kind,quantity,quote_version,unit_price_paise,currency,expires_at,created_at)
    values(v_actor.tenant_id,v_actor.member_id,p_item_id,v_product.name,v_product.kind,p_quantity,v_product.quote_version,v_product.price_paise,v_product.currency,v_expires,v_now)
    returning id into v_id;
  perform app.shop_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'shop_reservation.created','shop_reservation',v_id,null,
    jsonb_build_object('product_id',p_item_id,'quantity',p_quantity,'quote_version',v_product.quote_version,'expires_at',v_expires),null);
  return query select v_id,v_expires;
end
$fn$;

alter function public.create_shop_reservation(uuid,integer,uuid) owner to postgres;

-- ---------------------------------------------------------------------------
-- AMENDED: read_member_shop availability accounts for active PAY hard holds.
-- ---------------------------------------------------------------------------
create or replace function public.read_member_shop()
returns table (item_id uuid,section text,name text,description text,price_paise text,currency text,gst_rate_bp integer,
  validity_days integer,cancellation_terms text,quote_version uuid,category_id uuid,category_name text,image_asset_id uuid,availability text,available_quantity integer)
language plpgsql stable security definer set search_path='' as $fn$
declare c_catalogue_probe constant integer:=201; v_actor record;
begin
  select * into v_actor from app.shop_actor('member');
  return query select p.id,case when p.kind='product' then 'products' else 'services' end,p.name,p.description,p.price_paise::text,
    p.currency,p.gst_rate_bp::integer,p.validity_days::integer,p.cancellation_terms,p.quote_version,c.id,c.name,m.id,
    case when p.kind='product' and p.stock_quantity-app.shop_held_quantity(p.tenant_id,p.id)-app.pay_held_quantity(p.tenant_id,p.id)<=0 then 'out_of_stock' else 'available' end,
    case when p.kind='product' then greatest(p.stock_quantity-app.shop_held_quantity(p.tenant_id,p.id)-app.pay_held_quantity(p.tenant_id,p.id),0) else null::integer end
    from public.addon_products p
    left join public.shop_categories c on c.tenant_id=p.tenant_id and c.id=p.category_id and c.is_active and p.kind='product'
    left join public.media_assets m on m.tenant_id=p.tenant_id and m.kind='product' and m.attached_to_id=p.id and m.confirmed_at is not null and m.deleted_at is null
    where p.tenant_id=v_actor.tenant_id and app.shop_offer_listable(p)
    order by case when p.kind='product' then 0 else 1 end,c.sort_order nulls last,c.name nulls last,p.sort_order,p.name,p.id
    limit c_catalogue_probe;
end
$fn$;

alter function public.read_member_shop() owner to postgres;

-- ---------------------------------------------------------------------------
-- Direct stock adjustments cannot consume accepted PAY quantity (GL123).
-- The PAY recording path decrements through a one-shot capability row that a
-- session cannot forge: the allowance is inserted only by the definer stock
-- command and the trigger consumes it exactly once.
-- ---------------------------------------------------------------------------
create function app.enforce_pay_stock_holds() returns trigger
language plpgsql volatile security invoker set search_path = ''
as $fn$
declare
  v_token text;
  v_delta integer;
begin
  -- Preserve ADD's sold-kind refusal before PAY's stock arithmetic. This is
  -- the same invoker-visible history check as enforce_addon_product; no new
  -- authority or helper grant is introduced.
  if new.kind is distinct from old.kind and exists (
    select 1 from public.addon_orders o
     where o.tenant_id = old.tenant_id and o.addon_product_id = old.id
  ) then
    raise exception 'Add-on catalogue kind cannot change after a sale'
      using errcode = 'GL055', detail = 'catalogue_incomplete';
  end if;
  if new.stock_quantity is not distinct from old.stock_quantity then
    return new;
  end if;
  if new.stock_quantity is null or old.stock_quantity is null
    or new.stock_quantity >= old.stock_quantity then
    if new.stock_quantity is null and old.stock_quantity is not null
      and old.kind = 'product'
      and app.pay_held_view(old.tenant_id, old.id) > 0 then
      raise exception 'Accepted purchase requests hold this stock' using errcode='GL123',detail='stock_reserved';
    end if;
    return new;
  end if;
  v_delta := (old.stock_quantity - new.stock_quantity);
  v_token := current_setting('app.pay_stock_token', true);
  if v_token is not null then
    delete from app.pay_stock_allowance a
     where a.token::text = v_token
       and a.tenant_id = old.tenant_id
       and a.product_id = old.id
       and a.quantity = v_delta;
    if found then
      -- One-shot: the token is consumed here on purpose. A second decrease in
      -- the same transaction finds no allowance row and fails closed loudly
      -- (GL123 while holds remain) instead of silently riding an open token.
      perform set_config('app.pay_stock_token', '', true);
      return new;
    end if;
  end if;
  if app.pay_held_view(old.tenant_id, old.id) > 0 then
    raise exception 'Accepted purchase requests hold this stock' using errcode='GL123',detail='stock_reserved';
  end if;
  return new;
end
$fn$;
create trigger addon_products_pay_stock_holds
  before update of stock_quantity on public.addon_products
  for each row execute function app.enforce_pay_stock_holds();

-- (The stock decrement itself belongs to the existing fulfilment-effects trigger.)

-- ---------------------------------------------------------------------------
-- Public RPCs
-- ---------------------------------------------------------------------------

-- Safe request detail projection shared by every command and reader.
create function app.pay_request_json(
  p_request public.purchase_requests, p_replayed boolean
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $fn$
begin
  return jsonb_strip_nulls(jsonb_build_object(
    'requestId', p_request.id,
    'requestKey', p_request.request_key,
    'kind', p_request.kind::text,
    'status', p_request.status::text,
    'targetId', p_request.target_id,
    'quantity', p_request.quantity,
    'snapshot', p_request.snapshot,
    'quoteRevision', p_request.quote_revision,
    'createdAt', p_request.created_at,
    'expiresAt', p_request.expires_at,
    'acceptedAt', p_request.accepted_at,
    'acceptedRevision', p_request.accepted_revision,
    'rejectReason', p_request.reject_reason,
    'activeProofAssetId', p_request.active_proof_asset_id,
    'recordedPaymentId', p_request.recorded_payment_id,
    'recordedOrderId', p_request.recorded_order_id,
    'recordedMembershipId', p_request.recorded_membership_id,
    'recordedAmountPaise', p_request.recorded_amount_paise::text,
    'recordedCurrency', p_request.recorded_currency,
    'replayed', p_replayed
  ));
end
$fn$;

-- ---------------------------------------------------------------------------
-- create_purchase_request — member definer, typed intent + disclosed snapshot
-- ---------------------------------------------------------------------------
create function public.create_purchase_request(
  p_request_key uuid,
  p_kind public.purchase_request_kind,
  p_target_id uuid,
  p_quantity integer,
  p_expected_revision uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c_ttl constant interval := interval '24 hours';
  c_open_cap constant integer := 5;
  c_daily_cap constant integer := 10;
  c_max_quantity constant integer := 10;
  v_actor record;
  v_member public.members%rowtype;
  v_product public.addon_products%rowtype;
  v_existing public.purchase_requests%rowtype;
  v_membership public.memberships%rowtype;
  v_plan public.plans%rowtype;
  v_row public.purchase_requests%rowtype;
  v_snapshot jsonb;
  v_now timestamptz := transaction_timestamp();
  v_active integer;
  v_today_count integer;
begin
  select * into v_actor from app.shop_actor('member');
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = v_actor.member_id;
  if not found or v_member.status in ('cancelled', 'blocked')
    or v_member.erased_at is not null then
    raise exception 'The member cannot raise purchase requests here' using errcode = '42501';
  end if;
  if p_request_key is null or p_kind is null or p_target_id is null or p_quantity is null then
    raise exception 'Purchase request arguments required' using errcode = '22023';
  end if;
  if p_quantity < 1 or p_quantity > c_max_quantity then
    raise exception 'The requested quantity is invalid' using errcode = 'GL086', detail = 'invalid_quantity';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || v_actor.member_id::text, 0));

  if p_kind <> 'renewal' and p_expected_revision is null then
    raise exception 'The purchase quote revision is required' using errcode = '22023';
  end if;

  -- BUY-016: the key's current history is returned read-only whatever state it
  -- reached; a terminal request is never reopened and never re-created.
  select r.* into v_existing from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id
     and r.member_id = v_actor.member_id
     and r.kind = p_kind
     and r.request_key = p_request_key
   for update;
  if found then
    if v_existing.kind = p_kind
      and v_existing.target_id = p_target_id
      and v_existing.quantity = p_quantity
      and v_existing.created_by_user_id = v_actor.user_id
      and (p_kind = 'renewal' or v_existing.quote_revision = p_expected_revision) then
      v_row := v_existing;
      return app.pay_request_json(v_row, true);
    end if;
    raise exception 'Purchase request key already names different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select count(*) into v_active from public.purchase_requests
   where tenant_id = v_actor.tenant_id and member_id = v_actor.member_id
     and status in ('requested', 'owner_accepted', 'payment_proof_uploaded')
     and expires_at > v_now;
  if v_active >= c_open_cap then
    raise exception 'Too many open purchase requests' using errcode = '22023', detail = 'purchase_cap';
  end if;

  select count(*) into v_today_count from public.purchase_requests
   where tenant_id = v_actor.tenant_id and member_id = v_actor.member_id
     and created_at > v_now - c_ttl;
  if v_today_count >= c_daily_cap then
    raise exception 'Too many purchase requests raised today' using errcode = '22023', detail = 'purchase_cap';
  end if;

  if p_kind = 'shop' then
    select p.* into v_product from public.addon_products p
     where p.tenant_id = v_actor.tenant_id and p.id = p_target_id;
    if not found then
      raise exception 'The add-on offer was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    if not app.shop_offer_listable(v_product) or v_product.price_paise <= 0 then
      raise exception 'The add-on offer was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    if v_product.quote_version is distinct from p_expected_revision then
      raise exception 'The displayed add-on quote has changed' using errcode = 'GL086', detail = 'quote_changed';
    end if;
    v_snapshot := jsonb_build_object(
      'productId', v_product.id, 'productName', v_product.name,
      'kind', v_product.kind::text, 'description', v_product.description,
      'cancellationTerms', v_product.cancellation_terms,
      'validityDays', v_product.validity_days,
      'gstRateBp', v_product.gst_rate_bp,
      'unitPricePaise', v_product.price_paise::text,
      'pricePaise', (v_product.price_paise::numeric * p_quantity)::text,
      'totalPaise', (v_product.price_paise::numeric * p_quantity)::text,
      'currency', v_product.currency, 'quoteVersion', v_product.quote_version
    );
  elsif p_kind = 'pt' then
    select p.* into v_product from public.addon_products p
     where p.tenant_id = v_actor.tenant_id and p.id = p_target_id;
    if not found then
      raise exception 'The training programme was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    if p_quantity <> 1 then
      raise exception 'The training programme quantity is exactly one' using errcode = 'GL086', detail = 'invalid_quantity';
    end if;
    if v_product.kind is distinct from 'pt_package' or not v_product.is_active
      or v_product.currency <> 'INR' or v_product.price_paise <= 0
      or v_product.trainer_staff_id is null or v_product.session_count is null
      or v_product.description is null or btrim(v_product.description) = ''
      or v_product.cancellation_terms is null or btrim(v_product.cancellation_terms) = ''
      or v_product.validity_days is null or v_product.validity_days <= 0
      or v_product.stock_quantity is not null then
      raise exception 'The training programme was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    if not exists (select 1 from public.staff s
        where s.tenant_id = v_actor.tenant_id and s.id = v_product.trainer_staff_id
          and s.role = 'trainer' and s.is_active) then
      raise exception 'The training programme was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    if v_product.quote_version is distinct from p_expected_revision then
      raise exception 'The displayed training quote has changed' using errcode = 'GL086', detail = 'quote_changed';
    end if;
    v_snapshot := jsonb_build_object(
      'productId', v_product.id, 'productName', v_product.name,
      'kind', v_product.kind::text, 'description', v_product.description,
      'cancellationTerms', v_product.cancellation_terms,
      'validityDays', v_product.validity_days,
      'gstRateBp', v_product.gst_rate_bp,
      'unitPricePaise', v_product.price_paise::text,
      'pricePaise', v_product.price_paise::text,
      'totalPaise', v_product.price_paise::text,
      'currency', v_product.currency, 'quoteVersion', v_product.quote_version,
      'trainerStaffId', v_product.trainer_staff_id,
      'sessionCount', v_product.session_count
    );
  else
    if p_quantity <> 1 then
      raise exception 'The renewal quantity is exactly one' using errcode = 'GL086', detail = 'invalid_quantity';
    end if;
    select m.* into v_membership from public.memberships m
     where m.tenant_id = v_actor.tenant_id and m.id = p_target_id;
    if not found then
      raise exception 'The membership was not found' using errcode = 'P0002';
    end if;
    if v_membership.member_id is distinct from v_actor.member_id then
      raise exception 'The membership was not found' using errcode = 'P0002';
    end if;
    select p.* into v_plan from public.plans p
     where p.tenant_id = v_membership.tenant_id and p.id = v_membership.plan_id;
    if not found or not v_plan.is_active then
      raise exception 'Plan changes are a desk conversation' using errcode = 'GL066', detail = 'plan_unavailable';
    end if;
    if v_membership.status not in ('active', 'frozen') then
      raise exception 'Only an eligible held membership can be renewed here'
        using errcode = 'GL066', detail = 'membership_unavailable';
    end if;
    v_snapshot := jsonb_build_object(
      'membershipId', v_membership.id, 'planId', v_membership.plan_id,
      'planName', v_plan.name,
      'netPricePaise', greatest(v_membership.price_paise - v_membership.discount_paise, 0)::text,
      'grossPricePaise', v_membership.price_paise::text,
      'discountPaise', v_membership.discount_paise::text,
      'currency', v_membership.currency,
      'durationDays', v_plan.duration_days,
      'endsOn', v_membership.ends_on
    );
  end if;

  insert into public.purchase_requests (
    tenant_id, member_id, kind, target_id, request_key, quantity, snapshot,
    quote_revision, created_by_user_id, created_at, expires_at
  ) values (
    v_actor.tenant_id, v_actor.member_id, p_kind, p_target_id, p_request_key,
    p_quantity, v_snapshot,
    case when p_kind = 'renewal' then null else p_expected_revision end,
    v_actor.user_id, v_now, v_now + c_ttl
  ) returning * into v_row;

  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'purchase_request.created',
    'purchase_request', v_row.id, null,
    jsonb_build_object('status', 'requested', 'kind', p_kind::text,
      'targetId', p_target_id, 'quantity', p_quantity,
      'totalPaise', v_snapshot->>'totalPaise', 'currency', v_snapshot->>'currency'),
    null, p_request_key,
    jsonb_build_object('kind', p_kind::text, 'targetId', p_target_id, 'quantity', p_quantity));

  return app.pay_request_json(v_row, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- accept_purchase_request — front-office definer; the hard hold starts here
-- ---------------------------------------------------------------------------
create function public.accept_purchase_request(
  p_request_id uuid, p_expected_revision uuid, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c_ttl constant interval := interval '24 hours';
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_product public.addon_products%rowtype;
  v_membership public.memberships%rowtype;
  v_member public.members%rowtype;
  v_now timestamptz := transaction_timestamp();
  v_pay_held integer;
  v_tz text;
  v_today date;
  v_existing jsonb;
begin
  select * into v_actor from app.shop_actor('front_office');
  if p_request_id is null or p_command_key is null then
    raise exception 'Acceptance arguments required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'staff');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'accept');
  if v_existing is not null then
    select r.* into v_request from public.purchase_requests r
     where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
    if v_existing->>'actor_user_id' = v_actor.user_id::text then
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Acceptance key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_request.status is distinct from 'requested' then
    raise exception 'Request state does not permit acceptance'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = v_request.member_id;
  if not found or v_member.status in ('cancelled', 'blocked')
    or v_member.erased_at is not null then
    raise exception 'The member is unavailable' using errcode = 'GL066', detail = 'member_unavailable';
  end if;

  if v_request.kind in ('shop', 'pt') then
    select p.* into v_product from public.addon_products p
     where p.tenant_id = v_actor.tenant_id and p.id = v_request.target_id
     for update;
    if not found or not v_product.is_active then
      raise exception 'The add-on offer was not found' using errcode = 'GL086', detail = 'item_unavailable';
    end if;
    -- The member's viewed revision is display context: acceptance rechecks the
    -- real commitments (price vs disclosed snapshot, stock, eligibility). A
    -- repriced offer refuses here until the member reconfirms, which refreshes
    -- the snapshot to the live price.
    if nullif(v_request.snapshot->>'unitPricePaise', '')::numeric * v_request.quantity
      is distinct from v_product.price_paise::numeric * v_request.quantity::numeric then
      raise exception 'The displayed quote has changed' using errcode = 'GL086', detail = 'quote_changed';
    end if;
    if v_request.kind = 'shop' then
      v_pay_held := app.pay_held_quantity(v_actor.tenant_id, v_request.target_id);
      if v_product.stock_quantity - app.shop_held_quantity(v_actor.tenant_id, v_request.target_id) - v_pay_held
        < v_request.quantity then
        raise exception 'Accepted purchase requests hold this stock'
          using errcode = 'GL123', detail = 'stock_reserved';
      end if;
    else
      select o.timezone into v_tz from public.organizations o where o.id = v_actor.tenant_id;
      if not app.member_has_live_membership(v_actor.tenant_id, v_request.member_id,
          (v_now at time zone v_tz)::date) then
        raise exception 'A live membership is required' using errcode = 'GL066', detail = 'membership_required';
      end if;
    end if;
  else
    select m.* into v_membership from public.memberships m
     where m.tenant_id = v_actor.tenant_id and m.id = v_request.target_id;
    if not found or v_membership.member_id is distinct from v_request.member_id then
      raise exception 'The membership was not found' using errcode = 'P0002';
    end if;
    if v_membership.status not in ('active', 'frozen') then
      raise exception 'Only an eligible held membership can be renewed here'
        using errcode = 'GL066', detail = 'membership_unavailable';
    end if;
  end if;

  update public.purchase_requests r
     set status = 'owner_accepted',
         accepted_revision = case when r.kind = 'renewal' then gen_random_uuid() else p_expected_revision end,
         accepted_at = v_now,
         accepted_by_user_id = v_actor.user_id,
         accepted_by_staff_id = v_actor.staff_id,
         expires_at = v_now + c_ttl,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'accept',
    jsonb_build_object('acceptedRevision', v_request.accepted_revision), v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'purchase_request.accepted',
    'purchase_request', v_request.id,
    jsonb_build_object('status', 'requested'),
    jsonb_build_object('status', 'owner_accepted',
      'acceptedRevision', v_request.accepted_revision,
      'totalPaise', v_request.snapshot->>'totalPaise', 'currency', v_request.snapshot->>'currency'),
    null, p_command_key, jsonb_build_object('command', 'accept'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- reconfirm_purchase_quote — member definer; explicit revised-quote consent
-- ---------------------------------------------------------------------------
create function public.reconfirm_purchase_quote(
  p_request_id uuid, p_expected_revision uuid, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_product public.addon_products%rowtype;
  v_existing jsonb;
  v_facts jsonb;
  v_unit bigint;
begin
  select * into v_actor from app.shop_actor('member');
  if p_request_id is null or p_command_key is null then
    raise exception 'Reconfirmation arguments required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  v_facts := jsonb_build_object('revision', p_expected_revision);
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'member');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'reconfirm');
  if v_existing is not null then
    if v_existing->'facts' = v_facts and v_existing->>'actor_user_id' = v_actor.user_id::text then
      select r.* into v_request from public.purchase_requests r
       where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Reconfirmation key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
     and r.member_id = v_actor.member_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_request.status is distinct from 'requested'
    or v_request.kind not in ('shop', 'pt') then
    raise exception 'Request state does not permit reconfirmation'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  select p.* into v_product from public.addon_products p
   where p.tenant_id = v_actor.tenant_id and p.id = v_request.target_id;
  if not found or v_product.quote_version is distinct from p_expected_revision then
    raise exception 'The displayed quote has changed' using errcode = 'GL086', detail = 'quote_changed';
  end if;
  v_unit := v_product.price_paise;
  update public.purchase_requests r
     set snapshot = jsonb_set(jsonb_set(jsonb_set(jsonb_set(
           r.snapshot,
           '{unitPricePaise}', to_jsonb(v_unit::text)),
           '{pricePaise}', to_jsonb((v_unit::numeric * r.quantity)::text)),
           '{totalPaise}', to_jsonb((v_unit::numeric * r.quantity)::text)),
           '{quoteVersion}', to_jsonb(v_product.quote_version::text)),
         reconfirmed_revision = p_expected_revision,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'reconfirm',
    v_facts, v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'purchase_request.quote_reconfirmed',
    'purchase_request', v_request.id,
    jsonb_build_object('revision', v_request.reconfirmed_revision),
    jsonb_build_object('revision', p_expected_revision),
    null, p_command_key, jsonb_build_object('command', 'reconfirm'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- cancel_purchase_request — owning member only; hold releases with the state
-- ---------------------------------------------------------------------------
create function public.cancel_purchase_request(
  p_request_id uuid, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_existing jsonb;
  v_facts constant jsonb := '{}'::jsonb;
begin
  select * into v_actor from app.shop_actor('member');
  if p_request_id is null or p_command_key is null then
    raise exception 'Cancellation arguments required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'member');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'cancel');
  if v_existing is not null then
    if v_existing->>'actor_user_id' = v_actor.user_id::text then
      select r.* into v_request from public.purchase_requests r
       where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Cancellation key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
     and r.member_id = v_actor.member_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_request.status not in ('requested', 'owner_accepted', 'payment_proof_uploaded') then
    raise exception 'Request state does not permit cancellation'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;

  update public.purchase_requests r
     set status = 'cancelled',
         cancelled_at = transaction_timestamp(),
         cancelled_by_user_id = v_actor.user_id,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'cancel',
    v_facts, v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'purchase_request.cancelled',
    'purchase_request', v_request.id,
    jsonb_build_object('status', v_request.status),
    jsonb_build_object('status', 'cancelled'),
    null, p_command_key, jsonb_build_object('command', 'cancel'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- reject_purchase_request — front office, member-visible reason
-- ---------------------------------------------------------------------------
create function public.reject_purchase_request(
  p_request_id uuid, p_expected_revision uuid, p_reason text, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_reason text;
  v_existing jsonb;
  v_facts jsonb;
begin
  select * into v_actor from app.shop_actor('front_office');
  v_reason := btrim(p_reason);
  if p_request_id is null or p_command_key is null
    or v_reason is null or char_length(v_reason) not between 3 and 200 then
    raise exception 'A valid rejection reason is required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  v_facts := jsonb_build_object('reason', v_reason, 'revision', p_expected_revision);
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'staff');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'reject_request');
  if v_existing is not null then
    if v_existing->'facts' = v_facts and v_existing->>'actor_user_id' = v_actor.user_id::text then
      select r.* into v_request from public.purchase_requests r
       where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Rejection key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;

  if v_request.status not in ('requested', 'owner_accepted', 'payment_proof_uploaded') then
    raise exception 'Request state does not permit rejection'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;

  update public.purchase_requests r
     set status = 'rejected',
         rejected_at = transaction_timestamp(),
         rejected_by_user_id = v_actor.user_id,
         rejected_by_staff_id = v_actor.staff_id,
         reject_reason = v_reason,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'reject_request',
    v_facts, v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'purchase_request.rejected',
    'purchase_request', v_request.id,
    jsonb_build_object('status', v_request.status),
    jsonb_build_object('status', 'rejected'),
    v_reason, p_command_key, jsonb_build_object('command', 'reject_request'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- attach_payment_proof — owning member; one active proof per request
-- ---------------------------------------------------------------------------
create function public.attach_payment_proof(
  p_request_id uuid, p_asset_id uuid, p_expected_revision uuid, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_old public.payment_proofs%rowtype;
  v_asset public.media_assets%rowtype;
  v_proof_id uuid;
  v_conflict uuid;
  v_existing jsonb;
  v_facts jsonb;
  v_old_found boolean;
begin
  select * into v_actor from app.shop_actor('member');
  if p_request_id is null or p_asset_id is null or p_command_key is null
    or p_expected_revision is null then
    raise exception 'Proof arguments required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  v_facts := jsonb_build_object('assetId', p_asset_id, 'revision', p_expected_revision);
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'member');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'attach');
  if v_existing is not null then
    if v_existing->'facts' = v_facts and v_existing->>'actor_user_id' = v_actor.user_id::text then
      select r.* into v_request from public.purchase_requests r
       where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
      -- BUY-016 replay returns the ORIGINAL command's result read-only: the
      -- proof bound by that exact attach, not the request's current active one.
      return jsonb_set(
        app.pay_request_json(v_request, true),
        '{activeProofAssetId}',
        to_jsonb((v_existing->'facts'->>'assetId')::uuid));
    end if;
    raise exception 'Proof key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
     and r.member_id = v_actor.member_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_request.status not in ('owner_accepted', 'payment_proof_uploaded')
    or v_request.expires_at <= statement_timestamp() then
    raise exception 'Proof upload needs an accepted live request'
      using errcode = 'GL066', detail = 'request_not_accepted';
  end if;
  -- The attach validates the caller's expected revision server-side (BUY-010/016):
  -- a stale screen cannot attach against a request it has not seen.
  if p_expected_revision is distinct from v_request.accepted_revision then
    raise exception 'The request changed; refresh and try again'
      using errcode = 'GL066', detail = 'revision_stale';
  end if;

  select a.* into v_asset from public.media_assets a
   where a.tenant_id = v_actor.tenant_id and a.id = p_asset_id;
  if not found or v_asset.kind is distinct from 'payment_proof'
    or v_asset.confirmed_at is null or v_asset.deleted_at is not null
    or v_asset.created_by_member_id is distinct from v_actor.member_id then
    -- Unknown, foreign, unexposed and wrong-creator assets share one refusal.
    raise exception 'Proof asset is not a verified payment proof'
      using errcode = 'GL086', detail = 'media_not_ready';
  end if;
  -- Exact registration-to-request linkage, enforced independently at
  -- attachment (BUY-008/010): an asset registered for one request is already
  -- bound to that request, so attaching it elsewhere — first attach included —
  -- is the frozen GL124 binding conflict, not a media-seam refusal.
  if v_asset.linked_request_id is distinct from p_request_id then
    raise exception 'This proof already belongs to another request'
      using errcode = 'GL124', detail = 'proof_bound';
  end if;

  select p.id into v_conflict from public.payment_proofs p
   where p.tenant_id = v_actor.tenant_id and p.asset_id = p_asset_id
     and p.request_id is distinct from p_request_id;
  if v_conflict is not null then
    raise exception 'This proof already belongs to another request'
      using errcode = 'GL124', detail = 'proof_bound';
  end if;
  v_old_found := false;
  select p.* into v_old from public.payment_proofs p
   where p.tenant_id = v_actor.tenant_id and p.request_id = p_request_id
     and p.asset_id = p_asset_id;
  if found and v_old.disposition is distinct from 'active' then
    raise exception 'A proof disposition cannot reopen'
      using errcode = 'GL124', detail = 'proof_not_active';
  end if;
  select p.* into v_old from public.payment_proofs p
   where p.tenant_id = v_actor.tenant_id and p.request_id = p_request_id
     and p.disposition = 'active';
  if found then
    v_old_found := true;
  end if;

  if v_old_found and v_old.disposition = 'active' then
    update public.payment_proofs p
       set disposition = 'superseded',
           decided_at = transaction_timestamp(),
           decided_by_user_id = v_actor.user_id
     where p.tenant_id = v_actor.tenant_id and p.id = v_old.id;
    update public.media_assets a set attached_to_id = null
     where a.tenant_id = v_actor.tenant_id and a.id = v_old.asset_id
       and a.attached_to_id = p_request_id;
    perform app.pay_audit(
      v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'payment_proof.superseded',
      'purchase_request', p_request_id,
      jsonb_build_object('assetId', v_old.asset_id, 'disposition', 'active'),
      jsonb_build_object('disposition', 'superseded'),
      null, null, null);
  end if;

  insert into public.payment_proofs (
    tenant_id, request_id, asset_id, created_by_user_id
  ) values (
    v_actor.tenant_id, p_request_id, p_asset_id, v_actor.user_id
  ) returning id into v_proof_id;

  update public.media_assets a set attached_to_id = p_request_id
   where a.tenant_id = v_actor.tenant_id and a.id = p_asset_id
     and a.attached_to_id is null;

  update public.purchase_requests r
     set status = 'payment_proof_uploaded',
         active_proof_asset_id = p_asset_id,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'attach',
    v_facts, v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'payment_proof.attached',
    'purchase_request', p_request_id, null,
    jsonb_build_object('assetId', p_asset_id, 'disposition', 'active'),
    null, p_command_key, jsonb_build_object('command', 'attach'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- reject_payment_proof — desk verification outcome; returns to accepted
-- ---------------------------------------------------------------------------
create function public.reject_payment_proof(
  p_request_id uuid, p_asset_id uuid, p_expected_revision uuid,
  p_reason text, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_proof public.payment_proofs%rowtype;
  v_reason text;
  v_existing jsonb;
  v_facts jsonb;
begin
  select * into v_actor from app.shop_actor('front_office');
  v_reason := btrim(p_reason);
  if p_request_id is null or p_asset_id is null or p_command_key is null
    or v_reason is null or char_length(v_reason) not between 3 and 200 then
    raise exception 'A valid rejection reason is required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  v_facts := jsonb_build_object('assetId', p_asset_id, 'reason', v_reason, 'revision', p_expected_revision);
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'staff');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'reject_proof');
  if v_existing is not null then
    if v_existing->'facts' = v_facts and v_existing->>'actor_user_id' = v_actor.user_id::text then
      select r.* into v_request from public.purchase_requests r
       where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Proof rejection key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;

  if v_request.status is distinct from 'payment_proof_uploaded' then
    raise exception 'Request state does not permit a proof rejection'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;

  select p.* into v_proof from public.payment_proofs p
   where p.tenant_id = v_actor.tenant_id and p.request_id = p_request_id
     and p.asset_id = p_asset_id;
  if not found or v_proof.disposition is distinct from 'active' then
    raise exception 'Proof disposition does not permit this decision'
      using errcode = 'GL124', detail = 'proof_not_active';
  end if;

  update public.payment_proofs p
     set disposition = 'rejected',
         decided_at = transaction_timestamp(),
         decided_by_user_id = v_actor.user_id,
         decided_by_staff_id = v_actor.staff_id,
         decision_reason = v_reason
   where p.tenant_id = v_actor.tenant_id and p.id = v_proof.id;

  update public.media_assets a set attached_to_id = null
   where a.tenant_id = v_actor.tenant_id and a.id = p_asset_id
     and a.attached_to_id = p_request_id;

  update public.purchase_requests r
     set status = 'owner_accepted',
         active_proof_asset_id = null,
         updated_at = now()
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
   returning * into v_request;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'reject_proof',
    v_facts, v_actor.user_id);
  perform app.pay_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.app_role, 'payment_proof.rejected',
    'purchase_request', p_request_id,
    jsonb_build_object('disposition', 'active'),
    jsonb_build_object('disposition', 'rejected'),
    v_reason, p_command_key, jsonb_build_object('command', 'reject_proof'));

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------
-- Recording machinery: definer finalize (the INVOKER record command cannot
-- write the request/proof tables or audit directly) + hold consumption.
-- ---------------------------------------------------------------------------
-- Sold-terms cumulative arithmetic for PAY renewals: the existing grant
-- trigger divides by the membership's gross price, while PAY records against
-- the recorded sold NET terms (contract-resolution #3). This helper mirrors
-- app.grant_periods exactly, with the net price as the denominator, and
-- serializes on the same membership lock.
create function app.pay_extend_membership(
  p_tenant_id uuid, p_membership_id uuid, p_currency text
) returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_net bigint;
  v_price bigint;
  v_discount bigint;
  v_currency text;
  v_duration integer;
  v_starts date;
  v_ends date;
  v_granted integer;
  v_total bigint;
  v_owed integer;
  v_periods integer;
  v_tz text;
  v_today date;
begin
  perform app.pay_take_capability('extend', p_tenant_id, p_membership_id, 'staff');
  select m.price_paise, m.discount_paise, m.currency, m.starts_on, m.ends_on,
         m.periods_granted, p.duration_days
    into v_price, v_discount, v_currency, v_starts, v_ends, v_granted, v_duration
    from public.memberships m
    join public.plans p on p.id = m.plan_id and p.tenant_id = m.tenant_id
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;
  if v_price is null or v_duration is null then
    return;
  end if;
  v_net := v_price - v_discount;
  if v_net <= 0 or v_currency is distinct from p_currency then
    return;
  end if;
  select coalesce(sum(pp.amount_paise), 0)
    into v_total
    from public.payments pp
   where pp.tenant_id = p_tenant_id
     and pp.membership_id = p_membership_id
     and pp.currency = v_currency
     and pp.status in ('paid'::public.payment_status,
                       'refunded'::public.payment_status,
                       'reversed'::public.payment_status);
  v_owed := v_total / v_net;
  v_periods := v_owed - v_granted;
  if v_periods <= 0 then
    return;
  end if;
  select o.timezone into v_tz from public.organizations o where o.id = p_tenant_id;
  if v_tz is null then
    return;
  end if;
  v_today := (pg_catalog.now() at time zone v_tz)::date;
  update public.memberships m
     set ends_on = greatest(m.ends_on, v_today) + (v_duration * v_periods),
         periods_granted = v_owed,
         activated_at = coalesce(m.activated_at, pg_catalog.now()),
         status = case when m.status = 'pending'::public.membership_status
                            and m.starts_on is not null
                            and not exists (
                              select 1 from public.memberships other
                               where other.tenant_id = m.tenant_id
                                 and other.member_id = m.member_id
                                 and other.id <> m.id
                                 and other.status in ('active'::public.membership_status,
                                                      'frozen'::public.membership_status))
                       then 'active'::public.membership_status
                       else m.status end
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
     and m.ends_on is not null;
end
$fn$;

revoke all on function app.pay_extend_membership(uuid,uuid,text) from public, anon, service_role;
grant execute on function app.pay_extend_membership(uuid,uuid,text) to authenticated;

create function app.pay_mark_hold_consumed(
  p_tenant_id uuid, p_request_id uuid, p_command_key uuid,
  p_product_id uuid, p_quantity integer
) returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.pay_take_capability('hold', p_tenant_id, p_request_id, 'staff');
  update public.purchase_requests r
     set hold_consumed_at = transaction_timestamp(), updated_at = now()
   where r.tenant_id = p_tenant_id and r.id = p_request_id
     and r.hold_consumed_at is null;
  -- One-shot capability for the fulfilment trigger's own stock decrement: the
  -- direct stock-adjustment guard accepts the decrease only against this
  -- allowance row, which a session cannot forge and which dies with the
  -- transaction on any failure.
  if p_command_key is not null and p_product_id is not null
    and p_quantity is not null and p_quantity > 0 then
    insert into app.pay_stock_allowance(token, tenant_id, product_id, quantity)
      values (p_command_key, p_tenant_id, p_product_id, p_quantity);
    perform set_config('app.pay_stock_token', p_command_key::text, true);
  end if;
end
$fn$;

create function app.pay_finalize(
  p_tenant_id uuid, p_request_id uuid, p_status text,
  p_payment_id uuid, p_order_id uuid, p_membership_id uuid,
  p_amount bigint, p_currency text,
  p_actor_user_id uuid, p_actor_staff_id uuid, p_role text, p_command_key uuid
) returns public.purchase_requests
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_before public.purchase_requests%rowtype;
  v_after public.purchase_requests%rowtype;
  v_proof public.payment_proofs%rowtype;
begin
  perform app.pay_take_capability('finalize', p_tenant_id, p_request_id, 'staff');
  select r.* into v_before from public.purchase_requests r
   where r.tenant_id = p_tenant_id and r.id = p_request_id
   for update;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;

  update public.purchase_requests r
     set status = p_status::public.purchase_request_status,
         recorded_payment_id = p_payment_id,
         recorded_order_id = p_order_id,
         recorded_membership_id = p_membership_id,
         recorded_amount_paise = p_amount,
         recorded_currency = p_currency,
         recorded_at = transaction_timestamp(),
         recorded_by_user_id = p_actor_user_id,
         recorded_by_staff_id = p_actor_staff_id,
         hold_consumed_at = coalesce(r.hold_consumed_at, transaction_timestamp()),
         updated_at = now()
   where r.tenant_id = p_tenant_id and r.id = p_request_id
   returning * into v_after;

  select p.* into v_proof from public.payment_proofs p
   where p.tenant_id = p_tenant_id and p.request_id = p_request_id
     and p.disposition = 'active';
  if found then
    update public.payment_proofs p
       set disposition = 'bound',
           decided_at = transaction_timestamp(),
           decided_by_user_id = p_actor_user_id,
           bound_payment_id = p_payment_id,
           bound_at = transaction_timestamp()
     where p.tenant_id = p_tenant_id and p.id = v_proof.id;
    perform app.pay_audit(
      p_tenant_id, p_actor_user_id, p_role, 'payment_proof.bound',
      'purchase_request', p_request_id,
      jsonb_build_object('disposition', 'active', 'assetId', v_proof.asset_id),
      jsonb_build_object('disposition', 'bound', 'paymentId', p_payment_id),
      null, null, null);
  end if;

  perform app.pay_audit(
    p_tenant_id, p_actor_user_id, p_role, 'purchase_request.recorded',
    'purchase_request', p_request_id,
    jsonb_build_object('status', v_before.status,
      'totalPaise', v_before.snapshot->>'totalPaise', 'currency', v_before.snapshot->>'currency'),
    jsonb_build_object('status', v_after.status,
      'amountPaise', p_amount::text, 'currency', p_currency,
      'paymentId', p_payment_id, 'orderId', p_order_id,
      'membershipId', p_membership_id),
    null, p_command_key, jsonb_build_object('command', 'record'));

  return v_after;
end
$fn$;

-- ---------------------------------------------------------------------------
-- record_purchase_request — INVOKER, real front-office staff caller only.
-- ---------------------------------------------------------------------------
create function public.record_purchase_request(
  p_request_id uuid, p_expected_revision uuid, p_command_key uuid,
  p_actual_amount text, p_currency text, p_payment_method text,
  p_initial_slot jsonb default null,
  p_viewed_asset uuid default null, p_viewed_proof_revision uuid default null
) returns jsonb
language plpgsql volatile security invoker set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
  v_product public.addon_products%rowtype;
  v_membership public.memberships%rowtype;
  v_member public.members%rowtype;
  v_facts jsonb;
  v_existing jsonb;
  v_amount bigint;
  v_method public.payment_method;
  v_order_id uuid;
  v_payment_id uuid;
  v_session_id uuid;
  v_sale_replayed boolean;
  v_tz text;
  v_initial_slot jsonb;
begin
  if auth.uid() is null
     or app.is_front_office() is not true
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Recording requires a real front-office session' using errcode = '42501';
  end if;
  select auth.uid() as user_id, app.current_tenant_id() as tenant_id,
    app.current_staff_id() as staff_id, null::uuid as member_id,
    app.current_app_role() as app_role
    into v_actor;
  v_initial_slot := p_initial_slot;
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'staff');
  if p_request_id is null or p_command_key is null
    or p_actual_amount is null or p_currency is null or p_payment_method is null then
    raise exception 'Recording arguments required' using errcode = '22023';
  end if;
  if p_actual_amount !~ '^[0-9]+$' or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'Recording arguments required' using errcode = '22023';
  end if;
  v_amount := p_actual_amount::bigint;
  if v_amount <= 0 or v_amount > 9223372036854775807 then
    raise exception 'Recording arguments required' using errcode = '22023';
  end if;
  v_method := p_payment_method::public.payment_method;

  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));

  v_facts := jsonb_build_object(
    'amountPaise', v_amount::text, 'currency', p_currency, 'method', v_method::text,
    'revision', p_expected_revision,
    'viewedAsset', p_viewed_asset, 'viewedRevision', p_viewed_proof_revision);
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'staff');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'record');
  if v_existing is not null then
    select r.* into v_request from public.purchase_requests r
     where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
    if v_existing->'facts' = v_facts
      and v_existing->>'actor_user_id' = v_actor.user_id::text then
      return app.pay_request_json(v_request, true);
    end if;
    raise exception 'Recording key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;

  perform app.pay_grant_capability('hold', v_actor.tenant_id, p_request_id, 'staff');
  perform app.pay_grant_capability('finalize', v_actor.tenant_id, p_request_id, 'staff');
  perform app.pay_grant_capability('extend', v_actor.tenant_id, v_request.target_id, 'staff');

  if v_request.status in ('recorded', 'mismatch_recorded') then
    raise exception 'Recording key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;
  if v_request.status not in ('owner_accepted', 'payment_proof_uploaded') then
    raise exception 'Request state does not permit recording'
      using errcode = 'GL066', detail = 'request_state_invalid';
  end if;
  if v_request.status = 'owner_accepted' and v_method is distinct from 'cash' then
    raise exception 'A verified proof is required before recording'
      using errcode = 'GL066', detail = 'proof_required';
  end if;
  if v_request.expires_at <= statement_timestamp() then
    raise exception 'The request has expired' using errcode = 'GL066', detail = 'request_expired';
  end if;
  -- The recording validates the verifier's expected revision server-side and
  -- binds the decision to the exact currently viewed proof (BUY-010/012/016,
  -- frozen decision 3): a replaced proof invalidates the earlier verifier
  -- context even when the price is unchanged, and a null viewed asset with an
  -- active proof on file is never a proof-backed recording.
  if p_expected_revision is null
    or p_expected_revision is distinct from v_request.accepted_revision then
    raise exception 'The request changed; refresh and try again'
      using errcode = 'GL066', detail = 'revision_stale';
  end if;
  if (p_viewed_asset is null) <> (v_request.active_proof_asset_id is null)
    or (p_viewed_asset is null and p_viewed_proof_revision is not null)
    or (p_viewed_asset is not null and
      (p_viewed_asset is distinct from v_request.active_proof_asset_id
       or p_viewed_proof_revision is null
       or p_viewed_proof_revision is distinct from v_request.accepted_revision)) then
    raise exception 'Recording requires the exact currently viewed proof'
      using errcode = 'GL066', detail = 'proof_viewed_stale';
  end if;
  if nullif(v_request.snapshot->>'currency', '') is distinct from p_currency then
    raise exception 'The accepted currency cannot change' using errcode = '22023';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = v_request.member_id;
  if not found or v_member.status in ('cancelled', 'blocked')
    or v_member.erased_at is not null then
    raise exception 'The member is unavailable' using errcode = 'GL066', detail = 'member_unavailable';
  end if;

  if v_request.kind = 'shop' then
    if v_amount is distinct from nullif(v_request.snapshot->>'totalPaise', '')::bigint then
      insert into public.payments (
        tenant_id, member_id, membership_id, amount_paise, currency, status,
        method, recorded_by_staff_id, idempotency_key, notes
      ) values (
        v_actor.tenant_id, v_request.member_id, null, v_amount, p_currency, 'paid',
        v_method, v_actor.staff_id, 'purchase-request:' || p_command_key::text,
        'Recorded from purchase request')
      returning id into v_payment_id;
      perform app.pay_finalize(
        v_actor.tenant_id, p_request_id, 'mismatch_recorded',
        v_payment_id, null, null, v_amount, p_currency,
        v_actor.user_id, v_actor.staff_id, v_actor.app_role, p_command_key);
    else
      select p.* into v_product from public.addon_products p
       where p.tenant_id = v_actor.tenant_id and p.id = v_request.target_id;
      if not found then
        raise exception 'The add-on offer was not found' using errcode = 'P0002';
      end if;
      if v_product.price_paise::numeric * v_request.quantity
        is distinct from nullif(v_request.snapshot->>'totalPaise', '')::numeric then
        raise exception 'The accepted quote is stale' using errcode = 'GL066', detail = 'quote_changed';
      end if;
      perform app.pay_mark_hold_consumed(v_actor.tenant_id, p_request_id,
        p_command_key, v_request.target_id, v_request.quantity);
      select s.order_id, s.payment_id, s.initial_session_id, s.replayed
        into v_order_id, v_payment_id, v_session_id, v_sale_replayed
        from public.record_addon_sale(
          v_request.member_id, v_request.target_id, v_request.quantity,
          v_product.quote_version, null, null, null,
          v_method, 'Recorded from purchase request', p_command_key) as s
        limit 1;
      perform app.pay_finalize(
        v_actor.tenant_id, p_request_id, 'recorded',
        v_payment_id, v_order_id, null, v_amount, p_currency,
        v_actor.user_id, v_actor.staff_id, v_actor.app_role, p_command_key);
    end if;
  elsif v_request.kind = 'pt' then
    if v_amount is distinct from nullif(v_request.snapshot->>'totalPaise', '')::bigint then
      insert into public.payments (
        tenant_id, member_id, membership_id, amount_paise, currency, status,
        method, recorded_by_staff_id, idempotency_key, notes
      ) values (
        v_actor.tenant_id, v_request.member_id, null, v_amount, p_currency, 'paid',
        v_method, v_actor.staff_id, 'purchase-request:' || p_command_key::text,
        'Recorded from purchase request')
      returning id into v_payment_id;
      perform app.pay_finalize(
        v_actor.tenant_id, p_request_id, 'mismatch_recorded',
        v_payment_id, null, null, v_amount, p_currency,
        v_actor.user_id, v_actor.staff_id, v_actor.app_role, p_command_key);
    else
      select p.* into v_product from public.addon_products p
       where p.tenant_id = v_actor.tenant_id and p.id = v_request.target_id;
      if not found or v_product.quote_version is distinct from v_request.accepted_revision then
        raise exception 'The accepted quote is stale' using errcode = 'GL066', detail = 'quote_changed';
      end if;
      if not app.member_has_live_membership(v_actor.tenant_id, v_request.member_id, current_date) then
        raise exception 'A live membership is required' using errcode = 'GL066', detail = 'membership_required';
      end if;
      -- Contract amendment (MAJOR 5): the verifier supplies the initial slot; it is
      -- validated server-side by record_addon_sale's existing PT booking rules
      -- (trainer binding, slot window, validity). No valid slot -> pt_slot_required.
      if p_initial_slot is null or jsonb_typeof(p_initial_slot) is distinct from 'object'
        or nullif(p_initial_slot->>'startsAt', '') is null
        or nullif(p_initial_slot->>'endsAt', '') is null then
        raise exception 'PT recording needs a session slot' using errcode = 'GL066', detail = 'pt_slot_required';
      end if;
      perform app.pay_mark_hold_consumed(v_actor.tenant_id, p_request_id,
        p_command_key, v_request.target_id, v_request.quantity);
      select s.order_id, s.payment_id, s.initial_session_id, s.replayed
        into v_order_id, v_payment_id, v_session_id, v_sale_replayed
        from public.record_addon_sale(
          v_request.member_id, v_request.target_id, v_request.quantity,
          v_product.quote_version, v_product.trainer_staff_id,
          (v_initial_slot->>'startsAt')::timestamptz,
          (v_initial_slot->>'endsAt')::timestamptz,
          v_method, 'Recorded from purchase request', p_command_key) as s
        limit 1;
      perform app.pay_finalize(
        v_actor.tenant_id, p_request_id, 'recorded',
        v_payment_id, v_order_id, null, v_amount, p_currency,
        v_actor.user_id, v_actor.staff_id, v_actor.app_role, p_command_key);
    end if;
  else
    select m.* into v_membership from public.memberships m
     where m.tenant_id = v_actor.tenant_id and m.id = v_request.target_id;
    if not found or v_membership.member_id is distinct from v_request.member_id then
      raise exception 'The membership was not found' using errcode = 'P0002';
    end if;
    if v_membership.status not in ('active', 'frozen') then
      raise exception 'Only an eligible held membership can be renewed here'
        using errcode = 'GL066', detail = 'membership_unavailable';
    end if;
    if v_membership.currency is distinct from p_currency
      or v_membership.price_paise is distinct from nullif(v_request.snapshot->>'grossPricePaise', '')::bigint
      or v_membership.discount_paise is distinct from nullif(v_request.snapshot->>'discountPaise', '')::bigint then
      raise exception 'The sold terms changed; a fresh acceptance is required'
        using errcode = 'GL066', detail = 'membership_changed';
    end if;
    insert into public.payments (
      tenant_id, member_id, membership_id, amount_paise, currency, status,
      method, recorded_by_staff_id, idempotency_key, notes
    ) values (
      v_actor.tenant_id, v_request.member_id, v_request.target_id, v_amount, p_currency,
      'paid', v_method, v_actor.staff_id,
      'purchase-request:' || p_command_key::text, 'Recorded from purchase request')
    returning id into v_payment_id;
    perform app.pay_finalize(
      v_actor.tenant_id, p_request_id, 'recorded',
      v_payment_id, null, v_request.target_id, v_amount, p_currency,
      v_actor.user_id, v_actor.staff_id, v_actor.app_role, p_command_key);
    perform app.pay_extend_membership(v_actor.tenant_id, v_request.target_id, p_currency);
  end if;

  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;

  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'record',
    v_facts, v_actor.user_id);

  return app.pay_request_json(v_request, false);
end
$fn$;

-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- Safe reads: keyset pagination, tenant/member scope only, no storage fields
-- ---------------------------------------------------------------------------
create function public.read_member_purchase_requests(
  p_limit integer, p_after_created_at timestamptz, p_after_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $fn$
declare v_actor record; v_limit integer;
begin
  select * into v_actor from app.shop_actor('member');
  v_limit := coalesce(nullif(p_limit, 0), 20);
  if v_limit < 1 then v_limit := 1; end if;
  if v_limit > 100 then v_limit := 100; end if;
  return (
    with page as (
      select r.id as pid, r.created_at as cat,
             row_number() over (order by r.created_at desc, r.id desc) as rn
      from public.purchase_requests r
      where r.tenant_id = v_actor.tenant_id
        and r.member_id = v_actor.member_id
        and (p_after_created_at is null
          or r.created_at < p_after_created_at
          or (r.created_at = p_after_created_at and r.id < p_after_id))
      order by r.created_at desc, r.id desc
      limit v_limit + 1
    )
    select jsonb_build_object(
      'requests', coalesce((select jsonb_agg(
                    app.pay_request_json(r, null::boolean)
                    || jsonb_build_object('member_name', (select m.full_name from public.members m
                                           where m.tenant_id = r.tenant_id and m.id = r.member_id))
                    order by page.rn)
                             from page join public.purchase_requests r
                               on r.id = page.pid and r.tenant_id = v_actor.tenant_id
                             where page.rn <= v_limit), '[]'::jsonb),
      'nextAfter', case when exists (select 1 from page q where q.rn > v_limit)
                        then (select page.cat from page where page.rn = v_limit) end,
      'nextAfterId', case when exists (select 1 from page q where q.rn > v_limit)
                        then (select page.pid from page where page.rn = v_limit) end
    )
  );
end
$fn$;


create function public.read_purchase_requests(
  p_limit integer, p_after_created_at timestamptz, p_after_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $fn$
declare v_actor record; v_limit integer;
begin
  select * into v_actor from app.shop_actor('front_office');
  v_limit := coalesce(nullif(p_limit, 0), 20);
  if v_limit < 1 then v_limit := 1; end if;
  if v_limit > 100 then v_limit := 100; end if;
  return (
    with page as (
      select r.id as pid, r.created_at as cat,
             row_number() over (order by r.created_at desc, r.id desc) as rn
      from public.purchase_requests r
      where r.tenant_id = v_actor.tenant_id
        and (p_after_created_at is null
          or r.created_at < p_after_created_at
          or (r.created_at = p_after_created_at and r.id < p_after_id))
      order by r.created_at desc, r.id desc
      limit v_limit + 1
    )
    select jsonb_build_object(
      'requests', coalesce((select jsonb_agg(
                    app.pay_request_json(r, null::boolean)
                    || jsonb_build_object('memberId', r.member_id,
                        'member_name', (select m.full_name from public.members m
                          where m.tenant_id = r.tenant_id and m.id = r.member_id),
                        'resulting_end_date', (select mm.ends_on from public.memberships mm
                          where mm.tenant_id = r.tenant_id and mm.id = r.recorded_membership_id),
                        'received_paise', r.recorded_amount_paise::text,
                        'difference_paise', (greatest(
                          nullif(r.snapshot->>'totalPaise', '')::numeric
                          - coalesce(r.recorded_amount_paise, 0), 0))::text)
                    order by page.rn)
                             from page join public.purchase_requests r
                               on r.id = page.pid and r.tenant_id = v_actor.tenant_id
                             where page.rn <= v_limit), '[]'::jsonb),
      'nextAfter', case when exists (select 1 from page q where q.rn > v_limit)
                        then (select page.cat from page where page.rn = v_limit) end,
      'nextAfterId', case when exists (select 1 from page q where q.rn > v_limit)
                        then (select page.pid from page where page.rn = v_limit) end
    )
  );
end
$fn$;


create function public.read_purchase_request(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_request public.purchase_requests%rowtype;
begin
  select * into v_actor from app.shop_actor('member_or_front_office');
  if v_actor.member_id is not null then
    select r.* into v_request from public.purchase_requests r
     where r.tenant_id = v_actor.tenant_id and r.id = p_request_id
       and r.member_id = v_actor.member_id;
  else
    select r.* into v_request from public.purchase_requests r
     where r.tenant_id = v_actor.tenant_id and r.id = p_request_id;
  end if;
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  return app.pay_request_json(v_request, null::boolean);
end
$fn$;

-- ---------------------------------------------------------------------------
-- Ownership, volatility and grants for every public surface
-- ---------------------------------------------------------------------------
alter function public.register_payment_proof(uuid,text,integer) owner to postgres;
alter function public.register_payment_proof(uuid,text,integer,uuid) owner to postgres;
alter function public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid) owner to postgres;
alter function public.accept_purchase_request(uuid,uuid,uuid) owner to postgres;
alter function public.reconfirm_purchase_quote(uuid,uuid,uuid) owner to postgres;
alter function public.cancel_purchase_request(uuid,uuid) owner to postgres;
alter function public.attach_payment_proof(uuid,uuid,uuid,uuid) owner to postgres;
alter function public.reject_purchase_request(uuid,uuid,text,uuid) owner to postgres;
alter function public.reject_payment_proof(uuid,uuid,uuid,text,uuid) owner to postgres;
-- Six-arg identity preserved for callers pinning the frozen signature; the
-- slot parameter arrived with the contract's PT amendment and defaults to null.
create function public.record_purchase_request(
  p_request_id uuid, p_expected_revision uuid, p_command_key uuid,
  p_actual_amount text, p_currency text, p_payment_method text
) returns jsonb
language plpgsql volatile security invoker set search_path = ''
as $fn$
begin
  return public.record_purchase_request(p_request_id, p_expected_revision,
    p_command_key, p_actual_amount, p_currency, p_payment_method, null);
end
$fn$;

alter function public.record_purchase_request(uuid,uuid,uuid,text,text,text) owner to postgres;
alter function public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid) owner to postgres;
revoke all on function public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid) from public, anon, service_role;
grant execute on function public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid) to authenticated;
revoke all on function public.record_purchase_request(uuid,uuid,uuid,text,text,text) from public, anon, service_role;
grant execute on function public.record_purchase_request(uuid,uuid,uuid,text,text,text) to authenticated;
alter function public.read_member_purchase_requests(integer,timestamptz,uuid) owner to postgres;
alter function public.read_purchase_requests(integer,timestamptz,uuid) owner to postgres;
alter function public.read_purchase_request(uuid) owner to postgres;

revoke all on function public.register_payment_proof(uuid,text,integer) from public, anon, service_role;
revoke all on function public.register_payment_proof(uuid,text,integer,uuid) from public, anon, service_role;
revoke all on function public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid) from public, anon, service_role;
revoke all on function public.accept_purchase_request(uuid,uuid,uuid) from public, anon, service_role;
revoke all on function public.reconfirm_purchase_quote(uuid,uuid,uuid) from public, anon, service_role;
revoke all on function public.cancel_purchase_request(uuid,uuid) from public, anon, service_role;
revoke all on function public.attach_payment_proof(uuid,uuid,uuid,uuid) from public, anon, service_role;
revoke all on function public.reject_purchase_request(uuid,uuid,text,uuid) from public, anon, service_role;
revoke all on function public.reject_payment_proof(uuid,uuid,uuid,text,uuid) from public, anon, service_role;
revoke all on function public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid) from public, anon, service_role;
revoke all on function public.read_member_purchase_requests(integer,timestamptz,uuid) from public, anon, service_role;
revoke all on function public.read_purchase_requests(integer,timestamptz,uuid) from public, anon, service_role;
revoke all on function public.read_purchase_request(uuid) from public, anon, service_role;

grant execute on function public.register_payment_proof(uuid,text,integer) to authenticated;
grant execute on function public.register_payment_proof(uuid,text,integer,uuid) to authenticated;
grant execute on function public.create_purchase_request(uuid,public.purchase_request_kind,uuid,integer,uuid) to authenticated;
grant execute on function public.accept_purchase_request(uuid,uuid,uuid) to authenticated;
grant execute on function public.reconfirm_purchase_quote(uuid,uuid,uuid) to authenticated;
grant execute on function public.cancel_purchase_request(uuid,uuid) to authenticated;
grant execute on function public.attach_payment_proof(uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.reject_purchase_request(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.reject_payment_proof(uuid,uuid,uuid,text,uuid) to authenticated;
grant execute on function public.record_purchase_request(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid) to authenticated;
grant execute on function public.read_member_purchase_requests(integer,timestamptz,uuid) to authenticated;
grant execute on function public.read_purchase_requests(integer,timestamptz,uuid) to authenticated;
grant execute on function public.read_purchase_request(uuid) to authenticated;

-- Private app surface stays private.
revoke all on function app.pay_held_quantity(uuid,uuid) from public, anon, authenticated, service_role;
-- The amended invoker record_addon_sale and the stock trigger evaluate hold
-- arithmetic in the caller's context: they read through one definer projection
-- so neither private hold reader needs user EXECUTE (SHP-024 discipline kept).
create function app.pay_held_view(p_tenant_id uuid, p_product_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $fn$
  select coalesce(app.pay_held_quantity(p_tenant_id, p_product_id), 0)
$fn$;
alter function app.pay_held_view(uuid,uuid) owner to postgres;
revoke all on function app.pay_held_view(uuid,uuid) from public, anon, service_role;
grant execute on function app.pay_held_view(uuid,uuid) to authenticated;
revoke all on function app.pay_audit(uuid,uuid,text,text,text,uuid,jsonb,jsonb,text,uuid,jsonb) from public, anon, authenticated, service_role;
revoke all on function app.pay_command_record(uuid,uuid,uuid,text,jsonb,uuid) from public, anon, service_role;
grant execute on function app.pay_command_record(uuid,uuid,uuid,text,jsonb,uuid) to authenticated;
revoke all on function app.pay_command_lookup(uuid,uuid,uuid,text) from public, anon, service_role;
grant execute on function app.pay_command_lookup(uuid,uuid,uuid,text) to authenticated;
revoke all on function app.expire_purchase_requests(timestamptz) from public, anon, authenticated, service_role;
revoke all on function app.pay_finalize(uuid,uuid,text,uuid,uuid,uuid,bigint,text,uuid,uuid,text,uuid) from public, anon, service_role;
grant execute on function app.pay_finalize(uuid,uuid,text,uuid,uuid,uuid,bigint,text,uuid,uuid,text,uuid) to authenticated;
-- app.pay_extend_membership privileges are appended with its definition above.
revoke all on function app.pay_mark_hold_consumed(uuid,uuid,uuid,uuid,integer) from public, anon, service_role;
grant execute on function app.pay_mark_hold_consumed(uuid,uuid,uuid,uuid,integer) to authenticated;
revoke all on function app.pay_request_json(public.purchase_requests,boolean) from public, anon, service_role;
grant execute on function app.pay_request_json(public.purchase_requests,boolean) to authenticated;
revoke all on function app.enforce_payment_proof() from public, anon, authenticated, service_role;
revoke all on function app.enforce_purchase_request() from public, anon, authenticated, service_role;
revoke all on function app.enforce_pay_stock_holds() from public, anon, authenticated, service_role;
grant execute on function app.expire_purchase_requests(timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- Coordinator contract addition (2026-10-03; amended 2026-10-04, frozen
-- decisions 1+7): private proof URL authorization. SQL authorizes and bounds;
-- the Edge/web mint composes the final no-store signed GET (MEDIA has no
-- SQL-side signer). The definer door re-proves the real, unimpersonated
-- session class itself — a direct invoker read mints no capability token.
-- ACTIVE-ONLY viewing (frozen decision 1): only the currently active proof of
-- a LIVE request is viewable — the attached active proof, or while none is
-- attached yet the member's latest confirmed unattached registration for that
-- request. Recorded/mismatch/bound history, closed requests and expired
-- requests keep the one external refusal. The helper returns a concrete named
-- row type (never an anonymous record).
-- ---------------------------------------------------------------------------
create function app.pay_proof_evidence(
  p_tenant_id uuid, p_request_id uuid, p_member_id uuid, p_is_member boolean
) returns table (proof_id uuid, asset_id uuid)
language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_request public.purchase_requests%rowtype;
  v_proof public.payment_proofs%rowtype;
  v_asset public.media_assets%rowtype;
begin
  if p_is_member is null or p_tenant_id is null or p_request_id is null then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if p_is_member then
    if auth.uid() is null or app.current_app_role() is distinct from 'member'
      or app.current_staff_id() is not null or app.current_member_id() is null
      or app.current_impersonation_id() is not null
      or p_member_id is distinct from app.current_member_id()
      or not exists (select 1 from public.members m
           where m.tenant_id = p_tenant_id and m.id = app.current_member_id()
             and m.user_id = auth.uid() and m.status = 'active'
             and m.erased_at is null) then
      raise exception 'Request unavailable' using errcode = 'P0002';
    end if;
  else
    if auth.uid() is null or app.current_impersonation_id() is not null
      or app.current_member_id() is not null or app.current_staff_id() is null
      or app.current_app_role() not in ('gym_owner', 'gym_manager', 'front_desk')
      or not exists (select 1 from public.staff s
           where s.tenant_id = p_tenant_id and s.id = app.current_staff_id()
             and s.user_id = auth.uid() and s.role::text = app.current_app_role()
             and s.is_active) then
      raise exception 'Request unavailable' using errcode = 'P0002';
    end if;
  end if;
  select r.* into v_request from public.purchase_requests r
   where r.tenant_id = p_tenant_id and r.id = p_request_id
     and (not p_is_member or r.member_id = p_member_id);
  if not found then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  -- Active-only: a live request in a pre-recording state serves its current
  -- proof; recorded, mismatch_recorded, closed and expired requests refuse.
  if v_request.status in ('owner_accepted', 'payment_proof_uploaded')
    and v_request.expires_at > statement_timestamp() then
    select p.* into v_proof from public.payment_proofs p
     where p.tenant_id = p_tenant_id and p.request_id = p_request_id
       and p.disposition = 'active';
    if found then
      proof_id := v_proof.id;
      asset_id := v_proof.asset_id;
      return;
    end if;
    -- No attached proof yet: the member's latest confirmed, not-deleted,
    -- unattached registration for exactly this request is the current proof —
    -- but only if that asset was never attached (a rejected or superseded
    -- earlier proof is decision history, never the current view).
    select a.* into v_asset from public.media_assets a
     where a.tenant_id = p_tenant_id and a.kind = 'payment_proof'
       and a.linked_request_id = p_request_id
       and a.confirmed_at is not null and a.deleted_at is null
       and a.attached_to_id is null
     order by a.created_at desc, a.id desc
     limit 1;
    if found and not exists (select 1 from public.payment_proofs p
         where p.tenant_id = p_tenant_id and p.asset_id = v_asset.id) then
      proof_id := null;
      asset_id := v_asset.id;
      return;
    end if;
  end if;
  raise exception 'Request unavailable' using errcode = 'P0002';
end
$fn$;

create function public.read_purchase_proof_url(p_request_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_is_member boolean;
  v_member_id uuid;
  v_proof_id uuid;
  v_asset_id uuid;
begin
  if p_request_id is null then
    raise exception 'Request arguments required' using errcode = '22023';
  end if;
  -- One external refusal for every non-provable session shape (trainer,
  -- impersonation, incomplete or contradictory claims): the member-vs-verifier
  -- split resolves here; the definer door re-proves the same facts itself.
  if auth.uid() is not null and app.current_impersonation_id() is null then
    v_tenant := app.current_tenant_id();
    if app.current_app_role() = 'member' and app.current_member_id() is not null
      and app.current_staff_id() is null then
      v_is_member := true;
      v_member_id := app.current_member_id();
    elsif app.is_front_office() is true and app.current_staff_id() is not null
      and app.current_member_id() is null then
      v_is_member := false;
    end if;
  end if;
  if v_tenant is null or v_is_member is null then
    raise exception 'Request unavailable' using errcode = 'P0002';
  end if;
  if v_is_member then
    select proof_id, asset_id into v_proof_id, v_asset_id
      from app.pay_proof_evidence(v_tenant, p_request_id, v_member_id, true);
  else
    select proof_id, asset_id into v_proof_id, v_asset_id
      from app.pay_proof_evidence(v_tenant, p_request_id, null, false);
  end if;
  return jsonb_build_object(
    'requestId', p_request_id,
    'proofId', v_proof_id,
    'assetId', v_asset_id,
    'expiresAt', transaction_timestamp() + interval '60 seconds',
    'url', '/api/purchase-requests/' || p_request_id::text || '/proof-asset'
  );
end
$fn$;

alter function app.pay_proof_evidence(uuid,uuid,uuid,boolean) owner to postgres;
alter function public.read_purchase_proof_url(uuid) owner to postgres;
revoke all on function app.pay_proof_evidence(uuid,uuid,uuid,boolean) from public, anon, service_role;
grant execute on function app.pay_proof_evidence(uuid,uuid,uuid,boolean) to authenticated;
revoke all on function app.pay_grant_capability(text,uuid,uuid,text) from public, anon, service_role;
grant execute on function app.pay_grant_capability(text,uuid,uuid,text) to authenticated;
revoke all on function app.pay_take_capability(text,uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.read_purchase_proof_url(uuid) from public, anon, service_role;
grant execute on function public.read_purchase_proof_url(uuid) to authenticated;
