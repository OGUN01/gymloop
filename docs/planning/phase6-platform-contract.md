# Phase 6 platform control contract

Normative under ADR-111 for OPS-002/003, ONB-001–005 and NAV-006/008. Read with
the Phase 6 draft, fixed seam, identity, metrics and communications contracts.
Implement after Phase 5 archive and earlier Phase 6 slices, with independent
visible/holdout authors. Metrics owns fleet/readiness; this file consumes it.

## 1. Capability and error boundaries

New platform mutations first require a complete verified platform identity,
app_role=super_admin, auth.uid() matching an active super_admin platform_users
row, and no nonnull tenant/staff/member/impersonation claim. Missing session is 401
not_signed_in; another complete identity is 42501 / 403 not_permitted before
target/key/Auth lookup. Every callable mutating definer repeats that check.
Functions fully qualify names and set search_path=''; revoke PUBLIC/anon EXECUTE,
grant authenticated on the public commands and pure graph/TTL helpers. Private
write helpers have no PUBLIC/anon/authenticated/service_role EXECUTE. No API uses
a service key, trusts raw_user_meta_data or exposes an Auth roster.

Under ADR-111, direct authenticated organization INSERT and changes to its
commercial fields require the named platform commands. Their narrow definers
own the organization write together with its withheld audit/Auth capability;
they are not general table writers. `app.enforce_organization_commercial()` is
an INVOKER trigger: authenticated direct commercial edits are GL049; elevated
callable product writes require current_user=postgres and the complete live
super-admin shape. Authenticated cannot SET ROLE to that owner. Native trusted
subjectless owner/service history and Auth referential cleanup may bypass claim
authority checks, never structural graph/identity constraints. Public definers
reject missing claims before any write, so an empty JWT cannot enter the trusted
history path. Metadata fixes command owners; no caller-settable GUC is trusted.
Existing RLS/read grants stay intact. Direct owner UPDATE retains name/timezone/
currency with nonblank name, recognized pg_timezone_names entry and INR. Validate
profile fields only on creation/change: an unchanged malformed legacy timezone
does not prevent suspension/closure. id, gym_code and created_at are immutable;
status, tier, trial_ends_at and activated_at are commercial. A same-value write
does not count as changing a commercial field. The preview guard still refuses
all authenticated product mutations except its existing own-session end.

| SQLSTATE / API code | HTTP | Contract |
|---|---:|---|
| GL049 / platform_commercial_write_required | 403 | Direct authenticated commercial creation/change or protected staff Auth association bypass. |
| GL050 / invalid_organization_transition | 422 | A changing status edge outside the canonical graph. |
| GL051 / organization_not_ready | 409 | Activation readiness fails; return the shared ordered missingSettings array. |
| GL068 / idempotency_conflict | 409 | Reuse of a recorded key for different command/actor/request facts. Reuse the communications error, not a new alias. |
| 40001 / stale_platform_state | 409 | Compare-and-set expected state differs; refetch and obtain a new deliberate request/expected state. |
| P0002 / not_found | 404 | Target absent, wrong tenant or not the required target kind, with identical public wording. |
| 22023 / invalid_platform_input | 422 | Invalid normalized input, unsupported timezone/currency or a missing required reason. |
| 22023 / owner_account_unavailable | 422 | Exact email finds zero/multiple users, any platform identity, or an account already bound to a different staff row in this gym. |
| 23505 / preview_already_open | 409 | Only the named existing actor/open-session unique constraint; never every unique violation. |

Named 22023 messages distinguish their two API codes. Native checks, FK/type
errors and privilege refusals retain their own timing. Commands check role →
target/input shape → recorded replay → expected state → semantic no-op →
changing-edge/reason/readiness requirements. Key mismatch beats stale state.
The organization invariant checks immutable/profile shape, commercial authority,
graph, then state timestamp/readiness facts. Failed audit or Auth mutation aborts
the whole command. 40P01/40001 never becomes success; transport retries may
reuse the original key, but a real stale-state refusal needs refetch/review.

## 2. Minimal retry evidence and vocabulary

Add only nullable `audit_log.request_key uuid` and `request_facts jsonb`, with
CHECK that both are null or both nonnull and request_facts is an object.
Add unique `(tenant_id,request_key)` WHERE request_key IS NOT NULL. Keyed
platform events always have a nonnull tenant. Existing audit writers, including
audit_money_change, leave both new fields null and retain every existing field,
summary and event-count behavior. No generic command ledger or mutable last-
request fields are added to organizations. Audit privileges stay append-only.

Private writers construct request_facts exactly as `{command,actorUserId,request,
result}`; command is the SQL command name without its public schema prefix,
request the normalized object below, result the exact public success data.
Trim outer whitespace; email additionally lowercases; no other case/Unicode
rewrite. Keys/ids compare as UUIDs. Keys are shared across platform commands
within the gym: compare command, actor and every request field, including nulls,
before replaying original stored results. Later gym/owner/Auth/tier edits do
not change that evidence.
No arbitrary 23505 becomes replay: re-read the exact tenant/key evidence and
prove equality. Audit failure rolls back the effect whose result it records.

Status/tier/owner-link semantic no-ops append no row, touch no timestamp or Auth
metadata/session and leave their key unreserved. This exception to durable key
replay is inert only while expected state and target still hold; after an
intervening change, old expected state refuses with 40001. Successful changing
commands remain replayable after later changes.

Create canonical `public.plan_tier` enum basic/growth/pro and convert nullable
organizations.tier to it. ADR-115 explicitly authorizes one guarded correction
first: demo tenant 00000001-0000-4000-8000-000000000001, gym_code IRNBX1,
tier=tier_2 becomes growth, with a subjectless organization.tier_migrated audit
record (before/after tier, reason from ADR-115) and the matching seed update.
Any other invalid legacy text makes migration fail for explicit repair, never
silently maps to a tier. Reuse the existing `PlanTier` symbol,
making its alias the generated enum through a type-only @gymloop/db workspace
dependency; constrain PLAN_TIER_PRICES_PAISE to its exact key set. Shared remains
platform-free. Values remain basic=149900, growth=299900, pro=499900
integer paise/month, INR. No independently authored tier list, member cap,
invoice, payment, subscription or automatic charge is introduced.

## 3. Onboarding and derived facts

`public.onboard_gym(p_request_key uuid,p_name text,p_timezone text,p_currency
text,p_preset gym_preset,p_branch_name text,p_owner_name text,p_owner_email text)
RETURNS jsonb` is VOLATILE DEFINER. All parameters are required; owner_email
may be SQL NULL (blank normalizes to null). Names are trimmed/nonempty; timezone
must be a pg_timezone_names entry; currency must be INR. Preset is required.
The new organization id equals p_request_key. Serialize that UUID before
lookup/creation. An existing organization with no matching onboard evidence
is GL068. The request is exactly `{name,timezone,currency,preset,branchName,
ownerName,ownerEmail}`. Mutable later profile/settings values are never used
for replay comparison.

Atomically create organization, one organization_settings row, one default
branch, one zero-credit messaging_wallets row and one active gym_owner staff
row. Owner branch_id is null (all branches), user_id null, with supplied name
and optional contact email; no Auth account is created or linked implicitly.
The explicit owner-link command follows onboarding. A zero wallet creates no
zero ledger entry. Failure of any child or audit leaves no onboarding rows.

Organization starts pending_approval, then enters trial in this transaction.
created_at is server-stamped once; activated_at and tier remain null. Derive
trial_ends_at as the start of the gym-local date TRIAL_DAYS after the local date
of that created_at. Do calendar-day addition before timezone conversion; never
add a fixed number of UTC hours. Trial creation does not require owner access.
Trial expiry is not automatic activation or an invented status transition.

Generate gym_code from uppercase first GYM_CODE_LENGTH hex characters of a new
gen_random_uuid(), retaining the existing six-character format and uniqueness.
On collision retry only the exact gym-code unique constraint, not any child
or command-key failure. The gym code is an identifier, never a secret.
`app.platform_onboarding_defaults() RETURNS jsonb` is private IMMUTABLE INVOKER,
owner-executable, generated from registered TS constants. Its exact payload is
`{trialDays,gymCodeLength,presets}`; presets maps each generated gym_preset to
`{noShowThresholdDays,streakRule,weeklyGoal,maxFreezeDays,pauseApproverRole}`.
Add GYM_PRESET_SETTINGS to constants.ts; reuse TRIAL_DAYS/GYM_CODE_LENGTH.
The generated SQL payload has a drift check; future changes use a generated
forward migration rather than a copied list or hand-edited database types.

| Preset | Threshold | Streak | Goal | Freeze/year | Approver |
|---|---:|---|---:|---:|---|
| neighbourhood_gym | 7 | visit_streak | 3 | 30 | gym_owner |
| premium_studio | 5 | weekly_goal | 3 | 30 | gym_owner |
| functional_box | 3 | weekly_goal | 4 | 14 | gym_owner |

Copy once; other settings use existing defaults. Later preset edits do not
overwrite gym settings. The owner can approve another staff member's pause;
GL021 forbids self-approval. No manager or branch active flag is invented.

OrganizationResult is exactly `{tenantId,name,gymCode,status,tier,timezone,
currency,trialEndsAt,activatedAt}`. Onboard result is exactly
`{organization:OrganizationResult,branchId,ownerStaffId,ownerAccessPending:true}`.
Public money/count values use decimal integer strings, dates/timestamps use
strings, booleans stay booleans and missing facts are null.

## 4. Commercial lifecycle and activation

`app.organization_transition_allowed(p_from organization_status,p_to
organization_status) RETURNS boolean` is IMMUTABLE INVOKER. Same-state is
allowed. Changing edges are pending_approval→trial|active, trial→active|closed,
active→suspended|closed, suspended→active|closed. Closed is terminal. The enum
and this graph are unchanged; no trial→suspended or closed→active convenience.

`public.set_gym_status(p_tenant_id uuid,p_expected_status organization_status,
p_status organization_status,p_reason text,p_request_key uuid) RETURNS jsonb`
is VOLATILE DEFINER. Lock the organization, then resolve keyed replay/CAS.
Request is `{expectedStatus,status,reason}`; optional blank reason becomes null.
A changing move to suspended/closed, or suspended→active, requires a nonblank
reason. A no-op has no reason requirement. Result is exactly
`{organization:OrganizationResult,readiness}` using metrics' Readiness object.

Every changing move to active requires app.gym_readiness(tenant).settingsComplete
in the same SQL statement snapshot that conditionally writes the new status.
The decision, invariant and returned readiness use that coherent statement
snapshot, whether the shared STABLE helper is evaluated in the command, trigger
or both; evaluation count is not the requirement. No second formula or newer
snapshot may contradict the accepted decision. Missing settings keys/order and
providerReadiness are exactly metrics' contract. Blank logo/GSTIN/address and
unconfigured providers do not block activation. This decision uses a snapshot;
it does not freeze later legitimate settings/staff changes for an active gym.

On first entry to active, activated_at is server-stamped; later suspension,
closure and reactivation preserve that original instant. On pending→trial,
derive trial_ends_at from the immutable organization created_at/local onboarding
date as above. No product command extends a trial, backdates activation or
changes either timestamp independently. Other status transitions retain them.
Direct authenticated SQL cannot bypass these rules by naming server fields.
An invoker database invariant enforces graph/immutable timestamps under trusted
writes too; trusted history creation may supply honest historical facts.

`public.set_gym_tier(p_tenant_id uuid,p_expected_tier plan_tier,p_tier plan_tier,
p_request_key uuid) RETURNS jsonb` is VOLATILE DEFINER. Both tier arguments
may be SQL NULL; compare with IS DISTINCT FROM. Lock the gym, perform exact
replay/CAS/no-op, then change tier only. Request is `{expectedTier,tier}`;
result is exactly `{tenantId,tier}`. An unset tier displays “Unassigned”. Tier
does not activate a gym, extend a trial, enforce a member cap or charge money.

## 5. Owner Auth linking and ordinary staff boundaries

`public.link_gym_owner(p_tenant_id uuid,p_owner_staff_id uuid,p_expected_user_id
uuid,p_owner_email text,p_request_key uuid) RETURNS jsonb` is VOLATILE DEFINER.
Lock organization then the designated active same-gym gym_owner staff row;
expected_user_id may be null. Request is `{ownerStaffId,expectedUserId,ownerEmail}`.
After replay/CAS, privately resolve lower(trim(email)) against auth.users by
exact equality. Refuse zero/multiple matches, any platform_users identity
(including inactive support/admin), or another staff row in this gym already
bound to that user. Do not return candidate ids, emails or partial matches.
Lock the selected Auth row before committing its association.

If the exact selected user is already linked and CAS holds, return the inert
no-op without rewriting stored contact data or preferred-tenant metadata.
Otherwise set only staff.user_id and staff.email to that user/normalized email;
preserve role, name, branch and active state. Atomically set that Auth user's
raw_app_meta_data.active_tenant_id to the target gym, preserving every other
protected metadata key. Never write raw_user_meta_data or a caller-supplied
claim object. Revoke incoming and outgoing users' auth.sessions on replacement,
or incoming sessions on first link; do not alter outgoing preferred metadata.
Result is exactly `{tenantId,ownerStaffId,userId,ownerAccessPending:false}`.
Show “Sign in again after this gym is activated”; send no invitation or email.

`app.enforce_staff_auth_binding()` is an INVOKER trigger rejecting authenticated INSERT with
nonnull user_id and any UPDATE changing user_id. It also rejects changing into
or out of gym_owner on an already linked staff row; otherwise downgrade→rebind→
promote would bypass platform owner linking. Refusal is GL049 before private
Auth lookup. Ordinary owner CRUD retains unlinked profile creation, contact/
name/branch/is_active edits, and non-owner role changes with user_id unchanged;
existing role/deactivation revocation and audit triggers remain authoritative.
Staff id/tenant are immutable. An unlinked owner profile may be created normally
then linked by the platform command; no general employee linking/invite path is
added. Its callable owner-link path requires current_user=postgres plus the live
super-admin shape and rechecks OLD/NEW owner role, active state, fixed tenant/id
and permitted Auth target. Native trusted subjectless history/Auth cleanup keeps
the explicit §1 exception; no public RPC can acquire it by omitting claims.

Add a private uncallable AFTER staff.user_id-change revocation trigger deleting
auth.sessions for the distinct old/new nonnull user ids. Preserve trusted Auth
ON DELETE SET NULL and seed/history contexts; do not invent a claim actor for
them. The trigger handles revocation only, so owner-link writes one keyed audit
event rather than duplicate link events. The old role/deactivation trigger is
unchanged and still fires on its own distinct effects.

## 6. Hook eligibility and support preview

Land NAV-006/008 together. The hook permits ordinary gym claims only for active
gyms or trials with nonnull trial_ends_at > statement_timestamp(). Equality is
expired. Preserve cleaned Gymloop keys, reserved Auth claims, platform→staff→
member precedence and requested-tenant then created_at/id ordering. A matching
inactive/ineligible identity class stops fallthrough; an eligible alternative
gym in that same class may be selected. Pending/suspended/closed/expired or
malformed trial gyms give no fresh real staff/member claim. Super-admin preview
is an explicit exception and may target every existing gym status.

A private uncallable AFTER organization.status-change trigger deletes sessions
for distinct linked staff/member users when entering suspended or closed.
Its input is the changed organization, never caller-listed user ids. Preserve
other users' sessions. Reactivation and tier/profile edits do not revoke.
Expiry alone blocks the next hook call without promising a timer that deletes
all sessions at the exact expiry instant. Existing access tokens retain at
most the configured fifteen-minute residual; do not rewrite reserved exp.

`public.start_gym_preview(p_tenant_id uuid,p_reason text,p_request_key uuid)
RETURNS jsonb` is VOLATILE INVOKER with the platform guard. Use request_key as
the immutable impersonation_sessions.id; bind actor, tenant and trimmed nonblank
reason. Lock the acting platform row; exact id replay returns the original
`{sessionId,tenantId,startedAt,expiresAt}` without extending or reopening it.
Conflicting facts are GL068. Any different open session, including expired,
is preview_already_open. Start/expiry are database-derived, using the existing
two-hour maximum. Centralize that existing SQL duration in private IMMUTABLE
`app.impersonation_max_ttl() RETURNS interval`, shared by CHECK and start; no
second JS duration. Retain app.impersonation_is_live and immutable/end triggers.

POST /api/platform/impersonations refreshes Auth after success and routes by the
actual refreshed identity, never assumes an expired/ended replay grants preview.
The existing POST /api/impersonation/end remains claim-only, with no body target.
Refresh failure clears local Auth and asks for sign-in. The red banner shows
the target and hard expiry; there are no mutation controls while previewing.

An expired but unended session blocks the unique open key after the hook has
returned to platform claims. Add the explicit recovery command
`public.end_expired_gym_preview(p_session_id uuid) RETURNS jsonb`, VOLATILE
INVOKER, super-admin only, locking its own session and refusing another actor
as P0002 or an unexpired open row with 22023 invalid_platform_input. It sets
ended_at from the database clock through existing RLS/immutable/audit rules;
already-ended is inert. Result is `{sessionId,endedAt}`. Its POST route is
`/api/platform/impersonations/[id]/end`. This is an explicit “End expired preview”
action; start never silently creates an end event. No new policy is required.

## 7. Exact audit and product routes

Each changing platform command appends one keyed event with §2's evidence.
Actor is verified auth.uid()/super_admin, tenant/record id the gym (owner link
records staff id), impersonation null, occurred_at server clock.

| Action; record_type | before → after; reason |
|---|---|
| organization.onboarded; organization | NULL → `{organization:OrganizationResult,branch_id,owner_staff_id,preset,wallet_balance_credits:"0"}`; NULL. |
| organization.status_changed; organization | `{status,trial_ends_at,activated_at}` → same keys with accepted values; normalized reason or NULL. |
| organization.tier_changed; organization | `{tier}` → `{tier}`; NULL. |
| staff.owner_linked; staff | `{user_id,email}` → `{user_id,email,preferred_tenant_id}`; NULL. |

Private audit writers are not callable audit-insertion APIs. Commercial commands
own their event; ordinary direct profile changes do not fabricate a commercial
event. Impersonation start/end retain existing audit_impersonation_session
events/fields exactly, with their new request metadata null; session id itself
provides their retry identity. Unchanged replay/no-op appends nothing.

All platform POSTs use the existing envelopes/form 303 behavior: `/api/platform/
gyms` takes the onboarding request plus requestKey; `/gyms/[id]/status` takes
`{expectedStatus,status,reason,requestKey}`; `/tier` takes `{expectedTier,tier,
requestKey}`; `/owner-link` takes `{ownerStaffId,expectedUserId,ownerEmail,
requestKey}`. Preview start takes `{tenantId,reason,requestKey}` and expired-end
takes no body facts. Support sees fleet/detail/readiness and no controls.
Wallet controls remain exclusively the communications contract's adjustment.

Independent tests cover child atomicity, code/key races, every graph pair,
one-snapshot readiness, immutable clocks, direct commercial/link bypass,
old-result replay, no-op CAS, revocation/metadata preservation, owner lookup,
eligible-gym fallback and preview refresh/recovery. Regenerate types after CI;
preserve money/audit regressions and archive after the clickable journey passes.
