## Purpose

Take an enquiry to a converted member without losing tenant isolation, phone
privacy, stage discipline or exact counts, and never create a duplicate member
for a phone that already belongs to one.

## ADDED Requirements

### Requirement: Enquiry capture carries durable evidence
WHEN front office records an enquiry THE SYSTEM SHALL require a branch, name,
E.164 phone and canonical source, derive the tenant from the claim, and create
the lead at `new`. Creation SHALL stamp the real acting staff id and store the
request key and normalized facts; an exact retry by the same actor SHALL return
the original lead id and current revision without a write, while a reused key
with different facts or actor SHALL fail `GL062`.

#### Scenario: Lost response retry
- **WHEN** the creation committed but its response was lost and the same staff repeat the exact request
- **THEN** the original lead id SHALL return with its current revision and `replayed=true`

#### Scenario: Supplied actor
- **WHEN** an authenticated creation supplies a different acting staff or evidence actor
- **THEN** the request SHALL be refused

### Requirement: The canonical stage graph is enforced on every write
WHEN a lead changes stage THE SYSTEM SHALL allow only `new -> contacted ->
trial_scheduled -> trial_done -> converted` and a move to `lost` from any
nonterminal stage, refuse self-transitions, and keep `converted` and `lost`
terminal. `trial_scheduled` and `trial_done` SHALL require `trial_at`; `lost`
SHALL require a trimmed nonempty reason and every other stage SHALL forbid one;
conversion fields SHALL be null outside `converted`. The database SHALL enforce
the same rules on RPC and direct writes, keep identity, tenant, creation and
conversion evidence immutable, and rotate the database-owned `revision uuid`
only on accepted material changes.

#### Scenario: Forbidden edge
- **WHEN** a write tries to move `new` directly to `trial_done` or to reopen a `lost` lead
- **THEN** the write SHALL fail `GL059` and the row SHALL be unchanged

#### Scenario: CAS conflict
- **WHEN** a mutation supplies an `expectedRevision` that no longer matches the visible lead
- **THEN** the response SHALL be HTTP 409 `stale_lead` with the current revision

### Requirement: Conversion is atomic and never invents a duplicate
WHEN a `trial_done` lead converts with no eligible same-gym member matching the
normalized exact phone THE SYSTEM SHALL create the member and convert the lead
in one transaction using the accepting transaction's gym-local date, and create
nothing else. WHEN an eligible same-gym member already owns that phone THE
SYSTEM SHALL refuse automatic creation with `GL061` and offer only an explicit
link. An unavailable same-phone member SHALL produce a generic conflict with no
member facts, and a cross-gym, wrong-phone or unknown member SHALL never be
revealed, offered or linked.

#### Scenario: Duplicate phone
- **WHEN** create mode finds an eligible member with the same normalized phone in the same gym
- **THEN** no member SHALL be created and the conflict SHALL carry only that same-gym member's id, name, phone and status

#### Scenario: Cross-gym privacy
- **WHEN** another gym's member owns the phone
- **THEN** the outcome SHALL be identical to a no-match create, with no disclosure of the other gym's data

### Requirement: Conversion races resolve to exactly one outcome
WHEN two conversion requests race or one is retried THE SYSTEM SHALL produce
one converted lead and at most one new member. The lead lock and the
`(tenant_id, phone)` unique key SHALL serialize create-create, create-link and
retries; the first successful conversion SHALL be final even for an authorized
direct writer, and a converted lead SHALL never convert or relink again. An
exact retry SHALL replay the original immutable outcome after authorization
and visibility, before revision or stage checks; a changed retry SHALL fail
`GL062`; a lost race SHALL return the stale conflict.

#### Scenario: Concurrent create
- **WHEN** two identical create-mode conversions run concurrently
- **THEN** exactly one member and one converted lead SHALL exist, and the loser SHALL replay exactly or conflict

#### Scenario: Terminal direct write
- **WHEN** an authorized direct writer targets an already converted lead
- **THEN** the write SHALL be refused

### Requirement: The list is one snapshot with exact counts
WHEN front office opens or filters `/leads` THE SYSTEM SHALL read through
`public.list_leads` under RLS in one SQL statement snapshot, support
stage/source/assignee/branch/query filters, and return rows sorted by
`(updated_at desc, id desc)` with a keyset cursor. `totalMatchingCount`,
`pageResultCount`, `filteredStageCounts` and the rows SHALL derive from that
one statement; every displayed count SHALL equal the rows returned by the same
filters, and each count SHALL be a decimal integer string. Only front office
SHALL read or mutate lead data; trainers, members and preview identities SHALL
see none.

#### Scenario: Filtered counts
- **WHEN** a stage filter is applied
- **THEN** the selected stage's bucket SHALL equal the matched population and the other buckets SHALL be zero

#### Scenario: Role refusal
- **WHEN** a trainer, member or impersonating identity attempts any lead read or mutation
- **THEN** the request SHALL be refused without lead facts
