## Purpose

The screen a gym opens each morning. Not a dashboard — a **work queue**: who has gone quiet, how long for, what was already tried, and one obvious next action. `docs/architecture.md` names Linear as the bar: speed, keyboard-first, density without clutter.

The test of this screen is not what it renders. It is whether a front desk with four minutes before the 6am rush can see who to call. If that takes more than one glance, it has failed regardless of how it looks.

## Requirements

### Requirement: The list shows open cases, most absent first
THE SYSTEM SHALL list the gym's cases that are not closed, ordered so the member gone longest is first, and SHALL show for each: who they are, how to reach them, how many days absent, when they last came, and the case's state.

**Days absent is computed at read time, not read from `absent_days_at_open`.** That column is what the case saw when it opened and is deliberately frozen — it is the evidence the case was judged against the rule in force then. A list that shows it would tell the front desk a member has been gone eight days for as long as the case is open, which is wrong the day after and increasingly wrong after that.

#### Scenario: A gym's own cases
- **WHEN** staff open the red list
- **THEN** only their own gym's cases SHALL appear, and no application-side tenant filter SHALL be written — the policy is what filters

#### Scenario: Ordering
- **WHEN** the list is shown
- **THEN** the member absent longest SHALL be first

#### Scenario: Days absent is current
- **WHEN** a case opened at eight days absent is viewed three days later
- **THEN** the list SHALL show eleven days, not eight

#### Scenario: Days absent counts in the gym's own day
- **WHEN** the list is read at 05:00 in a gym whose timezone is ahead of UTC
- **THEN** the number SHALL be the one the gym would count, not the one UTC would

**Never `current_date`** (ADR-039, stated five lines from the column this reads in the migration that created it): every Supabase connection is UTC, so `current_date` is a UTC date while `opened_on` was stamped by the scan from the gym's own timezone. Subtracting one from the other is off by one for the five and a half hours between midnight IST and 05:30 IST — **every morning, for every gym not in UTC, precisely during the pre-6am window this screen exists for**. A case opened at eight days against a seven-day threshold would display "7 days away": a number below the gym's own threshold, on a case that exists only because the threshold was crossed.

### Requirement: An unusable cursor shows the first page, never a database error
THE SYSTEM SHALL validate every part of a decoded cursor as the type it will be used as, and SHALL answer anything unusable with the first page.

`typeof value === 'number'` is not that check. `JSON.parse` yields `Infinity` for `1e999` and `1e+21` for `1e21`, both of which are numbers and neither of which is an integer PostgREST will accept — they reach the database as `22P02 invalid input syntax for type integer` and the screen renders the message verbatim. The roster escaped this only because both its cursor fields are strings; this is the first numeric cursor, and a type check is not a validity check.

#### Scenario: A cursor carrying a number Postgres cannot read
- **WHEN** a cursor's numeric part decodes to `Infinity`, a value in exponent form, or anything that is not an integer
- **THEN** the first page SHALL be shown and no database message SHALL reach the screen

#### Scenario: A returned member
- **WHEN** a member with an open case checks in and the case closes
- **THEN** they SHALL leave the list, and their case's follow-up history SHALL still exist

### Requirement: The list is bounded
THE SYSTEM SHALL return a bounded page with a documented default and maximum, and SHALL give the caller what it needs to ask for the next page (gate 26), on the same terms as the member roster: keyset, a total sort order, and everything that shaped the page travelling with the cursor.

#### Scenario: More cases than one page
- **WHEN** a gym has more open cases than a page holds
- **THEN** at most the default number SHALL be shown, with a way to ask for the next

### Requirement: One obvious next action per row
THE SYSTEM SHALL offer, on each row, the action a person is about to take: log what happened when they called.

#### Scenario: Logging from the list
- **WHEN** staff record a follow-up from the list
- **THEN** the case SHALL move to `contacted`, or to `follow_up_due` if a next date was given, and the row SHALL show it

#### Scenario: A case someone else is contacting
- **WHEN** two staff log a follow-up on one case at the same instant
- **THEN** one SHALL be told the case is already being contacted, in a sentence rather than an error code

### Requirement: What was already tried is visible without leaving the list
THE SYSTEM SHALL show, per case, the most recent follow-up — when, by whom, on what channel, and its outcome — because "has anyone rung her?" is the question the screen exists to answer and a second call is the failure it exists to prevent.

#### Scenario: A contacted case
- **WHEN** a case has been followed up
- **THEN** the list SHALL show the latest attempt and who made it

#### Scenario: A case nobody has touched
- **WHEN** a case has no follow-ups
- **THEN** the list SHALL say so plainly rather than showing an empty space, which reads as missing data rather than as work to do

### Requirement: The screen works before JavaScript does
THE SYSTEM SHALL render the list and accept a follow-up as a server-rendered page and a native form, on the same terms as the check-in gate.

A front desk on a bad connection in Indore is the user. This is the same decision `MemberSearchPage` already made, and it is here so nobody "improves" the red list into something that needs a bundle to show a phone number.

#### Scenario: No client JavaScript
- **WHEN** the page is rendered with scripting unavailable
- **THEN** the list SHALL be readable and a follow-up SHALL be loggable
