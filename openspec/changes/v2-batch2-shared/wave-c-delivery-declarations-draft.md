# Wave C delivery declarations — DRAFT NOT FROZEN

2026-10-03. Public candidate for the serial contract owner; no author may treat
this as approval or start implementation from it. WSP's scoped Meta/INR
amendment is owner-approved (`a3a2a08`); the complete WSP contract and shared
seams are not frozen. NTF transport and Firebase prerequisites remain pending.
This document authorizes no setup, deployment, contact or purchase.

Sources: `docs/planning/phase6-comms-contract.md`, `docs/architecture.md`,
`docs/registry.md`, generated `Database` declarations for `notifications` and
`member_devices`, both channel proposals and their transport/provider-wallet
amendments. Existing registered commands/helpers are reused below. Additional
names are candidate declarations only, not exports or registry entries.

## Shared lifecycle, without a shared receipt fiction

Retain the canonical notification enum and graph: self; scheduled→sent,
opted_out or failed; sent→delivered or failed; delivered→clicked or converted;
clicked→converted. No reversal or new canonical state. Identity, channel,
source, immutable payload, recipient snapshot, dedupe key and scheduled_for
remain frozen. Same-state updates cannot manufacture evidence. Trigger checks
apply to privileged writes as well as ordinary writes.

`NotificationResult` remains exactly `{notificationId,memberId,channel,status,
sentAt,deliveredAt,failedAt,failedReason,optedOutAt,optedOutReason}` with explicit
nulls. SQL returns projections; HTTP routes wrap them in existing
`{ok:true,data}` / `{ok:false,error:{code,message}}`. Timestamps are server-stamped
ISO instants; bigint values are canonical decimal strings. No token, phone,
secret, provider id or lease appears in member/staff result envelopes.

| Existing seam | Candidate amendment |
|---|---|
| `public.send_notification(p_notification_id uuid) returns jsonb` | Retain VOLATILE INVOKER, real gym-admin actor and existing replay/eligibility rules. Configured push only admits SQL-owned transport work and returns current NotificationResult; it does not claim acceptance. Unconfigured push retains failed/provider_unconfigured with zero charge. Paid WSP uses its dedicated request command; manual whatsapp_link behavior is unchanged. |
| `app.enforce_notification() returns trigger` | Retain INVOKER. Dispatch edges require matching durable attempt and channel-specific causal facts, not a client-settable flag/GUC or merely current_user=postgres. Preserve structural/evidence checks on every transition and frozen fields. |
| `app.notification_transition_allowed(public.notification_status,public.notification_status) returns boolean` | Reuse unchanged; receipts traverse legal edges individually. |
| `app.notification_consent_purpose(public.message_category) returns public.consent_purpose` | Reuse existing category→purpose rule; external transactional push requires latest service consent. In-app ANC/CLS exceptions grant no external consent. |
| `public.acknowledge_notification(p_notification_id uuid) returns jsonb` | Preserve own in_app sent→delivered only. Neither push nor WSP adapter may call it to synthesize member receipt. |
| `public.open_notification_whatsapp(p_notification_id uuid) returns jsonb` | Preserve manual `{notification,url}` command and deterministic whatsapp:<source id> child; opening means neither paid send nor delivery. |
| `app.accept_paid_notification(uuid,text,bigint,uuid) returns jsonb` | Keep denied GL069 compatibility stub. Never activate acceptance-priced credit argument. WSP has separate acceptance and verified billable-delivery commands. |

Push children of an existing in_app event use `push:<source_notification_id>`;
existing renewal/CLS keys remain unchanged, ANC uses its exact versioned key.
WSP fallback is a distinct in_app source/causal key, never channel mutation;
optional push fallback is another push child. The root must freeze the exact
WSP paid-child/fallback key grammar with its source inventory before authors
start; this draft does not invent receipt events or historical backfill.

NTF accepted/received/opened, WSP accepted/delivered/provider-read and ANC card
read remain separate facts. Push opens require authenticated device evidence;
WSP provider_read_at never writes clicked_at; ANC receipt requires opening the
actual current card through ANC's command. WSP authenticated click/conversion
is not introduced by this draft. Notifications retain their source truth when
any external channel fails or is unconfigured.

## Reachable transport declarations

`app` stays outside PostgREST. Both adapters call only the following `public`
facades, never REST RPCs in `app`. Candidate arrangement: facades are VOLATILE
INVOKER, EXECUTE only service_role, with service-only EXECUTE on the named
private helpers. Helpers are narrowly justified DEFINER, postgres-owned,
search_path='', no PUBLIC/anon/authenticated EXECUTE. They alone perform guarded
writes; remove direct service_role DML on the new transport tables. Ordinary
sessions cannot use SET ROLE to postgres. Definer ownership is not an evidence
predicate: helpers validate durable causal rows before every mutation.

SQL signatures below all return jsonb. A public facade delegates to its same-
named app helper with identical arguments/return contract (no extra caller-
controlled tenant, member, price or payload). These private helper signatures
are therefore exact declarations as well. Existing `app.run_push_events
(p_tenant_id uuid) returns jsonb` remains trusted SQL scheduling only; revoke
ordinary EXECUTE. No public tenant-selection/event-runner facade is added.

| Service facade (and identical private app helper) | Exact successful result |
|---|---|
| `public.reserve_push_attempts(p_limit integer)` | `{attempts:[{attemptId,reservationId,expiresAt}],configuration:"ready"}`; identifiers only, no tokens. |
| `public.authorize_push_attempt(p_attempt_id uuid,p_reservation_id uuid)` | `{authorized:true,attemptId,reservationId,expiresAt,token,tokenRevision,message:{title,body,data:{notificationId,sourceNotificationId,relatedType,relatedId},ttlSeconds}}` or `{authorized:false,attemptId,reservationId,reason,deferredUntil}`. Explicit nulls for absent data/source/defer fields. Fixed generic lock-screen copy from NTF-013; closed source identifiers, no arbitrary URL. |
| `public.finish_push_attempt(p_attempt_id uuid,p_reservation_id uuid,p_provider_message_id text,p_failure_code text,p_uncertain boolean)` | `{attemptId,replayed,notification:NotificationResult}`. Exactly one result class: nonblank accepted id with null failure and false uncertainty; null id with allowlisted failure and false uncertainty; or null id/null failure/true uncertainty. |
| `public.claim_whatsapp_dispatch(p_batch_size integer)` | `{attempts:[{attemptId,ticket,expiresAt}],configuration:"ready"}`; no recipient, cost or rendered payload at claim. |
| `public.authorize_whatsapp_dispatch(p_attempt_id uuid,p_ticket uuid)` | `{authorized:true,attemptId,ticket,expiresAt,senderAccountId,templateRevisionId,rateVersionId,recipient,template:{name,locale,parameters}}` or `{authorized:false,attemptId,ticket,reason,deferredUntil}`. Recipient is ephemeral credential-service-only data; hold/currency/rate are validated SQL facts, not request prices. |
| `public.record_whatsapp_acceptance(p_attempt_id uuid,p_ticket uuid,p_provider_message_id text,p_evidence_digest text)` | `{attemptId,replayed,notification:NotificationResult}`; stores acceptance and preserves hold, zero ledger movement. |
| `public.finish_whatsapp_rejection(p_attempt_id uuid,p_ticket uuid,p_failure_code text,p_outcome_known boolean)` | `{attemptId,replayed,notification:NotificationResult}`. Known=false requires null failure_code and retains unresolved hold; known=true requires allowlisted proof-of-rejection failure code. |
| `public.record_whatsapp_receipt(p_sender_account_id uuid,p_provider_message_id text,p_receipt_fingerprint text,p_event_kind text,p_provider_at timestamptz,p_verified_evidence_digest text)` | `{attemptId,replayed,applied,notification:NotificationResult,ledgerId,debitedPaise,currency}`; ledgerId nullable, debitedPaise canonical string, currency INR. Allowed normalized kinds delivered/read/failed only. SQL derives sender→tenant→attempt; adapter signature verification precedes this call. No callback-supplied price. |

Successful empty claims are bounded `{attempts:[],configuration:"ready"}`.
Missing provider configuration returns `{attempts:[],configuration:
"provider_unconfigured"}` and creates no attempt/hold. Invalid provider
credentials stop the invocation before later claims/authorization; adapter
reports a count-only configuration failure and does not invalidate tokens.
Claims cannot pretend to detect credentials they do not possess: adapter
configuration validation precedes claim; SQL separately checks activated
configuration revisions. Existing unconfigured-push notification failure
remains terminal, never revived when configuration arrives.

NTF limit is 1–100, reservation 90 seconds, tenant request budget 100/minute.
WSP batch is 1–50, ticket 120 seconds, tenant request budget 30/minute.
Use proposal defaults as named registered constants at freeze. Claims select
tenants themselves, order tenant id then due scheduled_for then notification
id then device id, serialize tenant budget and skip locked work. Caps count
authorized device/provider requests, including uncertain started requests;
claims reserve budget atomically so overlapping workers cannot overspend.
One invocation processes at most its claimed bounded batch and never loops to
drain the queue or self-schedules. Promotions defer to next IST 08:00 during
[21:00,08:00), without changing scheduled_for; transactional exemptions remain.

Authorization locks/rechecks organization, complete member/current user and
guardian binding, consent, source validity and channel-specific revisions.
WSP also rechecks sender, template, recipient/contact consent revision and
effective approved INR rate/hold. Refusal cannot return a token/recipient.
Authorization marks io_started_at once, immediately before the one external
request; expired tickets cannot authorize I/O. Lost authorization response is
conservatively uncertain and must not prompt another send. A caller cannot
replay authorization to receive a second permission to send.

## Native/member declarations and denial

All member commands below are postgres-owned DEFINER, search_path='',
authenticated EXECUTE only, complete member+tenant+auth.uid() binding first,
no staff/platform/impersonation identity. Check current active eligible member,
GRD guardian completeness/current linked user for minors; no phone matching.

| Declaration, all returns jsonb | Exact safe result |
|---|---|
| `public.register_member_push_device(p_installation_id uuid,p_push_token text,p_platform text)` VOLATILE | `{deviceId,tokenRevision,active:true}`; Android native FCM only. |
| `public.unregister_member_push_device(p_installation_id uuid)` VOLATILE | `{disabled:true}`; absent own installation is inert. |
| `public.read_member_push_settings()` STABLE | `{preferences:[{category,enabled}],devices:[{id,lastSeenAt,active}]}`; sorted category/id, no token or provenance/contact. Missing preference means enabled subject to consent/OS permission. |
| `public.set_member_push_preference(p_category public.message_category,p_enabled boolean)` VOLATILE | `{category,enabled}`; identical value inert; never changes purpose consent. |
| `public.acknowledge_member_push(p_notification_id uuid,p_device_id uuid,p_token_revision bigint,p_event text)` VOLATILE | NotificationResult; received/opened only, accepted matching attempt and current same-user device/revision required. Open may legally apply sent→delivered→clicked, audit both edges; no converted_at. |
| `public.read_member_whatsapp_settings()` STABLE | `{service,marketing,recipientKind,maskedPhone,noticeVersion,available}`; booleans service/marketing express channel permission, not generic consent. |
| `public.set_member_whatsapp_consent(p_purpose public.consent_purpose,p_granted boolean,p_notice_version text)` VOLATILE | `{consentId,purpose,granted,noticeVersion,recordedAt}`; actual current adult/linked guardian recipient, exact unchanged current declaration inert. No generic-purpose consent mutation. |

Front-office WSP `public.request_whatsapp_dispatch(p_notification_id uuid,
p_request_key uuid) returns jsonb` is VOLATILE INVOKER, authenticated only,
existing real front-office authority; returns `{notificationId,queued,reason}`
with explicit nullable reason. It only queues admitted work; known refusal is
queued=false and an allowlisted safe reason. No provider/amount input.
`public.record_whatsapp_consent(p_member_id uuid,p_purpose public.consent_purpose,
p_granted boolean,p_notice_version text,p_source text,p_request_key uuid)
returns jsonb` is VOLATILE DEFINER, real front office, returning the same
consent projection; current approved GRD evidence boundary applies to guardians.
No default-on consent, bulk consent, new identity binding or sibling disclosure.

Device row uniqueness remains tenant/token plus tenant/member/installation.
Add registered_user_id, installation_id, token_revision, invalidated_at/reason
with composite tenant/member FK and tenant-leading policy/dispatch indexes.
Legacy provenance-null rows are inactive until self-registration. Same active
installation/user/token is inert (no revision/audit bump); authenticated
activity may refresh last_seen_at separately. New/changed/re-enabled binding
increments revision under lock and clears only its own invalidation. Token
collision with another member is a generic conflict, never a transfer or
identity disclosure. Logout unregister is best effort; final authorization
remains the security boundary. Old-revision provider errors never invalidate
a replacement. Generic INVALID_ARGUMENT/auth/quota/outage is not token proof.

Revoke ordinary member_devices table DML and token SELECT, including current
staff/platform paths; replace legitimate metadata access with safe RPCs, not
column-star reads. Preferences: own-member safe SELECT only; commands own
writes. Attempts/receipts/holds: no anon/PUBLIC/authenticated SELECT or DML.
Safe operational readers retain existing front-office authorization, omit
token/provider/ticket/recipient details; trainers get no communications access.
Front desk gets readiness/refusal, never wallet/ledger amounts. Owner/manager
may see INR wallet/charged aggregates. Platform preview remains read-only;
transport EXECUTE is denied even for super-admin/support/impersonation JWTs.
All new tables have RLS, indexed tenant claim predicates and composite tenant
FKs; none relies on service-key bypass as its product authorization rule.

## Revision, replay and uncertainty candidate

Resolve NTF-007's revision ambiguity conservatively: one durable attempt per
`(tenant_id,notification_id,device_id)`, with frozen authorized revision.
Rotation never grants a second request for that event after io_started_at.
Before start, an expired/refused reservation may be replaced under the same
attempt only after fresh revision/eligibility checks; its old reservation is
invalid. Other registered devices remain independently eligible. This is a
serial-freeze candidate, not an assertion that contradictory drafts agree.

Expired never-started reservations may release; expired started reservations
record uncertainty and never automatically resend. Finish records exact
result replay (inert/no audit); another result for the same attempt/ticket is
GL068. A stale ticket never mutates a replacement reservation. Late causal
acceptance/receipt after uncertainty is retained for reconciliation; it cannot
revive a notification already failed. Push notification becomes sent on any
known acceptance; when all attempts terminal with none accepted it becomes
failed, with uncertainty reason when applicable. Failure on another device
never regresses delivered/clicked history.

WSP retains one live attempt per notification plus tenant/request-key and
sender/provider-id uniqueness. Request-key mismatch refuses instead of
overwriting. Unknown started attempt/hold survives timer expiry; no debit,
automatic release, duplicate paid send or inference of rejection. Known
rejection releases hold without charge. Verified billable delivery debits
exactly once through existing locked wallet movement path, server tariff only;
zero-cost evidence creates no ledger row. Receipt replay is sender/fingerprint
idempotent; changed evidence conflicts. Out-of-order facts never regress state
or charge twice. Terminal failure retains late evidence for reconciliation.

WSP unit transition remains guarded: transaction locks and inventories both
wallet tables; only all-zero balances AND no ledger movements permit conversion
to integer paise/INR. Any history/nonzero value refuses pending an exact separately
approved history-preserving schedule. No runtime tax/FX, guessed exchange rate,
acceptance charge, wallet duplication or arbitrary backfill.

## Error precedence and freeze gaps

Candidate shared precedence: (1) effective EXECUTE/context/complete actor or
impersonation denial 42501; (2) argument shape/range 22023; (3) target visibility,
foreign/absent id indistinguishable P0002; (4) exact keyed replay/conflict GL068;
(5) current causal revision/lease/state validity; (6) eligibility/consent/source;
(7) provider/template/rate configuration; (8) quiet time/budget; (9) wallet funds;
(10) actual evidence/graph writes. Member unregister absent-own replay is the
documented exception to target-not-found. Existing commands preserve frozen
GL066 invalid-state, GL067 wallet and GL069 disabled-paid semantics. Do not
reuse these for new concepts. New refusal/lease/configuration SQLSTATE
allocations, failure-code allowlists, digest/token/string/request byte bounds,
timestamp sanity and callback cardinality must be published serially before
independent authors; native/schema validation alone is insufficient.

True unresolved owner choices: approve NTF Edge/wakeup/infrastructure boundary
or name the alternative; supply exact approved Firebase/Android registration
and restricted credential custody. NTF service-consent and dispatch quiet-hour
rules are retained contract rules, not fresh approval gates. WSP Meta/INR/
delivery-charge/channel-consent choices are already approved; do not reopen.
Actual WABA/sender, templates/categories, approved final effective INR tariff,
protected credentials and F9 India compliance determination remain activation
prerequisites. A nonzero wallet/history or sub-paise tariff triggers the explicit
existing conversion/rounding decision, not an invented commercial policy.

Serial-owner mechanical freeze work: resolve exact paid child/fallback source
keys, source event enablement cutoff with no historical backfill, safe operational
reader pagination/envelopes, actor/grant metadata, all bounded text/error constants,
cron credential/configuration observability and underlying grants. The proposed
private helper arrangement and conservative NTF revision rule require one serial
decision. No arbitrary new approval flow is added. CI alone applies migrations,
generates Database declarations via CLI and provisions approved provider setup.
No delivery/live win is claimed from drafts, fixtures, queue admission or wakeups.
