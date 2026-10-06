## Purpose

Turning a signed-in `auth.users` row into a Gymloop identity: the custom access-token hook, the claims it stamps, the order it resolves identities in, what an inactive or unlinked user gets, how one human who belongs to several gyms gets a token for exactly one of them, and how a live session loses its privileges when the row behind it changes.

The original hook requirements are expressible as direct calls to `app.custom_access_token_hook(<event>)` returning jsonb or catalogue queries. The v2 invitation requirements below additionally exercise verified sign-in and the command/API boundary.

## V2 batch 1 — secure invitation identity contract

Frozen owner-approved contract: INV-001…028 (v1.1/v1.2/v1.3) and STI-001…018 (v1.1), recorded in `docs/domain-rules.md` and the in-flight member/staff invite proposals. This canonical wording records the contract only: batch Gauntlet, browser/Android acceptance, complete local sweep, CI deployment and schema/type regeneration remain pending evidence. The changes are not archived here.

## Requirements

### Requirement: The hook is reachable by Auth and by nobody else
THE SYSTEM SHALL define the access-token hook in the `app` schema, not in `public`, so it is neither exposed through the Data API nor present in the generated types. `supabase_auth_admin` SHALL hold `usage` on the schema and `execute` on the function; `anon`, `authenticated` and `public` SHALL hold `execute` on it not at all.

#### Scenario: The hook is not on the public API surface
- **WHEN** the schema of the access-token hook function is inspected
- **THEN** it SHALL be `app` and SHALL NOT be `public`

#### Scenario: A signed-in caller cannot execute the hook
- **WHEN** execute privilege on the hook function is inspected for `authenticated` and for `anon`
- **THEN** neither SHALL hold it

#### Scenario: Auth's own role can execute the hook
- **WHEN** execute privilege on the hook function is inspected for `supabase_auth_admin`
- **THEN** it SHALL hold it

### Requirement: A failing hook degrades to a claimless token, never to an outage
A Postgres auth hook fails closed: an exception issues no token at all, for every user of the project at once. THE SYSTEM SHALL therefore remove every Gymloop claim from the copied claims object before resolution and contain the remaining logic in an exception handler that returns that cleaned event, so any unanticipated failure yields a token carrying no Gymloop claims — a session that reads zero rows — rather than a sign-in outage. Reserved Auth claims SHALL remain unchanged.

#### Scenario: An event that is not the documented shape
- **WHEN** the hook is called with a jsonb value that carries no `user_id` key
- **THEN** it SHALL return without raising

#### Scenario: A user id that matches nothing
- **WHEN** the hook is called with a `user_id` that exists in none of the three identity tables
- **THEN** it SHALL return without raising, and the returned claims SHALL carry neither `tenant_id` nor `app_role`

#### Scenario: A null user id
- **WHEN** the hook is called with `user_id` set to JSON null
- **THEN** it SHALL return without raising

### Requirement: The hook returns the whole claims object
Supabase Auth performs no implicit merge and rejects a token missing its required claims. THE SYSTEM SHALL return the event's existing claims with the Gymloop claims added, preserving every claim it did not set, and SHALL NOT alter any reserved claim (`iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`, `email`, `phone`, `is_anonymous`).

#### Scenario: Pre-existing claims survive
- **WHEN** the hook is called with an event whose claims carry `sub`, `aud`, `role` and `session_id`
- **THEN** every one of those claims SHALL be present in the returned claims with its original value

#### Scenario: The Postgres role claim is never rewritten
- **WHEN** the hook is called with an event whose `role` claim is `authenticated`, for a user who resolves to a `super_admin` identity
- **THEN** the returned `role` claim SHALL still be `authenticated`

### Requirement: A claim is absent or well-formed, never empty
THE SYSTEM SHALL omit a claim key entirely when it has no value for it, and SHALL NOT emit an empty string or a JSON null for `tenant_id`, `app_role`, `member_id`, `staff_id` or `impersonation_session_id`.

#### Scenario: An unlinked user's claims
- **WHEN** the hook is called for a user who matches no identity row
- **THEN** the returned claims SHALL contain no `tenant_id` key at all, rather than a `tenant_id` whose value is an empty string or null

#### Scenario: A platform user carries no gym claims
- **WHEN** the hook is called for an active `super_admin` with no live impersonation session
- **THEN** the returned claims SHALL carry `app_role` of `super_admin`, and SHALL contain no `tenant_id`, `member_id` or `staff_id` key

### Requirement: Identity resolves in one fixed order and stops at the first match
THE SYSTEM SHALL resolve a user against `platform_users`, then `staff`, then `members`, in that order, and SHALL stop at the first table in which the user has a row.

#### Scenario: A platform user who is also a gym member
- **WHEN** the hook is called for a user who has an active `platform_users` row and also an active `members` row
- **THEN** the returned `app_role` SHALL be the platform role and the returned claims SHALL carry no `member_id`

#### Scenario: A staff member who is also a member of the same gym
- **WHEN** the hook is called for a user who has an active `staff` row and an active `members` row in the same tenant
- **THEN** the returned claims SHALL carry `staff_id` and SHALL NOT carry `member_id`

#### Scenario: A gym member
- **WHEN** the hook is called for a user whose only identity is an active `members` row
- **THEN** the returned claims SHALL carry `app_role` of `member`, the member's `tenant_id`, and that member's id as `member_id`

### Requirement: An inactive identity gets nothing, and does not fall through
IF the user has rows in a table but none of them is active, THEN THE SYSTEM SHALL stop resolving and SHALL return a token carrying no Gymloop claims. It SHALL NOT continue to the next table in the order. An identity is active when its `is_active` is true, for `platform_users` and `staff`; a member is active when its `status` is neither `cancelled` nor `blocked` and its erasure timestamp is null — a `paused` or `expired` member signs in normally, because renewing is what they sign in to do.

#### Scenario: A deactivated super admin
- **WHEN** the hook is called for a user whose `platform_users` row has `is_active` false
- **THEN** the returned claims SHALL carry no `app_role` and no `tenant_id`

#### Scenario: A deactivated super admin who is also an active member
- **WHEN** the hook is called for a user whose `platform_users` row is inactive and who also has an active `members` row
- **THEN** the returned claims SHALL carry no `app_role`, no `tenant_id` and no `member_id` — the inactive platform identity SHALL NOT degrade into a member identity

#### Scenario: A deactivated staff member
- **WHEN** the hook is called for a user whose only `staff` row has `is_active` false
- **THEN** the returned claims SHALL carry no `app_role` and no `tenant_id`

#### Scenario: A lapsed member can still sign in
- **WHEN** the hook is called for a user whose only `members` row has status `expired`, and again for one whose status is `paused`
- **THEN** both SHALL return `app_role` of `member` with that member's `tenant_id` and `member_id`

#### Scenario: A cancelled or blocked member cannot
- **WHEN** the hook is called for a user whose only `members` row has status `cancelled`, and again for one whose status is `blocked`
- **THEN** both SHALL return claims carrying no `app_role`, no `tenant_id` and no `member_id`

#### Scenario: An erased member cannot
- **WHEN** the hook is called for a user whose only `members` row has status `active` and a non-null erasure timestamp
- **THEN** the returned claims SHALL carry no `app_role`, no `tenant_id` and no `member_id`

### Requirement: One token is for exactly one gym, and the requested gym is validated
WHERE a user has identity rows in more than one tenant, THE SYSTEM SHALL issue a token for exactly one of them. It SHALL read the requested tenant from the user's `raw_app_meta_data` key `active_tenant_id`, SHALL honour it only if the user has an active row in that tenant, and SHALL otherwise fall back to the user's active row with the earliest `created_at`, ties broken by the lower `id`, without raising.

#### Scenario: A valid requested tenant
- **WHEN** the hook is called for a user with active staff rows in two gyms, whose `active_tenant_id` names the second
- **THEN** the returned `tenant_id` SHALL be the second gym and `staff_id` SHALL be that gym's staff row

#### Scenario: A requested tenant the user does not belong to
- **WHEN** the hook is called for a user with active staff rows in two gyms, whose `active_tenant_id` names a third gym
- **THEN** the returned `tenant_id` SHALL be one of the two gyms the user belongs to, and SHALL NOT be the third

#### Scenario: A requested tenant where the user's row has been deactivated
- **WHEN** the hook is called for a user with an active staff row in gym A and an inactive one in gym B, whose `active_tenant_id` names gym B
- **THEN** the returned `tenant_id` SHALL be gym A

#### Scenario: No requested tenant at all
- **WHEN** the hook is called twice for a user with active staff rows in two gyms and no `active_tenant_id`
- **THEN** both calls SHALL return the same `tenant_id`, being the row with the earliest creation time

### Requirement: Deactivation and role change revoke the sessions already issued
A claim is a copy of a row taken when the token was issued, so changing the row changes nothing about a token already held. THE SYSTEM SHALL delete the user's authentication sessions when an identity row stops being active — `is_active` going from true to false, or a member's status becoming `cancelled` or `blocked`, or a member's erasure timestamp being set — and when an identity row's `role` changes, so that the access token in hand is the last one that user receives. `members` carries no role column and so writes no role-change audit row.

#### Scenario: Deactivating a staff member
- **WHEN** a staff row with a linked user is updated to `is_active` false
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Changing a staff member's role
- **WHEN** a staff row's `role` is changed from `front_desk` to `gym_manager`
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Deactivating a platform user
- **WHEN** a `platform_users` row is updated to `is_active` false
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Cancelling a member
- **WHEN** a `members` row with a linked user is updated to status `cancelled`
- **THEN** that user SHALL have no rows in the authentication session table afterwards

#### Scenario: Pausing a member revokes nothing
- **WHEN** a `members` row with a linked user is updated from status `active` to `paused`
- **THEN** that user's authentication sessions SHALL be unchanged

#### Scenario: An unrelated update revokes nothing
- **WHEN** a staff row's `full_name` is updated and neither `is_active` nor `role` changes
- **THEN** that user's authentication sessions SHALL be unchanged

### Requirement: A role change writes an audit row
INT-003 names a role change as an audited event. THE SYSTEM SHALL write an `audit_log` row when an identity row's `role` changes, recording the actor, the record type and id, and the before and after values, without the caller having to ask.

#### Scenario: A role change is audited
- **WHEN** a staff row's `role` is changed
- **THEN** an `audit_log` row SHALL exist for that record naming the previous and the new role

### Requirement: A deactivation writes an audit row
THE SYSTEM SHALL write an `audit_log` row when an identity is deactivated, recording the actor, the record and the before and after state. INT-003 names a role change and not a deactivation; this is a deliberate addition, because switching off a compromised platform account is the most security-relevant write in the schema and a log that records a promotion but not a revocation is inconsistent in the direction that matters.

#### Scenario: Deactivating a staff member is audited
- **WHEN** a staff row is updated to `is_active` false
- **THEN** an `audit_log` row SHALL exist for that record whose action names a deactivation and whose before and after record the change

#### Scenario: Cancelling a member is audited
- **WHEN** a `members` row is updated to status `cancelled`
- **THEN** an `audit_log` row SHALL exist for that member recording the status change

### Requirement: The first platform account is created once and never again
THE SYSTEM SHALL provide a way to create the very first `super_admin` from an already-registered authentication user, and that mechanism SHALL be inert once any `platform_users` row exists — so it cannot become a general-purpose way to create platform accounts.

#### Scenario: Bootstrapping into an empty platform roster
- **WHEN** the bootstrap runs against a database with no `platform_users` rows, naming a registered user
- **THEN** exactly one `platform_users` row SHALL exist afterwards, with role `super_admin`

#### Scenario: Bootstrapping again
- **WHEN** the bootstrap runs a second time naming a different registered user
- **THEN** no new `platform_users` row SHALL be created

### Requirement: The access token's lifetime is chosen, not defaulted
THE SYSTEM SHALL set the access-token lifetime explicitly in `supabase/config.toml`, and the value SHALL be shorter than the platform default of one hour, because the interval between a revocation and a token's expiry is the window in which a revoked privilege still works.

#### Scenario: The lifetime is configured
- **WHEN** `supabase/config.toml` is inspected for the access-token expiry setting
- **THEN** it SHALL be present and SHALL be less than 3600

### Requirement: Invitations bind a verified Google account to one existing record

INV-001…013 and STI-001…007 SHALL issue server-generated, hash-only, 48-hour invitations to one eligible on-file member or manager/front-desk/trainer staff row. Resend atomically supersedes the previous pending invitation; revoke closes a pending invitation, including an expired one. Pending→redeemed/revoked/superseded are the only legal invitation state edges; expiry is derived from its timestamp. Raw tokens and hashes SHALL never enter audit events. Linked identifiers remain pseudonymous personal data, despite the absence of contact fields in invite rows.

Redemption SHALL verify the Google identity and exact normalized current on-file email, acquire the shared per-Auth-user lock before row locks, and refuse any existing members/staff/platform_users binding, active or inactive. It SHALL never create a gym picker or second identity binding. Staff redemption SHALL revalidate the issuing active owner and preserve the row's owner-selected role and other profile fields. Unknown, expired, replaced, revoked and ineligible invites SHALL share generic unavailable copy; pre-auth peek SHALL expose only gym name, plus staff role for staff invites. Refusals SHALL return outcome rows so audit evidence commits; the accepted v1.1 refusal-count asymmetry remains explicit.

#### Scenario: Invitation targets an eligible on-file record
- **WHEN** an invitation is issued to one eligible on-file member or manager/front-desk/trainer staff row
- **THEN** it SHALL be server-generated, hash-only and valid for 48 hours

### Requirement: Only authorized commands change app identity

INV-014…018 and STI-008…012 SHALL deny direct authenticated binding writes. Member invitation management requires real front office; member unlink requires owner/manager. Staff creation/invitation/unlink requires the real owner and SHALL exclude owner-role targets. Platform read access SHALL not grant gym-side command authority, and impersonation SHALL not issue, redeem, unlink or read the privileged access model. Reasoned unlink SHALL clear the binding and revoke the former user's sessions; a redeemed token SHALL not reopen after unlink. The privileged operator recovery path and platform owner-link path remain available under their existing contracts.

#### Scenario: Member invitation management requires front office
- **WHEN** member invitation management is requested
- **THEN** real front office SHALL be required

### Requirement: Browser linking carries no token into OAuth

INV-020/021/027 and STI-013/014 SHALL use their audience's HttpOnly, SameSite=Lax, short-lived cookie for the OAuth round trip, with Secure on HTTPS and no token in callback/OAuth parameters. Invite sign-in SHALL request `prompt: 'select_account'`; account switching SHALL preserve the invite. Member cookie wins if both valid family cookies exist. Accept pages SHALL be noindex/no-referrer, identify the signed-in Google account and show the data-processing notice. Every invite response, refusal and redirect SHALL be no-store.

A successful member cookie redemption SHALL refresh claims once; the bearer client refreshes locally. A successful staff redemption SHALL expire the local session and require fresh Google sign-in, rather than attempting to refresh the revoked session or claiming the workspace is open. Failure/unknown outcome SHALL not fabricate success or clear a retryable invite cookie.

#### Scenario: Invite sign-in requests account selection
- **WHEN** invite sign-in begins
- **THEN** it SHALL request `prompt: 'select_account'`

### Requirement: Console state and history reflect persisted evidence

INV-019/025/026 and STI-015 SHALL show role-authorized dot-plus-word app-access states, with explicit loading/empty/error/preview states and read-only owner staff rows. Real front office SHALL see latest member invite enum status plus sent/expiry absolute IST timestamps inline and a tenant/search/status/pagination-preserving **Not joined yet** filter over unbound members. Expired pending invitations SHALL be labelled expired without adding an enum value. Trainers SHALL receive no invite/access metadata.

Member history SHALL show only that member's tenant-scoped persisted issue/supersede/revoke activity with actor, action and absolute IST time, and refresh after successful resend/revoke. Failed commands SHALL fabricate no history. Missing actors SHALL have an honest fallback; no tokens, hashes, raw audit JSON or refusal identity data SHALL be rendered. Trainers, public invitees and support preview SHALL receive no invite history.

#### Scenario: Expired pending invitations have truthful labels
- **WHEN** a pending invitation has expired
- **THEN** it SHALL be labelled expired without adding an enum value

### Requirement: Operational gates remain explicit

INV-023/024 and STI-016…018 SHALL use fixed actionable refusal/notice copy and the one-year invitation retention policy in `docs/security.md`. Pruning is a policy, not a job built by this batch. Member erasure SHALL immediately invalidate pending member invites. Open Auth signup remains owner-gated; verified deployed WEB_APP_URL, Android App Links signing configuration and legal review are operational prerequisites with their own evidence, not implied by this spec update.

#### Scenario: Member erasure invalidates pending invitations
- **WHEN** member erasure occurs
- **THEN** pending member invites SHALL be invalidated immediately

### Requirement: Front desk reads only the narrow recent-history projection

INV-028 SHALL provide stable postgres-owned `read_member_invite_history(member_id)` with empty search_path and authenticated-only execution. It SHALL revalidate the real owner/manager/front-desk actor before argument/target validation, accept no tenant argument and refuse inactive/incomplete/stale, trainer, member, platform and impersonation identities. Broad audit_log RLS SHALL remain unchanged.

Only this exact tenant/member's persisted issue/supersede/revoke/redeem and member link/unlink events SHALL return event_id, occurred_at, action and actor_name. No refusal event, unknown action, unrelated target, audit JSON, contact field, token/hash, Auth/staff/tenant id SHALL cross this boundary. Actor names SHALL resolve truthfully to a same-tenant staff actor or this member for their own member-attributed link/redemption; unresolved names SHALL be null and render **Name unavailable**, never the viewer's name. Recent history SHALL contain at most 50 events ordered occurred_at descending, event_id descending, with empty and failure distinguished. The UI SHALL use this reader rather than broad audit table queries. Its tenant-leading history index and shared MEMBER_INVITE_HISTORY_LIMIT belong to the frozen pending batch contract; this addition establishes no acceptance evidence.

#### Scenario: History reader validates its actor first
- **WHEN** `read_member_invite_history(member_id)` is called
- **THEN** it SHALL revalidate the real owner/manager/front-desk actor before argument/target validation

### Requirement: Owner-approved native consent and safe invite reopening (acceptance pending)

INV-029 SHALL name the gym and show the shared notice/full privacy link before native Google,
using locally hashed gym-only peek and SecureStore token handoff to the account chooser.
INV-030 SHALL check member replay only through live POST, open Home with fresh claims only for
already_linked_here, and provide viewer-email account recovery retaining the token. Other linked
identities remain refused under D1; web GET/render never mutates a binding. This records the
owner-approved v1.4 contract and does not establish deployed or Android acceptance.
#### Scenario: Native Google sign-in follows the shared notice
- **WHEN** native Google sign-in begins
- **THEN** the gym name, shared notice and full privacy link SHALL be shown before native Google
