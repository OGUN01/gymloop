# Announcement live-membership boundary

Status: owner-approved and frozen, 2026-10-03. The owner chose status and inclusive
gym-local dates. Independent tests precede the isolated targeting fix.

A fresh blind critic found a conflict in the frozen glossary: it calls for the
check-in gate's live-membership predicate but cites its original status-only
version. The current check-in predicate also requires inclusive membership dates.
The draft's status-only filter admits an active membership starting tomorrow or
ending yesterday to `live` announcements and excludes it from `not_live`.

Approved amendment to ANC-006 and its glossary: evaluate live membership with
`app.member_has_live_membership(tenant, member, app.gym_today(tenant))`. It requires
status `active` or `frozen`, `starts_on` null or on/before the gym-local current day,
and `ends_on` null or on/after that day. Either qualifying membership suffices;
pending, expired and cancelled rows never qualify. `not_live` is the exact inverse.
The existing validated gym timezone fallback applies. Reuse the registered shared
predicate and day helper; add no new helper or permission.

All consumers keep the single audience function: member feed, read markers,
publish count, staff counts and delivery. Good standing, all-member targeting,
transactional/promotional consent, notice behavior and money records stay intact.
Separate visible and holdout authors pin current-day endpoints, tomorrow/yesterday,
null dates and opposite gym timezones before the isolated implementation change.
A fresh critic and the full rollback sweep follow. No real delivery or UI win is
claimed by these source checks.

Rejected alternative: intentionally retain status-only membership targeting.
Then the glossary must explicitly distinguish announcement segment status from
check-in eligibility; it cannot claim to use the check-in live predicate.
