# ANC presentation and lifetime interfaces

Status: delegated public interface clarification, 2026-10-03. No audience,
consent, version, receipt, storage privilege or business rule changes.

The commissioned Q3/Q10 stability bar governs the Home insertion point. The
section follows the existing week figure and scan action in document order;
it still appears after the greeting as ANC-020 states. The proposal's earlier
exact-match insertion immediately after `member-hero` conflicts with that bar
and is superseded by this anchor. Announcement reads still start independently,
and streaming failure or arrival must not move those existing elements.

Native `AnnouncementsSection({ feed, timezone })` takes the public
`useAnnouncements()` result (`cards`, `stale`, `fetchedAt`, `loading`, `error`,
`reload`, `markRead`) and a timezone string. The collapsed card exposes a
separate two-line body preview; metadata is not a substitute for that preview.
Title remains the button's accessible name, with the expanded state and exact
version acknowledgement unchanged.

Scope means the complete existing tenant/user/member tuple. Reload preparation
and every render must exclude another scope's cards and read state, including
the interval before a new fetch settles. Pending cache receipts remain exact
version pairs. Delivery is idempotent and never double-counted; ANC-021 does not
promise exactly one HTTP request across concurrent delivery or retries.

Unmounted web command/form work cannot refresh, navigate or apply a completed
upload to a replacement form. Existing caller validation remains authoritative;
no browser-supplied identity is introduced. The separate failure-truth amendment
was explicitly owner-approved on 2026-10-03; its exact failure boundaries and
failure-truth-public-declarations.md supersede the older blanket fallback.

## Existing callable surfaces

- `AnnouncementComposer({ nouns, timezone, canPublish, detail })` is a named
  export from the console `announcement-composer.tsx`; `nouns: BusinessNouns`,
  `timezone: string`, `canPublish: boolean`, `detail?: AnnouncementDetail`.
- `AnnouncementActions({ detail, nouns, timezone, canPublish, review })` is a
  named export from `announcement-actions.tsx`; the same types apply, with
  required `detail` and optional boolean `review` (default false).
- Named `useAnnouncements()` consumes only `identity: GymloopIdentity` and
  `api: ApiClient` from the existing named `useMobile()` provider, plus the
  registered exact-scope cache interfaces. `markRead(announcementId: string,
  versionNo: number)` and `reload()` are asynchronous actions.
- Named `useAnnouncementCommand()` is a no-props console hook using the
  existing preview-read-only boolean, browser connectivity/fetch and Next
  router. `send(path: string, body: unknown)` returns a command data object
  or null. Existing outcome fields are `online`, `busy`, `error`, `conflict`,
  `setError`, `preview`, `disabled`. These are presentation interfaces, not a
  second source of caller authorization.

Blind authors may mock these public dependencies and import existing kit
components as black boxes, without reading feature implementation bodies.

Exact existing cache actions: `loadAnnouncementCache(scope)` returns
`Promise<CachedFeed | null>`; `saveAnnouncementCache(cache, isCurrent?)`,
`queueRead(scope, announcementId: string, versionNo: number, isCurrent?)` and
`flushPendingReads(api: ApiClient, scope, isCurrent?)` return `Promise<void>`.
`scope: AnnouncementScope` contains `tenantId`, `userId`, `memberId` strings;
optional `isCurrent(): boolean` defaults true. `CachedFeed` is the frozen
scope/fetchedAt/announcements/pendingReads value. These callbacks guard
lifetime, without introducing another identity or delivery-count promise.
