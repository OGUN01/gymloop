# Phase 6 owner and fleet metrics contract

Planning under ADR-111, implementing MET-001–008 and OPS-001/004. Read with
the fixed cross-cluster seam and communications contract. Source and tests
start only after Phase 5 archive and the preceding Phase 6 dependencies. The
named backend bar is PostgreSQL's statement snapshot: every displayed total
must be independently recomputable from the component rows in its response.

## Snapshot and access boundary

`public.owner_metrics(p_from date DEFAULT NULL,p_through date DEFAULT NULL)
RETURNS jsonb` is SQL STABLE SECURITY INVOKER with empty search path. Require
the existing gym-admin read identity (owner/manager or the authorized read-only
preview), derive the tenant from the verified claim, and reject other roles
with 42501 before looking up rows. No supplied tenant or asOf is accepted.
The wrapper and its read helpers use one containing SQL statement snapshot;
STABLE helpers must not query a newer snapshot. RLS remains enabled throughout.

`app.gym_metrics(p_tenant_id uuid,p_as_of timestamptz,p_from date,p_through date)
RETURNS jsonb` is the shared STABLE INVOKER read helper, callable by
authenticated/service_role inside authorized wrappers. It adds no privilege
and returns SQL NULL for an unreadable gym. Fleet aggregation may call it for
each visible gym in the same containing statement. No client may use its
asOf argument to claim a historical snapshot: the public product wrapper alone
sets asOf from statement_timestamp(). Historical ranges filter the current
snapshot's rows; they do not reconstruct old statuses.

Require both explicit dates or neither, from <= through, and a recognized gym
timezone. Invalid ranges/timezones fail with 22023, mapped to 422
`invalid_metrics_range` / `invalid_gym_timezone` respectively. No silently
substituted UTC/default timezone. Missing settings are separately reported by
fleet; they do not prevent date-based metrics when timezone is valid.

Default range begins at the first day of the current gym-local month and ends
at asOf, exclusive. Explicit ranges include both local dates, represented by
the half-open instant interval [from local midnight, through+1 local midnight).
Membership ends_on uses the inclusive local date range; the default date range
ends on gym-local today. Visits, live/paused members and open/due cases remain
current-state cards regardless of the selected historical range. Labels state
this. The response includes both calendar dates and actual boundary instants.

No source-query row cap, client sum of independently fetched pages, materialized
counter or separately refetched drill-down is permitted. The SQL aggregates
and components are produced from the same CTE populations. PostgreSQL numeric
is used for sums/products, including intermediate expressions; integer JSON
values are canonical decimal strings. UUIDs/dates/timestamps remain strings,
booleans remain booleans and missing facts remain explicit nulls. Screens use
BigInt/string arithmetic, never Number on money, counts or usage totals.

## Exact response

The object is exactly `{tenantId,asOf,timezone,localToday,range,cards,components,
warnings}`. range is `{from,through,startsAt,endsBefore,mode}` where mode is
`month_to_date` or `explicit`. Arrays are ordered by id ascending unless another
total order is stated below. Empty populations return empty arrays and zero
totals, never null aggregates. All returned row references are same-tenant.

cards is exactly:

```
{
  visitsToday, liveMembers, pausedMembers, openCases, followUpsDue, recovered,
  cash: [{currency,collectedPaise,returnedPaise,netPaise}],
  renewal: [{currency,duePaise}],
  leads: {converted,total},
  addonCash: [{currency,collectedPaise,returnedPaise,netPaise}],
  pt: {sessionsUsed,sessionsTotal,orders}
}
```

Currency arrays sort by currency. Their currencies are the union present in
their respective component rows, including a zero-valued due row. An empty
cash population has no invented INR row; the UI may show “No cash movement”.
Ratio cards show their numerator and denominator; denominator zero displays
“No cohort” and no percentage. If a percentage is displayed, use exact integer
basis points rounded half-up (ratio*10000, quotient/remainder), formatting two
decimal places; do not imply that utilisation or conversion uses a hidden
denominator. Components remain the authoritative exact fraction.

components has exactly the arrays in the following table. Card names sharing
a population use the same rows, filtered by the stated boolean, rather than
duplicating an independently queried array.

| Array and row fields | Exact population and derivation |
|---|---|
| visits `{attendanceId,memberId,memberName,checkedInAt}` | Attendance checked_in_at in today's half-open gym-local day. visitsToday = row count, including two accepted visits by one member. |
| liveMembers `{memberId,memberName,memberships,paused}`; memberships = `{membershipId,status,startsOn,endsOn,pauses}`; pauses = `{pauseId,startsOn,endsOn}` | Distinct members with at least one active/frozen membership whose nonnull inclusive dates cover localToday. Return each qualifying membership once. pauses contains approved pauses covering localToday for that membership. paused is true if any such pause exists; pausedMembers counts distinct live rows with paused=true. Profile status alone neither creates nor removes this membership-based population. |
| cases `{caseId,memberId,memberName,status,nextFollowUpAt,due}` | Status open/contacted/follow_up_due. due means nonnull next_follow_up_at <= asOf. openCases = all rows, followUpsDue = due rows. |
| recoveries `{caseId,memberId,memberName,returnedAt}` | Nonnull returned_at in the selected instant range, irrespective of current case status. recovered = rows. |
| collected `{paymentId,memberId,memberName,amountPaise,currency,paidAt,receiptNumber,addonOrderId}` | Payment status paid/refunded/reversed with nonnull paid_at in range. Amount is full accepted payment, never reduced in this row by a refund. The Phase 6 unique order/payment reference gives zero or one addonOrderId. |
| returned `{refundId,paymentId,memberId,memberName,amountPaise,currency,kind,processedAt,addonOrderId}` | Refund status completed with nonnull processed_at in range. Includes refund and reversal kinds, independently of original payment date and current payment status. |
| renewals | COM's exact `app.membership_renewal_remainder` result for every membership whose nonnull ends_on is in the inclusive selected local dates; no second formula and no extra status filter. Include memberName alongside that object. Zero-net entries remain visible as zero due. |
| leads `{leadId,fullName,createdAt,stage,convertedMemberId,convertedAt,converted}` | Lead created_at in selected instant range. converted means current stage=converted; conversion need not have happened in that range. Numerator counts converted rows, denominator all cohort rows. |
| ptOrders `{orderId,memberId,memberName,productId,trainerStaffId,status,cohortAt,cohortSource,sessionsUsed,sessionsTotal}` | PT orders status paid/active/completed whose cohort instant is in range, with known positive sessions_total and no full completed return of the linked payment. Positive orders use linked arrived-payment paid_at; complimentary orders use sold_at. cohortSource is payment or complimentary_sale. Exclude refunded/cancelled/pending and full-return completed orders. Expired-by-date active entitlements remain purchase-cohort history; expired is not an order status. |

cash groups collected and returned independently by their explicit currencies;
net is collected minus returned. addonCash uses those exact same collected and
returned arrays, restricted to nonnull addonOrderId. It does not require an
order to remain active or its original payment to be in the refund's period.
renewal groups the helper's duePaise. pt sums each included order's lifetime
usage and bought sessions; it is a purchase-cohort utilisation measure, not
sessions occurring during the selected range.

warnings is exactly `{undatedPayments,undatedReturns,undatedPtOrders,incompletePtOrders}`. Each
array lists all otherwise relevant same-gym rows whose missing event evidence
prevents assigning them to any range: payment `{paymentId,amountPaise,currency}`
for arrived status without paid_at; refund `{refundId,paymentId,amountPaise,
currency}` for completed without processed_at; PT `{orderId,status}` for the
eligible order-status population without its required cohort instant. They
never contribute to a dated card and must not silently disappear. Display
these as separate data-quality links with current, all-date scope.
incompletePtOrders contains `{orderId,status,cohortAt,sessionsUsed,sessionsTotal}`
for otherwise eligible PT orders with null sessions_total, preserving that null.
These all-date warnings contribute neither usage, denominator nor orders to
the utilisation card. The UI labels the fraction as the known-session cohort
and visibly links the excluded incomplete rows; it invents no bought sessions.

## Fleet reuse

`public.fleet_metrics() RETURNS jsonb` is SQL STABLE INVOKER, platform read
roles only, with one statement_timestamp() and no tenant/date parameters.
Return exactly `{asOf,gyms,exceptions}`. Each gym is `{tenantId,name,gymCode,
status,tier,timezone,trialEndsAt,activeMembers,openCases,failedNotifications,
settingsComplete,missingSettings,ownerAccessPending,providerReadiness,
metricsError,components}`. Gyms sort by name then tenantId. Readiness uses the
shared helper below, also consumed by platform activation. All counts
are decimal strings; providerReadiness remains verified false for the channels
without an implemented adapter, never inferred from a secret-shaped row.

Each gym's components contains `{liveMembers,cases,failedNotifications}`.
The first two are the exact shared owner populations; failed notifications
are `{notificationId,memberId,channel,failedAt,failedReason}` for current
status=failed, all dates, with failedNotifications equal to their count.
Use the owner's shared population helper/CTEs rather than a second authored
membership predicate. A malformed timezone produces an explicit gym metrics
error `metricsError:{code:"invalid_gym_timezone"}` and null activeMembers and
components.liveMembers with a settings exception, never a fake zero or
failure of the entire fleet. openCases/failedNotifications remain countable.
The owner page itself fails its metrics read explicitly for that invalid zone.
Valid gyms have metricsError=null. A shared STABLE invoker live-population
helper takes a nullable local date: null returns SQL NULL, not an empty array;
otherwise it owns the one membership/pause predicate. Fleet validates the zone
before constructing that date and never calls the failing owner wrapper. The
owner helper and fleet reuse that same population helper and common case rows.

exceptions is `{settingsIncomplete,ownerAccessPending,providerUnavailable,
trialExpired}`; each is an id-sorted array of tenant UUIDs derived exclusively
from the returned gyms and captured asOf. trialExpired means status=trial and
null or <=asOf trialEndsAt. providerUnavailable means at least one of the
documented provider channels is unavailable. Selecting any exception filters
that same response's gyms; no second snapshot supplies the apparent count.

`app.gym_readiness(p_tenant_id uuid) RETURNS jsonb` is a STABLE narrow read
DEFINER with empty search path. Admit platform read roles or a same-tenant
staff/authorized preview read identity before lookup; return SQL NULL for an
unreadable/absent gym. It exposes no Auth roster or email lookup. Its sole
elevated read is determining whether an active owner staff row's linked
auth.users id exists and has no platform_users identity, a fact ordinary gym
RLS cannot establish. Return exactly `{settingsComplete,missingSettings,
ownerAccessPending,providerReadiness}` in the same statement snapshot.

missingSettings is an ordered array of failing keys from:
`settings,default_branch,owner_access,timezone,currency,no_show_threshold,
streak_rule,weekly_goal,checkin_window,grace_period,freeze_limit,pause_approver`.
Default branch requires exactly one existing is_default branch, owner_access
the linked eligible active owner above, timezone a pg_timezone_names entry,
currency INR; the remaining settings use the schema's positive threshold,
canonical streak rule, weekly goal 1–14, nonnegative check-in/grace/freeze limits
and an active staff row with the configured approver role. If settings is
absent, report settings and skip its seven dependent field keys; still evaluate
branch/owner/timezone/currency. settingsComplete means no missing keys;
ownerAccessPending means owner_access fails. This does not promise solo pause
approval: GL021's distinct requester/approver rule remains.

providerReadiness is exactly `{push:{ready:false,reason:"provider_unconfigured"},
sms:{ready:false,reason:"outside_v1"},email:{ready:false,reason:"outside_v1"},
whatsappBusiness:{ready:false,reason:"outside_v1"}}`. Free in-app and
user-assisted WhatsApp links are described separately, not as provider-backed
sending. Implement/register this read helper with metrics; platform activation
reuses it when its mutations land. Narrow helper grants and auth-table access
need independent security tests, including cross-tenant and claimless callers.

## Routes and verification

Owner `/dashboard` admits real owner/manager and the authorized preview read
identity. Its read loader calls the invoker RPC directly through the caller's
Supabase client, following the architecture's read path; add no read-only Route
Handler. Support uses fleet, not a fabricated gym identity. Dates use `from`
and `through`; absence of both means month-to-date. The loader validates the
exact response and exposes safe mapped errors to the screen. Changing the
range explicitly fetches a new snapshot; selecting a card only changes the
visible component table. Large component arrays may paginate in memory after
receipt, with total and snapshot identity preserved. No separate SQL page
can be represented as a continuation of the old snapshot.

Full independent visible/holdout tests cover the money predicates, all exact
integer serialization including aggregates beyond JS safe integer, same-time
events, refund-only ranges, zero denominators, complimentary and undated PT,
inclusive membership/pause dates, timezone midnight/DST boundaries, counts
over the PostgREST row cap, cross-tenant reads and invalid roles. A true
concurrent update experiment must establish that every card reconciles from
its own returned components, with no claim that two requests see equal data.
Browser evidence recomputes each rendered card from that response, demonstrates
range changes and same-response drill-downs, and retains honest missing-data
and provider states. Registry records every helper, schema, route and constant.
