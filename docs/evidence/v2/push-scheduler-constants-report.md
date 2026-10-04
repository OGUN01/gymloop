# Push scheduler TS constants — registration report

Directive: close the fresh scheduler critic's P2-1 (shared TS operational
constants unregistered — SQL literals had no consistency proof).

## Added

`packages/shared/src/config/constants.ts`, immediately after the existing
`PUSH_DISPATCH_HTTP_STATUS` block, following the `PUSH_*` naming convention:

```ts
/** Frozen PSD-001…018 inert deployment scheduler bounds (deployment-scheduler-declaration). */
export const PUSH_SCHEDULER = {
  tenantTickLimit: 100, tickIntervalSeconds: 60, wakeupTimeoutMs: 5000,
  cronJobName: 'push-dispatch-minute', vaultSecretName: 'gymloop_push_dispatch_secret',
} as const;
```

Values mirrored verbatim from the migration literals (verified at
`supabase/migrations/20261005130000_push_scheduler.sql`):
- tenant tick/activation limit 100 — tick selection `(floor(epoch(v_tick)/60)::bigint * 100) % v_count` and `least(100, v_count)` (lines 196–197; PSD-004)
- tick interval 60 seconds — the minute-cycle epoch division; activation schedule `* * * * *`
- wakeup timeout 5000 ms — `timeout_milliseconds => 5000` (line 127; PSD-006)
- cron job name `push-dispatch-minute` (lines 12/177/222)
- Vault secret name `gymloop_push_dispatch_secret` (line 85; PSD-005)

## Registry

`docs/registry.md` "Push deployment scheduler (inert migration)" section gains
one row for `PUSH_SCHEDULER` (file, purpose, consumers) per hard rule 1.

## Checks

- shared package platform-free rule respected (constants file only, no new imports).
- `pnpm exec tsc --noEmit` in `packages/shared`: the only two errors are the
  pre-existing ones in `src/api/__tests__/purchase-visible-runtime-contract.test.ts`
  (the documented R10 generated-vocabulary residue pending the post-migrate
  gen-types push) — none reference `constants.ts`.
- No eslint-disable, no test/holdout/scratchpad/evidence reads beyond the
  named public builder report, no migration edits, no commits, no Cloud SQL.

## Provenance

- `packages/shared/src/config/constants.ts` sha256:
  `9cfd0c88db1318cb3cfd307396d4f5a0a43b1441489354e8726a0ed42924f803`
- `docs/registry.md` sha256:
  `46f9e7f226bd93b2e57b955aafe636034a54fd5b64d09509b1fbe740f753cdce`
