-- h67_member_invites_holdout: independent holdout suite for FitCruxx v2 feature INV
-- (member invites and self-linking, INV-001 to INV-024).
--
-- Authored from openspec/changes/member-invites/proposal.md ONLY. The visible
-- suite and the implementation were not read (AGENTS.md hard rule 10).
--
-- HOW THIS FILE IS BUILT, AND WHY
--
-- Every call into the feature goes through a pg_temp helper that runs as
-- postgres, borrows one role plus one set of JWT claims for exactly one
-- statement, catches any error inside a subtransaction and hands back a short
-- text result (a row summary, or err:SQLSTATE). A wrong implementation
-- therefore fails the assertion that exposed it instead of aborting the whole
-- transaction and hiding every later assertion. Helpers never print text rows
-- that could be mistaken for TAP lines.
--
-- Fixtures use the UUID prefix 67900000-0000-4000-8000- and gym codes H67xxx.
-- Scenario number k builds member u(10000+k), Auth user u(20000+k) and token
-- hash h(k) (the lowercase hex SHA-256 of a fixed string). Every count is
-- scoped to those fixtures (ADR-050). Time margins are at least an hour wide
-- except the 15 minute redeem window, which uses 8 minute rows inside it and
-- 22 or 25 minute rows outside it, so a slow Cloud run cannot flip a result.
--
-- COVERAGE MAP (assertion groups)
--   A  catalog: table, enum, columns, constraints, indexes, RLS, grants,
--      triggers, function signatures, privilege matrix, hygiene   INV-017
--   B  app.member_invite_audit allowlist, shape, denial            INV-016
--   C  table constraints by name, defaults, touch trigger          INV-001/003/024
--   D  members_auth_binding_invariant GL074, every role, both shapes  INV-013
--   E  issue: roles, tenancy, GL075..GL078, supersede, audit, limits, hashes
--      INV-001/002/003/004/006/016
--   F  revoke: roles, GL079, audit, token dead afterwards          INV-005
--   G  peek: oracle freedom, eligibility, malformed hashes         INV-012
--   H  redeem happy paths, email matching rules, member and gym state
--      flipped after a real issue                                  INV-007/008
--   I  redeem refusals: no oracle, check order, D1, audit rows     INV-008/011
--   J  redeem throttle windows and boundaries                      INV-010
--   K  replay, reuse, relink, supersede-then-redeem, advisory lock INV-009/011
--   L  unlink: roles, reasons, sessions, audit, invites untouched  INV-014
--   M  read_member_app_access precedence table                     INV-015
--   N  direct table access, RLS, no write grants                   INV-017
--   O  auth user deletion, audit hygiene                           INV-016/024

begin;

set local role postgres;

select plan(575);

-- ===========================================================================
-- helpers
-- ===========================================================================

create temp table h67_res (k text primary key, v text);
create temp table h67_marks (k text primary key, v bigint not null);

create function pg_temp.u(n integer) returns uuid language sql immutable as $f$
  select ('67900000-0000-4000-8000-' || lpad(to_hex(n), 12, '0'))::uuid
$f$;

create function pg_temp.h(n integer) returns text language sql immutable as $f$
  select encode(sha256(convert_to('h67-token-' || n::text, 'utf8')), 'hex')
$f$;

create function pg_temp.ts(p text) returns timestamptz language plpgsql as $f$
begin
  return p::timestamptz;
exception when others then
  return null;
end;
$f$;

create function pg_temp.nouuid(p text) returns text language sql immutable as $f$
  select regexp_replace(p, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'UUID', 'g')
$f$;

-- claims builders -----------------------------------------------------------

create function pg_temp.c_plain(p_user integer) returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(p_user), 'role', 'authenticated')::text
$f$;

create function pg_temp.c_staff(p_user integer, p_role text, p_org integer, p_staff integer) returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(p_user), 'role', 'authenticated', 'app_role', p_role,
                            'tenant_id', pg_temp.u(p_org), 'staff_id', pg_temp.u(p_staff))::text
$f$;

create function pg_temp.c_add(p_claims text, p_extra jsonb) returns text language sql as $f$
  select (p_claims::jsonb || p_extra)::text
$f$;

create function pg_temp.c_drop(p_claims text, p_key text) returns text language sql as $f$
  select (p_claims::jsonb - p_key)::text
$f$;

create function pg_temp.k_owner() returns text language sql as $f$
  select pg_temp.c_staff(2001, 'gym_owner', 101, 301)
$f$;

create function pg_temp.k_mgr() returns text language sql as $f$
  select pg_temp.c_staff(2002, 'gym_manager', 101, 302)
$f$;

create function pg_temp.k_desk() returns text language sql as $f$
  select pg_temp.c_staff(2003, 'front_desk', 101, 303)
$f$;

create function pg_temp.k_trainer() returns text language sql as $f$
  select pg_temp.c_staff(2004, 'trainer', 101, 304)
$f$;

create function pg_temp.k_ownerb() returns text language sql as $f$
  select pg_temp.c_staff(2005, 'gym_owner', 102, 305)
$f$;

create function pg_temp.k_inactive() returns text language sql as $f$
  select pg_temp.c_staff(2007, 'front_desk', 101, 307)
$f$;

create function pg_temp.k_ownerl() returns text language sql as $f$
  select pg_temp.c_staff(2014, 'gym_owner', 109, 314)
$f$;

create function pg_temp.k_member() returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(20260), 'role', 'authenticated', 'app_role', 'member',
                            'tenant_id', pg_temp.u(101), 'member_id', pg_temp.u(10260))::text
$f$;

create function pg_temp.k_super() returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(2020), 'role', 'authenticated', 'app_role', 'super_admin')::text
$f$;

create function pg_temp.k_super_t() returns text language sql as $f$
  select pg_temp.c_add(pg_temp.k_super(), jsonb_build_object('tenant_id', pg_temp.u(101)))
$f$;

create function pg_temp.k_support() returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(2021), 'role', 'authenticated', 'app_role', 'platform_support')::text
$f$;

create function pg_temp.k_plain() returns text language sql as $f$
  select pg_temp.c_plain(2022)
$f$;

create function pg_temp.k_imp() returns text language sql as $f$
  select pg_temp.c_add(pg_temp.k_owner(), jsonb_build_object('impersonation_session_id', pg_temp.u(9001)))
$f$;

create function pg_temp.k_imp2() returns text language sql as $f$
  select jsonb_build_object('sub', pg_temp.u(2020), 'role', 'authenticated', 'app_role', 'gym_owner',
                            'tenant_id', pg_temp.u(101), 'impersonation_session_id', pg_temp.u(9001))::text
$f$;

-- runners -------------------------------------------------------------------

create function pg_temp.run(p_claims text, p_role text, p_sql text, p_mode text default 'state')
returns text language plpgsql as $f$
declare
  v_out text;
  v_con text;
  v_msg text;
begin
  perform set_config('request.jwt.claims', coalesce(p_claims, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v_out;
  exception when others then
    get stacked diagnostics v_con = constraint_name, v_msg = message_text;
    v_out := 'err:' || sqlstate || case p_mode
      when 'con' then ':' || coalesce(v_con, '')
      when 'msg' then ':' || coalesce(v_msg, '')
      else '' end;
  end;
  set local role postgres;
  perform set_config('request.jwt.claims', '', true);
  return v_out;
end;
$f$;

create function pg_temp.dml(p_claims text, p_role text, p_sql text, p_mode text default 'state')
returns text language plpgsql as $f$
declare
  v_out text;
  v_con text;
  v_msg text;
  v_n bigint;
begin
  perform set_config('request.jwt.claims', coalesce(p_claims, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
    get diagnostics v_n = row_count;
    v_out := 'ok:' || v_n::text;
  exception when others then
    get stacked diagnostics v_con = constraint_name, v_msg = message_text;
    v_out := 'err:' || sqlstate || case p_mode
      when 'con' then ':' || coalesce(v_con, '')
      when 'msg' then ':' || coalesce(v_msg, '')
      else '' end;
  end;
  set local role postgres;
  perform set_config('request.jwt.claims', '', true);
  return v_out;
end;
$f$;

create function pg_temp.go(p_sql text) returns void language plpgsql as $f$
declare
  v_r text;
begin
  v_r := pg_temp.dml('', 'postgres', p_sql);
end;
$f$;

-- feature wrappers ----------------------------------------------------------

create function pg_temp.issue(p_claims text, p_member uuid, p_hash text, p_mode text default 'state', p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.run(p_claims, p_role,
    format($q$select count(*)::text || ':' || coalesce(string_agg(invite_id::text || '|' || coalesce(superseded_invite_id::text, '~') || '|' || extract(epoch from expires_at)::text, ';'), '') from public.issue_member_invite(%L, %L)$q$,
           p_member, p_hash), p_mode)
$f$;

create function pg_temp.revoke_inv(p_claims text, p_invite uuid, p_mode text default 'state', p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.run(p_claims, p_role, format($q$select public.revoke_member_invite(%L)::text$q$, p_invite), p_mode)
$f$;

create function pg_temp.redeem(p_claims text, p_hash text, p_mode text default 'state', p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.run(p_claims, p_role,
    format($q$select count(*)::text || ':' || coalesce(string_agg(outcome || '|' || coalesce(gym_name, '~'), ';'), '') from public.redeem_member_invite(%L)$q$,
           p_hash), p_mode)
$f$;

create function pg_temp.red(p_uk integer, p_hk integer) returns text language sql as $f$
  select pg_temp.redeem(pg_temp.c_plain(20000 + p_uk), pg_temp.h(p_hk))
$f$;

create function pg_temp.peek(p_role text, p_hash text, p_claims text default '') returns text language sql as $f$
  select pg_temp.run(p_claims, p_role,
    format($q$select count(*)::text || ':' || coalesce(string_agg(gym_name, ';'), '') from public.peek_member_invite(%L)$q$, p_hash))
$f$;

create function pg_temp.unlink_m(p_claims text, p_member uuid, p_reason text, p_mode text default 'state', p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.run(p_claims, p_role,
    format($q$select 'ok' from public.unlink_member_identity(%L, %L)$q$, p_member, p_reason), p_mode)
$f$;

create function pg_temp.rd(p_claims text, p_member uuid, p_cols text default 'state', p_role text default 'authenticated', p_mode text default 'state')
returns text language sql as $f$
  select pg_temp.run(p_claims, p_role,
    format($q$select count(*)::text || '#' || coalesce(string_agg((%s)::text, ';'), '') from public.read_member_app_access(%L)$q$,
           p_cols, p_member), p_mode)
$f$;

create function pg_temp.rdf(p_claims text, p_member uuid) returns text language sql as $f$
  select pg_temp.rd(p_claims, p_member,
    $q$state || '|' || coalesce(invite_id::text, '~') || '|' || coalesce(extract(epoch from issued_at)::text, '~') || '|' || coalesce(extract(epoch from expires_at)::text, '~') || '|' || coalesce(extract(epoch from linked_at)::text, '~')$q$)
$f$;

create function pg_temp.hook(p_user uuid) returns text language sql as $f$
  select pg_temp.run('', 'postgres', format(
    $q$select coalesce(x->>'app_role', '~') || '|' || coalesce(x->>'tenant_id', '~') || '|' || coalesce(x->>'member_id', '~') || '|' || coalesce(x->>'staff_id', '~')
         from (select (app.custom_access_token_hook(jsonb_build_object('user_id', %L::text, 'claims', jsonb_build_object('sub', %L::text, 'aud', 'authenticated', 'role', 'authenticated', 'session_id', %L::text))) -> 'claims') as x) y$q$,
    p_user, p_user, pg_temp.u(9100)))
$f$;

create function pg_temp.aud_call(p_action text) returns text language sql as $f$
  select format($q$select 'ok' from app.member_invite_audit(%L, %L, 'gym_owner', %L, 'member_invite', %L, null, null, null)$q$,
                pg_temp.u(107), pg_temp.u(2012), p_action, pg_temp.u(7777))
$f$;

-- audit counters --------------------------------------------------------------

create function pg_temp.audit_n() returns bigint language sql as $f$
  select count(*) from public.audit_log
   where action in ('member_invite.issued', 'member_invite.superseded', 'member_invite.revoked', 'member_invite.redeemed',
                    'member_invite.redeem_refused', 'member.linked', 'member.unlinked')
     and (tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g) or actor_user_id::text like '67900000-%')
$f$;

create function pg_temp.mark(p_k text) returns void language sql as $f$
  insert into pg_temp.h67_marks values (p_k, pg_temp.audit_n())
  on conflict (k) do update set v = excluded.v
$f$;

create function pg_temp.delta(p_k text) returns bigint language sql as $f$
  select pg_temp.audit_n() - (select v from pg_temp.h67_marks where k = p_k)
$f$;

create function pg_temp.iid(p_k integer) returns uuid language sql stable as $f$
  select id from public.member_invites where token_hash = pg_temp.h(p_k)
$f$;

-- fixture builders ------------------------------------------------------------

create function pg_temp.mk_user(p_n integer, p_email text, p_gmail text, p_confirmed boolean, p_prov boolean, p_eident boolean, p_google boolean)
returns void language plpgsql as $f$
begin
  insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data)
  values (pg_temp.u(p_n), p_email,
          case when p_confirmed then now() else null end,
          case when p_prov then '{"gymloop_provisioned": true}'::jsonb else '{}'::jsonb end);
  if p_google then
    insert into auth.identities (provider_id, user_id, identity_data, provider)
    values ('g67-' || p_n::text, pg_temp.u(p_n),
            jsonb_build_object('sub', 'g67-' || p_n::text, 'email', p_gmail, 'email_verified', true), 'google');
  end if;
  if p_eident then
    insert into auth.identities (provider_id, user_id, identity_data, provider)
    values ('e67-' || p_n::text, pg_temp.u(p_n),
            jsonb_build_object('sub', pg_temp.u(p_n)::text, 'email', coalesce(p_email, p_gmail), 'email_verified', true), 'email');
  end if;
end;
$f$;

create function pg_temp.scn(
  p_k integer,
  p_org integer default 101,
  p_memail text default 'auto',
  p_mstatus text default 'active',
  p_merased boolean default false,
  p_mbound uuid default null,
  p_inv text default 'pending',
  p_invuser uuid default null,
  p_gmail text default 'auto',
  p_aemail text default 'auto',
  p_confirmed boolean default true,
  p_prov boolean default false,
  p_eident boolean default false,
  p_google boolean default true,
  p_user boolean default true,
  p_dob date default null
) returns void language plpgsql as $f$
declare
  v_def text := 'm' || p_k::text || '@h67.example.test';
  v_staff integer := case p_org when 101 then 301 when 102 then 305 when 103 then 308 when 104 then 309
                          when 105 then 310 when 106 then 311 when 107 then 312 when 108 then 313 when 110 then 315 else 314 end;
begin
  if p_user then
    perform pg_temp.mk_user(20000 + p_k,
      case when p_aemail = 'auto' then v_def else p_aemail end,
      case when p_gmail = 'auto' then v_def else p_gmail end,
      p_confirmed, p_prov, p_eident, p_google);
  end if;
  insert into public.members (id, tenant_id, branch_id, user_id, full_name, phone, email, status, erased_at, date_of_birth)
  values (pg_temp.u(10000 + p_k), pg_temp.u(p_org), pg_temp.u(p_org + 10), p_mbound, 'Scn ' || p_k::text,
          '+9179' || lpad(p_k::text, 8, '0'),
          case when p_memail = 'auto' then v_def else p_memail end,
          p_mstatus::public.member_status,
          case when p_merased then now() else null end,
          p_dob);
  if p_inv <> 'none' then
    insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id,
                                       issued_at, expires_at, closed_at, closed_by_staff_id, redeemed_user_id)
    values (pg_temp.u(p_org), pg_temp.u(10000 + p_k), pg_temp.h(p_k),
            (case when p_inv = 'expired' then 'pending' else p_inv end)::public.member_invite_status,
            pg_temp.u(v_staff),
            case when p_inv = 'expired' then now() - interval '49 hours' else now() - interval '2 hours' end,
            case when p_inv = 'expired' then now() - interval '1 hour' else now() + interval '46 hours' end,
            case when p_inv in ('pending', 'expired') then null else now() - interval '1 hour' end,
            case when p_inv = 'revoked' then pg_temp.u(v_staff) else null end,
            case when p_inv = 'redeemed' then p_invuser else null end);
  end if;
end;
$f$;

create function pg_temp.ins(
  p_tenant uuid, p_member uuid, p_staff uuid, p_hash text,
  p_status text default 'pending',
  p_issued timestamptz default now() - interval '2 hours',
  p_expires timestamptz default now() + interval '46 hours',
  p_closed timestamptz default null,
  p_ruser uuid default null
) returns text language plpgsql as $f$
declare
  v_con text;
begin
  insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id,
                                     issued_at, expires_at, closed_at, redeemed_user_id)
  values (p_tenant, p_member, p_hash, p_status::public.member_invite_status, p_staff,
          p_issued, p_expires, p_closed, p_ruser);
  return 'ok';
exception when others then
  get stacked diagnostics v_con = constraint_name;
  return 'err:' || sqlstate || ':' || coalesce(v_con, '');
end;
$f$;

create function pg_temp.insv(
  p_tenant uuid, p_member uuid, p_staff uuid, p_hash text,
  p_status text default 'pending',
  p_issued timestamptz default now() - interval '2 hours',
  p_expires timestamptz default now() + interval '46 hours',
  p_closed timestamptz default null,
  p_ruser uuid default null
) returns void language plpgsql as $f$
begin
  perform pg_temp.ins(p_tenant, p_member, p_staff, p_hash, p_status, p_issued, p_expires, p_closed, p_ruser);
end;
$f$;

create function pg_temp.refs(p_user uuid, p_n integer, p_ago interval, p_action text default 'member_invite.redeem_refused')
returns void language sql as $f$
  insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, after, occurred_at)
  select null::uuid, p_user, 'member'::public.app_role, p_action, split_part(p_action, '.', 1), null::uuid,
         jsonb_build_object('outcome', 'invite_unavailable'), now() - p_ago - (g * interval '1 second')
    from generate_series(1, p_n) g
$f$;

create function pg_temp.g_ins(p_n integer, p_user uuid) returns text language sql as $f$
  select format($q$insert into public.members (id, tenant_id, branch_id, full_name, phone, user_id) values (%L, %L, %L, %L, %L, %L)$q$,
                pg_temp.u(11000 + p_n), pg_temp.u(101), pg_temp.u(111), 'Guard ' || p_n::text,
                '+9179' || lpad((5000 + p_n)::text, 8, '0'), p_user)
$f$;

-- ===========================================================================
-- SECTION A. catalog: the contract's shape (INV-017, INV-024, INV-003)
-- ===========================================================================

select has_table('public', 'member_invites', 'A INV-017 table public.member_invites exists');

select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e where e.enumtypid = to_regtype('public.member_invite_status')),
  array['pending', 'redeemed', 'revoked', 'superseded'],
  'A INV-003 member_invite_status holds pending, redeemed, revoked, superseded in that order');

select columns_are('public', 'member_invites',
  '{id,tenant_id,member_id,token_hash,status,issued_by_staff_id,issued_at,expires_at,closed_at,closed_by_staff_id,redeemed_user_id,created_at,updated_at}'::name[],
  'A INV-024 member_invites carries exactly the contract columns and no personal data column');

select is(
  (select string_agg(a.attname::text || ':' || t.typname::text || ':' || a.attnotnull::text, ',' order by a.attname::text collate "C")
     from pg_attribute a join pg_type t on t.oid = a.atttypid
    where a.attrelid = to_regclass('public.member_invites') and a.attnum > 0 and not a.attisdropped),
  'closed_at:timestamptz:false,closed_by_staff_id:uuid:false,created_at:timestamptz:true,expires_at:timestamptz:true,id:uuid:true,issued_at:timestamptz:true,issued_by_staff_id:uuid:true,member_id:uuid:true,redeemed_user_id:uuid:false,status:member_invite_status:true,tenant_id:uuid:true,token_hash:text:true,updated_at:timestamptz:true',
  'A INV-024 column types and nullability match the contract');

select is(
  (select count(*) from pg_constraint
    where conrelid = to_regclass('public.member_invites') and contype = 'c'
      and conname in ('member_invites_token_hash_format_chk', 'member_invites_expiry_chk', 'member_invites_closed_state_chk')),
  3::bigint,
  'A ADR-040 the three named check constraints exist');

select ok(
  exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
           where i.indrelid = to_regclass('public.member_invites') and c.relname = 'member_invites_token_hash_key'
             and i.indisunique and i.indnatts = 1 and i.indpred is null
             and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'token_hash'),
  'A INV-003 member_invites_token_hash_key is a global, total unique index on token_hash');

select ok(
  exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
           where i.indrelid = to_regclass('public.member_invites') and c.relname = 'member_invites_one_pending_key'
             and i.indisunique and i.indnatts = 2 and i.indpred is not null
             and pg_get_expr(i.indpred, i.indrelid) ~ 'pending'),
  'A INV-003 member_invites_one_pending_key is a partial unique index over two columns on pending');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'member_invites'
             and indexdef ~ '\(tenant_id, member_id, issued_at DESC\)'),
  'A index (tenant_id, member_id, issued_at desc) exists');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'member_invites'
             and indexdef ~ 'btree \(tenant_id, issued_at\)$'),
  'A index (tenant_id, issued_at) for the issue throttle exists');

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'audit_log'
             and indexdef ~ '\(actor_user_id, occurred_at\)' and indexdef ~ 'WHERE .*member_invite\.redeem_refused'),
  'A partial audit_log index on (actor_user_id, occurred_at) for redeem_refused exists');

select ok(
  exists (select 1 from pg_constraint
           where conrelid = to_regclass('public.member_invites') and contype = 'f'
             and confrelid = to_regclass('auth.users') and confdeltype = 'n'),
  'A INV-024 redeemed_user_id references auth.users on delete set null');

select ok(
  exists (select 1 from pg_constraint
           where conrelid = to_regclass('public.member_invites') and contype = 'f'
             and confrelid = to_regclass('public.members') and array_length(conkey, 1) = 2),
  'A ADR-052 composite foreign key (tenant_id, member_id) to members');

select ok(
  exists (select 1 from pg_constraint
           where conrelid = to_regclass('public.member_invites') and contype = 'f'
             and confrelid = to_regclass('public.staff') and array_length(conkey, 1) = 2),
  'A ADR-052 composite foreign key (tenant_id, issued_by_staff_id) to staff');

select ok(
  (select c.relrowsecurity and not c.relforcerowsecurity from pg_class c where c.oid = to_regclass('public.member_invites')),
  'A INV-017 row level security is enabled and not forced');

select ok(
  exists (select 1 from pg_policy where polrelid = to_regclass('public.member_invites') and polcmd = 'r'),
  'A INV-017 a select policy exists');

select ok(
  exists (select 1 from pg_policy where polrelid = to_regclass('public.member_invites'))
  and not exists (select 1 from pg_policy where polrelid = to_regclass('public.member_invites') and polcmd <> 'r'),
  'A INV-017 no policy permits an insert, update or delete');

select ok(
  has_table_privilege('authenticated', to_regclass('public.member_invites'), 'SELECT'),
  'A INV-017 authenticated holds select on member_invites');

select ok(
  not (has_table_privilege('authenticated', to_regclass('public.member_invites'), 'INSERT')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'UPDATE')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'DELETE')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'TRUNCATE')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'REFERENCES')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'TRIGGER')
    or has_table_privilege('authenticated', to_regclass('public.member_invites'), 'MAINTAIN')),
  'A INV-017 authenticated holds no table level write, truncate, references, trigger or maintain privilege');

select ok(
  not (has_any_column_privilege('authenticated', to_regclass('public.member_invites'), 'INSERT')
    or has_any_column_privilege('authenticated', to_regclass('public.member_invites'), 'UPDATE')
    or has_any_column_privilege('authenticated', to_regclass('public.member_invites'), 'REFERENCES')),
  'A INV-017 authenticated holds no column level insert, update or references privilege');

select ok(
  not (has_table_privilege('anon', to_regclass('public.member_invites'), 'SELECT')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'INSERT')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'UPDATE')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'DELETE')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'TRUNCATE')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'REFERENCES')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'TRIGGER')
    or has_table_privilege('anon', to_regclass('public.member_invites'), 'MAINTAIN')
    or has_any_column_privilege('anon', to_regclass('public.member_invites'), 'SELECT')
    or has_any_column_privilege('anon', to_regclass('public.member_invites'), 'INSERT')
    or has_any_column_privilege('anon', to_regclass('public.member_invites'), 'UPDATE')),
  'A ADR-037 anon holds no privilege of any kind on member_invites');

select ok(
  exists (select 1 from pg_trigger where tgrelid = to_regclass('public.member_invites')
             and tgname = 'member_invites_touch_updated_at' and not tgisinternal),
  'A the standard member_invites_touch_updated_at trigger exists');

select ok(
  exists (select 1 from pg_trigger where tgrelid = to_regclass('public.member_invites')
             and tgname = 'member_invites_preview_read_only' and not tgisinternal),
  'A the standard member_invites_preview_read_only trigger exists');

select ok(
  not exists (select 1 from pg_class s join pg_depend d on d.objid = s.oid
               where s.relkind = 'S' and d.refobjid = to_regclass('public.member_invites')),
  'A ADR-035 no sequence is owned by member_invites');

select ok(
  exists (select 1 from pg_trigger t
           where t.tgrelid = to_regclass('public.members') and t.tgname = 'members_auth_binding_invariant'
             and pg_get_triggerdef(t.oid) ~ 'BEFORE INSERT OR UPDATE OF user_id ON public\.members FOR EACH ROW EXECUTE FUNCTION app\.enforce_member_auth_binding\(\)'),
  'A INV-013 members_auth_binding_invariant is a before insert or update of user_id row trigger');

select ok(
  exists (select 1 from pg_proc p
           where p.pronamespace = to_regnamespace('app') and p.proname = 'enforce_member_auth_binding'
             and not p.prosecdef and p.prorettype = 'trigger'::regtype),
  'A INV-013 app.enforce_member_auth_binding is a security invoker trigger function');

select ok(
  exists (select 1 from pg_proc p
           where p.pronamespace = to_regnamespace('app') and p.proname = 'member_invite_actor'
             and pg_get_function_arguments(p.oid) = 'p_roles text[]' and not p.prosecdef),
  'A INV-001 app.member_invite_actor(p_roles text[]) exists as a security invoker helper');

select is(
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('issue_member_invite', 'revoke_member_invite', 'redeem_member_invite',
                      'peek_member_invite', 'unlink_member_identity', 'read_member_app_access')),
  6::bigint,
  'A INV-017 exactly six public member invite functions exist, with no overloads');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'issue_member_invite'),
  'p_member_id uuid, p_token_hash text => TABLE(invite_id uuid, expires_at timestamp with time zone, superseded_invite_id uuid)',
  'A INV-001 issue_member_invite signature and result columns');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'revoke_member_invite'),
  'p_invite_id uuid => uuid',
  'A INV-005 revoke_member_invite signature and result');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'redeem_member_invite'),
  'p_token_hash text => TABLE(outcome text, gym_name text)',
  'A INV-007 redeem_member_invite signature and result columns');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'peek_member_invite'),
  'p_token_hash text => TABLE(gym_name text)',
  'A INV-012 peek_member_invite returns the gym name and no other column');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'unlink_member_identity'),
  'p_member_id uuid, p_reason text => void',
  'A INV-014 unlink_member_identity signature and result');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'read_member_app_access'),
  'p_member_id uuid => TABLE(state text, invite_id uuid, issued_at timestamp with time zone, expires_at timestamp with time zone, linked_at timestamp with time zone)',
  'A INV-015 read_member_app_access signature and result columns');

select is(
  (select string_agg(regexp_replace(pg_get_function_arguments(p.oid), 'public\.', '', 'g') || ' => ' || pg_get_function_result(p.oid), ' ; ')
     from pg_proc p where p.pronamespace = to_regnamespace('app') and p.proname = 'member_invite_audit'),
  'p_tenant_id uuid, p_actor uuid, p_role app_role, p_action text, p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text => void',
  'A INV-016 app.member_invite_audit signature and result');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'issue_member_invite'),
  'A INV-017 issue_member_invite is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'revoke_member_invite'),
  'A INV-017 revoke_member_invite is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'redeem_member_invite'),
  'A INV-017 redeem_member_invite is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'peek_member_invite'),
  'A INV-017 peek_member_invite is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'unlink_member_identity'),
  'A INV-017 unlink_member_identity is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'read_member_app_access'),
  'A INV-017 read_member_app_access is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                                where split_part(cfg, '=', 1) = 'search_path' and split_part(cfg, '=', 2) in ('', '""')))
     from pg_proc p where p.pronamespace = to_regnamespace('app') and p.proname = 'member_invite_audit'),
  'A INV-016 app.member_invite_audit is security definer, owned by postgres, with an empty search_path');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'issue_member_invite'),
  'A INV-017 authenticated may execute issue_member_invite');

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'issue_member_invite'),
  'A INV-017 issue_member_invite is executable by neither anon, service_role nor PUBLIC');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'revoke_member_invite'),
  'A INV-017 authenticated may execute revoke_member_invite');

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'revoke_member_invite'),
  'A INV-017 revoke_member_invite is executable by neither anon, service_role nor PUBLIC');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'redeem_member_invite'),
  'A INV-017 authenticated may execute redeem_member_invite');

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'redeem_member_invite'),
  'A INV-017 redeem_member_invite is executable by neither anon, service_role nor PUBLIC');

select ok(
  (select bool_and(has_function_privilege('anon', p.oid, 'EXECUTE') and has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'peek_member_invite'),
  'A INV-012 anon and authenticated may both execute peek_member_invite');

select ok(
  (select bool_and(not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'peek_member_invite'),
  'A INV-017 peek_member_invite is executable by neither service_role nor PUBLIC');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'unlink_member_identity'),
  'A INV-017 authenticated may execute unlink_member_identity');

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'unlink_member_identity'),
  'A INV-017 unlink_member_identity is executable by neither anon, service_role nor PUBLIC');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'read_member_app_access'),
  'A INV-017 authenticated may execute read_member_app_access');

select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'read_member_app_access'),
  'A INV-017 read_member_app_access is executable by neither anon, service_role nor PUBLIC');

select ok(
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'EXECUTE')
                   and not has_function_privilege('anon', p.oid, 'EXECUTE')
                   and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                   and p.proacl is not null
                   and not exists (select 1 from unnest(p.proacl) a where a::text like '=%'))
     from pg_proc p where p.pronamespace = to_regnamespace('app') and p.proname = 'member_invite_audit'),
  'A INV-016 app.member_invite_audit is executable by nobody but its owner');

-- ===========================================================================
-- base fixtures: nine gyms, their staff, platform accounts
-- ===========================================================================

insert into public.organizations (id, name, gym_code, status, trial_ends_at) values
  (pg_temp.u(101), 'H67 Alpha Fitness',  'H67A01', 'active',           null),
  (pg_temp.u(102), 'H67 Beta Fitness',   'H67B02', 'active',           now() - interval '10 days'),
  (pg_temp.u(103), 'H67 Suspended Gym',  'H67S03', 'suspended',        null),
  (pg_temp.u(104), 'H67 Trial Gym',      'H67T04', 'trial',            now() + interval '30 days'),
  (pg_temp.u(105), 'H67 Expired Trial',  'H67E05', 'trial',            now() - interval '1 day'),
  (pg_temp.u(106), 'H67 Closed Gym',     'H67C06', 'closed',           null),
  (pg_temp.u(107), 'H67 Pending Gym',    'H67P07', 'pending_approval', null),
  (pg_temp.u(108), 'H67 Open Trial Gym', 'H67N08', 'trial',            null),
  (pg_temp.u(109), 'H67 Limit Gym',      'H67L09', 'active',           null),
  (pg_temp.u(110), 'H67 Flip Gym',       'H67F10', 'active',           null);

insert into public.organization_settings (tenant_id)
select pg_temp.u(g) from generate_series(101, 110) g;

insert into public.branches (id, tenant_id, name, is_default)
select pg_temp.u(g + 10), pg_temp.u(g), 'Main', true from generate_series(101, 110) g;

insert into auth.users (id, email, email_confirmed_at)
select pg_temp.u(n), 'staff' || n::text || '@h67.example.test', now()
  from unnest(array[2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2020, 2021, 2022]) n;

insert into public.staff (id, tenant_id, user_id, branch_id, role, full_name, is_active) values
  (pg_temp.u(301), pg_temp.u(101), pg_temp.u(2001), pg_temp.u(111), 'gym_owner',   'H67 Owner A',         true),
  (pg_temp.u(302), pg_temp.u(101), pg_temp.u(2002), pg_temp.u(111), 'gym_manager', 'H67 Manager A',       true),
  (pg_temp.u(303), pg_temp.u(101), pg_temp.u(2003), pg_temp.u(111), 'front_desk',  'H67 Desk A',          true),
  (pg_temp.u(304), pg_temp.u(101), pg_temp.u(2004), pg_temp.u(111), 'trainer',     'H67 Trainer A',       true),
  (pg_temp.u(305), pg_temp.u(102), pg_temp.u(2005), pg_temp.u(112), 'gym_owner',   'H67 Owner B',         true),
  (pg_temp.u(306), pg_temp.u(102), pg_temp.u(2006), pg_temp.u(112), 'front_desk',  'H67 Desk B',          true),
  (pg_temp.u(307), pg_temp.u(101), pg_temp.u(2007), pg_temp.u(111), 'front_desk',  'H67 Inactive Desk A', false),
  (pg_temp.u(308), pg_temp.u(103), pg_temp.u(2008), pg_temp.u(113), 'gym_owner',   'H67 Owner S',         true),
  (pg_temp.u(309), pg_temp.u(104), pg_temp.u(2009), pg_temp.u(114), 'gym_owner',   'H67 Owner T',         true),
  (pg_temp.u(310), pg_temp.u(105), pg_temp.u(2010), pg_temp.u(115), 'gym_owner',   'H67 Owner E',         true),
  (pg_temp.u(311), pg_temp.u(106), pg_temp.u(2011), pg_temp.u(116), 'gym_owner',   'H67 Owner C',         true),
  (pg_temp.u(312), pg_temp.u(107), pg_temp.u(2012), pg_temp.u(117), 'gym_owner',   'H67 Owner P',         true),
  (pg_temp.u(313), pg_temp.u(108), pg_temp.u(2013), pg_temp.u(118), 'gym_owner',   'H67 Owner N',         true),
  (pg_temp.u(314), pg_temp.u(109), pg_temp.u(2014), pg_temp.u(119), 'gym_owner',   'H67 Owner L',         true),
  (pg_temp.u(315), pg_temp.u(110), pg_temp.u(2015), pg_temp.u(120), 'gym_owner',   'H67 Owner F',         true);

insert into public.platform_users (user_id, role, full_name, email, is_active) values
  (pg_temp.u(2020), 'super_admin',      'H67 Root',    'root-h67@example.test',    true),
  (pg_temp.u(2021), 'platform_support', 'H67 Support', 'support-h67@example.test', true);

-- ===========================================================================
-- SECTION B. app.member_invite_audit: allowlist, shape, denial (INV-016)
-- ===========================================================================

select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.issued')), 'ok',
  'B INV-016 the audit helper accepts member_invite.issued');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.superseded')), 'ok',
  'B INV-016 the audit helper accepts member_invite.superseded');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.revoked')), 'ok',
  'B INV-016 the audit helper accepts member_invite.revoked');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.redeemed')), 'ok',
  'B INV-016 the audit helper accepts member_invite.redeemed');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.redeem_refused')), 'ok',
  'B INV-016 the audit helper accepts member_invite.redeem_refused');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member.linked')), 'ok',
  'B INV-016 the audit helper accepts member.linked');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member.unlinked')), 'ok',
  'B INV-016 the audit helper accepts member.unlinked');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member_invite.bogus')), 'err:22023',
  'B INV-016 an unknown member_invite verb raises 22023');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('payment.refunded')), 'err:22023',
  'B INV-016 a well formed action outside the seven raises 22023');
select is(pg_temp.run('', 'postgres', pg_temp.aud_call('member.linked2')), 'err:22023',
  'B INV-016 a near miss of an allowed action raises 22023');

select pg_temp.run('', 'postgres', format(
  $q$select 'ok' from app.member_invite_audit(%L, %L, 'gym_manager', 'member_invite.revoked', 'member_invite', %L, '{"status":"pending"}'::jsonb, '{"status":"revoked"}'::jsonb, 'h67 helper reason')$q$,
  pg_temp.u(107), pg_temp.u(2012), pg_temp.u(7778))) is null;

select is(
  (select count(*) from public.audit_log
    where record_id = pg_temp.u(7778) and tenant_id = pg_temp.u(107) and actor_user_id = pg_temp.u(2012)
      and actor_role = 'gym_manager' and action = 'member_invite.revoked' and record_type = 'member_invite'
      and before = '{"status":"pending"}'::jsonb and after = '{"status":"revoked"}'::jsonb
      and reason = 'h67 helper reason'),
  1::bigint,
  'B INV-016 the audit helper writes every argument it was given to the matching column');

select is(pg_temp.run(pg_temp.k_owner(), 'authenticated', pg_temp.aud_call('member_invite.issued')), 'err:42501',
  'B INV-017 an authenticated gym owner cannot call the audit helper');
select is(pg_temp.run('', 'anon', pg_temp.aud_call('member_invite.issued')), 'err:42501',
  'B INV-017 anon cannot call the audit helper');
select is(pg_temp.run('{"role":"service_role"}', 'service_role', pg_temp.aud_call('member_invite.issued')), 'err:42501',
  'B INV-017 service_role cannot call the audit helper');

-- ===========================================================================
-- SECTION C. table constraints by name, defaults, touch trigger
-- ===========================================================================

select pg_temp.scn(250, p_inv => 'none', p_user => false);
select pg_temp.scn(251, p_inv => 'none', p_user => false);
select pg_temp.scn(252, p_org => 102, p_inv => 'none', p_user => false);

select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(301), pg_temp.h(900)), 'ok',
  'C a well formed pending invite inserts');

select is(
  pg_temp.dml('', 'postgres', format(
    $q$insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, expires_at) values (%L, %L, %L, %L, now() + interval '47 hours')$q$,
    pg_temp.u(101), pg_temp.u(10251), pg_temp.h(901), pg_temp.u(301))),
  'ok:1',
  'C a minimal insert relies on column defaults');

select ok(
  (select status = 'pending' and id is not null and closed_at is null and closed_by_staff_id is null and redeemed_user_id is null
          and abs(extract(epoch from (issued_at - now()))) < 300 and created_at is not null and updated_at is not null
     from public.member_invites where token_hash = pg_temp.h(901)),
  'C defaults: status pending, generated id, issued_at near now, no closed or redeemed data');

select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), upper(pg_temp.h(902)), 'revoked', p_closed => now()),
  'err:23514:member_invites_token_hash_format_chk',
  'C ADR-040 an uppercase hex token hash violates member_invites_token_hash_format_chk');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), left(pg_temp.h(903), 63), 'revoked', p_closed => now()),
  'err:23514:member_invites_token_hash_format_chk',
  'C ADR-040 a 63 character token hash violates the format check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(904) || 'a', 'revoked', p_closed => now()),
  'err:23514:member_invites_token_hash_format_chk',
  'C ADR-040 a 65 character token hash violates the format check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), left(pg_temp.h(905), 63) || 'g', 'revoked', p_closed => now()),
  'err:23514:member_invites_token_hash_format_chk',
  'C ADR-040 a non hex character violates the format check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), '', 'revoked', p_closed => now()),
  'err:23514:member_invites_token_hash_format_chk',
  'C ADR-040 an empty token hash violates the format check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(907), 'revoked',
                      p_issued => now(), p_expires => now(), p_closed => now()),
  'err:23514:member_invites_expiry_chk',
  'C ADR-040 expires_at equal to issued_at violates member_invites_expiry_chk');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(908), 'revoked',
                      p_issued => now(), p_expires => now() - interval '1 hour', p_closed => now()),
  'err:23514:member_invites_expiry_chk',
  'C ADR-040 expires_at before issued_at violates the expiry check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(909), 'pending', p_closed => now()),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a pending invite with closed_at violates member_invites_closed_state_chk');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(910), 'revoked'),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a revoked invite without closed_at violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(911), 'superseded'),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a superseded invite without closed_at violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(912), 'redeemed', p_ruser => pg_temp.u(2001)),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a redeemed invite without closed_at violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(913), 'revoked',
                      p_closed => now(), p_ruser => pg_temp.u(2001)),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a revoked invite carrying redeemed_user_id violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(914), 'superseded',
                      p_closed => now(), p_ruser => pg_temp.u(2001)),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a superseded invite carrying redeemed_user_id violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(915), 'pending', p_ruser => pg_temp.u(2001)),
  'err:23514:member_invites_closed_state_chk',
  'C ADR-040 a pending invite carrying redeemed_user_id violates the closed state check');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(916), 'redeemed',
                      p_closed => now(), p_ruser => pg_temp.u(2001)),
  'ok',
  'C INV-007 a redeemed invite with its redeemed_user_id and closed_at is allowed');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(917), 'redeemed', p_closed => now()),
  'ok',
  'C ADR-176 a redeemed invite whose user was later deleted may carry a null redeemed_user_id');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(918), 'revoked', p_closed => now()),
  'ok',
  'C a revoked invite with closed_at is allowed beside the pending one for the same member');

select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10251), pg_temp.u(301), pg_temp.h(900), 'revoked', p_closed => now()),
  'err:23505:member_invites_token_hash_key',
  'C INV-003 a duplicate token hash is refused by member_invites_token_hash_key');
select is(pg_temp.ins(pg_temp.u(102), pg_temp.u(10252), pg_temp.u(305), pg_temp.h(900), 'revoked', p_closed => now()),
  'err:23505:member_invites_token_hash_key',
  'C INV-003 the token hash is unique across tenants, not per tenant');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(301), pg_temp.h(921)),
  'err:23505:member_invites_one_pending_key',
  'C INV-003 a second pending invite for one member is refused by member_invites_one_pending_key');
select is(pg_temp.dml('', 'postgres', format(
    $q$update public.member_invites set status = 'revoked', closed_at = now() where token_hash = %L$q$, pg_temp.h(900))),
  'ok:1',
  'C control: closing the pending invite succeeds');
select is(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(301), pg_temp.h(922)),
  'ok',
  'C INV-003 once the pending invite is closed a new pending invite is allowed');
select is(pg_temp.ins(pg_temp.u(102), pg_temp.u(10252), pg_temp.u(305), pg_temp.h(923)),
  'ok',
  'C INV-003 a pending invite for a different member is allowed');
select ok(left(pg_temp.ins(pg_temp.u(101), pg_temp.u(10252), pg_temp.u(301), pg_temp.h(924), 'revoked', p_closed => now()), 9) = 'err:23503',
  'C ADR-052 an invite cannot attach to another tenant member');
select ok(left(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(305), pg_temp.h(925), 'revoked', p_closed => now()), 9) = 'err:23503',
  'C ADR-052 an invite cannot name another tenant staff member as issuer');
select ok(left(pg_temp.ins(pg_temp.u(101), pg_temp.u(99999), pg_temp.u(301), pg_temp.h(926), 'revoked', p_closed => now()), 9) = 'err:23503',
  'C ADR-052 an invite for an unknown member is refused by the foreign key');
select ok(left(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(301), pg_temp.h(927), 'redeemed',
                           p_closed => now(), p_ruser => pg_temp.u(99998)), 9) = 'err:23503',
  'C INV-024 redeemed_user_id must reference an existing auth user');
select ok(left(pg_temp.ins(null, pg_temp.u(10250), pg_temp.u(301), pg_temp.h(928), 'revoked', p_closed => now()), 9) = 'err:23502',
  'C a null tenant_id is refused');
select ok(left(pg_temp.ins(pg_temp.u(101), pg_temp.u(10250), pg_temp.u(301), null, 'revoked', p_closed => now()), 9) = 'err:23502',
  'C a null token_hash is refused');

select pg_temp.go(format(
  $q$insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at, updated_at) values (%L, %L, %L, 'revoked', %L, now() - interval '3 hours', now() + interval '3 hours', now(), timestamptz '2020-01-01 00:00:00+00')$q$,
  pg_temp.u(101), pg_temp.u(10251), pg_temp.h(930), pg_temp.u(301)));
select pg_temp.go(format($q$update public.member_invites set closed_by_staff_id = %L where token_hash = %L$q$, pg_temp.u(301), pg_temp.h(930)));
select ok(
  (select updated_at > timestamptz '2020-06-01 00:00:00+00' from public.member_invites where token_hash = pg_temp.h(930)),
  'C the touch trigger moves updated_at forward on update');

-- ===========================================================================
-- SECTION D. members_auth_binding_invariant: GL074 (INV-013)
-- ===========================================================================

select pg_temp.scn(260, p_inv => 'none', p_mbound => pg_temp.u(20260));
select pg_temp.scn(261, p_inv => 'none');
select pg_temp.scn(262, p_inv => 'none');
select pg_temp.mk_user(20263, 'g263@h67.example.test', 'g263@h67.example.test', true, false, false, true);
select pg_temp.mk_user(20264, 'g264@h67.example.test', 'g264@h67.example.test', true, false, false, true);
select pg_temp.mk_user(20265, 'g265@h67.example.test', 'g265@h67.example.test', true, false, false, true);

select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated', pg_temp.g_ins(1, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a gym owner insert of a member with user_id is refused GL074');
select is(pg_temp.dml(pg_temp.k_mgr(), 'authenticated', pg_temp.g_ins(2, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a gym manager insert with user_id is refused GL074');
select is(pg_temp.dml(pg_temp.k_desk(), 'authenticated', pg_temp.g_ins(3, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a front desk insert with user_id is refused GL074');
select is(pg_temp.dml(pg_temp.k_trainer(), 'authenticated', pg_temp.g_ins(4, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a trainer insert with user_id is refused GL074 before any policy answers');
select is(pg_temp.dml(pg_temp.k_member(), 'authenticated', pg_temp.g_ins(5, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a member insert with user_id is refused GL074');
select is(pg_temp.dml(pg_temp.k_super(), 'authenticated', pg_temp.g_ins(6, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 a platform super admin insert with user_id is refused GL074');
select is(pg_temp.dml(pg_temp.k_plain(), 'authenticated', pg_temp.g_ins(7, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 an authenticated caller with no gym claims is refused GL074');
select ok(pg_temp.dml('', 'anon', pg_temp.g_ins(8, pg_temp.u(20262))) in ('err:42501', 'err:GL074'),
  'D INV-013 anon cannot insert a member with user_id');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated', pg_temp.g_ins(9, null)), 'ok:1',
  'D INV-013 control: an owner may still insert a member with a null user_id');
select is(pg_temp.dml('', 'postgres', pg_temp.g_ins(10, pg_temp.u(20263))), 'ok:1',
  'D INV-013 postgres may insert a member with user_id (definer commands, migrations, seed)');
select is(pg_temp.dml('{"role":"service_role"}', 'service_role', pg_temp.g_ins(11, pg_temp.u(20264))), 'ok:1',
  'D INV-013 service_role with no JWT subject may insert a bound member (operator provisioning)');
select is(pg_temp.dml(jsonb_build_object('role', 'service_role', 'sub', pg_temp.u(2001))::text, 'service_role', pg_temp.g_ins(12, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 service_role carrying a JWT subject is refused GL074');
select is(pg_temp.dml('{"role":"service_role"}', 'authenticated', pg_temp.g_ins(13, pg_temp.u(20262))), 'err:GL074',
  'D INV-013 the guard keys on the database role, not on a service_role claim');
select is(pg_temp.dml('', 'service_role', pg_temp.g_ins(14, pg_temp.u(20265))), 'ok:1',
  'D INV-013 service_role with no claims at all may insert a bound member');

select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.members set user_id = %L where id = %L$q$, pg_temp.u(20262), pg_temp.u(10261))), 'err:GL074',
  'D INV-013 an owner binding an unbound member by update is refused GL074');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.members set user_id = %L where id = %L$q$, pg_temp.u(20262), pg_temp.u(10260))), 'err:GL074',
  'D INV-013 an owner re-pointing a bound member to another user is refused GL074');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))), 'err:GL074',
  'D INV-013 an owner clearing user_id by update is refused GL074');
select ok(pg_temp.dml(pg_temp.k_mgr(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a manager cannot clear user_id');
select ok(pg_temp.dml(pg_temp.k_desk(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a front desk cannot clear user_id');
select ok(pg_temp.dml(pg_temp.k_trainer(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a trainer cannot clear user_id');
select ok(pg_temp.dml(pg_temp.k_member(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a member cannot clear user_id');
select ok(pg_temp.dml(pg_temp.k_super(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a platform super admin cannot clear user_id');
select ok(pg_temp.dml(pg_temp.k_plain(), 'authenticated',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'ok:0'),
  'D INV-013 a caller with no gym claims cannot clear user_id');
select ok(pg_temp.dml('', 'anon',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))) in ('err:GL074', 'err:42501'),
  'D INV-013 anon cannot clear user_id');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.members set user_id = user_id where id = %L$q$, pg_temp.u(10260))), 'ok:1',
  'D INV-013 an update that leaves user_id unchanged is not refused');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.members set full_name = 'Guard Renamed' where id = %L$q$, pg_temp.u(10260))), 'ok:1',
  'D INV-013 an owner may still edit other member columns');
select is(pg_temp.dml('', 'postgres',
  format($q$update public.members set user_id = %L where id = %L$q$, pg_temp.u(20262), pg_temp.u(10261))), 'ok:1',
  'D INV-013 postgres may bind a member by update');
select is(pg_temp.dml('', 'postgres',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10261))), 'ok:1',
  'D INV-013 postgres may clear a binding by update');
select is(pg_temp.dml('{"role":"service_role"}', 'service_role',
  format($q$update public.members set user_id = %L where id = %L$q$, pg_temp.u(20262), pg_temp.u(10261))), 'ok:1',
  'D INV-013 service_role with no subject may bind by update');
select pg_temp.go(format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10261)));
select is(pg_temp.dml(jsonb_build_object('role', 'service_role', 'sub', pg_temp.u(2001))::text, 'service_role',
  format($q$update public.members set user_id = null where id = %L$q$, pg_temp.u(10260))), 'err:GL074',
  'D INV-013 service_role carrying a subject cannot clear a binding by update');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$insert into public.members (id, tenant_id, branch_id, full_name, phone) values (%L, %L, %L, 'Scn 261', '+917900000261') on conflict (id) do update set user_id = %L$q$,
         pg_temp.u(10261), pg_temp.u(101), pg_temp.u(111), pg_temp.u(20262))), 'err:GL074',
  'D INV-013 an upsert whose update branch sets user_id is refused GL074');
select is((select user_id from public.members where id = pg_temp.u(10260)), pg_temp.u(20260),
  'D INV-013 after every attempt the bound member still points at its original user');
select is((select user_id from public.members where id = pg_temp.u(10261)), null::uuid,
  'D INV-013 after every attempt the unbound member is still unbound');

-- ===========================================================================
-- SECTION E. issue_member_invite (INV-001, 002, 003, 004, 006, 016)
-- ===========================================================================

select pg_temp.scn(200, p_inv => 'none', p_user => false);
select pg_temp.scn(201, p_inv => 'none', p_user => false);
select pg_temp.scn(202, p_inv => 'none', p_user => false);
select pg_temp.scn(203, p_inv => 'none', p_user => false);
select pg_temp.scn(204, p_inv => 'none', p_user => false, p_mstatus => 'paused');
select pg_temp.scn(205, p_inv => 'none', p_user => false, p_mstatus => 'expired');
select pg_temp.scn(206, p_inv => 'none', p_user => false, p_dob => (current_date - interval '10 years')::date);
select pg_temp.scn(207, p_inv => 'none', p_user => false);
select pg_temp.scn(210, p_inv => 'none', p_user => false, p_mstatus => 'cancelled');
select pg_temp.scn(211, p_inv => 'none', p_user => false, p_mstatus => 'blocked');
select pg_temp.scn(212, p_inv => 'none', p_user => false, p_merased => true);
select pg_temp.scn(213, p_inv => 'none', p_user => false, p_memail => null);
select pg_temp.scn(214, p_inv => 'none', p_user => false, p_memail => '');
select pg_temp.scn(215, p_inv => 'none', p_user => false, p_memail => '   ');
select pg_temp.scn(216, p_inv => 'none', p_user => false, p_memail => 'plain');
select pg_temp.scn(217, p_inv => 'none', p_user => false, p_memail => 'a@b');
select pg_temp.scn(218, p_inv => 'none', p_user => false, p_memail => '@b.co');
select pg_temp.scn(219, p_inv => 'none', p_user => false, p_memail => 'a@b@c.co');
select pg_temp.scn(220, p_inv => 'none', p_user => false, p_memail => 'a b@c.co');
select pg_temp.scn(221, p_inv => 'none', p_user => false, p_memail => 'a@b c.co');
select pg_temp.scn(222, p_inv => 'none', p_mbound => pg_temp.u(20222));
select pg_temp.scn(225, p_org => 103, p_inv => 'none', p_user => false);
select pg_temp.scn(226, p_org => 105, p_inv => 'none', p_user => false);
select pg_temp.scn(227, p_org => 106, p_inv => 'none', p_user => false);
select pg_temp.scn(228, p_org => 107, p_inv => 'none', p_user => false);
select pg_temp.scn(229, p_org => 108, p_inv => 'none', p_user => false);
select pg_temp.scn(230, p_org => 104, p_inv => 'none', p_user => false);
select pg_temp.scn(231, p_org => 102, p_inv => 'none', p_user => false);
select pg_temp.scn(232, p_org => 102, p_inv => 'none', p_user => false);
select pg_temp.scn(233, p_org => 102, p_inv => 'none', p_mbound => pg_temp.u(20233));
select pg_temp.scn(235, p_inv => 'none');
select pg_temp.scn(236, p_inv => 'expired', p_user => false);
select pg_temp.scn(237, p_inv => 'revoked', p_user => false);
select pg_temp.scn(238, p_inv => 'redeemed', p_invuser => pg_temp.u(20238));
select pg_temp.scn(240, p_inv => 'none', p_user => false);
select pg_temp.scn(241, p_inv => 'none', p_user => false);
select pg_temp.scn(245, p_user => false);
select pg_temp.scn(246, p_user => false);
select pg_temp.scn(247, p_inv => 'none', p_user => false);

-- E1. every caller that must be refused 42501, and nothing is written ------------

select pg_temp.mark('e1');
select is(pg_temp.issue(pg_temp.k_trainer(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 a trainer is refused 42501');
select is(pg_temp.issue(pg_temp.k_member(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 a member session is refused 42501');
select is(pg_temp.issue(pg_temp.k_super(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 a platform super admin is refused 42501');
select is(pg_temp.issue(pg_temp.k_super_t(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 a platform super admin holding the gym tenant claim is still refused 42501');
select is(pg_temp.issue(pg_temp.k_support(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 platform support is refused 42501');
select is(pg_temp.issue(pg_temp.k_imp(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a real owner staff claim carrying an impersonation id is refused 42501');
select is(pg_temp.issue(pg_temp.k_imp2(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a preview shaped owner claim with no staff id is refused 42501');
select is(pg_temp.issue(pg_temp.k_inactive(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 an inactive front desk staff row is refused 42501');
select is(pg_temp.issue(pg_temp.k_ownerb(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-002 the owner of another gym is refused 42501');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(99999), pg_temp.h(2100)), 'err:42501',
  'E INV-002 an unknown member id is refused 42501');
select is(pg_temp.issue(pg_temp.c_staff(2001, 'gym_owner', 102, 301), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a tenant claim that does not match the staff row is refused 42501');
select is(pg_temp.issue(pg_temp.c_staff(2001, 'gym_owner', 101, 305), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a staff id from another gym is refused 42501');
select is(pg_temp.issue(pg_temp.c_staff(2005, 'gym_owner', 101, 301), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a subject that is not the staff row user is refused 42501');
select is(pg_temp.issue(pg_temp.c_staff(2003, 'gym_owner', 101, 303), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a role claim that does not match the staff row role is refused 42501');
select is(pg_temp.issue(pg_temp.c_add(pg_temp.k_owner(), jsonb_build_object('member_id', pg_temp.u(10260))), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a staff claim that also carries a member id is refused 42501');
select is(pg_temp.issue(pg_temp.c_drop(pg_temp.k_owner(), 'sub'), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a staff claim with no subject is refused 42501');
select is(pg_temp.issue(pg_temp.k_plain(), pg_temp.u(10200), pg_temp.h(2100)), 'err:42501',
  'E INV-001 a signed in caller with no gym claims is refused 42501');
select is(pg_temp.issue('', pg_temp.u(10200), pg_temp.h(2100), p_role => 'anon'), 'err:42501',
  'E INV-017 anon cannot execute issue_member_invite');
select is(pg_temp.issue('{"role":"service_role"}', pg_temp.u(10200), pg_temp.h(2100), p_role => 'service_role'), 'err:42501',
  'E INV-017 service_role cannot execute issue_member_invite');
select ok(pg_temp.issue(pg_temp.k_owner(), null, pg_temp.h(2100)) in ('err:42501', 'err:22023'),
  'E INV-002 a null member id is refused');
select is(pg_temp.delta('e1'), 0::bigint,
  'E INV-016 refused issues write no audit row');
select is((select count(*) from public.member_invites where member_id = pg_temp.u(10200)), 0::bigint,
  'E INV-002 refused issues create no invite');

select is(
  pg_temp.nouuid(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10232), pg_temp.h(2100), 'msg')),
  pg_temp.nouuid(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(99999), pg_temp.h(2100), 'msg')),
  'E INV-002 a member of another gym and an unknown id are indistinguishable even by message');
select is(
  pg_temp.nouuid(pg_temp.issue(pg_temp.k_trainer(), pg_temp.u(10200), pg_temp.h(2100), 'msg')),
  pg_temp.nouuid(pg_temp.issue(pg_temp.k_trainer(), pg_temp.u(99999), pg_temp.h(2100), 'msg')),
  'E INV-002 a forbidden role learns nothing about whether the member id exists');

-- E2. success for each real front office role ------------------------------------

select pg_temp.mark('e2a');
insert into h67_res values ('iss201', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10201), pg_temp.h(2001)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss201'),
  'E INV-001 an owner issues an invite and receives exactly one row with no superseded id');
select ok(
  (select split_part(split_part(r.v, ':', 2), '|', 1) = i.id::text and split_part(r.v, '|', 3) = extract(epoch from i.expires_at)::text
     from h67_res r, public.member_invites i where r.k = 'iss201' and i.token_hash = pg_temp.h(2001)),
  'E INV-001 the returned invite_id and expires_at match the stored row');
select is(
  (select count(*) from public.member_invites
    where token_hash = pg_temp.h(2001) and tenant_id = pg_temp.u(101) and member_id = pg_temp.u(10201)
      and status = 'pending' and closed_at is null and closed_by_staff_id is null and redeemed_user_id is null
      and issued_by_staff_id = pg_temp.u(301)),
  1::bigint,
  'E INV-001 the stored invite is pending, unclosed, unredeemed, names the issuing staff and stores the hash given');
select ok(
  (select (expires_at - issued_at) between interval '47 hours 55 minutes' and interval '48 hours 5 minutes'
     from public.member_invites where token_hash = pg_temp.h(2001)),
  'E INV-001 the invite expires 48 hours after issue');
select is(pg_temp.delta('e2a'), 1::bigint,
  'E INV-016 a plain issue writes exactly one audit row');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.issued' and tenant_id = pg_temp.u(101) and actor_user_id = pg_temp.u(2001)
      and actor_role = 'gym_owner' and impersonation_session_id is null and record_type = 'member_invite'
      and record_id = pg_temp.iid(2001)),
  1::bigint,
  'E INV-016 member_invite.issued is attributed to the owner with tenant, role and invite id');
select ok(
  (select bool_and((a.after->>'member_id') = pg_temp.u(10201)::text
                   and pg_temp.ts(a.after->>'expires_at') = i.expires_at
                   and (a.after->>'superseded_invite_id') is null
                   and (a.after - 'member_id' - 'expires_at' - 'superseded_invite_id') = '{}'::jsonb)
     from public.audit_log a, public.member_invites i
    where a.action = 'member_invite.issued' and a.record_id = i.id and i.token_hash = pg_temp.h(2001)),
  'E INV-016 the issued audit after-image is exactly member_id, expires_at, superseded_invite_id');

select pg_temp.mark('e2b');
insert into h67_res values ('iss202', pg_temp.issue(pg_temp.k_mgr(), pg_temp.u(10202), pg_temp.h(2002)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss202'),
  'E INV-001 a manager issues an invite');
select is(
  (select count(*) from public.member_invites
    where token_hash = pg_temp.h(2002) and status = 'pending' and issued_by_staff_id = pg_temp.u(302) and tenant_id = pg_temp.u(101)),
  1::bigint,
  'E INV-001 the manager invite names the manager as issuer');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.issued' and actor_user_id = pg_temp.u(2002) and actor_role = 'gym_manager'
      and record_id = pg_temp.iid(2002)),
  1::bigint,
  'E INV-016 the manager issue is audited with role gym_manager');

insert into h67_res values ('iss203', pg_temp.issue(pg_temp.k_desk(), pg_temp.u(10203), pg_temp.h(2003)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss203'),
  'E INV-001 a front desk member issues an invite');
select is(
  (select count(*) from public.member_invites
    where token_hash = pg_temp.h(2003) and status = 'pending' and issued_by_staff_id = pg_temp.u(303)),
  1::bigint,
  'E INV-001 the front desk invite names the front desk member as issuer');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.issued' and actor_user_id = pg_temp.u(2003) and actor_role = 'front_desk'
      and record_id = pg_temp.iid(2003)),
  1::bigint,
  'E INV-016 the front desk issue is audited with role front_desk');

insert into h67_res values ('iss204', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10204), pg_temp.h(2004)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss204') and exists (select 1 from public.member_invites where token_hash = pg_temp.h(2004) and status = 'pending'),
  'E INV-002 a paused member is invitable');
insert into h67_res values ('iss205', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10205), pg_temp.h(2005)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss205') and exists (select 1 from public.member_invites where token_hash = pg_temp.h(2005) and status = 'pending'),
  'E INV-002 a member whose status is expired is invitable');
insert into h67_res values ('iss206', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10206), pg_temp.h(2006)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss206') and exists (select 1 from public.member_invites where token_hash = pg_temp.h(2006) and status = 'pending'),
  'E INV-002 a member under 18 is not specially blocked');
insert into h67_res values ('iss230', pg_temp.issue(pg_temp.c_staff(2009, 'gym_owner', 104, 309), pg_temp.u(10230), pg_temp.h(2300)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss230') and exists (select 1 from public.member_invites where token_hash = pg_temp.h(2300) and status = 'pending'),
  'E INV-002 a trial gym inside its trial window is eligible');
insert into h67_res values ('iss231', pg_temp.issue(pg_temp.k_ownerb(), pg_temp.u(10231), pg_temp.h(2301)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss231') and exists (select 1 from public.member_invites where token_hash = pg_temp.h(2301) and status = 'pending'),
  'E INV-002 an active gym is eligible even with a past trial_ends_at');

-- E3. member and gym states, email, linked ---------------------------------------

select pg_temp.mark('e3');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10210), pg_temp.h(2110)), 'err:GL075',
  'E INV-002 a cancelled member cannot be invited GL075');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10211), pg_temp.h(2111)), 'err:GL075',
  'E INV-002 a blocked member cannot be invited GL075');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10212), pg_temp.h(2112)), 'err:GL075',
  'E INV-002 an erased member cannot be invited GL075');
select is(pg_temp.issue(pg_temp.c_staff(2008, 'gym_owner', 103, 308), pg_temp.u(10225), pg_temp.h(2125)), 'err:GL075',
  'E INV-002 a suspended gym is not eligible GL075');
select is(pg_temp.issue(pg_temp.c_staff(2010, 'gym_owner', 105, 310), pg_temp.u(10226), pg_temp.h(2126)), 'err:GL075',
  'E INV-002 a trial gym past trial_ends_at is not eligible GL075');
select is(pg_temp.issue(pg_temp.c_staff(2011, 'gym_owner', 106, 311), pg_temp.u(10227), pg_temp.h(2127)), 'err:GL075',
  'E INV-002 a closed gym is not eligible GL075');
select is(pg_temp.issue(pg_temp.c_staff(2012, 'gym_owner', 107, 312), pg_temp.u(10228), pg_temp.h(2128)), 'err:GL075',
  'E INV-002 a gym pending approval is not eligible GL075');
select is(pg_temp.issue(pg_temp.c_staff(2013, 'gym_owner', 108, 313), pg_temp.u(10229), pg_temp.h(2129)), 'err:GL075',
  'E INV-002 a trial gym with no trial_ends_at is not eligible GL075');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10213), pg_temp.h(2113)), 'err:GL076',
  'E INV-002 a member with no email is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10214), pg_temp.h(2114)), 'err:GL076',
  'E INV-002 a member with an empty email is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10215), pg_temp.h(2115)), 'err:GL076',
  'E INV-002 a member with a blank email is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10216), pg_temp.h(2116)), 'err:GL076',
  'E INV-002 an email with no at sign is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10217), pg_temp.h(2117)), 'err:GL076',
  'E INV-002 an email whose domain has no dot is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10218), pg_temp.h(2118)), 'err:GL076',
  'E INV-002 an email with an empty local part is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10219), pg_temp.h(2119)), 'err:GL076',
  'E INV-002 an email with two at signs is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10220), pg_temp.h(2120)), 'err:GL076',
  'E INV-002 an email with whitespace in the local part is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10221), pg_temp.h(2121)), 'err:GL076',
  'E INV-002 an email with whitespace in the domain is refused GL076');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10222), pg_temp.h(2122)), 'err:GL077',
  'E INV-002 a member who already has a user_id is refused GL077');
select is(pg_temp.delta('e3'), 0::bigint,
  'E INV-006 every refused issue writes no audit row');
select is(
  (select count(*) from public.member_invites
    where member_id in (pg_temp.u(10210), pg_temp.u(10211), pg_temp.u(10212), pg_temp.u(10213), pg_temp.u(10214), pg_temp.u(10215),
                        pg_temp.u(10216), pg_temp.u(10217), pg_temp.u(10218), pg_temp.u(10219), pg_temp.u(10220), pg_temp.u(10221),
                        pg_temp.u(10222), pg_temp.u(10225), pg_temp.u(10226), pg_temp.u(10227), pg_temp.u(10228), pg_temp.u(10229))),
  0::bigint,
  'E INV-006 every refused issue creates no invite');

-- E4. resend: supersede in the same transaction -----------------------------------

insert into h67_res values ('iss235a', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10235), pg_temp.h(2351)));
select pg_temp.mark('e4');
insert into h67_res values ('iss235b', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10235), pg_temp.h(2352)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss235a'),
  'E INV-003 the first issue for a member reports no superseded invite');
select is(
  (select split_part(split_part(b.v, ':', 2), '|', 2) from h67_res b where b.k = 'iss235b'),
  (select split_part(split_part(a.v, ':', 2), '|', 1) from h67_res a where a.k = 'iss235a'),
  'E INV-003 the second issue returns the first invite id as superseded_invite_id');
select ok(
  (select status = 'superseded' and closed_at is not null and redeemed_user_id is null from public.member_invites where token_hash = pg_temp.h(2351)),
  'E INV-003 the old invite is superseded with closed_at set');
select ok(
  (select status = 'pending' and closed_at is null from public.member_invites where token_hash = pg_temp.h(2352)),
  'E INV-003 the new invite is pending');
select is(
  (select count(*) from public.member_invites where member_id = pg_temp.u(10235) and status = 'pending'),
  1::bigint,
  'E INV-003 exactly one pending invite remains for the member');
select is(pg_temp.delta('e4'), 2::bigint,
  'E INV-016 a resend writes exactly two audit rows, issued and superseded');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.superseded' and record_id = pg_temp.iid(2351) and tenant_id = pg_temp.u(101)
      and actor_user_id = pg_temp.u(2001) and actor_role = 'gym_owner' and record_type = 'member_invite'
      and before = '{"status":"pending"}'::jsonb
      and after = jsonb_build_object('status', 'superseded', 'replaced_by', pg_temp.iid(2352)::text)),
  1::bigint,
  'E INV-016 member_invite.superseded carries before pending and after superseded with replaced_by');
select ok(
  (select bool_and((a.after->>'superseded_invite_id') = pg_temp.iid(2351)::text)
     from public.audit_log a where a.action = 'member_invite.issued' and a.record_id = pg_temp.iid(2352)),
  'E INV-016 the second issued audit row names the superseded invite');

-- an already expired pending invite is superseded too
select pg_temp.mark('e5');
insert into h67_res values ('iss236', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10236), pg_temp.h(2361)));
select ok(
  (select split_part(split_part(v, ':', 2), '|', 2) = pg_temp.iid(236)::text from h67_res where k = 'iss236'),
  'E INV-003 an already expired pending invite is the one superseded');
select ok(
  (select status = 'superseded' and closed_at is not null from public.member_invites where token_hash = pg_temp.h(236)),
  'E INV-003 the expired pending invite is now superseded');
select is(pg_temp.delta('e5'), 2::bigint,
  'E INV-016 superseding an expired invite still writes issued and superseded');

-- a closed invite is not superseded
select pg_temp.mark('e6');
insert into h67_res values ('iss237', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10237), pg_temp.h(2371)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss237'),
  'E INV-003 issuing after a revoked invite reports no superseded id');
select ok(
  (select status = 'revoked' from public.member_invites where token_hash = pg_temp.h(237)),
  'E INV-003 the earlier revoked invite is left as revoked');
select is(pg_temp.delta('e6'), 1::bigint,
  'E INV-016 issuing after a closed invite writes only the issued row');
insert into h67_res values ('iss238', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10238), pg_temp.h(2381)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss238')
          and (select status = 'redeemed' from public.member_invites where token_hash = pg_temp.h(238)),
  'E INV-003 re-inviting a member whose earlier invite was redeemed leaves that record redeemed');

-- E5. atomicity and hash validation -----------------------------------------------

select pg_temp.mark('e7');
select ok(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10245), pg_temp.h(246)) like 'err:%',
  'E INV-003 reusing another invite token hash fails');
select ok(
  (select status = 'pending' and closed_at is null from public.member_invites where token_hash = pg_temp.h(245)),
  'E INV-003 the failed resend did not supersede the existing pending invite');
select is(pg_temp.delta('e7'), 0::bigint,
  'E INV-016 the failed resend wrote no audit row');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10247), upper(pg_temp.h(2470))), 'err:22023',
  'E INV-002 an uppercase token hash is malformed input 22023');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10247), left(pg_temp.h(2471), 63)), 'err:22023',
  'E INV-002 a 63 character token hash is malformed input 22023');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10247), pg_temp.h(2472) || 'a'), 'err:22023',
  'E INV-002 a 65 character token hash is malformed input 22023');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10247), ''), 'err:22023',
  'E INV-002 an empty token hash is malformed input 22023');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10247), null), 'err:22023',
  'E INV-002 a null token hash is malformed input 22023');
select is((select count(*) from public.member_invites where member_id = pg_temp.u(10247)), 0::bigint,
  'E INV-002 malformed hashes create no invite');

-- E6. limits ------------------------------------------------------------------

select pg_temp.insv(pg_temp.u(101), pg_temp.u(10240), pg_temp.u(301), pg_temp.h(2400), 'revoked',
  now() - interval '3 hours', now() + interval '45 hours', now() - interval '2 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10240), pg_temp.u(301), pg_temp.h(2401), 'revoked',
  now() - interval '4 hours', now() + interval '44 hours', now() - interval '3 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10240), pg_temp.u(301), pg_temp.h(2402), 'superseded',
  now() - interval '5 hours', now() + interval '43 hours', now() - interval '4 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10240), pg_temp.u(301), pg_temp.h(2403), 'superseded',
  now() - interval '6 hours', now() + interval '42 hours', now() - interval '5 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10240), pg_temp.u(301), pg_temp.h(2404), 'redeemed',
  now() - interval '7 hours', now() + interval '41 hours', now() - interval '6 hours');

select pg_temp.mark('e8');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10240), pg_temp.h(2405)), 'err:GL078',
  'E INV-006 a member with 5 invites in the rolling 24 hours is refused GL078 whatever their status');
select is((select count(*) from public.member_invites where member_id = pg_temp.u(10240)), 5::bigint,
  'E INV-006 the member limit refusal writes no invite');
select is(pg_temp.delta('e8'), 0::bigint,
  'E INV-006 the member limit refusal writes no audit row');

select pg_temp.insv(pg_temp.u(101), pg_temp.u(10241), pg_temp.u(301), pg_temp.h(2410), 'revoked',
  now() - interval '3 hours', now() + interval '45 hours', now() - interval '2 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10241), pg_temp.u(301), pg_temp.h(2411), 'revoked',
  now() - interval '4 hours', now() + interval '44 hours', now() - interval '3 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10241), pg_temp.u(301), pg_temp.h(2412), 'revoked',
  now() - interval '5 hours', now() + interval '43 hours', now() - interval '4 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10241), pg_temp.u(301), pg_temp.h(2413), 'superseded',
  now() - interval '6 hours', now() + interval '42 hours', now() - interval '5 hours');
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10241), pg_temp.u(301), pg_temp.h(2414), 'revoked',
  now() - interval '25 hours', now() - interval '1 hour', now() - interval '24 hours');

insert into h67_res values ('iss241a', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10241), pg_temp.h(2415)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss241a'),
  'E INV-006 4 invites in the last 24 hours plus one older than 24 hours still allows the fifth');
select pg_temp.mark('e9');
select is(pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10241), pg_temp.h(2416)), 'err:GL078',
  'E INV-006 the next issue is refused GL078 once 5 fall inside the window');
select ok(
  (select status = 'pending' from public.member_invites where token_hash = pg_temp.h(2415))
  and not exists (select 1 from public.member_invites where token_hash = pg_temp.h(2416)),
  'E INV-006 the refused resend left the pending invite pending and created nothing');
select is(pg_temp.delta('e9'), 0::bigint,
  'E INV-006 the refused resend wrote no audit row');

insert into public.members (id, tenant_id, branch_id, full_name, phone, email)
select pg_temp.u(10300 + g), pg_temp.u(109), pg_temp.u(119), 'Limit ' || g::text,
       '+9179' || lpad((300 + g)::text, 8, '0'), 'lim' || g::text || '@h67.example.test'
  from generate_series(0, 102) g;

insert into public.member_invites (tenant_id, member_id, token_hash, status, issued_by_staff_id, issued_at, expires_at, closed_at)
select pg_temp.u(109), pg_temp.u(10300 + g), pg_temp.h(3000 + g), 'revoked'::public.member_invite_status, pg_temp.u(314),
       now() - interval '10 minutes', now() + interval '47 hours', now() - interval '5 minutes'
  from generate_series(0, 99) g;

select pg_temp.mark('e10');
select is(pg_temp.issue(pg_temp.k_ownerl(), pg_temp.u(10400), pg_temp.h(3100)), 'err:GL078',
  'E INV-006 a gym with 100 invites issued in the rolling hour is refused GL078');
select is((select count(*) from public.member_invites where member_id = pg_temp.u(10400)), 0::bigint,
  'E INV-006 the gym limit refusal creates no invite');
select is(pg_temp.delta('e10'), 0::bigint,
  'E INV-006 the gym limit refusal writes no audit row');
select pg_temp.go(format(
  $q$update public.member_invites set issued_at = now() - interval '61 minutes', expires_at = now() + interval '47 hours' where token_hash = %L$q$,
  pg_temp.h(3000)));
insert into h67_res values ('iss400', pg_temp.issue(pg_temp.k_ownerl(), pg_temp.u(10400), pg_temp.h(3101)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss400'),
  'E INV-006 with only 99 issues inside the rolling hour the hundredth is allowed');
select is(pg_temp.issue(pg_temp.k_ownerl(), pg_temp.u(10401), pg_temp.h(3102)), 'err:GL078',
  'E INV-006 the next issue for a different member is refused GL078 once 100 fall inside the hour');
select is((select count(*) from public.member_invites where member_id = pg_temp.u(10401)), 0::bigint,
  'E INV-006 the second gym limit refusal creates no invite');
insert into h67_res values ('iss207', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10207), pg_temp.h(2007)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss207'),
  'E INV-006 another gym is unaffected while one gym is at its hourly limit');

-- ===========================================================================
-- SECTION F. revoke_member_invite (INV-005)
-- ===========================================================================

select pg_temp.scn(280);
select pg_temp.scn(281, p_user => false);
select pg_temp.scn(282, p_user => false);
select pg_temp.scn(283, p_inv => 'expired', p_user => false);
select pg_temp.scn(284, p_inv => 'revoked', p_user => false);
select pg_temp.scn(285, p_inv => 'superseded', p_user => false);
select pg_temp.scn(286, p_inv => 'redeemed', p_invuser => pg_temp.u(20286));
select pg_temp.scn(287, p_user => false);
select pg_temp.scn(288, p_org => 102, p_user => false);

select pg_temp.mark('f1');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(280)), pg_temp.iid(280)::text,
  'F INV-005 an owner revokes a pending invite and receives its id');
select ok(
  (select status = 'revoked' and closed_at is not null and closed_by_staff_id = pg_temp.u(301) and redeemed_user_id is null
     from public.member_invites where token_hash = pg_temp.h(280)),
  'F INV-005 the invite is revoked with closed_at and closed_by_staff_id set');
select is(pg_temp.delta('f1'), 1::bigint,
  'F INV-016 a revoke writes exactly one audit row');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.revoked' and record_id = pg_temp.iid(280) and tenant_id = pg_temp.u(101)
      and actor_user_id = pg_temp.u(2001) and actor_role = 'gym_owner' and record_type = 'member_invite'
      and before = '{"status":"pending"}'::jsonb and after = '{"status":"revoked"}'::jsonb),
  1::bigint,
  'F INV-016 member_invite.revoked carries before pending and after revoked');
select is(pg_temp.red(280, 280), '1:invite_unavailable|~',
  'F INV-005 a revoked token never redeems even though it has not expired');
select pg_temp.mark('f1b');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(280)), 'err:GL079',
  'F INV-005 revoking an already revoked invite fails GL079');
select is(pg_temp.delta('f1b'), 0::bigint,
  'F INV-005 a refused revoke writes no audit row');

select is(pg_temp.revoke_inv(pg_temp.k_mgr(), pg_temp.iid(281)), pg_temp.iid(281)::text,
  'F INV-005 a manager revokes a pending invite');
select ok(
  (select status = 'revoked' and closed_by_staff_id = pg_temp.u(302) from public.member_invites where token_hash = pg_temp.h(281)),
  'F INV-005 the manager is recorded as the closer');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.revoked' and record_id = pg_temp.iid(281) and actor_user_id = pg_temp.u(2002) and actor_role = 'gym_manager'),
  1::bigint,
  'F INV-016 the manager revoke is audited with role gym_manager');
select is(pg_temp.revoke_inv(pg_temp.k_desk(), pg_temp.iid(282)), pg_temp.iid(282)::text,
  'F INV-005 a front desk member revokes a pending invite');
select ok(
  (select status = 'revoked' and closed_by_staff_id = pg_temp.u(303) from public.member_invites where token_hash = pg_temp.h(282)),
  'F INV-005 the front desk member is recorded as the closer');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(283)), pg_temp.iid(283)::text,
  'F INV-005 a pending invite that has already expired is still pending by status and can be revoked');

select pg_temp.mark('f2');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(284)), 'err:GL079',
  'F INV-005 a revoked invite cannot be revoked GL079');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(285)), 'err:GL079',
  'F INV-005 a superseded invite cannot be revoked GL079');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(286)), 'err:GL079',
  'F INV-005 a redeemed invite cannot be revoked GL079');
select is(
  (select count(*) from public.member_invites
    where (token_hash = pg_temp.h(284) and status = 'revoked')
       or (token_hash = pg_temp.h(285) and status = 'superseded')
       or (token_hash = pg_temp.h(286) and status = 'redeemed')),
  3::bigint,
  'F INV-005 refused revokes leave the closed invites unchanged');
select is(pg_temp.delta('f2'), 0::bigint,
  'F INV-005 refused revokes write no audit row');

select pg_temp.mark('f3');
select is(pg_temp.revoke_inv(pg_temp.k_trainer(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 a trainer cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_member(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 a member cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_super(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 a platform super admin cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_support(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 platform support cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_imp(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 an impersonating owner cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_imp2(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 a preview shaped owner claim cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_inactive(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 an inactive staff row cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_ownerb(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 the owner of another gym cannot revoke');
select is(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.u(99999)), 'err:42501',
  'F INV-005 an unknown invite id is refused 42501');
select is(pg_temp.revoke_inv(pg_temp.k_plain(), pg_temp.iid(287)), 'err:42501',
  'F INV-005 a signed in caller with no gym claims cannot revoke');
select is(pg_temp.revoke_inv('', pg_temp.iid(287), p_role => 'anon'), 'err:42501',
  'F INV-017 anon cannot execute revoke_member_invite');
select is(pg_temp.revoke_inv('{"role":"service_role"}', pg_temp.iid(287), p_role => 'service_role'), 'err:42501',
  'F INV-017 service_role cannot execute revoke_member_invite');
select ok(pg_temp.revoke_inv(pg_temp.k_owner(), null) in ('err:42501', 'err:22023'),
  'F INV-005 a null invite id is refused');
select ok(
  (select status = 'pending' and closed_at is null from public.member_invites where token_hash = pg_temp.h(287)),
  'F INV-005 every refused revoke left the invite pending');
select is(pg_temp.delta('f3'), 0::bigint,
  'F INV-005 every refused revoke wrote no audit row');
select is(
  pg_temp.nouuid(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.iid(288), 'msg')),
  pg_temp.nouuid(pg_temp.revoke_inv(pg_temp.k_owner(), pg_temp.u(99999), 'msg')),
  'F INV-005 another gym invite and an unknown id are indistinguishable even by message');

-- ===========================================================================
-- SECTION G. peek_member_invite (INV-012)
-- ===========================================================================

select pg_temp.scn(170, p_user => false);
select pg_temp.scn(171, p_org => 102, p_user => false);
select pg_temp.scn(172, p_org => 104, p_user => false);
select pg_temp.scn(173, p_user => false, p_mstatus => 'paused');
select pg_temp.scn(174, p_user => false, p_mstatus => 'expired');
select pg_temp.scn(176, p_inv => 'expired', p_user => false);
select pg_temp.scn(177, p_inv => 'revoked', p_user => false);
select pg_temp.scn(178, p_inv => 'superseded', p_user => false);
select pg_temp.scn(179, p_inv => 'redeemed', p_invuser => pg_temp.u(20179));
select pg_temp.scn(181, p_user => false, p_mstatus => 'blocked');
select pg_temp.scn(182, p_user => false, p_merased => true);
select pg_temp.scn(183, p_mbound => pg_temp.u(20183));
select pg_temp.scn(184, p_org => 103, p_user => false);
select pg_temp.scn(185, p_org => 106, p_user => false);
select pg_temp.scn(186, p_org => 107, p_user => false);
select pg_temp.scn(187, p_org => 105, p_user => false);
select pg_temp.scn(188, p_org => 108, p_user => false);
select pg_temp.scn(189, p_user => false, p_mstatus => 'cancelled');

insert into h67_res
select 'peek_before', count(*)::text from public.member_invites
 where tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g);
select pg_temp.mark('g1');

select is(pg_temp.peek('anon', pg_temp.h(170)), '1:H67 Alpha Fitness',
  'G INV-012 a signed out caller sees only the gym name of a valid invite');
select is(pg_temp.peek('authenticated', pg_temp.h(170), pg_temp.k_plain()), '1:H67 Alpha Fitness',
  'G INV-012 a signed in caller with no gym claims sees the gym name');
select is(pg_temp.peek('authenticated', pg_temp.h(170), pg_temp.k_ownerb()), '1:H67 Alpha Fitness',
  'G INV-012 staff of another gym can peek, which is the public accept page');
select is(pg_temp.peek('anon', pg_temp.h(171)), '1:H67 Beta Fitness',
  'G INV-012 an active gym with a past trial_ends_at is eligible');
select is(pg_temp.peek('anon', pg_temp.h(172)), '1:H67 Trial Gym',
  'G INV-012 a trial gym inside its trial window is eligible');
select is(pg_temp.peek('anon', pg_temp.h(173)), '1:H67 Alpha Fitness',
  'G INV-012 a paused member is invitable-status');
select is(pg_temp.peek('anon', pg_temp.h(174)), '1:H67 Alpha Fitness',
  'G INV-012 a member whose status is expired is invitable-status');
select is(pg_temp.peek('anon', pg_temp.h(9175)), '0:',
  'G INV-012 an unknown token returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(176)), '0:',
  'G INV-004 INV-012 an expired invite returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(177)), '0:',
  'G INV-012 a revoked invite returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(178)), '0:',
  'G INV-012 a superseded invite returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(179)), '0:',
  'G INV-012 a redeemed invite returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(189)), '0:',
  'G INV-012 a cancelled member returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(181)), '0:',
  'G INV-012 a blocked member returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(182)), '0:',
  'G INV-012 an erased member returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(183)), '0:',
  'G INV-012 a member that is already bound returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(184)), '0:',
  'G INV-012 a suspended gym returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(185)), '0:',
  'G INV-012 a closed gym returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(186)), '0:',
  'G INV-012 a gym pending approval returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(187)), '0:',
  'G INV-012 a trial gym past its trial returns zero rows');
select is(pg_temp.peek('anon', pg_temp.h(188)), '0:',
  'G INV-012 a trial gym with no trial end returns zero rows');
select is(pg_temp.peek('service_role', pg_temp.h(170), '{"role":"service_role"}'), 'err:42501',
  'G INV-017 service_role cannot execute peek_member_invite');
select is(pg_temp.peek('anon', upper(pg_temp.h(170))), 'err:22023',
  'G INV-012 an uppercase hash raises 22023');
select is(pg_temp.peek('anon', left(pg_temp.h(170), 63)), 'err:22023',
  'G INV-012 a 63 character hash raises 22023');
select is(pg_temp.peek('anon', pg_temp.h(170) || 'a'), 'err:22023',
  'G INV-012 a 65 character hash raises 22023');
select is(pg_temp.peek('anon', ''), 'err:22023',
  'G INV-012 an empty hash raises 22023');
select is(pg_temp.peek('anon', null), 'err:22023',
  'G INV-012 a null hash raises 22023');
select is(pg_temp.peek('anon', pg_temp.h(170) || E'\n'), 'err:22023',
  'G INV-012 a valid hash followed by a newline raises 22023');
select is(pg_temp.peek('anon', ' ' || left(pg_temp.h(170), 63)), 'err:22023',
  'G INV-012 a hash with a leading space raises 22023');
select is(pg_temp.delta('g1'), 0::bigint,
  'G INV-012 peek writes no audit row');
select is(
  (select count(*) from public.member_invites where tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g)),
  (select v::bigint from h67_res where k = 'peek_before'),
  'G INV-012 peek changes no invite row');

-- ===========================================================================
-- SECTION H. redeem: happy paths and the email rules (INV-007)
-- ===========================================================================

select pg_temp.scn(1, p_inv => 'none');
select pg_temp.scn(2, p_inv => 'none');
select pg_temp.scn(3, p_memail => 'm1@h67.example.test');
select pg_temp.scn(4, p_memail => '  Mixed.Case4@H67.Example.TEST  ', p_gmail => 'mixed.case4@h67.example.test');
select pg_temp.scn(5, p_memail => 'lower5@h67.example.test', p_gmail => 'LoWeR5@H67.Example.Test');
select pg_temp.scn(6, p_memail => 'old6@h67.example.test', p_gmail => 'old6@h67.example.test');
select pg_temp.mk_user(20606, 'u20606@h67.example.test', 'new6@h67.example.test', true, false, false, true);
select pg_temp.go(format($q$update public.members set email = 'new6@h67.example.test' where id = %L$q$, pg_temp.u(10006)));
select pg_temp.scn(7, p_dob => (current_date - interval '10 years')::date);
select pg_temp.scn(8, p_mstatus => 'paused');
select pg_temp.scn(9, p_mstatus => 'expired');
select pg_temp.scn(10, p_org => 104);
select pg_temp.scn(11, p_org => 102);
select pg_temp.scn(12, p_aemail => 'different12@h67.example.test');
select pg_temp.scn(13, p_prov => true, p_eident => true);

insert into h67_res values ('iss1', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10001), pg_temp.h(1)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss1'),
  'H INV-007 setup: the owner issued the invite for member 1');
select is(pg_temp.peek('anon', pg_temp.h(1)), '1:H67 Alpha Fitness',
  'H INV-012 the pending invite is visible to peek before redemption');

insert into h67_res select 'adv_before', count(*)::text from pg_locks where locktype = 'advisory' and pid = pg_backend_pid();
select pg_temp.mark('h1');
select is(pg_temp.red(1, 1), '1:linked|H67 Alpha Fitness',
  'H INV-007 a verified Google account whose email matches links the member and returns the gym name');
select ok((select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid())
          > (select v::bigint from h67_res where k = 'adv_before'),
  'H INV-007 redeem takes a transaction scoped advisory lock for the Auth user');
select is((select user_id from public.members where id = pg_temp.u(10001)), pg_temp.u(20001),
  'H INV-007 members.user_id is the redeeming Auth user');
select ok(
  (select status = 'redeemed' and redeemed_user_id = pg_temp.u(20001) and closed_at is not null and closed_by_staff_id is null
     from public.member_invites where token_hash = pg_temp.h(1)),
  'H INV-007 the invite is redeemed with redeemed_user_id and closed_at, and no closing staff');
select is(pg_temp.delta('h1'), 2::bigint,
  'H INV-016 a successful redeem writes exactly two audit rows');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeemed' and tenant_id = pg_temp.u(101) and actor_user_id = pg_temp.u(20001)
      and actor_role = 'member' and record_type = 'member_invite' and record_id = pg_temp.iid(1)
      and before = '{"status":"pending"}'::jsonb
      and after = jsonb_build_object('status', 'redeemed', 'member_id', pg_temp.u(10001)::text)),
  1::bigint,
  'H INV-016 member_invite.redeemed is attributed to the redeemer as role member with the contract shapes');
select is(
  (select count(*) from public.audit_log
    where action = 'member.linked' and tenant_id = pg_temp.u(101) and actor_user_id = pg_temp.u(20001)
      and actor_role = 'member' and record_type = 'member' and record_id = pg_temp.u(10001)
      and before = '{"user_linked":false}'::jsonb
      and after = jsonb_build_object('user_linked', true, 'via', 'invite', 'invite_id', pg_temp.iid(1)::text)),
  1::bigint,
  'H INV-016 member.linked carries user_linked false to true, via invite and the invite id');
select is(pg_temp.hook(pg_temp.u(20001)), 'member|' || pg_temp.u(101)::text || '|' || pg_temp.u(10001)::text || '|~',
  'H INV-007 the access token hook mints member claims for the newly linked user');
select pg_temp.mark('h1p');
select is(pg_temp.red(1, 1), '1:already_linked_here|H67 Alpha Fitness',
  'H INV-009 the same account presenting the same token again gets already_linked_here');
select is(pg_temp.delta('h1p'), 0::bigint,
  'H INV-009 an idempotent replay writes nothing');
select is(pg_temp.peek('anon', pg_temp.h(1)), '0:',
  'H INV-012 a redeemed invite returns zero rows from peek');
select is(pg_temp.red(2, 1), '1:invite_unavailable|~',
  'H INV-009 any other account presenting a redeemed token gets invite_unavailable');
select is(pg_temp.red(1, 3), '1:account_already_linked|~',
  'H INV-011 an account that is already a member cannot link to a second member even with a matching email');
select ok(
  (select user_id is null from public.members where id = pg_temp.u(10003))
  and (select status = 'pending' from public.member_invites where token_hash = pg_temp.h(3)),
  'H INV-011 the refused second link bound nothing and left the invite pending');

select is(pg_temp.red(4, 4), '1:linked|H67 Alpha Fitness',
  'H INV-007 the email match trims whitespace on the member side and ignores case');
select is(pg_temp.red(5, 5), '1:linked|H67 Alpha Fitness',
  'H INV-007 the email match ignores case on the Google side');
select is(pg_temp.red(6, 6), '1:email_mismatch|~',
  'H INV-007 an email edited after issue is compared by its current value: the old address no longer matches');
select is(pg_temp.red(606, 6), '1:linked|H67 Alpha Fitness',
  'H INV-007 the account matching the edited address links and the refusal did not burn the invite');
select is(pg_temp.red(7, 7), '1:linked|H67 Alpha Fitness',
  'H INV-007 a member under 18 links like any other member');
select is(pg_temp.red(8, 8), '1:linked|H67 Alpha Fitness',
  'H INV-007 a paused member is bindable');
select is(pg_temp.red(9, 9), '1:linked|H67 Alpha Fitness',
  'H INV-007 a member whose status is expired is bindable');
select is(pg_temp.red(10, 10), '1:linked|H67 Trial Gym',
  'H INV-007 a trial gym inside its trial window is eligible');
select is(pg_temp.red(11, 11), '1:linked|H67 Beta Fitness',
  'H INV-007 an active gym with a past trial_ends_at is eligible');
select is(pg_temp.red(12, 12), '1:linked|H67 Alpha Fitness',
  'H INV-007 the Google identity email is what is compared, not auth.users.email');
select is(pg_temp.red(13, 13), '1:linked|H67 Alpha Fitness',
  'H INV-007 an operator provisioned account with an email identity and a Google identity is verified');

-- state flipped after a real issue: redeem re-checks the member and the gym
select pg_temp.scn(94, p_inv => 'none');
select pg_temp.scn(95, p_inv => 'none');
select pg_temp.scn(96, p_inv => 'none');
select pg_temp.scn(97, p_org => 110, p_inv => 'none');
insert into h67_res values ('iss94', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10094), pg_temp.h(9401)));
insert into h67_res values ('iss95', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10095), pg_temp.h(9501)));
insert into h67_res values ('iss96', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10096), pg_temp.h(9601)));
insert into h67_res values ('iss97', pg_temp.issue(pg_temp.c_staff(2015, 'gym_owner', 110, 315), pg_temp.u(10097), pg_temp.h(9701)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss94'),
  'H INV-008 setup: an invite was issued to a member who is then cancelled');
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss95'),
  'H INV-008 setup: an invite was issued to a member who is then blocked');
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss96'),
  'H INV-008 setup: an invite was issued to a member who is then erased');
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss97'),
  'H INV-008 setup: an invite was issued in a gym that is then suspended');
select pg_temp.go(format($q$update public.members set status = 'cancelled' where id = %L$q$, pg_temp.u(10094)));
select pg_temp.go(format($q$update public.members set status = 'blocked' where id = %L$q$, pg_temp.u(10095)));
select pg_temp.go(format($q$update public.members set erased_at = now() where id = %L$q$, pg_temp.u(10096)));
select pg_temp.go(format($q$update public.organizations set status = 'suspended' where id = %L$q$, pg_temp.u(110)));
select is(pg_temp.red(94, 9401), '1:invite_unavailable|~',
  'H INV-008 a member cancelled after issue can no longer redeem');
select is(pg_temp.red(95, 9501), '1:invite_unavailable|~',
  'H INV-008 a member blocked after issue can no longer redeem');
select is(pg_temp.red(96, 9601), '1:invite_unavailable|~',
  'H INV-008 a member erased after issue can no longer redeem');
select is(pg_temp.red(97, 9701), '1:invite_unavailable|~',
  'H INV-008 a gym suspended after issue stops redemption');
select is(pg_temp.peek('anon', pg_temp.h(9701)), '0:',
  'H INV-012 peek shows nothing for an invite whose gym was suspended after issue');
-- ADR-098 fixture import: this scenario tests invite eligibility restoration,
-- not platform activation readiness. Restore the already-active imported gym
-- under postgres with triggers temporarily disabled, leaving the same member,
-- Auth identity and pending unexpired invite untouched. Return to origin before
-- invoking redemption so all production enforcement applies to the retry.
set local session_replication_role = replica;
update public.organizations set status = 'active' where id = pg_temp.u(110);
set local session_replication_role = origin;
select is((select status::text from public.organizations where id = pg_temp.u(110)),
  'active',
  'H INV-008 setup: the gym eligibility fixture is actually restored before retrying the same invite');
select is(pg_temp.red(97, 9701), '1:linked|H67 Flip Gym',
  'H INV-008 once the gym is active again the same unexpired invite redeems, so the refusal did not burn it');

-- ===========================================================================
-- SECTION I. redeem refusals: no oracle, check order, D1 (INV-008, INV-011)
-- ===========================================================================

select pg_temp.mk_user(20124, 'other24@h67.example.test', 'other24@h67.example.test', true, false, false, true);
select pg_temp.mk_user(20134, 'other34@h67.example.test', 'other34@h67.example.test', true, false, false, true);
select pg_temp.scn(20, p_inv => 'none');
select pg_temp.scn(21, p_inv => 'expired');
select pg_temp.scn(22, p_inv => 'revoked');
select pg_temp.scn(23, p_inv => 'superseded');
select pg_temp.scn(24, p_inv => 'redeemed', p_invuser => pg_temp.u(20124), p_mbound => pg_temp.u(20124));
select pg_temp.scn(25, p_inv => 'redeemed', p_invuser => pg_temp.u(20025));
select pg_temp.scn(26, p_mstatus => 'cancelled');
select pg_temp.scn(27, p_mstatus => 'blocked');
select pg_temp.scn(28, p_merased => true);
select pg_temp.scn(29, p_org => 103);
select pg_temp.scn(30, p_org => 106);
select pg_temp.scn(31, p_org => 107);
select pg_temp.scn(32, p_org => 105);
select pg_temp.scn(33, p_org => 108);
select pg_temp.scn(34, p_mbound => pg_temp.u(20134));
select pg_temp.scn(35, p_mbound => pg_temp.u(20035));

select pg_temp.mark('i1');
select is(pg_temp.red(20, 9020), '1:invite_unavailable|~',
  'I INV-008 an unknown token is invite_unavailable with no gym name');
select is(pg_temp.red(21, 21), '1:invite_unavailable|~',
  'I INV-004 INV-008 an expired token is invite_unavailable');
select is(pg_temp.red(22, 22), '1:invite_unavailable|~',
  'I INV-008 a revoked token is invite_unavailable');
select is(pg_temp.red(23, 23), '1:invite_unavailable|~',
  'I INV-008 a superseded token is invite_unavailable');
select is(pg_temp.red(24, 24), '1:invite_unavailable|~',
  'I INV-008 a token redeemed by someone else is invite_unavailable');
select is(pg_temp.red(25, 25), '1:invite_unavailable|~',
  'I INV-009 the original redeemer presenting the token after the member was unlinked is invite_unavailable');
select is(pg_temp.red(26, 26), '1:invite_unavailable|~',
  'I INV-008 a cancelled member is invite_unavailable');
select is(pg_temp.red(27, 27), '1:invite_unavailable|~',
  'I INV-008 a blocked member is invite_unavailable');
select is(pg_temp.red(28, 28), '1:invite_unavailable|~',
  'I INV-008 an erased member is invite_unavailable');
select is(pg_temp.red(29, 29), '1:invite_unavailable|~',
  'I INV-008 a suspended gym is invite_unavailable');
select is(pg_temp.red(30, 30), '1:invite_unavailable|~',
  'I INV-008 a closed gym is invite_unavailable');
select is(pg_temp.red(31, 31), '1:invite_unavailable|~',
  'I INV-008 a gym pending approval is invite_unavailable');
select is(pg_temp.red(32, 32), '1:invite_unavailable|~',
  'I INV-008 a trial gym past its trial is invite_unavailable');
select is(pg_temp.red(33, 33), '1:invite_unavailable|~',
  'I INV-008 a trial gym with no trial end is invite_unavailable');
select is(pg_temp.red(34, 34), '1:invite_unavailable|~',
  'I INV-008 a member row already bound to someone else is invite_unavailable');
select is(pg_temp.red(35, 35), '1:invite_unavailable|~',
  'I INV-008 a member row already bound to the caller with a pending invite is invite_unavailable');
select is(pg_temp.delta('i1'), 16::bigint,
  'I INV-008 each of the 16 refusals writes exactly one audit row');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id between pg_temp.u(20020) and pg_temp.u(20035)
      and after = '{"outcome":"invite_unavailable"}'::jsonb),
  16::bigint,
  'I INV-008 every refusal row records after = {outcome} and nothing else');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id = pg_temp.u(20020) and tenant_id is null),
  1::bigint,
  'I INV-008 the refusal for an unresolvable token has a null tenant');
select is(
  (select count(*) from public.members where user_id between pg_temp.u(20020) and pg_temp.u(20035) and id <> pg_temp.u(10035)),
  0::bigint,
  'I INV-008 the refusals bound no member');
select is(
  (select count(*) from public.audit_log
    where action in ('member_invite.redeemed', 'member.linked') and actor_user_id between pg_temp.u(20020) and pg_temp.u(20035)),
  0::bigint,
  'I INV-008 the refusals wrote no redeemed or linked row');
select is(
  (select count(*) from public.member_invites
    where token_hash in (pg_temp.h(26), pg_temp.h(27), pg_temp.h(28), pg_temp.h(29), pg_temp.h(30), pg_temp.h(31),
                         pg_temp.h(32), pg_temp.h(33), pg_temp.h(34), pg_temp.h(35)) and status = 'pending'),
  10::bigint,
  'I INV-008 refusals left every still pending invite pending');

-- identity, email and D1 batteries
select pg_temp.scn(40, p_confirmed => false);
select pg_temp.scn(41, p_google => false, p_eident => true);
select pg_temp.scn(42, p_eident => true);
select pg_temp.scn(43, p_prov => true, p_confirmed => false);
select pg_temp.scn(44, p_prov => true, p_google => false, p_eident => true);
select pg_temp.scn(45, p_google => false);
select pg_temp.scn(46, p_gmail => 'other46@h67.example.test');
select pg_temp.scn(47, p_memail => 'a47+tag@h67.example.test', p_gmail => 'a47@h67.example.test');
select pg_temp.scn(48, p_memail => 'dot.ted48@h67.example.test', p_gmail => 'dotted48@h67.example.test');
select pg_temp.scn(49, p_memail => 'a_c49@h67.example.test', p_gmail => 'abc49@h67.example.test');
select pg_temp.scn(50, p_memail => '%@h67.example.test', p_gmail => 'anything50@h67.example.test');
select pg_temp.scn(51, p_memail => 'xx51@h67.example.test', p_gmail => 'x51@h67.example.test');
select pg_temp.scn(52, p_memail => null);
select pg_temp.scn(53, p_memail => '   ');
select pg_temp.scn(56);
select pg_temp.scn(156, p_org => 102, p_mbound => pg_temp.u(20056), p_inv => 'none', p_user => false);
select pg_temp.scn(57);
select pg_temp.scn(157, p_mbound => pg_temp.u(20057), p_inv => 'none', p_user => false);
select pg_temp.scn(58);
select pg_temp.scn(59);
select pg_temp.scn(60);
select pg_temp.scn(61);
select pg_temp.scn(62);
select pg_temp.scn(162, p_org => 102, p_mstatus => 'cancelled', p_mbound => pg_temp.u(20062), p_inv => 'none', p_user => false);
select pg_temp.scn(64, p_confirmed => false, p_gmail => 'other64@h67.example.test');
select pg_temp.scn(65, p_gmail => 'other65@h67.example.test');
select pg_temp.scn(66, p_confirmed => false);
select pg_temp.scn(67, p_mstatus => 'cancelled', p_confirmed => false);
select pg_temp.scn(68, p_mstatus => 'cancelled', p_gmail => 'other68@h67.example.test');
select pg_temp.scn(69, p_org => 103);
insert into public.staff (id, tenant_id, user_id, branch_id, role, full_name, is_active) values
  (pg_temp.u(320), pg_temp.u(102), pg_temp.u(20058), pg_temp.u(112), 'front_desk', 'H67 Staffer 58', true),
  (pg_temp.u(321), pg_temp.u(102), pg_temp.u(20059), pg_temp.u(112), 'front_desk', 'H67 Staffer 59', false),
  (pg_temp.u(322), pg_temp.u(102), pg_temp.u(20065), pg_temp.u(112), 'front_desk', 'H67 Staffer 65', true),
  (pg_temp.u(323), pg_temp.u(102), pg_temp.u(20066), pg_temp.u(112), 'front_desk', 'H67 Staffer 66', true),
  (pg_temp.u(324), pg_temp.u(102), pg_temp.u(20069), pg_temp.u(112), 'front_desk', 'H67 Staffer 69', true);
insert into public.platform_users (user_id, role, full_name, email, is_active) values
  (pg_temp.u(20060), 'platform_support', 'H67 Platform 60', 'plat60-h67@example.test', true),
  (pg_temp.u(20061), 'super_admin',      'H67 Platform 61', 'plat61-h67@example.test', false);

select pg_temp.mark('i2');
select is(pg_temp.red(40, 40), '1:identity_unverified|~',
  'I INV-008 an unconfirmed email is identity_unverified');
select is(pg_temp.red(41, 41), '1:identity_unverified|~',
  'I INV-008 an account with only an email identity and no Google identity is identity_unverified');
select is(pg_temp.red(42, 42), '1:identity_unverified|~',
  'I INV-008 a Google identity beside a password email identity on a self registered account is identity_unverified');
select is(pg_temp.red(43, 43), '1:identity_unverified|~',
  'I INV-008 the provisioned flag does not excuse an unconfirmed email');
select is(pg_temp.red(44, 44), '1:identity_unverified|~',
  'I INV-008 the provisioned flag does not excuse a missing Google identity');
select is(pg_temp.red(45, 45), '1:identity_unverified|~',
  'I INV-008 an account with no identities at all is identity_unverified');
select is(pg_temp.red(46, 46), '1:email_mismatch|~',
  'I INV-008 a Google identity of a different address is email_mismatch even when auth.users.email matches');
select is(pg_temp.red(47, 47), '1:email_mismatch|~',
  'I INV-008 plus addressing is not normalised');
select is(pg_temp.red(48, 48), '1:email_mismatch|~',
  'I INV-008 dots in the local part are not normalised');
select is(pg_temp.red(49, 49), '1:email_mismatch|~',
  'I INV-008 an underscore in the member email is not a wildcard');
select is(pg_temp.red(50, 50), '1:email_mismatch|~',
  'I INV-008 a percent sign in the member email is not a wildcard');
select is(pg_temp.red(51, 51), '1:email_mismatch|~',
  'I INV-008 an address that is merely a suffix of the member address does not match');
select is(pg_temp.red(52, 52), '1:email_mismatch|~',
  'I INV-008 a member with no email never matches');
select is(pg_temp.red(53, 53), '1:email_mismatch|~',
  'I INV-008 a member with a blank email never matches');
select is(pg_temp.red(56, 56), '1:account_already_linked|~',
  'I INV-011 an account bound as a member in another gym is account_already_linked');
select is(pg_temp.red(57, 57), '1:account_already_linked|~',
  'I INV-011 an account bound to another member of the same gym is account_already_linked');
select is(pg_temp.red(58, 58), '1:account_already_linked|~',
  'I INV-011 an account bound to a staff row is account_already_linked');
select is(pg_temp.red(59, 59), '1:account_already_linked|~',
  'I INV-011 an account bound to an inactive staff row is still account_already_linked');
select is(pg_temp.red(60, 60), '1:account_already_linked|~',
  'I INV-011 an account bound to a platform user is account_already_linked');
select is(pg_temp.red(61, 61), '1:account_already_linked|~',
  'I INV-011 an account bound to an inactive platform user is still account_already_linked');
select is(pg_temp.red(62, 62), '1:account_already_linked|~',
  'I INV-011 an account bound to a cancelled member elsewhere is still account_already_linked');
select is(pg_temp.red(64, 64), '1:identity_unverified|~',
  'I INV-008 order: identity is checked before the email');
select is(pg_temp.red(65, 65), '1:email_mismatch|~',
  'I INV-008 order: the email is checked before account bindings');
select is(pg_temp.red(66, 66), '1:identity_unverified|~',
  'I INV-008 order: identity is checked before account bindings');
select is(pg_temp.red(67, 67), '1:invite_unavailable|~',
  'I INV-008 order: member state is checked before identity');
select is(pg_temp.red(68, 68), '1:invite_unavailable|~',
  'I INV-008 order: member state is checked before the email');
select is(pg_temp.red(69, 69), '1:invite_unavailable|~',
  'I INV-008 order: gym state is checked before account bindings');
select is(pg_temp.delta('i2'), 27::bigint,
  'I INV-008 each of the 27 refusals writes exactly one audit row');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id between pg_temp.u(20040) and pg_temp.u(20069)
      and after = '{"outcome":"identity_unverified"}'::jsonb),
  8::bigint,
  'I INV-008 eight refusals recorded identity_unverified');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id between pg_temp.u(20040) and pg_temp.u(20069)
      and after = '{"outcome":"email_mismatch"}'::jsonb),
  9::bigint,
  'I INV-008 nine refusals recorded email_mismatch');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id between pg_temp.u(20040) and pg_temp.u(20069)
      and after = '{"outcome":"account_already_linked"}'::jsonb),
  7::bigint,
  'I INV-008 seven refusals recorded account_already_linked');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id between pg_temp.u(20040) and pg_temp.u(20069)
      and after = '{"outcome":"invite_unavailable"}'::jsonb),
  3::bigint,
  'I INV-008 three refusals recorded invite_unavailable');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id = pg_temp.u(20046) and tenant_id = pg_temp.u(101)),
  1::bigint,
  'I INV-008 a refusal whose token resolved records the invite tenant');
select is(
  (select count(*) from public.audit_log
    where action = 'member_invite.redeem_refused' and actor_user_id = pg_temp.u(20056) and tenant_id = pg_temp.u(101)),
  1::bigint,
  'I INV-008 an account_already_linked refusal records the invite tenant');
select is(
  (select count(*) from public.members
    where id in (pg_temp.u(10040), pg_temp.u(10041), pg_temp.u(10042), pg_temp.u(10043), pg_temp.u(10044), pg_temp.u(10045),
                 pg_temp.u(10046), pg_temp.u(10047), pg_temp.u(10048), pg_temp.u(10049), pg_temp.u(10050), pg_temp.u(10051),
                 pg_temp.u(10052), pg_temp.u(10053), pg_temp.u(10056), pg_temp.u(10057), pg_temp.u(10058), pg_temp.u(10059),
                 pg_temp.u(10060), pg_temp.u(10061), pg_temp.u(10062), pg_temp.u(10064), pg_temp.u(10065), pg_temp.u(10066),
                 pg_temp.u(10067), pg_temp.u(10068), pg_temp.u(10069))
      and user_id is not null),
  0::bigint,
  'I INV-008 none of the refused members was bound');
select is(
  (select count(*) from public.member_invites
    where token_hash in (pg_temp.h(40), pg_temp.h(41), pg_temp.h(42), pg_temp.h(43), pg_temp.h(44), pg_temp.h(45),
                         pg_temp.h(46), pg_temp.h(47), pg_temp.h(48), pg_temp.h(49), pg_temp.h(50), pg_temp.h(51),
                         pg_temp.h(52), pg_temp.h(53), pg_temp.h(56), pg_temp.h(57), pg_temp.h(58), pg_temp.h(59),
                         pg_temp.h(60), pg_temp.h(61), pg_temp.h(62), pg_temp.h(64), pg_temp.h(65), pg_temp.h(66),
                         pg_temp.h(67), pg_temp.h(68), pg_temp.h(69))
      and status = 'pending'),
  27::bigint,
  'I INV-008 a refusal never burns the invite, so the person can switch Google account and retry');

-- caller shapes
select pg_temp.scn(70);
select pg_temp.scn(71);
select pg_temp.scn(72);
insert into public.staff (id, tenant_id, user_id, branch_id, role, full_name, is_active) values
  (pg_temp.u(325), pg_temp.u(102), pg_temp.u(20072), pg_temp.u(112), 'front_desk', 'H67 Staffer 72', true);

select pg_temp.mark('i3');
select is(pg_temp.redeem(pg_temp.c_add(pg_temp.c_plain(20070), jsonb_build_object('impersonation_session_id', pg_temp.u(9001))), pg_temp.h(70)),
  'err:42501',
  'I INV-007 a caller carrying an impersonation id is refused 42501');
select is(pg_temp.delta('i3'), 0::bigint,
  'I INV-007 the impersonation refusal writes nothing');
select is((select user_id from public.members where id = pg_temp.u(10070)), null::uuid,
  'I INV-007 the impersonation refusal bound nothing');
select is(pg_temp.red(70, 70), '1:linked|H67 Alpha Fitness',
  'I INV-007 the invite was not burned: the same account without impersonation links');
select is(pg_temp.redeem(pg_temp.c_drop(pg_temp.c_plain(20071), 'sub'), pg_temp.h(71)), 'err:42501',
  'I INV-007 an authenticated caller with no subject is refused 42501');
select is(pg_temp.redeem('', pg_temp.h(71), p_role => 'anon'), 'err:42501',
  'I INV-017 anon cannot execute redeem_member_invite');
select is(pg_temp.redeem('{"role":"service_role"}', pg_temp.h(71), p_role => 'service_role'), 'err:42501',
  'I INV-017 service_role cannot execute redeem_member_invite');
select ok(pg_temp.redeem(pg_temp.c_plain(20071), upper(pg_temp.h(71))) in ('err:22023', '1:invite_unavailable|~'),
  'I INV-008 an uppercase hash is malformed or simply unavailable, never a link');
select ok(pg_temp.redeem(pg_temp.c_plain(20071), left(pg_temp.h(71), 63)) in ('err:22023', '1:invite_unavailable|~'),
  'I INV-008 a short hash is malformed or simply unavailable, never a link');
select ok(pg_temp.redeem(pg_temp.c_plain(20071), null) in ('err:22023', '1:invite_unavailable|~'),
  'I INV-008 a null hash is malformed or simply unavailable, never a link');
select is((select user_id from public.members where id = pg_temp.u(10071)), null::uuid,
  'I INV-008 malformed hashes bound nothing');
select is(pg_temp.redeem(pg_temp.c_staff(20072, 'front_desk', 102, 325), pg_temp.h(72)), '1:account_already_linked|~',
  'I INV-011 a staff session redeeming a member invite is account_already_linked');
select is(pg_temp.redeem(
    pg_temp.c_add(pg_temp.c_plain(20057), jsonb_build_object('app_role', 'member', 'tenant_id', pg_temp.u(101), 'member_id', pg_temp.u(10157))),
    pg_temp.h(57)),
  '1:account_already_linked|~',
  'I INV-011 a member session redeeming another member invite is account_already_linked');

-- ===========================================================================
-- SECTION J. redeem throttle: 10 refusals in a rolling 15 minutes (INV-010)
-- ===========================================================================

select pg_temp.scn(80);
select pg_temp.scn(81);
select pg_temp.scn(82);
select pg_temp.scn(83);
select pg_temp.scn(84);
select pg_temp.scn(85);
select pg_temp.scn(86);
select pg_temp.scn(87);
select pg_temp.scn(190, p_inv => 'redeemed', p_invuser => pg_temp.u(20080), p_mbound => pg_temp.u(20080), p_user => false, p_memail => 'x190@h67.example.test');
select pg_temp.refs(pg_temp.u(20080), 10, interval '8 minutes');
select pg_temp.refs(pg_temp.u(20081), 9, interval '8 minutes');
select pg_temp.refs(pg_temp.u(20082), 9, interval '8 minutes');
select pg_temp.refs(pg_temp.u(20082), 1, interval '22 minutes');
select pg_temp.refs(pg_temp.u(20083), 10, interval '25 minutes');
select pg_temp.refs(pg_temp.u(20084), 9, interval '8 minutes');
select pg_temp.refs(pg_temp.u(20084), 30, interval '5 minutes', 'member_invite.redeemed');
select pg_temp.refs(pg_temp.u(20084), 30, interval '5 minutes', 'member.linked');
select pg_temp.refs(pg_temp.u(20085), 9, interval '8 minutes');
select pg_temp.refs(pg_temp.u(20085), 10, interval '5 minutes', 'member_invite.issued');

select pg_temp.mark('j1');
select is(pg_temp.red(80, 80), '1:rate_limited|~',
  'J INV-010 an account with 10 refusals in the window is rate_limited even with a correct token');
select is(pg_temp.red(80, 9200), '1:rate_limited|~',
  'J INV-010 the throttle answers before the token is evaluated: an unknown token is rate_limited too');
select is(pg_temp.red(80, 190), '1:rate_limited|~',
  'J INV-010 the throttle precedes the replay check');
select is(pg_temp.delta('j1'), 0::bigint,
  'J INV-010 rate_limited writes nothing');
select is((select user_id from public.members where id = pg_temp.u(10080)), null::uuid,
  'J INV-010 the throttled correct token bound nothing');
select is((select status from public.member_invites where token_hash = pg_temp.h(80)), 'pending'::public.member_invite_status,
  'J INV-010 the throttled invite is still pending');
select is(
  (select count(*) from public.audit_log where action = 'member_invite.redeem_refused' and actor_user_id = pg_temp.u(20080)),
  10::bigint,
  'J INV-010 the refusal count for the throttled account did not grow');
select is(pg_temp.red(81, 81), '1:linked|H67 Alpha Fitness',
  'J INV-010 9 refusals in the window do not throttle');
select is(pg_temp.red(82, 82), '1:linked|H67 Alpha Fitness',
  'J INV-010 a refusal older than 15 minutes is not counted');
select is(pg_temp.red(83, 83), '1:linked|H67 Alpha Fitness',
  'J INV-010 ten refusals all older than 15 minutes do not throttle');
select is(pg_temp.red(84, 84), '1:linked|H67 Alpha Fitness',
  'J INV-010 successes are not counted toward the throttle');
select is(pg_temp.red(85, 85), '1:linked|H67 Alpha Fitness',
  'J INV-010 other audit actions by the same account are not counted');
select is(pg_temp.red(86, 86), '1:linked|H67 Alpha Fitness',
  'J INV-010 another account is unaffected by a throttled account');

select pg_temp.mark('j2');
select is(pg_temp.red(87, 9101), '1:invite_unavailable|~', 'J INV-010 refusal 1 of 10 is evaluated normally');
select is(pg_temp.red(87, 9102), '1:invite_unavailable|~', 'J INV-010 refusal 2 of 10 is evaluated normally');
select is(pg_temp.red(87, 9103), '1:invite_unavailable|~', 'J INV-010 refusal 3 of 10 is evaluated normally');
select is(pg_temp.red(87, 9104), '1:invite_unavailable|~', 'J INV-010 refusal 4 of 10 is evaluated normally');
select is(pg_temp.red(87, 9105), '1:invite_unavailable|~', 'J INV-010 refusal 5 of 10 is evaluated normally');
select is(pg_temp.red(87, 9106), '1:invite_unavailable|~', 'J INV-010 refusal 6 of 10 is evaluated normally');
select is(pg_temp.red(87, 9107), '1:invite_unavailable|~', 'J INV-010 refusal 7 of 10 is evaluated normally');
select is(pg_temp.red(87, 9108), '1:invite_unavailable|~', 'J INV-010 refusal 8 of 10 is evaluated normally');
select is(pg_temp.red(87, 9109), '1:invite_unavailable|~', 'J INV-010 refusal 9 of 10 is evaluated normally');
select is(pg_temp.red(87, 9110), '1:invite_unavailable|~', 'J INV-010 refusal 10 of 10 is evaluated normally');
select is(pg_temp.red(87, 9111), '1:rate_limited|~', 'J INV-010 the eleventh attempt is rate_limited');
select is(pg_temp.red(87, 87), '1:rate_limited|~', 'J INV-010 a correct token after ten refusals is still rate_limited');
select is(pg_temp.delta('j2'), 10::bigint,
  'J INV-010 only the ten evaluated refusals wrote audit rows');
select is((select user_id from public.members where id = pg_temp.u(10087)), null::uuid,
  'J INV-010 the throttled account bound nothing');

-- ===========================================================================
-- SECTION K. replay, reuse, relink, supersede then redeem (INV-009, INV-011)
-- ===========================================================================

select pg_temp.scn(90, p_inv => 'none');
select pg_temp.mk_user(20190, 'u20190@h67.example.test', 'm90@h67.example.test', true, false, false, true);
select pg_temp.scn(92, p_memail => 'm90@h67.example.test');
select pg_temp.scn(93);
select pg_temp.scn(193, p_memail => 'm93@h67.example.test', p_user => false);
select pg_temp.scn(293, p_org => 102, p_memail => 'm93@h67.example.test', p_user => false);
insert into auth.sessions (id, user_id) values
  (pg_temp.u(5101), pg_temp.u(20090)),
  (pg_temp.u(5102), pg_temp.u(20090)),
  (pg_temp.u(5103), pg_temp.u(20190)),
  (pg_temp.u(5104), pg_temp.u(2001));

insert into h67_res values ('iss90a', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10090), pg_temp.h(9001)));
select is(pg_temp.redeem(pg_temp.c_plain(20090), pg_temp.h(9001)), '1:linked|H67 Alpha Fitness',
  'K INV-007 first account links the member through the first token');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(9001)), '1:invite_unavailable|~',
  'K INV-009 a second account using the same token is invite_unavailable');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10090), 'Wrong account linked'), 'ok',
  'K INV-014 the owner unlinks the first account');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20090)), 0::bigint,
  'K INV-014 unlink deletes the former user sessions');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20190)), 1::bigint,
  'K INV-014 unlink leaves an unrelated user sessions alone');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(2001)), 1::bigint,
  'K INV-014 unlink leaves the acting owner sessions alone');
select is((select user_id from public.members where id = pg_temp.u(10090)), null::uuid,
  'K INV-014 unlink clears members.user_id');
select ok(
  (select status = 'redeemed' and redeemed_user_id = pg_temp.u(20090) from public.member_invites where token_hash = pg_temp.h(9001)),
  'K INV-014 unlink leaves the redeemed invite as a redeemed record');
select is(pg_temp.redeem(pg_temp.c_plain(20090), pg_temp.h(9001)), '1:invite_unavailable|~',
  'K INV-009 the old token presented by its original redeemer after unlink is invite_unavailable');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(9001)), '1:invite_unavailable|~',
  'K INV-009 the old token presented by another account after unlink is invite_unavailable');
select is(pg_temp.hook(pg_temp.u(20090)), '~|~|~|~',
  'K INV-014 after unlink the access token hook mints no gym claims for the former user');
insert into h67_res values ('iss90b', pg_temp.issue(pg_temp.k_owner(), pg_temp.u(10090), pg_temp.h(9002)));
select ok((select v ~ '^1:[0-9a-f-]{36}\|~\|[0-9.]+$' from h67_res where k = 'iss90b'),
  'K INV-003 issuing again after an unlink supersedes nothing because the earlier invite is redeemed');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(9002)), '1:linked|H67 Alpha Fitness',
  'K INV-007 a different account matching the address links on relink');
select is(pg_temp.redeem(pg_temp.c_plain(20090), pg_temp.h(9001)), '1:invite_unavailable|~',
  'K INV-009 the first token stays dead after a relink to another account');
select is(pg_temp.redeem(pg_temp.c_plain(20090), pg_temp.h(9002)), '1:invite_unavailable|~',
  'K INV-009 the relink token is dead for the previous account');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(9002)), '1:already_linked_here|H67 Alpha Fitness',
  'K INV-009 the relinked account replaying the relink token gets already_linked_here');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(9001)), '1:invite_unavailable|~',
  'K INV-009 the relinked account replaying the first token is invite_unavailable because another account redeemed it');
select is(pg_temp.hook(pg_temp.u(20190)), 'member|' || pg_temp.u(101)::text || '|' || pg_temp.u(10090)::text || '|~',
  'K INV-007 after the relink the hook mints member claims for the new account');
select is(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(92)), '1:account_already_linked|~',
  'K INV-011 after the relink the account is bound, so another member invite is account_already_linked');

select pg_temp.scn(91, p_inv => 'redeemed', p_invuser => pg_temp.u(20190), p_memail => 'm90@h67.example.test', p_user => false);
select ok(pg_temp.redeem(pg_temp.c_plain(20190), pg_temp.h(91)) in ('1:invite_unavailable|~', '1:account_already_linked|~'),
  'K INV-009 an account bound to a different member is never told already_linked_here');

-- one account, several invites
select is(pg_temp.red(93, 93), '1:linked|H67 Alpha Fitness',
  'K INV-011 one account links its first member');
select is(pg_temp.red(93, 193), '1:account_already_linked|~',
  'K INV-011 the same account cannot link a second member of the same gym');
select is(pg_temp.red(93, 293), '1:account_already_linked|~',
  'K INV-011 the same account cannot link a member of another gym');
select is(
  (select count(*) from public.members where id in (pg_temp.u(10193), pg_temp.u(10293)) and user_id is not null),
  0::bigint,
  'K INV-011 at most one binding exists for one account');
select is(
  (select count(*) from public.members where user_id = pg_temp.u(20093)),
  1::bigint,
  'K INV-011 the account is bound to exactly one member');

-- issue, issue again (section E), redeem the old token then the new one
select is(pg_temp.red(235, 2351), '1:invite_unavailable|~',
  'K INV-003 a superseded token never redeems although it has not expired');
select is(pg_temp.red(235, 2352), '1:linked|H67 Alpha Fitness',
  'K INV-003 the newest token redeems');

-- ===========================================================================
-- SECTION L. unlink_member_identity (INV-014)
-- ===========================================================================

select pg_temp.scn(100, p_inv => 'none', p_mbound => pg_temp.u(20100));
select pg_temp.scn(101, p_inv => 'none', p_mbound => pg_temp.u(20101));
select pg_temp.scn(102, p_inv => 'none', p_mbound => pg_temp.u(20102));
select pg_temp.scn(103, p_inv => 'none', p_mbound => pg_temp.u(20103));
select pg_temp.scn(104, p_inv => 'none', p_mstatus => 'cancelled', p_mbound => pg_temp.u(20104));
select pg_temp.scn(105, p_mbound => pg_temp.u(20105));
select pg_temp.scn(106, p_inv => 'none', p_mstatus => 'blocked', p_mbound => pg_temp.u(20106));
select pg_temp.scn(107, p_inv => 'none', p_mbound => pg_temp.u(20107));
select pg_temp.scn(108, p_inv => 'none');
select pg_temp.scn(109, p_inv => 'none', p_mbound => pg_temp.u(20109));
insert into auth.sessions (id, user_id) values
  (pg_temp.u(5001), pg_temp.u(20100)),
  (pg_temp.u(5002), pg_temp.u(20100)),
  (pg_temp.u(5003), pg_temp.u(20100)),
  (pg_temp.u(5004), pg_temp.u(20101)),
  (pg_temp.u(5005), pg_temp.u(20101)),
  (pg_temp.u(5006), pg_temp.u(20109)),
  (pg_temp.u(5007), pg_temp.u(20109)),
  (pg_temp.u(5008), pg_temp.u(2001)),
  (pg_temp.u(5009), pg_temp.u(20107)),
  (pg_temp.u(5010), pg_temp.u(20107)),
  (pg_temp.u(5011), pg_temp.u(20103));

select pg_temp.mark('l1');
select is(pg_temp.unlink_m(pg_temp.k_trainer(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a trainer cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_desk(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 front desk cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_member(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a member cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_super(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a platform super admin cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_super_t(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a platform super admin holding the gym tenant claim cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_imp(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 an impersonating owner cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_imp2(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a preview shaped owner claim cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_inactive(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 an inactive staff row cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_ownerb(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 the owner of another gym cannot unlink');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(99999), 'cleanup of the account link'), 'err:42501',
  'L INV-014 an unknown member id is refused 42501');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10233), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a bound member of another gym is refused 42501, not described');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10232), 'cleanup of the account link'), 'err:42501',
  'L INV-014 an unbound member of another gym is refused 42501, not GL080');
select is(pg_temp.unlink_m(pg_temp.k_plain(), pg_temp.u(10107), 'cleanup of the account link'), 'err:42501',
  'L INV-014 a signed in caller with no gym claims cannot unlink');
select is(pg_temp.unlink_m('', pg_temp.u(10107), 'cleanup of the account link', p_role => 'anon'), 'err:42501',
  'L INV-017 anon cannot execute unlink_member_identity');
select is(pg_temp.unlink_m('{"role":"service_role"}', pg_temp.u(10107), 'cleanup of the account link', p_role => 'service_role'), 'err:42501',
  'L INV-017 service_role cannot execute unlink_member_identity');
select is((select user_id from public.members where id = pg_temp.u(10107)), pg_temp.u(20107),
  'L INV-014 every refused unlink left the member bound');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20107)), 2::bigint,
  'L INV-014 every refused unlink left the sessions alone');
select is(pg_temp.delta('l1'), 0::bigint,
  'L INV-014 every refused unlink wrote no audit row');
select is(
  pg_temp.nouuid(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10233), 'cleanup of the account link', 'msg')),
  pg_temp.nouuid(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(99999), 'cleanup of the account link', 'msg')),
  'L INV-014 a member of another gym and an unknown id are indistinguishable even by message');
select is(
  pg_temp.nouuid(pg_temp.unlink_m(pg_temp.k_trainer(), pg_temp.u(10107), 'cleanup of the account link', 'msg')),
  pg_temp.nouuid(pg_temp.unlink_m(pg_temp.k_trainer(), pg_temp.u(99999), 'cleanup of the account link', 'msg')),
  'L INV-014 a forbidden role learns nothing about whether the member id exists');

select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10108), 'cleanup of the account link'), 'err:GL080',
  'L INV-014 unlinking an unbound member fails GL080');

select pg_temp.mark('l2');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), null), 'err:22023',
  'L INV-014 a null reason fails 22023');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), ''), 'err:22023',
  'L INV-014 an empty reason fails 22023');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), '     '), 'err:22023',
  'L INV-014 a blank reason fails 22023');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), 'ab'), 'err:22023',
  'L INV-014 a 2 character reason fails 22023');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), '   ab   '), 'err:22023',
  'L INV-014 a reason that is 2 characters once trimmed fails 22023');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), repeat('x', 201)), 'err:22023',
  'L INV-014 a 201 character reason fails 22023');
select is((select user_id from public.members where id = pg_temp.u(10100)), pg_temp.u(20100),
  'L INV-014 invalid reasons left the member bound');
select is(pg_temp.delta('l2'), 0::bigint,
  'L INV-014 invalid reasons wrote no audit row');

select pg_temp.mark('l3');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), 'abc'), 'ok',
  'L INV-014 an owner unlinks a bound member with a 3 character reason');
select is((select user_id from public.members where id = pg_temp.u(10100)), null::uuid,
  'L INV-014 user_id is cleared');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20100)), 0::bigint,
  'L INV-014 the former user sessions are deleted');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20101)), 2::bigint,
  'L INV-014 a different linked user keeps their sessions');
select is(pg_temp.delta('l3'), 1::bigint,
  'L INV-016 an unlink writes exactly one audit row');
select is(
  (select count(*) from public.audit_log
    where action = 'member.unlinked' and tenant_id = pg_temp.u(101) and actor_user_id = pg_temp.u(2001)
      and actor_role = 'gym_owner' and record_type = 'member' and record_id = pg_temp.u(10100)
      and before = '{"user_linked":true}'::jsonb and after = '{"user_linked":false}'::jsonb
      and btrim(reason) = 'abc'),
  1::bigint,
  'L INV-016 member.unlinked carries before user_linked true, after user_linked false and the reason');
select is(pg_temp.hook(pg_temp.u(20100)), '~|~|~|~',
  'L INV-014 the hook mints no gym claims for the unlinked user');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10100), 'abc'), 'err:GL080',
  'L INV-014 unlinking the same member again fails GL080');

select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10101), repeat('r', 200)), 'ok',
  'L INV-014 a 200 character reason is accepted');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10102), '  ' || repeat('r', 200) || '  '), 'ok',
  'L INV-014 the reason length is measured after trimming');
select is(pg_temp.unlink_m(pg_temp.k_mgr(), pg_temp.u(10103), 'manager requested'), 'ok',
  'L INV-014 a manager may unlink');
select is(
  (select count(*) from public.audit_log
    where action = 'member.unlinked' and record_id = pg_temp.u(10103) and actor_user_id = pg_temp.u(2002) and actor_role = 'gym_manager'),
  1::bigint,
  'L INV-016 the manager unlink is audited with role gym_manager');
select is((select count(*) from auth.sessions where user_id = pg_temp.u(20103)), 0::bigint,
  'L INV-014 the manager unlink deleted the former user sessions');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10104), 'cancelled member cleanup'), 'ok',
  'L INV-014 a cancelled but still bound member can be unlinked');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10105), 'invite stays untouched'), 'ok',
  'L INV-014 a bound member with a pending invite can be unlinked');
select ok(
  (select status = 'pending' and closed_at is null and token_hash = pg_temp.h(105) from public.member_invites where member_id = pg_temp.u(10105)),
  'L INV-014 the pending invite is left untouched by an unlink');
select is(pg_temp.unlink_m(pg_temp.k_owner(), pg_temp.u(10106), 'blocked member cleanup'), 'ok',
  'L INV-014 a blocked but still bound member can be unlinked');
select is((select count(*) from auth.sessions where user_id in (pg_temp.u(20109), pg_temp.u(2001))), 4::bigint,
  'L INV-014 unrelated sessions of a bystander and of the acting owner all survive');
select is((select user_id from public.members where id = pg_temp.u(10109)), pg_temp.u(20109),
  'L INV-014 the bystander member is still bound');

-- ===========================================================================
-- SECTION M. read_member_app_access precedence (INV-015)
-- ===========================================================================

select pg_temp.scn(130, p_inv => 'none', p_mbound => pg_temp.u(20130));
select pg_temp.scn(131, p_inv => 'none', p_mstatus => 'cancelled', p_mbound => pg_temp.u(20131));
select pg_temp.scn(132, p_inv => 'none', p_mstatus => 'blocked', p_mbound => pg_temp.u(20132));
select pg_temp.scn(133, p_inv => 'none', p_merased => true, p_mbound => pg_temp.u(20133));
select pg_temp.scn(134, p_inv => 'none', p_user => false, p_mstatus => 'cancelled');
select pg_temp.scn(135, p_inv => 'none', p_user => false, p_mstatus => 'blocked');
select pg_temp.scn(136, p_inv => 'none', p_user => false, p_merased => true);
select pg_temp.scn(137, p_user => false, p_mstatus => 'cancelled');
select pg_temp.scn(138, p_user => false, p_merased => true);
select pg_temp.scn(139, p_user => false, p_mstatus => 'blocked');
select pg_temp.scn(140, p_user => false);
select pg_temp.scn(141, p_inv => 'expired', p_user => false);
select pg_temp.scn(142, p_inv => 'revoked', p_user => false);
select pg_temp.scn(143, p_inv => 'superseded', p_user => false);
select pg_temp.scn(144, p_inv => 'redeemed', p_invuser => pg_temp.u(20144));
select pg_temp.scn(145, p_inv => 'revoked', p_user => false);
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10145), pg_temp.u(301), pg_temp.h(1450), 'pending',
  now() - interval '30 minutes', now() + interval '40 hours');
select pg_temp.scn(146, p_inv => 'superseded', p_user => false);
select pg_temp.insv(pg_temp.u(101), pg_temp.u(10146), pg_temp.u(301), pg_temp.h(1460), 'pending',
  now() - interval '1 hour', now() - interval '30 minutes');
select pg_temp.scn(147, p_inv => 'none', p_user => false);
select pg_temp.scn(148, p_inv => 'none', p_user => false, p_memail => null);
select pg_temp.scn(149, p_user => false, p_memail => null);
select pg_temp.scn(150, p_user => false, p_mstatus => 'paused');
select pg_temp.scn(151, p_user => false, p_mstatus => 'expired');
select pg_temp.scn(152);
select pg_temp.scn(153, p_inv => 'none', p_mbound => pg_temp.u(20153));
insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after, occurred_at) values
  (pg_temp.u(101), pg_temp.u(20153), 'member', 'member.linked', 'member', pg_temp.u(10153),
   '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-01-01 00:00:00+00'),
  (pg_temp.u(101), pg_temp.u(20153), 'member', 'member.linked', 'member', pg_temp.u(10153),
   '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-03-01 00:00:00+00'),
  (pg_temp.u(101), pg_temp.u(2001), 'gym_owner', 'member.unlinked', 'member', pg_temp.u(10153),
   '{"user_linked":true}'::jsonb, '{"user_linked":false}'::jsonb, timestamptz '2026-05-01 00:00:00+00'),
  (pg_temp.u(101), pg_temp.u(20130), 'member', 'member.linked', 'member', pg_temp.u(10147),
   '{"user_linked":false}'::jsonb, '{"user_linked":true,"via":"invite"}'::jsonb, timestamptz '2026-06-01 00:00:00+00');

select pg_temp.mark('m1');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10130)), '1#linked|~|~|~|~',
  'M INV-015 a bound member with no invites and no link audit row is linked with a null linked_at');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10131)), '1#linked',
  'M INV-015 a linked and cancelled member is linked');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10132)), '1#linked',
  'M INV-015 a linked and blocked member is linked');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10133)), '1#linked',
  'M INV-015 a linked and erased member is linked');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10134)), '1#unavailable|~|~|~|~',
  'M INV-015 a cancelled member with no invite is unavailable');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10135)), '1#unavailable|~|~|~|~',
  'M INV-015 a blocked member with no invite is unavailable');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10136)), '1#unavailable|~|~|~|~',
  'M INV-015 an erased member with no invite is unavailable');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10137)), '1#unavailable',
  'M INV-015 a cancelled member with a pending invite is unavailable');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10138)), '1#unavailable',
  'M INV-015 an erased member with a pending invite is unavailable');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10139)), '1#unavailable',
  'M INV-015 a blocked member with a pending invite is unavailable');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10140)),
  (select '1#invite_pending|' || i.id::text || '|' || extract(epoch from i.issued_at)::text || '|' || extract(epoch from i.expires_at)::text || '|~'
     from public.member_invites i where i.token_hash = pg_temp.h(140)),
  'M INV-015 an unexpired pending invite is invite_pending with its id, issued_at, expires_at and no linked_at');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10141)),
  (select '1#invite_expired|' || i.id::text || '|' || extract(epoch from i.issued_at)::text || '|' || extract(epoch from i.expires_at)::text || '|~'
     from public.member_invites i where i.token_hash = pg_temp.h(141)),
  'M INV-004 INV-015 a pending invite past its expiry is invite_expired with its id and times');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10142)), '1#not_invited|~|~|~|~',
  'M INV-015 a newest invite that is revoked counts as none');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10143)), '1#not_invited|~|~|~|~',
  'M INV-015 a newest invite that is superseded counts as none');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10144)), '1#not_invited|~|~|~|~',
  'M INV-015 a newest invite that is redeemed on an unlinked member counts as none');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10145)),
  (select '1#invite_pending|' || i.id::text || '|' || extract(epoch from i.issued_at)::text || '|' || extract(epoch from i.expires_at)::text || '|~'
     from public.member_invites i where i.token_hash = pg_temp.h(1450)),
  'M INV-015 the newest invite decides: an older revoked invite does not hide a newer pending one');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10146)),
  (select '1#invite_expired|' || i.id::text || '|' || extract(epoch from i.issued_at)::text || '|' || extract(epoch from i.expires_at)::text || '|~'
     from public.member_invites i where i.token_hash = pg_temp.h(1460)),
  'M INV-015 the newest invite decides: a newer expired pending invite is invite_expired');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10147)), '1#not_invited|~|~|~|~',
  'M INV-015 a member with an email and no invite is not_invited');
select is(pg_temp.rdf(pg_temp.k_owner(), pg_temp.u(10148)), '1#not_invited|~|~|~|~',
  'M INV-015 a member with no email and no invite is not_invited');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10149)), '1#invite_pending',
  'M INV-015 a pending invite decides the state even when the email has since been cleared');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10150)), '1#invite_pending',
  'M INV-015 a paused member with a pending invite is invite_pending');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10151)), '1#invite_pending',
  'M INV-015 a member whose status is expired with a pending invite is invite_pending');

select is(pg_temp.red(152, 152), '1:linked|H67 Alpha Fitness',
  'M setup: member 152 links through a real redemption');
select is(
  pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10152), $q$state || '|' || coalesce(extract(epoch from linked_at)::text, '~')$q$),
  '1#linked|' || (select extract(epoch from max(occurred_at))::text from public.audit_log where action = 'member.linked' and record_id = pg_temp.u(10152)),
  'M INV-015 linked_at equals the member.linked audit time of a real redemption');
select is(
  pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10153), $q$state || '|' || coalesce(extract(epoch from linked_at)::text, '~')$q$),
  '1#linked|' || extract(epoch from timestamptz '2026-03-01 00:00:00+00')::text,
  'M INV-015 linked_at is the latest member.linked time for that member, ignoring unlink rows and other members');

select is(pg_temp.rd(pg_temp.k_mgr(), pg_temp.u(10140)), '1#invite_pending',
  'M INV-015 a manager may read the access state');
select is(pg_temp.rd(pg_temp.k_desk(), pg_temp.u(10140)), '1#invite_pending',
  'M INV-015 a front desk member may read the access state');
select is(pg_temp.rd(pg_temp.k_trainer(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 a trainer cannot read the access state');
select is(pg_temp.rd(pg_temp.k_member(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 a member cannot read the access state');
select is(pg_temp.rd(pg_temp.k_super(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 a platform super admin cannot read the access state');
select is(pg_temp.rd(pg_temp.k_super_t(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 a platform super admin holding the gym tenant claim cannot read the access state');
select is(pg_temp.rd(pg_temp.k_support(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 platform support cannot read the access state');
select is(pg_temp.rd(pg_temp.k_inactive(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 an inactive staff row cannot read the access state');
select is(pg_temp.rd(pg_temp.k_ownerb(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 the owner of another gym cannot read the access state');
select is(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(99999)), 'err:42501',
  'M INV-015 an unknown member id is refused 42501');
select is(pg_temp.rd(pg_temp.k_plain(), pg_temp.u(10140)), 'err:42501',
  'M INV-015 a signed in caller with no gym claims cannot read the access state');
select is(pg_temp.rd('', pg_temp.u(10140), p_role => 'anon'), 'err:42501',
  'M INV-017 anon cannot execute read_member_app_access');
select is(pg_temp.rd('{"role":"service_role"}', pg_temp.u(10140), p_role => 'service_role'), 'err:42501',
  'M INV-017 service_role cannot execute read_member_app_access');
select is(
  pg_temp.nouuid(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(10233), p_mode => 'msg')),
  pg_temp.nouuid(pg_temp.rd(pg_temp.k_owner(), pg_temp.u(99999), p_mode => 'msg')),
  'M INV-015 a member of another gym and an unknown id are indistinguishable even by message');
select is(pg_temp.delta('m1') - 2, 0::bigint,
  'M INV-015 reading the access state writes no audit row apart from the one real redemption');

-- ===========================================================================
-- SECTION N. direct table access and RLS (INV-017)
-- ===========================================================================

select is(pg_temp.run(pg_temp.k_owner(), 'authenticated', 'select count(*)::text from public.member_invites'),
  (select count(*)::text from public.member_invites where tenant_id = pg_temp.u(101)),
  'N INV-017 an owner reads exactly the invites of their own gym');
select is(pg_temp.run(pg_temp.k_owner(), 'authenticated',
  format($q$select count(*)::text from public.member_invites where tenant_id <> %L$q$, pg_temp.u(101))), '0',
  'N INV-017 an owner reads no invite of any other gym');
select is(pg_temp.run(pg_temp.k_mgr(), 'authenticated', 'select count(*)::text from public.member_invites'),
  (select count(*)::text from public.member_invites where tenant_id = pg_temp.u(101)),
  'N INV-017 a manager reads the invites of their own gym');
select is(pg_temp.run(pg_temp.k_desk(), 'authenticated', 'select count(*)::text from public.member_invites'),
  (select count(*)::text from public.member_invites where tenant_id = pg_temp.u(101)),
  'N INV-017 a front desk member reads the invites of their own gym');
select is(pg_temp.run(pg_temp.k_ownerb(), 'authenticated', 'select count(*)::text from public.member_invites'),
  (select count(*)::text from public.member_invites where tenant_id = pg_temp.u(102)),
  'N INV-017 the owner of another gym reads only that gym invites');
select is(pg_temp.run(pg_temp.k_ownerb(), 'authenticated',
  format($q$select count(*)::text from public.member_invites where tenant_id = %L$q$, pg_temp.u(101))), '0',
  'N INV-017 the owner of another gym cannot read the first gym invites');
select is(pg_temp.run(pg_temp.k_trainer(), 'authenticated', 'select count(*)::text from public.member_invites'), '0',
  'N INV-017 a trainer reads no invite');
select is(pg_temp.run(pg_temp.k_member(), 'authenticated', 'select count(*)::text from public.member_invites'), '0',
  'N INV-017 a member reads no invite');
select is(pg_temp.run(pg_temp.k_plain(), 'authenticated', 'select count(*)::text from public.member_invites'), '0',
  'N INV-017 a signed in caller with no gym claims reads no invite');
select is(pg_temp.run('', 'anon', 'select count(*)::text from public.member_invites'), 'err:42501',
  'N INV-017 anon cannot select from member_invites');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$insert into public.member_invites (tenant_id, member_id, token_hash, issued_by_staff_id, expires_at) values (%L, %L, %L, %L, now() + interval '47 hours')$q$,
         pg_temp.u(101), pg_temp.u(10147), pg_temp.h(9300), pg_temp.u(301))), 'err:42501',
  'N INV-017 an owner cannot insert into member_invites directly');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$update public.member_invites set status = 'revoked', closed_at = now() where token_hash = %L$q$, pg_temp.h(140))), 'err:42501',
  'N INV-017 an owner cannot update member_invites directly');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated',
  format($q$delete from public.member_invites where token_hash = %L$q$, pg_temp.h(140))), 'err:42501',
  'N INV-017 an owner cannot delete from member_invites');
select is(pg_temp.dml(pg_temp.k_mgr(), 'authenticated',
  format($q$update public.member_invites set expires_at = now() + interval '90 days' where token_hash = %L$q$, pg_temp.h(140))), 'err:42501',
  'N INV-017 a manager cannot extend an invite by update');
select is(pg_temp.dml(pg_temp.k_desk(), 'authenticated',
  format($q$delete from public.member_invites where token_hash = %L$q$, pg_temp.h(140))), 'err:42501',
  'N INV-017 a front desk member cannot delete an invite');
select is(pg_temp.dml(pg_temp.k_super(), 'authenticated',
  format($q$delete from public.member_invites where token_hash = %L$q$, pg_temp.h(140))), 'err:42501',
  'N INV-017 a platform super admin cannot delete an invite');
select ok(
  (select status = 'pending' from public.member_invites where token_hash = pg_temp.h(140))
  and (select expires_at < now() + interval '5 days' from public.member_invites where token_hash = pg_temp.h(140)),
  'N INV-017 the refused direct writes changed nothing');
select is(pg_temp.dml(pg_temp.k_owner(), 'authenticated', 'truncate public.member_invites'), 'err:42501',
  'N INV-017 an owner cannot truncate member_invites');

-- ===========================================================================
-- SECTION O. auth user deletion and audit hygiene (INV-016, INV-024)
-- ===========================================================================

select pg_temp.scn(160, p_inv => 'redeemed', p_invuser => pg_temp.u(20160), p_mbound => pg_temp.u(20160));
select is(pg_temp.dml('', 'postgres', format($q$delete from auth.users where id = %L$q$, pg_temp.u(20160))), 'ok:1',
  'O ADR-176 deleting an Auth user succeeds even when it is bound and redeemed an invite');
select is((select user_id from public.members where id = pg_temp.u(10160)), null::uuid,
  'O ADR-176 deleting the Auth user clears members.user_id through its foreign key');
select ok(
  (select status = 'redeemed' and redeemed_user_id is null from public.member_invites where token_hash = pg_temp.h(160)),
  'O ADR-176 deleting the Auth user nulls redeemed_user_id and keeps the invite redeemed');

select is(
  (select count(*) from public.audit_log
    where action in ('member_invite.issued', 'member_invite.superseded', 'member_invite.revoked', 'member_invite.redeemed',
                     'member_invite.redeem_refused', 'member.linked', 'member.unlinked')
      and (tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g) or actor_user_id::text like '67900000-%')
      and (coalesce(before::text, '') || coalesce(after::text, '') || coalesce(reason, '')) ~ '[0-9a-f]{64}'),
  0::bigint,
  'O INV-016 no audit row of this feature contains a token hash or any 64 character hex value');
select is(
  (select count(*) from public.audit_log
    where action in ('member_invite.issued', 'member_invite.superseded', 'member_invite.revoked', 'member_invite.redeemed',
                     'member_invite.redeem_refused', 'member.linked', 'member.unlinked')
      and (tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g) or actor_user_id::text like '67900000-%')
      and actor_user_id is null),
  0::bigint,
  'O INV-016 every audit row of this feature names an actor');
select is(
  (select count(*) from public.audit_log
    where action in ('member_invite.issued', 'member_invite.superseded', 'member_invite.revoked', 'member_invite.redeemed',
                     'member_invite.redeem_refused', 'member.linked', 'member.unlinked')
      and (tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g) or actor_user_id::text like '67900000-%')
      and impersonation_session_id is not null),
  0::bigint,
  'O INV-016 no audit row of this feature carries an impersonation session');
select is(
  (select count(*) from public.audit_log
    where action in ('member_invite.issued', 'member_invite.superseded', 'member_invite.revoked', 'member_invite.redeemed',
                     'member_invite.redeem_refused', 'member.linked', 'member.unlinked')
      and (tenant_id in (select pg_temp.u(g) from generate_series(101, 110) g) or actor_user_id::text like '67900000-%')
      and record_id is distinct from pg_temp.u(7777)
      and record_type is distinct from split_part(action, '.', 1)),
  0::bigint,
  'O INV-016 every audit row record_type is the action prefix');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
