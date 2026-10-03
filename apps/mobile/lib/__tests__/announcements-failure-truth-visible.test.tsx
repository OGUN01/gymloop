// Independent approved failure-truth regressions; only platform boundaries mocked.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const test = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<{ slot: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>, deps: [] as Array<unknown[] | undefined>, calls: [] as Array<{ path: string; body: unknown; resolve: (value: unknown) => void }>, identity: { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }, offline: false }));
vi.mock('react', () => {
  const changed = (old: unknown[] | undefined, next: unknown[] | undefined) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const useState = (initial: unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[slot], (next: unknown) => { if (slots !== test.slots) return; slots[slot] = typeof next === 'function' ? (next as (old: unknown) => unknown)(slots[slot]) : next; }]; };
  return { useState, useRef: (initial: unknown) => useState({ current: initial })[0],
    useReducer: (reducer: (old: unknown, event: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = init ? init(initial) : initial; return [slots[slot], (event: unknown) => { if (slots === test.slots) slots[slot] = reducer(slots[slot], event); }]; },
    useCallback: (callback: unknown, deps: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.slots[slot] = callback; test.deps[slot] = deps; } return test.slots[slot]; },
    useEffect: (callback: () => unknown, deps?: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.deps[slot] = deps; test.effects.push({ slot, callback }); } },
  };
});
const disk = vi.hoisted(() => new Map<string, string>());
const storage = vi.hoisted(() => ({ read: vi.fn(), write: vi.fn(), remove: vi.fn() }));
const network = vi.hoisted(() => ({ probe: vi.fn() }));
const api = { post: (path: string, body: unknown) => new Promise((resolve) => { test.calls.push({ path, body, resolve }); }) };
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: test.identity, api, supabase: {} }) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: network.probe }));
vi.mock('expo-secure-store', () => ({ getItemAsync: storage.read, setItemAsync: storage.write, deleteItemAsync: storage.remove }));
const { ANNOUNCEMENT_CACHE_KEY, loadAnnouncementCache, saveAnnouncementCache, queueRead, discardAnnouncementCache } = await import('../announcements');
const { useAnnouncements } = await import('../use-announcements');
const render = () => {
  test.cursor = 0; const result = useAnnouncements();
  const effects = test.effects.splice(0);
  for (const { slot } of effects) { test.cleanups[slot]?.(); test.cleanups[slot] = undefined; }
  for (const { slot, callback } of effects) { const cleanup = callback(); if (typeof cleanup === 'function') test.cleanups[slot] = cleanup as () => void; }
  return result;
};
const unmount = () => { for (const cleanup of test.cleanups) cleanup?.(); test.cursor = 0; test.slots = []; test.effects = []; test.cleanups = []; test.deps = []; };
const settle = async () => { for (let step = 0; step < 40; step++) await Promise.resolve(); };
const id = '75000000-0000-4000-8000-000000000201';
const card = { announcementId: id, kind: 'transactional' as const, title: 'Scope private notice', body: 'Private body', imageUrl: null, versionNo: 2, publishedAt: '2026-10-02T00:00:00Z', editedAt: '2026-10-02T01:00:00Z', expiresAt: null, changeNote: 'Changed time', readState: 'updated' as const, readAt: '2026-10-02T00:30:00Z' };
const feed = (cards = [card]) => ({ ok: true, data: { asOf: '2026-10-02T01:30:00Z', announcements: cards } });
const request = (path: string, index = 0) => { const found = test.calls.filter(call => call.path === path)[index]; if (!found) throw new Error('Expected observable API request'); return found; };
const path = '/api/member/announcements/feed';
beforeEach(() => { unmount(); disk.clear(); network.probe.mockReset().mockResolvedValue({ isConnected: true, isInternetReachable: true }); storage.read.mockReset().mockImplementation(async (key: string) => disk.get(key) ?? null); storage.write.mockReset().mockImplementation(async (key: string, value: string) => { disk.set(key, value); }); storage.remove.mockReset().mockImplementation(async (key: string) => { disk.delete(key); }); test.calls = []; test.identity = { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }; });
afterEach(unmount);

const scope = () => ({ tenantId: test.identity.tenantId, userId: test.identity.userId, memberId: test.identity.memberId });
const cached = () => ({ scope: scope(), fetchedAt: '2026-10-02T01:30:00Z', announcements: [card], pendingReads: [] as Array<{ announcementId: string; versionNo: number }> });
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
describe('ANC real native hook permission and failure truth', () => {
  it.each([[401, 'not_signed_in'], [403, 'not_permitted']] as const)('removes current cached cards/pending receipts and retained acknowledgements on %s %s', async (status, code) => {
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify({ ...cached(), pendingReads: [{ announcementId: id, versionNo: 2 }] }));
    const retained = render(); await settle();
    request(path).resolve({ ok: false, status, error: { code, message: 'PRIVATE token/member/body' } });
    await settle(); const refused = render();
    expect(refused.cards).toEqual([]); expect(refused.stale).toBe(false);
    expect(refused.error).toEqual(expect.any(String)); expect(refused.error).not.toMatch(/PRIVATE|offline|back online/i);
    expect(await loadAnnouncementCache(scope())).toBeNull();
    const calls = test.calls.length;
    const oldRead = retained.markRead(id, 2); const refusedRead = refused.markRead(id, 2); await settle();
    expect(test.calls).toHaveLength(calls);
    await Promise.all([oldRead, refusedRead]);
    expect(await loadAnnouncementCache(scope())).toBeNull();
  });

  it.each(['server error', 'malformed feed', 'unknown network'] as const)('keeps only same-scope saved cards/time with truthful retry on %s', async failure => {
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cached()));
    if (failure === 'unknown network') network.probe.mockResolvedValue({ isConnected: null, isInternetReachable: null });
    render(); await settle();
    request(path).resolve(failure === 'malformed feed' ? { ok: true, data: { private: 'PRIVATE' } } :
      { ok: false, status: 500, error: { code: 'announcement_failed', message: 'PRIVATE token/body' } });
    await settle(); const result = render();
    expect(result.cards).toEqual([card]); expect(result.stale).toBe(true); expect(result.fetchedAt).toBe(cached().fetchedAt);
    expect(result.error).toEqual(expect.any(String));
    expect(result.error).toMatch(/try again|retry|reload|refresh/i);
    expect(result.error).not.toMatch(/offline|back online|PRIVATE/i);
  });

  it('uses offline wording only with actual disconnected connectivity evidence', async () => {
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cached()));
    network.probe.mockResolvedValue({ isConnected: false, isInternetReachable: false });
    render(); await settle();
    const currentRequest = test.calls.find(call => call.path === path);
    currentRequest?.resolve({ ok: false, status: 500, error: { code: 'network_error', message: 'PRIVATE' } });
    await settle(); const result = render();
    expect(network.probe).toHaveBeenCalled();
    expect(result.cards).toEqual([card]); expect(result.stale).toBe(true); expect(result.fetchedAt).toBe(cached().fetchedAt);
    expect(result.error).toMatch(/offline|back online/i); expect(result.error).not.toContain('PRIVATE');
  });

  it('a late old-scope permission refusal cannot delete or hide the newly successful scope', async () => {
    render(); await settle(); const original = request(path);
    test.identity = { ...test.identity, userId: '75000000-0000-4000-8000-000000000999', memberId: '75000000-0000-4000-8000-000000000998' };
    render(); await settle(); const replacementCard = { ...card, title: 'Replacement caller card' };
    request(path, 1).resolve(feed([replacementCard])); await settle(); render();
    original.resolve({ ok: false, status: 403, error: { code: 'not_permitted', message: 'PRIVATE' } }); await settle();
    expect(render().cards).toEqual([replacementCard]); expect(render().error).toBeFalsy();
    expect((await loadAnnouncementCache(scope()))?.announcements).toEqual([replacementCard]);
    await queueRead(scope(), id, 2);
    expect((await loadAnnouncementCache(scope()))?.pendingReads).toContainEqual({ announcementId: id, versionNo: 2 });
  });
});

describe('ANC actual exact-scope discard serialized persistence', () => {
  it('removes matching cards and pending reads while preserving a foreign complete scope', async () => {
    const originalScope = scope();
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify({ ...cached(), pendingReads: [{ announcementId: id, versionNo: 2 }] }));
    await discardAnnouncementCache(originalScope, () => true);
    expect(await loadAnnouncementCache(originalScope)).toBeNull();
    const replacement = { ...cached(), scope: { ...originalScope, userId: 'replacement' } };
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(replacement));
    await discardAnnouncementCache(originalScope, () => true);
    expect(await loadAnnouncementCache(replacement.scope)).toEqual(replacement);
  });

  it('rechecks permanent lifetime after an awaited storage read without globally revoking a new scope', async () => {
    const original = cached(); disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(original));
    const waiting = deferred<string | null>(); storage.read.mockReturnValueOnce(waiting.promise);
    let current = true;
    const operation = discardAnnouncementCache(original.scope, () => current);
    await settle();
    const replacement = { ...cached(), scope: { ...original.scope, memberId: 'replacement' } };
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(replacement)); current = false;
    waiting.resolve(JSON.stringify(original)); await operation;
    expect(await loadAnnouncementCache(replacement.scope)).toEqual(replacement);
    await queueRead(replacement.scope, id, 2);
    expect((await loadAnnouncementCache(replacement.scope))?.pendingReads).toContainEqual({ announcementId: id, versionNo: 2 });
  });

  it('orders refusal deletion after already-running and queued old-scope writes so they cannot restore it', async () => {
    expect(discardAnnouncementCache).toBeTypeOf('function');
    const waiting = deferred<void>();
    storage.write.mockImplementationOnce(async (key: string, value: string) => { await waiting.promise; disk.set(key, value); });
    const save = saveAnnouncementCache(cached(), () => true); await settle();
    expect(storage.write).toHaveBeenCalledTimes(1);
    const receipt = queueRead(scope(), id, 2, () => true);
    const discard = discardAnnouncementCache(scope(), () => true); await settle();
    waiting.resolve(); await Promise.all([save, receipt, discard]);
    expect(await loadAnnouncementCache(scope())).toBeNull();
  });
});
