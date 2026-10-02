import { describe, expect, it } from 'vitest';
import { createMemoryShopCache, writeShopCache, readShopCache, clearShopCache } from '../../../mobile/lib/shop-cache';
import { shopCacheScope, reserveOutcomeMessage, heldUntilLabel } from '../../../mobile/lib/shop';
const response = { items: [], reservations: [], truncated: false, serverTime: '2026-10-02T04:30:00Z' };
const identity = { kind: 'member' as const, userId: 'user', tenantId: 'tenant', memberId: 'member', role: 'member' as const };
describe('SHP-022 last-good app-run-only cache', () => {
  it('separates the verified identity components', () => expect(shopCacheScope(identity)).toBe('user:tenant:member'));
  it('returns last-good validated response with saved time', async () => { const store = createMemoryShopCache(); await writeShopCache(store, 'u:t:m', response); const saved = await readShopCache(store, 'u:t:m'); expect(saved?.response).toEqual(response); expect(saved?.savedAt).toEqual(expect.any(String)); expect(Number.isNaN(Date.parse(saved?.savedAt ?? ''))).toBe(false); });
  it('does not expose another identity or persist across app restart', async () => { const store = createMemoryShopCache(); await writeShopCache(store, 'u:t:m', response); expect(await readShopCache(store, 'u:other:m')).toBeNull(); expect(await readShopCache(createMemoryShopCache(), 'u:t:m')).toBeNull(); });
  it('signout clearing removes all remembered scopes', async () => { const store = createMemoryShopCache(); await writeShopCache(store, 'u:t:m', response); await writeShopCache(store, 'v:t:n', response); await clearShopCache(store); expect(await readShopCache(store, 'u:t:m')).toBeNull(); expect(await readShopCache(store, 'v:t:n')).toBeNull(); });
  it('corrupt cache cannot manufacture a successful catalogue', async () => { const store = createMemoryShopCache(); await store.set('u:t:m', '{broken'); expect(await readShopCache(store, 'u:t:m')).toBeNull(); });
  it('never translates an unknown refusal into a success', () => { expect(reserveOutcomeMessage('network_failed')).toBe("That didn't go through. Try again."); expect(reserveOutcomeMessage('sold_out')).toBe("There isn't enough left to reserve that many. Try fewer, or check back later."); });
  it('formats holds in the gym timezone rather than device timezone', () => { const label = heldUntilLabel('2026-10-02T04:30:00Z', 'Asia/Kolkata'); expect(label).toMatch(/10:00|10\.00/); });
});
