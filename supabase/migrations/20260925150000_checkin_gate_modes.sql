-- ATT-003/009-014. Forward-only; CI alone applies this migration.
-- Existing tenant policies, composite foreign keys, and indexed lookup paths stay intact.
create type public.checkin_gate_mode as enum ('printed_poster', 'rotating_screen');
alter table public.organization_settings
  add column checkin_gate_mode public.checkin_gate_mode not null default 'printed_poster';
-- Old gyms keep their working screen; new gyms get the new default.
update public.organization_settings set checkin_gate_mode = 'rotating_screen';
alter table public.qr_sessions
  add column gate_mode public.checkin_gate_mode not null default 'rotating_screen';
alter table public.qr_sessions alter column expires_at drop not null;
alter table public.qr_sessions drop constraint qr_sessions_expires_at_after_issued_at_chk;
alter table public.qr_sessions add constraint qr_sessions_expires_at_after_issued_at_chk
  check ((gate_mode = 'rotating_screen' and expires_at is not null and expires_at > issued_at)
      or (gate_mode = 'printed_poster' and expires_at is null));
create unique index qr_sessions_one_active_poster_per_branch_key
  on public.qr_sessions (tenant_id, branch_id)
  where gate_mode = 'printed_poster' and revoked_at is null;

-- Local wall-clock time; yesterday's overnight interval continues today.
-- Membership and once-per-day use today's branch-local calendar date, not this interval's starting weekday.
create function app.poster_open_at(p_hours jsonb, p_arrival timestamptz, p_timezone text)
returns boolean language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_local timestamp; v_day date; v_weekday text; v_schedule jsonb;
  v_range text; v_start time; v_end time; v_previous boolean;
begin
  if p_hours = '{}'::jsonb then return true; end if;
  if jsonb_typeof(p_hours) <> 'object' then return false; end if;
  v_local := p_arrival at time zone p_timezone;
  for v_previous in select unnest(array[false, true]) loop
    v_day := v_local::date - case when v_previous then 1 else 0 end;
    v_weekday := (array['sun','mon','tue','wed','thu','fri','sat'])
      [extract(dow from v_day)::integer + 1];
    v_schedule := p_hours -> v_weekday;
    if jsonb_typeof(v_schedule) is distinct from 'array' then continue; end if;
    for v_range in select jsonb_array_elements_text(v_schedule) loop
      if v_range !~ '^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$' then continue; end if;
      v_start := substr(v_range, 1, 5)::time;
      v_end := substr(v_range, 7, 5)::time;
      if v_previous then
        if v_end < v_start and v_local::time < v_end then return true; end if;
      elsif v_local::time >= v_start and
          ((v_end > v_start and v_local::time < v_end) or v_end < v_start) then
        return true;
      end if;
    end loop;
  end loop;
  return false;
end;
$function$;
revoke all on function app.poster_open_at(jsonb, timestamptz, text) from public, anon;
grant execute on function app.poster_open_at(jsonb, timestamptz, text) to authenticated, service_role;

-- Guard direct table writes. Definer commands below validate JWT and audit.
-- The two definer commands own these rows for the duration of the transaction:
-- no untrusted `SET ROLE postgres` or request-supplied tenant is involved.
create function app.guard_checkin_gate_write()
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
    if v_mode is distinct from 'rotating_screen'::public.checkin_gate_mode then
      raise exception 'Rotating gate not enabled' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;
create trigger organization_settings_guard_checkin_gate
  before update on public.organization_settings
  for each row execute function app.guard_checkin_gate_write();
create trigger qr_sessions_guard_checkin_gate
  before insert or update on public.qr_sessions
  for each row execute function app.guard_checkin_gate_write();
revoke all on function app.guard_checkin_gate_write() from public, anon;
-- Never accept actor or tenant from an RPC argument; revalidate even a JWT
-- whose staff_id was revoked, made inactive, or changed roles.
create function app.checkin_gate_actor()
returns table(tenant_id uuid, staff_id uuid, user_id uuid, role public.app_role)
language plpgsql stable security definer set search_path = ''
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
revoke all on function app.checkin_gate_actor() from public, anon, authenticated;

-- Shared gym-mode then exclusive tenant+branch advisory locks serialize a branch's
-- replacement without blocking other branches; switching modes takes the gym
-- lock exclusively. The partial unique index independently prevents two posters.
create function public.replace_checkin_poster(p_branch_id uuid, p_session_id uuid, p_token_hash text)
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
  insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after)
    values(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'checkin_poster.replaced', 'qr_session', p_session_id,
      jsonb_build_object('branch_id',p_branch_id,'revoked_session_ids',v_old_ids),
      jsonb_build_object('branch_id',p_branch_id,'session_id',p_session_id));
  return p_session_id;
end;
$function$;
revoke all on function public.replace_checkin_poster(uuid, uuid, text) from public, anon, service_role;
grant execute on function public.replace_checkin_poster(uuid, uuid, text) to authenticated;

create function public.set_checkin_gate_mode(p_mode public.checkin_gate_mode)
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
  insert into public.audit_log(tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after)
    values(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'checkin_gate.mode_changed', 'organization_settings', v_actor.tenant_id,
      jsonb_build_object('mode',v_previous), jsonb_build_object('mode',p_mode,'revoked_session_ids',v_revoked));
  return p_mode;
end;
$function$;
revoke all on function public.set_checkin_gate_mode(public.checkin_gate_mode) from public, anon, service_role;
grant execute on function public.set_checkin_gate_mode(public.checkin_gate_mode) to authenticated;

-- Both direct attendance inserts and the member RPC pass through this trigger.
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
