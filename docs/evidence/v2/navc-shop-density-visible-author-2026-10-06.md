# Shop density — independent visible author evidence

2026-10-06. Test author read AGENTS.md, NAVC-008/012, the approved orange reference board, frozen public reference-layout declarations, registry excerpts and existing visible native fixture suites. No Home/Shop/native UI implementation or holdout suite was read. Only the visible reference harness and this author note were edited; no production, database or runtime Cloud changes were made.

The frozen compact-supporting-catalogue seam is covered in `apps/mobile/app/__tests__/navc-reference-layout-visible.test.tsx`. All ten previous reference-layout cases retain their assertions. Eleven additional cases cover quiet controls with existing tokens, native disabled/accessibility behavior, ordinary outline defaults, full long names, wrapping plan title/price and metadata, existing stale plan notices, service sheet details, contextual actions and unchanged product/supporting photo sizes. These are rendered public-prop checks, not a fabricated viewport-density proof. Fresh actual-device comparison remains required.

Before implementation, the focused run returned **6 failed / 15 passed / 21 total**. Failures concern concise heading copy, horizontal wrapping plan heading and metadata, quiet service layout and the quiet action border/minimum-height variant. Original ten cases, unchanged photo sizes, ordinary outline defaults and both existing stale notices pass. Targeted ESLint and mobile TypeScript checks pass; `git diff --check` is clean.

## Separate existing presentation finding

An exploratory fixture with `PlanCatalogueView.heldUnavailable = true` and `truncated = true` showed neither corresponding public PLC notice on Shop. The full plan catalogue's existing copy defines both notices. This finding is separate from the arrangement refinement: the orchestrator clarified that preserving notices refers to Shop's current loading/error/stale/offline presentation and current `planCatalogueNotice` result. No new held-unavailable/truncated requirement is included in the frozen density acceptance, and no previous assertion was removed or weakened. Follow-up evaluation of that presentation gap requires its own approved scope.

Verification commands: focused Vitest for the reference harness, targeted ESLint for the same file, mobile TypeScript check and scoped diff whitespace check. Test-first commit is left to the orchestrator's serial staging procedure.
