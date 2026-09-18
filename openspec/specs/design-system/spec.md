## Purpose

Provide one platform-neutral visual language for Gymloop's member, owner and
front-desk experiences, with complete accessible light/dark appearances,
licensed English/Hindi typography and immediate local interaction feedback.

## Requirements

### Requirement: Appearance is complete and persistent
UX7-003 SHALL provide System, Light and Dark appearances, apply an explicit
choice without navigation, persist that choice across reloads, and let System
follow the operating-system preference without a hydration mismatch.

#### Scenario: A user chooses an appearance
- **WHEN** the user chooses Light or Dark and reloads the application
- **THEN** the root appearance and selected control restore that choice
- **AND** only System follows a subsequent operating-system appearance change

### Requirement: English, Hindi and enlarged text remain usable
UX7-004 SHALL use locally bundled licensed Latin and Devanagari faces and
preserve meaning, hierarchy and operable actions when text is Hindi, narrow or
enlarged to 200 percent.

#### Scenario: Mixed-script content reflows
- **WHEN** a surface renders English and Hindi content at an enlarged scale
- **THEN** both scripts retain their intended glyphs and hierarchy
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

### Requirement: Approved boards are route-level conformance references
UX7-013 SHALL apply the approved v2 typography, whitespace, continuous geometry,
quiet chrome, action hierarchy and complete light/dark treatment to each user,
owner and desk route; sharing colours or fonts over an unchanged utility layout
does not satisfy the visual system.

#### Scenario: A core-loop route receives the visual system
- **WHEN** rendered desktop and narrow crops are compared with the approved boards
- **THEN** the route has a deliberate composition for its actual job in both themes
- **AND** it uses only truthful existing content rather than illustrative board data

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
