# Manual WhatsApp opening evidence — mechanical clarification

Frozen 2026-10-04 before independent assertion correction. This reconciles
WSP-M01/03 with the existing command expressly reused by the owner-directed
manual release. It grants no provider-send capability and changes no money,
consent, identity, recipient, deduplication or delivery rule.

Authority: `manual-release-scope-amendment.md` and the existing frozen
`docs/planning/phase6-comms-contract.md` section 5. The latter explicitly
defines `open_notification_whatsapp` as a factual opening: one manual child
transitions `scheduled` to `sent`, with its `sent_at` recording that opening.
Its required visible label is **Opened in WhatsApp**. These historical database
names are not evidence that a provider or person sent a message.

WSP-M03's "shall not mark a message sent" concerns actual sending evidence or
claims. Preserve the reused command's canonical manual-child status/timestamp
representation; do not introduce a new status, clear truthful opening history,
or assert that its `sent_at` must be null. Opening writes no `delivered_at`,
`clicked_at`, or `converted_at`; it creates no paid attempt, provider initiation,
wallet reservation or debit. The already-sent in-app source retains its exact
factual state and timestamps. UI copy and metrics must describe manual opening,
never infer that the staff pressed Send or that the recipient received/read it.

An exact eligible repeated opening returns the same child and URL without a
new row, timestamp or audit. Current withdrawal/recipient/guardian/identity
refusals still govern each opening. Failed opening creates no fictitious event.
Dormant paid attempts use their separate real authorization/receipt evidence;
manual status spelling is never evidence for paid dispatch or billing.

Independent tests preserve all no-I/O/no-money and delivery-tracking assertions
and verify the existing factual opening representation explicitly. Implementers
receive only this public declaration and visible tests, never held diagnostics.
No source, test or Cloud mutation accompanies this clarification.
