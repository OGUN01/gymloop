# Phase 7 check-in surface

This second Phase 7 slice applies UX7-006, UX7-007, UX7-013 and UX7-014 to the
existing staff-assisted check-in route. The approved member/owner v2 boards are
the visual-fidelity bar, not loose colour inspiration: this route must reproduce
their deliberate typography, continuous geometry, whitespace, quiet chrome and
premium productivity character with its own truthful check-in content. It does
not change ATT-001–008,
the staff-only request boundary, member search, gate-code issuance, event keys,
offline/retry semantics, preview read-only behavior, navigation destinations or
any database/API response.

## Frozen interface

- `MemberSearchPage` keeps its existing props, GET search, cursor preservation,
  error copy and links. Its visual hierarchy becomes a calm check-in workspace:
  a 32/38/600 page title, quiet route actions, a single prominent search bar,
  opaque semantic surfaces and a shared-token 1440px-bounded canvas. At desktop
  width the search spans the canvas and the member queue plus gate-state panel
  form a purposeful asymmetric operational composition rather than a centered
  768px form with dead margins. Route actions are finished controls, not raw
  underlined utility links.
- `CheckInGate` keeps its existing `{ members }` prop and every request/state
  transition. Gate-code entry and issuance form one compact operational panel.
  The no-code explanation remains visible and direct; camera capability remains
  conditional; issued code stays monospaced and unambiguous.
- Each roster row shows a quiet initials mark, name, phone and explicit non-active
  status. `Check in` is the primary action and remains disabled without a gate
  code or while that member is busy. `At the desk` remains secondary and exposes
  the existing required reason form. Interactive targets are at least 44px web,
  with 48px primary desk controls.
- The latest success/refusal/retry outcome remains the strongest region on the
  page, never auto-dismisses, and is announced to assistive technology. Success
  uses the semantic action palette; refusal/retry uses semantic risk colours.
  Activating it preserves the existing retry-or-dismiss behavior.
- At wide widths, row identity and actions align without dense boxes. Below
  40rem, search, operational controls, rows and desk-reason controls stack in one
  column with no page-level horizontal overflow or hidden action. The shared
  account header also reflows intentionally at this breakpoint: brand and role
  stay together, while appearance and sign-out form one second row; the role may
  not be stranded beneath the controls as an accidental third band.
- The shared web token adapter emits the existing `geometry.layout` values with
  kebab-case `--gymloop-layout-*` names and `px` units. The workspace consumes
  `contentMaxWidth`, `desktopInset` and `mobileInset`; no duplicate width or inset
  literal is introduced.
- New selectors are private CSS class names in `globals.css`; no component,
  helper, constant, hook, schema or export is added. Existing shared tokens are
  the only visual values. No new library, generator, data read or query ships.

## Acceptance scenarios

### Requirement: Search is the first operational action

#### Scenario: Staff opens check-in or searches on a weak connection
- **WHEN** `/console/check-in` renders before client JavaScript or submits its GET search
- **THEN** the title, Red list/Members routes, labelled phone search and results remain usable
- **AND** search controls meet the shared target sizes in both appearances

### Requirement: Gate state is clear without inventing authority

#### Scenario: No current gate code exists
- **WHEN** the gate panel renders without a code
- **THEN** direct check-in remains disabled and the desk-reason path remains available
- **AND** the screen says why without presenting the public gym code as a gate token

### Requirement: The next member action is unambiguous

#### Scenario: Staff reads a member row at wide or narrow width
- **WHEN** a member is active or has a non-active status
- **THEN** name, phone, explicit non-active status and primary/secondary actions remain legible
- **AND** the row reflows without clipping, horizontal page scrolling or a lost action

### Requirement: Outcomes remain truthful and persistent

#### Scenario: A check-in is confirmed, refused or uncertain
- **WHEN** the existing request produces its current outcome state
- **THEN** the largest screen region announces the exact existing detail and member name
- **AND** it persists until the explicit existing retry, dismiss or next-attempt action

### Requirement: Styling does not alter the attendance contract

#### Scenario: The visual slice is reviewed
- **WHEN** code and browser behavior are compared with the frozen interface
- **THEN** event-key generation, payloads, endpoints, retry identity, preview disabling and copy are unchanged
- **AND** the slice performs no new read, write, role decision or domain computation

## Ownership and verification

An independent Luna author owns only
`apps/web/app/__tests__/phase7-check-in-surface.test.tsx` and commits the focused
tests red before implementation. Terra owns only
`apps/web/app/(console)/console/member-search-page.tsx`,
`apps/web/app/(console)/console/check-in/check-in-gate.tsx` and
`apps/web/app/globals.css`, plus the layout-token emission in
`apps/web/app/theme-token-style.tsx`; it never edits the test. Root owns contract, evidence,
canonical spec and archive. During implementation run only the focused check-in
surface test and web typecheck/lint. At completion run repository gates once,
then a real light/dark owner browser journey at 1440 and narrow width with no
attendance submission. A fresh Sol visual critic compares crops with the approved
owner/member v2 system and judges only this surface.

- [x] Contract and path ownership frozen.
- [x] Independent focused tests committed red.
- [x] Check-in surface implemented without behavior changes.
- [x] Focused checks and one full repository gate pass.
- [x] Real light/dark, wide/narrow browser journey recorded with no domain write.
- [x] Fresh Sol visual critic returns GO.
- [x] Registry/spec/evidence synchronized and change archived.
