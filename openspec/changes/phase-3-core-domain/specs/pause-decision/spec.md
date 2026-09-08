## Purpose

Who may approve a member's freeze, and on whose authority. A pause suspends what a gym is owed, so approving one is a commercial decision — and the rule governing it was, until the Phase 3 critic, enforced only in a TypeScript comparison that a direct `supabase-js` write went straight round.

This spec exists because the rule had no spec. The role matrix says who may *write* `membership_pauses`; it does not say who may *approve* one, and those are different questions.

## Requirements

### Requirement: The gym decides which role approves a freeze
THE SYSTEM SHALL permit an approval only by a staff member whose role equals the gym's configured `organization_settings.pause_approver_role`, and SHALL enforce this where every writer meets it rather than in a caller.

#### Scenario: The configured role approves
- **WHEN** a staff member whose role is the gym's configured approver role approves a pending pause
- **THEN** the approval SHALL succeed

#### Scenario: Another staff role approves
- **WHEN** a staff member of the gym holding any other role approves a pending pause
- **THEN** the approval SHALL be rejected

#### Scenario: The rule cannot be gone around
- **WHEN** a front-desk session writes the approval columns directly rather than through the endpoint
- **THEN** it SHALL be rejected on the same terms — a rule enforced by a caller is a rule with a way round it

### Requirement: The approver is whoever is acting, and cannot be someone else
THE SYSTEM SHALL require the recorded approver to be the acting staff member, so an approval cannot be attributed to a colleague.

#### Scenario: Attributing an approval to another staff member
- **WHEN** a staff member approves a pause recording a different staff member as the approver
- **THEN** the write SHALL be rejected

### Requirement: The person who asked is not the person who grants
THE SYSTEM SHALL reject an approval by the staff member who requested the pause, whatever their role. A freeze is money the gym does not collect, and a single person deciding it alone is the shape every expense-approval control exists to prevent.

#### Scenario: Approving one's own request
- **WHEN** the staff member who requested a pause approves it
- **THEN** the write SHALL be rejected

#### Scenario: A different staff member of the right role approves it
- **WHEN** a different staff member holding the configured role approves that same pause
- **THEN** the approval SHALL succeed

### Requirement: Rejecting a pause is not the decision approving one is
THE SYSTEM SHALL govern only the transition **into** approved. A rejection needs no configured role and no second person: refusing a freeze costs the gym nothing and denying it is not the commercial act granting it is.

#### Scenario: Any staff member may reject
- **WHEN** a staff member who may write pauses rejects a pending pause
- **THEN** the rejection SHALL succeed regardless of their role

#### Scenario: The requester may reject their own request
- **WHEN** the staff member who requested a pause rejects it
- **THEN** the rejection SHALL succeed

### Requirement: A decided pause stays decided
THE SYSTEM SHALL apply the approval rules only to a pause that has not already been decided, so a second approver cannot overwrite the first.

#### Scenario: Approving an already-approved pause
- **WHEN** a staff member approves a pause that has already been approved
- **THEN** nothing SHALL change and the original approver SHALL still be recorded
