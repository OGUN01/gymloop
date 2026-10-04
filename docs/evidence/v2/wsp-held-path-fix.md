# WSP held-test path fix — route normalization follow-through

The CI `test:scripts` gate failed on `supabase/tests-holdout/wsp-app-held.test.ts`
because commit `4c8c9cae` (notification route normalization
`[notificationId]` → `[id]`) moved the dispatch route the held test imports.

## Paths verified and state

| Target | Path | State |
|---|---|---|
| lib | `apps/web/lib/whatsapp` | exists, unchanged |
| operations | `apps/web/lib/whatsapp-operations` | exists, unchanged |
| memberSettingsPage | `apps/web/app/member/whatsapp-consent/page` | exists, unchanged |
| memberConsent | `apps/web/app/api/member/whatsapp-consent/route` | exists, unchanged |
| staffConsent | `apps/web/app/api/members/[memberId]/whatsapp-consent/route` | exists, unchanged |
| dispatch | `apps/web/app/api/notifications/[notificationId]/whatsapp-dispatch/route` | **MOVED** → `[id]/whatsapp-dispatch/route` |

## Edits (mechanical, mirroring 4c8c9cae's own params-key adaptation)

1. `targets.dispatch`: `[notificationId]` → `[id]` (the only moved path).
2. `DispatchRoute` type: `params: Promise<{ notificationId: string }>` → `{ id: string }` (the moved route reads `context.params.id`).
3. Nine `route.POST(...)` call sites: `params: Promise.resolve({ notificationId: ids.notification })` → `{ id: ids.notification }`.

No assertions, expectations, or mocks touched.

## Result

`pnpm exec vitest run supabase/tests-holdout/wsp-app-held.test.ts --maxWorkers=2`
→ **101 passed (101)**, file green.

File sha256 (post-fix): `e42b7e3a63c5d11ab68c62837227bbf7`
