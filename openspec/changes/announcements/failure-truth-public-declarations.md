# Approved announcement failure truth — public seams

Frozen engineering declarations, 2026-10-03, after explicit owner approval
of failure-truth-amendment.md. Original audience/version/receipt and actor
requirements remain unchanged. Independent authors precede the source builder.

The existing useAnnouncements seven-field interface, useAnnouncementCommand
interface and announcementCommand(request, command, context?) remain as declared
in application-interface-clarification.md. That file's older owner-pending
sentence is superseded by the approved amendment; it cannot block this repair.

```ts
// apps/mobile/lib/announcements.ts — alongside existing exact-scope cache actions
declare function discardAnnouncementCache(
  scope: AnnouncementScope, isCurrent: () => boolean
): Promise<void>;
```

This narrow scoped deletion removes refused cards and pending reads only if
the persisted complete tenant/user/member scope matches and the permanent
caller/request lifetime is still current. Recheck after awaited storage work
and within the existing serialized write/delete order. A late refusal must
neither delete nor revoke a newer caller's cache. The existing no-argument
clearAnnouncementCache identity cleanup keeps its global revocation behavior.
Do not change resolveAnnouncementFeed's interface or add another persistence
key, provider, tenant selector or storage dependency.

The registered API failure envelopes use not_signed_in (401) and not_permitted
(403). Existing definitive unauthorized/forbidden equivalents remain failures
if received from the actual transport. A definitive refused current feed shows
sanitized sign-in/permission feedback, no cached cards, and no acknowledgement
through retained callbacks. Non-permission read failures retain only same-scope
saved cards/time and provide refresh feedback; offline wording requires actual
disconnected/unreachable evidence. The already installed Expo Network
getNetworkStateAsync is the allowed native connectivity evidence seam. Unknown
network state or server/malformed results are refresh failures, not proof of
offline. No raw server error or body is rendered.

The shared ANNOUNCEMENT_REFUSAL_COPY gains only the owner-approved
unknown_outcome sentence, and announcement_outcome_unknown maps to that key.
Unexpected post-submission transport/server exceptions and malformed required
command results cannot claim Nothing was changed or trigger automatic replay.
Existing specific definitive refusals and pre-command request/auth/permission
failures keep their codes. RPCs returning void retain their ordinary successful
null result; absence of a required scalar/row differs from a legitimate void
response. Browser command hooks apply the same unknown-outcome truth to a lost
or malformed response and retain their unmount/preview/offline safeguards.

No SQL migration, audience/RLS change or generated type edit is authorized.
Tests exercise actual helpers/hooks/routes/cache and existing caller lifetimes,
mocking only declared API/caller/network/storage/rendering boundaries.

## Reachable saved-copy feedback

The existing registered native `AnnouncementsSection` in
`apps/mobile/components/announcements.tsx` accepts
`{feed: ReturnType<typeof useAnnouncements>; timezone: string}`. Its existing
seven-field feed includes cards, loading, error, stale, fetchedAt, reload and
markRead. A non-permission refresh error must coexist with retained same-scope
cards and their Saved copy timestamp; the actual rendered component must not
return before showing those cards. Show sanitized refresh feedback and an
explicit Try again action alongside the saved cards. They remain expandable
and their existing scoped offline read queue remains available. A definitive
permission refusal leaves no cached cards or acknowledgement capability and
renders only its sanitized refusal/retry state. Loading/empty/healthy feed
behavior remains unchanged. No new feed interface or persistence key is added.
Independent visible and held rendered regressions precede the component fix.
