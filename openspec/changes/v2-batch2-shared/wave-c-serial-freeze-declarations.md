# Wave C serial freeze declarations — coordinator mechanical decisions, 2026-10-03

Completes the "Serial-owner mechanical freeze work" gap list at the end of
`wave-c-delivery-declarations-draft.md` (dec3278). These are engineering
declarations within already-proposed boundaries; they invent no approval for
the pending owner choices (NTF Edge/transport boundary — since approved 2026-10-03
with the scoped pre-configuration amendment, PAY's three money/stock choices —
since approved with resolutions folded into the frozen PAY proposal, F9 DLT
determination, WABA/provider facts). Test authors are commissioned against
these declarations; the serial notification-seam migration incorporates both
channels in one amendment.

## Serial decisions adopted (the one required decision, resolved)

1. **Facade/helper arrangement adopted as drafted:** each public transport
   facade is VOLATILE INVOKER with EXECUTE granted only to `service_role`,
   delegating to a same-named private `app` helper with identical arguments
   and result contract. Private helpers are narrowly justified DEFINER,
   `postgres`-owned, `search_path=''`, no EXECUTE to PUBLIC/anon/
   authenticated; they alone perform guarded writes, and direct `service_role`
   DML on the new transport tables is removed. Definer ownership is never an
   evidence predicate; helpers validate durable causal rows before every
   mutation.
2. **Conservative NTF revision rule adopted:** one durable attempt per
   `(tenant_id, notification_id, device_id)` with the authorized
   `token_revision` frozen on the attempt. Rotation never grants a second
   provider request for that event once `io_started_at` is set. Before
   `io_started_at`, an expired or refused reservation may be replaced under
   the same attempt only after fresh revision/eligibility checks; the old
   reservation becomes invalid. Other registered devices remain independently
   eligible. Supersedes the proposal's `app.reserve_push_attempts
   (p_tenant_id uuid, ...)` shape: the facade is
   `public.reserve_push_attempts(p_limit integer)` selecting tenants itself.
3. **Error precedence adopted** as drafted in dec3278 §"Error precedence",
   including the documented unregister replay exception.

## WSP paid child and fallback key grammar (frozen)

Existing manual command is unchanged: `open_notification_whatsapp` creates or
reuses the `whatsapp_link` child keyed `'whatsapp:' || source.id`. Wave C adds
no `notification_channel` value; the enum stays
`push | whatsapp_link | in_app | sms | email` and the BIZ copy audit is
unaffected. Manual and paid evidence stay on distinct rows:

- **Paid WhatsApp child** (created by service SQL when an attempt is
  authorized for I/O): channel `whatsapp_link`, dedupe key
  `whatsapp-paid:<source_notification_id>`, same frozen recipient snapshot,
  related ids and category as its source. Its `sent`/`delivered` evidence
  comes only from WSP's attempt/receipt path; it is never touched by the
  manual command and vice versa.
- **In-app fallback** (separate causal row, created once when a WhatsApp
  attempt ends known-failed or the desk fallback is surfaced): channel
  `in_app`, key `whatsapp-fallback:<source_notification_id>`, referencing the
  same source. Never charged, never a channel mutation.
- **Push fallback** reuses NTF's child grammar `push:<source_notification_id>`,
  so an already-existing push child of the same source dedupes instead of
  double-buzzing.
- Attempt uniqueness stays `unique (tenant_id, request_key)` plus one live
  attempt per notification and provider-id-per-sender uniqueness, per WSP.

## Source-event enablement cutoff (frozen)

No historical backfill. Dispatch eligibility requires, at event creation time
inside `app.run_push_events`, that the source notification's `created_at` is
not earlier than the tenant's per-channel activation instant:

- push: the frozen push-configuration revision timestamp for the tenant's
  Firebase configuration row;
- whatsapp: `whatsapp_sender_accounts` template-ready/compliance-approved
  revision timestamp.

An event created before its channel's activation is never dispatch-eligible,
even if the channel activates later. Existing in-app truth is unaffected.

## Operational reader envelopes (frozen)

- `public.read_push_campaigns(p_before timestamptz default null,
  p_before_id uuid default null)` — VOLATILE-free STABLE front-office definer;
  orders `created_at desc, id desc`; limit default 20, max 50; returns
  `{campaigns:[...], nextBefore: string|null, nextBeforeId: string|null}`
  (`nextBefore` null when exhausted). Aggregates are count integers serialized
  as canonical decimal strings; no tokens, recipient names, reservations or
  provider ids.
- `public.read_whatsapp_operations` — signature amended from the proposal's
  single `p_after uuid` (a random uuid cannot key a stable page) to
  `(p_after_created_at timestamptz default null, p_after_id uuid default null,
  p_limit integer default 50)`, max 100; orders `created_at desc, id desc`;
  returns `{operations:[...], nextAfter: string|null,
  nextAfterId: string|null}`. Role-dependent field visibility exactly as the
  proposal pins (desk sees readiness/refusal only; owner/manager additionally
  wallet amounts and charged totals; no provider ids/tickets/raw receipts).
- `public.read_member_purchase_requests(p_limit integer default
  MEMBER_PAGE_SIZE_DEFAULT, p_after_created_at timestamptz default null,
  p_after_id uuid default null)` and the front-office twin — max 100 rows;
  same `{requests:[...], nextAfter, nextAfterId}` envelope; own-member or
  front-office actor filtering per BUY-019.

All three: single-statement RLS-safe reads, no existence oracle for foreign
ids (empty page, not an error distinguishing existence).

## Grant/actor matrix (consolidated, frozen pending the shared-seam migration)

| Surface | SELECT | Commands |
|---|---|---|
| `member_devices` | none for anon/authenticated (token column never readable); staff/platform metadata only via safe RPC | none; transport projects tokens service-only |
| `member_notification_preferences` | own member (indexed JWT tenant/member) | member definer command only |
| `notification_push_campaigns` | current-tenant front-office; separately approved platform read | owner/manager review/cancel commands; desk preview read-only |
| `notification_push_attempts` | none (no anon/authenticated/PUBLIC grants) | service facades only |
| `whatsapp_sender_accounts` | owner safe read RPC | operator configuration path only |
| `whatsapp_template_revisions` | front-office safe SELECT | owner/manager choose checked revisions; provider facts service-only |
| `whatsapp_rate_versions` | owner safe read | service-only verified publication after owner tariff approval |
| `whatsapp_channel_consents` | own member safe SELECT; front-office safe projection | member definer + front-office recorder commands |
| `notification_whatsapp_attempts` / `_receipts` | none | service facades only |
| transport facades | — | EXECUTE `service_role` only; denied to every ordinary/platform/impersonation JWT, verified with `has_function_privilege` |

Trainers: no communications access anywhere. Front desk: no wallet/ledger
amounts. Platform preview: read-only everywhere.

## Bounded text, failure-code and evidence constants (frozen)

Registered in `packages/shared/src/config/constants.ts` at implementation;
values below are the freeze:

- Push token ≤ 4096 chars, nonblank, platform exactly `android`;
  `installation_id` a UUID; `token_revision` starts at 1.
- FCM failure-code allowlist and token-invalidation classification (HTTP v1
  `error.status`/details): token-invalidating = `UNREGISTERED`,
  `SENDER_ID_MISMATCH`, and `INVALID_ARGUMENT` whose details identify
  `registration-token-not-registered`; everything else (auth, quota,
  `UNAVAILABLE`, `INTERNAL`, `THIRDPARTY_AUTH_ERROR`, generic
  `INVALID_ARGUMENT`) is non-invalidating. Unclassified codes are treated
  non-invalidating and recorded verbatim.
- `provider_message_id` ≤ 256 chars; `failure_code` ≤ 64 chars; evidence
  digest = lowercase hex SHA-256 (exactly 64 chars); webhook request body
  ≤ 256 KiB; receipt `provider_at` accepted only within
  `[received_at − 30 days, received_at + 5 minutes]`; one receipt row per
  `(sender_account_id, receipt_fingerprint)`.
- WSP rejection failure codes are the documented Meta error/receipt classes
  mapped at implementation time into an allowlisted closed set
  (`template_blocked`, `recipient_invalid`, `rate_limited`,
  `account_mismatch`, `provider_rejected`, `unknown`); no raw provider body
  enters the column.
- Rejection/decision reasons 3…200 chars trimmed (BUY-011 rule reused); NTF
  campaign review confirmation carries no free text beyond the reviewed facts.
- Quiet hours `PUSH_PROMO_QUIET_START_HOUR=21`, `PUSH_PROMO_QUIET_END_HOUR=8`,
  `PUSH_QUIET_TIMEZONE='Asia/Kolkata'`; limits as dec3278 pins (NTF limit
  1–100, reservation 90 s, 100/min; WSP batch 1–50, ticket 120 s, 30/min).

## Cron, credential and observability declarations (frozen)

- One `pg_cron` job per channel worker (`push-dispatch-minute`, WSP's
  equivalent), text referencing a private helper and the Vault name, never a
  literal secret. Jobs enabled only after the exact deployment/configuration
  checks pass; missing secret/configuration leaves wakeup disabled or
  refused with an observable count-only operational failure, never a fallback
  to the service key, publishable key or dummy value.
- Vault: explicit denial of ordinary-role Vault access and of `net` queue/
  header inspection; no claim that transient HTTP headers are encrypted.
- Every facade's effective privilege is asserted with `has_function_privilege`
  for ordinary, platform and impersonation roles in the migration itself
  (ADR-074); assertions run inside the CI-applied migration, not comments.
- Adapter configuration failure stops dispatch, reports count-only failure,
  does not consume the queue and does not invalidate tokens. SQL separately
  checks activated configuration revisions; claims never pretend to detect
  credentials they do not possess.

## SQLSTATE allocation (frozen reservations)

GL codes are allocated through GL114 (CLS). Wave C takes:

- **NTF GL115–GL118:** GL115 stale/expired reservation or authorization
  (dispatch lease conflict, distinct from GL068 exact-replay conflict);
  GL116 dispatch configuration invalid or stopped; GL117 push target not
  authorizable (identity/consent/revision refusal at authorization time);
  GL118 push receipt/acknowledgement evidence conflict.
- **WSP GL119–GL122:** GL119 sender/template/rate not dispatch-ready;
  GL120 WhatsApp attempt/ticket stale conflict; GL121 causal debit refusal
  (tariff/receipt/currency mismatch); GL122 receipt evidence conflict.
- **PAY GL123–GL129 reserved** (not used until PAY's owner choices land and
  its contract freezes; no semantic is claimed for them yet).

Existing GL066 invalid-state, GL067 wallet insufficiency and GL069 disabled
paid stub keep their meanings; nothing is repurposed.

## Remaining before test authors start

Serial work now complete except items that cannot precede owner decisions:
the shared-seam migration waits for the primary's batch-2 checkpoint and
CI-only application order; PAY's proof-media extension is frozen in its
proposal; the NTF pre-configuration amendment pins the unconfigured default.
WSP's wallet-side declarations (WSP-101…109) are already frozen and
implemented by the primary; nothing here revalues or duplicates them.
