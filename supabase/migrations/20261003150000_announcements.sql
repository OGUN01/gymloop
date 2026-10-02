-- ANC: pull-based announcements, immutable published versions, private receipts.
-- Notification vocabulary comes from the separately committed 083000 prelude.
create type public.announcement_kind as enum ('transactional','promotional');
create type public.announcement_status as enum ('draft','published','unpublished','discarded');
create type public.announcement_audience as enum ('all_members','segment');
create type public.announcement_membership_filter as enum ('any','live','not_live');

create table public.announcements (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id),
 kind public.announcement_kind not null,
 status public.announcement_status not null default 'draft',
 audience public.announcement_audience not null default 'all_members',
 segment_member_statuses public.member_status[],
 segment_membership public.announcement_membership_filter,
 current_version integer not null default 1,
 expires_at timestamptz, published_at timestamptz, closed_at timestamptz,
 created_by_staff_id uuid not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint announcements_tenant_id_id_key unique(tenant_id,id),
 constraint announcements_tenant_id_created_by_staff_id_fkey foreign key(tenant_id,created_by_staff_id) references public.staff(tenant_id,id),
 constraint announcements_segment_shape_chk check (
  (audience='all_members' and segment_member_statuses is null and segment_membership is null) or
  (audience='segment' and segment_member_statuses is not null and cardinality(segment_member_statuses) between 1 and 3
   and segment_member_statuses <@ array['active','paused','expired']::public.member_status[] and segment_membership is not null)),
 constraint announcements_state_chk check (
  (status='draft' and published_at is null and closed_at is null) or
  (status='published' and published_at is not null and closed_at is null) or
  (status='unpublished' and published_at is not null and closed_at is not null) or
  (status='discarded' and published_at is null and closed_at is not null)),
 constraint announcements_version_chk check(current_version>=1),
 constraint announcements_expiry_chk check(expires_at is null or published_at is null or expires_at>published_at)
);
create table public.announcement_versions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
 announcement_id uuid not null, version_no integer not null, title text not null, body text not null,
 image_asset_id uuid, change_note text, created_by_staff_id uuid not null,
 created_at timestamptz not null default now(),
 constraint announcement_versions_tenant_id_id_key unique(tenant_id,id),
 constraint announcement_versions_announcement_version_key unique(tenant_id,announcement_id,version_no),
 constraint announcement_versions_tenant_id_announcement_id_fkey foreign key(tenant_id,announcement_id) references public.announcements(tenant_id,id),
 constraint announcement_versions_tenant_id_created_by_staff_id_fkey foreign key(tenant_id,created_by_staff_id) references public.staff(tenant_id,id),
 constraint announcement_versions_tenant_id_image_asset_id_fkey foreign key(tenant_id,image_asset_id) references public.media_assets(tenant_id,id),
 constraint announcement_versions_version_no_chk check(version_no>=1),
 constraint announcement_versions_title_chk check(char_length(btrim(title)) between 1 and 80),
 constraint announcement_versions_body_chk check(char_length(btrim(body)) between 1 and 1500),
 constraint announcement_versions_change_note_chk check((version_no=1 and change_note is null) or
  (version_no>1 and change_note is not null and char_length(btrim(change_note)) between 3 and 200))
);
create table public.announcement_receipts (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.organizations(id),
 version_id uuid not null, member_id uuid not null, read_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 constraint announcement_receipts_version_member_key unique(tenant_id,version_id,member_id),
 constraint announcement_receipts_tenant_id_version_id_fkey foreign key(tenant_id,version_id) references public.announcement_versions(tenant_id,id),
 constraint announcement_receipts_tenant_id_member_id_fkey foreign key(tenant_id,member_id) references public.members(tenant_id,id)
);
create index announcements_tenant_created_idx on public.announcements(tenant_id,created_at desc,id desc);
create index announcements_tenant_published_idx on public.announcements(tenant_id,published_at desc) where status='published';
create index announcements_tenant_creator_idx on public.announcements(tenant_id,created_by_staff_id);
create index announcement_versions_tenant_image_idx on public.announcement_versions(tenant_id,image_asset_id) where image_asset_id is not null;
create index announcement_versions_tenant_creator_idx on public.announcement_versions(tenant_id,created_by_staff_id);
create index announcement_receipts_tenant_member_idx on public.announcement_receipts(tenant_id,member_id);
alter table public.announcements enable row level security;
alter table public.announcement_versions enable row level security;
alter table public.announcement_receipts enable row level security;
revoke all on public.announcements,public.announcement_versions,public.announcement_receipts from anon,authenticated;
grant select on public.announcements,public.announcement_versions,public.announcement_receipts to authenticated;
grant select on public.announcements,public.announcement_versions,public.announcement_receipts to service_role;
create policy announcements_tenant_select on public.announcements for select to authenticated
 using(tenant_id=(select app.current_tenant_id()) and (select app.is_front_office()));
create policy announcement_versions_tenant_select on public.announcement_versions for select to authenticated
 using(tenant_id=(select app.current_tenant_id()) and (select app.is_front_office()));
create policy announcement_receipts_member_select on public.announcement_receipts for select to authenticated
 using(tenant_id=(select app.current_tenant_id()) and (select app.current_app_role())='member'
 and member_id=(select app.current_member_id()));

create function app.announcement_actor(p_roles text[],p_allow_preview boolean default false) returns uuid
language plpgsql stable security invoker set search_path='' as $fn$
begin
 if auth.uid() is null or app.current_tenant_id() is null or app.current_app_role() is null
  or not (app.current_app_role()=any(p_roles)) or app.current_member_id() is not null then
  raise exception 'Announcement actor unavailable' using errcode='42501';
 end if;
 if app.current_impersonation_id() is not null then
  if p_allow_preview then return null; end if;
  raise exception 'Announcement actor unavailable' using errcode='42501';
 end if;
 if app.current_staff_id() is null or not exists(select 1 from public.staff s
  where s.tenant_id=app.current_tenant_id() and s.id=app.current_staff_id()
  and s.user_id=auth.uid() and s.role::text=app.current_app_role() and s.is_active) then
  raise exception 'Announcement actor unavailable' using errcode='42501';
 end if;
 return app.current_staff_id();
end
$fn$;
create function app.announcement_member_actor() returns uuid
language plpgsql stable security invoker set search_path='' as $fn$
begin
 if auth.uid() is null or app.current_tenant_id() is null or app.current_app_role() is distinct from 'member'
  or app.current_member_id() is null or app.current_staff_id() is not null or app.current_impersonation_id() is not null
  or not exists(select 1 from public.members m where m.tenant_id=app.current_tenant_id()
   and m.id=app.current_member_id() and m.user_id=auth.uid() and m.status in ('active','paused','expired') and m.erased_at is null) then
  raise exception 'Announcement member unavailable' using errcode='42501';
 end if;
 return app.current_member_id();
end
$fn$;
create function app.announcement_audience(p_announcement_id uuid,p_member_id uuid default null) returns setof uuid
language sql stable security invoker set search_path='' as $fn$
 select m.id from public.announcements a join public.members m on m.tenant_id=a.tenant_id
 where a.id=p_announcement_id and (p_member_id is null or m.id=p_member_id)
  and m.status in ('active','paused','expired') and m.erased_at is null
  and (a.kind='transactional' or coalesce((select c.granted from public.consents c
   where c.tenant_id=m.tenant_id and c.member_id=m.id and c.purpose='marketing'
   order by c.recorded_at desc,c.id desc limit 1),false))
  and (a.audience='all_members' or (m.status=any(a.segment_member_statuses) and
   (a.segment_membership='any' or (a.segment_membership='live')=
    app.member_has_live_membership(m.tenant_id,m.id,app.gym_today(m.tenant_id)))))
$fn$;
create function app.announcement_audit(p_tenant_id uuid,p_actor uuid,p_role public.app_role,p_action text,p_record_id uuid,p_before jsonb,p_after jsonb,p_reason text) returns void
language plpgsql volatile security definer set search_path='' as $fn$
begin
 if p_action is null or p_action not in ('announcement.drafted','announcement.discarded','announcement.published','announcement.edited','announcement.unpublished') then
  raise exception 'Unsupported announcement audit action' using errcode='22023';
 end if;
 insert into public.audit_log(tenant_id,actor_user_id,actor_role,action,record_type,record_id,before,after,reason)
 values(p_tenant_id,p_actor,p_role,p_action,'announcement',p_record_id,p_before,p_after,p_reason);
end
$fn$;
create function app.enforce_announcement() returns trigger
language plpgsql volatile security invoker set search_path='' as $fn$
begin
 if tg_op='UPDATE' then
  if new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id
   or new.created_by_staff_id is distinct from old.created_by_staff_id or new.created_at is distinct from old.created_at
   or (old.status<>'draft' and (new.kind is distinct from old.kind or new.audience is distinct from old.audience
    or new.segment_member_statuses is distinct from old.segment_member_statuses or new.segment_membership is distinct from old.segment_membership))
   or (old.published_at is not null and new.published_at is distinct from old.published_at)
   or (old.closed_at is not null and new.closed_at is distinct from old.closed_at) then
   raise exception 'Announcement field frozen' using errcode='GL088',detail='field_frozen';
  end if;
  if (new.status is distinct from old.status and not ((old.status='draft' and new.status in ('published','discarded'))
    or (old.status='published' and new.status='unpublished')))
   or (new.current_version is distinct from old.current_version and not
    (old.status='published' and new.status='published' and new.current_version=old.current_version+1)) then
   raise exception 'Announcement transition refused' using errcode='GL088',detail='invalid_transition';
  end if;
 end if;
 new.updated_at:=statement_timestamp();
 return new;
end
$fn$;
create function app.enforce_announcement_version() returns trigger
language plpgsql volatile security invoker set search_path='' as $fn$
begin
 if tg_op='DELETE' then raise exception 'Announcement version immutable' using errcode='GL088',detail='version_immutable'; end if;
 if old.version_no<>1 or not exists(select 1 from public.announcements a
  where a.tenant_id=old.tenant_id and a.id=old.announcement_id and a.status='draft')
  or new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id
  or new.announcement_id is distinct from old.announcement_id or new.version_no is distinct from old.version_no
  or new.created_by_staff_id is distinct from old.created_by_staff_id or new.created_at is distinct from old.created_at
  or new.change_note is not null or old.change_note is not null then
  raise exception 'Announcement version immutable' using errcode='GL088',detail='version_immutable';
 end if;
 return new;
end
$fn$;
create trigger announcements_touch_updated_at before insert or update on public.announcements
 for each row execute function app.enforce_announcement();
create trigger announcement_versions_touch_updated_at before update or delete on public.announcement_versions
 for each row execute function app.enforce_announcement_version();

create function public.create_announcement_draft(p_kind public.announcement_kind,p_title text,p_body text,p_audience public.announcement_audience,p_segment_member_statuses public.member_status[],p_segment_membership public.announcement_membership_filter,p_expires_at timestamptz,p_image_asset_id uuid) returns uuid
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_id uuid:=gen_random_uuid();
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager','front_desk']); v_tenant:=app.current_tenant_id();
 if p_kind is null or p_audience is null or p_title is null or char_length(btrim(p_title)) not between 1 and 80
  or p_body is null or char_length(btrim(p_body)) not between 1 and 1500
  or (p_audience='all_members' and (p_segment_member_statuses is not null or p_segment_membership is not null))
  or (p_audience='segment' and (p_segment_member_statuses is null or cardinality(p_segment_member_statuses) not between 1 and 3
   or not (p_segment_member_statuses <@ array['active','paused','expired']::public.member_status[])
   or array_position(p_segment_member_statuses,null) is not null or p_segment_membership is null
   or cardinality(p_segment_member_statuses)<>(select count(distinct x) from unnest(p_segment_member_statuses) x))) then
  raise exception 'Invalid announcement input' using errcode='22023'; end if;
 if p_image_asset_id is not null then
  perform 1 from public.media_assets m where m.tenant_id=v_tenant and m.id=p_image_asset_id
   and m.kind='announcement' and m.confirmed_at is not null and m.deleted_at is null
   and (m.attached_to_id is null or m.attached_to_id=v_id) for update;
  if not found then raise exception 'Announcement image unavailable' using errcode='GL088',detail='image_unavailable'; end if;
 end if;
 insert into public.announcements(id,tenant_id,kind,audience,segment_member_statuses,segment_membership,expires_at,created_by_staff_id)
 values(v_id,v_tenant,p_kind,p_audience,p_segment_member_statuses,p_segment_membership,p_expires_at,v_actor);
 if p_image_asset_id is not null then perform app.media_attach(v_tenant,p_image_asset_id,'announcement',v_id); end if;
 insert into public.announcement_versions(tenant_id,announcement_id,version_no,title,body,image_asset_id,created_by_staff_id)
 values(v_tenant,v_id,1,btrim(p_title),btrim(p_body),p_image_asset_id,v_actor);
 perform app.announcement_audit(v_tenant,auth.uid(),app.current_app_role()::public.app_role,'announcement.drafted',v_id,null,
  jsonb_build_object('status','draft','kind',p_kind,'audience',p_audience),null);
 return v_id;
end
$fn$;
create function public.update_announcement_draft(p_announcement_id uuid,p_kind public.announcement_kind,p_title text,p_body text,p_audience public.announcement_audience,p_segment_member_statuses public.member_status[],p_segment_membership public.announcement_membership_filter,p_expires_at timestamptz,p_image_asset_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_id uuid; v_a public.announcements%rowtype; v_old_image uuid;
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager','front_desk']); v_tenant:=app.current_tenant_id(); v_id:=p_announcement_id;
 select a.* into v_a from public.announcements a where a.tenant_id=v_tenant and a.id=p_announcement_id and a.status<>'discarded' for update;
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 if p_kind is null or p_audience is null or p_title is null or char_length(btrim(p_title)) not between 1 and 80
  or p_body is null or char_length(btrim(p_body)) not between 1 and 1500
  or (p_audience='all_members' and (p_segment_member_statuses is not null or p_segment_membership is not null))
  or (p_audience='segment' and (p_segment_member_statuses is null or cardinality(p_segment_member_statuses) not between 1 and 3
   or not (p_segment_member_statuses <@ array['active','paused','expired']::public.member_status[])
   or array_position(p_segment_member_statuses,null) is not null or p_segment_membership is null
   or cardinality(p_segment_member_statuses)<>(select count(distinct x) from unnest(p_segment_member_statuses) x))) then
  raise exception 'Invalid announcement input' using errcode='22023'; end if;
 if v_a.status<>'draft' then raise exception 'Announcement is not a draft' using errcode='GL088',detail='not_draft'; end if;
 select v.image_asset_id into v_old_image from public.announcement_versions v where v.tenant_id=v_tenant and v.announcement_id=v_id and v.version_no=1 for update;
 if p_image_asset_id is not null then
  perform 1 from public.media_assets m where m.tenant_id=v_tenant and m.id=p_image_asset_id
   and m.kind='announcement' and m.confirmed_at is not null and m.deleted_at is null
   and (m.attached_to_id is null or m.attached_to_id=v_id) for update;
  if not found then raise exception 'Announcement image unavailable' using errcode='GL088',detail='image_unavailable'; end if;
 end if;
 if v_old_image is distinct from p_image_asset_id then
  perform app.media_release(v_tenant,'announcement',v_id);
  if p_image_asset_id is not null then perform app.media_attach(v_tenant,p_image_asset_id,'announcement',v_id); end if;
 end if;
 update public.announcements set kind=p_kind,audience=p_audience,segment_member_statuses=p_segment_member_statuses,
  segment_membership=p_segment_membership,expires_at=p_expires_at where id=v_id;
 update public.announcement_versions set title=btrim(p_title),body=btrim(p_body),image_asset_id=p_image_asset_id
  where tenant_id=v_tenant and announcement_id=v_id and version_no=1;
end
$fn$;
create function public.discard_announcement_draft(p_announcement_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_a public.announcements%rowtype;
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager','front_desk']); v_tenant:=app.current_tenant_id();
 select a.* into v_a from public.announcements a where a.tenant_id=v_tenant and a.id=p_announcement_id and a.status<>'discarded' for update;
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 if v_a.status<>'draft' then raise exception 'Announcement is not a draft' using errcode='GL088',detail='not_draft'; end if;
 perform app.media_release(v_tenant,'announcement',v_a.id);
 update public.announcements set status='discarded',closed_at=statement_timestamp() where id=v_a.id;
 perform app.announcement_audit(v_tenant,auth.uid(),app.current_app_role()::public.app_role,'announcement.discarded',v_a.id,
  jsonb_build_object('status','draft'),jsonb_build_object('status','discarded'),null);
end
$fn$;
create function public.publish_announcement(p_announcement_id uuid)
returns table(published_at timestamptz,expires_at timestamptz,audience_count integer)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_a public.announcements%rowtype; v_image uuid; v_count integer;
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager']); v_tenant:=app.current_tenant_id();
 perform pg_advisory_xact_lock(hashtextextended('announcements:' || v_tenant::text,0));
 select a.* into v_a from public.announcements a where a.tenant_id=v_tenant and a.id=p_announcement_id and a.status<>'discarded' for update;
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 if v_a.status<>'draft' then raise exception 'Announcement is not a draft' using errcode='GL088',detail='not_draft'; end if;
 select v.image_asset_id into v_image from public.announcement_versions v
  where v.tenant_id=v_tenant and v.announcement_id=v_a.id and v.version_no=v_a.current_version for update;
 if v_image is not null then
  perform 1 from public.media_assets m where m.tenant_id=v_tenant and m.id=v_image and m.kind='announcement'
   and m.confirmed_at is not null and m.deleted_at is null and m.attached_to_id=v_a.id for update;
  if not found then raise exception 'Announcement image unavailable' using errcode='GL088',detail='image_unavailable'; end if;
 end if;
 if v_a.expires_at is not null and (v_a.expires_at<=statement_timestamp() or v_a.expires_at>statement_timestamp()+interval '365 days') then
  raise exception 'Invalid announcement expiry' using errcode='GL088',detail='expiry_invalid'; end if;
 if (select count(*) from public.announcements a where a.tenant_id=v_tenant and a.status='published'
  and (a.expires_at is null or a.expires_at>statement_timestamp()))>=10 then
  raise exception 'Announcement live limit reached' using errcode='GL088',detail='live_limit'; end if;
 if (select count(*) from public.announcements a where a.tenant_id=v_tenant and a.published_at>statement_timestamp()-interval '24 hours')>=20 then
  raise exception 'Announcement publish rate reached' using errcode='GL088',detail='publish_rate_limited'; end if;
 select count(*)::integer into v_count from app.announcement_audience(v_a.id);
 update public.announcements set status='published',published_at=statement_timestamp() where id=v_a.id;
 perform app.announcement_audit(v_tenant,auth.uid(),app.current_app_role()::public.app_role,'announcement.published',v_a.id,
  jsonb_build_object('status','draft'),jsonb_build_object('status','published','kind',v_a.kind,'audience',v_a.audience,
   'version_no',1,'expires_at',v_a.expires_at,'audience_count',v_count),null);
 return query select statement_timestamp(),v_a.expires_at,v_count;
end
$fn$;
create function public.edit_announcement(p_announcement_id uuid,p_expected_version integer,p_title text,p_body text,
 p_image_asset_id uuid,p_expires_at timestamptz,p_change_note text)
returns table(version_no integer,new_version boolean)
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_id uuid; v_a public.announcements%rowtype; v_v public.announcement_versions%rowtype; v_changed boolean; v_next integer;
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager']); v_tenant:=app.current_tenant_id(); v_id:=p_announcement_id;
 select a.* into v_a from public.announcements a where a.tenant_id=v_tenant and a.id=p_announcement_id and a.status<>'discarded' for update;
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 select v.* into v_v from public.announcement_versions v where v.tenant_id=v_tenant and v.announcement_id=v_id and v.version_no=v_a.current_version for update;
 v_changed:=v_v.title is distinct from btrim(p_title) or v_v.body is distinct from btrim(p_body) or v_v.image_asset_id is distinct from p_image_asset_id;
 if p_expected_version is null or p_expected_version<1 or p_title is null or char_length(btrim(p_title)) not between 1 and 80
  or p_body is null or char_length(btrim(p_body)) not between 1 and 1500
  or (p_change_note is not null and char_length(btrim(p_change_note)) not between 3 and 200)
  or (v_changed and p_change_note is null) then raise exception 'Invalid announcement edit' using errcode='22023'; end if;
 if v_a.status<>'published' or (v_a.expires_at is not null and v_a.expires_at<=statement_timestamp()) then
  raise exception 'Announcement is not live' using errcode='GL088',detail='not_live'; end if;
 if p_expected_version<>v_a.current_version then raise exception 'Announcement version conflict' using errcode='GL088',detail='version_conflict'; end if;
 if p_image_asset_id is not null then
  perform 1 from public.media_assets m where m.tenant_id=v_tenant and m.id=p_image_asset_id
   and m.kind='announcement' and m.confirmed_at is not null and m.deleted_at is null
   and (m.attached_to_id is null or m.attached_to_id=v_id) for update;
  if not found then raise exception 'Announcement image unavailable' using errcode='GL088',detail='image_unavailable'; end if;
 end if;
 if p_expires_at is not null and (p_expires_at<=statement_timestamp() or p_expires_at>statement_timestamp()+interval '365 days') then
  raise exception 'Invalid announcement expiry' using errcode='GL088',detail='expiry_invalid'; end if;
 if not v_changed and p_expires_at is not distinct from v_a.expires_at then
  raise exception 'Announcement unchanged' using errcode='GL088',detail='no_change'; end if;
 if v_changed and v_a.current_version>=10 then raise exception 'Announcement version limit reached' using errcode='GL088',detail='version_limit'; end if;
 v_next:=v_a.current_version;
 if v_changed then
  if v_v.image_asset_id is distinct from p_image_asset_id then
   perform app.media_release(v_tenant,'announcement',v_id);
   if p_image_asset_id is not null then perform app.media_attach(v_tenant,p_image_asset_id,'announcement',v_id); end if;
  end if;
  v_next:=v_next+1;
  insert into public.announcement_versions(tenant_id,announcement_id,version_no,title,body,image_asset_id,change_note,created_by_staff_id)
   values(v_tenant,v_id,v_next,btrim(p_title),btrim(p_body),p_image_asset_id,btrim(p_change_note),v_actor);
 end if;
 update public.announcements set current_version=v_next,expires_at=p_expires_at where id=v_id;
 perform app.announcement_audit(v_tenant,auth.uid(),app.current_app_role()::public.app_role,'announcement.edited',v_id,
  jsonb_build_object('version_no',v_a.current_version,'expires_at',v_a.expires_at),
  jsonb_build_object('version_no',v_next,'expires_at',p_expires_at,'content_changed',v_changed),case when v_changed then btrim(p_change_note) else null end);
 return query select v_next,v_changed;
end
$fn$;
create function public.unpublish_announcement(p_announcement_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $fn$
declare v_actor uuid; v_tenant uuid; v_a public.announcements%rowtype;
begin
 v_actor:=app.announcement_actor(array['gym_owner','gym_manager']); v_tenant:=app.current_tenant_id();
 select a.* into v_a from public.announcements a where a.tenant_id=v_tenant and a.id=p_announcement_id and a.status<>'discarded' for update;
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 if v_a.status<>'published' then raise exception 'Announcement is not published' using errcode='GL088',detail='not_published'; end if;
 update public.announcements set status='unpublished',closed_at=statement_timestamp() where id=v_a.id;
 perform app.announcement_audit(v_tenant,auth.uid(),app.current_app_role()::public.app_role,'announcement.unpublished',v_a.id,
  jsonb_build_object('status','published','version_no',v_a.current_version),jsonb_build_object('status','unpublished'),null);
end
$fn$;

create function public.list_announcements(p_before_created_at timestamptz default null,p_before_id uuid default null)
returns table(announcement_id uuid,kind public.announcement_kind,status public.announcement_status,display_status text,
 audience public.announcement_audience,segment_member_statuses public.member_status[],segment_membership public.announcement_membership_filter,
 title text,current_version integer,created_at timestamptz,published_at timestamptz,expires_at timestamptz,closed_at timestamptz,
 audience_count integer,read_current integer,read_any integer)
language plpgsql stable security definer set search_path='' as $fn$
begin
 perform app.announcement_actor(array['gym_owner','gym_manager','front_desk'],true);
 if (p_before_created_at is null)<>(p_before_id is null) then raise exception 'Complete cursor required' using errcode='22023'; end if;
 return query
 with page as (
  select a.*,case when a.status='draft' then 'draft' when a.status='unpublished' then 'taken_down'
   when a.expires_at is not null and a.expires_at<=statement_timestamp() then 'ended' else 'live' end as display,
   a.status='draft' or (a.status='published' and (a.expires_at is null or a.expires_at>statement_timestamp())) as restricted
  from public.announcements a where a.tenant_id=app.current_tenant_id() and a.status<>'discarded'
   and (p_before_created_at is null or (a.created_at,a.id)<(p_before_created_at,p_before_id))
  order by a.created_at desc,a.id desc limit 51
 )
 select a.id,a.kind,a.status,a.display,a.audience,a.segment_member_statuses,a.segment_membership,v.title,
  a.current_version,a.created_at,a.published_at,a.expires_at,a.closed_at,
  case when a.restricted then (select count(*)::integer from app.announcement_audience(a.id)) else null end,
  (select count(distinct r.member_id)::integer from public.announcement_receipts r
   join public.announcement_versions rv on rv.tenant_id=r.tenant_id and rv.id=r.version_id
   where rv.tenant_id=a.tenant_id and rv.announcement_id=a.id and rv.version_no=a.current_version
    and (not a.restricted or r.member_id in (select app.announcement_audience(a.id)))),
  (select count(distinct r.member_id)::integer from public.announcement_receipts r
   join public.announcement_versions rv on rv.tenant_id=r.tenant_id and rv.id=r.version_id
   where rv.tenant_id=a.tenant_id and rv.announcement_id=a.id
    and (not a.restricted or r.member_id in (select app.announcement_audience(a.id))))
 from page a join public.announcement_versions v on v.tenant_id=a.tenant_id and v.announcement_id=a.id and v.version_no=a.current_version
 order by a.created_at desc,a.id desc;
end
$fn$;
create function public.read_announcement(p_announcement_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $fn$
declare v_a public.announcements%rowtype; v_restricted boolean; v_display text; v_result jsonb;
begin
 perform app.announcement_actor(array['gym_owner','gym_manager','front_desk'],true);
 select a.* into v_a from public.announcements a where a.tenant_id=app.current_tenant_id() and a.id=p_announcement_id and a.status<>'discarded';
 if not found then raise exception 'Announcement unavailable' using errcode='42501'; end if;
 v_restricted:=v_a.status='draft' or (v_a.status='published' and (v_a.expires_at is null or v_a.expires_at>statement_timestamp()));
 v_display:=case when v_a.status='draft' then 'draft' when v_a.status='unpublished' then 'taken_down'
  when v_a.expires_at is not null and v_a.expires_at<=statement_timestamp() then 'ended' else 'live' end;
 select jsonb_build_object('announcement',jsonb_build_object(
  'id',v_a.id,'kind',v_a.kind,'status',v_a.status,'displayStatus',v_display,'audience',v_a.audience,
  'segmentMemberStatuses',v_a.segment_member_statuses,'segmentMembership',v_a.segment_membership,
  'currentVersion',v_a.current_version,'createdAt',v_a.created_at,'publishedAt',v_a.published_at,
  'expiresAt',v_a.expires_at,'closedAt',v_a.closed_at,
  'audienceCount',case when v_restricted then (select count(*)::integer from app.announcement_audience(v_a.id)) else null end,
  'readCurrent',(select count(distinct r.member_id)::integer from public.announcement_receipts r
   join public.announcement_versions rv on rv.tenant_id=r.tenant_id and rv.id=r.version_id
   where rv.tenant_id=v_a.tenant_id and rv.announcement_id=v_a.id and rv.version_no=v_a.current_version
    and (not v_restricted or r.member_id in (select app.announcement_audience(v_a.id)))),
  'readAny',(select count(distinct r.member_id)::integer from public.announcement_receipts r
   join public.announcement_versions rv on rv.tenant_id=r.tenant_id and rv.id=r.version_id
   where rv.tenant_id=v_a.tenant_id and rv.announcement_id=v_a.id
    and (not v_restricted or r.member_id in (select app.announcement_audience(v_a.id))))),
  'versions',coalesce((select jsonb_agg(jsonb_build_object('versionNo',v.version_no,'title',v.title,'body',v.body,
   'imageAssetId',v.image_asset_id,'changeNote',v.change_note,'createdAt',v.created_at,'createdByStaffId',v.created_by_staff_id,
   'readCount',(select count(distinct r.member_id)::integer from public.announcement_receipts r
    where r.tenant_id=v.tenant_id and r.version_id=v.id
     and (not v_restricted or r.member_id in (select app.announcement_audience(v_a.id))))) order by v.version_no desc)
   from public.announcement_versions v where v.tenant_id=v_a.tenant_id and v.announcement_id=v_a.id),'[]'::jsonb)) into v_result;
 return v_result;
end
$fn$;
create function public.read_member_announcements()
returns table(announcement_id uuid,kind public.announcement_kind,title text,body text,image_asset_id uuid,version_no integer,
 published_at timestamptz,edited_at timestamptz,expires_at timestamptz,change_note text,read_state text,read_at timestamptz)
language plpgsql stable security definer set search_path='' as $fn$
declare v_member uuid;
begin
 v_member:=app.announcement_member_actor();
 return query select a.id,a.kind,v.title,v.body,
  case when exists(select 1 from public.media_assets m where m.tenant_id=a.tenant_id and m.id=v.image_asset_id
   and m.kind='announcement' and m.confirmed_at is not null and m.deleted_at is null and m.attached_to_id=a.id)
   then v.image_asset_id else null end,
  v.version_no,a.published_at,case when v.version_no>1 then v.created_at else null end,a.expires_at,
  case when v.version_no>1 then v.change_note else null end,
  case when exists(select 1 from public.announcement_receipts r where r.tenant_id=a.tenant_id and r.version_id=v.id and r.member_id=v_member) then 'read'
   when receipts.last_read is not null then 'updated' else 'unread' end,receipts.last_read
 from public.announcements a
 join public.announcement_versions v on v.tenant_id=a.tenant_id and v.announcement_id=a.id and v.version_no=a.current_version
 cross join lateral (select max(r.read_at) as last_read from public.announcement_receipts r
  join public.announcement_versions rv on rv.tenant_id=r.tenant_id and rv.id=r.version_id
  where r.tenant_id=a.tenant_id and rv.announcement_id=a.id and r.member_id=v_member) receipts
 where a.tenant_id=app.current_tenant_id() and a.status='published' and (a.expires_at is null or a.expires_at>statement_timestamp())
  and exists(select 1 from app.announcement_audience(a.id,v_member))
 order by (a.kind='transactional') desc,a.published_at desc,a.id desc;
end
$fn$;
create function public.mark_announcement_read(p_announcement_id uuid,p_version_no integer) returns boolean
language plpgsql volatile security definer set search_path='' as $fn$
declare v_member uuid; v_a public.announcements%rowtype; v_version uuid;
begin
 v_member:=app.announcement_member_actor();
 -- Share the announcement lock with edits and take-down, then resolve the exact version.
 select a.* into v_a from public.announcements a where a.tenant_id=app.current_tenant_id() and a.id=p_announcement_id for update;
 if not found or v_a.status<>'published' or (v_a.expires_at is not null and v_a.expires_at<=statement_timestamp()) then return false; end if;
 if not exists(select 1 from app.announcement_audience(v_a.id,v_member)) then return false; end if;
 select v.id into v_version from public.announcement_versions v where v.tenant_id=v_a.tenant_id
  and v.announcement_id=v_a.id and v.version_no=p_version_no;
 if not found then return false; end if;
 insert into public.announcement_receipts(tenant_id,version_id,member_id,read_at)
  values(v_a.tenant_id,v_version,v_member,statement_timestamp())
  on conflict on constraint announcement_receipts_version_member_key do nothing;
 return true;
end
$fn$;

alter function app.announcement_actor(text[],boolean) owner to postgres;
revoke all on function app.announcement_actor(text[],boolean) from public,anon,authenticated,service_role;

alter function app.announcement_member_actor() owner to postgres;
revoke all on function app.announcement_member_actor() from public,anon,authenticated,service_role;

alter function app.announcement_audience(uuid,uuid) owner to postgres;
revoke all on function app.announcement_audience(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.announcement_audience(uuid,uuid) to service_role;

alter function app.announcement_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb,text) owner to postgres;
revoke all on function app.announcement_audit(uuid,uuid,public.app_role,text,uuid,jsonb,jsonb,text) from public,anon,authenticated,service_role;

alter function app.enforce_announcement() owner to postgres;
revoke all on function app.enforce_announcement() from public,anon,authenticated,service_role;

alter function app.enforce_announcement_version() owner to postgres;
revoke all on function app.enforce_announcement_version() from public,anon,authenticated,service_role;

alter function public.create_announcement_draft(public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) owner to postgres;
revoke all on function public.create_announcement_draft(public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.create_announcement_draft(public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) to authenticated;

alter function public.update_announcement_draft(uuid,public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) owner to postgres;
revoke all on function public.update_announcement_draft(uuid,public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.update_announcement_draft(uuid,public.announcement_kind,text,text,public.announcement_audience,public.member_status[],public.announcement_membership_filter,timestamptz,uuid) to authenticated;

alter function public.discard_announcement_draft(uuid) owner to postgres;
revoke all on function public.discard_announcement_draft(uuid) from public,anon,authenticated,service_role;
grant execute on function public.discard_announcement_draft(uuid) to authenticated;

alter function public.publish_announcement(uuid) owner to postgres;
revoke all on function public.publish_announcement(uuid) from public,anon,authenticated,service_role;
grant execute on function public.publish_announcement(uuid) to authenticated;

alter function public.edit_announcement(uuid,integer,text,text,uuid,timestamptz,text) owner to postgres;
revoke all on function public.edit_announcement(uuid,integer,text,text,uuid,timestamptz,text) from public,anon,authenticated,service_role;
grant execute on function public.edit_announcement(uuid,integer,text,text,uuid,timestamptz,text) to authenticated;

alter function public.unpublish_announcement(uuid) owner to postgres;
revoke all on function public.unpublish_announcement(uuid) from public,anon,authenticated,service_role;
grant execute on function public.unpublish_announcement(uuid) to authenticated;

alter function public.list_announcements(timestamptz,uuid) owner to postgres;
revoke all on function public.list_announcements(timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.list_announcements(timestamptz,uuid) to authenticated;

alter function public.read_announcement(uuid) owner to postgres;
revoke all on function public.read_announcement(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_announcement(uuid) to authenticated;

alter function public.read_member_announcements() owner to postgres;
revoke all on function public.read_member_announcements() from public,anon,authenticated,service_role;
grant execute on function public.read_member_announcements() to authenticated;

alter function public.mark_announcement_read(uuid,integer) owner to postgres;
revoke all on function public.mark_announcement_read(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.mark_announcement_read(uuid,integer) to authenticated;
