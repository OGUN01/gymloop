# OCC — occupancy, collection and class fill analytics

**DRAFT NOT FROZEN — 2026-10-03.** Public contract preparation only for F14 /
V2-D4. Wave C remains before Wave D; this document neither advances that order
nor authorizes build, tests or deployment. Owner approval and relevant
closed-test feedback must resolve the choices below before the contract is
frozen. No implementation, visible/holdout suite, private evidence, Cloud,
browser or device acceptance was inspected or performed for this draft.

## Purpose and bounds

Help an owner choose staffing hours, compare branches fairly, see actual
monthly collection, and identify classes with weak booking demand. This is one
owner-console feature, building on the existing metrics screen. It does not
change check-in, membership granting, refunds, class marking, RLS, provider
verification, retention or notifications. It introduces no adapter, source
export, table, RPC signature or status vocabulary at the draft stage. Reports
and GST/PDF exports remain RPE's work.

Source contracts: `docs/planning/v2-feature-map.md` F14;
`docs/planning/v2-campaign-goal.md`; `docs/planning/phase6-metrics-contract.md`
(MET-001–008); `docs/domain-rules.md` ATT, MNY-001–005, PAY-007/010/011,
ADD-012 and INT; `docs/data-model.md`; `docs/security.md`;
`openspec/specs/attendance/spec.md`, `membership-creation/spec.md`,
`membership-net-price/spec.md`, `payment-record/spec.md`,
`manual-payment/spec.md`, `refund-retries-and-money-audit/spec.md`;
`openspec/changes/classes/proposal.md` CLS-039 and its approved booking facts.
The quality comparator and future evidence bar are in `docs/design/v2/occ-bar.md`.

## Facts which constrain the draft

- Attendance is one accepted visit row with its recorded branch and
  `checked_in_at`; `checked_out_at` is optional. Counting arrivals can describe
  busy arrival hours, but cannot establish how many people were simultaneously
  present or a percentage of building capacity. Offline provenance is not a
  replacement analytics event timestamp.
- `branches.timezone` overrides `organizations.timezone` when nonnull.
  `organization_holidays.holiday_on` is a tenant calendar date with no
  branch-specific calendar. Invalid configured zones cannot produce fabricated
  UTC analytics. A null branch zone is an intentional gym-zone inheritance.
- The existing metrics snapshot counts arrived payment statuses
  `paid`/`refunded`/`reversed` at `paid_at`, and completed returns (refund and
  reversal kinds) at `processed_at`, independently. Requested/processing
  returns reserve refund headroom but are not returned cash.
- A membership may receive partial payments and subsequent period grants on
  the same row. Current `periods_granted` does not record a receipt's historical
  allocation. `renewal_of_membership_id` alone cannot classify all renewals;
  a null predecessor is not proof of a new member. Refunds reverse cash without
  rewriting granted periods. Existing cash definitions must not be replaced by
  membership prices, invoices, purchase requests or screenshot claims.
- CLS-039 defines its analytical “ran” proxy as session `status = 'scheduled'`
  with `ends_at < now`. A holding booking is `booked`, `attended` or `no_show`;
  attended/no-show facts require explicit marking. The roster's gym check-in
  evidence does not prove class presence. Session capacity is the stored
  per-session value; service defaults are not historical denominators.

## Stable EARS requirements

All OCC clauses below are draft requirements. Existing contracts cited above
remain authoritative; proposed choices are explicitly labelled and cannot be
treated as owner-approved financial definitions.

- **OCC-001 (audience and tenancy).** WHEN an analytics read is requested THE
  SYSTEM SHALL require the existing real owner/manager verified gym identity,
  derive tenant and server `asOf` from that identity and statement, and reject
  support preview, members, trainers, front desk, missing/mixed claims and other
  tenants before returning any partial analytics. Branch selections SHALL be
  same-tenant branches visible to that caller; a forged or unavailable branch
  SHALL produce a safe refusal without revealing whether a foreign row exists.
  Existing RLS SHALL remain enabled; no service credential SHALL enter a web
  read path.
- **OCC-002 (one snapshot).** WHEN totals, series, comparisons, denominators or
  drill-downs are returned THE SYSTEM SHALL derive them from one containing
  statement snapshot with one server `asOf`, retain exact reconciling component
  populations, and disclose `asOf`. The selected past range SHALL filter rows
  in this current snapshot; it SHALL NOT be presented as a reconstructed
  historical status snapshot. Separate pages, separately refreshed drills and
  client-summed RPC snapshots SHALL NOT supply one apparent total.
- **OCC-003 (dates and zones).** WHEN a range is selected THE SYSTEM SHALL require
  both real calendar dates with `from <= through`, represent each branch's
  range as `[from local midnight, through+1 local midnight)`, and return those
  dates, the effective IANA zone and boundary instants. An inherited gym zone
  SHALL be disclosed; an invalid nonnull branch zone or invalid gym zone SHALL
  produce an explicit zone error for the affected population, not a fallback
  zero. Money months SHALL use the valid gym zone, independently of branch
  selectors. Events at the lower bound SHALL be included and at the upper bound
  excluded. Events at or after `asOf` SHALL not contribute; current and future
  periods SHALL be visibly partial or unavailable, never full-period zeros.
- **OCC-004 (arrival heatmap).** WHEN a branch's staffing heatmap is displayed
  THE SYSTEM SHALL count each accepted `attendance` row once by its recorded
  `branch_id` and `checked_in_at`, converted to that branch's effective local
  date, weekday and clock hour. Two accepted visits by the same member SHALL
  count twice; retries SHALL not create a new analytics visit. THE SYSTEM SHALL
  call this “Check-in arrivals”, with total visits, not people currently inside,
  building occupancy percentage or class attendance. Neither member home branch,
  current membership/profile status nor an invented dwell duration SHALL
  reassign or remove historical visits.
- **OCC-005 (holiday exclusion; proposed display default).** WHILE attendance
  holiday exclusion is enabled THE SYSTEM SHALL exclude a visit whose
  branch-local date equals a same-tenant `holiday_on`, and exclude that date
  from every heatmap exposure denominator. The default SHALL be exclusion on,
  visibly reversible, with excluded dates/visit counts available from the same
  snapshot. An all-holiday range SHALL show “No eligible days”, not a quiet
  branch. THE SYSTEM SHALL not use this toggle to remove actual payments,
  returns or CLS sessions which remained standing and elapsed on a holiday.
- **OCC-006 (fair exposure; proposed exact normalization).** WHEN the heatmap
  presents comparable weekday/hour demand THE SYSTEM SHALL show both raw
  arrivals and the exact fraction `arrivals on eligible completed local dates /
  eligible completed local dates` for that weekday/hour. The fraction numerator
  SHALL contain only visits on the denominator's dates. Completed means next
  local midnight is `<= asOf`;
  incomplete today's arrivals SHALL be disclosed separately and not mixed into
  that average. Eligible dates SHALL be inside the selected dates, nonholiday
  when exclusion is on, and have that local hour under the IANA zone. Days with
  zero accepted visits SHALL count as zero observations, not disappear. A
  missing DST hour SHALL have no exposure; a repeated clock hour SHALL combine
  its two occurrences for that date and count that date once. This is average
  arrivals per eligible weekday-date, not arrivals per elapsed real-time hour.
  Closed-hour exposure is a calendar observation, not a claim that the branch
  was open; current opening-hours settings SHALL not invent historical opening
  hours. Denominator zero SHALL return no average.
- **OCC-007 (low-data integrity).** WHEN an attendance or class sample falls
  below the approved minimum THE SYSTEM SHALL disclose its raw numerator,
  denominator, eligible dates/sessions and “Limited history”, and SHALL not
  claim a reliable peak, improvement or weak-class ranking. UNTIL the owner
  approves the smoothing method and minimum in OCC-OPEN-02 THE SYSTEM SHALL
  permit no fabricated visits, hidden pseudocounts, neighbouring-branch
  borrowing, smoothed money, or definitive confidence label. Any approved
  smoothed display SHALL be explicitly labelled, reproducible from the same
  raw sample and its published parameters, and SHALL preserve raw totals.
- **OCC-008 (cross-branch comparison).** WHEN multiple branches are compared
  THE SYSTEM SHALL use the same selected local dates, weekday/hour coordinates,
  holiday toggle and metric definition for each branch, while applying each
  branch's own zone and reporting its own exposure. A common heatmap scale SHALL
  use the same unit and exact per-date normalization; zero exposure SHALL
  remain unavailable rather than rank lowest. A zone/permission/error result
  SHALL not be silently dropped from an apparent all-branch comparison. THE
  SYSTEM SHALL label clock-time alignment as local-time comparison, not
  simultaneous instants, and SHALL not average branch averages to claim an
  organization total. Raw organization arrivals SHALL sum the same included
  branch visit populations.
- **OCC-009 (monthly actual collection).** WHEN a monthly money series is read
  THE SYSTEM SHALL group the existing exact arrived-payment population by
  `paid_at` in gym-local calendar months and explicit currency, using full
  `amount_paise` once per payment. Created/pending/failed attempts, invoices,
  promised plan prices, screenshot/request states, and complimentary sales
  SHALL contribute no collected cash. Nonnull dated facts within the selected
  instant range and before `asOf` SHALL contribute; an arrived payment without
  `paid_at` SHALL instead remain in a visible current all-date warning.
- **OCC-010 (completed returns and net).** WHEN net collection is displayed THE
  SYSTEM SHALL independently group only completed refunds/reversals with
  nonnull `processed_at` by their completion month in the same gym zone and
  currency, and compute `netPaise = collectedPaise - returnedPaise`. A return
  in a later month SHALL reduce that later month even when the original payment
  lies outside the selected range; THE SYSTEM SHALL not rewrite the payment
  month. Requested/processing/failed returns SHALL contribute zero returned
  cash; a completed undated return SHALL be a visible current all-date warning.
  A returns-only month may be negative and SHALL remain visible. This adopts
  the approved MET cash definition, not a new accounting-recognition policy.
- **OCC-011 (exact money and percentages).** WHEN aggregation or presentation
  is performed THE SYSTEM SHALL preserve integer paise and explicit currency,
  canonical decimal-string counts/money and exact server integer/numeric
  intermediate arithmetic; client arithmetic SHALL use BigInt/strings. Money
  SHALL not pass through floating point, currency conversion or fractional
  allocation. Ratios SHALL reuse `ratioBasisPoints` / `formatBasisPoints` for
  half-up basis-point rounding, retain the exact fraction and show “No cohort”
  for a zero denominator. Display rounding SHALL not change any cash total.
- **OCC-012 (new-member and renewal split; blocked until owner definition).**
  WHEN classified monthly collection is displayed THE SYSTEM SHALL apply only
  the owner-approved OCC-OPEN-01 receipt allocation rule, with reconciling
  source evidence and no double counting. UNTIL that rule is approved and the
  required historical evidence exists THE SYSTEM SHALL show membership money
  as unclassified, preserve its exact collection/returns/net, and SHALL NOT
  label receipts using current `periods_granted`, member `joined_on`, first
  observed receipt, or null predecessor as guessed new-member/renewal facts.
  Known linked add-on money and other/unallocated manual money SHALL be
  disclosed separately from membership classification. Total collected,
  returned and net for each currency SHALL reconcile across the disjoint
  categories, including unknowns. Refund category allocation SHALL follow the
  approved original receipt allocation, not the member's later status; an
  unknown original allocation SHALL remain unknown, including a return whose
  original receipt is outside the selected range.
- **OCC-013 (money scope).** WHEN an attendance/class branch filter is changed
  THE SYSTEM SHALL keep the monthly collection panel explicitly “Whole gym”
  unless an owner-approved historical financial branch attribution exists.
  Payment/refund rows have no branch fact; today's member home branch SHALL
  not be substituted. THE SYSTEM SHALL label the series “Collection” and
  “Net collection after completed returns”, not profit, bank settlement,
  recognized revenue, unpaid renewal due or fees deducted. The current month
  SHALL show “Month to date” and its cutoff; partial endpoint months SHALL
  disclose covered dates and SHALL not receive a full-month growth claim.
- **OCC-014 (CLS elapsed session cohort).** WHEN class fill is calculated THE
  SYSTEM SHALL use only same-tenant selected-branch sessions whose
  `session_date` is in the selected branch-local dates, `status = 'scheduled'`
  and `ends_at < asOf`, exactly translating CLS-039's “ran” proxy to the shared
  server cutoff. A session ending exactly at `asOf`, ongoing/future or cancelled
  SHALL be excluded. Holiday sessions which remained scheduled SHALL stay in
  this cohort. Historical disabled services/trainers SHALL not erase it. THE
  SYSTEM SHALL disclose “Elapsed non-cancelled sessions” as the cohort; elapsed
  is not independent proof an instructor delivered a class.
- **OCC-015 (booked fill, not presence).** WHEN the F14 class percentage is
  displayed THE SYSTEM SHALL label it “Booked fill” and compute
  `sum(holding bookings) / sum(session capacity)` over OCC-014, with session
  drill-down fractions and counts of `booked`, `attended`, `no_show` and excluded
  cancelled sessions. Cancelled booking statuses SHALL not count. Capacity
  SHALL be the stored session capacity, not a service default, and a multi-session
  result SHALL be capacity weighted, never the unweighted mean of percentages.
  A no-show still held a seat and SHALL count in booked fill. Cancelled sessions
  SHALL contribute neither bookings nor capacity.
- **OCC-016 (explicit marked presence).** WHEN presence evidence is shown next
  to booked fill THE SYSTEM SHALL separately report explicitly marked
  `attended`, explicitly marked `no_show`, and still-`booked` unmarked counts
  from the same elapsed session cohort. `attended / capacity` may be labelled
  “Marked presence / capacity”, with marking coverage
  `(attended + no_show) / holding bookings` and an incomplete-marking disclosure;
  it SHALL not claim complete true attendance when bookings remain unmarked.
  THE SYSTEM SHALL not infer attended/no-show from gym attendance, missing
  check-in, elapsed time, cancellation or an unmarked booking, and SHALL not
  implement the comparator's `100% - attendance` no-show shortcut.
- **OCC-017 (truthful screen).** WHEN any view is empty, loading, failed,
  unauthorized, offline or low-data THE SYSTEM SHALL use established Chalkline
  states, keep zero, unavailable, excluded and unknown visibly distinct, and
  offer an applicable retry, range change or link to existing operational
  history. The comparison and monthly-series exact values SHALL be available
  as accessible ledger rows without relying on color, hover or chart sight.
  Both themes, large text, reduced motion and existing accessibility gates
  SHALL apply. No decorative forecast, causal recovery attribution or growth
  percentage SHALL be invented from these descriptive facts.

## Reuse boundary before implementation

The registry identifies `public.owner_metrics(date,date)`, `app.gym_metrics`,
`app.gym_live_members`, `ownerMetricsSchema` / `OwnerMetrics`, `loadOwnerMetrics`,
`MetricsDashboard`, `ratioBasisPoints` / `formatBasisPoints` and the existing
`/dashboard` route. These are the safe analytics seam, caller-session read
boundary, exact cash populations, codecs and presentation primitives to reuse.
`app.membership_renewal_remainder` remains authoritative for renewal **due**;
it must not be repurposed to classify collected receipts. Live members are a
current membership snapshot, not a historical heatmap/capacity denominator.

The present owner response has visits-today rather than historical per-branch
visits, and is an exact schema. CLS's approved `read_class_timetable` supplies
capacity/holding/marked counts and branches, but separately fetched timetable
and cash responses cannot satisfy OCC-002. A later approved design must extend
or version the existing metrics seam coherently, specify its exact response,
authorization and all-date warnings before tests, and preserve existing MET
behavior. This draft does not invent a parallel loader, service-role adapter or
loose schema. Any genuinely necessary new symbol must be searched and registered
by that later implementer; no source symbol is added here.

## Owner choices required before freeze

| ID | Unresolved choice and why it matters | Boundary already fixed |
|---|---|---|
| **OCC-OPEN-01 — cash classification** | Define “new-member money” versus “renewal money”: initial membership sale versus an individual's first purchase are different. Choose how a part-payment, later top-up, one receipt buying initial plus later periods, replacement plan, retired/revived membership, overpayment, imported/legacy row and mismatched-currency receipt are allocated. Choose whether durable receipt-time evidence is required going forward and whether legacy unknowns stay unknown. Define how a partial return is allocated across a split receipt, including integer-paise rounding/remainder ownership. Approve the disjoint add-on and unallocated-manual categories so the panel does not hide real cash. Existing rows and current counters do not settle these choices. | Actual gross receipts and completed returns stay exact and visible; no guessed classification, no dues-as-cash, no floats, no changing granting/refund rules. This is a money-contract decision requiring full blind authors after approval. |
| **OCC-OPEN-02 — smoothing and exposure** | Approve the arrival range default, hourly calendar exposure proposal (OCC-006), minimum observation threshold for arrivals and classes, and what F14 “low-data smoothing” means. Choose raw normalized observations with limited-history disclosure, or a precisely specified labelled estimator with window/weights/minimum and edge behavior. No numeric threshold, prior or smoothing window is frozen here. Confirm whether historical open-hours exposure is demanded; that would require evidence absent from current settings. | Raw facts and denominators remain accessible; no synthetic traffic, no money smoothing, no unqualified low-sample ranking. |
| **OCC-OPEN-03 — class terminology** | Confirm “Booked fill” for F14's bookings/capacity formula and the separate marked-presence disclosure (OCC-015/016). If the owner requires proof a class actually ran beyond CLS-039's elapsed scheduled proxy, approve that as a separate CLS contract change before OCC tests; OCC cannot assert a new completion fact. | CLS-039's existing proxy, frozen session capacities and explicit marking remain authoritative. Gym check-in never proves class attendance. |

Refund-month treatment is **already settled for actual collection** by MET and
ADD-012: completion month, independently of original paid month. Original-sale
month restatement, if wanted, must be separately named and approved; it cannot
silently replace this trend. Financial branch attribution and revenue recognition
are out of this draft, not choices secretly implemented using today's profile.

## Next authorized stage after decisions

Freeze the public contract serially after owner resolutions, then commission
implementation-blind visible and holdout authors for the money/snapshot/access
path and a fresh critic. No test authoring, implementation or migration is
authorized by this draft. Future proof must cover exact range boundaries,
different branch zones, holidays, sparse/zero exposure, repeated/gap hours,
partial months, later-month completed returns, undated warnings, mixed currencies,
unknown cash classification, holding-versus-marked class facts and immutable
same-snapshot reconciliations. All applicable gates and archival follow actual
acceptance, never draft publication. Wave C's closeout remains a prerequisite.
