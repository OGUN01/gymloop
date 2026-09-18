## Purpose

Provide owner and platform metrics from one PostgreSQL statement snapshot, with exact integer money/count serialization, truthful cohorts, and reusable readiness facts.

## Requirements

### Requirement: Owner metrics enforce identity and one snapshot
MET-001 SHALL expose `owner_metrics` only to a real same-gym owner or manager, derive the tenant from verified claims, reject preview/other identities, and return all cards and components from one statement snapshot.

#### Scenario: An owner opens the dashboard
- **WHEN** an authenticated owner or manager requests the dashboard for their gym
- **THEN** the response contains one claim-derived, same-gym statement snapshot
- **AND** a preview or other audience is rejected before the read

### Requirement: Ranges are explicit and timezone-correct
MET-002 SHALL accept neither dates or both inclusive local dates, reject an invalid pair or timezone, and label month-to-date versus explicit ranges with their actual half-open instants.

#### Scenario: An owner selects an explicit range
- **WHEN** both inclusive local dates are valid in the gym timezone
- **THEN** the response labels the corresponding half-open instants
- **AND** a single date, reversed pair or invalid timezone is rejected

### Requirement: Cards reconcile from returned components
MET-003 SHALL calculate visits, live/paused members, cases, follow-ups, recoveries, cash, renewals, leads, add-on cash and PT utilisation from the same response populations; no independent drill-down or row cap is permitted.

#### Scenario: An owner discloses a card's components
- **WHEN** the owner opens a metric card
- **THEN** every displayed component comes from the same returned snapshot
- **AND** the disclosure performs no second metrics query

### Requirement: Money and counts remain exact
MET-004 SHALL serialize integer money, counts and usage as canonical decimal strings, use PostgreSQL numeric/BigInt-safe arithmetic, and never coerce them to JavaScript Number.

#### Scenario: A snapshot contains values beyond safe JavaScript integer precision
- **WHEN** money, counts or usage are serialized
- **THEN** the API and UI preserve their canonical decimal-string values without `Number` coercion

### Requirement: Renewal due uses the canonical remainder
MET-005 SHALL use `membership_renewal_remainder` for every renewal row and never duplicate its formula; zero-net renewals remain visible.

#### Scenario: A membership has a zero or positive renewal remainder
- **WHEN** the renewal population is assembled
- **THEN** each row uses the canonical helper result
- **AND** a zero-net row remains visible

### Requirement: Ratios disclose their cohort
MET-006 SHALL return numerator and denominator components, use exact half-up basis points, and show no cohort when the denominator is zero.

#### Scenario: A ratio has no eligible cohort
- **WHEN** its denominator is zero
- **THEN** the snapshot returns the numerator and denominator and reports no cohort rather than inventing a percentage

### Requirement: Warnings preserve missing evidence
MET-007 SHALL return all relevant undated payment/refund/PT and incomplete PT rows as explicit warnings, excluding them from dated totals without inventing facts.

#### Scenario: A relevant row lacks evidence required for a dated total
- **WHEN** an undated payment, refund or PT row, or an incomplete PT row, is encountered
- **THEN** it is excluded from the dated total and represented by an explicit warning

### Requirement: Fleet metrics reuse owner populations
MET-008 SHALL expose `fleet_metrics` only to platform read roles, aggregate visible gyms from the shared populations in one snapshot, preserve nullable tiers/errors and truthful provider readiness, and expose deterministic exceptions.

#### Scenario: A platform reader opens the fleet
- **WHEN** a super admin or platform support user requests fleet metrics
- **THEN** the response reuses the shared populations in one snapshot and preserves nullable or exceptional facts
- **AND** an ineligible audience is rejected

### Requirement: Readiness is narrow and reusable
OPS-001/004 SHALL expose `gym_readiness` only to platform reads or an eligible same-tenant staff/preview identity, return ordered missing settings and exact provider states, and let platform activation reuse it without roster disclosure.

#### Scenario: Activation evaluates gym readiness
- **WHEN** an eligible caller evaluates a gym for activation
- **THEN** the response returns deterministic missing settings and exact provider states
- **AND** it does not disclose the gym's roster

### Requirement: Dashboard and fleet screens show the validated snapshot
OPS-001/004 SHALL render owner `/dashboard` and platform fleet/detail surfaces from validated response envelopes; range changes fetch a new snapshot while component disclosure stays within the existing response.

#### Scenario: A user changes a dashboard range and inspects a card
- **WHEN** the range changes
- **THEN** the screen requests one newly validated snapshot
- **AND** subsequent component disclosure remains local to that response
