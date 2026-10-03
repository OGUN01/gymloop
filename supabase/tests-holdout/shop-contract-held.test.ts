// Independent frozen-contract holdout; no SHP implementation or visible suite read.
import { describe, expect, it } from 'vitest';
import * as publicShared from '../../packages/shared/src/index';
type ContractSymbol = ((...args: unknown[]) => unknown) & { safeParse(value: unknown): { success: boolean }; parse(value: unknown): { name: string; pricePaise: string } };
const s = publicShared as unknown as Record<string, ContractSymbol>;
const id = '72910000-0000-4000-8000-000000000001';
const item = (patch = {}) => ({ itemId: id, section: 'products', name: 'Protein', description: 'Plain text', pricePaise: '9007199254740993', currency: 'INR', gstRateBp: 250, validityDays: 30, cancellationTerms: 'Ask desk', quoteVersion: id, categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 3, ...patch });
describe('SHP independent shared contract', () => {
  it.each([
    ['shopReserveRequestSchema', { itemId: id, quantity: 1, quoteVersion: id }],
    ['shopCatalogueRequestSchema', {}], ['shopMemberCancelRequestSchema', {}],
    ['shopDeskCancelRequestSchema', { reason: 'No stock' }],
    ['shopProductDisplayRequestSchema', { categoryId: null, sortOrder: 0, imageAssetId: null }],
    ['shopCategoryCreateRequestSchema', { name: 'Food' }],
    ['shopCategoryPatchRequestSchema', { isActive: false }],
    ['shopCategoryOrderRequestSchema', { orderedIds: [id] }],
    ['shopFulfilRequestSchema', { quoteVersion: id, method: 'cash', reason: null, idempotencyKey: id }],
  ])('%s accepts fixed shape and rejects identity/unknown fields', (name, body) => {
    expect(s[name].safeParse(body).success).toBe(true);
    for (const extra of ['tenantId', 'memberId', 'staffId', 'objectKey', '__proto_payload']) expect(s[name].safeParse({ ...body, [extra]: id }).success).toBe(false);
  });
  it('quantity, full-replace display, category and payment boundaries are strict', () => {
    for (const quantity of [0, -1, 11, 1.5, '1', null]) expect(s.shopReserveRequestSchema.safeParse({ itemId: id, quantity, quoteVersion: id }).success).toBe(false);
    for (const body of [{}, { categoryId: null }, { categoryId: null, sortOrder: 0 }]) expect(s.shopProductDisplayRequestSchema.safeParse(body).success).toBe(false);
    expect(s.shopCategoryPatchRequestSchema.safeParse({}).success).toBe(false);
    expect(s.shopCategoryCreateRequestSchema.parse({ name: '  Food  ' })).toEqual({ name: 'Food' });
    expect(s.shopDeskCancelRequestSchema.safeParse({ reason: '  a  ' }).success).toBe(false);
    expect(s.shopFulfilRequestSchema.safeParse({ quoteVersion: id, method: 'razorpay', reason: null, idempotencyKey: id }).success).toBe(false);
  });
  it('price stays exact decimal text, RPC and image secrets cannot enter the display model', () => {
    expect(s.shopItemSchema.parse(item()).pricePaise).toBe('9007199254740993');
    for (const pricePaise of [9007199254740992, '-1', '1.5', '1e3', ' 1', '']) expect(s.shopItemSchema.safeParse(item({ pricePaise })).success).toBe(false);
    for (const key of ['object_key', 'staging_object_key', 'published_etag', 'stock_quantity']) expect(s.shopItemSchema.safeParse(item({ [key]: 'PRIVATE' })).success).toBe(false);
  });
  it('kind, bounded quantity and GST do not invent product stock or tax', () => {
    expect(['product', 'diet_plan', 'pt_package', 'other'].map(s.shopSectionForKind)).toEqual(['products', 'services', null, null]);
    expect(s.shopMaxQuantity(item())).toBe(3); expect(s.shopMaxQuantity(item({ availableQuantity: 99 }))).toBe(10);
    expect(s.shopMaxQuantity(item({ availability: 'out_of_stock' }))).toBe(0);
    expect(s.shopMaxQuantity(item({ section: 'services', availableQuantity: null }))).toBe(1);
    expect(s.shopGstLabel(0, 'studio')).toBeNull();
    expect(s.shopGstLabel(250, 'studio')).toBe('GST rate set by your studio: 2.5%. You pay the price shown.');
    expect(s.shopGstLabel(1800, 'gym')).toBe('GST rate set by your gym: 18%. You pay the price shown.');
  });
  it('reservation words and desk-only payment notice remain literal', () => {
    expect(['reserved', 'expired', 'fulfilled', 'cancelled_by_member', 'cancelled_by_gym', 'paid'].map(s.shopReservationStateWord)).toEqual(['Reserved', 'Expired', 'Collected', 'Cancelled', 'Cancelled by the gym', 'Unavailable']);
    expect(s.shopReserveNotice({ place: 'studio', heldUntil: 'tomorrow 10 am' })).toBe('Reserving holds this for you until tomorrow 10 am. You pay and collect it at the front desk of your studio. Nothing is charged in the app, and it is yours only once the desk records the sale.');
    expect(s.shopOfflineNotice('10 am')).toBe("You're offline. Showing the shop as it was saved 10 am. Reserving needs a connection.");
    expect(s.shopRefusalMessage('constructor')).toBe("That didn't go through. Try again.");
  });
  it.each([
    ['sold_out', "There isn't enough left to reserve that many. Try fewer, or check back later."],
    ['quote_changed', 'The price or details of this item changed. Review it and reserve again.'],
    ['reservation_expired', 'This reservation has expired. Ask the front desk to sell it to you directly.'],
    ['reservation_exists', 'You already have this item reserved. Cancel that reservation first to change it.'],
  ])('refusal %s preserves outcome and next action', (code, copy) => expect(s.shopRefusalMessage(code)).toBe(copy));
});
describe('MEDIA independent primitive', () => {
  it.each(['product', 'trainer', 'announcement'])('builds only canonical %s namespaces and round-trips them', kind => {
    for (const storageArea of ['staging', 'published']) {
      const key = s.buildMediaObjectKey({ tenantId: id, objectUuid: id, kind, mime: 'image/jpeg', storageArea });
      expect(key).toBe(`${id}/${storageArea}/${kind}/${id}.jpg`);
      expect(s.parseMediaObjectKey(key)).toEqual({ tenantId: id, objectUuid: id, kind, extension: 'jpg', storageArea });
    }
    for (const key of [`${id}/${kind}/${id}.jpg`, `${id}/staging/${kind}/../${id}.jpg`, `${id}/staging/${kind}/${id}.jpg?secret`, `${id}/published/${kind}/${id}.jpeg`]) expect(s.parseMediaObjectKey(key)).toBeNull();
  });
  it('upload schema pins 2 MiB, supported MIME and strict trusted metadata boundary', () => {
    expect(s.mediaUploadRequestSchema.safeParse({ kind: 'product', mime: 'image/png', bytes: 2097152 }).success).toBe(true);
    for (const bytes of [0, 2097153, 1.5, '10']) expect(s.mediaUploadRequestSchema.safeParse({ kind: 'product', mime: 'image/png', bytes }).success).toBe(false);
    for (const mime of ['image/svg+xml', 'image/gif', 'image/png; charset=utf8']) expect(s.mediaUploadRequestSchema.safeParse({ kind: 'product', mime, bytes: 10 }).success).toBe(false);
    // The frozen proposal requires the same UUID validator and strict wire shape,
    // rather than identity of the enclosing strict-object schema.
    const memberMedia = s.memberMediaUrlRequestSchema as unknown as { shape: { assetId: unknown } };
    const confirmMedia = s.mediaConfirmRequestSchema as unknown as { shape: { assetId: unknown } };
    expect(memberMedia.shape.assetId).toBe(confirmMedia.shape.assetId);
    for (const schema of [s.memberMediaUrlRequestSchema, s.mediaConfirmRequestSchema]) {
      expect(schema.safeParse({ assetId: id }).success).toBe(true);
      for (const body of [{}, { assetId: 'not-a-uuid' }, { assetId: null }, { assetId: id, tenantId: id }, { assetId: id, objectKey: 'PRIVATE' }, { assetId: id, checked: true }]) {
        expect(schema.safeParse(body).success).toBe(false);
      }
    }
    expect(s.mediaConfirmRequestSchema.safeParse({ assetId: id, checked: true }).success).toBe(false);
  });
  it('signature validates bytes rather than extension and rejects short or wrong headers', () => {
    const vectors: Array<[string, number[]]> = [['image/jpeg', [255,216,255]], ['image/png', [137,80,78,71,13,10,26,10]], ['image/webp', [82,73,70,70,0,0,0,0,87,69,66,80]]];
    for (const [mime, bytes] of vectors) {
      expect(s.matchesImageSignature(mime, Uint8Array.from(bytes))).toBe(true);
      expect(s.matchesImageSignature(mime, Uint8Array.from(bytes.slice(0, -1)))).toBe(false);
      expect(s.matchesImageSignature(mime, Uint8Array.from([0, ...bytes.slice(1)]))).toBe(false);
    }
  });
  it('source-race and prototype names produce safe fixed copy', () => {
    expect(s.mediaRefusalMessage('upload_changed')).toBe('The photo changed while it was being checked. Choose it again and retry.');
    expect(s.mediaRefusalMessage('__proto__')).toBe("That photo couldn't be saved. Try again.");
  });
});
it('grouping keeps server category order, uncategorised last and services separate', () => {
  const category = '72910000-0000-4000-8000-000000000002';
  const other = '72910000-0000-4000-8000-000000000003';
  const entries = [item({ itemId: category, categoryId: category, categoryName: 'Z first' }), item({ itemId: other, categoryId: category, categoryName: 'Z first' }), item({ itemId: id, categoryId: other, categoryName: 'A second' }), item(), item({ section: 'services' })];
  expect(s.groupShopItems(entries)).toEqual({ products: [{ categoryId: category, categoryName: 'Z first', items: entries.slice(0, 2) }, { categoryId: other, categoryName: 'A second', items: [entries[2]] }, { categoryId: null, categoryName: null, items: [entries[3]] }], services: [entries[4]] });
});
