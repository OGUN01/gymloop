import { describe, expect, it } from 'vitest';
import * as shop from '../shop';
import { SHOP_LIMITS } from '../../config/constants';

const id = '72000000-0000-4000-8000-000000000001';
const item = { itemId: id, section: 'products', name: 'Protein', description: 'Tub', pricePaise: '9007199254740993', currency: 'INR', gstRateBp: 1800, validityDays: 30, cancellationTerms: 'Ask the desk', quoteVersion: id, categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 12 } as const;

describe('frozen SHP shared public contract', () => {
  it('pins every centrally named engineering limit', () => expect(SHOP_LIMITS).toEqual({ reservationTtlHours: 24, maxOpenReservationsPerMember: 5, maxQuantityPerReservation: 10, reservationsPerMemberPerDay: 10, catalogueMax: 200, categoryNameMax: 60, cancelReasonMin: 3, cancelReasonMax: 200 }));
  it.each([['product', 'products'], ['diet_plan', 'services'], ['pt_package', null], ['other', null]] as const)('maps kind %s without inventing a sale kind', (kind, expected) => expect(shop.shopSectionForKind(kind)).toBe(expected));
  it.each([0, -1, 11, 1.5, '1'])('rejects invalid reservation quantity %s', quantity => expect(shop.shopReserveRequestSchema.safeParse({ itemId: id, quantity, quoteVersion: id }).success).toBe(false));
  it('accepts boundary quantity and rejects tenant/price/key injection', () => {
    for (const quantity of [1, 10]) expect(shop.shopReserveRequestSchema.safeParse({ itemId: id, quantity, quoteVersion: id }).success).toBe(true);
    for (const extra of [{ tenantId: id }, { pricePaise: '1' }, { objectKey: 'private' }]) expect(shop.shopReserveRequestSchema.safeParse({ itemId: id, quantity: 1, quoteVersion: id, ...extra }).success).toBe(false);
  });
  it('read and member cancellation bodies are strictly empty', () => {
    for (const schema of [shop.shopCatalogueRequestSchema, shop.shopMemberCancelRequestSchema]) { expect(schema.safeParse({}).success).toBe(true); expect(schema.safeParse({ reason: 'forged' }).success).toBe(false); }
  });
  it('display replacement requires all fields and bounded integral order', () => {
    expect(shop.shopProductDisplayRequestSchema.safeParse({ categoryId: null, imageAssetId: null, sortOrder: 32767 }).success).toBe(true);
    for (const value of [{ sortOrder: 0 }, { categoryId: null, imageAssetId: null, sortOrder: 32768 }, { categoryId: null, imageAssetId: null, sortOrder: -1 }]) expect(shop.shopProductDisplayRequestSchema.safeParse(value).success).toBe(false);
  });
  it('category and cancellation strings trim and enforce bounds', () => {
    expect(shop.shopCategoryCreateRequestSchema.parse({ name: '  Protein  ' })).toEqual({ name: 'Protein' });
    expect(shop.shopCategoryPatchRequestSchema.safeParse({}).success).toBe(false);
    expect(shop.shopCategoryPatchRequestSchema.safeParse({ isActive: false }).success).toBe(true);
    for (const name of ['', ' ', 'a'.repeat(61)]) expect(shop.shopCategoryCreateRequestSchema.safeParse({ name }).success).toBe(false);
    for (const reason of ['ab', ' ', 'a'.repeat(201)]) expect(shop.shopDeskCancelRequestSchema.safeParse({ reason }).success).toBe(false);
    expect(shop.shopDeskCancelRequestSchema.parse({ reason: '  ask desk  ' })).toEqual({ reason: 'ask desk' });
  });
  it('preserves money as decimal text beyond safe JS integer range', () => { expect(shop.shopItemSchema.parse(item).pricePaise).toBe('9007199254740993'); expect(shop.shopItemSchema.safeParse({ ...item, pricePaise: 99 }).success).toBe(false); });
  it.each([[item, 10], [{ ...item, availableQuantity: 2 }, 2], [{ ...item, section: 'services', availableQuantity: null }, 1], [{ ...item, availability: 'out_of_stock' }, 0]] as const)('caps quantity without leaking stock', (value, expected) => expect(shop.shopMaxQuantity(value)).toBe(expected));
  it('groups products in server order and leaves services flat', () => {
    const category = { ...item, itemId: '72000000-0000-4000-8000-000000000002', categoryId: id, categoryName: 'Nutrition' };
    const service = { ...item, section: 'services' as const, availableQuantity: null };
    expect(shop.groupShopItems([category, item, service])).toEqual({ products: [{ categoryId: id, categoryName: 'Nutrition', items: [category] }, { categoryId: null, categoryName: null, items: [item] }], services: [service] });
  });
  it.each([[0, null], [250, 'GST rate set by your studio: 2.5%. You pay the price shown.'], [1800, 'GST rate set by your studio: 18%. You pay the price shown.']] as const)('shows informational GST %s', (rate, expected) => expect(shop.shopGstLabel(rate, 'studio')).toBe(expected));
  it('pins honest reservation and offline disclosures', () => {
    expect(shop.shopReserveNotice({ place: 'studio', heldUntil: 'tomorrow' })).toBe('Reserving holds this for you until tomorrow. You pay and collect it at the front desk of your studio. Nothing is charged in the app, and it is yours only once the desk records the sale.');
    expect(shop.shopOfflineNotice('10 am')).toBe("You're offline. Showing the shop as it was saved 10 am. Reserving needs a connection.");
    expect(shop.SHOP_TERMS_CHANGED_NOTE).toBe('The price or details changed after you reserved. The desk will confirm them before you pay.');
  });
  it.each([['reserved', 'Reserved'], ['expired', 'Expired'], ['fulfilled', 'Collected'], ['cancelled_by_member', 'Cancelled'], ['cancelled_by_gym', 'Cancelled by the gym'], ['paid', 'Unavailable']])('renders state %s honestly', (state, expected) => expect(shop.shopReservationStateWord(state)).toBe(expected));
  it('unknown/prototype refusal keys use safe fallback', () => { for (const key of ['unknown', 'constructor', '__proto__', 'toString']) expect(shop.shopRefusalMessage(key)).toBe("That didn't go through. Try again."); });
  it.each([
    ['sold_out', "There isn't enough left to reserve that many. Try fewer, or check back later."],
    ['item_unavailable', "This item isn't available to reserve right now."],
    ['quote_changed', 'The price or details of this item changed. Review it and reserve again.'],
    ['member_unavailable', "Reserving isn't available on your account right now. Ask the front desk."],
    ['invalid_quantity', 'Choose a quantity within the limit shown.'],
    ['reservation_exists', 'You already have this item reserved. Cancel that reservation first to change it.'],
    ['reservation_limit', "You've reached the reservation limit for now. Cancel one you no longer need, or try again tomorrow."],
    ['reservation_not_open', 'This reservation has already been collected or cancelled.'],
    ['reservation_expired', 'This reservation has expired. Ask the front desk to sell it to you directly.'],
  ])('pins refusal %s verbatim', (code, copy) => { expect(shop.SHOP_REFUSAL_COPY[code as keyof typeof shop.SHOP_REFUSAL_COPY]).toBe(copy); expect(shop.shopRefusalMessage(code)).toBe(copy); });
  it('category reorder has a nonempty bounded UUID array and no extra fields', () => {
    expect(shop.shopCategoryOrderRequestSchema.safeParse({ orderedIds: [id] }).success).toBe(true);
    for (const value of [{ orderedIds: [] }, { orderedIds: ['invalid'] }, { orderedIds: Array.from({ length: 201 }, () => id) }, { orderedIds: [id], tenantId: id }]) expect(shop.shopCategoryOrderRequestSchema.safeParse(value).success).toBe(false);
  });
  it('fulfil schema rejects online method and immutable sale field injection', () => {
    const command = { quoteVersion: id, method: 'cash', reason: null, idempotencyKey: id };
    expect(shop.shopFulfilRequestSchema.safeParse(command).success).toBe(true);
    expect(shop.shopFulfilRequestSchema.safeParse({ ...command, method: 'razorpay' }).success).toBe(false);
    expect(shop.shopFulfilRequestSchema.safeParse({ ...command, pricePaise: '1' }).success).toBe(false);
  });
});
