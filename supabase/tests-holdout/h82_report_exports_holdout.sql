-- Independent holdout repair 2026-10-04: the mirror era is over. This suite
-- no longer contains any behavioral stand-in. Section A pins the REAL
-- migration's shape through NULL-safe catalog probes; Sections B…K pin the
-- contract's BEHAVIOR exclusively through the real five-argument public RPC
-- `public.export_report_snapshot(text,date,date,uuid,integer)` (scalar jsonb),
-- the private `app.report_export_preparations` prepared/audit linkage and the
-- real `public.append_report_export_event(text,uuid,jsonb)` release helper,
-- called as authenticated callers under real RLS. There is no fallback: if a
-- real call fails, its assertion fails.
-- Authority: openspec/changes/report-exports/proposal.md,
-- openspec/changes/report-exports/sql-envelope-declaration.md (authoritative),
-- docs/design/v2/rpe-bar.md. No implementation, no visible suite, no other
-- holdout, no evidence or scratchpad file was read. Invoice half DEFERRED:
-- no invoice surface is pinned. CSV byte-level checks (BOM/CRLF/quoting) are
-- transport-layer contract and live in the route suite, not here; this suite
-- pins every envelope field that feeds them.
-- Lawfulness: no protected timestamp is forced null, no constraint is
-- disabled, every fixture row is lawful current evidence. Fixture uuids are
-- prefixed 82900000-. Everything rolls back; nothing commits; nothing was
-- executed against any database by this author.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(179);

-- §A — real-migration shape pins (catalog only).
select ok(to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') is not null,'the real five-argument bounded snapshot operation exists');
select ok(to_regprocedure('public.append_report_export_event(text,uuid,jsonb)') is not null,'the narrow public release audit helper exists');
select ok(to_regclass('app.report_export_preparations') is not null,'the private preparation relation exists');
select ok((select relrowsecurity from pg_class where oid = 'app.report_export_preparations'::regclass),'the preparation relation keeps RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.audit_log'::regclass),'audit_log keeps RLS enabled');
select is((select r.rolname from pg_proc p join pg_roles r on r.oid = p.proowner where p.oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'postgres','the snapshot operation is postgres-owned');
select is((select r.rolname from pg_proc p join pg_roles r on r.oid = p.proowner where p.oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'postgres','the release helper is postgres-owned');
select is((select prosecdef from pg_proc where oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),false,'the snapshot operation is security invoker so caller RLS decides every row');
select is((select prosecdef from pg_proc where oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),true,'the release helper is security definer so it alone elevates');
select is((select provolatile from pg_proc where oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'v','the snapshot operation is volatile: its prepared audit write is not optional');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)')),'','the snapshot operation runs an empty search path');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('public.append_report_export_event(text,uuid,jsonb)')),'','the release helper runs an empty search path');
select ok(has_function_privilege('authenticated','public.export_report_snapshot(text,date,date,uuid,integer)','EXECUTE'),'authenticated holds EXECUTE on the snapshot operation');
select ok(not has_function_privilege('anon','public.export_report_snapshot(text,date,date,uuid,integer)','EXECUTE'),'anon holds no EXECUTE on the snapshot operation');
select ok(not exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.export_report_snapshot(text,date,date,uuid,integer)') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC holds no EXECUTE on the snapshot operation');
select ok(not has_function_privilege('service_role','public.export_report_snapshot(text,date,date,uuid,integer)','EXECUTE'),'service_role holds no EXECUTE on the snapshot operation');
select ok(has_function_privilege('authenticated','public.append_report_export_event(text,uuid,jsonb)','EXECUTE'),'authenticated holds EXECUTE on the release helper');
select ok(not has_function_privilege('anon','public.append_report_export_event(text,uuid,jsonb)','EXECUTE'),'anon holds no EXECUTE on the release helper');
select ok(not exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.append_report_export_event(text,uuid,jsonb)') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC holds no EXECUTE on the release helper');
select ok(not has_function_privilege('service_role','public.append_report_export_event(text,uuid,jsonb)','EXECUTE'),'service_role holds no EXECUTE on the release helper');
select ok(not has_table_privilege('authenticated','public.audit_log','INSERT'),'authenticated cannot INSERT audit rows directly');
select ok(not has_table_privilege('authenticated','public.audit_log','UPDATE'),'authenticated cannot UPDATE audit rows');
select ok(not has_table_privilege('authenticated','public.audit_log','DELETE'),'authenticated cannot DELETE audit rows');
select ok(not has_table_privilege('authenticated','public.audit_log','TRUNCATE'),'authenticated cannot TRUNCATE audit');
select ok(has_column_privilege('authenticated','app.report_export_preparations','dataset','INSERT'),'authenticated may insert the dataset input column');
select ok(has_column_privilege('authenticated','app.report_export_preparations','range_from','INSERT'),'authenticated may insert the range_from input column');
select ok(has_column_privilege('authenticated','app.report_export_preparations','range_through','INSERT'),'authenticated may insert the range_through input column');
select ok(has_column_privilege('authenticated','app.report_export_preparations','branch_id','INSERT'),'authenticated may insert the branch_id input column');
select ok(has_column_privilege('authenticated','app.report_export_preparations','row_cap','INSERT'),'authenticated may insert the row_cap input column');
select ok(not has_column_privilege('authenticated','app.report_export_preparations','export_id','INSERT'),'authenticated may not insert the derived export_id');
select ok(not has_column_privilege('authenticated','app.report_export_preparations','tenant_id','INSERT'),'authenticated may not insert the derived tenant_id');
select ok(not has_column_privilege('authenticated','app.report_export_preparations','data_row_count','INSERT'),'authenticated may not insert the derived data_row_count');
select ok(has_table_privilege('authenticated','app.report_export_preparations','SELECT'),'authenticated holds SELECT on its own preparation rows under RLS');
select ok(not has_table_privilege('authenticated','app.report_export_preparations','UPDATE'),'authenticated holds no UPDATE on preparations');
select ok(not has_table_privilege('authenticated','app.report_export_preparations','DELETE'),'authenticated holds no DELETE on preparations');
select ok(not has_table_privilege('anon','app.report_export_preparations','INSERT'),'anon holds no INSERT on preparations');
select is((select count(*) from information_schema.columns where table_schema='app' and table_name='report_export_preparations'),19::bigint,'the preparation relation carries exactly the five input and fourteen derived columns');
select ok(not exists (select 1 from information_schema.columns where table_schema='app' and table_name='report_export_preparations' and column_name in ('export_id','tenant_id','actor_user_id','actor_role','format','generated_at_utc','snapshot_at_utc','source_cutoff_at_utc','range_basis','timezone','range_start_utc','range_end_exclusive_utc','branch_scope','data_row_count') and is_nullable='YES'),'every derived column is NOT NULL');
select ok(not exists (select 1 from information_schema.columns where table_schema='app' and table_name='report_export_preparations' and column_name in ('export_id','tenant_id','actor_user_id','actor_role','format','generated_at_utc','snapshot_at_utc','source_cutoff_at_utc','range_basis','timezone','range_start_utc','range_end_exclusive_utc','branch_scope','data_row_count') and column_default is not null),'no derived column carries a caller default: only the trigger fills them');
select ok(to_regprocedure('app.derive_report_export_preparation()') is not null,'the derivation trigger function exists');
select ok(to_regprocedure('app.audit_report_export_preparation()') is not null,'the audit trigger function exists');
select is((select provolatile from pg_proc where oid = to_regprocedure('app.derive_report_export_preparation()')),'s','the derivation trigger is stable: it shares the containing statement snapshot');
select is((select provolatile from pg_proc where oid = to_regprocedure('app.audit_report_export_preparation()')),'v','the audit trigger is volatile');
select is((select prosecdef from pg_proc where oid = to_regprocedure('app.derive_report_export_preparation()')),false,'the derivation trigger is an invoker, never a privilege bridge');
select is((select prosecdef from pg_proc where oid = to_regprocedure('app.audit_report_export_preparation()')),true,'the audit trigger is the only definer, confined to audit append');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('app.derive_report_export_preparation()')),'','the derivation trigger runs an empty search path');
select is((select (select case when setting in ('search_path=', 'search_path=""') then '' else substring(setting from length('search_path=')+1) end from unnest(proconfig) setting where setting like 'search_path=%') from pg_proc where oid = to_regprocedure('app.audit_report_export_preparation()')),'','the audit trigger runs an empty search path');
select ok(not has_function_privilege('authenticated','app.derive_report_export_preparation()','EXECUTE'),'authenticated holds no EXECUTE on the derivation trigger');
select ok(not has_function_privilege('authenticated','app.audit_report_export_preparation()','EXECUTE'),'authenticated holds no EXECUTE on the audit trigger');
select ok(exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where t.tgrelid='app.report_export_preparations'::regclass and not t.tgisinternal and t.tgname='report_export_preparations_derive' and n.nspname='app' and p.proname='derive_report_export_preparation' and t.tgtype & 7 = 7),'the derive trigger is a BEFORE INSERT row trigger on the preparation relation');
select ok(exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where t.tgrelid='app.report_export_preparations'::regclass and not t.tgisinternal and t.tgname='report_export_preparations_audit' and n.nspname='app' and p.proname='audit_report_export_preparation' and t.tgtype & 1 = 1 and t.tgtype & 2 = 0 and t.tgtype & 4 = 4),'the audit trigger is an AFTER INSERT row trigger on the preparation relation');
select ok(to_regclass('app.report_export_preparations_tenant_actor_export_idx') is not null,'the tenant/actor/export access index exists under its declared name');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='audit_log' and indexname='audit_log_report_export_event_unique'),'the RPE audit-event unique partial index exists on audit_log');
select ok((select indexdef from pg_indexes where schemaname='public' and tablename='audit_log' and indexname='audit_log_report_export_event_unique') like '%report_export.prepared%','the unique index names the prepared action');
select ok((select indexdef from pg_indexes where schemaname='public' and tablename='audit_log' and indexname='audit_log_report_export_event_unique') like '%report_export.released%','the unique index names the released action');

-- §B fixtures (lawful current rows; all inside the rolled-back transaction).
insert into public.organizations(id,name,gym_code,status) values
 ('82900000-0000-4000-8000-000000000001','H82 Export Gym','H82EXP','active'),
 ('82900000-0000-4000-8000-000000000009','H82 Other Gym','H82OTH','active');
insert into public.branches(id,tenant_id,name,timezone) values
 ('82900000-0000-4000-8000-000000000901','82900000-0000-4000-8000-000000000001','H82 Main',null),
 ('82900000-0000-4000-8000-000000000902','82900000-0000-4000-8000-000000000009','H82 Far',null),
 ('82900000-0000-4000-8000-000000000903','82900000-0000-4000-8000-000000000001','H82 Empty',null);
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
-- Attendance facts. The stored source is a generated vocabulary word; the
-- fixture reads a lawful label from the catalog instead of inventing one.
do $fix$
declare
  v_src text;
  r record;
begin
  select e.enumlabel into v_src
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    join pg_enum e on e.enumtypid = t.oid
   where a.attrelid = 'public.attendance'::regclass and a.attname = 'source'
     and e.enumlabel <> 'front_desk'
   limit 1;
  if v_src is null then
    raise exception 'holdout fixture: no non-front-desk attendance source label exists to model a member check-in lawfully';
  end if;
  for r in select * from (values
    ('82900000-0000-4000-8000-000000000061','82900000-0000-4000-8000-000000000031','82900000-0000-4000-8000-000000000901','2026-09-15T03:00:00+00'::timestamptz,'2026-09-15T04:00:00+00'::timestamptz),
    ('82900000-0000-4000-8000-000000000062','82900000-0000-4000-8000-000000000031','82900000-0000-4000-8000-000000000901','2026-09-15T05:30:00+00'::timestamptz,null::timestamptz),
    ('82900000-0000-4000-8000-000000000063','82900000-0000-4000-8000-000000000032','82900000-0000-4000-8000-000000000901','2026-09-15T06:00:00+00'::timestamptz,null::timestamptz),
    ('82900000-0000-4000-8000-000000000064','82900000-0000-4000-8000-000000000031','82900000-0000-4000-8000-000000000901','2026-09-14T17:00:00+00'::timestamptz,null::timestamptz),
    ('82900000-0000-4000-8000-000000000065','82900000-0000-4000-8000-000000000031','82900000-0000-4000-8000-000000000901','2026-09-15T18:30:00+00'::timestamptz,null::timestamptz)
  ) as t(id,member_id,branch_id,checked_in_at,checked_out_at)
  loop
    if v_src is not null then
      execute format('insert into public.attendance(id,tenant_id,member_id,branch_id,source,checked_in_at,checked_out_at,created_at) values (%L,%L,%L,%L,%L,%L,%L,%L)',
        r.id,'82900000-0000-4000-8000-000000000001',r.member_id,r.branch_id,v_src,r.checked_in_at,r.checked_out_at,r.checked_in_at);
    else
      execute format('insert into public.attendance(id,tenant_id,member_id,branch_id,checked_in_at,checked_out_at,created_at) values (%L,%L,%L,%L,%L,%L,%L)',
        r.id,'82900000-0000-4000-8000-000000000001',r.member_id,r.branch_id,r.checked_in_at,r.checked_out_at,r.checked_in_at);
    end if;
  end loop;
end $fix$;
-- …064 sits before the included lower bound; …065 on the excluded upper
-- bound; both stay outside. In-range: …061, …062, …063.

-- §C — actor revalidation matrix through the REAL RPC: refusal before any
-- read, and no prepared attempt or audit row survives any refusal.
select set_config('request.jwt.claims','',true);
set local role authenticated;
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'no claims gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000017","role":"authenticated","app_role":"member","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a member role claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000013","role":"authenticated","app_role":"trainer","staff_id":"82900000-0000-4000-8000-000000000023","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a trainer staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000012","role":"authenticated","app_role":"front_desk","staff_id":"82900000-0000-4000-8000-000000000022","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a front-desk staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000014","role":"authenticated","app_role":"gym_manager","staff_id":"82900000-0000-4000-8000-000000000024","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a manager staff claim gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000015","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000025","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a deactivated owner staff row gains no export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000007","role":"authenticated","app_role":"super_admin"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a platform super-admin claim gains no gym export authority');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000007","role":"authenticated","app_role":"super_admin","tenant_id":"82900000-0000-4000-8000-000000000001","staff_id":"82900000-0000-4000-8000-000000000021"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'mixed platform and gym identity is refused before any read');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000099","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'a staff id that matches no row is refused');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001","impersonation_session_id":"82900000-0000-4000-8000-000000000098"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100)$q$,'42501',null,'an impersonated owner session gains no export authority');
-- Actor-first ordering: an invalid actor with an also-invalid range reports
-- the actor refusal, never the range (RPE-001).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000017","role":"authenticated","app_role":"member","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$select public.export_report_snapshot('payments','2026-10-01','2026-09-01',null,100)$q$,'42501',null,'actor revalidation precedes semantic parameter validation');
set local role postgres;
select ok((select count(*) from app.report_export_preparations)=0,'every refused export attempt leaves no prepared attempt');
select ok((select count(*) from public.audit_log where record_type='report_export')=0,'every refused export attempt appends no audit event');

-- §D — a valid owner of ANOTHER tenant reads their own (empty) scope through
-- the real RPC: scoping, not erroring; and a zero-row result still prepares.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000016","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000026","tenant_id":"82900000-0000-4000-8000-000000000009"}',true);
set local role authenticated;
drop table if exists _h82_fx;
create temp table _h82_fx as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100) as env;
set local role postgres;
select is((select env->>'data_row_count' from _h82_fx),'0','a valid foreign-tenant owner reads their own empty scope');
select ok(exists(select 1 from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_fx) and tenant_id='82900000-0000-4000-8000-000000000009'),'a zero-row accepted export still inserts its one preparation');

-- §E — branch semantics through the real RPC (owner A).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select lives_ok($q$do $$ declare e1 text; e2 text; begin
 begin perform public.export_report_snapshot('payments','2026-09-15','2026-09-15','82900000-0000-4000-8000-000000000777',100); raise exception 'no refusal'; exception when others then e1 := sqlerrm; end;
 begin perform public.export_report_snapshot('payments','2026-09-15','2026-09-15','82900000-0000-4000-8000-000000000902',100); raise exception 'no refusal'; exception when others then e2 := sqlerrm; end;
 if e1 is null or e1 <> e2 then raise exception 'unknown and foreign branch refusals differ: % vs %', coalesce(e1,'<none>'), coalesce(e2,'<none>'); end if;
 end $$;$q$,'unknown and foreign branch ids share one unavailable refusal');
drop table if exists _h82_br;
create temp table _h82_br as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15','82900000-0000-4000-8000-000000000903',100) as env;
set local role postgres;
select is((select env->>'data_row_count' from _h82_br),'0','a valid same-tenant branch with no associated member exports an honest empty scope');
select is((select env->>'branch_scope' from _h82_br),'82900000-0000-4000-8000-000000000903','the bounded branch export names exactly its branch');

-- §F — zone and range honesty through the real RPC (RPE-003).
select throws_ok($q$do $$ declare original_claims text := current_setting('request.jwt.claims',true); begin
 perform set_config('request.jwt.claims','',true);
 update public.organizations set timezone='Mars/Olympus' where id='82900000-0000-4000-8000-000000000001';
 perform set_config('request.jwt.claims',original_claims,true);
 perform public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100);
 raise exception 'no zone refusal'; end $$;$q$,'22023',null,'an invalid configured zone is an explicit error, never a fallback');
-- Commercial fixture maintenance uses trusted postgres without a subject.
do $$ declare original_claims text := current_setting('request.jwt.claims',true); begin
 perform set_config('request.jwt.claims','',true);
 update public.organizations set timezone='Asia/Kolkata' where id='82900000-0000-4000-8000-000000000001';
 perform set_config('request.jwt.claims',original_claims,true);
end $$;
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
drop table if exists _h82_env;
create temp table _h82_env as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100) as env;
set local role postgres;
select is((select env->>'timezone' from _h82_env),'Asia/Kolkata','the effective gym zone is disclosed on the envelope');
select is((select env->>'data_row_count' from _h82_env),'4','the gym-local inclusive range admits exactly the four in-range payment rows');
select is((select (select count(*) from jsonb_array_elements(env->'rows') r where r->>'payment_id' in ('82900000-0000-4000-8000-000000000042','82900000-0000-4000-8000-000000000041','82900000-0000-4000-8000-000000000043','82900000-0000-4000-8000-000000000045')) from _h82_env),4::bigint,'lower bound included, before-range and upper-bound rows excluded');
select is((select env->'rows'->0->>'payment_id' from _h82_env),'82900000-0000-4000-8000-000000000042','the snapshot opens with the lower-bound payment in (created_at,id) order');
select is((select env->'rows'->1->>'payment_id' from _h82_env),'82900000-0000-4000-8000-000000000041','the second row follows the composite (created_at,id) order');
select is((select env->'rows'->2->>'payment_id' from _h82_env),'82900000-0000-4000-8000-000000000043','the third row follows the composite (created_at,id) order');
select is((select env->'rows'->3->>'payment_id' from _h82_env),'82900000-0000-4000-8000-000000000045','the snapshot closes with the last in-range payment');
select is((select env->>'range_start_utc' from _h82_env),'2026-09-14T18:30:00Z','the range opens at gym-local midnight from as a UTC Z instant');
select is((select env->>'range_end_exclusive_utc' from _h82_env),'2026-09-15T18:30:00Z','the range closes at gym-local midnight after through as a UTC Z instant');
select throws_ok($q$select public.export_report_snapshot('payments','2026-10-01','2026-09-01',null,100)$q$,'22023',null,'a reversed range is refused before any source read');
select throws_ok($q$select public.export_report_snapshot('payments','2026-01-01','2027-01-02',null,100)$q$,'22023',null,'a range beyond the inclusive 366-day maximum is refused');
select throws_ok($q$select public.export_report_snapshot('revenue','2026-09-15','2026-09-15',null,100)$q$,'22023',null,'an unknown dataset is refused by the fixed vocabulary');
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,0)$q$,'22023',null,'a row cap below one is refused');
select throws_ok($q$select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,5001)$q$,'22023',null,'a row cap above the declared maximum is refused');

-- §G — projection honesty on the real payments envelope (RPE-005/006).
select is((select array_agg(k order by k) from (select jsonb_object_keys(env) k from _h82_env) s),
  array['branch_id','branch_scope','data_row_count','dataset','export_id','format','generated_at_utc','has_more','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','returned_row_count','row_cap','rows','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],
  'the success envelope carries exactly the frozen top-level keys, nothing more');
select is((select env->'rows'->0->>'amount_paise' from _h82_env),'9007199254740993','beyond-safe-integer paise crosses as exact canonical text');
select ok((select jsonb_typeof(env->'rows'->0->'amount_paise') from _h82_env) = 'string','money crosses the operation as a string, never a number');
select ok((select jsonb_typeof(env->'rows'->0->'amount_display') from _h82_env) = 'string','the display amount crosses as presentation text, never a parsed-back number');
select is((select env->'rows'->3->>'current_member_name' from _h82_env),null,'an erased member leaves the payment row with a null current name');
select is((select env->'rows'->3->>'member_code' from _h82_env),null,'an erased member leaves the payment row with no member code');
select is((select env->'rows'->1->>'paid_at_utc' from _h82_env),null,'a created attempt keeps its null paid time instead of an inferred instant');
select is((select env->'rows'->1->>'receipt_number' from _h82_env),null,'a created attempt keeps its null receipt instead of an inferred number');
select is((select (select count(*) from jsonb_array_elements(env->'rows') r where r->>'currency'='USD') from _h82_env),1::bigint,'a foreign-currency row is present as its own row, never summed');
select is((select array_agg(k order by k) from (select jsonb_object_keys(env->'rows'->0) k from _h82_env) s),
  array['amount_display','amount_paise','created_at_utc','currency','current_member_name','member_code','member_id','method','paid_at_utc','payment_id','receipt_number','status']::text[],
  'the payments projection carries exactly its fixed keys in the declared set');
select is((select (select count(*) from jsonb_array_elements(env->'rows') r where r->>'status'='created') from _h82_env),1::bigint,'a payment attempt is exported as its recorded status word, not as collected money');
select is((select env->>'source_cutoff_at_utc' from _h82_env),(select env->>'snapshot_at_utc' from _h82_env),'the source cutoff equals the snapshot instant, never a route clock');
select is((select env->>'format' from _h82_env),'csv','the envelope format is the literal csv');
select is((select env->>'dataset' from _h82_env),'payments','the envelope echoes the validated dataset');
select is((select env->>'range_basis' from _h82_env),'created_at','the payments range basis is the payment creation instant');
select ok((select jsonb_typeof(env->'row_cap') from _h82_env)='number' and (select (env->>'row_cap')::int from _h82_env)=100,'the row cap crosses back as the validated JSON integer');
select is((select env->>'has_more' from _h82_env),'false','a bounded export reports has_more false');
select is((select env->>'returned_row_count' from _h82_env),'4','a bounded export returns every matching row');
select is((select env->>'branch_scope' from _h82_env),'all','a null branch export declares the all-branches scope');

-- §H — the members dataset: cohort basis, erasure, exact projection.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
drop table if exists _h82_mem;
create temp table _h82_mem as
select public.export_report_snapshot('members','2026-09-15','2026-09-15',null,100) as env;
set local role postgres;
select is((select env->>'data_row_count' from _h82_mem),'2','the member cohort is a direct joined_on comparison that excludes the erased profile');
select is((select env->'rows'->0->>'full_name' from _h82_mem),'H82 Member','the member cohort carries the current recorded name');
select is((select env->'rows'->0->>'joined_on' from _h82_mem),'2026-09-15','the member range basis is the calendar date itself');
select is((select env->'rows'->1->>'joined_on' from _h82_mem),'2026-09-15','both cohort rows carry calendar joined dates, never converted timestamps');
select is((select array_agg(k order by k) from (select jsonb_object_keys(env->'rows'->0) k from _h82_mem) s),
  array['branch_id','email','full_name','joined_on','member_code','member_id','phone','status']::text[],
  'the members projection carries exactly its fixed keys');
select is((select env->'rows'->0->>'status' from _h82_mem),'active','the member status crosses as the generated vocabulary word');
select is((select env->'rows'->0->>'member_id' from _h82_mem),'82900000-0000-4000-8000-000000000031','the cohort orders by (joined_on,id) with the lower id first');

-- §I — the attendance dataset: stored branch, local timestamp honesty.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
drop table if exists _h82_att;
create temp table _h82_att as
select public.export_report_snapshot('attendance','2026-09-15','2026-09-15',null,100) as env;
set local role postgres;
select is((select env->>'data_row_count' from _h82_att),'3','the attendance range admits exactly the three in-range stored events');
select is((select env->'rows'->0->>'attendance_id' from _h82_att),'82900000-0000-4000-8000-000000000061','attendance orders by (checked_in_at,id) with the earliest event first');
select is((select env->'rows'->0->>'checked_in_local' from _h82_att),'2026-09-15T08:30:00+05:30 [Asia/Kolkata]','the local check-in carries its numeric offset and named zone');
select is((select env->'rows'->1->>'checked_out_at_utc' from _h82_att),null,'an open event keeps its null checkout instead of an inferred instant');
select is((select env->'rows'->2->>'current_member_name' from _h82_att),null,'an erased member leaves the attendance event with a null current name');
select is((select array_agg(k order by k) from (select jsonb_object_keys(env->'rows'->0) k from _h82_att) s),
  array['attendance_id','branch_id','checked_in_at_utc','checked_in_local','checked_out_at_utc','current_member_name','member_code','member_id','offline_recorded_at_utc','replayed_at_utc','source']::text[],
  'the attendance projection carries exactly its fixed keys');
select is((select env->'rows'->0->>'source' from _h82_att),
  (select e.enumlabel::text from pg_attribute a join pg_type t on t.oid=a.atttypid join pg_enum e on e.enumtypid=t.oid where a.attrelid='public.attendance'::regclass and a.attname='source' and e.enumlabel <> 'front_desk' limit 1),
  'the attendance source crosses as its stored generated vocabulary word');
select is((select env->'rows'->0->>'branch_id' from _h82_att),'82900000-0000-4000-8000-000000000901','attendance branch filtering uses the stored event branch uuid');

-- §J — the cap boundary through the real RPC: at cap succeeds in full;
-- one row over returns the refusal envelope and prepares nothing (RPE-004).
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
drop table if exists _h82_cap4;
create temp table _h82_cap4 as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,4) as env;
drop table if exists _h82_cap3;
create temp table _h82_cap3 as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,3) as env;
set local role postgres;
select is((select env->>'returned_row_count' from _h82_cap4),'4','a snapshot at exactly the row cap succeeds in full');
select is((select env->>'has_more' from _h82_cap4),'false','the at-cap export is complete, not truncated');
select is((select env->>'returned_row_count' from _h82_cap4),(select env->>'data_row_count' from _h82_cap4),'a bounded export returns exactly its complete count');
select is((select jsonb_array_length(env->'rows') from _h82_cap3),0,'an over-cap export returns zero rows');
select is((select env->>'returned_row_count' from _h82_cap3),'0','the over-cap envelope reports zero returned rows');
select is((select env->>'has_more' from _h82_cap3),'true','the over-cap envelope honestly reports has_more');
select is((select env->>'data_row_count' from _h82_cap3),'4','the over-cap envelope still carries the exact complete snapshot count');
select is((select (env->>'row_cap')::int from _h82_cap3),3,'the over-cap envelope echoes the requested cap');
select ok(not exists(select 1 from app.report_export_preparations p where p.row_cap=3 and p.tenant_id='82900000-0000-4000-8000-000000000001'),'an over-cap refusal inserts no preparation and appends no audit');
select ok((select (env->>'export_id')::uuid from _h82_env) <> (select (env->>'export_id')::uuid from _h82_cap4),'every fresh attempt derives its own fresh export id');

-- §K — the preparation contract behind a real bounded attempt.
select is((select count(*) from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),1::bigint,'one accepted export inserts exactly one preparation');
select is((select dataset from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'payments','the preparation records the validated dataset');
select is((select range_from::text from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'2026-09-15','the preparation records the validated range open');
select is((select range_through::text from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'2026-09-15','the preparation records the validated range close');
select is((select branch_id from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),null::uuid,'the all-branches preparation stores a null branch');
select is((select row_cap from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),100,'the preparation records the validated row cap');
select is((select tenant_id from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'82900000-0000-4000-8000-000000000001','the preparation derives its tenant from the verified claims');
select is((select actor_user_id from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'82900000-0000-4000-8000-000000000011','the preparation derives its actor from the verified claims');
select is((select actor_role::text from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'gym_owner','the preparation derives its role server-side');
select is((select format from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'csv','the preparation records the format');
select is((select data_row_count::text from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'4','the preparation count equals the envelope snapshot count');
select is((select source_cutoff_at_utc from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),(select snapshot_at_utc from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'the preparation cutoff equals its snapshot instant');
select is((select timezone from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'Asia/Kolkata','the preparation records the validated zone');
select is((select range_basis from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'created_at','the preparation records the range basis');
select is((select branch_scope from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'all','the preparation records the branch scope');
select ok((select generated_at_utc is not null and snapshot_at_utc is not null and range_start_utc is not null and range_end_exclusive_utc is not null from app.report_export_preparations where export_id=(select (env->>'export_id')::uuid from _h82_env)),'every preparation stamp is server-derived and present');
-- Direct table INSERT: only a lawful bounded same-actor attempt is possible.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap)
values ('payments','2026-09-15','2026-09-15',null,77);
set local role postgres;
select ok(exists(select 1 from app.report_export_preparations where tenant_id='82900000-0000-4000-8000-000000000001' and row_cap=77 and export_id is not null),'a lawful direct insert derives its export id server-side');
select is((select data_row_count::text from app.report_export_preparations where tenant_id='82900000-0000-4000-8000-000000000001' and row_cap=77),'4','a direct insert derives its count from the real RLS source scan, never from a caller');
select ok(exists(select 1 from public.audit_log where record_type='report_export' and action='report_export.prepared' and record_id=(select export_id from app.report_export_preparations where tenant_id='82900000-0000-4000-8000-000000000001' and row_cap=77)),'a lawful direct insert appends its prepared audit atomically');
set local role authenticated;
select throws_ok($q$do $$ begin
  insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap,export_id)
  values ('payments','2026-09-15','2026-09-15',null,100,'82900000-0000-4000-8000-0000000007e1');
end $$;$q$,'42501',null,'a caller-supplied derived column is refused');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000012","role":"authenticated","app_role":"front_desk","staff_id":"82900000-0000-4000-8000-000000000022","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select throws_ok($q$do $$ begin
  insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap)
  values ('payments','2026-09-15','2026-09-15',null,100);
end $$;$q$,'42501',null,'a non-owner direct insert is refused by the derivation trigger');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($q$do $$ begin
  insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap)
  values ('payments','2026-09-15','2026-09-15',null,1);
end $$;$q$,'22023',null,'an over-cap direct insert is refused exactly like the RPC path');
select throws_ok($q$do $$ begin
  insert into app.report_export_preparations(dataset,range_from,range_through,branch_id,row_cap)
  values ('revenue','2026-09-15','2026-09-15',null,100);
end $$;$q$,'22023',null,'an unknown dataset is refused on the direct path too');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select is((select count(*) from app.report_export_preparations where tenant_id='82900000-0000-4000-8000-000000000009'),0::bigint,'an owner sees no other tenant preparation rows under RLS');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000016","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000026","tenant_id":"82900000-0000-4000-8000-000000000009"}',true);
set local role authenticated;
select is((select count(*) from app.report_export_preparations where tenant_id='82900000-0000-4000-8000-000000000001'),0::bigint,'the foreign owner sees no first-tenant preparation rows under RLS');
set local role postgres;

-- §L — the release helper: exact shape, lawful linkage, one release forever.
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($q$select public.append_report_export_event('report_export.released','82900000-0000-4000-8000-000000000601',jsonb_build_object('byte_count','123','artifact_sha256',repeat('a',64)))$q$,'42501',null,'a release without its prepared attempt is refused');
drop table if exists _h82_nc;
create temp table _h82_nc as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100) as env;
select lives_ok($q$do $nb$ declare v_refused boolean := false; begin
  begin
    perform public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_nc),jsonb_build_object('byte_count',123,'artifact_sha256',repeat('a',64)));
  exception when others then v_refused := true; end;
  if not v_refused then raise exception 'a byte count of JSON number type (never a canonical decimal string) was accepted';
  end if;
end $nb$;$q$,'a byte count that is not canonical decimal text is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','0409','artifact_sha256',repeat('a',64)))$q$,'22023',null,'a non-canonical byte count is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','8388609','artifact_sha256',repeat('a',64)))$q$,'22023',null,'a byte count above the eight-mebibyte cap is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('a',63)))$q$,'22023',null,'a digest that is not exactly 64 hex characters is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('A',64)))$q$,'22023',null,'an uppercase digest is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('a',64),'note','x'))$q$,'23514',null,'a caller-supplied extra release field is refused');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000016","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000026","tenant_id":"82900000-0000-4000-8000-000000000009"}',true);
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('b',64)))$q$,'42501',null,'a release by another actor is refused');
set local role postgres;
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000015","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000025","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('c',64)))$q$,'42501',null,'a deactivated owner cannot release');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
select lives_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('a',64)))$q$,'the linked release with canonical bytes and digest is recorded');
set local role postgres;
select is((select count(*) from public.audit_log where record_type='report_export' and action='report_export.released' and record_id=(select (env->>'export_id')::uuid from _h82_env)),1::bigint,'the released event is recorded exactly once for its export id');
select is((select array_agg(k order by k) from (select jsonb_object_keys("after") k from public.audit_log where record_type='report_export' and action='report_export.released' and record_id=(select (env->>'export_id')::uuid from _h82_env)) s),
  array['artifact_sha256','branch_id','branch_scope','byte_count','data_row_count','dataset','export_id','format','generated_at_utc','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],
  'the release event copies every prepared key and adds only the byte count and digest');
select is((select "after"->>'byte_count' from public.audit_log where record_type='report_export' and action='report_export.released' and record_id=(select (env->>'export_id')::uuid from _h82_env)),'123','the release records the canonical byte count string');
select is((select "after"->>'artifact_sha256' from public.audit_log where record_type='report_export' and action='report_export.released' and record_id=(select (env->>'export_id')::uuid from _h82_env)),repeat('a',64),'the release records the supplied digest verbatim');
select set_config('request.jwt.claims','{"sub":"82900000-0000-4000-8000-000000000011","role":"authenticated","app_role":"gym_owner","staff_id":"82900000-0000-4000-8000-000000000021","tenant_id":"82900000-0000-4000-8000-000000000001"}',true);
set local role authenticated;
select throws_ok($q$select public.append_report_export_event('report_export.released',(select (env->>'export_id')::uuid from _h82_env)::uuid,jsonb_build_object('byte_count','123','artifact_sha256',repeat('d',64)))$q$,'23514',null,'a second release of one prepared attempt is refused');
select throws_ok($q$select public.append_report_export_event('report_export.released','82900000-0000-4000-8000-000000000602',jsonb_build_object('byte_count','123','artifact_sha256',repeat('a',64)))$q$,'42501',null,'a release of an unknown export id is refused');
drop table if exists _h82_voc;
create temp table _h82_voc as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100) as env;
select lives_ok($q$do $voc$ declare v_refused boolean;
begin
  v_refused := false;
  begin
    perform public.append_report_export_event('report_export.prepared',(select (env->>'export_id')::uuid from _h82_voc),jsonb_build_object());
  exception when others then v_refused := true; end;
  if not v_refused then raise exception 'the public helper accepted the prepared event'; end if;
  v_refused := false;
  begin
    perform public.append_report_export_event('report_export.opened',(select (env->>'export_id')::uuid from _h82_voc),jsonb_build_object());
  exception when others then v_refused := true; end;
  if not v_refused then raise exception 'the public helper accepted an event outside the fixed vocabulary'; end if;
end $voc$;$q$,'the public helper accepts only the released event: prepared and unknown events are refused by the fixed vocabulary on a fresh unreleased attempt');
drop table if exists _h82_rel;
create temp table _h82_rel as
select public.export_report_snapshot('payments','2026-09-15','2026-09-15',null,100) as env;
select lives_ok($q$select public.append_report_export_event('report_export.released',(select env->>'export_id' from _h82_rel)::uuid,jsonb_build_object('byte_count','8388608','artifact_sha256',repeat('e',64)))$q$,'a byte count at the exact eight-mebibyte boundary is accepted');
set local role postgres;
select is((select count(*) from public.audit_log where record_type='report_export' and action='report_export.released'),2::bigint,'every refused release appended nothing: exactly the two lawful releases exist');
select throws_ok($q$do $$ begin
 set local role authenticated;
 insert into public.audit_log(tenant_id,action) values ('82900000-0000-4000-8000-000000000001','report_export.forged');
 end $$;$q$,'42501',null,'authenticated holds no direct audit INSERT — the helpers are the only paths');
select is((select array_agg(k order by k) from (select jsonb_object_keys("after") k from public.audit_log where record_type='report_export' and action='report_export.prepared' and record_id=(select (env->>'export_id')::uuid from _h82_env)) s),
  array['branch_id','branch_scope','data_row_count','dataset','export_id','format','generated_at_utc','range_basis','range_end_exclusive_utc','range_from','range_start_utc','range_through','snapshot_at_utc','source_cutoff_at_utc','timezone']::text[],
  'the prepared event carries exactly its declared keys and no exported personal content');
select is((select count(*) from app.report_export_preparations),(select count(*) from public.audit_log where record_type='report_export' and action='report_export.prepared'),'every prepared attempt carries exactly one prepared audit event');

select * from finish();
rollback;
