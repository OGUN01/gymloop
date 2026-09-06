## Purpose

The platform's own surface above the gyms: super-admin and support accounts, impersonation sessions with their mandatory reason and hard expiry, the append-only audit log, plus the two gym-side intake tables that belong to nobody else — leads and CSV member imports.

## ADDED Requirements

### Requirement: Platform accounts are visible only to the platform
ADR-033's first exemption: `platform_users` SHALL carry no tenant column and SHALL be reachable only by the `super_admin` and `platform_support` policy branch. No gym-side role SHALL read it.

#### Scenario: A gym owner reading the platform roster
- **WHEN** a caller whose role claim is `gym_owner` selects from the platform users table
- **THEN** zero rows SHALL be returned

#### Scenario: A platform role reading the platform roster
- **WHEN** a caller whose role claim is `super_admin` selects from the platform users table
- **THEN** the rows SHALL be returned

#### Scenario: A platform user with a gym-side role
- **WHEN** a platform user row is written with role `gym_owner`
- **THEN** the write SHALL be rejected

### Requirement: An impersonation session always has a reason and an expiry
THE SYSTEM SHALL reject an impersonation session with an empty reason or with an expiry that is not after its start, so an indefinite or unexplained session cannot exist (`docs/security.md`, Impersonation).

#### Scenario: A session with no stated reason
- **WHEN** an impersonation session is written with an empty reason
- **THEN** the write SHALL be rejected

#### Scenario: A session that never expires
- **WHEN** an impersonation session is written whose expiry is not after its start
- **THEN** the write SHALL be rejected

### Requirement: A gym can see who impersonated it, and change nothing about it
THE SYSTEM SHALL let a gym read the impersonation sessions targeting it, and SHALL NOT let a gym-side caller create, alter or delete one.

#### Scenario: A gym reading its own impersonation history
- **WHEN** a caller whose tenant claim is gym A selects impersonation sessions for gym A
- **THEN** the rows SHALL be returned

#### Scenario: A gym reading another gym's impersonation history
- **WHEN** a caller whose tenant claim is gym A selects impersonation sessions for gym B
- **THEN** zero rows SHALL be returned

#### Scenario: A gym inventing an impersonation session
- **WHEN** a caller whose tenant claim is gym A inserts an impersonation session for gym A
- **THEN** the write SHALL be rejected

### Requirement: The audit log is append-only and carries actor, action, record and time
INT-003's storage SHALL exist in Phase 1: THE SYSTEM SHALL record actor, actor role, action, record type, record id, a before/after summary and a timestamp, SHALL constrain the action to `<record_type>.<verb>` form, and SHALL give a signed-in caller no privilege to update or delete a row.

#### Scenario: Editing an audit row
- **WHEN** a caller with the `authenticated` role updates an audit row in their own tenant
- **THEN** the update SHALL be refused for want of privilege

#### Scenario: Deleting an audit row
- **WHEN** a caller with the `authenticated` role deletes an audit row in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

#### Scenario: An audit row with no action
- **WHEN** an audit row is written with an empty action
- **THEN** the write SHALL be rejected

### Requirement: A platform-level audit row is invisible to every gym
ADR-033's second exemption: an audit row with no tenant SHALL be readable only by the platform policy branch.

#### Scenario: A gym reading a platform-level audit row
- **WHEN** a caller whose tenant claim is gym A selects audit rows with no tenant
- **THEN** zero rows SHALL be returned

#### Scenario: A platform role reading the same row
- **WHEN** a caller whose role claim is `super_admin` selects audit rows with no tenant
- **THEN** the row SHALL be returned

### Requirement: A converted lead names the member it became
THE SYSTEM SHALL reject a lead marked `converted` that does not reference the member it converted into, and SHALL constrain source and stage to their enums.

#### Scenario: A converted lead with no member
- **WHEN** a lead is written as `converted` with no converted member
- **THEN** the write SHALL be rejected

#### Scenario: A lead source outside the vocabulary
- **WHEN** a lead is written with a source of `billboard`
- **THEN** the write SHALL be rejected

#### Scenario: A lead phone number that is not E.164
- **WHEN** a lead is written with a phone number that is not in E.164 form
- **THEN** the write SHALL be rejected

### Requirement: An import run records its mapping and its duplicate report
THE SYSTEM SHALL record, per CSV/Excel import, the uploading staff member, the column mapping used, and non-negative counts of rows read, rows imported and duplicates found.

#### Scenario: A negative duplicate count
- **WHEN** an import run is written with a negative duplicate count
- **THEN** the write SHALL be rejected

#### Scenario: An import by nobody
- **WHEN** an import run is written with no uploading staff member
- **THEN** the write SHALL be rejected
