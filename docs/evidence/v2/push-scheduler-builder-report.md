# Push scheduler migration builder report (2026-10-04)

Builder: separate source builder, blind to `supabase/tests/` and
`supabase/tests-holdout/`. Authority:
`openspec/changes/push-notifications/deployment-scheduler-declaration.md`
(frozen) + `proposal.md` + existing `20261004090000_push_delivery.sql`
vocabulary only.

## Scope built — `supabase/migrations/20261005130000_push_scheduler.sql`

1. **Inert forward migration (PSD-001).** Declares `pg_net` (schema `net`)
   and `supabase_vault` (schema `vault`) with `create extension if not exists`
   (no-ops where the platform pre-installed them). Creates no cron job, no
   configuration row, no Vault secret; reads no decrypted secret; performs no
   network/provider operation. Does not touch `20261004090000_push_delivery.sql`.
2. **Extension custody (PSD-007/008).** For `vault`, `net` and `cron` schemas:
   `revoke usage`/`revoke all on all tables`/`revoke execute on all functions`
   from `public, anon, authenticated, service_role` (explicit per-role revokes
   after the PUBLIC revoke because the platform pre-grants extension schemas to
   anon/authenticated/service_role). Only the trusted postgres operator/worker
   path retains access via explicit `grant usage/select/execute ... to postgres`.
   No extension function is altered; only ACL statements touch extension
   objects; extension-internal owner privileges are untouched. Existing cron
   schedules remain operational (their worker path does not depend on caller
   EXECUTE of cron scheduling functions).
3. **`app.read_push_dispatch_secret()` (PSD-005).** VOLATILE SECURITY DEFINER,
   postgres-owned, `search_path=''`, EXECUTE revoked from the four roles.
   One statement reads the candidate secret and its filtered count from
   `vault.decrypted_secrets where name = 'gymloop_push_dispatch_secret'`
   (single snapshot for missing vs duplicate). Missing → `... unavailable`,
   duplicate → `... ambiguous`, null/blank → `... unusable`; three fixed
   value-free messages, no secret value or count in any error. Never
   substitutes a service key.
4. **`app.enqueue_push_dispatch_wakeup(text)` (PSD-005).** Same definer
   posture. Exactly one `net.http_post` to
   `https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch` with
   body `'{}'`, headers `Content-Type: application/json` +
   `x-gymloop-push-dispatch-secret: <p_secret>`, timeout 5000 ms. No
   authorization JWT, recipient, tenant selector, query string or redirecting
   endpoint. Returns void — the pg_net request id never escapes the seam.
5. **`app.run_push_dispatch_tick()` (PSD-002..006).** VOLATILE SECURITY
   DEFINER, postgres-owned, `search_path=''`, four-role EXECUTE revoke, no
   public facade. Transaction advisory try-lock
   `pg_try_advisory_xact_lock(hashtextextended('push-dispatch-minute', 0))`
   — consistent with the repo's existing `hashtextextended` lock idiom;
   contention returns the exact seven-key result with `skipped=true`, zero
   counts, no Vault/network work. Eligibility comes only from tenant-keyed
   `public.push_provider_configurations` through the existing
   `app.push_configuration_ready(uuid)`; ONE statement captures
   `array_agg(tenant_id order by tenant_id)` + count so count and selection
   share one statement-time snapshot; empty set returns zero counts without
   reading Vault (PSD-003). Cyclic selection per PSD-004: offset
   `(floor(epoch(v_tick)/60)*100) % eligible_count` with the tick instant
   captured once at function entry, `min(100, eligible_count)` distinct
   ascending tenants, natural one-wrap. Each selected tenant delegates to the
   existing `app.run_push_events(uuid)` exactly once — no duplicated
   predicates, no broad no-show scan, no attempt reservation, no FCM from
   SQL; the runner's four count keys are aggregated. Any runner error aborts
   the transaction (no exception handler) so the tick rolls back with nothing
   enqueued (PSD-004). Secret lookup and the single wakeup happen only after
   all selected runners succeed. Result is exactly
   `{tenantsProcessed, announcementEvents, pushChildren, classReminders,
   absenceEvents, wakeupsQueued, skipped}`; no request id, tenant/member id,
   token, header, credential, provider id or raw exception escapes
   (PSD-006). No transient HTTP contents are persisted anywhere.
6. **Activation shape.** Nothing scheduled here. The unique
   `push-dispatch-minute` job (`* * * * *`, command
   `select app.run_push_dispatch_tick();`) is created only by the protected
   `activate` operation (PSD-013); pause (PSD-014) unschedules only it. The
   migration's closing comment records this; no additional public SQL facade
   exists.

## Vault/ACL handling notes

- `vault.decrypted_secrets` select grant to postgres covers the view (GRANT
  ON ALL TABLES includes views). The helper decrypts only within the Vault
  definer context; plaintext never leaves the function.
- Blank check uses `btrim(v_secret) = ''` — whitespace-only entries refuse
  (recorded interpretation of "nonblank").
- Grant-back to postgres is intentionally broad per schema (`all functions`,
  `all tables`) instead of per-signature, avoiding pg_net overload-signature
  guessing while keeping grants limited to the trusted postgres role.

## Declaration deviations

None forced. Two recorded judgment calls, both within declaration language:
1. Lock key derivation uses `hashtextextended('push-dispatch-minute', 0)`
   (the declaration says "keyed by the fixed job name" without pinning the
   derivation; the repo's existing per-tenant lock uses the same idiom).
2. The cyclic offset uses the tick instant captured at function entry rather
   than a fresh `statement_timestamp()` per statement, so count/selection
   snapshot (one statement) and offset derive from one deterministic instant.
3. Fresh-critic P2 fix (apply-time schema assumption): a named
   `$extension_schema_guard$` block before the custody revokes verifies
   `to_regnamespace('net'/'vault'/'cron')` and that `pg_net`, `supabase_vault`
   and `pg_cron` are actually installed in those exact schemas, raising
   `push_scheduler: extension_schema_unexpected ...` with the actual schema
   name instead of a generic revoke failure on relocation. pg_cron is guarded
   with the same pattern (same failure class for its revoke block).

## Static checks

- `$fn$` count 6 (even), total dollar-quote tags 8 (adds the paired `$extension_schema_guard$`), paren balance 45/45.
- Zero `commit` statements; no explicit transaction control (migration runs
  under CI's transaction).
- Rollback-guard script reports "does not start with BEGIN / end with
  ROLLBACK" — the same result for every existing migration file (the guard
  is scoped to pgTAP test files); matches repo convention.
- `search_path=''` + fully qualified references on all three definer helpers.

## Caveats for verification rounds

- `net.http_post` is invoked with named arguments (`url`, `body`, `headers`,
  `timeout_milliseconds`) — the modern supported pg_net signature. Production
  transport correctness requires the separate fixed-request verification the
  declaration demands; a synthetic test seam does not prove it.
- Registry rows proposed for coordinator: `app.run_push_dispatch_tick()`,
  `app.read_push_dispatch_secret()`, `app.enqueue_push_dispatch_wakeup(text)`,
  the Vault name `gymloop_push_dispatch_secret`, the approved cron job name
  `push-dispatch-minute`, and the shared TS operational constants (tick/
  activation limit 100, interval 60 s, timeout 5000 ms, names) per the
  declaration's registration section.

## Provenance

- Migration sha256: `c38c30999e12d7ac9d91160d6f8fbaac96fe7cc45841f362bc4aed3a830decaa` (post critic-GO-WITH-FIXES edit)
- Report sha256: `efabdeaa19965e5392a53b4f6b8fb48835a83312d77d36d8f3975f76f0c5cbc2` (plus this provenance update)
- No Cloud SQL executed; no tests read; no commits made.
