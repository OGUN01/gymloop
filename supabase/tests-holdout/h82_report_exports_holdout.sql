-- Fixture repair 2026-10-04: pg_proc.proconfig is text[], so read its
-- explicit search_path entry instead of applying a JSON operator.
-- 2026-10-04 independent reconciliation: frozen public contracts only; no
-- implementation, migrations, visible suites or private diagnostics read.
-- Independent holdout: the RPE database surface, derived from the frozen
-- contract (openspec/changes/report-exports/proposal.md — architecture
-- section "one bounded invoker data operation per artifact", "a definer may
-- elevate only audit append privileges", RPE-001/002/004/005/009) and
-- docs/design/v2/rpe-bar.md only. No visible suite, no implementation, no
-- registry, no other holdout file was read. Invoice half is DEFERRED (CSV
-- first): no invoice surface is pinned here.
--
-- Pattern chosen (stated per directive): hybrid. Section A pins the REAL
-- migration's shape through NULL-safe catalog probes and is RED until the
-- real migration lands. Section B pins the contract's BEHAVIOR through a
-- guarded stand-in mirror (schema holdout_rpe) that implements the frozen
-- semantics over the real public tables, so it is meaningful today. The
-- operation names below (public.export_report_snapshot /
-- public.append_report_export_event) are contract-role names chosen by this
-- author, not frozen text: if the implemented seam lands under different
-- names, the expectations — not the names — are the held contract, and
-- re-pointing Section A is a spec: round-trip.
--
-- Fixture uuids are prefixed 82900000-. Everything rolls back; nothing
-- commits; nothing was executed against any database by this author.
begin;
set local role postgres;
set local search_path to public, extensions, holdout_rpe;
select plan(62);

-- §A — real-migration shape pins (RED until the migration lands; NULL-safe).
select ok(to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') is not null,'bounded public snapshot operation exists for the CSV artifact');
select ok(to_regprocedure('public.append_report_export_event(text,uuid,jsonb)') is not null,'narrow public audit append helper exists');
select is((select r.rolname from pg_proc p join pg_roles r on r.oid = p.proowner where p.oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'postgres','snapshot operation is postgres-owned');
select is((select r.rolname from pg_proc p join pg_roles r on r.oid = p.proowner where p.oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'postgres','audit helper is postgres-owned');
select is((select prosecdef from pg_proc where oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),false,'snapshot operation is security invoker so caller RLS decides every row');
select is((select prosecdef from pg_proc where oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),true,'audit helper is definer so it alone elevates');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'','snapshot operation runs an empty search path');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'','audit helper runs an empty search path');
select ok(has_function_privilege('authenticated','public.export_report_snapshot(text,date,date,uuid,integer)','EXECUTE'),'authenticated holds EXECUTE on the snapshot operation');
select ok(not has_function_privilege('anon','public.export_report_snapshot(text,date,date,uuid,integer)','EXECUTE'),'anon holds no EXECUTE on the snapshot operation');
select ok(not exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC holds no EXECUTE on the snapshot operation');
select ok(has_function_privilege('authenticated','public.append_report_export_event(text,uuid,jsonb)','EXECUTE'),'authenticated holds EXECUTE on the audit helper');
select ok(not has_function_privilege('anon','public.append_report_export_event(text,uuid,jsonb)','EXECUTE'),'anon holds no EXECUTE on the audit helper');
select ok(not has_table_privilege('authenticated','public.audit_log','INSERT'),'authenticated cannot INSERT audit rows directly');
select ok(not has_table_privilege('authenticated','public.audit_log','UPDATE'),'authenticated cannot UPDATE audit rows');
select ok(not has_table_privilege('authenticated','public.audit_log','DELETE'),'authenticated cannot DELETE audit rows');
select ok(not has_table_privilege('authenticated','public.audit_log','TRUNCATE'),'authenticated cannot TRUNCATE audit');
select ok((select relrowsecurity from pg_class where oid = 'public.audit_log'::regclass),'audit_log keeps RLS enabled');

-- §B fixtures (mirror DDL + rows; all inside the rolled-back transaction).
create schema holdout_rpe;
create table holdout_rpe.report_export_events(
  event text not null,
  export_id uuid not null,
  tenant_id uuid not null,
  actor_user_id uuid not null,
  details jsonb not null,
  occurred_at timestamptz not null default now()
);
create function holdout_rpe.export_snapshot(p_dataset text, p_from date, p_through date, p_branch_id uuid default null, p_row_cap integer default null) returns jsonb
language plpgsql security invoker set search_path = '' as $fn$
declare
  c jsonb; s record; z text; n integer; lo timestamptz; hi timestamptz; payload jsonb;
begin
  -- Actor revalidation strictly before parameter validation, target lookup
  -- or any source read (RPE-001).
  c := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if c is null then raise insufficient_privilege; end if;
  if c->>'impersonation_session_id' is not null then raise insufficient_privilege; end if;
  if c->>'app_role' is distinct from 'gym_owner' then raise insufficient_privilege; end if;
  if c->>'sub' is null or c->>'staff_id' is null or c->>'tenant_id' is null then raise insufficient_privilege; end if;
  select * into s from public.staff where id = (c->>'staff_id')::uuid;
  if not found then raise insufficient_privilege; end if;
  if s.user_id is distinct from (c->>'sub')::uuid or s.is_active is distinct from true
     or s.tenant_id is distinct from (c->>'tenant_id')::uuid or s.role is distinct from 'gym_owner' then
    raise insufficient_privilege;
  end if;
  -- Zone before range: an invalid configured zone is an explicit error, never
  -- a silent fallback (RPE-003).
  select timezone into z from public.organizations where id = s.tenant_id;
  begin
    perform 1 where exists (select 1 from pg_timezone_names where name = z);
    lo := p_from::timestamp at time zone z;
    hi := (p_through + 1)::timestamp at time zone z;
  exception when others then
    raise exception 'invalid configured time zone' using errcode = '22023';
  end;
  if p_from is null or p_through is null or p_from > p_through then
    raise exception 'invalid export range' using errcode = '22023';
  end if;
  if p_row_cap is null or p_row_cap < 1 then
    raise exception 'row cap required' using errcode = '22023';
  end if;
  -- Unknown ≡ foreign branch: one refusal, no existence information (RPE-002).
  if p_branch_id is not null then
    perform 1 from public.branches b where b.id = p_branch_id and b.tenant_id = s.tenant_id;
    if not found then raise exception 'branch unavailable' using errcode = '22023'; end if;
  end if;
  if p_dataset = 'payments' then
    with snap as (
      select p.id, p.member_id, m.member_code, m.full_name as member_name,
             p.amount_paise::text as amount_paise, p.currency, p.status, p.method,
             p.created_at, p.paid_at, p.receipt_number
      from public.payments p
      left join public.members m on m.id = p.member_id and m.tenant_id = p.tenant_id
      where p.tenant_id = s.tenant_id
        and p.created_at >= lo and p.created_at < hi
        and (p_branch_id is null or exists (
          select 1 from public.members pm where pm.id = p.member_id and pm.branch_id = p_branch_id))
      order by p.created_at, p.id
    )
    select jsonb_build_object(
      'rows', coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]'::jsonb),
      'count', (select count(*) from snap),
      'asOf', now()::text, 'zone', z,
      'rangeFrom', p_from, 'rangeThrough', p_through
    ) into payload from snap;
  elsif p_dataset = 'members' then
    with snap as (
      select m.id, m.member_code, m.full_name, m.phone, m.email, m.branch_id, m.status, m.joined_on
      from public.members m
      where m.tenant_id = s.tenant_id and m.joined_on between p_from and p_through
      order by m.joined_on, m.id
    )
    select jsonb_build_object(
      'rows', coalesce(jsonb_agg(to_jsonb(x) order by x.joined_on, x.id), '[]'::jsonb),
      'count', (select count(*) from snap),
      'asOf', now()::text, 'zone', z,
      'rangeFrom', p_from, 'rangeThrough', p_through
    ) into payload from snap;
  else
    raise exception 'unknown export dataset' using errcode = '22023';
  end if;
  -- Cap+1 boundary: one bounded payload; over the cap the whole artifact is
  -- refused, never a truncated list (RPE-004).
  n := (payload->>'count')::integer;
  if n > p_row_cap then
    raise exception 'export exceeds row cap' using errcode = '22023';
  end if;
  return payload;
end $fn$;
create function holdout_rpe.append_event(p_event text, p_export_id uuid, p_details jsonb) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  c jsonb; u uuid; t uuid;
  allowed text[] := array['report_export.prepared','report_export.released'];
begin
  c := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if c is null then raise insufficient_privilege; end if;
  if c->>'impersonation_session_id' is not null then raise insufficient_privilege; end if;
  u := (c->>'sub')::uuid;
  t := (c->>'tenant_id')::uuid;
  if u is null or t is null then raise insufficient_privilege; end if;
  if not (p_event = any(allowed)) then
    raise exception 'unknown export audit event' using errcode = '22023';
  end if;
  -- No arbitrary payload: a fixed key set, actor never caller-supplied
  -- (RPE-009); release must carry bytes and SHA-256.
  if p_details is null
     or p_details ? 'actor' or p_details ? 'rows' or p_details ? 'payload' or p_details ? 'name' or p_details ? 'phone'
     or exists (select 1 from jsonb_object_keys(p_details) k
                where k not in ('dataset','format','rangeFrom','rangeThrough','rangeBasis','timezone','branchScope','rowCount','sha256','byteCount','snapshotAt')) then
    raise exception 'arbitrary export audit payload refused' using errcode = '22023';
  end if;
  if p_event = 'report_export.prepared' then
    if exists (select 1 from holdout_rpe.report_export_events e where e.export_id = p_export_id and e.event = 'report_export.prepared') then
      raise exception 'prepared already recorded' using errcode = '22023';
    end if;
  end if;
  if p_event = 'report_export.released' then
    if not exists (select 1 from holdout_rpe.report_export_events e where e.export_id = p_export_id and e.event = 'report_export.prepared' and e.tenant_id = t) then
      raise exception 'release requires its prepared event' using errcode = '22023';
    end if;
    if exists (select 1 from holdout_rpe.report_export_events e where e.export_id = p_export_id and e.event = 'report_export.released') then
      raise exception 'release already recorded' using errcode = '22023';
    end if;
    if p_details ? 'sha256' is distinct from true or p_details ? 'byteCount' is distinct from true then
      raise exception 'release must record bytes and digest' using errcode = '22023';
    end if;
  end if;
  insert into holdout_rpe.report_export_events(event, export_id, tenant_id, actor_user_id, details)
  values (p_event, p_export_id, t, u, p_details);
end $fn$;
grant execute on function holdout_rpe.export_snapshot(text,date,date,uuid,integer) to authenticated;
grant execute on function holdout_rpe.append_event(text,uuid,jsonb) to authenticated;

insert into public.organizations(id,name,gym_code,status) values
 ('82900000-0000-4000-8000-000000000001','H82 Export Gym','H82EXP','active'),
 ('82900000-0000-4000-8000-000000000009','H82 Other Gym','H82OTH','active');
insert into public.branches(id,tenant_id,name,timezone) values
 ('82900000-0000-4000-8000-000000000901','82900000-0000-4000-8000-000000000001','H82 Main',null),
 ('82900000-0000-4000-8000-000000000902','82900000-0000-4000-8000-000000000009','H82 Far',null);
insert into auth.users(id) values
 ('82900000-0000-4000-8000-000000000011'),('82900000-0000-4000-8000-000000000012'),
 ('82900000-0000-4000-8000-000000000013'),('82900000-0000-4000-8000-000000000014'),
 ('82900000-0000-4000-8000-000000000015'),('82900000-0000-4000-8000-000000000016'),
 ('82900000-0000-4000-8000-000000000017');
insert into public.staff(id,tenant_id,user_id,role,full_name,is_active) values
 ('82900000-0000-4000-8000-000000000021','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000011','gym_owner','H82 Owner',true),
 ('82900000-0000-4000-8000-000000000022','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000012','front_desk','H82 Desk',true),
 ('82900000-0000-4000-8000-000000000023','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000013','trainer','H82 Trainer',true),
 ('82900000-0000-4000-8000-000000000024','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000014','gym_manager','H82 Manager',true),
 ('82900000-0000-4000-8000-000000000025','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000015','gym_owner','H82 Retired Owner',false),
 ('82900000-0000-4000-8000-000000000026','82900000-0000-4000-8000-000000000009','82900000-0000-4000-8000-000000000016','gym_owner','H82 Other Owner',true);
insert into public.members(id,tenant_id,branch_id,user_id,member_code,full_name,phone,status,joined_on,erased_at) values
 ('82900000-0000-4000-8000-000000000031','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000901',null,'H82-001','H82 Member','+919876500001','active','2026-09-15',null),
 ('82900000-0000-4000-8000-000000000032','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000901',null,null,'','+919876500002','active','2026-09-15','2026-09-20T10:00:00+00'::timestamptz),
 ('82900000-0000-4000-8000-000000000033','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000901','82900000-0000-4000-8000-000000000017','H82-003','H82 App Member','+919876500003','active','2026-09-15',null),
 ('82900000-0000-4000-8000-000000000034','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000901',null,'H82-004','H82 Late Member','+919876500004','active','2026-09-16',null);
-- Payment facts: range from=through=2026-09-15 gym-local (IST). Local
-- midnight 2026-09-15 = 2026-09-14T18:30:00Z; 2026-09-16 = 2026-09-15T18:30:00Z.
insert into public.payments(id,tenant_id,member_id,amount_paise,currency,status,method,receipt_number,recorded_by_staff_id,created_at,paid_at) values
 ('82900000-0000-4000-8000-000000000041','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000031',12345,'INR','created','cash',null,'82900000-0000-4000-8000-000000000021','2026-09-15T02:00:00+00'::timestamptz,null),
 ('82900000-0000-4000-8000-000000000042','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000031',9007199254740993,'INR','paid','cash','H82/R/002','82900000-0000-4000-8000-000000000021','2026-09-14T18:30:00+00'::timestamptz,'2026-09-14T18:30:00+00'::timestamptz),
 ('82900000-0000-4000-8000-000000000043','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000031',500,'USD','paid','cash','H82/R/003','82900000-0000-4000-8000-000000000021','2026-09-15T05:00:00+00'::timestamptz,'2026-09-15T05:00:00+00'::timestamptz),
 ('82900000-0000-4000-8000-000000000044','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000031',700,'INR','paid','cash','H82/R/004','82900000-0000-4000-8000-000000000021','2026-09-15T18:30:00+00'::timestamptz,'2026-09-15T18:30:00+00'::timestamptz),
 ('82900000-0000-4000-8000-000000000045','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000032',900,'INR','paid','cash','H82/R/006','82900000-0000-4000-8000-000000000021','2026-09-15T07:00:00+00'::timestamptz,'2026-09-15T07:00:00+00'::timestamptz),
 ('82900000-0000-4000-8000-000000000046','82900000-0000-4000-8000-000000000001','82900000-0000-4000-8000-000000000031',100,'INR','paid','cash','H82/R/001','82900000-0000-4000-8000-000000000021','2026-09-14T18:29:59+00'::timestamptz,'2026-09-14T18:29:59+00'::timestamptz);
-- …044 sits exactly on the excluded upper bound (2026-09-16 local midnight);
-- …046 sits one second before the included lower bound; both stay outside.

-- §B1 — actor revalidation matrix: refusal before any read, and no audit row.
select set_config('request.jwt.claims','',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'no claims gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000017","role":"authenticated","app_role":"member","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a member role claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000013","role":"authenticated","app_role":"trainer","staff_id":"82900000-0000-4000-8000-000000000023","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a trainer staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000012","role":"authenticated","app_role":"front_desk","staff_id":"82900000-0000-4000-8000-000000000022","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a front-desk staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000014","role":"authenticated","app_role":"gym_manager","staff_id":"82900000-0000-4000-8000-000000000024","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a manager staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000015","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000025","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a deactivated owner staff row gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000007","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a platform super-admin claim gains no gym export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000007","role":"authenticated","app_role":"super_admin","tenant_id":"82900000-0000-4000-8000-000000000001","staff_id":"82900000-0000-4000-8000-000000000021"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'mixed platform and gym identity is refused before any read');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000099","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a staff id that matches no row is refused');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001","impersonation_session_id":"82900000-0000-4000-8000-000000000098"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'an impersonated owner session gains no export authority');
-- Actor-first ordering: an invalid actor with an also-invalid range reports
-- the actor refusal, never the range (RPE-001).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000017","role":"authenticated","app_role":"member","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-10-01','2026-09-01',null,100)$q$,'42501',null,'actor revalidation precedes semantic parameter validation');
select ok(not exists(select 1 from holdout_rpe.report_export_events),'refused export attempts append no audit row');
-- A valid owner of ANOTHER tenant reads their own (empty) queue: scoping, not
-- erroring.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000016","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000026","tenant_id":"82900000-0000-4000-8000-000000000009"}',true);
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->>'count'),'0','a valid foreign-tenant owner reads their own empty scope');
-- Unknown ≡ foreign branch share one identical refusal (RPE-002).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select lives_ok($q$do $$ declare e1 text; e2 text; begin
 begin perform holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15','82900000-0000-4000-8000-000000000777',100); raise exception 'no refusal'; exception when others then e1 := sqlerrm; end;
 begin perform holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15','82900000-0000-4000-8000-000000000902',100); raise exception 'no refusal'; exception when others then e2 := sqlerrm; end;
 if e1 is null or e1 <> e2 then raise exception 'unknown and foreign branch refusals differ: % vs %', coalesce(e1,'<none>'), coalesce(e2,'<none>'); end if;
 end $$;$q$,'unknown and foreign branch ids share one unavailable refusal');

-- §B2 — zone and range honesty (RPE-003).
select throws_ok($q$do $$ begin
 update public.organizations set timezone='Mars/Olympus' where id='82900000-0000-4000-8000-000000000001';
 perform holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100);
 raise exception 'no zone refusal'; end $$;$q$,'22023',null,'an invalid configured zone is an explicit error, never a fallback');
update public.organizations set timezone='Asia/Kolkata' where id='82900000-0000-4000-8000-000000000001';
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->>'zone'),'Asia/Kolkata','the effective gym zone is disclosed on the payload');
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->>'count'),'4','the gym-local inclusive range admits exactly the four in-range payment rows');
select is((select count(*) from jsonb_array_elements(holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows') r where r->>'id' in ('82900000-0000-4000-8000-000000000042','82900000-0000-4000-8000-000000000041','82900000-0000-4000-8000-000000000043','82900000-0000-4000-8000-000000000045')),4::bigint,'lower bound included, before-range and upper-bound rows excluded');
select lives_ok($q$do $$ declare p jsonb; begin
 p := holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100);
 if (p->'rows'->0->>'id') <> '82900000-0000-4000-8000-000000000042' or (p->'rows'->1->>'id') <> '82900000-0000-4000-8000-000000000041' or (p->'rows'->2->>'id') <> '82900000-0000-4000-8000-000000000043' or (p->'rows'->3->>'id') <> '82900000-0000-4000-8000-000000000045' then
   raise exception 'payments snapshot is not in (created_at,id) order';
 end if;
 end $$;$q$,'the snapshot is deterministically ordered by (created_at,id)');

-- §B3 — projection honesty (RPE-005).
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->0->>'amount_paise'),'9007199254740993','beyond-safe-integer paise crosses as exact canonical text');
select ok((select jsonb_typeof(holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->0->'amount_paise') = 'string'),'money crosses the operation as a string, never a number');
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->3->>'member_name'),'','an erased member leaves the payment row with a blank current name');
select ok((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->3->>'member_code') is null,'an erased member leaves the payment row with no member code');
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->1->>'paid_at'),null,'a created attempt keeps its null paid time instead of an inferred instant');
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows'->1->>'receipt_number'),null,'a created attempt keeps its null receipt instead of an inferred number');
select is((select count(*) from jsonb_array_elements(holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100)->'rows') r where r->>'currency' = 'USD'),1::bigint,'a foreign-currency row is present as its own row');
select lives_ok($q$do $$ declare p jsonb; begin
 p := holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,100);
 if p ? 'totals' or p ? 'net' or p ? 'sum' then raise exception 'payload carries a fabricated aggregate'; end if;
 if (p->>'count') <> ((select count(*) from jsonb_array_elements(p->'rows'))::text) then raise exception 'count does not equal data rows'; end if;
 end $$;$q$,'no totals row or sum key exists and count equals the data rows');
select is((holdout_rpe.export_snapshot('members','2026-09-15','2026-09-15',null,100)->>'count'),'2','the member cohort is a direct joined_on comparison for the inclusive dates');
select is((holdout_rpe.export_snapshot('members','2026-09-15','2026-09-15',null,100)->'rows'->0->>'full_name'),'H82 Member','the member cohort carries the current recorded name');
select lives_ok($q$do $$ declare p jsonb; begin
 p := holdout_rpe.export_snapshot('members','2026-09-15','2026-09-15',null,100);
 if (p->'rows'->0->>'joined_on') <> '2026-09-15' or (p->'rows'->1->>'joined_on') <> '2026-09-15' then raise exception 'member range basis is not joined_on'; end if;
 end $$;$q$,'the member dataset orders and ranges on joined_on directly');

-- §B4 — the cap boundary: exactly at cap succeeds; cap+1 refuses the whole
-- artifact (RPE-004).
select is((holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,4)->>'count'),'4','a snapshot at exactly the row cap succeeds in full');
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-09-15','2026-09-15',null,3)$q$,'22023',null,'one row over the cap refuses the entire artifact');
select throws_ok($q$select holdout_rpe.export_snapshot('payments','2026-10-01','2026-09-01',null,100)$q$,'22023',null,'a reversed range is refused before any source read');

-- §B5 — the audit helper: fixed vocabulary, fixed payload shape, claims
-- actor, prepared-before-release linkage (RPE-009).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select lives_ok($q$select holdout_rpe.append_event('report_export.prepared','82900000-0000-4000-8000-000000000501',jsonb_build_object('dataset','payments','format','csv','rangeFrom','2026-09-15','rangeThrough','2026-09-15','rangeBasis','created_at','timezone','Asia/Kolkata','rowCount',4))$q$,'a prepared event with the fixed shape is recorded');
select throws_ok($q$select holdout_rpe.append_event('report_export.released','82900000-0000-4000-8000-000000000502',jsonb_build_object('sha256','aa','byteCount',10))$q$,'22023',null,'a release without its prepared event is refused');
select throws_ok($q$select holdout_rpe.append_event('report_export.released','82900000-0000-4000-8000-000000000501',jsonb_build_object())$q$,'22023',null,'a release without byte count and digest is refused');
select lives_ok($q$select holdout_rpe.append_event('report_export.released','82900000-0000-4000-8000-000000000501',jsonb_build_object('sha256','aa','byteCount',10))$q$,'the linked release with bytes and digest is recorded');
select throws_ok($q$select holdout_rpe.append_event('report_export.released','82900000-0000-4000-8000-000000000501',jsonb_build_object('sha256','aa','byteCount',10))$q$,'22023',null,'a second release of one export id is refused');
select throws_ok($q$select holdout_rpe.append_event('report_export.opened','82900000-0000-4000-8000-000000000503',jsonb_build_object())$q$,'22023',null,'an unknown audit event is refused by the fixed vocabulary');
select throws_ok($q$select holdout_rpe.append_event('report_export.prepared','82900000-0000-4000-8000-000000000503',jsonb_build_object('dataset','payments','weather','sunny'))$q$,'22023',null,'an unknown detail key is refused as an arbitrary payload');
select throws_ok($q$select holdout_rpe.append_event('report_export.prepared','82900000-0000-4000-8000-000000000503',jsonb_build_object('actor','82900000-0000-4000-8000-000000000016'))$q$,'22023',null,'a caller-supplied actor key is refused — the actor comes from claims');
select is((select actor_user_id from holdout_rpe.report_export_events where export_id='82900000-0000-4000-8000-000000000501' and event='report_export.prepared'),'82900000-0000-4000-8000-000000000011','the recorded actor is the verified claim subject, never an argument');
select is((select count(*) from holdout_rpe.report_export_events where export_id='82900000-0000-4000-8000-000000000503'),0::bigint,'a refused audit call appends nothing');
select throws_ok($q$do $$ begin
 set local role authenticated;
 insert into public.audit_log(tenant_id,action) values ('82900000-0000-4000-8000-000000000001','report_export.forged');
 end $$;$q$,'42501',null,'authenticated holds no direct audit INSERT — the helper is the only path');

select * from finish();
rollback;
