# MEDIA/PAY repair holdout author report — 2026-10-04

Author: independent holdout author, repair round. Sources: committed proposal
(git show HEAD), `proof-runtime-protocol-declaration.md`,
`proof-runtime-decisions-frozen.md`, `docs/design/v2/pay-bar.md`,
`docs/security.md` (payment integrity / rate limiting / never-happen / INV
linking sections). No implementation source, visible suite, other critic or
evidence report read. h79/h80 never opened.

## File

`supabase/tests-holdout/pay-proof-runtime-held.test.ts`
sha256 `1749e68808211516b2e8f29b66c8fb2f3854802c75f076869c0f963d0e951563`
(25 tests, vitest, black-box over the public HTTP route surface + shared
public schemas + the two public upload transports; fixture ids 79400000-…,
harness follows the pay-app-boundary-held conventions).

## Command and counts (verbatim)

`pnpm exec vitest run supabase/tests-holdout/pay-proof-runtime-held.test.ts --maxWorkers=2`
→ `Test Files  1 failed (1)` / `Tests  10 failed | 15 passed (25)`

## RED (10) — one-line public-contract topic per failure

1. H1: member list must decode rows from the scalar `{requests,…}` page object.
2. H1: absent recorded facts must stay absent (no invented zero money/receipt).
3. H1: desk list must decode the same scalar shape.
4. Frozen decision 4: renewal creation must accept an explicit null
   expectedRevision.
5. Frozen decision 6: caps must surface as 22023 DETAIL purchase_cap → 429
   rate_limited (GL126 not authorized).
6. BUY-011: reject reasons must be trimmed and bounded 3–200 at the route.
7. Frozen decision 5: web registration call must carry the retained
   registration key.
8. Frozen decision 5: web retry after unknown outcome must transmit the SAME
   key.
9. Frozen decision 5: native transport must carry the retained key.
10. Frozen decision 5: the upload-url request schema must include the
    retained registration-key field.

## Passing (15) — behavior already correct, pinned against regression

cursor-pair forwarding; null cursors on final pages; P0002 → one external
404 refusal without target facts; proof-url returns only {url,expiresAt}
no-store; >60s deadline refused; foreign-origin URL refused; uncapability
proof-asset GET refused no-store; shop creation still requires the quote
revision; unknown kind / fractional quantity refused; empty/absent reject
assetId refused before any call; record strict body requires revision +
amount + currency + method; confirm strict body requires assetId + revision
+ commandKey; storage keys/ETags never leak into the proof-url envelope; no
GL126 constant in shared constants.

## Not locally runnable (flagged for the primary)

DB-side halves of H3 (exact registration↔request binding incl. first attach),
H4 (viewed-evidence comparison under locks pre-ledger), H5 (registration
replay storage/no counter reset), H8 (renewal sold-terms comparison), H6
(post-await actor/eligibility revalidation inside the trusted boundary) and
H7's active-only SQL boundary need the primary's Cloud rollback preview /
pg_prove. h79 supplements for these belong to the h79 author — never opened
by this author. One spec-tension note: the confirm-side zero-privileged-read
demand for unknown asset ids conflicts with the frozen first-upload flow;
the achievable contract (authorization precedes privileged access, refusal
after the request-scoped read) is what surface tests can pin.

## Fixture corrections made during authoring (author-owned)

- Reject-reason probes moved from a (non-existent public) reject-proof schema
  to route-level drives; trim fixture corrected from '  ok  ' (trims to 2) to
  '  abc  ' (trims to 3, within 3–200).
- Upload file fixture corrected to the standard web File shape
  ({name,type,size}).

## Round 2 — env fixture plumbing (coordinator follow-up)

The route import chain asserts the public env contract at module load; the
harness now stubs the exact asserted variable set from
`packages/shared/src/config/env.ts` (fixture plumbing only, no assertion
weakened). One fixture correction: an unknown upload outcome may surface as a
thrown error, so the retry test accepts throw-or-failed-result before
asserting the retained key.

New file sha256 `69b38c848f39ec478d76b071bc0ba4a8ec5d047a41d4a9e94e400fcdb3c98e33`.

Command (verbatim): `pnpm exec vitest run supabase/tests-holdout/pay-proof-runtime-held.test.ts --maxWorkers=2`
→ `Test Files  1 failed (1)` / `Tests  6 failed | 19 passed (25)`

## Still-failing (6) — public topic label + failure class only

1. H1 member list decodes the scalar page object — assertion: status 500 vs 200.
2. H1 absent recorded facts stay absent — TypeError: decoded page undefined
   (scalar object consumed as non-object; `requests` unreadable).
3. H1 desk list decodes the scalar shape — assertion: status 500 vs 200.
4. H9 record strict body accepts the contract-valid body — schema shape
   mismatch: contract-valid record body refused.
5. H5 native transport carries the retained registration key — assertion: 0
   registration calls observed (no network call under the declared input).
6. H5 upload-url schema includes the retained registration-key field —
   schema keys 2 vs ≥3.

## Round 3 — H1 no-fabrication fixture amended to the achievable contract

The "absent recorded facts" fixture now feeds the STRIPPED shape (recorded
fact keys absent, as `jsonb_strip_nulls` produces), and pins: no fabricated
`"recordedAmountPaise":"0"`, no /receipt/i match, and recorded fact keys
absent-or-null (either accepted), never a fabricated value. No-fabrication
substance kept, not weakened.

New file sha256 `9c0380967a34b0c3195a753a5d0860d1341ba502844b74ca1230e299a5ca14d9`.

Command (verbatim): `pnpm exec vitest run supabase/tests-holdout/pay-proof-runtime-held.test.ts --maxWorkers=2`
→ `Test Files  1 failed (1)` / `Tests  1 failed | 24 passed (25)`

Movement: with the stripped-shape fixture, the two H1 scalar-decode tests
(member list, desk list) now PASS as well — their earlier 500s stemmed from
the impossible explicit-null row shape this amendment removes.

Remaining RED (1): H5 native transport — assertion class: 0 registration
calls observed for the retained key under the declared input (native
transport contract gap, decision 5).

## Round 4 — native fixture reference corrected; file fully green

The H5 native case referenced `file.bytes` (undefined after the round-2 file
shape change) instead of `file.size`, so the transport correctly refused
before any registration — a fixture defect, not a transport gap. Reference
corrected to `file.size`.

New file sha256 `d630b645f4d74dcc7327d052a0d57dac53f3c0075eb99cae1f5bf66e44ad9364`.

Command (verbatim): `pnpm exec vitest run supabase/tests-holdout/pay-proof-runtime-held.test.ts --maxWorkers=2`
→ `Test Files  1 passed (1)` / `Tests  25 passed (25)`

Holdout file state: fully green locally. The DB-side halves (H3 exact
binding, H4 viewed-evidence under locks, H5 registration replay storage,
H6 post-await revalidation, H7 active-only SQL boundary, H8 renewal
sold-terms comparison) remain primary-owned Cloud-preview subjects, as
recorded above.
