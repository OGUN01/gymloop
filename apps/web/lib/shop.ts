import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { SHOP_LIMITS, SHOP_PAGE_LIMITS, SHOP_REFUSAL_COPY, shopRefusalMessage, shopCatalogueResponseSchema, shopItemSchema, shopReservationSchema, shopReservationRecordSchema, shopPageRequestSchema, shopPageResponseSchema, shopPageRpcRowSchema, type ShopCatalogueResponse, type ShopPageRequest, type ShopPageResponse } from '@gymloop/shared';
import { apiFail, noStore } from './api';

/** A forwarded member session signs each verified image at most once per read. */
async function memberShopImages(supabase: SupabaseClient<Database>) {
  const { memberMediaUrl } = await import('./media');
  const images = new Map<string, Promise<string | null>>();
  return (assetId: string | null) => {
    if (!assetId) return Promise.resolve(null);
    if (!images.has(assetId)) images.set(assetId, memberMediaUrl(supabase, assetId).catch(() => null));
    return images.get(assetId)!;
  };
}
async function projectShopItem(row: Database['public']['Functions']['read_member_shop']['Returns'][number], image: Awaited<ReturnType<typeof memberShopImages>>) {
  return shopItemSchema.parse({ itemId: row.item_id, section: row.section, name: row.name, description: row.description, pricePaise: row.price_paise, currency: row.currency, gstRateBp: row.gst_rate_bp, validityDays: row.validity_days, cancellationTerms: row.cancellation_terms, quoteVersion: row.quote_version, categoryId: row.category_id, categoryName: row.category_name, imageUrl: await image(row.image_asset_id), availability: row.availability, availableQuantity: row.available_quantity });
}
async function projectShopReservation(row: ReturnType<typeof shopReservationRecordSchema.parse>, image: Awaited<ReturnType<typeof memberShopImages>>) {
  return shopReservationSchema.parse({ reservationId: row.reservation_id, itemId: row.item_id, itemName: row.item_name, section: row.section, quantity: row.quantity, unitPricePaise: row.unit_price_paise, totalPaise: row.total_paise, currency: row.currency, state: row.state, createdAt: row.created_at, expiresAt: row.expires_at, cancelReason: row.cancel_reason, termsChanged: row.terms_changed, orderId: row.order_id, imageUrl: await image(row.image_asset_id) });
}

/** Only caller-scoped public RPCs cross the member projection boundary. */
export async function loadMemberShop(supabase: SupabaseClient<Database>, _tenantId: string): Promise<ShopCatalogueResponse> {
  void _tenantId; // RPC derives scope exclusively from the verified caller.
  const [catalogue, history] = await Promise.all([supabase.rpc('read_member_shop'), supabase.rpc('read_member_shop_reservations')]);
  if (catalogue.error || history.error) throw new Error('The shop could not be loaded.');
  const rows = catalogue.data ?? [];
  const image = await memberShopImages(supabase);
  const items = await Promise.all(rows.slice(0, SHOP_LIMITS.catalogueMax).map(row => projectShopItem(row, image)));
  const reservations = await Promise.all((history.data ?? []).map(row => projectShopReservation(shopReservationRecordSchema.parse(row), image)));
  return shopCatalogueResponseSchema.parse({ items, reservations, truncated: rows.length > SHOP_LIMITS.catalogueMax, serverTime: new Date().toISOString() });
}

/** Opt-in bounded history; the database derives identity and preserves precision. */
export async function loadMemberShopPage(supabase: SupabaseClient<Database>, input: ShopPageRequest): Promise<ShopPageResponse> {
  const request = shopPageRequestSchema.parse(input);
  const after = request.mode === 'more' ? request.after : null;
  // This fixed literal bridge is removed after CI applies the migration and types are regenerated.
  const reservationRead = supabase.rpc('read_member_shop_reservation_page' as keyof Database['public']['Functions'], { p_after_created_at: after?.createdAt ?? null, p_after_id: after?.id ?? null } as never);
  const [page, catalogue] = await Promise.all([reservationRead, request.mode === 'initial' ? supabase.rpc('read_member_shop') : Promise.resolve(null)]);
  if (page.error) throw page.error;
  if (catalogue?.error) throw catalogue.error;
  if (!Array.isArray(page.data) || page.data.length !== 1) throw new Error('Invalid shop page.');
  const row = shopPageRpcRowSchema.parse(page.data[0]);
  if ((request.mode === 'more' && row.active_reservations.length !== 0)
    || (request.mode === 'initial' && row.history.length > SHOP_PAGE_LIMITS.initialHistory)
    || row.active_reservations.some(reservation => reservation.state !== 'reserved')
    || row.history.some(reservation => reservation.state === 'reserved')) throw new Error('Invalid shop page.');
  const image = await memberShopImages(supabase);
  const reservations = await Promise.all([...row.active_reservations, ...row.history].map(reservation => projectShopReservation(reservation, image)));
  const nextAfter = row.next_after_created_at && row.next_after_id ? { createdAt: row.next_after_created_at, id: row.next_after_id } : null;
  const common = { reservations, nextAfter, serverTime: row.as_of };
  if (request.mode === 'more') return shopPageResponseSchema.parse({ mode: 'more', ...common });
  const rows = catalogue?.data ?? [];
  const items = await Promise.all(rows.slice(0, SHOP_LIMITS.catalogueMax).map(item => projectShopItem(item, image)));
  return shopPageResponseSchema.parse({ mode: 'initial', ...common, items, truncated: rows.length > SHOP_LIMITS.catalogueMax });
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
