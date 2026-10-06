## Purpose

Allow an owner to control member Classes discovery independently of business type and preserve a member's own booked commitments when catalogue browsing eligibility changes.

## ADDED Requirements

### Requirement: NAVC-001 reuse the mixed-activity class model
WHEN a tenant configures several activities, the system SHALL retain existing service/rule/session behavior for gyms, dance, yoga, martial arts and studios without a new activity enum or changes to membership eligibility, frozen-membership eligibility, booking serialization or attendance semantics.

#### Scenario: Separate weekdays
- **WHEN** one tenant offers Yoga on Monday and Dance on Tuesday
- **THEN** the existing timetable supplies separate named occurrences with their branch, time, instructor, capacity and booking state

### Requirement: NAVC-004 authorized tenant visibility command and read
WHEN an active canonical owner or manager changes saved Classes visibility, the system SHALL save the boolean with one audit per change and none for same-value retries. It SHALL enforce actor, audience, tenant and direct-write guards, expose only caller-tenant visibility to members without a tenant argument, fail on missing settings, and preserve existing staff/platform settings reads and commands.

#### Scenario: Authorized save and no-op retry
- **WHEN** a canonical owner sets visibility On and repeats the same command
- **THEN** the first call returns enabled On and changed true, the second returns enabled On and changed false, and exactly one change audit exists

#### Scenario: Wrong or revoked identity
- **WHEN** a front-desk, trainer, platform, impersonated, mismatched, revoked or foreign-tenant actor, or a wrong-audience caller, tries to change the setting
- **THEN** the command fails without changing settings or producing a successful change audit

#### Scenario: Direct write and member read isolation
- **WHEN** an authenticated owner attempts a direct field update or a member supplies another tenant identity
- **THEN** the direct update is refused and the caller-bound member read cannot reveal another tenant's setting

#### Scenario: Missing settings and compatibility
- **WHEN** the caller's settings row is missing or an existing staff/platform settings read or another settings command runs
- **THEN** missing settings fail rather than return Off, while existing settings reads and commands retain their behavior

### Requirement: NAVC-005 discovery-only switch
WHEN visibility is switched Off, the system SHALL preserve services, rules, sessions, bookings, messages and ordinary cancellation rights. The switch SHALL not alter class generation or new-booking authorization; existing service activation remains the scheduling and booking control.

#### Scenario: Hide with pending booking
- **WHEN** an owner switches Off while a scheduled session has a booked member
- **THEN** the session and booking retain their state and authorized cancellation continues normally

### Requirement: NAVC-013 own commitments survive branch changes
WHEN a caller has a class booking whose session ends after the captured server clock and starts before that clock plus 28 days, the system SHALL return current session/booking states and authoritative cancellation deadline/permission regardless of home-branch, cross-branch or service filters. It SHALL include caller-owned cancelled states, order by absolute start then session identity, expose no other member's booking or identity, and grant no new booking eligibility.

#### Scenario: Member changes home branch
- **WHEN** a member's upcoming booked class is no longer in the browsable branch catalogue
- **THEN** the own-bookings read retains it with current cancellation facts and no other member's booking

### Requirement: NAVC-014 absolute commitment horizon
WHEN branch-local dates differ from the home branch date, the own-bookings read SHALL include upcoming and in-progress commitments by absolute start/end time and the UI SHALL display each in its own branch timezone. Ended sessions and sessions starting at or after the upper horizon SHALL be excluded.

#### Scenario: Western branch date is yesterday
- **WHEN** an upcoming booked class has yesterday's local date relative to the home branch
- **THEN** it remains visible because its absolute end is in the future and its start is within the server horizon

### Requirement: NAVC-015 compatibility defaults
WHEN the additive setting is introduced, the system SHALL default new tenants Off and backfill existing tenants On when they have an active service or a booked, scheduled session ending after one captured migration clock. An in-progress booked session SHALL qualify; only ended sessions, cancelled bookings or cancelled sessions SHALL not qualify. The backfill SHALL run once, not override later owner choices.

#### Scenario: Booked in-progress class without active catalogue
- **WHEN** a tenant has an inactive service but a booked scheduled session currently in progress
- **THEN** the compatibility backfill enables Classes without changing that service or booking
