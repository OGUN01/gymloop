## Purpose

A super admin acting as a gym for support, under a session that has a stated reason, a hard expiry, exactly one live instance per actor, an audit trail the database writes rather than the caller, and a claim on every request that marks it as impersonated.

Phase 1 built the table and its constraints. This capability is the behaviour behind them.

## Requirements

### Requirement: Only a super admin may impersonate
THE SYSTEM SHALL set impersonation claims only for an identity that resolves as an active `super_admin`. A `platform_support` account SHALL NOT be able to impersonate, and SHALL NOT be able to create an impersonation session.

#### Scenario: A support account creating a session
- **WHEN** a caller whose role claim is `platform_support` inserts an `impersonation_sessions` row
- **THEN** the insert SHALL be rejected by the row-security policy

#### Scenario: A super admin creating a session
- **WHEN** a caller whose role claim is `super_admin` inserts an `impersonation_sessions` row with a reason and a future expiry
- **THEN** the insert SHALL succeed

### Requirement: An impersonating token acts as the gym, not as the platform
WHILE a live impersonation session exists for the acting super admin, THE SYSTEM SHALL issue a token carrying the session's target as `tenant_id`, `gym_owner` as `app_role`, and the session's id as `impersonation_session_id`, and carrying neither `staff_id` nor `member_id`. The token SHALL NOT satisfy the platform test — an impersonator has the gym's reach, not the gym's reach *and* the platform's.

#### Scenario: The claims of an impersonating token
- **WHEN** the hook is called for an active super admin with one live impersonation session targeting gym A
- **THEN** the returned claims SHALL carry `tenant_id` of gym A, `app_role` of `gym_owner`, and the session id as `impersonation_session_id`, and SHALL carry no `staff_id` and no `member_id`

#### Scenario: An impersonating session is not a platform session
- **WHEN** a caller carrying those claims selects from a table holding rows for gym A and gym B
- **THEN** only gym A's rows SHALL be returned

#### Scenario: An impersonating session cannot reach the platform roster
- **WHEN** a caller carrying those claims selects from `platform_users`
- **THEN** zero rows SHALL be returned

### Requirement: A session that has ended or expired sets no claims
THE SYSTEM SHALL treat a session as live only while it has not ended and its expiry is in the future, and SHALL issue an ordinary platform token once it is neither.

#### Scenario: An expired session
- **WHEN** the hook is called for an active super admin whose only impersonation session has an expiry in the past
- **THEN** the returned claims SHALL carry `app_role` of `super_admin`, and no `tenant_id` and no `impersonation_session_id`

#### Scenario: An ended session
- **WHEN** the hook is called for an active super admin whose only impersonation session has been ended
- **THEN** the returned claims SHALL carry `app_role` of `super_admin`, and no `tenant_id` and no `impersonation_session_id`

### Requirement: One live session per actor
THE SYSTEM SHALL reject a second live impersonation session for the same actor, so the tenant an impersonating token names is never ambiguous.

#### Scenario: A second live session
- **WHEN** an impersonation session is created for an actor who already has one that has not ended
- **THEN** the write SHALL be rejected

#### Scenario: A new session after the previous one ended
- **WHEN** an impersonation session is created for an actor whose previous session has been ended
- **THEN** the write SHALL succeed

### Requirement: The database writes the audit rows, not the caller
INT-003 requires an audit row when an impersonation session is created and when it is ended. THE SYSTEM SHALL write both from the database itself, so neither depends on a caller remembering — and because `audit_log` is not writable by a signed-in session in any case.

#### Scenario: Starting a session
- **WHEN** an impersonation session is created
- **THEN** an `audit_log` row SHALL exist naming the acting user, the target tenant, the stated reason, and the session as the record

#### Scenario: Ending a session
- **WHEN** an impersonation session's end time is set
- **THEN** a second `audit_log` row SHALL exist for that session recording the end

#### Scenario: The caller writes no audit row
- **WHEN** a caller whose role claim is `super_admin` inserts an `audit_log` row directly
- **THEN** the insert SHALL be refused for want of privilege

### Requirement: A gym sees who impersonated it, and only its owner and manager may look
THE SYSTEM SHALL let a gym read the impersonation sessions targeting it, restricted to the roles the matrix names, and SHALL let no gym-side role create, alter or delete one.

#### Scenario: An owner reading their gym's impersonation history
- **WHEN** a caller whose role claim is `gym_owner` and whose tenant claim is gym A selects impersonation sessions for gym A
- **THEN** the rows SHALL be returned

#### Scenario: Front desk reading impersonation history
- **WHEN** a caller whose role claim is `front_desk` in gym A selects impersonation sessions for gym A
- **THEN** zero rows SHALL be returned

#### Scenario: A gym inventing an impersonation session
- **WHEN** a caller whose role claim is `gym_owner` inserts an impersonation session for their own gym
- **THEN** the insert SHALL be rejected

### Requirement: An abandoned session leaves a start with no end, and that is visible
An expired session is not swept by any job, so its end audit row is written only if someone ends it. THE SYSTEM SHALL make the expiry readable on the session row itself, so a reader of the audit log can distinguish a session that ended from one that lapsed rather than assuming an end row exists.

#### Scenario: A lapsed session has no end audit row
- **WHEN** an impersonation session's expiry passes without anyone ending it
- **THEN** the session row SHALL still show its expiry and a null end time, and no end audit row SHALL have been written
