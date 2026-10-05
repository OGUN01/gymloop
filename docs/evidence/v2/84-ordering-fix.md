# 84_push_scheduler ordering fix

## Defect

`84_push_scheduler.sql` aborted in the CI's pgTAP run (`exited 3`, 0 tests ran).

Root cause: `pg_temp.reads_now()` and `pg_temp.sends_now()` are
`language sql` helper functions whose bodies reference
`pg_temp.seam_reads` / `pg_temp.seam_sends` — temp tables that were
created ~110 lines later (line 200). PostgreSQL validates language-SQL
function bodies at CREATE time (check_function_bodies defaults ON), so
both CREATEs failed and the suite aborted before `plan(149)` could
execute. Same class as the `h83_snap` defect in h83 and the `zone76`
grant-before-create defect in 83.

## Fix

Moved `create temp table seam_reads(n integer)` and
`create temp table seam_sends(n integer, secret text)` from their
original position (line ~200, after the D0 savepoint) to immediately
after `select plan(149)` (line 72-73) — before the helper function
creates at lines 92-93.

## Verification

- Statement-order sanity check: zero remaining reference-before-create
  problems (3 false positives are comments in the header).
- `node scripts/check-pgtap-rollback.mjs`: 159 files, all
  rollback-wrapped — green.
- `plan(149)` intact; `rollback;` terminal statement intact.

## sha256

`dcc891eeece3680cd2cec1ac9a42fd28303ad60cb3fe448d561929fb4afea7ca`
