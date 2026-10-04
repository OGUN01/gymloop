# RPE holdout author report — h82 repair round 1 (2026-10-04)

Author: independent blind holdout author (fork, glm). Authority: only
`openspec/changes/report-exports/proposal.md`,
`openspec/changes/report-exports/sql-envelope-declaration.md` (authoritative),
`docs/design/v2/rpe-bar.md`, the prior `h82` holdout, and one older holdout
(`h80`) for TAP/fixture conventions. No implementation migration, no visible
suite, no other holdout, no evidence or scratchpad file was read. No Cloud
SQL, no git mutation, nothing executed against any database.

## Deliverable

- Repaired `supabase/tests-holdout/h82_report_exports_holdout.sql`,
  sha256 `5bf0b173b60f332e17dd66b3f1d4bebae182f02acf35ce67c5c6795e6b861b22`.
- `plan(180)` literal; lowercase `begin;`/`rollback;`; `select * from finish();`;
  SETOF-text TAP; fixture uuid prefix `82900000-`; zero commits.

## Mirror / fallback elimination

- The private behavioral mirror (`holdout_rpe` schema: `export_snapshot`,
  `append_event`, `report_export_events`) is **deleted entirely**. Every
  meaningful assertion now exercises the real five-argument
  `public.export_report_snapshot(text,date,date,uuid,integer)` scalar-jsonb
  RPC, the real private `app.report_export_preparations` relation with its two
  declared triggers, and the real `public.append_report_export_event` release
  helper — called as `set local role authenticated` callers with JWT claims,
  under real RLS.
- There is no fallback path: no `exception when others then … pass` pattern
  exists; a failing real call fails its assertion (or aborts the suite, which
  is also a failure signal for the diagnostic harness).
- Section A keeps the prior NULL-safe catalog probes (owner, invoker/definer,
  volatility, empty search_path, grants, RLS, column privileges, NOT NULL/no
  defaults on derived columns, both trigger shapes and names, both declared
  index names including the audit unique partial index) and adds the
  VOLATILE pin and service_role/no-PUBLIC EXECUTE pins the frozen declaration
  names.

## What the repaired suite now pins (new/changed vs the mirror era)

- Exact 19-key scalar success envelope and exact per-dataset row key sets
  (payments 12, attendance 11, members 8), SQL null → JSON null honesty
  (erased member name/code, null paid time, null receipt, open-event
  checkout) instead of the mirror's invented `''`.
- Over-cap is the **refusal envelope** (`rows: []`, `returned_row_count "0"`,
  `has_more true`, exact count/metadata), not an exception — and it inserts
  no preparation and appends no audit. At-cap succeeds in full with
  `returned_row_count = data_row_count`.
- Prepared/audit linkage: exactly one preparation per accepted attempt
  (including zero-row), input echo, derived tenant/actor/role/format/stamps
  filled server-side, `source_cutoff_at_utc = snapshot_at_utc`, direct-INSERT
  lawful path (bounded, same-actor, count derived from a real RLS scan) and
  its refusals (derived column supplied, non-owner, over-cap, unknown
  dataset), cross-tenant RLS SELECT scoping both directions.
- Release helper: canonical `byte_count` string (type, non-canonical,
  8388608/8388609 boundary), 64-lowercase-hex digest, no extra caller keys,
  prepared-required linkage, foreign-actor and deactivated-owner refusal,
  one-release-forever, exact 17-key released `after` and exact 15-key
  prepared `after` (no personal content), public helper accepts only
  `report_export.released`, direct audit INSERT refused, and a global
  count(preparations) = count(prepared audits) coherence close.
- Preserved lawful legacy assertions: actor matrix (10 roles/shapes) with
  actor-first ordering, no audit on refusals, foreign-tenant empty scope,
  unknown ≡ foreign branch identical refusal, invalid-zone explicit refusal
  with lawful restore, IST boundary honesty (…042 included at local midnight,
  …044 excluded on the upper bound, …046 one second early), composite
  ordering, beyond-safe-integer paise `9007199254740993` as exact text, USD
  row never summed, `created` status word not presented as collected money,
  members joined_on direct-date cohort with erasure exclusion, cap 0/5001 and
  reversed/367-day range refusals, fresh export UUID per attempt.

## RED expectation mapping

- **Pre-implementation (migration absent):** Section A is RED (all 55 catalog
  probes miss), and the first real-RPC call in Section C aborts the file with
  `undefined function` — the strongest honest RED, not a per-assertion count.
  This file has NOT been executed by this author.
- **Post-implementation deviations** surface as targeted assertion failures:
  shape pins (§A) fail independently of behavior; envelope/projection pins
  (§G–§J) fail on key sets, ordering, nulls, caps; linkage pins (§K–§L) fail
  on preparation/audit/relate semantics. SQLSTATEs are pinned per codebase
  convention (42501 authority refusals, 22023 semantic refusals) where the
  frozen declaration names no state; a conforming implementation that uses
  different states will flag here and needs a `spec:` adjudication, not a
  silent fix.

## Ambiguities hit (reported, not invented)

1. **Attendance fixture columns are best-effort.** The suite inserts
   `attendance(id,tenant_id,member_id,branch_id,source,checked_in_at,
   checked_out_at,created_at)` with `source` read as a lawful enum label from
   the catalog at fixture time. If `attendance` carries additional NOT NULL
   columns or a non-enum `source`, the fixture aborts; the repair is an
   author fixture correction, not an implementation change.
2. **`checked_in_local` exact string** is pinned as
   `2026-09-15T08:30:00+05:30 [Asia/Kolkata]` from the declaration's "local
   ISO timestamp with numeric offset followed by ` [<timezone>]`" — if the
   implementation emits a space separator or different fraction formatting,
   this flags for adjudication.
3. **`amount_display`** is pinned type-only (string). The existing formatter's
   exact output is not derivable from the contract alone; the route-level
   decoded-file comparison (bar RPE-Q5) owns the exact rendering.
4. **Audit actor column names** in `audit_log` are not named by the
   declaration, so the suite asserts record_type/record_id/action/`after`
   shapes and never an actor column name.
5. **CSV byte-level checks (BOM/CRLF/quoting/apostrophe protection)** are
   transport-layer contract (route assembly); the SQL holdout pins every
   envelope field that feeds them and deliberately does not duplicate the
   route suite.
6. The audit-failure-simulating case ("audit failure releases nothing") is not
   simulated here — inducing an audit trigger failure would require tampering
   with platform objects; it is left to the fresh critic and CI seam.

## Ownership note

This file and this report are author-owned working-tree edits, uncommitted.
Per campaign rules the primary commits test-only `spec:` paths after its own
verification; the implementer never opens this file.
