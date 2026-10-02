import { expect, it } from 'vitest';
import { createMemoryShopCache, writeShopCache, readShopCache, clearShopCache } from '../../apps/mobile/lib/shop-cache';
import { shopCacheScope, reserveOutcomeMessage } from '../../apps/mobile/lib/shop';
const id = '72940000-0000-4000-8000-000000000001';
const identity = { kind: 'member', userId: id, tenantId: id, memberId: id } as const;
const response = { items: [], reservations: [], truncated: false, serverTime: '2026-10-02T10:00:00Z' };
it('scope binds user tenant and member; incomplete and preview identity grant no cached member data', () => {
  expect(shopCacheScope(identity)).toBe(`${id}:${id}:${id}`);
  for (const actor of [{ kind: 'unlinked' }, { ...identity, memberId: undefined }, { kind: 'impersonation', userId: id, tenantId: id, impersonationSessionId: id }]) expect(shopCacheScope(actor as never)).toBeNull();
});
it('in-memory cache is last-good, exact-scope and cleared on signout, never shared across restart', async () => {
  const store = createMemoryShopCache(); const scope = shopCacheScope(identity)!;
  await writeShopCache(store, scope, response);
  expect((await readShopCache(store, scope))?.response).toEqual(response); expect((await readShopCache(store, scope))?.savedAt).toEqual(expect.any(String));
  expect(await readShopCache(store, `${scope}:foreign`)).toBeNull(); expect(await readShopCache(createMemoryShopCache(), scope)).toBeNull();
  await clearShopCache(store); expect(await readShopCache(store, scope)).toBeNull();
});
it('corrupt and foreign cache payloads do not become a last-good catalogue', async () => {
  const store = createMemoryShopCache(); await store.set(id, '{malformed'); expect(await readShopCache(store, id)).toBeNull();
  await store.set(id, JSON.stringify({ response: { ...response, items: [{ pricePaise: 1 }] }, savedAt: response.serverTime })); expect(await readShopCache(store, id)).toBeNull();
});
it('native outcome uses the same pinned safe shared refusal', () => {
  expect(reserveOutcomeMessage('quote_changed')).toBe('The price or details of this item changed. Review it and reserve again.'); expect(reserveOutcomeMessage('constructor')).toBe("That didn't go through. Try again.");
});
