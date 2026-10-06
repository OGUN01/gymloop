import { describe, expect, it } from 'vitest';
import * as shop from '../shop';

// SHP-PAGE-004/005/009: authored from the frozen public contract, source-blind.
const id = '85000000-0000-4000-8000-000000000001';
const instant = '2026-10-07T09:10:11.123456+05:30';
const cursor = { createdAt: instant, id };
const row = { reservationId: id, itemId: id, itemName: 'Snapshot name', section: 'products', quantity: 2, unitPricePaise: '9007199254740993', totalPaise: '18014398509481986', currency: 'INR', state: 'expired', createdAt: instant, expiresAt: '2026-10-08T09:10:11Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null };
const initial = { mode: 'initial', items: [], reservations: [row], nextAfter: cursor, truncated: false, serverTime: instant };
const more = { mode: 'more', reservations: [row], nextAfter: null, serverTime: instant };

describe('SHP-PAGE frozen strict shared page contract', () => {
  it('preserves exact microsecond text and explicit offsets', () => {
    expect(shop.shopReservationCursorSchema.parse(cursor)).toEqual(cursor);
    expect(shop.shopReservationCursorSchema.parse({ ...cursor, createdAt: '2026-10-07T03:40:11.123456Z' }).createdAt).toBe('2026-10-07T03:40:11.123456Z');
  });
  it.each([
    { createdAt: '2026-10-07T09:10:11', id },
    { createdAt: '2026-02-30T09:10:11Z', id },
    { createdAt: '2026-10-07T24:00:00Z', id },
    { createdAt: instant }, { id }, { createdAt: instant, id: 'invalid' },
    { ...cursor, tenantId: id }, { ...cursor, memberId: id }, { ...cursor, pageSize: 5 },
  ])('refuses malformed or identity-bearing cursor %j', value => {
    expect(shop.shopReservationCursorSchema.safeParse(value).success).toBe(false);
  });
  it('accepts precisely initial or an explicit non-null continuation', () => {
    expect(shop.shopPageRequestSchema.parse({ mode: 'initial' })).toEqual({ mode: 'initial' });
    expect(shop.shopPageRequestSchema.parse({ mode: 'more', after: cursor })).toEqual({ mode: 'more', after: cursor });
  });
  it.each([{}, { mode: 'initial', after: null }, { mode: 'initial', after: cursor }, { mode: 'more' }, { mode: 'more', after: null }, { mode: 'more', after: { createdAt: instant } }, { mode: 'more', after: cursor, pageSize: 50 }, { mode: 'initial', tenantId: id }, { mode: 'initial', memberId: id }])('refuses non-contract request %j', value => {
    expect(shop.shopPageRequestSchema.safeParse(value).success).toBe(false);
  });
  it('preserves exact decimal-string money through both modes', () => {
    for (const response of [initial, more]) {
      const parsed = shop.shopPageResponseSchema.parse(response);
      expect(parsed.reservations[0]?.totalPaise).toBe('18014398509481986');
      expect(parsed.reservations[0]?.unitPricePaise).toBe('9007199254740993');
      expect(parsed.serverTime).toBe(instant);
    }
  });
  it('validates separate eight-row initial and five-row continuation bounds', () => {
    expect(shop.shopPageResponseSchema.safeParse({ ...initial, reservations: Array.from({ length: 8 }, () => row) }).success).toBe(true);
    expect(shop.shopPageResponseSchema.safeParse({ ...initial, reservations: Array.from({ length: 9 }, () => row) }).success).toBe(false);
    expect(shop.shopPageResponseSchema.safeParse({ ...more, reservations: Array.from({ length: 5 }, () => row) }).success).toBe(true);
    expect(shop.shopPageResponseSchema.safeParse({ ...more, reservations: Array.from({ length: 6 }, () => row) }).success).toBe(false);
  });
  it('keeps initial catalogue capped at 200', () => {
    const item = { itemId: id, section: 'products', name: 'Product', description: 'Actual item', pricePaise: '99', currency: 'INR', gstRateBp: 0, validityDays: 7, cancellationTerms: 'Ask desk', quoteVersion: id, categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 1 };
    expect(shop.shopPageResponseSchema.safeParse({ ...initial, items: Array.from({ length: 200 }, () => item) }).success).toBe(true);
    expect(shop.shopPageResponseSchema.safeParse({ ...initial, items: Array.from({ length: 201 }, () => item) }).success).toBe(false);
  });
  it.each([{ ...more, items: [] }, { ...more, truncated: false }, { ...initial, objectKey: 'private' }, { ...more, nextAfter: { ...cursor, storageKey: 'private' } }, { ...initial, mode: 'other' }, { ...more, serverTime: 'not-an-instant' }, { ...more, reservations: [{ ...row, totalPaise: 99 }] }, { ...more, reservations: [{ ...row, state: 'paid' }] }])('refuses malformed backend page %j', value => {
    expect(shop.shopPageResponseSchema.safeParse(value).success).toBe(false);
  });
  it('retains strict released catalogue and empty member-cancel contracts', () => {
    const legacy = { items: [], reservations: Array.from({ length: 50 }, () => row), truncated: false, serverTime: instant };
    expect(shop.shopCatalogueResponseSchema.safeParse(legacy).success).toBe(true);
    expect(shop.shopCatalogueRequestSchema.parse({})).toEqual({});
    expect(shop.shopMemberCancelRequestSchema.parse({})).toEqual({});
    for (const schema of [shop.shopCatalogueRequestSchema, shop.shopMemberCancelRequestSchema]) {
      expect(schema.safeParse({ mode: 'initial' }).success).toBe(false);
      expect(schema.safeParse({ after: cursor }).success).toBe(false);
    }
  });
});
