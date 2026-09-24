# Closed-test identity provisioning (PROV-001…010)

## Why
Google Play's closed test needs 12+ real testers who can actually use the app.
Gymloop has no invite or self-linking flow in v1 (ADR-134): a member's
`members.user_id` is set only by hand-written SQL today, and front-desk/trainer
`staff.user_id` binding is limited to the service/postgres path (GL049). Hand
SQL against the one Cloud project is exactly the silent-failure shape ADR-059
reserves the full blind arrangement for: binding the wrong Auth user to a
member shows one person another person's membership, receipts and messages.

This change adds one operator tool that binds a pre-created, email-confirmed
Auth identity to exactly one existing gym row, refusing every ambiguous case.
The person then signs in with "Continue with Google" (Supabase links a Google
identity to an existing confirmed user with the same verified email) or an
operator-issued password reset. It adds no product surface, no migration and
no RLS change; owners keep the audited `/platform` "Link owner profile" path.

## Contract (frozen before fan-out)

Module: `scripts/provision-identity.mjs` (ESM). Exports exactly:

```js
/** Pure decision + effect sequence over an injected port. Never reads env. */
export async function provisionIdentity(port, request) // → Promise<ProvisionResult>
/** Adapter from a service-role supabase-js client to the port. */
export function createSupabaseProvisionPort(adminClient) // → ProvisionPort
/** CLI entry: parses argv, builds the service-role client from env, prints one JSON line. */
export async function main(argv) // → Promise<number> exit code
```

`request`:
```js
{
  email: string,            // the person's sign-in email (e.g. their Play tester Gmail)
  gymCode: string,          // organizations.gym_code, ^[A-Z0-9]{6}$
  target: { kind: 'member', id: string } | { kind: 'staff', id: string }, // uuid
  apply: boolean,           // false = dry run
}
```

`port` (every method async; the adapter implements them with the service-role client):
```js
{
  findGymByCode(code)                 // → { id, gymCode } | null
  findMember(tenantId, memberId)      // → { id, tenantId, email, userId, status, erasedAt } | null
  findStaff(tenantId, staffId)        // → { id, tenantId, email, userId, role, isActive } | null
  findAuthUserByEmail(email)          // → { id, email } | null   (case-insensitive match)
  countBindings(userId)               // → { members, staff, platform }  rows whose user_id = userId
  createConfirmedAuthUser(email)      // → { id }   email_confirm: true, NO password
  deleteAuthUser(userId)              // → void
  bindMember(tenantId, memberId, userId) // → number of rows changed; conditional on user_id IS NULL
  bindStaff(tenantId, staffId, userId)   // → number of rows changed; conditional on user_id IS NULL
}
```

`ProvisionResult`:
```js
{
  ok: boolean,
  code: 'planned' | 'linked' | 'already_linked'
      | 'invalid_request' | 'gym_not_found' | 'target_not_found' | 'email_mismatch'
      | 'target_ineligible' | 'target_already_linked' | 'identity_bound_elsewhere' | 'bind_conflict',
  target: { kind: 'member' | 'staff', id: string } | null,
  authUser: 'would_create' | 'would_reuse' | 'created' | 'reused' | 'none',
  authUserId: string | null,        // only when known; never a token
  email: string | null,             // REDACTED: first character of the local part + '***@' + domain
}
```

## Requirements (EARS)

- **PROV-001 (dry run by default).** When `apply` is false, the tool shall call
  only `find*`/`countBindings` port methods and shall return `code: 'planned'`
  (`ok: true`, `authUser: 'would_create' | 'would_reuse'`) when every check in
  PROV-003…006 passes, or the refusal code otherwise. It shall never call
  `createConfirmedAuthUser`, `deleteAuthUser`, `bindMember` or `bindStaff`.
- **PROV-002 (request validation).** If the email is not a single plausible
  address (one `@`, non-empty local part and dotted domain, no whitespace), the
  gym code does not match `^[A-Z0-9]{6}$`, the target id is not a UUID, or the
  target kind is neither `member` nor `staff`, the tool shall return
  `invalid_request` without calling any port method. Emails are compared
  trimmed and case-insensitively; the gym code is not case-folded.
- **PROV-003 (gym and target).** The tool shall resolve the tenant only from
  `findGymByCode`; if absent → `gym_not_found`. It shall read the target only
  through `findMember`/`findStaff` with that tenant id; if absent (including a
  row in another tenant) → `target_not_found`.
- **PROV-004 (the row must name this person).** If the target row's `email` is
  null or differs (trimmed, case-insensitive) from the request email → 
  `email_mismatch`.
- **PROV-005 (eligibility).** A member is ineligible when `status` is
  `cancelled` or `blocked` or `erasedAt` is non-null; a staff row is ineligible
  when `isActive` is false or `role` is `gym_owner` (owners are linked only by
  the audited `/platform` path). Ineligible → `target_ineligible`.
- **PROV-006 (one identity, one gym row).** If the target row already has a
  `userId`: when it equals the Auth user found by email → `already_linked`
  (`ok: true`, no writes); otherwise → `target_already_linked`. If an Auth user
  exists for the email and `countBindings` reports any member, staff or
  platform binding → `identity_bound_elsewhere` (v1 allows one verified gym
  association per person, ADR-134).
- **PROV-007 (apply).** When `apply` is true and all checks pass, the tool shall
  reuse the existing unbound Auth user or create one with
  `createConfirmedAuthUser` (no password), then call exactly one bind method
  once. If it returns exactly 1 → `linked` (`authUser: 'created' | 'reused'`).
- **PROV-008 (race and compensation).** If the bind returns anything other than
  1 → `bind_conflict`, `ok: false`; if this run created the Auth user, it shall
  call `deleteAuthUser` for that id exactly once. A reused Auth user is never
  deleted. If `createConfirmedAuthUser` or the bind throws, the tool shall
  apply the same compensation and rethrow nothing secret (the result or error
  message never contains keys, tokens or the unredacted email).
- **PROV-009 (redaction).** Every result and every CLI output line shall carry
  the email only in redacted form (`a***@example.com`) and shall never contain
  the service-role key, an access/refresh token or a password.
- **PROV-010 (CLI).** `main(argv)` accepts `--email <e> --gym <CODE>` and exactly
  one of `--member <uuid>` / `--staff <uuid>`, plus optional `--apply`. It reads
  the Supabase URL and service-role key only through a function exported from
  `packages/shared/src/config/env.ts` (AGENTS.md rule 3), prints exactly one
  JSON line (the result), and returns 0 when `ok` is true, 1 otherwise. Missing
  or duplicate flags → `invalid_request` without network calls.

## Out of scope
Owner linking (keeps `/platform`), password issuance, invitations, a product
UI, bulk import, any migration or policy change, disabling Auth signup (a
separate, reversible configuration step recorded in ADR-172).
