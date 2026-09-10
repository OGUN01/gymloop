# Phase 6 add-on sale and fulfilment contract

**Status:** normative freeze under ADR-111 and ADR-116, 2026-09-10. This fixes
Cluster A of `phase6-draft.md`, inheriting `phase6-contract-seam.md`. Start its
OpenSpec/tests only after Phase 5 is green and archived and this contract is
reviewed. It changes no source, tests or database by itself.

## Scope and adopted decisions

Deliver `/add-ons`, `/add-ons/orders/[orderId]` and `/member/add-ons`: publish
an offer, explicitly select it, take a verified desk payment or accept a
complimentary offer, deliver the product/diet/PT service, and inspect the same
order, receipt, usage and returned money. Members select by carrying the offer
to the desk; they create no order or payment. Nothing is pre-selected.

Reuse ADD-001–013, MNY-001–005, PAY-005–011, INT-001/003, DQA-004/005;
`catalogue`, `manual-payment`, `payment-record` and the Phase 5 refund contract.
The existing enum labels, tenant-composite foreign keys, grants, RLS,
`app.stamp_payment()`, receipt counter, payment enforcement, period-grant
trigger and `app.audit_money_change()` remain authoritative. Add-on payments
name no membership, so they grant no membership period. No coupon, proration,
tax calculation, GST invoice or provider integration is introduced.

Under ADR-111 the additional decisions are:

- Product quantities are positive integers; PT and diet quantities are exactly
  one. All v1 sales use INR and full catalogue list price; zero is permitted.
  Non-INR offers are refused as unsupported_currency; no conversion or tax is invented.
- Validity starts on the acceptance date in the gym timezone, inclusive;
  expiry is `starts_on + validity_days - 1`. A product is handed over during
  this sale and reaches completed immediately. A diet plan has an explicit
  front-office completion action. Expiry is a derived label, never a new enum
  value or an invented active-to-cancelled transition.
- New active offers require the full disclosure below. Legacy incomplete
  offers remain readable but cannot be sold. Qualification is the gym's own
  stated text; neither the application nor migration invents accreditation.
- A sale form carries the catalogue `quote_version` it displayed. A new sale
  against different offer terms is refused for review; stock changes alone
  preserve the quote and the atomic stock check still decides availability.
  Exact retry of an existing sale is resolved before looking at today's offer.
- Complimentary acceptance requires a nonblank reason; a paid sale may carry
  an optional note in that same field. Both become immutable request evidence.
- Scheduled PT sessions reserve purchased sessions: used plus scheduled may
  never exceed bought. Cancellation/no-show frees a reservation, consumes
  nothing and permits a new booking with a new session UUID.

## Exact schema additions

No new enum or transaction table is required. Existing columns and indexes stay.
All new nullable columns have no default so history is not fabricated.

| Table / column | Type and contract |
|---|---|
| `addon_products.trainer_qualification` | nullable `text`; trimmed nonblank for a new active PT offer |
| `addon_products.quote_version` | nonnull database-owned `uuid`; a new random UUID on insert or an actual offer-term change, as defined below |
| `addon_orders.sold_by_staff_id` | nullable `uuid`; composite `(tenant_id, sold_by_staff_id)` FK to staff; claim-stamped and required on every new sale order |
| `addon_orders.idempotency_key` | nullable `text`; canonical lowercase UUID text; required on every new sale order |
| `addon_orders.sold_at` | nullable `timestamptz`; server acceptance instant, frozen after first pending-to-paid edge |
| `addon_orders.sale_snapshot` | nullable `jsonb`; exact object below, required on every new sale order |
| `addon_orders.sale_request` | nullable `jsonb`; exact immutable RPC inputs below, required on every new sale order |
| `addon_orders.initial_session_id` | nullable `uuid`; composite tenant/session FK to `pt_sessions`; filled before PT acceptance, otherwise null |

The database ignores client-assigned quote_version. It rotates on an actual
change to kind/name/description/price_paise/currency/validity_days/session_count/
trainer_staff_id/trainer_qualification/cancellation_terms/is_active only; stock,
sort_order, timestamps and unused GST metadata preserve OLD. Existing catalogue
rows receive a current UUID identifying today's offer, not historical disclosure.
No unique index is needed: compare the quote with its named product.

Create these exact indexes: unique partial
`addon_orders_tenant_id_idempotency_key_key(tenant_id,idempotency_key)` WHERE
key IS NOT NULL; unique partial
`addon_orders_tenant_id_payment_id_key(tenant_id,payment_id)` WHERE payment IS
NOT NULL; `addon_orders_sold_by_staff_id_idx(sold_by_staff_id)`;
`addon_orders_initial_session_id_idx(initial_session_id)`;
`addon_orders_tenant_id_sold_at_idx(tenant_id,sold_at)`; and
`pt_sessions_tenant_id_addon_order_id_status_idx(tenant_id,addon_order_id,status)`.
FK names are `addon_orders_tenant_id_sold_by_staff_id_fkey` and
`addon_orders_tenant_id_initial_session_id_fkey`. Use the existing parent
tenant/id unique keys; add the referenced key only if registry/source audit
proves it absent. Never replace a tenant-composite key with a global UUID FK.

`sale_snapshot` has exactly these keys, no extras: `kind` (generated enum),
`name`, `description`, `cancellationTerms` (nonblank strings),
`validityDays` (positive integer), `trainerQualification` (nonblank string for
PT, null otherwise). Kind is frozen here so a later catalogue kind edit cannot
reinterpret delivered stock or PT history. Existing order columns store price,
currency, trainer, sessions and dates, with no second arithmetic formula.

`sale_request` has exactly `memberId`, `productId`, `quantity`,
`quoteVersion`, `trainerStaffId`, `initialStartsAt`, `initialEndsAt`,
`method`, `reason`. UUIDs and instants are canonical database text; optional
values are explicit JSON null. The three trainer/slot values are null outside
PT. `method` is a manual enum label for a positive sale and null for a free
sale. `reason` is outer-trimmed, empty becomes null, and otherwise preserves
case, Unicode and internal whitespace. SQL validates the shape and equality
to the row/sale facts; clients cannot smuggle arbitrary JSON into either field.

Backfill only `sold_by_staff_id` from the linked payment's nonnull same-gym
`recorded_by_staff_id`, and positive sold orders' `sold_at` from linked
`paid_at` when actual arrival evidence exists. Leave unavailable actors/dates,
all historical keys, snapshots and initial-session pointers null. Do not infer
old disclosure terms from today's catalogue. Historical duplicates that would
block the new payment key require a recorded reconciliation decision before
migration, never deletion or automatic reassignment. No live DB inspection is
part of this planning task; CI owns the currently busy Cloud project.

## Callable commands and wire schemas

The five mutation RPCs below are VOLATILE, SECURITY INVOKER, SET search_path=''; revoke
PUBLIC/anon execute, grant authenticated. It derives tenant and actor from
verified claims, rejects impersonation, and checks its named role before any
lookup. No tenant, seller, price, usage, stock or payment status argument is
accepted. Cross-tenant/missing target is the same `not_found`, never an existence
oracle. All JSON bigint amounts, including list/detail reads, are decimal
strings; never pass them through JS Number. SQL computes multiplication with
checked bigint arithmetic; overflow is refused, no rounding is performed.

```sql
public.record_addon_sale(
  p_member_id uuid, p_product_id uuid, p_quantity integer,
  p_quote_version uuid, p_trainer_staff_id uuid,
  p_initial_starts_at timestamptz, p_initial_ends_at timestamptz,
  p_method public.payment_method, p_reason text, p_idempotency_key uuid
) returns table(order_id uuid, payment_id uuid,
                initial_session_id uuid, replayed boolean);

public.schedule_pt_session(
  p_order_id uuid, p_session_id uuid, p_starts_at timestamptz,
  p_ends_at timestamptz, p_notes text
) returns table(session_id uuid, order_id uuid, replayed boolean);

public.finish_pt_session(
  p_session_id uuid, p_status public.pt_session_status
) returns table(session_id uuid, order_id uuid,
                session_status public.pt_session_status,
                order_status public.addon_order_status, replayed boolean);

public.complete_addon_order(p_order_id uuid)
returns table(order_id uuid, order_status public.addon_order_status,
              replayed boolean);

public.complete_manual_addon_refund(
  p_refund_id uuid, p_expected_amount_paise bigint,
  p_expected_currency text, p_expected_reason text
) returns table(refund_id uuid, order_id uuid,
                refund_status public.refund_status,
                order_status public.addon_order_status,
                processed_at timestamptz, replayed boolean);
```

Member returned-money disclosure uses one deliberately narrow read boundary:

```sql
public.read_member_addon_returns(p_order_id uuid) returns jsonb;
```

It is STABLE, SECURITY DEFINER, postgres-owned, and has an empty search path.
PUBLIC/anon execute are revoked and authenticated execute is granted. Before
lookup it requires the complete verified NAV member shape: valid subject,
tenant and member UUIDs, role `member`, and no staff or impersonation claim.
Every other identity is `42501`; after authorization a null argument is `22023`.
The named order and any linked payment must independently equal the claimed
tenant/member. Missing, foreign or inconsistent order/payment linkage is the
same `P0002` result. It uses only fully qualified static reads and has no write,
lock, audit or trusted-caller path.

Its one JSON object has exactly `orderId` and `returns`. Each return has exactly
`refundId`, `kind`, `amountPaise`, `currency`, `processedAt`; kind preserves the
row's generated `refund_kind` value (`refund` or `reversal`),
amount is canonical decimal text, and processedAt may be null only for undated
historical completion. Include completed refund/reversal records only, ordered
by processed_at ascending nulls last then id. Own orders with no completed
return, including complimentary orders, return an empty array. Do not expose
reason, actor, provider reference, request key or pending/failed attempts, and
do not combine currencies. The member screen labels these as recorded completed
returns, never provider-verified transfers. This fixed projection is the only
security-definer read exception; member SELECT on `refunds` remains denied.

The five mutation RPC results always contain exactly one row on success. Each
UUID result is non-null except sale payment/initial-session ids. `processed_at`
is non-null on a new completion and may remain null only when an exact replay
returns an undated historical completed refund.
HTTP JSON success wraps those fields with the existing typed envelope;
forms use the existing successful redirect convention. First writes and proven
replays both succeed; failures never redirect as success.

| Route / input schema | Allowed real staff / command |
|---|---|
| POST/PATCH `/api/add-ons` | owner/manager; ordinary caller-scoped catalogue insert/update |
| POST `/api/add-on-orders` | front office; sale RPC with camelCase equivalents of its ten parameters |
| POST `/api/add-on-orders/[orderId]/sessions` | trainer; `{sessionId,startsAt,endsAt,notes}` → schedule RPC |
| PATCH same sessions route | trainer; `{sessionId,status}` → finish RPC; URL order must equal session order |
| POST `/api/add-on-orders/[orderId]/complete` | front office; no body → complete RPC |
| POST `/api/refunds/[refundId]/complete-addon` | owner/manager; `{expectedAmountPaise,expectedCurrency,expectedReason}` → manual refund RPC |

Catalogue payload: optional `productId` for update, generated `kind`, `name`,
`description`, decimal-string `pricePaise`, `validityDays`, `cancellationTerms`,
`isActive`, nullable `trainerStaffId`, `trainerQualification`, `sessionCount`,
`stockQuantity`. Currency is server INR. PT requires trainer/qualification/count
and null stock; product requires stock and null trainer/qualification/count;
diet requires all four null. A new active row must be complete; an incomplete
legacy row may be deactivated or edited as inactive without bogus defaults.
Catalogue kind changes are allowed only when no order references the product;
otherwise create another catalogue row. `sort_order`/GST fields are not inputs.
All schemas are strict: unexpected status, amount override, coupon, actor or
usage fields are invalid, with coupon specifically `unsupported_coupon`.
Missing/null required UUIDs, timestamps and numeric inputs are invalid in both
RPC and route; nullable fields above are still present with explicit null.
The shared seam's gym-timezone conversion rejects ambiguous/nonexistent local
slot times before calling the RPC; the RPC accepts offset-bearing instants.

The session UUID is the creation request key. Schedule generates it once per
form, reuses it on retry, and inserts only `scheduled`; an existing same-gym id
is replay only if order, original slot and normalized notes match exactly.
Session notes are outer-trimmed; blank becomes null, and otherwise case, Unicode
and internal whitespace are preserved.
Slots/notes are immutable after creation: reschedule means cancel then create
a new UUID. Finish accepts only completed/cancelled/no_show; its existing UUID
plus target status is the natural terminal-command identity. Same terminal
status is a read-only replay; a different terminal status is refused. No
second command ledger or nonce is needed for an irreversible terminal edge.
Order completion uses its UUID the same way and accepts product/diet only:
completed is inert, active diet completes, all other states/kinds are refused.

## Sale, replay and fulfilment invariants

**A-001:** Before a new sale, require a visible non-erased member whose profile
is neither cancelled nor blocked, an active complete offer, matching displayed
version and valid organization timezone/INR currency. PT trainer is a same-gym
active staff row with role trainer, equals the catalogue trainer and the
requested trainer. Membership status does not independently prohibit add-ons.

**A-002:** Insert pending order with seller/key/request and the current
disclosure snapshot. Copy price/currency; require `total = unit * quantity`,
zero usage, PT session total exactly catalogue count, and non-PT session total
null. Lock/check the product before recording payment using the narrow trigger
described below. For PT insert the initial scheduled session, pass the existing
exclusion constraint, then fill initial_session_id. No pending unpaid order or
booking from this RPC survives a failure or a successful return.
At first PT acceptance, a database invariant also requires initial_session_id
to reference this exact order's scheduled session, with its original start/end,
trainer and member equal to sale_request and the frozen order. A same-tenant
session belonging to another order cannot satisfy the reservation requirement.
The composite FK alone is not this cross-row acceptance check.

**A-003:** Positive sale inserts one ordinary paid manual payment for exactly
the same tenant/member/total/currency, null membership/mandate/coupon/provider
fields, verified seller and normalized reason as notes. Payment key is exactly
`addon-sale:<canonical-order-request-uuid>`. Zero sale requires null method,
nonnull reason and null payment. Advance pending→paid→active, then product
active→completed. Stamp sold_at at pending→paid and derive the inclusive local
dates from that instant. The acceptance stamp is transaction_timestamp(), the
same fixed instant used for initial-slot validity before the payment insert;
crossing midnight while statements run cannot move its sold window. Use
ordinary payment stamping/receipt/audit triggers;
any failure rolls back order, sessions, payment, receipt allocation and stock.

**A-004:** Serialize sale request keys before reading them. Compare the nine
normalized non-key arguments in sale_request plus the original seller. Exact
retry returns original ids with no write even after price edits, deactivation,
refund, completion or expiry.
Changed method, reason, trainer, slot, quantity, version, member, product or
seller is GL052. Lookup/unique/index/trigger errors never count as replay. A
failed original consumes no key. Same key in different gyms is independent.

**A-005:** All new sale orders start pending; id/tenant/member/product, seller, key and request are
immutable from insert. First acceptance freezes payment, product, quantity,
price/total/currency, snapshot, trainer, sessions_total, initial_session_id,
starts_on/expires_on and sold_at forever, including complimentary orders and
terminal/refunded history. Once any linked payment has arrived these facts are
already frozen against tampering while still pending. A new keyed sale order
must carry the complete request/snapshot shape and be accepted or cancelled by
transaction end; missing facts are invalid_snapshot, never a way to escape the
deferred unaccepted_order check. New authenticated inserts require that shape.
Historical null-key rows and trusted legacy fixtures are not retroactively
required to represent a completed sale. A legacy pending row cannot be accepted
as a new sale: create a keyed order. Compatibility waives no payment, money,
identity or usage invariant; authors update invalid fixtures against the approved
requirements. Only database-owned effects change usage; no new unpaid PT hold survives.

**A-006:** The payment reference is one-to-one and must name arrived money
(`paid`, `refunded` or `reversed` with nonnull paid_at), same tenant/member,
exact amount/currency, no membership. A newly accepted order cannot consume
already returned money: first acceptance requires payment.status=paid and no
completed refund against it; the wider arrival states apply to existing history.
Freeze relevant payment identity at the existing paid
boundary; do not permit a payment to buy both membership and add-on service.

**A-007:** A physical product decrements exactly once at pending→paid, including
zero price, using conditional `stock_quantity >= quantity`; insufficient stock
aborts everything. No completion, cancellation or refund automatically restocks
an item: money returned does not prove a physical return. Stock adjustments
remain owner/manager catalogue edits and cannot make stock negative.

**A-008:** Every session references a PT order and equals its frozen tenant,
member and trainer. Session id/tenant/order/member/trainer are immutable from
creation. Trainer writes check BOTH old and new assignment against
the verified staff id; front office retains existing administrative table
access. New sessions are scheduled. Initial slot is allowed on its transaction's
pending order; every other new session requires an active unexpired order.
Slot start is not before acceptance/current command time; end is later than
start and no later than gym-local midnight after expires_on. Adjacent slots
are valid; scheduled/completed overlaps remain `pt_sessions_trainer_overlap_excl`.

**A-009:** Serialize each order before checking `sessions_used + scheduled <=
sessions_total`. Completed count equals sessions_used for new orders. Only
scheduled→completed increments it, and the last increment completes the active
order. Completion requires session end <= server now and local today within
the sold window; late logging after expiry is refused in v1. Cancel/no-show
may close an old scheduled row after expiry without consumption. Completed,
cancelled and no-show rows cannot change identity, slot, notes or status;
same-value writes are harmless but product replay performs no UPDATE.

**A-010:** Preserve order graph exactly: pending→paid|cancelled;
paid→active|cancelled|refunded; active→completed|refunded. Completed/cancelled/
refunded are terminal; same-state writes do not imply another acceptance.
Paid cancellation cancels scheduled slots atomically, does not refund or
restock, and preserves the receipt. No direct active→cancelled escape exists.
An expired active diet/PT order is displayed as expired and refuses delivery;
its stored status and purchased/used history stay honest.

## Returned money, serialization and private capabilities

**A-011:** The existing refund request remains requested, not returned cash.
The new completion form shows amount/currency/reason and requires an explicit
staff confirmation that money was actually returned. Its RPC verifies the
exact expected facts, a same-gym add-on payment with a manual method, and no
provider refund id. It advances requested→processing→completed, or
processing→completed, in one transaction. Failed refunds require a new request;
completed with matching facts is read-only replay. It performs no transfer and
never claims provider verification. Reuse GL048 for changed refund confirmation
facts and existing GL041/040/036 guards, ceiling, refund identity and audit.

On a new completed refund/reversal, processed_at is server-stamped for an
authenticated writer, nonnull for every new completion, and immutable after
completion (GL041). A trusted provider writer may supply its actual event time;
otherwise stamp server time. Historical completed/null timestamps remain
undated; do not invent processed_at. This timestamp rule is shared with metrics.

**A-012:** Lock payment before computing completed returned amount. Only
completed refunds/reversals of that payment's currency count. Different refund
currency is refused for add-on payments. When their sum equals payment amount,
move only paid/active orders to refunded and cancel every scheduled session in
the same transaction. Partial returns preserve status and remaining usage;
completed/cancelled order history stays terminal. Never reduce sessions_used,
erase completed sessions, modify original payment money, or automatically
restock. Later use is refused after full return, even for malformed old status.

Supported RPCs acquire a transaction advisory lock on
`hashtextextended('addon-order:' || tenant_id || ':' || order_id,0)` before row
mutation; hash collision only serializes unrelated work. Sale-key locking uses
the separate `'addon-sale:' || tenant_id || ':' || key` namespace. Order keys
are acquired in UUID order for multi-order work. Extend record_refund only
after its existing role check to acquire the order lock for a visible same-gym
add-on payment. Completion acquires it before touching the refund row. Within
effects, row-lock order is payment→order→session; new product sale separately
locks product before its new payment. Arbitrary direct SQL/provider updates can
already hold a session/refund row before a trigger runs: native 40P01/40001 is a
retryable rolled-back failure, never success. No universal deadlock-free claim.

Private uncallable mutating SECURITY DEFINER trigger helpers are permitted only for:
(1) locking/checking the selected catalogue row at pending-order insert and
conditionally decrementing its stock on acceptance; (2) validating/serializing
accepted PT session effects and updating only parent sessions_used/status;
(3) refund handover's parent status and scheduled-slot cancellation; and
(4) the existing audit writer's append. Empty search_path, fully qualified
objects, revoked PUBLIC/anon/authenticated execution, and exact trigger table/
operation checks are mandatory. Authenticated source tenant must equal its
verified claim and carry a real staff actor authorized for that source action.
Each resolves the source row's tenant/order/
member/trainer and rejects impersonation before elevated access. Claim-based
actor checks apply to authenticated contexts; trusted invariant processing does
not invent a staff actor. No caller-settable GUC or trigger-depth-only claim may
authorize an unrelated write. Public sale/session RPCs remain invoker; neither
catalogue nor order policies gain a broader writer.

## Refusals, audit, metrics and independent evidence

Reserve only GL052–GL058 for this cluster. One ordered enforcement function per
candidate order/session owns the project-rule precedence below; private effects
must not bypass those invariants. SQL DETAIL is the exact named refusal.

| Order | SQLSTATE | Stable refusal names / HTTP code |
|---|---|---|
| 1 | GL053 | `order_is_a_record`, `session_is_a_record` |
| 2 | GL054 | `invalid_order_transition` |
| 3 | GL055 | `catalogue_incomplete`, `offer_unavailable`, `quote_changed`, `unsupported_currency`, `member_unavailable`, `trainer_unavailable`, `invalid_quantity`, `invalid_payment`, `invalid_validity`, `invalid_snapshot`, `unaccepted_order`, `wrong_order_kind`, `order_unavailable` |
| 4 | GL058 | `invalid_session_transition`, `session_budget_exhausted`, `session_outside_validity`, `session_not_ended`, `session_identity_mismatch` |
| 5 | GL056 | `seller_not_yours`, `trainer_not_yours` |
| effect | GL057 | `insufficient_stock` |
| request | GL052 | `idempotency_conflict` |

The total order covers only applicable named row rules, skips inapplicable
rules and promises nothing over native grants/RLS, casts, checks, keys, index
exclusions or which row a multi-row statement evaluates first. Request replay
conflicts and stock effects sit outside that order. Map 42501→not_permitted,
only the named overlap exclusion→slot_unavailable, native deadlock/serialization
failure→retryable, and unrelated native failures→operation_failed. Never map an
arbitrary 23505/23514/23P01 to replay or a specific business refusal.
For named project errors, HTTP error.code is the listed DETAIL value; the
existing envelope remains `{ok:false,error:{code,message}}`. A missing or
incomplete verified identity is `401 not_signed_in`; a complete identity whose
role is refused, and SQLSTATE `42501`, are `403 not_permitted`. Invisible target
(`P0002`) is 404, invalid arguments (`22023`) 400, business refusal/retryable
conflict 409, unrelated failure 500. Successful JSON is 200.

Extend `app.audit_money_change()` for addon_orders INSERT/UPDATE using actions
`addon_order.created`/`addon_order.updated`, record_type `addon_order`, order id,
and the existing verified-subject/trusted-null actor rule. Summary contains
every domain column (existing order columns plus additions), excluding only id,
tenant_id, created_at, updated_at; id/tenant are already envelope fields. Before
is null on insert; reason is sale_request.reason. Every accepted operation has
one event, including free acceptance and database-derived status/usage writes;
replay has none and audit failure rolls the operation back. Existing payment/
refund event shapes do not change. No audit or disclosure backfill is claimed.

MET-004/007 use payment paid_at for positive cash collection and completed
refund processed_at for returned cash, grouped by currency, not order.updated_at.
PT cohort time is linked paid_at for positive orders and sold_at for free ones;
paid/active/completed orders with full completed return excluded contribute
sessions_used/sessions_total. Complimentary orders contribute zero revenue.
Missing historical dates/qualifications/sellers are explicitly unknown/undated;
historical usage discrepancies are disclosed, never normalized by invention.
Legacy PT usage may continue from its existing trainer/session/date facts and
the referenced catalogue kind (which can no longer change while referenced);
missing validity or inconsistent usage is `order_unavailable`, not a guessed
entitlement. Do not fill a historical disclosure snapshot from today's terms.

Independent visible and holdout authors cover each kind including zero, each
changed replay fact, post-sale edits, stock-only quote stability, client version
spoofing, term-driven quote rotation, concurrent last stock/reservation/double
completion, sale rollback at every child failure,
cross-tenant/member/trainer references, direct-write snapshot/usage attacks,
both OLD/NEW trainer assignment, all enum pairs and named refusal pairs,
expiry/midnight/adjacent-slot boundaries, partial/full/terminal refunds,
processed_at freeze, the member return projection's identity/cross-tenant/data
minimization rules, exact audit and member/owner reconciliation. Exercise
Journey C with receipt, consumed PT and completed manual refund. Keep full
money/RLS independence and CI-only migrations; regenerate types via CLI after
CI applies them, register exports, then archive OpenSpec before completion.
