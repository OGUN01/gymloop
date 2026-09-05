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
