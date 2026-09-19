-- Repair the member money projection after add-on orders moved to frozen sales.
-- Add-on history must present the sold snapshot, never the mutable catalogue.

create or replace function public.read_member_mobile_money()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_member uuid;
begin
  select i.tenant_id, i.member_id
    into v_tenant, v_member
    from app.member_mobile_identity() i;

  return jsonb_build_object(
    'receipts', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'amountPaise', p.amount_paise::text,
            'currency', p.currency,
            'paidAt', p.paid_at,
            'receiptNumber', p.receipt_number,
            'status', p.status
          )
          order by p.created_at desc
        )
        from public.payments p
        where p.tenant_id = v_tenant
          and p.member_id = v_member
      ),
      '[]'::jsonb
    ),
    'addOns', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', o.id,
            'name', o.sale_snapshot ->> 'name',
            'status', o.status,
            'totalPaise', o.total_paise::text,
            'currency', o.currency,
            'sessionsUsed', o.sessions_used,
            'sessionsTotal', o.sessions_total
          )
          order by o.created_at desc
        )
        from public.addon_orders o
        where o.tenant_id = v_tenant
          and o.member_id = v_member
      ),
      '[]'::jsonb
    )
  );
end;
$function$;
