# PTF member booking surfaces — public declarations

Status: orchestrator-frozen engineering declarations, 2026-10-03, following
the owner's approval of member-policy-read-amendment.md. No booking, money,
identity, refusal-order or policy requirement changes. PTF-029/030 and the
original bar remain binding. Independent tests precede the separate builder.

## Web seam

```ts
// apps/web/app/member/classes/training/pt-actions.tsx
type PtBookingFacts = {
  pack: PtPack | null;
  slots: PtReadSection<{ startsAt: string; endsAt: string; timezone: string }>;
  policy: PtPolicyRead;
  sessions?: PtReadSection<PtSession>;
};
declare function PtBookingForm(props: {
  orderId: string;
  scopeKey: string;
  nouns: BusinessNouns;
  initial: PtBookingFacts;
  refreshFacts: () => Promise<PtBookingFacts | null>;
}): React.ReactNode;
```

PtPack, PtReadSection, PtPolicyRead and BusinessNouns are existing registered
shared projections. This component reuses ClassConfirmation and the Chalkline
kit. It adds no caller client, private settings access or command endpoint.

The default booking page remains
`app/member/classes/training/book/[orderId]/page.tsx`, with Next's ordinary
`{params: Promise<{orderId:string}>}` signature. It authenticates the member,
validates the order id and loads only that caller's projections through the
registered loadMemberTraining, loadMemberSlots and loadMemberPtPolicy adapters.
The server action refreshFacts revalidates the complete original user, tenant
and member before using the fresh authenticated client. A mismatch/refusal
returns null, never facts belonging to the new caller. scopeKey identifies
that complete original scope; it is presentation metadata, not authority.

## Native seam

`apps/mobile/app/training/book/[orderId].tsx` retains the default screen export
and no supplied caller props. It uses the registered useLocalSearchParams,
useMobile, loadTraining, loadSlots and loadPtPolicy boundaries. Route params
select only a valid own order; readiness, complete member identity and the
current supplied API/Supabase clients determine the presentation lifetime.
Route focus is also part of that lifetime. Leaving a mounted native stack
screen permanently revokes its sheet, retry capability and awaited callbacks;
returning creates a fresh lifetime and cannot reactivate a retained callback.
The installed `expo-router` `useFocusEffect` export is the declared focus host:
it accepts a memoized effect returning a cleanup callback. Independent native
hosts invoke that cleanup on blur while keeping the screen mounted, then run
the effect anew on focus. No other navigation hook/provider is introduced.
The root Expo Stack already admits filesystem routes; no additional stack,
provider, dependency or invented route authority is required.

## Current facts and commitment

Both surfaces show days/open times for the next 14 inclusive gym-local dates,
using PT_BOOKING_LIMITS.slotRangeDays, toLocalDate and the existing classDayStrip
calendar helper. The supplied current caller can read its own organization
timezone through the existing RLS path (web loadBusinessOrganization; native
the existing caller client). Validate the zone and retain the established UTC
fallback. Returned slots retain their own timezone for displayed times and
grouping; the client never invents an open time or calculates trainer grids.

A new, not-yet-submitted sheet refreshes own pack, slots and the current two-field
policy. Only an exact returned future slot for a current canBook live pack and
a successfully parsed policy enables Confirm. The displayed programme,
trainer, start/end and timezone come from those facts; the exact policy feeds
ptBookingConsequence. Loading, missing/error policy, unavailable pack, failed
or missing slots and revoked caller/unmount cannot dispatch a booking.
Refresh again before a new command: changed displayed pack/slot/policy facts require
renewed confirmation. The database remains the final command-time authority.

Commit remains POST `/api/member/pt-bookings`, with exactly
`{orderId, sessionId, startsAt}`. Mint a UUID once per sheet; an explicit retry
retains that sheet's original UUID and command facts. A changed/reopened sheet
cannot silently rewrite or replay a prior submitted command. Decode the
existing exact booking answer and refusal mapping; a wrong/malformed answer
is not success. Do not automatically replay, queue offline commands or retain
module-global/private persisted member facts. After every awaited read or
native network preflight, recheck the permanent original lifetime before the
next read, command or UI publication. A false/throwing final guard sends
nothing. Retry feedback stays truthful; unknown transport failure is no
evidence that booking succeeded.

PTF-011's existing uncertain-command replay takes precedence over a new-command
eligibility refresh. After an attempted submission with an unknown outcome,
retain the exact original body and offer only an explicit retry/reload decision.
The member may retry that body while the original permanent caller lifetime
and live connectivity remain valid, even if a fresh read no longer lists that
slot or shows the pack exhausted/closed. The server resolves replay before
current eligibility and returns the session's current status. Render that
status truthfully; a replay of a later cancelled/completed session must not
claim a newly booked session. A closed sheet loses its retry capability and
must not transfer a previous body to a reopened/new selection.

PTF-Q2 also requires the absolute cancellation cutoff before Confirm, including
when the slot is already inside the window and the pinned consequence sentence
contains no date. Reuse the registered `ptCancellationConsequence` cutoff from
the same freshly parsed policy and selected start; render it with the existing
date/time formatter and the selected slot's gym-defined trainer/branch timezone
(proposal quality point 7), naming that zone. Keep the exact consequence
sentence alongside this neutral cutoff fact; never derive it from a default.

The booking answer does not carry effective consumption. For a returned
`cancelled_by_member` answer, refresh the original caller's authoritative
Training projections before choosing a consumption-sensitive label. The
optional `sessions` facts carry the existing `PtSession` projection from
upcoming/history reads; production loaders populate them without a new RPC.
Only an exact session/order/recorded-interval match with actual boolean
`consumed` authorizes “Cancelled by you” or “Cancelled late - session used”.
Missing/failed/nonmatching projections leave the command acknowledged with
neutral “Cancelled. Reload to check whether a session was used.” feedback.
They never infer consumption from current policy, the answer's cancellation
window, an earlier read, or a hardcoded false value. Recheck original lifetime
after this awaited read; failure must not automatically resubmit the command.
The neutral cancellation feedback is ordinary feedback, not an additional
StatusWord/Status label: PTF-Q5's six existing status words remain the complete
status vocabulary. Only established effective consumption enables its matching
cancelled status word.

## Verification ownership

Independent visible and held authors cover actual web/native surfaces,
current-caller page refresh, current policy changes, own order/slot selection,
invalid/foreign route inputs, exact command/retry identity, boundary/refusal
states, unknown response, offline no queue and permanently revoked callbacks.
They may mock only the declared caller/read/transport/network/kit host seams;
neither sees source or the other suite. Root commits their RED suites before
the separate implementer. A fresh blind source critic and the complete final
browser/Android booking journey remain required.
