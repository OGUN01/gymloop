# Privacy operations contract (HARD-006)

**Status:** owner-delegated draft; freeze the field maps and legal boundary before
security-sensitive tests or implementation.
It implements ADR-144: process member data to deliver the gym service, never sell it
or use it for Gymloop's independent advertising; give a verified person a portable
export and erase unnecessary personal data on request. This is not a claim of DPDP
or other statutory compliance.

This contract does not alter the durations in `docs/security.md`. They remain
engineering defaults pending qualified legal review of durations, clocks,
field-level dispositions, legal bases, DPA, and request deadlines.

## Boundaries and authorization

The gym is the Data Fiduciary and Gymloop its processor (DPD-001). A member may
request an export or erasure only for their own `(tenant_id, member_id)` after
re-authentication or other recorded verification accepted by the Fiduciary. Staff
and support may assist with submission but do not make a request verified merely
by knowing a member's details. A request never searches outside its tenant.

Each request has an immutable idempotency key, verified requester/user-evidence
reference, subject, kind (`export` or `erasure`), state, timestamps, submitter,
policy version, and refusal/escalation code. Replays return the original terminal
result or in-progress operation; changed facts under a key are refused. The
append-only privacy-operation ledger records non-PII per-item results:
`exported`, `blanked`, `deleted`, `retained_policy`, `retained_hold`,
`refused`, or `failed`. It is separate from but linked to `audit_log`; it
never stores an export or raw personal data.

Only a platform `super_admin` may place or release a case-specific legal hold.
It requires documented gym-fiduciary/legal instruction, external reference, narrow
subject/record scope, legal basis, actor and timestamps. Both actions write an
audit event. A gym owner may request/review a hold but cannot toggle one. An
active hold blocks only its stated scope.

## Export

An export is a portable UTF-8 JSON document with documented schema version,
generated-at time, tenant/member identifiers, profile, consent history,
membership/purchase history, member-identifying payments/refunds/invoices,
attendance, retention/contact history, notifications, device metadata (never
push tokens) and PT/add-on
records. It includes data held under retention or hold unless release is
prohibited by the hold instruction. It omits secrets, hashes, credentials, other
people's data, internal verification evidence and unrelated audit rows.

The artifact is encrypted at rest, access-controlled to the verified requester,
and expires/deletes after the product-configured delivery interval. The ledger
stores its integrity digest, schema/policy version, creation/expiry timestamps and
delivery outcome, not its contents. Erasure cannot start until a requested export
is terminal or explicitly cancelled.

## Erasure and field dispositions

Erasure preserves immutable identifiers needed for referential integrity but
removes data not necessary for service or approved retention/hold. It is a
privileged, transactional-per-batch operation, never direct authenticated DML. A
completed erasure sets `members.erased_at`, revokes Auth sessions, clears
`user_id`, and prevents contact, member login and future member-service
processing. Do not delete an Auth user that also has an independently valid
staff/platform identity; the request ledger records the separate Auth action.

The schema must permit `members.phone is null` **only** where `erased_at is not
null`, retaining existing E.164/non-null and tenant uniqueness for non-erased
members. Set `full_name` to one generic non-PII label; clear `phone`, `email`,
`member_code`, `gender`, `date_of_birth`, `photo_url`, `notes`, and
`user_id`. Never invent a synthetic E.164 phone. Contact and identity jobs must
exclude erased members.

| Surface | Disposition |
|---|---|
| `members` | Blank direct profile/contact fields; retain `id`, `tenant_id`, branch and non-PII lifecycle facts. |
| `member_devices` | Delete rows and invalidate push delivery; `push_token` is direct contact data. |
| `notifications` | At the one-year clock, blank direct payload/contact content and failure text; retain minimum delivery/audit facts only while policy/hold requires. JSON is PII-bearing until field-mapped. |
| `consents` | Retain as eight-year proof/hold-class evidence; never rewrite append-only history. Export it. |
| `attendance`, `attendance_corrections`, `qr_sessions` | Retain visit facts for three years; blank approved member/free-text/JSON fields. Delete expired QR sessions at 90 days; never export token hashes. |
| `no_show_cases`, `follow_ups` | Retain case facts for three years; blank `notes`, `next_action` and approved identifying/free-text fields. |
| `memberships`, `membership_pauses`, `plans`, `coupons` | Retain sale/contract facts for eight years; preserve member FKs. `cancel_reason` and pause `reason` require field-level legal/operational disposition before blanking. |
| `payments`, `refunds`, `invoices`, `document_counters`, `webhook_events` | Retain accounting facts for the existing eight-year default; never mutate amounts, currency, status, ids or sequence. Free-text, buyer fields, PDF URL, line items, payload and processing-error fields require an approved field map. |
| `addon_orders`, `pt_sessions`, `addon_products` | Retain order/sale facts for eight years and PT history for three. Blank snapshots, requests, notes and other free-text/JSON only by approved map; never break payment/order links. |
| `razorpay_mandates` | Treat provider identifiers and `raw` JSON as personal/financial-adjacent evidence; do not erase until approved financial/hold disposition. |
| `audit_log`, `impersonation_sessions` | Retain audit history for eight years. Do not delete/rewrite facts; JSON/text redaction requires an approved contract. |
| `member_imports` | Delete run, filename, mapping and error report at one year. Before then, member erasure requires safe subject discovery/redaction; otherwise record refusal/escalation. |
| `leads` | Delete non-converted leads at two years. Converted-lead export/erasure treatment requires a field map before implementation. |
| `messaging_wallets`, `messaging_wallet_ledger`, `organizations`, `organization_settings`, `branches`, `staff`, `platform_users`, `message_templates`, `organization_holidays` | Not member-subject data here; apply their existing account/financial policy separately. |

JSON, free text, file URLs and provider payloads are never assumed anonymous. Each
needs a schema-versioned export allowlist and explicit blank/retain reason before
real processing. The table above is an inventory and conservative default, not
permission to process an unmapped field. An unresolved financial/audit field
stays protected and blocks a complete-erasure claim pending qualified review.

### Unfrozen schema decisions found in the Phase 8 field audit

This is a blocker inventory, not an authorized erasure mapping:

| Member-derived field/surface | Current constraint or ambiguity | Decision required before a real erasure |
|---|---|---|
| `members.full_name`, `members.phone` | Both are `NOT NULL`; phone also has E.164 and `(tenant_id, phone)` uniqueness. | Keep one non-PII erased label for name; make phone nullable only for erased rows without weakening the active-member format/uniqueness contract. |
| `members.weekly_goal_visits`, `rest_days`, `motivation_push_enabled` | Habit/preferences are personal but the draft retained them as lifecycle facts; the latter two are non-null. | Decide to clear/reset or retain with a documented basis, then test the erased profile and downstream streak/contact behavior. |
| `invoices.buyer_name`; `refunds.reason`; `membership_pauses.reason`; `attendance_corrections.reason`, `before`, `after`; `notifications.payload`; `webhook_events.payload` | Non-null text/JSON and financial/audit semantics prevent a generic blank-all-fields routine. | Approve per-field export and retain/redact rule; retain accounting facts and case-specific holds without falsely declaring those personal fields erased. |
| `razorpay_mandates` | `member_id`, provider identifiers and `raw` JSON exist even though the online provider is disabled. | Approve the member-specific retention clock, scope and export/redaction map; the prior gym-only classification was incorrect. |
| Converted `leads`, `member_imports`, `audit_log` JSON | A member reference may be direct, converted or embedded in free text/JSON. | Define bounded subject discovery and a versioned JSON map; unknown content refuses/escalates rather than being skipped silently. |
| `members.photo_url`, invoice PDFs and exported artifacts | A URL alone is not proof of Storage object ownership or deletion. | Establish exact object-key ownership, access control and deletion receipt before reporting completion. |

## Retention policy and clocks

The runner records policy version and evaluated clock per item. It uses existing
durations only after these deterministic fallbacks are frozen:

- Membership/member: latest terminal membership `ends_on`; if none, do not
  destructively process.
- No-show: `closed_at`; if absent, do not age out.
- Add-on: terminal `completed`/`cancelled`/`refunded` timestamp; if absent,
  do not age out.
- PT: terminal-session timestamp; if absent, do not age out.
- Notification: `sent_at`, otherwise terminal failure/opt-out timestamp; a
  scheduled unsent row is neither silently retained nor deleted.
- Device: `last_seen_at`; inactive/uninstall proof may accelerate removal only
  under an approved rule.
- Import, consent, audit, transaction and visit use documented
  run/decision/event/transaction/visit timestamps. A missing clock produces
  `refused` or `failed`, never guessed deletion.

An active applicable hold wins and records `retained_hold`. Ordinary policy
retention records `retained_policy`; neither represents legal approval.

## Storage, Auth and execution safety

Photo deletion requires verifiable Gymloop Storage ownership/key mapping from the
member to the exact object. An arbitrary `photo_url` proves neither ownership nor
deletion authority. Missing mapping or deletion receipt leaves a durable
incomplete result and escalates; it never reports erasure complete. The same
applies to invoice/export artifacts where deletion is promised.

Every execution has dry-run and real modes. Dry-run resolves subject, holds,
policy, clocks and dispositions but changes no database, Auth or Storage state;
it records a distinct planned result set. Real mode uses locks/batches, durable
start/per-item results and idempotency; partial failure is non-terminal. It must
not log raw PII, tokens, provider secrets, credential URLs or export bodies.

## EARS acceptance contract

- **PRIV-001** WHEN a verified subject submits an export request, THE SYSTEM
  SHALL create one tenant-scoped idempotent request and produce only that
  subject's portable export.
- **PRIV-002** WHEN export is delivered, THE SYSTEM SHALL record digest,
  schema/policy version and expiry, and SHALL delete/invalidate the artifact at
  expiry without retaining its contents in the ledger.
- **PRIV-003** WHEN erasure executes, THE SYSTEM SHALL apply the field map,
  revoke Auth, remove device delivery, set `erased_at`, and preserve only
  justified identifiers/evidence.
- **PRIV-004** WHEN a JSON/free-text/Storage class is unknown, THE SYSTEM SHALL
  refuse or escalate the item and SHALL NOT claim full completion.
- **PRIV-005** WHEN an active applicable hold exists, THE SYSTEM SHALL retain
  only scoped items, record its reference, and continue eligible unheld actions.
- **PRIV-006** WHEN retention evaluates an item, THE SYSTEM SHALL use recorded
  policy and deterministic clock; a missing clock SHALL cause no destructive action.
- **PRIV-007** WHEN dry-run executes, THE SYSTEM SHALL record the same planned
  dispositions as real mode and SHALL make no database, Auth or Storage change.
- **PRIV-008** WHEN a request key is replayed, THE SYSTEM SHALL return the
  original result without duplicate export, redaction, deletion or audit effects.
- **PRIV-009** WHEN photo ownership/deletion cannot be verified, THE SYSTEM
  SHALL leave an incomplete result and SHALL NOT report completion.
- **PRIV-010** WHEN a hold is placed/released, THE SYSTEM SHALL require
  `super_admin`, documented external reference and narrow scope, append audit,
  and SHALL refuse a gym-owner direct toggle.

## Preconditions before implementation

Obtain qualified legal/DPA review for bases, durations, deadlines, hold wording
and financial/audit redactions. Independently author visible and holdout tests
from this contract. Required schema work: privacy request/item ledger,
case-specific holds, versioned policy evidence, narrow erased-member phone
constraint, and owned Storage-key mapping. No real retention runner or destructive
erasure is authorized until tests, migrations and review gates are complete.
