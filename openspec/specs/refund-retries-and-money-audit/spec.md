# Refund retries and financial audit

## Purpose

Make refund retries deterministic and financial changes auditable while preserving tenant isolation and existing money rules.

## Requirements

### Requirement: One refund request has one recorded result
WHEN an authorized gym owner or manager with verified tenant and staff claims
submits a keyed refund THE SYSTEM SHALL atomically insert or return the exact
existing refund through the security-invoker `public.record_refund` RPC.
The normative signature, authorization and exact comparison are REF-001 through
REF-005 and the Database and API convention in the frozen
`docs/planning/refund-contract-detail.md`.

#### Scenario: Equivalent retry
- **WHEN** two serial or concurrent requests use the same gym, UUID key and exact parsed refund facts
- **THEN** both SHALL return the same refund id, only one refund row and creation audit SHALL exist, and replay SHALL perform no update

#### Scenario: Conflicting retry
- **WHEN** the same gym and key are reused with a different payment, amount, currency, kind or reason
- **THEN** the RPC SHALL refuse with GL048 and the form SHALL show idempotency_conflict without changing the recorded result

#### Scenario: Unauthorized or missing staff identity
- **WHEN** a caller lacks the required gym-admin and real staff claims, including impersonated preview
- **THEN** the RPC SHALL refuse with 42501 before any keyed lookup

### Requirement: Refund keys are tenant scoped and immutable
THE SYSTEM SHALL store nullable canonical UUID text in refunds.idempotency_key
with the named partial tenant/key unique index and GL041 edit freeze specified
by REF-003 and REF-004. Historical null keys SHALL not be backfilled or changed.

#### Scenario: Separate intentional refund
- **WHEN** a fresh receipt render submits another valid refund with a new cryptographic UUID key
- **THEN** the request SHALL create a separate refund subject to the existing received-money ceiling

#### Scenario: Invalid form nonce
- **WHEN** the form key is missing, blank or not a UUID
- **THEN** parsing SHALL refuse before a database call

### Requirement: Project-owned money refusals have a stable order
THE SYSTEM SHALL apply payment row refusals in the order GL038, GL042, GL039,
GL034, GL035 and refund row refusals in the order GL041, GL040, GL036, skipping
inapplicable rules. ERR-001 through ERR-003 specify their boundaries; this
promise excludes native PostgreSQL privileges, RLS, constraints and indexes.

#### Scenario: Multiple named rules fail on one row
- **WHEN** one candidate row passes the excluded mechanisms but violates multiple named project-owned rules
- **THEN** the first applicable code in the stated row order SHALL answer

### Requirement: Financial changes write atomic append-only audit events
AFTER each accepted payment or refund INSERT or UPDATE THE SYSTEM SHALL write
exactly one audit_log row in the same transaction, with the exact actions,
actor attribution and financial before/after summaries in AUD-001 and AUD-002
of the frozen contract. No historical backfill SHALL occur.

#### Scenario: Accepted operation
- **WHEN** an insert or update succeeds, including an unchanged-value update
- **THEN** its single corresponding audit event SHALL record the row's tenant and the defined actor and summary

#### Scenario: Refused operation or equivalent replay
- **WHEN** a financial write is refused or rolled back, or the RPC returns an equivalent keyed replay
- **THEN** no additional audit event SHALL remain

#### Scenario: Private audit writer
- **WHEN** anon or authenticated tries to call the elevated audit trigger function directly
- **THEN** execution SHALL be denied while legitimate trigger invocation remains able to write the event
