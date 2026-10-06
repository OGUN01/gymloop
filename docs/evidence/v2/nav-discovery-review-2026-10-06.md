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

The follow-up independent regression commits **8d823864** and **1f97a8fb** pinned eight refresh/legibility/navigator failures plus two malformed-array routing failures before their repairs. The original reviewer returned **scoped GO** after all repairs, including consistent exact-scalar route parsing. Full native visible verification now passes **59 files, 697 tests** with two workers. Full shared verification passes **30 files, 1,071 tests**; full web verification passes **180 files, 4,496 tests**. SQL runtime, device/visual and final CI remain excluded.

Local lint, registry, escape-hatches (957 files), rollback (161 files), duplication (461 files, zero clones), dependencies (937 modules, zero violations), renewal-window synchronization and strict OpenSpec 1.14.1 all pass. Knip passes when launched with the existing env-file; its bare script emits an unchanged Playwright configuration load error despite exit zero. OpenSpec overlength requirements were shortened without changing approved clauses; compatibility edge cases remain explicit scenarios.

The wider root suite initially passed **4,712/4,760** across 125 files. Forty-six older held native Classes cases lacked new standard focus interfaces, and one held hub case asserted the previous expanded purchase presentation; a separate implementation-blind held author is updating those interfaces/approved IA without reading visible tests or production. One unchanged 50,000-identity load-fixture assertion exceeded Vitest's generic 5-second default on Windows. The same assertions pass 16/16 with a diagnostic 30-second runner budget (14.42 seconds total); the original default local gate remains FAIL. HARD-004 has no planner-latency requirement, and unchanged baseline Ubuntu CI **37409128878** passed the default script step. No timeout policy or CI gate was edited or waived. Requirement coverage reports 132/160 with 28 existing gaps; it excludes in-flight NAVC requirements and is not full coverage proof.

Fresh old-artifact captures [Home](../screens/2026-10-06-device-nav-before-awake.png) and [Shop](../screens/2026-10-06-device-shop-before-awake.png) confirm the seven-tab bar and reservation-first clutter on the connected test app. They are before evidence, not acceptance of the new implementation.

The independent held author completed and committed the three existing native fixture/IA amendments at **5d1db4d2**; their focused result is **135/135**, with no implementation or visible-suite reads. The subsequent full root diagnostic run passed **4,761/4,763**, 124/125 files. Both remaining failures were explicit 20-second timeouts in an unchanged HARD-004 campaign held suite during the native build; no assertion mismatch was reported. Isolated re-verification is pending after the build. The earlier default-budget failure remains recorded; no test or timeout policy was changed.

Implementation is committed locally at **a4d1481f**. C:/gc is safely detached at that commit after preserving and verifying its two previous local deltas in an owner-only backup; the direct Gradle v2check/debug-signed build is running. Nothing has been installed or pushed yet. Compact reference matching still requires device and visual review.

## Deployment boundary

Prior DB run 37409145394 is still active. No competing local SQL sweep, manual migration apply or generated-type edit has occurred. The new schema metadata intentionally remains unavailable until CI applies the migration and the authorized CLI regenerates it. Expo generated the local announcements route types through its offline development command; mobile typecheck now reports only the four new RPC metadata errors. Final CI, SQL runtime and exact-artifact OnePlus evidence remain required.
