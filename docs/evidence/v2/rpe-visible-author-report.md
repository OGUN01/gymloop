# RPE visible test author report — suite 82 repair (2026-10-04)

Author: independent visible test author (blind to implementation and holdouts;
authority = `openspec/changes/report-exports/proposal.md` (frozen, CSV-first),
`openspec/changes/report-exports/sql-envelope-declaration.md` (frozen
mechanical envelope), `docs/design/v2/rpe-bar.md`, TAP-convention reference
suites only. `supabase/migrations/20261005110000_report_exports.sql` was never
opened; no holdout, no docs/evidence (other than this report), no scratchpad
file was read; no SQL executed; no git commands run.)

- File: `supabase/tests/82_report_exports.sql`
- sha256: `00b1f9591a47751674a842e52a5eef8f9e966e3b477bd299fff8ec9466dfa9f6`
- plan: **206** (was 99), all assertions line-start `select is(...)/ok(...)`
  emitting TAP results, one lowercase `begin; … rollback;` pair,
  `select * from finish();`, zero commits, zero PERFORM TAP.
- Static guard: `node scripts/check-pgtap-rollback.mjs` → 157 pgTAP files
  checked, all rollback-wrapped (whole-repo run; this file included).

## Why the suite was rewritten rather than patched

The pre-repair suite pinned the superseded caller shape
`{rows,has_more,timezone}` (its own header said so) and the superseded audit
model (public `append_report_export_event` accepting `report_export.prepared`
with caller-supplied tenant/actor/role/row_count details, truncated rows on
cap, empty-scope reads for unknown branches). The frozen envelope declaration
supersedes every one of those. Per-authority rule ("documents win"), the suite
now pins the declaration, preserving every lawful business-rule assertion from
the old suite (projection key lists, ordering, money-text, erasure blanks,
cross-currency, tenant isolation, stored-branch filtering, local stamps,
DST-free zone handling, invalid-zone refusal, actor precedence, audit
append-only surroundings).

## New coverage added (declaration-driven)

- **A22–A46**: `app.report_export_preparations` exists with RLS and exactly
  the 5 input + 14 derived columns; authenticated has column-level INSERT on
  inputs only (no derived-column INSERT, no UPDATE/DELETE); anon/service_role
  hold nothing; `app.derive_report_export_preparation` STABLE INVOKER +
  `app.audit_report_export_preparation` VOLATILE DEFINER, both empty
  search_path, no direct EXECUTE; trigger names/timings
  (`…_derive` BEFORE INSERT, `…_audit` AFTER INSERT); the declared
  `report_export_preparations_tenant_actor_export_idx`; the partial UNIQUE
  `audit_log_report_export_event_unique` over exactly the two RPE actions.
- **A7 tightened**: the public command is pinned VOLATILE exactly (the
  declaration repairs the registry's STABLE label; the old suite accepted
  `v` or `s`).
- **B17**: row cap above the declared 1…5000 bound refuses.
- **B18/B19**: unknown branch and foreign (other-tenant) branch share ONE
  indistinguishable unavailable refusal — replacing the old empty-scope read.
- **C2/C15–C17**: boundary payments — one at exactly gym-local midnight from
  (included, earliest row), one at exactly local midnight after through
  (excluded from January, included in February).
- **C18/C19**: unsafe-size money (9007199254740993 paise, beyond the JS
  safe-integer range) crosses as exact canonical decimal text with a matching
  presentation column.
- **C20–C22**: payments branch filter uses the member's CURRENT branch; an
  erased member's payment cannot satisfy any branch filter.
- **F1–F41**: the exact 19-key scalar envelope; every stamp key; exact UTC
  boundary values for Kolkata (+05:30); generated ≤ snapshot; snapshot =
  source_cutoff; fresh export UUID per retry; counts as canonical strings;
  `row_cap` JSON integer echo; over-cap refusal envelope (`rows: []`,
  `returned_row_count: "0"`, `has_more: true`, exact count) with NO prepared
  attempt and NO audit; exact-boundary cap (6/6) returns all rows;
  prepared-audit linkage (one preparation + one prepared event, envelope
  snapshot/count equal the audit's, no before image, exact 15-key after
  payload); members/attendance range bases; an America/New_York DST boundary
  pair (start 2026-03-07T05:00:00Z EST, end 2026-03-10T04:00:00Z EDT —
  actual local midnights, not a fixed 24-hour addition; zone restored after);
  zero-match exports stamp and still prepare/audit.
- **G1–G25**: direct lawful preparation INSERT by the real owner; every
  derived column value (tenant/actor/role/basis/zone/scope/count/stamps);
  supplied derived value refused; over-cap INSERT refused; UPDATE/DELETE
  refused; member sees and inserts nothing; no cross-actor/tenant SELECT;
  prepared audit appended for direct attempts including zero-row ones.
- **H1–H27**: public release writer accepts ONLY `report_export.released`
  (`prepared` via the public path refuses); exact detail allowlist
  `{byte_count, artifact_sha256}`; byte count as canonical decimal text ≤ 8
  MiB and > 0; digest exactly 64 lowercase hex; absent/foreign/already-
  released attempts refuse; attribution from claims; refused calls write
  nothing; the released after-payload is prepared stamps + exactly the two
  release fields.

## Removed/replaced assertions, with reasons

- Old F1 (`keys = has_more,rows,timezone`) — superseded envelope shape.
- Old F2/F3 (cap truncation with rows + has_more) — the declaration refuses
  the whole file over cap (`rows: []`, `returned_row_count: "0"`).
- Old F5 (timezone as one of three keys) — folded into the 19-key pin.
- Old F6/F7 (unknown branch = empty scope) — superseded by the one
  unavailable refusal (B18/B19).
- Old G1–G8 (public prepared events with caller-supplied details) — prepared
  auditing is private via the preparation relation's triggers; public path
  accepts only `released` (H14 pins the refusal).
- Old G9's `byte_count` as JSON number `2048` / digest `a3f1` — superseded by
  canonical decimal text ≤ 8 MiB and 64 lowercase hex (H4/H5/H20–H24).
- No lawful business-rule assertion was removed. All fixture changes are
  additive (three payments, one member); the existing refund lifecycle,
  attendance provenance and identity fixtures are unchanged and remain
  lawful under the pinned table checks (front_desk requires staff+reason;
  offline requires the replay pair).

## RED expectation

Before `20261005110000_report_exports.sql` exists, the suite must be RED
end-to-end WITHOUT aborting: A1 fails (no function), B/H probes return
42P01/42883 against their expected codes, and the envelope captures leave no
`res` row so their assertions do not evaluate — `finish()` then reports an
honest plan mismatch (ran < 206). Once CI applies the migration, every
assertion evaluates. RED-defect pins (the assertions that MUST fail against
any implementation that deviates from the declaration): the 19-key envelope
pin, exact Kolkata/DST boundary instants, over-cap refusal envelope with no
preparation/audit, counts-as-strings, snapshot=cutoff, derived-column
attribution, prepared-event after-payload key set, release allowlist and
unique-release semantics, and the unknown/foreign-branch shared refusal.

## SQLSTATE pins that are author assumptions (declaration names no code)

Shared repo precedence vocabulary (actor 42501; value/shape 22023; audit
details allowlist 23514 — carried from the pre-repair suite's header) was
applied where the declaration is silent; a different mapping is a
contract-defect round-trip, never a test edit:

1. Unknown/foreign branch refusal pinned `22023` (B18/B19) — "one
   indistinguishable unavailable response".
2. Supplied derived-column INSERT refusal pinned `in ('22023','42501','P0001')`
   (G13) — either a column grant or the declared trigger may fire first.
3. Over-cap preparation INSERT pinned `in ('22023','P0001')` (G14).
4. Release refusals for absent/foreign/already-released attempts pinned
   `42501` (H10/H11/H12) — writer revalidation; a concurrent loser that
   reaches the unique index instead would surface 23505, which H12's
   `<> 'OK'` form also catches.
5. byte-count/digest format refusals pinned `in ('23514','22023')`
   (H20–H24) — writer validation or a CHECK constraint both satisfy the
   contract.

## Contract ambiguity flagged (not resolved by invention)

`amount_display` derivation location: the declaration lists `amount_display`
as a required row key in the scalar envelope while also calling it "a
presentation column … a format-only adapter may derive this". The suite pins
the RPC's rows as carrying `amount_display` (the envelope declaration is the
acceptance surface and behavioral acceptance calls the REAL RPC). If the
route (not the RPC) is meant to derive it, the implementer must round-trip
rather than bend the test.

## Other notes

- The huge-money fixture (payment 407, 9007199254740993 paise) assumes no
  upper CHECK bound on `payments.amount_paise` beyond positivity; if a
  bound exists, the fixture insert fails and the suite aborts — that would be
  a fixture defect for this author to repair, not an implementation defect.
- The February-range and DST sections each restore the gym zone / use only
  rollback-only state; the commercial-invariant trigger is disabled only for
  the two zone-corruption fixtures (same pattern as the pre-repair suite's
  invalid-zone case) and re-enabled immediately.

## Runtime repair round 1 (post first Cloud diagnostic)

Runtime fact (orchestrator's rollback-only diagnostic, current snapshot): the
suite aborted before its plan with
`ERROR: 42501: check-in refused: offline replay requires a member gate event`.

Diagnosis: fixture row 423 staged an offline replay as `source='front_desk'`
with `assisted_by_staff_id` set. The active check-in trigger
(`app.enforce_check_in`, latest definition 20260925150000_checkin_gate_modes)
accepts `offline_recorded_at` only for a member gate replay: member claims,
`source='qr'`, a live `qr_sessions` row and a non-null `client_event_id`; a
front-desk row can never lawfully carry offline stamps. The suite's own D7/D8
pins (offline + replay stamps on projection row 2) therefore require the
member-replay path, and D9's original `front_desk` pin on the same row was an
authoring defect contradicting the system's lawful offline-replay rule.

Repair (fixture staging + one author-owned assertion-value correction):
- Staged the offline provenance lawfully: added `plans` u(151),
  `memberships` u(161) for member 101 (active, 2026-01-01..2026-01-31 — the
  member scan requires a membership live on the scan day),
  `organization_settings` u(1) with `checkin_gate_mode='rotating_screen'`
  (matching the session's default gate mode), and `qr_sessions` u(430)
  (branch 11, issued/created 2026-01-04, expires 2026-01-06, rotating).
- Row 423 is now inserted under member 101's own claims
  (`pg_temp.claim('member',null,101,901,1)`) as `source='qr'` with
  `qr_session_id=u(430)`, `client_event_id=u(431)`,
  `offline_recorded_at=2026-01-05 02:30Z`; the trigger owns
  `checked_in_at` (= offline time) and `replayed_at` (server-owned). Claims
  cleared immediately; `checked_out_at` 04:00Z applied by the lawful later
  write (check-out is a legitimate update; the guard is insert-only).
- Dedupe safety: settings default `checkin_dedupe_seconds=120` < the 1800 s
  gap to row 421 (02:00Z), and client event ids differ.
- Assertion correction (not a weakening; equal-strength exact pin): RPE D9's
  expected source literal corrected `front_desk` → `qr` with the reason
  recorded in the assertion label. Every other assertion and plan(206) are
  untouched.
- Ordering integrity preserved: D10 (rows->>0 = u(422), earliest
  checked_in_at), D2 (3 tenant rows), D3–D5 zone expectations unchanged;
  423's trigger-owned checked_in_at (02:30Z) keeps it third in
  (checked_in_at,id) order.

New file sha256:
ff29bc10f29b003a5fe972d7c90c2c2d17723988590e3c49be063d95db6752f2

Static checks: check-pgtap-rollback green (no findings for this file);
plan count re-verified at 206.
