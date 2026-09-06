## Purpose

Everything the gym sends and everything the member consented to receive: per-gym message templates, the notification record whose de-duplication key makes "one message per stage" structural, versioned append-only consent, the registered devices push is delivered to, and the per-gym messaging credit wallet with its ledger.

## ADDED Requirements

### Requirement: One message per stage is structural, not a scheduling convention
PAY-002 SHALL rest on a uniqueness constraint: THE SYSTEM SHALL reject a second notification carrying a de-duplication key already used within that organisation, so a reminder job that runs twice cannot send twice.

#### Scenario: The same reminder stage scheduled twice
- **WHEN** a notification is written a second time with the same de-duplication key for the same organisation
- **THEN** the second write SHALL be rejected

#### Scenario: The same key at another gym
- **WHEN** the same de-duplication key is written for a different organisation
- **THEN** the write SHALL succeed

#### Scenario: Ad-hoc messages with no key
- **WHEN** two notifications are written with no de-duplication key
- **THEN** both writes SHALL succeed

### Requirement: Consent is versioned, append-only, and split by purpose
DPD-002, DPD-003, DPD-004 and INT-002 SHALL hold structurally: THE SYSTEM SHALL record each consent decision as a new row carrying a purpose, a version, a source and a timestamp, and SHALL give a signed-in caller no privilege to update or delete one. Marketing consent and service consent SHALL be independent purposes.

#### Scenario: Withdrawing consent
- **WHEN** a consent row is written for the same member and purpose with consent withheld
- **THEN** the write SHALL succeed and the earlier row SHALL still exist

#### Scenario: Editing a consent record
- **WHEN** a caller with the `authenticated` role updates a consent row in their own tenant
- **THEN** the update SHALL be refused for want of privilege

#### Scenario: Deleting a consent record
- **WHEN** a caller with the `authenticated` role deletes a consent row in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

#### Scenario: Withdrawing one purpose leaves the other
- **WHEN** marketing consent is withdrawn for a member who has also granted service consent
- **THEN** the service consent row SHALL be unchanged

#### Scenario: Consent with no version
- **WHEN** a consent row is written with an empty version
- **THEN** the write SHALL be rejected

### Requirement: A template is unique per gym, key, channel and locale
THE SYSTEM SHALL hold message copy per organisation, keyed by template key, channel and locale, and SHALL reject a duplicate of that combination so a send can never be ambiguous about which copy to use.

#### Scenario: A duplicate template
- **WHEN** a second template is written with the same key, channel and locale at the same organisation
- **THEN** the write SHALL be rejected

#### Scenario: The same key in another locale
- **WHEN** a template is written with the same key and channel in a different locale
- **THEN** the write SHALL succeed

#### Scenario: A malformed locale
- **WHEN** a template is written with a locale of `en-IN`
- **THEN** the write SHALL be rejected

### Requirement: A push notification has somewhere to go
THE SYSTEM SHALL store the devices a member has registered for push (ADR-016's v1 primary channel), one row per push token, so a scheduled notification has a delivery target.

#### Scenario: The same push token registered twice
- **WHEN** a second device row is written with an existing push token
- **THEN** the write SHALL be rejected

#### Scenario: A member with several devices
- **WHEN** a second device row is written for the same member with a different push token
- **THEN** the write SHALL succeed

### Requirement: The messaging wallet balance can never go negative and its ledger is append-only
ADR-016's per-gym credit wallet SHALL exist from day one: THE SYSTEM SHALL reject a balance below zero, SHALL record every movement as a ledger row carrying a non-zero delta and a non-empty reason, and SHALL give a signed-in caller no privilege to update or delete a ledger row.

#### Scenario: A balance driven below zero
- **WHEN** a wallet balance is updated to a negative number
- **THEN** the write SHALL be rejected

#### Scenario: A ledger entry that moves nothing
- **WHEN** a ledger row is written with a delta of zero
- **THEN** the write SHALL be rejected

#### Scenario: Editing the ledger
- **WHEN** a caller with the `authenticated` role updates a ledger row in their own tenant
- **THEN** the update SHALL be refused for want of privilege

#### Scenario: One wallet per gym
- **WHEN** a second wallet row is written for the same organisation
- **THEN** the write SHALL be rejected

### Requirement: Notification status and channel come from the closed vocabularies
THE SYSTEM SHALL constrain a notification's status and channel to their enums, so delivery reporting cannot invent a state.

#### Scenario: A status outside the vocabulary
- **WHEN** a notification is written with a status of `bounced`
- **THEN** the write SHALL be rejected

#### Scenario: A channel outside the vocabulary
- **WHEN** a notification is written with a channel of `telegram`
- **THEN** the write SHALL be rejected
