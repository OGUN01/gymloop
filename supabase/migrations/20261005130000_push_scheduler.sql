-- NTF push scheduler — inert deployment migration (frozen mechanical
-- declaration PSD-001..PSD-008, 2026-10-04).
-- Authority: openspec/changes/push-notifications/deployment-scheduler-declaration.md
-- (authoritative) + proposal.md. This migration is INERT at apply time: it
-- creates no pg_cron job, no configuration row, no Vault secret, reads no
-- decrypted secret and performs no network/provider operation. It declares the
-- supported pg_net and supabase_vault extensions, applies the frozen extension
-- custody denials, and installs exactly three private trusted helpers:
--   app.run_push_dispatch_tick()          — the cyclic minute driver
--   app.read_push_dispatch_secret()       — exact one/nonblank Vault lookup
--   app.enqueue_push_dispatch_wakeup(text)— the fixed HTTP wakeup request
-- Activation (the unique `push-dispatch-minute` cron job with command
-- `select app.run_push_dispatch_tick();`) and pause stay reviewed protected
-- operator statements (PSD-013/PSD-014); no additional public SQL facade
-- exists here. The migration never rewrites 20261004090000_push_delivery.sql.

-- ---------------------------------------------------------------------------
-- 1. Extension declaration (PSD-001). Platform-supported schemas; both are
--    expected to pre-exist on Cloud, so these statements are no-ops there.
-- ---------------------------------------------------------------------------
create extension if not exists pg_net with schema net;
create extension if not exists supabase_vault with schema vault;

-- Named apply-time assumption guard: the custody revokes below target the
-- exact `net`/`vault`/`cron` schemas. If a platform relocates an extension to
-- a different schema, fail here with a refusal that names the problem and the
-- actual schema instead of a generic revoke error.
do $extension_schema_guard$
declare
  v_schema text;
begin
  if to_regnamespace('net') is null then
    raise exception 'push_scheduler: extension_schema_unexpected schema net is absent';
  end if;
  if to_regnamespace('vault') is null then
    raise exception 'push_scheduler: extension_schema_unexpected schema vault is absent';
  end if;
  if to_regnamespace('cron') is null then
    raise exception 'push_scheduler: extension_schema_unexpected schema cron is absent';
  end if;
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pg_net';
  if v_schema is distinct from 'net' then
    raise exception 'push_scheduler: extension_schema_unexpected pg_net lives in schema %, expected net', v_schema;
  end if;
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'supabase_vault';
  if v_schema is distinct from 'vault' then
    raise exception 'push_scheduler: extension_schema_unexpected supabase_vault lives in schema %, expected vault', v_schema;
  end if;
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pg_cron';
  if v_schema is distinct from 'cron' then
    raise exception 'push_scheduler: extension_schema_unexpected pg_cron lives in schema %, expected cron', v_schema;
  end if;
end
$extension_schema_guard$;

-- ---------------------------------------------------------------------------
-- 2. Extension custody (PSD-007/PSD-008). Effective denial for ordinary
--    callers on Vault plaintext/decryption and secret mutation, on net queue/
--    header/response inspection and HTTP enqueue, and on cron scheduling and
--    schedule-table reads. Explicit per-role revokes follow the PUBLIC revoke
--    because the platform pre-grants extension schemas to anon/authenticated/
--    service_role. Only the trusted postgres operator/worker path retains the
--    execution privileges it needs; extension-internal privileges (owned by
--    the extension owners) are untouched and no extension function is altered.
--    Existing unrelated cron schedules remain operational: their worker path
--    does not depend on caller EXECUTE of cron scheduling functions.
-- ---------------------------------------------------------------------------
revoke usage on schema vault from public, anon, authenticated, service_role;
revoke all on all tables in schema vault from public, anon, authenticated, service_role;
revoke execute on all functions in schema vault from public, anon, authenticated, service_role;

revoke usage on schema net from public, anon, authenticated, service_role;
revoke all on all tables in schema net from public, anon, authenticated, service_role;
revoke execute on all functions in schema net from public, anon, authenticated, service_role;

revoke usage on schema cron from public, anon, authenticated, service_role;
revoke all on all tables in schema cron from public, anon, authenticated, service_role;
revoke execute on all functions in schema cron from public, anon, authenticated, service_role;

-- Trusted custody retained for the postgres-owned driver and the protected
-- operator activation/pause statements only (PSD-013/PSD-014 run as postgres
-- through the linked CLI).
grant usage on schema vault to postgres;
grant select on all tables in schema vault to postgres;
grant execute on all functions in schema vault to postgres;

grant usage on schema net to postgres;
grant select on all tables in schema net to postgres;
grant execute on all functions in schema net to postgres;

grant usage on schema cron to postgres;
grant select on all tables in schema cron to postgres;
grant execute on all functions in schema cron to postgres;

-- ---------------------------------------------------------------------------
-- 3. app.read_push_dispatch_secret (PSD-005). Exact one nonblank Vault entry
--    named `gymloop_push_dispatch_secret`; missing/duplicate/blank refuses
--    with a fixed value-free operational error. One statement reads both the
--    candidate and its filtered count so missing and duplicate share one
--    snapshot. Never substitutes a service key; never logs or returns context
--    beyond the fixed messages.
-- ---------------------------------------------------------------------------
create function app.read_push_dispatch_secret()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_secret text;
  v_count bigint;
begin
  select s.decrypted_secret, count(*) over ()
    into v_secret, v_count
    from vault.decrypted_secrets s
   where s.name = 'gymloop_push_dispatch_secret';

  if v_count is null or v_count = 0 then
    raise exception 'push_dispatch_wakeup: secret configuration unavailable';
  end if;
  if v_count > 1 then
    raise exception 'push_dispatch_wakeup: secret configuration ambiguous';
  end if;
  if v_secret is null or btrim(v_secret) = '' then
    raise exception 'push_dispatch_wakeup: secret configuration unusable';
  end if;
  return v_secret;
end
$fn$;
alter function app.read_push_dispatch_secret() owner to postgres;
revoke all on function app.read_push_dispatch_secret() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.enqueue_push_dispatch_wakeup (PSD-005). Exactly one net.http_post to
--    the approved Edge endpoint: empty JSON body, Content-Type plus the
--    dedicated-secret header, 5000 ms timeout. No authorization JWT, no
--    recipient, no tenant selector, no query string, no redirecting endpoint.
--    The queued request is only a wakeup — never acceptance or receipt. The
--    helper returns void so the pg_net request id never escapes the seam.
-- ---------------------------------------------------------------------------
create function app.enqueue_push_dispatch_wakeup(p_secret text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if p_secret is null or btrim(p_secret) = '' then
    raise exception 'push_dispatch_wakeup: secret configuration unusable';
  end if;
  perform net.http_post(
    url => 'https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch',
    body => '{}'::jsonb,
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'x-gymloop-push-dispatch-secret', p_secret),
    timeout_milliseconds => 5000);
end
$fn$;
alter function app.enqueue_push_dispatch_wakeup(text) owner to postgres;
revoke all on function app.enqueue_push_dispatch_wakeup(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.run_push_dispatch_tick (PSD-002..PSD-006). The only scheduler
--    command; executed by the trusted postgres cron owner as
--    `select app.run_push_dispatch_tick();`. Transaction advisory try-lock
--    keyed by the fixed job name; contention is an inert skipped tick with
--    zero counts and no secret access or HTTP request. Driver eligibility
--    comes only from tenant-keyed push_provider_configurations through the
--    existing app.push_configuration_ready(uuid); an empty eligible set
--    returns zero counts without reading Vault. One statement captures the
--    eligible set so count and selection share one statement-time snapshot;
--    the tick instant for the cyclic offset is captured once at function
--    entry. Each selected tenant delegates to the existing private
--    app.run_push_events(uuid) exactly once — no duplicated predicates, no
--    broad no-show scan, no attempt reservation, no FCM call from SQL. The
--    tick is bounded to 100 tenants selected cyclically ascending from
--    (floor(epoch(statement_timestamp())/60)*100) modulo eligible_count,
--    wrapping once. Secret lookup and the single wakeup enqueue happen only
--    after all selected runners succeed; any runner error aborts the
--    transaction so the tick rolls back with nothing enqueued. The result
--    carries exactly the seven declared keys; no request id, tenant/member
--    id, token, header, credential, provider id or raw exception escapes.
-- ---------------------------------------------------------------------------
create function app.run_push_dispatch_tick()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tick timestamptz := statement_timestamp();
  v_eligible uuid[];
  v_count integer := 0;
  v_offset bigint;
  v_take integer;
  v_idx integer;
  v_runner jsonb;
  v_ann integer := 0;
  v_children integer := 0;
  v_reminders integer := 0;
  v_absence integer := 0;
  v_processed integer := 0;
  v_secret text;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('push-dispatch-minute', 0)) then
    return jsonb_build_object(
      'tenantsProcessed', 0, 'announcementEvents', 0, 'pushChildren', 0,
      'classReminders', 0, 'absenceEvents', 0, 'wakeupsQueued', 0,
      'skipped', true);
  end if;

  select array_agg(c.tenant_id order by c.tenant_id), count(*)::integer
    into v_eligible, v_count
    from public.push_provider_configurations c
   where app.push_configuration_ready(c.tenant_id);

  if v_count = 0 or v_eligible is null then
    return jsonb_build_object(
      'tenantsProcessed', 0, 'announcementEvents', 0, 'pushChildren', 0,
      'classReminders', 0, 'absenceEvents', 0, 'wakeupsQueued', 0,
      'skipped', false);
  end if;

  v_offset := (floor(extract(epoch from v_tick) / 60)::bigint * 100) % v_count::bigint;
  v_take := least(100, v_count);

  for v_idx in 0 .. (v_take - 1) loop
    v_runner := app.run_push_events(
      v_eligible[1 + ((v_offset + v_idx) % v_count::bigint)::integer]);
    v_ann := v_ann + coalesce((v_runner->>'announcementEvents')::integer, 0);
    v_children := v_children + coalesce((v_runner->>'pushChildren')::integer, 0);
    v_reminders := v_reminders + coalesce((v_runner->>'classReminders')::integer, 0);
    v_absence := v_absence + coalesce((v_runner->>'absenceEvents')::integer, 0);
    v_processed := v_processed + 1;
  end loop;

  v_secret := app.read_push_dispatch_secret();
  perform app.enqueue_push_dispatch_wakeup(v_secret);

  return jsonb_build_object(
    'tenantsProcessed', v_processed, 'announcementEvents', v_ann,
    'pushChildren', v_children, 'classReminders', v_reminders,
    'absenceEvents', v_absence, 'wakeupsQueued', 1, 'skipped', false);
end
$fn$;
alter function app.run_push_dispatch_tick() owner to postgres;
revoke all on function app.run_push_dispatch_tick() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- End. No activation here: the unique `push-dispatch-minute` job with the
-- `* * * * *` schedule and the private driver command is created only by the
-- protected `activate` operation (PSD-013), after the PSD-010/PSD-019 gate
-- chain, in one trusted transaction that also validates explicit tenant
-- selection. Pause (PSD-014) unschedules only that job and removes the Edge
-- wakeup secret. No secret value ever appears in this migration, its logs,
-- audit rows or any repository artifact (PSD-008).
-- ---------------------------------------------------------------------------
