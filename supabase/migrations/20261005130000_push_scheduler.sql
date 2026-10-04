-- NTF push scheduler — inert deployment migration (frozen mechanical
-- declaration PSD-001..PSD-008, 2026-10-04; extension-placement facts
-- corrected 2026-10-04 from first runtime evidence).
-- Authority: openspec/changes/push-notifications/deployment-scheduler-declaration.md
-- (authoritative) + proposal.md. This migration is INERT at apply time: it
-- creates no cron job, no configuration row, no Vault secret, reads no
-- decrypted secret and performs no network/provider operation. It declares the
-- supported extensions and applies the frozen extension custody denials, and
-- installs exactly three private trusted helpers:
--   app.run_push_dispatch_tick()          — the cyclic minute driver
--   app.read_push_dispatch_secret()       — exact one/nonblank Vault lookup
--   app.enqueue_push_dispatch_wakeup(text)— the fixed HTTP wakeup request
-- Activation (the unique `push-dispatch-minute` cron job with command
-- `select app.run_push_dispatch_tick();`) and pause stay reviewed protected
-- operator statements (PSD-013/PSD-014); no additional public SQL facade
-- exists here. The migration never rewrites 20261004090000_push_delivery.sql.
-- Runtime-established extension reality on the approved project: pg_cron is
-- installed in `pg_catalog` (precedent migration 20260909170000 declares it
-- with no schema clause), supabase_vault in `vault`, and pg_net was absent —
-- it is declared into `extensions` following the repo precedent
-- (20260906115131_tenancy.sql / 20260906115153_catalogue.sql).

-- ---------------------------------------------------------------------------
-- 1. Extension reality guard — BEFORE any create-extension statement, so a
--    placement drift is refused by name instead of failing a later revoke
--    with a generic error. pg_net absence is recorded, not refused.
-- ---------------------------------------------------------------------------
do $extension_schema_guard$
declare
  v_schema text;
  v_installed boolean;
begin
  if to_regnamespace('pg_catalog') is null then
    raise exception 'push_scheduler: extension_schema_unexpected pg_catalog is absent';
  end if;
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pg_cron';
  if v_schema is distinct from 'pg_catalog' then
    raise exception 'push_scheduler: extension_schema_unexpected pg_cron lives in schema %, expected pg_catalog', coalesce(v_schema, '(absent)');
  end if;

  if to_regnamespace('vault') is null then
    raise exception 'push_scheduler: extension_schema_unexpected schema vault is absent';
  end if;
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'supabase_vault';
  if v_schema is distinct from 'vault' then
    raise exception 'push_scheduler: extension_schema_unexpected supabase_vault lives in schema %, expected vault', coalesce(v_schema, '(absent)');
  end if;

  if to_regnamespace('extensions') is null then
    raise exception 'push_scheduler: extension_schema_unexpected schema extensions is absent';
  end if;
  select exists (select 1 from pg_extension where extname = 'pg_net') into v_installed;
  raise notice 'push_scheduler: pg_net installed before declaration: %', v_installed;
end
$extension_schema_guard$;

-- pg_net is declared into the `extensions` schema per repo precedent;
-- supabase_vault stays in `vault` (no-op where the platform pre-installed it).
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- Post-declaration placement check: if pg_net landed anywhere other than
-- `extensions`, refuse by name before any custody statement runs.
do $extension_placement_guard$
declare
  v_schema text;
begin
  select n.nspname into v_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pg_net';
  if v_schema is distinct from 'extensions' then
    raise exception 'push_scheduler: extension_schema_unexpected pg_net lives in schema %, expected extensions', coalesce(v_schema, '(absent)');
  end if;
end
$extension_placement_guard$;

-- ---------------------------------------------------------------------------
-- 2. Extension custody (PSD-007/PSD-008), scoped to the real object homes.
--    vault: per-object ACL statements — Vault internals (including the
--    pgsodium crypto helpers behind `decrypted_secrets`) are not all owned or
--    grantable by the apply role, so a blanket schema-wide
--    grant/revoke can abort the apply with `permission denied for function
--    _crypto_aead_det_encrypt`. Each object is attempted individually: a
--    denial that cannot be applied by the apply role is recorded with a
--    notice (the independent ACL suites pin effective custody and will flag
--    any real gap), and a failure to grant the one object the driver's Vault
--    read path needs (`vault.decrypted_secrets`) is a NAMED refusal.
--    pg_net objects live inside the SHARED `extensions` schema, so a blanket
--    revoke there would touch unrelated extensions — the revokes enumerate
--    exactly the objects that belong to the pg_net extension via pg_depend.
--    pg_cron objects live in `pg_catalog`, so a schema-scoped revoke there is
--    forbidden; the revokes enumerate exactly the pg_cron member functions
--    (scheduling surface) and tables via pg_depend. The trusted postgres
--    operator/worker path retains only what it needs; extension-internal
--    owner privileges are untouched and no extension function is altered.
--    Existing unrelated cron schedules remain operational: their worker path
--    does not depend on caller EXECUTE of the scheduling functions.
-- ---------------------------------------------------------------------------
-- A transaction-local ACL applier: try the statement as the apply role; on
-- insufficient privilege, retry once per candidate owning role via
-- `set local role` (the apply role may hold membership of the extension
-- owners). The helper lives in pg_temp and dies with the migration
-- transaction — no persistent object, no public facade.
do $custody_acl_setup$
begin
  create function pg_temp.psd_acl(p_sql text, p_owner_roles text[])
  returns boolean
  language plpgsql
  volatile
  as $acl$
  declare
    own text;
  begin
    begin
      execute p_sql;
      return true;
    exception when insufficient_privilege then
      null;
    end;
    foreach own in array p_owner_roles loop
      begin
        execute 'set local role ' || quote_ident(own);
        execute p_sql;
        execute 'reset role';
        return true;
      exception when others then
        begin
          execute 'reset role';
        exception when others then
          null;
        end;
      end;
    end loop;
    return false;
  end
  $acl$;
end
$custody_acl_setup$;

do $vault_custody$
declare
  r record;
  v_ok boolean;
  v_owners text[] := array['supabase_admin', 'supabase_vault_admin'];
begin
  if not pg_temp.psd_acl(
    'revoke usage on schema vault from public, anon, authenticated, service_role',
    v_owners) then
    raise notice 'push_scheduler: vault schema-usage denial skipped (not grantable by the apply role or its owner roles)';
  end if;
  for r in
    select c.oid::regclass as obj, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'vault' and c.relkind in ('r', 'v', 'p', 'f')
  loop
    v_ok := pg_temp.psd_acl(
      'revoke all on ' || r.obj::text || ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant select on ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      if r.relname = 'decrypted_secrets' then
        raise exception 'push_scheduler: custody_refused vault view decrypted_secrets is not grantable by the apply role; the driver Vault read path cannot be installed';
      end if;
      raise notice 'push_scheduler: vault custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
  for r in
    select p.oid::regprocedure as obj
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'vault'
  loop
    v_ok := pg_temp.psd_acl(
      'revoke execute on function ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant execute on function ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: vault custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
end
$vault_custody$;
grant usage on schema vault to postgres;

-- pg_net member objects (wherever pg_depend says they live — `extensions`
-- after section 1): effective denial for ordinary callers.
do $net_custody$
declare
  r record;
  v_ok boolean;
  v_owners text[] := array['supabase_admin'];
begin
  for r in
    select p.oid::regprocedure as obj
      from pg_depend d
      join pg_proc p on p.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pg_net'
       and d.classid = 'pg_proc'::regclass
       and d.deptype = 'e'
    union
    select p.oid::regprocedure as obj
      from pg_proc p
      join pg_extension e on e.extnamespace = p.pronamespace
     where e.extname = 'pg_net'
       and p.proname ~ '^(http_|_http)'
  loop
    v_ok := pg_temp.psd_acl(
      'revoke execute on function ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant execute on function ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: net custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
  for r in
    select c.oid::regclass as obj
      from pg_depend d
      join pg_class c on c.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pg_net'
       and d.classid = 'pg_class'::regclass
       and d.deptype = 'e'
       and c.relkind in ('r', 'v', 'p', 'f')
  loop
    v_ok := pg_temp.psd_acl(
      'revoke all on ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant select on ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: net custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
end
$net_custody$;

-- pg_cron member objects (in `pg_catalog` on this project): deny the
-- scheduling surface and schedule-table reads for ordinary callers, scoped to
-- exactly the extension's member objects — never blanket pg_catalog revokes.
do $cron_custody$
declare
  r record;
  v_ok boolean;
  v_owners text[] := array['supabase_admin'];
begin
  for r in
    select p.oid::regprocedure as obj
      from pg_depend d
      join pg_proc p on p.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pg_cron'
       and d.classid = 'pg_proc'::regclass
       and d.deptype = 'e'
    union
    select p.oid::regprocedure as obj
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = (select n2.nspname from pg_extension e2 join pg_namespace n2 on n2.oid = e2.extnamespace where e2.extname = 'pg_cron')
       and p.proname in ('schedule', 'unschedule', 'schedule_in_database',
                         'alter_job', 'remove_job')
  loop
    v_ok := pg_temp.psd_acl(
      'revoke execute on function ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant execute on function ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: cron custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
  for r in
    select c.oid::regclass as obj
      from pg_depend d
      join pg_class c on c.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pg_cron'
       and d.classid = 'pg_class'::regclass
       and d.deptype = 'e'
       and c.relkind in ('r', 'v', 'p', 'f')
  loop
    v_ok := pg_temp.psd_acl(
      'revoke all on ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant select on ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: cron custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
end
$cron_custody$;

-- ---------------------------------------------------------------------------
-- 3. Trusted-only pgsodium execution grants. Vault's decrypted view and
--    pgsodium's apply-time DDL event machinery call crypto internals
--    (`_crypto_aead_det_encrypt` and siblings) that pgsodium keeps
--    EXECUTE-denied from PUBLIC. The helper's definer chain runs as postgres,
--    so the trusted postgres path needs explicit member grants for the Vault
--    read path to work (and for the migration's own `create extension` to
--    apply cleanly in environments where that machinery runs under the apply
--    role). Nothing here grants to anon/authenticated/service_role/public —
--    ordinary-role custody is unchanged.
-- ---------------------------------------------------------------------------
do $pgsodium_trust_grants$
declare
  r record;
  v_present boolean;
  v_ok boolean;
  v_owners text[] := array['supabase_admin'];
begin
  select exists (select 1 from pg_extension where extname = 'pgsodium') into v_present;
  if not v_present then
    raise notice 'push_scheduler: pgsodium is not installed; the vault read path cannot be verified here';
    return;
  end if;
  -- The pgsodium crypto surface is the Vault plaintext/decryption machinery
  -- (PSD-007): ordinary roles lose EXECUTE regardless of schema placement,
  -- then only the trusted postgres path is granted back.
  for r in
    select p.oid::regprocedure as obj
      from pg_depend d
      join pg_proc p on p.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pgsodium'
       and d.classid = 'pg_proc'::regclass
       and d.deptype = 'e'
  loop
    v_ok := pg_temp.psd_acl(
      'revoke execute on function ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant execute on function ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: pgsodium custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
  for r in
    select c.oid::regclass as obj
      from pg_depend d
      join pg_class c on c.oid = d.objid
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'pgsodium'
       and d.classid = 'pg_class'::regclass
       and d.deptype = 'e'
       and c.relkind in ('r', 'v', 'p', 'f')
  loop
    v_ok := pg_temp.psd_acl(
      'revoke all on ' || r.obj::text ||
      ' from public, anon, authenticated, service_role',
      v_owners);
    if v_ok then
      v_ok := pg_temp.psd_acl('grant select on ' || r.obj::text || ' to postgres', v_owners);
    end if;
    if not v_ok then
      raise notice 'push_scheduler: pgsodium custody skipped for % (not grantable by the apply role or its owner roles)', r.obj::text;
    end if;
  end loop;
end
$pgsodium_trust_grants$;

-- ---------------------------------------------------------------------------
-- 4. app.read_push_dispatch_secret (PSD-005). Exact one nonblank Vault entry
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
-- 5. app.enqueue_push_dispatch_wakeup (PSD-005). Exactly one pg_net HTTP POST
--    to the approved Edge endpoint: empty JSON body, Content-Type plus the
--    dedicated-secret header, 5000 ms timeout. No authorization JWT, no
--    recipient, no tenant selector, no query string, no redirecting endpoint.
--    The queued request is only a wakeup — never acceptance or receipt. The
--    helper returns void so the pg_net request id never escapes the seam.
--    pg_net lives in the `extensions` schema on this project, so the call is
--    extension-qualified.
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
  perform extensions.http_post(
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
-- 6. app.run_push_dispatch_tick (PSD-002..PSD-006). The only scheduler
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
