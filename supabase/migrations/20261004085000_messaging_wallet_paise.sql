-- Approved WSP-101..109 wallet unit conversion. CI supplies the transaction.
-- Same tables, complete locked baseline, exact arithmetic; no provider activation.
set local timezone = 'UTC';
lock table public.messaging_wallets in access exclusive mode;
lock table public.messaging_wallet_ledger in access exclusive mode;

do $cutover$
declare
  v_manifest jsonb;
  v_after jsonb;
  v_cutover timestamptz := clock_timestamp();
begin
  select jsonb_build_object(
    'wallets', coalesce((select jsonb_agg(jsonb_build_object(
      'tenant_id', w.tenant_id, 'balance_credits', w.balance_credits::text,
      'created_at', w.created_at, 'updated_at', w.updated_at
    ) order by w.tenant_id) from public.messaging_wallets w), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'tenant_id', l.tenant_id, 'delta_credits', l.delta_credits::text,
      'balance_after_credits', l.balance_after_credits::text, 'reason', l.reason,
      'notification_id', l.notification_id, 'request_key', l.request_key,
      'recorded_by_user_id', l.recorded_by_user_id, 'created_at', l.created_at
    ) order by l.tenant_id, l.id) from public.messaging_wallet_ledger l), '[]'::jsonb)
  ) into v_manifest;
  if encode(pg_catalog.sha256(pg_catalog.convert_to(v_manifest::text, 'UTF8')), 'hex')
       <> '79a7a86950098a93b9a2d0f78e9e0416beea077ea0bdc9308ae1e805df12cacb'
     or (select count(*) from public.messaging_wallets) <> 3
     or (select count(*) from public.messaging_wallets where balance_credits <> 0) <> 1
     or (select sum(balance_credits::numeric) from public.messaging_wallets) <> 4500
     or (select count(*) from public.messaging_wallet_ledger) <> 2
     or (select sum(delta_credits::numeric) from public.messaging_wallet_ledger) <> 4500 then
    raise exception 'Original wallet inventory changed; owner review required' using errcode = '23514';
  end if;
  if exists (select 1 from public.messaging_wallets w where w.balance_credits < 0
      or w.balance_credits::numeric <> (select coalesce(sum(l.delta_credits::numeric),0)
        from public.messaging_wallet_ledger l where l.tenant_id=w.tenant_id))
     or exists (select 1 from public.messaging_wallet_ledger l where l.delta_credits=0
       or not exists(select 1 from public.messaging_wallets w where w.tenant_id=l.tenant_id)) then
    raise exception 'Original per-tenant wallet equation is inconsistent' using errcode = '23514';
  end if;
  if exists (select 1 from (
      select balance_credits::numeric * 100 as value from public.messaging_wallets
      union all select delta_credits::numeric * 100 from public.messaging_wallet_ledger
      union all select balance_after_credits::numeric * 100 from public.messaging_wallet_ledger
        where balance_after_credits is not null
    ) amounts where value < -9223372036854775808::numeric or value > 9223372036854775807::numeric) then
    raise exception 'Original money cannot be converted within bigint bounds' using errcode = '23514';
  end if;

  alter table public.messaging_wallets rename column balance_credits to balance_paise;
  alter table public.messaging_wallet_ledger rename column delta_credits to delta_paise;
  alter table public.messaging_wallet_ledger rename column balance_after_credits to balance_after_paise;
  alter table public.messaging_wallets
    rename constraint messaging_wallets_balance_credits_chk to messaging_wallets_balance_paise_chk;
  alter table public.messaging_wallet_ledger
    rename constraint messaging_wallet_ledger_delta_credits_chk to messaging_wallet_ledger_delta_paise_chk;
  alter table public.messaging_wallet_ledger
    rename constraint messaging_wallet_ledger_balance_after_credits_chk to messaging_wallet_ledger_balance_after_paise_chk;
  alter table public.messaging_wallets
    add column currency text not null default 'INR' constraint messaging_wallets_currency_chk check(currency='INR'),
    add column original_balance_credits bigint,
    add column conversion_paise_per_credit bigint,
    add column conversion_currency text,
    add column conversion_approval_ref text,
    add column converted_at timestamptz;
  alter table public.messaging_wallet_ledger
    add column currency text not null default 'INR' constraint messaging_wallet_ledger_currency_chk check(currency='INR'),
    add column original_delta_credits bigint,
    add column original_balance_after_credits bigint,
    add column conversion_paise_per_credit bigint,
    add column conversion_currency text,
    add column conversion_approval_ref text,
    add column converted_at timestamptz;
  alter table public.messaging_wallets disable trigger messaging_wallets_touch_updated_at;
  update public.messaging_wallets set
    original_balance_credits=balance_paise, balance_paise=(balance_paise::numeric*100)::bigint,
    conversion_paise_per_credit=100, conversion_currency='INR', conversion_approval_ref='efff581', converted_at=v_cutover;
  update public.messaging_wallet_ledger set
    original_delta_credits=delta_paise, original_balance_after_credits=balance_after_paise,
    delta_paise=(delta_paise::numeric*100)::bigint,
    balance_after_paise=(balance_after_paise::numeric*100)::bigint,
    conversion_paise_per_credit=100, conversion_currency='INR', conversion_approval_ref='efff581', converted_at=v_cutover;
  alter table public.messaging_wallets enable trigger messaging_wallets_touch_updated_at;

  select jsonb_build_object(
    'wallets', coalesce((select jsonb_agg(jsonb_build_object(
      'tenant_id', w.tenant_id, 'balance_credits', w.original_balance_credits::text,
      'created_at', w.created_at, 'updated_at', w.updated_at
    ) order by w.tenant_id) from public.messaging_wallets w), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'tenant_id', l.tenant_id, 'delta_credits', l.original_delta_credits::text,
      'balance_after_credits', l.original_balance_after_credits::text, 'reason', l.reason,
      'notification_id', l.notification_id, 'request_key', l.request_key,
      'recorded_by_user_id', l.recorded_by_user_id, 'created_at', l.created_at
    ) order by l.tenant_id, l.id) from public.messaging_wallet_ledger l), '[]'::jsonb)
  ) into v_after;
  if v_after is distinct from v_manifest
     or (select sum(balance_paise::numeric) from public.messaging_wallets) <> 450000
     or exists(select 1 from public.messaging_wallets w where
       w.balance_paise::numeric <> w.original_balance_credits::numeric*100
       or w.balance_paise::numeric <> (select coalesce(sum(l.delta_paise::numeric),0)
         from public.messaging_wallet_ledger l where l.tenant_id=w.tenant_id))
     or exists(select 1 from public.messaging_wallet_ledger l where
       l.delta_paise::numeric <> l.original_delta_credits::numeric*100
       or l.balance_after_paise::numeric is distinct from l.original_balance_after_credits::numeric*100) then
    raise exception 'Exact converted wallet invariants failed' using errcode='23514';
  end if;
end
$cutover$;

alter table public.messaging_wallets add constraint messaging_wallets_conversion_evidence_chk check (
  (original_balance_credits is null and conversion_paise_per_credit is null and conversion_currency is null
    and conversion_approval_ref is null and converted_at is null)
  or (original_balance_credits is not null and original_balance_credits >= 0
    and conversion_paise_per_credit is not null and conversion_paise_per_credit=100
    and conversion_currency is not null and conversion_currency='INR'
    and conversion_approval_ref is not null and conversion_approval_ref='efff581' and converted_at is not null)
);
alter table public.messaging_wallet_ledger add constraint messaging_wallet_ledger_conversion_evidence_chk check (
  (original_delta_credits is null and original_balance_after_credits is null and conversion_paise_per_credit is null
    and conversion_currency is null and conversion_approval_ref is null and converted_at is null)
  or (original_delta_credits is not null and original_delta_credits <> 0
    and conversion_paise_per_credit is not null and conversion_paise_per_credit=100
    and conversion_currency is not null and conversion_currency='INR'
    and conversion_approval_ref is not null and conversion_approval_ref='efff581' and converted_at is not null
    and delta_paise::numeric=original_delta_credits::numeric*100
    and balance_after_paise::numeric is not distinct from original_balance_after_credits::numeric*100)
);

create function app.enforce_wallet_conversion_evidence()
returns trigger language plpgsql volatile security invoker set search_path='' as $fn$
declare
  v_new jsonb;
  v_old jsonb;
begin
  if tg_op='DELETE' then
    if tg_table_name='messaging_wallet_ledger' or old.converted_at is not null then
      raise exception 'Wallet conversion history cannot be removed' using errcode='23514';
    end if;
    return old;
  end if;
  v_new := to_jsonb(new);
  if tg_op='INSERT' then
    if new.converted_at is not null or new.conversion_paise_per_credit is not null
       or new.conversion_currency is not null or new.conversion_approval_ref is not null
       or v_new->>'original_balance_credits' is not null or v_new->>'original_delta_credits' is not null
       or v_new->>'original_balance_after_credits' is not null then
      raise exception 'New rows cannot forge conversion history' using errcode='23514';
    end if;
  else
    v_old := to_jsonb(old);
    if tg_table_name='messaging_wallet_ledger' then
      raise exception 'Wallet ledger is append-only' using errcode='23514';
    end if;
    if old.converted_at is not null and new.tenant_id is distinct from old.tenant_id then
      raise exception 'Converted wallet identity is immutable' using errcode='23514';
    end if;
    if (v_new->'original_balance_credits',new.conversion_paise_per_credit,new.conversion_currency,
        new.conversion_approval_ref,new.converted_at) is distinct from
       (v_old->'original_balance_credits',old.conversion_paise_per_credit,old.conversion_currency,
        old.conversion_approval_ref,old.converted_at) then
      raise exception 'Wallet conversion evidence is immutable' using errcode='23514';
    end if;
  end if;
  return new;
end
$fn$;
alter function app.enforce_wallet_conversion_evidence() owner to postgres;
revoke all on function app.enforce_wallet_conversion_evidence() from public,anon,authenticated,service_role;
create trigger messaging_wallets_conversion_evidence before insert or update or delete
  on public.messaging_wallets for each row execute function app.enforce_wallet_conversion_evidence();
create trigger messaging_wallet_ledger_conversion_evidence before insert or update or delete
  on public.messaging_wallet_ledger for each row execute function app.enforce_wallet_conversion_evidence();

create function app.record_wallet_movement(
  p_tenant_id uuid,
  p_delta_paise bigint,
  p_currency text,
  p_reason text,
  p_request_key uuid,
  p_notification_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_balance bigint;
  v_new_balance numeric;
  v_new_balance_bigint bigint;
  v_ledger_id uuid;
  v_created_at timestamptz;
  v_actor uuid;
  v_reason text;
  v_existing public.messaging_wallet_ledger%rowtype;
begin
  v_actor := app.require_platform_super_admin();
  if p_actor_user_id is distinct from v_actor then
    raise exception 'A wallet adjustment requires its verified super admin actor'
      using errcode = '42501';
  end if;

  select w.balance_paise into v_balance
    from public.messaging_wallets w
   where w.tenant_id = p_tenant_id
   for update;
  if v_balance is null then
    raise exception 'Wallet not found' using errcode = 'P0002';
  end if;

  if p_currency is distinct from 'INR' or p_delta_paise is null then
    raise exception 'Explicit INR paise are required' using errcode='22023';
  end if;
  if p_delta_paise = 0 then
    raise exception 'A wallet adjustment requires a nonzero delta'
      using errcode = '23514';
  end if;
  v_reason := btrim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'A wallet adjustment requires a reason'
      using errcode = '23514';
  end if;
  if p_request_key is null then
    raise exception 'A wallet adjustment requires its request key'
      using errcode = '22023';
  end if;

  -- Wallet locking serializes every request-key replay with its original
  -- movement. The comparison belongs here, beside the eventual insert.
  select l.* into v_existing from public.messaging_wallet_ledger l
   where l.tenant_id = p_tenant_id and l.request_key = p_request_key;
  if found then
    if v_existing.currency = p_currency
       and v_existing.notification_id is not distinct from p_notification_id
       and v_existing.delta_paise = p_delta_paise
       and v_existing.reason = v_reason
       and v_existing.recorded_by_user_id = p_actor_user_id then
      return jsonb_build_object(
        'ledgerId', v_existing.id, 'tenantId', v_existing.tenant_id,
        'deltaPaise', v_existing.delta_paise::text, 'currency', v_existing.currency, 'reason', v_existing.reason,
        'balanceAfterPaise', v_existing.balance_after_paise::text,
        'createdAt', v_existing.created_at
      );
    end if;
    raise exception 'This request key is bound to a different adjustment'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  v_new_balance := v_balance::numeric + p_delta_paise::numeric;
  if v_new_balance < 0 then
    raise exception 'This movement would drive the wallet below zero'
      using errcode = 'GL067';
  end if;
  begin
    v_new_balance_bigint := v_new_balance::bigint;
  exception
    when numeric_value_out_of_range then
      raise exception 'This movement overflows the paise balance'
        using errcode = '22003';
  end;

  insert into public.messaging_wallet_ledger (
    tenant_id, delta_paise, currency, reason, notification_id, request_key,
    recorded_by_user_id, balance_after_paise
  ) values (
    p_tenant_id, p_delta_paise, p_currency, v_reason, p_notification_id, p_request_key,
    p_actor_user_id, v_new_balance_bigint
  )
  returning id, created_at into v_ledger_id, v_created_at;

  update public.messaging_wallets
     set balance_paise = v_new_balance_bigint
   where tenant_id = p_tenant_id;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    p_tenant_id, v_actor, 'super_admin'::public.app_role, null,
    case when p_notification_id is not null then 'messaging_wallet.debited' else 'messaging_wallet.adjusted' end,
    'messaging_wallet', p_tenant_id,
    jsonb_build_object('balance_paise', v_balance::text, 'currency', p_currency),
    jsonb_build_object(
      'balance_paise', v_new_balance_bigint::text,
      'currency', p_currency,
      'ledger_id', v_ledger_id,
      'delta_paise', p_delta_paise::text,
      'notification_id', p_notification_id,
      'request_key', p_request_key,
      'recorded_by_user_id', p_actor_user_id
    ),
    v_reason
  );

  return jsonb_build_object(
    'ledgerId', v_ledger_id, 'tenantId', p_tenant_id,
    'deltaPaise', p_delta_paise::text, 'currency', p_currency, 'reason', v_reason,
    'balanceAfterPaise', v_new_balance_bigint::text,
    'createdAt', v_created_at
  );
end
$fn$;

revoke all on function app.record_wallet_movement(uuid, bigint, text, text, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

alter function app.record_wallet_movement(uuid,bigint,text,text,uuid,uuid,uuid) owner to postgres;

create function public.adjust_messaging_wallet_paise(
  p_tenant_id uuid,
  p_delta_paise bigint,
  p_currency text,
  p_reason text,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_user uuid;
begin
  v_user := auth.uid();
  if v_user is null
     or app.current_app_role() is distinct from 'super_admin'
     or app.current_tenant_id() is not null
     or app.current_staff_id() is not null
     or app.current_member_id() is not null
     or app.current_impersonation_id() is not null
     or not exists (
       select 1 from public.platform_users pu
        where pu.user_id = v_user and pu.role = 'super_admin'::public.app_role and pu.is_active
     ) then
    raise exception 'A wallet adjustment requires a real super admin session'
      using errcode = '42501';
  end if;

  -- Resolve the target before request validation.
  if not exists (select 1 from public.messaging_wallets w where w.tenant_id = p_tenant_id) then
    raise exception 'Wallet not found' using errcode = 'P0002';
  end if;
  return app.record_wallet_movement(p_tenant_id, p_delta_paise, p_currency, p_reason, p_request_key, null, v_user);
end
$fn$;

revoke all on function public.adjust_messaging_wallet_paise(uuid, bigint, text, text, uuid) from public, anon, service_role;
grant execute on function public.adjust_messaging_wallet_paise(uuid, bigint, text, text, uuid) to authenticated;

alter function public.adjust_messaging_wallet_paise(uuid,bigint,text,text,uuid) owner to postgres;

create or replace function public.adjust_messaging_wallet(
  p_tenant_id uuid,
  p_delta_credits bigint,
  p_reason text,
  p_request_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_user uuid;
  v_existing public.messaging_wallet_ledger%rowtype;
  v_reason text;
begin
  v_user := auth.uid();
  if v_user is null
     or app.current_app_role() is distinct from 'super_admin'
     or app.current_tenant_id() is not null
     or app.current_staff_id() is not null
     or app.current_member_id() is not null
     or app.current_impersonation_id() is not null
     or not exists (
       select 1 from public.platform_users pu
        where pu.user_id = v_user and pu.role = 'super_admin'::public.app_role and pu.is_active
     ) then
    raise exception 'A wallet adjustment requires a real super admin session'
      using errcode = '42501';
  end if;

  -- Resolve the target before request validation.
  if not exists (select 1 from public.messaging_wallets w where w.tenant_id = p_tenant_id) then
    raise exception 'Wallet not found' using errcode = 'P0002';
  end if;
  perform 1 from public.messaging_wallets w where w.tenant_id=p_tenant_id for update;
  if not found then raise exception 'Wallet not found' using errcode='P0002'; end if;
  if p_delta_credits=0 then
    raise exception 'A wallet adjustment requires a nonzero delta' using errcode='23514';
  end if;
  v_reason := btrim(coalesce(p_reason,''));
  if v_reason='' then
    raise exception 'A wallet adjustment requires a reason' using errcode='23514';
  end if;
  if p_request_key is null or p_delta_credits is null then
    raise exception 'Legacy credits permit historical replay only' using errcode='22023';
  end if;
  select l.* into v_existing from public.messaging_wallet_ledger l
   where l.tenant_id=p_tenant_id and l.request_key=p_request_key;
  if not found or v_existing.converted_at is null or v_existing.notification_id is not null then
    raise exception 'Legacy credits permit historical replay only' using errcode='22023';
  end if;
  if v_existing.original_delta_credits is distinct from p_delta_credits
     or v_existing.reason is distinct from v_reason
     or v_existing.recorded_by_user_id is distinct from v_user then
    raise exception 'This request key is bound to a different adjustment' using errcode='GL068',detail='idempotency_conflict';
  end if;
  return jsonb_build_object('ledgerId',v_existing.id,'tenantId',v_existing.tenant_id,
    'deltaCredits',v_existing.original_delta_credits::text,'reason',v_existing.reason,
    'balanceAfterCredits',v_existing.original_balance_after_credits::text,'createdAt',v_existing.created_at);
end
$fn$;

revoke all on function public.adjust_messaging_wallet(uuid, bigint, text, uuid) from public, anon, service_role;
grant execute on function public.adjust_messaging_wallet(uuid, bigint, text, uuid) to authenticated;

alter function public.adjust_messaging_wallet(uuid,bigint,text,uuid) owner to postgres;

-- Retire the old private arithmetic path; legacy RPC can only replay evidence.
drop function app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid);

create or replace function public.list_notifications(p_channel public.notification_channel default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
begin
  if auth.uid() is null
     or app.current_tenant_id() is null
     or (app.current_impersonation_id() is null and (
       app.is_front_office() is not true
       or app.current_staff_id() is null
       or not exists (
       select 1 from public.staff s
        where s.tenant_id = app.current_tenant_id()
          and s.id = app.current_staff_id()
          and s.user_id = auth.uid()
          and s.role::text = app.current_app_role()
          and s.is_active
       )
     )) then
    raise exception 'The messages list requires a real front-office session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();

  return (
    with filtered as (
      select n.id, n.member_id, m.full_name as member_name, n.channel,
             n.category, n.status, n.scheduled_for, n.sent_at, n.delivered_at,
             n.failed_at, n.failed_reason, n.opted_out_at, n.opted_out_reason,
             n.source_notification_id
        from public.notifications n
        join public.members m on m.tenant_id = n.tenant_id and m.id = n.member_id
       where n.tenant_id = v_tenant
         and (p_channel is null or n.channel = p_channel)
    )
    select jsonb_build_object(
      'asOf', statement_timestamp(),
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', f.id, 'memberId', f.member_id, 'memberName', f.member_name,
          'channel', f.channel, 'category', f.category, 'status', f.status,
          'scheduledFor', f.scheduled_for, 'sentAt', f.sent_at,
          'deliveredAt', f.delivered_at, 'failedAt', f.failed_at,
          'failedReason', f.failed_reason, 'optedOutAt', f.opted_out_at,
          'optedOutReason', f.opted_out_reason,
          'sourceNotificationId', f.source_notification_id
        ) order by f.scheduled_for desc, f.id desc) from filtered f
      ), '[]'::jsonb),
      'statusCounts', (
        select jsonb_build_object(
          'scheduled', (count(*) filter (where f.status = 'scheduled'::public.notification_status))::text,
          'sent', (count(*) filter (where f.status = 'sent'::public.notification_status))::text,
          'delivered', (count(*) filter (where f.status = 'delivered'::public.notification_status))::text,
          'failed', (count(*) filter (where f.status = 'failed'::public.notification_status))::text,
          'opted_out', (count(*) filter (where f.status = 'opted_out'::public.notification_status))::text
        ) from filtered f
      ),
      -- Keep money as decimal text. Front desk receives a null wallet;
      -- a verified gym admin receives explicit INR paise
      -- in the same list snapshot.
      'wallet', case when app.is_gym_admin() is true then (
        select jsonb_build_object('balancePaise',w.balance_paise::text,'currency',w.currency) from public.messaging_wallets w
         where w.tenant_id = v_tenant
      ) else null end
    )
  );
end
$fn$;

revoke all on function public.list_notifications(public.notification_channel) from public, anon, service_role;
grant execute on function public.list_notifications(public.notification_channel) to authenticated;

alter function public.list_notifications(public.notification_channel) owner to postgres;

create or replace function public.onboard_gym(
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
  insert into public.messaging_wallets (tenant_id,balance_paise,currency) values (p_request_key,0,'INR');
  insert into public.staff (tenant_id,user_id,branch_id,role,full_name,email,is_active)
  values (p_request_key,null,null,'gym_owner',v_owner,v_email,true) returning id into v_owner_id;
  update public.organizations set status='trial'::public.organization_status where id=p_request_key;
  v_result := jsonb_build_object('organization',app.organization_result(p_request_key),'branchId',v_branch_id,'ownerStaffId',v_owner_id,'ownerAccessPending',true);
  perform app.platform_audit(p_request_key,v_actor,'organization.onboarded','organization',p_request_key,null,
    jsonb_build_object('organization',app.organization_result(p_request_key),'branch_id',v_branch_id,'owner_staff_id',v_owner_id,'preset',p_preset,'wallet_balance_paise','0','wallet_currency','INR'),null,p_request_key,
    jsonb_build_object('command','onboard_gym','actorUserId',v_actor::text,'request',v_request,'result',v_result));
  return v_result;
end
$fn$;

alter function public.onboard_gym(uuid,text,text,text,public.gym_preset,text,text,text) owner to postgres;
