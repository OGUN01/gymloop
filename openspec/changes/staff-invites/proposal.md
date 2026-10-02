# Staff invites and self-linking (STI-001…STI-018)

Feature F17 of `docs/planning/v2-feature-map.md`, phase V2-A2 of `docs/planning/v2-campaign-goal.md`,
**batched with INV into one migration push by owner decision (2026-10-02)** so a single DB run and a
single type regeneration cover both. Rigor: full blind arrangement (ADR-059) — identity and claim
contract. Depends on the frozen contract in `openspec/changes/member-invites/proposal.md` (read it
first; this file only states the staff deltas). Where this file says "as INV", the INV text applies with
`member` → `staff`.

## What it is

An owner invites a manager, front-desk or trainer: the owner creates the staff row (name, email, role,
optional branch) and an invite in one action, shares the link/QR, and the person opens it, signs in with
Google, and links themselves to that row. The role is the owner's choice and lives on the staff row; the
invitee cannot change it. After linking, existing sessions of the invitee are revoked by the existing
staff-binding trigger, so the person signs in once more and the access-token hook mints the staff claims.
Owners are never created or linked this way (only `/platform` links gym owners — the audited path stays).

D1 applies unchanged: one Google account is one identity in the whole system; an account already
bound as member, staff or platform user is refused. Quality bar: `docs/design/v2/inv-bar.md` (same
criteria, staff wording); the same bar decisions as INV apply (exact email match, 48 h expiry, gym and
role shown pre-auth, never the person's name).

Out (recorded): mobile redemption (staff link on web, then sign into the desk app with the same Google
account), automated delivery, staff roster editing beyond invite/unlink, owner invites.

## Fixed names

### Database (migration `20261002110000_staff_invites.sql`, applied after INV's `20261002100000`)

| Object | Name / signature |
|---|---|
| enum | `public.staff_invite_status` = `pending`, `redeemed`, `revoked`, `superseded` |
| table | `public.staff_invites` — as `member_invites` with `staff_id` for `member_id`; composite FKs `(tenant_id, staff_id) → staff(tenant_id, id)` and `(tenant_id, issued_by_staff_id) → staff(tenant_id, id)`; global unique `staff_invites_token_hash_key (token_hash)`; partial unique `staff_invites_one_pending_key (tenant_id, staff_id) where status = 'pending'`; checks `staff_invites_token_hash_format_chk`, `staff_invites_expiry_chk`, `staff_invites_closed_state_chk`; RLS read policy: `gym_owner` only, own tenant; `authenticated` select only; the standard touch/preview triggers |
| indexes | `(tenant_id, staff_id, issued_at desc)`, `(tenant_id, issued_at)`, `audit_log (actor_user_id, occurred_at) where action = 'staff_invite.redeem_refused'` |
| audit helper | `app.staff_invite_audit(...)` — same signature as INV's helper; allowlist exactly: `staff.invited`, `staff_invite.issued`, `staff_invite.superseded`, `staff_invite.revoked`, `staff_invite.redeemed`, `staff_invite.redeem_refused`, `staff.linked`, `staff.unlinked` |
| RPC: create + invite | `public.invite_staff_member(p_full_name text, p_email text, p_phone text, p_role public.app_role, p_branch_id uuid, p_token_hash text) returns table (staff_id uuid, invite_id uuid, expires_at timestamptz)` — gym owner only; inserts the `staff` row (`user_id` null, `is_active` true) and its first invite atomically; writes `staff.invited` and `staff_invite.issued` |
| RPC: issue / resend | `public.issue_staff_invite(p_staff_id uuid, p_token_hash text) returns table (invite_id uuid, expires_at timestamptz, superseded_invite_id uuid)` |
| RPC: revoke | `public.revoke_staff_invite(p_invite_id uuid) returns uuid` |
| RPC: redeem | `public.redeem_staff_invite(p_token_hash text) returns table (outcome text, gym_name text, staff_role public.app_role)` — refusals are rows; `staff_role` null unless `linked`/`already_linked_here` |
| RPC: peek | `public.peek_staff_invite(p_token_hash text) returns table (gym_name text, staff_role public.app_role)` — `anon` and `authenticated` |
| RPC: unlink | `public.unlink_staff_identity(p_staff_id uuid, p_reason text) returns void` |
| RPC: read | `public.read_staff_app_access(p_staff_id uuid) returns table (state text, invite_id uuid, issued_at timestamptz, expires_at timestamptz, linked_at timestamptz)` — same five states |
| actor | all owner-only RPCs call INV's `app.member_invite_actor(array['gym_owner'])` |
| trigger amendment | `app.enforce_staff_auth_binding()` (GL049) gains exactly two admitted shapes and nothing else: **link** — `current_user = 'postgres'`, transaction-local setting `app.staff_binding_command` equals `'link:' || new.user_id::text`, `old.user_id is null`, `new.user_id is not null`, `old.role`/`new.role` in (`gym_manager`,`front_desk`,`trainer`), `old.is_active` and `new.is_active`; **unlink** — `current_user = 'postgres'`, setting equals `'unlink:' || old.user_id::text`, `new.user_id is null`, `old.user_id is not null`, role in the same three, no role/active/tenant change. Both skip `require_platform_super_admin()` and the owner-link-only second block. Every other shape, every other caller and the owner path behave exactly as before (GL049); `staff_auth_binding_session_revoke` is untouched, so unlinking and linking both delete the user's `auth.sessions` |
| SQLSTATEs | the INV codes keep their meanings for staff: `GL075` not invitable (inactive staff, role `gym_owner`, or gym not eligible), `GL076` email missing/implausible, `GL077` already linked, `GL078` rate limited, `GL079` not pending, `GL080` not linked, `42501`, `22023`; new: `GL081` staff email already used in this gym (case-insensitive trimmed, any staff row), `GL082` role not invitable (`p_role` not in manager/front_desk/trainer) |
| limits (`STAFF_INVITE_LIMITS`) | ttl 48 h; 30 issues per tenant per rolling hour; 5 issues per staff row per rolling 24 h; redeem refusal throttle is **shared** with INV: 10 refused redemptions per Auth user per rolling 15 min counted across `member_invite.redeem_refused` and `staff_invite.redeem_refused` (INV's redeem function is not changed; the staff function counts both actions and writes its own) |

Redeem (`redeem_staff_invite`) is INV-007 with `staff` for `member`, and: advisory lock first —
`pg_advisory_xact_lock(hashtextextended('identity-bind:' || auth.uid()::text, 0))`, the same key INV uses —
then the staff row lock, then the invite row lock; (a) bindable = `is_active`, role in the three, `user_id`
null, gym eligible, **and the issuing staff row (`issued_by_staff_id`) is still an active `gym_owner` of
the tenant** (revalidated at redemption); the binding is written with
`set_config('app.staff_binding_command', 'link:' || auth.uid()::text, true)` immediately before the
`update staff set user_id`, and the setting is reset to `''` right after. Check order and outcomes are
INV's (`invite_unavailable`, `identity_unverified`, `email_mismatch`, `account_already_linked`,
`rate_limited`, replay `already_linked_here`). The identity rule (PROV-006a), email rule and D1 count are
byte-for-byte INV's. Unlink writes `unlink:<uid>`.

### Shared (`packages/shared/src/api/staff-invites.ts`, re-exported)

- `STAFF_INVITE_ROLES = ['gym_manager','front_desk','trainer'] as const`; `STAFF_INVITE_ROLE_LABELS = { gym_manager: 'manager', front_desk: 'front desk', trainer: 'trainer' }`.
- `staffInviteIssueRequestSchema` = `z.strictObject({ staffId: z.uuid() })`; `staffInviteRevokeRequestSchema` = `{ inviteId: z.uuid() }`; `staffInviteRedeemRequestSchema` = `{ token: <INVITE_TOKEN_PATTERN string> }`; `staffMemberInviteRequestSchema` = `z.strictObject({ fullName: trimmed 1..120, email: trimmed plausible email (<= 254), phone: optional E.164 `^\+[1-9][0-9]{7,14}$` (empty string → undefined), role: enum STAFF_INVITE_ROLES, branchId: optional uuid })`; `staffUnlinkRequestSchema` = `{ staffId: z.uuid(), reason: trimmed 3..200 }`.
- `STAFF_INVITE_REFUSAL_COPY` (five sentences) and `staffInviteRefusalMessage(code)`:
  - `invite_unavailable`: "This invite can't be used. It may have expired or been replaced. Ask your gym owner to send a new one."
  - `email_mismatch`: "This invite wasn't sent to this Google account. Sign in with the email your gym owner has on file for you, or ask them to update it."
  - `identity_unverified`: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in."
  - `account_already_linked`: "This account is already linked to a gym and can't be linked again. Ask your gym owner to send the invite to a different email."
  - `rate_limited`: "Too many attempts. Wait a few minutes, then try again."
- `buildStaffInviteLink(origin, token)` → `${origin}/staff-invite/${token}`; `parseStaffInviteToken(input)` (bare token or `https://<host>/staff-invite/<token>`; null otherwise); `staffInviteShareMessage({ staffName, gymName, roleLabel, email, link })`; `staffInviteNotice(gymName, roleLabel)` — "By linking, you let {gym} connect this Google account (your name and email) to your staff profile as {role}. FitCruxx processes it on {gym}'s behalf so you can sign in and do your work. Ask {gym}'s owner to unlink it at any time."
- `config/constants.ts`: `STAFF_INVITE_LIMITS = { ttlHours: 48, tenantIssuesPerHour: 30, staffIssuesPerDay: 5, redeemFailuresPerWindow: 10, redeemWindowMinutes: 15, tokenBytes: 32, cookieMaxAgeSeconds: 1800 }`, `STAFF_INVITE_COOKIE_NAME = 'fitcruxx_staff_invite'`.
- Token generation/hashing reuse `apps/web/lib/member-invite-token.ts` (`generateInviteToken`, `hashInviteToken`) unchanged.

### Web

- `lib/staff-invites.ts`: `loadStaffAppAccess(supabase, staffId)` (rpc `read_staff_app_access`), `peekStaffInvite(supabase, token)` → `{ gymName, staffRole } | null` (rpc `peek_staff_invite`, hashed).
- Routes (envelope, `no-store`, session before body, owner-only except redeem):
  - `POST /api/staff-members` (gym_owner) body = `staffMemberInviteRequestSchema` → `data: { staffId, inviteId, link, expiresAt }`. `GL076`→422 `staff_email_required`, `GL081`→409 `staff_email_taken`, `GL082`→422 `staff_role_not_invitable`, `GL078`→429 `invite_rate_limited`, `42501`→404 `branch_not_found`, validation→400 `invalid_request`, other→500 `invite_failed`.
  - `POST /api/staff-invites` (gym_owner) `{ staffId }` → `data: { inviteId, link, expiresAt, supersededInviteId }`. `42501`→404 `staff_not_found`, `GL075`→409 `staff_not_invitable`, `GL076`→422 `staff_email_required`, `GL077`→409 `staff_already_linked`, `GL078`→429 `invite_rate_limited`.
  - `POST /api/staff-invites/revoke` (gym_owner) `{ inviteId }` → `data: { revoked: true }`; `42501`→404 `invite_not_found`, `GL079`→409 `invite_not_pending`.
  - `POST /api/staff-invites/redeem` (any signed-in session; same token/cookie rules as INV with cookie `fitcruxx_staff_invite`). On `linked`/`already_linked_here` the existing trigger has already deleted the invitee's sessions, so the handler does **not** call `refreshSession()`: it expires the Supabase auth cookies and the invite cookie and answers JSON `data: { outcome, gymName, role, signInAgain: true }` / form 303 → `/sign-in?linked=staff`. Refusal mapping and form 303 `/staff-invite/continue?result=<outcome>` as INV.
  - `POST /api/staff-identity/unlink` (gym_owner) `{ staffId, reason }` → `data: { unlinked: true }`; `42501`→404 `staff_not_found`, `GL080`→409 `staff_not_linked`, `22023`→400 `invalid_request`.
- Pages: `app/staff-invite/[token]/page.tsx` and `app/staff-invite/continue/page.tsx` mirror INV's accept pages (same states, `noindex`, `no-referrer`, `staffInviteNotice`, role label shown, server action `startStaffInviteGoogleSignIn(token)` in `lib/auth-actions.ts` setting `fitcruxx_staff_invite`). `app/sign-in/page.tsx` shows "Linked. Sign in with Google again to open your workspace." when `?linked=staff`.
- `app/auth/callback/route.ts`: after INV's branch, when the identity is `unlinked`, there is no valid member-invite cookie and `fitcruxx_staff_invite` is valid → 303 `/staff-invite/continue`; all other cases unchanged.
- Console (gym_owner only; others get 403/not-found): `app/(console)/team/page.tsx` (staff list: name, role label, email, dot-plus-word access state `Linked` / `Invite pending` / `Invite expired` / `Not invited` / `Inactive`; "Invite staff member" button), `app/(console)/team/new/page.tsx` (form: full name, email, optional phone, role, optional branch), `app/(console)/team/[staffId]/page.tsx` with client `StaffAccessPanel` (`app/(console)/team/[staffId]/staff-access-panel.tsx`; actions Resend / Revoke / Unlink with required reason; after issue shows link once with copy, QR, WhatsApp, `mailto:` exactly like INV's panel). The owner's own row and other owners' rows show "Owner — linked by the platform team" with no actions. Console navigation gains "Team" for `gym_owner` only (the e2e role allow-list is amended in a `spec:` commit).
- Shared UI internals with INV's panel are factored by the implementers (jscpd threshold is 0); only the names above are fixed.

## EARS requirements

- **STI-001 (create and invite).** WHEN a real gym owner (not impersonating) submits a full name, plausible email, optional E.164 phone, a role in manager/front desk/trainer and an optional branch of their own gym THE SYSTEM SHALL, in one transaction, insert one active unlinked `staff` row and one `pending` hash-only invite (48 h), write `staff.invited` and `staff_invite.issued`, and return their ids. Role `gym_owner` or any other value SHALL fail `GL082`; a staff email already used in the gym (trimmed, case-insensitive, active or not) SHALL fail `GL081`; an implausible/blank email `GL076`; another gym's branch `42501`.
- **STI-002 (issue/resend/revoke).** As INV-001/003/005 for `staff_invites`, owner-only: manager, front desk, trainer, member, platform and impersonator SHALL be refused `42501`. An inactive staff row or a `gym_owner` row SHALL fail `GL075`; one with a `user_id` `GL077`; no/implausible email `GL076`. Resend supersedes the pending (even expired) invite in the same transaction.
- **STI-003 (limits).** 30 issues per gym per rolling hour and 5 per staff row per rolling 24 h (`GL078`), counted over `staff_invites.issued_at`; `invite_staff_member` counts toward both.
- **STI-004 (redeem).** As INV-007…011 with the staff changes stated above, including: the issuing staff row must still be an active `gym_owner` of the tenant at redemption (else `invite_unavailable`); the refusal throttle counts refusals of both families; D1 counts `members`, `staff` and `platform_users`; the same advisory lock key serializes a concurrent member and staff redemption by one account so at most one binding results.
- **STI-005 (role is the owner's).** THE SYSTEM SHALL never let the invitee choose or change the role: redemption sets only `staff.user_id`; the role, branch, name and email of the row are untouched; the access-token hook then mints `app_role` = the row's role and `staff_id`.
- **STI-006 (binding guard).** `app.enforce_staff_auth_binding` SHALL admit only the two shapes in "trigger amendment"; a front-desk, manager, owner or any other session writing `staff.user_id` directly SHALL still fail `GL049`; owner linking by `/platform` is unchanged; a `gym_owner` row can never be linked or unlinked through these commands.
- **STI-007 (peek).** As INV-012, returning gym name and the row's role only for a pending, unexpired invite of an active, role-valid staff row whose issuer is still an active owner, in an eligible gym.
- **STI-008 (unlink).** As INV-014, owner-only; target role must be manager/front desk/trainer; effects: `user_id` cleared via the admitted unlink shape, the former user's sessions deleted by the existing trigger, `staff.unlinked` audited with the reason; an unbound row fails `GL080`.
- **STI-009 (read model).** `read_staff_app_access` owner-only; states and precedence as INV-015 (`unavailable` = inactive staff or `gym_owner` role).
- **STI-010 (audit).** Every create, issue, supersede, revoke, redeem, refusal, link and unlink writes `audit_log` via `app.staff_invite_audit` with no token or hash; shapes mirror INV-016 with record types `staff_invite` / `staff` and the action names listed above; `staff.invited` after `{ role, branch_id }` and the new staff id as `record_id`; `staff.linked` after `{ user_linked: true, via: 'invite', invite_id, role }`.
- **STI-011 (tenancy/grants).** `staff_invites` is invisible across tenants and to every non-owner; no write grant to `authenticated`; all seven RPCs executable by no role beyond `authenticated` (`anon` only for peek); existing meta-suites amended in a `spec:` commit.
- **STI-012 (API).** The five routes behave as above with the INV-018 rules.
- **STI-013 (post-link sign-in).** After a staff link the handler SHALL end the local session and the person SHALL see the "sign in again" notice; it SHALL NOT claim the workspace is open.
- **STI-014 (accept pages).** As INV-020/021 with the staff cookie, role label and staff notice; the OAuth callback honours the staff cookie only when no valid member-invite cookie exists.
- **STI-015 (team console).** The Team pages SHALL be reachable only by `gym_owner`, show dot-plus-word states, never show another gym's staff, enumerate loading/empty/error/permission-denied/offline states (gate 30), and keep owner rows read-only.
- **STI-016 (copy).** Refusal copy is exactly the five staff sentences; no invented numbers; the notice states role and data processed.
- **STI-017 (retention).** `staff_invites` holds no personal data; retention row in `docs/security.md` as for `member_invites`.
- **STI-018 (no regression).** Existing owner-link (`link_gym_owner`), `deactivate_gym_owner`, hook precedence, staff front-desk RPCs and the operator provisioning tool behave exactly as before.

## Operational preconditions

As INV: open Auth signup is owner-gated; App Links wait for V2-R. Staff redeem has no mobile surface.

## Test and deployment order

Batched with INV: both migrations, both DB test sets, in one push after the local splice sweep proves them together; types regenerated once; both feature sets' TypeScript in the second push. Test file numbering: visible `supabase/tests/68_staff_invites.sql`, holdout `supabase/tests-holdout/h68_staff_invites_holdout.sql`; TS tests named `staff-*` beside their INV siblings.

## Contract amendments v1.1 (2026-10-02, after reconciling the STI test authors' ambiguity reports)

These settle the points the authors flagged. They also inherit **every** clarification in
`openspec/changes/member-invites/proposal.md` "Contract amendments v1.1" (error-argument rules, check order,
audit conventions, revoke/replay/throttle semantics, extra FK indexes, volatility, `service_role` revoke,
no-store, status codes, form/JSON redeem rules) with `member` → `staff`, except where this section says otherwise.

**Database**
- Both admitted GL049 shapes additionally require that the statement changes **no column except `user_id`** (and the trigger-maintained `updated_at`): a link or unlink that also changes role, `is_active`, `tenant_id`, `branch_id`, name or email stays refused (GL049 for sessions; a postgres-run definer without a matching setting fails as before).
- Policies: `staff_invites_owner_select` (tenant term first, then owner-only) and `staff_invites_platform_select` (platform roles read all); extra indexes `(tenant_id, issued_by_staff_id)`, `(redeemed_user_id)`, composite FK `(tenant_id, closed_by_staff_id)` with an index. Same grants posture as INV (`authenticated` select only, `service_role`/`public` no execute, `anon` only on `peek_staff_invite`). Volatility: writers volatile, `peek_staff_invite` and `read_staff_app_access` stable.
- Malformed or null token hash raises `22023` in `invite_staff_member`, `issue_staff_invite`, `redeem_staff_invite` and `peek_staff_invite`; a reused hash propagates `23505`. Redeem with no `auth.uid()` raises `42501`.
- `invite_staff_member` check order: `42501` → `22023` → `GL082` (role) → `GL075` (gym not eligible) → `GL076` (email) → `GL081` (duplicate email) → `GL078`; a foreign branch is `42501`. `issue_staff_invite` order: `42501` → `22023` → `GL075` (inactive / owner role / gym) → `GL077` → `GL076` → `GL078`.
- Redeem returns `gym_name` and `staff_role` on `linked` and on `already_linked_here`, null on every refusal. Replay requires the invite to be `redeemed` by this caller and the staff row still bound to them; after an unlink the same token is `invite_unavailable`.
- Audit: `record_type`/`record_id`: `staff.invited` → (`staff`, new staff id) with `before` null and `after {role, branch_id}` (`branch_id` is JSON null when none); `staff_invite.*` → (`staff_invite`, invite id); `staff.linked|unlinked` → (`staff`, staff id). `staff_invite.issued` after `{staff_id, expires_at, superseded_invite_id}`; `staff_invite.redeemed` after `{status:'redeemed', staff_id}`. `actor_role`: the owner's role for invited/issued/superseded/revoked/unlinked; **the staff row's own role** for redeemed and `staff.linked`; null for `redeem_refused`. Refusal rows carry `tenant_id` whenever the token resolved to an invite row.
- Unlinking an owner-role row (including the caller's own) raises `42501` (only the platform path touches owner rows). `read_staff_app_access`: precedence is `linked` first (any non-null `user_id`, including a platform-linked owner row with `linked_at` null), then `unavailable` (inactive row or owner role), then the newest invite, else `not_invited`.
- Revoking an expired-but-pending invite is allowed; impersonation raises `42501` on every command and on read.
- The throttle asymmetry is accepted and recorded: INV's redeem counts only `member_invite.redeem_refused`; the staff redeem counts both families.
- The advisory lock key `identity-bind:<uid>` is taken before any row lock on every redeem path and is observable in `pg_locks` within the transaction.

**Shared / web** (in addition to the INV web amendments)
- Create, issue, revoke and unlink answer 200 or 201 on success; every response (including errors and redirects) carries `Cache-Control: no-store`. SQLSTATEs a route does not map yield 500 `invite_failed` and never leak a token. `invite_staff_member` is called with all six named arguments, `null` for an omitted phone/branch.
- Unlink is **owner-only** (a manager is refused 403), unlike INV's owner-or-manager unlink.
- Redeem JSON `role` is the enum value (`front_desk`), not the label; a JSON call needs `{token}` and never falls back to the cookie; a form post uses a pattern-valid hidden field, else the staff cookie, and never reads the member cookie. RPC error / no row / several rows / unknown outcome → failure envelope (status ≥ 400), no cookie change. `refreshSession()` is never called on this route.
- `parseStaffInviteToken` accepts only a bare token or `https://<host>/staff-invite/<token>`; `http://`, `fitcruxx://` and `/invite/<token>` return null.
- `app/auth/callback/route.ts` keeps INV's branch first and adds the staff branch (member cookie wins when both are valid).
- Team console: a non-owner is redirected / not-found before any table read; the owner's own row and other owner rows are read-only ("Owner — linked by the platform team"); the panel states the on-file email and the 48-hour expiry beside Send invite.
- The staff share message has no expiry input; the panel states the expiry in the panel text instead.
