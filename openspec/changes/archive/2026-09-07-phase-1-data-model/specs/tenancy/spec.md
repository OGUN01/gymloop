## Purpose

Tenant isolation for a single Postgres database shared by every gym: the organisation → branch → member hierarchy, the JWT-claim tenant contract every other table inherits, and the guarantee that one gym can never reach another gym's rows under any role.

## ADDED Requirements

### Requirement: Tenant scoping is universal and closed
Every table in the `public` schema SHALL either carry a `tenant_id` column referencing `organizations`, or be `organizations` itself (whose `id` is the tenant id). The only exemptions SHALL be the two named in `docs/decisions.md` ADR-033 — `platform_users`, which carries no tenant column, and `audit_log`, whose tenant column is nullable for platform-level events. A third exemption SHALL NOT exist.

#### Scenario: A table without a tenant column
- **WHEN** the schema is inspected for tables in `public` that carry neither a `tenant_id` column nor a tenant identity of their own
- **THEN** the result SHALL contain only `platform_users`

#### Scenario: Row-Level Security is on everywhere
- **WHEN** the schema is inspected for tables in `public` with Row-Level Security disabled
- **THEN** the result SHALL be empty

### Requirement: The tenant id comes from the JWT claim, never from a subquery
THE SYSTEM SHALL read the acting tenant from the `tenant_id` claim of the request's JWT, through exactly one accessor function. No Row-Level Security policy SHALL contain a subquery against another table to establish the acting tenant.

#### Scenario: A policy expression referencing another table
- **WHEN** every policy expression on every table in `public` is inspected
- **THEN** none SHALL reference a table other than the one the policy is attached to

#### Scenario: The accessor reads the claim
- **WHILE** a `tenant_id` claim is set on the session
- **THEN** the tenant accessor SHALL return that value as a uuid

### Requirement: A missing tenant claim grants nothing
IF the request carries no `tenant_id` claim, or an empty one, THEN THE SYSTEM SHALL return zero rows from every tenant-scoped table for the `authenticated` role, and SHALL NOT raise an error.

#### Scenario: Reading with no claim at all
- **WHEN** a caller with the `authenticated` role and no JWT claims reads a tenant-scoped table that contains rows
- **THEN** the read SHALL return zero rows and SHALL NOT raise

#### Scenario: Writing with no claim at all
- **WHEN** a caller with the `authenticated` role and no JWT claims inserts into a tenant-scoped table
- **THEN** the insert SHALL be rejected by the row-security policy

### Requirement: One gym can never reach another gym's rows
WHILE acting as gym A, THE SYSTEM SHALL NOT allow a caller to read, insert, update or delete any row belonging to gym B, on any table, regardless of the caller's role within gym A.

#### Scenario: Reading across tenants
- **WHEN** a caller whose `tenant_id` claim is gym A selects from a table holding rows for both gym A and gym B
- **THEN** only gym A's rows SHALL be returned

#### Scenario: Updating another tenant's row
- **WHEN** a caller whose `tenant_id` claim is gym A updates a row belonging to gym B by its primary key
- **THEN** zero rows SHALL be affected and gym B's row SHALL be unchanged

#### Scenario: Inserting a row labelled with another tenant
- **WHEN** a caller whose `tenant_id` claim is gym A inserts a row whose `tenant_id` is gym B
- **THEN** the insert SHALL be rejected by the row-security policy

#### Scenario: Deleting another tenant's row
- **WHEN** a caller whose `tenant_id` claim is gym A attempts to delete a row belonging to gym B
- **THEN** gym B's row SHALL still exist afterwards

### Requirement: Platform roles cross tenants by policy, never by disabling RLS
WHILE the acting role claim is `super_admin` or `platform_support`, THE SYSTEM SHALL grant access across all tenants through a policy branch. Row-Level Security SHALL remain enabled on every table for those roles.

#### Scenario: A platform role reads every tenant
- **WHEN** a caller whose role claim is `super_admin` selects from a table holding rows for two gyms
- **THEN** rows from both gyms SHALL be returned

#### Scenario: A gym-side role is not a platform role
- **WHEN** a caller whose role claim is `gym_owner` and whose tenant claim is gym A selects from a table holding rows for two gyms
- **THEN** only gym A's rows SHALL be returned

### Requirement: Every column a policy filters on is indexed
THE SYSTEM SHALL provide, for every tenant-scoped table, at least one btree index whose leading column is that table's tenant column, and SHALL index every foreign-key column.

#### Scenario: A tenant column with no leading index
- **WHEN** the schema is inspected for tenant-scoped tables with no index whose first column is the tenant column
- **THEN** the result SHALL be empty

#### Scenario: An unindexed foreign key
- **WHEN** the schema is inspected for foreign-key columns that neither lead an index of their own nor sit immediately after the tenant column in a tenant-leading composite index
- **THEN** the result SHALL be empty

### Requirement: Table privileges are granted deliberately, not inherited
THE SYSTEM SHALL grant the `anon` role no privilege on any table in `public`. THE SYSTEM SHALL NOT grant `DELETE` or `TRUNCATE` on any table to `authenticated`, so that INT-001 (financial records, attendance corrections and follow-up history are never hard-deleted) holds structurally rather than by convention.

#### Scenario: The anonymous role has no reach
- **WHEN** the schema is inspected for privileges held by `anon` on tables in `public`
- **THEN** the result SHALL be empty

#### Scenario: No table can be deleted from by a signed-in user
- **WHEN** the schema is inspected for tables in `public` granting `DELETE` or `TRUNCATE` to `authenticated`
- **THEN** the result SHALL be empty

### Requirement: Append-only tables cannot be rewritten
THE SYSTEM SHALL withhold `UPDATE` from `authenticated` on the append-only tables — attendance corrections, follow-ups, consents, the audit log, the messaging wallet ledger and webhook events — so a recorded fact can be superseded by a new row but never altered (INT-001, NSH-007, DPD-004).

#### Scenario: Attempting to alter an append-only row
- **WHEN** a caller with the `authenticated` role updates a row in an append-only table inside their own tenant
- **THEN** the update SHALL be refused for want of privilege

### Requirement: The organisation hierarchy exists from day one
THE SYSTEM SHALL model a gym as an `organization` containing one or more `branches`, with each member and each staff row belonging to the organisation and referencing a branch. Exactly one branch per organisation SHALL be marked as the default.

#### Scenario: A second default branch
- **WHEN** a second branch of the same organisation is marked default
- **THEN** the write SHALL be rejected by a uniqueness constraint

#### Scenario: A gym code is globally unique
- **WHEN** two organisations are written with the same gym code
- **THEN** the second write SHALL be rejected

#### Scenario: A malformed gym code
- **WHEN** an organisation is written with a gym code that is not six upper-case alphanumeric characters
- **THEN** the write SHALL be rejected

### Requirement: The role vocabulary is a database enum
THE SYSTEM SHALL define the seven v1 roles (`super_admin`, `platform_support`, `gym_owner`, `gym_manager`, `front_desk`, `trainer`, `member`) as a Postgres enum, which is the single source the generated TypeScript types derive from. A parallel TypeScript role constant SHALL NOT exist.

#### Scenario: An invalid role label
- **WHEN** a staff row is written with a role outside the enum
- **THEN** the write SHALL be rejected

#### Scenario: A gym-side staff row cannot hold a platform role
- **WHEN** a staff row is written with role `super_admin`
- **THEN** the write SHALL be rejected

### Requirement: A member's identifying details are unique within their gym and never include a government ID
THE SYSTEM SHALL reject a second member with the same phone number within one organisation (the duplicate-phone detection CSV import depends on), SHALL store phone numbers in E.164 form, and SHALL provide no column for a government-issued identity document (DPD-008).

#### Scenario: A duplicate phone within one gym
- **WHEN** a second member of the same organisation is written with an existing member's phone number
- **THEN** the write SHALL be rejected

#### Scenario: The same phone number at a different gym
- **WHEN** a member of a different organisation is written with that same phone number
- **THEN** the write SHALL succeed

#### Scenario: A malformed phone number
- **WHEN** a member is written with a phone number that is not in E.164 form
- **THEN** the write SHALL be rejected

### Requirement: Erasure blanks personal data without destroying the row
THE SYSTEM SHALL support marking a member as erased while retaining the row itself and the financial history that references it (DPD-006, INT-001).

#### Scenario: An erased member is still referenced
- **WHEN** a member is marked erased
- **THEN** the member row SHALL still exist and rows referencing it SHALL still resolve
