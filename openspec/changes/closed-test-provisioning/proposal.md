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

## Amendment 1 (2026-09-24, after the fresh critic's NO-GO) — supersedes the conflicting text above

The critic found four silent-failure paths. The contract changes as follows;
anything not mentioned stays as written.

**Port changes**
```js
{
  findAuthUserByEmail(email)
    // → { id, email, provisioned: boolean, googleVerified: boolean, hasEmailIdentity: boolean } | null
    //   provisioned     = app_metadata.gymloop_provisioned === true (only the service role can set app_metadata)
    //   googleVerified  = the user has an identity with provider 'google' whose email equals `email`
    //                     (trimmed, case-insensitive)
    //   hasEmailIdentity = the user has an identity with provider 'email' (a password/self sign-up identity)
    //   THROWS (never returns null) if the directory could not be fully searched (page cap reached with
    //   more pages remaining, or any API error).
  countBindings(userId)             // unchanged shape; THROWS on any query error or a missing count (never 0 by default)
  createConfirmedAuthUser(email)    // → { id }; email_confirm: true, NO password,
                                    //   app_metadata: { gymloop_provisioned: true }
  bindMember(tenantId, memberId, userId, expectedEmail)
  bindStaff(tenantId, staffId, userId, expectedEmail)
    // one conditional UPDATE: tenant_id, id, user_id IS NULL, AND the row's email equals expectedEmail
    // (trimmed, case-insensitive; LIKE wildcards must be escaped if ILIKE is used), AND still eligible
    // (member: status not cancelled/blocked and erased_at IS NULL; staff: is_active AND role <> 'gym_owner').
    // → number of rows changed
  unbindMember(tenantId, memberId, userId)   // user_id := NULL where tenant_id, id AND user_id = userId → rows changed
  unbindStaff(tenantId, staffId, userId)     // same for staff
}
```

**New and changed requirements**
- **PROV-006a (reuse only a verified identity).** An existing Auth user found by email may be reused only if
  `provisioned` is true, or `googleVerified` is true **and** `hasEmailIdentity` is false. Otherwise the tool
  returns the new refusal code **`identity_unverified`** with no writes (an operator must investigate: the
  account may have been self-registered by someone who does not own the address).
- **PROV-006b (already linked means exactly one binding).** `already_linked` is returned only when the target
  row's `userId` equals the found Auth user **and** `countBindings` reports exactly one binding in total
  (members + staff + platform = 1); otherwise `identity_bound_elsewhere`.
- **PROV-007a (bind re-asserts the checks).** Apply passes the request email as `expectedEmail` to the bind
  method; the adapter's conditional update re-asserts email and eligibility, so a row edited between the read
  and the write is not bound (the bind returns 0 → `bind_conflict`).
- **PROV-011 (post-bind verification).** After a bind returns exactly 1, the tool calls `countBindings(userId)`
  again. If the total is not exactly 1 (a concurrent run bound the same identity elsewhere), it calls the
  matching unbind method for this row once, applies the PROV-008 compensation (delete a user created in this
  run), and returns `bind_conflict`. If the verification or unbind itself throws, the tool reports
  `bind_conflict` (never `linked`) and rethrows nothing secret.
- **PROV-012 (fail closed on lookup errors).** Any thrown port error during checks yields `ok: false` with a
  generic code (`lookup_failed`), no writes, and no secret or raw email in the result.

`ProvisionResult.code` gains `identity_unverified` and `lookup_failed`.

**Operational precondition (ADR-173, not enforced by the tool):** public Auth signup is disabled on the
project before real testers are provisioned, so nobody can pre-register a tester's address.
**Operational rule (not enforced by the tool):** one operator runs the tool, one invocation at a time. PROV-011
is defence in depth against an accidental concurrent run — it fails closed (both runs may unwind and report
`bind_conflict`; re-running one of them is safe) — not a substitute for a database-level lock. A global
one-identity-one-row invariant enforced in the database is a separate, migration-level change if the tool
ever runs unattended or concurrently.

## Amendment 2 (2026-09-24, second critic NO-GO) — clarifications, no new behaviour
- **PROV-011 is symmetric:** for both the create and the reuse path, the post-bind total must be **exactly 1**;
  0 or more than 1 unwinds (unbind this row once) and returns `bind_conflict`. A post-bind 0 is never a link.
- **`countBindings` shape is strict:** it returns all three numeric fields `members`, `staff`, `platform`; a
  missing, null or non-numeric field is a lookup failure (checks → `lookup_failed`; post-bind → `bind_conflict`
  with unwind). Nothing is coerced to 0.
- **Bind email predicate:** a case-insensitive exact match of the stored value against the trimmed request
  email (LIKE wildcards escaped). A stored email with surrounding whitespace therefore fails closed as
  `bind_conflict`; staff fix the record and re-run. Eligibility and identity filters are applied to the
  UPDATE's filter builder (supabase-js: `from(t).update(v)` returns the builder that has `.eq/.is/.not/.ilike`).
- **Directory cap:** `findAuthUserByEmail` throws only when more users exist beyond the page cap (it may fetch
  one extra page to find out); an exactly full last page is not an error.
- **The adapter is tested too:** `createSupabaseProvisionPort` must pass tests that drive it with a fake client
  whose builder API matches supabase-js v2 (filters exist only after `select()`/`update()`/`delete()`).
