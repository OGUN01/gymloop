BEGIN;

SELECT plan(18);

-- Phase 7 security completion: the member surface is command-only.  The
-- authenticated role must not be able to read the proof row or manufacture
-- an attendance row through PostgREST.
SELECT ok(
  has_table_privilege('authenticated', 'public.qr_sessions', 'SELECT') IS FALSE,
  'ATT-001/Phase-7: members cannot SELECT QR sessions'
);

SELECT ok(
  has_table_privilege('authenticated', 'public.attendance', 'INSERT') IS FALSE,
  'ATT-001/Phase-7: members cannot INSERT attendance directly'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.prosecdef
  ),
  'ATT-001/Phase-7: the atomic member check-in command is security definer'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  'ATT-001/Phase-7: only the narrowly exposed command is executable by members'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.proconfig @> ARRAY['row_security=off']
  ),
  'ATT-001/Phase-7: command does not disable row security'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.proargnames @> ARRAY['gate_token']
  ),
  'ATT-001/Phase-7: command accepts a gate-token proof'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.proargnames @> ARRAY['event_id']
  ),
  'ATT-007/Phase-7: command carries the original replay event key'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.proargnames @> ARRAY['offline_recorded_at']
  ),
  'ATT-007/Phase-7: command carries the offline timestamp as a complete pair'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND p.proargnames @> ARRAY['occurrence_at']
  ),
  'ATT-007/Phase-7: command has a server-validated occurrence input'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'attendance'
      AND a.attname = 'replayed_at'
      AND a.attgenerated = ''
  ),
  'ATT-007/Phase-7: attendance records retain a server replay stamp'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class r ON r.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = r.relnamespace
    WHERE n.nspname = 'public'
      AND r.relname = 'attendance'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) ILIKE '%event%'
  ),
  'ATT-007/Phase-7: replay event identity is constrained at the database boundary'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%app_role%member%'
  ),
  'NAV-001/Phase-7: command validates the canonical member role'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%current_tenant_id%'
  ),
  'NAV-001/Phase-7: command derives tenant from verified claims'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%current_member_id%'
  ),
  'NAV-001/Phase-7: command derives member from verified claims'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%mixed%'
  ),
  'NAV-001/Phase-7: mixed or non-member claims are rejected'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%transaction_timestamp%'
  ),
  'ATT-001/Phase-7: live check-in time is server-owned'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%replayed_at%'
  ),
  'ATT-007/Phase-7: replay timestamp is assigned by the server'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%offline_recorded_at%'
      AND pg_get_functiondef(p.oid) ILIKE '%occurrence_at%'
  ),
  'ATT-007/Phase-7: offline occurrence requires the complete validated pair'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app'
      AND p.proname = 'record_member_checkin'
      AND pg_get_functiondef(p.oid) ILIKE '%ON CONFLICT%'
  ),
  'ATT-004/ATT-007: exact replay is idempotent while conflicting event reuse is refused'
);

SELECT * FROM finish();
ROLLBACK;
