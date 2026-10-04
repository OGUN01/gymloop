# Route conflict fix — notifications dynamic segments — 2026-10-04

## Conflict found

Two sibling dynamic segment pairs at the same level (Next.js refuses
"different slug names for the same dynamic path" — killed `next dev` boot and,
after regeneration, web `tsc` via `.next/types/validator.ts`):

1. `apps/web/app/api/member/notifications/`: `[id]/delivered/route.ts` vs
   `[notificationId]/push-event/route.ts`
2. `apps/web/app/api/notifications/` (same defect class, also blocks boot):
   `[id]/whatsapp/route.ts` vs `[notificationId]/whatsapp-dispatch/route.ts`

## Canonical choice: `[id]`

The two committed comms routes read `context.params.id` and their pinned test
table (`comms-routes.test.ts:17-18`) maps them as `[id]`; the
`[notificationId]` dirs were the newer additions. Runtime fetch URLs are
segment-name-independent (params key is the only coupling).

## Changes (moves byte-for-byte via `mv`; no behavior change)

- MOVED `apps/web/app/api/member/notifications/[notificationId]/push-event/route.ts`
  → `[id]/push-event/route.ts` (the other agent's uncommitted modification
  travels with the file; old path now deleted in git terms, content intact).
  2-line params adaptation: `Promise<{ notificationId: string }>` →
  `Promise<{ id: string }>` and `const { notificationId }` → 
  `const { id: notificationId }` — same value, same behavior.
  Doc header already said `[id]`. sha256 `c39578d08a9c1f02`.
- MOVED `apps/web/app/api/notifications/[notificationId]/whatsapp-dispatch/route.ts`
  → `[id]/whatsapp-dispatch/route.ts`. Same 2-line params adaptation; doc
  header path updated `[notificationId]` → `[id]` (comment only).
  sha256 `98fc179e85325f7e`.
- EDITED (forced by rename) `apps/web/app/__tests__/ntf-push-routes.test.ts`:
  import path `[notificationId]/push-event` → `[id]/push-event`; context
  params object now `{ id, notificationId: id, announcementId: id, campaignId: id }`
  (kept the old key — harmless — added the new one). sha256 `0ab258302c6f5ca1`.
- DELETED generated `apps/web/.next/types/` (stale validator pinned the old
  segment names). Nothing under `.next` is source.
- Untouched: `comms-routes.test.ts` (already keys `{ id }`), both `[id]` routes,
  `member-message-actions.tsx` and `use-push-response.ts` (runtime URLs),
  all other agents' files.

## Verification (verbatim)

- Scoped vitest: `pnpm vitest run apps/web/app/__tests__/comms-routes.test.ts
  apps/web/app/__tests__/ntf-push-routes.test.ts
  apps/web/app/__tests__/messages-pages.test.tsx`
  → `Test Files 3 passed (3)` / `Tests 140 passed (140)`.
- Web typecheck `pnpm --filter web exec tsc --noEmit` → exit **0** (was exit 1
  on generated validator artifacts).
- Dev boot: `npx next dev -p 3199` from `apps/web` → `✓ Ready in 4.1s`, no
  route error in log; process killed after check.

## Not covered

`next build`, production env checks, and any e2e run remain the primary's.
No commits made.
