-- Independent H27 leads holdout: frozen ADR-111 phase6-leads contract and
-- openspec/changes/phase6-leads/specs/leads/spec.md only. No implementation
-- and no visible suite (apps/web/app/__tests__/, supabase/tests/) were read.
-- Prior holdout files supplied only harness conventions (claim simulation,
-- pg_temp helpers, BEGIN ... ROLLBACK, exact plan), not scenarios.
--
-- Coverage is the silent-failure core the contract names: conversion
-- identity/RLS behavior (who may call public.create_lead / public.update_lead /
-- public.transition_lead / public.convert_lead / public.list_leads), the
-- phone-privacy boundary (cross-gym matches indistinguishable from no match,
-- generic not-found for foreign/unknown targets, no profile in the
-- member-unavailable conflict), finality of the first conversion for every
-- writer, replay of exact durable requests vs GL062 conflicts, ineligible
-- (cancelled/blocked/erased) members never offered or linked, and one-snapshot
-- list counts that cannot disagree with their rows under filters.
--
-- Red against current code for the contracted reason: the RPCs and the
-- evidence/revision columns do not exist yet, so metadata assertions fail and
-- every wrapped call reports a missing-object error that the tolerant
-- refusals explicitly reject. No file-level abort: new columns are read only
-- through to_jsonb(row) and every RPC call is caught by pg_temp.h27_call.
-- True two-connection concurrency is the coordinator's (ADR-030 wraps every
-- file in one transaction); this suite proves the deterministic faces of the
-- race: the lead lock's serialized outcomes, the fresh-key conflicts, and the
-- tenant-phone unique key as the final guard.
begin;
set local role postgres;
select plan(276);

-- ---------------------------------------------------------------- helpers --
create function pg_temp.h27_id(bucket integer, n integer) returns uuid
language sql immutable strict as $$
  select ('270000ff-0027-4000-8000-' || bucket::text || lpad(n::text,11,'0'))::uuid
$$;
create function pg_temp.h27_call(statement text) returns jsonb language plpgsql as $$
declare result jsonb; detail text; message text;
begin
  execute 'select to_jsonb(r) from ('||statement||') r' into strict result;
  return coalesce(result,'null'::jsonb) || jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail = pg_exception_detail, message = pg_exception_message;
  return jsonb_build_object('state',sqlstate,'message',message,'detail',detail);
end
$$;
create function pg_temp.h27_exec(statement text) returns jsonb language plpgsql as $$
declare detail text;
begin
  execute statement;
  return jsonb_build_object('state','00000');
exception when others then
  get stacked diagnostics detail = pg_exception_detail;
  return jsonb_build_object('state',sqlstate,'detail',detail);
end
$$;
create function pg_temp.h27_attempt(statement text) returns text language plpgsql as $$
declare affected bigint;
begin
  execute statement;
  get diagnostics affected = row_count;
  return 'rows=' || affected;
exception when others then
  return 'error=' || sqlstate;
end
$$;
create function pg_temp.h27_claim(role_name text default 'gym_owner',
  tenant integer default 1, staff integer default 1, member integer default null,
  sub integer default null, impersonate integer default null)
returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
    'role','authenticated','sub',pg_temp.h27_id(9,coalesce(sub,staff,member,1)),
    'app_role',role_name,'tenant_id',pg_temp.h27_id(1,tenant),
    'staff_id',pg_temp.h27_id(3,staff),'member_id',pg_temp.h27_id(5,member),
    'impersonation_session_id',pg_temp.h27_id(6,impersonate)))::text,true)
$$;
create function pg_temp.h27_missing(p_state text) returns boolean language sql immutable as $$
  select coalesce(p_state,'') in ('42883','42P01','42703','42601','42704')
$$;
create function pg_temp.h27_stale(p_outcome jsonb) returns boolean language sql immutable as $$
  select not pg_temp.h27_missing(p_outcome->>'state')
    and coalesce(p_outcome->>'state','') not in ('00000','23505','P0002','GL062')
$$;
create function pg_temp.h27_unavailable(p_outcome jsonb) returns boolean language sql immutable as $$
  select not pg_temp.h27_missing(p_outcome->>'state')
    and coalesce(p_outcome->>'state','') not in ('00000','23505','P0002','GL061','GL062')
$$;
create function pg_temp.h27_mentions(p_outcome jsonb, needle text) returns boolean language sql immutable as $$
  select coalesce(position(needle in p_outcome::text),0) > 0
$$;
create function pg_temp.h27_lead(p_lead integer) returns jsonb language sql as $$
  select to_jsonb(l) from public.leads l where l.id = pg_temp.h27_id(7,p_lead)
$$;
create function pg_temp.h27_rev(p_lead integer) returns text language sql as $$
  select to_jsonb(l)->>'revision' from public.leads l where l.id = pg_temp.h27_id(7,p_lead)
$$;
create function pg_temp.h27_create(p_key integer, p_branch integer, p_name text, p_phone text,
  p_email text, p_source text, p_assignee integer, p_notes text) returns jsonb language plpgsql as $$
begin
  return pg_temp.h27_call(format(
    'select public.create_lead(%L,%L,%L,%L,%s,%L,%s,%s) as value',
    pg_temp.h27_id(8,p_key), pg_temp.h27_id(2,p_branch), p_name, p_phone,
    coalesce(quote_literal(p_email),'null'), p_source,
    coalesce(quote_literal(pg_temp.h27_id(3,p_assignee)::text),'null'),
    coalesce(quote_literal(p_notes),'null')));
end
$$;
create function pg_temp.h27_update(p_lead integer, p_branch integer, p_name text, p_phone text,
  p_email text, p_source text, p_assignee integer, p_notes text,
  p_revision text default null) returns jsonb language plpgsql as $$
begin
  return pg_temp.h27_call(format(
    'select public.update_lead(%L,%s,%L,%L,%s,%L,%s,%s) as value',
    pg_temp.h27_id(7,p_lead), coalesce(quote_literal(coalesce(p_revision,pg_temp.h27_rev(p_lead))),'null'),
    pg_temp.h27_id(2,p_branch), p_name, p_phone,
    coalesce(quote_literal(p_email),'null'), p_source,
    coalesce(quote_literal(pg_temp.h27_id(3,p_assignee)::text),'null'),
    coalesce(quote_literal(p_notes),'null')));
end
$$;
create function pg_temp.h27_transition(p_lead integer, p_stage text,
  p_trial_at timestamptz default null, p_reason text default null,
  p_revision text default null) returns jsonb language plpgsql as $$
begin
  return pg_temp.h27_call(format(
    'select public.transition_lead(%L,%s,%L,%s,%s) as value',
    pg_temp.h27_id(7,p_lead), coalesce(quote_literal(coalesce(p_revision,pg_temp.h27_rev(p_lead))),'null'),
    p_stage, coalesce(quote_literal(p_trial_at::text),'null'),
    coalesce(quote_literal(p_reason),'null')));
end
$$;
create function pg_temp.h27_convert(p_lead integer, p_key integer, p_mode text,
  p_member integer default null, p_revision text default null) returns jsonb language plpgsql as $$
begin
  return pg_temp.h27_call(format(
    'select public.convert_lead(%L,%L,%s,%L,%s) as value',
    pg_temp.h27_id(7,p_lead), pg_temp.h27_id(8,p_key),
    coalesce(quote_literal(coalesce(p_revision,pg_temp.h27_rev(p_lead))),'null'),
    p_mode, coalesce(quote_literal(pg_temp.h27_id(5,p_member)::text),'null')));
end
$$;
create function pg_temp.h27_list(p_stage text default null, p_source text default null,
  p_assignee text default null, p_branch integer default null, p_query text default null,
  p_after text default null, p_after_id text default null, p_limit integer default null)
returns jsonb language plpgsql as $$
begin
  return pg_temp.h27_call(format(
    'select public.list_leads(%s,%s,%s,%s,%s,%s,%s,%s) as value',
    coalesce(quote_literal(p_stage),'null'), coalesce(quote_literal(p_source),'null'),
    coalesce(quote_literal(p_assignee),'null'),
    coalesce(quote_literal(pg_temp.h27_id(2,p_branch)::text),'null'),
    coalesce(quote_literal(p_query),'null'), coalesce(quote_literal(p_after),'null'),
    coalesce(quote_literal(p_after_id),'null'), coalesce(quote_literal(p_limit::text),'null')));
end
$$;
create temp table h27_seen(name text primary key, value jsonb);
grant all on h27_seen to public;
do $grant$
begin
  execute format('grant usage on schema %I to public', pg_my_temp_schema()::regnamespace);
end
$grant$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------- A. frozen metadata ----
select has_column('public','leads','revision','H27 database-owned revision uuid exists');
select col_type_is('public','leads','revision','uuid','H27 revision is a UUID');
select col_not_null('public','leads','revision','H27 every current lead carries a revision');
select col_is_null('public','leads',column_name,'H27 historical '||column_name||' may be unknown')
from unnest(array['created_by_staff_id','creation_request_key','creation_request_facts',
  'conversion_request_key','conversion_request_facts']) column_name;
select has_column('public','leads','created_by_staff_id','H27 creation actor column exists');
select col_type_is('public','leads','created_by_staff_id','uuid','H27 creation actor is a UUID');
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.leads'::regclass
  and c.conname='leads_tenant_id_created_by_staff_id_fkey'
  and c.contype='f' and c.confrelid='public.staff'::regclass
  and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.conrelid and attname='created_by_staff_id')]
  and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='tenant_id'),
    (select attnum from pg_attribute where attrelid=c.confrelid and attname='id')])),
  'H27 creation actor is a tenant-composite staff reference');
select ok(to_regclass('public.leads_created_by_staff_id_idx') is not null,
  'H27 creation actor is indexed');
select ok(exists(select 1 from pg_index i
  where i.indrelid='public.leads'::regclass and i.indisunique
  and pg_get_indexdef(i.indexrelid,1,true)='tenant_id'
  and pg_get_indexdef(i.indexrelid,2,true)=key_column
  and pg_get_expr(i.indpred,i.indrelid)='('||key_column||' IS NOT NULL)'),
  'H27 unique tenant-scoped '||key_column)
from unnest(array['creation_request_key','conversion_request_key']) key_column;
select ok(coalesce((select not p.prosecdef and p.provolatile='v' and 'search_path=""'=any(p.proconfig)
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p where p.oid=to_regprocedure(signature)),false),
  'H27 invoker mutation boundary: '||signature)
from unnest(array[
  'public.create_lead(uuid,uuid,text,text,text,public.lead_source,uuid,text)',
  'public.update_lead(uuid,uuid,uuid,text,text,text,public.lead_source,uuid,text)',
  'public.transition_lead(uuid,uuid,public.lead_stage,timestamptz,text)',
  'public.convert_lead(uuid,uuid,uuid,text,uuid)']) signature;
select ok(coalesce((select not p.prosecdef and p.provolatile='s' and 'search_path=""'=any(p.proconfig)
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE')
  from pg_proc p where p.oid=to_regprocedure('public.list_leads(public.lead_stage,public.lead_source,text,uuid,text,timestamptz,uuid,integer)')),false),
  'H27 list is a stable invoker read under RLS, granted only to authenticated');
select ok(exists(select 1 from pg_constraint c where c.conrelid='public.members'::regclass
  and c.conname='members_tenant_id_phone_key' and c.contype='u'),
  'H27 the tenant-phone unique key remains the final race guard');

-- --------------------------------------------------------- B. fixtures ----
insert into public.organizations(id,name,gym_code,timezone,currency,status) values
  (pg_temp.h27_id(1,1),'H27 Gym A','H27GYA','Asia/Kolkata','INR','active'),
  (pg_temp.h27_id(1,2),'H27 Gym B','H27GYB','Pacific/Kiritimati','INR','active');
insert into public.branches(id,tenant_id,name,is_default) values
  (pg_temp.h27_id(2,1),pg_temp.h27_id(1,1),'H27 Branch One',true),
  (pg_temp.h27_id(2,2),pg_temp.h27_id(1,1),'H27 Branch Two',false),
  (pg_temp.h27_id(2,3),pg_temp.h27_id(1,2),'H27 Branch Foreign',true);
insert into auth.users(id) select pg_temp.h27_id(9,n) from generate_series(1,8) n;
insert into public.platform_users(user_id,role,full_name,email,is_active) values
  (pg_temp.h27_id(9,7),'super_admin','H27 Platform Super','h27super@example.test',true),
  (pg_temp.h27_id(9,8),'platform_support','H27 Platform Support','h27support@example.test',true);
insert into public.staff(id,tenant_id,branch_id,user_id,role,full_name,is_active) values
  (pg_temp.h27_id(3,1),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(9,1),'gym_owner','H27 Owner',true),
  (pg_temp.h27_id(3,2),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(9,2),'gym_manager','H27 Manager',true),
  (pg_temp.h27_id(3,3),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(9,3),'front_desk','H27 Desk',true),
  (pg_temp.h27_id(3,4),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(9,4),'trainer','H27 Trainer',true),
  (pg_temp.h27_id(3,5),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(9,5),'front_desk','H27 Inactive Desk',false),
  (pg_temp.h27_id(3,6),pg_temp.h27_id(1,2),pg_temp.h27_id(2,3),pg_temp.h27_id(9,6),'gym_owner','H27 Owner B',true);
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,joined_on,erased_at) values
  (pg_temp.h27_id(5,1),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Active','+919271000001','active','2026-09-01',null),
  (pg_temp.h27_id(5,2),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Cancelled','+919271000002','cancelled','2026-09-01',null),
  (pg_temp.h27_id(5,3),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Blocked','+919271000003','blocked','2026-09-01',null),
  (pg_temp.h27_id(5,4),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Erased','+919271000004','active','2026-09-01',transaction_timestamp()),
  (pg_temp.h27_id(5,5),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Paused','+919271000005','paused','2026-09-01',null),
  (pg_temp.h27_id(5,6),pg_temp.h27_id(1,2),pg_temp.h27_id(2,3),'H27 Member Foreign','+919271000006','active','2026-09-01',null),
  (pg_temp.h27_id(5,7),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),'H27 Member Expired','+919271000007','expired','2026-09-01',null);
insert into public.impersonation_sessions(id,tenant_id,actor_user_id,reason,expires_at) values
  (pg_temp.h27_id(6,1),pg_temp.h27_id(1,1),pg_temp.h27_id(9,7),'H27 independent preview',transaction_timestamp()+interval '45 minutes');

select pg_temp.h27_claim();
set local role authenticated;

-- ------------------------------------------- C. creation via the RPC ----
insert into h27_seen values ('L1-create', pg_temp.h27_create(1, 1, 'H27 Lead One', '+919272000001', null, 'walk_in', null, null));
select is((select value->>'state' from h27_seen where name='L1-create'),'00000','H27 front office creates an enquiry');
select is((select array_agg(k order by k) from jsonb_object_keys(
    (select value->'value' from h27_seen where name='L1-create')) k),
  array['leadId','replayed','revision'],'H27 the creation result is exactly the frozen envelope');
select is((select value->'value'->>'leadId' from h27_seen where name='L1-create'),pg_temp.h27_id(7,1)::text,
  'H27 the creation result names the new lead');
select is((select pg_temp.h27_lead(1)->>'stage'),'new','H27 a lead is created only at new');
select matches((select pg_temp.h27_rev(1)),'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$','H27 creation stamps a database-owned revision uuid');
select is((select pg_temp.h27_lead(1)->>'created_by_staff_id'),pg_temp.h27_id(3,1)::text,'H27 creation stamps the real acting staff id');
select is((select pg_temp.h27_lead(1)->>'creation_request_key'),pg_temp.h27_id(8,1)::text,'H27 creation stores the durable request key');
select ok((select pg_temp.h27_lead(1)->'creation_request_facts') is not null,'H27 a key and its facts are stored together');
select is((select jsonb_build_array(pg_temp.h27_lead(1)->'trial_at',pg_temp.h27_lead(1)->'converted_member_id',
  pg_temp.h27_lead(1)->'converted_at',pg_temp.h27_lead(1)->'lost_reason')),
  jsonb_build_array(to_jsonb(null::timestamptz),to_jsonb(null::uuid),to_jsonb(null::timestamptz),to_jsonb(null::text)),
  'H27 trial, conversion and loss fields start null');
insert into h27_seen values ('L2-create', pg_temp.h27_create(2, 1, 'H27 Lead Two', '+919271000001', null, 'walk_in', 2, null));
select is((select value->>'state' from h27_seen where name='L2-create'),'00000','H27 assigned enquiry created');
select is((select to_jsonb(l)->>'assigned_to_staff_id' from public.leads l where l.id=pg_temp.h27_id(7,2)),pg_temp.h27_id(3,2)::text,'H27 same-tenant active manager may be assigned at creation');
select is((select count(*) from (values
  (3, 1,'H27 Lead Three','+919271000002',null::text,'walk_in',null::int,null::text),
  (4, 1,'H27 Lead Four','+919271000006',null,'walk_in',null,null),
  (5, 1,'H27 Lead Five','+919271000003',null,'referral',null,null),
  (6, 1,'H27 Lead Six','+919271000004',null,'google',null,null),
  (7, 1,'H27 Lead Seven','+919271000005',null,'referral',null,null),
  (8, 1,'H27 Lead Eight','+919272000008',null,'instagram',null,null),
  (9, 1,'H27 Lead Nine','+919272000009',null,'phone',null,null),
  (10,1,'H27 Lead Ten','+919272000010','h27ten@example.test','walk_in',null,'H27 creation notes'),
  (11,1,'H27 Lead Eleven','+919271000002',null,'walk_in',null,null),
  (12,1,'H27 Lead Twelve','+919272000012',null,'website',null,null),
  (15,1,'H27 Lead Fifteen','+919271000007',null,'referral',null,null)
) v(key,branch,name,phone,email,source,assignee,notes)
  where pg_temp.h27_create(v.key,v.branch,v.name,v.phone,v.email,v.source,v.assignee,v.notes)->>'state'='00000'),
  11,'H27 scenario enquiries created through the keyed RPC');
select is((select count(*) from public.leads l where l.stage='new' and l.id in
  (select pg_temp.h27_id(7,n) from unnest(array[3,4,5,6,7,8,9,10,11,12,15]) n)),11,
  'H27 every scenario enquiry rests at new');
select is((select count(*) from (values
  (20,2,'H27 Lead Twenty','+919272000020',null::text,'referral',2,null::text),
  (21,1,'H27 Lead Twentyone','+919272000021',null,'instagram',null,null),
  (22,1,'H27 Lead Twentytwo','+919272000022',null,'walk_in',3,null),
  (23,1,'H27 Lead Twentythree','+919272000023',null,'google',2,null),
  (24,2,'H27 Lead Twentyfour','+919272000024',null,'walk_in',null,null),
  (25,1,'H27 Lead Twentyfive','+919272000025',null,'phone',null,null)
) v(key,branch,name,phone,email,source,assignee,notes)
  where pg_temp.h27_create(v.key,v.branch,v.name,v.phone,v.email,v.source,v.assignee,v.notes)->>'state'='00000'),
  6,'H27 list fixtures created through the keyed RPC');
select is((select count(*) from public.leads l where l.stage='new' and l.id in
  (select pg_temp.h27_id(7,n) from unnest(array[20,21,22,23,24,25]) n)),6,
  'H27 every list fixture rests at new');
select is(pg_temp.h27_create(31,999,'H27 Lead Thirtyone','+919272000031',null,'walk_in',null,null)->>'state',
  'P0002','H27 unknown branch is a generic not-found');
select is(pg_temp.h27_create(32,3,'H27 Lead Thirtytwo','+919272000032',null,'walk_in',null,null)->>'state',
  'P0002','H27 cross-gym branch is the same generic not-found');
select is(pg_temp.h27_create(31,999,'H27 Lead Thirtyone','+919272000031',null,'walk_in',null,null)->>'state',
  pg_temp.h27_create(32,3,'H27 Lead Thirtytwo','+919272000032',null,'walk_in',null,null)->>'state'),
  'H27 unknown and cross-gym branch UUIDs are indistinguishable');
select is(pg_temp.h27_create(33,1,'H27 Lead Thirtythree','+919272000033',null,'walk_in',999,null)->>'state',
  'P0002','H27 unknown assignee is a generic not-found');
select is(pg_temp.h27_create(34,1,'H27 Lead Thirtyfour','+919272000034',null,'walk_in',6,null)->>'state',
  'P0002','H27 cross-gym assignee is the same generic not-found');
select pg_temp.h27_claim('gym_owner',2,6);
insert into h27_seen values ('L14-create', pg_temp.h27_create(10, 3, 'H27 Lead Fourteen', '+919273000014', null, 'walk_in', null, null));
select is((select value->>'state' from h27_seen where name='L14-create'),'00000','H27 another gym reuses the same request key independently');
select is((select value->'value'->>'replayed' from h27_seen where name='L14-create'),'false','H27 the foreign same-key creation is not a replay');
insert into h27_seen values ('L14-replay', pg_temp.h27_create(10, 3, 'H27 Lead Fourteen', '+919273000014', null, 'walk_in', null, null));
select is((select value->'value'->>'replayed' from h27_seen where name='L14-replay'),'true','H27 the foreign gym replays its own key');
select pg_temp.h27_claim();
insert into h27_seen values ('L30-refused', pg_temp.h27_create(30,999,'H27 Lead Thirty','+919272000030',null,'walk_in',null,null));
select is((select value->>'state' from h27_seen where name='L30-refused'),'P0002','H27 a refused creation fails before its key is consumed');
insert into h27_seen values ('L30-create', pg_temp.h27_create(30, 1, 'H27 Lead Thirty', '+919272000030', null, 'walk_in', null, null));
select is((select value->>'state' from h27_seen where name='L30-create'),'00000','H27 a refused request key stays reusable');
select is((select value->'value'->>'replayed' from h27_seen where name='L30-create'),'false','H27 the retried creation is a fresh write, not a replay');
insert into h27_seen values ('L16-create', pg_temp.h27_create(16, 1, '  H27  Lead Sixteen  ', '+919272000016', null, 'walk_in', null, null));
select is((select value->>'state' from h27_seen where name='L16-create'),'00000','H27 creation accepts outer-padded input');

-- ---------------------- D. creation replay and GL062 fact conflicts ----
insert into h27_seen values ('L10-rev0', jsonb_build_object('rev', pg_temp.h27_rev(10)));
select is(pg_temp.h27_create(10, 1, changed, '+919272000010', 'h27ten@example.test','walk_in',null,'H27 creation notes')->>'state',
  'GL062','H27 reused creation key with changed '||label)
from (values('name','H27 Lead Ten Renamed'),('phone','+919272000011')) v(label,changed);
select is(pg_temp.h27_create(10, branch, 'H27 Lead Ten','+919272000010','h27ten@example.test','walk_in',null,'H27 creation notes')->>'state',
  'GL062','H27 reused creation key with changed branch')
from (values(2)) v(branch);
select is(pg_temp.h27_create(10, 1, 'H27 Lead Ten','+919272000010','h27ten@example.test',source,null,'H27 creation notes')->>'state',
  'GL062','H27 reused creation key with changed source')
from (values('referral')) v(source);
select is(pg_temp.h27_create(10, 1, 'H27 Lead Ten','+919272000010','h27ten@example.test','walk_in',assignee,'H27 creation notes')->>'state',
  'GL062','H27 reused creation key with changed assignee')
from (values(3)) v(assignee);
select is(pg_temp.h27_create(10, 1, 'H27 Lead Ten','+919272000010',email,'walk_in',null,'H27 creation notes')->>'state',
  'GL062','H27 reused creation key with changed email')
from (values('other@example.test')) v(email);
select is(pg_temp.h27_create(10, 1, 'H27 Lead Ten','+919272000010','h27ten@example.test','walk_in',null,notes)->>'state',
  'GL062','H27 reused creation key with changed notes')
from (values('H27 changed notes')) v(notes);
select pg_temp.h27_claim('gym_manager',1,2);
select is(pg_temp.h27_create(10, 1, 'H27 Lead Ten','+919272000010','h27ten@example.test','walk_in',null,'H27 creation notes')->>'state',
  'GL062','H27 another authorized actor cannot replay someone else''s request key');
select pg_temp.h27_claim();
insert into h27_seen values ('L10-rename', pg_temp.h27_update(10, 1, 'H27 Lead Ten Renamed', '+919272000010', 'h27ten@example.test', 'walk_in', null, 'H27 creation notes'));
select is((select value->>'state' from h27_seen where name='L10-rename'),'00000','H27 same-stage detail edit accepted');
select isnt((select value->'value'->'lead'->>'revision' from h27_seen where name='L10-rename'),
  (select value->>'rev' from h27_seen where name='L10-rev0'),'H27 accepted material change rotates the revision');
insert into h27_seen values ('L10-replay', pg_temp.h27_create(10, 1, 'H27 Lead Ten', '+919272000010', 'h27ten@example.test', 'walk_in', null, 'H27 creation notes'));
select is((select value->'value'->>'replayed' from h27_seen where name='L10-replay'),'true','H27 exact creation retry replays the original lead');
select is((select value->'value'->>'leadId' from h27_seen where name='L10-replay'),pg_temp.h27_id(7,10)::text,
  'H27 creation replay returns the original stable lead id');
select is((select value->'value'->>'revision' from h27_seen where name='L10-replay'),pg_temp.h27_rev(10),
  'H27 creation replay returns the current revision, never an old snapshot');

-- --------------------- E. direct inserts need complete evidence ---------
select isnt(pg_temp.h27_attempt(format(
  'insert into public.leads (id,tenant_id,branch_id,full_name,phone,source) values (%L,%L,%L,''H27 Direct Fifty'',''+919272000050'',''walk_in'')',
  pg_temp.h27_id(7,50),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1))),'rows=1',
  'H27 a direct insert without creation evidence is refused');
select is((select count(*) from public.leads l where l.phone='+919272000050'),0,'H27 the evidenceless row does not exist');
select isnt(pg_temp.h27_attempt(format(
  'insert into public.leads (id,tenant_id,branch_id,full_name,phone,source,created_by_staff_id,creation_request_key,creation_request_facts) values (%L,%L,%L,''H27 Direct Fiftyone'',''+919272000051'',''walk_in'',%L,%L,''{}''::jsonb)',
  pg_temp.h27_id(7,51),pg_temp.h27_id(1,1),pg_temp.h27_id(2,1),pg_temp.h27_id(3,2),pg_temp.h27_id(8,51))),'rows=1',
  'H27 a direct insert naming a different evidence actor is refused');
select is((select count(*) from public.leads l where l.phone='+919272000051'),0,'H27 the wrong-actor row does not exist');

-- --------------------------------------------- F. legal stage pipeline ----
insert into h27_seen values ('L1-rev-pre-contact', jsonb_build_object('rev', pg_temp.h27_rev(1)));
insert into h27_seen values ('L1-contacted', pg_temp.h27_transition(1,'contacted'));
select is((select value->>'state' from h27_seen where name='L1-contacted'),'00000','H27 new moves to contacted');
select isnt(pg_temp.h27_rev(1),(select value->>'rev' from h27_seen where name='L1-rev-pre-contact'),'H27 a stage change rotates the revision');
insert into h27_seen values ('L1-scheduled', pg_temp.h27_transition(1,'trial_scheduled', transaction_timestamp()+interval '2 days'));
select is((select value->>'state' from h27_seen where name='L1-scheduled'),'00000','H27 trial_scheduled accepts an instant');
select is((select (pg_temp.h27_lead(1)->>'trial_at')::timestamptz),transaction_timestamp()+interval '2 days','H27 trial_at is stored exactly');
insert into h27_seen values ('L1-done', pg_temp.h27_transition(1,'trial_done'));
select is((select value->>'state' from h27_seen where name='L1-done'),'00000','H27 trial_done completes the legal path');
select is((select count(*) from (values (2),(3),(4),(5),(6),(7),(8),(11),(15)) v(lead)
  where pg_temp.h27_transition(v.lead,'contacted')->>'state'='00000'),9,
  'H27 conversion fixtures move to contacted');
select is((select count(*) from (values (2),(3),(4),(5),(6),(7),(8),(11),(15)) v(lead)
  where pg_temp.h27_transition(v.lead,'trial_scheduled', transaction_timestamp()+interval '2 days')->>'state'='00000'),9,
  'H27 conversion fixtures schedule their trial');
select is((select count(*) from (values (2),(3),(4),(5),(6),(7),(8),(11),(15)) v(lead)
  where pg_temp.h27_transition(v.lead,'trial_done')->>'state'='00000'),9,
  'H27 conversion fixtures reach trial_done');
select is((select count(*) from public.leads l where l.stage='trial_done' and l.id in
  (select pg_temp.h27_id(7,n) from unnest(array[2,3,4,5,6,7,8,11,15]) n)),9,
  'H27 all nine conversion fixtures rest at trial_done');
select is((select count(*) from (values (21),(22),(25)) v(lead)
  where pg_temp.h27_transition(v.lead,'contacted')->>'state'='00000'),3,
  'H27 list fixtures move to contacted');
select is((select count(*) from (values (21),(22)) v(lead)
  where pg_temp.h27_transition(v.lead,'trial_scheduled', transaction_timestamp()+interval '2 days')->>'state'='00000'),2,
  'H27 list fixtures schedule their trial');
select is(pg_temp.h27_transition(22,'trial_done')->>'state','00000','H27 the trial-done list fixture completes its path');
select is(pg_temp.h27_transition(23,'lost',null,'H27 list lost')->>'state','00000','H27 the lost list fixture retains its reason');

-- ------------------------- G. graph, CAS and loss discipline (L9) -------
select is(pg_temp.h27_transition(9,'contacted')->>'state','00000','H27 L9 moves to contacted');
select is(pg_temp.h27_transition(9,'contacted')->>'state','GL059','H27 a self-transition is refused');
select is(pg_temp.h27_transition(9,'trial_done')->>'state','GL059','H27 a skipped transition is refused');
select is(pg_temp.h27_transition(9,'trial_scheduled', transaction_timestamp()+interval '3 days')->>'state','00000','H27 L9 schedules its trial');
select is((select (pg_temp.h27_lead(9)->>'trial_at')::timestamptz),transaction_timestamp()+interval '3 days','H27 L9 trial_at stored');
select is(pg_temp.h27_transition(9,'contacted')->>'state','GL059','H27 a reverse transition is refused');
select is(pg_temp.h27_transition(9,'trial_done')->>'state','00000','H27 L9 reaches trial_done');
insert into h27_seen values ('L9-stale-convert', pg_temp.h27_convert(9,90,'create',null,pg_temp.h27_id(8,900)::text));
select ok(pg_temp.h27_stale((select value from h27_seen where name='L9-stale-convert')),
  'H27 a visible lead with a wrong expectedRevision is a conflict, not a crash and not a not-found');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000009'),0,
  'H27 the refused conversion creates no member');
select is(pg_temp.h27_transition(9,'lost',null,'   ')->>'state','GL060','H27 lost requires a trimmed nonempty reason');
insert into h27_seen values ('L9-lost', pg_temp.h27_transition(9,'lost',null,'H27 lost reason'));
select is((select value->>'state' from h27_seen where name='L9-lost'),'00000','H27 a legal loss is accepted');
select is((select to_jsonb(l)->>'lost_reason' from public.leads l where l.id=pg_temp.h27_id(7,9)),'H27 lost reason','H27 the loss reason is retained');
select is(pg_temp.h27_transition(9,'contacted')->>'state','GL059','H27 a lost lead cannot be reopened');
select is(pg_temp.h27_update(9, 1, 'H27 Lead Nine', '+919272000009', null, 'phone', null, null)->>'state','GL059',
  'H27 a terminal row''s business facts cannot change through update_details');
select isnt(pg_temp.h27_attempt(format('update public.leads set lost_reason=''rewritten'' where id=%L',pg_temp.h27_id(7,9))),
  'rows=1','H27 a terminal row''s loss reason is frozen even for a direct writer');
select is((select to_jsonb(l)->>'lost_reason' from public.leads l where l.id=pg_temp.h27_id(7,9)),'H27 lost reason',
  'H27 the refused rewrite changed nothing');

-- ------------------------------ H. direct-write graph discipline (L12) --
select is(pg_temp.h27_attempt(format('update public.leads set stage=''trial_done'' where id=%L',pg_temp.h27_id(7,12))),
  'error=GL059','H27 a direct write cannot skip stages');
select is(pg_temp.h27_transition(12,'contacted', transaction_timestamp()+interval '1 day')->>'state','GL060',
  'H27 earlier stages forbid trial_at');
select is(pg_temp.h27_transition(12,'contacted')->>'state','00000','H27 L12 moves to contacted');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''trial_scheduled'' where id=%L',pg_temp.h27_id(7,12))),
  'error=GL060','H27 a direct write cannot schedule without trial_at');
insert into h27_seen values ('L12-rev0', jsonb_build_object('rev', pg_temp.h27_rev(12)));
select is(pg_temp.h27_attempt(format('update public.leads set stage=''trial_scheduled'', trial_at=%L where id=%L',
  transaction_timestamp()+interval '2 days',pg_temp.h27_id(7,12))),'rows=1',
  'H27 a legal direct stage change with trial_at is accepted');
select isnt(pg_temp.h27_rev(12),(select value->>'rev' from h27_seen where name='L12-rev0'),
  'H27 the accepted direct change rotates the revision');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''lost'', lost_reason=''H27 direct lost'' where id=%L',
  pg_temp.h27_id(7,12))),'rows=1','H27 a legal direct loss with a reason is accepted');
select is((select jsonb_build_array(to_jsonb(l)->>'stage',to_jsonb(l)->>'lost_reason') from public.leads l where l.id=pg_temp.h27_id(7,12)),
  jsonb_build_array('lost','H27 direct lost'),'H27 the direct loss stored its facts');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''contacted'' where id=%L',pg_temp.h27_id(7,12))),
  'error=GL059','H27 a direct writer cannot reopen a terminal row');
select isnt(pg_temp.h27_attempt(format('update public.leads set lost_reason='''' where id=%L',pg_temp.h27_id(7,12))),
  'rows=1','H27 a direct writer cannot blank a loss reason');
select is((select to_jsonb(l)->>'lost_reason' from public.leads l where l.id=pg_temp.h27_id(7,12)),'H27 direct lost',
  'H27 the loss reason survived the refused blanking');
select is(pg_temp.h27_attempt(format('update public.leads set lost_reason=''nope'' where id=%L',pg_temp.h27_id(7,8))),
  'error=GL060','H27 every non-lost stage forbids a loss reason');

-- ------------------------------ I. assignee facts on update_lead (L8) ---
select is(pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 4, null)->>'state','GL060',
  'H27 a trainer cannot be assigned a lead');
select is(pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 5, null)->>'state','GL060',
  'H27 an inactive staff member cannot be assigned a lead');
select is(pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 999, null)->>'state','P0002',
  'H27 unknown assignee on update is a generic not-found');
select is(pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 6, null)->>'state','P0002',
  'H27 cross-gym assignee is the same generic not-found');
select is(pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 999, null)->>'state',
  pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 6, null)->>'state'),
  'H27 unknown and cross-gym assignees are indistinguishable on update');
insert into h27_seen values ('L8-rev0', jsonb_build_object('rev', pg_temp.h27_rev(8)));
insert into h27_seen values ('L8-reassign', pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 3, null));
select is((select value->>'state' from h27_seen where name='L8-reassign'),'00000','H27 an active front-desk assignee is accepted');
select isnt(pg_temp.h27_rev(8),(select value->>'rev' from h27_seen where name='L8-rev0'),'H27 the reassignment rotates the revision');
insert into h27_seen values ('L8-stale', pg_temp.h27_update(8, 1, 'H27 Lead Eight', '+919272000008', null, 'instagram', 3, null, pg_temp.h27_id(8,902)::text));
select ok(pg_temp.h27_stale((select value from h27_seen where name='L8-stale')),
  'H27 a stale expectedRevision on update_lead is a conflict, not a silent overwrite');

-- ---------------- J. revision ownership and evidence immutability (L30) -
insert into h27_seen values ('L30-rev0', jsonb_build_object('rev', pg_temp.h27_rev(30)));
select is(pg_temp.h27_attempt(format('update public.leads set full_name=full_name where id=%L',pg_temp.h27_id(7,30))),
  'rows=1','H27 a no-op write is accepted');
select is(pg_temp.h27_rev(30),(select value->>'rev' from h27_seen where name='L30-rev0'),'H27 a no-op write does not rotate the revision');
select is(pg_temp.h27_attempt(format('update public.leads set full_name=''H27 Lead Thirty Renamed'' where id=%L',pg_temp.h27_id(7,30))),
  'rows=1','H27 a material direct edit is accepted');
select isnt(pg_temp.h27_rev(30),(select value->>'rev' from h27_seen where name='L30-rev0'),'H27 the material edit rotates the revision');
select pg_temp.h27_attempt(format('update public.leads set revision=%L where id=%L',pg_temp.h27_id(8,901),pg_temp.h27_id(7,30)));
select isnt(pg_temp.h27_rev(30),pg_temp.h27_id(8,901)::text,'H27 clients cannot set the revision');
select isnt(pg_temp.h27_attempt(format('update public.leads set creation_request_key=%L where id=%L',pg_temp.h27_id(8,999),pg_temp.h27_id(7,30))),
  'rows=1','H27 creation evidence is immutable for a direct writer');
select is((select to_jsonb(l)->>'creation_request_key' from public.leads l where l.id=pg_temp.h27_id(7,30)),
  pg_temp.h27_id(8,30)::text,'H27 the creation key is unchanged');
select isnt(pg_temp.h27_attempt(format('update public.leads set created_by_staff_id=%L where id=%L',pg_temp.h27_id(3,2),pg_temp.h27_id(7,30))),
  'rows=1','H27 the creation actor is immutable for a direct writer');
select is((select to_jsonb(l)->>'created_by_staff_id' from public.leads l where l.id=pg_temp.h27_id(7,30)),
  pg_temp.h27_id(3,1)::text,'H27 the creation actor is unchanged');
select isnt(pg_temp.h27_attempt(format('update public.leads set creation_request_facts=''{"injected":"yes"}''::jsonb where id=%L',pg_temp.h27_id(7,30))),
  'rows=1','H27 creation facts are immutable for a direct writer');

-- --------------------------------- K. conversion, replay and finality ----
insert into h27_seen values ('L1-rev-pre-convert', jsonb_build_object('rev', pg_temp.h27_rev(1)));
insert into h27_seen values ('L1-convert', pg_temp.h27_convert(1,1,'create'));
select is((select value->>'state' from h27_seen where name='L1-convert'),'00000','H27 a trial_done lead converts with no phone match');
select is((select array_agg(k order by k) from jsonb_object_keys(
    (select value->'value' from h27_seen where name='L1-convert')) k),
  array['leadId','memberId','outcome','replayed','revision'],
  'H27 the conversion result is exactly the frozen envelope');
select is((select value->'value'->>'leadId' from h27_seen where name='L1-convert'),pg_temp.h27_id(7,1)::text,
  'H27 the conversion result names its lead');
select is((select value->'value'->>'memberId' from h27_seen where name='L1-convert'),
  (select to_jsonb(l)->>'converted_member_id' from public.leads l where l.id=pg_temp.h27_id(7,1)),
  'H27 the conversion result names the member it created');
select is((select value->'value'->>'outcome' from h27_seen where name='L1-convert'),'created_member','H27 create mode reports created_member');
select is((select value->'value'->>'replayed' from h27_seen where name='L1-convert'),'false','H27 the first conversion is not a replay');
select is((select jsonb_build_array(to_jsonb(l)->>'stage', to_jsonb(l)->'converted_at' is not null) from public.leads l where l.id=pg_temp.h27_id(7,1)),
  jsonb_build_array('converted',true),'H27 the lead is converted with a server time');
select is((select jsonb_build_array(m.tenant_id::text,m.branch_id::text,m.full_name,m.phone,to_jsonb(m.email),m.status::text)
  from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000001'),
  jsonb_build_array(pg_temp.h27_id(1,1)::text,pg_temp.h27_id(2,1)::text,'H27 Lead One','+919272000001','null'::jsonb,'active'),
  'H27 one member is created from the lead branch, name, phone and email');
select is((select m.joined_on::text from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000001'),
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date::text,
  'H27 joined_on is the accepting transaction''s gym-local date');
select is((select jsonb_build_array(to_jsonb(m.member_code),to_jsonb(m.user_id),
  (select count(*) from public.memberships ms where ms.member_id=m.id and ms.tenant_id=m.tenant_id),
  (select count(*) from public.payments p where p.member_id=m.id and p.tenant_id=m.tenant_id),
  (select count(*) from public.attendance a where a.member_id=m.id and a.tenant_id=m.tenant_id),
  (select count(*) from public.consents c where c.member_id=m.id and c.tenant_id=m.tenant_id))
  from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000001'),
  jsonb_build_array(to_jsonb(null::text),to_jsonb(null::uuid),0,0,0,0),
  'H27 conversion creates no code, auth user, membership, payment, attendance or consent');
insert into h27_seen values ('L1-replay', pg_temp.h27_convert(1,1,'create',null,
  (select value->>'rev' from h27_seen where name='L1-rev-pre-convert')));
select is((select value->'value'->>'replayed' from h27_seen where name='L1-replay'),'true',
  'H27 an exact conversion retry replays after revision and stage checks would have refused');
select is((select value->'value'->>'outcome' from h27_seen where name='L1-replay'),'created_member',
  'H27 the replay returns the original immutable outcome');
select is((select value->'value'->>'memberId' from h27_seen where name='L1-replay'),
  (select to_jsonb(l)->>'converted_member_id' from public.leads l where l.id=pg_temp.h27_id(7,1)),
  'H27 the replay returns the original member id');
select is((select value->'value'->>'revision' from h27_seen where name='L1-replay'),pg_temp.h27_rev(1),
  'H27 the replay returns the lead''s current revision');
insert into h27_seen values ('L1-key-link', pg_temp.h27_convert(1,1,'link_existing',1,
  (select value->>'rev' from h27_seen where name='L1-rev-pre-convert')));
select is((select value->>'state' from h27_seen where name='L1-key-link'),'GL062','H27 a reused conversion key with a changed mode conflicts');
insert into h27_seen values ('L1-key-rev', pg_temp.h27_convert(1,1,'create',null,pg_temp.h27_id(8,900)::text));
select is((select value->>'state' from h27_seen where name='L1-key-rev'),'GL062','H27 a reused conversion key with a changed revision conflicts');
select pg_temp.h27_claim('gym_manager',1,2);
insert into h27_seen values ('L1-key-actor', pg_temp.h27_convert(1,1,'create',null,
  (select value->>'rev' from h27_seen where name='L1-rev-pre-convert')));
select is((select value->>'state' from h27_seen where name='L1-key-actor'),'GL062',
  'H27 a conversion retry by another actor conflicts even with matching facts');
select pg_temp.h27_claim();
insert into h27_seen values ('L1-again-create', pg_temp.h27_convert(1,101,'create'));
select ok(pg_temp.h27_stale((select value from h27_seen where name='L1-again-create')),
  'H27 a converted lead can never be converted again');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000001'),1,
  'H27 the second conversion attempt creates no second member for the phone');
insert into h27_seen values ('L1-again-link', pg_temp.h27_convert(1,102,'link_existing',1));
select ok(pg_temp.h27_stale((select value from h27_seen where name='L1-again-link')),
  'H27 a converted lead can never be relinked');
select is((select jsonb_build_array(to_jsonb(l)->>'stage', to_jsonb(l)->>'converted_member_id')
    from public.leads l where l.id=pg_temp.h27_id(7,1)),
  jsonb_build_array('converted',
    (select m.id::text from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000001')),
  'H27 the relink attempt leaves the converted member unchanged');
select is(pg_temp.h27_transition(1,'lost',null,'H27 never')->>'state','GL059',
  'H27 a converted lead refuses a transition');
select is(pg_temp.h27_update(1, 1, 'H27 Lead One Renamed', '+919272000001', null, 'walk_in', null, null)->>'state','GL059',
  'H27 a converted lead refuses a detail edit');
select is(pg_temp.h27_attempt(format('update public.leads set converted_member_id=%L where id=%L',
  pg_temp.h27_id(5,5),pg_temp.h27_id(7,1))),'error=GL059','H27 the converted member is frozen against a direct writer');
select is(pg_temp.h27_attempt(format('update public.leads set converted_at=null where id=%L',pg_temp.h27_id(7,1))),
  'error=GL059','H27 the conversion time is frozen against a direct writer');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''lost'' where id=%L',pg_temp.h27_id(7,1))),
  'error=GL059','H27 a direct writer cannot leave the terminal converted stage');
select isnt(pg_temp.h27_attempt(format('update public.leads set lost_reason=''x'' where id=%L',pg_temp.h27_id(7,1))),
  'rows=1','H27 a converted row cannot grow a loss reason');
select is((select to_jsonb(l)->>'lost_reason' from public.leads l where l.id=pg_temp.h27_id(7,1)),null,
  'H27 the converted row still has no loss reason');
select isnt(pg_temp.h27_attempt(format('update public.leads set conversion_request_key=%L where id=%L',
  pg_temp.h27_id(8,999),pg_temp.h27_id(7,1))),'rows=1','H27 conversion evidence is immutable');
select isnt(pg_temp.h27_attempt(format('update public.leads set conversion_request_facts=''{"injected":"yes"}''::jsonb where id=%L',
  pg_temp.h27_id(7,1))),'rows=1','H27 conversion facts are immutable');

-- -------------- L. GL061, explicit linking, unavailability, privacy ------
insert into h27_seen values ('L2-rev-pre', jsonb_build_object('rev', pg_temp.h27_rev(2)));
insert into h27_seen values ('L2-convert', pg_temp.h27_convert(2,2,'create'));
select is((select value->>'state' from h27_seen where name='L2-convert'),'GL061',
  'H27 an eligible same-gym member owning the phone refuses automatic creation');
select is((select jsonb_build_array(to_jsonb(l)->>'stage',to_jsonb(l)->>'converted_member_id',to_jsonb(l)->>'revision')
    from public.leads l where l.id=pg_temp.h27_id(7,2)),
  jsonb_build_array('trial_done','null'::jsonb,(select value->>'rev' from h27_seen where name='L2-rev-pre')),
  'H27 the refused conversion leaves the lead at trial_done with no member and no rotation');
insert into h27_seen values ('L2-link', pg_temp.h27_convert(2,3,'link_existing',1));
select is((select value->>'state' from h27_seen where name='L2-link'),'00000','H27 the explicit link is accepted');
select is((select value->'value'->>'outcome' from h27_seen where name='L2-link'),'linked_existing','H27 link mode reports linked_existing');
select is((select jsonb_build_array(to_jsonb(l)->>'stage',to_jsonb(l)->>'converted_member_id',l.full_name)
  from public.leads l where l.id=pg_temp.h27_id(7,2)),
  jsonb_build_array('converted',pg_temp.h27_id(5,1)::text,'H27 Lead Two'),
  'H27 the link converts the lead to the named member without editing its profile');
select is((select jsonb_build_array(m.full_name,m.phone,m.status::text,m.joined_on::text,to_jsonb(m.email))
  from public.members m where m.id=pg_temp.h27_id(5,1)),
  jsonb_build_array('H27 Member Active','+919271000001','active','2026-09-01','null'::jsonb),
  'H27 linking edits neither profile');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919271000001'),1,
  'H27 linking creates no duplicate member');
insert into h27_seen values ('L7-convert', pg_temp.h27_convert(7,7,'create'));
select is((select value->>'state' from h27_seen where name='L7-convert'),'GL061',
  'H27 a paused member remains eligible and refuses automatic creation');
select pg_temp.h27_claim('gym_manager',1,2);
insert into h27_seen values ('L7-link', pg_temp.h27_convert(7,70,'link_existing',5));
select is((select value->>'state' from h27_seen where name='L7-link'),'00000','H27 a manager may perform the explicit link');
select is((select value->'value'->>'outcome' from h27_seen where name='L7-link'),'linked_existing','H27 the paused member links');
select pg_temp.h27_claim();
insert into h27_seen values ('L15-convert', pg_temp.h27_convert(15,15,'create'));
select is((select value->>'state' from h27_seen where name='L15-convert'),'GL061',
  'H27 an expired member remains eligible and refuses automatic creation');
insert into h27_seen values ('L15-link', pg_temp.h27_convert(15,150,'link_existing',7));
select is((select value->>'state' from h27_seen where name='L15-link'),'00000','H27 the expired member links');
insert into h27_seen values ('L3-convert', pg_temp.h27_convert(3,5,'create'));
select ok(pg_temp.h27_unavailable((select value from h27_seen where name='L3-convert')),
  'H27 a cancelled same-phone member yields a generic conflict, never an offer, a success or a unique violation');
select ok(not pg_temp.h27_mentions((select value from h27_seen where name='L3-convert'),pg_temp.h27_id(5,2)::text),
  'H27 the unavailable conflict names no member id');
select ok(not pg_temp.h27_mentions((select value from h27_seen where name='L3-convert'),'H27 Member Cancelled'),
  'H27 the unavailable conflict names no profile');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919271000002'),1,
  'H27 the unavailable path creates no member');
select is((select jsonb_build_array(to_jsonb(l)->>'stage',to_jsonb(l)->>'converted_member_id')
  from public.leads l where l.id=pg_temp.h27_id(7,3)),jsonb_build_array('trial_done','null'::jsonb),
  'H27 the unavailable path changes no lead fact');
insert into h27_seen values ('L5-convert', pg_temp.h27_convert(5,50,'create'));
select ok(pg_temp.h27_unavailable((select value from h27_seen where name='L5-convert')),
  'H27 a blocked same-phone member yields the same generic conflict');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919271000003'),1,
  'H27 the blocked path creates no member');
insert into h27_seen values ('L6-convert', pg_temp.h27_convert(6,60,'create'));
select ok(pg_temp.h27_unavailable((select value from h27_seen where name='L6-convert')),
  'H27 an erased same-phone member yields the same generic conflict');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919271000004'),1,
  'H27 the erased path creates no member');
select ok((select count(distinct value->>'state')=1 from h27_seen where name in ('L3-convert','L5-convert','L6-convert'))
  and not exists(select 1 from h27_seen where name in ('L3-convert','L5-convert','L6-convert')
    and pg_temp.h27_missing(value->>'state')),
  'H27 every unavailable outcome is one indistinguishable generic shape');
insert into h27_seen values
  ('L8-link-wrongphone', pg_temp.h27_convert(8,80,'link_existing',1)),
  ('L8-link-cancelled',  pg_temp.h27_convert(8,81,'link_existing',2)),
  ('L8-link-foreign',    pg_temp.h27_convert(8,82,'link_existing',6)),
  ('L8-link-unknown',    pg_temp.h27_convert(8,83,'link_existing',999));
select is((select value->>'state' from h27_seen where name='L8-link-wrongphone'),'P0002','H27 a wrong-phone target is a generic not-found');
select is((select value->>'state' from h27_seen where name='L8-link-cancelled'),'P0002','H27 an ineligible target is never offered or linked');
select is((select value->>'state' from h27_seen where name='L8-link-foreign'),'P0002','H27 a cross-gym target is a generic not-found');
select is((select value->>'state' from h27_seen where name='L8-link-unknown'),'P0002','H27 an unknown target is a generic not-found');
select ok((select count(distinct value->>'state')=1 from h27_seen
    where name in ('L8-link-wrongphone','L8-link-cancelled','L8-link-foreign','L8-link-unknown'))
  and not exists(select 1 from h27_seen
    where name in ('L8-link-wrongphone','L8-link-cancelled','L8-link-foreign','L8-link-unknown')
    and pg_temp.h27_missing(value->>'state')),
  'H27 wrong-phone, ineligible, cross-gym and unknown targets are indistinguishable');
select pg_temp.h27_claim('front_desk',1,3);
insert into h27_seen values ('L4-convert', pg_temp.h27_convert(4,4,'create'));
select is((select value->>'state' from h27_seen where name='L4-convert'),'00000',
  'H27 a cross-gym phone match converts exactly like a no-match create');
select is((select value->'value'->>'outcome' from h27_seen where name='L4-convert'),'created_member',
  'H27 the foreign-phone conversion reports created_member');
select ok(not pg_temp.h27_mentions((select value from h27_seen where name='L4-convert'),pg_temp.h27_id(5,6)::text),
  'H27 the result discloses no other gym''s member');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919271000006'),1,
  'H27 the new same-gym member owns the phone now');
select pg_temp.h27_claim();
select is(pg_temp.h27_convert(21,210,'create')->>'state','GL059','H27 only trial_done may convert');
select is((select count(*) from public.members m where m.tenant_id=pg_temp.h27_id(1,1) and m.phone='+919272000021'),0,
  'H27 the stage refusal creates no member');
select pg_temp.h27_claim('gym_owner',2,6);
select is(pg_temp.h27_convert(3,211,'create')->>'state','P0002','H27 another gym''s front office sees a generic not-found, not the lead');
select is(pg_temp.h27_convert(1,1,'create',null,
  (select value->>'rev' from h27_seen where name='L1-rev-pre-convert'))->>'state','P0002',
  'H27 replay resolves only after target visibility: a foreign caller gets not-found');
select pg_temp.h27_claim();

-- ------------------------ M. direct-write conversion guard (L11) --------
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_member_id=%L, converted_at=%L where id=%L',
  pg_temp.h27_id(5,1),transaction_timestamp(),pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion needs the exact lead phone');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_member_id=%L, converted_at=%L where id=%L',
  pg_temp.h27_id(5,2),transaction_timestamp(),pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion needs an eligible member');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_at=%L where id=%L',
  transaction_timestamp(),pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion requires a member');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_member_id=%L, converted_at=%L where id=%L',
  pg_temp.h27_id(5,2),'2020-01-01 00:00:00+00',pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion stamps the server time, never a supplied one');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_member_id=%L where id=%L',
  pg_temp.h27_id(5,2),pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion requires the conversion time');
select is(pg_temp.h27_attempt(format('update public.leads set stage=''converted'', converted_member_id=%L, converted_at=%L where id=%L',
  pg_temp.h27_id(5,6),transaction_timestamp(),pg_temp.h27_id(7,11))),'error=GL060',
  'H27 a direct conversion cannot name a cross-gym member');
select is((select to_jsonb(l)->>'stage' from public.leads l where l.id=pg_temp.h27_id(7,11)),'trial_done',
  'H27 every refused direct conversion left the lead unchanged');

-- --------------------------------- N. platform authority boundary -------
select pg_temp.h27_claim('super_admin',null,null,null,7);
select is(pg_temp.h27_attempt(format('update public.leads set stage=''lost'' where id=%L',pg_temp.h27_id(7,1))),
  'error=GL059','H27 retained database authority cannot reopen a terminal row');
insert into h27_seen values ('L30-rev-notes', jsonb_build_object('rev', pg_temp.h27_rev(30)));
select is(pg_temp.h27_attempt(format('update public.leads set notes=''H27 platform note'' where id=%L',pg_temp.h27_id(7,30))),
  'rows=1','H27 super admin retains its existing direct write authority');
select isnt(pg_temp.h27_rev(30),(select value->>'rev' from h27_seen where name='L30-rev-notes'),
  'H27 the platform material edit still rotates the revision');
select pg_temp.h27_claim('platform_support',null,null,null,8);
select isnt(pg_temp.h27_attempt(format('update public.leads set notes=''H27 support note'' where id=%L',pg_temp.h27_id(7,30))),
  'rows=1','H27 platform support cannot mutate lead rows');
select is((select to_jsonb(l)->>'notes' from public.leads l where l.id=pg_temp.h27_id(7,30)),'H27 platform note',
  'H27 the refused support write changed nothing');
select isnt(pg_temp.h27_attempt(format('update public.leads set stage=''lost'', lost_reason=''H27 support lost'' where id=%L',
  pg_temp.h27_id(7,30))),'rows=1','H27 platform support cannot change lead stage directly');
select ok(exists(select 1 from public.leads l where l.tenant_id=pg_temp.h27_id(1,1))
  and exists(select 1 from public.leads l where l.tenant_id=pg_temp.h27_id(1,2)),
  'H27 platform support keeps its cross-gym lead reads');
select pg_temp.h27_claim('gym_owner',1,1,null,null,1);
select is(pg_temp.h27_attempt(format('update public.leads set notes=''preview'' where id=%L',pg_temp.h27_id(7,30))),
  'error=42501','H27 an impersonation preview cannot write lead rows');
select pg_temp.h27_claim();

-- ------------------------------- O. who may call the list RPC -----------
select is(pg_temp.h27_list()->>'state','00000','H27 an owner reads the list');
select pg_temp.h27_claim('gym_manager',1,2);
select is(pg_temp.h27_list()->>'state','00000','H27 a manager reads the list');
select pg_temp.h27_claim('front_desk',1,3);
select is(pg_temp.h27_list()->>'state','00000','H27 front desk reads the list');
select pg_temp.h27_claim('trainer',1,4);
select is(pg_temp.h27_list()->>'state','42501','H27 a trainer reads no lead data');
select pg_temp.h27_claim('member',1,null,1);
select is(pg_temp.h27_list()->>'state','42501','H27 a member reads no lead data');
select pg_temp.h27_claim('gym_owner',1,1,null,null,1);
select is(pg_temp.h27_list()->>'state','42501','H27 an impersonation preview reads no lead data');
select pg_temp.h27_claim('platform_support',null,null,null,8);
select is(pg_temp.h27_list()->>'state','42501','H27 platform support cannot use the gym-side list');
select pg_temp.h27_claim('super_admin',null,null,null,7);
select is(pg_temp.h27_list()->>'state','42501','H27 super admin cannot use the gym-side list');
select pg_temp.h27_claim('gym_owner',1,null);
select is(pg_temp.h27_list()->>'state','42501','H27 a front-office role without a staff claim reads nothing');
select pg_temp.h27_claim('gym_owner',1,6);
select is(pg_temp.h27_list()->>'state','42501','H27 a staff row from another gym is not a complete identity');
select pg_temp.h27_claim('gym_owner',1,999);
select is(pg_temp.h27_list()->>'state','42501','H27 a staff claim naming no real row reads nothing');
select pg_temp.h27_claim();

-- ---------------------------- P. who may call the mutation RPCs ---------
select pg_temp.h27_claim('trainer',1,4);
select is(pg_temp.h27_convert(3,84,'create')->>'state','42501','H27 a trainer cannot convert, even a visible lead');
select is(pg_temp.h27_create(85,1,'H27 Trainer Lead','+919272000085',null,'walk_in',null,null)->>'state','42501',
  'H27 a trainer cannot create a lead');
select is(pg_temp.h27_transition(3,'lost',null,'H27 trainer attempt')->>'state','42501','H27 a trainer cannot transition a lead');
select pg_temp.h27_claim('member',1,null,1);
select is(pg_temp.h27_convert(3,86,'create')->>'state','42501','H27 a member cannot convert');
select is(pg_temp.h27_create(87,1,'H27 Member Lead','+919272000087',null,'walk_in',null,null)->>'state','42501',
  'H27 a member cannot create a lead');
select is(pg_temp.h27_update(3, 1, 'H27 Lead Three', '+919271000002', null, 'walk_in', null, null)->>'state','42501',
  'H27 a member cannot edit a lead');
select pg_temp.h27_claim('gym_owner',1,1,null,null,1);
select is(pg_temp.h27_convert(3,88,'create')->>'state','42501','H27 an impersonation preview cannot convert');
select is(pg_temp.h27_create(89,1,'H27 Preview Lead','+919272000089',null,'walk_in',null,null)->>'state','42501',
  'H27 an impersonation preview cannot create');
select pg_temp.h27_claim('platform_support',null,null,null,8);
select is(pg_temp.h27_convert(3,91,'create')->>'state','42501','H27 platform support cannot convert');
select is(pg_temp.h27_create(92,1,'H27 Support Lead','+919272000092',null,'walk_in',null,null)->>'state','42501',
  'H27 platform support cannot create');
select is(pg_temp.h27_update(3, 1, 'H27 Lead Three', '+919271000002', null, 'walk_in', null, null)->>'state','42501',
  'H27 platform support cannot edit');
select pg_temp.h27_claim('super_admin',null,null,null,7);
select is(pg_temp.h27_convert(3,93,'create')->>'state','42501','H27 super admin cannot convert through the gym-side route');
select pg_temp.h27_claim('gym_owner',2,6);
select is(pg_temp.h27_update(3, 1, 'H27 Lead Three', '+919271000002', null, 'walk_in', null, null)->>'state','P0002',
  'H27 another gym''s front office gets not-found on update');
select is(pg_temp.h27_transition(3,'lost',null,'H27 foreign attempt')->>'state','P0002',
  'H27 another gym''s front office gets not-found on transition');
select pg_temp.h27_claim();

-- ---------------------------------- Q. one-snapshot list content --------
insert into h27_seen values ('list-all', pg_temp.h27_list());
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-all'),
  (select count(*)::text from public.leads),'H27 the unfiltered total is the whole visible population');
select is(coalesce((select value->'value'->>'pageResultCount' from h27_seen where name='list-all'),'h27-none-a'),
  coalesce((select jsonb_array_length(value->'value'->'rows')::text from h27_seen where name='list-all'),'h27-none-b'),
  'H27 pageResultCount equals the returned rows');
select is((select jsonb_array_length(value->'value'->'rows') from h27_seen where name='list-all'),
  (select count(*)::int from public.leads),'H27 a small population returns every row on one page');
select is((select value->'value'->'nextAfter' from h27_seen where name='list-all'),'null'::jsonb,
  'H27 the last complete page carries a null cursor tail');
select is(coalesce((select sum((e.value#>>'{}')::int)::text from jsonb_each(
      (select value->'value'->'filteredStageCounts' from h27_seen where name='list-all')) e),'h27-none-a'),
  coalesce((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-all'),'h27-none-b'),
  'H27 the stage buckets sum to the total');
select is((select array_agg(k order by k) from jsonb_object_keys(
    (select value->'value'->'filteredStageCounts' from h27_seen where name='list-all')) k),
  array['contacted','converted','lost','new','trial_done','trial_scheduled'],
  'H27 filteredStageCounts carries every canonical stage');
select is((select array_agg(k order by k) from jsonb_object_keys(
    (select value->'value' from h27_seen where name='list-all')) k),
  array['asOf','filteredStageCounts','nextAfter','pageResultCount','rows','totalMatchingCount'],
  'H27 the result object is exactly the frozen envelope');
select is((select array_agg(k order by k) from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') rr,
    jsonb_object_keys(rr) k
  where s.name='list-all' and rr->>'id'=pg_temp.h27_id(7,1)::text),
  array['assignedToName','assignedToStaffId','branchId','branchName','convertedMemberId','fullName','id',
    'lostReason','phone','revision','source','stage','trialAt','updatedAt'],
  'H27 every row is exactly LeadListRow');
select is(coalesce((select jsonb_agg(r->>'id' order by ord)::text from jsonb_array_elements(
      (select value->'value'->'rows' from h27_seen where name='list-all')) with ordinality t(r,ord)),'h27-none-a'),
  coalesce((select jsonb_agg(l.id::text order by l.updated_at desc, l.id desc)::text from public.leads l),'h27-none-b'),
  'H27 rows sort by (updated_at desc, id desc)');
select ok(jsonb_typeof((select value->'value'->'totalMatchingCount' from h27_seen where name='list-all'))='string',
  'H27 the total is a decimal integer string');
select ok(jsonb_typeof((select value->'value'->'pageResultCount' from h27_seen where name='list-all'))='string',
  'H27 the page count is a decimal integer string');
select ok((select bool_and(jsonb_typeof(e.value)='string') from jsonb_each(
    (select value->'value'->'filteredStageCounts' from h27_seen where name='list-all')) e),
  'H27 every stage bucket is a decimal integer string');
select ok(jsonb_typeof((select value->'value'->'asOf' from h27_seen where name='list-all'))='string',
  'H27 asOf is the statement timestamp as a string');
select is((select r->>'assignedToName' from h27_seen s, jsonb_array_elements(s.value->'value'->'rows') r
    where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,2)::text),'H27 Manager',
  'H27 an assigned row names its assignee');
select is((select jsonb_build_array(r->'assignedToName',r->'assignedToStaffId') from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,30)::text),
  jsonb_build_array(to_jsonb(null::text),to_jsonb(null::uuid)),
  'H27 an unassigned row carries explicit nulls');
select is((select jsonb_build_array(r->>'branchId',r->>'branchName') from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,20)::text),
  jsonb_build_array(pg_temp.h27_id(2,2)::text,'H27 Branch Two'),
  'H27 rows carry their branch identity');
select ok((select r->'trialAt' is not null from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,21)::text),
  'H27 a scheduled trial exposes its instant');
select is((select r->>'convertedMemberId' from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,1)::text),
  (select to_jsonb(l)->>'converted_member_id' from public.leads l where l.id=pg_temp.h27_id(7,1)),
  'H27 a converted row names its member');
select is((select r->>'lostReason' from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-all' and r->>'id'=pg_temp.h27_id(7,9)::text),
  'H27 lost reason','H27 a lost row carries its reason');

-- ------------------------------------ R. filtered counts stay exact -----
insert into h27_seen values ('list-new', pg_temp.h27_list('new'));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-new'),
  (select count(*)::text from public.leads l where l.stage='new'),
  'H27 a stage filter counts exactly its population');
select is(coalesce((select value->'value'->'filteredStageCounts'->>'new' from h27_seen where name='list-new'),'h27-none-a'),
  coalesce((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-new'),'h27-none-b'),
  'H27 the selected stage bucket equals the matched population');
select is((select count(*) from jsonb_each((select value->'value'->'filteredStageCounts' from h27_seen where name='list-new')) e
    where e.key<>'new' and e.value#>>'{}'<>'0'),0,
  'H27 every other bucket is zero under the stage filter');
select is(coalesce((select jsonb_array_length(value->'value'->'rows')::text from h27_seen where name='list-new'),'h27-none-a'),
  coalesce((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-new'),'h27-none-b'),
  'H27 the filtered page returns exactly the matched rows');
insert into h27_seen values ('list-referral', pg_temp.h27_list(null,'referral'));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-referral'),
  (select count(*)::text from public.leads l where l.source='referral'),
  'H27 a source filter counts exactly its population');
insert into h27_seen values ('list-unassigned', pg_temp.h27_list(null,null,'unassigned'));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-unassigned'),
  (select count(*)::text from public.leads l where l.assigned_to_staff_id is null),
  'H27 the unassigned filter counts exactly its population');
select ok((select bool_and(r->>'assignedToStaffId' is null) from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-unassigned'),
  'H27 the unassigned page contains only unassigned rows');
insert into h27_seen values ('list-assignee', pg_temp.h27_list(null,null,pg_temp.h27_id(3,2)::text));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-assignee'),
  (select count(*)::text from public.leads l where l.assigned_to_staff_id=pg_temp.h27_id(3,2)),
  'H27 a UUID assignee filter counts exactly its population');
insert into h27_seen values ('list-br2', pg_temp.h27_list(null,null,null,2));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-br2'),
  (select count(*)::text from public.leads l where l.branch_id=pg_temp.h27_id(2,2)),
  'H27 a branch filter counts exactly its population');
insert into h27_seen values ('list-br3', pg_temp.h27_list(null,null,null,3));
select is((select jsonb_build_array(value->'value'->>'totalMatchingCount',value->'value'->>'pageResultCount',
    value->'value'->'filteredStageCounts') from h27_seen where name='list-br3'),
  jsonb_build_array('0','0',(select jsonb_object_agg(k,'0')
    from unnest(array['contacted','converted','lost','new','trial_done','trial_scheduled']) k)),
  'H27 a cross-gym branch filter discloses nothing but zeros');
insert into h27_seen values ('list-combined', pg_temp.h27_list('new',null,null,2));
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-combined'),
  (select count(*)::text from public.leads l where l.stage='new' and l.branch_id=pg_temp.h27_id(2,2)),
  'H27 combined filters count exactly their intersection');
insert into h27_seen values ('list-qnull', pg_temp.h27_list()), ('list-qempty', pg_temp.h27_list(null,null,null,null,''));
select ok((select jsonb_build_array(value->'value'->'rows',value->'value'->>'totalMatchingCount',
    value->'value'->'filteredStageCounts') from h27_seen where name='list-qnull')
  = (select jsonb_build_array(value->'value'->'rows',value->'value'->>'totalMatchingCount',
    value->'value'->'filteredStageCounts') from h27_seen where name='list-qempty')
  and not exists(select 1 from h27_seen where name in ('list-qnull','list-qempty')
    and pg_temp.h27_missing(value->>'state')),
  'H27 an empty search is null');

-- ----------------------------------- S. the other gym sees only itself --
select pg_temp.h27_claim('gym_owner',2,6);
insert into h27_seen values ('list-t2', pg_temp.h27_list());
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='list-t2'),
  (select count(*)::text from public.leads),'H27 gym B counts only its own leads');
select ok((select bool_and(r->>'id'=pg_temp.h27_id(7,14)::text) from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') r where s.name='list-t2'),
  'H27 gym B''s page contains only its own lead');
select pg_temp.h27_claim();

-- ------------------------ T. paging, clamps and cursor continuations ----
insert into h27_seen values ('batch-create', pg_temp.h27_exec($sql$
  select public.create_lead(pg_temp.h27_id(8,1000+g), pg_temp.h27_id(2,1),
    'H27 Batch '||g, '+919274'||lpad(g::text,6,'0'), null, 'website', null, null)
  from generate_series(1,205) g
$sql$));
select is((select value->>'state' from h27_seen where name='batch-create'),'00000','H27 the paging population is created');
select is((select count(*)::text from public.leads l where l.source='website'),'206',
  'H27 the batch created exactly 205 new website enquiries');
insert into h27_seen values ('page-default', pg_temp.h27_list());
select is((select value->'value'->>'pageResultCount' from h27_seen where name='page-default'),'50',
  'H27 an unrequested page size is the registry default 50');
select is((select value->'value'->>'totalMatchingCount' from h27_seen where name='page-default'),
  (select count(*)::text from public.leads),'H27 the total still counts the whole population');
select ok((select (value->'value'->'nextAfter'->>'updatedAt')::timestamptz = l.updated_at
    and value->'value'->'nextAfter'->>'id' = l.id::text
    from h27_seen s, public.leads l
    where s.name='page-default' and l.id=(select l2.id from public.leads l2
      order by l2.updated_at desc, l2.id desc offset 49 limit 1)),
  'H27 the cursor tail names the exact last row of the page');
insert into h27_seen values ('page-max', pg_temp.h27_list(null,null,null,null,null,null,null,500));
select is((select value->'value'->>'pageResultCount' from h27_seen where name='page-max'),'200',
  'H27 an oversized page request clamps to 200, never refuses');
insert into h27_seen values ('page-2', pg_temp.h27_list(null,null,null,null,null,null,null,2));
select is((select value->'value'->>'pageResultCount' from h27_seen where name='page-2'),'2',
  'H27 a two-row page returns two rows');
select ok((select (value->'value'->'nextAfter'->>'updatedAt')::timestamptz = l.updated_at
    and value->'value'->'nextAfter'->>'id' = l.id::text
    from h27_seen s, public.leads l
    where s.name='page-2' and l.id=(select l2.id from public.leads l2
      order by l2.updated_at desc, l2.id desc offset 1 limit 1)),
  'H27 the small page tail names the exact second row');
insert into h27_seen values ('page-2-next', pg_temp.h27_list(null,null,null,null,null,
  (select value->'value'->'nextAfter'->>'updatedAt' from h27_seen where name='page-2'),
  (select value->'value'->'nextAfter'->>'id' from h27_seen where name='page-2'),2));
select is(coalesce((select r->>'id' from h27_seen s,
    jsonb_array_elements(s.value->'value'->'rows') with ordinality t(r,ord)
    where s.name='page-2-next' order by ord limit 1),'h27-none-a'),
  coalesce((select l.id::text from public.leads l order by l.updated_at desc, l.id desc offset 2 limit 1),'h27-none-b'),
  'H27 the cursor continues at the third row of the ordering');
select is((select value->'value'->>'pageResultCount' from h27_seen where name='page-2-next'),'2',
  'H27 the continuation page returns two rows');
insert into h27_seen values ('page-2-unusable', pg_temp.h27_list(null,null,null,null,null,
  (select value->'value'->'nextAfter'->>'updatedAt' from h27_seen where name='page-2'),null,2));
select ok((select value->'value'->'rows' from h27_seen where name='page-2-unusable')
  = (select value->'value'->'rows' from h27_seen where name='page-2')
  and not exists(select 1 from h27_seen where name='page-2-unusable'
    and pg_temp.h27_missing(value->>'state')),
  'H27 an unusable cursor starts page one');
insert into h27_seen values ('walk-1', pg_temp.h27_list(null,null,null,null,null,null,null,200));
insert into h27_seen values ('walk-2', pg_temp.h27_list(null,null,null,null,null,
  (select value->'value'->'nextAfter'->>'updatedAt' from h27_seen where name='walk-1'),
  (select value->'value'->'nextAfter'->>'id' from h27_seen where name='walk-1'),200));
select is((select value->'value'->'nextAfter' from h27_seen where name='walk-2'),'null'::jsonb,
  'H27 the final page carries a null tail');
select is(coalesce((select value->'value'->>'pageResultCount' from h27_seen where name='walk-2'),'h27-none-a'),
  coalesce((select (((value->'value'->>'totalMatchingCount')::int)-200)::text from h27_seen where name='walk-1'),'h27-none-b'),
  'H27 the second page returns exactly the remaining rows');
select is((select count(distinct r->>'id') from h27_seen s,
    jsonb_array_elements(case when s.name in ('walk-1','walk-2') then s.value->'value'->'rows' else '[]'::jsonb end) r
    where s.name in ('walk-1','walk-2')),
  (select (value->'value'->>'totalMatchingCount')::int from h27_seen where name='walk-1'),
  'H27 the walked pages cover the population with no overlap and no gap');

-- ------------------------------------------- U. no invented audit rows ---
set local role postgres;
select set_config('request.jwt.claims','',true);
select is((select count(*) from public.audit_log a
  where (a.record_type='lead'
     or a.record_id in (select l.id from public.leads l
        where l.tenant_id in (pg_temp.h27_id(1,1),pg_temp.h27_id(1,2))))
    and a.tenant_id in (pg_temp.h27_id(1,1),pg_temp.h27_id(1,2))),0,
  'H27 ordinary lead writes invent no audit evidence');
select * from finish();
rollback;
