## Purpose

Recording that a member turned up. The product's core loop starts here — no attendance, no churn signal, no retention. Two ways in: a member scans the gym's QR code, or the front desk checks someone in for them.

The bar is a metro gate: scan to confirmation is the design, not a detail. But the requirement that actually costs something is **exactly-once** — a duplicate attendance row is silent, it corrupts a streak and a churn scan quietly, and nobody notices for weeks. That is why this capability gets the full blind treatment (ADR-059).

Phase 1's schema already enforces some of this and those rules are not restated below: `attendance_front_desk_has_assist_chk` makes a front-desk row impossible without a staff member and a non-empty reason (ATT-005, ATT-006); `attendance_tenant_id_client_event_id_key` makes a client event id unique per tenant; `attendance_assisted_pair_chk` and `attendance_offline_stamp_pair_chk` keep their column pairs honest.

## Requirements

### Requirement: A check-in is recorded only against a valid QR session and a live membership
WHEN a member presents a QR code, THE SYSTEM SHALL verify that the QR session exists, belongs to this gym, has not expired and has not been revoked, and that the member holds a membership in `active` or `frozen` status, **before** recording attendance (ATT-001).

#### Scenario: A valid scan
- **WHEN** a member with an active membership scans a live QR session for their gym
- **THEN** exactly one attendance row SHALL be recorded, with source `qr` and the scanned session's id

#### Scenario: An expired QR session
- **WHEN** the QR session's expiry has passed
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded (ATT-002)

#### Scenario: A revoked QR session
- **WHEN** the QR session has been revoked
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: A QR session belonging to another gym
- **WHEN** a member scans a QR session issued by a different gym
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: A member whose membership has lapsed
- **WHEN** a member whose only membership is `expired` or `cancelled` scans a live session
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

### Requirement: The QR token is never stored, only its hash
THE SYSTEM SHALL store a QR session's token as a hash and SHALL NOT store the token itself, so that a reader of the database cannot mint a scan (ATT-003). A session SHALL carry an expiry, so a screenshot of a previously valid code stops working.

#### Scenario: The token is not recoverable from the row
- **WHEN** a `qr_sessions` row is inspected
- **THEN** it SHALL hold a hash and no column SHALL contain the token in a form that could be presented

### Requirement: A repeated scan inside the gym's window changes nothing
IF a member is scanned again within the gym's configured de-duplication window, THEN THE SYSTEM SHALL reject the duplicate and SHALL leave the original attendance row intact (ATT-004). The window is `organization_settings.checkin_dedupe_seconds` and is read per gym, never hardcoded.

#### Scenario: A second scan inside the window
- **WHEN** a member who checked in thirty seconds ago scans again, and the gym's window is longer than that
- **THEN** no second attendance row SHALL be recorded and the first SHALL be unchanged

#### Scenario: A second scan after the window
- **WHEN** a member scans again after the gym's window has elapsed
- **THEN** a second attendance row SHALL be recorded

#### Scenario: The window is the gym's own
- **WHEN** two gyms configure different windows
- **THEN** each gym's de-duplication SHALL use its own value

### Requirement: Two simultaneous scans produce exactly one attendance row
WHILE two check-ins for the same member arrive concurrently, THE SYSTEM SHALL record exactly one attendance row. A de-duplication implemented as a read followed by a write is not sufficient: both reads can pass before either writes, and the resulting duplicate is silent.

**The guard belongs to the table, not to a caller.** `attendance` grants `insert` to `authenticated` and its write policy admits any front-office session, so **any rule that lives only in a Route Handler or only in an RPC is bypassed by a direct `supabase-js` insert** — which is a supported path in this architecture, not an abuse of it. The guard must therefore be attached to the table itself, where every writer meets it. *(Found by the blind visible-suite author, and it is the same shape as Phase 2's recurring defect: a rule whose correctness is held by a different component than the one being protected.)*

**The two "twice" cases are different and both are correct.** A repeated *scan* is a second attempt that happens to fall inside the window: it is refused, and the person is told they are already checked in. A repeated *submission carrying the same client event id* is the same attempt arriving twice — a network retry, or an offline replay — and it is absorbed silently, because reporting an error would make a client that retries look broken. The distinguishing question is not "is this a duplicate" but "is this a second attempt, or the same attempt again".

#### Scenario: Concurrent scans of the same member
- **WHEN** two check-ins for the same member are submitted at the same instant
- **THEN** exactly one attendance row SHALL exist for that member in that window afterwards

#### Scenario: The same client event submitted twice
- **WHEN** the same check-in is submitted twice carrying the same client event id
- **THEN** exactly one attendance row SHALL exist, and the second submission SHALL NOT be reported as an error to the caller

#### Scenario: One client event id, two members
- **WHEN** a submission carries a client event id already recorded against a **different** member of the same gym
- **THEN** the submission SHALL be refused, and SHALL NOT be answered with the other member's attendance row. The uniqueness the database holds is `(tenant_id, client_event_id)` and says nothing about the member, so "the same attempt arriving twice" cannot be concluded from the id alone. A client that reuses an id across members — a fixed string, a counter reset by a reinstall — otherwise gets the front desk told that the person standing in front of them is already checked in, under their own name, with nothing recorded. *(Found by the blind handler-suite author.)*

### Requirement: A refusal the handler does not recognise is answered as a failure
THE SYSTEM SHALL answer an unrecognised SQLSTATE as a server error, and SHALL NOT let a code that merely resembles a known one produce a success status.

A refusal table keyed by SQLSTATE is looked up by a code that arrives from outside. **Every JavaScript object answers to `constructor`, `toString` and `valueOf`**, so a plain index into that table returns an inherited function for those keys — truthy, with no status on it — and a response built from it carries HTTP 200 while its body says the check-in failed. A caller that reads the status and not the body then records a visit that does not exist. The lookup must therefore ask whether the table *owns* the key.

#### Scenario: A SQLSTATE that is a property of every object
- **WHEN** the database refuses with a code such as `constructor` or `toString`
- **THEN** the response SHALL carry a failure status, never 200

### Requirement: An assisted check-in names the staff member and the reason
WHEN staff record a check-in on a member's behalf, THE SYSTEM SHALL require the acting staff member and a non-empty reason, and SHALL record the source as `front_desk` (ATT-005, ATT-006).

#### Scenario: Assisted check-in with a reason
- **WHEN** front desk checks a member in with a stated reason
- **THEN** an attendance row SHALL be recorded with source `front_desk`, the acting staff member, and that reason

#### Scenario: Assisted check-in with no reason
- **WHEN** front desk submits an assisted check-in with an empty reason
- **THEN** the check-in SHALL be rejected and no attendance row SHALL be recorded

#### Scenario: Assisted check-in with a reason of whitespace
- **WHEN** front desk submits an assisted check-in whose reason is only spaces
- **THEN** the check-in SHALL be rejected — **Phase 1's constraint tests `assist_reason <> ''`, which accepts three spaces**, and a blank line is not a reason for having marked somebody else present. Verified against the live database before this scenario was written: the row inserts today.

#### Scenario: A reason of a tab and a newline
- **WHEN** front desk submits an assisted check-in whose reason is a tab and a newline
- **THEN** the check-in SHALL be rejected. **`btrim()` with no second argument strips spaces only** — measured: `btrim(E'	
') = ''` is false — so the obvious repair of the previous scenario still admits this row. The test is "no non-whitespace character", which a regex expresses totally and a trim does not. *(The blind holdout author found this by testing a tab where the visible suite tested spaces; the fix for the first hole had the second hole in it.)*

#### Scenario: A trainer attempting an assisted check-in
- **WHEN** a caller whose role is `trainer` submits an assisted check-in
- **THEN** it SHALL be rejected — the matrix gives `attendance` a write gate of front office and above

### Requirement: A check-in never crosses a tenant
THE SYSTEM SHALL record attendance only for a member of the acting session's own gym, and SHALL NOT rely on the caller supplying the correct tenant.

#### Scenario: Checking in another gym's member
- **WHEN** a check-in names a member id belonging to a different gym
- **THEN** it SHALL be rejected and no attendance row SHALL be recorded

### Requirement: Check-out is optional and blocks nothing
THE SYSTEM SHALL treat a missing check-out as normal, and no other behaviour SHALL depend on one being present (ATT-008).

#### Scenario: Attendance with no check-out
- **WHEN** an attendance row has no check-out time
- **THEN** it SHALL still count as a visit
