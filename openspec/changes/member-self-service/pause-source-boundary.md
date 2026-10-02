# Pause source boundary — audited baseline, 2026-10-03

Status: planning evidence only; not a frozen SLF contract, owner approval,
runtime proof, or authorization to change commercial rules. The orchestrator
read the existing source to resolve the public-contract prerequisite. Future
visible and holdout authors must derive tests from the subsequently approved
public rules, not from this implementation or its old tests.

## Established authority and current source

`openspec/specs/pause-decision/spec.md` preserves the configured approver role,
different requester and approver, original caller attribution, pending-only
creation, immutable requester, immutable decided facts, and refusal of changing
the requested facts in the deciding statement. ADR-064 derives an effective
pause from an approved, non-rejected inclusive date interval; it changes neither
membership status nor paid dates. SLF must preserve these rules.

The last function replacement is
`supabase/migrations/20260908210000_a_rule_that_reads_a_nullable_column.sql`:
`app.enforce_pause_decision()` is an invoker trigger with empty search path.
`20260908230000_a_rule_that_only_refuses_belongs_after_the_policy.sql` moves the
trigger after the write policy. Its ordinary-caller checks use GL020–GL028.
Its existing trusted-context carve-out tests `row_security_active`, not a
missing staff claim. No subsequent migration adds an annual/plan budget check
to that function. This observation does not authorize a definer bypass.

`apps/web/app/api/memberships/pauses/route.ts` currently does the following:

- Request creation inserts the original staff requester's pending row after
  `pauseRequestSchema` validates real ISO days, inclusive ordering and a
  nonblank reason. It does not consume an approval allowance.
- Decision loads settings and the current staff role, loads the undecided pause,
  and rejects missing settings, wrong configured role or a decided row. The
  table independently enforces the attribution and two-person boundaries.
- Approval calls its private `exceedsFreezeBudget`. The budget is **per member
  across memberships**, using the **calendar year of the requested start day**.
  It selects approved rows whose `starts_on` is within that calendar year and
  counts each row's **entire inclusive interval**, including any days extending
  into the next year. It adds the entire proposed interval and refuses a sum
  strictly greater than the current gym's `max_freeze_days_per_year`.
- A rejection does not call the budget calculation. The actual decision update
  checks both decision timestamps are still null and inspects returned rows;
  a zero-row outcome is not reported as success.

## Precisely bounded gaps

OPEN-016 already records the missing database-enforced allowances. The route's
budget read and decision write are separate requests, so decisions on different
pauses are not serialized for the member's annual budget. Ordinary direct table
updates do not pass through this calculation. A failed budget query also becomes
an empty prior total in the route. These are source findings, not newly measured
Cloud behavior.

The route never reads `plans.max_freeze_days`; no authoritative source observed
here defines whether that field is a per-request, per-membership or annual cap,
whether zero forbids all pauses, or whether the current plan setting or sold
terms govern. No plan allowance is snapshotted in the existing membership.
The route does not implement the new SLF interval/overlap/eligibility checks.
Its current start-year allocation is distinct from allocating each day to its
own calendar year. Neither can silently be substituted for the other.

## Required freeze work

Publish the approved allowance meanings, year-end allocation, ordinary direct
writer scope and failure behavior as public EARS before independent SLF tests.
Then freeze the additive database budget/overlap and source-link invariants,
including one resource protocol shared by SLF commands and ordinary desk/direct
pause writers. Wrappers alone cannot close the existing race or bypass.
The protocol must address row locks already held by direct updates, cancellation
versus approval, settings changes and retryable lock refusal; merely saying
“take a member lock” is insufficient. No helper signature, lock implementation
or allowance change is selected by this audit.
