# Membership creation

## Purpose

What a membership may be created **as**. Phase 5 spent ten rounds governing
every UPDATE to a membership — the price, the length, the count, the dates — and
never once looked at the INSERT, which is where all four of those values first
arrive.

Every failure here is silent in the way this phase's worst ones were: the row
audits clean. One payment, one receipt, `periods_granted = floor(money / price)`
holding, the plan's own price on the row, no frozen term touched — and twice the
membership the money bought.

## Requirements

### Requirement: The first period is set, not added

WHERE an eligible membership has been granted no periods and its dates are
either both present or both absent, THE SYSTEM SHALL set its span from the
recorded sold duration rather than extend a span it already carries.

For a fully dated first grant, THE SYSTEM SHALL start it at the later of its
recorded start and the gym-local current date. For a fully dateless first grant,
THE SYSTEM SHALL start it on the gym-local current date. The end date SHALL be
that start plus the recorded sold duration multiplied by the complete periods
bought. The existing payment eligibility, currency, retired-membership and
activation rules in `payment-record/spec.md` continue to apply.

#### Scenario: A payment that does not complete a period
- **WHEN** a payment leaves eligible money short of one complete period
- **THEN** no period SHALL be granted and neither membership date SHALL move

#### Scenario: The first payment against a membership that carries a typed span
- **WHEN** a payment grants the first period of a fully dated membership
- **THEN** its span SHALL become exactly one sold period, not one period more

#### Scenario: A future agreed start
- **WHEN** the first complete payment arrives before the recorded start date
- **THEN** that start SHALL be preserved and the paid span SHALL begin there

#### Scenario: An unpaid elapsed start
- **WHEN** the first complete payment arrives after the recorded start date
- **THEN** the paid span SHALL begin on the gym-local current date

#### Scenario: Several periods bought by the first complete payment
- **WHEN** the first complete payment buys multiple periods
- **THEN** the span SHALL equal the recorded sold duration times that period count

#### Scenario: A renewal
- **WHEN** a payment grants new periods to a membership already granted a period
- **THEN** its start SHALL remain unchanged and its end SHALL extend from the
  later of its current end and the gym-local current date by those new periods

#### Scenario: The ordinary path
- **WHEN** a payment grants the first period of a fully dateless membership
- **THEN** it SHALL be dated from the gym-local current date for the sold duration,
  with the existing activation rules preserved

#### Scenario: A pending membership with only an end date
- **WHEN** a payment buys a period for a pending membership with a null start and
  a present end date
- **THEN** its start SHALL remain null, its end SHALL extend from the later of
  its current end and the gym-local current date, and it SHALL remain pending

#### Scenario: A pending membership with only a start date
- **WHEN** a payment names a pending membership with a present start and null end
- **THEN** both dates and its granted-period count SHALL remain unchanged

## Recorded boundaries

The proposed universal INSERT date cap was withdrawn and is not implemented.
Unpaid time granted through direct creation remains OPEN-029. Both half-dated
shapes above preserve the deferred OPEN-026 behavior; they are not a remedy for
malformed memberships. A required refund is escalated to an owner or manager.
