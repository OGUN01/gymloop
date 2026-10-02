-- Current linked Phase 6 definitions, read-only capture 2026-10-02.
-- Public input for the PTF surgical amendment; this file is not a migration.

CREATE OR REPLACE FUNCTION app.addon_order_fully_returned(p_tenant_id uuid, p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;


CREATE OR REPLACE FUNCTION app.enforce_addon_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$;


CREATE OR REPLACE FUNCTION app.lock_addon_order_for_pt_session()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
