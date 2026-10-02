-- CLS-001..040: materialised classes, private member projection and transactional bookings.
-- Contract: openspec/changes/classes/proposal.md and batch-2 decisions.
create type public.class_session_status as enum ('scheduled', 'cancelled');

alter table public.organization_settings
  add column class_cancel_window_hours integer not null default 2
    constraint organization_settings_class_cancel_window_hours_chk check (class_cancel_window_hours between 0 and 168),
  add column class_allow_cross_branch boolean not null default false;

create table public.services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  name text not null constraint services_name_chk check (char_length(btrim(name)) between 1 and 80 and name = btrim(name)),
  description text constraint services_description_chk check (description is null or char_length(description) <= 500),
  default_duration_minutes integer not null constraint services_default_duration_minutes_chk check (default_duration_minutes between 5 and 480),
  default_capacity integer not null constraint services_default_capacity_chk check (default_capacity between 1 and 500),
  is_active boolean not null default true,
  sort_order smallint not null default 0 constraint services_sort_order_chk check (sort_order between 0 and 1000),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint services_tenant_id_id_key unique (tenant_id,id)
);
create table public.class_rules (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
  service_id uuid not null, branch_id uuid not null,
  weekday smallint not null constraint class_rules_weekday_chk check (weekday between 0 and 6),
  start_time time not null,
  duration_minutes integer not null constraint class_rules_duration_minutes_chk check (duration_minutes between 5 and 480),
  capacity integer not null constraint class_rules_capacity_chk check (capacity between 1 and 500),
  trainer_staff_id uuid, valid_from date not null, valid_until date, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint class_rules_tenant_id_id_key unique (tenant_id,id),
  constraint class_rules_service_id_fkey foreign key (tenant_id,service_id) references public.services(tenant_id,id),
  constraint class_rules_branch_id_fkey foreign key (tenant_id,branch_id) references public.branches(tenant_id,id),
  constraint class_rules_trainer_staff_id_fkey foreign key (tenant_id,trainer_staff_id) references public.staff(tenant_id,id),
  constraint class_rules_validity_chk check (valid_until is null or valid_until >= valid_from)
);
create table public.class_sessions (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
  service_id uuid not null, branch_id uuid not null, rule_id uuid,
  session_date date not null, starts_at timestamptz not null, ends_at timestamptz not null,
  capacity integer not null constraint class_sessions_capacity_chk check (capacity between 1 and 500),
  trainer_staff_id uuid, status public.class_session_status not null default 'scheduled',
  customised_at timestamptz, cancelled_at timestamptz, cancel_reason text, cancelled_by_staff_id uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint class_sessions_tenant_id_id_key unique (tenant_id,id),
  constraint class_sessions_service_id_fkey foreign key (tenant_id,service_id) references public.services(tenant_id,id),
  constraint class_sessions_branch_id_fkey foreign key (tenant_id,branch_id) references public.branches(tenant_id,id),
  constraint class_sessions_rule_id_fkey foreign key (tenant_id,rule_id) references public.class_rules(tenant_id,id),
  constraint class_sessions_trainer_staff_id_fkey foreign key (tenant_id,trainer_staff_id) references public.staff(tenant_id,id),
  constraint class_sessions_cancelled_by_staff_id_fkey foreign key (tenant_id,cancelled_by_staff_id) references public.staff(tenant_id,id),
  constraint class_sessions_window_chk check (ends_at > starts_at and ends_at <= starts_at + interval '480 minutes'),
  constraint class_sessions_cancel_state_chk check ((status = 'cancelled') = (cancelled_at is not null and cancel_reason is not null and cancelled_by_staff_id is not null))
);
create table public.class_bookings (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
  session_id uuid not null, member_id uuid not null, status public.booking_status not null default 'booked',
  booked_at timestamptz not null default now(), cancelled_at timestamptz, cancel_reason text, marked_at timestamptz,
  acted_by_staff_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint class_bookings_session_id_fkey foreign key (tenant_id,session_id) references public.class_sessions(tenant_id,id),
  constraint class_bookings_member_id_fkey foreign key (tenant_id,member_id) references public.members(tenant_id,id),
  constraint class_bookings_acted_by_staff_id_fkey foreign key (tenant_id,acted_by_staff_id) references public.staff(tenant_id,id),
  constraint class_bookings_tenant_id_session_id_member_id_key unique (tenant_id,session_id,member_id),
  constraint class_bookings_cancel_evidence_chk check ((status in ('cancelled_by_member','cancelled_by_gym','session_cancelled')) = (cancelled_at is not null)),
  constraint class_bookings_mark_evidence_chk check ((status in ('attended','no_show')) = (marked_at is not null)),
  constraint class_bookings_gym_cancel_reason_chk check (status <> 'cancelled_by_gym' or cancel_reason is not null)
);

create unique index services_tenant_id_name_lower_key on public.services(tenant_id,lower(btrim(name)));
create index services_tenant_id_is_active_sort_order_idx on public.services(tenant_id,is_active,sort_order);
create index class_rules_tenant_id_service_id_idx on public.class_rules(tenant_id,service_id);
create index class_rules_tenant_id_branch_id_weekday_idx on public.class_rules(tenant_id,branch_id,weekday);
create index class_rules_tenant_id_trainer_staff_id_idx on public.class_rules(tenant_id,trainer_staff_id);
create unique index class_rules_slot_active_key on public.class_rules(tenant_id,branch_id,service_id,weekday,start_time) where is_active;
create unique index class_sessions_tenant_id_rule_id_session_date_key on public.class_sessions(tenant_id,rule_id,session_date) where rule_id is not null;
create unique index class_sessions_one_off_slot_key on public.class_sessions(tenant_id,branch_id,service_id,starts_at) where rule_id is null and status = 'scheduled';
create index class_sessions_tenant_id_branch_id_session_date_idx on public.class_sessions(tenant_id,branch_id,session_date);
create index class_sessions_tenant_id_service_id_starts_at_idx on public.class_sessions(tenant_id,service_id,starts_at);
create index class_sessions_tenant_id_starts_at_idx on public.class_sessions(tenant_id,starts_at);
create index class_sessions_tenant_id_trainer_staff_id_starts_at_idx on public.class_sessions(tenant_id,trainer_staff_id,starts_at);
create index class_sessions_tenant_id_cancelled_by_staff_id_idx on public.class_sessions(tenant_id,cancelled_by_staff_id) where cancelled_by_staff_id is not null;
create index class_bookings_tenant_id_session_id_status_idx on public.class_bookings(tenant_id,session_id,status);
create index class_bookings_tenant_id_member_id_status_idx on public.class_bookings(tenant_id,member_id,status);
create index class_bookings_tenant_id_acted_by_staff_id_idx on public.class_bookings(tenant_id,acted_by_staff_id) where acted_by_staff_id is not null;

alter table public.services enable row level security;
alter table public.class_rules enable row level security;
alter table public.class_sessions enable row level security;
alter table public.class_bookings enable row level security;
create policy services_tenant_select on public.services for select to authenticated using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));
create policy services_platform_select on public.services for select to authenticated using ((select app.is_platform()));
create policy class_rules_tenant_select on public.class_rules for select to authenticated using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));
create policy class_rules_platform_select on public.class_rules for select to authenticated using ((select app.is_platform()));
create policy class_sessions_tenant_select on public.class_sessions for select to authenticated using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));
create policy class_sessions_platform_select on public.class_sessions for select to authenticated using ((select app.is_platform()));
create policy class_bookings_tenant_select on public.class_bookings for select to authenticated using (tenant_id = (select app.current_tenant_id()) and (select app.is_staff()));
create policy class_bookings_platform_select on public.class_bookings for select to authenticated using ((select app.is_platform()));
revoke all on public.services, public.class_rules, public.class_sessions, public.class_bookings from anon, authenticated;
grant select on public.services, public.class_rules, public.class_sessions, public.class_bookings to authenticated;

create function app.enforce_class_rule() returns trigger language plpgsql security invoker set search_path = '' as $fn$
begin
  if (new.service_id,new.branch_id,new.weekday,new.start_time,new.created_at)
     is distinct from (old.service_id,old.branch_id,old.weekday,old.start_time,old.created_at) then
    raise exception 'Rule identity is immutable' using errcode = '23514';
  end if;
  new.updated_at := statement_timestamp(); return new;
end $fn$;

create function app.enforce_class_session() returns trigger language plpgsql security invoker set search_path = '' as $fn$
begin
  if (new.service_id,new.branch_id,new.rule_id,new.created_at) is distinct from (old.service_id,old.branch_id,old.rule_id,old.created_at)
     or (old.rule_id is not null and new.session_date is distinct from old.session_date) then
    raise exception 'Session identity is immutable' using errcode = '23514';
  end if;
  if old.status = 'cancelled' and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then
    raise exception 'Session is closed' using errcode = 'GL111';
  end if;
  new.updated_at := statement_timestamp(); return new;
end $fn$;
create function app.enforce_class_booking() returns trigger language plpgsql security invoker set search_path = '' as $fn$
begin
  if (new.session_id,new.member_id,new.created_at) is distinct from (old.session_id,old.member_id,old.created_at) then
    raise exception 'Booking identity is immutable' using errcode = '23514';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'booked' and new.status in ('cancelled_by_member','cancelled_by_gym','session_cancelled','attended','no_show'))
    or (old.status in ('cancelled_by_member','cancelled_by_gym') and new.status = 'booked')
    or (old.status = 'attended' and new.status in ('booked','no_show'))
    or (old.status = 'no_show' and new.status in ('booked','attended'))) then
    raise exception 'Booking transition refused' using errcode = 'GL113';
  end if;
  if old.status = 'booked' and new.status = 'session_cancelled' and not exists (
    select 1 from public.class_sessions s where s.tenant_id = new.tenant_id and s.id = new.session_id and s.status = 'cancelled') then
    raise exception 'Session must be cancelled first' using errcode = 'GL113';
  end if;
  new.updated_at := statement_timestamp(); return new;
end $fn$;
create trigger services_touch_updated_at before update on public.services for each row execute function app.touch_updated_at();
create trigger class_rules_touch_updated_at before update on public.class_rules for each row execute function app.enforce_class_rule();
create trigger class_sessions_touch_updated_at before update on public.class_sessions for each row execute function app.enforce_class_session();
create trigger class_bookings_touch_updated_at before update on public.class_bookings for each row execute function app.enforce_class_booking();

create function app.class_staff_actor(p_roles text[])
returns table(tenant_id uuid,staff_id uuid,user_id uuid,role public.app_role)
language plpgsql stable security invoker set search_path = '' as $fn$
begin
  if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
     or app.current_member_id() is not null or app.current_impersonation_id() is not null
     or not coalesce(app.current_app_role() = any(p_roles),false) then
    raise exception 'Real staff identity required' using errcode = '42501';
  end if;
  return query select s.tenant_id,s.id,s.user_id,s.role from public.staff s
    where s.tenant_id = app.current_tenant_id() and s.id = app.current_staff_id()
      and s.user_id = auth.uid() and s.role::text = app.current_app_role() and s.is_active;
  if not found then raise exception 'Real staff identity required' using errcode = '42501'; end if;
exception when invalid_text_representation then raise exception 'Real staff identity required' using errcode = '42501';
end $fn$;
create function app.class_member_actor()
returns table(tenant_id uuid,member_id uuid,user_id uuid,branch_id uuid)
language plpgsql stable security invoker set search_path = '' as $fn$
begin
  if auth.uid() is null or app.current_tenant_id() is null or app.current_member_id() is null
     or app.current_staff_id() is not null or app.current_impersonation_id() is not null
     or app.current_app_role() is distinct from 'member' then
    raise exception 'Real member identity required' using errcode = '42501';
  end if;
  return query select m.tenant_id,m.id,m.user_id,m.branch_id from public.members m
    where m.tenant_id = app.current_tenant_id() and m.id = app.current_member_id() and m.user_id = auth.uid()
      and m.status not in ('cancelled','blocked') and m.erased_at is null;
  if not found then raise exception 'Real member identity required' using errcode = '42501'; end if;
exception when invalid_text_representation then raise exception 'Real member identity required' using errcode = '42501';
end $fn$;
create function app.class_gym_eligible(p_tenant_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $fn$
  select exists(select 1 from public.organizations o where o.id = p_tenant_id
    and (o.status = 'active' or (o.status = 'trial' and o.trial_ends_at > statement_timestamp())))
$fn$;
create function app.class_branch_timezone(p_tenant_id uuid,p_branch_id uuid) returns text
language sql stable security invoker set search_path = '' as $fn$
  select coalesce((select z.name from public.branches b join pg_catalog.pg_timezone_names z on z.name = b.timezone
    where b.tenant_id = p_tenant_id and b.id = p_branch_id),
    (select z.name from public.organizations o join pg_catalog.pg_timezone_names z on z.name = o.timezone where o.id = p_tenant_id),'UTC')
$fn$;
create function app.class_local_instant(p_timezone text,p_day date,p_time time) returns timestamptz
language sql stable security invoker set search_path = '' as $fn$ select (p_day + p_time) at time zone p_timezone $fn$;
create function app.class_booking_holds(p_status public.booking_status) returns boolean
language sql immutable security invoker set search_path = '' as $fn$ select p_status in ('booked','attended','no_show') $fn$;
create function app.class_holding_count(p_tenant_id uuid,p_session_id uuid) returns integer
language sql stable security invoker set search_path = '' as $fn$
  select count(*)::integer from public.class_bookings b where b.tenant_id = p_tenant_id and b.session_id = p_session_id and app.class_booking_holds(b.status)
$fn$;

-- Commands require elevation: authenticated has SELECT only on feature tables and audit_log.
-- This private writer is not callable by any request role; command actors are revalidated first.
create function app.class_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_type text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if p_action is null or p_action not in ('service.created','service.updated','service.activated','service.deactivated',
    'class_rule.created','class_rule.updated','class_session.created','class_session.updated','class_session.cancelled',
    'class_sessions.pruned','class_booking.booked','class_booking.cancelled','class_booking.cancelled_by_gym','class_booking.attendance_marked') then
    raise exception 'Unknown class audit action' using errcode = '22023';
  end if;
  insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason,occurred_at)
    values(p_tenant_id,p_actor,p_role,p_action,p_record_type,p_record_id,p_before,p_after,p_reason,statement_timestamp());
end $fn$;

-- Only these locked, never-booked derived sessions may be deleted (CLS-007).
create function app.prune_class_sessions(p_tenant_id uuid,p_rule_id uuid,p_reason text) returns integer
language plpgsql volatile security definer set search_path = '' as $fn$
declare v_s public.class_sessions%rowtype; v_r public.class_rules%rowtype; v_count integer := 0;
begin
  if p_reason is null or p_reason not in ('holiday','rule_ended') or (p_reason = 'rule_ended' and p_rule_id is null) then
    raise exception 'Invalid prune reason' using errcode = '22023';
  end if;
  if p_rule_id is not null then select * into v_r from public.class_rules r where r.tenant_id = p_tenant_id and r.id = p_rule_id for update; end if;
  for v_s in select s.* from public.class_sessions s join public.class_rules r on r.tenant_id = s.tenant_id and r.id = s.rule_id
    where s.tenant_id = p_tenant_id and (p_rule_id is null or s.rule_id = p_rule_id)
      and s.rule_id is not null and s.customised_at is null and s.status = 'scheduled' and s.starts_at > statement_timestamp()
      and ((p_reason = 'holiday' and exists(select 1 from public.organization_holidays h where h.tenant_id = s.tenant_id and h.holiday_on = s.session_date))
        or (p_reason = 'rule_ended' and (not r.is_active or s.session_date < r.valid_from or s.session_date > r.valid_until)))
    order by s.starts_at,s.id loop
    perform app.booking_lock(p_tenant_id,'class_session',v_s.id);
    select * into v_s from public.class_sessions s where s.tenant_id = p_tenant_id and s.id = v_s.id for update;
    if found and v_s.customised_at is null and v_s.status = 'scheduled' and v_s.starts_at > statement_timestamp()
       and not exists(select 1 from public.class_bookings b where b.tenant_id = p_tenant_id and b.session_id = v_s.id) then
      delete from public.class_sessions s where s.tenant_id = p_tenant_id and s.id = v_s.id;
      v_count := v_count + 1;
    end if;
  end loop;
  if p_reason = 'holiday' and v_count > 0 then
    perform app.class_audit(p_tenant_id,auth.uid(),app.current_app_role()::public.app_role,'class_sessions.pruned','class_session',null,null,
      jsonb_build_object('reason','holiday','rule_id',p_rule_id,'count',v_count),null);
  end if;
  return v_count;
end $fn$;
create function app.generate_class_sessions(p_tenant_id uuid,p_rule_id uuid default null,p_service_id uuid default null) returns integer
language plpgsql volatile security definer set search_path = '' as $fn$
declare v_r public.class_rules%rowtype; v_day date; v_today date; v_zone text; v_start timestamptz; v_start_date date; v_count integer := 0; v_n integer;
begin
  if not app.class_gym_eligible(p_tenant_id) then return 0; end if;
  for v_r in select r.* from public.class_rules r join public.services s on s.tenant_id = r.tenant_id and s.id = r.service_id
    where r.tenant_id = p_tenant_id and (p_rule_id is null or r.id = p_rule_id) and (p_service_id is null or r.service_id = p_service_id)
      and r.is_active and s.is_active order by r.id for update of r loop
    perform app.prune_class_sessions(p_tenant_id,v_r.id,'holiday');
    v_zone := app.class_branch_timezone(p_tenant_id,v_r.branch_id);
    v_today := (statement_timestamp() at time zone v_zone)::date;
    for v_day in select v_today + g.n from pg_catalog.generate_series(0,27) g(n) loop
      if extract(dow from v_day)::smallint <> v_r.weekday or v_day < v_r.valid_from or v_day > v_r.valid_until
        or exists(select 1 from public.organization_holidays h where h.tenant_id = p_tenant_id and h.holiday_on = v_day) then continue; end if;
      v_start := app.class_local_instant(v_zone,v_day,v_r.start_time);
      v_start_date := (v_start at time zone v_zone)::date;
      if v_start_date <> v_day or v_start <= statement_timestamp() then continue; end if;
      insert into public.class_sessions(tenant_id,service_id,branch_id,rule_id,session_date,starts_at,ends_at,capacity,trainer_staff_id)
        values(p_tenant_id,v_r.service_id,v_r.branch_id,v_r.id,v_start_date,v_start,v_start + v_r.duration_minutes * interval '1 minute',v_r.capacity,v_r.trainer_staff_id)
        on conflict (tenant_id,rule_id,session_date) where rule_id is not null do nothing;
      get diagnostics v_n = row_count; v_count := v_count + v_n;
    end loop;
  end loop;
  return v_count;
end $fn$;

create function public.create_service(p_name text,p_description text,p_default_duration_minutes integer,p_default_capacity integer,p_sort_order integer) returns uuid
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; v_id uuid;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 or char_length(btrim(p_description)) > 500
    or p_default_duration_minutes is null or p_default_duration_minutes not between 5 and 480
    or p_default_capacity is null or p_default_capacity not between 1 and 500 or p_sort_order is null or p_sort_order not between 0 and 1000 then
    raise exception 'Invalid service fields' using errcode = '22023'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode = '42501'; end if;
  -- Serialize the catalogue cap; no count taken before this lock is trusted.
  perform 1 from public.organizations o where o.id = a.tenant_id for update;
  if (select count(*) from public.services s where s.tenant_id = a.tenant_id) >= 50 then raise exception 'Catalogue limit reached' using errcode = 'GL114'; end if;
  insert into public.services(tenant_id,name,description,default_duration_minutes,default_capacity,sort_order)
    values(a.tenant_id,btrim(p_name),nullif(btrim(p_description),''),p_default_duration_minutes,p_default_capacity,p_sort_order) returning id into v_id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'service.created','service',v_id,null,
    jsonb_build_object('name',btrim(p_name),'default_duration_minutes',p_default_duration_minutes,'default_capacity',p_default_capacity,'sort_order',p_sort_order,'is_active',true),null);
  return v_id;
end $fn$;
create function public.update_service(p_service_id uuid,p_name text,p_description text,p_default_duration_minutes integer,p_default_capacity integer,p_sort_order integer) returns void
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; s public.services%rowtype; v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb; k text; oldj jsonb; newj jsonb;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_service_id is null or p_name is null or char_length(btrim(p_name)) not between 1 and 80 or char_length(btrim(p_description)) > 500
    or p_default_duration_minutes is null or p_default_duration_minutes not between 5 and 480
    or p_default_capacity is null or p_default_capacity not between 1 and 500 or p_sort_order is null or p_sort_order not between 0 and 1000 then
    raise exception 'Invalid service fields' using errcode = '22023'; end if;
  select * into s from public.services t where t.tenant_id = a.tenant_id and t.id = p_service_id for update;
  if not found then raise exception 'Service unavailable' using errcode = '42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode = '42501'; end if;
  oldj := jsonb_build_object('name',s.name,'description',s.description,'default_duration_minutes',s.default_duration_minutes,'default_capacity',s.default_capacity,'sort_order',s.sort_order);
  newj := jsonb_build_object('name',btrim(p_name),'description',nullif(btrim(p_description),''),'default_duration_minutes',p_default_duration_minutes,'default_capacity',p_default_capacity,'sort_order',p_sort_order);
  for k in select jsonb_object_keys(newj) loop
    if oldj->k is distinct from newj->k then v_before := v_before || jsonb_build_object(k,oldj->k); v_after := v_after || jsonb_build_object(k,newj->k); end if;
  end loop;
  if v_after = '{}'::jsonb then return; end if;
  update public.services t set name=btrim(p_name),description=nullif(btrim(p_description),''),default_duration_minutes=p_default_duration_minutes,default_capacity=p_default_capacity,sort_order=p_sort_order where t.tenant_id=a.tenant_id and t.id=s.id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'service.updated','service',s.id,v_before,v_after,null);
end $fn$;
create function public.set_service_active(p_service_id uuid,p_is_active boolean) returns boolean
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; s public.services%rowtype;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_service_id is null or p_is_active is null then raise exception 'Invalid service fields' using errcode='22023'; end if;
  select * into s from public.services t where t.tenant_id=a.tenant_id and t.id=p_service_id for update;
  if not found then raise exception 'Service unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  if s.is_active = p_is_active then return false; end if;
  update public.services t set is_active=p_is_active where t.tenant_id=a.tenant_id and t.id=s.id;
  if p_is_active then perform app.generate_class_sessions(a.tenant_id,null,s.id); end if;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,case when p_is_active then 'service.activated' else 'service.deactivated' end,'service',s.id,
    jsonb_build_object('is_active',s.is_active),jsonb_build_object('is_active',p_is_active),null);
  return true;
end $fn$;

create function public.create_class_rules(p_service_id uuid,p_branch_id uuid,p_weekdays smallint[],p_start_time time,p_duration_minutes integer,p_capacity integer,p_trainer_staff_id uuid,p_valid_from date,p_valid_until date)
returns table(rule_id uuid,weekday smallint,sessions_created integer)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare a record; v_service public.services%rowtype; v_day smallint; v_from date; v_id uuid; v_count integer;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_service_id is null or p_branch_id is null or p_start_time is null or p_start_time >= time '24:00' or p_duration_minutes is null or p_duration_minutes not between 5 and 480
    or p_capacity is null or p_capacity not between 1 and 500 or p_weekdays is null or cardinality(p_weekdays) not between 1 and 7
    or exists(select 1 from unnest(p_weekdays) d where d is null or d not between 0 and 6)
    or (select count(distinct d) from unnest(p_weekdays) d) <> cardinality(p_weekdays) then raise exception 'Invalid weekly rule' using errcode='22023'; end if;
  select * into v_service from public.services s where s.tenant_id=a.tenant_id and s.id=p_service_id;
  if not found or not exists(select 1 from public.branches b where b.tenant_id=a.tenant_id and b.id=p_branch_id)
    or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id)) then
    raise exception 'Reference unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  if not v_service.is_active then raise exception 'Service inactive' using errcode='GL110'; end if;
  v_from := coalesce(p_valid_from,(statement_timestamp() at time zone app.class_branch_timezone(a.tenant_id,p_branch_id))::date);
  if p_valid_until < v_from or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id and t.is_active
    and t.role in ('trainer','gym_manager','gym_owner') and (t.branch_id is null or t.branch_id=p_branch_id))) then raise exception 'Invalid trainer or validity' using errcode='22023'; end if;
  perform 1 from public.organizations o where o.id=a.tenant_id for update;
  if (select count(*) from public.class_rules r where r.tenant_id=a.tenant_id and r.is_active)+cardinality(p_weekdays) > 200 then raise exception 'Rule limit reached' using errcode='GL114'; end if;
  foreach v_day in array p_weekdays loop
    insert into public.class_rules(tenant_id,service_id,branch_id,weekday,start_time,duration_minutes,capacity,trainer_staff_id,valid_from,valid_until)
      values(a.tenant_id,p_service_id,p_branch_id,v_day,p_start_time,p_duration_minutes,p_capacity,p_trainer_staff_id,v_from,p_valid_until) returning id into v_id;
    perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_rule.created','class_rule',v_id,null,
      jsonb_build_object('service_id',p_service_id,'branch_id',p_branch_id,'weekday',v_day,'start_time',to_char(p_start_time,'HH24:MI'),'duration_minutes',p_duration_minutes,
        'capacity',p_capacity,'trainer_staff_id',p_trainer_staff_id,'valid_from',v_from,'valid_until',p_valid_until),null);
    v_count := app.generate_class_sessions(a.tenant_id,v_id,null);
    return query select v_id,v_day,v_count;
  end loop;
end $fn$;
create function public.update_class_rule(p_rule_id uuid,p_duration_minutes integer,p_capacity integer,p_trainer_staff_id uuid,p_valid_until date,p_is_active boolean)
returns table(sessions_created integer,sessions_updated integer,sessions_removed integer,sessions_kept integer)
language plpgsql volatile security definer set search_path = '' as $fn$
#variable_conflict use_column
declare a record; r public.class_rules%rowtype; s public.class_sessions%rowtype; m record; v_now timestamptz := statement_timestamp();
  v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb; oldj jsonb; newj jsonb; k text;
  v_created integer := 0; v_updated integer := 0; v_removed integer := 0; v_kept integer := 0; v_end timestamptz;
  v_notice uuid; v_zone text; v_name text; v_trainer text; v_key text;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_rule_id is null or p_duration_minutes is null or p_duration_minutes not between 5 and 480 or p_capacity is null or p_capacity not between 1 and 500 or p_is_active is null then
    raise exception 'Invalid rule fields' using errcode='22023'; end if;
  -- The same catalogue mutex as creation prevents concurrent reactivations exceeding the cap.
  perform 1 from public.organizations o where o.id=a.tenant_id for update;
  select * into r from public.class_rules t where t.tenant_id=a.tenant_id and t.id=p_rule_id for update;
  if not found or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id)) then raise exception 'Reference unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  if p_valid_until < r.valid_from or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id and t.is_active
    and t.role in ('trainer','gym_manager','gym_owner') and (t.branch_id is null or t.branch_id=r.branch_id))) then raise exception 'Invalid trainer or validity' using errcode='22023'; end if;
  if p_is_active and not r.is_active and (select count(*) from public.class_rules t where t.tenant_id=a.tenant_id and t.is_active)>=200 then
    raise exception 'Rule limit reached' using errcode='GL114'; end if;
  oldj := jsonb_build_object('duration_minutes',r.duration_minutes,'capacity',r.capacity,'trainer_staff_id',r.trainer_staff_id,'valid_until',r.valid_until,'is_active',r.is_active);
  newj := jsonb_build_object('duration_minutes',p_duration_minutes,'capacity',p_capacity,'trainer_staff_id',p_trainer_staff_id,'valid_until',p_valid_until,'is_active',p_is_active);
  for k in select jsonb_object_keys(newj) loop if oldj->k is distinct from newj->k then v_before := v_before || jsonb_build_object(k,oldj->k); v_after := v_after || jsonb_build_object(k,newj->k); end if; end loop;
  if v_after = '{}'::jsonb then return query select 0,0,0,0; return; end if;
  update public.class_rules t set duration_minutes=p_duration_minutes,capacity=p_capacity,trainer_staff_id=p_trainer_staff_id,valid_until=p_valid_until,is_active=p_is_active where t.tenant_id=a.tenant_id and t.id=r.id;
  for s in select t.* from public.class_sessions t where t.tenant_id=a.tenant_id and t.rule_id=r.id and t.starts_at > v_now and t.status='scheduled' and t.customised_at is null order by t.starts_at,t.id loop
    perform app.booking_lock(a.tenant_id,'class_session',s.id);
    select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=s.id for update;
    if not found or s.starts_at <= v_now or s.status <> 'scheduled' or s.customised_at is not null then continue; end if;
    if not p_is_active or s.session_date > p_valid_until then
      if exists(select 1 from public.class_bookings b where b.tenant_id=a.tenant_id and b.session_id=s.id) then v_kept := v_kept+1;
      else delete from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=s.id; v_removed := v_removed+1; end if;
      continue;
    end if;
    v_end := s.starts_at + p_duration_minutes * interval '1 minute';
    if app.class_holding_count(a.tenant_id,s.id) > 0 and v_end is distinct from s.ends_at then v_end := s.ends_at; v_kept := v_kept+1; end if;
    if (s.capacity,s.trainer_staff_id,s.ends_at) is distinct from (p_capacity,p_trainer_staff_id,v_end) then
      update public.class_sessions t set capacity=p_capacity,trainer_staff_id=p_trainer_staff_id,ends_at=v_end where t.tenant_id=a.tenant_id and t.id=s.id;
      v_updated := v_updated+1;
      if s.trainer_staff_id is distinct from p_trainer_staff_id and p_trainer_staff_id is not null then
        v_zone := app.class_branch_timezone(a.tenant_id,s.branch_id);
        select t.name into v_name from public.services t where t.tenant_id=a.tenant_id and t.id=s.service_id;
        select t.full_name into v_trainer from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id;
        for m in select t.id,t.status,t.erased_at from public.members t join public.class_bookings b on b.tenant_id=t.tenant_id and b.member_id=t.id
          where b.tenant_id=a.tenant_id and b.session_id=s.id and b.status='booked' order by t.id for update of t loop
          if m.status in ('cancelled','blocked') or m.erased_at is not null then continue; end if;
          v_key := 'class-trainer:'||s.id||':'||m.id||':'||p_trainer_staff_id||':'||(extract(epoch from v_now)*1000000)::bigint::text;
          v_notice := null;
          insert into public.notifications(tenant_id,member_id,channel,category,template_key,related_type,related_id,scheduled_for,dedupe_key,payload)
            values(a.tenant_id,m.id,'in_app','class_update','class_trainer_changed','class_session',s.id,v_now,v_key,
              jsonb_build_object('kind','class_trainer_changed','sessionId',s.id,'trainerName',v_trainer,
                'body',v_name||' on '||to_char(s.starts_at at time zone v_zone,'FMDD Mon YYYY "at" FMHH12:MI am')||' will now be led by '||v_trainer))
            on conflict do nothing returning id into v_notice;
          if v_notice is not null then update public.notifications n set status='sent',sent_at=v_now where n.tenant_id=a.tenant_id and n.id=v_notice; end if;
        end loop;
      end if;
    end if;
  end loop;
  v_created := app.generate_class_sessions(a.tenant_id,r.id,null);
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_rule.updated','class_rule',r.id,v_before,
    v_after||jsonb_build_object('effects',jsonb_build_object('created',v_created,'updated',v_updated,'removed',v_removed,'kept',v_kept)),null);
  return query select v_created,v_updated,v_removed,v_kept;
end $fn$;

create function public.create_class_session(p_service_id uuid,p_branch_id uuid,p_session_date date,p_start_time time,p_duration_minutes integer,p_capacity integer,p_trainer_staff_id uuid) returns uuid
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; s public.services%rowtype; v_start timestamptz; v_start_date date; v_today date; v_id uuid; v_zone text;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_service_id is null or p_branch_id is null or p_session_date is null or p_start_time is null or p_start_time >= time '24:00' or p_duration_minutes is null or p_duration_minutes not between 5 and 480
    or p_capacity is null or p_capacity not between 1 and 500 then raise exception 'Invalid session fields' using errcode='22023'; end if;
  select * into s from public.services t where t.tenant_id=a.tenant_id and t.id=p_service_id;
  if not found or not exists(select 1 from public.branches t where t.tenant_id=a.tenant_id and t.id=p_branch_id)
    or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id)) then raise exception 'Reference unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  if not s.is_active then raise exception 'Service inactive' using errcode='GL110'; end if;
  v_zone := app.class_branch_timezone(a.tenant_id,p_branch_id); v_start := app.class_local_instant(v_zone,p_session_date,p_start_time); v_today := (statement_timestamp() at time zone v_zone)::date;
  v_start_date := (v_start at time zone v_zone)::date;
  if v_start_date <> p_session_date or v_start <= statement_timestamp() or p_session_date < v_today or p_session_date > v_today+27
    or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id and t.is_active
      and t.role in ('trainer','gym_manager','gym_owner') and (t.branch_id is null or t.branch_id=p_branch_id))) then raise exception 'Invalid trainer or date' using errcode='22023'; end if;
  insert into public.class_sessions(tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,trainer_staff_id)
    values(a.tenant_id,p_service_id,p_branch_id,v_start_date,v_start,v_start+p_duration_minutes*interval '1 minute',p_capacity,p_trainer_staff_id) returning id into v_id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_session.created','class_session',v_id,null,
    jsonb_build_object('service_id',p_service_id,'branch_id',p_branch_id,'session_date',v_start_date,'starts_at',v_start,'ends_at',v_start+p_duration_minutes*interval '1 minute','capacity',p_capacity,'trainer_staff_id',p_trainer_staff_id,'rule_id',null),null);
  return v_id;
end $fn$;

create function public.update_class_session(p_session_id uuid,p_session_date date,p_start_time time,p_duration_minutes integer,p_capacity integer,p_trainer_staff_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; s public.class_sessions%rowtype; m record; v_start timestamptz; v_end timestamptz; v_now timestamptz := statement_timestamp();
  oldj jsonb; newj jsonb; v_before jsonb := '{}'::jsonb; v_after jsonb := '{}'::jsonb; k text;
  v_zone text; v_start_date date; v_name text; v_trainer text; v_notice uuid; v_key text;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_session_id is null or p_session_date is null or p_start_time is null or p_start_time >= time '24:00' or p_duration_minutes is null or p_duration_minutes not between 5 and 480 or p_capacity is null or p_capacity not between 1 and 500 then raise exception 'Invalid session fields' using errcode='22023'; end if;
  if not exists(select 1 from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=p_session_id)
    or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id)) then raise exception 'Reference unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  perform app.booking_lock(a.tenant_id,'class_session',p_session_id);
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=p_session_id for update;
  if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
  if s.status='cancelled' or s.ends_at <= v_now then raise exception 'Session closed' using errcode='GL111'; end if;
  v_zone := app.class_branch_timezone(a.tenant_id,s.branch_id); v_start := app.class_local_instant(v_zone,p_session_date,p_start_time); v_end := v_start+p_duration_minutes*interval '1 minute';
  v_start_date := (v_start at time zone v_zone)::date;
  if v_start_date <> p_session_date or (s.rule_id is not null and s.session_date<>v_start_date)
    or (v_start is distinct from s.starts_at and v_start <= v_now)
    or (p_trainer_staff_id is not null and not exists(select 1 from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id and t.is_active
      and t.role in ('trainer','gym_manager','gym_owner') and (t.branch_id is null or t.branch_id=s.branch_id))) then raise exception 'Invalid trainer or date' using errcode='22023'; end if;
  if (v_start,v_end) is distinct from (s.starts_at,s.ends_at) and app.class_holding_count(a.tenant_id,s.id)>0 then raise exception 'Session has bookings' using errcode='GL112'; end if;
  oldj := jsonb_build_object('starts_at',s.starts_at,'ends_at',s.ends_at,'capacity',s.capacity,'trainer_staff_id',s.trainer_staff_id);
  newj := jsonb_build_object('starts_at',v_start,'ends_at',v_end,'capacity',p_capacity,'trainer_staff_id',p_trainer_staff_id);
  for k in select jsonb_object_keys(newj) loop if oldj->k is distinct from newj->k then v_before := v_before||jsonb_build_object(k,oldj->k); v_after := v_after||jsonb_build_object(k,newj->k); end if; end loop;
  if v_after='{}'::jsonb then return; end if;
  update public.class_sessions t set session_date=v_start_date,starts_at=v_start,ends_at=v_end,capacity=p_capacity,trainer_staff_id=p_trainer_staff_id,customised_at=coalesce(t.customised_at,v_now) where t.tenant_id=a.tenant_id and t.id=s.id;
  if s.trainer_staff_id is distinct from p_trainer_staff_id and p_trainer_staff_id is not null then
    select t.name into v_name from public.services t where t.tenant_id=a.tenant_id and t.id=s.service_id;
    select t.full_name into v_trainer from public.staff t where t.tenant_id=a.tenant_id and t.id=p_trainer_staff_id;
    for m in select t.id,t.status,t.erased_at from public.members t join public.class_bookings b on b.tenant_id=t.tenant_id and b.member_id=t.id
      where b.tenant_id=a.tenant_id and b.session_id=s.id and b.status='booked' order by t.id for update of t loop
      if m.status in ('cancelled','blocked') or m.erased_at is not null then continue; end if;
      v_key := 'class-trainer:'||s.id||':'||m.id||':'||p_trainer_staff_id||':'||(extract(epoch from v_now)*1000000)::bigint::text;
      v_notice := null;
      insert into public.notifications(tenant_id,member_id,channel,category,template_key,related_type,related_id,scheduled_for,dedupe_key,payload)
        values(a.tenant_id,m.id,'in_app','class_update','class_trainer_changed','class_session',s.id,v_now,v_key,
          jsonb_build_object('kind','class_trainer_changed','sessionId',s.id,'trainerName',v_trainer,
            'body',v_name||' on '||to_char(v_start at time zone v_zone,'FMDD Mon YYYY "at" FMHH12:MI am')||' will now be led by '||v_trainer))
        on conflict do nothing returning id into v_notice;
      if v_notice is not null then update public.notifications n set status='sent',sent_at=v_now where n.tenant_id=a.tenant_id and n.id=v_notice; end if;
    end loop;
  end if;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_session.updated','class_session',s.id,v_before,v_after,null);
end $fn$;

create function public.cancel_class_session(p_session_id uuid,p_reason text)
returns table(bookings_cancelled integer,notices_written integer,notices_withheld integer,members_without_app integer)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; s public.class_sessions%rowtype; m record; v_now timestamptz := statement_timestamp();
  v_cancelled integer := 0; v_written integer := 0; v_withheld integer := 0; v_noapp integer := 0;
  v_notice uuid; v_zone text; v_name text; v_key text;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager']);
  if p_session_id is null or p_reason is null or char_length(btrim(p_reason)) not between 3 and 200 then raise exception 'Invalid cancellation fields' using errcode='22023'; end if;
  if not exists(select 1 from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=p_session_id) then raise exception 'Session unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  perform app.booking_lock(a.tenant_id,'class_session',p_session_id);
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=p_session_id for update;
  if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
  if s.status='cancelled' or s.ends_at <= v_now then raise exception 'Session closed' using errcode='GL111'; end if;
  update public.class_sessions t set status='cancelled',cancelled_at=v_now,cancel_reason=btrim(p_reason),cancelled_by_staff_id=a.staff_id where t.tenant_id=a.tenant_id and t.id=s.id;
  v_zone := app.class_branch_timezone(a.tenant_id,s.branch_id);
  select t.name into v_name from public.services t where t.tenant_id=a.tenant_id and t.id=s.service_id;
  for m in select t.id,t.status,t.erased_at,t.user_id,b.id as booking_id from public.members t join public.class_bookings b on b.tenant_id=t.tenant_id and b.member_id=t.id
    where b.tenant_id=a.tenant_id and b.session_id=s.id and b.status='booked' order by t.id for update of t,b loop
    update public.class_bookings b set status='session_cancelled',cancelled_at=v_now,cancel_reason=null,marked_at=null,acted_by_staff_id=null where b.tenant_id=a.tenant_id and b.id=m.booking_id;
    v_cancelled := v_cancelled+1;
    if m.user_id is null then v_noapp := v_noapp+1; end if;
    if m.status in ('cancelled','blocked') or m.erased_at is not null then v_withheld := v_withheld+1; continue; end if;
    v_key := 'class-cancelled:'||s.id||':'||m.id; v_notice := null;
    insert into public.notifications(tenant_id,member_id,channel,category,template_key,related_type,related_id,scheduled_for,dedupe_key,payload)
      values(a.tenant_id,m.id,'in_app','class_update','class_session_cancelled','class_session',s.id,v_now,v_key,
        jsonb_build_object('kind','class_session_cancelled','sessionId',s.id,'reason',btrim(p_reason),
          'body',v_name||' on '||to_char(s.starts_at at time zone v_zone,'FMDD Mon YYYY "at" FMHH12:MI am')||' has been cancelled. Reason: '||btrim(p_reason)))
      on conflict do nothing returning id into v_notice;
    if v_notice is not null then update public.notifications n set status='sent',sent_at=v_now where n.tenant_id=a.tenant_id and n.id=v_notice; end if;
    v_written := v_written+1;
  end loop;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_session.cancelled','class_session',s.id,jsonb_build_object('status','scheduled'),
    jsonb_build_object('status','cancelled','bookings_cancelled',v_cancelled,'notices_written',v_written,'notices_withheld',v_withheld),btrim(p_reason));
  return query select v_cancelled,v_written,v_withheld,v_noapp;
end $fn$;

-- CLS-039 requires one booking core. Private invoker: only verified definer commands call it.
-- Lock order in every booking writer is advisory resource, session row, booking row.
create function app.class_book_core(p_tenant_id uuid,p_member_id uuid,p_staff_id uuid,p_actor uuid,p_role public.app_role,p_session_id uuid,p_desk boolean)
returns table(booking_id uuid,status public.booking_status,spots_left integer)
language plpgsql volatile security invoker set search_path = '' as $fn$
declare s public.class_sessions%rowtype; m public.members%rowtype; b public.class_bookings%rowtype; v_count integer; v_id uuid; v_cross boolean; v_now timestamptz := statement_timestamp(); v_service_active boolean;
begin
  if p_session_id is null or p_member_id is null then raise exception 'Invalid booking fields' using errcode='22023'; end if;
  if not exists(select 1 from public.class_sessions t where t.tenant_id=p_tenant_id and t.id=p_session_id)
    or not exists(select 1 from public.members t where t.tenant_id=p_tenant_id and t.id=p_member_id) then raise exception 'Reference unavailable' using errcode='42501'; end if;
  perform app.booking_lock(p_tenant_id,'class_session',p_session_id);
  select * into s from public.class_sessions t where t.tenant_id=p_tenant_id and t.id=p_session_id for update;
  if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
  select * into m from public.members t where t.tenant_id=p_tenant_id and t.id=p_member_id;
  select * into b from public.class_bookings t where t.tenant_id=p_tenant_id and t.session_id=p_session_id and t.member_id=p_member_id for update;
  select t.is_active into v_service_active from public.services t where t.tenant_id=p_tenant_id and t.id=s.service_id;
  if not app.class_gym_eligible(p_tenant_id) or s.status='cancelled' or not v_service_active
    or (not p_desk and (s.starts_at <= v_now or b.status='cancelled_by_gym')) or (p_desk and s.ends_at <= v_now) then raise exception 'Session not bookable' using errcode='GL092'; end if;
  select coalesce(t.class_allow_cross_branch,false) into v_cross from public.organization_settings t where t.tenant_id=p_tenant_id;
  if m.branch_id <> s.branch_id and not coalesce(v_cross,false) then raise exception 'Other branch' using errcode='GL094'; end if;
  if app.class_booking_holds(b.status) then raise exception 'Already booked' using errcode='GL091'; end if;
  if m.status in ('cancelled','blocked') or m.erased_at is not null or not app.member_has_live_membership(p_tenant_id,p_member_id,s.session_date) then raise exception 'Membership not live' using errcode='GL093'; end if;
  v_count := app.class_holding_count(p_tenant_id,s.id);
  if v_count >= s.capacity then raise exception 'Class full' using errcode='GL090'; end if;
  if b.id is null then
    insert into public.class_bookings(tenant_id,session_id,member_id,booked_at,acted_by_staff_id)
      values(p_tenant_id,s.id,m.id,v_now,p_staff_id) returning id into v_id;
  else
    update public.class_bookings t set status='booked',booked_at=v_now,cancelled_at=null,cancel_reason=null,marked_at=null,acted_by_staff_id=p_staff_id where t.tenant_id=p_tenant_id and t.id=b.id returning t.id into v_id;
  end if;
  perform app.class_audit(p_tenant_id,p_actor,p_role,'class_booking.booked','class_booking',v_id,
    case when b.id is null then null else jsonb_build_object('status',b.status) end,
    jsonb_build_object('session_id',s.id,'member_id',m.id,'status','booked','via',case when p_desk then 'desk' else 'member' end),null);
  return query select v_id,'booked'::public.booking_status,greatest(s.capacity-v_count-1,0);
end $fn$;
create function public.book_class_session(p_session_id uuid)
returns table(booking_id uuid,status public.booking_status,spots_left integer)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record;
begin
  select * into a from app.class_member_actor();
  return query select * from app.class_book_core(a.tenant_id,a.member_id,null,a.user_id,'member',p_session_id,false);
end $fn$;
create function public.desk_book_class_session(p_session_id uuid,p_member_id uuid)
returns table(booking_id uuid,status public.booking_status,spots_left integer)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager','front_desk']);
  return query select * from app.class_book_core(a.tenant_id,p_member_id,a.staff_id,a.user_id,a.role,p_session_id,true);
end $fn$;

create function public.cancel_class_booking(p_booking_id uuid)
returns table(booking_id uuid,status public.booking_status)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; b public.class_bookings%rowtype; s public.class_sessions%rowtype; v_hours integer;
begin
  select * into a from app.class_member_actor();
  if p_booking_id is null then raise exception 'Invalid booking fields' using errcode='22023'; end if;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.member_id=a.member_id and t.id=p_booking_id;
  if not found then raise exception 'Booking unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  perform app.booking_lock(a.tenant_id,'class_session',b.session_id);
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=b.session_id for update;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.member_id=a.member_id and t.id=p_booking_id for update;
  if b.status <> 'booked' then raise exception 'Booking state refused' using errcode='GL113'; end if;
  select t.class_cancel_window_hours into v_hours from public.organization_settings t where t.tenant_id=a.tenant_id;
  if statement_timestamp() > s.starts_at-coalesce(v_hours,2)*interval '1 hour' then raise exception 'Cancellation window closed' using errcode='GL095'; end if;
  update public.class_bookings t set status='cancelled_by_member',cancelled_at=statement_timestamp(),cancel_reason=null,acted_by_staff_id=null where t.tenant_id=a.tenant_id and t.id=b.id;
  perform app.class_audit(a.tenant_id,a.user_id,'member','class_booking.cancelled','class_booking',b.id,jsonb_build_object('status','booked'),jsonb_build_object('status','cancelled_by_member'),null);
  return query select b.id,'cancelled_by_member'::public.booking_status;
end $fn$;
create function public.desk_cancel_class_booking(p_booking_id uuid,p_reason text)
returns table(booking_id uuid,status public.booking_status)
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; b public.class_bookings%rowtype; s public.class_sessions%rowtype;
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager','front_desk']);
  if p_booking_id is null or p_reason is null or char_length(btrim(p_reason)) not between 3 and 200 then raise exception 'Invalid cancellation fields' using errcode='22023'; end if;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.id=p_booking_id;
  if not found then raise exception 'Booking unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  perform app.booking_lock(a.tenant_id,'class_session',b.session_id);
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=b.session_id for update;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.id=p_booking_id for update;
  if b.status <> 'booked' then raise exception 'Booking state refused' using errcode='GL113'; end if;
  if s.ends_at <= statement_timestamp() then raise exception 'Session closed' using errcode='GL111'; end if;
  update public.class_bookings t set status='cancelled_by_gym',cancelled_at=statement_timestamp(),cancel_reason=btrim(p_reason),acted_by_staff_id=a.staff_id where t.tenant_id=a.tenant_id and t.id=b.id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_booking.cancelled_by_gym','class_booking',b.id,jsonb_build_object('status','booked'),jsonb_build_object('status','cancelled_by_gym'),btrim(p_reason));
  return query select b.id,'cancelled_by_gym'::public.booking_status;
end $fn$;
create function public.mark_class_attendance(p_booking_id uuid,p_status public.booking_status) returns public.booking_status
language plpgsql volatile security definer set search_path = '' as $fn$
declare a record; b public.class_bookings%rowtype; s public.class_sessions%rowtype; v_now timestamptz := statement_timestamp();
begin
  select * into a from app.class_staff_actor(array['gym_owner','gym_manager','front_desk','trainer']);
  if p_booking_id is null or p_status is null or p_status not in ('booked','attended','no_show') then raise exception 'Invalid attendance fields' using errcode='22023'; end if;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.id=p_booking_id;
  if not found then raise exception 'Booking unavailable' using errcode='42501'; end if;
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=b.session_id;
  if a.role='trainer' and s.trainer_staff_id is distinct from a.staff_id then raise exception 'Booking unavailable' using errcode='42501'; end if;
  if not app.class_gym_eligible(a.tenant_id) then raise exception 'Gym unavailable' using errcode='42501'; end if;
  perform app.booking_lock(a.tenant_id,'class_session',b.session_id);
  select * into s from public.class_sessions t where t.tenant_id=a.tenant_id and t.id=b.session_id for update;
  select * into b from public.class_bookings t where t.tenant_id=a.tenant_id and t.id=p_booking_id for update;
  if a.role='trainer' and s.trainer_staff_id is distinct from a.staff_id then raise exception 'Booking unavailable' using errcode='42501'; end if;
  if b.status not in ('booked','attended','no_show') then raise exception 'Booking state refused' using errcode='GL113'; end if;
  if s.status='cancelled' or v_now > s.ends_at+interval '24 hours'
    or (p_status='attended' and v_now < s.starts_at-interval '60 minutes') or (p_status='no_show' and v_now < s.starts_at) then raise exception 'Session closed' using errcode='GL111'; end if;
  if b.status=p_status then return p_status; end if;
  update public.class_bookings t set status=p_status,marked_at=case when p_status='booked' then null else v_now end,acted_by_staff_id=a.staff_id where t.tenant_id=a.tenant_id and t.id=b.id;
  perform app.class_audit(a.tenant_id,a.user_id,a.role,'class_booking.attendance_marked','class_booking',b.id,jsonb_build_object('status',b.status),jsonb_build_object('status',p_status),null);
  return p_status;
end $fn$;

-- Members have no table policy; elevation exposes only aggregate counts and their own booking.
create function public.read_member_class_schedule(p_from date,p_to date)
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
    case when b.status='booked' then s.starts_at-coalesce(v_hours,2)*interval '1 hour' else null end
  from public.class_sessions s join public.services sv on sv.tenant_id=s.tenant_id and sv.id=s.service_id
    join public.branches br on br.tenant_id=s.tenant_id and br.id=s.branch_id
    left join public.staff tr on tr.tenant_id=s.tenant_id and tr.id=s.trainer_staff_id
    left join public.class_bookings b on b.tenant_id=s.tenant_id and b.session_id=s.id and b.member_id=a.member_id
    cross join lateral (select app.class_holding_count(s.tenant_id,s.id) as holding) c
  where s.tenant_id=a.tenant_id and (s.branch_id=a.branch_id or coalesce(v_cross,false)) and s.session_date between p_from and p_to
    and ((s.status='scheduled' and sv.is_active) or b.id is not null)
  order by s.starts_at,s.id;
end $fn$;

create function public.read_class_timetable(p_branch_id uuid,p_from date,p_to date)
returns table(session_id uuid,service_id uuid,service_name text,service_is_active boolean,branch_id uuid,session_date date,starts_at timestamptz,ends_at timestamptz,timezone text,trainer_staff_id uuid,trainer_name text,trainer_is_active boolean,capacity integer,booked_count integer,attended_count integer,no_show_count integer,spots_left integer,session_status public.class_session_status,cancel_reason text,rule_id uuid,is_customised boolean,on_holiday boolean,trainer_overlaps boolean)
language plpgsql stable security invoker set search_path = '' as $fn$
begin
  -- This explicit gate also makes platform RPC readers empty, retaining their direct SELECT policy.
  if app.is_staff() is not true then return; end if;
  if p_from is null or p_to is null or p_from > p_to or p_to-p_from > 30 then raise exception 'Invalid class window' using errcode='22023'; end if;
  return query select s.id,s.service_id,sv.name,sv.is_active,s.branch_id,s.session_date,s.starts_at,s.ends_at,
    app.class_branch_timezone(s.tenant_id,s.branch_id),s.trainer_staff_id,tr.full_name,tr.is_active,s.capacity,
    c.holding,c.attended,c.no_show,greatest(s.capacity-c.holding,0),s.status,s.cancel_reason,s.rule_id,s.customised_at is not null,
    exists(select 1 from public.organization_holidays h where h.tenant_id=s.tenant_id and h.holiday_on=s.session_date),
    exists(select 1 from public.class_sessions other where other.tenant_id=s.tenant_id and other.id<>s.id and other.trainer_staff_id=s.trainer_staff_id
      and other.status='scheduled' and s.status='scheduled' and other.starts_at<s.ends_at and other.ends_at>s.starts_at)
  from public.class_sessions s join public.services sv on sv.tenant_id=s.tenant_id and sv.id=s.service_id
    left join public.staff tr on tr.tenant_id=s.tenant_id and tr.id=s.trainer_staff_id
    cross join lateral (select count(*) filter(where app.class_booking_holds(b.status))::integer as holding,
      count(*) filter(where b.status='attended')::integer as attended,count(*) filter(where b.status='no_show')::integer as no_show
      from public.class_bookings b where b.tenant_id=s.tenant_id and b.session_id=s.id) c
  where s.tenant_id=(select app.current_tenant_id()) and (select app.is_staff()) and (p_branch_id is null or s.branch_id=p_branch_id)
    and s.session_date between p_from and p_to order by s.starts_at,s.id;
end $fn$;
create function public.read_class_roster(p_session_id uuid)
returns table(booking_id uuid,member_id uuid,member_name text,member_code text,member_phone text,has_app boolean,status public.booking_status,booked_at timestamptz,cancelled_at timestamptz,cancel_reason text,marked_at timestamptz,membership_live boolean,checked_in_at timestamptz)
language sql stable security invoker set search_path = '' as $fn$
  select b.id,m.id,m.full_name,m.member_code,m.phone,m.user_id is not null,b.status,b.booked_at,b.cancelled_at,b.cancel_reason,b.marked_at,
    app.member_has_live_membership(s.tenant_id,m.id,s.session_date),
    (select max(att.checked_in_at) from public.attendance att where att.tenant_id=s.tenant_id and att.member_id=m.id and att.branch_id=s.branch_id
      and att.checked_in_at >= app.class_local_instant(app.class_branch_timezone(s.tenant_id,s.branch_id),s.session_date,time '00:00')
      and att.checked_in_at < app.class_local_instant(app.class_branch_timezone(s.tenant_id,s.branch_id),s.session_date+1,time '00:00'))
  from public.class_bookings b join public.class_sessions s on s.tenant_id=b.tenant_id and s.id=b.session_id
    join public.members m on m.tenant_id=b.tenant_id and m.id=b.member_id
  where b.tenant_id=(select app.current_tenant_id()) and (select app.is_staff()) and b.session_id=p_session_id order by b.booked_at,b.id
$fn$;
create function public.run_class_generation_all() returns jsonb
language plpgsql volatile security invoker set search_path = '' as $fn$
declare v_tenant uuid; v_tenants integer := 0; v_created integer := 0;
begin
  for v_tenant in select o.id from public.organizations o where o.status='active' or (o.status='trial' and o.trial_ends_at>statement_timestamp()) order by o.id loop
    v_created := v_created+app.generate_class_sessions(v_tenant,null,null); v_tenants := v_tenants+1;
  end loop;
  return jsonb_build_object('tenants',v_tenants,'created',v_created);
end $fn$;

-- Explicit ownership and ACLs; no elevated function relies on defaults.
alter function app.class_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) owner to postgres;
alter function app.generate_class_sessions(uuid,uuid,uuid) owner to postgres;
alter function app.prune_class_sessions(uuid,uuid,text) owner to postgres;
revoke all on function app.class_audit(uuid,uuid,public.app_role,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function app.prune_class_sessions(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function app.generate_class_sessions(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function app.generate_class_sessions(uuid,uuid,uuid) to service_role;
revoke all on function app.class_book_core(uuid,uuid,uuid,uuid,public.app_role,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function app.class_staff_actor(text[]) from public,anon,authenticated,service_role;
revoke all on function app.class_member_actor() from public,anon,authenticated,service_role;
revoke all on function app.class_gym_eligible(uuid) from public,anon,authenticated,service_role;
revoke all on function app.enforce_class_rule(),app.enforce_class_session(),app.enforce_class_booking() from public,anon,authenticated;
revoke all on function app.class_holding_count(uuid,uuid),app.class_booking_holds(public.booking_status),app.class_branch_timezone(uuid,uuid),app.class_local_instant(text,date,time) from public,anon;
grant execute on function app.class_holding_count(uuid,uuid),app.class_booking_holds(public.booking_status),app.class_branch_timezone(uuid,uuid),app.class_local_instant(text,date,time) to authenticated,service_role;

alter function public.create_service(text,text,integer,integer,integer) owner to postgres;
alter function public.update_service(uuid,text,text,integer,integer,integer) owner to postgres;
alter function public.set_service_active(uuid,boolean) owner to postgres;
alter function public.create_class_rules(uuid,uuid,smallint[],time,integer,integer,uuid,date,date) owner to postgres;
alter function public.update_class_rule(uuid,integer,integer,uuid,date,boolean) owner to postgres;
alter function public.create_class_session(uuid,uuid,date,time,integer,integer,uuid) owner to postgres;
alter function public.update_class_session(uuid,date,time,integer,integer,uuid) owner to postgres;
alter function public.cancel_class_session(uuid,text) owner to postgres;
alter function public.book_class_session(uuid) owner to postgres;
alter function public.desk_book_class_session(uuid,uuid) owner to postgres;
alter function public.cancel_class_booking(uuid) owner to postgres;
alter function public.desk_cancel_class_booking(uuid,text) owner to postgres;
alter function public.mark_class_attendance(uuid,public.booking_status) owner to postgres;
alter function public.read_member_class_schedule(date,date) owner to postgres;
revoke all on function public.create_service(text,text,integer,integer,integer), public.update_service(uuid,text,text,integer,integer,integer), public.set_service_active(uuid,boolean),
  public.create_class_rules(uuid,uuid,smallint[],time,integer,integer,uuid,date,date), public.update_class_rule(uuid,integer,integer,uuid,date,boolean),
  public.create_class_session(uuid,uuid,date,time,integer,integer,uuid), public.update_class_session(uuid,date,time,integer,integer,uuid), public.cancel_class_session(uuid,text),
  public.book_class_session(uuid), public.desk_book_class_session(uuid,uuid), public.cancel_class_booking(uuid), public.desk_cancel_class_booking(uuid,text),
  public.mark_class_attendance(uuid,public.booking_status), public.read_member_class_schedule(date,date), public.read_class_timetable(uuid,date,date), public.read_class_roster(uuid)
  from public,anon,service_role;
grant execute on function public.create_service(text,text,integer,integer,integer), public.update_service(uuid,text,text,integer,integer,integer), public.set_service_active(uuid,boolean),
  public.create_class_rules(uuid,uuid,smallint[],time,integer,integer,uuid,date,date), public.update_class_rule(uuid,integer,integer,uuid,date,boolean),
  public.create_class_session(uuid,uuid,date,time,integer,integer,uuid), public.update_class_session(uuid,date,time,integer,integer,uuid), public.cancel_class_session(uuid,text),
  public.book_class_session(uuid), public.desk_book_class_session(uuid,uuid), public.cancel_class_booking(uuid), public.desk_cancel_class_booking(uuid,text),
  public.mark_class_attendance(uuid,public.booking_status), public.read_member_class_schedule(date,date), public.read_class_timetable(uuid,date,date), public.read_class_roster(uuid)
  to authenticated;
revoke all on function public.run_class_generation_all() from public,anon,authenticated;
grant execute on function public.run_class_generation_all() to service_role;
select cron.schedule('class-sessions-daily','0 19 * * *',$cron$select public.run_class_generation_all()$cron$);
