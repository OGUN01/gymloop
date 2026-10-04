# WSP pre-I/O consent refusal — mechanical clarification

Frozen 2026-10-04 before independent evidence authors resume. Read with
WSP-003 and the later frozen Wave C serial paid-child declaration. This selects
the existing durable attempt failure field; it adds no status enum, channel,
provider activation, recipient permission, retry or money movement.

A paid WhatsApp child is created only when service SQL successfully authorizes
provider I/O. If current channel consent fails before that point, no paid child
exists to mark opted out. The already-sent in-app source must not be regressed,
and absence of a paid child must not erase the durable refusal.

For an already-reserved attempt denied at final authorization because its exact
channel grant is missing, withdrawn, superseded or recipient-stale, record
`notification_whatsapp_attempts.failure_code='opted_out'` and its existing
server-timed `released_at` in the same transaction. Keep `io_started_at` null,
create no paid child, provider request or ledger debit, and preserve factual
source notification state and all consent/attempt history. The API returns the
existing safe refusal outcome; it must not raise an exception which rolls back
the mandatory release/refusal facts. Existing unknown-after-I/O handling stays
unchanged: this rule never clears initiated work or releases an uncertain hold.

Independent tests require the durable attempt marker and release as well as
no initiation/child/debit. They do not guess a nonexistent child's state or
replace a sent source's factual state. Preparation-time refusal before any
attempt retains the existing source/refusal outcome and must not invent an
attempt merely to carry this marker. All generic-purpose and channel-specific
consent requirements remain independent and unchanged.
