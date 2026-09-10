-- Phase 6 add-on catalogue, sale, fulfilment, returns and member disclosure.
-- Frozen contract: docs/planning/phase6-addon-contract.md and ADR-116.

alter table public.addon_products
  add column trainer_qualification text,
  add column quote_version uuid;

update public.addon_products set quote_version = gen_random_uuid();

alter table public.addon_products
  alter column quote_version set not null;

alter table public.addon_orders
  add column sold_by_staff_id uuid,
  add column idempotency_key text,
  add column sold_at timestamptz,
  add column sale_snapshot jsonb,
  add column sale_request jsonb,
  add column initial_session_id uuid;

do $migration$
begin
  if exists (
    select 1 from public.addon_orders
     where payment_id is not null
     group by tenant_id, payment_id having count(*) > 1
  ) then
    raise exception 'Phase 6 requires reconciliation of duplicate add-on payment links before migration';
  end if;
end
$migration$;

create unique index addon_orders_tenant_id_idempotency_key_key
  on public.addon_orders (tenant_id, idempotency_key)
  where idempotency_key is not null;
create unique index addon_orders_tenant_id_payment_id_key
  on public.addon_orders (tenant_id, payment_id)
  where payment_id is not null;
create index addon_orders_sold_by_staff_id_idx
  on public.addon_orders (sold_by_staff_id);
create index addon_orders_initial_session_id_idx
  on public.addon_orders (initial_session_id);
create index addon_orders_tenant_id_sold_at_idx
  on public.addon_orders (tenant_id, sold_at);
create index pt_sessions_tenant_id_addon_order_id_status_idx
  on public.pt_sessions (tenant_id, addon_order_id, status);

alter table public.pt_sessions
  add constraint pt_sessions_tenant_id_id_key unique (tenant_id, id);

alter table public.addon_orders
  add constraint addon_orders_tenant_id_sold_by_staff_id_fkey
  foreign key (tenant_id, sold_by_staff_id)
  references public.staff (tenant_id, id),
  add constraint addon_orders_tenant_id_initial_session_id_fkey
  foreign key (tenant_id, initial_session_id)
  references public.pt_sessions (tenant_id, id);

-- Run schema DDL before backfills: these updates can queue deferred trigger
-- events on historical orders, after which PostgreSQL refuses ALTER TABLE.
-- History is attributed only where the linked payment already proves the actor.
update public.addon_orders o
   set sold_by_staff_id = p.recorded_by_staff_id
  from public.payments p
 where p.tenant_id = o.tenant_id
   and p.id = o.payment_id
   and p.recorded_by_staff_id is not null;

-- Do not fabricate acceptance dates. Only an exact arrived add-on payment is
-- evidence for the historical sold instant.
update public.addon_orders o
   set sold_at = p.paid_at
  from public.payments p
 where p.tenant_id = o.tenant_id
   and p.id = o.payment_id
   and p.member_id = o.member_id
   and p.amount_paise = o.total_paise
   and p.currency = o.currency
   and p.membership_id is null
   and p.status in ('paid', 'refunded', 'reversed')
   and p.paid_at is not null
   and o.total_paise > 0
   and o.status <> 'pending';

create function app.stamp_addon_product_quote_version()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' then
    new.quote_version := gen_random_uuid();
  elsif row(
      new.kind, new.name, new.description, new.price_paise, new.currency,
      new.validity_days, new.session_count, new.trainer_staff_id,
      new.trainer_qualification, new.cancellation_terms, new.is_active
    ) is distinct from row(
      old.kind, old.name, old.description, old.price_paise, old.currency,
      old.validity_days, old.session_count, old.trainer_staff_id,
      old.trainer_qualification, old.cancellation_terms, old.is_active
    ) then
    new.quote_version := gen_random_uuid();
  else
    new.quote_version := old.quote_version;
  end if;
  return new;
end
$fn$;

revoke all on function app.stamp_addon_product_quote_version()
  from public, anon, authenticated;

create trigger addon_products_quote_version
  before insert or update on public.addon_products
  for each row execute function app.stamp_addon_product_quote_version();

create function app.enforce_addon_product()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE'
     and new.kind is distinct from old.kind
     and exists (
       select 1 from public.addon_orders o
        where o.tenant_id = old.tenant_id
          and o.addon_product_id = old.id
     ) then
    raise exception 'Add-on catalogue kind cannot change after a sale'
      using errcode = 'GL055', detail = 'catalogue_incomplete';
  end if;

  if not new.is_active then
    return null;
  end if;

  if btrim(new.name) = ''
     or new.description is null or btrim(new.description) = ''
     or new.cancellation_terms is null or btrim(new.cancellation_terms) = ''
     or new.validity_days is null or new.validity_days <= 0 then
    raise exception 'Active add-on offers require complete disclosed terms'
      using errcode = 'GL055', detail = 'catalogue_incomplete';
  end if;

  if new.kind = 'pt_package' then
    if new.trainer_staff_id is null
       or new.trainer_qualification is null
       or btrim(new.trainer_qualification) = ''
       or new.session_count is null
       or new.stock_quantity is not null then
      raise exception 'Active PT offers require a trainer, qualification and session count'
        using errcode = 'GL055', detail = 'catalogue_incomplete';
    end if;
    if not exists (
      select 1 from public.staff s
       where s.tenant_id = new.tenant_id
         and s.id = new.trainer_staff_id
         and s.role = 'trainer'
         and s.is_active
    ) then
      raise exception 'The disclosed PT trainer is unavailable'
        using errcode = 'GL055', detail = 'trainer_unavailable';
    end if;
  elsif new.kind = 'product' then
    if new.stock_quantity is null
       or new.trainer_staff_id is not null
       or new.trainer_qualification is not null
       or new.session_count is not null then
      raise exception 'Active product offers require stock and no PT fields'
        using errcode = 'GL055', detail = 'catalogue_incomplete';
    end if;
  elsif new.kind = 'diet_plan' then
    if new.stock_quantity is not null
       or new.trainer_staff_id is not null
       or new.trainer_qualification is not null
       or new.session_count is not null then
      raise exception 'Active diet offers cannot carry product or PT fields'
        using errcode = 'GL055', detail = 'catalogue_incomplete';
    end if;
  end if;
  return null;
end
$fn$;

revoke all on function app.enforce_addon_product()
  from public, anon, authenticated;

create trigger addon_products_enforce
  after insert or update on public.addon_products
  for each row execute function app.enforce_addon_product();

create function app.lock_addon_product_for_order()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if tg_relid <> 'public.addon_orders'::regclass or tg_op <> 'INSERT' then
    raise exception 'Invalid add-on product lock source';
  end if;
  if auth.uid() is not null then
    if app.current_tenant_id() is null
       or app.current_staff_id() is null
       or app.current_app_role() not in ('gym_owner', 'gym_manager', 'front_desk')
       or app.current_impersonation_id() is not null
       or new.tenant_id is distinct from app.current_tenant_id() then
      return new;
    end if;
  end if;
  perform 1 from public.addon_products p
   where p.tenant_id = new.tenant_id and p.id = new.addon_product_id
   for update;
  return new;
end
$fn$;

revoke all on function app.lock_addon_product_for_order()
  from public, anon, authenticated;

create trigger addon_orders_product_lock
  before insert on public.addon_orders
  for each row execute function app.lock_addon_product_for_order();

create function app.enforce_addon_order()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_product public.addon_products%rowtype;
  v_payment public.payments%rowtype;
  v_session public.pt_sessions%rowtype;
  v_snapshot_keys bigint;
  v_request_keys bigint;
  v_timezone text;
  v_expected_start date;
  v_expected_end date;
  v_row public.addon_orders%rowtype;
  v_deferred boolean := coalesce(tg_argv[0], '') = 'deferred';
begin
  if v_deferred then
    select o.* into v_row from public.addon_orders o
     where o.tenant_id = new.tenant_id and o.id = new.id;
    if found and v_row.idempotency_key is not null
       and v_row.status = 'pending' then
      raise exception 'A keyed add-on sale cannot survive unaccepted'
        using errcode = 'GL055', detail = 'unaccepted_order';
    end if;
    return null;
  end if;

  -- A-005: identity and accepted facts are records, not editable fields.
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.member_id is distinct from old.member_id
       or new.addon_product_id is distinct from old.addon_product_id
       or new.sold_by_staff_id is distinct from old.sold_by_staff_id
       or new.idempotency_key is distinct from old.idempotency_key
       or new.sale_request is distinct from old.sale_request then
      raise exception 'An add-on order is a permanent sale record'
        using errcode = 'GL053', detail = 'order_is_a_record';
    end if;

    if old.status <> 'pending' then
      if new.payment_id is distinct from old.payment_id
         or new.quantity is distinct from old.quantity
         or new.unit_price_paise is distinct from old.unit_price_paise
         or new.total_paise is distinct from old.total_paise
         or new.currency is distinct from old.currency
         or new.trainer_staff_id is distinct from old.trainer_staff_id
         or new.sessions_total is distinct from old.sessions_total
         or new.initial_session_id is distinct from old.initial_session_id
         or new.starts_on is distinct from old.starts_on
         or new.expires_on is distinct from old.expires_on
         or new.sold_at is distinct from old.sold_at
         or new.sale_snapshot is distinct from old.sale_snapshot
         or (pg_catalog.row_security_active(tg_relid)
             and new.sessions_used is distinct from old.sessions_used) then
        raise exception 'Accepted add-on terms and usage are frozen'
          using errcode = 'GL053', detail = 'order_is_a_record';
      end if;
    end if;

    if not (
      old.status = new.status
      or (old.status = 'pending' and new.status in ('paid', 'cancelled'))
      or (old.status = 'paid' and new.status in ('active', 'cancelled', 'refunded'))
      or (old.status = 'active' and new.status in ('completed', 'refunded'))
    ) then
      raise exception 'Invalid add-on order status transition'
        using errcode = 'GL054', detail = 'invalid_order_transition';
    end if;
  end if;

  -- Authenticated callers cannot use the nullable legacy shape to create a
  -- sale outside the command. Claimless migrations and fixtures remain able
  -- to preserve historical rows whose request evidence never existed.
  if tg_op = 'INSERT' and pg_catalog.row_security_active(tg_relid)
     and (new.idempotency_key is null
          or new.sold_by_staff_id is null
          or new.sale_snapshot is null
          or new.sale_request is null) then
    raise exception 'Invalid add-on sale snapshot'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  -- New keyed sale rows carry complete, exact request evidence.
  if new.idempotency_key is not null then
    if new.idempotency_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or new.sold_by_staff_id is null
       or new.sale_snapshot is null
       or jsonb_typeof(new.sale_snapshot) <> 'object'
       or new.sale_request is null
       or jsonb_typeof(new.sale_request) <> 'object' then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end if;

    select count(*) into v_snapshot_keys
      from jsonb_object_keys(new.sale_snapshot);
    select count(*) into v_request_keys
      from jsonb_object_keys(new.sale_request);
    if v_snapshot_keys <> 6
       or not (new.sale_snapshot ?& array[
         'kind', 'name', 'description', 'cancellationTerms',
         'validityDays', 'trainerQualification'
       ])
       or v_request_keys <> 9
       or not (new.sale_request ?& array[
         'memberId', 'productId', 'quantity', 'quoteVersion',
         'trainerStaffId', 'initialStartsAt', 'initialEndsAt',
         'method', 'reason'
       ]) then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end if;

    if new.sale_request->>'memberId' is distinct from new.member_id::text
       or new.sale_request->>'productId' is distinct from new.addon_product_id::text
       or jsonb_typeof(new.sale_request->'quantity') <> 'number'
       or (new.sale_request->>'quantity')::integer is distinct from new.quantity
       or new.total_paise::numeric is distinct from
          new.unit_price_paise::numeric * new.quantity::numeric then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end if;

    if tg_op = 'INSERT' then
      select p.* into v_product from public.addon_products p
       where p.tenant_id = new.tenant_id and p.id = new.addon_product_id;
      if found then
        if new.sale_request->>'quoteVersion' is distinct from v_product.quote_version::text
           or new.sale_snapshot->>'kind' is distinct from v_product.kind::text
           or new.sale_snapshot->>'name' is distinct from v_product.name
           or new.sale_snapshot->>'description' is distinct from v_product.description
           or new.sale_snapshot->>'cancellationTerms' is distinct from v_product.cancellation_terms
           or jsonb_typeof(new.sale_snapshot->'validityDays') <> 'number'
           or (new.sale_snapshot->>'validityDays')::integer is distinct from v_product.validity_days
           or new.unit_price_paise is distinct from v_product.price_paise
           or new.currency is distinct from v_product.currency
           or (
             v_product.trainer_qualification is null
             and new.sale_snapshot->'trainerQualification' <> 'null'::jsonb
           )
           or (
             v_product.trainer_qualification is not null
             and new.sale_snapshot->>'trainerQualification'
                 is distinct from v_product.trainer_qualification
           ) then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' and new.idempotency_key is not null
     and new.status <> 'pending' then
    raise exception 'A new sale must begin pending'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  -- The first acceptance proves all frozen money, validity and PT facts.
  if tg_op = 'UPDATE'
     and old.status = 'pending' and new.status = 'paid' then
    select timezone into v_timezone from public.organizations
     where id = new.tenant_id;
    if v_timezone is null
       or not exists (select 1 from pg_timezone_names where name = v_timezone)
       or new.sold_at is null
       or new.starts_on is null or new.expires_on is null then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end if;
    v_expected_start := (new.sold_at at time zone v_timezone)::date;
    begin
      v_expected_end := v_expected_start
        + ((new.sale_snapshot->>'validityDays')::integer - 1);
    exception when others then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end;
    if new.starts_on is distinct from v_expected_start
       or new.expires_on is distinct from v_expected_end then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end if;

    if new.total_paise > 0 then
      if new.payment_id is null then
        raise exception 'A paid add-on requires its payment'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
      select p.* into v_payment from public.payments p
       where p.tenant_id = new.tenant_id and p.id = new.payment_id;
      if not found
         or v_payment.member_id is distinct from new.member_id
         or v_payment.amount_paise is distinct from new.total_paise
         or v_payment.currency is distinct from new.currency
         or v_payment.status <> 'paid'
         or v_payment.paid_at is null
         or v_payment.membership_id is not null
         or v_payment.mandate_id is not null
         or v_payment.coupon_id is not null
         or v_payment.provider is not null
         or v_payment.provider_order_id is not null
         or v_payment.provider_payment_id is not null
         or v_payment.recorded_by_staff_id is distinct from new.sold_by_staff_id
         or v_payment.idempotency_key is distinct from 'addon-sale:' || new.idempotency_key then
        raise exception 'The linked payment does not exactly buy this add-on'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
    elsif new.payment_id is not null
       or new.sale_request->'method' <> 'null'::jsonb
       or new.sale_request->'reason' = 'null'::jsonb
       or btrim(new.sale_request->>'reason') = '' then
      raise exception 'A complimentary add-on requires a reason and no payment'
        using errcode = 'GL055', detail = 'invalid_payment';
    end if;

    if new.sale_snapshot->>'kind' = 'pt_package' then
      if new.initial_session_id is null
         or new.sessions_total is null
         or new.trainer_staff_id is null then
        raise exception 'A PT sale requires its initial reservation'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
      select s.* into v_session from public.pt_sessions s
       where s.tenant_id = new.tenant_id and s.id = new.initial_session_id;
      if not found
         or v_session.addon_order_id is distinct from new.id
         or v_session.member_id is distinct from new.member_id
         or v_session.trainer_staff_id is distinct from new.trainer_staff_id
         or v_session.status <> 'scheduled'
         or v_session.starts_at::text is distinct from new.sale_request->>'initialStartsAt'
         or v_session.ends_at::text is distinct from new.sale_request->>'initialEndsAt' then
        raise exception 'The initial PT reservation does not match the sale'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
    end if;
  end if;

  -- Seller ownership is deliberately last so policy/shape answers win first.
  if tg_op = 'INSERT' and pg_catalog.row_security_active(tg_relid)
     and (
       app.current_staff_id() is null
       or new.sold_by_staff_id is distinct from app.current_staff_id()
     ) then
    raise exception 'The add-on seller must be the acting staff member'
      using errcode = 'GL056', detail = 'seller_not_yours';
  end if;
  return new;
end
$fn$;

revoke all on function app.enforce_addon_order()
  from public, anon, authenticated;

create trigger addon_orders_enforce
  before insert or update on public.addon_orders
  for each row execute function app.enforce_addon_order();

create constraint trigger addon_orders_unaccepted
  after insert on public.addon_orders
  deferrable initially deferred
  for each row execute function app.enforce_addon_order('deferred');

create function app.apply_addon_order_effects()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if tg_relid <> 'public.addon_orders'::regclass or tg_op <> 'UPDATE' then
    raise exception 'Invalid add-on order effect source';
  end if;
  if old.status = 'pending' and new.status = 'paid'
     and new.sale_snapshot->>'kind' = 'product' then
    update public.addon_products p
       set stock_quantity = p.stock_quantity - new.quantity
     where p.tenant_id = new.tenant_id
       and p.id = new.addon_product_id
       and p.stock_quantity >= new.quantity;
    if not found then
      raise exception 'The selected product no longer has enough stock'
        using errcode = 'GL057', detail = 'insufficient_stock';
    end if;
  end if;
  return null;
end
$fn$;

revoke all on function app.apply_addon_order_effects()
  from public, anon, authenticated;

create trigger addon_orders_fulfilment_effects
  after update on public.addon_orders
  for each row execute function app.apply_addon_order_effects();

create function app.lock_addon_order_for_pt_session()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if tg_relid <> 'public.pt_sessions'::regclass
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Invalid PT order lock source';
  end if;
  if auth.uid() is not null then
    if app.current_tenant_id() is null
       or app.current_staff_id() is null
       or app.is_staff() is not true
       or app.current_impersonation_id() is not null
       or new.tenant_id is distinct from app.current_tenant_id() then
      return new;
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || new.tenant_id::text || ':' || new.addon_order_id::text, 0
  ));
  perform 1 from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.id = new.addon_order_id
   for update;
  return new;
end
$fn$;

revoke all on function app.lock_addon_order_for_pt_session()
  from public, anon, authenticated;

create trigger pt_sessions_order_lock
  before insert or update on public.pt_sessions
  for each row execute function app.lock_addon_order_for_pt_session();

create function app.enforce_pt_session()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_order public.addon_orders%rowtype;
  v_kind text;
  v_reserved integer;
  v_timezone text;
  v_window_start timestamptz;
  v_window_end timestamptz;
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.addon_order_id is distinct from old.addon_order_id
       or new.trainer_staff_id is distinct from old.trainer_staff_id
       or new.member_id is distinct from old.member_id
       or new.starts_at is distinct from old.starts_at
       or new.ends_at is distinct from old.ends_at
       or new.notes is distinct from old.notes then
      raise exception 'A PT session identity and slot are permanent'
        using errcode = 'GL053', detail = 'session_is_a_record';
    end if;
    if not (
      old.status = new.status
      or (old.status = 'scheduled'
          and new.status in ('completed', 'cancelled', 'no_show'))
    ) then
      raise exception 'Invalid PT session transition'
        using errcode = 'GL058', detail = 'invalid_session_transition';
    end if;
  elsif pg_catalog.row_security_active(tg_relid)
        and new.status <> 'scheduled' then
    raise exception 'New PT sessions must begin scheduled'
      using errcode = 'GL058', detail = 'invalid_session_transition';
  end if;

  -- Refuse an assignment mismatch before inspecting the order or its capacity.
  if pg_catalog.row_security_active(tg_relid)
     and app.current_app_role() = 'trainer'
     and (
       app.current_staff_id() is null
       or new.trainer_staff_id is distinct from app.current_staff_id()
       or (tg_op = 'UPDATE'
           and old.trainer_staff_id is distinct from app.current_staff_id())
     ) then
    raise exception 'The PT session belongs to another trainer'
      using errcode = 'GL056', detail = 'trainer_not_yours';
  end if;

  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.id = new.addon_order_id;
  if not found then
    raise exception 'The PT order was not found' using errcode = 'P0002';
  end if;
  v_kind := coalesce(v_order.sale_snapshot->>'kind', (
    select p.kind::text from public.addon_products p
     where p.tenant_id = v_order.tenant_id and p.id = v_order.addon_product_id
  ));
  if v_kind is distinct from 'pt_package'
     or v_order.sessions_total is null then
    raise exception 'The order is unavailable for PT fulfilment'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  if v_order.member_id is distinct from new.member_id
     or v_order.trainer_staff_id is distinct from new.trainer_staff_id then
    raise exception 'The PT session does not match its purchased order'
      using errcode = 'GL058', detail = 'session_identity_mismatch';
  end if;
  if tg_op = 'UPDATE'
     and old.status = 'scheduled' and new.status = 'completed'
     and (v_order.status <> 'active'
          or v_order.starts_on is null or v_order.expires_on is null) then
    raise exception 'The order is unavailable for PT fulfilment'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;

  if tg_op = 'INSERT' then
    if v_order.status = 'pending' then
      if v_order.sale_request is null
         or v_order.sale_request->>'trainerStaffId' is distinct from new.trainer_staff_id::text
         or (v_order.sale_request->>'initialStartsAt')::timestamptz is distinct from new.starts_at
         or (v_order.sale_request->>'initialEndsAt')::timestamptz is distinct from new.ends_at then
        raise exception 'The initial PT reservation does not match its sale'
          using errcode = 'GL058', detail = 'session_identity_mismatch';
      end if;
    elsif v_order.status <> 'active' then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;

    select v_order.sessions_used + count(*)::integer into v_reserved
      from public.pt_sessions s
     where s.tenant_id = new.tenant_id
       and s.addon_order_id = new.addon_order_id
       and s.status = 'scheduled';
    if v_reserved > v_order.sessions_total then
      raise exception 'The purchased PT reservation budget is exhausted'
        using errcode = 'GL058', detail = 'session_budget_exhausted';
    end if;
  end if;

  if v_order.starts_on is not null and v_order.expires_on is not null then
    select o.timezone into v_timezone from public.organizations o
     where o.id = new.tenant_id;
    if v_timezone is null
       or not exists (select 1 from pg_timezone_names where name = v_timezone) then
      raise exception 'The PT order has no valid gym timezone'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
    v_window_start := v_order.starts_on::timestamp at time zone v_timezone;
    v_window_end := (v_order.expires_on + 1)::timestamp at time zone v_timezone;
    if new.starts_at < v_window_start or new.ends_at > v_window_end then
      raise exception 'The PT session is outside the purchased validity window'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'scheduled' and new.status = 'completed'
     and new.ends_at > clock_timestamp() then
    raise exception 'The PT session has not ended'
      using errcode = 'GL058', detail = 'session_not_ended';
  end if;
  if tg_op = 'UPDATE'
     and old.status = 'scheduled' and new.status = 'completed'
     and (clock_timestamp() at time zone v_timezone)::date
         not between v_order.starts_on and v_order.expires_on then
    raise exception 'The PT completion is outside the purchased validity window'
      using errcode = 'GL058', detail = 'session_outside_validity';
  end if;

  return null;
end
$fn$;

revoke all on function app.enforce_pt_session()
  from public, anon, authenticated;

create trigger pt_sessions_enforce
  after insert or update on public.pt_sessions
  for each row execute function app.enforce_pt_session();

create function app.apply_pt_session_effect()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_used integer;
  v_total integer;
begin
  if tg_relid <> 'public.pt_sessions'::regclass or tg_op <> 'UPDATE' then
    raise exception 'Invalid PT session effect source';
  end if;
  if old.status = 'scheduled' and new.status = 'completed' then
    perform pg_advisory_xact_lock(hashtextextended(
      'addon-order:' || new.tenant_id::text || ':' || new.addon_order_id::text, 0
    ));
    update public.addon_orders o
       set sessions_used = o.sessions_used + 1,
           status = case
             when o.sessions_used + 1 = o.sessions_total
               then 'completed'::public.addon_order_status
             else o.status
           end
     where o.tenant_id = new.tenant_id
       and o.id = new.addon_order_id
       and o.status = 'active'
       and o.member_id = new.member_id
       and o.trainer_staff_id = new.trainer_staff_id
       and o.sessions_total is not null
       and o.sessions_used < o.sessions_total
     returning sessions_used, sessions_total into v_used, v_total;
    if not found then
      raise exception 'The purchased PT session cannot be consumed'
        using errcode = 'GL058', detail = 'session_budget_exhausted';
    end if;
  end if;
  return null;
end
$fn$;

revoke all on function app.apply_pt_session_effect()
  from public, anon, authenticated;

create trigger pt_sessions_parent_effect
  after update on public.pt_sessions
  for each row execute function app.apply_pt_session_effect();

create function public.record_addon_sale(
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

create function public.schedule_pt_session(
  p_order_id uuid,
  p_session_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_notes text
)
returns table (session_id uuid, order_id uuid, replayed boolean)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_notes text := nullif(btrim(p_notes), '');
  v_existing public.pt_sessions%rowtype;
  v_order public.addon_orders%rowtype;
  v_reserved integer;
  v_timezone text;
  v_window_start timestamptz;
  v_window_end timestamptz;
begin
  if auth.uid() is null
     or app.current_app_role() is distinct from 'trainer'
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Scheduling PT requires a real trainer session'
      using errcode = '42501';
  end if;
  if p_order_id is null or p_session_id is null
     or p_starts_at is null or p_ends_at is null then
    raise exception 'The PT schedule request is incomplete'
      using errcode = '22023';
  end if;
  if p_ends_at <= p_starts_at then
    raise exception 'The PT slot is invalid'
      using errcode = 'GL058', detail = 'session_outside_validity';
  end if;
  v_tenant := app.current_tenant_id();
  v_staff := app.current_staff_id();

  select s.* into v_existing from public.pt_sessions s
   where s.tenant_id = v_tenant and s.id = p_session_id;
  if found then
    if v_existing.addon_order_id is not distinct from p_order_id
       and v_existing.trainer_staff_id is not distinct from v_staff
       and v_existing.starts_at is not distinct from p_starts_at
       and v_existing.ends_at is not distinct from p_ends_at
       and v_existing.notes is not distinct from v_notes then
      return query select v_existing.id, v_existing.addon_order_id, true;
      return;
    end if;
    raise exception 'This PT session UUID already names a different slot'
      using errcode = 'GL052', detail = 'idempotency_conflict';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_tenant::text || ':' || p_order_id::text, 0
  ));
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.id = p_order_id;
  if not found then
    raise exception 'The PT order was not found' using errcode = 'P0002';
  end if;
  if coalesce(v_order.sale_snapshot->>'kind', (
       select p.kind::text from public.addon_products p
        where p.tenant_id = v_tenant and p.id = v_order.addon_product_id
     )) is distinct from 'pt_package'
     or v_order.status <> 'active'
     or v_order.sessions_total is null
     or v_order.starts_on is null or v_order.expires_on is null
     or exists (
       select 1 from public.refunds r
       join public.payments p on p.tenant_id = r.tenant_id and p.id = r.payment_id
       where p.tenant_id = v_order.tenant_id and p.id = v_order.payment_id
       group by p.amount_paise
       having coalesce(sum(r.amount_paise) filter (where r.status = 'completed'), 0)
              >= p.amount_paise
     ) then
    raise exception 'The order is unavailable for PT fulfilment'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  if v_order.trainer_staff_id is distinct from v_staff then
    raise exception 'The PT order belongs to another trainer'
      using errcode = 'GL056', detail = 'trainer_not_yours';
  end if;
  select v_order.sessions_used + count(*)::integer into v_reserved
    from public.pt_sessions s
   where s.tenant_id = v_tenant and s.addon_order_id = p_order_id
     and s.status = 'scheduled';
  if v_reserved >= v_order.sessions_total then
    raise exception 'The purchased PT reservation budget is exhausted'
      using errcode = 'GL058', detail = 'session_budget_exhausted';
  end if;

  select o.timezone into v_timezone from public.organizations o
   where o.id = v_tenant;
  if v_timezone is null
     or not exists (select 1 from pg_timezone_names where name = v_timezone) then
    raise exception 'The PT order has no valid gym timezone'
      using errcode = 'GL058', detail = 'session_outside_validity';
  end if;
  v_window_start := v_order.starts_on::timestamp at time zone v_timezone;
  v_window_end := (v_order.expires_on + 1)::timestamp at time zone v_timezone;
  if p_starts_at < statement_timestamp()
     or p_starts_at < v_window_start or p_ends_at > v_window_end then
    raise exception 'The PT session is outside the purchased validity window'
      using errcode = 'GL058', detail = 'session_outside_validity';
  end if;

  insert into public.pt_sessions (
    id, tenant_id, addon_order_id, trainer_staff_id, member_id,
    starts_at, ends_at, status, notes
  ) values (
    p_session_id, v_tenant, p_order_id, v_staff, v_order.member_id,
    p_starts_at, p_ends_at, 'scheduled', v_notes
  );
  return query select p_session_id, p_order_id, false;
end
$fn$;

revoke all on function public.schedule_pt_session(
  uuid, uuid, timestamptz, timestamptz, text
) from public, anon;
grant execute on function public.schedule_pt_session(
  uuid, uuid, timestamptz, timestamptz, text
) to authenticated;

create function public.finish_pt_session(
  p_session_id uuid,
  p_status public.pt_session_status
)
returns table (
  session_id uuid,
  order_id uuid,
  session_status public.pt_session_status,
  order_status public.addon_order_status,
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
  v_session public.pt_sessions%rowtype;
  v_order_status public.addon_order_status;
begin
  if auth.uid() is null
     or app.current_app_role() is distinct from 'trainer'
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Finishing PT requires a real trainer session'
      using errcode = '42501';
  end if;
  if p_session_id is null or p_status is null
     or p_status not in ('completed', 'cancelled', 'no_show') then
    raise exception 'The PT terminal command is invalid'
      using errcode = '22023';
  end if;
  v_tenant := app.current_tenant_id();
  v_staff := app.current_staff_id();

  select s.* into v_session from public.pt_sessions s
   where s.tenant_id = v_tenant and s.id = p_session_id;
  if not found then
    raise exception 'The PT session was not found' using errcode = 'P0002';
  end if;
  if v_session.trainer_staff_id is distinct from v_staff then
    raise exception 'The PT session belongs to another trainer'
      using errcode = 'GL056', detail = 'trainer_not_yours';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_tenant::text || ':' || v_session.addon_order_id::text, 0
  ));
  select s.* into v_session from public.pt_sessions s
   where s.tenant_id = v_tenant and s.id = p_session_id
   for update;

  if v_session.status = p_status then
    select o.status into v_order_status from public.addon_orders o
     where o.tenant_id = v_tenant and o.id = v_session.addon_order_id;
    return query select v_session.id, v_session.addon_order_id,
      v_session.status, v_order_status, true;
    return;
  end if;
  if v_session.status <> 'scheduled' then
    raise exception 'The PT session already has a different terminal result'
      using errcode = 'GL058', detail = 'invalid_session_transition';
  end if;
  if p_status = 'completed' and v_session.ends_at > clock_timestamp() then
    raise exception 'The PT session has not ended'
      using errcode = 'GL058', detail = 'session_not_ended';
  end if;
  update public.pt_sessions set status = p_status
   where tenant_id = v_tenant and id = p_session_id;
  select o.status into v_order_status from public.addon_orders o
   where o.tenant_id = v_tenant and o.id = v_session.addon_order_id;
  return query select v_session.id, v_session.addon_order_id,
    p_status, v_order_status, false;
end
$fn$;

revoke all on function public.finish_pt_session(uuid, public.pt_session_status)
  from public, anon;
grant execute on function public.finish_pt_session(uuid, public.pt_session_status)
  to authenticated;

create function public.complete_addon_order(p_order_id uuid)
returns table (
  order_id uuid,
  order_status public.addon_order_status,
  replayed boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_order public.addon_orders%rowtype;
  v_kind text;
begin
  if auth.uid() is null
     or not app.is_front_office()
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Completing an add-on requires a real front-office session'
      using errcode = '42501';
  end if;
  if p_order_id is null then
    raise exception 'The add-on order id is required' using errcode = '22023';
  end if;
  v_tenant := app.current_tenant_id();
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_tenant::text || ':' || p_order_id::text, 0
  ));
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.id = p_order_id
   for update;
  if not found then
    raise exception 'The add-on order was not found' using errcode = 'P0002';
  end if;
  v_kind := coalesce(v_order.sale_snapshot->>'kind', (
    select p.kind::text from public.addon_products p
     where p.tenant_id = v_tenant and p.id = v_order.addon_product_id
  ));
  if v_order.status in ('refunded', 'cancelled', 'pending', 'paid') then
    raise exception 'The add-on order is unavailable for completion'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  if v_kind = 'pt_package' then
    raise exception 'PT orders complete through their sessions'
      using errcode = 'GL055', detail = 'wrong_order_kind';
  end if;
  if v_kind not in ('product', 'diet_plan') then
    raise exception 'The add-on order kind is unsupported'
      using errcode = 'GL055', detail = 'wrong_order_kind';
  end if;
  if v_order.status = 'completed' then
    return query select v_order.id, v_order.status, true;
    return;
  end if;
  if v_order.status <> 'active' then
    raise exception 'The add-on order is unavailable for completion'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  update public.addon_orders set status = 'completed'
   where tenant_id = v_tenant and id = p_order_id;
  return query select p_order_id, 'completed'::public.addon_order_status, false;
end
$fn$;

revoke all on function public.complete_addon_order(uuid) from public, anon;
grant execute on function public.complete_addon_order(uuid) to authenticated;

create or replace function app.stamp_refund()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if pg_catalog.row_security_active('public.refunds') then
    if tg_op = 'INSERT' and new.initiated_by_staff_id is null then
      new.initiated_by_staff_id := app.current_staff_id();
    end if;
    if tg_op = 'UPDATE' then
      if old.status <> 'completed' and new.status = 'completed' then
        new.processed_at := clock_timestamp();
      elsif old.status = 'completed' then
        if new.processed_at is distinct from old.processed_at then
          raise exception 'A completed refund is permanent'
            using errcode = 'GL041';
        end if;
        new.processed_at := old.processed_at;
      elsif new.processed_at is not null then
        new.processed_at := null;
      end if;
    elsif new.status = 'completed' then
      new.processed_at := clock_timestamp();
    else
      new.processed_at := null;
    end if;
  elsif new.status = 'completed' and new.processed_at is null then
    new.processed_at := clock_timestamp();
  end if;
  return new;
end
$fn$;

drop trigger refunds_stamp on public.refunds;
create trigger refunds_stamp
  before insert or update on public.refunds
  for each row execute function app.stamp_refund();

create or replace function app.enforce_refund_total()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid bigint;
  v_refunded bigint;
  v_actor uuid;
begin
  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.idempotency_key is distinct from old.idempotency_key
       or new.currency is distinct from old.currency
       or new.kind is distinct from old.kind
       or new.payment_id is distinct from old.payment_id
       or new.amount_paise is distinct from old.amount_paise) then
    raise exception 'Refund identity and money facts are immutable'
      using errcode = 'GL041';
  end if;
  if tg_op = 'UPDATE' and old.status = 'completed'
     and (new.status is distinct from old.status
       or new.processed_at is distinct from old.processed_at) then
    raise exception 'A completed refund is permanent'
      using errcode = 'GL041';
  end if;

  if pg_catalog.row_security_active('public.refunds') then
    v_actor := app.current_staff_id();
    if tg_op = 'UPDATE' then
      if new.initiated_by_staff_id is distinct from old.initiated_by_staff_id then
        raise exception 'Refund attribution cannot be reassigned'
          using errcode = 'GL040';
      end if;
    elsif v_actor is null
       or new.initiated_by_staff_id is distinct from v_actor then
      raise exception 'A refund must name the acting staff member'
        using errcode = 'GL040';
    end if;
  end if;

  if exists (
       select 1 from public.payments p
        where p.id = new.payment_id and p.tenant_id = new.tenant_id
     ) and not exists (
       select 1 from public.payments p
        where p.id = new.payment_id and p.tenant_id = new.tenant_id
          and p.status in ('paid', 'refunded', 'reversed')
     ) then
    raise exception 'Refund refused because the payment never arrived'
      using errcode = 'GL036';
  end if;

  if new.status <> 'failed' then
    select p.amount_paise into v_paid from public.payments p
     where p.id = new.payment_id and p.tenant_id = new.tenant_id
     for update;
    if v_paid is not null then
      select coalesce(sum(r.amount_paise), 0) into v_refunded
        from public.refunds r
       where r.payment_id = new.payment_id and r.tenant_id = new.tenant_id
         and r.status <> 'failed' and r.id <> new.id;
      if v_refunded + new.amount_paise > v_paid then
        raise exception 'Refund total exceeds the payment'
          using errcode = 'GL036';
      end if;
    end if;
  end if;
  return null;
end
$fn$;

create or replace function public.record_refund(
  p_payment_id uuid,
  p_amount_paise bigint,
  p_currency text,
  p_kind public.refund_kind,
  p_reason text,
  p_idempotency_key uuid
)
returns table (refund_id uuid, replayed boolean)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_id uuid;
  v_order_id uuid;
  v_reason text := nullif(btrim(p_reason), '');
  v_existing public.refunds%rowtype;
begin
  if not app.is_gym_admin() or auth.uid() is null
     or app.current_impersonation_id() is not null then
    raise exception 'A refund requires an owner or manager staff session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  v_staff := app.current_staff_id();
  if v_tenant is null or v_staff is null then
    raise exception 'A refund requires a gym and real staff identity'
      using errcode = '42501';
  end if;
  if p_idempotency_key is null then
    raise exception 'A refund request requires a UUID key'
      using errcode = '22023';
  end if;
  select o.id into v_order_id from public.addon_orders o
   where o.tenant_id = v_tenant and o.payment_id = p_payment_id;
  if v_order_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'addon-order:' || v_tenant::text || ':' || v_order_id::text, 0
    ));
  end if;

  insert into public.refunds (
    tenant_id, payment_id, amount_paise, currency, kind, reason,
    initiated_by_staff_id, status, idempotency_key
  ) values (
    v_tenant, p_payment_id, p_amount_paise, p_currency, p_kind, v_reason,
    v_staff, 'requested', p_idempotency_key::text
  )
  on conflict (tenant_id, idempotency_key) where idempotency_key is not null
    do nothing
  returning id into v_id;

  if v_id is not null then
    return query select v_id, false;
    return;
  end if;
  select r.* into v_existing from public.refunds r
   where r.tenant_id = v_tenant
     and r.idempotency_key = p_idempotency_key::text;
  if not found then
    raise exception 'The existing refund result could not be read'
      using errcode = 'P0002';
  end if;
  if v_existing.payment_id is not distinct from p_payment_id
     and v_existing.amount_paise is not distinct from p_amount_paise
     and v_existing.currency is not distinct from p_currency
     and v_existing.kind is not distinct from p_kind
     and v_existing.reason is not distinct from v_reason then
    return query select v_existing.id, true;
    return;
  end if;
  raise exception 'This request key already names different refund facts'
    using errcode = 'GL048';
end
$fn$;

revoke all on function public.record_refund(
  uuid, bigint, text, public.refund_kind, text, uuid
) from public, anon;
grant execute on function public.record_refund(
  uuid, bigint, text, public.refund_kind, text, uuid
) to authenticated;

create function app.apply_addon_refund_effect()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_order public.addon_orders%rowtype;
  v_payment public.payments%rowtype;
  v_returned bigint;
begin
  if tg_relid <> 'public.refunds'::regclass or tg_op <> 'UPDATE' then
    raise exception 'Invalid add-on refund effect source';
  end if;
  if old.status = 'completed' or new.status <> 'completed' then
    return null;
  end if;
  select p.* into v_payment from public.payments p
   where p.tenant_id = new.tenant_id and p.id = new.payment_id;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.payment_id = new.payment_id;
  if not found then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_order.tenant_id::text || ':' || v_order.id::text, 0
  ));
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.id = v_order.id
   for update;
  select coalesce(sum(r.amount_paise), 0) into v_returned
    from public.refunds r
   where r.tenant_id = new.tenant_id and r.payment_id = new.payment_id
     and r.status = 'completed' and r.currency = v_payment.currency;
  if v_returned = v_payment.amount_paise
     and v_order.status in ('paid', 'active') then
    update public.addon_orders set status = 'refunded'
     where tenant_id = v_order.tenant_id and id = v_order.id;
    update public.pt_sessions set status = 'cancelled'
     where tenant_id = v_order.tenant_id and addon_order_id = v_order.id
       and status = 'scheduled';
  end if;
  return null;
end
$fn$;

revoke all on function app.apply_addon_refund_effect()
  from public, anon, authenticated;

create trigger refunds_fulfilment_effect
  after update on public.refunds
  for each row execute function app.apply_addon_refund_effect();

create function public.complete_manual_addon_refund(
  p_refund_id uuid,
  p_expected_amount_paise bigint,
  p_expected_currency text,
  p_expected_reason text
)
returns table (
  refund_id uuid,
  order_id uuid,
  refund_status public.refund_status,
  order_status public.addon_order_status,
  processed_at timestamptz,
  replayed boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_reason text := nullif(btrim(p_expected_reason), '');
  v_refund public.refunds%rowtype;
  v_payment public.payments%rowtype;
  v_order public.addon_orders%rowtype;
begin
  if auth.uid() is null or not app.is_gym_admin()
     or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'Completing a manual add-on return requires a real gym admin'
      using errcode = '42501';
  end if;
  if p_refund_id is null or p_expected_amount_paise is null
     or p_expected_amount_paise <= 0 or p_expected_currency is null
     or v_reason is null then
    raise exception 'The refund confirmation is incomplete'
      using errcode = '22023';
  end if;
  v_tenant := app.current_tenant_id();
  select r.* into v_refund from public.refunds r
   where r.tenant_id = v_tenant and r.id = p_refund_id;
  if not found then
    raise exception 'The add-on refund was not found' using errcode = 'P0002';
  end if;
  select p.* into v_payment from public.payments p
   where p.tenant_id = v_tenant and p.id = v_refund.payment_id;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.payment_id = v_refund.payment_id;
  if not found or v_payment.id is null then
    raise exception 'The add-on refund was not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_tenant::text || ':' || v_order.id::text, 0
  ));
  select p.* into v_payment from public.payments p
   where p.tenant_id = v_tenant and p.id = v_refund.payment_id
   for update;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.id = v_order.id
   for update;
  select r.* into v_refund from public.refunds r
   where r.tenant_id = v_tenant and r.id = p_refund_id
   for update;

  if v_payment.method = 'razorpay' or v_refund.provider_refund_id is not null then
    raise exception 'Only manual add-on refunds can be confirmed here'
      using errcode = 'GL048';
  end if;
  if v_refund.amount_paise is distinct from p_expected_amount_paise
     or v_refund.currency is distinct from p_expected_currency
     or v_refund.reason is distinct from v_reason then
    raise exception 'The refund confirmation no longer matches its request'
      using errcode = 'GL048';
  end if;
  if v_refund.status = 'completed' then
    return query select v_refund.id, v_order.id, v_refund.status,
      v_order.status, v_refund.processed_at, true;
    return;
  end if;
  if v_refund.status = 'failed' then
    raise exception 'A failed refund requires a new request'
      using errcode = 'GL048';
  end if;
  if v_refund.status = 'requested' then
    update public.refunds set status = 'processing'
     where tenant_id = v_tenant and id = p_refund_id;
  end if;
  update public.refunds set status = 'completed'
   where tenant_id = v_tenant and id = p_refund_id;
  select r.* into v_refund from public.refunds r
   where r.tenant_id = v_tenant and r.id = p_refund_id;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.id = v_order.id;
  return query select v_refund.id, v_order.id, v_refund.status,
    v_order.status, v_refund.processed_at, false;
end
$fn$;

revoke all on function public.complete_manual_addon_refund(
  uuid, bigint, text, text
) from public, anon;
grant execute on function public.complete_manual_addon_refund(
  uuid, bigint, text, text
) to authenticated;

create or replace function app.audit_money_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_columns text[];
  v_record_type text;
  v_before jsonb;
  v_after jsonb;
  v_actor uuid;
  v_role public.app_role;
  v_impersonation uuid;
  v_reason text;
begin
  if tg_table_schema <> 'public'
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Unsupported financial audit source';
  end if;
  if tg_table_name = 'payments' then
    v_record_type := 'payment';
    v_columns := array[
      'member_id', 'membership_id', 'mandate_id', 'coupon_id', 'amount_paise',
      'currency', 'status', 'method', 'provider', 'provider_order_id',
      'provider_payment_id', 'receipt_number', 'recorded_by_staff_id',
      'idempotency_key', 'paid_at', 'failed_reason', 'notes'
    ];
  elsif tg_table_name = 'refunds' then
    v_record_type := 'refund';
    v_columns := array[
      'payment_id', 'kind', 'amount_paise', 'currency', 'status',
      'provider_refund_id', 'reason', 'initiated_by_staff_id', 'processed_at',
      'idempotency_key'
    ];
  elsif tg_table_name = 'addon_orders' then
    v_record_type := 'addon_order';
    select array_agg(a.attname::text order by a.attnum) into v_columns
      from pg_attribute a
     where a.attrelid = 'public.addon_orders'::regclass
       and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('id', 'tenant_id', 'created_at', 'updated_at');
  else
    raise exception 'Unsupported financial audit table';
  end if;

  select jsonb_object_agg(j.key, j.value) into v_after
    from jsonb_each(to_jsonb(new)) j where j.key = any(v_columns);
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(j.key, j.value) into v_before
      from jsonb_each(to_jsonb(old)) j where j.key = any(v_columns);
  end if;
  if v_record_type = 'refund' then
    v_reason := v_after->>'reason';
  elsif v_record_type = 'addon_order' then
    v_reason := v_after->'sale_request'->>'reason';
  end if;

  v_actor := auth.uid();
  if v_actor is not null then
    select e.enumlabel::text::public.app_role into v_role
      from pg_enum e
     where e.enumtypid = 'public.app_role'::regtype
       and e.enumlabel = app.current_app_role();
    v_impersonation := app.current_impersonation_id();
  end if;
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    new.tenant_id, v_actor, v_role, v_impersonation,
    v_record_type || case when tg_op = 'INSERT' then '.created' else '.updated' end,
    v_record_type, new.id, v_before, v_after, v_reason
  );
  return null;
end
$fn$;

revoke all on function app.audit_money_change()
  from public, anon, authenticated;

create trigger addon_orders_money_audit
  after insert or update on public.addon_orders
  for each row execute function app.audit_money_change();

create function public.read_member_addon_returns(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_member uuid;
  v_order public.addon_orders%rowtype;
  v_payment public.payments%rowtype;
  v_returns jsonb;
begin
  begin
    if auth.uid() is null
       or app.current_app_role() is distinct from 'member'
       or app.current_tenant_id() is null
       or app.current_member_id() is null
       or app.current_staff_id() is not null
       or app.current_impersonation_id() is not null then
      raise exception 'Member return disclosure requires a complete member identity'
        using errcode = '42501';
    end if;
    v_tenant := app.current_tenant_id();
    v_member := app.current_member_id();
  exception when invalid_text_representation then
    raise exception 'Member return disclosure requires a complete member identity'
      using errcode = '42501';
  end;
  if p_order_id is null then
    raise exception 'The add-on order id is required' using errcode = '22023';
  end if;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = v_tenant and o.member_id = v_member
     and o.id = p_order_id;
  if not found then
    raise exception 'The add-on order was not found' using errcode = 'P0002';
  end if;
  if v_order.payment_id is not null then
    select p.* into v_payment from public.payments p
     where p.tenant_id = v_tenant and p.member_id = v_member
       and p.id = v_order.payment_id;
    if not found then
      raise exception 'The add-on order was not found' using errcode = 'P0002';
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'refundId', r.id::text,
      'kind', r.kind::text,
      'amountPaise', r.amount_paise::text,
      'currency', r.currency,
      'processedAt', r.processed_at
    ) order by r.processed_at asc nulls last, r.id), '[]'::jsonb)
    into v_returns
    from public.refunds r
   where v_order.payment_id is not null
     and r.tenant_id = v_tenant and r.payment_id = v_order.payment_id
     and r.status = 'completed';
  return jsonb_build_object('orderId', v_order.id::text, 'returns', v_returns);
end
$fn$;

alter function public.read_member_addon_returns(uuid) owner to postgres;
revoke all on function public.read_member_addon_returns(uuid)
  from public, anon, authenticated;
grant execute on function public.read_member_addon_returns(uuid)
  to authenticated;
