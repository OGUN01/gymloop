# WSP retained schema inventory — mechanical declaration

Frozen 2026-10-04 before independent inventory/foreign-key fixture reconciliation.
This records the existing registered names and tenant/member integrity required
by WSP-003, WSP-010 and the approved manual-release-scope amendment. It introduces
no activation, provider send, wallet movement, user permission or new API.

The retained dormant transport has exactly these eight public WSP tables:
`whatsapp_sender_accounts`, `whatsapp_template_revisions`,
`whatsapp_rate_versions`, `whatsapp_channel_consents`,
`notification_whatsapp_attempts`, `notification_whatsapp_receipts`,
`whatsapp_dispatch_requests` and `whatsapp_command_keys`.
The last two persist bounded dispatch requests and idempotent command facts;
manual release does not remove their retained security/retention invariants.
These names are already recorded together in `docs/registry.md`; closed public
table inventories include all eight. This is not an open-ended table allowlist.

Attempt-to-consent integrity must bind the consent id and tenant to the same
consent row. Required column mappings are `consent_id` to `id` and `tenant_id`
to `tenant_id` on `whatsapp_channel_consents`. A stronger composite constraint
may also bind `member_id` to `member_id` on that same row; it must not substitute
another mapping for either required pair. Referencing/referenced ordinal order
and deparsed SQL formatting are not contract behavior. Independent catalogue
checks zip `conkey` with `confkey`, require the two mappings and admit only the
specified additional same-member mapping, rather than assert incidental arity
two or formatting. Runtime foreign-tenant/member consent denials remain required.

All existing role, consent, guardian, money, replay, grants and fail-closed
requirements remain unchanged. No implementer receives held diagnostics.
