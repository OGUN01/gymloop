## Purpose

One command that fills an empty schema with a complete, believable demo gym — enough data that every screen built in a later phase has something real to render, and enough shape that the retention loop and the renewal pipeline both have live cases to show.

## Requirements

### Requirement: One command seeds a complete demo gym
Gate 11 SHALL be met by a single command that populates the demo gym described in `docs/data-model.md`: one Tier-2 neighbourhood gym with its settings and one default branch, thirty members, three trainers and one front-desk user, four plan tiers, six members absent between ten and twenty days, five memberships expiring within seven days, PT, diet and supplement add-ons, and leads at several stages.

#### Scenario: Seeding an empty schema
- **WHEN** the seed command is run against a schema with no rows
- **THEN** exactly one organisation SHALL exist, with one default branch, four active plans, four staff rows and thirty members

#### Scenario: The retention loop has something to show
- **WHEN** the seed has run
- **THEN** exactly six members SHALL have no attendance in the last ten days while holding a live membership

#### Scenario: The renewal pipeline has something to show
- **WHEN** the seed has run
- **THEN** exactly five memberships SHALL be active with an expiry within the next seven days

#### Scenario: The add-on catalogue is populated
- **WHEN** the seed has run
- **THEN** at least one add-on of each kind — PT package, diet plan and product — SHALL exist, and at least one add-on order SHALL reference a verified payment

#### Scenario: Leads exist at more than one stage
- **WHEN** the seed has run
- **THEN** leads SHALL exist in at least three distinct stages

### Requirement: Seeding twice changes nothing
THE SYSTEM SHALL make the seed idempotent: running it a second time SHALL converge on the same demo gym rather than creating a second one or failing on a uniqueness constraint.

#### Scenario: Running the seed twice
- **WHEN** the seed command is run a second time
- **THEN** it SHALL succeed and the number of organisations, members and memberships SHALL be unchanged

### Requirement: Seeded data obeys every constraint the schema enforces
THE SYSTEM SHALL seed only rows that satisfy the schema's own rules — no membership without an expiry, no paid payment without a reference, no overlapping trainer sessions, no negative stock — so the seed is itself a demonstration that the constraints are livable rather than an exception to them.

#### Scenario: The seed passes the data-quality rules
- **WHEN** the seeded data is checked against DQA-001 through DQA-005
- **THEN** no violation SHALL be found

### Requirement: The seed does not run unattended against the shared project
THE SYSTEM SHALL apply the seed only through an explicitly triggered CI run, never as part of the migration stream applied on every merge (ADR-030, ADR-034), so the one Cloud project cannot acquire demo rows by accident.

#### Scenario: A migration merges
- **WHEN** a migration is merged and applied by CI
- **THEN** no seed data SHALL be written
