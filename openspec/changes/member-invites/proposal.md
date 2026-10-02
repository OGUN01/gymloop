# Member invites and self-linking (INV-001…INV-024)

Feature F1 of `docs/planning/v2-feature-map.md`, phase V2-A1 of `docs/planning/v2-campaign-goal.md`.
Rigor: **full blind arrangement (ADR-059)** — identity and claim contract; a silent mistake shows one
person another person's membership, receipts and messages.

## Quality bar

Named, fetchable references are in `docs/design/v2/inv-bar.md` (accept-invite page, admin-side
pending/expired/revoked/resend states, deep-linked mobile onboarding). The bar for this feature is the
measurable list at the end of that file plus the structural criteria here: every refusal names what
happened and the next action in one sentence; no refusal reveals whether another person's record exists;
status is dot-plus-word; the accept flow is two taps after Google consent; copy states what data is
processed.

## Why

Today a member's `members.user_id` is set only by `scripts/provision-identity.mjs` (PROV-001…012), run
by an operator with the service-role key (ADR-173). That cannot scale past the closed test. INV lets
a gym add a member and hand them an invite (link or QR); the member signs in with Google and links
themselves. The operator script stays for recovery. This supersedes the "public invite/self-link is
post-v1" clauses of ADR-134 and ADR-173 (recorded as ADR-176).

D1 (owner decision 2026-10-02, `v2-campaign-goal.md`): **one Google account is exactly one member, ever,
in the whole system.** An account already linked anywhere is refused with clear copy. Never a gym
picker, never a silent second binding.

## Scope

In: DB (table, enum, guard trigger, six RPCs), shared contracts, web (console "App access" panel,
public accept pages, four API routes, OAuth round-trip), mobile (deep-link route, paste-a-link on the
not-linked screen), audit, docs. Out (recorded, not built): automated email/WhatsApp/push delivery of the
invite (arrives with WSP/NTF — until then staff share the link, QR, a WhatsApp share link or `mailto:`);
Android App Links / `assetlinks.json` (needs the Play signing fingerprint and a native build — V2-R);
guardian linking for minors (GRD); staff invites (STI); disabling or enabling Auth signup (owner-gated
configuration, see "Operational preconditions").

## Bar decisions and deliberate deviations (`docs/design/v2/inv-bar.md`)

- **Email match is exact** (trimmed, case-insensitive) — the bar's open point 1, GitHub's precedent. No lenient matching.
- **Expiry is 48 hours** — open point 2; inside the feature map's 24–48 h range.
- **No member name before sign-in** — open point 3; the pre-auth page shows the gym name only (INV-Q7). The signed-in continue page shows the Google email in use, never the address on file.
- **Deviation from INV-Q6 (causes never conflated), decided here:** the five fixed refusal sentences separate every case the person can act on (wrong Google account, account already linked, unverified sign-in, rate limited) and deliberately collapse unknown/expired/revoked/replaced/already-used/member-ineligible into one, because the next action is identical (ask your gym for a new invite) and a distinct sentence would tell whoever holds a link whether a member is cancelled or blocked and what the invite's history is. The copy names the likely causes ("expired or been replaced") without asserting one. The owner may override this by amending the copy table; the tests pin the five sentences.
- **INV-Q10 (reviewed send):** the panel states the on-file email and the 48-hour expiry beside "Send invite", and creating the invite immediately shows the link, QR and share actions; there is no separate confirm step because creating an invite sends nothing by itself.
- **INV-Q12:** limit refusals say what limit was hit ("Too many invites for this member today. Try again tomorrow." / "Too many invites from this gym this hour. Try again in an hour.") with no number beyond those. The console copy table is implementation-owned but must not invent numbers.

## Fixed names (the contract — nothing here changes while agents work against it)

### Database

| Object | Name / signature |
|---|---|
| enum | `public.member_invite_status` = `pending`, `redeemed`, `revoked`, `superseded` |
| table | `public.member_invites` (tenant-scoped, direct `tenant_id`, RLS on) |
| columns | `id uuid pk default gen_random_uuid()`, `tenant_id uuid not null → organizations`, `member_id uuid not null`, `token_hash text not null` (lowercase hex SHA-256), `status member_invite_status not null default 'pending'`, `issued_by_staff_id uuid not null`, `issued_at timestamptz not null default now()`, `expires_at timestamptz not null`, `closed_at timestamptz`, `closed_by_staff_id uuid`, `redeemed_user_id uuid → auth.users on delete set null`, `created_at`, `updated_at` |
| keys | composite FKs `(tenant_id, member_id) → members(tenant_id, id)` and `(tenant_id, issued_by_staff_id) → staff(tenant_id, id)`; global unique `member_invites_token_hash_key (token_hash)` (a token carries no tenant, so this is the third deliberate non-tenant-leading unique beside `qr_sessions_token_hash_key`; `04_contract_meta` is amended in a `spec:` commit); partial unique `member_invites_one_pending_key (tenant_id, member_id) where status = 'pending'` |
| checks (ADR-040 names) | `member_invites_token_hash_format_chk` (`^[0-9a-f]{64}$`), `member_invites_expiry_chk` (`expires_at > issued_at`), `member_invites_closed_state_chk` (`status = 'pending'` ⇔ `closed_at is null`; `redeemed` ⇒ `redeemed_user_id` may be set; non-redeemed ⇒ `redeemed_user_id is null`) |
| indexes | `(tenant_id, member_id, issued_at desc)`, `(tenant_id, issued_at)` (issue throttle), `audit_log (actor_user_id, occurred_at) where action = 'member_invite.redeem_refused'` (redeem throttle) |
| RLS / grants | `authenticated`: `select` only, via a front-office read policy on own tenant (`app.is_front_office()` and `tenant_id = (select app.current_tenant_id())`); no insert/update/delete grant; members, trainers and other tenants read nothing; the standard `member_invites_touch_updated_at` and `member_invites_preview_read_only` triggers (`04_contract_meta` convention) |
| guard trigger | `members_auth_binding_invariant` — `before insert or update of user_id` on `public.members`, function `app.enforce_member_auth_binding()` (invoker). Refuses `GL074` when `new.user_id is not null` on insert, or `new.user_id is distinct from old.user_id` on update, **unless** `current_user = 'postgres'` (definer commands, migrations, seed) **or** `current_user = 'service_role'` with `auth.uid() is null` (the operator provisioning tool). So even an owner cannot write `members.user_id` through a session. It adds no cross-table check (existing fixtures legitimately bind one user in several tables); the cross-table rule lives in the redeem command. |
| audit helper | `app.member_invite_audit(p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text, p_record_type text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text) returns void` — definer, owner `postgres`, executable by nobody else, action allowlist exactly the seven below (anything else raises `22023`) |
| RPC: issue | `public.issue_member_invite(p_member_id uuid, p_token_hash text) returns table (invite_id uuid, expires_at timestamptz, superseded_invite_id uuid)` — definer, `set search_path = ''`, executable by `authenticated` only |
| RPC: revoke | `public.revoke_member_invite(p_invite_id uuid) returns uuid` (returns the invite id) — same posture |
| RPC: redeem | `public.redeem_member_invite(p_token_hash text) returns table (outcome text, gym_name text)` — same posture; **returns refusal outcomes as rows, never as exceptions**, so the refusal audit row and throttle evidence commit |
| RPC: peek | `public.peek_member_invite(p_token_hash text) returns table (gym_name text)` — definer; executable by `anon` **and** `authenticated` (the only anon-executable definer added); returns zero rows unless the token is a pending, unexpired invite for an invitable member in an eligible gym |
| RPC: unlink | `public.unlink_member_identity(p_member_id uuid, p_reason text) returns void` — same posture as issue |
| RPC: read | `public.read_member_app_access(p_member_id uuid) returns table (state text, invite_id uuid, issued_at timestamptz, expires_at timestamptz, linked_at timestamptz)` — same posture; `state` ∈ `linked`, `invite_pending`, `invite_expired`, `not_invited`, `unavailable` |
| advisory lock key | the per-Auth-user lock in redeem is exactly `pg_advisory_xact_lock(hashtextextended('identity-bind:' || auth.uid()::text, 0))`; staff invites (batched change `staff-invites`) take the same key so one account cannot be linked as member and as staff concurrently |
| actor helper | `app.member_invite_actor(p_roles text[])` (invoker, mirrors `app.checkin_gate_actor`): `auth.uid()`, tenant, staff id present; no member id; no impersonation id; `app_role` in `p_roles`; the staff row active with matching tenant/id/user/role; else `42501` |
| SQLSTATEs | `GL074` binding guard refused · `GL075` member not invitable (status `cancelled`/`blocked`, `erased_at` set, or gym not eligible) · `GL076` member email missing or implausible · `GL077` member already linked · `GL078` invite rate limit · `GL079` invite not pending (revoke) · `GL080` member not linked (unlink) · `42501` permission/visibility (cross-tenant or unknown ids are indistinguishable from forbidden) · `22023` malformed input |
| limits (mirrored in `MEMBER_INVITE_LIMITS`) | ttl 48 hours; 100 issues per tenant per rolling hour; 5 issues per member per rolling 24 hours; 10 refused redemptions per Auth user per rolling 15 minutes |
| audit actions | `member_invite.issued`, `member_invite.superseded`, `member_invite.revoked`, `member_invite.redeemed`, `member_invite.redeem_refused`, `member.linked`, `member.unlinked` |

"Gym eligible" is the predicate the access-token hook already uses:
`organizations.status = 'active'` or (`status = 'trial'` and `trial_ends_at > statement_timestamp()`).
"Invitable member" = status not `cancelled`/`blocked`, `erased_at is null`, `user_id is null`, `email`
present and plausible (one `@`, non-empty local part, dotted domain, no whitespace — the PROV-002 rule),
gym eligible.

### Shared (`packages/shared`, platform-free)

`src/api/member-invites.ts`, re-exported from `src/index.ts`:

- `INVITE_TOKEN_PATTERN` = `/^[A-Za-z0-9_-]{43}$/` (32 random bytes, base64url, no padding).
- `inviteIssueRequestSchema` = `z.strictObject({ memberId: z.uuid() })`.
- `inviteRevokeRequestSchema` = `z.strictObject({ inviteId: z.uuid() })`.
- `inviteRedeemRequestSchema` = `z.strictObject({ token: z.string().regex(INVITE_TOKEN_PATTERN) })`.
- `memberUnlinkRequestSchema` = `z.strictObject({ memberId: z.uuid(), reason: z.string().trim().min(3).max(200) })`.
- `INVITE_REDEEM_OUTCOMES` = `['linked','already_linked_here','invite_unavailable','email_mismatch','identity_unverified','account_already_linked','rate_limited'] as const`, type `InviteRedeemOutcome`.
- `INVITE_REFUSAL_COPY: Record<Exclude<InviteRedeemOutcome,'linked'|'already_linked_here'>, string>` and `inviteRefusalMessage(code: string): string` (unknown code → the `invite_unavailable` copy). The five sentences, verbatim:
  - `invite_unavailable`: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one."
  - `email_mismatch`: "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it."
  - `identity_unverified`: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in."
  - `account_already_linked`: "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email."
  - `rate_limited`: "Too many attempts. Wait a few minutes, then try again."
- `buildInviteLink(origin: string, token: string): string` → `${origin}/invite/${token}` (origin without trailing slash).
- `parseInviteToken(input: string): string | null` — accepts a bare token, `https://<host>/invite/<token>` (query/hash ignored), or `fitcruxx://invite/<token>`; surrounding whitespace trimmed; anything not matching `INVITE_TOKEN_PATTERN` → `null`.
- `inviteShareMessage(input: { memberName: string; gymName: string; email: string; link: string }): string` — first name only, e.g. "Hi Asha, Iron Box Fitness invited you to join on FitCruxx. Open this link and sign in with Google using asha@example.com so your membership connects: <link>".
- `inviteNotice(gymName: string): string` — the DPDP notice: "By linking, you let {gym} connect this Google account (your name and email) to your membership record. FitCruxx processes it on {gym}'s behalf to show you your visits, payments and messages. Ask {gym} to unlink it at any time."

`config/constants.ts`: `MEMBER_INVITE_LIMITS = { ttlHours: 48, tenantIssuesPerHour: 100, memberIssuesPerDay: 5, redeemFailuresPerWindow: 10, redeemWindowMinutes: 15, tokenBytes: 32, cookieMaxAgeSeconds: 1800 }` and `INVITE_COOKIE_NAME = 'fitcruxx_invite'`.

### Web (`apps/web`)

- `lib/member-invite-token.ts`: `generateInviteToken(): string` (32 bytes of `node:crypto` randomness, base64url) and `hashInviteToken(token: string): string` (lowercase hex SHA-256 of the token's UTF-8 text). **The database never sees a raw token** — handlers hash before every RPC (the poster-code precedent).
- `lib/member-invites.ts`: `loadMemberAppAccess(supabase, memberId)` (calls `read_member_app_access`), `peekInvite(supabase, token)` (calls `peek_member_invite`, returns `{ gymName } | null`).
- `lib/api.ts`: new `signedInSession(request)` — any verified session, **including an unlinked one** (cookie or bearer, never mixed), returning `{ supabase, userId }`, else 401 `not_signed_in`.
- Routes (all `Cache-Control: no-store`; session before body; envelope per `lib/api.ts`):
  - `POST /api/member-invites` (front office; JSON `{memberId}`) → `data: { inviteId, link, expiresAt, supersededInviteId }`. Errors: `42501`→404 `member_not_found`, `GL075`→409 `member_not_invitable`, `GL076`→422 `member_email_required`, `GL077`→409 `member_already_linked`, `GL078`→429 `invite_rate_limited`, schema failure→400 `invalid_request`, other→500 `invite_failed`.
  - `POST /api/member-invites/revoke` (front office; `{inviteId}`) → `data: { revoked: true }`. `42501`→404 `invite_not_found`, `GL079`→409 `invite_not_pending`.
  - `POST /api/member-identity/unlink` (owner/manager only; `{memberId, reason}`) → `data: { unlinked: true }`. `42501`→404 `member_not_found`, `GL080`→409 `member_not_linked`.
  - `POST /api/member-invites/redeem` (any signed-in session). Token from JSON `{token}` (mobile, envelope response) **or**, for a form post, the hidden `token` field falling back to the `fitcruxx_invite` cookie (303 response). After `linked`/`already_linked_here` the handler calls `supabase.auth.refreshSession()` so the access-token hook mints member claims (the hook runs only at token issue; ADR notes the 15-minute `jwt_expiry`), clears the cookie, and answers `data: { outcome, gymName }` / 303 to `identityHome`. Refusals: `invite_unavailable`→404, `email_mismatch`→403, `identity_unverified`→403, `account_already_linked`→409, `rate_limited`→429, each `apiFail` with `code` = the outcome; form path 303 → `/invite/continue?result=<outcome>`; the cookie is **kept** on refusal so the person can switch Google account and retry. If the refresh fails the session is signed out and auth cookies expired (the `impersonation/end` precedent).
- Pages (outside `(console)` and `member/`, both of which bounce unlinked users): `app/invite/[token]/page.tsx` (landing) and `app/invite/continue/page.tsx`. Both set `robots: noindex` and `referrer: no-referrer` (the token is in the URL). The landing page's Google button is a server action (`lib/auth-actions.ts`: `startInviteGoogleSignIn(token)`) that sets the `fitcruxx_invite` cookie (`HttpOnly`, `SameSite=Lax`, `Path=/`, `Max-Age` = `cookieMaxAgeSeconds`, `Secure` on https) **then** starts Google OAuth.
- `app/auth/callback/route.ts`: when the exchanged identity is `unlinked` **and** the `fitcruxx_invite` cookie is present and matches `INVITE_TOKEN_PATTERN`, redirect to `/invite/continue`; every other case is unchanged (still ignores `next`).
- `app/not-linked/page.tsx`: adds one sentence and no input: open the invite link your gym sent you, then sign in. Existing pinned strings remain.
- Console: `app/(console)/members/[memberId]/app-access-panel.tsx` exports `AppAccessPanel` (client) rendered by the member page for front-office roles only (hidden for trainers); `QRCodeSVG` from `qrcode.react` for the link.

### Mobile (`apps/mobile`)

- `app/invite/[token].tsx` — route for `fitcruxx://invite/<token>`; handles every identity state itself (cold start bypasses `app/index.tsx`).
- `lib/invite.ts` — pure logic: `PENDING_INVITE_KEY = 'gymloop.pending-invite'`; `resolveInviteEntry(input: { token: string | null; sessionPresent: boolean; identityKind: 'unlinked' | 'member' | 'staff' | 'platform' | 'impersonation' | 'none' }): { action: 'invalid_link' | 'save_and_sign_in' | 'redeem' | 'already_linked' }` (null/invalid token → `invalid_link`; no session → `save_and_sign_in`; session + `unlinked` → `redeem`; any other session → `already_linked`); `inviteOutcomeMessage(code: string): string` re-using `inviteRefusalMessage`; storage helpers `savePendingInvite(token)`, `takePendingInvite()` over SecureStore.
- `app/not-linked.tsx` gains "Have an invite?" — a `Field` accepting a pasted link or token and an `ActionButton` "Link my membership"; a pending token saved by the deep-link route is offered automatically. It posts through `api.post('/api/member-invites/redeem', { token })` (no offline queue — a single-use token is never queued), then `supabase.auth.refreshSession()`; `onAuthStateChange` re-resolves identity and the existing redirect routes the member home. Existing pinned `not-linked` strings stay and none of `does not exist|no account|not found|no such account|invalid account` appears.

## EARS requirements

- **INV-001 (issue).** WHEN real front-office staff (owner, manager, front desk; never an impersonation or preview identity) issue an invite for an invitable member of their own gym, THE SYSTEM SHALL create exactly one `pending` invite that stores only the lowercase-hex SHA-256 of the token, expires 48 hours after issue, names the issuing staff, and writes `member_invite.issued`. The raw token SHALL never be stored, logged, audited or returned by the database.
- **INV-002 (invitable).** IF the member is `cancelled` or `blocked`, erased, or the gym is not eligible THEN issue SHALL fail `GL075`; IF `email` is null, blank or implausible THEN `GL076`; IF the member already has a `user_id` THEN `GL077`. A member of another gym, an unknown id and a forbidden role SHALL be indistinguishable (`42501`). Trainers, members, platform users and impersonators SHALL be refused `42501`.
- **INV-003 (one pending; resend).** A member SHALL have at most one `pending` invite, enforced by the database under concurrent issues. Issuing while a pending invite exists (including an already-expired one) SHALL, in the same transaction, mark the old invite `superseded` with `closed_at`, write `member_invite.superseded`, and return its id as `superseded_invite_id`. A superseded token SHALL never redeem.
- **INV-004 (expiry).** An invite SHALL be redeemable only while `status = 'pending'` and `expires_at > statement_timestamp()`. Expiry is derived; no sweeper runs; `read_member_app_access` reports `invite_expired` for a pending row past expiry.
- **INV-005 (revoke).** WHEN front-office staff of the same gym revoke a `pending` invite THE SYSTEM SHALL mark it `revoked`, set `closed_at`/`closed_by_staff_id`, and write `member_invite.revoked`; a revoked token SHALL never redeem. Revoking a non-pending invite SHALL fail `GL079`; another gym's or an unknown invite SHALL fail `42501`.
- **INV-006 (abuse limits).** THE SYSTEM SHALL refuse an issue `GL078` when the gym has issued 100 invites in the rolling hour or the member has been issued 5 in the rolling 24 hours (counted from `member_invites.issued_at`). A refusal writes nothing.
- **INV-007 (redeem).** WHEN an authenticated caller presents the hash of a `pending`, unexpired invite THE SYSTEM SHALL, in one transaction that takes (in this order) a per-Auth-user advisory lock, the member row lock, then the invite row lock, set `members.user_id = auth.uid()` only if **all** hold: (a) the member is still bindable — status not `cancelled`/`blocked`, `erased_at` null, `user_id` null, gym eligible; (b) the caller's Auth user has `email_confirmed_at` and a `google` identity, and is a verified identity by the PROV-006a rule (`raw_app_meta_data->>'gymloop_provisioned' = 'true'`, or no identity with provider `email`); (c) that Google identity's `identity_data->>'email'` equals the member's *current* `email` (trimmed, case-insensitive; a null or blank member email never matches); (d) the caller's Auth user is bound to no row of `members`, `staff` or `platform_users`; and (e) the caller is not impersonating (otherwise `42501`). It then marks the invite `redeemed` (`redeemed_user_id`, `closed_at`), writes `member_invite.redeemed` and `member.linked`, and returns `outcome = 'linked'` with the gym's name. After a link, `app.custom_access_token_hook` SHALL mint `app_role = 'member'` claims for that user on the next token issue.
- **INV-008 (refusals are rows, with no oracle).** Redeem refusals SHALL be returned as rows with `outcome` ∈ {`invite_unavailable`, `email_mismatch`, `identity_unverified`, `account_already_linked`, `rate_limited`} and `gym_name` null. An unknown, expired, revoked, superseded or redeemed-by-someone-else token; a cancelled, blocked or erased member; an ineligible gym; and a member row that is already bound SHALL all return `invite_unavailable`. Check order: throttle, replay (INV-009), token, member/gym state (a), then identity (b → `identity_unverified`), then email (c → `email_mismatch`), then account bindings (d → `account_already_linked`). No outcome carries member facts or the address on file. Every refusal except `rate_limited` writes `member_invite.redeem_refused` (tenant when the token resolved, else null; `after = {outcome}`).
- **INV-009 (idempotent replay).** After the throttle check and before the pending check, WHEN the Auth user recorded as `redeemed_user_id` of a `redeemed` invite presents its token again and the member is still bound to that user THE SYSTEM SHALL return `already_linked_here` with no write; any other caller SHALL get `invite_unavailable`. An account bound to a *different* member is `account_already_linked` (INV-011), never `already_linked_here`.
- **INV-010 (redeem throttle).** WHEN an Auth user has 10 or more `member_invite.redeem_refused` rows in the rolling 15 minutes THE SYSTEM SHALL return `rate_limited` before evaluating the token and write nothing.
- **INV-011 (D1: one account, one member).** IF the caller's Auth user is already bound anywhere — any gym, as member, staff or platform user — THEN THE SYSTEM SHALL return `account_already_linked` and bind nothing. Two concurrent redemptions by one account SHALL produce at most one binding (the advisory lock).
- **INV-012 (peek).** `peek_member_invite` SHALL return the gym name only for a pending, unexpired invite whose member is invitable-status and whose gym is eligible, and zero rows otherwise. It SHALL be callable signed-out and SHALL return no other column. Hashes that are not 64 lowercase-hex characters raise `22023`.
- **INV-013 (binding guard).** THE SYSTEM SHALL refuse `GL074` any insert of a `members` row with a non-null `user_id`, and any update changing `user_id`, issued through `authenticated` or `anon` (every role, including owner), while the definer commands, migrations, seed and the service-role provisioning tool (no JWT subject) continue to work.
- **INV-014 (unlink).** WHEN a real gym owner or manager unlinks a bound member with a reason of 3–200 trimmed characters THE SYSTEM SHALL clear `user_id`, delete the former user's `auth.sessions` rows, and write `member.unlinked` carrying the reason. Unlinking an unbound member SHALL fail `GL080`; front desk, trainer, member, platform, impersonator and another gym SHALL fail `42501`; a missing or too-short reason SHALL fail `22023`. A pending invite is left untouched.
- **INV-015 (read model).** `read_member_app_access` SHALL be front-office-only (`42501` otherwise, including cross-gym) and return `linked` (with `linked_at` = the latest `member.linked` audit time, or null for operator-bound members), `invite_pending`, `invite_expired`, `not_invited`, or `unavailable` (member `cancelled`, `blocked` or erased). Precedence: `linked` (a non-null `user_id`), then `unavailable`, then the newest invite (`invite_pending` if `expires_at` is in the future, else `invite_expired`; a closed `redeemed`/`revoked`/`superseded` newest invite counts as none), else `not_invited`. A member with no email and no invite is `not_invited`.
- **INV-016 (audit).** Every issue, supersede, revoke, redeem, refusal, link and unlink SHALL write `audit_log` through `app.member_invite_audit`, attributed to `auth.uid()` and role, with no token and no token hash in `before`/`after`. Shapes: `issued` after `{member_id, expires_at, superseded_invite_id}`; `superseded` before `{status:'pending'}` after `{status:'superseded', replaced_by}`; `revoked` before `{status:'pending'}` after `{status:'revoked'}`; `redeemed` (role `member`) before `{status:'pending'}` after `{status:'redeemed', member_id}`; `member.linked` before `{user_linked:false}` after `{user_linked:true, via:'invite', invite_id}`; `member.unlinked` before `{user_linked:true}` after `{user_linked:false}` with `reason`. The operator provisioning tool writes no audit row (a recorded gap, ADR-176).
- **INV-017 (tenancy).** `member_invites` SHALL be invisible across tenants and to members and trainers; `authenticated` SHALL hold no insert, update or delete privilege; every RPC SHALL be executable by no role beyond those stated (`anon` only for peek). Existing schema meta-tests are amended for the new table, unique index and definer functions.
- **INV-018 (API).** The four routes SHALL behave as in "Web", validate through the shared schemas, return the typed envelope, set `Cache-Control: no-store`, identify the caller before reading the body, map SQLSTATEs by `Object.hasOwn` lookup, and never place a token, hash or address in a log, an error message or a URL query.
- **INV-019 (console panel).** The member page SHALL show an "App access" section to front-office roles (not trainers) with dot-plus-word state: **Linked** (since date; "Unlink account" for owner/manager, behind a confirm panel with a required reason), **Invite pending** (expires time; "Resend invite" and "Revoke"), **Invite expired** ("Send a new invite"), **Not invited** ("Send invite"; when the member has no email, a message with a link to edit the member; when cancelled/blocked/erased, an explanation, no action). After issuing, the panel SHALL show the link once with Copy, a QR code, a WhatsApp share link and a `mailto:` link, and say that resending replaces the link. In support preview the panel is read-only. States enumerated per gate 30: loading, not invited, pending, expired, linked, unavailable, permission denied (hidden), error, rate-limited, offline.
- **INV-020 (accept pages).** `/invite/[token]` SHALL show, for a valid token, the gym name, the DPDP notice (`inviteNotice`) with a link to `/privacy`, and one primary action — "Continue with Google" when signed out, "Link this account" when signed in unlinked; for any invalid token ONE generic unavailable state; for a signed-in already-linked account the D1 copy and a link home; for a signed-in unlinked account whose cookie/token is valid, the signed-in email is shown. `/invite/continue` SHALL read the cookie, show gym name, signed-in email, the notice and one "Link my membership" button, map `?result=` through `inviteRefusalMessage`, and offer "Use a different Google account" (sign out; the cookie is kept). With no cookie it SHALL show the unavailable state. A signed-out visit to `/invite/continue` SHALL redirect to the token landing if the cookie holds a token, else to `/sign-in`.
- **INV-021 (OAuth round trip).** THE SYSTEM SHALL carry the token across Google OAuth only in the `fitcruxx_invite` cookie (never in `redirectTo`, `next`, a query string or local storage), expire it after 30 minutes, and honour it only in the callback's unlinked branch.
- **INV-022 (mobile).** THE SYSTEM SHALL let an unlinked signed-in member paste an invite link or token on the not-linked screen, accept `fitcruxx://invite/<token>` via the route above, save a token that arrives before sign-in and offer it after, and never queue a redemption offline (an offline attempt shows a retry message, no fake success). After a successful link the member lands on the member home with fresh claims. This amends the "no public-code join" requirement of `openspec/specs/mobile`: a single-use, expiring, email-bound invite token is not the public gym code and is not an unauthenticated join.
- **INV-023 (copy and consent).** Every user-visible string SHALL follow the product voice: specific, honest, no invented numbers; refusal copy is exactly the five sentences in "Shared"; the accept pages state what data is processed (INV-020). `/privacy` gains a sentence on invite-based account linking.
- **INV-024 (data lifecycle).** `member_invites` holds no personal data (ids, hash, timestamps). Retention: prune 1 year after `closed_at` or `expires_at` (a `docs/security.md` row; no job is built, like the other rows). A member erasure (`erased_at`) makes their pending invite unavailable at once (INV-008).

## Operational preconditions (owner-gated; not performed by this change)

1. **Public Auth signup must be open for a never-seen Google account to reach redemption** (ADR-173 closed it; `auth-signup.yml mode=enable-signup`). Orphan unlinked accounts gain nothing: every gym surface needs a claim, and redemption needs the invite token *and* a matching verified email. The owner decides when to flip it. Until then INV works for Google accounts that already exist in Auth (for example those provisioned by the script).
2. The Auth redirect allow-list already contains `https://fitcruxx.vercel.app/auth/callback`, so no allow-list change is needed.
3. Android App Links and a custom domain are V2-R work; until then an `https://…/invite/…` link opens the web accept page, which also offers "Open in the FitCruxx app" through the `fitcruxx://invite/<token>` scheme.

## Test and deployment order

1. `spec:` commits: this proposal, EARS rows, the amended meta-suites; visible pgTAP (`supabase/tests/67_member_invites.sql`) and holdout pgTAP (`supabase/tests-holdout/h67_member_invites_holdout.sql`, lowercase `begin;`/`select * from finish();` so `sweep.py` can splice it) by two independent authors; visible and holdout TypeScript suites by the same two authors.
2. Migration `20261002100000_member_invites.sql` only, plus pgTAP tests: prove locally with `scripts/pgtap/sweep.py` splicing the migration (no DB run in flight), push; wait for the DB run (≈50 minutes) to apply and pass.
3. Regenerate `packages/db/types/database.ts` with `supabase gen types typescript --linked`; push types + TypeScript tests (`spec:`) + implementation in separate commits (tests, types, implementation); wait for the second DB run (schema-drift) and `ci.yml`.
4. Web verification first; Android hot-reload after, with the owner.
