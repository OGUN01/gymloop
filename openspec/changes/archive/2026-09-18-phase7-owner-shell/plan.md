# Phase 7 owner shell

This high-leverage Phase 7 slice applies UX7-006/013/014 and ADR-128 to the
authenticated gym-owner/manager shell. The approved owner v2 board's slim
sidebar, gym switcher treatment and restrained desktop frame are the literal
bar. It changes navigation presentation only; identity, redirect, preview,
route authorization, sign-out and theme behavior remain exact.

## Frozen interface

- At desktop width, console routes render inside one centered premium frame with
  a slim left navigation rail and min-width-zero content region. Gymloop, the
  real organization name and six-character gym code are visible; no branch,
  person or location is synthesized.
- The console navigation uses the existing route and permission contracts:
  owner/manager Overview, Check-in, Follow-ups, Members, Payments, Add-ons;
  Messages/Leads only when `canViewMessages`/front-office permission allows;
  Imports only when `canImportMembers` allows. Support preview keeps its explicit
  banner and never gains a write or owner-only destination.
- A private client navigation component marks only the current route with
  `aria-current="page"` and the board's quiet mint selection treatment. It does
  not authorize access; server-side loaders remain authoritative.
- Existing System/Light/Dark and sign-out controls remain accessible and local.
  At or below 64rem the rail becomes an intentional top shell with horizontally
  scrollable/rewrapping navigation and no page overflow; at 390px identity and
  account controls retain the established two-row hierarchy and 44px targets.
- Generic member/platform `AccountFrame` callers retain their current semantics
  and do not receive console navigation. The slice adds no library, domain
  mutation, API endpoint, migration or platform-neutral token.

## Acceptance scenarios

### Requirement: The owner shell matches the generated workspace frame

#### Scenario: An owner opens a console route on desktop
- **WHEN** the verified owner shell loads with organization data
- **THEN** the sidebar shows truthful gym identity/code and permitted route links
- **AND** the current route is visibly and accessibly selected while content remains unclipped

### Requirement: Permission and preview truth survive navigation polish

#### Scenario: A restricted staff or preview identity opens the shell
- **WHEN** server identity determines its permitted destinations
- **THEN** unauthorized owner/import/front-office links are absent
- **AND** the existing preview banner, route guards, sign-out and theme behavior remain unchanged

### Requirement: The shell has an intentional narrow form

#### Scenario: The owner shell renders at 1024px and 390px
- **WHEN** the desktop rail no longer fits
- **THEN** navigation and account controls reflow without clipping or horizontal page scrolling
- **AND** every navigation/account control remains at least 44px high with visible focus

## Ownership and verification

An independent Luna author owns only
`apps/web/app/__tests__/phase7-owner-shell.test.tsx` and commits red first. Terra
owns `apps/web/app/account-frame.tsx`, `apps/web/app/console-navigation.tsx`,
`apps/web/app/(console)/layout.tsx` and private shell CSS in `globals.css`; it
never edits the test. Root owns contract, registry/evidence/spec/archive. Run the
focused test and affected web typecheck/lint during development, then one full
gate pass. A real owner light/dark journey visits `/dashboard`, `/red-list` and
`/console/check-in` at desktop, 1024px and 390px without submitting a form. A
fresh Sol critic compares the shell directly with the approved owner v2 board.

- [x] Contract and path ownership frozen.
- [x] Independent focused tests committed red.
- [x] Owner shell implemented without authority changes.
- [x] Focused checks and one full repository gate pass.
- [x] Real light/dark desktop/1024px/390px journey recorded without mutation.
- [x] Fresh Sol visual critic returns GO.
- [x] Registry/spec/evidence synchronized and change archived.
