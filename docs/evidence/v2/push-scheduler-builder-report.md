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
2a. **Custody enforcement with owner-role escalation.** All four custody DO
   blocks now apply ACL statements through a transaction-local
   `pg_temp.psd_acl(sql, owner_roles)` helper: try as the apply role; on
   insufficient privilege retry once per candidate owning role
   (`supabase_admin`, and `supabase_vault_admin` for vault) via
   `set local role`. The helper lives in pg_temp and dies with the migration
   transaction. Unachievable denials remain loud notices — never silent —
   and the `decrypted_secrets` refusal stays named. This addresses the held
   A-cluster custody labels (vault secret/decryption function EXECUTE,
   vault.secrets/decrypted_secrets SELECT, net enqueue/inspection, cron
   scheduling, cron.job reads) whenever the apply role holds membership of
   the owning roles; if the platform denies even that, the residual gap is
   operator-routable, not silently waived.
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
  pairs) plus the paired `$acl$` inside the setup block. Paren balance 71/71.
  Zero `commit` statements. Zero unqualified
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

- Migration sha256: `ca79d903905940fd1700746a0588cd837cdff14ca91f29f8524ebbad37446701` (post custody escalation)
- Report sha256: `efabdeaa19965e5392a53b4f6b8fb48835a83312d77d36d8f3975f76f0c5cbc2` (plus this provenance update)
- No Cloud SQL executed; no tests read; no commits made.

## Held-suite RED adjudication (26/94, labels only)

- **Source fixes applied:** A39, A43, A44 (and the same mechanism covers
  A40, A45, A46) — vault/net/cron denials can now escalate to the owning
  roles instead of being notice-skipped when the apply role lacks grant
  rights. Requires re-run against sha `ca79d903...46701`; if the previously
  applied Cloud iteration predated the latest sha, part of the A-cluster RED
  may reflect the stale applied bytes rather than the current source.
- **Holdout-overpin candidates for the orchestrator:** C2 — the advisory
  lock derivation is not pinned by the declaration; the driver uses
  `hashtextextended('push-dispatch-minute', 0)` (repo idiom). A blind
  contention probe cannot reproduce that key; the declaration must pin the
  derivation or the probe must observe the driver's actual lock key.
  J2/J3 — staging-health failures cascade: every F/G/H/I tick/queue label is
  statically satisfied by the current source (single statement-time
  snapshot, cyclic min(100,n) selection, one runner call per tenant, counts
  aggregated from the runner's four keys, enqueue only after all runners,
  exact seven-key result); if fewer than all 109 provider configurations
  staged, those labels cannot adjudicate the driver. A29 — if pinned via
  helper-source inspection, the body contains exactly `Content-Type` /
  `application/json`; a lowercase-only pin would overpin. D2/F5 — the blank
  refusal is the declared value-free ERROR (tick aborts, nothing enqueued)
  and the driver passes the read helper's return verbatim into the enqueue
  helper; if the holdout expects a non-error result shape or a different
  seam signature than `app.read_push_dispatch_secret() returns text` /
  `app.enqueue_push_dispatch_wakeup(p_secret text) returns void`, that is an
  overpin against the frozen seam contract.

## Custody follow-up (post-escalation re-run)

Re-run at the escalated bytes (`ca79d903...46701`, on-disk, not stale) still
shows the A-cluster plus F/G/H/I labels failing. Static analysis from the
migration alone: (i) the net and cron revokes have no exception path — they
either succeeded or would have aborted the apply, so persistent net/cron RED
labels (A40, A45, A46) cannot be explained by unapplied revokes; (ii) the
vault per-object block may still notice-skip if the apply role holds
membership of neither `supabase_admin` nor `supabase_vault_admin` — those
vault labels (A39, A43, A44) would then be genuinely unreachable from any
migration running as postgres and are operator-routable; (iii) my migration
touches no object in the `public` schema and grants nothing to ordinary
roles, so if the A-cluster actually probes provider-configuration
member-readability, that behavior is owned by `20261004090000_push_delivery.sql`
(RLS enabled, all four roles revoked there) plus whatever the holdout stages
itself — fixture-adjacent, not this migration. Requested: the exact got/wanted
per A-label (public values) to split (a) owner-role reach from (b) probe
mechanics before any further byte change. Bytes unchanged pending that dump.

## Custody widening (residual-count response)

Got/wanted counts (3 vault-family / 5 net-family / 4 cron-family residual
EXECUTE for ordinary roles) addressed by three widening changes:

1. **pgsodium surface now gets full custody, not just trust grants.** Under
   PSD-007 the pgsodium crypto surface IS the Vault plaintext/decryption
   machinery; its member functions/relations are now revoked from
   public/anon/authenticated/service_role (escalated through owning roles)
   before the trusted-only postgres grants. If Supabase's default extension
   grants put pgsodium helpers inside the residual vault-family counts, this
   closes them; if the apply role cannot install these denials even under
   owner-role escalation, the per-object notices name them as the honest
   operator prerequisite.
2. **pg_net enumeration widened** beyond pg_depend membership: functions in
   the pg_net extension's own schema whose names match `^(http_|_http)` are
   now included, catching helper overloads the dependency records may not
   attribute (closes part of the net-family residual count without touching
   unrelated `extensions`-schema functions).
3. **pg_cron enumeration widened**: the pg_depend members are unioned with
   the cron scheduling surface names (`schedule`, `unschedule`,
   `schedule_in_database`, `alter_job`, `remove_job`) in the extension's
   actual schema.

If the next run still shows residuals, the counts are names-blind — request
the named-object dump from the holdout author for a precise per-label
verdict; any object the platform will not let the apply role (or its owner
roles) touch is recorded as the honest operator prerequisite per-label.
New sha256 `10cbb342...8ba9`.

## Named-object verdict (A-cluster close-out)

Live-catalog capture of the 8 residual executables:

- Cron family (granted to anon+authenticated+service_role):
  `cron.job_cache_invalidate()`, `cron.schedule(text, text)`,
  `cron.schedule(text, text, text)`, `cron.unschedule(text)`,
  `cron.unschedule(bigint)`.
- Vault family (granted to service_role only):
  `vault._crypto_aead_det_decrypt(bytea, bytea, bigint, bytea, bytea)`,
  `vault.create_secret(text, text, text, uuid)`,
  `vault.update_secret(uuid, text, text, text, uuid)`.

All 8 were ALREADY inside the migration's enumeration scope (the vault block
scans every function in schema `vault`; the cron union names schedule/
unschedule; `job_cache_invalidate` is a pg_cron pg_depend member) — the
widening changed nothing because these are not enumeration misses. They are
privilege-model misses: REVOKE requires being the object owner or holding
the privilege with grant option; these extension-managed objects are owned
by the platform's admin roles (extension scripts executed outside the apply
role), and the apply role holds membership of neither owning role — so both
the direct attempt and every owner-role escalation fail. A migration running
as postgres cannot revoke platform-granted privileges on objects it does not
own. **Honest per-label limit: operator prerequisite.** The protected
activation workflow (or a platform dashboard SQL editor session as
`supabase_admin`) must run, per object:

  revoke execute on function <object> from public, anon, authenticated, service_role;

for the five cron functions and the three vault functions above. Until that
runs, the A-cluster labels stay RED by design and no suite edit may paper
over them. Note: net-family residuals closed by the widening — net custody
is migration-complete.
