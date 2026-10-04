# NTF provider-result validation — FROZEN

2026-10-04. Serial mechanical completion before the adapter builder starts.
No audience, money, consent, scheduling or notification transition changes.

The exact SQL projections remain those in the shared Wave C delivery and
serial declarations. Reject malformed, extra-field, mismatched-id or expired
claim/authorization/finish projections with HTTP502 `upstream_failed`, keeping
only the bounded facts already established. Never infer authorization, send
after a failed projection, or count a finish that was not validated. UUIDs use
Postgres canonical grouping without an RFC version restriction. The SQL bigint
`tokenRevision` projection is canonical positive decimal text bounded by signed
bigint. A claim must not repeat an attempt or reservation, exceed 100 entries,
or return work under `provider_unconfigured`.

An OAuth success is usable only with a nonblank string `access_token`, exact
`token_type: "Bearer"` and integer `expires_in` in 1–3600 seconds. Its lifetime
starts at the request start according to the injected clock. Never send with
an expired OAuth token or authorization lease; no refresh/retry is introduced
within an invocation. Malformed or unusable success returns the previously
frozen HTTP502 before claim. The RS256 assertion lasts at most 3600 seconds.

A successful FCM response counts as acceptance only if `name` is a nonblank
string of at most the frozen 256 characters, of the form
`projects/samuraiapi-51996/messages/<opaque-message-id>` with one nonempty
final path segment and no whitespace/control characters. Ignore extra response
metadata; never expose it. A malformed/mismatched success has unknown outcome:
finish uncertainty once, do not invent acceptance or resend. Validated exact
finish replay counts the same factual result once within this invocation.

For a rejected FCM response, extract only the documented FCM `errorCode` from
typed `google.firebase.fcm.v1.FcmError` details, falling back to the documented
`error.status`. Never use message/debug text as a code. Retain the existing
serial failure-code bound and invalidation classification. If no bounded
nonblank code can be established, finish uncertainty. Provider HTTP401/403
stops the invocation after its one factual finish, before later authorization;
return HTTP503 `configuration_invalid` with established counts. A transport
exception or lost/malformed success never proves rejection.

These are application validation choices based on the approved confinement
boundary and the official [FCM HTTP v1 response](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
and [FCM error structures](https://firebase.google.com/docs/cloud-messaging/error-codes).
Independent authors supplement their own suites before implementation.
