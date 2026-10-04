# Push scheduler migration builder report (2026-10-04)

Builder: separate source builder, blind to `supabase/tests/` and
`supabase/tests-holdout/`. Authority:
`openspec/changes/push-notifications/deployment-scheduler-declaration.md`
(frozen) + `proposal.md` + existing `20261004090000_push_delivery.sql`
vocabulary only.

## Scope built — `supabase/migrations/20261005130000_push_scheduler.sql`

1. **Inert forward migration (PSD-001, fact-corrected 2026-10-04).** Declares
   `pg_net` into the `extensions` schema (repo precedent: tenancy/catalogue
   migrations) and `supabase_vault` into `vault` with `create extension if not
   exists` (no-ops where the platform pre-installed them). Runtime evidence on
   the approved project: pg_cron is installed in `pg_catalog` (precedent
   20260909170000 declares it with no schema clause), supabase_vault in
   `vault`, pg_net was ABSENT — it is declared here. Creates no cron job, no
   configuration row, no Vault secret; reads no decrypted secret; performs no
   network/provider operation. Does not touch `20261004090000_push_delivery.sql`.
2. **Extension custody (PSD-007/008), scoped to real object homes and
   apply-clean.** `vault`: per-object ACL statements in a resilient DO block —
   Vault internals (including the pgsodium crypto helpers behind
   `decrypted_secrets`) are not all owned or grantable by the apply role, so a
   blanket `ALL FUNCTIONS/TABLES IN SCHEMA vault` grant/revoke aborted the
   first alone-run with `42501: permission denied for function
   _crypto_aead_det_encrypt`. Each vault object is attempted individually:
   revokes/grants that the apply role cannot perform are recorded with a
   notice (the independent ACL suites pin effective custody and will flag any
   real gap as RED), and failure to grant the one object the driver's Vault
   read path needs (`vault.decrypted_secrets`) is a NAMED refusal
   (`push_scheduler: custody_refused ...`). Ordinary-role denials are kept
   wherever the apply role can apply them. `pg_net`: its objects now live inside the SHARED `extensions` schema,
   so a blanket schema revoke would touch unrelated extensions — the DO blocks
   enumerate exactly the pg_net member functions and tables/views via
   `pg_depend` (deptype 'e') and revoke each from the four roles. `pg_cron`:
   objects live in `pg_catalog`, so a schema-scoped revoke is forbidden — the
   DO blocks enumerate exactly the pg_cron member functions (scheduling
   surface) and member tables via `pg_depend` and revoke each. Only the
   trusted postgres operator/worker path retains access via explicit grants to
   postgres. No extension function is altered; extension-internal owner
   privileges are untouched. Existing cron schedules remain operational.
2b. **Trusted-only pgsodium member grants.** Vault's decrypted view and
   pgsodium's apply-time DDL machinery call crypto internals
   (`_crypto_aead_det_encrypt` and siblings) that pgsodium keeps
   EXECUTE-denied from PUBLIC; the helper's definer chain runs as postgres, so
   a DO block enumerates the pgsodium member functions and relations via
   `pg_depend` and grants EXECUTE/SELECT on them to postgres only (resilient
   per-object; a notice records pgsodium absence). Nothing is granted to
   anon/authenticated/service_role/public — ordinary-role custody is
   unchanged; this closes the coordinator's hypothesis (a)/(c) class while
   making the migration apply cleanly.
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
- Named apply-time guards (fresh-critic P2 + runtime correction): a
  pre-declaration `$extension_schema_guard$` verifies pg_cron in `pg_catalog`,
  supabase_vault in `vault`, `extensions` schema present, and RECORDS pg_net
  pre-state via `raise notice` (absence allowed); a post-declaration
  `$extension_placement_guard$` refuses with
  `push_scheduler: extension_schema_unexpected ...` if pg_net did not land in
  `extensions`. Guards run BEFORE any revoke, so relocation/misplacement is
  refused by name, never by a generic revoke error.
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

## 42601 investigation (coordinator item d)

Statically no `syntax error at or near "from"` candidate exists in this
migration: every `FROM` occurrence was extracted and reviewed in context —
all are well-formed SELECT/JOIN/EXTRACT/REVOKE/GRANT grammar, and the
plpgsql SELECT-INTO statements (including the window-function form
`select s.decrypted_secret, count(*) over () into ...`) parse per PL/pgSQL
grammar. The reported 42601 appeared in the BATCHED run only and was masked
in the alone-run by the earlier 3F000 (schema `net` absent) abort — i.e. it
surfaced at a LATER statement. Since this migration's own statements check
out statically, the 42601 most plausibly belongs to a later statement in the
same compiled batch (another spliced file or a splice-concatenation
artifact). The next alone-run of this migration past the extension setup
will confirm or refute; nothing was found to fix in this file.

## Static checks

- `$fn$` count 6 (even); dollar-quote tags all paired: $fn$×2,
  $extension_schema_guard$×2, $extension_placement_guard$×2, $vault_custody$×2,
  $net_custody$×2, $cron_custody$×2, $pgsodium_trust_grants$×2 (14 tags, 7
  pairs). Paren balance 54/54. Zero `commit` statements. Zero unqualified
  `net.` references; the single pg_net call is `extensions.http_post`. No
  blanket `ALL TABLES/FUNCTIONS IN SCHEMA vault` statements remain (the
  apply-unsafe forms are gone).
- Zero `commit` statements; no explicit transaction control (migration runs
  under CI's transaction).
- Rollback-guard script reports "does not start with BEGIN / end with
  ROLLBACK" — the same result for every existing migration file (the guard
  is scoped to pgTAP test files); matches repo convention.
- `search_path=''` + fully qualified references on all three definer helpers.

## Caveats for verification rounds

- pg_net's enqueue is invoked as `extensions.http_post` with named arguments
  (`url`, `body`, `headers`, `timeout_milliseconds`) — the modern supported
  signature, extension-qualified per the runtime-established placement.
  Production transport correctness requires the separate fixed-request
  verification the declaration demands; a synthetic test seam does not prove
  it.
- Registry rows proposed for coordinator: `app.run_push_dispatch_tick()`,
  `app.read_push_dispatch_secret()`, `app.enqueue_push_dispatch_wakeup(text)`,
  the Vault name `gymloop_push_dispatch_secret`, the approved cron job name
  `push-dispatch-minute`, and the shared TS operational constants (tick/
  activation limit 100, interval 60 s, timeout 5000 ms, names) per the
  declaration's registration section.

## Provenance

- Migration sha256: `f47bb720f3f6a2cec2a07dbec25d5b8e747fe7ea312897b4c6b017b38a35f3cf` (post custody apply-clean correction)
- Report sha256: `efabdeaa19965e5392a53b4f6b8fb48835a83312d77d36d8f3975f76f0c5cbc2` (plus this provenance update)
- No Cloud SQL executed; no tests read; no commits made.
