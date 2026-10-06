# native-member-discovery Specification

## Purpose

Give members a clear primary navigation and contextual access to shopping, membership actions, personal messages and mixed-activity classes without crowding the bottom bar.

## Requirements

### Requirement: NAVC-002 enabled member navigation
WHEN the tenant's confirmed Classes visibility is On, the system SHALL show exactly Home, Classes, Shop, You, Activity in that order, including when no class is scheduled today. The Classes label SHALL remain Classes for every business type.

#### Scenario: Enabled empty timetable
- **WHEN** an enabled dance academy has no session today
- **THEN** five tabs remain visible and the timetable offers other dates with truthful empty wording

### Requirement: NAVC-003 disabled discovery preserves commitments
WHEN visibility is Off, the system SHALL show Home, Shop, You, Activity, retain My classes and personal training in You or the business hub, and return a currently selected primary Classes destination to Home. My classes SHALL display caller-owned commitments independently of catalogue activity and branch filters.

#### Scenario: Owner hides Classes after booking
- **WHEN** Classes is switched Off while a member is viewing the primary Classes destination
- **THEN** the app returns to Home without cancelling a booking and the member can open My classes and its permitted cancellation action from the business hub

### Requirement: NAVC-006 unresolved and cached visibility
WHILE the first authorized visibility read is unresolved, the system SHALL present stable loading and retry without interpreting absence or failure as Off, with the existing sign-out action available to a verified member. It SHALL retain an exact-identity confirmed value during temporary read failure, refresh on resume/focus, and clear it on sign-out/replacement. Late reads SHALL not affect a replacement identity.

#### Scenario: Connection fails after a confirmed On read
- **WHEN** an On value was confirmed for the current identity and the next read fails
- **THEN** Classes remains visible with recoverable state and another tenant cannot reuse that value

#### Scenario: Initial visibility unavailable and account switching
- **WHEN** a verified member's first visibility read is pending or failed
- **THEN** the member can use the existing sign-out action without entering a primary tab or receiving an invented Off value

### Requirement: NAVC-007 secondary routes and desk navigation
WHEN Buy, Freeze requests, full announcements or Training is opened, the system SHALL keep those destinations outside the primary tab buttons and preserve existing role guards. The desk SHALL have at most five primary destinations and expose native Training through More only for authorized trainers. Shop SHALL provide Buy access and the business hub SHALL provide plan-renewal and Freeze requests access beside membership.

#### Scenario: Contextual member actions
- **WHEN** a member opens Buy from Shop or Freeze requests from membership
- **THEN** the intended screen is reachable and no lowercase or extra tab appears

#### Scenario: Trainer desk
- **WHEN** a trainer opens More
- **THEN** native Training is reachable without a sixth tab and other roles retain their existing permission boundary

### Requirement: NAVC-008 catalogue-first Shop
WHEN Shop opens, the system SHALL show saved-category Products, Plans and Services before purchase access and reservations. Missing categories SHALL use Other products; missing/invalid images SHALL use the existing honest placeholder. It SHALL show three reservations, reveal five more per explicit Load more tap from the existing response, disclose hidden active reservations and retain hold deadlines/cancellation actions. It SHALL not claim database pagination.

#### Scenario: Uncategorised product and six reservations
- **WHEN** the response has an uncategorised product with no image and six reservations
- **THEN** the product appears before reservations under Other products, the first three reservations appear with an accessible additional-active count where applicable, and one Load more tap reveals the remaining three

### Requirement: NAVC-009 distinct compact Home updates
WHEN Home opens, the system SHALL show at most one compact Messages for you preview near membership, with access to the existing personal-message list, and at most two shared announcements below Last visit under From your gym, studio or academy. View all SHALL open a separate non-tab list. It SHALL preserve announcement read/version/consent/cache behavior and SHALL add no bell or duplicate update banner.

#### Scenario: Both message types available
- **WHEN** one personal message and three announcements exist
- **THEN** membership has one personal preview, only two shared previews appear after Last visit, and View all opens the full shared list without marking unseen cards read

### Requirement: NAVC-010 business wording and mixed activities
WHEN a supported business type is saved, the system SHALL use the existing business nouns for the business hub, shared announcement heading, instructor/teacher context and timetable content. Services SHALL retain their actual names independently of type. Business type SHALL not determine access to activities or silently change when an activity is added.

#### Scenario: Gym offers Yoga and Zumba
- **WHEN** a gym has Yoga and Zumba services
- **THEN** both appear by their service names while the business remains a gym

### Requirement: NAVC-011 activity filtering
WHEN a member selects an activity or date, the system SHALL filter authorized timetable rows by stable service identity and branch-local session date, order occurrences chronologically, reset a removed activity selection, display a truthful filtered empty state, and retain My bookings independent of that filter. Existing booking eligibility, review/confirmation, capacity and cancellation rules SHALL remain authoritative.

#### Scenario: Filter excludes a booked activity
- **WHEN** a member with a booked Yoga session selects Dance
- **THEN** Dance timetable rows are shown and the Yoga commitment remains in My bookings

### Requirement: NAVC-012 theme and legibility
WHEN screens render missing images, long names, mixed activities or large text, the system SHALL preserve meaningful labels and accessible actions using existing Chalkline tokens. Prominent visit metrics and prices SHALL use the existing primary color. Freeze date copy and keyboard access SHALL improve without changing its command payload or hook.

#### Scenario: Large text and long product name
- **WHEN** a product has a long name at large text size
- **THEN** its name and purchase/reservation actions remain legible and reachable without introducing a new palette
