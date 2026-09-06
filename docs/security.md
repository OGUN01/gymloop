# Security

## Tenancy isolation (RLS)

Single Postgres database, Row-Level Security on every table. `tenant_id` (the organization id) is injected into the JWT via a custom access-token hook at auth time, and RLS policies read it from the JWT claim — **never** via a per-row subquery against another table (that pattern is slow and has historically been the source of cross-tenant leaks in Supabase RLS setups). Every RLS-referenced column is indexed. A pgTAP cross-tenant leak suite runs per table: Gym A must never be able to read, update, or delete Gym B's rows under any role, including edge cases like a null/missing tenant claim. See `docs/data-model.md` for the policy-map shape; the actual policies are written in Phase 1.

`super_admin` and `platform_support` see across all tenants by explicit RLS policy design (a policy branch keyed on role), not by disabling RLS or using the service-role key from application code paths a user can reach.

## Impersonation

Super Admin may impersonate a gym owner for support. Every impersonation session:
- Requires a mandatory typed reason, recorded before the session starts.
- Shows a persistent red banner in the UI for the duration of the session.
- Writes an audit row on start and on end (actor, target gym, reason, start/end timestamps).
- Auto-expires — an impersonation session has a hard TTL, not an indefinite one ended only by manual logout.

## Payment integrity

- Per-gym Razorpay `key_id`, `key_secret`, and `webhook_secret` are encrypted at rest via Supabase Vault — never stored as plaintext columns, never logged.
- Every webhook is signature-verified **per gym** (using that gym's own `webhook_secret`) before any state change is applied. An unverified or mis-signed webhook is rejected and logged, not silently ignored.
- The provider is the sole source of truth for payment state (PAY-006 through PAY-009 in `docs/domain-rules.md`). No client-reported success ever marks a payment `paid`.
- No secret key is ever sent to client code. `NEXT_PUBLIC_*`-prefixed env vars are the only ones reachable from the browser bundle; `SUPABASE_SERVICE_ROLE_KEY` and Razorpay secrets never carry that prefix (enforced by `packages/shared/src/config/env.ts`'s client/server schema split, and by convention review — there is no automated lint rule that inspects env var *names* for the prefix, only one that blocks direct `process.env` access outside `env.ts`).

## Audit logging

Every mutation of financial data, an attendance correction, a follow-up record, a role change, or an impersonation session writes an audit row: actor, action, record type, record id, a before/after summary, and a timestamp (INT-003). Audit rows are themselves subject to INT-001 (never hard-deleted).

## DPDP compliance (Digital Personal Data Protection Act)

- **Roles**: the gym (organization) is the **Data Fiduciary**; the platform (Gymloop) is the **Data Processor**. The gym's contract with the platform needs a Data Processing Agreement (DPA) clause reflecting this — a legal/commercial deliverable, not a schema one, but the schema must support everything the DPA promises members.
- **Consent**: versioned records, each with a timestamp and a stated purpose (DPD-002). Marketing consent and service-communication consent are independently controlled and independently withdrawable (INT-002, DPD-003).
- **Withdrawal**: withdrawing consent stops the corresponding communication category without deleting consent history (DPD-004).
- **Export**: members can request a portable export of their personal data (DPD-005).
- **Erasure**: members can request erasure; financial records under legal hold are retained per their retention period and excluded from erasure (DPD-006, INT-001).
- **Retention**: the per-table retention policy is below, written in Phase 1 alongside the schema it describes (DPD-007, `docs/decisions.md` ADR-036).
- **Breach notification**: a runbook is required before launch (who is notified, within what window, by what channel). **Deferred to Phase 8, deliberately** — ADR-036 records the call and its reasoning. It is an operational document about people and escalation paths, none of which exist yet; Phase 1 had nothing to write into it that would not have been a placeholder. The retention policy, which *is* a property of the schema, was written now instead.
- **Photos vs IDs**: member photos are permitted; no government-issued ID is stored in v1 (DPD-008).

## Per-table retention (DPD-007)

Written in Phase 1 because a retention policy is a statement about tables, and this is the moment the tables exist (ADR-036). Two things it is **not**: it is not enforced by anything yet — no job deletes on this schedule, and building one is Phase 8's work, not Phase 1's — and the durations below are **engineering defaults awaiting legal sign-off**, not advice. They are set to the longest obligation the platform can identify so that nothing is destroyed too early; a lawyer shortening one is a safe change, and lengthening one after data is gone is not.

The clock starts at the event named in "Retained from". "Erasable" says whether a DPD-006 erasure request reaches the row: `blank` means the personal columns are cleared and the row survives (its financial or audit meaning does not belong to the member), `delete` means the row goes, and `hold` means it is retained under legal hold and explicitly excluded from erasure.

| Table(s) | Retained from | Duration | Erasable | Why |
|---|---|---|---|---|
| `payments`, `refunds`, `invoices`, `document_counters`, `webhook_events` | the transaction | **8 years** | `hold` | The longest Indian books-of-account obligation the platform must assume: the Income-tax Act's six-year reassessment window plus the Companies Act's eight-year book-retention rule. GST's own six years sits inside it. DPD-006 excludes these explicitly. |
| `memberships`, `membership_pauses`, `coupons`, `plans` | membership end | **8 years** | `hold` | The consideration behind a financial record. Retaining a payment whose contract has been deleted makes the payment unauditable. |
| `attendance`, `attendance_corrections`, `qr_sessions` | the visit | **3 years** | `blank` | Operational history: enough for a multi-year retention narrative and a disputed-visit investigation, not indefinite behavioural tracking. `qr_sessions` holds only a token hash and is prunable at **90 days** — it has no evidential value past its own expiry. |
| `members`, `member_devices` | last membership end | **3 years** | `blank` | The row survives because financial history references it; the personal columns do not. A device token is dead the moment the app is uninstalled and should be pruned at **1 year** of inactivity regardless. |
| `consents` | the consent decision | **8 years** | `hold` | Proof of consent has to outlive the consent. DPD-004 is explicit that withdrawal must not delete consent history — a fiduciary that cannot show what was consented to, and when, has no defence. |
| `audit_log`, `impersonation_sessions` | the event | **8 years** | `hold` | INT-003's whole point. An audit log with a shorter life than the records it audits proves nothing about them. |
| `no_show_cases`, `follow_ups` | case close | **3 years** | `blank` | Retention analytics and a dispute record about how a member was contacted. Tracks attendance, which is what the cases derive from. |
| `notifications` | send | **1 year** | `blank` | Delivery reporting and opt-out evidence. The consent record, not this table, is the long-lived proof. |
| `messaging_wallets`, `messaging_wallet_ledger` | the movement | **8 years** | n/a | A credit ledger the gym is billed against — financial, and it holds no member personal data. |
| `addon_products`, `addon_orders`, `pt_sessions` | order completion | **8 years** for the order, **3 years** for the session | `hold` / `blank` | An add-on order is a sale (see the financial row); a PT session is operational history (see attendance). |
| `leads` | last activity | **2 years** | `delete` | A non-member's personal data held on the basis of an enquiry. The only table here whose rows a DPD-006 request removes outright — nothing financial or evidential references a lead that never converted. |
| `member_imports` | the run | **1 year** | `delete` | Its error report is a debugging artifact containing member data. It should be the shortest-lived table in the schema. |
| `organizations`, `organization_settings`, `branches`, `staff`, `platform_users`, `razorpay_accounts`, `razorpay_mandates`, `message_templates`, `organization_holidays` | account closure | **8 years** | n/a | Gym-side configuration and staff records, not member personal data. Tied to the financial clock because the gym is the platform's own customer. |

**What must be built before this is real** (Phase 8, not Phase 1): a job that applies these durations, an erasure routine implementing the `blank`/`delete`/`hold` column, and a legal review of every duration above.

## Credential rotation — outstanding

**`SUPABASE_ACCESS_TOKEN` must be rotated.** The token currently set as a repo secret was transmitted in plaintext through a chat conversation during Phase 0 to unblock the drift gate. It is a personal access token scoped to the whole Supabase account (it can see `gymloop`, `FitAi`, and `gamer_addaz`), not to one project — so its blast radius is every project in that account, not just this one. Revoke it at `supabase.com/dashboard/account/tokens`, issue a replacement, and update the secret with `gh secret set SUPABASE_ACCESS_TOKEN -R OGUN01/gymloop`. Nothing in the repo needs to change — only the secret's value.

More generally: any credential that has passed through a chat transcript, a terminal history, or a CI log should be treated as disclosed and rotated, regardless of how briefly it was exposed.

## Rate limiting and bot protection

Cloudflare Turnstile is required on OTP requests, signup, and any other public (unauthenticated) endpoint. Rate limiting applies at the edge (Cloudflare) and, for state-changing mutations, at the Route Handler layer — gate 24.

## What must never happen (a quick-scan list for review)

- A secret reaching a client bundle.
- A webhook state change before signature verification.
- A membership extension before a verified payment.
- An RLS policy that reads tenant id via a subquery instead of the JWT claim.
- A hard delete of a financial, attendance-correction, or follow-up record.
- An impersonation session with no reason, no banner, no audit row, or no expiry.
