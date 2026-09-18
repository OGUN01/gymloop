## Purpose

The platform's own surface above the gyms: super-admin and support accounts, impersonation sessions with their mandatory reason and hard expiry, the append-only audit log, plus the two gym-side intake tables that belong to nobody else — leads and CSV member imports.

## Requirements

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

### Requirement: Gym onboarding is one atomic platform command
WHEN a verified super admin onboards a gym THE SYSTEM SHALL atomically create
the organization, exactly one settings row, exactly one same-gym default branch,
one zero-credit messaging wallet and one active unlinked owner profile. The gym
SHALL start in trial with a unique six-character code and a gym-local fourteen-day
trial boundary. Failure of any child write SHALL leave none of these rows.

#### Scenario: A child write fails during onboarding
- **WHEN** any required settings, branch, wallet, owner or audit write fails
- **THEN** the organization and every sibling write SHALL be rolled back

#### Scenario: A preset is selected
- **WHEN** onboarding chooses a registered preset
- **THEN** its registered settings SHALL be copied once and later preset changes SHALL NOT overwrite the gym

### Requirement: Activation is manual and readiness-gated
WHEN a super admin changes a gym to active THE SYSTEM SHALL use one coherent
readiness snapshot and require valid settings, exactly one default branch, an
active owner linked to a non-platform Auth user, a recognized timezone and INR.
Provider credentials, logo, address and GSTIN SHALL NOT be invented as blockers.

#### Scenario: Required readiness is incomplete
- **WHEN** activation is requested while any required readiness fact is missing
- **THEN** the command SHALL refuse atomically with the ordered missing settings

#### Scenario: First activation succeeds
- **WHEN** a ready gym first enters active
- **THEN** its activation timestamp SHALL be server-stamped and preserved through later suspension/reactivation

### Requirement: Commercial state changes use the canonical graph and CAS
ONLY a live non-preview super admin SHALL change status, tier, trial or activation
facts. Status changes SHALL follow the canonical graph, require reasons for
suspension, closure and reactivation, compare the expected state, and append one
keyed audit event. Direct authenticated commercial writes SHALL be refused.

#### Scenario: A stale status command arrives
- **WHEN** the supplied expected status no longer matches the locked organization
- **THEN** the command SHALL refuse without changing or auditing the gym

#### Scenario: An inert retry arrives
- **WHEN** an accepted request key is replayed with identical actor and facts
- **THEN** the original result SHALL be returned without a second effect or audit event

### Requirement: Tier is a manual label, not billing
WHEN a super admin assigns a tier THE SYSTEM SHALL accept only `basic`, `growth`
or `pro`, display the registered integer-paise monthly price and audit a real
change. Tier SHALL NOT activate a gym, charge money or impose an unapproved cap.

#### Scenario: A tier is changed
- **WHEN** the expected tier matches and the new canonical tier differs
- **THEN** only the tier SHALL change and the keyed result SHALL be replayable

### Requirement: Owner linking proves one exact Auth account
WHEN a super admin links an active same-gym owner profile THE SYSTEM SHALL resolve
one normalized exact Auth email, reject absent/ambiguous/platform/already-bound
accounts, preserve protected metadata, set the preferred tenant, revoke affected
refresh sessions and write one keyed audit event. No invitation SHALL be implied.

#### Scenario: The email belongs to a platform identity
- **WHEN** owner linking resolves an active or inactive platform account
- **THEN** linking SHALL be refused without disclosing the Auth roster

#### Scenario: The exact owner is already linked
- **WHEN** the expected user and exact normalized account already match
- **THEN** the command SHALL be inert and SHALL NOT rewrite metadata or sessions

### Requirement: Ineligible gyms receive no fresh ordinary claims
WHEN the access-token hook sees a pending, suspended, closed, expired-trial or
malformed-trial gym THE SYSTEM SHALL issue no fresh staff/member gym claims.
Suspension or closure SHALL revoke sessions for that gym's linked staff/members;
an explicit live super-admin preview remains the only exception.

#### Scenario: A suspended gym refreshes a staff token
- **WHEN** the hook resolves only an identity in that suspended gym
- **THEN** it SHALL remove stale Gymloop claim keys and issue no gym identity

### Requirement: A support preview is explicit, bounded and read-only
WHEN a super admin starts a gym preview THE SYSTEM SHALL require a nonblank reason,
bind actor and gym, use the database-derived two-hour expiry, refresh to the real
preview claim and display a persistent red banner. While previewing, every product
mutation SHALL be refused except ending that caller's own exact session.
Platform support SHALL see fleet/detail facts with no mutation controls and SHALL
have no ability to start a preview.

#### Scenario: A super admin ends the live preview
- **WHEN** the banner's end action is used by the bound actor
- **THEN** the exact session SHALL end, Auth SHALL refresh and the user SHALL return to platform

#### Scenario: A preview requests owner metrics
- **WHEN** a preview identity opens the owner metrics route
- **THEN** it SHALL be redirected before the owner metrics RPC is invoked

### Requirement: Only super admin controls platform commercial state
WHEN platform support or any gym-side role calls onboarding, status, tier,
owner-link or preview-start commands THE SYSTEM SHALL refuse before target,
request-key or Auth-roster lookup. Support SHALL retain the complete read surface.

#### Scenario: Platform support opens the fleet and detail
- **WHEN** an active support account opens those routes
- **THEN** the same fleet/readiness facts SHALL render with no mutation forms
