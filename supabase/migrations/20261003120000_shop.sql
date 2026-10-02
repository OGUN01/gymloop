-- SHP / MEDIA: frozen shop proposal and owner-approved media-verification amendment.
-- CI applies this forward-only migration. Money commands and existing policies are unchanged.
create type public.shop_reservation_status as enum
  ('reserved', 'fulfilled', 'cancelled_by_member', 'cancelled_by_gym');

create table public.media_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  kind text not null,
  staging_object_key text not null,
  object_key text,
  verified_source_etag text,
  published_etag text,
  mime text not null,
  bytes integer not null,
  created_by_staff_id uuid not null,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  deleted_at timestamptz,
  attached_to_id uuid,
  constraint media_assets_tenant_id_id_key unique (tenant_id,id),
  constraint media_assets_tenant_id_created_by_staff_id_fkey foreign key (tenant_id,created_by_staff_id)
    references public.staff(tenant_id,id),
  constraint media_assets_tenant_id_staging_object_key_key unique (tenant_id,staging_object_key),
  constraint media_assets_tenant_id_object_key_key unique (tenant_id,object_key),
  constraint media_assets_kind_chk check (kind in ('product','trainer','announcement')),
  constraint media_assets_mime_chk check (mime in ('image/jpeg','image/png','image/webp')),
  constraint media_assets_bytes_chk check (bytes > 0 and bytes <= 2097152),
  constraint media_assets_staging_object_key_format_chk check (staging_object_key ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/staging/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'),
  constraint media_assets_object_key_format_chk check (object_key is null or object_key ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'),
  constraint media_assets_staging_object_key_scope_chk check (
    split_part(staging_object_key,'/',1) = tenant_id::text
    and split_part(staging_object_key,'/',3) = kind
    and split_part(staging_object_key,'.',2) = case mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end),
  constraint media_assets_object_key_scope_chk check (object_key is null or (
    split_part(object_key,'/',1) = tenant_id::text and split_part(object_key,'/',3) = kind
    and split_part(object_key,'.',2) = case mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end)),
  constraint media_assets_verification_shape_chk check (
    (confirmed_at is null and object_key is null and verified_source_etag is null and published_etag is null)
    or (confirmed_at is not null and object_key is not null and verified_source_etag is not null
      and published_etag is not null and btrim(verified_source_etag) <> '' and btrim(published_etag) <> '')),
  constraint media_assets_attached_is_confirmed_chk check (attached_to_id is null or confirmed_at is not null),
  constraint media_assets_deleted_is_detached_chk check (deleted_at is null or attached_to_id is null)
);
create unique index media_assets_tenant_id_kind_attached_to_id_live_key
  on public.media_assets(tenant_id,kind,attached_to_id) where attached_to_id is not null and deleted_at is null;
create index media_assets_tenant_id_kind_created_at_idx on public.media_assets(tenant_id,kind,created_at desc);
create index media_assets_tenant_id_created_at_idx on public.media_assets(tenant_id,created_at);
create index media_assets_tenant_id_created_by_staff_id_created_at_idx on public.media_assets(tenant_id,created_by_staff_id,created_at);

create table public.shop_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  name text not null,
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shop_categories_tenant_id_id_key unique (tenant_id,id),
  constraint shop_categories_name_chk check (btrim(name)=name and char_length(name) between 1 and 60),
  constraint shop_categories_sort_order_chk check (sort_order>=0)
);
create unique index shop_categories_tenant_id_name_key on public.shop_categories(tenant_id,lower(name));
create index shop_categories_tenant_id_is_active_sort_order_idx on public.shop_categories(tenant_id,is_active,sort_order);
alter table public.addon_products add column category_id uuid;
alter table public.addon_products add constraint addon_products_tenant_id_category_id_fkey
  foreign key (tenant_id,category_id) references public.shop_categories(tenant_id,id);
create index addon_products_tenant_id_category_id_idx on public.addon_products(tenant_id,category_id);

create table public.shop_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  member_id uuid not null,
  product_id uuid not null,
  product_name text not null,
  kind public.addon_kind not null,
  quantity integer not null,
  quote_version uuid not null,
  unit_price_paise bigint not null,
  currency text not null default 'INR',
  status public.shop_reservation_status not null default 'reserved',
  expires_at timestamptz not null,
  fulfilled_at timestamptz,
  fulfilled_by_staff_id uuid,
  order_id uuid,
  cancelled_at timestamptz,
  cancelled_by_staff_id uuid,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shop_reservations_tenant_id_id_key unique (tenant_id,id),
  constraint shop_reservations_tenant_id_member_id_fkey foreign key (tenant_id,member_id) references public.members(tenant_id,id),
  constraint shop_reservations_tenant_id_product_id_fkey foreign key (tenant_id,product_id) references public.addon_products(tenant_id,id),
  constraint shop_reservations_tenant_id_fulfilled_by_staff_id_fkey foreign key (tenant_id,fulfilled_by_staff_id) references public.staff(tenant_id,id),
  constraint shop_reservations_tenant_id_cancelled_by_staff_id_fkey foreign key (tenant_id,cancelled_by_staff_id) references public.staff(tenant_id,id),
  constraint shop_reservations_tenant_id_order_id_fkey foreign key (tenant_id,order_id) references public.addon_orders(tenant_id,id),
  constraint shop_reservations_quantity_chk check (quantity between 1 and 10),
  constraint shop_reservations_service_quantity_chk check (kind <> 'diet_plan' or quantity=1),
  constraint shop_reservations_kind_chk check (kind in ('product','diet_plan')),
  constraint shop_reservations_unit_price_paise_chk check (unit_price_paise>=0),
  constraint shop_reservations_currency_format_chk check (currency ~ '^[A-Z]{3}$'),
  constraint shop_reservations_product_name_chk check (btrim(product_name)<>''),
  constraint shop_reservations_expiry_chk check (expires_at>created_at),
  constraint shop_reservations_cancel_reason_chk check (cancel_reason is null or char_length(btrim(cancel_reason)) between 3 and 200),
  constraint shop_reservations_closed_state_chk check (
    (status='reserved' and fulfilled_at is null and fulfilled_by_staff_id is null and order_id is null
      and cancelled_at is null and cancelled_by_staff_id is null and cancel_reason is null)
    or (status='fulfilled' and fulfilled_at is not null and fulfilled_by_staff_id is not null and order_id is not null
      and cancelled_at is null and cancelled_by_staff_id is null and cancel_reason is null)
    or (status='cancelled_by_member' and cancelled_at is not null and cancelled_by_staff_id is null and cancel_reason is null
      and fulfilled_at is null and fulfilled_by_staff_id is null and order_id is null)
    or (status='cancelled_by_gym' and cancelled_at is not null and cancelled_by_staff_id is not null and cancel_reason is not null
      and fulfilled_at is null and fulfilled_by_staff_id is null and order_id is null))
);
create unique index shop_reservations_tenant_id_order_id_key on public.shop_reservations(tenant_id,order_id) where order_id is not null;
create index shop_reservations_tenant_id_product_id_expires_at_idx on public.shop_reservations(tenant_id,product_id,expires_at) where status='reserved';
create index shop_reservations_tenant_id_member_id_created_at_idx on public.shop_reservations(tenant_id,member_id,created_at desc);
create index shop_reservations_tenant_id_status_expires_at_id_idx on public.shop_reservations(tenant_id,status,expires_at,id);
create index shop_reservations_tenant_id_fulfilled_by_staff_id_idx on public.shop_reservations(tenant_id,fulfilled_by_staff_id) where fulfilled_by_staff_id is not null;
create index shop_reservations_tenant_id_cancelled_by_staff_id_idx on public.shop_reservations(tenant_id,cancelled_by_staff_id) where cancelled_by_staff_id is not null;

alter table public.media_assets enable row level security;
alter table public.shop_categories enable row level security;
alter table public.shop_reservations enable row level security;
create policy media_assets_platform_select on public.media_assets for select to authenticated using ((select app.is_platform()));
create policy media_assets_tenant_select on public.media_assets for select to authenticated
  using (tenant_id=(select app.current_tenant_id()) and (select app.is_front_office()));
create policy shop_categories_platform_select on public.shop_categories for select to authenticated using ((select app.is_platform()));
create policy shop_categories_platform_write on public.shop_categories for all to authenticated
  using ((select app.current_app_role())='super_admin') with check ((select app.current_app_role())='super_admin');
create policy shop_categories_tenant_select on public.shop_categories for select to authenticated
  using (tenant_id=(select app.current_tenant_id()) and (select app.is_staff()));
create policy shop_categories_tenant_write on public.shop_categories for all to authenticated
  using (tenant_id=(select app.current_tenant_id()) and (select app.is_gym_admin()))
  with check (tenant_id=(select app.current_tenant_id()) and (select app.is_gym_admin()));
create policy shop_reservations_platform_select on public.shop_reservations for select to authenticated using ((select app.is_platform()));
create policy shop_reservations_tenant_select on public.shop_reservations for select to authenticated
  using (tenant_id=(select app.current_tenant_id()) and (select app.is_front_office()));
-- Supabase default grants are removed deliberately, including service-role DML.
revoke all on public.media_assets,public.shop_categories,public.shop_reservations from public,anon,authenticated,service_role;
grant select (id,tenant_id,kind,mime,bytes,created_by_staff_id,created_at,confirmed_at,deleted_at,attached_to_id) on public.media_assets to authenticated;
grant select on public.media_assets to service_role;
grant select,insert,update on public.shop_categories to authenticated;
grant select on public.shop_reservations to authenticated;
create trigger media_assets_preview_read_only before insert or update or delete on public.media_assets for each row execute function app.enforce_preview_read_only();
create trigger shop_categories_preview_read_only before insert or update or delete on public.shop_categories for each row execute function app.enforce_preview_read_only();
create trigger shop_categories_touch_updated_at before update on public.shop_categories for each row execute function app.touch_updated_at();
create trigger shop_reservations_preview_read_only before insert or update or delete on public.shop_reservations for each row execute function app.enforce_preview_read_only();
create trigger shop_reservations_touch_updated_at before update on public.shop_reservations for each row execute function app.touch_updated_at();

create function app.shop_actor(p_audience text)
returns table (user_id uuid,tenant_id uuid,staff_id uuid,member_id uuid,app_role text)
language plpgsql stable security invoker set search_path='' as $fn$
begin
  if p_audience is null or p_audience not in ('member','front_office','gym_admin','member_or_front_office') then
    raise exception 'Unknown shop audience' using errcode='22023';
  end if;
  if auth.uid() is null or app.current_tenant_id() is null or app.current_impersonation_id() is not null then
    raise exception 'A real shop session is required' using errcode='42501';
  end if;
  if p_audience in ('member','member_or_front_office') and app.current_app_role()='member' then
    if app.current_member_id() is null or app.current_staff_id() is not null then
      raise exception 'A complete member session is required' using errcode='42501';
    end if;
    return query select m.user_id,m.tenant_id,null::uuid,m.id,'member'::text from public.members m
      where m.tenant_id=app.current_tenant_id() and m.id=app.current_member_id() and m.user_id=auth.uid();
  else
    if p_audience='member' or app.current_staff_id() is null or app.current_member_id() is not null
      or not coalesce(app.current_app_role()=any(case when p_audience='gym_admin'
        then array['gym_owner','gym_manager'] else array['gym_owner','gym_manager','front_desk'] end),false) then
      raise exception 'Allowed gym staff required' using errcode='42501';
    end if;
    return query select s.user_id,s.tenant_id,s.id,null::uuid,s.role::text from public.staff s
      where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id() and s.user_id=auth.uid()
        and s.role::text=app.current_app_role() and s.is_active;
  end if;
  if not found then raise exception 'Current bound shop actor required' using errcode='42501'; end if;
exception when invalid_text_representation then
  raise exception 'Valid shop identity required' using errcode='42501';
end
$fn$;

create function app.shop_offer_listable(p_offer public.addon_products) returns boolean
language sql stable security invoker set search_path='' as $fn$
  select coalesce(p_offer.kind in ('product','diet_plan') and p_offer.is_active and p_offer.currency='INR'
    and btrim(p_offer.name)<>'' and btrim(p_offer.description)<>'' and btrim(p_offer.cancellation_terms)<>''
    and p_offer.validity_days>0 and p_offer.trainer_staff_id is null and p_offer.trainer_qualification is null
    and p_offer.session_count is null and ((p_offer.kind='product' and p_offer.stock_quantity is not null)
      or (p_offer.kind='diet_plan' and p_offer.stock_quantity is null)),false)
$fn$;
create function app.shop_held_quantity(p_tenant_id uuid,p_product_id uuid) returns integer
language sql stable security invoker set search_path='' as $fn$
  select coalesce(sum(r.quantity),0)::integer from public.shop_reservations r
    where r.tenant_id=p_tenant_id and r.product_id=p_product_id and r.kind='product'
      and r.status='reserved' and r.expires_at>statement_timestamp()
$fn$;
create function app.media_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_id uuid,p_before jsonb,p_after jsonb)
returns void language plpgsql volatile security definer set search_path='' as $fn$
begin
  if p_action is null or p_action not in ('media_asset.registered','media_asset.confirmed','media_asset.attached','media_asset.released','media_asset.deleted') then
    raise exception 'Unsupported media audit action' using errcode='22023';
  end if;
  insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after)
    values(p_tenant_id,p_actor,p_role,p_action,'media_asset',p_record_id,p_before,p_after);
end
$fn$;
create function app.shop_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_type text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text)
returns void language plpgsql volatile security definer set search_path='' as $fn$
begin
  if p_action is null or p_action not in ('shop_reservation.created','shop_reservation.fulfilled','shop_reservation.cancelled','shop_product.display_changed') then
    raise exception 'Unsupported shop audit action' using errcode='22023';
  end if;
  insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason)
    values(p_tenant_id,p_actor,p_role,p_action,p_record_type,p_record_id,p_before,p_after,p_reason);
end
$fn$;

create function app.enforce_media_asset_verification() returns trigger
language plpgsql volatile security invoker set search_path='' as $fn$
declare v_claims jsonb;
begin
  if tg_op='DELETE' then
    raise exception 'Media metadata is retained' using errcode='GL086',detail='media_verification_invariant';
  end if;
  if tg_op='INSERT' then
    if new.confirmed_at is not null or new.object_key is not null or new.verified_source_etag is not null
      or new.published_etag is not null or new.attached_to_id is not null or new.deleted_at is not null then
      raise exception 'Media must start unverified and unattached' using errcode='GL086',detail='media_verification_invariant';
    end if;
    return new;
  end if;
  if row(new.id,new.tenant_id,new.kind,new.staging_object_key,new.mime,new.bytes,new.created_by_staff_id,new.created_at)
    is distinct from row(old.id,old.tenant_id,old.kind,old.staging_object_key,old.mime,old.bytes,old.created_by_staff_id,old.created_at)
    or (old.deleted_at is not null and new is distinct from old) then
    raise exception 'Media registration and tombstones are immutable' using errcode='GL086',detail='media_verification_invariant';
  end if;
  if row(new.object_key,new.verified_source_etag,new.published_etag,new.confirmed_at)
    is distinct from row(old.object_key,old.verified_source_etag,old.published_etag,old.confirmed_at) then
    v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
    if old.confirmed_at is not null or old.deleted_at is not null or old.object_key is not null
      or old.verified_source_etag is not null or old.published_etag is not null
      or new.confirmed_at is null or new.object_key is null or new.verified_source_etag is null or new.published_etag is null
      or btrim(new.verified_source_etag)='' or btrim(new.published_etag)=''
      or new.attached_to_id is distinct from old.attached_to_id or new.deleted_at is distinct from old.deleted_at
      or current_user<>'postgres' or current_setting('role',true) is distinct from 'service_role'
      or v_claims->>'role' is distinct from 'service_role'
      or nullif(v_claims->>'sub','') is not null or nullif(v_claims->>'impersonation_session_id','') is not null
      or current_setting('app.media_finalize_command',true) is distinct from ('finalize:'||old.id::text)
      or new.object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
      or split_part(new.object_key,'/',1)<>new.tenant_id::text or split_part(new.object_key,'/',3)<>new.kind
      or split_part(new.object_key,'.',2)<>(case new.mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
      raise exception 'Only the credential verifier may publish' using errcode='GL086',detail='media_verification_invariant';
    end if;
  end if;
  if new.attached_to_id is not null and (new.confirmed_at is null or new.deleted_at is not null)
    or (old.attached_to_id is not null and new.attached_to_id is not null and old.attached_to_id<>new.attached_to_id)
    or (new.deleted_at is not null and new.attached_to_id is not null) then
    raise exception 'Media attachment state is invalid' using errcode='GL086',detail='media_verification_invariant';
  end if;
  return new;
end
$fn$;
create trigger media_assets_verified_immutable before insert or update or delete on public.media_assets
  for each row execute function app.enforce_media_asset_verification();

create function app.enforce_shop_reservation() returns trigger
language plpgsql volatile security invoker set search_path='' as $fn$
begin
  if tg_op='INSERT' then
    if new.status is distinct from 'reserved'::public.shop_reservation_status or new.fulfilled_at is not null
      or new.fulfilled_by_staff_id is not null or new.order_id is not null or new.cancelled_at is not null
      or new.cancelled_by_staff_id is not null or new.cancel_reason is not null or new.expires_at<=new.created_at then
      raise exception 'Reservation must start open' using errcode='GL086',detail='reservation_not_open';
    end if;
    return new;
  end if;
  if old.status<>'reserved' then
    raise exception 'Reservation is already closed' using errcode='GL086',detail='reservation_not_open';
  end if;
  if old.expires_at<=statement_timestamp() then
    raise exception 'Reservation expired' using errcode='GL086',detail='reservation_expired';
  end if;
  if row(new.id,new.tenant_id,new.member_id,new.product_id,new.product_name,new.kind,new.quantity,new.quote_version,new.unit_price_paise,new.currency,new.expires_at,new.created_at)
    is distinct from row(old.id,old.tenant_id,old.member_id,old.product_id,old.product_name,old.kind,old.quantity,old.quote_version,old.unit_price_paise,old.currency,old.expires_at,old.created_at)
    or new.status not in ('fulfilled','cancelled_by_member','cancelled_by_gym') then
    raise exception 'Reservation facts and edges are fixed' using errcode='GL086',detail='reservation_not_open';
  end if;
  if (new.status='fulfilled' and (new.fulfilled_at is null or new.fulfilled_by_staff_id is null or new.order_id is null
      or new.cancelled_at is not null or new.cancelled_by_staff_id is not null or new.cancel_reason is not null))
    or (new.status='cancelled_by_member' and (new.cancelled_at is null or new.cancelled_by_staff_id is not null or new.cancel_reason is not null
      or new.fulfilled_at is not null or new.fulfilled_by_staff_id is not null or new.order_id is not null))
    or (new.status='cancelled_by_gym' and (new.cancelled_at is null or new.cancelled_by_staff_id is null or new.cancel_reason is null
      or char_length(btrim(new.cancel_reason)) not between 3 and 200
      or new.fulfilled_at is not null or new.fulfilled_by_staff_id is not null or new.order_id is not null)) then
    raise exception 'Reservation closure evidence is incomplete' using errcode='GL086',detail='reservation_not_open';
  end if;
  if new.status='fulfilled' and not exists(select 1 from public.addon_orders o
    where o.tenant_id=new.tenant_id and o.id=new.order_id and o.member_id=new.member_id
      and o.addon_product_id=new.product_id and o.quantity=new.quantity and o.created_at>=new.created_at) then
    raise exception 'Reservation sale does not match' using errcode='GL086',detail='reservation_not_open';
  end if;
  return new;
end
$fn$;
create trigger shop_reservations_enforce before insert or update on public.shop_reservations
  for each row execute function app.enforce_shop_reservation();

create function public.register_media_asset(p_kind text,p_object_key text,p_mime text,p_bytes integer)
returns uuid language plpgsql volatile security definer set search_path='' as $fn$
declare
  c_bytes constant integer:=2097152;
  c_hourly constant integer:=60;
  v_actor record;
  v_id uuid;
begin
  select * into v_actor from app.shop_actor('front_office');
  if p_kind in ('product','trainer') and v_actor.app_role not in ('gym_owner','gym_manager') then
    raise exception 'Media kind requires gym admin' using errcode='42501';
  end if;
  if p_kind is null or p_kind not in ('product','trainer','announcement') or p_object_key is null
    or p_mime is null or p_mime not in ('image/jpeg','image/png','image/webp') or p_bytes is null or p_bytes<=0 or p_bytes>c_bytes
    or p_object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/staging/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$' then
    raise exception 'Malformed media registration' using errcode='22023';
  end if;
  if split_part(p_object_key,'/',1)<>v_actor.tenant_id::text then
    raise exception 'Media tenant is unavailable' using errcode='42501';
  end if;
  if split_part(p_object_key,'/',3)<>p_kind or split_part(p_object_key,'.',2)<>
    (case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
    raise exception 'Media namespace does not match' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('media-register:'||v_actor.tenant_id::text,0));
  if exists(select 1 from public.media_assets m where m.tenant_id=v_actor.tenant_id and m.staging_object_key=p_object_key) then
    raise exception 'Media staging key already registered' using errcode='22023';
  end if;
  if (select count(*) from public.media_assets m where m.tenant_id=v_actor.tenant_id and m.created_at>statement_timestamp()-interval '1 hour')>=c_hourly then
    raise exception 'Media registration limit reached' using errcode='GL086',detail='media_limit';
  end if;
  insert into public.media_assets(tenant_id,kind,staging_object_key,mime,bytes,created_by_staff_id,created_at)
    values(v_actor.tenant_id,p_kind,p_object_key,p_mime,p_bytes,v_actor.staff_id,statement_timestamp()) returning id into v_id;
  perform app.media_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'media_asset.registered',v_id,null,
    jsonb_build_object('kind',p_kind,'mime',p_mime,'bytes',p_bytes));
  return v_id;
end
$fn$;
create function public.confirm_media_asset(p_asset_id uuid) returns void
language plpgsql volatile security invoker set search_path='' as $fn$
begin
  raise exception 'Trusted media verification is required' using errcode='42501';
end
$fn$;

create function public.finalize_media_asset(p_asset_id uuid,p_actor_user_id uuid,p_actor_staff_id uuid,p_actor_role public.app_role,
  p_tenant_id uuid,p_kind text,p_mime text,p_bytes integer,p_staging_object_key text,p_source_etag text,p_published_object_key text,p_published_etag text)
returns boolean language plpgsql volatile security definer set search_path='' as $fn$
declare
  v_claims jsonb;
  v_asset public.media_assets%rowtype;
  v_prior_marker text;
begin
  v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  if current_setting('role',true) is distinct from 'service_role' or v_claims->>'role' is distinct from 'service_role'
    or nullif(v_claims->>'sub','') is not null or nullif(v_claims->>'impersonation_session_id','') is not null then
    raise exception 'Credential-only verifier required' using errcode='42501';
  end if;
  -- Lock the active actor before the asset; revocation and finalization serialize.
  perform 1 from public.staff s where s.id=p_actor_staff_id and s.tenant_id=p_tenant_id and s.user_id=p_actor_user_id
    and s.role=p_actor_role and s.is_active and s.role in ('gym_owner','gym_manager','front_desk') for update;
  if not found or p_actor_user_id is null or p_actor_staff_id is null or p_tenant_id is null
    or p_actor_role is null or (p_kind in ('product','trainer') and p_actor_role='front_desk') then
    raise exception 'Verified active media actor required' using errcode='42501';
  end if;
  select m.* into v_asset from public.media_assets m where m.id=p_asset_id and m.tenant_id=p_tenant_id for update;
  if not found then raise exception 'Media asset unavailable' using errcode='42501'; end if;
  if v_asset.kind in ('product','trainer') and p_actor_role='front_desk' then
    raise exception 'Verified actor cannot finalize this media kind' using errcode='42501';
  end if;
  if v_asset.deleted_at is not null then
    raise exception 'Media asset is deleted' using errcode='GL086',detail='media_not_ready';
  end if;
  if p_kind is null or p_kind not in ('product','trainer','announcement') or p_kind is distinct from v_asset.kind
    or p_mime is distinct from v_asset.mime or p_bytes is distinct from v_asset.bytes
    or p_staging_object_key is distinct from v_asset.staging_object_key
    or p_source_etag is null or btrim(p_source_etag)='' or p_published_etag is null or btrim(p_published_etag)=''
    or p_published_object_key is null
    or p_published_object_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/published/(product|trainer|announcement)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    or split_part(p_published_object_key,'/',1)<>p_tenant_id::text or split_part(p_published_object_key,'/',3)<>p_kind
    or split_part(p_published_object_key,'.',2)<>(case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end) then
    raise exception 'Verified metadata does not match registration' using errcode='22023';
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

create function public.delete_media_asset(p_asset_id uuid,p_unconfirmed_only boolean default false)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record; v_asset public.media_assets%rowtype;
begin
  select * into v_actor from app.shop_actor('front_office');
  if p_asset_id is null or p_unconfirmed_only is null then raise exception 'Asset request required' using errcode='22023'; end if;
  select m.* into v_asset from public.media_assets m where m.tenant_id=v_actor.tenant_id and m.id=p_asset_id for update;
  if not found or (v_asset.kind in ('product','trainer') and v_actor.app_role not in ('gym_owner','gym_manager')) then
    raise exception 'Asset unavailable to this actor' using errcode='42501';
  end if;
  if v_asset.deleted_at is not null or (p_unconfirmed_only and v_asset.confirmed_at is not null) then return; end if;
  if v_asset.attached_to_id is not null then raise exception 'Media is attached' using errcode='GL086',detail='media_in_use'; end if;
  update public.media_assets set deleted_at=statement_timestamp() where id=v_asset.id;
  perform app.media_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'media_asset.deleted',v_asset.id,
    jsonb_build_object('deleted',false),jsonb_build_object('deleted',true));
end
$fn$;
create function app.media_attach(p_tenant_id uuid,p_asset_id uuid,p_kind text,p_record_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_asset public.media_assets%rowtype;
begin
  if p_tenant_id is null or p_asset_id is null or p_kind is null or p_record_id is null
    or p_kind not in ('product','trainer','announcement') then raise exception 'Attachment required' using errcode='22023'; end if;
  select m.* into v_asset from public.media_assets m where m.id=p_asset_id and m.tenant_id=p_tenant_id for update;
  if not found then raise exception 'Media asset unavailable' using errcode='42501'; end if;
  if v_asset.confirmed_at is null or v_asset.deleted_at is not null then raise exception 'Media not ready' using errcode='GL086',detail='media_not_ready'; end if;
  if v_asset.kind<>p_kind then raise exception 'Media kind differs' using errcode='GL086',detail='media_kind_mismatch'; end if;
  if v_asset.attached_to_id is not null and v_asset.attached_to_id<>p_record_id then
    raise exception 'Media already attached' using errcode='GL086',detail='media_in_use';
  end if;
  if v_asset.attached_to_id=p_record_id then return; end if;
  if exists(select 1 from public.media_assets m where m.tenant_id=p_tenant_id and m.kind=p_kind
    and m.attached_to_id=p_record_id and m.deleted_at is null) then
    raise exception 'Record already has media' using errcode='GL086',detail='media_in_use';
  end if;
  update public.media_assets set attached_to_id=p_record_id where id=v_asset.id;
  perform app.media_audit(p_tenant_id,auth.uid(),app.current_app_role()::public.app_role,'media_asset.attached',v_asset.id,null,
    jsonb_build_object('kind',p_kind,'record_id',p_record_id));
end
$fn$;
create function app.media_release(p_tenant_id uuid,p_kind text,p_record_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_asset public.media_assets%rowtype;
begin
  if p_tenant_id is null or p_record_id is null or p_kind is null or p_kind not in ('product','trainer','announcement') then
    raise exception 'Release target required' using errcode='22023';
  end if;
  select m.* into v_asset from public.media_assets m where m.tenant_id=p_tenant_id and m.kind=p_kind
    and m.attached_to_id=p_record_id and m.deleted_at is null for update;
  if not found then return; end if;
  update public.media_assets set attached_to_id=null,deleted_at=statement_timestamp() where id=v_asset.id;
  perform app.media_audit(p_tenant_id,auth.uid(),app.current_app_role()::public.app_role,'media_asset.released',v_asset.id,
    jsonb_build_object('record_id',p_record_id),jsonb_build_object('released',true));
  perform app.media_audit(p_tenant_id,auth.uid(),app.current_app_role()::public.app_role,'media_asset.deleted',v_asset.id,
    jsonb_build_object('deleted',false),jsonb_build_object('deleted',true));
end
$fn$;

create function public.set_shop_product_display(p_product_id uuid,p_category_id uuid,p_sort_order smallint,p_image_asset_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record; v_product public.addon_products%rowtype; v_old_image uuid;
begin
  select * into v_actor from app.shop_actor('gym_admin');
  if p_product_id is null then raise exception 'Product required' using errcode='22023'; end if;
  select p.* into v_product from public.addon_products p where p.tenant_id=v_actor.tenant_id and p.id=p_product_id for update;
  if not found then raise exception 'Product unavailable' using errcode='42501'; end if;
  if v_product.kind not in ('product','diet_plan') then raise exception 'Item not shoppable' using errcode='GL086',detail='item_unavailable'; end if;
  if p_sort_order is null or p_sort_order<0 then raise exception 'Display order invalid' using errcode='22023'; end if;
  if p_category_id is not null and (v_product.kind<>'product' or not exists(select 1 from public.shop_categories c
    where c.tenant_id=v_actor.tenant_id and c.id=p_category_id and c.is_active)) then
    raise exception 'Category unavailable' using errcode='GL086',detail='category_unavailable';
  end if;
  select m.id into v_old_image from public.media_assets m where m.tenant_id=v_actor.tenant_id and m.kind='product'
    and m.attached_to_id=v_product.id and m.deleted_at is null for update;
  if v_product.category_id is not distinct from p_category_id and v_product.sort_order=p_sort_order
    and v_old_image is not distinct from p_image_asset_id then return; end if;
  if v_old_image is distinct from p_image_asset_id then
    perform app.media_release(v_actor.tenant_id,'product',v_product.id);
    if p_image_asset_id is not null then perform app.media_attach(v_actor.tenant_id,p_image_asset_id,'product',v_product.id); end if;
  end if;
  update public.addon_products set category_id=p_category_id,sort_order=p_sort_order where id=v_product.id;
  perform app.shop_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'shop_product.display_changed','shop_product',v_product.id,
    jsonb_build_object('category_id',v_product.category_id,'sort_order',v_product.sort_order,'has_image',v_old_image is not null),
    jsonb_build_object('category_id',p_category_id,'sort_order',p_sort_order,'has_image',p_image_asset_id is not null),null);
end
$fn$;

create function public.read_member_shop()
returns table (item_id uuid,section text,name text,description text,price_paise text,currency text,gst_rate_bp integer,
  validity_days integer,cancellation_terms text,quote_version uuid,category_id uuid,category_name text,image_asset_id uuid,availability text,available_quantity integer)
language plpgsql stable security definer set search_path='' as $fn$
declare c_catalogue_probe constant integer:=201; v_actor record;
begin
  select * into v_actor from app.shop_actor('member');
  return query select p.id,case when p.kind='product' then 'products' else 'services' end,p.name,p.description,p.price_paise::text,
    p.currency,p.gst_rate_bp::integer,p.validity_days::integer,p.cancellation_terms,p.quote_version,c.id,c.name,m.id,
    case when p.kind='product' and p.stock_quantity-app.shop_held_quantity(p.tenant_id,p.id)<=0 then 'out_of_stock' else 'available' end,
    case when p.kind='product' then greatest(p.stock_quantity-app.shop_held_quantity(p.tenant_id,p.id),0) else null::integer end
    from public.addon_products p
    left join public.shop_categories c on c.tenant_id=p.tenant_id and c.id=p.category_id and c.is_active and p.kind='product'
    left join public.media_assets m on m.tenant_id=p.tenant_id and m.kind='product' and m.attached_to_id=p.id and m.confirmed_at is not null and m.deleted_at is null
    where p.tenant_id=v_actor.tenant_id and app.shop_offer_listable(p)
    order by case when p.kind='product' then 0 else 1 end,c.sort_order nulls last,c.name nulls last,p.sort_order,p.name,p.id
    limit c_catalogue_probe;
end
$fn$;
create function public.read_member_shop_reservations()
returns table (reservation_id uuid,item_id uuid,item_name text,section text,quantity integer,unit_price_paise text,total_paise text,
  currency text,state text,created_at timestamptz,expires_at timestamptz,cancel_reason text,terms_changed boolean,order_id uuid,image_asset_id uuid)
language plpgsql stable security definer set search_path='' as $fn$
declare c_page_size constant integer:=50; v_actor record;
begin
  select * into v_actor from app.shop_actor('member');
  return query select r.id,r.product_id,r.product_name,case when r.kind='product' then 'products' else 'services' end,r.quantity,
    r.unit_price_paise::text,(r.unit_price_paise::numeric*r.quantity)::text,r.currency,
    case when r.status='reserved' and r.expires_at<=statement_timestamp() then 'expired' else r.status::text end,
    r.created_at,r.expires_at,case when r.status='cancelled_by_gym' then r.cancel_reason else null::text end,
    r.status='reserved' and r.expires_at>statement_timestamp() and p.quote_version is distinct from r.quote_version,
    case when r.status='fulfilled' then r.order_id else null::uuid end,m.id
    from public.shop_reservations r
    join public.addon_products p on p.tenant_id=r.tenant_id and p.id=r.product_id
    left join public.media_assets m on m.tenant_id=p.tenant_id and m.kind='product' and m.attached_to_id=p.id
      and m.confirmed_at is not null and m.deleted_at is null
    where r.tenant_id=v_actor.tenant_id and r.member_id=v_actor.member_id
    order by case when r.status='reserved' and r.expires_at>statement_timestamp() then 0 else 1 end,
      case when r.status='reserved' and r.expires_at>statement_timestamp() then r.expires_at end asc,
      r.created_at desc,r.id desc limit c_page_size;
end
$fn$;

create function public.create_shop_reservation(p_item_id uuid,p_quantity integer,p_quote_version uuid)
returns table (reservation_id uuid,expires_at timestamptz)
language plpgsql volatile security definer set search_path='' as $fn$
declare
  c_ttl constant interval:=interval '24 hours'; c_open_limit constant integer:=5;
  c_daily_limit constant integer:=10; c_max_quantity constant integer:=10;
  v_actor record; v_product public.addon_products%rowtype; v_member public.members%rowtype;
  v_now timestamptz:=statement_timestamp(); v_id uuid; v_expires timestamptz;
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
  if v_product.kind='product' and v_product.stock_quantity-app.shop_held_quantity(v_actor.tenant_id,p_item_id)<p_quantity then
    raise exception 'Not enough left to reserve' using errcode='GL087',detail='sold_out';
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

create function public.cancel_shop_reservation(p_reservation_id uuid,p_reason text)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record; v_res public.shop_reservations%rowtype; v_reason text; v_status public.shop_reservation_status;
begin
  select * into v_actor from app.shop_actor('member_or_front_office');
  if p_reservation_id is null then raise exception 'Reservation required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shop-reservation:'||v_actor.tenant_id::text||':'||p_reservation_id::text,0));
  select r.* into v_res from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.id=p_reservation_id
    and (v_actor.member_id is null or r.member_id=v_actor.member_id) for update;
  if not found then raise exception 'Reservation unavailable' using errcode='42501'; end if;
  if v_actor.member_id is null then
    v_reason:=btrim(p_reason);
    if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'Cancellation reason required' using errcode='22023'; end if;
    v_status:='cancelled_by_gym';
  else v_status:='cancelled_by_member'; end if;
  if v_res.status<>'reserved' then raise exception 'Reservation closed' using errcode='GL086',detail='reservation_not_open'; end if;
  if v_res.expires_at<=statement_timestamp() then raise exception 'Reservation expired' using errcode='GL086',detail='reservation_expired'; end if;
  update public.shop_reservations set status=v_status,cancelled_at=statement_timestamp(),cancelled_by_staff_id=v_actor.staff_id,cancel_reason=v_reason where id=v_res.id;
  perform app.shop_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'shop_reservation.cancelled','shop_reservation',v_res.id,
    jsonb_build_object('status','reserved'),jsonb_build_object('status',v_status),v_reason);
end
$fn$;

create function app.shop_reservation_mark_fulfilled(p_reservation_id uuid,p_order_id uuid)
returns void language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record; v_res public.shop_reservations%rowtype; v_order public.addon_orders%rowtype;
begin
  select * into v_actor from app.shop_actor('front_office');
  if p_reservation_id is null or p_order_id is null then raise exception 'Reservation and order required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shop-reservation:'||v_actor.tenant_id::text||':'||p_reservation_id::text,0));
  select r.* into v_res from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.id=p_reservation_id for update;
  if not found then raise exception 'Reservation unavailable' using errcode='42501'; end if;
  if v_res.status<>'reserved' then raise exception 'Reservation closed' using errcode='GL086',detail='reservation_not_open'; end if;
  if v_res.expires_at<=statement_timestamp() then raise exception 'Reservation expired' using errcode='GL086',detail='reservation_expired'; end if;
  select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=p_order_id for update;
  if not found or v_order.member_id<>v_res.member_id or v_order.addon_product_id<>v_res.product_id or v_order.quantity<>v_res.quantity
    or v_order.sold_by_staff_id is distinct from v_actor.staff_id or v_order.status not in ('active','completed')
    or v_order.created_at<v_res.created_at or exists(select 1 from public.shop_reservations r where r.tenant_id=v_actor.tenant_id and r.order_id=p_order_id) then
    raise exception 'Sale cannot fulfil this reservation' using errcode='GL086',detail='reservation_not_open';
  end if;
  update public.shop_reservations set status='fulfilled',fulfilled_at=statement_timestamp(),fulfilled_by_staff_id=v_actor.staff_id,order_id=p_order_id where id=v_res.id;
  perform app.shop_audit(v_actor.tenant_id,v_actor.user_id,v_actor.app_role::public.app_role,'shop_reservation.fulfilled','shop_reservation',v_res.id,
    jsonb_build_object('status','reserved'),jsonb_build_object('status','fulfilled','order_id',p_order_id),null);
end
$fn$;

create function public.fulfil_shop_reservation(p_reservation_id uuid,p_quote_version uuid,p_method public.payment_method,p_reason text,p_idempotency_key uuid)
returns table (reservation_id uuid,order_id uuid,payment_id uuid,replayed boolean)
language plpgsql volatile security invoker set search_path='' as $fn$
declare v_tenant uuid; v_staff uuid; v_res public.shop_reservations%rowtype; v_sale record; v_existing_key text;
begin
  -- Invoker command cannot execute private shop_actor; validate the same bound front-office shape
  -- under the existing staff RLS. The mark helper independently validates again as definer.
  if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
    or app.current_member_id() is not null or app.current_impersonation_id() is not null or app.is_front_office() is not true
    or not exists(select 1 from public.staff s where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id()
      and s.user_id=auth.uid() and s.role::text=app.current_app_role() and s.is_active) then
    raise exception 'Active real front office required' using errcode='42501';
  end if;
  v_tenant:=app.current_tenant_id(); v_staff:=app.current_staff_id();
  if p_reservation_id is null or p_quote_version is null or p_idempotency_key is null then raise exception 'Fulfil request required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shop-reservation:'||v_tenant::text||':'||p_reservation_id::text,0));
  -- SELECT only: row locking here would require the deliberately withheld UPDATE privilege.
  select r.* into v_res from public.shop_reservations r where r.tenant_id=v_tenant and r.id=p_reservation_id;
  if not found then raise exception 'Reservation unavailable' using errcode='42501'; end if;
  if v_res.status='fulfilled' then
    select o.idempotency_key into v_existing_key from public.addon_orders o where o.tenant_id=v_tenant and o.id=v_res.order_id;
    if v_existing_key is distinct from p_idempotency_key::text then raise exception 'Reservation closed' using errcode='GL086',detail='reservation_not_open'; end if;
  elsif v_res.status<>'reserved' then raise exception 'Reservation closed' using errcode='GL086',detail='reservation_not_open';
  elsif v_res.expires_at<=statement_timestamp() then raise exception 'Reservation expired' using errcode='GL086',detail='reservation_expired'; end if;
  select * into v_sale from public.record_addon_sale(v_res.member_id,v_res.product_id,v_res.quantity,p_quote_version,null,null,null,p_method,p_reason,p_idempotency_key);
  if v_res.status='reserved' then perform app.shop_reservation_mark_fulfilled(v_res.id,v_sale.order_id); end if;
  return query select v_res.id,v_sale.order_id,v_sale.payment_id,v_sale.replayed;
exception when invalid_text_representation then
  raise exception 'Valid shop identity required' using errcode='42501';
end
$fn$;
create function public.read_shop_product_holds() returns table (product_id uuid,held_quantity integer)
language plpgsql stable security invoker set search_path='' as $fn$
begin
  if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
    or app.current_member_id() is not null or app.current_impersonation_id() is not null or app.is_front_office() is not true
    or not exists(select 1 from public.staff s where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id()
      and s.user_id=auth.uid() and s.role::text=app.current_app_role() and s.is_active) then
    raise exception 'Active front office required' using errcode='42501';
  end if;
  return query select r.product_id,sum(r.quantity)::integer from public.shop_reservations r
    where r.tenant_id=app.current_tenant_id() and r.kind='product' and r.status='reserved' and r.expires_at>statement_timestamp() group by r.product_id;
exception when invalid_text_representation then raise exception 'Valid shop identity required' using errcode='42501';
end
$fn$;
create function public.reorder_shop_categories(p_ordered_ids uuid[]) returns void
language plpgsql volatile security invoker set search_path='' as $fn$
declare c_max_categories constant integer:=200; v_id uuid; v_pos integer:=0; v_count integer;
begin
  if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
    or app.current_member_id() is not null or app.current_impersonation_id() is not null or app.is_gym_admin() is not true
    or not exists(select 1 from public.staff s where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id()
      and s.user_id=auth.uid() and s.role::text=app.current_app_role() and s.is_active) then
    raise exception 'Active gym admin required' using errcode='42501';
  end if;
  if p_ordered_ids is null or cardinality(p_ordered_ids)>c_max_categories or array_position(p_ordered_ids,null) is not null
    or (select count(distinct x) from unnest(p_ordered_ids) x)<>cardinality(p_ordered_ids) then
    raise exception 'Category order invalid' using errcode='22023';
  end if;
  foreach v_id in array p_ordered_ids loop
    update public.shop_categories set sort_order=v_pos::smallint where tenant_id=app.current_tenant_id() and id=v_id;
    get diagnostics v_count=row_count;
    if v_count<>1 then raise exception 'Category order includes unavailable id' using errcode='22023'; end if;
    v_pos:=v_pos+1;
  end loop;
exception when invalid_text_representation then raise exception 'Valid shop identity required' using errcode='42501';
end
$fn$;

-- Every new function is postgres-owned with an explicit closed execution matrix.
alter function app.shop_actor(text) owner to postgres;
alter function app.shop_offer_listable(public.addon_products) owner to postgres;
alter function app.shop_held_quantity(uuid,uuid) owner to postgres;
alter function app.media_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb) owner to postgres;
alter function app.shop_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) owner to postgres;
alter function app.media_attach(uuid,uuid,text,uuid) owner to postgres;
alter function app.media_release(uuid,text,uuid) owner to postgres;
alter function app.enforce_media_asset_verification() owner to postgres;
alter function app.enforce_shop_reservation() owner to postgres;
alter function app.shop_reservation_mark_fulfilled(uuid,uuid) owner to postgres;
alter function public.register_media_asset(text,text,text,integer) owner to postgres;
alter function public.confirm_media_asset(uuid) owner to postgres;
alter function public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text) owner to postgres;
alter function public.delete_media_asset(uuid,boolean) owner to postgres;
alter function public.set_shop_product_display(uuid,uuid,smallint,uuid) owner to postgres;
alter function public.read_member_shop() owner to postgres;
alter function public.read_member_shop_reservations() owner to postgres;
alter function public.create_shop_reservation(uuid,integer,uuid) owner to postgres;
alter function public.cancel_shop_reservation(uuid,text) owner to postgres;
alter function public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid) owner to postgres;
alter function public.read_shop_product_holds() owner to postgres;
alter function public.reorder_shop_categories(uuid[]) owner to postgres;
revoke all on function app.shop_actor(text),app.shop_offer_listable(public.addon_products),app.shop_held_quantity(uuid,uuid),
  app.media_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb),app.shop_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text),
  app.media_attach(uuid,uuid,text,uuid),app.media_release(uuid,text,uuid),app.enforce_media_asset_verification(),app.enforce_shop_reservation(),
  app.shop_reservation_mark_fulfilled(uuid,uuid),public.register_media_asset(text,text,text,integer),public.confirm_media_asset(uuid),
  public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text),public.delete_media_asset(uuid,boolean),
  public.set_shop_product_display(uuid,uuid,smallint,uuid),public.read_member_shop(),public.read_member_shop_reservations(),
  public.create_shop_reservation(uuid,integer,uuid),public.cancel_shop_reservation(uuid,text),public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid),
  public.read_shop_product_holds(),public.reorder_shop_categories(uuid[]) from public,anon,authenticated,service_role;
grant execute on function app.shop_reservation_mark_fulfilled(uuid,uuid),public.register_media_asset(text,text,text,integer),
  public.delete_media_asset(uuid,boolean),public.set_shop_product_display(uuid,uuid,smallint,uuid),public.read_member_shop(),
  public.read_member_shop_reservations(),public.create_shop_reservation(uuid,integer,uuid),public.cancel_shop_reservation(uuid,text),
  public.fulfil_shop_reservation(uuid,uuid,public.payment_method,text,uuid),public.read_shop_product_holds(),public.reorder_shop_categories(uuid[]) to authenticated;
grant execute on function public.finalize_media_asset(uuid,uuid,uuid,public.app_role,uuid,text,text,integer,text,text,text,text) to service_role;
