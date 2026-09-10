# Phase 6 identity and navigation — verified

The frozen NAV-001..005/007 contract gives every complete verified identity one
home, adds real member and platform read surfaces, removes stale Gymloop claims
on every access-token-hook result, and makes support preview read-only in the
screen, API and database. NAV-006/008 remain in the later platform slice.

## Independent tests first

Visible and holdout authors worked implementation-blind and did not read each
other's suites. Their red commits precede production source. The final identity
set covers the pure classifier and exact money display, verified API sessions,
role entry pages, preview controls, own-session ending, hook fallback cleanup,
and metadata-complete preview write guards. The database suite contains 53
rollback-wrapped files.

Two authoring commits (`9d0fe21` and `2cb3440`) combined tests with test-runtime
configuration and therefore failed the push-range immutability checker even
though they contain no product implementation. The implementation is isolated
in `52e44c4`. A later documentation-only push checks only its own push range and
records a clean gate result; it does not retroactively change the historical
authoring-workflow failures.

## Candidate checks and critics

The full local TypeScript suites pass: 716 web tests and 123 shared tests. Type
checking, lint, production build, dependency boundaries, dead-code analysis,
registry lint, escape-hatch checking, rollback checking and duplication analysis
all pass. Strict validation of the change specification passes.

The full candidate Cloud sweep passed all 53 visible and holdout pgTAP files,
4729 assertions, with zero failures and every declared plan complete. The
identity migration was replayed inside each test transaction and rolled back.

A fresh Astra security critic initially found that the end-preview refresh
failure path relied on the SDK's local sign-out succeeding. The route now also
expires every matching Supabase auth-token base/chunk cookie on its 303 response.
The critic reproduced expired-token, rejected-refresh and rejected-sign-out
cases and returned GO: all auth cookies were removed, unrelated cookies remained,
and the success path was unchanged. A separate Astra UI review returned GO for
the Phase 6 working-screen bar; its visual refinements are inputs to Phase 7.

## Real browser acceptance and cleanup

Real Supabase sessions exercised the deployed access-token hook and the local
Next application. The gym owner, front desk and trainer each reached `/console`
with the correct audience label. The member reached `/member/add-ons`, saw the
active gym catalogue with exact rupee values and an own-order empty state. The
super admin and a temporary platform-support identity reached `/platform`; the
support surface was labelled read-only and contained no mutation controls. A
temporary Auth user with no identity row reached `/not-linked`.

A temporary live super-admin preview reached `/console` as Support preview. Its
sticky red banner named Iron Box Fitness — Vijay Nagar, showed expiry in
Asia/Kolkata, and kept End preview available. The new-member screen rendered no
write form, while the check-in screen left search usable and disabled every gate
and check-in mutation control. End preview wrote the own-session end, refreshed
the identity, and a fresh real session reached `/platform` as Platform admin.
Direct write refusal and exact own-end behavior are additionally proven by the
visible and independent holdout database suites.

Acceptance created exactly two temporary Auth users, one platform-support row,
one preview session and its two database-authored audit rows. Cleanup compared
the support row and preview identity against their full recorded manifests,
removed exactly those rows and users, then verified both emails and all recorded
ids were absent. The local manifest and bootstrap script were also removed.
No seeded demo identity, member, money row or document counter changed.

## Delivery

Implementation commit `52e44c48a7fe19117f654101efc0328ac9da1fe3`
passed main CI `34466593301` and holdout `34466593296`. Database workflow
`34466593342` applied the migration, matched generated types, passed all 53
rollback-wrapped pgTAP files / 4729 assertions, and passed the seed dry run.
The historical immutability failures on mixed test-runtime authoring commits
remain recorded above; the documentation-only archive push is checked on its
own range and records its own result.
