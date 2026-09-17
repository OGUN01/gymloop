## Purpose

Everything the gym sends and everything the member consented to receive: per-gym message templates, the notification record whose de-duplication key makes "one message per stage" structural, versioned append-only consent, the registered devices push is delivered to, and the per-gym messaging credit wallet with its ledger.

## Requirements

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
THE SYSTEM SHALL store the devices a member has registered for push (ADR-016's v1 primary channel), one row per push token **per organisation** (ADR-047), so a scheduled notification has a delivery target and a member who belongs to two gyms can still be reached by both.

#### Scenario: The same push token registered twice at the same gym
- **WHEN** a second device row is written for the same organisation with an existing push token
- **THEN** the write SHALL be rejected

#### Scenario: The same push token registered at a second gym
- **WHEN** the same push token is written for a different organisation
- **THEN** the write SHALL succeed

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

### Requirement: Consent decisions are claim-derived and serialized
COM-007 and DPD-002–004 SHALL be implemented by `public.record_consent`: THE
SYSTEM SHALL derive the gym, member or acting staff identity from verified
claims, lock one member/purpose decision stream, persist the caller's request
key, and return the existing row on an exact replay. A staff caller may record
consent only for a same-gym member; a member may record only their own decision.
The current decision is the newest server timestamp with the row id as the
total-order tie-breaker. Direct inserts SHALL obey the same stamps and source
rules, and consent rows remain append-only.

#### Scenario: Two consent decisions race
- **WHEN** grant and withdrawal requests for one member and purpose overlap
- **THEN** they SHALL serialize and the newest committed row SHALL be the current decision

#### Scenario: A request key is replayed with different facts
- **WHEN** the same caller reuses a consent request key with different decision facts
- **THEN** the command SHALL fail explicitly rather than return the earlier row

### Requirement: Notification lifecycle and evidence are structural
COM-001–007, INT-002/003 and PAY-002 SHALL be enforced for every writer. A
notification SHALL carry a category, claim-compatible source and member, and
an allowed status/evidence combination. Scheduled may advance to sent,
delivered, failed or opted_out; sent may advance to delivered or failed; every
other state is terminal. Identity, content, consent evidence, request identity,
wallet identity and provider evidence SHALL be immutable after insert. A
consent-required notification SHALL persist the exact current granted decision;
marketing never inherits service consent. In-app notifications require no paid
wallet movement; a paid adapter may accept a message only through the private
wallet command whose debit and notification acceptance are one transaction.

#### Scenario: Delivery evidence is invented
- **WHEN** a writer marks a notification delivered without the required delivery timestamp
- **THEN** the write SHALL be rejected

#### Scenario: A terminal notification is changed
- **WHEN** a delivered, failed or opted-out notification is transitioned again or its immutable facts are edited
- **THEN** the write SHALL be rejected

#### Scenario: A member acknowledges an in-app notification
- **WHEN** its owner replays `public.acknowledge_notification` for the same sent or delivered in-app row
- **THEN** the command SHALL return the same delivered result and SHALL NOT create paid-delivery evidence

### Requirement: Renewal reminders use the money path's one remainder formula
COM-004/005 and PAY-001 SHALL use `app.membership_renewal_remainder` for both
reminder scheduling and metrics. The remainder is the Phase 5 net period price
less arrived receipt money after whole periods granted, expressed as canonical
decimal strings. Daily stages use the gym-local date, the configured positive
windows and a tenant/date/stage de-duplication key. Replays and overlapping
schedulers SHALL produce at most one notification for a stage. Zero-net
renewals remain visible to reads but SHALL NOT schedule a reminder.

#### Scenario: The daily scheduler is replayed
- **WHEN** the same tenant and gym-local date are run more than once, including concurrently
- **THEN** each eligible membership/window stage SHALL have at most one notification

### Requirement: Wallet adjustments are exact, replay-safe money movements
PAY-003 SHALL be implemented by `public.adjust_messaging_wallet`: only an
authorized platform actor may adjust a gym wallet, amounts are non-zero signed
integer paise with explicit currency, the wallet row is locked before its
ledger stream, and a movement is accepted only when its stored resulting
balance equals the wallet balance in the same transaction. Caller/request key
replay returns the original movement; mismatched replay, currency mismatch and
negative result fail explicitly. The ledger remains append-only.

#### Scenario: Two debits compete for the final balance
- **WHEN** concurrent commands would together make the wallet negative
- **THEN** at most the affordable debit SHALL commit and every accepted ledger balance SHALL reconcile

### Requirement: Staff and member messaging screens expose only honest state
THE SYSTEM SHALL provide `/messages` for authorized gym staff and
`/member/messages` for the signed-in member. The staff snapshot SHALL expose
counts, rows, current consent actions and role-gated template/wallet controls
from one validated response. The member view SHALL expose only that member's
in-app messages and consent history; it SHALL NOT fabricate provider delivery,
wallet balance or another member's rows. Generated database enum values are the
only accepted template category vocabulary at the HTTP and form boundaries.

#### Scenario: A member opens the staff workspace
- **WHEN** a member session requests `/messages`
- **THEN** the product SHALL redirect to the member home rather than render staff data
