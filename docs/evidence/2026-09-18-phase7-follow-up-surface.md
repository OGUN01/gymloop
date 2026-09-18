# Phase 7 follow-up surface — verification evidence

## Contract and implementation

- [x] UX7-006/007/013/014 and ADR-128 were frozen for presentation only. The
  route, loader, longest-away ordering, permissions, preview behavior, cursor,
  generated enums, form names and `/api/follow-ups` mutation stayed unchanged.
- [x] Tests preceded implementation: contract `368b391`; initial red test
  `3903573`; contract repairs `1b80a7c` and `f8091c3`; implementation `77fffba`.
- [x] The first fresh Sol critic returned NO-GO only for clipped desktop
  Outcome/Note content and 24px mobile member links. Independent regression
  `dd8c7ad` was red before focused CSS repair `96650b7` made it green.
- [x] Final focused suite passed 6/6; web typecheck/lint passed for the source
  pass, lint passed for the CSS-only repair, and the single final
  `pnpm run gates` execution reported `ALL GATES GREEN`.
- [x] No export, helper, dependency, query, migration or database type changed;
  the registry and database remain current.

## Browser and visual evidence

- [x] Real owner data rendered longest-away first with linked member identity,
  current days away, last-attendance truth and explicit latest-contact truth.
  No illustrative board member, visit or recovery value was copied into product data.
- [x] At 1600×900 in Light and Dark, the repaired Outcome control measured
  122.8×48px and fully showed `will_return`; Note measured 160×48px and fully
  showed “What they said.”
- [x] At 390×844 in Light and Dark, all 25 rendered member-name links measured
  exactly 44px high and all row controls measured 48px. At 1024px,
  `scrollWidth === clientWidth === 1009px` after the form moved to its related
  full-width row.
- [x] The approved owner v2 “People to follow up” region was the comparison bar:
  quiet initials, restrained separators, prominent absence evidence, compact
  truthful contact history and emerald/mint actions remained consistent across themes.
- [x] Browser warning/error count was zero. No follow-up form or membership link
  was submitted/opened, so no demo data changed and no cleanup was required.

## Review and archive

- [x] Replacement fresh Sol critic returned GO after independently measuring
  the two cited regressions and intermediate-width overflow.
- [x] Canonical design-system spec, roadmap and campaign state were synchronized.
- [x] Change archived at
  `openspec/changes/archive/2026-09-18-phase7-follow-up-surface/`.
