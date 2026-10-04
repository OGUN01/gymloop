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

## Runtime repair — round 6 (declaration conformance amendments, coordinator line refs)

- #63/#64 amended (declaration line 143): drill-row wants extended to the full
  declared key set — `startsAt`/`endsAt` inserted after `sessionDate` with the
  stored session instants (`2026-09-14T01:00:00Z`/`02:00:00Z`,
  `2026-09-16T01:00:00Z`/`02:00:00Z`); all counting/fraction keys unchanged.
- #67 amended (declaration line 148): the per-service rollup want is now the
  full declared `{serviceId, summary:Summary}` item — the sole cohort
  service's aggregate (service 411 owns both cohort sessions) equals the
  branch summary pinned in #62; exact-key equality subsumes the previous
  "no trainer or member identifiers" projection pin.
- #30 (OCC-012 exact February classification, the add-on order-link /
  unallocated evidence pin): runtime capture returned no got/wanted detail —
  noted here for the coordinator. The want pins, per month Feb of the wide
  range: collectedPaise "98122" = 42345 (707 first-membership money) + 50000
  (708's successor renewal) + 5000 (501's add-on via order linkage to 703) +
  777 (704 unallocated manual), returnedPaise "0", netPaise "98122";
  categories.label the derived-classification string, all four categories
  with unknownReturnPaise "0" in unallocated. The discriminator evidence the
  runtime would have revealed: whether 501's add-on linkage (addon_orders →
  payments 703) classifies under `addon` and 707's membership evidence
  (createdAt 2025-06-01 strictly earlier) classifies the Feb 2 payment as
  first-membership money. If the runtime mismatch is in any of those
  numbers, the likeliest causes are (a) the 707/708 IST-midnight boundary
  arithmetic or (b) the order-linkage derivation path — both already pinned
  independently in #30's own want and in #24/#25's evidence assertions.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `c10e74f6bacfd6b5dfe07bc796f65f6fe2f0e2328092ba37530b65c8193e29a7`.

## Runtime repair — round 7 (claims-context cluster #5/#13/#14/#15)

- Root cause (coordinator-proven via prefix probe): at section B the
  top-level claims context still held the fixture section's gym-owner
  object — subtransaction-local settings (any clear executed inside a probe's
  begin/exception block or DO wrapper) roll back with the subtransaction, so
  the gate cases judged against an empty context never saw one and the gate
  lawfully admitted the stale identity.
- Edit: the claims clear for section B is now an explicit TOP-LEVEL
  statement (`select set_config('request.jwt.claims','',true);`) placed at
  the section-B header before case #5, with a recorded reason comment.
  Section transitions audited: line-190 claim (before A) is the stale
  identity the clear supersedes; line-215's top-level gym_owner re-claim
  covers C onward; the section-J tenant-2 switch and its post-J re-claim are
  both top-level and intentional; no other wrapped-context clears exist.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `04a6e26cf9a36f43a304ea54e841dec9484144a637d2e55126684221c46d0bd2`.

## Runtime repair — round 8 (call-form amendment: explicit holiday toggle everywhere)

- Runtime fact (top-level clear + defaults-less bytes): 68 failures, the
  dominant class 42883 — the builder shipped the two-arg delegate and the
  full 4-arg form with NO boolean default, so every 3-arg call site (the
  third null relying on the old default) matched no signature and the
  guarded probes captured a signature error instead of the intended
  envelope/refusal shape.
- Amendment per the declaration's stated call forms: every 3-arg call site
  gains the explicit fourth argument — default holiday-exclusion `true`
  everywhere the scenario meant the default; toggle-off scenarios already
  passed their own. Sites amended: the two unguarded-toggle snapshot helpers
  (`pg_temp.snap`, `pg_temp.snapj` — both now call the 4-arg form with
  `true`), the six B-section gate probes, and the five C-section state calls
  (reversed range, non-Gregorian date, invalid branch zone, unknown branch,
  foreign branch). `snapx`/`snapjx` and the null-toggle pin were already
  4-arg. The previously-passing state under leaked gym-owner claims masked
  real gate behavior; regressions are re-derivable now that call forms and
  claims sequencing are both correct.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `639a42bc50478e6ab8945372de35466a612e5f450e724056b4dcbefecedf9e8b`.

## Runtime repair — round 9 (suite-side projection type bug at #28)

- Root cause (suite-side, not runtime): the #28 have-payload built
  `jsonb_build_object('allocationUnknown', r->>'allocationUnknown', ...)` —
  the `->>` TEXT extraction put the boolean's text into a jsonb STRING slot,
  so the have side always rendered `"allocationUnknown":"false"/"true"` while
  the want literal pins real JSON booleans. The runtime may already be
  correct.
- Edit: extraction switched to jsonb-preserving `r->'allocationUnknown'` —
  expectation unchanged.
- Sibling sweep (all `jsonb_build_object` fed by `->>` extractions): #21
  month/from/through/coverage are want-strings (text correct); #44's
  visit counters are want-strings per the declaration's string-typed counts
  (text correct); #60/#61 mix month/from/through/coverage strings with an
  already jsonb-preserved `m->'currencies'`. #30's evidence checks compare
  text directly (`#>>'{membershipEvidence,hasEarlierMembership}'='true'`) and
  cast timestamps — no typed slots; the add-on/unallocated evidence probe
  already uses `r->'membershipEvidence' is null` (jsonb-preserving). No
  further same-class sites exist.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `aa9185ff39cfb8481c45b298e3c7768b04f333095d75f0d2fccd71cbab7eb8f9`.

## Runtime repair — round 10 (timestamp spelling canonicalization to RFC3339 Z)

- Builder decision: the OCC envelope emits canonical RFC3339 UTC `Z` at all
  17 emission sites; the suite's wants previously mixed `Z` and `+00:00`
  spellings, which no deterministic emission could satisfy.
- Sweep results: exactly ONE non-`Z` want literal existed — #28's
  membershipEvidence createdAt embed (`2026-01-10T00:00:00+00:00`), now
  `2026-01-10T00:00:00Z`; the real-boolean `allocationUnknown` literal stays.
- Correct as-is (no amendment): the moneyRange/months/branch-range boundary
  comparisons cast the runtime-emitted text to timestamptz and compare
  instants — spelling-agnostic under either emission; drill-row
  startsAt/endsAt wants were authored directly in `Z`; no disclosure-stamp
  want literal carries a non-`Z` spelling.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `e7d3b84a2054150c0f49188a61eaa20eaf401d5efd7959366e701248949812ee`.

## Runtime repair — round 11 (seven residual pins adjudicated suite-side, zero source deltas)

Compared each pin against the coordinator's captured keys for this suite's
exact snapshot calls (`scratchpad/83-keys.txt`):

- #20 — root cause: type confusion on the PRESENT-null. KEYmr carries
  `"error": null` as a jsonb null VALUE; my conjunct `->'error' is null`
  tests SQL null and is false for a present jsonb null. Amended to
  `->'error'='null'::jsonb`. All other conjuncts verified against KEYmr by
  instant-cast (startsAt 2025-12-31T18:30Z = Jan-1 00:00 IST, cutoff ==
  endsBefore, localToday 2026-10-04 = gym_today).
- #30 — same class: KEYc703/KEYc704 carry category + `membershipEvidence`
  jsonb null exactly as pinned; `r->'membershipEvidence' is null` was false
  for the present null. Amended both conjuncts to `='null'::jsonb`.
- #39 — KEYhb11 zone/zoneSource match; the failing conjunct was the same
  present-null error test. Amended to `->'error'='null'::jsonb`.
- #49 — KEYhb13 matches all nine fields; the failing conjunct was
  `->'range' is null` on the present jsonb null. Amended to
  `=`'null'::jsonb`.
- #56 — re-planned per adjudication: the resolved selection must contain the
  asOf-derived current day; the snapshot call is now a seven-day window
  ending at the run day (`gym_today()-6 .. gym_today()`) instead of the
  single-day range. Expectations unchanged (state=current, visits=1, exact
  clock-hour arrival).
- #66 — want amended to the captured five-key drill form (identity keys plus
  startsAt/endsAt instants) with the recorded label note that capacity,
  bookings and fractions stay absent.
- #76 — the section already routes through the corrupt gym's owner claims at
  the section-J header; a defensive explicit top-level claims restatement
  (sub 905, gym_owner, tenant 2, staff 25) now sits immediately before the
  snapshot calls so the captured-call fallthrough to the valid tenant cannot
  recur.
- #28's spelling canonicalization was completed in round 10.

No test weakening anywhere; each amendment preserves (or strengthens) the
declaration pin. plan(77) preserved (77 verified); rollback guard green (159
files). SQL NOT executed here.
- New sha256: `d55452609d73f95ef3a3023966aa51100031ad78818f59e743d6efea4cf3b973`.

## Runtime repair — round 12 (three residual pins)

- #49 — re-walked every conjunct against the captured branch-13 entry: the
  remaining false conjunct was `->'week' is null` — the captured entry
  carries `"week": null` as a PRESENT jsonb null, so `is null` is the same
  type-confusion class rounds 11 fixed elsewhere. Amended to
  `->'week'='null'::jsonb`. Every other field verified: zone text preserved,
  zoneSource branch, error {code invalid_branch_timezone}, range present
  null, totalVisits/excludedVisits/availability SQL-null through `->>`,
  days and cells both empty.
- #56 — the seven-day window does include gym_today() at runtime
  (gym-local date arithmetic on `date`, asOf-tz = Kolkata run day), so the
  window is fine; the suspect conjunct was the one I could break statically:
  the disclosed hour was compared against `extract(hour from now())` at
  ASSERTION time while the fixture insert ran at its own instant — an hour
  rollover between insert and assertion makes the pin fail without any
  envelope defect. Amended to derive the expected hour from the STORED
  check-in instant (row 616's checked_in_at), so the pin is the recorded
  arrival's own clock hour — stronger, not weaker.
- #76 — coordinator: request fresh runtime key dumps. Specifically: (a)
  KEYzone76 — the top-level `{zone, moneyRange.scope, moneyRange.error,
  months, collection}` of the `('2026-01-01','2026-03-31',null)` snapshot
  executed under the tenant-2 owner claims as my round-11 restatement now
  establishes them (the earlier "hit the valid tenant" capture predated
  that restatement and cannot represent it); and (b) KEYtoday7 — the
  seven-day window (`gym_today()-6 .. gym_today()`) branch-11 today entry
  (state/visits/hours) confirming the resolved selection contains the
  asOf-derived current day. With those two dumps #76's and #56's remaining
  conjuncts are adjudicable without another full run.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `9ff18cf6f25fa4d2fc60ded84b7ff0f64cc39fa8d6ee8709c2c964ba074d3ff6`.

## Runtime repair — round 13 (today arrival restaged as lawful QR; #76 routing pinned)

- #56 fixture: the today arrival (616) was a `front_desk` row staged before the
  Sep window — the capture showed today's visits 0 because that row's provenance
  chain was the desk path, not a member-gate self check-in. Restaged: 616 is
  now staged in its own insert under the member's own claims context
  (sub 911, member 101, tenant 1) with `source='qr'` and no staff/reason — the
  settled member-gate provenance (suite 06 precedent: a QR check-in needs
  neither). checked_in_at stays `now()`, so the round-12 stored-instant hour
  derivation still pins the recorded arrival's own clock hour. Sep-window
  counts and holiday/eligible-date arithmetic are untouched (the row lives in
  the today window only).
- #76: per adjudication, the routing itself is now pinned inside the existing
  assertion as its FIRST conjunct — the exact tenant-2 owner claims object
  (sub 905, gym_owner, tenant 2, staff 25) must equal
  `current_setting('request.jwt.claims',true)` at execution — and the claims
  are restated at top level immediately before the call. If the snapshot still
  resolves the valid tenant under those claims, the pin now fails naming the
  routing context rather than silently, and the KEYzone76-style capture gains
  a decisive diagnostic: the captured `request.jwt.claims` value itself proves
  whether the fallthrough is a claims-context artifact of the capture harness
  or a real tenant-derivation defect in the RPC (which would then be a public
  contract finding, not a suite edit).
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `066cc6ca1f027ceeb5abd4d098c4301d4c7c5f6101b77fd780e430b37d78ce8e`.

## Runtime repair — round 14 (exact trigger condition mirrored)

- Trigger condition (coordinator): a member claims-context insert refuses
  unless `source='qr' AND qr_session_id is not null AND assist_reason is null
  AND assisted_by_staff_id is null AND membership_id is null`. The round-13
  bare-QR row failed precisely on the missing live session.
- Staging now mirrors the settled lawful shape word-for-word (suite-82
  "pure member gate replay"): `organization_settings` gains
  `checkin_gate_mode='rotating_screen'` for tenant 1; a live `qr_sessions`
  row (440, tenant 1, branch 11, rotating_screen, statement-window validity)
  is staged under postgres with cleared claims; the attendance row (616) is
  recorded under the member's own claims (sub 911, member_id 101) with
  `source='qr'`, `qr_session_id=440`, `client_event_id=460`,
  `offline_recorded_at=statement_timestamp()` — membership_id, staff and
  reason all absent, checked_in_at and replayed_at owned by the trigger.
- Context hygiene: the settings/session inserts run as postgres with cleared
  claims (no stale tenant-2 owner context); the doubled role switch tidied.
  plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `d6b884e25699c206f67458e044b9391e33dd194d92d28743a567c4eb97a82bed`.

## Runtime repair — round 15 (GL010 root: front-office-only RLS on qr_sessions)

- Root cause: the attendance trigger is SECURITY INVOKER
  (20260908081957), so its qr_sessions SELECT runs under the caller's RLS —
  and `qr_sessions_tenant_select` grants read to front office only. A member
  claims context is structurally blind to the session row, so every direct
  member-context INSERT-with-session staging can only ever see GL010
  "QR session is unavailable". The suite-82 rows-430 shape was never proven
  to pass this guard: its own run aborted earlier in the same staging region
  ("offline replay requires a member gate event").
- Repair — the staging now uses the production member gate-scan path:
  `public.member_mobile_check_in('<64-hex token hash of the live session>',
  client_event_id 460, statement_timestamp())` under the member's own claims
  (sub 911, member 101, tenant 1). The definer
  (`app.record_member_mobile_check_in`) resolves the live session BY TOKEN
  HASH with RLS bypassed, inserts with trigger-owned checked_in_at/replayed_at,
  and the returned row is captured into `occ_today_arrival`. The member RPC
  requires an active linked member (101's user 911, active membership 301) —
  satisfied.
- #56's hour derivation re-pointed to the captured RPC row
  (`occ_today_arrival.checked_in_at`), keeping the stored-instant pin; the
  direct attendance-616 lookup is gone along with the un-guardable direct
  insert. plan(77) preserved (77 verified); rollback guard green (159 files).
  SQL NOT executed here.
- New sha256: `ab2f401ffbb7f570055cd3e647ae85ec615d2d0e813a01d8028687a187817be7`.

## Runtime repair — round 16 (member identity binding)

- Root cause: the gate-scan RPC resolves identity through the claims' sub →
  members.user_id binding; my member claims used sub …911 while member 101's
  fixture binding is user …906 — the same binding the suite's own member-gate
  refusal pin already used. The RPC refused with "Member command requires an
  active linked member".
- Edit: the staging claims context now uses sub …906 (member 101's actual
  linked user); status/active and the auth.users row already exist. No
  assertion touched; plan(77) preserved; rollback guard green (159 files).
SQL NOT executed here.
- New sha256: `ce4a0b0fcbc2504e242b5fa9483af3caa7d96be339fa072c0eef08e4e4ddb7fc`.

## Runtime repair — round 17 (owner-binding routing for the corrupt gym; #56 hour confirmation)

- #56 answer (coordinator question): yes — the pin derives the disclosed hour
  from `occ_today_arrival.checked_in_at`, the exact instant the gate-scan RPC
  stamped, and the snapshot day-row's hours carry arrivals from that same
  recorded instant; both sides derive the identical value (15 in the
  captured run). Additional rollover hazards are structurally excluded:
  `gym_today()`, the fixture `now()`/`statement_timestamp()` stamps and the
  snapshot's own asOf/cutoff all evaluate inside one transaction, so no
  midnight/hour flip can separate fixture time from assertion time. If the
  pin still fails with hour 15 on both sides, the residual difference is
  runtime-vs-fixture elsewhere and a targeted K capture will name it.
- #76 — adjudication option (a) implemented: the corrupt gym's zone is now
  reached through an OWNED tenant-2 owner binding. New fixture staff row 26
  (tenant 2, branch 14, gym_owner, user 916 — within the staged auth.users
  901..916 series, unbound elsewhere), and section J's claims route through
  that identity (sub 916, staff 26, tenant 2). Every lawful resolution path
  — claims tenant_id, staff binding, or owned tenant — now lands on
  organizations …2. The routing-precondition conjunct and the per-call
  top-level restatement were updated to the same identity.
- Decisive K captures requested for the next runtime round:
  K1 — in-transaction `select timezone from public.organizations where
  id=pg_temp.u(2)` evaluated immediately before the #76 snapshot call
  (proves the corruption seam took: expect `Mars/Phobos`); K2 — the
  snapshot's top-level `zone` (and `moneyRange.error`) under the new
  owner-bound claims. If K1 shows `Mars/Phobos` and K2 still resolves
  `Asia/Kolkata`, the envelope's gym-zone state sourcing reads a row other
  than the actor-resolved organizations row — a public contract finding
  (source delta), not a suite edit.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `4cce6417449e1198a47eebbadee960aab0b885bdef8d27ef92d66fa482c03f32`.

## Round 18 — #76 closure adjudication (coordinator K data)

- K1: `organizations…2.timezone = Mars/Phobos` in-transaction immediately
  before the pin call — the corruption seam took. K2: the claims context at
  the call is exactly the routed tenant-2 owner identity (sub 916, staff 26,
  tenant_id …2) — the routing-precondition conjunct passes. K3: the snapshot
  STILL returned `zone = Asia/Kolkata` with `moneyRange.error = null` — under
  a tenant-2 owner whose staff binding lives in tenant 2 and a tenant-2
  stored corrupt zone.
- Classification per the round-17 split: PUBLIC CONTRACT FINDING. The
  analytics envelope's gym-zone/tenant state-source does not follow the
  tenant resolved from the verified actor context — under BOTH plausible
  resolution paths (claims tenant_id; staff-join tenant) the resolved row is
  organizations …2, so returning tenant …0001's zone proves the envelope
  reads a different row/state (member-link, GUC ordering, or a stable
  app-level tenant picker that mis-resolves). Held as the builder's item:
  relocate the sourcing to the actor-resolved tenant.
- Pin #76 stays as authored: its first conjunct (exact claims equality)
  remains valid routing proof; the residual failure is genuine downstream
  divergence, not a suite defect. No further suite edits for #76.
- Remaining open item: #56 residual — awaiting the coordinator's targeted
  capture of (a) the snapshot's branch-11 today day-row
  (`state`, `visits`, the hours array around hour 15) under the same
  seven-day window with the gate-scan row present, and (b) in-tx
  `select checked_in_at, extract(hour from checked_in_at at time zone
  'Asia/Kolkata') from occ_today_arrival` — if both name hour 15 and the day
  row's hour-15 cell is not `visits='1'`, the divergence is in the heatmap
  population's day/hour bucketing state source, which may fold into the same
  round-18 tenant/actor sourcing finding.

## Round 19 — rollback-theory verification (builder diagnosis)

- Static verification: every #76 claims statement is a TOP-LEVEL `select`
  (the section-header `pg_temp.claim`, the defensive re-assertion, and the
  per-call `set_config`) — no probe/DO wrapper encloses any of them, so the
  subtransaction-rollback mechanism cannot apply to this suite's own bytes.
  Moreover the #76 assertion itself already ran the claims read and the
  snapshot call in ONE statement: had a rollback cleared the claims, the
  FIRST conjunct (exact claims-object equality with `current_setting`) would
  be false — the recorded failure mode (routing conjunct passes, zone wrong)
  contradicts the rollback theory for my suite's own execution.
- Strengthening per the coordinator's specified verification: the pin now
  leads with the RAW one-statement echo —
  `current_setting('request.jwt.claims',true)::jsonb->>'tenant_id' =
  pg_temp.u(2)::text` — before the exact-object equality conjunct, so the
  live settings at the same execution context as the `pg_temp.snapj` call
  are named directly. If a rerun still shows tenant-2 echoed and
  Asia/Kolkata returned in that single statement, the builder's derivation
  theory is falsified in-suite and the packet goes to the owner as a
  derivation defect. If instead the echo fails, the wrapper lives in the
  capture harness that re-executes this region, not in the suite.
- plan(77) preserved (77 verified); rollback guard green (159 files). SQL NOT
  executed here.
- New sha256: `499d7497265c6073d91c325c971af5b6607596991190c813fedc7e1661e114ff`.

## Round 20 — observability split (both directions)

- #76 (direction a): the routing echo is now its own `select is(...)` —
  have = the live `current_setting('request.jwt.claims',true)::jsonb->>'tenant_id'`
  read in the same statement context as the snapshot call, want = the corrupt
  gym's id — so the TAP shows the echo's own pass/fail, separated from the
  envelope zone assertion (which keeps every envelope conjunct as ok()).
  If the echo pin is green while the zone pin is red, the claims context at
  execution is provably tenant-2 and the failure is downstream derivation
  (owner packet); if the echo pin itself is red, the wrapper lives in the
  executing harness, not the suite.
- #56 (direction b): split into three `is()` pins with visible have/want —
  #56a today-day state, #56b today-day visits ('1'), #56c the recorded
  clock-hour cell ('1'). Branch identity is already proven lawful: the
  gate-scan row's branch is the live session's branch (…11) — the same
  branch the heatmap exposes (KEYhb11/KEYhb13 branchId …11) — so a zero
  in #56b/#56c with a green #56a names the day/hour bucketing state source
  as the residual divergence, folding toward the builder's tenant/actor
  sourcing packet.
- Plan literal follows the assertion count exactly: plan(79) = 47 is + 32 ok
  (the three #56 pins and one #76 echo pin are additions; every prior
  expectation is preserved verbatim in the split pins). Rollback guard green
  (159 files). SQL NOT executed here.
- New sha256: `1425d779710e0d5253ee4e6110ad94478ddedb158c230ad4ed293fb8a066ece5`.

## Round 21 — split-pin results and the in-invocation coupling

- Split results (coordinator runtime): #56a GREEN (today day row state
  current); #56b/#56c RED with `have: 0` while `occ_today_arrival` proves the
  arrival exists. Per the builder's correction the Day shape carries NO
  state filter and NO separate today key — `days[].visits` (counts all
  accepted arrivals before asOf, including today), `hours[].visits` (sums to
  the day total) and `cells[].todayArrivals` are exactly what my pins read.
  So the residual is genuine aggregation divergence: the recorded instant is
  not bucketing into the today day row/hour cell — same state-sourcing
  family as the #76 finding, routed to the builder packet. #56 stays as
  authored (all three pins; no nonexistent keys).
- #76: the split echo came back RED — the in-statement `current_setting`
  read shows NOT the corrupt gym's tenant. My suite's own bytes set the
  claims in an unambiguous top-level statement immediately before it, which
  at raw-statement execution cannot roll back — so the remaining live
  mechanism is statement-level isolation in the executing harness (the same
  signature as the builder's "set_config inside a subtransaction", but
  located at the runner, not the suite source). To make the pin independent
  of ANY statement isolation: `pg_temp.zone76()` now sets the tenant-2 owner
  claims and calls the analytics RPC inside ONE plain plpgsql invocation (a
  plain body is not a subtransaction, so the local setting survives within
  it), capturing `{ctxTenant, snapshot}` into `zone76_capture`. The #76 ok()
  asserts ctxTenant = tenant …2 at the exact point of resolution AND the
  same envelope expectations on the captured snapshot. If ctxTenant is
  green and the snapshot zone is still tenant …0001's, the derivation
  defect is proven in-suite and the owner packet is warranted; if ctxTenant
  is red inside the invocation too, the isolation lives even below function
  scope and the harness itself is the finding.
- The standalone top-level claims routing and the echo is() remain in place
  as the harness-behavior probe. plan(79) unchanged (no assertion count
  change; helper and capture are fixture plumbing). Rollback guard green
  (159 files). SQL NOT executed here.
- New sha256: `b0567f9c3cab17f35ff0d8d17696b03e8cbc23c44b587998622a4144ffcb7ee6`.
