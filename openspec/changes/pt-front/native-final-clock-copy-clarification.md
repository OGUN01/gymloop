# Native Training final start clock and offline copy

Status: frozen clarification of PTF-013, PTF-030 and PTF-034, 2026-10-03.
No policy, endpoint, permission or booking eligibility rule changes.

An authoritative current row can arrive after its projection was computed.
Immediately before the existing cancellation command, after every awaited
read, connectivity or image operation, the native control must also compare
the current clock with that exact row's startsAt. Strictly before the start is
eligible for this clock check; at or after the start sends no command and shows
the pinned too_late_to_cancel sentence. No await separates this synchronous
check from the command invocation. Current cancellation facts, renewed explicit
confirmation, permanent capability lease and the free-cutoff check still apply.
The database continues to decide the actual command-time result.

Positive connectivity loss shows all the frozen offline presentation: the
last-loaded sentence, an explicit stale marker, and the pinned retry sentence
"Please try again." Disabled actions need not be pressed to reveal that copy.
Reconnect cannot submit anything automatically. This does not classify an
unknown connectivity result as positive offline or invent success.

Independent visible and held authors pause the actual confirming read across
the start, with otherwise valid late cancellation facts. They cover one
millisecond before, equality, and one millisecond after the exact start, ensuring
no stale command at equality or later. They also deliver a real public network
listener callback and check offline/stale/retry copy before any command press.
Their red tests precede the separate implementer and another fresh review.
