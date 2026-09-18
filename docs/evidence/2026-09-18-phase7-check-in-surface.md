# Phase 7 staff check-in surface — verification evidence

## Contract and implementation

- [x] UX7-006/007/013/014 visual scope was frozen without changing ATT-001–008,
  identity, preview, member search, gate-code, request, event-key or retry behavior.
- [x] Tests preceded each implementation: contract `4ed2d05`; initial red test
  `48829f0`; corrected contract assertions `3ba384a`; implementation `d642938`;
  tightened fidelity contract `231ed0d`; red composition test `3ab0563` and
  selector correction `21da938`; final composition repair `0fc152a`.
- [x] Final focused suite passed 6/6. Shared/web typecheck and web lint passed.
  The final `pnpm run gates` execution passed every repository gate.
- [x] No exported symbol or library was added, so the existing registry remains
  current. Existing platform-neutral layout tokens are now emitted by the web
  adapter rather than duplicated as route literals.

## Browser and visual evidence

- [x] The first 768px tokenized pass was rejected as a dressed-up Phase 6 form.
  That NO-GO was not waived: the contract and independent tests were tightened
  before the second implementation.
- [x] At a 1600px review viewport, the final workspace measured 1440px centered
  with 32px inset. The 1361px operational region split approximately 2:1: an
  891px primary roster and 446px supporting gate panel with a 24px gap; search
  spans the canvas and outcomes span the composition.
- [x] At 390px, brand/role occupy the first account-header row and appearance /
  sign-out the second. Search, gate, roster, actions and assisted-reason controls
  collapse to one column with `scrollWidth === clientWidth` and no clipped action.
- [x] Light rendered porcelain/white/emerald and dark rendered ink/charcoal/mint.
  Both kept 32/38/600 title typography, continuous corners, fine separators and
  opaque critical surfaces. Route controls measured 44px and desk/search controls
  48px. Browser logs contained no warning, error or hydration failure.
- [x] The real owner journey opened/closed the assisted disclosure only. It did
  not issue a gate code or submit attendance, so no domain cleanup was required;
  the test session signed out.

## Review and archive

- [x] Fresh Sol re-critic returned GO against the approved member/owner v2 boards.
- [x] ADR-128 and the canonical design-system spec record that the boards are the
  per-route conformance bar, not palette inspiration.
- [x] Change archived at
  `openspec/changes/archive/2026-09-18-phase7-check-in-surface/`.
