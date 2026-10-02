-- GRD-001..028; ADR-178. Forward-only, applied by CI alone.
-- Frozen guardian-minors proposal and owner-approved marker-integrity amendment.
do $pre$
begin
  if to_regprocedure('public.issue_member_invite(uuid,text)') is null
     or to_regprocedure('public.redeem_member_invite(text)') is null
     or to_regprocedure('public.peek_member_invite(text)') is null
     or to_regprocedure('app.member_invite_actor(text[])') is null
     or to_regclass('public.guardian_consents') is not null
     or to_regtype('public.guardian_relation') is not null then
    raise exception 'Guardian migration requires INV and a fresh guardian schema';
  end if;
end
$pre$;

create type public.guardian_relation as enum ('mother','father','grandparent','sibling','legal_guardian','other');
alter table public.members
  add column guardian_name text,
  add column guardian_relation public.guardian_relation,
  add column guardian_phone text,
  add column guardian_email text,
  add column guardian_linked_at timestamptz,
  add constraint members_guardian_name_chk check (guardian_name is null or
    (guardian_name = btrim(guardian_name) and char_length(guardian_name) between 1 and 120)),
  add constraint members_guardian_phone_format_chk check (guardian_phone is null or guardian_phone ~ '^\+[1-9][0-9]{7,14}$'),
  add constraint members_guardian_email_format_chk check (guardian_email is null or
    (char_length(guardian_email) <= 254 and guardian_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  add constraint members_guardian_identity_chk check ((guardian_name is null) = (guardian_relation is null)),
  add constraint members_guardian_contact_chk check (guardian_name is not null or (guardian_phone is null and guardian_email is null)),
  add constraint members_guardian_linked_state_chk check (guardian_linked_at is null or user_id is not null);
alter table public.organization_settings add column members_without_dob_attested_adult_at timestamptz;

create table public.guardian_consents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  member_id uuid not null,
  granted boolean not null,
  version text not null,
  source text not null,
  guardian_name text not null,
  guardian_relation public.guardian_relation not null,
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by_staff_id uuid not null,
  created_at timestamptz not null default now(),
  constraint guardian_consents_member_id_fkey foreign key (tenant_id,member_id) references public.members(tenant_id,id),
  constraint guardian_consents_recorded_by_staff_id_fkey foreign key (tenant_id,recorded_by_staff_id) references public.staff(tenant_id,id),
  constraint guardian_consents_tenant_id_member_id_recorded_at_key unique (tenant_id,member_id,recorded_at),
  constraint guardian_consents_version_format_chk check (version ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  constraint guardian_consents_source_chk check (source = btrim(source) and char_length(source) between 1 and 200),
  constraint guardian_consents_guardian_name_chk check (guardian_name = btrim(guardian_name) and char_length(guardian_name) between 1 and 120)
);
create index guardian_consents_tenant_id_member_id_recorded_at_id_idx on public.guardian_consents(tenant_id,member_id,recorded_at desc,id desc);
create index guardian_consents_tenant_id_recorded_by_staff_id_idx on public.guardian_consents(tenant_id,recorded_by_staff_id);
alter table public.guardian_consents enable row level security;
create policy guardian_consents_tenant_select on public.guardian_consents for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_front_office()));
create policy guardian_consents_platform_select on public.guardian_consents for select to authenticated
  using ((select app.is_platform()));
revoke all on public.guardian_consents from anon,authenticated,service_role;
grant select on public.guardian_consents to authenticated,service_role;
create trigger guardian_consents_preview_read_only before insert or update or delete on public.guardian_consents
  for each row execute function app.enforce_preview_read_only();

-- The sole age threshold; leap-day adulthood is the later day.
create function app.member_adult_on(p_date_of_birth date) returns date
language sql immutable security invoker set search_path = '' as $fn$
  select anniversary + case when extract(month from p_date_of_birth) = 2 and extract(day from p_date_of_birth) = 29
    then 1 else 0 end from (select (p_date_of_birth + interval '18 years')::date as anniversary) a
$fn$;
create function app.member_is_minor_on(p_date_of_birth date,p_on date) returns boolean
language sql immutable security invoker set search_path = '' as $fn$
  select coalesce(p_on < app.member_adult_on(p_date_of_birth),false)
$fn$;
create function app.gym_today(p_tenant_id uuid) returns date
language sql stable security invoker set search_path = '' as $fn$
  select (statement_timestamp() at time zone coalesce(z.name,'UTC'))::date
    from public.organizations o left join pg_catalog.pg_timezone_names z on z.name = o.timezone
    where o.id = p_tenant_id
$fn$;
create function app.member_guardian_complete(p_member public.members) returns boolean
language sql immutable security invoker set search_path = '' as $fn$
  select p_member.guardian_name is not null and p_member.guardian_relation is not null and p_member.guardian_phone is not null
$fn$;
create function app.member_guardian_consent_state(p_tenant_id uuid,p_member_id uuid) returns text
language sql stable security invoker set search_path = '' as $fn$
  select coalesce((select case when c.id is null then 'none' when not c.granted then 'withdrawn'
      when lower(c.guardian_name) = lower(m.guardian_name) and c.guardian_relation = m.guardian_relation then 'granted'
      else 'stale' end
    from public.members m left join lateral (
      select gc.* from public.guardian_consents gc where gc.tenant_id = m.tenant_id and gc.member_id = m.id
      order by gc.recorded_at desc,gc.id desc limit 1
    ) c on true where m.tenant_id = p_tenant_id and m.id = p_member_id),'none')
$fn$;
create function app.member_scoring_state(p_tenant_id uuid,p_member_id uuid,p_on date) returns text
language sql stable security invoker set search_path = '' as $fn$
  select case when p_on is null then 'off_age_unknown'
    when m.date_of_birth is null then case when s.members_without_dob_attested_adult_at is not null
      and m.created_at <= s.members_without_dob_attested_adult_at then 'on_adult' else 'off_age_unknown' end
    when not app.member_is_minor_on(m.date_of_birth,p_on) then 'on_adult'
    when not app.member_guardian_complete(m) then 'off_no_guardian'
    else case app.member_guardian_consent_state(m.tenant_id,m.id)
      when 'granted' then 'on_consent' when 'withdrawn' then 'off_consent_withdrawn'
      when 'stale' then 'off_consent_stale' else 'off_no_consent' end end
  from public.members m left join public.organization_settings s on s.tenant_id = m.tenant_id
  where m.tenant_id = p_tenant_id and m.id = p_member_id
$fn$;
create function app.member_scoring_eligible(p_tenant_id uuid,p_member_id uuid,p_on date) returns boolean
language sql stable security invoker set search_path = '' as $fn$
  select p_on is not null and coalesce(app.member_scoring_state(p_tenant_id,p_member_id,p_on) in ('on_adult','on_consent'),false)
$fn$;
create function app.member_invite_email(p_member public.members,p_on date) returns text
language sql stable security invoker set search_path = '' as $fn$
  select case when app.member_is_minor_on(p_member.date_of_birth,p_on)
    then nullif(btrim(p_member.guardian_email),'') else nullif(btrim(p_member.email),'') end
$fn$;
create function app.member_invite_guardian_ok(p_member public.members,p_on date) returns boolean
language sql stable security invoker set search_path = '' as $fn$
  select not app.member_is_minor_on(p_member.date_of_birth,p_on) or app.member_guardian_complete(p_member)
$fn$;
create function app.member_contact_phone(p_tenant_id uuid,p_member_id uuid) returns text
language sql stable security invoker set search_path = '' as $fn$
  select case when app.member_is_minor_on(m.date_of_birth,app.gym_today(m.tenant_id))
    then case when app.member_guardian_complete(m) then m.guardian_phone end else m.phone end
  from public.members m where m.tenant_id = p_tenant_id and m.id = p_member_id
$fn$;
create function app.member_contact_email(p_tenant_id uuid,p_member_id uuid) returns text
language sql stable security invoker set search_path = '' as $fn$
  select case when app.member_is_minor_on(m.date_of_birth,app.gym_today(m.tenant_id))
    then case when app.member_guardian_complete(m) then m.guardian_email end else m.email end
  from public.members m where m.tenant_id = p_tenant_id and m.id = p_member_id
$fn$;

create function app.guardian_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,
  p_record_type text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text) returns void
language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if p_action is null or p_action not in ('organization.members_without_dob_attested_adult','member.age_changed',
    'member.guardian_changed','member.scoring_stopped','guardian_consent.granted','guardian_consent.withdrawn','member.account_transitioned') then
    raise exception 'Unsupported guardian audit action' using errcode = '22023';
  end if;
  insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason)
    values(p_tenant_id,p_actor,p_role,p_action,p_record_type,p_record_id,p_before,p_after,p_reason);
end
$fn$;
create function app.close_ineligible_cases(p_tenant_id uuid,p_member_id uuid,p_cause text) returns integer
language plpgsql volatile security invoker set search_path = '' as $fn$
declare v_closed integer := 0; v_role public.app_role;
begin
  if not app.member_scoring_eligible(p_tenant_id,p_member_id,app.gym_today(p_tenant_id)) then
    update public.no_show_cases c set status = 'closed',closed_at = pg_catalog.now()
      where c.tenant_id = p_tenant_id and c.member_id = p_member_id and c.status in ('open','contacted','follow_up_due');
    get diagnostics v_closed = row_count;
    if v_closed > 0 then
      if auth.uid() is not null and app.current_app_role() = any(enum_range(null::public.app_role)::text[]) then
        v_role := app.current_app_role()::public.app_role;
      end if;
      perform app.guardian_audit(p_tenant_id,auth.uid(),v_role,'member.scoring_stopped','member',p_member_id,
        null,jsonb_build_object('closed_cases',v_closed,'cause',p_cause),null);
    end if;
  end if;
  return v_closed;
end
$fn$;
create function app.members_guardian_marker() returns trigger
language plpgsql security invoker set search_path = '' as $fn$
begin
  -- Same trust boundary as INV. Alphabetic trigger order leaves INV's binding refusal first.
  if current_user <> 'postgres' and not (current_user = 'service_role' and auth.uid() is null) then
    if (tg_op = 'INSERT' and new.guardian_linked_at is not null)
       or (tg_op = 'UPDATE' and new.guardian_linked_at is distinct from old.guardian_linked_at) then
      raise exception 'Guardian binding is changed by its audited commands' using errcode = '42501',detail = 'guardian_binding_command_required';
    end if;
  elsif tg_op = 'UPDATE' and new.user_id is distinct from old.user_id
    and new.guardian_linked_at is not distinct from old.guardian_linked_at then
    new.guardian_linked_at := null;
  end if;
  return new;
end
$fn$;
create function app.members_guardian_after_change() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare v_role public.app_role; v_today date := app.gym_today(new.tenant_id); v_cause text := 'guardian_changed';
begin
  if auth.uid() is not null and app.current_app_role() = any(enum_range(null::public.app_role)::text[]) then
    v_role := app.current_app_role()::public.app_role;
  end if;
  if old.date_of_birth is distinct from new.date_of_birth then
    v_cause := 'age_changed';
    perform app.guardian_audit(new.tenant_id,auth.uid(),v_role,'member.age_changed','member',new.id,
      jsonb_build_object('dob_known',old.date_of_birth is not null,'minor',app.member_is_minor_on(old.date_of_birth,v_today)),
      jsonb_build_object('dob_known',new.date_of_birth is not null,'minor',app.member_is_minor_on(new.date_of_birth,v_today)),null);
  end if;
  if old.guardian_name is distinct from new.guardian_name or old.guardian_relation is distinct from new.guardian_relation
    or old.guardian_phone is distinct from new.guardian_phone or old.guardian_email is distinct from new.guardian_email then
    perform app.guardian_audit(new.tenant_id,auth.uid(),v_role,'member.guardian_changed','member',new.id,
      jsonb_build_object('guardian_present',old.guardian_name is not null,'relation',old.guardian_relation,
        'complete',app.member_guardian_complete(old),'phone_present',old.guardian_phone is not null,'email_present',old.guardian_email is not null),
      jsonb_build_object('guardian_present',new.guardian_name is not null,'relation',new.guardian_relation,
        'complete',app.member_guardian_complete(new),'phone_present',new.guardian_phone is not null,'email_present',new.guardian_email is not null),null);
  end if;
  perform app.close_ineligible_cases(new.tenant_id,new.id,v_cause);
  return new;
end
$fn$;
create function app.guard_legacy_adult_attestation() returns trigger
language plpgsql security invoker set search_path = '' as $fn$
begin
  if tg_op = 'INSERT' then
    if new.members_without_dob_attested_adult_at is not null and current_user in ('authenticated','anon','service_role') then
      raise exception 'Legacy attestation requires its owner command' using errcode = '42501';
    end if;
  elsif new.members_without_dob_attested_adult_at is distinct from old.members_without_dob_attested_adult_at then
    if current_user in ('authenticated','anon','service_role') then
      raise exception 'Legacy attestation requires its owner command' using errcode = '42501';
    end if;
    if old.members_without_dob_attested_adult_at is not null then
      raise exception 'Legacy attestation is immutable' using errcode = '22023';
    end if;
  end if;
  return new;
end
$fn$;
create trigger members_guardian_marker before insert or update of user_id,guardian_linked_at on public.members
  for each row execute function app.members_guardian_marker();
create trigger members_guardian_after_change after update of date_of_birth,guardian_name,guardian_relation,guardian_phone,guardian_email on public.members
  for each row when (old.date_of_birth is distinct from new.date_of_birth or old.guardian_name is distinct from new.guardian_name
    or old.guardian_relation is distinct from new.guardian_relation or old.guardian_phone is distinct from new.guardian_phone
    or old.guardian_email is distinct from new.guardian_email) execute function app.members_guardian_after_change();
create trigger organization_settings_legacy_adult_attestation_guard before insert or update on public.organization_settings
  for each row execute function app.guard_legacy_adult_attestation();

create function public.attest_members_without_dob_adult()
returns table(members_without_dob_attested_adult_at timestamptz,changed boolean)
language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor record; v_at timestamptz;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner']);
  select s.members_without_dob_attested_adult_at into v_at from public.organization_settings s
    where s.tenant_id = v_actor.tenant_id for update;
  if not found then raise exception 'Gym settings unavailable' using errcode = '42501'; end if;
  if v_at is not null then return query select v_at,false; return; end if;
  v_at := clock_timestamp();
  update public.organization_settings s set members_without_dob_attested_adult_at = v_at where s.tenant_id = v_actor.tenant_id;
  perform app.guardian_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'organization.members_without_dob_attested_adult',
    'organization_settings',v_actor.tenant_id,jsonb_build_object('members_without_dob_attested_adult_at',null),
    jsonb_build_object('members_without_dob_attested_adult_at',v_at),null);
  return query select v_at,true;
end
$fn$;
create function public.set_member_age_guardian(p_member_id uuid,p_date_of_birth date,p_guardian_name text,
  p_guardian_relation public.guardian_relation,p_guardian_phone text,p_guardian_email text) returns void
language plpgsql volatile security invoker set search_path = '' as $fn$
declare v_member public.members%rowtype; v_name text; v_phone text; v_email text; v_tenant uuid;
begin
  -- INV actor is private; this non-elevated command revalidates the same real actor under caller RLS.
  begin
    if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
      or app.current_member_id() is not null or app.current_impersonation_id() is not null
      or app.is_front_office() is not true or not exists (
        select 1 from public.staff s where s.tenant_id = app.current_tenant_id() and s.id = app.current_staff_id()
          and s.user_id = auth.uid() and s.role::text = app.current_app_role() and s.is_active
      ) then raise exception 'Real front-office staff required' using errcode = '42501'; end if;
    v_tenant := app.current_tenant_id();
  exception when invalid_text_representation then
    raise exception 'Real front-office staff required' using errcode = '42501';
  end;
  if p_member_id is null then raise exception 'Member required' using errcode = '22023'; end if;
  select m.* into v_member from public.members m where m.tenant_id = v_tenant and m.id = p_member_id for no key update;
  if not found then raise exception 'Member unavailable to this gym' using errcode = '42501'; end if;
  v_name := nullif(btrim(p_guardian_name, E' \t\r\n'),''); v_phone := nullif(btrim(p_guardian_phone, E' \t\r\n'),''); v_email := nullif(btrim(p_guardian_email, E' \t\r\n'),'');
  if p_date_of_birth > app.gym_today(v_tenant) then
    raise exception 'date_of_birth_in_future' using errcode = '22023';
  end if;
  if v_name is null and (p_guardian_relation is not null or v_phone is not null or v_email is not null) then
    raise exception 'Guardian details require a name' using errcode = '22023';
  end if;
  update public.members m set date_of_birth = p_date_of_birth,guardian_name = v_name,guardian_relation = p_guardian_relation,
    guardian_phone = v_phone,guardian_email = v_email where m.tenant_id = v_tenant and m.id = p_member_id
    and (m.date_of_birth is distinct from p_date_of_birth or m.guardian_name is distinct from v_name
      or m.guardian_relation is distinct from p_guardian_relation or m.guardian_phone is distinct from v_phone or m.guardian_email is distinct from v_email);
end
$fn$;
create function public.record_guardian_consent(p_member_id uuid,p_granted boolean,p_version text,p_source text)
returns table(consent_id uuid,recorded_at timestamptz,changed boolean)
language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor record; v_member public.members%rowtype; v_previous public.guardian_consents%rowtype;
  v_version text := btrim(p_version, E' \t\r\n'); v_source text := btrim(p_source, E' \t\r\n'); v_state text; v_at timestamptz; v_id uuid;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner','gym_manager','front_desk']);
  if p_member_id is null then raise exception 'Member required' using errcode = '22023'; end if;
  select m.* into v_member from public.members m where m.tenant_id = v_actor.tenant_id and m.id = p_member_id for no key update;
  if not found then raise exception 'Member unavailable to this gym' using errcode = '42501'; end if;
  if p_granted is null or v_version is null or v_version !~ '^[a-z0-9][a-z0-9._-]{0,63}$'
    or v_source is null or char_length(v_source) not between 1 and 200 then
    raise exception 'Valid consent decision, version and source required' using errcode = '22023';
  end if;
  if not app.member_is_minor_on(v_member.date_of_birth,app.gym_today(v_actor.tenant_id)) then
    raise exception 'Member is not a known minor' using errcode = 'GL084';
  end if;
  if not app.member_guardian_complete(v_member) then raise exception 'Guardian required' using errcode = 'GL083'; end if;
  select c.* into v_previous from public.guardian_consents c where c.tenant_id = v_actor.tenant_id and c.member_id = p_member_id
    order by c.recorded_at desc,c.id desc limit 1;
  if found and v_previous.granted = p_granted and v_previous.version = v_version
    and (not p_granted or (lower(v_previous.guardian_name) = lower(v_member.guardian_name)
      and v_previous.guardian_relation = v_member.guardian_relation)) then
    return query select v_previous.id,v_previous.recorded_at,false; return;
  end if;
  v_state := app.member_guardian_consent_state(v_actor.tenant_id,p_member_id);
  v_at := greatest(clock_timestamp(),v_previous.recorded_at + interval '1 microsecond');
  insert into public.guardian_consents(tenant_id,member_id,granted,version,source,guardian_name,guardian_relation,recorded_at,recorded_by_staff_id)
    values(v_actor.tenant_id,p_member_id,p_granted,v_version,v_source,v_member.guardian_name,v_member.guardian_relation,v_at,v_actor.staff_id)
    returning id into v_id;
  perform app.guardian_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,
    case when p_granted then 'guardian_consent.granted' else 'guardian_consent.withdrawn' end,'guardian_consent',v_id,
    jsonb_build_object('standing',v_state),jsonb_build_object('member_id',p_member_id,'version',v_version),null);
  if not p_granted then perform app.close_ineligible_cases(v_actor.tenant_id,p_member_id,'consent_withdrawn'); end if;
  return query select v_id,v_at,true;
end
$fn$;
create function public.transition_member_to_own_account(p_member_id uuid,p_reason text) returns void
language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor record; v_member public.members%rowtype; v_reason text;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner','gym_manager']);
  if p_member_id is null then raise exception 'Member required' using errcode = '22023'; end if;
  select m.* into v_member from public.members m where m.tenant_id = v_actor.tenant_id and m.id = p_member_id for no key update;
  if not found then raise exception 'Member unavailable to this gym' using errcode = '42501'; end if;
  v_reason := btrim(p_reason, E' \t\r\n');
  if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'A reason of 3 to 200 characters is required' using errcode = '22023'; end if;
  if v_member.date_of_birth is null or app.gym_today(v_actor.tenant_id) is null
    or app.member_is_minor_on(v_member.date_of_birth,app.gym_today(v_actor.tenant_id)) then
    raise exception 'Member is not a known adult' using errcode = 'GL084';
  end if;
  if v_member.user_id is null or v_member.guardian_linked_at is null then
    raise exception 'Member is not guardian linked' using errcode = 'GL085';
  end if;
  update public.members m set user_id = null,guardian_linked_at = null where m.tenant_id = v_actor.tenant_id and m.id = p_member_id;
  delete from auth.sessions s where s.user_id = v_member.user_id;
  perform app.guardian_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'member.account_transitioned','member',p_member_id,
    jsonb_build_object('user_linked',true,'guardian_linked',true),jsonb_build_object('user_linked',false,'guardian_linked',false),v_reason);
end
$fn$;

create function public.read_member_guardian(p_member_id uuid)
returns table(age_state text,date_of_birth date,adult_on date,gym_today date,guardian_name text,guardian_relation public.guardian_relation,
  guardian_phone text,guardian_email text,guardian_complete boolean,link_email text,link_email_in_use boolean,consent_state text,
  consent_recorded_at timestamptz,consent_version text,scoring_state text,guardian_linked_at timestamptz,handover_due boolean,legacy_attested_adult boolean)
language plpgsql stable security invoker set search_path = '' as $fn$
declare v_member public.members%rowtype; v_today date;
begin
  if app.is_front_office() is not true or app.current_tenant_id() is null then
    raise exception 'Front-office read required' using errcode = '42501';
  end if;
  select m.* into v_member from public.members m where m.tenant_id = app.current_tenant_id() and m.id = p_member_id;
  if not found then raise exception 'Member unavailable to this gym' using errcode = '42501'; end if;
  v_today := app.gym_today(v_member.tenant_id);
  return query select case when v_member.date_of_birth is null then 'unknown'
    when app.member_is_minor_on(v_member.date_of_birth,v_today) then 'minor' else 'adult' end,
    v_member.date_of_birth,app.member_adult_on(v_member.date_of_birth),v_today,v_member.guardian_name,v_member.guardian_relation,
    v_member.guardian_phone,v_member.guardian_email,app.member_guardian_complete(v_member),app.member_invite_email(v_member,v_today),
    exists(select 1 from public.members other where other.tenant_id = v_member.tenant_id and other.id <> v_member.id and other.user_id is not null
      and lower(app.member_invite_email(other,v_today)) = lower(app.member_invite_email(v_member,v_today))),
    app.member_guardian_consent_state(v_member.tenant_id,v_member.id),c.recorded_at,c.version,
    app.member_scoring_state(v_member.tenant_id,v_member.id,v_today),v_member.guardian_linked_at,
    v_member.date_of_birth is not null and not app.member_is_minor_on(v_member.date_of_birth,v_today)
      and v_member.user_id is not null and v_member.guardian_linked_at is not null,
    v_member.date_of_birth is null and exists(select 1 from public.organization_settings s where s.tenant_id = v_member.tenant_id
      and s.members_without_dob_attested_adult_at is not null and v_member.created_at <= s.members_without_dob_attested_adult_at)
    from (select 1) singleton left join lateral (
      select gc.recorded_at,gc.version from public.guardian_consents gc where gc.tenant_id = v_member.tenant_id and gc.member_id = v_member.id
      order by gc.recorded_at desc,gc.id desc limit 1
    ) c on true;
end
$fn$;
create function public.read_guardian_coverage()
returns table(tracked integer,no_birth_date integer,minor_no_guardian integer,minor_consent_missing integer,handover_due integer,
  members_without_dob_attested_adult_at timestamptz)
language plpgsql stable security invoker set search_path = '' as $fn$
declare v_tenant uuid; v_today date;
begin
  if app.is_front_office() is not true or app.current_tenant_id() is null then
    raise exception 'Front-office read required' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id(); v_today := app.gym_today(v_tenant);
  return query with live as (
    select m.id,app.member_scoring_state(v_tenant,m.id,v_today) as state from public.members m
    where m.tenant_id = v_tenant and exists(select 1 from public.memberships ms where ms.tenant_id = v_tenant and ms.member_id = m.id
      and ms.status in ('active','frozen') and (ms.ends_on is null or ms.ends_on >= v_today))
  ) select count(*) filter(where l.state in ('on_adult','on_consent'))::integer,
    count(*) filter(where l.state = 'off_age_unknown')::integer,count(*) filter(where l.state = 'off_no_guardian')::integer,
    count(*) filter(where l.state in ('off_no_consent','off_consent_withdrawn','off_consent_stale'))::integer,
    (select count(*)::integer from public.members m where m.tenant_id = v_tenant and m.erased_at is null
      and m.status not in ('cancelled','blocked') and m.date_of_birth is not null and not app.member_is_minor_on(m.date_of_birth,v_today)
      and m.user_id is not null and m.guardian_linked_at is not null),
    (select s.members_without_dob_attested_adult_at from public.organization_settings s where s.tenant_id = v_tenant)
    from live l;
end
$fn$;
create function public.list_guardian_attention(p_reason text)
returns table(member_id uuid,member_name text,member_phone text,scoring_state text)
language plpgsql stable security invoker set search_path = '' as $fn$
declare c_limit constant integer := 100; v_tenant uuid; v_today date;
begin
  if app.is_front_office() is not true or app.current_tenant_id() is null then
    raise exception 'Front-office read required' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('no_birth_date','minor_no_guardian','minor_consent_missing','handover_due') then
    raise exception 'Invalid attention reason' using errcode = '22023';
  end if;
  v_tenant := app.current_tenant_id(); v_today := app.gym_today(v_tenant);
  return query select m.id,m.full_name,m.phone,app.member_scoring_state(v_tenant,m.id,v_today) from public.members m
    where m.tenant_id = v_tenant and case when p_reason = 'handover_due' then
      m.erased_at is null and m.status not in ('cancelled','blocked') and m.date_of_birth is not null
      and not app.member_is_minor_on(m.date_of_birth,v_today) and m.user_id is not null and m.guardian_linked_at is not null
    else exists(select 1 from public.memberships ms where ms.tenant_id = v_tenant and ms.member_id = m.id
      and ms.status in ('active','frozen') and (ms.ends_on is null or ms.ends_on >= v_today))
      and case p_reason when 'no_birth_date' then app.member_scoring_state(v_tenant,m.id,v_today) = 'off_age_unknown'
        when 'minor_no_guardian' then app.member_scoring_state(v_tenant,m.id,v_today) = 'off_no_guardian'
        else app.member_scoring_state(v_tenant,m.id,v_today) in ('off_no_consent','off_consent_withdrawn','off_consent_stale') end
    end order by m.full_name,m.id limit c_limit;
end
$fn$;

-- Canonical function bodies, with only the frozen GRD deltas below.

create or replace function public.issue_member_invite(p_member_id uuid, p_token_hash text)
returns table (invite_id uuid, expires_at timestamptz, superseded_invite_id uuid)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in MEMBER_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_ttl constant interval := interval '48 hours';
  c_tenant_issues_per_hour constant integer := 100;
  c_member_issues_per_day constant integer := 5;
  v_actor record;
  v_member public.members%rowtype;
  v_eligible boolean;
  v_now timestamptz := statement_timestamp();
  v_old_id uuid;
  v_new_id uuid;
  v_expires timestamptz;
  v_count integer;
begin
  select * into v_actor from app.member_invite_actor(array['gym_owner', 'gym_manager', 'front_desk']);
  if p_member_id is null then
    raise exception 'Member required' using errcode = '22023';
  end if;
  -- Serialize the gym's quota before any target-row lock: distinct members share this limit.
  perform pg_advisory_xact_lock(hashtextextended('member-invite-issue:' || v_actor.tenant_id::text, 0));
  -- Scoped to the actor's gym, so another gym's member and an unknown id are the same 42501.
  select m.* into v_member from public.members m
   where m.tenant_id = v_actor.tenant_id and m.id = p_member_id for no key update;
  if not found then
    raise exception 'Member unavailable to this gym' using errcode = '42501';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;

  select (o.status = 'active'::public.organization_status
          or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
    into v_eligible from public.organizations o where o.id = v_actor.tenant_id;
  if v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null or not coalesce(v_eligible, false) then
    raise exception 'Member cannot be invited' using errcode = 'GL075', detail = 'member_not_invitable';
  end if;
  if v_member.user_id is not null then
    raise exception 'Member is already linked' using errcode = 'GL077', detail = 'member_already_linked';
  end if;
  if app.member_is_minor_on(v_member.date_of_birth,app.gym_today(v_member.tenant_id)) then
    if not app.member_invite_guardian_ok(v_member,app.gym_today(v_member.tenant_id))
       or app.member_invite_email(v_member,app.gym_today(v_member.tenant_id)) is null then
      raise exception 'Guardian required' using errcode = 'GL083',detail = 'guardian_required';
    end if;
  else
  -- PROV-002: one @, non-empty local part, dotted domain, no whitespace (after trimming).
  if v_member.email is null
     or btrim(v_member.email, E' \t\r\n') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Member email required' using errcode = 'GL076', detail = 'member_email_required';
  end if;
  end if;

  -- Rolling windows counted from issued_at, over every status, so a revoked or superseded invite still
  -- counts: the limit bounds what staff can send, not what is currently live.
  select count(*) into v_count from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.issued_at > v_now - interval '1 hour';
  if v_count >= c_tenant_issues_per_hour then
    raise exception 'Too many invites from this gym' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;
  select count(*) into v_count from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.member_id = v_member.id and i.issued_at > v_now - interval '24 hours';
  if v_count >= c_member_issues_per_day then
    raise exception 'Too many invites for this member' using errcode = 'GL078', detail = 'invite_rate_limited';
  end if;

  -- Resend: close the live invite first (the one-pending index needs the slot), even if it has expired.
  select i.id into v_old_id from public.member_invites i
   where i.tenant_id = v_actor.tenant_id and i.member_id = v_member.id and i.status = 'pending' for update;
  if v_old_id is not null then
    update public.member_invites i set status = 'superseded', closed_at = v_now where i.id = v_old_id;
  end if;

  v_expires := v_now + c_ttl;
  insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, issued_at, expires_at)
    values (v_actor.tenant_id, v_member.id, p_token_hash, v_actor.staff_id, v_now, v_expires)
    returning member_invites.id into v_new_id;

  if v_old_id is not null then
    perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member_invite.superseded',
      'member_invite', v_old_id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'superseded', 'replaced_by', v_new_id), null);
  end if;
  perform app.member_invite_audit(v_actor.tenant_id, v_actor.user_id, v_actor.role, 'member_invite.issued',
    'member_invite', v_new_id, null,
    jsonb_build_object('member_id', v_member.id, 'expires_at', v_expires, 'superseded_invite_id', v_old_id), null);

  return query select v_new_id, v_expires, v_old_id;
end
$fn$;


create or replace function public.redeem_member_invite(p_token_hash text)
returns table (outcome text, gym_name text)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  -- Contract limits, mirrored in MEMBER_INVITE_LIMITS (packages/shared/src/config/constants.ts).
  c_failure_limit constant integer := 10;
  c_failure_window constant interval := interval '15 minutes';
  v_uid uuid;
  v_now timestamptz := statement_timestamp();
  v_recent integer;
  v_found boolean;
  v_invite public.member_invites%rowtype;
  v_member public.members%rowtype;
  v_gym_name text;
  v_gym_eligible boolean;
  v_confirmed boolean;
  v_has_google boolean;
  v_has_password boolean;
  v_provisioned boolean;
  v_outcome text;
  v_today date;
begin
  begin
    v_uid := auth.uid();
    if v_uid is null or app.current_impersonation_id() is not null then
      raise exception 'Signed-in account required' using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    -- A malformed uuid claim is a forged claim.
    raise exception 'Signed-in account required' using errcode = '42501';
  end;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;

  -- Two concurrent redemptions by one account (or a member and a staff link) queue here, so at most one
  -- binding can ever be made for that account.
  perform pg_advisory_xact_lock(hashtextextended('identity-bind:' || v_uid::text, 0));

  select count(*) into v_recent from public.audit_log a
   where a.actor_user_id = v_uid and a.action = 'member_invite.redeem_refused'
     and a.occurred_at > v_now - c_failure_window;
  if v_recent >= c_failure_limit then
    return query select 'rate_limited'::text, null::text;
    return;
  end if;

  select i.* into v_invite from public.member_invites i where i.token_hash = p_token_hash;
  v_found := found;
  if v_found then
    select m.* into v_member from public.members m
     where m.tenant_id = v_invite.tenant_id and m.id = v_invite.member_id for no key update;
    -- Re-read under the lock; everything below decides on this version of the row.
    select i.* into v_invite from public.member_invites i where i.id = v_invite.id for update;
  end if;

  <<decide>>
  begin
    if not v_found then
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    select o.name::text,
           (o.status = 'active'::public.organization_status
            or (o.status = 'trial'::public.organization_status and o.trial_ends_at > v_now))
      into v_gym_name, v_gym_eligible
      from public.organizations o where o.id = v_invite.tenant_id;

    v_today := app.gym_today(v_invite.tenant_id);

    -- Replay (INV-009): only the recorded redeemer, and only while the member is still bound to them.
    -- No write, and no member-status check: they are already in.
    if v_invite.status = 'redeemed'::public.member_invite_status then
      if v_invite.redeemed_user_id = v_uid and v_member.user_id = v_uid then
        return query select 'already_linked_here'::text, v_gym_name;
        return;
      end if;
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    -- (a) The invite is live and the member and gym are still bindable. A member row that already has
    -- a user_id, even this caller's, is unavailable: it cannot be bound twice.
    if v_invite.status <> 'pending'::public.member_invite_status
       or v_invite.expires_at <= v_now
       or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       or v_member.erased_at is not null
       or v_member.user_id is not null
       or not coalesce(v_gym_eligible, false)
       or not app.member_invite_guardian_ok(v_member,v_today) then
      v_outcome := 'invite_unavailable';
      exit decide;
    end if;

    -- (b) A verified Google sign-in (PROV-006a): confirmed email, a google identity, and either
    -- operator-provisioned or no password (email-provider) identity beside it. A self-registered
    -- password account that merely added Google later is not verified.
    select u.email_confirmed_at is not null,
           exists (select 1 from auth.identities gi where gi.user_id = u.id and gi.provider = 'google'),
           exists (select 1 from auth.identities ei where ei.user_id = u.id and ei.provider = 'email'),
           coalesce(u.raw_app_meta_data ->> 'gymloop_provisioned', '') = 'true'
      into v_confirmed, v_has_google, v_has_password, v_provisioned
      from auth.users u where u.id = v_uid;
    if not coalesce(v_confirmed, false) or not coalesce(v_has_google, false)
       or not (coalesce(v_provisioned, false) or not coalesce(v_has_password, false)) then
      v_outcome := 'identity_unverified';
      exit decide;
    end if;

    -- (c) The Google identity's own email, never auth.users.email, equals the member's CURRENT email.
    -- Exact after trimming and lower-casing (no dot or plus normalisation). A blank address on either
    -- side becomes null and null never equals null, so it never matches.
    if not exists (
      select 1 from auth.identities gi
       where gi.user_id = v_uid and gi.provider = 'google'
         and nullif(lower(btrim(gi.identity_data ->> 'email', E' \t\r\n')), '')
           = nullif(lower(btrim(app.member_invite_email(v_member,v_today), E' \t\r\n')), '')
    ) then
      v_outcome := 'email_mismatch';
      exit decide;
    end if;

    -- (d) D1: this Auth user is bound to nothing, in any gym, as member, staff or platform user,
    -- active or not. The target member's own user_id is null (checked in (a)), so any hit is another row.
    if exists (select 1 from public.members bm where bm.user_id = v_uid)
       or exists (select 1 from public.staff bs where bs.user_id = v_uid)
       or exists (select 1 from public.platform_users bp where bp.user_id = v_uid) then
      v_outcome := 'account_already_linked';
      exit decide;
    end if;

    -- Bind. The guard trigger admits this write because the function runs as its postgres owner.
    update public.members m set user_id = v_uid,
      guardian_linked_at = case when app.member_is_minor_on(v_member.date_of_birth,v_today) then statement_timestamp() else null end where m.tenant_id = v_member.tenant_id and m.id = v_member.id;
    update public.member_invites i
       set status = 'redeemed', redeemed_user_id = v_uid, closed_at = v_now
     where i.id = v_invite.id;
    perform app.member_invite_audit(v_invite.tenant_id, v_uid, 'member'::public.app_role, 'member_invite.redeemed',
      'member_invite', v_invite.id, jsonb_build_object('status', 'pending'),
      jsonb_build_object('status', 'redeemed', 'member_id', v_member.id), null);
    perform app.member_invite_audit(v_invite.tenant_id, v_uid, 'member'::public.app_role, 'member.linked',
      'member', v_member.id, jsonb_build_object('user_linked', false),
      jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', v_invite.id), null);
    return query select 'linked'::text, v_gym_name;
    return;
  end;

  -- A refusal. The tenant and record are known only when the token resolved to an invite row; the
  -- audit row carries the outcome and nothing about the member (and, by construction, no token or hash).
  perform app.member_invite_audit(case when v_found then v_invite.tenant_id end, v_uid, null::public.app_role,
    'member_invite.redeem_refused', 'member_invite', case when v_found then v_invite.id end, null,
    jsonb_build_object('outcome', v_outcome), null);
  return query select v_outcome, null::text;
end
$fn$;


create or replace function public.peek_member_invite(p_token_hash text)
returns table (gym_name text)
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'A lowercase SHA-256 token hash is required' using errcode = '22023';
  end if;
  return query
    select o.name::text
      from public.member_invites i
      join public.members m on m.tenant_id = i.tenant_id and m.id = i.member_id
      join public.organizations o on o.id = i.tenant_id
     where i.token_hash = p_token_hash
       and i.status = 'pending'::public.member_invite_status
       and i.expires_at > statement_timestamp()
       and m.status not in ('cancelled'::public.member_status, 'blocked'::public.member_status)
       and m.erased_at is null
       and m.user_id is null
       and app.member_invite_guardian_ok(m,app.gym_today(m.tenant_id))
       and app.member_invite_email(m,app.gym_today(m.tenant_id)) is not null
       and btrim(app.member_invite_email(m,app.gym_today(m.tenant_id)), E' \t\r\n') ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       and (o.status = 'active'::public.organization_status
            or (o.status = 'trial'::public.organization_status and o.trial_ends_at > statement_timestamp()));
end
$fn$;


create or replace function app.run_no_show_scan(p_tenant_id uuid, p_today date default null)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_today     date;
  v_threshold integer;
  v_timezone  text;
  v_opened    integer;
begin
  select o.timezone,
         coalesce(p_today, (pg_catalog.now() at time zone o.timezone)::date),
         s.no_show_threshold_days
    into v_timezone, v_today, v_threshold
    from public.organizations o
    join public.organization_settings s on s.tenant_id = o.id
   where o.id = p_tenant_id;

  if v_today is null or v_threshold is null then
    return 0;
  end if;

  -- Close first, then open. Either order works — the opening pass already
  -- excludes members without a live membership — but closing first means the
  -- function reads as "tidy up what has expired, then look for what is new",
  -- which is the order a person would describe it in.
  update public.no_show_cases c
     set status    = 'closed'::public.no_show_case_status,
         closed_at = pg_catalog.now()
   where c.tenant_id = p_tenant_id
     and c.status in ('open'::public.no_show_case_status,
                      'contacted'::public.no_show_case_status,
                      'follow_up_due'::public.no_show_case_status)
     -- The same definition of "live" the opening pass uses, deliberately
     -- written out rather than shared: if these two ever disagree, a member can
     -- be simultaneously too lapsed to open a case and too live to close one,
     -- and the case sits for ever in between. Any future edit belongs in both.
     and (not exists (
       select 1
         from public.memberships m
        where m.tenant_id = p_tenant_id
          and m.member_id = c.member_id
          and m.status in ('active'::public.membership_status,
                           'frozen'::public.membership_status)
          and (m.ends_on is null or m.ends_on >= v_today)
     ) or not app.member_scoring_eligible(p_tenant_id, c.member_id, v_today));

  with live as (
    select m.member_id, min(m.starts_on) as started_on
      from public.memberships m
     where m.tenant_id = p_tenant_id
       and m.status in ('active'::public.membership_status,
                        'frozen'::public.membership_status)
       and (m.ends_on is null or m.ends_on >= v_today)
     group by m.member_id
  ),
  last_visit as (
    select a.member_id,
           max((a.checked_in_at at time zone v_timezone)::date) as last_on
      from public.attendance a
     where a.tenant_id = p_tenant_id
     group by a.member_id
  ),
  candidate as (
    select l.member_id,
           v.last_on,
           (v_today - coalesce(v.last_on, l.started_on)) as absent_days
      from live l
      left join last_visit v on v.member_id = l.member_id
     where l.started_on is not null
  )
  insert into public.no_show_cases (
    tenant_id, member_id, status, opened_on,
    last_attended_on, absent_days_at_open, threshold_days
  )
  select p_tenant_id, c.member_id, 'open'::public.no_show_case_status, v_today,
         c.last_on, c.absent_days, v_threshold
    from candidate c
   where c.absent_days > v_threshold
     and app.member_scoring_eligible(p_tenant_id, c.member_id, v_today)
     and not exists (
       select 1
         from public.membership_pauses p
         join public.memberships mm on mm.id = p.membership_id
        where p.tenant_id = p_tenant_id
          and mm.member_id = c.member_id
          and p.approved_at is not null
          and p.rejected_at is null
          and v_today between p.starts_on and p.ends_on
     )
  on conflict (tenant_id, member_id)
    where status in ('open'::public.no_show_case_status,
                     'contacted'::public.no_show_case_status,
                     'follow_up_due'::public.no_show_case_status)
    do nothing;

  -- Still the number OPENED, not opened-plus-closed. The spec's contract is
  -- "how many cases did this scan open", and an operator reading a nightly log
  -- needs "we found three new people" to keep meaning that when six lapsed
  -- memberships happen to close on the same night.
  get diagnostics v_opened = row_count;
  return v_opened;
end;
$fn$;


create or replace function app.enforce_notification()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_action text;
  v_source public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_remainder jsonb;
  v_expected_status public.notification_status;
  v_expected_reason text;
  v_renewal public.memberships%rowtype;
  v_offsets smallint[];
  v_offset smallint;
  v_expected_body text;
begin
  new.updated_at := statement_timestamp();

  if tg_op = 'INSERT' then
    if new.category is null or new.dedupe_key is null then
      raise exception 'A new message requires a category and dedupe key'
        using errcode = 'GL066';
    end if;
    if new.status <> 'scheduled'::public.notification_status
       or new.sent_at is not null
       or new.delivered_at is not null
       or new.clicked_at is not null
       or new.converted_at is not null
       or new.failed_at is not null
       or new.failed_reason is not null
       or new.opted_out_at is not null
       or new.opted_out_reason is not null then
      raise exception 'A new message starts scheduled with no delivery evidence'
        using errcode = 'GL066';
    end if;

    -- Renewal/membership rows are scheduler-owned and have one immutable
    -- identity; a caller cannot sidestep it by replacing only the key.
    if new.template_key = 'renewal_reminder'
       or (new.category = 'renewal'::public.message_category
           and new.related_type = 'membership'
           and new.related_id is not null) then
      if current_user = 'authenticated' then
        raise exception 'A renewal reminder is created only by the trusted scheduler'
          using errcode = '42501';
      end if;
      if new.template_key is distinct from 'renewal_reminder'
         or new.channel is distinct from 'in_app'::public.notification_channel
         or new.category is distinct from 'renewal'::public.message_category
         or new.template_id is not null
         or new.source_notification_id is not null
         or new.related_type is distinct from 'membership' then
        raise exception 'A reserved renewal identity must carry its exact structural shape'
          using errcode = 'GL066';
      end if;
      select o.* into v_org from public.organizations o where o.id = new.tenant_id;
      select ms.* into v_renewal from public.memberships ms
       where ms.tenant_id = new.tenant_id
         and ms.id = new.related_id
         and ms.member_id = new.member_id
         and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                           'frozen'::public.membership_status)
         and ms.ends_on is not null;
      v_remainder := app.membership_renewal_remainder(new.tenant_id, new.related_id);
      select os.renewal_reminder_days_from_expiry into v_offsets
        from public.organization_settings os where os.tenant_id = new.tenant_id;
      if not found then
        raise exception 'A reserved renewal reminder requires gym settings'
          using errcode = 'GL066';
      end if;
      v_offset := null;
      if v_offsets is null then
        select w.days_from_expiry into v_offset
          from app.default_renewal_reminder_windows() w
         where w.window_id = new.payload ->> 'windowId';
      else
        select d into v_offset from unnest(v_offsets) d
         where app.renewal_window_id(d) = new.payload ->> 'windowId';
      end if;
      if v_org.id is null
         or v_renewal.id is null
         or v_remainder is null
         or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
         or v_offset is null
         or (statement_timestamp() at time zone v_org.timezone)::date <> v_renewal.ends_on + v_offset
         or new.dedupe_key is distinct from ('renewal:' || lower(v_renewal.id::text) || ':'
             || to_char(v_renewal.ends_on, 'YYYY-MM-DD') || ':' || (new.payload ->> 'windowId'))
         or jsonb_typeof(new.payload) <> 'object'
         or (select count(*) from jsonb_object_keys(new.payload)) <> 7
         or new.payload ->> 'locale' is distinct from 'en'
         or new.payload ->> 'membershipId' is distinct from v_renewal.id::text
         or new.payload ->> 'cycleEndsOn' is distinct from to_char(v_renewal.ends_on, 'YYYY-MM-DD')
         or new.payload ->> 'duePaise' is distinct from v_remainder ->> 'duePaise'
         or new.payload ->> 'currency' is distinct from v_remainder ->> 'currency'
         or new.scheduled_for is distinct from statement_timestamp() then
        raise exception 'A reserved renewal reminder must match the current membership cycle'
          using errcode = 'GL066';
      end if;
      v_expected_body := 'Your membership ends on ' || to_char(v_renewal.ends_on, 'YYYY-MM-DD')
        || '. Renewal amount due: ' || (v_remainder ->> 'currency') || ' '
        || trunc((v_remainder ->> 'duePaise')::numeric / 100::numeric)::text || '.'
        || lpad(mod((v_remainder ->> 'duePaise')::numeric, 100::numeric)::text, 2, '0') || '.';
      if new.payload ->> 'body' is distinct from v_expected_body then
        raise exception 'A reserved renewal reminder must carry the exact renewal body'
          using errcode = 'GL066';
      end if;
    end if;

    if new.source_notification_id is not null then
      select s.* into v_source
        from public.notifications s
       where s.tenant_id = new.tenant_id
         and s.id = new.source_notification_id
         and s.member_id = new.member_id;
      if v_source.id is null then
        raise exception 'A notification source must belong to the same tenant and member'
          using errcode = '23503';
      end if;
    end if;

    if new.channel = 'whatsapp_link'::public.notification_channel then
      if new.source_notification_id is null then
        raise exception 'A WhatsApp message requires its in-app source'
          using errcode = 'GL066';
      end if;
      if current_user <> 'postgres' then
        raise exception 'A WhatsApp child is created only by the open command'
          using errcode = '42501';
      end if;
      if auth.uid() is null
         or app.is_front_office() is not true
         or app.current_tenant_id() is distinct from new.tenant_id
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.staff st
            where st.tenant_id = new.tenant_id
              and st.id = app.current_staff_id()
              and st.user_id = auth.uid()
              and st.role::text = app.current_app_role()
              and st.is_active
         ) then
        raise exception 'A WhatsApp child requires a real front-office session'
          using errcode = '42501';
      end if;
      if v_source.channel is distinct from 'in_app'::public.notification_channel
         or v_source.status not in ('sent'::public.notification_status, 'delivered'::public.notification_status)
         or new.category is distinct from v_source.category
         or new.related_type is distinct from v_source.related_type
         or new.related_id is distinct from v_source.related_id
         or new.payload is distinct from v_source.payload
         or new.template_id is not null
         or new.template_key is not null
         or new.recipient_phone is distinct from app.member_contact_phone(new.tenant_id, new.member_id) then
        raise exception 'A WhatsApp child must be an unchanged snapshot of its source'
          using errcode = 'GL066';
      end if;
    end if;

    perform app.write_notification_audit(
      new.tenant_id, new.id, 'notification.scheduled', null,
      app.notification_audit_shape(new), null
    );
    return new;
  end if;

  -- UPDATE. Identity/content freeze precedes graph/evidence validation.
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.member_id is distinct from old.member_id
     or new.channel is distinct from old.channel
     or new.template_id is distinct from old.template_id
     or new.template_key is distinct from old.template_key
     or new.category is distinct from old.category
     or new.source_notification_id is distinct from old.source_notification_id
     or new.recipient_phone is distinct from old.recipient_phone
     or new.dedupe_key is distinct from old.dedupe_key
     or new.scheduled_for is distinct from old.scheduled_for
     or new.related_type is distinct from old.related_type
     or new.related_id is distinct from old.related_id
     or new.payload is distinct from old.payload
     or new.created_at is distinct from old.created_at then
    raise exception 'A notification''s identity and content are frozen after creation'
      using errcode = 'GL066';
  end if;

  if (old.sent_at is not null and new.sent_at is distinct from old.sent_at)
     or (old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at)
     or (old.clicked_at is not null and new.clicked_at is distinct from old.clicked_at)
     or (old.converted_at is not null and new.converted_at is distinct from old.converted_at)
     or (old.failed_at is not null and new.failed_at is distinct from old.failed_at)
     or (old.opted_out_at is not null and new.opted_out_at is distinct from old.opted_out_at) then
    raise exception 'An existing delivery event cannot be changed'
      using errcode = 'GL066';
  end if;

  if new.status is distinct from old.status then
    if not app.notification_transition_allowed(old.status, new.status) then
      raise exception 'That status change is not an edge of the notification graph'
        using errcode = 'GL066';
    end if;

    -- An authenticated caller has no generic state setter.  The only
    -- availability transition it can produce is the same current-member,
    -- current-consent decision that send_notification makes.  This closes
    -- the direct-table path without a client-settable trust flag.
    if current_user in ('authenticated', 'service_role') then
      if old.status <> 'scheduled'::public.notification_status then
        raise exception 'Direct message writes cannot record delivery evidence'
          using errcode = '42501';
      end if;
      if old.category is null then
        if new.status <> 'failed'::public.notification_status
           or new.failed_reason is distinct from 'classification_missing' then
          raise exception 'A scheduled historical message has no classification'
            using errcode = 'GL066';
        end if;
      end if;
      if old.scheduled_for > statement_timestamp() then
        raise exception 'That message is not yet due' using errcode = 'GL066';
      end if;

      select m.* into v_member from public.members m
       where m.tenant_id = old.tenant_id and m.id = old.member_id
       for update;
      select o.* into v_org from public.organizations o where o.id = old.tenant_id;

      v_expected_status := null;
      v_expected_reason := null;
      if old.category is null then
        v_expected_status := 'failed'::public.notification_status;
        v_expected_reason := 'classification_missing';
      elsif v_member.id is null
         or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
         or v_member.erased_at is not null
         or v_org.id is null
         or not (v_org.status = 'active'::public.organization_status
                 or (v_org.status = 'trial'::public.organization_status
                     and v_org.trial_ends_at is not null
                     and v_org.trial_ends_at > statement_timestamp())) then
        v_expected_status := 'opted_out'::public.notification_status;
        v_expected_reason := 'recipient_ineligible';
      elsif old.category = 'motivation'::public.message_category
            and coalesce(v_member.motivation_push_enabled, false) is not true then
        v_expected_status := 'opted_out'::public.notification_status;
        v_expected_reason := 'motivation_disabled';
      else
        v_purpose := app.notification_consent_purpose(old.category);
        select c.granted into v_granted from public.consents c
         where c.tenant_id = old.tenant_id
           and c.member_id = old.member_id
           and c.purpose = v_purpose
         order by c.recorded_at desc, c.id desc
         limit 1;
        if coalesce(v_granted, false) is not true then
          v_expected_status := 'opted_out'::public.notification_status;
          v_expected_reason := 'consent_withdrawn';
        elsif old.category = 'renewal'::public.message_category
              and old.related_type = 'membership' and old.related_id is not null then
          v_remainder := app.membership_renewal_remainder(old.tenant_id, old.related_id);
          if v_remainder is null
             or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
             or not exists (
               select 1 from public.memberships ms
                where ms.tenant_id = old.tenant_id
                  and ms.id = old.related_id
                  and ms.member_id = old.member_id
                  and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                                    'frozen'::public.membership_status)
                  and ms.ends_on::text = old.payload ->> 'cycleEndsOn'
             ) then
            v_expected_status := 'opted_out'::public.notification_status;
            v_expected_reason := 'renewal_stopped';
          end if;
        end if;
      end if;

      if v_expected_status is null then
        if old.channel = 'in_app'::public.notification_channel then
          v_expected_status := 'sent'::public.notification_status;
        elsif old.channel = 'push'::public.notification_channel then
          v_expected_status := 'failed'::public.notification_status;
          v_expected_reason := 'provider_unconfigured';
        else
          raise exception 'That channel has no v1 send action' using errcode = 'GL066';
        end if;
      end if;
      if new.status is distinct from v_expected_status
         or (v_expected_reason is not null and
             new.failed_reason is distinct from v_expected_reason and
             new.opted_out_reason is distinct from v_expected_reason) then
        raise exception 'That direct availability decision does not match current communication facts'
          using errcode = 'GL066';
      end if;
    end if;

    if old.channel = 'in_app'::public.notification_channel
       and old.status = 'sent'::public.notification_status
       and new.status = 'delivered'::public.notification_status
    then
      if current_user <> 'postgres'
         or auth.uid() is null
         or app.current_app_role() <> 'member'
         or app.current_tenant_id() is distinct from old.tenant_id
         or app.current_member_id() is distinct from old.member_id
         or app.current_staff_id() is not null
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.members m
            where m.tenant_id = old.tenant_id and m.id = old.member_id
              and m.user_id = auth.uid()
              and m.status not in ('cancelled'::public.member_status, 'blocked'::public.member_status)
              and m.erased_at is null
         ) then
        raise exception 'Only the member''s own acknowledgement marks a message delivered'
          using errcode = '42501';
      end if;
    end if;

    if old.channel = 'whatsapp_link'::public.notification_channel
       and old.status = 'scheduled'::public.notification_status
       and new.status = 'sent'::public.notification_status
    then
      if current_user <> 'postgres'
         or auth.uid() is null
         or app.is_front_office() is not true
         or app.current_tenant_id() is distinct from old.tenant_id
         or app.current_impersonation_id() is not null
         or not exists (
           select 1 from public.staff st
            where st.tenant_id = old.tenant_id
              and st.id = app.current_staff_id()
              and st.user_id = auth.uid()
              and st.role::text = app.current_app_role()
              and st.is_active
         ) then
        raise exception 'Only the open command may send a WhatsApp child'
          using errcode = '42501';
      end if;
    end if;

    -- Event time is database evidence, never a caller fact.  The clock is
    -- clamped to the preceding event where that relation exists.
    if new.status = 'sent'::public.notification_status then
      new.sent_at := clock_timestamp();
    elsif new.status = 'delivered'::public.notification_status then
      new.delivered_at := greatest(clock_timestamp(), old.sent_at);
    elsif new.status = 'clicked'::public.notification_status then
      new.clicked_at := greatest(clock_timestamp(), old.delivered_at);
    elsif new.status = 'converted'::public.notification_status then
      if old.status = 'delivered'::public.notification_status and new.clicked_at is not null then
        raise exception 'A delivered message cannot add a click while converting'
          using errcode = 'GL066';
      end if;
      new.converted_at := greatest(clock_timestamp(), old.delivered_at, coalesce(old.clicked_at, old.delivered_at));
    elsif new.status = 'failed'::public.notification_status then
      new.failed_at := greatest(clock_timestamp(), coalesce(old.sent_at, '-infinity'::timestamptz));
    elsif new.status = 'opted_out'::public.notification_status then
      new.opted_out_at := clock_timestamp();
    end if;

    if new.status = 'sent'::public.notification_status and new.sent_at is null then
      raise exception 'A sent message requires its sent timestamp' using errcode = 'GL066';
    elsif new.status = 'delivered'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null) then
      raise exception 'A delivered message requires its sent and delivered timestamps'
        using errcode = 'GL066';
    elsif new.status = 'clicked'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null or new.clicked_at is null) then
      raise exception 'A clicked message requires its full evidence chain'
        using errcode = 'GL066';
    elsif new.status = 'converted'::public.notification_status
          and (new.sent_at is null or new.delivered_at is null or new.converted_at is null) then
      raise exception 'A converted message requires its full evidence chain'
        using errcode = 'GL066';
    elsif new.status = 'failed'::public.notification_status
          and (new.failed_at is null or coalesce(btrim(new.failed_reason), '') = '') then
      raise exception 'A failed message requires its timestamp and reason'
        using errcode = 'GL066';
    elsif new.status = 'failed'::public.notification_status
          and old.status = 'scheduled'::public.notification_status
          and new.sent_at is not null then
      raise exception 'A pre-send failure cannot carry sent evidence'
        using errcode = 'GL066';
    elsif new.status = 'opted_out'::public.notification_status
          and (new.opted_out_at is null or coalesce(btrim(new.opted_out_reason), '') = '') then
      raise exception 'An opted-out message requires its timestamp and reason'
        using errcode = 'GL066';
    end if;

    if (new.status = 'sent'::public.notification_status
        and (new.delivered_at is not null or new.clicked_at is not null or new.converted_at is not null
             or new.failed_at is not null or new.failed_reason is not null
             or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'delivered'::public.notification_status
           and (new.clicked_at is not null or new.converted_at is not null
                or new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'clicked'::public.notification_status
           and (new.converted_at is not null or new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'converted'::public.notification_status
           and (new.failed_at is not null or new.failed_reason is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'failed'::public.notification_status
           and (new.delivered_at is not null or new.clicked_at is not null or new.converted_at is not null
                or new.opted_out_at is not null or new.opted_out_reason is not null))
       or (new.status = 'opted_out'::public.notification_status
           and (new.sent_at is not null or new.delivered_at is not null or new.clicked_at is not null
                or new.converted_at is not null or new.failed_at is not null or new.failed_reason is not null)) then
      raise exception 'That notification state carries inconsistent delivery evidence'
        using errcode = 'GL066';
    end if;

    v_action := 'notification.' || new.status::text;
    perform app.write_notification_audit(
      new.tenant_id, new.id, v_action,
      app.notification_audit_shape(old), app.notification_audit_shape(new),
      case new.status
        when 'failed'::public.notification_status then new.failed_reason
        when 'opted_out'::public.notification_status then new.opted_out_reason
        else null
      end
    );
  else
    if new.sent_at is distinct from old.sent_at
       or new.delivered_at is distinct from old.delivered_at
       or new.clicked_at is distinct from old.clicked_at
       or new.converted_at is distinct from old.converted_at
       or new.failed_at is distinct from old.failed_at
       or new.failed_reason is distinct from old.failed_reason
       or new.opted_out_at is distinct from old.opted_out_at
       or new.opted_out_reason is distinct from old.opted_out_reason then
      raise exception 'A same-state write cannot add delivery evidence'
        using errcode = 'GL066';
    end if;
  end if;

  return new;
end
$fn$;


create or replace function public.open_notification_whatsapp(p_notification_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_staff uuid;
  v_tenant uuid;
  v_source public.notifications%rowtype;
  v_member public.members%rowtype;
  v_org public.organizations%rowtype;
  v_child public.notifications%rowtype;
  v_purpose public.consent_purpose;
  v_granted boolean;
  v_remainder jsonb;
  v_dedupe text;
  v_url text;
begin
  if auth.uid() is null or app.is_front_office() is not true
     or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  select s.id into v_staff from public.staff s where s.tenant_id = v_tenant
    and s.id = app.current_staff_id() and s.user_id = auth.uid()
    and s.role::text = app.current_app_role() and s.is_active;
  if v_staff is null then
    raise exception 'This action requires a real front-office session' using errcode = '42501';
  end if;

  select n.* into v_source from public.notifications n
   where n.tenant_id = v_tenant
     and n.id = p_notification_id
   for update;
  if not found then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;
  if v_source.channel is distinct from 'in_app'::public.notification_channel
     or v_source.status not in ('sent'::public.notification_status, 'delivered'::public.notification_status) then
    raise exception 'Notification not found' using errcode = 'P0002';
  end if;

  if v_source.category is null then
    raise exception 'A source message has no classification' using errcode = 'GL066';
  end if;

  select m.* into v_member from public.members m
   where m.tenant_id = v_tenant and m.id = v_source.member_id
   for update;
  select o.* into v_org from public.organizations o where o.id = v_tenant;
  if v_member.id is null
     or v_member.status in ('cancelled'::public.member_status, 'blocked'::public.member_status)
     or v_member.erased_at is not null
     or app.member_contact_phone(v_tenant, v_member.id) is null
     or v_org.id is null
     or not (v_org.status = 'active'::public.organization_status
             or (v_org.status = 'trial'::public.organization_status
                 and v_org.trial_ends_at is not null
                 and v_org.trial_ends_at > statement_timestamp())) then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  if v_source.category = 'motivation'::public.message_category
     and coalesce(v_member.motivation_push_enabled, false) is not true then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  v_purpose := app.notification_consent_purpose(v_source.category);
  select c.granted into v_granted from public.consents c
   where c.tenant_id = v_tenant and c.member_id = v_member.id and c.purpose = v_purpose
   order by c.recorded_at desc, c.id desc
   limit 1;
  if coalesce(v_granted, false) is not true then
    return jsonb_build_object('communicationOptedOut', true);
  end if;

  if v_source.category = 'renewal'::public.message_category
     and v_source.related_type = 'membership' and v_source.related_id is not null then
    v_remainder := app.membership_renewal_remainder(v_tenant, v_source.related_id);
    if v_remainder is null
       or (v_remainder ->> 'duePaise')::numeric <= 0::numeric
       or not exists (
         select 1 from public.memberships ms
          where ms.tenant_id = v_tenant
            and ms.id = v_source.related_id
            and ms.member_id = v_source.member_id
            and ms.status in ('pending'::public.membership_status, 'active'::public.membership_status,
                              'frozen'::public.membership_status)
            and ms.ends_on::text = v_source.payload ->> 'cycleEndsOn'
       ) then
      return jsonb_build_object('communicationOptedOut', true);
    end if;
  end if;

  v_dedupe := 'whatsapp:' || v_source.id::text;

  select n.* into v_child from public.notifications n
   where n.tenant_id = v_tenant
     and n.source_notification_id = v_source.id
     and n.channel = 'whatsapp_link'::public.notification_channel;

  if found then
    if v_child.recipient_phone is distinct from app.member_contact_phone(v_tenant, v_member.id) then
      raise exception 'The member''s phone number has changed since this message was sent'
        using errcode = 'GL066';
    end if;
  else
    -- template_key is deliberately NOT copied from the source: the contract
    -- lists exactly what a WhatsApp child carries ("same member/category/
    -- relation", source_notification_id, recipient_phone, payload) and
    -- template_key is not among them. Copying it would also be structurally
    -- illegal for a renewal source: the reserved renewal identity check
    -- requires channel='in_app' for any row named template_key='renewal_reminder',
    -- and this child is whatsapp_link.
    insert into public.notifications (
      tenant_id, member_id, channel, status, category,
      source_notification_id, recipient_phone, dedupe_key,
      related_type, related_id, scheduled_for, payload
    ) values (
      v_tenant, v_member.id, 'whatsapp_link', 'scheduled', v_source.category,
      v_source.id, app.member_contact_phone(v_tenant, v_member.id), v_dedupe,
      v_source.related_type, v_source.related_id, statement_timestamp(), v_source.payload
    )
    returning * into v_child;

    update public.notifications
       set status = 'sent', sent_at = statement_timestamp()
     where tenant_id = v_tenant and id = v_child.id
     returning * into v_child;
  end if;

  v_url := 'https://wa.me/' || replace(v_child.recipient_phone, '+', '')
           || '?text=' || app.url_encode_component(coalesce(v_child.payload ->> 'body', ''));

  return jsonb_build_object('notification', app.notification_result_json(v_child), 'url', v_url);
end
$fn$;




-- Explicit ownership and least privileges; no public or service command execution.

alter function app.member_adult_on(date) owner to postgres;
revoke all on function app.member_adult_on(date) from public,anon,authenticated,service_role;
alter function app.member_is_minor_on(date,date) owner to postgres;
revoke all on function app.member_is_minor_on(date,date) from public,anon,authenticated,service_role;
alter function app.gym_today(uuid) owner to postgres;
revoke all on function app.gym_today(uuid) from public,anon,authenticated,service_role;
alter function app.member_guardian_complete(public.members) owner to postgres;
revoke all on function app.member_guardian_complete(public.members) from public,anon,authenticated,service_role;
alter function app.member_guardian_consent_state(uuid,uuid) owner to postgres;
revoke all on function app.member_guardian_consent_state(uuid,uuid) from public,anon,authenticated,service_role;
alter function app.member_scoring_state(uuid,uuid,date) owner to postgres;
revoke all on function app.member_scoring_state(uuid,uuid,date) from public,anon,authenticated,service_role;
alter function app.member_scoring_eligible(uuid,uuid,date) owner to postgres;
revoke all on function app.member_scoring_eligible(uuid,uuid,date) from public,anon,authenticated,service_role;
alter function app.member_invite_email(public.members,date) owner to postgres;
revoke all on function app.member_invite_email(public.members,date) from public,anon,authenticated,service_role;
alter function app.member_invite_guardian_ok(public.members,date) owner to postgres;
revoke all on function app.member_invite_guardian_ok(public.members,date) from public,anon,authenticated,service_role;
alter function app.member_contact_phone(uuid,uuid) owner to postgres;
revoke all on function app.member_contact_phone(uuid,uuid) from public,anon,authenticated,service_role;
alter function app.member_contact_email(uuid,uuid) owner to postgres;
revoke all on function app.member_contact_email(uuid,uuid) from public,anon,authenticated,service_role;
alter function app.close_ineligible_cases(uuid,uuid,text) owner to postgres;
revoke all on function app.close_ineligible_cases(uuid,uuid,text) from public,anon,authenticated,service_role;
alter function app.guardian_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) owner to postgres;
revoke all on function app.guardian_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated,service_role;
alter function app.members_guardian_marker() owner to postgres;
revoke all on function app.members_guardian_marker() from public,anon,authenticated,service_role;
alter function app.members_guardian_after_change() owner to postgres;
revoke all on function app.members_guardian_after_change() from public,anon,authenticated,service_role;
alter function app.guard_legacy_adult_attestation() owner to postgres;
revoke all on function app.guard_legacy_adult_attestation() from public,anon,authenticated,service_role;
alter function public.attest_members_without_dob_adult() owner to postgres;
revoke all on function public.attest_members_without_dob_adult() from public,anon,authenticated,service_role;
alter function public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text) owner to postgres;
revoke all on function public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text) from public,anon,authenticated,service_role;
alter function public.record_guardian_consent(uuid,boolean,text,text) owner to postgres;
revoke all on function public.record_guardian_consent(uuid,boolean,text,text) from public,anon,authenticated,service_role;
alter function public.transition_member_to_own_account(uuid,text) owner to postgres;
revoke all on function public.transition_member_to_own_account(uuid,text) from public,anon,authenticated,service_role;
alter function public.read_member_guardian(uuid) owner to postgres;
revoke all on function public.read_member_guardian(uuid) from public,anon,authenticated,service_role;
alter function public.read_guardian_coverage() owner to postgres;
revoke all on function public.read_guardian_coverage() from public,anon,authenticated,service_role;
alter function public.list_guardian_attention(text) owner to postgres;
revoke all on function public.list_guardian_attention(text) from public,anon,authenticated,service_role;
alter function public.issue_member_invite(uuid,text) owner to postgres;
revoke all on function public.issue_member_invite(uuid,text) from public,anon,authenticated,service_role;
alter function public.redeem_member_invite(text) owner to postgres;
revoke all on function public.redeem_member_invite(text) from public,anon,authenticated,service_role;
alter function public.peek_member_invite(text) owner to postgres;
revoke all on function public.peek_member_invite(text) from public,anon,authenticated,service_role;
grant execute on function app.member_adult_on(date) to authenticated,service_role;
grant execute on function app.member_is_minor_on(date,date) to authenticated,service_role;
grant execute on function app.gym_today(uuid) to authenticated,service_role;
grant execute on function app.member_guardian_complete(public.members) to authenticated,service_role;
grant execute on function app.member_guardian_consent_state(uuid,uuid) to authenticated,service_role;
grant execute on function app.member_scoring_state(uuid,uuid,date) to authenticated,service_role;
grant execute on function app.member_scoring_eligible(uuid,uuid,date) to authenticated,service_role;
grant execute on function app.member_invite_email(public.members,date) to authenticated,service_role;
grant execute on function app.member_invite_guardian_ok(public.members,date) to authenticated,service_role;
grant execute on function app.member_contact_phone(uuid,uuid) to authenticated,service_role;
grant execute on function app.member_contact_email(uuid,uuid) to authenticated,service_role;
grant execute on function public.attest_members_without_dob_adult() to authenticated;
grant execute on function public.set_member_age_guardian(uuid,date,text,public.guardian_relation,text,text) to authenticated;
grant execute on function public.record_guardian_consent(uuid,boolean,text,text) to authenticated;
grant execute on function public.transition_member_to_own_account(uuid,text) to authenticated;
grant execute on function public.read_member_guardian(uuid) to authenticated;
grant execute on function public.read_guardian_coverage() to authenticated;
grant execute on function public.list_guardian_attention(text) to authenticated;
grant execute on function public.issue_member_invite(uuid,text) to authenticated;
grant execute on function public.redeem_member_invite(text) to authenticated;
grant execute on function public.peek_member_invite(text) to anon,authenticated;
revoke all on function app.enforce_notification() from public,anon,authenticated;
revoke all on function public.open_notification_whatsapp(uuid) from public,anon;
grant execute on function public.open_notification_whatsapp(uuid) to authenticated;

