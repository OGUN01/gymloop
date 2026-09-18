BEGIN;

SELECT plan(19);

-- Phase 7's member check-in is a command boundary, not a direct PostgREST
-- write. The public wrapper is deliberately invoker-rights; its private core
-- is the narrowly justified elevated capability.
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'qr_sessions'
     AND cmd IN ('ALL', 'SELECT')
     AND roles @> ARRAY['authenticated']::name[]
     AND coalesce(qual, '') ILIKE '%current_member_id%'
), 'ATT-001/Phase-7: members have no QR-session read policy');

SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'attendance'
     AND cmd IN ('ALL', 'INSERT')
     AND roles @> ARRAY['authenticated']::name[]
     AND coalesce(with_check, '') ILIKE '%current_member_id%'
), 'ATT-001/Phase-7: members have no direct attendance INSERT policy');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'record_member_mobile_check_in' AND p.prosecdef
)
AND EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'member_mobile_check_in' AND NOT p.prosecdef
), 'ATT-001/Phase-7: the atomic private capability is definer-rights behind an invoker-rights public wrapper');

SELECT ok(
  has_function_privilege('authenticated', 'public.member_mobile_check_in(text,uuid,timestamp with time zone)'::regprocedure, 'EXECUTE'),
  'ATT-001/Phase-7: members execute the narrowly exposed public wrapper');

SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'record_member_mobile_check_in'
     AND p.proconfig @> ARRAY['row_security=off']
), 'ATT-001/Phase-7: command does not disable row security');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'member_mobile_check_in'
     AND p.proargtypes[0] = 'text'::regtype
), 'ATT-001/Phase-7: command accepts an opaque gate-token proof');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'member_mobile_check_in'
     AND p.proargtypes[1] = 'uuid'::regtype
), 'ATT-007/Phase-7: command carries the original replay event key');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'member_mobile_check_in'
     AND p.proargtypes[2] = 'timestamp with time zone'::regtype
), 'ATT-007/Phase-7: command carries the offline timestamp');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'member_mobile_check_in' AND p.pronargs = 3
), 'ATT-001/ATT-007: callers cannot supply tenant, member, or a separate occurrence time');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'attendance' AND a.attname = 'replayed_at' AND a.attgenerated = ''
), 'ATT-007/Phase-7: attendance records retain a server replay stamp');

SELECT ok(EXISTS (
  SELECT 1 FROM pg_index i JOIN pg_class r ON r.oid = i.indrelid
  JOIN pg_namespace n ON n.oid = r.relnamespace
  WHERE n.nspname = 'public' AND r.relname = 'attendance' AND i.indisunique
    AND pg_get_indexdef(i.indexrelid) ILIKE '%tenant_id%'
    AND pg_get_indexdef(i.indexrelid) ILIKE '%client_event_id%'
    AND pg_get_indexdef(i.indexrelid) ILIKE '%where%client_event_id%is not null%'
), 'ATT-007/Phase-7: replay event identity is constrained by its partial unique database index');

SELECT ok(
  pg_get_functiondef('app.member_mobile_identity()'::regprocedure) ILIKE '%current_app_role%'
  AND pg_get_functiondef('app.member_mobile_identity()'::regprocedure) ILIKE '%member%',
  'NAV-001/Phase-7: command validates the canonical member role');

SELECT ok(pg_get_functiondef('app.member_mobile_identity()'::regprocedure) ILIKE '%current_tenant_id%',
  'NAV-001/Phase-7: command derives tenant from verified claims');

SELECT ok(pg_get_functiondef('app.member_mobile_identity()'::regprocedure) ILIKE '%current_member_id%',
  'NAV-001/Phase-7: command derives member from verified claims');

SELECT ok(pg_get_functiondef('app.member_mobile_identity()'::regprocedure) ILIKE '%staff_id%',
  'NAV-001/Phase-7: mixed or non-member claims are rejected');

SELECT ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ILIKE '%statement_timestamp%',
  'ATT-001/Phase-7: live check-in time is server-owned');

SELECT ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ILIKE '%replayed_at%',
  'ATT-007/Phase-7: replay timestamp is assigned by the server');

SELECT ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ILIKE '%offline_recorded_at%'
  AND pg_get_functiondef('app.enforce_check_in()'::regprocedure) ILIKE '%replayed_at%'
  AND pg_get_functiondef('app.enforce_check_in()'::regprocedure) ILIKE '%expires_at%',
  'ATT-007: check-in enforcement owns the complete replay pair and QR expiry boundary');

SELECT ok(
  pg_get_functiondef('app.record_member_mobile_check_in(text,uuid,timestamp with time zone)'::regprocedure) ILIKE '%client_event_id%',
  'ATT-004/ATT-007: the atomic member core owns the original event identity');

SELECT * FROM finish();
ROLLBACK;
