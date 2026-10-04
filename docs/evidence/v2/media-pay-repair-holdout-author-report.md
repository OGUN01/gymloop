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
