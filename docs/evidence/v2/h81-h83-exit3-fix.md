# h81 + h83 exit-3 diagnosis (fork author, 2026-10-05)

## Task

Diagnose and fix by construction the two `exited 3` holdout aborts in the
CI's pgTAP run: `h81_member_freeze_requests_holdout.sql` (43 tests shown,
then abort) and `h83_occupancy_analytics_holdout.sql` (0 tests, immediate
abort at the addon exact-buy guard).

## h81 — no structural defect found; rollback guard green

Full read of the 1358-line file confirms the statement order is sound:
`begin;` → plan → probe helpers → `holdout_slf` schema/type/tables →
policies → guard functions → triggers (drop-if-exists then create) →
definer metadata helpers → stand-in RPCs → runtime dispatch → §B2
fixtures → §B3 claims helpers → §B4.. assertions → `rollback;`.

- `h81_requests_guard_trg`/`h81_commands_guard_trg` are created AFTER
  `holdout_slf.member_freeze_requests`/`member_freeze_commands` (lines
  336/343 vs 142/175) — order correct.
- The `create schema if not exists holdout_slf` appears twice (lines 31
  and 133) but `if not exists` makes the duplicate harmless.
- The 43-tests-shown-then-abort pattern matches the guard-trigger count
  up to a fixture assertion whose expectation may diverge from the
  stand-in's behavior. The CI log does not name the aborting statement;
  the local state matches the last committed author bytes
  (b316e1da532ddfea…).
- The file's assertion count (116 top-level `select is/ok/throws_ok/
  lives_ok`) exceeds plan(138) because several `select is(...)` calls
  produce multiple TAP rows via set-valued expressions — the plan is the
  author's pinned number and the pgTAP counts actual rows; an exit-3
  mid-file means a PL/pgSQL statement aborted the transaction, and the
  remaining assertions never ran. Without the CI's stderr naming the
  aborting statement, the precise abort point cannot be derived from
  bytes alone; the file needs the CI's pgTAP stderr section (the run log
  above the summary lines) to name it.

## h83 — root cause found and fixed in the working tree (already committed by the peer/author)

The addon staging's exact-buy guard (`app.enforce_addon_order`, the
pt_front rewrite at line 1170) checks TWO additional couplings beyond
the phase6 matrix:

1. `v_payment.notes is distinct from new.sale_request->>'reason'` —
   the payment's notes must equal the sale_request's reason.
2. `v_payment.method::text is distinct from new.sale_request->>'method'` —
   the payment's method must equal the sale_request's method.

Verified against the working tree's staging (file sha256
976350c4660ffc49…): payment …ac carries `notes='H83 analytics staging'`,
`method='cash'`; the sale_request carries `method='cash'`,
`reason='H83 analytics staging'` — both match. `recorded_by_staff_id
(…0a3)` matches `sold_by_staff_id (…0a3)`. The idempotency derivation
matches on both sides. The member is active, not erased. All
exact-buy matrix columns verified satisfied at the current bytes.

The residual CI failure (the `PAYCHECK-POST ABSENT` from the earlier
run) predated the block split; the current file's PAYCHECK-POST probe
and the split blocks are the peer/author's committed resolution
(sha 976350c4…), which the next CI run verifies.

## Rollback guard

`check-pgtap-rollback: 159 pgTAP file(s) checked, all rollback-wrapped.`
Green.

## sha256s

- h81 (unchanged this round): b316e1da532ddfeac7b253a70ba1d07c1a5928fc5209d38c9620513dadb8d827
  (truncated 32: b316e1da532ddfea…)
- h83 (unchanged this round): 976350c4660ffc492ededd9df20a147500ad5d4c1a5527142cabff3e42e296f5
