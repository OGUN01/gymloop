## Purpose

Recording that a member turned up. The product's core loop starts here — no attendance, no churn signal, no retention. Two ways in: a member scans the gym's QR code, or the front desk checks someone in for them.

The bar is a metro gate: scan to confirmation is the design, not a detail. But the requirement that actually costs something is **exactly-once** — a duplicate attendance row is silent, it corrupts a streak and a churn scan quietly, and nobody notices for weeks. That is why this capability gets the full blind treatment (ADR-059).

Phase 1's schema already enforces some of this and those rules are not restated below: `attendance_front_desk_has_assist_chk` makes a front-desk row impossible without a staff member and a non-empty reason (ATT-005, ATT-006); `attendance_tenant_id_client_event_id_key` makes a client event id unique per tenant; `attendance_assisted_pair_chk` and `attendance_offline_stamp_pair_chk` keep their column pairs honest.

## Requirements

### Requirement: A check-in is recorded only against a valid QR session and a live membership
WHEN a member presents a QR code, THE SYSTEM SHALL verify that the QR session exists, belongs to this gym, has not expired and has not been revoked, and that the member holds a membership in `active` or `frozen` status, **before** recording attendance (ATT-001).

#### Scenario: A valid scan
- **WHEN** a member with an active membership scans a live QR session for their gym
- **THEN** exactly one attendance row SHALL be recorded, with source `qr` and the scanned session's id

#### Scenario: An expired QR session
- **WHEN** the QR session's expiry has passed
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded (ATT-002)

#### Scenario: A revoked QR session
- **WHEN** the QR session has been revoked
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: A QR session belonging to another gym
- **WHEN** a member scans a QR session issued by a different gym
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: A member whose membership has lapsed
- **WHEN** a member whose only membership is `expired` or `cancelled` scans a live session
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

### Requirement: The QR token is never stored, only its hash
THE SYSTEM SHALL store a QR session's token as a hash and SHALL NOT store the token itself, so that a reader of the database cannot mint a scan (ATT-003). A session SHALL carry an expiry, so a screenshot of a previously valid code stops working.

#### Scenario: The token is not recoverable from the row
- **WHEN** a `qr_sessions` row is inspected
- **THEN** it SHALL hold a hash and no column SHALL contain the token in a form that could be presented

### Requirement: A repeated scan inside the gym's window changes nothing
IF a member is scanned again within the gym's configured de-duplication window, THEN THE SYSTEM SHALL reject the duplicate and SHALL leave the original attendance row intact (ATT-004). The window is `organization_settings.checkin_dedupe_seconds` and is read per gym, never hardcoded.

#### Scenario: A second scan inside the window
- **WHEN** a member who checked in thirty seconds ago scans again, and the gym's window is longer than that
- **THEN** no second attendance row SHALL be recorded and the first SHALL be unchanged

#### Scenario: A second scan after the window
- **WHEN** a member scans again after the gym's window has elapsed
- **THEN** a second attendance row SHALL be recorded

#### Scenario: The window is the gym's own
- **WHEN** two gyms configure different windows
- **THEN** each gym's de-duplication SHALL use its own value

### Requirement: Two simultaneous scans produce exactly one attendance row
WHILE two check-ins for the same member arrive concurrently, THE SYSTEM SHALL record exactly one attendance row. A de-duplication implemented as a read followed by a write is not sufficient: both reads can pass before either writes, and the resulting duplicate is silent.

#### Scenario: Concurrent scans of the same member
- **WHEN** two check-ins for the same member are submitted at the same instant
- **THEN** exactly one attendance row SHALL exist for that member in that window afterwards

#### Scenario: The same client event submitted twice
- **WHEN** the same check-in is submitted twice carrying the same client event id
- **THEN** exactly one attendance row SHALL exist, and the second submission SHALL NOT be reported as an error to the caller

### Requirement: An assisted check-in names the staff member and the reason
WHEN staff record a check-in on a member's behalf, THE SYSTEM SHALL require the acting staff member and a non-empty reason, and SHALL record the source as `front_desk` (ATT-005, ATT-006).

#### Scenario: Assisted check-in with a reason
- **WHEN** front desk checks a member in with a stated reason
- **THEN** an attendance row SHALL be recorded with source `front_desk`, the acting staff member, and that reason

#### Scenario: Assisted check-in with no reason
- **WHEN** front desk submits an assisted check-in with an empty reason
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: Assisted check-in with a reason of whitespace
- **WHEN** front desk submits an assisted check-in whose reason is only spaces
- **THEN** the check-in SHALL be rejected — **Phase 1's constraint tests `assist_reason <> ''`, which accepts three spaces**, and a blank line is not a reason for having marked somebody else present. Verified against the live database before this scenario was written: the row inserts today.

#### Scenario: A trainer attempting an assisted check-in
- **WHEN** a caller whose role is `trainer` submits an assisted check-in
- **THEN** it SHALL be rejected — the matrix gives `attendance` a write gate of front office and above

### Requirement: A check-in never crosses a tenant
THE SYSTEM SHALL record attendance only for a member of the acting session's own gym, and SHALL NOT rely on the caller supplying the correct tenant.

#### Scenario: Checking in another gym's member
- **WHEN** a check-in names a member id belonging to a different gym
- **THEN** it SHALL be rejected and no attendance row SHALL be recorded

### Requirement: Check-out is optional and blocks nothing
THE SYSTEM SHALL treat a missing check-out as normal, and no other behaviour SHALL depend on one being present (ATT-008).

#### Scenario: Attendance with no check-out
- **WHEN** an attendance row has no check-out time
- **THEN** it SHALL still count as a visit
