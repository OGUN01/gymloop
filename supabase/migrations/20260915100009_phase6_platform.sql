-- Phase 6 platform control: OPS-002/003, ONB-001--005 and NAV-006/008.
-- This migration deliberately consumes the readiness/metrics and communications
-- helpers from 20260915100007/8; it does not recreate their formulas.

-- Canonical commercial vocabulary, with ADR-115's deliberately narrow legacy repair.
create type public.plan_tier as enum ('basic', 'growth', 'pro');

alter table public.audit_log
  add column request_key uuid,
  add column request_facts jsonb,
  add constraint audit_log_request_evidence_chk check (
    (request_key is null and request_facts is null)
    or (request_key is not null and tenant_id is not null and jsonb_typeof(request_facts) = 'object')
  );

create unique index audit_log_tenant_id_request_key_key
  on public.audit_log (tenant_id, request_key)
  where request_key is not null;

do $block$
declare
  v_bad text;
begin
  select o.tier into v_bad
    from public.organizations o
   where o.tier is not null
     and o.tier not in ('basic', 'growth', 'pro', 'tier_2')
   limit 1;
  if v_bad is not null then
    raise exception 'Invalid legacy organization tier requires explicit repair'
      using errcode = '22023', detail = 'invalid_platform_input';
  end if;

  if exists (
    select 1 from public.organizations o
     where o.id = '00000001-0000-4000-8000-000000000001'::uuid
       and o.gym_code = 'IRNBX1' and o.tier = 'tier_2'
  ) then
    update public.organizations
       set tier = 'growth'
     where id = '00000001-0000-4000-8000-000000000001'::uuid
       and gym_code = 'IRNBX1' and tier = 'tier_2';
    insert into public.audit_log (tenant_id, action, record_type, record_id, before, after, reason)
    values (
      '00000001-0000-4000-8000-000000000001'::uuid,
      'organization.tier_migrated', 'organization', '00000001-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object('tier', 'tier_2'), jsonb_build_object('tier', 'growth'),
      'ADR-115 guarded demo tier correction'
    );
  end if;
end
$block$;

alter table public.organizations
  alter column tier type public.plan_tier using tier::public.plan_tier;

-- A complete, live platform shape is required by every public platform mutation.
create function app.require_platform_super_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
begin
  if v_user is null then
    raise exception 'Not signed in' using errcode = '42501', detail = 'not_signed_in';
  end if;
  if app.current_app_role() is distinct from 'super_admin'
     or v_claims ? 'tenant_id' and v_claims -> 'tenant_id' <> 'null'::jsonb
     or v_claims ? 'staff_id' and v_claims -> 'staff_id' <> 'null'::jsonb
     or v_claims ? 'member_id' and v_claims -> 'member_id' <> 'null'::jsonb
     or v_claims ? 'impersonation_session_id' and v_claims -> 'impersonation_session_id' <> 'null'::jsonb
     or not exists (
       select 1 from public.platform_users pu
        where pu.user_id = v_user and pu.role = 'super_admin'::public.app_role and pu.is_active
     ) then
    raise exception 'Not permitted' using errcode = '42501', detail = 'not_permitted';
  end if;
  return v_user;
end
$fn$;

-- Read-only invoker counterpart for the two preview RPCs. It is deliberately
-- callable by authenticated: it performs no elevated write or Auth lookup, and
-- its complete-identity check is the capability boundary those RPCs need.
create function app.assert_platform_super_admin()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
begin
  if v_user is null then
    raise exception 'Not signed in' using errcode = '42501', detail = 'not_signed_in';
  end if;
  if app.current_app_role() is distinct from 'super_admin'
     or v_claims ? 'tenant_id' and v_claims -> 'tenant_id' <> 'null'::jsonb
     or v_claims ? 'staff_id' and v_claims -> 'staff_id' <> 'null'::jsonb
     or v_claims ? 'member_id' and v_claims -> 'member_id' <> 'null'::jsonb
     or v_claims ? 'impersonation_session_id' and v_claims -> 'impersonation_session_id' <> 'null'::jsonb
     or not exists (
       select 1 from public.platform_users pu
        where pu.user_id = v_user and pu.role = 'super_admin'::public.app_role and pu.is_active
     ) then
    raise exception 'Not permitted' using errcode = '42501', detail = 'not_permitted';
  end if;
  return v_user;
end
$fn$;

create function app.organization_transition_allowed(
  p_from public.organization_status,
  p_to public.organization_status
) returns boolean
language sql immutable security invoker set search_path = '' as $fn$
  select p_from = p_to or (p_from, p_to) in (
    ('pending_approval'::public.organization_status, 'trial'::public.organization_status),
    ('pending_approval'::public.organization_status, 'active'::public.organization_status),
    ('trial'::public.organization_status, 'active'::public.organization_status),
    ('trial'::public.organization_status, 'closed'::public.organization_status),
    ('active'::public.organization_status, 'suspended'::public.organization_status),
    ('active'::public.organization_status, 'closed'::public.organization_status),
    ('suspended'::public.organization_status, 'active'::public.organization_status),
    ('suspended'::public.organization_status, 'closed'::public.organization_status)
  )
$fn$;

create function app.impersonation_max_ttl()
returns interval language sql immutable security invoker set search_path = '' as $fn$
  select interval '2 hours'
$fn$;

alter table public.impersonation_sessions
  drop constraint impersonation_sessions_ttl_chk,
  add constraint impersonation_sessions_ttl_chk
    check (expires_at <= started_at + app.impersonation_max_ttl());

create function app.organization_result(p_tenant_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'tenantId', o.id, 'name', o.name, 'gymCode', o.gym_code, 'status', o.status,
    'tier', o.tier, 'timezone', o.timezone, 'currency', o.currency,
    'trialEndsAt', o.trial_ends_at, 'activatedAt', o.activated_at
  ) from public.organizations o where o.id = p_tenant_id
$fn$;

create function app.platform_audit(
  p_tenant_id uuid, p_actor uuid, p_action text, p_record_type text, p_record_id uuid,
  p_before jsonb, p_after jsonb, p_reason text, p_request_key uuid, p_request_facts jsonb
) returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id, action, record_type,
    record_id, before, after, reason, request_key, request_facts
  ) values (
    p_tenant_id, p_actor, 'super_admin'::public.app_role, null, p_action, p_record_type,
    p_record_id, p_before, p_after, p_reason, p_request_key, p_request_facts
  );
end
$fn$;

-- The commercial invariant is deliberately INVOKER: direct authenticated writes are
-- refused, while the narrow postgres-owned commands retain their verified authority.
create function app.enforce_organization_commercial()
returns trigger language plpgsql security invoker set search_path = '' as $fn$
declare
  v_commercial boolean;
  v_readiness jsonb;
  v_trusted boolean;
begin
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
      raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
    if btrim(new.name) = '' or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone)
       or new.currency <> 'INR' then
      raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
    end if;
    return new;
  end if;

  if new.id is distinct from old.id or new.gym_code is distinct from old.gym_code or new.created_at is distinct from old.created_at then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.name is distinct from old.name and btrim(new.name) = '' then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.timezone is distinct from old.timezone
     and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone) then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.currency is distinct from old.currency and new.currency <> 'INR' then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  v_commercial := new.status is distinct from old.status
    or new.tier is distinct from old.tier
    or new.trial_ends_at is distinct from old.trial_ends_at
    or new.activated_at is distinct from old.activated_at;
  if v_commercial and not v_trusted then
    raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
  end if;
  if new.status is distinct from old.status
     and not app.organization_transition_allowed(old.status, new.status) then
    raise exception 'Invalid organization transition' using errcode = 'GL050', detail = 'invalid_organization_transition';
  end if;
  if new.status is distinct from old.status and new.status = 'active'::public.organization_status then
    v_readiness := app.gym_readiness(new.id);
    if not coalesce((v_readiness ->> 'settingsComplete')::boolean, false) then
      raise exception 'Organization not ready'
        using errcode = 'GL051',
          detail = jsonb_build_object('missingSettings', coalesce(v_readiness -> 'missingSettings', '[]'::jsonb))::text;
    end if;
    if old.activated_at is null then
      new.activated_at := clock_timestamp();
    elsif new.activated_at is distinct from old.activated_at then
      raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
    end if;
  elsif new.activated_at is distinct from old.activated_at then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if new.status is distinct from old.status and old.status = 'pending_approval'::public.organization_status
     and new.status = 'trial'::public.organization_status then
    new.trial_ends_at := (((old.created_at at time zone old.timezone)::date
      + (app.platform_onboarding_defaults() ->> 'trialDays')::integer)::timestamp at time zone old.timezone);
  elsif new.trial_ends_at is distinct from old.trial_ends_at then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  return new;
end
$fn$;

create trigger organizations_commercial_invariant
before insert or update on public.organizations
for each row execute function app.enforce_organization_commercial();

create function app.enforce_staff_auth_binding()
returns trigger language plpgsql security invoker set search_path = '' as $fn$
declare v_trusted boolean;
begin
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
    if new.user_id is not null and not v_trusted then
      raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if (new.user_id is distinct from old.user_id
      or (old.user_id is not null and (new.role = 'gym_owner'::public.app_role) is distinct from (old.role = 'gym_owner'::public.app_role)))
     and not v_trusted then
    raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
  end if;
  if auth.uid() is not null and new.user_id is distinct from old.user_id then
    if old.role <> 'gym_owner'::public.app_role or new.role <> 'gym_owner'::public.app_role
       or not old.is_active or not new.is_active or new.user_id is null
       or not exists (select 1 from auth.users u where u.id = new.user_id)
       or exists (select 1 from public.platform_users pu where pu.user_id = new.user_id)
       or exists (select 1 from public.staff s where s.tenant_id = new.tenant_id and s.user_id = new.user_id and s.id <> new.id) then
      raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;
  if auth.uid() is not null and old.user_id is not null
     and (new.role is distinct from old.role or new.is_active is distinct from old.is_active) then
    raise exception 'Platform commercial write required' using errcode = 'GL049', detail = 'platform_commercial_write_required';
  end if;
  return new;
end
$fn$;

create trigger staff_auth_binding_invariant
before insert or update on public.staff
for each row execute function app.enforce_staff_auth_binding();

create function app.revoke_sessions_on_staff_binding_change()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  delete from auth.sessions s
   where s.user_id in (old.user_id, new.user_id) and s.user_id is not null;
  return null;
end
$fn$;

create trigger staff_auth_binding_session_revoke
after update of user_id on public.staff
for each row when (old.user_id is distinct from new.user_id)
execute function app.revoke_sessions_on_staff_binding_change();

create function app.revoke_sessions_on_organization_status_change()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  delete from auth.sessions s
   where s.user_id in (
     select st.user_id from public.staff st where st.tenant_id = new.id and st.user_id is not null
     union
     select m.user_id from public.members m where m.tenant_id = new.id and m.user_id is not null
   );
  return null;
end
$fn$;

create trigger organizations_status_session_revoke
after update of status on public.organizations
for each row when (old.status is distinct from new.status and new.status in ('suspended'::public.organization_status, 'closed'::public.organization_status))
execute function app.revoke_sessions_on_organization_status_change();

-- Generated from GYM_PRESET_SETTINGS in packages/shared/src/config/constants.ts.
create function app.platform_onboarding_defaults()
returns jsonb language sql immutable security invoker set search_path = '' as $fn$
  select jsonb_build_object(
    'trialDays',
    -- GENERATED_TRIAL_DAYS_START
14
    -- GENERATED_TRIAL_DAYS_END
    , 'gymCodeLength',
    -- GENERATED_GYM_CODE_LENGTH_START
6
    -- GENERATED_GYM_CODE_LENGTH_END
    ,
    'presets', jsonb_build_object(
    -- GENERATED_GYM_PRESET_SETTINGS_START
      'neighbourhood_gym', jsonb_build_object('noShowThresholdDays', 7, 'streakRule', 'visit_streak', 'weeklyGoal', 3, 'maxFreezeDays', 30, 'pauseApproverRole', 'gym_owner'),
      'premium_studio', jsonb_build_object('noShowThresholdDays', 5, 'streakRule', 'weekly_goal', 'weeklyGoal', 3, 'maxFreezeDays', 30, 'pauseApproverRole', 'gym_owner'),
      'functional_box', jsonb_build_object('noShowThresholdDays', 3, 'streakRule', 'weekly_goal', 'weeklyGoal', 4, 'maxFreezeDays', 14, 'pauseApproverRole', 'gym_owner')
    -- GENERATED_GYM_PRESET_SETTINGS_END
    )
  )
$fn$;

create function app.platform_request_replay(p_tenant_id uuid, p_key uuid, p_actor uuid, p_command text, p_request jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_facts jsonb;
begin
  select a.request_facts into v_facts from public.audit_log a
   where a.tenant_id = p_tenant_id and a.request_key = p_key;
  if not found then return null; end if;
  if v_facts ->> 'command' = p_command
     and v_facts ->> 'actorUserId' = p_actor::text
     and v_facts -> 'request' = p_request then
    return v_facts -> 'result';
  end if;
  raise exception 'Idempotency conflict' using errcode = 'GL068', detail = 'idempotency_conflict';
end
$fn$;

create function public.onboard_gym(
  p_request_key uuid, p_name text, p_timezone text, p_currency text, p_preset public.gym_preset,
  p_branch_name text, p_owner_name text, p_owner_email text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_actor uuid := app.require_platform_super_admin(); v_name text := btrim(p_name); v_timezone text := btrim(p_timezone);
  v_currency text := btrim(p_currency); v_branch text := btrim(p_branch_name); v_owner text := btrim(p_owner_name);
  v_email text := nullif(lower(btrim(p_owner_email)), ''); v_created timestamptz := clock_timestamp();
  v_trial_end timestamptz; v_code text; v_branch_id uuid; v_owner_id uuid; v_result jsonb; v_request jsonb; v_constraint text;
begin
  if p_request_key is null or p_preset is null or p_name is null or p_timezone is null or p_currency is null
     or p_branch_name is null or p_owner_name is null or v_name = '' or v_timezone = '' or v_currency = '' or v_branch = '' or v_owner = '' then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  if v_currency <> 'INR' or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Invalid platform input' using errcode = '22023', detail = 'invalid_platform_input';
  end if;
  v_request := jsonb_build_object('name',v_name,'timezone',v_timezone,'currency',v_currency,'preset',p_preset,'branchName',v_branch,'ownerName',v_owner,'ownerEmail',v_email);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_key::text, 0));
  if exists(select 1 from public.organizations o where o.id=p_request_key) then
    v_result := app.platform_request_replay(p_request_key,p_request_key,v_actor,'onboard_gym',v_request);
    if v_result is not null then return v_result; end if;
    raise exception 'Idempotency conflict' using errcode='GL068', detail='idempotency_conflict';
  end if;
  v_trial_end := (((v_created at time zone v_timezone)::date + (app.platform_onboarding_defaults()->>'trialDays')::integer)::timestamp at time zone v_timezone);
  loop
    v_code := upper(substring(gen_random_uuid()::text from 1 for (app.platform_onboarding_defaults()->>'gymCodeLength')::integer));
    begin
      insert into public.organizations (id,name,gym_code,status,timezone,currency,created_at,trial_ends_at)
      values (p_request_key,v_name,v_code,'pending_approval',v_timezone,v_currency,v_created,v_trial_end);
      exit;
    exception when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint <> 'organizations_gym_code_key' then raise; end if;
    end;
  end loop;
  insert into public.organization_settings (tenant_id,preset,no_show_threshold_days,streak_rule_type,weekly_goal_default,max_freeze_days_per_year,pause_approver_role)
  values (p_request_key,p_preset,
    (app.platform_onboarding_defaults()->'presets'->p_preset::text->>'noShowThresholdDays')::smallint,
    (app.platform_onboarding_defaults()->'presets'->p_preset::text->>'streakRule')::public.streak_rule_type,
    (app.platform_onboarding_defaults()->'presets'->p_preset::text->>'weeklyGoal')::smallint,
    (app.platform_onboarding_defaults()->'presets'->p_preset::text->>'maxFreezeDays')::smallint,
    (app.platform_onboarding_defaults()->'presets'->p_preset::text->>'pauseApproverRole')::public.app_role);
  insert into public.branches (tenant_id,name,is_default) values (p_request_key,v_branch,true) returning id into v_branch_id;
  insert into public.messaging_wallets (tenant_id,balance_credits) values (p_request_key,0);
  insert into public.staff (tenant_id,user_id,branch_id,role,full_name,email,is_active)
  values (p_request_key,null,null,'gym_owner',v_owner,v_email,true) returning id into v_owner_id;
  update public.organizations set status='trial'::public.organization_status where id=p_request_key;
  v_result := jsonb_build_object('organization',app.organization_result(p_request_key),'branchId',v_branch_id,'ownerStaffId',v_owner_id,'ownerAccessPending',true);
  perform app.platform_audit(p_request_key,v_actor,'organization.onboarded','organization',p_request_key,null,
    jsonb_build_object('organization',app.organization_result(p_request_key),'branch_id',v_branch_id,'owner_staff_id',v_owner_id,'preset',p_preset,'wallet_balance_credits','0'),null,p_request_key,
    jsonb_build_object('command','onboard_gym','actorUserId',v_actor::text,'request',v_request,'result',v_result));
  return v_result;
end
$fn$;

create function public.set_gym_status(p_tenant_id uuid, p_expected_status public.organization_status, p_status public.organization_status, p_reason text, p_request_key uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor uuid:=app.require_platform_super_admin(); v_org public.organizations%rowtype; v_changed public.organizations%rowtype; v_reason text:=nullif(btrim(p_reason),''); v_request jsonb; v_replay jsonb; v_ready jsonb; v_result jsonb; v_before jsonb;
begin
  if p_tenant_id is null or p_expected_status is null or p_status is null or p_request_key is null then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input'; end if;
  v_request:=jsonb_build_object('expectedStatus',p_expected_status,'status',p_status,'reason',v_reason);
  select * into v_org from public.organizations where id=p_tenant_id for update;
  if not found then raise exception 'Not found' using errcode='P0002'; end if;
  v_replay:=app.platform_request_replay(p_tenant_id,p_request_key,v_actor,'set_gym_status',v_request); if v_replay is not null then return v_replay; end if;
  if v_org.status is distinct from p_expected_status then raise exception 'Stale platform state' using errcode='40001',detail='stale_platform_state'; end if;
  if v_org.status = p_status then return jsonb_build_object('organization',app.organization_result(p_tenant_id),'readiness',app.gym_readiness(p_tenant_id)); end if;
  if (p_status in ('suspended'::public.organization_status,'closed'::public.organization_status) or (v_org.status='suspended'::public.organization_status and p_status='active'::public.organization_status)) and v_reason is null then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input'; end if;
  if not app.organization_transition_allowed(v_org.status,p_status) then raise exception 'Invalid organization transition' using errcode='GL050',detail='invalid_organization_transition'; end if;
  v_before:=jsonb_build_object('status',v_org.status,'trial_ends_at',v_org.trial_ends_at,'activated_at',v_org.activated_at);
  with readiness as (select app.gym_readiness(p_tenant_id) as value), changed as (
    update public.organizations o
       set status=p_status,
           trial_ends_at=case when v_org.status='pending_approval'::public.organization_status and p_status='trial'::public.organization_status then (((o.created_at at time zone o.timezone)::date + (app.platform_onboarding_defaults()->>'trialDays')::integer)::timestamp at time zone o.timezone) else o.trial_ends_at end,
           activated_at=case when p_status='active'::public.organization_status and o.activated_at is null then clock_timestamp() else o.activated_at end
      from readiness r
     where o.id=p_tenant_id
     returning o.*, r.value
  ) select c.id,c.name,c.gym_code,c.status,c.tier,c.trial_ends_at,c.activated_at,c.timezone,c.currency,c.created_at,c.updated_at,c.value
      into v_changed.id,v_changed.name,v_changed.gym_code,v_changed.status,v_changed.tier,v_changed.trial_ends_at,v_changed.activated_at,v_changed.timezone,v_changed.currency,v_changed.created_at,v_changed.updated_at,v_ready
      from changed c;
  if not found then raise exception 'Not found' using errcode='P0002'; end if;
  v_result:=jsonb_build_object('organization',jsonb_build_object('tenantId',v_changed.id,'name',v_changed.name,'gymCode',v_changed.gym_code,'status',v_changed.status,'tier',v_changed.tier,'timezone',v_changed.timezone,'currency',v_changed.currency,'trialEndsAt',v_changed.trial_ends_at,'activatedAt',v_changed.activated_at),'readiness',v_ready);
  perform app.platform_audit(p_tenant_id,v_actor,'organization.status_changed','organization',p_tenant_id,v_before,jsonb_build_object('status',v_changed.status,'trial_ends_at',v_changed.trial_ends_at,'activated_at',v_changed.activated_at),v_reason,p_request_key,jsonb_build_object('command','set_gym_status','actorUserId',v_actor::text,'request',v_request,'result',v_result));
  return v_result;
end
$fn$;

create function public.set_gym_tier(p_tenant_id uuid,p_expected_tier public.plan_tier,p_tier public.plan_tier,p_request_key uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid:=app.require_platform_super_admin();v_org public.organizations%rowtype;v_request jsonb;v_replay jsonb;v_result jsonb;
begin
 if p_tenant_id is null or p_request_key is null then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input';end if;
 v_request:=jsonb_build_object('expectedTier',p_expected_tier,'tier',p_tier);select * into v_org from public.organizations where id=p_tenant_id for update;if not found then raise exception 'Not found' using errcode='P0002';end if;
 v_replay:=app.platform_request_replay(p_tenant_id,p_request_key,v_actor,'set_gym_tier',v_request);if v_replay is not null then return v_replay;end if;
 if v_org.tier is distinct from p_expected_tier then raise exception 'Stale platform state' using errcode='40001',detail='stale_platform_state';end if;
 v_result:=jsonb_build_object('tenantId',p_tenant_id,'tier',p_tier);if v_org.tier is not distinct from p_tier then return v_result;end if;
 update public.organizations set tier=p_tier where id=p_tenant_id;
 perform app.platform_audit(p_tenant_id,v_actor,'organization.tier_changed','organization',p_tenant_id,jsonb_build_object('tier',v_org.tier),jsonb_build_object('tier',p_tier),null,p_request_key,jsonb_build_object('command','set_gym_tier','actorUserId',v_actor::text,'request',v_request,'result',v_result));return v_result;
end
$fn$;

create function public.link_gym_owner(p_tenant_id uuid,p_owner_staff_id uuid,p_expected_user_id uuid,p_owner_email text,p_request_key uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid:=app.require_platform_super_admin();v_org uuid;v_staff public.staff%rowtype;v_user auth.users%rowtype;v_email text:=nullif(lower(btrim(p_owner_email)), '');v_request jsonb;v_replay jsonb;v_result jsonb;v_old_user uuid;
begin
 if p_tenant_id is null or p_owner_staff_id is null or p_request_key is null or v_email is null then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input';end if;
 v_request:=jsonb_build_object('ownerStaffId',p_owner_staff_id,'expectedUserId',p_expected_user_id,'ownerEmail',v_email);
 select id into v_org from public.organizations where id=p_tenant_id for update;if not found then raise exception 'Not found' using errcode='P0002';end if;
 select * into v_staff from public.staff where id=p_owner_staff_id and tenant_id=p_tenant_id and role='gym_owner'::public.app_role and is_active for update;if not found then raise exception 'Not found' using errcode='P0002';end if;
 v_replay:=app.platform_request_replay(p_tenant_id,p_request_key,v_actor,'link_gym_owner',v_request);if v_replay is not null then return v_replay;end if;
 if v_staff.user_id is distinct from p_expected_user_id then raise exception 'Stale platform state' using errcode='40001',detail='stale_platform_state';end if;
 select * into v_user from auth.users where lower(email)=v_email for update;
 if not found or (select count(*) from auth.users where lower(email)=v_email)<>1 or exists(select 1 from public.platform_users pu where pu.user_id=v_user.id) or exists(select 1 from public.staff s where s.tenant_id=p_tenant_id and s.user_id=v_user.id and s.id<>p_owner_staff_id) then raise exception 'Owner account unavailable' using errcode='22023',detail='owner_account_unavailable';end if;
 if v_staff.user_id=v_user.id then return jsonb_build_object('tenantId',p_tenant_id,'ownerStaffId',p_owner_staff_id,'userId',v_staff.user_id,'ownerAccessPending',false);end if;
 v_old_user:=v_staff.user_id;
 update public.staff set user_id=v_user.id,email=v_email where id=p_owner_staff_id and tenant_id=p_tenant_id;
 update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('active_tenant_id',p_tenant_id::text) where id=v_user.id;
 v_result:=jsonb_build_object('tenantId',p_tenant_id,'ownerStaffId',p_owner_staff_id,'userId',v_user.id,'ownerAccessPending',false);
 perform app.platform_audit(p_tenant_id,v_actor,'staff.owner_linked','staff',p_owner_staff_id,jsonb_build_object('user_id',v_old_user,'email',v_staff.email),jsonb_build_object('user_id',v_user.id,'email',v_email,'preferred_tenant_id',p_tenant_id),null,p_request_key,jsonb_build_object('command','link_gym_owner','actorUserId',v_actor::text,'request',v_request,'result',v_result));return v_result;
end
$fn$;

-- Hook eligibility is deliberately evaluated in the lookup query, retaining class
-- precedence: a matching but ineligible staff class cannot fall through to member.
create or replace function app.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_user_id uuid;v_claims jsonb;v_requested text;v_role public.app_role;v_tenant_id uuid;v_member_id uuid;v_staff_id uuid;v_session_id uuid;v_exists boolean;v_active boolean;
begin
 v_claims:=(case when jsonb_typeof(event->'claims')='object' then event->'claims' else '{}'::jsonb end)-array['app_role','tenant_id','staff_id','member_id','impersonation_session_id'];event:=jsonb_set(event,'{claims}',v_claims);v_user_id:=nullif(event->>'user_id','')::uuid;if v_user_id is null then return event;end if;
 select true,pu.is_active,pu.role into v_exists,v_active,v_role from public.platform_users pu where pu.user_id=v_user_id;
 if v_exists then if not v_active then return event;end if;if v_role='super_admin'::public.app_role then select i.id,i.tenant_id into v_session_id,v_tenant_id from public.impersonation_sessions i where i.actor_user_id=v_user_id and app.impersonation_is_live(i.ended_at,i.expires_at);if v_session_id is not null then return jsonb_set(event,'{claims}',v_claims||jsonb_build_object('app_role','gym_owner','tenant_id',v_tenant_id,'impersonation_session_id',v_session_id));end if;end if;return jsonb_set(event,'{claims}',v_claims||jsonb_build_object('app_role',v_role::text));end if;
 select u.raw_app_meta_data->>'active_tenant_id' into v_requested from auth.users u where u.id=v_user_id;
 select true into v_exists from public.staff s where s.user_id=v_user_id limit 1;if v_exists then
   select s.id,s.tenant_id,s.role into v_staff_id,v_tenant_id,v_role from public.staff s join public.organizations o on o.id=s.tenant_id where s.user_id=v_user_id and s.is_active and s.tenant_id::text=v_requested and (o.status='active'::public.organization_status or(o.status='trial'::public.organization_status and o.trial_ends_at>statement_timestamp()));
   if v_staff_id is null then select s.id,s.tenant_id,s.role into v_staff_id,v_tenant_id,v_role from public.staff s join public.organizations o on o.id=s.tenant_id where s.user_id=v_user_id and s.is_active and (o.status='active'::public.organization_status or(o.status='trial'::public.organization_status and o.trial_ends_at>statement_timestamp())) order by s.created_at,s.id limit 1;end if;
   if v_staff_id is null then return event;end if;return jsonb_set(event,'{claims}',v_claims||jsonb_build_object('app_role',v_role::text,'tenant_id',v_tenant_id,'staff_id',v_staff_id));
 end if;
 select true into v_exists from public.members m where m.user_id=v_user_id limit 1;if v_exists then
   select m.id,m.tenant_id into v_member_id,v_tenant_id from public.members m join public.organizations o on o.id=m.tenant_id where m.user_id=v_user_id and m.status not in ('cancelled'::public.member_status,'blocked'::public.member_status) and m.erased_at is null and m.tenant_id::text=v_requested and (o.status='active'::public.organization_status or(o.status='trial'::public.organization_status and o.trial_ends_at>statement_timestamp()));
   if v_member_id is null then select m.id,m.tenant_id into v_member_id,v_tenant_id from public.members m join public.organizations o on o.id=m.tenant_id where m.user_id=v_user_id and m.status not in ('cancelled'::public.member_status,'blocked'::public.member_status) and m.erased_at is null and (o.status='active'::public.organization_status or(o.status='trial'::public.organization_status and o.trial_ends_at>statement_timestamp())) order by m.created_at,m.id limit 1;end if;
   if v_member_id is null then return event;end if;return jsonb_set(event,'{claims}',v_claims||jsonb_build_object('app_role','member','tenant_id',v_tenant_id,'member_id',v_member_id));
 end if;return event;
exception when others then return event;
end
$fn$;

create function public.start_gym_preview(p_tenant_id uuid,p_reason text,p_request_key uuid)
returns jsonb language plpgsql volatile security invoker set search_path='' as $fn$
declare v_actor uuid:=app.assert_platform_super_admin();v_reason text:=nullif(btrim(p_reason),'');v_session public.impersonation_sessions%rowtype;v_started timestamptz:=transaction_timestamp();v_constraint text;
begin
 if p_tenant_id is null or p_request_key is null or v_reason is null then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input';end if;
 perform 1 from public.platform_users pu where pu.user_id=v_actor and pu.role='super_admin'::public.app_role and pu.is_active for update;
 if not found then raise exception 'Not permitted' using errcode='42501',detail='not_permitted';end if;
 select * into v_session from public.impersonation_sessions where id=p_request_key for update;
 if found then if v_session.actor_user_id=v_actor and v_session.tenant_id=p_tenant_id and v_session.reason=v_reason then return jsonb_build_object('sessionId',v_session.id,'tenantId',v_session.tenant_id,'startedAt',v_session.started_at,'expiresAt',v_session.expires_at);end if;raise exception 'Idempotency conflict' using errcode='GL068',detail='idempotency_conflict';end if;
 if not exists(select 1 from public.organizations o where o.id=p_tenant_id) then raise exception 'Not found' using errcode='P0002';end if;
 select * into v_session from public.impersonation_sessions where actor_user_id=v_actor and ended_at is null for update;if found then raise exception 'Preview already open' using errcode='23505',constraint='impersonation_sessions_actor_user_id_open_key',detail='preview_already_open';end if;
 begin
   insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,started_at,expires_at) values(p_request_key,p_tenant_id,v_actor,v_reason,v_started,v_started+app.impersonation_max_ttl()) returning * into v_session;
 exception when unique_violation then
   get stacked diagnostics v_constraint = constraint_name;
   select * into v_session from public.impersonation_sessions where id=p_request_key for update;
   if found then
     if v_session.actor_user_id=v_actor and v_session.tenant_id=p_tenant_id and v_session.reason=v_reason then
       return jsonb_build_object('sessionId',v_session.id,'tenantId',v_session.tenant_id,'startedAt',v_session.started_at,'expiresAt',v_session.expires_at);
     end if;
     raise exception 'Idempotency conflict' using errcode='GL068',detail='idempotency_conflict';
   end if;
   if v_constraint = 'impersonation_sessions_actor_user_id_open_key' then
     raise exception 'Preview already open' using errcode='23505',constraint='impersonation_sessions_actor_user_id_open_key',detail='preview_already_open';
   end if;
   raise;
 end;
 return jsonb_build_object('sessionId',v_session.id,'tenantId',v_session.tenant_id,'startedAt',v_session.started_at,'expiresAt',v_session.expires_at);
end
$fn$;

create function public.end_expired_gym_preview(p_session_id uuid)
returns jsonb language plpgsql volatile security invoker set search_path='' as $fn$
declare v_actor uuid:=app.assert_platform_super_admin();v_session public.impersonation_sessions%rowtype;
begin
 select * into v_session from public.impersonation_sessions where id=p_session_id and actor_user_id=v_actor for update;if not found then raise exception 'Not found' using errcode='P0002';end if;
 if v_session.ended_at is not null then return jsonb_build_object('sessionId',v_session.id,'endedAt',v_session.ended_at);end if;
 if v_session.expires_at>clock_timestamp() then raise exception 'Invalid platform input' using errcode='22023',detail='invalid_platform_input';end if;
 update public.impersonation_sessions set ended_at=clock_timestamp() where id=v_session.id returning * into v_session;
 return jsonb_build_object('sessionId',v_session.id,'endedAt',v_session.ended_at);
end
$fn$;

alter function app.require_platform_super_admin() owner to postgres;
alter function app.assert_platform_super_admin() owner to postgres;
alter function app.organization_result(uuid) owner to postgres;
alter function app.platform_audit(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid,jsonb) owner to postgres;
alter function app.platform_request_replay(uuid,uuid,uuid,text,jsonb) owner to postgres;
alter function app.platform_onboarding_defaults() owner to postgres;
alter function app.impersonation_max_ttl() owner to postgres;
alter function app.organization_transition_allowed(public.organization_status,public.organization_status) owner to postgres;
alter function public.onboard_gym(uuid,text,text,text,public.gym_preset,text,text,text) owner to postgres;
alter function public.set_gym_status(uuid,public.organization_status,public.organization_status,text,uuid) owner to postgres;
alter function public.set_gym_tier(uuid,public.plan_tier,public.plan_tier,uuid) owner to postgres;
alter function public.link_gym_owner(uuid,uuid,uuid,text,uuid) owner to postgres;
alter function public.start_gym_preview(uuid,text,uuid) owner to postgres;
alter function public.end_expired_gym_preview(uuid) owner to postgres;

revoke all on function app.require_platform_super_admin(),app.organization_result(uuid),app.platform_audit(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid,jsonb),app.platform_request_replay(uuid,uuid,uuid,text,jsonb),app.enforce_organization_commercial(),app.enforce_staff_auth_binding(),app.revoke_sessions_on_staff_binding_change(),app.revoke_sessions_on_organization_status_change(),app.platform_onboarding_defaults() from public,anon,authenticated,service_role;
revoke all on function app.assert_platform_super_admin() from public,anon,service_role;
grant execute on function app.assert_platform_super_admin() to authenticated;
revoke all on function app.custom_access_token_hook(jsonb) from public,anon,authenticated;
grant execute on function app.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke all on function app.organization_transition_allowed(public.organization_status,public.organization_status),app.impersonation_max_ttl() from public,anon;
grant execute on function app.organization_transition_allowed(public.organization_status,public.organization_status),app.impersonation_max_ttl() to authenticated;
revoke all on function public.onboard_gym(uuid,text,text,text,public.gym_preset,text,text,text),public.set_gym_status(uuid,public.organization_status,public.organization_status,text,uuid),public.set_gym_tier(uuid,public.plan_tier,public.plan_tier,uuid),public.link_gym_owner(uuid,uuid,uuid,text,uuid),public.start_gym_preview(uuid,text,uuid),public.end_expired_gym_preview(uuid) from public,anon,service_role;
grant execute on function public.onboard_gym(uuid,text,text,text,public.gym_preset,text,text,text),public.set_gym_status(uuid,public.organization_status,public.organization_status,text,uuid),public.set_gym_tier(uuid,public.plan_tier,public.plan_tier,uuid),public.link_gym_owner(uuid,uuid,uuid,text,uuid),public.start_gym_preview(uuid,text,uuid),public.end_expired_gym_preview(uuid) to authenticated;
