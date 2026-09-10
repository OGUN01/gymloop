# Phase 6 identity and navigation

Authorized under ADR-111 after Phase 5 refund archive `2d1213d`. The reviewed
`docs/planning/phase6-identity-contract.md` fixes the normative first-slice
signatures, claim shapes and errors. NAV-006 and NAV-008 belong to the later
platform slice; this change preserves existing gym eligibility semantics.

Comparable reference: Supabase's custom access-token hook contract, fetched
2026-09-10: https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook .
Preserve required Auth claims while resolving only the current Gymloop identity.
Member/platform homes are working baseline screens; Phase 7 owns visual redesign.

Reuse the registered UUID_PATTERN, API wrappers, Supabase clients and shared
rupeesFromPaise. No complete classifier/home selector exists in the registry or
codebase. Extend the existing formatter rather than inventing another one.
The only route added is POST /api/impersonation/end; reads use Supabase and RLS.

Independent visible and holdout authors write tests before source and never
read implementation or each other's suites. Holdout JS lives under
supabase/tests-holdout/web with an author-owned import-only Vitest bridge.
The implementer never reads holdout files. Commit red tests separately from
source. Private database changes use CI-only migration application and no
hand-edited generated types. All local database tests roll back and run only
while the shared database workflow is idle.

- [x] Reviewed contract and fetchable reference fixed before dispatch.
- [x] Independent visible/holdout tests committed red.
- [x] Identity, API, hook, preview boundary and working role homes implemented.
- [x] Targeted and full regression gates pass.
- [x] Fresh independent critic GO.
- [ ] CI migration, generated type verification and all workflows pass.
- [ ] Real role navigation and end-preview browser proof, exact cleanup.
- [ ] Current specifications, registry and evidence synchronized; archive.
