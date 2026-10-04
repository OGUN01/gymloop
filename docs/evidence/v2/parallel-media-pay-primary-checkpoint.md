# Primary integration checkpoint — 2026-10-04

The six independently authored MEDIA/PAY proof test files are now committed
in a test-only `spec:` commit titled
`spec: independently require trusted private payment proof uploads`.
Resolve its exact SHA in current Git history before source repair. Root ran
all six unchanged files together: **117 tests, 65 failed and 52 passed**;
all six test files failed. Receipt:
`scratchpad/media-pay-independent-red-root-20261004.log`.
The result matches the independent visible 39/69 RED and held 26/48 RED.
Production upload source was not changed in that commit.

The parallel coordinator may now launch its separate implementer against the
committed visible tests and frozen public contracts. Never give it held tests
or private diagnostics. Preserve the existing uncommitted PAY migration and
other external source. Public RPC/metadata differences must be reported as
precise integration requests; fixture correction remains author-owned. Do not
invent a new exposed projection or administrator client to satisfy a mock.

The approved canonical-currency wording is clarified in `6d6a6a4a`: accepted
quotes/fulfillment remain INR; BUY-014 factual currency mismatch may be recorded
through existing money guards, without fulfillment or conversion. This does
not broaden proof privacy or authorize live money testing.

Primary retains Git/index, Cloud SQL, CI/deploy, central shared-file integration
and final device/release. This checkpoint permits source work only; it does
not claim local green, deployment, live upload or v2 acceptance.
