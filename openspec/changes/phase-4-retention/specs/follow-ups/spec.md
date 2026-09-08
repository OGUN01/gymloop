## Purpose

What a human did about a case, recorded so that the next human can pick it up. A case that is opened and never worked is worth nothing; a case worked twice by two people is worse than one worked by nobody, because the member is the one who notices.

Every rule here is about a record that has to stay true months later. The scan's failures are silent; these are not — a double call is embarrassing in public, and a missing note is noticed the moment somebody asks "did anyone ring her?". That is why this half gets one implementer rather than the full blind arrangement (ADR-059), and why the rules that *are* silent — who contacted, and whether the log can be rewritten — are still enforced by the table.

## Requirements

### Requirement: A follow-up records who did it, and it is the acting staff member
THE SYSTEM SHALL record `follow_ups.staff_id` as the staff member holding the session, and SHALL refuse a value naming anybody else.

This is the same rule as `attendance.assisted_by_staff_id` (`GL016`) and `membership_pauses.requested_by_staff_id` (`GL026`), for the same reason and with the same failure mode if it is left to the endpoint: `follow_ups` grants `insert` to `authenticated`, so a rule living only in a Route Handler has a supported way round it. **The three should look alike, because they are one rule about attribution appearing three times.**

#### Scenario: Logging a follow-up
- **WHEN** a staff member logs a follow-up on a case in their gym
- **THEN** it SHALL be recorded against them

#### Scenario: Naming a colleague
- **WHEN** a staff member logs a follow-up naming a different staff member
- **THEN** the write SHALL be refused

#### Scenario: A session with no staff identity
- **WHEN** a session inside row security carrying no `staff_id` claim logs a follow-up
- **THEN** the write SHALL be refused — there is nobody to record, and `null is distinct from null` is false, so the rule SHALL name that case rather than rely on a comparison (ADR-071)

### Requirement: The contact log is append-only
THE SYSTEM SHALL record a correction as a new row naming the one it corrects, never as an edit or a delete (NSH-007). `authenticated` already holds `select, insert` and no `update` or `delete` on `follow_ups`; this requirement is that the product does not work around it and that a correction is traceable to what it corrects.

#### Scenario: Correcting a follow-up
- **WHEN** a staff member corrects an earlier follow-up
- **THEN** a new row SHALL be written carrying `corrects_follow_up_id`, and the original SHALL be unchanged

#### Scenario: Correcting a follow-up on another case
- **WHEN** the row named by `corrects_follow_up_id` belongs to a different case
- **THEN** the write SHALL be refused — a correction that points at another case's entry is not a correction, and it would make either case's history read wrongly

#### Scenario: Editing the log
- **WHEN** any signed-in caller attempts to update or delete a `follow_ups` row
- **THEN** it SHALL be refused for want of privilege

### Requirement: Two staff cannot contact one case at the same instant
WHILE one staff member is logging a follow-up against a case, THE SYSTEM SHALL prevent a second logging one concurrently (NSH-006), and SHALL tell the second why.

**A read-then-write is not sufficient and the reason is Phase 3's, verbatim:** both reads can pass before either writes. `app.enforce_check_in()` is the worked example — an advisory lock on the contested key, taken before the read that decides.

The window is what makes this a rule rather than a nicety: a member phoned twice in ten minutes by two people is the failure the red list exists to prevent, and it is exactly what happens when two staff open the same morning's list.

#### Scenario: Two follow-ups at once
- **WHEN** two staff log a follow-up on one case at the same instant
- **THEN** exactly one SHALL be recorded and the other SHALL be told the case is already being contacted

#### Scenario: Two follow-ups in sequence
- **WHEN** a staff member logs a follow-up on a case that was contacted an hour ago
- **THEN** it SHALL succeed — the rule is about concurrency, not about a case being contacted only once

### Requirement: A case's status follows its contact history
WHEN a follow-up is recorded, THE SYSTEM SHALL move the case to `contacted`, and to `follow_up_due` when the follow-up names a `next_follow_up_at`.

The status is derived from what happened, not set by the caller: a caller who could write the status directly could mark a case contacted without contacting anybody, which is the one thing the red list must never show.

#### Scenario: A follow-up with no next action
- **WHEN** a follow-up is logged with no `next_follow_up_at`
- **THEN** the case SHALL be `contacted`

#### Scenario: A follow-up with a next action
- **WHEN** a follow-up is logged naming a `next_follow_up_at`
- **THEN** the case SHALL be `follow_up_due` and SHALL carry that instant

#### Scenario: A closed case
- **WHEN** a follow-up is logged against a case that is already `closed`
- **THEN** it SHALL be refused — the member came back, and the case is a finished record

#### Scenario: A correction does not re-decide the schedule
- **WHEN** a follow-up carrying `corrects_follow_up_id` is recorded
- **THEN** the case's status and `next_follow_up_at` SHALL be left as they were

**A correction corrects the record; it does not make a new decision about the member.** This was unasked in the first version and the answer it fell into is the dangerous one: staff log "will return — ring Friday", notice a minute later that the outcome was wrong, and file a correction, which is the *only* way to fix anything on an append-only log. Deriving status from the correction blanks `next_follow_up_at`, drops the case out of `no_show_cases_tenant_id_next_follow_up_at_due_idx` — the index built for "which follow-ups are due" — and nobody rings on Friday.

The failure is silent, it is caused by staff doing exactly the right thing, and it is the outcome this whole phase exists to prevent.

### Requirement: A case can be assigned, and assignment is not a decision about the member
THE SYSTEM SHALL allow a case to be assigned to a staff member of the same gym, and SHALL refuse assignment to anybody else.

#### Scenario: Assigning to a colleague
- **WHEN** a staff member assigns a case to another staff member of their gym
- **THEN** it SHALL succeed — unlike an approval, assignment is not an authority a person exercises over their own request

#### Scenario: Assigning outside the gym
- **WHEN** a case is assigned to a staff member of another gym
- **THEN** it SHALL be refused
