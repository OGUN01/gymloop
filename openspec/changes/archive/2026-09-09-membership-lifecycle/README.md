# Membership lifecycle — OPEN-030, closed

Folded into `openspec/specs/membership-lifecycle/spec.md`.

## What it closed

`payments` has had a state machine since Phase 5 round three
(`app.payment_transition_allowed()`, `GL039`); `memberships` had none. A critic
revived a retired membership from an ordinary front-desk session in one
statement: `update public.memberships set status = 'active' where id = <cancelled>`.

`docs/data-model.md` had listed the legal transitions since Phase 1 and called
`expired` and `cancelled` terminal. **The gap was never a missing contract — it
was that nothing enforced the one that existed**, and a routing-table document
asserted a rule the database did not keep. `GL047` enforces it now (ADR-098), on its own trigger — named
`memberships_status_transitions` at the time and **renamed to
`memberships_transitions_after_terms` by ADR-101**, because the old name sorted
before `memberships_terms_frozen` and Postgres fires same-timing row triggers in
name order, so `GL047` was answering ahead of five rules that should have
preceded it.

## The shape of what went wrong, which is the part worth keeping

Three defects, and none of them was the state machine itself. All three were
about **where a rule lives and what answers first**.

1. **A rule folded into a function the seed switches off.** The obvious home for
   the transition check was beside the other rules in
   `app.enforce_membership_terms_frozen()`. Both seed files *disable* that
   trigger around their own statements — a window argued for dates and never for
   transitions — so the rule would have been silently off for the whole seed and
   would have passed every assertion anybody wrote. A blind author caught it.
   It got its own trigger.

2. **A migration re-emitted a hundred-line function it did not need to touch**,
   and the re-emission was not behaviour-preserving: ~60 lines of recorded
   reasoning gone, and `GL042` moved from before the `GL043` length check to
   after it. **Every assertion in both suites stayed green** — a full 47-file
   sweep of 4052 assertions — because no assertion had ever named a single
   statement that violates two rules at once. This repo names that hazard
   verbatim in a registry cell I wrote one change earlier (ADR-099).

3. **And the order it was restored to had never been decided either.** A holdout
   author read the requirement's unqualified sentence — *"it SHALL be this rule
   that answers, not another one the same statement also violates"* — as written,
   and measured `member_id + periods_granted` answering `GL044` and
   `member_id + ends_on` answering `GL045`. Ownership was checked third because
   two clauses had been typed in by earlier migrations and one by a later one.
   Six migrations each appended where the last one ended, and the precedence was
   nobody's judgement (ADR-100).

## The general form

**Where two rules can fire on the same row, which one answers is behaviour** —
the caller acts on the message, and the wrong rule's message prescribes a repair
that does not apply. This codebase had been deciding it by typing order in every
multi-rule trigger it has. ADR-100 decides it for the four membership-terms
absolutes and OPEN-034 records the five places it is still undecided — one of
which is not merely undecided but **unassertable**, because the refund
amount-freeze is assigned no SQLSTATE anywhere in the contract.

That is ADR-092's grep one table over: *where a requirement names a harm, no
scenario under it may permit that harm's outcome by another route* becomes *where
two rules can answer, either the contract decides which, or an assertion pins
that nobody may rely on it.*

## Next

OPEN-029 (creation is unpoliced for dates), then OPEN-031 (refunds have no
idempotency key).
