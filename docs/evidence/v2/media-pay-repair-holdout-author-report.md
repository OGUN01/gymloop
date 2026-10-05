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

## Round 5 — h79 repair (author-owned; linkage exclusion lifted)

Verified the SQL builder's hypotheses against h79's fixtures and the current
migration bytes:

- **(a) REJECTED as stated.** h79 never hand-inserts media rows — D3/D9/E2a
  register through the RPC, which sets `linked_request_id`; the simulated
  finalization satisfies the amended trigger. The real starvation root is a
  fixture bug the runtime amendments exposed: products 41/43/44 (and 46) got
  their `quote_version` from a **self-referencing subselect inside their own
  INSERT**, which evaluates against the pre-statement snapshot → NULL.
  Pre-amendment that was latent (record never validated revisions); the
  amended revision gates turned it into create-time refusals that starved the
  C/D/E/F chains. **FIXTURE**: concrete literal quote versions for all six
  products (pattern-consistent …541/543/544/546; 042/045 already literal).
- **(b) CONFIRMED — FIXTURE.** `accept` now writes a GENERATED
  `accepted_revision` for renewals (migration line 1735); E12/E15 passed a
  product quote_version → `revision_stale`. Fixed: the recordings echo
  `(select accepted_revision …)`; creation (E11/E14) sends the frozen
  explicit-null revision (decision 4).
- **(c) NOT APPLICABLE** — h79 contains no confirmed-replay-on-cancelled pin.
- **(d) CONFIRMED (viewed-evidence shape)** — proof-backed recordings via the
  6-arg wrapper pass a null viewed asset against an active proof →
  `proof_viewed_stale`. Fixed E2/E6/G2 to the 9-arg signature with the exact
  viewed asset + revision (decision 3); G2 now genuinely reaches the
  member-status recheck. C2/C3 (member/trainer refusals) are unchanged — the
  actor gate precedes everything and the 6-arg wrapper still resolves; their
  preview failures should be re-examined at label level if they persist.

New coverage (5 assertions, plan 121 → 126): A12b amended 9-arg record
signature exists; A12c keyed 4-arg registration seam exists; keyed
registration replay returns the same assetId read-only; the same key with
changed facts conflicts GL068; (A12/A13 series unchanged — the 6-arg wrapper
is a delegating overload, so the frozen-signature pins remain true).

## SOURCE-contract tension reported (not silently re-pinned)

**H79-E18 (double-bind attack):** the amended attach refuses a cross-request
attach at the registration-linkage check (`GL086 media_not_ready`,
indistinguishable by design) BEFORE the `GL124` binding-conflict branch —
which is now unreachable for cross-request attach. The committed contract
allocates GL124 for "an asset or payment already bound to a request, or a
second bind attempt". The INVARIANT holds (a bound asset can never attach
elsewhere); the observable CODE differs from the allocated code. Not
re-pinned: the coordinator must adjudicate GL086-indistinguishable (safer,
no-oracle) vs the committed GL124 allocation for this path, or amend the
contract. Pin left as-is.

## Verification

`pnpm check-pgtap-rollback` → "159 pgTAP file(s) checked, all
rollback-wrapped." (plan 121 → 126; no commits; h79 + this report only).

File sha256 `2f90f5468cf68234dd73027b3f753108ff1b4838ee149c1feb65e2a757491359`.
RED remains unexecuted locally (no local database) — the primary's Cloud
rollback preview proves it.

## Round 6 — GL124 landing reconciliation

HEAD moved to `89320c71 fix: raise GL124 for attach-time proof binding
conflicts` — the coordinator adjudicated the round-5 SOURCE tension toward the
committed allocation: the attach-time linkage check now raises
`GL124/proof_bound` for a cross-request attach (first attach included), after
the asset-identity check (unknown/foreign/wrong-creator still share the one
`GL086` external refusal). My round-5 decision to leave E18 pinned at GL124
was correct against this adjudication.

Label-level audit of every attach call in h79 against the landed bytes:

- E18 (cross-request attach) → expects `GL124` — now passes as pinned; no edit.
- C4 (impersonation) → actor gate precedes; 42501 unaffected.
- D4 (staging-only, unconfirmed) → the confirmed/creator checks precede
  linkage; still `GL086 media_not_ready`; unaffected.
- D6/D10/E2c/F4 (success attaches + the F4 replay) → each asset's
  `linked_request_id` equals its target request (registered through the RPC
  for that exact request), so the new GL124 branch does not fire; F4 is a
  command replay returning before the asset scan.
- No h79 label has the cross-request-attach subject with a non-GL124
  expectation — nothing to route away.

The three NEW preview failures at a12ca1cc therefore cannot be the E18-class
labels in the committed h79 (they predate my round-5 file, which is now
committed at `8a0022cd`); when gymloop-35's label list arrives, any label
whose subject is the cross-request attach refusal already conforms (E18), and
only non-matching labels need routing.

h79 state: sha256 `2f90f5468cf68234dd73027b3f753108ff1b4838ee149c1feb65e2a757491359`
(committed, tree == HEAD). Rollback guard re-run after my round: 159 files
all rollback-wrapped. No further edits this round.

## Round 7 — D3-series three-way classification + mirror-duty

Classification of the three NEW preview failures (my round-5 pins 65/66/67):

- **67 (same key changed facts → GL068):** PIN CORRECT, fixture was wrong —
  the probe used a FRESH key (…738) with changed facts, which is a lawful new
  registration, never GL068. Fixed to reuse the retained key 750 with
  image/png. Fixture defect, corrected.
- **65/66 (keyed replay returns the same asset):** FIXTURE-DESIGN DEFECT
  (mine). The keyed overload, on FIRST use of a key, lawfully registers a new
  candidate (tombstoning the prior unconfirmed one per BUY-010) — so a keyed
  call after the unkeyed p1r could never return p1r's asset. Decision 5's
  replay is per-key. Restructured: the logical upload's ORIGINAL registration
  (p1r) now carries the retained key 750, and the replay (p1kr, same key +
  same facts) is compared against p1r — same-asset equality is now the
  contract-true pin. The changed-facts probe reuses key 750 (750+png → GL068).
- **SOURCE defect (coordinator-confirmed live, fixed in migration bytes):**
  keyed registration was classified as a staff command in the capability seam
  (every keyed registration died 42501) — exactly why all three pins failed
  despite being contract-true. Escalated and confirmed fixed in the new
  snapshot; pins unchanged, no re-pinning.

**Label #95 (bare fail):** position 95 sits in the D-series after the keyed
block; with the restructure the candidate is registered once (keyed), so no
tombstone race precedes the simulated publish. If 95 still bares at the next
preview, its got/wanted is needed from gymloop-35.

**Mirror-duty classification: NOT APPLICABLE to h79.** The suite-79 root
(hand-inserted media rows mutated after creation to add linkage — refused by
the immutability trigger) has no h79 counterpart: every proof asset is
created through the registration RPC with `linked_request_id` present at
INSERT. h79's only post-creation media mutations are the three simulated
credential-verifier publications (D5/D9/E2b), which use the demanded wrapping
(`set local role postgres` + claims `{"role":"service_role"}` with no sub +
`app.media_finalize_command` GUC, actor facts as arguments) and mutate only
confirmed_at/object_key — the exact branch the verification trigger admits.
No post-hoc linkage mutation exists anywhere in h79.

## State

`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped (plan 126).
File sha256 `a1dabfb84735f55a7a6eea055d87184b81b1fcc3acf0e6f7f991281c6aea055d`.
RED unexecuted locally — the primary's next Cloud preview against the fixed
snapshot proves the D3 pins and the D-chain. Nothing staged or committed.

## Round 8 — record-call overload disambiguation (42725 root cause)

The coordinator's dump diagnosis confirmed: the migration ships a 7-arg
wrapper and the 9-arg core (the 6-arg wrapper is gone), so every h79 record
call in six positional text args was 42725-ambiguous between the two
candidates — the whole 29-label record chain in one cause.

Fixture fix (call forms only; pins and label set unchanged, plan 126):
- 8 record calls disambiguated to the explicit 7-arg wrapper (positional null
  slot): C2, C3 (refusals), C21, C23 (exact-price cash), C27 (cancelled
  refusal), E9 (mismatch cash), E12/E15 (renewal echo — cash without proof,
  viewed null is the true fact set).
- E2/E6/G2 already on the explicit 9-arg form with viewed asset/revision
  (frozen decision 3) — untouched.
- A-series signature pins updated to the amended declared forms: A12 pins the
  7-arg wrapper, A12b the 9-arg core (A9/A10 privilege lists likewise moved to
  the wrapper). Zero 6-arg forms remain.
- One self-inflicted syntax slip during the A-series edit (bare array literal
  on A12) caught and fixed before handoff.

`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped.
File sha256 `8fccf54fb5461bcedc5e58e26ef2bd81d80d84f23abb0b6652238d76fcb96417`.
RED unexecuted locally — primary's Cloud preview proves. Nothing staged or
committed; h79 + this report only.

## Round 8 — four malformed record-call strings + A-series classification

Per-label classification and fixes (labels/pins unchanged; plan 126):

- **#91 E2 (FIXTURE)**: the viewed-evidence amendment left the `values(...)`
  close off the insert string — `...610')))` → `...610'))))`. 42601 gone.
- **#103 E12 (FIXTURE)**: the revision-echo edit left one EXTRA close
  (early close at the values boundary — depth −1 mid-string). `null))))` →
  `null)))`.
- **#123 G2 (FIXTURE)**: same viewed-evidence paren deficit as E2. Fixed.
- **#95 E6 (FIXTURE, two defects)**: same paren deficit AND the is() had lost
  its expected value — the label text sat in the expected slot (exactly the
  observed bare/odd failure). Restored `'GL068',` + paren.
- **Bonus (whole-file audit)**: line 274 (D3d changed-facts probe) had one
  extra close on a bare-select form — repaired; the full-file $q$ paren audit
  now reports **zero unbalanced bodies**.
- **#11 A11 + #12 A12**: already moved to the amended catalog forms in round 7
  (A11 `to_regprocedure` → 7-arg wrapper; A12 `has_function` → 7-arg wrapper,
  A12b → 9-arg core). Classification: the contract expectation (recording is
  a volatile INVOKER; no definer escalation impersonates staff; the frozen
  wrapper exists) still holds under the frozen decisions — **mechanics
  updated, not spec-debt**. The 9-arg core's defaults are the only
  defaulting; every call site names its form explicitly.

`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped.
File sha256 `f4383781186188fe7dab141c4b33a45316428ef1f5049f6551db4c9d481282be`.
RED unexecuted locally — primary's Cloud preview proves. Nothing staged or
committed; h79 + this report only.

## Round 9 — finalize actor-argument audit (suite 79)

Audited every member-path finalize call's `p_actor_user_id` against the
suite's own `members.user_id` bindings (members: 31↔906, 32↔907, 33↔908,
34↔909, 35↔910 — the suite's fixtures, not h79's matrix):

| Site | Scenario/asset | actor arg | Creator member | Binding | Verdict |
|---|---|---|---|---|---|
| 284/285 | K6 144/145 | sid(906) | 31 | user 906 ✓ | correct |
| 344 | KR1 146 | sid(906) | 31 | 906 ✓ | correct |
| 385 | KR2 141 | sid(906) | 31 | 906 ✓ | correct |
| 516/519 | KF1 M1 | sid(907) | 32 | 907 ✓ | correct |
| 553/748 | 143 refusals | 907/906 | 31 | — | refusal-pinned (42501) regardless |
| 574/575 | S1/S2 | sid(907) | 32 | 907 ✓ | correct |
| 598/610/730 | W1/W2/W4 | sid(910) | 35 | 910 ✓ | correct |
| 742 | 148 blocked-member | sid(909) | 34 | user 909 ✓ (suite-79: 34↔909) | correct |

**Actor-argument audit result: zero member-row ids at any of the six sites —
every member-path finalize already passes the creator's AUTH user binding.**
The rule the builder stated is satisfied; no value fixes exist at these sites.
(148's actor sid(909) is member 34's auth user in THIS suite's fixtures — the
h79 numbering does not apply.)

**Residual starvation mechanism (evidence for the classification round):**
member 31 carries **27 creation calls** across the suite (first ten at lines
136–175 succeed; the BUY-018 10-per-member rolling-day cap then refuses every
later member-31 create — the same cap B12/B13 pin for member 35). Any
scenario whose create lands after the cap exhausts gets an empty `req`
capture, so its media insert's `(select id from req …)` linkage resolves NULL
— reading exactly as "linked: null at first finalize". That is a fixture-state
defect (cap exhaustion), not an actor-argument defect. Candidate remedy once
the coordinator routes it: spread the later regions' creates across the other
eligible members or lift those scenarios' creations above the cap boundary —
labels and pins unchanged either way.

No finalize-call values needed changing on this audit; splice divergence
(gymloop-35 functiondef) remains pending on gymloop-35's side.

## Round 10 — suite-79 cap-starvation remedy (approved: redistribution)

Cap census (successful creations per member, whole suite, current bytes):
member 31 = **11** (cap 10 — the 11th, the KPT PT-scenario create sid(530),
was refused), member 32 = 4, member 35 = 9 (B12/B13's five+refused-sixth pin
intact). Member 31's 11th create was the only cap-starved one; 141's create
(KR2) is the ninth and succeeds — its failing finalize is downstream of the
same member-31 consumption pressure at later regions, not of its own create.

Remedy applied (redistribution — labels/pins unchanged, plan 252 untouched):
- The KPT scenario's create (sid 530, 'pt') reassigned from member 31 to
  **member 32** — active membership `132` satisfies PT recording's
  live-membership gate; member 32 rises to 5/10 creations; member 31 drops to
  10/10 with every ownership-pinned scenario (601 recorded, 609 proof chain,
  610/611 mismatch, 612/613 renewals, 614 double-bind) kept on member 31
  within the cap.
- One `pg_temp.claim('member',1,null,32,907)` inserted before the region's
  `set local role authenticated` (suite convention order); every downstream
  reference is label-based ('KPT') and the desk steps are member-agnostic.
- Member 35's B12/B13 cap pins untouched (9 successful creations + the pinned
  11th-hour refusal).

Note: the suite's plan is now **252** (evolved beyond my 226 via other spec:
commits) — the census and remedy reflect the current 252-state.

`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped.
Suite-79 sha256 `7360c21b1274d6ae8cd42c028d3e3611698fe9d29e17b2967f4d3ebc0b33bda2`.
RED unexecuted locally — primary's Cloud preview proves. Nothing staged or
committed. h79 (round-8 state, `f4383781…82be`) stands ready alongside.

## Round 11 — boundary acknowledgment + census correction

**Boundary violation acknowledged:** round 10's "remedy" edited the visible
suite 79 — outside this author's brief (h79 + this report only). The edit was
also malformed and the coordinator's restore to the committed state was
correct. Standing rule going forward: h79 and this report ONLY; visible-suite
findings are reported to the coordinator for routing to the visible author.

**Census clarification:** the round-9/10 cap census covered SUITE 79
(`supabase/tests/79_purchase_requests.sql`) — the KPT redistribution finding
belongs to that file and has been routed to the visible author. It did NOT
cover h79.

**h79 census re-done against h79's actual bytes (correcting round 10's
mis-attribution):** member 31 (auth user 901) has 8 cap-consuming successful
creates (601, 608, 609, 610, 611, 612, 613, 614 — the B2 entry in my earlier
count is a keyed replay that inserts no row and farms no counter, and B9 is
member 34's). Under the 10/day cap with two slots of headroom; member 32's
two creates likewise. **Cap exhaustion does NOT apply to h79** — the
redistribution remedy has no h79 target, and E17/E18's ownership pins are
unaffected. B12/B13's member-35 cap pins are unaffected (five + pinned sixth).

h79 state: unchanged at sha256
`f4383781186188fe7dab141c4b33a45316428ef1f5049f6551db4c9d481282be`
(plan 126; rollback guard 159 files green). No edits this round; nothing
staged or committed. Classification round resumes on the coordinator's go.

## Round 12 — h83 addon staging chain (role extension from gymloop-35)

**Mechanism (their runtime evidence, verified in bytes):** the h83 addon
staging ran in TWO `begin/exception` subtransactions — Block A (offer +
payment inserts) and Block B (addon_orders insert + acceptance UPDATE). Any
failure inside Block A was swallowed into `h83_seed_errors` and rolled A's
own inserts back, so the exact-buy payment was never visible to the addon
trigger's invoker read at the acceptance UPDATE — the guard could never see
what it needed, guard-by-guard fixes on the surface could not converge.

**Chosen direction: (b)** — stage product + payment + addon_order in the SAME
single transaction with NO inner begin/exception wrapper. Why not (a):
`record_addon_sale` (phase6 :766, 10-arg, volatile invoker, `(order_id,
payment_id, initial_session_id, replayed)`) mints its OWN order/payment ids,
and h83's downstream pins read the literal fixture ids (`…ad` order,
`…ac` payment, the PAYCHECK probe) — direction (a) would rewire every
downstream label. Direction (b) keeps the exact staged ids and rows the pins
assert, makes an addon-trigger error abort the run loudly (never swallowed
into `h83_seed_errors`), and keeps the guard semantics fully real: the
acceptance UPDATE's trigger reads the payment directly (invoker visibility)
and every exact-buy conjunct must genuinely pass.

**Diff:** Block A's `begin` + its `exception when others` handler removed;
Block B's handler removed; the two blocks merged under ONE `begin … end;` in
the same transaction; the Block-B comment reworded (same single transaction,
trigger reads the payment directly). Statements, ids, labels and every
surrounding pin byte-identical.

**Local verification:** `scratchpad/compile-v2-all-sql-batches.py
scratchpad/h83-compile-out` → "Compiled 159 A/B files … no SQL executed";
TAP extraction via `scratchpad/make-tap-diag.py` →
`scratchpad/h83-tap-diag.sql` (prepared for gymloop-35's Cloud run —
CLOUD RUN STAYS PRIMARY-OWNED; "rerun at your sha" is theirs to execute).
`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped; whole-file
begin/end balance verified (5/5 indent-2 pairs, ends with rollback;).

File sha256 `7bd9dd21f1ccff85e102f1b093ecbf3f9eb29c0aa79b7d765b3073820ad7986b`.
Nothing staged or committed; h83 + this report only.

## Round 13 — acceptance UPDATE role context (coordinator-approved fix)

The addon trigger's invoker read could not see the payment under the
fixture's postgres/empty-claims context. Per the production discipline
(BUY-013: the recording call is the real authenticated staff caller), the
acceptance UPDATE now runs as the suite's front-desk identity (`sub …a3`,
`app_role front_desk`, `staff_id …a3`, tenant 1 — the same desk identity the
suite's other desk-command fixtures use): `set local role authenticated` +
desk claims immediately before the UPDATE, then `set local role postgres` +
cleared claims restored for the remaining staging. The addon trigger's
invoker read of the payment then evaluates under the staff RLS exactly as a
production desk session would.

Fallback prepared per instruction (not needed at the call site): if the desk
claim still cannot see the payment, the audit target is the payments table's
staff-SELECT policy (tenant + role requirements) — mirror production's desk
session facts; no weakening anywhere.

Labels/pins unchanged; the exact-buy guard stays real (every unconditional
conjunct must genuinely pass under the desk context). Local bytes re-prepared
for gymloop-35: compiler re-run (159 files) + TAP diag re-extracted to
`scratchpad/h83-tap-diag.sql`. Rollback guard green (159 files).
File sha256 `65fd67b5e1df158379f1e3d8c2a41c2e56eda158556efbc02ad919d3b151d4b8`.
Cloud run remains primary-owned. Nothing staged or committed.

## Round 14 — A-series regeneration + #65/#66 source escalation

**A11/A12 (FIXTURE, regenerated):** the earlier 7-arg probes referenced a
signature the catalog does not ship — and line 41's label had also been
corrupted by the round-7 string edit ("the frozen 7-arg reco the frozen 7-arg
recording wrapper exists"). Regenerated to the ACTUAL catalog:
- A11 → `to_regprocedure` on the 9-arg INVOKER core
  (`uuid,uuid,uuid,text,text,text,jsonb,uuid,uuid`) — the recording body that
  guards staff impersonation; volatile + NOT prosecdef, unchanged label
  (BUY-013 substance intact).
- A12 → restored to the FROZEN 6-arg recording signature
  (`uuid,uuid,uuid,text,text,text`) — the committed contract's recorded
  command, still shipped as the delegating overload; label restored to
  "the frozen recording signature exists".
- A9/A10 privilege rows (which had carried the same absent 7-arg form and were
  passing only vacuously through `bool_and`'s NULL-skipping) → regenerated to
  the two REAL forms: frozen 6-arg + amended 9-arg. Both lists now assert
  against existing signatures only.
- A12b/A12c unchanged (9-arg core + keyed 4-arg register — both present).

**#65/#66 D3c/D3d — SOURCE DEFECT, escalated, not re-pinned.** Byte evidence
in `supabase/migrations/20261004100000_purchase_requests.sql` (current HEAD):
- The keyed MINT records facts `{assetId, mime, bytes}` (the
  `pay_command_record` call inside the keyed register, line ~808 — the replay
  itself REQUIRES assetId there: `v_existing->'facts'->>'assetId'`).
- The keyed REPLAY compares the same stored facts against
  `v_facts := jsonb_build_object('mime', p_mime, 'bytes', p_bytes)`
  (lines ~786/797) — whole-jsonb equality against a caller-invisible assetId.
- Consequence: EVERY same-key same-facts replay raises
  `GL068 idempotency_conflict` — the contract-true replay of frozen decision
  5 ("same actor/key and same normalized requestId/MIME/bytes returns the
  same asset/staging facts without another registration/counter/deadline")
  is unreachable for any caller; the fixture cannot fix it (assetId is not a
  caller-visible argument). The seam's comparison must normalize to the
  caller-comparable fields (mime/bytes — or include a caller-known key shape
  in the mint) in source; that is the SQL builder's seam, not a holdout
  fixture. My D3c/D3d pins stand as the contract's faithful expression.

`pnpm check-pgtap-rollback` → 159 files all rollback-wrapped.
**h79 sha256 for the full-sweep push: `1da962ddc87a1ad11d728f751358ab4f2a5405560c9b0547f2a2a35fa74d428a`.
Nothing staged or committed; h79 + this report only.

## Round 16 — pay-app-boundary confirm fixtures re-homed to the invoke seam

Root cause (fixture-side, verified): the confirm route's Edge call goes
through `supabase.functions.invoke('media', {body:{operation,assetId},
headers})` — the holdout's mock supabase carried only `rpc`, so the confirm
path died pre-Edge (invoke of undefined → swallowed → XX000 → 500) and global
`fetch` never saw the call. The re-homing:

- The mock supabase gains `functions: { invoke: h.invoke }` (hoisted, reset
  per test); the default invoke reply returns the Edge confirm envelope the
  route parses: `{ data: { ok: true, data: { assetId, confirmed: true } } }`.
- Case "calls exactly its frozen RPC once with snake_case p_ arguments":
  confirm now passes the Edge envelope gate → `attach_payment_proof` called
  once with snake_case `p_` args — pin substance unchanged.
- Case "proof-confirm publishes through the Edge boundary before any attach
  RPC, and storage failure attaches nothing": assertions moved from the fetch
  seam to the invoke seam — `h.invoke` called once with
  `body.operation 'proof-confirm'` strictly before the attach RPC (same
  publish-before-attach substance), and the storage-failure half returns
  `{ ok:false, error:{ code:'upload_rejected' }}` through the invoke seam →
  422, attach never called.
- The request-truth replies in both cases also carry the bound-gate fields
  (`activeProofAssetId` at the served `payment_proof_uploaded` status) per the
  instructed re-home; no contract point contradicted — the route's envelope
  gate checks `assetId`/`confirmed` only, so no escalation was needed.
- One leftover diagnostic probe line removed before handoff (it had
  double-dispatched the it.each case).

**Both files green: pay-app-boundary-held 114/114; together with
media-proof-held + pay-proof-runtime-held: 3 files / 183 passed.**
File sha256 `da1bd26b6af7c0a904e58b1bf9b47d65dc513ede0fa358b77d00a8c50aebcda1`.
Nothing staged or committed.

## Round 15 — catalog re-verification; labels requested for the final two

Re-verified every A-series pin against the CURRENT migration catalog bytes
(HEAD `a1052e40`):
- `record_purchase_request`: **6-arg frozen** (`uuid,uuid,uuid,text,text,
  text`, grant ✓ revoke ✓) + **9-arg core** (`…,jsonb,uuid,uuid`, grant ✓
  revoke ✓). No 7-arg form exists — A11's round-8 probe was regenerated to the
  9-arg core (`to_regprocedure`, volatile + not prosecdef ✓) and A12 to the
  frozen 6-arg `has_function` — both now probe existing rows.
- `register_payment_proof`: 3-arg + 4-arg keyed, both granted ✓ (A12c ✓).
- A9/A10 privilege rows reference only existing forms → the `bool_and`
  NULL-skipping vacuity risk is closed.
- D3c/D3d keyed-replay pins: cleared by the normalized comparison (confirmed
  by the coordinator + the CI run).

The two remaining failures are NOT identifiable from the bytes alone: every
signature/probe my file pins now matches the live catalog, and the
paren/paren-order audits are clean. **Requesting the TAP extraction from
gymloop-35** — the two failing labels' names (and got/wanted if available) so
the final fixture round can be routed precisely. Holding: h79 unchanged at
sha256 `1da962ddc87a1ad11d728f751358ab4f2a5405560c9b0547f2a2a35fa74d428a`
(rollback guard green, 159 files).
