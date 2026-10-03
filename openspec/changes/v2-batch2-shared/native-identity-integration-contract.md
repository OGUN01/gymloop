# Existing native identity guarantees — batch-2 integration

Status: delegated integration of frozen INV/SHP/ANC privacy and current-caller
requirements, 2026-10-03. No claim, audience, privilege, authentication provider
or business-rule change. Existing SDK/session locking remains authoritative.

## Private feature cleanup

The current `MobileProvider` is the integration boundary. Authentication
replacement, unresolved ownership, sign-out and provider teardown immediately
revoke the preceding feature work. Before publishing a different verified
member/tenant/user, clear the previous Shop memory and announcement cards/read
queue. Old asynchronous results cannot recreate them after cleanup completes.
An initial same-owner offline cache remains usable only through the existing
complete-scope checks; no unknown/other-owner cache becomes visible.

Use existing `clearShopCache()` and its synchronous cache lease invalidation.
Add only `clearAnnouncementCache(): Promise<void>` to the registered native
announcement cache module. It synchronously invalidates preceding cache work,
then removes the existing SecureStore value in the same serialized order as
writes. A paused old write/receipt continuation cannot restore it after clear.
Fresh work started for the new current scope may save normally. No new key,
storage dependency or persisted Shop cache is introduced.

Private cleanup errors must not prevent the existing Auth sign-out operation
from being attempted. Preserve the existing completed-sign-out guarantee and
honest failed-sign-out behavior. A failed privacy-critical cleanup cannot
publish another linked caller; preserve the existing offline-check-in protections
and business-word cleanup rather than replacing those lifecycle rules.

## Caller-bound native transport

`useMobile().api` is an operation capability for its current verified session,
not permission for a retained former screen to borrow a replacement caller's
token. Revoke preceding capabilities synchronously when Auth replacement,
sign-out or teardown begins, including while claims/session resolution awaits.
If token acquisition pauses across replacement, the old action must not send
using the new user's token or act as that new caller. A newly published current
capability still uses the existing API client and routes. Preserve legitimate
current authenticated-unlinked invite/recovery calls; do not introduce a member
audience gate or second claim parser.

No new server privilege, route, credentials, SDK lock/interceptor or identity
storage is added. Existing server caller checks remain authoritative. Independent
visible and held authors test the public provider/cache/API seams before a
separate integrator touches source, preserving all earlier identity regression
suites. Real logout/account switching and Android remain final acceptance work.
