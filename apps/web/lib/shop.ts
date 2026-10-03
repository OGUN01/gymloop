import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { SHOP_LIMITS, SHOP_REFUSAL_COPY, shopRefusalMessage, shopCatalogueResponseSchema, shopItemSchema, shopReservationSchema, type ShopCatalogueResponse } from '@gymloop/shared';
import { apiFail, noStore } from './api';

/** Only caller-scoped public RPCs cross the member projection boundary. */
export async function loadMemberShop(supabase: SupabaseClient<Database>, _tenantId: string): Promise<ShopCatalogueResponse> {
  void _tenantId; // RPC derives scope exclusively from the verified caller.
  const [catalogue, history] = await Promise.all([supabase.rpc('read_member_shop'), supabase.rpc('read_member_shop_reservations')]);
  if (catalogue.error || history.error) throw new Error('The shop could not be loaded.');
  const rows = catalogue.data ?? [];
  const { memberMediaUrl } = await import('./media');
  const images = new Map<string, Promise<string | null>>();
  const image = (assetId: string | null) => {
    if (!assetId) return Promise.resolve(null);
    if (!images.has(assetId)) images.set(assetId, memberMediaUrl(supabase, assetId).catch(() => null));
    return images.get(assetId)!;
  };
  const items = await Promise.all(rows.slice(0, SHOP_LIMITS.catalogueMax).map(async row => shopItemSchema.parse({ itemId: row.item_id, section: row.section, name: row.name, description: row.description, pricePaise: row.price_paise, currency: row.currency, gstRateBp: row.gst_rate_bp, validityDays: row.validity_days, cancellationTerms: row.cancellation_terms, quoteVersion: row.quote_version, categoryId: row.category_id, categoryName: row.category_name, imageUrl: await image(row.image_asset_id), availability: row.availability, availableQuantity: row.available_quantity })));
  const reservations = await Promise.all((history.data ?? []).map(async row => shopReservationSchema.parse({ reservationId: row.reservation_id, itemId: row.item_id, itemName: row.item_name, section: row.section, quantity: row.quantity, unitPricePaise: row.unit_price_paise, totalPaise: row.total_paise, currency: row.currency, state: row.state, createdAt: row.created_at, expiresAt: row.expires_at, cancelReason: row.cancel_reason, termsChanged: row.terms_changed, orderId: row.order_id, imageUrl: await image(row.image_asset_id) })));
  return shopCatalogueResponseSchema.parse({ items, reservations, truncated: rows.length > SHOP_LIMITS.catalogueMax, serverTime: new Date().toISOString() });
}
/** No untrusted SQL message or prototype key is reflected to a caller. */
export function shopFailure(code: string, detail: string | null, _message: string): Response {
  void _message; // Untrusted upstream text never crosses this boundary.
  if (code === '42501') return noStore(apiFail('forbidden', 'not_permitted', 'This account cannot perform this shop action.'));
  if (code === '22023') return noStore(apiFail('bad_request', 'invalid_request', 'Check the details and try again.'));
  if ((code === 'GL086' || code === 'GL087') && detail && Object.hasOwn(SHOP_REFUSAL_COPY, detail)) {
    const status = detail === 'invalid_quantity' ? 'unprocessable' : detail === 'reservation_limit' ? 'too_many_requests' : 'conflict';
    return noStore(apiFail(status, detail, shopRefusalMessage(detail)));
  }
  return noStore(apiFail('server_error', 'operation_failed', shopRefusalMessage('unknown')));
}
