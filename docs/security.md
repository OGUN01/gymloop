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
- **Retention**: a per-table retention policy is defined once Phase 1 finalizes the schema — this section is the pointer for where that table lives once written, not the policy itself (DPD-007).
- **Breach notification**: a runbook is required before launch (who is notified, within what window, by what channel) — written alongside the Phase 1 retention policy, tracked as a Phase 1 exit item in `docs/roadmap.md`.
- **Photos vs IDs**: member photos are permitted; no government-issued ID is stored in v1 (DPD-008).

## Rate limiting and bot protection

Cloudflare Turnstile is required on OTP requests, signup, and any other public (unauthenticated) endpoint. Rate limiting applies at the edge (Cloudflare) and, for state-changing mutations, at the Route Handler layer — gate 24.

## What must never happen (a quick-scan list for review)

- A secret reaching a client bundle.
- A webhook state change before signature verification.
- A membership extension before a verified payment.
- An RLS policy that reads tenant id via a subquery instead of the JWT claim.
- A hard delete of a financial, attendance-correction, or follow-up record.
- An impersonation session with no reason, no banner, no audit row, or no expiry.
