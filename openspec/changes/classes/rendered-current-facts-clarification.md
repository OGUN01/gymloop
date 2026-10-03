# Classes current facts and lifetime integration — public metadata

Delegated integration of frozen CLS-018/031/033 and the existing caller-lifetime
requirements, 2026-10-03. No policy, actor, grant, booking/cancellation window,
notice, money or owner-pending prebooking requirement changes.

## Native command continuation

The five existing native command helpers in lib/classes.ts may accept one final
optional `shouldSend?: () => boolean` argument after their frozen arguments.
Existing calls retain their online-only behavior. This presentation guard can
only refuse: it cannot choose an identity, grant permission or replace the
server actor. Check it before work and after the helper's asynchronous network
preflight immediately before `api.post`. A false/throwing guard produces no
command or successful outcome. The pane supplies its captured permanent caller
lifetime, including unmount and A → B → A invalidation. No second identity source,
SDK lock, queue, dependency or API-client replacement is introduced.

## Web current-session read

Public MemberClassesView props add optional `scopeKey: string` and
`refreshSessions: () => Promise<MemberClassSession[] | null>`. ClassActions props
add optional `scopeKey: string` and
`refreshSession: () => Promise<MemberClassSession | null>`. Missing current-read
metadata fails closed for cancellation; optional presentation settings never
substitute for an authoritative deadline.

The member server page supplies an inline read-only server callback. It freshly
reuses requireAudience('member'), compares the parsed user/tenant/member with
the original verified render before any feature read, then reuses the existing
loadMemberClassSchedule and original bounded window. No callback identifier
argument, read route, RPC, grant, browser Supabase client, token prop, new claim
parser or public helper export is added. A changed/refused caller or read error
returns null without borrowing another caller. Each row derives its exact
session callback from that authorized result.

Refresh before preparing/reopening and before confirming an existing booking's
cancellation. Use the current exact booking id, scheduled status, canCancel,
cancelBy and branch-local time. A missing/mismatched row, failed read, closed
window or revoked lifetime submits nothing. Recheck the current clock at
confirmation; the inclusive cutoff remains unchanged. If returned confirmation
facts change, show the current facts and require a renewed explicit confirmation.
New-booking deadline repair remains owner-pending and cannot use client defaults.

The existing useClassCommand remains the command seam. Its obsolete callbacks
cannot start a fetch after unmount or permanent scope invalidation. Late results
cannot update feedback, refresh a replacement view or return success to an old
continuation. Optional scope metadata is a presentation lease, never authority.

## Current roster facts

A refreshed selected roster must use the current timetable session together
with current booking rows: status, capacity/counts, trainer and marking window
cannot remain the original selection after a refresh. An externally cancelled,
reassigned or unavailable session has the current explanation/controls, and
current server reads still decide authority. Reuse the existing bounded reads;
do not add an unbounded dataset or summary RPC.

Independent visible and held regressions precede separate source changes.
The already-frozen tap budget and seven-day paging remain separate acceptance
work; this packet changes neither.
