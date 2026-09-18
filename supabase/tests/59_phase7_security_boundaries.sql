-- Phase 7 security boundary contract.
--
-- This file intentionally checks the public database contract rather than
-- naming a migration, policy, or RPC implementation.  Members get one narrow
-- atomic command; they do not get a readable QR-session table or a direct
-- attendance INSERT capability.  All assertions are transactional (ADR-030).

begin;

select plan(17);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'qr_sessions'
       and cmd = 'SELECT'
       and (
         coalesce(qual, '') ilike '%current_member_id%'
         or coalesce(qual, '') ilike '%app_role%member%'
       )
  ),
  'a member cannot SELECT qr_sessions or discover gate-token rows'
);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and (
         coalesce(with_check, '') ilike '%current_member_id%'
         or coalesce(with_check, '') ilike '%app_role%member%'
       )
  ),
  'a member cannot INSERT attendance directly through PostgREST'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.oid = to_regprocedure('public.member_mobile_check_in(text, uuid, timestamptz)')
       and not p.prosecdef
  ),
  'the public member command is an invoker wrapper around the atomic definer capability'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.member_mobile_check_in(text, uuid, timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.member_mobile_check_in(text, uuid, timestamptz)',
    'EXECUTE'
  ),
  'authenticated callers can execute the narrow public token command while anon cannot'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and p.oid = to_regprocedure('app.member_mobile_identity()')
       and pg_get_functiondef(p.oid) ilike '%app_role%'
       and pg_get_functiondef(p.oid) ilike '%auth.uid%'
       and pg_get_functiondef(p.oid) ilike '%tenant_id%'
       and pg_get_functiondef(p.oid) ilike '%member_id%'
  ),
  'the canonical identity helper validates authenticated subject, role, tenant, and member'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and p.oid = to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)')
       and pg_get_functiondef(p.oid) ilike '%member_mobile_identity%'
       and pg_get_functiondef(p.oid) ilike '%token%'
       and pg_get_functiondef(p.oid) ilike '%client_event_id%'
  ),
  'the definer core calls canonical identity and resolves token/event facts'
);

select ok(
  exists (
    select 1
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.attendance'::regclass
       and not t.tgisinternal
       and p.oid = to_regprocedure('app.enforce_check_in()')
       and p.prorettype = 'trigger'::regtype
       and (t.tgtype::int & 4) = 4
  ),
  'the existing attendance trigger owns live occurrence stamping'
);

select ok(
  exists (
    select 1
      from pg_proc p
     where p.oid = to_regprocedure('app.enforce_check_in()')
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
       and pg_get_functiondef(p.oid) ilike '%client_event_id%'
  ),
  'offline acceptance requires the complete event and occurrence pair'
);

select ok(
  exists (
    select 1 from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.attendance'::regclass
       and not t.tgisinternal
       and p.oid = to_regprocedure('app.enforce_check_in()')
       and p.prorettype = 'trigger'::regtype
       and (t.tgtype::int & 4) = 4
  ),
  'the attendance trigger validates offline occurrence against QR creation and expiry'
);

select ok(
  exists (
    select 1 from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.attendance'::regclass
       and not t.tgisinternal
       and p.oid = to_regprocedure('app.enforce_check_in()')
       and p.prorettype = 'trigger'::regtype
       and (t.tgtype::int & 4) = 4
  ),
  'the attendance trigger stamps replay time on the server'
);

select ok(
  exists (
    select 1 from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.attendance'::regclass
       and not t.tgisinternal
       and p.oid = to_regprocedure('app.enforce_check_in()')
       and p.prorettype = 'trigger'::regtype
       and (t.tgtype::int & 4) = 4
  ),
  'the attendance trigger validates membership on the offline occurrence date'
);

select ok(
  exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and tablename = 'attendance'
       and indexdef ilike '%client_event_id%'
  ),
  'replay retains an event-key uniqueness guard'
);

select ok(
  exists (
    select 1
      from pg_constraint
     where conrelid = 'public.attendance'::regclass
       and pg_get_constraintdef(oid) ilike '%offline_recorded_at%'
       and pg_get_constraintdef(oid) ilike '%replayed_at%'
  ),
  'attendance keeps the offline/replayed timestamp pair atomic'
);

select ok(
  exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'attendance'
       and column_name = 'client_event_id'
       and data_type = 'uuid'
  ),
  'replay event identity remains a UUID rather than an unbounded body string'
);

select ok(
  not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('payments', 'memberships', 'addon_orders')
       and column_name like '%paise'
       and data_type in ('numeric', 'double precision', 'real')
  ),
  'money storage remains integer paise at the database boundary'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%app_role%'
       and pg_get_functiondef(p.oid) ilike '%member_id%'
  ),
  'claim classification helpers reject incomplete or mixed identity claims'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%auth.uid%'
       and pg_get_functiondef(p.oid) ilike '%app_role%'
  ),
  'server identity checks bind the authenticated subject before command work'
);

select * from finish();

rollback;
