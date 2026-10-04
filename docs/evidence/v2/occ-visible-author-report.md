# OCC visible author report — suite 83 repair (2026-10-04)

Independent blind visible pgTAP author for occupancy/collection/class-fill
analytics. Authority read: `openspec/changes/occupancy-analytics/proposal.md`
(FROZEN 2026-10-03), `openspec/changes/occupancy-analytics/sql-envelope-declaration.md`
(FROZEN 2026-10-04, authoritative mechanical envelope), `docs/design/v2/occ-bar.md`,
`supabase/tests/83_occupancy_analytics.sql` (owned suite), and one older visible
suite for TAP conventions. The implementing migration, holdout, evidence and
scratchpad files were never opened.

## Suite state

- File: `supabase/tests/83_occupancy_analytics.sql`, rewritten against the
  frozen envelope.
- sha256: `ac5439e9453c46d3a143d9ee2fad7bd9f0fd76de6e9648327b442dcddab4c3d2`
- plan(77) = 77 `select is(...)`/`select ok(...)` statements (verified by grep:
  44 is + 33 ok), one lowercase `begin;`/`rollback;` pair, one
  `select * from finish();`, zero PERFORM TAP, SETOF-text TAP convention kept,
  fixture prefix convention kept. `check-pgtap-rollback` green (157 files).
- NOT executed against Cloud SQL; no commits made. Actual RED belongs to the
  primary's Cloud rollback preview, as commissioned.

## What changed and why (remap, not removal)

The dirty 83 file pinned the earlier loader-era key shapes. The frozen
envelope supersedes them; every business fact the old assertions carried is
re-expressed against the envelope keys. Old-key → new-key mapping applied:

| Old pinned shape | New envelope pin |
|---|---|
| top-level `heatmap.zone/zoneSource` | `zone` (top) + per-branch `zone/zoneSource/error` |
| `heatmap.eligibleDateCount` | per-cell/per-week `eligibleDates` (13 with holiday exclusion, 14 without) |
| `heatmap.excludedDates` array | day rows `isHoliday/excluded/visits` + branch `excludedVisits` |
| `heatmap.arrivalDays` | `days[]` with `state` and `hours[]` (0..23, `exists`) |
| `heatmap.cells` partial list | all 168 coordinates, exact `{weekday,hour,arrivals,todayArrivals,eligibleDates,fraction,limited,message}` |
| string fractions `"0.2500…"` | exact `{numerator,denominator,basisPoints}` triples, half-up `floor((2n*10000+d)/(2d))` |
| month `classification` object | `categories` `{label,newMember,renewal,addon,unallocated}` with `unknownReturnPaise` in unallocated only |
| single `classes` summary object | `classes.branches[]` + `reconciliation`, per-service and per-session drill rows |
| absent | new pins: `range` echo, `moneyRange`, `collection` (currencies + components Receipts/Returns), `warnings.totals`, month `coverage`, `alignment`, invalid-gym-zone envelope, today/future month states, cash invariance under branch selector and toggle |

Lawfulness repairs (per directive):

- No fixture touches a protected timestamp and no constraint is disabled. The
  offline front-desk check-in provenance concern is addressed by pinning the
  envelope rule directly: only recorded `branch_id`/`checked_in_at` selects
  visits (assertion via exact cell/day arithmetic; the fixtures use the
  guarded front-desk insert path as before).
- The old today-section assertion `noEligibleDays=true` contradicted the
  frozen envelope's new definition (noEligibleDays iff some nonfuture date
  exists and ALL nonfuture dates are excluded — today is current and not
  excluded, so it is `false`). Remapped to assertions 56/57: zero-denominator
  fraction with null basis points, "Limited history" current-only message,
  `availability=partial`. The old business truth (today is not a completed
  exposure) is preserved by those pins.

## RED expectation mapping (honest, unexecuted)

The implementing migration is known-incomplete against the frozen envelope
(four runtime fixes only; complete envelope unbuilt). Expected against the
current source:

- Likely already green (shape-independent): A 1–4 (4-arg signature, jsonb
  scalar, invoker/grants — the old suite pinned the same), B 5–10 (actor
  refusals), C 11–15 (value/branch refusals), I 71–72 (owner_metrics seam),
  34 (foreign-money absence).
- Expected RED (new-shape or new-semantics pins): 16 (null toggle invalid),
  17–33, 35 (months/collection/moneyRange/warnings exact shapes), 36–54
  (heatmap branch arrays, days/hours, cells, fractions, reconciliation),
  55–60 (today/current-month/future-month states), 61–70 (classes branches,
  drill rows, zero-cohort summary, reconciliation), 73–76 (toggle-off
  denominators, cash invariance), and J 75–76 unless the invalid-gym-zone
  envelope already exists.
- Expected RED ≈ 60 of 77; exact split is established by the primary's Cloud
  rollback preview, not by this author.

## Assumptions flagged (contract round-trips, not invented requirements)

1. `unknownReturnPaise` is pinned ALWAYS present on the unallocated category
   (envelope: "a separate unknownReturnPaise field in that category only").
   If the implementer emits it only when nonzero, that is a contract-defect
   round-trip, not a test edit.
2. A branch-selected call pins exactly ONE entry in `heatmap.branches` and
   `classes.branches` (population = the selected visible branch). If the
   envelope intends all visible branches in every call, that is a round-trip.
3. A branch inheriting an invalid gym zone pins `zone` = the invalid gym-zone
   text with `zoneSource:"gym"` and error `{code:"invalid_gym_timezone"}`.
4. Zero-cohort branch summary is nonnull with zero strings and null basis
   points (only invalid/future-only branches get null summary), message
   "Limited history" because 0 < 10.
5. Timestamps are compared as instants (`::timestamptz`), never as spelling —
   the envelope requires RFC3339 instants without pinning one spelling.
6. Foreign gym (org 2) fixture timezone changed from `Asia/Kolkata` to
   `Mars/Phobos` to exercise the invalid-gym-zone envelope lawfully; foreign
   refusal assertions are unaffected (P0002 precedes zone resolution).

## Runtime repair — round 2 (first Cloud diagnostic, current snapshot)

- Runtime fact: suite aborted pre-plan with `ERROR: 22023: Invalid platform input`
  (organizations INSERT). Trace: the `organizations_commercial_invariant`
  trigger (20260915100009_phase6_platform.sql) validates `timezone` against
  `pg_catalog.pg_timezone_names` on INSERT for every writer — the fixture's
  foreign gym row carried the corruption zone `Mars/Phobos` directly.
- Root cause: authoring bug. The invalid-gym-zone envelope (zoneSource='gym',
  `invalid_gym_timezone`) is unreachable through any lawful write path; it
  requires registered corruption. The suite already carried the registered
  disable/restore seam concept, but the disable statements sat misplaced
  (post-fixture, unpaired) instead of around the corruption insert.
- Edit (assertions untouched, plan(77) preserved, 77 top-level assertions
  grep-verified): moved a single disable/restore pair around the
  organizations INSERT — trigger disabled, both org rows inserted, trigger
  re-enabled immediately, before every application check. Branch u(13) keeps
  its invalid zone naturally (branches carry no zone trigger); branch u(14)
  inherits the corrupted gym zone through the restored-after-write row.
- Static: `check-pgtap-rollback` 157 files green. SQL NOT executed here.
- New sha256: `e666095c162fdf881a23aeff16895940228b53b343eec811530613097c062368`.

## Runtime repair — round 3 (second Cloud diagnostic, current snapshot)

- Runtime fact: after the round-2 org-insert fix, the suite aborted later with
  the raw `ERROR: 22023: time zone "Mars/Phobos" not recognized`. Diagnosis
  (no implementation reads; legacy public migrations only): the foreign gym's
  tenant-2 fixture writes (membership 306, attendance 617, payment 760) run
  through legacy business triggers (check-in liveness, manual payment,
  membership periods) that resolve the gym zone at WRITE time
  (`(now() at time zone <gym zone>)`) — with org 2 corrupted at INSERT, the
  attendance insert aborted outside any guard.
- Repair (lawful fixture alternative, per the seam's own design): the foreign
  gym now INSERTS with a valid zone (`UTC`), every tenant-2 fixture write
  proceeds through normal business triggers, and the registered
  disable/restore seam moves to AFTER the last fixture write as a single
  guarded UPDATE to `Mars/Phobos` (trigger disabled for the UPDATE only,
  restored immediately). Every application check runs with the trigger
  enabled. Assertions untouched; plan(77) preserved (77 top-level assertions
  grep-verified).
- Static: `check-pgtap-rollback` 159 files green. SQL NOT executed here.
- New sha256: `6564df0d78eb9d359a9aafa34506432b28ac017af3f0c7ea524c89ed550909c6`.

## Runtime repair — round 4 (third Cloud diagnostic, current snapshot)

- Runtime fact: suite aborted with `ERROR: 42883: operator does not exist:
  jsonb !~~ unknown` — the OCC-009 non-arrived-attempt assertion (line ~273).
- Root cause: operator-precedence bug, not an expectation defect. In
  `pg_temp.snapj(...)->'months'::text not like ...` the `::text` cast binds to
  the KEY LITERAL ('months'), the `->` operator still returns jsonb, and
  `!~~` has no jsonb operand. Line 269 was already correct
  (`snapj(...)::text` — the whole value cast).
- Edit: parenthesized both extraction operands —
  `(pg_temp.snapj(...)->'months')::text not like '%25000%'` and the same for
  `->'collection'`; expectation unchanged. Sweep for the sibling pattern
  (`)->'key'::text` / `)->>'key'::text` across the suite) found no other
  occurrence. plan(77) preserved (77 verified); rollback guard green (159
  files). SQL NOT executed here.
- New sha256: `82ce4bbe62eeeb3d5fb2ee59dfb5eb304837bb87f17f89e50569ca4d118f2796`.

## Runtime repair — round 5 (coordinator adjudication: unreachable completed/undated return)

- Adjudication: runtime evidence shows a completed refund with null
  processed_at is UNREACHABLE — the phase6 addon-sales refund guard stamps
  processed_at on every insert/update to `completed` (and nulls it on
  un-completion) on every path; the coordinator probed fixture 803 mid-suite
  (row exists, processed_at auto-stamped to transaction time) and the RPC's
  undatedReturns population correctly excludes it. The former #32 pin (exact
  one-row undatedReturns column) demanded an impossible state.
- Amendment (recorded reason in the assertion label; per the adjudication
  note in openspec/changes/occupancy-analytics/sql-envelope-declaration.md,
  warnings section):
  - #32 rewritten as `ok(...)`: the coupled invariant pinned directly —
    staged 803 carries a non-null processed_at, every staged completed refund
    for the tenant carries a non-null processed_at, and the snapshot's
    `undatedReturns` is `[]` under lawful staging.
  - #33 totals amended: `undatedReturnCount` "0" / `undatedReturnPaise" "0"`;
    the totals-sum-exclusively-from-arrays discipline and the scope
    disclosure pin both stay (the empty array still sums to exact zero
    totals).
  - Fixture comment corrected (803 stays a staged completed refund; its
    stamp is now documented as invariant-driven).
- Attendance staging provenance (round 2) untouched per coordinator note.
  plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `1135c79633e204c38197135b3baec91fb8c9e21cfdd9f3b7cc82be3d681f3d6a`.
