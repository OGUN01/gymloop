-- Phase 7 member mobile boundary.
--
-- A member has no table-level attendance write or QR-session read path. The
-- only member mutation is the token-proof command below; it derives every
-- identity fact from the verified JWT and does the lookup and insert together.

drop policy if exists attendance_member_insert on public.attendance;
drop policy if exists qr_sessions_member_scan_select on public.qr_sessions;

create or replace function app.enforce_check_in()
returns trigger language plpgsql volatile security invoker set search_path = ''
as $function$
declare
  v_expires_at timestamptz; v_created_at timestamptz; v_revoked_at timestamptz;
  v_branch_id uuid; v_window_seconds integer; v_timezone text; v_scan_day date;
  v_is_member boolean := false;
begin
  begin
    v_is_member := auth.uid() is not null and app.current_app_role() = 'member'
      and app.current_tenant_id() is not null and app.current_member_id() is not null
      and app.current_staff_id() is null and app.current_impersonation_id() is null;
  exception when invalid_text_representation then v_is_member := false;
  end;
  new.tenant_id := coalesce(new.tenant_id, app.current_tenant_id());
  if app.current_member_id() is not null and not v_is_member then
    raise exception 'check-in refused: incomplete member identity' using errcode = '42501';
  end if;
  if v_is_member and new.member_id is distinct from app.current_member_id() then
    raise exception 'check-in refused: member identity mismatch' using errcode = '42501';
  end if;
  if v_is_member and (new.source <> 'qr'::public.attendance_source or new.qr_session_id is null or new.assist_reason is not null or new.assisted_by_staff_id is not null or new.membership_id is not null) then
    raise exception 'check-in refused: member check-in must be a gate scan' using errcode = '42501';
  end if;
  if new.assisted_by_staff_id is not null and app.current_staff_id() is not null and new.assisted_by_staff_id is distinct from app.current_staff_id() then
    raise exception 'check-in refused: acting staff mismatch' using errcode = 'GL016';
  end if;
  if new.source = 'front_desk'::public.attendance_source and new.assisted_by_staff_id is null then new.assisted_by_staff_id := app.current_staff_id(); end if;
  if new.offline_recorded_at is not null then
    if not v_is_member or new.source <> 'qr'::public.attendance_source or new.qr_session_id is null or new.client_event_id is null then
      raise exception 'check-in refused: offline replay requires a member gate event' using errcode = '42501';
    end if;
    if new.offline_recorded_at > statement_timestamp() then raise exception 'check-in refused: offline time is in the future' using errcode = 'GL017'; end if;
    new.checked_in_at := new.offline_recorded_at; new.replayed_at := statement_timestamp();
  elsif new.replayed_at is not null then
    raise exception 'check-in refused: replay evidence is server-owned' using errcode = 'GL017';
  elsif v_is_member then
    new.checked_in_at := statement_timestamp();
  end if;
  if new.qr_session_id is not null then
    select q.created_at, q.expires_at, q.revoked_at, q.branch_id into v_created_at, v_expires_at, v_revoked_at, v_branch_id from public.qr_sessions q where q.id = new.qr_session_id and q.tenant_id = new.tenant_id;
    if not found then raise exception 'check-in refused: QR session is unavailable' using errcode = 'GL010'; end if;
    if new.checked_in_at < v_created_at then raise exception 'check-in refused: QR session timing is invalid' using errcode = 'GL017'; end if;
    if v_expires_at <= new.checked_in_at then
      if new.offline_recorded_at is null then raise exception 'check-in refused: QR session expired' using errcode = 'GL011'; end if;
      raise exception 'check-in refused: QR session timing is invalid' using errcode = 'GL017';
    end if;
    if v_revoked_at is not null and v_revoked_at <= new.checked_in_at then raise exception 'check-in refused: QR session was revoked' using errcode = 'GL012'; end if;
    new.branch_id := case when v_is_member then v_branch_id else coalesce(new.branch_id, v_branch_id) end;
    select o.timezone into v_timezone from public.organizations o where o.id = new.tenant_id;
    v_scan_day := (case when new.offline_recorded_at is null then statement_timestamp() else new.checked_in_at end at time zone coalesce(v_timezone, 'UTC'))::date;
    if not exists (select 1 from public.memberships m where m.tenant_id = new.tenant_id and m.member_id = new.member_id and m.status in ('active'::public.membership_status, 'frozen'::public.membership_status) and (v_timezone is null or ((m.starts_on is null or m.starts_on <= v_scan_day) and (m.ends_on is null or m.ends_on >= v_scan_day)))) then
      raise exception 'check-in refused: member has no membership live on occurrence day' using errcode = 'GL013';
    end if;
  end if;
  if new.branch_id is null then select m.branch_id into v_branch_id from public.members m where m.tenant_id = new.tenant_id and m.id = new.member_id; new.branch_id := v_branch_id; end if;
  perform pg_advisory_xact_lock(('x' || substr(md5(new.tenant_id::text || ':' || new.member_id::text), 1, 16))::bit(64)::bigint);
  select s.checkin_dedupe_seconds into v_window_seconds from public.organization_settings s where s.tenant_id = new.tenant_id;
  if coalesce(v_window_seconds, 0) > 0 and exists (select 1 from public.attendance a where a.tenant_id = new.tenant_id and a.member_id = new.member_id and a.id <> new.id and a.checked_in_at > new.checked_in_at - make_interval(secs => v_window_seconds) and a.checked_in_at < new.checked_in_at + make_interval(secs => v_window_seconds) and (new.client_event_id is null or a.client_event_id is distinct from new.client_event_id)) then
    raise exception 'check-in refused: duplicate visit' using errcode = 'GL014';
  end if;
  return new;
end;
$function$;

create function app.member_mobile_identity()
returns table (tenant_id uuid, member_id uuid, user_id uuid)
language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant uuid; v_member uuid; v_user uuid;
begin
  begin
    if auth.uid() is null or app.current_app_role() is distinct from 'member'
       or app.current_tenant_id() is null or app.current_member_id() is null
       or app.current_staff_id() is not null or app.current_impersonation_id() is not null then
      raise exception 'Member command requires a complete member identity' using errcode = '42501';
    end if;
    v_tenant := app.current_tenant_id(); v_member := app.current_member_id(); v_user := auth.uid();
  exception when invalid_text_representation then
    raise exception 'Member command requires a complete member identity' using errcode = '42501';
  end;
  if not exists (select 1 from public.members m where m.tenant_id = v_tenant and m.id = v_member and m.user_id = v_user and m.status not in ('cancelled'::public.member_status, 'blocked'::public.member_status) and m.erased_at is null) then
    raise exception 'Member command requires an active linked member' using errcode = '42501';
  end if;
  return query select v_tenant, v_member, v_user;
end;
$function$;

create function app.record_member_mobile_check_in(p_token_hash text, p_client_event_id uuid default null, p_offline_recorded_at timestamptz default null)
returns table (id uuid, checked_in_at timestamptz, source public.attendance_source, replay boolean)
language plpgsql volatile security definer set search_path = ''
as $function$
declare v_tenant uuid; v_member uuid; v_existing public.attendance%rowtype; v_gate public.qr_sessions%rowtype; v_recorded public.attendance%rowtype;
begin
  select i.tenant_id, i.member_id into v_tenant, v_member from app.member_mobile_identity() i;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'A gate-token proof is required' using errcode = '22023'; end if;
  if p_offline_recorded_at is not null and p_client_event_id is null then raise exception 'Offline replay requires its event id' using errcode = '22023'; end if;
  if p_client_event_id is not null then
    select a.* into v_existing from public.attendance a where a.tenant_id = v_tenant and a.client_event_id = p_client_event_id;
    if found then
      if v_existing.member_id is distinct from v_member then raise exception 'That check-in id belongs to another member' using errcode = 'GL018'; end if;
      return query select v_existing.id, v_existing.checked_in_at, v_existing.source, true; return;
    end if;
  end if;
  select q.* into v_gate from public.qr_sessions q where q.tenant_id = v_tenant and q.token_hash = p_token_hash;
  if not found then raise exception 'check-in refused: QR session is unavailable' using errcode = 'GL010'; end if;
  insert into public.attendance (tenant_id, branch_id, member_id, source, qr_session_id, client_event_id, offline_recorded_at)
  values (v_tenant, v_gate.branch_id, v_member, 'qr'::public.attendance_source, v_gate.id, p_client_event_id, p_offline_recorded_at)
  returning * into v_recorded;
  return query select v_recorded.id, v_recorded.checked_in_at, v_recorded.source, false;
exception when unique_violation then
  if p_client_event_id is null then raise; end if;
  select a.* into v_existing from public.attendance a where a.tenant_id = v_tenant and a.client_event_id = p_client_event_id;
  if found and v_existing.member_id = v_member then return query select v_existing.id, v_existing.checked_in_at, v_existing.source, true; return; end if;
  raise exception 'That check-in id belongs to another member' using errcode = 'GL018';
end;
$function$;

-- This invoker wrapper is the PostgREST surface. The narrowly scoped definer
-- it calls is needed only because members intentionally have no table access.
create function public.member_mobile_check_in(p_token_hash text, p_client_event_id uuid default null, p_offline_recorded_at timestamptz default null)
returns table (id uuid, checked_in_at timestamptz, source public.attendance_source, replay boolean)
language sql volatile security invoker set search_path = ''
as $function$
  select * from app.record_member_mobile_check_in(p_token_hash, p_client_event_id, p_offline_recorded_at)
$function$;

create function public.read_member_mobile_money()
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant uuid; v_member uuid;
begin
  select i.tenant_id, i.member_id into v_tenant, v_member from app.member_mobile_identity() i;
  return jsonb_build_object(
    'receipts', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'amountPaise', p.amount_paise::text, 'currency', p.currency, 'paidAt', p.paid_at, 'receiptNumber', p.receipt_number, 'status', p.status) order by p.created_at desc) from public.payments p where p.tenant_id = v_tenant and p.member_id = v_member), '[]'::jsonb),
    'addOns', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', coalesce(product.name, 'Add-on'), 'status', o.status, 'totalPaise', o.total_paise::text, 'currency', o.currency, 'sessionsUsed', o.sessions_used, 'sessionsTotal', o.sessions_total) order by o.created_at desc) from public.addon_orders o left join public.addon_products product on product.id = o.product_id and product.tenant_id = o.tenant_id where o.tenant_id = v_tenant and o.member_id = v_member), '[]'::jsonb)
  );
end;
$function$;

-- The member portal needs presentation settings, but a table-level settings
-- read would disclose GSTIN and financial configuration. Keep this projection
-- claim-scoped and deliberately narrower than the underlying row.
create function public.read_member_portal_settings()
returns table (
  city text,
  state text,
  weekly_goal_default smallint,
  week_start_day smallint,
  streak_rule_type public.streak_rule_type
)
language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant uuid;
begin
  select i.tenant_id into v_tenant from app.member_mobile_identity() i;
  return query
    select s.city, s.state, s.weekly_goal_default, s.week_start_day, s.streak_rule_type
    from public.organization_settings s
    where s.tenant_id = v_tenant;
end;
$function$;

revoke all on function app.member_mobile_identity() from public, anon, authenticated;
revoke all on function app.record_member_mobile_check_in(text, uuid, timestamptz) from public, anon;
grant execute on function app.record_member_mobile_check_in(text, uuid, timestamptz) to authenticated;
revoke all on function public.member_mobile_check_in(text, uuid, timestamptz) from public, anon;
grant execute on function public.member_mobile_check_in(text, uuid, timestamptz) to authenticated;
revoke all on function public.read_member_mobile_money() from public, anon;
grant execute on function public.read_member_mobile_money() to authenticated;
revoke all on function public.read_member_portal_settings() from public, anon;
grant execute on function public.read_member_portal_settings() to authenticated;
