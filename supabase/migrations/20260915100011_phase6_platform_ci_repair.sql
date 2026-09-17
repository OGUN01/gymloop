-- Phase 6 platform CI repair.
--
-- Preserve the frozen platform command boundary while restoring two older
-- contracts: cross-tenant organization inserts fail at the tenancy boundary,
-- and ordinary staff edits remain available when they do not change the Auth
-- binding or move a linked row into/out of gym_owner.

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
begin
  if tg_op = 'INSERT'
     and current_user = 'authenticated'
     and app.current_tenant_id() is not null
     and new.id is distinct from app.current_tenant_id() then
    raise exception 'Not permitted'
      using errcode = '42501', detail = 'not_permitted';
  end if;

  if current_user = 'postgres' then
    if auth.uid() is not null then
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

create or replace function app.enforce_staff_auth_binding()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  v_protected boolean;
  v_trusted boolean := false;
begin
  if tg_op = 'INSERT' then
    v_protected := new.user_id is not null;
  else
    if new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id then
      raise exception 'Invalid platform input'
        using errcode = '22023', detail = 'invalid_platform_input';
    end if;
    v_protected := new.user_id is distinct from old.user_id
      or (
        old.user_id is not null
        and (new.role = 'gym_owner'::public.app_role)
          is distinct from (old.role = 'gym_owner'::public.app_role)
      );
  end if;

  if v_protected then
    if current_user = 'postgres' then
      if auth.uid() is not null then
        perform app.require_platform_super_admin();
      end if;
      v_trusted := true;
    elsif current_user = 'service_role' and auth.uid() is null then
      v_trusted := true;
    end if;

    if not v_trusted then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and auth.uid() is not null
     and new.user_id is distinct from old.user_id then
    if old.role <> 'gym_owner'::public.app_role
       or new.role <> 'gym_owner'::public.app_role
       or not old.is_active
       or not new.is_active
       or new.user_id is null
       or not exists (select 1 from auth.users u where u.id = new.user_id)
       or exists (
         select 1 from public.platform_users pu where pu.user_id = new.user_id
       )
       or exists (
         select 1
           from public.staff s
          where s.tenant_id = new.tenant_id
            and s.user_id = new.user_id
            and s.id <> new.id
       ) then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;
  return new;
end
$fn$;

