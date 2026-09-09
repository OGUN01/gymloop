# Membership lifecycle

## Purpose

Which membership status may follow which, and what that means for money already
paid. `payments` has had a state machine since Phase 5 round three
(`app.payment_transition_allowed()`, `GL039`); `memberships` has never had one,
and three rules already depend on the answer.

Every failure here is **silent to everyone but the member**. A membership
revived out of `cancelled` looks like an ordinary active one, and nothing
surfaces it — the check-in gate reads exactly this column.

**Retiring a live membership early is not one of those failures**, and an
earlier draft of this paragraph listed it as one while the requirement below
permits it. Ending a membership before its dates run out is what cancellation
*is*. What this change does make permanent is the mistake: a status written to
`expired` or `cancelled` in error can no longer be typed back, and the repair is
to sell the member a new membership — which the freed one-live-membership index
allows, and which a blind author asserted end to end rather than assuming.

## Requirements

### Requirement: A membership's status moves only where it can go
WHEN a membership's status changes, THE SYSTEM SHALL refuse any change that is
not one of: `pending` to `active` or `cancelled`; `active` to `frozen`,
`cancelled` or `expired`; `frozen` to `active`, `cancelled` or `expired`. THE
SYSTEM SHALL refuse every change out of `expired` and `cancelled`.

`docs/data-model.md` has listed exactly this set since Phase 1 and called
`expired` and `cancelled` terminal. **Nothing has ever enforced it**, which a
critic showed from an ordinary front-desk session in one statement:
`cancelled → active`, reviving a retired membership.

**Retiring a membership early is not the defect**, and an earlier draft of this
paragraph implied it was by naming "`expired` written onto a membership live for
another ten days" as a harm and then permitting exactly that two scenarios
below. Ending a membership before its dates run out is what cancellation *is* —
it is half of the repair this codebase prescribes for every mis-sold membership,
and `expired` is the same act under a different word. The defect is that
**nothing distinguished a legal move from an illegal one**, so the one move that
must never happen — coming back out of a terminal state — was as available as
the ones that must.

A status written back to itself is **allowed** — it changes nothing, and a rule
that refuses a write which cannot do harm breaks ordinary column-listing
updates. This is settled the same way for `periods_granted`, the dates, and the
frozen terms.

**`expired` is legal to write and the product never writes it.** ADR-064/075
say liveness is derived from dates and nothing in this product writes that
status; `supabase/seed-scenarios.sql` writes it to build the lapsed fixture the
retention loop is demonstrated on. Those are not in conflict once stated
plainly: the transition is legal, the product does not use it, and no rule may
read `expired` as the *definition* of lapsed — dates remain that.

#### Scenario: Reviving a retired membership
- **WHEN** any session changes a `cancelled` or `expired` membership's status **to a different status**
- **THEN** it SHALL be refused and the status SHALL be unchanged

**"To a different status" is not padding.** As first written this scenario said
"changes a `cancelled` or `expired` membership's status", which the self-write
scenario below then permits — the two overlapped on exactly `cancelled →
cancelled` and `expired → expired`. A blind author caught it and read the prose
rather than the scenario, which was the right call and is the reading that
matters in practice: **`app.grant_periods()` writes `status = m.status` on every
grant**, and a desk UPDATE listing `status` beside a note is the commonest write
in the product. A rule that refused a status write rather than a status *change*
would break every renewal.

#### Scenario: Retiring a live membership
- **WHEN** a session cancels or expires an `active` or `frozen` membership
- **THEN** it SHALL be allowed

**`pending → cancelled` is legal here and unreachable for a dateless row**, which
a blind author measured rather than assumed: `memberships_dated_unless_pending_chk`
permits null dates only while a membership is `pending`, so cancelling one that
has never been dated fails the CHECK with `23514` before this rule is consulted.
A sale called off before any money arrived is exactly that row.

That is a collision with a Phase 1 constraint, not a contradiction inside this
requirement — the transition is permitted by the lifecycle and refused by the
shape. It is the same family as OPEN-026's half-dated rows, and it belongs with
OPEN-029's work on creation rather than being fixed in the same breath as this
one.

#### Scenario: Pausing and returning
- **WHEN** a session moves a membership between `active` and `frozen`
- **THEN** it SHALL be allowed in both directions

#### Scenario: Activating on the first payment
- **WHEN** the granting rule activates a `pending` membership
- **THEN** it SHALL be allowed

#### Scenario: Writing a status back unchanged
- **WHEN** a statement sets a status to the value it already holds
- **THEN** it SHALL be allowed

### Requirement: Money paid against a retired membership is refundable, not strandable
WHERE a membership is `cancelled` or `expired`, THE SYSTEM SHALL record and
receipt a payment against it, SHALL NOT extend it, and SHALL leave that payment
refundable in full.

**This replaces a scenario that the requirement above makes unreachable.**
ADR-096 decided that money paid while retired stays on record *because the
membership might be revived and the total would then count it* — "detaching that
money would mean they bought nothing and cannot get it back, which is a worse
answer than the one this rule was written to prevent."

Retirement is now terminal, so that revival never comes. **The money would
strand.** The answer is not to refuse the payment — a manual payment is cash
already in the drawer before any row is written, and refusing it leaves the gym
holding money with nothing to show for it, which is the harm ADR-096 named. The
answer is that the payment is a complete, refundable record: the receipt proves
the cash arrived, and the remedy is to refund it and take it against a live
membership.

**The desk is not expected to discover this.** Nothing in the console offers a
retired membership for renewal; reaching this state needs a direct API call
naming a retired `membershipId`. It is specified because it is reachable, not
because it is a flow.

#### Scenario: Paying against a retired membership
- **WHEN** a payment names a `cancelled` or `expired` membership
- **THEN** it SHALL be recorded and receipted, and the membership SHALL NOT move

#### Scenario: Getting that money back
- **WHEN** a refund is recorded against that payment for its full amount
- **THEN** it SHALL be allowed, because the payment took money and `GL036` bounds it by what was taken

#### Scenario: Taking it against the live membership instead
- **WHEN** a payment for the same amount names the member's live membership
- **THEN** it SHALL extend that membership normally
