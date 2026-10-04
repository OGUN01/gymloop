# H84 push scheduler holdout — author report (2026-10-04)

Author: independent holdout author, blind. Sources read: only
`openspec/changes/push-notifications/deployment-scheduler-declaration.md`
(PSD-001..020) and `openspec/changes/push-notifications/proposal.md`, plus
`supabase/tests-holdout/h83_occupancy_analytics_holdout.sql` for TAP/fixture
conventions only. No implementation (none exists), no visible suite, no other
holdout, no docs/evidence or scratchpad content, and not the unfrozen
`deployment-runner-interface-declaration.md`. No Cloud SQL was executed; no
git operation was performed.

## Deliverable

`supabase/tests-holdout/h84_push_scheduler_holdout.sql` — plan(94),
rollback-only (lowercase `begin;` … `select * from finish(); rollback;`),
fixture prefix `84500000-`. RED by design against the unbuilt
`20261005130000_push_scheduler.sql`: all driver/helper posture, prosrc and
behavioral probes fail loudly today; catalog armor (extensions present, no
cron job, no Vault secret, no provider row) may already hold and stays.

## Coverage (sections)

- A1–A8 inertness/absence: declared extensions present; migration creates no
  cron job, no `run_push_dispatch_tick` reference, no WSP/WhatsApp schedule,
  no Vault secret, no `samuraiapi-51996` provider row (PSD-001/013).
- A9–A26 posture of `app.run_push_dispatch_tick()`,
  `app.read_push_dispatch_secret()`, `app.enqueue_push_dispatch_wakeup(text)`:
  exists, VOLATILE, SECURITY DEFINER, postgres-owned, search_path pinned,
  EXECUTE denied to public/anon/authenticated/service_role (PSD-002 +
  registry section).
- A27–A38 catalog `prosrc` pins of the REAL helpers: frozen endpoint, header
  name, content type, 5000 timeout, empty body, no Authorization/apikey/
  Bearer; secret helper reads the frozen Vault name and does no HTTP; driver
  delegates to `run_push_events`, locks on the fixed job name, never
  enqueues directly, derives offset from `statement_timestamp`.
- A39–A46 extension custody: effective-EXECUTE denial over Vault
  secret/decryption, net enqueue/inspection, cron scheduling functions for
  all four roles; SELECT denial over `vault.secrets`,
  `vault.decrypted_secrets`, `net._http_response`, `cron.job`,
  `push_provider_configurations` (PSD-007).
- B1–B8 unconfigured tick via sanctioned readiness seam: exact seven-key
  result, zero counts, no enqueue, no attempt rows, skipped=false (PSD-003).
- C1–C5 lock overlap: advisory try-lock held on `hashtext('push-dispatch-minute')`
  → inert skipped tick, no Vault work (Vault intentionally empty, so any
  wrongful read fails loudly), no enqueue (PSD-002).
- D1–D4 / E1–E3 / F1–F8 real Vault matrix against the REAL secret helper with
  synthetic values only: blank entry refuses value-free; duplicate entry
  either refuses the tick (if the platform permits two same-name rows) or is
  structurally impossible (unique-name index pinned); exactly one nonblank
  entry yields exactly one wakeup whose recorded seam secret equals the
  staged value; exact result shape retained (PSD-005).
- G1–G4 mixed readiness: only ready tenants processed; still one wakeup.
- H1–H3 readiness failure aborts the whole tick, propagates (no silent
  swallow), and enqueues nothing after the error (PSD-004).
- I1–I4 100-tenant bound: 109 eligible tenants → exactly 100 processed,
  exactly one wakeup (PSD-004).
- J1–J3 hygiene/health: no captured refusal message contains the synthetic
  secret value; zero swallowed staging errors; 109 provider rows staged.
- J4–J9 activation cron shape: `cron.schedule('push-dispatch-minute',
  '* * * * *', 'select app.run_push_dispatch_tick();')` yields exactly one
  postgres-owned row with the frozen schedule/command; unschedule reverses
  cleanly; same-name reschedule behavior recorded for the activation
  protocol (PSD-013).

## Sanctioned seams used

`app.push_configuration_ready` replaced by a synthetic narrowed predicate
(backed by `pg_temp.h84_ready`, with a deliberate poison-raise test row — a
test construct inside the sanctioned seam, disclosed here);
`app.enqueue_push_dispatch_wakeup` replaced by a recorder seam. Both seams
are postgres-owned definer with EXECUTE revoked from the four roles; no
ordinary access granted, no real HTTP enqueued, no real credential read.
The real secret helper is never replaced — the Vault matrix exercises it
directly. All replacements are undone by the single ROLLBACK.

## RED expectation

Pre-implementation: every driver/helper probe (A9–A26, B–I sections that call
the tick) fails; A27–A38 prosrc pins fail on empty prosrc; armor assertions
(A1–A8, A39–A46, J2–J9) may pass today and remain mandatory post-build.
Post-implementation the whole plan must run without abort; failures localize
to the exact PSD clause.

## Declared gaps / ambiguities (recorded, not invented)

1. Lock-key derivation: PSD-002 says "keyed by the fixed job name" but does
   not pin the derivation. The suite assumes `hashtext('push-dispatch-minute')`;
   a different keying is a contract conversation, not a silent test edit.
2. Cyclic offset determinism (PSD-004 formula) is not directly observable
   from the seven-key result; the suite pins the 100-tenant bound, one-wakeup
   and statement-time derivation pins, but per-minute rotation ordering needs
   an implementation-observable seam or the live gate.
3. Nonzero runner count aggregation (PSD-006 four keys) is pinned at zero
   only; staging real push events blind was not attempted — requires a later
   lawful fixture round or visible-suite coverage.
4. Runner (not readiness) failure mid-loop ("no enqueue after an event-runner
   error") is covered only via the readiness-poison proxy; forcing a real
   `app.run_push_events` failure blind is out of the sanctioned seam set.
5. `hashtext`/prosrc pins are static-by-nature; production transport
   correctness of the real enqueue/secret helpers remains the separate
   protected verification the declaration itself demands.
6. Provider-configuration staging uses a best-guess column shape
   (id, tenant_id, firebase_project_id, activated_at); any shape mismatch
   lands in `h84_errors` and fails J2/J3 loudly rather than silently passing.
7. `cron.job` username pin assumes the `username` column; if the installed
   pg_cron version differs, the staging health records it.
8. Existing unrelated cron schedules' continued operation (PSD-007 tail) is
   not asserted — pre-splice state is not observable inside one transaction;
   left to CI/live gates.

Static checks: `scripts/check-pgtap-rollback.mjs` clean for this file.
File sha256: `e9a074971310334328b9ab184da2bd174466bc2b257f533d081ab7553b4fc89f`.
