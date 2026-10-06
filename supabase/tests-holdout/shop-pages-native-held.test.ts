// Independent native SHP-PAGE public-hook proof. No source or visible tests read.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';
import type { ShopCatalogueResponse } from '../../packages/shared/src/api/shop';
import { clearShopCache, nativeShopCache, readShopCache, writeShopCache } from '../../apps/mobile/lib/shop-cache';
import * as pageHook from '../../apps/mobile/lib/use-member-shop-pages';

const h = vi.hoisted(() => {
  const post = vi.fn();
  return { slots: [] as unknown[], position: 0, effects: [] as Array<() => void>, cleanups: [] as Array<(() => void) | undefined>, identity: { kind: 'unlinked' } as GymloopIdentity, post, api: { post }, network: { isConnected: true, isInternetReachable: true } };
});
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: h.api, ready: true }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => h.network, getNetworkStateAsync: async () => h.network }));
vi.mock('react', () => {
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const n = h.position++; const previous = h.slots[n] as { deps?: unknown[]; value: unknown } | undefined;
    if (!previous || !deps || deps.some((value, i) => !Object.is(value, previous.deps?.[i]))) h.slots[n] = { deps, value: factory() };
    return (h.slots[n] as { value: unknown }).value;
  };
  const effect = (callback: () => (() => void) | void, deps?: unknown[]) => {
    const n = h.position++; const previous = h.slots[n] as unknown[] | undefined;
    if (!previous || !deps || deps.some((value, i) => !Object.is(value, previous[i]))) {
      h.slots[n] = deps; h.effects.push(() => { h.cleanups[n]?.(); h.cleanups[n] = callback() ?? undefined; });
    }
  };
  return {
    useState: (initial: unknown) => { const n = h.position++; if (!(n in h.slots)) h.slots[n] = typeof initial === 'function' ? initial() : initial; return [h.slots[n], (value: unknown) => { h.slots[n] = typeof value === 'function' ? value(h.slots[n]) : value; }]; },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []), useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps), useEffect: effect, useLayoutEffect: effect,
  };
});
type Row = { reservationId: string; itemName: string; state: string; [key: string]: unknown };
type Hook = { view: null | { scope: string; response: ShopCatalogueResponse; savedAt: string; stale: boolean }; loading: boolean; loadingMore: boolean; error: string | null; visibleCount: number; hasMore: boolean; reload(): Promise<void>; loadMore(): Promise<void> };
const id = (n: number) => `92050000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const member = (n = 1): GymloopIdentity => ({ kind: 'member', userId: id(n), tenantId: id(100), memberId: id(200 + n) });
const instant = '2026-10-07T01:00:00.123456Z';
const cursor = { createdAt: instant, id: id(9) };
const row = (n: number, patch = {}): Row => ({ reservationId: id(n), itemId: id(300), itemName: `Reservation ${n}`, section: 'products', quantity: 1, unitPricePaise: '100', totalPaise: '100', currency: 'INR', state: 'expired', createdAt: instant, expiresAt: '2026-10-07T00:00:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null, ...patch });
const initial = (rows = [row(1), row(2), row(3)], nextAfter: unknown = cursor) => ({ ok: true, data: { mode: 'initial', items: [], reservations: rows, truncated: false, nextAfter, serverTime: instant } });
const more = (rows = [row(4), row(5), row(6), row(7), row(8)], nextAfter: unknown = null) => ({ ok: true, data: { mode: 'more', reservations: rows, nextAfter, serverTime: instant } });
const deferred = <T,>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; };
const render = (): Hook => { h.position = 0; return pageHook.useMemberShopPages() as Hook; };
const settle = async (): Promise<Hook> => { let state = render(); for (let pass = 0; pass < 32; pass += 1) { for (const effect of h.effects.splice(0)) effect(); await Promise.resolve(); state = render(); } return state; };
const scope = (identity = h.identity) => { const value = identity as Extract<GymloopIdentity, { kind: 'member' }>; return `${value.userId}:${value.tenantId}:${value.memberId}`; };
beforeEach(async () => {
  for (const cleanup of h.cleanups) cleanup?.();
  h.slots = []; h.position = 0; h.effects = []; h.cleanups = []; vi.clearAllMocks();
  await clearShopCache(nativeShopCache); h.identity = member(); h.api = { post: h.post }; h.network = { isConnected: true, isInternetReachable: true };
  h.post.mockResolvedValue(initial());
});

describe('independent SHP-PAGE-006 small explicit disclosure', () => {
  it('initial exposes three, keeps five holds accessible, then reveals cached rows without a request', async () => {
    h.post.mockResolvedValue(initial([...Array.from({ length: 5 }, (_, i) => row(i + 1, { state: 'reserved', expiresAt: '2026-10-08T00:00:00Z' })), row(6), row(7), row(8)]));
    const start = await settle(); expect(start.visibleCount).toBe(3); expect(start.view?.response.reservations).toHaveLength(8); expect(start.hasMore).toBe(true);
    expect(h.post).toHaveBeenCalledTimes(1); await start.loadMore(); const shown = await settle();
    expect(shown.visibleCount).toBe(8); expect(h.post).toHaveBeenCalledTimes(1); expect(shown.hasMore).toBe(true);
  });
  it('tap fetches one continuation with untouched cursor, stops at a full final page', async () => {
    const start = await settle(); h.post.mockResolvedValue(more()); await start.loadMore(); const state = await settle();
    expect(h.post).toHaveBeenCalledTimes(2); expect(h.post.mock.calls[1]?.[0]).toBe('/api/shop/catalogue/page'); expect(h.post.mock.calls[1]?.[1]).toEqual({ mode: 'more', after: cursor });
    expect(state.visibleCount).toBe(8); expect(state.view?.response.reservations).toHaveLength(8); expect(state.hasMore).toBe(false);
    await state.loadMore(); await settle(); expect(h.post).toHaveBeenCalledTimes(2);
  });
  it('pending continuation synchronously blocks repeated taps without speculative paging', async () => {
    const start = await settle(); const pending = deferred<unknown>(); h.post.mockReturnValue(pending.promise);
    const first = start.loadMore(); const second = start.loadMore(); const busy = render();
    expect(h.post).toHaveBeenCalledTimes(2); expect(busy.loadingMore).toBe(true);
    pending.resolve(more(undefined, cursor)); await Promise.all([first, second]); await settle(); expect(h.post).toHaveBeenCalledTimes(2);
  });
  it.each(['transient', 'malformed'])('failed %s continuation preserves population, count and retry cursor', async failure => {
    const start = await settle(); h.post.mockResolvedValue(failure === 'transient' ? { ok: false, error: { code: 'shop_failed', message: 'Retry the shop.', status: 500 } } : more([row(4, { totalPaise: 100 })]));
    await start.loadMore(); const failed = await settle(); expect(failed.visibleCount).toBe(3); expect(failed.view?.response).toEqual(start.view?.response); expect(failed.error).toEqual(expect.any(String)); expect(failed.hasMore).toBe(true);
    h.post.mockResolvedValue(more()); await failed.loadMore(); await settle(); expect(h.post.mock.calls[2]?.[1]).toEqual({ mode: 'more', after: cursor });
  });
  it('merges an expired formerly active identity and retains latest facts once', async () => {
    h.post.mockResolvedValue(initial([row(1, { state: 'reserved', expiresAt: '2026-10-08T00:00:00Z' }), row(2), row(3)]));
    const start = await settle(); h.post.mockResolvedValue(more([row(1, { state: 'cancelled_by_gym', cancelReason: 'No stock', itemName: 'Updated snapshot' }), row(4), row(5)]));
    await start.loadMore(); const state = await settle(); const all = state.view?.response.reservations ?? [];
    expect(all.map(entry => entry.reservationId)).toEqual([id(1), id(2), id(3), id(4), id(5)]); expect(all[0]).toMatchObject({ state: 'cancelled_by_gym', cancelReason: 'No stock', itemName: 'Updated snapshot' }); expect(state.visibleCount).toBe(5);
  });
});

describe('independent SHP-PAGE-007 caller, refresh and cache lifetime', () => {
  it.each(['userId', 'tenantId', 'memberId', 'api'] as const)('late result is invalidated synchronously for %s', async dimension => {
    const start = await settle(); const oldScope = scope(); const pending = deferred<unknown>(); h.post.mockReturnValue(pending.promise); const action = start.loadMore();
    const never = deferred<unknown>(); if (dimension === 'api') h.api = { post: vi.fn(() => never.promise) }; else h.identity = { ...h.identity, [dimension]: id(999) } as GymloopIdentity;
    const next = render(); if (dimension !== 'api') expect(next.view).toBeNull(); pending.resolve(more([row(500)])); await action;
    const cache = await readShopCache(nativeShopCache, oldScope); expect(cache?.response.reservations.some(entry => entry.reservationId === id(500))).not.toBe(true);
    expect(render().view?.response.reservations.some(entry => entry.reservationId === id(500))).not.toBe(true);
    if (dimension !== 'api') expect(render().view).toBeNull();
  });
  it('refresh replaces population, resets three, and an old continuation cannot write or unlock newer work', async () => {
    const start = await settle(); const old = deferred<unknown>(); h.post.mockReturnValue(old.promise); const first = start.loadMore();
    h.post.mockResolvedValue(initial([row(101), row(102), row(103)], { ...cursor, id: id(103) })); await render().reload(); const fresh = await settle();
    expect(fresh.visibleCount).toBe(3); expect(fresh.view?.response.reservations.map(entry => entry.reservationId)).toEqual([id(101), id(102), id(103)]);
    const newer = deferred<unknown>(); h.post.mockReturnValue(newer.promise); const second = fresh.loadMore();
    old.resolve(more([row(500)])); await first; expect(render().loadingMore).toBe(true); expect(render().view?.response.reservations.some(entry => entry.reservationId === id(500))).toBe(false);
    const cache = await readShopCache(nativeShopCache, scope()); expect(cache?.response.reservations.some(entry => entry.reservationId === id(500))).not.toBe(true);
    newer.resolve(more([row(104)])); await second; const done = await settle(); expect(done.loadingMore).toBe(false); expect(done.view?.response.reservations.at(-1)?.reservationId).toBe(id(104));
  });
  it('unmount invalidates pending continuation in both memory and the shared cache', async () => {
    const start = await settle(); const pending = deferred<unknown>(); h.post.mockReturnValue(pending.promise); const action = start.loadMore();
    for (const cleanup of h.cleanups) cleanup?.(); pending.resolve(more([row(500)])); await action;
    const cache = await readShopCache(nativeShopCache, scope()); expect(cache?.response.reservations.some(entry => entry.reservationId === id(500))).not.toBe(true);
  });
});

describe('independent SHP-PAGE-008 last-good authorization discipline', () => {
  it('offline reload marks scoped cached data stale and only reveals cached rows', async () => {
    h.post.mockResolvedValue(initial([row(1), row(2), row(3), row(4), row(5)], cursor)); const start = await settle();
    h.network = { isConnected: false, isInternetReachable: false }; await start.reload(); const offline = await settle();
    expect(offline.view?.stale).toBe(true); expect(offline.visibleCount).toBe(3); const reads = h.post.mock.calls.length;
    await offline.loadMore(); const disclosed = await settle(); expect(disclosed.visibleCount).toBe(5); expect(h.post).toHaveBeenCalledTimes(reads);
    await disclosed.loadMore(); const retry = await settle(); expect(retry.visibleCount).toBe(5); expect(retry.error).toEqual(expect.any(String)); expect(h.post).toHaveBeenCalledTimes(reads);
    h.network = { isConnected: true, isInternetReachable: true }; h.post.mockResolvedValue(initial([row(10)], null)); await retry.reload(); const restored = await settle(); expect(restored.view?.stale).toBe(false); expect(restored.visibleCount).toBe(3);
  });
  it.each(['not_signed_in', 'not_permitted', 'unauthorized', 'forbidden'])('authorization %s latches absence through later offline reload until authorized success', async code => {
    const start = await settle(); const saved = start.view!.response; h.post.mockResolvedValue({ ok: false, error: { code, message: 'Sign in again.', status: code === 'not_signed_in' ? 401 : 403 } });
    await start.loadMore(); const refused = await settle(); expect(refused.view).toBeNull(); expect(await readShopCache(nativeShopCache, scope())).toBeNull();
    await writeShopCache(nativeShopCache, scope(), saved); h.network = { isConnected: false, isInternetReachable: false }; await refused.reload(); expect((await settle()).view).toBeNull();
    h.network = { isConnected: true, isInternetReachable: true }; h.post.mockResolvedValue(initial([row(42)], null)); await render().reload(); const recovered = await settle(); expect(recovered.view?.stale).toBe(false); expect(recovered.view?.response.reservations[0]?.reservationId).toBe(id(42));
  });
  it('incomplete member identities never recover cached caller rows or send page requests', async () => {
    const start = await settle(); await writeShopCache(nativeShopCache, scope(), start.view!.response); h.post.mockClear(); h.identity = { kind: 'member', userId: id(1), tenantId: id(100), memberId: '' };
    expect(render().view).toBeNull(); const state = await settle(); await state.reload(); await state.loadMore(); expect(render().view).toBeNull(); expect(h.post).not.toHaveBeenCalled();
  });
});
