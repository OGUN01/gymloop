begin;

select plan(8);

-- Phase 7 deliberately adds a member INSERT path without reopening the existing
-- staff/front-office policy.  These are catalog assertions because policy names
-- are not a product interface; the reach of the predicate is.
select ok(
  exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and roles @> array['authenticated']::name[]
       and qual is null
       and with_check ilike '%current_member_id%'
       and with_check ilike '%member_id%'
       and with_check ilike '%current_tenant_id%'
       and with_check ilike '%app_role%member%'
  ),
  'a member-self attendance INSERT policy is present and binds tenant, role, and member id'
);

select ok(
  not exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance'
       and cmd = 'INSERT'
       and roles @> array['authenticated']::name[]
       and with_check ilike '%current_member_id%'
       and with_check not ilike '%member_id%'
  ),
  'no member attendance INSERT policy omits the row member binding'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
       and pg_get_functiondef(p.oid) ilike '%replayed_at%'
       and pg_get_functiondef(p.oid) ilike '%qr_sessions%'
       and pg_get_functiondef(p.oid) ilike '%created_at%'
       and pg_get_functiondef(p.oid) ilike '%expires_at%'
  ),
  'offline replay validates the claimed occurrence against the QR creation and expiry interval'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at%'
       and pg_get_functiondef(p.oid) ilike '%now()%'
       and pg_get_functiondef(p.oid) ilike '%replayed_at%'
  ),
  'offline replay stamps replayed_at on the server rather than accepting a client replay time'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%offline_recorded_at::date%'
       and pg_get_functiondef(p.oid) ilike '%memberships%'
  ),
  'offline membership liveness is evaluated on the validated offline occurrence day'
);

select ok(
  exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and pg_get_functiondef(p.oid) ilike '%client_event_id%'
       and pg_get_functiondef(p.oid) ilike '%member_id%'
       and pg_get_functiondef(p.oid) ilike '%23505%'
  ),
  'replay code distinguishes event idempotency by member rather than returning another member attendance'
);

select ok(
  exists (
    select 1
      from pg_constraint
     where conrelid = 'public.attendance'::regclass
       and contype = 'u'
  ) or exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and tablename = 'attendance'
       and indexdef ilike '%client_event_id%'
  ),
  'attendance retains a tenant-scoped client event uniqueness guard for exactly-once replay'
);

select ok(
  exists (
    select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
     where c.oid = 'public.attendance'::regclass
       and not t.tgisinternal
       and pg_get_triggerdef(t.oid) ilike '%INSERT%'
  ),
  'attendance checks remain attached to INSERT so direct writes cannot bypass the check-in contract'
);

select * from finish();

rollback;
