## Purpose

Intra-tenant authorization: what each of the seven roles may read and write inside a gym it belongs to. Phase 1 proved one gym cannot reach another gym's rows; this capability adds that being inside the right gym is no longer sufficient. It closes `OPEN-013`.

The authoritative table is **section 8.3 of this change's `design.md`**, one row per table in `public`. Every requirement below states a property of that table; where a requirement and the matrix disagree, the matrix is the specification and the disagreement is a defect to raise, not to resolve by judgement.

## Requirements

### Requirement: A tenant claim alone grants nothing
THE SYSTEM SHALL require both a matching tenant and a recognised role for any gym-side access. A session carrying a valid `tenant_id` claim but no `app_role` claim, or an `app_role` outside the seven-value enum, SHALL read zero rows from every table in `public` and SHALL write to none.

#### Scenario: A tenant claim with no role
- **WHEN** a caller with the `authenticated` role sets a `tenant_id` claim naming a gym that has rows, and sets no `app_role` claim, and selects from a tenant-scoped table
- **THEN** zero rows SHALL be returned

#### Scenario: A tenant claim with no role attempting a write
- **WHEN** that same caller inserts a row whose `tenant_id` is their own gym
- **THEN** the insert SHALL be rejected by the row-security policy

### Requirement: A refused write affects zero rows; a refused insert raises
THE SYSTEM SHALL separate the read gate and the write gate into distinct policies, so that a caller permitted to read a table but not to write it sees an `UPDATE` affect **zero rows** rather than raise. An `INSERT` it is not permitted to make SHALL still be rejected by the row-security policy, there being no existing row for a read gate to filter.

#### Scenario: The read gate and the write gate are separate policies
- **WHEN** the gym-side policies on a table whose read gate and write gate differ are inspected
- **THEN** there SHALL be a `SELECT` policy carrying the read gate and a separate policy carrying the write gate, and no single policy SHALL carry the read gate on `USING` and the write gate on `WITH CHECK`

#### Scenario: A refused update is silent
- **WHEN** a caller who may read a table but not write it updates a row of it in their own tenant
- **THEN** zero rows SHALL be affected and no error SHALL be raised

#### Scenario: A refused insert is not silent
- **WHEN** that same caller inserts a row into that table in their own tenant
- **THEN** the insert SHALL be rejected by the row-security policy

### Requirement: An unrecognised role grants nothing and raises nothing
THE SYSTEM SHALL treat an `app_role` claim outside the seven-value vocabulary as conferring no privilege, on every table, and SHALL NOT raise. The role claim SHALL be compared as text and never cast to the enum, so that one forged claim does not behave differently from table to table.

#### Scenario: A role claim that is not a role
- **WHEN** a caller sets an `app_role` claim of `superuser` together with a valid tenant claim, and selects from every table in `public`
- **THEN** zero rows SHALL be returned from each, and no error SHALL be raised

#### Scenario: A role claim that is not a role, attempting a write
- **WHEN** that same caller updates a row in their claimed tenant
- **THEN** zero rows SHALL be affected and no error SHALL be raised

### Requirement: The gate vocabulary is closed
THE SYSTEM SHALL express every gym-side policy gate using exactly four predicates — the acting role, whether it is any of the four gym-side staff roles, whether it is an owner or manager, and whether it is a staff role other than trainer — and SHALL define each as a function in the `app` schema rather than repeating a role list inline.

#### Scenario: The gates exist as functions
- **WHEN** the `app` schema is inspected for functions
- **THEN** it SHALL contain accessors for the acting role, the acting member, the acting staff row, and the acting impersonation session, and the three role-set gates

#### Scenario: No policy reads the claims directly
- **WHEN** every policy expression on every table in `public` is inspected
- **THEN** none SHALL reference `request.jwt.claims`, every claim being read through an `app` accessor

### Requirement: A policy still references only its own table
Phase 1's guarantee is unchanged by the role matrix. No policy expression SHALL reference any table other than the one the policy is attached to, so no access decision becomes a per-row subquery.

#### Scenario: A policy expression naming another table
- **WHEN** every policy expression on every table in `public` is inspected
- **THEN** none SHALL reference a table other than the one the policy is attached to

### Requirement: Every table's read gate matches the matrix
FOR every table in `public`, THE SYSTEM SHALL admit a read by exactly the roles the matrix names for it, and SHALL return zero rows to every gym-side role it does not name.

#### Scenario: A trainer reading money
- **WHEN** a caller whose role claim is `trainer` and whose tenant claim is gym A selects from `payments`, `refunds`, `invoices`, `razorpay_accounts` or `document_counters`, each holding rows for gym A
- **THEN** zero rows SHALL be returned

#### Scenario: A trainer reading the retention loop
- **WHEN** that same caller selects from `members`, `attendance`, `memberships`, `no_show_cases`, `follow_ups`, `plans`, `addon_products` or `pt_sessions`, each holding rows for gym A
- **THEN** gym A's rows SHALL be returned

#### Scenario: Front desk reading the gym's own configuration
- **WHEN** a caller whose role claim is `front_desk` selects from `razorpay_accounts`, `messaging_wallets`, `messaging_wallet_ledger`, `webhook_events`, `audit_log`, `impersonation_sessions` or `member_imports`, each holding rows for their gym
- **THEN** zero rows SHALL be returned

#### Scenario: An owner reading everything in their gym
- **WHEN** a caller whose role claim is `gym_owner` selects from any table in `public` that holds rows for their gym, other than `platform_users`
- **THEN** their gym's rows SHALL be returned

#### Scenario: A gym-side role reading the platform roster
- **WHEN** a caller whose role claim is any of the four gym-side staff roles, or `member`, selects from `platform_users`
- **THEN** zero rows SHALL be returned

### Requirement: Every table's write gate matches the matrix
FOR every table in `public`, THE SYSTEM SHALL admit a write by exactly the roles the matrix names for it, and SHALL reject a write attempted by any other gym-side role even when the row is correctly labelled with the caller's own tenant.

#### Scenario: A manager promoting itself
- **WHEN** a caller whose role claim is `gym_manager` updates a `staff` row in their own gym to set its role to `gym_owner`
- **THEN** zero rows SHALL be affected, no error SHALL be raised, and the row SHALL be unchanged

#### Scenario: A manager inserting a staff member
- **WHEN** that same caller inserts a `staff` row into their own gym
- **THEN** the insert SHALL be rejected by the row-security policy

#### Scenario: An owner changing a staff member's role
- **WHEN** a caller whose role claim is `gym_owner` updates a `staff` row in their own gym
- **THEN** the update SHALL succeed

#### Scenario: Front desk changing the price list
- **WHEN** a caller whose role claim is `front_desk` updates a `plans` row in their own gym
- **THEN** zero rows SHALL be affected

#### Scenario: Front desk recording a payment
- **WHEN** that same caller inserts a `payments` row into their own gym
- **THEN** the insert SHALL succeed

#### Scenario: A trainer recording attendance
- **WHEN** a caller whose role claim is `trainer` inserts an `attendance` row into their own gym
- **THEN** the insert SHALL be rejected by the row-security policy

#### Scenario: A trainer recording a follow-up
- **WHEN** that same caller inserts a `follow_ups` row for a case in their own gym
- **THEN** the insert SHALL succeed

### Requirement: A member reads only their own rows, and only from the tables the matrix names
THE SYSTEM SHALL return to a `member` session, from each table carrying a member-scoped policy, only the rows whose member is the acting member; SHALL return zero rows from every table carrying no member policy; and SHALL return the whole gym's rows only from the tables the matrix marks as gym-wide for members.

#### Scenario: A member reading another member's data
- **WHEN** a caller whose role claim is `member` and whose member claim is member X selects from `attendance`, `memberships`, `payments`, `notifications`, `member_devices`, `consents`, `addon_orders` or `pt_sessions`, each holding rows for member X and for another member of the same gym
- **THEN** only member X's rows SHALL be returned

#### Scenario: A member reading the member roster
- **WHEN** that same caller selects from `members`, which holds their own row and other members' rows in the same gym
- **THEN** only their own row SHALL be returned

#### Scenario: A member reading the gym's catalogue
- **WHEN** that same caller selects from `organizations`, `branches`, `plans`, `addon_products` or `organization_holidays`
- **THEN** their gym's rows SHALL be returned

#### Scenario: A member reading what members may not see
- **WHEN** that same caller selects from `staff`, `coupons`, `qr_sessions`, `no_show_cases`, `follow_ups`, `organization_settings`, `invoices`, `refunds`, `membership_pauses`, `attendance_corrections`, `message_templates`, `leads`, `member_imports`, `razorpay_accounts`, `razorpay_mandates`, `document_counters`, `messaging_wallets`, `messaging_wallet_ledger`, `webhook_events`, `audit_log` or `impersonation_sessions`, each holding rows for their own gym
- **THEN** zero rows SHALL be returned from every one of them

#### Scenario: A member claim carried by a session that is not a member
- **WHEN** a caller whose role claim is `trainer` also carries a `member_id` claim naming a member of their gym, and selects from `consents`, `notifications`, `member_devices` or `payments`
- **THEN** zero rows SHALL be returned — the member policy SHALL require the role as well as the claim, rather than relying on the token issuer never pairing the two

#### Scenario: A member with no member claim
- **WHEN** a caller whose role claim is `member` and whose tenant claim is gym A carries no `member_id` claim, and selects from a member-scoped table holding gym A's rows
- **THEN** zero rows SHALL be returned

### Requirement: A member writes nothing directly
THE SYSTEM SHALL reject every write attempted by a `member` session against every table in `public`, member-readable tables included, because no v1 flow writes to the database directly from a member session.

#### Scenario: A member updating their own profile
- **WHEN** a caller whose role claim is `member` updates their own `members` row
- **THEN** zero rows SHALL be affected

#### Scenario: A member registering a device
- **WHEN** that same caller inserts a `member_devices` row naming themselves in their own gym
- **THEN** the insert SHALL be rejected by the row-security policy

#### Scenario: A member inserting attendance for themselves
- **WHEN** that same caller inserts an `attendance` row naming themselves in their own gym
- **THEN** the insert SHALL be rejected by the row-security policy

### Requirement: A table the gym may not write carries a select-only policy
THE SYSTEM SHALL attach a select-only gym-side policy — not an all-command one — to the tables whose privilege grant already withholds insert and update, so that no policy permits what the grant denies.

#### Scenario: The read-only tables carry no all-command gym policy
- **WHEN** the policies on `audit_log`, `webhook_events`, `messaging_wallets`, `messaging_wallet_ledger` and `impersonation_sessions` are inspected
- **THEN** the gym-side policy on each SHALL be for `SELECT` only

### Requirement: Platform support reads everywhere and writes nowhere
THE SYSTEM SHALL let `platform_support` read across all tenants, as `super_admin` does, and SHALL reject every write it attempts on every table — including its own row in `platform_users`, so a support account cannot promote itself.

#### Scenario: Support reads across tenants
- **WHEN** a caller whose role claim is `platform_support` selects from a table holding rows for two gyms
- **THEN** rows from both gyms SHALL be returned

#### Scenario: Support writing a gym's data
- **WHEN** that same caller updates a row belonging to a gym, or inserts one
- **THEN** the update SHALL affect zero rows without raising, and the insert SHALL be rejected by the row-security policy

#### Scenario: Support promoting itself
- **WHEN** that same caller updates their own `platform_users` row to set its role to `super_admin`
- **THEN** zero rows SHALL be affected and the row SHALL be unchanged

#### Scenario: A super admin writing across tenants
- **WHEN** a caller whose role claim is `super_admin` updates a row belonging to a gym
- **THEN** the update SHALL succeed

### Requirement: Every column a policy filters on is still indexed
The index rule is unchanged and now has more to cover: THE SYSTEM SHALL index every column appearing in any policy predicate. A standalone index whose leading column is that column satisfies the rule, as does its position immediately after the tenant column in a tenant-leading composite.

#### Scenario: A policy column with no index
- **WHEN** every column appearing in a policy predicate on every table in `public` is inspected against that table's indexes
- **THEN** every such column SHALL lead an index, or sit immediately after the tenant column in a tenant-leading index
