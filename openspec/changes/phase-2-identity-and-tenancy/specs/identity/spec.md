## Purpose

Turning a signed-in `auth.users` row into a Gymloop identity: the custom access-token hook, the claims it stamps, the order it resolves identities in, what an inactive or unlinked user gets, how one human who belongs to several gyms gets a token for exactly one of them, and how a live session loses its privileges when the row behind it changes.

Every requirement here is expressible as a direct call to `app.custom_access_token_hook(<event>)` returning jsonb, or as a query against the catalogue. None of them requires signing in.

## Requirements

### Requirement: The hook is reachable by Auth and by nobody else
THE SYSTEM SHALL define the access-token hook in the `app` schema, not in `public`, so it is neither exposed through the Data API nor present in the generated types. `supabase_auth_admin` SHALL hold `usage` on the schema and `execute` on the function; `anon`, `authenticated` and `public` SHALL hold `execute` on it not at all.

#### Scenario: The hook is not on the public API surface
- **WHEN** the schema of the access-token hook function is inspected
- **THEN** it SHALL be `app` and SHALL NOT be `public`

#### Scenario: A signed-in caller cannot execute the hook
- **WHEN** execute privilege on the hook function is inspected for `authenticated` and for `anon`
- **THEN** neither SHALL hold it

#### Scenario: Auth's own role can execute the hook
- **WHEN** execute privilege on the hook function is inspected for `supabase_auth_admin`
- **THEN** it SHALL hold it

### Requirement: A failing hook degrades to a claimless token, never to an outage
A Postgres auth hook fails closed: an exception issues no token at all, for every user of the project at once. THE SYSTEM SHALL therefore contain the hook's resolution logic in an exception handler that returns the event unmodified, so that any unanticipated failure yields a token carrying no Gymloop claims — a session that reads zero rows — rather than a sign-in outage.

#### Scenario: An event that is not the documented shape
- **WHEN** the hook is called with a jsonb value that carries no `user_id` key
- **THEN** it SHALL return without raising

#### Scenario: A user id that matches nothing
- **WHEN** the hook is called with a `user_id` that exists in none of the three identity tables
- **THEN** it SHALL return without raising, and the returned claims SHALL carry neither `tenant_id` nor `app_role`

#### Scenario: A null user id
- **WHEN** the hook is called with `user_id` set to JSON null
- **THEN** it SHALL return without raising

### Requirement: The hook returns the whole claims object
Supabase Auth performs no implicit merge and rejects a token missing its required claims. THE SYSTEM SHALL return the event's existing claims with the Gymloop claims added, preserving every claim it did not set, and SHALL NOT alter any reserved claim (`iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`, `email`, `phone`, `is_anonymous`).

#### Scenario: Pre-existing claims survive
- **WHEN** the hook is called with an event whose claims carry `sub`, `aud`, `role` and `session_id`
- **THEN** every one of those claims SHALL be present in the returned claims with its original value

#### Scenario: The Postgres role claim is never rewritten
- **WHEN** the hook is called with an event whose `role` claim is `authenticated`, for a user who resolves to a `super_admin` identity
- **THEN** the returned `role` claim SHALL still be `authenticated`

### Requirement: A claim is absent or well-formed, never empty
THE SYSTEM SHALL omit a claim key entirely when it has no value for it, and SHALL NOT emit an empty string or a JSON null for `tenant_id`, `app_role`, `member_id`, `staff_id` or `impersonation_session_id`.

#### Scenario: An unlinked user's claims
- **WHEN** the hook is called for a user who matches no identity row
- **THEN** the returned claims SHALL contain no `tenant_id` key at all, rather than a `tenant_id` whose value is an empty string or null

#### Scenario: A platform user carries no gym claims
- **WHEN** the hook is called for an active `super_admin` with no live impersonation session
- **THEN** the returned claims SHALL carry `app_role` of `super_admin`, and SHALL contain no `tenant_id`, `member_id` or `staff_id` key

### Requirement: Identity resolves in one fixed order and stops at the first match
THE SYSTEM SHALL resolve a user against `platform_users`, then `staff`, then `members`, in that order, and SHALL stop at the first table in which the user has a row.

#### Scenario: A platform user who is also a gym member
- **WHEN** the hook is called for a user who has an active `platform_users` row and also an active `members` row
- **THEN** the returned `app_role` SHALL be the platform role and the returned claims SHALL carry no `member_id`

#### Scenario: A staff member who is also a member of the same gym
- **WHEN** the hook is called for a user who has an active `staff` row and an active `members` row in the same tenant
- **THEN** the returned claims SHALL carry `staff_id` and SHALL NOT carry `member_id`

#### Scenario: A gym member
- **WHEN** the hook is called for a user whose only identity is an active `members` row
- **THEN** the returned claims SHALL carry `app_role` of `member`, the member's `tenant_id`, and that member's id as `member_id`

### Requirement: An inactive identity gets nothing, and does not fall through
IF the identity row matched by the resolution order has `is_active` false, THEN THE SYSTEM SHALL stop resolving and SHALL return a token carrying no Gymloop claims. It SHALL NOT continue to the next table in the order.

#### Scenario: A deactivated super admin
- **WHEN** the hook is called for a user whose `platform_users` row has `is_active` false
- **THEN** the returned claims SHALL carry no `app_role` and no `tenant_id`

#### Scenario: A deactivated super admin who is also an active member
- **WHEN** the hook is called for a user whose `platform_users` row is inactive and who also has an active `members` row
- **THEN** the returned claims SHALL carry no `app_role`, no `tenant_id` and no `member_id` — the inactive platform identity SHALL NOT degrade into a member identity

#### Scenario: A deactivated staff member
- **WHEN** the hook is called for a user whose only `staff` row has `is_active` false
- **THEN** the returned claims SHALL carry no `app_role` and no `tenant_id`

### Requirement: One token is for exactly one gym, and the requested gym is validated
WHERE a user has identity rows in more than one tenant, THE SYSTEM SHALL issue a token for exactly one of them. It SHALL read the requested tenant from the user's `raw_app_meta_data` key `active_tenant_id`, SHALL honour it only if the user has an active row in that tenant, and SHALL otherwise fall back to the user's active row with the earliest `created_at`, ties broken by the lower `id`, without raising.

#### Scenario: A valid requested tenant
- **WHEN** the hook is called for a user with active staff rows in two gyms, whose `active_tenant_id` names the second
- **THEN** the returned `tenant_id` SHALL be the second gym and `staff_id` SHALL be that gym's staff row

#### Scenario: A requested tenant the user does not belong to
- **WHEN** the hook is called for a user with active staff rows in two gyms, whose `active_tenant_id` names a third gym
- **THEN** the returned `tenant_id` SHALL be one of the two gyms the user belongs to, and SHALL NOT be the third

#### Scenario: A requested tenant where the user's row has been deactivated
- **WHEN** the hook is called for a user with an active staff row in gym A and an inactive one in gym B, whose `active_tenant_id` names gym B
- **THEN** the returned `tenant_id` SHALL be gym A

#### Scenario: No requested tenant at all
- **WHEN** the hook is called twice for a user with active staff rows in two gyms and no `active_tenant_id`
- **THEN** both calls SHALL return the same `tenant_id`, being the row with the earliest creation time

### Requirement: Deactivation and role change revoke the sessions already issued
A claim is a copy of a row taken when the token was issued, so changing the row changes nothing about a token already held. THE SYSTEM SHALL delete the user's authentication sessions when an identity row's `is_active` goes from true to false, and when an identity row's `role` changes, so that the access token in hand is the last one that user receives.

#### Scenario: Deactivating a staff member
- **WHEN** a staff row with a linked user is updated to `is_active` false
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Changing a staff member's role
- **WHEN** a staff row's `role` is changed from `front_desk` to `gym_manager`
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Deactivating a platform user
- **WHEN** a `platform_users` row is updated to `is_active` false
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: An unrelated update revokes nothing
- **WHEN** a staff row's `full_name` is updated and neither `is_active` nor `role` changes
- **THEN** that user's authentication sessions SHALL be unchanged

### Requirement: A role change writes an audit row
INT-003 names a role change as an audited event. THE SYSTEM SHALL write an `audit_log` row when an identity row's `role` changes, recording the actor, the record type and id, and the before and after values, without the caller having to ask.

#### Scenario: A role change is audited
- **WHEN** a staff row's `role` is changed
- **THEN** an `audit_log` row SHALL exist for that record naming the previous and the new role

### Requirement: The first platform account is created once and never again
THE SYSTEM SHALL provide a way to create the very first `super_admin` from an already-registered authentication user, and that mechanism SHALL be inert once any `platform_users` row exists — so it cannot become a general-purpose way to create platform accounts.

#### Scenario: Bootstrapping into an empty platform roster
- **WHEN** the bootstrap runs against a database with no `platform_users` rows, naming a registered user
- **THEN** exactly one `platform_users` row SHALL exist afterwards, with role `super_admin`

#### Scenario: Bootstrapping again
- **WHEN** the bootstrap runs a second time naming a different registered user
- **THEN** no new `platform_users` row SHALL be created

### Requirement: The access token's lifetime is chosen, not defaulted
THE SYSTEM SHALL set the access-token lifetime explicitly in `supabase/config.toml`, and the value SHALL be shorter than the platform default of one hour, because the interval between a revocation and a token's expiry is the window in which a revoked privilege still works.

#### Scenario: The lifetime is configured
- **WHEN** `supabase/config.toml` is inspected for the access-token expiry setting
- **THEN** it SHALL be present and SHALL be less than 3600
