# Existing-session cancellation confirmation duration

Status: owner-approved and frozen, 2026-10-03. The owner approved recorded
duration and local start/end times in both platforms' cancellation confirmation
after the third rejection of the completeness/consequence dimension.

PTF-Q2 says Confirm shows session duration, while PTF-031 explicitly places
length on the new-booking sheet. The existing cancellation confirmation shows
start and consequence, but not the already-recorded duration. Safety checks now
pass source inspection; that does not resolve this presentation ambiguity.

Apply PTF-Q2's duration requirement to both booking and cancellation
confirmation on web and Android. Existing-session cancellation must show its
authoritative current startsAt and endsAt in the gym-local zone and the exact
recorded elapsed duration from those two instants. It must never substitute
today's gym session-length setting or silently round a legacy duration.
Unavailable or invalid interval facts refuse confirmation rather than inventing
a duration. A changed interval requires another explicit confirmation, as the
existing current-fact contract already requires.

No policy, money, cancellation consumption, endpoint, read projection, grant or
booking destination changes. Independent visible and held
authors pin both platforms' existing cancellation presentation and changed
interval refusal/reconfirmation; their red commits precede the separate builder
and a new blind critic. Actual browser/Android and final full-v2 checks remain.
