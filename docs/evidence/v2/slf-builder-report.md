# SLF builder round — held-suite findings adjudication, 2026-10-04

Separate source builder. Read only `20261005100000_member_freeze_requests.sql`
(in full), the four contract files in `openspec/changes/member-self-service/`,
and the fresh critic's P3 sections. No test file, holdout file or scratchpad
artifact was opened; nothing was executed; nothing was committed.

## Fixed (4 findings, contract-traced)

1. **F2 — changed actor under the create key conflicts without leaking facts.**
   SLF-013 pins "an exact authorized replay precedes revision and
   target-eligibility checks" and "changed facts/action/actor under a key
   SHALL conflict without leaking stored facts". The replay/conflict block ran
   AFTER the membership load/eligibility check, so a changed actor under a
   known key got 42501 `Membership unavailable for freeze requests` (a
   membership-fact disclosure) before the GL068 conflict. Fix:
   `request_member_freeze` now validates the actor, takes the serialization
   lock, builds the normalized facts, and runs the command-key
   replay/conflict lookup (keyed on `app.current_tenant_id()`) BEFORE the
   membership load and every eligibility check. The member-for-share /
   membership-for-share / actor-revalidation block is unchanged and still
   runs before the value validation. (Lines ~1409–1457.)

2. **F8 — changed expected revision under the adopt key must conflict.**
   `expected_revision` is a normalized command argument of the four desk
   commands ("Facts contain normalized command arguments", proposal). It was
   absent from stored `member_freeze_commands.facts`, so a changed-revision
   retry under a used key replayed instead of conflicting GL068. Fix:
   `expected_revision` is now part of `v_expected_facts` in
   `app.slf_freeze_prepare` (from `p_expected_revision`) and in
   `app.slf_freeze_finish` (from `v_preparation.expected_revision`); the four
   invoker wrappers pass it in their facts; and all four `finish` command-row
   INSERTs store `v_expected_facts` verbatim. Exact same-revision retries
   still replay; changed revisions now conflict. (Lines ~893, ~1160, 1232,
   1289, 1331, 1364, 1702, 1744, 1821, 1863.)

3. **F9 — cancel of another member's request collapses to the unavailable
   signal.** Aligned with the safe reads' P0002 collapse (critic P3-3: one
   unavailable signal for the create/cancel pair; proposal HTTP map:
   absent/foreign/unavailable → one `request_unavailable` class).
   `cancel_member_freeze_request` now refuses missing, foreign-tenant,
   non-owning-member and non-original-subject targets with a single
   P0002 `Member freeze request unavailable` instead of distinguishing
   existence with 42501. (Lines ~1591–1599.)

4. **F12 — paired-argument keyset cursor enforced.** Critic P3-4 + the
   deterministic-keyset requirement: a lone `p_after_created_at` without
   `p_after_id` cannot break timestamp ties and re-served boundary rows.
   Both `read_member_freeze_requests` and `read_staff_freeze_requests` now
   refuse a one-sided cursor with 22023
   `Member freeze keyset cursor requires both arguments`, and the predicates
   no longer carry the `p_after_id is null` escape (both-or-neither is
   guaranteed before the predicate). (Lines ~1920–1927, ~1963–1970, ~1929–1931,
   ~1972–1974.)

## Recorded as adjudication questions (8 findings; no source change derivable)

These findings' observed refusals cannot be produced by the current source
order given their labels, or the contract does not pin the observed/expected
difference. Per the rules I changed nothing and record each precisely:

- **F1 "replay created no second row" (have 0).** The replay branch appends
  no request/command/audit row by construction (it returns before any
  insert), and the unique `(tenant_id, command_key)` plus the FK guarantee
  the replayed command's request exists. A 0-count against any
  "original-only" expectation is not derivable from the source; plausibly
  downstream of F2/F8 ordering in the same scenario. Re-adjudicate after this
  round's rerun.
- **F3 SLF-002 pending membership (observed GL066 open-request).** In the
  current source the membership-state refusal (22023
  `Membership does not permit freeze requests`) executes strictly BEFORE the
  one-effective-open-request check (GL066) in the same function. A pending
  membership create therefore cannot observe GL066 first unless the fixture's
  pending state is not represented in the checked `memberships.status` row.
  Either the fixture state shape needs re-derivation, or the scenario targets
  a different call path than create — a held-suite question, not a source
  defect I can locate.
- **F4 SLF-004 span (observed GL066 open-request).** Same ordering argument:
  the span refusal (22023 `Member freeze interval leaves the membership
  span`, lines ~1485–1488) precedes the one-effective check (~1513). The
  observed code cannot fire after a failed span check for the same
  membership/interval pair.
- **F5 SLF_LIMITS one effective open request (observed GL066 open-request).**
  The one-effective guard IS the source's SLF_LIMITS site and raises GL066
  `Member already has an open freeze request`. If the held expectation pins a
  different message or code for this guard, the frozen contract text does not
  pin either (the proposal names no refusal string for SLF_LIMITS; GL066 is
  the declared overlap/state class). Contract question: which exact code and
  message does the frozen vocabulary assign to the one-effective bound, and
  does it differ from the one-effective guard's current text?
- **F6 SLF-003 trio (all observed 42501 `Member freeze authority
  unavailable`).** `app.slf_member_actor` is the declared validator and this
  exact code/message is its declared outcome for erased/unlinked/invalid
  claim actors (SLF-003: such identities "SHALL gain no SLF authority").
  For the foreign-tenant-target case, create raises 42501
  `Membership unavailable for freeze requests` after this round's F2 reorder.
  If the held expectation pins different exact codes/messages for these
  three scenarios, the declarations do not state them — contract question.
- **F7 SLF-005 overlap with an approved source pause (observed GL066
  open-request message).** When a fixture contains BOTH an effective open
  request and an approved overlapping pause, the source raises the
  SLF_LIMITS guard (which precedes the overlap check). The frozen contract
  does not pin a precedence between SLF_LIMITS and SLF-005 when both
  conditions hold. Contract question: which guard wins, or must the fixture
  isolate the two conditions?
- **F10 SLF-010 read effective state (have NULL).** `app.slf_freeze_detail`
  assigns `v_effective` on every branch (approved/requested/
  desk_submitted/else) and cannot emit a NULL `effective_state` for a
  materialized row; the reads check the row before projecting. A NULL result
  is not derivable from the source — likely a NULL row composite or a
  fixture-state artifact in the held scenario. Re-adjudicate after rerun.
- **F11 SLF-014 partial unique (observed 23514 reciprocal mismatch).** For a
  second row that agrees with its source pause on every checked dimension
  (tenant/member/membership, dates, reason, adopter provenance, decision
  truth), the BEFORE trigger passes and the partial unique index produces
  23505 — the trigger does not consult sibling rows. A 23514 from
  `Member freeze reciprocal source scope/provenance mismatch` means the
  inserted duplicate disagreed with the pause on some checked dimension. If
  the held fixture intends an agreeing duplicate, its row shape needs
  re-derivation against the every-writer agreement clause; if it intends a
  refusing shape, the expected SQLSTATE (23505 vs 23514) is a contract
  question.

## Risk notes for the orchestrator

- The F9 collapse changes cancel's foreign-id refusal from 42501 to P0002.
  If the independent visible suite pinned the old 42501 for a foreign cancel
  target, that visible assertion will now fail and needs a lawful
  author-owned amendment (the critic's P3-3 and the HTTP map both support
  the collapse).
- The F8 facts-shape change adds `expected_revision` to desk-command facts.
  If a visible assertion pins the exact stored `facts` jsonb of a desk
  command, it will need the same one-key amendment.
- The F12 guard makes one-sided cursor calls refuse 22023. If a visible
  assertion exercised a one-sided cursor expecting a result, it needs the
  paired-argument amendment.

## Static checks

- `check-pgtap-rollback` on the migration file reports "does not start with
  BEGIN / end with ROLLBACK" — expected for a migration (the harness wraps
  migrations; the guard's BEGIN/ROLLBACK rule targets test files). No
  rolled-back-test findings.
- `$fn$` pairs: 40 (even); bare `$$`: 0; top-level parenthesis balance: 0.
- No test file opened or modified; no Cloud SQL; no commits.

## Hash

New migration sha256:
`0faadbaadec9910a05e61b59d84b69d5c6eb76742753bdc0c123ca0137f18326`
