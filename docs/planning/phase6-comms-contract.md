# Phase 6 communications and wallet contract

Normative under ADR-111, 2026-09-10; implements COM-001–009, PAY-001–003,
INT-002/003, DPD-002–004 and STK-004. Read with `phase6-contract-seam.md` and
`phase6-implementation-order.md`. This freezes the communications slice for
independent authors; it creates no implementation or tests. Phase 5 must
be gated and archived before this becomes the Phase 6 OpenSpec. The existing
comms/authorization specs remain authoritative except for the explicit narrow
commands and strengthened invariants below. No provider adapter, invitation,
email sender, SMS sender or WhatsApp Business sender is included.

## 1. Shared boundaries and exact errors

All new functions set `search_path=''` and fully qualify objects. Reuse the
registered claim accessors and four role gates; introduce no fifth gate.
Revoke default PUBLIC/anon execution. Private trigger/write helpers are owner-only;
the pure transition/category helpers grant authenticated/service_role EXECUTE,
the default-window helper only service_role. Other callable ACLs are stated below.
Public gym mutations derive tenant and actor from verified claims, require a
real active same-gym staff row matching `auth.uid()`, staff id and role, and
reject impersonation. Every private write helper also rejects impersonation.
A callable definer checks impersonation first, even for service privileges.
Existing table grants and RLS stay intact; there is no general member or front-desk notification-write policy.

Before looking up a target or replay key, commands enforce their role. An
absent/invisible/cross-gym target gives `P0002` / `not_found` / HTTP 404 with
identical public text. `42501` maps to `forbidden` / 403; missing verified
session remains `not_signed_in` / 401. Public errors never contain SQL detail,
constraint names, phone numbers, other-gym ids or existence clues.

| SQLSTATE | Exact message / API code | HTTP | Meaning |
|---|---|---:|---|
| GL065 | `invalid_consent` | 422 | Blank version/source, invalid consent attribution or missing required consent facts. |
| GL066 | `invalid_notification` | 422 | Illegal graph edge, frozen content/identity mutation, inconsistent event evidence, unsupported user channel or unclassified new message. |
| GL067 | `insufficient_credits` | 409 | A credit movement would put the locked wallet below zero. |
| GL068 | `idempotency_conflict` | 409 | Existing command key has different canonical request facts. |
| GL069 | `invalid_provider_evidence` | 422 | A trusted paid-acceptance request lacks valid positive cost or acceptance identity, or tries a free channel. |

Within a command: authorization/target visibility → basic request validation →
exact replay/conflict → current state/consent → credit availability. A replay
does not revalidate facts that subsequently changed or append any event. The
WhatsApp URL exception in §5 always rechecks consent before exposing an action.
Within notification invariants, identity/content freeze precedes graph/evidence
validation; both use GL066. Native RLS/FK/CHECK/unique/type errors retain their
own timing; no universal order over PostgreSQL constraints is promised.
`40P01`/`40001` mean rolled-back, retryable work, never a successful command.

All request keys below are UUIDs, normalized by PostgreSQL UUID parsing. Text
fields are trimmed at both RPC and route boundaries; no internal whitespace,
case or Unicode rewriting. Money is integer paise with explicit currency;
credits are integer counts, not rupees. JSON money, credits, counters and
numeric components are canonical decimal strings (`0` or nonzero-leading
digits; negative values have one leading minus). Keep strings/BigInt until
formatting. No bigint/numeric value crosses JSON as a JS number. Delta/cost
inputs use signed/nonnegative strings within PostgreSQL bigint range; sums
and products use exact `numeric`, without bigint intermediate overflow.

## 2. Schema and indexes

Reuse `notification_channel`, `notification_status`, `consent_purpose` and
existing composite tenant FKs. Add one classification enum, `message_category`,
with labels `renewal`, `payment`, `fulfilment`, `promotion`, `motivation`.
It is generated into database types, never duplicated as a TS vocabulary.

| Table | New columns and invariants |
|---|---|
| `message_templates` | `category message_category NULL` for historical rows. New/activated templates require a category, trimmed nonempty key/body and existing supported locale (`en` or `hi`). `renewal_reminder` is a reserved system key and cannot be authored through gym CRUD. Template bodies are literal plain text in v1; no executable markup or invented interpolation language. |
| `consents` | `request_key uuid NULL` for historical/direct entries. Product commands require it. Preserve append-only privileges. New decisions always have a real claim-stamped staff actor under RLS. Historical null actors/timestamps are not rewritten. |
| `notifications` | `template_id uuid NULL`, composite FK `(tenant_id,template_id)` to templates; `category message_category NULL` for history; `source_notification_id uuid NULL`, composite same-tenant self FK; `recipient_phone text NULL` with the existing member E.164 format CHECK; `failed_at timestamptz NULL`, `opted_out_at timestamptz NULL`, `opted_out_reason text NULL`. New product rows require a category and nonnull dedupe key. Source rows and children must have the same member. WhatsApp children snapshot recipient_phone. |
| `messaging_wallet_ledger` | `request_key uuid NULL`, `recorded_by_user_id uuid NULL` FK to `platform_users(user_id)`, `balance_after_credits bigint NULL CHECK >=0`. All three may remain null on historical entries. New adjustment entries require key, active super-admin actor and resulting balance. Notification debits require null platform actor, a key and resulting balance. |

Add unique `(tenant_id,request_key)` WHERE key IS NOT NULL to consents and
wallet ledger. Replace the consent current-state index with
`(member_id,purpose,recorded_at DESC,id DESC)`; preserve tenant-leading and
actor indexes. Add notifications indexes `(tenant_id,template_id)` and
`(tenant_id,source_notification_id)` and unique `(tenant_id,source_notification_id)`
WHERE source IS NOT NULL AND channel='whatsapp_link'. Add unique
`(tenant_id,notification_id)` on ledger WHERE notification_id IS NOT NULL,
and an index on `recorded_by_user_id`. Keep the existing notification dedupe,
queue, member and related-record indexes. No second queue table is added.
Template `(tenant_id,id)` needs a composite unique key for its new FK.

Before migration, assert every existing wallet equals its ledger sum. The
2026-09-10 observed IronBox baseline is exactly 4500/4500; create no opening
entry. A later mismatch fails the migration for separately justified repair.
Do not fabricate historical message categories, delivery events, consent or
ledger actors. Old history remains readable. Unclassified historical scheduled
rows cannot send: fail with `classification_missing`; terminal history stays
unchanged. Seed fixtures must reach new events honestly through the new rules.

## 3. Consent and the serialization point

`public.record_consent(p_member_id uuid,p_purpose consent_purpose,p_granted
boolean,p_version text,p_source text,p_request_key uuid) RETURNS jsonb` is
VOLATILE SECURITY INVOKER, executable by authenticated only; requires
`app.is_front_office()` plus the real staff identity. Returns exactly
`{consentId,memberId,purpose,granted,version,source,recordedAt,recordedByStaffId}`.
All values come from the accepted row; exact replay returns the same object.
The key binds member, purpose, granted, normalized version/source and actor.
Lookup a tenant/key replay before taking a member lock; race resolution after
the lock/unique conflict compares the same immutable facts, never an upsert.

An invoker VOLATILE BEFORE INSERT invariant `app.stamp_consent()` covers direct
table inserts too. It locks the visible same-gym member FOR UPDATE, then in a
fresh SQL command reads the latest row for that member/purpose ordered by
`recorded_at DESC,id DESC`. It stamps recorded_at to
`greatest(clock_timestamp(), last_recorded_at + interval '1 microsecond')`;
with no previous row use clock_timestamp(). One microsecond is named as the
database timestamp precision, not a configurable product delay. New client
timestamps are ignored; a supplied different actor is GL065, a missing actor
is filled from the verified staff claim. This actor rule applies under RLS;
trusted history loading may supply an honest actor, but cannot skip monotonic
ordering. Blank version/source fails even in trusted context.

`app.notification_consent_purpose(p_category message_category) RETURNS
consent_purpose` is IMMUTABLE INVOKER: promotion→marketing; every other category
→service. Missing category fails closed. Motivation also requires current
`members.motivation_push_enabled=true`. Missing/withdrawn consent is refusal;
the latest decision in each purpose stands independently. There is no implied
consent from purchase, import, attendance, device registration or trial.

Every send/availability/WhatsApp decision takes that same member FOR UPDATE
lock before the notification lock, then reads current consent in a separate
fresh SQL command in a VOLATILE routine. Do not combine lock acquisition and
consent lookup in one stale CTE/snapshot. Check member, organization and
motivation eligibility under that lock too. Withdrawal committed before this
serialization point prevents the new action. A send serialized first remains
a truthful historical send; withdrawal does not retroactively erase it.
Two decisions in one transaction, including grant then withdrawal, obey this
ordering. Batch commands acquire member ids in ascending UUID order.

## 4. Lifecycle and ordinary send command

`app.notification_transition_allowed(p_from notification_status,p_to
notification_status) RETURNS boolean` is IMMUTABLE INVOKER. Same-state is
allowed; the only changing edges are:
`scheduled→sent|opted_out|failed`, `sent→delivered|failed`,
`delivered→clicked|converted`, `clicked→converted`. Failed, opted_out and
converted are terminal. A failed stage is never recreated with another key;
v1 has no retry edge that the canonical graph does not permit.

An invoker invariant `app.enforce_notification()` applies on INSERT/UPDATE.
For new base renewal rows, it enforces the reserved system identity directly:
channel=in_app, category=renewal, template_key=renewal_reminder, no template_id
or source, related_type=membership and related_id/member matching the visible
same-gym membership. The cycle date equals that membership's current ends_on,
the window id is one configured for this gym and matches the current local
date, and dedupe_key equals the exact grammar in §6. Validate the exact renewal
payload and due value against the shared helper under the same member lock.
No caller may bypass the key by supplying another template key/category or
payload while naming a reserved renewal identity. Direct authenticated writes
cannot create base renewal rows (42501); their creation belongs to the trusted
scheduler, whose inserts still obey these structural checks. WhatsApp renewal
children obey the distinct source/child identity in §5, never a second base key.
New rows start scheduled with all event timestamps/reasons null. Freeze id,
tenant, member, channel, template identity/key, category, source, recipient, dedupe key,
scheduled_for, related identity and payload after creation. Templates are
snapshotted at scheduling; later copy/category edits do not alter queued rows.
No caller may backdate a new event; the database stamps clock_timestamp(),
clamped no earlier than its preceding event. Existing event timestamps cannot
change. Same-state writes cannot add evidence. `failed_at` pairs with a
nonempty failed_reason; opted_out_at pairs with opted_out_reason. Sent requires
sent_at; delivered requires sent_at/delivered_at; clicked additionally requires
clicked_at; converted requires sent_at/delivered_at/converted_at and retains
clicked_at only if an actual click preceded it. Failed after sent retains
sent_at; failure before sending leaves all delivery timestamps null.

The trigger is INVOKER, so its `current_user` preserves the actual privilege
context. Direct authenticated updates cannot record WhatsApp opening or
delivery/click/conversion: they may only make the same in-app availability,
unconfigured-push failure or opt-out decision as send_notification, enforcing
the same member lock/fresh read. Setting an app_role claim does not elevate
current_user. Metadata checks fix the two narrow definer owners to postgres;
authenticated cannot SET ROLE to that owner or call a generic state setter.

For in_app sent→delivered, require current_user=postgres plus a verified member
claim/auth.uid()/eligible member/tenant match to OLD and NEW. For creation and
scheduled→sent of a WhatsApp child, require current_user=postgres plus verified
active front-office staff/role/auth.uid()/tenant, the matching in-app source,
unchanged member/body/category/relation and the current recipient snapshot.
Repeat these evidence checks in the invoker invariant as well as each narrow
RPC; definer context alone never authorizes an arbitrary target or edge. The
renewal job uses its separately granted trusted service context for scheduled
in-app creation/availability only. V1 exposes no click/conversion writer.
There is no client-settable trust flag/GUC. Graph/content/evidence rules never
exempt service-role writes; privileged maintenance still cannot create a new
product delivery without its required member evidence.

`public.send_notification(p_notification_id uuid) RETURNS jsonb` is VOLATILE
INVOKER, authenticated only, requiring a real gym admin. It sends only an
existing own-gym scheduled row at/after scheduled_for. Ineligible organization
or member gives opted_out with reason `recipient_ineligible`; missing service
or marketing consent gives `consent_withdrawn`; disabled motivation gives
`motivation_disabled`; an obsolete/paid renewal cycle gives `renewal_stopped`.
Future scheduled time is GL066. In-app becomes sent at zero cost. Push becomes
failed with `provider_unconfigured`, null sent/delivered_at and zero cost.
whatsapp_link requires §5; SMS/email are GL066 and have no v1 send action.
An already processed row returns its current NotificationResult without UPDATE.

NotificationResult is exactly `{notificationId,memberId,channel,status,sentAt,
deliveredAt,failedAt,failedReason,optedOutAt,optedOutReason}` with explicit nulls.
Member list/detail GETs never mutate. Staff `/messages` shows scheduled/sent/
delivered/failed/opted-out rows and drill-down counts from identical filters;
front desk sees consent/action sections, while template/wallet sections require
gym admin. `/member/messages` reads only own in-app sent/delivered messages and
shows consent history separately. No queue entry is described as delivered.

## 5. Narrow member and WhatsApp commands

`public.acknowledge_notification(p_notification_id uuid) RETURNS jsonb` is
VOLATILE DEFINER, authenticated only. Require a complete member claim,
auth.uid() linked to that own-gym member (not cancelled/blocked, erased_at null),
no staff claim and no impersonation. Resolve only a notification with that exact tenant/member and
channel=in_app; other ids are indistinguishable P0002. It permits only
sent→delivered and returns NotificationResult; already delivered is an inert
replay. Other states give GL066. It cannot change payload, identity or another
notification. A withdrawal after availability does not prevent acknowledging
an already-sent historical message. `POST /api/member/notifications/[id]/delivered`
runs only after explicit opening/acknowledgement of the rendered message,
never from prefetch, list visibility, hydration or a background effect.

`public.open_notification_whatsapp(p_notification_id uuid) RETURNS jsonb` is
VOLATILE DEFINER, authenticated only, with a real front-office identity. The
input is an own-gym in_app source notification already sent/delivered. Under
the member lock it freshly checks consent/category/eligibility and source
renewal state. Any refused current consent/eligibility/renewal decision returns
403 `communication_opted_out`, creates no child and exposes no URL. Otherwise
it creates/reuses exactly one whatsapp_link child with
`dedupe_key='whatsapp:' || source.id::text`, same member/category/relation,
source_notification_id, current E.164 recipient_phone and immutable payload snapshot. It transitions that
child scheduled→sent and returns exactly `{notification:NotificationResult,
url}`. URL is `https://wa.me/<snapshot phone without +>?text=<encoded body>`;
body is plain text from the source. No delivery/click/conversion timestamp is
written. Label this event “Opened in WhatsApp”, and never charge a credit.

The source id is this action's deterministic request identity; no second UUID
nonce can create another child. Repeated opening while eligible returns the
same child/URL without row, timestamp or audit changes. If the current member
phone differs from the child's frozen recipient_phone, refuse with GL066;
never rewrite a sent recipient or open the link to the old number. Withdrawal before a
repeat refuses a new URL with 403 `communication_opted_out` and changes no
already-sent child. Withdrawal before first opening creates no send/child and
gives the same code. The URL is returned only from the POST action; a GET never
exposes a fresh send action. A browser opening WhatsApp is not proof that the
member received anything. This narrow command adds no front-desk table grant.

## 6. One renewal formula and idempotent daily stages

`app.membership_renewal_remainder(p_tenant_id uuid,p_membership_id uuid)
RETURNS jsonb` is SQL STABLE INVOKER, read-only, callable by authenticated and
service_role inside other routines. Missing/unreadable membership returns SQL
NULL. Exact object: `{membershipId,memberId,currency,endsOn,pricePaise,
discountPaise,netPricePaise,periodsGranted,eligiblePaidPaise,residualPaise,
duePaise,receipts}`; receipts are id-sorted `{paymentId,amountPaise}` rows.
Use Phase 5's exact predicate: same tenant/membership/currency payments with
status paid/refunded/reversed. Do not subtract refunds or require a new date
predicate: money already returned still bought the recorded periods.
`A=price-discount; T=sum(receipts); R=T-periodsGranted*A;
due=CASE WHEN A=0 THEN 0 ELSE greatest(0,A-R) END`.
Do not clamp R or silently reconcile inconsistent historical grant counts.
Every integer field is a decimal string. Dashboard MET-005 and the scheduler
call this exact helper; neither repeats the formula. The containing metrics
statement provides one snapshot and asOf; this helper never reads the clock.

`app.default_renewal_reminder_windows() RETURNS TABLE(window_id text,
days_from_expiry smallint)` is private IMMUTABLE INVOKER, generated from the
existing registered `RENEWAL_REMINDER_WINDOWS` constant. The migration payload
is generated, not retyped. A drift check compares the newest generated SQL
payload's ordered rows to that TS constant; later changes require a generated
forward migration. No generated database types are hand-edited. Null gym
offsets use that helper; an empty array disables reminders. Custom arrays
contain finite nonnull smallints, deduplicated and numerically sorted, with
ids expiry_minus_N / expiry_day / expiry_plus_N. Malformed arrays fail the
settings CHECK with 23514; changing settings never rewrites existing messages.

`app.run_renewal_reminders(p_tenant_id uuid) RETURNS jsonb` is VOLATILE INVOKER,
service_role/owner only. `public.run_renewal_reminders_all() RETURNS jsonb` is
VOLATILE INVOKER, service_role/owner only, not an authenticated RPC. Each gym
uses statement_timestamp() and its stored timezone to compute one local date;
the all-gym function visits tenant ids in ascending order in that same SQL
statement. Complete each gym's work atomically. A failure propagates and rolls
back the calling transaction. The all-gym result is `{runs:[RunResult...]}` in
tenant order. RunResult is exactly `{tenantId,localDate,timezone,evaluatedAt,
createdCount,sentCount,optedOutCount}`. Counts describe new events in this
invocation: an unchanged rerun returns zero new counts. No user-supplied
date/asOf or completed-run cache/table is added.

The cron name is `renewal-reminders-hourly`, schedule `0 * * * *`, command
`select public.run_renewal_reminders_all()`. Named cron registration is
idempotent; the cadence is recorded once as a SQL operational constant and
in the registry. Each invocation evaluates the current gym-local date,
including DST boundaries; no later missed-stage catch-up. Newly eligible facts
such as a consent grant or new membership can produce a previously absent
stage later that same day; existing cycle/window rows remain inert. Ineligible gyms create
no notification: require settings and active, or trial with nonnull
future trial_ends_at. Skip cancelled/blocked/erased members and cancelled/expired
memberships, missing ends_on, zero due, absent service consent or unmatched
offset. Pending/active/frozen memberships otherwise use their current ends_on.
`ends_on` being in the past does not mean status='expired': expiry_plus_3
remains useful on a renewable row retaining pending/active/frozen status. The
explicit expired enum is terminal under ADR-098/GL047, as is cancelled; those
rows require a new membership and remain excluded as the shared seam requires.

An offset matches exactly `localDate = ends_on + days_from_expiry`. Under the
member then membership locks, freshly re-read membership and remainder before
creation; recheck the offset against its current ends_on. The key is exactly
`renewal:<lowercase membership UUID>:<YYYY-MM-DD ends_on>:<window_id>`.
Existing key is inert irrespective of status; never update its amount/body on
rerun. Member locking plus the existing tenant/dedupe unique index makes
overlapping equivalent jobs converge on one row; no duplicate insert or audit
is committed. New row is in_app, category renewal, template_key renewal_reminder,
related_type membership, related_id membership UUID, scheduled_for=evaluatedAt.
Payload is exactly `{body,locale:"en",membershipId,cycleEndsOn,windowId,duePaise,
currency}`. Body: `Your membership ends on <date>. Renewal amount due: <currency>
<amount with exactly two decimal places>.` Format paise with integer arithmetic.
Create scheduled then make available as sent in the same transaction, with the
fresh consent decision in §3. A queued renewal is still eligible only if its
membership retains the same ends_on, permissible status and positive due.
Stopping a queued cycle produces opted_out/renewal_stopped; it never changes
already-sent history. The same cycle/date key cannot become a later renewal.

## 7. Wallet movement and future provider acceptance

`public.adjust_messaging_wallet(p_tenant_id uuid,p_delta_credits bigint,
p_reason text,p_request_key uuid) RETURNS jsonb` is VOLATILE DEFINER,
authenticated only. Require super_admin with a matching active platform_users
row, auth.uid() and no gym/staff/member/impersonation identity. Reject zero
delta or blank reason with native 23514 mapped to 422 `invalid_adjustment`.
Target must already have a wallet. The key binds tenant, signed delta, trimmed
reason and acting user. Lock the wallet before replay lookup; exact replay
returns `{ledgerId,tenantId,deltaCredits,reason,balanceAfterCredits,createdAt}`
from the original immutable entry, even if current balance later changed.
Conflict is GL068. Sum in numeric; negative is GL067, bigint overflow is 22003
mapped to 422 `credits_out_of_range`. Append one ledger row and update wallet
within that locked transaction; failure of audit/ledger/update rolls all back.

`app.record_wallet_movement(p_tenant_id uuid,p_delta_credits bigint,p_reason
text,p_request_key uuid,p_notification_id uuid,p_actor_user_id uuid) RETURNS
jsonb` returns the same adjustment result and is its private DEFINER helper; direct
execution is revoked from PUBLIC, anon, authenticated and service_role. Only
the owning command may call it. It owns the locked replay comparison, derived
balance_after_credits, server-created_at, ledger append, balance update and one
audit event; callers never supply resulting balance. Actor must match the
verified super-admin identity for adjustments. Current calls always have null
notification_id. No balance change lives in a BEFORE INSERT ledger trigger:
an ON CONFLICT DO NOTHING insert must never move a balance without a row.
Authenticated receives no table privilege. Future notification-linked entries
must be negative, same-gym, unique per notification and backed by accepted paid
evidence; a free/failed notification cannot acquire one. Privileged operator
history loading is outside these product commands and must retain balance/ledger
equality. No migration re-applies historical opening entries to current balance.

Future paid transport uses `app.accept_paid_notification(p_notification_id
uuid,p_provider_message_id text,p_cost_credits bigint,p_request_key uuid)
RETURNS jsonb`, a service-only INVOKER contract, never an authenticated route.
No implementation or grant is added in this phase. A later provider change
must bind a verified acceptance reference and fixed positive cost to
the notification, take member→notification→wallet locks, recheck consent,
reject insufficient funds before recording acceptance, and atomically mark
sent, append exactly one negative keyed ledger entry and audit. Its exact
result will be `{notification:NotificationResult,ledgerId,debitedCredits,
balanceAfterCredits}`. Key equivalence is notification, acceptance reference,
positive cost and tenant; a reused notification with another acceptance/key
is GL068. Provider-reference persistence and uniqueness are mandatory in that
future migration; the adapter/configuration contract must be frozen before it.

This is the database acceptance boundary, not a claim that PostgreSQL can
undo an external send. Reservation/transport/provider idempotency must be
settled with the actual provider before enabling paid sends. Phase 6 has no
configured paid path and does not fabricate acceptance evidence. In-app,
WhatsApp opening and provider_unconfigured push always have zero ledger rows.

## 8. Exact audit and endpoint shapes

Private uncallable definer audit writers (consent/notification triggers, the
wallet movement helper for wallets) append only to audit_log, retaining
auth.uid(), canonical actor role and null impersonation; subjectless scheduled
work uses null actor/role. occurred_at is server clock. Audit failure aborts
the operation. No historical audit backfill; exact command replays append none.

| Event | record_type / record_id | before → after; reason |
|---|---|---|
| `consent.recorded` | consent / consent.id | NULL → `{member_id,purpose,granted,version,source,recorded_at,recorded_by_staff_id,request_key}`; NULL. |
| `notification.scheduled` | notification / notification.id | NULL → N; NULL. |
| `notification.sent`, `.delivered`, `.failed`, `.opted_out`, `.clicked`, `.converted` | notification / notification.id | old N → new N on the actual changing edge only; failed_reason or opted_out_reason for those two events, otherwise NULL. |
| `messaging_wallet.adjusted` | messaging_wallet / tenant UUID | `{balance_credits:<before string>}` → W; submitted adjustment reason. |
| `messaging_wallet.debited` | messaging_wallet / tenant UUID | `{balance_credits:<before string>}` → W; ledger reason `notification_accepted` (future only). |

N is exactly `{member_id,channel,category,template_key,source_notification_id,
dedupe_key,status,scheduled_for,sent_at,delivered_at,clicked_at,converted_at,
failed_at,failed_reason,opted_out_at,opted_out_reason,related_type,related_id}`.
W is exactly `{balance_credits,ledger_id,delta_credits,notification_id,
request_key,recorded_by_user_id}`; integer values are strings. Audit excludes
message body, device tokens, phone and automatic updated_at. One wallet movement
has one wallet audit event, not separate balance/ledger duplicates.

Routes reuse `{ok:true,data}` / `{ok:false,error:{code,message}}` and existing
303 form handling. `POST /api/consents` takes `{memberId,purpose,granted,version,
source,requestKey}`; member/WhatsApp POSTs take no body facts; wallet POST takes
`{tenantId,deltaCredits,reason,requestKey}`. `POST /api/message-templates` takes
`{templateId?,key,channel,locale,category,body,isActive}` and uses ordinary
RLS-backed insert/update, gym admin only. It cannot mutate key/channel/locale
on an existing template; a new identity requires a new row. Screen readiness
is false for push, SMS, email and WhatsApp Business; platform configuration
presence alone never changes that fact.

Before authors start, register additions in the frozen OpenSpec inventory. Full
blind visible/holdout authors cover consent ordering, fresh-read withdrawal
races, daily/key races, direct-write bypasses, member/WhatsApp narrow privileges,
every graph pair, exact large-integer remainder components, negative-wallet races
and inert/audited replays. Implementation reads no holdout/unpublished author work;
no test/source combined commit or manual migration.
