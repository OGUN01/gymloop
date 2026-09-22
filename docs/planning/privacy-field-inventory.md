# Privacy field inventory (PRIV-001..010 preparation)

**Status:** technical inventory for root/owner review; not legal sign-off and not an
erasure/export implementation contract. This file records the current schema and
conservative candidate dispositions only. An unmapped text, JSON, provider payload,
or storage URL remains protected and must block a claim of complete erasure.

**Scope and method.** The inventory is derived from the current `public` table
definitions, later `ALTER TABLE` migrations, generated row types, and
`docs/planning/privacy-operations-contract.md`. A member-linked row is either
directly keyed by `(tenant_id, member_id)`, reachable through a member-linked row
(for example `refunds -> payments -> members`), or capable of carrying a member
reference in JSON/text. `tenant_id` is always part of the subject boundary. The
candidate export column sets below are intentionally narrower than “all columns”;
they are proposals to freeze, not permission to ship.

## Disposition vocabulary

* **Candidate export** — safe to consider for the portable member export after the
  owner freezes the schema version and exact shape.
* **Blocked / protected** — never include by default (secret, token/hash,
  credentials, another person’s data, internal evidence, or an immutable accounting
  fact); retain/delete behavior still follows the frozen contract.
* **Needs decision** — personal/free-text/JSON/file/provider content whose exact
  allowlist and redaction/retention rule is not frozen.
* **Structural retain** — identifier or relationship needed for referential
  integrity and history; it is not itself a reason to expose every adjacent field.

## Direct member tables

| Table / reference | Current columns and constraints | Candidate export | Blocked / needs decision |
|---|---|---|---|
| `members` (`20260906115131_tenancy.sql`) | `id uuid PK`, `tenant_id uuid NOT NULL`, `branch_id uuid NOT NULL`, `user_id uuid NULL FK auth.users ON DELETE SET NULL`; `member_code text NULL`; `full_name text NOT NULL`; `phone text NOT NULL` with E.164 check and `(tenant_id,phone)` unique; `email`, `gender`, `date_of_birth`, `photo_url`, `notes` nullable; `status` enum NOT NULL; `joined_on date NOT NULL`; `weekly_goal_visits smallint NULL` (1..14); `rest_days smallint[] NOT NULL`; `motivation_push_enabled boolean NOT NULL`; `erased_at timestamptz NULL`; created/updated timestamps NOT NULL. | `id` (subject reference), `branch_id`, `status`, `joined_on`, `weekly_goal_visits`, `rest_days`, `motivation_push_enabled`, and timestamps only if the owner confirms lifecycle/preferences are portable. `full_name` is exportable before erasure; after erasure the generic non-PII label is exportable. | `tenant_id` is boundary metadata; `user_id` is internal identity linkage; `phone`, `email`, `member_code`, `gender`, `date_of_birth`, `photo_url`, `notes` need explicit export map. `phone`/`full_name` are currently NOT NULL; erasure draft requires a generic name and nullable phone only when `erased_at IS NOT NULL`, preserving active E.164 and uniqueness. `photo_url` needs storage-key ownership/deletion receipt. |
| `member_devices` (`20260906115159_comms.sql`) | `id`, `tenant_id NOT NULL`, `member_id NOT NULL FK`, `platform text NOT NULL` constrained to ios/android/web, `push_token text NOT NULL`, `last_seen_at NOT NULL`, `is_active NOT NULL`, created/updated NOT NULL; `(tenant_id,push_token)` unique. | `platform`, `last_seen_at`, `is_active` as device metadata if the export schema explicitly allows it. | `push_token` is direct contact/device data and is never exported; rows are candidates for deletion and push invalidation. `member_id`/tenant boundary are structural. |
| `consents` (`20260906115159_comms.sql`) | `id`, `tenant_id NOT NULL`, `member_id NOT NULL FK`, `purpose enum NOT NULL`, `granted boolean NOT NULL`, `version text NOT NULL` non-empty, `source text NOT NULL` non-empty, `recorded_at NOT NULL`, `recorded_by_staff_id NULL`, `request_key NULL`, `created_at NOT NULL`; append-only withdrawal rows (`granted=false`). | `id`, purpose, granted, version, source, recorded_at, created_at (and a non-identifying recorded-by role if later approved). | Never rewrite/delete as part of member erasure under current contract (eight-year proof/hold evidence). `recorded_by_staff_id` and request/idempotency evidence need a privacy-safe shape; raw internal verification evidence is blocked. |
| `notifications` (`20260906115159_comms.sql` plus Phase 6 comms) | `id`, `tenant_id NOT NULL`, `member_id NOT NULL FK`; channel/status enums NOT NULL; `template_key`, `dedupe_key`, `related_type`, `related_id`, `template_id`, `source_notification_id` nullable; `scheduled_for NOT NULL`; sent/delivered/clicked/converted/failed/opted-out timestamps nullable; `failed_reason`, `opted_out_reason`, `recipient_phone` nullable; `payload jsonb NOT NULL DEFAULT {}`; category nullable; created/updated NOT NULL. | Delivery/audit facts: `id`, channel, status, template key/category, scheduled/sent/delivered/clicked/converted/failed/opted-out timestamps, related type/id only when the related record is in the same subject export. | `recipient_phone`, `payload`, `failed_reason`, `opted_out_reason`, template/body-derived content, and source chains need field-level maps. One-year policy says blank direct content/failure text while retaining minimum delivery facts; JSON is PII-bearing until mapped. |
| `attendance` (`20260906115149_attendance.sql`, later Phase 7) | `id`, `tenant_id NOT NULL`, `branch_id NOT NULL`, `member_id NOT NULL FK`, `membership_id NULL FK`, `checked_in_at NOT NULL`, `checked_out_at NULL`, `source enum NOT NULL`, `qr_session_id NULL FK`, `assisted_by_staff_id NULL`, `assist_reason NULL`, `client_event_id/offline_recorded_at/replayed_at NULL`, `created_at NOT NULL`; checkout-after-checkin check; event id uniqueness. | `id`, branch, membership reference, check-in/out timestamps, source, and offline/replay timestamps as visit history. | `assist_reason` is free text and needs a map. Staff identifiers are other-person data (omit or role-normalize). Retain visit facts for three years; blank only approved member/free-text/JSON fields. |
| `no_show_cases` (`20260906115156_retention.sql`) | `id`, `tenant_id NOT NULL`, `member_id NOT NULL FK`, status enum NOT NULL, opened/last-attended dates, absent/threshold snapshots NOT NULL, assigned staff/contact/next-follow-up/returned/closed timestamps nullable, created/updated NOT NULL. | Case status, opened/last-attended dates, absent/threshold snapshots, contact/return/close timestamps. | Assigned staff identifier is other-person data. No free text currently. Three-year case facts retained; subject discovery must follow membership clock fallback. |
| `follow_ups` (`20260906115156_retention.sql`) | No direct member FK: `case_id -> no_show_cases -> member`. `id`, tenant/case/staff/channel/outcome NOT NULL; `notes`, `next_action`, `next_follow_up_at`, `corrects_follow_up_id` nullable; created_at NOT NULL. Append-only contact log; corrections point to prior row. | Contact channel/outcome and contact/next-follow-up timestamps; a redacted correction relation if needed. | `notes` and `next_action` are free text and need a field map; staff id is other-person data. Retain case/contact facts for three years. |
| `memberships` (`20260906115146_membership_money.sql` plus period migrations) | `id`, `tenant_id NOT NULL`, `member_id NOT NULL FK`, `plan_id NOT NULL FK`, status enum NOT NULL, starts/ends nullable, `price_paise`, `discount_paise`, `currency` NOT NULL, `coupon_id`/`renewal_of_membership_id` nullable, `activated_at`/`cancelled_at` nullable, `cancel_reason` nullable, `duration_days`/`periods_granted` NOT NULL, created/updated NOT NULL. Rows are period/sale history; renewal is a new row. | Sale/contract facts: id, plan/coupon references (plus portable snapshots if later defined), status, dates, price/discount/currency, activation/cancellation timestamps, duration/periods, renewal relation. | `cancel_reason` is free text and needs a disposition. Preserve member FK and immutable accounting facts; retain eight years. Do not export tenant-only plan/coupon rows merely because they are referenced unless included through this membership record. |
| `razorpay_mandates` (`20260906115146_membership_money.sql`) | `id`, tenant/member NOT NULL FKs, provider customer/subscription/plan identifiers, status enum NOT NULL, max amount/currency NOT NULL, auth/next-charge/end/cancel timestamps nullable, `raw jsonb NULL`, created/updated NOT NULL; provider subscription unique per tenant. | Status, amount/currency, lifecycle timestamps only if explicitly approved as member financial history. | Provider identifiers and `raw` are financial-adjacent personal evidence; no export/redaction/clock is frozen. Needs decision before processing. |
| `payments` (`20260906115146_membership_money.sql`) | `id`, tenant/member NOT NULL FKs; membership/mandate/coupon/staff refs nullable; amount/currency/status/method NOT NULL; provider/order/payment/receipt/idempotency refs nullable; paid_at/failed_reason/notes nullable; created/updated NOT NULL; amount/status/ids are accounting facts. | Payment id, membership ref, amount/currency, status, method, provider name, receipt number, paid_at, created_at (subject to owner approving provider identifier exposure). | Provider order/payment IDs, mandate/coupon/staff refs, `failed_reason`, `notes`, and idempotency key need field map. Never mutate amount, currency, status, ids. Retain eight years. |
| `addon_orders` (`20260906115153_catalogue.sql` plus Phase 6) | `id`, tenant/member/product NOT NULL FKs; payment/session/staff refs nullable; status, quantity, unit/total/currency, sessions_used NOT NULL; sessions_total/starts/expires/cancelled/sold timestamps nullable; `sale_request jsonb NULL`, `sale_snapshot jsonb NULL`; created/updated NOT NULL. | Order/sale facts, dates, quantity, price/currency, status and session counters; product name only via an approved portable snapshot. | `sale_request`, `sale_snapshot`, trainer/sold-by/initial-session refs, and any free text need map. Retain eight years for sale facts; do not break payment/order links. |
| `pt_sessions` (`20260906115153_catalogue.sql`) | `id`, tenant/addon order/trainer/member NOT NULL FKs, starts/ends/status NOT NULL, `notes NULL`, created/updated NOT NULL; ends-after-starts check. | Session id, add-on order ref, starts/ends/status. | Trainer is other-person data; `notes` is free text and needs map. Retain PT history three years. |

## Linked and indirect surfaces

| Surface / path | Technical member linkage and fields | Candidate export | Blocked / needs decision |
|---|---|---|---|
| `attendance_corrections` (`20260906115149_attendance.sql`) | No direct member FK: `(tenant_id,attendance_id)` -> attendance -> member. `id`, tenant, attendance, corrected_by_staff NOT NULL; `reason text NOT NULL` non-empty; `before jsonb NOT NULL`, `after jsonb NOT NULL`; created_at NOT NULL. Append-only correction history. | Correction id, attendance ref, created_at, and a schema-approved projection of before/after. | `reason`, `before`, `after` are explicitly unresolved free text/JSON; staff id is other-person data. Never rewrite append-only history without a frozen redaction rule. |
| `membership_pauses` (`20260906115146_membership_money.sql`) | No direct member FK: membership_id -> memberships -> member. All of id/tenant/membership/starts/ends/reason NOT NULL; reason non-empty; requester/approver staff refs and approval/rejection timestamps nullable; created/updated NOT NULL. | Pause dates and approval/rejection state. | `reason` needs decision (current contract explicitly calls it out); staff refs are other-person data. |
| `refunds` (`20260906115146_membership_money.sql`) | No direct member FK: payment_id -> payments -> member. id/tenant/payment/kind/amount/currency/status/reason NOT NULL; reason non-empty; provider refund/idempotency/staff/processed_at nullable; created/updated NOT NULL. | Refund id, payment ref, kind, amount/currency/status, processed_at, created_at. | `reason`, provider refund id, idempotency key, staff ref need map. Accounting amount/currency/status/id immutable; retain eight years. |
| `invoices` (`20260906115146_membership_money.sql`) | No direct member FK: payment_id -> payment -> member; one invoice per payment. Buyer name NOT NULL; invoice/payment/year/timestamps, taxable/tax totals/currency/line_items NOT NULL; seller/buyer GSTIN, place, `pdf_url` nullable; immutable invoice/accounting facts. | Invoice number/year, issued_at, tax/total amounts and currency, and a specifically approved buyer projection. | `buyer_name`, GSTINs, place of supply, `line_items jsonb`, `pdf_url` all need map. URL does not establish Storage ownership/deletion. Retain eight years; never mutate accounting facts. |
| `plans`, `coupons`, `document_counters` | No member FK. They become reachable through membership/payment references; `plans`/`coupons` are tenant catalogue rows, `document_counters` is tenant sequence state. | Export only the referenced plan/coupon label/terms if needed to make a member sale record portable; no standalone tenant catalogue export. | Descriptions/codes and coupon use need scope decision. `document_counters` is structural tenant accounting state and blocked from member export. |
| `qr_sessions` (`20260906115149_attendance.sql`) | No member FK; attendance.qr_session_id -> QR session. id/tenant/branch/token_hash/issued/expires/created NOT NULL; created-by/revoked nullable; token hash unique; expiry-after-issued check. | Issued/expiry/revocation timestamps only when needed to explain an attendance row. | `token_hash` is never exported; created-by staff is other-person data. Delete expired sessions at 90 days under policy; do not expose token material. |
| `webhook_events` (`20260906115146_membership_money.sql`) | No member FK; may carry member/payment data inside `payload jsonb`. provider/event id/type/payload/signature/received/created NOT NULL; processed/error nullable; provider+event unique. Append-only delivery evidence. | Only a redacted event type/timestamp reference if needed to explain an exported payment, after mapping. | `payload` and `processing_error` require schema-versioned mapping; provider event IDs/signatures are protected operational evidence. Retain eight years; unknown embedded subject data refuses/escalates. |
| `audit_log` (`20260906115203_platform.sql`, Phase 6 evidence) | No member FK; nullable tenant/record id; `record_type`/action NOT NULL; actor/impersonation refs nullable; `before`, `after`, `request_facts` JSON and `reason` nullable; occurred/created NOT NULL. A member can be referenced by record id or embedded facts. Append-only audit history. | At most a bounded, redacted audit reference (record type/action/time) if explicitly included in export schema. | Raw actor IDs, `before`/`after`/request facts/reason are internal verification/audit data and blocked pending contract. Never delete/rewrite; unknown JSON member discovery must refuse/escalate. |
| `member_imports` (`20260906115203_platform.sql`, Phase 6 import) | No member FK; import rows can contain a member subject and uploaded source data. id/tenant/uploader/file name/column mapping/status/created/updated; branch/request/hash/parser/country/effective/uploaded user/candidate hash additions; counts/error report nullable as typed in generated schema. | Import run status/counts and effective date only if required to explain subject provenance. | `file_name`, `column_mapping`, `error_report`, hashes, request facts and uploaded-user/staff refs can identify members or source files. Delete run/file mapping/errors at one year; before then safe discovery/redaction is required or record refusal/escalation. |
| `leads` (`20260906115203_platform.sql`, Phase 6 leads) | Converted path: `converted_member_id uuid NULL FK members`; otherwise independent lead. `full_name`, `phone` NOT NULL (phone E.164); email, lost_reason, notes, conversion/creation evidence JSON+keys, assigned/created staff refs, branch, source/stage/timestamps. | For a converted lead only, export conversion timestamp/stage and a frozen, deduplicated contact-history projection if approved. | Name/phone/email, lost_reason/notes, request facts, staff refs need a converted-lead map. Non-converted leads are not member subjects and follow two-year deletion policy. Unknown embedded references refuse/escalate. |
| `impersonation_sessions` (`20260906115203_platform.sql`) | Tenant-scoped platform support row; no member FK. Actor, reason NOT NULL; lifecycle timestamps NOT NULL/nullable; TTL and ended-after-start checks. A support action may be related through audit_log. | None by default. | Reason, actor and session evidence are internal verification/audit data; retain audit history eight years and do not expose other people’s data. |

## Explicit exclusions and structural notes

* `addon_products`, `plans`, `coupons`, `document_counters`, `message_templates`,
  `organizations`, `organization_settings`, `branches`, `staff`,
  `organization_holidays`, `messaging_wallets` and its ledger are not member
  subjects by themselves. They may be referenced to explain a member transaction;
  only the minimum approved projection belongs in that member’s export.
* `tenant_id`, foreign keys, UUIDs, timestamps, enum statuses, amounts, currency,
  and sequence/accounting identifiers are not automatically “anonymous.” They are
  classified as structural or protected according to the table above.
* There is no government-ID column in the current `members` schema. Adding one is a
  specification change, not an inventory inference.
* Generated row types in `packages/db/types/database.ts` are evidence of current
  nullability only; they are generated and must not be hand-edited.

## Proposed export allowlist baseline (pending freeze)

The portable document may start with: subject/member id; branch reference; generic
profile fields explicitly approved from `members`; lifecycle/status/join date and
approved habit preferences; consent history; membership/sale/renewal and approved
pause facts; payments/refunds/invoices with approved buyer projection; attendance;
no-show/follow-up/contact facts with redacted staff identity; notification delivery
facts without push tokens or raw payload; device platform/last-seen metadata without
push tokens; and PT/add-on records with approved product/snapshot projections.

Do not include: auth/session credentials, `members.user_id`, push tokens, QR token
hashes, internal verification evidence, raw audit rows, raw webhook/provider
payloads, other people’s identifiers, unapproved free text/JSON, or arbitrary file
URLs. Export artifacts themselves are encrypted, requester-scoped, digest-recorded,
and expire/delete per the product-configured interval; the artifact is not stored in
the privacy ledger.

## Root review checklist to freeze PRIV-001..010

- [ ] Freeze the versioned export schema and every field-level allowlist above,
      including whether habit/preferences and device metadata are included.
- [ ] Decide the exact erasure disposition for `members` nullable/NOT NULL fields,
      including the generic `full_name`, conditional `phone` nullability, and
      `user_id`/Auth-session action.
- [ ] Approve or reject maps for all listed free text/JSON: notification payload and
      failure text; attendance correction before/after/reason; pause/cancel reasons;
      payment/refund notes/reasons; add-on snapshots/requests; mandate raw; invoice
      buyer/line-items; webhook payload/errors; audit JSON/reason; import mapping,
      filename and errors; converted-lead fields.
- [ ] Freeze provider/financial and audit clocks, retention/hold precedence, and
      whether any provider identifiers may appear in exports.
- [ ] Define bounded subject discovery for indirect/embedded references and the
      fail-closed `refused`/`escalated` result for unknown JSON/text.
- [ ] Prove Storage ownership/key mapping and deletion receipts for member photos,
      invoice PDFs and export artifacts; an arbitrary URL is insufficient.
- [ ] Confirm other-person data treatment for staff/uploader/actor identifiers and
      whether exports use role labels or omit them.
- [ ] Record owner/legal review in the appropriate decision/spec artifact before
      security-sensitive tests or any implementation; this inventory itself grants
      no legal approval.

## Verification references

Primary sources inspected: `docs/planning/privacy-operations-contract.md`,
`docs/security.md`, `docs/data-model.md`, `docs/registry.md`,
`packages/db/types/database.ts`, and the migrations named beside each table (all
files under `supabase/migrations/`, especially the tenancy, membership-money,
attendance, retention, comms, catalogue, platform, leads, member-import, and Phase 7
identity migrations). No SQL, migration, application code, tests, holdout suite, or
generated type was changed by this inventory.
