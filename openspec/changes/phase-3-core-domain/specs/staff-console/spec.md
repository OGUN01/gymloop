## Purpose

The first screens: a staff member signs in with email and password, and sees the members of their own gym. This is the slice that makes Phase 2's identity layer observable — until now every claim has been set by hand in a pgTAP fixture and no real token has ever been issued.

## Requirements

### Requirement: Only a signed-in staff session reaches the console
THE SYSTEM SHALL redirect an unauthenticated visitor from every console route to the sign-in page, and SHALL NOT render any console content before the session is established.

#### Scenario: An unauthenticated visitor
- **WHEN** a visitor with no session requests a console route
- **THEN** they SHALL be redirected to the sign-in page

#### Scenario: A signed-in visitor on the sign-in page
- **WHEN** a visitor with a valid session requests the sign-in page
- **THEN** they SHALL be redirected to the console

### Requirement: Sign-in is by email and password, and there is no self-signup
THE SYSTEM SHALL authenticate a staff member by email and password. It SHALL NOT offer a route by which a visitor creates their own account — gym accounts are created by the gym, and platform accounts by an existing super admin.

#### Scenario: Correct credentials
- **WHEN** a staff member submits an email and password matching an active identity
- **THEN** a session SHALL be established and they SHALL land on the console

#### Scenario: Wrong credentials
- **WHEN** the password does not match
- **THEN** an error SHALL be shown, no session SHALL be established, and the message SHALL NOT reveal whether the email exists

### Requirement: A session with no Gymloop identity is told so, not broken
A signed-in `auth.users` row that no gym has linked receives a token with no `app_role` claim — a supported state (`openspec/specs/identity/`). THE SYSTEM SHALL show such a session a page saying the account is not linked to a gym, and SHALL NOT show an empty member list, an error page, or a crash.

#### Scenario: A linked-to-nothing account signs in
- **WHEN** a session whose token carries no `app_role` reaches the console
- **THEN** a page SHALL explain the account is not yet linked to a gym

### Requirement: The member list is filtered by the database, never by the application
THE SYSTEM SHALL read members through the caller's own session so that Row-Level Security performs the filtering, and SHALL NOT add a tenant predicate of its own. An application-side tenant filter would mask exactly the defect the pgTAP suite exists to catch.

#### Scenario: A gym's staff sees its own members
- **WHEN** a staff session lists members and the database holds members of two gyms
- **THEN** only their own gym's members SHALL be shown

#### Scenario: The query carries no tenant of its own
- **WHEN** the member-list query is inspected
- **THEN** it SHALL contain no `tenant_id` filter, that being the policy's job

### Requirement: A member is findable by phone
THE SYSTEM SHALL let staff find a member by phone number, which is how a front desk identifies someone standing in front of them.

#### Scenario: Searching by a full phone number
- **WHEN** staff search for a member's phone number
- **THEN** that member SHALL be listed

#### Scenario: Searching for a member of another gym
- **WHEN** staff search for the phone number of a member of a different gym
- **THEN** no member SHALL be listed

### Requirement: Signing out ends the session
THE SYSTEM SHALL provide a sign-out that clears the session, after which console routes redirect to sign-in again.

#### Scenario: Signing out
- **WHEN** a signed-in staff member signs out and then requests a console route
- **THEN** they SHALL be redirected to the sign-in page
