## Purpose

Noticing that a member has stopped coming, before they decide they have left. Phase 3 records attendance; nothing yet reads the absence of it. This is the half of the loop the product is sold on.

Every failure here is **silent**. A case that is never opened looks exactly like a member who is fine. A paused member wrongly flagged looks exactly like a real churn risk until a human phones them about it. A scan that runs twice at a timezone boundary opens nothing visibly wrong. That is why the scan gets the full blind arrangement (ADR-059).

## The interface, because it is a contract and not a detail

THE SYSTEM SHALL expose the scan as a database function:

```
app.run_no_show_scan(p_tenant_id uuid, p_today date default null) returns integer
```

returning the number of cases it opened. `p_today` exists so a test can put the gym at a chosen calendar day; **when it is null the function SHALL derive the day from the gym's own configured timezone**, and that is the path production takes.

Two reasons this is in the spec rather than left to the implementer. First, a blind test author cannot write a single assertion without knowing what to call — naming the entry point is what makes the arrangement possible at all. Second, the scan belongs in the database for the same reason every other rule in this product does: `no_show_cases` grants `insert` to `authenticated`, so a scan living only in an Edge Function is a scan with a way round it, and the one-open-case-per-member guarantee would be a property of the job rather than of the table.

The Edge Function on cron is then a caller: it selects the gyms and invokes this per gym. It holds no rule of its own, and nothing about the correctness of a scan depends on it running.

## Requirements

### Requirement: The scan runs once per calendar day, in each gym's own timezone
THE SYSTEM SHALL evaluate a gym's members against that gym's own configured timezone, not UTC and not the server's (NSH-001, MNY-004). A gym in a different timezone SHALL see its own day boundary.

#### Scenario: Two gyms whose day boundaries differ
- **WHEN** two gyms in different timezones are scanned at the same instant, and the instant falls on different calendar days for each
- **THEN** each gym's evaluation SHALL use its own calendar day

#### Scenario: Running twice in one gym-day
- **WHEN** the scan runs a second time on the same gym-day
- **THEN** it SHALL open no additional cases and change no existing one

### Requirement: Absence is measured from the last visit, and never having visited counts
THE SYSTEM SHALL compare the days since a member's most recent attendance against the gym's `no_show_threshold_days`. A member who has **never** attended SHALL be measured from the date their membership began, not excluded for want of a row to measure from.

#### Scenario: One day short of the threshold
- **WHEN** a member's last visit is one day fewer than the threshold
- **THEN** no case SHALL be opened

#### Scenario: One day past the threshold
- **WHEN** a member's last visit is one day more than the threshold
- **THEN** a case SHALL be opened

#### Scenario: Absence exactly equal to the threshold
- **WHEN** a member's last visit is exactly `no_show_threshold_days` ago
- **THEN** no case SHALL be opened. NSH-003 says a case opens when an absence **crosses** the threshold, and a member who has been away exactly the number of days the gym allows has reached it, not crossed it. *(The blind holdout author flagged this as genuinely unstated and declined to assert either way, which was the right call — an implementer and a test author guessing separately is how a boundary ends up meaning two things.)*

#### Scenario: A member who has never visited
- **WHEN** a member with an active membership older than the threshold has no attendance at all
- **THEN** a case SHALL be opened

#### Scenario: The threshold is the gym's own
- **WHEN** two gyms configure different thresholds
- **THEN** each gym's members SHALL be evaluated against that gym's value, never a constant

### Requirement: A member who cannot attend is not a churn risk
THE SYSTEM SHALL exclude from evaluation any member whose membership is not live, and any member with an **approved pause covering the scan date** (NSH-002).

**Paused is derived, not a status** (ADR-064): nothing sets `memberships.status = 'frozen'`, so the scan SHALL ask `membership_pauses` for `approved_at is not null and rejected_at is null` and the scan date between `starts_on` and `ends_on`. A scan that reads the status column instead will flag every paused member, and the demo data contains one waiting to prove it.

#### Scenario: An approved pause covering today
- **WHEN** a member absent far longer than the threshold has an approved pause covering the scan date
- **THEN** no case SHALL be opened

#### Scenario: A rejected pause is not a pause
- **WHEN** that member's only pause was rejected
- **THEN** a case SHALL be opened

#### Scenario: A pause that has ended
- **WHEN** a member's approved pause ended before the scan date and they have not returned
- **THEN** a case SHALL be opened

#### Scenario: A membership that is not live
- **WHEN** a member's membership is `expired`, `cancelled` or `pending`
- **THEN** no case SHALL be opened — they are not a member who stopped coming, they are a member who stopped

#### Scenario: A membership whose end date has passed
- **WHEN** a member's membership still reads `active` but its `ends_on` is before the scan date
- **THEN** no case SHALL be opened

**Expiry is derived from the date, exactly as paused is derived from the pause** — and for the same reason, which the first version of this spec made for one and not the other. **Nothing in this product ever writes `memberships.status = 'expired'`**: grep the migrations, `apps/` and `packages/` and the label appears only in the enum's own definition. ADR-064 already said why — a status flip needs a scheduler this project does not have.

So a lapsed membership sits at `active` indefinitely, and a scan trusting the column opens a churn case for somebody whose membership ended weeks ago. Because their absence keeps growing, that case rises to the **top** of the red list and stays there: the first person the front desk is told to ring every morning, about a membership that no longer exists. The demo data already contains one — a member whose `ends_on` was 2026-09-05 and whose status still reads `active`.

### Requirement: Exactly one open case per member, however often the scan runs
THE SYSTEM SHALL open exactly one case for a member and SHALL NOT open a second while one is open (NSH-003, NSH-004). This SHALL hold when two scans run concurrently, not merely when they run in sequence.

A partial unique index already enforces one open case per member. **Do not reimplement it in application code**: a read-then-write has the race Phase 3 spent a day removing from check-in, and `app.enforce_check_in()` is the worked example of the alternative.

#### Scenario: The scan runs twice
- **WHEN** the scan runs twice against an unchanged database
- **THEN** the member SHALL have exactly one open case, and its `opened_on` SHALL be unchanged

#### Scenario: Two scans at once
- **WHEN** two scans for the same gym run concurrently
- **THEN** exactly one case per qualifying member SHALL exist afterwards

### Requirement: A case records what it saw when it opened
THE SYSTEM SHALL record, on opening, the date the member last attended, how many days absent they were, and the threshold in force — so a case read months later can be judged against the rule that produced it rather than the rule current at reading.

#### Scenario: The case carries its own evidence
- **WHEN** a case is opened
- **THEN** it SHALL carry `last_attended_on`, `absent_days_at_open` and `threshold_days`

### Requirement: A returning member closes their own case
WHEN a member with an open case checks in, THE SYSTEM SHALL transition that case to `returned` and then `closed`, **preserving its follow-up history rather than deleting it** (NSH-005). The recovery is the product's evidence that the loop worked, and it is destroyed by a delete.

#### Scenario: A member returns
- **WHEN** a member with an open case records attendance
- **THEN** their case SHALL become closed, and every follow-up on it SHALL still exist

#### Scenario: A member with no case returns
- **WHEN** a member with no open case records attendance
- **THEN** nothing SHALL change beyond the attendance row

### Requirement: Two staff cannot contact the same case at once
THE SYSTEM SHALL prevent a second staff member logging a contact against a case another is already contacting (NSH-006) — a member phoned twice in ten minutes by two people is worse than not being phoned.

#### Scenario: Concurrent contact
- **WHEN** two staff log a follow-up on one case at the same instant
- **THEN** exactly one SHALL be recorded and the other SHALL be told why

### Requirement: The contact log is append-only
THE SYSTEM SHALL record a correction to a follow-up as a new entry referencing the original, never as an edit or a delete (NSH-007). `authenticated` already holds `select, insert` and no `update` on `follow_ups`; this requirement is that the product does not work around it.

#### Scenario: Correcting a follow-up
- **WHEN** a staff member corrects an earlier follow-up
- **THEN** a new row SHALL be written naming the one it corrects, and the original SHALL be unchanged
