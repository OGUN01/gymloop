## Purpose

The silent-churn half of the product loop: a no-show case opened when a member's absence crosses their gym's threshold, at most one live case per member, and the append-only contact log that records who was called, what they said, and what happens next.

## ADDED Requirements

### Requirement: A member has at most one live no-show case
NSH-003 and NSH-004 SHALL hold structurally rather than by scan logic: THE SYSTEM SHALL reject a second no-show case for a member while one is already `open`, `contacted` or `follow_up_due`, so a repeated scan run cannot open a duplicate.

#### Scenario: A second case while one is open
- **WHEN** a second no-show case is written for a member whose existing case is `open`
- **THEN** the write SHALL be rejected

#### Scenario: A second case while one is being contacted
- **WHEN** a second no-show case is written for a member whose existing case is `contacted`
- **THEN** the write SHALL be rejected

#### Scenario: A new case after the last one closed
- **WHEN** a no-show case is written for a member whose previous case is `closed`
- **THEN** the write SHALL succeed

### Requirement: A case records the threshold it was opened against
THE SYSTEM SHALL store, on each case, the number of absent days at the moment it opened and the gym's configured threshold at that moment, so a later change to the setting does not rewrite the history of why a case exists.

#### Scenario: A case opened against no threshold
- **WHEN** a no-show case is written with a threshold of zero
- **THEN** the write SHALL be rejected

#### Scenario: A case opened with a negative absence
- **WHEN** a no-show case is written with a negative absent-day count
- **THEN** the write SHALL be rejected

### Requirement: The contact log is append-only
NSH-007 SHALL hold structurally: a signed-in caller SHALL have no privilege to update or delete a follow-up row. A correction SHALL be a new row referencing the one it corrects.

#### Scenario: Editing a logged contact
- **WHEN** a caller with the `authenticated` role updates a follow-up row in their own tenant
- **THEN** the update SHALL be refused for want of privilege

#### Scenario: Deleting a logged contact
- **WHEN** a caller with the `authenticated` role deletes a follow-up row in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

#### Scenario: Correcting a logged contact
- **WHEN** a new follow-up row is written referencing the row it corrects
- **THEN** the write SHALL succeed and both rows SHALL exist

### Requirement: A case that closes keeps its contact history
NSH-005 SHALL hold structurally: a signed-in caller SHALL have no privilege to delete a no-show case, so resolving a case preserves the follow-ups attached to it.

#### Scenario: Deleting a resolved case
- **WHEN** a caller with the `authenticated` role deletes a `closed` no-show case in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

### Requirement: A follow-up records a channel and an outcome from the closed vocabularies
THE SYSTEM SHALL constrain the contact channel and the follow-up outcome to their enums, so an outcome cannot be free text that later analysis has to guess at.

#### Scenario: An outcome outside the vocabulary
- **WHEN** a follow-up is written with an outcome of `busy`
- **THEN** the write SHALL be rejected

#### Scenario: A channel outside the vocabulary
- **WHEN** a follow-up is written with a channel of `telegram`
- **THEN** the write SHALL be rejected

### Requirement: A follow-up belongs to a case and a staff member
THE SYSTEM SHALL require every follow-up to reference an existing case and the staff member who made the contact, so a contact with no attributable author cannot be recorded.

#### Scenario: A follow-up on a case that does not exist
- **WHEN** a follow-up is written referencing a case id that does not exist
- **THEN** the write SHALL be rejected
