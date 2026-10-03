# PAY contract resolutions — APPROVED (owner, 2026-10-03)

**APPROVED.** The owner selected all three recommended boundaries: (1) hard
stock holds for accepted PAY requests; (2) record actual funds without falsely
completing the purchase (`mismatch_recorded`); (3) renew eligible held
memberships at their recorded sold terms. The resolutions are folded into the
frozen `proposal.md`, which pins the exact recording command
`public.record_purchase_request(...)` and the renewal revision token. The
remaining engineering sequence is unchanged: independent visible and holdout
money tests (implementer-blind), separate implementer, fresh critics and
every gate. It changes no batch-2 migration.

## 1. Accepted stock

**Recommended: preserve F10's guarantee with hard holds for accepted PAY requests.**
Accepting a physical-product request reserves its exact quantity until its fixed
expiry, cancellation, rejection or atomic payment recording. Two concurrent
acceptances for the last unit have exactly one winner. Ordinary counter sales,
SHP collection, inventory adjustment and trusted writes cannot consume that
accepted quantity. The existing product locks, stock counter and guarded sale
remain the single inventory; no duplicate stock ledger is introduced. Recording
the accepted request consumes its own hold and creates the existing sale in one
transaction; failure restores the hold and leaves all money untouched. Expired
holds cease counting without requiring a successful background job. SHP's
ordinary member reservations retain their approved soft-hold behavior, while
their availability accounts for active PAY hard holds.

This requires narrowly amending the existing stock/sale invariants, plus
independent visible and holdout money tests and a fresh blind source critic.
Full signature, guard scope, lock order, replay and exact error precedence must
be frozen before those authors start. No ordinary session setting may bypass
the hard hold or forge its consumption.

**Alternative, requiring an explicit F10 change:** accepted PAY requests use the
existing SHP soft holds. A counter sale can exhaust them before collection; the
acceptance screen and member detail must disclose that stock is not guaranteed.
It must never claim F10's original guarantee has been delivered.

## 2. Money received at a different amount

**Recommended: record actual funds without falsely completing the purchase.**
For a Shop/PT amount mismatch, insert an ordinary actor-attributed manual paid
payment with the actual positive integer-paise amount and explicit currency,
`membership_id=null`, through existing authenticated money policies and guards.
The existing payment table and desk path already permit such a member payment;
there is no new wallet, balance, credit, discount or price rewrite. Bind that
payment and the exact currently viewed proof once to the request, then close the
request as a distinct terminal `mismatch_recorded` outcome and release its hold.
Show quoted amount, received amount and difference, the real receipt, and
“Money recorded; purchase needs desk resolution.” Create no order, usable pack
or membership extension. The request cannot reopen or reuse the proof/payment.
Refund or a separate correctly priced sale remains the normal desk path; money
may not be silently transferred to a replacement purchase or counted twice.

An exact-price purchase continues to use the unchanged guarded sale. A renewal
payment instead stays attached to its eligible held membership and uses the
existing cumulative-period arithmetic: partial money is recorded honestly,
and only genuinely granted dates appear. No screenshot implies settlement.
Foreign-currency or unsupported collection situations must follow the frozen
existing money boundary, never be silently converted to INR.

Alternative: change the existing add-on price/settlement contract to permit an
under/overpriced purchase. That is a separate money amendment; it cannot be
implemented by changing an order total or inventing a discount in PAY.

## 3. Held-plan renewals

**Recommended: renew eligible active/frozen held memberships at their recorded
sold price, discount, currency and duration.** The confirmation shows those
terms explicitly and distinguishes the catalogue's current price. The existing
paid history and cumulative-period logic remain unchanged. Only the member's
own eligible held membership is accepted. Pending, retired, expired, cancelled,
inactive-plan or changed-plan cases go to the desk and create no misleading
self-service renewal request.

Alternative: introduce a successor-membership contract at today's plan price.
That must freeze successor creation, live-membership uniqueness, payment
allocation and activation dates before independent tests; it may never rewrite
the old paid membership's terms.

## Verification and authority

These are product/money decisions, not permission to collect money or contact
anyone. After approval, the orchestrator updates proposal/bar/ADRs, resolves exact
public protocol details, and freezes them serially before independent visible
and holdout tests, a separate implementer, fresh critics and every gate. Real
last-unit accept-versus-counter-sale, cancel/expiry-versus-record and payment
binding races remain mandatory. Screens and Android acceptance remain required.
The private proof extension and its exact authorization must also be frozen;
prior MEDIA approval alone does not broaden that boundary.
