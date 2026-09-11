# Phase 6 leads

Authorized under ADR-111 after the add-on sales cluster. The normative
implementation contract is `docs/planning/phase6-leads-contract.md`, frozen
2026-09-10 with independent review GO, including the cross-cluster seam
(`docs/planning/phase6-contract-seam.md`). The contract is fixed before
authors are dispatched; changes require stopping and reconciling every author
first.

Comparable references reviewed 2026-09-10: GymMaster lead nurturing
https://help.gymmaster.com/588988-How-to-nurture-leads-into-members,
GymMaster prospect funnel stages
https://help.gymmaster.com/686007-Setting-up-your-prospect-funnel-stages.
Gymloop's frozen tenancy, phone-privacy, CAS and exact-count contracts decide
behavior where references differ: no next-action scheduling columns, no
cross-gym disclosure, and every displayed total from one statement snapshot.

Reuse the registered identity/claim classifier, API envelope, keyset cursor
encoder/validator, `MEMBER_PAGE_SIZE_DEFAULT`/`MEMBER_PAGE_SIZE_MAX`, Temporal
gym-local input rejection, form controls and account frame. Add only the
evidence columns, triggers, RPCs, routes and components the contract proves
missing. Do not hand-edit generated database types.

`convert_lead`, the stage-graph enforcement and the phone-privacy boundary are
silent-failure territory (identity, RLS, cross-tenant disclosure). Conversion
proof uses the full blind arrangement: independent visible and holdout authors
work implementation-blind, never read each other's suites, and commit red
before source. The implementer never reads holdout files. Database migrations
apply only through CI; local candidate SQL replays migration plus
rollback-wrapped suites against the linked project only while its DB workflow
is idle.

- [x] Detailed contract and shared seam fixed; comparable references named.
- [x] Independent visible and holdout tests committed red.
- [x] Graph enforcement, conversion RPC, list read and working screens implemented.
- [x] Targeted and full local gates pass.
- [ ] Fresh-context money/security and UI critics return GO.
- [ ] CI applies migration; generated types, pgTAP, seed and all workflows pass.
- [ ] Real enquiry-to-conversion and duplicate-link journey passes with exact cleanup.
- [ ] Current specifications, registry, evidence and roadmap synchronized; archive.
