# Phase 5 — money

Archived 2026-09-09. **Seventeen rounds, sixteen NO-GO verdicts, then GO.**
The longest gauntlet in this project by a factor of four, and worth reading
because the shape of it is more useful than any single defect.

## What shipped

Manual payment at the desk as a first-class path, not a fallback: cash, UPI,
card or bank transfer, the gym's own receipt book numbered per financial year
(`2026-27/000001`), attributed from the JWT claim, extending the membership the
money bought. Refunds bounded by what was actually taken. A payments ledger, a
receipt page and a refund control. Razorpay built to the exact point test
credentials are required and stopped there — `razorpay-gap.md` names what is
missing rather than stubbing it, and duplicate webhook delivery was proven
idempotent as `service_role` with no Razorpay account in existence.

## What went wrong, which is the point of this file

**The money path is one line of arithmetic:**

    ends_on = duration_days × floor(money / price_paise)

Everything that went wrong in twelve rounds was an input to that line being
writable by somebody who should not have been writing it, and **every round
closed one input and left another open.**

| round | closed | left open, measured next round |
|---|---|---|
| 6 | the price, once a period was granted | the gate was `periods_granted`, which the desk could rewrite |
| 7 | made that count unforgeable | the gate still said "granted", so a **part-paid** membership was wide open — ten years for one paisa |
| 8 | gated on money arriving instead | the plan's `duration_days` was still read live |
| 9 | made the length derived, never typed | the **dates** — the arithmetic's own output — were writable by hand |
| 10 | the dates | the **price**, the other factor, still freely typed: 300 days for one month's fee |
| 11 | the price, by moving it to the gym admin | `coupon_id`, which names *why* a member owes less, sat outside the same rule |
| 12 | the coupon | — |
| 13 | a payment extending a **retired** membership — the rule read price, currency, dates, count and length and never `status` | the refusal was deferred, not durable: money paid while retired stayed on record |
| 17 | the `GL036` ceiling defeated by demoting a refund to `failed`; a refund against a payment that took nothing; a membership moved to another member by one front-desk statement | — **GO** |

Rounds 14, 15 and 16 found no defect in the money arithmetic at all. Their
blockers were contract text, documentation claims that measurement
falsified, stale data in the shared demo project, and — twice — a fix of
mine introducing a fresh critical.

**Three of those rounds existed because the contract was wrong, not the code.**
Twice a requirement named a harm in its own prose and then permitted the
identical outcome by another route, three lines below itself — and both times
the blind test suites certified it, because they were written to the scenario.
That produced ADR-092's rule, which is now run as a check rather than
remembered: *where a requirement names a harm, no scenario under it may permit
that harm's outcome by another route.* It found a real defect in three of the
last four rounds, including one in the round that wrote it.

**A premise recorded as measured, and false.** ADR-092 ranked the dates below
the length because a hand-written `ends_on` supposedly left a detectable trace.
The number behind that claim had been borrowed from a different audit. Measured
properly, the invariant already failed for 17 of 46 memberships before any
fraud — and a blind author later falsified it from the other end by showing an
ordinary part payment breaks it. A wrong reason for a priority is worse than no
reason, because it stops the question being asked again (ADR-093).

**The unpoliced INSERT, three rounds running.** A rule gets written for UPDATE
and creation is the door left open — the count, the dates, then the price. Both
authors found the third one independently and neither guessed at it.

**A gate that only checked the seed ran.** `seed-dry-run` passed for eleven
rounds while the seed produced wrong data: its date snapshot was taken before
the statement that wrote the dates, so every span was short by the days since
the last seed and accumulating. A re-run reproduced the same wrong answer, so
"idempotent" held and hid it. It then hid two consecutive criticals in the
receipt counter, because on the live project the seed's payments already
exist and `on conflict do nothing` means new expressions never run — a gate
that exercises only the path the data already took.

**And the verification harness itself was silently replaced** (ADR-097). The
47-file sweep is the only local check this project has; it lives in an
unversioned scratchpad every subagent can write to, and one overwrote it
with a narrower version whose allowlist was twenty pgTAP function names from
memory. Thirty-four of forty-seven files reported FAIL while passing. The
harness deserves the same treatment as the code it verifies and does not
have it.

## The three failure modes, in order of how much they cost

**1. A rule keyed on something the constrained party can rewrite.** Round
six froze the price and keyed the freeze on `periods_granted`, which the
front desk can retype. Round seventeen froze the refund ceiling and keyed it
on a refund status nothing froze. ADR-089 states the general form — *a
freeze is worth exactly as much as the immutability of the thing it is keyed
on* — and it was still being violated eleven rounds later, one table over.

**2. A requirement that names a harm and then permits it.** Twice inside the
paragraph written to fix the previous instance. ADR-092's grep exists for
this and found a real defect in eight of the last nine rounds, including
twice in the requirement written to record the lesson. **Both blind authors
now run it before writing a line**, and it is the single highest-yield check
in the loop.

**3. Claims about the system that measurement falsifies.** Eighteen wrong
registry cells across thirteen rounds, five written in the same commit as
the code they describe. A premise recorded as measured that was borrowed
from a different audit. A cleanup declared "verified" that had swept three
of six tables. A verification that passed because it selected zero rows. The
code settled around round thirteen; **what kept the phase open for four more
rounds was what I wrote down about it.**

## What the arrangement bought, and what it cost

The blind authors found more contract defects than the critics did. They
reported holes in requirements they were writing against, staged genuinely open
questions with a `diag` instead of guessing, and twice changed assertions of
their own that encoded a contract since corrected. On one seam the two suites
disagreed with each other, which is what forced an edge nobody had decided.

It cost a leak, recorded as ADR-091: hard rule 1 obliges every session to read
`docs/registry.md`, and the implementer had updated it in the same working tree
while both authors were writing — so it told them the trigger names, the column
names and two design decisions before either designed an assertion. The
registry now travels with the implementation commit.

## Left open deliberately

- **OPEN-027** — a plan round-trip keeps a length no plan carries. Needs gym
  admin; the same admin reaches the same outcome legitimately by creating a long
  plan, which differs only in leaving evidence. The honest instrument is an
  audit trail, which this product does not have.
- **OPEN-028** — whether the agreed price is the gross or the net.
  `discount_paise` exists, the seed writes it, and nothing in the money path
  reads it.
- **OPEN-029** — creation is unpoliced for dates. Closing it contradicts the
  seed on every demo row.

Each is recorded in `docs/decisions.md` with its measurement and the reason it
was not closed here.

## Still owed by the owner

Razorpay test keys with a captured payload and signature; credential rotation
before launch.
