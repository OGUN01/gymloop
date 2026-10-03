# Announcement failure truth — proposed contract repair

Status: proposed for owner decision, 2026-10-03. No audience, consent,
version, receipt count, booking, money or mutation privilege changes.

The frozen ANC-021 blanket failed-fetch cache fallback conflicts with Q8's
permission-denied state. Its pinned generic refusal also promises "Nothing was
changed" for failures whose commit outcome cannot be established. Resolve only
these two boundaries, preserving the original quality bar.

## Native failed reads

A definitive unauthorized or forbidden feed response must display the ordinary
sanitized permission/sign-in failure, show no cached cards, and disable cached
acknowledgements. Discard only the refused current scope's persisted cards and
pending reads, with the same tenant/user/member and lifetime guards as writes;
a late refusal cannot erase a newer caller's cache. Do not call a permission
failure an offline state or silently resurrect those cards.

Other read failures retain the existing same-scope saved-copy fallback and its
time. A server/malformed-result failure must also give truthful refresh/retry
feedback. Offline wording requires actual disconnected/unreachable evidence;
an inconclusive network error is a refresh failure, not proof of being offline.
Successful authoritative reloads retain the existing feed and version rules.
The pure `resolveAnnouncementFeed` interface need not change.

## Unknown mutation outcomes

Keep every existing specific definitive refusal and the pinned generic sentence
for a confirmed refusal. Add a distinct `unknown_outcome` refusal sentence:
"The result could not be confirmed. Reload to check whether the announcement was saved."

Unexpected transport/server exceptions or a malformed/missing command result
whose outcome is unknown use `announcement_outcome_unknown` with that sentence.
They must not assert that no write happened or automatically replay a create,
publish, edit or take-down. Reload establishes the current authoritative state.
Known pre-command request/auth/permission failures retain their existing codes.
No body, token or individual member data is exposed in errors or logs.

## Pipeline

Owner approval precedes freeze and independent visible/held tests committed
first, then a separate implementer and a fresh blind critic. No SQL migration,
audience/RLS expansion, new dependency or generated-type edit is needed. Retain
all original tests except where these exact failure boundaries supersede a
blanket fallback/unknown-outcome expectation, and exercise the reachable states
on web and Android before claiming full acceptance.
