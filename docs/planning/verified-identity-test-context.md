# Verified identity I/O fixtures

Public fixture metadata for independent app authors, 2026-10-03. This documents
the existing registered identity seam; it adds no authorization or requirement.
Authority: `phase6-identity-contract.md` and
`openspec/specs/identity-navigation/spec.md`. Authors need no classifier body.

`GymloopIdentity` has these exact classified shapes; every identifier is a valid
UUID, and forbidden audience fields are absent:

- staff: `{ kind: 'staff', userId, tenantId, staffId, role }`, where role is the
  generated `StaffRole` (`gym_owner`, `gym_manager`, `front_desk`, `trainer`).
- member: `{ kind: 'member', userId, tenantId, memberId }`.
- platform: `{ kind: 'platform', userId, role }`, where role is generated
  `PlatformRole` (`super_admin`, `platform_support`).
- impersonation: `{ kind: 'impersonation', userId, tenantId,
  impersonationSessionId }`.
- unlinked: `{ kind: 'unlinked' }`.

Mock `readIdentity`/`readRequestIdentity` with their existing context object:
`{ supabase, signedIn, authenticatedUser, identity }`. A verified positive
context sets both booleans true and carries one complete classified identity.
A missing session sets both false and carries unlinked identity; it is not a
null I/O result. A genuinely authenticated but unlinked account is distinct
from a missing session; preserve each test's intended scenario.

There is no context `audience` field and no exported `VerifiedAudience` type.
The existing `requireAudience` result exposes its passed caller's Supabase
client and correctly narrowed identity. Type-only imports of registered
`GymloopIdentity`, `StaffRole` and `PlatformRole` are sufficient for fixtures.
Do not read production function bodies to author expected behavior.

Unsigned, contradictory or incomplete raw claims belong in classifier/transport
tests; do not disguise them as an already-classified valid success identity.
Keep failures, role refusals, body-order checks, caller scope and existing
assertions unchanged when correcting a fixture representation.
