## Purpose

Synthetic data shaped so the **retention loop** can be exercised end to end, rather than data that merely fills tables. The existing seed gives one gym, thirty members, and every single one of them `active` with an `active` membership and six weeks of attendance. Nothing in it can be detected, because there is nothing to detect *against*: no lapsed member, no approaching expiry, no pause, no broken streak.

Each scenario below is a **named member**, so a test, a screen or a person can say "the member who paused" instead of "member 17". The names are the fixture identifiers and must not be renumbered casually — an assertion that names a scenario still means something after the data changes; one that says "the seventeenth row" does not.

## Requirements

### Requirement: Every member status and every membership status is represented
THE SYSTEM's demo data SHALL contain at least one member in each `member_status` and at least one membership in each `membership_status`, so no screen or query is written against a world where only `active` exists.

#### Scenario: Every enum value appears
- **WHEN** the demo data is inspected for the distinct values of `members.status` and `memberships.status`
- **THEN** each enum's full set SHALL be present

### Requirement: The renewal windows each have a member sitting in them
PAY-001 defines reminder windows at **-14, -7, -3, 0 and +3 days** from expiry. THE SYSTEM's demo data SHALL contain a member whose membership ends in each of those windows, so a reminder run has something to find in every one and an off-by-one at the boundary is visible rather than theoretical.

#### Scenario: A member in each window
- **WHEN** the demo data is grouped by days between today and `memberships.ends_on`
- **THEN** each of -14, -7, -3, 0 and +3 SHALL be occupied

### Requirement: Churn candidates sit either side of the threshold
The gym's `no_show_threshold_days` decides who is at risk. THE SYSTEM's demo data SHALL contain members whose last visit was **just inside** and **just outside** that threshold, and one who has never visited at all.

#### Scenario: Either side of the boundary
- **WHEN** the demo data is inspected for days since last attendance
- **THEN** at least one member SHALL be one day short of the threshold, one SHALL be one day past it, and one SHALL have no attendance at all

### Requirement: A paused member is not a churn candidate
NSH-002 excludes `paused` and `frozen` members from the red list. THE SYSTEM's demo data SHALL contain a member with an **approved** pause covering today who has not attended for longer than the threshold — the case that catches a no-show scan which forgot to check for a pause.

#### Scenario: A paused member with a long absence
- **WHEN** the demo data is inspected
- **THEN** a member SHALL exist with an approved pause covering today and a last visit older than the gym's threshold

#### Scenario: A rejected pause is not a pause
- **WHEN** a member's only pause has been rejected
- **THEN** that member SHALL be treated as unpaused

### Requirement: Streaks have something to compute
STK-001 names three rule types and STK-002 says a rest day or an approved pause does not break a streak. THE SYSTEM's demo data SHALL contain a member with a long unbroken run, one whose run is bridged only by their configured rest days, one whose run is bridged only by an approved pause, and one with a genuinely broken streak.

#### Scenario: The rest-day case is distinguishable
- **WHEN** the member whose gaps fall only on their configured rest days is evaluated
- **THEN** their streak SHALL be unbroken, and it SHALL differ from a member with the same gaps and no rest days configured

### Requirement: The history is long enough to mean something
THE SYSTEM's demo data SHALL carry at least six months of attendance, because a six-week window cannot show a habit forming, a streak of any length, or a member drifting away over a season.

#### Scenario: Six months of history
- **WHEN** the span between the earliest and latest attendance is measured
- **THEN** it SHALL be at least 180 days

### Requirement: The data is idempotent and additive
THE SYSTEM SHALL allow the scenario data to be applied repeatedly without duplicating rows, and SHALL NOT alter or remove the rows the existing seed creates — the current thirty members stay exactly as they are (ADR-034's idempotency, and gate 11).

#### Scenario: Applied twice
- **WHEN** the scenario data is applied a second time
- **THEN** the row counts SHALL be identical to after the first
