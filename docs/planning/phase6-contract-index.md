# Phase 6 contract index

The owner delegated remaining decisions under ADR-111. Phase 5 verification and
archive remain the prerequisite for Phase 6 OpenSpec, tests and source. These
documents fix behavior before authors work in parallel; their existence does
not mean a feature has been implemented.

`phase6-draft.md` owns the accepted product requirements. The shared
`phase6-contract-seam.md` owns cross-cluster boundaries. Detailed contracts below
fix signatures, responses and edge cases for their cluster. The implementation
inventory records the initial repository audit and delivery order; its earlier
suggested signatures are superseded by the reviewed detailed contracts. A real
conflict is resolved before dispatch rather than left for implementers to choose.

| Contract | Independent review status | First implementation scope |
|---|---|---|
| `phase6-contract-seam.md` | GO, ADR-114 | Shared decisions only; implementation distributed by owning slice. |
| `phase6-identity-contract.md` | GO, including exact money-display addendum | NAV-001–005/007, preview write boundary, member/platform read homes, reusable exact formatter extension. |
| `phase6-leads-contract.md` | GO | Lead pipeline, explicit conversion/linking, shared gym-local time input and OPEN-008 follow-up UI. |
| `phase6-import-contract.md` | GO after final parser/privilege review | Bounded parsing, frozen preview, profiles-only atomic commit and exact report. |
| `phase6-comms-contract.md` | GO | Consent, renewal reminders, truthful free/unconfigured channels, manual wallet adjustments. |
| `phase6-addon-contract.md` | GO | Complete catalogue offers, atomic manual/complimentary sales, PT usage and refund handover. |
| `phase6-metrics-contract.md` | GO | One-snapshot owner/fleet components, exact money, shared readiness helper. |
| `phase6-platform-contract.md` | GO; ADR-115 adds the measured demo-tier correction | NAV-006/008, onboarding, owner linking, status/tier and support preview controls. |

The first slice changes no organization eligibility semantics. Commercial-field
protection and eligibility/revocation land together in the platform slice. The
metrics readiness helper is introduced with metrics and reused by activation.
Provider acceptance remains a future contract: this phase implements no paid
sender and creates no fictional provider event or debit.

Identity, RLS, money, consent ordering and wallet work use independent visible
and holdout authors. Implementation never reads holdout source. Commit the
frozen slice before authors, then tests before source; run the fresh critic,
local gates, serialized CI, real screen checks and archive for each slice.
Generated database types come only from the linked CLI after CI applies the
migration. Shared contracts may support parallel builds, but units land serially.
