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

Pending duplicate invocations cannot replace or clear the active original
command. If refreshed offer props change its price or currency, reconciliation
still reviews, validates and retries the retained command's original context;
a newly zero-priced offer cannot require a reason on an earlier paid command.

## Existing product display interface

`apps/web/app/(console)/shop/product-display-panel.tsx` exports
`ProductDisplayPanel({ product, categories })`. Public structural types from
`apps/web/lib/shop-console.ts` are:

- `ShopCategory = Pick<Database['public']['Tables']['shop_categories']['Row'],
  'id' | 'name' | 'sort_order' | 'is_active'>`.
- `ShopProduct = Omit<Database['public']['Tables']['addon_products']['Row'],
  'price_paise'> & { price_paise: string; heldQuantity: number | null;
  imageUrl: string | null; imageAssetId: string | null }`.

The existing public file delegate is `uploadProductImage(file, onStage?)`;
the asset result and stages are fixed in upload-stage-interface-clarification.
The form uses the existing same-origin PATCH `/api/shop/products/{id}` and
strict shared product-display request schema. Source-blind tests may double the
delegate to control verification timing and ordinary fetch for the display save.
Same-render repeated activation cannot create concurrent upload/save sequences.
Invalid display fields cannot report Saving when no display mutation occurs;
errors and retries must preserve truthful stages and confirmed-asset reuse.

## Existing route loading fallbacks

The member `app/member/shop/loading.tsx` and console
`app/(console)/shop/loading.tsx` each export the ordinary no-props Next loading
component as default. The frozen States table requires shaped skeleton tiles
for the member and skeleton rows for the console; a loading sentence alone
does not satisfy it. Placeholders are decorative, contain no fabricated money,
counts, names or images, and are excluded from the accessibility tree. The
ongoing loading state is announced separately. Reuse existing theme/spacing
tokens and honour enlarged text/reduced motion; no exact placeholder count is
invented. Independent structural tests precede the fallback correction, with
actual rendering/accessibility evidence still required for full acceptance.
