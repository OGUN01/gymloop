BEGIN;

select plan(42);

-- MET-001: the owner entrypoint is an authenticated, caller-contained snapshot.
select has_function('public', 'owner_metrics', array['date', 'date'], 'MET-001 owner snapshot entrypoint exists');
select function_returns('public', 'owner_metrics', array['date', 'date'], 'jsonb', 'MET-001 owner snapshot returns jsonb');
select volatility_is('public', 'owner_metrics', array['date', 'date'], 'stable', 'MET-001 owner snapshot is stable');
select ok(
  not (select prosecdef from pg_proc where oid = 'public.owner_metrics(date,date)'::regprocedure),
  'MET-001 owner snapshot is security invoker'
);
select ok(
  exists (
    select 1 from pg_proc, unnest(coalesce(proconfig, array[]::text[])) setting
    where oid = 'public.owner_metrics(date,date)'::regprocedure and setting = 'search_path='
  ),
  'MET-001 owner snapshot pins an empty search path'
);
select is(
  has_function_privilege('anon', 'public.owner_metrics(date,date)'::regprocedure, 'execute'), false,
  'MET-001 anonymous callers cannot execute owner metrics'
);
select is(
  has_function_privilege('authenticated', 'public.owner_metrics(date,date)'::regprocedure, 'execute'), true,
  'MET-001 authenticated callers can reach the identity gate'
);

-- MET-002: the reusable gym helper is not a hidden elevated or historical API.
select has_function('app', 'gym_metrics', array['uuid', 'timestamp with time zone', 'date', 'date'], 'MET-002 shared gym helper exists');
select function_returns('app', 'gym_metrics', array['uuid', 'timestamp with time zone', 'date', 'date'], 'jsonb', 'MET-002 shared gym helper returns jsonb');
select volatility_is('app', 'gym_metrics', array['uuid', 'timestamp with time zone', 'date', 'date'], 'stable', 'MET-002 shared gym helper is stable');
select ok(
  not (select prosecdef from pg_proc where oid = 'app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure),
  'MET-002 shared gym helper is security invoker'
);
select ok(
  exists (
    select 1 from pg_proc, unnest(coalesce(proconfig, array[]::text[])) setting
    where oid = 'app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure and setting = 'search_path='
  ),
  'MET-002 shared gym helper pins an empty search path'
);
select is(
  has_function_privilege('anon', 'app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure, 'execute'), false,
  'MET-002 anonymous callers cannot execute shared gym metrics'
);
select is(
  has_function_privilege('authenticated', 'app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure, 'execute'), true,
  'MET-002 authenticated wrappers can execute shared gym metrics'
);
select is(
  app.gym_metrics(gen_random_uuid(), statement_timestamp(), current_date, current_date), 'null'::jsonb,
  'MET-002 unreadable or absent gyms return SQL null rather than a fabricated snapshot'
);

-- MET-003/MET-004: fleet is a separate platform-only, single-snapshot view.
select has_function('public', 'fleet_metrics', array[]::text[], 'MET-003 fleet snapshot entrypoint exists');
select function_returns('public', 'fleet_metrics', array[]::text[], 'jsonb', 'MET-003 fleet snapshot returns jsonb');
select volatility_is('public', 'fleet_metrics', array[]::text[], 'stable', 'MET-003 fleet snapshot is stable');
select ok(
  not (select prosecdef from pg_proc where oid = 'public.fleet_metrics()'::regprocedure),
  'MET-003 fleet snapshot is security invoker'
);
select ok(
  exists (
    select 1 from pg_proc, unnest(coalesce(proconfig, array[]::text[])) setting
    where oid = 'public.fleet_metrics()'::regprocedure and setting = 'search_path='
  ),
  'MET-003 fleet snapshot pins an empty search path'
);
select is(
  has_function_privilege('anon', 'public.fleet_metrics()'::regprocedure, 'execute'), false,
  'MET-003 anonymous callers cannot execute fleet metrics'
);
select is(
  (select pronargs from pg_proc where oid = 'public.fleet_metrics()'::regprocedure), 0::smallint,
  'MET-003 fleet has no caller-controlled tenant, date, or as-of parameter'
);

-- MET-005/MET-008/OPS-004: readiness is deliberately the one narrow definer seam.
select has_function('app', 'gym_readiness', array['uuid'], 'MET-005 readiness helper exists');
select function_returns('app', 'gym_readiness', array['uuid'], 'jsonb', 'MET-005 readiness helper returns jsonb');
select volatility_is('app', 'gym_readiness', array['uuid'], 'stable', 'MET-005 readiness helper is stable');
select ok(
  (select prosecdef from pg_proc where oid = 'app.gym_readiness(uuid)'::regprocedure),
  'MET-005 readiness is the explicitly contained security-definer seam'
);
select ok(
  exists (
    select 1 from pg_proc, unnest(coalesce(proconfig, array[]::text[])) setting
    where oid = 'app.gym_readiness(uuid)'::regprocedure and setting = 'search_path='
  ),
  'MET-005 readiness pins an empty search path'
);
select is(
  has_function_privilege('anon', 'app.gym_readiness(uuid)'::regprocedure, 'execute'), false,
  'MET-005 anonymous callers cannot execute readiness'
);
select is(
  app.gym_readiness(gen_random_uuid()), 'null'::jsonb,
  'MET-005 absent or unreadable gyms do not disclose readiness or auth-roster facts'
);
select ok(
  position('auth.users' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0
  and position('app.is_platform' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0,
  'MET-005 readiness contains its elevated Auth read behind a platform identity gate'
);

-- MET-006: neither public aggregate may hide a source-row cap or a second query path.
select is(
  position('limit ' in lower(pg_get_functiondef('public.owner_metrics(date,date)'::regprocedure))), 0,
  'MET-006 owner metrics has no source-query row cap'
);
select is(
  position('limit ' in lower(pg_get_functiondef('app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure))), 0,
  'MET-006 gym metrics has no source-query row cap'
);
select is(
  position('limit ' in lower(pg_get_functiondef('public.fleet_metrics()'::regprocedure))), 0,
  'MET-006 fleet metrics has no source-query row cap'
);
select ok(
  position('statement_timestamp' in lower(pg_get_functiondef('public.owner_metrics(date,date)'::regprocedure))) > 0,
  'MET-006 owner snapshot establishes its as-of instant in the containing statement'
);
select ok(
  position('statement_timestamp' in lower(pg_get_functiondef('public.fleet_metrics()'::regprocedure))) > 0,
  'MET-006 fleet snapshot establishes one captured as-of instant'
);

-- MET-007: response shapes retain non-invented provider/missing-data facts.
select ok(
  position('provider_unconfigured' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0
  and position('outside_v1' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0,
  'MET-007 readiness reports documented unavailable providers instead of inferred readiness'
);
select ok(
  position('undatedPayments' in pg_get_functiondef('app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure)) > 0
  and position('incompletePtOrders' in pg_get_functiondef('app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure)) > 0,
  'MET-007 metrics retain undated and incomplete PT warnings as explicit response facts'
);
select ok(
  position('::text' in pg_get_functiondef('app.gym_metrics(uuid,timestamp with time zone,date,date)'::regprocedure)) > 0,
  'MET-007 metric integer serialization is explicit text, preserving values beyond JavaScript safe integers'
);

-- OPS-001/OPS-004: date validation, timezone isolation and role collision must be explicit.
select ok(
  position('invalid_metrics_range' in pg_get_functiondef('public.owner_metrics(date,date)'::regprocedure)) > 0,
  'OPS-001 owner metrics names the explicit invalid-range contract'
);
select ok(
  position('invalid_gym_timezone' in pg_get_functiondef('public.owner_metrics(date,date)'::regprocedure)) > 0
  and position('invalid_gym_timezone' in pg_get_functiondef('public.fleet_metrics()'::regprocedure)) > 0,
  'OPS-001 owner and fleet keep malformed timezones explicit and isolated'
);
select ok(
  position('pg_timezone_names' in pg_get_functiondef('public.owner_metrics(date,date)'::regprocedure)) > 0,
  'OPS-001 owner metrics validates the configured timezone before local boundaries'
);
select ok(
  position('owner_access' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0
  and position('platform_users' in pg_get_functiondef('app.gym_readiness(uuid)'::regprocedure)) > 0,
  'OPS-004 readiness distinguishes a linked owner from a platform identity collision'
);

select * from finish();

ROLLBACK;
