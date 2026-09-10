# Phase 6 implementation order

**Status:** implementation planning only, audited against the repository on
2026-09-10. `docs/planning/phase6-draft.md` remains the accepted product
contract. This file identifies the facts that its OpenSpec change must freeze
before test authors are dispatched and orders the smallest working slices. It
does not authorize work before Phase 5 is green and archived.
The subsequent detailed contracts and their review status are indexed in
`phase6-contract-index.md`. Their frozen signatures replace suggestions in
this initial audit; do not implement an older suggested interface from here.

## Audit result

The accepted product choices are implementable on the existing schema, but the
draft is not yet an implementation contract. These gaps can otherwise produce
screens that look correct while money, identity or counts disagree:

1. The current access-token hook routes identities in the order platform,
   staff, member, but every product sign-in currently redirects to `/console`.
   The `(console)` layout accepts only a real `staff_id`. There is no member or
   platform layout, and an impersonating token deliberately has no `staff_id`.
2. `staffSession()` proves a real staff identity and tenant but does not return
   or check `app_role`. Every new mutation must have an explicit route role
   guard before its first database write; RLS remains the database boundary.
3. The add-on tables have shape checks and tenant-safe foreign keys, but no
   legal-transition enforcement, exact list-price check, sold-snapshot freeze,
   payment/order one-to-one rule, stock movement, session consumption or refund
   handover. A route that calls the existing payment endpoint and then writes an
   order would leave a paid orphan whenever the second write fails.
4. The legal graphs for add-on orders, PT sessions, leads, notifications and
   organizations are documentation only. Phase 6 is the first mutator and must
   enforce them in PostgreSQL before exposing the routes.
5. OPEN-010 is not closed by the current comms schema. `consents.recorded_at`
   still trusts a supplied value, equal timestamps have no documented tie-break,
   and only the unique notification key exists; no renewal-key grammar or
   scheduler owns creation. The seam fixes the intended consent ordering: a
   member-row lock, a strict server timestamp, and a sender that takes that same
   lock then reads consent freshly before sending.
6. `member_imports` stores results but no durable preview identity. Confirmation
   therefore has no specified way to prove that it is importing the file and
   mapping the owner or manager just reviewed. Upload byte and row limits are
   also absent, and the web package has no `.xlsx` parser.
7. MET-001/MET-008 cannot be met by independent card and drill-down HTTP reads.
   Passing the same `asOf` does not recreate an earlier MVCC snapshot when a
   status or timestamp is updated. Supabase's default row cap would also make a
   client-side sum silently wrong, and JavaScript `number` cannot preserve every
   PostgreSQL `bigint` aggregate.
8. Organization status is currently a writable label. The hook does not consult
   it, changing it revokes no gym sessions, the graph is not enforced, and a gym
   owner policy can currently reach every organization column, including tier,
   status, trial and activation fields.
9. ONB-001 crosses five tables. Four are writable by super admin under existing
   policies, while `messaging_wallets` is deliberately read-only to every
   `authenticated` session. Onboarding and wallet adjustment therefore need
   narrow database-owned write boundaries; sequential Route Handler inserts are
   not atomic.
10. ONB-003 currently copies `pause_approver_role=gym_manager` for all presets,
    while ONB-001 creates only a `gym_owner`. Approval requires the exact
    configured role, so a new gym would have nobody who can approve a pause.
    ADR-111 resolves the initial value to `gym_owner` for all three presets; the
    owner may select `gym_manager` after that staff identity exists. GL021 still
    requires distinct requester and approver, so this does not promise solo
    approval for an onboarding owner.

One sentence in the accepted draft also overstates current authorization.
`pt_sessions_tenant_write` uses `app.is_staff()`, so owner, manager, front desk
and trainer can write the table. This existing policy is useful for ADD-010,
because the front-office sale creates the first slot. Keep that database gate.
The product route for later scheduling/completion may require `trainer`
explicitly, but the OpenSpec must call that a route restriction and must not
claim that RLS is trainer-only.

## Existing rules to reuse unchanged

| Area | Current database fact | Phase 6 use |
|---|---|---|
| Tenant references | ADR-052 replaced cross-table UUID foreign keys with composite `(tenant_id, id)` foreign keys. | Never add route-side tenant lookups as a substitute. Supply the claim tenant and let the composite keys reject cross-gym product, member, payment, trainer, branch and notification references. |
| Staff reads/writes | Catalogue writes use `app.is_gym_admin()`; order writes use `app.is_front_office()`; PT-session writes use `app.is_staff()`; leads/consents use `app.is_front_office()`; imports use `app.is_gym_admin()`. | Preserve these policies. Route guards give a clear 403 before a write and may be narrower for a particular product action. |
| Member access | A member policy can read all `addon_products` rows for their gym, including an inactive product needed by old order history, and only their own orders, sessions, notifications, consents, payments and member row; a member writes no table directly. | The browse query explicitly filters `is_active=true`; history may still resolve an inactive product. Member pages use the member's own Supabase session. A member-state mutation needs a narrow RPC behind a Route Handler rather than a new general table-write policy. |
| Platform access | `platform_support` reads across tenants and writes none; only `super_admin` satisfies platform write policies. Wallet, wallet ledger and audit log still withhold write grants from all authenticated roles. | Platform layouts admit both roles; every mutator requires super admin explicitly. Use a narrow definer only where the existing grant intentionally prevents the needed write. |
| Money arrival | Payments already enforce the canonical status graph, actor attribution, provider/manual separation, immutable paid facts, receipt numbering and net-price period grants. Paid history is `paid`, `refunded` or `reversed`; refunds/reversals remain separate rows. | An add-on sale inserts an ordinary manual payment inside its transaction and lets the existing payment triggers stamp and audit it. It does not reproduce receipt, actor or payment-transition logic. |
| Retry keys | Payments currently have unique `(tenant_id, idempotency_key)`; the accepted Phase 5 exit adds the refund exact-replay RPC and `GL048` before this phase begins. | Do not interpret every `23505` as replay. Each Phase 6 command names its own key, exact comparison facts and conflict result. |
| Catalogue structure | Product stock is nonnegative; sessions used cannot exceed sessions bought; paid/nonzero orders need a payment; orders cannot be deleted; PT overlap is tenant-scoped and raises `23P01`; adjacent slots are valid. | Add only the missing behavior. Keep the exclusion constraint as the final authority on slot availability and map its named failure to `slot_unavailable`. |
| Comms structure | Consent rows and wallet ledger rows are append-only; notification keys are unique per tenant; wallets cannot be negative; notification/member references are tenant-safe. | Server-stamp new consents, use the existing unique key for scheduler replay, and move wallet balance only with an appended ledger row in the same transaction. |
| Identity | The hook resolves platform, then active staff, then eligible member. Impersonation yields `gym_owner`, tenant and `impersonation_session_id`, with neither staff nor member id. The existing own-session policy lets an impersonator end only that session and existing triggers audit start/end. | Never manufacture a staff id. Impersonation is a read-only gym preview enforced by an invoker BEFORE mutation trigger on authenticated-writable public tables, preserving reads and the exact own-session end exception. End it through the existing own-session update path, not a new elevated end RPC. |
| Jobs | `pg_cron` already runs the database-owned no-show job; its all-tenant function is executable only by `service_role`. | Use the same private scheduled-job posture for renewal creation. Do not add a user-callable scheduler endpoint. |

## Cross-cutting contract seam to freeze first

This seam is serial. Amend the Phase 6 OpenSpec and current specs, allocate
stable SQLSTATEs after `GL048`, then freeze them before any visible or holdout
author starts. Constraint names remain stable where PostgreSQL owns the error;
Route Handlers map both named constraints and project SQLSTATEs to stable API
codes. No handler treats an arbitrary `23505`, `23514` or `23P01` as success.

### Identity and route ownership

Add one claim classifier used by both layouts and API guards. It returns a
discriminated identity from signature-verified claims:

| Identity | Required claims | Home | Mutations |
|---|---|---|---|
| real staff | staff-side `app_role`, `tenant_id`, `staff_id` | `/console` | Only through a real-staff guard plus the route's explicit allowed roles. |
| member | `app_role=member`, `tenant_id`, `member_id` | `/member/add-ons` | No direct table write; only a member-specific Route Handler/RPC where the contract calls for one. |
| platform | `app_role=super_admin` or `platform_support`, no gym identity required | `/platform` | Read for both; mutations require `super_admin`. |
| impersonation | `app_role=gym_owner`, `tenant_id`, `impersonation_session_id`, no staff/member id | `/console` | Read-only preview plus ending its own session. No product mutation may invent or infer a staff actor. |
| unlinked/claimless | none of the complete shapes above | `/not-linked` | None. |

Suggested ownership is `apps/web/lib/identity.ts` for pure classification and
home selection, with `apps/web/lib/api.ts` retaining response envelopes and
wrapping it as `staffSession`, `memberSession`, `platformSession` and an
impersonation end guard. Extend `StaffSession` with its generated `app_role`
type. A small `requireRole` helper performs the explicit route check; it does
not create another exported role vocabulary.

Keep `(console)` for staff and impersonated gym reads, and add sibling
`(member)` and `(platform)` route groups. The console layout accepts either a
real staff identity or impersonation, displays the persistent red banner for
the latter, and leaves every existing/new staff mutation behind the real-staff
guard. Member and platform pages never live below the console layout.

`signIn`, the already-signed-in branch of `/sign-in`, `/`, and `/not-linked`
all use the same home selector. Land that selector only in the same slice as the
real `/member/add-ons` catalogue and `/platform` fleet pages, so no successful
login points at a placeholder or dead route. Starting impersonation refreshes
the session into the gym preview; ending it updates the caller's own session by
the existing policy, refreshes back to platform claims and returns to the gym
page.

Every Phase 6 mutation has one guard owner:

| Route | Required verified identity/role |
|---|---|
| `/api/add-ons` and `/api/message-templates` | real staff; owner or manager |
| `/api/add-on-orders`, `/api/leads`, `/api/leads/[leadId]`, `/api/leads/[leadId]/convert`, `/api/consents`, `/api/notifications/[notificationId]/open-whatsapp` | real staff; owner, manager or front desk |
| `/api/add-on-orders/[orderId]/sessions` | real staff; trainer for later schedule/status actions; the sale RPC separately creates the initial slot for front office |
| `/api/member-imports` | real staff; owner or manager |
| `/api/member/notifications/[notificationId]/delivered` | member; the notification must be the claimed member's own row |
| `/api/platform/gyms`, `/api/platform/gyms/[gymId]/status`, `/api/platform/gyms/[gymId]/tier`, `/api/platform/gyms/[gymId]/owner-link`, `/api/platform/wallet-adjustments`, `/api/platform/impersonations` | platform; super admin only |
| `/api/impersonation/end` | the impersonating identity; only the session id in its own verified claim |

`/api/message-templates`, the member delivery endpoint, the tier endpoint and
both impersonation endpoints are required route seams missing from the accepted
draft's mutation lists. They close behavior the EARS already requires; they do
not add a new product surface.

### RPC and privilege convention

- Use ordinary Route Handler writes for one-table commands. The handler parses
  a `packages/shared` zod schema, identifies the caller, checks the exact role,
  derives tenant/actor, then writes with that caller's Supabase session.
- Use a `public` `security invoker` RPC when one command must commit several
  caller-writable tables atomically: add-on sale, lead conversion and import
  commit. RLS, grants, existing triggers and composite foreign keys remain in
  force. Revoke default execute from `public` and `anon`, grant
  `authenticated`, and check the required `app_role` inside the function as
  well as in its Route Handler.
- A `security definer` routine is allowed only for the deliberately withheld
  capability it owns: product stock movement from an accepted sale, member
  delivery acknowledgement, wallet movement/audit, onboarding/owner lookup,
  organization status audit/session revocation, and database audit writers.
  Put private trigger helpers in `app`, set `search_path=''`, fully qualify all
  objects, revoke direct execution, derive the actor from verified claims and
  repeat the exact authorization check inside any callable definer. Do not make
  the add-on sale itself a broad definer.
- Read-only aggregation RPCs are `security invoker`. They use one SQL statement
  so all CTEs share one MVCC snapshot and the underlying RLS remains active.
- Every retryable command accepts a server-validated UUID request key. Exact
  replay returns the original record id and changes no row, count, stock,
  session usage, receipt, wallet or audit event. Reuse with any different
  command fact is `idempotency_conflict`. Concurrent equivalent requests
  converge on one result; concurrent conflicting requests have one database
  winner and one conflict without promising which wins.

### Add-on money and usage invariants

Freeze all of the following before the add-on test authors start:

1. Add `addon_orders.idempotency_key` with a tenant-scoped partial unique index
   and exact-replay semantics. Store a UUID form nonce in canonical lowercase
   text; derive a namespaced payment key from it so a sale cannot collide with
   a standalone payment command. Replay facts are member, product, quantity,
   trainer and initial slot. Add a unique partial payment reference so one
   payment cannot fund two orders. New orders also carry a claim-stamped
   `sold_by_staff_id`; historical null actor values may remain if they cannot
   be derived unambiguously, but new sale writes may not be anonymous.
2. At the sale, derive product, member, tenant, unit price, currency, validity,
   trainer and session total. Require `total_paise = unit_price_paise * quantity`
   in PostgreSQL with checked bigint arithmetic. Once an order first leaves
   pending, freeze its id, tenant, member, product, payment, quantity, all
   price/currency fields, trainer, session total and validity snapshot, and
   server-stamp immutable `sold_at`. Catalogue edits never rewrite sold orders.
   A zero-total order uses that same boundary because it has no payment to
   provide the ordinary freeze point.
3. The linked payment must be the same tenant and member, exactly equal the
   order total/currency, represent money that entered `paid`, name no membership,
   and fund no other order. The Phase 6 route accepts only the existing manual
   methods; existing payment rules reject provider-shaped desk rows.
4. `public.record_addon_sale(...)` is `security invoker` and orders statements
   so a product stock row is locked and checked, or a PT pending order and first
   session pass the existing overlap exclusion, before the payment insert. It
   then inserts the ordinary payment and advances the order one legal edge at a
   time. Any failure rolls back order, session, payment, receipt and stock.
5. Front office cannot update `addon_products` under the admin-only catalogue
   policy. An uncallable `app` definer trigger owns only the conditional stock
   decrement when an accepted product order first enters `paid`. It uses one
   `UPDATE ... WHERE stock_quantity >= quantity RETURNING` under a row lock and
   raises `insufficient_stock` when no row moves. It never edits price or other
   catalogue fields, and replay never fires it again.
6. Preserve the existing `app.is_staff()` PT-session write policy. The sale RPC
   uses it to create the front-office first slot. The later sessions Route
   Handler explicitly admits `trainer`; this is the narrower product route, not
   a narrower RLS claim. A trainer may create or change only sessions assigned
   to their verified staff id, with both OLD and NEW assignment checked on
   UPDATE. Every PT session must reference an order whose product kind is
   `pt_package` and equal that order's frozen member and trainer identities;
   owner, manager and front office retain
   their existing administrative table access.
7. Enforce the documented add-on and PT graphs in database functions. Only
   `scheduled -> completed` increments usage, exactly once. Cancelled/no-show
   consumes none. The last consumption advances an active order to completed;
   a retry observes the already-completed session and changes nothing.
8. A completed refund/reversal linked through the order payment moves only a
   `paid` or `active` order to `refunded` when completed returned money equals
   the payment amount. Partial return and return after terminal `completed`
   remain visible without changing the order. A completed refund must carry
   `processed_at`, because both the handover and MET-004 use that instant.
9. The free-add-on path is fixed. The schema permits a zero price while payments
   require a positive amount. A zero-total order creates no payment or receipt,
   retains its seller/request key and snapshots, server-stamps `sold_at` when it
   leaves pending, still decrements physical stock or creates the first PT slot,
   contributes zero revenue, and follows the same usage graph. Complimentary PT
   cohorts use `sold_at`; positive-price PT cohorts use the linked payment's
   `paid_at`. Missing historical acceptance evidence remains explicit null and
   undated rather than being invented or assigned to an arbitrary cohort.

### Other missing database invariants

- Leads need their documented transition function plus conditional facts:
  trial stages require `trial_at`, lost requires a trimmed reason, converted
  requires member and server conversion time, and terminal leads cannot be
  changed or relinked. `public.convert_lead(...)` locks one lead, returns its
  existing member on exact retry, creates at most one member under the existing
  tenant-phone key, and exposes only a same-gym phone match as an explicit link
  choice.
- Import confirmation must bind to the exact preview. Use a server-computed file
  digest plus canonical column mapping and a request key; confirmation reparses
  and renormalizes the submitted file and refuses if its digest/mapping differs
  from the preview. The contract must set numeric byte and row caps and select a
  maintained `.xlsx` parser before tests. Do not load an unbounded workbook into
  a Route Handler. The commit RPC owns the run lock, inserts only validated rows,
  rolls back member writes on a processing exception, and still records a
  failed run with its report through a contained subtransaction. Authorization,
  policy and cross-tenant failures propagate; they must not be swallowed as a
  failed import owned by the caller.
- Consent inserts need a member-row lock, a before-insert server stamp from
  `clock_timestamp()`, and a claim-stamped real staff actor. Each accepted
  decision is strictly later than the member/purpose's last `recorded_at` by one
  database timestamp tick when necessary; current consent is ordered by
  `(recorded_at desc, id desc)`, with id resolving historical ties only, and the
  supporting index must carry the same order. The sender takes the same
  member-row lock and reads current consent in a fresh command before its send
  decision, so a serialized withdrawal wins. Impersonation cannot record
  consent because it has no staff id.
- Notification and organization graphs need database transition functions.
  State timestamps must agree with state: sent/delivered/failed and completed
  refund timestamps cannot be absent or client-backdated when that event is
  created by the product.
- A notification debit needs a unique notification-linked negative ledger
  movement, so retry cannot charge twice. Wallet update and ledger append share
  one locked transaction; balance remains equal to the starting balance plus
  its ledger. Existing seed data already provides matching opening ledger rows.
- Organization sensitive fields need a database guard: a gym owner may update
  permitted profile fields but cannot change status, tier, trial or activation.
  Enforce the canonical status graph, require a reason for suspend/reactivate/
  close, and audit the accepted change. Constrain tier structurally to null or
  `basic`, `growth`, `pro`; the labels remain manual and enforce no member cap.
- The access-token hook must issue fresh gym-side claims only for an `active`
  organization or a `trial` organization with a nonnull future trial end; it
  rejects pending approval, suspended, closed and expired/malformed trials while
  preserving its fail-closed claimless exception behavior. The status mutation
  deletes refresh sessions for linked staff and members using the existing
  identity-revocation pattern; current access tokens retain only the configured
  fifteen-minute residual and reserved `exp` stays unchanged. Super-admin
  impersonation remains available for suspended and closed gyms as an explicitly
  bannered support preview, with database-enforced read-only writes.
- Onboarding needs one command for organization, settings, one existing same-gym
  default branch, zero wallet and owner staff. It derives the six-character
  code, trial end at the start of the gym-local date fourteen days after
  onboarding, and preset values; every preset initially copies
  `pause_approver_role=gym_owner`, and the client cannot override those derived
  facts. No active-branch flag is an activation prerequisite. The callable
  boundary explicitly requires super admin and uses a narrow definer because
  wallet insert and auth-user lookup are intentionally unavailable through
  normal authenticated grants. Owner linking resolves one normalized exact email
  privately, never exposes the auth roster, rejects ambiguous matches and every
  platform identity, atomically sets the target gym as the user's protected
  `active_tenant_id` preferred tenant, revokes outgoing and incoming linked refresh sessions on a
  replacement (or the incoming user's on first link), and audits the link.
  Activation checks all prerequisites in the same status command.

### Renewal and dashboard arithmetic

Write the next-period remainder once in PostgreSQL and make both the renewal
job and dashboard call it. It uses the Phase 5 population and terms exactly:

`A = price_paise - discount_paise`

`R = eligible paid total - (periods_granted * A)`

`due = max(0, A - R)`

When `A = 0`, due is zero without division. Do not copy this arithmetic into a
Route Handler. Before the reminder author starts, also make one runtime the
source of the default reminder windows. Today they live only in
`RENEWAL_REMINDER_WINDOWS`, while an authoritative `pg_cron` SQL function cannot
import TypeScript. The OpenSpec must choose a database-readable representation
or an operator job that supplies that registered list; it may not silently
hard-code a second list in SQL.

The reminder job computes the gym-local day, checks the latest service consent,
uses key `renewal:<membership_id>:<ends_on>:<window_id>`, and relies on the
existing tenant/key unique index. An in-app reminder advances scheduled to sent
in the same job and debits no wallet. Push without configuration advances to
failed with `provider_unconfigured` and null sent/delivered times. A member read
is a client-triggered POST after the message is actually rendered; its narrow
definer RPC may update only the caller's own notification through a legal
sent-to-delivered edge. Add the missing `/member/messages` surface rather than
trying to make the staff `/messages` page serve members.

`public.dashboard_snapshot(range_start, range_end)` should be a read-only,
`security invoker`, single-statement SQL RPC that captures `statement_timestamp()`
once, computes gym-local `[start, end)` instants, and returns one JSON object
containing every card and the concise rows behind every drill-down. Clicking a
card switches among the already-returned components; it does not issue an
independent query that could observe a newer state. Returning one aggregated
object also avoids PostgREST's default 1,000-row truncation of source data. Every
bigint/numeric integer component and aggregate crosses JSON as a decimal string,
is validated as an integer string, and remains string/`BigInt` until display; no
aggregate passes through a JavaScript `number`. Nested read helpers are STABLE
and share the containing statement's snapshot.

Freeze these metric predicates in the OpenSpec:

- gym timezone, not branch or server timezone; `asOf` is server-captured and is
  not a user-selectable historical reconstruction;
- attendance by `checked_in_at`, live membership by inclusive local date, pause
  by an approved interval covering that date, and current red-list status;
- collected payment rows are statuses `paid`, `refunded` or `reversed` with
  `paid_at` in `[start,end)`; returned rows are completed refund/reversal rows
  with `processed_at` in that interval;
- renewal due selects current `ends_on` in the local date range and calls the
  shared remainder function;
- lead conversion denominator is `leads.created_at` in range and numerator is
  the converted subset of that same cohort, regardless of conversion date;
- add-on revenue is event-based like cash movement: linked payment `paid_at`
  inflow in range minus linked completed refund `processed_at` outflow in range;
  PT utilization cohorts non-refunded positive-price PT orders by linked
  payment `paid_at` and complimentary PT orders by immutable `sold_at`, then
  exposes both session sums. Missing historical acceptance evidence stays
  explicit null and undated. “Non-refunded” excludes a payment fully returned by
  completed refund/reversal rows even when ADD-012 keeps an already-completed
  order in its terminal `completed` status;
- each card is calculated from the exact component array returned beside it,
  including separate currency groups and zero denominators.

Use the same one-object pattern for the completed platform fleet snapshot after
all clusters exist. It returns gym rows and the exact exception/drill-down
components. Provider ready remains false until a real adapter and configuration
verification exists; a `razorpay_accounts` row or placeholder secret is not
evidence of readiness. OPS-001 uses MET-002's distinct live-membership
population, including approved pauses as separately labeled, and reuses that
predicate in the count, row component and activation/tier copy.

### Remaining decisions before author dispatch

ADR-111 may resolve these without another product-approval round, but each
answer belongs in the frozen OpenSpec rather than in an implementer's code:

1. Resolved: a trainer may create or change only a PT session whose OLD and NEW
   `trainer_staff_id` equal the acting verified staff id; every session also
   references an order whose product kind is `pt_package` and equals its frozen
   member and trainer identities.
2. Resolved: zero-price add-ons are valid, create no payment or receipt, and
   use immutable `sold_at` for complimentary PT cohorts.
3. The member-import maximum bytes, maximum rows and maintained `.xlsx` parser.
4. The one database-readable source for default renewal window ids/offsets.
5. Resolved: super admin may preview suspended and closed gyms, with database-
   enforced read-only mutations, preserved reads and the exact own-session end
   exception. A genuine gym staff/member session is blocked either way.
6. Resolved: trial end is the start of the gym-local date fourteen days after
   onboarding; activation requires settings, exactly one same-gym default branch,
   an active linked non-platform owner, recognized IANA timezone, and INR.
7. Resolved: OPS-001 active members uses MET-002's distinct live-membership
   population, with approved pauses separately labeled.
8. Resolved: an owner link rejects platform identities, sets protected
   `active_tenant_id` preferred tenant, revokes old and new linked refresh
   sessions on replacement (or the new user's on first link), and directs the
   owner to sign in again after activation.
9. The historical backfill rule for `sold_by_staff_id`; new orders are always
   claim-stamped, but an old row with no uniquely attributable payment actor
   must remain explicit null rather than acquire an invented identity.
10. The historical wallet baseline if the cloud balance and ledger sum do not
    already match. The seed does match; this audit did not query the busy CI
    database. Any opening entry must be explicit and must not fabricate past
    notification sends.

## Prioritized vertical slices

Every row below means: freeze its OpenSpec section, write and commit visible
tests red, write the independent holdout suite where marked, then implement
without changing either suite. Database migrations are applied by CI only and
must finish before a later migration is pushed.

| Order | Minimum working slice | Required test-first contract | Completion evidence |
|---:|---|---|---|
| 0 | Finish, gate and archive Phase 5; open and freeze one Phase 6 OpenSpec change containing the seam above. | Contract review only. Allocate all Phase 6 SQLSTATEs/API codes and precedence among overlapping project-owned rules before dispatch. | No Phase 5 change remains in flight; current specs and registry are the source read by every author. |
| 1 | Identity routing plus real read surfaces: claim classifier, shared home routing, staff/member/platform layouts, `/member/add-ons`, baseline `/platform`, impersonation banner and own-session end. Add organization status to claim issuance/revocation only when its full blind tests are ready. | **Full blind for hook/status/impersonation.** Test every complete/incomplete claim shape, role-aware sign-in redirects, no dead target, database-enforced read-only preview with preserved reads and own end, cross-tenant RLS, active/unexpired-trial claim selection and the fifteen-minute residual. | Staff reaches console, member reaches a real catalogue, platform reaches a real fleet, unlinked reaches not-linked, impersonator sees gym plus banner and can return to platform. |
| 2 | Leads: `/leads`, create/update routes, transition invariant and atomic conversion/link choice. | Test role refusal before write; every graph edge and illegal edge; trial/lost/terminal facts; same-gym duplicate choice without cross-gym disclosure; serial retry and a true conversion race; list totals from identical filters. | New -> contact -> trial -> convert works from the screen; duplicate link is explicit and retry creates no member. |
| 3 | Import: upload/mapping/preview and one confirmation/commit path with downloadable report. | Freeze byte/row caps/parser first. Test CSV and first-sheet XLSX, normalization, all three duplicate classes, exact counters, preview digest mismatch, request replay, concurrent confirmation, rollback-to-failed report, cross-gym privacy and profiles-only writes. | A mixed file imports exactly the previewed rows once and its report/counts reconcile. |
| 4 | Comms core: consent history/current state, member messages/read acknowledgement, renewal remainder and scheduled in-app reminders, click-to-WhatsApp truthfulness, unconfigured push, wallet adjustment. | **Full blind for consent integrity, wallet and scheduler de-duplication.** Test strict server ordering, same-member lock/fresh sender read, withdrawal, exact key grammar/cycle rollover, job rerun/race, zero due, no wallet debit for free/failed channels, member self-only delivery, support/gym adjustment refusal, negative-balance race and one audit/ledger event. | `/messages` and `/member/messages` show one truthful lifecycle; cron rerun creates nothing extra; wallet balances to ledger. |
| 5 | Add-ons in three increments behind one frozen money contract: catalogue/staff+member browse; atomic product/diet/PT sale with receipt; later PT usage and refund handover. | **Full blind for the whole slice.** Test every item in the add-on invariant section, all legal/illegal graphs, exact replay/conflict and true concurrency, price edits after sale, cross-tenant references, complimentary `sold_at` cohorts, insufficient stock, PT overlap before payment, OLD/NEW trainer ownership, order member/trainer/kind equality, one payment per order, one stock/session movement, partial/full/terminal refund behavior, and existing payment/refund audit effects. | Journey C completes from member selection through staff payment to linked receipt and member usage; owner sees the same order; every retry is inert. |
| 6 | Owner `/dashboard` backed by the single snapshot RPC. | Test boundary instants around gym midnight, inclusive membership dates and pauses, paid-then-refunded histories, currencies, net-price residuals, zero values/denominators, more than 1,000 source rows, totals beyond JS safe integer, decimal-string serialization of every integer component/aggregate, STABLE helper snapshot consistency, and every card recomputed solely from its returned components. Include a concurrent mutation test proving one response is internally one snapshot. | Each clickable card switches to its exact rows and an independent integer/string sum equals the card. |
| 7 | Platform completion: exact fleet snapshot, onboarding, owner link, tier/status controls, wallet control, `POST /api/platform/impersonations`, `POST /api/impersonation/end` through the existing own-session policy, and gym detail. | **Full blind for identity, platform RLS and status.** Test support reads/writes, owner commercial-field bypass attempts, onboarding child failure atomicity, gym-code race, one existing default branch without an active-flag predicate, preset copy-once with the configured owner approver and GL021 two-person pause rule, later manager reassignment, unlinked activation, normalized owner lookup/platform rejection/protected preferred tenant/no auth roster leak, all organization graph edges, reason/audit, refresh revocation and impersonation across suspended/closed gyms. | One transaction creates every onboarding child or none; its owner is configured as pause approver for another authorized staff requester; activation cannot lie; support has no controls; fleet counts and exception rows reconcile. |
| 8 | Phase integration and archive. | Run the required gates once the last coherent unit is green, Journey C, role navigation for all identities, renewal cron evidence, dashboard/fleet reconciliation and the fresh-context critic. | Registry and generated types match CI, OpenSpec is archived, and no Phase 7 redesign entered the diff. |

## File and symbol ownership

- `packages/shared/src/api/` owns zod request/response schemas and exact integer
  string validation. It imports generated database types and stays platform-free.
- `packages/shared/src/config/constants.ts` owns application constants such as
  upload bounds once chosen. Do not create local copies in pages or handlers.
- `apps/web/lib/identity.ts` owns claim classification/home selection;
  `apps/web/lib/api.ts` owns API envelopes, session wrappers and explicit role
  refusal. Layouts own redirects and banners, not mutation authorization.
- `apps/web/lib/<cluster>.ts` owns direct RLS-backed reads and pagination. The
  dashboard/fleet helpers call their single snapshot RPC rather than assembling
  totals from paged queries.
- `apps/web/app/api/**/route.ts` owns mutation orchestration and stable error
  mapping. It never accepts tenant, actor, status, stock, usage, price snapshots,
  wallet balance or audit fields from the client.
- `supabase/migrations/` owns state machines, cross-row invariants, transaction
  RPCs, indexes, claim changes, audit triggers and cron schedules. Do not put
  transaction guarantees in React or a sequence of PostgREST calls.
- `docs/registry.md` registers every exported helper, type, schema, route, RPC,
  trigger function, view and constant in the same coherent unit.

## Schema and generated-type impact

At minimum Phase 6 changes `addon_orders` (request/actor identity and unique
payment use), consent ordering/stamping, wallet debit uniqueness, organization
tier/commercial guards, and the function catalogue. Import may need digest/key
columns once its preview contract is frozen. New RPC return shapes and any
columns alter `packages/db/types/database.ts`; it is regenerated from the linked
Supabase project only after CI applies each migration and is never hand-edited.
The implementation order must therefore serialize migrations and type
generation rather than letting parallel clusters generate against different
cloud schemas.

No phase should combine its red tests and implementation in one commit. Money,
RLS and identity slices keep independent visible author, holdout author,
implementer and fresh-context critic. The quieter CRUD slices still freeze the
spec and commit tests red before source. No author reads the holdout directory.
