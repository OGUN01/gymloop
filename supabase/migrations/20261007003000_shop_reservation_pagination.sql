-- SHP-PAGE-001..009: additive read-only member history transport.
-- CI applies this forward-only migration. Legacy reads/commands/policies stay intact.
create index shop_reservations_tenant_member_created_id_idx
  on public.shop_reservations(tenant_id,member_id,created_at desc,id desc);
create index shop_reservations_tenant_member_reserved_expiry_idx
  on public.shop_reservations(tenant_id,member_id,expires_at,created_at desc,id desc)
  where status='reserved';

create function public.read_member_shop_reservation_page(
  p_after_created_at timestamptz default null,p_after_id uuid default null
)
returns table(active_reservations jsonb,history jsonb,next_after_created_at timestamptz,next_after_id uuid,as_of timestamptz)
language plpgsql stable security definer set search_path='' as $fn$
declare
  -- Mirrors SHOP_PAGE_LIMITS, derived from the existing three/five display and five-hold rule.
  c_initial_history constant integer:=3;
  c_history_page constant integer:=5;
  c_active_limit constant integer:=5;
  v_actor record;
  v_now timestamptz:=statement_timestamp();
  v_limit integer;
  v_active jsonb;
  v_history jsonb;
  v_active_count integer;
  v_history_count integer;
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'Authenticated shop member required' using errcode='42501';
  end if;
  select * into v_actor from app.shop_actor('member');
  if not exists(select 1 from public.members m where m.tenant_id=v_actor.tenant_id and m.id=v_actor.member_id
    and m.user_id=v_actor.user_id and m.status not in ('cancelled','blocked') and m.erased_at is null) then
    raise exception 'Current available shop member required' using errcode='42501';
  end if;
  if (p_after_created_at is null) <> (p_after_id is null)
    or (p_after_created_at is not null and not isfinite(p_after_created_at)) then
    raise exception 'Complete finite cursor required' using errcode='22023';
  end if;
  v_limit:=case when p_after_created_at is null then c_initial_history else c_history_page end;

  -- Select only bounded candidate rows before product/media joins and JSON projection.
  with active_candidates as materialized (
    select r.* from public.shop_reservations r
    where p_after_created_at is null and r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id
      and r.status='reserved' and r.expires_at>v_now
    order by r.expires_at asc,r.created_at desc,r.id desc
    limit c_active_limit+1
  ), history_candidates as materialized (
    select r.* from public.shop_reservations r
    where r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id
      and not (r.status='reserved' and r.expires_at>v_now)
      and (p_after_created_at is null or (r.created_at,r.id)<(p_after_created_at,p_after_id))
    order by r.created_at desc,r.id desc
    limit v_limit+1
  ), candidates as (
    select a.*,true as is_active from active_candidates a
    union all select h.*,false as is_active from history_candidates h
  ), projected as (
    select r.id,r.created_at,r.expires_at,r.is_active,
      jsonb_build_object(
        'reservation_id',r.id,'item_id',r.product_id,'item_name',r.product_name,
        'section',case when r.kind='product' then 'products' else 'services' end,
        'quantity',r.quantity,'unit_price_paise',r.unit_price_paise::text,
        'total_paise',(r.unit_price_paise::numeric*r.quantity)::text,'currency',r.currency,
        'state',case when r.status='reserved' and r.expires_at<=v_now then 'expired' else r.status::text end,
        'created_at',r.created_at,'expires_at',r.expires_at,
        'cancel_reason',case when r.status='cancelled_by_gym' then r.cancel_reason else null::text end,
        'terms_changed',r.status='reserved' and r.expires_at>v_now and p.quote_version is distinct from r.quote_version,
        'order_id',case when r.status='fulfilled' then r.order_id else null::uuid end,
        'image_asset_id',m.id
      ) as facts
    from candidates r
    join public.addon_products p on p.tenant_id=r.tenant_id and p.id=r.product_id
    left join public.media_assets m on m.tenant_id=p.tenant_id and m.kind='product' and m.attached_to_id=p.id
      and m.confirmed_at is not null and m.deleted_at is null
  )
  select
    coalesce(jsonb_agg(facts order by expires_at asc,created_at desc,id desc) filter(where is_active),'[]'::jsonb),
    coalesce(jsonb_agg(facts order by created_at desc,id desc) filter(where not is_active),'[]'::jsonb),
    count(*) filter(where is_active),count(*) filter(where not is_active)
  into v_active,v_history,v_active_count,v_history_count from projected;

  if v_active_count>c_active_limit then
    raise exception 'Active reservation population exceeds bound' using errcode='22023';
  end if;
  if v_history_count>v_limit then
    -- Read the exact timestamp text from the last returned row, never a rounded client instant.
    v_cursor_created_at:=(v_history->(v_limit-1)->>'created_at')::timestamptz;
    v_cursor_id:=(v_history->(v_limit-1)->>'reservation_id')::uuid;
    select coalesce(jsonb_agg(e.value order by e.ordinality),'[]'::jsonb) into v_history
      from jsonb_array_elements(v_history) with ordinality e(value,ordinality) where e.ordinality<=v_limit;
  end if;
  return query select v_active,v_history,v_cursor_created_at,v_cursor_id,v_now;
end
$fn$;

alter function public.read_member_shop_reservation_page(timestamptz,uuid) owner to postgres;
revoke all on function public.read_member_shop_reservation_page(timestamptz,uuid) from public,anon,service_role;
grant execute on function public.read_member_shop_reservation_page(timestamptz,uuid) to authenticated;
