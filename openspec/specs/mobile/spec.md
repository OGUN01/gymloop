## Purpose

Provide one real native Gymloop application for the member and front-desk
audiences, preserving the same verified identity, tenant, attendance, money and
presentation contracts as the web application. Android is the accepted v1
runtime under ADR-134; physical iOS acceptance is deferred without being
represented as complete.

## Requirements

### Requirement: Native requests use one verified identity boundary
NAV-001–008 SHALL accept exactly one Supabase credential transport: the
existing verified cookies or `Authorization: Bearer <user access token>`.
Missing, malformed, unverifiable, service-role/unclassified and mixed
cookie-plus-bearer requests SHALL fail closed before body parsing. A verified
bearer SHALL produce the same `classifyIdentity` result and RLS-scoped client as
a verified cookie; decoded claims alone are never authority.

#### Scenario: A mobile session calls an authenticated route
- **WHEN** the app sends one valid user bearer credential
- **THEN** the route verifies its signature, subject, role and complete claim set
- **AND** data access remains scoped by the same RLS identity as the web session

#### Scenario: Credential transports are ambiguous or untrusted
- **WHEN** a request has both cookie and bearer credentials, or its bearer cannot be classified as a verified user
- **THEN** it is refused before the request body is parsed
- **AND** no service-role or caller-decoded claim is accepted as user authority

### Requirement: Member QR check-in derives its subject from the session
ATT-001–008 SHALL let a verified member present a gate token without choosing a
tenant or member. The claim-validating database command SHALL derive both from
the canonical member identity, validate the gate proof and active membership,
and record the attendance atomically. Members SHALL NOT select QR-session rows
or insert attendance directly, and the staff-assisted path remains unchanged.

#### Scenario: A verified member scans a live gate
- **WHEN** the verified member submits a valid gate token
- **THEN** the server derives that member and tenant from the authenticated claim
- **AND** one attendance row is recorded without exposing the QR-session row

#### Scenario: A body attempts to choose another identity
- **WHEN** a member request attempts to select another member or gym
- **THEN** the request is refused
- **AND** no attendance row is written outside the verified association

### Requirement: Offline replay is identity-scoped and exactly once
An offline command SHALL retain its original UUID event key, scanned gate token
and `offlineRecordedAt`. The server SHALL stamp `replayed_at`, accept the claimed
occurrence only inside the QR session's creation/expiry interval and not in the
future, and use that validated instant for membership liveness. Queue ownership
is exactly `(userId, tenantId, memberId)`; an account or association change
SHALL NOT replay another identity's command.

#### Scenario: A member scans while disconnected
- **WHEN** the device cannot receive server confirmation after a valid local scan
- **THEN** the app says that the visit is saved on this device and awaiting confirmation
- **AND** it preserves the original event id, token, occurrence and exact identity scope

#### Scenario: The originating member reconnects
- **WHEN** the same verified identity regains connectivity
- **THEN** the queue replays the original command and removes it only after server confirmation
- **AND** replaying that event again returns the same success without a second visit

#### Scenario: A different member receives the queued event
- **WHEN** the authenticated `(userId, tenantId, memberId)` does not exactly match the queue owner
- **THEN** the event is refused or retained without replay
- **AND** event-key reuse across members is a conflict, never another member's success

### Requirement: Native session continuity grants no offline server authority
The device SHALL store the refreshable user session and last verified identity
in Expo SecureStore using the public Supabase URL and anonymous key only. A
transient network failure at cold start MAY retain authenticated local UI for
the last verified identity, but it SHALL grant no new server capability.
Sign-out SHALL clear the session, cached identity and queued commands.

#### Scenario: An authenticated device restarts offline
- **WHEN** remote refresh is temporarily unavailable but a matching last verified identity exists
- **THEN** the app may render that identity's truthful cached/offline state
- **AND** protected writes remain queued until the server verifies the session again

#### Scenario: The user signs out
- **WHEN** sign-out completes
- **THEN** the native session, cached identity and that device queue are removed
- **AND** the next user cannot inherit them

### Requirement: Mobile reads expose only authorized presentation facts
The member snapshot SHALL read organization presentation settings through the
claim-scoped `public.read_member_portal_settings()` command. It returns exactly
`city`, `state`, `weekly_goal_default`, `week_start_day` and
`streak_rule_type`; no settings row, GSTIN, financial configuration or tenant
identifier crosses that boundary. Mobile money is always a canonical decimal
string in integer paise with explicit currency, never a JavaScript number.

#### Scenario: A member opens their gym and money history
- **WHEN** the member snapshot loads
- **THEN** membership, receipt, add-on and presentation facts belong only to the verified association
- **AND** every bigint money value crosses the application boundary as a decimal string

### Requirement: The native app is complete for both v1 audiences
UX7-001/003–014 SHALL provide four labelled member tabs (Home, Activity,
My gym, You) and four front-desk tabs (Check-in, Members, Follow-ups, More),
complete System/Light/Dark appearance, accessible English-only controls, and
truthful loading, empty, error, permission, offline and conflict states. Member
flows cover QR scan/queue/status, attendance/streak, membership/receipts,
messages/consent and add-on history. Desk flows cover search, assisted check-in,
follow-up, lead entry, appearance and sign-out. Production screens SHALL use
real authorized reads and SHALL NOT substitute mock data or decorative delivery
claims.

#### Scenario: A verified member or front-desk user enters the app
- **WHEN** their complete role identity is loaded
- **THEN** only that audience's four labelled destinations and authorized data are shown
- **AND** Light, Dark, enlarged text and reduced-motion settings preserve every action

#### Scenario: The app cannot complete an operation
- **WHEN** data is loading, empty, refused, stale, offline, uncertain or conflicting
- **THEN** the screen shows the exact actionable state
- **AND** it does not represent local acceptance as server confirmation

### Requirement: V1 has one verified gym association
Under ADR-134, a member SHALL use one verified gym association in v1. The app
SHALL expose no public-code join or switch control because a code is not
authorization. Secure invitation-based multi-gym linking is post-v1 and does
not block the Android Phase 7 boundary.

#### Scenario: A member sees their gym code
- **WHEN** the verified member opens My gym
- **THEN** the current gym identity and code may be displayed as context
- **AND** the code cannot be used to grant or switch authorization

## Acceptance record

- Android ARM64 development/debug build and physical Android 13 member/front-
  desk authentication passed for all eight tabs, Light/Dark, sign-out, device-
  maximum text and Remove animations:
  `docs/evidence/2026-09-20-phase7-android-device.md`.
- A physical airplane-mode QR scan queued one event, survived a cold restart,
  replayed once after reconnect and remained single after another restart:
  `docs/evidence/screens/2026-09-20-phase7-android-offline-queued.png`,
  `docs/evidence/screens/2026-09-20-phase7-android-offline-restart.png` and
  `docs/evidence/screens/2026-09-20-phase7-android-replay-confirmed.png`.
- Fresh security/money and original-resolution visual critics returned GO; CI
  passed the independent visible/holdout contracts before archive.
- EAS simulator build `22ede637-bdad-428b-b091-ceda282e7fa5` proves the SDK 57
  native iOS project compiles on macOS. It is not physical iOS runtime evidence:
  `docs/evidence/2026-09-20-phase7-ios-build.md`.
- Physical iOS runtime and airplane/reconnect acceptance remain deferred by the
  owner under ADR-134 and are not claimed complete.
