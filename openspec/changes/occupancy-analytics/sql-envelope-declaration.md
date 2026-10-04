# OCC public SQL envelope — frozen mechanical declaration

Frozen 2026-10-04 after independent public-contract review; this is a complete
mechanical declaration, not implementation certification or permission to
weaken frozen OCC-001…017. The frozen proposal and its approved cash/cutoff
amendments take precedence. Independent authors follow this serial freeze.

## Callable boundary and transport

Canonical call: `public.owner_occupancy_analytics(p_from date, p_through date,
p_branch_id uuid DEFAULT NULL, p_exclude_holidays boolean DEFAULT TRUE) RETURNS jsonb`.
Use all four named arguments. Any existing two-argument overload is not a second
contract or acceptance target. `owner_metrics(date,date)` retains its MET contract.
One scalar JSON object; no SETOF, outer array, paging, cursor, row cap or client cutoff.
One containing statement snapshot and server `statement_timestamp()` supplies `asOf`.
STABLE INVOKER reads retain RLS and the existing verified real owner/manager
identity; refuse preview, unauthorized/mixed/missing claims before population lookup.
A forged/unavailable branch receives the same safe refusal, never partial analytics.

  Adjudication (2026-10-04, orchestrator): the safe refusal class is the
  shipped target-invisibility signal P0002 (missing and forged/unavailable
  branches share one unavailable outcome, matching the read-RPC collapse
  precedent used across SLF/PAY/NTF); no authority-revealing 42501 branch
  refusal is used. Suite pins conform to this note.
No service credential, supplied tenant/asOf or read-only Route Handler is introduced.
Both SQL dates are required, real Gregorian dates, `from <= through`; null toggle is
invalid rather than silently defaulted. Default omission means holiday exclusion on.
Frontend absence of both dates resolves the approved last-28-local-days selection;
resolve once, then send and return actual selected dates. One missing date is invalid.

Notation below declares EXACT keys; `T[]` means an array, not optional properties.
All counts, capacities, integer paise and basis points are canonical decimal STRINGS:
nonnegative `0|[1-9][0-9]*`; signed net allows `-[1-9][0-9]*`, never `-0`.
Only weekday/hour coordinates are JSON numbers (Sunday=0…Saturday=6; hour=0…23).
Dates are `YYYY-MM-DD`, months `YYYY-MM`, timestamps unambiguous RFC3339 instants,
UUIDs strings, currency the original explicit currency; booleans stay booleans.
Missing facts are explicit null; zero counts are `"0"`; empty arrays are `[]`.
Server sums/products use exact integer/numeric arithmetic; client uses BigInt/strings.

## Exact successful envelope

`{asOf, zone, range, moneyRange, months, collection, heatmap, classes, warnings}`.
`zone` is valid gym IANA zone or null for invalid gym zone; never fabricated UTC.
`range = {from, through, branchId, excludeHolidays}` echoes actual resolved selection.
`moneyRange = {scope, zone, error, startsAt, endsBefore, cutoffAt, localToday}`;
`scope = "Whole gym"`; `error` null or `{code:"invalid_gym_timezone"}`.
For a valid zone, boundaries are selected from-local-midnight and through+1-local-
midnight, and cutoffAt=min(endsBefore,asOf); an entirely future range remains
unavailable, not a full zero. For an invalid zone all these derived fields are null,
`months=[]`, `collection=null`; branch-zone populations remain individually explicit.
Branch selector and holiday toggle never change cash populations or cash coverage.

`months` contains every gym-local month intersecting selected dates, ascending:
`{month, from, through, startsAt, endsBefore, cutoffAt, coverage, currencies}`.
from/through are selected dates clipped to that month, boundaries those dates'
midnights; cutoffAt=min(endsBefore,asOf). `coverage` is `full`, `partial`, or
`unavailable`: full requires complete calendar-month selection and end<=asOf;
unavailable means start>=asOf; otherwise partial. Current month is labelled
“Month to date” with cutoff; selected partial endpoints disclose covered dates.
`currencies: Cash[]`; unavailable months have `[]`, never invented currency zeros.
Currency population is the union of that month's dated collected/returned facts;
no movement yields `[]`, including empty fully covered months. No growth inference.
`collection = {currencies:Cash[], components:{collected:Receipt[], returned:Return[]}}`.
Its currency union is all dated selected facts, not all-date warnings.
`Cash = {currency, collectedPaise, returnedPaise, netPaise, categories}`.
`categories = {label, newMember, renewal, addon, unallocated}`; label is
`"Membership linkage (derived classification)"`; each category contains
`{collectedPaise, returnedPaise, netPaise}`. Sum the four categories for each Cash
field; net=collected-returned at every level. Return allocation unknown means the
unallocated category, with a separate `unknownReturnPaise` field in that category
only; it equals that category's returnedPaise, not an additional summand.
`Receipt = {paymentId, paidAt, amountPaise, currency, category, membershipEvidence}`.
`Return = {returnId, paymentId, processedAt, amountPaise, currency, category,
allocationUnknown, membershipEvidence}`. Category strings are presentation keys
`newMember|renewal|addon|unallocated`, not invented database statuses.
`membershipEvidence` null for addon/unallocated, otherwise `{createdAt,
hasEarlierMembership}`; no member/profile/name/contact/Auth id is exposed.
Earlier means strictly smaller created_at among same-member rows, not receipt dates; equal timestamps are not earlier and no id tie-break is permitted.
Arrived statuses paid/refunded/reversed contribute full receipt once at paid_at;
completed refund/reversal facts contribute independently once at processed_at.
Each timestamp lies in moneyRange's half-open boundaries and strictly before asOf.
Null dates go only to warnings. Receipt membership link takes classification
precedence; membership is newMember iff no earlier row exists, otherwise renewal;
whole part-payments/top-ups retain that membership nature. No periods_granted,
joined_on, first observed receipt or predecessor-only inference. Nonmembership
addon link is addon, neither link is unallocated. Returns use the original receipt's
category even outside selected payment dates; allocationUnknown is true exactly for unallocated returns. No original-sale-month restatement,
proportional allocation, conversion, recognition or current home-branch attribution.
Components sort by event instant then id; months and collection reconcile exactly
from these same returned components, with no independently selected mirror.

## Arrival exposure and branch comparison

`heatmap = {alignment, branches, reconciliation}`; alignment=`"Local time"`.
`branches: Branch[]`, same selected visible branch population, sorted by branchId.
`Branch = {branchId, zone, zoneSource, error, range, totalVisits, completedVisits,
currentDayVisits, excludedVisits, days, cells, week, availability, noEligibleDays}`.
zoneSource=`branch|gym`; invalid configured zone is preserved as zone text and
error=`{code:"invalid_branch_timezone"}` or `{code:"invalid_gym_timezone"}`.
Valid branch error=null; range=`{from,through,startsAt,endsBefore,cutoffAt,localToday}`
uses that branch's effective zone with inherited gym zone explicitly disclosed.
Invalid branch: range=null, numeric aggregates/week/noEligibleDays=null, availability=null, days/cells=[];
retain its branch entry and error in comparison; no fallback or silent dropping.
`days: Day[]`, one per selected local date, ascending, including zero/future dates.
`Day = {localDate, startsAt, endsBefore, isHoliday, excluded, state, visits, hours}`;
state=`completed|current|future` based on day boundaries and asOf. excluded means
holiday AND toggle on. visits counts all accepted arrivals in that day before asOf,
including excluded holidays; future visits=`"0"` with future state, not eligible zero.
`hours: {hour, exists, visits}[]`, ordered 0…23; exists means that local clock hour
exists under the zone on this date. Missing DST hour has no exposure; repeated
hour combines both occurrences and counts this date once. Hours sum to day visits.
Only recorded attendance branch/checked_in_at selects visits; no member-status,
home-branch, dwell-duration or offline-provenance substitution.
`cells: Cell[]` includes all 168 weekday/hour coordinates in coordinate order.
`Cell = {weekday,hour,arrivals,todayArrivals,eligibleDates,fraction,limited,message}`.
arrivals=sum(hour visits on nonexcluded completed dates with that coordinate);
todayArrivals=sum(nonexcluded current-day hour visits), never the fraction numerator.
eligibleDates counts those completed nonexcluded dates on which hour exists,
including zero-arrival dates. Fraction=arrivals/eligibleDates; limited iff eligibleDates<14; message null,
`"Unavailable"` for future-only, `"Limited history"` for current-only; otherwise `"No eligible days"` at zero, `"Limited history"` below 14, null at 14+.
`week = {arrivals,eligibleDates,fraction,limited,message}`: sum completed nonexcluded
date visits divided by completed nonexcluded date count (each date once), same
14-date threshold and Cell message priority. No averaging cell/branch averages, invented opening-hour history,
smoothing, pseudocounts or ranking of insufficient/unavailable populations.
totalVisits=completedVisits+currentDayVisits=sum all nonexcluded day visits;
excludedVisits=sum excluded day visits. completed/current component sums and
cell numerators/current counts must reconcile to the same returned day/hour rows.
availability=`unavailable` if all dates future, `partial` if any current/future, else `complete`. noEligibleDays iff some date is nonfuture and all nonfuture dates are excluded; future-only is unavailable, current-only exposes raw arrivals with no completed average.
`reconciliation = {complete,totalVisits,completedVisits,currentDayVisits,excludedVisits}`;
complete iff every included branch is valid. Counts sum corresponding branch fields
when complete; otherwise null, preventing an apparent organization total from
silently omitting errors. Below 14 dates, display raw counts/denominators with Limited history; prohibit normalized fraction display and common-scale encoding. Eligible common scales use the same exact unit.

## Elapsed classes and exact fractions

`classes = {branches, reconciliation}`; branch array sorted by branchId.
Each `{branchId,error,availability,summary,services,sessions,cancelledSessions}`; availability follows heatmap branch and errors follow
heatmap branch errors; invalid/future-only branch has summary=null and all three arrays empty.
Session date selection is selected branch-local dates, never payment dates;
standing scheduled sessions require endsAt<asOf, including holidays. EndsAt=asOf,
ongoing/future/cancelled sessions never enter the cohort; disabled services/trainers
never erase historical facts. Label “Elapsed non-cancelled sessions”.
`sessions: {sessionId,serviceId,sessionDate,startsAt,endsAt,capacity,bookedCount,
attendedCount,noShowCount,holdingBookings,bookedFill,markedPresence,markingCoverage}[]`
ordered sessionDate,startsAt,sessionId; each is an exact cohort drill row.
`cancelledSessions: {sessionId,serviceId,sessionDate,startsAt,endsAt}[]` contains
selected-date cancelled sessions with endsAt<asOf, sorted identically; no capacity/bookings.
`summary = Summary`; `services: {serviceId,summary:Summary}[]` sorted serviceId (cancelled exclusions restricted to that service),
using only returned cohort rows; service ids are necessary cohort identity, no trainer
or booking/member identifiers. `Summary = {cohortSessions,totalCapacity,
holdingBookings,attendedCount,noShowCount,unmarkedCount,cancelledSessionsExcluded,
bookedFill,markedPresence,markingCoverage,incompleteMarkingDisclosed,limited,message}`.
holdingBookings=booked+attended+no_show; unmarkedCount=bookedCount; cancelled
booking statuses contribute zero. Capacity is each stored session's capacity.
bookedFill=holdingBookings/totalCapacity; markedPresence=attendedCount/totalCapacity;
markingCoverage=(attendedCount+noShowCount)/holdingBookings. Summary totals sum
session rows; cancelledSessionsExcluded counts returned cancelled drill rows.
No-show holds a seat; never infer marking from gym attendance or elapsed time.
incompleteMarkingDisclosed iff unmarkedCount>0; limited iff cohortSessions<10;
message=`"Limited history"` when limited, otherwise null. Raw exact fractions stay
available; class cohort percentages/ranking suppressed below 10 elapsed sessions; mandated session drill fractions remain available.
Per-session raw fraction is still returned, not a reliable weak-class ranking.
`reconciliation = {complete,summary}`: complete iff every branch has nonnull summary; null summary if incomplete, otherwise
aggregate returned rows across branches, capacity weighted, never mean percentages.

Every fraction above has EXACT `{numerator,denominator,basisPoints}` keys; counts
are strings even at denominator zero. basisPoints=null at zero; display “No cohort”
(or exposure-specific excluded/zero “No eligible days”, future “Unavailable”, current raw “Limited history”). Otherwise half-up exact rounding:
floor((2*numerator*10000+denominator)/(2*denominator)); retain unreduced integers.
Reuse ratioBasisPoints/formatBasisPoints; two decimal percentage places, no float.
Limited-history displays show raw numerator/denominator; normalized heatmap/common-scale display below 14 and class cohort percentages below 10 are prohibited.
## Warnings, reusable seams and behavioral acceptance

`warnings = {scope,undatedPayments,undatedReturns,totals}`; scope=`"Current all-date"`.

 Adjudication (2026-10-04, orchestrator, runtime evidence): a COMPLETED
 return with a null processed_at is unreachable in the money domain -- the
 phase6 addon-sales refund guard couples the two in both directions
 (insert/update to `completed` stamps `processed_at := clock_timestamp()`;
 un-completion nulls it; both RLS-active and inactive paths). Every lawful
 insert path therefore yields a dated completed return, and the built
 envelope's always-empty `undatedReturns` content is the HONEST behavior.
 Suites SHALL pin the coupled invariant (completed implies processed_at
 stamped, and vice versa) and pin `undatedReturns` as empty under lawful
 staging instead of demanding rows for an impossible state; the warnings
 section and its scope disclosure remain part of the envelope.
Population: same authorized tenant/current snapshot, independent of range/branch/holiday; arrived paid/refunded/reversed with paid_at null, completed refund/reversal with processed_at null. No pending/failed/requested/processing rows or invented cutoff. Undated payment rows exactly `{paymentId,amountPaise,currency}`, return rows exactly
`{returnId,paymentId,amountPaise,currency}`, sorted id. `totals: {currency,
undatedPaymentCount,undatedPaymentPaise,undatedReturnCount,undatedReturnPaise}[]`
sorted currency, summed exclusively from those arrays; no dated collection contribution.
No added person identifiers, contact data, receipt text or claim details.

OccupancyRequest fields map to the four named SQL arguments; returned range replaces
client-echo boundary evidence. OccupancySnapshot's loose records are not a codec.
Reuse registered CollectionMonth/ClassificationBreakdown/ClassifiedCollection,
HeatmapCell/HeatmapExposure/BookedFillSummary only after reconciling their declarations
with these exact strings/nested fractions/coverage/drills; numeric-count aliases do
not satisfy OCC-011. Preserve ownerMetricsSchema/OwnerMetrics and MET behavior.
Reuse caller-session loadOccupancyAnalytics, OccupancyAnalytics/MetricsDashboard,
existing date/money/ratio primitives and Chalkline accessible ledger/empty/error states.
Search registry/code declarations and register any future exports/exact runtime codec
BEFORE implementation; this docs-only declaration adds none. No permissive record,
coercion, frontend default or request echo may conceal missing server facts.
Acceptance invokes the REAL four-argument public RPC under actual caller identity;
assert returned components, selection, exact arithmetic, snapshot, errors and cutoff
behavior. An independent mirror selector, helper-built aggregate, client rebuild,
stand-in RPC or separately refreshed drill cannot prove this contract. Presentation
may map names/format existing facts only. No source/test edits or acceptance claim here.
