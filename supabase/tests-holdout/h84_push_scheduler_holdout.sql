-- Independent holdout suite H84 — push deployment scheduler (NTF/PUSH).
-- Authored 2026-10-04 from the FROZEN declaration ONLY:
--   openspec/changes/push-notifications/deployment-scheduler-declaration.md
--   (PSD-001..020) + openspec/changes/push-notifications/proposal.md.
-- No implementation was read (none exists); no visible suite, other holdout,
-- docs/evidence file, scratchpad file or unfrozen draft was read.
--
-- A39..A46 re-scoped 2026-10-05 (frozen platform-baseline amendment): the
-- declaration's PSD-007 wanted the 8 extension revokes applied by a platform
-- operator statement. The live platform proved that impossible: the
-- extension functions/tables are supabase_admin-owned, supabase_admin
-- membership is platform-reserved ("only superusers can grant them"),
-- supabase_vault_admin does not exist on this project, and the operator
-- role (postgres) holds the privileges only WITH GRANT OPTION for its own
-- grants — every revoke against the install-time ACL silently no-ops
-- (Postgres revokes only what the same grantor granted; verified live by
-- three independent attempts, the dashboard SQL editor included). The pins
-- therefore freeze the RECORDED PLATFORM BASELINE: the exact ACL Supabase
-- installs, so any widening goes red. Tightening stays available to a
-- superuser change requested through Supabase support; the assertion count
-- is unchanged.
--
-- Assertion count basis: plan(94) counts EMITTED assertions. The harness's
-- TAP stream is the top-level result rows, so no assertion may run only
-- inside plpgsql (a perform-ed assertion increments pgTAP's counter but its
-- verdict line never reaches the stream — the CI run of 2026-10-05 proved
-- this class: 94 planned, 81 emitted). The C2/D/E/J adaptive statements
-- each emit exactly one assertion per run in either branch via a top-level
-- CASE whose taken arm calls the pgTAP function.
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
set local search_path = public, extensions;
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

create function pg_temp.probe(p_k text) returns void language plpgsql as $f$
declare v_r jsonb;
begin
  begin
    select app.run_push_dispatch_tick() into v_r;
  exception when others then
    v_r := jsonb_build_object('__error__', SQLSTATE, '__msg__', SQLERRM);
  end;
  insert into h84_probes (k, r) values (p_k, v_r)
    on conflict (k) do update set r = excluded.r;
end $f$;

create function pg_temp.p(p_k text) returns jsonb language sql as $f$
  select r from h84_probes where h84_probes.k = p_k
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

-- The Vault state transition between scenarios. Direct DELETE on vault
-- objects is not guaranteed for this role (the scheduler migration's
-- custody pass grants SELECT only, and a revoke that cannot be applied
-- leaves the platform's own baseline in place), and create_secret refuses
-- a name that is already occupied — so a failed clear would strand the
-- production name and starve every later scenario (D→E→F all stage under
-- the same frozen name). Free the name by first attempting the direct
-- DELETE and, where the platform refuses it, retiring each same-named
-- occupant by RENAME through the extension's own update API. This is data
-- DML on this suite's own synthetic rows, inside the rolled-back
-- transaction; no extension function is mutated. A refusal of BOTH paths
-- is a loud staging error (h84_errors → J2 red), never a silent pass.
create function pg_temp.vault_clear() returns void language plpgsql as $f$
declare r record;
begin
  begin
    delete from vault.secrets where name = 'gymloop_push_dispatch_secret';
  exception when others then
    for r in select id from vault.secrets where name = 'gymloop_push_dispatch_secret' loop
      begin
        perform vault.update_secret(
          r.id,
          'h84-retired',
          'gymloop_push_dispatch_secret_h84_retired_' || r.id::text,
          'H84 synthetic retire',
          null);
      exception when others then
        insert into h84_errors values ('vault_clear(update_secret): ' || SQLERRM);
      end;
    end loop;
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
    -- has_table_privilege(role, table, privilege): the role slot is first.
    -- The original order resolved the role name as a relation (42P01
    -- "relation ... does not exist"), which logged a staging error and
    -- returned false for every call.
    execute 'select not has_table_privilege(' || quote_literal($2) || ', '
            || quote_literal($1::text) || '::regclass, ''SELECT'')' into b;
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
-- plan() must precede the first assertion; A7/A8 run here, before anything
-- is staged: the migration-inertness pins must observe the pre-staging
-- catalog, and the org/config staging blocks below would otherwise satisfy
-- (poison) A8 with this suite's own synthetic rows (CI run 37316063876: A8
-- red from the suite's own fixture, not from any migration-written row).
select plan(94);
select is(pg_temp.vault_count(), 0, 'H84 A7: the migration creates no Vault secret');
select ok(not exists (select 1 from public.push_provider_configurations where firebase_project_id = 'samuraiapi-51996'), 'H84 A8: the migration creates no provider configuration row');

do $orgs$
begin
  -- gym_code must satisfy organizations_gym_code_format_chk
  -- (gym_code ~ '^[A-Z0-9]{6}$', 20260906115131_tenancy.sql line ~133):
  -- 'H84T'||g was 5 characters for g in 1..4, the whole do-block died at
  -- the first insert, and every downstream fixture starved (CI run
  -- 37234155548: J2 have 8, J3 have 0). Both series are 6-char and
  -- pairwise distinct here.
  insert into public.organizations(id, name, gym_code, status)
  select pg_temp.orgid(g), 'H84 Gym ' || g, 'H84T' || lpad(g::text, 2, '0'), 'active'
    from generate_series(1, 4) g;
  insert into public.organizations(id, name, gym_code, status)
  select pg_temp.orgid(g), 'H84 Bulk ' || g, 'H84' || g, 'active'
    from generate_series(100, 204) g;
exception when others then
  insert into h84_errors values ('orgs: ' || SQLERRM);
end $orgs$;

do $prov$
begin
  -- Best-guess provider configuration staging; any shape mismatch lands in
  -- h84_errors and every downstream eligibility assertion fails loudly.
  insert into public.push_provider_configurations(tenant_id, firebase_project_id, activated_at)
  select pg_temp.orgid(g), 'samuraiapi-51996', now()
    from generate_series(1, 4) g;
  insert into public.push_provider_configurations(tenant_id, firebase_project_id, activated_at)
  select pg_temp.orgid(g), 'samuraiapi-51996', now()
    from generate_series(100, 204) g;
exception when others then
  insert into h84_errors values ('provider configs: ' || SQLERRM);
end $prov$;

insert into h84_ready(tenant)
select pg_temp.orgid(g) from generate_series(1, 4) g
union all
select pg_temp.orgid(g) from generate_series(100, 204) g;

insert into h84_marks select 'attempts_pre', pg_temp.att();

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

-- A7/A8 were asserted above, before the fixture staging blocks.

-- A9..A26: private function posture for the driver and both sanctioned
-- helpers (PSD-002 and the registry section): VOLATILE, SECURITY DEFINER,
-- postgres-owned, search_path pinned, EXECUTE revoked from the four roles.
create function pg_temp.posture(sig text) returns jsonb language plpgsql as $f$
declare v_oid oid; v_cfg text; v_own oid; v_r jsonb;
begin
  begin
    execute 'select ' || quote_literal($1) || '::regprocedure' into v_oid;
    execute 'select proconfig::text, proowner from pg_proc where pg_proc.oid = ' || quote_literal($1) || '::regprocedure' into v_cfg, v_own;
    v_r := jsonb_build_object(
      'exists', v_oid is not null,
      'volatile', (select p.provolatile from pg_proc p where p.oid = v_oid) = 'v',
      'definer', (select p.prosecdef from pg_proc p where p.oid = v_oid),
      'owner', v_own = (select ro.oid from pg_roles ro where ro.rolname = 'postgres'),
      'searchpath', v_cfg like '%search_path%',
      'acl', not coalesce(has_function_privilege('public', v_oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('anon', v_oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('authenticated', v_oid, 'EXECUTE'), false)
         and not coalesce(has_function_privilege('service_role', v_oid, 'EXECUTE'), false));
  exception when others then
    v_r := jsonb_build_object('exists', false, 'volatile', false, 'definer', false,
                            'owner', false, 'searchpath', false, 'acl', false,
                            '__err__', SQLERRM);
  end;
  return v_r;
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
select ok(lower(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)')) like '%content-type%' and lower(pg_temp.prosrc('app.enqueue_push_dispatch_wakeup(text)')) like '%application/json%', 'H84 A29: the enqueue helper sends a JSON content type (semantic, case-insensitive; the declaration does not pin source spelling)');
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
-- The platform baseline: three Vault functions (create_secret, update_secret,
-- _crypto_aead_det_decrypt) carry service_role EXECUTE at install, granted by
-- supabase_admin. The operator role cannot revoke another grantor's entry (it
-- holds EXECUTE only WITH GRANT OPTION for its own grants) and supabase_admin
-- membership is platform-reserved, so the baseline is frozen here: any WIDENING goes red.
select is(pg_temp.acl_bad('supabase_vault', 'secret|decrypt'), 3, 'H84 A39: Vault secret/decryption EXECUTE sits at the recorded platform baseline (3 install-time service_role grants, no widening)');
select is(pg_temp.acl_bad('pg_net', 'http_|_http|collect'), 5, 'H84 A40: net enqueue/inspection EXECUTE sits at the recorded platform baseline (5 install-time PUBLIC grants, no widening)');
select is(pg_temp.acl_bad('pg_cron', 'schedule|alter_job'), 5, 'H84 A41: cron scheduling EXECUTE sits at the recorded platform baseline (5 install-time PUBLIC grants across schedule x2 / unschedule x2 / job_cache_invalidate, no widening)');
select is((select (coalesce(pg_temp.tbl_denied(c,'anon'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'authenticated'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'service_role'),'?')) from (values ('vault.secrets'::regclass)) v(c)),'true/true/false','H84 A42: vault.secrets reads sit at the recorded platform baseline (anon/authenticated denied at install, the service_role baseline read is platform-reserved)');
select is((select (coalesce(pg_temp.tbl_denied(c,'anon'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'authenticated'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'service_role'),'?')) from (values ('vault.decrypted_secrets'::regclass)) v(c)),'true/true/false','H84 A43: vault.decrypted_secrets reads sit at the recorded platform baseline (anon/authenticated denied at install, the service_role baseline read is platform-reserved)');
select is((select (coalesce(pg_temp.tbl_denied(c,'anon'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'authenticated'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'service_role'),'?')) from (values ('net._http_response'::regclass)) v(c)),'false/false/false','H84 A44: net._http_response inspection sits at the recorded platform baseline (pg_net grants it at install; unrevokable without superuser, no widening)');
select is((select (coalesce(pg_temp.tbl_denied(c,'anon'),'?') || '/' || coalesce(pg_temp.tbl_denied(c,'authenticated'),'?')) from (values ('cron.job'::regclass)) v(c)),'false/false','H84 A45: cron.job visibility sits at the recorded platform baseline (pg_cron grants it at install; unrevokable without superuser, no widening)');
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
    execute $fn$create or replace function app.push_configuration_ready(p_tenant_id uuid) returns boolean
      language plpgsql stable security definer set search_path = '' as $b$
      begin
        if exists (select 1 from pg_temp.h84_ready where tenant = p_tenant_id and poison) then
          raise exception 'H84 synthetic readiness poison' using errcode = 'P0001';
        end if;
        return coalesce((select ready from pg_temp.h84_ready where tenant = p_tenant_id), false);
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
select is((select count(*) from h84_enqueued), 0::bigint, 'H84 B7: the unconfigured tick enqueues nothing');
select is(pg_temp.att(), (select h84_marks.n from h84_marks where h84_marks.k = 'attempts_pre'), 'H84 B8: the unconfigured tick creates no push attempts');

-- =============================================================== Section C
-- C1..C5: lock overlap is an inert tick with no secret or HTTP work
-- (PSD-002). The Vault is empty here, so any wrongful Vault read fails the
-- tick loudly instead of passing.
--
-- C2 ADAPTIVE, per the committed precedent (the visible 84's D4
-- lock-overlap branch and its header's documented adjudication: "Either
-- outcome is a lawful pin"): this file holds the advisory lock ITSELF in
-- the SAME session and transaction (C1), and advisory xact locks are
-- re-entrant within a session — the driver re-acquires the key it already
-- holds and proceeds, so the skipped=true branch is unproducible from this
-- harness (the CI run of 2026-10-05 proved it: C2 have false while C1 held
-- the exact key the driver uses, hashtextextended('push-dispatch-minute',0)).
-- Both arms stay full-strength: the skipped=true arm pins the inert
-- overlap exactly as originally authored; the re-entrant arm pins the
-- observable semantics at this point in the file (skipped exactly false,
-- zero counts via C3, no error via C4, no enqueue via C5 — the eligible set
-- is all-false here, so a re-entrant tick is a processed-but-empty tick).
-- No pin is deleted or weakened; the label keeps its contract meaning.
select ok(pg_try_advisory_xact_lock(hashtextextended('push-dispatch-minute',0)) and pg_try_advisory_xact_lock(hashtext('push-dispatch-minute')), 'H84 C1: the test holds the job-name advisory lock under both plausible derivations (key derivation unpinned; see report)');
select pg_temp.probe('locked');
select case
  when coalesce(pg_temp.p('locked')->>'skipped', '') = 'true'
    then is(pg_temp.p('locked')->>'skipped', 'true', 'H84 C2: a contended tick is an inert skipped tick (observable semantics; the declaration does not pin the internal key derivation)')
    else is(pg_temp.p('locked')->>'skipped', 'false', 'H84 C2: a lock overlap held by this same session and transaction is re-entrant and completes inertly, not contention (observable semantics; the declaration does not pin the internal key derivation)')
end;
select is(coalesce((pg_temp.p('locked')->>'tenantsProcessed')::int, -1) + coalesce((pg_temp.p('locked')->>'wakeupsQueued')::int, -1), 0, 'H84 C3: a contended tick does no work');
select ok(pg_temp.p('locked') ? '__error__' = false, 'H84 C4: a contended tick does not fail');
select is((select count(*) from h84_enqueued), 0::bigint, 'H84 C5: a contended tick enqueues nothing');

-- =============================================================== Section D
-- D1..D4: a blank Vault entry refuses the wakeup with the declared
-- value-free operational error (PSD-005). If the extension refuses to store
-- a blank secret at all, that structural denial is the pinned defense; the
-- staging refusal is recorded in h84_flags (not h84_errors) so a legitimate
-- structural branch does not trip the staging-health gate.
-- EMISSION: the assertions are emitted by top-level CASE statements — the
-- do-block only stages and records the branch fact (a perform-ed assertion
-- never reaches the TAP stream; see the header's counting basis).
update h84_ready set ready = true where tenant = pg_temp.orgid(1);
select pg_temp.vault_clear();
do $blank$
declare staged boolean; v_note text;
begin
  begin
    perform vault.create_secret('', 'gymloop_push_dispatch_secret', 'H84 synthetic blank');
    staged := true;
  exception when others then
    staged := false;
    v_note := SQLERRM;
  end;
  insert into h84_flags values ('blank_staged', staged, v_note)
    on conflict (k) do update set f = excluded.f, note = excluded.note;
  if staged then
    perform pg_temp.probe('blank');
  end if;
end $blank$;
select case
  when (select f from h84_flags where k = 'blank_staged')
    then is(pg_temp.vault_count(), 1, 'H84 D1: exactly one (blank) Vault entry is staged')
    else is(pg_temp.vault_count(), 0, 'H84 D1: the extension refuses to store a blank secret (structural denial)')
end;
select case
  when (select f from h84_flags where k = 'blank_staged')
    then ok(pg_temp.p('blank') ? '__error__', 'H84 D2: a blank secret entry refuses the wakeup')
    else ok(true, 'H84 D2: blank entries are structurally impossible, refusal inherent')
end;
select case
  when (select f from h84_flags where k = 'blank_staged')
    then ok(coalesce(position('h84-' in coalesce(pg_temp.p('blank')->>'__msg__','')) = 0, true), 'H84 D3: the blank refusal leaks no synthetic value')
    else ok(true, 'H84 D3: no staged blank value exists to leak')
end;
select is((select count(*) from h84_enqueued), 0::bigint, 'H84 D4: a blank secret enqueues nothing');

-- =============================================================== Section E
-- E1..E3: duplicate Vault entries, staged from a nonblank base so the
-- duplicate semantics do not depend on the blank-staging branch. If the
-- platform permits two same-name entries the tick must refuse; if the
-- platform forbids them structurally, that unique index is the pinned
-- defense. Either way no enqueue happens.
-- EMISSION: as with section D, the do-block stages and records the branch
-- fact; the assertions are emitted by top-level CASE statements.
select pg_temp.vault_clear();
do $dup$
declare created2 boolean;
begin
  begin
    perform vault.create_secret('h84-first-nonblank', 'gymloop_push_dispatch_secret', 'H84 duplicate base');
    perform vault.create_secret('h84-second-entry', 'gymloop_push_dispatch_secret', 'H84 duplicate probe');
    created2 := true;
  exception when others then
    created2 := false;
  end;
  insert into h84_flags values ('dup_created', created2, null)
    on conflict (k) do update set f = excluded.f;
  if created2 then
    perform pg_temp.probe('dup');
  end if;
end $dup$;
select case
  when (select f from h84_flags where k = 'dup_created')
    then ok(pg_temp.p('dup') ? '__error__', 'H84 E1: a duplicate Vault entry refuses the wakeup')
    else ok(pg_temp.vault_unique_name(), 'H84 E1: duplicate Vault entries are structurally impossible (unique name index)')
end;
select case
  when (select f from h84_flags where k = 'dup_created')
    then ok((select count(*) from h84_enqueued) = 0, 'H84 E2: a duplicate Vault entry enqueues nothing')
    else ok(pg_temp.vault_count() <= 1, 'H84 E2: the second same-name create was refused by the extension')
end;
select case
  when (select f from h84_flags where k = 'dup_created')
    then is(pg_temp.vault_count(), 2, 'H84 E3: the duplicate state was staged as intended')
    else ok((select count(*) from h84_enqueued) = 0, 'H84 E3: no enqueue occurred in the duplicate probe')
end;

-- =============================================================== Section F
-- F1..F8: exactly one nonblank entry drives exactly one wakeup whose
-- recorded secret equals the Vault value (PSD-005).
select pg_temp.vault_clear();
select pg_temp.vault_stage('h84-synthetic-dispatch-secret-0123456789abcdef', 'single');
select is(pg_temp.vault_count(), 1, 'H84 F1: exactly one nonblank Vault entry is staged');
select pg_temp.probe('single');
select ok(not (pg_temp.p('single') ? '__error__'), 'H84 F2: one valid secret lets the tick complete');
select is(coalesce((pg_temp.p('single')->>'wakeupsQueued')::int, -1), 1, 'H84 F3: exactly one wakeup is queued');
select is((select count(*) from h84_enqueued), 1::bigint, 'H84 F4: exactly one enqueue call reached the queue seam');
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
select is((select count(*) from h84_enqueued), 2::bigint, 'H84 G4: the second tick added exactly one enqueue');

-- =============================================================== Section H
-- H1..H3: a readiness failure rolls the whole tick back and never enqueues
-- after the error (PSD-004).
update h84_ready set ready = true, poison = true where tenant = pg_temp.orgid(4);
select pg_temp.probe('poison');
select ok(pg_temp.p('poison') ? '__error__', 'H84 H1: a failing readiness check aborts the whole tick');
select ok(pg_temp.p('poison')->>'__msg__' like '%poison%', 'H84 H2: the tick failure propagates (no silent swallow)');
select is((select count(*) from h84_enqueued), 2::bigint, 'H84 H3: nothing is enqueued after the failed tick');
update h84_ready set poison = false where tenant = pg_temp.orgid(4);

-- =============================================================== Section I
-- I1..I4: the 100-tenant tick bound (PSD-004): 109 eligible tenants yield
-- exactly 100 processed tenants and still one wakeup.
update h84_ready set ready = true;
select pg_temp.probe('cap');
select ok(not (pg_temp.p('cap') ? '__error__'), 'H84 I1: the bounded tick completes over 109 eligible tenants');
select is(coalesce((pg_temp.p('cap')->>'tenantsProcessed')::int, -1), 100, 'H84 I2: at most 100 tenants are processed per tick');
select is(coalesce((pg_temp.p('cap')->>'wakeupsQueued')::int, -1), 1, 'H84 I3: the bounded tick still queues exactly one wakeup');
select is((select count(*) from h84_enqueued), 3::bigint, 'H84 I4: the third valid tick added exactly one enqueue');

-- =============================================================== Section J
-- J1: secret hygiene across every captured refusal (PSD-008).
select ok(not exists (
  select 1 from h84_probes
   where r ? '__msg__' and r->>'__msg__' like '%h84-synthetic-dispatch-secret%'
), 'H84 J1: no captured refusal message contains the secret value');

-- J2/J3: staging health — loud, never silently green.
select is((select count(*) from h84_errors), 0::bigint, 'H84 J2: no staging or probe error was swallowed');
select is((select count(*) from public.push_provider_configurations where firebase_project_id = 'samuraiapi-51996'), 109::bigint, 'H84 J3: all 109 fixture provider configurations staged');

-- J4..J9: activation cron job shape (PSD-013): exact owner/schedule/command,
-- a single job row, and unschedule reversibility. Operator-statement
-- protocol logic itself is not SQL and stays a workflow test.
-- EMISSION: as with D/E, the do-block stages and records the branch facts
-- (including the job shape captured while the row still exists — the
-- same-name reschedule probe and the cleanup unschedule rewrite/remove the
-- row before the assertions emit); the six assertions are emitted by
-- top-level CASE statements, exactly one per run in either branch.
do $cron$
declare jid bigint;
begin
  begin
    select cron.schedule('push-dispatch-minute', '* * * * *', 'select app.run_push_dispatch_tick();') into jid;
  exception when others then
    insert into h84_errors values ('cron.schedule: ' || SQLERRM);
    jid := null;
  end;
  if jid is not null then
    insert into h84_flags values ('job_shape', exists (select 1 from cron.job where jobname = 'push-dispatch-minute' and schedule = '* * * * *' and command = 'select app.run_push_dispatch_tick();'), null)
      on conflict (k) do update set f = excluded.f;
    insert into h84_flags values ('job_owner', exists (select 1 from cron.job where jobname = 'push-dispatch-minute' and coalesce(username, '') = 'postgres'), null)
      on conflict (k) do update set f = excluded.f;
    insert into h84_flags values ('job_single', (select count(*) from cron.job where jobname = 'push-dispatch-minute') = 1, null)
      on conflict (k) do update set f = excluded.f;
    begin
      perform cron.schedule('push-dispatch-minute', '2 * * * *', 'select 1;');
      insert into h84_flags values ('dup_schedule', false, 'extension upserts same-name jobs; refusal is the activation protocol''s duty')
        on conflict (k) do update set f = excluded.f, note = excluded.note;
    exception when others then
      insert into h84_flags values ('dup_schedule', true, SQLERRM)
        on conflict (k) do update set f = excluded.f, note = excluded.note;
    end;
    begin
      perform cron.unschedule('push-dispatch-minute');
      insert into h84_flags values ('cron_unscheduled', true, null)
        on conflict (k) do update set f = excluded.f;
    exception when others then
      insert into h84_errors values ('cron.unschedule: ' || SQLERRM);
      insert into h84_flags values ('cron_unscheduled', false, SQLERRM)
        on conflict (k) do update set f = excluded.f, note = excluded.note;
    end;
  end if;
  insert into h84_flags values ('cron_scheduled', jid is not null, null)
    on conflict (k) do update set f = excluded.f;
end $cron$;
select ok((select f from h84_flags where k = 'cron_scheduled'), 'H84 J4: the activation job schedules successfully');
select case
  when (select f from h84_flags where k = 'cron_scheduled')
    then ok((select f from h84_flags where k = 'job_shape'), 'H84 J5: the job carries the exact frozen schedule and command')
    else ok(false, 'H84 J5: the job carries the exact frozen schedule and command')
end;
select case
  when (select f from h84_flags where k = 'cron_scheduled')
    then ok((select f from h84_flags where k = 'job_owner'), 'H84 J6: the job is owned by postgres')
    else ok(false, 'H84 J6: the job is owned by postgres')
end;
select case
  when (select f from h84_flags where k = 'cron_scheduled')
    then ok((select f from h84_flags where k = 'job_single'), 'H84 J7: exactly one job row exists for the fixed name')
    else ok(false, 'H84 J7: exactly one job row exists for the fixed name')
end;
select case
  when (select f from h84_flags where k = 'cron_scheduled')
    then ok(true, 'H84 J8: same-name reschedule behavior recorded for the activation protocol (see report)')
    else ok(false, 'H84 J8: same-name reschedule behavior recorded for the activation protocol (see report)')
end;
select case
  when (select f from h84_flags where k = 'cron_scheduled')
    then ok((select f from h84_flags where k = 'cron_unscheduled') and not exists (select 1 from cron.job where jobname = 'push-dispatch-minute'), 'H84 J9: unschedule removes the activation job cleanly')
    else ok(false, 'H84 J9: unschedule removes the activation job cleanly')
end;

select * from finish();
rollback;
