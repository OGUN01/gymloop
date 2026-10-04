# NTF visible historical test correction — independent contract adjudication

Date: 2026-10-04. Verdict: **GO for the scoped test-only correction.**

This is a fresh, implementation-blind adjudication of the visible test delta,
not certification of the original authors' independence or of historical
tests-first execution. I cannot establish those authors' provenance. I read
AGENTS.md, the frozen NTF proposal, transport and pre-configuration amendments,
the Wave C serial freeze declarations, and the delivery-declarations draft
whose error precedence the freeze expressly adopts. I inspected the original
`supabase/tests/78_push_delivery.sql` at
`afe660c8730da40c4b7cb438c03f8871eedc331f` and only that test path's delta in
`5aab604737e9bb4079f4ec127eecad2ec6be9b74`. I also searched public
`docs/data-model.md` for relevant schema/visibility terms. I read no
implementation source, migration, holdout suite or private receipt. I used
no Cloud, browser or device, ran no SQL, and made no commit or test edit.

## Scope and counting

The inspected delta changes six assertion lines: four bigint expected operands,
one count operand cast, and one campaign refusal assertion. The last assertion
has two edits (SQLSTATE and description), giving seven individual textual
changes. There is no seventh changed assertion in this delta.

| Original test line | Change | Contract adjudication |
|---|---|---|
| 134 | Replay expectation `1` becomes `1::bigint` | GO. The proposal's public data contract explicitly declares `member_devices.token_revision bigint`. The same replay, queried row and expected numerical value remain. |
| 137 | Rotation expectation `2` becomes `2::bigint` | GO. Same declared bigint column; increment expectation remains exactly two. |
| 138 | Frozen revision expectation `2` becomes `2::bigint` | GO. Same declared bigint column; no predicate or value changes. |
| 178 | Legacy adoption expectation `1` becomes `1::bigint` | GO. Same declared bigint column; revision-one expectation remains exact. |
| 189 | Foreign-installation `count(*)` becomes `count(*)::integer` | GO. The exact zero-row expectation and installation predicate remain. A count cast cannot turn a positive count into zero; an out-of-range count fails rather than passing. This is operand type alignment, not removal of the invisibility assertion. |
| 364 | Unknown campaign expectation `42501` becomes `P0002` | GO. The frozen error precedence explicitly adopts actor/context denial `42501` first, then argument validation, then indistinguishable foreign/absent target visibility `P0002`. This assertion already installs the valid gym-owner actor and supplies a non-null UUID. It reaches the target-visibility stage. The old expected SQLSTATE contradicts that frozen allocation. |
| 364 | Description adds “target-invisible” | GO. This accurately names the frozen target-visibility stage and retains the unknown/foreign indistinguishability claim. |

The bigint type conclusion comes from the frozen public schema declaration,
not inspection of the deployed column or migration. The original visible
suite itself also contains an unchanged `int8` shape assertion. Provider
message identifiers remain textual facts under the frozen transport facade
(`p_provider_message_id text`); none of these edits changes provider types,
provider evidence or delivery expectations.

## What this verdict establishes

No assertion is removed, bypassed, changed to a permissive match or numerically
relaxed. The test plan, fixtures, actor claims, lookup predicates, transaction
wrapper and rollback remain untouched by the inspected delta. The five casts
preserve the tested propositions. The SQLSTATE correction restores the
already-frozen contract; it does not create a new requirement needing a
`spec:` change.

The description's foreign/unknown claim is stronger than this individual
unknown-target case proves: the changed assertion executes only an unknown
campaign. This was already the original assertion's limitation and is not
introduced by the correction. This verdict is scoped to the historical delta,
not a claim that the complete suite exhaustively proves target
indistinguishability or that all unrelated original assertions are correct.

A test-only commit followed by a source-only commit can accurately represent
the reconstructed ordering of unpublished history. This adjudication does
not establish an original red run, authorize rewriting published history, or
erase the original mixed-commit provenance. Keep that provenance explicit.
No runtime green, deployment, provider delivery or live gate closure is
claimed here.
