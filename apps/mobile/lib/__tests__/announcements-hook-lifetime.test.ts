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
const api = { post: (path: string, body: unknown) => new Promise((resolve) => { test.calls.push({ path, body, resolve }); }) };
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: test.identity, api, supabase: {} }) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async (key: string) => disk.get(key) ?? null, setItemAsync: async (key: string, value: string) => { disk.set(key, value); }, deleteItemAsync: async (key: string) => { disk.delete(key); } }));
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
beforeEach(() => { unmount(); disk.clear(); test.calls = []; test.identity = { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }; });
afterEach(unmount);
describe('ANC scope and exact-version hook lifetimes', () => {
  it.each(['tenantId', 'userId', 'memberId'] as const)('%s transition hides cards immediately and revokes retained callbacks', async (key) => {
    render(); await settle(); request(path).resolve(feed()); await settle();
    const previous = render(); expect(previous.cards).toHaveLength(1);
    test.identity = { ...test.identity, [key]: '75000000-0000-4000-8000-000000000999' };
    expect(render().cards).toEqual([]); await settle();
    const calls = test.calls.length;
    const read = previous.markRead(id, 2); const reload = previous.reload(); await settle();
    expect(test.calls).toHaveLength(calls); expect(render().cards).toEqual([]);
    request(path, 1).resolve(feed([])); await settle(); await Promise.all([read, reload]);
    expect(render().cards).toEqual([]);
  });
  it('unmounted retained work cannot mutate a replacement mount or make old requests', async () => {
    const previous = render(); await settle(); const old = request(path);
    unmount(); render(); await settle(); const calls = test.calls.length;
    const reload = previous.reload(); const read = previous.markRead(id, 2); await settle();
    expect(test.calls).toHaveLength(calls);
    old.resolve(feed()); await settle(); expect(render().cards).toEqual([]);
    request(path, 1).resolve(feed([])); await settle(); await Promise.all([read, reload]); expect(render().cards).toEqual([]);
  });
  it.each(['false', '404'] as const)('%s read acknowledgement cannot leave phantom read state', async (outcome) => {
    render(); await settle(); request(path).resolve(feed()); await settle();
    const operation = render().markRead(id, 2); await settle();
    request(`/api/member/announcements/${id}/read`).resolve(outcome === 'false' ? { ok: true, data: { recorded: false } } : { ok: false, status: 404, error: { code: 'announcement_not_found', message: 'Unavailable' } });
    await operation; await settle(); expect(render().cards.find(value => value.announcementId === id)?.readState).not.toBe('read');
  });
  it('successful authoritative refresh reconciles an optimistic receipt against the exact version', async () => {
    render(); await settle(); request(path).resolve(feed()); await settle();
    const operation = render().markRead(id, 2); await settle();
    request(`/api/member/announcements/${id}/read`).resolve({ ok: true, data: { recorded: true } }); await operation; await settle();
    const reload = render().reload(); await settle();
    request(path, 1).resolve(feed([{ ...card, versionNo: 3 }])); await reload; await settle();
    expect(render().cards[0]?.versionNo).toBe(3); expect(render().cards[0]?.readState).toBe('updated');
  });
});
