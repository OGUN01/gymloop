# Existing-session cancellation confirmation duration

Status: proposed owner clarification, 2026-10-03. Native cancellation confirmation
has received a third rejection of its completeness/consequence dimension.
AGENTS.md requires owner escalation; this proposal does not authorize a fix.

PTF-Q2 says Confirm shows session duration, while PTF-031 explicitly places
length on the new-booking sheet. The existing cancellation confirmation shows
start and consequence, but not the already-recorded duration. Safety checks now
pass source inspection; that does not resolve this presentation ambiguity.

Approve applying PTF-Q2's duration requirement to both booking and cancellation
confirmation on web and Android. Existing-session cancellation must show its
authoritative current startsAt and endsAt in the gym-local zone and the exact
recorded elapsed duration from those two instants. It must never substitute
today's gym session-length setting or silently round a legacy duration.
Unavailable or invalid interval facts refuse confirmation rather than inventing
a duration. A changed interval requires another explicit confirmation, as the
existing current-fact contract already requires.

No policy, money, cancellation consumption, endpoint, read projection, grant or
booking destination changes. After approval, independent visible and held
authors pin both platforms' existing cancellation presentation and changed
interval refusal/reconfirmation; their red commits precede the separate builder
and a new blind critic. Actual browser/Android and final full-v2 checks remain.
