-- PTF-008 / PTF-017: private absolute-time grid and target-first reassignment.
create function app.pt_availability_grid(p_gym_timezone text,p_trainer_timezone text,p_from date,p_to date,p_windows jsonb,p_session_minutes integer)
returns table(starts_at timestamptz,ends_at timestamptz)
language plpgsql stable security invoker set search_path='' as $fn$
declare v_window jsonb;v_key text;v_number numeric;v_lower timestamptz;v_upper timestamptz;
begin
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) then
  raise exception 'Invalid slot range' using errcode='22023',detail='range_invalid';
 end if;
 if p_to<p_from or p_to-p_from>=14 then raise exception 'Invalid slot range' using errcode='22023',detail='range_invalid'; end if;
 if p_gym_timezone is null or p_trainer_timezone is null
 or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p_gym_timezone)
 or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p_trainer_timezone) then
  raise exception 'Invalid timezone' using errcode='22023';
 end if;
 if p_session_minutes is null or p_session_minutes not between 15 and 180 or p_session_minutes%5<>0 then
  raise exception 'Invalid session duration' using errcode='22023';
 end if;
 if p_windows is null or jsonb_typeof(p_windows)<>'array' then raise exception 'Invalid availability' using errcode='22023'; end if;
 if jsonb_array_length(p_windows)>28 then raise exception 'Invalid availability' using errcode='22023'; end if;
 for v_window in select x.value from jsonb_array_elements(p_windows) x loop
  if jsonb_typeof(v_window)<>'object' then raise exception 'Invalid availability' using errcode='22023'; end if;
  if (select count(*) from jsonb_object_keys(v_window))<>3 or not (v_window ?& array['weekday','startMinute','endMinute']) then
   raise exception 'Invalid availability' using errcode='22023';
  end if;
  foreach v_key in array array['weekday','startMinute','endMinute'] loop
   if jsonb_typeof(v_window->v_key) is distinct from 'number' then raise exception 'Invalid availability' using errcode='22023'; end if;
   v_number:=(v_window->>v_key)::numeric;
   if v_number<>trunc(v_number) or v_number<0 or v_number>(case when v_key='weekday' then 6 else 1440 end) then
    raise exception 'Invalid availability' using errcode='22023';
   end if;
  end loop;
  if (v_window->>'startMinute')::numeric::integer >= (v_window->>'endMinute')::numeric::integer then raise exception 'Invalid availability' using errcode='22023'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_windows) with ordinality a(w,n)
 join jsonb_array_elements(p_windows) with ordinality b(w,n) on a.n<b.n
 and (a.w->>'weekday')::numeric::integer=(b.w->>'weekday')::numeric::integer
 and (a.w->>'startMinute')::numeric::integer<(b.w->>'endMinute')::numeric::integer
 and (b.w->>'startMinute')::numeric::integer<(a.w->>'endMinute')::numeric::integer) then
  raise exception 'Overlapping availability' using errcode='22023';
 end if;
 if jsonb_array_length(p_windows)=0 then return; end if;
 -- PostgreSQL-supported timezone displacements are strictly less than 24
 -- hours. UTC midnight plus that displacement envelope contains every
 -- absolute instant on the requested gym-local dates, including date-line
 -- changes. Enumerate absolute seconds so historical second offsets, folds
 -- and gaps require no inference about transition spacing or tzdb version.
 -- The exact local date and zero-second predicates reject normalization.
 v_lower:=(p_from::timestamp at time zone 'UTC')-interval '24 hours';
 v_upper:=((p_to+1)::timestamp at time zone 'UTC')+interval '24 hours';
 return query
 select s.instant,s.instant+make_interval(mins=>p_session_minutes)
 from generate_series(v_lower,v_upper,interval '1 second') s(instant)
 cross join lateral(select s.instant at time zone p_trainer_timezone as wall) t
 where (s.instant at time zone p_gym_timezone)::date between p_from and p_to
 and extract(second from t.wall)=0
 and exists(select 1 from jsonb_array_elements(p_windows) w(value)
  where (w.value->>'weekday')::numeric::integer=extract(dow from t.wall)::integer
  and (extract(hour from t.wall)::integer*60+extract(minute from t.wall)::integer)>=(w.value->>'startMinute')::numeric::integer
  and (extract(hour from t.wall)::integer*60+extract(minute from t.wall)::integer)+p_session_minutes<=(w.value->>'endMinute')::numeric::integer
  and (extract(hour from t.wall)::integer*60+extract(minute from t.wall)::integer-(w.value->>'startMinute')::numeric::integer)%p_session_minutes=0)
 order by s.instant;
exception when datetime_field_overflow or numeric_value_out_of_range then
 raise exception 'Unsupported slot arithmetic boundary' using errcode='22023',detail='range_invalid';
end
$fn$;
alter function app.pt_availability_grid(text,text,date,date,jsonb,integer) owner to postgres;
revoke all on function app.pt_availability_grid(text,text,date,date,jsonb,integer) from public,anon,authenticated,service_role;

create or replace function public.read_member_pt_slots(p_order_id uuid,p_from date,p_to date) returns table(starts_at timestamptz,ends_at timestamptz,timezone text)
language plpgsql stable security definer set search_path='' as $fn$
declare v_actor record;v_pack record;v_length integer;v_gym_zone text;v_windows jsonb;
begin
 select * into v_actor from app.pt_member_actor();
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) then raise exception 'Invalid slot range' using errcode='22023',detail='range_invalid'; end if;
 if p_to<p_from or p_to-p_from>=14 then raise exception 'Invalid slot range' using errcode='22023',detail='range_invalid'; end if;
 select x.*,o.trainer_staff_id into v_pack from public.read_member_pt_packs() x join public.addon_orders o on o.id=x.order_id and o.tenant_id=v_actor.tenant_id where x.order_id=p_order_id;
 if not found or not v_pack.can_book then return; end if;
 select os.pt_session_minutes into v_length from public.organization_settings os where os.tenant_id=v_actor.tenant_id;
 select g.timezone into v_gym_zone from public.organizations g where g.id=v_actor.tenant_id;
 select coalesce(jsonb_agg(jsonb_build_object('weekday',a.weekday,'startMinute',a.start_minute,'endMinute',a.end_minute)),'[]'::jsonb)
 into v_windows from public.trainer_availability a where a.tenant_id=v_actor.tenant_id and a.staff_id=v_pack.trainer_staff_id;
 return query select q.starts_at,q.ends_at,v_pack.timezone::text
 from app.pt_availability_grid(v_gym_zone,v_pack.timezone,p_from,p_to,v_windows,v_length) q
 where app.pt_slot_state(v_actor.tenant_id,v_pack.trainer_staff_id,q.starts_at)='open'
 and q.starts_at>=v_pack.starts_on::timestamp at time zone v_pack.timezone
 and q.ends_at<=(v_pack.expires_on+1)::timestamp at time zone v_pack.timezone
 and q.starts_at>=v_pack.starts_on::timestamp at time zone v_gym_zone
 and q.ends_at<=(v_pack.expires_on+1)::timestamp at time zone v_gym_zone
 order by q.starts_at limit 400;
end
$fn$;
create or replace function public.reassign_pt_packs(p_from_staff_id uuid,p_to_staff_id uuid,p_order_ids uuid[],p_reason text)
returns table(order_id uuid,changed boolean,cancelled_sessions integer)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor record;v_ids uuid[];v_id uuid;v_order public.addon_orders%rowtype;v_target public.staff%rowtype;v_source public.staff%rowtype;v_session public.pt_sessions%rowtype;
 v_reason text:=btrim(p_reason);v_count integer;v_policy public.organization_settings%rowtype;v_gym text;v_programme text;v_body text;v_notice uuid;
 v_previous text:=coalesce(current_setting('app.pt_reassign_command',true),'');v_kind text:='pt_pack_reassigned';
begin
 select * into v_actor from app.pt_staff_actor(array['gym_owner','gym_manager']);
 if p_from_staff_id is null or p_to_staff_id is null then raise exception 'Trainer ids required' using errcode='22023'; end if;
 if v_reason is null or char_length(v_reason) not between 3 and 200 then raise exception 'Invalid reason' using errcode='22023',detail='reason_invalid'; end if;
 if p_order_ids is not null and cardinality(p_order_ids)>100 then raise exception 'Batch too large' using errcode='22023',detail='batch_too_large'; end if;
 perform app.booking_lock(v_actor.tenant_id,'trainer_slot',least(p_from_staff_id,p_to_staff_id));
 perform app.booking_lock(v_actor.tenant_id,'trainer_slot',greatest(p_from_staff_id,p_to_staff_id));
 select s.* into v_target from public.staff s where s.tenant_id=v_actor.tenant_id and s.id=p_to_staff_id for share;
 if not found or v_target.role<>'trainer' or not v_target.is_active then raise exception 'Trainer unavailable' using errcode='GL055',detail='trainer_unavailable'; end if;
 if p_from_staff_id=p_to_staff_id then raise exception 'Same trainer' using errcode='22023',detail='same_trainer'; end if;
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
