# DBV-002/004 native query-result reporting compatibility

Frozen by root on 8 October 2026 before independent regressions or implementation. Actual hosted run37563272622/attempt1 at8727213ec47b8136c8332c6e757015a3075dbb33 remains failed. Authenticated retained evidence reproduces its final receipt exactly: native exit0,163 unique file headers,16329 assertions,zero failed assertions,one matching plan and timer per file,one successful aggregate and final Result: PASS. The reporting verifier marks113 files incomplete solely because their native verbose output includes non-TAP SQL query results. No intrinsic TAP shortfall, changed test hash or missing timer exists. The separate structural proof is1554da233340e2c2b5a6efa2e099d90ae1810e221d3416f34d97e87e1c7f5a0b; no assertion descriptions or plaintext transcripts were published.

The [TAP specification](https://testanything.org/tap-specification.html) distinguishes unknown non-test output from test points and plans. The unchanged pinned native client remains verdict authority. This repair changes only the existing private parseNativeOutput reporting boundary; it does not normalize raw output, edit SQL, replace pg_prove, alter reporting flags or introduce another checker.

## Frozen compatibility behavior

Within a recognized unique native file block, ordinary non-TAP query-result output may appear before the plan, between assertions or after assertions. It shall not count as a test, plan, timer or success marker, and shall not by itself mark the file incomplete. This includes synthetic JSON/object/array, numeric, boolean, UUID, timestamp and ordinary text rows. No query result may establish success or fill a missing native fact.

Malformed or duplicate native control records remain refused: test-point prefixes (`ok` or `not ok`), plan prefixes (`1.`), TAP version prefixes, per-file timing records and aggregate/result/success framing must still satisfy their existing grammar, count and ordering requirements. Existing recognized native SQL/client errors, bailout, failed native exit, incomplete process, failed assertions, missing/extra files/plans/assertions/timers, changed hashes, wrong totals, failed cleanup and unknown output outside a file block remain red. Retain every current predicate outside this narrow non-test-output distinction.

Acceptance still requires the full unchanged native stream and successful process, every manifest file and exact per-file plan/sequential assertion/timer, zero failures, exact aggregate and final native PASS, unchanged hashes and independently verified cleanup. Arbitrary query-result rows alongside an incomplete or failed run cannot turn it green. The original failed run is not reclassified; the correction requires fresh complete native confirmation before release or performance acceptance.

## Independent tests first

Fresh visible and held authors use only the frozen public buildNativePgtapManifest and verifyNativePgtapRun interfaces in design.md and synthetic nonpersonal data. Do not read implementation, existing tests, SQL bodies or the other author. Cover a complete native transcript with query-result rows in all three positions and prove the candidate receipt remains accepted with exact counts/timers; positive cases must fail against the current implementation before any source change. Independently cover the failure boundaries above with result noise present. Tests may import existing shared constants; register any new private fixture helper before writing it. Preserve red receipts and immutable assertions; root never opens held assertions. No Cloud access or real credentials are needed.

### Public native reporting grammar clarification

Before accepted red receipts, both authors requested the missing native stream ABI. An early visible draft preceded the pause and received this grammar correction before its genuine red run; no accepted oracle or production code was changed. Authors may independently obtain the syntax from the fixed client using only a synthetic stub, network-disabled disposable container and their own fixture files. The timestamped verbose header is `[HH:MM:SS] <manifest path> <one or more dots>`; an absolute native path ending in the manifest path is also valid. A file has one `1..N` plan, numbered `ok`/`not ok` test points in sequence and one native footer `ok <integer milliseconds> ms (<native timing text>)` or its failed `not ok` counterpart. A timestamp-only line ends its block. After all files, the native output has one `All tests successful.`, one `Files=<file count>, Tests=<point count>, <native timing text>` and one final `Result: PASS`. Synthetic nonpersonal structural example for a single file block:

```text
[01:02:03] supabase/tests/synthetic-query.sql ....
1..2
ok 1 - synthetic first point
ok 2 - synthetic second point
ok 25 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
[01:02:04]
```

Complete manifest fixtures still include both suite directories and a matching full aggregate; the example is a block, not a complete accepted receipt. This supplies native structural syntax, not a production implementation or another author's oracle.

### Held pre-handoff code-assignment correction

The initial held run retained64 cases with14 failures: ten genuine complete-query-row regressions and four unsupported per-boundary failure-code assumptions. All four boundary outcomes already refuse, while the public contract does not assign their individual codes. Before author edits or implementation, authorize only the original held author to remove those four unfrozen code-assignment assertions while preserving every refused-outcome assertion, scenario and other acceptance check. Preserve the initial file d14fc5ebfc7d49d5b5d772e6d5e53d868c9a08979c70923a9e2cf61f6dec3a21 and all failed receipts. Do not substitute observed implementation codes for an independent oracle. Reserved SQL severity/error prefixes, including an isolated PANIC control, still cannot be treated as ordinary query data; their conservative refusal remains required even when no particular code is prescribed.
