# NTF held test path fix (route normalization follow-up)

The route normalization commit `4c8c9cae spec:` moved the notification
dynamic route segments from `[notificationId]` to `[id]`; the held test
file's `targets` table kept the old path, so `import()` failed and the
"member push-event evidence exports POST only and exists at the pinned
path" assertion failed at CI's `test:scripts` gate.

## Path fixed (one occurrence)

- `supabase/tests-holdout/ntf-app-held.test.ts:97`
  `../../apps/web/app/api/member/notifications/[notificationId]/push-event/route`
  → `../../apps/web/app/api/member/notifications/[id]/push-event/route`
  (target verified on disk: `apps/web/app/api/member/notifications/[id]/push-event/route.ts`).

The other dynamic routes in the same ROUTES table (`[announcementId]`
push-review, `[campaignId]` cancel) were already correct on disk. The
fail-closed tests pass unchanged: each route authenticates before reading
`context.params`, so an unauthenticated malformed POST returns its 401/403
before the params read (which is why the missing second argument does not
throw in those tests).

Siblings checked: `ntf-native-held.test.tsx` (imports a mobile app path,
no notificationId refs), `push-dispatch-handler-held.test.ts` (no path
imports) — clean.

## Runtime

`pnpm exec vitest run supabase/tests-holdout/ntf-app-held.test.ts --maxWorkers=2`
→ **17 passed (17)**, file green.

## sha256

- `supabase/tests-holdout/ntf-app-held.test.ts`: `23cec5ba3f084e07dfb4ec4a88bb2c0896f9a648e4badcaba2eae8d806287084`
