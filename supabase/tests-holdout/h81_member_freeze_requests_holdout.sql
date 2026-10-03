-- Independent holdout: frozen SLF-001..018 public contract only
-- (openspec/changes/member-self-service/proposal.md, docs/design/v2/slf-bar.md,
-- docs/data-model.md, docs/security.md). No implementation, no visible suite,
-- no other holdout file, no registry was read.
--
-- Pattern (declared per directive): the real SLF migration does not exist yet.
-- Schema `holdout_slf` carries a guarded stand-in mirror of the frozen database
-- boundary so behavioral assertions are meaningful now and, after the migration
-- lands, the same behavioral assertions dispatch to the real public.* RPCs and
-- tables. Section A pins the real migration's shape in `public` and is RED
-- until it lands; the stand-in deliberately lives outside `public` so it cannot
-- satisfy Section A. Section B dispatches on runtime presence. Everything is
-- rollback-only.
--
-- Stand-in refusal-code conventions (frozen shared classes; implementer must
-- reconcile with the real detail map): 42501 actor, 22023 shape/interval,
-- P0002 invisible target, GL068 replay/idempotency conflict, GL066 invalid or
-- stale state (terminal, elapsed, wrong revision), GL067 limit/overlap/allowance
-- insufficiency, 23514 structural invariant, 23505 uniqueness.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(139);

-- Probe helpers first: every Section-A assertion must degrade to a clean RED
-- (false) instead of aborting the file while the real migration is absent.
create schema if not exists holdout_slf;
grant usage on schema holdout_slf to authenticated, anon;
do $h81$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                 where n.nspname='holdout_slf' and t.typname='member_freeze_request_status') then
    create type holdout_slf.member_freeze_request_status as enum
      ('requested','desk_submitted','approved','rejected','cancelled','expired');
  end if;
end $h81$;
create or replace function holdout_slf.h81_rls(p_table text) returns boolean language plpgsql stable as $f$
declare v boolean;
begin
  if to_regclass(p_table) is null then return false; end if;
  execute format('select relrowsecurity from pg_class where oid = to_regclass(%L)', p_table) into v;
  return v;
end $f$;
create or replace function holdout_slf.h81_lacks_priv(p_role text, p_table text, p_priv text) returns boolean language plpgsql stable as $f$
begin
  if to_regclass(p_table) is null then return true; end if;
  return not has_table_privilege(p_role, p_table, p_priv);
end $f$;
create or replace function holdout_slf.h81_enum_labels() returns text[] language plpgsql stable as $f$
declare v text[];
begin
  if to_regtype('public.member_freeze_request_status') is not null then
    execute 'select array(select unnest(enum_range(null::public.member_freeze_request_status))::text[])' into v;
  else
    execute 'select array(select unnest(enum_range(null::holdout_slf.member_freeze_request_status))::text[])' into v;
  end if;
  return v;
end $f$;
grant execute on all functions in schema holdout_slf to authenticated, anon;

-- §A Contract shape of the real migration (RED until it lands).
select has_table('public','member_freeze_requests','frozen request table exists');
select has_table('public','member_freeze_commands','frozen append-only command table exists');
select has_type('public','member_freeze_request_status','request vocabulary is a database enum');
select is((holdout_slf.h81_enum_labels()),
  array['requested','desk_submitted','approved','rejected','cancelled','expired']::text[],
  'SLF-005/006/007/008/009/010 frozen request vocabulary order');
select columns_are('public','member_freeze_requests',
  array['id','tenant_id','member_id','membership_id','requested_by_user_id','request_key',
        'starts_on','ends_on','reason','status','revision','source_pause_id',
        'adopted_by_staff_id','adopted_at','decided_by_staff_id','decided_at',
        'decision_reason','cancelled_by_user_id','closed_at','created_at','updated_at'],
  'frozen boundary column set exactly');
select columns_are('public','member_freeze_commands',
  array['id','tenant_id','request_id','actor_user_id','command_key','action','facts','result','created_at'],
  'command ledger column set exactly');
select col_type_is('public','member_freeze_requests','status','member_freeze_request_status','status is the request enum, never text');
select col_type_is('public','member_freeze_requests','revision','bigint','revision is bigint');
select col_type_is('public','member_freeze_commands','facts','jsonb','facts are jsonb');
select col_type_is('public','member_freeze_commands','action','text','action is a checked text vocabulary');
select col_not_null('public','member_freeze_requests','tenant_id','tenant always present');
select col_not_null('public','member_freeze_commands','command_key','command key always present');
select col_is_null('public','member_freeze_requests','source_pause_id','source link nullable until adoption');
select col_is_null('public','member_freeze_requests','decision_reason','decision reason nullable until decision');
select ok((holdout_slf.h81_rls('public.member_freeze_requests')),'SLF-014 requests RLS enabled at creation');
select ok((holdout_slf.h81_rls('public.member_freeze_commands')),'SLF-014 commands RLS enabled at creation');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_requests','SELECT')),'application reads use safe RPCs, no direct member SELECT');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_requests','INSERT')),'no application INSERT on requests');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_requests','UPDATE')),'no application UPDATE on requests');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_requests','DELETE')),'no application DELETE on requests');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_requests','TRUNCATE')),'no application TRUNCATE on requests');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_commands','SELECT')),'commands expose no authenticated SELECT');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_commands','INSERT')),'commands expose no authenticated INSERT');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_commands','UPDATE')),'commands expose no authenticated UPDATE');
select ok((holdout_slf.h81_lacks_priv('authenticated','public.member_freeze_commands','DELETE')),'commands expose no authenticated DELETE');
select ok((holdout_slf.h81_lacks_priv('anon','public.member_freeze_requests','SELECT')),'anon reads nothing');
select ok((holdout_slf.h81_lacks_priv('anon','public.member_freeze_commands','INSERT')),'anon writes nothing');
select has_function('public','request_member_freeze',array['uuid','uuid','uuid','uuid','uuid'],'create signature frozen');
select has_function('public','cancel_member_freeze_request',array['uuid','uuid'],'cancel signature frozen');
select has_function('public','adopt_member_freeze_request',array['uuid','bigint','uuid'],'adopt signature frozen');
select has_function('public','approve_member_freeze_request',array['uuid','bigint','uuid'],'approve signature frozen');
select has_function('public','reject_member_freeze_request',array['uuid','bigint','text','uuid'],'reject signature frozen');
select has_function('public','expire_member_freeze_request',array['uuid','bigint','uuid'],'expire signature frozen');
select has_function('public','read_member_freeze_request',array['uuid'],'single read signature frozen');
select has_function('public','read_member_freeze_requests',array['integer','timestamptz','uuid'],'member list signature frozen');
select has_function('public','read_staff_freeze_requests',array['integer','timestamptz','uuid'],'staff list signature frozen');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and p.proconfig is not null and p.proconfig::text like '%search_path=%'),9::bigint,'SLF-014 every RPC runs an empty fixed search path');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and p.prosecurity = 'definer'),5::bigint,'member and reader commands are narrow definers');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request')
   and p.prosecurity = 'invoker'),4::bigint,'staff source commands are invokers through unchanged RLS/guards');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and has_function_privilege('authenticated',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')','EXECUTE')),9::bigint,'authenticated EXECUTE granted explicitly on all nine');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and has_function_privilege('public',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')','EXECUTE')),0::bigint,'PUBLIC EXECUTE revoked');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and has_function_privilege('anon',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')','EXECUTE')),0::bigint,'anon EXECUTE revoked');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('request_member_freeze','cancel_member_freeze_request','adopt_member_freeze_request','approve_member_freeze_request','reject_member_freeze_request','expire_member_freeze_request','read_member_freeze_request','read_member_freeze_requests','read_staff_freeze_requests')
   and has_function_privilege('service_role',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')','EXECUTE')),0::bigint,'service-role EXECUTE revoked');

-- §B0 Stand-in mirror of the frozen boundary (schema holdout_slf), guarded.
create schema if not exists holdout_slf;
grant usage on schema holdout_slf to authenticated, anon;
do $h81$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                 where n.nspname='holdout_slf' and t.typname='member_freeze_request_status') then
    create type holdout_slf.member_freeze_request_status as enum
      ('requested','desk_submitted','approved','rejected','cancelled','expired');
  end if;
end $h81$;
create table if not exists holdout_slf.member_freeze_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  member_id uuid not null,
  membership_id uuid not null,
  requested_by_user_id uuid not null references auth.users(id),
  request_key uuid not null,
  starts_on date not null,
  ends_on date not null,
  reason text not null,
  status holdout_slf.member_freeze_request_status not null default 'requested',
  revision bigint not null default 1,
  source_pause_id uuid,
  adopted_by_staff_id uuid,
  adopted_at timestamptz,
  decided_by_staff_id uuid,
  decided_at timestamptz,
  decision_reason text,
  cancelled_by_user_id uuid,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint h81_dates_ordered check (starts_on <= ends_on),
  constraint h81_reason_len check (char_length(btrim(reason)) between 1 and 2000),
  constraint h81_decision_reason_len check (decision_reason is null or char_length(btrim(decision_reason)) between 3 and 200),
  constraint h81_adopted_pair check ((source_pause_id is null) = (adopted_by_staff_id is null) and (source_pause_id is null) = (adopted_at is null)),
  constraint h81_approved_shape check (status <> 'approved' or (source_pause_id is not null and decided_by_staff_id is not null and decided_at is not null)),
  constraint h81_rejected_shape check (status <> 'rejected' or (decided_by_staff_id is not null and decided_at is not null and decision_reason is not null)),
  constraint h81_cancelled_shape check (status <> 'cancelled' or cancelled_by_user_id is not null),
  constraint h81_terminal_closed check ((status in ('approved','rejected','cancelled','expired')) = (closed_at is not null)),
  constraint h81_request_key_unique unique (tenant_id, request_key)
);
create unique index if not exists h81_source_pause_key on holdout_slf.member_freeze_requests (tenant_id, source_pause_id) where source_pause_id is not null;
create table if not exists holdout_slf.member_freeze_commands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id),
  request_id uuid not null,
  actor_user_id uuid not null references auth.users(id),
  command_key uuid not null,
  action text not null check (action in ('create','adopt','approve','reject','cancel','expire')),
  facts jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  constraint h81_command_key_unique unique (tenant_id, command_key)
);
revoke all on holdout_slf.member_freeze_requests from public, anon, authenticated;
revoke all on holdout_slf.member_freeze_commands from public, anon, authenticated;
alter table holdout_slf.member_freeze_requests enable row level security;
alter table holdout_slf.member_freeze_commands enable row level security;

create or replace function holdout_slf.h81_claims() returns jsonb language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claims', true),'')::jsonb,'{}'::jsonb)
$f$;
create or replace function holdout_slf.h81_today(p_tenant uuid) returns date language sql stable as $f$
  select (now() at time zone o.timezone)::date from public.organizations o where o.id = p_tenant
$f$;
create or replace function holdout_slf.h81_front_office(p_tenant uuid) returns uuid language plpgsql stable as $f$
declare c jsonb := holdout_slf.h81_claims(); v uuid;
begin
  if c->>'impersonation_session_id' is not null then raise exception 'preview refused' using errcode='42501'; end if;
  if coalesce(c->>'app_role','') not in ('gym_owner','gym_manager','front_desk') then raise exception 'not front office' using errcode='42501'; end if;
  if coalesce(c->>'tenant_id','') <> p_tenant::text then raise exception 'foreign tenant' using errcode='42501'; end if;
  select s.id into v from public.staff s
   where s.tenant_id = p_tenant and s.user_id = (c->>'sub')::uuid
     and s.is_active and s.role::text = c->>'app_role';
  if v is null then raise exception 'no active matching staff' using errcode='42501'; end if;
  return v;
end $f$;
create or replace function holdout_slf.h81_member() returns record language plpgsql stable as $f$
declare c jsonb := holdout_slf.h81_claims(); m public.members;
begin
  if c->>'impersonation_session_id' is not null or coalesce(c->>'app_role','') <> 'member' then
    raise exception 'actor is not a member' using errcode='42501';
  end if;
  select * into m from public.members
   where tenant_id = (c->>'tenant_id')::uuid and user_id = (c->>'sub')::uuid;
  if not found then raise exception 'unlinked subject' using errcode='P0002'; end if;
  return m;
end $f$;
create or replace function holdout_slf.h81_effective(r holdout_slf.member_freeze_requests) returns text language plpgsql stable as $f$
begin
  if r.status in ('requested','desk_submitted') then
    if r.starts_on < holdout_slf.h81_today(r.tenant_id) then return 'expired'; end if;
    if not exists (select 1 from public.memberships m where m.id = r.membership_id and m.status in ('active','frozen')) then return 'expired'; end if;
    if exists (select 1 from public.members mm where mm.id = r.member_id and (mm.erased_at is not null or mm.status in ('blocked','cancelled'))) then return 'expired'; end if;
  end if;
  return r.status::text;
end $f$;
create or replace function holdout_slf.h81_year_used(p_tenant uuid, p_member uuid, p_year int) returns int language sql stable as $f$
  select coalesce(sum((p.ends_on - p.starts_on) + 1),0)::int
    from public.membership_pauses p
    join public.memberships m on m.id = p.membership_id and m.tenant_id = p.tenant_id
   where m.member_id = p_member
     and p.approved_at is not null and p.rejected_at is null
     and extract(year from p.starts_on)::int = p_year
$f$;
create or replace function holdout_slf.h81_overlaps(p_tenant uuid, p_member uuid, p_from date, p_to date, p_self uuid) returns boolean language plpgsql stable as $f$
begin
  if exists (select 1 from holdout_slf.member_freeze_requests r2
              where r2.tenant_id = p_tenant and r2.member_id = p_member
                and (p_self is null or r2.id <> p_self)
                and holdout_slf.h81_effective(r2) in ('requested','desk_submitted')
                and r2.starts_on <= p_to and p_from <= r2.ends_on) then
    return true;
  end if;
  if exists (select 1 from public.membership_pauses p
              join public.memberships m on m.id = p.membership_id and m.tenant_id = p_tenant
              where m.member_id = p_member and p.rejected_at is null
                and (p_self is null or not exists (select 1 from holdout_slf.member_freeze_requests lr
                      where lr.source_pause_id = p.id and lr.id = p_self))
                and not exists (select 1 from holdout_slf.member_freeze_requests lr
                      where lr.source_pause_id = p.id and lr.tenant_id = p_tenant
                        and lr.status in ('cancelled','rejected','expired'))
                and p.starts_on <= p_to and p_from <= p.ends_on) then
    return true;
  end if;
  return false;
end $f$;

-- Additive source invariant (SLF-014): a decision on a source pause linked to a
-- closed/ineffective request is refused; approval requires the linked request to
-- still be awaiting approval. Attached to the real pause table, guarded by name.
create or replace function holdout_slf.h81_source_invariant() returns trigger language plpgsql as $f$
declare r record;
begin
  if tg_op = 'UPDATE' then
    if new.approved_at is not null and old.approved_at is null then
      select * into r from holdout_slf.member_freeze_requests
       where tenant_id = new.tenant_id and source_pause_id = new.id;
      if found and r.status is distinct from 'desk_submitted' then
        raise exception 'linked request not awaiting approval' using errcode='GL066';
      end if;
    end if;
    if new.rejected_at is not null and old.rejected_at is null then
      select * into r from holdout_slf.member_freeze_requests
       where tenant_id = new.tenant_id and source_pause_id = new.id;
      if found and r.status in ('cancelled','expired','approved') then
        raise exception 'linked closed request source decision' using errcode='GL066';
      end if;
    end if;
  end if;
  return coalesce(new, old);
end $f$;
do $h81$ begin
  if not exists (select 1 from pg_trigger where tgname = 'h81_source_invariant_trg'
                 and tgrelid = 'public.membership_pauses'::regclass) then
    create trigger h81_source_invariant_trg before update on public.membership_pauses
      for each row execute function holdout_slf.h81_source_invariant();
  end if;
end $h81$;

-- Structural guard for the stand-in requests table: tenant agreement, frozen
-- fields, terminal closure, one-step revision.
create or replace function holdout_slf.h81_requests_guard() returns trigger language plpgsql as $f$
begin
  if tg_op = 'INSERT' then
    if new.created_at is distinct from now() and abs(extract(epoch from (new.created_at - now()))) > 5 then
      raise exception 'user-supplied audit timestamp refused' using errcode='22023';
    end if;
    if not exists (select 1 from public.members m where m.id = new.member_id and m.tenant_id = new.tenant_id)
       or not exists (select 1 from public.memberships ms
                       where ms.id = new.membership_id and ms.tenant_id = new.tenant_id and ms.member_id = new.member_id) then
      raise exception 'tenant composite disagreement' using errcode='23514';
    end if;
    if new.closed_at is not null or new.status <> 'requested' or new.revision <> 1
       or new.source_pause_id is not null or new.adopted_by_staff_id is not null
       or new.decided_by_staff_id is not null or new.cancelled_by_user_id is not null then
      raise exception 'born advanced or closed' using errcode='23514';
    end if;
    return new;
  end if;
  if row(new.id,new.tenant_id,new.member_id,new.membership_id,new.requested_by_user_id,new.request_key,new.starts_on,new.ends_on,new.reason,new.created_at)
     is distinct from
     row(old.id,old.tenant_id,old.member_id,old.membership_id,old.requested_by_user_id,old.request_key,old.starts_on,old.ends_on,old.reason,old.created_at) then
    raise exception 'frozen fields immutable' using errcode='23514';
  end if;
  if old.status in ('approved','rejected','cancelled','expired') then
    if row(new.status,new.source_pause_id,new.adopted_by_staff_id,new.adopted_at,new.decided_by_staff_id,new.decided_at,new.decision_reason,new.cancelled_by_user_id,new.closed_at)
       is distinct from
       row(old.status,old.source_pause_id,old.adopted_by_staff_id,old.adopted_at,old.decided_by_staff_id,old.decided_at,old.decision_reason,old.cancelled_by_user_id,old.closed_at) then
      raise exception 'terminal row frozen' using errcode='23514';
    end if;
  end if;
  if row(new.status,coalesce(new.source_pause_id::text,''),coalesce(new.adopted_by_staff_id::text,''),coalesce(new.adopted_at::text,''),coalesce(new.decided_by_staff_id::text,''),coalesce(new.decided_at::text,''),coalesce(new.decision_reason,''),coalesce(new.cancelled_by_user_id::text,''),coalesce(new.closed_at::text,''))
     is distinct from
     row(old.status,coalesce(old.source_pause_id::text,''),coalesce(old.adopted_by_staff_id::text,''),coalesce(old.adopted_at::text,''),coalesce(old.decided_by_staff_id::text,''),coalesce(old.decided_at::text,''),coalesce(old.decision_reason,''),coalesce(old.cancelled_by_user_id::text,''),coalesce(old.closed_at::text,'')) then
    new.revision := old.revision + 1;
  elsif new.revision < old.revision then
    raise exception 'revision regression' using errcode='23514';
  end if;
  new.updated_at := now();
  return new;
end $f$;
drop trigger if exists h81_requests_guard_trg on holdout_slf.member_freeze_requests;
create trigger h81_requests_guard_trg before insert or update on holdout_slf.member_freeze_requests
  for each row execute function holdout_slf.h81_requests_guard();
create or replace function holdout_slf.h81_commands_guard() returns trigger language plpgsql as $f$
begin
  raise exception 'commands are append-only';
end $f$;
drop trigger if exists h81_commands_guard_trg on holdout_slf.member_freeze_commands;
create trigger h81_commands_guard_trg before update or delete on holdout_slf.member_freeze_commands
  for each row execute function holdout_slf.h81_commands_guard();

-- Definer metadata helpers (request-table writes behind invoker wrappers).
create or replace function holdout_slf.h81_meta_adopt(p_request uuid, p_pause uuid, p_staff uuid) returns void
language plpgsql security definer as $f$
begin
  update holdout_slf.member_freeze_requests
     set status='desk_submitted', source_pause_id=p_pause, adopted_by_staff_id=p_staff, adopted_at=now()
   where id = p_request;
end $f$;
create or replace function holdout_slf.h81_meta_decide(p_request uuid, p_status text, p_staff uuid, p_reason text) returns void
language plpgsql security definer as $f$
begin
  update holdout_slf.member_freeze_requests
     set status=p_status::holdout_slf.member_freeze_request_status, decided_by_staff_id=p_staff, decided_at=now(),
         decision_reason=p_reason, closed_at=now()
   where id = p_request;
end $f$;
create or replace function holdout_slf.h81_meta_cancel(p_request uuid, p_user uuid) returns void
language plpgsql security definer as $f$
begin
  update holdout_slf.member_freeze_requests
     set status='cancelled', cancelled_by_user_id=p_user, closed_at=now()
   where id = p_request;
end $f$;
create or replace function holdout_slf.h81_meta_expire(p_request uuid) returns void
language plpgsql security definer as $f$
begin
  update holdout_slf.member_freeze_requests
     set status='expired', closed_at=now()
   where id = p_request;
end $f$;
create or replace function holdout_slf.h81_log(p_tenant uuid, p_request uuid, p_actor uuid, p_key uuid, p_action text, p_facts jsonb, p_result jsonb) returns void
language sql security definer as $f$
  insert into holdout_slf.member_freeze_commands(tenant_id,request_id,actor_user_id,command_key,action,facts,result)
  values (p_tenant,p_request,p_actor,p_key,p_action,p_facts,p_result)
$f$;

-- Stand-in RPC bodies, faithful to the frozen contract.
create or replace function holdout_slf.standin_request_freeze(p_membership_id uuid,p_starts_on date,p_ends_on date,p_reason text,p_request_key uuid)
returns jsonb language plpgsql volatile security definer as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; m public.members; ms public.memberships;
 v_id uuid; v_rev bigint; v_st text; v_prev holdout_slf.member_freeze_requests;
begin
  if c->>'impersonation_session_id' is not null or coalesce(c->>'app_role','') <> 'member' then
    raise exception 'actor refused' using errcode='42501'; end if;
  v_tenant := (c->>'tenant_id')::uuid;
  select * into m from public.members where tenant_id = v_tenant and user_id = (c->>'sub')::uuid;
  if not found or m.erased_at is not null or m.status in ('blocked','cancelled') then
    raise exception 'unavailable member' using errcode='P0002'; end if;
  select * into v_prev from holdout_slf.member_freeze_requests where tenant_id = v_tenant and request_key = p_request_key;
  if found then
    if v_prev.requested_by_user_id = (c->>'sub')::uuid and v_prev.membership_id = p_membership_id
       and v_prev.starts_on = p_starts_on and v_prev.ends_on = p_ends_on and v_prev.reason = btrim(coalesce(p_reason,'')) then
      return jsonb_build_object('requestId',v_prev.id,'revision',v_prev.revision::text,
        'status',holdout_slf.h81_effective(v_prev),'replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into ms from public.memberships where id = p_membership_id and tenant_id = v_tenant;
  if not found or ms.member_id <> m.id then raise exception 'unavailable membership' using errcode='P0002'; end if;
  if ms.status not in ('active','frozen') or ms.starts_on is null or ms.ends_on is null then
    raise exception 'membership not live' using errcode='GL066'; end if;
  if p_starts_on is null or p_ends_on is null or p_starts_on > p_ends_on
     or btrim(coalesce(p_reason,'')) = '' or char_length(btrim(p_reason)) > 2000 then
    raise exception 'invalid request shape' using errcode='22023'; end if;
  if p_starts_on < holdout_slf.h81_today(v_tenant) or p_starts_on < ms.starts_on or p_ends_on > ms.ends_on then
    raise exception 'interval outside permitted span' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('slf:'||v_tenant::text||':'||m.id::text,0));
  if exists (select 1 from holdout_slf.member_freeze_requests r
              where r.tenant_id = v_tenant and r.member_id = m.id
                and holdout_slf.h81_effective(r) in ('requested','desk_submitted')) then
    raise exception 'one open request per member' using errcode='GL067';
  end if;
  if holdout_slf.h81_overlaps(v_tenant,m.id,p_starts_on,p_ends_on,null) then
    raise exception 'inclusive overlap' using errcode='GL067';
  end if;
  insert into holdout_slf.member_freeze_requests(tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason)
  values (v_tenant,m.id,p_membership_id,(c->>'sub')::uuid,p_request_key,p_starts_on,p_ends_on,btrim(p_reason))
  returning id, revision, status::text into v_id, v_rev, v_st;
  perform holdout_slf.h81_log(v_tenant,v_id,(c->>'sub')::uuid,p_request_key,'create',
    jsonb_build_object('membershipId',p_membership_id,'startsOn',p_starts_on,'endsOn',p_ends_on,'reason',btrim(p_reason)),
    jsonb_build_object('requestId',v_id,'revision',v_rev::text,'status',v_st,'replayed',false));
  return jsonb_build_object('requestId',v_id,'revision',v_rev::text,'status',v_st,'replayed',false);
end $f$;
create or replace function holdout_slf.standin_cancel_member_freeze_request(p_request_id uuid,p_command_key uuid)
returns jsonb language plpgsql volatile security definer as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; m public.members; r holdout_slf.member_freeze_requests; v_prev holdout_slf.member_freeze_commands;
begin
  if c->>'impersonation_session_id' is not null or coalesce(c->>'app_role','') <> 'member' then
    raise exception 'actor refused' using errcode='42501'; end if;
  v_tenant := (c->>'tenant_id')::uuid;
  select * into m from public.members where tenant_id = v_tenant and user_id = (c->>'sub')::uuid;
  if not found then raise exception 'unlinked subject' using errcode='P0002'; end if;
  select * into v_prev from holdout_slf.member_freeze_commands
   where tenant_id = v_tenant and command_key = p_command_key;
  if found then
    if v_prev.request_id = p_request_id and v_prev.actor_user_id = (c->>'sub')::uuid and v_prev.action = 'cancel' then
      select * into r from holdout_slf.member_freeze_requests where id = p_request_id;
      return jsonb_build_object('requestId',p_request_id,'revision',r.revision::text,
        'status',holdout_slf.h81_effective(r),'replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
  if not found or r.member_id <> m.id or r.requested_by_user_id <> (c->>'sub')::uuid then
    raise exception 'request unavailable' using errcode='P0002'; end if;
  if r.status not in ('requested','desk_submitted') then raise exception 'terminal state' using errcode='GL066'; end if;
  perform pg_advisory_xact_lock(hashtextextended('slf:'||v_tenant::text||':'||m.id::text,0));
  perform holdout_slf.h81_meta_cancel(p_request_id,(c->>'sub')::uuid);
  perform holdout_slf.h81_log(v_tenant,p_request_id,(c->>'sub')::uuid,p_command_key,'cancel',
    jsonb_build_object('requestId',p_request_id),
    jsonb_build_object('requestId',p_request_id,'status','cancelled','replayed',false));
  return jsonb_build_object('requestId',p_request_id,'revision',
    (select revision::text from holdout_slf.member_freeze_requests where id = p_request_id),
    'status','cancelled','replayed',false);
end $f$;
create or replace function holdout_slf.standin_adopt_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)
returns jsonb language plpgsql volatile security invoker as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; v_staff uuid; r holdout_slf.member_freeze_requests;
 v_pause uuid; v_prev holdout_slf.member_freeze_commands; v_org public.organizations;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  v_staff := holdout_slf.h81_front_office(v_tenant);
  select * into v_prev from holdout_slf.member_freeze_commands where tenant_id = v_tenant and command_key = p_command_key;
  if found then
    if v_prev.request_id = p_request_id and v_prev.actor_user_id = (c->>'sub')::uuid
       and v_prev.action = 'adopt' and (v_prev.facts->>'expectedRevision')::bigint = p_expected_revision then
      return v_prev.result || jsonb_build_object('replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
  if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
  if r.revision <> p_expected_revision then raise exception 'stale revision' using errcode='GL066'; end if;
  if holdout_slf.h81_effective(r) <> 'requested' then raise exception 'not adoptable now' using errcode='GL066'; end if;
  if not exists (select 1 from public.memberships ms where ms.id = r.membership_id and ms.status in ('active','frozen')) then
    raise exception 'membership not live' using errcode='GL066'; end if;
  select * into v_org from public.organizations where id = v_tenant;
  perform pg_advisory_xact_lock(hashtextextended('slf:'||v_tenant::text||':'||r.member_id::text,0));
  if holdout_slf.h81_overlaps(v_tenant,r.member_id,r.starts_on,r.ends_on,r.id) then
    raise exception 'inclusive overlap at adoption' using errcode='GL067';
  end if;
  insert into public.membership_pauses(tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id)
  values (v_tenant,r.membership_id,r.starts_on,r.ends_on,r.reason,v_staff)
  returning id into v_pause;
  perform holdout_slf.h81_meta_adopt(p_request_id,v_pause,v_staff);
  perform holdout_slf.h81_log(v_tenant,p_request_id,(c->>'sub')::uuid,p_command_key,'adopt',
    jsonb_build_object('requestId',p_request_id,'expectedRevision',p_expected_revision::text),
    jsonb_build_object('requestId',p_request_id,'revision',(select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
      'status','desk_submitted','sourcePauseId',v_pause,'replayed',false));
  return jsonb_build_object('requestId',p_request_id,'revision',
    (select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
    'status','desk_submitted','sourcePauseId',v_pause,'replayed',false);
end $f$;
create or replace function holdout_slf.standin_approve_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)
returns jsonb language plpgsql volatile security invoker as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; v_staff uuid; r holdout_slf.member_freeze_requests;
 p public.membership_pauses; v_prev holdout_slf.member_freeze_commands; v_max int; v_used int;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  v_staff := holdout_slf.h81_front_office(v_tenant);
  -- configured-role equality is enforced by the unchanged pause decision guard
  -- in production; the stand-in mirrors it so behavioral pins stay meaningful.
  if not exists (select 1 from public.organization_settings os
                  where os.tenant_id = v_tenant and os.pause_approver_role::text = c->>'app_role') then
    raise exception 'configured approver role mismatch' using errcode='GL066';
  end if;
  select * into v_prev from holdout_slf.member_freeze_commands where tenant_id = v_tenant and command_key = p_command_key;
  if found then
    if v_prev.request_id = p_request_id and v_prev.actor_user_id = (c->>'sub')::uuid
       and v_prev.action = 'approve' and (v_prev.facts->>'expectedRevision')::bigint = p_expected_revision then
      return v_prev.result || jsonb_build_object('replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
  if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
  if r.status <> 'desk_submitted' or holdout_slf.h81_effective(r) <> 'desk_submitted' then
    raise exception 'not approvable now' using errcode='GL066'; end if;
  if r.revision <> p_expected_revision then raise exception 'stale revision' using errcode='GL066'; end if;
  if r.adopted_by_staff_id = v_staff then raise exception 'adopter cannot approve own' using errcode='GL066'; end if;
  select * into p from public.membership_pauses where id = r.source_pause_id and tenant_id = v_tenant;
  if not found or p.approved_at is not null or p.rejected_at is not null then
    raise exception 'source pause not undecided' using errcode='GL066'; end if;
  if not exists (select 1 from public.memberships ms where ms.id = r.membership_id and ms.status in ('active','frozen')) then
    raise exception 'membership not live' using errcode='GL066'; end if;
  select coalesce(max_freeze_days_per_year,0)::int into v_max from public.organization_settings where tenant_id = v_tenant;
  v_used := holdout_slf.h81_year_used(v_tenant,r.member_id,extract(year from r.starts_on)::int);
  perform pg_advisory_xact_lock(hashtextextended('slf:'||v_tenant::text||':'||r.member_id::text,0));
  if v_used + ((r.ends_on - r.starts_on) + 1) > v_max then
    raise exception 'annual freeze allowance exceeded' using errcode='GL067';
  end if;
  update public.membership_pauses set approved_by_staff_id = v_staff, approved_at = now() where id = r.source_pause_id;
  perform holdout_slf.h81_meta_decide(p_request_id,'approved',v_staff,null);
  perform holdout_slf.h81_log(v_tenant,p_request_id,(c->>'sub')::uuid,p_command_key,'approve',
    jsonb_build_object('requestId',p_request_id,'expectedRevision',p_expected_revision::text),
    jsonb_build_object('requestId',p_request_id,'revision',(select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
      'status','approved','sourcePauseId',r.source_pause_id,'replayed',false));
  return jsonb_build_object('requestId',p_request_id,'revision',
    (select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
    'status','approved','sourcePauseId',r.source_pause_id,'replayed',false);
end $f$;
create or replace function holdout_slf.standin_reject_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_reason text,p_command_key uuid)
returns jsonb language plpgsql volatile security invoker as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; v_staff uuid; r holdout_slf.member_freeze_requests;
 p public.membership_pauses; v_prev holdout_slf.member_freeze_commands;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  v_staff := holdout_slf.h81_front_office(v_tenant);
  select * into v_prev from holdout_slf.member_freeze_commands where tenant_id = v_tenant and command_key = p_command_key;
  if found then
    if v_prev.request_id = p_request_id and v_prev.actor_user_id = (c->>'sub')::uuid
       and v_prev.action = 'reject' and (v_prev.facts->>'expectedRevision')::bigint = p_expected_revision
       and v_prev.facts->>'reason' = btrim(coalesce(p_reason,'')) then
      return v_prev.result || jsonb_build_object('replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
  if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
  if r.status not in ('requested','desk_submitted') then raise exception 'terminal state' using errcode='GL066'; end if;
  if r.revision <> p_expected_revision then raise exception 'stale revision' using errcode='GL066'; end if;
  if btrim(coalesce(p_reason,'')) is null or char_length(btrim(p_reason)) < 3 or char_length(btrim(p_reason)) > 200 then
    raise exception 'invalid decision reason' using errcode='22023'; end if;
  if r.source_pause_id is not null then
    select * into p from public.membership_pauses where id = r.source_pause_id and tenant_id = v_tenant;
    if found and p.approved_at is not null then raise exception 'approved pause is never rewritten' using errcode='GL066'; end if;
    if found and p.rejected_at is null then
      update public.membership_pauses set rejected_at = now() where id = r.source_pause_id;
    end if;
  end if;
  perform holdout_slf.h81_meta_decide(p_request_id,'rejected',v_staff,btrim(p_reason));
  perform holdout_slf.h81_log(v_tenant,p_request_id,(c->>'sub')::uuid,p_command_key,'reject',
    jsonb_build_object('requestId',p_request_id,'expectedRevision',p_expected_revision::text,'reason',btrim(p_reason)),
    jsonb_build_object('requestId',p_request_id,'status','rejected','replayed',false));
  return jsonb_build_object('requestId',p_request_id,'revision',
    (select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
    'status','rejected','replayed',false);
end $f$;
create or replace function holdout_slf.standin_expire_member_freeze_request(p_request_id uuid,p_expected_revision bigint,p_command_key uuid)
returns jsonb language plpgsql volatile security invoker as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; v_staff uuid; r holdout_slf.member_freeze_requests;
 v_prev holdout_slf.member_freeze_commands;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  v_staff := holdout_slf.h81_front_office(v_tenant);
  select * into v_prev from holdout_slf.member_freeze_commands where tenant_id = v_tenant and command_key = p_command_key;
  if found then
    if v_prev.request_id = p_request_id and v_prev.actor_user_id = (c->>'sub')::uuid
       and v_prev.action = 'expire' and (v_prev.facts->>'expectedRevision')::bigint = p_expected_revision then
      return v_prev.result || jsonb_build_object('replayed',true);
    end if;
    raise exception 'idempotency conflict' using errcode='GL068';
  end if;
  select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
  if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
  if r.status not in ('requested','desk_submitted') then raise exception 'terminal state' using errcode='GL066'; end if;
  if holdout_slf.h81_effective(r) <> 'expired' then raise exception 'only an ineffective request expires' using errcode='GL066'; end if;
  if r.revision <> p_expected_revision then raise exception 'stale revision' using errcode='GL066'; end if;
  perform holdout_slf.h81_meta_expire(p_request_id);
  perform holdout_slf.h81_log(v_tenant,p_request_id,(c->>'sub')::uuid,p_command_key,'expire',
    jsonb_build_object('requestId',p_request_id,'expectedRevision',p_expected_revision::text),
    jsonb_build_object('requestId',p_request_id,'status','expired','replayed',false));
  return jsonb_build_object('requestId',p_request_id,'revision',
    (select revision::text from holdout_slf.member_freeze_requests where id=p_request_id),
    'status','expired','replayed',false);
end $f$;
create or replace function holdout_slf.standin_read_member_freeze_request(p_request_id uuid)
returns jsonb language plpgsql stable security definer as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; m record; r holdout_slf.member_freeze_requests; v_staff uuid;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  if coalesce(c->>'app_role','') = 'member' then
    m := holdout_slf.h81_member();
    select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant and member_id = m.id;
    if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
    return jsonb_build_object('requestId',r.id,'membershipId',r.membership_id,'startsOn',r.starts_on,'endsOn',r.ends_on,
      'reason',r.reason,'status',r.status::text,'effectiveStatus',holdout_slf.h81_effective(r),
      'revision',r.revision::text,'createdAt',r.created_at,'sourcePauseId',r.source_pause_id);
  elsif coalesce(c->>'app_role','') in ('gym_owner','gym_manager','front_desk') then
    v_staff := holdout_slf.h81_front_office(v_tenant);
    select * into r from holdout_slf.member_freeze_requests where id = p_request_id and tenant_id = v_tenant;
    if not found then raise exception 'request unavailable' using errcode='P0002'; end if;
    return jsonb_build_object('requestId',r.id,'membershipId',r.membership_id,'startsOn',r.starts_on,'endsOn',r.ends_on,
      'reason',r.reason,'status',r.status::text,'effectiveStatus',holdout_slf.h81_effective(r),
      'revision',r.revision::text,'createdAt',r.created_at,'sourcePauseId',r.source_pause_id,
      'adoptedByStaffId',r.adopted_by_staff_id,'decidedByStaffId',r.decided_by_staff_id);
  end if;
  raise exception 'actor refused' using errcode='42501';
end $f$;
create or replace function holdout_slf.standin_read_member_freeze_requests(p_limit integer,p_after_created_at timestamptz,p_after_id uuid)
returns jsonb language plpgsql stable security definer as $f$
declare c jsonb := holdout_slf.h81_claims(); m record; v_limit int;
begin
  m := holdout_slf.h81_member();
  v_limit := least(greatest(coalesce(p_limit,50),1),200);
  return coalesce((select jsonb_agg(jsonb_build_object('requestId',r.id,'startsOn',r.starts_on,'endsOn',r.ends_on,
      'status',r.status::text,'effectiveStatus',holdout_slf.h81_effective(r),'revision',r.revision::text)
      order by r.created_at desc, r.id desc)
    from (select * from holdout_slf.member_freeze_requests
           where tenant_id = (c->>'tenant_id')::uuid and member_id = m.id
             and (p_after_created_at is null or (created_at, id) < (p_after_created_at, coalesce(p_after_id,'00000000-0000-0000-0000-000000000000'::uuid)))
           order by created_at desc, id desc limit v_limit) r),'[]'::jsonb);
end $f$;
create or replace function holdout_slf.standin_read_staff_freeze_requests(p_limit integer,p_after_created_at timestamptz,p_after_id uuid)
returns jsonb language plpgsql stable security definer as $f$
declare c jsonb := holdout_slf.h81_claims(); v_tenant uuid; v_limit int;
begin
  v_tenant := (c->>'tenant_id')::uuid;
  perform holdout_slf.h81_front_office(v_tenant);
  v_limit := least(greatest(coalesce(p_limit,50),1),200);
  return coalesce((select jsonb_agg(jsonb_build_object('requestId',r.id,'startsOn',r.starts_on,'endsOn',r.ends_on,
      'status',r.status::text,'effectiveStatus',holdout_slf.h81_effective(r),'revision',r.revision::text,
      'adoptedByStaffId',r.adopted_by_staff_id)
      order by r.created_at desc, r.id desc)
    from (select * from holdout_slf.member_freeze_requests
           where tenant_id = v_tenant
             and (p_after_created_at is null or (created_at, id) < (p_after_created_at, coalesce(p_after_id,'00000000-0000-0000-0000-000000000000'::uuid)))
           order by created_at desc, id desc limit v_limit) r),'[]'::jsonb);
end $f$;

-- §B1 Runtime dispatch: real migration when present, stand-in otherwise.
do $h81$ begin
  if to_regclass('public.member_freeze_requests') is null then
    perform set_config('h81.schema','holdout_slf',true);
  else
    perform set_config('h81.schema','public',true);
  end if;
end $h81$;
create or replace function holdout_slf.request_freeze(a uuid,b date,c date,d text,e uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.request_member_freeze(uuid,uuid,uuid,uuid,uuid)') is not null then
    return public.request_member_freeze(a,b,c,d,e);
  end if;
  return holdout_slf.standin_request_freeze(a,b,c,d,e);
end $f$;
create or replace function holdout_slf.cancel_request(a uuid,b uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.cancel_member_freeze_request(uuid,uuid)') is not null then
    return public.cancel_member_freeze_request(a,b);
  end if;
  return holdout_slf.standin_cancel_member_freeze_request(a,b);
end $f$;
create or replace function holdout_slf.adopt_request(a uuid,b bigint,c uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.adopt_member_freeze_request(uuid,bigint,uuid)') is not null then
    return public.adopt_member_freeze_request(a,b,c);
  end if;
  return holdout_slf.standin_adopt_member_freeze_request(a,b,c);
end $f$;
create or replace function holdout_slf.approve_request(a uuid,b bigint,c uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.approve_member_freeze_request(uuid,bigint,uuid)') is not null then
    return public.approve_member_freeze_request(a,b,c);
  end if;
  return holdout_slf.standin_approve_member_freeze_request(a,b,c);
end $f$;
create or replace function holdout_slf.reject_request(a uuid,b bigint,c text,d uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.reject_member_freeze_request(uuid,bigint,text,uuid)') is not null then
    return public.reject_member_freeze_request(a,b,c,d);
  end if;
  return holdout_slf.standin_reject_member_freeze_request(a,b,c,d);
end $f$;
create or replace function holdout_slf.expire_request(a uuid,b bigint,c uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.expire_member_freeze_request(uuid,bigint,uuid)') is not null then
    return public.expire_member_freeze_request(a,b,c);
  end if;
  return holdout_slf.standin_expire_member_freeze_request(a,b,c);
end $f$;
create or replace function holdout_slf.read_request(a uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.read_member_freeze_request(uuid)') is not null then
    return public.read_member_freeze_request(a);
  end if;
  return holdout_slf.standin_read_member_freeze_request(a);
end $f$;
create or replace function holdout_slf.read_member_list(a integer,b timestamptz,c uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.read_member_freeze_requests(integer,timestamptz,uuid)') is not null then
    return public.read_member_freeze_requests(a,b,c);
  end if;
  return holdout_slf.standin_read_member_freeze_requests(a,b,c);
end $f$;
create or replace function holdout_slf.read_staff_list(a integer,b timestamptz,c uuid) returns jsonb language plpgsql as $f$
begin
  if to_regprocedure('public.read_staff_freeze_requests(integer,timestamptz,uuid)') is not null then
    return public.read_staff_freeze_requests(a,b,c);
  end if;
  return holdout_slf.standin_read_staff_freeze_requests(a,b,c);
end $f$;
grant execute on all functions in schema holdout_slf to authenticated, anon;

-- Direct-write probes against whichever schema the runtime resolved to.
create or replace function holdout_slf.h81_dup_request_key() returns void language plpgsql as $f$
begin
  execute format('insert into %I.member_freeze_requests(tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) '
    || 'values ($1,$2,$3,$4,$5,$6,$7,$8)', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000001'::uuid,
          '81900000-0000-4000-8000-000000000101'::uuid,
          '81900000-0000-4000-8000-000000000201'::uuid,
          '81900000-0000-4000-8000-000000000301'::uuid,
          '81900000-0000-4000-8000-000000000701'::uuid,
          current_date, current_date + 3, 'duplicate key probe';
end $f$;
create or replace function holdout_slf.h81_dup_source_pause() returns void language plpgsql as $f$
declare v_pause uuid; v_adopter uuid;
begin
  execute format('select source_pause_id, adopted_by_staff_id from %I.member_freeze_requests where request_key = $1', current_setting('h81.schema'))
    into v_pause, v_adopter
    using '81900000-0000-4000-8000-000000000701'::uuid;
  execute format('insert into %I.member_freeze_requests(tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,source_pause_id,adopted_by_staff_id,adopted_at) '
    || 'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now())', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000001'::uuid,
          '81900000-0000-4000-8000-000000000101'::uuid,
          '81900000-0000-4000-8000-000000000201'::uuid,
          '81900000-0000-4000-8000-000000000301'::uuid,
          '81900000-0000-4000-8000-000000000902'::uuid,
          current_date, current_date + 3, 'dup pause probe',
          v_pause, v_adopter;
end $f$;
create or replace function holdout_slf.h81_dup_command_key() returns void language plpgsql as $f$
begin
  execute format('insert into %I.member_freeze_commands(tenant_id,request_id,actor_user_id,command_key,action,facts,result) '
    || 'values ($1,$2,$3,$4,$5,$6,$7)', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000001'::uuid,
          '81900000-0000-4000-8000-000000000801'::uuid,
          '81900000-0000-4000-8000-000000000301'::uuid,
          '81900000-0000-4000-8000-000000000701'::uuid,
          'create','{}'::jsonb,'{}'::jsonb;
end $f$;
create or replace function holdout_slf.h81_frozen_update() returns void language plpgsql as $f$
begin
  execute format('update %I.member_freeze_requests set starts_on = starts_on + 1 where request_key = $1', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000701'::uuid;
end $f$;
create or replace function holdout_slf.h81_terminal_update() returns void language plpgsql as $f$
begin
  execute format('update %I.member_freeze_requests set decision_reason = coalesce(decision_reason,'||chr(39)||'tamper'||chr(39)||') where request_key = $1', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000701'::uuid;
end $f$;
create or replace function holdout_slf.h81_commands_update() returns void language plpgsql as $f$
begin
  execute format('update %I.member_freeze_commands set facts = ''{"tampered":true}''::jsonb where command_key = $1', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000701'::uuid;
end $f$;
create or replace function holdout_slf.h81_commands_delete() returns void language plpgsql as $f$
begin
  execute format('delete from %I.member_freeze_commands where command_key = $1', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000701'::uuid;
end $f$;
create or replace function holdout_slf.h81_born_advanced() returns void language plpgsql as $f$
begin
  execute format('insert into %I.member_freeze_requests(tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason,status) '
    || 'values ($1,$2,$3,$4,$5,$6,$7,$8,'||chr(39)||'approved'||chr(39)||')', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000001'::uuid,
          '81900000-0000-4000-8000-000000000101'::uuid,
          '81900000-0000-4000-8000-000000000201'::uuid,
          '81900000-0000-4000-8000-000000000301'::uuid,
          '81900000-0000-4000-8000-000000000905'::uuid,
          current_date, current_date + 3, 'born advanced probe';
end $f$;
create or replace function holdout_slf.h81_cross_tenant_request() returns void language plpgsql as $f$
begin
  execute format('insert into %I.member_freeze_requests(tenant_id,member_id,membership_id,requested_by_user_id,request_key,starts_on,ends_on,reason) '
    || 'values ($1,$2,$3,$4,$5,$6,$7,$8)', current_setting('h81.schema'))
    using '81900000-0000-4000-8000-000000000002'::uuid,
          '81900000-0000-4000-8000-000000000101'::uuid,
          '81900000-0000-4000-8000-000000000201'::uuid,
          '81900000-0000-4000-8000-000000000301'::uuid,
          '81900000-0000-4000-8000-000000000906'::uuid,
          current_date, current_date + 3, 'cross tenant probe';
end $f$;

-- §B2 Fixtures. Tenant A …0001, tenant B …0002. Members U-series, staff S-series.
insert into public.organizations(id,name,gym_code,status) values
 ('81900000-0000-4000-8000-000000000001','H81 Gym A','H81AAA','active'),
 ('81900000-0000-4000-8000-000000000002','H81 Gym B','H81BBB','active');
insert into public.branches(id,tenant_id,name,is_default) values
 ('81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000001','Main',true),
 ('81900000-0000-4000-8000-000000000011','81900000-0000-4000-8000-000000000002','B Main',true);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 ('81900000-0000-4000-8000-000000000020','81900000-0000-4000-8000-000000000001','H81 Plan',30,100000);
insert into public.organization_settings(tenant_id,pause_approver_role,max_freeze_days_per_year) values
 ('81900000-0000-4000-8000-000000000001','gym_manager',30),
 ('81900000-0000-4000-8000-000000000002','gym_manager',30);
insert into auth.users(id) values
 ('81900000-0000-4000-8000-000000000301'),('81900000-0000-4000-8000-000000000302'),
 ('81900000-0000-4000-8000-000000000303'),('81900000-0000-4000-8000-000000000304'),
 ('81900000-0000-4000-8000-000000000305'),('81900000-0000-4000-8000-000000000306'),
 ('81900000-0000-4000-8000-000000000307'),('81900000-0000-4000-8000-000000000308'),
 ('81900000-0000-4000-8000-000000000309'),('81900000-0000-4000-8000-000000000310'),
 ('81900000-0000-4000-8000-000000000311'),('81900000-0000-4000-8000-000000000312'),
 ('81900000-0000-4000-8000-000000000313'),('81900000-0000-4000-8000-000000000314'),
 ('81900000-0000-4000-8000-000000000315'),('81900000-0000-4000-8000-000000000316'),
 ('81900000-0000-4000-8000-000000000317'),('81900000-0000-4000-8000-000000000318'),
 ('81900000-0000-4000-8000-000000000319'),('81900000-0000-4000-8000-000000000320'),
 ('81900000-0000-4000-8000-000000000340'),('81900000-0000-4000-8000-000000000341'),
 ('81900000-0000-4000-8000-000000000342');
insert into public.staff(id,tenant_id,user_id,role,full_name,is_active) values
 ('81900000-0000-4000-8000-000000000401','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000308','gym_owner','H81 Owner A',true),
 ('81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000309','front_desk','H81 Desk A',true),
 ('81900000-0000-4000-8000-000000000403','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000310','gym_manager','H81 Manager A',true),
 ('81900000-0000-4000-8000-000000000404','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000311','gym_manager','H81 Manager A2',true),
 ('81900000-0000-4000-8000-000000000405','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000312','trainer','H81 Trainer A',true),
 ('81900000-0000-4000-8000-000000000406','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000313','front_desk','H81 Desk A2',true),
 ('81900000-0000-4000-8000-000000000407','81900000-0000-4000-8000-000000000002','81900000-0000-4000-8000-000000000314','front_desk','H81 Desk B',true);
insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,status) values
 ('81900000-0000-4000-8000-000000000101','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000301','H81 M1','+919000000001','active'),
 ('81900000-0000-4000-8000-000000000102','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000302','H81 M3','+919000000002','active'),
 ('81900000-0000-4000-8000-000000000103','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000303','H81 M4','+919000000003','active'),
 ('81900000-0000-4000-8000-000000000104','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000305','H81 M5','+919000000004','active'),
 ('81900000-0000-4000-8000-000000000105','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000306','H81 M6','+919000000005','active'),
 ('81900000-0000-4000-8000-000000000106','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000307','H81 M7','+919000000006','active'),
 ('81900000-0000-4000-8000-000000000107','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000315','H81 M8','+919000000007','active'),
 ('81900000-0000-4000-8000-000000000108','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000316','H81 M9','+919000000008','active'),
 ('81900000-0000-4000-8000-000000000109','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000317','H81 M10','+919000000009','active'),
 ('81900000-0000-4000-8000-000000000110','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000318','H81 M11','+919000000010','active'),
 ('81900000-0000-4000-8000-000000000111','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000319','H81 M12','+919000000011','active'),
 ('81900000-0000-4000-8000-000000000112','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000320','H81 M13','+919000000012','active'),
 ('81900000-0000-4000-8000-000000000113','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000340','H81 M14','+919000000013','active'),
 ('81900000-0000-4000-8000-000000000114','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000341','H81 M15','+919000000014','active'),
 ('81900000-0000-4000-8000-000000000115','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000010','81900000-0000-4000-8000-000000000342','H81 M16','+919000000015','active');
update public.members set erased_at = now() where id = '81900000-0000-4000-8000-000000000103';
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on) values
 -- M1: current active spanning two more years, plus an older expired one
 ('81900000-0000-4000-8000-000000000201','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000101','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000202','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000101','81900000-0000-4000-8000-000000000020','expired',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '2 years',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '1 year'),
 -- M3
 ('81900000-0000-4000-8000-000000000203','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000102','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 -- M14 pending
 ('81900000-0000-4000-8000-000000000214','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000113','81900000-0000-4000-8000-000000000020','pending',null,null),
 -- M5, M6, M7(long), M8, M9a/M9b, M10a/M10b, M11, M12, M13, M15, M16
 ('81900000-0000-4000-8000-000000000205','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000104','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000206','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000105','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000207','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000106','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '3 years')::date),
 ('81900000-0000-4000-8000-000000000208','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000107','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000209','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000108','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '3 years')::date),
 ('81900000-0000-4000-8000-000000000210','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000109','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '3 years')::date),
 ('81900000-0000-4000-8000-000000000211','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000109','81900000-0000-4000-8000-000000000020','expired',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '2 years',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '1 year'),
 ('81900000-0000-4000-8000-000000000212','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000110','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000213','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000111','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000215','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000112','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000216','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000114','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 ('81900000-0000-4000-8000-000000000217','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000115','81900000-0000-4000-8000-000000000020','active',date_trunc('year',now() at time zone 'Asia/Kolkata')::date - interval '9 months',(date_trunc('year',now() at time zone 'Asia/Kolkata')::date + interval '2 years')::date),
 -- M15 second, expired membership (different-membership-id bypass probe)
 ('81900000-0000-4000-8000-000000000218','81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000114','81900000-0000-4000-8000-000000000020','expired',(date_trunc('day',now() at time zone 'Asia/Kolkata')::date),(date_trunc('day',now() at time zone 'Asia/Kolkata')::date + 20));
insert into public.membership_pauses(tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id,approved_by_staff_id,approved_at) values
 -- M3: approved pause 4 days immediately after R3's window (adjacency case)
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000203',(date_trunc('day',now() at time zone 'Asia/Kolkata')::date + 5),(date_trunc('day',now() at time zone 'Asia/Kolkata')::date + 8),'H81 fixture pause','81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000403',now()),
 -- M8: 28-day approved pause earlier this year (budget refusal)
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000208',(date_trunc('day',now() at time zone 'Asia/Kolkata')::date - 30),(date_trunc('day',now() at time zone 'Asia/Kolkata')::date - 3),'H81 budget pause','81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000403',now()),
 -- M9: 396-day approved pause starting Jan 1 of the run year, charged wholly
 -- to that start year even though it spills into the next
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000209',make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int,1,1),make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int,1,1) + 395,'H81 year boundary pause','81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000403',now()),
 -- M10: 28-day approved pause on the EXPIRED membership, start year = run year
 -- (member-scoped bucket across memberships)
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000211',make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int,1,1),make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int,1,1) + 27,'H81 cross membership pause','81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000403',now()),
 -- M11: 30-day REJECTED pause (rejection consumes nothing)
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000212',(date_trunc('day',now() at time zone 'Asia/Kolkata')::date - 40),(date_trunc('day',now() at time zone 'Asia/Kolkata')::date - 11),'H81 rejected pause','81900000-0000-4000-8000-000000000402',null,null);
update public.membership_pauses set rejected_at = now()
 where tenant_id = '81900000-0000-4000-8000-000000000001'
   and membership_id = '81900000-0000-4000-8000-000000000212';

-- §B3 Behavioral dispatch helpers (fixture claims).
create or replace function holdout_slf.h81_member_claims(p_user uuid, p_tenant uuid, p_member uuid) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_user::text,'role','authenticated','app_role','member',
      'tenant_id',p_tenant::text,'member_id',p_member::text)::text, true);
end $f$;
create or replace function holdout_slf.h81_staff_claims(p_user uuid, p_tenant uuid, p_role text, p_staff uuid) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_user::text,'role','authenticated','app_role',p_role,
      'tenant_id',p_tenant::text,'staff_id',p_staff::text)::text, true);
end $f$;
create or replace function holdout_slf.h81_platform_claims(p_user uuid) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_user::text,'role','authenticated','app_role','super_admin')::text, true);
end $f$;
create or replace function holdout_slf.h81_preview_claims(p_user uuid) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_user::text,'role','authenticated','app_role','super_admin',
      'impersonation_session_id','81900000-0000-4000-8000-000000000999')::text, true);
end $f$;
grant execute on all functions in schema holdout_slf to authenticated, anon;

-- shorthand uuids used below
-- org A  …0001  org B …0002
-- members M1 …101 U1 …301, M3 …102 U3 …302, M4 …103 U4 …303(erased),
-- M5 …104 U5 …305, M6 …105 U6 …306, M7 …106 U7 …307, M8 …107 U8m …315,
-- M9 …108 U9m …316, M10 …109 U10m …317, M11 …110 U11m …318, M12 …111 U12m …319,
-- M13 …112 U13m …320, M14 …113 U14m …340, M15 …114 U15m …341, M16 …115 U16m …342
-- staff: owner …401 U …308, desk …402 U …309, mgr …403 U …310, mgr2 …404 U …311,
-- trainer …405 U …312, desk2 …406 U …313, deskB …407 U …314

-- §B4 Creation (SLF-003/004/005). d0 = gym-local today of org A.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select is((holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,
        (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date + 4, ' family trip ',
        '81900000-0000-4000-8000-000000000701'::uuid)->>'status'),
 'requested','SLF-004 eligible member creates one requested row with trimmed reason');
select is((holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,
        (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date + 4, 'family trip',
        '81900000-0000-4000-8000-000000000701'::uuid)->>'replayed'),
 'true','SLF-013 identical normalized facts replay read-only');
select is((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'revision'),'1','creation starts at revision 1');
select is((select count(*) from jsonb_array_elements(holdout_slf.read_member_list(200::integer,null::timestamptz,null::uuid)) e
            where e->>'requestId' = holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid)),1::bigint,'replay created no second row');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date + 1,(now() at time zone 'Asia/Kolkata')::date + 4,'family trip','81900000-0000-4000-8000-000000000701'::uuid)$q$,'GL068'::char(5),null,'SLF-013 changed facts under the create key conflict');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000302','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000102')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'family trip','81900000-0000-4000-8000-000000000701'::uuid)$q$,'GL068'::char(5),null,'SLF-013 changed actor under the create key conflicts without leaking facts');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date - 1,(now() at time zone 'Asia/Kolkata')::date + 4,'backdated','81900000-0000-4000-8000-000000000731'::uuid)$q$,'22023'::char(5),null,'SLF-004 interval may not start before gym-local today');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'   ','81900000-0000-4000-8000-000000000732'::uuid)$q$,'22023'::char(5),null,'SLF-004 blank trimmed reason refused');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,repeat('x',2001),'81900000-0000-4000-8000-000000000733'::uuid)$q$,'22023'::char(5),null,'SLF-004 reason above 2000 refused');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000214'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'pending plan','81900000-0000-4000-8000-000000000734'::uuid)$q$,'GL066'::char(5),null,'SLF-002 pending membership grants no freeze creation');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date + 400,(now() at time zone 'Asia/Kolkata')::date + 404,'beyond span','81900000-0000-4000-8000-000000000735'::uuid)$q$,'22023'::char(5),null,'SLF-004 interval must lie within the membership span');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date + 10,(now() at time zone 'Asia/Kolkata')::date + 14,'second open','81900000-0000-4000-8000-000000000736'::uuid)$q$,'GL067'::char(5),null,'SLF_LIMITS one effective open request per member');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000312','role','authenticated','app_role','trainer','tenant_id','81900000-0000-4000-8000-000000000001')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'trainer','81900000-0000-4000-8000-000000000737'::uuid)$q$,'42501'::char(5),null,'SLF-003 trainer gains no member self-service');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000344','role','authenticated','app_role','super_admin')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'platform','81900000-0000-4000-8000-000000000738'::uuid)$q$,'42501'::char(5),null,'SLF-003 platform identity gains no member self-service');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000344','role','authenticated','app_role','super_admin','impersonation_session_id','81900000-0000-4000-8000-000000000999')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'preview','81900000-0000-4000-8000-000000000739'::uuid)$q$,'42501'::char(5),null,'SLF-003 support preview gains no member self-service');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000303','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000103')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'erased','81900000-0000-4000-8000-000000000740'::uuid)$q$,'P0002'::char(5),null,'SLF-003 erased member gains no self-service');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000399','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'unlinked','81900000-0000-4000-8000-000000000741'::uuid)$q$,'P0002'::char(5),null,'SLF-003 a live token alone preserves no unlinked actor permission');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000002','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'cross tenant','81900000-0000-4000-8000-000000000742'::uuid)$q$,'P0002'::char(5),null,'SLF-003 foreign tenant claims expose no target');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000302','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000102')::text, true);
select is((holdout_slf.request_freeze('81900000-0000-4000-8000-000000000203'::uuid,
        (now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'adjacent ok',
        '81900000-0000-4000-8000-000000000703'::uuid)->>'status'),
 'requested','SLF-005 adjacent intervals sharing no date are allowed');
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000203'::uuid,(now() at time zone 'Asia/Kolkata')::date + 7,(now() at time zone 'Asia/Kolkata')::date + 9,'overlap','81900000-0000-4000-8000-000000000743'::uuid)$q$,'GL067'::char(5),null,'SLF-005 inclusive overlap with an approved source pause is refused');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000341','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000114')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000218'::uuid,(now() at time zone 'Asia/Kolkata')::date + 12,(now() at time zone 'Asia/Kolkata')::date + 13,'other membership','81900000-0000-4000-8000-000000000744'::uuid)$q$,null::char(5),null,'SLF-005 a different membership id does not bypass member-level conflict');

create or replace function holdout_slf.request_id_by_key(p_key uuid) returns uuid language plpgsql as $f$
declare v uuid;
begin
  execute format('select id from %I.member_freeze_requests where tenant_id = $1 and request_key = $2',
                 current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, p_key;
  return v;
end $f$;
create or replace function holdout_slf.request_row_json(p_key uuid) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  execute format('select to_jsonb(r) from %I.member_freeze_requests r where tenant_id = $1 and request_key = $2',
                 current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, p_key;
  return v;
end $f$;
create or replace function holdout_slf.command_count(p_key uuid, p_action text) returns bigint language plpgsql as $f$
declare v bigint;
begin
  execute format('select count(*) from %I.member_freeze_commands c join %I.member_freeze_requests r on r.id = c.request_id '
                 || 'where r.tenant_id = $1 and r.request_key = $2 and ($3::text is null or c.action = $3)',
                 current_setting('h81.schema'), current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, p_key, p_action;
  return v;
end $f$;
create or replace function holdout_slf.member_request_count(p_member uuid, p_status text) returns bigint language plpgsql as $f$
declare v bigint;
begin
  execute format('select count(*) from %I.member_freeze_requests where tenant_id = $1 and member_id = $2 and status::text = $3',
                 current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, p_member, p_status;
  return v;
end $f$;
create or replace function holdout_slf.pause_count_for_request(p_key uuid) returns bigint language plpgsql as $f$
declare v bigint;
begin
  execute format('select count(*) from public.membership_pauses p where p.id in '
                 || '(select source_pause_id from %I.member_freeze_requests where tenant_id = $1 and request_key = $2 and source_pause_id is not null)',
                 current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, p_key;
  return v;
end $f$;
create or replace function holdout_slf.h81_approve_cancelled_pause() returns void language plpgsql as $f$
declare v uuid;
begin
  execute format('select source_pause_id from %I.member_freeze_requests where tenant_id = $1 and request_key = $2',
                 current_setting('h81.schema'))
    into v using '81900000-0000-4000-8000-000000000001'::uuid, '81900000-0000-4000-8000-000000000710'::uuid;
  update public.membership_pauses set approved_at = now(), approved_by_staff_id = '81900000-0000-4000-8000-000000000403' where id = v;
end $f$;
grant execute on all functions in schema holdout_slf to authenticated, anon;

-- §B5 Adoption (SLF-006). R1 = key …701 (M1), R3 = …703 (M3).
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select is((holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),1::bigint,'81900000-0000-4000-8000-000000000801'::uuid)->>'status'),
 'desk_submitted','SLF-006 real front office adopts a requested row as awaiting approval');
select is((select p.requested_by_staff_id from public.membership_pauses p
            where p.id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'source_pause_id')::uuid),
 '81900000-0000-4000-8000-000000000402','SLF-006 the adopting caller is the real pause requester, never a member or a colleague');
select ok((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'adopted_by_staff_id' is not null
       and holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'adopted_at' is not null
       and holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'source_pause_id' is not null),
 'SLF-006 adopted fields present exactly with the source link');
select is((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'revision'),'2','SLF-014 revision advances once per material transition');
select is((holdout_slf.command_count('81900000-0000-4000-8000-000000000701'::uuid,null)),2::bigint,'SLF-015 create and adopt each appended one atomic command row');
select is((holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),1::bigint,'81900000-0000-4000-8000-000000000801'::uuid)->>'replayed'),
 'true','SLF-013 identical adopt replay returns the original result read-only');
select is((holdout_slf.pause_count_for_request('81900000-0000-4000-8000-000000000701'::uuid)),1::bigint,'SLF-013 adopt replay created no second source pause');
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000801'::uuid)$q$,'GL068'::char(5),null,'SLF-013 changed expected revision under the adopt key conflicts');
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),999::bigint,'81900000-0000-4000-8000-000000000802'::uuid)$q$,'GL066'::char(5),null,'SLF-013 a stale revision refuses before effects');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000312','role','authenticated','app_role','trainer','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000405')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000703'::uuid),1::bigint,'81900000-0000-4000-8000-000000000803'::uuid)$q$,'42501'::char(5),null,'SLF-006 trainers are not front office');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000314','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000002','staff_id','81900000-0000-4000-8000-000000000407')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000804'::uuid)$q$,'42501'::char(5),null,'SLF-003 another gym front office gains no target');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000805'::uuid)$q$,'42501'::char(5),null,'SLF-006 members cannot adopt their own request');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000806'::uuid)$q$,'GL066'::char(5),null,'SLF-006 a desk_submitted request is not adoptable again');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select throws_ok($q$insert into public.membership_pauses(tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id) values ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000201',(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 2,'forged colleague','81900000-0000-4000-8000-000000000403')$q$,null::char(5),null,'SLF-006 adoption never names a different employee (existing GL026 guard stays authoritative)');

-- §B6 Approval (SLF-007/012).
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000811'::uuid)->>'status'),
 'approved','SLF-007 the configured-role second staff member approves');
select is((select approved_by_staff_id from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'source_pause_id')::uuid),
 '81900000-0000-4000-8000-000000000403','SLF-007 the approval pair carries the real deciding caller');
select is((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'revision'),'3','SLF-014 approval advances revision exactly once');
select ok((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000701'::uuid)->>'closed_at' is not null),'SLF-014 terminal status carries closure');
-- M5 flow: member U5 creates, desk adopts, then the ADOPTER tries to approve own.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000305','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000104')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000205'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'two person','81900000-0000-4000-8000-000000000705'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000705'::uuid),1::bigint,'81900000-0000-4000-8000-000000000812'::uuid);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000705'::uuid),2::bigint,'81900000-0000-4000-8000-000000000813'::uuid)$q$,null::char(5),null,'SLF-007 the adopter cannot approve their own sponsorship (GL021 boundary)');
-- M6 flow: owner attempt while the configured approver role is gym_manager.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000306','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000105')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000206'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'owner rank','81900000-0000-4000-8000-000000000706'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000706'::uuid),1::bigint,'81900000-0000-4000-8000-000000000814'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000308','role','authenticated','app_role','gym_owner','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000401')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000706'::uuid),2::bigint,'81900000-0000-4000-8000-000000000815'::uuid)$q$,null::char(5),null,'SLF-007 owner rank does not override a different configured approver role');
-- M7 flow: owner approves when the configured role is gym_owner.
update public.organization_settings set pause_approver_role = 'gym_owner' where tenant_id = '81900000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000307','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000106')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000207'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'owner config','81900000-0000-4000-8000-000000000707'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000707'::uuid),1::bigint,'81900000-0000-4000-8000-000000000816'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000308','role','authenticated','app_role','gym_owner','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000401')::text, true);
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000707'::uuid),2::bigint,'81900000-0000-4000-8000-000000000817'::uuid)->>'status'),
 'approved','SLF-007 the owner approves when the configured role is gym_owner');
select is((select approved_by_staff_id from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000707'::uuid)->>'source_pause_id')::uuid),
 '81900000-0000-4000-8000-000000000401','SLF-007 owner approval carries the owner as the real decision actor');
update public.organization_settings set pause_approver_role = 'gym_manager' where tenant_id = '81900000-0000-4000-8000-000000000001';
-- M8 flow: an approved 28-day pause already exists this year; 3 more refuse.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000315','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000107')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000208'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 2,'budget','81900000-0000-4000-8000-000000000708'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000708'::uuid),1::bigint,'81900000-0000-4000-8000-000000000818'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000708'::uuid),2::bigint,'81900000-0000-4000-8000-000000000819'::uuid)$q$,'GL067'::char(5),null,'SLF-012 used 28 whole days + proposed 3 exceeds max_freeze_days_per_year 30 at final approval');
-- M9 flow: a 396-day approved pause is charged wholly to its start year.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000316','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000108')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000209'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 1,'start year','81900000-0000-4000-8000-000000000709'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000709'::uuid),1::bigint,'81900000-0000-4000-8000-000000000820'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000709'::uuid),2::bigint,'81900000-0000-4000-8000-000000000821'::uuid)$q$,'GL067'::char(5),null,'SLF-012 the whole 396-day interval counts in its start calendar year, so two more days refuse');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000316','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000108')::text, true);
select is((holdout_slf.cancel_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000709'::uuid),'81900000-0000-4000-8000-000000000822'::uuid)->>'status'),
 'cancelled','SLF-009 the original member withdraws the refused request');
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000209'::uuid,
 make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int + 1,2,10),
 make_date(extract(year from (now() at time zone 'Asia/Kolkata')::date)::int + 1,2,16),'next year','81900000-0000-4000-8000-000000000719'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000719'::uuid),1::bigint,'81900000-0000-4000-8000-000000000823'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000719'::uuid),2::bigint,'81900000-0000-4000-8000-000000000824'::uuid)->>'status'),
 'approved','SLF-012 the next calendar year starts from zero despite last year spilling into it');
-- M10 flow: the 28-day pause sits on an EXPIRED membership; the member bucket spans memberships.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000317','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000109')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000210'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 2,'member scope','81900000-0000-4000-8000-000000000710'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000710'::uuid),1::bigint,'81900000-0000-4000-8000-000000000825'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000710'::uuid),2::bigint,'81900000-0000-4000-8000-000000000826'::uuid)$q$,'GL067'::char(5),null,'SLF-012 allowance is member-scoped across memberships, including an expired membership approved pause');
-- M11 flow: a 30-day REJECTED pause consumes nothing.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000318','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000110')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000212'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 2,'rejected free','81900000-0000-4000-8000-000000000711'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000711'::uuid),1::bigint,'81900000-0000-4000-8000-000000000827'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000711'::uuid),2::bigint,'81900000-0000-4000-8000-000000000828'::uuid)->>'status'),
 'approved','SLF-012 a rejection never consumes budget, so approval succeeds despite 30 rejected days');
-- M12 flow: an intervening directly-approved desk pause changes the recheck.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000319','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000111')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000213'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'recheck','81900000-0000-4000-8000-000000000712'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000712'::uuid),1::bigint,'81900000-0000-4000-8000-000000000829'::uuid);
insert into public.membership_pauses(tenant_id,membership_id,starts_on,ends_on,reason,requested_by_staff_id,approved_by_staff_id,approved_at) values
 ('81900000-0000-4000-8000-000000000001','81900000-0000-4000-8000-000000000213',(now() at time zone 'Asia/Kolkata')::date - 40,(now() at time zone 'Asia/Kolkata')::date - 13,'intervening desk pause','81900000-0000-4000-8000-000000000402','81900000-0000-4000-8000-000000000403',now());
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000712'::uuid),2::bigint,'81900000-0000-4000-8000-000000000830'::uuid)$q$,'GL067'::char(5),null,'SLF-012 final approval rechecks under serialization against intervening desk pauses');
-- M13 flow: the configured role changes between adoption and approval.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000320','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000112')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000215'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 2,'role change','81900000-0000-4000-8000-000000000713'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000713'::uuid),1::bigint,'81900000-0000-4000-8000-000000000831'::uuid);
update public.organization_settings set pause_approver_role = 'front_desk' where tenant_id = '81900000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000713'::uuid),2::bigint,'81900000-0000-4000-8000-000000000832'::uuid)$q$,null::char(5),null,'SLF-007 the current configured role is read at approval time, not adoption time');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000313','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000406')::text, true);
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000713'::uuid),2::bigint,'81900000-0000-4000-8000-000000000833'::uuid)->>'status'),
 'approved','SLF-007 a different active staff member of the new configured role approves');
update public.organization_settings set pause_approver_role = 'gym_manager' where tenant_id = '81900000-0000-4000-8000-000000000001';
select is((holdout_slf.approve_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),2::bigint,'81900000-0000-4000-8000-000000000811'::uuid)->>'replayed'),
 'true','SLF-013 approve replay after the decision returns the original result');
select is((holdout_slf.command_count('81900000-0000-4000-8000-000000000701'::uuid,null)),3::bigint,'SLF-015 replays append no second command row');
select throws_ok($q$select holdout_slf.reject_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),3::bigint,'too late','81900000-0000-4000-8000-000000000834'::uuid)$q$,'GL066'::char(5),null,'SLF-008 an approved source pause is never rewritten by rejection');

-- §B7 Rejection, withdrawal, expiry (SLF-008/009/010).
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000342','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000115')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000217'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'reject me','81900000-0000-4000-8000-000000000716'::uuid);
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select is((holdout_slf.reject_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000716'::uuid),1::bigint,'cannot accommodate dates','81900000-0000-4000-8000-000000000835'::uuid)->>'status'),
 'rejected','SLF-008 real front office rejects an open request with a member-visible reason');
select ok((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000716'::uuid)->>'decided_by_staff_id' is not null
       and holdout_slf.request_row_json('81900000-0000-4000-8000-000000000716'::uuid)->>'closed_at' is not null
       and holdout_slf.request_row_json('81900000-0000-4000-8000-000000000716'::uuid)->>'decision_reason' is not null),
 'SLF-008 rejection records the actual actor, reason and closure');
select throws_ok($q$select holdout_slf.reject_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000703'::uuid),1::bigint,'no','81900000-0000-4000-8000-000000000836'::uuid)$q$,'22023'::char(5),null,'SLF-008 rejection reason below three characters refused');
select is((holdout_slf.reject_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000712'::uuid),2::bigint,'desk cannot cover','81900000-0000-4000-8000-000000000837'::uuid)->>'status'),
 'rejected','SLF-008 rejection of a desk_submitted request');
select ok((select rejected_at is not null from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000712'::uuid)->>'source_pause_id')::uuid),
 'SLF-008 the linked undecided source pause is rejected as the real staff caller');
-- Member withdrawal.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000341','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000114')::text, true);
select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000216'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'withdraw me','81900000-0000-4000-8000-000000000715'::uuid);
select is((holdout_slf.cancel_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000715'::uuid),'81900000-0000-4000-8000-000000000838'::uuid)->>'status'),
 'cancelled','SLF-009 the original member cancels a requested row');
select is((holdout_slf.request_row_json('81900000-0000-4000-8000-000000000715'::uuid)->>'cancelled_by_user_id'),
 '81900000-0000-4000-8000-000000000341','SLF-009 cancellation carries the original member subject');
select is((holdout_slf.cancel_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000710'::uuid),'81900000-0000-4000-8000-000000000839'::uuid)->>'status'),
 'cancelled','SLF-009 withdrawal works for a desk_submitted row and needs ownership, not eligibility');
select ok((select approved_at is null and rejected_at is null from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000710'::uuid)->>'source_pause_id')::uuid),
 'SLF-009 the linked undecided source pause remains unapproved historical evidence');
select throws_ok($q$select holdout_slf.h81_approve_cancelled_pause()$q$,null::char(5),null,'SLF-009 every subsequent attempt, including a direct staff approval, refuses the closed request source');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000341','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000114')::text, true);
select throws_ok($q$select holdout_slf.cancel_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000710'::uuid),'81900000-0000-4000-8000-000000000840'::uuid)$q$,'P0002'::char(5),null,'SLF-009 a member cannot cancel another member request');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select throws_ok($q$select holdout_slf.cancel_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),'81900000-0000-4000-8000-000000000841'::uuid)$q$,'GL066'::char(5),null,'SLF-009 cancellation never undoes an approved freeze');
-- Expiry (SLF-010). M6's desk_submitted request with a retiring membership.
update public.memberships set status = 'expired' where id = '81900000-0000-4000-8000-000000000206';
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select is((holdout_slf.expire_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000706'::uuid),2::bigint,'81900000-0000-4000-8000-000000000842'::uuid)->>'status'),
 'expired','SLF-010 an ineffective request materializes closure exactly once');
select throws_ok($q$select holdout_slf.expire_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000706'::uuid),3::bigint,'81900000-0000-4000-8000-000000000843'::uuid)$q$,'GL066'::char(5),null,'SLF-010 expiry is a once-only materialization');
-- Effective expiry without materialization (M3: retire MS3 under the open request).
update public.memberships set status = 'expired' where id = '81900000-0000-4000-8000-000000000203';
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000703'::uuid),1::bigint,'81900000-0000-4000-8000-000000000844'::uuid)$q$,'GL066'::char(5),null,'SLF-010 effective expiration refuses adoption before closure is materialized');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000302','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000102')::text, true);
select is((holdout_slf.read_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000703'::uuid))->>'effectiveStatus'),
 'expired','SLF-010 reads derive the effective expired state');
select is((holdout_slf.read_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000703'::uuid))->>'status'),
 'requested','SLF-010 reads never write; the persisted state is unchanged');
select is((holdout_slf.command_count('81900000-0000-4000-8000-000000000703'::uuid,null)),1::bigint,'SLF-010 reads appended no command evidence');
-- Expiry leaves a linked undecided pause intact (M10 was cancelled; use R12's linked pause? R12 was rejected.
-- Use the desk_submitted R8 whose approval was refused for budget; retire MS8 and expire it.
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select ok((select approved_at is null and rejected_at is null from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000708'::uuid)->>'source_pause_id')::uuid),
 'SLF-010 the refused-approval request still holds its undecided source pause before closure');
update public.memberships set status = 'expired' where id = '81900000-0000-4000-8000-000000000208';
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select holdout_slf.expire_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000708'::uuid),2::bigint,'81900000-0000-4000-8000-000000000845'::uuid);
select ok((select approved_at is null and rejected_at is null from public.membership_pauses where id = (holdout_slf.request_row_json('81900000-0000-4000-8000-000000000708'::uuid)->>'source_pause_id')::uuid),
 'SLF-010 materialized expiry leaves the linked undecided source pause intact');

-- §B8 Replay, audit truth, structural defense (SLF-013/014/015).
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select is((holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),1::bigint,'81900000-0000-4000-8000-000000000801'::uuid)->>'replayed'),
 'true','SLF-013 an exact authorized replay precedes revision and eligibility checks even after approval');
select is((holdout_slf.command_count('81900000-0000-4000-8000-000000000708'::uuid,'approve')),0::bigint,'SLF-015 refused commands append no audit evidence');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000310','role','authenticated','app_role','gym_manager','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000403')::text, true);
select throws_ok($q$select holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000712'::uuid),2::bigint,'81900000-0000-4000-8000-000000000829'::uuid)$q$,'GL068'::char(5),null,'SLF-013 a changed actor under an existing command key conflicts');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000301','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000101')::text, true);
select throws_ok($q$select holdout_slf.request_freeze('81900000-0000-4000-8000-000000000201'::uuid,(now() at time zone 'Asia/Kolkata')::date,(now() at time zone 'Asia/Kolkata')::date + 4,'fresh after terminal','81900000-0000-4000-8000-000000000701'::uuid)$q$,'GL068'::char(5),null,'SLF-013 a fresh command reusing a terminal request key conflicts without leaking stored facts');
select throws_ok($q$select holdout_slf.h81_commands_update()$q$,null::char(5),null,'SLF-014 the command ledger is immutable to every writer (update)');
select throws_ok($q$select holdout_slf.h81_commands_delete()$q$,null::char(5),null,'SLF-014 the command ledger is immutable to every writer (delete)');
select throws_ok($q$select holdout_slf.h81_frozen_update()$q$,null::char(5),null,'SLF-014 request identity/scope/reason fields are frozen for every writer');
select throws_ok($q$select holdout_slf.h81_terminal_update()$q$,null::char(5),null,'SLF-014 a terminal row permits only updated_at');
select throws_ok($q$select holdout_slf.h81_born_advanced()$q$,null::char(5),null,'SLF-014 no writer inserts a born-advanced request row');
select throws_ok($q$select holdout_slf.h81_cross_tenant_request()$q$,null::char(5),null,'SLF-014 tenant-composite relationships hold for every writer');
select throws_ok($q$select holdout_slf.h81_dup_request_key()$q$,'23505'::char(5),null,'SLF-014 unique (tenant_id, request_key)');
select throws_ok($q$select holdout_slf.h81_dup_source_pause()$q$,'23505'::char(5),null,'SLF-014 partial unique (tenant_id, source_pause_id)');
select throws_ok($q$select holdout_slf.h81_dup_command_key()$q$,'23505'::char(5),null,'SLF-014 unique (tenant_id, command_key)');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000344','role','authenticated','app_role','super_admin')::text, true);
select throws_ok($q$select holdout_slf.read_staff_list(10::integer,null::timestamptz,null::uuid)$q$,'42501'::char(5),null,'SLF-003 platform identities gain no staff freeze queue');
select throws_ok($q$select holdout_slf.read_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid))$q$,'42501'::char(5),null,'SLF-003 platform preview gains no request detail');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000341','role','authenticated','app_role','member','tenant_id','81900000-0000-4000-8000-000000000001','member_id','81900000-0000-4000-8000-000000000114')::text, true);
select throws_ok($q$select holdout_slf.read_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid))$q$,'P0002'::char(5),null,'SLF-003 a member cannot read another member request');
select ok(holdout_slf.read_member_list(10::integer,null::timestamptz,null::uuid) @> jsonb_build_array(jsonb_build_object('requestId',holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000715'::uuid)))
   and not holdout_slf.read_member_list(10::integer,null::timestamptz,null::uuid) @> jsonb_build_array(jsonb_build_object('requestId',holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid))),
 'SLF-003 the member list is own-member scoped with a deterministic descending keyset');
select throws_ok($q$select holdout_slf.read_staff_list(10::integer,null::timestamptz,null::uuid)$q$,'42501'::char(5),null,'SLF-003 an impersonating identity gains no staff queue');
select set_config('request.jwt.claims', '{bad json'::text, true);
select throws_ok($q$select holdout_slf.read_staff_list(10::integer,null::timestamptz,null::uuid)$q$,null::char(5),null,'SLF-003 forged or malformed claims confer no authority');
select set_config('request.jwt.claims', json_build_object('sub','81900000-0000-4000-8000-000000000309','role','authenticated','app_role','front_desk','tenant_id','81900000-0000-4000-8000-000000000001','staff_id','81900000-0000-4000-8000-000000000402')::text, true);
select is(jsonb_typeof((holdout_slf.adopt_request(holdout_slf.request_id_by_key('81900000-0000-4000-8000-000000000701'::uuid),1::bigint,'81900000-0000-4000-8000-000000000801'::uuid)->'revision')),
 'string','SLF-005 bigint revisions and day counts travel as canonical decimal strings');
select is((holdout_slf.member_request_count('81900000-0000-4000-8000-000000000114'::uuid,'cancelled')),1::bigint,'SLF-005 cancelled evidence reserves no days and history remains intact');

select * from finish();
rollback;

