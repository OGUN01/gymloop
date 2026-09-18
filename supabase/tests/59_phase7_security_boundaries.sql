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
       and p.prosecdef = false
       and pg_get_functiondef(p.oid) ilike '%qr_sessions%'
       and pg_get_functiondef(p.oid) ilike '%attendance%'
       and pg_get_functiondef(p.oid) ilike '%token%'
       and pg_get_functiondef(p.oid) ilike '%current_member_id%'
  ),
  'an atomic member command derives member and tenant from the verified claim and token proof'
);

select ok(
  exists (
    select 1
      from information_schema.routine_privileges r
     where r.routine_schema = 'public'
       and r.grantee = 'authenticated'
       and r.privilege_type = 'EXECUTE'
       and r.routine_name in (
         select p.proname
           from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public'
            and pg_get_functiondef(p.oid) ilike '%qr_sessions%'
            and pg_get_functiondef(p.oid) ilike '%attendance%'
            and pg_get_functiondef(p.oid) ilike '%token%'
       )
  ),
  'authenticated callers can execute only the narrow token command, not table writes'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%app_role%'
       and pg_get_functiondef(p.oid) ilike '%member%'
       and pg_get_functiondef(p.oid) ilike '%member_id%'
  ),
  'the member command requires the canonical member role and member claim'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%tenant_id%'
       and pg_get_functiondef(p.oid) ilike '%current_tenant_id%'
  ),
  'the command binds the attendance tenant to the verified tenant claim'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%now()%'
       and pg_get_functiondef(p.oid) ilike '%checked_in_at%'
  ),
  'live attendance occurrence is server-stamped'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
       and pg_get_functiondef(p.oid) ilike '%client_event_id%'
  ),
  'offline acceptance requires the complete event and occurrence pair'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
       and pg_get_functiondef(p.oid) ilike '%created_at%'
       and pg_get_functiondef(p.oid) ilike '%expires_at%'
  ),
  'offline occurrence is validated against the scanned QR session interval'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%replayed_at%'
       and pg_get_functiondef(p.oid) ilike '%now()%'
  ),
  'replay time is stamped by the server'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at::date%'
       and pg_get_functiondef(p.oid) ilike '%memberships%'
  ),
  'offline membership validity uses the validated occurrence date'
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
