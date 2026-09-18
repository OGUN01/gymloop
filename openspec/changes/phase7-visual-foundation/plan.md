# Phase 7 visual foundation

This first Phase 7 slice implements UX7-003–006, UX7-013 and the local-feedback
portion of UX7-014 from the owner-approved experience PRD. It establishes the
shared visual language on sign-in and the authenticated account shell without
changing authentication, navigation destinations, domain responses or writes.

## Frozen interface

- `packages/shared/src/config/constants.ts` exports one platform-neutral
  `UI_TOKENS` object. It contains the PRD's light/dark semantic colours,
  typography sizes/line heights, spacing, radii, target sizes and motion
  durations as strings or numbers with no DOM, React, Next or native import.
- `apps/web/app/theme-provider.tsx` exports `AppThemeProvider` and
  `ThemeControl`. The provider uses `data-theme`, System/Light/Dark, system as
  the default, and the stable `gymloop-theme` storage key. The control is one
  named group with three named pressed-state buttons; before client resolution
  it renders a same-size noninteractive placeholder.
- `apps/web/app/theme-token-style.tsx` exports `ThemeTokenStyle`, the web adapter
  that emits trusted CSS custom properties from `UI_TOKENS`. There is no token
  generator and no duplicated palette in CSS.
- The root layout installs the token style and provider with only a scoped root
  hydration exception. `globals.css` owns the semantic base, focus, selection,
  reduced-motion/transparency and reusable non-exported class vocabulary.
- The web font source is locally bundled Inter and Noto Sans Devanagari WOFF2
  with upstream licensing retained. Latin and Devanagari font variables are
  selected by content rather than assuming Inter covers Hindi.
- `AccountFrame` and sign-in consume the system immediately. `AccountFrame`
  retains its existing `{children, home, label}` API and sign-out behavior.
  This slice does not invent audience navigation or restyle route-specific
  metrics/business content.

## Acceptance scenarios

### Requirement: Appearance is complete and persistent

#### Scenario: A user selects an explicit appearance
- **WHEN** the user selects Light or Dark
- **THEN** the root `data-theme` changes without navigation and the choice is restored after reload
- **AND** System continues to follow the operating-system preference

### Requirement: Foundation remains accessible

#### Scenario: A keyboard or screen-reader user reaches the appearance control
- **WHEN** focus enters the control
- **THEN** the group and all three choices have names, visible focus and pressed state
- **AND** controls meet the PRD target sizes and semantic colour pairs

#### Scenario: Hindi or enlarged text is rendered
- **WHEN** the shell contains Devanagari or text is enlarged to 200 percent
- **THEN** the licensed Devanagari face renders and shell actions reflow without clipping

### Requirement: Reduced effects keep the interface complete

#### Scenario: Reduced motion or transparency is requested
- **WHEN** the matching browser preference is enabled
- **THEN** navigation and controls retain content/actions with immediate motion and opaque surfaces

### Requirement: Tokens are shared and honest

#### Scenario: Web consumes the visual system
- **WHEN** sign-in and an authenticated account shell render in either theme
- **THEN** their colour, type, spacing, radius and motion values originate in `UI_TOKENS`
- **AND** no authentication, role, money, metrics or navigation contract changes

## Ownership and verification

An independent Luna author owns only
`apps/web/app/__tests__/phase7-theme-foundation.test.tsx` and commits red tests
before implementation. Terra owns the listed shared token and web foundation
files after that commit, but never the test file. Root alone owns dependency,
lockfile, registry, evidence and archive changes. Focused tests plus web/shared
typecheck and lint run during implementation; the full repository gates run
once after the slice. Browser acceptance covers sign-in and one real owner page
in light/dark, reload persistence, keyboard focus, a Hindi glyph sample and
reduced-motion/transparency emulation where the browser exposes it. A fresh Sol
visual critic reviews rendered light/dark crops against the approved references.

- [x] Contract and path ownership frozen.
- [ ] Independent focused tests committed red.
- [ ] Tokens, fonts, theme provider/control and immediate consumers implemented.
- [ ] Focused checks and one full repository gate pass.
- [ ] Real light/dark browser journey and visual crops recorded.
- [ ] Fresh Sol visual critic returns GO.
- [ ] Registry/spec/evidence synchronized and change archived.
