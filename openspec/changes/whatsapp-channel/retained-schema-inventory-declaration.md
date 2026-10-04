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

The generic-purpose consent and WhatsApp-number opt-in are distinct evidence.
The existing attempt `consent_id` retains its reference to `public.consents`;
it must not be repurposed as a WhatsApp opt-in id. Service-category rules retain
their existing treatment of absent generic-purpose consent. The earlier text
incorrectly conflated those references and is corrected here before any builder.

Every retained transport attempt additionally stores `channel_consent_id uuid
not null`, selected by trusted preparation from the exact current granted
`public.whatsapp_channel_consents` row for that tenant/member, category and
current adult/guardian recipient revision. A composite foreign key binds
`(tenant_id,member_id,channel_consent_id)` to `(tenant_id,member_id,id)` on that
table, backed by the referenced unique key and a tenant-leading attempt index.
The reference is immutable with the attempt's causal registration facts. No
ordinary caller chooses the reference or gains access to protected attempt
data. Both claim and immediately-before-I/O authorization re-prove that this
exact opt-in evidence remains the current effective grant; withdrawal, a newer
decision, recipient change or foreign-member substitution creates no provider
request/debit and follows WSP-003's existing refusal/release rules. No historical
opt-in is invented. The uncommitted inert migration introduces empty transport
tables, so no backfill of production attempt history is authorized or required.

Referencing/referenced ordinal order and deparsed SQL formatting are not
contract behavior. Independent catalogue checks zip `conkey` with `confkey`
and require the three named mappings, while behavior checks independently
exercise cross-tenant/member substitution, missing/revoked/stale opt-in and
lawful current grants. Existing generic-purpose evidence checks remain intact.

All existing role, consent, guardian, money, replay, grants and fail-closed
requirements remain unchanged. No implementer receives held diagnostics.
