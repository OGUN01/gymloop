# Existing account exit on unresolved discovery

2026-10-06 device finding: the first unconfirmed Classes read currently gates the member tab navigator, leaving only Retry and no account exit. Owner-approved UI edge-case work requires keeping account switching reachable without deleting test-app data or bypassing verified identity.

`MemberLayout` reuses `useMobile().signOut(): Promise<void>` through an existing quiet native action when `ready === true`, `identity.kind === 'member'` and visibility is unresolved. It is available during initial loading and initial read failure. Existing Retry remains. An unverified identity or wrong role receives the existing loading/redirect behavior.

This adds a UI entry point only. MobileProvider, session resolution, claims, cleanup/cache functions and the visibility hook remain byte-identical. No new exported symbol, number, authenticated capability or API is introduced. A confirmed value keeps the existing stable navigator and contextual screens.

Independent tests use the public context/signOut contract and runtime-import MemberLayout; do not read its implementation or private suites. Assert one call to the existing action, retained Retry, no tabs/false Off during unknown state, and preserved unverified/wrong-role behavior.
