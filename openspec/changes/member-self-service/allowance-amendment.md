# Pause allowance decision

Status: proposed owner decision, 2026-10-03. Not approved or frozen. Read with
`proposal.md`, `pause-source-boundary.md` and OPEN-016. This selects commercial
meaning before independent tests; it authorizes no source or database change.

## Recommended meaning

Preserve the existing annual accounting rule: the current organization's
`max_freeze_days_per_year` applies per member across all their memberships,
using the calendar year of each request's start date. Count the entire
inclusive approved interval in that start year, including days beyond year
end. Add the entire proposed approved interval; equality is allowed, a larger
sum is refused. Rejected, pending and withdrawn requests consume no allowance.
Do not silently replace this with per-day allocation, a rolling year or a
membership-specific annual counter.

Define the currently unenforced plan `max_freeze_days` as a maximum inclusive
length of one approved pause, using the membership's current RLS-visible plan
at approval. Zero means no permitted pause; it does not mean unlimited. The
organization's annual cap and the plan's single-pause cap must both pass.
Missing or unreadable settings/plan/budget refuses approval, never becomes zero
prior usage or an invented default. This decision does not invent a sold
allowance snapshot that old memberships never stored. A different meaning for
plan allowance requires an explicit owner choice before freeze.

## Required protection

Close OPEN-016 with additive database allowance enforcement on the existing
pause source, not just a web wrapper. Ordinary desk approval and direct
authenticated source writes must use the same authoritative checks and a
member-scoped serialization protocol. Two approvals competing for the last
days cannot both succeed. Settings and plan changes require fresh checks;
failure, lock refusal and rejected approval leave the source and allowance
unchanged. Final public helper/guard signatures, safe lock order and refusal
precedence must be frozen serially before independent authors start.

Preserve the current configured approver role, distinct staff requester and
approver, immutable attribution and unchanged paid membership dates. The
member request remains staff-sponsored under the SLF proposal. No solo-owner
exception, new paid days, automatic renewal, credit or money movement is
introduced. Cancellation/withdrawal and overlap protection remain required.

## Owner decision

Approve the retained start-year/member annual rule, current-plan single-pause
cap with zero meaning none, and the additive database closure of OPEN-016;
or specify the intended year/plan allowance meaning. Approval settles the
commercial boundary, not the still-pending PAY or notification contracts.
