# Expired PT pack remaining count

Status: owner approved in the campaign chat on 2026-10-02: retain the explicit
expiry exception and show seven unused sessions in the example. The separate
implementer's draft and current tests do not yet prove the expired-with-unclosed-
scheduled boundary. Fresh contract review and independent test updates precede
the separate source correction.

PTF-005 defines sessions_remaining as max(total - used - scheduled, 0), shared by
member and staff reads. PTF-018 explicitly uses total - used for expired packs so
the owner can see unspent value. They differ when a pack expires while sessions
remain scheduled. A ten-session pack with three used and two still scheduled
would display either seven unused sessions or five unreserved sessions.

## Approved decision: retain the explicit expiry exception

For state expired only, both read_member_pt_packs and read_pt_packs return
sessions_remaining = max(sessions_total - sessions_used, 0).
sessions_scheduled continues to report the actual scheduled-row count separately.
All other states keep the frozen max(total - used - scheduled, 0) equation.
PTF-005 and PTF-032 explicitly acknowledge PTF-018's exception.

An expired pack remains unavailable for booking, can_book=false, and its order
status remains active. This changes no sessions_used, session status, sold term,
validity, refund, waiver eligibility, audit or money mutation. It introduces no
expiry sweeper or inferred attendance. Existing expired wording remains visible.

Both independent SQL authors add an expired pack with genuine unclosed scheduled
sessions and pin member/staff counts, actual scheduled count, refusal/no-write
evidence and unchanged live-pack counts before a separate source correction.
Independent app authors assert the same count and expired/unbookable presentation.
A fresh critic then checks this exact boundary and the unchanged money rules.

## Rejected alternative: use the common balance formula in every state

Amend PTF-018 to max(total - used - scheduled, 0), retaining the current shared
read-model equation without an expiry exception. The example would display five.
The same independent boundary tests and no-write/refusal evidence apply. This
changes the explicit expiry requirement rather than interpreting its exception.
