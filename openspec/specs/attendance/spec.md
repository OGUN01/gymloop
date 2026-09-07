## Purpose

The record of who came to the gym and when: session-bound QR codes, one row per visit with optional check-out, the assisted front-desk fallback and its mandatory reason, the offline-replay stamp that makes a queued check-in exactly-once, append-only corrections, and the gym's holiday calendar.

## Requirements

### Requirement: A QR session expires and only its hash is stored
ATT-003 SHALL hold structurally: THE SYSTEM SHALL store only a hash of a check-in QR token, never the token, and SHALL require every QR session to carry an expiry later than its issue time.

#### Scenario: A session that expires before it is issued
- **WHEN** a QR session is written whose expiry is not after its issue time
- **THEN** the write SHALL be rejected

#### Scenario: A reused token hash
- **WHEN** a second QR session is written with an existing token hash
- **THEN** the write SHALL be rejected

### Requirement: An assisted check-in names the staff member and the reason
ATT-005 and ATT-006 SHALL hold structurally: a check-in whose source is the front desk SHALL carry both the acting staff member and a non-empty reason. Neither SHALL be recorded without the other.

#### Scenario: A front-desk check-in with no reason
- **WHEN** an attendance row with source `front_desk` is written with no reason
- **THEN** the write SHALL be rejected

#### Scenario: A front-desk check-in with an empty reason
- **WHEN** an attendance row with source `front_desk` is written with an empty-string reason
- **THEN** the write SHALL be rejected

#### Scenario: A front-desk check-in with no acting staff member
- **WHEN** an attendance row with source `front_desk` is written with a reason but no staff member
- **THEN** the write SHALL be rejected

#### Scenario: A QR check-in needs neither
- **WHEN** an attendance row with source `qr` is written with no staff member and no reason
- **THEN** the write SHALL succeed

### Requirement: A queued offline check-in replays exactly once
ATT-007 SHALL hold structurally: THE SYSTEM SHALL reject a second attendance row carrying a device-generated event id already recorded for that organisation, so replaying a queue cannot duplicate a visit.

#### Scenario: The same queued check-in replayed twice
- **WHEN** an attendance row is written a second time with the same device event id for the same organisation
- **THEN** the second write SHALL be rejected

#### Scenario: Two live check-ins with no device event id
- **WHEN** two attendance rows are written with no device event id
- **THEN** both writes SHALL succeed

### Requirement: An offline replay records both timestamps or neither
ATT-007's audit stamp SHALL be complete: a replayed row SHALL carry both the original offline timestamp and the time it was replayed.

#### Scenario: A replay time with no offline time
- **WHEN** an attendance row is written with a replay time but no offline timestamp
- **THEN** the write SHALL be rejected

#### Scenario: An offline time with no replay time
- **WHEN** an attendance row is written with an offline timestamp but no replay time
- **THEN** the write SHALL be rejected

### Requirement: Check-out is optional and never precedes check-in
ATT-008 SHALL hold: a visit with no check-out SHALL be valid. A check-out earlier than its check-in SHALL NOT be.

#### Scenario: A visit with no check-out
- **WHEN** an attendance row is written with no check-out time
- **THEN** the write SHALL succeed

#### Scenario: A check-out before the check-in
- **WHEN** an attendance row is written whose check-out precedes its check-in
- **THEN** the write SHALL be rejected

### Requirement: A visit is corrected, never removed
INT-001 and DQA-003 SHALL hold structurally: a signed-in caller SHALL have no privilege to delete an attendance row, and every correction SHALL be an append-only row carrying a non-empty reason and the acting staff member.

#### Scenario: Deleting a visit
- **WHEN** a caller with the `authenticated` role deletes an attendance row in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

#### Scenario: A correction with no reason
- **WHEN** an attendance correction is written with an empty reason
- **THEN** the write SHALL be rejected

#### Scenario: Editing a correction
- **WHEN** a caller with the `authenticated` role updates an existing attendance correction
- **THEN** the update SHALL be refused for want of privilege

### Requirement: The gym's holiday calendar has one entry per date
THE SYSTEM SHALL hold a holiday calendar per organisation, with at most one entry per date, so a holiday can be excluded from streak-break evaluation (STK-002) without ambiguity.

#### Scenario: The same holiday twice
- **WHEN** a second holiday is written for the same organisation and date
- **THEN** the write SHALL be rejected

### Requirement: A visit is scoped to a branch and a member of the same gym
THE SYSTEM SHALL require every attendance row to reference a branch and a member, and SHALL reject a row whose referenced rows do not exist.

#### Scenario: A visit by a member who does not exist
- **WHEN** an attendance row is written referencing a member id that does not exist
- **THEN** the write SHALL be rejected
