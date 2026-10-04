-- Independent holdout suite H84 — push deployment scheduler (NTF/PUSH).
-- Authored 2026-10-04 from the FROZEN declaration ONLY:
--   openspec/changes/push-notifications/deployment-scheduler-declaration.md
--   (PSD-001..020) + openspec/changes/push-notifications/proposal.md.
-- No implementation was read (none exists); no visible suite, other holdout,
-- docs/evidence file, scratchpad file or unfrozen draft was read.
--
-- RED BY DESIGN: `20261005130000_push_scheduler.sql` is unbuilt, so every
-- app.run_push_dispatch_tick / app.read_push_dispatch_secret /
-- app.enqueue_push_dispatch_wakeup probe fails loudly today. Catalog armor
-- (extensions, cron/Vault inertness, extension ACL posture) may already hold.
--
-- Declared seams (declaration sanctions exactly these): this suite replaces
-- app.push_configuration_ready with a synthetic narrowed predicate backed by
-- pg_temp.h84_ready, and app.enqueue_push_dispatch_wakeup with a synthetic
-- recorder. Both seams are postgres-owned definer with EXECUTE revoked from
-- public/anon/authenticated/service_role; no ordinary access is granted and
-- no real HTTP request is enqueued from this file. The Vault matrix below
-- exercises the REAL app.read_push_dispatch_secret against REAL
-- supabase_vault rows holding synthetic values only; nothing here reads a
-- real credential. The real enqueue helper's fixed request construction is
-- pinned via catalog prosrc before the seam swap; per the declaration that
-- static pin does not replace production transport verification.
--
-- Rollback-only: one lowercase begin;/rollback; pair; nothing commits; no
-- extension function is mutated (only the two sanctioned app helpers are
-- replaced transactionally); all fixture ids use the 84500000- prefix.
begin;
set local role postgres;
set local time zone 'Asia/Kolkata';
set local search_path = public;
select set_config('request.jwt.claims','',true);

-- ---------------------------------------------------------------- fixtures
create temp table h84_errors(line text not null);
create temp table h84_flags(k text primary key, f boolean not null, note text);
create temp table h84_probes(k text primary key, r jsonb not null);
create temp table h84_enqueued(secret text, called_at timestamptz default clock_timestamp());
create temp table h84_ready(tenant uuid primary key, ready boolean not null default false, poison boolean not null default false);
create temp table h84_marks(k text primary key, n bigint not null);

create function pg_temp.orgid(g int) returns uuid language sql as $f$
  select ('84500000-0000-4000-8000-' || lpad(to_hex($1), 12, '0'))::uuid
$f$;

create function pg_temp.probe(k text) returns void language plpgsql as $f$
declare r jsonb;
begin
  begin
    select app.run_push_dispatch_tick() into r;
  exception when others then
    r := jsonb_build_object('__error__', SQLSTATE, '__msg__', SQLERRM);
  end;
  insert into h84_probes values (k, r)
    on conflict (k) do update set r = excluded.r;
end $f$;

create function pg_temp.p(k text) returns jsonb language sql as $f$
  select r from h84_probes where h84_probes.k = $1
$f$;

create function pg_temp.att() returns bigint language plpgsql as $f$
declare n bigint;
begin
  begin
    execute 'select count(*) from public.notification_push_attempts' into n;
  exception when others then
    insert into h84_errors values ('attempts count: ' || SQLERRM);
    n := -1;
  end;
  return n;
end $f$;

create function pg_temp.vault_count() returns int language plpgsql as $f$
declare n int;
begin
  begin
    execute 'select count(*)::int from vault.secrets where name = ''gymloop_push_dispatch_secret''' into n;
  exception when others then
    insert into h84_errors values ('vault_count: ' || SQLERRM);
    n := -1;
  end;
  return n;
end $f$;

create function pg_temp.vault_stage(val text, how text) returns void language plpgsql as $f$
begin
  begin
    perform vault.create_secret(val, 'gymloop_push_dispatch_secret', 'H84 synthetic test secret');
  exception when others then
    insert into h84_errors values ('vault_stage(' || how || '): ' || SQLERRM);
  end;
end $f$;

create function pg_temp.vault_clear() returns void language plpgsql as $f$
begin
  begin
    delete from vault.secrets where name = 'gymloop_push_dispatch_secret';
  exception when others then
    insert into h84_errors values ('vault_clear: ' || SQLERRM);
  end;
end $f$;

create function pg_temp.vault_unique_name() returns boolean language plpgsql as $f$
declare b boolean;
begin
  begin
    execute 'select exists (select 1 from pg_indexes where schemaname = ''vault'' and tablename = ''secrets'' and indexdef ~* ''unique'' and indexdef ~* ''name'')' into b;
  exception when others then
    b := false;
  end;
  return b;
end $f$;

-- Denial counter over extension-owned functions: counts effective EXECUTE
-- grants held by public/anon/authenticated/service_role on functions of the
-- given extension matching the proname filter. -1 means the catalog probe
-- itself failed (staging health, never a silent pass).
create function pg_temp.acl_bad(ext text, name_pat text) returns int language plpgsql as $f$
declare n int;
begin
  begin
    execute format($q$
      select count(*)::int from pg_proc p
        join pg_depend d on d.objid = p.oid and d.deptype = 'e'
        join pg_extension e on e.oid = d.refobjid
       where e.extname = %L
         and p.proname ~ %L
         and (has_function_privilege('public', p.oid, 'EXECUTE')
           or has_function_privilege('anon', p.oid, 'EXECUTE')
           or has_function_privilege('authenticated', p.oid, 'EXECUTE')
           or has_function_privilege('service_role', p.oid, 'EXECUTE'))
    $q$, ext, name_pat) into n;
  exception when others then
    insert into h84_errors values ('acl_bad(' || ext || '): ' || SQLERRM);
    n := -1;
  end;
  return n;
end $f$;

create function pg_temp.tbl_denied(tbl regclass, who text) returns boolean language plpgsql as $f$
declare b boolean;
begin
  begin
    execute 'select not has_table_privilege(' || quote_literal($1::text) || '::regclass, ' || quote_literal($2) || ', ''SELECT'')' into b;
  exception when others then
    insert into h84_errors values ('tbl_denied: ' || SQLERRM);
    b := false;
  end;
  return b;
end $f$;

create function pg_temp.prosrc(fn regprocedure) returns text language plpgsql as $f$
declare s text;
begin
  begin
    execute 'select prosrc from pg_proc where oid = ' || quote_literal($1::text) || '::regprocedure' into s;
  exception when others then
    insert into h84_errors values ('prosrc(' || $1::text || '): ' || SQLERRM);
    s := null;
  end;
  return coalesce(s, '');
end $f$;

-- ---------------------------------------------------------------- fixtures
do $orgs$
begin
  insert into public.organizations(id, name, gym_code, status)
  select pg_temp.orgid(g), 'H84 Gym ' || g, 'H84B' || g, 'active'
    from generate_series(1, 4) g;
  insert into public.organizations(id, name, gym_code, status)
  select pg_temp.orgid(g), 'H84 Bulk ' || g, 'H84B' || g, 'active'
    from generate_series(1000, 1104) g;
exception when others then
  insert into h84_errors values ('orgs: ' || SQLERRM);
end $orgs$;

do $prov$
begin
  -- Best-guess provider configuration staging; any shape mismatch lands in
  -- h84_errors and every downstream eligibility assertion fails loudly.
  insert into public.push_provider_configurations(id, tenant_id, firebase_project_id, activated_at)
  select pg_temp.orgid(g), pg_temp.orgid(g), 'samuraiapi-51996', now()
    from generate_series(1, 4) g;
  insert into public.push_provider_configurations(id, tenant_id, firebase_project_id, activated_at)
  select pg_temp.orgid(g), pg_temp.orgid(g), 'samuraiapi-51996', now()
    from generate_series(1000, 1104) g;
exception when others then
  insert into h84_errors values ('provider configs: ' || SQLERRM);
end $prov$;

insert into h84_ready(tenant)
select pg_temp.orgid(g) from generate_series(1, 4) g
union all
select pg_temp.orgid(g) from generate_series(1000, 1104) g;

insert into h84_marks select 'attempts_pre', pg_temp.att();

-- ---------------------------------------------------------------- plan
select plan(94);

-- =============================================================== Section A
-- A1..A3: declared extensions are present (PSD-001).
select ok(exists (select 1 from pg_extension where extname = 'pg_cron'), 'H84 A1: pg_cron is installed');
select ok(exists (select 1 from pg_extension where extname = 'pg_net'), 'H84 A2: pg_net is installed');
select ok(exists (select 1 from pg_extension where extname = 'supabase_vault'), 'H84 A3: supabase_vault is installed');

-- A4..A6: migration inertness — no scheduler job, no tick wiring, no WSP
-- schedule exists after the migration set applies (PSD-001/013).
select is((select count(*) from cron.job where jobname = 'push-dispatch-minute'), 0::bigint, 'H84 A4: the migration creates no cron job');
select ok(not exists (select 1 from cron.job where command like '%run_push_dispatch_tick%'), 'H84 A5: no schedule references the driver before activation');
select ok(not exists (select 1 from cron.job where jobname ~* 'wsp|whatsapp' or command ~* 'whatsapp'), 'H84 A6: no WSP/WhatsApp schedule exists (PSD-013)');

-- A7/A8: no Vault secret and no provider configuration row were created by
-- the migration (PSD-001); asserted before this suite stages anything.
select is(pg_temp.vault_count(), 0, 'H84 A7: the migration creates no Vault secret');
select ok(not exists (select 1 from public.push_provider_configurations where firebase_project_id = 'samuraiapi-51996'), 'H84 A8: the migration creates no provider configuration row');

-- A9..A26: private function posture for the driver and both sanctioned
-- helpers (PSD-002 and the registry section): VOLATILE, SECURITY DEFINER,
-- postgres-owned, search_path pinned, EXECUTE revoked from the four roles.
create function pg_temp.posture(sig text) returns jsonb language plpgsql as $f$
declare oid oid; cfg text; own oid; r jsonb;
begin
  begin
    execute 'select ' || quote_literal($1) || '::regprocedure' into oid;
    execute 'select proconfig::text, proowner from pg_proc where oid = ' || quote_literal($1) || '::regprocedure' into cfg, own;
    r := jsonb_build_object(
      'exists', oid is not null,
      'volatile', (select provolatile from pg_proc where oid = oid) = 'v',
      'definer', (select prosecdef from pg_proc where oid = oid),
      'owner', own = (select oid from pg_roles where rolname = 'postgres'),
      'searchpath', cfg like '%search_path%',
      'acl', not coalesce(has_function_privilege('public', oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('anon', oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('authenticated', oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('service_role', oid, 'EXECUTE'), false));
  exception when others then
    r := jsonb_build_object('exists', false, 'volatile', false, 'definer', false,
                            'owner', false, 'searchpath', false, 'acl', false,
                            '__err__', SQLERRM);
  end;
  return r;
end $f$;

select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'exists' = 'true', 'H84 A9: the driver exists');
select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'volatile' = 'true', 'H84 A10: the driver is VOLATILE');
select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'definer' = 'true', 'H84 A11: the driver is SECURITY DEFINER');
select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'owner' = 'true', 'H84 A12: the driver is postgres-owned');
select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'searchpath' = 'true', 'H84 A13: the driver pins search_path');
select ok(pg_temp.posture('app.run_push_dispatch_tick()')->>'acl' = 'true', 'H84 A14: the driver denies public/anon/authenticated/service_role');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'exists' = 'true', 'H84 A15: the secret helper exists');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'volatile' = 'true', 'H84 A16: the secret helper is VOLATILE');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'definer' = 'true', 'H84 A17: the secret helper is SECURITY DEFINER');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'owner' = 'true', 'H84 A18: the secret helper is postgres-owned');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'searchpath' = 'true', 'H84 A19: the secret helper pins search_path');
select ok(pg_temp.posture('app.read_push_dispatch_secret()')->>'acl' = 'true', 'H84 A20: the secret helper denies the four roles');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'exists' = 'true', 'H84 A21: the enqueue helper exists');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'volatile' = 'true', 'H84 A22: the enqueue helper is VOLATILE');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'definer' = 'true', 'H84 A23: the enqueue helper is SECURITY DEFINER');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'owner' = 'true', 'H84 A24: the enqueue helper is postgres-owned');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'searchpath' = 'true', 'H84 A25: the enqueue helper pins search_path');
select ok(pg_temp.posture('app.enqueue_push_dispatch_wakeup(text)')->>'acl' = 'true', 'H84 A26: the enqueue helper denies the four roles');

-- A27..A38: catalog prosrc pins of the REAL helpers against the frozen
-- request construction (PSD-005) and driver delegation (PSD-003/004).
-- Static by nature; production transport verification remains a separate
-- protected gate per the declaration's own caveat.
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') like '%https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch%', 'H84 A27: the enqueue helper targets the frozen endpoint');
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') like '%x-gymloop-push-dispatch-secret%', 'H84 A28: the enqueue helper sends the dedicated-secret header');
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') like '%Content-Type: application/json%', 'H84 A29: the enqueue helper sends the JSON content type');
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') like '%5000%', 'H84 A30: the enqueue helper uses the 5000 ms timeout');
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') not like '%Authorization%' and pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') not like '%apikey%' and pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') not like '%Bearer%', 'H84 A31: the enqueue helper carries no authorization credential');
select ok(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)') like '%{}%', 'H84 A32: the enqueue helper posts an empty JSON body');
select ok(pg_temp.prosrc('app.read_push_dispatch_secret()') like '%gymloop_push_dispatch_secret%', 'H84 A33: the secret helper reads the frozen Vault name');
select ok(pg_temp.prosrc('app.read_push_dispatch_secret()') not like '%http_post%', 'H84 A34: the secret helper performs no HTTP work');
select ok(pg_temp.prosrc('app.run_push_dispatch_tick()') like '%run_push_events%', 'H84 A35: the driver delegates to the existing event runner');
select ok(pg_temp.prosrc('app.run_push_dispatch_tick()') like '%push-dispatch-minute%', 'H84 A36: the driver locks on the fixed job name');
select ok(pg_temp.prosrc('app.run_push_dispatch_tick()') not like '%http_post%', 'H84 A37: the driver never enqueues directly (PSD-002)');
select ok(pg_temp.prosrc('app.run_push_dispatch_tick()') like '%statement_timestamp%', 'H84 A38: the driver derives its rotation offset from statement time');

-- A39..A46: extension custody — effective denial of Vault plaintext and
-- mutation, net inspection and enqueue, cron scheduling (PSD-007).
select is(pg_temp.acl_bad('supabase_vault', 'secret|decrypt'), 0, 'H84 A39: no ordinary role executes Vault secret/decryption functions');
select is(pg_temp.acl_bad('pg_net', 'http_|_http|collect'), 0, 'H84 A40: no ordinary role executes net enqueue/inspection functions');
select is(pg_temp.acl_bad('pg_cron', 'schedule|alter_job'), 0, 'H84 A41: no ordinary role executes cron scheduling functions');
select ok(pg_temp.tbl_denied('vault.secrets', 'anon') and pg_temp.tbl_denied('vault.secrets', 'authenticated') and pg_temp.tbl_denied('vault.secrets', 'service_role'), 'H84 A42: vault.secrets SELECT is denied to ordinary roles');
select ok(pg_temp.tbl_denied('vault.decrypted_secrets', 'anon') and pg_temp.tbl_denied('vault.decrypted_secrets', 'authenticated') and pg_temp.tbl_denied('vault.decrypted_secrets', 'service_role'), 'H84 A43: vault.decrypted_secrets is denied to ordinary roles');
select ok(pg_temp.tbl_denied('net._http_response', 'anon') and pg_temp.tbl_denied('net._http_response', 'authenticated') and pg_temp.tbl_denied('net._http_response', 'service_role'), 'H84 A44: net._http_response queue inspection is denied');
select ok(pg_temp.tbl_denied('cron.job', 'anon') and pg_temp.tbl_denied('cron.job', 'authenticated'), 'H84 A45: cron.job is hidden from member-facing roles');
select ok(pg_temp.tbl_denied('public.push_provider_configurations', 'anon') and pg_temp.tbl_denied('public.push_provider_configurations', 'authenticated'), 'H84 A46: provider configuration is not member-readable');

-- =============================================================== Section B
-- Seams installed (sanctioned); readiness narrowed to all-false first.
create function pg_temp.install_seams() returns void language plpgsql as $f$
begin
  begin
    execute $fn$create or replace function app.enqueue_push_dispatch_wakeup(p_secret text) returns void
      language plpgsql volatile security definer set search_path = '' as $b$
      begin
        insert into pg_temp.h84_enqueued(secret) values (p_secret);
      end$b$$fn$;
    execute 'revoke all on function app.enqueue_push_dispatch_wakeup(text) from public, anon, authenticated, service_role';
  exception when others then
    insert into h84_errors values ('enqueue seam: ' || SQLERRM);
  end;
  begin
    execute $fn$create or replace function app.push_configuration_ready(p_tenant uuid) returns boolean
      language plpgsql stable security definer set search_path = '' as $b$
      begin
        if exists (select 1 from pg_temp.h84_ready where tenant = p_tenant and poison) then
          raise exception 'H84 synthetic readiness poison' using errcode = 'P0001';
        end if;
        return coalesce((select ready from pg_temp.h84_ready where tenant = p_tenant), false);
      end$b$$fn$;
    execute 'revoke all on function app.push_configuration_ready(uuid) from public, anon, authenticated, service_role';
  exception when others then
    insert into h84_errors values ('readiness seam: ' || SQLERRM);
  end;
end $f$;
select pg_temp.install_seams();

-- B1..B8: unconfigured eligible set (PSD-003): zero counts, no Vault work,
-- no attempts, no enqueue, exact shape.
select pg_temp.probe('unconfigured');
select ok(not (pg_temp.p('unconfigured') ? '__error__'), 'H84 B1: an empty eligible set returns without error');
select is(pg_temp.p('unconfigured') ? 'tenantsProcessed' and pg_temp.p('unconfigured') ? 'announcementEvents' and pg_temp.p('unconfigured') ? 'pushChildren' and pg_temp.p('unconfigured') ? 'classReminders' and pg_temp.p('unconfigured') ? 'absenceEvents' and pg_temp.p('unconfigured') ? 'wakeupsQueued' and pg_temp.p('unconfigured') ? 'skipped' and jsonb_array_length(jsonb_path_query_array(pg_temp.p('unconfigured'), '$.keyvalue()')) = 7, true, 'H84 B2: the driver result is exactly the frozen seven keys');
select is(coalesce((pg_temp.p('unconfigured')->>'tenantsProcessed')::int, -1), 0, 'H84 B3: zero tenants are processed when unconfigured');
select is(coalesce((pg_temp.p('unconfigured')->>'announcementEvents')::int, -1) + coalesce((pg_temp.p('unconfigured')->>'pushChildren')::int, -1) + coalesce((pg_temp.p('unconfigured')->>'classReminders')::int, -1) + coalesce((pg_temp.p('unconfigured')->>'absenceEvents')::int, -1), 0, 'H84 B4: all four event counts are zero when unconfigured');
select is(coalesce((pg_temp.p('unconfigured')->>'wakeupsQueued')::int, -1), 0, 'H84 B5: no wakeup is queued when unconfigured');
select is(pg_temp.p('unconfigured')->>'skipped', 'false', 'H84 B6: an unconfigured tick is a processed tick, not a skipped one');
select is((select count(*) from h84_enqueued), 0, 'H84 B7: the unconfigured tick enqueues nothing');
select is(pg_temp.att(), (select n from h84_marks where k = 'attempts_pre'), 'H84 B8: the unconfigured tick creates no push attempts');

-- =============================================================== Section C
-- C1..C5: lock overlap is an inert skipped tick with no secret or HTTP work
-- (PSD-002). The Vault is empty here, so any wrongful Vault read fails the
-- tick loudly instead of passing.
select ok(pg_try_advisory_xact_lock(hashtext('push-dispatch-minute')), 'H84 C1: the test holds the job-name advisory lock (hashtext derivation; see report)');
select pg_temp.probe('locked');
select is(pg_temp.p('locked')->>'skipped', 'true', 'H84 C2: a contended tick is an inert skipped tick');
select is(coalesce((pg_temp.p('locked')->>'tenantsProcessed')::int, -1) + coalesce((pg_temp.p('locked')->>'wakeupsQueued')::int, -1), 0, 'H84 C3: a contended tick does no work');
select ok(pg_temp.p('locked') ? '__error__' = false, 'H84 C4: a contended tick does not fail');
select is((select count(*) from h84_enqueued), 0, 'H84 C5: a contended tick enqueues nothing');

-- =============================================================== Section D
-- D1..D4: a blank Vault entry refuses the wakeup with a value-free
-- operational error (PSD-005).
update h84_ready set ready = true where tenant = pg_temp.orgid(1);
select pg_temp.vault_clear();
select pg_temp.vault_stage('', 'blank');
select is(pg_temp.vault_count(), 1, 'H84 D1: exactly one (blank) Vault entry is staged');
select pg_temp.probe('blank');
select ok(pg_temp.p('blank') ? '__error__', 'H84 D2: a blank secret entry refuses the wakeup');
select ok(coalesce(position('h84-' in coalesce(pg_temp.p('blank')->>'__msg__','')) = 0, true), 'H84 D3: the blank refusal leaks no synthetic value');
select is((select count(*) from h84_enqueued), 0, 'H84 D4: a blank secret enqueue nothing');

-- =============================================================== Section E
-- E1..E3: duplicate Vault entries. If the platform permits two same-name
-- entries the tick must refuse; if the platform forbids them structurally,
-- that unique index is the pinned defense. Either way no enqueue happens.
do $dup$
declare created2 boolean; r jsonb;
begin
  begin
    perform vault.create_secret('h84-second-entry', 'gymloop_push_dispatch_secret', 'H84 duplicate probe');
    created2 := true;
  exception when others then
    created2 := false;
  end;
  insert into h84_flags values ('dup_created', created2, null)
    on conflict (k) do update set f = excluded.f;
  if created2 then
    perform pg_temp.probe('dup');
    r := pg_temp.p('dup');
    ok(r ? '__error__', 'H84 E1: a duplicate Vault entry refuses the wakeup');
    ok((select count(*) from h84_enqueued) = 0, 'H84 E2: a duplicate Vault entry enqueues nothing');
    ok(pg_temp.vault_count() = 2, 'H84 E3: the duplicate state was staged as intended');
  else
    ok(pg_temp.vault_unique_name(), 'H84 E1: duplicate Vault entries are structurally impossible (unique name index)');
    ok(pg_temp.vault_count() = 1, 'H84 E2: the second same-name create was refused by the extension');
    ok((select count(*) from h84_enqueued) = 0, 'H84 E3: no enqueue occurred in the duplicate probe');
  end if;
end $dup$;

-- =============================================================== Section F
-- F1..F8: exactly one nonblank entry drives exactly one wakeup whose
-- recorded secret equals the Vault value (PSD-005).
select pg_temp.vault_clear();
select pg_temp.vault_stage('h84-synthetic-dispatch-secret-0123456789abcdef', 'single');
select is(pg_temp.vault_count(), 1, 'H84 F1: exactly one nonblank Vault entry is staged');
select pg_temp.probe('single');
select ok(not (pg_temp.p('single') ? '__error__'), 'H84 F2: one valid secret lets the tick complete');
select is(coalesce((pg_temp.p('single')->>'wakeupsQueued')::int, -1), 1, 'H84 F3: exactly one wakeup is queued');
select is((select count(*) from h84_enqueued), 1, 'H84 F4: exactly one enqueue call reached the queue seam');
select is((select secret from h84_enqueued limit 1), 'h84-synthetic-dispatch-secret-0123456789abcdef', 'H84 F5: the enqueued wakeup carries the decrypted Vault value');
select is(coalesce((pg_temp.p('single')->>'tenantsProcessed')::int, -1), 1, 'H84 F6: the ready tenant was processed');
select ok(pg_temp.p('single') ? 'tenantsProcessed' and pg_temp.p('single') ? 'announcementEvents' and pg_temp.p('single') ? 'pushChildren' and pg_temp.p('single') ? 'classReminders' and pg_temp.p('single') ? 'absenceEvents' and pg_temp.p('single') ? 'wakeupsQueued' and pg_temp.p('single') ? 'skipped' and jsonb_array_length(jsonb_path_query_array(pg_temp.p('single'), '$.keyvalue()')) = 7, 'H84 F7: the valid-secret result keeps the exact seven-key shape');
select is(pg_temp.p('single')->>'skipped', 'false', 'H84 F8: a valid-secret tick is not skipped');

-- =============================================================== Section G
-- G1..G4: mixed tenant readiness — only ready tenants are processed
-- (PSD-003), one wakeup per tick regardless (PSD-005).
update h84_ready set ready = true where tenant = pg_temp.orgid(3);
select pg_temp.probe('mixed');
select ok(not (pg_temp.p('mixed') ? '__error__'), 'H84 G1: a mixed-readiness tick completes');
select is(coalesce((pg_temp.p('mixed')->>'tenantsProcessed')::int, -1), 2, 'H84 G2: exactly the ready tenants are processed');
select is(coalesce((pg_temp.p('mixed')->>'wakeupsQueued')::int, -1), 1, 'H84 G3: still exactly one wakeup per tick');
select is((select count(*) from h84_enqueued), 2, 'H84 G4: the second tick added exactly one enqueue');

-- =============================================================== Section H
-- H1..H3: a readiness failure rolls the whole tick back and never enqueues
-- after the error (PSD-004).
update h84_ready set ready = true, poison = true where tenant = pg_temp.orgid(4);
select pg_temp.probe('poison');
select ok(pg_temp.p('poison') ? '__error__', 'H84 H1: a failing readiness check aborts the whole tick');
select ok(pg_temp.p('poison')->>'__msg__' like '%poison%', 'H84 H2: the tick failure propagates (no silent swallow)');
select is((select count(*) from h84_enqueued), 2, 'H84 H3: nothing is enqueued after the failed tick');
update h84_ready set poison = false where tenant = pg_temp.orgid(4);

-- =============================================================== Section I
-- I1..I4: the 100-tenant tick bound (PSD-004): 109 eligible tenants yield
-- exactly 100 processed tenants and still one wakeup.
update h84_ready set ready = true;
select pg_temp.probe('cap');
select ok(not (pg_temp.p('cap') ? '__error__'), 'H84 I1: the bounded tick completes over 109 eligible tenants');
select is(coalesce((pg_temp.p('cap')->>'tenantsProcessed')::int, -1), 100, 'H84 I2: at most 100 tenants are processed per tick');
select is(coalesce((pg_temp.p('cap')->>'wakeupsQueued')::int, -1), 1, 'H84 I3: the bounded tick still queues exactly one wakeup');
select is((select count(*) from h84_enqueued), 3, 'H84 I4: the third valid tick added exactly one enqueue');

-- =============================================================== Section J
-- J1: secret hygiene across every captured refusal (PSD-008).
select ok(not exists (
  select 1 from h84_probes
   where r ? '__msg__' and r->>'__msg__' like '%h84-synthetic-dispatch-secret%'
), 'H84 J1: no captured refusal message contains the secret value');

-- J2/J3: staging health — loud, never silently green.
select is((select count(*) from h84_errors), 0, 'H84 J2: no staging or probe error was swallowed');
select is((select count(*) from public.push_provider_configurations where firebase_project_id = 'samuraiapi-51996'), 109, 'H84 J3: all 109 fixture provider configurations staged');

-- J4..J9: activation cron job shape (PSD-013): exact owner/schedule/command,
-- a single job row, and unschedule reversibility. Operator-statement
-- protocol logic itself is not SQL and stays a workflow test.
do $cron$
declare jid bigint; dup_err text;
begin
  begin
    select cron.schedule('push-dispatch-minute', '* * * * *', 'select app.run_push_dispatch_tick();') into jid;
  exception when others then
    insert into h84_errors values ('cron.schedule: ' || SQLERRM);
    jid := null;
  end;
  if jid is not null then
    ok(true, 'H84 J4: the activation job schedules successfully');
    ok(exists (select 1 from cron.job where jobname = 'push-dispatch-minute' and schedule = '* * * * *' and command = 'select app.run_push_dispatch_tick();'), 'H84 J5: the job carries the exact frozen schedule and command');
    ok(exists (select 1 from cron.job where jobname = 'push-dispatch-minute' and coalesce(username, '') = 'postgres'), 'H84 J6: the job is owned by postgres');
    ok((select count(*) from cron.job where jobname = 'push-dispatch-minute') = 1, 'H84 J7: exactly one job row exists for the fixed name');
    begin
      perform cron.schedule('push-dispatch-minute', '2 * * * *', 'select 1;');
      insert into h84_flags values ('dup_schedule', false, 'extension upserts same-name jobs; refusal is the activation protocol''s duty');
    exception when others then
      insert into h84_flags values ('dup_schedule', true, SQLERRM);
    end;
    ok(true, 'H84 J8: same-name reschedule behavior recorded for the activation protocol (see report)');
    begin
      perform cron.unschedule('push-dispatch-minute');
      ok(not exists (select 1 from cron.job where jobname = 'push-dispatch-minute'), 'H84 J9: unschedule removes the activation job cleanly');
    exception when others then
      insert into h84_errors values ('cron.unschedule: ' || SQLERRM);
      ok(false, 'H84 J9: unschedule removes the activation job cleanly');
    end;
  else
    ok(false, 'H84 J4: the activation job schedules successfully');
    ok(false, 'H84 J5: the job carries the exact frozen schedule and command');
    ok(false, 'H84 J6: the job is owned by postgres');
    ok(false, 'H84 J7: exactly one job row exists for the fixed name');
    ok(false, 'H84 J8: same-name reschedule behavior recorded for the activation protocol (see report)');
    ok(false, 'H84 J9: unschedule removes the activation job cleanly');
  end if;
end $cron$;

select * from finish();
rollback;
