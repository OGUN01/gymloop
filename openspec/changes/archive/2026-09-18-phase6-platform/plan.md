# Phase 6 platform control

Authorized under ADR-111 after metrics. The normative contract is
`docs/planning/phase6-platform-contract.md` (OPS-002/003, ONB-001–005 and
NAV-006/008), with the fixed seam, identity, metrics and communications
contracts inherited exactly. Requirements are frozen before implementation.

Frozen surface:

- Atomic gym onboarding with copied preset settings, one default branch, one
  unlinked owner, one zero wallet, gym-local trial clock and keyed audit replay.
- Canonical `plan_tier`; CAS status/tier commands; exact readiness reuse;
  activation timestamps; suspension/closure revocation; no direct commercial
  or protected staff/Auth binding bypass.
- Exact owner linking against Auth without roster disclosure, protected
  metadata preservation and incoming/outgoing session revocation.
- Eligible-gym claim issuance, explicit super-admin preview start/replay and
  expired-preview recovery, with platform support read-only throughout.
- Fleet/detail/forms use the existing response envelopes; support receives no
  mutation controls; no provider, invitation, billing or member-cap fiction.

Full blind arrangement applies because onboarding, Auth linking, claim
eligibility, session revocation, impersonation and commercial state are silent
identity/RLS/money failures. Independent visible and holdout suites land red;
the implementer reads neither suite. Migrations apply only through serialized
CI and generated database types follow the applied migration.

- [x] Platform contract and cross-cluster seams frozen.
- [x] Independent visible and holdout database tests committed red.
- [x] Independent route/screen tests committed red.
- [x] Migration, RPCs, claim/revocation boundaries and generated defaults implemented.
- [x] Platform fleet/detail/forms and route wiring implemented.
- [x] Focused and Phase 6 gates pass; fresh Sol identity/RLS/money critic returns GO.
- [x] CI migration/types/pgTAP/seed workflows pass serially.
- [x] Real super-admin/support/preview journeys pass with exact cleanup.
- [x] Specifications, registry, evidence and roadmap synchronized; archive moves this completed plan intact.
