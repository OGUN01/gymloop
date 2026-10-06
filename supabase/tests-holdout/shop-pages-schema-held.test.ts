// Independent SHP-PAGE contract author. No production source or visible suite read.
import { describe, expect, it } from 'vitest';
import * as shop from '../../packages/shared/src/api/shop';

type Schema = { safeParse(input: unknown): { success: boolean }; parse(input: unknown): unknown };
type PublicSchemas = { shopReservationCursorSchema: Schema; shopPageRequestSchema: Schema; shopPageResponseSchema: Schema; shopCatalogueRequestSchema: Schema; shopMemberCancelRequestSchema: Schema; shopCatalogueResponseSchema: Schema };
const publicSchemas = shop as unknown as PublicSchemas;
const id = '92030000-0000-4000-8000-000000000001';
const instant = '2026-10-07T00:00:00.987654+05:30';
const cursor = { createdAt: instant, id };
const reservation = (patch = {}) => ({ reservationId: id, itemId: id, itemName: 'Stored name', section: 'products', quantity: 10, unitPricePaise: '9007199254740993', totalPaise: '90071992547409930', currency: 'INR', state: 'expired', createdAt: instant, expiresAt: '2026-10-08T00:00:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null, ...patch });
const item = { itemId: id, section: 'products', name: 'Current name', description: 'Plain description', pricePaise: '100', currency: 'INR', gstRateBp: 0, validityDays: 30, cancellationTerms: 'Desk terms', quoteVersion: id, categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 2 };
const initial = (patch = {}) => ({ mode: 'initial', items: [], reservations: [], nextAfter: null, truncated: false, serverTime: instant, ...patch });
const more = (patch = {}) => ({ mode: 'more', reservations: [], nextAfter: null, serverTime: instant, ...patch });

describe('independent SHP-PAGE-003/004 strict string cursor', () => {
  it.each(['2026-10-07T00:00:00.123456Z', instant, '2026-10-06T18:30:00.000001-04:00'])('preserves exact valid timestamp %s', createdAt => {
    expect(publicSchemas.shopReservationCursorSchema.parse({ createdAt, id })).toEqual({ createdAt, id });
  });
  it.each([
    { createdAt: '2026-10-07T00:00:00', id }, { createdAt: '2026-02-30T00:00:00Z', id },
    { createdAt: '2026-10-07', id }, { createdAt: '2026-10-07T24:01:00Z', id },
    { createdAt: '2026-10-07T00:00:00+25:00', id }, { createdAt: '2026-10-07T00:00:00Z ', id },
    { createdAt: new Date('2026-10-07T00:00:00Z'), id }, { createdAt: instant, id: 'not-an-id' },
    { createdAt: instant }, { id }, {}, null,
    { ...cursor, memberId: id }, { ...cursor, tenantId: id }, { ...cursor, pageSize: 50 },
  ])('rejects malformed, partial or identity-bearing cursor %#', bad => {
    expect(publicSchemas.shopReservationCursorSchema.safeParse(bad).success).toBe(false);
  });
  it('accepts only the two explicit page request variants', () => {
    expect(publicSchemas.shopPageRequestSchema.parse({ mode: 'initial' })).toEqual({ mode: 'initial' });
    expect(publicSchemas.shopPageRequestSchema.parse({ mode: 'more', after: cursor })).toEqual({ mode: 'more', after: cursor });
  });
  it.each([
    {}, { mode: 'initial', after: cursor }, { mode: 'more' }, { mode: 'more', after: null },
    { mode: 'initial', tenantId: id }, { mode: 'initial', memberId: id }, { mode: 'initial', limit: 5 },
    { mode: 'more', after: cursor, pageSize: 3 }, { mode: 'more', after: { ...cursor, staffId: id } },
    { mode: 'unknown' }, { mode: 'more', after: { createdAt: instant, id: null } },
  ])('strict request rejects a restart, selector or size override %#', bad => {
    expect(publicSchemas.shopPageRequestSchema.safeParse(bad).success).toBe(false);
  });
});

describe('independent SHP-PAGE-002/004/005/009 response and released schemas', () => {
  it('accepts exactly eight initial reservations, five continuation rows and 200 items', () => {
    expect(publicSchemas.shopPageResponseSchema.safeParse(initial({ items: Array.from({ length: 200 }, () => item), reservations: Array.from({ length: 8 }, () => reservation()), nextAfter: cursor })).success).toBe(true);
    expect(publicSchemas.shopPageResponseSchema.safeParse(more({ reservations: Array.from({ length: 5 }, () => reservation()), nextAfter: cursor })).success).toBe(true);
  });
  it.each([
    initial({ items: Array.from({ length: 201 }, () => item) }),
    initial({ reservations: Array.from({ length: 9 }, () => reservation()) }),
    more({ reservations: Array.from({ length: 6 }, () => reservation()) }),
    more({ items: [] }), more({ truncated: false }), initial({ memberId: id }),
    more({ nextAfter: { createdAt: instant } }), initial({ serverTime: '2026-02-30T00:00:00Z' }),
    more({ serverTime: '2026-10-07T00:00:00' }),
    more({ reservations: [reservation({ unitPricePaise: 9007199254740992 })] }),
    more({ reservations: [reservation({ totalPaise: '9.1e16' })] }),
    more({ reservations: [reservation({ object_key: 'private/path' })] }),
    more({ reservations: [reservation({ state: 'paid' })] }),
  ])('refuses invalid mode, bounds, backend facts and metadata %#', invalid => {
    expect(publicSchemas.shopPageResponseSchema.safeParse(invalid).success).toBe(false);
  });
  it('keeps integer decimal money and timestamp precision through decoding', () => {
    expect(publicSchemas.shopPageResponseSchema.parse(more({ reservations: [reservation()], nextAfter: cursor }))).toEqual(more({ reservations: [reservation()], nextAfter: cursor }));
  });
  it('released catalogue and member cancellation retain their strict empty requests', () => {
    for (const name of ['shopCatalogueRequestSchema', 'shopMemberCancelRequestSchema'] as const) {
      expect(publicSchemas[name].parse({})).toEqual({});
      for (const body of [{ mode: 'initial' }, { after: cursor }, { nextAfter: cursor }, { memberId: id }]) expect(publicSchemas[name].safeParse(body).success).toBe(false);
    }
    const released = { items: [], reservations: [], truncated: false, serverTime: instant };
    expect(publicSchemas.shopCatalogueResponseSchema.parse(released)).toEqual(released);
    expect(publicSchemas.shopCatalogueResponseSchema.safeParse({ ...released, mode: 'initial', nextAfter: null }).success).toBe(false);
  });
});
