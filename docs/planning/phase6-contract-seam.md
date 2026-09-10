# Phase 6 fixed cross-cluster decisions

Accepted under ADR-111, 2026-09-10. This supplements the accepted growth
contract and implementation inventory. It is planning while Phase 5 finishes;
Phase 6 source and OpenSpec work start after that archive. Authors must receive
these decisions together with their cluster's exact API contract before tests.

## Product decisions

| Decision | Fixed behavior |
|---|---|
| Trainer assignment | A trainer may create or change only PT sessions assigned to their own verified staff id; an UPDATE checks both OLD and NEW assignment. Every session must reference a PT order and equal that order's frozen member and trainer identities. Front office creates the initial slot in the sale RPC. The existing staff-wide PT RLS policy remains; a database claim invariant prevents a trainer changing another trainer's work, while owner/manager/front desk retain their existing administrative table access. |
| Complimentary add-ons | Zero-price products, diet plans and PT packages are valid. Record an attributed, keyed order and the normal stock/booking/usage effects; create no zero-valued payment or receipt. Freeze the sold snapshot when the order first leaves pending. Show “Complimentary” and zero revenue. |
| Catalogue disclosure | New active offers require nonempty description and cancellation terms, an explicit validity period, and PT trainer qualification text. Record qualification as a catalogue field; do not imply verification or invent a trainer credential. Old incomplete catalogue rows remain readable in history but cannot be sold until completed. |
| Impersonation targets | Super admin may preview suspended and closed gyms for support. It is a read-only gym preview with the existing session reason, hard expiry, banner and own-session end action. No inferred staff/member identity and no product mutation. Database enforcement also refuses direct authenticated table mutations carrying an impersonation claim, preserving existing reads and the exact own-session end exception. |
| Trial clock | Onboarding records trial end at the start of the gym-local date fourteen days after its onboarding date. At or after that instant the hook issues no new trial-gym claims, even before an operational status update. Existing access tokens retain at most the configured fifteen-minute residual; reserved exp is unchanged. The UI shows the local expiry and pending manual activation without claiming an instant token cutoff. |
| Identity selection | Preserve platform, staff, member precedence and deterministic tenant selection. Eligible gyms are active, or trial with a nonnull future trial end. Pending_approval, suspended, closed and expired/malformed trials are ineligible. Select another eligible active staff/member row using the existing requested-tenant/default order. If staff rows exist but none qualify, do not fall through to a member identity. |
| Claim cleanup | The hook removes its five Gymloop keys before resolving the current identity: app_role, tenant_id, staff_id, member_id, impersonation_session_id. Every success or fallback returns the cleaned claims plus only the newly resolved shape. Reserved Auth claims remain unchanged. This prevents refreshes carrying a stale gym identity after suspension. |
| Owner linking | Link an existing Auth user by normalized exact email, never expose an Auth roster. Refuse ambiguous email matches and users with any platform_users identity. Atomically set that user's protected active_tenant_id to the target gym. Revoke incoming and outgoing linked users' refresh sessions on replacement, or the incoming user's on first link. Show “Sign in again after this gym is activated”; do not claim an invitation was sent. An unchanged exact link is inert. |
| Settings completeness | Require a settings row, exactly one existing same-gym default branch, an active owner linked to an existing non-platform Auth user, a PostgreSQL-recognized IANA timezone, and a supported currency (INR in v1). Required settings are positive no-show threshold, valid streak rule/weekly goal, nonnegative check-in/grace/freeze limits, and an approver role for which an active staff row exists. Blank logo, GSTIN, street address and provider credentials do not block activation. |
| Fleet active members | Use MET-002's distinct live-membership population, including approved pauses as separately labeled, rather than profile status. Fleet and owner dashboards share that predicate and inclusive gym-local date boundaries. |
| Historical sellers | Backfill a sold order's seller only from its linked payment's nonnull same-gym recorded_by_staff_id. An ambiguous or unavailable actor remains explicit null. New orders require a real attributed seller. Never synthesize an actor for historical online payments. |
| Wallet baseline | Inspect live balance and ledger before changing behavior. If they match, add no opening entry. A mismatch requires a separately recorded, exact opening adjustment with an honest reason, never fabricated notification debits. No automatic repair is implicit in this contract. |
| In-app delivery | Reading a message means the member explicitly opens it or acknowledges it; merely prefetching a list does not claim delivery. Repeated acknowledgement leaves timestamps and audit unchanged. |
| Consent ordering | Serialize new consent decisions on the member row. Stamp each accepted decision from clock_timestamp(), making it strictly later than that member/purpose's last recorded timestamp by one database timestamp tick when necessary. Current state is ordered by recorded_at then id, both descending; the id handles historical ties only. A later withdrawal in the same transaction must win. No fabricated historical decisions. |

New orders gain immutable `sold_at`, server-stamped when first moving from
pending to paid, including complimentary acceptance. Positive-price PT cohorts
use the linked payment's paid_at; complimentary PT cohorts use sold_at and
contribute usage with zero revenue. Existing positive sold orders may derive
sold_at from their linked paid_at. Missing historical acceptance evidence stays
null and is reported as undated, rather than silently invented or counted in
an arbitrary period.

The initial owner is the configured pause approver for a request from another
authorized staff identity. Existing GL021 still requires different requester
and approver; onboarding one owner does not promise self-approval.

A read-only live inspection on 2026-09-10 found one messaging wallet: IronBox
holds 4500 credits and its ledger sums to exactly 4500. No opening correction
is needed. The later wallet migration must assert its expected baseline rather
than create a balancing entry by assumption.

PT usage needs the same narrow privilege treatment as stock: trainers may write
their sessions but may not directly update addon_orders. A private uncallable
definer may serialize and advance only the parent order from an accepted
session effect, with tenant/order/member/trainer and real-actor checks. Public
sale/session RPCs remain invoker. Supported add-on commands share a per-order
transaction advisory lock before row mutation; record_refund acquires that
same lock for an add-on-linked payment after its existing authorization check.
Arbitrary direct SQL may still encounter native deadlocks; atomic rollback and
retryable 40P01/40001 error handling are required, never a success response.

The preview write boundary is an invoker BEFORE mutation trigger on every
authenticated-writable public table except the existing tightly constrained
own-session end operation. It refuses impersonation claims while row security
applies, leaving reads intact. Any new callable definer separately rejects
impersonation before using elevated privileges. A metadata assertion prevents
future writable product tables from silently missing the preview guard.

The strict consent timestamp increment is one microsecond, PostgreSQL's stored
timestamp precision. It is a database representation rule, not a configurable
product delay. SQL documents it by name; no separate TypeScript constant is
needed unless the application consumes that precision.

## Renewal calculation and canonical windows

The database owns the next-period remainder used by both reminder creation and
metrics. One read-only STABLE invoker helper takes a membership row/identifier and computes its
net amount and eligible receipts using the same currency and arrived-payment
predicate as Phase 5. It returns integer decimal strings at the JSON boundary.
No JS number sum or second formula is used by the screens.

Default reminder windows become database-readable through a private immutable
SQL helper generated from the existing `RENEWAL_REMINDER_WINDOWS` constant in
`packages/shared/src/config/constants.ts`. That constant remains the single
authored source. Generate the migration payload from it rather than transcribing
the five offsets a second time, and add a drift check comparing the SQL payload
with the constant. Changing defaults later needs a forward migration generated
the same way. This never edits generated Supabase types. Initial values
remain expiry_minus_14=-14, expiry_minus_7=-7, expiry_minus_3=-3, expiry_day=0,
expiry_plus_3=3. A gym's explicit empty offset array disables reminders; null
uses the platform default. Custom offsets have ids expiry_minus_N, expiry_day,
or expiry_plus_N. Deduplicate repeated offsets before scheduling.

A run evaluates the current local calendar date once per gym. An offset is
eligible when localToday = ends_on + offset; reruns on that date are inert.
There is no unspecified catch-up policy that sends several missed stages on a
later day. Skip suspended/closed gyms, expired trials, cancelled/blocked/erased
members, cancelled/expired memberships, missing consent and zero due. A
scheduled row is checked again before becoming available; withdrawal marks it
opted_out without sending. Consent insertion and every send/availability
decision acquire the same member-row lock. The sender reads current consent
in a fresh command after acquiring that lock. Withdrawal preceding that
serialized decision prevents sending; existing sent messages remain history.
Jobs acquire multiple member locks in UUID order to avoid opposite lock order.

## Exact metrics response

Owner and platform snapshots are single-statement invoker RPCs. Each returns
one JSON object with asOf, timezone/date range, currency groups, cards and their
exact component rows. Cards switch to components already in that response;
a later database query cannot pretend to use the earlier transaction snapshot.
No source-row cap truncates aggregate input. Every bigint/numeric integer
component and aggregate is serialized as a decimal string, then formatted
through exact integer arithmetic. Nested read helpers are STABLE and share the
containing statement's snapshot; no VOLATILE helper may read newer rows during
snapshot construction.

The default owner range is the current gym-local calendar month through the
current instant. An explicit date range is inclusive in local calendar dates,
converted to a half-open instant range from start-day midnight to the next day
after end-day midnight. Visits today remain today's local-date measure even
when a historical money range is selected; labels disclose that distinction.
No-show and live-membership cards are current-state cards. Cash and recovery
cards use event times. Lead conversion uses the created-in-range cohort.

## Local appointment input

Lead trials, PT slots and follow-up scheduling show the gym timezone beside a
datetime-local field. The server converts the wall-clock text with that gym's
timezone, never the server/browser timezone. Nonexistent or ambiguous local
times are rejected with an actionable error; they are not silently shifted.
Use Temporal's documented reject disambiguation and overflow behavior via
`@js-temporal/polyfill`, pinned when installed. The repository has no existing
wall-clock-to-instant helper. See the primary
[Temporal ZonedDateTime reference](https://tc39.es/proposal-temporal/docs/zoneddatetime.html)
and [polyfill repository](https://github.com/js-temporal/temporal-polyfill).

Phase 6 closes OPEN-008 by adding this optional next-follow-up field to the
existing red-list action and a due filter. Reuse the existing follow-up schema,
append-only write and case derivation after converting to an offset-bearing
instant; do not create a second scheduling table or alter the outcome graph.

## Delivery constraints

Full blind authorship remains mandatory for identity, RLS, money, consent
ordering, scheduler de-duplication and wallet changes. Fix cluster signatures,
SQLSTATEs, replay comparisons and exact audit fields before author dispatch.
Shared identity/role/time helpers land first with working member and platform
read surfaces. Subsequent clusters build independently and land serially after
the preceding migration's CI completes. Every cluster ships its screen and
runtime evidence. These decisions do not move the Phase 7 visual redesign into
Phase 6.
