-- Approved current member booking-policy projections; read-only, forward-only.

create or replace function public.read_member_class_schedule(p_from date,p_to date)
returns table(session_id uuid,service_id uuid,service_name text,service_description text,branch_id uuid,branch_name text,timezone text,session_date date,starts_at timestamptz,ends_at timestamptz,trainer_name text,capacity integer,booked_count integer,spots_left integer,session_status public.class_session_status,my_booking_id uuid,my_booking_status public.booking_status,availability text,can_cancel boolean,cancel_by timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
declare a record; v_cross boolean; v_hours integer;
begin
  select * into a from app.class_member_actor();
  if p_from is null or p_to is null or p_from > p_to or p_to-p_from > 30 then raise exception 'Invalid class window' using errcode='22023'; end if;
  if not app.class_gym_eligible(a.tenant_id) then return; end if;
  select t.class_allow_cross_branch,t.class_cancel_window_hours into v_cross,v_hours from public.organization_settings t where t.tenant_id=a.tenant_id;
  return query select s.id,s.service_id,sv.name,sv.description,s.branch_id,br.name,app.class_branch_timezone(a.tenant_id,s.branch_id),s.session_date,s.starts_at,s.ends_at,tr.full_name,
    s.capacity,c.holding,greatest(s.capacity-c.holding,0),s.status,b.id,b.status,
    case when s.status='cancelled' then 'cancelled' when app.class_booking_holds(b.status) then 'booked'
      when statement_timestamp() >= s.starts_at or not sv.is_active or b.status='cancelled_by_gym' then 'closed'
      when not app.member_has_live_membership(a.tenant_id,a.member_id,s.session_date) then 'membership_not_live'
      when c.holding >= s.capacity then 'full' else 'open' end,
    coalesce(b.status='booked' and s.status='scheduled' and statement_timestamp() <= s.starts_at-coalesce(v_hours,2)*interval '1 hour',false),
    case when b.status='booked' or (case when s.status='cancelled' then 'cancelled' when app.class_booking_holds(b.status) then 'booked'
      when statement_timestamp() >= s.starts_at or not sv.is_active or b.status='cancelled_by_gym' then 'closed'
      when not app.member_has_live_membership(a.tenant_id,a.member_id,s.session_date) then 'membership_not_live'
      when c.holding >= s.capacity then 'full' else 'open' end)='open' then s.starts_at-coalesce(v_hours,2)*interval '1 hour' else null end
  from public.class_sessions s join public.services sv on sv.tenant_id=s.tenant_id and sv.id=s.service_id
    join public.branches br on br.tenant_id=s.tenant_id and br.id=s.branch_id
    left join public.staff tr on tr.tenant_id=s.tenant_id and tr.id=s.trainer_staff_id
    left join public.class_bookings b on b.tenant_id=s.tenant_id and b.session_id=s.id and b.member_id=a.member_id
    cross join lateral (select app.class_holding_count(s.tenant_id,s.id) as holding) c
  where s.tenant_id=a.tenant_id and (s.branch_id=a.branch_id or coalesce(v_cross,false)) and s.session_date between p_from and p_to
    and ((s.status='scheduled' and sv.is_active) or b.id is not null)
  order by s.starts_at,s.id;
end $fn$;
alter function public.read_member_class_schedule(date,date) owner to postgres;

create function public.read_member_pt_policy()
returns table(cancel_window_hours integer,late_cancel_consumes_session boolean)
language plpgsql stable security definer set search_path = '' as $fn$
declare a record;
begin
  select * into a from app.pt_member_actor();
  return query select s.pt_cancel_window_hours,s.pt_late_cancel_consumes_session
  from public.organization_settings s where s.tenant_id=a.tenant_id;
end $fn$;

alter function public.read_member_pt_policy() owner to postgres;
revoke all on function public.read_member_pt_policy() from public,anon,authenticated,service_role;
grant execute on function public.read_member_pt_policy() to authenticated;
