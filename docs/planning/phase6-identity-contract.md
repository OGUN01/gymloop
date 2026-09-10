# Phase 6 identity and navigation slice

Planning contract under ADR-111. Implement only after Phase 5 is verified and
archived. This is the first Phase 6 slice because every later screen and route
needs the same caller classification. It inherits the cross-cluster decisions
in `phase6-contract-seam.md`; no independent author is dispatched until review
has settled this file.

**First-slice scope:** NAV-001 through NAV-005, NAV-007 claim cleanup, and the
database preview-write boundary. NAV-006 gym eligibility/revocation and NAV-008
commercial controls land together in the later platform slice, before status
controls are exposed. They are fixed phase-wide requirements below, not claims
that the initial read/navigation slice already implements them. The first
slice changes no organization status semantics and adds no public RPC, so its
private hook/preview changes do not invent a public database type dependency.

## Observable requirements

- **NAV-001** WHEN a verified session has one complete identity shape THE
  SYSTEM SHALL route it to its role's working home. Missing or contradictory
  Gymloop claims SHALL route to not-linked and authorize no mutation. A caller
  with no verified session SHALL be sent to sign-in.
- **NAV-002** THE SYSTEM SHALL use one pure classifier and one home selector
  from sign-in, the signed-in sign-in page, root, not-linked, layouts and API
  session helpers. Staff SHALL reach `/console`, member `/member/add-ons`, and
  platform `/platform`. A navigation link SHALL not be treated as authorization.
- **NAV-003** WHILE impersonating THE SYSTEM SHALL render the target gym's
  read surfaces with a persistent red banner naming the gym and expiry, and
  offer “End preview”. It SHALL permit only ending the caller's own session
  among product mutations and SHALL never infer a staff/member id.
- **NAV-004** WHEN an impersonation ends THE SYSTEM SHALL update only the
  session id in verified claims under the existing own-session RLS policy,
  refresh Auth claims, and return to platform. If refresh fails THE SYSTEM
  SHALL clear the local session and request sign-in, rather than continuing
  with stale preview claims.
- **NAV-005** THE SYSTEM SHALL serve the member's active catalogue and own
  orders under the member session and a real fleet list under platform RLS
  in the same slice as routing. Support SHALL have no mutation controls.
  Both read pages SHALL handle empty results and backend failures explicitly.
- **NAV-006** WHEN a gym is pending approval, suspended, closed or an expired/malformed trial THE SYSTEM
  SHALL issue no fresh gym-side identity for it. A super admin's explicitly
  requested support preview remains permitted. Organization changes to
  suspended/closed SHALL revoke linked staff/member refresh sessions; the
  existing access token remains usable for at most fifteen minutes.
- **NAV-007** WHEN the hook resolves any identity or fails to resolve one THE
  SYSTEM SHALL remove stale Gymloop keys before returning claims, preserve
  reserved Auth claims, and retain the existing platform/staff/member
  precedence and deterministic requested/default tenant choice.
- **NAV-008** THE SYSTEM SHALL protect organization commercial fields before
  making them an access-control input. Only a non-impersonating super admin
  may change status, tier, trial or activation fields. Suspended gym owners
  SHALL NOT reactivate themselves during the residual access-token window.

## Complete claim shapes

Recognized identities require a valid UUID Auth subject and canonical generated
app_role. UUID fields must be actual valid UUID strings, not merely nonempty
strings. Extra reserved/non-Gymloop claims are ignored. A forbidden Gymloop key
must be absent or JSON null; a blank or malformed string is contradictory.

| Kind | Required Gymloop keys | Forbidden nonnull Gymloop keys |
|---|---|---|
| staff | role is gym_owner, gym_manager, front_desk or trainer; tenant_id; staff_id | member_id, impersonation_session_id |
| member | role member; tenant_id; member_id | staff_id, impersonation_session_id |
| platform | role super_admin or platform_support | tenant_id, staff_id, member_id, impersonation_session_id |
| impersonation | role gym_owner; tenant_id; impersonation_session_id | staff_id, member_id |

The role subset is checked against the generated database enum, not a new
canonical status vocabulary. Unknown roles, partial shapes, two simultaneous
identities and invalid identifiers classify as unlinked. No table query is
needed to classify already signature-verified claims. The fifteen-minute
database revocation window remains explicit.

## Existing API compatibility

`staffSession`, `staffForm` and `staffFormParsed` keep their existing envelope
and invalid-form behavior. They now require a complete real-staff shape and
return its generated role in addition to tenantId/staffId/supabase. An optional
allowed-role argument supports the explicit guards required by new routes;
the omitted argument admits the four real staff roles, leaving existing table
permissions intact. Rejection occurs before a database mutation or RPC.

Existing callers that previously constructed minimal test JWTs must supply
valid complete staff claims in their independent fixtures. This is a stronger
identity contract, not permission to change unrelated route expectations.
Missing verified identity remains unauthorized/not_signed_in. A complete
identity refused by an explicit role gate is forbidden/not_permitted.

Add `memberSession` and `platformSession` with the same failure-envelope
convention. Member session returns only member identity and tenant; platform
session returns platform role and subject with no fabricated tenant or staff.
The platform write form path requires super_admin; support remains read-only.

## Database scope and coupling

Preserve the hook's existing privileges, empty search path and reserved claims.
Its cleanup applies to all early returns and its exception fallback. The hook
must continue to return a supported claimless identity rather than turning a
row-resolution error into a global sign-in outage.

Organization status is not safe to enforce in the hook before protecting it
from gym-side writes. The later platform migration therefore ships eligibility,
commercial-field guards, transition graph, status RPC, mandatory reason, audit
and activation prerequisites together. The initial navigation slice preserves
the existing status semantics and exposes no status mutation UI. Once the
platform slice lands, direct super-admin table writes also obey the graph and
commercial invariants; a route is never their sole enforcement boundary.

No new impersonation end RPC or policy is required. The existing own-session
policy, end audit trigger and hard TTL remain authoritative. Read-only preview
is also enforced for direct authenticated database mutations by the private
invoker preview guard described in the seam. Preserve read policies and the
exact own-session end exception. Every new elevated callable RPC must reject
impersonation explicitly before its write capability is used.

## Read-surface scope

The member catalogue explicitly selects active offers and shows the required
price, currency, validity and terms. An incomplete legacy offer is labeled
unavailable for sale pending catalogue completion; do not invent qualification
or cancellation text. Own orders show status and usage even if their product
is now inactive. Member responses must not expose other members' orders.
Read bigint prices/totals with PostgREST projection casts (`price_paise::text`, `unit_price_paise::text`,
`total_paise::text`) so JSON never rounds a stored price before formatting.
This is supported by the primary [PostgREST casting documentation](https://docs.postgrest.org/en/v14/references/api/tables_views.html#casting-columns)
and needs no new public RPC or hand-written database types.

The baseline fleet shows each gym's name, code, status, tier and local trial
expiry, with support/read-only labeling. Full metrics, onboarding and controls
arrive in their later slices. The page must identify missing provider setup or
pending owner access truthfully where it reports them; a count not implemented
yet is omitted, never displayed as zero.

## Verification boundaries

Use implementation-blind visible and holdout authors for both the pure/API
claim behavior and the database hook/status boundary. Holdout JS tests remain
unread by implementers just like SQL holdouts. Commit tests before source.
Keep JavaScript holdout source under `supabase/tests-holdout/web/`; its author
may add a minimal import-only `.test.ts` entry in the existing web test tree so
the unchanged Vitest command executes it. This preserves the established
holdout directory boundary without suppressions or a second test command that
CI could forget. The bridge and holdout are owned by the independent author.
Test all seven roles, missing/contradictory shapes, reserved-claim preservation,
stale-claim removal on success/fallback, existing deterministic tenant selection
and direct preview-write refusal with the own-end exception. The later platform
suite adds eligible-gym selection, expired trials, real/impersonated suspended
gyms and organization refresh revocation.

Browser evidence must show real staff, member, platform support/super admin,
unlinked and impersonating navigation, including end-preview refresh. Reuse
demo identities where available and clean only exact temporary rows created
for the exercise. This slice does not create a new Auth invitation workflow.

## Fixed first-slice TypeScript seam

Search and register these symbols when implemented; the current registry has
no complete classifier or role-aware home selector. The file owner is
`apps/web/lib/identity.ts`:

- `StaffRole` and `PlatformRole` are subsets extracted from the generated
  `Database['public']['Enums']['app_role']`, not hand-written canonical enums.
- `GymloopIdentity` is discriminated by kind. Staff includes userId, tenantId,
  staffId and role; member includes userId, tenantId and memberId; platform
  includes userId and role; impersonation includes userId, tenantId and
  impersonationSessionId; unlinked has only its kind.
- `classifyIdentity(claims: unknown): GymloopIdentity` is pure and performs no
  session lookup. It accepts only the complete shapes above.
- `identityHome(identity: GymloopIdentity)` returns the exact home path in
  NAV-002 (impersonation shares console; unlinked uses not-linked).

The API module preserves existing wrapper signatures, extending them as
`staffSession(allowedRoles?: readonly StaffRole[])`,
`staffForm(request, allowedRoles?)` and
`staffFormParsed(request, schema, allowedRoles?)`. StaffSession carries userId
and role alongside its existing fields. Every flattening wrapper preserves
both additions. `memberSession()` returns its complete member identity plus
Supabase client in the existing `{ session } | { failure }` envelope.
`platformSession(options?: { requireAdmin?: boolean })` does likewise;
requireAdmin refuses support before a write. These helpers consume verified
claims through the existing server client and classifier.

`POST /api/impersonation/end` accepts no target id from the body. It derives the
session id from verified impersonation claims, performs the existing allowed
end update, refreshes Auth, and returns a 303 to `/platform`. A caller that is
not impersonating is refused before a write. Native row-policy and immutable
session rules remain responsible for ownership and non-end fields.

No new project SQLSTATE is needed for the initial navigation slice. Preview
mutation refusal uses PostgreSQL insufficient_privilege (42501), which the
existing API already maps. GL049–GL051 are reserved for the later platform
commercial/transition/activation contract; GL052–GL058 belong to add-ons.

## Exact money display extension needed by the read screen

Extend the registered `rupeesFromPaise` in its current shared module to accept
`number | string`, preserving every existing safe-integer number result. A
string must match `^(?:0|-?[1-9][0-9]*)$` (zero or a canonical signed nonzero
integer, excluding -0); reject invalid strings with TypeError.
Reject a non-safe-integer number with RangeError. Format arbitrary-size strings
exactly to two rupee decimal places using the existing PAISE_DIGITS and
PAISE_PER_RUPEE constants, including zero, negative fractions and values beyond
JS safe integer. Do not add a second money formatter or change paiseFromRupees.
The independent money tests for this extension are committed before source
alongside the first slice's identity tests. All later Phase 6 money read screens
reuse the same formatter and string projections/RPC outputs.
