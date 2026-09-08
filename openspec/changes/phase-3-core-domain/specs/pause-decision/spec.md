## Purpose

Who may approve a member's freeze, and on whose authority. A pause suspends what a gym is owed, so approving one is a commercial decision — and the rule governing it was, until the Phase 3 critic, enforced only in a TypeScript comparison that a direct `supabase-js` write went straight round.

This spec exists because the rule had no spec. The role matrix says who may *write* `membership_pauses`; it does not say who may *approve* one, and those are different questions.

## Requirements

### Requirement: The gym decides which role approves a freeze
THE SYSTEM SHALL permit an approval only by a staff member whose role equals the gym's configured `organization_settings.pause_approver_role`, and SHALL enforce this where every writer meets it rather than in a caller.

#### Scenario: The configured role approves
- **WHEN** a staff member whose role is the gym's configured approver role approves a pending pause
- **THEN** the approval SHALL succeed

#### Scenario: Another staff role approves
- **WHEN** a staff member of the gym holding any other role approves a pending pause
- **THEN** the approval SHALL be rejected

#### Scenario: The rule cannot be gone around
- **WHEN** a front-desk session writes the approval columns directly rather than through the endpoint
- **THEN** it SHALL be rejected on the same terms — a rule enforced by a caller is a rule with a way round it

### Requirement: The approver is whoever is acting, and cannot be someone else
THE SYSTEM SHALL require the recorded approver to be the acting staff member, so an approval cannot be attributed to a colleague.

#### Scenario: Attributing an approval to another staff member
- **WHEN** a staff member approves a pause recording a different staff member as the approver
- **THEN** the write SHALL be rejected

### Requirement: The person who asked is not the person who grants
THE SYSTEM SHALL reject an approval by the staff member who requested the pause, whatever their role. A freeze is money the gym does not collect, and a single person deciding it alone is the shape every expense-approval control exists to prevent.

#### Scenario: Approving one's own request
- **WHEN** the staff member who requested a pause approves it
- **THEN** the write SHALL be rejected

#### Scenario: A different staff member of the right role approves it
- **WHEN** a different staff member holding the configured role approves that same pause
- **THEN** the approval SHALL succeed

### Requirement: Rejecting a pause is not the decision approving one is
THE SYSTEM SHALL govern only the transition **into** approved. A rejection needs no configured role and no second person: refusing a freeze costs the gym nothing and denying it is not the commercial act granting it is.

#### Scenario: Any staff member may reject
- **WHEN** a staff member who may write pauses rejects a pending pause
- **THEN** the rejection SHALL succeed regardless of their role

#### Scenario: The requester may reject their own request
- **WHEN** the staff member who requested a pause rejects it
- **THEN** the rejection SHALL succeed

### Requirement: The person who asked is stamped from the session, then never changes
THE SYSTEM SHALL require `requested_by_staff_id` to be the acting staff member when a pause is inserted, and SHALL refuse an update that alters it afterwards.

**Immutability alone is not enough, and the reason is the whole of ADR-068 applied one statement earlier.** Making the column unchangeable on UPDATE puts it outside the writer's reach *after* it exists — but INSERT is where it enters, and there it was still whatever the caller typed. So a manager inserted a pause naming a colleague as requester (or naming nobody, the column being nullable) and approved it in the next statement: the comparison passed, the freeze was granted, and the record named an employee who never asked. Two statements instead of one, by one person, with no rule crossed.

The test is the one `assisted_by_staff_id` already gets on `attendance` — a supplied value that is not the acting staff member is refused rather than corrected. A caller who is not inside row security is exempt, as everywhere else here.

**Without this, the requirement above is not a control at all.** "The approver must differ from the requester" only constrains anybody if at least one side of that comparison is a recorded fact rather than the writer's own input. `membership_pauses` grants `update` to `authenticated` and its write policy is `is_front_office()` for every command, so a single statement can set `requested_by_staff_id` to a colleague and `approved_by_staff_id` to oneself — the comparison passes, the freeze is granted, and the permanent record names an employee who never asked for it. A separation-of-duties rule that the writer can satisfy by rewriting the other half is decoration.

#### Scenario: Reassigning the request in the approving statement
- **WHEN** a staff member updates a pause they requested, setting `requested_by_staff_id` to a colleague and approving it in the same statement
- **THEN** the write SHALL be refused

#### Scenario: Reassigning the request on its own
- **WHEN** any staff member updates only `requested_by_staff_id`
- **THEN** the write SHALL be refused

#### Scenario: Inserting a pause in a colleague's name
- **WHEN** a staff member inserts a pause naming a different staff member as the requester
- **THEN** the insert SHALL be refused

#### Scenario: Inserting a pause in nobody's name
- **WHEN** a staff member inserts a pause with `requested_by_staff_id` left null
- **THEN** the insert SHALL be refused — a freeze nobody is recorded as having asked for is the same hole with the name left blank

### Requirement: A pause cannot be created already decided
WHEN a session subject to row security inserts a pause carrying `approved_at` **or `rejected_at`**, THE SYSTEM SHALL refuse it, whatever role that session holds.

*Rejected as well as approved, because "a pause arrives pending or it does not arrive" is the rule and half of it is not the rule.* A born-rejected row moves no money, so it looks harmless — but it lands already decided, the settled-row guard then freezes it, and a front-office session has permanently recorded a refusal against a request nobody made, naming any colleague as the requester, with no way to undo it. A pause is requested and then decided; a row that arrives at the destination was never governed on the way.

*"Subject to row security" and not "whoever is asking":* the seed and the demo scenario data legitimately create an already-approved pause — there is one covering today, and Phase 4's no-show scan is built to find it — and they run as `postgres`, which bypasses row security by design. The same carve-out as the requirement below, for the same reason.

**On an insert there is no recorded fact to check anything against** — `requested_by_staff_id` and `approved_by_staff_id` are both the caller's input in the same statement, so every rule above is vacuous by construction there. The answer is not to evaluate those rules more carefully at insert time; it is that this state has no legitimate way to arise. A gym that wants an immediately-approved freeze writes two statements, and the second one is governed.

#### Scenario: A pause born approved
- **WHEN** any session inserts a pause with `approved_at` set, naming a colleague as the requester and itself as the approver
- **THEN** the insert SHALL be refused

#### Scenario: A pause born rejected
- **WHEN** a session inserts a pause with `rejected_at` set
- **THEN** the insert SHALL be refused

### Requirement: Only a session with a staff identity may decide
THE SYSTEM SHALL refuse to record or alter a decision from a session that carries no `staff_id` claim. A guard that returns early when it cannot identify the caller is reading "I do not know who you are" as "you are trusted", and the set of callers it actually lets through is larger than the set it was written for.

Concretely, the callers it was written for are `postgres` and `service_role` — the seed and the pgTAP fixtures — which bypass row security by design and are not `authenticated` sessions at all. The callers it *also* lets through are a super admin's token and, worse, **an impersonating token**: `app.custom_access_token_hook` mints `app_role = 'gym_owner'` and a `tenant_id` for a live impersonation session but deliberately mints no `staff_id`, so such a session passes `is_front_office()` and carries no staff identity. It would meet no rule here — not the configured role, not the two-person rule, not even "a decided pause stays decided". `docs/security.md` says an impersonating token has the gym's reach and not more; this is more, and impersonation is meant to be the *most* constrained path, not the least.

#### Scenario: An impersonating platform admin approves a freeze
- **WHEN** a session holding a live impersonation token approves a pause
- **THEN** the write SHALL be refused

#### Scenario: An impersonating platform admin rewrites a decision
- **WHEN** that session updates the decision columns of a pause already approved
- **THEN** the write SHALL be refused

#### Scenario: The seed and the fixtures are unaffected
- **WHEN** a trusted context that is not an `authenticated` session writes a pause
- **THEN** it SHALL succeed — row security does not apply to it in the first place, and imposing this rule there would break every fixture without protecting anything a policy is not already protecting

### Requirement: A decided pause stays decided, and so does what it decided
Once a pause carries a decision, THE SYSTEM SHALL refuse any change to **any column of that row** other than `updated_at`. A second approver cannot overwrite the first, and nobody can move the freeze out from under the approval.

**Every column, not a list of them.** The first version of this named seven columns — the three decision columns plus the membership and the dates and the reason — and a blind critic immediately found the two it did not name: `id`, so a decided pause could be renumbered and become unfindable at the id anything else was holding, and `created_at`, the row's only record of when it was asked for. A list of frozen columns is a thing that goes stale the day somebody adds a column, and it was already stale on the day it was written. **The safe default is that a new column is frozen**, which an allowlist of what may still move gives and a denylist of what may not does not.

**An authorisation is an authorisation of something.** A guard that freezes only `approved_at`, `approved_by_staff_id` and `rejected_at` leaves an approved pause repointable at another member's membership and its `ends_on` extendable — so the freeze the gym is bound by need not be the freeze anybody approved, and the record still names the approver as having granted it. Moving what an authorisation covers forges it as surely as rewriting who gave it, and it does so without touching a single column such a guard is watching. *(Found by the blind holdout author, against a guard that had just been written to close a different version of this same rule.)*

`tenant_id` is deliberately not among the frozen columns: the write policy's `with check` already refuses moving a row to another gym, and a rule here that raised first would answer ahead of the policy.

#### Scenario: Approving an already-approved pause
- **WHEN** a staff member approves a pause that has already been approved
- **THEN** nothing SHALL change and the original approver SHALL still be recorded

#### Scenario: Repointing an approved pause at another membership
- **WHEN** a staff member updates an approved pause's `membership_id`
- **THEN** the write SHALL be refused

#### Scenario: Extending an approved freeze
- **WHEN** a staff member updates an approved pause's `starts_on` or `ends_on`
- **THEN** the write SHALL be refused

#### Scenario: Rewriting why an approved freeze was granted
- **WHEN** a staff member updates an approved pause's `reason`
- **THEN** the write SHALL be refused — the reason is what the approver read before granting it

#### Scenario: Renumbering a decided pause
- **WHEN** a staff member updates a decided pause's `id`
- **THEN** the write SHALL be refused — the row would become unfindable at the id anything else was holding

#### Scenario: Backdating a decided pause
- **WHEN** a staff member updates a decided pause's `created_at`
- **THEN** the write SHALL be refused

### Requirement: The statement that decides may decide and nothing else
WHEN a pause moves from pending to decided, THE SYSTEM SHALL permit that statement to write only the decision columns, and SHALL refuse it if it also changes what is being decided.

**A guard that reads `old` to ask "was this already decided?" is blind to the statement doing the deciding.** Everything above governs the row before and after; nothing governed the transition itself. So an approver approved and moved `ends_on` in one statement — a seven-day freeze granted as a two-year one — and every rule held: the approver was the configured role, was not the requester, and the row was pending when the statement began. The record then reads as a properly authorised freeze that nobody requested and nobody approved in that form.

This is the third appearance of one shape in this capability: **the rule was attached to the states, and the transition between them is a place a rule can be left out of.** The approver's authority is to grant the request that was made, not to alter it and grant that instead — a granter who can rewrite what they are granting makes the requester's half of the two-person rule decorative.

#### Scenario: Approving and extending in one statement
- **WHEN** the configured approver sets `approved_at` and `ends_on` in the same statement
- **THEN** the write SHALL be refused

#### Scenario: Rejecting and amending in one statement
- **WHEN** a staff member sets `rejected_at` and changes any other column in the same statement
- **THEN** the write SHALL be refused

#### Scenario: Approving on its own
- **WHEN** the configured approver sets only the decision columns
- **THEN** the approval SHALL succeed — this is the transition working, and the case a careless fix breaks
