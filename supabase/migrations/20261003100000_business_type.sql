-- BIZ-001..008: vocabulary only; existing tenancy and commercial behavior retained.
create type public.business_type as enum ('gym', 'dance', 'yoga', 'martial_arts', 'studio');
alter table public.organizations
  add column business_type public.business_type not null default 'gym';

create or replace function app.enforce_organization_commercial()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  v_commercial boolean;
  v_readiness jsonb;
  v_trusted boolean;
  v_business_command boolean := false;
begin
  if tg_op = 'INSERT'
     and current_user = 'authenticated'
     and app.current_tenant_id() is not null
     and new.id is distinct from app.current_tenant_id() then
    raise exception 'Not permitted'
      using errcode = '42501', detail = 'not_permitted';
  end if;

  if tg_op = 'UPDATE' then
    v_business_command := current_user = 'postgres' and auth.uid() is not null
      and new.business_type is distinct from old.business_type
      and (to_jsonb(new) - 'business_type' - 'updated_at')
        = (to_jsonb(old) - 'business_type' - 'updated_at');
  end if;

  if current_user = 'postgres' then
    if auth.uid() is not null and not v_business_command then
      perform app.require_platform_super_admin();
    end if;
    v_trusted := true;
  elsif current_user = 'service_role' and auth.uid() is null then
    v_trusted := true;
  else
    v_trusted := false;
  end if;

  if tg_op = 'INSERT' then
    if not v_trusted then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
    if btrim(new.name) = ''
       or not exists (
         select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone
       )
       or new.currency <> 'INR' then
      raise exception 'Invalid platform input'
        using errcode = '22023', detail = 'invalid_platform_input';
    end if;
    return new;
  end if;

  if new.id is distinct from old.id
     or new.gym_code is distinct from old.gym_code
     or new.created_at is distinct from old.created_at then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.name is distinct from old.name and btrim(new.name) = '' then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.timezone is distinct from old.timezone
     and not exists (
       select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone
     ) then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.currency is distinct from old.currency and new.currency <> 'INR' then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;

  if new.business_type is distinct from old.business_type
     and current_user in ('authenticated','anon') then
    raise exception 'Change business type with its audited command'
      using errcode = '42501', detail = 'business_type_command_required';
  end if;

  v_commercial := new.status is distinct from old.status
    or new.tier is distinct from old.tier
    or new.trial_ends_at is distinct from old.trial_ends_at
    or new.activated_at is distinct from old.activated_at;
  if v_commercial and not v_trusted then
    raise exception 'Platform commercial write required'
      using errcode = 'GL049', detail = 'platform_commercial_write_required';
  end if;
  if new.status is distinct from old.status
     and not app.organization_transition_allowed(old.status, new.status) then
    raise exception 'Invalid organization transition'
      using errcode = 'GL050', detail = 'invalid_organization_transition';
  end if;
  if new.status is distinct from old.status
     and new.status = 'active'::public.organization_status then
    v_readiness := app.gym_readiness(new.id);
    if not coalesce((v_readiness ->> 'settingsComplete')::boolean, false) then
      raise exception 'Organization not ready'
        using errcode = 'GL051',
          detail = jsonb_build_object(
            'missingSettings',
            coalesce(v_readiness -> 'missingSettings', '[]'::jsonb)
          )::text;
    end if;
    if old.activated_at is null then
      new.activated_at := clock_timestamp();
    elsif new.activated_at is distinct from old.activated_at then
      raise exception 'Invalid platform input'
        using errcode = '22023', detail = 'invalid_platform_input';
    end if;
  elsif new.activated_at is distinct from old.activated_at then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.status is distinct from old.status
     and old.status = 'pending_approval'::public.organization_status
     and new.status = 'trial'::public.organization_status then
    new.trial_ends_at := (
      (
        (old.created_at at time zone old.timezone)::date
        + (app.platform_onboarding_defaults() ->> 'trialDays')::integer
      )::timestamp at time zone old.timezone
    );
  elsif new.trial_ends_at is distinct from old.trial_ends_at then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  return new;
end
$fn$;

create function app.business_type_audit(
  p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text,
  p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb
) returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_action is distinct from 'organization.business_type_changed' then
    raise exception 'Invalid audit action' using errcode = '22023';
  end if;
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after
  ) values (
    p_tenant_id, p_actor, p_role, p_action, p_record_type, p_record_id, p_before, p_after
  );
end
$fn$;

create function public.set_business_type(p_business_type public.business_type)
returns table (
  business_type public.business_type,
  previous_business_type public.business_type,
  changed boolean
)
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_previous public.business_type;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  if p_business_type is null then
    raise exception 'Business type required' using errcode = '22023';
  end if;
  select o.business_type into v_previous from public.organizations o
    where o.id = v_actor.tenant_id for update;
  if not found then
    raise exception 'Organization unavailable' using errcode = '42501';
  end if;
  if v_previous = p_business_type then
    return query select p_business_type, v_previous, false;
    return;
  end if;
  update public.organizations o set business_type = p_business_type
    where o.id = v_actor.tenant_id;
  perform app.business_type_audit(
    v_actor.tenant_id, v_actor.user_id, v_actor.role,
    'organization.business_type_changed', 'organization', v_actor.tenant_id,
    jsonb_build_object('business_type', v_previous),
    jsonb_build_object('business_type', p_business_type)
  );
  return query select p_business_type, v_previous, true;
end
$fn$;

create function public.set_gym_business_type(
  p_tenant_id uuid, p_expected_business_type public.business_type,
  p_business_type public.business_type, p_request_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor uuid := app.require_platform_super_admin();
  v_org public.organizations%rowtype;
  v_request jsonb;
  v_replay jsonb;
  v_result jsonb;
begin
  if p_tenant_id is null or p_expected_business_type is null
     or p_business_type is null or p_request_key is null then
    raise exception 'Invalid platform input'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  v_request := jsonb_build_object(
    'expectedBusinessType', p_expected_business_type, 'businessType', p_business_type
  );
  select o.* into v_org from public.organizations o
    where o.id = p_tenant_id for update;
  if not found then raise exception 'Not found' using errcode = 'P0002'; end if;
  v_replay := app.platform_request_replay(
    p_tenant_id, p_request_key, v_actor, 'set_gym_business_type', v_request
  );
  if v_replay is not null then return v_replay; end if;
  if v_org.business_type is distinct from p_expected_business_type then
    raise exception 'Stale platform state'
      using errcode = '40001', detail = 'stale_platform_state';
  end if;
  v_result := jsonb_build_object('tenantId', p_tenant_id, 'businessType', p_business_type);
  if v_org.business_type is not distinct from p_business_type then return v_result; end if;
  update public.organizations o set business_type = p_business_type where o.id = p_tenant_id;
  perform app.platform_audit(
    p_tenant_id, v_actor, 'organization.business_type_changed', 'organization', p_tenant_id,
    jsonb_build_object('business_type', v_org.business_type),
    jsonb_build_object('business_type', p_business_type), null, p_request_key,
    jsonb_build_object('command', 'set_gym_business_type', 'actorUserId', v_actor::text,
      'request', v_request, 'result', v_result)
  );
  return v_result;
end
$fn$;

alter function app.business_type_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb) owner to postgres;
alter function public.set_business_type(public.business_type) owner to postgres;
alter function public.set_gym_business_type(uuid, public.business_type, public.business_type, uuid) owner to postgres;
revoke all on function app.business_type_audit(uuid, uuid, public.app_role, text, text, uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.set_business_type(public.business_type),
  public.set_gym_business_type(uuid, public.business_type, public.business_type, uuid)
  from public, anon, service_role;
grant execute on function public.set_business_type(public.business_type),
  public.set_gym_business_type(uuid, public.business_type, public.business_type, uuid)
  to authenticated;
