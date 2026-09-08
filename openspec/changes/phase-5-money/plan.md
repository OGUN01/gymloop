# Phase 5 — Money

One document (ADR-060). EARS spec separate.

## Two payment paths, and the manual one is not a fallback

**Owner decision, 2026-09-08.** A gym takes money two ways and the product treats both as first class:

1. **Manual** — cash, UPI, card or bank transfer taken at the desk, recorded by a staff member, producing a receipt and driving renewal exactly as an online payment does.
2. **Razorpay** — online, per gym, with its own key and webhook secret.

PAY-011 already required the first ("IF a gym has no payment gateway connected THEN THE SYSTEM SHALL remain fully functional for cash/UPI/card payments recorded by front desk, including staff attribution, a receipt, and a working renewal pipeline"). What the owner has settled is that it is **the path most Indian gyms will actually use**, not a degraded mode — and the schema already agrees: `payment_method` is `{razorpay, cash, upi, card, bank_transfer}`, four of five needing no gateway at all.

**The sequencing consequence, which is the useful part: Phase 5 is not blocked on credentials.** The manual path is built and demonstrated first, end to end, against the demo gym. Razorpay is added beside it. A phase that cannot start until a secret arrives is a phase that does not start.

## What this phase ships

| Layer | |
|---|---|
| **Manual payments** | Record a payment against a member and a membership: amount in paise, method, staff attribution, receipt number. Extends the membership on the same rules an online payment would. |
| **Receipts** | A receipt number per gym from `document_counters`, and something printable. |
| **GST invoices** | `invoices` exists with the fields; OPEN-003 (how a PDF is produced) is decided here. |
| **Razorpay** | Per-gym key and webhook secret in Vault, order creation, webhook verification **per gym**, and the payment state machine. |
| **Refunds** | A separate row, never a mutation of the original (PAY-010, INT-001). |
| **Renewals** | The pipeline PAY-001 to PAY-004 drives, reading the gym's own `renewal_reminder_days_from_expiry`. |

## The rules that decide the design

- **Money is integer paise, always** (MNY-001) — and the rounding rule for anything derived is chosen *here*, once, and written down (MNY-003).
- **The provider is the only source of truth for online payment state** (PAY-006). No client report ever marks a payment `paid`; a membership extends only after a verified webhook or an independently verified provider status (PAY-008).
- **A duplicate webhook changes nothing** (PAY-009). `webhook_events` is already read-only to `authenticated` and carries `signature_valid` — the idempotency belongs in the database, on the table, exactly as the check-in guard does. Phase 3's `app.enforce_check_in()` is the worked example.
- **A manual payment has no provider to verify against**, so its integrity comes from staff attribution and the audit row instead. That asymmetry is the whole reason the two paths are separate code, and it must be stated rather than blurred.

## Process (ADR-059)

**The whole phase is the full blind arrangement.** Money is the case ADR-059 names explicitly, and every failure here is silent in the worst way: a membership extended without payment, a payment marked paid that was not, a duplicate webhook extending twice, a refund that mutates the original row.

## Blocked, and named so it is not discovered late

Razorpay test credentials do not exist. The manual path, receipts, invoices, refunds and the renewal pipeline do not need them. Order creation and webhook verification do.
