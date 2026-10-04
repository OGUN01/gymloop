# Push scheduler migration — fresh blind source critic

2026-10-04. Reviewer: fresh-context source critic, implementation-blind to all
tests and holdouts; authority limited to the four named documents plus the
registry section. Files read: `deployment-scheduler-declaration.md`,
`push-notifications/proposal.md`,
`supabase/migrations/20261005130000_push_scheduler.sql` (in full),
`supabase/migrations/20261004090000_push_delivery.sql` (vocabulary),
`docs/registry.md` scheduler rows.

## Verdict: GO-WITH-FIXES

No P1 finding. One P2 (shared operational constants missing) and one P2-class
apply-time robustness note; the substance of PSD-001..008 is correctly
implemented.

## Per-dimension table

| Dimension | Verdict | Notes |
|---|---|---|
| Inertness (PSD-001) | PASS | Only `create extension if not exists` (no-op on Cloud), schema ACL statements, three functions. No cron job, no configuration/Vault row, no network call, no secret read at apply time. |
| Secret hygiene (PSD-005/008) | PASS | Exact single-name lookup; missing/duplicate/blank each raise fixed value-free messages (`secret configuration unavailable/ambiguous/unusable`); secret value never returned to any caller but the trusted tick; enqueue discards the pg_net request id; no Authorization header; no request id in the result. |
| ACL/custody (PSD-007) | PASS | Schema-level + per-function revokes for public/anon/authenticated/service_role on vault, net, cron; grants back to postgres only; no extension function altered; extension-internal owners retain their own EXECUTE. |
| Cyclic scheduling (PSD-004) | PASS | Single-statement snapshot of the eligible set; ascending `array_agg(order by tenant_id)`; offset `(floor(epoch(statement_timestamp())/60)*100) % eligible_count` computed from the entry-time `statement_timestamp()`; `min(100,n)` distinct tenants, wrap once via modulo indexing; `tenantsProcessed ≤ 100`, `wakeupsQueued = 1`, `skipped` boolean. |
| Activation path (PSD-013) | PASS | No job creation in the migration; the unique `push-dispatch-minute` job/command appears only in comments; pause/activate remain operator statements. |
| Money/tenancy (PSD-003/006) | PASS | No wallet/ledger writes; delegation to `app.run_push_events(uuid)` exactly once per selected tenant; result aggregates exactly the runner's four declared count keys (verified against the runner's return keys); zero-eligible returns zero counts before any Vault/network access. |
| Locking (PSD-002) | PASS | `pg_try_advisory_xact_lock(hashtextextended('push-dispatch-minute',0))`; contention returns skipped=true with zero counts and no secret/network work; single lock, no ordering hazard. |
| General correctness | PASS | `search_path=''` on all three helpers; owner postgres + four-role revokes on all three; fully qualified objects; `$fn$` balanced; no COMMIT; blank-secret re-validation in enqueue is defense in depth. |

## Findings

1. **P2 — Shared operational constants not yet registered** (proposal,
   "Registry/decision proposals": "Add shared named operational constants for
   tenant tick/activation input limit 100, tick interval 60 seconds, wakeup
   timeout 5000 ms and job/Vault names"). The migration hardcodes 100, 60 and
   5000 as SQL literals; `packages/shared/src/config/constants.ts` has no
   corresponding named constants, so the SQL/TS mirrored bounds have no
   consistency proof today. Fix: add the named constants (e.g.
   `PUSH_SCHEDULER_TENANT_LIMIT`, `PUSH_SCHEDULER_TICK_SECONDS`,
   `PUSH_SCHEDULER_WAKEUP_TIMEOUT_MS`, job/Vault name constants) and pin the
   equality in a test-side assertion per the established pattern. Registry
   rows for the SQL symbols already exist and match the migration.
2. **P2 — Apply-time schema assumption is unverified.** The revokes/grants
   target schemas `net`, `vault`, `cron` immediately after
   `create extension if not exists ... with schema net|vault`. On the platform
   standard this is a no-op + existing schemas, but if pg_net or supabase_vault
   were installed in a different schema (or absent while cron also absent),
   the very next schema-scoped revoke fails the migration apply loudly. The
   failure is loud, not silent, so this is not a correctness hole — but the
   declaration's "enumerate installed extension objects" spirit argues for a
   cheap guarded existence check (or an explicit to_regnamespace assertion)
   before the revoke block so a nonstandard Cloud state produces a named
   refusal instead of a raw 42P01.
3. **P3 — Runner exception vocabulary feeds cron job_run_details.** When a
   selected tenant's `app.run_push_events` raises, the transaction aborts
   (correct per PSD-004) and pg_cron records the error message in job run
   details. Those raise texts live in `20261004090000_push_delivery.sql`,
   outside this migration; the coordinator should confirm each raise message
   there is value-free (no member/tenant identifiers) so the PSD-006/PSD-008
   no-raw-exception rule holds at the cron surface, not just in the driver
   result.
4. **P3 — Pre-existing owner-statement gap in the runner.**
   `app.run_push_events(uuid)` carries the four-role revoke but no explicit
   `alter function ... owner to postgres` in `20261004090000_push_delivery.sql`
   (line ~1574), unlike its sibling functions. Migrations apply as the
   platform's postgres-equivalent role so the effective owner is almost
   certainly already postgres, but the explicit statement is the established
   pattern and the tick's security-definer delegation depends on it. Pre-existing
   file; record, do not edit it from this review.
5. **P3 — Extension schema name assumption recorded, not invented.** `net`
   and `vault` are the platform-supported schemas per PSD-001; the named-arg
   `net.http_post` production-transport caveat the builder recorded is real
   and remains covered by PSD-018's live non-sending proof, not by any
   synthetic seam.

## Explicitly verified non-findings

- The duplicate-secret path cannot leak the secret: with two matching rows,
  the window count raises `ambiguous` before anything is returned.
- Lock contention (`skipped=true`) reads no secret and queues nothing.
- The eligible snapshot uses one statement, so count and selection cannot
  disagree (PSD-004's "same statement-time configuration snapshot").
- `skipped=false` on the zero-eligible path is correct: zero tenants processed
  is a completed tick, not a skipped one; `skipped=true` is reserved for lock
  contention per PSD-002.
- No test/holdout file, no scratchpad content, no other evidence file was
  opened; nothing was executed; no file other than this report was modified.
