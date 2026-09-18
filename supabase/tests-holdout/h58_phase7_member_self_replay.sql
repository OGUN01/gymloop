begin;

select plan(11);

-- Phase 7 is command-only for members: the authenticated grant and the policy
-- matrix must not become a second path around the claim-validating command.
select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd in ('ALL', 'INSERT')
       and roles @> array['authenticated']::name[]
       and coalesce(with_check, '') ~ 'current_member_id'
  ),
  'ATT-001/Phase-7: attendance has no member-self INSERT policy outside the atomic command'
);

select ok(
  has_table_privilege('authenticated', 'public.attendance', 'INSERT'),
  'ATT-001/Phase-7: the command-only member boundary preserves staff attendance INSERT capability'
);

select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'ALL'
       and coalesce(with_check, '') ~ 'is_front_office'
  ),
  'the established staff write policy remains a distinct front-office capability'
);

select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'SELECT'
       and coalesce(qual, '') ~ 'is_platform'
  ),
  'the established platform read policy remains present'
);

select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'ALL'
       and coalesce(with_check, '') ~ 'super_admin'
  ),
  'the established platform write policy remains super-admin-only'
);

-- The existing trigger is the table boundary shared by direct inserts, live
-- HTTP traffic and queued replay.  A replay implementation that only changes a
-- route would leave the direct member insert path unchecked.
select ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'offline_recorded_at',
  'check-in enforcement distinguishes an offline occurrence from a live insert'
);

select ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'replayed_at',
  'check-in enforcement owns the replay audit stamp'
);

select ok(
  to_regprocedure('app.member_mobile_identity()') is not null,
  'member command delegates canonical identity validation to the named member identity boundary'
);

select ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'expires_at',
  'offline occurrence validation consults the QR session expiry boundary'
);

select ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'v_scan_day',
  'membership liveness has an explicit day selected by the server boundary'
);

select ok(
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'offline_recorded_at.*::date|offline_recorded_at.*at time zone',
  'offline membership liveness is derived from the accepted occurrence rather than replay time'
);

select * from finish();

rollback;
