-- Close the add-on acceptance, fulfilment and return races found by the
-- fresh-context Phase 6 critic. This migration is forward-only because
-- 20260915100003 is already applied to Cloud.

create function app.addon_order_fully_returned(
  p_tenant_id uuid,
  p_order_id uuid
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_role public.app_role;
begin
  if auth.uid() is not null then
    v_role := app.current_app_role();
    if app.current_tenant_id() is distinct from p_tenant_id
       or app.current_staff_id() is null
       or v_role not in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')
       or app.current_impersonation_id() is not null then
      raise exception 'Returned-money state requires a real staff session'
        using errcode = '42501';
    end if;
    if v_role = 'trainer' and not exists (
      select 1 from public.addon_orders o
       where o.tenant_id = p_tenant_id and o.id = p_order_id
         and o.trainer_staff_id = app.current_staff_id()
    ) then
      raise exception 'The PT order belongs to another trainer'
        using errcode = 'GL056', detail = 'trainer_not_yours';
    end if;
  end if;

  return exists (
    select 1
      from public.addon_orders o
      join public.payments p
        on p.tenant_id = o.tenant_id and p.id = o.payment_id
     where o.tenant_id = p_tenant_id and o.id = p_order_id
       and p.amount_paise > 0
       and (
         select coalesce(sum(r.amount_paise), 0)
           from public.refunds r
          where r.tenant_id = p.tenant_id and r.payment_id = p.id
            and r.status = 'completed' and r.currency = p.currency
       ) = p.amount_paise
  );
end
$fn$;

revoke all on function app.addon_order_fully_returned(uuid, uuid)
  from public, anon;
grant execute on function app.addon_order_fully_returned(uuid, uuid)
  to authenticated;

create or replace function public.complete_addon_order(p_order_id uuid)
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
  v_timezone text;
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
   where o.tenant_id = v_tenant and o.id = p_order_id;
  if not found then
    raise exception 'The add-on order was not found' using errcode = 'P0002';
  end if;
  v_kind := coalesce(v_order.sale_snapshot->>'kind', (
    select p.kind::text from public.addon_products p
     where p.tenant_id = v_tenant and p.id = v_order.addon_product_id
  ));
  if v_order.status = 'completed' then
    if v_kind not in ('product', 'diet_plan') then
      raise exception 'The add-on order kind is unsupported for completion'
        using errcode = 'GL055', detail = 'wrong_order_kind';
    end if;
    return query select v_order.id, v_order.status, true;
    return;
  end if;
  if app.addon_order_fully_returned(v_tenant, p_order_id) then
    raise exception 'The add-on order is unavailable for completion'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  if v_order.status <> 'active'
     or v_order.starts_on is null or v_order.expires_on is null then
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
  if v_kind = 'product' then
    raise exception 'Products complete only during their sale'
      using errcode = 'GL055', detail = 'wrong_order_kind';
  end if;
  select o.timezone into v_timezone from public.organizations o
   where o.id = v_tenant;
  if v_timezone is null
     or not exists (select 1 from pg_timezone_names where name = v_timezone)
     or (clock_timestamp() at time zone v_timezone)::date
          not between v_order.starts_on and v_order.expires_on then
    raise exception 'The diet order is outside its delivery window'
      using errcode = 'GL055', detail = 'order_unavailable';
  end if;
  update public.addon_orders set status = 'completed'
   where tenant_id = v_tenant and id = p_order_id;
  return query select p_order_id, 'completed'::public.addon_order_status, false;
end
$fn$;

create or replace function app.apply_addon_order_effects()
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
  if (old.status = 'pending' and new.status = 'paid'
      and new.sale_snapshot->>'kind' = 'product')
     or (old.status = 'paid' and new.status = 'cancelled') then
    begin
      if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
        select 1 from public.staff s
         where s.tenant_id = new.tenant_id
           and s.id = app.current_staff_id()
           and s.user_id = auth.uid()
           and s.role::text = app.current_app_role()
           and s.role in ('gym_owner', 'gym_manager', 'front_desk')
           and s.is_active
           and app.current_tenant_id() = new.tenant_id
           and app.current_impersonation_id() is null
      ) then
        raise exception 'Add-on order effects require real front-office staff'
          using errcode = '42501';
      end if;
    exception when invalid_text_representation then
      raise exception 'Add-on order effects require real front-office staff'
        using errcode = '42501';
    end;
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
  elsif old.status = 'paid' and new.status = 'cancelled' then
    update public.pt_sessions set status = 'cancelled'
     where tenant_id = new.tenant_id and addon_order_id = new.id
       and status = 'scheduled';
  end if;
  return null;
end
$fn$;

create or replace function app.apply_addon_refund_effect()
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
  if tg_relid <> 'public.refunds'::regclass
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Invalid add-on refund effect source';
  end if;
  if new.status <> 'completed'
     or (tg_op = 'UPDATE' and old.status = 'completed') then
    return null;
  end if;
  select p.* into v_payment from public.payments p
   where p.tenant_id = new.tenant_id and p.id = new.payment_id;
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.payment_id = new.payment_id;
  if not found then
    return null;
  end if;
  begin
    if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
      select 1 from public.staff s
       where s.tenant_id = new.tenant_id
         and s.id = app.current_staff_id()
         and s.user_id = auth.uid()
         and s.role::text = app.current_app_role()
         and s.role in ('gym_owner', 'gym_manager')
         and s.is_active
         and app.current_tenant_id() = new.tenant_id
         and app.current_impersonation_id() is null
    ) then
      raise exception 'Add-on refund effects require a real gym admin'
        using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    raise exception 'Add-on refund effects require a real gym admin'
      using errcode = '42501';
  end;
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

drop trigger refunds_fulfilment_effect on public.refunds;
create trigger refunds_fulfilment_effect
  after insert or update on public.refunds
  for each row execute function app.apply_addon_refund_effect();

create function public.read_member_addon_trainer_names()
returns table (product_id uuid, trainer_name text)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
begin
  begin
    if auth.uid() is null
       or app.current_app_role() is distinct from 'member'
       or app.current_tenant_id() is null
       or app.current_member_id() is null
       or app.current_staff_id() is not null
       or app.current_impersonation_id() is not null then
      raise exception 'Trainer names require a complete member session'
        using errcode = '42501';
    end if;
    v_tenant := app.current_tenant_id();
  exception when invalid_text_representation then
    raise exception 'Trainer names require a complete member session'
      using errcode = '42501';
  end;
  return query
    select p.id, s.full_name
      from public.addon_products p
      join public.staff s
        on s.tenant_id = p.tenant_id and s.id = p.trainer_staff_id
     where p.tenant_id = v_tenant
       and p.kind = 'pt_package' and p.is_active and s.is_active
     order by p.id;
end
$fn$;

revoke all on function public.read_member_addon_trainer_names()
  from public, anon;
grant execute on function public.read_member_addon_trainer_names()
  to authenticated;

create or replace function app.lock_addon_order_for_pt_session()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_order public.addon_orders%rowtype;
begin
  if tg_relid <> 'public.pt_sessions'::regclass
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Invalid PT order lock source';
  end if;
  begin
    if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
      select 1 from public.staff s
       where s.tenant_id = new.tenant_id
         and s.id = app.current_staff_id()
         and s.user_id = auth.uid()
         and s.role::text = app.current_app_role()
         and s.role in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')
         and s.is_active
         and app.current_tenant_id() = new.tenant_id
         and app.current_impersonation_id() is null
    ) then
      raise exception 'PT order locking requires a real staff session'
        using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    raise exception 'PT order locking requires a real staff session'
      using errcode = '42501';
  end;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || new.tenant_id::text || ':' || new.addon_order_id::text, 0
  ));
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.id = new.addon_order_id
   for update;
  if found then
    if tg_op = 'INSERT'
       and app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    elsif tg_op = 'UPDATE'
       and old.status = 'scheduled' and new.status = 'completed'
       and app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;
  end if;
  return new;
end
$fn$;

create or replace function app.enforce_pt_session()
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

  if tg_op = 'INSERT' or (
    tg_op = 'UPDATE' and old.status = 'scheduled' and new.status = 'completed'
  ) then
    select o.timezone into v_timezone from public.organizations o
     where o.id = new.tenant_id;
    if v_timezone is null
       or not exists (select 1 from pg_timezone_names where name = v_timezone) then
      raise exception 'The PT order has no valid gym timezone'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
    if tg_op = 'INSERT' and v_order.status = 'pending'
       and v_order.idempotency_key is not null
       and v_order.starts_on is null and v_order.expires_on is null then
      begin
        v_window_start := ((transaction_timestamp() at time zone v_timezone)::date)::timestamp
          at time zone v_timezone;
        v_window_end := (
          (transaction_timestamp() at time zone v_timezone)::date
          + (v_order.sale_snapshot->>'validityDays')::integer
        )::timestamp at time zone v_timezone;
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'The PT order has no valid sale window'
          using errcode = 'GL058', detail = 'session_outside_validity';
      end;
    elsif v_order.starts_on is null or v_order.expires_on is null then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    else
      v_window_start := v_order.starts_on::timestamp at time zone v_timezone;
      v_window_end := (v_order.expires_on + 1)::timestamp at time zone v_timezone;
    end if;
    if new.ends_at <= new.starts_at
       or new.starts_at < v_window_start or new.ends_at > v_window_end then
      raise exception 'The PT session is outside the purchased validity window'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.starts_at < statement_timestamp() then
      raise exception 'A PT session cannot start before this command'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
    if v_order.status = 'pending' then
      if v_order.sale_request is null
         or v_order.sale_request->>'trainerStaffId' is distinct from new.trainer_staff_id::text
         or (v_order.sale_request->>'initialStartsAt')::timestamptz is distinct from new.starts_at
         or (v_order.sale_request->>'initialEndsAt')::timestamptz is distinct from new.ends_at then
        raise exception 'The initial PT reservation does not match its sale'
          using errcode = 'GL058', detail = 'session_identity_mismatch';
      end if;
    elsif v_order.status <> 'active'
       or (clock_timestamp() at time zone v_timezone)::date
            not between v_order.starts_on and v_order.expires_on
       or app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
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

  if tg_op = 'UPDATE'
     and old.status = 'scheduled' and new.status = 'completed' then
    if v_order.status <> 'active'
       or app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;
    if new.ends_at > clock_timestamp() then
      raise exception 'The PT session has not ended'
        using errcode = 'GL058', detail = 'session_not_ended';
    end if;
    if (clock_timestamp() at time zone v_timezone)::date
         not between v_order.starts_on and v_order.expires_on then
      raise exception 'The PT completion is outside the purchased validity window'
        using errcode = 'GL058', detail = 'session_outside_validity';
    end if;
  end if;

  return null;
end
$fn$;

create or replace function app.apply_pt_session_effect()
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
    begin
      if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
        select 1 from public.staff s
         where s.tenant_id = new.tenant_id
           and s.id = new.trainer_staff_id
           and s.id = app.current_staff_id()
           and s.user_id = auth.uid()
           and s.role = 'trainer'
           and s.role::text = app.current_app_role()
           and s.is_active
           and app.current_tenant_id() = new.tenant_id
           and app.current_impersonation_id() is null
      ) then
        raise exception 'PT consumption requires the assigned real trainer'
          using errcode = '42501';
      end if;
    exception when invalid_text_representation then
      raise exception 'PT consumption requires the assigned real trainer'
        using errcode = '42501';
    end;
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

create or replace function public.schedule_pt_session(
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

  -- The request UUID serializes independently of the order. Two identical
  -- calls now wait, reread and return the committed row as an exact replay.
  perform pg_advisory_xact_lock(hashtextextended(
    'pt-session:' || v_tenant::text || ':' || p_session_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || v_tenant::text || ':' || p_order_id::text, 0
  ));

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
     or app.addon_order_fully_returned(v_tenant, p_order_id) then
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

create or replace function app.enforce_addon_order()
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
  v_kind text;
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

  if pg_catalog.row_security_active(tg_relid)
     and (
       auth.uid() is null
       or not app.is_front_office()
       or app.current_tenant_id() is null
       or app.current_staff_id() is null
       or app.current_impersonation_id() is not null
       or new.tenant_id is distinct from app.current_tenant_id()
     ) then
    raise exception 'Writing an add-on order requires a real front-office session'
      using errcode = '42501';
  end if;

  if new.idempotency_key is not null
     and (
       (tg_op = 'INSERT' and new.sessions_used is distinct from 0)
       or (tg_op = 'UPDATE' and old.status = 'pending'
           and (
             new.sessions_used is distinct from old.sessions_used
             or (new.status = 'paid'
                 and (old.sessions_used is distinct from 0
                      or new.sessions_used is distinct from 0))
           ))
     ) then
    raise exception 'Only completed PT sessions may record add-on usage'
      using errcode = 'GL053', detail = 'order_is_a_record';
  end if;

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
    if old.status <> 'pending' or old.payment_id is not null then
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
    elsif new.status = 'paid' and (
      new.quantity is distinct from old.quantity
      or new.unit_price_paise is distinct from old.unit_price_paise
      or new.total_paise is distinct from old.total_paise
      or new.currency is distinct from old.currency
      or new.trainer_staff_id is distinct from old.trainer_staff_id
      or new.sessions_total is distinct from old.sessions_total
      or new.initial_session_id is distinct from old.initial_session_id
      or new.sale_snapshot is distinct from old.sale_snapshot
      or new.sessions_used is distinct from old.sessions_used
    ) then
      raise exception 'Acceptance cannot rewrite the offered terms'
        using errcode = 'GL053', detail = 'order_is_a_record';
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
    if old.status = 'pending' and new.status = 'paid'
       and old.idempotency_key is null then
      raise exception 'A legacy pending order cannot be accepted as a new sale'
        using errcode = 'GL055', detail = 'unaccepted_order';
    end if;
  end if;

  if tg_op = 'INSERT' and pg_catalog.row_security_active(tg_relid)
     and (new.idempotency_key is null
          or new.sold_by_staff_id is null
          or new.sale_snapshot is null
          or new.sale_request is null) then
    raise exception 'Invalid add-on sale snapshot'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

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

    begin
      if new.sale_request->>'memberId' is distinct from new.member_id::text
         or new.sale_request->>'productId' is distinct from new.addon_product_id::text
         or jsonb_typeof(new.sale_request->'quantity') <> 'number'
         or (new.sale_request->>'quantity')::integer is distinct from new.quantity
         or new.total_paise::numeric is distinct from
            new.unit_price_paise::numeric * new.quantity::numeric then
        raise exception 'Invalid add-on sale snapshot'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end;

    if tg_op = 'INSERT' or (tg_op = 'UPDATE' and old.status = 'pending') then
      select p.* into v_product from public.addon_products p
       where p.tenant_id = new.tenant_id and p.id = new.addon_product_id;
      if not found
         or not v_product.is_active
         or v_product.description is null or btrim(v_product.description) = ''
         or v_product.cancellation_terms is null or btrim(v_product.cancellation_terms) = ''
         or v_product.validity_days is null or v_product.validity_days <= 0
         or v_product.currency <> 'INR'
         or new.sale_request->>'quoteVersion' is distinct from v_product.quote_version::text
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
        raise exception 'The add-on offer no longer matches the accepted facts'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;

      if exists (
        select 1 from public.members m
         where m.tenant_id = new.tenant_id and m.id = new.member_id
           and (m.status in ('cancelled', 'blocked') or m.erased_at is not null)
      ) then
        raise exception 'The member is unavailable for an add-on sale'
          using errcode = 'GL055', detail = 'member_unavailable';
      end if;

      if v_product.kind in ('pt_package', 'diet_plan')
         and new.quantity <> 1 then
        raise exception 'The add-on quantity is invalid'
          using errcode = 'GL055', detail = 'invalid_quantity';
      end if;

      if v_product.kind = 'pt_package' then
        if v_product.trainer_staff_id is null
           or v_product.trainer_qualification is null
           or btrim(v_product.trainer_qualification) = ''
           or v_product.session_count is null
           or v_product.stock_quantity is not null
           or new.trainer_staff_id is null
           or new.sessions_total is distinct from v_product.session_count
           or (
             exists (
               select 1 from public.staff s
                where s.tenant_id = new.tenant_id
                  and s.id = new.trainer_staff_id
             ) and (
               new.trainer_staff_id is distinct from v_product.trainer_staff_id
               or new.sale_request->>'trainerStaffId'
                    is distinct from v_product.trainer_staff_id::text
             )
           )
           or new.sale_request->'initialStartsAt' = 'null'::jsonb
           or new.sale_request->'initialEndsAt' = 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
        if exists (
          select 1 from public.staff s
           where s.tenant_id = new.tenant_id and s.id = new.trainer_staff_id
             and (s.role <> 'trainer' or not s.is_active)
        ) then
          raise exception 'The selected trainer is unavailable'
            using errcode = 'GL055', detail = 'trainer_unavailable';
        end if;
      elsif v_product.kind = 'product' then
        if v_product.stock_quantity is null
           or v_product.trainer_staff_id is not null
           or v_product.trainer_qualification is not null
           or v_product.session_count is not null
           or new.trainer_staff_id is not null
           or new.sessions_total is not null
           or new.initial_session_id is not null
           or new.sale_request->'trainerStaffId' <> 'null'::jsonb
           or new.sale_request->'initialStartsAt' <> 'null'::jsonb
           or new.sale_request->'initialEndsAt' <> 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
      else
        if v_product.stock_quantity is not null
           or v_product.trainer_staff_id is not null
           or v_product.trainer_qualification is not null
           or v_product.session_count is not null
           or new.trainer_staff_id is not null
           or new.sessions_total is not null
           or new.initial_session_id is not null
           or new.sale_request->'trainerStaffId' <> 'null'::jsonb
           or new.sale_request->'initialStartsAt' <> 'null'::jsonb
           or new.sale_request->'initialEndsAt' <> 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
      end if;

      if new.total_paise > 0 then
        if jsonb_typeof(new.sale_request->'method') <> 'string'
           or new.sale_request->>'method' not in ('cash', 'upi', 'card', 'bank_transfer') then
          raise exception 'A paid add-on requires an offline payment method'
            using errcode = 'GL055', detail = 'invalid_payment';
        end if;
      elsif new.sale_request->'method' <> 'null'::jsonb
         or jsonb_typeof(new.sale_request->'reason') <> 'string'
         or btrim(new.sale_request->>'reason') = '' then
        raise exception 'A complimentary add-on requires a reason and no payment'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' and new.idempotency_key is not null
     and new.status <> 'pending' then
    raise exception 'A new sale must begin pending'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  -- Payment linkage is a permanent order invariant, including cancellation.
  -- A pending positive sale may still be unpaid, but any attached payment must
  -- already be arrived and match this exact tenant, member, total and currency.
  if new.total_paise = 0 and new.payment_id is not null then
    raise exception 'A complimentary add-on cannot carry a payment'
      using errcode = 'GL055', detail = 'invalid_payment';
  elsif new.payment_id is not null then
    select p.* into v_payment from public.payments p
     where p.tenant_id = new.tenant_id and p.id = new.payment_id;
    if not found
       or v_payment.member_id is distinct from new.member_id
       or v_payment.amount_paise is distinct from new.total_paise
       or v_payment.currency is distinct from new.currency
       or v_payment.status not in ('paid', 'refunded', 'reversed')
       or v_payment.paid_at is null
       or v_payment.membership_id is not null then
      raise exception 'The linked payment does not exactly buy this add-on'
        using errcode = 'GL055', detail = 'invalid_payment';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'pending' and new.status = 'paid' then
    select timezone into v_timezone from public.organizations
     where id = new.tenant_id;
    if v_timezone is null
       or not exists (select 1 from pg_timezone_names where name = v_timezone)
       or new.sold_at is distinct from transaction_timestamp()
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
         or v_payment.idempotency_key is distinct from 'addon-sale:' || new.idempotency_key
         or v_payment.method::text is distinct from new.sale_request->>'method'
         or v_payment.notes is distinct from new.sale_request->>'reason'
         or exists (
           select 1 from public.refunds r
            where r.tenant_id = v_payment.tenant_id and r.payment_id = v_payment.id
              and r.status = 'completed'
         ) then
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

  if tg_op = 'UPDATE' and old.status is distinct from new.status then
    v_kind := coalesce(new.sale_snapshot->>'kind', (
      select p.kind::text from public.addon_products p
       where p.tenant_id = new.tenant_id and p.id = new.addon_product_id
    ));
    if new.status = 'completed' then
      if app.addon_order_fully_returned(new.tenant_id, new.id) then
        raise exception 'A fully returned add-on cannot be delivered'
          using errcode = 'GL055', detail = 'order_unavailable';
      end if;
      if v_kind = 'pt_package' then
        if new.sessions_total is null
           or new.sessions_used is distinct from new.sessions_total then
          raise exception 'PT completes only through consumed sessions'
            using errcode = 'GL055', detail = 'order_unavailable';
        end if;
      elsif v_kind = 'diet_plan' then
        select timezone into v_timezone from public.organizations
         where id = new.tenant_id;
        if v_timezone is null
           or not exists (select 1 from pg_timezone_names where name = v_timezone)
           or new.starts_on is null or new.expires_on is null
           or (clock_timestamp() at time zone v_timezone)::date
                not between new.starts_on and new.expires_on then
          raise exception 'The diet order is outside its delivery window'
            using errcode = 'GL055', detail = 'order_unavailable';
        end if;
      elsif v_kind = 'product' then
        if new.sold_at is null
           or new.sold_at is distinct from transaction_timestamp() then
          raise exception 'A product completes only inside its sale'
            using errcode = 'GL055', detail = 'wrong_order_kind';
        end if;
      else
        raise exception 'The add-on order kind is unsupported'
          using errcode = 'GL055', detail = 'wrong_order_kind';
      end if;
    elsif new.status = 'refunded'
       and not app.addon_order_fully_returned(new.tenant_id, new.id) then
      raise exception 'An add-on becomes refunded only after the full return completed'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;
  end if;

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

create or replace function app.lock_addon_product_for_order()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if tg_relid <> 'public.addon_orders'::regclass
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Invalid add-on product lock source';
  end if;
  if tg_op = 'UPDATE' and old.status <> 'pending' then
    return new;
  end if;
  begin
    if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
      select 1 from public.staff s
       where s.tenant_id = new.tenant_id
         and s.id = app.current_staff_id()
         and s.user_id = auth.uid()
         and s.role::text = app.current_app_role()
         and s.role in ('gym_owner', 'gym_manager', 'front_desk')
         and s.is_active
         and app.current_tenant_id() = new.tenant_id
         and app.current_impersonation_id() is null
    ) then
      raise exception 'Add-on acceptance locking requires real front-office staff'
        using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    raise exception 'Add-on acceptance locking requires real front-office staff'
      using errcode = '42501';
  end;
  -- Keep the order fixed across the catalogue and eligibility proof. The lock
  -- order is shared by every direct acceptance: product, member, then trainer.
  perform 1 from public.addon_products p
   where p.tenant_id = new.tenant_id and p.id = new.addon_product_id
   for update;
  perform 1 from public.members m
   where m.tenant_id = new.tenant_id and m.id = new.member_id
   for update;
  if new.trainer_staff_id is not null then
    perform 1 from public.staff s
     where s.tenant_id = new.tenant_id and s.id = new.trainer_staff_id
     for update;
  end if;
  return new;
end
$fn$;

-- PostgreSQL orders same-event triggers by name. The original lock sorted
-- after addon_orders_enforce, so a catalogue edit could commit while the sale
-- waited and the stale disclosure would never be checked again.
drop trigger addon_orders_product_lock on public.addon_orders;
create trigger addon_orders_00_product_lock
  before insert or update on public.addon_orders
  for each row execute function app.lock_addon_product_for_order();

create or replace function app.enforce_refund_total()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid bigint;
  v_paid_currency text;
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
    select p.amount_paise, p.currency
      into v_paid, v_paid_currency
      from public.payments p
     where p.id = new.payment_id and p.tenant_id = new.tenant_id
     for update;
    if v_paid is not null then
      if exists (
        select 1 from public.addon_orders o
         where o.tenant_id = new.tenant_id and o.payment_id = new.payment_id
      ) and new.currency is distinct from v_paid_currency then
        raise exception 'An add-on return must use the payment currency'
          using errcode = 'GL036';
      end if;
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

-- Preserve the refund API's established nonblank-reason refusal while still
-- normalizing accepted reasons for exact retry comparison.
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
  if v_reason is null then
    raise exception 'A refund reason must not be blank'
      using errcode = '23514';
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
