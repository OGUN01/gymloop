## Purpose

Give every verified Gymloop identity a usable home and enforce read-only support preview consistently across screens, API calls and direct database writes.

## ADDED Requirements

### Requirement: Complete identities and one home selection
WHEN verified claims are classified THE SYSTEM SHALL apply NAV-001 and NAV-002
and the complete-claim table in docs/planning/phase6-identity-contract.md through
the fixed pure classifyIdentity and identityHome interfaces. UUID identifiers
SHALL be valid strings; missing or contradictory Gymloop facts SHALL classify
as unlinked. Reserved non-Gymloop claims SHALL not affect classification.

#### Scenario: Role home
- **WHEN** claims form a complete real staff, member, platform or impersonation identity
- **THEN** home SHALL respectively be /console, /member/add-ons, /platform or /console

#### Scenario: Contradictory or incomplete claims
- **WHEN** the subject or required identity UUID is invalid, the role unknown, or a forbidden Gymloop key is nonnull
- **THEN** classification SHALL be unlinked and home SHALL be /not-linked

### Requirement: Verified API identity and role gates
WHEN staffSession, staffForm or staffFormParsed accepts a caller THE SYSTEM SHALL
require complete verified staff claims and preserve the existing envelopes,
adding userId and generated role through every wrapper. Missing complete staff
identity SHALL return 401 not_signed_in; an explicit allowedRoles refusal SHALL
return 403 not_permitted before any write. memberSession and platformSession
SHALL use the fixed same-envelope signatures and expose only their own identity.

#### Scenario: Staff and role refusal
- **WHEN** a complete trainer calls a staff helper without a role restriction
- **THEN** it SHALL return the complete staff session, while an owner/manager-only restriction SHALL refuse it before mutation

#### Scenario: Support read access
- **WHEN** complete platform support claims call platformSession
- **THEN** reads SHALL receive the platform identity and requireAdmin SHALL refuse before mutation

### Requirement: Navigation uses verified identity consistently
WHEN signing in or visiting signed-in sign-in, root, not-linked or an audience
layout THE SYSTEM SHALL use the shared classifier and home selector. A missing
verified session SHALL reach sign-in; an identity entering another audience's
layout SHALL reach its own home. Member and platform homes SHALL have truthful
empty/error states and authenticated reads protected by existing RLS.

#### Scenario: Member catalogue and history
- **WHEN** a member visits /member/add-ons
- **THEN** the page SHALL show active catalogue offers and only that member's orders, including inactive-product history, label incomplete legacy offers unavailable and invent no terms or qualifications

#### Scenario: Fleet read home
- **WHEN** a platform user visits /platform
- **THEN** the page SHALL show real gym name, code, status, tier and local trial expiry and support SHALL receive no mutation controls

### Requirement: Read-only preview and safe ending
WHILE impersonating THE SYSTEM SHALL show a persistent red banner naming the
target gym and expiry with End preview. A private invoker BEFORE guard SHALL
refuse direct authenticated mutations carrying an impersonation claim on every
authenticated-writable public table, preserving read policies and the existing
tightly constrained own-session end exception. Metadata coverage SHALL be
asserted. No staff/member id SHALL be inferred for a preview.

#### Scenario: Direct mutation refusal
- **WHEN** an authenticated preview token attempts a product table mutation
- **THEN** the statement SHALL be refused with insufficient_privilege (42501), with no change to existing read permissions

#### Scenario: End and refresh
- **WHEN** POST /api/impersonation/end receives complete verified preview claims
- **THEN** it SHALL derive only the claim session id, update through existing own-session RLS, refresh Auth and return 303 /platform; a refresh failure SHALL clear the local session and return to sign-in

#### Scenario: Non-preview caller
- **WHEN** another identity calls the end route
- **THEN** it SHALL be refused before any session update, regardless of body-supplied target id

### Requirement: Fresh hook claims preserve Auth facts
WHEN the access-token hook resolves an identity or takes a fallback THE SYSTEM
SHALL remove app_role, tenant_id, staff_id, member_id and impersonation_session_id
before returning the newly resolved shape. It SHALL preserve reserved Auth
claims, existing privileges and search path, platform/staff/member precedence,
requested/default tenant selection and current organization eligibility semantics.
Resolution failure SHALL return cleaned claimless identity without a global
sign-in outage.

#### Scenario: Refresh changes identity
- **WHEN** incoming claims contain stale keys for a different previous identity
- **THEN** the returned claims SHALL contain only the currently resolved Gymloop shape and unchanged reserved Auth facts

#### Scenario: Resolution fallback
- **WHEN** no row resolves or resolution raises an exception
- **THEN** the hook SHALL return the cleaned claims rather than preserve stale Gymloop authorization

### Requirement: Exact large money read display
WHEN formatting money THE SYSTEM SHALL extend the existing rupeesFromPaise to
number|string exactly as the fixed money addendum requires. Safe integer number
results SHALL remain unchanged; unsafe/noninteger numbers SHALL raise RangeError.
Canonical decimal strings matching ^(?:0|-?[1-9][0-9]*)$ SHALL format to exactly
two decimal places without precision loss; other strings SHALL raise TypeError.
Member reads SHALL cast stored bigint price/totals to text in PostgREST projections.

#### Scenario: Large and negative values
- **WHEN** a canonical amount exceeds JavaScript safe integer range or represents negative fractional rupees
- **THEN** the output SHALL retain every digit and the exact sign with two decimal places, reusing existing paise constants

#### Scenario: Existing parser unchanged
- **WHEN** callers use paiseFromRupees or pass existing safe-integer numbers to rupeesFromPaise
- **THEN** their existing valid behavior SHALL remain unchanged
