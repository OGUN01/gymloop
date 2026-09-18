# Phase 7 visual foundation — verification evidence

## Contract, tests and implementation

- [x] The frozen UX7-003–006, UX7-013 and local-feedback UX7-014 slice is in
  `openspec/changes/archive/2026-09-18-phase7-visual-foundation/plan.md`; it
  changes no identity, navigation, money or domain contract.
- [x] Contract/dependency/test/implementation sequence:
  `d383e0d`, `52bd4fc`, `16b911b`, `9bcf2d3`, `0a70f52`, `34901fa`,
  `538c0ed`, `4538388`, `ac35b97`, `a280a3e`, `2cebd39`, `1d44935`,
  `29d1855`, `3e70f28`.
- [x] The final independent focused suite passed 8/8. Web typecheck and lint,
  shared typecheck and registry-lint passed. `pnpm run gates` was rerun after
  the critic repairs and every repository gate passed on the final source.
- [x] On pushed archive commit `48612f9`, Cloud CI `35315680186`, Holdout
  `35315680617` and Test immutability `35315680296` all completed successfully.
- [x] The real-browser pass found the first provider implementation's hydration
  mismatch. A separate red contract repair (`538c0ed`) required a structurally
  stable unresolved placeholder; `4538388` made that contract green. A fresh
  tab after the repair reported no console warnings, errors or hydration issue.
- [x] The first visual judgment found camel-cased typography variables and a
  24px shell-brand target. Independent red assertions preceded `1d44935`, which
  aligned the names and raised the target to 44px. The narrow recheck then found
  the corrected 32/38 title still inherited weight 400; `29d1855` captured the
  shared-weight contract red and `3e70f28` applied its unitless 600 token.

## Real browser journey

- [x] A clean `/sign-in` load rendered the Hindi sample `आपका स्वागत है।`,
  restored Light with `data-theme=light` and exposed exactly one selected
  appearance. Switching to Dark, reloading and resolving the control restored
  Dark with `data-theme=dark`; the same reload proof passed after returning to
  Light.
- [x] Keyboard Tab focus reached System and the computed focus indication was a
  visible 3px solid outline. The appearance group and all choices had accessible
  names and state in the browser tree.
- [x] The real `gym_owner` account signed in, reached the existing console, and
  then loaded `/dashboard` with the shared dark account shell and live owner
  metrics. The route body was intentionally not restyled by this foundation
  slice. No console warning/error occurred and the test session signed out.
- [x] No domain row was written, so journey cleanup was the session sign-out;
  no seeded data needed restoration.

## Effect and architecture evidence

- [x] Source and focused tests cover reduced-motion and reduced-transparency
  fallbacks. The available browser controls did not expose those operating-system
  preference emulations, so this is not represented as a real-device check.
- [x] `UI_TOKENS` is platform-neutral. Web-only CSS emission, provider state and
  icons remain in `apps/web`; the shared package imports no web, DOM or Node API.
- [x] Approved direction references remain
  `docs/design/phase7/member-minimal-light-dark-v2.png` and
  `docs/design/phase7/owner-minimal-light-dark-v2.png`. The foundation applies
  their porcelain/ink, emerald/mint, continuous-corner and quiet-typography
  system without treating illustrative data as product truth.

## Review and archive

- [x] Fresh-context Sol visual critic returned final GO after measuring the
  rendered title at 32px/38px/600, the shell brand target at 76.56px × 44px,
  and no hydration or console errors.
- [x] Canonical requirements are synchronized at
  `openspec/specs/design-system/spec.md`; registry and ADR-127 are current; the
  change is archived at
  `openspec/changes/archive/2026-09-18-phase7-visual-foundation/`.
