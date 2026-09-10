# Domain rules (EARS)

Every rule below traces to a bullet in the master build prompt §8. Each requirement gets a stable ID (`<CATEGORY>-<NNN>`) so gate 2 ("every requirement has ≥1 visible and ≥1 holdout test") is mechanically checkable once Phase 1+ writes tests against these IDs — reference the ID in the test name or description, don't restate the requirement text in the test.

Canonical status vocabularies referenced below are defined in `docs/data-model.md`. Do not invent a parallel vocabulary.

## Attendance and QR (ATT)

- **ATT-001** WHEN a member presents a QR code to check in THE SYSTEM SHALL verify the QR session is valid and the membership is active before recording attendance.
- **ATT-002** IF the QR session is expired or invalid THEN THE SYSTEM SHALL reject the check-in and SHALL NOT record attendance.
- **ATT-003** THE SYSTEM SHALL generate check-in QR codes as rotating or session-bound, so a screenshot of a previously valid QR code does not remain scannable indefinitely.
- **ATT-004** WHEN a duplicate scan for the same member arrives inside a configurable de-duplication window THE SYSTEM SHALL reject the duplicate without discarding the original, legitimate attendance record.
- **ATT-005** WHEN staff perform an assisted front-desk check-in THE SYSTEM SHALL require the acting staff member's identity and a mandatory reason before recording the check-in.
- **ATT-006** IF an assisted check-in is submitted without a reason THEN THE SYSTEM SHALL reject the check-in.
- **ATT-007** WHILE a device is offline THE SYSTEM SHALL queue check-ins locally and, on reconnect, SHALL replay each queued check-in exactly once, writing an audit stamp recording the original offline timestamp and the replay time.
- **ATT-008** THE SYSTEM SHALL treat check-out as optional in v1 — a missing check-out SHALL NOT block any other system behavior (streaks, no-show detection, or billing).

## Streaks (STK)

- **STK-001** THE SYSTEM SHALL support three configurable streak rule types per gym: visit streak (consecutive planned workouts), weekly goal (e.g. N of M planned visits per week), and calendar streak (challenge periods only).
- **STK-002** WHEN a member has an approved pause or a configured rest day THE SYSTEM SHALL NOT count that day as a streak break.
- **STK-003** THE SYSTEM SHALL present streak status and missed days without shaming language — copy review is part of the Phase 7 design gauntlet, not optional polish.
- **STK-004** WHEN a member disables motivational notifications THE SYSTEM SHALL stop sending streak/motivation pushes to that member while continuing to compute and display their streak in-app.

## No-show detection (NSH)

- **NSH-001** THE SYSTEM SHALL run the no-show scan once per calendar day, in each gym's own configured timezone (not UTC, not the server's local time).
- **NSH-002** WHEN the no-show scan runs THE SYSTEM SHALL exclude members whose membership is `paused`, `frozen`, `expired`, or `cancelled` from red-list evaluation.
- **NSH-003** WHEN a member's absence crosses the gym's configured no-show threshold THE SYSTEM SHALL open exactly one no-show case in `open` status.
- **NSH-004** IF a member already has an open no-show case THEN THE SYSTEM SHALL NOT open a second case for the same member, on any subsequent scan run.
- **NSH-005** WHEN a member with an open no-show case checks in THE SYSTEM SHALL automatically transition the case to `returned` and then `closed`, preserving the case's full contact history rather than deleting it.
- **NSH-006** WHILE a no-show case is being contacted by one staff member THE SYSTEM SHALL prevent a second staff member from concurrently logging a call to the same case (no double-contact race).
- **NSH-007** THE SYSTEM SHALL treat every contact-log entry as append-only; a correction to a prior contact log SHALL be written as a new entry, never as an edit or delete of the original.

## Renewals and payments (PAY)

- **PAY-001** THE SYSTEM SHALL send renewal reminders at configurable day-offsets relative to membership expiry, defaulting to 14, 7 and 3 days **before** expiry, on the expiry date itself, and 3 days **after** expiry. Encoded in `RENEWAL_REMINDER_WINDOWS`, each window carrying an explicit `daysFromExpiry` on one axis: **negative = before expiry, 0 = the expiry date, positive = after**. So the windows are `-14, -7, -3, 0, +3` and this requirement's "+3" is literally `+3`.
- **PAY-002** THE SYSTEM SHALL send at most one reminder message per configured stage.
- **PAY-003** WHEN a membership's renewal payment is verified, OR the membership is cancelled, OR the member opts out of renewal messaging THEN THE SYSTEM SHALL stop sending further renewal reminders for that renewal cycle.
- **PAY-004** WHEN a renewal payment fails THE SYSTEM SHALL escalate on a path distinct from the no-response path (different message, different staff-facing signal).
- **PAY-005** THE SYSTEM SHALL NOT store raw card numbers or raw UPI credentials anywhere in the system.
- **PAY-006** THE SYSTEM SHALL treat the payment provider (Razorpay) as the sole source of truth for payment state.
- **PAY-007** THE SYSTEM SHALL NOT treat a `payment_initiated`/`created`/`pending` record as `paid` under any circumstance.
- **PAY-008** THE SYSTEM SHALL extend a membership only after a webhook signature has been verified or a provider status response has been independently verified — never on client-reported success alone.
- **PAY-009** WHEN a duplicate webhook delivery for an already-processed event arrives THE SYSTEM SHALL process it idempotently, producing no additional state change or duplicate membership extension.
- **PAY-010** THE SYSTEM SHALL record refunds and reversals as separate records from the original payment, never by mutating the original payment row.
- **PAY-011** IF a gym has no payment gateway connected THEN THE SYSTEM SHALL remain fully functional for cash/UPI/card payments recorded by front desk, including staff attribution, a receipt, and a working renewal pipeline.

## Money and time (MNY)

- **MNY-001** THE SYSTEM SHALL store every money amount as an integer number of paise, never as a floating-point number.
- **MNY-002** THE SYSTEM SHALL store an explicit currency code alongside every money amount.
- **MNY-003** THE SYSTEM SHALL apply one documented, tested rounding rule wherever a money amount is derived (discounts, proration, tax) — the rule itself lives in `docs/decisions.md` once Phase 5 picks it, but rounding SHALL NOT be implicit or ad hoc per call site.
- **MNY-004** THE SYSTEM SHALL evaluate every scheduled or date-boundary computation (no-show scans, reminders, streak resets) in the timezone of the gym the computation concerns, not in UTC or server-local time.
- **MNY-005** THE SYSTEM SHALL be tested across timezone date boundaries (midnight rollover, DST-adjacent regions if ever expanded beyond India) so a scan does not run twice or zero times around a boundary.

## Add-ons (ADD)

- **ADD-001** THE SYSTEM SHALL NOT pre-select any add-on (PT package, diet plan, product) in a purchase flow — the member SHALL make an affirmative choice.
- **ADD-002** WHEN a member views an add-on before purchase THE SYSTEM SHALL display its exact price, validity period, trainer qualification (for PT) or stock level (for products), and cancellation terms.
- **ADD-003** WHEN a member attempts to purchase a PT add-on THE SYSTEM SHALL check trainer availability before accepting payment, not after.
- **ADD-004** IF fulfilling an add-on order would take product stock or a trainer's session count below zero THEN THE SYSTEM SHALL reject the order.
- **ADD-005** WHEN real front-office staff accept an affirmatively selected, complete add-on offer THE SYSTEM SHALL serialize the request UUID and current quote, derive the tenant, seller, exact bigint money and inclusive gym-local validity, freeze the normalized request and disclosed terms, and commit the order, any manual payment, receipt, initial PT reservation, stock effect and audit as one transaction. An exact same-seller retry SHALL be read-only; a changed retry SHALL be `GL052 idempotency_conflict`; any failure SHALL consume nothing.
- **ADD-006** WHEN an add-on order is written THE SYSTEM SHALL keep its identity, seller, request, accepted disclosure, money, validity, payment, trainer and usage facts permanent; SHALL allow only pending→paid/cancelled, paid→active/cancelled/refunded and active→completed/refunded; and SHALL keep completed, cancelled and refunded terminal. A positive-price order SHALL link one arrived, unused, same-member, same-currency payment for the exact total, while a complimentary order SHALL require a reason and create no payment.
- **ADD-007** WHEN a trainer schedules or finishes PT THE SYSTEM SHALL require that exact assigned real trainer, an active unexpired and not-fully-returned order, a gym-local slot at or after the current command, remaining purchased capacity and no overlap. Session identity, slot and notes SHALL be permanent; only scheduled→completed/cancelled/no_show is legal; completion SHALL happen after the slot ends and consume once, while cancellation/no-show consumes nothing.
- **ADD-008** WHEN front office completes a service order THE SYSTEM SHALL complete only an active diet plan inside its inclusive sold window, replay an already-completed product or diet without a write, and refuse PT, nonterminal product, unavailable or terminal orders without inventing an expired state.
- **ADD-009** WHEN an owner or manager confirms an eligible manual add-on return THE SYSTEM SHALL verify the exact displayed amount, payment currency and reason, record a server completion time and make exact retries read-only. Requested/processing amounts SHALL reserve headroom but SHALL not count as returned cash. A completed full return SHALL move only eligible paid/active orders to refunded and cancel scheduled PT, without restocking or rewriting completed usage or terminal delivery history.
- **ADD-010** WHEN a complete member identity reads its own add-on order THE SYSTEM SHALL expose frozen sold terms and only the fixed completed-return projection; direct refund reads, pending attempts, internal actors, provider facts and another member's order SHALL remain unavailable. An active PT offer may reveal its assigned trainer's display name through the member-only name projection, beyond the offer's own trainer id, but no staff contact, auth or internal identity field.
- **ADD-011** WHEN staff or members use an add-on screen THE SYSTEM SHALL preserve exact decimal-text/BigInt money, distinguish current offers from frozen sold facts, show pending return requests separately from completed returned cash, hide role-inaccessible finance, preserve retry identity after uncertain responses and provide only actions valid for the role and state. Preview identities SHALL have reads and no mutation controls.
- **ADD-012** WHEN an add-on order changes THE SYSTEM SHALL append the exact actor-attributed financial audit event in the same transaction. Cash reconciliation SHALL use payment `paid_at`, completed returned cash SHALL use refund `processed_at`, complimentary orders SHALL contribute zero and legacy unknowns SHALL remain visibly unknown rather than being invented.

## Identity navigation (NAV)

NAV-001–005 and NAV-007 are current. NAV-006 and NAV-008 are fixed Phase 6
requirements deferred to the platform slice, before commercial controls appear.

- **NAV-001** WHEN a verified session has one complete Gymloop identity shape THE SYSTEM SHALL route it to its role's working home; missing or contradictory claims SHALL route to not-linked and authorize no mutation, while a missing verified session SHALL reach sign-in.
- **NAV-002** THE SYSTEM SHALL use one pure identity classifier and one home selector across sign-in, root, not-linked, audience layouts and API session helpers: staff `/console`, members `/member/add-ons`, platform users `/platform`, and previews `/console`.
- **NAV-003** WHILE a super admin previews a gym THE SYSTEM SHALL show a persistent red banner naming the gym and expiry, permit only ending that caller's exact preview session among product mutations, and SHALL infer no staff or member identity.
- **NAV-004** WHEN a preview ends THE SYSTEM SHALL update only the verified claim session, refresh Auth and return to platform; IF refresh fails THEN it SHALL clear the local session and return to sign-in.
- **NAV-005** THE SYSTEM SHALL expose a real member catalogue and own-order read surface plus a real platform fleet read surface, with truthful empty/error states; platform support SHALL receive no mutation controls.
- **NAV-006** WHEN a gym is pending approval, suspended, closed or has an expired or malformed trial THE SYSTEM SHALL issue no fresh gym-side identity; an explicitly requested super-admin preview remains permitted, and suspension/closure SHALL revoke linked staff/member refresh sessions.
- **NAV-007** WHEN the access-token hook resolves or fails to resolve an identity THE SYSTEM SHALL first remove stale Gymloop claim keys, preserve reserved Auth facts, and retain the established identity precedence and deterministic tenant choice.
- **NAV-008** THE SYSTEM SHALL allow only a non-preview super admin to change organization status, tier, trial or activation fields, so a suspended gym cannot reactivate itself during the residual token window.

## Data integrity (INT)

- **INT-001** THE SYSTEM SHALL NOT hard-delete financial records, attendance corrections, or follow-up history under any user-facing action.
- **INT-002** THE SYSTEM SHALL store marketing consent and service-communication consent as separately controlled flags — withdrawing one SHALL NOT affect the other.
- **INT-003** WHEN a financial record, an attendance correction, a follow-up record, a role change, or an impersonation session is created, modified, or ended THEN THE SYSTEM SHALL write an audit row recording actor, action, record type, record id, a before/after summary, and a timestamp.

## Data-quality alerts (DQA)

- **DQA-001** THE SYSTEM SHALL flag any membership row that has no expiry date set.
- **DQA-002** THE SYSTEM SHALL flag any payment row in `paid` status that carries no provider reference.
- **DQA-003** THE SYSTEM SHALL flag any attendance correction that carries no reason.
- **DQA-004** THE SYSTEM SHALL flag any product stock level that has gone negative.
- **DQA-005** THE SYSTEM SHALL flag any trainer double-booking (two sessions for the same trainer with overlapping times).

## Compliance — DPDP (DPD)

- **DPD-001** THE SYSTEM SHALL treat the gym (organization) as the Data Fiduciary and the platform as the Data Processor for member personal data — the gym's contract carries a DPA clause reflecting this.
- **DPD-002** THE SYSTEM SHALL record consent as versioned entries, each carrying a timestamp and a stated purpose.
- **DPD-003** THE SYSTEM SHALL keep marketing consent and service consent as independently withdrawable flags (see INT-002).
- **DPD-004** WHEN a member withdraws consent THE SYSTEM SHALL stop the corresponding category of communication without deleting the consent history itself.
- **DPD-005** WHEN a member requests a data export THE SYSTEM SHALL produce their personal data in a portable format.
- **DPD-006** WHEN a member requests erasure THE SYSTEM SHALL erase their personal data EXCEPT financial records under legal hold, which SHALL be retained per the applicable retention period and excluded from the erasure.
- **DPD-007** THE SYSTEM SHALL define a per-table retention policy (recorded in `docs/security.md` once Phase 1 finalizes the schema) and a breach-notification runbook.
- **DPD-008** THE SYSTEM SHALL support storing member photos but SHALL NOT store any government-issued ID in v1.
