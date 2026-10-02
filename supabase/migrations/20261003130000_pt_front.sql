-- PTF-001..026. CI applies this forward-only migration after BOOKING and MEDIA.
create type public.pt_pack_state as enum ('live','fully_booked','spent','expired','closed');
alter table public.organization_settings
  add column pt_late_cancel_consumes_session boolean not null default true,
  add column pt_cancel_window_hours integer not null default 24
    constraint organization_settings_pt_cancel_window_hours_chk check (pt_cancel_window_hours between 0 and 168),
  add column pt_session_minutes integer not null default 60
    constraint organization_settings_pt_session_minutes_chk check (pt_session_minutes between 15 and 180 and pt_session_minutes % 5 = 0);
create table public.trainer_profiles (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
 staff_id uuid not null, bio text not null default '' constraint trainer_profiles_bio_chk check(char_length(bio)<=600),
 specialities text[] not null default '{}' constraint trainer_profiles_specialities_chk check(cardinality(specialities)<=8),
 photo_asset_id uuid, is_listed boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint trainer_profiles_tenant_id_staff_id_key unique(tenant_id,staff_id),
 foreign key(tenant_id,staff_id) references public.staff(tenant_id,id),
 foreign key(tenant_id,photo_asset_id) references public.media_assets(tenant_id,id)
);
create table public.trainer_availability (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id), staff_id uuid not null,
 weekday smallint not null constraint trainer_availability_weekday_chk check(weekday between 0 and 6),
 start_minute smallint not null constraint trainer_availability_start_minute_chk check(start_minute between 0 and 1439),
 end_minute smallint not null constraint trainer_availability_end_minute_chk check(end_minute between 1 and 1440),
 created_at timestamptz not null default now(), foreign key(tenant_id,staff_id) references public.staff(tenant_id,id),
 constraint trainer_availability_window_chk check(end_minute>start_minute),
 constraint trainer_availability_window_overlap_excl exclude using gist
 (tenant_id with =,staff_id with =,weekday with =,int4range(start_minute::integer,end_minute::integer) with &&)
);
create table public.trainer_time_off (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id),staff_id uuid not null,
 starts_on date not null,ends_on date not null,reason text constraint trainer_time_off_reason_chk check(reason is null or char_length(reason)<=200),
 created_by_staff_id uuid not null,removed_at timestamptz,removed_by_staff_id uuid,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 constraint trainer_time_off_range_chk check(ends_on>=starts_on),
 constraint trainer_time_off_removed_chk check((removed_at is null)=(removed_by_staff_id is null)),
 foreign key(tenant_id,staff_id) references public.staff(tenant_id,id),
 foreign key(tenant_id,created_by_staff_id) references public.staff(tenant_id,id),
 foreign key(tenant_id,removed_by_staff_id) references public.staff(tenant_id,id)
);
create table public.pt_cancellations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id),pt_session_id uuid not null,
 addon_order_id uuid not null,member_id uuid not null,trainer_staff_id uuid not null,
 outcome public.booking_status not null constraint pt_cancellations_outcome_chk check(outcome in ('cancelled_by_member','cancelled_by_gym')),
 cancelled_at timestamptz not null,cancelled_by_staff_id uuid,window_hours integer not null,policy_consumes boolean not null,
 was_late boolean not null,completed_order boolean not null default false,consumed boolean not null,
 reason text constraint pt_cancellations_reason_chk check(reason is null or char_length(reason) between 3 and 200),
 waived_at timestamptz,waived_by_staff_id uuid,waive_reason text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 constraint pt_cancellations_tenant_id_pt_session_id_key unique(tenant_id,pt_session_id),
 constraint pt_cancellations_actor_chk check((outcome='cancelled_by_gym')=(cancelled_by_staff_id is not null)),
 constraint pt_cancellations_completed_order_chk check(not completed_order or (outcome='cancelled_by_member' and was_late and policy_consumes and consumed)),
 constraint pt_cancellations_consumed_chk check(not consumed or (outcome='cancelled_by_member' and was_late and policy_consumes)),
 constraint pt_cancellations_waived_chk check((waived_at is null and waived_by_staff_id is null and waive_reason is null) or
 (waived_at is not null and waived_by_staff_id is not null and waive_reason is not null and consumed)),
 foreign key(tenant_id,pt_session_id) references public.pt_sessions(tenant_id,id),
 foreign key(tenant_id,addon_order_id) references public.addon_orders(tenant_id,id),
 foreign key(tenant_id,member_id) references public.members(tenant_id,id),
 foreign key(tenant_id,trainer_staff_id) references public.staff(tenant_id,id),
 foreign key(tenant_id,cancelled_by_staff_id) references public.staff(tenant_id,id),
 foreign key(tenant_id,waived_by_staff_id) references public.staff(tenant_id,id)
);
create index trainer_profiles_tenant_id_photo_asset_id_idx on public.trainer_profiles(tenant_id,photo_asset_id) where photo_asset_id is not null;
create index trainer_time_off_tenant_id_created_by_staff_id_idx on public.trainer_time_off(tenant_id,created_by_staff_id);
create index trainer_time_off_tenant_id_removed_by_staff_id_idx on public.trainer_time_off(tenant_id,removed_by_staff_id) where removed_by_staff_id is not null;
create index pt_cancellations_tenant_id_cancelled_by_staff_id_idx on public.pt_cancellations(tenant_id,cancelled_by_staff_id) where cancelled_by_staff_id is not null;
create index pt_cancellations_tenant_id_waived_by_staff_id_idx on public.pt_cancellations(tenant_id,waived_by_staff_id) where waived_by_staff_id is not null;
create index trainer_availability_tenant_id_staff_id_weekday_idx on public.trainer_availability(tenant_id,staff_id,weekday);
create index trainer_time_off_tenant_id_staff_id_starts_on_idx on public.trainer_time_off(tenant_id,staff_id,starts_on);
create index pt_cancellations_tenant_id_trainer_staff_id_cancelled_at_idx on public.pt_cancellations(tenant_id,trainer_staff_id,cancelled_at);
create index pt_cancellations_tenant_id_member_id_idx on public.pt_cancellations(tenant_id,member_id);
create index pt_cancellations_tenant_id_addon_order_id_idx on public.pt_cancellations(tenant_id,addon_order_id);
create index audit_log_actor_user_id_occurred_at_pt_booked_idx on public.audit_log(actor_user_id,occurred_at) where action='pt_session.booked';
do $ddl$
declare v_table text; v_staff text;
begin
 foreach v_table in array array['trainer_profiles','trainer_availability','trainer_time_off','pt_cancellations'] loop
  v_staff:=case when v_table='pt_cancellations' then 'trainer_staff_id' else 'staff_id' end;
  execute format('alter table public.%I enable row level security',v_table);
  execute format('revoke all on public.%I from anon,authenticated',v_table);
  execute format('grant select on public.%I to authenticated',v_table);
  execute format('create policy %I on public.%I for select to authenticated using ((select app.is_platform()))',v_table||'_platform_select',v_table);
  execute format('create policy %I on public.%I for select to authenticated using (tenant_id=(select app.current_tenant_id()) and ((select app.is_front_office()) or ((select app.current_app_role())=''trainer'' and %I=(select app.current_staff_id()))))',v_table||'_tenant_select',v_table,v_staff);
  execute format('create trigger %I before insert or update or delete on public.%I for each row execute function app.enforce_preview_read_only()',v_table||'_preview_read_only',v_table);
  if v_table<>'trainer_availability' then
   execute format('create trigger %I before update on public.%I for each row execute function app.touch_updated_at()',v_table||'_touch_updated_at',v_table);
  end if;
 end loop;
end
$ddl$;
create function app.guard_pt_policy_write() returns trigger language plpgsql volatile security invoker set search_path='' as $fn$
begin
 if current_user in ('authenticated','anon') and
 (new.pt_cancel_window_hours is distinct from old.pt_cancel_window_hours or
  new.pt_late_cancel_consumes_session is distinct from old.pt_late_cancel_consumes_session or
  new.pt_session_minutes is distinct from old.pt_session_minutes) then
  raise exception 'Change training policy with its audited command' using errcode='42501';
 end if; return new;
end
$fn$;
-- Member projections elevate because staff/availability/refunds are not member-readable.
create function public.read_member_trainers() returns table(trainer_key uuid,display_name text,qualification text,bio text,specialities text[],image_asset_id uuid,branch_name text,is_profile_listed boolean)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_member_actor();
 return query select app.pt_trainer_key(s.tenant_id,s.id),s.full_name,s.qualification,
 case when p.is_listed then p.bio else '' end,case when p.is_listed then p.specialities else '{}'::text[] end,
 case when p.is_listed and ma.kind='trainer' and ma.confirmed_at is not null and ma.deleted_at is null and ma.attached_to_id=s.id then ma.id end,
 b.name,coalesce(p.is_listed,false)
 from public.staff s left join public.trainer_profiles p on p.tenant_id=s.tenant_id and p.staff_id=s.id
 left join public.media_assets ma on ma.tenant_id=p.tenant_id and ma.id=p.photo_asset_id
 left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id
 where s.tenant_id=v_actor.tenant_id and s.role='trainer' and s.is_active and
 (p.is_listed or exists(select 1 from public.addon_products a where a.tenant_id=s.tenant_id and a.trainer_staff_id=s.id and a.kind='pt_package' and a.is_active
 and nullif(btrim(a.description),'') is not null and nullif(btrim(a.cancellation_terms),'') is not null and a.validity_days is not null
 and a.session_count is not null and nullif(btrim(a.trainer_qualification),'') is not null and a.stock_quantity is null)) order by s.full_name,s.id;
end
$fn$;
create function public.read_member_programmes() returns table(programme_id uuid,trainer_key uuid,trainer_name text,name text,description text,price_paise text,currency text,gst_rate_bp integer,session_count integer,validity_days integer,trainer_qualification text,cancellation_terms text)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_member_actor();
 return query select p.id,app.pt_trainer_key(s.tenant_id,s.id),s.full_name,p.name,p.description,p.price_paise::text,p.currency,p.gst_rate_bp::integer,p.session_count,p.validity_days,p.trainer_qualification,p.cancellation_terms
 from public.addon_products p join public.staff s on s.tenant_id=p.tenant_id and s.id=p.trainer_staff_id
 where p.tenant_id=v_actor.tenant_id and p.kind='pt_package' and p.is_active and s.role='trainer' and s.is_active
 and nullif(btrim(p.description),'') is not null and nullif(btrim(p.cancellation_terms),'') is not null and p.validity_days is not null
 and p.session_count is not null and nullif(btrim(p.trainer_qualification),'') is not null and p.stock_quantity is null order by p.sort_order,p.id;
end
$fn$;
create function public.read_member_pt_packs() returns table(order_id uuid,programme_name text,trainer_key uuid,trainer_name text,sessions_total integer,sessions_used integer,sessions_scheduled integer,sessions_remaining integer,starts_on date,expires_on date,state public.pt_pack_state,can_book boolean,timezone text)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_member_actor();
 return query select o.id,coalesce(o.sale_snapshot->>'name',p.name),app.pt_trainer_key(o.tenant_id,s.id),s.full_name,o.sessions_total,o.sessions_used,
 c.n,case when app.pt_pack_state(o.tenant_id,o.id)='expired' then greatest(o.sessions_total-o.sessions_used,0) else greatest(o.sessions_total-o.sessions_used-c.n,0) end,o.starts_on,o.expires_on,app.pt_pack_state(o.tenant_id,o.id),
 coalesce(app.pt_pack_state(o.tenant_id,o.id)='live' and s.role='trainer' and s.is_active and (s.branch_id is null or s.branch_id=v_actor.branch_id)
 and app.member_has_live_membership(o.tenant_id,o.member_id,app.gym_today(o.tenant_id)),false),coalesce(b.timezone,g.timezone)
 from public.addon_orders o join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
 join public.organizations g on g.id=o.tenant_id left join public.staff s on s.tenant_id=o.tenant_id and s.id=o.trainer_staff_id
 left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id
 cross join lateral(select count(*)::integer n from public.pt_sessions ps where ps.tenant_id=o.tenant_id and ps.addon_order_id=o.id and ps.status='scheduled') c
 where o.tenant_id=v_actor.tenant_id and o.member_id=v_actor.member_id and o.status in ('active','completed','refunded') and coalesce(o.sale_snapshot->>'kind',p.kind::text)='pt_package' order by o.id;
end
$fn$;
create function public.read_member_pt_sessions(p_scope text,p_limit integer default null,p_after_starts_at timestamptz default null,p_after_id uuid default null)
returns table(session_id uuid,order_id uuid,programme_name text,trainer_key uuid,trainer_name text,starts_at timestamptz,ends_at timestamptz,timezone text,status public.booking_status,consumed boolean,cancelled_at timestamptz,can_cancel boolean,cancel_cutoff timestamptz,late_now boolean,consumes_now boolean)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_member_actor();
 if p_scope is null or p_scope not in ('upcoming','history') then raise exception 'Invalid scope' using errcode='22023',detail='scope_invalid'; end if;
 if (p_after_starts_at is null)<>(p_after_id is null) then raise exception 'Invalid cursor' using errcode='22023',detail='range_invalid'; end if;
 return query select ps.id,o.id,coalesce(o.sale_snapshot->>'name',p.name),app.pt_trainer_key(ps.tenant_id,s.id),s.full_name,ps.starts_at,ps.ends_at,coalesce(b.timezone,g.timezone),
 app.pt_booking_status(ps.status,c.outcome),coalesce(c.consumed and c.waived_at is null,false),c.cancelled_at,
 ps.status='scheduled' and ps.starts_at>statement_timestamp(),ps.starts_at-make_interval(hours=>os.pt_cancel_window_hours),
 statement_timestamp()>ps.starts_at-make_interval(hours=>os.pt_cancel_window_hours),
 statement_timestamp()>ps.starts_at-make_interval(hours=>os.pt_cancel_window_hours) and os.pt_late_cancel_consumes_session
 from public.pt_sessions ps join public.addon_orders o on o.tenant_id=ps.tenant_id and o.id=ps.addon_order_id
 join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
 join public.staff s on s.tenant_id=ps.tenant_id and s.id=ps.trainer_staff_id join public.organizations g on g.id=o.tenant_id
 join public.organization_settings os on os.tenant_id=o.tenant_id left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id
 left join public.pt_cancellations c on c.tenant_id=ps.tenant_id and c.pt_session_id=ps.id
 where ps.tenant_id=v_actor.tenant_id and ps.member_id=v_actor.member_id
 and ((p_scope='upcoming' and ps.status='scheduled') or (p_scope='history' and ps.status<>'scheduled'))
 and (p_after_id is null or (p_scope='upcoming' and (ps.starts_at,ps.id)>(p_after_starts_at,p_after_id)) or (p_scope='history' and (ps.starts_at,ps.id)<(p_after_starts_at,p_after_id)))
 order by case when p_scope='upcoming' then ps.starts_at end asc,case when p_scope='upcoming' then ps.id end asc,
 case when p_scope='history' then ps.starts_at end desc,case when p_scope='history' then ps.id end desc limit least(greatest(coalesce(p_limit,50),1),50);
end
$fn$;
create function public.read_member_pt_slots(p_order_id uuid,p_from date,p_to date) returns table(starts_at timestamptz,ends_at timestamptz,timezone text)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;v_pack record;v_length integer;v_gym_zone text;
begin
 select * into v_actor from app.pt_member_actor();
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>=14 then raise exception 'Invalid slot range' using errcode='22023',detail='range_invalid'; end if;
 select x.*,o.trainer_staff_id into v_pack from public.read_member_pt_packs() x join public.addon_orders o on o.id=x.order_id and o.tenant_id=v_actor.tenant_id where x.order_id=p_order_id;
 if not found or not v_pack.can_book then return; end if;
 select os.pt_session_minutes into v_length from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 select g.timezone into v_gym_zone from public.organizations g where g.id=v_actor.tenant_id;
 return query select q.slot,q.slot+make_interval(mins=>v_length),v_pack.timezone::text from
 (select ((d.day::date)::timestamp+make_interval(mins=>m.minute)) at time zone v_pack.timezone as slot
 from generate_series(greatest(p_from,v_pack.starts_on)::timestamp,least(p_to,v_pack.expires_on)::timestamp,interval '1 day') d(day)
 join public.trainer_availability a on a.tenant_id=v_actor.tenant_id and a.staff_id=v_pack.trainer_staff_id and a.weekday=extract(dow from d.day)::integer
 cross join lateral generate_series(a.start_minute::integer,a.end_minute::integer-v_length,v_length) m(minute)) q
 where app.pt_slot_state(v_actor.tenant_id,v_pack.trainer_staff_id,q.slot)='open'
 and q.slot+make_interval(mins=>v_length)<=(v_pack.expires_on+1)::timestamp at time zone v_pack.timezone
 -- The unchanged Phase 6 session guard additionally preserves its gym-local sold window.
 and q.slot>=v_pack.starts_on::timestamp at time zone v_gym_zone
 and q.slot+make_interval(mins=>v_length)<=(v_pack.expires_on+1)::timestamp at time zone v_gym_zone order by q.slot limit 400;
end
$fn$;
-- Staff projections elevate to enforce own-client scoping independent of legacy broad table reads.
create function public.read_pt_bookings(p_from timestamptz,p_to timestamptz,p_trainer_staff_id uuid default null,p_status public.booking_status default null,p_limit integer default null,p_after_starts_at timestamptz default null,p_after_id uuid default null)
returns table(session_id uuid,order_id uuid,member_id uuid,member_name text,member_code text,trainer_staff_id uuid,trainer_name text,starts_at timestamptz,ends_at timestamptz,timezone text,status public.booking_status,consumed boolean,cancelled_at timestamptz,sessions_total integer,sessions_used integer,sessions_remaining integer)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','front_desk','trainer'],true);
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>interval '62 days' or (p_after_starts_at is null)<>(p_after_id is null) then raise exception 'Invalid booking range' using errcode='22023',detail='range_invalid'; end if;
 return query select ps.id,o.id,m.id,m.full_name,m.member_code,s.id,s.full_name,ps.starts_at,ps.ends_at,coalesce(b.timezone,g.timezone),app.pt_booking_status(ps.status,c.outcome),coalesce(c.consumed and c.waived_at is null,false),c.cancelled_at,
 o.sessions_total,o.sessions_used,greatest(o.sessions_total-o.sessions_used-r.n,0)
 from public.pt_sessions ps join public.addon_orders o on o.tenant_id=ps.tenant_id and o.id=ps.addon_order_id
 join public.members m on m.tenant_id=ps.tenant_id and m.id=ps.member_id join public.staff s on s.tenant_id=ps.tenant_id and s.id=ps.trainer_staff_id
 join public.organizations g on g.id=ps.tenant_id left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id
 left join public.pt_cancellations c on c.tenant_id=ps.tenant_id and c.pt_session_id=ps.id
 cross join lateral(select count(*)::integer n from public.pt_sessions x where x.tenant_id=o.tenant_id and x.addon_order_id=o.id and x.status='scheduled') r
 where ps.tenant_id=v_actor.tenant_id and ps.starts_at>=p_from and ps.starts_at<p_to
 and (v_actor.role<>'trainer' or ps.trainer_staff_id=v_actor.staff_id) and (p_trainer_staff_id is null or ps.trainer_staff_id=p_trainer_staff_id)
 and (p_status is null or app.pt_booking_status(ps.status,c.outcome)=p_status) and (p_after_id is null or (ps.starts_at,ps.id)>(p_after_starts_at,p_after_id))
 order by ps.starts_at,ps.id limit least(greatest(coalesce(p_limit,50),1),50);
end
$fn$;
create function public.read_pt_packs(p_trainer_staff_id uuid default null,p_state public.pt_pack_state default null,p_limit integer default null,p_after_id uuid default null)
returns table(order_id uuid,member_id uuid,member_name text,member_code text,trainer_staff_id uuid,trainer_name text,trainer_active boolean,programme_name text,sessions_total integer,sessions_used integer,sessions_scheduled integer,sessions_remaining integer,starts_on date,expires_on date,state public.pt_pack_state,timezone text)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','front_desk','trainer'],true);
 return query select o.id,m.id,m.full_name,m.member_code,s.id,s.full_name,coalesce(s.is_active and s.role='trainer',false),coalesce(o.sale_snapshot->>'name',p.name),o.sessions_total,o.sessions_used,r.n,
 case when app.pt_pack_state(o.tenant_id,o.id)='expired' then greatest(o.sessions_total-o.sessions_used,0) else greatest(o.sessions_total-o.sessions_used-r.n,0) end,o.starts_on,o.expires_on,app.pt_pack_state(o.tenant_id,o.id),coalesce(b.timezone,g.timezone)
 from public.addon_orders o join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
 join public.members m on m.tenant_id=o.tenant_id and m.id=o.member_id left join public.staff s on s.tenant_id=o.tenant_id and s.id=o.trainer_staff_id
 join public.organizations g on g.id=o.tenant_id left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id
 cross join lateral(select count(*)::integer n from public.pt_sessions x where x.tenant_id=o.tenant_id and x.addon_order_id=o.id and x.status='scheduled') r
 where o.tenant_id=v_actor.tenant_id and o.status in ('active','completed','refunded') and coalesce(o.sale_snapshot->>'kind',p.kind::text)='pt_package'
 and (v_actor.role<>'trainer' or o.trainer_staff_id=v_actor.staff_id) and (p_trainer_staff_id is null or o.trainer_staff_id=p_trainer_staff_id)
 and (p_state is null or app.pt_pack_state(o.tenant_id,o.id)=p_state) and (p_after_id is null or o.id>p_after_id)
 order by o.id limit least(greatest(coalesce(p_limit,50),1),50);
end
$fn$;
create trigger organization_settings_guard_pt_policy before update on public.organization_settings for each row execute function app.guard_pt_policy_write();
create function app.guard_pt_cancellation_completion() returns trigger language plpgsql volatile security invoker set search_path='' as $fn$
begin
 if new.completed_order is distinct from old.completed_order then raise exception 'Cancellation completion provenance is immutable' using errcode='22023',detail='pt_cancellation_provenance_immutable'; end if;
 return new;
end
$fn$;
create trigger pt_cancellations_completed_order_immutable before update of completed_order on public.pt_cancellations for each row execute function app.guard_pt_cancellation_completion();

-- Private elevated identity proofs read rows unavailable to member callers.
create function app.pt_member_actor() returns table(tenant_id uuid,member_id uuid,user_id uuid,branch_id uuid)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if auth.uid() is null or app.current_app_role() is distinct from 'member' or app.current_tenant_id() is null
 or app.current_member_id() is null or app.current_staff_id() is not null or app.current_impersonation_id() is not null then
  raise exception 'Complete member identity required' using errcode='42501'; end if;
 return query select m.tenant_id,m.id,m.user_id,m.branch_id from public.members m join public.organizations o on o.id=m.tenant_id
 where m.tenant_id=app.current_tenant_id() and m.id=app.current_member_id() and m.user_id=auth.uid()
 and m.erased_at is null and m.status not in ('cancelled','blocked')
 and (o.status='active' or (o.status='trial' and o.trial_ends_at>statement_timestamp()));
 if not found then raise exception 'Complete member identity required' using errcode='42501'; end if;
exception when invalid_text_representation then raise exception 'Complete member identity required' using errcode='42501';
end
$fn$;
create function app.pt_staff_actor(p_roles text[],p_allow_preview boolean default false)
returns table(tenant_id uuid,staff_id uuid,user_id uuid,role public.app_role)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if app.current_impersonation_id() is not null then
  if p_allow_preview is distinct from true or auth.uid() is null or app.current_tenant_id() is null
  or app.current_app_role() is distinct from 'gym_owner' or not coalesce('gym_owner'=any(p_roles),false)
  or app.current_staff_id() is not null or app.current_member_id() is not null then
   raise exception 'Complete staff identity required' using errcode='42501';
  end if;
  return query select i.tenant_id,null::uuid,auth.uid(),'gym_owner'::public.app_role
  from public.impersonation_sessions i
  join public.platform_users u on u.user_id=i.actor_user_id
  join public.organizations g on g.id=i.tenant_id
  where i.id=app.current_impersonation_id() and i.tenant_id=app.current_tenant_id()
  and i.actor_user_id=auth.uid() and app.impersonation_is_live(i.ended_at,i.expires_at)
  and u.is_active and u.role='super_admin';
  if not found then raise exception 'Complete staff identity required' using errcode='42501'; end if;
  return;
 end if;
 if auth.uid() is null or app.current_tenant_id() is null or app.current_staff_id() is null
 or app.current_member_id() is not null or app.current_impersonation_id() is not null
 or app.current_app_role() is null or not(app.current_app_role()=any(p_roles)) then
 raise exception 'Complete staff identity required' using errcode='42501'; end if;
 return query select s.tenant_id,s.id,s.user_id,s.role from public.staff s
 where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id() and s.user_id=auth.uid()
 and s.role::text=app.current_app_role() and s.role in ('gym_owner','gym_manager','front_desk','trainer') and s.is_active;
 if not found then raise exception 'Complete staff identity required' using errcode='42501'; end if;
exception when invalid_text_representation then raise exception 'Complete staff identity required' using errcode='42501';
end
$fn$;
create function app.pt_member_command_ok(p_tenant_id uuid,p_order_id uuid,p_session_id uuid,p_verbs text[])
returns boolean language plpgsql stable security invoker set search_path='' as $fn$
declare v_parts text[];
begin
 v_parts:=string_to_array(current_setting('app.pt_member_command',true),':');
 if current_user<>'postgres' or cardinality(v_parts) is distinct from 3 or not(v_parts[1]=any(p_verbs))
 or v_parts[3] is distinct from p_order_id::text or (p_session_id is not null and v_parts[2] is distinct from p_session_id::text)
 or auth.uid() is null or app.current_app_role() is distinct from 'member' or app.current_tenant_id() is distinct from p_tenant_id
 or app.current_member_id() is null or app.current_staff_id() is not null or app.current_impersonation_id() is not null then return false; end if;
 if v_parts[2] is distinct from (v_parts[2]::uuid)::text then return false; end if;
 return exists(select 1 from public.addon_orders o join public.members m on m.tenant_id=o.tenant_id and m.id=o.member_id
 where o.tenant_id=p_tenant_id and o.id=p_order_id and m.id=app.current_member_id() and m.user_id=auth.uid());
exception when invalid_text_representation then return false;
end
$fn$;
create function app.pt_trainer_key(p_tenant_id uuid,p_staff_id uuid) returns uuid
language sql immutable security invoker set search_path='' as $fn$ select md5('pt-trainer:'||p_tenant_id::text||':'||p_staff_id::text)::uuid $fn$;
create function app.pt_booking_status(p_status public.pt_session_status,p_outcome public.booking_status) returns public.booking_status
language sql immutable security invoker set search_path='' as $fn$
 select case p_status when 'scheduled' then 'booked'::public.booking_status when 'completed' then 'attended'::public.booking_status
 when 'no_show' then 'no_show'::public.booking_status when 'cancelled' then coalesce(p_outcome,'cancelled_by_gym'::public.booking_status) end
$fn$;
-- Private readers are reached only after the public command/read proves identity.
create function app.pt_pack_state(p_tenant_id uuid,p_order_id uuid) returns public.pt_pack_state
language sql stable security invoker set search_path='' as $fn$
 select case when o.status='completed' then 'spent'::public.pt_pack_state when o.status in ('refunded','cancelled') then 'closed'::public.pt_pack_state
 when o.status='active' and app.gym_today(o.tenant_id)>o.expires_on then 'expired'::public.pt_pack_state
 when o.status='active' and app.gym_today(o.tenant_id) between o.starts_on and o.expires_on then
 case when o.sessions_total-o.sessions_used-(select count(*) from public.pt_sessions s where s.tenant_id=o.tenant_id and s.addon_order_id=o.id and s.status='scheduled')>0
 then 'live'::public.pt_pack_state else 'fully_booked'::public.pt_pack_state end else 'closed'::public.pt_pack_state end
 from public.addon_orders o where o.tenant_id=p_tenant_id and o.id=p_order_id
$fn$;
create function app.pt_slot_state(p_tenant_id uuid,p_staff_id uuid,p_starts_at timestamptz) returns text
language plpgsql stable security invoker set search_path='' as $fn$
declare v_zone text;v_local timestamp;v_length integer;v_minute integer;
begin
 if p_starts_at<statement_timestamp()+interval '60 minutes' then return 'too_soon'; end if;
 if p_starts_at>=statement_timestamp()+interval '28 days' then return 'beyond_horizon'; end if;
 select coalesce(b.timezone,o.timezone),os.pt_session_minutes into v_zone,v_length
 from public.staff s join public.organizations o on o.id=s.tenant_id join public.organization_settings os on os.tenant_id=o.id
 left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id where s.tenant_id=p_tenant_id and s.id=p_staff_id;
 if not found then return 'not_offered'; end if;
 v_local:=p_starts_at at time zone v_zone;v_minute:=extract(hour from v_local)::integer*60+extract(minute from v_local)::integer;
 if exists(select 1 from public.organization_holidays h where h.tenant_id=p_tenant_id and h.holiday_on=v_local::date) then return 'holiday'; end if;
 if exists(select 1 from public.trainer_time_off t where t.tenant_id=p_tenant_id and t.staff_id=p_staff_id and t.removed_at is null and v_local::date between t.starts_on and t.ends_on) then return 'time_off'; end if;
 if extract(second from v_local)<>0 or not exists(select 1 from public.trainer_availability a where a.tenant_id=p_tenant_id and a.staff_id=p_staff_id
 and a.weekday=extract(dow from v_local)::integer and a.start_minute<=v_minute and v_minute+v_length<=a.end_minute and (v_minute-a.start_minute)%v_length=0) then return 'not_offered'; end if;
 if exists(select 1 from public.pt_sessions s where s.tenant_id=p_tenant_id and s.trainer_staff_id=p_staff_id and s.status in ('scheduled','completed')
 and s.starts_at<p_starts_at+make_interval(mins=>v_length) and s.ends_at>p_starts_at) then return 'taken'; end if;
 return 'open';
end
$fn$;
-- Callers cannot append audit_log; this narrow definer records safe summaries.
create function app.pt_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_type text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text)
returns void language plpgsql volatile security definer set search_path='' as $fn$
begin
 if p_action is null or p_action not in ('trainer_profile.updated','trainer_availability.replaced','trainer_time_off.added','trainer_time_off.removed','pt_session.booked','pt_session.cancelled','pt_session.cancelled_by_gym','pt_forfeit.waived','pt_order.reassigned','pt_policy.changed') then raise exception 'Invalid PT audit action' using errcode='22023'; end if;
 insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason)
 values(p_tenant_id,p_actor,p_role,p_action,p_record_type,p_record_id,p_before,p_after,p_reason);
end
$fn$;

-- Profile commands need narrow write elevation: authenticated has SELECT only.
-- The private common writer preserves the authority of the two public entrypoints.
create function app.pt_write_profile(p_staff_id uuid,p_bio text,p_specialities text[],p_photo_asset_id uuid,p_is_listed boolean,p_own boolean)
returns uuid language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_staff public.staff%rowtype;v_old public.trainer_profiles%rowtype;v_new public.trainer_profiles%rowtype;v_specs text[];
begin
 select * into v_actor from app.pt_staff_actor(case when p_own then array['trainer'] else array['gym_owner','gym_manager'] end);
 if p_own then p_staff_id:=v_actor.staff_id; end if;
 select s.* into v_staff from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_staff_id for update;
 if not found then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if v_staff.role<>'trainer' then raise exception 'Not a trainer' using errcode='22023',detail='not_a_trainer'; end if;
 if not v_staff.is_active then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if p_bio is null or char_length(btrim(p_bio))>600 then raise exception 'Invalid bio' using errcode='22023',detail='bio_invalid'; end if;
 if p_specialities is null or cardinality(p_specialities)>8 or exists(select 1 from unnest(p_specialities) x where x is null or char_length(btrim(x)) not between 1 and 40)
 or (select count(*) from unnest(p_specialities) x)<>(select count(distinct lower(btrim(x))) from unnest(p_specialities) x) then
 raise exception 'Invalid specialities' using errcode='22023',detail='speciality_invalid'; end if;
 select coalesce(array_agg(btrim(x) order by n),'{}'::text[]) into v_specs from unnest(p_specialities) with ordinality q(x,n);
 select p.* into v_old from public.trainer_profiles p where p.tenant_id=v_actor.tenant_id and p.staff_id=p_staff_id for update;
 if p_own then p_photo_asset_id:=v_old.photo_asset_id;p_is_listed:=coalesce(v_old.is_listed,false); end if;
 if p_is_listed is null then raise exception 'Listed flag required' using errcode='22023'; end if;
 if not p_own and p_photo_asset_id is not null then
  perform 1 from public.media_assets ma where ma.tenant_id=v_actor.tenant_id and ma.id=p_photo_asset_id and ma.kind='trainer'
  and ma.confirmed_at is not null and ma.deleted_at is null for update;
  if not found then raise exception 'Photo unavailable' using errcode='22023',detail='photo_unavailable'; end if;
 end if;
 if not p_own and p_photo_asset_id is distinct from v_old.photo_asset_id then
  if v_old.photo_asset_id is not null then perform app.media_release(v_actor.tenant_id,'trainer',p_staff_id); end if;
  if p_photo_asset_id is not null then perform app.media_attach(v_actor.tenant_id,p_photo_asset_id,'trainer',p_staff_id); end if;
 end if;
 insert into public.trainer_profiles as p(tenant_id,staff_id,bio,specialities,photo_asset_id,is_listed)
 values(v_actor.tenant_id,p_staff_id,btrim(p_bio),v_specs,p_photo_asset_id,p_is_listed)
 on conflict(tenant_id,staff_id) do update set bio=excluded.bio,specialities=excluded.specialities,photo_asset_id=excluded.photo_asset_id,is_listed=excluded.is_listed returning p.* into v_new;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'trainer_profile.updated','trainer_profile',v_new.id,
 case when v_old.id is not null then jsonb_build_object('is_listed',v_old.is_listed,'has_photo',v_old.photo_asset_id is not null,'speciality_count',cardinality(v_old.specialities)) end,
 jsonb_build_object('is_listed',v_new.is_listed,'has_photo',v_new.photo_asset_id is not null,'speciality_count',cardinality(v_new.specialities)),null);
 return v_new.id;
end
$fn$;
-- Staff callers cannot write profile rows; the private writer repeats identity proof.
create function public.set_trainer_profile(p_staff_id uuid,p_bio text,p_specialities text[],p_photo_asset_id uuid,p_is_listed boolean)
returns uuid language plpgsql volatile security definer set search_path='' as $fn$
begin return app.pt_write_profile(p_staff_id,p_bio,p_specialities,p_photo_asset_id,p_is_listed,false); end
$fn$;
create function public.set_own_trainer_profile(p_bio text,p_specialities text[])
returns uuid language plpgsql volatile security definer set search_path='' as $fn$
begin return app.pt_write_profile(null,p_bio,p_specialities,null,false,true); end
$fn$;
-- Replacement and time-off commands elevate only after complete staff proof and target scope.
create function public.set_trainer_availability(p_staff_id uuid,p_windows jsonb) returns integer
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_staff public.staff%rowtype;v_window jsonb;v_before jsonb;v_after jsonb;
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','trainer']);
 if v_actor.role='trainer' and p_staff_id is distinct from v_actor.staff_id then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 select s.* into v_staff from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_staff_id for update;
 if not found then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if v_staff.role<>'trainer' then raise exception 'Not a trainer' using errcode='22023',detail='not_a_trainer'; end if;
 if not v_staff.is_active then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if p_windows is null or jsonb_typeof(p_windows)<>'array' then raise exception 'Invalid windows' using errcode='22023',detail='window_invalid'; end if;
 if jsonb_array_length(p_windows)>28 then raise exception 'Invalid windows' using errcode='22023',detail='window_invalid'; end if;
 for v_window in select jsonb_array_elements(p_windows) loop
  if jsonb_typeof(v_window)<>'object' then raise exception 'Invalid window' using errcode='22023',detail='window_invalid'; end if;
  if (select count(*) from jsonb_object_keys(v_window))<>3 or not(v_window ?& array['weekday','startMinute','endMinute'])
  or jsonb_typeof(v_window->'weekday') is distinct from 'number' or jsonb_typeof(v_window->'startMinute') is distinct from 'number' or jsonb_typeof(v_window->'endMinute') is distinct from 'number' then
  raise exception 'Invalid window' using errcode='22023',detail='window_invalid'; end if;
  if (v_window->>'weekday')::numeric<>trunc((v_window->>'weekday')::numeric) or (v_window->>'startMinute')::numeric<>trunc((v_window->>'startMinute')::numeric)
  or (v_window->>'endMinute')::numeric<>trunc((v_window->>'endMinute')::numeric) or (v_window->>'weekday')::numeric not between 0 and 6
  or (v_window->>'startMinute')::numeric not between 0 and 1439 or (v_window->>'endMinute')::numeric not between 1 and 1440
  or (v_window->>'endMinute')::numeric<=(v_window->>'startMinute')::numeric then raise exception 'Invalid window' using errcode='22023',detail='window_invalid'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_windows) with ordinality a(w,n) join jsonb_array_elements(p_windows) with ordinality b(w,n)
 on a.n<b.n and (a.w->>'weekday')::numeric=(b.w->>'weekday')::numeric
 and (a.w->>'startMinute')::numeric<(b.w->>'endMinute')::numeric and (b.w->>'startMinute')::numeric<(a.w->>'endMinute')::numeric) then
 raise exception 'Windows overlap' using errcode='22023',detail='window_overlap'; end if;
 select jsonb_build_object('windows',coalesce(jsonb_agg(jsonb_build_object('weekday',a.weekday,'start_minute',a.start_minute,'end_minute',a.end_minute) order by a.weekday,a.start_minute),'[]'::jsonb)) into v_before
 from public.trainer_availability a where a.tenant_id=v_actor.tenant_id and a.staff_id=p_staff_id;
 delete from public.trainer_availability a where a.tenant_id=v_actor.tenant_id and a.staff_id=p_staff_id;
 insert into public.trainer_availability(tenant_id,staff_id,weekday,start_minute,end_minute)
 select v_actor.tenant_id,p_staff_id,(w->>'weekday')::numeric::smallint,(w->>'startMinute')::numeric::smallint,(w->>'endMinute')::numeric::smallint from jsonb_array_elements(p_windows) w;
 select jsonb_build_object('windows',coalesce(jsonb_agg(jsonb_build_object('weekday',a.weekday,'start_minute',a.start_minute,'end_minute',a.end_minute) order by a.weekday,a.start_minute),'[]'::jsonb)) into v_after
 from public.trainer_availability a where a.tenant_id=v_actor.tenant_id and a.staff_id=p_staff_id;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'trainer_availability.replaced','trainer_availability',p_staff_id,v_before,v_after,null);
 return jsonb_array_length(p_windows);
end
$fn$;
create function public.add_trainer_time_off(p_staff_id uuid,p_starts_on date,p_ends_on date,p_reason text) returns uuid
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_staff public.staff%rowtype;v_id uuid;v_reason text:=nullif(btrim(p_reason),'');
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','trainer']);
 if v_actor.role='trainer' and p_staff_id is distinct from v_actor.staff_id then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 select s.* into v_staff from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_staff_id for update;
 if not found or not v_staff.is_active then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if v_staff.role<>'trainer' then raise exception 'Not a trainer' using errcode='22023',detail='not_a_trainer'; end if;
 if p_starts_on is null or p_ends_on is null or p_ends_on<p_starts_on then raise exception 'Invalid date range' using errcode='22023',detail='range_invalid'; end if;
 if char_length(v_reason)>200 then raise exception 'Invalid reason' using errcode='22023',detail='reason_invalid'; end if;
 insert into public.trainer_time_off(tenant_id,staff_id,starts_on,ends_on,reason,created_by_staff_id)
 values(v_actor.tenant_id,p_staff_id,p_starts_on,p_ends_on,v_reason,v_actor.staff_id) returning id into v_id;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'trainer_time_off.added','trainer_time_off',v_id,null,jsonb_build_object('staff_id',p_staff_id,'starts_on',p_starts_on,'ends_on',p_ends_on),null);
 return v_id;
end
$fn$;
create function public.remove_trainer_time_off(p_time_off_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_row public.trainer_time_off%rowtype;
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','trainer']);
 select t.* into v_row from public.trainer_time_off t where t.tenant_id=v_actor.tenant_id and t.id=p_time_off_id for update;
 if not found or (v_actor.role='trainer' and (v_row.staff_id<>v_actor.staff_id or v_row.created_by_staff_id<>v_actor.staff_id)) then raise exception 'Time off unavailable' using errcode='42501'; end if;
 if v_row.created_by_staff_id<>v_actor.staff_id then raise exception 'Time off unavailable' using errcode='42501'; end if;
 if v_row.removed_at is not null then return; end if;
 update public.trainer_time_off t set removed_at=statement_timestamp(),removed_by_staff_id=v_actor.staff_id where t.id=v_row.id;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'trainer_time_off.removed','trainer_time_off',v_row.id,
 jsonb_build_object('staff_id',v_row.staff_id,'starts_on',v_row.starts_on,'ends_on',v_row.ends_on),jsonb_build_object('staff_id',v_row.staff_id,'starts_on',v_row.starts_on,'ends_on',v_row.ends_on),null);
end
$fn$;
-- Policy writes are unavailable directly even to staff; this command supplies audit.
create function public.set_pt_policy(p_cancel_window_hours integer,p_late_cancel_consumes boolean,p_session_minutes integer) returns void
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_old public.organization_settings%rowtype;
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager']);
 if p_cancel_window_hours is null or p_cancel_window_hours not between 0 and 168 or p_late_cancel_consumes is null or p_session_minutes is null
 or p_session_minutes not between 15 and 180 or p_session_minutes%5<>0 then raise exception 'Invalid policy' using errcode='22023',detail='policy_out_of_range'; end if;
 select os.* into v_old from public.organization_settings os where os.tenant_id=v_actor.tenant_id for update;
 if not found then raise exception 'Settings unavailable' using errcode='42501'; end if;
 update public.organization_settings os set pt_cancel_window_hours=p_cancel_window_hours,pt_late_cancel_consumes_session=p_late_cancel_consumes,pt_session_minutes=p_session_minutes where os.tenant_id=v_actor.tenant_id;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'pt_policy.changed','organization_settings',v_actor.tenant_id,
 jsonb_build_object('cancel_window_hours',v_old.pt_cancel_window_hours,'late_cancel_consumes',v_old.pt_late_cancel_consumes_session,'session_minutes',v_old.pt_session_minutes),
 jsonb_build_object('cancel_window_hours',p_cancel_window_hours,'late_cancel_consumes',p_late_cancel_consumes,'session_minutes',p_session_minutes),null);
end
$fn$;
-- Member commands elevate for the existing staff-only PT ledger and hidden refunds.
-- Authority is the complete actor plus ownership, never the caller's command setting.
create function public.book_pt_session(p_order_id uuid,p_session_id uuid,p_starts_at timestamptz)
returns table(session_id uuid,order_id uuid,starts_at timestamptz,ends_at timestamptz,status public.booking_status,in_cancel_window boolean,replayed boolean)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_order public.addon_orders%rowtype;v_first_trainer uuid;v_trainer public.staff%rowtype;v_member public.members%rowtype;
 v_session public.pt_sessions%rowtype;v_zone text;v_gym_zone text;v_policy public.organization_settings%rowtype;v_end timestamptz;v_state text;v_reserved integer;v_outcome public.booking_status;v_previous text:=coalesce(current_setting('app.pt_member_command',true),'');
begin
 select * into v_actor from app.pt_member_actor();
 if p_order_id is null or p_session_id is null or p_starts_at is null or not isfinite(p_starts_at) then raise exception 'Booking arguments required' using errcode='22023'; end if;
 select o.* into v_order from public.addon_orders o join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
 where o.tenant_id=v_actor.tenant_id and o.id=p_order_id and o.member_id=v_actor.member_id and coalesce(o.sale_snapshot->>'kind',p.kind::text)='pt_package';
 if not found then raise exception 'Pack unavailable' using errcode='42501'; end if;
 v_first_trainer:=v_order.trainer_staff_id;
 if v_first_trainer is null then raise exception 'Trainer unavailable' using errcode='GL055',detail='trainer_unavailable'; end if;
 perform app.booking_lock(v_actor.tenant_id,'trainer_slot',v_first_trainer);
 perform pg_advisory_xact_lock(hashtextextended('pt-session:'||v_actor.tenant_id::text||':'||p_session_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('addon-order:'||v_actor.tenant_id::text||':'||p_order_id::text,0));
 select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=p_order_id and o.member_id=v_actor.member_id for update;
 if not found then raise exception 'Pack unavailable' using errcode='42501'; end if;
 if v_order.trainer_staff_id is distinct from v_first_trainer then raise exception 'Pack trainer changed' using errcode='40001'; end if;
 select os.* into v_policy from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 select ps.* into v_session from public.pt_sessions ps where ps.id=p_session_id;
 if found then
  if v_session.tenant_id is distinct from v_actor.tenant_id or v_session.addon_order_id is distinct from p_order_id or v_session.member_id is distinct from v_actor.member_id
  or v_session.trainer_staff_id is distinct from v_order.trainer_staff_id or v_session.starts_at is distinct from p_starts_at then raise exception 'Request identity conflicts' using errcode='GL052'; end if;
  select c.outcome into v_outcome from public.pt_cancellations c where c.tenant_id=v_actor.tenant_id and c.pt_session_id=p_session_id;
  return query select v_session.id,v_session.addon_order_id,v_session.starts_at,v_session.ends_at,app.pt_booking_status(v_session.status,v_outcome),
  statement_timestamp()>v_session.starts_at-make_interval(hours=>v_policy.pt_cancel_window_hours),true;return;
 end if;
 -- The member row serializes their overlapping bookings and rolling-user throttle across trainers.
 select m.* into v_member from public.members m where m.tenant_id=v_actor.tenant_id and m.id=v_actor.member_id for update;
 if (select count(*) from public.audit_log a where a.actor_user_id=v_actor.user_id and a.action='pt_session.booked' and a.occurred_at>statement_timestamp()-interval '24 hours')>=10 then
 raise exception 'Booking rate limited' using errcode='GL097'; end if;
 select s.* into v_trainer from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=v_order.trainer_staff_id for share;
 select coalesce(b.timezone,g.timezone),g.timezone into v_zone,v_gym_zone from public.organizations g
 left join public.branches b on b.tenant_id=g.id and b.id=v_trainer.branch_id where g.id=v_actor.tenant_id;
 v_end:=p_starts_at+make_interval(mins=>v_policy.pt_session_minutes);
 if v_member.erased_at is not null or v_member.status in ('cancelled','blocked') or v_member.user_id is distinct from v_actor.user_id
 or not app.member_has_live_membership(v_actor.tenant_id,v_actor.member_id,(p_starts_at at time zone v_zone)::date) then raise exception 'Membership not live' using errcode='GL093'; end if;
 if v_order.status<>'active' or v_order.starts_on is null or v_order.expires_on is null then raise exception 'Pack unavailable' using errcode='GL055',detail='order_unavailable'; end if;
 perform set_config('app.pt_member_command','book:'||p_session_id::text||':'||p_order_id::text,true);
 if app.addon_order_fully_returned(v_actor.tenant_id,p_order_id) then raise exception 'Pack unavailable' using errcode='GL055',detail='order_unavailable'; end if;
 perform set_config('app.pt_member_command',v_previous,true);
 if v_trainer.id is null or not v_trainer.is_active or v_trainer.role<>'trainer' then raise exception 'Trainer unavailable' using errcode='GL055',detail='trainer_unavailable'; end if;
 if v_trainer.branch_id is not null and v_trainer.branch_id is distinct from v_member.branch_id then raise exception 'Trainer branch differs' using errcode='GL094'; end if;
 select count(*)::integer into v_reserved from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.addon_order_id=p_order_id and ps.status='scheduled';
 if v_order.sessions_total is null or v_order.sessions_used+v_reserved>=v_order.sessions_total then raise exception 'Pack spent' using errcode='GL058',detail='session_budget_exhausted'; end if;
 if p_starts_at<v_order.starts_on::timestamp at time zone v_zone or v_end>(v_order.expires_on+1)::timestamp at time zone v_zone
 or p_starts_at<v_order.starts_on::timestamp at time zone v_gym_zone or v_end>(v_order.expires_on+1)::timestamp at time zone v_gym_zone
 or (clock_timestamp() at time zone v_gym_zone)::date not between v_order.starts_on and v_order.expires_on then raise exception 'Outside pack dates' using errcode='GL058',detail='session_outside_validity'; end if;
 if exists(select 1 from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.member_id=v_actor.member_id and ps.status='scheduled' and ps.starts_at<v_end and ps.ends_at>p_starts_at) then raise exception 'Already booked' using errcode='GL091'; end if;
 v_state:=app.pt_slot_state(v_actor.tenant_id,v_order.trainer_staff_id,p_starts_at);
 if v_state='taken' then raise exception 'Slot taken' using errcode='GL096'; elsif v_state<>'open' then raise exception 'Slot unavailable' using errcode='GL092',detail=v_state; end if;
 begin
  perform set_config('app.pt_member_command','book:'||p_session_id::text||':'||p_order_id::text,true);
  insert into public.pt_sessions(id,tenant_id,addon_order_id,member_id,trainer_staff_id,starts_at,ends_at,status,notes)
  values(p_session_id,v_actor.tenant_id,p_order_id,v_actor.member_id,v_order.trainer_staff_id,p_starts_at,v_end,'scheduled',null);
  perform set_config('app.pt_member_command',v_previous,true);
 exception when exclusion_violation then raise exception 'Slot taken' using errcode='GL096'; end;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,'member','pt_session.booked','pt_session',p_session_id,null,
 jsonb_build_object('order_id',p_order_id,'trainer_staff_id',v_order.trainer_staff_id,'starts_at',p_starts_at,'ends_at',v_end),null);
 return query select p_session_id,p_order_id,p_starts_at,v_end,'booked'::public.booking_status,statement_timestamp()>p_starts_at-make_interval(hours=>v_policy.pt_cancel_window_hours),false;
exception when others then perform set_config('app.pt_member_command',v_previous,true);raise;
end
$fn$;
create function public.cancel_pt_booking(p_session_id uuid)
returns table(session_id uuid,status public.booking_status,late boolean,consumed boolean,sessions_remaining integer,replayed boolean)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_session public.pt_sessions%rowtype;v_order public.addon_orders%rowtype;v_cancel public.pt_cancellations%rowtype;
 v_policy public.organization_settings%rowtype;v_late boolean;v_consumed boolean;v_completed boolean;v_reserved integer;v_previous text:=coalesce(current_setting('app.pt_member_command',true),'');
begin
 select * into v_actor from app.pt_member_actor();
 if p_session_id is null then raise exception 'Session required' using errcode='22023'; end if;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id and ps.member_id=v_actor.member_id;
 if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pt-session:'||v_actor.tenant_id::text||':'||p_session_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('addon-order:'||v_actor.tenant_id::text||':'||v_session.addon_order_id::text,0));
 select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=v_session.addon_order_id and o.member_id=v_actor.member_id for update;
 if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id and ps.member_id=v_actor.member_id for update;
 select c.* into v_cancel from public.pt_cancellations c where c.tenant_id=v_actor.tenant_id and c.pt_session_id=p_session_id;
 if v_session.status='cancelled' then
  select count(*)::integer into v_reserved from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.addon_order_id=v_order.id and ps.status='scheduled';
  return query select p_session_id,app.pt_booking_status(v_session.status,v_cancel.outcome),coalesce(v_cancel.was_late,false),coalesce(v_cancel.consumed and v_cancel.waived_at is null,false),greatest(v_order.sessions_total-v_order.sessions_used-v_reserved,0),true;return;
 end if;
 if v_session.status<>'scheduled' then raise exception 'Session closed' using errcode='GL058',detail='invalid_session_transition'; end if;
 if v_session.starts_at<=statement_timestamp() then raise exception 'Session already started' using errcode='GL095'; end if;
 select os.* into v_policy from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 v_late:=statement_timestamp()>v_session.starts_at-make_interval(hours=>v_policy.pt_cancel_window_hours);
 v_consumed:=v_late and v_policy.pt_late_cancel_consumes_session;
 v_completed:=v_consumed and v_order.status='active' and v_order.sessions_used=v_order.sessions_total-1;
 perform set_config('app.pt_member_command','cancel:'||p_session_id::text||':'||v_order.id::text,true);
 update public.pt_sessions ps set status='cancelled' where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id;
 perform set_config('app.pt_member_command',v_previous,true);
 insert into public.pt_cancellations(tenant_id,pt_session_id,addon_order_id,member_id,trainer_staff_id,outcome,cancelled_at,window_hours,policy_consumes,was_late,completed_order,consumed)
 values(v_actor.tenant_id,p_session_id,v_order.id,v_actor.member_id,v_session.trainer_staff_id,'cancelled_by_member',statement_timestamp(),v_policy.pt_cancel_window_hours,v_policy.pt_late_cancel_consumes_session,v_late,v_completed,v_consumed);
 if v_consumed then
  -- The existing completion invariant uses the unchanged returned-money predicate,
  -- whose approved member admission is the book marker, scoped to this exact order.
  perform set_config('app.pt_member_command','book:'||p_session_id::text||':'||v_order.id::text,true);
  update public.addon_orders o set sessions_used=o.sessions_used+1,status=case when o.sessions_used+1=o.sessions_total then 'completed'::public.addon_order_status else o.status end where o.tenant_id=v_actor.tenant_id and o.id=v_order.id returning o.* into v_order;
  perform set_config('app.pt_member_command',v_previous,true);
 end if;
 select count(*)::integer into v_reserved from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.addon_order_id=v_order.id and ps.status='scheduled';
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,'member','pt_session.cancelled','pt_session',p_session_id,jsonb_build_object('status','scheduled'),
 jsonb_build_object('status','cancelled','outcome','cancelled_by_member','late',v_late,'consumed',v_consumed,'sessions_used',v_order.sessions_used),null);
 return query select p_session_id,'cancelled_by_member'::public.booking_status,v_late,v_consumed,greatest(v_order.sessions_total-v_order.sessions_used-v_reserved,0),false;
exception when others then perform set_config('app.pt_member_command',v_previous,true);raise;
end
$fn$;
-- Staff cannot append provenance/audits/notices directly; this command is atomic.
create function public.cancel_pt_session_as_gym(p_session_id uuid,p_reason text)
returns table(session_id uuid,status public.booking_status,replayed boolean)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_session public.pt_sessions%rowtype;v_order public.addon_orders%rowtype;v_policy public.organization_settings%rowtype;
 v_cancel public.pt_cancellations%rowtype;v_reason text:=btrim(p_reason);v_zone text;v_name text;v_gym text;v_notice uuid;v_kind text:='pt_session_cancelled_by_gym';
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager','front_desk']);
 if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'Invalid reason' using errcode='22023',detail='reason_invalid'; end if;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id;
 if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pt-session:'||v_actor.tenant_id::text||':'||p_session_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('addon-order:'||v_actor.tenant_id::text||':'||v_session.addon_order_id::text,0));
 select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=v_session.addon_order_id for update;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id for update;
 select c.* into v_cancel from public.pt_cancellations c where c.tenant_id=v_actor.tenant_id and c.pt_session_id=p_session_id;
 if v_session.status='cancelled' then return query select p_session_id,app.pt_booking_status(v_session.status,v_cancel.outcome),true;return; end if;
 if v_session.status<>'scheduled' then raise exception 'Session closed' using errcode='GL058',detail='invalid_session_transition'; end if;
 select os.* into v_policy from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 update public.pt_sessions ps set status='cancelled' where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id;
 insert into public.pt_cancellations(tenant_id,pt_session_id,addon_order_id,member_id,trainer_staff_id,outcome,cancelled_at,cancelled_by_staff_id,window_hours,policy_consumes,was_late,consumed,reason)
 values(v_actor.tenant_id,p_session_id,v_order.id,v_session.member_id,v_session.trainer_staff_id,'cancelled_by_gym',statement_timestamp(),v_actor.staff_id,v_policy.pt_cancel_window_hours,v_policy.pt_late_cancel_consumes_session,false,false,v_reason);
 select coalesce(b.timezone,g.timezone),s.full_name,g.name into v_zone,v_name,v_gym from public.staff s join public.organizations g on g.id=s.tenant_id
 left join public.branches b on b.tenant_id=s.tenant_id and b.id=s.branch_id where s.tenant_id=v_actor.tenant_id and s.id=v_session.trainer_staff_id;
 insert into public.notifications as n(tenant_id,member_id,channel,status,category,template_key,related_type,related_id,dedupe_key,payload)
 values(v_actor.tenant_id,v_session.member_id,'in_app','scheduled','fulfilment',v_kind,'pt_session',p_session_id,'pt:'||v_kind||':'||p_session_id::text,
 jsonb_build_object('kind',v_kind,'body','Your session with '||v_name||' on '||to_char(v_session.starts_at at time zone v_zone,'FMDD Mon YYYY, FMHH12:MI AM')||' was cancelled by '||v_gym||'. It did not use a session from your pack.'))
 on conflict(tenant_id,dedupe_key) where dedupe_key is not null do nothing returning n.id into v_notice;
 if v_notice is not null then update public.notifications n set status='sent',sent_at=statement_timestamp() where n.id=v_notice; end if;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'pt_session.cancelled_by_gym','pt_session',p_session_id,jsonb_build_object('status','scheduled'),jsonb_build_object('status','cancelled','outcome','cancelled_by_gym'),v_reason);
 return query select p_session_id,'cancelled_by_gym'::public.booking_status,false;
end
$fn$;
-- Owner/manager waiver needs hidden refunds and private cancellation writes;
-- the exact terminal-order exception remains an invoker invariant below.
create function public.waive_pt_forfeit(p_session_id uuid,p_reason text)
returns table(session_id uuid,order_id uuid,sessions_used integer,replayed boolean)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_session public.pt_sessions%rowtype;v_order public.addon_orders%rowtype;v_cancel public.pt_cancellations%rowtype;
 v_reason text:=btrim(p_reason);v_zone text;v_gym text;v_programme text;v_status public.addon_order_status;v_old_used integer;v_now timestamptz;v_notice uuid;
 v_previous text:=coalesce(current_setting('app.pt_completed_waive_command',true),'');v_kind text:='pt_forfeit_waived';
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager']);
 if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'Invalid reason' using errcode='22023',detail='reason_invalid'; end if;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id;
 if not found then raise exception 'Session unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pt-session:'||v_actor.tenant_id::text||':'||p_session_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('addon-order:'||v_actor.tenant_id::text||':'||v_session.addon_order_id::text,0));
 select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=v_session.addon_order_id for update;
 select ps.* into v_session from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.id=p_session_id for update;
 select c.* into v_cancel from public.pt_cancellations c where c.tenant_id=v_actor.tenant_id and c.pt_session_id=p_session_id for update;
 if not found or not v_cancel.consumed then raise exception 'Cancellation did not consume' using errcode='22023',detail='not_consumed'; end if;
 if v_cancel.waived_at is not null then return query select p_session_id,v_order.id,v_order.sessions_used,true;return; end if;
 v_now:=clock_timestamp();
 select g.timezone,g.name,coalesce(v_order.sale_snapshot->>'name',p.name) into v_zone,v_gym,v_programme
 from public.organizations g join public.addon_products p on p.tenant_id=g.id and p.id=v_order.addon_product_id where g.id=v_actor.tenant_id;
 if v_order.status not in ('active','completed') or v_order.starts_on is null or v_order.expires_on is null
 or (v_now at time zone v_zone)::date not between v_order.starts_on and v_order.expires_on or v_order.sessions_used<=0
 or app.addon_order_fully_returned(v_actor.tenant_id,v_order.id) then raise exception 'Pack unavailable' using errcode='GL055',detail='order_unavailable'; end if;
 if v_order.status='completed' and (
 not v_cancel.completed_order or not v_cancel.was_late or not v_cancel.policy_consumes or v_cancel.outcome<>'cancelled_by_member'
 or v_session.status<>'cancelled' or v_cancel.addon_order_id is distinct from v_order.id or v_session.addon_order_id is distinct from v_order.id
 or v_cancel.member_id is distinct from v_order.member_id or v_session.member_id is distinct from v_order.member_id
 or v_cancel.trainer_staff_id is distinct from v_order.trainer_staff_id or v_session.trainer_staff_id is distinct from v_order.trainer_staff_id
 or v_order.sessions_used is distinct from v_order.sessions_total
 or coalesce(v_order.sale_snapshot->>'kind',(select p.kind::text from public.addon_products p where p.tenant_id=v_order.tenant_id and p.id=v_order.addon_product_id)) is distinct from 'pt_package'
 or exists(select 1 from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.addon_order_id=v_order.id and ps.status='scheduled')
 or exists(select 1 from public.refunds r where r.tenant_id=v_order.tenant_id and r.payment_id=v_order.payment_id)) then raise exception 'Pack unavailable' using errcode='GL055',detail='order_unavailable'; end if;
 v_old_used:=v_order.sessions_used;v_status:=v_order.status;
 update public.pt_cancellations c set waived_at=v_now,waived_by_staff_id=v_actor.staff_id,waive_reason=v_reason where c.id=v_cancel.id;
 if v_status='completed' then perform set_config('app.pt_completed_waive_command','waive:'||p_session_id::text||':'||v_order.id::text,true); end if;
 update public.addon_orders o set sessions_used=o.sessions_used-1,status=case when o.status='completed' then 'active'::public.addon_order_status else o.status end where o.tenant_id=v_actor.tenant_id and o.id=v_order.id;
 perform set_config('app.pt_completed_waive_command',v_previous,true);
 insert into public.notifications as n(tenant_id,member_id,channel,status,category,template_key,related_type,related_id,dedupe_key,payload)
 values(v_actor.tenant_id,v_order.member_id,'in_app','scheduled','fulfilment',v_kind,'pt_session',p_session_id,'pt:'||v_kind||':'||p_session_id::text,
 jsonb_build_object('kind',v_kind,'body',v_gym||' returned a session to your '||v_programme||' pack.'))
 on conflict(tenant_id,dedupe_key) where dedupe_key is not null do nothing returning n.id into v_notice;
 if v_notice is not null then update public.notifications n set status='sent',sent_at=statement_timestamp() where n.id=v_notice; end if;
 perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'pt_forfeit.waived','pt_session',p_session_id,
 jsonb_build_object('consumed',true,'sessions_used',v_old_used,'order_status',v_status),
 jsonb_build_object('consumed',false,'sessions_used',v_old_used-1,'order_status',case when v_status='completed' then 'active' else v_status::text end),v_reason);
 return query select p_session_id,v_order.id,v_old_used-1,false;
exception when others then perform set_config('app.pt_completed_waive_command',v_previous,true);raise;
end
$fn$;
-- Reassignment writes frozen trainer terms only through the exact admitted guard.
create function public.reassign_pt_packs(p_from_staff_id uuid,p_to_staff_id uuid,p_order_ids uuid[],p_reason text)
returns table(order_id uuid,changed boolean,cancelled_sessions integer)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_ids uuid[];v_id uuid;v_order public.addon_orders%rowtype;v_target public.staff%rowtype;v_source public.staff%rowtype;v_session public.pt_sessions%rowtype;
 v_reason text:=btrim(p_reason);v_count integer;v_policy public.organization_settings%rowtype;v_gym text;v_programme text;v_body text;v_notice uuid;
 v_previous text:=coalesce(current_setting('app.pt_reassign_command',true),'');v_kind text:='pt_pack_reassigned';
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager']);
 if p_from_staff_id is null or p_to_staff_id is null then raise exception 'Trainer ids required' using errcode='22023'; end if;
 if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'Invalid reason' using errcode='22023',detail='reason_invalid'; end if;
 if p_from_staff_id=p_to_staff_id then raise exception 'Same trainer' using errcode='22023',detail='same_trainer'; end if;
 if p_order_ids is not null and cardinality(p_order_ids)>100 then raise exception 'Batch too large' using errcode='22023',detail='batch_too_large'; end if;
 perform app.booking_lock(v_actor.tenant_id,'trainer_slot',least(p_from_staff_id,p_to_staff_id));
 perform app.booking_lock(v_actor.tenant_id,'trainer_slot',greatest(p_from_staff_id,p_to_staff_id));
 select s.* into v_target from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_to_staff_id for share;
 if not found or v_target.role<>'trainer' or not v_target.is_active then raise exception 'Trainer unavailable' using errcode='GL055',detail='trainer_unavailable'; end if;
 select s.* into v_source from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_from_staff_id;
 if not found then raise exception 'Trainer unavailable' using errcode='42501'; end if;
 if p_order_ids is null then
 select coalesce(array_agg(o.id order by o.id),'{}'::uuid[]) into v_ids from public.addon_orders o join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
 where o.tenant_id=v_actor.tenant_id and o.trainer_staff_id=p_from_staff_id and o.status='active' and coalesce(o.sale_snapshot->>'kind',p.kind::text)='pt_package';
 else
 if array_position(p_order_ids,null) is not null then raise exception 'Pack unavailable' using errcode='42501'; end if;
 select coalesce(array_agg(x order by x),'{}'::uuid[]) into v_ids from (select distinct unnest(p_order_ids) x) q;
 end if;
 if cardinality(v_ids)>100 then raise exception 'Batch too large' using errcode='22023',detail='batch_too_large'; end if;
 foreach v_id in array v_ids loop perform pg_advisory_xact_lock(hashtextextended('addon-order:'||v_actor.tenant_id::text||':'||v_id::text,0)); end loop;
 -- Validate the entire batch under its locks before writing any row.
 foreach v_id in array v_ids loop
  select o.* into v_order from public.addon_orders o join public.addon_products p on p.tenant_id=o.tenant_id and p.id=o.addon_product_id
  where o.tenant_id=v_actor.tenant_id and o.id=v_id and coalesce(o.sale_snapshot->>'kind',p.kind::text)='pt_package' for update of o;
  if not found or v_order.trainer_staff_id not in (p_from_staff_id,p_to_staff_id) then raise exception 'Pack unavailable' using errcode='42501'; end if;
  if v_order.status<>'active' then raise exception 'Pack unavailable' using errcode='GL055',detail='order_unavailable'; end if;
  if v_target.branch_id is not null and not exists(select 1 from public.members m where m.tenant_id=v_actor.tenant_id and m.id=v_order.member_id and m.branch_id=v_target.branch_id) then raise exception 'Trainer branch differs' using errcode='GL094'; end if;
 end loop;
 select os.* into v_policy from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 select g.name into v_gym from public.organizations g where g.id=v_actor.tenant_id;
 foreach v_id in array v_ids loop
  select o.* into v_order from public.addon_orders o where o.tenant_id=v_actor.tenant_id and o.id=v_id;
  if v_order.trainer_staff_id=p_to_staff_id then return query select v_id,false,0;continue; end if;
  v_count:=0;
  for v_session in select ps.* from public.pt_sessions ps where ps.tenant_id=v_actor.tenant_id and ps.addon_order_id=v_id and ps.status='scheduled' order by ps.id for update loop
   update public.pt_sessions ps set status='cancelled' where ps.tenant_id=v_actor.tenant_id and ps.id=v_session.id;
   insert into public.pt_cancellations(tenant_id,pt_session_id,addon_order_id,member_id,trainer_staff_id,outcome,cancelled_at,cancelled_by_staff_id,window_hours,policy_consumes,was_late,consumed,reason)
   values(v_actor.tenant_id,v_session.id,v_id,v_order.member_id,v_session.trainer_staff_id,'cancelled_by_gym',statement_timestamp(),v_actor.staff_id,v_policy.pt_cancel_window_hours,v_policy.pt_late_cancel_consumes_session,false,false,v_reason);
   v_count:=v_count+1;
  end loop;
  perform set_config('app.pt_reassign_command','reassign:'||v_id::text||':'||p_from_staff_id::text||':'||p_to_staff_id::text,true);
  update public.addon_orders o set trainer_staff_id=p_to_staff_id where o.tenant_id=v_actor.tenant_id and o.id=v_id;
  perform set_config('app.pt_reassign_command',v_previous,true);
  select coalesce(v_order.sale_snapshot->>'name',p.name) into v_programme from public.addon_products p where p.tenant_id=v_actor.tenant_id and p.id=v_order.addon_product_id;
  v_body:=v_gym||' moved your '||v_programme||' pack from '||v_source.full_name||' to '||v_target.full_name||'. '||case when v_count>0 then
  'Sessions booked with '||v_source.full_name||' were cancelled and did not use your pack. Book new times in the app.' else 'You can book times with '||v_target.full_name||' in the app.' end;
  insert into public.notifications as n(tenant_id,member_id,channel,status,category,template_key,related_type,related_id,dedupe_key,payload)
  values(v_actor.tenant_id,v_order.member_id,'in_app','scheduled','fulfilment',v_kind,'addon_order',v_id,'pt:'||v_kind||':'||v_id::text,jsonb_build_object('kind',v_kind,'body',v_body))
  on conflict(tenant_id,dedupe_key) where dedupe_key is not null do nothing returning n.id into v_notice;
  if v_notice is not null then update public.notifications n set status='sent',sent_at=statement_timestamp() where n.id=v_notice; end if;
  perform app.pt_audit(v_actor.tenant_id,v_actor.user_id,v_actor.role,'pt_order.reassigned','addon_order',v_id,jsonb_build_object('trainer_staff_id',p_from_staff_id),jsonb_build_object('trainer_staff_id',p_to_staff_id,'cancelled_sessions',v_count),v_reason);
  return query select v_id,true,v_count;
 end loop;
exception when others then perform set_config('app.pt_reassign_command',v_previous,true);raise;
end
$fn$;

-- Three linked Phase 6 baselines, changed only at the named PTF-023 admission sites.
CREATE OR REPLACE FUNCTION app.addon_order_fully_returned(p_tenant_id uuid, p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_role public.app_role;
  v_member_command boolean := false;
begin
  if auth.uid() is not null then
    if current_user = 'postgres' then
      v_member_command := app.pt_member_command_ok(p_tenant_id, p_order_id, null, array['book']);
    end if;
    if not v_member_command then
      v_role := app.current_app_role();
      if app.current_tenant_id() is distinct from p_tenant_id
         or app.current_staff_id() is null
         or v_role not in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')
         or app.current_impersonation_id() is not null then
        raise exception 'Returned-money state requires a real staff session'
          using errcode = '42501';
      end if;
      if v_role = 'trainer' and not exists (
        select 1 from public.addon_orders o
         where o.tenant_id = p_tenant_id and o.id = p_order_id
           and o.trainer_staff_id = app.current_staff_id()
      ) then
        raise exception 'The PT order belongs to another trainer'
          using errcode = 'GL056', detail = 'trainer_not_yours';
      end if;
    end if;
  end if;

  return exists (
    select 1
      from public.addon_orders o
      join public.payments p
        on p.tenant_id = o.tenant_id and p.id = o.payment_id
     where o.tenant_id = p_tenant_id and o.id = p_order_id
       and p.amount_paise > 0
       and (
         select coalesce(sum(r.amount_paise), 0)
           from public.refunds r
          where r.tenant_id = p.tenant_id and r.payment_id = p.id
            and r.status = 'completed' and r.currency = p.currency
       ) = p.amount_paise
  );
end
$function$;

CREATE OR REPLACE FUNCTION app.enforce_addon_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_product public.addon_products%rowtype;
  v_payment public.payments%rowtype;
  v_session public.pt_sessions%rowtype;
  v_snapshot_keys bigint;
  v_request_keys bigint;
  v_timezone text;
  v_expected_start date;
  v_expected_end date;
  v_kind text;
  v_row public.addon_orders%rowtype;
  v_deferred boolean := coalesce(tg_argv[0], '') = 'deferred';
  v_pt_reassign boolean := false;
  v_pt_completed_waive boolean := false;
begin
  if v_deferred then
    select o.* into v_row from public.addon_orders o
     where o.tenant_id = new.tenant_id and o.id = new.id;
    if found and v_row.idempotency_key is not null
       and v_row.status = 'pending' then
      raise exception 'A keyed add-on sale cannot survive unaccepted'
        using errcode = 'GL055', detail = 'unaccepted_order';
    end if;
    return null;
  end if;

  -- Exact PTF-023 exceptions. OLD proves the terminal pre-change counter;
  -- NEW proves the minus-one result. All other recorded terms stay frozen.
  if tg_op = 'UPDATE' and current_user = 'postgres' then
    v_pt_reassign := old.status = 'active' and new.status = 'active'
      and coalesce(old.sale_snapshot->>'kind', (
        select p.kind::text from public.addon_products p
        where p.tenant_id = old.tenant_id and p.id = old.addon_product_id
      )) = 'pt_package'
      and current_setting('app.pt_reassign_command', true) =
        'reassign:' || old.id::text || ':' || old.trainer_staff_id::text || ':' || new.trainer_staff_id::text
      and (to_jsonb(new) - array['trainer_staff_id','updated_at']) =
          (to_jsonb(old) - array['trainer_staff_id','updated_at'])
      and exists (select 1 from public.staff s where s.tenant_id = old.tenant_id
        and s.id = new.trainer_staff_id and s.role = 'trainer' and s.is_active);
    v_pt_completed_waive := old.status = 'completed' and new.status = 'active'
      and old.sessions_total is not null and old.sessions_used = old.sessions_total
      and new.sessions_used = old.sessions_used - 1
      and new.sessions_used = new.sessions_total - 1
      and (to_jsonb(new) - array['status','sessions_used','updated_at']) =
          (to_jsonb(old) - array['status','sessions_used','updated_at'])
      and coalesce(old.sale_snapshot->>'kind', (
        select p.kind::text from public.addon_products p
        where p.tenant_id = old.tenant_id and p.id = old.addon_product_id
      )) = 'pt_package'
      and auth.uid() is not null and app.current_tenant_id() = old.tenant_id
      and app.current_member_id() is null and app.current_impersonation_id() is null
      and app.current_app_role() in ('gym_owner','gym_manager')
      and exists (select 1 from public.staff s where s.tenant_id = old.tenant_id
        and s.id = app.current_staff_id() and s.user_id = auth.uid()
        and s.role::text = app.current_app_role() and s.is_active
        and s.role in ('gym_owner','gym_manager'))
      and old.starts_on is not null and old.expires_on is not null
      and exists (select 1 from public.organizations g where g.id = old.tenant_id
        and (clock_timestamp() at time zone g.timezone)::date between old.starts_on and old.expires_on)
      and not exists (select 1 from public.refunds r where r.tenant_id = old.tenant_id
        and r.payment_id = old.payment_id)
      and not exists (select 1 from public.pt_sessions ps where ps.tenant_id = old.tenant_id
        and ps.addon_order_id = old.id and ps.status = 'scheduled')
      and exists (select 1 from public.pt_cancellations c join public.pt_sessions ps
        on ps.tenant_id = c.tenant_id and ps.id = c.pt_session_id
        where c.tenant_id = old.tenant_id and c.addon_order_id = old.id
          and c.member_id = old.member_id and c.trainer_staff_id = old.trainer_staff_id
          and ps.addon_order_id = old.id and ps.member_id = old.member_id
          and ps.trainer_staff_id = old.trainer_staff_id and ps.status = 'cancelled'
          and c.outcome = 'cancelled_by_member' and c.was_late and c.policy_consumes
          and c.consumed and c.completed_order and c.waived_at is not null
          and c.waived_by_staff_id = app.current_staff_id()
          and char_length(btrim(c.waive_reason)) between 3 and 200
          -- A command's EXCEPTION block can assign a subtransaction xid.
          -- Its own granted xid lock proves same-transaction provenance too.
          and exists (select 1 from pg_catalog.pg_locks l
            where l.locktype = 'transactionid' and l.transactionid = c.xmin
              and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock')
          and current_setting('app.pt_completed_waive_command', true) =
            'waive:' || c.pt_session_id::text || ':' || old.id::text);
  end if;

  if pg_catalog.row_security_active(tg_relid)
     and (
       auth.uid() is null
       or not app.is_front_office()
       or app.current_tenant_id() is null
       or app.current_staff_id() is null
       or app.current_impersonation_id() is not null
       or new.tenant_id is distinct from app.current_tenant_id()
     ) then
    raise exception 'Writing an add-on order requires a real front-office session'
      using errcode = '42501';
  end if;

  if new.idempotency_key is not null
     and (
       (tg_op = 'INSERT' and new.sessions_used is distinct from 0)
       or (tg_op = 'UPDATE' and old.status = 'pending'
           and (
             new.sessions_used is distinct from old.sessions_used
             or (new.status = 'paid'
                 and (old.sessions_used is distinct from 0
                      or new.sessions_used is distinct from 0))
           ))
     ) then
    raise exception 'Only completed PT sessions may record add-on usage'
      using errcode = 'GL053', detail = 'order_is_a_record';
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.member_id is distinct from old.member_id
       or new.addon_product_id is distinct from old.addon_product_id
       or new.sold_by_staff_id is distinct from old.sold_by_staff_id
       or new.idempotency_key is distinct from old.idempotency_key
       or new.sale_request is distinct from old.sale_request then
      raise exception 'An add-on order is a permanent sale record'
        using errcode = 'GL053', detail = 'order_is_a_record';
    end if;
    if old.status <> 'pending' or old.payment_id is not null then
      if new.payment_id is distinct from old.payment_id
         or new.quantity is distinct from old.quantity
         or new.unit_price_paise is distinct from old.unit_price_paise
         or new.total_paise is distinct from old.total_paise
         or new.currency is distinct from old.currency
         or (new.trainer_staff_id is distinct from old.trainer_staff_id and not coalesce(v_pt_reassign, false))
         or new.sessions_total is distinct from old.sessions_total
         or new.initial_session_id is distinct from old.initial_session_id
         or new.starts_on is distinct from old.starts_on
         or new.expires_on is distinct from old.expires_on
         or new.sold_at is distinct from old.sold_at
         or new.sale_snapshot is distinct from old.sale_snapshot
         or (pg_catalog.row_security_active(tg_relid)
             and new.sessions_used is distinct from old.sessions_used) then
        raise exception 'Accepted add-on terms and usage are frozen'
          using errcode = 'GL053', detail = 'order_is_a_record';
      end if;
    elsif new.status = 'paid' and (
      new.quantity is distinct from old.quantity
      or new.unit_price_paise is distinct from old.unit_price_paise
      or new.total_paise is distinct from old.total_paise
      or new.currency is distinct from old.currency
      or new.trainer_staff_id is distinct from old.trainer_staff_id
      or new.sessions_total is distinct from old.sessions_total
      or new.initial_session_id is distinct from old.initial_session_id
      or new.sale_snapshot is distinct from old.sale_snapshot
      or new.sessions_used is distinct from old.sessions_used
    ) then
      raise exception 'Acceptance cannot rewrite the offered terms'
        using errcode = 'GL053', detail = 'order_is_a_record';
    end if;

    if not (
      old.status = new.status
      or (old.status = 'pending' and new.status in ('paid', 'cancelled'))
      or (old.status = 'paid' and new.status in ('active', 'cancelled', 'refunded'))
      or (old.status = 'active' and new.status in ('completed', 'refunded'))
      or coalesce(v_pt_completed_waive, false)
    ) then
      raise exception 'Invalid add-on order status transition'
        using errcode = 'GL054', detail = 'invalid_order_transition';
    end if;
    if old.status = 'pending' and new.status = 'paid'
       and old.idempotency_key is null then
      raise exception 'A legacy pending order cannot be accepted as a new sale'
        using errcode = 'GL055', detail = 'unaccepted_order';
    end if;
  end if;

  if tg_op = 'INSERT' and pg_catalog.row_security_active(tg_relid)
     and (new.idempotency_key is null
          or new.sold_by_staff_id is null
          or new.sale_snapshot is null
          or new.sale_request is null) then
    raise exception 'Invalid add-on sale snapshot'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  if new.idempotency_key is not null then
    if new.idempotency_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or new.sold_by_staff_id is null
       or new.sale_snapshot is null
       or jsonb_typeof(new.sale_snapshot) <> 'object'
       or new.sale_request is null
       or jsonb_typeof(new.sale_request) <> 'object' then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end if;

    select count(*) into v_snapshot_keys
      from jsonb_object_keys(new.sale_snapshot);
    select count(*) into v_request_keys
      from jsonb_object_keys(new.sale_request);
    if v_snapshot_keys <> 6
       or not (new.sale_snapshot ?& array[
         'kind', 'name', 'description', 'cancellationTerms',
         'validityDays', 'trainerQualification'
       ])
       or v_request_keys <> 9
       or not (new.sale_request ?& array[
         'memberId', 'productId', 'quantity', 'quoteVersion',
         'trainerStaffId', 'initialStartsAt', 'initialEndsAt',
         'method', 'reason'
       ]) then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end if;

    begin
      if new.sale_request->>'memberId' is distinct from new.member_id::text
         or new.sale_request->>'productId' is distinct from new.addon_product_id::text
         or jsonb_typeof(new.sale_request->'quantity') <> 'number'
         or (new.sale_request->>'quantity')::integer is distinct from new.quantity
         or new.total_paise::numeric is distinct from
            new.unit_price_paise::numeric * new.quantity::numeric then
        raise exception 'Invalid add-on sale snapshot'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid add-on sale snapshot'
        using errcode = 'GL055', detail = 'invalid_snapshot';
    end;

    if tg_op = 'INSERT' or (tg_op = 'UPDATE' and old.status = 'pending') then
      select p.* into v_product from public.addon_products p
       where p.tenant_id = new.tenant_id and p.id = new.addon_product_id;
      if not found
         or not v_product.is_active
         or v_product.description is null or btrim(v_product.description) = ''
         or v_product.cancellation_terms is null or btrim(v_product.cancellation_terms) = ''
         or v_product.validity_days is null or v_product.validity_days <= 0
         or v_product.currency <> 'INR'
         or new.sale_request->>'quoteVersion' is distinct from v_product.quote_version::text
         or new.sale_snapshot->>'kind' is distinct from v_product.kind::text
         or new.sale_snapshot->>'name' is distinct from v_product.name
         or new.sale_snapshot->>'description' is distinct from v_product.description
         or new.sale_snapshot->>'cancellationTerms' is distinct from v_product.cancellation_terms
         or jsonb_typeof(new.sale_snapshot->'validityDays') <> 'number'
         or (new.sale_snapshot->>'validityDays')::integer is distinct from v_product.validity_days
         or new.unit_price_paise is distinct from v_product.price_paise
         or new.currency is distinct from v_product.currency
         or (
           v_product.trainer_qualification is null
           and new.sale_snapshot->'trainerQualification' <> 'null'::jsonb
         )
         or (
           v_product.trainer_qualification is not null
           and new.sale_snapshot->>'trainerQualification'
               is distinct from v_product.trainer_qualification
         ) then
        raise exception 'The add-on offer no longer matches the accepted facts'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;

      if exists (
        select 1 from public.members m
         where m.tenant_id = new.tenant_id and m.id = new.member_id
           and (m.status in ('cancelled', 'blocked') or m.erased_at is not null)
      ) then
        raise exception 'The member is unavailable for an add-on sale'
          using errcode = 'GL055', detail = 'member_unavailable';
      end if;

      if v_product.kind in ('pt_package', 'diet_plan')
         and new.quantity <> 1 then
        raise exception 'The add-on quantity is invalid'
          using errcode = 'GL055', detail = 'invalid_quantity';
      end if;

      if v_product.kind = 'pt_package' then
        if v_product.trainer_staff_id is null
           or v_product.trainer_qualification is null
           or btrim(v_product.trainer_qualification) = ''
           or v_product.session_count is null
           or v_product.stock_quantity is not null
           or new.trainer_staff_id is null
           or new.sessions_total is distinct from v_product.session_count
           or (
             exists (
               select 1 from public.staff s
                where s.tenant_id = new.tenant_id
                  and s.id = new.trainer_staff_id
             ) and (
               new.trainer_staff_id is distinct from v_product.trainer_staff_id
               or new.sale_request->>'trainerStaffId'
                    is distinct from v_product.trainer_staff_id::text
             )
           )
           or new.sale_request->'initialStartsAt' = 'null'::jsonb
           or new.sale_request->'initialEndsAt' = 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
        if exists (
          select 1 from public.staff s
           where s.tenant_id = new.tenant_id and s.id = new.trainer_staff_id
             and (s.role <> 'trainer' or not s.is_active)
        ) then
          raise exception 'The selected trainer is unavailable'
            using errcode = 'GL055', detail = 'trainer_unavailable';
        end if;
      elsif v_product.kind = 'product' then
        if v_product.stock_quantity is null
           or v_product.trainer_staff_id is not null
           or v_product.trainer_qualification is not null
           or v_product.session_count is not null
           or new.trainer_staff_id is not null
           or new.sessions_total is not null
           or new.initial_session_id is not null
           or new.sale_request->'trainerStaffId' <> 'null'::jsonb
           or new.sale_request->'initialStartsAt' <> 'null'::jsonb
           or new.sale_request->'initialEndsAt' <> 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
      else
        if v_product.stock_quantity is not null
           or v_product.trainer_staff_id is not null
           or v_product.trainer_qualification is not null
           or v_product.session_count is not null
           or new.trainer_staff_id is not null
           or new.sessions_total is not null
           or new.initial_session_id is not null
           or new.sale_request->'trainerStaffId' <> 'null'::jsonb
           or new.sale_request->'initialStartsAt' <> 'null'::jsonb
           or new.sale_request->'initialEndsAt' <> 'null'::jsonb then
          raise exception 'Invalid add-on sale snapshot'
            using errcode = 'GL055', detail = 'invalid_snapshot';
        end if;
      end if;

      if new.total_paise > 0 then
        if jsonb_typeof(new.sale_request->'method') <> 'string'
           or new.sale_request->>'method' not in ('cash', 'upi', 'card', 'bank_transfer') then
          raise exception 'A paid add-on requires an offline payment method'
            using errcode = 'GL055', detail = 'invalid_payment';
        end if;
      elsif new.sale_request->'method' <> 'null'::jsonb
         or jsonb_typeof(new.sale_request->'reason') <> 'string'
         or btrim(new.sale_request->>'reason') = '' then
        raise exception 'A complimentary add-on requires a reason and no payment'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' and new.idempotency_key is not null
     and new.status <> 'pending' then
    raise exception 'A new sale must begin pending'
      using errcode = 'GL055', detail = 'invalid_snapshot';
  end if;

  -- Payment linkage is a permanent order invariant, including cancellation.
  -- A pending positive sale may still be unpaid, but any attached payment must
  -- already be arrived and match this exact tenant, member, total and currency.
  if new.total_paise = 0 and new.payment_id is not null then
    raise exception 'A complimentary add-on cannot carry a payment'
      using errcode = 'GL055', detail = 'invalid_payment';
  elsif new.payment_id is not null then
    select p.* into v_payment from public.payments p
     where p.tenant_id = new.tenant_id and p.id = new.payment_id;
    if not found
       or v_payment.member_id is distinct from new.member_id
       or v_payment.amount_paise is distinct from new.total_paise
       or v_payment.currency is distinct from new.currency
       or v_payment.status not in ('paid', 'refunded', 'reversed')
       or v_payment.paid_at is null
       or v_payment.membership_id is not null then
      raise exception 'The linked payment does not exactly buy this add-on'
        using errcode = 'GL055', detail = 'invalid_payment';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'pending' and new.status = 'paid' then
    select timezone into v_timezone from public.organizations
     where id = new.tenant_id;
    if v_timezone is null
       or not exists (select 1 from pg_timezone_names where name = v_timezone)
       or new.sold_at is distinct from transaction_timestamp()
       or new.starts_on is null or new.expires_on is null then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end if;
    v_expected_start := (new.sold_at at time zone v_timezone)::date;
    begin
      v_expected_end := v_expected_start
        + ((new.sale_snapshot->>'validityDays')::integer - 1);
    exception when others then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end;
    if new.starts_on is distinct from v_expected_start
       or new.expires_on is distinct from v_expected_end then
      raise exception 'The add-on validity window is invalid'
        using errcode = 'GL055', detail = 'invalid_validity';
    end if;

    if new.total_paise > 0 then
      if new.payment_id is null then
        raise exception 'A paid add-on requires its payment'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
      select p.* into v_payment from public.payments p
       where p.tenant_id = new.tenant_id and p.id = new.payment_id;
      if not found
         or v_payment.member_id is distinct from new.member_id
         or v_payment.amount_paise is distinct from new.total_paise
         or v_payment.currency is distinct from new.currency
         or v_payment.status <> 'paid'
         or v_payment.paid_at is null
         or v_payment.membership_id is not null
         or v_payment.mandate_id is not null
         or v_payment.coupon_id is not null
         or v_payment.provider is not null
         or v_payment.provider_order_id is not null
         or v_payment.provider_payment_id is not null
         or v_payment.recorded_by_staff_id is distinct from new.sold_by_staff_id
         or v_payment.idempotency_key is distinct from 'addon-sale:' || new.idempotency_key
         or v_payment.method::text is distinct from new.sale_request->>'method'
         or v_payment.notes is distinct from new.sale_request->>'reason'
         or exists (
           select 1 from public.refunds r
            where r.tenant_id = v_payment.tenant_id and r.payment_id = v_payment.id
              and r.status = 'completed'
         ) then
        raise exception 'The linked payment does not exactly buy this add-on'
          using errcode = 'GL055', detail = 'invalid_payment';
      end if;
    elsif new.payment_id is not null
       or new.sale_request->'method' <> 'null'::jsonb
       or new.sale_request->'reason' = 'null'::jsonb
       or btrim(new.sale_request->>'reason') = '' then
      raise exception 'A complimentary add-on requires a reason and no payment'
        using errcode = 'GL055', detail = 'invalid_payment';
    end if;

    if new.sale_snapshot->>'kind' = 'pt_package' then
      if new.initial_session_id is null
         or new.sessions_total is null
         or new.trainer_staff_id is null then
        raise exception 'A PT sale requires its initial reservation'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
      select s.* into v_session from public.pt_sessions s
       where s.tenant_id = new.tenant_id and s.id = new.initial_session_id;
      if not found
         or v_session.addon_order_id is distinct from new.id
         or v_session.member_id is distinct from new.member_id
         or v_session.trainer_staff_id is distinct from new.trainer_staff_id
         or v_session.status <> 'scheduled'
         or v_session.starts_at::text is distinct from new.sale_request->>'initialStartsAt'
         or v_session.ends_at::text is distinct from new.sale_request->>'initialEndsAt' then
        raise exception 'The initial PT reservation does not match the sale'
          using errcode = 'GL055', detail = 'invalid_snapshot';
      end if;
    end if;
  end if;

  if tg_op = 'UPDATE' and old.status is distinct from new.status then
    v_kind := coalesce(new.sale_snapshot->>'kind', (
      select p.kind::text from public.addon_products p
       where p.tenant_id = new.tenant_id and p.id = new.addon_product_id
    ));
    if new.status = 'completed' then
      if app.addon_order_fully_returned(new.tenant_id, new.id) then
        raise exception 'A fully returned add-on cannot be delivered'
          using errcode = 'GL055', detail = 'order_unavailable';
      end if;
      if v_kind = 'pt_package' then
        if new.sessions_total is null
           or new.sessions_used is distinct from new.sessions_total then
          raise exception 'PT completes only through consumed sessions'
            using errcode = 'GL055', detail = 'order_unavailable';
        end if;
      elsif v_kind = 'diet_plan' then
        select timezone into v_timezone from public.organizations
         where id = new.tenant_id;
        if v_timezone is null
           or not exists (select 1 from pg_timezone_names where name = v_timezone)
           or new.starts_on is null or new.expires_on is null
           or (clock_timestamp() at time zone v_timezone)::date
                not between new.starts_on and new.expires_on then
          raise exception 'The diet order is outside its delivery window'
            using errcode = 'GL055', detail = 'order_unavailable';
        end if;
      elsif v_kind = 'product' then
        if new.sold_at is null
           or new.sold_at is distinct from transaction_timestamp() then
          raise exception 'A product completes only inside its sale'
            using errcode = 'GL055', detail = 'wrong_order_kind';
        end if;
      else
        raise exception 'The add-on order kind is unsupported'
          using errcode = 'GL055', detail = 'wrong_order_kind';
      end if;
    elsif new.status = 'refunded'
       and not app.addon_order_fully_returned(new.tenant_id, new.id) then
      raise exception 'An add-on becomes refunded only after the full return completed'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;
  end if;

  if tg_op = 'INSERT' and pg_catalog.row_security_active(tg_relid)
     and (
       app.current_staff_id() is null
       or new.sold_by_staff_id is distinct from app.current_staff_id()
     ) then
    raise exception 'The add-on seller must be the acting staff member'
      using errcode = 'GL056', detail = 'seller_not_yours';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION app.lock_addon_order_for_pt_session()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order public.addon_orders%rowtype;
begin
  if tg_relid <> 'public.pt_sessions'::regclass
     or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'Invalid PT order lock source';
  end if;
  begin
    if (current_setting('role', true) = 'authenticated' or auth.role() = 'authenticated' or auth.uid() is not null) and not exists (
      select 1 from public.staff s
       where s.tenant_id = new.tenant_id
         and s.id = app.current_staff_id()
         and s.user_id = auth.uid()
         and s.role::text = app.current_app_role()
         and s.role in ('gym_owner', 'gym_manager', 'front_desk', 'trainer')
         and s.is_active
         and app.current_tenant_id() = new.tenant_id
         and app.current_impersonation_id() is null
    ) and not (
      new.member_id = app.current_member_id()
      and ((tg_op = 'INSERT' and new.status = 'scheduled'
            and app.pt_member_command_ok(new.tenant_id, new.addon_order_id, new.id, array['book']))
           or (tg_op = 'UPDATE' and old.status = 'scheduled' and new.status = 'cancelled'
            and app.pt_member_command_ok(new.tenant_id, new.addon_order_id, new.id, array['cancel'])))
    ) then
      raise exception 'PT order locking requires a real staff session'
        using errcode = '42501';
    end if;
  exception when invalid_text_representation then
    raise exception 'PT order locking requires a real staff session'
      using errcode = '42501';
  end;
  perform pg_advisory_xact_lock(hashtextextended(
    'addon-order:' || new.tenant_id::text || ':' || new.addon_order_id::text, 0
  ));
  select o.* into v_order from public.addon_orders o
   where o.tenant_id = new.tenant_id and o.id = new.addon_order_id
   for update;
  if found then
    if tg_op = 'INSERT'
       and app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    elsif tg_op = 'UPDATE'
       and old.status = 'scheduled' and new.status = 'completed'
       and app.addon_order_fully_returned(v_order.tenant_id, v_order.id) then
      raise exception 'The order is unavailable for PT fulfilment'
        using errcode = 'GL055', detail = 'order_unavailable';
    end if;
  end if;
  return new;
end
$function$;

-- Explicit owners/audiences defeat Supabase's permissive function defaults.
do $privileges$
declare v_name text;v_signature text;
begin
 foreach v_name in array array[
  'read_member_trainers','read_member_programmes','read_member_pt_packs','read_member_pt_sessions','read_member_pt_slots',
  'book_pt_session','cancel_pt_booking','set_trainer_profile','set_own_trainer_profile','set_trainer_availability',
  'add_trainer_time_off','remove_trainer_time_off','read_pt_bookings','read_pt_packs','cancel_pt_session_as_gym',
  'waive_pt_forfeit','reassign_pt_packs','set_pt_policy'] loop
  select p.oid::regprocedure::text into strict v_signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=v_name;
  execute 'alter function '||v_signature||' owner to postgres';
  execute 'revoke all on function '||v_signature||' from public,anon,authenticated,service_role';
  execute 'grant execute on function '||v_signature||' to authenticated';
 end loop;
 foreach v_name in array array['pt_audit','pt_member_actor','pt_staff_actor','pt_member_command_ok','pt_slot_state','pt_trainer_key','pt_booking_status','pt_pack_state','guard_pt_policy_write','guard_pt_cancellation_completion','pt_write_profile'] loop
  select p.oid::regprocedure::text into strict v_signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app' and p.proname=v_name;
  execute 'alter function '||v_signature||' owner to postgres';
  execute 'revoke all on function '||v_signature||' from public,anon,authenticated,service_role';
 end loop;
end
$privileges$;
