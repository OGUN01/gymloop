-- Preserve the client-event replay boundary when a member already has a
-- different visit inside the duplicate window. The table's unique index remains
-- the final authority for concurrent inserts; this read only orders refusals.

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

  -- The caller's members SELECT policy makes a foreign member indistinguishable
  -- from an unknown member before the event ID is examined.
  select m.full_name, m.branch_id into v_member_name, v_branch_id
  from public.members m where m.id = p_member_id;
  if not found then return; end if;

  -- A reused event ID must reach the route's same-member replay lookup, even
  -- when this target also has an unrelated visit in the duplicate window.
  -- This lookup is limited to the authenticated caller's tenant and subject to
  -- the attendance SELECT policy; the unique index still catches races.
  if p_client_event_id is not null and exists (
    select 1 from public.attendance a
    where a.tenant_id = app.current_tenant_id()
      and a.client_event_id = p_client_event_id
  ) then
    raise exception 'check-in refused: client event already recorded'
      using errcode = '23505', constraint = 'attendance_tenant_id_client_event_id_key';
  end if;

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
