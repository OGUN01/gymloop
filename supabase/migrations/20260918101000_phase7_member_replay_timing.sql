-- Phase 7 member replay timing repair.
--
-- The member-only replay boundary introduced a QR creation-time check in the
-- shared attendance trigger. Historical staff/core writes predate the QR
-- session fixtures by design, so that check must govern only member commands.

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
    if v_is_member and new.checked_in_at < v_created_at then raise exception 'check-in refused: QR session timing is invalid' using errcode = 'GL017'; end if;
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
