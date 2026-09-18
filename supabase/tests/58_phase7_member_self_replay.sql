begin;

select plan(8);

-- Phase 7 exposes one member check-in command. The table remains closed to
-- member writes; the public wrapper is a narrow surface around the
-- claim-validating app core (registry: member_mobile_check_in).

select ok(
  to_regprocedure('public.member_mobile_check_in(text, uuid, timestamptz)') is not null,
  'the canonical public member check-in command exists'
);

select ok(
  not (select p.prosecdef
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.oid = to_regprocedure('public.member_mobile_check_in(text, uuid, timestamptz)')),
  'the public member command is an invoker wrapper around the narrow definer core'
);

select ok(
  to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)') is not null
  and exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and p.oid = to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)')
       and p.prosecdef
  ),
  'the private core is the security-definer claim-validation boundary'
);

select ok(
  has_function_privilege('authenticated', 'public.member_mobile_check_in(text, uuid, timestamptz)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.member_mobile_check_in(text, uuid, timestamptz)', 'EXECUTE'),
  'authenticated members can execute the public wrapper while anon cannot'
);

select ok(
  exists (
    select 1 from pg_proc p
     where p.oid = to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)')
       and pg_get_functiondef(p.oid) ilike '%token%'
       and pg_get_functiondef(p.oid) ilike '%qr_sessions%'
  ),
  'the command accepts a gate-token proof and resolves the QR session atomically'
);

select ok(
  exists (
    select 1 from pg_proc p
     where p.oid = to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)')
       and pg_get_functiondef(p.oid) ilike '%client_event_id%'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
  ),
  'the command carries the original event key and complete offline timestamp pair'
);

select ok(
  exists (
    select 1 from pg_proc p
     where p.oid = to_regprocedure('app.record_member_mobile_check_in(text, uuid, timestamptz)')
       and pg_get_functiondef(p.oid) ilike '%member_mobile_identity%'
       and pg_get_functiondef(p.oid) ilike '%app_role%'
       and pg_get_functiondef(p.oid) ilike '%tenant_id%'
       and pg_get_functiondef(p.oid) ilike '%member_id%'
  ),
  'the command derives canonical member role, tenant, and member from verified claims'
);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and coalesce(with_check, '') ilike '%current_member_id%'
  ),
  'the member path is the atomic command, not a direct attendance INSERT policy'
);

select * from finish();

rollback;
