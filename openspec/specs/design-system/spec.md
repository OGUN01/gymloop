## Purpose

Provide one platform-neutral visual language for Gymloop's member, owner and
front-desk experiences, with complete accessible light/dark appearances,
licensed English typography and immediate local interaction feedback.

## Requirements

### Requirement: Appearance is complete and persistent
UX7-003 SHALL provide System, Light and Dark appearances, apply an explicit
choice without navigation, persist that choice across reloads, and let System
follow the operating-system preference without a hydration mismatch.

#### Scenario: A user chooses an appearance
- **WHEN** the user chooses Light or Dark and reloads the application
- **THEN** the root appearance and selected control restore that choice
- **AND** only System follows a subsequent operating-system appearance change

### Requirement: English and enlarged text remain usable
UX7-004 SHALL use a locally bundled licensed Latin face and preserve meaning,
hierarchy and operable actions when text is narrow or enlarged to 200 percent.

#### Scenario: Enlarged English content reflows
- **WHEN** a surface renders English content at an enlarged scale
- **THEN** its intended glyphs and hierarchy remain clear
- **AND** shell actions reflow without clipping or losing an action

### Requirement: Reduced effects preserve the complete interface
UX7-005 SHALL make motion immediate and surfaces opaque when the corresponding
reduced-motion or reduced-transparency preference is enabled, without hiding
content, state or actions.

#### Scenario: A user requests reduced effects
- **WHEN** reduced motion or transparency is enabled
- **THEN** the same content and actions remain available
- **AND** transition duration or translucent material is removed as requested

### Requirement: Every control is accessible
UX7-006 SHALL give interactive controls accessible names and state, visible
keyboard focus, adequate pointer/touch targets and WCAG AA semantic colour
pairs in both appearances.

#### Scenario: A keyboard or assistive-technology user changes appearance
- **WHEN** focus or a screen reader reaches the appearance group
- **THEN** the group and System, Light and Dark choices have names and state
- **AND** the focused choice has a visible indication independent of colour

### Requirement: Shared tokens have one platform-neutral source
UX7-013 SHALL define semantic colour, typography, spacing, radius, target and
motion values in the shared platform-free layer, with registered web or native
adapters consuming those values rather than duplicating a palette.

#### Scenario: A platform renders the visual system
- **WHEN** web or native renders a supported Gymloop surface
- **THEN** its theme values originate in the shared token contract
- **AND** platform imports and rendering details remain outside the shared layer

### Requirement: Accepted input receives immediate local feedback
UX7-014 SHALL acknowledge a locally accepted appearance or shell interaction
within 100 ms without waiting for a network response; broader production-build
performance remains measured per surface as those slices ship.

#### Scenario: A user changes appearance
- **WHEN** a valid appearance control is activated
- **THEN** its selected state and theme acknowledge the action locally
- **AND** no network completion is represented as required for that feedback

### Requirement: Visual foundation does not alter product authority
The design system SHALL preserve existing identity, role, navigation, money and
domain response contracts; illustrative design-reference content never becomes
product data or a permission.

#### Scenario: A real owner enters the themed account shell
- **WHEN** the existing verified owner session loads an owner route
- **THEN** the shared shell adopts the selected appearance
- **AND** its route destination, data authority and response remain unchanged

### Requirement: Routes conform to the Chalkline boards (ADR-170)
UX9-005 SHALL render each member, desk, owner and platform route in the Chalkline
direction (`docs/design/phase9/direction.md`, boards in `docs/design/phase9/concepts/`):
condensed display titles and figures, hairline ledger rows instead of boxed cards,
one clay primary action per view and generous spacing, using only truthful loaded
data. Board content is illustrative and never becomes product data.

#### Scenario: A route is rendered at the owner breakpoints
- **WHEN** it renders at 390, 1024 and 1440px in Light and Dark
- **THEN** its composition follows the Chalkline boards with no page-level horizontal overflow
- **AND** no slogan, trend delta, sparkline or photo appears without a data source

### Requirement: Chalkline tokens and local Archivo
UX9-001/002 SHALL carry the Chalkline light/dark semantic palette (including a
success role), Archivo text/display/eyebrow roles and Chalkline radii in the shared
token contract. The web bundles Archivo (width and weight axes) locally; native
bundles static Archivo instances including an ExtraCondensed display cut. Every
text pair meets 4.5:1 and every control outline 3:1 in both appearances.

#### Scenario: Either platform renders text
- **WHEN** web or Android renders any Gymloop surface
- **THEN** its fonts load from the app bundle, never a runtime font CDN
- **AND** its colours come from the shared tokens

### Requirement: People see words, not stored values
UX9-003 SHALL show statuses as a dot plus a human word (never colour alone, never
the raw vocabulary value), money as rupees with Indian digit grouping via the
shared `formatMoney`, and dates, times and phone numbers through the shared
display formatters, on web and native alike. Raw values may remain in form
values and machine attributes.

#### Scenario: A payment, membership or follow-up status is shown
- **WHEN** a status vocabulary value reaches a screen
- **THEN** it renders as a toned dot and a sentence-case word
- **AND** amounts read as "₹8,000" or "₹1,500.50", never floating-point or unformatted paise

### Requirement: Recoverable and missing routes are designed states
UX9-004 SHALL render a Chalkline recoverable error with a real retry for the
console, member and platform audiences, and an honest not-found page with a way
back. Route-level streaming fallbacks are not used, because they replace or
duplicate the page's `main` landmark; navigation keeps the current page until the
next is ready.

#### Scenario: A route fails or addresses a missing record
- **WHEN** a server read throws or a record is absent
- **THEN** the user sees a Chalkline error with "Try again" or a not-found page with a link home
- **AND** the raw error text never reaches the page

### Requirement: Native parity
UX9-006 SHALL render the Android member and desk apps with the same tokens, type
roles, status language and formatters as the web, respecting safe-area insets.

#### Scenario: The member opens any tab on Android
- **WHEN** Home, Activity, My gym or You renders in Light or Dark
- **THEN** it follows the same Chalkline composition as the web boards
- **AND** its week rhythm marks the same calendar week the "N of goal" count uses

### Requirement: Staff check-in keeps visual and attendance truth together
UX7-006/007/013/014 SHALL present staff check-in on the shared token-backed
canvas with a primary member queue, supporting gate state, persistent announced
outcomes, finished controls and one-column mobile reflow, without changing the
staff identity, gate-code, assisted-reason, event-key or retry contracts.

#### Scenario: Staff opens check-in without a gate code
- **WHEN** the existing member search and gate state render
- **THEN** search, roster and gate guidance form one responsive operational composition
- **AND** direct check-in remains disabled while the assisted-reason path stays available

#### Scenario: Check-in is confirmed, refused or uncertain
- **WHEN** the existing request produces its outcome
- **THEN** the exact outcome remains the strongest announced region until explicit action
- **AND** its retry or dismissal preserves the original event and request behavior

### Requirement: The gym console uses the approved owner workspace shell
UX7-006/013/014 SHALL present authenticated gym-console routes inside the
Chalkline console rail: a truthful gym identity, permission-filtered
navigation, one exact current-route state and locally available appearance and
sign-out controls. The shell is presentation only; server loaders remain the
authority for route access.

#### Scenario: Owner or manager opens a console route on desktop
- **WHEN** the verified audience and organization data load
- **THEN** a viewport-bound slim rail shows the real organization name and gym code
- **AND** permitted destinations, theme controls and sign-out remain reachable while long route content scrolls

#### Scenario: The owner shell reflows at intermediate and narrow widths
- **WHEN** the viewport reaches 1024px or 390px
- **THEN** the rail becomes an intentional top shell without absorbing spare height or causing page overflow
- **AND** truthful identity text remains complete and navigation/account targets remain at least 44px high

#### Scenario: A generic member or platform frame loads
- **WHEN** `AccountFrame` has no console navigation/context
- **THEN** its existing horizontal account-header semantics remain unchanged

### Requirement: Follow-up is a truthful owner-board work queue
UX7-006/007/013/014 SHALL present `/red-list` as the Chalkline “People to
follow up” queue, with real member identity, current absence evidence, latest-
contact truth and the exact existing follow-up mutation contract in each row.

#### Scenario: Staff reviews and records a follow-up
- **WHEN** the longest-away-first queue contains an open retention case
- **THEN** the linked member, phone, days away, attendance and contact history remain visible
- **AND** channel, outcome, optional note, case id and `/api/follow-ups` submission remain exact

#### Scenario: The queue reflows or has no usable result
- **WHEN** the route renders at desktop, intermediate or 390px width, or its read is empty or fails
- **THEN** controls and linked identities remain unclipped 44/48px targets without page overflow
- **AND** honest empty, explicit error and cursor pagination states remain distinct

### Requirement: Owner overview reconciles one truthful snapshot
UX7-002–007/012–014 and MET-001–008 SHALL present `/dashboard` as the Chalkline
owner overview while keeping the existing single `OwnerMetrics` request
and response as its only data authority.

#### Scenario: An owner opens the operational overview
- **WHEN** the owner or manager opens `/dashboard`
- **THEN** a compact action header, exactly four primary metrics, six-case follow-up preview and renewal/recovery support form one responsive workspace
- **AND** every fact, range, currency and component row is traceable to the already loaded snapshot

#### Scenario: An owner asks for metric detail
- **WHEN** a primary or secondary metric is selected
- **THEN** an accessible local disclosure renders human names, statuses, localized times, exact money and meaningful counts from that response
- **AND** internal identifiers, raw ISO values, underscore vocabularies and literal booleans are not presented or fetched again

#### Scenario: The overview reflows through owner breakpoints
- **WHEN** the workspace renders at 1600px, 1024px or 390px in Light or Dark
- **THEN** the current-destination navigation, period control, actions and panels remain reachable with at least 44px targets and no page overflow
- **AND** the narrow navigation starts collapsed, exposes every permitted destination vertically, and preserves the exact single current-route state
