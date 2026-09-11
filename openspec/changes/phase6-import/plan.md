# Phase 6 member CSV import

Authorized under ADR-111 after the leads cluster. The normative
implementation contract is `docs/planning/phase6-import-contract.md`
(CSV-D01..D16), frozen 2026-09-10 with independent review GO, including the
cross-cluster seam `docs/planning/phase6-contract-seam.md`. The contract is
fixed before authors are dispatched; changes require stopping and reconciling
every author first.

Comparable references reviewed with the contract: GymMaster member import
https://help.gymmaster.com/1296032-Importing-members-from-a-spreadsheet,
GymMaster spreadsheet import limits
https://help.gymmaster.com/1296032-CSV-import-file-requirements. Gymloop's
frozen tenancy, phone-privacy and exact-count contracts decide behavior where
references differ: no cross-gym disclosure, no member overwrites, every count
from the persisted report.

Frozen surface (module layout decided here so every author imports the same
names; the contract already freezes the RPC signatures and the four HTTP
endpoints):

- `packages/shared/src/api/member-imports.ts` — shared zod schemas, limits,
  reason-code types and normalizers (platform-free, registered exports).
- `apps/web/lib/member-import-parse.ts` — CSV/XLSX parsing and XLSX streaming
  preflight; the pinned `read-excel-file` 9.3.10, `unzipper-esm` 0.13.3 and
  `saxen` 11.1.1 dependencies live here.
- `apps/web/lib/member-imports.ts` — server loader and screen types
  (`lib/leads.ts` pattern).
- `apps/web/app/api/member-imports/inspect/route.ts`,
  `apps/web/app/api/member-imports/route.ts`,
  `apps/web/app/api/member-imports/[importId]/commit/route.ts`,
  `apps/web/app/api/member-imports/[importId]/errors/route.ts` — the four
  contract endpoints.
- `apps/web/app/(console)/imports/page.tsx` + `import-forms.tsx` — the
  upload → mapping → preview → confirmation → report screen, owner/manager
  only.

The commit RPC, the v1 run invariant and the duplicate/phone boundary are
silent-failure territory (identity, RLS, money-adjacent member creation).
Full blind arrangement: independent database, unit, route and screen authors
work implementation-blind, never read each other's suites, and commit red
before source. The implementer never reads holdout files. Database migrations
apply only through CI; local candidate SQL replays migration plus
rollback-wrapped suites against the linked project only while its DB workflow
is idle.

Test split per the contract: database tests own identity/RLS/duplicates/
transitions (`supabase/tests/28/29/30` + holdout `h28`); unit tests own
CSV/XLSX parsing, limits, header/mapping and normalization; route integration
tests own exact inspect/preview/commit file binding and terminal HTTP replay;
one screen test owns the five-step journey including the
fewer-imports-than-preview warning.

- [x] Detailed contract and shared seam fixed; comparable references named.
- [x] Independent database tests committed red (visible 28/29/30 + holdout h28).
- [x] Independent unit, route and screen tests committed red.
- [x] Schema migration, prepare/commit RPCs, routes, parser and working screens implemented.
- [x] Targeted and full local gates pass.
- [ ] Fresh-context critics return GO.
- [ ] CI applies migration; generated types, pgTAP, seed and all workflows pass.
- [ ] Real import journey passes with exact cleanup.
- [ ] Current specifications, registry, evidence and roadmap synchronized; archive.
