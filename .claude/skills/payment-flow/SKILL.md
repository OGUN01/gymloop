---
name: payment-flow
description: Fires when the user asks to build or change anything touching Razorpay, webhooks, renewals, refunds, or offline payment recording. Expects which part of the flow (order creation, webhook handling, offline recording, refund) as input.
---

# Payment flow

The rules below are gates 19–21 (`docs/gates.md`) and requirements PAY-001 through PAY-011 (`docs/domain-rules.md`) made operational. None of them are negotiable per-endpoint judgment calls.

1. **The provider is the sole source of truth.** A payment is never `paid` because the client said so, or because a Route Handler returned 200 — only a signature-verified webhook or an independently verified provider status query can mark it `paid`.
2. **Verify the webhook signature per gym** using that gym's own `webhook_secret` (Supabase Vault-encrypted, `docs/security.md`) *before* touching any row. An unverified webhook is rejected and logged, never processed "to be safe."
3. **Idempotency by construction.** A duplicate webhook delivery (Razorpay retries on non-2xx, and can redeliver) must produce zero additional state change on the second and later deliveries — key on the provider's event/payment id, not on "this probably hasn't happened before."
4. **Membership extension happens only after step 1's verification**, never optimistically before it, never on a timer that assumes the webhook will arrive.
5. **Refunds and reversals are new records**, never a mutation of the original payment row — the original payment's history must stay intact for audit (INT-001, INT-003).
6. **Never store raw card or UPI credentials** anywhere in this codebase, including logs. Razorpay's own tokenized references only.
7. **Offline payments (no gateway connected) are a first-class path, not a degraded one** — front-desk-recorded cash/UPI/card with staff attribution, a receipt, and the same renewal-pipeline effect as a verified online payment. Most early gyms will be in this state; it must be fully exercised in tests, not treated as an edge case.

Every change here needs a duplicate-webhook-delivery test and a payment-provider-unreachable test before it's considered done — see `docs/gates.md` gate 13 and gate 17.
