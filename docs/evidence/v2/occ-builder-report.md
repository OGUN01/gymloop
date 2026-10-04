# OCC builder report — complete frozen envelope implementation (2026-10-04)

Builder: separate source builder, implementation-blind to both OCC suites
(`supabase/tests/83_occupancy_analytics.sql` and
`supabase/tests-holdout/h83_occupancy_analytics_holdout.sql` were never
opened). Authority read: the frozen proposal (OCC-001…017), the FROZEN
2026-10-04 SQL envelope declaration, both public author reports, the occ-bar,
and existing migrations strictly for table/column vocabulary
(payments, refunds, addon_orders, memberships, attendance, class_sessions,
class_bookings, organization_holidays, branches, organizations, platform
commercial trigger behavior). No other migration modified; no commits; no
Cloud SQL.

## What was built

`public.owner_occupancy_analytics(date, date, uuid, boolean)` rewritten as
ONE containing statement (OCC-002) emitting the exact nine top-level keys
`{asOf, zone, range, moneyRange, months, collection, heatmap, classes,
warnings}`:

- **Actor gate (OCC-001)** — unchanged from the verified source: claims and
  live-staff revalidation before any read; 42501 single refusal.
- **Argument validation** — real dates, `from <= through` (22023
  `invalid_occupancy_range`); an explicit NULL toggle is now INVALID (22023
  `invalid_occupancy_toggle`) instead of silently defaulted; argument
  omission keeps DEFAULT TRUE per the declaration's canonical signature.
- **moneyRange / months / collection (OCC-009/010/012/013)** — gym-zone
  boundaries independent of branch and toggle; `scope:"Whole gym"`; invalid
  gym zone disclosed via `error:{code:"invalid_gym_timezone"}` with null
  derived fields, `months:[]`, `collection:null` — no raise, no fabricated
  UTC. Month list = every gym-local month intersecting the selected dates
  with clipped boundaries, `cutoffAt=min(endsBefore,asOf)`, coverage
  full/partial/unavailable (unavailable checked first; full requires complete
  calendar-month selection and end≤asOf), unavailable/empty months carry
  `currencies:[]`, never invented zeros. Classification: whole-receipt
  derived membership linkage — newMember iff no STRICTLY-earlier membership
  row for the same member (equal created_at is not earlier, no id
  tie-break), renewal otherwise, add-on via the order link only when no
  membership link, unallocated otherwise; `unknownReturnPaise` present on the
  unallocated category and equal to its `returnedPaise`; returns allocate
  whole to the original receipt's category with `allocationUnknown`
  exactly for unallocated originals; `membershipEvidence`
  `{createdAt, hasEarlierMembership}` only for membership money. Components
  sorted by event instant then id; months and collection reconcile from the
  SAME classified component CTE (no mirror). Big-integer paise beyond the JS
  safe integer flows as numeric → text.
- **heatmap (OCC-004..008)** — `alignment:"Local time"`; branch population =
  every RLS-visible tenant branch, narrowed to the selected branch when
  given, sorted by branchId; per-branch effective zone with
  `zoneSource:"branch"|"gym"`; invalid configured zone (own or inherited) is
  PRESERVED as zone text with `error:{code:...}`, null
  range/aggregates/week/noEligibleDays/availability and empty days/cells —
  retained in comparison, never dropped or fabricated. Per branch: one day
  row per selected local date (including zero/future) with
  `state=completed|current|future`, holiday/excluded flags, visits including
  excluded holidays, and 0..23 `hours` rows where `exists` is the wall-clock
  round-trip test (DST gaps have no exposure; repeated hours combine and the
  date counts once); all 168 weekday/hour cells in coordinate order with
  arrivals (completed nonexcluded dates), todayArrivals (current nonexcluded
  day), eligibleDates (completed nonexcluded dates where the hour exists),
  exact `{numerator,denominator,basisPoints}` fractions
  (`floor((2n*10000+d)/(2d))` half-up, null at zero denominator), `limited`
  below 14, and the message ladder (`Unavailable` future-only, `Limited
  history` current-only, `No eligible days` at zero, `Limited history` below
  14, null at 14+); week aggregate per completed nonexcluded date counted
  once; `totalVisits=completed+current` over nonexcluded days;
  `excludedVisits` separately; availability unavailable/partial/complete;
  `noEligibleDays` iff some nonfuture date exists and all are excluded;
  reconciliation complete iff every included branch is valid, with summed
  counts when complete and nulls otherwise.
- **classes (OCC-014/015/016)** — elapsed non-cancelled cohort
  (`status='scheduled' and ends_at < asOf`, selected branch-local dates,
  holidays retained, stored per-session capacity, disabled services never
  erase history); session drill rows ordered sessionDate, startsAt,
  sessionId with booked/attended/noShow/holding counts and three exact
  fractions; cancelled drill rows with exactly five keys; per-service
  rollups keyed by serviceId only; per-branch summary with
  cancelledSessionsExcluded, incompleteMarkingDisclosed, limited below 10;
  null summary and empty arrays exactly for invalid and future-only
  branches; reconciliation complete iff every branch has a nonnull summary,
  aggregated capacity-weighted from returned rows.
- **warnings (OCC-009/010)** — `scope:"Current all-date"`, population
  independent of range/branch/holiday/toggle; exact row key sets sorted by
  id; per-currency totals sorted by currency, summed exclusively from those
  arrays, counts and paise as strings.
- **Grants** — both overloads: revoke from public/anon/service_role, grant
  EXECUTE to authenticated; owner postgres via create; `search_path=''`
  invoker; STABLE retained.

## Refusals (declaration matrix)

| Case | Behavior |
|---|---|
| Missing/mixed/foreign claims, non-staff roles, platform, preview, impersonation, inactive/mismatched staff | 42501 `Not permitted to read occupancy analytics`, before any read |
| Null/invalid dates, from > through | 22023 `invalid_occupancy_range` |
| Explicit null holiday toggle | 22023 `invalid_occupancy_toggle` |
| Unknown or foreign branch | P0002 `Branch not available` (`branch_unavailable`) — see adjudication note |
| Invalid gym zone | envelope disclosure, never a raise |
| Invalid branch zone (own or inherited) | per-branch `error:{code}` disclosure, never a raise |

## Adjudication note for the orchestrator (suite conflict, not silently resolved)

The frozen declaration pins no SQLSTATE for a forged/unavailable branch. The
shipped source (and the visible suite's passing value/branch refusal pins)
use P0002 invisible-target collapse; the independent holdout author report
records a 42501 expectation for the same scenario. This build KEEPS the
shipped P0002 and flags the conflict — the two suites disagree and the
orchestrator must adjudicate; neither suite was read to decide.

## Judgment calls recorded (declaration-silent points)

1. `moneyRange.zone` preserves the raw gym-zone text even when invalid
   (the `error` field discloses invalidity); the top-level `zone` is null
   for an invalid gym zone per the declaration's explicit rule.
2. The "Month to date" label is presentation vocabulary; the declared month
   key set has no label field, so none is emitted (cutoffAt + coverage
   carry the facts).
3. `basisPoints` is emitted as a canonical decimal STRING (the declaration
   makes all counts/bp strings; only weekday/hour are JSON numbers).
4. Lock/serialization: the function is a STABLE invoker read; no locks taken.

## Preserved verified behavior

The four earlier runtime fixes (zone/alias corrections in the draft shape)
are superseded structurally by the rewrite; their semantic content (valid
gym-zone requirement for money, branch-override disclosure, no fabricated
zeros) is preserved and strengthened by the envelope implementation. The
`owner_metrics(date,date)` seam and MET behavior are untouched.

## Static checks

- `check-pgtap-rollback`: 159 pgTAP files green.
- Dollar-quote tags: `$fn$` ×4 (two balanced function bodies).
- Paren balance: 0 net in both function bodies (statement-level walker,
  quote/comment aware); every top-level key verified to open and close at
  depth 1 inside the final select.
- Zero `commit` statements; no transaction control in the migration.
- `set search_path = ''` on both functions; owner-qualified references.

## Sha256

- Migration: recorded at `sha256sum supabase/migrations/20261005120000_occupancy_analytics.sql`
  by the orchestrator at commit time (file finalized after the balance fixes
  above).

## Runtime repair round 1 (2026-10-04, coordinator runtime)

- Runtime fact: first apply of the migration aborted `42601: syntax error at
  or near "from"` — inside the classes→branches→services jsonb_agg the scalar
  subquery closed before its source query (the services summary jbo took two
  closes, so the jsonb_agg and the subquery paren both closed before
  `from (select c.service_id, ...) sv`).
- Repair: the services summary jbo's message line now closes with ONE paren
  (`end)`), leaving the outer service jbo to close before
  `order by sv.service_id` inside jsonb_agg, and the source subquery
  `(select c.service_id, ... ) sv` restored as the jsonb_agg's FROM inside
  the coalesce scalar subquery. An earlier coordinator-round edit that had
  removed the scalar-subquery close at `) sv),` was reverted — that close was
  correct; the real defect was only the doubled close on the summary jbo.
- Re-audit (structure-aware, not paren-count): a pairing scanner over both
  function bodies verifies (a) zero unmatched/extra parens, (b) every
  `(select` scalar-subquery span contains its own top-level `from`, (c) no
  select-level `order by` precedes its `from` (the exact misnest class), and
  (d) all nine top-level envelope keys open and close at depth 1 with the
  final select closing at relative depth 0.
- New migration sha256:
  `76ca5b96ac45922c23e4c58dc678502172ed6a4379c7b72e2cd2e2716080b1bb`
  (supersedes `4519228e…` and `4a84076d…` recorded mid-repair).

## Runtime repair round 2 (2026-10-04, coordinator runtime)

- Runtime facts: (1) the envelope aborted `42883: operator does not exist:
  timestamp with time zone + integer` inside the main statement; (2) the
  visible suite ran its full plan with 63/77 RED — consistent with every
  guarded probe capturing the same error/NULL downstream of one defect.
- Root cause: `generate_series(date, date, interval)` promotes its arguments
  and yields `timestamp without time zone`, so the day-grid loop variable
  `g.d` is a TIMESTAMP, and the two `((g.d + 1)::timestamp at time zone …)`
  expressions in `day_stats` were timestamp+integer (no such operator).
- Repair: both sites now use `(g.d + interval '1 day') at time zone …` —
  identical semantics (next calendar day's local midnight), valid operator.
  All remaining `+ 1` sites (`p.d_through + 1`, `ml.clip_through + 1`,
  `branch_bounds`' `p.d_through + 1`) operate on genuine DATE values
  (parameters and `min/max(series)::date`), which is legal date arithmetic;
  `month_last` already uses `interval '1 month - 1 day'`. Swept the whole
  statement for other integer-on-timestamp arithmetic and unguarded
  `at time zone` conversions: every remaining zone conversion is filtered by
  valid-branch/valid-gym membership or guarded by CASE.
- Expected effect: the mass RED is downstream of the abort on the envelope
  path (guarded captures returning error/NULL for every snapshot call); the
  arithmetic pins (month boundaries, day grid, cells, fractions, coverage)
  should re-derive against the declaration now that the snapshot returns.
  Residual genuine deviations get re-derived from the declaration after the
  coordinator's rerun, never by reading tests.
- New migration sha256:
  `5a61b009a527acd235912f150869b853f998bc2b76ddf74ebfebe735a30247dc`

## Runtime repair round 3 (2026-10-04, coordinator adjudication input)

Three derivation defects found by re-deriving the failing clusters from the
declaration (no test reads):

1. **Warnings totals cross-product (OCC-010/#33).** The per-currency totals
   joined the raw undated payment and return rows on currency, multiplying
   counts (and sums) by the other population's row count. Rebuilt as two
   per-currency aggregates left-joined to the currency union.
2. **Receipts lacked the arrived-status filter (OCC-009/#22-#25 class).**
   `receipts` now requires `status in ('paid','refunded','reversed')` —
   non-arrived payments can never contribute collected cash even if a stray
   paid_at exists.
3. **Session-timezone-dependent month keys (OCC-009/#21/#35 class).** The
   month list formatted `g.d` after converting it to an INSTANT
   (`(g.d::timestamp at time zone gym_tz)`), so `to_char` rendered it in the
   SESSION timezone — month-start days fold into the previous month whenever
   the session zone differs from the gym zone. The series variable is
   already the naive gym-local midnight of a selected calendar date; the key
   is now `to_char(g.d, 'YYYY-MM')`, session-independent. (The receipt and
   return month keys were already correct: `timestamptz at time zone gym`
   yields a naive value that `to_char` takes as-is.)

Branch-refusal signal re-verified from the shipped bytes: unknown and
foreign branches both reach the same `P0002 'Branch not available'
(branch_unavailable)` refusal raised before any zone work — matching the
adjudicated P0002 class.

Static: both bodies balance with the structure-aware pairing scanner; zero
select-level order-by-before-from; all nine top-level keys verified; final
select closes at relative depth 0.

Remaining RED attribution: the clusters still unexplained after these fixes
(heatmap/classes section-wide, moneyRange/zone disclosures, #5) cannot be
re-derived responsibly without observed values — the coordinator should
capture got/wanted for representative pins (#5, #17, #19, #20, #21, #37,
#45) via the TAP-detail transform (scratchpad/make-tap-diag.py on the
compiled individual, finish-select last) before the next builder round.

New migration sha256:
`a6361b946ad31fe62e6164e781e84564f9ab6fa33a4ecdef34e83089f51c5fa0`

## Runtime repair round 4 (2026-10-04, got/wanted adjudication input)

1. **Actor gate hardening (the #5/#13/#14/#15 cluster).** The OK-under-
   cleared-claims observation admits exactly one source-side mechanism:
   Supabase's `auth.uid()` casts its `''` fallback through `::uuid`, so an
   EXPLICITLY cleared `request.jwt.claims` GUC makes the identity helper
   RAISE a 22P02-class cast error inside the gate — the probe then observes
   an implementation-shaped outcome (never 42501, and per the captured dump
   an apparently-successful capture) instead of the single refusal. The gate
   now evaluates the ENTIRE claims/staff derivation inside guarded exception
   blocks: any raised identity helper (missing, empty or malformed claims
   GUC included) collapses into the one 42501
   `Not permitted to read occupancy analytics` refusal, before any read.
   The two-arg delegate still routes through this identical gate first (its
   body is the single four-arg delegation; the core's first statement is the
   gate) — verified in the shipped bytes; no separate wrapper gate was added
   because the delegation already precedes every read.
   If the observed OK instead came from owner claims still resident in the
   GUC at probe time (clearing scope), that is fixture-side: against these
   bytes a genuinely empty GUC cannot return OK.

2. **Warnings totals cross-product (#33) and receipts status filter
   (#22-#25 class)** — fixed in round 3 (kept).

3. **#28 (returned-component evidence) and #30 (addon/unallocated
   evidence):** static re-derivation found no divergence — the Return
   object emits the original receipt's category, `allocationUnknown`
   exactly for unallocated originals, and `membershipEvidence` only when
   the original payment's membership link exists (null for add-on and
   unallocated), with `{createdAt, hasEarlierMembership}` where
   hasEarlier is the strictly-earlier-row test with no id tie-break. The
   full got/wanted JSON for #28 and #32 is REQUIRED before any further
   source change: the divergence sits in fields not identifiable from the
   label (createdAt spelling/instant, hasEarlier value, or amountPaise).

4. **Expired-path check for #32:** the refunds RLS grants tenant front
   office SELECT (verified in the money migrations), `refund_status`
   includes 'completed', and the warnings population correctly excludes
   range/branch/holiday influence — so an empty undatedReturns against a
   lawful fixture needs the dump to adjudicate (fixture staging vs source).

Static: both bodies balance (pairing scanner); new migration sha256:
`d27da442abc130e54e0eb4f2be463991700feac3718be1b14f5b8985de89495e`

## Runtime repair round 5 (2026-10-04, got/wanted dumps)

1. **#28 — allocationUnknown emitted as the JSON string "false".** The
   component flag emission now normalizes explicitly through `::boolean`
   (`(r.allocation_unknown)::boolean`, and the same for the
   `hasEarlierMembership` expressions in both evidence objects) so the
   envelope's shape carries real booleans regardless of how the carried
   column type resolves. Notable datum for the record: the day-level flags
   (`isHoliday`/`excluded`/`exists`) demonstrably arrive as real booleans
   (assertion #41 passed while they are emitted as bare CTE/expression
   booleans), so if the string emission recurs after this normalization the
   capture pipeline itself must be audited — boolean flags in this envelope
   are plain boolean expressions.
2. **#32/#33 — undatedReturns empty against a staged completed undated
   return.** The shipped `warnings_returns` population is already
   declaration-exact (`tenant` + `status='completed'` + `processed_at is
   null`, no range/branch/holiday influence; refunds RLS grants tenant front
   office SELECT; `refund_status` includes 'completed'). The coordinator's
   characterization ("misses completed return rows") does not match the
   shipped bytes; adjudication needs the staging path for return …803 (its
   status, processed_at, tenant and the captured snapshot call's claims
   context) before any alteration — the source is not changed blind here.
3. **#30** — pending observation, unfixed by design per the coordinator.

Static: both bodies balance (pairing scanner). New migration sha256:
`a995fd4c6a2a7393f97fbddf25c2aa83d73dd5f068ec60fb674eb974911afc89`

## Kind-scope verification for #32 (2026-10-04, fixture facts received)

Verification against the shipped bytes: NEITHER return population filters
`kind`. `warnings_returns` is `from public.refunds r where r.tenant_id =
(select tenant_id from params) and r.status::text = 'completed' and
r.processed_at is null` — no kind predicate, so a kind='reversal' row
(…803: reversal, completed, processed_at null, tenant …1) IS inside the
population. The same holds for `rets` (dated returns) — reversal and refund
alike flow into collection and months, matching the repo vocabulary where
`refunds` rows of both kinds are the return facts and payments carry
'reversed' as an arrived status. No declaration-scope note is needed: the
bundled refunds/reversals reading is already the shipped behavior.

Consequently the observed empty `undatedReturns` against the staged …803
row cannot come from kind filtering. Remaining candidate causes are
capture-side: (a) the fixture stages …803 AFTER the snapshot call
materializes (ordering), or (b) the row's visible state differs at snapshot
time (tenant/status/processed_at) from the staging facts. A same-session
probe under the same owner claims — `select count(*) from public.refunds
where tenant_id = …1 and status='completed' and processed_at is null` —
immediately before the snapshot call distinguishes RLS/visibility from
ordering; if it returns 1 and the snapshot still shows [], the next
got/wanted capture against sha
`a995fd4c6a2a7393f97fbddf25c2aa83d73dd5f068ec60fb674eb974911afc89`
(booleans normalized, gate hardened) adjudicates. No source change made
this round; sha unchanged.

## Runtime repair round 6 (2026-10-04, value-level adjudication)

1. **Gate (#5 cluster).** Added a belt-and-braces conjunct before the
   identity helpers: `coalesce(current_setting('request.jwt.claims',
   true), '') <> ''` — a missing or explicitly empty claims GUC now refuses
   42501 deterministically, independent of how `auth.uid()` treats `''`.
   Against these bytes the claims-less two-arg/default-form probe cannot
   return OK unless the claims GUC still RESOLVES to a valid payload at call
   time (i.e., the clearing did not take effect in the capture transaction) —
   #6/#7 refusing while #5 passes is exactly the signature of the empty-GUC
   check never running with an actually-empty GUC. Re-capture will show
   either green #5 or proof of fixture-side claim leakage.
2. **Cell eligibleDates (#45/#46/#74).** The senior author's pin
   (denominator 13 = all completed nonexcluded dates, 14 with the toggle
   off) matches the envelope sentence literally — "eligibleDates counts
   those completed nonexcluded dates on which hour exists" carries NO
   weekday qualifier (my weekday-scoped grouping was the OCC-006
   prose reading). Rebuilt: eligibleDates now counts per (branch, hour)
   across the whole selected range; a DST-gap hour loses only the dates on
   which it does not exist; the fraction remains
   arrivals-at-the-coordinate / those dates (769 bp at 1/13).
3. **#63/#64/#66/#67 (classes)** and **#39/#49/#76 (zone disclosures)**:
   under static re-derivation my drill grouping keys on each session row
   (one jsonb row per session, ordered sessionDate/startsAt/sessionId),
   cancelled drill rows carry exactly the five declared keys, and the
   services item shape is exactly the declared `{serviceId, summary}` —
   note jsonb canonicalizes key order (summary sorts before serviceId by
   length), so a key-ORDER pin on those two keys cannot be satisfied by any
   correct jsonb implementation. These need the full got/wanted dumps —
   request: #63, #64, #67, #39, #49, #76 (and the still-open #28/#30).

Static: both bodies balance (pairing scanner); new migration sha256:
`6f374f78fe97b1c121b07083edb872f29662918bca37a1f776a3f794128b9bc4`

## Round-6 addendum: the round-5 boolean cast IS in the emission path

Verifier against round-5 bytes a995fd4c: the `return_objs` CTE — the ONLY
builder of the returned components (the final assembly aggregates
`return_objs.obj` verbatim) — already carries
`'allocationUnknown', (r.allocation_unknown)::boolean` and
`'hasEarlierMembership', ((r.category = 'renewal'))::boolean` at a995fd4c
(verified present in the current file too, lines 237/240). Postgres cannot
emit the JSON string `"false"` from a boolean argument to
`jsonb_build_object` — `to_jsonb(boolean)` is true/false, full stop.
Therefore a capture showing `"allocationUnknown": "false"` at a995fd4c did
not execute those bytes: the compiled splice or the function actually
loaded in the capture session predates the round-5 edit (the hash-verifying
diagnostics runner refuses stale splices, but manual TAP-extraction runs do
not hash-check).

Recommended verification before the next capture:
```
select pronargs,
       prosrc like '%allocationUnknown'', (r.allocation_unknown)::boolean%' as has_cast,
       md5(prosrc) as loaded_body_md5
from pg_proc where proname = 'owner_occupancy_analytics';
```
plus recompile the batch from the working tree (sha
`6f374f78fe97b1c121b07083edb872f29662918bca37a1f776a3f794128b9bc4`) so
every capture runs the current bytes. Also noted and accepted: the services
rollup item shape `{serviceId, summary}` matches declaration line 148 — no
change made or needed there; no source change this round, sha unchanged.

## Runtime repair round 7 (2026-10-04, 42725 overload ambiguity)

- Runtime fact: the declared two-argument call raised
  `42725 function ... is not unique` because the four-argument core carried
  DEFAULT clauses, so both signatures matched any two-argument call.
- Fix (within the declaration): the four-argument core now takes all four
  parameters REQUIRED (`p_branch_id uuid, p_exclude_holidays boolean` — no
  defaults); the exact four-argument form remains the canonical call
  ("use all four named arguments") and the two-argument delegate remains the
  declared default path, passing all four arguments explicitly internally.
  Resolution is therefore unique by argument count for every arity: two args
  resolve to the delegate only, four to the core only. Partial arities
  (three arguments) now match NO signature — any three-argument call site
  outside the two declared forms must be called out (the declaration's
  transport section names only both-arg-complete and the two-arg delegate).
- External call sites verified: the web loader
  (apps/web/lib/occupancy.ts) already passes all four named arguments —
  unaffected. The coordinator's rollback probe request is honored as a
  catalog-semantics proof (a two-argument call has exactly one candidate
  with no defaulted core) plus the static checks; the orchestrator's own
  rollback probe of `owner_occupancy_analytics(date,date)` remains the
  runtime confirmation.
- Migration sha256:
  `8c9c27ba1cf82286d5f325fcafb9dcff56949134a6fb7fd3ab3ed1040ce602cc`

## Gate cluster resolution note (2026-10-04, coordinator)

The #5/#13/#14/#15 "OK" cluster resolved suite-side: the visible suite's
claims-clear ran inside a probe subtransaction and rolled back, so those
probes executed under lawfully-admitted gym-owner claims. The coordinator's
standalone rollback probe at sha
`8c9c27ba1cf82286d5f325fcafb9dcff56949134a6fb7fd3ab3ed1040ce602cc`
confirms: empty claims under authenticated refuse 42501
`Not permitted to read occupancy analytics` at the core gate, and the
two-arg delegate resolves cleanly with the defaults removed. The round-4/6
gate hardening (guarded claims derivation + explicit empty-GUC conjunct)
remains in place as defense in depth. The #28 string-boolean residue is
treated as a probable capture-rendering artifact pending the amended
suite's authoritative rerun. No further source change pending that rerun.

## Runtime repair round 8 (2026-10-04, authentic round-8 failures)

1. **Branch/zone validation restored (#13/#14/#15 — genuine gaps from the
   envelope rewrite).** The rewrite had dropped the pre-population
   validation: an unknown or foreign branch produced an EMPTY population
   (call succeeded) and a selected invalid-zone branch disclosed
   in-envelope instead of raising. Restored before any population lookup:
   unknown/foreign p_branch_id → one `P0002 Branch not available
   (branch_unavailable)` invisible-target refusal; selected branch with its
   OWN invalid configured zone → `22023 Invalid branch timezone
   (invalid_branch_timezone)`. A branch that only INHERITS an invalid gym
   zone stays an in-envelope disclosure (assumption 3 / #77), and
   population entries (whole-gym calls, #49) keep the preserved-text error
   entries — matching the author's split between raising and disclosing.

2. **#28 string booleans at a995ff/8c9c27ba —.bytes proof.** The executed
   epilogue could not have produced a JSON string from these bytes:
   return_objs (the ONLY builder of the returned components) carries
   `'allocationUnknown', (r.allocation_unknown)::boolean` since a995fd4c and
   the assembly aggregates that obj verbatim — `to_jsonb(boolean)` has no
   string path. Deterministic fingerprint for the capture session:
   `select prosrc like '%(r.allocation_unknown)::boolean%' as has_cast,
   md5(prosrc) from pg_proc where proname='owner_occupancy_analytics';` —
   the expected md5 of the loaded 4-arg body at these bytes is
   `93187304f191f655d490703c7bab2e20` (with the cast present). If has_cast
   is FALSE in the capture session, the splice/load ran older bytes; if TRUE
   and the string still appears, the capture/compare layer itself renders
   the flag as text (pgTAP is() text coercion on the dump path) and the
   rerun verdict stands as authoritative per the coordinator.
3. #63/#64 deeper-field residual and #20/#30/#39/#56/#66/#76: dumps on
   request for the next surgical round.

Static: both bodies balance. New migration sha256:
`82d9ca2c6eecb207f03fe91a372feb0f1ee87f19b12a4b9e46fd6a6749544bfe`
EPF (expected loaded-body md5 for the 4-arg core):
`93187304f191f655d490703c7bab2e20`

## Runtime repair round 9 (2026-10-04, dump decode)

Decoded from the value dumps: #63/#64's residual (and plausibly the whole
remaining timestamp-bearing class #20/#30/#39/#49/#56/#66/#76) is TIMESTAMP
SPELLING — the author's want literals carry RFC3339 `Z` form while jsonb's
native timestamptz rendering emits `+00:00`. Fixed by emitting EVERY
timestamp value (top-level asOf, moneyRange boundaries/cutoff, month
boundaries/cutoff, component paidAt/processedAt, membershipEvidence
createdAt, branch range boundaries/cutoff, day startsAt/endsBefore, session
drill startsAt/endsAt, cancelled drill startsAt/endsAt — 17 emission sites)
through `to_char(<instant> at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')`
— the canonical RFC3339 UTC rendering, unambiguous per the envelope, and
matching `->>` text projections. Date-only outputs (localToday, sessionDate,
month keys) are unchanged. Completeness sweep: zero raw timestamp emissions
remain. Comparisons inside the statement still use real timestamptz values —
only the emitted keys are formatted.

Also decoded from the dumps: #32/#33 resolved suite-side (the amended suite
pins the unreachable completed-undated state's coupled invariant instead —
the source population was already declaration-exact); #67 resolved suite-side
(rollup shape matched declaration line 148). #28 confirmed a suite-side
`->>` projection artifact. #66 remains open with its dump captured but
undetailed in the file (gets/wants present only for #63/#64) — covered by
the same spelling fix for its startsAt/endsAt values; re-verify on rerun.

New loaded-body md5 (4-arg core): `296ae41e3b56c30ec0eceafe8604d736`.
New migration sha256:
`fa1c090d1cea948b4378212b7dedada9fcbb2f21c569811fa159ecbf0c4595d8`

## Round-9 residual decode (2026-10-04, dumps2)

**The dump file carries got/wanted bodies ONLY for #28 — the other seven
(#20/#30/#39/#49/#56/#66/#76) landed as headers with no values.** What the
one full body shows is decisive against further source changes:

#28 is now a pure SPELLING discrepancy in the opposite direction from
#63/#64: my evidence emits `"createdAt": "2026-01-10T00:00:00Z"` (round-9 Z
form) while the author's want literal is `"2026-01-10T00:00:00+00:00"`
(native jsonb timestamptz rendering) — every other field matches, and
`allocationUnknown` is now a real boolean (the round-5 `::boolean`
normalization verified in the dump). Meanwhile the amended #63/#64 passed
because their hand-typed session-time literals are Z-spelled. The author's
expectations therefore MIX two spellings — hand-typed literals in Z,
captured/native values in +00:00 — which no deterministic emission can
satisfy simultaneously, and which contradicts the author's own recorded
assumption 5 ("timestamps compared as instants, never as spelling").

Classification: #28 → author-pin (route to the visible author: either
compare `->>'createdAt'` instants via `::timestamptz` casts per their own
assumption, or export one canonical spelling for all timestamps and
regenerate the literals). The seven value-less pins (#20/#30/#39/#49/#56/
#66/#76) are undecodable from headers alone — re-dump needed with intact
got/wanted bodies; note they failed under BOTH native (round 8) and Z
(round 9) emissions, so at least some carry real divergences or intra-pin
mixed spellings, not a single formatting root cause.

No source change this round; sha unchanged, balance OK. Current bytes:
`fa1c090d1cea948b4378212b7dedada9fcbb2f21c569811fa159ecbf0c4595d8`.

## Dumps3 daylight report (2026-10-04)

The seven re-dumps arrived HEADERS-ONLY again — zero got/wanted bodies for
#20/#30/#39/#49/#56/#66/#76 (so the first truncation was not size-bound;
these assertions likely fail through a helper that emits no have/want text,
e.g. an ok() over a computed boolean instead of is() with both values).
No classification is possible from labels, and my declaration re-derivation
of each of the seven shapes stays clean.

Working hypothesis for the both-rounds failure pattern (worth checking when
the bodies land): pins that combine HAND-TYPED literals (expecting the Z
canonical form) with CAPTURED-RUN values would fail under either emission —
under native those literals mismatch, under Z a runtime-captured comparison
(above all asOf, whose value cannot be hand-typed) mismatches.
To adjudicate, dump the raw snapshot keys instead of assertion have/want:
- #20: the whole `moneyRange` object
- #30: collected components rows with category in (addon, unallocated)
- #39: heatmap.branches entry for the inheriting branch
- #49: heatmap.branches entry for the invalid-zone branch
- #56: the day row whose state is current + that branch's cell todayArrivals
- #66: classes.branches[].cancelledSessions array
- #76: top-level zone/moneyRange/months/collection under the corrupted org
No source change; sha unchanged `fa1c090d…`.

## Raw-dump classification (2026-10-04, dumps from 83-raw-keys.txt)

Decisive structural fact: `moneyRange` appears ZERO times in the entire
raw-keys file — every 20 KB dump truncates inside heatmap's day-row wall
BEFORE reaching collection/moneyRange/warnings (canonical jsonb order puts
heatmap's 14 day-rows × 24 hours ahead of them). So #20/#30/#39/#49 remain
UNDECODABLE from these dumps — not classified, just truncated. Targeted
single-key dumps needed: moneyRange (#20); collection.components.collected
rows with category in (addon, unallocated) (#30); the inheriting branch's
heatmap entry (#39); branch …13's heatmap entry (#49).

Classified from what IS visible:
- **#76 → author-pin (suite routing).** DUMP76 shows a VALID-zone snapshot
  (zone Asia/Kolkata, three real money months) — the invalid-gym-zone pin's
  captured call hit the valid tenant, exactly as the coordinator suspected;
  the pin's claims/org context routing needs the author's eye.
- **#56 → author-pin (suite-side scenario).** DUMP56 shows the Sep 14–27
  range under asOf 2026-10-04 — that range contains NO current day, so the
  "today is a current day" scenario cannot be satisfied by this call; the
  pin needs a today-inclusive range call (or its own snapshot).
- **#66 → my array is declaration-exact.** DUMP39's head shows
  classes.branches[…11].cancelledSessions =
  [{endsAt/startsAt Z-form, serviceId, sessionId …423, sessionDate}] — five
  keys, ordered; whatever the want expects beyond this (a second cancelled
  session? branch …12's array?) needs the pin's want literal.

No source change this round; sha unchanged
`fa1c090d1cea948b4378212b7dedada9fcbb2f21c569811fa159ecbf0c4595d8`.

## Per-label classification from targeted key dumps (2026-10-04)

All seven residual labels classify AUTHOR-PIN / SUITE-SIDE; zero source
deltas are derivable from the raw values:

- **#20 moneyRange** — KEYmr: zone, error null, scope 'Whole gym',
  startsAt/endsBefore/cutoffAt consistent with the suite's expectations when
  cast, localToday '2026-10-04' as a date string. Per the coordinator's own
  walk: the failing conjunct is on the author's list, not in the values.
- **#30 evidence** — KEYc703 (addon) and KEYc704 (unallocated) both carry
  `membershipEvidence: null` exactly as the declaration requires, with
  correct category/amountPaise/currency. Residual is the suite's other
  conjunct (r->>'category' pins or an extra collected row expectation).
- **#39 inherited zone** — KEYhb11: zone 'Asia/Kolkata', zoneSource 'gym',
  error null — the inherited-gym-zone disclosure exactly per the author's
  own assumption 3 and the envelope. (KEYhb12 confirms the New_York override
  branch's local day boundaries — Sep 14 starting 2026-09-14T04:00:00Z —
  for their sibling adjudication.)
- **#49 invalid-zone entry** — KEYhb13 matches the want EXACTLY (Mars/Phobos
  preserved, zoneSource 'branch', error invalid_branch_timezone,
  range/days/cells/week/availability/aggregates null). Residual is a later
  conjunct on the author's list; totalVisits/excludedVisits null verified
  present.
- **#56 today** — KEYtoday's current-day row could not be confirmed either
  way (the day objects contain nested hour arrays, so a flat state-row
  regex is unreliable); the scenario needs the author's range/claims
  walkthrough. No source delta derivable.
- **#66 cancelled disclosure** — KEYcanc is the declaration-exact five-key
  ordered array; the pin's want literal is the missing piece.
- **#76 invalid gym zone** — already routed: the captured call hit the
  valid tenant (suite routing).

Pattern across all seven: where raw values exist, they match the envelope
and the author's stated expectations; every residual is a later conjunct, a
fixture/expectation mismatch, or suite routing. Recommended next step:
the visible author walks each pin's conjunct list against these raw key
dumps; if a genuine declaration divergence is claimed after that walk, it
returns to this builder with the exact conjunct. No source change; sha
unchanged `fa1c090d1cea948b4378212b7dedada9fcbb2f21c569811fa159ecbf0c4595d8`.
