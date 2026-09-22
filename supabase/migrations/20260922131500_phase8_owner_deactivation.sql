-- PILOT-008: retire one exact linked gym owner through a verified platform
-- command. The identity trigger owns session revocation and its own audit row;
-- this command adds the request-keyed platform decision in the same transaction.
create function public.deactivate_gym_owner(
  p_tenant_id uuid,
  p_owner_staff_id uuid,
  p_expected_user_id uuid,
  p_request_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor uuid := app.require_platform_super_admin();
  v_org_id uuid;
  v_owner public.staff%rowtype;
  v_request jsonb;
  v_replay jsonb;
  v_result jsonb;
begin
  if p_tenant_id is null or p_owner_staff_id is null
     or p_expected_user_id is null or p_request_key is null then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;

  v_request := jsonb_build_object(
    'ownerStaffId', p_owner_staff_id,
    'expectedUserId', p_expected_user_id
  );
  select o.id into v_org_id
    from public.organizations o
   where o.id = p_tenant_id
   for update;
  if not found then
    raise exception 'Not found' using errcode = 'P0002';
  end if;

  select s.* into v_owner
    from public.staff s
   where s.id = p_owner_staff_id
     and s.tenant_id = v_org_id
     and s.role = 'gym_owner'::public.app_role
   for update;
  if not found then
    raise exception 'Not found' using errcode = 'P0002';
  end if;

  v_replay := app.platform_request_replay(
    p_tenant_id, p_request_key, v_actor, 'deactivate_gym_owner', v_request
  );
  if v_replay is not null then
    return v_replay;
  end if;

  if not v_owner.is_active or v_owner.user_id is distinct from p_expected_user_id then
    raise exception 'Stale platform state'
      using errcode = '40001', detail = 'stale_platform_state';
  end if;

  update public.staff
     set is_active = false
   where id = v_owner.id and tenant_id = p_tenant_id;

  v_result := jsonb_build_object(
    'tenantId', p_tenant_id,
    'ownerStaffId', v_owner.id,
    'userId', v_owner.user_id,
    'isActive', false
  );
  perform app.platform_audit(
    p_tenant_id, v_actor, 'staff.owner_deactivated', 'staff', v_owner.id,
    jsonb_build_object('is_active', true, 'user_id', v_owner.user_id),
    jsonb_build_object('is_active', false, 'user_id', v_owner.user_id),
    null, p_request_key,
    jsonb_build_object(
      'command', 'deactivate_gym_owner',
      'actorUserId', v_actor::text,
      'request', v_request,
      'result', v_result
    )
  );
  return v_result;
end
$fn$;

alter function public.deactivate_gym_owner(uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function public.deactivate_gym_owner(uuid,uuid,uuid,uuid)
  from public, anon, service_role;
grant execute on function public.deactivate_gym_owner(uuid,uuid,uuid,uuid)
  to authenticated;
