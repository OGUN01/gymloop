begin;

select plan(11);

-- Phase 7 may add member insertion, but its scope is deliberately narrower
-- than the established staff/platform read and write matrix.  These catalog
-- assertions avoid naming an implementation-owned policy while making the
-- policy's capability and its exclusions observable.
select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and roles @> array['authenticated']::name[]
       and coalesce(with_check, '') ~ 'member_id'
       and coalesce(with_check, '') ~ 'current_member_id'
  ),
  'attendance has a member-scoped authenticated INSERT policy'
);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and coalesce(with_check, '') ~ 'current_member_id'
       and coalesce(with_check, '') !~ 'tenant_id'
  ),
  'member insertion binds the tenant as well as the member'
);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and coalesce(with_check, '') ~ 'current_member_id'
       and coalesce(with_check, '') ~ 'is_front_office'
  ),
  'member insertion is not a disguised front-office capability'
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
  'the established staff write policy remains present'
);

select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'ALL'
       and coalesce(with_check, '') ~ 'is_platform'
  ),
  'the established platform policy remains present'
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
  pg_get_functiondef('app.enforce_check_in()'::regprocedure) ~ 'issued_at',
  'offline occurrence validation consults the QR session opening boundary'
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
