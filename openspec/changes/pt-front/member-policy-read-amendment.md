# Member PT policy read — proposed contract repair

Status: proposed for owner decision, 2026-10-03. Existing booking and
cancellation authority, lock order, money records and policy history do not change.

## Problem and exact change

PTF D10 requires the booking sheet to show the gym's current cancellation window
and consumption policy. The approved five member projections provide session
cutoff/late/consumption facts for existing sessions, but a not-yet-booked slot
contains no policy. Members cannot read `organization_settings`. A default or
programme's sold cancellation prose would invent the current gym policy.

Add only `public.read_member_pt_policy() returns table (cancel_window_hours
integer, late_cancel_consumes_session boolean)`, a stable SECURITY DEFINER read,
owned by postgres with empty search_path and execute only for authenticated
(PUBLIC, anon and service_role revoked). It reuses exactly `app.pt_member_actor()`
for the existing complete real-member identity boundary, including active/trial
gym eligibility, member/user/tenant binding, erased and blocked/cancelled status
and malformed/contradictory claim refusals. No second validator or private-helper
grant is introduced. It returns one current same-tenant
settings row, and exposes no identifiers, finance fields or unrelated settings.
No argument may choose another tenant/member. Unknown, malformed, staff, platform
or impersonated claims are refused with 42501; a missing settings row is empty.
Both outputs are the same row's `pt_cancel_window_hours` and
`pt_late_cancel_consumes_session`. The read takes no locks and writes no data,
audit or notification.

Web `loadMemberPtPolicy(supabase)` and native `loadPtPolicy(client)` return
`{ data: { cancelWindowHours, lateCancelConsumes } | null, error: string | null }`
through this caller-scoped read. Errors are sanitized. This is separate from the
existing five-section training reader; no caller can reach a private table.
Every newly prepared or reopened booking confirmation fetches policy as the
current caller. Loading, null and failures disable Confirm and offer retry;
unknown policy never silently uses defaults.
The server remains authoritative if policy changes after that read.

Existing-session cancellation continues to use its current authoritative
session projection's cutoff/late/consumption facts, refreshed before confirmation.
No refund, quota, session balance, attendance or stored sold term changes.

## Pipeline

Freeze after owner decision, then separate implementation-blind visible and
holdout SQL/app authors, commits RED first, separate implementer and fresh blind
critic. Register the RPC/loaders and include the new routine in catalog/meta
contracts without widening any other privilege. Use a forward-only follow-up
migration, not an edit of the eight already
applied migrations. CI alone applies it after the whole preceding DB run is
green, with generated-type follow-up under ADR-177. Preserve all original
batch-2 tests and all gates, then exercise changed policy in actual web/Android.
