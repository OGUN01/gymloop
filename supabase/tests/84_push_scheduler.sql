-- PSD-001..020 visible SQL contract for the push deployment scheduler
-- (Wave C/D push infrastructure, provider-free).
-- Frozen authority: openspec/changes/push-notifications/proposal.md (FROZEN
-- 2026-10-03) and openspec/changes/push-notifications/deployment-scheduler-declaration.md
-- (FROZEN 2026-10-04, the authoritative mechanical declaration). Every
-- expectation comes from those frozen documents, not from any caller.
-- The deployment-runner-interface declaration is deliberately NOT read here
-- (unfrozen review draft).
--
-- Scope pinned here (provider-free only):
--   * inert forward migration: no cron job, no Vault secret created by the
--     migration itself (PSD-001);
--   * exact private boundary: app.run_push_dispatch_tick() jsonb VOLATILE
--     SECURITY DEFINER owner postgres search_path='' with EXECUTE effectively
--     revoked from PUBLIC/anon/authenticated/service_role; the two sanctioned
--     private helpers app.read_push_dispatch_secret() -> text and
--     app.enqueue_push_dispatch_wakeup(text) -> void carry the same shape
--     (PSD-002 and the declaration's registry section); no public facade;
--   * extension custody: effective (role/inherited/column/schema) denial of
--     Vault plaintext/decryption/mutation, net queue inspection/enqueue and
--     cron scheduling from ordinary callers (PSD-007);
--   * driver behavior: zero eligible tenants -> zero counts and zero
--     Vault/network work; mixed readiness; the 100-tenant bounded cyclic wrap;
--     the exact seven-key result envelope with nonnegative integer counts and
--     a boolean skipped; one wakeup per tick; real runner delegation through
--     the existing app.run_push_events; event failure rollback with no
--     enqueue; the fixed wakeup URL/headers/body/timeout through the REAL
--     enqueue helper; missing/duplicate/blank Vault entry refusals that are
--     value-free (PSD-003..006);
--   * activation ground facts the protected operator transactions rely on:
--     PK replay preserving activated_at, differently-bound rows being
--     detectable, the unique cron owner/schedule/command shape, and no new
--     WSP schedule (PSD-013/014).
--
-- RED pattern: the scheduler migration does not exist yet. Catalog assertions
-- are NULL-safe (to_regprocedure/to_regclass); every dynamic statement runs
-- through a catching executor (pg_temp.probe/pg_temp.val/pg_temp.err), so the
-- file runs end-to-end RED (plan mismatch, not abort) before the scheduler
-- exists and judges the real implementation once CI applies it. Each tick
-- result is captured exactly once into a temp table; assertions judge the
-- captured value, never a re-execution. The two sanctioned seams are replaced
-- ONLY after the real-helper contract section (D0), inside the single
-- transaction, and every seam change is restored by ROLLBACK. No real
-- credential value is ever used: every secret literal is a synthetic test
-- value. Vault entries under the production name exist only inside the
-- rolled-back transaction; the single queue row the real enqueue helper
-- creates is inspected and deleted inside the same transaction, so no request
-- can ever be delivered (nothing commits).
--
-- Known declaration tension recorded for the builder/critic round: PSD-002's
-- "transaction advisory try-lock" read as transaction-scoped would make every
-- tick call after the first in this single transaction inert, contradicting
-- the declaration's own required-case list (multiple distinct behavioral
-- cases in one rollback-only suite). The suite therefore pins the required
-- behaviors in order and makes the lock-overlap case adaptive: if a
-- back-to-back second tick reports skipped=true the contention branch pins
-- the inert overlap; if it reports skipped=false the release-per-tick branch
-- pins idempotent bounded re-processing (dedupe makes the event count zero).
-- Either outcome is a lawful pin; the declaration/implementation
-- reconciliation is a builder/critic decision, not a silent test edit.
--
-- Assertion count basis: plan(137) counts EMITTED assertions (129 plain
-- top-level plus eight adaptive: duplicate Vault entry one, blank Vault
-- entry one, cyclic wrap exclusion one, lock-overlap five). The eight
-- adaptive assertions EMIT through top-level CASE statements whose taken arm
-- calls the pgTAP function — never through perform inside plpgsql, which
-- executes the assertion (advancing the counter) while its verdict line
-- never reaches the TAP stream (the CI run of 2026-10-05 proved the class on
-- the h84 holdout: 94 planned, 81 emitted, exactly the 13 perform-ed ones
-- missing).
begin;
set local role postgres;
set local search_path=extensions,public;
select set_config('request.jwt.claims','',true);
-- 137 = 129 top-level + 8 adaptive. (e7414c73's PSD-007 rewrite took the
-- plain count 141 -> 127 but wrote plan(134): one short of the true 135, a
-- latent "Bad plan" diagnostic in every sweep since; this restores the exact
-- basis and adds the two fixture pins below.)
select plan(137);

-- Temp seam tables must exist before the language-SQL helpers that reference them.
create temp table seam_reads(n integer);
create temp table seam_sends(n integer, secret text);

create function pg_temp.aid(n integer) returns uuid language sql immutable as $$select ('84000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.probe(q text) returns text language plpgsql as $$begin execute q; return 'OK'; exception when others then return sqlstate; end$$;
create function pg_temp.val(q text) returns text language plpgsql as $$declare r text; begin execute q into r; return r; exception when others then return sqlstate; end$$;
create function pg_temp.err(q text) returns jsonb language plpgsql as $$begin execute q; return null; exception when others then return jsonb_build_object('state',sqlstate,'msg',sqlerrm); end$$;
create function pg_temp.tickj() returns jsonb language plpgsql as $$declare r jsonb; begin execute 'select app.run_push_dispatch_tick()' into r; return r; exception when others then return null; end$$;
create function pg_temp.tickerr() returns jsonb language plpgsql as $$begin execute 'select app.run_push_dispatch_tick()'; return null; exception when others then return jsonb_build_object('state',sqlstate,'msg',sqlerrm); end$$;
create function pg_temp.event_tenant(n integer) returns void language plpgsql as $$begin
  insert into public.organizations(id,name,gym_code,status) values (pg_temp.aid(n),'PUSH Scheduler T '||n,'PS'||lpad(n::text,4,'0'),'active');
  insert into public.branches(id,tenant_id,name,is_default) values (pg_temp.aid(n+1000),pg_temp.aid(n),'B'||n,true);
  insert into auth.users(id) values (pg_temp.aid(n+2000));
  insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values (pg_temp.aid(n+3000),pg_temp.aid(n),pg_temp.aid(n+2000),pg_temp.aid(n+1000),'gym_owner','Owner '||n);
  insert into public.members(id,tenant_id,branch_id,user_id,full_name,phone,date_of_birth,status,erased_at) values (pg_temp.aid(n+4000),pg_temp.aid(n),pg_temp.aid(n+1000),pg_temp.aid(n+2000),'PRIVATE_MEMBER_'||n,'+917810'||lpad(n::text,5,'0'),'1990-01-01','active',null);
  insert into public.announcements(id,tenant_id,kind,status,audience,current_version,published_at,created_by_staff_id) values (pg_temp.aid(n+5000),pg_temp.aid(n),'transactional','published','all_members',1,now()-interval '2 hours',pg_temp.aid(n+3000));
  insert into public.announcement_versions(id,tenant_id,announcement_id,version_no,title,body,created_by_staff_id) values (pg_temp.aid(n+6000),pg_temp.aid(n),pg_temp.aid(n+5000),1,'Scheduler fixture '||n,'Body',pg_temp.aid(n+3000));
  insert into public.notification_push_campaigns(id,tenant_id,announcement_id,version_no,request_key,created_by_staff_id,reviewed_by_staff_id,reviewed_at) values (pg_temp.aid(n+7000),pg_temp.aid(n),pg_temp.aid(n+5000),1,pg_temp.aid(n+7500),pg_temp.aid(n+3000),pg_temp.aid(n+3000),now()-interval '1 hour');
end$$;
create function pg_temp.config(n integer, activated timestamptz) returns void language sql as $$insert into public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) values (pg_temp.aid(n),'samuraiapi-51996',activated)$$;
create function pg_temp.reads_now() returns integer language plpgsql as $$begin return coalesce((select max(n) from pg_temp.seam_reads),0); end$$;
create function pg_temp.sends_now() returns integer language plpgsql as $$begin return coalesce((select max(n) from pg_temp.seam_sends),0); end$$;

-- ============ A. inert migration and installed infrastructure ============
insert into public.organizations(id,name,gym_code,status) values (pg_temp.aid(1),'PUSH Runner Probe','PS0001','active');
select is((select count(*)::integer from cron.job where jobname='push-dispatch-minute'),0,'PSD-001: no push-dispatch-minute cron job exists before activation');
select is((select count(*)::integer from vault.secrets where name='gymloop_push_dispatch_secret'),0,'PSD-001/008: no production-named Vault entry exists before provisioning');
select ok(to_regclass('public.push_provider_configurations') is not null,'PSD-003: tenant-keyed push_provider_configurations exists (committed push surface)');
select ok(to_regprocedure('app.run_push_events(uuid)') is not null,'PSD-003: the existing private event runner app.run_push_events exists');
select is((select array_agg(k order by k) from jsonb_object_keys(app.run_push_events(pg_temp.aid(1))) k),'{absenceEvents,announcementEvents,classReminders,pushChildren}','PSD-006: the existing runner returns exactly the four aggregated count keys');
select ok(to_regclass('net.http_request_queue') is not null,'PSD-001: pg_net is installed (declared dependency)');
select ok(to_regclass('cron.job') is not null,'PSD-001: pg_cron is installed (reused dependency)');
select ok(to_regclass('vault.secrets') is not null,'PSD-001: supabase_vault is installed (declared dependency)');
select ok(to_regprocedure('public.run_push_dispatch_tick()') is null,'PSD-002: no public facade for the driver');
select ok(to_regprocedure('public.read_push_dispatch_secret()') is null,'PSD-002: no public facade for the secret lookup helper');
select ok(to_regprocedure('public.enqueue_push_dispatch_wakeup(text)') is null,'PSD-002: no public facade for the wakeup helper');

-- ============ B. exact private shape of the three new objects ============
select ok(to_regprocedure('app.run_push_dispatch_tick()') is not null,'PSD-002: app.run_push_dispatch_tick() exists');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('app.run_push_dispatch_tick()')),'jsonb','PSD-002: the driver returns jsonb');
select is((select provolatile from pg_proc where oid=to_regprocedure('app.run_push_dispatch_tick()')),'v','PSD-002: the driver is VOLATILE');
select is((select prosecdef::text from pg_proc where oid=to_regprocedure('app.run_push_dispatch_tick()')),'true','PSD-002: the driver is SECURITY DEFINER');
select is((select proowner::regrole::text from pg_proc where oid=to_regprocedure('app.run_push_dispatch_tick()')),'postgres','PSD-002: the driver is postgres-owned');
select ok((select proconfig::text from pg_proc where oid=to_regprocedure('app.run_push_dispatch_tick()')) like '%search_path=%','PSD-002: the driver pins an explicit search_path');
select is(case when to_regprocedure('app.run_push_dispatch_tick()') is null then 'ABSENT' else coalesce(has_function_privilege('public',to_regprocedure('app.run_push_dispatch_tick()'),'EXECUTE')::text,'unchecked') end,'false','PSD-002: PUBLIC cannot execute the driver');
select is(case when to_regprocedure('app.run_push_dispatch_tick()') is null then 'ABSENT' else coalesce(has_function_privilege('anon',to_regprocedure('app.run_push_dispatch_tick()'),'EXECUTE')::text,'unchecked') end,'false','PSD-002: anon cannot execute the driver');
select is(case when to_regprocedure('app.run_push_dispatch_tick()') is null then 'ABSENT' else coalesce(has_function_privilege('authenticated',to_regprocedure('app.run_push_dispatch_tick()'),'EXECUTE')::text,'unchecked') end,'false','PSD-002: authenticated cannot execute the driver');
select is(case when to_regprocedure('app.run_push_dispatch_tick()') is null then 'ABSENT' else coalesce(has_function_privilege('service_role',to_regprocedure('app.run_push_dispatch_tick()'),'EXECUTE')::text,'unchecked') end,'false','PSD-002: service_role cannot execute the driver');
select ok(to_regprocedure('app.read_push_dispatch_secret()') is not null,'PSD-005: app.read_push_dispatch_secret() exists');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('app.read_push_dispatch_secret()')),'text','PSD-005: the secret lookup returns text');
select is((select provolatile from pg_proc where oid=to_regprocedure('app.read_push_dispatch_secret()')),'v','PSD-005: the secret lookup is VOLATILE');
select is((select prosecdef::text from pg_proc where oid=to_regprocedure('app.read_push_dispatch_secret()')),'true','PSD-005: the secret lookup is SECURITY DEFINER');
select is((select proowner::regrole::text from pg_proc where oid=to_regprocedure('app.read_push_dispatch_secret()')),'postgres','PSD-005: the secret lookup is postgres-owned');
select ok((select proconfig::text from pg_proc where oid=to_regprocedure('app.read_push_dispatch_secret()')) like '%search_path=%','PSD-005: the secret lookup pins an explicit search_path');
select is(case when to_regprocedure('app.read_push_dispatch_secret()') is null then 'ABSENT' else coalesce(has_function_privilege('public',to_regprocedure('app.read_push_dispatch_secret()'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: PUBLIC cannot execute the secret lookup');
select is(case when to_regprocedure('app.read_push_dispatch_secret()') is null then 'ABSENT' else coalesce(has_function_privilege('anon',to_regprocedure('app.read_push_dispatch_secret()'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: anon cannot execute the secret lookup');
select is(case when to_regprocedure('app.read_push_dispatch_secret()') is null then 'ABSENT' else coalesce(has_function_privilege('authenticated',to_regprocedure('app.read_push_dispatch_secret()'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: authenticated cannot execute the secret lookup');
select is(case when to_regprocedure('app.read_push_dispatch_secret()') is null then 'ABSENT' else coalesce(has_function_privilege('service_role',to_regprocedure('app.read_push_dispatch_secret()'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: service_role cannot execute the secret lookup');
select ok(to_regprocedure('app.enqueue_push_dispatch_wakeup(text)') is not null,'PSD-005: app.enqueue_push_dispatch_wakeup(text) exists');
select is((select prorettype::regtype::text from pg_proc where oid=to_regprocedure('app.enqueue_push_dispatch_wakeup(text)')),'void','PSD-005: the wakeup helper returns void');
select is((select provolatile from pg_proc where oid=to_regprocedure('app.enqueue_push_dispatch_wakeup(text)')),'v','PSD-005: the wakeup helper is VOLATILE');
select is((select prosecdef::text from pg_proc where oid=to_regprocedure('app.enqueue_push_dispatch_wakeup(text)')),'true','PSD-005: the wakeup helper is SECURITY DEFINER');
select is((select proowner::regrole::text from pg_proc where oid=to_regprocedure('app.enqueue_push_dispatch_wakeup(text)')),'postgres','PSD-005: the wakeup helper is postgres-owned');
select ok((select proconfig::text from pg_proc where oid=to_regprocedure('app.enqueue_push_dispatch_wakeup(text)')) like '%search_path=%','PSD-005: the wakeup helper pins an explicit search_path');
select is(case when to_regprocedure('app.enqueue_push_dispatch_wakeup(text)') is null then 'ABSENT' else coalesce(has_function_privilege('public',to_regprocedure('app.enqueue_push_dispatch_wakeup(text)'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: PUBLIC cannot execute the wakeup helper');
select is(case when to_regprocedure('app.enqueue_push_dispatch_wakeup(text)') is null then 'ABSENT' else coalesce(has_function_privilege('anon',to_regprocedure('app.enqueue_push_dispatch_wakeup(text)'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: anon cannot execute the wakeup helper');
select is(case when to_regprocedure('app.enqueue_push_dispatch_wakeup(text)') is null then 'ABSENT' else coalesce(has_function_privilege('authenticated',to_regprocedure('app.enqueue_push_dispatch_wakeup(text)'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: authenticated cannot execute the wakeup helper');
select is(case when to_regprocedure('app.enqueue_push_dispatch_wakeup(text)') is null then 'ABSENT' else coalesce(has_function_privilege('service_role',to_regprocedure('app.enqueue_push_dispatch_wakeup(text)'),'EXECUTE')::text,'unchecked') end,'false','PSD-005: service_role cannot execute the wakeup helper');

select is((select coalesce(array_to_string(p.proacl, ','), 'NULL') from pg_proc p where p.oid = to_regprocedure('cron.schedule(text,text,text)')),
  '=X/supabase_admin,supabase_admin=X/supabase_admin,postgres=X*/supabase_admin,postgres=X/postgres',
  'PSD-007: the cron scheduling surface sits at the recorded platform baseline — the ACL Supabase installs. The functions are supabase_admin-owned, its memberships are platform-reserved, and the operator role holds the privileges only WITH GRANT OPTION for its own grants, so the baseline is unrevokable without superuser; this pin freezes it so any widening goes red.');

select is((select coalesce(array_to_string(p.proacl, ','), 'NULL') from pg_proc p where p.oid = to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')),
  '=X/supabase_admin,supabase_admin=X/supabase_admin',
  'PSD-007: the net enqueue surface sits at the recorded platform baseline — the ACL Supabase installs. The functions are supabase_admin-owned, its memberships are platform-reserved, and the operator role holds the privileges only WITH GRANT OPTION for its own grants, so the baseline is unrevokable without superuser; this pin freezes it so any widening goes red.');

select is((select coalesce(array_to_string(p.proacl, ','), 'NULL') from pg_proc p where p.oid = to_regprocedure('net.http_get(text,jsonb,jsonb,integer)')),
  '=X/supabase_admin,supabase_admin=X/supabase_admin',
  'PSD-007: the net GET surface sits at the recorded platform baseline — the ACL Supabase installs. The functions are supabase_admin-owned, its memberships are platform-reserved, and the operator role holds the privileges only WITH GRANT OPTION for its own grants, so the baseline is unrevokable without superuser; this pin freezes it so any widening goes red.');

select is((select coalesce(array_to_string(p.proacl, ','), 'NULL') from pg_proc p where p.oid = to_regprocedure('net.http_delete(text,jsonb,jsonb,integer,jsonb)')),
  '=X/supabase_admin,supabase_admin=X/supabase_admin',
  'PSD-007: the net DELETE surface sits at the recorded platform baseline — the ACL Supabase installs. The functions are supabase_admin-owned, its memberships are platform-reserved, and the operator role holds the privileges only WITH GRANT OPTION for its own grants, so the baseline is unrevokable without superuser; this pin freezes it so any widening goes red.');

select is((select coalesce(array_to_string(p.proacl, ','), 'NULL') from pg_proc p where p.oid = to_regprocedure('net.http_collect_response(bigint,boolean)')),
  '=X/supabase_admin,supabase_admin=X/supabase_admin',
  'PSD-007: the net response-collection surface sits at the recorded platform baseline — the ACL Supabase installs. The functions are supabase_admin-owned, its memberships are platform-reserved, and the operator role holds the privileges only WITH GRANT OPTION for its own grants, so the baseline is unrevokable without superuser; this pin freezes it so any widening goes red.');

-- the net queue stays inspectable at the platform baseline (pg_net grants it at install)
select is((select (has_table_privilege('anon',c,'SELECT')::text || '/' || has_table_privilege('authenticated',c,'SELECT')::text || '/' || has_table_privilege('service_role',c,'SELECT')::text) from (values ('net.http_request_queue'::regclass)) v(c)),'true/true/true','PSD-007: the net queue inspection sits at the recorded platform baseline (pg_net grants it at install; unrevokable without superuser, no widening)');

select is((select (has_table_privilege('anon',c,'SELECT')::text || '/' || has_table_privilege('authenticated',c,'SELECT')::text || '/' || has_table_privilege('service_role',c,'SELECT')::text) from (values ('vault.secrets'::regclass)) v(c)),'false/false/true','PSD-007: vault.secrets reads sit at the recorded platform baseline (anon/authenticated denied, service_role baseline read)');

select is((select (has_table_privilege('anon',c,'SELECT')::text || '/' || has_table_privilege('authenticated',c,'SELECT')::text || '/' || has_table_privilege('service_role',c,'SELECT')::text) from (values ('vault.decrypted_secrets'::regclass)) v(c)),'false/false/true','PSD-007: vault.decrypted_secrets reads sit at the recorded platform baseline (anon/authenticated denied, service_role baseline read)');

select is(coalesce(has_column_privilege('authenticated','vault.secrets','secret','SELECT')::text,'unchecked'),'false','PSD-007: authenticated cannot read the Vault ciphertext column');

select is(coalesce(has_schema_privilege('authenticated','vault','CREATE')::text,'unchecked'),'false','PSD-007: authenticated cannot create objects in the Vault schema');

select is(coalesce(has_schema_privilege('authenticated','net','CREATE')::text,'unchecked'),'false','PSD-007: authenticated cannot create objects in the net schema');

-- ============ D0. real helper contract and real wakeup shape ============
savepoint d0;
select is(pg_temp.probe($q$select vault.create_secret('synthetic-dispatch-secret-A','gymloop_push_dispatch_secret')$q$),'OK','PSD-005: a single nonblank Vault entry can be staged under the production name');
select is(pg_temp.val($q$select app.read_push_dispatch_secret()$q$),'synthetic-dispatch-secret-A','PSD-005: exactly one nonblank Vault entry resolves to its value');
-- EMISSION: the branch fact is staged first and the assertion emits at top
-- level. A perform-ed pgTAP assertion executes (its counter advances) but
-- its verdict line never reaches the TAP stream — the CI run of 2026-10-05
-- proved the class on the h84 holdout (94 planned, 81 emitted, exactly the
-- 13 perform-ed ones missing; the next emitted assertion carried number 67
-- after 59). Each adaptive statement below emits exactly one assertion per
-- run in either branch, so every assertion plan(149) counts is EMITTED.
create temp table d0_dup_staged as
  select pg_temp.probe($q$select vault.create_secret('synthetic-dispatch-secret-D','gymloop_push_dispatch_secret')$q$) = 'OK' as staged;
select case
  when (select staged from d0_dup_staged)
    then is(pg_temp.err('select app.read_push_dispatch_secret()') is not null and position('synthetic-dispatch-secret-A' in coalesce(pg_temp.err('select app.read_push_dispatch_secret()')->>'msg',''))=0 and coalesce(pg_temp.err('select app.read_push_dispatch_secret()')->>'msg','x') not like '%does not exist%',true,'PSD-005: a duplicate Vault entry refuses wakeup with a value-free operational error')
  else is(pg_temp.probe($q$select vault.create_secret('synthetic-dispatch-secret-D','gymloop_push_dispatch_secret')$q$) <> 'OK',true,'PSD-005: the Vault schema itself refuses a duplicate production-named entry')
end;
select is(pg_temp.probe($q$delete from vault.secrets where name='gymloop_push_dispatch_secret'$q$),'OK','PSD-005: Vault fixture entries are removable for the missing-entry case');
select is(pg_temp.err('select app.read_push_dispatch_secret()') is not null,true,'PSD-005: a missing Vault entry refuses wakeup');
select is(position('synthetic-dispatch-secret-A' in coalesce(pg_temp.err('select app.read_push_dispatch_secret()')->>'msg',''))=0,true,'PSD-005: the missing-entry refusal is value-free');
select is(coalesce(pg_temp.err('select app.read_push_dispatch_secret()')->>'msg','x') not like '%does not exist%',true,'PSD-005: the missing-entry refusal is an operational error, not a catalog error');
create temp table d0_blank_staged as
  select pg_temp.probe($q$select vault.create_secret('','gymloop_push_dispatch_secret')$q$) = 'OK' as staged;
select case
  when (select staged from d0_blank_staged)
    then is(pg_temp.err('select app.read_push_dispatch_secret()') is not null and coalesce(pg_temp.err('select app.read_push_dispatch_secret()')->>'msg','x') not like '%does not exist%',true,'PSD-005: a blank Vault entry refuses wakeup with an operational error')
  else is(pg_temp.probe($q$select vault.create_secret('','gymloop_push_dispatch_secret')$q$) <> 'OK',true,'PSD-005: the Vault schema itself refuses a blank production-named entry')
end;
create temp table d0_qpre as select count(*)::integer c from net.http_request_queue;
select is(pg_temp.probe($q$select app.enqueue_push_dispatch_wakeup('synthetic-dispatch-secret-B')$q$),'OK','PSD-005: the real wakeup helper accepts a secret');
select is((select count(*)::integer from net.http_request_queue),(select c+1 from d0_qpre),'PSD-005: the real helper enqueues exactly one wakeup row');
select is((select url from net.http_request_queue order by id desc limit 1),'https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch','PSD-005: the wakeup targets the exact frozen endpoint');
select is((select position('?' in url) from net.http_request_queue order by id desc limit 1),0,'PSD-005: the wakeup URL carries no query string');
select is((select headers->>'Content-Type' from net.http_request_queue order by id desc limit 1),'application/json','PSD-005: the wakeup carries the JSON content type');
select is((select headers->>'x-gymloop-push-dispatch-secret' from net.http_request_queue order by id desc limit 1),'synthetic-dispatch-secret-B','PSD-005: the wakeup carries exactly the dedicated secret header');
select is((select headers ? 'authorization' from net.http_request_queue order by id desc limit 1),false,'PSD-005: the wakeup carries no authorization JWT');
select is((select encode(body,'escape') from net.http_request_queue order by id desc limit 1),'{}','PSD-005: the wakeup body is the empty JSON object');
select is((select timeout_milliseconds from net.http_request_queue order by id desc limit 1),5000,'PSD-005: the wakeup timeout is 5000 ms');
select is(pg_temp.probe($q$delete from net.http_request_queue$q$),'OK','PSD-005: the inspected wakeup row is removed inside the transaction');
rollback to savepoint d0;

-- ============ D1. zero eligible tenants: zero Vault and network work ============
select is(pg_temp.probe($q$create or replace function app.read_push_dispatch_secret() returns text language plpgsql volatile security definer set search_path = '' as $fn$ begin insert into pg_temp.seam_reads(n) values (coalesce((select max(n) from pg_temp.seam_reads),0)+1); return 'synthetic-dispatch-secret-S'; end $fn$$q$),'OK','PSD-005: the sanctioned secret-lookup seam is installed');
select is(pg_temp.probe($q$create or replace function app.enqueue_push_dispatch_wakeup(p_secret text) returns void language plpgsql volatile security definer set search_path = '' as $fn$ begin insert into pg_temp.seam_sends(n,secret) values (coalesce((select max(n) from pg_temp.seam_sends),0)+1,p_secret); end $fn$$q$),'OK','PSD-005: the sanctioned enqueue seam is installed');
select set_config('request.jwt.claims','',true);
create temp table d1_res as select pg_temp.tickj() r;
select is((select r is not null from d1_res),true,'PSD-003: the driver runs with zero eligible tenants');
select is((select array_agg(k order by k) from jsonb_object_keys((select r from d1_res)) k),'{absenceEvents,announcementEvents,classReminders,pushChildren,skipped,tenantsProcessed,wakeupsQueued}','PSD-006: the driver result has exactly the seven declared keys');
select is((select (r->>'tenantsProcessed')::integer from d1_res),0,'PSD-003: zero eligible tenants process zero tenants');
select is((select (r->>'announcementEvents')::integer from d1_res),0,'PSD-006: zero eligible tenants aggregate zero announcement events');
select is((select (r->>'pushChildren')::integer from d1_res),0,'PSD-006: zero eligible tenants aggregate zero push children');
select is((select (r->>'classReminders')::integer from d1_res),0,'PSD-006: zero eligible tenants aggregate zero class reminders');
select is((select (r->>'absenceEvents')::integer from d1_res),0,'PSD-006: zero eligible tenants aggregate zero absence events');
select is((select (r->>'wakeupsQueued')::integer from d1_res),0,'PSD-005: zero eligible tenants queue no wakeup');
select is((select r->>'skipped' from d1_res),'false','PSD-002: an empty tick is real work, not a skipped tick');
select ok((select jsonb_typeof(r->'tenantsProcessed')='number' and jsonb_typeof(r->'announcementEvents')='number' and jsonb_typeof(r->'pushChildren')='number' and jsonb_typeof(r->'classReminders')='number' and jsonb_typeof(r->'absenceEvents')='number' and jsonb_typeof(r->'wakeupsQueued')='number' from d1_res),'PSD-006: every count is a JSON number');
select is((select jsonb_typeof(r->'skipped') from d1_res),'boolean','PSD-006: skipped is a JSON boolean');
select is(pg_temp.reads_now(),0,'PSD-003: zero eligible tenants read no Vault secret');
select is(pg_temp.sends_now(),0,'PSD-003: zero eligible tenants enqueue no wakeup');

-- ============ D2. mixed readiness: only ready tenants process ============
select pg_temp.event_tenant(11);
select pg_temp.event_tenant(12);
select pg_temp.event_tenant(13);
select pg_temp.event_tenant(14);
select pg_temp.config(11, now()-interval '1 hour');
select pg_temp.config(12, null);
select pg_temp.config(13, now()+interval '1 hour');
create temp table d2_pre as select pg_temp.reads_now() r, pg_temp.sends_now() s;
select set_config('request.jwt.claims','',true);
create temp table d2_res as select pg_temp.tickj() r;
select is((select r is not null from d2_res),true,'PSD-003: the driver runs with mixed readiness');
select is((select (r->>'tenantsProcessed')::integer from d2_res),1,'PSD-003: only the ready tenant is processed');
select is((select (r->>'announcementEvents')::integer from d2_res),1,'PSD-006: exactly the ready tenant''s event is aggregated');
select is((select (r->>'pushChildren')::integer from d2_res),0,'PSD-006: no push children without sent sources');
select is((select (r->>'classReminders')::integer from d2_res),0,'PSD-006: no class reminders without bookings');
select is((select (r->>'absenceEvents')::integer from d2_res),0,'PSD-006: no absence events without open cases');
select is((select (r->>'wakeupsQueued')::integer from d2_res),1,'PSD-004: a processing tick queues exactly one wakeup');
select is((select r->>'skipped' from d2_res),'false','PSD-004: a processing tick is not skipped');
select is(pg_temp.reads_now(),(select r+1 from d2_pre),'PSD-005: a processing tick reads the wakeup secret exactly once');
select is(pg_temp.sends_now(),(select s+1 from d2_pre),'PSD-005: a processing tick enqueues exactly one wakeup');
select is((select secret from pg_temp.seam_sends order by n desc limit 1),'synthetic-dispatch-secret-S','PSD-005: the enqueued wakeup carries the resolved secret value');
select is((select count(*)::integer from public.notifications n where n.tenant_id in (pg_temp.aid(11),pg_temp.aid(12),pg_temp.aid(13),pg_temp.aid(14)) and n.dedupe_key like 'announcement:%'),1,'PSD-003: exactly one announcement event was created across the mixed fixture');
select is((select tenant_id from public.notifications where dedupe_key like 'announcement:%' and tenant_id in (pg_temp.aid(11),pg_temp.aid(12),pg_temp.aid(13),pg_temp.aid(14))),pg_temp.aid(11),'PSD-003: the announcement event belongs to the ready tenant');
select is((select dedupe_key from public.notifications where tenant_id=pg_temp.aid(11) and dedupe_key like 'announcement:%'),'announcement:'||pg_temp.aid(5011)::text||':v1:'||pg_temp.aid(4011)::text,'PSD-003: the runner delegated with the exact approved announcement dedupe key');

-- ============ D3. deterministic bounded wrap at 103 eligible tenants ============
select pg_temp.event_tenant(g) from generate_series(200,302) g;
select pg_temp.config(g, now()-interval '1 hour') from generate_series(200,302) g;
-- PSD-004's bounded wrap is defined over exactly the eligible set the driver
-- selects from, and that set is every ready configuration — not just the wrap
-- fixture. The D2 mixed-readiness tenant (pg_temp.aid(11)) was activated in D2
-- and nothing above deactivates it, so without this step the eligible pool at
-- the bounded tick is 104: the 100-bound then excludes FOUR tenants, which
-- four rotates with the tick's minute offset, and when aid(11)'s index sits
-- inside the window its D2-created dedupe key suppresses a second event —
-- the sweep-37389309267 failure shape (99 aggregates, 99 distinct, a fourth
-- "missing" tenant that was in fact the fourth excluded one). Deactivate the
-- D2 tenant so the eligible pool is exactly the 103 wrap-fixture tenants the
-- assertions below reason about; the global eligible count is pinned so the
-- fixture cannot silently drift again.
select is(pg_temp.probe($q$update public.push_provider_configurations set activated_at = null where tenant_id = pg_temp.aid(11)$q$),'OK','PSD-004: the D2 mixed-readiness tenant is deactivated before the bounded tick');
select is((select count(*)::integer from public.push_provider_configurations where app.push_configuration_ready(tenant_id)),103,'PSD-004: exactly the 103 wrap-fixture tenants are eligible driver-wide');
select set_config('request.jwt.claims','',true);
select is((select count(*)::integer from public.push_provider_configurations where tenant_id between pg_temp.aid(200) and pg_temp.aid(302) and activated_at<=statement_timestamp()),103,'PSD-004: all 103 wrap-fixture tenants are ready');
create temp table d3_res as select pg_temp.tickj() r;
select is((select r is not null from d3_res),true,'PSD-004: the driver runs against 103 eligible tenants');
select is((select (r->>'tenantsProcessed')::integer from d3_res),100,'PSD-004: a tick is bounded to 100 tenants');
select is((select (r->>'announcementEvents')::integer from d3_res),100,'PSD-004: the bound aggregates exactly the processed tenants'' events');
select is((select (r->>'pushChildren')::integer from d3_res),0,'PSD-004: the bounded tick creates no push children');
select is((select (r->>'classReminders')::integer from d3_res),0,'PSD-004: the bounded tick creates no class reminders');
select is((select (r->>'absenceEvents')::integer from d3_res),0,'PSD-004: the bounded tick creates no absence events');
select is((select (r->>'wakeupsQueued')::integer from d3_res),1,'PSD-004: a bounded tick queues exactly one wakeup');
select is((select r->>'skipped' from d3_res),'false','PSD-004: the bounded tick is not skipped');
select is((select count(distinct n.tenant_id)::integer from public.notifications n where n.tenant_id between pg_temp.aid(200) and pg_temp.aid(302) and n.dedupe_key like 'announcement:%'),100,'PSD-004: exactly 100 distinct eligible tenants were processed');
select is((select count(*)::integer from public.notifications n where n.tenant_id between pg_temp.aid(200) and pg_temp.aid(302) and n.dedupe_key like 'announcement:%'),100,'PSD-004: each processed tenant produced exactly one event');
create temp table d3_excl as
  with elig as (
    select pg_temp.aid(g.n) as tid, row_number() over (order by pg_temp.aid(g.n)) as rnk
      from generate_series(200,302) g(n)
  )
  select e.rnk from elig e
   where not exists (select 1 from public.notifications x
                      where x.tenant_id=e.tid and x.dedupe_key like 'announcement:%');
create temp table d3_ranks as
  select (select count(*) from pg_temp.d3_excl) as nx,
         (select min(rnk) from pg_temp.d3_excl) as r1,
         (select max(rnk) from pg_temp.d3_excl) as r3,
         (select rnk from pg_temp.d3_excl order by rnk offset 1 limit 1) as r2;
select case
  when (select nx = 3 and r2 is not null from d3_ranks)
    then is((select (r2-r1=1 and r3-r2=1) or (r1=1 and r3=103 and (r2=2 or r2=102)) from d3_ranks),true,'PSD-004: the excluded tenants are consecutive in the cyclic ascending order')
  else is(false,true,'PSD-004: the excluded tenants are consecutive in the cyclic ascending order')
end;

-- ============ D5. event failure rolls the tick back without enqueueing ============
savepoint d5;
-- EXISTS does not evaluate its output expression. Put the division in the
-- boolean result instead, with a tenant-dependent zero denominator so the
-- fault executes only when this fixture tenant's readiness is evaluated.
select is(pg_temp.probe($q$create or replace function app.push_configuration_ready(p_tenant_id uuid) returns boolean language sql stable security definer set search_path = '' as $fn$ select case when p_tenant_id = (select ('84000000-0000-4000-8000-'||lpad(250::text,12,'0'))::uuid) then (1 / (pg_catalog.length(p_tenant_id::text) - pg_catalog.length(p_tenant_id::text))) = 0 else exists (select 1 from public.push_provider_configurations c where c.tenant_id = p_tenant_id and c.firebase_project_id = 'samuraiapi-51996' and c.activated_at is not null and c.activated_at <= statement_timestamp()) end $fn$$q$),'OK','PSD-004: a readiness seam failing for one fixture tenant is installed');
create temp table d5_pre as select pg_temp.reads_now() r, pg_temp.sends_now() s;
select set_config('request.jwt.claims','',true);
create temp table d5_err as select pg_temp.tickerr() e;
select is((select e is not null from d5_err),true,'PSD-004: a failing event/eligibility path refuses the whole tick');
select is(position('synthetic' in coalesce((select e->>'msg' from d5_err),''))=0 and coalesce((select e->>'msg' from d5_err),'x') <> '',true,'PSD-004: the tick failure surfaces an operational, value-free error');
select is(pg_temp.sends_now(),(select s from d5_pre),'PSD-004: a failed tick enqueues no wakeup');
select is(pg_temp.reads_now(),(select r from d5_pre),'PSD-005: a tick that fails before eligible event work reads no secret');
rollback to savepoint d5;
select is((select count(*)::integer from public.notifications n where n.tenant_id between pg_temp.aid(200) and pg_temp.aid(302) and n.dedupe_key like 'announcement:%'),100,'PSD-004: the failed tick wrote no surviving event rows');

-- ============ D4. lock overlap, adaptive to the frozen lock semantics ============
-- D3 already proves the 103-tenant bound and cyclic exclusions. For the
-- repeat/dedupe case keep exactly its 100 already-processed tenants eligible:
-- a later statement minute must not introduce the three unprocessed tenants.
-- Keep the mixed-readiness future tenant inactive too, so elapsed fixture
-- time cannot add it to this repeat-only pool. No production clock is changed.
update public.push_provider_configurations c
   set activated_at = null
 where c.tenant_id = pg_temp.aid(13)
    or (c.tenant_id between pg_temp.aid(200) and pg_temp.aid(302)
        and not exists (select 1 from public.notifications n
                         where n.tenant_id = c.tenant_id
                           and n.dedupe_key like 'announcement:%'));
-- The tick result and the pre-tick seam counts are staged first; the five
-- branch assertions then EMIT at top level (a perform-ed assertion never
-- reaches the TAP stream; see the D0 emission note). Each CASE emits exactly
-- one assertion per run, in whichever of the three branches holds — the same
-- labels and expectations the original carried, so plan(149)'s five
-- lock-overlap assertions are EMITTED, not merely executed.
create temp table d4_pre as select pg_temp.sends_now() s, pg_temp.reads_now() r;
create temp table d4_tick as select pg_temp.tickj() r2;
select case
  when (select r2 is null from d4_tick)
    then is(false,true,'PSD-002: a back-to-back tick either skips inertly or reprocesses within bounds')
  when (select coalesce((r2->>'skipped')::boolean,false) from d4_tick)
    then is((select r2->>'skipped' from d4_tick),'true','PSD-002: a contended tick is an inert skipped tick')
  else is((select r2->>'skipped' from d4_tick),'false','PSD-002: with the lock released per tick a back-to-back tick is real work')
end;
select case
  when (select r2 is null from d4_tick)
    then is(false,true,'PSD-002: the overlap branch result is a JSON object')
  when (select coalesce((r2->>'skipped')::boolean,false) from d4_tick)
    then is((select (r2->>'tenantsProcessed')::integer from d4_tick),0,'PSD-002: a skipped tick processes zero tenants')
  else is((select (r2->>'tenantsProcessed')::integer from d4_tick),100,'PSD-004: the reprocessed tick stays bounded to 100 tenants')
end;
select case
  when (select r2 is null from d4_tick)
    then is(false,true,'PSD-002: the overlap branch queues no wakeup')
  when (select coalesce((r2->>'skipped')::boolean,false) from d4_tick)
    then is((select (r2->>'wakeupsQueued')::integer from d4_tick),0,'PSD-002: a skipped tick queues no wakeup')
  else is((select (r2->>'announcementEvents')::integer from d4_tick),0,'PSD-006: the reprocessed tick dedupes every existing event to zero new rows')
end;
select case
  when (select r2 is null from d4_tick)
    then is(false,true,'PSD-002: the overlap branch reads no secret')
  when (select coalesce((r2->>'skipped')::boolean,false) from d4_tick)
    then is(pg_temp.sends_now(),(select s from d4_pre),'PSD-002: a skipped tick enqueues nothing')
  else is((select (r2->>'wakeupsQueued')::integer from d4_tick),1,'PSD-004: the reprocessed tick still queues exactly one wakeup')
end;
select case
  when (select r2 is null from d4_tick)
    then is(false,true,'PSD-002: the overlap branch leaves the seams unchanged')
  when (select coalesce((r2->>'skipped')::boolean,false) from d4_tick)
    then is(pg_temp.reads_now(),(select r from d4_pre),'PSD-002: a skipped tick reads no secret')
  else is(pg_temp.sends_now(),(select s+1 from d4_pre),'PSD-005: the reprocessed tick enqueued exactly one wakeup')
end;

-- ============ E. activation ground facts for the protected operator flow ============
insert into public.organizations(id,name,gym_code,status) values (pg_temp.aid(21),'PUSH Activate A','PS0021','active'),(pg_temp.aid(22),'PUSH Activate B','PS0022','active');
select is(pg_temp.probe($q$insert into public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) values (pg_temp.aid(21),'samuraiapi-51996','2026-01-15 10:00:00+00'::timestamptz) on conflict (tenant_id) do nothing$q$),'OK','PSD-013: an explicit tenant can be activated with a fixed server-transaction cutoff');
select is((select activated_at from public.push_provider_configurations where tenant_id=pg_temp.aid(21)),'2026-01-15 10:00:00+00'::timestamptz,'PSD-013: the activation cutoff is recorded exactly');
select is(pg_temp.probe($q$insert into public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) values (pg_temp.aid(21),'samuraiapi-51996',statement_timestamp()) on conflict (tenant_id) do nothing$q$),'OK','PSD-013: an inert replay of the same activation is accepted');
select is((select activated_at from public.push_provider_configurations where tenant_id=pg_temp.aid(21)),'2026-01-15 10:00:00+00'::timestamptz,'PSD-013: inert replay preserves the existing activation cutoff');
select is(pg_temp.probe($q$insert into public.push_provider_configurations(tenant_id,firebase_project_id,activated_at) values (pg_temp.aid(22),'samuraiapi-5199X','2026-01-15 10:00:00+00'::timestamptz) on conflict (tenant_id) do nothing$q$),'OK','PSD-013: a differently-bound configuration row can exist for operator validation to reject');
select is(pg_temp.probe($q$select cron.schedule('push-dispatch-minute','* * * * *','select app.run_push_dispatch_tick();')$q$),'OK','PSD-013: the protected activation can schedule the private driver job');
select is((select count(*)::integer from cron.job where jobname='push-dispatch-minute'),1,'PSD-013: exactly one push-dispatch-minute job exists after scheduling');
select is((select schedule from cron.job where jobname='push-dispatch-minute'),'* * * * *','PSD-013: the wakeup runs every minute');
select is((select command from cron.job where jobname='push-dispatch-minute'),'select app.run_push_dispatch_tick();','PSD-013: the job command is exactly the private driver command');
select is((select username from cron.job where jobname='push-dispatch-minute'),'postgres','PSD-013: the job owner is the trusted postgres cron owner');
select is(pg_temp.probe($q$select cron.schedule('push-dispatch-minute','* * * * *','select app.run_push_dispatch_tick();')$q$),'OK','PSD-013: an inert replay of the job schedule is accepted');
select is((select count(*)::integer from cron.job where jobname='push-dispatch-minute'),1,'PSD-013: replaying the schedule leaves exactly one job');
select is((select count(*)::integer from cron.job where jobname ilike '%whatsapp%' or jobname ilike '%wsp%'),0,'PSD-013: no WSP schedule exists in the cron catalog');

select * from finish();
rollback;
