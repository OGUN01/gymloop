# Native navigation and Classes discovery review — 2026-10-06

## Independent static security review

Fresh class_discovery_final_blind_critic, separate from all builders and test authors, returned **GO: no P1/P2 findings** for the new migration and shared/API boundary against NAVC-004/005/013/014/015 and CLS-026/028. The critic read no visible or holdout tests, implementation progress/handoff notes, prior critic notes, execution logs or Cloud/schema state. Owner editor and runtime acceptance were excluded.

The review verified canonical active actors and authenticated audience, tenant isolation, missing-settings failure, direct-field protection, serialized audited saves/no-op retry, one-clock historical qualification, the absolute 28-day own-commitment projection, preserved cancellation facts, unchanged eligibility/settings/RLS/grants, function ownership/search paths, supporting indexes, strict boolean API and malformed-read null handling. The migration is still unapplied; this verdict is not SQL runtime proof. An earlier advisory critic accidentally saw visible search snippets and is not used as the required independent blind verdict.

## Independent native integration review

Fresh native_nav_integration_reviewer read production against the approved spec without opening tests or holdout, accessing Cloud or installing a device build. Four focused suites executed: **57 tests passed**. Four P2 findings require repair and re-review:

1. Keep the navigator subtree stable across a cached visibility refresh failure/retry, preserving contextual drafts and confirmations.
2. Refresh timetable and own commitments on screen focus and app resume, preserving caller lifetime guards.
3. Show complete start/end, branch, instructor and timezone in wrapping session details rather than permanently truncated Row metadata.
4. Use the current existing palette for Freeze text on Dark, preserving theme tokens and command payloads.

The first broad mobile run passed 673/687. Three auth/provider suites passed 28/28 when rerun with two workers; the initial timeouts came from concurrent worker startup. Two legacy screen suites require independently authored fixture/approved-layout amendments, preserving offline/privacy/cancellation and integer-money assertions. No acceptance gate is marked passed from this partial result.

## Deployment boundary

Prior DB run 37409145394 is still active. No competing local SQL sweep, manual migration apply or generated-type edit has occurred. The new schema metadata intentionally remains unavailable until CI applies the migration and the authorized CLI regenerates it. Expo generated the local announcements route types through its offline development command; mobile typecheck now reports only the four new RPC metadata errors. Final CI, SQL runtime and exact-artifact OnePlus evidence remain required.
