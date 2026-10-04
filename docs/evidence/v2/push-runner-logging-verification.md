# Push runner logging verification — 2026-10-04

Research verifier report on real Supabase Cloud SQL statement-logging behavior,
to support freezing or correcting `deployment-runner-interface-declaration.md`
(the "PostgreSQL logging prerequisite" section) and PSD-017/PSD-018 in the
frozen scheduler declaration. Sources: Supabase docs (fetched 2026-10-04) and
the `supabase/postgres` platform configuration repository (develop branch).
No Cloud SQL was run; effective values on project `pecxrpskmfeuyzngvewq`
remain runtime-verified items.

## Q1. What is logged when SQL runs (SQL editor / CLI db query / cron)

Platform defaults from the managed-image config (`ansible/files/postgresql_config/postgresql.conf.j2`, supabase/postgres develop):

- `log_statement = 'ddl'` — actively set, NOT the commented default. **DDL
  statements (CREATE/ALTER/DROP, including CREATE TEMP TABLE and embedded
  function bodies) are logged with their full statement text, including any
  literal values, for ordinary connections.** A companion migration
  (`migrations/db/migrations/20250205060043_disable_log_statement_on_internal_roles.sql`)
  sets `log_statement = none` only for `supabase_admin`, `supabase_auth_admin`
  and `supabase_storage_admin` — the `postgres` role used by CLI db query
  keeps the DDL default.
- `log_min_error_statement = error` (core default, line commented) — **any
  statement that raises an ERROR is logged in full with literals.**
- `log_min_duration_statement = -1`, `log_min_duration_sample = -1`,
  `log_statement_sample_rate = 1.0`, `log_duration = off` (commented defaults,
  i.e. no duration logging by default).
- `log_parameter_max_length = -1`, `log_parameter_max_length_on_error = 0`
  (commented). These bind-parameter limits are irrelevant to `supabase db
  query --file`, which sends inline literals: **inline literals are part of
  statement text and are never redacted by these settings.**
- `shared_preload_libraries` includes `pgaudit`, `auto_explain`, `supabase_vault`, `pg_cron`, `pg_net`.
- `auto_explain.log_min_duration = 10s` is set (`conf.d/auto_explain.conf`) —
  any statement running ≥10 s logs its full **Query Text** (literals included)
  plus plan. `log_nested_statements` is not set.
- pgaudit is preloaded but `pgaudit.log` defaults to `none`; the dashboard
  guide (https://supabase.com/docs/guides/observability/configure-logging)
  documents enabling statement logging *via pgaudit* and warns that
  "recorded statements and messages can contain sensitive values".
- Postgres log events land in `postgres_logs` in the Logs Explorer; the field
  reference (https://supabase.com/docs/guides/observability/log-field-reference)
  warns that **statement text and error details may appear directly in
  `event_message`**, events are truncated at 100,000 characters, and a missing
  structured field does not mean the event has no detail.

Consequence: a secret interpolated into SQL text (PSD-017's provisioning
literal) is logged if the statement is DDL, errors, or runs ≥10 s, unless
session/transaction-local suppressions are active. The draft's suppressions
(`log_statement=none`, duration thresholds `-1`, rates 0, `log_duration=off`,
pgaudit off, auto_explain disabled) are necessary and, per the platform config
permissions (`supautils.privileged_role_allowed_configs` explicitly allows
`log_statement`, `log_min_error_statement`, `log_min_duration_statement`,
`log_duration`, `auto_explain.*`, `pgaudit.*` for the postgres role),
permitted — but the suppression list must also include
**`log_min_error_statement`** (the draft names the inspect list but its
suppression list does not spell it out) and it only protects statements
*after* the SET LOCAL in the same received message.

Function-argument secrets (e.g. `app.enqueue_push_dispatch_wakeup(p_secret
text)`) are **not part of statement text**; they leak only through pgaudit
function-class logging (off by default, and `pgaudit.log_parameter` cannot be
enabled on Supabase — the pgAudit guide says it is restricted precisely to
avoid logging secrets from Vault/pgsodium) or through a function that echoes
argument values in an error message (PSD-006 already requires value-free
errors).

## Q2. pg_cron output

- `cron.job_run_details` records run status (https://supabase.com/docs/guides/cron); Dashboard Cron UI and SQL both read it.
- pg_cron runs jobs as background workers of the Postgres process, so a job's
  raised ERROR surfaces in the Postgres log stream (`postgres_logs`) with the
  same statement/error-text rules as Q1 (log_min_error_statement applies to
  the cron-executed statement). Documented pages do not describe the routing
  explicitly; this is standard pg_cron/Postgres behavior and should be
  runtime-confirmed once (one deliberately failing cron tick, then inspect
  `postgres_logs`).
- The frozen PSD-013 cron command (`select app.run_push_dispatch_tick();`)
  contains no secret, so `cron.job` text storage is safe by construction;
  Vault decryption happens inside function code, never in SQL text.

## Q3. Retention and purge

- Retention "depends on your pricing plan" (https://supabase.com/docs/guides/platform/logs); the usage page
  (https://supabase.com/docs/guides/platform/manage-your-usage/logs) documents
  ingest/query billing and Log Drains but no per-source retention length and
  no deletion API.
- No documented purge/deletion mechanism for already-ingested `postgres_logs`
  was found. A leaked secret must therefore be treated as retained for the
  plan's whole retention window and rotated, not purged.

## Q4. GUC/set_config payloads

- No documentation states that `set_config` payloads or GUC values are
  themselves logged. `SET` is not in the `ddl` statement class; pgaudit's
  `misc` class (which can include SET) defaults to off. GUC values reach logs
  only through statement text of logged statements or auto_explain Query Text.

## Impact on the draft's secret-safe transport claim

1. The draft's implicit assumption that statement logging is off by default is
   wrong for DDL: platform default is `log_statement='ddl'` for the postgres
   role. The proveLogging preflight must verify effective (session/role/DB)
   values at runtime, as the draft already requires — this finding makes that
   clause load-bearing, not optional.
2. The suppression list must be extended with `log_min_error_statement`
   (e.g. `panic`) for the sensitive transaction, and the transaction must
   contain no DDL, no errors, and no ≥10 s statements. PSD-017's
   "zero or one existing named Vault entry" lock-read already avoids erroring;
   the single-statement design should also keep runtime under 10 s.
3. Secret-as-function-argument transport is safe against statement logging
   under the documented defaults (pgaudit off, parameters not loggable).
4. The draft's caveats (whole multi-statement simple-query message received
   before SET LOCAL; parser error before SET; privileged extension hooks) are
   consistent with the documented/observed mechanism and must stay.

## Recommendation

- Safe to freeze: the inspect-list of settings; the refuse-on-uninspectable
  rule (`logging_unproven`); per-session suppression approach with its stated
  caveats; role-level-only configuration posture; value-free error discipline.
- Must change before freeze: add `log_min_error_statement` (and explicitly
  `auto_explain.log_min_duration`/`log_nested_statements`) to the suppression
  list; state the platform DDL default (`log_statement='ddl'`) as the reason
  the preflight is mandatory; forbid DDL statements inside the sensitive
  transaction explicitly.
- Unverifiable from docs (runtime verification required): effective values on
  the live project; exact plan retention window for `postgres_logs`; absence
  of purge; pg_cron stderr routing into `postgres_logs`; whether the Supabase
  CLI sends `--file` as one simple-query message (protocol-level, affects the
  pre-SET caveat).

Sources: https://supabase.com/docs/guides/platform/logs ·
https://supabase.com/docs/guides/observability/configure-logging ·
https://supabase.com/docs/guides/observability/log-field-reference ·
https://supabase.com/docs/guides/database/extensions/pgaudit ·
https://supabase.com/docs/guides/cron ·
https://supabase.com/docs/guides/platform/manage-your-usage/logs ·
https://github.com/supabase/postgres (develop:
`ansible/files/postgresql_config/postgresql.conf.j2`, `conf.d/auto_explain.conf`,
`migrations/db/migrations/20250205060043_disable_log_statement_on_internal_roles.sql`,
`supautils.conf.j2`).
