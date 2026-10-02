-- BOOKING primitives: shared by CLS and PTF. Mirrors the check-in date predicate.
create type public.booking_status as enum (
  'booked', 'cancelled_by_member', 'cancelled_by_gym', 'session_cancelled', 'attended', 'no_show'
);

create function app.booking_lock(p_tenant_id uuid, p_kind text, p_resource_id uuid)
returns void language plpgsql volatile security invoker set search_path = '' as $fn$
begin
  if p_tenant_id is null or p_resource_id is null or p_kind is null
     or p_kind not in ('class_session', 'trainer_slot') then
    raise exception 'Invalid booking resource' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'booking:' || p_tenant_id || ':' || p_kind || ':' || p_resource_id, 0));
end
$fn$;

create function app.member_has_live_membership(p_tenant_id uuid, p_member_id uuid, p_on date)
returns boolean language sql stable security invoker set search_path = '' as $fn$
  select exists (select 1 from public.memberships m
    where m.tenant_id = p_tenant_id and m.member_id = p_member_id
      and m.status in ('active', 'frozen')
      and (m.starts_on is null or m.starts_on <= p_on)
      and (m.ends_on is null or m.ends_on >= p_on))
$fn$;

alter function app.booking_lock(uuid,text,uuid) owner to postgres;
alter function app.member_has_live_membership(uuid,uuid,date) owner to postgres;
revoke all on function app.booking_lock(uuid,text,uuid) from public, anon;
revoke all on function app.member_has_live_membership(uuid,uuid,date) from public, anon;
grant execute on function app.booking_lock(uuid,text,uuid) to authenticated, service_role;
grant execute on function app.member_has_live_membership(uuid,uuid,date) to authenticated, service_role;
