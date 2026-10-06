-- NAVC-004/005/013/014/015: discovery configuration and caller-owned commitments.
-- Existing class eligibility, generation, commands and table policies are unchanged.

alter table public.organization_settings
  add column member_classes_enabled boolean not null default false;

-- Compatibility is evaluated once against one clock. Later catalogue/booking
-- changes never infer visibility or override a saved owner choice.
do $backfill$
declare v_now timestamptz := statement_timestamp();
begin
  update public.organization_settings os
  set member_classes_enabled = true
  where exists (
    select 1 from public.services sv
    where sv.tenant_id = os.tenant_id and sv.is_active
  ) or exists (
    select 1 from public.class_bookings b
    join public.class_sessions s on s.tenant_id = b.tenant_id and s.id = b.session_id
    where b.tenant_id = os.tenant_id and b.status = 'booked'
      and s.status = 'scheduled' and s.ends_at > v_now
  );
end $backfill$;

-- Keep the canonical writer byte-identical except for the additive action.
create or replace function app.class_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_type text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if p_action is null or p_action not in ('service.created','service.updated','service.activated','service.deactivated',
    'class_rule.created','class_rule.updated','class_session.created','class_session.updated','class_session.cancelled',
    'class_sessions.pruned','class_booking.booked','class_booking.cancelled','class_booking.cancelled_by_gym','class_booking.attendance_marked',
    'organization.class_visibility_changed') then
    raise exception 'Unknown class audit action' using errcode = '22023';
  end if;
  insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason,occurred_at)
    values(p_tenant_id,p_actor,p_role,p_action,p_record_type,p_record_id,p_before,p_after,p_reason,statement_timestamp());
end $fn$;

-- A normal request can retain this field while editing existing settings.
-- Only validated postgres-owned commands may change it.
create function app.guard_member_class_visibility_write()
returns trigger language plpgsql security invoker set search_path = '' as $fn$
begin
  if current_user in ('authenticated','anon') then
    if (tg_op = 'INSERT' and new.member_classes_enabled is distinct from false)
      or (tg_op = 'UPDATE' and new.member_classes_enabled is distinct from old.member_classes_enabled) then
      raise exception 'Use the class visibility command' using errcode = '42501';
    end if;
  end if;
  return new;
end $fn$;
create trigger organization_settings_guard_member_class_visibility
  before insert or update on public.organization_settings
  for each row execute function app.guard_member_class_visibility_write();

create function public.set_member_classes_enabled(p_enabled boolean)
returns table(enabled boolean,changed boolean)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; v_previous boolean;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'Authenticated staff audience required' using errcode = '42501';
  end if;
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_enabled is null then raise exception 'Invalid class visibility' using errcode = '22023'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode = '42501'; end if;
  select os.member_classes_enabled into v_previous
  from public.organization_settings os where os.tenant_id = a.tenant_id for update;
  if not found then raise exception 'Class settings unavailable' using errcode = '22023'; end if;
  if v_previous = p_enabled then return query select v_previous,false; return; end if;
  update public.organization_settings os set member_classes_enabled = p_enabled where os.tenant_id = a.tenant_id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'organization.class_visibility_changed','organization_settings',a.tenant_id,
    jsonb_build_object('member_classes_enabled',v_previous),jsonb_build_object('member_classes_enabled',p_enabled),null);
  return query select p_enabled,true;
exception when invalid_text_representation then
  raise exception 'Authenticated staff identity required' using errcode = '42501';
end $fn$;

create function public.read_member_class_visibility()
returns table(enabled boolean)
language plpgsql stable security definer set search_path = '' as $fn$
declare a record; v_enabled boolean;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'Authenticated member audience required' using errcode = '42501';
  end if;
  select * into a from app.class_member_actor();
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode = '42501'; end if;
  select os.member_classes_enabled into v_enabled from public.organization_settings os where os.tenant_id = a.tenant_id;
  if not found then raise exception 'Class settings unavailable' using errcode = '22023'; end if;
  return query select v_enabled;
exception when invalid_text_representation then
  raise exception 'Authenticated member identity required' using errcode = '42501';
end $fn$;

create function public.read_member_upcoming_class_bookings()
returns table(session_id uuid,service_id uuid,service_name text,service_description text,branch_id uuid,branch_name text,timezone text,session_date date,starts_at timestamptz,ends_at timestamptz,trainer_name text,capacity integer,booked_count integer,spots_left integer,session_status public.class_session_status,my_booking_id uuid,my_booking_status public.booking_status,availability text,can_cancel boolean,cancel_by timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
declare a record; v_hours integer; v_now timestamptz := statement_timestamp();
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'Authenticated member audience required' using errcode = '42501';
  end if;
  select * into a from app.class_member_actor();
  if not app.class_gym_eligible(a.tenant_id) then return; end if;
  select os.class_cancel_window_hours into v_hours from public.organization_settings os where os.tenant_id = a.tenant_id;
  return query
  select s.id,s.service_id,sv.name,sv.description,s.branch_id,br.name,
    app.class_branch_timezone(a.tenant_id,s.branch_id),
    (s.starts_at at time zone app.class_branch_timezone(a.tenant_id,s.branch_id))::date,
    s.starts_at,s.ends_at,tr.full_name,s.capacity,c.holding,greatest(s.capacity-c.holding,0),s.status,b.id,b.status,
    case when s.status = 'cancelled' then 'cancelled'
      when app.class_booking_holds(b.status) then 'booked' else 'closed' end,
    coalesce(b.status = 'booked' and s.status = 'scheduled'
      and v_now <= s.starts_at-coalesce(v_hours,2)*interval '1 hour',false),
    case when b.status = 'booked' then s.starts_at-coalesce(v_hours,2)*interval '1 hour' else null end
  from public.class_bookings b
    join public.class_sessions s on s.tenant_id = b.tenant_id and s.id = b.session_id
    join public.services sv on sv.tenant_id = s.tenant_id and sv.id = s.service_id
    join public.branches br on br.tenant_id = s.tenant_id and br.id = s.branch_id
    left join public.staff tr on tr.tenant_id = s.tenant_id and tr.id = s.trainer_staff_id
    cross join lateral (select app.class_holding_count(s.tenant_id,s.id) as holding) c
  where b.tenant_id = a.tenant_id and b.member_id = a.member_id
    -- 28 * 24 absolute hours: session timezone/DST cannot shift this horizon.
    and s.ends_at > v_now and s.starts_at < v_now+interval '672 hours'
  order by s.starts_at,s.id;
exception when invalid_text_representation then
  raise exception 'Authenticated member identity required' using errcode = '42501';
end $fn$;

alter function app.class_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) owner to postgres;
alter function app.guard_member_class_visibility_write() owner to postgres;
alter function public.set_member_classes_enabled(boolean) owner to postgres;
alter function public.read_member_class_visibility() owner to postgres;
alter function public.read_member_upcoming_class_bookings() owner to postgres;
revoke all on function app.class_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function app.guard_member_class_visibility_write() from public,anon,authenticated,service_role;
revoke all on function public.set_member_classes_enabled(boolean),public.read_member_class_visibility(),public.read_member_upcoming_class_bookings() from public,anon,authenticated,service_role;
grant execute on function public.set_member_classes_enabled(boolean),public.read_member_class_visibility(),public.read_member_upcoming_class_bookings() to authenticated;
