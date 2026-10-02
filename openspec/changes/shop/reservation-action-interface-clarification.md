# SHP desk reservation action interface

Status: delegated existing-interface clarification, 2026-10-03. No money,
authorization, request or retry requirement changes.

`apps/web/app/(console)/shop/reservation-actions.tsx` exports the client component
`ReservationActions` with these public props:

- `reservationId: string`, `quoteVersion: string`
- `currentPricePaise: string`, `currency: string`, `quantity: number`

It uses the existing shared fulfil request schema and ordinary same-origin
POST `/api/shop-reservations/{id}/fulfil`. The response uses the normal
`{ ok: true, data }` or `{ ok: false, error: { code, message } }` envelope.
Serialization/deadlock responses use the existing `retryable` refusal. Browser
tests may independently double fetch, router refresh and preview context. The
preview context's public hook is `usePreviewReadOnly(): boolean`; it does not
grant a write capability. Existing kit classes and native interfaces need no
change for this desk-only control.

SHP-019 continues to require one original command and idempotency key across
retries, including retryable failures and uncertain network outcomes. Such a
retry preserves its quote, payment method and reason. A deliberately revised
command after a definitive business/quote refusal is a new reviewed command;
success links to the actual order and receipt. Independent visible and held
authors retain separate harnesses and may not read the source or each other.
