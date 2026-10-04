# Push scheduler visible author report (PSD visible suite)

Author: independent visible test author, provider-free scope. Authority: only
`openspec/changes/push-notifications/proposal.md` (FROZEN 2026-10-03) and
`openspec/changes/push-notifications/deployment-scheduler-declaration.md`
(FROZEN 2026-10-04). The unfrozen deployment-runner-interface declaration was
NOT read. No holdout file, no docs/evidence file other than this report, no
scratchpad file, no implementation (the scheduler migration does not exist),
no Cloud SQL, no git.

## Deliverable

- `supabase/tests/84_push_scheduler.sql`, sha256
  `a6c96e8f0c5cdc44e20b31218a4b7e25b1834d1da0e4795b23ec73cc6b91d4a4`,
  plan(149) = 141 top-level assertions + 8 emitted by four adaptive blocks
  (duplicate Vault entry 1, blank Vault entry 1, cyclic wrap exclusion 1,
  lock-overlap branch 5). One `begin;`/`rollback;` pair, lowercase, literal
  plan, `select * from finish();`, fixture prefix `84000000-`. Rollback guard:
  `check-pgtap-rollback: 159 pgTAP file(s) checked, all rollback-wrapped`.

## Coverage map (declaration clause -> section)

- A (11): inert migration — no cron job, no Vault entry, no public facade;
  installed pg_net/pg_cron/vault; existing runner present with exactly the
  four aggregated keys (PSD-001/002/003/006).
- B (30): exact private shape of `app.run_push_dispatch_tick()`,
  `app.read_push_dispatch_secret()`, `app.enqueue_push_dispatch_wakeup(text)`:
  return types, VOLATILE, SECURITY DEFINER, postgres owner, explicit
  search_path, effective EXECUTE denial for PUBLIC/anon/authenticated/
  service_role (PSD-002 + registry section).
- C (25): extension custody — effective denial of `cron.schedule`,
  `net.http_post`, `net.http_request` SELECT, `vault.secrets`
  SELECT/INSERT, `vault.decrypted_secrets` SELECT, the Vault ciphertext
  column, and schema CREATE in vault/net, across the four ordinary roles
  (PSD-007). Catalog/ACL pins are NULL-safe.
- D0 (18): REAL helper contract before any seam replacement —
  exactly-one-nonblank Vault lookup returns the entry value (the RED driver);
  missing/duplicate/blank refuse with value-free operational errors
  (adaptive duplicate/blank blocks: if the Vault schema itself refuses the
  fixture row, that refusal is pinned instead — belt-and-braces honesty, no
  invented implementation facts); the REAL enqueue helper's fixed request is
  pinned from the in-transaction queue row (exact URL, no query string,
  Content-Type, dedicated secret header, no authorization JWT, body `{}`,
  timeout 5000) and the row is deleted before the savepoint rollback, so no
  request can ever be delivered (PSD-005).
- D1 (13): zero eligible tenants -> seven-key result, all zero counts,
  `skipped=false`, zero Vault reads and zero enqueues observed through the
  two sanctioned seams (PSD-003).
- D2 (14): mixed readiness (past-activated / null-activated / future-activated
  / absent) -> exactly one tenant processed, exactly one real announcement
  event created through the REAL runner with the exact approved dedupe key,
  one Vault read and one enqueue carrying the resolved secret (PSD-003/005/006).
- D3 (12): 103 ready tenants -> tenantsProcessed=100, 100 distinct tenants
  with exactly one event each, wakeupsQueued=1, and the 3 excluded tenants
  consecutive in the cyclic ascending order (offset-free structural pin)
  (PSD-004).
- D5 (6): a readiness seam that fails for one fixture tenant -> the whole
  tick refuses, no enqueue, no secret read (PSD-004/005 ordering), and no
  surviving event rows after the savepoint rollback.
- D4 (5, adaptive): back-to-back second tick — contention branch pins the
  inert skipped tick (zeros, no seams touched); release-per-tick branch pins
  bounded idempotent re-processing (100 tenants, zero new events by dedupe,
  one wakeup). See tension note below.
- E (13): activation ground facts — PK replay preserving a fixed
  activated_at, inert replay accepted, differently-bound rows detectable for
  operator validation, one cron job with exact name/schedule/command and
  postgres owner, replay leaves one job, no WSP schedule in the cron catalog
  (PSD-013/014).

## RED expectation

The scheduler migration does not exist, so every B/D pin is RED now (absent
objects leave no captured rows / NULL-safe probes fail cleanly); A/C/E pins
are environment armor that must stay green. The suite runs end-to-end with
`ran=plan` and a nonzero failure count — RED by plan-honest failures, never
by abort. Once CI applies the migration the same file judges the real
implementation without edits.

## Declaration gaps and interpretation notes (recorded, not invented)

1. **Lock semantics tension.** PSD-002 says "transaction advisory try-lock";
   read as transaction-scoped, every tick after the first inside one
   rollback-only transaction would be inert, contradicting the declaration's
   own required-case list. The suite pins the required behaviors first and
   makes the overlap case adaptive; the builder/critic must reconcile.
2. **SQLSTATEs.** The declaration names no SQLSTATE for the helper refusals
   or the tick failure; the suite pins value-free operational error messages
   (and that they are not catalog errors) instead of inventing codes.
3. **skipped semantics.** Only lock contention is declared to skip; the
   suite pins `skipped=false` for real-work ticks accordingly.
4. **`proconfig` search_path format.** Postgres stores empty search_path in
   proconfig in a version-dependent spelling; the suite pins that an explicit
   search_path is present rather than guessing the exact stored form.
5. **Statement-time snapshot equality (count vs selection, PSD-004).** Not
   provider-free observable without a seam the declaration does not grant;
   left to the fresh critic's source review.
6. **`cron.schedule` overload.** Pins `(text,text,text)`; absence of that
   exact overload is treated as denial (cannot execute what does not exist).
7. **Constants consistency (100/60s/5000ms/job and Vault names).** SQL-side
   values are pinned here; the shared named constants live in
   `packages/shared/src/config/constants.ts` and their consistency proof is a
   gate/critic matter, not a SQL observable.
8. **Vault name uniqueness.** If the Vault schema enforces unique names, the
   duplicate-entry helper branch is unreachable; the adaptive block records
   which layer refuses.
9. **A1/A2 armor caveat.** "No cron job / no Vault entry" is pinned at suite
   start; if protected provisioning ever runs before the pgTAP suite in CI,
   those pins become false REDs — provisioning must stay after the full DB
   run, per PSD-010's settle requirement.
10. **Real queue-row inspection interpretation.** The declaration forbids
    tests to "enqueue a real HTTP request"; the suite inspects the in-
    transaction queue row created by the REAL helper and deletes it before
    the (only) rollback — with no commit the pg_net worker can never observe
    or deliver it, and no real secret value is involved. Recorded here for
    the fresh critic to adjudicate the strict reading.

## Lawfulness

No constraint disabled, no protected timestamp touched, no synthetic state
that persists (single rollback), no real credential value, no Cloud SQL, no
commits, no implementation or holdout reads.
