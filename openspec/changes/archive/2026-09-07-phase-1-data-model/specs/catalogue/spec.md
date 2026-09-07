## Purpose

What a gym sells beyond membership: PT packages, diet plans and physical products, a member's order and its usage state, and the personal-training sessions a trainer cannot be double-booked into.

## ADDED Requirements

### Requirement: An add-on carries what a member must see before buying
ADD-002 SHALL be storable: THE SYSTEM SHALL hold, per add-on, its price in paise, its validity period, its cancellation terms, its trainer's qualification where it is a PT package, and its stock level where it is a product.

#### Scenario: A PT package with no session count
- **WHEN** a PT package add-on is written with no session count
- **THEN** the write SHALL be rejected

#### Scenario: A product with no stock level
- **WHEN** a product add-on is written with no stock quantity
- **THEN** the write SHALL be rejected

#### Scenario: A diet plan needs neither
- **WHEN** a diet-plan add-on is written with neither a session count nor a stock quantity
- **THEN** the write SHALL succeed

#### Scenario: A duplicate add-on name at one gym
- **WHEN** a second add-on is written with an existing name at the same organisation
- **THEN** the write SHALL be rejected

### Requirement: Stock can never go negative
DQA-004 and ADD-004 SHALL hold structurally: THE SYSTEM SHALL reject any write that would leave a product's stock quantity below zero.

#### Scenario: Stock driven below zero
- **WHEN** an add-on's stock quantity is updated to a negative number
- **THEN** the write SHALL be rejected

### Requirement: Sessions used can never exceed sessions bought
ADD-004 SHALL hold structurally for PT packages: THE SYSTEM SHALL reject an order whose used session count exceeds its total.

#### Scenario: Consuming more sessions than were bought
- **WHEN** an add-on order is updated so that used sessions exceed total sessions
- **THEN** the write SHALL be rejected

#### Scenario: Consuming the last session
- **WHEN** an add-on order is updated so that used sessions equal total sessions
- **THEN** the write SHALL succeed

#### Scenario: A negative used-session count
- **WHEN** an add-on order is written with a negative used-session count
- **THEN** the write SHALL be rejected

### Requirement: A paid add-on order carries its payment
THE SYSTEM SHALL require any add-on order past `pending` or `cancelled` to reference the payment that bought it, unless its total is zero.

#### Scenario: A paid order with no payment
- **WHEN** an add-on order with a non-zero total is written as `paid` with no payment reference
- **THEN** the write SHALL be rejected

#### Scenario: A pending order with no payment
- **WHEN** an add-on order is written as `pending` with no payment reference
- **THEN** the write SHALL succeed

### Requirement: An add-on order is never hard-deleted
INT-001 SHALL hold for orders as it does for payments: a signed-in caller SHALL have no privilege to delete an add-on order. Cancellation SHALL be a status.

#### Scenario: Deleting an order
- **WHEN** a caller with the `authenticated` role deletes an add-on order in their own tenant
- **THEN** the delete SHALL be refused for want of privilege

### Requirement: A trainer cannot be double-booked
DQA-005 SHALL hold structurally: THE SYSTEM SHALL reject a personal-training session that overlaps in time with another live session for the same trainer.

#### Scenario: Two overlapping sessions for one trainer
- **WHEN** a session is written for a trainer whose time range overlaps an existing `scheduled` session for that trainer
- **THEN** the write SHALL be rejected

#### Scenario: Two adjacent sessions for one trainer
- **WHEN** a session is written for a trainer starting exactly when their previous session ends
- **THEN** the write SHALL succeed

#### Scenario: Overlapping sessions for different trainers
- **WHEN** an overlapping session is written for a different trainer
- **THEN** the write SHALL succeed

#### Scenario: A cancelled session frees the slot
- **WHEN** a session is written overlapping an existing session that is `cancelled`
- **THEN** the write SHALL succeed

#### Scenario: A session that ends before it starts
- **WHEN** a session is written whose end time is not after its start time
- **THEN** the write SHALL be rejected

### Requirement: An order's validity window is coherent
THE SYSTEM SHALL reject an add-on order whose expiry date precedes its start date, and SHALL reject a non-positive quantity.

#### Scenario: An expiry before the start
- **WHEN** an add-on order is written whose expiry precedes its start
- **THEN** the write SHALL be rejected

#### Scenario: A zero quantity
- **WHEN** an add-on order is written with a quantity of zero
- **THEN** the write SHALL be rejected
