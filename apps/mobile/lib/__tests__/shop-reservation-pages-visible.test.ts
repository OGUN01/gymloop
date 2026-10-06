import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity, ShopCatalogueResponse, ShopReservation } from '@gymloop/shared';

// SHP-PAGE-006, SHP-PAGE-007, SHP-PAGE-008: real hook/cache, deferred public API.
const h = vi.hoisted(() => ({
  cursor: 0, slots: [] as unknown[], deps: [] as Array<readonly unknown[] | undefined>,
  effects: [] as Array<{ index: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>,
  identity: { kind: 'member', userId: 'shop-page-user', tenantId: 'shop-page-tenant', memberId: 'shop-page-member' } as GymloopIdentity,
  online: true, api: null as unknown, calls: [] as Array<{ api: unknown; path: string; body: unknown; resolve: (value: unknown) => void }>,
}));
vi.mock('react', async original => {
  const actual = await original<Record<string, unknown>>();
  const changed = (old?: readonly unknown[], next?: readonly unknown[]) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const hooks = {
    useState: (initial: unknown) => { const index = h.cursor++; const slots = h.slots; if (!(index in slots)) slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[index], (next: unknown) => { if (slots === h.slots) slots[index] = typeof next === 'function' ? (next as (value: unknown) => unknown)(slots[index]) : next; }]; },
    useRef: (initial: unknown) => { const index = h.cursor++; h.slots[index] ??= { current: initial }; return h.slots[index]; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.slots[index] = factory(); h.deps[index] = deps; } return h.slots[index]; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.slots[index] = callback; h.deps[index] = deps; } return h.slots[index]; },
    useEffect: (callback: () => unknown, deps?: readonly unknown[]) => { const index = h.cursor++; if (changed(h.deps[index], deps)) { h.deps[index] = deps; h.effects.push({ index, callback }); } },
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown> | undefined), ...hooks } };
});
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: h.api, ready: true, session: h.identity.kind === 'member' ? {} : null, supabase: {} }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));

type Pages = { view: null | { scope: string; response: ShopCatalogueResponse; savedAt: string; stale: boolean }; loading: boolean; loadingMore: boolean; error: string | null; visibleCount: number; hasMore: boolean; reload: () => Promise<void>; loadMore: () => Promise<void> };
let usePages: () => Pages;
let cache: typeof import('../shop-cache');
const scope = 'shop-page-user:shop-page-tenant:shop-page-member';
const id = (n: number) => `85000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const cursor = { createdAt: '2026-10-07T03:40:11.123456+00:00', id: id(100) };
const reservation = (n: number, state: ShopReservation['state'] = 'expired'): ShopReservation => ({ reservationId: id(n), itemId: id(1), itemName: `Private row ${n}`, section: 'products', quantity: 1, unitPricePaise: '9007199254740993', totalPaise: '9007199254740993', currency: 'INR', state, createdAt: '2026-10-06T00:00:00Z', expiresAt: '2026-10-07T00:00:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null });
const history = (start: number, length: number) => Array.from({ length }, (_, index) => reservation(start + index));
const initial = (rows: ShopReservation[] = history(100, 3), nextAfter: typeof cursor | null = cursor) => ({ ok: true, data: { mode: 'initial', items: [], reservations: rows, nextAfter, truncated: false, serverTime: '2026-10-07T03:40:12Z' } });
const more = (rows = history(200, 5), nextAfter: typeof cursor | null = null) => ({ ok: true, data: { mode: 'more', reservations: rows, nextAfter, serverTime: '2026-10-07T03:40:13Z' } });
function api() { const capability = { post: (path: string, body: unknown) => new Promise(resolve => { h.calls.push({ api: capability, path, body, resolve }); }) }; return capability; }
function draw(runEffects = true) {
  h.cursor = 0; const result = usePages();
  if (runEffects) { const effects = h.effects.splice(0); effects.forEach(({ index }) => { h.cleanups[index]?.(); h.cleanups[index] = undefined; }); effects.forEach(({ index, callback }) => { const cleanup = callback(); if (typeof cleanup === 'function') h.cleanups[index] = cleanup as () => void; }); }
  return result;
}
async function settle() { for (let tick = 0; tick < 40; tick++) await Promise.resolve(); return draw(); }
function unmount() { h.cleanups.forEach(cleanup => cleanup?.()); h.cursor = 0; h.slots = []; h.deps = []; h.effects = []; h.cleanups = []; }
function latest() { const call = h.calls.at(-1); if (!call) throw new Error('Expected observable Shop page request'); expect(call.path).toBe('/api/shop/catalogue/page'); return call; }
async function boot(result = initial()) { draw(); await settle(); expect(latest().body).toEqual({ mode: 'initial' }); latest().resolve(result); return settle(); }
async function cacheText(target = scope) { return JSON.stringify(await cache.readShopCache(cache.nativeShopCache, target)); }
beforeEach(async () => {
  unmount(); vi.resetModules(); h.identity = { kind: 'member', userId: 'shop-page-user', tenantId: 'shop-page-tenant', memberId: 'shop-page-member' }; h.online = true; h.calls = []; h.api = api();
  cache = await import('../shop-cache'); await cache.clearShopCache(cache.nativeShopCache);
  usePages = (await import('../use-member-shop-pages')).useMemberShopPages;
});
afterEach(unmount);

describe('SHP-PAGE native disclosure and caller lifetimes', () => {
  it('reveals three initially, then five cached rows without a continuation', async () => {
    const active = history(10, 5).map(row => ({ ...row, state: 'reserved' as const, expiresAt: '2099-10-07T00:00:00Z' }));
    const first = await boot(initial([...active, ...history(100, 3)]));
    expect(first.visibleCount).toBe(3); expect(first.view?.response.reservations.slice(0, 5).map(row => row.reservationId)).toEqual(active.map(row => row.reservationId)); expect(first.hasMore).toBe(true);
    await first.loadMore(); const revealed = await settle(); expect(revealed.visibleCount).toBe(8); expect(h.calls).toHaveLength(1); expect(revealed.hasMore).toBe(true);
    const operation = revealed.loadMore(); await settle(); expect(latest().body).toEqual({ mode: 'more', after: cursor }); latest().resolve(more()); await operation;
    const final = await settle(); expect(final.visibleCount).toBe(13); expect(final.hasMore).toBe(false); expect(final.view?.response.reservations).toHaveLength(13);
  });
  it('requests only one continuation for a tap and rejects same-turn repeated taps', async () => {
    const first = await boot(); const a = first.loadMore(); const b = first.loadMore(); const c = first.loadMore();
    await settle(); expect(h.calls).toHaveLength(2); expect(draw().loadingMore).toBe(true); expect(draw().visibleCount).toBe(3);
    latest().resolve(more(history(200, 5), { ...cursor, id: id(204) })); await Promise.all([a, b, c]);
    expect((await settle()).visibleCount).toBe(8); expect(h.calls).toHaveLength(2); expect(draw().hasMore).toBe(true);
  });
  it('combines fewer hidden cached rows with a single page to reveal no more than five', async () => {
    const active = history(10, 2).map(row => ({ ...row, state: 'reserved' as const, expiresAt: '2099-10-07T00:00:00Z' }));
    const first = await boot(initial([...active, ...history(100, 3)])); const operation = first.loadMore(); await settle(); latest().resolve(more()); await operation;
    const result = await settle(); expect(result.visibleCount).toBe(8); expect(result.view?.response.reservations).toHaveLength(10); expect(result.hasMore).toBe(true);
    await result.loadMore(); expect((await settle()).visibleCount).toBe(10); expect(h.calls).toHaveLength(2); expect(draw().hasMore).toBe(false);
  });
  it.each(['transient', 'malformed'] as const)('%s continuation keeps rows, count and precise cursor for retry', async kind => {
    const first = await boot(); const before = first.view; const operation = first.loadMore(); await settle();
    latest().resolve(kind === 'transient' ? { ok: false, status: 503, error: { code: 'network_failed', message: 'Try again' } } : { ok: true, data: { ...more().data, reservations: [{ ...reservation(200), totalPaise: 1 }] } });
    await operation; const failed = await settle(); expect(failed.view?.response).toEqual(before?.response); expect(failed.view?.stale).toBe(true); expect(failed.visibleCount).toBe(3); expect(failed.loadingMore).toBe(false); expect(failed.error).toEqual(expect.any(String)); expect(failed.hasMore).toBe(true);
    const retry = failed.loadMore(); await settle(); expect(latest().body).toEqual({ mode: 'more', after: cursor }); latest().resolve(more(history(200, 2))); await retry;
    expect((await settle()).visibleCount).toBe(5); expect(draw().hasMore).toBe(false); expect(draw().error).toBeNull(); expect(draw().view?.stale).toBe(true);
  });
  it('updates an existing active reservation ID when returned in history, preserving uniqueness', async () => {
    const active = { ...reservation(10), state: 'reserved' as const, expiresAt: '2099-10-07T00:00:00Z' };
    const first = await boot(initial([active, ...history(100, 2)])); const operation = first.loadMore(); await settle();
    latest().resolve(more([{ ...reservation(10), itemName: 'Now expired fact' }, ...history(200, 4)])); await operation;
    const rows = (await settle()).view?.response.reservations ?? []; expect(rows).toHaveLength(7); expect(new Set(rows.map(row => row.reservationId)).size).toBe(7);
    expect(rows.find(row => row.reservationId === id(10))).toMatchObject({ state: 'expired', itemName: 'Now expired fact' });
  });
  it('reload immediately invalidates old continuation, resets preview and protects newer busy guard', async () => {
    const first = await boot(); const oldOperation = first.loadMore(); await settle(); const old = latest();
    const refresh = draw().reload(); await settle(); expect(latest().body).toEqual({ mode: 'initial' }); latest().resolve(initial(history(300, 3))); await refresh;
    const fresh = await settle(); expect(fresh.visibleCount).toBe(3); const newestOperation = fresh.loadMore(); await settle(); const newest = latest();
    old.resolve(more(history(900, 5))); await oldOperation; await settle(); expect(draw().loadingMore).toBe(true); expect(draw().view?.response.reservations.map(row => row.reservationId)).toEqual(history(300, 3).map(row => row.reservationId));
    expect(await cacheText()).not.toContain('Private row 900'); newest.resolve(more(history(400, 5))); await newestOperation; expect((await settle()).visibleCount).toBe(8);
  });
  it.each(['userId', 'tenantId', 'memberId'] as const)('%s replacement revokes pending work before effects and retained callbacks', async key => {
    const first = await boot(); const operation = first.loadMore(); await settle(); const old = latest();
    h.identity = { kind: 'member', userId: 'shop-page-user', tenantId: 'shop-page-tenant', memberId: 'shop-page-member', [key]: 'replacement' };
    expect(draw(false).view).toBeNull(); const calls = h.calls.length; await first.loadMore(); expect(h.calls).toHaveLength(calls);
    old.resolve(more(history(900, 5))); await operation; await settle(); expect(draw().view).toBeNull(); expect(await cacheText()).not.toContain('Private row 900');
  });
  it('API capability replacement revokes an old response synchronously', async () => {
    const first = await boot(); const operation = first.loadMore(); await settle(); const old = latest();
    h.api = api(); draw(false); old.resolve(more(history(900, 5))); await operation; await settle();
    expect(draw().view?.response.reservations.some(row => row.reservationId === id(900))).not.toBe(true); expect(await cacheText()).not.toContain('Private row 900');
    expect(latest().api).toBe(h.api); expect(latest().body).toEqual({ mode: 'initial' });
  });
  it('unmount invalidates continuation in real cache and retained actions', async () => {
    const first = await boot(); const operation = first.loadMore(); await settle(); const old = latest(); unmount(); const calls = h.calls.length;
    await first.loadMore(); await first.reload(); expect(h.calls).toHaveLength(calls); old.resolve(more(history(900, 5))); await operation;
    expect(await cacheText()).not.toContain('Private row 900');
  });
  it('offline reload restores labelled last-good data and cached disclosure without a resumable cursor', async () => {
    const active = history(10, 5).map(row => ({ ...row, state: 'reserved' as const, expiresAt: '2099-10-07T00:00:00Z' }));
    await boot(initial([...active, ...history(100, 3)])); h.online = false; await draw().reload(); const offline = await settle();
    expect(offline.view?.stale).toBe(true); expect(offline.visibleCount).toBe(3); const calls = h.calls.length;
    await offline.loadMore(); const expanded = await settle(); expect(expanded.visibleCount).toBe(8); expect(h.calls).toHaveLength(calls); expect(expanded.hasMore).toBe(false);
    h.online = true; const retry = expanded.reload(); await settle(); latest().resolve(initial(history(300, 3))); await retry;
    expect((await settle()).view?.stale).toBe(false); expect(draw().visibleCount).toBe(3); expect(draw().hasMore).toBe(true);
  });
  it('offline continuation retains the live cursor for an explicit later retry', async () => {
    const first = await boot(); h.online = false; draw(); const calls = h.calls.length; await first.loadMore(); const failed = await settle();
    expect(h.calls).toHaveLength(calls); expect(failed.visibleCount).toBe(3); expect(failed.hasMore).toBe(true); expect(failed.error).toEqual(expect.any(String));
    h.online = true; const retry = draw().loadMore(); await settle(); expect(latest().body).toEqual({ mode: 'more', after: cursor }); latest().resolve(more()); await retry;
    expect((await settle()).visibleCount).toBe(8);
  });
  it.each(['not_signed_in', 'not_permitted', 'unauthorized', 'forbidden'])('%s refusal clears private cache and cannot be undone by offline reload', async code => {
    const first = await boot(); const operation = first.loadMore(); await settle(); latest().resolve({ ok: false, status: 403, error: { code, message: 'Access refused' } }); await operation;
    expect((await settle()).view).toBeNull(); expect(await cache.readShopCache(cache.nativeShopCache, scope)).toBeNull();
    h.online = false; await draw().reload(); expect((await settle()).view).toBeNull();
    h.online = true; const authorized = draw().reload(); await settle(); latest().resolve(initial(history(300, 3))); await authorized;
    expect((await settle()).view?.stale).toBe(false); expect(draw().view?.response.reservations[0]?.reservationId).toBe(id(300));
  });
  it('transient initial refresh keeps labelled last-good facts and offers retry', async () => {
    const first = await boot(); const refresh = first.reload(); await settle(); latest().resolve({ ok: false, status: 503, error: { code: 'network_failed', message: 'Retry' } }); await refresh;
    const failed = await settle(); expect(failed.view?.response).toEqual(first.view?.response); expect(failed.view?.stale).toBe(true); expect(failed.error).toEqual(expect.any(String)); expect(failed.visibleCount).toBe(3);
  });
});
