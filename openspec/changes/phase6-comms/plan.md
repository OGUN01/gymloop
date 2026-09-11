# Phase 6 communications and wallet

Authorized under ADR-111 after the leads cluster. The normative
implementation contract is `docs/planning/phase6-comms-contract.md`
(COM-001..009, PAY-001..003, INT-002/003, DPD-002..004, STK-004; GL065..069),
frozen 2026-09-10 with the cross-cluster seam
(`docs/planning/phase6-contract-seam.md`). The contract is fixed before
authors are dispatched; changes require stopping and reconciling every author
first.

Comparable references reviewed with the contract (2026-09-10): WhatsApp
click-to-chat deep links (https://faq.whatsapp.com/5913398998672939) and
Twilio's conversation state model. Gymloop's frozen tenancy, consent
serialization, credit-wallet and exact-count contracts decide behavior where
references differ: no retroactive send erasure, no fabricated delivery
evidence, one ledger row per movement with balance equality.

Frozen surface:

- Migration `20260915100007_phase6_comms.sql` — `message_category` enum,
  template category/consent request keys/notification identity and evidence
  columns, wallet ledger actor/key/balance columns, all unique and composite
  indexes, the consent serialization point (`app.stamp_consent`,
  `public.record_consent`), the notification graph and evidence invariants
  (`app.enforce_notification`, `app.notification_transition_allowed`,
  `app.notification_consent_purpose`), the narrow commands
  (`public.acknowledge_notification`, `public.open_notification_whatsapp`),
  the renewal remainder helper and idempotent daily stages
  (`app.membership_renewal_remainder`,
  `app.default_renewal_reminder_windows`, `app.run_renewal_reminders`,
  `public.run_renewal_reminders_all`, the named hourly cron), wallet movement
  (`public.adjust_messaging_wallet`, `app.record_wallet_movement`, the
  `app.accept_paid_notification` service-only contract stub) and the private
  audit writers.
- Web surface: `POST /api/consents`,
  `POST /api/member/notifications/[id]/delivered`, the WhatsApp open action,
  `POST /api/message-templates`, the wallet adjust endpoint, the staff
  `/messages` screen (consent/action sections for front desk; template/wallet
  sections gym admin) and the member `/member/messages` screen with separate
  consent history.

Full blind arrangement (ADR-059): consent serialization, notification
identity/evidence, wallet money movement and the claim-derived actor checks
are silent-failure territory — independent database, unit, route and screen
authors work implementation-blind, commit red before source, and the
implementer never reads holdout files. Migrations apply only through CI;
local replays only while the DB workflow is idle.

- [x] Detailed contract verified against current schema; OpenSpec change opened.
- [x] Independent visible and holdout database tests committed red.
- [x] Independent unit, route and screen tests committed red.
- [ ] Migration, RPCs, routes and working screens implemented.
- [ ] Targeted and full local gates pass.
- [ ] Fresh-context critics return GO.
- [ ] CI applies migration; generated types, pgTAP, seed and all workflows pass.
- [ ] Real messaging journeys pass with exact cleanup.
- [ ] Current specifications, registry, evidence and roadmap synchronized; archive.
