import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { CachedFeed, AnnouncementScope } from '../../apps/mobile/lib/announcements';
import type { ShopCacheStore } from '../../apps/mobile/lib/shop-cache';
const storage = vi.hoisted(() => ({ values: new Map<string, string>(), pause: null as null | (() => Promise<void>) }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(async (key: string) => storage.values.get(key) ?? null),
  setItemAsync: vi.fn(async (key: string, value: string) => { const pause = storage.pause; storage.pause = null; if (pause) await pause(); storage.values.set(key, value); }),
  deleteItemAsync: vi.fn(async (key: string) => { storage.values.delete(key); }),
}));
import * as announcementModule from '../../apps/mobile/lib/announcements';
const announcements = announcementModule as typeof announcementModule & { clearAnnouncementCache: () => Promise<void> };
import { clearShopCache, readShopCache, writeShopCache } from '../../apps/mobile/lib/shop-cache';
function deferred() { let resolve!: () => void; const promise = new Promise<void>((done) => { resolve = done; }); return { promise, resolve }; }
const owner: AnnouncementScope = { tenantId: '10000000-0000-4000-8000-000000000001', userId: '20000000-0000-4000-8000-000000000001', memberId: '30000000-0000-4000-8000-000000000001' };
const nextOwner: AnnouncementScope = { ...owner, userId: '20000000-0000-4000-8000-000000000002', memberId: '30000000-0000-4000-8000-000000000002' };
const feed = (scope = owner): CachedFeed => ({ scope, fetchedAt: '2026-10-03T10:00:00+05:30', announcements: [{ announcementId: '40000000-0000-4000-8000-000000000001', kind: 'transactional', title: 'Private reminder', body: 'Your renewal is due.', imageUrl: null, versionNo: 1, publishedAt: '2026-10-03T09:00:00+05:30', editedAt: null, expiresAt: null, changeNote: null, readState: 'unread', readAt: null }], pendingReads: [] });
beforeEach(() => { storage.values.clear(); storage.pause = null; vi.clearAllMocks(); });
describe('independent private cache lifetime', () => {
  it('deletes a physically late announcement writer and permits fresh owner data', async () => {
    expect(announcements.clearAnnouncementCache).toBeTypeOf('function'); const gate = deferred(); const entered = deferred(); storage.pause = () => { entered.resolve(); return gate.promise; };
    const writing = announcements.saveAnnouncementCache(feed()); await entered.promise;
    const clearing = announcements.clearAnnouncementCache(); gate.resolve(); await Promise.all([writing, clearing]);
    expect(await announcements.loadAnnouncementCache(owner)).toBeNull();
    await announcements.saveAnnouncementCache(feed(nextOwner));
    expect(await announcements.loadAnnouncementCache(nextOwner)).toEqual(feed(nextOwner));
    expect(await announcements.loadAnnouncementCache(owner)).toBeNull();
  });
  it('does not resurrect a pending queue receipt after clear', async () => {
    await announcements.saveAnnouncementCache(feed());
    expect(announcements.clearAnnouncementCache).toBeTypeOf('function'); const gate = deferred(); const entered = deferred(); storage.pause = () => { entered.resolve(); return gate.promise; };
    const queuing = announcements.queueRead(owner, feed().announcements[0]!.announcementId, 1); await entered.promise;
    const clearing = announcements.clearAnnouncementCache(); gate.resolve(); await Promise.all([queuing, clearing]);
    expect(await announcements.loadAnnouncementCache(owner)).toBeNull();
  });
  it('ignores a suspended receipt response after clear and new scope save', async () => {
    expect(announcements.clearAnnouncementCache).toBeTypeOf('function'); await announcements.saveAnnouncementCache(feed()); await announcements.queueRead(owner, feed().announcements[0]!.announcementId, 1);
    const gate = deferred(); const entered = deferred();
    const api = { checkIn: vi.fn(), post: async <T,>() => { entered.resolve(); await gate.promise; return { ok: true as const, data: {} as T }; } };
    const flushing = announcements.flushPendingReads(api, owner); await entered.promise;
    await announcements.clearAnnouncementCache(); await announcements.saveAnnouncementCache(feed(nextOwner)); gate.resolve(); await flushing;
    expect(await announcements.loadAnnouncementCache(owner)).toBeNull(); expect(await announcements.loadAnnouncementCache(nextOwner)).toEqual(feed(nextOwner));
  });
  it('clears an old Shop write that completes physically after clear starts', async () => {
    const values = new Map<string, string>(); const entered = deferred(); const gate = deferred(); let paused = true;
    const store: ShopCacheStore = { get: async (key) => values.get(key) ?? null, set: async (key, value) => { if (paused) { paused = false; entered.resolve(); await gate.promise; } values.set(key, value); }, remove: async (key) => { values.delete(key); } };
    const catalogue = { items: [], reservations: [], truncated: false, serverTime: '2026-10-03T10:00:00+05:30' };
    const writing = writeShopCache(store, 'owner-a', catalogue); await entered.promise;
    const clearing = clearShopCache(store); gate.resolve(); await Promise.all([writing, clearing]);
    expect(await readShopCache(store, 'owner-a')).toBeNull(); await writeShopCache(store, 'owner-b', catalogue); expect(await readShopCache(store, 'owner-b')).not.toBeNull();
  });
  it('preserves a genuine same-owner offline feed with complete scope matching', async () => {
    await announcements.saveAnnouncementCache(feed()); const cached = await announcements.loadAnnouncementCache(owner);
    expect(announcements.resolveAnnouncementFeed({ fetched: null, cached, scope: owner }).cards).toEqual(feed().announcements);
    expect(announcements.resolveAnnouncementFeed({ fetched: null, cached, scope: nextOwner }).cards).toEqual([]);
  });
});
