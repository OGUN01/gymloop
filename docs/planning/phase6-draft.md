# Phase 6 growth surfaces — contract draft

**Status:** DRAFT for product-owner approval. This document proposes behavior;
it does not claim that its tests, implementation, migrations or verification exist.

**Phase boundary:** finish and archive the Phase 5 cleanup before opening the Phase 6 OpenSpec change. The product owner has resolved OPEN-028: a membership's agreed amount is `price_paise - discount_paise`; ₹12,000 less ₹1,200 is fully paid by ₹10,800. Phase 5 owns making that rule true, freezing every term it reads, and proving it. Phase 6 only consumes the result in reminders and metrics.

Phase 6 ships thin working screens for add-ons, leads, imports, messaging, owner metrics, and platform operations. It does not perform the Phase 7 visual redesign.

## Contract already in force

The Phase 6 OpenSpec change must inherit these facts rather than restate or weaken them:

- `ADD-001`–`ADD-004`, `MNY-001`–`MNY-005`, `PAY-001`–`PAY-011`, `INT-001`–`INT-003`, and `DPD-002`–`DPD-004` in `docs/domain-rules.md`.
- `openspec/specs/catalogue/spec.md`: exact catalogue fields, non-negative stock, used sessions bounded by sessions bought, paid-order evidence, no order deletion, coherent validity, and no trainer overlap.
- `openspec/specs/comms/spec.md`: tenant-scoped de-duplication, append-only versioned consent, template uniqueness, per-gym device registration, non-negative wallet balance, append-only wallet ledger, and closed channel/status vocabularies.
- `openspec/specs/platform/spec.md`: platform-only users, append-only audit, converted-lead member reference, E.164 lead phones, and import provenance/counts.
- `openspec/specs/authorization/spec.md`: existing RLS role gates remain authoritative. In particular, owner/manager administer catalogue and imports; front office writes orders, consents, devices and leads; trainers write PT sessions; members read the active catalogue and only their own orders, sessions, notifications and consent history; platform support reads across gyms and writes nowhere; only super admin performs platform writes.
- The canonical state graphs in `docs/data-model.md` remain the only state vocabularies. Mutations must enforce the documented legal transitions rather than create TypeScript copies.
- ADR-016: v1 channels are push, click-to-WhatsApp and in-app; SMS and WhatsApp Business API are outside v1. ADR-017: fourteen-day trial and manual super-admin activation at launch. ADR-059: each cluster ends with a clickable screen. ADR-060: add-ons, leads, CSV import, messaging wallet and super-admin console remain v1.
- OPEN-010 is unresolved implementation debt that Phase 6 must close before sending: consent time is server-stamped, and reminder de-duplication keys have one deterministic grammar.
- OPEN-018 belongs here: gym onboarding creates the organization and its settings together, rather than relying on a trigger or allowing a gym with no settings.

## Proposed decisions that need explicit approval

The EARS requirements below assume the recommended answer in this table. Change the affected requirements before test authors are dispatched if any answer is rejected.

| ID | Decision | Recommended v1 answer | Why approval is needed |
|---|---|---|---|
| P6-D01 | Who completes an add-on sale? | Member browses and selects; front office completes payment. No unattended member checkout until Razorpay credentials exist. | The member role cannot write orders or payments, and the current product has no verified online-payment path. |
| P6-D02 | What does PT “availability before payment” mean? | A PT sale must name an active trainer and an initial session slot; the overlap constraint must accept that slot before payment is recorded. The pending order and slot are one short transaction, so no unpaid hold survives a failure. | `ADD-003` requires a check, but the current contract does not define availability. |
| P6-D03 | Add-on coupons and GST | Keep the base Phase 6 sale at catalogue list price: copy `unit_price_paise` and currency to the order, require `total = unit × quantity`, and accept no add-on coupon or derived tax split. If add-on coupons or GST invoices are required now, approve them as a separate money contract before dispatch. | The existing ADD EARS requires an exact displayed price but does not define coupon arithmetic, inclusive/exclusive GST, or the extra snapshot evidence either choice needs. |
| P6-D04 | Duplicate lead conversion | Never merge silently. Conversion may create a member only when no member has that phone; otherwise staff must explicitly link the lead to the existing same-gym member. | The unique member phone key rejects duplicates but does not define the product response. |
| P6-D05 | Import commit policy | Preview first, then import every valid unique row and skip invalid/duplicate rows. Never overwrite an existing member. | `member_imports` supports counts and an error report but does not choose all-or-nothing versus partial success. |
| P6-D06 | Renewal opt-out | A renewal reminder is a service communication. Withdrawing service consent stops it; v1 has no narrower renewal-only opt-out. | `PAY-003` names renewal opt-out, while the canonical consent vocabulary has only `service` and `marketing`. |
| P6-D07 | Providerless notification behavior | Automated renewal reminders use in-app in v1. Click-to-WhatsApp is user-assisted and may be recorded as “opened”, never “delivered”. Push remains visibly unavailable and fails with `provider_unconfigured` until a provider adapter and configuration are implemented and verified. No wallet debit occurs for any failed or zero-cost channel. | No push, SMS, email, or WhatsApp Business sender/configuration path is implemented; credentials may exist outside the repository, but Phase 6 cannot infer or claim they are usable. |
| P6-D08 | Wallet unit and funding | One credit is an internal billable send unit. Super admin may add or remove credits with a mandatory reason; only an actually accepted paid-provider send debits one credit. In-app and click-to-WhatsApp cost zero credits in v1. | The ledger exists, but credit price, funding and debit events are not specified. |
| P6-D09 | Owner account provisioning | Onboarding may create an unlinked owner staff row, but activation is blocked until an already-registered auth user is explicitly linked. The UI says “account access pending”; it never claims an invitation was sent. | There is no signup/invite workflow or outbound email credential to deliver an owner invitation. |
| P6-D10 | Suspension semantics | `suspended` and `closed` gyms cannot use gym-side sessions after the existing fifteen-minute token window; changing to either status revokes refresh sessions. Reactivation is allowed only from `suspended`. | Today organization status is a label, not an identity gate. Making it an operational control changes the claim contract and requires the full blind process. |
| P6-D11 | Preset payloads | Approve the concrete table under ONB-003. A preset is copied once during onboarding; later settings edits do not rewrite it, and changing the label does not reapply defaults. | The three enum labels exist, but their behavior is unspecified. |
| P6-D12 | SaaS tier limits | Use the existing `basic`, `growth`, `pro` labels and listed monthly prices for manual assignment only in v1. Do not enforce member caps or bill gyms until active-member thresholds and billing are approved. | ADR-017 gives indicative prices but no tier thresholds; `organizations.tier` is currently unconstrained text. |
| P6-D13 | Renewal-cycle identity and partial prepayment | Identify a reminder cycle by membership plus the `ends_on` date being renewed. Amount due for the next period is the agreed net price less only the residual eligible money not already represented by `periods_granted`; a zero-net period is due ₹0 and gets no collection reminder. | Membership-level lifetime receipts include money for periods already granted. Subtracting them from one price would suppress every later renewal, while a key with no cycle anchor could never be reused. |

## Cluster A — add-on catalogue, orders and usage

**Roles:** owner/manager administer catalogue; owner/manager/front desk sell and view orders; trainers schedule and complete PT sessions; members browse active catalogue and see only their own usage.

**Screens:** `/add-ons` (catalogue, stock and orders), `/add-ons/orders/[orderId]` (payment and usage history), `/member/add-ons` (active catalogue and own orders). **Mutations:** `/api/add-ons`, `/api/add-on-orders`, `/api/add-on-orders/[orderId]/sessions`, with the existing typed envelope and claim-derived tenant/actor.

- **ADD-005** WHEN an owner or manager publishes an add-on THE SYSTEM SHALL require every field ADD-002 makes visible, SHALL validate the kind-specific stock/session/trainer fields, and SHALL hide inactive items from new purchases while preserving their order history.
- **ADD-006** WHEN a member or staff member views an active add-on THE SYSTEM SHALL show the final unit price and currency, validity, cancellation terms, and either trainer qualification and sessions for PT or current stock for a product; THE SYSTEM SHALL pre-select none (ADD-001).
- **ADD-007** WHEN front office creates an order THE SYSTEM SHALL snapshot the existing order fields: product, quantity, unit price, total, currency, validity, trainer and sessions; SHALL derive tenant and actor from verified claims; and SHALL reject any client-supplied status, stock decrement or usage count.
- **ADD-008** WHEN an order is priced THE SYSTEM SHALL copy unit price and currency from the selected catalogue row and require `total_paise = unit_price_paise × quantity`. The base Phase 6 route SHALL reject an add-on coupon with an actionable unsupported-feature error unless P6-D03 is replaced by an approved money contract.
- **ADD-009** WHEN a product order becomes paid THE SYSTEM SHALL decrement stock exactly once by its quantity and advance the order through `active` to `completed`; IF stock is insufficient THEN THE SYSTEM SHALL record neither a paid payment nor a completed order (ADD-004).
- **ADD-010** WHEN a PT order is submitted for payment THE SYSTEM SHALL require an active trainer and an initial session slot accepted by the no-overlap constraint before recording payment; IF the slot is unavailable THEN THE SYSTEM SHALL record neither paid payment nor live booking (ADD-003).
- **ADD-011** WHEN a PT session becomes `completed` THE SYSTEM SHALL increment its order's `sessions_used` exactly once; cancelled/no-show sessions SHALL consume none, and the final used session SHALL complete the order. A retry SHALL not consume a second session.
- **ADD-012** WHEN a diet order becomes paid THE SYSTEM SHALL make it active until staff completes it or its validity expires. WHEN a full completed refund exists THE SYSTEM SHALL move a paid/active order to `refunded` and refuse later usage; a partial refund, or a refund after the terminal `completed` state, SHALL remain visible from refund rows without inventing an unsupported order transition.
- **ADD-013** THE SYSTEM SHALL enforce every documented `addon_order_status` and `pt_session_status` transition, SHALL never hard-delete an order, and SHALL show the linked receipt/refund rows on the order screen.

**Acceptance:** Journey C is demonstrable without a provider: member selects one active add-on, staff records verified manual payment, stock or PT usage changes once, receipt is linked, member sees usage, and owner sees the same order in utilisation. A duplicate request changes no count or money row. This money-adjacent cluster uses the full blind test/implementer/critic arrangement.

## Cluster B — leads and enquiries

**Roles:** owner/manager/front desk only; trainers and members have no lead access. **Screen:** `/leads` with stage, assignee, next action, trial time and conversion. **Mutations:** `/api/leads` and `/api/leads/[leadId]/convert`.

- **LEAD-001** WHEN front office records an enquiry THE SYSTEM SHALL require a branch, name, E.164 phone and canonical source, SHALL derive tenant from the claim, and SHALL create the lead at `new`.
- **LEAD-002** WHEN a lead changes stage THE SYSTEM SHALL enforce the canonical graph; `trial_scheduled`/`trial_done` SHALL require `trial_at`, `lost` SHALL require a non-empty `lost_reason`, and `converted` SHALL require both member and conversion time. `converted` and `lost` SHALL be terminal.
- **LEAD-003** WHEN a lead converts with no same-gym member phone match THE SYSTEM SHALL create the member and link the lead in one transaction. WHEN that phone already belongs to a member THE SYSTEM SHALL refuse automatic creation and offer an explicit link to that member; a cross-gym member SHALL never be revealed or linked.
- **LEAD-004** WHEN two conversion requests race or one is retried THE SYSTEM SHALL produce one converted lead and at most one new member. A converted lead SHALL never be converted again or relinked.
- **LEAD-005** THE SYSTEM SHALL let staff filter by stage/source/assignee and act from the list; every displayed total SHALL equal the rows returned by the same filters.

**Acceptance:** create → contact → trial → convert works from the screen; duplicate-phone conversion gives a useful link-existing-member choice; retry creates nothing extra; lost reason and terminal stages remain visible.

## Cluster C — CSV/Excel member import

**Roles:** owner/manager only. **Screen:** `/members/import` with upload, mapping, preview, confirmation and downloadable error report. **Mutation:** `/api/member-imports`.

- **CSV-001** WHEN an owner/manager uploads UTF-8 CSV or `.xlsx` THE SYSTEM SHALL parse the first worksheet/header row, SHALL store the original file name and acting staff id, and SHALL require mappings for full name and phone. Optional mappings SHALL use existing member fields only.
- **CSV-002** WHEN a mapping is previewed THE SYSTEM SHALL normalise whitespace and phone values, treating a bare ten-digit Indian mobile as `+91…` only when India is selected as the import country; ambiguous phones and invalid dates SHALL be row errors, never guessed values.
- **CSV-003** THE SYSTEM SHALL classify duplicates separately: an existing same-gym phone, a repeated phone inside the file, and a conflicting same-gym member code. It SHALL reveal nothing about another gym and SHALL never overwrite an existing member.
- **CSV-004** WHEN the user confirms a preview THE SYSTEM SHALL import each valid unique row once and skip every duplicate or invalid row. `row_count` SHALL equal `imported_count + duplicate_count + invalid-row count in error_report`; counts SHALL never be estimates.
- **CSV-005** WHEN an import is retried THE SYSTEM SHALL create no duplicate members; previously imported phones SHALL appear as duplicates. IF processing fails before completion THEN no unreported member write SHALL survive, and the run SHALL be `failed` with an actionable error report.
- **CSV-006** THE SYSTEM SHALL create member profiles only. It SHALL not invent memberships, payments, consent, attendance or government-ID fields from an import.

**Acceptance:** a mixed file previews deterministic mapping/errors, confirmation imports only the promised rows, retry creates zero new members, counters reconcile, and another gym's phone is not treated as a visible duplicate.

## Cluster D — consent, reminders, delivery and wallet

**Roles:** owner/manager manage templates and see queue/wallet; front office records consent and operates click-to-WhatsApp; members see own notification/consent history; only super admin adjusts wallet balance. **Screen:** `/messages` with templates, scheduled/sent/failed rows, consent state and wallet ledger. **Mutations:** `/api/consents`, `/api/notifications/[notificationId]/open-whatsapp`, `/api/platform/wallet-adjustments`.

- **COM-001** WHEN a consent decision is recorded THE SYSTEM SHALL stamp `recorded_at` on the server, append a versioned row, and derive member/tenant/actor from verified context. Current consent SHALL be the latest server-stamped row per member and purpose; history SHALL remain immutable.
- **COM-002** THE SYSTEM SHALL classify renewal/payment/fulfilment messages as `service`, promotions as `marketing`, and motivation messages as service messages additionally gated by `motivation_push_enabled`. IF the applicable consent is absent or withdrawn THEN THE SYSTEM SHALL create no send attempt, or SHALL move an already-scheduled one to `opted_out` before sending.
- **COM-003** WHEN the renewal scheduler reaches a configured gym-local offset THE SYSTEM SHALL create at most one in-app notification using `renewal:<membership_id>:<ends_on>:<window_id>`, where `ends_on` is the expiry being renewed; a rerun for that cycle SHALL change nothing. It SHALL stop that cycle after cancellation, service-consent withdrawal, or the next-period remainder reaching zero (PAY-001–003).
- **COM-004** THE SYSTEM SHALL compute the next-period remainder from Phase 5's own paid-period accounting: agreed amount `A = price_paise - discount_paise`; residual eligible money `R = eligible paid total - (periods_granted × A)`; amount due `max(0, A - R)`. IF `A = 0` THEN amount due SHALL be zero without division, and no collection reminder SHALL be created. “Eligible paid total” SHALL be the same payment population used by the approved Phase 5 period-grant rule, never a second reminder-specific copy.
- **COM-005** WHEN an in-app notification is made available THE SYSTEM SHALL mark it `sent`; it SHALL mark `delivered` only when the member surface actually reads it. WHEN staff opens a `wa.me` link THE SYSTEM SHALL record `sent` and label it “opened in WhatsApp”; it SHALL not claim delivery, click or conversion without a corresponding event.
- **COM-006** WHEN a push send is attempted without an approved provider configuration THE SYSTEM SHALL move the notification to `failed` with stable reason `provider_unconfigured`, leave `sent_at`/`delivered_at` null, debit no wallet credit, and show the missing setup on `/messages` and the platform gym page.
- **COM-007** WHEN a paid provider accepts a send THE SYSTEM SHALL append one negative wallet ledger row tied to that notification and update the balance atomically. Insufficient balance SHALL leave the notification unsent and the wallet non-negative. In-app and click-to-WhatsApp SHALL append no debit.
- **COM-008** WHEN super admin adjusts credits THE SYSTEM SHALL require a non-zero delta and reason, append one ledger row, audit the action, and reject a debit that would make balance negative. Gym-side users and platform support SHALL have no adjustment path.
- **COM-009** THE SYSTEM SHALL enforce the canonical notification transitions and make every queue count drill into exactly those rows. A send retry SHALL reuse the same notification/dedupe key rather than create another stage.

**Acceptance:** scheduler rerun creates one row; consent withdrawal prevents delivery; click-to-WhatsApp never says delivered; missing push credentials produce a visible failure and zero debit; wallet adjustment and balance reconcile exactly to the append-only ledger.

### Provider readiness at draft time

| Capability | Current evidence | Truthful Phase 6 behavior |
|---|---|---|
| In-app | Needs no external credential | May send and record actual member reads. |
| Click-to-WhatsApp | `wa.me` needs no provider credential | User-assisted open only; no delivery receipt. |
| Push | No sender or validated provider-configuration path is implemented | Blocked until provider choice, implementation and verified configuration; never report sent. |
| SMS/email | No sender/configuration path is implemented; ADR-016 excludes SMS in v1 | No send path. Email may be revisited only for owner invitations after a provider decision. |
| WhatsApp Business API | Explicitly deferred by ADR-016 | No automated send or wallet charge. |
| Razorpay | Phase 5 gap remains credential-blocked | No unattended member checkout; manual verified desk payments remain usable. |

## Cluster E — owner metrics that reconcile

**Roles:** owner/manager. **Screen:** `/dashboard`; cards are links to filtered row lists, not decorative charts. Reads go through the caller's Supabase session and RLS. Every response carries one `asOf` instant, gym timezone, range start/end and currency.

- **MET-001** WHEN an owner opens the dashboard THE SYSTEM SHALL evaluate date boundaries in the gym timezone and use one captured `asOf` instant for every card, so cards cannot disagree because they were queried at different times.
- **MET-002** “Visits today” SHALL count attendance rows whose `checked_in_at` falls on the current gym-local date. “Live members” SHALL count distinct members with a membership in `active` or `frozen` whose dates include `asOf`; paused members SHALL be shown separately from approved pauses covering that date.
- **MET-003** “Open red list” SHALL count cases in `open`, `contacted` or `follow_up_due`; “follow-ups due” SHALL count live cases whose `next_follow_up_at <= asOf`; “recovered” SHALL count cases whose `returned_at` falls in the selected range.
- **MET-004** “Collected” SHALL sum payments carrying evidence they entered `paid`, by `paid_at` in the range. “Returned” SHALL sum completed refunds/reversals by `processed_at` in the range. “Net cash movement” SHALL be collected minus returned, grouped by currency with no conversion.
- **MET-005** “Renewal amount due” SHALL sum the COM-004 next-period remainder for memberships whose current `ends_on` falls in the selected range, grouped by membership currency. It SHALL not subtract lifetime receipts from a single period price; payments already represented by `periods_granted` are already spent on earlier periods. A zero-net membership SHALL contribute ₹0 without division.
- **MET-006** “Lead conversion” SHALL use a created-in-range cohort: converted leads from that cohort divided by all leads in that cohort. The card SHALL show numerator and denominator and handle zero denominator without division.
- **MET-007** “Add-on net revenue” SHALL use payments linked from add-on orders minus their completed refunds/reversals in the selected range. “PT utilisation” SHALL show `sum(sessions_used) / sum(sessions_total)` over the selected range's paid/active/completed, non-refunded PT-order cohort, with both values visible.
- **MET-008** WHEN any metric is selected THE SYSTEM SHALL show the exact underlying rows and the same filters; the displayed count or sum SHALL reconcile exactly to those rows. The dashboard SHALL not use manually maintained summary numbers in v1.

**Acceptance:** for a fixed `asOf`, timezone and range, an independent sum/count over each drill-down equals its card exactly, including refunds, discounts, zero denominators, and two payments at the same timestamp.

## Cluster F — super-admin fleet, onboarding and operational controls

**Roles:** platform support reads; super admin reads and mutates. **Screens:** `/platform` (fleet and exceptions) and `/platform/gyms/[gymId]` (status, tier, settings completeness, provider readiness, wallet and impersonation). **Mutations:** `/api/platform/gyms`, `/api/platform/gyms/[gymId]/status`, `/api/platform/gyms/[gymId]/owner-link`, plus the wallet endpoint in Cluster D.

- **OPS-001** WHEN a platform user opens the fleet THE SYSTEM SHALL show every gym's name, code, status, tier, trial end, active-member count, open red-list count, failed-notification count, settings completeness and provider readiness. Support SHALL see the same facts with no mutation controls.
- **OPS-002** WHEN super admin changes gym status THE SYSTEM SHALL enforce the canonical `organization_status` graph, require a reason for suspend/reactivate/close, write an audit row, and apply the approved suspension semantics. Gym owners may still edit permitted profile fields, but SHALL NOT change `status`, `tier`, trial or activation fields; platform support and other gym roles SHALL affect zero commercial fields.
- **OPS-003** WHEN super admin starts impersonation THE SYSTEM SHALL require the existing reason and hard expiry, attribute the session to the actor, and show the persistent red banner for its duration. Support SHALL have no start control.
- **OPS-004** WHEN the fleet reports a count or exception THE SYSTEM SHALL link to the exact gyms/rows that produce it. “Provider ready” SHALL be false until a real provider configuration is verified; a database row or placeholder secret alone SHALL not count.
- **ONB-001** WHEN super admin creates a gym THE SYSTEM SHALL create the organization, exactly one `organization_settings` row, one default branch, one messaging wallet, and one owner staff row in one transaction. Failure of any child write SHALL create none, closing OPEN-018.
- **ONB-002** THE SYSTEM SHALL generate a unique six-character gym code, set the fourteen-day trial from the gym-local onboarding date, and keep activation manual. Activation SHALL be refused until settings, default branch, owner identity link, timezone and currency are present.
- **ONB-003** WHEN a preset is selected THE SYSTEM SHALL copy these proposed defaults once:

  | Preset | No-show threshold | Streak rule | Weekly goal | Max freeze/year | Pause approver |
  |---|---:|---|---:|---:|---|
  | `neighbourhood_gym` | 7 days | `visit_streak` | 3 | 30 days | `gym_manager` |
  | `premium_studio` | 5 days | `weekly_goal` | 3 | 30 days | `gym_manager` |
  | `functional_box` | 3 days | `weekly_goal` | 4 | 14 days | `gym_manager` |

- **ONB-004** WHEN onboarding has no linked owner auth user or no invitation provider THE SYSTEM SHALL show “account access pending”, SHALL send nothing, and SHALL keep activation unavailable. Linking SHALL require an existing auth user and SHALL be explicit and audited.
- **ONB-005** WHEN a tier is assigned THE SYSTEM SHALL accept only `basic`, `growth` or `pro`, show the registered monthly price, and treat it as a manual commercial label in v1; it SHALL enforce no unapproved member cap and create no platform charge.

**Acceptance:** an onboarded gym always has settings/default branch/wallet; a deliberately failed child write leaves no partial gym; support cannot mutate; super admin status changes and impersonation are audited; unconfigured providers and unlinked owners remain visibly pending; every fleet count drills into its rows.

## Build order after approval

1. Close and archive Phase 5, including the approved net-price rule. Freeze this Phase 6 contract and record the approved P6 decisions.
2. Land the serial contract seam: OPEN-010, common status-transition/error/idempotency conventions, and any schema snapshot fields approved by P6-D03. Because it touches consent integrity, money and notification de-duplication, use the full blind arrangement.
3. Build independent vertical clusters B (leads), C (imports), and the provider-independent part of D (consent/in-app/WhatsApp truthfulness). Each owns its route, screen and API schemas end to end.
4. Build A with the full money-path arrangement. Then build E against the now-fixed underlying rows.
5. Build F last because its fleet reads all clusters and its suspension/onboarding paths touch identity. Use the full blind arrangement for suspension and owner linking.
6. Run the Phase 6 gates and Journey C, reconcile every owner metric, archive the OpenSpec change, and stop. Phase 7 redesign is a separate future phase.

## Phase 6 exit criteria

- Every cluster has its named clickable screen and role-correct mutation path.
- Journey C works with a manual verified payment and exactly-once usage/stock behavior.
- Lead conversion and import retries create no duplicate member.
- Consent, reminders, delivery states and wallet entries tell only events that actually happened.
- Every owner and fleet number drills into, and exactly equals, its underlying rows at the stated `asOf`.
- A newly onboarded gym cannot exist without settings and a default branch, and cannot activate with an unlinked owner or fake provider readiness.
- The approved contract, tests-first commits, required blind suites for money/identity/RLS, gates, evidence and OpenSpec archive are complete before the phase ends.
