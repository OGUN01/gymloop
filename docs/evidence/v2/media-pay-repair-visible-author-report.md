# MEDIA/PAY repair round — visible author report (2026-10-04)

Author role: independent visible test author. Assertions derived only from
`git show HEAD:openspec/changes/member-purchases/proposal.md`,
`proof-runtime-protocol-declaration.md`, `proof-runtime-decisions-frozen.md`,
`docs/design/v2/pay-bar.md`, `docs/registry.md` and committed visible-test
conventions. No implementation, holdout, evidence-report or critic file read.
SQL assertions are RED-unexecuted locally (no local database); the primary's
Cloud preview proves them.

## Pre-existing untracked repair tests (another author's, reused not edited)

Seven uncommitted visible files already pin most repair requirements and run
20 RED / rest green — defect-capturing, kept untouched:
`purchase-visible-page-decode.test.ts`, `purchase-visible-proof-asset.test.ts`,
`purchase-visible-upload-identity.test.ts`,
`purchase-visible-verifier-surface.test.tsx`,
`packages/shared/.../purchase-visible-runtime-contract.test.ts`,
`apps/mobile/.../purchase-visible-hook-identity.test.ts`,
`apps/mobile/.../purchase-visible-native-identity.test.tsx`.
DEFECT for that author/primary: the first two files carry 13 web `tsc` errors
(strict own-file typing: `purchase-visible-upload-identity.test.ts` lines
~73–74 `Object is possibly 'undefined'`, plus page-decode errors) — test-side
fixes owed by their author; my files typecheck clean.

## Files I authored/edited

1. `supabase/tests/79_purchase_requests.sql` sha256-16 `58871fcbd7222e20`
   — plan(226) → **plan(246)** (+20 assertions, diff-verified +52/−32 assert
   lines including call-site rewrites):
   - **R11/GL126 removal:** the eleventh-registration cap case now pins
     `22023:purchase_cap` (stable DETAIL marker) instead of the unapproved
     GL126.
   - **R9 active-only flip:** the three post-recording bound-view positives
     (member KR1U, verifier KR1V, mismatch KR2U) become the one external
     refusal (`P0002`) for everyone; only the payload pins were deleted.
   - **R9 active-view positives:** new block pins member + verifier obtain the
     URL for a live request's ACTIVE proof (KF3), with requestId/path/expiry
     ≤60s, exactly-five-safe-keys and no-storage-metadata payload pins; a
     foreign member shares the refusal.
   - **R3 attach linkage:** confirmed asset registered for KF4 refuses to
     attach to the same member's second live accepted request KF5 (first
     attach included) while still attaching to its own request; fixture W2
     finalized for the purpose (member-35 caps respected).
   - **R4 viewed evidence:** every `record_purchase_request` call site gains
     the approved tuple `(p_initial_slot, p_viewed_asset,
     p_viewed_proof_revision)`; signature registry row updated to
     `(uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid)`. New pins: recording
     refuses a verifier context bound to the superseded proof, refuses a
     viewed revision that is not the current request revision, refuses a null
     viewed asset while an active proof exists.
   - **R4 attach revisions:** all ten attach call sites now send the real
     `pg_temp.rev(label)`; new pin: attach with a wrong expected revision
     refuses.
   - **R5 registration replay:** keyed `register_payment_proof(request, mime,
     bytes, key)` pins — same key + same facts replays the same asset and
     staging key (no second candidate, no new deadline), changed facts
     conflict.
   - **R8/decision-2b PT slot:** exact-price PT recording without a valid
     initial slot refuses; a fabricated slot jsonb is never client-trusted
     (server-side validation refusal); PT scenario fixture KPT (member-31
     caps respected).
2. `apps/web/app/__tests__/purchase-visible-active-proof-boundary.test.ts`
   sha256-16 `eab905fcfe2c145d` — R9 transport boundary: recorded and
   mismatch_recorded requests refuse the owner member and the verifier with
   exactly `404 request_unavailable` and no target/expiry/url remnants
   (no-store); trainer audience is `403 not_permitted` with zero RPC calls;
   the live active proof still serves `{url,expiresAt}` only. **5/5 green** —
   these are correct-behavior pins: the transport already refuses when the
   database refuses; the genuine R9 RED is the SQL-level flip above.

## Verbatim results

- Repair-set run (12 files, mine + reused untracked): `Test Files 7 failed |
  5 passed (12)` / `Tests 20 failed | 162 passed (182)`.
- The 20 RED tests, by requirement: R1 scalar decode ×7 (page/detail,
  camelCase keys, nested PT/renewal snapshots, absent-facts-absent), R2
  capability TTL ×1 (GET inside TTL must serve with no-store), R4/R7 viewed
  evidence on the recording command ×1, R5 registration identity ×3 (PUT
  failure retry reuses key/facts, confirm-failure replay, MIME/bytes carried),
  R6 native identity ×3 (member change/sign-out during picker refuse before
  any network; hook reload seam), R7 surfaces ×4 (desk renders the real
  screenshot, recording disabled before the proof was viewed, member
  replacement offered at payment_proof_uploaded, native detail/proof path
  after upload), R8 renewal null revision ×1, R10 generated enum vocabulary
  ×1. Each is a public-contract violation shape per the committed contract,
  declaration and frozen decisions — no implementation diagnosis claimed.
- My R9 transport file: `Test Files 1 passed (1)` / `Tests 5 passed (5)`.
- `pnpm check-pgtap-rollback`: 155 pgTAP files checked, all rollback-wrapped.
- Scoped web `tsc --noEmit`: 13 errors, ALL in the two reused untracked files
  listed above; zero in my files.
- SQL RED honestly unexecuted: the plan(246) suite (cap marker, active-only
  refusals, viewed-evidence tuple, attach linkage/revisions, registration
  replay, PT slot) is proven only at the primary's Cloud preview.

## Coverage gaps noted for the builder round

- R2's "SQL evidence helper needs a concrete named return type" is pinned
  indirectly by the five-safe-keys payload assertion; a direct return-type
  catalog pin would need a pgTAP catalog probe the suite's style does not
  use — flagged for the primary's judgment.
- PT recording success with a valid slot is not pinned (needs a full PTF
  booking fixture); the refusal pins above capture the approved amendment's
  safety half.
- R3's "no admin web client exists" is a negative-existence claim left to the
  fresh critic's source inspection, not a test.

## Round 2 — author-of-record fixture repairs (coordinator follow-up)

Became author of record for the seven reused untracked files. Repaired the 13
web `tsc` errors with strict own-file typing, no non-null assertions, no
suppressions, no weakened assertions:

- `purchase-visible-page-decode.test.ts` (sha256-16 `a6294f8f0a8d9f56`):
  the continuation test now guards `matched[0]` with a throwing guard carrying
  the original assertion message before the three field assertions; the
  `toHaveLength(1)` expectation is retained.
- `purchase-visible-upload-identity.test.ts` (sha256-16 `db8e78f4c27cd242`):
  (1) the JPEG proof bytes are built with `Uint8Array.set`/`fill` instead of
  the nonexistent `concat`; (2) `runUpload` now calls the public helper with
  its real signature `uploadPaymentProof(file, requestId, expectedRevision,
  commandKey)` — the previous call passed the arguments in the wrong order
  (the request id as the File); (3) both retry tests capture the first/retry
  and first/last confirm entries through guarded locals carrying the original
  expectation messages. Assertion strength unchanged or stronger: with the
  corrected call shape the caller passes the same stable request facts on
  every attempt, exactly as the real retry flow does, so the retained-identity
  assertions still discriminate helper behavior.

Verbatim re-run (12 files, same set as round 1): `Test Files 7 failed |
5 passed (12)` / `Tests 18 failed | 164 passed (182)`.

The RED count moved 20 → 18 because two R5 cases were failing on the test's
own wrong-signature call, not on the source: with the real signature they pin
correct behavior and pass — `a retry after a confirm failure replays the same
attachment command key` and `the declared MIME and byte facts are carried with
the registration`. They remain part of the committed suite as green
correct-behavior pins. The remaining 18 RED keep the round-1 mapping
(R1 ×8, R2 ×1, R4 ×1, R5 ×1, R6 ×3, R7 ×4, R8 ×1, R10 ×1... exactly: R10 ×1,
R1 ×7 in runtime-contract + ×1 in page-decode, R8 ×1, R4/R7 viewed-evidence
×1, R5 PUT-failure identity ×1, R6 hook ×1 + native ×2, R7 web ×3 + native ×1,
R2 GET-inside-TTL ×1).

Scoped web `tsc --noEmit`: **0 errors**. `pnpm check-pgtap-rollback`:
unchanged green (155 files). Unchanged files keep their round-1 hashes:
suite 79 `58871fcbd7222e20`, active-proof-boundary `eab905fcfe2c145d`.
SQL RED remains honestly unexecuted locally — the primary's Cloud preview
proves plan(246).
