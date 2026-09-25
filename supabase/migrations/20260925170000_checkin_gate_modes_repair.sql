-- Repair for 20260925150000_checkin_gate_modes (forward-only; CI alone applies it).
-- 1. Rotating screen is the default: gyms opt in to a printed poster. A gym with
--    no settings row behaves as rotating, as before this feature existed.
-- 2. app.checkin_gate_actor needs no elevation of its own (its callers are).
-- 3. audit_log is written only by an app security-definer function (INT-003).
alter table public.organization_settings alter column checkin_gate_mode set default 'rotating_screen';

create function app.checkin_gate_audit(
  p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text,
  p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb
) returns void language plpgsql volatile security definer set search_path = '' as $function$
begin
  if p_action not in ('checkin_poster.replaced', 'checkin_gate.mode_changed') then
    raise exception 'Unsupported gate audit action' using errcode = '22023';
  end if;
  insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after)
    values(p_tenant_id, p_actor, p_role, p_action, p_record_type, p_record_id, p_before, p_after);
end;
$function$;
alter function app.checkin_gate_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb) owner to postgres;
revoke all on function app.checkin_gate_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb) from public, anon, authenticated, service_role;

create or replace function app.checkin_gate_actor()
returns table(tenant_id uuid, staff_id uuid, user_id uuid, role public.app_role)
language plpgsql stable security invoker set search_path = ''
as $function$
begin
  if auth.uid() is null or app.current_tenant_id() is null
     or app.current_staff_id() is null or app.current_member_id() is not null
     or app.current_impersonation_id() is not null
     or app.current_app_role() not in ('gym_owner','gym_manager') then
    raise exception 'Gym owner or manager required' using errcode = '42501';
  end if;
  return query select s.tenant_id, s.id, s.user_id, s.role
  from public.staff s where s.tenant_id = app.current_tenant_id()
    and s.id = app.current_staff_id() and s.user_id = auth.uid()
    and s.role::text = app.current_app_role() and s.is_active;
  if not found then raise exception 'Active gym owner or manager required' using errcode = '42501'; end if;
exception when invalid_text_representation then
  raise exception 'Valid gym staff identity required' using errcode = '42501';
end;
$function$;

create or replace function app.guard_checkin_gate_write()
returns trigger language plpgsql volatile security invoker set search_path = ''
as $function$
declare v_mode public.checkin_gate_mode;
begin
  if tg_table_name = 'organization_settings' then
    if old.checkin_gate_mode is distinct from new.checkin_gate_mode
       and current_user in ('authenticated', 'anon') then
      raise exception 'Change gate mode with its audited command' using errcode = '42501';
    end if;
    -- Even a same-mode settings write must wait for scans using the old hours.
    -- This guard acquires the same gym-wide lock as a mode switch.
    if old.opening_hours is distinct from new.opening_hours
       or old.checkin_dedupe_seconds is distinct from new.checkin_dedupe_seconds then
      perform pg_advisory_xact_lock(('x' || substr(md5('checkin-gate:' || old.tenant_id::text), 1, 16))::bit(64)::bigint);
    end if;
  elsif tg_table_name = 'qr_sessions' and current_user in ('authenticated', 'anon') then
    if new.gate_mode = 'printed_poster' or (tg_op = 'UPDATE' and old.gate_mode = 'printed_poster') then
      raise exception 'Replace poster with its audited command' using errcode = '42501';
    end if;
    if new.tenant_id is distinct from app.current_tenant_id() then
      raise exception 'Rotating gate belongs to another gym' using errcode = '42501';
    end if;
    -- Shared gym-mode lock permits unrelated branches to operate concurrently.
    -- A mode change takes this same lock exclusively before revoking posters.
    perform pg_advisory_xact_lock_shared(('x' || substr(md5('checkin-gate:' || new.tenant_id::text), 1, 16))::bit(64)::bigint);
    if tg_op = 'UPDATE' and (new.tenant_id is distinct from old.tenant_id
        or new.branch_id is distinct from old.branch_id) then
      raise exception 'Gate session tenant and branch are immutable' using errcode = '42501';
    end if;
    perform pg_advisory_xact_lock(('x' || substr(md5('checkin-branch:' || new.tenant_id::text || ':' || new.branch_id::text), 1, 16))::bit(64)::bigint);
    select s.checkin_gate_mode into v_mode
    from public.organization_settings s where s.tenant_id = new.tenant_id;
    if coalesce(v_mode, 'rotating_screen'::public.checkin_gate_mode) is distinct from 'rotating_screen'::public.checkin_gate_mode then
      raise exception 'Rotating gate not enabled' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function app.enforce_check_in()
returns trigger language plpgsql volatile security invoker set search_path = ''
as $function$
declare
  v_expires_at timestamptz; v_created_at timestamptz; v_revoked_at timestamptz;
  v_branch_id uuid; v_window_seconds integer; v_timezone text; v_scan_day date;
  v_is_member boolean := false;
  v_gate_mode public.checkin_gate_mode; v_settings_mode public.checkin_gate_mode;
  v_hours jsonb; v_arrival timestamptz; v_member_branch uuid; v_branch_timezone text;
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
    -- Mode changes take the gym lock exclusively. Scans take it shared, then
    -- lock the session's tenant+branch; replacement and issuance use this order
    -- too. No settings row lock demands UPDATE privilege from front desk.
    if auth.uid() is not null and new.tenant_id is distinct from app.current_tenant_id() then
      raise exception 'check-in refused: gate belongs to another gym' using errcode = 'GL010';
    end if;
    perform pg_advisory_xact_lock_shared(('x' || substr(md5('checkin-gate:' || new.tenant_id::text), 1, 16))::bit(64)::bigint);
    select q.branch_id into v_branch_id from public.qr_sessions q
      where q.id = new.qr_session_id and q.tenant_id = new.tenant_id;
    if not found then raise exception 'check-in refused: QR session is unavailable' using errcode = 'GL010'; end if;
    perform pg_advisory_xact_lock(('x' || substr(md5('checkin-branch:' || new.tenant_id::text || ':' || v_branch_id::text), 1, 16))::bit(64)::bigint);
    select s.checkin_gate_mode, s.opening_hours into v_settings_mode, v_hours
      from public.organization_settings s where s.tenant_id = new.tenant_id;
    -- Reread after waiting for a replacement; the old hash may be revoked now.
    select q.created_at, q.expires_at, q.revoked_at, q.branch_id, q.gate_mode
      into v_created_at, v_expires_at, v_revoked_at, v_branch_id, v_gate_mode
      from public.qr_sessions q where q.id = new.qr_session_id and q.tenant_id = new.tenant_id;
    if not found then raise exception 'check-in refused: QR session is unavailable' using errcode = 'GL010'; end if;
    -- A revoked poster always reports its revocation, including after a mode
    -- switch. A still-live rotating code in poster mode reports wrong mode,
    -- even if its old TTL has since elapsed. Rotating validity otherwise
    -- keeps its original time and offline-replay ordering unchanged.
    if v_gate_mode = 'printed_poster' and v_revoked_at is not null then
      raise exception 'check-in refused: QR session was revoked' using errcode = 'GL012';
    end if;
    v_settings_mode := coalesce(v_settings_mode, 'rotating_screen'::public.checkin_gate_mode);
    if v_settings_mode is distinct from v_gate_mode then
      raise exception 'check-in refused: session is for a different gate mode' using errcode = 'GL070';
    end if;
    if v_is_member and v_gate_mode = 'rotating_screen' and new.checked_in_at < v_created_at then raise exception 'check-in refused: QR session timing is invalid' using errcode = 'GL017'; end if;
    if v_expires_at <= new.checked_in_at then
      if new.offline_recorded_at is null then raise exception 'check-in refused: QR session expired' using errcode = 'GL011'; end if;
      raise exception 'check-in refused: QR session timing is invalid' using errcode = 'GL017';
    end if;
    if v_revoked_at is not null and v_revoked_at <= new.checked_in_at then
      raise exception 'check-in refused: QR session was revoked' using errcode = 'GL012';
    end if;
    new.branch_id := case when v_is_member then v_branch_id else coalesce(new.branch_id, v_branch_id) end;
    select o.timezone into v_timezone from public.organizations o where o.id = new.tenant_id;
    if v_gate_mode = 'printed_poster' then
      if new.branch_id is not null and new.branch_id is distinct from v_branch_id then
        raise exception 'check-in refused: poster belongs to another branch' using errcode = 'GL071';
      end if;
      v_arrival := statement_timestamp();
      select m.branch_id into v_member_branch from public.members m
        where m.tenant_id = new.tenant_id and m.id = new.member_id;
      if v_member_branch is distinct from v_branch_id then
        raise exception 'check-in refused: poster belongs to another branch' using errcode = 'GL071';
      end if;
      select b.timezone into v_branch_timezone from public.branches b
        where b.tenant_id = new.tenant_id and b.id = v_branch_id;
      v_branch_timezone := coalesce(v_branch_timezone, v_timezone, 'UTC');
      if not app.poster_open_at(coalesce(v_hours, '{}'::jsonb), v_arrival, v_branch_timezone) then
        raise exception 'check-in refused: gym is closed for poster check-in' using errcode = 'GL072';
      end if;
      -- A device's offline time is provenance, not authority to backdate a scan.
      new.checked_in_at := v_arrival;
      new.branch_id := v_branch_id;
    end if;
    v_scan_day := (case when v_gate_mode = 'printed_poster' then v_arrival
                        when new.offline_recorded_at is null then statement_timestamp()
                        else new.checked_in_at end at time zone
                     case when v_gate_mode = 'printed_poster' then v_branch_timezone
                          else coalesce(v_timezone, 'UTC') end)::date;
    if not exists (select 1 from public.memberships m where m.tenant_id = new.tenant_id and m.member_id = new.member_id and m.status in ('active'::public.membership_status, 'frozen'::public.membership_status) and (v_gate_mode = 'rotating_screen' and v_timezone is null or ((m.starts_on is null or m.starts_on <= v_scan_day) and (m.ends_on is null or m.ends_on >= v_scan_day)))) then
      raise exception 'check-in refused: member has no membership live on occurrence day' using errcode = 'GL013';
    end if;
  end if;
  if new.branch_id is null then select m.branch_id into v_branch_id from public.members m where m.tenant_id = new.tenant_id and m.id = new.member_id; new.branch_id := v_branch_id; end if;
  perform pg_advisory_xact_lock(('x' || substr(md5(new.tenant_id::text || ':' || new.member_id::text), 1, 16))::bit(64)::bigint);
  if v_gate_mode = 'printed_poster' and exists (
    select 1 from public.attendance a
    where a.tenant_id = new.tenant_id and a.member_id = new.member_id
      and a.id <> new.id
      and a.checked_in_at >= (v_scan_day::timestamp at time zone v_branch_timezone)
      and a.checked_in_at < ((v_scan_day + 1)::timestamp at time zone v_branch_timezone)
      and (new.client_event_id is null or a.client_event_id is distinct from new.client_event_id)
  ) then
    raise exception 'check-in refused: already checked in today' using errcode = 'GL073';
  end if;
  select s.checkin_dedupe_seconds into v_window_seconds from public.organization_settings s where s.tenant_id = new.tenant_id;
  -- The configured seconds window remains in force for every attendance source,
  -- including posters. Even across local midnight, two scans inside this window
  -- are one physical visit; beyond it the new day's poster scan may succeed.
  if coalesce(v_window_seconds, 0) > 0 and exists (select 1 from public.attendance a where a.tenant_id = new.tenant_id and a.member_id = new.member_id and a.id <> new.id and a.checked_in_at > new.checked_in_at - make_interval(secs => v_window_seconds) and a.checked_in_at < new.checked_in_at + make_interval(secs => v_window_seconds) and (new.client_event_id is null or a.client_event_id is distinct from new.client_event_id)) then
    raise exception 'check-in refused: duplicate visit' using errcode = 'GL014';
  end if;
  return new;
end;
$function$;

create or replace function public.replace_checkin_poster(p_branch_id uuid, p_session_id uuid, p_token_hash text)
returns uuid language plpgsql volatile security definer set search_path = ''
as $function$
declare v_actor record; v_mode public.checkin_gate_mode; v_old_ids uuid[];
begin
  select * into v_actor from app.checkin_gate_actor();
  if p_session_id is null or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'New session id and hash required' using errcode = '22023';
  end if;
  if p_branch_id is null then raise exception 'Branch unavailable to this gym' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock_shared(('x' || substr(md5('checkin-gate:' || v_actor.tenant_id::text), 1, 16))::bit(64)::bigint);
  perform pg_advisory_xact_lock(('x' || substr(md5('checkin-branch:' || v_actor.tenant_id::text || ':' || p_branch_id::text), 1, 16))::bit(64)::bigint);
  select s.checkin_gate_mode into v_mode from public.organization_settings s
    where s.tenant_id = v_actor.tenant_id;
  if v_mode is distinct from 'printed_poster'::public.checkin_gate_mode then
    raise exception 'Switch gym to printed poster mode first' using errcode = 'GL070';
  end if;
  if not exists (select 1 from public.branches b where b.tenant_id = v_actor.tenant_id and b.id = p_branch_id) then
    raise exception 'Branch unavailable to this gym' using errcode = '42501';
  end if;
  select coalesce(array_agg(q.id), '{}'::uuid[]) into v_old_ids
    from public.qr_sessions q where q.tenant_id = v_actor.tenant_id
      and q.branch_id = p_branch_id and q.gate_mode = 'printed_poster' and q.revoked_at is null;
  update public.qr_sessions q set revoked_at = statement_timestamp()
    where q.tenant_id = v_actor.tenant_id and q.branch_id = p_branch_id
      and q.gate_mode = 'printed_poster' and q.revoked_at is null;
  insert into public.qr_sessions(id, tenant_id, branch_id, gate_mode, token_hash, expires_at, created_by_staff_id)
    values(p_session_id, v_actor.tenant_id, p_branch_id, 'printed_poster', p_token_hash, null, v_actor.staff_id);
  perform app.checkin_gate_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'checkin_poster.replaced', 'qr_session', p_session_id,
      jsonb_build_object('branch_id',p_branch_id,'revoked_session_ids',v_old_ids),
      jsonb_build_object('branch_id',p_branch_id,'session_id',p_session_id));
  return p_session_id;
end;
$function$;

create or replace function public.set_checkin_gate_mode(p_mode public.checkin_gate_mode)
returns public.checkin_gate_mode language plpgsql volatile security definer set search_path = ''
as $function$
declare v_actor record; v_previous public.checkin_gate_mode; v_revoked uuid[];
begin
  select * into v_actor from app.checkin_gate_actor();
  if p_mode is null then raise exception 'Gate mode required' using errcode = '22023'; end if;
  -- Row locks precede BEFORE UPDATE triggers. Take the settings row before
  -- the gym lock: a direct hours/dedupe update owns that row while its guard
  -- waits for the gym lock. The reverse order would deadlock that update.
  -- Scans and poster replacements do not request a settings row lock.
  select s.checkin_gate_mode into v_previous from public.organization_settings s
    where s.tenant_id = v_actor.tenant_id for update;
  if not found then raise exception 'Gym gate settings unavailable' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(('x' || substr(md5('checkin-gate:' || v_actor.tenant_id::text), 1, 16))::bit(64)::bigint);
  if v_previous = p_mode then return p_mode; end if;
  if p_mode = 'rotating_screen' then
    select coalesce(array_agg(q.id), '{}'::uuid[]) into v_revoked
    from public.qr_sessions q where q.tenant_id = v_actor.tenant_id
      and q.gate_mode = 'printed_poster' and q.revoked_at is null;
    update public.qr_sessions q set revoked_at = statement_timestamp()
      where q.tenant_id = v_actor.tenant_id and q.gate_mode = 'printed_poster' and q.revoked_at is null;
  end if;
  update public.organization_settings s set checkin_gate_mode = p_mode where s.tenant_id = v_actor.tenant_id;
  perform app.checkin_gate_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'checkin_gate.mode_changed', 'organization_settings', v_actor.tenant_id,
      jsonb_build_object('mode',v_previous), jsonb_build_object('mode',p_mode,'revoked_session_ids',v_revoked));
  return p_mode;
end;
$function$;
