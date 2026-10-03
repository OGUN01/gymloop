# Class cancellation deadline before booking — proposed contract repair

Status: owner-approved and frozen, 2026-10-03 (five scoped batch-2 repairs).
No booking eligibility,
cancellation authority, identity, capacity, money or attendance change.

## Problem and exact change

CLS-Q4 requires the confirmation sheet to show an absolute gym-local free-cancel
deadline before booking. The frozen member schedule returns `cancel_by` only
when the caller already has a `booked` row. An open class therefore supplies no
deadline, and members cannot read `organization_settings`. Inventing a default
in the screen would fail the bar whenever the gym changes its setting.

Change only the existing `read_member_class_schedule(date,date)` projection:
`cancel_by` is non-null when the caller's booking status is `booked` **or** the
returned availability is `open`. It is the existing server calculation
`starts_at - current class_cancel_window_hours hours`, with the existing
server-side missing-settings default. Every other case retains null, and all
existing booked-row deadlines retain their current values. This reveals one
session-specific deadline, with no additional identifiers or settings fields.

The routine's signature, stable SECURITY DEFINER properties, postgres owner,
empty search path, grants, actor validator, gym/branch/session visibility,
date-window limits, counts and own-booking projection remain unchanged. No new
RPC, table read policy, client-supplied tenant/member, lock, write, audit or
notification is introduced. `can_cancel` retains its existing definition and
never becomes true for an unbooked row.

Web and native confirmation preparation refresh the current caller's schedule
before enabling Confirm. Loading, read failure, missing row, changed availability
or missing deadline prevents commitment and offers the appropriate refresh or
refusal. The displayed absolute time uses the returned session timezone. No
screen calculates a deadline from a guessed gym setting. The server remains
authoritative if availability or policy changes after the read.

## Pipeline

After owner approval, freeze this amendment, obtain independent visible and
held SQL/application tests committed first, then a separate implementer and a
fresh blind critic. Preserve the original assertions except where this precise
new projection boundary supersedes an unbooked-null expectation. Register the
projection semantics. Use one forward-only follow-up migration; do not edit
the eight applied batch-2 migrations. CI alone applies it after the preceding
DB run is wholly green, with ADR-177 generated-type handling if required.
Exercise a changed gym policy and pre-booking deadline on web and Android.
