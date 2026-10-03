import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { CachedFeed } from '../announcements';
import * as announcementModule from '../announcements';
const announcements = announcementModule as typeof announcementModule & { clearAnnouncementCache: () => Promise<void> };
import { clearShopCache, createMemoryShopCache, readShopCache, shopCacheCurrent, writeShopCache } from '../shop-cache';

const storage = vi.hoisted(() => ({ values: new Map<string, string>(), pause: null as null | (() => Promise<void>) }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(async (key: string) => storage.values.get(key) ?? null),
  setItemAsync: vi.fn(async (key: string, value: string) => { await storage.pause?.(); storage.values.set(key, value); }),
  deleteItemAsync: vi.fn(async (key: string) => { storage.values.delete(key); }),
}));
const scope = { tenantId: '10000000-0000-4000-8000-000000000001', userId: '20000000-0000-4000-8000-000000000001', memberId: '30000000-0000-4000-8000-000000000001' };
const feed: CachedFeed = { scope, fetchedAt: '2026-10-03T10:00:00+05:30', announcements: [{ announcementId: '40000000-0000-4000-8000-000000000001', kind: 'transactional', title: 'Class update', body: 'Class begins this evening.', imageUrl: null, versionNo: 1, publishedAt: '2026-10-03T09:00:00+05:30', editedAt: null, expiresAt: null, changeNote: null, readState: 'unread', readAt: null }], pendingReads: [] };
function deferred() { let resolve!: () => void; const promise = new Promise<void>((done) => { resolve = done; }); return { promise, resolve }; }
async function turns() { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); }
describe('native private cache integration contract', () => {
  beforeEach(() => { storage.values.clear(); storage.pause = null; });
  it('failed Shop deletion remains retryable and fresh writes work after successful cleanup', async () => {
    const values = new Map<string, string>();
    let failRemoval = true;
    const store = {
      get: async (key: string) => values.get(key) ?? null,
      set: async (key: string, value: string) => { values.set(key, value); },
      remove: async (key: string) => { if (failRemoval) throw new Error('Private Shop removal failed'); values.delete(key); },
    };
    const catalogue = { items: [], reservations: [], truncated: false, serverTime: feed.fetchedAt };
    await writeShopCache(store, scope.memberId, catalogue);
    expect(values.size).toBeGreaterThan(0);
    await expect(clearShopCache(store)).rejects.toThrow();
    expect(values.size).toBeGreaterThan(0);
    failRemoval = false;
    await clearShopCache(store);
    expect(values.size).toBe(0);
    expect(await readShopCache(store, scope.memberId)).toBeNull();
    await writeShopCache(store, scope.memberId, catalogue);
    expect(await readShopCache(store, scope.memberId)).not.toBeNull();
    const replacement = '30000000-0000-4000-8000-000000000002';
    await writeShopCache(store, replacement, catalogue);
    expect(await readShopCache(store, replacement)).not.toBeNull();
  });
  it('Shop clear revokes its preceding lease synchronously and permits fresh work', async () => {
    const store = createMemoryShopCache(); const old = shopCacheCurrent(store);
    await writeShopCache(store, scope.memberId, { items: [], reservations: [], truncated: false, serverTime: feed.fetchedAt });
    const clearing = clearShopCache(store);
    expect(old()).toBe(false);
    await clearing;
    expect(await readShopCache(store, scope.memberId)).toBeNull();
    await writeShopCache(store, scope.memberId, { items: [], reservations: [], truncated: false, serverTime: feed.fetchedAt });
    expect(await readShopCache(store, scope.memberId)).not.toBeNull();
  });
  it('serialized announcement clear defeats an already paused old write, then admits fresh saves', async () => {
    expect(announcements.clearAnnouncementCache).toBeTypeOf('function');
    const entered = deferred(); const release = deferred();
    storage.pause = async () => { entered.resolve(); await release.promise; };
    const writing = announcements.saveAnnouncementCache(feed);
    await entered.promise;
    const clearing = announcements.clearAnnouncementCache();
    release.resolve(); await Promise.all([writing, clearing]); storage.pause = null;
    expect(await announcements.loadAnnouncementCache(scope)).toBeNull();
    await announcements.saveAnnouncementCache(feed);
    expect(await announcements.loadAnnouncementCache(scope)).toEqual(feed);
  });
  it('an old receipt continuation cannot restore cards or read queue after clear', async () => {
    expect(announcements.clearAnnouncementCache).toBeTypeOf('function');
    await announcements.saveAnnouncementCache({ ...feed, pendingReads: [{ announcementId: feed.announcements[0]!.announcementId, versionNo: 1 }] });
    const receipt = deferred(); const entered = deferred();
    const api = { post: async <T,>() => { entered.resolve(); await receipt.promise; return { ok: true as const, data: {} as T }; }, checkIn: vi.fn() };
    const flushing = announcements.flushPendingReads(api, scope);
    await entered.promise; await announcements.clearAnnouncementCache(); receipt.resolve(); await flushing; await turns();
    expect(await announcements.loadAnnouncementCache(scope)).toBeNull();
  });
  it('complete same-owner cached feed survives offline resolution; another owner never receives it', async () => {
    await announcements.saveAnnouncementCache(feed);
    const cached = await announcements.loadAnnouncementCache(scope);
    expect(announcements.resolveAnnouncementFeed({ fetched: null, cached, scope }).cards).toEqual(feed.announcements);
    expect(await announcements.loadAnnouncementCache({ ...scope, userId: '20000000-0000-4000-8000-000000000002' })).toBeNull();
  });
});
