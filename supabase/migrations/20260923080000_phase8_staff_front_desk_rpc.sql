-- HARD-004: combine the RLS-visible member read and assisted attendance write
-- in one network round trip. The existing attendance policies and trigger
-- remain the final authority for tenant, actor, duplicate and source rules.

create or replace function public.record_staff_front_desk_check_in(
  p_member_id uuid,
  p_reason text,
  p_client_event_id uuid
)
returns table (
  id uuid,
  checked_in_at timestamptz,
  source public.attendance_source,
  member_name text
)
language plpgsql volatile security invoker set search_path = ''
as $function$
declare
  v_member_name text;
  v_branch_id uuid;
  v_recorded public.attendance%rowtype;
begin
  if current_user <> 'authenticated'
     or auth.uid() is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.is_front_office() is not true then
    raise exception 'assisted check-in requires an authenticated front-office actor'
      using errcode = '42501';
  end if;

  if p_reason is null or p_reason ~ '^[[:space:]]*$' then
    raise exception 'assisted check-in requires a reason' using errcode = '22023';
  end if;

  -- Deliberately no tenant predicate: the caller's members SELECT policy must
  -- be the boundary, and a foreign member must look like an unknown one.
  select m.full_name, m.branch_id into v_member_name, v_branch_id
  from public.members m where m.id = p_member_id;
  if not found then return; end if;

  insert into public.attendance (
    tenant_id, branch_id, member_id, source, assist_reason, client_event_id
  ) values (
    app.current_tenant_id(), v_branch_id, p_member_id,
    'front_desk'::public.attendance_source, p_reason, p_client_event_id
  ) returning * into v_recorded;

  id := v_recorded.id;
  checked_in_at := v_recorded.checked_in_at;
  source := v_recorded.source;
  member_name := v_member_name;
  return next;
end;
$function$;

revoke all on function public.record_staff_front_desk_check_in(uuid, text, uuid)
  from public, anon, service_role;
grant execute on function public.record_staff_front_desk_check_in(uuid, text, uuid)
  to authenticated;
