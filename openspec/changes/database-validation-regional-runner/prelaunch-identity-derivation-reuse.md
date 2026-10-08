# Existing HARD-004 fixture validation: bounded UUID derivation reuse

Frozen by root on 8 October 2026 before this source repair. This preserves the approved HARD-004 fixture-planning contract in phase8-hardening/plan.md; it adds no export, product requirement, SQL operation, database run, dependency or acceptance exception.

The actual complete serialized tooling run collected the same 168 files and 8,218 cases, with 8,217 passed, one failed and zero pending. The historical Windows PS5 suite passed all eight cases. Only the independently authored, unchanged prelaunch fixture validation case exceeded its existing five-second deadline (5,840.99ms). Full report0e2bfadce73670c378accb8cf05f8f40f25409133e42854c667ce4d8445fc193, aggregatec8a9e4b6f37b44245f7342520bfbe2009690aa0846af07a203fc35355d043e7c and scope5d1e3684086369e03ba3151ea83904dfa5495e52d70b9bba7219942f11ca0ca0 retain that genuine pre-repair failure. The existing visible and holdout tests precede this repair and remain byte-immutable; reuse their original EARS oracles and a fresh source-only critic rather than writing assertions that mirror a cache implementation.

## Preserved behavior

- WHEN a valid marker is supplied, the public builder shall return the same complete deterministic identities in fresh object trees; caller mutation shall not affect later calls.
- WHEN either SQL renderer receives a plan, it shall continue validating the entire recovered plan, rejecting malformed, foreign, changed or incomplete identities and rendering only from a fresh trusted canonical tree.
- WHEN markers differ, including only in case, identity namespaces shall remain distinct. Invalid markers shall still be rejected before derivation.
- The four exported signatures, marker grammar, exact top-level fields, property order, both complete JSON serialization calls and their order, source of canonical SQL, Auth binding validation and all SQL bytes remain unchanged.

## Smallest implementation boundary

Memoize only the immutable UUID strings produced by existing private plannedUuid/uuidFrom. A single private plannedUuidCache retains one exact marker and a map keyed by the unchanged complete seed (marker, kind and gym/member indices). An exact marker change clears the map. Only successful deterministic UUID strings enter it; never cache a caller object, canonical tree or serialized plan.

The unchanged private builder loops are the sole callers and bound retained keys to the existing fixed hierarchy: gymCount times four gym identities plus membersPerGym times two member identities, currently100,400. No shared constant or new numerical limit is needed. Keep uuidFrom, all fresh object construction, assertPlan, candidate-then-expected serialization and both SQL renderers unchanged. A future caller that expands this private derivation boundary must re-establish its retention bound.

Registry search found no reusable bounded synthetic UUID cache. The runtime readiness/guardian caches serve different identities and cannot be reused without coupling unrelated security boundaries. Register the new private state before construction. Preserve all three failed complete runs; require unchanged original suites, exact outputs, source-only critique and a new complete zero-failure local result before the coherent implementation push. No trial10 admission, Cloud native/seed run or Play upload is authorized by a merely focused pass.
