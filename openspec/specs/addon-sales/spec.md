## Purpose

Sell and fulfil products, diet plans and personal-training packages without
losing stock, session capacity, money precision, tenant isolation or the terms
the member accepted.

## ADDED Requirements

### Requirement: Published offers disclose complete versioned terms
WHEN an owner or manager creates or edits an add-on THE SYSTEM SHALL apply the
strict kind-specific catalogue shape and quote-rotation rules in the frozen
Phase 6 add-on contract. A new active offer SHALL disclose name, description,
exact INR price, inclusive validity, cancellation terms and the applicable
stock or trainer qualification/session facts. Incomplete legacy offers SHALL
remain readable but unsellable, and referenced offer kind SHALL not change.

#### Scenario: Offer terms change
- **WHEN** a term that affects acceptance changes
- **THEN** the database SHALL rotate `quote_version`, while a stock-only or presentation-order edit SHALL preserve it

#### Scenario: Incomplete legacy offer
- **WHEN** an incomplete historical offer is read or deactivated
- **THEN** it SHALL remain available as history without invented disclosure and SHALL not be accepted for a new sale

### Requirement: Sale acceptance is atomic, affirmative and exactly replayable
WHEN real front-office staff record an add-on sale THE SYSTEM SHALL require an
affirmatively selected visible member and offer, derive tenant/seller/terms and
money in the database, and accept through `record_addon_sale` as one transaction.
The request UUID SHALL serialize before current offer lookup. An exact retry by
the same seller SHALL return the original ids without a write; any changed
normalized request fact SHALL return `GL052 idempotency_conflict`. Failure SHALL
leave no order, payment, session, receipt, stock movement or consumed key.

#### Scenario: Lost response retry
- **WHEN** the original sale committed but its response was lost and the same seller repeats the exact request
- **THEN** the original order, payment and initial-session ids SHALL return with `replayed=true` and no new audit or stock effect

#### Scenario: Changed retry
- **WHEN** the same gym and request key carry a different member, offer, quantity, quote, trainer, slot, method, reason or seller
- **THEN** the request SHALL be refused as `idempotency_conflict` without changing the first sale

### Requirement: Money, stock and accepted terms agree exactly
WHEN accepting a positive-price offer THE SYSTEM SHALL create one ordinary paid
manual payment for the exact checked bigint total in the order currency, with
the verified seller, receipt and no membership, coupon, provider or mandate.
WHEN accepting a zero-price offer THE SYSTEM SHALL require a nonblank reason and
create no payment or receipt. Product stock SHALL decrement exactly once at
acceptance and SHALL never become negative. The order SHALL freeze the exact
request and disclosure snapshot defined by A-002–A-007.

#### Scenario: Last item sold concurrently
- **WHEN** two valid sales race for the final unit
- **THEN** exactly one SHALL commit and the other SHALL return `GL057 insufficient_stock`, with no partial child effects

#### Scenario: Complimentary acceptance
- **WHEN** staff accept a complete zero-price offer with a reason
- **THEN** the order SHALL be accepted and audited with no payment, receipt or floating-point calculation

### Requirement: Add-on orders are records with a closed lifecycle
WHEN an add-on order is written THE SYSTEM SHALL enforce A-005, A-006 and A-010
through one ordered rule owner. Request identity and accepted sale facts SHALL
be immutable; payment linkage SHALL be arrived, same-tenant, same-member,
same-currency, exact-total and unused by membership or another order. The only
stored transitions SHALL be pending→paid/cancelled, paid→active/cancelled/refunded
and active→completed/refunded. Completed, cancelled and refunded SHALL be terminal.

#### Scenario: Direct snapshot or payment substitution
- **WHEN** an authenticated writer changes frozen disclosure, request, identity, money, dates, seller, usage or payment facts
- **THEN** the write SHALL be refused by the applicable `GL053`–`GL056` rule and leave the record unchanged

#### Scenario: Product acceptance
- **WHEN** an atomic product sale succeeds
- **THEN** its order SHALL reach completed immediately while preserving its receipt and frozen sold terms

### Requirement: PT reservations and usage cannot exceed the purchase
WHEN a PT sale is accepted THE SYSTEM SHALL create its exact initial scheduled
session inside the sale. Later `schedule_pt_session` calls SHALL require the
assigned real trainer, active unexpired order, available reservation capacity,
valid gym-local slot and no overlap. Session identity, slot and notes SHALL be
immutable. Only scheduled→completed SHALL consume one session, and it SHALL do
so once; cancelled/no-show SHALL free the reservation and consume none.

#### Scenario: Concurrent final reservation
- **WHEN** two valid bookings race for the last available purchased session
- **THEN** exactly one SHALL commit and used plus scheduled SHALL never exceed purchased

#### Scenario: Completion replay and conflict
- **WHEN** a terminal PT command repeats the same status
- **THEN** it SHALL return a read-only replay; a different terminal status SHALL be refused as `invalid_session_transition`

#### Scenario: Trainer ownership and time
- **WHEN** a trainer changes a session whose old or new assignment is not their own, or completes a session before it ends or outside validity
- **THEN** the command SHALL be refused without revealing another tenant's facts or consuming usage

### Requirement: Diet and service completion stays truthful
WHEN front office completes an active diet order THE SYSTEM SHALL move it once
to completed; a replay SHALL be inert. Product orders are already completed by
sale and PT completes only through consumed sessions. Expiry SHALL be derived
from the inclusive gym-local sold window and SHALL refuse new delivery without
inventing a stored expired transition or erasing purchased/used history.

#### Scenario: Wrong fulfilment kind
- **WHEN** general order completion targets PT, a nonterminal product, pending, cancelled, refunded or an expired nonterminal service
- **THEN** it SHALL be refused by the applicable wrong-kind, transition or unavailable rule

#### Scenario: Completed product or diet replay
- **WHEN** general order completion targets a completed product or diet order
- **THEN** it SHALL return the stored completed state as a read-only replay

### Requirement: Manual return completion records cash actually returned
WHEN an owner or manager explicitly confirms that an eligible manual add-on
refund was returned THE SYSTEM SHALL verify the displayed amount, currency and
reason, then move requested/processing to completed atomically with a server
processing time. Exact completed replay SHALL be read-only; changed facts SHALL
be `GL048`. Requested/processing amounts reserve refund headroom but SHALL not
be labelled returned cash. Completed returns SHALL drive returned totals.

#### Scenario: Full completed return
- **WHEN** completed refund/reversal money reaches the linked payment amount
- **THEN** eligible paid/active orders SHALL become refunded and scheduled PT sessions SHALL cancel, without restock or reduction of completed usage

#### Scenario: Partial or terminal return
- **WHEN** completed returned money is partial, or the linked order is already completed/cancelled
- **THEN** returned history SHALL remain visible while the order's truthful terminal/fulfilment history is preserved

### Requirement: A member sees only completed returns for their own order
WHEN a complete verified member calls `read_member_addon_returns(order_id)` THE
SYSTEM SHALL apply ADR-116: independently match order and payment to the member
and tenant claims and return one fixed JSON projection containing only completed
return id, actual generated refund/reversal kind, exact decimal-string amount,
currency and processing time. It
SHALL expose no pending attempt or internal reason/actor/provider/request fact.
Direct member SELECT on refunds SHALL remain denied.

#### Scenario: Own completed returns
- **WHEN** the member requests their own paid add-on order
- **THEN** completed returns SHALL appear in stable time/id order and no other refund state SHALL appear

#### Scenario: Foreign or incomplete identity
- **WHEN** another identity or member requests the order, or order/payment linkage is missing or inconsistent
- **THEN** authorization or the uniform not-found result SHALL reveal no cross-tenant or cross-member fact

### Requirement: Working screens expose every Phase 6 action and state
WHEN staff or a member uses the add-on surfaces THE SYSTEM SHALL provide the
routes, strict payloads, role gates and truthful states in the frozen contract
and `docs/planning/phase6-addon-ui-brief.md`. No offer SHALL be preselected.
Preview SHALL show reads with no mutation controls. Money SHALL stay decimal
text/BigInt through reads and reconciliation. Empty, legacy, expired, pending,
failed, retryable, unavailable and completed states SHALL remain distinguishable.

#### Scenario: Staff journey
- **WHEN** authorized staff publish, select, sell, schedule, fulfil, inspect receipt or confirm a return
- **THEN** each action SHALL use its named API/RPC, show exact accepted facts, preserve uncertain retry identity and expose the next valid recovery

#### Scenario: Member journey
- **WHEN** a member opens catalogue or an own order
- **THEN** they SHALL see current offer disclosures or frozen sold terms, applicable usage/receipt/completed-return facts, and no staff-only action

### Requirement: Add-on money changes are audited and reconcilable
WHEN an add-on order is inserted or updated THE SYSTEM SHALL append the exact
`addon_order.created` or `addon_order.updated` audit event described by the
frozen contract, including every domain column and verified actor attribution.
Replay SHALL append nothing and audit failure SHALL roll back the product write.
Positive cash and completed returned cash SHALL use payment `paid_at` and refund
`processed_at`, respectively; complimentary orders SHALL contribute zero.

#### Scenario: Accepted free and paid sales
- **WHEN** either kind commits
- **THEN** the order audit SHALL identify its exact actor/reason and underlying payment/order rows SHALL reconcile without using `updated_at`

#### Scenario: Historical unknowns
- **WHEN** legacy rows lack sold time, seller, qualification, disclosure or consistent usage
- **THEN** reads and metrics SHALL disclose unknown/undated facts rather than backfill or normalize them by invention
