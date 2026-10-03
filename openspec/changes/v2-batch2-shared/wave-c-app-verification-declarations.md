# Wave C application verification declarations — 2026-10-03

This serial packet makes the selected application interfaces explicit for
independent fixture authors. It supplements the frozen PAY/WSP proposals and
`wave-c-serial-freeze-declarations.md`; it changes no money, consent, identity,
audience, error-precedence or evidence rule. Fixture changes must preserve all
positive and negative behavioral assertions. A failure of an approved rule
remains RED even when the current application accepts it.

## PAY request and copy interfaces

The registered shared create schema is `purchaseCreateRequestSchema`. Its
strict HTTP body is `{requestKey, kind, targetId, quantity, expectedRevision}`;
ids are UUIDs, kind is shop/PT/renewal, quantity is an integer from 1 to 10,
and non-shop requests have quantity 1. The verifier recorder's existing
strict HTTP fields are `{expectedRevision, commandKey, actualAmount, currency,
method}`, with optional `requestId`. `actualAmount` is a positive canonical
base-10 integer-paise **string**, currency is INR, and method is drawn from
the generated `payment_method` enum. SQL uses `p_actual_amount`,
`p_currency`, and `p_payment_method`. Omission of method is an invalid body,
not a valid-recording scenario. The approved PT initial-slot addition in the
PAY proposal remains required; this packet does not excuse an absent route
or schema integration of that addition.

Invalid JSON/body shape remains HTTP 400 `invalid_request`. The existing
23514 value constraint uses HTTP 422 `validation_refused`; its
`proof_media_refused` detail uses HTTP 422 `upload_rejected`. This preserves
the frozen distinction between invalid shape, value constraints, and refused
media; actor/target/state/rate refusals retain their frozen precedence.

The proof-URL endpoint is `/api/purchase-requests/[id]/proof-url` for both
the owner-member and the real same-tenant verifier. Member-specific upload
registration and confirmation retain their frozen member routes. Every URL
request is independently authorized; nothing in this packet permits a fake
successful upload or general MEDIA exposure of proof.

`purchaseRequestCopy` is a semantic copy object, not an enum-indexed map.
Its truth-bearing keys include `pendingVerification`, `recorded`, `requested`,
`accepted`, `mismatchTitle`, `mismatchNote`, `rejectedTitle`, `expiredTitle`,
`expiredNote`, and `cancelledTitle`. The registered shared function
`purchaseRequestStatusWord(status: string): string` returns Requested,
Accepted, Pending verification, Payment recorded, Money recorded, Declined,
Cancelled and Expired for the corresponding frozen statuses; unknown status
returns Update pending. Labels never infer verified funds from an upload.
The web presentation exports `purchaseStatusLabel` and
`purchaseStatusSequence` are located in
`apps/web/app/member/buy/purchase-wording.ts`; the registry's combined shared
location for these two presentation exports needs correction. This is a
location declaration, not a new shared API or a relaxation of BUY-022.
`purchaseStatusLabel` aliases the shared status-word function;
`purchaseStatusSequence` is a readonly presentation array of `{status, word}`
for requested/Requested, owner_accepted/Accepted,
payment_proof_uploaded/Pending verification and recorded/Payment recorded.

`BUY_LIMITS` uses these selected property names and frozen values:

| Property | Value |
|---|---:|
| requestTtlSecondsAfterAcceptance | 86400 |
| requestTtlSecondsUnaccepted | 86400 |
| openRequestsPerMember | 5 |
| creationsPerMemberPerDay | 10 |
| proofRegistrationsPerMemberPerHour | 10 |
| maxQuantity | 10 |
| reasonMinLength | 3 |
| reasonMaxLength | 200 |
| proofMaxBytes | 2097152 |
| privateProofGetTtlSeconds | 60 |

## WSP operations interfaces

The registered loader lives in `apps/web/lib/whatsapp-operations.ts`.
`loadWhatsappOperations(params: {cursor?: string})` returns a promise of
`{view: WhatsappOperationsPage|null, errorMessage: string|null,
isPreview: boolean}`. It obtains the verified console identity through
`requireAudience('console')` and calls the frozen read RPC with paired
`p_after_created_at`, `p_after_id` and bounded `p_limit`. The selected page
size is 100, within the frozen maximum. A loader cursor carries both returned
halves as `createdAt|id`; the initial page sends both null. The public
`whatsappOperationsCursor(page)` returns that paired string or null when
either half is null. These mechanical names do not alter paging order.

The frozen seven-key page is
`{operations, nextAfter, nextAfterId, statusCounts, templateBlockers,
wallet, chargedTotals}`. `nextAfter` and `nextAfterId` are nullable strings.
`statusCounts` is `{accepted, delivered, read, unknown}`, each a nonnegative
canonical base-10 decimal string. A template blocker is
`{templateId, name, reason}`, each a string. Wallet is
`{balancePaise: string, currency: 'INR'}|null`; charged totals is
`{chargedPaise: string}|null`. Desk gets null for both money fields;
owner/manager and their authorized read-only preview get the safe projection.
Trainers/members remain denied. No provider id, token, raw phone, ticket or
receipt payload is a permissible field.

An operations row has exactly these safe keys:
`notificationId`, `memberId`, `memberName`, `status`, `maskedPhone`,
`recipientKind`, `templateName`, `refusal`, `scheduledFor`, `sentAt`,
`deliveredAt`, `providerReadAt`, `failedAt`, `failedReason`, `optedOutAt`,
`optedOutReason`, `outcomeUnknown`.
The recipient kind is self or guardian, outcomeUnknown is boolean, and
refusal/failedReason/optedOutReason and the five optional evidence timestamps
are nullable strings. Other fields are strings. `scheduledFor` is a string.
The mask must conceal the phone; this declaration never permits raw digits
under a different property name.

## WSP consent and staff recorder interfaces

The registered settings validator is
`memberWhatsappSettings(data: unknown): MemberWhatsappSettings|null` in
`apps/web/lib/whatsapp.ts`; the consent-result validator is
`whatsappConsentWriteResult(data: unknown): WhatsappConsentWriteResult|null`.
The member web settings loader is the default async page export in
`apps/web/app/member/whatsapp-consent/page.tsx`. It verifies
`requireAudience('member')`, requests `read_member_whatsapp_settings` with an
empty argument object, and renders validated settings into the registered
consent controls or an honest unavailable/error state. The frozen contract
does not require an invented `loadMemberWhatsappSettings` export in the
validator module. Tests may observe this page/controls boundary to verify the
same read, role, error and availability rules. No new production export is
necessary merely to match a fixture's invented helper name.

The member command body is `{purpose, granted, noticeVersion}`. The staff
recorder body is `{memberId, purpose, granted, noticeVersion, source,
requestKey}`. Both are strict objects: purpose is a valid generated
`consent_purpose`, granted is boolean, noticeVersion and source are nonblank,
and member/request ids are UUIDs. Frozen SQL argument names are unchanged.
The safe consent result is exactly
`{consentId, purpose, granted, noticeVersion, recordedAt}`.

The successful result must correspond to the submitted purpose and granted
value; an unknown or mismatched result cannot truthfully confirm the command.
This is the existing consent truth boundary. Independent tests of that
correlation remain required and any present violation stays RED. Public
mechanical declarations do not authorize accepting another purpose, weakening
staff authority, revealing upstream errors, or treating missing consent as
opt-in.

The shared staff guard receives front-office roles and
`{completeWrongAudience: 'forbidden'}` before parsing, independent of the
recorder's successful RPC result. Authority-call observation fixtures still
need an honest asynchronous RPC envelope if they continue through a valid
command body; an undefined mock reply is not a production RPC response.

## Identity fixture contract

The registered `readRequestIdentity` returns null for an absent, invalid or
unclassified session. Fixtures for an unauthenticated caller must return null
rather than an invented unlinked identity object. Verified identities keep
the existing registered wrappers and audience predicates. No route may
derive authority from the existence of a mocked target or from body fields.

## Explicit remaining build defects

These declarations are not acceptance. MEDIA payment-proof upload completion,
the approved PT initial-slot HTTP integration, canonical generated enum use,
consent-result correlation, live provider setup, final browser/device evidence
and all publication gates remain required. Independent authors must report
genuine failures separately from mechanical fixture mistakes.
