import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { SHOP_LIMITS, SHOP_PAGE_LIMITS, SHOP_SORT_ORDER_MAX, BASIS_POINTS_PER_PERCENT, BASIS_POINT_DECIMAL_PLACES } from '../config/constants';
import { addonSaleRequestSchema } from './addons';

export const SHOP_SECTIONS = ['products', 'services'] as const;
export type ShopSection = (typeof SHOP_SECTIONS)[number];
export const SHOP_AVAILABILITY = ['available', 'out_of_stock'] as const;
export const SHOP_RESERVATION_STATES = [...Constants.public.Enums.shop_reservation_status, 'expired'] as const;
export function shopSectionForKind(kind: string): ShopSection | null { return kind === 'product' ? 'products' : kind === 'diet_plan' ? 'services' : null; }
export const shopReserveRequestSchema = z.strictObject({ itemId: z.uuid(), quantity: z.number().int().min(1).max(SHOP_LIMITS.maxQuantityPerReservation), quoteVersion: z.uuid() });
export const shopCatalogueRequestSchema = z.strictObject({});
export const shopMemberCancelRequestSchema = z.strictObject(shopCatalogueRequestSchema.shape);
export const shopDeskCancelRequestSchema = z.strictObject({ reason: z.string().trim().min(SHOP_LIMITS.cancelReasonMin).max(SHOP_LIMITS.cancelReasonMax) });
export const shopFulfilRequestSchema = z.strictObject({ quoteVersion: addonSaleRequestSchema.shape.quoteVersion, method: addonSaleRequestSchema.shape.method, reason: addonSaleRequestSchema.shape.reason, idempotencyKey: addonSaleRequestSchema.shape.idempotencyKey });
export const shopProductDisplayRequestSchema = z.strictObject({ categoryId: z.uuid().nullable(), sortOrder: z.number().int().min(0).max(SHOP_SORT_ORDER_MAX), imageAssetId: z.uuid().nullable() });
const categoryName = z.string().trim().min(1).max(SHOP_LIMITS.categoryNameMax);
export const shopCategoryCreateRequestSchema = z.strictObject({ name: categoryName });
export const shopCategoryPatchRequestSchema = z.strictObject({ name: categoryName.optional(), isActive: z.boolean().optional() }).refine(value => Object.keys(value).length > 0);
export const shopCategoryOrderRequestSchema = z.strictObject({ orderedIds: z.array(z.uuid()).min(1).max(SHOP_LIMITS.catalogueMax) });
const money = z.string().regex(/^(?:0|[1-9][0-9]*)$/);
const instant = z.iso.datetime({ offset: true });
export const shopReserveResultSchema = z.array(z.strictObject({ reservation_id: z.uuid(), expires_at: instant })).length(1);
export const shopFulfilResultSchema = z.array(z.strictObject({ reservation_id: z.uuid(), order_id: z.uuid(), payment_id: z.uuid().nullable(), replayed: z.boolean() })).length(1);
export const shopItemSchema = z.strictObject({ itemId: z.uuid(), section: z.enum(SHOP_SECTIONS), name: z.string().trim().min(1), description: z.string().trim().min(1), pricePaise: money, currency: z.literal('INR'), gstRateBp: z.number().int().nonnegative(), validityDays: z.number().int().positive(), cancellationTerms: z.string().trim().min(1), quoteVersion: z.uuid(), categoryId: z.uuid().nullable(), categoryName: z.string().nullable(), imageUrl: z.url().nullable(), availability: z.enum(SHOP_AVAILABILITY), availableQuantity: z.number().int().nonnegative().nullable() });
export type ShopItem = z.infer<typeof shopItemSchema>;
export const shopReservationSchema = z.strictObject({ reservationId: z.uuid(), itemId: z.uuid(), itemName: z.string(), section: z.enum(SHOP_SECTIONS), quantity: z.number().int().positive(), unitPricePaise: money, totalPaise: money, currency: z.literal('INR'), state: z.enum(SHOP_RESERVATION_STATES), createdAt: instant, expiresAt: instant, cancelReason: z.string().nullable(), termsChanged: z.boolean(), orderId: z.uuid().nullable(), imageUrl: z.url().nullable() });
export type ShopReservation = z.infer<typeof shopReservationSchema>;
export const shopCatalogueResponseSchema = z.strictObject({ items: z.array(shopItemSchema).max(SHOP_LIMITS.catalogueMax), reservations: z.array(shopReservationSchema), truncated: z.boolean(), serverTime: instant });
export type ShopCatalogueResponse = z.infer<typeof shopCatalogueResponseSchema>;

/** Cursor timestamps retain database precision, including microseconds. */
export const shopReservationCursorSchema = z.strictObject({ createdAt: instant, id: z.uuid() });
export type ShopReservationCursor = z.infer<typeof shopReservationCursorSchema>;
export const shopPageRequestSchema = z.discriminatedUnion('mode', [
  z.strictObject({ mode: z.literal('initial') }),
  z.strictObject({ mode: z.literal('more'), after: shopReservationCursorSchema }),
]);
export type ShopPageRequest = z.infer<typeof shopPageRequestSchema>;
export const shopPageResponseSchema = z.discriminatedUnion('mode', [
  z.strictObject({ mode: z.literal('initial'), items: z.array(shopItemSchema).max(SHOP_LIMITS.catalogueMax), reservations: z.array(shopReservationSchema).max(SHOP_PAGE_LIMITS.initialReservations), nextAfter: shopReservationCursorSchema.nullable(), truncated: z.boolean(), serverTime: instant }),
  z.strictObject({ mode: z.literal('more'), reservations: z.array(shopReservationSchema).max(SHOP_PAGE_LIMITS.historyPage), nextAfter: shopReservationCursorSchema.nullable(), serverTime: instant }),
]);
export type ShopPageResponse = z.infer<typeof shopPageResponseSchema>;
/** Strict database JSON boundary; shares the released reservation facts. */
export const shopReservationRecordSchema = z.strictObject({
  reservation_id: shopReservationSchema.shape.reservationId, item_id: shopReservationSchema.shape.itemId,
  item_name: shopReservationSchema.shape.itemName, section: shopReservationSchema.shape.section,
  quantity: shopReservationSchema.shape.quantity, unit_price_paise: shopReservationSchema.shape.unitPricePaise,
  total_paise: shopReservationSchema.shape.totalPaise, currency: shopReservationSchema.shape.currency,
  state: shopReservationSchema.shape.state, created_at: shopReservationSchema.shape.createdAt,
  expires_at: shopReservationSchema.shape.expiresAt, cancel_reason: shopReservationSchema.shape.cancelReason,
  terms_changed: shopReservationSchema.shape.termsChanged, order_id: shopReservationSchema.shape.orderId,
  image_asset_id: z.uuid().nullable(),
});
export const shopPageRpcRowSchema = z.strictObject({
  active_reservations: z.array(shopReservationRecordSchema).max(SHOP_PAGE_LIMITS.active),
  history: z.array(shopReservationRecordSchema).max(SHOP_PAGE_LIMITS.historyPage),
  next_after_created_at: instant.nullable(), next_after_id: z.uuid().nullable(), as_of: instant,
}).refine(row => (row.next_after_created_at === null) === (row.next_after_id === null))
  .refine(row => row.next_after_id === null || row.history.length > 0);
export function groupShopItems(items: ShopItem[]) {
  const products: { categoryId: string | null; categoryName: string | null; items: ShopItem[] }[] = [];
  const services: ShopItem[] = [];
  for (const item of items) {
    if (item.section === 'services') { services.push(item); continue; }
    const last = products.at(-1);
    if (last && last.categoryId === item.categoryId) last.items.push(item);
    else products.push({ categoryId: item.categoryId, categoryName: item.categoryName, items: [item] });
  }
  return { products, services };
}
export function shopMaxQuantity(item: ShopItem): number { return item.availability === 'out_of_stock' ? 0 : item.section === 'services' ? 1 : Math.min(item.availableQuantity ?? 0, SHOP_LIMITS.maxQuantityPerReservation); }
export function shopGstLabel(gstRateBp: number, place: string): string | null {
  if (gstRateBp === 0) return null;
  const rate = BigInt(gstRateBp);
  const remainder = String(rate % BASIS_POINTS_PER_PERCENT).padStart(BASIS_POINT_DECIMAL_PLACES, '0').replace(/0+$/, '');
  return `GST rate set by your ${place}: ${rate / BASIS_POINTS_PER_PERCENT}${remainder ? `.${remainder}` : ''}%. You pay the price shown.`;
}
export function shopReserveNotice(input: { place: string; heldUntil: string }): string { return `Reserving holds this for you until ${input.heldUntil}. You pay and collect it at the front desk of your ${input.place}. Nothing is charged in the app, and it is yours only once the desk records the sale.`; }
export const SHOP_REFUSAL_COPY = {
  sold_out: "There isn't enough left to reserve that many. Try fewer, or check back later.",
  item_unavailable: "This item isn't available to reserve right now.",
  quote_changed: 'The price or details of this item changed. Review it and reserve again.',
  member_unavailable: "Reserving isn't available on your account right now. Ask the front desk.",
  invalid_quantity: 'Choose a quantity within the limit shown.',
  reservation_exists: 'You already have this item reserved. Cancel that reservation first to change it.',
  reservation_limit: "You've reached the reservation limit for now. Cancel one you no longer need, or try again tomorrow.",
  reservation_not_open: 'This reservation has already been collected or cancelled.',
  reservation_expired: 'This reservation has expired. Ask the front desk to sell it to you directly.',
} as const;
export function shopRefusalMessage(code: string): string { return Object.hasOwn(SHOP_REFUSAL_COPY, code) ? SHOP_REFUSAL_COPY[code as keyof typeof SHOP_REFUSAL_COPY] : "That didn't go through. Try again."; }
export const SHOP_TERMS_CHANGED_NOTE = 'The price or details changed after you reserved. The desk will confirm them before you pay.';
export function shopOfflineNotice(savedAt: string): string { return `You're offline. Showing the shop as it was saved ${savedAt}. Reserving needs a connection.`; }
export function shopReservationStateWord(state: string): string {
  switch (state) { case 'reserved': return 'Reserved'; case 'expired': return 'Expired'; case 'fulfilled': return 'Collected'; case 'cancelled_by_member': return 'Cancelled'; case 'cancelled_by_gym': return 'Cancelled by the gym'; default: return 'Unavailable'; }
}
